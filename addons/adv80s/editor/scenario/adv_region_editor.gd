@tool
class_name AdvRegionEditor
extends ConfirmationDialog
## 範囲のエディタ（6.8）。シーンの背景の上で、もの・出口の範囲（region：[x, y, 幅, 高さ]）をドラッグで決める。
##
##   var ed := AdvRegionEditor.new()
##   add_child(ed)
##   ed.open(texture, [{key, label, region}], func(regions): …)   # regions は key → [x, y, w, h]（消したものは null）
##
## - 左の一覧で、もの・出口を選ぶ
## - 絵の上をドラッグすると、その範囲になる（元の解像度のピクセル。1ドット単位）
## - 「範囲を消す」で、範囲を書かない（スプライトの形などを使う）にする

const DEFAULT_SIZE := Vector2i(640, 400)

var list: ItemList
var canvas: Control
var info: Label
var texture: Texture2D
var targets: Array = []          ## [{key, label, region}]
var regions: Dictionary = {}     ## key → [x, y, w, h] か null
var _done: Callable
var _drag_from = null            ## 絵の座標（Vector2i）
var _drag_to: Vector2i


func _init() -> void:
	title = "範囲を絵で決める"
	ok_button_text = "決定"
	min_size = Vector2i(900, 520)
	var box := HBoxContainer.new()
	add_child(box)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	box.add_child(left)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(_i):
		_update_info()
		canvas.queue_redraw())
	left.add_child(list)
	var clear := Button.new()
	clear.text = "範囲を消す"
	clear.pressed.connect(func():
		var k := selected_key()
		if k != "":
			regions[k] = null
			_update_info()
			canvas.queue_redraw())
	left.add_child(clear)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(info)
	canvas = Control.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(660, 440)
	canvas.clip_contents = true
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_on_canvas_input)
	box.add_child(canvas)
	confirmed.connect(func():
		if _done.is_valid():
			_done.call(regions.duplicate(true)))


func open(tex: Texture2D, p_targets: Array, done: Callable = Callable()) -> void:
	texture = tex
	targets = p_targets
	_done = done
	regions = {}
	list.clear()
	for t in targets:
		regions[t["key"]] = t.get("region")
		list.add_item(String(t["label"]))
	if list.item_count > 0:
		list.select(0)
	_update_info()
	popup_centered()
	canvas.queue_redraw()


func selected_key() -> String:
	var sel := list.get_selected_items()
	return String(targets[sel[0]]["key"]) if not sel.is_empty() else ""


func image_size() -> Vector2i:
	return Vector2i(texture.get_size()) if texture != null else DEFAULT_SIZE


## 絵を出す倍率と位置。
func _fit() -> Array:
	var isz := Vector2(image_size())
	var s := minf(canvas.size.x / isz.x, canvas.size.y / isz.y)
	if s >= 1.0:
		s = floorf(s)
	s = maxf(s, 0.1)
	var off := ((canvas.size - isz * s) / 2).floor()
	return [s, off]


func to_image(p: Vector2) -> Vector2i:
	var f := _fit()
	var q: Vector2 = ((p - f[1]) / f[0]).floor()
	var isz := image_size()
	return Vector2i(clampi(int(q.x), 0, isz.x), clampi(int(q.y), 0, isz.y))


## ドラッグの始まりと終わり（絵の座標）から範囲を決める（テストからも呼ぶ）。
func set_region_by_drag(a: Vector2i, b: Vector2i) -> void:
	var k := selected_key()
	if k == "":
		return
	var x0 := mini(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var w := absi(a.x - b.x)
	var h := absi(a.y - b.y)
	if w < 1 or h < 1:
		return
	regions[k] = [x0, y0, w, h]
	_update_info()
	canvas.queue_redraw()


func _on_canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_drag_from = to_image(e.position)
			_drag_to = _drag_from
		elif _drag_from != null:
			set_region_by_drag(_drag_from, to_image(e.position))
			_drag_from = null
		canvas.queue_redraw()
	elif e is InputEventMouseMotion and _drag_from != null:
		_drag_to = to_image(e.position)
		info.text = "%d, %d 〜 %d, %d" % [_drag_from.x, _drag_from.y, _drag_to.x, _drag_to.y]
		canvas.queue_redraw()


func _draw_canvas() -> void:
	var f := _fit()
	var s: float = f[0]
	var off: Vector2 = f[1]
	var isz := Vector2(image_size())
	if texture != null:
		canvas.draw_texture_rect(texture, Rect2(off, isz * s), false)
	else:
		canvas.draw_rect(Rect2(off, isz * s), Color(0.15, 0.15, 0.18))
		for x in range(0, int(isz.x), 40):
			canvas.draw_line(off + Vector2(x, 0) * s, off + Vector2(x, isz.y) * s, Color(1, 1, 1, 0.08))
		for y in range(0, int(isz.y), 40):
			canvas.draw_line(off + Vector2(0, y) * s, off + Vector2(isz.x, y) * s, Color(1, 1, 1, 0.08))
	var sel := selected_key()
	var font := canvas.get_theme_default_font()
	for t in targets:
		var r = regions.get(t["key"])
		if not r is Array or r.size() < 4:
			continue
		var rect := Rect2(off + Vector2(r[0], r[1]) * s, Vector2(r[2], r[3]) * s)
		var on: bool = t["key"] == sel
		var col := Color(1, 0.85, 0.2) if on else Color(0.4, 0.8, 1.0)
		canvas.draw_rect(rect, Color(col, 0.18 if on else 0.08))
		canvas.draw_rect(rect, col, false, 2.0 if on else 1.0)
		if font != null:
			canvas.draw_string(font, rect.position + Vector2(3, 14), String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	if _drag_from != null:
		var a := off + Vector2(_drag_from) * s
		var b := off + Vector2(_drag_to) * s
		canvas.draw_rect(Rect2(a, b - a).abs(), Color(1, 1, 1, 0.9), false, 1.0)


func _update_info() -> void:
	var k := selected_key()
	var r = regions.get(k)
	if k == "":
		info.text = ""
	elif r is Array:
		info.text = "x %d, y %d, 幅 %d, 高さ %d\n絵の上をドラッグして決め直せます。" % r
	else:
		info.text = "範囲なし。\n絵の上をドラッグして決めます。"
