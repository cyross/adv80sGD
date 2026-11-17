@tool
extends EditorPlugin
## adv80s MP4 のエディタプラグイン（段階70）。
## 入れると、ゲームの始めに MP4 の書き出しを登録する自動読み込み（AdvMp4）を足す。外すと取り除く。

const AUTOLOAD := "AdvMp4"
const SETUP := "res://addons/adv80s_mp4/adv_mp4_setup.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD, SETUP)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD)
