class_name AdvPlayer
extends Control
## ゲームを動かすノード。Core、シナリオアダプタ、画面、入力UIをつなぎ、出力イベントを順に実行する。
##
## シーンに置いて、template_id と scenario_paths を設定すれば動く。

signal game_ended
signal idle   ## 出力イベントを実行し終えて、入力を待つ状態になった

@export var template_id: String = "pc98_classic"
@export var scenario_paths: PackedStringArray = []
## 素材フォルダ（フォルダの決まりに従って自動でIDを付ける）
@export var assets_root: String = ""
## 開始シーン（空ならシナリオの start）
@export var entry: String = ""
## テスト用：クリック待ちを自動で進める
@export var auto_click: bool = false

var core: AdvCore
var screen: AdvScreen
var template: AdvTemplate
var busy: bool = false
var ended: bool = false

var _click_pending: bool = false


func _ready() -> void:
	core = AdvCore.new()
	core.setup({})
	if assets_root != "":
		core.assets.scan(assets_root)
	core.use_adapter(AdvJsonAdapter.new())
	core.load_scenario(scenario_paths)
	for d in core.validate():
		var line := "[adv80s] %s %s: %s (%s %s)" % [d["severity"], d["code"], d["message"], d["file"], d["path"]]
		if d["severity"] == "error":
			push_error(line)
		elif d["severity"] == "warning":
			push_warning(line)

	var diags := []
	template = AdvTemplate.load_template(template_id, diags)
	for d in diags:
		push_error("[adv80s] %s: %s" % [d["code"], d["message"]])
	if template == null:
		return
	core.preset = String(template.preset.get("id", "98"))
	core.group = String(template.preset.get("group", ""))

	screen = AdvScreen.new()
	screen.name = "Screen"
	add_child(screen)
	screen.build(template)
	if screen.command_select != null:
		screen.command_select.intent_selected.connect(submit_intent)
	if screen.command_line != null:
		screen.command_line.command_entered.connect(submit_text)
	_run(core.start(entry))


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
			screen.show_image(String(args.get("layer", "bg")), id, core.assets.resolve("image", id))
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
