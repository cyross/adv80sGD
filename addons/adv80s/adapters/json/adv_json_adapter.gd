class_name AdvJsonAdapter
extends AdvScenarioAdapter
## JSONシナリオのアダプタ（5.2、5.7、5.8）。
##
## シナリオファイルの形（1ファイルに全部書いても、分けて書いてもよい）：
## {
##   "start": "hallway",
##   "variables":  { 変数名: {type, default} },
##   "characters": { 話者ID: {name, pal, voice} },
##   "items":      { アイテムID: {name, names, on: {動詞: 手順}} },
##   "scenes":     { シーンID: {name, image, first, enter, objects, exits, on} },
##   "dialogues":  { 会話ID: [手順...] },
##   "topics":     { 話者ID: [{id, label, dialogue, when}] },
##   "nouns":      { 名詞ID: [言い換え...] },  "replies": { コード: 文 },
##   "intent_schema": { 意図スキーマの層 }
## }
## シーン1つだけのファイル（"scene": "hallway" を持つ）も読める。
##
## 反応（on）の探し方：
##   1. 対象がシーンの objects にあれば、その on。"USE+door" のように「動詞+with の対象ID」を書くと優先する
##   2. 対象がシーンの exits にあれば、その on。なければ MOVE はそのシーンへ移る
##   3. 対象が持っているアイテムなら、items の on
##   4. 対象がなければ、シーンの on
##   5. 見つからなければ、辞書の fallback → default_reply → 「なにも おこらない」

var scenes: Dictionary = {}
var dialogues: Dictionary = {}
var characters: Dictionary = {}
var items: Dictionary = {}
var topics: Dictionary = {}
var variables: Dictionary = {}
var start_scene: String = ""
var intent_schema_layer: Variant = null
var event_defaults: Dictionary = {}
var flow: Dictionary = {"nodes": [], "edges": []}   ## フローチャートの構造（"flow": {nodes, edges}）
var chapters: Array = []                             ## チャプター（"chapters": [{id, label, node}]）
var asset_roots: PackedStringArray = []   ## シナリオが持つ素材フォルダ（"assets": {"root": …}）
var files: PackedStringArray = []
var sources: Dictionary = {}              ## ファイル → 読み込んだJSON（validate で使う）
var diags: Array[Dictionary] = []

const MAX_STEPS := 100000
## 「.」を含まない出力イベントの名前（短い書き方 {"checkpoint": {…}} で使える）
const _DOTLESS_EVENTS := ["checkpoint", "wait", "group"]

# 1回の処理（start や handle_intent）の間だけ使う作業用の値
var _scratch: AdvState      ## 下書きの状態。出したイベントをここにも適用して、続く条件の評価に使う
var _out: Array[Dictionary] = []
var _steps_run: int = 0
var _occurrence: Dictionary = {}

var _stack: Array = []        ## 実行中の手順 [{steps, i, path, kind}]。入力待ちで止まっても残る
var _choice: Dictionary = {}  ## 選択肢の入力待ち {id, path, options: {項目ID: 手順}, args}
var _suspended: bool = false  ## ほかのアダプタ（Ink）に処理を渡して止まっている


# ---------------------------------------------------------------- 読み込み

func load_sources(paths: PackedStringArray) -> Error:
	var result := OK
	for path in paths:
		var d = AdvJson.load_file(path, diags)
		if not d is Dictionary:
			result = ERR_PARSE_ERROR
			continue
		files.append(path)
		sources[path] = d
		_merge_source(d, path)
	ctx.state.declared = variables
	return result


func _merge_source(d: Dictionary, path: String) -> void:
	if d.has("scene"):
		var id := String(d["scene"])
		_put(scenes, id, d, path, "/scene")
		_origin["scenes/%s" % id] = path
		if start_scene == "":
			start_scene = id
	for key in ["scenes", "dialogues", "characters", "items", "topics", "variables"]:
		var table: Dictionary = get(key)
		var src: Dictionary = d.get(key, {})
		for id in src:
			_put(table, id, src[id], path, "/%s/%s" % [key, id])
	if d.has("start"):
		start_scene = String(d["start"])
	if d.get("flow") is Dictionary:
		flow["nodes"].append_array(d["flow"].get("nodes", []))
		flow["edges"].append_array(d["flow"].get("edges", []))
	if d.get("chapters") is Array:
		chapters.append_array(d["chapters"])
	if d.has("event_defaults"):
		event_defaults = AdvJson.merge(event_defaults, d["event_defaults"])
	if d.get("assets") is Dictionary and d["assets"].has("root"):
		var root := String(d["assets"]["root"])
		if not root.contains("://"):
			root = path.get_base_dir() + "/" + root
		asset_roots.append(root.trim_suffix("/"))
	if d.has("intent_schema"):
		intent_schema_layer = d["intent_schema"] if intent_schema_layer == null \
			else AdvJson.merge(intent_schema_layer, d["intent_schema"])
	var dict_layer := {}
	for key in ["nouns", "replies", "verbs", "particles"]:
		if d.has(key):
			dict_layer[key] = d[key]
	if not dict_layer.is_empty():
		ctx.dictionary.add_layer(dict_layer)


func _put(table: Dictionary, id: String, value: Variant, path: String, json_path: String) -> void:
	if table.has(id):
		diags.append(AdvDiag.make("warning", "DUPLICATE_ID", "IDが重複しています: %s" % id,
			"Duplicate ID: %s" % id, path, json_path))
	table[id] = value
	_origin["%s/%s" % [json_path.get_slice("/", 1), id]] = path


# ---------------------------------------------------------------- 実行

func start(entry: String) -> Array[Dictionary]:
	_begin()
	_stack.clear()
	_choice = {}
	_suspended = false
	var id := entry if entry != "" else start_scene
	_goto_scene(id)
	_resume()
	return _out


func handle_intent(intent: Dictionary) -> Array[Dictionary]:
	_begin()
	var verb := String(intent.get("verb", ""))
	var slots: Dictionary = intent.get("slots", {})
	if verb == "CHOOSE":
		_choose(slots.get("target"))
		_resume()
		return _out
	if not _choice.is_empty():
		ctx.warn("CHOICE_PENDING", "選択肢を選ぶまで、ほかのコマンドは受け付けません")
		return _out
	var target = slots.get("target")
	var with_v = slots.get("with")
	var scene: Dictionary = scenes.get(_scratch.scene, {})
	var reaction = null
	var path := "%s/%s" % [_scratch.scene, verb]

	if target is Dictionary:
		var tid := String(target.get("id", ""))
		path = "%s/%s/%s" % [_scratch.scene, tid, verb]
		var exits: Dictionary = scene.get("exits", {})
		var obj = _object_for(tid)
		if obj != null:
			reaction = _find_on(obj.get("on", {}), verb, with_v)
		elif exits.has(tid) and _visible(exits[tid]):
			var ex = exits[tid]
			reaction = _find_on(ex.get("on", {}) if ex is Dictionary else {}, verb, with_v)
			if reaction == null and verb == "MOVE":
				reaction = {"goto": tid}
		elif items.has(tid) and _scratch.has_item(tid):
			reaction = _find_on(items[tid].get("on", {}), verb, with_v)
		else:
			_text(ctx.reply("no_target"), path)
			return _out
		if reaction == null and verb == "ASK" and slots.has("topic"):
			reaction = _topic_reaction(tid, String(slots["topic"].get("id", "")))
	else:
		reaction = _find_on(scene.get("on", {}), verb, with_v)
		if reaction == null and verb == "ITEMS":
			_list_items()
			return _out

	if reaction == null:
		var fb := ctx.dictionary.fallback(verb)
		if fb != "" and target is Dictionary:
			var fobj = _object_for(String(target.get("id", "")))
			if fobj is Dictionary:
				reaction = _find_on(fobj.get("on", {}), fb, with_v)
	if reaction == null:
		var r := ctx.dictionary.default_reply(verb)
		reaction = r if r != "" else ctx.reply("nothing_happens")
	_stack.clear()
	_push(reaction, path, "reaction")
	_resume()
	return _out


## Ink などから戻ってきたら、止めていた手順の続きを実行する。
func resume(_result: Dictionary = {}) -> Array[Dictionary]:
	_begin()
	_suspended = false
	_resume()
	return _out


func _begin() -> void:
	_scratch = ctx.state.duplicate_state()
	_out = []
	_steps_run = 0
	_occurrence = {}


func _find_on(on: Dictionary, verb: String, with_v: Variant) -> Variant:
	if with_v is Dictionary:
		var key := "%s+%s" % [verb, AdvCore.slot_key(with_v)]
		if on.has(key):
			return on[key]
	return on.get(verb)


func _visible(def: Variant) -> bool:
	if def is Dictionary and def.has("when"):
		return ctx.eval(def["when"], _scratch)
	return true


## シーンの物を探す。キーが一致するか、character が一致するもの（見えているものだけ）。
func _object_for(id: String) -> Variant:
	var objects: Dictionary = scenes.get(_scratch.scene, {}).get("objects", {})
	if objects.has(id) and objects[id] is Dictionary and _visible(objects[id]):
		return objects[id]
	for obj in objects.values():
		if obj is Dictionary and String(obj.get("character", "")) == id and _visible(obj):
			return obj
	return null


func _topic_reaction(character: String, topic: String) -> Variant:
	for t in topics.get(character, []):
		if String(t.get("id", "")) == topic and ctx.eval(t.get("when", true), _scratch):
			return {"dialogue": t.get("dialogue", "")}
	return null


func _list_items() -> void:
	var ids := _scratch.item_ids()
	if ids.is_empty():
		_text(ctx.reply("items_none"), "items")
		return
	var names := PackedStringArray()
	for id in ids:
		names.append(item_label(id))
	_text("%s %s" % [ctx.reply("items_header"), "、".join(names)], "items")


func item_label(id: String) -> String:
	var def = items.get(id, {})
	return String(def.get("name", id)) if def is Dictionary else id


# 手順は「積み重ね（スタック）」で実行する。選択肢などの入力待ちで止まったら、続きはスタックに残り、
# 選ばれた結果（CHOOSE の意図）が届いたところから再開する。スタックはセーブにも含める。

func _push(step: Variant, path: String, kind: String = "block") -> void:
	var steps: Array = step if step is Array else [step]
	_stack.append({"steps": steps, "i": 0, "path": path, "kind": kind})


func _resume() -> void:
	while not _stack.is_empty() and _choice.is_empty() and not _suspended:
		_steps_run += 1
		if _steps_run > MAX_STEPS:
			ctx.warn("UNREACHABLE", "手順が多すぎます（循環していませんか）")
			_stack.clear()
			break
		var f: Dictionary = _stack.back()
		if int(f["i"]) >= f["steps"].size():
			_stack.pop_back()
			continue
		var step = f["steps"][f["i"]]
		f["i"] = int(f["i"]) + 1
		_exec(step, String(f["path"]))


func _exec(step: Variant, path: String) -> void:
	if step is String:
		_text(step, path)
	elif step is Array:
		_push(step, path)
	elif step is Dictionary:
		_exec_dict(step, path)


func _exec_dict(d: Dictionary, path: String) -> void:
	if d.has("if"):
		var branch = d.get("then") if ctx.eval(d["if"], _scratch) else d.get("else")
		if branch != null:
			_push(branch, path)
		return
	if d.has("set"):
		var s: Dictionary = d["set"]
		for name in s:
			var v = s[name]
			if v is String and String(v).begins_with("="):
				v = ctx.eval_expr(String(v).substr(1), _scratch)
			_emit(AdvEvents.make("state.set", {"name": name, "value": v}))
		return
	if d.has("let"):
		var stmts = AdvExpr.parse_let(String(d["let"]))
		if stmts == null:
			ctx.warn("COND_SYNTAX", "let を読めません: %s" % d["let"])
			return
		for st in stmts:
			var v = AdvCondition.eval_ast(st[1], _scratch, ctx.extra())
			_emit(AdvEvents.make("state.set", {"name": st[0], "value": v}))
		return
	if d.has("say"):
		_say(String(d["say"]), String(d.get("text", "")), path, String(d.get("id", "")), d.get("voice"))
		return
	if d.has("goto"):
		var id := String(d["goto"])
		if dialogues.has(id) and (path.begins_with("dlg:") or not scenes.has(id)):
			_jump_dialogue(id)
		else:
			_goto_scene(id)
		return
	if d.has("call") or d.has("dialogue"):
		_call_dialogue(String(d.get("call", d.get("dialogue"))))
		return
	if d.has("choice"):
		if d["choice"] is Dictionary:
			_show_choice(d["choice"], path)
		return
	if d.has("ink"):
		# Ink に処理を渡す。Core が Ink のアダプタを積み、終わったら resume で続きに戻る
		_emit(AdvEvents.make("adapter.enter", {"adapter": "ink", "entry": String(d["ink"])}))
		_suspended = true
		return
	if d.has("type"):
		_emit(d.duplicate(true))
		return
	if d.size() == 1 and (String(d.keys()[0]).contains(".") or String(d.keys()[0]) in _DOTLESS_EVENTS):
		var type := String(d.keys()[0])
		var args = d[type]
		_emit(AdvEvents.make(type, args.duplicate(true) if args is Dictionary else {}))
		return
	ctx.warn("UNKNOWN_KEY", "解釈できない手順です: %s（%s）" % [JSON.stringify(d), path])


## 会話を呼ぶ（終わったら戻る）。
func _call_dialogue(id: String) -> void:
	if not dialogues.has(id):
		ctx.warn("MISSING_TARGET", "会話が見つかりません: %s" % id)
		return
	_emit(AdvEvents.make("state.mark", {"kind": "talked", "id": id}))
	_push(dialogues[id], "dlg:" + id, "dialogue")


## 会話へ移る（戻らない）：いまの会話の続きを捨ててから呼ぶ。
func _jump_dialogue(id: String) -> void:
	while not _stack.is_empty():
		var f: Dictionary = _stack.pop_back()
		if f["kind"] == "dialogue":
			break
	_call_dialogue(id)


## シーンへ移る。いま実行中の手順は打ち切る。
func _goto_scene(id: String) -> void:
	if not scenes.has(id):
		ctx.warn("MISSING_TARGET", "シーンが見つかりません: %s" % id)
		return
	_stack.clear()
	var first := not _scratch.visited.has(id)
	_emit(AdvEvents.make("scene.goto", {"scene": id}))
	var sc: Dictionary = scenes[id]
	if sc.has("image"):
		_emit(AdvEvents.make("image.show", {"layer": "bg", "id": String(sc["image"])}))
	if first and sc.has("first"):
		_push(sc["first"], "%s/first" % id, "scene")
	elif sc.has("enter"):
		_push(sc["enter"], "%s/enter" % id, "scene")


## 選択肢を出して、選ばれるまで止まる。
func _show_choice(c: Dictionary, path: String) -> void:
	var prompt := String(c.get("prompt", ""))
	var cid := String(c.get("id", ""))
	var options: Array = c.get("options", [])
	if cid == "":
		var labels := PackedStringArray()
		for o in options:
			if o is Dictionary:
				labels.append(String(o.get("label", "")))
		cid = "%s#c%s" % [path, (prompt + "|" + "|".join(labels)).md5_text().substr(0, 8)]
	var shown := []
	var map := {}
	for i in options.size():
		var o = options[i]
		if not o is Dictionary:
			continue
		var oid := String(o.get("id", "o%d" % (i + 1)))
		if o.has("when") and not ctx.eval(o["when"], _scratch):
			continue
		if bool(o.get("once", false)) and _scratch.chosen.has("%s/%s" % [cid, oid]):
			continue
		shown.append({"id": oid, "label": String(o.get("label", oid))})
		map[oid] = o.get("do", [])
	if shown.is_empty():
		return
	var args := {"id": cid, "choices": shown}
	if prompt != "":
		args["prompt"] = prompt
	_emit(AdvEvents.make("choice.show", args))
	_choice = {"id": cid, "path": path, "options": map, "args": args}


## 選ばれた結果（CHOOSE の意図）を受け取って、続きを再開する。
func _choose(target: Variant) -> void:
	if _choice.is_empty():
		ctx.warn("CHOICE_NONE", "選択肢を出していないのに CHOOSE が届きました")
		return
	var oid := String(target.get("id", "")) if target is Dictionary else str(target)
	if not _choice["options"].has(oid):
		ctx.warn("CHOICE_UNKNOWN", "知らない選択肢の項目です: %s" % oid)
		return
	_emit(AdvEvents.make("state.mark", {"kind": "chosen", "id": "%s/%s" % [_choice["id"], oid]}))
	var steps = _choice["options"][oid]
	var path := String(_choice["path"])
	_choice = {}
	_push(steps, path)


func _emit(ev: Dictionary) -> void:
	var def = event_defaults.get(String(ev.get("type", "")))
	if def is Dictionary:
		for k in def:
			if not ev.has(k):
				ev[k] = def[k]
	if AdvEvents.is_state_event(ev):
		_scratch.apply_event(ev)
	_out.append(ev)


## 文字列の手順："文章"（地の文）、"@話者ID 文章"（台詞）、"@@…"（行頭の @ を文字として出す）。
func _text(s: String, path: String) -> void:
	if s.begins_with("@@"):
		_say("", s.substr(1), path)
	elif s.begins_with("@"):
		var rest := s.substr(1)
		var cut := -1
		for i in rest.length():
			if rest[i] == " " or rest[i] == "　":
				cut = i
				break
		if cut < 0:
			_say(rest, "", path)
		else:
			_say(rest.substr(0, cut), rest.substr(cut + 1).strip_edges(true, false), path)
	else:
		_say("", s, path)


func _say(speaker: String, body: String, path: String, id: String = "", voice: Variant = null) -> void:
	if id == "":
		id = _line_id(path, body)
	var name := ""
	if speaker != "":
		var c = characters.get(speaker, {})
		name = String(c.get("name", speaker)) if c is Dictionary else speaker
	var ev := AdvEvents.text(body, speaker, name, id)
	if speaker != "" and characters.get(speaker, {}) is Dictionary and characters[speaker].has("pal"):
		ev["args"]["pal"] = characters[speaker]["pal"]
	if voice != null:
		_emit(AdvEvents.make("voice.play", {"id": String(voice)}))
	_emit(ev)


## 行のID：場所＋本文のハッシュ。同じ場所に同じ本文があれば出現順の番号を足す。
func _line_id(path: String, body: String) -> String:
	var base := "%s#%s" % [path, body.md5_text().substr(0, 8)]
	var n: int = _occurrence.get(base, 0)
	_occurrence[base] = n + 1
	return base if n == 0 else "%s-%d" % [base, n]


# ---------------------------------------------------------------- 問い合わせ

func query(what: String, args: Dictionary = {}) -> Variant:
	match what:
		"scene":
			var sc: Dictionary = scenes.get(ctx.state.scene, {})
			return {"id": ctx.state.scene, "name": String(sc.get("name", ctx.state.scene))}
		"targets":
			return _targets()
		"items":
			var list := []
			for id in ctx.state.item_ids():
				list.append({"type": "item", "id": id, "label": item_label(id), "count": ctx.state.item_count(id)})
			return list
		"hotspots":
			var list := []
			for id in scenes.get(ctx.state.scene, {}).get("objects", {}):
				var obj = scenes[ctx.state.scene]["objects"][id]
				if obj is Dictionary and obj.has("region") and ctx.eval(obj.get("when", true)):
					var is_char: bool = obj.has("character")
					var target := String(obj["character"]) if is_char else String(id)
					list.append({"id": id, "target": target, "type": "character" if is_char else "object",
						"label": _object_label(String(id), obj), "region": obj["region"], "rect": obj["region"]})
			return list
		"flow_structure":
			return flow if not flow["nodes"].is_empty() else null
		"chapters_structure":
			return chapters if not chapters.is_empty() else null
		"topics":
			var list := []
			for t in topics.get(String(args.get("target", "")), []):
				if ctx.eval(t.get("when", true)):
					list.append({"type": "topic", "id": t["id"], "label": t.get("label", t["id"]),
						"new": not ctx.state.talked.has(String(t.get("dialogue", "")))})
			return list
		"nouns":
			return _all_names()
		"asset_roots":
			return asset_roots
		"asset_refs":
			return _asset_refs()
		"intent_schema":
			return intent_schema_layer
		"start":
			return start_scene
		"character":
			var c = characters.get(String(args.get("id", "")))
			return c.duplicate() if c is Dictionary else null
		"ink_refs":
			validate()
			return _v_ink_refs.duplicate(true)
		"pending_choice":
			return _choice.get("args") if not _choice.is_empty() else null
	return null


## いま入力で指せる対象の一覧 [{type, id, label, names}]。
func _targets() -> Array:
	var list := []
	var sc: Dictionary = scenes.get(ctx.state.scene, {})
	var objects: Dictionary = sc.get("objects", {})
	for id in objects:
		var obj = objects[id]
		if not obj is Dictionary or not ctx.eval(obj.get("when", true)):
			continue
		var type := "object"
		var names: Array = obj.get("names", []).duplicate()
		if obj.has("character"):
			type = "character"
			var c = characters.get(String(obj["character"]), {})
			if c is Dictionary and c.has("name"):
				names.append(c["name"])
			names.append_array(c.get("names", []) if c is Dictionary else [])
		var tid: String = obj.get("character", id)
		names.append_array(ctx.dictionary.noun_names(id))
		list.append({"type": type, "id": tid, "label": String(obj.get("label", names[0] if not names.is_empty() else id)), "names": names})
	var exits: Dictionary = sc.get("exits", {})
	for id in exits:
		var ex = exits[id]
		if ex is Dictionary and not ctx.eval(ex.get("when", true)):
			continue
		var names: Array = ex.get("names", []).duplicate() if ex is Dictionary else []
		var target_scene: Dictionary = scenes.get(id, {})
		if target_scene.has("name"):
			names.append(target_scene["name"])
		names.append_array(ctx.dictionary.noun_names(id))
		var label := String(ex.get("label", "")) if ex is Dictionary else ""
		if label == "":
			label = String(names[0]) if not names.is_empty() else id
		list.append({"type": "scene", "id": id, "label": label, "names": names})
	for id in ctx.state.item_ids():
		var def = items.get(id, {})
		var names: Array = def.get("names", []).duplicate() if def is Dictionary else []
		names.append(item_label(id))
		names.append_array(ctx.dictionary.noun_names(id))
		list.append({"type": "item", "id": id, "label": item_label(id), "names": names})
	return list


func _object_label(id: String, obj: Dictionary) -> String:
	if obj.has("label"):
		return String(obj["label"])
	if obj.has("character"):
		var c = characters.get(String(obj["character"]), {})
		if c is Dictionary and c.has("name"):
			return String(c["name"])
	var names: Array = obj.get("names", [])
	return String(names[0]) if not names.is_empty() else id


## シナリオ全体に出てくる呼び名（いまは指せないものも含む）。
## パーサーが「その ことばは わからない」と「そんな ものは ない」を区別するのに使う。
func _all_names() -> Array:
	var names := []
	for sid in scenes:
		var sc: Dictionary = scenes[sid]
		if sc.has("name"):
			names.append(sc["name"])
		for obj in sc.get("objects", {}).values():
			if obj is Dictionary:
				names.append_array(obj.get("names", []))
		for ex in sc.get("exits", {}).values():
			if ex is Dictionary:
				names.append_array(ex.get("names", []))
	for id in items:
		if items[id] is Dictionary:
			names.append(item_label(id))
			names.append_array(items[id].get("names", []))
	for id in characters:
		if characters[id] is Dictionary:
			if characters[id].has("name"):
				names.append(characters[id]["name"])
			names.append_array(characters[id].get("names", []))
	return names


# ---------------------------------------------------------------- セーブ

func save_state() -> Dictionary:
	return {"stack": _stack.duplicate(true), "choice": _choice.duplicate(true), "suspended": _suspended}


func load_state(data: Dictionary) -> Error:
	_stack = data.get("stack", []).duplicate(true)
	_choice = data.get("choice", {}).duplicate(true)
	_suspended = bool(data.get("suspended", false))
	for f in _stack:
		f["i"] = int(f.get("i", 0))
	return OK


# ---------------------------------------------------------------- 確認

## 出力イベントで参照している素材の種類（イベントの種類 → 素材の種類）
const _ASSET_EVENTS := {"image.show": "image", "bgm.play": "bgm", "se.play": "se", "voice.play": "voice"}

# validate の作業用
var _v_reads: Dictionary = {}     ## 読んでいる変数 → 最初に見つかった場所 [file, path]
var _v_writes: Dictionary = {}    ## 書いている変数
var _v_targets: Dictionary = {}   ## goto・出口の行き先
var _v_refs: Array = []           ## 素材の参照 [{kind, id, file, path}]
var _v_ink_refs: Array = []       ## Ink への受け渡し [{entry, file, path}]
var _v_out: Array[Dictionary] = []


func validate() -> Array[Dictionary]:
	_v_reads = {}
	_v_writes = {}
	_v_targets = {}
	_v_refs = []
	_v_ink_refs = []
	_v_out = diags.duplicate()
	for f in sources:
		for d in AdvSchemaValidator.check(sources[f], "scenario", f):
			_v_out.append(d)
	var first_file := files[0] if not files.is_empty() else ""
	if start_scene == "" or not scenes.has(start_scene):
		_v_out.append(AdvDiag.make("error", "MISSING_TARGET", "開始シーンが見つかりません: %s" % start_scene,
			"Start scene not found: %s" % start_scene, first_file, "/start"))
	_walk_all()

	for ref in _v_refs:
		if not ctx.has_asset(ref["kind"], ref["id"]):
			_v_out.append(AdvDiag.make("warning", "ASSET_NOT_FOUND", "素材が見つかりません: %s（%s）" % [ref["id"], ref["kind"]],
				"Asset not found: %s (%s)" % [ref["id"], ref["kind"]], ref["file"], ref["path"]))
	for name in _v_reads:
		if not variables.has(name) and not _v_writes.has(name):
			var at: Array = _v_reads[name]
			_v_out.append(AdvDiag.make("warning", "UNKNOWN_VARIABLE", "宣言も変更もされていない変数を参照しています: %s" % name,
				"Variable is read but never declared or set: %s" % name, at[0], at[1]))
	for sid in scenes:
		if sid != start_scene and not _v_targets.has(sid):
			_v_out.append(AdvDiag.make("info", "UNREACHABLE", "どこからも移動してこないシーンです: %s" % sid,
				"No goto or exit leads to this scene: %s" % sid, _file_of("scenes", sid), "/scenes/%s" % sid))
	return _v_out


## シナリオが参照している素材 [{kind, id, file, path}]。
func _asset_refs() -> Array:
	validate()
	return _v_refs


var _origin: Dictionary = {}


func _file_of(table: String, id: String) -> String:
	return String(_origin.get("%s/%s" % [table, id], files[0] if not files.is_empty() else ""))


func _walk_all() -> void:
	for sid in scenes:
		var sc = scenes[sid]
		if not sc is Dictionary:
			continue
		var f := _file_of("scenes", sid)
		var jp := _scene_pointer(sid, f)
		if sc.has("image"):
			_v_refs.append({"kind": "image", "id": String(sc["image"]), "file": f, "path": jp + "/image"})
		for key in ["first", "enter"]:
			if sc.has(key):
				_walk_step(sc[key], "%s/%s" % [jp, key], f, false)
		_walk_on(sc.get("on", {}), jp + "/on", f)
		for oid in sc.get("objects", {}):
			var obj = sc["objects"][oid]
			if obj is Dictionary:
				_walk_cond(obj.get("when"), "%s/objects/%s/when" % [jp, oid], f)
				_walk_on(obj.get("on", {}), "%s/objects/%s/on" % [jp, oid], f)
				if obj.has("character") and not characters.has(String(obj["character"])):
					_v_out.append(AdvDiag.make("warning", "MISSING_TARGET", "話者が定義されていません: %s" % obj["character"],
						"Speaker is not defined: %s" % obj["character"], f, "%s/objects/%s/character" % [jp, oid]))
		for eid in sc.get("exits", {}):
			_v_targets[eid] = true
			if not scenes.has(eid):
				_v_out.append(AdvDiag.make("error", "MISSING_TARGET", "出口の行き先のシーンがありません: %s" % eid,
					"Exit target scene not found: %s" % eid, f, "%s/exits/%s" % [jp, eid]))
			var ex = sc["exits"][eid]
			if ex is Dictionary:
				_walk_cond(ex.get("when"), "%s/exits/%s/when" % [jp, eid], f)
				_walk_on(ex.get("on", {}), "%s/exits/%s/on" % [jp, eid], f)
	for iid in items:
		if items[iid] is Dictionary:
			_walk_on(items[iid].get("on", {}), "/items/%s/on" % iid, _file_of("items", iid))
	for did in dialogues:
		_walk_step(dialogues[did], "/dialogues/%s" % did, _file_of("dialogues", did), true)
	for cid in topics:
		var f := _file_of("topics", cid)
		if not characters.has(cid):
			_v_out.append(AdvDiag.make("warning", "MISSING_TARGET", "話題の話者が定義されていません: %s" % cid,
				"Topic speaker is not defined: %s" % cid, f, "/topics/%s" % cid))
		var list = topics[cid]
		if list is Array:
			for i in list.size():
				var tp = list[i]
				if not tp is Dictionary:
					continue
				_walk_cond(tp.get("when"), "/topics/%s/%d/when" % [cid, i], f)
				if not dialogues.has(String(tp.get("dialogue", ""))):
					_v_out.append(AdvDiag.make("error", "MISSING_TARGET", "会話が見つかりません: %s" % tp.get("dialogue", ""),
						"Dialogue not found: %s" % tp.get("dialogue", ""), f, "/topics/%s/%d/dialogue" % [cid, i]))


## シーン1つだけのファイルでは、JSON Pointer はファイルの直下になる。
func _scene_pointer(sid: String, f: String) -> String:
	var src = sources.get(f)
	if src is Dictionary and String(src.get("scene", "")) == sid:
		return ""
	return "/scenes/%s" % sid


func _walk_on(on: Variant, jp: String, f: String) -> void:
	if not on is Dictionary:
		return
	for key in on:
		var verb := String(key).get_slice("+", 0)
		if not ctx.schema.has_verb(verb):
			_v_out.append(AdvDiag.make("error", "UNKNOWN_VERB", "知らない動詞です: %s" % verb,
				"Unknown verb: %s" % verb, f, "%s/%s" % [jp, key]))
		_walk_step(on[key], "%s/%s" % [jp, key], f, false)


func _walk_step(step: Variant, jp: String, f: String, in_dialogue: bool) -> void:
	if step is String:
		var s := String(step)
		if s.begins_with("@") and not s.begins_with("@@"):
			var speaker := s.substr(1).get_slice(" ", 0).get_slice("　", 0)
			if not characters.has(speaker):
				_v_out.append(AdvDiag.make("warning", "MISSING_TARGET", "話者が定義されていません: %s" % speaker,
					"Speaker is not defined: %s" % speaker, f, jp))
		_collect_text_vars(s, jp, f)
	elif step is Array:
		for i in step.size():
			_walk_step(step[i], "%s/%d" % [jp, i], f, in_dialogue)
	elif step is Dictionary:
		var d: Dictionary = step
		if d.has("if"):
			_walk_cond(d["if"], jp + "/if", f)
			for k in ["then", "else"]:
				if d.has(k):
					_walk_step(d[k], "%s/%s" % [jp, k], f, in_dialogue)
		if d.has("set") and d["set"] is Dictionary:
			for name in d["set"]:
				_v_writes[name] = true
				var v = d["set"][name]
				if v is String and String(v).begins_with("="):
					_collect_expr(String(v).substr(1), "%s/set/%s" % [jp, name], f)
		if d.has("let"):
			var stmts = AdvExpr.parse_let(String(d["let"]))
			if stmts == null:
				_v_out.append(AdvDiag.make("error", "COND_SYNTAX", "let を読めません: %s" % d["let"],
					"Cannot parse let: %s" % d["let"], f, jp + "/let"))
			else:
				for st in stmts:
					_v_writes[st[0]] = true
					_collect_ast(st[1], jp + "/let", f)
		if d.has("say"):
			if not characters.has(String(d["say"])):
				_v_out.append(AdvDiag.make("warning", "MISSING_TARGET", "話者が定義されていません: %s" % d["say"],
					"Speaker is not defined: %s" % d["say"], f, jp + "/say"))
			_collect_text_vars(String(d.get("text", "")), jp + "/text", f)
		if d.has("goto"):
			var id := String(d["goto"])
			_v_targets[id] = true
			if not scenes.has(id) and not dialogues.has(id):
				_v_out.append(AdvDiag.make("error", "MISSING_TARGET", "移動先が見つかりません: %s" % id,
					"goto target not found: %s" % id, f, jp + "/goto"))
		for k in ["call", "dialogue"]:
			if d.has(k) and not dialogues.has(String(d[k])):
				_v_out.append(AdvDiag.make("error", "MISSING_TARGET", "会話が見つかりません: %s" % d[k],
					"Dialogue not found: %s" % d[k], f, "%s/%s" % [jp, k]))
		if d.has("ink"):
			_v_ink_refs.append({"entry": String(d["ink"]), "file": f, "path": jp + "/ink"})
		if d.has("choice") and d["choice"] is Dictionary:
			var opts = d["choice"].get("options", [])
			if opts is Array:
				for i in opts.size():
					if opts[i] is Dictionary:
						_walk_cond(opts[i].get("when"), "%s/choice/options/%d/when" % [jp, i], f)
						if opts[i].has("do"):
							_walk_step(opts[i]["do"], "%s/choice/options/%d/do" % [jp, i], f, in_dialogue)
		# 出力イベント（完全形と短い書き方）
		var type := ""
		var args = null
		var ap := ""
		if d.has("type"):
			type = String(d["type"])
			args = d.get("args", {})
			ap = jp + "/args"
		elif d.size() == 1 and (String(d.keys()[0]).contains(".") or String(d.keys()[0]) in _DOTLESS_EVENTS):
			type = String(d.keys()[0])
			args = d[type]
			ap = "%s/%s" % [jp, _ptr(type)]
		if type == "state.set" and args is Dictionary:
			_v_writes[String(args.get("name", args.get("var", args.get("flag", ""))))] = true
		if _ASSET_EVENTS.has(type) and args is Dictionary and args.has("id"):
			_v_refs.append({"kind": _ASSET_EVENTS[type], "id": String(args["id"]), "file": f, "path": ap + "/id"})
		if type == "scene.goto" and args is Dictionary:
			_v_targets[String(args.get("scene", args.get("id", "")))] = true


func _walk_cond(cond: Variant, jp: String, f: String) -> void:
	if cond == null:
		return
	var err := AdvCondition.check(cond)
	if err != "":
		_v_out.append(AdvDiag.make("error", "COND_SYNTAX", "条件式の誤り: %s" % err,
			"Condition syntax error: %s" % err, f, jp))
		return
	_collect_cond(cond, jp, f)


## 条件の中で読んでいる変数を集める。
func _collect_cond(cond: Variant, jp: String, f: String) -> void:
	if cond is String:
		if AdvCondition.is_identifier(cond):
			_read(cond, jp, f)
		else:
			_collect_cond(AdvCondition.compile(cond), jp, f)
	elif cond is Array:
		for c in cond:
			_collect_cond(c, jp, f)
	elif cond is Dictionary:
		for k in ["all", "any"]:
			if cond.has(k):
				_collect_cond(cond[k], jp, f)
		if cond.has("not"):
			_collect_cond(cond["not"], jp, f)
		if cond.has("var"):
			_read(String(cond["var"]), jp, f)
		if cond.has("calc"):
			_collect_expr(String(cond["calc"]), jp, f)
		for op in ["eq", "ne", "lt", "le", "gt", "ge"]:
			var v = cond.get(op)
			if v is Dictionary:
				if v.has("var"):
					_read(String(v["var"]), jp, f)
				if v.has("calc"):
					_collect_expr(String(v["calc"]), jp, f)


func _collect_expr(text: String, jp: String, f: String) -> void:
	var ast = AdvExpr.parse(text)
	if ast == null:
		_v_out.append(AdvDiag.make("error", "COND_SYNTAX", "計算式を読めません: %s" % text,
			"Cannot parse expression: %s" % text, f, jp))
		return
	_collect_ast(ast, jp, f)


func _collect_ast(ast: Array, jp: String, f: String) -> void:
	match ast[0]:
		"id":
			_read(ast[1], jp, f)
		"bin":
			_collect_ast(ast[2], jp, f)
			_collect_ast(ast[3], jp, f)
		"neg", "not":
			_collect_ast(ast[1], jp, f)
		"and", "or":
			for a in ast[1]:
				_collect_ast(a, jp, f)


static var _re_text_var: RegEx


## 本文の {変数} と [var=変数]。
func _collect_text_vars(s: String, jp: String, f: String) -> void:
	if _re_text_var == null:
		_re_text_var = RegEx.create_from_string("(?<!\\{)\\{([A-Za-z_][A-Za-z0-9_]*)\\}|\\[var=([^\\]]+)\\]")
	for m in _re_text_var.search_all(s):
		var name := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
		_read(name, jp, f)


func _read(name: String, jp: String, f: String) -> void:
	if not _v_reads.has(name):
		_v_reads[name] = [f, jp]


static func _ptr(k: String) -> String:
	return k.replace("~", "~0").replace("/", "~1")
