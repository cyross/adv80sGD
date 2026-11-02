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

## 全プレイ共通の進行の記録（フローチャートとチャプター選択に使う。なくてもよい）
var progress: AdvProgress = null

var preset: String = "98"
var group: String = "pc80"
var features: Dictionary = {}

var _adapters: Array[AdvScenarioAdapter] = []   ## 積み上げているアダプタ（最後が処理中のもの）
var adapters_by_name: Dictionary = {}            ## 名前 → アダプタ（積んでいないものも含む）
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


## 主となるアダプタを決める（それまでのアダプタはすべて外す）。
func use_adapter(adapter: AdvScenarioAdapter, name: String = "main") -> Error:
	_adapters = [adapter]
	adapters_by_name = {name: adapter}
	return adapter.setup(ctx)


## 受け渡し先のアダプタを足す（{"ink": …} の手順で積まれる）。
func add_adapter(name: String, a: AdvScenarioAdapter) -> Error:
	adapters_by_name[name] = a
	return a.setup(ctx)


func adapter_name(a: AdvScenarioAdapter) -> String:
	for k in adapters_by_name:
		if adapters_by_name[k] == a:
			return k
	return ""


var adapter: AdvScenarioAdapter:
	get:
		return null if _adapters.is_empty() else _adapters.back()


## 素材フォルダを重ねる（プロジェクト → テンプレート → シナリオ の順に呼ぶ）。
func add_asset_roots(roots: Array) -> void:
	for r in roots:
		assets.add_root(String(r), diagnostics)


## シナリオを読む。.ink.json は Ink のアダプタに、それ以外は主のアダプタに渡す。
## .ink.json だけなら Ink のアダプタを主にする。
func load_scenario(paths: PackedStringArray) -> Error:
	var main := PackedStringArray()
	var ink := PackedStringArray()
	for p in paths:
		if String(p).ends_with(".ink.json"):
			ink.append(p)
		else:
			main.append(p)
	var err := OK
	if not ink.is_empty():
		var ia: AdvScenarioAdapter = adapters_by_name.get("ink")
		if ia == null:
			ia = AdvInkAdapter.new()
			if main.is_empty():
				use_adapter(ia, "ink")
			else:
				add_adapter("ink", ia)
		err = ia.load_sources(ink)
	if not main.is_empty() or ink.is_empty():
		var e2 := _adapters[0].load_sources(main)
		if err == OK:
			err = e2
	_apply_globals()
	_reload_schema()
	return err


## 全シナリオで共通の変数と定数（プロジェクト設定の variables・constants）を、シナリオの宣言と合わせる。
## 同じ名前があればシナリオの宣言を使う（validate が警告する）。
func _apply_globals() -> void:
	var decl: Dictionary = config.get("variables", {}).duplicate(true)
	for n in state.declared:
		decl[n] = state.declared[n]
	state.declared = decl
	var consts: Dictionary = config.get("constants", {}).duplicate(true)
	for a in _adapters + adapters_by_name.values():
		if a != null and a.get("constants") is Dictionary:
			for n in a.constants:
				consts[n] = a.constants[n]
	state.constants = consts


## 始める。entry を省略するとシナリオの開始位置から。
func start(entry: String = "") -> Array[Dictionary]:
	_adapters = [_adapters[0]]
	return _drive(_adapters[0].start(entry))


## 意図を受け取る。省略形の意図も受け付け、slots の形にそろえてから渡す。
func submit(intent: Dictionary) -> Array[Dictionary]:
	var it := normalize_intent(intent)
	var verb := String(it.get("verb", ""))
	var pending = query("pending_choice")
	if verb != "CHOOSE" and pending != null and not (pending is Dictionary and pending.get("accepts_intents", false)):
		return []  # 選択肢を選ぶまでは、ほかの意図を受け付けない（Ink の intent タグつきの選択肢は除く）
	if not schema.has_verb(verb):
		return _commit([AdvEvents.text(dictionary.reply("cannot"))])
	for s in schema.slots(verb):
		if s["required"] and not it["slots"].has(s["name"]):
			# 足りないスロットを聞き返す（入力UIが候補を出し、埋めてからもう一度送る）
			return _commit([AdvEvents.make("input.request", {
				"slot": s["name"], "type": s["type"], "verb": verb,
				"prompt": dictionary.reply("missing_slot", {"verb": dictionary.verb_label(verb)}),
				"intent": it,
			})])
	var events: Array[Dictionary] = []
	if verb != "CHOOSE":
		var key := verb
		if it["slots"].has("target"):
			key += ":" + slot_key(it["slots"]["target"])
		events.append(AdvEvents.make("state.mark", {"kind": "tried", "id": key}))
	events.append_array(adapter.handle_intent(it))
	return _drive(events)


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


## アダプタから届いた出力イベントを順に処理する。adapter.enter でアダプタを積んで start を、
## adapter.exit で積んだアダプタを外して下のアダプタの resume を呼び、その出力を続けて処理する。
## この2つのイベントは表示側へは渡さない。
func _drive(events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var queue: Array = events.duplicate()
	var switches := 0
	while not queue.is_empty():
		var e: Dictionary = queue.pop_front()
		var t := String(e.get("type", ""))
		if t == "adapter.enter" or t == "adapter.exit":
			switches += 1
			if switches > 1000:
				AdvDiag.debug_warn("UNREACHABLE", "アダプタの受け渡しが多すぎます", "Too many adapter switches")
				break
			var more: Array = _switch_adapter(e)
			queue = more + queue
			continue
		out.append_array(_commit([e]))
	return out


func _switch_adapter(e: Dictionary) -> Array:
	var args: Dictionary = e.get("args", {})
	if e["type"] == "adapter.enter":
		var name := String(args.get("adapter", ""))
		var a: AdvScenarioAdapter = adapters_by_name.get(name)
		if a == null:
			AdvDiag.debug_warn("UNSUPPORTED", "アダプタがありません: %s" % name, "Adapter not found: %s" % name)
			return adapter.resume({"error": "no_adapter"})
		_adapters.append(a)
		return a.start(String(args.get("entry", "")))
	if _adapters.size() <= 1:
		return []  # 主のアダプタが終わった
	_adapters.pop_back()
	return adapter.resume(args)


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
			# 既読スキップのため、この表示の前に読んでいたかを残しておく
			if not e.has("ext"):
				e["ext"] = {}
			e["ext"]["was_read"] = state.read.has(String(e["id"])) or (progress != null and progress.read.has(String(e["id"])))
			state.read[String(e["id"])] = true
		out.append(e)
	return out


## 問い合わせ（5.1）。Core が答えるもの以外はアダプタに聞く。
func query(what: String, args: Dictionary = {}) -> Variant:
	match what:
		"verbs":
			return _query_verbs()
		"tried":
			return state.tried.keys()
		"objective":
			return state.objective.duplicate() if not state.objective.is_empty() else null
		"notebook":
			var cat := String(args.get("category", ""))
			var list := []
			for id in state.notebook:
				var n: Dictionary = state.notebook[id]
				if cat == "" or n["category"] == cat:
					list.append({"id": id, "category": n["category"], "title": n["title"], "body": n["body"], "order": n["order"]})
			list.sort_custom(func(x, y): return x["order"] < y["order"])
			return list
		"hints":
			var topic := String(args.get("topic", ""))
			var list := []
			for t in state.hints:
				if topic != "" and t != topic:
					continue
				var h: Dictionary = state.hints[t]
				var n := int(h["revealed"])
				list.append({"topic": t, "stages": h["hints"].size(), "revealed": n, "texts": h["hints"].slice(0, n)})
			return list
		"flow":
			var st = _adapter_query("flow_structure", args)
			if not st is Dictionary:
				return null
			var nodes := []
			for n in st.get("nodes", []):
				var id := String(n.get("id", ""))
				var reached := state.flow.has(id) or (progress != null and progress.reached.has(id))
				nodes.append({"id": id, "label": String(n.get("label", id)), "chapter": String(n.get("chapter", "")),
					"reached": reached, "can_jump": progress != null and progress.snapshots.has(id)})
			return {"nodes": nodes, "edges": st.get("edges", []).duplicate(true)}
		"chapters":
			var st = _adapter_query("chapters_structure", args)
			if not st is Array:
				return null
			var list := []
			for c in st:
				var node := String(c.get("node", c.get("id", "")))
				var unlocked := bool(c.get("unlocked", false)) or state.flow.has(node) or (progress != null and progress.reached.has(node))
				list.append({"id": String(c.get("id", "")), "label": String(c.get("label", "")), "node": node,
					"unlocked": unlocked, "can_jump": progress != null and progress.snapshots.has(node)})
			return list
		"hotspots":
			var hs = _adapter_query("hotspots", args)
			if not hs is Array:
				return hs
			var hidden: Dictionary = state.ui.get("hidden", {})
			var shown = state.ui.get("shown")
			var list := []
			for h in hs:
				var id := String(h["id"])
				if hidden.has(id) or (shown is Array and not id in shown):
					continue
				var tried_verbs := []
				for k in state.tried:
					var parts := String(k).split(":")
					if parts.size() == 2 and parts[1] == String(h.get("target", id)):
						tried_verbs.append(parts[0])
				var e: Dictionary = h.duplicate()
				e["tried_verbs"] = tried_verbs
				e["new"] = tried_verbs.is_empty()
				list.append(e)
			return list
	return _adapter_query(what, args)


func _adapter_query(what: String, args: Dictionary) -> Variant:
	for i in range(_adapters.size() - 1, -1, -1):
		var r = _adapters[i].query(what, args)
		if r != null:
			return r
	for a in adapters_by_name.values():
		if not a in _adapters:
			var r = a.query(what, args)
			if r != null:
				return r
	return null


## 使える動詞の一覧 [{id, label, slots, enabled, tried}]。
## 標準は辞書にある基本の動詞（extended でないもの）。プロジェクト設定 verbs で足し、verbs.update で変えられる。
func _query_verbs() -> Array:
	var ids: Array = []
	var ui_verbs = state.ui.get("verbs")
	if ui_verbs is Array:
		ids = ui_verbs.duplicate()
	else:
		for id in schema.verbs:
			if dictionary.has_verb(id) and not dictionary.is_extended(id):
				ids.append(id)
		for id in config.get("verbs", []):
			if not id in ids:
				ids.append(id)
		for id in state.ui.get("verbs_added", []):
			if not id in ids:
				ids.append(id)
		for id in state.ui.get("verbs_removed", []):
			ids.erase(id)
	var list := []
	for id in ids:
		if not schema.has_verb(id) or not dictionary.has_verb(id):
			continue
		var tried := false
		for k in state.tried:
			if String(k) == id or String(k).begins_with(id + ":"):
				tried = true
				break
		list.append({"id": id, "label": dictionary.verb_label(id), "slots": schema.slots(id), "enabled": true, "tried": tried})
	return list


## ヒントを1段階進める（モダン機能 hint）。進めたら true。
func reveal_hint(topic: String) -> bool:
	return state.reveal_hint(topic)


func validate() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for d in diagnostics:
		r.append(d)
	for a in adapters_by_name.values():
		r.append_array(a.validate())
	return r


## セーブ：状態、乱数、すべてのアダプタの状態、積み上げの順番。
func save_state() -> Dictionary:
	var ad := {}
	for k in adapters_by_name:
		ad[k] = adapters_by_name[k].save_state()
	var active := []
	for a in _adapters:
		active.append(adapter_name(a))
	return {"state": state.to_dict(), "rng": rng.save_state(), "adapters": ad, "active": active}


func load_state(data: Dictionary) -> Error:
	state.from_dict(data.get("state", {}))
	rng.load_state(data.get("rng", {}))
	_reload_schema()
	if not data.has("adapters"):
		# 段階6までの形（主のアダプタだけ）
		_adapters = [_adapters[0]]
		return _adapters[0].load_state(data.get("adapter", {}))
	var err := OK
	var ad: Dictionary = data["adapters"]
	for k in ad:
		if adapters_by_name.has(k):
			var e: Error = adapters_by_name[k].load_state(ad[k])
			if e != OK:
				err = e
	var stack: Array[AdvScenarioAdapter] = []
	for n in data.get("active", []):
		if adapters_by_name.has(String(n)):
			stack.append(adapters_by_name[String(n)])
	if stack.is_empty():
		stack = [_adapters[0]]
	_adapters = stack
	return err
