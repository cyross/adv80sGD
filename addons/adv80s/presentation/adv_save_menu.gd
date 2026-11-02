class_name AdvSaveMenu
extends Panel
## セーブとロードの画面。スロットの一覧を出し、選んだスロットを slot_chosen で知らせる。

signal slot_chosen(mode: String, slot: String)
signal closed

var mode: String = "save"   ## save / load


## slots：[{slot, label, exists, info}]（AdvPlayer.list_saves の結果）
func open(menu_mode: String, slots: Array, tpl: AdvTemplate, screen_size: Vector2) -> void:
	mode = menu_mode
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
	box.position = Vector2(16, 8)
	box.size = screen_size - Vector2(32, 16)
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "― セーブ ―" if mode == "save" else "― ロード ―"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var sw := Button.new()
	sw.text = "ロードへ" if mode == "save" else "セーブへ"
	sw.pressed.connect(func(): _switch(slots, tpl, screen_size))
	head.add_child(sw)
	var back := Button.new()
	back.text = "もどる"
	back.pressed.connect(close)
	head.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	var first: Button = null
	for s in slots:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  %s" % [String(s["label"]), String(s.get("info", "")) if s.get("exists", false) else "―――"]
		b.disabled = mode == "load" and not s.get("exists", false)
		b.pressed.connect(func(): slot_chosen.emit(mode, String(s["slot"])))
		list.add_child(b)
		if first == null and not b.disabled:
			first = b
	if first != null:
		first.call_deferred("grab_focus")


func _switch(slots: Array, tpl: AdvTemplate, screen_size: Vector2) -> void:
	for c in get_children():
		c.queue_free()
	open("load" if mode == "save" else "save", slots, tpl, screen_size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		accept_event()


func close() -> void:
	closed.emit()
	queue_free()
