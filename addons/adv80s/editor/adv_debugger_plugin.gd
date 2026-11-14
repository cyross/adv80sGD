@tool
extends EditorDebuggerPlugin
## デバッグ実行中のゲームからの知らせを受け取る（EngineDebugger.send_message の "adv80s:…"）。
## - adv80s:open_scene [シーンID, {dialogue?, knot?}] … シナリオエディタでそのシーン（会話・Ink のノットがあればそこ）を開く
## - adv80s:preset_saved [名前] … ゲームがひな形を書いた（シナリオエディタが取り込む）
## - adv80s:settings_saved [] … ゲームが設定の書きかえ（コンソールの notice save）を書いた（シナリオエディタが取り込む）

signal open_scene_requested(scene_id: String, location: Dictionary)
signal preset_saved(name: String)
signal settings_saved()


func _has_capture(capture: String) -> bool:
	return capture == "adv80s"


func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message == "adv80s:open_scene" and not data.is_empty():
		open_scene_requested.emit(String(data[0]), data[1] if data.size() >= 2 and data[1] is Dictionary else {})
		return true
	if message == "adv80s:settings_saved":
		settings_saved.emit()
		return true
	if message == "adv80s:preset_saved":
		preset_saved.emit(String(data[0]) if not data.is_empty() else "")
		return true
	return false
