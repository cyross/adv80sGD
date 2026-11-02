class_name AdvTextMarkup
extends RefCounted
## 本文の装飾記法（BBCode拡張、5.4）を、表示用の RichTextLabel の BBCode に変換する。
## 扱うもの：{変数}（{{ で "{" を出す）、[var=名前]、[pal=n]…[/pal]、[ruby=よみ]…[/ruby]、[em]…[/em]、[blink]…[/blink]、
## Godot の [b]、[i]、[u]、[s]、[color]。
## 文字送りのタグ（[p]、[p=秒]、[page]、[page=秒]、[w=秒]、[se=ID]、[speed=n]…[/speed]、[instant]…[/instant]）は、
## to_bbcode_stops が「止まる位置」（表示する文字の数）として返す。to_bbcode は取り除くだけ。

static var _re_var: RegEx
static var _re_tag: RegEx


static func _init_re() -> void:
	if _re_var == null:
		_re_var = RegEx.create_from_string("\\{([^{}\\s]+)\\}")
		_re_tag = RegEx.create_from_string("\\[(/?)([a-z_]+)(?:=([^\\]]*))?\\]")


## 変換する。tpl はパレットとルビの表示方法に使う。
static func to_bbcode(body: String, state: AdvState, tpl: AdvTemplate) -> String:
	return String(to_bbcode_stops(body, state, tpl)["bbcode"])


## 変換して、文字送りのタグの位置も返す。{bbcode, stops: [{at: その前に出す文字の数, kind, value}]}
## kind は p（クリック待ちで続ける）、page（クリック待ちで次のページ）、w（待つ）、se（効果音）、speed（文字の速さ。-1 で元に戻す、0 で一度に）。
## p と page の value は自動でめくる秒数（0 ならクリックまで待つ）。page の前には改行を入れる。
static func to_bbcode_stops(body: String, state: AdvState, tpl: AdvTemplate) -> Dictionary:
	_init_re()
	var ruby_mode := String(tpl.get_section("text").get("ruby", "paren")) if tpl != null else "paren"
	var em_mode := String(tpl.get_section("text").get("emphasis", "paren")) if tpl != null else "paren"
	var denied: Array = tpl.get_section("text").get("denied_tags", []) if tpl != null else []

	# 1. 変数の差し込み
	var s := body.replace("{{", "\u0001")
	s = _replace_vars(s, state)
	s = s.replace("\u0001", "{")

	# 2. 本文中の "[" と "]" を、タグ以外は表示用にエスケープする
	var out := ""
	var pos := 0
	var ruby_stack: Array = []
	var count := 0          # 表示する文字の数（タグは数えない）
	var stops: Array = []
	for m in _re_tag.search_all(s):
		var chunk := s.substr(pos, m.get_start() - pos)
		out += _escape(chunk)
		count += chunk.length()
		pos = m.get_end()
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2)
		var arg := m.get_string(3)
		if tag in denied:
			continue
		match tag:
			"var":
				var vt := _var_text(arg, state)
				out += _escape(vt)
				count += vt.length()
			"pal":
				if closing:
					out += "[/color]"
				elif tpl != null:
					out += "[color=#%s]" % tpl.color(int(arg)).to_html(false)
			"ruby":
				if closing:
					var r: String = ruby_stack.pop_back() if not ruby_stack.is_empty() else ""
					if ruby_mode != "none" and r != "":
						out += "（%s）" % _escape(r)
						count += r.length() + 2
				else:
					ruby_stack.append(arg)
			"em":
				if em_mode == "paren":
					out += "』" if closing else "『"
					count += 1
			"b", "i", "u", "s", "color":
				out += m.get_string()
			"blink":
				out += "[/pulse]" if closing else "[pulse freq=2.0 color=#ffffff00 ease=-8.0]"
			"p":
				if not closing:
					stops.append({"at": count, "kind": "p", "value": float(arg) if arg != "" else 0.0})
			"page":
				if not closing:
					if not out.ends_with("\n") and count > 0:
						out += "\n"
						count += 1
					stops.append({"at": count, "kind": "page", "value": float(arg) if arg != "" else 0.0})
			"w":
				if not closing:
					stops.append({"at": count, "kind": "w", "value": float(arg) if arg != "" else 0.5})
			"se":
				if not closing and arg != "":
					stops.append({"at": count, "kind": "se", "value": arg})
			"speed":
				stops.append({"at": count, "kind": "speed", "value": -1.0 if closing else float(arg)})
			"instant":
				stops.append({"at": count, "kind": "speed", "value": -1.0 if closing else 0.0})
			_:
				pass  # gaiji など：表示には出さない
	var rest := s.substr(pos)
	out += _escape(rest)
	return {"bbcode": out, "stops": stops}


## 読み上げ用の文字列。ルビのある語はルビ（読み）で読み、ほかの装飾は取り除く。
static func to_speech(body: String, state: AdvState) -> String:
	var re := RegEx.create_from_string("\\[ruby=([^\\]]*)\\][^\\[]*\\[/ruby\\]")
	var s := re.sub(body, "$1", true)
	return to_plain(s, state, null)


## 装飾を取り除いた文字列（メッセージログや読み上げ用）。
static func to_plain(body: String, state: AdvState, tpl: AdvTemplate) -> String:
	_init_re()
	var bb := to_bbcode(body, state, tpl)
	var re := RegEx.create_from_string("\\[(/?)([a-z_]+)(=[^\\]]*)?\\]")
	var out := ""
	var pos := 0
	for m in re.search_all(bb):
		out += bb.substr(pos, m.get_start() - pos)
		match m.get_string(2):
			"lb": out += "["
			"rb": out += "]"
		pos = m.get_end()
	return out + bb.substr(pos)


static func _replace_vars(s: String, state: AdvState) -> String:
	var out := ""
	var pos := 0
	for m in _re_var.search_all(s):
		out += s.substr(pos, m.get_start() - pos)
		out += _var_text(m.get_string(1), state)
		pos = m.get_end()
	return out + s.substr(pos)


static func _var_text(name: String, state: AdvState) -> String:
	if state == null:
		return ""
	var v = state.get_var(name)
	return "" if v == null else str(v)


static func _escape(t: String) -> String:
	var r := ""
	for c in t:
		if c == "[":
			r += "[lb]"
		elif c == "]":
			r += "[rb]"
		else:
			r += c
	return r
