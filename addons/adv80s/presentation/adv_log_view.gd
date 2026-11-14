class_name AdvLogView
extends Panel
## メッセージログの画面（第9章）。テンプレートの窓の見た目で、画面全体に重ねて出す。
## マウスホイールでさかのぼり、右クリック・Esc・ログのキーで閉じる。

signal closed
signal rewind_requested(index: int)   ## 入力の行を押した（その入力の前まで巻き戻す）
signal voice_requested(id: String)    ## ボイスの印を押した（もう一度鳴らす）

var _text: RichTextLabel
var filter: String = "all"        ## 出すもの：all（すべて）、text（お知らせ以外）、notice（お知らせだけ）
var filter_button: Button
var _title: Label
var _log: AdvMessageLog
var _tpl: AdvTemplate
var _can_rewind := false
var _notice: Dictionary = {}

const FILTERS := ["all", "text", "notice"]
const FILTER_NAMES := {"all": "ひょうじ：すべて", "text": "ひょうじ：ぶんしょう", "notice": "ひょうじ：おしらせ"}


## 見出し・「ひょうじ」・ログの文を、テンプレートの文字の色（text.color）に（段階63。地の色と見分けられる色）。
func _ready() -> void:
	var c := _tpl.color(int(_tpl.get_section("text").get("color", 7)))
	_text.add_theme_color_override("default_color", c)
	if _title != null:
		_title.add_theme_color_override("font_color", c)
	if filter_button != null:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			filter_button.add_theme_color_override(k, c)


## notice はお知らせの見た目（log_mark：前に付ける印、log_color：色のパレットの番号）。
func open(entries_log: AdvMessageLog, tpl: AdvTemplate, screen_size: Vector2, can_rewind: bool = false, notice: Dictionary = {}) -> void:
	position = Vector2.ZERO
	size = screen_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var skin: Dictionary = tpl.get_section("ui").get("window_skin", {})
	var sb := StyleBoxFlat.new()
	sb.bg_color = tpl.window_fill_color()   # 文字の色と見分けられる地の色（段階63）
	sb.set_border_width_all(int(skin.get("border", 1)))
	sb.border_color = tpl.color(int(skin.get("pal", 7)))
	sb.anti_aliasing = false
	add_theme_stylebox_override("panel", sb)
	var title := Label.new()
	title.text = "― ログ ―"
	title.position = Vector2(8, 2)
	add_child(title)
	_title = title
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.position = Vector2(8, 20)
	_text.size = screen_size - Vector2(16, 28)
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_text)
	_log = entries_log
	_tpl = tpl
	_can_rewind = can_rewind
	_notice = notice
	# お知らせのあるときだけ、出すものの切り替えを出す
	if entries_log.entries.any(func(e): return e.get("kind") == "notice"):
		filter_button = Button.new()
		filter_button.name = "Filter"
		filter_button.focus_mode = Control.FOCUS_NONE
		filter_button.flat = true
		var fw := minf(172.0, screen_size.x - 8.0)   # 小さい画面（GB など）でも画面の中に（段階63）
		filter_button.position = Vector2(screen_size.x - fw - 8.0, 0)
		filter_button.size = Vector2(fw, 20)
		filter_button.clip_text = true
		filter_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		filter_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		filter_button.pressed.connect(func(): set_filter(FILTERS[(FILTERS.find(filter) + 1) % FILTERS.size()]))
		add_child(filter_button)
	set_filter(String(notice.get("log_filter", "all")))
	_text.meta_clicked.connect(func(meta):
		var m := str(meta)
		if m.begins_with("v:"):
			voice_requested.emit(m.substr(2))
		else:
			rewind_requested.emit(int(m)))


## Tab キーでも、出すものを切り替える。
func _unhandled_key_input(event: InputEvent) -> void:
	if filter_button != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		set_filter(FILTERS[(FILTERS.find(filter) + 1) % FILTERS.size()])
		get_viewport().set_input_as_handled()


## 出すものを変えて、書き直す。
func set_filter(f: String) -> void:
	filter = f if f in FILTERS else "all"
	if filter_button != null:
		var labels: Dictionary = FILTER_NAMES.duplicate()
		var custom = _notice.get("log_labels", {})
		if custom is Dictionary:
			labels.merge(custom, true)
		filter_button.text = String(labels[filter])
	var tpl := _tpl
	var name_c := tpl.color(int(tpl.get_section("text").get("name_color", 6))).to_html(false)
	var text_i := int(tpl.get_section("text").get("color", 7))   # 色の少ないパレット（GB など）では文字の色を使う（段階63）
	var input_c := tpl.color(5 if tpl.preset.get("palette", PackedColorArray()).size() > 5 else text_i).to_html(false)
	var notice_c := tpl.color(int(_notice.get("log_color", 5 if tpl.preset.get("palette", PackedColorArray()).size() > 5 else text_i))).to_html(false)
	var notice_mark := AdvTextMarkup._escape(String(_notice.get("log_mark", "◆ ")))
	var lines := PackedStringArray()
	for e in _log.entries:
		var is_notice: bool = e["kind"] == "notice"
		if (filter == "text" and is_notice) or (filter == "notice" and not is_notice):
			continue
		var body := AdvTextMarkup._escape(String(e.get("body", "")))
		if is_notice:
			lines.append("[color=#%s]%s%s[/color]" % [notice_c, notice_mark, body])
		elif e["kind"] == "input":
			if _can_rewind and e.has("rewind"):
				lines.append("[url=%d][color=#%s]> %s[/color][/url]" % [int(e["rewind"]), input_c, body])
			else:
				lines.append("[color=#%s]> %s[/color]" % [input_c, body])
		else:
			var voice := "[url=v:%s]♪[/url] " % String(e["voice"]) if String(e.get("voice", "")) != "" else ""
			if e.has("name"):
				lines.append("%s[color=#%s]%s[/color]「%s」" % [voice, name_c, AdvTextMarkup._escape(String(e["name"])), body])
			else:
				lines.append(voice + body)
	if _can_rewind and filter != "notice":
		lines.append("")
		lines.append("（入力の行を えらぶと、その まえに もどる）")
	_text.text = "\n".join(lines)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		accept_event()


func close() -> void:
	closed.emit()
	queue_free()
