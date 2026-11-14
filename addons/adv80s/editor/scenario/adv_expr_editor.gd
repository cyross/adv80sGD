@tool
class_name AdvExprEditor
extends ConfirmationDialog
## 式エディタ（6.8）。条件式（if・when）や let 文を、複数行のテキストで書く。
## 打つと、変数・定数・アイテム・シーン・会話・組み込みの名前を候補に出す（自前の一覧。Ctrl+Space でも出る）。
## 関数の括弧の中では、その関数に合うもの（visited( ならシーン）だけを出す。↑↓で選び、Enter・Tab で入れる。
## 書いた式はその場で確かめ、誤りがあれば下に理由を出す。
##
##   var ed := AdvExprEditor.new()
##   add_child(ed)
##   ed.open("has(key) and money >= 100", "condition", func(text): ...)

const MODE_CONDITION := "condition"   ## 条件式（"has(key) and money >= 100"）
const MODE_LET := "let"               ## let 文（"money = money - 10; seen = true"）

const KEYWORDS := ["and", "or", "not", "true", "false"]

var code: CodeEdit
var message: Label
var expr_mode: String = MODE_CONDITION
## 候補：[{name, kind, note}]（kind は「変数」「定数」「アイテム」「シーン」「会話」「組み込み」など）
var candidates: Array = []
var _done: Callable
var _list: ItemList


func _init() -> void:
	title = "式エディタ"
	min_size = Vector2i(560, 320)
	ok_button_text = "決定"
	var box := VBoxContainer.new()
	add_child(box)
	code = CodeEdit.new()
	code.custom_minimum_size = Vector2(540, 200)
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.auto_brace_completion_enabled = false
	code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code.text_changed.connect(_on_text_changed)
	code.gui_input.connect(_on_code_input)
	code.caret_changed.connect(func():
		if is_completion_visible() and completion_items().is_empty():
			hide_completion())
	box.add_child(code)
	# 候補の一覧（自前。括弧を開いた直後でも出せる）
	_list = ItemList.new()
	_list.visible = false
	_list.focus_mode = Control.FOCUS_NONE
	_list.auto_height = false
	_list.item_activated.connect(func(i): accept_completion(i))
	_list.item_clicked.connect(func(i, _p, _b): accept_completion(i))
	code.add_child(_list)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(540, 0)
	box.add_child(message)
	confirmed.connect(func():
		if _done.is_valid():
			_done.call(text()))



## 開く。done は決定したときに、書いた式（改行は空白にする）で呼ぶ。
func open(value: String, p_mode: String = MODE_CONDITION, done: Callable = Callable()) -> void:
	expr_mode = p_mode
	_done = done
	title = "式エディタ（条件）" if expr_mode == MODE_CONDITION else "式エディタ（変数の計算：名前 = 式; …）"
	code.text = value.replace("; ", ";\n") if expr_mode == MODE_LET else value
	_check()
	popup_centered(Vector2i(600, 340))
	code.grab_focus.call_deferred()


## 書いた式。条件式は改行を空白に、let 文は改行を "; " にする。
func text() -> String:
	var lines := []
	for l in code.text.split("\n"):
		if l.strip_edges() != "":
			lines.append(l.strip_edges())
	if expr_mode == MODE_LET:
		return "; ".join(lines.map(func(l): return String(l).trim_suffix(";")))
	return " ".join(lines)


## 書いた式の誤り（なければ空文字）。
func error_text() -> String:
	var t := text()
	if t == "":
		return ""
	if expr_mode == MODE_LET:
		return "" if AdvExpr.parse_let(t) != null else "「名前 = 式」を ; で区切って書いてください。"
	var e := AdvCondition.check(t)
	return "" if e == "" else "条件式の誤り：%s" % e


func _check() -> void:
	var e := error_text()
	var unknown := _unknown_names()
	if e != "":
		message.text = e
		message.modulate = Color(1, 0.5, 0.45)
	elif not unknown.is_empty():
		message.text = "知らない名前（新しい変数なら問題ありません）：%s" % "、".join(unknown)
		message.modulate = Color(1, 0.85, 0.4)
	else:
		message.text = "正しい式です。" if text() != "" else "Ctrl+Space で候補を出せます。"
		message.modulate = Color(0.6, 0.9, 0.6)
	get_ok_button().disabled = e != ""


## 候補にない名前（関数の引数は除く）。
func _unknown_names() -> Array:
	var known := {}
	for c in candidates:
		known[String(c["name"]).get_slice("(", 0)] = true
	for k in KEYWORDS:
		known[k] = true
	var out := []
	var re := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_\\.]*)\\s*(\\()?")
	var t := text()
	for m in re.search_all(t):
		var name := m.get_string(1)
		if m.get_string(2) != "":
			continue   # 関数（組み込み）
		# 関数の引数（visited(hall) の hall）は、シーン・会話・アイテムなどの名前なので、候補と比べるだけ
		if not known.has(name) and not name in out and not name.is_valid_float():
			out.append(name)
	return out


func _on_text_changed() -> void:
	_check()
	# 名前を打っている途中か、関数の括弧を開いたところなら候補を出す
	var line := code.get_line(code.get_caret_line())
	var col := code.get_caret_column()
	if col > 0:
		var ch := line[col - 1]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "(":
			request_completion()
			return
	hide_completion()


## 候補の一覧を出す（打った途中の名前と、いま書いている関数の引数に合うもの）。
func request_completion() -> void:
	var items := completion_items()
	_list.clear()
	if items.is_empty():
		hide_completion()
		return
	for c in items:
		_list.add_item(String(c["label"]))
		_list.set_item_metadata(_list.item_count - 1, c["insert"])
		_list.set_item_tooltip(_list.item_count - 1, String(c.get("note", "")))
	_list.select(0)
	var pos := code.get_caret_draw_pos()
	var h := mini(items.size(), 8) * 22 + 8
	_list.size = Vector2(320, h)
	var y := pos.y + code.get_line_height() * 0.5 + 4
	if y + h > code.size.y:
		y = maxf(0, pos.y - code.get_line_height() * 1.5 - h)
	_list.position = Vector2(clampf(pos.x, 0, maxf(0, code.size.x - 320)), y)
	_list.visible = true


func hide_completion() -> void:
	if _list != null:
		_list.visible = false


func is_completion_visible() -> bool:
	return _list != null and _list.visible


## いまの位置の候補 [{label, insert, note}]（insert は打った途中の名前と置き換える文字）。
func completion_items() -> Array:
	var line := code.get_line(code.get_caret_line()).substr(0, code.get_caret_column())
	var pm := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_.]*)$").search(line)
	var prefix := pm.get_string(1) if pm != null else ""
	var before := line.substr(0, line.length() - prefix.length())
	# いま、関数の引数を書いているなら、その関数に合う候補だけ
	var fn := ""
	var open_at := before.rfind("(")
	if open_at > 0 and before.rfind(")") < open_at:
		var m := RegEx.create_from_string("([A-Za-z_]+)\\s*$").search(before.substr(0, open_at))
		if m != null:
			fn = m.get_string(1)
	var in_arg := fn != "" and before.substr(open_at + 1).strip_edges() == ""
	var want := {"has": ["アイテム"], "count": ["アイテム"], "visited": ["シーン"], "talked": ["会話"], "read": ["会話"],
		"chosen": ["選択肢"], "feature": ["機能"]}
	var lp := prefix.to_lower()
	var starts := []
	var contains := []
	var pool := candidates.duplicate()
	if not in_arg:
		for k in KEYWORDS:
			pool.append({"name": k, "kind": "ことば"})
	for c in pool:
		var kind := String(c["kind"])
		if in_arg and want.has(fn) and not kind in want[fn]:
			continue
		if not in_arg and kind in ["シーン", "会話", "選択肢", "機能"]:
			continue
		var name := String(c["name"])
		var bare := name.get_slice("(", 0)
		var e := {"label": "%s  — %s" % [name, kind], "insert": bare + ("(" if name.contains("(") else ""),
			"note": String(c.get("note", ""))}
		if lp == "" or bare.to_lower().begins_with(lp):
			starts.append(e)
		elif bare.to_lower().contains(lp):
			contains.append(e)
	if prefix == "" and not in_arg:
		return []   # 何も打っていなければ出さない（Ctrl+Space なら全部出す）
	return starts + contains


## 選んだ候補を入れる（打った途中の名前と置き換える）。
func accept_completion(index: int = -1) -> void:
	if not is_completion_visible():
		return
	if index < 0:
		var sel := _list.get_selected_items()
		index = sel[0] if not sel.is_empty() else 0
	var insert := String(_list.get_item_metadata(index))
	var line_no := code.get_caret_line()
	var col := code.get_caret_column()
	var line := code.get_line(line_no)
	var pm := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)$").search(line.substr(0, col))
	var start := col - (pm.get_string(1).length() if pm != null else 0)
	code.set_line(line_no, line.substr(0, start) + insert + line.substr(col))
	code.set_caret_column(start + insert.length())
	hide_completion()
	_check()
	if insert.ends_with("("):
		request_completion()


func _on_code_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var k: InputEventKey = event
	if k.keycode == KEY_SPACE and k.is_command_or_control_pressed():
		var items := completion_items()
		if items.is_empty():
			# 何も打っていないときは、すべて
			_list.clear()
			for c in candidates:
				_list.add_item("%s  — %s" % [c["name"], c["kind"]])
				var nm := String(c["name"])
				_list.set_item_metadata(_list.item_count - 1, nm.get_slice("(", 0) + ("(" if nm.contains("(") else ""))
			if _list.item_count > 0:
				_list.select(0)
				_list.position = code.get_caret_draw_pos() + Vector2(0, code.get_line_height() * 0.5 + 4)
				_list.size = Vector2(320, 8 * 22 + 8)
				_list.visible = true
		else:
			request_completion()
		code.get_viewport().set_input_as_handled()
		return
	if not is_completion_visible():
		return
	match k.keycode:
		KEY_UP, KEY_DOWN:
			var sel := _list.get_selected_items()
			var i: int = sel[0] if not sel.is_empty() else 0
			i = clampi(i + (1 if k.keycode == KEY_DOWN else -1), 0, _list.item_count - 1)
			_list.select(i)
			_list.ensure_current_is_visible()
			code.get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			accept_completion()
			code.get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			hide_completion()
			code.get_viewport().set_input_as_handled()


## プロジェクトとシナリオのモデルから候補を作る。
## システムシーンで読める値（6.9）。
const SYS_NAMES := [["mode", "save・load・settings・log"], ["slot_count", "セーブ枠の数"], ["slot_01", "枠の説明（日時とシーン名）"],
	["slot_01_exists", "枠にセーブがあるか"], ["slot_01_label", "枠の名前"], ["text_speed", "文字の速さ"], ["bgm_volume", "おんがくの大きさ"],
	["se_volume", "効果音の大きさ"], ["voice_volume", "声の大きさ"], ["auto_delay", "オートの待ち時間"]]


## サブシーンの引数（arg.名前）を候補に足す。
static func _add_params(data: Dictionary, add: Callable) -> void:
	var scs = data.get("scenes", {})
	if not scs is Dictionary:
		return
	for sid in scs:
		var sc = scs[sid]
		if sc is Dictionary and sc.get("params") is Dictionary:
			for p in sc["params"]:
				add.call("arg." + String(p), "引数", "サブシーン %s" % sid)


static func collect_candidates(model: AdvScenarioModel = null) -> Array:
	var out := []
	var seen := {}
	var add := func(name: String, kind: String, note: String = ""):
		var key := kind + ":" + name
		if seen.has(key) or name == "":
			return
		seen[key] = true
		out.append({"name": name, "kind": kind, "note": note})
	for b in AdvVariableIndex.BUILTINS:
		var n := String(b[0])
		add.call(n.get_slice("(", 0) + ("()" if n.contains("(") else ""), "組み込み", String(b[1]))
	var path := model.project_path if model != null else AdvProject.DEFAULT_PATH
	for v in AdvVariableIndex.collect(path):
		if v.get("kind") in ["変数", "定数", "リスト"]:
			add.call(String(v["name"]), String(v["kind"]), String(v.get("type", "")))
	if model != null:
		for id in model.all_scene_ids():
			add.call(String(id), "シーン")
		for id in model.all_dialogue_ids():
			add.call(String(id), "会話")
		for s in model.scenarios():
			if s["loose"]:
				continue
			var d := model.load_scenario_data(s["id"])
			for id in d.get("items", {}):
				add.call(String(id), "アイテム")
			_add_params(d, add)
			for c in model.chapters(s["id"]):
				var cd := model.load_chapter_data(s["id"], c["id"])
				for id in cd.get("items", {}):
					add.call(String(id), "アイテム")
				_add_params(cd, add)
	for n in SYS_NAMES:
		add.call("sys." + String(n[0]), "システム", String(n[1]))
	for f in AdvFeatures.TABLE:
		add.call(String(f), "機能")
	return out
