class_name AdvMenuPanel
extends Panel
## 画面全体に重ねる、項目を並べた画面の部品（システムメニュー、ヒント、手帳、設定など）。
## テンプレートの窓の見た目で描く。右クリック・Esc で閉じる。

signal closed

var tpl: AdvTemplate
var _list: VBoxContainer
var _title: Label


func setup(title: String, template: AdvTemplate, screen_size: Vector2) -> AdvMenuPanel:
	tpl = template
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
	var box := VBoxContainer.new()
	box.position = Vector2(16, 6)
	box.size = screen_size - Vector2(32, 12)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = Label.new()
	_title.text = "― %s ―" % title
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_list)
	return self


func set_title(title: String) -> void:
	_title.text = "― %s ―" % title


func clear_items() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


func add_button(text: String, cb: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.pressed.connect(cb)
	_list.add_child(b)
	return b


## 文章の行（BBCode を使える）。color はパレットの番号（-1 なら標準の色）。
func add_text(text: String, color: int = -1) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = text
	if color >= 0:
		r.add_theme_color_override("default_color", tpl.color(color))
	_list.add_child(r)
	return r


func add_control(c: Control) -> void:
	_list.add_child(c)


func add_back(text: String = "もどる") -> Button:
	return add_button(text, close)


func focus_first() -> void:
	for c in _list.get_children():
		if c is Button and not c.disabled:
			c.call_deferred("grab_focus")
			return


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		accept_event()


func close() -> void:
	closed.emit()
	queue_free()
