@tool
extends ScrollContainer
## セットアップ画面（6.7）。新しいゲームの初期設定を入力して、プロジェクト設定・素材フォルダ・エントリポイントを作る。
## 中身の処理は AdvSetup。エディタの「adv80s」画面で「セットアップ」を選ぶと出る。
## adv80s.project.json がまだないプロジェクトでは、最初にこの画面が出る。

signal applied(result: Dictionary)

var project_path: String = AdvProject.DEFAULT_PATH

var _game_id: LineEdit
var _title: LineEdit
var _template: OptionButton
var _command: OptionButton
var _command_note: Label
var _devices: Dictionary = {}     ## 機器 → CheckBox
var _base_dir: LineEdit
var _main_scene: CheckBox
var _display: CheckBox
var _preview: Label
var _result: RichTextLabel
var _apply: Button
var _templates: Array = []
var _id_edited: bool = false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var head := Label.new()
	head.text = "新しいゲームのセットアップ"
	head.add_theme_font_size_override("font_size", 18)
	box.add_child(head)
	var lead := Label.new()
	lead.text = "ゲームの基本の設定を決めると、プロジェクト設定、素材フォルダ、最初のシナリオ、メインシーンを作ります。すでにあるファイルは上書きしません（プロジェクト設定は、ここの項目だけ書き換えます）。"
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lead)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	_title = LineEdit.new()
	_title.placeholder_text = "例：やかたの なぞ"
	_title.text_changed.connect(_on_title_changed)
	_row(grid, "タイトル", _title, "ゲームの名前です。ウィンドウのタイトルにも使います。")

	_game_id = LineEdit.new()
	_game_id.placeholder_text = "例：yakata_no_nazo"
	_game_id.text_changed.connect(func(_t): _id_edited = true; _refresh())
	_row(grid, "ゲームID", _game_id, "ほかのゲームと重ならない名前です（英小文字で始まる英小文字・数字・_）。セーブデータの見分けに使います。")

	_template = OptionButton.new()
	_template.item_selected.connect(func(_i): _refresh())
	_row(grid, "画面テンプレート", _template, "画面の解像度、色、窓の並びを決める機種のテンプレートです。あとから変えられます。")

	_command = OptionButton.new()
	for s in AdvSetup.COMMAND_STYLES:
		_command.add_item(String(s["label"]))
	_command.item_selected.connect(func(_i): _refresh())
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_child(_command)
	_command_note = Label.new()
	_command_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command_note.modulate = Color(1, 1, 1, 0.7)
	cbox.add_child(_command_note)
	_row(grid, "コマンド方式", cbox, "遊ぶ人がコマンドを選ぶ方法です。")

	var dbox := HBoxContainer.new()
	for dv in AdvSetup.DEVICES:
		var cb := CheckBox.new()
		cb.text = String(AdvSetup.DEVICE_LABELS[dv])
		cb.button_pressed = true
		cb.toggled.connect(func(_on): _refresh())
		dbox.add_child(cb)
		_devices[dv] = cb
	_row(grid, "入力デバイス", dbox, "遊ぶときに使える入力機器です。外した機器の操作は受け付けません。")

	_base_dir = LineEdit.new()
	_base_dir.text = "res://game"
	_base_dir.text_changed.connect(func(_t): _refresh())
	_row(grid, "作成先のフォルダ", _base_dir, "素材フォルダ（assets）、シナリオ（scenario）、メインシーン（main.tscn）を作るフォルダです。")

	var obox := VBoxContainer.new()
	_main_scene = CheckBox.new()
	_main_scene.text = "作ったメインシーンを、実行するシーンにする"
	_main_scene.button_pressed = true
	obox.add_child(_main_scene)
	_display = CheckBox.new()
	_display.text = "画面の大きさとストレッチの設定を、テンプレートに合わせる"
	_display.button_pressed = true
	obox.add_child(_display)
	_row(grid, "Godot の設定", obox, "Godot のプロジェクト設定（メインシーン、ウィンドウ）も合わせて書き換えます。")

	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_preview)

	var bar := HBoxContainer.new()
	box.add_child(bar)
	_apply = Button.new()
	_apply.text = "作成する"
	_apply.pressed.connect(_on_apply)
	bar.add_child(_apply)

	_result = RichTextLabel.new()
	_result.fit_content = true
	_result.bbcode_enabled = false
	_result.selection_enabled = true
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_result)


func _row(grid: GridContainer, label: String, control: Control, tip: String) -> void:
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = tip
	grid.add_child(control)


## いまのプロジェクトの値を入れ直す。
func reload() -> void:
	var d := AdvSetup.defaults(project_path)
	_templates = AdvSetup.template_list()
	_template.clear()
	for i in _templates.size():
		var t: Dictionary = _templates[i]
		_template.add_item("%s　%s（%dx%d）" % [t["id"], t["name"], t["size"].x, t["size"].y])
		if t["id"] == d["template"]:
			_template.select(i)
	_title.text = String(d["title"])
	_game_id.text = String(d["game_id"])
	_id_edited = FileAccess.file_exists(project_path)
	for i in AdvSetup.COMMAND_STYLES.size():
		if AdvSetup.COMMAND_STYLES[i]["id"] == d["command"]:
			_command.select(i)
	for dv in _devices:
		(_devices[dv] as CheckBox).button_pressed = dv in d["devices"]
	_base_dir.text = String(d["base_dir"])
	_result.text = ""
	_refresh()


## 画面の入力から、AdvSetup に渡す設定を作る。
func options() -> Dictionary:
	var tid := String(_templates[_template.selected]["id"]) if _template.selected >= 0 and _template.selected < _templates.size() else ""
	return {
		"game_id": _game_id.text.strip_edges(),
		"title": _title.text.strip_edges(),
		"template": tid,
		"command": String(AdvSetup.COMMAND_STYLES[maxi(0, _command.selected)]["id"]),
		"devices": AdvSetup.DEVICES.filter(func(dv): return (_devices[dv] as CheckBox).button_pressed),
		"base_dir": _base_dir.text.strip_edges(),
		"set_main_scene": _main_scene.button_pressed,
		"set_display": _display.button_pressed,
	}


func _on_title_changed(text: String) -> void:
	if not _id_edited:
		_game_id.text = AdvSetup.to_id(text)
	_refresh()


func _refresh() -> void:
	var opts := options()
	_command_note.text = String(AdvSetup.command_style(String(opts["command"]))["note"])
	var errs := AdvSetup.check(opts)
	_apply.disabled = not errs.is_empty()
	if not errs.is_empty():
		_preview.text = "\n".join(errs)
		_preview.modulate = Color(1.0, 0.6, 0.5)
		return
	_preview.modulate = Color(1, 1, 1, 0.8)
	var pl := AdvSetup.plan(opts, project_path)
	var lines := PackedStringArray(["作るもの（すでにあるものは残します）："])
	lines.append("・%s（プロジェクト設定%s）" % [project_path, "。いまの設定に書き足します" if FileAccess.file_exists(project_path) else ""])
	lines.append("・%s/（素材フォルダ：%s）" % [pl["assets"], "、".join(AdvSetup.ASSET_DIRS)])
	lines.append("・%s（シナリオ共通の設定）" % pl["scenario_main"])
	lines.append("・%s（最初のチャプター）" % pl["scenario"])
	lines.append("・%s（メインシーン。ゲームの入口）" % pl["scene"])
	_preview.text = "\n".join(lines)


func _on_apply() -> void:
	var opts := options()
	var res := AdvSetup.apply(opts, project_path, true)
	var lines := PackedStringArray()
	if not (res["errors"] as Array).is_empty():
		lines.append("できなかったこと：")
		for e in res["errors"]:
			lines.append("・" + String(e))
	else:
		lines.append("セットアップが終わりました。F5 で実行できます。")
	for key in [["created", "作ったファイル"], ["updated", "書き換えたファイル"], ["skipped", "すでにあったので残したファイル"]]:
		var list: Array = res.get(key[0], []).filter(func(p): return not String(p).ends_with(".gitkeep"))
		if not list.is_empty():
			lines.append("%s：" % key[1])
			for p in list:
				lines.append("・" + String(p))
	if (res["errors"] as Array).is_empty() and bool(opts["set_display"]):
		lines.append("画面の大きさの設定は、エディタを開き直すと確実に反映されます。")
	_result.text = "\n".join(lines)
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.scan()
	applied.emit(res)
	_refresh()
