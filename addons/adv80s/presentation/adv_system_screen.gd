class_name AdvSystemScreen
extends Control
## 自作のシステム画面（.tscn）の土台（6.9）。プロジェクト設定 system_scenes で、セーブ・ロード・設定・ログの画面を
## Godot のシーンに差し替えるときは、そのシーンの一番上のノードにこのスクリプトを継いだものを付ける。
##
##   extends AdvSystemScreen
##   func _on_opened() -> void:
##       for s in slots(): …            # セーブ枠の一覧 [{slot, label, exists, info}]
##   func _on_slot_pressed(slot):
##       save(slot) か load_slot(slot)   # どちらも、そのあと閉じる
##
## 開くと player（AdvPlayer）と mode（"save"・"load"・"settings"・"log"）が入り、_on_opened が呼ばれる。
## close() で閉じる。Esc・右クリックでも閉じる。

signal closed

var player: Node           ## AdvPlayer
var mode: String = ""      ## save・load・settings・log


func open(p: Node, m: String) -> void:
	player = p
	mode = m
	_on_opened()


## 開いたとき（継いだスクリプトで書く）。
func _on_opened() -> void:
	pass


## セーブ枠の一覧 [{slot, label, exists, info}]。
func slots() -> Array:
	return player.list_saves()


## セーブして閉じる。
func save(slot: String) -> Error:
	var err: Error = player.save_game(slot)
	close()
	return err


## ロードして閉じる。
func load_slot(slot: String) -> void:
	close()
	player.load_game(slot)


## 設定の値を読む・書く（text_speed、bgm_volume、se_volume、voice_volume、filters など）。
func get_setting(key: String, default: Variant = null) -> Variant:
	return player.settings.get_value(key, default)


func set_setting(key: String, value: Variant) -> void:
	player.apply_setting(key, value)


## メッセージログの行 [{name, text, …}]。
func log_entries() -> Array:
	return player.message_log.entries


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		accept_event()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
