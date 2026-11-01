class_name AdvExpr
extends RefCounted
## 条件式と計算式の短い文字列の形を読む、フレームワーク独自の小さなパーサー（5.8）。
## Godot の Expression は使わない。
##
## 構文木（AST）は配列で表す：
##   ["num", 値] ["str", 文字列] ["bool", 真偽] ["id", 名前]
##   ["call", 名前, [引数...]] ["bin", 演算子, 左, 右]
##   ["and", [...]] ["or", [...]] ["not", 式] ["neg", 式]

var _tokens: Array = []
var _pos: int = 0
var error: String = ""

const _OPS2 := ["&&", "||", "==", "!=", ">=", "<="]
const _OPS1 := ["!", ">", "<", "+", "-", "*", "/", "%", "(", ")", ",", "=", ";"]


## 文字列を読んで AST を返す。失敗したら null を返し、error に理由を入れる。
static func parse(text: String) -> Variant:
	var p := AdvExpr.new()
	return p._parse_all(text)


## let 文（"a = 式; b = 式"）を読む。[[変数名, AST], ...] を返す。失敗したら null。
static func parse_let(text: String) -> Variant:
	var result := []
	for part in text.split(";", false):
		var s := part.strip_edges()
		if s == "":
			continue
		var eq := _find_assign(s)
		if eq < 0:
			return null
		var name := s.substr(0, eq).strip_edges()
		var ast = parse(s.substr(eq + 1))
		if name == "" or ast == null:
			return null
		result.append([name, ast])
	return result


## 代入の "=" の位置（"==", "!=", ">=", "<=" の一部ではないもの）。
static func _find_assign(s: String) -> int:
	for i in s.length():
		if s[i] != "=":
			continue
		var prev := s[i - 1] if i > 0 else ""
		var next := s[i + 1] if i + 1 < s.length() else ""
		if next == "=" or prev in ["=", "!", ">", "<"]:
			continue
		return i
	return -1


func _parse_all(text: String) -> Variant:
	if not _tokenize(text):
		return null
	if _tokens.is_empty():
		error = "empty"
		return null
	var ast = _parse_or()
	if ast == null:
		return null
	if _pos < _tokens.size():
		error = "unexpected token: %s" % str(_tokens[_pos][1])
		return null
	return ast


func _tokenize(text: String) -> bool:
	_tokens.clear()
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r" or c == "　":
			i += 1
			continue
		if c == "\"" or c == "'":
			var j := i + 1
			var buf := ""
			while j < n and text[j] != c:
				if text[j] == "\\" and j + 1 < n:
					j += 1
				buf += text[j]
				j += 1
			if j >= n:
				error = "unterminated string"
				return false
			_tokens.append(["str", buf])
			i = j + 1
			continue
		if c >= "0" and c <= "9":
			var j := i
			while j < n and ((text[j] >= "0" and text[j] <= "9") or text[j] == "."):
				j += 1
			var s := text.substr(i, j - i)
			_tokens.append(["num", float(s) if s.contains(".") else int(s)])
			i = j
			continue
		var two := text.substr(i, 2)
		if two in _OPS2:
			_tokens.append(["op", two])
			i += 2
			continue
		if c in _OPS1:
			_tokens.append(["op", c])
			i += 1
			continue
		# 識別子：演算子・空白・括弧・引用符以外の文字の並び（日本語のIDも使える）
		var j := i
		while j < n:
			var d := text[j]
			if d in [" ", "\t", "\n", "\r", "　", "\"", "'"] or d in _OPS1 or text.substr(j, 2) in _OPS2:
				break
			j += 1
		var word := text.substr(i, j - i)
		match word:
			"and": _tokens.append(["op", "&&"])
			"or": _tokens.append(["op", "||"])
			"not": _tokens.append(["op", "!"])
			"true": _tokens.append(["bool", true])
			"false": _tokens.append(["bool", false])
			_: _tokens.append(["id", word])
		i = j
	return true


func _peek_op(op: String) -> bool:
	return _pos < _tokens.size() and _tokens[_pos][0] == "op" and _tokens[_pos][1] == op


func _parse_or() -> Variant:
	var first = _parse_and()
	if first == null:
		return null
	var list := [first]
	while _peek_op("||"):
		_pos += 1
		var r = _parse_and()
		if r == null:
			return null
		list.append(r)
	return first if list.size() == 1 else ["or", list]


func _parse_and() -> Variant:
	var first = _parse_not()
	if first == null:
		return null
	var list := [first]
	while _peek_op("&&"):
		_pos += 1
		var r = _parse_not()
		if r == null:
			return null
		list.append(r)
	return first if list.size() == 1 else ["and", list]


func _parse_not() -> Variant:
	if _peek_op("!"):
		_pos += 1
		var e = _parse_not()
		return null if e == null else ["not", e]
	return _parse_cmp()


func _parse_cmp() -> Variant:
	var left = _parse_add()
	if left == null:
		return null
	for op in ["==", "!=", ">=", "<=", ">", "<"]:
		if _peek_op(op):
			_pos += 1
			var right = _parse_add()
			return null if right == null else ["bin", op, left, right]
	return left


func _parse_add() -> Variant:
	var left = _parse_mul()
	while left != null and (_peek_op("+") or _peek_op("-")):
		var op: String = _tokens[_pos][1]
		_pos += 1
		var right = _parse_mul()
		left = null if right == null else ["bin", op, left, right]
	return left


func _parse_mul() -> Variant:
	var left = _parse_unary()
	while left != null and (_peek_op("*") or _peek_op("/") or _peek_op("%")):
		var op: String = _tokens[_pos][1]
		_pos += 1
		var right = _parse_unary()
		left = null if right == null else ["bin", op, left, right]
	return left


func _parse_unary() -> Variant:
	if _peek_op("-"):
		_pos += 1
		var e = _parse_unary()
		return null if e == null else ["neg", e]
	return _parse_primary()


func _parse_primary() -> Variant:
	if _pos >= _tokens.size():
		error = "unexpected end"
		return null
	var t: Array = _tokens[_pos]
	_pos += 1
	match t[0]:
		"num": return ["num", t[1]]
		"str": return ["str", t[1]]
		"bool": return ["bool", t[1]]
		"id":
			if _peek_op("("):
				_pos += 1
				var args := []
				if not _peek_op(")"):
					while true:
						var a = _parse_or()
						if a == null:
							return null
						args.append(a)
						if _peek_op(","):
							_pos += 1
							continue
						break
				if not _peek_op(")"):
					error = "missing )"
					return null
				_pos += 1
				return ["call", t[1], args]
			return ["id", t[1]]
		"op":
			if t[1] == "(":
				var e = _parse_or()
				if e == null:
					return null
				if not _peek_op(")"):
					error = "missing )"
					return null
				_pos += 1
				return e
	error = "unexpected token: %s" % str(t[1])
	return null


## AST を短い文字列の形に戻す（JSONの形へ変換するときの計算式に使う）。
static func to_text(ast: Array) -> String:
	match ast[0]:
		"num": return str(ast[1])
		"str": return "\"%s\"" % String(ast[1]).replace("\"", "\\\"")
		"bool": return "true" if ast[1] else "false"
		"id": return ast[1]
		"call":
			var parts := PackedStringArray()
			for a in ast[2]:
				parts.append(to_text(a))
			return "%s(%s)" % [ast[1], ", ".join(parts)]
		"bin": return "(%s %s %s)" % [to_text(ast[2]), ast[1], to_text(ast[3])]
		"neg": return "-%s" % to_text(ast[1])
		"not": return "not %s" % to_text(ast[1])
		"and", "or":
			var parts := PackedStringArray()
			for a in ast[1]:
				parts.append(to_text(a))
			return "(%s)" % (" %s " % ast[0]).join(parts)
	return ""
