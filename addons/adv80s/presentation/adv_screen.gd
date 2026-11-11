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
var wait_mark: Control               ## クリック待ちの印（テンプレートの ui.wait_mark）
var page_mark: Control               ## ページ送り待ちの印（ui.page_mark。なければ wait_mark と同じ形）
## 文字送りが止まった理由：""（送り中）、"stop"（文字送りのタグ）、"page"（窓がいっぱい）、"end"（最後まで出した）
var halt: String = ""
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
var _text_clip: Control              ## 文章の窓の中の、見える範囲（ページごとに文章をずらす）
var _stops: Array = []               ## 文字送りのタグ [{at, kind, value}]（at は表示する文字の数）
var _stop_i: int = 0                 ## 次の止まる位置
var _stop: Dictionary = {}           ## いま止まっている文字送りのタグ
var _limit: int = 0                  ## 今回の文字送りで出す文字の数
var _page_top: int = 0               ## いまのページの先頭の行
var _inline_speed: float = -1.0      ## [speed] で変えた速さ（-1 なら _speed）
var _since_wait: int = 0             ## 最後に待ってから出した文字の数


func build(template: AdvTemplate) -> void:
	tpl = template
	_keep_dirty = true
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
	sprite_layers.clear()
	# 画面全体の層のうち、名前が back で始まるものは絵の窓より奥
	var screen_layer_names: Array = tpl.get_section("layout").get("screen_layers", ["back", "front"])
	for n in screen_layer_names:
		if String(n).begins_with("back"):
			_add_sprite_layer(self, String(n), true)

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
		_add_sprite_layer(picture, String(layer_name), false)
	hotspot_layer = AdvHotspotLayer.new()
	hotspot_layer.name = "Hotspots"
	hotspot_layer.tpl = tpl
	picture.add_child(hotspot_layer)

	_msg_win = _window("MessageWindow")
	_text_clip = Control.new()
	_text_clip.name = "TextClip"
	_text_clip.clip_contents = true
	_text_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_win.add_child(_text_clip)
	message_label = RichTextLabel.new()
	message_label.name = "Text"
	message_label.bbcode_enabled = true
	message_label.scroll_active = false
	message_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_clip.add_child(message_label)
	set_marks(null, null)

	if tpl.region_rect("commands").size != Vector2i.ZERO:
		_cmd_win = _window("CommandWindow")
		command_select = AdvCommandSelect.new()
		command_select.name = "CommandSelect"
		command_select.columns = maxi(1, int(tpl.get_section("inputs").get("command_columns", 2)))
		_cmd_win.add_child(command_select)
	if tpl.region_rect("input").size != Vector2i.ZERO:
		command_line = AdvCommandLine.new()
		command_line.name = "CommandLine"
		add_child(command_line)

	for n in screen_layer_names:
		if not String(n).begins_with("back"):
			_add_sprite_layer(self, String(n), true)
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
	set_text_style(_style_size, _style_color, _style_opacity)


var _style_size: float = 1.0
var _style_color: int = -1
var _style_opacity: float = 1.0


## 文章の表示調整（モダン機能 text_options）：文字の大きさの倍率、色（パレットの番号、-1 でテンプレートの色）、窓の背景の不透明度。
## ドットのフォントは整数倍でないと形が崩れるので、倍率は 1.0、1.5、2.0 のように選ばせる（1.5 は読みやすいフォント向け）。
func set_text_style(size_scale: float, color_index: int, opacity: float) -> void:
	_keep_dirty = true
	_style_size = size_scale
	_style_color = color_index
	_style_opacity = opacity
	if message_label == null:
		return
	var fsize := int(round(font_size * size_scale))
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		if is_equal_approx(size_scale, 1.0):
			message_label.remove_theme_font_size_override(key)
		else:
			message_label.add_theme_font_size_override(key, fsize)
	if color_index < 0:
		message_label.remove_theme_color_override("default_color")
	else:
		message_label.add_theme_color_override("default_color", tpl.color(color_index))
	var sb = _msg_win.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var c: Color = (sb as StyleBoxFlat).bg_color
		c.a = clampf(opacity, 0.0, 1.0)
		(sb as StyleBoxFlat).bg_color = c
	elif sb is StyleBoxTexture:
		_msg_win.self_modulate.a = clampf(opacity, 0.0, 1.0)


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
	# 窓の内側の余白（テンプレートの ui.window_padding [横, 縦]。枠の画像が太いときに広げる）
	var pad_a: Array = tpl.get_section("ui").get("window_padding", [8, 4])
	var pad := Vector2(float(pad_a[0]), float(pad_a[1]))
	if message_label != null:
		_text_clip.position = pad
		_text_clip.size = _msg_win.size - pad * 2
		message_label.size = Vector2(_text_clip.size.x, 100000)
		_scroll_to_page()
		_place_marks()
	if _cmd_win != null:
		_place_window(_cmd_win, tpl.region_rect("commands"))
		var cpad := Vector2(maxf(4, pad.x - 4), maxf(4, pad.y))
		command_select.position = cpad
		command_select.size = _cmd_win.size - cpad * 2
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


## テンプレートの fonts.main（読みやすいフォントのときは fonts.readable）。
## {asset, size, line_height} を1つ、または候補の配列で書く。配列なら、素材が見つかった最初のものを使う。
## どれも見つからなければ、OSのフォントを使う（大きさは最初の候補のもの）。
## 行の高さは line_height（省略時は文字の大きさ）にそろえる。当時の画面のように、16ドットの文字なら16行ごとに並ぶ。
## ドットのフォント（main）は、なめらかにせず、ドットのまま描く。
var font_size: int = 16


func _main_font() -> Font:
	var fonts := tpl.get_section("fonts")
	var key := "readable" if readable and fonts.has("readable") else "main"
	var entry = fonts.get(key, {})
	var cands: Array = entry if entry is Array else [entry]
	var main: Dictionary = cands[0] if not cands.is_empty() and cands[0] is Dictionary else {}
	var font: Font = null
	for c in cands:
		if not c is Dictionary:
			continue
		var asset := String(c.get("asset", "")).trim_prefix("font.")
		if asset == "" or not resolver.is_valid():
			continue
		var path := String(resolver.call("font", asset))
		if path == "":
			continue
		var f = load(path)
		if f is FontFile:
			var ff: FontFile = f.duplicate()
			if key == "main":
				ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				ff.hinting = TextServer.HINTING_NONE
				ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				ff.multichannel_signed_distance_field = false
				ff.generate_mipmaps = false
			font = ff
			main = c
			break
		elif f is Font:
			font = f
			main = c
			break
	var fsize := int(main.get("size", 16))
	font_size = fsize
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
	var fsize := font_size
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
## 層に画像を出す。visual は Texture2D か、組み立て済みの Control（動く画像を重ねたもの）。
func show_image(layer: String, id: String, path: String, tr: Dictionary = {"type": "cut"}, visual: Variant = null) -> void:
	var l: Control = layers.get(layer, layers.get("bg"))
	if l == null:
		return
	var old := l.get_children()
	var g := CanvasGroup.new()
	g.name = "Image"
	g.add_child(visual if visual is Control else _image_node(id, path, visual as Texture2D))
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


func _image_node(id: String, path: String, tex: Texture2D = null) -> Control:
	if tex == null and path != "":
		tex = AdvImages.first_texture(AdvImages.load_visual(path))
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
## area は演出をかける範囲 {region: 画面の中の範囲, screen: 画面の大きさ, host: 色で隠すときに覆いを置く Control}（既定は絵の窓）。
func _transition(new_g: CanvasGroup, old: Array, tr: Dictionary, hiding: bool, area: Dictionary = {}) -> void:
	var t := String(tr.get("type", "cut"))
	var region: Rect2 = area.get("region", Rect2(picture.position, picture.size))
	var screen_sz: Vector2 = area.get("screen", size)
	var host: Control = area.get("host", picture)
	var dur := float(tr.get("duration", AdvVisuals.DEFAULT_DURATION))
	if t == "cut" or dur <= 0.0:
		return
	if t == "fade_color":
		var cover := ColorRect.new()
		cover.color = Color.html(String(tr.get("color", "#000000")))
		cover.size = host.size
		cover.modulate.a = 0.0
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(cover)
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
	var rule: Texture2D = tr.get("rule_texture")
	if t == "mosaic":
		var half := dur * 0.5
		var mo := AdvVisuals.build_transition_material(tr, region, screen_sz)
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
		var mn := AdvVisuals.build_transition_material(tr, region, screen_sz)
		new_g.material = mn
		new_g.visible = true
		await _tween(mn, "shader_parameter/progress", 0.0, 1.0, half)
		new_g.material = null
		return
	var mat := AdvVisuals.build_transition_material(tr, region, screen_sz, rule)
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
# ---------------------------------------------------------------- スプライト（6.4）

## 層の名前 → スプライトを置く Node2D。絵の窓の層は絵の窓の座標、画面全体の層は画面の座標。
var sprite_layers: Dictionary = {}
var _screen_space: Dictionary = {}


func _add_sprite_layer(parent: Control, name: String, screen_space: bool) -> void:
	var n := Node2D.new()
	n.name = "Sprites_" + name
	parent.add_child(n)
	sprite_layers[name] = n
	_screen_space[name] = screen_space


func is_screen_layer(name: String) -> bool:
	return bool(_screen_space.get(name, false))


func sprite(id: String) -> AdvSprite:
	for l in sprite_layers.values():
		var s: Node = (l as Node).get_node_or_null(_sprite_node_name(id))
		if s != null and not s.is_queued_for_deletion():
			return s as AdvSprite
	return null


static func _sprite_node_name(id: String) -> String:
	return "S_" + id.replace("/", "_").replace(":", "_").replace(".", "_").replace("@", "_")


## スプライトを作る（同じIDがあれば置き換える）。層がなければ char、それもなければ最初の層。
func add_sprite(id: String, layer: String) -> AdvSprite:
	var old := sprite(id)
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	var l: Node2D = sprite_layers.get(layer)
	if l == null:
		l = sprite_layers.get("char", sprite_layers.values()[0] if not sprite_layers.is_empty() else null)
	if l == null:
		return null
	var s := AdvSprite.new()
	s.name = _sprite_node_name(id)
	s.sprite_id = id
	s.layer_name = layer
	l.add_child(s)
	return s


## スプライトを消す。transition が fade（などの演出）なら薄くしてから消す。
func remove_sprite(id: String, tr: Dictionary = {"type": "cut"}) -> void:
	var s := sprite(id)
	if s == null:
		return
	s.stop_motion()
	await _sprite_transition(s, tr, true)
	if is_instance_valid(s):
		s.get_parent().remove_child(s)
		s.queue_free()


## スプライトを出す演出。
func reveal_sprite(s: AdvSprite, tr: Dictionary) -> void:
	await _sprite_transition(s, tr, false)


## スプライト1枚に切り替え演出をかける（hiding なら消える側）。fade と fade_color は薄くする・濃くする。
## そのほかの演出は、スプライトの絵を CanvasGroup に入れて、画像の切り替えと同じシェーダーをかける。
## 範囲はスプライトの見えている四角。動画のスプライトは fade にする。
func _sprite_transition(s: AdvSprite, tr: Dictionary, hiding: bool) -> void:
	var t := String(tr.get("type", "cut"))
	var dur := float(tr.get("duration", AdvVisuals.DEFAULT_DURATION))
	if t == "cut" or dur <= 0.0 or s == null:
		return
	if t in ["fade", "fade_color"] or s.has_video() or s.bounds().size == Vector2.ZERO:
		var a := s.modulate.a
		if not hiding:
			s.modulate.a = 0.0
		var tw := s.create_tween()
		tw.tween_property(s, "modulate:a", 0.0 if hiding else a, dur)
		await tw.finished
		return
	var g := s.begin_transition_group()
	var mat := AdvVisuals.build_transition_material(tr, s.screen_bounds(), size, tr.get("rule_texture"))
	if hiding:
		mat.set_shader_parameter("invert", true)
	g.material = mat
	await _tween(mat, "shader_parameter/progress", 0.0, 1.0, dur)
	if is_instance_valid(s) and not hiding:
		s.end_transition_group()


func clear_sprites(layer: String = "") -> void:
	for name in sprite_layers:
		if layer != "" and name != layer:
			continue
		for c in sprite_layers[name].get_children():
			c.queue_free()


func sprite_ids() -> Array:
	var out := []
	for l in sprite_layers.values():
		for c in l.get_children():
			if c is AdvSprite and not c.is_queued_for_deletion():
				out.append(c.sprite_id)
	return out


# ---------------------------------------------------------------- 動画（6.6）

var video_player: VideoStreamPlayer
var _video_back: ColorRect
var _video_group: CanvasGroup      ## 動画と黒い余白をまとめたもの（切り替え演出をかける）


## 動画を流す。area は picture か screen。parent を渡すとそこに置く（フィルターをかけないとき）。
func play_video(stream: VideoStream, area: String, fit: String, loop: bool, volume_db: float, parent: Control = null) -> VideoStreamPlayer:
	stop_video()
	var rect := Rect2(Vector2.ZERO, Vector2(tpl.screen_size))
	if area != "screen":
		rect = Rect2(picture.position, picture.size)
	var host: Control = parent if parent != null else (self if area == "screen" else picture)
	var origin := rect.position if host != picture else Vector2.ZERO
	_video_group = CanvasGroup.new()
	_video_group.name = "Video"
	_video_back = ColorRect.new()
	_video_back.color = Color.BLACK
	_video_back.position = origin
	_video_back.size = rect.size
	_video_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_back.clip_contents = true
	_video_group.add_child(_video_back)
	host.add_child(_video_group)
	if host == picture:
		picture.move_child(_video_group, hotspot_layer.get_index())
	elif host == self and _overlay != null:
		move_child(_video_group, _overlay.get_index())
	video_player = VideoStreamPlayer.new()
	video_player.stream = stream
	video_player.loop = loop
	video_player.volume_db = volume_db
	video_player.expand = true
	video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_back.add_child(video_player)
	video_player.play()
	var tex := video_player.get_video_texture()
	var vs := Vector2(tex.get_size()) if tex != null and tex.get_width() > 0 else rect.size
	var sz := rect.size
	match fit:
		"stretch":
			sz = rect.size
		"cover":
			sz = vs * maxf(rect.size.x / vs.x, rect.size.y / vs.y)
		_:
			sz = vs * minf(rect.size.x / vs.x, rect.size.y / vs.y)
	video_player.size = sz.round()
	video_player.position = ((rect.size - sz) * 0.5).round()
	return video_player


func stop_video() -> void:
	if _video_group != null and is_instance_valid(_video_group):
		_video_group.queue_free()
	_video_group = null
	_video_back = null
	video_player = null


## 流し始めた動画を、切り替え演出で現す（終わるまで待つ）。
func reveal_video(tr: Dictionary) -> void:
	if _video_group == null or not is_instance_valid(_video_group):
		return
	await _transition(_video_group, [], tr, false, _video_area())


## 動画を切り替え演出で消してから止める（終わるまで待つ）。
func stop_video_with(tr: Dictionary) -> void:
	if _video_group != null and is_instance_valid(_video_group) and String(tr.get("type", "cut")) != "cut":
		var g := _video_group
		await _transition(null, [g], tr, true, _video_area())
		if g != _video_group:
			# 演出の間に別の動画が始まった
			if is_instance_valid(g):
				g.queue_free()
			return
	stop_video()


## 動画に演出をかける範囲（フィルターの外に置いたときも、その画面の座標で求める）。
func _video_area() -> Dictionary:
	var xf := _video_back.get_global_transform_with_canvas()
	var r := xf * Rect2(Vector2.ZERO, _video_back.size)
	return {"region": r, "screen": _video_back.get_viewport().get_visible_rect().size, "host": _video_group.get_parent() as Control}


func reset_layer(layer: String) -> void:
	var l: Control = layers.get(layer)
	if l != null:
		l.position = Vector2.ZERO
		l.scale = Vector2.ONE


# ---------------------------------------------------------------- 文章

## 文章を表示する（文字送りあり）。name があれば「名前「本文」」の形にする。
## stops は AdvTextMarkup.to_bbcode_stops の止まる位置。instant なら最後まで一度に出す（最後のページを見せる）。
func show_text(bbcode: String, speaker_name: String = "", instant: bool = false, stops: Array = []) -> void:
	_cur_body = bbcode
	_cur_speaker = speaker_name
	var offset := 0 if speaker_name == "" else speaker_name.length() + 1
	message_label.text = _compose_text(bbcode, speaker_name)
	_keep_dirty = true
	set_wait_mark(false)
	_stops = []
	for st in stops:
		var d: Dictionary = st.duplicate()
		d["at"] = int(d["at"]) + offset
		_stops.append(d)
	_stop_i = 0
	_stop = {}
	_page_top = 0
	_inline_speed = -1.0
	_since_wait = 0
	_scroll_to_page()
	if instant:
		show_all()
		return
	_shown = 0.0
	message_label.visible_characters = 0
	_start_typing()


## いまの文章の続きに足して、足したところから文字送りをする（text.append）。
## 話者のある文章では「」の中に足す。ページはそのまま続け、窓に入りきらなければページをめくる。
func append_text(bbcode: String, instant: bool = false, stops: Array = []) -> void:
	if message_label.text == "":
		show_text(bbcode, "", instant, stops)
		return
	var shift := 0
	# 足す文章が [page] で始まるときは、前の文章との間で改行する
	if not stops.is_empty() and String(stops[0]["kind"]) == "page" and int(stops[0]["at"]) == 0 and not _cur_body.ends_with("\n"):
		bbcode = "\n" + bbcode
		shift = 1
	var at := message_label.get_total_character_count() - (1 if _cur_speaker != "" else 0)
	_cur_body += bbcode
	message_label.text = _compose_text(_cur_body, _cur_speaker)
	_keep_dirty = true
	set_wait_mark(false)
	_stops = []
	for st in stops:
		var d: Dictionary = st.duplicate()
		d["at"] = int(d["at"]) + at + shift
		_stops.append(d)
	_stop_i = 0
	_stop = {}
	_inline_speed = -1.0
	_since_wait = 0
	_scroll_to_page()
	if instant:
		show_all()
		return
	_shown = float(at)
	message_label.visible_characters = at
	_start_typing()


# ---------------------------------------------------------------- 減色しない外字（keep_colors: true）
# 文章の窓と同じ並びの写しを、減色しない範囲を描く画面（AdvDisplay.keep_layer）に置く。
# 写しでは文字を透明にし、減色しない外字の画像だけを描く。フィルターは、そこが不透明なところだけ減色を飛ばす。

var keep_layer_provider: Callable   ## func() -> Control（AdvDisplay が設定する）
var keep_mask_toggle: Callable      ## func(on: bool)
var _keep_clip: Control
var _keep_label: RichTextLabel
var _keep_dirty: bool = false
static var _re_keep_strip: RegEx
static var _re_keep_img: RegEx


func _sync_keep() -> void:
	if _keep_dirty:
		_keep_dirty = false
		_rebuild_keep()
	if _keep_label == null or not is_instance_valid(_keep_label) or message_label == null:
		return
	var xf := _text_clip.get_global_transform_with_canvas()
	_keep_clip.position = xf.origin
	_keep_clip.scale = xf.get_scale()
	_keep_clip.size = _text_clip.size
	_keep_clip.visible = message_label.is_visible_in_tree()
	_keep_label.position = message_label.position
	_keep_label.size = message_label.size
	_keep_label.visible_characters = message_label.visible_characters


func _rebuild_keep() -> void:
	var has := message_label != null and message_label.text.contains(AdvTextMarkup.GAIJI_KEEP_PREFIX)
	if _keep_label != null and is_instance_valid(_keep_label):
		_keep_label.queue_free()
	_keep_label = null
	if not has or not keep_layer_provider.is_valid():
		if _keep_clip != null and is_instance_valid(_keep_clip):
			_keep_clip.visible = false
		if keep_mask_toggle.is_valid():
			keep_mask_toggle.call(false)
		return
	if _keep_clip == null or not is_instance_valid(_keep_clip):
		_keep_clip = Control.new()
		_keep_clip.name = "KeepText"
		_keep_clip.clip_contents = true
		_keep_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(keep_layer_provider.call() as Control).add_child(_keep_clip)
	_keep_clip.theme = theme
	_keep_label = message_label.duplicate(0) as RichTextLabel
	_keep_label.add_theme_color_override("default_color", Color(0, 0, 0, 0))
	_keep_label.text = keep_bbcode(message_label.text)
	_keep_clip.add_child(_keep_label)
	if keep_mask_toggle.is_valid():
		keep_mask_toggle.call(true)
	_sync_keep()


## 写しの BBCode：色の指定と点滅を外して文字を透明にし、減色しない外字のほかの画像も透明にする（並びは変えない）。
static func keep_bbcode(bb: String) -> String:
	if _re_keep_strip == null:
		_re_keep_strip = RegEx.create_from_string("\\[/?(color|pulse)(=[^\\]]*| [^\\]]*)?\\]")
		_re_keep_img = RegEx.create_from_string("\\[img\\]([^\\[]*)\\[/img\\]")
	var out := _re_keep_strip.sub(bb, "", true)
	var res := ""
	var at := 0
	for m in _re_keep_img.search_all(out):
		res += out.substr(at, m.get_start() - at)
		var path := m.get_string(1)
		res += m.get_string() if path.begins_with(AdvTextMarkup.GAIJI_KEEP_PREFIX) else "[img color=#00000000]%s[/img]" % path
		at = m.get_end()
	return res + out.substr(at)


func _compose_text(bbcode: String, speaker_name: String) -> String:
	if speaker_name == "":
		return bbcode
	var nc := tpl.color(int(tpl.get_section("text").get("name_color", 6))).to_html(false)
	return "[color=#%s]%s[/color]「%s」" % [nc, AdvTextMarkup._escape(speaker_name), bbcode]


var _cur_body: String = ""       ## いま出している本文（BBCode。話者の名前と「」は含まない）
var _cur_speaker: String = ""


## 最後まで一度に出す（ロードしたときなど）。いちばん後ろのページを見せる。
func show_all() -> void:
	_typing = false
	_stop_i = _stops.size()
	message_label.visible_characters = -1
	_shown = float(message_label.get_total_character_count())
	var last := maxi(0, message_label.get_line_count() - 1)
	var top := 0
	for st in _stops:
		if st["kind"] == "page":
			top = maxi(top, _line_of(int(st["at"])))
	while top < last and not _fits(top, last):
		top += 1
	_page_top = top
	_scroll_to_page()
	halt = "end"


## 文字速度（1秒あたりの文字数。0 なら一度に表示）。
func set_text_speed(chars_per_sec: float) -> void:
	_speed = chars_per_sec


## [speed=n] の速さ（1秒あたりの文字数。0 なら一度に、-1 なら元に戻す）。
func set_inline_speed(chars_per_sec: float) -> void:
	_inline_speed = chars_per_sec


func clear_text() -> void:
	message_label.text = ""
	_keep_dirty = true
	_cur_body = ""
	_cur_speaker = ""
	set_wait_mark(false)
	_typing = false
	_stops = []
	_page_top = 0
	_scroll_to_page()
	halt = "end"


## 文字送りの途中か（止まる位置かページの終わりで止まっているときは false）。
func is_typing() -> bool:
	return _typing


## クリックされたとき：今の区切り（次の止まる位置かページの終わり）まで一度に出す。
func complete_text() -> void:
	if not _typing:
		return
	_shown = float(_limit)
	_halt_at_limit()


## いま止まっている文字送りのタグ。
func current_stop() -> Dictionary:
	return _stop


## 最後に待ってから出した文字の数（ページの終わりとタグが重なったときに、二度待たないため）。
func shown_since_wait() -> int:
	return _since_wait


func mark_waited() -> void:
	_since_wait = 0


## 止まっていたところから文字送りを続ける。
func resume() -> void:
	_stop = {}
	_start_typing()


## 次のページへ（まだ出していない最初の文字の行を、窓のいちばん上にする）。
func next_page() -> void:
	_stop = {}
	var total := message_label.get_total_character_count()
	if int(_shown) < total:
		_page_top = maxi(_page_top, _line_of(int(_shown)))
		_scroll_to_page()
	_start_typing()


func _start_typing() -> void:
	halt = ""
	var total := message_label.get_total_character_count()
	var page_end := _page_end_char()
	_limit = mini(page_end, total)
	var reason := "end" if _limit >= total else "page"
	while _stop_i < _stops.size() and int(_stops[_stop_i]["at"]) < int(_shown):
		_stop_i += 1
	if _stop_i < _stops.size() and int(_stops[_stop_i]["at"]) <= _limit:
		_limit = int(_stops[_stop_i]["at"])
		reason = "stop"
	_pending_reason = reason
	var spd := _speed if _inline_speed < 0.0 else _inline_speed
	if spd <= 0.0 or int(_shown) >= _limit:
		_shown = float(maxi(int(_shown), _limit))
		_halt_at_limit()
		return
	_typing = true


var _pending_reason := "end"


func _halt_at_limit() -> void:
	_typing = false
	var before := message_label.visible_characters
	message_label.visible_characters = -1 if _limit >= message_label.get_total_character_count() else _limit
	_since_wait += maxi(0, _limit - (before if before >= 0 else _limit))
	halt = _pending_reason
	if halt == "stop":
		_stop = _stops[_stop_i]
		_stop_i += 1


## このページに入りきる最後の文字の次の位置。
func _page_end_char() -> int:
	var lines := message_label.get_line_count()
	var l := _page_top
	while l < lines and _fits(_page_top, l):
		l += 1
	if l >= lines:
		return message_label.get_total_character_count()
	return message_label.get_line_range(l).x


## top 行から line 行までが窓に入るか。
func _fits(top: int, line: int) -> bool:
	if line <= top:
		return true
	var bottom := message_label.get_line_offset(line + 1) if line + 1 < message_label.get_line_count() else message_label.get_content_height()
	return bottom - message_label.get_line_offset(top) <= _text_clip.size.y + 0.5


func _line_of(char_index: int) -> int:
	var total := message_label.get_total_character_count()
	if total == 0:
		return 0
	return maxi(0, message_label.get_character_line(clampi(char_index, 0, total - 1)))


func _scroll_to_page() -> void:
	if message_label == null:
		return
	message_label.position.y = -message_label.get_line_offset(_page_top) if _page_top > 0 and message_label.get_line_count() > _page_top else 0.0


# ---------------------------------------------------------------- 待ちの印

## 待ちの印を作り直す。click、page は Control（null なら「▼」の点滅）。
func set_marks(click: Control, page: Control) -> void:
	for m in [wait_mark, page_mark]:
		if m != null and is_instance_valid(m):
			m.queue_free()
	wait_mark = click if click != null else _text_mark("▼", true)
	page_mark = page if page != null else _text_mark(wait_mark.get_meta("text", "▼"), true) if not wait_mark.has_meta("image") else wait_mark.duplicate()
	for m in [wait_mark, page_mark]:
		m.visible = false
		_msg_win.add_child(m)
	_place_marks()


## 文字の印（点滅つき）。
func _text_mark(text: String, blink: bool) -> Control:
	var l := Label.new()
	l.text = text
	l.set_meta("text", text)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blink:
		l.set_meta("blink", true)
	return l


func _place_marks() -> void:
	for mm in [wait_mark, page_mark]:
		if mm == null or not is_instance_valid(mm) or _msg_win == null:
			continue
		var m: Control = mm
		var sz: Vector2 = m.get_meta("size", Vector2(16, 16)) if m.has_meta("size") else m.get_combined_minimum_size()
		var off: Vector2 = m.get_meta("offset", Vector2.ZERO)
		m.position = (_msg_win.size - sz - Vector2(6, 6) + off).round()


## 待ちの印を出す・消す。kind は click か page。
func set_wait_mark(on: bool, kind: String = "click") -> void:
	for mm in [wait_mark, page_mark]:
		if mm == null or not is_instance_valid(mm):
			continue
		var m: Control = mm
		var show: bool = on and m == (page_mark if kind == "page" else wait_mark)
		if m.visible == show:
			continue
		m.visible = show
		if m.has_meta("tween"):
			var old = m.get_meta("tween")
			if old is Tween and old.is_valid():
				old.kill()
			m.remove_meta("tween")
		m.modulate.a = 1.0
		if show and m.get_meta("blink", false):
			var tw: Tween = m.create_tween().set_loops()
			tw.tween_property(m, "modulate:a", 0.0, 0.0).set_delay(0.5)
			tw.tween_property(m, "modulate:a", 1.0, 0.0).set_delay(0.5)
			m.set_meta("tween", tw)


## 待ちの印が出ているか。
func is_waiting_mark() -> bool:
	return (wait_mark != null and wait_mark.visible) or (page_mark != null and page_mark.visible)


func _process(delta: float) -> void:
	_sync_keep()
	if not _typing:
		return
	var spd := _speed if _inline_speed < 0.0 else _inline_speed
	_shown += spd * delta
	if int(_shown) >= _limit:
		_shown = float(_limit)
		_halt_at_limit()
		return
	var before := message_label.visible_characters
	message_label.visible_characters = int(_shown)
	_since_wait += maxi(0, int(_shown) - before)
