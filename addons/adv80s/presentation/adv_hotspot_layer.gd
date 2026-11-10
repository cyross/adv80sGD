class_name AdvHotspotLayer
extends Control
## 画像の上に重ねる、調べられる場所の層。
## - 画面選択（入力UI click）：押した場所にある物を hotspot_clicked で知らせる
## - 調べられる場所の表示（モダン機能 hotspot）：show_all が true の間、枠と名前を出す。マウスを重ねた物の名前も出す
## - 試したコマンドの表示（tried_marks）：まだ試していない物に印を付ける
## 範囲（region）は画像の層の中の座標（元の解像度のピクセル）。

signal hotspot_clicked(hotspot: Dictionary)
signal long_pressed(hotspot: Dictionary)   ## タッチで長押しした（右クリックの代わり。場所になければ空）

const LONG_PRESS_SEC := 0.5      ## 長押しと見なす時間
const LONG_PRESS_MOVE := 8.0     ## これより動いたら長押しにしない（絵の窓の座標）

var tpl: AdvTemplate
var hotspots: Array = []
var show_all: bool = false       ## すべての枠を出す
var show_hover: bool = false     ## マウスを重ねた物の名前を出す
var show_new: bool = false       ## まだ試していない物に印を付ける
var _hover: Dictionary = {}
var long_press: bool = false     ## タッチの長押しを使う（絵の中の対象を選ぶコマンド方式。4.5）
var _touch: Dictionary = {}      ## 押している途中のタッチ {pos, at, fired}
var _kbd: Dictionary = {}        ## キーボードやゲームパッドで選んでいる場所（マウスを動かすと外れる）
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
	if not _touch.is_empty() and not _touch["fired"] and Time.get_ticks_msec() - int(_touch["at"]) >= int(LONG_PRESS_SEC * 1000):
		_touch["fired"] = true
		long_pressed.emit(hotspot_at(_touch["pos"]))
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
	_kbd = {}
	queue_redraw()


## キーボードやゲームパッドで、次（前）の場所を選ぶ。選べる場所がなければ何もしない。
func focus_next(dir: int = 1) -> Dictionary:
	var list := hotspots.filter(func(h): return rect_of(h).size != Vector2.ZERO)
	if list.is_empty():
		_kbd = {}
		return {}
	var i := -1 if dir > 0 else 0
	for k in list.size():
		if list[k].get("id") == _kbd.get("id"):
			i = k
	_kbd = list[posmod(i + dir, list.size())]
	queue_redraw()
	return _kbd


## キーボードやゲームパッドで選んでいる場所（なければ空）。
func focused() -> Dictionary:
	return _kbd


func clear_focus() -> void:
	if not _kbd.is_empty():
		_kbd = {}
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


## いまマウスが重なっている場所（なければ空）。キーボードで選んでいれば、その場所。
func hovered() -> Dictionary:
	if not _kbd.is_empty():
		return _kbd
	return hotspot_at(get_local_mouse_position())


func _gui_input(event: InputEvent) -> void:
	# タッチ（タッチから作られたマウスの操作）：離したときにクリック、押し続けると長押し
	if long_press and event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_touch = {"pos": event.position, "at": Time.get_ticks_msec(), "fired": false}
			elif not _touch.is_empty():
				var fired: bool = _touch["fired"]
				var at: Vector2 = _touch["pos"]
				_touch = {}
				var th := hotspot_at(at)
				if not fired and not th.is_empty():
					hotspot_clicked.emit(th)
			accept_event()
			return
		if event is InputEventMouseMotion and not _touch.is_empty() and event.position.distance_to(_touch["pos"]) > LONG_PRESS_MOVE:
			_touch = {}
	if event is InputEventMouseMotion:
		clear_focus()
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
	if not _kbd.is_empty():
		var kr := rect_of(_kbd)
		draw_rect(kr, hl, false, 1.0)
		if not show_all:
			_label(font, fsize, kr.position + Vector2(2, -2), String(_kbd.get("label", _kbd["id"])), hl, fg)
	elif show_hover and not _hover.is_empty() and not show_all:
		var hr := rect_of(_hover)
		_label(font, fsize, hr.position + Vector2(2, -2), String(_hover.get("label", _hover["id"])), hl, fg)


func _label(font: Font, fsize: int, pos: Vector2, text: String, bg: Color, fg: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := Vector2(clampf(pos.x, 0, size.x - w - 4), maxf(pos.y, fsize))
	draw_rect(Rect2(p - Vector2(2, fsize), Vector2(w + 4, fsize + 2)), bg, true)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
