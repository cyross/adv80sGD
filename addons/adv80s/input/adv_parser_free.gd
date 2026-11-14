class_name AdvParserFree
extends AdvParserJa
## 自由文のパーサープロファイル（4.2、"free"）。「古いドアを開けてみる」「かぎでドアをあけてください」のような
## ふつうの文を読む。空白で区切らなくてよい。
##
## 1. 文の終わりの言い回し（「てみる」「てください」「たい」「ます」「よう」「。」など）を取る
## 2. 文の終わりから動詞を探す（辞書の言い換え・語幹と、活用の終わり「る」「た」「て」「ない」など）
## 3. 残りから、知っている名詞（長い順）と、そのすぐ後の助詞を拾う。知らない語（「古い」「その」など）は読み飛ばす
## 4. あとは日本式と同じに、助詞と意図スキーマでスロットに振り分ける
##
## 名詞がいくつもの対象を指すとき（「ドア」が2つあるなど）は、文の中のほかの語が呼び名に入っている対象を選ぶ
## （「古いドア」なら、呼び名に「古い」を含むドア）。

## 文の終わりの言い回し（長い順に、何度でも取る）
const ENDINGS := [
	"てみようかな", "でみようかな", "てみようか", "てみたいな", "てみてください", "てみてくれ", "てみよう", "でみよう",
	"てみたい", "でみたい", "てみます", "てみる", "でみる", "てみろ", "てください", "でください", "てくれないか",
	"てくれ", "でくれ", "てほしい", "ください", "なさい", "ましょう", "たいな", "たい", "ます", "ません",
	"よう", "かな", "てみ", "でみ", "ぞ", "ね", "よ", "な", "か", "。", "、", "!", "?", "！", "？", ".", "…", "~", "〜",
]
## 動詞の語幹の後ろにつく活用の終わり
const CONJ := ["", "る", "た", "て", "だ", "で", "ない", "ろ", "れ", "よ", "う", "ます", "って", "った", "いた", "いて",
	"した", "して", "さない", "す", "する", "け", "こう", "い", "く", "き", "し", "っ", "ん", "わ", "り", "ち"]


static func parse(text: String, core: AdvCore) -> Dictionary:
	var p := AdvParserFree.new()
	return p._parse(text, core)


func _parse(text: String, core: AdvCore) -> Dictionary:
	_dict = core.dictionary
	_build_nouns(core)
	var src := _dict.normalize(text).strip_edges().replace(" ", "").replace("\t", "")
	if src == "":
		return _reply("no_verb")
	src = strip_endings(src)
	# 動詞：文の終わりのできるだけ長い部分
	var verb := ""
	var head := src
	for i in src.length():
		var v := _verb_at_end(src.substr(i))
		if v != "":
			verb = v
			head = src.substr(0, i)
			break
	var tokens := _nouns_in(head)
	if verb == "":
		if tokens.is_empty():
			return _reply("unknown_word")
		return _reply("no_verb")
	tokens.append({"kind": "verb", "value": verb, "particle": ""})
	_narrow_by_words(tokens, head)
	return _tokens_to_intent(tokens, core)


## 文の終わりの言い回しを取る。
func strip_endings(s: String) -> String:
	var changed := true
	while changed:
		changed = false
		for e in ENDINGS:
			var ne: String = _dict.normalize(e)
			if s.length() > ne.length() and s.ends_with(ne):
				s = s.substr(0, s.length() - ne.length())
				changed = true
				break
	return s


## tail 全体が1つの動詞（言い換えそのもの、または語幹＋活用の終わり）なら、その動詞。
func _verb_at_end(tail: String) -> String:
	var v := _dict.match_verb_exact(tail)
	if v != "":
		return v
	# 言い換えの終わりの「る」「う」「す」などを活用させたもの（見る → 見た、使う → 使って）
	var verbs: Dictionary = _dict.data.get("verbs", {})
	for id in verbs:
		var words: Array = verbs[id].get("words", []).duplicate()
		words.append(verbs[id].get("label", ""))
		for w in words:
			var nw: String = _dict.normalize(String(w))
			if nw.length() < 2:
				continue
			var base := nw.substr(0, nw.length() - 1)   # 最後の1文字を除いたもの
			if tail.begins_with(base) and tail.length() - base.length() <= 3 and _is_conj(tail.substr(base.length())):
				return id
		for st in verbs[id].get("stems", []):
			var ns: String = _dict.normalize(String(st))
			if ns != "" and tail.begins_with(ns) and _is_conj(tail.substr(ns.length())):
				return id
	return ""


func _is_conj(rest: String) -> bool:
	for c in CONJ:
		if rest == _dict.normalize(c):
			return true
	return false


## 名詞と、すぐ後の助詞を拾う（長い呼び名から。重なるところは先に取ったものを使う）。
func _nouns_in(head: String) -> Array:
	var used := []
	used.resize(head.length())
	used.fill(false)
	var found := []   # [位置, 語]
	var names: Array = _noun_names.duplicate()
	var elsewhere: Array = _known_elsewhere.keys()
	elsewhere.sort_custom(func(a, b): return a.length() > b.length())
	for group in [[names, "noun"], [elsewhere, "absent"]]:
		for name in group[0]:
			if name == "":
				continue
			var at := 0
			while true:
				var i := head.find(name, at)
				if i < 0:
					break
				at = i + 1
				var free := true
				for j in name.length():
					if used[i + j]:
						free = false
						break
				if not free:
					continue
				for j in name.length():
					used[i + j] = true
				found.append([i, name, group[1]])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var tokens := []
	for f in found:
		var after := head.substr(f[0] + f[1].length())
		var particle := ""
		for p in _dict.particles():
			if after.begins_with(p):
				particle = p
				break
		if f[2] == "noun":
			tokens.append({"kind": "noun", "value": _nouns[f[1]], "particle": particle, "name": f[1]})
		else:
			tokens.append({"kind": "absent", "value": f[1], "particle": particle})
	return tokens


## 名詞が複数の対象を指すとき、文の中のほかの語（「古い」など）を呼び名に含む対象を先にする。
func _narrow_by_words(tokens: Array, head: String) -> void:
	for t in tokens:
		if t["kind"] != "noun" or (t["value"] as Array).size() < 2:
			continue
		var rest := head.replace(String(t["name"]), " ")
		var scored := []
		for cand in t["value"]:
			var best := 0
			for name in _nouns:
				if not cand in _nouns[name] or name == t["name"] or not String(name).contains(t["name"]):
					continue
				var extra := String(name).replace(t["name"], "")
				if extra != "" and rest.contains(extra):
					best = maxi(best, extra.length())
			scored.append([best, cand])
		scored.sort_custom(func(a, b): return a[0] > b[0])
		t["value"] = scored.map(func(s): return s[1])
