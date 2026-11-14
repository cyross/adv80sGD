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
	# スクリプトのエラーで止まったときに、待ち続けないように
	create_timer(100.0).timeout.connect(func():
		printerr("FAIL: timed out")
		quit(1))


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


func _settle(n: int = 3) -> void:
	for i in n:
		await process_frame


## 段階60：ひな形まわりの窓を順に開いて写真を撮る（大きさ・文字の切れの見直し）。
func _review_windows(ed: AdvScenarioEditor) -> void:
	ed.save_run_preset("見直し：とても長い名前のひな形を一つ作っておく", {"lamp": true, "money": 120, "name": "たろう", "long_variable_name_for_review": "長い文字の値をここに"}, {"key": 2, "lamp_item": 1}, "見直しの組")
	ed.save_run_preset("見直し2", {"lamp": false}, {"key": 1}, "見直しの組")
	ed.open_preset_dialog("見直し：とても長い名前のひな形を一つ作っておく")
	ed.compare_preset_with("見直し2")
	await _shot("review_01_preset_dialog")
	# 段階61：窓を広げると違いの欄が伸びる
	var h61 := ed._preset_diff.size.y
	ed._preset_dialog.size = Vector2i(ed._preset_dialog.size.x, ed._preset_dialog.size.y + 200)
	await process_frame
	await process_frame
	check(ed._preset_diff.size.y >= h61 + 150.0, "s61: diff grows with the window: %s → %s" % [h61, ed._preset_diff.size.y])
	await _shot("review_01b_preset_dialog_tall")
	ed._preset_dialog.size = Vector2i(ed._preset_dialog.size.x, ed._preset_dialog.size.y - 200)
	# 段階62：ひな形の窓のキー
	check(ed._preset_dialog.get_node_or_null("Keys") is AdvKeyCatcher, "s62: key catcher in the preset dialog")
	var kz := InputEventKey.new()
	kz.pressed = true
	kz.ctrl_pressed = true
	kz.keycode = KEY_Z
	check(not ed._on_preset_key(kz), "s62: Ctrl+Z with nothing to undo passes through")
	ed.compare_preset_with("見直し2")
	ed.take_preset_value("vars", "lamp")
	check(ed._preset_vars.text.begins_with("lamp = false"), "s62: took a value")
	ed._preset_dialog.gui_release_focus()
	check(ed._on_preset_key(kz) and ed._preset_vars.text.begins_with("lamp = true"), "s62: Ctrl+Z undoes the take")
	var ka := InputEventKey.new()
	ka.pressed = true
	ka.keycode = KEY_Z
	check(not ed._on_preset_key(ka), "s62: Z alone is just a letter")
	ed._preset_vars.text = ed._preset_vars.text + "\nkey62 = 6"
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.ctrl_pressed = true
	ke.keycode = KEY_ENTER
	check(ed._on_preset_key(ke) and not ed._preset_dialog.visible and int(ed.run_presets()["見直し：とても長い名前のひな形を一つ作っておく"]["vars"].get("key62", 0)) == 6, "s62: Ctrl+Enter saves and closes")
	check(ed._preset_dialog.get_ok_button().tooltip_text.contains("Ctrl+Enter"), "s62: save button tells the key")
	ed.open_preset_dialog("見直し：とても長い名前のひな形を一つ作っておく")
	ed.compare_preset_with("見直し2")
	# 本当のキー入力で（文字の欄にフォーカスがあっても、欄より先に受け取る）
	await process_frame
	ed._preset_vars.grab_focus()
	ed.take_preset_value("vars", "lamp")
	Input.parse_input_event(kz.duplicate())
	await process_frame
	await process_frame
	check(ed._preset_vars.text.begins_with("lamp = true"), "s62: real Ctrl+Z in the text box undoes the take: %s" % ed._preset_vars.text.get_slice("\n", 0))
	ed._preset_vars.text = ed._preset_vars.text + "\nkey62b = 7"
	ed._preset_vars.grab_focus()
	Input.parse_input_event(ke.duplicate())
	await process_frame
	await process_frame
	check(not ed._preset_dialog.visible and int(ed.run_presets()["見直し：とても長い名前のひな形を一つ作っておく"]["vars"].get("key62b", 0)) == 7, "s62: real Ctrl+Enter in the text box saves")
	ed.open_preset_dialog("見直し：とても長い名前のひな形を一つ作っておく")
	ed.compare_preset_with("見直し2")
	ed.compare_preset_with_start()
	await _shot("review_02_preset_start")
	ed._preset_dialog.hide()
	ed.open_tidy_dialog()
	await _shot("review_03_tidy")
	# 段階62：窓を広げると一覧が伸びる
	var sc62 := ed._tidy_list.get_parent() as Control
	var th62 := sc62.size.y
	ed._tidy_dialog.size = Vector2i(ed._tidy_dialog.size.x, ed._tidy_dialog.size.y + 200)
	await process_frame
	await process_frame
	check(sc62.size.y >= th62 + 150.0, "s62: tidy list grows: %s → %s" % [th62, sc62.size.y])
	ed._tidy_dialog.size = Vector2i(ed._tidy_dialog.size.x, ed._tidy_dialog.size.y - 200)
	ed._tidy_dialog.hide()
	ed.open_group_dialog("見直しの組")
	await _shot("review_04_group")
	ed._group_dialog.hide()
	ed.open_move_group_dialog("見直し2")
	await _shot("review_05_move_group")
	ed._move_group_dialog.hide()
	ed.open_export_pick()
	await _shot("review_06_export_pick")
	ed._preset_export_pick.hide()
	var f := "user://review_presets.json"
	ed.export_run_presets(f)
	ed.delete_run_preset("見直し2")
	ed.open_import_pick(f)
	var isc62 := ed._import_list.get_parent() as Control
	var ih62 := isc62.size.y
	ed._preset_import_pick.size = Vector2i(ed._preset_import_pick.size.x, ed._preset_import_pick.size.y + 200)
	await process_frame
	await process_frame
	check(isc62.size.y >= ih62 + 150.0, "s62: import list grows: %s → %s" % [ih62, isc62.size.y])
	ed._preset_import_pick.size = Vector2i(ed._preset_import_pick.size.x, ed._preset_import_pick.size.y - 200)
	# 段階61：読み込む窓の説明にファイルの中身（同じ名前があればいまの中身も）
	var tip61 := (ed._import_checks["見直し2"] as CheckBox).tooltip_text
	check(tip61.contains("ファイル：lamp = false ／ 持ち物 key × 1") and not tip61.contains("いま"), "s61: import tip shows file contents: %s" % tip61)
	var tip61b := (ed._import_checks["見直し：とても長い名前のひな形を一つ作っておく"] as CheckBox).tooltip_text
	check(tip61b.contains("\nファイル：") and tip61b.contains("lamp = true、") and tip61b.contains("\nいま　　：lamp = true"), "s61: import tip shows the current one too: %s" % tip61b)
	check(AdvScenarioEditor.preset_value_summary({}) == "（中身なし）" and AdvScenarioEditor.preset_value_summary(null) == "（中身なし）", "s61: summary of nothing")
	await _shot("review_07_import_pick")
	# 段階63：読み込む窓の Ctrl+Enter
	var ke63 := InputEventKey.new()
	ke63.pressed = true
	ke63.ctrl_pressed = true
	ke63.keycode = KEY_ENTER
	check(ed._preset_import_pick.get_node_or_null("Keys") is AdvKeyCatcher and ed._on_import_key(ke63) and ed.run_presets().has("見直し2") and not ed._preset_import_pick.visible, "s63: Ctrl+Enter in the import window reads")
	check(ed._preset_import_pick.get_ok_button().tooltip_text.contains("Ctrl+Enter"), "s63: read button tells the key")
	ed._preset_import_pick.hide()
	DirAccess.remove_absolute(f)
	AdvPlayer.put_notice_style_set(true, "見直しの見た目", {"fg": 7, "bg": 1, "position": "top", "margin": 8})
	AdvPlayer.put_notice_style_set(true, "見直し2", {"fg": 2})
	ed.open_style_sets_dialog(true)
	ed.select_style_set("見直しの見た目")
	await _shot("review_08_style_sets")
	ed.compare_style_with("見直し2")
	await _shot("review_09_style_compare")
	ed._style_dialog.hide()
	DirAccess.remove_absolute(AdvPlayer.NOTICE_STYLE_SETS_FILE)
	ed.open_preset_context("見直し：とても長い名前のひな形を一つ作っておく", Vector2(200, 60))
	await _shot("review_10_context_menu")
	ed._preset_ctx.hide()


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
	AdvScenarioModel._save_json(pj, {"project_version": 1, "title": "テスト", "scenarios": [], "asset_roots": [BASE + "/assets"]})
	# サムネイルと範囲のエディタ用の背景
	DirAccess.make_dir_recursive_absolute(BASE + "/assets/bg")
	var bimg := Image.create(320, 200, false, Image.FORMAT_RGB8)
	bimg.fill(Color(0.2, 0.3, 0.5))
	bimg.fill_rect(Rect2i(40, 40, 120, 80), Color(0.8, 0.6, 0.2))
	bimg.save_png(BASE + "/assets/bg/hallroom.png")
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
	# 新規作成：名前と ID を聞く
	ed._on_new()
	await _settle()
	check(ed._new_dialog.visible, "editor: new dialog asks name and id")
	ed._new_name.text = "Mansion"
	ed._new_name.text_changed.emit("Mansion")
	check(ed._new_id.text == "mansion", "editor: id suggested from the name (%s)" % ed._new_id.text)
	await _shot("02a_new")
	ed._new_dialog.get_ok_button().pressed.emit()
	await _settle()
	check(ed._grid.ids() == ["mansion"], "editor: new scenario card (%s)" % str(ed._grid.ids()))
	ed._on_new()
	ed._new_name.text = "やかた"
	ed._new_name.text_changed.emit("やかた")
	check(ed._new_id.text == "scenario", "editor: Japanese name gets a fallback id")
	ed._new_id.text = "Bad ID"
	ed._new_id.text_changed.emit("Bad ID")
	check(ed._new_dialog.get_ok_button().disabled, "editor: invalid id blocks OK")
	ed._new_id.text = "mansion"
	ed._new_id.text_changed.emit("mansion")
	check(ed._new_dialog.get_ok_button().disabled, "editor: taken id blocks OK")
	ed._new_dialog.hide()
	ed.create_item("やかた", "yakata")
	await _settle()
	check(ed._grid.ids().size() == 2, "editor: two scenarios")
	await _shot("02_game")

	# 名前の変更（カードの上で）
	var first := String(ed._grid.ids()[0])
	ed._on_card_renamed(first, "やかたの なぞ")
	check(ed.model.scenario(first)["name"] == "やかたの なぞ", "editor: renamed scenario")

	# 設定のタブ：変数を足して保存
	check(ed._tabs.get_tab_count() == 9, "editor: settings tabs (%d)" % ed._tabs.get_tab_count())
	# 段階23：タイトル・おわりとおまけ・システムのタブ
	var tab_names := []
	for i in ed._tabs.get_tab_count():
		tab_names.append(ed._tabs.get_tab_title(i))
	check(tab_names.slice(5, 9) == ["タイトル", "おわり・おまけ", "システム", "その他"], "s23: new settings tabs: %s" % str(tab_names))
	var ext_keys: Array = ed._tab_forms[6]["keys"]
	check(ext_keys == ["endings", "fin", "extras"] and ed._tab_forms[5]["keys"].has("title_variants"), "s23: tab keys")
	var other_keys: Array = ed._tab_forms[8]["keys"]
	check(not other_keys.has("extras") and not other_keys.has("title_screen"), "s23: moved out of the other tab: %s" % str(other_keys))
	# 素材の候補
	check(AdvScenarioEditor.asset_kind_of(["extras", "gallery", "images"]) == "image" and AdvScenarioEditor.asset_kind_of(["extras", "music", "id"]) == "bgm"
		and AdvScenarioEditor.asset_kind_of(["title_bgm"]) == "bgm" and AdvScenarioEditor.asset_kind_of(["fin", "items", "image"]) == "image"
		and AdvScenarioEditor.asset_kind_of(["variables"]) == "", "s23: asset kinds of fields")
	check(ed._suggest(["extras", "gallery", 0, "id"]) == Array(ed.model.asset_ids("image")), "s23: gallery id suggests images")
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
	# 削除と元に戻す
	ed._menu_ids = [ed._grid.ids()[3]]
	var gone := String(ed._grid.ids()[3])
	ed._do_delete()
	check(ed.model.scenario(gone).is_empty(), "editor: deleted")
	ed.undo()
	check(not ed.model.scenario(gone).is_empty() and ed._grid.ids().size() == 4, "editor: undo delete")

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
	ed.create_item("ろうか", "hall")
	await _settle()
	check(ed._grid.ids().size() == 2, "editor: new scene")
	# 背景を付けるとサムネイル
	var cd0 := ed.model.load_chapter_data(first, "chapter1")
	cd0["scenes"][scene]["image"] = "hallroom"
	cd0["scenes"]["hall"]["enter"] = [{"goto": scene}]
	ed.model.save_chapter_data(first, "chapter1", cd0)
	ed._show(AdvScenarioEditor.Page.CHAPTER)
	await _settle()
	check(ed._grid._cards[scene].find_children("*", "TextureRect", true, false).size() == 1, "editor: thumbnail on the scene card")
	# 並べ替え
	ed._on_reordered(["hall", scene])
	check(ed.model.scenes(first, "chapter1").map(func(x): return x["id"]) == ["hall", scene], "editor: scenes reordered")
	check(AdvCardGrid.move_ids(["a", "b", "c", "d"], ["a", "c"], "d", true) == ["b", "d", "a", "c"], "card grid: move ids after")
	check(AdvCardGrid.move_ids(["a", "b", "c", "d"], ["d"], "a", false) == ["d", "a", "b", "c"], "card grid: move ids before")
	# ID の変更：参照（goto、start、entry）も変わる。元に戻す・やり直す
	var old_scene := scene
	check(ed.change_id(old_scene, "entrance") == OK, "editor: change scene id")
	scene = "entrance"
	var cd1 := ed.model.load_chapter_data(first, "chapter1")
	check(cd1["scenes"].has("entrance") and cd1["scenes"]["hall"]["enter"][0]["goto"] == "entrance", "editor: goto follows the new id")
	check(ed.model.load_scenario_data(first)["start"] == "entrance", "editor: start follows the new id")
	check(ed.model.load_project()["entry"] == "entrance", "editor: entry follows the new id")
	check(ed.change_id("hall", "entrance") != OK, "editor: taken id refused")
	ed.undo()
	check(ed.model.load_chapter_data(first, "chapter1")["scenes"].has(old_scene) and ed.model.load_scenario_data(first)["start"] == old_scene, "editor: undo id change")
	ed.redo()
	check(ed.model.load_chapter_data(first, "chapter1")["scenes"].has("entrance"), "editor: redo id change")
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

	# 選択肢の項目の専用の欄（once・id）
	var opt_item: TreeItem = st.tree.get_root().get_child(2).get_child(0)
	opt_item.select(0)
	await _settle()
	var once_box := st._details.find_child("once", false, false) as CheckBox
	check(once_box != null, "step editor: once field for an option")
	once_box.button_pressed = true
	(st._details.find_child("id", false, false) as LineEdit).text_changed.emit("pick_yes")
	var copts: Array = st.get_steps()[2]["choice"]["options"]
	check(copts[0].get("once") == true and copts[0].get("id") == "pick_yes", "step editor: once and id saved: %s" % str(copts[0]))
	await _shot("06b_details")

	# 範囲を絵で決める
	ed.save()
	ed._show(AdvScenarioEditor.Page.SCENE)
	await _settle()
	ed._open_region_editor()
	await _settle()
	var rg := ed.region_editor
	check(rg.visible and rg.texture != null and rg.image_size() == Vector2i(320, 200), "region editor: shows the background")
	rg.list.select(0)
	rg.set_region_by_drag(Vector2i(110, 90), Vector2i(10, 20))
	await _settle()
	await _shot("06c_region")
	rg.get_ok_button().pressed.emit()
	await _settle()
	var desk: Dictionary = ed._load_scene()["objects"]["desk"]
	check(desk.get("region") == [10, 20, 100, 70] and desk["on"].has("LOOK"), "region editor: region saved and steps kept: %s" % str(desk))

	# フォームの式の項目には「式…」
	check(ed._expr_mode_of(["objects", "desk", "when"], {"$ref": "#/definitions/condition"}) == "condition", "form: condition fields open the expression editor")
	check(ed._expr_mode_of(["x"], {"type": "string"}) == "", "form: other fields do not")

	# 手順の木：読み込んで書き戻すと同じになる
	var steps := [
		"地の文", "@a 台詞", {"if": "has(key)", "then": ["あく"], "else": [{"goto": "hall"}]},
		{"let": "money = money - 1"}, {"call": "chat"}, {"ink": "knot"}, {"image.show": {"id": "bg"}},
		{"choice": {"prompt": "どれ？", "options": [{"label": "A", "when": "visited(hall)", "do": ["a"], "once": true}]}},
		{"call_scene": "shop", "args": {"price": "=money + 1"}, "into": "result"}, {"return": "=arg.price * 2"},
		{"return": null}, {"return": true},
	]
	st.set_steps(steps)
	check(st.get_steps() == steps, "step editor: round trip: %s" % JSON.stringify(st.get_steps()))
	# 段階23：出力イベントの手順
	var ev_steps := [{"extras.open": {}}, {"fin.show": {"then": "title"}}, {"wait": 1.5}, {"opening.play": {}}]
	st.set_steps(ev_steps)
	var ev_root := st.tree.get_root()
	check(ev_root.get_children().all(func(it): return it.get_metadata(0)["t"] == "event"), "s23: events read as event steps")
	check(st.get_steps() == ev_steps, "s23: event steps round trip: %s" % JSON.stringify(st.get_steps()))
	check(AdvStepEditor.event_names().has("extras.open") and AdvStepEditor.event_names().has("fin.show"), "s23: event names from the schema")
	ev_root.get_child(1).select(1)
	await _settle()
	var eob := st._details.get_node("event_name") as OptionButton
	check(eob != null and eob.get_item_text(eob.selected) == "fin.show", "s23: event name picker")
	var ei := AdvStepEditor.event_names().find("credits.roll")
	eob.select(ei)
	eob.item_selected.emit(ei)
	check(st.get_steps()[1] == {"credits.roll": {"then": "title"}}, "s23: event renamed by the picker: %s" % JSON.stringify(st.get_steps()[1]))
	await _settle()
	# 段階24：引数はイベントごとのフォームで書く
	check(st.args_form.visible and st.args_form.schema_root.get("properties", {}).has("speed"), "s24: args form for credits.roll")
	st.args_form.data = {"items": ["スタッフ"], "speed": 40}
	st.args_form.changed.emit()
	check(st.get_steps()[1] == {"credits.roll": {"items": ["スタッフ"], "speed": 40}}, "s24: event args edited in the form: %s" % JSON.stringify(st.get_steps()[1]))
	if DisplayServer.get_name() != "headless":
		var shot_st := AdvStepEditor.new()
		var shot_bg := Panel.new()
		shot_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(shot_bg)
		shot_bg.add_child(shot_st)
		shot_st.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shot_st.set_steps(["くらく なった。", {"credits.roll": {"items": ["スタッフ"], "speed": 40}}, {"extras.open": {}}])
		shot_st.tree.get_root().get_child(1).select(1)
		await _settle()
		await _shot("09_event_args")
		shot_st.image_source = func(id: String) -> Variant: return ed._thumb(id)
		shot_st.id_source = ed.id_candidates
		shot_st.set_steps([{"image.show": {"id": "hallroom", "transition": "fade"}}])
		shot_st.tree.get_root().get_child(0).select(1)
		await _settle()
		await _shot("09b_image_preview")
		shot_st.set_steps([{"image.show": {"id": "hallroomm"}}])
		shot_st.tree.get_root().get_child(0).select(1)
		await _settle()
		await _shot("09c_missing_id")
		shot_bg.queue_free()
		await _settle()
	check(AdvStepEditor.event_args_schema("fin.show").get("properties", {}).has("then"), "s24: fin.show args use the fin definition")
	check(AdvStepEditor.event_args_schema("notice.show").get("required", []) == ["text"], "s24: notice.show args")
	check(AdvStepEditor.event_args_schema("x.custom").is_empty(), "s24: custom events have no form")
	ev_root.get_child(0).select(1)
	await _settle()
	check(not st.args_form.visible and st._details.get_children().any(func(c): return c is Label and c.text == "（引数はありません）"), "s24: events without args")
	st.set_steps([{"x.mine": {"a": 1}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(not st.args_form.visible and st._details.has_node("args"), "s24: custom events use JSON")
	# 段階25：引数の ID を一覧から選ぶ・手で書く
	check(AdvStepEditor.arg_id_kind("bgm.play", ["id"]) == "bgm" and AdvStepEditor.arg_id_kind("fin.show", ["items", 0, "image"]) == "image"
		and AdvStepEditor.arg_id_kind("scene.goto", ["scene"]) == "scene" and AdvStepEditor.arg_id_kind("bgm.play", ["fade"]) == "", "s25: id kinds of args")
	check(st.id_source.is_valid() and st.id_source.call("scene").has(scene), "s25: step editor gets id candidates")
	st.set_steps([{"scene.goto": {"scene": scene}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	var sg_item: TreeItem = null
	for it in st.args_form.get_root().get_children():
		if it.get_text(0) == "scene":
			sg_item = it
	var sg_meta: Dictionary = sg_item.get_metadata(0) if sg_item != null else {}
	check(sg_meta.get("kind") == "choice" and sg_meta["choices"].has(scene) and sg_meta["choices"].back() == AdvSchemaForm.MANUAL, "s25: scene picker with manual entry: %s" % str(sg_meta.get("choices")))
	check(st.args_form.suggest.call(["scene"]).has(scene), "s25: scene.goto suggests scenes")
	# 段階26：画像の ID の見本
	st.image_source = func(id: String) -> Variant: return ed._thumb(id)
	st.set_steps([{"image.show": {"id": "hallroom"}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(st.args_form.preview_of(["id"]) != null, "s26: image preview in the args form")
	st.set_steps([{"scene.goto": {"scene": scene}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(st.args_form.preview_of(["scene"]) == null, "s26: no preview for scenes")
	check(ed.form_preview(["title_image"], "hallroom") != null and ed.form_preview(["title_bgm"], "x") == null, "s26: settings form preview")
	# 段階27：音の項目に ▶
	st.audio_player = ed.play_audio
	st.set_steps([{"bgm.play": {"id": "theme"}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(st.args_form.has_play(["id"]) and not st.args_form.has_play(["fade"]), "s27: play button on bgm id")
	check(ed.form_audio_kind(["title_bgm"]) == "bgm" and ed.form_audio_kind(["notice_style", "se"]) == "se" and ed.form_audio_kind(["title_image"]) == "", "s27: audio kinds of settings")
	ed.play_audio("bgm", "no_such_bgm")
	check(ed.playing_audio == "", "s27: missing audio does not play")
	var some_bgm := Array(ed.model.asset_ids("bgm"))
	if not some_bgm.is_empty():
		ed.play_audio("bgm", some_bgm[0])
		check(ed.playing_audio == "bgm:" + some_bgm[0], "s27: preview plays")
		ed.play_audio("bgm", some_bgm[0])
		check(ed.playing_audio == "", "s27: pressing again stops")
	# 段階28：見つからない ID は赤字
	st.set_steps([{"scene.goto": {"scene": "nowhere"}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(st.args_form.warning_of(["scene"]) == "シーンが見つかりません：nowhere", "s28: missing scene warned: %s" % st.args_form.warning_of(["scene"]))
	st.args_form.set_manual_value(["scene"], scene)
	check(st.args_form.warning_of(["scene"]) == "", "s28: warning cleared when fixed")
	st.set_steps([{"fin.show": {"then": "title"}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(st.args_form.warning_of(["then"]) == "", "s28: fin then title is fine")
	check(ed.form_check(["title_image"], "no_such_image") == "画像が見つかりません：no_such_image" and ed.form_check(["title_image"], "hallroom") == "", "s28: settings check images")
	check(ed.form_check(["title_image"], "hallroom@night") == "", "s28: image variants checked by the base id")
	check(ed.form_check(["opening"], "nowhere") != "" and ed.form_check(["system_scenes", "save"], "res://x.tscn") == "" and ed.form_check(["title"], "nowhere") == "", "s28: scene ids checked")
	# 段階29：プロジェクト全体の ID の確認
	var cd29 := ed.model.load_chapter_data(first, "chapter1")
	cd29["scenes"]["bad_scene"] = {"name": "まちがい", "image": "no_such_bg", "enter": [{"bgm.play": {"id": "no_such_bgm"}}, {"image.show": {"id": "hallroom"}}]}
	ed.model.save_chapter_data(first, "chapter1", cd29)
	var res29 := ed.scan_missing_ids()
	var msgs29 := res29.map(func(r): return r["message"])
	check(msgs29.has("画像が見つかりません：no_such_bg") and msgs29.has("曲が見つかりません：no_such_bgm"), "s29: scan finds missing ids: %s" % str(msgs29))
	check(not msgs29.any(func(m): return String(m).contains("hallroom")), "s29: existing ids are fine")
	var bad_bgm: Dictionary = res29.filter(func(r): return r["message"] == "曲が見つかりません：no_such_bgm")[0]
	check(bad_bgm["scene"] == "bad_scene" and bad_bgm["where"] == "scenes.bad_scene.enter[0].bgm.play.id", "s29: where: %s" % bad_bgm["where"])
	ed.show_check_panel(true)
	await _settle()
	check(ed.check_panel.visible and ed.check_toggle.button_pressed and ed.check_list.item_count == res29.size(), "s29: check panel shown")
	await _shot("10_id_check")
	ed.open_check_result(res29.find(bad_bgm))
	await _settle()
	check(ed.page == AdvScenarioEditor.Page.SCENE and ed.scene_id == "bad_scene", "s29: open the scene from the list")
	ed.show_check_panel(false)
	check(not ed.check_panel.visible and not ed.check_toggle.button_pressed, "s29: check panel hidden")
	# 段階30：Ink の中も確かめる・まとめて直す
	var ink_dir := String(ed.model.scenario(first)["dir"]) + "/ink"
	DirAccess.make_dir_recursive_absolute(ink_dir)
	var ink_path := ink_dir + "/check30.ink"
	var fw := FileAccess.open(ink_path, FileAccess.WRITE)
	fw.store_string("=== start ===\nくらい へや。 # bg:no_bg_ink\nあかるい へや。 # bg:hallroom\n~ call_scene(\"nowhere_x\")\n# {\"image.show\": {\"id\": \"no_bg_ink\"}}\n-> END\n")
	fw.close()
	cd29["scenes"]["bad_scene"] = {"name": "まちがい", "image": "no_such_bg", "enter": [{"image.show": {"id": "no_such_bg"}}]}
	ed.model.save_chapter_data(first, "chapter1", cd29)
	ed.show_check_panel(true)
	await _settle()
	var r30 := ed.check_results
	var ink_hits := r30.filter(func(r): return String(r["file"]).ends_with("check30.ink"))
	check(ink_hits.map(func(r): return r["id"]) == ["no_bg_ink", "nowhere_x", "no_bg_ink"] and ink_hits[0]["where"] == "2 行目", "s30: ink tags checked: %s" % str(ink_hits.map(func(r): return [r["id"], r["where"]])))
	check(not ink_hits.any(func(r): return r["id"] == "hallroom"), "s30: ink existing ids fine")
	# Ink の bg を直す（同じ ID をまとめて：タグと JSON のタグの両方）
	ed.check_list.deselect_all()
	ed.check_list.select(r30.find(ink_hits[0]))
	ed._fill_fix_choices()
	var hi := -1
	for i in ed.fix_pick.item_count:
		if ed.fix_pick.get_item_text(i) == "hallroom":
			hi = i
	ed.fix_pick.select(hi)
	# 段階31：まとめて直す前に確かめる
	check(ed.fix_selected(true) == 2 and ed.fix_confirm.visible and ed.fix_confirm.dialog_text.begins_with("2 か所を書き換えます"), "s31: confirm before fixing: %s" % ed.fix_confirm.dialog_text.left(40))
	check(FileAccess.get_file_as_string(ink_path).contains("no_bg_ink"), "s31: nothing written before confirming")
	ed.fix_confirm.confirmed.emit()
	ed.fix_confirm.hide()
	var ink_txt := FileAccess.get_file_as_string(ink_path)
	check(ink_txt.contains("# bg:hallroom\nあかるい") and ink_txt.contains("\"id\": \"hallroom\"") and not ink_txt.contains("no_bg_ink"), "s30: ink fixed: %s" % ink_txt)
	# JSON の シーンを直す（2か所）
	var json_hits := ed.check_results.filter(func(r): return r["id"] == "no_such_bg")
	check(json_hits.size() == 2, "s30: two json hits")
	# 段階31：種類とファイルで絞り込む
	var total31 := ed.check_results.size()
	ed.set_check_filter("scene", "")
	check(ed.check_list.item_count == ed.check_results.filter(func(r): return r["kind"] == "scene").size() and ed.check_list.item_count < total31, "s31: filter by kind")
	ed.set_check_filter("", json_hits[0]["file"])
	check(ed.check_list.item_count == 2 and ed._check_label.text.contains("全部で"), "s31: filter by file: %s" % ed._check_label.text)
	ed.set_check_filter("image", json_hits[0]["file"])
	check(ed.check_list.item_count == 2, "s31: filter by both")
	ed.check_list.deselect_all()
	ed.check_list.select(1)
	ed._fill_fix_choices()
	check(ed.fix_pick.item_count > 0 and ed.check_results[ed.check_view[1]]["id"] == "no_such_bg", "s31: selection maps through the filter")
	await _shot("12_id_filter")
	# 段階32：書き出す
	var csv_path := "user://s32_check.csv"
	check(ed.export_check(csv_path) == OK, "s32: export csv")
	var csv_bytes := FileAccess.get_file_as_bytes(csv_path)
	var csv_txt := FileAccess.get_file_as_string(csv_path)
	check(csv_bytes[0] == 0xEF and csv_txt.contains("種類,ID,内容,場所,ファイル") and csv_txt.contains("画像,no_such_bg,") and csv_txt.split("\n", false).size() == 3, "s32: csv content: %s" % csv_txt)
	var txt_path := "user://s32_check.txt"
	check(ed.export_check(txt_path) == OK and FileAccess.get_file_as_string(txt_path).begins_with("見つからない ID：2 件"), "s32: export text")
	check(AdvScenarioEditor._csv_cell("a,b") == "\"a,b\"" and AdvScenarioEditor._csv_cell("say \"hi\"") == "\"say \"\"hi\"\"\"", "s32: csv quoting")
	DirAccess.remove_absolute(csv_path)
	DirAccess.remove_absolute(txt_path)
	# 段階33：エディタで書いたら確かめ直す
	var before33 := ed.check_results.size()
	var cd33 := ed.model.load_chapter_data(first, "chapter1")
	cd33["scenes"]["bad_scene"]["bgm"] = "no_such_bgm33"
	ed.model.begin("テスト")
	ed.model.save_chapter_data(first, "chapter1", cd33)
	ed.model.end()
	await _settle()
	check(ed.check_results.size() == before33 + 1 and ed.check_results.any(func(r): return r["id"] == "no_such_bgm33"), "s33: recheck after saving: %d -> %d" % [before33, ed.check_results.size()])
	ed.undo()
	await _settle()
	check(ed.check_results.size() == before33, "s33: recheck after undo")
	# 保存で読み直す（プロジェクト設定 debug.auto_reload）
	ed.auto_reload_toggle.button_pressed = true
	check(bool(ed.model.load_project().get("debug", {}).get("auto_reload", false)), "s33: toggle writes debug.auto_reload")
	ed.undo()
	check(not ed.auto_reload_toggle.button_pressed and not bool(ed.model.load_project().get("debug", {}).get("auto_reload", false)), "s33: undo restores the toggle")
	# 段階34：エディタの外で書き換えたファイルを読み直す
	check(ed.check_external_changes().is_empty(), "s34: nothing changed outside")
	await create_timer(1.1).timeout
	var cpath34: String = ed.model.chapter_path(first, "chapter1") if ed.model.has_method("chapter_path") else ""
	if cpath34 == "":
		for f in ed.model.all_files():
			if String(f).ends_with("chapter1.scenario.json") and String(f).contains(first):
				cpath34 = f
	var raw34 := FileAccess.get_file_as_string(cpath34)
	var fx := FileAccess.open(cpath34, FileAccess.WRITE)
	fx.store_string(raw34.replace("\"no_such_bg\"", "\"no_such_bg34\""))
	fx.close()
	var ext34 := ed.check_external_changes()
	check(ext34.has(cpath34), "s34: outside change found: %s" % str(ext34))
	check(ed.check_results.any(func(r): return r["id"] == "no_such_bg34"), "s34: id check refreshed after outside change")
	check(ed._status.text.begins_with("ほかで書き換えられたファイルを読み直しました"), "s34: status: %s" % ed._status.text)
	await create_timer(1.1).timeout   # 更新時刻は秒の単位なので、間をあける
	fx = FileAccess.open(cpath34, FileAccess.WRITE)
	fx.store_string(raw34)
	fx.close()
	check(not ed.check_external_changes().is_empty() and not ed.check_results.any(func(r): return r["id"] == "no_such_bg34"), "s34: restored outside")
	# シーンの ID で開く（ゲームの「エディタで開く」）
	ed.sid = ""
	check(ed.open_scene_by_id("bad_scene") and ed.page == AdvScenarioEditor.Page.SCENE and ed.scene_id == "bad_scene" and ed.sid == first, "s34: open scene by id")
	check(not ed.open_scene_by_id("no_scene_34"), "s34: unknown scene")
	var dbg_script: Script = load("res://addons/adv80s/editor/adv_debugger_plugin.gd")
	check(dbg_script != null and dbg_script.can_instantiate(), "s34: debugger plugin script loads")
	var dbg = dbg_script.new() if ClassDB.can_instantiate("EditorDebuggerPlugin") else null
	if dbg != null:
		var got34 := [""]
		dbg.open_scene_requested.connect(func(id): got34[0] = id)
		check(dbg._has_capture("adv80s") and dbg._capture("adv80s:open_scene", ["bad_scene"], 0) and got34[0] == "bad_scene", "s34: debugger message")
	ed.sid = first
	ed.cid = "chapter1"
	ed.scene_id = scene
	ed.set_check_filter("", "")
	check(ed.check_list.item_count == total31, "s31: filter cleared")
	ed.check_list.deselect_all()
	ed.check_list.select(ed.check_results.find(json_hits[0]))
	ed._fill_fix_choices()
	for i in ed.fix_pick.item_count:
		if ed.fix_pick.get_item_text(i) == "hallroom":
			ed.fix_pick.select(i)
	var fixed30 := ed.fix_selected(true, false)
	check(fixed30 == 2, "s30: fix same id in json: %d sel=%s pick=%d status=%s" % [fixed30, str(ed.check_list.get_selected_items()), ed.fix_pick.selected, ed._status.text])
	var bs: Dictionary = ed.model.load_chapter_data(first, "chapter1")["scenes"]["bad_scene"]
	check(bs["image"] == "hallroom" and bs["enter"][0]["image.show"]["id"] == "hallroom", "s30: json fixed: %s" % str(bs))
	check(not ed.check_results.any(func(r): return r["id"] == "no_such_bg"), "s30: list refreshed")
	ed.undo()
	check(ed.model.load_chapter_data(first, "chapter1")["scenes"]["bad_scene"]["image"] == "no_such_bg", "s30: fix can be undone")
	ed.redo()
	await _shot("11_id_fix")
	check(AdvScenarioEditor._replace_ink_ref("あ # bg:abc #se:abc", "abc", "xyz") == "あ # bg:xyz #se:xyz" and AdvScenarioEditor._replace_ink_ref("# bg:abcd", "abc", "x") == "# bg:abcd", "s30: ink replace only whole ids")
	DirAccess.remove_absolute(ink_path)
	ed.show_check_panel(false)
	cd29["scenes"].erase("bad_scene")
	ed.model.save_chapter_data(first, "chapter1", cd29)
	# 段階35：このシーンから実行（頼みのファイル）、会話・Ink のノットを開く、大きさでも気づく
	check(ed.run_from_scene("bad_scene", false), "s35: run from scene")
	check(AdvPlayer.take_run_from_request() == "bad_scene", "s35: run-from request read by the game")
	var cd35 := ed.model.load_chapter_data(first, "chapter1")
	var dls: Dictionary = cd35.get("dialogues", {})
	dls["talk35"] = ["こんにちは。", "ふたつめ。"]
	cd35["dialogues"] = dls
	ed.model.save_chapter_data(first, "chapter1", cd35)
	check(ed.open_location("bad_scene", {"dialogue": "talk35"}) and ed.page == AdvScenarioEditor.Page.DIALOGUE and ed.dlg.get("id") == "talk35", "s35: open dialogue: %s" % str(ed.dlg))
	var ink35 := String(ed.model.scenario(first)["dir"]) + "/ink/loc35.ink"
	var fk := FileAccess.open(ink35, FileAccess.WRITE)
	fk.store_string("=== start ===\nはじめ\n-> END\n\n=== k35 ===\nここ\n-> END\n")
	fk.close()
	check(ed.open_location("bad_scene", {"knot": "k35.0"}) and ed.dlg.get("kind") == "ink" and ed._ink_code.get_caret_line() == 4, "s35: open ink knot at line %d" % ed._ink_code.get_caret_line())
	ed._show(AdvScenarioEditor.Page.SCENE)
	# 同じ秒の書き換えも大きさで気づく
	ed.check_external_changes()
	fk = FileAccess.open(ink35, FileAccess.WRITE)
	fk.store_string("=== start ===\nはじめ（なおした）\n-> END\n")
	fk.close()
	check(ed.check_external_changes().has(ink35), "s35: same-second change found by size")
	# 段階36：ひな形、途中から実行、履歴
	AdvScenarioEditor.clear_run_history()
	var pv := AdvScenarioEditor.parse_assign_lines("a = true\nb = 3\n# メモ\nc = 文字\nd = \"s\"\n\nbad")
	check(pv.size() == 4 and pv["a"] == true and int(pv["b"]) == 3 and pv["c"] == "文字" and pv["d"] == "s", "s36: parse preset lines: %s" % str(pv))
	check(AdvScenarioEditor.parse_assign_lines(AdvScenarioEditor.assign_lines_text({"x": true, "y": "z"})) == {"x": true, "y": "z"}, "s36: preset lines round trip")
	check(ed.save_run_preset("終盤", {"f": true, "n": 3}, {"key": 1}) == OK and ed.run_presets().has("終盤"), "s36: save preset")
	check(ed.run_preset_pick.item_count == 2 and ed.selected_preset == "終盤", "s36: preset pick lists it and selects it")
	await _shot("12_run_row")
	ed.model.undo()
	check(not ed.run_presets().has("終盤"), "s36: saving a preset can be undone")
	ed.model.redo()
	ed.select_preset("終盤")
	check(ed.run_from_scene("bad_scene", false), "s36: run with a preset")
	var rq := AdvPlayer.take_run_from()
	check(rq.get("preset") == "終盤" and rq.get("vars", {}).get("f") == true and int(rq.get("items", {}).get("key", 0)) == 1, "s36: request carries the preset values: %s" % str(rq))
	check(ed.open_location("bad_scene", {"dialogue": "talk35"}), "s36: open the dialogue again")
	ed._dlg_steps.tree.get_root().get_child(1).select(0)
	check(ed._dlg_steps.selected_top_index() == 1, "s36: selected step index")
	check(ed.run_from_dialogue(false), "s36: run from the dialogue")
	rq = AdvPlayer.take_run_from()
	check(rq.get("dialogue") == "talk35" and int(rq.get("line", 0)) == 1 and String(rq.get("scene", "")) != "", "s36: dialogue request: %s" % str(rq))
	fk = FileAccess.open(ink35, FileAccess.WRITE)
	fk.store_string("=== start ===\nはじめ\n-> END\n\n=== k35 ===\nここ\n-> END\n")
	fk.close()
	check(ed.open_location("bad_scene", {"knot": "k35"}), "s36: open the knot again")
	ed._ink_code.set_caret_line(5)
	check(ed.run_from_dialogue(false) and AdvPlayer.take_run_from().get("knot") == "k35", "s36: run from the ink knot at the caret")
	check(AdvScenarioEditor.ink_knot_at("=== a ===\nx\n= st\ny\n=== b ===\nz", 3) == "a.st" and AdvScenarioEditor.ink_knot_at("=== a ===\nx\n= st\ny\n=== b ===\nz", 5) == "b"
		and AdvScenarioEditor.ink_knot_at("=== a ===\nx", 0) == "a" and AdvScenarioEditor.ink_knot_at("x\ny", 1) == "", "s36: knot at a line")
	var hist := AdvScenarioEditor.run_history()
	check(hist.size() == 3 and hist[0].get("knot") == "k35" and hist[2].get("scene") == "bad_scene" and hist[2].get("preset") == "終盤" and not hist[2].has("vars"), "s36: history newest first: %s" % str(hist))
	ed.select_preset("")
	check(ed.run_from_scene("bad_scene", false) and AdvScenarioEditor.run_history().size() == 4, "s36: same scene without a preset is a new entry")
	check(ed.run_from_scene("bad_scene", false) and AdvScenarioEditor.run_history().size() == 4, "s36: the same run is not repeated")
	AdvPlayer.take_run_from()
	check(AdvScenarioEditor.history_label({"scene": "h", "dialogue": "t", "line": 2, "preset": "p"}) == "h ／ 会話 t の 3 番目から ／ ひな形 p", "s36: history label")
	ed._fill_history_menu()
	check(ed.run_history_menu.get_popup().item_count == 7, "s36: history menu (4 + separator + favorites + clear)")
	check(ed.run_history_entry(1, false) and AdvPlayer.take_run_from().get("knot") == "k35", "s36: rerun from history")
	check(ed.run_history_entry(3, false) and AdvPlayer.take_run_from().get("vars", {}).get("n") == 3, "s36: rerun keeps its preset (read now)")
	ed.open_preset_dialog("終盤")
	check(ed._preset_name.text == "終盤" and ed._preset_vars.text.contains("f = true"), "s36: preset dialog shows the values")
	ed._preset_dialog.hide()
	check(ed.delete_run_preset("終盤") == OK and not ed.run_presets().has("終盤") and ed.selected_preset == "", "s36: delete preset")
	check(ed.run_history_entry(0, false) and not AdvPlayer.take_run_from().has("vars"), "s36: rerun with a deleted preset runs without it")
	# 段階37：入れ子の手順の道筋、お気に入り、ゲームからのひな形
	st.set_steps(["a", {"if": "x", "then": ["t1", "t2"], "else": ["e1"]}, {"choice": {"prompt": "?", "options": [{"label": "p", "do": ["p1"]}, {"label": "q", "do": ["q1", "q2"]}]}}])
	var r37 := st.tree.get_root()
	var if37 := r37.get_child(1)
	check(st.path_of(r37.get_child(0)) == [0] and st.path_of(if37) == [1], "s37: top-level path")
	check(st.path_of(if37.get_child(0).get_child(1)) == [1, "then", 1] and st.path_of(if37.get_child(1).get_child(0)) == [1, "else", 0], "s37: path inside then / else")
	check(st.path_of(if37.get_child(0)) == [1, "then", 0], "s37: the then row itself starts at its first step")
	var ch37 := r37.get_child(2)
	check(st.path_of(ch37.get_child(1).get_child(1)) == [2, "choice", "options", "1", "do", 1] and st.path_of(ch37.get_child(1)) == [2, "choice", "options", "1", "do", 0], "s37: path inside a choice option: %s" % str(st.path_of(ch37.get_child(1).get_child(1))))
	if37.get_child(0).get_child(1).select(0)
	check(st.selected_path() == [1, "then", 1], "s37: selected path")
	check(AdvPlayer.path_text([1, "then", 1]) == "2 › そうなら › 2" and AdvPlayer.path_text([2, "choice", "options", "1", "do", 0]) == "3 › 選択肢 2 › 1", "s37: path text")
	check(ed.run_from({"scene": "bad_scene", "dialogue": "talk35", "path": [1, "then", 1], "preset": ""}, false), "s37: run from a nested step")
	var rq37 := AdvPlayer.take_run_from()
	check(rq37.get("path") == [1, "then", 1] and not rq37.has("line"), "s37: request carries the path: %s" % str(rq37))
	check(ed.run_from({"scene": "bad_scene", "dialogue": "talk35", "path": [1], "preset": ""}, false) and int(AdvPlayer.take_run_from().get("line", 0)) == 1, "s37: a one-step path is a line")
	check(AdvScenarioEditor.history_label(AdvScenarioEditor.run_history()[1]) == "bad_scene ／ 会話 talk35 の 2 › そうなら › 2 番目から", "s37: history label with a path: %s" % AdvScenarioEditor.history_label(AdvScenarioEditor.run_history()[1]))
	# お気に入り：上に並び、数えない。消しても残る
	var h37 := AdvScenarioEditor.run_history()
	var last37: Dictionary = h37.back()
	check(ed.toggle_favorite(h37.size() - 1) and AdvScenarioEditor._same_run(AdvScenarioEditor.run_history()[0], last37) and AdvScenarioEditor.run_history()[0].get("fav") == true, "s37: favorite goes to the top")
	check(AdvScenarioEditor.history_label(AdvScenarioEditor.run_history()[0]).begins_with("★ "), "s37: favorite label has a star")
	for i37 in 12:
		ed.run_from({"scene": "s%d" % i37, "preset": ""}, false)
	AdvPlayer.take_run_from()
	var h37b := AdvScenarioEditor.run_history()
	check(h37b.size() == AdvScenarioEditor.RUN_HISTORY_MAX + 1 and h37b[0].get("fav") == true and h37b[1].get("scene") == "s11", "s37: favorites are not counted: %d" % h37b.size())
	ed.run_history_entry(0, false)
	check(not AdvPlayer.take_run_from().has("fav") and AdvScenarioEditor.run_history()[0].get("fav") == true, "s37: rerunning a favorite keeps it on top")
	ed._fill_history_menu()
	var sub37 := ed.run_history_menu.get_popup().get_node("Fav") as PopupMenu
	check(sub37.item_count == h37b.size() and sub37.is_item_checked(0) and not sub37.is_item_checked(1), "s37: favorite submenu")
	ed.clear_history_keep_favorites()
	check(AdvScenarioEditor.run_history().size() == 1 and AdvScenarioEditor.run_history()[0].get("fav") == true, "s37: clearing keeps favorites")
	check(not ed.toggle_favorite(0) and AdvScenarioEditor.run_history()[0].get("fav") == null, "s37: unmark favorite")
	# ゲームの「ひな形に」で書かれたものを取り込む
	var gp := FileAccess.open(AdvPlayer.GAME_PRESETS_FILE, FileAccess.WRITE)
	gp.store_string(JSON.stringify([{"name": "ゲーム1", "vars": {"g": 2}, "items": {"key": 1.0}, "time": 0}, {"name": "", "vars": {}}, {"name": "ゲーム2", "vars": {"h": true}}]))
	gp.close()
	var got37 := ed.import_game_presets()
	check(got37 == ["ゲーム1", "ゲーム2"] and ed.run_presets()["ゲーム1"]["items"]["key"] is int and ed.selected_preset == "ゲーム2" and not FileAccess.file_exists(AdvPlayer.GAME_PRESETS_FILE), "s37: import presets from the game: %s" % str(got37))
	ed.model.undo()
	check(not ed.run_presets().has("ゲーム1"), "s37: importing can be undone")
	check(ed.import_game_presets().is_empty(), "s37: nothing to import")
	# 段階38：ひな形を比べる、設定を先に
	var d38 := AdvScenarioEditor.diff_presets({"vars": {"a": 1, "b": true, "c": "x"}, "items": {"key": 1}}, {"vars": {"a": 1.0, "b": false, "d": 4}, "items": {"key": 2, "map": 1}})
	check(d38.size() == 5 and d38[0]["key"] == "b" and d38[1]["key"] == "c" and d38[1]["b"] == null and d38[2]["key"] == "d" and d38[3]["kind"] == "items" and d38[3]["key"] == "key", "s38: diff presets: %s" % str(d38))
	check(AdvScenarioEditor.diff_presets({"vars": {"n": 3}}, {"vars": {"n": 3.0}}).is_empty() and AdvScenarioEditor.diff_text({}, {}, "A", "B").contains("違うところはありません"), "s38: same presets")
	check(AdvScenarioEditor.diff_text({"vars": {"a": 1}}, {}, "A", "B").contains("変数 a：1 ／ なし"), "s38: diff text")
	ed.save_run_preset("前半", {"f": false, "n": 1}, {"key": 1})
	ed.save_run_preset("後半", {"f": true, "n": 1}, {"key": 1, "map": 1})
	ed.open_preset_dialog("前半")
	check(ed._preset_cmp.item_count == 3 and ed._preset_diff.text == "", "s38: compare list excludes itself")
	ed.compare_preset_with("後半")
	check(ed._preset_diff.text.contains("変数 f：false ／ true") and ed._preset_diff.text.contains("持ち物 map：なし ／ 1") and not ed._preset_diff.text.contains("変数 n"), "s38: compare in the dialog: %s" % ed._preset_diff.text)
	ed._preset_vars.text = "f = true\nn = 1"
	ed._preset_vars.text_changed.emit()
	check(not ed._preset_diff.text.contains("変数 f") and ed._preset_diff.text.contains("map"), "s38: diff follows the edits")
	await _shot("13_preset_compare")
	ed._preset_dialog.hide()
	ed.delete_run_preset("前半")
	ed.delete_run_preset("後半")
	check(ed.open_location("bad_scene", {"dialogue": "talk35"}), "s38: open the dialogue")
	ed._pre_sets_check.button_pressed = true
	check(ed.run_pre_sets and ed.run_from_dialogue(false), "s38: run with pre-sets")
	var rq38 := AdvPlayer.take_run_from()
	check(rq38.get("pre_sets") == true, "s38: request carries pre_sets: %s" % str(rq38))
	check(AdvScenarioEditor.history_label(AdvScenarioEditor.run_history()[0]).contains("（設定を先に）"), "s38: history label shows pre-sets")
	ed._pre_sets_check.button_pressed = false
	var n38 := AdvScenarioEditor.run_history().size()
	ed.run_from_dialogue(false)
	AdvPlayer.take_run_from()
	check(AdvScenarioEditor.run_history().size() == n38 + 1, "s38: with and without pre-sets are different runs")
	# 段階39：条件も、複製
	check(AdvScenarioEditor.pre_sets_mode(true) == "plain" and AdvScenarioEditor.pre_sets_mode(false) == "" and AdvScenarioEditor.pre_sets_mode("cond") == "cond" and AdvScenarioEditor.pre_sets_mode(null) == "", "s39: pre-sets mode")
	ed._pre_sets_check.button_pressed = false
	check(ed._pre_cond_check.disabled, "s39: 条件も is off without 設定を先に")
	ed._pre_sets_check.button_pressed = true
	ed._pre_cond_check.button_pressed = true
	check(not ed._pre_cond_check.disabled and ed.run_from_dialogue(false) and AdvPlayer.take_run_from().get("pre_sets") == "cond", "s39: run with conditional pre-sets")
	check(AdvScenarioEditor.history_label(AdvScenarioEditor.run_history()[0]).contains("（設定を先に・条件も）"), "s39: history label with conditions")
	ed._pre_cond_check.button_pressed = false
	ed.run_from_dialogue(false)
	var h39 := AdvScenarioEditor.run_history()
	check(AdvPlayer.take_run_from().get("pre_sets") == true and h39[0].get("pre_sets") == true and h39[1].get("pre_sets") == "cond", "s39: plain and conditional are different runs: %s" % str(h39.slice(0, 2)))
	ed._pre_sets_check.button_pressed = false
	ed.save_run_preset("元", {"f": true}, {"key": 1})
	check(ed.duplicate_run_preset("元") == "元 のコピー" and ed.duplicate_run_preset("元") == "元 のコピー 2" and AdvScenarioEditor.diff_presets(ed.run_presets()["元 のコピー"], ed.run_presets()["元"]).is_empty(), "s39: duplicate preset")
	check(ed.duplicate_run_preset("ない") == "", "s39: duplicate a missing preset")
	ed.open_preset_dialog("元")
	ed._preset_vars.text = "f = false"
	check(ed.duplicate_preset_in_dialog() == "元 のコピー 3" and ed._preset_name.text == "元 のコピー 3" and ed.run_presets()["元 のコピー 3"]["vars"]["f"] == false and ed.run_presets()["元"]["vars"]["f"] == true, "s39: duplicate in the dialog saves what is written")
	check(ed._preset_diff.text.contains("変数 f：false ／ true"), "s39: the copy is compared with the original: %s" % ed._preset_diff.text)
	ed._preset_dialog.hide()
	# 段階40：書き出し・読み込み
	var px := "user://s40_presets.json"
	check(ed.export_run_presets(px) == OK, "s40: export presets")
	var xd = AdvJson.load_file(px, [])
	check(xd is Dictionary and xd.get("format") == "adv80s_run_presets" and xd["presets"].size() == 4 and xd["presets"]["元"]["vars"]["f"] == true, "s40: export file: %s" % str(xd).left(200))
	check(ed.import_run_presets(px).is_empty(), "s40: importing the same presets adds nothing")
	ed.delete_run_preset("元 のコピー")
	ed.save_run_preset("元", {"f": "changed"}, {})
	var got40 := ed.import_run_presets(px)
	check(got40 == ["元（読み込み）", "元 のコピー"] and ed.run_presets()["元（読み込み）"]["vars"]["f"] == true and ed.run_presets()["元"]["vars"]["f"] == "changed", "s40: import adds missing and renames different: %s" % str(got40))
	check(ed.import_run_presets(px).is_empty(), "s40: importing again adds nothing")
	ed.model.undo()
	check(not ed.run_presets().has("元（読み込み）") and not ed.run_presets().has("元 のコピー"), "s40: import can be undone")
	ed.model.redo()
	var fx40 := FileAccess.open(px, FileAccess.WRITE)
	fx40.store_string(JSON.stringify({"手書き": {"vars": {"h": 1}, "items": {"k": 2.0}}, "": {}, "だめ": 3}))
	fx40.close()
	check(ed.import_run_presets(px) == ["手書き"] and ed.run_presets()["手書き"]["items"]["k"] is int, "s40: import a plain presets dictionary")
	fx40 = FileAccess.open(px, FileAccess.WRITE)
	fx40.store_string("[1, 2]")
	fx40.close()
	check(ed.import_run_presets(px).is_empty() and ed.import_run_presets("user://none40.json").is_empty(), "s40: unreadable files import nothing")
	# 段階41：選んだものだけ書き出す
	ed.open_export_pick()
	await process_frame
	await process_frame
	check(ed._export_checks.size() == ed.run_presets().size() and ed._export_checks.values().all(func(c): return c.button_pressed), "s41: export pick lists all, all marked")
	await _shot("14_export_pick")
	check(ed.confirm_export_pick() and ed.export_names.is_empty(), "s41: all marked = export all")
	ed.set_export_all(false)
	check(not ed.confirm_export_pick(), "s41: nothing marked = no export")
	ed.set_export_check("元", true)
	ed.set_export_check("手書き", true)
	check(ed.confirm_export_pick() and ed.export_names.size() == 2 and ed.export_names.has("元"), "s41: picked names: %s" % str(ed.export_names))
	check(ed.export_run_presets(px, ed.export_names) == OK and AdvJson.load_file(px, [])["presets"].keys().size() == 2, "s41: export only the picked ones")
	ed._preset_export_pick.hide()
	# 段階42：読み込むものを選ぶ（同じものは印なしで押せない）
	var fx42 := FileAccess.open(px, FileAccess.WRITE)
	fx42.store_string(JSON.stringify({"format": "adv80s_run_presets", "version": 1, "presets": {"元": {"vars": {"f": 99}}, "新しい": {"vars": {"z": 1}}, "手書き": ed.run_presets()["手書き"], "空": {}}}))
	fx42.close()
	check(AdvScenarioEditor.import_status(ed.run_presets(), "新しい", {}) == "new" and AdvScenarioEditor.import_status(ed.run_presets(), "手書き", ed.run_presets()["手書き"]) == "same"
		and AdvScenarioEditor.import_status(ed.run_presets(), "元", {"vars": {"f": 99}}) == "rename", "s42: import status")
	check(ed.open_import_pick(px), "s42: open import pick")
	await process_frame
	await process_frame
	var ic42: Dictionary = ed._import_checks
	check(ic42.size() == 4 and (ic42["手書き"] as CheckBox).disabled and not (ic42["手書き"] as CheckBox).button_pressed and (ic42["新しい"] as CheckBox).button_pressed
		and (ic42["元"] as CheckBox).text.contains("「元（読み込み 2）」"), "s42: pick shows what will happen: %s" % (ic42["元"] as CheckBox).text)
	await _shot("15_import_pick")
	ed.set_import_check("新しい", false)
	ed.set_import_check("空", false)
	ed.set_import_check("手書き", true)
	var got42 := ed.confirm_import_pick()
	check(got42 == ["元（読み込み 2）"] and not ed.run_presets().has("新しい") and ed.run_presets()["元（読み込み 2）"]["vars"]["f"] == 99, "s42: import only the picked ones: %s" % str(got42))
	ed.open_import_pick(px)
	ed.set_import_all(false)
	check(ed.confirm_import_pick().is_empty() and ed._preset_msg.text.contains("選んで"), "s42: nothing picked")
	ed.set_import_all(true)
	check(ed.confirm_import_pick() == ["新しい", "空"] and not ed.run_presets()["空"].has("vars") and not ed.run_presets()["空"].has("items"), "s42: all = the rest (same ones stay off)")
	# 段階43：中身が違うものを上書きする
	check(AdvScenarioEditor.import_status(ed.run_presets(), "元", {"vars": {"f": 99}}, true) == "overwrite" and AdvScenarioEditor.import_status(ed.run_presets(), "元", {"vars": {"f": 99}}) == "same", "s43: overwrite compares only the same name")
	ed.open_import_pick(px)
	check((ed._import_checks["元"] as CheckBox).disabled, "s43: without overwrite, an imported copy counts as same")
	ed.set_import_overwrite(true)
	check(not (ed._import_checks["元"] as CheckBox).disabled and (ed._import_checks["元"] as CheckBox).button_pressed and (ed._import_checks["元"] as CheckBox).text.contains("上書き")
		and (ed._import_checks["新しい"] as CheckBox).disabled and ed._import_overwrite_check.button_pressed, "s43: overwrite marks the different one")
	# 段階44：上書きされる中身を、いまの中身と比べて見せる
	var pv44 := ed.import_overwrite_preview()
	check(pv44.contains("元[/b] を上書き") and pv44.contains("変数 f：\"changed\" → 99") and not pv44.contains("99.0") and ed._import_preview.visible, "s44: overwrite preview: %s" % pv44)
	ed.set_import_check("元", false)
	check(ed.import_overwrite_preview() == "" and not ed._import_preview.visible, "s44: unmarked = no preview")
	ed.set_import_check("元", true)
	await _shot("16_import_overwrite")
	var got43 := ed.confirm_import_pick()
	check(got43 == ["元"] and ed.run_presets()["元"]["vars"]["f"] == 99, "s43: overwritten: %s" % str(got43))
	ed.model.undo()
	check(ed.run_presets()["元"]["vars"]["f"] == "changed", "s43: overwrite can be undone")
	ed.set_import_overwrite(false)
	check(not ed._import_overwrite_check.button_pressed and (ed._import_checks["元"] as CheckBox).text.contains("同じもの"), "s43: turning overwrite off relabels")
	ed._preset_import_pick.hide()
	check(not ed.open_import_pick("user://none42.json"), "s42: unreadable file")
	# 段階45：組と絞り込み
	var lay45 := AdvScenarioEditor.preset_pick_layout({"b": {}, "a": {"group": "g2"}, "c": {"group": "g1"}, "d": {"group": "g1"}})
	check(lay45 == [["", ["b"]], ["g1", ["c", "d"]], ["g2", ["a"]]], "s45: pick layout: %s" % str(lay45))
	check(AdvScenarioEditor.preset_pick_layout({"b": {}, "a": {"group": "g2"}, "c": {"group": "G1"}}, "g1") == [["G1", ["c"]]]
		and AdvScenarioEditor.preset_pick_layout({"b": {}, "a": {"group": "g2"}}, "zz", "b") == [["", ["b"]]], "s45: filter by name or group, keep the selected")
	ed.save_run_preset("組A1", {"x": 1}, {}, "組A")
	ed.save_run_preset("組A2", {"x": 2}, {}, "組A")
	ed.select_preset("組A2")
	AdvScenarioEditor._save_folded([])
	ed._fill_preset_pick()
	var sep45 := 0
	for i45 in ed.run_preset_pick.item_count:
		if String(ed.run_preset_pick.get_item_metadata(i45)).begins_with("#group:"):
			sep45 += 1
	check(sep45 >= 1 and ed.run_preset_pick.get_item_metadata(ed.run_preset_pick.selected) == "組A2" and ed.run_presets()["組A1"]["group"] == "組A", "s45: groups in the run pick")
	ed.set_preset_filter("組a")
	check(ed.run_preset_pick.item_count == 4 and ed._preset_filter_edit.text == "組a", "s45: filter the run pick (none + header + 2): %d" % ed.run_preset_pick.item_count)
	ed.set_preset_filter("")
	ed.run_preset_pick.show_popup()
	await _shot("17_run_pick_groups")
	ed.run_preset_pick.get_popup().hide()
	ed.open_preset_dialog("組A1")
	check(ed._preset_group.text == "組A", "s45: dialog shows the group")
	ed._preset_group.text = "組B"
	ed._confirm_preset()
	check(ed.run_presets()["組A1"]["group"] == "組B", "s45: change the group in the dialog")
	check(ed.duplicate_run_preset("組A1") == "組A1 のコピー" and ed.run_presets()["組A1 のコピー"]["group"] == "組B", "s45: copy keeps the group")
	ed._preset_dialog.hide()
	var gp45 := FileAccess.open(AdvPlayer.GAME_PRESETS_FILE, FileAccess.WRITE)
	gp45.store_string(JSON.stringify([{"name": "続け", "vars": {"m": 1}, "group": "続け"}, {"name": "続け 2", "vars": {"m": 2}, "group": "続け"}]))
	gp45.close()
	check(ed.import_game_presets() == ["続け", "続け 2"] and ed.run_presets()["続け 2"]["group"] == "続け", "s45: game presets keep their group")
	check(ed.export_run_presets(px, ["続け"]) == OK and AdvScenarioEditor.read_preset_file(px)["続け"]["group"] == "続け", "s45: export/read keep the group")
	# 段階46：組をたたむ、組の名前を変える・書き出す・消す
	check(ed.run_preset_groups() == ["組A", "組B", "続け"], "s46: groups: %s" % str(ed.run_preset_groups()))
	ed.select_preset("組A2")
	check(ed.set_group_folded("続け", true) and AdvScenarioEditor.folded_groups() == ["続け"], "s46: fold a group")
	var txt46: Array = []
	for i46 in ed.run_preset_pick.item_count:
		txt46.append(ed.run_preset_pick.get_item_text(i46))
	check(txt46.has("▸ 組：続け（2）") and not txt46.has("　続け 2") and txt46.has("▾ 組：組A"), "s46: folded group shows only its header: %s" % str(txt46))
	ed.set_group_folded("組A", true)
	var hasA2 := false
	for i46 in ed.run_preset_pick.item_count:
		if ed.run_preset_pick.get_item_metadata(i46) == "組A2":
			hasA2 = true
	check(hasA2 and ed.run_preset_pick.get_item_metadata(ed.run_preset_pick.selected) == "組A2", "s46: the selected preset stays visible in a folded group")
	var hi46 := -1
	for i46 in ed.run_preset_pick.item_count:
		if ed.run_preset_pick.get_item_metadata(i46) == "#group:続け":
			hi46 = i46
	ed._on_preset_picked(hi46)
	check(not AdvScenarioEditor.folded_groups().has("続け") and ed.selected_preset == "組A2", "s46: picking a header opens it and keeps the selection")
	check(ed.rename_preset_group("続け", "続き") == 2 and ed.run_presets()["続け 2"]["group"] == "続き" and ed.run_preset_groups().has("続き"), "s46: rename a group")
	check(ed.rename_preset_group("組A", "組Z") == 1 and AdvScenarioEditor.folded_groups().has("組Z") and not AdvScenarioEditor.folded_groups().has("組A"), "s46: renaming keeps it folded")
	ed.model.undo()
	check(ed.run_presets()["組A2"].get("group", "") == "組A", "s46: rename can be undone")
	ed.model.redo()
	check(ed.export_group("組B", px) == OK and AdvScenarioEditor.read_preset_file(px).keys().size() == ed.preset_names_in_group("組B").size(), "s46: export a group")
	ed.open_group_dialog("続き")
	await process_frame
	check(ed.picked_group() == "続き" and ed._group_info.text.contains("続け 2"), "s46: group dialog")
	await _shot("18_group_dialog")
	ed._group_dialog.hide()
	var nB := ed.preset_names_in_group("組B").size()
	check(ed.delete_preset_group("組B") == nB and ed.preset_names_in_group("組B").is_empty(), "s46: delete a group")
	ed.model.undo()
	check(ed.preset_names_in_group("組B").size() == nB, "s46: delete can be undone")
	check(ed.rename_preset_group("続き", "") == 2 and not ed.run_presets()["続け"].has("group"), "s46: empty name = ungroup")
	AdvScenarioEditor._save_folded([])
	# 段階47：組の並び順、組への出し入れ
	check(AdvScenarioEditor.preset_pick_layout({"a": {"group": "x"}, "b": {"group": "y"}, "c": {}}, "", "", ["y", "nope"]) == [["", ["c"]], ["y", ["b"]], ["x", ["a"]]], "s47: layout follows the order")
	check(ed.preset_group_order() == ["組B", "組Z"], "s47: default order by name: %s" % str(ed.preset_group_order()))
	check(ed.move_preset_group("組Z", -1) and ed.preset_group_order() == ["組Z", "組B"] and not ed.move_preset_group("組Z", -1), "s47: move a group up")
	var hz := -1
	var hb := -1
	for i47 in ed.run_preset_pick.item_count:
		var m47 := String(ed.run_preset_pick.get_item_metadata(i47))
		if m47 == "#group:組Z":
			hz = i47
		elif m47 == "#group:組B":
			hb = i47
	check(hz >= 0 and hz < hb, "s47: run pick follows the order")
	ed.model.undo()
	check(ed.preset_group_order() == ["組B", "組Z"], "s47: order can be undone")
	ed.model.redo()
	check(ed.rename_preset_group("組Z", "組Y") == 1 and ed.preset_group_order()[0] == "組Y", "s47: rename keeps the place in the order")
	ed.open_group_dialog("組B")
	await process_frame
	var inB: Array = ed.preset_names_in_group("組B")
	check(ed._group_member_checks.size() == ed.run_presets().size() and (ed._group_member_checks[inB[0]] as CheckBox).button_pressed and not (ed._group_member_checks["続け"] as CheckBox).button_pressed
		and (ed._group_member_checks["組A2"] as CheckBox).text.contains("（組：組Y）"), "s47: member list marks the group's presets")
	await _shot("19_group_members")
	ed.set_group_member_check("続け", true)
	ed.set_group_member_check("組A2", true)
	ed.set_group_member_check(inB[0], false)
	check(ed.confirm_group_members() == 3 and ed.run_presets()["続け"]["group"] == "組B" and ed.run_presets()["組A2"]["group"] == "組B" and not ed.run_presets()[inB[0]].has("group"), "s47: move presets in and out")
	check(not ed.preset_group_order().has("組Y"), "s47: an emptied group leaves the order")
	ed.model.undo()
	check(ed.run_presets()["組A2"]["group"] == "組Y" and not ed.run_presets()["続け"].has("group"), "s47: member change can be undone")
	ed._group_dialog.hide()
	# 段階48：最後に使った日時、組の窓から実行、ゲームからお知らせの設定
	var now48 := Time.get_unix_time_from_system()
	check(AdvScenarioEditor.used_label(0) == "未使用" and AdvScenarioEditor.used_label(now48, now48) == "今日" and AdvScenarioEditor.used_label(now48 - 86400 * 3, now48) == "3日前"
		and AdvScenarioEditor.used_label(now48 - 86400 * 20, now48) == "2週前" and AdvScenarioEditor.used_label(now48 - 86400 * 95, now48) == "3か月前", "s48: used label")
	AdvScenarioEditor._save_folded(["x48"])
	AdvScenarioEditor._mark_preset_used("組A2", now48 - 86400 * 3)
	check(AdvScenarioEditor.folded_groups() == ["x48"] and absf(AdvScenarioEditor.preset_last_used("組A2") - (now48 - 86400 * 3)) < 1.0 and AdvScenarioEditor.preset_last_used("ない") == 0.0, "s48: last used kept beside folded groups")
	AdvScenarioEditor._save_folded([])
	ed._fill_preset_pick()
	var t48 := ""
	var tip48 := ""
	var un48 := false
	for i48 in ed.run_preset_pick.item_count:
		if ed.run_preset_pick.get_item_metadata(i48) == "組A2":
			t48 = ed.run_preset_pick.get_item_text(i48)
			tip48 = ed.run_preset_pick.get_item_tooltip(i48)
		elif ed.run_preset_pick.get_item_text(i48).contains("〔未使用〕"):
			un48 = true
	check(t48.contains("〔3日前〕") and tip48.begins_with("最後に使った日時：") and un48, "s48: run pick shows last used: %s / %s" % [t48, tip48])
	check(ed.run_with_preset("組A2", false) and AdvPlayer.take_run_from().get("preset") == "組A2" and ed.selected_preset == "組A2" and AdvScenarioEditor.used_label(AdvScenarioEditor.preset_last_used("組A2")) == "今日", "s48: run with a preset marks it used")
	check(not ed.run_with_preset("ない", false), "s48: missing preset")
	ed.open_group_dialog("組Y")
	await process_frame
	check(ed._group_run_pick.item_count == 1 and ed._group_run_pick.get_item_metadata(0) == "組A2" and ed._group_run_pick.get_item_text(0).contains("〔今日〕"), "s48: group dialog run pick")
	await _shot("20_group_run")
	check(ed.run_group_pick(false) and AdvPlayer.take_run_from().get("preset") == "組A2" and not ed._group_dialog.visible, "s48: run from the group dialog")
	var gs48 := FileAccess.open(AdvPlayer.GAME_SETTINGS_FILE, FileAccess.WRITE)
	gs48.store_string(JSON.stringify({"notices": {"reload": false, "bogus": true, "editor": true}}))
	gs48.close()
	var got48 := ed.import_game_settings()
	check(got48 == {"notices": {"reload": false, "editor": true}} and ed.model.load_project()["debug"]["notices"]["reload"] == false and not FileAccess.file_exists(AdvPlayer.GAME_SETTINGS_FILE), "s48: import notice settings from the game: %s" % str(got48))
	ed.model.undo()
	check(not ed.model.load_project().get("debug", {}).has("notices"), "s48: notice settings import can be undone")
	check(ed.import_game_settings().is_empty(), "s48: nothing to import")
	# 段階49：使った順、片付け、ゲームからお知らせの見た目
	check(AdvScenarioEditor.preset_pick_layout({"a": {}, "b": {}, "c": {}}, "", "", [], {"b": 100.0, "c": 50.0}) == [["", ["b", "c", "a"]]], "s49: layout by last used")
	AdvScenarioEditor._mark_preset_used("手書き", now48 - 60)
	AdvScenarioEditor._mark_preset_used("空", now48 - 120)
	AdvScenarioEditor._mark_preset_used("元", now48 - 86400 * 40)
	AdvScenarioEditor._mark_preset_used("新しい", now48 - 86400 * 5)
	ed.set_run_sort_by_used(true)
	check(AdvScenarioEditor.run_sort_by_used() and ed._sort_pick.selected == 1 and ed.run_preset_pick.get_item_metadata(1) == "手書き" and ed.run_preset_pick.get_item_metadata(2) == "空", "s49: run pick sorted by last used: %s" % ed.run_preset_pick.get_item_text(1))
	ed.set_run_sort_by_used(false)
	check(not AdvScenarioEditor.run_sort_by_used() and ed.run_preset_pick.get_item_metadata(1) == "元", "s49: back to name order")
	var st49 := ed.stale_presets(30, false, now48)
	check(st49.has("元") and not st49.has("新しい") and not st49.has("元 のコピー"), "s49: stale presets: %s" % str(st49))
	check(ed.stale_presets(30, true, now48).has("元 のコピー") and not ed.stale_presets(30, true, now48).has("手書き"), "s49: stale with unused")
	ed.open_tidy_dialog()
	await process_frame
	check(ed._tidy_checks.has("元") and (ed._tidy_checks["元"] as CheckBox).button_pressed and not ed._tidy_checks.has("元 のコピー"), "s49: tidy dialog lists stale presets")
	ed._tidy_unused.button_pressed = true
	await process_frame
	check(ed._tidy_checks.has("元 のコピー") and (ed._tidy_checks["元"] as CheckBox).text.contains("〔"), "s49: tidy includes unused when asked")
	await _shot("21_tidy")
	for n49 in ed._tidy_checks.keys():
		ed.set_tidy_check(n49, n49 == "元" or n49 == "元 のコピー")
	ed._tidy_group.text = "古い"
	check(ed.tidy_to_group() == 2 and ed.run_presets()["元"]["group"] == "古い" and ed.run_presets()["元 のコピー"]["group"] == "古い", "s49: move stale presets to a group")
	ed.model.undo()
	check(not ed.run_presets()["元"].has("group"), "s49: group move can be undone")
	for n49 in ed._tidy_checks.keys():
		ed.set_tidy_check(n49, n49 == "元")
	check(ed.tidy_delete() == 1 and not ed.run_presets().has("元"), "s49: delete stale presets")
	ed.model.undo()
	check(ed.run_presets().has("元"), "s49: delete can be undone")
	ed._tidy_dialog.hide()
	var gs49 := FileAccess.open(AdvPlayer.GAME_SETTINGS_FILE, FileAccess.WRITE)
	gs49.store_string(JSON.stringify({"notice_style": {"fg": 10.0, "position": "bottom", "bad": 1}, "notices": {"reload": true}}))
	gs49.close()
	var got49 := ed.import_game_settings()
	check(got49.get("notice_style") == {"fg": 10, "position": "bottom"} and got49.get("notices") == {"reload": true} and ed.model.load_project()["debug"]["notice_style"]["fg"] is int, "s49: import notice style from the game: %s" % str(got49))
	ed.model.undo()
	check(not ed.model.load_project().get("debug", {}).has("notice_style"), "s49: style import can be undone")
	# 段階50：作った順、片付けを組で絞る、ゲームからふつうのお知らせの見た目
	ed.save_run_preset("作50", {"q": 1}, {})
	var c50 := ed.preset_created("作50")
	check(c50 > 0.0 and absf(c50 - Time.get_unix_time_from_system()) < 5.0, "s50: created time is stored")
	ed.save_run_preset("作50", {"q": 2}, {})
	check(ed.preset_created("作50") == c50, "s50: rewriting keeps the created time")
	var pj50 := ed.model.load_project()
	pj50["debug"]["run_presets"]["作50"]["created"] = 4000000000.0   # 先の時刻にして、作った順のいちばん上へ
	ed.model.write_json(ed.model.project_path, pj50)
	ed.set_run_sort("created")
	check(AdvScenarioEditor.run_sort() == "created" and ed._sort_pick.selected == 2 and ed.run_preset_pick.get_item_metadata(1) == "作50", "s50: created order: %s" % ed.run_preset_pick.get_item_text(1))
	check(ed.run_preset_pick.get_item_tooltip(1).contains("作った日時："), "s50: tooltip shows the created time")
	ed.set_run_sort("name")
	check(AdvScenarioEditor.run_sort() == "name" and not AdvScenarioEditor.run_sort_by_used(), "s50: back to name order")
	ed.delete_run_preset("作50")
	ed.open_tidy_dialog("")
	await process_frame
	check(ed.tidy_group() == "", "s50: tidy group pick")
	ed._tidy_unused.button_pressed = true
	await process_frame
	check(ed._tidy_checks.has("元 のコピー") and not ed._tidy_checks.has("組A1"), "s50: tidy only ungrouped: %s" % str(ed._tidy_checks.keys()))
	ed.set_tidy_group("組B")
	await process_frame
	check(ed._tidy_checks.has("組A1") and not ed._tidy_checks.has("元 のコピー"), "s50: tidy only one group")
	ed.set_tidy_group("*")
	await process_frame
	check(ed._tidy_checks.has("組A1") and ed._tidy_checks.has("元 のコピー"), "s50: tidy all groups")
	await _shot("22_tidy_group")
	ed._tidy_dialog.hide()
	check(ed.stale_presets(30, true, -1.0, "組B").all(func(n): return AdvScenarioEditor.preset_group(ed.run_presets()[n]) == "組B"), "s50: stale presets by group")
	var gs50 := FileAccess.open(AdvPlayer.GAME_SETTINGS_FILE, FileAccess.WRITE)
	gs50.store_string(JSON.stringify({"game_notice_style": {"fg": 3.0, "overflow": "fade", "bad": 1}}))
	gs50.close()
	var hadDebug50 := ed.model.load_project().has("debug")
	var got50 := ed.import_game_settings()
	check(got50 == {"game_notice_style": {"fg": 3, "overflow": "fade"}} and ed.model.load_project()["notice_style"]["fg"] is int and ed.model.load_project().has("debug") == hadDebug50, "s50: import the game notice style: %s" % str(got50))
	ed.model.undo()
	check(ed.model.load_project().get("notice_style", {}).get("overflow", "") != "fade", "s50: game style import can be undone")
	# 段階51：ひな形の窓に日時、片付けの前に中身をのぞく
	var dt51 := ed.preset_dates_text("組A2")
	check(dt51.begins_with("作った日時：") and dt51.contains("最後に使った日時：") and dt51.contains("（今日）") and ed.preset_dates_text("") == "（新しいひな形）", "s51: dates text: %s" % dt51)
	ed.open_preset_dialog("組A2")
	check(ed._preset_dates.text == dt51, "s51: preset dialog shows the dates")
	await _shot("23_preset_dates")
	ed._preset_dialog.hide()
	check(ed.preset_summary("元").contains("f = ") and ed.preset_summary("空") == "（中身なし）" and ed.preset_summary("ない") == "（中身なし）", "s51: preset summary: %s" % ed.preset_summary("元"))
	ed.save_run_preset("中身51", {"a": 1, "b": "x"}, {"key": 2})
	check(ed.preset_summary("中身51") == "a = 1、b = \"x\" ／ 持ち物 key × 2", "s51: summary format: %s" % ed.preset_summary("中身51"))
	ed.delete_run_preset("中身51")
	ed.open_tidy_dialog("*")
	ed._tidy_unused.button_pressed = true
	await process_frame
	check(ed._tidy_preview.text.contains("[b]元[/b]：") and (ed._tidy_checks["元"] as CheckBox).tooltip_text.ends_with("\n" + ed.preset_summary("元")), "s51: tidy preview lists the marked presets")
	ed.set_tidy_check("元", false)
	check(not ed._tidy_preview.text.contains("[b]元[/b]") and ed._tidy_preview.text.contains("元 のコピー"), "s51: preview follows the marks")
	await _shot("24_tidy_preview")
	for n51 in ed._tidy_checks.keys():
		ed.set_tidy_check(n51, false)
	check(ed.tidy_preview_text() == "", "s51: nothing marked = empty preview")
	# 段階52：二つを比べる
	ed._tidy_compare.button_pressed = true
	ed.set_tidy_check("元", true)
	check(ed._tidy_preview.text == "印を二つ付けてください（いま 1）", "s52: compare needs two")
	ed.set_tidy_check("元 のコピー 3", true)
	check(ed._tidy_preview.text.contains("の違い") and ed._tidy_preview.text.contains("変数 f"), "s52: compare two presets: %s" % ed._tidy_preview.text)
	await _shot("25_tidy_compare")
	# 段階58：片付けの比べで写す
	check(ed._tidy_preview.text.contains("[url=tidy:L:vars:f]← 左へ[/url]") and ed._tidy_preview.text.contains("[url=tidy:R:vars:f]右へ →[/url]"), "s58: tidy diff links: %s" % ed._tidy_preview.text)
	await _shot("38_tidy_copy")
	var va58 = ed.run_presets()["元"]["vars"]["f"]
	var vb58 = ed.run_presets()["元 のコピー 3"]["vars"]["f"]
	var sel59: Array = ed.tidy_selection()
	ed._on_tidy_preview_meta("tidy:R:vars:f")
	# 段階59：開いたまま元に戻すと並べ直す
	ed.undo()
	check(ed._tidy_preview.text.contains("変数 f") and ed.tidy_selection() == sel59, "s59: tidy follows undo, marks kept: %s" % ed._tidy_preview.text)
	ed.redo()
	check(not ed._tidy_preview.text.contains("変数 f") and ed.tidy_selection() == sel59, "s59: tidy follows redo")
	check(str(ed.run_presets()["元 のコピー 3"]["vars"]["f"]) == str(va58) and not ed._tidy_preview.text.contains("変数 f"), "s58: copy left to right: %s" % ed._tidy_preview.text)
	check(not ed.tidy_copy_value("元", "元 のコピー 3", "vars", "f") and not ed.tidy_copy_value("元", "元", "vars", "f") and not ed.tidy_copy_value("元", "元 のコピー 3", "vars", "ない58") and not ed.tidy_copy_value("元", "ない58", "vars", "f"), "s58: nothing to copy")
	ed.model.undo()
	ed._update_tidy_preview()
	check(str(ed.run_presets()["元 のコピー 3"]["vars"]["f"]) == str(vb58) and ed._tidy_preview.text.contains("の違い"), "s58: undo the copy")
	ed._on_tidy_preview_meta("tidy:L:vars:f")
	check(str(ed.run_presets()["元"]["vars"]["f"]) == str(vb58), "s58: copy right to left")
	ed.model.undo()
	check(str(ed.run_presets()["元"]["vars"]["f"]) == str(va58), "s58: undo again")
	ed.save_run_preset("片58", {"a": 1}, {"key": 2})
	check(ed.tidy_copy_value("元", "片58", "vars", "a") and not ed.run_presets()["片58"].has("vars") and ed.tidy_copy_value("片58", "元", "items", "key") and int(ed.run_presets()["元"]["items"]["key"]) == 2, "s58: missing value erases, empty section removed")
	ed.model.undo()
	ed.delete_run_preset("片58")
	ed._update_tidy_preview()
	# 段階59：全部左へ・全部右へ
	check(ed._tidy_preview.text.contains("[url=tidyall:L]［← 全部左へ］[/url]") and ed._tidy_preview.text.contains("[url=tidyall:R]［全部右へ →］[/url]"), "s59: copy-all links")
	var before59: Dictionary = ed.run_presets()["元 のコピー 3"].duplicate(true)
	ed._on_tidy_preview_meta("tidyall:R")
	check(AdvScenarioEditor.diff_presets(ed.run_presets()["元"], ed.run_presets()["元 のコピー 3"]).is_empty() and ed._tidy_preview.text.contains("違うところはありません"), "s59: all to the right")
	await _shot("39_tidy_copy_all")
	check(ed.tidy_copy_all(true) == 0, "s59: nothing left to copy")
	ed.undo()
	check(AdvScenarioEditor.diff_presets(ed.run_presets()["元 のコピー 3"], before59).is_empty() and ed._tidy_preview.text.contains("の違い（2）"), "s59: one undo brings all back: %s" % ed._tidy_preview.text)
	await _shot("41_tidy_all_links")
	check(ed.tidy_copy_all(true) == 2 and AdvScenarioEditor.diff_presets(ed.run_presets()["元"], before59).is_empty(), "s59: all to the left")
	# 段階63：片付けの窓のキー（Ctrl+Z・Ctrl+Y）
	check(ed._tidy_dialog.get_node_or_null("Keys") is AdvKeyCatcher, "s63: key catcher in the tidy dialog")
	var kz63 := InputEventKey.new()
	kz63.pressed = true
	kz63.ctrl_pressed = true
	kz63.keycode = KEY_Z
	var ky63 := kz63.duplicate()
	ky63.keycode = KEY_Y
	check(ed._on_tidy_key(kz63) and not AdvScenarioEditor.diff_presets(ed.run_presets()["元"], before59).is_empty() and ed._tidy_preview.text.contains("の違い（2）"), "s63: Ctrl+Z in tidy undoes")
	check(ed._on_tidy_key(ky63) and AdvScenarioEditor.diff_presets(ed.run_presets()["元"], before59).is_empty(), "s63: Ctrl+Y in tidy redoes")
	ed.undo()
	ed._tidy_compare.button_pressed = false
	check(ed._tidy_preview.text.contains("[b]元[/b]："), "s52: back to the list")
	ed._tidy_dialog.hide()
	# 段階52：最後に使った場所
	check(ed.run_from({"scene": "bad_scene", "dialogue": "talk35", "line": 1, "preset": "組A2"}, false), "s52: run with a place")
	AdvPlayer.take_run_from()
	check(AdvScenarioEditor.preset_last_where("組A2") == "bad_scene ／ 会話 talk35 の 2 番目" and ed.preset_dates_text("組A2").contains("\n最後に使った場所：bad_scene ／ 会話 talk35 の 2 番目"), "s52: last place: %s" % AdvScenarioEditor.preset_last_where("組A2"))
	ed.run_from({"scene": "bad_scene", "preset": "組A2"}, false)
	AdvPlayer.take_run_from()
	check(AdvScenarioEditor.preset_last_where("組A2") == "bad_scene" and AdvScenarioEditor.preset_last_where("ない") == "", "s52: last place without a dialogue")
	# 段階52：取っておいたお知らせの見た目をエディタから書く
	var sf52 := FileAccess.open(AdvPlayer.NOTICE_STYLE_SETS_FILE, FileAccess.WRITE)
	sf52.store_string(JSON.stringify({"game": {"あか": {"fg": 2.0, "border": 3.0}, "しろ": {"fg": 7.0}}, "debug": {"青": {"bg": 1.0, "position": "bottom"}}}))
	sf52.close()
	ed.open_style_sets_dialog(true)
	await process_frame
	check(ed._style_pick.item_count == 2 and ed._style_pick.get_item_text(0) == "あか" and ed._style_show.text.contains("fg：2") and ed._style_show.text.contains("（いま"), "s52: style sets dialog: %s" % ed._style_show.text)
	await _shot("26_style_sets")
	check(ed.apply_style_set(true, "あか") == 2 and ed.model.load_project()["notice_style"]["fg"] == 2 and ed.model.load_project()["notice_style"]["fg"] is int, "s52: apply a game style")
	check(not ed._style_show.text.contains("fg：2（いま"), "s52: dialog shows it now matches")
	ed.model.undo()
	check(int(ed.model.load_project().get("notice_style", {}).get("fg", -1)) != 2, "s52: apply can be undone")
	ed._style_kind.select(1)
	ed._fill_style_pick()
	check(ed._style_pick.item_count == 1 and ed._style_pick.get_item_text(0) == "青", "s52: debug styles listed separately")
	check(ed.apply_style_set(false, "青") == 2 and ed.model.load_project()["debug"]["notice_style"]["position"] == "bottom", "s52: apply a debug style")
	ed.model.undo()
	check(ed.apply_style_set(true, "ない") == 0, "s52: missing style")
	# 段階53：見た目の名前を変える・消す・戻す
	ed._style_kind.select(0)
	ed._fill_style_pick()
	check(ed._style_rename.text == "あか", "s53: rename box shows the picked name")
	check(ed.rename_style_set(true, "あか", "しろ") != "" and ed._style_msg.text.contains("もうあります"), "s53: rename to an existing name refused")
	check(ed.rename_style_set(true, "あか", "  ") != "", "s53: rename to empty refused")
	check(ed.rename_style_set(true, "あか", "まっか") == "" and AdvPlayer.notice_style_sets(true).has("まっか") and not AdvPlayer.notice_style_sets(true).has("あか"), "s53: rename")
	check(ed._style_picked() == "まっか" and int(AdvPlayer.notice_style_sets(true)["まっか"]["fg"]) == 2, "s53: renamed one is picked and keeps values")
	check(ed._style_restore.disabled, "s53: nothing to restore yet")
	check(ed.erase_style_set(true, "しろ") and not AdvPlayer.notice_style_sets(true).has("しろ") and ed._style_pick.item_count == 1, "s53: erase")
	check(not ed._style_restore.disabled and ed._style_msg.text.contains("消しました"), "s53: restore button on")
	await _shot("27_style_rename")
	check(ed.restore_erased_style_set() == "しろ" and int(AdvPlayer.notice_style_sets(true)["しろ"]["fg"]) == 7 and ed._style_restore.disabled, "s53: restore")
	check(ed.restore_erased_style_set() == "" and not ed.erase_style_set(true, "ない"), "s53: nothing to restore / missing")
	ed.erase_style_set(true, "しろ")
	AdvPlayer.put_notice_style_set(true, "しろ", {"fg": 1})
	check(ed.restore_erased_style_set() == "しろ（戻す）" and AdvPlayer.notice_style_sets(true).size() == 3, "s53: restore beside a new one of the same name")
	check(not ed.erase_style_set(false, "まっか") and ed.erase_style_set(false, "青") and AdvPlayer.notice_style_sets(true).has("まっか"), "s53: game and debug kept apart")
	ed._style_dialog.hide()
	# 段階53：ひな形といつもの始まりを比べる
	var u53 := AdvScenarioEditor._run_ui()
	if u53.get("last_where") is Dictionary:
		u53["last_where"].erase("始まり53")
	AdvScenarioEditor._save_run_ui(u53)
	ed.save_run_preset("始まり53", {"money": 99, "nope53": 1}, {"key": 2})
	ed.open_preset_dialog("始まり53")
	await process_frame
	check(ed._preset_cmp.get_item_text(1) == "いつもの始まり（ひな形なし）", "s53: start in the compare list")
	ed.compare_preset_with_start()
	var st53: String = ed._preset_diff.text
	check(st53.contains("始めるシーン：いつもは") and st53.contains("変数 nope53：1 ／ なし") and st53.contains("持ち物 key：2 ／ 0"), "s53: diff with start: %s" % st53)
	check(not ed._start_vals.has("money") or st53.contains("変数 money：99 ／ %s" % AdvPlayer.value_text(ed._start_vals["money"])), "s53: declared default shown: %s" % st53)
	await _shot("28_preset_vs_start")
	var b53 := AdvScenarioEditor.start_base({"vars": {"a": 1, "b": 2}, "items": {"k": 3}}, {"a": 1, "z": 5})
	check(b53 == {"vars": {"a": 1}, "items": {"k": 0}}, "s53: start base: %s" % str(b53))
	check(AdvScenarioEditor.start_diff_text({"vars": {"a": 1}}, {"a": 1.0}, "x", "hall").contains("違うところはありません")
		and AdvScenarioEditor.start_diff_text({}, {}, "x", "", "hall").contains("いつもは （未設定）　このひな形は最後に hall"), "s53: start diff text")
	# 段階53：そこから動かす
	check(ed._preset_run_last.disabled and not ed.run_preset_from_last("始まり53", false), "s53: never used = no run")
	ed._preset_dialog.hide()
	check(ed.run_from({"scene": "bad_scene", "dialogue": "talk35", "path": [1], "pre_sets": "cond", "preset": "始まり53"}, false), "s53: run with a place")
	AdvPlayer.take_run_from()
	var rq53 := AdvScenarioEditor.preset_last_request("始まり53")
	check(rq53.get("scene") == "bad_scene" and rq53.get("dialogue") == "talk35" and rq53.get("line") == 1 and rq53.get("line") is int and rq53.get("pre_sets") == "cond" and not rq53.has("vars"), "s53: last request kept: %s" % str(rq53))
	ed.open_preset_dialog("始まり53")
	check(not ed._preset_run_last.disabled, "s53: run-from-there button on")
	await _shot("29_preset_run_last")
	ed._preset_dialog.hide()
	check(ed.run_preset_from_last("始まり53", false), "s53: run from there")
	var rf53 := AdvPlayer.take_run_from()
	check(rf53.get("scene") == "bad_scene" and rf53.get("dialogue") == "talk35" and int(rf53.get("line", 0)) == 1 and rf53.get("preset") == "始まり53" and rf53.get("vars", {}).get("nope53") == 1 and str(rf53.get("pre_sets")) == "cond", "s53: run from there writes the request: %s" % str(rf53))
	check(AdvScenarioEditor.preset_last_request("組A2") == {"scene": "bad_scene"}, "s53: old place without request still runs from the scene")
	ed.delete_run_preset("始まり53")
	check(not ed.run_preset_from_last("始まり53", false), "s53: deleted preset cannot run")
	# 段階54：ひな形にない変数も薄く
	var o54 := AdvScenarioEditor.start_others_text({"vars": {"a": 1}}, {"a": 0, "c": true, "b": 3})
	check(o54 == "[color=#9ca3af]ひな形にない変数（いつもの値のまま 2）：[url=add:b]b = 3[/url]、[url=add:c]c = true[/url]　[url=addall]［全部足す］[/url][/color]", "s54: others text: %s" % o54)
	check(AdvScenarioEditor.start_others_text({"vars": {"a": 1}}, {"a": 0}) == "", "s54: no others")
	var many54 := {}
	for i54 in 25:
		many54["v%02d" % i54] = i54
	check(AdvScenarioEditor.start_others_text({}, many54).contains("（いつもの値のまま 25）") and AdvScenarioEditor.start_others_text({}, many54).contains("v19 = 19[/url] …ほか 5"), "s54: others capped")
	check(AdvScenarioEditor.start_diff_text({"vars": {"a": 1}}, {"a": 0, "z": 2}, "x", "hall").ends_with("z = 2[/url]　[url=addall]［全部足す］[/url][/color]"), "s54: others after the diff")
	var u54 := AdvScenarioEditor._run_ui()
	if u54.get("last_where") is Dictionary:
		u54["last_where"].erase("始まり54")
	AdvScenarioEditor._save_run_ui(u54)
	ed.save_run_preset("始まり54", {"lamp": true}, {})
	ed.open_preset_dialog("始まり54")
	ed._start_vals = {"lamp": false, "money": 10, "name": "たろう"}
	ed.compare_preset_with_start()
	check(ed._preset_diff.text.contains("変数 lamp：true ／ false") and ed._preset_diff.text.contains("ひな形にない変数（いつもの値のまま 2）：[url=add:money]money = 10[/url]、[url=add:name]name = \"たろう\"[/url]"), "s54: dialog shows others: %s" % ed._preset_diff.text)
	await _shot("30_preset_start_others")
	# 段階55：薄い行を押して足す
	check(ed.add_start_var_to_dialog("money") and ed._preset_vars.text == "lamp = true\nmoney = 10" and not ed._preset_diff.text.contains("add:money"), "s55: add from others: %s" % ed._preset_vars.text)
	check(ed._preset_diff.text.contains("いつもの値のまま 1") and ed._preset_diff.text.contains("違い（1）"), "s55: added one equals start (no new diff)")
	check(not ed.add_start_var_to_dialog("money") and not ed.add_start_var_to_dialog("ない55"), "s55: no double / unknown")
	ed._on_preset_diff_meta("add:" + "name".uri_encode())
	check(ed._preset_vars.text.ends_with("name = \"たろう\"") and ed._preset_in_dialog()["vars"].get("name") == "たろう", "s55: meta click adds string value")
	check(not ed._preset_diff.text.contains("ひな形にない変数"), "s55: others line gone when all added")
	check(ed.run_presets()["始まり54"].get("vars", {}).size() == 1, "s55: not saved until save")
	# 段階56：全部足す
	ed._start_vals["b56"] = "x"
	ed._start_vals["a56"] = 1
	ed._update_preset_diff()
	check(ed._preset_diff.text.contains("[url=addall]［全部足す］[/url]"), "s56: add-all link")
	ed._on_preset_diff_meta("addall")
	check(ed._preset_vars.text.ends_with("name = \"たろう\"\na56 = 1\nb56 = \"x\"") and not ed._preset_diff.text.contains("ひな形にない変数"), "s56: add all: %s" % ed._preset_vars.text)
	check(ed.add_all_start_vars_to_dialog() == 0, "s56: nothing left to add")
	ed._preset_vars.text = "lamp = true"
	var many56 := {}
	for i56 in 25:
		many56["w%02d" % i56] = i56
	ed._start_vals = many56
	check(ed.add_all_start_vars_to_dialog() == 25 and ed._preset_in_dialog()["vars"].size() == 26, "s56: add all beyond the 20 shown")
	# 段階57：違いの行を押して窓へ写す
	check(AdvScenarioEditor.set_assign_line("a = 1\na = 2\n\n", "a", "3") == "a = 3\n\n" and AdvScenarioEditor.set_assign_line("b = 1\n\n", "a", "2") == "b = 1\na = 2", "s57: set line")
	check(AdvScenarioEditor.set_assign_line("# a = 0\na = 1\nb = 2", "a", null) == "# a = 0\nb = 2", "s57: remove line, comment kept")
	ed._preset_vars.text = "# メモ\nlamp = true\nx57 = 3"
	ed._preset_items.text = "key = 2"
	ed._start_vals = {"lamp": false, "x57": 3}
	ed.compare_preset_with_start()
	check(ed._preset_diff.text.contains("[url=take:vars:lamp]変数 lamp：true ／ false[/url]") and ed._preset_diff.text.contains("[url=takeall]［全部写す］[/url]"), "s57: diff lines are links: %s" % ed._preset_diff.text)
	ed._on_preset_diff_meta("take:vars:lamp")
	check(ed._preset_vars.text == "# メモ\nlamp = false\nx57 = 3", "s57: take a var: %s" % ed._preset_vars.text)
	# 段階58：写す前に戻す
	check(not ed._preset_undo_btn.disabled and ed._preset_undo_btn.tooltip_text.contains("lamp を写す") and ed.undo_preset_edit() and ed._preset_vars.text == "# メモ\nlamp = true\nx57 = 3" and ed._preset_undo_btn.disabled, "s58: undo a take")
	check(not ed.undo_preset_edit(), "s58: only one undo")
	ed.take_preset_value("vars", "lamp")
	check(ed.take_preset_value("items", "key") and ed._preset_items.text == "key = 0", "s57: take an item from start: %s" % ed._preset_items.text)
	check(not ed.take_preset_value("vars", "lamp") and not ed.take_preset_value("vars", "ない57") and not ed.take_preset_value("x", "lamp"), "s57: nothing to take")
	await _shot("35_preset_take")
	ed.save_run_preset("相手57", {"lamp": true, "y57": "a"}, {})
	ed._fill_preset_cmp("始まり54")
	ed.compare_preset_with("相手57")
	check(ed._preset_diff.text.contains("の違い（4）"), "s57: 4 differences: %s" % ed._preset_diff.text)
	ed._on_preset_diff_meta("takeall")
	check(ed._preset_vars.text == "# メモ\nlamp = true\ny57 = \"a\"" and ed._preset_items.text == "", "s57: take all: %s / %s" % [ed._preset_vars.text, ed._preset_items.text])
	await _shot("36_preset_undo_take")
	check(ed.undo_preset_edit() and ed._preset_vars.text == "# メモ\nlamp = false\nx57 = 3" and ed._preset_items.text == "key = 0", "s58: one undo brings take-all back: %s / %s" % [ed._preset_vars.text, ed._preset_items.text])
	ed.take_all_preset_values()
	check(ed._preset_diff.text.contains("違うところはありません") and ed.take_all_preset_values() == 0, "s57: same after take all")
	check(ed.run_presets()["始まり54"].get("vars", {}).size() == 1, "s57: not saved until save")
	ed.compare_preset_with("")
	check(not ed.take_preset_value("vars", "lamp"), "s57: no compare, no take")
	check(not ed.preset_edit_undo.is_empty(), "s58: undo kept while the dialog is open")
	ed.open_preset_dialog("始まり54")
	check(ed.preset_edit_undo.is_empty() and ed._preset_undo_btn.disabled, "s58: reopening forgets the undo")
	# 段階60：ひな形の窓を開いたまま元に戻すと並べ直す
	ed.save_run_preset("相手60", {"lamp": 5}, {})
	ed.open_preset_dialog("始まり54")
	ed._preset_vars.text = "lamp = 1"
	ed.compare_preset_with("相手60")
	check(ed._preset_diff.text.contains("変数 lamp：1 ／ 5"), "s60: before: %s" % ed._preset_diff.text)
	ed.save_run_preset("相手60", {"lamp": 7}, {})
	check(ed._preset_diff.text.contains("変数 lamp：1 ／ 7") and ed._preset_vars.text == "lamp = 1", "s60: follows a save, text kept: %s" % ed._preset_diff.text)
	ed.undo()
	check(ed._preset_diff.text.contains("変数 lamp：1 ／ 5") and String(ed._preset_cmp.get_item_metadata(ed._preset_cmp.selected)) == "相手60", "s60: follows undo: %s" % ed._preset_diff.text)
	ed.delete_run_preset("相手60")
	check(ed._preset_cmp.selected == 0 and ed._preset_diff.text == "", "s60: compared one deleted = no compare")
	ed.undo()
	var has60 := false
	for i60 in ed._preset_cmp.item_count:
		has60 = has60 or ed._preset_cmp.get_item_text(i60) == "相手60"
	check(has60 and ed._preset_vars.text == "lamp = 1", "s60: undo delete brings it back to the list")
	ed.delete_run_preset("相手60")
	ed.open_preset_dialog("始まり54")
	ed.delete_run_preset("相手57")
	# 段階57：書き出し・読み込みで組・作った日時・組の並びを運ぶ
	var p57 := ed.model.load_project()
	var keep57 := p57.duplicate(true)
	ed.save_run_preset("輸A57", {"a": 1}, {}, "G1_57")
	ed.save_run_preset("輸B57", {"b": 2}, {}, "G2_57")
	var made57 := float(ed.run_presets()["輸A57"]["created"])
	p57 = ed.model.load_project()
	p57["debug"]["run_group_order"] = ["G2_57", "G1_57"]
	ed.model.write_json(ed.model.project_path, p57)
	var f57 := "user://s57_presets.json"
	check(ed.export_run_presets(f57, ["輸A57", "輸B57"]) == OK, "s57: export")
	var raw57 = AdvJson.load_file(f57, [])
	check(raw57.get("group_order") == ["G2_57", "G1_57"] and raw57["presets"]["輸A57"].get("group") == "G1_57" and float(raw57["presets"]["輸A57"].get("created", 0)) == made57, "s57: file has groups, created and order: %s" % str(raw57))
	check(AdvScenarioEditor.read_preset_file_group_order(f57) == ["G2_57", "G1_57"] and AdvScenarioEditor.read_preset_file_group_order("user://ない57.json") == [], "s57: read group order")
	ed.model.write_json(ed.model.project_path, keep57)
	check(not ed.run_presets().has("輸A57"), "s57: removed before import")
	# 段階58：読み込む窓に組を出す
	check(AdvScenarioEditor.import_group_text({"x": {"group": "G"}}, {"group": "G"}) == "　［組：G］" and AdvScenarioEditor.import_group_text({}, {"group": "G"}) == "　［組：G（新しい組）］" and AdvScenarioEditor.import_group_text({}, {}) == "", "s58: import group text")
	var u60 := AdvScenarioEditor._run_ui()
	u60.erase("import_group")
	AdvScenarioEditor._save_run_ui(u60)
	check(ed.open_import_pick(f57) and ed._import_checks["輸A57"].text == "輸A57　［組：G1_57（新しい組）］（新しい）", "s58: import pick shows the group: %s" % ed._import_checks["輸A57"].text)
	# 段階59：読み込む組を選ぶ
	check(ed._import_group_pick.get_item_text(0) == "ファイルの組のまま" and ed.import_group_choice() == null and not ed._import_group_new.visible, "s59: import group pick")
	ed.set_import_group("#new")
	ed._import_group_new.text = "受け59"
	ed._refresh_import_pick(false)
	check(ed._import_group_new.visible and ed.import_group_choice() == "受け59" and ed._import_checks["輸A57"].text.contains("［組：受け59（新しい組）］"), "s59: new group shown: %s" % ed._import_checks["輸A57"].text)
	await _shot("40_import_into_group")
	ed.set_import_group("")
	check(ed.import_group_choice() == "" and ed._import_checks["輸A57"].text == "輸A57（新しい）", "s59: no group: %s" % ed._import_checks["輸A57"].text)
	ed.set_import_group("#new")
	ed._import_group_new.text = "  "
	check(ed.import_group_choice() == null, "s59: empty new name = file groups")
	ed.set_import_group("#file")
	await _shot("37_import_groups")
	ed._preset_import_pick.hide()
	var before57 := ed.preset_group_order()
	check(ed.import_run_presets(f57).size() == 2, "s57: import")
	var ord57 := ed.preset_group_order()
	check(ord57.slice(ord57.size() - 2) == ["G2_57", "G1_57"] and ord57.slice(0, before57.size()) == before57, "s57: new groups follow the file order at the end: %s" % str(ord57))
	check(ed.preset_group(ed.run_presets()["輸A57"]) == "G1_57" and float(ed.run_presets()["輸A57"]["created"]) == made57, "s57: group and created kept")
	ed.model.undo()
	check(not ed.run_presets().has("輸A57") and not ed.preset_group_order().has("G2_57"), "s57: undo import")
	check(ed.import_run_presets(f57, ["輸A57"], false, "受け59") == ["輸A57"] and ed.preset_group(ed.run_presets()["輸A57"]) == "受け59" and ed.preset_group_order()[-1] == "受け59" and not ed.preset_group_order().has("G1_57"), "s59: import into a chosen group: %s" % str(ed.preset_group_order()))
	ed.model.undo()
	check(ed.import_run_presets(f57, ["輸A57"], false, "") == ["輸A57"] and ed.preset_group(ed.run_presets()["輸A57"]) == "", "s59: import with no group")
	ed.model.undo()
	ed.open_import_pick(f57)
	ed.set_import_group("#new")
	ed._import_group_new.text = "受け59b"
	ed.set_import_check("輸B57", false)
	check(ed.confirm_import_pick() == ["輸A57"] and ed.preset_group(ed.run_presets()["輸A57"]) == "受け59b", "s59: confirm uses the chosen group")
	ed._preset_import_pick.hide()
	# 段階60：読み込む組を覚える
	check(AdvScenarioEditor._run_ui().get("import_group") == "受け59b", "s60: import group remembered")
	ed.open_import_pick(f57)
	check(ed.import_group_choice() == "受け59b" and ed._import_group_pick.get_item_text(ed._import_group_pick.selected) == "組：受け59b", "s60: remembered group picked")
	ed._preset_import_pick.hide()
	ed.model.undo()
	ed.open_import_pick(f57)
	check(ed.import_group_choice() == "受け59b" and String(ed._import_group_pick.get_item_metadata(ed._import_group_pick.selected)) == "#new" and ed._import_group_new.visible, "s60: gone group comes back as a new name")
	ed.set_import_group("")
	ed.set_import_check("輸B57", false)
	ed.confirm_import_pick()
	ed._preset_import_pick.hide()
	ed.model.undo()
	ed.open_import_pick(f57)
	check(ed.import_group_choice() == "", "s60: no group remembered")
	ed.set_import_group("#file")
	ed.set_import_check("輸B57", false)
	ed.confirm_import_pick()
	ed._preset_import_pick.hide()
	ed.model.undo()
	ed.open_import_pick(f57)
	check(ed.import_group_choice() == null and ed._import_group_pick.selected == 0, "s60: file groups remembered")
	ed._preset_import_pick.hide()
	ed._preset_import_pick.hide()
	var f57b := "user://s57_old.json"
	var fo57 := FileAccess.open(f57b, FileAccess.WRITE)
	fo57.store_string(JSON.stringify({"旧57": {"vars": {"a": 1}, "group": "G3_57"}}))
	fo57.close()
	var raw_ord57 = ed.model.load_project().get("debug", {}).get("run_group_order", [])
	check(ed.import_run_presets(f57b) == ["旧57"] and ed.model.load_project().get("debug", {}).get("run_group_order", []) == raw_ord57, "s57: old file leaves the order alone")
	ed.model.write_json(ed.model.project_path, keep57)
	DirAccess.remove_absolute(f57)
	DirAccess.remove_absolute(f57b)
	ed._preset_dialog.hide()
	# 段階54：「実行：」の右クリック
	check(not ed.open_preset_context("") and not ed.open_preset_context("ない54"), "s54: no menu for none")
	check(ed.open_preset_context("始まり54") and ed._preset_ctx.item_count == 5 and ed._preset_ctx.is_item_disabled(0) and ed._preset_ctx.get_item_text(0).contains("まだ使っていません"), "s54: menu before use")
	ed.run_from({"scene": "bad_scene", "dialogue": "talk35", "line": 1, "preset": "始まり54"}, false)
	AdvPlayer.take_run_from()
	ed.open_preset_context("始まり54")
	check(not ed._preset_ctx.is_item_disabled(0) and ed._preset_ctx.get_item_text(0).contains("bad_scene ／ 会話 talk35 の 2 番目"), "s54: menu shows the place: %s" % ed._preset_ctx.get_item_text(0))
	check(ed.preset_context_pressed(AdvScenarioEditor.PresetCtx.RUN_LAST, false), "s54: run from there via menu")
	var rf54 := AdvPlayer.take_run_from()
	check(rf54.get("dialogue") == "talk35" and rf54.get("preset") == "始まり54" and rf54.get("vars", {}).get("lamp") == true, "s54: menu run writes request: %s" % str(rf54))
	if ed.scene_id != "":
		check(ed.preset_context_pressed(AdvScenarioEditor.PresetCtx.RUN_HERE, false) and AdvPlayer.take_run_from().get("scene") == ed.scene_id, "s54: run here via menu")
	else:
		check(ed._preset_ctx.is_item_disabled(1), "s54: run here off without a scene")
	check(ed.preset_context_pressed(AdvScenarioEditor.PresetCtx.DUP, false) and ed.run_presets().has("始まり54 のコピー"), "s54: duplicate via menu")
	check(ed.preset_context_pressed(AdvScenarioEditor.PresetCtx.OPEN, false) and ed._preset_dialog.visible and ed._preset_name.text == "始まり54", "s54: open via menu")
	ed._preset_dialog.hide()
	# 段階55：右クリックの「組を変える…」
	check(ed._preset_ctx.get_item_text(4) == "組を変える…（いまは 組なし）", "s55: group item: %s" % ed._preset_ctx.get_item_text(4))
	check(ed.preset_context_pressed(AdvScenarioEditor.PresetCtx.GROUP, false) and ed.move_group_name == "始まり54" and ed._move_group_pick.get_item_text(0) == "（組なし）" and ed._move_group_pick.selected == 0, "s55: move dialog")
	check(not ed._move_group_new.editable, "s55: new-group box off")
	ed.select_move_group("#new")
	ed._move_group_new.text = "  移した55 "
	check(ed._move_group_new.editable and ed.move_group_choice() == "移した55", "s55: new group choice")
	await _shot("32_move_group")
	ed._move_group_dialog.hide()
	# 段階66：組を変える・書き出すの窓にも Ctrl+Enter
	check(ed._move_group_dialog.get_node_or_null("Keys") is AdvKeyCatcher and ed._preset_export_pick.get_node_or_null("Keys") is AdvKeyCatcher, "s66: key catchers in move-group and export windows")
	var ke66 := InputEventKey.new()
	ke66.pressed = true
	ke66.ctrl_pressed = true
	ke66.keycode = KEY_ENTER
	ed.open_move_group_dialog("始まり54")
	ed.select_move_group("#new")
	ed._move_group_new.text = "キー66"
	check(ed._ok_key(ed._move_group_dialog, ke66) and ed.preset_group(ed.run_presets()["始まり54"]) == "キー66", "s66: Ctrl+Enter moves the group")
	ed.model.undo()
	ed.open_move_group_dialog("始まり54")   # 段階55の続きのために、選びを元に戻す
	ed.select_move_group("#new")
	ed._move_group_new.text = "  移した55 "
	ed._move_group_dialog.hide()
	check(ed.set_preset_group("始まり54", ed.move_group_choice()) and ed.preset_group(ed.run_presets()["始まり54"]) == "移した55", "s55: moved")
	check(not ed.set_preset_group("始まり54", "移した55"), "s55: same group = no change")
	ed.open_move_group_dialog("始まり54")
	check(ed.move_group_choice() == "移した55" and ed._move_group_pick.get_item_text(ed._move_group_pick.selected) == "組：移した55", "s55: dialog picks current group")
	ed.model.undo()
	check(ed.preset_group(ed.run_presets()["始まり54"]) == "", "s55: undo move")
	ed.model.redo()
	check(ed.set_preset_group("始まり54", "") and ed.preset_group(ed.run_presets()["始まり54"]) == "", "s55: to no group")
	check(not ed.set_preset_group("ない55", "x"), "s55: missing preset")
	ed._move_group_dialog.hide()
	ed.delete_run_preset("始まり54 のコピー")
	ed.delete_run_preset("始まり54")
	# 段階54：いまの設定を取っておく
	var p54 := ed.model.load_project()
	var keep54 := p54.duplicate(true)
	p54["notice_style"] = {"fg": 5, "position": "top"}
	var d54 = p54.get("debug", {})
	if d54 is Dictionary:
		d54.erase("notice_style")
	ed.model.write_json(ed.model.project_path, p54)
	DirAccess.remove_absolute(AdvPlayer.NOTICE_STYLE_SETS_FILE)
	ed.open_style_sets_dialog(true)
	check(ed.keep_project_style(true, "") == "いまの設定" and int(AdvPlayer.notice_style_sets(true)["いまの設定"]["fg"]) == 5, "s54: keep project style")
	check(ed._style_picked() == "いまの設定" and ed._style_msg.text.contains("取っておきました"), "s54: kept one is picked")
	check(ed.keep_project_style(true, "いまの設定") == "いまの設定 2", "s54: same name gets a number")
	await _shot("31_style_keep")
	check(ed.keep_project_style(false, "でば") == "" and ed._style_msg.text.contains("debug.notice_style"), "s54: nothing to keep for debug")
	# 段階55：見た目を二つ比べる
	AdvPlayer.put_notice_style_set(true, "いまの設定 2", {"fg": 6, "bg": 1})
	ed.select_style_set("いまの設定")
	check(ed._style_cmp.item_count == 2 and ed._style_cmp.get_item_text(1) == "いまの設定 2" and not ed._style_cmp.disabled, "s55: compare list excludes itself")
	ed.compare_style_with("いまの設定 2")
	check(ed._style_show.text == "[b]いまの設定[/b] ／ [b]いまの設定 2[/b] の違い（3）\n　[url=copy:fg]fg：5 ／ 6[/url]\n　[url=copy:position]position：\"top\" ／ なし[/url]\n　[url=copy:bg]bg：なし ／ 1[/url]\n[color=#9ca3af]行を押すと、いまの設定 2 の値を いまの設定 へ写します　[url=copyall]［全部写す］[/url][/color]", "s55: style diff: %s" % ed._style_show.text)
	await _shot("33_style_compare")
	ed.select_style_set("いまの設定 2")
	check(ed._style_show.text.contains("いまの設定 2[/b] ／ [b]いまの設定[/b]") and ed.style_cmp_name == "いまの設定", "s55: picking the compared one swaps: %s" % ed._style_show.text)
	ed.compare_style_with("")
	check(not ed._style_show.text.contains("の違い") and ed._style_cmp.selected == 0, "s55: back to normal show")
	ed.select_style_set("いまの設定")
	check(AdvScenarioEditor.style_diff_text("a", {"fg": 1}, "b", {"fg": 1.0}).ends_with("違うところはありません"), "s55: same values")
	ed.compare_style_with("")
	# 段階56：選び直すと前の知らせを消す
	ed._style_msg.text = "前の知らせ"
	ed.select_style_set("いまの設定 2")
	check(ed._style_msg.text == "", "s56: picking clears the old message")
	ed._style_msg.text = "前の知らせ"
	ed.select_style_set("いまの設定")
	ed.compare_style_with("いまの設定 2")
	check(ed._style_msg.text == "", "s56: comparing clears the old message")
	# 段階56：違うキーを押して写す
	check(ed._style_show.text.contains("[url=copy:fg]fg：5 ／ 6[/url]") and ed._style_show.text.contains("いまの設定 2 の値を いまの設定 へ写します"), "s56: diff lines are links: %s" % ed._style_show.text)
	ed._on_style_show_meta("copy:fg")
	check(int(AdvPlayer.notice_style_sets(true)["いまの設定"]["fg"]) == 6 and ed._style_msg.text.contains("写しました") and ed.style_cmp_name == "いまの設定 2", "s56: copy fg: %s" % ed._style_msg.text)
	check(ed._style_show.text.contains("の違い（2）") and not ed._style_restore.disabled and ed._style_restore.text == "一つ戻す", "s56: still comparing after copy")
	await _shot("34_style_copy")
	check(ed.copy_style_key("position") and not AdvPlayer.notice_style_sets(true)["いまの設定"].has("position"), "s56: copy a missing key erases it")
	check(ed.copy_style_key("bg") and ed._style_show.text.ends_with("違うところはありません"), "s56: all copied")
	check(not ed.copy_style_key("bg") and not ed.copy_style_key("ない56"), "s56: nothing to copy")
	check(ed.restore_erased_style_set() == "いまの設定" and not AdvPlayer.notice_style_sets(true)["いまの設定"].has("bg") and ed._style_msg.text.contains("写す前に戻しました"), "s56: undo the last copy")
	AdvPlayer.put_notice_style_set(true, "ひとつ56", {"fg": 1})
	AdvPlayer.put_notice_style_set(true, "べつ56", {"bg": 2})
	ed._fill_style_pick()
	ed.select_style_set("ひとつ56")
	ed.compare_style_with("べつ56")
	check(not ed.copy_style_key("fg") and ed._style_msg.text.contains("空になる"), "s56: refuse to empty")
	check(ed.copy_style_key("bg") and ed.rename_style_set(true, "ひとつ56", "ふたつ56") == "" and ed.restore_erased_style_set() == "ふたつ56" and not AdvPlayer.notice_style_sets(true)["ふたつ56"].has("bg"), "s56: undo copy follows a rename")
	# 段階57：全部写す
	ed.compare_style_with("べつ56")
	check(ed._style_show.text.contains("[url=copyall]［全部写す］[/url]"), "s57: copy-all link")
	ed._on_style_show_meta("copyall")
	check(AdvPlayer.notice_style_sets(true)["ふたつ56"] == {"bg": 2.0} and ed._style_msg.text.contains("全部写しました") and ed._style_msg.text.contains("（2）"), "s57: copy all: %s" % str(AdvPlayer.notice_style_sets(true)["ふたつ56"]))
	check(ed._style_show.text.ends_with("違うところはありません") and ed.copy_all_style_keys() == 0, "s57: same after copy all")
	check(ed.restore_erased_style_set() == "ふたつ56" and AdvPlayer.notice_style_sets(true)["ふたつ56"] == {"fg": 1.0}, "s57: one undo brings all back")
	# 段階63：見た目の窓の Ctrl+Z
	ed.copy_all_style_keys()
	var kz63s := InputEventKey.new()
	kz63s.pressed = true
	kz63s.ctrl_pressed = true
	kz63s.keycode = KEY_Z
	ed._style_dialog.gui_release_focus()
	check(ed._style_dialog.get_node_or_null("Keys") is AdvKeyCatcher and ed._on_style_key(kz63s) and AdvPlayer.notice_style_sets(true)["ふたつ56"] == {"fg": 1.0}, "s63: Ctrl+Z in the style dialog")
	check(not ed._on_style_key(kz63s) and ed._style_restore.tooltip_text.contains("戻せるものはありません"), "s63: nothing more to undo")
	ed.compare_style_with("")
	ed.select_style_set("いまの設定")
	ed._style_dialog.hide()
	ed.model.write_json(ed.model.project_path, keep54)
	DirAccess.remove_absolute(AdvPlayer.NOTICE_STYLE_SETS_FILE)
	DirAccess.remove_absolute(AdvPlayer.NOTICE_STYLE_SETS_FILE)
	for n45 in ["組A1", "組A2", "組A1 のコピー", "続け", "続け 2"]:
		ed.delete_run_preset(n45)
	for n42 in ["元（読み込み 2）", "新しい", "空"]:
		ed.delete_run_preset(n42)
	DirAccess.remove_absolute(px)
	for n in ["元", "元 のコピー", "元 のコピー 2", "元 のコピー 3", "元（読み込み）", "手書き"]:
		ed.delete_run_preset(n)
	AdvScenarioEditor.clear_run_history()
	DirAccess.remove_absolute(ink35)
	dls.erase("talk35")
	ed.model.save_chapter_data(first, "chapter1", cd35)
	ed.check_external_changes()
	ed.sid = first
	ed.cid = "chapter1"
	ed.scene_id = scene
	st.set_steps([{"scene.goto": {"scene": scene}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(AdvScenarioEditor.missing_message("item", "key", ["key"]) == "" and AdvScenarioEditor.missing_message("item", "x", []) == "持ち物が見つかりません：x", "s28: missing message")
	st.set_steps([{"scene.goto": {"scene": scene}}])
	st.tree.get_root().get_child(0).select(1)
	await _settle()
	check(AdvScenarioEditor.asset_kind_of(["items", "key", "icon"]) == "image" and AdvScenarioEditor.asset_kind_of(["notices", "item_add", "icon"]) == "image", "s26: icon fields are images")
	st.args_form.set_manual_value(["scene"], "どこか")
	check(st.get_steps()[0] == {"scene.goto": {"scene": "どこか"}}, "s25: manual value: %s" % JSON.stringify(st.get_steps()[0]))
	st.add_step("event")
	check(st.get_steps()[1] == {"extras.open": {}}, "s23: new event step after the selected one: %s" % JSON.stringify(st.get_steps()))

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
	# 括弧を開いた直後でも、その関数に合う候補を出す（自前の一覧）
	x.code.text = "visited("
	x.code.set_caret_column(8)
	var opts := x.completion_items().map(func(o): return o["insert"])
	check(scene in opts and not "money" in opts, "expr: completion right after visited(: %s" % str(opts))
	x.request_completion()
	check(x.is_completion_visible(), "expr: completion list shown")
	await _settle()
	await _shot("08a_completion")
	x.accept_completion(opts.find(scene))
	check(x.code.text == "visited(" + scene, "expr: completion inserted (%s)" % x.code.text)
	x.code.text = "mo"
	x.code.set_caret_column(2)
	opts = x.completion_items().map(func(o): return o["insert"])
	check(opts[0] == "money", "expr: completion of names: %s" % str(opts))
	x.code.text = "ha"
	x.code.set_caret_column(2)
	opts = x.completion_items().map(func(o): return o["insert"])
	check("has(" in opts, "expr: functions insert an open paren: %s" % str(opts))
	x.code.text = "sys.slot_c"
	x.code.set_caret_column(10)
	opts = x.completion_items().map(func(o): return o["insert"])
	check("sys.slot_count" in opts, "expr: completion of dotted names: %s" % str(opts))
	x.hide_completion()
	# Ink の call_scene・goto_scene の行き先の候補
	var cdi := ed.model.load_chapter_data(first, "chapter1")
	cdi["scenes"]["shop_sub"] = {"kind": "sub", "enter": "みせ"}
	ed.model.save_chapter_data(first, "chapter1", cdi)
	var ici := ed.ink_completion_items("~ call_scene(\"sh").map(func(o): return o["insert"])
	check(ici == ["shop_sub"], "ink completion: call_scene lists subscenes: %s" % str(ici))
	ici = ed.ink_completion_items("~ goto_scene(\"").map(func(o): return o["insert"])
	check(ici.has("shop_sub") and ici.has(scene), "ink completion: goto_scene lists all scenes: %s" % str(ici))
	check(ed.ink_completion_items("~ x = 1").is_empty(), "ink completion: nothing elsewhere")
	# 段階23：シーンのカードに種類を出す、シーンの候補
	check(ed.model.scenes(first, "chapter1").any(func(s): return s["id"] == "shop_sub" and s["kind"] == "sub"), "s23: scene kind in the model")
	check(ed._suggest(["opening"]).has("shop_sub") and ed._suggest(["system_scenes", "save"]).has(scene), "s23: scene id suggestions")
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
	# 開始シナリオ
	check(ed._start_row.visible and ed._start_pick.item_count == 4, "editor: start scenario picker")
	var yi := -1
	for i in ed._start_pick.item_count:
		if ed._start_pick.get_item_metadata(i) == "yakata":
			yi = i
	ed._on_start_picked(yi)
	check(ed.model.load_project()["entry"] == ed.model.load_scenario_data("yakata")["start"], "editor: start scenario sets entry")
	check(ed.model.start_scenario() == "yakata", "editor: start scenario")
	await _shot("02b_game")
	# 古い形のファイルを移す
	AdvScenarioModel._save_json(BASE + "/scenario/old.scenario.json", {"scenario_version": 1, "start": "old_room",
		"variables": {"lamp": {"type": "bool", "default": false}}, "scenes": {"old_room": {"enter": "ふるい へや。"}}})
	var pp := ed.model.load_project()
	pp["scenarios"].insert(0, BASE + "/scenario/old.scenario.json")
	ed.model.save_project(pp)
	ed.sid = AdvScenarioModel.LOOSE_ID
	ed._show(AdvScenarioEditor.Page.SCENARIO)
	check(ed.migrate(BASE + "/scenario/old.scenario.json", "old_one", "ふるい はなし") == OK, "editor: migrate a loose file")
	check(not FileAccess.file_exists(BASE + "/scenario/old.scenario.json"), "migrate: old file removed")
	var om := ed.model.load_scenario_data("old_one")
	check(om.get("start") == "old_room" and om.has("variables") and not om.has("scenes"), "migrate: main settings: %s" % str(om.keys()))
	check(ed.model.load_chapter_data("old_one", "chapter1")["scenes"].has("old_room"), "migrate: scenes in chapter1")
	var plist: Array = ed.model.load_project()["scenarios"]
	check(plist.slice(-2) == [BASE + "/scenario/old_one/_scenario.scenario.json", BASE + "/scenario/old_one/chapter1.scenario.json"] and not BASE + "/scenario/old.scenario.json" in plist, "migrate: scenarios updated: %s" % str(plist))
	check(not FileAccess.get_file_as_string(BASE + "/scenario/old_one/_scenario.scenario.json").contains(".0"), "model: integers are written as integers")
	ed.undo()
	check(FileAccess.file_exists(BASE + "/scenario/old.scenario.json") and ed.model.load_project()["scenarios"][0] == BASE + "/scenario/old.scenario.json", "migrate: undo")
	ed.redo()
	ed._show(AdvScenarioEditor.Page.GAME)

	# 作ったものがゲームとして読める
	var p: Dictionary = AdvScenarioModel._load(pj)
	var core := AdvCore.new()
	core.setup({"seed": 1})
	core.use_adapter(AdvJsonAdapter.new())
	check(core.load_scenario(PackedStringArray(p["scenarios"])) == OK, "editor: scenario files load")
	var errs := core.validate().filter(func(d): return d["severity"] == "error")
	check(errs.is_empty(), "editor: no errors: %s" % str(errs.map(func(d): return d["message"])))

	# 段階60：窓をまとめて見直す（画面写真）
	await _review_windows(ed)
	_rmdir(BASE)
	print("")
	print("passed: %d  failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
