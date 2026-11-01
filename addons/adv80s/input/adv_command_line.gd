class_name AdvCommandLine
extends LineEdit
## コマンド入力欄。Enter で入力した文字列を command_entered で知らせる。読み取りは AdvParserJa などのプロファイルで行う。

signal command_entered(text: String)


func _ready() -> void:
	placeholder_text = "> コマンドを にゅうりょく"
	text_submitted.connect(_on_submitted)


func _on_submitted(t: String) -> void:
	var s := t.strip_edges()
	clear()
	if s != "":
		command_entered.emit(s)


func set_enabled(on: bool) -> void:
	editable = on
	if not on and has_focus():
		release_focus()
