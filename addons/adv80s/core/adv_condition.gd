class_name AdvCondition
extends RefCounted
## 条件式の評価（5.8）。JSONの形が正式な形で、短い文字列の形は読み込み時にJSONの形へ変換する。
##
## 評価には AdvState と、追加の情報 extra = {preset, group, features: {名前: bool}} を使う。
## 比較の右辺には値のほか、{"var": 名前}（変数）と {"calc": "計算式"}（計算式）を書ける。

const _CMP_KEYS := ["eq", "ne", "lt", "le", "gt", "ge", "in"]
const _BIN_TO_KEY := {"==": "eq", "!=": "ne", "<": "lt", "<=": "le", ">": "gt", ">=": "ge"}
const _BUILTIN_EQ := ["scene", "preset", "group"]
const _BUILTIN_CALL := ["has", "count", "visited", "talked", "read", "chosen", "feature", "scene", "preset", "group"]

static var _cache: Dictionary = {}

static var _ident_re: RegEx = null


## 短い文字列の形を JSONの形に変換する。失敗したら null。
## 例："has_key and money >= 100" → {"all": ["has_key", {"var": "money", "ge": 100}]}
static func compile(text: String) -> Variant:
	if _cache.has(text):
		return _cache[text]
	var ast = AdvExpr.parse(text)
	if ast == null:
		return null
	var json = _ast_to_cond(ast)
	_cache[text] = json
	return json


## 文字列が「フラグ名だけ」か。
static func is_identifier(s: String) -> bool:
	if _ident_re == null:
		_ident_re = RegEx.create_from_string("^[^\\s()!=<>&|+\\-*/%,;\"']+$")
	return _ident_re.search(s) != null and not s in ["and", "or", "not", "true", "false"]


## 条件を書く場所で使える、正しい条件かどうか確かめる。誤りなら理由、正しければ空文字。
static func check(cond: Variant) -> String:
	if cond is String:
		if is_identifier(cond):
			return ""
		var p := AdvExpr.new()
		var ast = p._parse_all(cond)
		if ast == null:
			return p.error
		return "" if _ast_to_cond(ast) != null else "unsupported expression"
	if cond is bool or cond is Dictionary or cond is Array:
		return ""
	return "invalid condition type"


static func _ast_to_cond(ast: Array) -> Variant:
	match ast[0]:
		"bool": return ast[1]
		"id": return ast[1]
		"num": return ast[1] != 0
		"and", "or":
			var list := []
			for a in ast[1]:
				var c = _ast_to_cond(a)
				if c == null:
					return null
				list.append(c)
			return {"all" if ast[0] == "and" else "any": list}
		"not":
			var c = _ast_to_cond(ast[1])
			return null if c == null else {"not": c}
		"call":
			var name: String = ast[1]
			if not name in _BUILTIN_CALL:
				return null
			var args := []
			for a in ast[2]:
				args.append(_literal_or_name(a))
			if args.is_empty():
				return {name: true}
			return {name: args[0] if args.size() == 1 else args}
		"bin":
			var op: String = ast[1]
			if not _BIN_TO_KEY.has(op):
				return null
			var key: String = _BIN_TO_KEY[op]
			var left: Array = ast[2]
			var right: Array = ast[3]
			if left[0] == "id" and left[1] in _BUILTIN_EQ and (op == "==" or op == "!="):
				var c := {left[1]: _literal_or_name(right)}
				return c if op == "==" else {"not": c}
			if left[0] == "id":
				return {"var": left[1], key: _value_of(right)}
			if left[0] == "call" and left[1] == "count" and left[2].size() == 1:
				return {"count": _literal_or_name(left[2][0]), key: _value_of(right)}
			return {"calc": AdvExpr.to_text(left), key: _value_of(right)}
	return null


## 組み込み条件の引数：識別子はそのまま文字列として扱う。
static func _literal_or_name(a: Array) -> Variant:
	match a[0]:
		"id", "str", "num", "bool": return a[1]
	return AdvExpr.to_text(a)


## 比較の右辺：値ならそのまま、識別子は変数、式は計算式。
static func _value_of(a: Array) -> Variant:
	match a[0]:
		"num", "str", "bool": return a[1]
		"id": return {"var": a[1]}
	return {"calc": AdvExpr.to_text(a)}


## 条件を評価する。
static func evaluate(cond: Variant, state: AdvState, extra: Dictionary = {}) -> bool:
	if cond == null:
		return true
	if cond is bool:
		return cond
	if cond is String:
		if is_identifier(cond):
			return _truthy(_read_var(cond, state))
		var compiled = compile(cond)
		if compiled == null:
			AdvDiag.debug_warn("COND_SYNTAX", "条件式を読めません: %s" % cond, "Cannot parse condition: %s" % cond)
			return false
		return evaluate(compiled, state, extra)
	if cond is Array:
		# 配列はすべて満たす（all と同じ）
		for c in cond:
			if not evaluate(c, state, extra):
				return false
		return true
	if not cond is Dictionary:
		return false
	var d: Dictionary = cond
	if d.has("all"):
		for c in d["all"]:
			if not evaluate(c, state, extra):
				return false
		return true
	if d.has("any"):
		for c in d["any"]:
			if evaluate(c, state, extra):
				return true
		return false
	if d.has("not"):
		return not evaluate(d["not"], state, extra)
	if d.has("var"):
		return _compare(_read_var(String(d["var"]), state), d, state, extra)
	if d.has("calc"):
		return _compare(eval_text(String(d["calc"]), state, extra), d, state, extra)
	if d.has("count"):
		return _compare(state.item_count(String(d["count"])), d, state, extra)
	if d.has("has"):
		return state.has_item(String(d["has"]))
	if d.has("scene"):
		return state.scene == String(d["scene"])
	if d.has("visited"):
		return state.visited.has(String(d["visited"]))
	if d.has("talked"):
		return state.talked.has(String(d["talked"]))
	if d.has("read"):
		return state.read.has(String(d["read"]))
	if d.has("chosen"):
		var v = d["chosen"]
		var key := "%s/%s" % [v[0], v[1]] if v is Array and v.size() >= 2 else String(v)
		return state.chosen.has(key)
	if d.has("preset"):
		var p := String(extra.get("preset", ""))
		var want := String(d["preset"])
		return p == want or p.begins_with(want + ".")
	if d.has("group"):
		return String(extra.get("group", "")) == String(d["group"])
	if d.has("feature"):
		return bool(extra.get("features", {}).get(String(d["feature"]), false))
	return false


static func _compare(left: Variant, d: Dictionary, state: AdvState, extra: Dictionary) -> bool:
	var has_op := false
	for key in _CMP_KEYS:
		if not d.has(key):
			continue
		has_op = true
		var right = _resolve_value(d[key], state, extra)
		if not _compare_one(key, left, right):
			return false
	if not has_op:
		return _truthy(left)
	return true


static func _resolve_value(v: Variant, state: AdvState, extra: Dictionary) -> Variant:
	if v is Dictionary:
		if v.has("var"):
			return _read_var(String(v["var"]), state)
		if v.has("calc"):
			return eval_text(String(v["calc"]), state, extra)
	return v


static func _compare_one(key: String, a: Variant, b: Variant) -> bool:
	if key == "in":
		if b is Array:
			for x in b:
				if _equals(a, x):
					return true
		return false
	if key == "eq":
		return _equals(a, b)
	if key == "ne":
		return not _equals(a, b)
	var fa := _to_number(a)
	var fb := _to_number(b)
	match key:
		"lt": return fa < fb
		"le": return fa <= fb
		"gt": return fa > fb
		"ge": return fa >= fb
	return false


static func _equals(a: Variant, b: Variant) -> bool:
	if a == null:
		a = _default_like(b)
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return str(a) == str(b)
	return a == b


static func _default_like(b: Variant) -> Variant:
	if b is bool: return false
	if b is int or b is float: return 0
	if b is String: return ""
	return null


static func _to_number(v: Variant) -> float:
	if v == null:
		return 0.0
	if v is bool:
		return 1.0 if v else 0.0
	if v is String:
		return float(v) if String(v).is_valid_float() else 0.0
	return float(v)


static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return true


static func _read_var(name: String, state: AdvState) -> Variant:
	if not state.has_var(name):
		AdvDiag.debug_warn("UNKNOWN_VARIABLE", "未定義の変数を参照しました: %s" % name,
			"Undefined variable referenced: %s" % name)
		return null
	return state.get_var(name)


# ---------------------------------------------------------------- 計算式

## 計算式の文字列を評価する（"= money - price * 2" の "=" の後ろの部分）。
static func eval_text(text: String, state: AdvState, extra: Dictionary = {}) -> Variant:
	var ast = AdvExpr.parse(text)
	if ast == null:
		AdvDiag.debug_warn("COND_SYNTAX", "計算式を読めません: %s" % text, "Cannot parse expression: %s" % text)
		return null
	return eval_ast(ast, state, extra)


static func eval_ast(ast: Array, state: AdvState, extra: Dictionary = {}) -> Variant:
	match ast[0]:
		"num", "str", "bool":
			return ast[1]
		"id":
			return _read_var(ast[1], state)
		"neg":
			return -_to_number(eval_ast(ast[1], state, extra))
		"not":
			return not _truthy(eval_ast(ast[1], state, extra))
		"and":
			for a in ast[1]:
				if not _truthy(eval_ast(a, state, extra)):
					return false
			return true
		"or":
			for a in ast[1]:
				if _truthy(eval_ast(a, state, extra)):
					return true
			return false
		"call":
			var c = _ast_to_cond(ast)
			if c is Dictionary and c.has("count"):
				return state.item_count(String(c["count"]))
			return evaluate(c, state, extra) if c != null else null
		"bin":
			var op: String = ast[1]
			var a = eval_ast(ast[2], state, extra)
			var b = eval_ast(ast[3], state, extra)
			if _BIN_TO_KEY.has(op):
				return _compare_one(_BIN_TO_KEY[op], a, b)
			if op == "+" and (a is String or b is String):
				return ("" if a == null else str(a)) + ("" if b == null else str(b))
			var opname: String = {"+": "add", "-": "sub", "*": "mul", "/": "div", "%": "mod"}[op]
			if a == null: a = 0
			if b == null: b = 0
			return AdvState.apply_op(opname, a, b)
	return null
