class_name AdvTextMarkup
extends RefCounted
## 本文の装飾記法（BBCode拡張、5.4）を、表示用の RichTextLabel の BBCode に変換する。
## 変換の順：エイリアス [alias=名前 引数…] → 条件 [if=条件]…[elif=条件]…[else]…[/if] → 変数 → 装飾。
## 扱うもの：{変数}（{{ で "{" を出す）、[var=名前]、[pal=n]…[/pal]、[ruby=よみ]…[/ruby]、[em]…[/em]、[blink]…[/blink]、
## [gaiji=ID]（素材の画像を文中に入れる。1文字として数える）、Godot の [b]、[i]、[u]、[s]、[color]。
## 文字送りのタグ（[p]、[p=秒]、[page]、[page=秒]、[w=秒]、[se=ID]、[speed=n]…[/speed]、[instant]…[/instant]）は、
## to_bbcode_stops が「止まる位置」（表示する文字の数）として返す。to_bbcode は取り除くだけ。

static var _re_var: RegEx
static var _re_tag: RegEx
## 外字の画像を探す関数 func(id) -> {path?: [img] に書くパス, alt?: 文字で表すとき（ログ、読み上げ）}。AdvPlayer が設定する。
static var gaiji_resolver: Callable
## 減色しない外字（マニフェストの keep_colors: true）の画像を置く仮のパス。表示はこれを見て、減色しない範囲を作る
const GAIJI_KEEP_PREFIX := "res://.adv80s_gaiji/keep/"
static var _plain := false
## エイリアス（5.4）：名前 → {params: [引数名…], text: 置き換える文}。AdvPlayer がプロジェクト設定とシナリオから設定する
static var aliases: Dictionary = {}
## [if=条件] の条件を評価する関数 func(条件の文字列, state) -> bool（なければ AdvCondition で評価する）
static var cond_evaluator: Callable
static var _re_alias: RegEx
static var _re_if: RegEx
static var _warned: Dictionary = {}
const MAX_ALIAS_DEPTH := 32


static func _init_re() -> void:
	if _re_var == null:
		_re_var = RegEx.create_from_string("\\{([^{}\\s]+)\\}")
		_re_tag = RegEx.create_from_string("\\[(/?)([a-z_]+)(?:=([^\\]]*))?\\]")
		_re_alias = RegEx.create_from_string("\\[alias=([^\\]]+)\\]")
		_re_if = RegEx.create_from_string("\\[(if|elif)=([^\\]]*)\\]|\\[(else|/if)\\]")


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

	# 0. エイリアスと条件
	var s := expand(body, state)
	# 1. 変数の差し込み
	s = s.replace("{{", "\u0001")
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
			"gaiji":
				if closing or arg == "":
					continue
				var g: Dictionary = gaiji_resolver.call(arg) if gaiji_resolver.is_valid() else {}
				if not _plain and String(g.get("path", "")) != "":
					out += "[img]%s[/img]" % String(g["path"])
					count += 1
				else:
					var alt := String(g.get("alt", ""))
					out += _escape(alt)
					count += alt.length()
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
				pass  # 知らないタグ：表示には出さない
	var rest := s.substr(pos)
	out += _escape(rest)
	return {"bbcode": out, "stops": stops}


## 読み上げ用の文字列。ルビのある語はルビ（読み）で読み、ほかの装飾は取り除く。
static func to_speech(body: String, state: AdvState) -> String:
	var re := RegEx.create_from_string("\\[ruby=([^\\]]*)\\][^\\[]*\\[/ruby\\]")
	var s := re.sub(expand(body, state), "$1", true)
	return to_plain(s, state, null)


## 装飾を取り除いた文字列（メッセージログや読み上げ用）。
static func to_plain(body: String, state: AdvState, tpl: AdvTemplate) -> String:
	_init_re()
	_plain = true
	var bb := to_bbcode(body, state, tpl)
	_plain = false
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


# ---------------------------------------------------------------- エイリアスと条件

## エイリアスの定義を設定する。値は文字列（引数なし）か {params: [引数名…], text: 文}。
static func set_aliases(defs: Dictionary) -> void:
	aliases = {}
	_warned = {}
	for name in defs:
		aliases[String(name)] = normalize_alias(defs[name])


static func normalize_alias(v: Variant) -> Dictionary:
	if v is Dictionary:
		var ps: Array = []
		for p in v.get("params", []):
			ps.append(String(p))
		return {"params": ps, "text": String(v.get("text", ""))}
	return {"params": [], "text": str(v)}


## エイリアスと条件を展開する（装飾タグと変数はそのまま残す）。
static func expand(body: String, state: AdvState) -> String:
	_init_re()
	var s := body
	if s.contains("[alias="):
		s = _expand_aliases(s, [])
	if s.contains("[if="):
		s = _expand_ifs(s, state)
	return s


## [alias=名前 引数1 引数2] の中身を、名前と引数に分ける（引数は空白で区切る。空白を含むなら "…" で囲む）。
static func parse_alias_tag(inner: String) -> Array:
	var parts: Array = []
	var cur := ""
	var quoted := false
	var has := false
	for c in inner:
		if c == "\"":
			quoted = not quoted
			has = true
		elif (c == " " or c == "　") and not quoted:
			if has or cur != "":
				parts.append(cur)
			cur = ""
			has = false
		else:
			cur += c
	if has or cur != "":
		parts.append(cur)
	if parts.is_empty():
		return ["", []]
	return [String(parts[0]), parts.slice(1)]


static func _expand_aliases(s: String, chain: Array) -> String:
	var out := ""
	var pos := 0
	for m in _re_alias.search_all(s):
		out += s.substr(pos, m.get_start() - pos)
		pos = m.get_end()
		var pa := parse_alias_tag(m.get_string(1))
		var name: String = pa[0]
		var args: Array = pa[1]
		if not aliases.has(name):
			_warn_once("ALIAS_UNKNOWN:" + name, "ALIAS_UNKNOWN", "知らないエイリアスです: %s" % name, "Unknown alias: %s" % name)
			continue
		if name in chain or chain.size() >= MAX_ALIAS_DEPTH:
			var path := " → ".join(chain + [name])
			_error_once("ALIAS_CYCLE:" + path, "ALIAS_CYCLE", "エイリアスが循環しています: %s" % path, "Alias refers to itself: %s" % path)
			continue
		var def: Dictionary = aliases[name]
		var text := String(def["text"])
		var params: Array = def["params"]
		for i in params.size():
			text = text.replace("{arg.%s}" % params[i], String(args[i]) if i < args.size() else "")
		out += _expand_aliases(text, chain + [name])
	return out + s.substr(pos)


## [if=条件]…[elif=条件]…[else]…[/if] のうち、条件に合う部分だけを残す（入れ子にできる）。
static func _expand_ifs(s: String, state: AdvState) -> String:
	var stack: Array = []   # [{active, taken, parent}]
	var out := ""
	var pos := 0
	for m in _re_if.search_all(s):
		if _all_active(stack):
			out += s.substr(pos, m.get_start() - pos)
		pos = m.get_end()
		var tag := m.get_string(1) if m.get_string(1) != "" else m.get_string(3)
		match tag:
			"if":
				var pa := _all_active(stack)
				var ok := pa and _eval_cond(m.get_string(2), state)
				stack.append({"active": ok, "taken": ok, "parent": pa})
			"elif":
				if stack.is_empty():
					continue
				var f: Dictionary = stack.back()
				if f["parent"] and not f["taken"] and _eval_cond(m.get_string(2), state):
					f["active"] = true
					f["taken"] = true
				else:
					f["active"] = false
			"else":
				if stack.is_empty():
					continue
				var f: Dictionary = stack.back()
				f["active"] = f["parent"] and not f["taken"]
				f["taken"] = true
			"/if":
				if not stack.is_empty():
					stack.pop_back()
	if _all_active(stack):
		out += s.substr(pos)
	if not stack.is_empty():
		_warn_once("IF_UNCLOSED:" + s, "IF_UNCLOSED", "[if] が [/if] で閉じていません: %s" % s, "[if] is not closed: %s" % s)
	return out


static func _all_active(stack: Array) -> bool:
	for f in stack:
		if not f["active"]:
			return false
	return true


static func _eval_cond(text: String, state: AdvState) -> bool:
	if state == null:
		return false
	if cond_evaluator.is_valid():
		return bool(cond_evaluator.call(text, state))
	return AdvCondition.evaluate(text, state)


static func _warn_once(key: String, code: String, ja: String, en: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	AdvDiag.debug_warn(code, ja, en)


static func _error_once(key: String, code: String, ja: String, en: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_error("[adv80s] %s: %s" % [code, ja if AdvDiag.current_lang() == "ja" else en])


## エイリアスの定義を確かめる：循環（ALIAS_CYCLE、エラー）と、定義の中の知らないエイリアス（ALIAS_UNKNOWN）。
## refs を渡すと、シナリオの中の参照 [{name, file, path}] も確かめる。
static func check_aliases(defs: Dictionary, refs: Array = []) -> Array:
	_init_re()
	var norm := {}
	for n in defs:
		norm[String(n)] = normalize_alias(defs[n])
	var out: Array = []
	var edges := {}
	for n in norm:
		var list: Array = []
		for m in _re_alias.search_all(String(norm[n]["text"])):
			var ref: String = parse_alias_tag(m.get_string(1))[0]
			list.append(ref)
			if not norm.has(ref):
				out.append(AdvDiag.make("error", "ALIAS_UNKNOWN", "エイリアス %s の中の知らないエイリアス: %s" % [n, ref],
					"Unknown alias %s used in alias %s" % [ref, n], "", "aliases/" + n))
		edges[n] = list
	# 循環：深さ優先でたどる
	var state := {}   # 名前 → 1（たどっている途中）・2（済み）
	var reported := {}
	for start in edges:
		_walk_alias(start, edges, state, [], out, reported)
	for r in refs:
		if not norm.has(String(r["name"])):
			out.append(AdvDiag.make("error", "ALIAS_UNKNOWN", "知らないエイリアスです: %s" % r["name"],
				"Unknown alias: %s" % r["name"], String(r.get("file", "")), String(r.get("path", ""))))
	return out


static func _walk_alias(n: String, edges: Dictionary, st: Dictionary, chain: Array, out: Array, reported: Dictionary) -> void:
	if st.get(n, 0) == 2:
		return
	if st.get(n, 0) == 1:
		var i := chain.find(n)
		var loop: Array = chain.slice(i) + [n]
		var key := "|".join(loop)
		if not reported.has(key):
			reported[key] = true
			out.append(AdvDiag.make("error", "ALIAS_CYCLE", "エイリアスが循環しています: %s" % " → ".join(loop),
				"Aliases refer to each other: %s" % " → ".join(loop), "", "aliases/" + n))
		return
	st[n] = 1
	for m in edges.get(n, []):
		if edges.has(m):
			_walk_alias(m, edges, st, chain + [n], out, reported)
	st[n] = 2


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
