class_name AdvTemplate
extends RefCounted
## 画面テンプレート（6.1）。extends による継承（項目ごとに上書き、null で取り除く）を解決して持つ。

## テンプレートを探す場所（ID から template.json を探す）。
const SEARCH_DIRS := ["res://game/templates", "res://addons/adv80s/templates"]

var data: Dictionary = {}
var path: String = ""         ## 読み込んだ template.json のパス
var preset: Dictionary = {}   ## AdvPresets.resolve の結果
var _layout_name: String = ""


## ID か template.json のパスから読み込む。失敗したら null。
static func load_template(id_or_path: String, diags: Array = []) -> AdvTemplate:
	var d = _load_resolved(id_or_path, diags, {})
	if not d is Dictionary:
		return null
	var t := AdvTemplate.new()
	t.data = d
	t.path = find_path(id_or_path)
	t.preset = AdvPresets.resolve(String(d.get("display", {}).get("preset", "98")))
	if t.preset.is_empty():
		diags.append(AdvDiag.make("error", "MISSING_TARGET", "プリセットが見つかりません: %s" % d.get("display", {}).get("preset"),
			"Preset not found: %s" % d.get("display", {}).get("preset"), id_or_path, "/display/preset"))
		t.preset = AdvPresets.resolve("98")
	return t


static func find_path(id: String) -> String:
	if id.ends_with(".json"):
		return id
	for dir in SEARCH_DIRS:
		var p := "%s/%s/template.json" % [dir, id]
		if FileAccess.file_exists(p):
			return p
	return ""


static func _load_resolved(id_or_path: String, diags: Array, seen: Dictionary) -> Variant:
	var path := find_path(id_or_path)
	if path == "" or seen.has(path):
		diags.append(AdvDiag.make("error", "MISSING_TARGET", "テンプレートが見つからないか、継承が循環しています: %s" % id_or_path,
			"Template not found or circular extends: %s" % id_or_path, id_or_path))
		return null
	seen[path] = true
	var d = AdvJson.load_file(path, diags)
	if not d is Dictionary:
		return null
	var parent = d.get("extends")
	if parent is String and parent != "":
		var base = _load_resolved(parent, diags, seen)
		if base is Dictionary:
			d = AdvJson.merge(base, d)
	return d


var id: String:
	get:
		return String(data.get("id", ""))


var screen_size: Vector2i:
	get:
		return preset.get("size", Vector2i(640, 400))


## パレットの色。palette.colors で独自の色を指定できる。
func color(index: int) -> Color:
	var pal: PackedColorArray = preset.get("palette", PackedColorArray())
	var own: Array = data.get("palette", {}).get("colors", [])
	if String(data.get("palette", {}).get("source", "preset")) != "preset" and index < own.size():
		return Color.html(String(own[index]))
	if index >= 0 and index < pal.size():
		return pal[index]
	return Color.WHITE


## 名前付きのレイアウトに切り替える（空文字で元に戻す）。
func set_layout(name: String) -> void:
	_layout_name = name


## 区割りの矩形（テンプレートの元の解像度のピクセル）。なければ空の Rect2i。
## 名前付きのレイアウトで "visible": false にした区割りも空になる（その窓を隠す）。
func region_rect(name: String) -> Rect2i:
	var layout: Dictionary = data.get("layout", {})
	var regions: Dictionary = layout.get("regions", {})
	if _layout_name != "":
		var named: Dictionary = layout.get("named", {}).get(_layout_name, {})
		regions = AdvJson.merge(regions, named.get("regions", {}))
	var reg = regions.get(name, {})
	if not reg is Dictionary or not bool(reg.get("visible", true)):
		return Rect2i()
	var r: Array = reg.get("rect", [])
	if r.size() < 4:
		return Rect2i()
	return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))


func region(name: String) -> Dictionary:
	return data.get("layout", {}).get("regions", {}).get(name, {})


## テンプレートが持つ素材フォルダ（assets.root、template.json のフォルダからの相対）。なければ空文字。
func asset_root() -> String:
	var root := String(get_section("assets").get("root", ""))
	if root == "" or path == "":
		return ""
	var dir := root if root.contains("://") else path.get_base_dir() + "/" + root
	dir = dir.trim_suffix("/")
	return dir if DirAccess.dir_exists_absolute(dir) else ""


func get_section(key: String) -> Dictionary:
	var v = data.get(key, {})
	return v if v is Dictionary else {}
