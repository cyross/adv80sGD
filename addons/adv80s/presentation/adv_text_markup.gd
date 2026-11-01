class_name AdvTextMarkup
extends RefCounted
## 本文の装飾記法（BBCode拡張、5.4）を、表示用の RichTextLabel の BBCode に変換する。
## 段階1で扱うもの：{変数}（{{ で "{" を出す）、[var=名前]、[pal=n]…[/pal]、[ruby=よみ]…[/ruby]、[em]…[/em]、
## 演出用のタグ（[w=]、[p]、[page]、[speed=]、[/speed]、[instant]、[se=]、[blink]）は表示から取り除く。

static var _re_var: RegEx
static var _re_tag: RegEx


static func _init_re() -> void:
	if _re_var == null:
		_re_var = RegEx.create_from_string("\\{([^{}\\s]+)\\}")
		_re_tag = RegEx.create_from_string("\\[(/?)([a-z_]+)(?:=([^\\]]*))?\\]")


## 変換する。tpl はパレットとルビの表示方法に使う。
static func to_bbcode(body: String, state: AdvState, tpl: AdvTemplate) -> String:
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
	for m in _re_tag.search_all(s):
		out += _escape(s.substr(pos, m.get_start() - pos))
		pos = m.get_end()
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2)
		var arg := m.get_string(3)
		if tag in denied:
			continue
		match tag:
			"var":
				out += _escape(_var_text(arg, state))
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
				else:
					ruby_stack.append(arg)
			"em":
				if em_mode == "paren":
					out += "』" if closing else "『"
			"b", "i", "u", "s", "color":
				out += m.get_string()
			_:
				pass  # w、p、page、speed、instant、se、blink など：表示には出さない
	out += _escape(s.substr(pos))
	return out


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
