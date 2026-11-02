class_name AdvScreen
extends Control
## 画面（表示層）。元の解像度で作り、テンプレートの区割りに従って、画像の層、メッセージの窓、
## コマンドの窓、入力欄を置く。切り替え演出と画面効果もここで行う（フィルターは AdvDisplay がかける）。

const READABLE_FONTS := ["BIZ UDGothic", "BIZ UDPGothic", "Meiryo", "Hiragino Sans", "Noto Sans CJK JP", "sans-serif"]
const FALLBACK_FONTS := ["MS Gothic", "ＭＳ ゴシック", "Osaka-Mono", "Noto Sans Mono CJK JP",
	"Noto Sans CJK JP", "IPAGothic", "VL Gothic", "monospace"]

var tpl: AdvTemplate
var picture: Control
var layers: Dictionary = {}          ## 層の名前 → Control
var message_label: RichTextLabel
var wait_mark: Label
var command_select: AdvCommandSelect
var command_line: AdvCommandLine
var hotspot_layer: AdvHotspotLayer
var readable: bool = false           ## 読みやすいフォントを使う（モダン機能 readable_font）
## 素材IDからパスを引く関数（フォントやマスク画像に使う）。func(kind, id) -> String
var resolver: Callable

var _msg_win: Panel
var _cmd_win: Panel
var _overlay: Control                ## 画面効果の重ね描き
var _tint: ColorRect                 ## 続けてかける色味（tint）
var _speed: float = 40.0             ## 1秒あたりの文字数。0 なら一度に表示
var _shown: float = 0.0
var _typing: bool = false


func build(template: AdvTemplate) -> void:
	tpl = template
	for c in get_children():
		remove_child(c)
		c.queue_free()
	layers.clear()
	_tint = null
	var sz := tpl.screen_size
	position = Vector2.ZERO
	size = Vector2(sz)
	custom_minimum_size = Vector2(sz)
	clip_contents = true
	theme = _make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_speed = float(tpl.get_section("text").get("speed", 40))

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = tpl.color(int(tpl.get_section("layout").get("background", 0)))
	bg.size = Vector2(sz)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	picture = Control.new()
	picture.name = "Picture"
	picture.clip_contents = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	for layer_name in tpl.get_section("layout").get("layers", ["bg"]):
		var l := Control.new()
		l.name = String(layer_name)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(l)
		layers[String(layer_name)] = l
	hotspot_layer = AdvHotspotLayer.new()
	hotspot_layer.name = "Hotspots"
	hotspot_layer.tpl = tpl
	picture.add_child(hotspot_layer)

	_msg_win = _window("MessageWindow")
	message_label = RichTextLabel.new()
	message_label.name = "Text"
	message_label.bbcode_enabled = true
	message_label.scroll_active = false
	message_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_win.add_child(message_label)
	wait_mark = Label.new()
	wait_mark.text = "▼"
	wait_mark.visible = false
	_msg_win.add_child(wait_mark)

	if tpl.region_rect("commands").size != Vector2i.ZERO:
		_cmd_win = _window("CommandWindow")
		command_select = AdvCommandSelect.new()
		command_select.name = "CommandSelect"
		_cmd_win.add_child(command_select)
	if tpl.region_rect("input").size != Vector2i.ZERO:
		command_line = AdvCommandLine.new()
		command_line.name = "CommandLine"
		add_child(command_line)

	_overlay = Control.new()
	_overlay.name = "Effects"
	_overlay.size = Vector2(sz)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	apply_layout()


## 読みやすいフォントに切り替える。
func set_readable(on: bool) -> void:
	readable = on
	theme = _make_theme()


## 区割りを今のレイアウトに合わせて置き直す（layout.set で切り替えたときにも呼ぶ）。
func apply_layout() -> void:
	_place(picture, tpl.region_rect("picture"))
	if hotspot_layer != null:
		hotspot_layer.size = picture.size
	for l in layers.values():
		l.size = picture.size
		for g in l.get_children():
			for c in g.get_children():
				if c is Control:
					c.size = picture.size
	_place_window(_msg_win, tpl.region_rect("message"))
	if message_label != null:
		message_label.position = Vector2(8, 4)
		message_label.size = _msg_win.size - Vector2(16, 8)
		wait_mark.position = Vector2(_msg_win.size.x - 22, _msg_win.size.y - 22)
	if _cmd_win != null:
		_place_window(_cmd_win, tpl.region_rect("commands"))
		command_select.position = Vector2(4, 4)
		command_select.size = _cmd_win.size - Vector2(8, 8)
	if command_line != null:
		var r := tpl.region_rect("input")
		command_line.visible = r.size != Vector2i.ZERO
		_place(command_line, r)


func _place(c: Control, r: Rect2i) -> void:
	c.position = Vector2(r.position)
	c.size = Vector2(r.size)


func _place_window(w: Panel, r: Rect2i) -> void:
	w.visible = r.size != Vector2i.ZERO
	_place(w, r)


## 枠つきの窓（window_skin が box のとき：パレットの色で単純な枠線を描く。nine_patch は画像）。
func _window(node_name: String) -> Panel:
	var p := Panel.new()
	p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var skin: Dictionary = tpl.get_section("ui").get("window_skin", {})
	if String(skin.get("type", "box")) == "nine_patch" and resolver.is_valid():
		var path := String(resolver.call("image", String(skin.get("image", ""))))
		var tex := load(path) as Texture2D if path != "" else null
		if tex != null:
			var sbt := StyleBoxTexture.new()
			sbt.texture = tex
			var m: Array = skin.get("margins", [4, 4, 4, 4])
			sbt.texture_margin_left = m[0]
			sbt.texture_margin_top = m[1]
			sbt.texture_margin_right = m[2]
			sbt.texture_margin_bottom = m[3]
			p.add_theme_stylebox_override("panel", sbt)
			add_child(p)
			return p
	var sb := StyleBoxFlat.new()
	sb.bg_color = tpl.color(int(skin.get("fill", 0)))
	sb.set_border_width_all(int(skin.get("border", 1)))
	sb.border_color = tpl.color(int(skin.get("pal", 7)))
	sb.anti_aliasing = false
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


## テンプレートの fonts.main。素材が見つからなければ、OSのフォントを使う。
## 行の高さは fonts.main.line_height（省略時は文字の大きさ）にそろえる。当時の画面のように、16ドットの文字なら16行ごとに並ぶ。
func _main_font() -> Font:
	var fonts := tpl.get_section("fonts")
	var main: Dictionary = fonts.get("readable" if readable and fonts.has("readable") else "main", {})
	var fsize := int(main.get("size", 16))
	var font: Font = null
	var asset := String(main.get("asset", ""))
	if asset != "" and resolver.is_valid():
		var path := String(resolver.call("font", asset))
		if path != "":
			font = load(path) as Font
	if font == null:
		var sf := SystemFont.new()
		if readable:
			# 読みやすいフォント：なめらかに描く
			sf.font_names = PackedStringArray(READABLE_FONTS)
			sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		else:
			sf.font_names = PackedStringArray(FALLBACK_FONTS)
			sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			sf.hinting = TextServer.HINTING_NONE
			sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font = sf
	var line_h := int(main.get("line_height", fsize))
	var extra := int(round(font.get_height(fsize))) - line_h
	if extra == 0:
		return font
	var fv := FontVariation.new()
	fv.base_font = font
	fv.spacing_top = -int(extra / 2.0)
	fv.spacing_bottom = -(extra - int(extra / 2.0))
	return fv


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = _main_font()
	var fsize := int(tpl.get_section("fonts").get("main", {}).get("size", 16))
	th.default_font_size = fsize
	var fg := tpl.color(int(tpl.get_section("text").get("color", 7)))
	var hl := tpl.color(int(tpl.get_section("ui").get("highlight", 1)))
	var dim := tpl.color(8) if tpl.preset.get("palette", PackedColorArray()).size() > 8 else tpl.color(1)
	for type in ["Label", "Button", "LineEdit", "RichTextLabel"]:
		th.set_color("font_color" if type != "RichTextLabel" else "default_color", type, fg)
	th.set_color("font_hover_color", "Button", fg)
	th.set_color("font_focus_color", "Button", fg)
	th.set_color("font_pressed_color", "Button", fg)
	th.set_color("font_disabled_color", "Button", dim)
	th.set_color("font_uneditable_color", "LineEdit", dim)
	th.set_color("caret_color", "LineEdit", fg)
	# ボタンは行の高さを詰めて、コマンドの窓に多く並べられるようにする
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	var on := StyleBoxFlat.new()
	on.bg_color = hl
	on.anti_aliasing = false
	on.content_margin_left = 2
	on.content_margin_top = 0
	on.content_margin_bottom = 0
	for st in ["normal", "disabled"]:
		th.set_stylebox(st, "Button", empty)
	for st in ["hover", "pressed", "focus"]:
		th.set_stylebox(st, "Button", on)
	var le := StyleBoxFlat.new()
	le.bg_color = tpl.color(0)
	le.set_border_width_all(1)
	le.border_color = tpl.color(7)
	le.anti_aliasing = false
	le.content_margin_left = 6
	le.content_margin_top = 0
	le.content_margin_bottom = 0
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", le)
	th.set_stylebox("read_only", "LineEdit", le)
	return th


# ---------------------------------------------------------------- 画像と切り替え演出

## 画像を表示する。path が空なら代わりの表示（IDを書いた枠）を出す。tr は AdvVisuals.resolve_transition の結果。
## 切り替え演出が終わるまで待つ（await できる）。
func show_image(layer: String, id: String, path: String, tr: Dictionary = {"type": "cut"}) -> void:
	var l: Control = layers.get(layer, layers.get("bg"))
	if l == null:
		return
	var old := l.get_children()
	var g := CanvasGroup.new()
	g.name = "Image"
	g.add_child(_image_node(id, path))
	l.add_child(g)
	await _transition(g, old, tr, false)
	for o in old:
		if is_instance_valid(o):
			o.queue_free()


func hide_image(layer: String, tr: Dictionary = {"type": "cut"}) -> void:
	var l: Control = layers.get(layer)
	if l == null:
		return
	var old := l.get_children()
	if not old.is_empty():
		await _transition(null, old, tr, true)
	for o in old:
		if is_instance_valid(o):
			o.queue_free()


func _image_node(id: String, path: String) -> Control:
	var tex: Texture2D = load(path) as Texture2D if path != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.size = picture.size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var ph := ColorRect.new()
	ph.color = tpl.color(9 if tpl.preset.get("palette", PackedColorArray()).size() > 9 else 1)
	ph.size = picture.size
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lb := Label.new()
	lb.text = "[%s]" % id
	lb.position = Vector2(8, 8)
	ph.add_child(lb)
	return ph


## 切り替え演出を行う。new_g が現れる側、old は消える側。hiding なら old を消すだけ。
func _transition(new_g: CanvasGroup, old: Array, tr: Dictionary, hiding: bool) -> void:
	var t := String(tr.get("type", "cut"))
	var dur := float(tr.get("duration", AdvVisuals.DEFAULT_DURATION))
	if t == "cut" or dur <= 0.0:
		return
	if t == "fade_color":
		var cover := ColorRect.new()
		cover.color = Color.html(String(tr.get("color", "#000000")))
		cover.size = picture.size
		cover.modulate.a = 0.0
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(cover)
		if new_g != null:
			new_g.visible = false
		await _tween(cover, "modulate:a", 0.0, 1.0, dur * 0.5)
		for o in old:
			if is_instance_valid(o):
				o.visible = false
		if new_g != null:
			new_g.visible = true
		await _tween(cover, "modulate:a", 1.0, 0.0, dur * 0.5)
		cover.queue_free()
		return
	var region := Rect2(picture.position, picture.size)
	var rule: Texture2D = tr.get("rule_texture")
	if t == "mosaic":
		var half := dur * 0.5
		var mo := AdvVisuals.build_transition_material(tr, region, size)
		mo.set_shader_parameter("invert", true)
		for o in old:
			if o is CanvasItem:
				o.material = mo
		if new_g != null:
			new_g.visible = false
		await _tween(mo, "shader_parameter/progress", 0.0, 1.0, half)
		for o in old:
			if is_instance_valid(o):
				o.visible = false
		if new_g == null:
			return
		var mn := AdvVisuals.build_transition_material(tr, region, size)
		new_g.material = mn
		new_g.visible = true
		await _tween(mn, "shader_parameter/progress", 0.0, 1.0, half)
		new_g.material = null
		return
	var mat := AdvVisuals.build_transition_material(tr, region, size, rule)
	if hiding:
		mat.set_shader_parameter("invert", true)
		for o in old:
			if o is CanvasItem:
				o.material = mat
	else:
		new_g.material = mat
	await _tween(mat, "shader_parameter/progress", 0.0, 1.0, dur)
	if new_g != null and is_instance_valid(new_g):
		new_g.material = null


func _tween(obj: Object, prop: String, from: Variant, to: Variant, dur: float) -> void:
	if dur <= 0.0:
		obj.set_indexed(prop, to)
		return
	var tw := create_tween()
	tw.tween_property(obj, prop, to, dur).from(from)
	await tw.finished


# ---------------------------------------------------------------- 画面効果

## 画面効果を行う（7.4）。終わるまで待つ（await できる）。
func play_effect(name: String, args: Dictionary) -> void:
	var dur := float(args.get("duration", AdvVisuals.DEFAULT_DURATION))
	match name:
		"flash":
			var n := maxi(1, int(args.get("count", 1)))
			var r := ColorRect.new()
			r.color = Color.html(String(args.get("color", "#ffffff")))
			r.size = size
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_overlay.add_child(r)
			for i in n:
				await _tween(r, "modulate:a", 1.0, 0.0, dur / n)
			r.queue_free()
		"shake":
			var amp := float(args.get("amplitude", 4.0))
			var ax := String(args.get("axis", "both"))
			var t := 0.0
			while t < dur:
				var k := amp * (1.0 - t / dur)
				var off := Vector2(randf_range(-k, k) if ax != "y" else 0.0, randf_range(-k, k) if ax != "x" else 0.0)
				position = off.round()
				await get_tree().process_frame
				t += get_process_delta_time()
			position = Vector2.ZERO
		"invert", "raster":
			var r := _effect_rect(0 if name == "invert" else 2)
			var mat: ShaderMaterial = r.material
			mat.set_shader_parameter("amount", float(args.get("amount", 1.0)))
			if name == "raster":
				mat.set_shader_parameter("amplitude", float(args.get("amplitude", 4.0)))
				mat.set_shader_parameter("wavelength", float(args.get("wavelength", 32.0)))
				mat.set_shader_parameter("phase", 0.0)
				await _tween(mat, "shader_parameter/phase", 0.0, float(args.get("speed", 6.0)) * dur, dur)
			else:
				await get_tree().create_timer(dur).timeout
			r.queue_free()
		"tint":
			# 色味は続けてかける。amount を 0 にすると戻る
			if _tint == null:
				_tint = _effect_rect(1)
				_tint.material.set_shader_parameter("amount", 0.0)
			var mat: ShaderMaterial = _tint.material
			mat.set_shader_parameter("tint_color", Color.html(String(args.get("color", "#b38c59"))))
			var to := float(args.get("amount", 1.0))
			await _tween(mat, "shader_parameter/amount", mat.get_shader_parameter("amount"), to, dur)
			if to <= 0.0:
				_tint.queue_free()
				_tint = null
		"scroll", "zoom":
			var l: Control = layers.get(String(args.get("layer", "bg")))
			if l == null:
				return
			if name == "scroll":
				var dirs := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}
				var v: Vector2 = dirs.get(String(args.get("direction", "left")), Vector2.LEFT) * float(args.get("distance", 32))
				await _tween(l, "position", l.position, l.position + v, dur)
			else:
				var c: Array = args.get("center", [0.5, 0.5])
				l.pivot_offset = Vector2(float(c[0]), float(c[1])) * picture.size
				await _tween(l, "scale", l.scale, Vector2.ONE * float(args.get("scale", 2.0)), dur)
		_:
			AdvDiag.debug_warn("UNSUPPORTED", "まだ使えない画面効果です: %s" % name, "Effect not supported yet: %s" % name)


func _effect_rect(mode: int) -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = AdvVisuals.EFFECT_SHADER
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("screen_px", size)
	r.material = mat
	_overlay.add_child(r)
	return r


## 画像の層の位置と拡大を元に戻す（scroll、zoom の後、新しい背景にしたとき）。
func reset_layer(layer: String) -> void:
	var l: Control = layers.get(layer)
	if l != null:
		l.position = Vector2.ZERO
		l.scale = Vector2.ONE


# ---------------------------------------------------------------- 文章

## 文章を表示する（文字送りあり）。name があれば「名前「本文」」の形にする。
func show_text(bbcode: String, speaker_name: String = "", instant: bool = false) -> void:
	var t := bbcode
	if speaker_name != "":
		var nc := tpl.color(int(tpl.get_section("text").get("name_color", 6))).to_html(false)
		t = "[color=#%s]%s[/color]「%s」" % [nc, AdvTextMarkup._escape(speaker_name), bbcode]
	message_label.text = t
	wait_mark.visible = false
	if instant or _speed <= 0.0:
		complete_text()
	else:
		_shown = 0.0
		message_label.visible_characters = 0
		_typing = true


## 文字速度（1秒あたりの文字数。0 なら一度に表示）。
func set_text_speed(chars_per_sec: float) -> void:
	_speed = chars_per_sec


func clear_text() -> void:
	message_label.text = ""
	wait_mark.visible = false
	_typing = false


func is_typing() -> bool:
	return _typing


func complete_text() -> void:
	_typing = false
	message_label.visible_characters = -1


func set_wait_mark(on: bool) -> void:
	wait_mark.visible = on


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += _speed * delta
	message_label.visible_characters = int(_shown)
	if int(_shown) >= message_label.get_total_character_count():
		complete_text()
