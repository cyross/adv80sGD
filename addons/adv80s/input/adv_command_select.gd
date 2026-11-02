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
var _labels: PackedStringArray = []   ## ログに残す、選んだものの表示名
var choosing: bool = false            ## 選択肢を出している
var show_tried: bool = false          ## 試したコマンドを区別して出す（モダン機能 tried_marks）
var icons: bool = false               ## 動詞をアイコンで出す（入力UI icon）。アイコンは画像ID "icon.動詞ID（小文字）"
var dim_color: Color = Color(0.6, 0.6, 0.6)


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
	choosing = false
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


func _add(label: String, cb: Callable, tried: bool = false, icon: Texture2D = null) -> void:
	var b := Button.new()
	b.text = label
	if icon != null:
		b.icon = icon
		b.expand_icon = false
	if tried and show_tried:
		b.add_theme_color_override("font_color", dim_color)
		b.add_theme_color_override("font_hover_color", dim_color)
		b.add_theme_color_override("font_focus_color", dim_color)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not _enabled
	b.pressed.connect(cb)
	_grid.add_child(b)


func _show_verbs() -> void:
	_verb = {}
	_clear()
	_grid.columns = columns
	var verbs = _core.query("verbs")
	if not verbs is Array:
		return
	for v in verbs:
		var icon: Texture2D = null
		if icons:
			var p := _core.assets.resolve("image", "icon." + String(v["id"]).to_lower())
			if p != "":
				icon = load(p) as Texture2D
		_add(String(v["label"]), _on_verb.bind(v), bool(v.get("tried", false)), icon)


func _on_verb(v: Dictionary) -> void:
	_verb = v
	_filled = {}
	_slot_index = 0
	_labels = PackedStringArray([String(v["label"])])
	_next_slot()


## 選択肢を出す（choice.show）。選ぶと CHOOSE の意図を出す。
func show_choices(choices: Array) -> void:
	choosing = true
	_clear()
	_grid.columns = 1
	for c in choices:
		_add(String(c["label"]), _on_choice.bind(c))
	if _grid.get_child_count() > 0 and _enabled:
		(_grid.get_child(0) as Button).call_deferred("grab_focus")


func _on_choice(c: Dictionary) -> void:
	choosing = false
	_show_verbs()
	intent_selected.emit({"verb": "CHOOSE", "slots": {"target": {"type": "choice", "id": String(c["id"])}},
		"source": "select", "ext": {"label": String(c["label"])}})


## 次に埋めるスロットの候補を出す。全部埋まったら意図を出す。
func _next_slot() -> void:
	var slots: Array = _verb.get("slots", [])
	if _slot_index >= slots.size():
		var intent := {"verb": _verb["id"], "slots": _filled.duplicate(), "source": "select",
			"ext": {"label": " ".join(_labels)}}
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
		var tried := _core.state.tried.has("%s:%s" % [_verb["id"], c["id"]])
		_add(String(c["label"]), _on_target.bind(def, c), tried)
	if not def.get("required", true):
		_add(_label("select_none", "まわり"), _on_skip)
	_add(_label("select_back", "もどる"), _show_verbs)


func focus_first() -> void:
	for b in _grid.get_children():
		if b is Button and not b.disabled:
			b.grab_focus()
			return


## いま対象を選んでいる途中か（画面選択で使う）。
func is_picking() -> bool:
	return not _verb.is_empty() and not choosing


## 画面選択で選んだ物を、いま埋めているスロットに入れる。入れられたら true。
func pick_target(t: Dictionary) -> bool:
	if not is_picking():
		return false
	var slots: Array = _verb.get("slots", [])
	if _slot_index >= slots.size():
		return false
	var def: Dictionary = slots[_slot_index]
	if not _core.schema.accepts(String(def.get("type", "object")), String(t["type"])):
		return false
	_on_target(def, t)
	return true


func _on_target(def: Dictionary, c: Dictionary) -> void:
	_filled[def["name"]] = {"type": c["type"], "id": c["id"]}
	_labels.insert(_labels.size() - 1, String(c["label"]))
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
