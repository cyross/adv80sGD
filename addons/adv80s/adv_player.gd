class_name AdvPlayer
extends Control
## ゲームを動かすノード。Core、シナリオアダプタ、画面、入力UIをつなぎ、出力イベントを順に実行する。
##
## シーンに置いて、template_id と scenario_paths を設定すれば動く。

signal game_ended
signal idle   ## 出力イベントを実行し終えて、入力を待つ状態になった

## プロジェクト設定（adv80s.project.json）。下の項目を空にしておくと、ここに書いた値を使う
@export_file("*.json") var project_path: String = AdvProject.DEFAULT_PATH
## 画面テンプレートのID（空ならプロジェクト設定の template）
@export var template_id: String = ""
## シナリオファイル（空ならプロジェクト設定の scenarios）
@export var scenario_paths: PackedStringArray = []
## 追加の素材フォルダ（プロジェクト設定の asset_roots の後に重ねる）
@export var assets_root: String = ""
## 開始シーン（空ならプロジェクト設定の entry、それも空ならシナリオの start）
@export var entry: String = ""
## テスト用：クリック待ちを自動で進める
@export var auto_click: bool = false

var project: AdvProject
var core: AdvCore
var screen: AdvScreen
var template: AdvTemplate
var features: AdvFeatures
var busy: bool = false
var ended: bool = false

var _click_pending: bool = false


func _ready() -> void:
	var diags: Array = []
	project = AdvProject.load_project(project_path, diags)
	core = AdvCore.new()
	core.setup(project.core_config())
	core.assets.folders = project.asset_folders()

	var tid := template_id if template_id != "" else String(project.get_value("template", "pc98_classic"))
	template = AdvTemplate.load_template(tid, diags)
	if template == null:
		_report(diags)
		return
	core.preset = String(template.preset.get("id", "98"))
	core.group = String(template.preset.get("group", ""))
	core.assets.set_preset(core.preset, core.group)

	# 素材フォルダ：プロジェクト → テンプレート → シナリオ
	var roots: Array = project.get_value("asset_roots", []).duplicate()
	if assets_root != "":
		roots.append(assets_root)
	var troot := template.asset_root()
	if troot != "":
		roots.append(troot)
	core.add_asset_roots(roots)

	core.use_adapter(AdvJsonAdapter.new())
	var paths := scenario_paths if not scenario_paths.is_empty() else PackedStringArray(project.get_value("scenarios", []))
	core.load_scenario(paths)
	var sroots = core.query("asset_roots")
	if sroots is PackedStringArray or sroots is Array:
		core.add_asset_roots(Array(sroots))

	var env := {
		"templates": max(1, project.get_value("templates", []).size()),
		"readable_font": template.get_section("fonts").has("readable"),
		"tts": _tts_available(),
		"touch": DisplayServer.is_touchscreen_available(),
	}
	features = AdvFeatures.resolve(project.get_value("features", {}), template.get_section("features"), env, {}, diags)
	core.features = features.enabled

	diags.append_array(core.validate())
	_report(diags)

	screen = AdvScreen.new()
	screen.name = "Screen"
	add_child(screen)
	screen.build(template)
	if screen.command_select != null:
		screen.command_select.intent_selected.connect(submit_intent)
	if screen.command_line != null:
		screen.command_line.command_entered.connect(submit_text)
	var start_at := entry if entry != "" else String(project.get_value("entry", ""))
	_run(core.start(start_at))


func _report(diags: Array) -> void:
	for d in diags:
		var line := "[adv80s] %s %s: %s (%s %s)" % [d["severity"], d["code"], d["message"], d.get("file", ""), d.get("path", "")]
		match String(d["severity"]):
			"error": push_error(line)
			"warning": push_warning(line)


static func _tts_available() -> bool:
	# 読み上げはプロジェクト設定 audio/general/text_to_speech が有効なときだけ使える
	if DisplayServer.get_name() == "headless" or not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return false
	return not DisplayServer.tts_get_voices().is_empty()


## 意図を送る（入力UIから呼ぶ）。
func submit_intent(intent: Dictionary) -> void:
	if busy or ended:
		return
	_run(core.submit(intent))


## コマンド入力の文字列を送る。
func submit_text(text: String) -> void:
	if busy or ended:
		return
	var r := AdvParserJa.parse(text, core)
	if r.has("reply"):
		_run([AdvEvents.text(String(r["reply"]))])
	else:
		submit_intent(r["intent"])


func _run(events: Array) -> void:
	busy = true
	_set_inputs_enabled(false)
	for ev in events:
		await _play(ev)
		if ended:
			break
	busy = false
	if ended:
		game_ended.emit()
		return
	_set_inputs_enabled(true)
	if screen.command_select != null:
		screen.command_select.refresh(core)
	if screen.command_line != null and not auto_click:
		screen.command_line.grab_focus()
	idle.emit()


func _set_inputs_enabled(on: bool) -> void:
	if screen.command_select != null:
		screen.command_select.set_enabled(on)
	if screen.command_line != null:
		screen.command_line.set_enabled(on)


## 出力イベントを1つ実行する。
func _play(ev: Dictionary) -> void:
	var args: Dictionary = ev.get("args", {})
	var type := String(ev.get("type", ""))
	match type:
		"text.show":
			var body := AdvTextMarkup.to_bbcode(String(args.get("body", "")), core.state, template)
			screen.show_text(body, String(args.get("name", args.get("speaker", ""))))
		"text.clear":
			screen.clear_text()
		"image.show":
			var id := String(args.get("id", ""))
			var path := core.assets.resolve("image", id, String(args.get("variant", "")))
			if path == "" and core.assets.report_missing("image", id):
				ended = true
				return
			screen.show_image(String(args.get("layer", "bg")), id, path)
		"image.hide":
			screen.hide_image(String(args.get("layer", "bg")))
		"group":
			for sub in args.get("events", []):
				await _play(sub)
		"game.end":
			ended = true
			return
		_:
			if not AdvEvents.is_state_event(ev) and not type in ["wait", "voice.play"]:
				AdvDiag.debug_warn("UNSUPPORTED", "段階1ではまだ実行できない出力イベントです: %s" % type,
					"Output event not supported yet: %s" % type)
	await _wait(AdvEvents.wait_of(ev))


func _wait(w: Variant) -> void:
	if w is String:
		match w:
			"click":
				await _wait_click()
			"end":
				while screen.is_typing():
					await get_tree().process_frame
	elif w is float or w is int:
		if float(w) > 0.0:
			await get_tree().create_timer(float(w)).timeout


func _wait_click() -> void:
	_click_pending = false
	while screen.is_typing():
		if _click_pending or auto_click:
			screen.complete_text()
			_click_pending = false
			break
		await get_tree().process_frame
	screen.set_wait_mark(true)
	_click_pending = false
	while not _click_pending and not auto_click:
		await get_tree().process_frame
	_click_pending = false
	screen.set_wait_mark(false)


## 実行中（busy）のクリックとキーは、すべて「次へ進む」として扱う。
func _input(event: InputEvent) -> void:
	if not busy:
		return
	var pressed := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	elif event.is_action_pressed("ui_accept"):
		pressed = true
	if pressed:
		_click_pending = true
		get_viewport().set_input_as_handled()
