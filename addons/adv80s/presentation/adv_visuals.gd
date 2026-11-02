class_name AdvVisuals
extends RefCounted
## フィルター、切り替え演出、画面効果の設定をまとめて扱う（7.1〜7.4）。
## - フィルター：プリセットの既定値とテンプレートの filters（default / append / replace / none）から決める
## - 切り替え演出：名前付きの組み合わせ、テンプレートの既定、時代に合わない演出の置き換え表を解決する
## - 自作：「シェーダー＋設定項目を定義したJSON（*.effect.json）」を登録できる

const FILTER_SHADER := preload("res://addons/adv80s/shaders/adv_filter.gdshader")
const TRANSITION_SHADER := preload("res://addons/adv80s/shaders/adv_transition.gdshader")
const EFFECT_SHADER := preload("res://addons/adv80s/shaders/adv_effect.gdshader")

const BUILTIN_FILTERS := ["scanline", "reduce", "dither", "bleed", "crt", "rgb_mask", "mono", "lcd", "aspect"]
const TRANSITION_MODES := {
	"fade": 0, "wipe": 1, "blinds": 2, "line_draw": 3, "interlace": 4, "plane_draw": 5,
	"mosaic": 6, "dissolve": 7, "blocks": 8, "iris": 9, "mask": 10,
}
const DIRECTIONS := {"right": 0, "left": 1, "down": 2, "up": 3}
const DEFAULT_DURATION := 0.5
const DEFAULT_LINE_SPEED := 480.0   ## line_draw の既定：1秒あたりの行数

## 自作の定義（*.effect.json）：ID → {kind, shader, params, ...}
static var custom: Dictionary = {}


## 自作の定義を読み込む。
static func load_custom(paths: Array, diags: Array = []) -> void:
	for p in paths:
		var d = AdvJson.load_file(String(p), diags)
		if not d is Dictionary or not d.has("id"):
			continue
		var def: Dictionary = d.duplicate(true)
		var shader := String(def.get("shader", ""))
		if shader != "" and not shader.contains("://"):
			def["shader"] = String(p).get_base_dir() + "/" + shader
		custom[String(def["id"])] = def


# ---------------------------------------------------------------- フィルター

## 使うフィルターの一覧を決める。override は実行時の自由選択（{mode, list} か配列、null なら使わない）。
static func resolve_filters(tpl: AdvTemplate, override: Variant = null) -> Array:
	var base: Array = tpl.preset.get("filters", [])
	var spec = override if override != null else tpl.data.get("filters", {"mode": "default"})
	if spec is Array:
		return _normalize_list(spec)
	if not spec is Dictionary:
		return _normalize_list(base)
	var list: Array = _normalize_list(spec.get("list", []))
	match String(spec.get("mode", "default")):
		"none":
			return []
		"replace":
			return list
		"append":
			return _normalize_list(base) + list
	return _normalize_list(base)


## {"type": …} の形にそろえる（文字列だけなら種類名）。
static func _normalize_list(list: Array) -> Array:
	var r := []
	for f in list:
		if f is String:
			r.append({"type": f})
		elif f is Dictionary and f.has("type"):
			r.append(f.duplicate(true))
	return r


## 標準フィルターのシェーダーを作る。自作フィルターは別の段（追加の描画）になるので、その一覧を返す。
## 戻り値：{"material": ShaderMaterial, "passes": [自作の定義と引数...], "aspect": bool}
static func build_filter_material(filters: Array, tpl: AdvTemplate) -> Dictionary:
	var mat := ShaderMaterial.new()
	mat.shader = FILTER_SHADER
	var size: Vector2i = tpl.screen_size
	mat.set_shader_parameter("source_size", Vector2(size))
	var passes := []
	var aspect := false
	for f in filters:
		var t := String(f["type"])
		match t:
			"scanline":
				mat.set_shader_parameter("scanline", float(f.get("intensity", 0.35)))
			"reduce":
				_set_reduce(mat, f, tpl)
			"dither":
				mat.set_shader_parameter("dither", float(f.get("amount", 0.6)))
			"bleed":
				mat.set_shader_parameter("bleed", float(f.get("amount", 0.5)))
			"crt":
				mat.set_shader_parameter("curvature", float(f.get("curvature", 0.02)))
				mat.set_shader_parameter("vignette", float(f.get("vignette", 0.2)))
			"rgb_mask":
				mat.set_shader_parameter("rgb_mask", float(f.get("amount", 0.25)))
			"mono":
				mat.set_shader_parameter("mono", {"green": 1, "amber": 2, "white": 3}.get(String(f.get("color", "green")), 1))
			"lcd":
				mat.set_shader_parameter("lcd", float(f.get("grid", 0.25)))
			"aspect":
				aspect = true
			_:
				if custom.has(t) and String(custom[t].get("kind", "")) == "filter":
					passes.append({"def": custom[t], "args": f})
				else:
					AdvDiag.debug_warn("UNKNOWN_FILTER", "知らないフィルターです: %s" % t, "Unknown filter: %s" % t)
	return {"material": mat, "passes": passes, "aspect": aspect}


static func _set_reduce(mat: ShaderMaterial, f: Dictionary, tpl: AdvTemplate) -> void:
	var colors: Array = f.get("colors", [])
	var pal := PackedColorArray()
	if not colors.is_empty():
		for c in colors:
			pal.append(Color.html(String(c)))
	else:
		pal = tpl.preset.get("palette", PackedColorArray())
	var bits: Array = f.get("bits", tpl.preset.get("bits", []))
	if not pal.is_empty() and not f.has("bits"):
		var arr: Array = []
		for i in 64:
			arr.append(pal[i] if i < pal.size() else Color.BLACK)
		mat.set_shader_parameter("palette", arr)
		mat.set_shader_parameter("palette_size", mini(pal.size(), 64))
	elif bits.size() >= 3:
		mat.set_shader_parameter("levels", Vector3(pow(2, int(bits[0])) - 1, pow(2, int(bits[1])) - 1, pow(2, int(bits[2])) - 1))
	if f.has("dither"):
		mat.set_shader_parameter("dither", float(f["dither"]))


## 自作フィルターの1段分のシェーダー（画面を読み直す canvas_item シェーダー）。
static func build_custom_pass(p: Dictionary, tpl: AdvTemplate) -> ShaderMaterial:
	var def: Dictionary = p["def"]
	var shader := load(String(def.get("shader", ""))) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("source_size", Vector2(tpl.screen_size))
	_apply_params(mat, def, p["args"])
	return mat


static func _apply_params(mat: ShaderMaterial, def: Dictionary, args: Dictionary) -> void:
	var params: Dictionary = def.get("params", {})
	for name in params:
		var v = args.get(name, params[name].get("default"))
		if v == null:
			continue
		if String(params[name].get("type", "")) == "color" and v is String:
			v = Color.html(v)
		mat.set_shader_parameter(name, v)


# ---------------------------------------------------------------- 切り替え演出

## 切り替え演出を決める。spec は名前（文字列）か {type, duration, …}。省略時はテンプレートの default。
## 戻り値：{type, duration, …}。type が "cut" ならすぐに切り替える。
static func resolve_transition(spec: Variant, tpl: AdvTemplate, named_project: Dictionary = {}, use_default: bool = true) -> Dictionary:
	var tr: Dictionary = tpl.get_section("transitions") if tpl != null else {}
	if spec == null or (spec is String and spec == ""):
		if not use_default:
			return {"type": "cut"}
		spec = tr.get("default", "cut")
	var d: Dictionary = {"type": spec} if spec is String else (spec as Dictionary).duplicate(true)
	if d.has("name") and not d.has("type"):
		d["type"] = d["name"]
	# 名前付きの組み合わせ（テンプレートが優先、次にプロジェクト）
	var named: Dictionary = AdvJson.merge_shallow(named_project, tr.get("named", {}))
	var guard := 0
	while named.has(String(d.get("type", ""))) and guard < 8:
		var base = named[String(d["type"])]
		var b: Dictionary = {"type": base} if base is String else (base as Dictionary).duplicate(true)
		d.erase("type")
		d = AdvJson.merge(b, d)
		guard += 1
	# 時代に合わない演出の置き換え
	var rep: Dictionary = tr.get("replace", {})
	if rep.has(String(d.get("type", ""))):
		d["type"] = rep[String(d["type"])]
	var t := String(d.get("type", "cut"))
	if not d.has("duration"):
		d["duration"] = DEFAULT_DURATION
	if t == "line_draw":
		var lines := float(tpl.region_rect("picture").size.y) if tpl != null else 400.0
		d["duration"] = lines / float(d.get("speed", DEFAULT_LINE_SPEED))
	if t != "cut" and t != "fade_color" and not TRANSITION_MODES.has(t) and not (custom.has(t) and String(custom[t].get("kind", "")) == "transition"):
		AdvDiag.debug_warn("UNKNOWN_TRANSITION", "知らない切り替え演出です: %s（cut にします）" % t, "Unknown transition: %s (using cut)" % t)
		d["type"] = "cut"
	return d


## 切り替え演出のシェーダーを作る。
static func build_transition_material(d: Dictionary, region: Rect2, screen: Vector2, rule_tex: Texture2D = null) -> ShaderMaterial:
	var t := String(d.get("type", "fade"))
	var mat := ShaderMaterial.new()
	if custom.has(t):
		mat.shader = load(String(custom[t].get("shader", ""))) as Shader
		_apply_params(mat, custom[t], d)
	else:
		mat.shader = TRANSITION_SHADER
		mat.set_shader_parameter("mode", TRANSITION_MODES.get(t, 0))
		var default_dir := "down" if t in ["line_draw", "blinds"] else "right"
		mat.set_shader_parameter("direction", DIRECTIONS.get(String(d.get("direction", default_dir)), 0))
		mat.set_shader_parameter("softness", float(d.get("softness", 0.0)))
		mat.set_shader_parameter("count", float(d.get("count", 8)))
		mat.set_shader_parameter("block_size", float(d.get("size", d.get("max_size", 16))))
		var pattern := 0
		if t == "dissolve" and String(d.get("pattern", "dither")) == "random":
			pattern = 1
		elif t == "blocks" and String(d.get("order", "random")) == "sequential":
			pattern = 1
		mat.set_shader_parameter("pattern", pattern)
		var c: Array = d.get("center", [0.5, 0.5])
		mat.set_shader_parameter("center", Vector2(float(c[0]), float(c[1])))
		var order := String(d.get("order", "brg")) if t == "plane_draw" else "brg"
		mat.set_shader_parameter("plane_order", Vector3(order.find("r"), order.find("g"), order.find("b")))
		if rule_tex != null:
			mat.set_shader_parameter("rule_texture", rule_tex)
	mat.set_shader_parameter("region", Vector4(region.position.x / screen.x, region.position.y / screen.y,
		region.size.x / screen.x, region.size.y / screen.y))
	mat.set_shader_parameter("region_px", region.size)
	mat.set_shader_parameter("progress", 0.0)
	return mat
