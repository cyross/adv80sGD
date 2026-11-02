class_name AdvHotspotLayer
extends Control
## 画像の上に重ねる、調べられる場所の層。
## - 画面選択（入力UI click）：押した場所にある物を hotspot_clicked で知らせる
## - 調べられる場所の表示（モダン機能 hotspot）：show_all が true の間、枠と名前を出す。マウスを重ねた物の名前も出す
## - 試したコマンドの表示（tried_marks）：まだ試していない物に印を付ける
## 範囲（region）は画像の層の中の座標（元の解像度のピクセル）。

signal hotspot_clicked(hotspot: Dictionary)

var tpl: AdvTemplate
var hotspots: Array = []
var show_all: bool = false       ## すべての枠を出す
var show_hover: bool = false     ## マウスを重ねた物の名前を出す
var show_new: bool = false       ## まだ試していない物に印を付ける
var _hover: Dictionary = {}
## スプライトを探す関数 func(id) -> AdvSprite（物に "sprite" があるとき、その見えている範囲を使う）
var sprite_lookup: Callable


## 調べられる場所の範囲（絵の窓の座標）。スプライトに結び付いていて見えていなければ空。
func rect_of(h: Dictionary) -> Rect2:
	if h.has("sprite") and sprite_lookup.is_valid():
		var sp = sprite_lookup.call(String(h["sprite"]))
		if sp == null or not sp.visible:
			return Rect2()
		return sp.bounds()
	var r: Array = h.get("region", [])
	if r.size() >= 4:
		return Rect2(r[0], r[1], r[2], r[3])
	return Rect2()


## 動くスプライトに合わせて描き直す。
func _process(_d: float) -> void:
	if show_all or show_new or not _hover.is_empty():
		for h in hotspots:
			if h.has("sprite"):
				queue_redraw()
				return


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_hotspots(list: Array) -> void:
	hotspots = list
	_hover = {}
	queue_redraw()


func hotspot_at(p: Vector2) -> Dictionary:
	for i in range(hotspots.size() - 1, -1, -1):
		var h: Dictionary = hotspots[i]
		if h.has("sprite") and sprite_lookup.is_valid():
			# スプライトの透明でない部分だけ
			var sp = sprite_lookup.call(String(h["sprite"]))
			if sp != null and sp.is_opaque_at(p):
				return h
			continue
		if rect_of(h).has_point(p):
			return h
	return {}


## いまマウスが重なっている場所（なければ空）。
func hovered() -> Dictionary:
	return hotspot_at(get_local_mouse_position())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := hotspot_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := hotspot_at(event.position)
		if not h.is_empty():
			hotspot_clicked.emit(h)
			accept_event()


func _draw() -> void:
	if tpl == null:
		return
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var hl := tpl.color(int(tpl.get_section("ui").get("highlight", 1)))
	var fg := tpl.color(int(tpl.get_section("text").get("color", 7)))
	for h in hotspots:
		var rect := rect_of(h)
		if rect.size == Vector2.ZERO:
			continue
		if show_all:
			draw_rect(rect, fg, false, 1.0)
			_label(font, fsize, rect.position + Vector2(2, -2), String(h.get("label", h["id"])), hl, fg)
		if show_new and h.get("new", false):
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - 6, 0), Vector2(6, 6)), hl, true)
	if show_hover and not _hover.is_empty() and not show_all:
		var hr := rect_of(_hover)
		_label(font, fsize, hr.position + Vector2(2, -2), String(_hover.get("label", _hover["id"])), hl, fg)


func _label(font: Font, fsize: int, pos: Vector2, text: String, bg: Color, fg: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := Vector2(clampf(pos.x, 0, size.x - w - 4), maxf(pos.y, fsize))
	draw_rect(Rect2(p - Vector2(2, fsize), Vector2(w + 4, fsize + 2)), bg, true)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
