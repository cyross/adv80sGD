class_name AdvVideoEncoder
extends RefCounted
## 録画の書き出しの受け口（段階69）。録画（AdvCapture）は、コマと音をこの形で渡す。
## 本体が持つのは AVI（AdvAviEncoder）だけ。MP4 などは、別に置く差し込み部品がこれを継いで作り、
##   AdvCapture.register_encoder("mp4", func(): return MyMp4Encoder.new())
## で登録する（モダン機能 recording の options.format で選ぶ）。
## open から close までは、どれも録画のスレッド（メインではないスレッド）から順に呼ぶ。

var options: Dictionary = {}   ## モダン機能 recording の options（open の前に入れる）


## 書き出すファイルの拡張子（"avi"、"mp4" など）。
func extension() -> String:
	return ""


## この環境で使えるか。false なら、録画は AVI になる。
func is_available() -> bool:
	return true


## ファイルを開く。audio_rate が 0 なら音なし（音は左右 2 つ）。
func open(_path: String, _width: int, _height: int, _fps: int, _audio_rate: int) -> Error:
	return ERR_UNAVAILABLE


## 1 コマ足す（RGB8、大きさは open と同じ）。
func add_video(_img: Image) -> void:
	pass


## 前のコマをもう一度足す（間に合わなかったコマの代わり）。
func repeat_video() -> void:
	pass


## 音を足す（左右の組の並び、-1〜1）。
func add_audio(_samples: PackedVector2Array) -> void:
	pass


## いまのファイルの大きさ（バイト。わからなければ 0）。
func size() -> int:
	return 0


## 閉じる。{path, frames, seconds, bytes} を返す。
func close() -> Dictionary:
	return {}
