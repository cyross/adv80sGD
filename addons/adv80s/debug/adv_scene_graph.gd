@tool
class_name AdvSceneGraph
extends RefCounted
## シーングラフの解析・レイアウト計算・SVG/PNG出力を行うデバッグ用クラス。
## 配布するアプリ（リリースビルド）には含めない。

const MODE_OVERVIEW := "overview"
const MODE_NODE_DETAIL := "node"
const MODE_EDGE_DETAIL := "edge"


## AdvCore からシーングラフのデータを構築する。
static func build_from_core(core: AdvCore) -> Dictionary:
	if core == null:
		return {"nodes": {}, "node_order": [], "edges": [], "edge_map": {}, "start_scene": "", "current_scene": ""}
	var json_adapter: AdvJsonAdapter = null
	for a in core.adapters_by_name.values():
		if a is AdvJsonAdapter:
			json_adapter = a
			break
	if json_adapter == null and core.adapter is AdvJsonAdapter:
		json_adapter = core.adapter as AdvJsonAdapter
	var ink_adapter: AdvInkAdapter = core.adapters_by_name.get("ink") as AdvInkAdapter
	if ink_adapter == null and core.adapter is AdvInkAdapter:
		ink_adapter = core.adapter as AdvInkAdapter
	var g := build_from_adapters(json_adapter, ink_adapter)
	g["current_scene"] = core.state.scene if core.state != null else ""
	return g


## プロジェクト設定ファイルのパスからシーングラフを構築する（エディタ用）。
static func build_from_project(project_path: String = AdvProject.DEFAULT_PATH) -> Dictionary:
	var diags: Array = []
	var project := AdvProject.load_project(project_path, diags)
	var core := AdvCore.new()
	core.setup(project.core_config())
	core.use_adapter(AdvJsonAdapter.new())
	core.load_scenario(PackedStringArray(project.get_value("scenarios", [])))
	return build_from_core(core)


## JSONアダプタとInkアダプタからシーングラフを構築する。
static func build_from_adapters(json_adapter: AdvJsonAdapter, ink_adapter: AdvInkAdapter = null) -> Dictionary:
	var nodes: Dictionary = {}
	var node_order: Array = []
	var edge_map: Dictionary = {}
	var edges: Array = []
	var start_scene := ""

	if json_adapter == null:
		return {"nodes": nodes, "node_order": node_order, "edges": edges, "edge_map": edge_map, "start_scene": "", "current_scene": ""}

	start_scene = json_adapter.start_scene
	var scenes: Dictionary = json_adapter.scenes
	var dialogues: Dictionary = json_adapter.dialogues
	var topics: Dictionary = json_adapter.topics
	var items: Dictionary = json_adapter.items
	var characters: Dictionary = json_adapter.characters

	# Inkノット内の goto_scene 呼び出しを事前に解析する
	var ink_goto_map: Dictionary = _collect_ink_gotos(ink_adapter)

	# 1. 各シーン（ノード）の基本データと詳細データを構築
	for sid_v in scenes:
		var sid := String(sid_v)
		var sc = scenes[sid]
		if not sc is Dictionary:
			continue
		node_order.append(sid)
		var sname := String(sc.get("name", sid))
		var file := json_adapter._file_of("scenes", sid)

		# 背景画像情報
		var image_summary := _summarize_image(sc.get("image"))

		# スプライト情報
		var sprite_list: Array = []
		var raw_sprites = sc.get("sprites", [])
		if raw_sprites is Array:
			for sp in raw_sprites:
				if sp is Dictionary:
					sprite_list.append({
						"id": String(sp.get("id", "")),
						"image": String(sp.get("image", "")),
						"when": cond_to_text(sp.get("when")),
						"layer": String(sp.get("layer", "char")),
					})

		# 初回 (first) / 入室時 (enter) の手順と変更データ
		var first_info := _analyze_steps(sc.get("first"), dialogues, ink_goto_map)
		var enter_info := _analyze_steps(sc.get("enter"), dialogues, ink_goto_map)

		# オブジェクト情報
		var obj_list: Array = []
		var raw_objs: Dictionary = sc.get("objects", {})
		for oid_v in raw_objs:
			var oid := String(oid_v)
			var obj = raw_objs[oid]
			if not obj is Dictionary:
				continue
			var olabel := _object_display_name(oid, obj, characters)
			var on_list: Array = []
			var raw_on = obj.get("on", {})
			if raw_on is Dictionary:
				for verb_k in raw_on:
					var act := _analyze_steps(raw_on[verb_k], dialogues, ink_goto_map)
					on_list.append({
						"verb": String(verb_k),
						"effects": act["effects"],
						"conditions": act["conditions"],
						"gotos": act["gotos"],
						"dialogues": act["dialogues"],
						"code": steps_to_code(raw_on[verb_k]),
					})
			obj_list.append({
				"id": oid,
				"label": olabel,
				"names": obj.get("names", []).duplicate() if obj.get("names") is Array else [],
				"character": String(obj.get("character", "")),
				"when": cond_to_text(obj.get("when")),
				"region": obj.get("region", []),
				"sprite": String(obj.get("sprite", "")),
				"actions": on_list,
			})

		# 出口情報
		var exit_list: Array = []
		var raw_exits: Dictionary = sc.get("exits", {})
		for eid_v in raw_exits:
			var eid := String(eid_v)
			var ex = raw_exits[eid]
			var target_name := String(scenes.get(eid, {}).get("name", eid)) if scenes.get(eid) is Dictionary else eid
			var elabel := target_name
			var ewhen := ""
			var enames: Array = []
			var eactions: Array = []
			if ex is Dictionary:
				elabel = String(ex.get("label", target_name))
				ewhen = cond_to_text(ex.get("when"))
				if ex.get("names") is Array:
					enames = ex["names"].duplicate()
				if ex.get("on") is Dictionary:
					for vk in ex["on"]:
						var act := _analyze_steps(ex["on"][vk], dialogues, ink_goto_map)
						eactions.append({
							"verb": String(vk),
							"effects": act["effects"],
							"conditions": act["conditions"],
							"gotos": act["gotos"],
							"code": steps_to_code(ex["on"][vk]),
						})
			exit_list.append({
				"to": eid,
				"label": elabel,
				"names": enames,
				"when": ewhen,
				"actions": eactions,
			})

		# シーン直下の on
		var scene_on_list: Array = []
		if sc.get("on") is Dictionary:
			for vk in sc["on"]:
				var act := _analyze_steps(sc["on"][vk], dialogues, ink_goto_map)
				scene_on_list.append({
					"verb": String(vk),
					"effects": act["effects"],
					"conditions": act["conditions"],
					"gotos": act["gotos"],
					"code": steps_to_code(sc["on"][vk]),
				})

		nodes[sid] = {
			"id": sid,
			"name": sname,
			"is_start": sid == start_scene,
			"file": file,
			"image": image_summary,
			"sprites": sprite_list,
			"first": first_info,
			"enter": enter_info,
			"objects": obj_list,
			"exits": exit_list,
			"scene_on": scene_on_list,
			"raw": sc,
		}

	# 2. シーン間の遷移（エッジ）を抽出
	for sid in node_order:
		var sc: Dictionary = scenes[sid]
		# (a) exits による遷移
		var raw_exits: Dictionary = sc.get("exits", {})
		for eid_v in raw_exits:
			var eid := String(eid_v)
			var ex = raw_exits[eid]
			var ex_when := cond_to_text(ex.get("when")) if ex is Dictionary else ""
			var has_custom_move := false
			if ex is Dictionary and ex.get("on") is Dictionary:
				for vk in ex["on"]:
					if String(vk) == "MOVE":
						has_custom_move = true
					_extract_step_transitions(sid, ex["on"][vk], {
						"kind": "exit",
						"source": "出口: %s" % eid,
						"verb": String(vk),
						"base_cond": ex_when,
						"raw_step": ex["on"][vk],
						"path": "/scenes/%s/exits/%s/on/%s" % [sid, eid, vk],
					}, scenes, dialogues, ink_goto_map, edge_map, edges, nodes)
			if not has_custom_move:
				var short_cond := "MOVE" if ex_when == "" else "MOVE [%s]" % ex_when
				_add_transition(sid, eid, {
					"kind": "exit",
					"source": "出口: %s (%s)" % [eid, _scene_title(eid, scenes)],
					"verb": "MOVE",
					"condition": ex_when if ex_when != "" else "（無条件）",
					"short": short_cond,
					"effects": [],
					"code": "exits.%s (MOVE)" % eid,
					"path": "/scenes/%s/exits/%s" % [sid, eid],
				}, edge_map, edges, nodes)

		# (b) objects.<oid>.on.<verb> による遷移（人物の topics も含む）
		var raw_objs: Dictionary = sc.get("objects", {})
		for oid_v in raw_objs:
			var oid := String(oid_v)
			var obj = raw_objs[oid]
			if not obj is Dictionary:
				continue
			var obj_when := cond_to_text(obj.get("when"))
			var olabel := _object_display_name(oid, obj, characters)
			var raw_on = obj.get("on", {})
			if raw_on is Dictionary:
				for vk in raw_on:
					_extract_step_transitions(sid, raw_on[vk], {
						"kind": "object",
						"source": "物: %s (%s)" % [oid, olabel],
						"object_id": oid,
						"verb": String(vk),
						"base_cond": obj_when,
						"raw_step": raw_on[vk],
						"path": "/scenes/%s/objects/%s/on/%s" % [sid, oid, vk],
					}, scenes, dialogues, ink_goto_map, edge_map, edges, nodes)
			if obj.has("character"):
				var cid := String(obj["character"])
				var tlist = topics.get(cid, [])
				if tlist is Array:
					for tp in tlist:
						if not tp is Dictionary:
							continue
						var dlg_id := String(tp.get("dialogue", ""))
						if dialogues.has(dlg_id):
							var tp_when := _combine_cond(obj_when, cond_to_text(tp.get("when")))
							_extract_step_transitions(sid, dialogues[dlg_id], {
								"kind": "topic",
								"source": "話題: %s (%s)" % [tp.get("id", ""), tp.get("label", "")],
								"object_id": cid,
								"verb": "ASK+%s" % String(tp.get("id", "")),
								"base_cond": tp_when,
								"raw_step": dialogues[dlg_id],
								"path": "/topics/%s/%s" % [cid, tp.get("id", "")],
							}, scenes, dialogues, ink_goto_map, edge_map, edges, nodes)

		# (c) first / enter / scene.on による遷移
		for key in ["first", "enter"]:
			if sc.has(key):
				_extract_step_transitions(sid, sc[key], {
					"kind": "scene",
					"source": "シーン%s" % ("初回 (first)" if key == "first" else "入室 (enter)"),
					"object_id": "",
					"verb": key,
					"base_cond": "初回訪問" if key == "first" else "",
					"raw_step": sc[key],
					"path": "/scenes/%s/%s" % [sid, key],
				}, scenes, dialogues, ink_goto_map, edge_map, edges, nodes)
		if sc.get("on") is Dictionary:
			for vk in sc["on"]:
				_extract_step_transitions(sid, sc["on"][vk], {
					"kind": "scene",
					"source": "シーンコマンド",
					"object_id": "",
					"verb": String(vk),
					"base_cond": "",
					"raw_step": sc["on"][vk],
					"path": "/scenes/%s/on/%s" % [sid, vk],
				}, scenes, dialogues, ink_goto_map, edge_map, edges, nodes)

	# (d) items.<iid>.on 内にシーン移動がある場合
	for iid_v in items:
		var iid := String(iid_v)
		var item_def = items[iid]
		if not item_def is Dictionary or not item_def.get("on") is Dictionary:
			continue
		var ilabel := String(item_def.get("name", iid))
		for vk in item_def["on"]:
			var verb_str := String(vk)
			# どのシーンから発生するかを推定（USE+ target がそのシーンにあるか、条件に scene == X があるか）
			for sid in node_order:
				var sc: Dictionary = scenes[sid]
				if verb_str.contains("+"):
					var target_id := verb_str.get_slice("+", 1)
					if not sc.get("objects", {}).has(target_id):
						continue
				_extract_step_transitions(sid, item_def["on"][vk], {
					"kind": "item",
					"source": "アイテム: %s (%s)" % [iid, ilabel],
					"object_id": iid,
					"verb": verb_str,
					"base_cond": "has(%s)" % iid,
					"raw_step": item_def["on"][vk],
					"path": "/items/%s/on/%s" % [iid, vk],
				}, scenes, dialogues, ink_goto_map, edge_map, edges, nodes)

	# 各エッジの概要テキストを確定
	for e in edges:
		_finalize_edge_summary(e)

	return {
		"nodes": nodes,
		"node_order": node_order,
		"edges": edges,
		"edge_map": edge_map,
		"start_scene": start_scene,
		"current_scene": "",
	}


static func _scene_title(sid: String, scenes: Dictionary) -> String:
	var sc = scenes.get(sid)
	if sc is Dictionary and sc.has("name"):
		return String(sc["name"])
	return sid


static func _object_display_name(oid: String, obj: Dictionary, characters: Dictionary) -> String:
	if obj.has("label"):
		return String(obj["label"])
	if obj.has("character"):
		var c = characters.get(String(obj["character"]), {})
		if c is Dictionary and c.has("name"):
			return String(c["name"])
	var names = obj.get("names", [])
	if names is Array and not names.is_empty():
		return String(names[0])
	return oid


static func _summarize_image(im: Variant) -> String:
	if im == null:
		return "（なし）"
	if im is String:
		return im
	if im is Array:
		var parts := PackedStringArray()
		for e in im:
			if e is String:
				parts.append(e)
			elif e is Dictionary:
				var s := String(e.get("id", ""))
				if e.has("variant"):
					s += "@" + String(e["variant"])
				if e.has("when"):
					s += " [%s]" % cond_to_text(e["when"])
				parts.append(s)
		return " + ".join(parts)
	return str(im)


static func _collect_ink_gotos(ink_adapter: AdvInkAdapter) -> Dictionary:
	var res: Dictionary = {}
	if ink_adapter == null:
		return res
	for f in ink_adapter.files:
		var s: AdvInkStory = ink_adapter.stories.get(f)
		if s == null:
			continue
		for o in s.all_objects():
			if o.kind == AdvInkStory.K_DIVERT and o.d == "x" and String(o.a) == "goto_scene":
				var p: String = String(o.parent.path()) if o.parent != null else ""
				var knot: String = p.get_slice(".", 0)
				if not res.has(knot):
					res[knot] = []
	return res


## 手順を再帰的に解析し、変更されるデータ（effects）、条件（conditions）、移動先（gotos）、会話呼び出し（dialogues）を集める。
static func _analyze_steps(step: Variant, dialogues: Dictionary, ink_goto_map: Dictionary, visited_dlgs: Dictionary = {}) -> Dictionary:
	var effects: Array = []
	var conditions: Array = []
	var gotos: Array = []
	var dlg_calls: Array = []
	_walk_analyze(step, effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, visited_dlgs)
	return {
		"effects": effects,
		"conditions": conditions,
		"gotos": gotos,
		"dialogues": dlg_calls,
		"code": steps_to_code(step),
	}


static func _walk_analyze(step: Variant, effects: Array, conditions: Array, gotos: Array, dlg_calls: Array,
		dialogues: Dictionary, ink_goto_map: Dictionary, visited_dlgs: Dictionary) -> void:
	if step == null or step is String:
		return
	if step is Array:
		for sub in step:
			_walk_analyze(sub, effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, visited_dlgs)
		return
	if not step is Dictionary:
		return
	var d: Dictionary = step
	if d.has("if"):
		var c := cond_to_text(d["if"])
		if c != "" and not c in conditions:
			conditions.append(c)
		if d.has("then"):
			_walk_analyze(d["then"], effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, visited_dlgs)
		if d.has("else"):
			_walk_analyze(d["else"], effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, visited_dlgs)
		return
	if d.has("set") and d["set"] is Dictionary:
		for k in d["set"]:
			var eff := "%s = %s" % [k, _val_to_text(d["set"][k])]
			if not eff in effects:
				effects.append(eff)
		return
	if d.has("let"):
		var eff := "let: %s" % String(d["let"])
		if not eff in effects:
			effects.append(eff)
		return
	if d.has("goto"):
		var target := String(d["goto"])
		if dialogues.has(target) and not visited_dlgs.has(target):
			if not target in dlg_calls:
				dlg_calls.append(target)
			var next_v := visited_dlgs.duplicate()
			next_v[target] = true
			_walk_analyze(dialogues[target], effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, next_v)
		elif not target in gotos:
			gotos.append(target)
		return
	if d.has("call") or d.has("dialogue"):
		var dlg := String(d.get("call", d.get("dialogue", "")))
		if dlg != "" and not dlg in dlg_calls:
			dlg_calls.append(dlg)
		if dialogues.has(dlg) and not visited_dlgs.has(dlg):
			var next_v := visited_dlgs.duplicate()
			next_v[dlg] = true
			_walk_analyze(dialogues[dlg], effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, next_v)
		return
	if d.has("choice") and d["choice"] is Dictionary:
		var opts = d["choice"].get("options", [])
		if opts is Array:
			for o in opts:
				if o is Dictionary:
					if o.has("when"):
						var oc := cond_to_text(o["when"])
						if oc != "" and not oc in conditions:
							conditions.append(oc)
					if o.has("do"):
						_walk_analyze(o["do"], effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, visited_dlgs)
		return
	var ev_type := ""
	var ev_args: Dictionary = {}
	if d.has("type"):
		ev_type = String(d["type"])
		if d.get("args") is Dictionary:
			ev_args = d["args"]
	elif d.size() == 1:
		var k := String(d.keys()[0])
		if k.contains(".") or k in ["checkpoint", "wait", "group"]:
			ev_type = k
			if d[k] is Dictionary:
				ev_args = d[k]
	match ev_type:
		"state.set":
			var vname := String(ev_args.get("name", ev_args.get("var", ev_args.get("flag", ""))))
			var op := String(ev_args.get("op", "set"))
			var val := _val_to_text(ev_args.get("value", true))
			var eff := "%s (%s) %s" % [vname, op, val] if op != "set" else "%s = %s" % [vname, val]
			if not eff in effects:
				effects.append(eff)
		"item.add":
			var eff := "+アイテム: %s" % String(ev_args.get("id", ""))
			if int(ev_args.get("count", 1)) != 1:
				eff += " x%d" % int(ev_args.get("count", 1))
			if not eff in effects:
				effects.append(eff)
		"item.remove":
			var eff := "-アイテム: %s" % String(ev_args.get("id", ""))
			if not eff in effects:
				effects.append(eff)
		"flow.mark":
			var eff := "flow.mark: %s" % String(ev_args.get("node", ""))
			if not eff in effects:
				effects.append(eff)
		"objective.set":
			var eff := "目的: %s" % String(ev_args.get("text", "（クリア）"))
			if not eff in effects:
				effects.append(eff)
		"notebook.add":
			var eff := "手帳: %s" % String(ev_args.get("title", ev_args.get("id", "")))
			if not eff in effects:
				effects.append(eff)
		"hint.set":
			var eff := "ヒント更新: %s" % String(ev_args.get("topic", ""))
			if not eff in effects:
				effects.append(eff)
		"scene.goto":
			var target := String(ev_args.get("scene", ev_args.get("id", "")))
			if target != "" and not target in gotos:
				gotos.append(target)
		"group":
			if ev_args.get("events") is Array:
				_walk_analyze(ev_args["events"], effects, conditions, gotos, dlg_calls, dialogues, ink_goto_map, visited_dlgs)


## 手順の中からシーン遷移（goto / scene.goto）をすべて探し出し、その到達条件と手前の変更データを記録してエッジに追加する。
static func _extract_step_transitions(from_scene: String, step: Variant, ctx_info: Dictionary,
		scenes: Dictionary, dialogues: Dictionary, ink_goto_map: Dictionary,
		edge_map: Dictionary, edges: Array, nodes: Dictionary) -> void:
	var initial_cond := String(ctx_info.get("base_cond", ""))
	var initial_effects: Array = []
	_walk_transitions(from_scene, step, initial_cond, initial_effects, ctx_info, scenes, dialogues, ink_goto_map, {}, edge_map, edges, nodes)


static func _walk_transitions(from_scene: String, step: Variant, cur_cond: String, cur_effects: Array,
		ctx_info: Dictionary, scenes: Dictionary, dialogues: Dictionary, ink_goto_map: Dictionary,
		visited_dlgs: Dictionary, edge_map: Dictionary, edges: Array, nodes: Dictionary) -> void:
	if step == null or step is String:
		return
	if step is Array:
		var running_effects := cur_effects.duplicate()
		for sub in step:
			_collect_immediate_effects(sub, running_effects)
			_walk_transitions(from_scene, sub, cur_cond, running_effects, ctx_info, scenes, dialogues, ink_goto_map, visited_dlgs, edge_map, edges, nodes)
		return
	if not step is Dictionary:
		return
	var d: Dictionary = step
	if d.has("if"):
		var if_cond := cond_to_text(d["if"])
		var then_cond := _combine_cond(cur_cond, if_cond)
		if d.has("then"):
			_walk_transitions(from_scene, d["then"], then_cond, cur_effects.duplicate(), ctx_info, scenes, dialogues, ink_goto_map, visited_dlgs, edge_map, edges, nodes)
		if d.has("else"):
			var else_cond := _combine_cond(cur_cond, _negate_cond_text(if_cond))
			_walk_transitions(from_scene, d["else"], else_cond, cur_effects.duplicate(), ctx_info, scenes, dialogues, ink_goto_map, visited_dlgs, edge_map, edges, nodes)
		return
	if d.has("choice") and d["choice"] is Dictionary:
		var opts = d["choice"].get("options", [])
		if opts is Array:
			for o in opts:
				if not o is Dictionary:
					continue
				var olabel := String(o.get("label", o.get("id", "")))
				var ocond := _combine_cond(cur_cond, cond_to_text(o.get("when")))
				ocond = _combine_cond(ocond, "選択「%s」" % olabel)
				if o.has("do"):
					_walk_transitions(from_scene, o["do"], ocond, cur_effects.duplicate(), ctx_info, scenes, dialogues, ink_goto_map, visited_dlgs, edge_map, edges, nodes)
		return
	if d.has("call") or d.has("dialogue"):
		var dlg := String(d.get("call", d.get("dialogue", "")))
		if dialogues.has(dlg) and not visited_dlgs.has(dlg):
			var next_v := visited_dlgs.duplicate()
			next_v[dlg] = true
			var next_ctx := ctx_info.duplicate()
			next_ctx["source"] = "%s → 会話: %s" % [ctx_info.get("source", ""), dlg]
			_walk_transitions(from_scene, dialogues[dlg], cur_cond, cur_effects.duplicate(), next_ctx, scenes, dialogues, ink_goto_map, next_v, edge_map, edges, nodes)
		return
	if d.has("goto"):
		var target := String(d["goto"])
		var in_dlg := String(ctx_info.get("path", "")).begins_with("/dialogues/") or not visited_dlgs.is_empty()
		if dialogues.has(target) and (in_dlg or not scenes.has(target)):
			if not visited_dlgs.has(target):
				var next_v := visited_dlgs.duplicate()
				next_v[target] = true
				var next_ctx := ctx_info.duplicate()
				next_ctx["source"] = "%s → 会話: %s" % [ctx_info.get("source", ""), target]
				_walk_transitions(from_scene, dialogues[target], cur_cond, cur_effects.duplicate(), next_ctx, scenes, dialogues, ink_goto_map, next_v, edge_map, edges, nodes)
			return
		_register_goto(from_scene, target, cur_cond, cur_effects, ctx_info, scenes, edge_map, edges, nodes)
		return
	var ev_type := ""
	var ev_args: Dictionary = {}
	if d.has("type"):
		ev_type = String(d["type"])
		if d.get("args") is Dictionary:
			ev_args = d["args"]
	elif d.size() == 1:
		var k := String(d.keys()[0])
		if k.contains(".") or k in ["checkpoint", "wait", "group"]:
			ev_type = k
			if d[k] is Dictionary:
				ev_args = d[k]
	if ev_type == "scene.goto":
		var target := String(ev_args.get("scene", ev_args.get("id", "")))
		if target != "":
			_register_goto(from_scene, target, cur_cond, cur_effects, ctx_info, scenes, edge_map, edges, nodes)
	elif ev_type == "group" and ev_args.get("events") is Array:
		_walk_transitions(from_scene, ev_args["events"], cur_cond, cur_effects.duplicate(), ctx_info, scenes, dialogues, ink_goto_map, visited_dlgs, edge_map, edges, nodes)


static func _collect_immediate_effects(step: Variant, effects: Array) -> void:
	if not step is Dictionary:
		return
	var d: Dictionary = step
	if d.has("set") and d["set"] is Dictionary:
		for k in d["set"]:
			var eff := "%s = %s" % [k, _val_to_text(d["set"][k])]
			if not eff in effects:
				effects.append(eff)
	elif d.has("let"):
		var eff := "let: %s" % String(d["let"])
		if not eff in effects:
			effects.append(eff)
	elif d.has("if"):
		# `if not X then set X = true` のような直前の前提条件つき代入も記録
		var c := cond_to_text(d["if"])
		var sub_effs: Array = []
		if d.get("then") is Array:
			for s in d["then"]:
				_collect_immediate_effects(s, sub_effs)
		elif d.get("then") is Dictionary:
			_collect_immediate_effects(d["then"], sub_effs)
		for se in sub_effs:
			var tagged: String = "%s (if %s)" % [se, c] if c != "" else String(se)
			if not tagged in effects:
				effects.append(tagged)
	else:
		var ev_type := ""
		var ev_args: Dictionary = {}
		if d.has("type"):
			ev_type = String(d["type"])
			if d.get("args") is Dictionary:
				ev_args = d["args"]
		elif d.size() == 1:
			var k := String(d.keys()[0])
			if k.contains("."):
				ev_type = k
				if d[k] is Dictionary:
					ev_args = d[k]
		if ev_type == "state.set":
			var vname := String(ev_args.get("name", ev_args.get("var", ev_args.get("flag", ""))))
			var val := _val_to_text(ev_args.get("value", true))
			var eff := "%s = %s" % [vname, val]
			if not eff in effects:
				effects.append(eff)
		elif ev_type == "item.add":
			var eff := "+アイテム: %s" % String(ev_args.get("id", ""))
			if not eff in effects:
				effects.append(eff)
		elif ev_type == "item.remove":
			var eff := "-アイテム: %s" % String(ev_args.get("id", ""))
			if not eff in effects:
				effects.append(eff)


static func _register_goto(from_scene: String, to_scene: String, cond_text: String, effects: Array,
		ctx_info: Dictionary, _scenes: Dictionary, edge_map: Dictionary, edges: Array, nodes: Dictionary) -> void:
	var verb := String(ctx_info.get("verb", ""))
	var obj_id := String(ctx_info.get("object_id", ""))
	var prefix := "%s: %s" % [obj_id, verb] if obj_id != "" else verb
	var short_text := prefix
	if cond_text != "":
		short_text += " [%s]" % cond_text
	_add_transition(from_scene, to_scene, {
		"kind": String(ctx_info.get("kind", "scene")),
		"source": String(ctx_info.get("source", "")),
		"verb": verb,
		"condition": cond_text if cond_text != "" else "（無条件）",
		"short": short_text,
		"effects": effects.duplicate(),
		"code": steps_to_code(ctx_info.get("raw_step")),
		"path": String(ctx_info.get("path", "")),
	}, edge_map, edges, nodes)


static func _add_transition(from_scene: String, to_scene: String, trigger: Dictionary,
		edge_map: Dictionary, edges: Array, nodes: Dictionary) -> void:
	if not nodes.has(to_scene):
		# 未定義の移動先シーンもノードとして仮登録しておく（エラー診断用にも有用）
		nodes[to_scene] = {
			"id": to_scene,
			"name": to_scene + " (未定義)",
			"is_start": false,
			"file": "",
			"image": "（未定義）",
			"sprites": [],
			"first": {"effects": [], "conditions": [], "gotos": [], "dialogues": [], "code": ""},
			"enter": {"effects": [], "conditions": [], "gotos": [], "dialogues": [], "code": ""},
			"objects": [],
			"exits": [],
			"scene_on": [],
			"raw": {},
		}
	var eid := "%s->%s" % [from_scene, to_scene]
	if not edge_map.has(eid):
		var edge := {
			"id": eid,
			"from": from_scene,
			"to": to_scene,
			"summary": "",
			"triggers": [],
		}
		edge_map[eid] = edge
		edges.append(edge)
	edge_map[eid]["triggers"].append(trigger)


static func _finalize_edge_summary(edge: Dictionary) -> void:
	var shorts := PackedStringArray()
	for tr in edge.get("triggers", []):
		var s := String(tr.get("short", ""))
		if s != "" and not s in shorts:
			shorts.append(s)
	edge["summary"] = " / ".join(shorts) if not shorts.is_empty() else "移動"


static func _combine_cond(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	if a == b:
		return a
	return "%s and %s" % [a, b]


static func _negate_cond_text(c: String) -> String:
	if c == "":
		return ""
	if c.begins_with("not "):
		return c.substr(4).strip_edges()
	if c.contains(" "):
		return "not (%s)" % c
	return "not %s" % c


## 条件式（文字列またはJSON辞書/配列）を読みやすい短い文字列に変換する。
static func cond_to_text(cond: Variant) -> String:
	if cond == null:
		return ""
	if cond is bool:
		return "" if cond else "false"
	if cond is String:
		return String(cond).strip_edges()
	if cond is Array:
		var parts := PackedStringArray()
		for c in cond:
			var t := cond_to_text(c)
			if t != "":
				parts.append(t)
		return " and ".join(parts)
	if cond is Dictionary:
		var d: Dictionary = cond
		if d.has("all") and d["all"] is Array:
			var parts := PackedStringArray()
			for c in d["all"]:
				var t := cond_to_text(c)
				if t != "":
					parts.append("(%s)" % t if t.contains(" or ") else t)
			return " and ".join(parts)
		if d.has("any") and d["any"] is Array:
			var parts := PackedStringArray()
			for c in d["any"]:
				var t := cond_to_text(c)
				if t != "":
					parts.append(t)
			return " or ".join(parts)
		if d.has("not"):
			return _negate_cond_text(cond_to_text(d["not"]))
		if d.has("var") or d.has("calc") or d.has("count"):
			var lhs := String(d.get("var", d.get("calc", "")))
			if d.has("count"):
				lhs = "count(%s)" % String(d["count"])
			var ops := {"eq": "==", "ne": "!=", "lt": "<", "le": "<=", "gt": ">", "ge": ">=", "in": "in"}
			for k in ops:
				if d.has(k):
					return "%s %s %s" % [lhs, ops[k], _val_to_text(d[k])]
			return lhs
		for fn in ["has", "visited", "talked", "read", "feature"]:
			if d.has(fn):
				return "%s(%s)" % [fn, str(d[fn])]
		if d.has("chosen"):
			var ch = d["chosen"]
			if ch is Array and ch.size() >= 2:
				return "chosen(%s, %s)" % [ch[0], ch[1]]
			return "chosen(%s)" % str(ch)
		if d.has("scene"):
			return "scene == %s" % str(d["scene"])
		if d.has("preset"):
			return "preset == %s" % str(d["preset"])
		if d.has("group"):
			return "group == %s" % str(d["group"])
		return JSON.stringify(d)
	return str(cond)


static func _val_to_text(v: Variant) -> String:
	if v is Dictionary:
		if v.has("var"):
			return String(v["var"])
		if v.has("calc"):
			return String(v["calc"])
	if v is String:
		return v if v.begins_with("=") else "\"%s\"" % v
	return JSON.stringify(v)


## 手順（配列や辞書）を見やすいコード文字列に整形する。
static func steps_to_code(step: Variant) -> String:
	if step == null:
		return "（なし）"
	return JSON.stringify(step, "  ", false)


# ---------------------------------------------------------------- レイアウト計算

## 現在の表示モード（overview / node / edge）に合わせてノードとエッジの描画座標を計算する。
## 戻り値：
## {
##   "mode": mode,
##   "focus_id": focus_id,
##   "nodes": { sid: {id, name, rect: Rect2, role: "focus"|"neighbor"|"external", sub_lines: Array, ...} },
##   "edges": [ {id, from, to, summary, start: Vector2, end: Vector2, mid: Vector2, arrow: PackedVector2Array,
##               label_rect: Rect2, dashed: bool, highlighted: bool, role: "primary"|"external", triggers: Array} ],
##   "bounds": Rect2
## }
static func compute_layout(graph: Dictionary, mode: String = MODE_OVERVIEW, focus_id: String = "",
		font: Font = null, font_size: int = 14) -> Dictionary:
	var all_nodes: Dictionary = graph.get("nodes", {})
	var node_order: Array = graph.get("node_order", [])
	for k in all_nodes:
		if not k in node_order:
			node_order.append(k)
	var all_edges: Array = graph.get("edges", [])
	var start_scene := String(graph.get("start_scene", ""))
	var current_scene := String(graph.get("current_scene", ""))

	# 各ノードのサイズと表示行を決める
	var node_boxes: Dictionary = {}
	var node_roles: Dictionary = {}
	var node_sub_lines: Dictionary = {}

	# 注目ノード・関連ノードの判定
	var primary_nodes: Dictionary = {}
	var neighbor_nodes: Dictionary = {}
	if mode == MODE_NODE_DETAIL and all_nodes.has(focus_id):
		primary_nodes[focus_id] = true
		for e in all_edges:
			if e["from"] == focus_id:
				neighbor_nodes[e["to"]] = "out"
			elif e["to"] == focus_id:
				neighbor_nodes[e["from"]] = "in" if not neighbor_nodes.has(e["from"]) else "both"
	elif mode == MODE_EDGE_DETAIL and graph.get("edge_map", {}).has(focus_id):
		var fe: Dictionary = graph["edge_map"][focus_id]
		primary_nodes[fe["from"]] = true
		primary_nodes[fe["to"]] = true
		for e in all_edges:
			if e["id"] == focus_id:
				continue
			if primary_nodes.has(e["from"]) and not primary_nodes.has(e["to"]):
				neighbor_nodes[e["to"]] = "out"
			elif primary_nodes.has(e["to"]) and not primary_nodes.has(e["from"]):
				neighbor_nodes[e["from"]] = "in"

	for sid in node_order:
		var nd: Dictionary = all_nodes[sid]
		var role := "normal"
		if mode == MODE_OVERVIEW:
			role = "normal"
		elif primary_nodes.has(sid):
			role = "focus"
		elif neighbor_nodes.has(sid):
			role = "neighbor"
		else:
			role = "external"
		node_roles[sid] = role

		var subs: Array = []
		if role == "focus":
			subs.append("背景: %s" % String(nd.get("image", "")))
			var obj_names := PackedStringArray()
			for o in nd.get("objects", []):
				obj_names.append("%s(%s)" % [o["label"], o["id"]])
			if not obj_names.is_empty():
				subs.append("物: " + ", ".join(obj_names))
			var ex_names := PackedStringArray()
			for ex in nd.get("exits", []):
				ex_names.append(String(ex["to"]))
			if not ex_names.is_empty():
				subs.append("出口: " + ", ".join(ex_names))
			var first_effs: Array = nd.get("first", {}).get("effects", [])
			if not first_effs.is_empty():
				subs.append("初回変更: " + ", ".join(PackedStringArray(first_effs.slice(0, 3))))
		else:
			var obj_count: int = nd.get("objects", []).size()
			var ex_count: int = nd.get("exits", []).size()
			subs.append("物: %d / 出口: %d" % [obj_count, ex_count])
		node_sub_lines[sid] = subs

		var title := "%s (%s)" % [nd.get("name", sid), sid]
		var w := _measure_text(font, font_size + 2, title) + 36.0
		for sl in subs:
			w = maxf(w, _measure_text(font, max(11, font_size - 2), sl) + 28.0)
		w = clampf(w, 160.0 if role != "focus" else 220.0, 360.0)
		var h := 44.0 + subs.size() * 18.0
		if role == "focus":
			h += 8.0
		node_boxes[sid] = Vector2(w, h)

	# モード別のノード座標配置
	var positions: Dictionary = {}
	if mode == MODE_NODE_DETAIL and all_nodes.has(focus_id):
		positions = _layout_node_detail(focus_id, node_order, all_edges, node_boxes, neighbor_nodes)
	elif mode == MODE_EDGE_DETAIL and graph.get("edge_map", {}).has(focus_id):
		positions = _layout_edge_detail(focus_id, graph["edge_map"][focus_id], node_order, all_edges, node_boxes)
	else:
		positions = _layout_overview(start_scene, node_order, all_edges, node_boxes)

	var layout_nodes: Dictionary = {}
	for sid in node_order:
		var nd: Dictionary = all_nodes[sid]
		var pos: Vector2 = positions.get(sid, Vector2(60, 60))
		var sz: Vector2 = node_boxes[sid]
		layout_nodes[sid] = {
			"id": sid,
			"name": String(nd.get("name", sid)),
			"is_start": bool(nd.get("is_start", false)),
			"is_current": sid == current_scene and current_scene != "",
			"role": node_roles[sid],
			"dashed": node_roles[sid] == "external",
			"rect": Rect2(pos, sz),
			"sub_lines": node_sub_lines[sid],
			"data": nd,
		}

	# エッジのジオメトリ（矢印、双方向オフセット、ラベル矩形、実線/点線）を計算
	var pair_counts: Dictionary = {}
	for e in all_edges:
		var k1 := "%s->%s" % [e["from"], e["to"]]
		pair_counts[k1] = true

	var layout_edges: Array = []
	for e in all_edges:
		var from_id := String(e["from"])
		var to_id := String(e["to"])
		if not layout_nodes.has(from_id) or not layout_nodes.has(to_id):
			continue
		var r_from: Rect2 = layout_nodes[from_id]["rect"]
		var r_to: Rect2 = layout_nodes[to_id]["rect"]

		# 3(ノード詳細)と4(遷移詳細)では、注目外の遷移を点線（dashed = true）にする（要件5）
		var is_primary_edge := true
		var is_highlighted := false
		if mode == MODE_NODE_DETAIL:
			is_primary_edge = (from_id == focus_id or to_id == focus_id)
			is_highlighted = is_primary_edge
		elif mode == MODE_EDGE_DETAIL:
			is_primary_edge = (String(e["id"]) == focus_id)
			is_highlighted = is_primary_edge

		var has_reverse := pair_counts.has("%s->%s" % [to_id, from_id]) and from_id != to_id
		var offset_px := 0.0
		if has_reverse:
			# 反対方向の矢印と重ならないよう法線方向にずらす
			offset_px = 24.0

		var geom := _compute_edge_geometry(r_from, r_to, offset_px, String(e["summary"]), font, max(11, font_size - 1))
		layout_edges.append({
			"id": String(e["id"]),
			"from": from_id,
			"to": to_id,
			"summary": String(e["summary"]),
			"summary_lines": geom["summary_lines"],
			"triggers": e["triggers"],
			"start": geom["start"],
			"end": geom["end"],
			"mid": geom["mid"],
			"arrow": geom["arrow"],
			"label_rect": geom["label_rect"],
			"dashed": not is_primary_edge,
			"highlighted": is_highlighted,
			"role": "primary" if is_primary_edge else "external",
		})

	# 全体のバウンディングボックスを計算し、負の座標があればマージン分シフトする
	var bounds := Rect2()
	var first_rect := true
	for sid in layout_nodes:
		var r: Rect2 = layout_nodes[sid]["rect"]
		bounds = r if first_rect else bounds.merge(r)
		first_rect = false
	for le in layout_edges:
		var lr: Rect2 = le["label_rect"]
		bounds = lr if first_rect else bounds.merge(lr)
		first_rect = false
	if first_rect:
		bounds = Rect2(0, 0, 640, 360)

	var margin := Vector2(48, 48)
	var shift := margin - bounds.position
	if shift != Vector2.ZERO:
		for sid in layout_nodes:
			layout_nodes[sid]["rect"].position += shift
		for le in layout_edges:
			le["start"] += shift
			le["end"] += shift
			le["mid"] += shift
			le["label_rect"].position += shift
			var pts: PackedVector2Array = le["arrow"]
			for i in pts.size():
				pts[i] += shift
			le["arrow"] = pts
		bounds.position += shift
	bounds = bounds.grow_individual(margin.x, margin.y, margin.x, margin.y)
	bounds.position = Vector2.ZERO

	return {
		"mode": mode,
		"focus_id": focus_id,
		"nodes": layout_nodes,
		"node_order": node_order,
		"edges": layout_edges,
		"bounds": bounds,
	}


static func _layout_overview(start_scene: String, node_order: Array, edges: Array, node_boxes: Dictionary) -> Dictionary:
	var depth: Dictionary = {}
	if start_scene != "" and start_scene in node_order:
		depth[start_scene] = 0
		var queue: Array = [start_scene]
		while not queue.is_empty():
			var cur := String(queue.pop_front())
			var d: int = depth[cur]
			for e in edges:
				if String(e["from"]) == cur:
					var nxt := String(e["to"])
					if not depth.has(nxt):
						depth[nxt] = d + 1
						queue.append(nxt)
	var max_d := 0
	for d in depth.values():
		max_d = maxi(max_d, int(d))
	for sid in node_order:
		if not depth.has(sid):
			max_d += 1
			depth[sid] = max_d

	var cols: Dictionary = {}
	for sid in node_order:
		var d: int = depth.get(sid, 0)
		if not cols.has(d):
			cols[d] = []
		cols[d].append(sid)

	var col_keys := cols.keys()
	col_keys.sort()
	var positions: Dictionary = {}
	var x := 60.0
	var col_gap := 210.0
	var row_gap := 76.0
	for c in col_keys:
		var sids: Array = cols[c]
		var col_w := 180.0
		var y := 60.0
		for sid in sids:
			var box: Vector2 = node_boxes[sid]
			var row_offset := (sids.find(sid) % 2) * 16.0 if sids.size() > 1 else 0.0
			positions[sid] = Vector2(x + row_offset, y)
			y += box.y + row_gap
			col_w = maxf(col_w, box.x)
		x += col_w + col_gap
	return positions


static func _layout_node_detail(focus_id: String, node_order: Array, edges: Array,
		node_boxes: Dictionary, neighbor_nodes: Dictionary) -> Dictionary:
	var positions: Dictionary = {}
	var center_pos := Vector2(400, 180)
	var center_box: Vector2 = node_boxes.get(focus_id, Vector2(220, 80))
	positions[focus_id] = center_pos

	var in_only: Array = []
	var out_or_both: Array = []
	var externals: Array = []
	for sid in node_order:
		if sid == focus_id:
			continue
		var rel := String(neighbor_nodes.get(sid, ""))
		if rel == "in":
			in_only.append(sid)
		elif rel == "out" or rel == "both":
			out_or_both.append(sid)
		else:
			externals.append(sid)

	# 左側に流入元ノード、右側に流出先（および双方向）ノードを配置
	var left_y := center_pos.y - maxf(0.0, (in_only.size() - 1) * 72.0)
	for sid in in_only:
		var b: Vector2 = node_boxes[sid]
		positions[sid] = Vector2(center_pos.x - b.x - 210.0, left_y)
		left_y += b.y + 72.0

	var right_y := center_pos.y - maxf(0.0, (out_or_both.size() - 1) * 72.0)
	for sid in out_or_both:
		var b: Vector2 = node_boxes[sid]
		positions[sid] = Vector2(center_pos.x + center_box.x + 210.0, right_y)
		right_y += b.y + 72.0

	# ノード外のシーンはさらに外周（下段または右外）に配置して点線遷移を見せる
	var ext_x := center_pos.x + center_box.x + 510.0 if not out_or_both.is_empty() else center_pos.x + center_box.x + 220.0
	var ext_y := 80.0
	for sid in externals:
		var b: Vector2 = node_boxes[sid]
		positions[sid] = Vector2(ext_x, ext_y)
		ext_y += b.y + 64.0
	return positions


static func _layout_edge_detail(focus_edge_id: String, focus_edge: Dictionary,
		node_order: Array, _edges: Array, node_boxes: Dictionary) -> Dictionary:
	var positions: Dictionary = {}
	var from_id := String(focus_edge["from"])
	var to_id := String(focus_edge["to"])
	var from_box: Vector2 = node_boxes.get(from_id, Vector2(220, 80))
	positions[from_id] = Vector2(120, 180)
	if to_id != from_id:
		positions[to_id] = Vector2(120 + from_box.x + 250.0, 180)

	var ext_x := 120.0
	var ext_y := 340.0
	for sid in node_order:
		if sid == from_id or sid == to_id:
			continue
		var b: Vector2 = node_boxes[sid]
		positions[sid] = Vector2(ext_x, ext_y)
		ext_x += b.x + 170.0
	return positions


## 遷移条件の文字列が長いとき、複数行に折り返した配列を返す。
static func _wrap_edge_summary(summary: String, font: Font, font_size: int,
		max_line_px: float = 148.0, max_lines: int = 5) -> Array[String]:
	var clean := summary.strip_edges()
	if clean == "":
		return ["移動"]
	# まずトリガー区切り " / " で分割し、さらに条件式 "[" や論理演算子の前で分割候補を作る
	var raw_clauses := clean.split(" / ", false)
	var segments: Array[String] = []
	for rc in raw_clauses:
		var clause := String(rc).strip_edges()
		if _measure_text(font, font_size, clause) <= max_line_px:
			segments.append(clause)
			continue
		# "対象: 動詞 [条件]" の形なら "[条件]" を次行に送る
		var bracket_idx := clause.find(" [")
		if bracket_idx > 0:
			var head := clause.substr(0, bracket_idx).strip_edges()
			var tail := clause.substr(bracket_idx + 1).strip_edges()
			segments.append(head)
			segments.append(tail)
		else:
			segments.append(clause)

	var lines: Array[String] = []
	for seg in segments:
		if _measure_text(font, font_size, seg) <= max_line_px:
			lines.append(seg)
			continue
		# まだ1行に収まらない場合は文字単位で折り返す
		var cur := ""
		for i in range(seg.length()):
			var ch := seg.substr(i, 1)
			var candidate := cur + ch
			if cur != "" and _measure_text(font, font_size, candidate) > max_line_px:
				lines.append(cur.strip_edges())
				cur = ch.strip_edges() if ch == " " else ch
			else:
				cur = candidate
		if cur.strip_edges() != "":
			lines.append(cur.strip_edges())

	if lines.is_empty():
		lines.append(clean)
	if lines.size() > max_lines:
		var last_idx := max_lines - 1
		var last_line := lines[last_idx]
		if last_line.length() > 1:
			last_line = last_line.substr(0, last_line.length() - 1) + "…"
		else:
			last_line += "…"
		lines.resize(max_lines)
		lines[last_idx] = last_line
	return lines


static func _compute_edge_geometry(r_from: Rect2, r_to: Rect2, offset_px: float,
		summary: String, font: Font, font_size: int) -> Dictionary:
	var summary_lines: Array[String] = _wrap_edge_summary(summary, font, font_size, 148.0, 5)
	var line_h := float(font_size + 4)
	var max_w := 0.0
	for sl in summary_lines:
		max_w = maxf(max_w, _measure_text(font, font_size, sl))
	var lw := clampf(max_w + 14.0, 48.0, 172.0)
	var lh := float(summary_lines.size()) * line_h + 8.0

	var c_from := r_from.get_center()
	var c_to := r_to.get_center()
	if r_from == r_to:
		# 自己ループ遷移
		var p1 := Vector2(r_from.position.x + r_from.size.x * 0.7, r_from.position.y)
		var p2 := Vector2(r_from.position.x + r_from.size.x * 0.3, r_from.position.y)
		var mid := Vector2(r_from.get_center().x, r_from.position.y - 20.0 - lh * 0.5)
		var arrow := _make_arrow_head(p2, Vector2(0, 1))
		return {
			"start": p1,
			"end": p2,
			"mid": mid,
			"arrow": arrow,
			"label_rect": Rect2(mid - Vector2(lw * 0.5, lh * 0.5), Vector2(lw, lh)),
			"summary_lines": summary_lines,
		}

	var dir := (c_to - c_from).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var shifted_from := c_from + normal * offset_px
	var shifted_to := c_to + normal * offset_px

	var start_pt := _rect_border_point(r_from, shifted_from, dir)
	var end_pt := _rect_border_point(r_to, shifted_to, -dir)
	var normal_shift := (lh * 0.5 + 4.0) if offset_px != 0.0 else 0.0
	var mid_pt := (start_pt + end_pt) * 0.5 + normal * normal_shift
	var seg_dir := (end_pt - start_pt).normalized()
	var arrow := _make_arrow_head(end_pt, seg_dir)

	var label_pos := mid_pt - Vector2(lw * 0.5, lh * 0.5)
	if offset_px == 0.0:
		label_pos.y -= (lh * 0.5 + 4.0)
	var lrect := Rect2(label_pos, Vector2(lw, lh))
	# ノードと重なる場合は法線方向に避ける
	if lrect.intersects(r_from.grow(4.0)) or lrect.intersects(r_to.grow(4.0)):
		var nudge_dir := normal if normal.y <= 0.0 else -normal
		lrect.position += nudge_dir * (lh * 0.65 + 10.0)

	return {
		"start": start_pt,
		"end": end_pt,
		"mid": mid_pt,
		"arrow": arrow,
		"label_rect": lrect,
		"summary_lines": summary_lines,
	}


static func _rect_border_point(r: Rect2, origin: Vector2, dir: Vector2) -> Vector2:
	var c := r.get_center()
	var half := r.size * 0.5
	var dx := dir.x if absf(dir.x) > 0.0001 else 0.0001
	var dy := dir.y if absf(dir.y) > 0.0001 else 0.0001
	var tx := half.x / absf(dx)
	var ty := half.y / absf(dy)
	var t := minf(tx, ty)
	var pt := c + dir * t
	var perp := origin - c
	if tx < ty:
		pt.y = clampf(c.y + perp.y, r.position.y + 8.0, r.end.y - 8.0)
	else:
		pt.x = clampf(c.x + perp.x, r.position.x + 8.0, r.end.x - 8.0)
	return pt


static func _make_arrow_head(tip: Vector2, dir: Vector2, length: float = 12.0, half_width: float = 5.5) -> PackedVector2Array:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	var base := tip - d * length
	return PackedVector2Array([
		tip,
		base + n * half_width,
		base - n * half_width,
	])


static func _measure_text(font: Font, font_size: int, text: String) -> float:
	if font != null:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var w := 0.0
	for i in text.length():
		w += float(font_size) if text.unicode_at(i) > 127 else float(font_size) * 0.6
	return w


# ---------------------------------------------------------------- SVG / PNG 出力

## シーングラフを SVG 文字列として出力する。
## options:
##   scale: float (既定 1.0)
##   transparent_bg: bool (既定 false)
##   include_details: bool (既定 true)
static func to_svg(graph: Dictionary, layout: Dictionary, options: Dictionary = {}) -> String:
	var scale := maxf(0.25, float(options.get("scale", 1.0)))
	var transparent_bg := bool(options.get("transparent_bg", false))
	var bounds: Rect2 = layout.get("bounds", Rect2(0, 0, 800, 480))
	var detail_lines := _detail_summary_lines(graph, layout)
	var detail_h := (detail_lines.size() * 20.0 + 32.0) if not detail_lines.is_empty() and bool(options.get("include_details", true)) else 0.0
	var total_w := int(ceilf((bounds.size.x) * scale))
	var total_h := int(ceilf((bounds.size.y + detail_h) * scale))

	var lines := PackedStringArray()
	lines.append('<?xml version="1.0" encoding="UTF-8"?>')
	lines.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [
		total_w, total_h, int(ceilf(bounds.size.x)), int(ceilf(bounds.size.y + detail_h))
	])
	lines.append('  <style>')
	lines.append('    text { font-family: "Meiryo", "BIZ UDGothic", "Yu Gothic", "Noto Sans CJK JP", monospace; }')
	lines.append('  </style>')

	if not transparent_bg:
		lines.append('  <rect x="0" y="0" width="%d" height="%d" fill="#121620"/>' % [
			int(ceilf(bounds.size.x)), int(ceilf(bounds.size.y + detail_h))
		])

	# ヘッダータイトル
	var mode_title := _mode_title(graph, layout)
	lines.append('  <text x="16" y="24" fill="#9ec5fe" font-size="14" font-weight="bold">%s</text>' % _xml_escape(mode_title))

	# 1. エッジの線と矢印（ノードの背面に描画）
	for e in layout.get("edges", []):
		var p1: Vector2 = e["start"]
		var p2: Vector2 = e["end"]
		var dashed := bool(e.get("dashed", false))
		var hl := bool(e.get("highlighted", false))
		var stroke := "#ffd166" if hl else ("#6c757d" if dashed else "#7cc6fe")
		var sw := "2.5" if hl else ("1.5" if dashed else "2.0")
		var dash_attr := ' stroke-dasharray="6,4"' if dashed else ""
		lines.append('  <line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%s"%s/>' % [
			p1.x, p1.y, p2.x, p2.y, stroke, sw, dash_attr
		])
		var arrow: PackedVector2Array = e["arrow"]
		if arrow.size() >= 3:
			lines.append('  <polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="%s"/>' % [
				arrow[0].x, arrow[0].y, arrow[1].x, arrow[1].y, arrow[2].x, arrow[2].y, stroke
			])

	# 2. ノード（矩形とテキスト）
	var layout_nodes: Dictionary = layout.get("nodes", {})
	for sid in layout.get("node_order", []):
		if not layout_nodes.has(sid):
			continue
		var nd: Dictionary = layout_nodes[sid]
		var r: Rect2 = nd["rect"]
		var role := String(nd.get("role", "normal"))
		var nd_dashed := bool(nd.get("dashed", false))
		var fill := "#23395b" if role == "focus" else ("#18202c" if nd_dashed else "#1e293b")
		var border := "#ffd166" if role == "focus" else ("#4ade80" if nd.get("is_current", false) else ("#6c757d" if nd_dashed else "#60a5fa"))
		var bw := "2.5" if role == "focus" or nd.get("is_current", false) else "1.5"
		var dash_attr := ' stroke-dasharray="5,4"' if nd_dashed else ""
		lines.append('  <rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="6" fill="%s" stroke="%s" stroke-width="%s"%s/>' % [
			r.position.x, r.position.y, r.size.x, r.size.y, fill, border, bw, dash_attr
		])
		var badge := ""
		if nd.get("is_start", false):
			badge += "[START] "
		if nd.get("is_current", false):
			badge += "[現在] "
		var title := "%s%s (%s)" % [badge, nd["name"], sid]
		var title_c := "#ffffff" if not nd_dashed else "#b0b8c4"
		lines.append('  <text x="%.1f" y="%.1f" fill="%s" font-size="14" font-weight="bold">%s</text>' % [
			r.position.x + 12.0, r.position.y + 24.0, title_c, _xml_escape(title)
		])
		var sy := r.position.y + 44.0
		for sl in nd.get("sub_lines", []):
			lines.append('  <text x="%.1f" y="%.1f" fill="#94a3b8" font-size="12">%s</text>' % [
				r.position.x + 12.0, sy, _xml_escape(String(sl))
			])
			sy += 18.0

	# 3. エッジの遷移条件ラベル（ノードの後ろに隠れないよう最前面に複数行描画）
	for e in layout.get("edges", []):
		var dashed := bool(e.get("dashed", false))
		var hl := bool(e.get("highlighted", false))
		var stroke := "#ffd166" if hl else ("#6c757d" if dashed else "#7cc6fe")
		var dash_attr := ' stroke-dasharray="6,4"' if dashed else ""
		var lr: Rect2 = e["label_rect"]
		var label_bg := "#2b2312" if hl else ("#1a1e29" if dashed else "#1b2838")
		var label_fg := "#ffe082" if hl else ("#9aa5b4" if dashed else "#d8ecff")
		lines.append('  <rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="3" fill="%s" stroke="%s" stroke-width="1"%s/>' % [
			lr.position.x, lr.position.y, lr.size.x, lr.size.y, label_bg, stroke, dash_attr
		])
		var s_lines: Array = e.get("summary_lines", [String(e.get("summary", ""))])
		var line_y := lr.position.y + 15.0
		for sl_v in s_lines:
			var disp_text := String(sl_v)
			lines.append('  <text x="%.1f" y="%.1f" fill="%s" font-size="12">%s</text>' % [
				lr.position.x + 6.0, line_y, label_fg, _xml_escape(disp_text)
			])
			line_y += 16.0

	# 詳細モード時の詳細情報ブロック
	if detail_h > 0.0:
		var dy := bounds.size.y + 8.0
		lines.append('  <rect x="16" y="%.1f" width="%.1f" height="%.1f" rx="4" fill="#182030" stroke="#475569" stroke-width="1"/>' % [
			dy, maxf(200.0, bounds.size.x - 32.0), detail_h - 16.0
		])
		var ty := dy + 22.0
		for dl in detail_lines:
			lines.append('  <text x="28" y="%.1f" fill="#e2e8f0" font-size="12">%s</text>' % [
				ty, _xml_escape(String(dl))
			])
			ty += 20.0

	lines.append('</svg>')
	return "\n".join(lines) + "\n"


## シーングラフを PNG 用の Image としてレンダリングする。
static func to_png_image(graph: Dictionary, layout: Dictionary, options: Dictionary = {}) -> Image:
	var scale := clampf(float(options.get("scale", 1.0)), 0.5, 4.0)
	var transparent_bg := bool(options.get("transparent_bg", false))
	var bounds: Rect2 = layout.get("bounds", Rect2(0, 0, 800, 480))
	var w := maxi(64, int(ceilf(bounds.size.x * scale)))
	var h := maxi(64, int(ceilf(bounds.size.y * scale)))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0) if transparent_bg else Color.html("#121620"))

	# 1. エッジの線と矢印を描画
	for e in layout.get("edges", []):
		var p1: Vector2 = e["start"] * scale
		var p2: Vector2 = e["end"] * scale
		var dashed := bool(e.get("dashed", false))
		var hl := bool(e.get("highlighted", false))
		var col := Color.html("#ffd166") if hl else (Color.html("#6c757d") if dashed else Color.html("#7cc6fe"))
		var thick := maxf(1.0, (2.5 if hl else 2.0) * scale)
		if dashed:
			_img_draw_dashed_line(img, p1, p2, col, thick, 6.0 * scale, 4.0 * scale)
		else:
			_img_draw_line(img, p1, p2, col, thick)
		var arrow: PackedVector2Array = e["arrow"]
		if arrow.size() >= 3:
			_img_fill_triangle(img, arrow[0] * scale, arrow[1] * scale, arrow[2] * scale, col)

	# 2. ノードを描画
	var layout_nodes: Dictionary = layout.get("nodes", {})
	for sid in layout.get("node_order", []):
		if not layout_nodes.has(sid):
			continue
		var nd: Dictionary = layout_nodes[sid]
		var r := Rect2(nd["rect"].position * scale, nd["rect"].size * scale)
		var role := String(nd.get("role", "normal"))
		var nd_dashed := bool(nd.get("dashed", false))
		var fill := Color.html("#23395b") if role == "focus" else (Color.html("#18202c") if nd_dashed else Color.html("#1e293b"))
		var border := Color.html("#ffd166") if role == "focus" else (Color.html("#4ade80") if nd.get("is_current", false) else (Color.html("#6c757d") if nd_dashed else Color.html("#60a5fa")))
		_img_fill_rect(img, r, fill)
		_img_stroke_rect(img, r, border, maxi(1, int(round(2.0 * scale))), nd_dashed)

	# 3. エッジラベル枠をノードの前面に描画
	for e in layout.get("edges", []):
		var dashed := bool(e.get("dashed", false))
		var hl := bool(e.get("highlighted", false))
		var col := Color.html("#ffd166") if hl else (Color.html("#6c757d") if dashed else Color.html("#7cc6fe"))
		var lr := Rect2(e["label_rect"].position * scale, e["label_rect"].size * scale)
		var lbg := Color.html("#2b2312") if hl else (Color.html("#1a1e29") if dashed else Color.html("#1b2838"))
		_img_fill_rect(img, lr, lbg)
		_img_stroke_rect(img, lr, col, 1, dashed)

	return img


static func _mode_title(graph: Dictionary, layout: Dictionary) -> String:
	var mode := String(layout.get("mode", MODE_OVERVIEW))
	var focus_id := String(layout.get("focus_id", ""))
	if mode == MODE_NODE_DETAIL:
		var nd: Dictionary = graph.get("nodes", {}).get(focus_id, {})
		return "シーングラフ - ノード詳細: %s (%s)" % [nd.get("name", focus_id), focus_id]
	if mode == MODE_EDGE_DETAIL:
		var ed: Dictionary = graph.get("edge_map", {}).get(focus_id, {})
		return "シーングラフ - 遷移詳細: %s → %s" % [ed.get("from", ""), ed.get("to", "")]
	return "シーングラフ - 全体図"


static func _detail_summary_lines(graph: Dictionary, layout: Dictionary) -> Array:
	var mode := String(layout.get("mode", MODE_OVERVIEW))
	var focus_id := String(layout.get("focus_id", ""))
	var out: Array = []
	if mode == MODE_NODE_DETAIL and graph.get("nodes", {}).has(focus_id):
		var nd: Dictionary = graph["nodes"][focus_id]
		out.append("【シーン詳細】 %s (%s)  背景: %s" % [nd.get("name", focus_id), focus_id, nd.get("image", "")])
		for o in nd.get("objects", []):
			var w := " [条件: %s]" % o["when"] if String(o.get("when", "")) != "" else ""
			out.append("  ・物: %s (%s)%s" % [o["label"], o["id"], w])
		for e in graph.get("edges", []):
			if e["from"] == focus_id or e["to"] == focus_id:
				for tr in e.get("triggers", []):
					var eff := " / 変更: " + ", ".join(PackedStringArray(tr["effects"])) if not tr.get("effects", []).is_empty() else ""
					out.append("  ・遷移 %s → %s : %s (条件: %s%s)" % [e["from"], e["to"], tr["verb"], tr["condition"], eff])
	elif mode == MODE_EDGE_DETAIL and graph.get("edge_map", {}).has(focus_id):
		var ed: Dictionary = graph["edge_map"][focus_id]
		out.append("【遷移詳細】 %s → %s" % [ed["from"], ed["to"]])
		for tr in ed.get("triggers", []):
			var eff := " / 変更データ: " + ", ".join(PackedStringArray(tr["effects"])) if not tr.get("effects", []).is_empty() else ""
			out.append("  ・%s | 動詞: %s | 条件: %s%s" % [tr["source"], tr["verb"], tr["condition"], eff])
	return out


static func _xml_escape(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")


static func _img_fill_rect(img: Image, r: Rect2, col: Color) -> void:
	var x0 := clampi(int(r.position.x), 0, img.get_width() - 1)
	var y0 := clampi(int(r.position.y), 0, img.get_height() - 1)
	var x1 := clampi(int(r.end.x), 0, img.get_width())
	var y1 := clampi(int(r.end.y), 0, img.get_height())
	if x1 > x0 and y1 > y0:
		img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), col)


static func _img_stroke_rect(img: Image, r: Rect2, col: Color, bw: int = 1, dashed: bool = false) -> void:
	var p0 := r.position
	var p1 := Vector2(r.end.x, r.position.y)
	var p2 := r.end
	var p3 := Vector2(r.position.x, r.end.y)
	if dashed:
		_img_draw_dashed_line(img, p0, p1, col, float(bw), 5.0, 4.0)
		_img_draw_dashed_line(img, p1, p2, col, float(bw), 5.0, 4.0)
		_img_draw_dashed_line(img, p2, p3, col, float(bw), 5.0, 4.0)
		_img_draw_dashed_line(img, p3, p0, col, float(bw), 5.0, 4.0)
	else:
		_img_draw_line(img, p0, p1, col, float(bw))
		_img_draw_line(img, p1, p2, col, float(bw))
		_img_draw_line(img, p2, p3, col, float(bw))
		_img_draw_line(img, p3, p0, col, float(bw))


static func _img_draw_line(img: Image, a: Vector2, b: Vector2, col: Color, thickness: float = 1.0) -> void:
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceilf(dist * 1.5)))
	var r := maxi(0, int(floorf((thickness - 1.0) * 0.5)))
	var w := img.get_width()
	var h := img.get_height()
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var px := int(roundf(p.x))
		var py := int(roundf(p.y))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var xx := px + dx
				var yy := py + dy
				if xx >= 0 and xx < w and yy >= 0 and yy < h:
					img.set_pixel(xx, yy, col)


static func _img_draw_dashed_line(img: Image, a: Vector2, b: Vector2, col: Color, thickness: float, dash: float, gap: float) -> void:
	var total := a.distance_to(b)
	if total <= 0.001:
		return
	var dir := (b - a) / total
	var pos := 0.0
	while pos < total:
		var seg_end := minf(pos + dash, total)
		_img_draw_line(img, a + dir * pos, a + dir * seg_end, col, thickness)
		pos += dash + gap


static func _img_fill_triangle(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, col: Color) -> void:
	var min_x := clampi(int(floorf(minf(p0.x, minf(p1.x, p2.x)))), 0, img.get_width() - 1)
	var max_x := clampi(int(ceilf(maxf(p0.x, maxf(p1.x, p2.x)))), 0, img.get_width() - 1)
	var min_y := clampi(int(floorf(minf(p0.y, minf(p1.y, p2.y)))), 0, img.get_height() - 1)
	var max_y := clampi(int(ceilf(maxf(p0.y, maxf(p1.y, p2.y)))), 0, img.get_height() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d1 := (pt.x - p1.x) * (p0.y - p1.y) - (p0.x - p1.x) * (pt.y - p1.y)
			var d2 := (pt.x - p2.x) * (p1.y - p2.y) - (p1.x - p2.x) * (pt.y - p2.y)
			var d3 := (pt.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (pt.y - p0.y)
			var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
			var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
			if not (has_neg and has_pos):
				img.set_pixel(x, y, col)
