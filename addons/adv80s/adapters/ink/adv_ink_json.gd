class_name AdvInkJson
extends RefCounted
## Ink の変換済み JSON を読む小さなパーサー。
## Godot の JSON はすべての数値を float にするが、Ink では整数と小数を区別するので、自前で読む。
## 失敗したら null を返し、error に理由を入れる。

var _s: String
var _i: int = 0
var error: String = ""


static func parse(text: String) -> Variant:
	var p := AdvInkJson.new()
	p._s = text
	p._skip_ws()
	var v = p._value()
	if p.error != "":
		push_error("[adv80s] Ink の JSON を読めません: %s" % p.error)
		return null
	return v


func _skip_ws() -> void:
	while _i < _s.length():
		var c := _s.unicode_at(_i)
		if c == 32 or c == 9 or c == 10 or c == 13 or c == 0xFEFF:
			_i += 1
		else:
			break


func _value() -> Variant:
	if _i >= _s.length():
		error = "unexpected end"
		return null
	var c := _s[_i]
	match c:
		"{":
			return _object()
		"[":
			return _array()
		"\"":
			return _string()
		"t":
			_i += 4
			return true
		"f":
			_i += 5
			return false
		"n":
			_i += 4
			return null
	return _number()


func _object() -> Variant:
	var d := {}
	_i += 1
	_skip_ws()
	if _s[_i] == "}":
		_i += 1
		return d
	while error == "":
		_skip_ws()
		var k = _string()
		_skip_ws()
		if _i >= _s.length() or _s[_i] != ":":
			error = "expected : at %d" % _i
			return null
		_i += 1
		_skip_ws()
		d[k] = _value()
		_skip_ws()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
			continue
		if _i < _s.length() and _s[_i] == "}":
			_i += 1
			return d
		error = "expected , or } at %d" % _i
	return null


func _array() -> Variant:
	var a := []
	_i += 1
	_skip_ws()
	if _s[_i] == "]":
		_i += 1
		return a
	while error == "":
		_skip_ws()
		a.append(_value())
		_skip_ws()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
			continue
		if _i < _s.length() and _s[_i] == "]":
			_i += 1
			return a
		error = "expected , or ] at %d" % _i
	return null


func _string() -> Variant:
	if _s[_i] != "\"":
		error = "expected string at %d" % _i
		return null
	_i += 1
	var out := ""
	var start := _i
	while _i < _s.length():
		var c := _s[_i]
		if c == "\"":
			out += _s.substr(start, _i - start)
			_i += 1
			return out
		if c == "\\":
			out += _s.substr(start, _i - start)
			_i += 1
			var e := _s[_i]
			match e:
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				"b": out += "\b"
				"f": out += "\f"
				"u":
					out += String.chr(_s.substr(_i + 1, 4).hex_to_int())
					_i += 4
				_: out += e
			_i += 1
			start = _i
			continue
		_i += 1
	error = "unterminated string"
	return null


func _number() -> Variant:
	var start := _i
	var is_float := false
	while _i < _s.length():
		var c := _s[_i]
		if c in ["-", "+", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			_i += 1
		elif c in [".", "e", "E"]:
			is_float = true
			_i += 1
		else:
			break
	var t := _s.substr(start, _i - start)
	if t == "":
		error = "unexpected character at %d" % _i
		return null
	return float(t) if is_float else int(t)
