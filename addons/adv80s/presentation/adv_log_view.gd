class_name AdvLogView
extends Panel
## メッセージログの画面（第9章）。テンプレートの窓の見た目で、画面全体に重ねて出す。
## マウスホイールでさかのぼり、右クリック・Esc・ログのキーで閉じる。

signal closed
signal rewind_requested(index: int)   ## 入力の行を押した（その入力の前まで巻き戻す）
signal voice_requested(id: String)    ## ボイスの印を押した（もう一度鳴らす）

var _text: RichTextLabel


func open(entries_log: AdvMessageLog, tpl: AdvTemplate, screen_size: Vector2, can_rewind: bool = false) -> void:
	position = Vector2.ZERO
	size = screen_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var skin: Dictionary = tpl.get_section("ui").get("window_skin", {})
	var sb := StyleBoxFlat.new()
	sb.bg_color = tpl.color(int(skin.get("fill", 0)))
	sb.set_border_width_all(int(skin.get("border", 1)))
	sb.border_color = tpl.color(int(skin.get("pal", 7)))
	sb.anti_aliasing = false
	add_theme_stylebox_override("panel", sb)
	var title := Label.new()
	title.text = "― ログ ―"
	title.position = Vector2(8, 2)
	add_child(title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.position = Vector2(8, 20)
	_text.size = screen_size - Vector2(16, 28)
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_text)
	var name_c := tpl.color(int(tpl.get_section("text").get("name_color", 6))).to_html(false)
	var input_c := tpl.color(5 if tpl.preset.get("palette", PackedColorArray()).size() > 5 else 7).to_html(false)
	var lines := PackedStringArray()
	for e in entries_log.entries:
		var body := AdvTextMarkup._escape(String(e.get("body", "")))
		if e["kind"] == "input":
			if can_rewind and e.has("rewind"):
				lines.append("[url=%d][color=#%s]> %s[/color][/url]" % [int(e["rewind"]), input_c, body])
			else:
				lines.append("[color=#%s]> %s[/color]" % [input_c, body])
		else:
			var voice := "[url=v:%s]♪[/url] " % String(e["voice"]) if String(e.get("voice", "")) != "" else ""
			if e.has("name"):
				lines.append("%s[color=#%s]%s[/color]「%s」" % [voice, name_c, AdvTextMarkup._escape(String(e["name"])), body])
			else:
				lines.append(voice + body)
	if can_rewind:
		lines.append("")
		lines.append("（入力の行を えらぶと、その まえに もどる）")
	_text.text = "\n".join(lines)
	_text.meta_clicked.connect(func(meta):
		var m := str(meta)
		if m.begins_with("v:"):
			voice_requested.emit(m.substr(2))
		else:
			rewind_requested.emit(int(m)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		accept_event()


func close() -> void:
	closed.emit()
	queue_free()
