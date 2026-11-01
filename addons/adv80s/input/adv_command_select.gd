class_name AdvCommandSelect
extends ScrollContainer
## コマンド選択。動詞を選び、次にスロットごとの対象を選ぶ。選び終えたら intent_selected で意図を知らせる。
## 対象の候補は core.query("targets") と core.query("topics") から作り、意図スキーマの型で絞る。

signal intent_selected(intent: Dictionary)

var columns: int = 2

var _core: AdvCore
var _grid: GridContainer
var _verb: Dictionary = {}
var _slot_index: int = 0
var _filled: Dictionary = {}
var _enabled: bool = true


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 0)
	add_child(_grid)


## 動詞の一覧から始め直す。
func refresh(core: AdvCore) -> void:
	_core = core
	_verb = {}
	_filled = {}
	_slot_index = 0
	_show_verbs()


func set_enabled(on: bool) -> void:
	_enabled = on
	if _grid == null:
		return
	for b in _grid.get_children():
		if b is Button:
			b.disabled = not on


func _clear() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	scroll_vertical = 0


func _add(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not _enabled
	b.pressed.connect(cb)
	_grid.add_child(b)


func _show_verbs() -> void:
	_clear()
	_grid.columns = columns
	var verbs = _core.query("verbs")
	if not verbs is Array:
		return
	for v in verbs:
		_add(String(v["label"]), _on_verb.bind(v))


func _on_verb(v: Dictionary) -> void:
	_verb = v
	_filled = {}
	_slot_index = 0
	_next_slot()


## 次に埋めるスロットの候補を出す。全部埋まったら意図を出す。
func _next_slot() -> void:
	var slots: Array = _verb.get("slots", [])
	if _slot_index >= slots.size():
		var intent := {"verb": _verb["id"], "slots": _filled.duplicate(), "source": "select"}
		_show_verbs()
		intent_selected.emit(intent)
		return
	var def: Dictionary = slots[_slot_index]
	var cands := _candidates(def)
	if cands.is_empty() and not def.get("required", true):
		_slot_index += 1
		_next_slot()
		return
	_clear()
	_grid.columns = columns
	for c in cands:
		_add(String(c["label"]), _on_target.bind(def, c))
	if not def.get("required", true):
		_add(_label("select_none", "まわり"), _on_skip)
	_add(_label("select_back", "もどる"), _show_verbs)


func _on_target(def: Dictionary, c: Dictionary) -> void:
	_filled[def["name"]] = {"type": c["type"], "id": c["id"]}
	_slot_index += 1
	_next_slot()


func _on_skip() -> void:
	_slot_index += 1
	_next_slot()


func _candidates(def: Dictionary) -> Array:
	var list := []
	var type := String(def.get("type", "object"))
	if _core.schema.base_type(type) == "topic":
		var who = _filled.get("target", {})
		var topics = _core.query("topics", {"target": String(who.get("id", ""))})
		return topics if topics is Array else []
	var targets = _core.query("targets")
	if targets is Array:
		for t in targets:
			if _core.schema.accepts(type, String(t["type"])) and not _already_used(t):
				list.append(t)
	return list


func _already_used(t: Dictionary) -> bool:
	for v in _filled.values():
		if v["id"] == t["id"] and v["type"] == t["type"]:
			return true
	return false


func _label(code: String, fallback: String) -> String:
	var s := _core.dictionary.reply(code)
	return s if s != "" else fallback
