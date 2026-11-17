class_name AdvAviWriter
extends RefCounted
## 録画のファイル（AVI）を書く（段階68）。映像は 1 コマずつの JPEG（MJPEG）、音は 16 ビットの PCM。
## 外部のライブラリを使わずに書けて、多くの再生ソフトや動画の変換ソフト（ffmpeg など）で読める。
## 使い方：open → add_video・repeat_video・add_audio を順に → close。
## 1 つのファイルは 4 GB まで（RIFF の大きさが 32 ビットのため）。録画の側で手前で止める。

const AVIF_HASINDEX := 0x10
const AVIF_ISINTERLEAVED := 0x100
const AVIIF_KEYFRAME := 0x10

var path := ""
var width := 0
var height := 0
var fps := 30
var audio_rate := 0           ## 音の 1 秒あたりのサンプル数（0 なら音なし）
var channels := 2
var frames := 0               ## 書いたコマの数
var audio_bytes := 0          ## 書いた音のバイト数

var _f: FileAccess = null
var _riff_size_pos := 0
var _hdrl_size_pos := 0
var _avih_frames_pos := 0
var _vstrh_len_pos := 0
var _astrh_len_pos := 0
var _movi_size_pos := 0
var _movi_pos := 0            ## "movi" の 4 文字の位置（索引の位置はここから数える）
var _index := PackedByteArray()
var _last_video := PackedByteArray()


## ファイルを開いて、頭（大きさは仮）を書く。audio_rate を 0 にすると音なし。
func open(p: String, w: int, h: int, frame_rate: int, rate: int = 0, ch: int = 2) -> Error:
	path = p
	width = w
	height = h
	fps = maxi(1, frame_rate)
	audio_rate = maxi(0, rate)
	channels = clampi(ch, 1, 2)
	_f = FileAccess.open(p, FileAccess.WRITE)
	if _f == null:
		return FileAccess.get_open_error()
	var block := channels * 2
	_fourcc("RIFF")
	_riff_size_pos = _f.get_position()
	_f.store_32(0)
	_fourcc("AVI ")
	_fourcc("LIST")
	_hdrl_size_pos = _f.get_position()
	_f.store_32(0)
	_fourcc("hdrl")
	# avih（全体の頭）
	_fourcc("avih")
	_f.store_32(56)
	_f.store_32(int(1000000.0 / fps))   # 1 コマの長さ（マイクロ秒）
	_f.store_32(0)                       # 1 秒あたりの最大のバイト数（使わない）
	_f.store_32(0)
	_f.store_32(AVIF_HASINDEX | AVIF_ISINTERLEAVED)
	_avih_frames_pos = _f.get_position()
	_f.store_32(0)                       # コマの数（閉じるときに書く）
	_f.store_32(0)
	_f.store_32(2 if audio_rate > 0 else 1)
	_f.store_32(w * h * 3)
	_f.store_32(w)
	_f.store_32(h)
	for i in 4:
		_f.store_32(0)
	# 映像の流れ
	var vl := _begin_list("strl")
	_fourcc("strh")
	_f.store_32(56)
	_fourcc("vids")
	_fourcc("MJPG")
	_f.store_32(0)       # flags
	_f.store_32(0)       # priority・language
	_f.store_32(0)       # initial frames
	_f.store_32(1)       # scale
	_f.store_32(fps)     # rate（rate / scale がコマの速さ）
	_f.store_32(0)       # start
	_vstrh_len_pos = _f.get_position()
	_f.store_32(0)       # length（閉じるときに書く）
	_f.store_32(w * h * 3)
	_f.store_32(0xFFFFFFFF)   # quality（-1）
	_f.store_32(0)       # sample size
	_f.store_16(0)
	_f.store_16(0)
	_f.store_16(w)
	_f.store_16(h)
	_fourcc("strf")
	_f.store_32(40)      # BITMAPINFOHEADER
	_f.store_32(40)
	_f.store_32(w)
	_f.store_32(h)
	_f.store_16(1)
	_f.store_16(24)
	_fourcc("MJPG")
	_f.store_32(w * h * 3)
	for i in 4:
		_f.store_32(0)
	_end_list(vl)
	# 音の流れ
	if audio_rate > 0:
		var al := _begin_list("strl")
		_fourcc("strh")
		_f.store_32(56)
		_fourcc("auds")
		_f.store_32(0)
		_f.store_32(0)
		_f.store_32(0)
		_f.store_32(0)
		_f.store_32(block)                # scale
		_f.store_32(audio_rate * block)   # rate（1 秒あたりのバイト数）
		_f.store_32(0)
		_astrh_len_pos = _f.get_position()
		_f.store_32(0)                    # length（サンプルの組の数。閉じるときに書く）
		_f.store_32(audio_rate * block)
		_f.store_32(0xFFFFFFFF)
		_f.store_32(block)                # sample size
		for i in 4:
			_f.store_16(0)
		_fourcc("strf")
		_f.store_32(18)                   # WAVEFORMATEX
		_f.store_16(1)                    # PCM
		_f.store_16(channels)
		_f.store_32(audio_rate)
		_f.store_32(audio_rate * block)
		_f.store_16(block)
		_f.store_16(16)
		_f.store_16(0)
		_end_list(al)
	_end_list(_hdrl_size_pos)
	_fourcc("LIST")
	_movi_size_pos = _f.get_position()
	_f.store_32(0)
	_movi_pos = _f.get_position()
	_fourcc("movi")
	return OK


func is_open() -> bool:
	return _f != null


## いまのファイルの大きさ（バイト）。
func size() -> int:
	return _f.get_position() if _f != null else 0


## 1 コマ（JPEG のバイト列）を足す。
func add_video(jpeg: PackedByteArray) -> void:
	if _f == null or jpeg.is_empty():
		return
	_chunk("00dc", jpeg, true)
	_last_video = jpeg
	frames += 1


## 前のコマをもう一度足す（間に合わなかったコマの代わり。音とずれないように数を合わせる）。
func repeat_video() -> void:
	if not _last_video.is_empty():
		add_video(_last_video)


## 音（16 ビットの PCM。左右が交互）を足す。
func add_audio(pcm: PackedByteArray) -> void:
	if _f == null or audio_rate <= 0 or pcm.is_empty():
		return
	_chunk("01wb", pcm, false)
	audio_bytes += pcm.size()


## 索引を書いて、仮にしておいた大きさを直して閉じる。{path, frames, seconds, bytes} を返す。
func close() -> Dictionary:
	if _f == null:
		return {}
	_end_list(_movi_size_pos)
	_fourcc("idx1")
	_f.store_32(_index.size())
	_f.store_buffer(_index)
	var end := _f.get_position()
	_patch(_riff_size_pos, end - _riff_size_pos - 4)
	_patch(_avih_frames_pos, frames)
	_patch(_vstrh_len_pos, frames)
	if audio_rate > 0:
		_patch(_astrh_len_pos, audio_bytes / (channels * 2))
	_f.close()
	_f = null
	_index = PackedByteArray()
	_last_video = PackedByteArray()
	return {"path": path, "frames": frames, "seconds": float(frames) / fps, "bytes": end}


## 音（Godot の左右の組の並び。-1〜1）を 16 ビットの PCM にする。
static func pcm16(samples: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 4)
	var i := 0
	for v in samples:
		out.encode_s16(i, int(clampf(v.x, -1.0, 1.0) * 32767.0))
		out.encode_s16(i + 2, int(clampf(v.y, -1.0, 1.0) * 32767.0))
		i += 4
	return out


## 書いた AVI の頭を読む（確かめ用）。{width, height, fps, frames, streams, audio_rate, video_chunks, audio_chunks}。読めなければ {}。
static func read_info(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() < 12:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return {}
	var riff := f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "AVI ":
		return {}
	var info := {"riff_ok": riff + 8 == f.get_length(), "video_chunks": 0, "audio_chunks": 0, "audio_rate": 0}
	_read_chunks(f, f.get_length(), info)
	return info


static func _read_chunks(f: FileAccess, end: int, info: Dictionary) -> void:
	while f.get_position() + 8 <= end:
		var id := f.get_buffer(4).get_string_from_ascii()
		var sz := f.get_32()
		var start := f.get_position()
		match id:
			"LIST":
				f.get_buffer(4)
				_read_chunks(f, start + sz, info)
			"avih":
				var us := f.get_32()
				info["fps"] = int(round(1000000.0 / us)) if us > 0 else 0
				f.get_32()
				f.get_32()
				f.get_32()
				info["frames"] = f.get_32()
				f.get_32()
				info["streams"] = f.get_32()
				f.get_32()
				info["width"] = f.get_32()
				info["height"] = f.get_32()
			"strf":
				if sz == 18:
					f.get_16()
					info["channels"] = f.get_16()
					info["audio_rate"] = f.get_32()
			"00dc":
				info["video_chunks"] += 1
				if not info.has("first_jpeg"):
					info["first_jpeg"] = f.get_buffer(sz)
			"01wb":
				info["audio_chunks"] += 1
			"idx1":
				info["index_entries"] = sz / 16
		f.seek(start + sz + (sz & 1))


func _fourcc(s: String) -> void:
	_f.store_buffer(s.to_ascii_buffer())


func _begin_list(kind: String) -> int:
	_fourcc("LIST")
	var pos := _f.get_position()
	_f.store_32(0)
	_fourcc(kind)
	return pos


func _end_list(size_pos: int) -> void:
	_patch(size_pos, _f.get_position() - size_pos - 4)


func _patch(pos: int, value: int) -> void:
	var back := _f.get_position()
	_f.seek(pos)
	_f.store_32(value)
	_f.seek(back)


func _chunk(id: String, data: PackedByteArray, key: bool) -> void:
	var at := _f.get_position()
	_fourcc(id)
	_f.store_32(data.size())
	_f.store_buffer(data)
	if data.size() & 1:
		_f.store_8(0)
	var e := PackedByteArray()
	e.resize(16)
	e.encode_u32(0, id.to_ascii_buffer().decode_u32(0))
	e.encode_u32(4, AVIIF_KEYFRAME if key else 0)
	e.encode_u32(8, at - _movi_pos)
	e.encode_u32(12, data.size())
	_index.append_array(e)
