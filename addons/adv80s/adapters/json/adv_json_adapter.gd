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
var files: PackedStringArray = []
var diags: Array[Dictionary] = []

const MAX_DEPTH := 64

# 1回の処理（start や handle_intent）の間だけ使う作業用の値
var _scratch: AdvState      ## 下書きの状態。出したイベントをここにも適用して、続く条件の評価に使う
var _out: Array[Dictionary] = []
var _depth: int = 0
var _halt: bool = false
var _occurrence: Dictionary = {}


# ---------------------------------------------------------------- 読み込み

func load_sources(paths: PackedStringArray) -> Error:
	var result := OK
	for path in paths:
		var d = AdvJson.load_file(path, diags)
		if not d is Dictionary:
			result = ERR_PARSE_ERROR
			continue
		files.append(path)
		_merge_source(d, path)
	ctx.state.declared = variables
	return result


func _merge_source(d: Dictionary, path: String) -> void:
	if d.has("scene"):
		var id := String(d["scene"])
		_put(scenes, id, d, path, "/scene")
		if start_scene == "":
			start_scene = id
	for key in ["scenes", "dialogues", "characters", "items", "topics", "variables"]:
		var table: Dictionary = get(key)
		var src: Dictionary = d.get(key, {})
		for id in src:
			_put(table, id, src[id], path, "/%s/%s" % [key, id])
	if d.has("start"):
		start_scene = String(d["start"])
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


# ---------------------------------------------------------------- 実行

func start(entry: String) -> Array[Dictionary]:
	_begin()
	var id := entry if entry != "" else start_scene
	_goto_scene(id)
	return _out


func handle_intent(intent: Dictionary) -> Array[Dictionary]:
	_begin()
	var verb := String(intent.get("verb", ""))
	var slots: Dictionary = intent.get("slots", {})
	var target = slots.get("target")
	var with_v = slots.get("with")
	var scene: Dictionary = scenes.get(_scratch.scene, {})
	var reaction = null
	var path := "%s/%s" % [_scratch.scene, verb]

	if target is Dictionary:
		var tid := String(target.get("id", ""))
		var ttype := String(target.get("type", ""))
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
	_run(reaction, path)
	return _out


func _begin() -> void:
	_scratch = ctx.state.duplicate_state()
	_out = []
	_depth = 0
	_halt = false
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


## 手順を実行する。
func _run(step: Variant, path: String) -> void:
	if _halt:
		return
	_depth += 1
	if _depth > MAX_DEPTH:
		ctx.warn("UNREACHABLE", "手順の呼び出しが深すぎます（循環していませんか）: %s" % path)
		_depth -= 1
		_halt = true
		return
	if step is String:
		_text(step, path)
	elif step is Array:
		for s in step:
			if _halt:
				break
			_run(s, path)
	elif step is Dictionary:
		_run_dict(step, path)
	_depth -= 1


func _run_dict(d: Dictionary, path: String) -> void:
	if d.has("if"):
		if ctx.eval(d["if"], _scratch):
			if d.has("then"):
				_run(d["then"], path)
		elif d.has("else"):
			_run(d["else"], path)
		return
	if d.has("set"):
		var s: Dictionary = d["set"]
		for name in s:
			var v = s[name]
			if v is String and String(v).begins_with("="):
				v = ctx.eval_expr(String(v).substr(1), _scratch)
			_emit(AdvEvents.make("state.set", {"var": name, "value": v}))
		return
	if d.has("let"):
		var stmts = AdvExpr.parse_let(String(d["let"]))
		if stmts == null:
			ctx.warn("COND_SYNTAX", "let を読めません: %s" % d["let"])
			return
		for st in stmts:
			var v = AdvCondition.eval_ast(st[1], _scratch, ctx.extra())
			_emit(AdvEvents.make("state.set", {"var": st[0], "value": v}))
		return
	if d.has("say"):
		_say(String(d["say"]), String(d.get("text", "")), path, String(d.get("id", "")), d.get("voice"))
		return
	if d.has("goto"):
		var id := String(d["goto"])
		if dialogues.has(id) and not (scenes.has(id) and not path.begins_with("dlg:")):
			_dialogue(id)
		else:
			_goto_scene(id)
		_halt = true
		return
	if d.has("call") or d.has("dialogue"):
		_dialogue(String(d.get("call", d.get("dialogue"))))
		return
	if d.has("choice"):
		ctx.warn("UNSUPPORTED", "choice は段階1ではまだ使えません: %s" % path)
		return
	if d.has("ink"):
		ctx.warn("UNSUPPORTED", "Ink アダプタは段階1ではまだ使えません: %s" % path)
		return
	if d.has("type"):
		_emit(d.duplicate(true))
		return
	if d.size() == 1 and String(d.keys()[0]).contains("."):
		var type := String(d.keys()[0])
		var args = d[type]
		_emit(AdvEvents.make(type, args if args is Dictionary else {}))
		return
	ctx.warn("UNKNOWN_KEY", "解釈できない手順です: %s（%s）" % [JSON.stringify(d), path])


func _emit(ev: Dictionary) -> void:
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


func _dialogue(id: String) -> void:
	if not dialogues.has(id):
		ctx.warn("MISSING_TARGET", "会話が見つかりません: %s" % id)
		return
	_emit(AdvEvents.make("state.mark", {"kind": "talked", "id": id}))
	var saved_halt := _halt
	_run(dialogues[id], "dlg:" + id)
	_halt = saved_halt


func _goto_scene(id: String) -> void:
	if not scenes.has(id):
		ctx.warn("MISSING_TARGET", "シーンが見つかりません: %s" % id)
		return
	var first := not _scratch.visited.has(id)
	_emit(AdvEvents.make("scene.goto", {"id": id}))
	var sc: Dictionary = scenes[id]
	if sc.has("image"):
		_emit(AdvEvents.make("image.show", {"layer": "bg", "id": String(sc["image"])}))
	var saved_halt := _halt
	_halt = false
	if first and sc.has("first"):
		_run(sc["first"], "%s/first" % id)
	elif sc.has("enter"):
		_run(sc["enter"], "%s/enter" % id)
	_halt = saved_halt


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
					list.append({"id": id, "rect": obj["region"]})
			return list
		"topics":
			var list := []
			for t in topics.get(String(args.get("target", "")), []):
				if ctx.eval(t.get("when", true)):
					list.append({"type": "topic", "id": t["id"], "label": t.get("label", t["id"])})
			return list
		"nouns":
			return _all_names()
		"intent_schema":
			return intent_schema_layer
		"start":
			return start_scene
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


# ---------------------------------------------------------------- 確認

func validate() -> Array[Dictionary]:
	var r: Array[Dictionary] = diags.duplicate()
	var file := files[0] if not files.is_empty() else ""
	if start_scene == "" or not scenes.has(start_scene):
		r.append(AdvDiag.make("error", "MISSING_TARGET", "開始シーンが見つかりません: %s" % start_scene,
			"Start scene not found: %s" % start_scene, file, "/start"))
	for sid in scenes:
		var sc: Dictionary = scenes[sid]
		if sc.has("image") and not ctx.has_asset("image", String(sc["image"])):
			r.append(AdvDiag.make("warning", "ASSET_NOT_FOUND", "画像が見つかりません: %s（代わりの表示を使います）" % sc["image"],
				"Image not found: %s (placeholder will be used)" % sc["image"], file, "/scenes/%s/image" % sid))
		for key in ["first", "enter"]:
			if sc.has(key):
				_check_steps(sc[key], "/scenes/%s/%s" % [sid, key], file, r)
		_check_on(sc.get("on", {}), "/scenes/%s/on" % sid, file, r)
		for oid in sc.get("objects", {}):
			var obj = sc["objects"][oid]
			if obj is Dictionary:
				_check_cond(obj.get("when"), "/scenes/%s/objects/%s/when" % [sid, oid], file, r)
				_check_on(obj.get("on", {}), "/scenes/%s/objects/%s/on" % [sid, oid], file, r)
		for eid in sc.get("exits", {}):
			if not scenes.has(eid):
				r.append(AdvDiag.make("error", "MISSING_TARGET", "出口の行き先のシーンがありません: %s" % eid,
					"Exit target scene not found: %s" % eid, file, "/scenes/%s/exits/%s" % [sid, eid]))
	for iid in items:
		if items[iid] is Dictionary:
			_check_on(items[iid].get("on", {}), "/items/%s/on" % iid, file, r)
	for did in dialogues:
		_check_steps(dialogues[did], "/dialogues/%s" % did, file, r)
	return r


func _check_on(on: Dictionary, jp: String, file: String, r: Array[Dictionary]) -> void:
	for key in on:
		var verb := String(key).get_slice("+", 0)
		if not ctx.schema.has_verb(verb):
			r.append(AdvDiag.make("error", "UNKNOWN_VERB", "知らない動詞です: %s" % verb,
				"Unknown verb: %s" % verb, file, "%s/%s" % [jp, key]))
		_check_steps(on[key], "%s/%s" % [jp, key], file, r)


func _check_steps(step: Variant, jp: String, file: String, r: Array[Dictionary]) -> void:
	if step is Array:
		for i in step.size():
			_check_steps(step[i], "%s/%d" % [jp, i], file, r)
	elif step is Dictionary:
		if step.has("if"):
			_check_cond(step["if"], jp + "/if", file, r)
			for k in ["then", "else"]:
				if step.has(k):
					_check_steps(step[k], "%s/%s" % [jp, k], file, r)
		if step.has("goto"):
			var id := String(step["goto"])
			if not scenes.has(id) and not dialogues.has(id):
				r.append(AdvDiag.make("error", "MISSING_TARGET", "移動先が見つかりません: %s" % id,
					"goto target not found: %s" % id, file, jp + "/goto"))
		for k in ["call", "dialogue"]:
			if step.has(k) and not dialogues.has(String(step[k])):
				r.append(AdvDiag.make("error", "MISSING_TARGET", "会話が見つかりません: %s" % step[k],
					"Dialogue not found: %s" % step[k], file, "%s/%s" % [jp, k]))


func _check_cond(cond: Variant, jp: String, file: String, r: Array[Dictionary]) -> void:
	if cond == null:
		return
	var err := AdvCondition.check(cond)
	if err != "":
		r.append(AdvDiag.make("error", "COND_SYNTAX", "条件式の誤り: %s" % err,
			"Condition syntax error: %s" % err, file, jp))
