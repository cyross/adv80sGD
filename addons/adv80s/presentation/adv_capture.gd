class_name AdvCapture
extends Node
## 画面の写真（スクリーンショット）と録画（段階68・69）。
## 写すのは grab（source → Image）が返す画像。プレイヤーが「窓の全体」か「元の解像度の画面」を渡す。
## 録画は、決まった速さ（fps）でコマを取り、書き出し（AdvVideoEncoder）に渡す。
## 書き出しは別のスレッドで行い、ゲームの動きを止めないようにする。
## 音はマスターのバスに AudioEffectCapture を足して取る（録画しているあいだだけ）。
## 書き出しは options.format で選ぶ。本体は AVI だけを持つ。"mp4" は、登録した書き出し（register_encoder）があればそれ、
## なければパソコンで ffmpeg が見つかれば、AVI で録ってから MP4 に変える（AdvFfmpeg）。どちらもだめなら AVI のまま。

signal recording_stopped(path: String, reason: String)
## MP4 などに変え終えた。ok なら path は変えたファイル、だめなら残した AVI。
signal converted(path: String, ok: bool)

## モダン機能 screenshot の options の既定値
const SHOT_DEFAULTS := {
	"key": "F7", "source": "window", "scale": 1.0, "folder": "user://screenshots", "prefix": "screenshot",
	"notice": true, "menu": true,
}
## モダン機能 recording の options の既定値
const REC_DEFAULTS := {
	"key": "F10", "source": "window", "scale": 1.0, "folder": "user://recordings", "prefix": "recording",
	"notice": true, "menu": true, "fps": 30, "quality": 0.85, "audio": true, "max_seconds": 600, "indicator": "title",
	"format": "avi", "ffmpeg": "", "ffmpeg_args": [], "keep_avi": false,
}
const MAX_BYTES := 1900 * 1024 * 1024   ## 1 つのファイルの上限（AVI は 4 GB まで。手前で止める）
const MAX_BACKLOG_SECONDS := 1.0         ## 書き出しが追いつかないとき、これより溜まったらコマを前のコマで代える

## 登録した書き出し（形式 → 作る Callable。AdvVideoEncoder を返す）
static var _encoders: Dictionary = {}

var last_error := ""          ## 撮れなかった・始められなかった理由
var last_note := ""           ## 録画を始めたときの知らせ（NO_MP4：MP4 にできないので AVI、NO_ENCODER：その形式がないので AVI）
var last_info: Dictionary = {}   ## 最後に止めた録画の {path, frames, seconds, bytes, format}

var _grab: Callable
var _conf: Dictionary = {}
var _enc: AdvVideoEncoder = null
var _path := ""
var _thread: Thread = null
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _opened := Semaphore.new()
var _open_err: Error = OK
var _queue: Array = []
var _pending_video := 0
var _bytes := 0
var _t0 := 0
var _queued_frames := 0
var _cap: AudioEffectCapture = null
var _w := 0
var _h := 0
var _convert: Dictionary = {}      ## 録り終えたら変えるもの {ffmpeg, encoder}
var _converts: Array = []          ## 変えている途中 [{pid, src, dst, keep}]


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


# ---------------------------------------------------------------- 書き出しの受け口

## 録画の書き出しを登録する（差し込み部品から呼ぶ）。factory は AdvVideoEncoder を返す Callable。
## 空の Callable を渡すと登録を外す。
static func register_encoder(format: String, factory: Callable) -> void:
	if factory.is_valid():
		_encoders[format.to_lower()] = factory
	else:
		_encoders.erase(format.to_lower())


## 登録した書き出しの形式の一覧。
static func encoder_formats() -> Array:
	return _encoders.keys()


## その形式の書き出しを作る（登録がない、この環境で使えないなら null）。"avi" はいつも本体のもの。
static func make_encoder(format: String) -> AdvVideoEncoder:
	var f := format.to_lower()
	if f == "avi" or f == "":
		return AdvAviEncoder.new()
	if not _encoders.has(f):
		return null
	var e = (_encoders[f] as Callable).call()
	return e if e is AdvVideoEncoder and (e as AdvVideoEncoder).is_available() else null


## options の format で録ると、どうなるか。{format: 書き出す形式, encoder: "avi" か登録した形式, convert: 変える形式 or "", ffmpeg: パス, note}
static func plan(opts: Dictionary) -> Dictionary:
	var fmt := String(opts.get("format", "avi")).to_lower()
	if fmt == "" or fmt == "avi":
		return {"format": "avi", "encoder": "avi", "convert": "", "ffmpeg": "", "note": ""}
	if make_encoder(fmt) != null:
		return {"format": fmt, "encoder": fmt, "convert": "", "ffmpeg": "", "note": ""}
	if fmt == "mp4":
		var ff := AdvFfmpeg.find(String(opts.get("ffmpeg", "")))
		if ff != "":
			return {"format": "mp4", "encoder": "avi", "convert": "mp4", "ffmpeg": ff, "note": ""}
		return {"format": "avi", "encoder": "avi", "convert": "", "ffmpeg": "", "note": "NO_MP4"}
	return {"format": "avi", "encoder": "avi", "convert": "", "ffmpeg": "", "note": "NO_ENCODER"}


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
	return _enc != null


## 録画しているパス（していなければ ""）。
func recording_path() -> String:
	return _path if _enc != null else ""


## 録画を始めてからの秒数。
func recording_seconds() -> float:
	return (Time.get_ticks_usec() - _t0) / 1000000.0 if _enc != null else 0.0


## 録画を始める。grab は source（"window"・"screen"）を受けて Image を返す。始めたファイルのパス（だめなら ""）。
func start_recording(opts: Dictionary, grab: Callable) -> String:
	last_error = ""
	last_note = ""
	if _enc != null:
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
	var pl := plan(_conf)
	last_note = String(pl["note"])
	var enc := make_encoder(String(pl["encoder"]))
	enc.options = _conf
	_convert = {"ffmpeg": pl["ffmpeg"], "format": pl["convert"]} if String(pl["convert"]) != "" else {}
	var rate := int(AudioServer.get_mix_rate()) if bool(_conf.get("audio", true)) else 0
	var ext := enc.extension() if enc.extension() != "" else String(pl["encoder"])
	var p := make_path(String(_conf.get("folder", REC_DEFAULTS["folder"])), String(_conf.get("prefix", "recording")), ext)
	# 書き出しは開くところから録画のスレッドで行う
	_queue.clear()
	_pending_video = 0
	_bytes = 0
	_enc = enc
	_path = p
	_open_err = OK
	_thread = Thread.new()
	_thread.start(_work.bind(p, rate))
	_opened.wait()
	if _open_err != OK:
		_thread.wait_to_finish()
		_thread = null
		_enc = null
		_path = ""
		last_error = "WRITE:%s" % error_string(_open_err)
		return ""
	if rate > 0:
		_cap = AudioEffectCapture.new()
		_cap.buffer_length = 1.0
		AudioServer.add_bus_effect(0, _cap)
		_cap.clear_buffer()
	_t0 = Time.get_ticks_usec()
	_queued_frames = 0
	_push_video(first)
	return p


## 録画を止めてファイルを閉じる。閉じたパス（録画していなければ ""）。reason は recording_stopped に渡す。
## MP4 に変えるときは、変え始めてから recording_stopped を出す（変え終えたら converted）。
func stop_recording(reason: String = "stop") -> String:
	if _enc == null:
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
	var p := _path
	last_info["format"] = _enc.extension()
	_enc = null
	_path = ""
	_grab = Callable()
	if not _convert.is_empty() and FileAccess.file_exists(p):
		start_convert(p, String(_convert["ffmpeg"]), _conf)
	_convert = {}
	recording_stopped.emit(p, reason)
	return p


# ---------------------------------------------------------------- MP4 に変える（ffmpeg）

## 変えている途中か（src を渡せば、そのファイルを変えているか）。
func is_converting(src: String = "") -> bool:
	return _converts.any(func(c): return src == "" or c["src"] == src)


## AVI を ffmpeg で MP4 に変え始める（終わりは _process で見て converted を出す）。始めたら変えた先のパス、だめなら ""。
## ゲームを閉じても ffmpeg は終わるまで続く（そのときは AVI も残る）。
func start_convert(src: String, ffmpeg: String, opts: Dictionary) -> String:
	var dst := src.get_basename() + ".mp4"
	var n := 2
	while FileAccess.file_exists(dst):
		dst = "%s_%d.mp4" % [src.get_basename(), n]
		n += 1
	var video := PackedStringArray()
	var extra = opts.get("ffmpeg_args", [])
	if extra is Array and not extra.is_empty():
		for a in extra:
			video.append(String(a))
	else:
		var h264 := AdvFfmpeg.h264_of(ffmpeg)
		if h264 == "":
			last_error = "NO_H264"
			converted.emit(src, false)
			return ""
		video = AdvFfmpeg.video_args(h264, float(opts.get("quality", 0.85)))
	var args := AdvFfmpeg.mp4_args(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst), video, bool(opts.get("audio", true)))
	var pid := OS.create_process(ffmpeg, args)
	if pid <= 0:
		last_error = "FFMPEG_START"
		converted.emit(src, false)
		return ""
	_converts.append({"pid": pid, "src": src, "dst": dst, "keep": bool(opts.get("keep_avi", false))})
	return dst


func _poll_converts() -> void:
	for c in _converts.duplicate():
		if OS.is_process_running(int(c["pid"])):
			continue
		_converts.erase(c)
		var dst := String(c["dst"])
		var ok := OS.get_process_exit_code(int(c["pid"])) == 0 and FileAccess.file_exists(dst) \
			and FileAccess.get_size(dst) > 0
		if ok:
			if not bool(c["keep"]):
				DirAccess.remove_absolute(String(c["src"]))
		else:
			last_error = "FFMPEG_FAILED"
			if FileAccess.file_exists(dst):
				DirAccess.remove_absolute(dst)
		converted.emit(dst if ok else String(c["src"]), ok)


func _process(_delta: float) -> void:
	if not _converts.is_empty():
		_poll_converts()
	if _enc == null:
		return
	var fps := int(_conf["fps"])
	var elapsed := recording_seconds()
	var max_s := float(_conf.get("max_seconds", 0))
	if max_s > 0.0 and elapsed >= max_s:
		stop_recording("max_seconds")
		return
	_mutex.lock()
	var bytes := _bytes
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


## 録画のスレッド：書き出しを開き、届いた順に渡し、最後に閉じる。
func _work(path: String, rate: int) -> void:
	var enc := _enc
	_open_err = enc.open(path, _w, _h, int(_conf["fps"]), rate)
	_opened.post()
	if _open_err != OK:
		return
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
			enc.add_video(img)
			_mutex.lock()
			_pending_video -= 1
			_mutex.unlock()
		elif item.has("repeat"):
			enc.repeat_video()
		elif item.has("audio"):
			enc.add_audio(item["audio"])
		var sz := enc.size()
		_mutex.lock()
		_bytes = sz
		_mutex.unlock()
	var info := enc.close()
	_mutex.lock()
	last_info = info
	_mutex.unlock()
