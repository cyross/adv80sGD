class_name AdvDictionary
extends RefCounted
## コマンド入力用の同義語辞書（4.4）。
## プロジェクト → テンプレート → シナリオ の順に重ね、後のものが上書きする。

const STANDARD_JA := "res://addons/adv80s/data/dictionaries/ja.json"
const STANDARD_EN := "res://addons/adv80s/data/dictionaries/en.json"

var data: Dictionary = {}
var lang: String = "ja"

var _verb_words: Dictionary = {}   ## 整形済みの言い換え → 動詞ID
var _verb_stems: Array = []        ## [[整形済みの語幹, 動詞ID], ...]（長い順）
var _particles: PackedStringArray = []


## 辞書の層を重ねる。layer は辞書のJSONの中身。
func add_layer(layer: Dictionary) -> void:
	if data.is_empty():
		data = layer.duplicate(true)
	else:
		data = AdvJson.merge(data, layer)
	lang = String(data.get("lang", lang))
	_rebuild()


func load_layer(path: String, diags: Array = []) -> bool:
	var d = AdvJson.load_file(path, diags)
	if d is Dictionary:
		add_layer(d)
		return true
	return false


func _rebuild() -> void:
	_verb_words.clear()
	_verb_stems.clear()
	var verbs: Dictionary = data.get("verbs", {})
	for id in verbs:
		var v: Dictionary = verbs[id]
		_verb_words[normalize(String(v.get("label", "")))] = id
		for w in v.get("words", []):
			_verb_words[normalize(String(w))] = id
		for s in v.get("stems", []):
			_verb_stems.append([normalize(String(s)), id])
	_verb_stems.sort_custom(func(a, b): return a[0].length() > b[0].length())
	_particles.clear()
	for p in data.get("particles", []):
		_particles.append(normalize(String(p)))
	var arr := Array(_particles)
	arr.sort_custom(func(a, b): return a.length() > b.length())
	_particles = PackedStringArray(arr)


## 照合前の整形：ひらがなとカタカナ、全角と半角を区別しない。英字は小文字にそろえる。
func normalize(s: String) -> String:
	var opt: Dictionary = data.get("normalize", {"kana": true, "width": true})
	return AdvDictionary.normalize_text(s, bool(opt.get("kana", true)), bool(opt.get("width", true)))


static func normalize_text(s: String, kana: bool = true, width: bool = true) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if width:
			if c >= 0xFF01 and c <= 0xFF5E:
				c -= 0xFEE0
			elif c == 0x3000:
				c = 0x20
		if kana and c >= 0x30A1 and c <= 0x30F6:
			c -= 0x60
		out += String.chr(c)
	return out.to_lower()


## 動詞を探す。完全一致を優先し、なければ語幹で始まるかを見る。見つからなければ空文字。
func match_verb(word: String) -> String:
	var w := normalize(word)
	if _verb_words.has(w):
		return _verb_words[w]
	for pair in _verb_stems:
		if pair[0] != "" and w.begins_with(pair[0]):
			return pair[1]
	return ""


## 言い換えとの完全一致だけで動詞を探す。
func match_verb_exact(word: String) -> String:
	return String(_verb_words.get(normalize(word), ""))


func particles() -> PackedStringArray:
	return _particles


func has_verb(id: String) -> bool:
	return data.get("verbs", {}).has(id)


func verb_ids() -> PackedStringArray:
	return PackedStringArray(data.get("verbs", {}).keys())


func verb_label(id: String) -> String:
	return String(data.get("verbs", {}).get(id, {}).get("label", id))


## 拡張の動詞（プロジェクトで有効にして使う）か。
func is_extended(id: String) -> bool:
	return bool(data.get("verbs", {}).get(id, {}).get("extended", false))


func default_reply(id: String) -> String:
	return String(data.get("verbs", {}).get(id, {}).get("default_reply", ""))


## 動詞の代用先（実装者が辞書の fallback で指定したときだけ）。
func fallback(id: String) -> String:
	return String(data.get("verbs", {}).get(id, {}).get("fallback", ""))


## 名詞の言い換え（シナリオ全体で使うもの）。
func noun_names(id: String) -> Array:
	return data.get("nouns", {}).get(id, [])


func nouns() -> Dictionary:
	return data.get("nouns", {})


## 決まった返事。{verb} などの差し込みができる。
func reply(code: String, params: Dictionary = {}) -> String:
	var s := String(data.get("replies", {}).get(code, ""))
	for k in params:
		s = s.replace("{%s}" % k, str(params[k]))
	return s
