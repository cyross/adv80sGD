class_name AdvImages
extends RefCounted
## 画像の読み込みの共通処理。静止画（Texture2D）、アニメーション画像（AdvImageFrames）、動画（VideoStream）を同じ口で読む。
## カラーキー（指定した色を透明にする）は読み込むときに一度だけ行い、結果を覚えておく。

static var _cache: Dictionary = {}


## path を読む。color_key は Color か null。
static func load_visual(path: String, color_key: Variant = null) -> Resource:
	if path == "":
		return null
	var key := path if color_key == null else "%s|%s" % [path, (color_key as Color).to_html()]
	if _cache.has(key):
		var c = _cache[key].get_ref() if _cache[key] is WeakRef else _cache[key]
		if c != null:
			return c
	var res = load(path)
	if color_key is Color:
		if res is Texture2D:
			res = keyed_texture(res, color_key)
		elif res is AdvImageFrames:
			var f := AdvImageFrames.new()
			f.delays = res.delays
			f.loop_count = res.loop_count
			f.size = res.size
			for t in res.frames:
				f.frames.append(keyed_texture(t, color_key))
			res = f
	if res != null:
		_cache[key] = weakref(res)
	return res


## 最初のコマ（静止画として使うとき）。
static func first_texture(res: Resource) -> Texture2D:
	if res is AdvImageFrames:
		return res.first()
	return res as Texture2D


## 指定した色を透明にした複製。
static func keyed_texture(tex: Texture2D, key: Color) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var k := key.to_rgba32() >> 8
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		if ((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]) == k:
			data[i + 3] = 0
	img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(img)


## カラーキーの指定（"#ff00ff" か、テンプレートのパレット番号）を色にする。なければ null。
static func key_color(v: Variant, tpl: AdvTemplate = null) -> Variant:
	if v == null or (v is bool and not v):
		return null
	if v is String:
		return Color.html(v) if Color.html_is_valid(v) else null
	if (v is int or v is float) and tpl != null:
		return tpl.color(int(v))
	return null
