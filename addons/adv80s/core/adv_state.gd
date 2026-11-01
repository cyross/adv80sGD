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

## 宣言された変数（名前 → {type, default}）。未定義の変数の判定に使う。
var declared: Dictionary = {}


func get_var(name: String) -> Variant:
	if vars.has(name):
		return vars[name]
	if declared.has(name):
		return declared[name].get("default", null)
	return null


func has_var(name: String) -> bool:
	return vars.has(name) or declared.has(name)


func set_var(name: String, value: Variant) -> void:
	vars[name] = value


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
			scene = String(args.get("id", ""))
			visited[scene] = true
			return true
		"state.mark":
			_apply_mark(args)
			return true
	return false


func _apply_set(args: Dictionary) -> void:
	var name := String(args.get("var", args.get("flag", args.get("name", ""))))
	if name == "":
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
