class_name AdvCommandSelect
extends ScrollContainer
## コマンド選択。動詞を選び、次にスロットごとの対象を選ぶ。選び終えたら intent_selected で意図を知らせる。
## 対象の候補は core.query("targets") と core.query("topics") から作り、意図スキーマの型で絞る。
##
## mode で操作の方式を変える（テンプレート・プロジェクト設定の inputs.enabled）。
## - menu（select）：動詞の一覧 → 対象の一覧を、同じ窓の中で順に選ぶ（日本のコマンド選択式）
## - verbs（verb_click）：動詞の一覧と持ち物を出したままにし、動詞を選んでから絵の中の対象か持ち物を選ぶ
## - cursor（verb_cursor）：選んだ動詞がカーソルに残り、続けて対象を選べる。cycle_verb で動詞を順に切り替える
## - context：動詞は出さず、持ち物だけを出す。絵の中の対象を選ぶと、その対象に合った動詞を画面側が決める
## verbs・cursor・context では、絵の中の対象は画面選択（pick_target）で受け取る。

signal intent_selected(intent: Dictionary)
signal verb_changed()      ## 選んでいる動詞が変わった（カーソルの形を変えるため）
signal menu_requested()    ## メニューのボタンが押された（cursor）
signal target_clicked(target: Dictionary)
signal item_long_pressed(target: Dictionary)   ## タッチで持ち物を長押しした（右クリックの代わり）

const LONG_PRESS_SEC := 0.5   ## 動詞を選ばずに、一覧の対象が押された（context）

var columns: int = 2

var _core: AdvCore
var _box: VBoxContainer
var _sentence_row: HBoxContainer
var _sentence: Label
var _ok: Button
var _cancel: Button
var _menu: Button
var _grid: GridContainer
var _inv: GridContainer
var _verb: Dictionary = {}
var _slot_index: int = 0
var _filled: Dictionary = {}
var _enabled: bool = true
var _labels: PackedStringArray = []   ## ログに残す、選んだものの表示名
var _sticky: String = ""              ## cursor：選んだままにする動詞
var _hold: Dictionary = {}            ## 長押しの途中の持ち物 {target, at}
var choosing: bool = false            ## 選択肢を出している
var show_tried: bool = false          ## 試したコマンドを区別して出す（モダン機能 tried_marks）
var icons: bool = false               ## 動詞をアイコンで出す（入力UI icon）。アイコンは画像ID "icon.動詞ID（小文字）"
var dim_color: Color = Color(0.6, 0.6, 0.6)
var mode: String = "menu"             ## menu、verbs、cursor、context
var item_verb: String = "USE"         ## 持ち物を選んだときの動詞（inputs.item_verb）
var alt_verb: String = "LOOK"         ## 右クリックの動詞（inputs.context_alt_verb）
var hotspot_keys: Dictionary = {}     ## 絵の中で選べる対象（"種類:ID" → true）。ここにない対象は一覧に出す


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 0)
	add_child(_box)
	_sentence_row = HBoxContainer.new()
	_sentence_row.visible = false
	_box.add_child(_sentence_row)
	_sentence = Label.new()
	_sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sentence.clip_text = true
	_sentence_row.add_child(_sentence)
	_ok = _small_button("○", "これで実行する", _on_ok)
	_cancel = _small_button("×", "やめる", cancel)
	_menu = _small_button("≡", "メニュー", func(): menu_requested.emit())
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 0)
	_box.add_child(_grid)
	_inv = GridContainer.new()
	_inv.columns = columns
	_inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv.add_theme_constant_override("h_separation", 4)
	_inv.add_theme_constant_override("v_separation", 0)
	_inv.visible = false
	_box.add_child(_inv)


func _small_button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	b.pressed.connect(cb)
	_sentence_row.add_child(b)
	return b


## 絵の中の対象を選ぶ方式か（verbs、cursor、context）。
func is_pointer() -> bool:
	return mode != "menu"


## 動詞の一覧から始め直す。
func refresh(core: AdvCore) -> void:
	_core = core
	choosing = false
	_reset()
	_show_verbs()


func _reset() -> void:
	_verb = {}
	_filled = {}
	_slot_index = 0
	_labels = PackedStringArray()
	if mode == "cursor" and _core != null:
		_arm(_sticky)


## cursor：動詞を選んだ状態にする（対象を待つ）。なければ、対象を取る最初の動詞。
func _arm(verb_id: String) -> void:
	var list := _cycle_verbs()
	if list.is_empty():
		return
	var v: Dictionary = list[0]
	for x in list:
		if x["id"] == verb_id:
			v = x
	_sticky = String(v["id"])
	_verb = v
	_labels = PackedStringArray([String(v["label"])])


## 順に切り替える動詞（対象を取るもの）。
func _cycle_verbs() -> Array:
	var out := []
	var verbs = _core.query("verbs") if _core != null else null
	if verbs is Array:
		for v in verbs:
			if not (v.get("slots", []) as Array).is_empty():
				out.append(v)
	return out


## cursor：次（前）の動詞に切り替える。
func cycle_verb(dir: int = 1) -> void:
	var list := _cycle_verbs()
	if list.is_empty() or choosing:
		return
	var i := 0
	for k in list.size():
		if list[k]["id"] == _verb.get("id", ""):
			i = k
	_sticky = String(list[posmod(i + dir, list.size())]["id"])
	_reset()
	_show_verbs()
	verb_changed.emit()


## いま選んでいる動詞のID（なければ空）。
func current_verb_id() -> String:
	return String(_verb.get("id", "")) if not choosing else ""


## 対象を1つでも選んだあとか（やめる操作の対象になる）。
func has_partial() -> bool:
	return not _filled.is_empty() or (mode != "cursor" and not _verb.is_empty())


func set_enabled(on: bool) -> void:
	_enabled = on
	if _grid == null:
		return
	for g in [_grid, _inv, _sentence_row]:
		for b in g.get_children():
			if b is Button:
				b.disabled = not on


func _clear() -> void:
	for g in [_grid, _inv]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	_inv.visible = false
	_sentence_row.visible = false
	scroll_vertical = 0


func _add(label: String, cb: Callable, tried: bool = false, icon: Texture2D = null, to: GridContainer = null) -> Button:
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
	(to if to != null else _grid).add_child(b)
	return b


func _show_verbs() -> void:
	if not is_pointer():
		_verb = {}
	_clear()
	_grid.columns = columns
	_inv.columns = columns
	var verbs = _core.query("verbs")
	if not verbs is Array:
		return
	if mode != "context":
		for v in verbs:
			var icon: Texture2D = null
			if icons or mode == "cursor":
				var p := _core.assets.resolve("image", "icon." + String(v["id"]).to_lower())
				if p != "":
					icon = load(p) as Texture2D
			var b := _add(String(v["label"]), _on_verb.bind(v), bool(v.get("tried", false)), icon)
			if is_pointer():
				b.toggle_mode = true
				b.set_pressed_no_signal(v["id"] == _verb.get("id", ""))
	if is_pointer():
		_show_inventory()
		_update_sentence()


## 持ち物の一覧（verbs、cursor、context）。
func _show_inventory() -> void:
	var targets = _core.query("targets")
	if not targets is Array:
		return
	for t in targets:
		if _core.schema.base_type(String(t["type"])) != "item":
			continue
		var b := _add(String(t["label"]), _on_item.bind(t), false, null, _inv)
		b.set_meta("target", t)
		b.gui_input.connect(_on_item_input.bind(t))
		b.toggle_mode = true
		b.set_pressed_no_signal(_holds(t))
	# 絵の中で選べない対象（範囲のない物や出口）は、一覧から選べるようにする
	var slots: Array = _verb.get("slots", [])
	var extras := []
	if not _verb.is_empty() and _slot_index < slots.size():
		extras = _candidates(slots[_slot_index])
	elif mode == "context":
		extras = targets
	for t in extras:
		if _core.schema.base_type(String(t["type"])) in ["item", "topic"] or hotspot_keys.has("%s:%s" % [t["type"], t["id"]]):
			continue
		_add("→ " + String(t["label"]), _on_extra.bind(t), false, null, _inv)
	_inv.visible = _inv.get_child_count() > 0


## タッチ（タッチから作られたマウスの操作）で持ち物を押し続けると、長押しとして知らせる。
func _on_item_input(event: InputEvent, t: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device == InputEvent.DEVICE_ID_EMULATION:
		_hold = {"target": t, "at": Time.get_ticks_msec()} if event.pressed else {}


func _process(_d: float) -> void:
	if not _hold.is_empty() and Time.get_ticks_msec() - int(_hold["at"]) >= int(LONG_PRESS_SEC * 1000):
		var t: Dictionary = _hold["target"]
		_hold = {}
		if _enabled and not choosing:
			item_long_pressed.emit(t)


func _on_extra(t: Dictionary) -> void:
	if is_picking():
		pick_target(t)
	else:
		target_clicked.emit(t)


func _holds(t: Dictionary) -> bool:
	for v in _filled.values():
		if v["id"] == t["id"] and v["type"] == t["type"]:
			return true
	return false


## いまマウスが重なっている持ち物（なければ空）。
func item_at_mouse() -> Dictionary:
	if _inv == null or not _inv.visible:
		return {}
	for b in _inv.get_children():
		if b is Button and b.get_global_rect().has_point(b.get_global_mouse_position()):
			return b.get_meta("target", {})
	return {}


## 作りかけの文（「かぎ つかう …」）と、実行・やめるのボタン。
func _update_sentence() -> void:
	var slots: Array = _verb.get("slots", [])
	var waiting := not _verb.is_empty() and _slot_index < slots.size()
	_sentence.text = (" ".join(_labels) + (" …" if waiting else "")) if not _verb.is_empty() else ""
	var rest_optional := waiting
	for i in range(_slot_index, slots.size()):
		if slots[i].get("required", true):
			rest_optional = false
	_ok.visible = rest_optional
	_cancel.visible = has_partial()
	_menu.visible = mode == "cursor"
	_sentence_row.visible = true


func _on_ok() -> void:
	_slot_index = (_verb.get("slots", []) as Array).size()
	_next_slot()


## 選びかけの動詞と対象をやめる。
func cancel() -> void:
	if choosing:
		return
	_reset()
	_show_verbs()
	verb_changed.emit()


func _on_verb(v: Dictionary) -> void:
	if is_pointer() and mode == "verbs" and _verb.get("id", "") == v["id"]:
		cancel()   # 同じ動詞をもう一度押すと、やめる
		return
	if mode == "cursor" and not (v.get("slots", []) as Array).is_empty():
		_sticky = String(v["id"])
	_verb = v
	_filled = {}
	_slot_index = 0
	_labels = PackedStringArray([String(v["label"])])
	if is_pointer():
		verb_changed.emit()
	_next_slot()


## 持ち物を選んだ：動詞を選んでいればその対象に、そうでなければ item_verb（つかう）の対象にする。
func _on_item(t: Dictionary) -> void:
	if _holds(t):
		cancel()
		return
	if is_picking() and pick_target(t):
		return
	var v := _find_verb(item_verb)
	_verb = v
	_filled = {}
	_slot_index = 0
	_labels = PackedStringArray([String(v["label"])])
	verb_changed.emit()
	if not pick_target(t):
		cancel()


## 持ち物を右クリックで調べる（alt_verb）。
func alt_item(t: Dictionary) -> void:
	if not _enabled or choosing:
		return
	var v := _find_verb(alt_verb)
	_reset()
	_show_verbs()
	intent_selected.emit({"verb": v["id"], "slots": {"target": {"type": t["type"], "id": t["id"]}}, "source": "select",
		"ext": {"label": "%s %s" % [String(t["label"]), String(v["label"])]}})


func _find_verb(verb_id: String) -> Dictionary:
	var verbs = _core.query("verbs")
	if verbs is Array:
		for x in verbs:
			if x["id"] == verb_id:
				return x
	return {"id": verb_id, "label": _core.dictionary.verb_label(verb_id), "slots": _core.schema.slots(verb_id)}


## 聞き返し（input.request）：動詞と埋まっているスロットはそのままで、足りないスロットの候補を出す。
func start_request(verb_id: String, filled: Dictionary, slot: String) -> void:
	choosing = false
	var v := _find_verb(verb_id)
	_verb = v
	_filled = filled.duplicate(true)
	_labels = PackedStringArray([String(v["label"])])
	_slot_index = 0
	var slots: Array = v.get("slots", [])
	for i in slots.size():
		if slots[i]["name"] == slot:
			_slot_index = i
			break
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
	_reset()
	_show_verbs()
	intent_selected.emit({"verb": "CHOOSE", "slots": {"target": {"type": "choice", "id": String(c["id"])}},
		"source": "select", "ext": {"label": String(c["label"])}})


## 次に埋めるスロットの候補を出す。全部埋まったら意図を出す。
func _next_slot() -> void:
	var slots: Array = _verb.get("slots", [])
	if _slot_index >= slots.size():
		var intent := {"verb": _verb["id"], "slots": _filled.duplicate(), "source": "select",
			"ext": {"label": " ".join(_labels)}}
		_reset()
		_show_verbs()
		intent_selected.emit(intent)
		return
	var def: Dictionary = slots[_slot_index]
	var cands := _candidates(def)
	if cands.is_empty() and not def.get("required", true):
		_slot_index += 1
		_next_slot()
		return
	# 絵の中の対象を選ぶ方式では、一覧を出さずに待つ（話題だけは一覧から選ぶ）
	if is_pointer() and _core.schema.base_type(String(def.get("type", "object"))) != "topic":
		_show_verbs()
		return
	_clear()
	_grid.columns = columns
	for c in cands:
		var tried := _core.state.tried.has("%s:%s" % [_verb["id"], c["id"]])
		_add(String(c["label"]), _on_target.bind(def, c), tried)
	if not def.get("required", true):
		_add(_label("select_none", "まわり"), _on_skip)
	_add(_label("select_back", "もどる"), cancel if is_pointer() else _show_verbs)


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
	if not is_picking() or not _enabled:
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
