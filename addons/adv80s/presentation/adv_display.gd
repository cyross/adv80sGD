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
	viewport.add_child(screen)
	resized.connect(_relayout)


## テンプレートに合わせて作り直す。filter_override は実行時の自由選択（null ならテンプレートどおり）。
func setup(template: AdvTemplate, filter_override: Variant = null) -> void:
	tpl = template
	var sz := tpl.screen_size
	viewport.size = sz
	container.size = Vector2(sz)
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


func _relayout() -> void:
	if tpl == null:
		return
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
