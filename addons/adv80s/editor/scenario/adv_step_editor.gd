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
	["let", "変数の計算"], ["goto", "移動"], ["call", "会話の呼び出し"], ["call_scene", "サブシーンの呼び出し"], ["return", "サブシーンから戻る"],
	["ink", "Ink のノット"], ["event", "演出・システム（出力イベント）"], ["raw", "そのほか（JSON）"],
]
## 出力イベントとして読む、点のない名前
const DOTLESS_EVENTS := ["checkpoint", "wait", "group"]
const BTN_EXPR := 1
## 種類ごとの、木の列に出さない項目（下の欄で書く）：[名前, 型, 説明]
const DETAILS := {
	"say": [["id", "string", "行のID（既読やボイスの結び付けに使う。なければ自動）"], ["voice", "string", "ボイスの素材ID"]],
	"choice": [["id", "string", "選択肢のID（chosen(…) で使う）"]],
	"option": [["id", "string", "項目のID（chosen(…) で使う）"], ["once", "bool", "一度選んだら出さない"]],
	"call_scene": [["args", "json", "引数（{\"名前\": 値}。\"=式\" と書くと呼び出し元で計算する）"], ["into", "string", "戻り値を入れる変数"]],
	"event": [["args", "json", "イベントの引数（{\"名前\": 値}。なければ {}）"]],
}

static var _event_names: Array = []
## 出力イベントの引数のうち、一覧から選べる ID の項目（イベント → 項目名 → 種類）。"*" はどのイベントでも
const ARG_ID_KINDS := {
	"image.show": {"id": "image"}, "sprite.show": {"image": "image"}, "cursor.set": {"image": "image"},
	"bgm.play": {"id": "bgm"}, "se.play": {"id": "se"}, "voice.play": {"id": "voice"}, "video.play": {"id": "video"},
	"scene.goto": {"scene": "scene"}, "scene.call": {"scene": "scene"}, "game.new": {"scene": "scene"}, "opening.play": {"scene": "scene"},
	"item.add": {"id": "item"}, "item.remove": {"id": "item"},
	"fin.show": {"then": "scene", "image": "image"}, "credits.roll": {"image": "image", "bgm": "bgm"},
	"notice.show": {"icon": "image"},
}


## 出力イベントの引数の項目（道筋）から、ID の種類を決める。なければ ""。
static func arg_id_kind(event: String, path: Array) -> String:
	var keys := path.filter(func(p): return p is String)
	if keys.is_empty():
		return ""
	return String(ARG_ID_KINDS.get(event, {}).get(String(keys[keys.size() - 1]), ""))
static var _scenario_schema: Dictionary = {}


static func _schema() -> Dictionary:
	if _scenario_schema.is_empty():
		_scenario_schema = AdvSchemaValidator.load_schema("scenario")
	return _scenario_schema


## 出力イベントの引数のスキーマ（フォームで書く）。定義がなければ {}（JSON で書く）。
static func event_args_schema(name: String) -> Dictionary:
	var defs: Dictionary = _schema().get("definitions", {})
	var s = defs.get("event_args", {}).get("properties", {}).get(name)
	if not s is Dictionary:
		return {}
	var out: Dictionary = (s as Dictionary).duplicate(true)
	if out.has("$ref"):
		out = (defs.get(String(out["$ref"]).get_file(), {}) as Dictionary).duplicate(true)
	out["definitions"] = defs
	return out


## 出力イベントの名前の一覧（シナリオのスキーマから読む）。
static func event_names() -> Array:
	if _event_names.is_empty():
		var t = _schema().get("definitions", {}).get("event", {}).get("properties", {}).get("type", {})
		for b in t.get("anyOf", []):
			if b is Dictionary and b.has("enum"):
				_event_names = Array(b["enum"])
	return _event_names

var expr_editor: AdvExprEditor     ## 式…で開く（使う側が渡す。なければ自分で作る）
var tree: Tree
var _add: MenuButton
var _json_box: VBoxContainer
var _json: TextEdit
var _json_msg: Label
var _icon: Texture2D
var _details: HBoxContainer
var args_form: AdvSchemaForm     ## 出力イベントの引数のフォーム
## ID の候補を返す関数 func(種類) -> Array（種類は image・bgm・se・voice・video・scene・item）。使う側が渡す
var id_source: Callable
## 画像の見本を返す関数 func(ID) -> Texture2D。使う側が渡す
var image_source: Callable
## 音を試しに鳴らす関数 func(種類, ID)。使う側が渡す
var audio_player: Callable
var _args_item: TreeItem


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
	tree.item_selected.connect(_fill_details)
	add_child(tree)
	_details = HBoxContainer.new()
	add_child(_details)
	args_form = AdvSchemaForm.new()
	args_form.name = "ArgsForm"
	args_form.custom_minimum_size = Vector2(0, 160)
	args_form.visible = false
	args_form.changed.connect(_on_args_changed)
	args_form.suggest = func(path: Array) -> Array:
		if not id_source.is_valid() or _args_item == null or not is_instance_valid(_args_item):
			return []
		var kind := arg_id_kind(_args_item.get_text(1).strip_edges(), path)
		return id_source.call(kind) if kind != "" else []
	args_form.audio_kind = func(path: Array) -> String:
		if not audio_player.is_valid() or _args_item == null or not is_instance_valid(_args_item):
			return ""
		var k := arg_id_kind(_args_item.get_text(1).strip_edges(), path)
		return k if k in ["bgm", "se", "voice"] else ""
	args_form.play_requested.connect(func(kind: String, id: String): audio_player.call(kind, id))
	args_form.check = func(path: Array, value: Variant) -> String:
		if not id_source.is_valid() or _args_item == null or not is_instance_valid(_args_item):
			return ""
		var kind := arg_id_kind(_args_item.get_text(1).strip_edges(), path)
		if kind == "scene" and String(value) in ["title", "new", "quit", "stay"]:
			return ""   # おわりの画面の then の決まった値
		return AdvScenarioEditor.missing_message(kind, String(value), id_source.call(kind)) if kind != "" else ""
	args_form.preview = func(path: Array, value: Variant) -> Variant:
		if not image_source.is_valid() or _args_item == null or not is_instance_valid(_args_item):
			return null
		if arg_id_kind(_args_item.get_text(1).strip_edges(), path) != "image":
			return null
		return image_source.call(String(value))
	add_child(args_form)

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
	_fill_details()
	if _json_box.visible:
		_json.text = JSON.stringify(get_steps(), "  ", false)


## 選んでいる行の、いちばん上の段での番号（会話の何番目の手順か）。選んでいなければ -1。
func selected_top_index() -> int:
	var it := tree.get_selected()
	if it == null:
		return -1
	while it.get_parent() != null and it.get_parent() != tree.get_root():
		it = it.get_parent()
	return it.get_index()


## 選んでいる行の、手順の中の場所（get_steps() の形での道筋）。例：[2, "then", 0]、[1, "choice", "options", "0", "do", 2]。
## 数は手順の番目、文字はキー（選択肢の項目の番目も文字）。
## 「もし」の「そうなら」・選択肢の項目そのものを選んだときは、その中の最初。選んでいなければ []。
func selected_path() -> Array:
	return path_of(tree.get_selected())


func path_of(it: TreeItem) -> Array:
	if it == null or it == tree.get_root():
		return []
	var t := String((it.get_metadata(0) as Dictionary).get("t", ""))
	if t in ["then", "else", "option"]:
		return _container_path(it) + [0]
	return _container_path(it.get_parent()) + [it.get_index()]


## 子の手順が並ぶところ（ルート、「そうなら」「そうでないなら」、選択肢の項目）までの道筋。
func _container_path(c: TreeItem) -> Array:
	if c == null or c == tree.get_root():
		return []
	var t := String((c.get_metadata(0) as Dictionary).get("t", ""))
	if t in ["then", "else"]:
		return path_of(c.get_parent()) + [t]
	if t == "option":
		return path_of(c.get_parent()) + ["choice", "options", str(c.get_index()), "do"]   # 項目の番目は文字（手順の番目と分ける）
	return path_of(c)


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
	if d.has("say") and d.has("text") and d.keys().all(func(k): return k in ["say", "text", "id", "voice"]):
		var it := _make(parent, "say", "@%s %s" % [d["say"], d["text"]])
		it.set_metadata(0, {"t": "say", "extra": _without(d, ["say", "text"])})
		return
	for k in ["goto", "call", "ink"]:
		if d.size() == 1 and d.has(k) and d[k] is String:
			_make(parent, k, String(d[k]))
			return
	if d.has("call_scene") and d["call_scene"] is String and d.keys().all(func(k): return k in ["call_scene", "args", "into"]):
		var it := _make(parent, "call_scene", String(d["call_scene"]))
		it.set_metadata(0, {"t": "call_scene", "extra": _without(d, ["call_scene"])})
		return
	if d.size() == 1 and d.has("return"):
		var rv = d["return"]
		_make(parent, "return", "" if rv == null else (String(rv) if rv is String else JSON.stringify(rv)))
		return
	if d.size() == 1 and (String(d.keys()[0]).contains(".") or String(d.keys()[0]) in DOTLESS_EVENTS):
		var name := String(d.keys()[0])
		var it := _make(parent, "event", name)
		var ev_args = d[name]
		it.set_metadata(0, {"t": "event", "extra": {} if ev_args is Dictionary and ev_args.is_empty() else {"args": ev_args}})
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
				var line := body if body.begins_with("@") else "@" + body
				var extra: Dictionary = m.get("extra", {})
				if extra.is_empty():
					out.append(line)
				else:
					var sp := line.substr(1).get_slice(" ", 0)
					var o := {"say": sp, "text": line.substr(1 + sp.length()).strip_edges()}
					o.merge(extra)
					out.append(o)
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
			"call_scene":
				var o := {"call_scene": body}
				o.merge(m.get("extra", {}))
				out.append(o)
			"return":
				var rb := body.strip_edges()
				var rv: Variant = null
				if rb != "":
					var j := JSON.new()
					rv = j.data if not rb.begins_with("=") and j.parse(rb) == OK else rb
				out.append({"return": rv})
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
			"event":
				var name := body.strip_edges()
				if name != "":
					out.append({name: m.get("extra", {}).get("args", {})})
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
	var body_editable := t in ["text", "say", "let", "goto", "call", "call_scene", "return", "ink", "raw", "choice", "option", "event"]
	it.set_editable(1, body_editable)
	if t == "if":
		it.set_text(1, "（条件に合えば「そうなら」、合わなければ「そうでないなら」）")
		it.set_custom_color(1, Color(1, 1, 1, 0.5))
	if t in ["if", "option"]:
		it.set_editable(2, true)
		it.add_button(2, _expr_icon(), BTN_EXPR, false, "式エディタで書く")
	if t == "let":
		it.add_button(1, _expr_icon(), BTN_EXPR, false, "式エディタで書く")
	if t == "return":
		it.set_tooltip_text(1, "戻り値（空なら null。\"=式\" で計算。ほかは JSON の値か文字列）")
	if t == "option":
		it.set_tooltip_text(2, "この項目を出す条件（空ならいつも）")
	if t == "event":
		it.set_tooltip_text(1, "イベントの名前（下の欄の一覧からも選べます）")
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
		"event":
			it = _make(parent, "event", "extras.open")
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


## 選んだ行の、木に出さない項目（ID、once、voice）の欄を作る。
func _fill_details() -> void:
	for c in _details.get_children():
		_details.remove_child(c)
		c.queue_free()
	args_form.visible = false
	_args_item = null
	var it := tree.get_selected()
	if it == null:
		return
	var m: Dictionary = it.get_metadata(0)
	var spec: Array = DETAILS.get(String(m["t"]), [])
	if spec.is_empty():
		return
	var extra: Dictionary = m.get("extra", {})
	if String(m["t"]) == "event":
		var ob := OptionButton.new()
		ob.name = "event_name"
		ob.tooltip_text = "出力イベントの名前"
		var names := event_names()
		for i in names.size():
			ob.add_item(String(names[i]), i)
		ob.selected = names.find(it.get_text(1))
		ob.item_selected.connect(func(i: int):
			if is_instance_valid(it):
				it.set_text(1, String(names[i]))
				_emit()
				_fill_details.call_deferred())
		_details.add_child(ob)
		var es := event_args_schema(it.get_text(1).strip_edges())
		if not es.is_empty():
			# 引数はフォームで書く（項目のないイベントは「引数なし」）
			if es.get("properties", {}).is_empty():
				var nl := Label.new()
				nl.text = "（引数はありません）"
				_details.add_child(nl)
			else:
				_args_item = it
				args_form.setup(es, AdvSchemaForm.normalize(extra.get("args", {}) if extra.get("args") is Dictionary else {}))
				args_form.visible = true
			return
	for f in spec:
		var key := String(f[0])
		var l := Label.new()
		l.text = key
		l.tooltip_text = String(f[2])
		_details.add_child(l)
		if f[1] == "bool":
			var cb := CheckBox.new()
			cb.name = key
			cb.button_pressed = bool(extra.get(key, false))
			cb.tooltip_text = String(f[2])
			cb.toggled.connect(func(on: bool): _set_extra(it, key, on if on else null))
			_details.add_child(cb)
		elif f[1] == "json":
			var je := LineEdit.new()
			je.name = key
			je.text = JSON.stringify(extra[key]) if extra.has(key) else ""
			je.custom_minimum_size = Vector2(220, 0)
			je.tooltip_text = String(f[2])
			je.text_changed.connect(func(t: String):
				var s := t.strip_edges()
				if s == "":
					_set_extra(it, key, null)
					return
				var j := JSON.new()
				if j.parse(s) == OK:
					_set_extra(it, key, j.data))
			_details.add_child(je)
		else:
			var e := LineEdit.new()
			e.name = key
			e.text = String(extra.get(key, ""))
			e.custom_minimum_size = Vector2(140, 0)
			e.tooltip_text = String(f[2])
			e.text_changed.connect(func(t: String): _set_extra(it, key, t.strip_edges() if t.strip_edges() != "" else null))
			_details.add_child(e)


func _on_args_changed() -> void:
	if _args_item == null or not is_instance_valid(_args_item):
		return
	var v = args_form.data
	_set_extra(_args_item, "args", v if v is Dictionary and not v.is_empty() else null)


func _set_extra(it: TreeItem, key: String, value: Variant) -> void:
	if not is_instance_valid(it):
		return
	var m: Dictionary = it.get_metadata(0)
	var extra: Dictionary = m.get("extra", {}).duplicate()
	if value == null:
		extra.erase(key)
	else:
		extra[key] = value
	m["extra"] = extra
	it.set_metadata(0, m)
	_emit()
