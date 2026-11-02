class_name AdvParserEn
extends AdvParserJa
## 英語式パーサープロファイル（4.2）。「OPEN DOOR」「USE KEY ON DOOR」「GIVE KEY TO AYUMI」を読む。
##
## - 最初に動詞（「look at」「pick up」のような2語の動詞も辞書に書ける）、続けて名詞を書く
## - 前置詞（辞書の particles：with、on、to、at、in、about など）で名詞を区切る
## - 冠詞（the、a、an）は読み飛ばす
## - 名詞は、意図スキーマのスロットの順に、型が合うところへ入れる

const ARTICLES := ["the", "a", "an"]


static func parse(text: String, core: AdvCore) -> Dictionary:
	var p := AdvParserEn.new()
	return p._parse_en(text, core)


func _parse_en(text: String, core: AdvCore) -> Dictionary:
	_dict = core.dictionary
	_build_nouns(core)
	var src := _dict.normalize(text).strip_edges()
	for c in [".", ",", "!", "?"]:
		src = src.replace(c, " ")
	var words := Array(src.split(" ", false)).filter(func(w): return not w in ARTICLES)
	if words.is_empty():
		return _reply("no_verb")
	# 動詞：長い方から（3語、2語、1語）
	var verb := ""
	var used := 0
	for n in [3, 2, 1]:
		if words.size() >= n:
			var v := _dict.match_verb_exact(" ".join(words.slice(0, n)))
			if v != "":
				verb = v
				used = n
				break
	if verb == "":
		var known := _nouns.has(String(words[0])) or _known_elsewhere.has(String(words[0]))
		return _reply("no_verb" if known else "unknown_word")
	# 前置詞で区切って名詞のまとまりにする
	var preps := Array(_dict.particles())
	var groups := []   # [[前置詞, 語の配列]]
	var cur := ["", []]
	for w in words.slice(used):
		if w in preps:
			if not cur[1].is_empty():
				groups.append(cur)
			cur = [w, []]
		else:
			cur[1].append(w)
	if not cur[1].is_empty():
		groups.append(cur)
	var defs: Array = core.schema.slots(verb)
	var slots := {}
	for g in groups:
		var name := " ".join(g[1])
		if _known_elsewhere.has(name) and not _nouns.has(name):
			return _reply("no_target")
		if not _nouns.has(name):
			return _reply("unknown_word")
		var placed := false
		for cand in _nouns[name]:
			var s := _slot_for(defs, slots, cand["type"], "", core.schema)
			if s != "":
				slots[s] = {"type": cand["type"], "id": cand["id"]}
				placed = true
				break
		if not placed:
			return _reply("cannot")
	return {"intent": {"verb": verb, "slots": slots, "source": "parser"}}
