@tool
class_name AdvCardGrid
extends ScrollContainer
## カードを並べた一覧（6.8）。シナリオ・チャプター・シーンを1枚ずつのカードで見せる。
##
## - クリックで選ぶ。Ctrl+クリックで足す・外す、Shift+クリックで範囲を選ぶ
## - ダブルクリック（Enter）で開く
## - 右クリックで編集メニュー（menu_requested を出す。メニューは使う側が作る）
## - F2 で名前の変更（item_renamed を出す）、Delete で削除（delete_requested を出す）

signal opened(id: String)
signal menu_requested(ids: Array, at: Vector2)
signal item_renamed(id: String, name: String)
signal delete_requested(ids: Array)
signal selection_changed

const CARD_SIZE := Vector2(180, 96)

var selected: Array = []
var _flow: HFlowContainer
var _cards: Dictionary = {}     ## ID → PanelContainer
var _names: Dictionary = {}     ## ID → 名前の Label
var _order: Array = []
var _anchor: String = ""
var _style: StyleBoxFlat
var _style_sel: StyleBoxFlat


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode = Control.FOCUS_ALL
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flow.mouse_filter = Control.MOUSE_FILTER_PASS
	_flow.add_theme_constant_override("h_separation", 8)
	_flow.add_theme_constant_override("v_separation", 8)
	add_child(_flow)
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.18, 0.2, 0.25)
	_style.set_border_width_all(2)
	_style.border_color = Color(0.3, 0.33, 0.4)
	_style.set_corner_radius_all(4)
	_style.set_content_margin_all(8)
	_style_sel = _style.duplicate()
	_style_sel.bg_color = Color(0.22, 0.3, 0.45)
	_style_sel.border_color = Color(0.45, 0.65, 1.0)
	_flow.gui_input.connect(_on_empty_input)


## 並べ直す。items は [{id, name, sub}]（sub はカードの下の小さな字）。
func set_items(items: Array) -> void:
	for c in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	_cards.clear()
	_names.clear()
	_order.clear()
	var keep := selected.duplicate()
	selected.clear()
	for it in items:
		var id := String(it["id"])
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = "%s\nID: %s" % [it.get("name", id), id]
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		var name := Label.new()
		name.text = String(it.get("name", id))
		name.add_theme_font_size_override("font_size", 16)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name)
		var sub := Label.new()
		sub.text = String(it.get("sub", id))
		sub.modulate = Color(1, 1, 1, 0.6)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(sub)
		card.gui_input.connect(_on_card_input.bind(id))
		_flow.add_child(card)
		_cards[id] = card
		_names[id] = name
		_order.append(id)
		if id in keep:
			selected.append(id)
	_refresh_styles()


func ids() -> Array:
	return _order.duplicate()


func select_only(id: String) -> void:
	selected = [id] if _cards.has(id) else []
	_anchor = id
	_refresh_styles()
	selection_changed.emit()


## カードの上で名前を書き換える。決めたら renamed を出す（Esc でやめる）。
func begin_rename(id: String) -> void:
	if not _cards.has(id):
		return
	var label: Label = _names[id]
	var edit := LineEdit.new()
	edit.text = label.text
	edit.select_all_on_focus = true
	label.visible = false
	label.get_parent().add_child(edit)
	label.get_parent().move_child(edit, 0)
	edit.grab_focus()
	edit.select_all()
	var finish := func(ok: bool):
		if not is_instance_valid(edit) or edit.is_queued_for_deletion():
			return
		var t := edit.text.strip_edges()
		edit.queue_free()
		label.visible = true
		if ok and t != "" and t != label.text:
			label.text = t
			item_renamed.emit(id, t)
	edit.text_submitted.connect(func(_t): finish.call(true))
	edit.focus_exited.connect(func(): finish.call(true))
	edit.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			finish.call(false))


func _on_card_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				select_only(id)
				opened.emit(id)
			elif event.is_command_or_control_pressed():
				if id in selected:
					selected.erase(id)
				else:
					selected.append(id)
				_anchor = id
				_refresh_styles()
				selection_changed.emit()
			elif event.shift_pressed and _anchor != "" and _order.has(_anchor):
				var a := _order.find(_anchor)
				var b := _order.find(id)
				selected = _order.slice(mini(a, b), maxi(a, b) + 1)
				_refresh_styles()
				selection_changed.emit()
			else:
				select_only(id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not id in selected:
				select_only(id)
			menu_requested.emit(selected.duplicate(), event.global_position)
			accept_event()


func _on_empty_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
		if event.button_index == MOUSE_BUTTON_LEFT:
			selected.clear()
			_refresh_styles()
			selection_changed.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected.clear()
			_refresh_styles()
			menu_requested.emit([], event.global_position)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_F2:
			if not selected.is_empty():
				begin_rename(String(selected[0]))
				accept_event()
		KEY_DELETE:
			if not selected.is_empty():
				delete_requested.emit(selected.duplicate())
				accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if selected.size() == 1:
				opened.emit(String(selected[0]))
				accept_event()
		KEY_A:
			if event.is_command_or_control_pressed():
				selected = _order.duplicate()
				_refresh_styles()
				selection_changed.emit()
				accept_event()


func _refresh_styles() -> void:
	for id in _cards:
		(_cards[id] as PanelContainer).add_theme_stylebox_override("panel", _style_sel if id in selected else _style)
