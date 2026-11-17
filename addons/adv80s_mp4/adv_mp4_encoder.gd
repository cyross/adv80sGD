class_name AdvMp4Encoder
extends AdvVideoEncoder
## 録画を OS のエンコーダーで MP4（H.264＋AAC）に書く（段階70）。いまは Windows（Media Foundation）だけ。
## 中身は GDExtension の AdvMfWriter。DLL が読めない・その環境で使えないときは is_available() が false で、
## 録画は ffmpeg で変えるか AVI になる（AdvCapture.plan）。
## 映像は NV12（BT.709、16〜235）にして渡す。音は 44100・48000 Hz のときだけ AAC で書く（ほかは音なし）。

const NATIVE := "AdvMfWriter"

static var _ready_cache: Variant = null

var _w: Object = null
var _path := ""


## GDExtension が読めていて、この環境で MP4 を書けるか。
static func native_ready() -> bool:
	if _ready_cache == null:
		_ready_cache = ClassDB.class_exists(NATIVE) and bool(ClassDB.instantiate(NATIVE).call("is_supported"))
	return bool(_ready_cache)


## 録画（AdvCapture）に "mp4" の書き出しとして登録する。
static func register() -> void:
	AdvCapture.register_encoder("mp4", func(): return AdvMp4Encoder.new())


## options の quality（0〜1）を映像のビット毎秒にする（2〜12 Mbps）。
static func bitrate_of(quality: float) -> int:
	return int(round(lerpf(2000.0, 12000.0, clampf(quality, 0.0, 1.0)))) * 1000


func extension() -> String:
	return "mp4"


func is_available() -> bool:
	return native_ready()


func open(path: String, width: int, height: int, fps: int, audio_rate: int) -> Error:
	if not native_ready():
		return ERR_UNAVAILABLE
	_path = path
	_w = ClassDB.instantiate(NATIVE)
	return _w.call("open", ProjectSettings.globalize_path(path), width, height, fps, audio_rate,
		bitrate_of(float(options.get("quality", 0.85))))


func add_video(img: Image) -> void:
	_w.call("add_video", img)


func repeat_video() -> void:
	_w.call("repeat_video")


func add_audio(samples: PackedVector2Array) -> void:
	_w.call("add_audio", samples)


func size() -> int:
	return int(_w.call("get_size")) if _w != null else 0


func close() -> Dictionary:
	if _w == null:
		return {}
	var d: Dictionary = _w.call("close")
	d["path"] = _path
	_w = null
	return d


## 確かめ用：MP4 の中身 {video, width, height, fps, audio, audio_rate, channels, seconds}。
static func probe(path: String) -> Dictionary:
	return ClassDB.instantiate(NATIVE).call("probe", ProjectSettings.globalize_path(path)) if native_ready() else {}


## 確かめ用：最初のコマ。
static func read_first_frame(path: String) -> Image:
	return ClassDB.instantiate(NATIVE).call("read_first_frame", ProjectSettings.globalize_path(path)) if native_ready() else null
