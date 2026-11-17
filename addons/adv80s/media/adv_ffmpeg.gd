class_name AdvFfmpeg
extends RefCounted
## 録画の AVI を ffmpeg で MP4 にする（段階69）。パソコン（Windows・Mac・Linux）だけ。
## ffmpeg は同梱しない。使うのは、作る人が書いた場所（options.ffmpeg）か、
## ゲームの実行ファイルの隣の ffmpeg、遊ぶ人が入れた ffmpeg（PATH）。
## H.264 は、その ffmpeg にあるものを H264_ORDER の順に選ぶ（LGPL の ffmpeg でも、OS のエンコーダーが使える）。

const H264_ORDER := ["libx264", "h264_mf", "h264_videotoolbox", "libopenh264"]

static var _ok: Dictionary = {}        ## 試した ffmpeg → 動いたか
static var _h264: Dictionary = {}      ## ffmpeg → 使う H.264 のエンコーダー（なければ ""）


## この環境で ffmpeg を使えるか（パソコンだけ。Web・スマートフォン・ゲーム機では使わない）。
static func supported() -> bool:
	return OS.has_feature("pc") and not OS.has_feature("web")


## 探す場所。custom を書いたらそこだけ（相対パスは実行ファイルのフォルダから。res://・user:// も書ける）。
static func candidates(custom: String) -> PackedStringArray:
	var list := PackedStringArray()
	var exe_dir := OS.get_executable_path().get_base_dir()
	if custom != "":
		if custom.begins_with("res://") or custom.begins_with("user://"):
			list.append(ProjectSettings.globalize_path(custom))
		elif custom.is_absolute_path() or not (custom.contains("/") or custom.contains("\\")):
			list.append(custom)   # 絶対パスか、PATH から探す名前
		else:
			list.append(exe_dir.path_join(custom))
		return list
	list.append(exe_dir.path_join("ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"))
	list.append("ffmpeg")
	return list


## 使える ffmpeg（なければ ""）。一度試した結果は覚えておく。
static func find(custom: String = "") -> String:
	if not supported():
		return ""
	for c in candidates(custom):
		if c.is_absolute_path() and not FileAccess.file_exists(c):
			continue
		if not _ok.has(c):
			_ok[c] = OS.execute(c, ["-hide_banner", "-version"], []) == 0
		if _ok[c]:
			return c
	return ""


## 覚えておいた結果を消す（ffmpeg を入れ直したときやテスト）。
static func forget() -> void:
	_ok.clear()
	_h264.clear()


## ffmpeg -encoders の出力から、使う H.264 のエンコーダーを選ぶ（なければ ""）。
static func pick_h264(encoders_text: String) -> String:
	var names := {}
	for line in encoders_text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 2 and parts[0].length() == 6 and parts[0].begins_with("V"):
			names[parts[1]] = true
	for n in H264_ORDER:
		if names.has(n):
			return n
	return ""


## その ffmpeg で使う H.264 のエンコーダー（なければ ""）。
static func h264_of(ffmpeg: String) -> String:
	if not _h264.has(ffmpeg):
		var out: Array = []
		_h264[ffmpeg] = pick_h264("\n".join(out)) if OS.execute(ffmpeg, ["-hide_banner", "-encoders"], out) == 0 else ""
	return _h264[ffmpeg]


## 映像の引数。quality（0〜1）を、libx264 なら crf（28〜16）、ほかはビットレート（2〜12 Mbps）にする。色の範囲は tv、画素の形は yuv420p（h264_mf は nv12）。
static func video_args(encoder: String, quality: float) -> PackedStringArray:
	var q := clampf(quality, 0.0, 1.0)
	var a := PackedStringArray(["-c:v", encoder])
	if encoder == "libx264":
		a.append_array(["-preset", "veryfast", "-crf", str(int(round(lerpf(28.0, 16.0, q))))])
	else:
		a.append_array(["-b:v", "%dk" % int(round(lerpf(2000.0, 12000.0, q)))])
	# JPEG の色はフルレンジなので、ふつうの動画の範囲（tv）に直す（SNS や再生ソフトで色が変わらないように）
	a.append_array(["-vf", "scale=out_range=tv", "-pix_fmt", "nv12" if encoder == "h264_mf" else "yuv420p"])
	return a


## AVI を MP4 にする引数。extra（options.ffmpeg_args）を書いたら、映像の引数の代わりに使う。
static func mp4_args(src: String, dst: String, video: PackedStringArray, audio: bool) -> PackedStringArray:
	var a := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error", "-i", src])
	a.append_array(video)
	a.append_array(["-c:a", "aac", "-b:a", "192k"] if audio else ["-an"])
	a.append_array(["-movflags", "+faststart", dst])
	return a
