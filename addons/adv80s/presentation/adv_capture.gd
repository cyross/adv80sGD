class_name AdvCapture
extends Node
## 画面の写真（スクリーンショット）と録画（段階68）。
## 写すのは grab（source → Image）が返す画像。プレイヤーが「窓の全体」か「元の解像度の画面」を渡す。
## 録画は、決まった速さ（fps）でコマを取り、JPEG にして AVI（AdvAviWriter）に書く。
## JPEG にしてファイルに書くのは別のスレッドで行い、ゲームの動きを止めないようにする。
## 音はマスターのバスに AudioEffectCapture を足して取る（録画しているあいだだけ）。

signal recording_stopped(path: String, reason: String)

## モダン機能 screenshot の options の既定値
const SHOT_DEFAULTS := {
	"key": "F7", "source": "window", "scale": 1.0, "folder": "user://screenshots", "prefix": "screenshot",
	"notice": true, "menu": true,
}
## モダン機能 recording の options の既定値
const REC_DEFAULTS := {
	"key": "F10", "source": "window", "scale": 1.0, "folder": "user://recordings", "prefix": "recording",
	"notice": true, "menu": true, "fps": 30, "quality": 0.85, "audio": true, "max_seconds": 600, "indicator": "title",
}
const MAX_BYTES := 1900 * 1024 * 1024   ## 1 つのファイルの上限（AVI は 4 GB まで。手前で止める）
const MAX_BACKLOG_SECONDS := 1.0         ## JPEG にするのが追いつかないとき、これより溜まったらコマを前のコマで代える

var last_error := ""          ## 撮れなかった・始められなかった理由
var last_info: Dictionary = {}   ## 最後に止めた録画の {path, frames, seconds, bytes}

var _grab: Callable
var _conf: Dictionary = {}
var _writer: AdvAviWriter = null
var _thread: Thread = null
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _queue: Array = []
var _pending_video := 0
var _t0 := 0
var _queued_frames := 0
var _cap: AudioEffectCapture = null
var _w := 0
var _h := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## options に既定値を重ねる（kind は "screenshot" か "recording"）。
static func options_for(kind: String, opts: Variant) -> Dictionary:
	var d: Dictionary = (REC_DEFAULTS if kind == "recording" else SHOT_DEFAULTS).duplicate()
	if opts is Dictionary:
		for k in opts:
			d[k] = opts[k]
	return d


## options の key（"F7" など）のキーコード。読めなければ既定のキー。
static func keycode_of(kind: String, opts: Dictionary) -> Key:
	var k := OS.find_keycode_from_string(String(opts.get("key", "")))
	if k == KEY_NONE:
		k = OS.find_keycode_from_string(String((REC_DEFAULTS if kind == "recording" else SHOT_DEFAULTS)["key"]))
	return k


## 保存するファイルのパス（folder/prefix_年月日_時分秒.ext。同じ名前があれば _2、_3…）。フォルダも作る。
static func make_path(folder: String, prefix: String, ext: String, now: Dictionary = {}) -> String:
	if folder == "":
		folder = "user://"
	DirAccess.make_dir_recursive_absolute(folder)
	var t: Dictionary = now if not now.is_empty() else Time.get_datetime_dict_from_system()
	var safe := prefix
	for c in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		safe = safe.replace(c, "_")
	if safe == "":
		safe = "capture"
	var base := "%s/%s_%04d%02d%02d_%02d%02d%02d" % [folder.trim_suffix("/"), safe,
		int(t.get("year", 0)), int(t.get("month", 0)), int(t.get("day", 0)),
		int(t.get("hour", 0)), int(t.get("minute", 0)), int(t.get("second", 0))]
	var p := "%s.%s" % [base, ext]
	var n := 2
	while FileAccess.file_exists(p):
		p = "%s_%d.%s" % [base, n, ext]
		n += 1
	return p


## 倍率をかける（1 より大きいときは点のまま拡大、小さいときはなめらかに縮める）。even なら幅と高さを偶数にする。
static func scaled(img: Image, scale: float, even: bool = false) -> Image:
	if img == null or img.is_empty():
		return img
	var w := maxi(1, int(round(img.get_width() * scale)))
	var h := maxi(1, int(round(img.get_height() * scale)))
	if even:
		w = maxi(2, w - w % 2)
		h = maxi(2, h - h % 2)
	if w != img.get_width() or h != img.get_height():
		img.resize(w, h, Image.INTERPOLATE_NEAREST if scale >= 1.0 else Image.INTERPOLATE_BILINEAR)
	return img


# ---------------------------------------------------------------- 写真

## 画像を PNG で保存する。保存したパス（だめなら "" で、理由は last_error）。
func save_screenshot(img: Image, opts: Dictionary) -> String:
	last_error = ""
	if img == null or img.is_empty():
		last_error = "NO_IMAGE"
		return ""
	img = scaled(img, maxf(0.05, float(opts.get("scale", 1.0))))
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var p := make_path(String(opts.get("folder", SHOT_DEFAULTS["folder"])), String(opts.get("prefix", "screenshot")), "png")
	var err := img.save_png(p)
	if err != OK:
		last_error = "WRITE:%s" % error_string(err)
		return ""
	return p


# ---------------------------------------------------------------- 録画

func is_recording() -> bool:
	return _writer != null


## 録画しているパス（していなければ ""）。
func recording_path() -> String:
	return _writer.path if _writer != null else ""


## 録画を始めてからの秒数。
func recording_seconds() -> float:
	return (Time.get_ticks_usec() - _t0) / 1000000.0 if _writer != null else 0.0


## 録画を始める。grab は source（"window"・"screen"）を受けて Image を返す。始めたファイルのパス（だめなら ""）。
func start_recording(opts: Dictionary, grab: Callable) -> String:
	last_error = ""
	if _writer != null:
		last_error = "ALREADY"
		return ""
	_conf = opts.duplicate()
	_grab = grab
	var first := _grab_frame()
	if first == null:
		last_error = "NO_IMAGE"
		return ""
	_w = first.get_width()
	_h = first.get_height()
	var fps := clampi(int(_conf.get("fps", 30)), 1, 60)
	_conf["fps"] = fps
	var rate := int(AudioServer.get_mix_rate()) if bool(_conf.get("audio", true)) else 0
	var p := make_path(String(_conf.get("folder", REC_DEFAULTS["folder"])), String(_conf.get("prefix", "recording")), "avi")
	var w := AdvAviWriter.new()
	var err := w.open(p, _w, _h, fps, rate)
	if err != OK:
		last_error = "WRITE:%s" % error_string(err)
		return ""
	_writer = w
	_queue.clear()
	_pending_video = 0
	if rate > 0:
		_cap = AudioEffectCapture.new()
		_cap.buffer_length = 1.0
		AudioServer.add_bus_effect(0, _cap)
		_cap.clear_buffer()
	_thread = Thread.new()
	_thread.start(_work)
	_t0 = Time.get_ticks_usec()
	_queued_frames = 0
	_push_video(first)
	return p


## 録画を止めてファイルを閉じる。閉じたパス（録画していなければ ""）。reason は recording_stopped に渡す。
func stop_recording(reason: String = "stop") -> String:
	if _writer == null:
		return ""
	if _cap != null:
		_take_audio()
		for i in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, i) == _cap:
				AudioServer.remove_bus_effect(0, i)
				break
		_cap = null
	_push({"end": true})
	_thread.wait_to_finish()
	_thread = null
	last_info = _writer.close()
	var p := _writer.path
	_writer = null
	_grab = Callable()
	recording_stopped.emit(p, reason)
	return p


func _process(_delta: float) -> void:
	if _writer == null:
		return
	var fps := int(_conf["fps"])
	var elapsed := recording_seconds()
	var max_s := float(_conf.get("max_seconds", 0))
	if max_s > 0.0 and elapsed >= max_s:
		stop_recording("max_seconds")
		return
	_mutex.lock()
	var bytes := _writer.size()
	_mutex.unlock()
	if bytes >= MAX_BYTES:
		stop_recording("max_size")
		return
	var want := int(elapsed * fps) + 1
	if want > _queued_frames:
		_push_video(_grab_frame())
		# 遅れた分は前のコマで埋める（音とずれないように）
		while _queued_frames < want:
			_push({"repeat": true})
			_queued_frames += 1
	if _cap != null:
		_take_audio()


func _exit_tree() -> void:
	stop_recording("exit")


func _grab_frame() -> Image:
	if not _grab.is_valid():
		return null
	var img = _grab.call(String(_conf.get("source", "window")))
	if not img is Image or (img as Image).is_empty():
		return null
	return scaled(img, maxf(0.05, float(_conf.get("scale", 1.0))), true)


func _push_video(img: Image) -> void:
	_queued_frames += 1
	_mutex.lock()
	var backlog := _pending_video
	_mutex.unlock()
	if img == null or backlog > int(float(_conf["fps"]) * MAX_BACKLOG_SECONDS):
		_push({"repeat": true})
		return
	_mutex.lock()
	_pending_video += 1
	_mutex.unlock()
	_push({"image": img})


func _take_audio() -> void:
	var n := _cap.get_frames_available()
	if n > 0:
		_push({"audio": _cap.get_buffer(n)})


func _push(item: Dictionary) -> void:
	_mutex.lock()
	_queue.append(item)
	_mutex.unlock()
	_sem.post()


## 別のスレッド：JPEG にして書く。
func _work() -> void:
	var q := float(_conf.get("quality", 0.85))
	while true:
		_sem.wait()
		_mutex.lock()
		var item: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_mutex.unlock()
		if item.has("end"):
			break
		if item.has("image"):
			var img: Image = item["image"]
			if img.get_width() != _w or img.get_height() != _h:
				img.resize(_w, _h, Image.INTERPOLATE_BILINEAR)   # 録画中に窓の大きさが変わったとき
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
			var jpg := img.save_jpg_to_buffer(clampf(q, 0.05, 1.0))
			_mutex.lock()
			_writer.add_video(jpg)
			_pending_video -= 1
			_mutex.unlock()
		elif item.has("repeat"):
			_mutex.lock()
			_writer.repeat_video()
			_mutex.unlock()
		elif item.has("audio"):
			var pcm := AdvAviWriter.pcm16(item["audio"])
			_mutex.lock()
			_writer.add_audio(pcm)
			_mutex.unlock()
