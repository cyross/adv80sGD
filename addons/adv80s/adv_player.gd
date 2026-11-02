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
##   F1・右クリック・ゲームパッドの Start  メニュー   F6  調べられる場所の表示の切り替え

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
## 全プレイ共通の進行の記録のファイル（空なら保存しない）
@export var progress_path: String = AdvProgress.PATH

var project: AdvProject
var core: AdvCore
var display: AdvDisplay
var screen: AdvScreen
var template: AdvTemplate
var features: AdvFeatures
var settings: AdvSettings
var message_log: AdvMessageLog = AdvMessageLog.new()
var key_provider: AdvKeyProvider
var progress: AdvProgress
var modern: AdvModernUI
var audio: AdvAudio

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
var _flow_pending: PackedStringArray = []  ## flow.mark で到達した点（ひとまとまり実行し終えたら記録する）
var _history: Array = []                   ## 巻き戻し用の記録 [{data, log_size}]
var _show_all_hotspots: bool = false
var _last_voice: String = ""            ## 直前の voice.play（次の text.show のログに付ける）
var _request: Dictionary = {}          ## 聞き返し中（input.request）の引数


func _ready() -> void:
	var diags: Array = []
	project = AdvProject.load_project(project_path, diags)
	settings = AdvSettings.load_settings(settings_path) if settings_path != "" else AdvSettings.new()
	progress = AdvProgress.load_progress(progress_path)
	modern = AdvModernUI.new(self)
	core = AdvCore.new()
	core.setup(project.core_config())
	core.progress = progress
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

	audio = AdvAudio.new()
	audio.name = "Audio"
	add_child(audio)
	apply_volumes()
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
	screen.hotspot_layer.hotspot_clicked.connect(_on_hotspot_clicked)
	if features.is_on("readable_font") and template.get_section("fonts").has("readable"):
		screen.set_readable(true)


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


func save_settings() -> void:
	_save_settings()


## 音量（プレイヤー設定）を反映する。
func apply_volumes() -> void:
	audio.bgm_volume = float(settings.get_value("bgm_volume", 1.0))
	audio.se_volume = float(settings.get_value("se_volume", 1.0))
	audio.voice_volume = float(settings.get_value("voice_volume", 1.0))
	audio.apply_volumes()


## モダン機能を実行時に切り替える（プロジェクトで禁止したものは変えられない）。
func set_feature(key: String, on: bool) -> void:
	if not features.allowed.get(key, true):
		return
	var f: Dictionary = settings.get_value("features", {})
	f[key] = on
	settings.set_value("features", f)
	_save_settings()
	_resolve_features()
	match key:
		"readable_font":
			screen.set_readable(features.is_on("readable_font"))
		"tts":
			if not features.is_on("tts") and _tts_available():
				DisplayServer.tts_stop()
	if not busy:
		_enter_idle()


## 登録したテンプレート（プロジェクト設定 templates）を順に切り替える（旧表示と新表示の切り替え）。
func cycle_template() -> void:
	var list: Array = project.get_value("templates", [])
	if list.size() < 2:
		return
	var i := list.find(template.id)
	await switch_template(String(list[(i + 1) % list.size()]))


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
	_request = {}
	_push_history()
	var label := String(intent.get("ext", {}).get("label", ""))
	if label != "":
		message_log.add_input(label)
		message_log.entries.back()["rewind"] = _history.size() - 1
	_run(core.submit(intent))


## コマンド入力の文字列を読む（テンプレートの inputs.parser_profile："ja"、"en"、またはスクリプトのパス）。
func parse_text(text: String) -> Dictionary:
	return AdvParsers.parse(String(template.get_section("inputs").get("parser_profile", "ja")), text, core)


## コマンド入力の文字列を送る。
func submit_text(text: String) -> void:
	if busy or ended or _overlay != null:
		return
	if core.query("pending_choice") != null:
		return
	_push_history()
	message_log.add_input(text)
	message_log.entries.back()["rewind"] = _history.size() - 1
	if not _request.is_empty():
		# 聞き返しへの答え：動詞を足して読み、埋まっていたスロットと合わせる
		var req := _request
		_request = {}
		var r2 := parse_text("%s %s" % [text, core.dictionary.verb_label(String(req["verb"]))])
		if r2.has("intent") and String(r2["intent"]["verb"]) == String(req["verb"]):
			var it: Dictionary = r2["intent"]
			var filled: Dictionary = req.get("intent", {}).get("slots", {})
			for k in filled:
				if not it["slots"].has(k):
					it["slots"][k] = filled[k]
			_run(core.submit(it))
			return
	var r := parse_text(text)
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
	if not _flow_pending.is_empty():
		var snap := _make_save_data()
		for node in _flow_pending:
			progress.mark_reached(node, snap)
		_flow_pending.clear()
	progress.merge_read(core.state.read)
	if progress_path != "":
		progress.save()
	_enter_idle()


## 入力を待つ状態にする。選択肢を出しているときは、選択肢だけを選べるようにする。
func _enter_idle() -> void:
	var choice = core.query("pending_choice")
	_apply_input_modes()
	_set_inputs_enabled(true)
	if choice is Dictionary:
		if screen.command_select != null:
			screen.command_select.show_choices(choice.get("choices", []))
		if screen.command_line != null:
			screen.command_line.set_enabled(false)
	else:
		if screen.command_select != null:
			screen.command_select.refresh(core)
			if not _request.is_empty():
				screen.command_select.start_request(String(_request["verb"]), _request.get("intent", {}).get("slots", {}), String(_request["slot"]))
		if screen.command_line != null and screen.command_line.visible and not auto_click:
			screen.command_line.grab_focus()
	_refresh_hotspots()
	idle.emit()


## 入力UIの切り替え（テンプレートの inputs.enabled、出力イベント input.mode）。
func _apply_input_modes() -> void:
	var modes = core.state.ui.get("input_modes")
	if not modes is Array:
		modes = template.get_section("inputs").get("enabled", ["select", "parser"])
	if screen.command_line != null:
		screen.command_line.visible = "parser" in modes and template.region_rect("input").size != Vector2i.ZERO
	if screen.command_select != null:
		screen.command_select.get_parent().visible = ("select" in modes or "icon" in modes) and template.region_rect("commands").size != Vector2i.ZERO
		screen.command_select.icons = "icon" in modes
		screen.command_select.show_tried = features.is_on("tried_marks")
	var click: bool = "click" in modes
	screen.hotspot_layer.mouse_filter = Control.MOUSE_FILTER_STOP if click or features.is_on("hotspot") else Control.MOUSE_FILTER_IGNORE
	screen.hotspot_layer.set_meta("click", click)


func _refresh_hotspots() -> void:
	var hs = core.query("hotspots")
	var layer := screen.hotspot_layer
	layer.set_hotspots(hs if hs is Array else [])
	layer.show_hover = features.is_on("hotspot")
	layer.show_all = _show_all_hotspots and features.is_on("hotspot")
	layer.show_new = features.is_on("tried_marks")
	layer.queue_redraw()


## 画面選択：コマンド選択で対象を選んでいる途中ならその対象に、そうでなければ既定の動詞で調べる。
func _on_hotspot_clicked(h: Dictionary) -> void:
	if busy or _overlay != null or not bool(screen.hotspot_layer.get_meta("click", false)):
		return
	var t := {"type": String(h.get("type", "object")), "id": String(h.get("target", h["id"])), "label": String(h.get("label", h["id"]))}
	if screen.command_select != null and screen.command_select.is_picking():
		screen.command_select.pick_target(t)
		return
	var verb := String(template.get_section("inputs").get("click_verb", "EXAMINE"))
	submit_intent({"verb": verb, "slots": {"target": {"type": t["type"], "id": t["id"]}}, "source": "click",
		"ext": {"label": "%s %s" % [t["label"], core.dictionary.verb_label(verb)]}})


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
			var voice := String(args.get("voice", _last_voice))
			_last_voice = ""
			if args.has("voice") and not skipping:
				_play_voice(voice)
			_last_text = {"body": raw, "name": who}
			message_log.add_text(AdvTextMarkup.to_plain(raw, core.state, template), who, String(ev.get("id", "")), voice)
			screen.show_text(AdvTextMarkup.to_bbcode(raw, core.state, template), who, skipping)
			if features.is_on("tts") and not skipping and not audio.is_voice_playing():
				_speak(raw, who)
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
			if name == "palette_cycle":
				var dur := float(args.get("duration", 0.0))
				var job := display.palette_cycle.bind(args.get("range", []), float(args.get("speed", 4.0)), dur)
				if dur > 0.0 and wait is String and wait == "end":
					await job.call()
				else:
					job.call()
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
		"flow.mark":
			_flow_pending.append(String(args.get("node", "")))
		"bgm.play":
			var id := String(args.get("id", ""))
			var path := core.assets.resolve("bgm", id)
			if path == "" and core.assets.report_missing("bgm", id):
				ended = true
				return
			var e := core.assets.entry("bgm", id)
			audio.play_bgm(id, path, bool(args.get("loop", true)), float(args.get("fade", 0.0)),
				float(args.get("volume", 1.0)) * float(e.get("volume", 1.0)), float(e.get("loop_start", 0.0)))
		"bgm.stop":
			audio.stop_bgm(float(args.get("fade", 0.0)))
		"se.play":
			if not skipping:
				var id := String(args.get("id", ""))
				var path := core.assets.resolve("se", id)
				if path == "" and core.assets.report_missing("se", id):
					ended = true
					return
				if path != "":
					audio.play_se(path, float(args.get("volume", 1.0)) * float(core.assets.entry("se", id).get("volume", 1.0)))
				if wait is String and wait == "end":
					await get_tree().create_timer((load(path) as AudioStream).get_length() if path != "" else 0.0).timeout
					wait = "none"
		"voice.play":
			_last_voice = String(args.get("id", ""))
			if not skipping:
				_play_voice(_last_voice)
		"checkpoint":
			if features.is_on("autosave") and bool(args.get("autosave", true)) and "checkpoint" in _autosave_on():
				_autosave_pending = true
		"notebook.add", "objective.set", "hint.set", "verbs.update", "hotspots.update", "input.mode":
			pass  # 状態は Core が記録する。表示は入力待ちになったときに更新する
		"choice.show":
			var prompt := String(args.get("prompt", ""))
			if prompt != "":
				_last_text = {"body": prompt, "name": ""}
				message_log.add_text(AdvTextMarkup.to_plain(prompt, core.state, template))
				screen.show_text(AdvTextMarkup.to_bbcode(prompt, core.state, template), "", skipping)
			skip_mode = false
			wait = "none"   # 選択肢は _enter_idle で出す（入力待ちでは必ず止まる）
		"input.request":
			_request = args.duplicate(true)
			var prompt := String(args.get("prompt", ""))
			if prompt != "":
				_last_text = {"body": prompt, "name": ""}
				message_log.add_text(AdvTextMarkup.to_plain(prompt, core.state, template))
				screen.show_text(AdvTextMarkup.to_bbcode(prompt, core.state, template), "", true)
			wait = "none"   # 候補は _enter_idle で出す
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
			if not AdvEvents.is_state_event(ev) and not type in ["wait", "flow.mark"]:
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
	if bool(settings.get_value("voice_stop_on_advance", true)):
		audio.stop_voice()


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
			KEY_F1:
				modern.open_system_menu()
			KEY_F6:
				_show_all_hotspots = not _show_all_hotspots
				_refresh_hotspots()
			_:
				pass
		if event.keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F9, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			modern.open_system_menu()
			get_viewport().set_input_as_handled()
			return
		# ゲームパッドで操作し始めたら、入力欄からコマンドの一覧へ移る
		if not busy and screen.command_line != null and screen.command_line.has_focus() and screen.command_select != null:
			screen.command_select.focus_first()
	if not busy:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			modern.open_system_menu()
			get_viewport().set_input_as_handled()
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
	v.open(message_log, template, Vector2(template.screen_size), features.is_on("rewind") and not busy)
	v.rewind_requested.connect(func(i: int): v.close(); rewind_to(i))
	v.voice_requested.connect(_play_voice)
	await show_overlay(v)


## 画面全体に重ねる画面（ログ、セーブ、メニューなど）を出し、閉じるまで待つ。
func show_overlay(c: Control) -> void:
	if _overlay != null:
		_overlay.call("close")
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
	await show_overlay(m)


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


## セーブするデータ（巻き戻しとフローチャートの記録にも同じ形を使う）。
func _make_save_data() -> Dictionary:
	var sc = core.query("scene")
	return {
		"save_version": 1,
		"meta": {
			"time": int(Time.get_unix_time_from_system()),
			"scene": core.state.scene,
			"scene_name": String(sc.get("name", "")) if sc is Dictionary else "",
		},
		"core": core.save_state(),
		"log": message_log.to_array(),
		"view": {"template": template.id, "layout": template._layout_name, "images": _images.duplicate(true),
			"text": _last_text.duplicate(), "bgm": audio.current_bgm.duplicate()},
	}


## セーブする。実行中（busy）は、選択肢の入力待ちのときだけセーブできる。
func save_game(slot: String) -> Error:
	var cfg := _save_cfg()
	var data := _make_save_data()
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
	_history.clear()
	await _apply_save_data(res["data"])
	loaded.emit(slot)
	return ""


## セーブと同じ形のデータから、状態と画面を戻す。
func _apply_save_data(data: Dictionary) -> void:
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
	var bgm: Dictionary = view.get("bgm", {})
	if bgm.is_empty():
		audio.stop_bgm()
	else:
		var bid := String(bgm["id"])
		var e := core.assets.entry("bgm", bid)
		audio.play_bgm(bid, core.assets.resolve("bgm", bid), bool(bgm.get("loop", true)), 0.0,
			float(bgm.get("volume", 1.0)), float(e.get("loop_start", 0.0)))
	ended = false
	_enter_idle()


# ---------------------------------------------------------------- 巻き戻し、フローチャート、読み上げ

## 入力を送る直前の状態を残す（モダン機能 rewind）。
func _push_history() -> void:
	if not features.is_on("rewind"):
		return
	_history.append({"data": _make_save_data(), "log_size": message_log.entries.size()})
	var max_steps := int(features.options.get("rewind", {}).get("max_steps", 100))
	while _history.size() > max_steps:
		_history.pop_front()
		for e in message_log.entries:
			if e.has("rewind"):
				e["rewind"] = int(e["rewind"]) - 1


func can_rewind() -> bool:
	return features.is_on("rewind") and not _history.is_empty()


## steps 回分の入力の前まで戻す。
func rewind(steps: int = 1) -> void:
	if busy or _history.is_empty():
		return
	rewind_to(maxi(0, _history.size() - steps))


## 記録の index 番目（その入力を送る直前）まで戻す。
func rewind_to(index: int) -> void:
	if busy or index < 0 or index >= _history.size():
		return
	var h: Dictionary = _history[index]
	_history.resize(index)
	await _apply_save_data(h["data"])


## フローチャートやチャプター選択で、到達した点から再開する。
func jump_to_node(node: String) -> void:
	if busy or not progress.snapshots.has(node):
		return
	_history.clear()
	await _apply_save_data(progress.snapshots[node])


func _play_voice(id: String) -> void:
	if id == "":
		return
	var path := core.assets.resolve("voice", id)
	if path == "":
		core.assets.report_missing("voice", id)
		return
	audio.play_voice(path, float(core.assets.entry("voice", id).get("volume", 1.0)))


## 文章を読み上げる（モダン機能 tts）。ルビのある語はルビで読む。
func _speak(body: String, speaker_name: String) -> void:
	if not _tts_available():
		return
	var voices := DisplayServer.tts_get_voices_for_language(String(project.get_value("lang", "ja")))
	if voices.is_empty():
		voices = DisplayServer.tts_get_voices().map(func(v): return v["id"])
	if voices.is_empty():
		return
	var text := AdvTextMarkup.to_speech(body, core.state)
	if speaker_name != "":
		text = speaker_name + "。" + text
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, String(voices[0]))


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
