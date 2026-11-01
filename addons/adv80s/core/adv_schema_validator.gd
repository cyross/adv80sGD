class_name AdvSchemaValidator
extends RefCounted
## 同梱の JSON Schema（draft-07）で JSON を確かめる、小さな検証器（6.2）。
## 外部ツールなしで validate とコマンドラインの確認に使う。ゲームの実行中には使わない。
##
## 対応するキーワード：$ref（同じファイル内の #/definitions/…）、type、properties、required、
## additionalProperties、patternProperties、enum、const、items、minItems、maxItems、
## minimum、maximum、minLength、pattern、anyOf、oneOf、allOf
##
## 知らない項目（additionalProperties: false に当たるもの）は警告 UNKNOWN_KEY、それ以外の違反はエラー SCHEMA_VIOLATION。

const SCHEMA_DIR := "res://addons/adv80s/schemas"

static var _cache: Dictionary = {}
static var _re_cache: Dictionary = {}

var _root: Dictionary
var _file: String


## 同梱のスキーマを読む。name は "scenario" など。言語は AdvDiag の表示言語に合わせる。
static func load_schema(name: String) -> Dictionary:
	var lang := AdvDiag.current_lang()
	var path := "%s/%s/%s.schema.json" % [SCHEMA_DIR, lang, name]
	if not FileAccess.file_exists(path):
		path = "%s/ja/%s.schema.json" % [SCHEMA_DIR, name]
	if _cache.has(path):
		return _cache[path]
	var d = AdvJson.load_file(path)
	_cache[path] = d if d is Dictionary else {}
	return _cache[path]


## data をスキーマ name で確かめ、診断の配列を返す。
static func check(data: Variant, name: String, file: String = "") -> Array:
	var schema := load_schema(name)
	if schema.is_empty():
		return []
	var v := AdvSchemaValidator.new()
	v._root = schema
	v._file = file
	var diags: Array = []
	v._validate(data, schema, "", diags)
	return diags


func _validate(data: Variant, schema: Variant, path: String, diags: Array) -> void:
	if schema is bool:
		if not schema:
			_err(diags, path, "ここには値を書けません", "No value is allowed here")
		return
	if not schema is Dictionary:
		return
	var s: Dictionary = schema
	if s.has("$ref"):
		_validate(data, _resolve_ref(String(s["$ref"])), path, diags)
	if s.has("type") and not _type_ok(data, s["type"]):
		_err(diags, path, "型が違います（%s が必要）" % _type_text(s["type"]),
			"Wrong type (%s expected)" % _type_text(s["type"]))
		return
	if s.has("const") and not _equal(data, s["const"]):
		_err(diags, path, "値は %s にしてください" % JSON.stringify(s["const"]), "Value must be %s" % JSON.stringify(s["const"]))
	if s.has("enum"):
		var ok := false
		for e in s["enum"]:
			if _equal(data, e):
				ok = true
				break
		if not ok:
			_err(diags, path, "使える値は %s です" % JSON.stringify(s["enum"]), "Allowed values: %s" % JSON.stringify(s["enum"]))
	if data is String:
		if s.has("minLength") and String(data).length() < int(s["minLength"]):
			_err(diags, path, "文字列が短すぎます", "String is too short")
		if s.has("pattern") and _regex(String(s["pattern"])).search(data) == null:
			_err(diags, path, "書き方が違います（%s）" % s["pattern"], "Does not match pattern %s" % s["pattern"])
	if data is int or data is float:
		if s.has("minimum") and float(data) < float(s["minimum"]):
			_err(diags, path, "%s 以上にしてください" % s["minimum"], "Must be >= %s" % s["minimum"])
		if s.has("maximum") and float(data) > float(s["maximum"]):
			_err(diags, path, "%s 以下にしてください" % s["maximum"], "Must be <= %s" % s["maximum"])
	if data is Array:
		if s.has("minItems") and data.size() < int(s["minItems"]):
			_err(diags, path, "要素が %s 個以上必要です" % s["minItems"], "At least %s items required" % s["minItems"])
		if s.has("maxItems") and data.size() > int(s["maxItems"]):
			_err(diags, path, "要素は %s 個までです" % s["maxItems"], "At most %s items allowed" % s["maxItems"])
		if s.has("items"):
			for i in data.size():
				_validate(data[i], s["items"], "%s/%d" % [path, i], diags)
	if data is Dictionary:
		_validate_object(data, s, path, diags)
	if s.has("allOf"):
		for sub in s["allOf"]:
			_validate(data, sub, path, diags)
	for key in ["anyOf", "oneOf"]:
		if s.has(key):
			_validate_choice(data, s[key], path, diags)


func _validate_object(data: Dictionary, s: Dictionary, path: String, diags: Array) -> void:
	for req in s.get("required", []):
		if not data.has(req):
			_err(diags, path, "項目 %s が必要です" % req, "Missing required property: %s" % req)
	var props: Dictionary = s.get("properties", {})
	var patterns: Dictionary = s.get("patternProperties", {})
	for key in data:
		var p := "%s/%s" % [path, _escape(String(key))]
		var matched := false
		if props.has(key):
			_validate(data[key], props[key], p, diags)
			matched = true
		for pat in patterns:
			if _regex(String(pat)).search(String(key)) != null:
				_validate(data[key], patterns[pat], p, diags)
				matched = true
		if matched or key == "$schema":
			continue
		if s.has("additionalProperties"):
			var ap = s["additionalProperties"]
			if ap is bool and not ap:
				diags.append(_make("warning", "UNKNOWN_KEY", p, "知らない項目です: %s" % key, "Unknown property: %s" % key))
			elif ap is Dictionary:
				_validate(data[key], ap, p, diags)


## anyOf / oneOf：どれかに当てはまればよい。当てはまらなければ、いちばん近い候補の診断を出す。
func _validate_choice(data: Variant, choices: Array, path: String, diags: Array) -> void:
	var best: Array = []
	var best_score := 1 << 30
	for sub in choices:
		var d: Array = []
		_validate(data, sub, path, d)
		if d.is_empty():
			return
		var score := 0
		for x in d:
			score += 1 if x["severity"] == "warning" else 10
		if score < best_score:
			best_score = score
			best = d
	diags.append_array(best)


func _resolve_ref(ref: String) -> Variant:
	if not ref.begins_with("#/"):
		return true
	var cur: Variant = _root
	for part in ref.substr(2).split("/"):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return true
	return cur


static func _type_ok(data: Variant, t: Variant) -> bool:
	if t is Array:
		for x in t:
			if _type_ok(data, x):
				return true
		return false
	match String(t):
		"string": return data is String
		"number": return data is int or data is float
		"integer": return data is int or (data is float and data == floorf(data))
		"boolean": return data is bool
		"object": return data is Dictionary
		"array": return data is Array
		"null": return data == null
	return true


static func _type_text(t: Variant) -> String:
	return "、".join(PackedStringArray(t)) if t is Array else String(t)


static func _equal(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


static func _regex(p: String) -> RegEx:
	if not _re_cache.has(p):
		_re_cache[p] = RegEx.create_from_string(p)
	return _re_cache[p]


static func _escape(k: String) -> String:
	return k.replace("~", "~0").replace("/", "~1")


func _err(diags: Array, path: String, ja: String, en: String) -> void:
	diags.append(_make("error", "SCHEMA_VIOLATION", path, ja, en))


func _make(severity: String, code: String, path: String, ja: String, en: String) -> Dictionary:
	return AdvDiag.make(severity, code, ja, en, _file, path if path != "" else "/")
