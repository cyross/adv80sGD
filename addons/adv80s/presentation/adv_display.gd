class_name AdvDisplay
extends Control
## 元の解像度の画面（AdvScreen）を SubViewport に描き、整数倍に拡大して、フィルターをかけて表示する。
## - 640x200 などの縦2倍表示のモードは、縦だけさらに2倍にする
## - 縦横比補正（テンプレートの display.aspect_correction、またはフィルター aspect）は縦を伸ばして行う
## - 標準のフィルターは1回の描画でまとめてかけ、自作のフィルターは画面を読み直す段として後ろに重ねる

var tpl: AdvTemplate
var screen: AdvScreen
var viewport: SubViewport
var container: SubViewportContainer
var frame: Control                     ## 見える範囲で切り抜く枠
var filters: Array = []
var filters_enabled: bool = true

var _material: ShaderMaterial
var _passes: Array = []                ## 自作フィルターの段（BackBufferCopy と ColorRect）
var _aspect: bool = false
var _keep_vp: SubViewport              ## 減色しない範囲（外字の keep_colors: true）を描く画面。使うときだけ作る
var _keep_root: Control
var _keep_on: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	frame = Control.new()
	frame.name = "Frame"
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(frame)
	container = SubViewportContainer.new()
	container.name = "Native"
	container.stretch = false
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(container)
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.transparent_bg = false
	viewport.handle_input_locally = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	screen = AdvScreen.new()
	screen.name = "Screen"
	screen.keep_layer_provider = keep_layer
	screen.keep_mask_toggle = set_keep_mask
	viewport.add_child(screen)
	resized.connect(_relayout)


## テンプレートに合わせて作り直す。filter_override は実行時の自由選択（null ならテンプレートどおり）。
func setup(template: AdvTemplate, filter_override: Variant = null) -> void:
	tpl = template
	var sz := tpl.screen_size
	viewport.size = sz
	container.size = Vector2(sz)
	if _keep_vp != null:
		_keep_vp.size = sz
	screen.build(tpl)
	set_filters(AdvVisuals.resolve_filters(tpl, filter_override))


func set_filters(list: Array) -> void:
	filters = list
	for p in _passes:
		p.queue_free()
	_passes.clear()
	var built := AdvVisuals.build_filter_material(filters, tpl)
	_material = built["material"]
	_material.set_shader_parameter("enabled", filters_enabled)
	container.material = _material
	_apply_keep_mask()
	_aspect = built["aspect"] or bool(tpl.get_section("display").get("aspect_correction", false))
	for p in built["passes"]:
		var mat := AdvVisuals.build_custom_pass(p, tpl)
		if mat == null:
			continue
		var bb := BackBufferCopy.new()
		bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(bb)
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.material = mat
		add_child(r)
		_passes.append(bb)
		_passes.append(r)
	_relayout()


## 減色しない範囲を描く Control（元の解像度の画面と同じ座標）。はじめて呼ばれたときに作る。
func keep_layer() -> Control:
	if _keep_vp == null:
		_keep_vp = SubViewport.new()
		_keep_vp.name = "KeepMask"
		_keep_vp.transparent_bg = true
		_keep_vp.disable_3d = true
		_keep_vp.gui_disable_input = true
		_keep_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		_keep_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_keep_vp.size = viewport.size
		add_child(_keep_vp)
		_keep_root = Control.new()
		_keep_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keep_vp.add_child(_keep_root)
	return _keep_root


## 減色しない範囲を使う・使わない（外字の keep_colors: true が出ているあいだだけ使う）。
func set_keep_mask(on: bool) -> void:
	_keep_on = on
	_apply_keep_mask()


func _apply_keep_mask() -> void:
	if _material == null:
		return
	var on := _keep_on and _keep_vp != null
	_material.set_shader_parameter("use_keep_mask", on)
	if on:
		_material.set_shader_parameter("keep_mask", _keep_vp.get_texture())


## フィルターをまとめて切り替える（モダン機能 filter_toggle）。
func set_filters_enabled(on: bool) -> void:
	filters_enabled = on
	if _material != null:
		_material.set_shader_parameter("enabled", on)
	for p in _passes:
		if p is CanvasItem:
			p.visible = on


## パレットの色を順に回す（画面効果 palette_cycle）。range は [最初の番号, 最後の番号]、speed は1秒あたりの段数。
## duration が 0 なら止めるまで続ける。speed を 0 にすると止める。減色でパレットを使っていないときは何もしない。
func palette_cycle(range_: Array, speed: float, duration: float) -> void:
	_cycle_id += 1
	var my_id := _cycle_id
	if _material == null or int(_material.get_shader_parameter("palette_size")) == 0:
		AdvDiag.debug_warn("UNSUPPORTED", "palette_cycle はパレットで減色しているときだけ使えます",
			"palette_cycle needs a palette-based reduce filter")
		return
	if speed <= 0.0 or range_.size() < 2:
		_material.set_shader_parameter("cycle_len", 0)
		return
	var a := int(range_[0])
	var b := int(range_[1])
	_material.set_shader_parameter("cycle_start", mini(a, b))
	_material.set_shader_parameter("cycle_len", absi(b - a) + 1)
	var t := 0.0
	var step := 0
	while my_id == _cycle_id and (duration <= 0.0 or t < duration):
		await get_tree().create_timer(1.0 / speed).timeout
		if my_id != _cycle_id:
			return
		t += 1.0 / speed
		step += 1
		_material.set_shader_parameter("cycle_offset", step)
	if my_id == _cycle_id:
		_material.set_shader_parameter("cycle_len", 0)


var _cycle_id := 0


## 表示の倍率（横, 縦）。
func display_scale() -> Vector2:
	if tpl == null:
		return Vector2.ONE
	var vis: Rect2i = tpl.preset.get("visible", Rect2i(Vector2i.ZERO, tpl.screen_size))
	var ld := 2.0 if bool(tpl.preset.get("line_double", false)) else 1.0
	var ac := 1.0
	if _aspect:
		ac = 1.0 / maxf(0.1, float(tpl.preset.get("pixel_aspect", 1.0)))
	var base := Vector2(vis.size) * Vector2(1.0, ld * ac)
	var avail := size if size.x > 0 and size.y > 0 else base
	var k := minf(avail.x / base.x, avail.y / base.y)
	k = floorf(k) if k >= 1.0 else k
	return Vector2(k, k * ld * ac)


## フィルターをかけない重ね物（filters: false の動画など）を置く場所。画面と同じ座標（元の解像度）で、表示の倍率で拡大する。
func unfiltered_overlay() -> Control:
	var o := get_node_or_null("Unfiltered") as Control
	if o == null:
		o = Control.new()
		o.name = "Unfiltered"
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		o.clip_contents = true
		add_child(o)
	move_child(o, get_child_count() - 1)
	_place_overlay(o)
	return o


func _place_overlay(o: Control) -> void:
	if tpl == null:
		return
	var s := display_scale()
	var vis: Rect2i = tpl.preset.get("visible", Rect2i(Vector2i.ZERO, tpl.screen_size))
	o.position = frame.position - Vector2(vis.position) * s
	o.size = Vector2(tpl.screen_size)
	o.scale = s


func _relayout() -> void:
	if tpl == null:
		return
	var uo := get_node_or_null("Unfiltered") as Control
	if uo != null:
		_place_overlay(uo)
	var s := display_scale()
	var vis: Rect2i = tpl.preset.get("visible", Rect2i(Vector2i.ZERO, tpl.screen_size))
	var out := Vector2(vis.size) * s
	frame.size = out
	frame.position = ((size - out) * 0.5).floor() if size.x > 0 else Vector2.ZERO
	container.scale = s
	container.position = -Vector2(vis.position) * s
	for p in _passes:
		if p is ColorRect:
			p.position = frame.position
			p.size = out
			(p.material as ShaderMaterial).set_shader_parameter("display_size", out)
