@tool
class_name AdvStepEditor
extends VBoxContainer
## 手順のエディタ（6.8）。コマンドエディタと、JSON のセリフエディタで使う。
## 手順（地の文、台詞、条件分岐、選択肢、変数の計算、移動、会話の呼び出し…）を木で並べて書く。
##
## - 列：種類 / 内容 / 条件
## - 内容と条件はその場で書き換える。式のところは「式…」で式エディタを開く
## - 「JSON」で、手順の JSON を直接書き換えることもできる

signal changed

const TYPES := [
	["text", "地の文"], ["say", "台詞"], ["if", "条件分岐"], ["choice", "選択肢"], ["option", "選択肢の項目"],
	["let", "変数の計算"], ["goto", "移動"], ["call", "会話の呼び出し"], ["ink", "Ink のノット"], ["raw", "そのほか（JSON）"],
]
const BTN_EXPR := 1

var expr_editor: AdvExprEditor     ## 式…で開く（使う側が渡す。なければ自分で作る）
var tree: Tree
var _add: MenuButton
var _json_box: VBoxContainer
var _json: TextEdit
var _json_msg: Label
var _icon: Texture2D


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	_add = MenuButton.new()
	_add.text = "＋ 手順を追加"
	_add.flat = false
	_add.tooltip_text = "選んでいる手順の後ろ（条件分岐・選択肢の項目なら中）に足します"
	for i in TYPES.size():
		_add.get_popup().add_item(TYPES[i][1], i)
	_add.get_popup().id_pressed.connect(func(i): add_step(String(TYPES[i][0])))
	bar.add_child(_add)
	for spec in [["削除", remove_selected, "選んでいる手順を消します"], ["↑", func(): move_selected(-1), "上へ"],
			["↓", func(): move_selected(1), "下へ"]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.pressed.connect(spec[1])
		bar.add_child(b)
	var jt := CheckButton.new()
	jt.text = "JSON"
	jt.tooltip_text = "手順の JSON を直接書き換えます"
	jt.toggled.connect(_toggle_json)
	bar.add_child(jt)

	tree = Tree.new()
	tree.columns = 3
	tree.column_titles_visible = true
	tree.set_column_title(0, "種類")
	tree.set_column_title(1, "内容")
	tree.set_column_title(2, "条件")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 150)
	tree.set_column_expand_ratio(1, 3)
	tree.set_column_expand_ratio(2, 2)
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size = Vector2(0, 200)
	tree.item_edited.connect(func(): _emit())
	tree.button_clicked.connect(_on_button)
	tree.create_item()
	add_child(tree)

	_json_box = VBoxContainer.new()
	_json_box.visible = false
	_json_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_json_box)
	_json = TextEdit.new()
	_json.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json.custom_minimum_size = Vector2(0, 200)
	_json_box.add_child(_json)
	var jb := HBoxContainer.new()
	_json_box.add_child(jb)
	var apply := Button.new()
	apply.text = "JSON を反映"
	apply.pressed.connect(_apply_json)
	jb.add_child(apply)
	_json_msg = Label.new()
	jb.add_child(_json_msg)


# ---------------------------------------------------------------- 読み書き

## 手順（文字列・配列・オブジェクト）を読み込む。
func set_steps(steps: Variant) -> void:
	tree.clear()
	var root := tree.create_item()
	_build(root, steps)
	if _json_box.visible:
		_json.text = JSON.stringify(get_steps(), "  ", false)


## 手順の配列にして返す。
func get_steps() -> Array:
	return _collect(tree.get_root())


func _build(parent: TreeItem, v: Variant) -> void:
	if v == null:
		return
	if v is Array:
		for e in v:
			_build(parent, e)
		return
	if v is String:
		var s := String(v)
		if s.begins_with("@"):
			_make(parent, "say", s)
		else:
			_make(parent, "text", s)
		return
	if not v is Dictionary:
		_make(parent, "raw", JSON.stringify(v))
		return
	var d: Dictionary = v
	if d.has("if") and d.keys().all(func(k): return k in ["if", "then", "else"]):
		var it := _make(parent, "if", "", _cond_text(d["if"]))
		var th := _group(it, "then")
		_build(th, d.get("then"))
		var el := _group(it, "else")
		_build(el, d.get("else"))
		return
	if d.size() == 1 and d.has("let"):
		_make(parent, "let", String(d["let"]))
		return
	if d.has("say") and d.has("text") and d.size() == 2:
		_make(parent, "say", "@%s %s" % [d["say"], d["text"]])
		return
	for k in ["goto", "call", "ink"]:
		if d.size() == 1 and d.has(k) and d[k] is String:
			_make(parent, k, String(d[k]))
			return
	if d.size() == 1 and d.get("choice") is Dictionary:
		var c: Dictionary = d["choice"]
		var it := _make(parent, "choice", String(c.get("prompt", "")))
		it.set_metadata(0, {"t": "choice", "extra": _without(c, ["prompt", "options"])})
		for o in c.get("options", []):
			if not o is Dictionary:
				continue
			var oi := _make(it, "option", String(o.get("label", "")), _cond_text(o.get("when", "")))
			oi.set_metadata(0, {"t": "option", "extra": _without(o, ["label", "when", "do"])})
			_build(oi, o.get("do"))
		return
	_make(parent, "raw", JSON.stringify(d))


func _collect(parent: TreeItem) -> Array:
	var out := []
	if parent == null:
		return out
	for it in parent.get_children():
		var m: Dictionary = it.get_metadata(0)
		var t := String(m["t"])
		var body := it.get_text(1)
		match t:
			"text":
				out.append(body)
			"say":
				out.append(body if body.begins_with("@") else "@" + body)
			"if":
				var o := {"if": _cond_value(it.get_text(2))}
				for g in it.get_children():
					var steps := _collect(g)
					var gm: Dictionary = g.get_metadata(0)
					if gm["t"] == "then" or not steps.is_empty():
						o[gm["t"]] = steps
				out.append(o)
			"let":
				out.append({"let": body})
			"goto", "call", "ink":
				out.append({t: body})
			"choice":
				var c: Dictionary = (m.get("extra", {}) as Dictionary).duplicate(true)
				if body != "":
					c["prompt"] = body
				var opts := []
				for oi in it.get_children():
					var om: Dictionary = oi.get_metadata(0)
					var o: Dictionary = (om.get("extra", {}) as Dictionary).duplicate(true)
					o["label"] = oi.get_text(1)
					if oi.get_text(2).strip_edges() != "":
						o["when"] = _cond_value(oi.get_text(2))
					o["do"] = _collect(oi)
					opts.append(o)
				c["options"] = opts
				out.append({"choice": c})
			"raw":
				var j := JSON.new()
				out.append(j.data if j.parse(body) == OK else body)
	return out


static func _cond_text(c: Variant) -> String:
	if c is String:
		return c
	if c is bool:
		return "true" if c else "false"
	return JSON.stringify(c) if c != null else ""


static func _cond_value(s: String) -> Variant:
	s = s.strip_edges()
	if s.begins_with("{") or s.begins_with("["):
		var j := JSON.new()
		if j.parse(s) == OK:
			return j.data
	if s == "true":
		return true
	if s == "false":
		return false
	return s


static func _without(d: Dictionary, keys: Array) -> Dictionary:
	var o := {}
	for k in d:
		if not k in keys:
			o[k] = d[k]
	return o


# ---------------------------------------------------------------- 行

func _label(t: String) -> String:
	for e in TYPES:
		if e[0] == t:
			return e[1]
	return {"then": "そうなら", "else": "そうでないなら"}.get(t, t)


func _make(parent: TreeItem, t: String, body: String, cond: String = "") -> TreeItem:
	var it := tree.create_item(parent)
	it.set_metadata(0, {"t": t})
	it.set_text(0, _label(t))
	it.set_text(1, body)
	it.set_text(2, cond)
	var body_editable := t in ["text", "say", "let", "goto", "call", "ink", "raw", "choice", "option"]
	it.set_editable(1, body_editable)
	if t == "if":
		it.set_text(1, "（条件に合えば「そうなら」、合わなければ「そうでないなら」）")
		it.set_custom_color(1, Color(1, 1, 1, 0.5))
	if t in ["if", "option"]:
		it.set_editable(2, true)
		it.add_button(2, _expr_icon(), BTN_EXPR, false, "式エディタで書く")
	if t == "let":
		it.add_button(1, _expr_icon(), BTN_EXPR, false, "式エディタで書く")
	if t == "option":
		it.set_tooltip_text(2, "この項目を出す条件（空ならいつも）")
	return it


func _group(parent: TreeItem, t: String) -> TreeItem:
	var it := tree.create_item(parent)
	it.set_metadata(0, {"t": t})
	it.set_text(0, _label(t))
	it.set_custom_color(0, Color(0.6, 0.8, 1.0))
	return it


func _expr_icon() -> Texture2D:
	if _icon != null:
		return _icon
	if Engine.is_editor_hint() and EditorInterface.get_base_control() != null:
		_icon = EditorInterface.get_base_control().get_theme_icon("Edit", "EditorIcons")
	if _icon == null:
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.7, 0.8, 1.0))
		_icon = ImageTexture.create_from_image(img)
	return _icon


## 手順を足す。選んでいるのが「そうなら」などの入れ物・選択肢の項目なら、その中の最後に足す。
func add_step(t: String) -> TreeItem:
	var sel := tree.get_selected()
	var parent := tree.get_root()
	var after: TreeItem = null
	if sel != null:
		var st := String(sel.get_metadata(0)["t"])
		if t == "option":
			# 選択肢の項目は、選択肢の中だけ
			var c := sel
			while c != null and c != tree.get_root() and String(c.get_metadata(0)["t"]) != "choice":
				c = c.get_parent()
			if c == null or c == tree.get_root():
				return null
			parent = c
		elif st in ["then", "else", "option"]:
			parent = sel
		elif st == "if":
			parent = sel.get_child(0)
		elif st == "choice":
			parent = sel.get_parent()
			after = sel
		else:
			parent = sel.get_parent()
			after = sel
	elif t == "option":
		return null
	var it: TreeItem
	match t:
		"if":
			it = _make(parent, "if", "", "")
			_group(it, "then")
			_group(it, "else")
		"choice":
			it = _make(parent, "choice", "どうする？")
			_make(it, "option", "はい")
			_make(it, "option", "いいえ")
		"say":
			it = _make(parent, "say", "@話者 ")
		"raw":
			it = _make(parent, "raw", "{}")
		_:
			it = _make(parent, t, "")
	if after != null:
		it.move_after(after)
	it.select(1)
	tree.scroll_to_item(it)
	_emit()
	return it


func remove_selected() -> void:
	var sel := tree.get_selected()
	if sel == null or String(sel.get_metadata(0)["t"]) in ["then", "else"]:
		return
	sel.get_parent().remove_child(sel)
	sel.free()
	_emit()


func move_selected(dir: int) -> void:
	var sel := tree.get_selected()
	if sel == null or String(sel.get_metadata(0)["t"]) in ["then", "else"]:
		return
	if dir < 0 and sel.get_prev() != null:
		sel.move_before(sel.get_prev())
	elif dir > 0 and sel.get_next() != null:
		sel.move_after(sel.get_next())
	_emit()


func _on_button(it: TreeItem, col: int, id: int, _mouse: int) -> void:
	if id != BTN_EXPR:
		return
	if expr_editor == null:
		expr_editor = AdvExprEditor.new()
		add_child(expr_editor)
	var mode := AdvExprEditor.MODE_LET if col == 1 else AdvExprEditor.MODE_CONDITION
	expr_editor.open(it.get_text(col), mode, func(text: String):
		it.set_text(col, text)
		_emit())


func _toggle_json(on: bool) -> void:
	_json_box.visible = on
	tree.visible = not on
	if on:
		_json.text = JSON.stringify(get_steps(), "  ", false)
		_json_msg.text = ""


func _apply_json() -> void:
	var j := JSON.new()
	if j.parse(_json.text) != OK:
		_json_msg.text = "JSON の誤り（%d 行目）: %s" % [j.get_error_line(), j.get_error_message()]
		return
	set_steps(j.data)
	_json_msg.text = "反映しました"
	_emit()


func _emit() -> void:
	changed.emit()
