class_name AdvPlayer
extends Control
## ゲームを動かすノード。Core、シナリオアダプタ、画面、入力UIをつなぎ、出力イベントを順に実行する。
## セーブとロード、メッセージログ、既読スキップ、オート送り、選択肢もここで扱う。
##
## シーンに置けば、プロジェクト設定（adv80s.project.json）に従って動く。
##
## 標準のキー操作：
##   クリック・Enter・Space  次へ進む          Ctrl（押している間）  スキップ
##   F2  オート送りの切り替え                   F3  スキップの切り替え
##   F4・ホイール上  メッセージログ             F5  クイックセーブ   F9  クイックロード
##   Esc  セーブ・ロードの画面（開いている画面は閉じる）

signal game_ended
signal idle                     ## 出力イベントを実行し終えて、入力を待つ状態になった
signal saved(slot: String)
signal loaded(slot: String)

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
## プレイヤー設定のファイル（空なら保存しない）
@export var settings_path: String = AdvSettings.PATH

var project: AdvProject
var core: AdvCore
var display: AdvDisplay
var screen: AdvScreen
var template: AdvTemplate
var features: AdvFeatures
var settings: AdvSettings
var message_log: AdvMessageLog = AdvMessageLog.new()
var key_provider: AdvKeyProvider

var busy: bool = false
var ended: bool = false
var skip_mode: bool = false      ## スキップを切り替えで入れている
var auto_mode: bool = false      ## オート送り
var skipping: bool = false       ## いま実行中のイベントをスキップしているか（切り替え演出は cut、画面効果は省く）

var _click_pending: bool = false
var _images: Dictionary = {}           ## 層 → {id, variant}（テンプレートの切り替えやロードで表示し直す）
var _scene_transition: Variant = null  ## scene.goto の transition（次の背景の表示に使う）
var _last_text: Dictionary = {}        ## 最後に表示した文章 {body, name}（ロードで表示し直す）
var _overlay: Control = null           ## 開いているログ画面やセーブ画面
var _autosave_pending: bool = false


func _ready() -> void:
	var diags: Array = []
	project = AdvProject.load_project(project_path, diags)
	settings = AdvSettings.load_settings(settings_path) if settings_path != "" else AdvSettings.new()
	core = AdvCore.new()
	core.setup(project.core_config())
	core.assets.folders = project.asset_folders()

	AdvVisuals.load_custom(project.get_value("effects", []), diags)
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

	_resolve_features(diags)
	key_provider = _make_key_provider(diags)
	diags.append_array(core.validate())
	_report(diags)

	display = AdvDisplay.new()
	display.name = "Display"
	add_child(display)
	screen = display.screen
	screen.resolver = func(kind: String, id: String) -> String: return core.assets.resolve(kind, id)
	_build_screen()
	var start_at := entry if entry != "" else String(project.get_value("entry", ""))
	_run(core.start(start_at))


func _resolve_features(diags: Array = []) -> void:
	var env := {
		"templates": max(1, project.get_value("templates", []).size()),
		"readable_font": template.get_section("fonts").has("readable"),
		"tts": _tts_available(),
		"touch": DisplayServer.is_touchscreen_available(),
	}
	features = AdvFeatures.resolve(project.get_value("features", {}), template.get_section("features"), env,
		settings.get_value("features", {}), diags)
	core.features = features.enabled
	message_log.max_entries = int(features.options.get("message_log", {}).get("max_entries", 500))


func _build_screen() -> void:
	display.setup(template)
	display.set_filters_enabled(bool(settings.get_value("filters", true)) or not features.is_on("filter_toggle"))
	screen.set_text_speed(float(template.get_section("text").get("speed", 40)) * float(settings.get_value("text_speed", 1.0)))
	if screen.command_select != null:
		screen.command_select.intent_selected.connect(submit_intent)
	if screen.command_line != null:
		screen.command_line.command_entered.connect(submit_text)


## 画面テンプレートを切り替える（旧表示と新表示の切り替えなど）。状態はそのままで、画面を作り直す。
func switch_template(id: String, transition: Variant = null) -> void:
	var diags := []
	var t := AdvTemplate.load_template(id, diags)
	if t == null:
		_report(diags)
		return
	var tr := AdvVisuals.resolve_transition(transition, template, _named_transitions(), false)
	if not skipping and String(tr.get("type", "cut")) in ["fade_color", "fade"]:
		await screen.play_effect("flash", {"color": String(tr.get("color", "#000000")), "duration": float(tr.get("duration", 0.5))})
	template = t
	core.preset = String(t.preset.get("id", ""))
	core.group = String(t.preset.get("group", ""))
	core.assets.set_preset(core.preset, core.group)
	_build_screen()
	_redraw_view()
	if not busy:
		_enter_idle()


## 今の状態（画像、最後の文章、選択肢）を画面に出し直す。
func _redraw_view() -> void:
	for layer in screen.layers:
		if not _images.has(layer):
			screen.hide_image(layer)
	for layer in _images:
		var im: Dictionary = _images[layer]
		screen.show_image(layer, im["id"], core.assets.resolve("image", im["id"], im.get("variant", "")))
	if _last_text.is_empty():
		screen.clear_text()
	else:
		var body := AdvTextMarkup.to_bbcode(String(_last_text.get("body", "")), core.state, template)
		screen.show_text(body, String(_last_text.get("name", "")), true)


## フィルターを切り替える（設定画面から呼ぶ）。filter_toggle が許可されていないときは何もしない。
func set_filters_enabled(on: bool) -> void:
	if features != null and not features.is_on("filter_toggle"):
		return
	display.set_filters_enabled(on)
	settings.set_value("filters", on)
	_save_settings()


## 文字速度の倍率を変える（モダン機能 text_options）。
func set_text_speed(scale: float) -> void:
	settings.set_value("text_speed", scale)
	screen.set_text_speed(float(template.get_section("text").get("speed", 40)) * scale)
	_save_settings()


func _save_settings() -> void:
	if settings_path != "":
		settings.save(settings_path)


func _named_transitions() -> Dictionary:
	return project.get_value("transitions", {}).get("named", {})


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


# ---------------------------------------------------------------- 入力

## 意図を送る（入力UIから呼ぶ）。
func submit_intent(intent: Dictionary) -> void:
	if busy or ended or _overlay != null:
		return
	var label := String(intent.get("ext", {}).get("label", ""))
	if label != "":
		message_log.add_input(label)
	_run(core.submit(intent))


## コマンド入力の文字列を送る。
func submit_text(text: String) -> void:
	if busy or ended or _overlay != null:
		return
	if core.query("pending_choice") != null:
		return
	message_log.add_input(text)
	var r := AdvParserJa.parse(text, core)
	if r.has("reply"):
		_run([AdvEvents.text(String(r["reply"]))])
	else:
		_run(core.submit(r["intent"]))


func _run(events: Array) -> void:
	busy = true
	_set_inputs_enabled(false)
	for ev in events:
		await _play(ev)
		if ended:
			break
	skipping = false
	busy = false
	if ended:
		game_ended.emit()
		return
	if _autosave_pending:
		_autosave_pending = false
		autosave()
	_enter_idle()


## 入力を待つ状態にする。選択肢を出しているときは、選択肢だけを選べるようにする。
func _enter_idle() -> void:
	var choice = core.query("pending_choice")
	_set_inputs_enabled(true)
	if choice is Dictionary:
		if screen.command_select != null:
			screen.command_select.show_choices(choice.get("choices", []))
		if screen.command_line != null:
			screen.command_line.set_enabled(false)
	else:
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


# ---------------------------------------------------------------- 出力イベント

## 出力イベントを1つ実行する。
func _play(ev: Dictionary) -> void:
	var args: Dictionary = ev.get("args", {})
	var type := String(ev.get("type", ""))
	var wait = AdvEvents.wait_of(ev)
	skipping = _skip_held()
	match type:
		"text.show":
			var was_read := bool(ev.get("ext", {}).get("was_read", false))
			if skipping and not was_read and not bool(settings.get_value("skip_unread", false)):
				# 未読の文章ではスキップを止める
				skip_mode = false
				skipping = _skip_held()
			var raw := String(args.get("body", ""))
			var who := String(args.get("name", args.get("speaker", "")))
			_last_text = {"body": raw, "name": who}
			message_log.add_text(AdvTextMarkup.to_plain(raw, core.state, template), who, String(ev.get("id", "")), String(args.get("voice", "")))
			screen.show_text(AdvTextMarkup.to_bbcode(raw, core.state, template), who, skipping)
			if skipping and wait is String and wait == "click":
				wait = "none"
		"text.clear":
			_last_text = {}
			screen.clear_text()
		"image.show", "image.hide":
			var layer := String(args.get("layer", "bg"))
			var spec = args.get("transition")
			if spec == null and layer == "bg" and _scene_transition != null:
				spec = _scene_transition
			_scene_transition = null
			var tr := _transition_for(spec)
			if not ev.has("wait"):
				wait = "none" if String(tr.get("type", "cut")) == "cut" else "end"
			var job: Callable
			if type == "image.show":
				var id := String(args.get("id", ""))
				var variant := String(args.get("variant", ""))
				var path := core.assets.resolve("image", id, variant)
				if path == "" and core.assets.report_missing("image", id):
					ended = true
					return
				_images[layer] = {"id": id, "variant": variant}
				screen.reset_layer(layer)
				job = screen.show_image.bind(layer, id, path, tr)
			else:
				_images.erase(layer)
				job = screen.hide_image.bind(layer, tr)
			if wait is String and wait == "end":
				await job.call()
				wait = "none"
			else:
				job.call()
		"effect.play":
			var name := String(args.get("name", args.get("effect", "")))
			if skipping:
				return
			if wait is String and wait == "end":
				await screen.play_effect(name, args)
				wait = "none"
			else:
				screen.play_effect(name, args)
		"scene.goto":
			_scene_transition = args.get("transition")
			if features.is_on("autosave") and "scene" in _autosave_on():
				_autosave_pending = true
			wait = "none"
		"checkpoint":
			if features.is_on("autosave") and bool(args.get("autosave", true)) and "checkpoint" in _autosave_on():
				_autosave_pending = true
		"choice.show":
			var prompt := String(args.get("prompt", ""))
			if prompt != "":
				_last_text = {"body": prompt, "name": ""}
				message_log.add_text(AdvTextMarkup.to_plain(prompt, core.state, template))
				screen.show_text(AdvTextMarkup.to_bbcode(prompt, core.state, template), "", skipping)
			skip_mode = false
			wait = "none"   # 選択肢は _enter_idle で出す（入力待ちでは必ず止まる）
		"save.request":
			await open_save_menu("save")
			wait = "none"
		"layout.set":
			template.set_layout(String(args.get("layout", "")))
			screen.apply_layout()
			wait = "none"
		"template.switch":
			await switch_template(String(args.get("template", "")), args.get("transition"))
			wait = "none"
		"group":
			for sub in args.get("events", []):
				await _play(sub)
		"game.end":
			ended = true
			return
		_:
			if not AdvEvents.is_state_event(ev) and not type in ["wait", "voice.play"]:
				AdvDiag.debug_warn("UNSUPPORTED", "まだ実行できない出力イベントです: %s" % type,
					"Output event not supported yet: %s" % type)
	if skipping and type == "wait":
		return
	await _wait(wait)


## 切り替え演出を決める（スキップ中は cut）。mask のルール画像は素材IDかパスで指定する。
func _transition_for(spec: Variant) -> Dictionary:
	if skipping:
		return {"type": "cut"}
	var tr := AdvVisuals.resolve_transition(spec, template, _named_transitions())
	if String(tr.get("type", "")) == "mask" and tr.has("image"):
		var p := core.assets.resolve("image", String(tr["image"]))
		if p != "":
			tr["rule_texture"] = load(p)
	return tr


func _wait(w: Variant) -> void:
	if w is String:
		match w:
			"click":
				await _wait_click()
			"end":
				while screen.is_typing():
					if _skip_held():
						screen.complete_text()
					await get_tree().process_frame
	elif w is float or w is int:
		if float(w) > 0.0:
			await get_tree().create_timer(float(w)).timeout


func _wait_click() -> void:
	_click_pending = false
	while screen.is_typing():
		if _click_pending or auto_click or _skip_held():
			screen.complete_text()
			_click_pending = false
			break
		await get_tree().process_frame
	if _skip_held():
		return
	screen.set_wait_mark(true)
	_click_pending = false
	var waited := 0.0
	var auto_wait := float(settings.get_value("auto_delay", 1.2)) + \
		float(settings.get_value("auto_per_char", 0.04)) * screen.message_label.get_total_character_count()
	while not _click_pending and not auto_click and not _skip_held():
		await get_tree().process_frame
		if auto_mode and _overlay == null:
			waited += get_process_delta_time()
			if waited >= auto_wait:
				break
	_click_pending = false
	screen.set_wait_mark(false)


func _skip_held() -> bool:
	if features == null or not features.is_on("skip"):
		return false
	return skip_mode or Input.is_key_pressed(KEY_CTRL)


func _autosave_on() -> Array:
	return features.options.get("autosave", {}).get("on", ["checkpoint", "scene"])


## オート送りを切り替える。
func toggle_auto() -> void:
	if features.is_on("auto_advance"):
		auto_mode = not auto_mode


## スキップを切り替える。
func toggle_skip() -> void:
	if features.is_on("skip"):
		skip_mode = not skip_mode


func _input(event: InputEvent) -> void:
	if _overlay != null:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_F4):
			_overlay.call("close")
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2:
				toggle_auto()
			KEY_F3:
				toggle_skip()
			KEY_F4:
				open_log()
			KEY_F5:
				if not busy:
					save_game("quick")
			KEY_F9:
				if not busy:
					load_game("quick")
			KEY_ESCAPE:
				if not busy:
					open_save_menu("save")
			_:
				pass
		if event.keycode in [KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F9, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			return
	if not busy:
		return
	var pressed := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	elif event.is_action_pressed("ui_accept"):
		pressed = true
	if pressed:
		_click_pending = true
		skip_mode = false
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# 画面の上でホイールを上に回すとログを開く（コマンドの一覧のスクロールが先に受け取る）
	if _overlay == null and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		open_log()


# ---------------------------------------------------------------- メッセージログ

## メッセージログの画面を開く。閉じるまで待つ（await できる）。
func open_log() -> void:
	if _overlay != null or not features.is_on("message_log"):
		return
	var v := AdvLogView.new()
	v.open(message_log, template, Vector2(template.screen_size))
	await _show_overlay(v)


func _show_overlay(c: Control) -> void:
	_overlay = c
	screen.add_child(c)
	await c.closed
	_overlay = null


# ---------------------------------------------------------------- セーブとロード

## セーブ・ロードの画面を開く。閉じるまで待つ（await できる）。
func open_save_menu(mode: String = "save") -> void:
	if _overlay != null:
		return
	var m := AdvSaveMenu.new()
	m.open(mode, list_saves(), template, Vector2(template.screen_size))
	m.slot_chosen.connect(func(md: String, slot: String):
		if md == "save":
			save_game(slot)
		else:
			load_game(slot)
		m.close())
	await _show_overlay(m)


func _save_cfg() -> Dictionary:
	return AdvJson.merge({"protection": "hmac", "on_tamper": "reject", "text_format": false,
		"dir": "user://saves", "slots": 10, "key_provider": "embedded"}, project.get_value("save", {}))


func _slot_path(slot: String) -> String:
	var cfg := _save_cfg()
	var ext := "json" if _text_allowed() and bool(cfg.get("text_format", false)) else "sav"
	return "%s/%s.%s" % [String(cfg["dir"]).trim_suffix("/"), slot, ext]


func _text_allowed() -> bool:
	return OS.is_debug_build() or bool(_save_cfg().get("text_format", false))


## スロットの一覧 [{slot, label, exists, info}]。
func list_saves() -> Array:
	var r := []
	var n := int(_save_cfg().get("slots", 10))
	var slots := PackedStringArray(["quick"])
	for i in int(features.options.get("autosave", {}).get("slots", 3)):
		slots.append("auto%d" % (i + 1))
	for i in n:
		slots.append("%02d" % (i + 1))
	for s in slots:
		var label := "クイック" if s == "quick" else ("オート%s" % s.substr(4) if s.begins_with("auto") else s)
		var info := ""
		var exists := false
		var res := _read_slot(s)
		if res["ok"]:
			exists = true
			var meta: Dictionary = res["data"].get("meta", {})
			var local := int(meta.get("time", 0)) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
			info = "%s  %s" % [Time.get_datetime_string_from_unix_time(local, true), meta.get("scene_name", "")]
		r.append({"slot": s, "label": label, "exists": exists, "info": info})
	return r


func _read_slot(slot: String) -> Dictionary:
	var cfg := _save_cfg()
	for ext in ["sav", "json"]:
		var p := "%s/%s.%s" % [String(cfg["dir"]).trim_suffix("/"), slot, ext]
		if FileAccess.file_exists(p):
			return AdvSave.decode(AdvSave.read_file(p), key_provider, _text_allowed(), String(cfg.get("on_tamper", "reject")))
	return {"ok": false, "error": AdvSave.ERR_IO, "data": {}}


## セーブする。実行中（busy）は、選択肢の入力待ちのときだけセーブできる。
func save_game(slot: String) -> Error:
	var cfg := _save_cfg()
	var data := {
		"save_version": 1,
		"meta": {
			"time": int(Time.get_unix_time_from_system()),
			"scene": core.state.scene,
			"scene_name": String((core.query("scene") if core.query("scene") is Dictionary else {}).get("name", "")),
		},
		"core": core.save_state(),
		"log": message_log.to_array(),
		"view": {"template": template.id, "layout": template._layout_name, "images": _images.duplicate(true),
			"text": _last_text.duplicate()},
	}
	var bytes: PackedByteArray
	if _text_allowed() and bool(cfg.get("text_format", false)):
		bytes = AdvSave.encode_text(data)
	else:
		bytes = AdvSave.encode(data, String(cfg.get("protection", "hmac")), key_provider)
	if bytes.is_empty():
		push_error("[adv80s] セーブできません（鍵がありません）")
		return ERR_UNAVAILABLE
	var err := AdvSave.write_file(_slot_path(slot), bytes)
	if err == OK:
		saved.emit(slot)
	return err


## オートセーブ（オートの枠を順番に使う）。
func autosave() -> void:
	var n := maxi(1, int(features.options.get("autosave", {}).get("slots", 3)))
	var oldest := 1
	var oldest_time := 1 << 62
	for i in n:
		var res := _read_slot("auto%d" % (i + 1))
		var t := int(res["data"].get("meta", {}).get("time", 0)) if res["ok"] else -1
		if t < oldest_time:
			oldest_time = t
			oldest = i + 1
	save_game("auto%d" % oldest)


## ロードする。成功したら空文字、失敗したら理由のコード（AdvSave.ERR_*）。
func load_game(slot: String) -> String:
	if busy and core.query("pending_choice") == null:
		return "BUSY"
	var res := _read_slot(slot)
	if not res["ok"]:
		push_warning("[adv80s] ロードできません: %s（%s）" % [slot, res["error"]])
		return String(res["error"])
	if res.get("warning", "") != "":
		push_warning("[adv80s] セーブデータの署名が一致しません（改ざんの疑い）。設定に従って読み込みます: %s" % slot)
	var data: Dictionary = res["data"]
	core.load_state(data.get("core", {}))
	message_log.from_array(data.get("log", []))
	var view: Dictionary = data.get("view", {})
	_images = view.get("images", {}).duplicate(true)
	_last_text = view.get("text", {}).duplicate()
	var tid := String(view.get("template", template.id))
	if tid != template.id:
		await switch_template(tid)
	template.set_layout(String(view.get("layout", "")))
	screen.apply_layout()
	_redraw_view()
	ended = false
	_enter_idle()
	loaded.emit(slot)
	return ""


## プロジェクト設定 save.key_provider に従って鍵を用意する。
func _make_key_provider(diags: Array) -> AdvKeyProvider:
	var kind := String(_save_cfg().get("key_provider", "embedded"))
	var kp: AdvKeyProvider
	match kind:
		"embedded":
			kp = AdvEmbeddedKeyProvider.new()
		"per_user":
			kp = AdvPerUserKeyProvider.new()
		_:
			var s = load(kind)
			kp = s.new() if s != null else AdvEmbeddedKeyProvider.new()
	if kp.is_available():
		return kp
	if OS.is_debug_build():
		diags.append(AdvDiag.make("warning", "NO_KEY",
			"セーブの鍵がないので、開発用の仮の鍵を使います（ツールメニュー「adv80s: セーブの鍵を生成」で作れます）",
			"No save key; using a temporary development key (create one from the Tools menu)", AdvEmbeddedKeyProvider.KEY_FILE))
		return _DevKeyProvider.new(String(ProjectSettings.get_setting("application/config/name", "adv80s")))
	diags.append(AdvDiag.make("error", "NO_KEY", "セーブの鍵がありません", "No save key", AdvEmbeddedKeyProvider.KEY_FILE))
	return kp


## 開発中だけ使う仮の鍵（製品版では使わない）。
class _DevKeyProvider extends AdvKeyProvider:
	var _k: PackedByteArray
	func _init(seed_text: String) -> void:
		_k = AdvKeyProvider.sha256(("adv80s-dev-key:" + seed_text).to_utf8_buffer())
	func get_master_key() -> PackedByteArray:
		return _k
