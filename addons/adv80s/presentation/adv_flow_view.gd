class_name AdvFlowView
extends Control
## フローチャートの図（モダン機能 flowchart）。点を左から右へ、つながりの深さの順に並べる。
## 到達した点は名前を出し、まだの点は「？？？」にする。到達して再開できる点を押すと node_chosen を出す。

signal node_chosen(id: String)

var tpl: AdvTemplate
var flow: Dictionary = {}
var _boxes: Dictionary = {}   ## 点ID → Rect2
var BOX := Vector2(112, 20)
const GAP := Vector2(24, 8)


func setup(template: AdvTemplate, flow_data: Dictionary) -> void:
	tpl = template
	flow = flow_data
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_layout()
	queue_redraw()


func _layout() -> void:
	# 箱の大きさは、いちばん長い名前に合わせる（画面に入った後でないとフォントが決まらない）
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var w := font.get_string_size("？？？", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	for n in flow.get("nodes", []):
		if n.get("reached", false):
			w = maxf(w, font.get_string_size(String(n.get("label", n["id"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
	BOX = Vector2(ceilf(w) + 8, fsize + 4)
	_boxes.clear()
	var depth := {}
	var nodes: Array = flow.get("nodes", [])
	var edges: Array = flow.get("edges", [])
	var incoming := {}
	for e in edges:
		incoming[String(e["to"])] = true
	for n in nodes:
		if not incoming.has(n["id"]):
			depth[n["id"]] = 0
	# つながりをたどって深さを決める（循環しても止まるように回数を限る）
	for _i in nodes.size():
		for e in edges:
			var f := String(e["from"])
			var t := String(e["to"])
			if depth.has(f):
				depth[t] = maxi(int(depth.get(t, 0)), int(depth[f]) + 1)
	var rows := {}
	for n in nodes:
		var d: int = depth.get(n["id"], 0)
		var row: int = rows.get(d, 0)
		rows[d] = row + 1
		_boxes[n["id"]] = Rect2(Vector2(d * (BOX.x + GAP.x), row * (BOX.y + GAP.y)), BOX)
	var size_needed := Vector2.ZERO
	for r in _boxes.values():
		size_needed = size_needed.max(r.end)
	custom_minimum_size = size_needed + Vector2(4, 4)


func _draw() -> void:
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var line_c := tpl.color(7)
	for e in flow.get("edges", []):
		var a: Rect2 = _boxes.get(String(e["from"]), Rect2())
		var b: Rect2 = _boxes.get(String(e["to"]), Rect2())
		if a.size != Vector2.ZERO and b.size != Vector2.ZERO:
			draw_line(Vector2(a.end.x, a.get_center().y), Vector2(b.position.x, b.get_center().y), line_c, 1.0)
	for n in flow.get("nodes", []):
		var r: Rect2 = _boxes[n["id"]]
		var reached := bool(n.get("reached", false))
		var fill := tpl.color(int(tpl.get_section("ui").get("highlight", 1))) if reached else tpl.color(0)
		draw_rect(r, fill, true)
		draw_rect(r, line_c, false, 1.0)
		var label := String(n.get("label", n["id"])) if reached else "？？？"
		draw_string(font, r.position + Vector2(4, r.size.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, fsize, line_c)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for n in flow.get("nodes", []):
			if _boxes[n["id"]].has_point(event.position) and n.get("can_jump", false):
				node_chosen.emit(String(n["id"]))
				accept_event()
				return
