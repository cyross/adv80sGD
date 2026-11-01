class_name AdvScreen
extends Control
## 画面（表示層）。テンプレートの区割りに従って、画像の層、メッセージの窓、コマンドの窓、入力欄を作る。

const FALLBACK_FONTS := ["MS Gothic", "ＭＳ ゴシック", "Osaka-Mono", "Noto Sans Mono CJK JP",
	"Noto Sans CJK JP", "IPAGothic", "VL Gothic", "monospace"]

var tpl: AdvTemplate
var picture: Control
var layers: Dictionary = {}          ## 層の名前 → Control
var message_label: RichTextLabel
var wait_mark: Label
var command_select: AdvCommandSelect
var command_line: AdvCommandLine

var _speed: float = 40.0             ## 1秒あたりの文字数。0 なら一度に表示
var _shown: float = 0.0
var _typing: bool = false


func build(template: AdvTemplate) -> void:
	tpl = template
	for c in get_children():
		c.queue_free()
	layers.clear()
	var sz := tpl.screen_size
	position = Vector2.ZERO
	size = Vector2(sz)
	custom_minimum_size = Vector2(sz)
	clip_contents = true
	theme = _make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_speed = float(tpl.get_section("text").get("speed", 40))

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = tpl.color(int(tpl.get_section("layout").get("background", 0)))
	bg.size = Vector2(sz)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 画像の層
	picture = Control.new()
	picture.name = "Picture"
	picture.clip_contents = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(picture, tpl.region_rect("picture"))
	add_child(picture)
	for layer_name in tpl.get_section("layout").get("layers", ["bg"]):
		var l := Control.new()
		l.name = String(layer_name)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size = picture.size
		picture.add_child(l)
		layers[String(layer_name)] = l

	# メッセージの窓
	var msg_rect := tpl.region_rect("message")
	var msg_win := _window("MessageWindow", msg_rect)
	message_label = RichTextLabel.new()
	message_label.name = "Text"
	message_label.bbcode_enabled = true
	message_label.scroll_active = false
	message_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.position = Vector2(8, 4)
	message_label.size = Vector2(msg_rect.size) - Vector2(16, 8)
	msg_win.add_child(message_label)
	wait_mark = Label.new()
	wait_mark.text = "▼"
	wait_mark.visible = false
	wait_mark.position = Vector2(msg_rect.size.x - 22, msg_rect.size.y - 22)
	msg_win.add_child(wait_mark)

	# コマンドの窓
	var cmd_rect := tpl.region_rect("commands")
	if cmd_rect.size != Vector2i.ZERO:
		var cmd_win := _window("CommandWindow", cmd_rect)
		command_select = AdvCommandSelect.new()
		command_select.name = "CommandSelect"
		command_select.position = Vector2(4, 4)
		command_select.size = Vector2(cmd_rect.size) - Vector2(8, 8)
		cmd_win.add_child(command_select)

	# コマンド入力欄
	var in_rect := tpl.region_rect("input")
	if in_rect.size != Vector2i.ZERO:
		command_line = AdvCommandLine.new()
		command_line.name = "CommandLine"
		_place(command_line, in_rect)
		add_child(command_line)


func _place(c: Control, r: Rect2i) -> void:
	c.position = Vector2(r.position)
	c.size = Vector2(r.size)


## 枠つきの窓（window_skin が box のとき：パレットの色で単純な枠線を描く）。
func _window(node_name: String, r: Rect2i) -> Panel:
	var p := Panel.new()
	p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_place(p, r)
	var skin: Dictionary = tpl.get_section("ui").get("window_skin", {})
	var sb := StyleBoxFlat.new()
	sb.bg_color = tpl.color(int(skin.get("fill", 0)))
	var bw := int(skin.get("border", 1))
	sb.set_border_width_all(bw)
	sb.border_color = tpl.color(int(skin.get("pal", 7)))
	sb.anti_aliasing = false
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _make_theme() -> Theme:
	var th := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FALLBACK_FONTS)
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	th.default_font = font
	var fsize := int(tpl.get_section("fonts").get("main", {}).get("size", 16))
	th.default_font_size = fsize
	var fg := tpl.color(int(tpl.get_section("text").get("color", 7)))
	var hl := tpl.color(int(tpl.get_section("ui").get("highlight", 1)))
	var dim := tpl.color(8)
	for type in ["Label", "Button", "LineEdit", "RichTextLabel"]:
		th.set_color("font_color" if type != "RichTextLabel" else "default_color", type, fg)
	th.set_color("font_hover_color", "Button", fg)
	th.set_color("font_focus_color", "Button", fg)
	th.set_color("font_pressed_color", "Button", fg)
	th.set_color("font_disabled_color", "Button", dim)
	th.set_color("font_uneditable_color", "LineEdit", dim)
	th.set_color("caret_color", "LineEdit", fg)
	# ボタンは行の高さを詰めて、コマンドの窓に多く並べられるようにする
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_top = -3
	empty.content_margin_bottom = -3
	var on := StyleBoxFlat.new()
	on.bg_color = hl
	on.anti_aliasing = false
	on.content_margin_left = 2
	on.content_margin_top = -3
	on.content_margin_bottom = -3
	for st in ["normal", "disabled"]:
		th.set_stylebox(st, "Button", empty)
	for st in ["hover", "pressed", "focus"]:
		th.set_stylebox(st, "Button", on)
	var le := StyleBoxFlat.new()
	le.bg_color = tpl.color(0)
	le.set_border_width_all(1)
	le.border_color = tpl.color(7)
	le.anti_aliasing = false
	le.content_margin_left = 6
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", le)
	th.set_stylebox("read_only", "LineEdit", le)
	return th


# ---------------------------------------------------------------- 画像

## 画像を表示する。path が空なら代わりの表示（IDを書いた枠）を出す。
func show_image(layer: String, id: String, path: String) -> void:
	var l: Control = layers.get(layer, layers.get("bg"))
	if l == null:
		return
	for c in l.get_children():
		c.queue_free()
	var tex: Texture2D = null
	if path != "":
		tex = load(path) as Texture2D
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.size = picture.size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_child(tr)
	else:
		var ph := ColorRect.new()
		ph.color = tpl.color(9)
		ph.size = picture.size
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lb := Label.new()
		lb.text = "[%s]" % id
		lb.position = Vector2(8, 8)
		ph.add_child(lb)
		l.add_child(ph)


func hide_image(layer: String) -> void:
	var l: Control = layers.get(layer)
	if l != null:
		for c in l.get_children():
			c.queue_free()


# ---------------------------------------------------------------- 文章

## 文章を表示する（文字送りあり）。name があれば「名前「本文」」の形にする。
func show_text(bbcode: String, speaker_name: String = "", instant: bool = false) -> void:
	var t := bbcode
	if speaker_name != "":
		var nc := tpl.color(int(tpl.get_section("text").get("name_color", 6))).to_html(false)
		t = "[color=#%s]%s[/color]「%s」" % [nc, AdvTextMarkup._escape(speaker_name), bbcode]
	message_label.text = t
	wait_mark.visible = false
	if instant or _speed <= 0.0:
		complete_text()
	else:
		_shown = 0.0
		message_label.visible_characters = 0
		_typing = true


func clear_text() -> void:
	message_label.text = ""
	wait_mark.visible = false
	_typing = false


func is_typing() -> bool:
	return _typing


func complete_text() -> void:
	_typing = false
	message_label.visible_characters = -1


func set_wait_mark(on: bool) -> void:
	wait_mark.visible = on


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += _speed * delta
	message_label.visible_characters = int(_shown)
	if int(_shown) >= message_label.get_total_character_count():
		complete_text()
