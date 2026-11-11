@tool
class_name AdvScenarioEditor
extends VBoxContainer
## シナリオエディタ（6.8）。HyperCard のように、カードを開いていってシナリオを作る。
##
##   ゲーム（シナリオの一覧）→ シナリオ（チャプターの一覧）→ チャプター（シーンの一覧）→ シーン
##                                                                     ├ セリフエディタ（JSON / Ink）
##                                                                     └ コマンドエディタ
##
## - 上のパンくずで、どの一覧にも戻れる
## - 一覧の左は、その段の共通の設定（初期設定・変数・コマンド・セリフ・アセット・その他）
## - 一覧の右はカード。ダブルクリックで開く、右クリックで名前の変更・新規作成・複写・別の場所へ複写・削除
## - 式は、手入力か式エディタ（候補を出す）で書く
## データの読み書きは AdvScenarioModel。

signal open_assets_requested     ## 「アセットエディタ」を押したとき（エディタの画面がマニフェストを開く）
signal status(text: String)

enum Page { ROOT, GAME, SCENARIO, CHAPTER, SCENE, DIALOGUE, COMMAND }

const MENU_OPEN := 0
const MENU_RENAME := 1
const MENU_NEW := 2
const MENU_DUP := 3
const MENU_COPY_TO := 4
const MENU_DELETE := 5

## 設定のタブ：[タブ名, [項目名…]]。最後の「その他」には、ほかのタブにない項目が入る
const GAME_TABS := [
	["初期設定", ["title", "game_id", "template", "templates", "entry", "lang", "seed", "input_devices", "features"]],
	["変数", ["variables", "constants"]],
	["コマンド", ["verbs", "inputs", "dictionaries", "slot_mode", "intent_schema"]],
	["セリフ", ["event_defaults", "hint_topics"]],
	["アセット", ["asset_roots", "asset_folders", "missing_asset"]],
]
const GAME_HIDDEN := ["$schema", "project_version", "scenarios"]
const SCENARIO_TABS := [
	["初期設定", ["start", "flow", "chapters"]],
	["変数", ["variables", "constants", "items"]],
	["コマンド", ["verbs", "nouns", "replies", "particles", "topics", "intent_schema"]],
	["セリフ", ["characters", "event_defaults"]],
	["アセット", ["assets"]],
]
## シナリオ・チャプターの設定に出さない項目（シーンの中身、シーン1つのファイルの項目）
const SCENARIO_HIDDEN := ["$schema", "scenario_version", "scenes", "dialogues", "scene", "name", "image", "image_transition",
	"first", "enter", "objects", "exits", "sprites", "on"]
const SCENE_STEP_KEYS := ["on", "first", "enter"]

var model: AdvScenarioModel
var page: int = Page.ROOT
var sid: String = ""         ## 開いているシナリオ
var cid: String = ""         ## 開いているチャプター
var scene_id: String = ""    ## 開いているシーン
var dlg: Dictionary = {}     ## 開いているセリフ {kind: "json"|"ink", id, path}
var cmd: Dictionary = {}     ## 開いているコマンド {target, key}（target：enter / first / scene / obj:ID / exit:ID）

var _crumbs: HFlowContainer
var _status: Label
var _pages: Dictionary = {}
var _dirty: bool = false

# シナリオのフォルダ
var _root_edit: LineEdit
# 一覧（ゲーム・シナリオ・チャプター）
var _list_split: HSplitContainer
var _tabs: TabContainer
var _tab_forms: Array = []          ## [{form, keys}]
var _settings_data: Dictionary = {}
var _settings_note: Label
var _grid: AdvCardGrid
var _list_title: Label
var _menu: PopupMenu
var _menu_ids: Array = []
# シーン
var _scene_form: AdvSchemaForm
var _scene_data: Dictionary = {}     ## シーンの定義（手順も含む全部）
var _dlg_kind: OptionButton
var _dlg_list: ItemList
var _cmd_list: ItemList
# セリフ
var _dlg_id: LineEdit
var _dlg_steps: AdvStepEditor
var _ink_code: CodeEdit
var _dlg_msg: Label
# コマンド
var _cmd_target: OptionButton
var _cmd_targets: Array = []
var _cmd_verb: OptionButton
var _cmd_verbs: Array = []
var _cmd_with: LineEdit
var _cmd_steps: AdvStepEditor
var _cmd_verb_row: HBoxContainer
# ダイアログ
var _copy_dialog: ConfirmationDialog
var _copy_count: SpinBox
var _copy_scenario: OptionButton
var _copy_chapter: OptionButton
var _copy_to_other: bool = false
var _delete_dialog: ConfirmationDialog
var _ask_dialog: ConfirmationDialog
var _ask_edit: LineEdit
var _ask_done: Callable
var expr_editor: AdvExprEditor


func _init(project_path: String = AdvProject.DEFAULT_PATH) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	model = AdvScenarioModel.new(project_path)
	_build()


## エディタの画面に出したとき。ファイルから読み直す。
func reload() -> void:
	model = AdvScenarioModel.new(model.project_path)
	_refresh_expr_candidates()
	if not model.has_root():
		_show(Page.ROOT)
	elif page == Page.ROOT:
		_show(Page.GAME)
	else:
		_show(page)


func set_project_path(path: String) -> void:
	model = AdvScenarioModel.new(path)


# ---------------------------------------------------------------- 画面を作る

func _build() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	_crumbs = HFlowContainer.new()
	_crumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_crumbs)
	_status = Label.new()
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(120, 0)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)
	add_child(HSeparator.new())

	_pages[Page.ROOT] = _build_root_page()
	_pages[Page.GAME] = _build_list_page()
	_pages[Page.SCENE] = _build_scene_page()
	_pages[Page.DIALOGUE] = _build_dialogue_page()
	_pages[Page.COMMAND] = _build_command_page()
	for p in _pages.values():
		if p.get_parent() == null:
			p.visible = false
			p.size_flags_vertical = Control.SIZE_EXPAND_FILL
			add_child(p)
	_build_dialogs()
	expr_editor = AdvExprEditor.new()
	add_child(expr_editor)
	_dlg_steps.expr_editor = expr_editor
	_cmd_steps.expr_editor = expr_editor


func _build_root_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "シナリオを置くフォルダを決めてください。\nフォルダの下に、シナリオごとのフォルダと、チャプターごとのファイルを作ります（セットアップで作ったゲームなら、もう決まっています）。"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	var row := HBoxContainer.new()
	box.add_child(row)
	_root_edit = LineEdit.new()
	_root_edit.text = AdvScenarioModel.DEFAULT_ROOT
	_root_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_edit.text_submitted.connect(func(_t): _on_root_decided())
	row.add_child(_root_edit)
	var b := Button.new()
	b.text = "決定"
	b.pressed.connect(_on_root_decided)
	row.add_child(b)
	return box


func _build_list_page() -> Control:
	_list_split = HSplitContainer.new()
	_list_split.split_offset = 80
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2
	_list_split.add_child(left)
	var lt := Label.new()
	lt.text = "共通の設定"
	left.add_child(lt)
	_settings_note = Label.new()
	_settings_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_note.modulate = Color(1, 1, 1, 0.7)
	left.add_child(_settings_note)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_tabs)
	var sb := HBoxContainer.new()
	left.add_child(sb)
	var save_b := Button.new()
	save_b.text = "設定を保存"
	save_b.pressed.connect(save)
	sb.add_child(save_b)
	var assets_b := Button.new()
	assets_b.text = "アセットエディタ…"
	assets_b.tooltip_text = "素材の一覧（マニフェスト）を編集します"
	assets_b.pressed.connect(func(): open_assets_requested.emit())
	sb.add_child(assets_b)
	var expr_b := Button.new()
	expr_b.text = "式エディタ…"
	expr_b.tooltip_text = "式を書いて確かめます（書いた式はコピーして使えます）"
	expr_b.pressed.connect(func(): expr_editor.open("", AdvExprEditor.MODE_CONDITION, func(t): DisplayServer.clipboard_set(t)))
	sb.add_child(expr_b)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 3
	_list_split.add_child(right)
	var rb := HBoxContainer.new()
	right.add_child(rb)
	_list_title = Label.new()
	_list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.add_child(_list_title)
	var nb := Button.new()
	nb.text = "＋ 新規作成"
	nb.pressed.connect(_on_new)
	rb.add_child(nb)
	var hint := Label.new()
	hint.text = "ダブルクリックで開く／右クリックで編集（Ctrl・Shift+クリックで複数選択、F2 で名前の変更、Delete で削除）"
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)
	_grid = AdvCardGrid.new()
	_grid.opened.connect(_on_card_opened)
	_grid.menu_requested.connect(_on_card_menu)
	_grid.item_renamed.connect(_on_card_renamed)
	_grid.delete_requested.connect(_ask_delete)
	right.add_child(_grid)
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	return _list_split


func _build_scene_page() -> Control:
	var split := HSplitContainer.new()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3
	split.add_child(left)
	var lt := Label.new()
	lt.text = "シーン共通の設定（背景、もの、出口、スプライトなど）"
	left.add_child(lt)
	_scene_form = AdvSchemaForm.new()
	_scene_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_form.changed.connect(func(): _dirty = true)
	left.add_child(_scene_form)
	var sb := HBoxContainer.new()
	left.add_child(sb)
	var save_b := Button.new()
	save_b.text = "シーンを保存"
	save_b.pressed.connect(save)
	sb.add_child(save_b)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2
	split.add_child(right)
	var dl := Label.new()
	dl.text = "セリフ（このチャプターの会話と、このシナリオの Ink）"
	right.add_child(dl)
	var dr := HBoxContainer.new()
	right.add_child(dr)
	_dlg_kind = OptionButton.new()
	_dlg_kind.add_item("JSON")
	_dlg_kind.add_item("INK")
	dr.add_child(_dlg_kind)
	var db := Button.new()
	db.text = "セリフを作成"
	db.pressed.connect(_on_new_dialogue)
	dr.add_child(db)
	var dd := Button.new()
	dd.text = "削除"
	dd.pressed.connect(_on_delete_dialogue)
	dr.add_child(dd)
	_dlg_list = ItemList.new()
	_dlg_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dlg_list.custom_minimum_size = Vector2(0, 120)
	_dlg_list.item_activated.connect(func(i): _open_dialogue(_dlg_list.get_item_metadata(i)))
	right.add_child(_dlg_list)
	var cl := Label.new()
	cl.text = "コマンド（入ったときの手順と、動詞ごとの反応）"
	right.add_child(cl)
	var cr := HBoxContainer.new()
	right.add_child(cr)
	var cb := Button.new()
	cb.text = "コマンドを作成"
	cb.pressed.connect(func(): _open_command({"target": "scene", "key": ""}))
	cr.add_child(cb)
	var cd := Button.new()
	cd.text = "削除"
	cd.pressed.connect(_on_delete_command)
	cr.add_child(cd)
	_cmd_list = ItemList.new()
	_cmd_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cmd_list.custom_minimum_size = Vector2(0, 160)
	_cmd_list.item_activated.connect(func(i): _open_command(_cmd_list.get_item_metadata(i)))
	right.add_child(_cmd_list)
	return split


func _build_dialogue_page() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = "会話ID"
	row.add_child(l)
	_dlg_id = LineEdit.new()
	_dlg_id.custom_minimum_size = Vector2(240, 0)
	_dlg_id.text_changed.connect(func(_t): _dirty = true)
	row.add_child(_dlg_id)
	var sv := Button.new()
	sv.text = "保存"
	sv.pressed.connect(save)
	row.add_child(sv)
	var cp := Button.new()
	cp.name = "Compile"
	cp.text = "Ink をコンパイル"
	cp.tooltip_text = "inklecate で .ink.json を作ります（エディタ設定 adv80s/inklecate_path）"
	cp.pressed.connect(_compile_ink)
	row.add_child(cp)
	_dlg_msg = Label.new()
	_dlg_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dlg_msg.clip_text = true
	row.add_child(_dlg_msg)
	_dlg_steps = AdvStepEditor.new()
	_dlg_steps.changed.connect(func(): _dirty = true)
	box.add_child(_dlg_steps)
	_ink_code = CodeEdit.new()
	_ink_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ink_code.gutters_draw_line_numbers = true
	_ink_code.text_changed.connect(func(): _dirty = true)
	box.add_child(_ink_code)
	return box


func _build_command_page() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = "対象"
	row.add_child(l)
	_cmd_target = OptionButton.new()
	_cmd_target.custom_minimum_size = Vector2(240, 0)
	_cmd_target.item_selected.connect(func(_i):
		_dirty = true
		_cmd_verb_row.visible = not String(_cmd_targets[_cmd_target.selected]) in ["enter", "first"])
	row.add_child(_cmd_target)
	var ao := Button.new()
	ao.text = "＋ もの"
	ao.tooltip_text = "シーンに、調べられるもの・人物を足します"
	ao.pressed.connect(func(): _ask("新しいもののID（英数字と _）", "", func(t): _add_target("objects", t)))
	row.add_child(ao)
	var ae := Button.new()
	ae.text = "＋ 出口"
	ae.tooltip_text = "シーンに出口を足します（行き先のシーンID）"
	ae.pressed.connect(func(): _ask("行き先のシーンID", "", func(t): _add_target("exits", t)))
	row.add_child(ae)
	var sv := Button.new()
	sv.text = "保存"
	sv.pressed.connect(save)
	row.add_child(sv)
	_cmd_verb_row = HBoxContainer.new()
	box.add_child(_cmd_verb_row)
	var vl := Label.new()
	vl.text = "動詞"
	_cmd_verb_row.add_child(vl)
	_cmd_verb = OptionButton.new()
	_cmd_verb.custom_minimum_size = Vector2(180, 0)
	_cmd_verb.item_selected.connect(func(_i): _dirty = true)
	_cmd_verb_row.add_child(_cmd_verb)
	var wl := Label.new()
	wl.text = "＋ 使うもの（USE+ドア のように。なければ空）"
	_cmd_verb_row.add_child(wl)
	_cmd_with = LineEdit.new()
	_cmd_with.custom_minimum_size = Vector2(160, 0)
	_cmd_with.text_changed.connect(func(_t): _dirty = true)
	_cmd_verb_row.add_child(_cmd_with)
	var hint := Label.new()
	hint.text = "手順：「＋ 手順を追加」から、地の文・台詞・条件分岐・選択肢などを足します。条件と変数の計算は「式…」で式エディタを開けます。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	_cmd_steps = AdvStepEditor.new()
	_cmd_steps.changed.connect(func(): _dirty = true)
	box.add_child(_cmd_steps)
	return box


func _build_dialogs() -> void:
	_copy_dialog = ConfirmationDialog.new()
	_copy_dialog.title = "複写"
	var cb := VBoxContainer.new()
	cb.name = "Box"
	_copy_dialog.add_child(cb)
	var r1 := HBoxContainer.new()
	cb.add_child(r1)
	var l1 := Label.new()
	l1.text = "いくつ作るか（1つずつ）"
	r1.add_child(l1)
	_copy_count = SpinBox.new()
	_copy_count.min_value = 1
	_copy_count.max_value = 99
	_copy_count.value = 1
	r1.add_child(_copy_count)
	var r2 := HBoxContainer.new()
	r2.name = "ToScenario"
	cb.add_child(r2)
	var l2 := Label.new()
	l2.text = "複写先のシナリオ"
	r2.add_child(l2)
	_copy_scenario = OptionButton.new()
	_copy_scenario.item_selected.connect(func(_i): _fill_copy_chapters())
	r2.add_child(_copy_scenario)
	var r3 := HBoxContainer.new()
	r3.name = "ToChapter"
	cb.add_child(r3)
	var l3 := Label.new()
	l3.text = "複写先のチャプター"
	r3.add_child(l3)
	_copy_chapter = OptionButton.new()
	r3.add_child(_copy_chapter)
	_copy_dialog.confirmed.connect(_do_copy)
	add_child(_copy_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "削除"
	_delete_dialog.confirmed.connect(_do_delete)
	add_child(_delete_dialog)

	_ask_dialog = ConfirmationDialog.new()
	_ask_edit = LineEdit.new()
	_ask_edit.custom_minimum_size = Vector2(300, 0)
	_ask_dialog.add_child(_ask_edit)
	_ask_dialog.register_text_enter(_ask_edit)
	_ask_dialog.confirmed.connect(func():
		var t := _ask_edit.text.strip_edges()
		if t != "" and _ask_done.is_valid():
			_ask_done.call(t))
	add_child(_ask_dialog)


func _ask(title: String, value: String, done: Callable) -> void:
	_ask_dialog.title = title
	_ask_edit.text = value
	_ask_done = done
	_ask_dialog.popup_centered()
	_ask_edit.grab_focus.call_deferred()


# ---------------------------------------------------------------- 画面の切り替え

func _show(p: int) -> void:
	if _dirty and p != page:
		save()   # ほかの画面へ移るときは、書いたものを保存する
	page = p
	_dirty = false
	for k in _pages:
		var shown: bool = k == p or (k == Page.GAME and p in [Page.GAME, Page.SCENARIO, Page.CHAPTER])
		_pages[k].visible = shown
	match p:
		Page.ROOT:
			_root_edit.text = model.root if model.root != "" else AdvScenarioModel.DEFAULT_ROOT
		Page.GAME, Page.SCENARIO, Page.CHAPTER:
			_fill_list()
		Page.SCENE:
			_fill_scene()
		Page.DIALOGUE:
			_fill_dialogue()
		Page.COMMAND:
			_fill_command()
	_dirty = false
	_fill_crumbs()


func _fill_crumbs() -> void:
	for c in _crumbs.get_children():
		_crumbs.remove_child(c)
		c.queue_free()
	var parts := []
	if page != Page.ROOT:
		parts.append(["ゲーム", Page.GAME])
	if page >= Page.SCENARIO and sid != "":
		parts.append([String(model.scenario(sid).get("name", sid)), Page.SCENARIO])
	if page >= Page.CHAPTER and cid != "":
		parts.append([String(model.chapter(sid, cid).get("name", cid)), Page.CHAPTER])
	if page >= Page.SCENE and scene_id != "":
		parts.append([_scene_name(), Page.SCENE])
	if page == Page.DIALOGUE:
		parts.append(["セリフ：" + String(dlg.get("id", "")), Page.DIALOGUE])
	if page == Page.COMMAND:
		parts.append(["コマンド：" + _cmd_label(cmd) if String(cmd.get("key", "")) != "" or cmd.get("target") in ["enter", "first"] else "新しいコマンド", Page.COMMAND])
	var root_b := Button.new()
	root_b.text = "フォルダ"
	root_b.flat = true
	root_b.tooltip_text = "シナリオのフォルダ：%s" % model.root
	root_b.pressed.connect(func(): _show(Page.ROOT))
	_crumbs.add_child(root_b)
	for i in parts.size():
		var sep := Label.new()
		sep.text = "›"
		_crumbs.add_child(sep)
		var b := Button.new()
		b.text = String(parts[i][0])
		b.flat = true
		b.disabled = i == parts.size() - 1
		var to: int = parts[i][1]
		b.pressed.connect(func(): _show(to))
		_crumbs.add_child(b)


func _set_status(t: String) -> void:
	_status.text = t
	status.emit(t)


func _on_root_decided() -> void:
	var err := model.set_root(_root_edit.text)
	if err != OK:
		_set_status("フォルダを作れません（%s）" % error_string(err))
		return
	model.sync_project()
	_set_status("シナリオのフォルダ：%s" % model.root)
	_show(Page.GAME)


# ---------------------------------------------------------------- 一覧

func _fill_list() -> void:
	var schema_name := "project" if page == Page.GAME else "scenario"
	var tabs: Array = GAME_TABS if page == Page.GAME else SCENARIO_TABS
	var hidden: Array = GAME_HIDDEN if page == Page.GAME else SCENARIO_HIDDEN
	var items := []
	_settings_note.text = ""
	match page:
		Page.GAME:
			_settings_data = AdvScenarioModel._load(model.project_path)
			_list_title.text = "シナリオ（%s）" % model.root
			for s in model.scenarios():
				var n := model.chapters(s["id"]).size()
				items.append({"id": s["id"], "name": s["name"], "sub": "%s ・ チャプター %d" % [s["id"], n]})
			_settings_note.text = "ゲーム全体の設定（%s）。シナリオの一覧はシナリオエディタが書きます。" % model.project_path
		Page.SCENARIO:
			_settings_data = model.load_scenario_data(sid)
			_list_title.text = "チャプター"
			for c in model.chapters(sid):
				items.append({"id": c["id"], "name": c["name"], "sub": "%s ・ シーン %d" % [c["id"], c["scenes"]]})
			if model.scenario(sid).get("loose", false):
				_settings_note.text = "フォルダに分けていないファイルです。設定は、それぞれのチャプターで書いてください。"
			else:
				_settings_note.text = "このシナリオの全チャプターで使う設定（%s）。" % AdvScenarioModel.MAIN_FILE
		Page.CHAPTER:
			_settings_data = model.load_chapter_data(sid, cid)
			_list_title.text = "シーン"
			for s in model.scenes(sid, cid):
				items.append({"id": s["id"], "name": s["name"], "sub": "%s%s" % [s["id"], "" if s.get("image") == null else " ・ " + str(s["image"])]})
			_settings_note.text = "このチャプターの設定（%s）。" % model.chapter_path(sid, cid).get_file()
			tabs = tabs.map(func(t): return [t[0], (t[1] as Array).filter(func(k): return k != "start")])
	_build_tabs(AdvSchemaValidator.load_schema(schema_name), tabs, hidden, _settings_data)
	_tabs.visible = not (page == Page.SCENARIO and model.scenario(sid).get("loose", false))
	_grid.set_items(items)


## 設定のタブを作る。タブごとに、その項目だけのスキーマでフォームを作る。
func _build_tabs(schema: Dictionary, tabs: Array, hidden: Array, data: Dictionary) -> void:
	var cur := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tab_forms.clear()
	var used := {}
	for t in tabs:
		for k in t[1]:
			used[k] = true
	var rest := []
	for k in schema.get("properties", {}):
		if not used.has(k) and not k in hidden:
			rest.append(k)
	var all := tabs + [["その他", rest]]
	for t in all:
		var keys: Array = t[1]
		var f := AdvSchemaForm.new()
		f.name = String(t[0])
		f.suggest = _suggest
		var value := {}
		for k in keys:
			if data.has(k):
				value[k] = data[k]
		f.setup(sub_schema(schema, keys), AdvSchemaForm.normalize(value))
		f.changed.connect(func(): _dirty = true)
		_tabs.add_child(f)
		_tab_forms.append({"form": f, "keys": keys})
	if cur >= 0 and cur < _tabs.get_tab_count():
		_tabs.current_tab = cur


## スキーマの項目 keys だけを持つスキーマ（definitions も持たせて $ref を読めるようにする）。
static func sub_schema(schema: Dictionary, keys: Array) -> Dictionary:
	var props := {}
	for k in keys:
		if schema.get("properties", {}).has(k):
			props[k] = schema["properties"][k]
	return {"type": "object", "properties": props, "additionalProperties": false, "definitions": schema.get("definitions", {})}


## タブのフォームの値を、設定のデータに戻す。
func _merge_tabs(data: Dictionary) -> Dictionary:
	for t in _tab_forms:
		var v: Dictionary = t["form"].data if t["form"].data is Dictionary else {}
		for k in t["keys"]:
			if v.has(k):
				data[k] = v[k]
			else:
				data.erase(k)
	return data


func _level() -> String:
	return {Page.GAME: "scenario", Page.SCENARIO: "chapter", Page.CHAPTER: "scene"}.get(page, "")


func _on_new() -> void:
	var id := ""
	match page:
		Page.GAME:
			id = model.create_scenario("新しいシナリオ")
		Page.SCENARIO:
			id = model.create_chapter(sid, "新しいチャプター")
		Page.CHAPTER:
			id = model.create_scene(sid, cid, "新しいシーン")
	if id == "":
		_set_status("作れませんでした")
		return
	_fill_list()
	_grid.select_only(id)
	_grid.begin_rename(id)
	_set_status("作りました：%s" % id)
	_refresh_expr_candidates()


func _on_card_opened(id: String) -> void:
	match page:
		Page.GAME:
			sid = id
			_show(Page.SCENARIO)
		Page.SCENARIO:
			cid = id
			_show(Page.CHAPTER)
		Page.CHAPTER:
			scene_id = id
			_show(Page.SCENE)


func _on_card_renamed(id: String, name: String) -> void:
	var ids := [id]
	match page:
		Page.SCENARIO:
			ids = [sid, id]
		Page.CHAPTER:
			ids = [sid, cid, id]
	var err := model.rename(_level(), ids, name)
	_set_status("名前を変えました：%s" % name if err == OK else "名前を変えられません（%s）" % error_string(err))
	_fill_list()


func _on_card_menu(ids: Array, at: Vector2) -> void:
	_menu_ids = ids
	_menu.clear()
	var one := ids.size() == 1
	_menu.add_item("開く", MENU_OPEN)
	_menu.set_item_disabled(_menu.get_item_index(MENU_OPEN), not one)
	_menu.add_item("名前を変更", MENU_RENAME)
	_menu.set_item_disabled(_menu.get_item_index(MENU_RENAME), not one)
	_menu.add_item("新規作成", MENU_NEW)
	_menu.add_separator()
	_menu.add_item("複写…", MENU_DUP)
	_menu.set_item_disabled(_menu.get_item_index(MENU_DUP), ids.is_empty())
	if page != Page.GAME:
		_menu.add_item("別の%sへ複写…" % ("シナリオ" if page == Page.SCENARIO else "シナリオ・チャプター"), MENU_COPY_TO)
		_menu.set_item_disabled(_menu.get_item_index(MENU_COPY_TO), ids.is_empty())
	_menu.add_separator()
	_menu.add_item("削除", MENU_DELETE)
	_menu.set_item_disabled(_menu.get_item_index(MENU_DELETE), ids.is_empty())
	_menu.reset_size()
	_menu.popup(Rect2i(Vector2i(get_screen_position() + at - global_position), Vector2i.ZERO))


func _on_menu(id: int) -> void:
	match id:
		MENU_OPEN:
			_on_card_opened(String(_menu_ids[0]))
		MENU_RENAME:
			_grid.begin_rename(String(_menu_ids[0]))
		MENU_NEW:
			_on_new()
		MENU_DUP:
			_ask_copy(false)
		MENU_COPY_TO:
			_ask_copy(true)
		MENU_DELETE:
			_ask_delete(_menu_ids)


func _ask_copy(to_other: bool) -> void:
	_copy_to_other = to_other
	_copy_count.value = 1
	_copy_dialog.title = "%d 件を複写" % _menu_ids.size()
	_copy_dialog.get_node("Box/ToScenario").visible = to_other
	_copy_dialog.get_node("Box/ToChapter").visible = to_other and page == Page.CHAPTER
	_copy_scenario.clear()
	var list := model.scenarios()
	for s in list:
		if page == Page.SCENARIO and s["id"] == sid:
			continue
		_copy_scenario.add_item(String(s["name"]))
		_copy_scenario.set_item_metadata(_copy_scenario.item_count - 1, s["id"])
	_fill_copy_chapters()
	_copy_dialog.popup_centered()


func _fill_copy_chapters() -> void:
	_copy_chapter.clear()
	if _copy_scenario.selected < 0:
		return
	for c in model.chapters(String(_copy_scenario.get_item_metadata(_copy_scenario.selected))):
		_copy_chapter.add_item(String(c["name"]))
		_copy_chapter.set_item_metadata(_copy_chapter.item_count - 1, c["id"])


func _do_copy() -> void:
	var n := int(_copy_count.value)
	var to_s := String(_copy_scenario.get_item_metadata(_copy_scenario.selected)) if _copy_to_other and _copy_scenario.selected >= 0 else ""
	var to_c := String(_copy_chapter.get_item_metadata(_copy_chapter.selected)) if _copy_to_other and _copy_chapter.selected >= 0 else ""
	if _copy_to_other and (to_s == "" or (page == Page.CHAPTER and to_c == "")):
		_set_status("複写先を選んでください")
		return
	var made := []
	match page:
		Page.GAME:
			made = model.duplicate_scenarios(_menu_ids, n)
		Page.SCENARIO:
			made = model.duplicate_chapters(sid, _menu_ids, n, to_s)
		Page.CHAPTER:
			made = model.duplicate_scenes(sid, cid, _menu_ids, n, to_s, to_c)
	_set_status("%d 件を複写しました%s" % [made.size(), "（%s へ）" % to_s if to_s != "" else ""])
	_fill_list()
	_refresh_expr_candidates()


func _ask_delete(ids: Array) -> void:
	if ids.is_empty():
		return
	_menu_ids = ids
	var what := {Page.GAME: "シナリオ（フォルダごと）", Page.SCENARIO: "チャプター（ファイル）", Page.CHAPTER: "シーン"}.get(page, "")
	_delete_dialog.dialog_text = "%s %d 件を削除します。\n%s\n%s" % [what, ids.size(), "、".join(ids),
		"ファイルは OS のごみ箱へ移します。" if page != Page.CHAPTER else "シーンはチャプターのファイルから消えます（元に戻すには、ファイルを戻してください）。"]
	_delete_dialog.popup_centered()


func _do_delete() -> void:
	match page:
		Page.GAME:
			model.delete_scenarios(_menu_ids)
		Page.SCENARIO:
			model.delete_chapters(sid, _menu_ids)
		Page.CHAPTER:
			model.delete_scenes(sid, cid, _menu_ids)
	_set_status("%d 件を削除しました" % _menu_ids.size())
	_fill_list()
	_refresh_expr_candidates()


# ---------------------------------------------------------------- シーン

func _scene_name() -> String:
	for s in model.scenes(sid, cid):
		if s["id"] == scene_id:
			return String(s["name"])
	return scene_id


func _load_scene() -> Dictionary:
	var d := model.load_chapter_data(sid, cid)
	if String(d.get("scene", "")) == scene_id:
		return AdvScenarioModel._single_scene_body(d)
	var v = d.get("scenes", {}).get(scene_id)
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


func _save_scene(scene: Dictionary) -> Error:
	var d := model.load_chapter_data(sid, cid)
	if String(d.get("scene", "")) == scene_id:
		for k in ["name", "image", "image_transition", "first", "enter", "objects", "exits", "sprites", "on", "ext"]:
			d.erase(k)
		d.merge(scene, true)
	else:
		var sc: Dictionary = d.get("scenes", {})
		sc[scene_id] = scene
		d["scenes"] = sc
	return model.save_chapter_data(sid, cid, d)


## シーンの設定のスキーマ（手順の項目 on・first・enter は、コマンドエディタで書くので出さない）。
static func scene_schema() -> Dictionary:
	var root := AdvSchemaValidator.load_schema("scenario")
	var s: Dictionary = (root["properties"]["scenes"]["additionalProperties"] as Dictionary).duplicate(true)
	var props: Dictionary = s["properties"]
	for k in SCENE_STEP_KEYS:
		props.erase(k)
	var obj = props.get("objects", {}).get("additionalProperties")
	if obj is Dictionary:
		obj.get("properties", {}).erase("on")
	var ex = props.get("exits", {}).get("additionalProperties")
	if ex is Dictionary:
		for b in ex.get("anyOf", []):
			if b is Dictionary and b.has("properties"):
				b["properties"].erase("on")
	s["definitions"] = root.get("definitions", {})
	return s


## シーンの定義から、手順（on・first・enter と、もの・出口の on）を除いたもの。
static func strip_steps(scene: Dictionary) -> Dictionary:
	var out := scene.duplicate(true)
	for k in SCENE_STEP_KEYS:
		out.erase(k)
	for group in ["objects", "exits"]:
		if out.get(group) is Dictionary:
			for id in out[group]:
				if out[group][id] is Dictionary:
					out[group][id].erase("on")
	return out


## フォームで書いた設定に、元の手順を戻す。
static func merge_steps(form_value: Dictionary, original: Dictionary) -> Dictionary:
	var out := form_value.duplicate(true)
	for k in SCENE_STEP_KEYS:
		if original.has(k):
			out[k] = original[k]
	for group in ["objects", "exits"]:
		if not original.get(group) is Dictionary or not out.get(group) is Dictionary:
			continue
		for id in out[group]:
			var o = original[group].get(id)
			if o is Dictionary and o.has("on"):
				if out[group][id] is bool:
					out[group][id] = {}
				if out[group][id] is Dictionary:
					out[group][id]["on"] = o["on"]
	return out


func _fill_scene() -> void:
	_scene_data = _load_scene()
	_scene_form.setup(scene_schema(), AdvSchemaForm.normalize(strip_steps(_scene_data)))
	_scene_form.suggest = _suggest
	# セリフ
	_dlg_list.clear()
	for id in model.load_chapter_data(sid, cid).get("dialogues", {}):
		_dlg_list.add_item("JSON：%s" % id)
		_dlg_list.set_item_metadata(_dlg_list.item_count - 1, {"kind": "json", "id": String(id)})
	for f in _ink_files():
		_dlg_list.add_item("INK：%s" % f.get_file().trim_suffix(".ink"))
		_dlg_list.set_item_metadata(_dlg_list.item_count - 1, {"kind": "ink", "id": f.get_file().trim_suffix(".ink"), "path": f})
	# コマンド
	_cmd_list.clear()
	for c in commands_of(_scene_data):
		_cmd_list.add_item(_cmd_label(c))
		_cmd_list.set_item_metadata(_cmd_list.item_count - 1, c)


## シーンのコマンド（手順）の一覧 [{target, key}]。
static func commands_of(scene: Dictionary) -> Array:
	var out := []
	for k in ["first", "enter"]:
		if scene.has(k):
			out.append({"target": k, "key": ""})
	for verb in scene.get("on", {}):
		out.append({"target": "scene", "key": String(verb)})
	for group in [["objects", "obj:"], ["exits", "exit:"]]:
		var g = scene.get(group[0], {})
		if not g is Dictionary:
			continue
		for id in g:
			if g[id] is Dictionary:
				for verb in g[id].get("on", {}):
					out.append({"target": group[1] + String(id), "key": String(verb)})
	return out


func _cmd_label(c: Dictionary) -> String:
	var t := String(c.get("target", ""))
	var k := String(c.get("key", ""))
	match t:
		"first":
			return "初めて入ったとき"
		"enter":
			return "入ったとき"
		"scene":
			return "シーン：%s" % k
	if t.begins_with("obj:"):
		var o = _scene_data.get("objects", {}).get(t.substr(4), {})
		return "もの %s：%s" % [String(o.get("label", t.substr(4))) if o is Dictionary else t.substr(4), k]
	if t.begins_with("exit:"):
		return "出口 %s：%s" % [t.substr(5), k]
	return "%s：%s" % [t, k]


func _ink_files() -> Array:
	var s := model.scenario(sid)
	var dir := String(s.get("dir", "")) + "/ink"
	var out := []
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".ink"):
				out.append(dir + "/" + f)
	out.sort()
	return out


func _on_new_dialogue() -> void:
	var ink := _dlg_kind.selected == 1
	_ask("新しいセリフ（会話）のID", "", func(id: String):
		id = AdvSetup.to_id(id) if AdvSetup.to_id(id) != "my_game" else id
		if ink:
			var s := model.scenario(sid)
			if s.get("loose", true):
				_set_status("Ink のセリフは、フォルダに分けたシナリオで作れます")
				return
			var path := String(s["dir"]) + "/ink/" + id + ".ink"
			if FileAccess.file_exists(path):
				_set_status("もうあります：%s" % path)
				return
			AdvScenarioModel._save_text(path, "=== %s ===\nここに セリフを かきます。\n-> DONE\n" % id)
			_open_dialogue({"kind": "ink", "id": id, "path": path})
		else:
			var d := model.load_chapter_data(sid, cid)
			var dl: Dictionary = d.get("dialogues", {})
			if dl.has(id) or model.all_dialogue_ids().has(id):
				_set_status("その会話IDは、もう使われています：%s" % id)
				return
			dl[id] = []
			d["dialogues"] = dl
			model.save_chapter_data(sid, cid, d)
			_refresh_expr_candidates()
			_open_dialogue({"kind": "json", "id": id}))


func _on_delete_dialogue() -> void:
	var sel := _dlg_list.get_selected_items()
	if sel.is_empty():
		return
	var m: Dictionary = _dlg_list.get_item_metadata(sel[0])
	if m["kind"] == "json":
		var d := model.load_chapter_data(sid, cid)
		d.get("dialogues", {}).erase(m["id"])
		model.save_chapter_data(sid, cid, d)
	else:
		AdvScenarioModel._trash(String(m["path"]))
		AdvScenarioModel._trash(String(m["path"]) + ".json")
		model.sync_project()
	_set_status("セリフを削除しました：%s" % m["id"])
	_fill_scene()


func _on_delete_command() -> void:
	var sel := _cmd_list.get_selected_items()
	if sel.is_empty():
		return
	var c: Dictionary = _cmd_list.get_item_metadata(sel[0])
	_scene_data = _load_scene()
	_set_command_steps(_scene_data, c, null)
	_save_scene(_scene_data)
	_set_status("コマンドを削除しました：%s" % _cmd_label(c))
	_fill_scene()


# ---------------------------------------------------------------- セリフ

func _open_dialogue(m: Dictionary) -> void:
	if _dirty:
		save()
	dlg = m
	_show(Page.DIALOGUE)


func _fill_dialogue() -> void:
	var ink := String(dlg.get("kind")) == "ink"
	_dlg_steps.visible = not ink
	_ink_code.visible = ink
	_dlg_id.editable = not ink
	_dlg_id.text = String(dlg.get("id", ""))
	(_pages[Page.DIALOGUE].find_child("Compile", true, false) as Button).visible = ink
	_dlg_msg.text = ""
	if ink:
		_ink_code.text = FileAccess.get_file_as_string(String(dlg["path"]))
		_dlg_msg.text = String(dlg["path"])
	else:
		_dlg_steps.set_steps(model.load_chapter_data(sid, cid).get("dialogues", {}).get(dlg["id"], []))


func _save_dialogue() -> Error:
	if String(dlg.get("kind")) == "ink":
		var err := AdvScenarioModel._save_text(String(dlg["path"]), _ink_code.text)
		_dlg_msg.text = "保存しました（ゲームで使うには「Ink をコンパイル」）" if err == OK else "保存できません"
		return err
	var d := model.load_chapter_data(sid, cid)
	var old := String(dlg["id"])
	var id := _dlg_id.text.strip_edges()
	if id == "":
		id = old
	var dl: Dictionary = d.get("dialogues", {})
	if id != old and (dl.has(id) or model.all_dialogue_ids().has(id)):
		_set_status("その会話IDは、もう使われています：%s" % id)
		id = old
	# 名前を変えても、並び順はそのまま
	var out := {}
	for k in dl:
		out[id if k == old else k] = _dlg_steps.get_steps() if k == old else dl[k]
	if not dl.has(old):
		out[id] = _dlg_steps.get_steps()
	d["dialogues"] = out
	dlg["id"] = id
	var err := model.save_chapter_data(sid, cid, d)
	if id != old:
		_refresh_expr_candidates()
		_set_status("会話IDを変えました（呼んでいる手順の ID は変わりません）：%s → %s" % [old, id])
	return err


## Ink をコンパイルする（inklecate のパスはエディタ設定 adv80s/inklecate_path）。
func _compile_ink() -> void:
	if _dirty:
		save()
	var exe := ""
	if Engine.is_editor_hint():
		var es := EditorInterface.get_editor_settings()
		if es != null and es.has_setting("adv80s/inklecate_path"):
			exe = String(es.get_setting("adv80s/inklecate_path"))
		elif es != null:
			es.set_setting("adv80s/inklecate_path", "")
			es.set_initial_value("adv80s/inklecate_path", "", false)
	if exe == "" or not FileAccess.file_exists(exe):
		_dlg_msg.text = "inklecate が見つかりません。エディタ設定の adv80s/inklecate_path に inklecate の場所を書いてください。"
		return
	var src := ProjectSettings.globalize_path(String(dlg["path"]))
	var out := []
	var code := OS.execute(exe, ["-o", src + ".json", src], out, true)
	if code == 0:
		model.sync_project()
		_dlg_msg.text = "コンパイルしました：%s.json" % String(dlg["path"]).get_file()
		if Engine.is_editor_hint() and EditorInterface.get_resource_filesystem() != null:
			EditorInterface.get_resource_filesystem().scan()
	else:
		_dlg_msg.text = "コンパイルできません：%s" % "\n".join(out).strip_edges().get_slice("\n", 0)


# ---------------------------------------------------------------- コマンド

func _open_command(c: Dictionary) -> void:
	if _dirty:
		save()
	cmd = c.duplicate()
	_show(Page.COMMAND)


func _fill_command() -> void:
	_scene_data = _load_scene()
	_cmd_target.clear()
	_cmd_targets = ["enter", "first", "scene"]
	for t in ["入ったとき", "初めて入ったとき", "シーン全体"]:
		_cmd_target.add_item(t)
	for id in _scene_data.get("objects", {}):
		_cmd_targets.append("obj:" + String(id))
		var o = _scene_data["objects"][id]
		_cmd_target.add_item("もの：%s" % (String(o.get("label", id)) if o is Dictionary else String(id)))
	for id in _scene_data.get("exits", {}):
		_cmd_targets.append("exit:" + String(id))
		_cmd_target.add_item("出口：%s" % id)
	var ti := _cmd_targets.find(String(cmd.get("target", "scene")))
	_cmd_target.select(maxi(ti, 0))
	_cmd_verb_row.visible = not String(cmd.get("target")) in ["enter", "first"]
	# 動詞：標準・プロジェクト・シナリオの動詞
	_cmd_verbs = []
	var std = AdvJson.load_file("res://addons/adv80s/data/intent_schema.standard.json")
	if std is Dictionary:
		_cmd_verbs.append_array(std.get("verbs", {}).keys())
	for v in AdvScenarioModel._load(model.project_path).get("verbs", []):
		if not v in _cmd_verbs:
			_cmd_verbs.append(String(v))
	for v in model.load_scenario_data(sid).get("verbs", {}):
		if not v in _cmd_verbs:
			_cmd_verbs.append(String(v))
	var key := String(cmd.get("key", ""))
	var verb := key.get_slice("+", 0)
	if verb != "" and not verb in _cmd_verbs:
		_cmd_verbs.append(verb)
	_cmd_verb.clear()
	for v in _cmd_verbs:
		_cmd_verb.add_item(String(v))
	_cmd_verb.select(maxi(_cmd_verbs.find(verb if verb != "" else "LOOK"), 0))
	_cmd_with.text = key.get_slice("+", 1) if key.contains("+") else ""
	_cmd_steps.set_steps(_get_command_steps(_scene_data, cmd))


func _current_cmd() -> Dictionary:
	var t := String(_cmd_targets[_cmd_target.selected])
	if t in ["enter", "first"]:
		return {"target": t, "key": ""}
	var key := String(_cmd_verbs[_cmd_verb.selected]) if _cmd_verb.selected >= 0 else "LOOK"
	if _cmd_with.text.strip_edges() != "":
		key += "+" + _cmd_with.text.strip_edges()
	return {"target": t, "key": key}


static func _get_command_steps(scene: Dictionary, c: Dictionary) -> Variant:
	var t := String(c.get("target", ""))
	if t in ["enter", "first"]:
		return scene.get(t, [])
	var on = _on_of(scene, t, false)
	return on.get(String(c.get("key", "")), []) if on is Dictionary else []


## コマンドの手順を書く（steps が null なら消す）。
static func _set_command_steps(scene: Dictionary, c: Dictionary, steps: Variant) -> void:
	var t := String(c.get("target", ""))
	if t in ["enter", "first"]:
		if steps == null:
			scene.erase(t)
		else:
			scene[t] = steps
		return
	var on = _on_of(scene, t, steps != null)
	if not on is Dictionary:
		return
	if steps == null:
		on.erase(String(c["key"]))
	else:
		on[String(c["key"])] = steps


static func _on_of(scene: Dictionary, target: String, create: bool) -> Variant:
	var holder: Dictionary = scene
	if target.begins_with("obj:") or target.begins_with("exit:"):
		var group := "objects" if target.begins_with("obj:") else "exits"
		var id := target.get_slice(":", 1)
		var g = scene.get(group)
		if not g is Dictionary or not g.has(id):
			return null
		if g[id] is bool:
			if not create:
				return null
			g[id] = {}
		holder = g[id]
	if not holder.has("on"):
		if not create:
			return null
		holder["on"] = {}
	return holder["on"]


func _save_command() -> Error:
	_scene_data = _load_scene()
	var now := _current_cmd()
	var old_key := String(cmd.get("key", ""))
	if (old_key != "" or cmd.get("target") in ["enter", "first"]) and (now["target"] != cmd["target"] or now["key"] != old_key):
		_set_command_steps(_scene_data, cmd, null)
	_set_command_steps(_scene_data, now, _cmd_steps.get_steps())
	cmd = now
	return _save_scene(_scene_data)


func _add_target(group: String, id: String) -> void:
	_scene_data = _load_scene()
	var g: Dictionary = _scene_data.get(group, {})
	if g.has(id):
		_set_status("もうあります：%s" % id)
	else:
		g[id] = {"names": [id], "label": id, "on": {}} if group == "objects" else {"label": id, "on": {}}
		_scene_data[group] = g
		_save_scene(_scene_data)
	var keep_steps := _cmd_steps.get_steps()
	cmd = {"target": ("obj:" if group == "objects" else "exit:") + id, "key": ""}
	_fill_command()
	_cmd_steps.set_steps(keep_steps)
	_dirty = true


# ---------------------------------------------------------------- 保存

## いまの画面で書いたものを保存する（Ctrl+S でも）。
func save() -> void:
	var err := OK
	match page:
		Page.GAME:
			var p := _merge_tabs(AdvScenarioModel._load(model.project_path))
			err = AdvScenarioModel._save_json(model.project_path, p)
		Page.SCENARIO:
			if model.scenario(sid).get("loose", false):
				return
			err = model.save_scenario_data(sid, _merge_tabs(model.load_scenario_data(sid)))
		Page.CHAPTER:
			err = model.save_chapter_data(sid, cid, _merge_tabs(model.load_chapter_data(sid, cid)))
		Page.SCENE:
			var v: Dictionary = _scene_form.data if _scene_form.data is Dictionary else {}
			err = _save_scene(merge_steps(v, _load_scene()))
		Page.DIALOGUE:
			err = _save_dialogue()
		Page.COMMAND:
			err = _save_command()
		_:
			return
	_dirty = false
	if err == OK:
		_set_status("保存しました")
		_refresh_expr_candidates()
		if Engine.is_editor_hint() and EditorInterface.get_resource_filesystem() != null:
			EditorInterface.get_resource_filesystem().scan()
	else:
		_set_status("保存できません（%s）" % error_string(err))
	if page == Page.COMMAND or page == Page.DIALOGUE:
		_fill_crumbs()


func is_dirty() -> bool:
	return _dirty


# ---------------------------------------------------------------- 候補

func _refresh_expr_candidates() -> void:
	if expr_editor != null:
		expr_editor.candidates = AdvExprEditor.collect_candidates(model)


func _suggest(path: Array) -> Array:
	if path.is_empty():
		return []
	var last := str(path[path.size() - 1])
	if path == ["start"] or path == ["entry"]:
		return model.all_scene_ids().keys()
	if path == ["template"] or (path.size() == 2 and path[0] == "templates"):
		return _template_ids()
	if path.size() == 2 and path[0] == "exits":
		return model.all_scene_ids().keys()
	if last == "character" or (path.size() >= 2 and path[0] == "characters"):
		return model.load_scenario_data(sid).get("characters", {}).keys()
	return []


static func _template_ids() -> Array:
	var out := []
	for dir in AdvTemplate.SEARCH_DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			if FileAccess.file_exists("%s/%s/template.json" % [dir, sub]) and not sub in out:
				out.append(sub)
	return out
