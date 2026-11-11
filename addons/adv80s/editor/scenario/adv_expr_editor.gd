@tool
class_name AdvExprEditor
extends ConfirmationDialog
## 式エディタ（6.8）。条件式（if・when）や let 文を、複数行のテキストで書く。
## 打つと、変数・定数・アイテム・シーン・会話・組み込みの名前を候補に出す（Ctrl+Space でも出る）。
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


func _init() -> void:
	title = "式エディタ"
	min_size = Vector2i(560, 320)
	ok_button_text = "決定"
	var box := VBoxContainer.new()
	add_child(box)
	code = CodeEdit.new()
	code.custom_minimum_size = Vector2(540, 200)
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.code_completion_enabled = true
	code.auto_brace_completion_enabled = true
	code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code.code_completion_requested.connect(_on_completion)
	code.text_changed.connect(_on_text_changed)
	box.add_child(code)
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
	# 名前を打っている途中なら候補を出す
	var line := code.get_line(code.get_caret_line())
	var col := code.get_caret_column()
	if col > 0:
		var ch := line[col - 1]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_" or ch == "(":
			code.request_code_completion()


func _on_completion() -> void:
	var line := code.get_line(code.get_caret_line()).substr(0, code.get_caret_column())
	# いま、関数の引数を書いているなら、その関数に合う候補だけ
	var fn := ""
	var open_at := line.rfind("(")
	if open_at > 0 and line.rfind(")") < open_at:
		var re := RegEx.create_from_string("([A-Za-z_]+)\\s*$")
		var m := re.search(line.substr(0, open_at))
		if m != null:
			fn = m.get_string(1)
	var want := {"has": ["アイテム"], "count": ["アイテム"], "visited": ["シーン"], "talked": ["会話"],
		"chosen": ["選択肢"], "feature": ["機能"]}
	for c in candidates:
		var kind := String(c["kind"])
		if fn != "" and want.has(fn) and not kind in want[fn]:
			continue
		if fn == "" and kind in ["シーン", "会話", "選択肢", "機能"]:
			continue
		var name := String(c["name"])
		var insert := name.get_slice("(", 0) + ("(" if name.contains("(") else "")
		var t := CodeEdit.KIND_FUNCTION if name.contains("(") else (CodeEdit.KIND_CONSTANT if kind == "定数" else CodeEdit.KIND_VARIABLE)
		code.add_code_completion_option(t, "%s  — %s" % [name, kind] if String(c.get("note", "")) == "" else "%s  — %s：%s" % [name, kind, c["note"]], insert)
	if fn == "":
		for k in KEYWORDS:
			code.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, k, k)
	code.update_code_completion_options(false)


## プロジェクトとシナリオのモデルから候補を作る。
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
			for c in model.chapters(s["id"]):
				for id in model.load_chapter_data(s["id"], c["id"]).get("items", {}):
					add.call(String(id), "アイテム")
	for f in AdvFeatures.TABLE:
		add.call(String(f), "機能")
	return out
