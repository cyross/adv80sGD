class_name AdvParserJa
extends RefCounted
## 日本式パーサープロファイル（4.2）。「ドア しらべる」「ドアを あける」「かぎを ドアに つかう」を読む。
##
## - 語は空白で区切る。区切らずに「ドアをあける」と書いても、知っている名詞と助詞で切り分ける。
## - 助詞は、意図スキーマに particles があればスロットの振り分けに使う。語順は問わない。
## - ひらがなとカタカナ、全角と半角は区別しない（辞書の normalize）。
##
## parse() の結果：
##   成功 → {"intent": {verb, slots, source: "parser"}}
##   失敗 → {"reply": 返事の文, "code": 返事のコード}


## core.query("targets") などから名詞の表を作って読む。
static func parse(text: String, core: AdvCore) -> Dictionary:
	var p := AdvParserJa.new()
	return p._parse(text, core)


var _dict: AdvDictionary
var _nouns: Dictionary = {}       ## 整形済みの呼び名 → [対象...]
var _noun_names: Array = []       ## 呼び名（長い順）
var _known_elsewhere: Dictionary = {}  ## 辞書には載っているが、いまは指せない呼び名


func _parse(text: String, core: AdvCore) -> Dictionary:
	_dict = core.dictionary
	_build_nouns(core)
	var tokens := []   # [{kind: "verb"/"noun"/"absent", value, particle}]
	var src := _dict.normalize(text).strip_edges()
	if src == "":
		return _reply("no_verb")
	for chunk in src.split(" ", false):
		var r := _read_chunk(chunk)
		if r.is_empty():
			return _reply("unknown_word")
		tokens.append_array(r)

	var verb := ""
	var nouns := []
	for t in tokens:
		match t["kind"]:
			"verb":
				verb = t["value"]
			"noun":
				nouns.append(t)
			"absent":
				return _reply("no_target")
	if verb == "":
		return _reply("no_verb" if not nouns.is_empty() else "unknown_word")

	var defs: Array = core.schema.slots(verb)
	var slots := {}
	# 助詞のある名詞を先に振り分ける
	for n in nouns:
		if n["particle"] == "":
			continue
		var placed := false
		for cand in n["value"]:
			var s := _slot_for(defs, slots, cand["type"], n["particle"], core.schema)
			if s != "":
				slots[s] = {"type": cand["type"], "id": cand["id"]}
				placed = true
				break
		if not placed:
			n["particle"] = ""
	for n in nouns:
		if n["particle"] != "" and _is_placed(slots, n):
			continue
		var placed := false
		for cand in n["value"]:
			var s := _slot_for(defs, slots, cand["type"], "", core.schema)
			if s != "":
				slots[s] = {"type": cand["type"], "id": cand["id"]}
				placed = true
				break
		if not placed:
			return _reply("cannot")
	return {"intent": {"verb": verb, "slots": slots, "source": "parser"}}


func _is_placed(slots: Dictionary, n: Dictionary) -> bool:
	for s in slots.values():
		for cand in n["value"]:
			if s["id"] == cand["id"] and s["type"] == cand["type"]:
				return true
	return false


func _slot_for(defs: Array, filled: Dictionary, type: String, particle: String, schema: AdvIntentSchema) -> String:
	for d in defs:
		if filled.has(d["name"]):
			continue
		if not schema.accepts(d["type"], type):
			continue
		if particle != "":
			var ok := false
			for p in d.get("particles", []):
				if _dict.normalize(String(p)) == particle:
					ok = true
					break
			if not ok:
				continue
		return d["name"]
	return ""


func _build_nouns(core: AdvCore) -> void:
	_nouns.clear()
	var targets = core.query("targets")
	if targets is Array:
		for t in targets:
			_add_noun(t)
			if t["type"] == "character":
				var topics = core.query("topics", {"target": t["id"]})
				if topics is Array:
					for tp in topics:
						var names: Array = tp.get("names", []).duplicate()
						var label := String(tp.get("label", ""))
						names.append(label)
						for suffix in ["について", "のこと"]:
							if label.ends_with(suffix):
								names.append(label.trim_suffix(suffix))
						_add_noun({"type": "topic", "id": tp["id"], "names": names})
	_noun_names = _nouns.keys()
	_noun_names.sort_custom(func(a, b): return a.length() > b.length())
	_known_elsewhere.clear()
	var dn := _dict.nouns()
	for id in dn:
		for name in dn[id]:
			var k := _dict.normalize(String(name))
			if not _nouns.has(k):
				_known_elsewhere[k] = id
	var all_names = core.query("nouns")
	if all_names is Array:
		for name in all_names:
			var k := _dict.normalize(String(name))
			if k != "" and not _nouns.has(k):
				_known_elsewhere[k] = name


func _add_noun(t: Dictionary) -> void:
	var names: Array = t.get("names", []).duplicate()
	if t.has("label"):
		names.append(t["label"])
	names.append(t["id"])
	for name in names:
		var k := _dict.normalize(String(name))
		if k == "":
			continue
		if not _nouns.has(k):
			_nouns[k] = []
		var entry := {"type": t["type"], "id": t["id"]}
		if not _nouns[k].has(entry):
			_nouns[k].append(entry)


## 空白で区切った1つの塊を、名詞・助詞・動詞の並びに切り分ける。読めなければ空の配列。
func _read_chunk(chunk: String) -> Array:
	if chunk == "":
		return []
	# 1. 動詞の言い換えと完全一致
	var v := _dict.match_verb_exact(chunk)
	if v != "":
		return [{"kind": "verb", "value": v, "particle": ""}]
	# 2. 名詞（＋助詞）
	if _nouns.has(chunk):
		return [{"kind": "noun", "value": _nouns[chunk], "particle": ""}]
	if _known_elsewhere.has(chunk):
		return [{"kind": "absent", "value": chunk, "particle": ""}]
	for p in _dict.particles():
		if chunk.length() > p.length() and chunk.ends_with(p):
			var stem := chunk.substr(0, chunk.length() - p.length())
			if _nouns.has(stem):
				return [{"kind": "noun", "value": _nouns[stem], "particle": p}]
			if _known_elsewhere.has(stem):
				return [{"kind": "absent", "value": stem, "particle": p}]
	# 3. 区切らずに書かれた「名詞＋助詞＋残り」
	for name in _noun_names:
		if chunk.begins_with(name) and chunk.length() > name.length():
			var rest := chunk.substr(name.length())
			var particle := ""
			for p in _dict.particles():
				if rest.begins_with(p):
					particle = p
					break
			rest = rest.substr(particle.length())
			var tail := _read_chunk(rest) if rest != "" else []
			if rest == "" or not tail.is_empty():
				var r := [{"kind": "noun", "value": _nouns[name], "particle": particle}]
				r.append_array(tail)
				return r
	# 4. 動詞の語幹
	v = _dict.match_verb(chunk)
	if v != "":
		return [{"kind": "verb", "value": v, "particle": ""}]
	return []


func _reply(code: String) -> Dictionary:
	return {"reply": _dict.reply(code), "code": code}
