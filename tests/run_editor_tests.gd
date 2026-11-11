extends SceneTree
## シナリオエディタ（6.8）の画面のテスト。
##   godot --path . --script res://tests/run_editor_tests.gd        （画面あり：tests/_shots/editor_*.png を書く）
##   godot --headless --path . --script res://tests/run_editor_tests.gd
## 失敗があれば終了コード 1 で終わる。

const BASE := "res://tests/_tmp_editor"

var _failed := 0
var _passed := 0
var ed: AdvScenarioEditor


func _initialize() -> void:
	_main.call_deferred()


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


func _settle(n: int = 3) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/_shots")
	root.get_texture().get_image().save_png("res://tests/_shots/editor_%s.png" % name)


func _rmdir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rmdir(path + "/" + sub)
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


func _main() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	_rmdir(BASE)
	DirAccess.make_dir_recursive_absolute(BASE)
	var pj := BASE + "/adv80s.project.json"
	AdvScenarioModel._save_json(pj, {"project_version": 1, "title": "テスト", "scenarios": []})
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	ed = AdvScenarioEditor.new(pj)
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ed)
	ed.reload()
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.ROOT, "editor: asks for the scenario folder first")
	await _shot("01_root")

	ed._root_edit.text = BASE + "/scenario"
	ed._on_root_decided()
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.GAME, "editor: game list after the folder")
	ed._on_new()
	await _settle()
	check(ed._grid.ids().size() == 1, "editor: new scenario card")
	ed._grid.get_viewport().gui_release_focus()
	ed._on_new()
	await _settle()
	ed.get_viewport().gui_release_focus()
	await _settle()
	check(ed._grid.ids().size() == 2, "editor: two scenarios")
	await _shot("02_game")

	# 名前の変更（カードの上で）
	var first := String(ed._grid.ids()[0])
	ed._on_card_renamed(first, "やかたの なぞ")
	check(ed.model.scenario(first)["name"] == "やかたの なぞ", "editor: renamed scenario")

	# 設定のタブ：変数を足して保存
	check(ed._tabs.get_tab_count() == 6, "editor: settings tabs (%d)" % ed._tabs.get_tab_count())
	var vf: AdvSchemaForm = ed._tab_forms[1]["form"]
	vf.data = {"variables": {"money": {"type": "int", "default": 10}}}
	ed._dirty = true
	ed.save()
	check(AdvScenarioModel._load(BASE + "/adv80s.project.json").get("variables", {}).has("money"), "editor: game settings saved")

	# 複写（2つずつ）
	ed._menu_ids = [first]
	ed._ask_copy(false)
	ed._copy_count.value = 2
	ed._copy_dialog.hide()
	ed._do_copy()
	await _settle()
	check(ed._grid.ids().size() == 4, "editor: duplicated 2 (%s)" % str(ed._grid.ids()))

	# シナリオを開く → チャプター → シーン
	ed._on_card_opened(first)
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.SCENARIO and ed._grid.ids() == ["chapter1"], "editor: chapter list")
	check(ed._crumbs.get_child_count() >= 5, "editor: breadcrumb")
	await _shot("03_scenario")
	ed._on_card_opened("chapter1")
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.CHAPTER and ed._grid.ids().size() == 1, "editor: scene list")
	var scene := String(ed._grid.ids()[0])
	ed._on_new()
	await _settle()
	ed.get_viewport().gui_release_focus()
	check(ed._grid.ids().size() == 2, "editor: new scene")
	await _shot("04_chapter")
	ed._on_card_opened(scene)
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.SCENE, "editor: scene page")
	check(ed._cmd_list.item_count == 1, "editor: enter is listed as a command")
	await _shot("05_scene")

	# コマンドを作る：もの「つくえ」を足し、LOOK の手順に台詞と条件分岐と選択肢を書く
	ed._open_command({"target": "scene", "key": ""})
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.COMMAND, "editor: command page")
	ed._add_target("objects", "desk")
	ed._cmd_verb.select(ed._cmd_verbs.find("LOOK"))
	var st := ed._cmd_steps
	st.add_step("text").set_text(1, "つくえが ある。")
	st.tree.deselect_all()
	var cond := st.add_step("if")
	cond.set_text(2, "money >= 10")
	cond.select(0)
	st.add_step("say").set_text(1, "@me おかねが ある。")
	st.tree.deselect_all()
	var ch := st.add_step("choice")
	ch.select(0)
	st.add_step("option").set_text(1, "しらべる")
	ed.save()
	await _settle()
	var sd: Dictionary = ed._load_scene()
	var look: Array = sd.get("objects", {}).get("desk", {}).get("on", {}).get("LOOK", [])
	check(look.size() == 3 and look[0] == "つくえが ある。", "editor: command steps saved: %s" % str(look))
	check(look.size() == 3 and look[1].get("if") == "money >= 10" and look[1]["then"] == ["@me おかねが ある。"], "editor: if step")
	check(look.size() == 3 and look[2]["choice"]["options"].size() == 3, "editor: choice with options")
	await _shot("06_command")

	# 手順の木：読み込んで書き戻すと同じになる
	var steps := [
		"地の文", "@a 台詞", {"if": "has(key)", "then": ["あく"], "else": [{"goto": "hall"}]},
		{"let": "money = money - 1"}, {"call": "chat"}, {"ink": "knot"}, {"image.show": {"id": "bg"}},
		{"choice": {"prompt": "どれ？", "options": [{"label": "A", "when": "visited(hall)", "do": ["a"], "once": true}]}},
	]
	st.set_steps(steps)
	check(st.get_steps() == steps, "step editor: round trip: %s" % JSON.stringify(st.get_steps()))

	# セリフ（JSON）
	ed._show(AdvScenarioEditor.Page.SCENE)
	await _settle()
	check(ed._cmd_list.item_count == 2, "editor: LOOK command listed (%d)" % ed._cmd_list.item_count)
	var dl := ed.model.load_chapter_data(first, "chapter1")
	dl["dialogues"] = {"chat": ["@a やあ"]}
	ed.model.save_chapter_data(first, "chapter1", dl)
	ed._fill_scene()
	ed._open_dialogue(ed._dlg_list.get_item_metadata(0))
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.DIALOGUE and ed._dlg_steps.get_steps() == ["@a やあ"], "editor: dialogue page")
	ed._dlg_steps.add_step("text").set_text(1, "またね")
	ed._dlg_id.text = "greet"
	ed.save()
	var dd: Dictionary = ed.model.load_chapter_data(first, "chapter1")["dialogues"]
	check(dd.has("greet") and not dd.has("chat") and dd["greet"].size() == 2, "editor: dialogue saved and renamed: %s" % str(dd))
	await _shot("07_dialogue")

	# 式エディタ
	var x := ed.expr_editor
	x.candidates = AdvExprEditor.collect_candidates(ed.model)
	check(x.candidates.any(func(c): return c["name"] == "money" and c["kind"] == "変数"), "expr: variable candidate")
	check(x.candidates.any(func(c): return c["kind"] == "シーン" and c["name"] == scene), "expr: scene candidate")
	x.open("has(key) and\nmoney >= 10", AdvExprEditor.MODE_CONDITION)
	check(x.text() == "has(key) and money >= 10" and x.error_text() == "", "expr: multi-line condition")
	x.code.text = "visited(" + scene.substr(0, 2)
	x.code.set_caret_column(10)
	x.code.request_code_completion(true)
	var opts := x.code.get_code_completion_options().map(func(o): return o["insert_text"])
	check(scene in opts and not "money" in opts, "expr: completion inside visited(): %s" % str(opts))
	x.code.text = "mo"
	x.code.set_caret_column(2)
	x.code.request_code_completion(true)
	opts = x.code.get_code_completion_options().map(func(o): return o["insert_text"])
	check("money" in opts, "expr: completion of names: %s" % str(opts))
	x.code.text = "money >= "
	check(x.error_text() != "", "expr: error shown")
	x.open("a = 1; b = a + 2", AdvExprEditor.MODE_LET)
	check(x.code.text == "a = 1;\nb = a + 2" and x.text() == "a = 1; b = a + 2", "expr: let lines")
	await _settle()
	await _shot("08_expr")
	x.hide()

	# パンくずで戻る
	ed._show(AdvScenarioEditor.Page.GAME)
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.GAME and ed._grid.ids().size() == 4, "editor: back to the game list")

	# 作ったものがゲームとして読める
	var p: Dictionary = AdvScenarioModel._load(pj)
	var core := AdvCore.new()
	core.setup({"seed": 1})
	core.use_adapter(AdvJsonAdapter.new())
	check(core.load_scenario(PackedStringArray(p["scenarios"])) == OK, "editor: scenario files load")
	var errs := core.validate().filter(func(d): return d["severity"] == "error")
	check(errs.is_empty(), "editor: no errors: %s" % str(errs.map(func(d): return d["message"])))

	_rmdir(BASE)
	print("")
	print("passed: %d  failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
