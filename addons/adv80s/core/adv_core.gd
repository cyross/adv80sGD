class_name AdvCore
extends RefCounted
## Core（第3章）。状態を持ち、入力から来た意図をシナリオアダプタに渡し、
## 返ってきた出力イベントのうち状態を変えるものを適用して、表示側へ渡す。
##
## 使い方：
##   var core := AdvCore.new()
##   core.setup({})
##   core.use_adapter(AdvJsonAdapter.new())
##   core.load_scenario(["res://game/scenario.json"])
##   var events := core.start()
##   events = core.submit({"verb": "OPEN", "target": "door", "source": "parser"})

var state := AdvState.new()
var rng := AdvRng.new()
var dictionary := AdvDictionary.new()
var schema := AdvIntentSchema.new()
var assets := AdvAssets.new()
var config: Dictionary = {}
var ctx: AdvContext

var preset: String = "98"
var group: String = "pc80"
var features: Dictionary = {}

var _adapters: Array[AdvScenarioAdapter] = []
var diagnostics: Array = []


## 設定を読み込む。cfg の主な項目：
##   dictionaries: [追加の辞書のパス...]（標準の日本語辞書の上に重ねる）
##   lang: "ja" / "en"
##   intent_schema: {entry, layers: [{file, when}]}
##   slot_mode: "named" / "standard"
##   seed: 乱数の種（省略するとランダム）
##   event_defaults: 出力イベントの既定値の書き換え（プロジェクト設定）
##   missing_asset: "placeholder" / "error"
func setup(cfg: Dictionary = {}) -> Error:
	config = cfg
	ctx = AdvContext.new(self)
	assets.missing_asset = String(cfg.get("missing_asset", "placeholder"))
	if cfg.has("seed"):
		rng = AdvRng.new(int(cfg["seed"]))
	var lang := String(cfg.get("lang", "ja"))
	dictionary.load_layer(AdvDictionary.STANDARD_EN if lang == "en" else AdvDictionary.STANDARD_JA, diagnostics)
	for p in cfg.get("dictionaries", []):
		dictionary.load_layer(String(p), diagnostics)
	schema.slot_mode = String(cfg.get("slot_mode", "named"))
	_reload_schema()
	return OK


## 意図スキーマを読み直す（entry → 条件を満たす layers → シナリオの intent_schema）。
func _reload_schema() -> void:
	var s := AdvIntentSchema.new()
	s.slot_mode = schema.slot_mode
	var sc: Dictionary = config.get("intent_schema", {})
	s.load_layer(String(sc.get("entry", AdvIntentSchema.STANDARD)), diagnostics)
	for layer in sc.get("layers", []):
		if ctx.eval(layer.get("when", true)):
			s.load_layer(String(layer.get("file", "")), diagnostics)
	var own = query("intent_schema") if not _adapters.is_empty() else null
	if own is Dictionary:
		s.add_layer(own, diagnostics)
	schema = s


func use_adapter(adapter: AdvScenarioAdapter) -> Error:
	_adapters = [adapter]
	return adapter.setup(ctx)


var adapter: AdvScenarioAdapter:
	get:
		return null if _adapters.is_empty() else _adapters.back()


## 素材フォルダを重ねる（プロジェクト → テンプレート → シナリオ の順に呼ぶ）。
func add_asset_roots(roots: Array) -> void:
	for r in roots:
		assets.add_root(String(r), diagnostics)


func load_scenario(paths: PackedStringArray) -> Error:
	var err := adapter.load_sources(paths)
	_reload_schema()
	return err


## 始める。entry を省略するとシナリオの開始位置から。
func start(entry: String = "") -> Array[Dictionary]:
	return _commit(adapter.start(entry))


## 意図を受け取る。省略形の意図も受け付け、slots の形にそろえてから渡す。
func submit(intent: Dictionary) -> Array[Dictionary]:
	var it := normalize_intent(intent)
	var verb := String(it.get("verb", ""))
	if not schema.has_verb(verb):
		return _commit([AdvEvents.text(dictionary.reply("cannot"))])
	for s in schema.slots(verb):
		if s["required"] and not it["slots"].has(s["name"]):
			return _commit([AdvEvents.text(dictionary.reply("missing_slot", {"verb": dictionary.verb_label(verb)}))])
	var key := verb
	if it["slots"].has("target"):
		key += ":" + slot_key(it["slots"]["target"])
	var events: Array[Dictionary] = [AdvEvents.make("state.mark", {"kind": "tried", "id": key})]
	events.append_array(adapter.handle_intent(it))
	return _commit(events)


## 意図を正式な形 {verb, slots, source, ext} にそろえる。
func normalize_intent(intent: Dictionary) -> Dictionary:
	var verb := String(intent.get("verb", ""))
	var slots: Dictionary = intent.get("slots", {}).duplicate(true)
	for key in intent:
		if key in ["verb", "slots", "source", "ext"]:
			continue
		slots[key] = intent[key]
	for name in slots.keys():
		slots[name] = _normalize_value(verb, name, slots[name])
	return {
		"verb": verb,
		"slots": slots,
		"source": String(intent.get("source", "")),
		"ext": intent.get("ext", {}),
	}


func _normalize_value(verb: String, slot: String, v: Variant) -> Variant:
	if v is Dictionary:
		return v
	var def := schema.slot_def(verb, slot)
	var t := schema.base_type(String(def.get("type", "object")))
	if v is String and t in AdvIntentSchema.REFERENCE_TYPES:
		return {"type": t, "id": v}
	if v is int or v is float:
		return {"type": "number", "value": v}
	if v is bool:
		return {"type": "bool", "value": v}
	return {"type": t if t != "" else "string", "value": v}


static func slot_key(v: Variant) -> String:
	if v is Dictionary:
		return str(v.get("id", v.get("value", "")))
	return str(v)


## 出力イベントのうち、状態を変えるものを適用する。シーン移動では意図スキーマを読み直す。
func _commit(events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var defaults: Dictionary = config.get("event_defaults", {})
	for ev in events:
		var e: Dictionary = ev
		var def = defaults.get(String(e.get("type", "")))
		if def is Dictionary:
			for k in def:
				if not e.has(k):
					e[k] = def[k]
		if AdvEvents.is_state_event(e):
			state.apply_event(e)
			if e["type"] == "scene.goto":
				_reload_schema()
		if e.get("type") == "text.show" and e.has("id"):
			state.read[String(e["id"])] = true
		out.append(e)
	return out


## 問い合わせ（5.1）。Core が答えるもの以外はアダプタに聞く。
func query(what: String, args: Dictionary = {}) -> Variant:
	match what:
		"verbs":
			var list := []
			for id in schema.verbs:
				if dictionary.has_verb(id):
					list.append({"id": id, "label": dictionary.verb_label(id), "slots": schema.slots(id)})
			return list
		"tried":
			return state.tried.keys()
	for i in range(_adapters.size() - 1, -1, -1):
		var r = _adapters[i].query(what, args)
		if r != null:
			return r
	return null


func validate() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for d in diagnostics:
		r.append(d)
	for a in _adapters:
		r.append_array(a.validate())
	return r


func save_state() -> Dictionary:
	return {"state": state.to_dict(), "rng": rng.save_state(), "adapter": adapter.save_state()}


func load_state(data: Dictionary) -> Error:
	state.from_dict(data.get("state", {}))
	rng.load_state(data.get("rng", {}))
	_reload_schema()
	return adapter.load_state(data.get("adapter", {}))
