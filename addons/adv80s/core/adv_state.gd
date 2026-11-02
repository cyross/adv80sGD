class_name AdvState
extends RefCounted
## ゲームの状態（フラグと変数、所持品、現在のシーン、到達記録）。
## 変更は Core が出力イベント（state.set、item.add など）を実行するときだけ行う。
## シナリオ側には読み取り用として渡す。

var vars: Dictionary = {}        ## フラグと変数（名前 → 値）
var items: Dictionary = {}       ## 所持品（アイテムID → 個数）。並び順は手に入れた順
var scene: String = ""           ## 現在のシーンID
var visited: Dictionary = {}     ## 訪れたシーン（シーンID → true）
var talked: Dictionary = {}      ## 見た会話（会話ID → true）
var read: Dictionary = {}        ## 読んだ行（行ID → true）
var chosen: Dictionary = {}      ## 選んだ選択肢（"選択肢ID/項目ID" → true）
var tried: Dictionary = {}       ## 試したコマンド（"動詞:対象" → true）

# モダン機能の記録（出力イベントで Core が更新する）
var notebook: Dictionary = {}    ## 手帳（ID → {category, title, body, order}）
var objective: Dictionary = {}   ## 目的 {id, text}。空なら目的なし
var hints: Dictionary = {}       ## ヒント（話題 → {hints: [段階の文…], revealed: 見た段階の数}）
var flow: Dictionary = {}        ## フローチャートで到達した点（点ID → true）
var ui: Dictionary = {}          ## 入力UIの上書き {verbs: [動詞ID…] | null, hidden: {物ID: true}, input_modes: [...] | null}

## 宣言された変数（名前 → {type, default}）。未定義の変数の判定に使う。
var declared: Dictionary = {}
## 定数（名前 → 値）。プロジェクト設定とシナリオの constants。書き換えられない（セーブにも入れない）
var constants: Dictionary = {}


func get_var(name: String) -> Variant:
	if constants.has(name):
		return constants[name]
	if vars.has(name):
		return vars[name]
	if declared.has(name):
		return declared[name].get("default", null)
	return null


func has_var(name: String) -> bool:
	return vars.has(name) or declared.has(name) or constants.has(name)


func set_var(name: String, value: Variant) -> void:
	if _is_constant(name):
		return
	vars[name] = value


func _is_constant(name: String) -> bool:
	if constants.has(name):
		AdvDiag.debug_warn("CONST_WRITE", "定数は書き換えられません: %s" % name, "Constants cannot be changed: %s" % name)
		return true
	return false


func item_count(id: String) -> int:
	return int(items.get(id, 0))


func has_item(id: String) -> bool:
	return item_count(id) > 0


func item_ids() -> PackedStringArray:
	var r := PackedStringArray()
	for id in items:
		if int(items[id]) > 0:
			r.append(id)
	return r


## 状態を変える出力イベントを適用する。適用したら true。
func apply_event(ev: Dictionary) -> bool:
	var args: Dictionary = ev.get("args", {})
	match String(ev.get("type", "")):
		"state.set":
			_apply_set(args)
			return true
		"item.add":
			var id := String(args.get("id", ""))
			items[id] = item_count(id) + int(args.get("count", 1))
			return true
		"item.remove":
			var id := String(args.get("id", ""))
			var n := item_count(id) - int(args.get("count", 1))
			if n > 0:
				items[id] = n
			else:
				items.erase(id)
			return true
		"scene.goto":
			scene = String(args.get("scene", args.get("id", "")))
			visited[scene] = true
			return true
		"state.mark":
			_apply_mark(args)
			return true
		"notebook.add":
			var id := String(args.get("id", args.get("title", "")))
			var order: int = notebook[id]["order"] if notebook.has(id) else notebook.size()
			notebook[id] = {"category": String(args.get("category", "")), "title": String(args.get("title", id)),
				"body": String(args.get("body", "")), "order": order}
			return true
		"objective.set":
			var text := String(args.get("text", ""))
			objective = {} if text == "" else {"id": String(args.get("id", "")), "text": text}
			return true
		"hint.set":
			var topic := String(args.get("topic", ""))
			var list: Array = args.get("hints", [])
			if list.is_empty():
				hints.erase(topic)
			else:
				# 同じ内容ならそのまま。内容が変わったら（謎が進んだら）最初の段階からにする
				var old: Dictionary = hints.get(topic, {})
				var revealed: int = int(old.get("revealed", 0)) if old.get("hints", []) == list else 0
				hints[topic] = {"hints": list.duplicate(), "revealed": revealed}
			return true
		"flow.mark":
			flow[String(args.get("node", ""))] = true
			return true
		"verbs.update":
			_apply_list_update("verbs", args.get("verbs", []), String(args.get("mode", "replace")))
			return true
		"hotspots.update":
			var mode := String(args.get("mode", "replace"))
			var hidden: Dictionary = ui.get("hidden", {})
			var objs: Array = args.get("objects", [])
			match mode:
				"remove":
					for o in objs:
						hidden[String(o)] = true
				"add":
					for o in objs:
						hidden.erase(String(o))
				_:
					ui["shown"] = objs.duplicate()
					hidden.clear()
			ui["hidden"] = hidden
			return true
		"input.mode":
			var en = args.get("enable", null)
			ui["input_modes"] = en.duplicate() if en is Array else null
			return true
	return false


## verbs.update：replace は一覧を置き換え、add と remove は足し引きする。
func _apply_list_update(key: String, list: Array, mode: String) -> void:
	var added: Array = ui.get(key + "_added", [])
	var removed: Array = ui.get(key + "_removed", [])
	match mode:
		"add":
			for v in list:
				removed.erase(v)
				if ui.get(key) is Array:
					if not v in ui[key]:
						ui[key].append(v)
				elif not v in added:
					added.append(v)
		"remove":
			for v in list:
				added.erase(v)
				if ui.get(key) is Array:
					ui[key].erase(v)
				elif not v in removed:
					removed.append(v)
		_:
			ui[key] = list.duplicate()
			added = []
			removed = []
	ui[key + "_added"] = added
	ui[key + "_removed"] = removed


## ヒントを1段階進める。進めたら true。
func reveal_hint(topic: String) -> bool:
	if not hints.has(topic):
		return false
	var h: Dictionary = hints[topic]
	if int(h["revealed"]) >= h["hints"].size():
		return false
	h["revealed"] = int(h["revealed"]) + 1
	return true


func _apply_set(args: Dictionary) -> void:
	var name := String(args.get("name", args.get("var", args.get("flag", ""))))
	if name == "" or _is_constant(name):
		return
	var op := String(args.get("op", "set"))
	var value = args.get("value", true)
	var cur = get_var(name)
	match op:
		"set":
			vars[name] = value
		"toggle":
			vars[name] = not bool(cur)
		_:
			vars[name] = AdvState.apply_op(op, cur, value)


func _apply_mark(args: Dictionary) -> void:
	var id := String(args.get("id", ""))
	match String(args.get("kind", "")):
		"talked": talked[id] = true
		"read": read[id] = true
		"chosen": chosen[id] = true
		"tried": tried[id] = true
		"visited": visited[id] = true


## 数値の演算（add、sub、mul、div、mod、min、max）。
static func apply_op(op: String, cur: Variant, value: Variant) -> Variant:
	if cur == null:
		cur = 0
	if typeof(cur) == TYPE_STRING and op == "add":
		return String(cur) + str(value)
	var a: float = float(cur)
	var b: float = float(value)
	var r: float
	match op:
		"add": r = a + b
		"sub": r = a - b
		"mul": r = a * b
		"div": r = a / b if b != 0.0 else 0.0
		"mod": r = fmod(a, b) if b != 0.0 else 0.0
		"min": r = minf(a, b)
		"max": r = maxf(a, b)
		_: return value
	if typeof(cur) == TYPE_INT and typeof(value) == TYPE_INT and op != "div":
		return int(r)
	if op == "div" and typeof(cur) == TYPE_INT and typeof(value) == TYPE_INT:
		return int(r)
	return r


## 状態をまるごと複製する（シナリオの下書き用の状態に使う）。
func duplicate_state() -> AdvState:
	var s := AdvState.new()
	s.from_dict(to_dict())
	s.declared = declared
	s.constants = constants
	return s


func to_dict() -> Dictionary:
	return {
		"vars": vars.duplicate(true),
		"items": items.duplicate(true),
		"scene": scene,
		"visited": visited.duplicate(),
		"talked": talked.duplicate(),
		"read": read.duplicate(),
		"chosen": chosen.duplicate(),
		"tried": tried.duplicate(),
		"notebook": notebook.duplicate(true),
		"objective": objective.duplicate(),
		"hints": hints.duplicate(true),
		"flow": flow.duplicate(),
		"ui": ui.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	vars = d.get("vars", {}).duplicate(true)
	items = d.get("items", {}).duplicate(true)
	scene = String(d.get("scene", ""))
	visited = d.get("visited", {}).duplicate()
	talked = d.get("talked", {}).duplicate()
	read = d.get("read", {}).duplicate()
	chosen = d.get("chosen", {}).duplicate()
	tried = d.get("tried", {}).duplicate()
	notebook = d.get("notebook", {}).duplicate(true)
	objective = d.get("objective", {}).duplicate()
	hints = d.get("hints", {}).duplicate(true)
	flow = d.get("flow", {}).duplicate()
	ui = d.get("ui", {}).duplicate(true)
