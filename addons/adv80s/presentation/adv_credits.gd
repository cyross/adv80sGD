class_name AdvCredits
extends Control
## スタッフロール（出力イベント credits.roll、6.9）。行を縦に並べて、下から上へ流す。
##   {"credits.roll": {"text": "げんさく\nなまえ\n\nおんがく\nなまえ", "speed": 30, "align": "center", "pal": 7}}
## lines（配列）か items（配列）でも書ける。要素は文字列か、次の項目の辞書：
##   text   文（[pal=n] などの装飾記法とエイリアスも使える）
##   pal    文字の色（パレット番号）        size   文字の大きさ（画素）
##   align  center・left・right             image  画像の素材ID（文の代わりに、または文の上に出す）
##   scale  画像の拡大率（既定 1）          gap    この行の前に空ける画素
## margin（既定 16）は左右の余白。
## duration（秒）を書くと、その時間で流し終える。bgm を書くと、流し始めに鳴らす（ID か {id, fade, loop, volume}）。

signal finished

var box: VBoxContainer
var _tween: Tween
var _done := false


## image_loader：素材IDから Texture2D を返す（AdvPlayer が渡す）。
func setup(args: Dictionary, tpl: AdvTemplate, state: AdvState, image_loader: Callable = Callable()) -> AdvCredits:
	var sz := Vector2(tpl.screen_size)
	position = Vector2.ZERO
	size = sz
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bool(args.get("background", true)):
		var bg := ColorRect.new()
		bg.color = tpl.color(int(args.get("fill", 0)))
		bg.size = sz
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", int(args.get("line_gap", 0)))
	var margin := float(args.get("margin", 16))
	box.position = Vector2(margin, sz.y)
	box.size = Vector2(sz.x - margin * 2, 10)
	add_child(box)
	build_items(box, args, tpl, state, image_loader, sz.x - margin * 2)
	return self


## 行を box に並べる（スタッフロールと「おわり」の画面で使う）。width は文の幅。
static func build_items(box: VBoxContainer, args: Dictionary, tpl: AdvTemplate, state: AdvState, image_loader: Callable, width: float) -> void:
	var def_pal := int(args.get("pal", 7))
	var def_align := String(args.get("align", "center"))
	var def_size := int(args.get("size", 0))
	for item in items_of(args):
		var it: Dictionary = item if item is Dictionary else {"text": str(item)}
		if int(it.get("gap", 0)) > 0:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(0, int(it["gap"]))
			box.add_child(sp)
		var align := String(it.get("align", def_align))
		if String(it.get("image", "")) != "" and image_loader.is_valid():
			var tex: Texture2D = image_loader.call(String(it["image"]))
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tr.custom_minimum_size = tex.get_size() * float(it.get("scale", 1.0))
				tr.size_flags_horizontal = {"left": Control.SIZE_SHRINK_BEGIN, "right": Control.SIZE_SHRINK_END}.get(align, Control.SIZE_SHRINK_CENTER)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(tr)
		if it.has("text") or not it.has("image"):
			var label := RichTextLabel.new()
			label.bbcode_enabled = true
			label.fit_content = true
			label.scroll_active = false
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.custom_minimum_size = Vector2(width, 0)
			label.add_theme_color_override("default_color", tpl.color(int(it.get("pal", def_pal))))
			var fs := int(it.get("size", def_size))
			if fs > 0:
				for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
					label.add_theme_font_size_override(k, fs)
			var text := String(it.get("text", ""))
			var bb := AdvTextMarkup.to_bbcode(text, state, tpl) if text != "" else " "
			match align:
				"center":
					bb = "[center]%s[/center]" % bb
				"right":
					bb = "[right]%s[/right]" % bb
			label.text = bb
			box.add_child(label)


## 行の一覧：items → lines → text の順に探す。
static func items_of(args: Dictionary) -> Array:
	if args.get("items") is Array:
		return args["items"]
	if args.get("lines") is Array:
		return args["lines"]
	return Array(String(args.get("text", "")).split("\n"))


## 流す。終わったら finished を出す。
func roll(args: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var h := box.get_combined_minimum_size().y
	box.size = Vector2(box.size.x, h)
	var dist := size.y + h
	var dur := float(args.get("duration", 0.0))
	if dur <= 0.0:
		dur = dist / maxf(1.0, float(args.get("speed", 30.0)))
	_tween = create_tween()
	_tween.tween_property(box, "position:y", -h, dur)
	_tween.finished.connect(_finish)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()


## 最後まで飛ばす。
func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_finish()
