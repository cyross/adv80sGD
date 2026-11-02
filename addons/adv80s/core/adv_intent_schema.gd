class_name AdvIntentSchema
extends RefCounted
## 意図スキーマ（4.3）。動詞ごとのスロット（名前、型、助詞、必須か）を持つ。
## 層を重ねて使い、後の層が動詞・型ごとに上書きする。null を書くと取り除く。

const STANDARD := "res://addons/adv80s/data/intent_schema.standard.json"
const REFERENCE_TYPES := ["object", "item", "character", "scene", "topic", "choice"]
const BASIC_TYPES := ["number", "string", "bool", "enum", "point"]
const _DEFAULT_PARTICLES := {"target": ["を"], "with": ["で"], "topic": ["について", "のことを", "のこと"]}

var verbs: Dictionary = {}   ## 動詞ID → {"slots": [{name, type, particles, required}]}
var types: Dictionary = {}   ## 型名 → {base, ...制約} または {handler}
var slot_mode: String = "named"


func add_layer(layer: Dictionary, diags: Array = [], file: String = "") -> void:
	var t: Dictionary = layer.get("types", {})
	types = AdvJson.merge_shallow(types, t)
	var v: Dictionary = layer.get("verbs", {})
	for id in v:
		if v[id] == null:
			verbs.erase(id)
		else:
			verbs[id] = _normalize_verb(id, v[id], diags, file)


func load_layer(path: String, diags: Array = []) -> bool:
	var d = AdvJson.load_file(path, diags)
	if d is Dictionary:
		add_layer(d, diags, path)
		return true
	return false


## 省略形（"target": "object"、"with": "item?"）を完全形にそろえる。
func _normalize_verb(id: String, def: Variant, diags: Array, file: String) -> Dictionary:
	var slots: Array = []
	if def is Dictionary and def.has("slots"):
		for s in def["slots"]:
			var name := String(s.get("name", ""))
			slots.append({
				"name": name,
				"type": String(s.get("type", "object")),
				"particles": s.get("particles", _DEFAULT_PARTICLES.get(name, [])),
				"required": bool(s.get("required", true)),
			})
	elif def is Dictionary:
		for name in def:
			var type_text := String(def[name])
			var optional := type_text.ends_with("?")
			slots.append({
				"name": name,
				"type": type_text.trim_suffix("?"),
				"particles": _DEFAULT_PARTICLES.get(name, []),
				"required": not optional,
			})
	if slot_mode == "standard":
		for s in slots:
			if not s["name"] in ["target", "with"]:
				diags.append(AdvDiag.make("error", "SLOT_MISMATCH",
					"slot_mode が standard のため、スロット %s は使えません（動詞 %s）" % [s["name"], id],
					"Slot %s is not allowed in standard slot_mode (verb %s)" % [s["name"], id], file, "/verbs/%s" % id))
	return {"slots": slots}


func has_verb(id: String) -> bool:
	return verbs.has(id)


func slots(verb: String) -> Array:
	return verbs.get(verb, {}).get("slots", [])


func slot_def(verb: String, slot: String) -> Dictionary:
	for s in slots(verb):
		if s["name"] == slot:
			return s
	return {}


## 型の基になる標準の型（自作の型は base をたどる）。
func base_type(type_name: String) -> String:
	var seen := {}
	var t := type_name
	while types.has(t) and not seen.has(t):
		seen[t] = true
		var def: Dictionary = types[t]
		if not def.has("base"):
			break
		t = String(def["base"])
	return t


## スロットの型に、値の型が入れられるか。
## object は「画面の中の物」全般として、アイテムと人物も受け付ける。
func accepts(slot_type: String, value_type: String) -> bool:
	var st := base_type(slot_type)
	var vt := base_type(value_type)
	if st == vt:
		return true
	if st == "object" and vt in ["item", "character"]:
		return true
	return false


func is_known_type(type_name: String) -> bool:
	var b := base_type(type_name)
	return b in REFERENCE_TYPES or b in BASIC_TYPES or types.has(type_name)
