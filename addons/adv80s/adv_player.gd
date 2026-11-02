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
var _sprites: Dictionary = {}          ## スプライトID → いまの状態（sprite.show の引数に変更を重ねたもの。セーブと表示し直しに使う）
var _video: Dictionary = {}            ## 繰り返しの動画の引数（セーブと表示し直しに使う）
var _cursor_forced: Variant = null     ## cursor.set で固定した形（種類の文字列か {image, hotspot}）
var _cursor_kind: String = ""          ## いま出しているカーソルの種類


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

	# 素材フォルダ：アドオンの標準 → プロジェクト → テンプレート → シナリオ
	var roots: Array = []
	if DirAccess.dir_exists_absolute(AdvAssets.BUILTIN_ROOT):
		roots.append(AdvAssets.BUILTIN_ROOT)
	roots.append_array(project.get_value("asset_roots", []))
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
	if screen.command_select != null and not screen.command_select.intent_selected.is_connected(submit_intent):
		screen.command_select.intent_selected.connect(submit_intent)
	if screen.command_line != null and not screen.command_line.command_entered.is_connected(submit_text):
		screen.command_line.command_entered.connect(submit_text)
	if not screen.hotspot_layer.hotspot_clicked.is_connected(_on_hotspot_clicked):
		screen.hotspot_layer.hotspot_clicked.connect(_on_hotspot_clicked)
	screen.hotspot_layer.sprite_lookup = screen.sprite
	var ui: Dictionary = template.get_section("ui")
	screen.set_marks(_make_mark(ui.get("wait_mark")), _make_mark(ui.get("page_mark", ui.get("wait_mark"))))
	_cursor_kind = ""
	_apply_text_cursor()
	if features.is_on("readable_font") and template.get_section("fonts").has("readable"):
		screen.set_readable(true)
	apply_text_style()


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
	# 切り替え先のテンプレートの素材フォルダ（窓の枠の画像など）を重ねる
	var troot := t.asset_root()
	if troot != "" and not troot in core.assets.roots:
		core.add_asset_roots([troot])
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
		screen.show_image(layer, _image_label(im["id"]), "", {"type": "cut"}, _layer_texture(im["id"], String(im.get("variant", ""))))
	screen.clear_sprites()
	for id in _sprites:
		_restore_sprite(_sprites[id])
	screen.stop_video()
	if not _video.is_empty():
		_start_video(_video)
	if _last_text.is_empty():
		screen.clear_text()
	else:
		var conv := AdvTextMarkup.to_bbcode_stops(String(_last_text.get("body", "")), core.state, template)
		screen.show_text(conv["bbcode"], String(_last_text.get("name", "")), true, conv["stops"])


## フィルターを切り替える（設定画面から呼ぶ）。filter_toggle が許可されていないときは何もしない。
func set_filters_enabled(on: bool) -> void:
	if features != null and not features.is_on("filter_toggle"):
		return
	display.set_filters_enabled(on)
	settings.set_value("filters", on)
	_save_settings()


## 文章の表示調整を設定から反映する（モダン機能 text_options。オフなら標準の見た目）。
func apply_text_style() -> void:
	if screen == null:
		return
	if features != null and not features.is_on("text_options"):
		screen.set_text_style(1.0, -1, 1.0)
		return
	screen.set_text_style(float(settings.get_value("text_size", 1.0)), int(settings.get_value("text_color", -1)),
		float(settings.get_value("window_opacity", 1.0)))


## 文章の表示調整のひとつを変えて保存する（key は text_size、text_color、window_opacity）。
func set_text_option(key: String, value: Variant) -> void:
	settings.set_value(key, value)
	_save_settings()
	apply_text_style()


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
	var pc = core.query("pending_choice")
	if pc != null and not (pc is Dictionary and pc.get("accepts_intents", false)):
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
	var intents: bool = choice is Dictionary and choice.get("accepts_intents", false)
	if choice is Dictionary and not (intents and choice.get("choices", []).is_empty()):
		if screen.command_select != null:
			screen.command_select.show_choices(choice.get("choices", []))
		if screen.command_line != null:
			# Ink の intent タグつきの選択肢は、コマンド入力でも選べる
			screen.command_line.set_enabled(intents)
			if intents and screen.command_line.visible and not auto_click:
				screen.command_line.grab_focus()
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
	if t["type"] == "exit":
		verb = "MOVE"
		t["type"] = "scene"
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
			var conv := AdvTextMarkup.to_bbcode_stops(raw, core.state, template)
			screen.show_text(conv["bbcode"], who, skipping, conv["stops"])
			if features.is_on("tts") and not skipping and not audio.is_voice_playing():
				_speak(raw, who)
			# ページめくりと文字送りのタグ（[p]、[page]、[w]、[se]、[speed]）を最後まで進める
			await _finish_text()
			if skipping and wait is String and wait == "click":
				wait = "none"
			elif wait is float or wait is int:
				# 秒数の wait：クリックかその秒数で次へ（オート送りと同じく、待ちの印を出す）
				await _wait_input("click", maxf(0.01, float(wait)))
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
				var idv = args.get("id", "")
				var variant := String(args.get("variant", ""))
				for e in (idv if idv is Array else [idv]):
					var eid := String(e.get("id", "")) if e is Dictionary else String(e)
					var evar := String(e.get("variant", "")) if e is Dictionary else variant
					if core.assets.resolve("image", eid, evar) == "" and core.assets.report_missing("image", eid):
						ended = true
						return
				_images[layer] = {"id": idv, "variant": variant}
				screen.reset_layer(layer)
				job = screen.show_image.bind(layer, _image_label(idv), "", tr, _layer_texture(idv, variant))
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
			# "keep": false のスプライトはシーンを移ると消える（6.4）
			for id in _sprites.keys():
				if _sprites[id].get("keep", true) == false and not _sprites[id].has("scene"):
					_sprites.erase(id)
					screen.remove_sprite(String(id))
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
		"sprite.show":
			var s := _show_sprite(args)
			if s != null:
				var tr := _sprite_transition(args)
				if wait is String and wait == "end":
					await screen.reveal_sprite(s, tr)
				else:
					screen.reveal_sprite(s, tr)
			wait = "none"
		"sprite.set":
			await _set_sprite(args, wait is String and wait == "end")
			wait = "none"
		"sprite.hide":
			var ids: Array = args["id"] if args.get("id") is Array else [args.get("id", "")]
			var tr := _sprite_transition(args)
			for id in ids:
				_sprites.erase(String(id))
				if wait is String and wait == "end" and id == ids.back():
					await screen.remove_sprite(String(id), tr)
				else:
					screen.remove_sprite(String(id), tr)
			wait = "none"
		"sprite.anim":
			var s := screen.sprite(String(args.get("id", "")))
			if s != null:
				var an = args.get("anim")
				if not s.play_anim(String(an) if an != null else "", args.get("loop")):
					AdvDiag.debug_warn("MISSING_TARGET", "スプライトのアニメーションがありません: %s" % an, "Sprite animation not found: %s" % an)
				_sync_sprite_state(s)
			wait = "none"
		"sprite.effect":
			var s := screen.sprite(String(args.get("id", "")))
			if s != null and not skipping:
				var job := s.play_effect.bind(String(args.get("name", "")), float(args.get("duration", -1.0)), args.get("params", {}))
				if wait is String and wait == "end":
					await job.call()
				else:
					job.call()
				_sync_sprite_state(s)
			wait = "none"
		"sprite.clear":
			var layer := String(args.get("layer", ""))
			for id in _sprites.keys():
				if layer == "" or String(_sprites[id].get("layer", "char")) == layer:
					_sprites.erase(id)
			screen.clear_sprites(layer)
		"cursor.set":
			_cursor_forced = args.get("image") if args.get("image") != null else args.get("kind")
			if args.get("image") != null:
				_cursor_forced = {"image": args["image"], "hotspot": args.get("hotspot", [0, 0])}
			_cursor_kind = ""
		"video.play":
			if skipping and progress.read.has("video:" + String(args.get("id", ""))):
				wait = "none"
			else:
				await _play_video(args, wait)
				wait = "none"
		"video.stop":
			_video = {}
			screen.stop_video()
			audio.resume_bgm()
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


# ---------------------------------------------------------------- スプライト（6.4）

const _SPRITE_NOT_PROPS := ["id", "image", "variant", "layer", "transition", "duration", "anim", "keep", "scene",
	"color_key", "wait", "ease", "loop", "yoyo", "path"]


## スプライトを作って出す（演出はかけない）。作れなければ null。
func _show_sprite(args: Dictionary) -> AdvSprite:
	var id := String(args.get("id", ""))
	var img := String(args.get("image", ""))
	if id == "" or img == "":
		AdvDiag.debug_warn("SCHEMA_VIOLATION", "sprite.show には id と image が必要です", "sprite.show needs id and image")
		return null
	var kind := "video" if core.assets.has("video", img) else "image"
	var variant := String(args.get("variant", ""))
	var path := core.assets.resolve(kind, img, variant)
	if path == "":
		core.assets.report_missing("image", img)
		return null
	var entry := core.assets.entry(kind, img)
	var ck = AdvImages.key_color(args.get("color_key", entry.get("color_key")), template)
	var res := AdvImages.load_visual(path, ck)
	var s := screen.add_sprite(id, String(args.get("layer", "char")))
	if s == null:
		return null
	var loader := func(fid: String) -> Texture2D:
		var at := fid.find("@")
		var base := fid.substr(0, at) if at >= 0 else fid
		var v := fid.substr(at + 1) if at >= 0 else ""
		return AdvImages.first_texture(AdvImages.load_visual(core.assets.resolve("image", base, v), ck))
	s.set_visual(res, entry, loader)
	var props := {}
	for k in args:
		if not k in _SPRITE_NOT_PROPS:
			props[k] = args[k]
	s.apply(props)
	if args.has("anim"):
		if args["anim"] != null:
			s.play_anim(String(args["anim"]))
	elif "default" in s.anim_names():
		s.play_anim("default")
	var keep := args.duplicate(true)
	for k in ["transition", "duration", "wait"]:
		keep.erase(k)
	_sprites[id] = keep
	_sync_sprite_state(s)
	return s


## スプライトの出し入れの演出。指定がなければ演出なし（cut）。duration で長さを変えられる。
func _sprite_transition(args: Dictionary) -> Dictionary:
	if not args.has("transition") or skipping:
		return {"type": "cut"}
	var tr := _transition_for(args["transition"])
	if args.has("duration"):
		tr["duration"] = float(args["duration"])
	return tr


func _sync_sprite_state(s: AdvSprite) -> void:
	if not _sprites.has(s.sprite_id):
		return
	var st: Dictionary = _sprites[s.sprite_id]
	for k in s.state:
		st[k] = s.state[k]
	for k in ["effect", "_motion"]:
		if not s.state.has(k):
			st.erase(k)
	st["anim"] = s.state.get("anim")


## sprite.set：すぐに、または duration をかけて変える。
func _set_sprite(args: Dictionary, wait_end: bool) -> void:
	var id := String(args.get("id", ""))
	var s := screen.sprite(id)
	if s == null:
		AdvDiag.debug_warn("MISSING_TARGET", "スプライトがありません: %s" % id, "Sprite not found: %s" % id)
		return
	if args.has("image") or args.has("variant"):
		var spec: Dictionary = _sprites.get(id, {}).duplicate(true)
		for k in ["image", "variant", "color_key"]:
			if args.has(k):
				spec[k] = args[k]
		s = _show_sprite(spec)
		if s == null:
			return
	var dur := 0.0 if skipping else float(args.get("duration", 0.0))
	if dur > 0.0 or args.has("path"):
		s.stop_motion()
		var loop := int(args.get("loop", 1))
		var tw := s.tween_to(args, maxf(dur, 0.01), String(args.get("ease", "linear")), loop, bool(args.get("yoyo", false)))
		_sync_sprite_state(s)
		if wait_end and loop == 1:
			await tw.finished
	else:
		var props := {}
		for k in args:
			if not k in _SPRITE_NOT_PROPS:
				props[k] = args[k]
		s.apply(props)
		if args.has("anim"):
			s.play_anim(String(args["anim"]) if args["anim"] != null else "")
		_sync_sprite_state(s)


## セーブやテンプレートの切り替えのあとに、スプライトを出し直す（繰り返しの動きと効果も）。
func _restore_sprite(spec: Dictionary) -> void:
	var s := _show_sprite(spec)
	if s == null:
		return
	if spec.has("anim") and spec["anim"] != null:
		s.play_anim(String(spec["anim"]))
	var m = spec.get("_motion")
	if m is Dictionary:
		s.tween_to(m["args"], float(m["duration"]), String(m["ease"]), int(m["loop"]), bool(m["yoyo"]))
	var ef = spec.get("effect")
	if ef is Dictionary:
		s.play_effect(String(ef["name"]), -1.0, ef.get("params", {}))
	_sync_sprite_state(s)


# ---------------------------------------------------------------- 動画（6.6）

func _play_video(args: Dictionary, wait: Variant) -> void:
	var loop := bool(args.get("loop", false))
	if not _start_video(args):
		return
	if loop:
		_video = args.duplicate(true)
		return
	var vid := String(args.get("id", ""))
	var skippable := bool(args.get("skippable", true))
	_click_pending = false
	while screen.video_player != null and is_instance_valid(screen.video_player) and screen.video_player.is_playing():
		if skippable and (_click_pending or _skip_held()):
			break
		await get_tree().process_frame
	_click_pending = false
	screen.stop_video()
	if String(args.get("bgm", "pause")) == "pause":
		audio.resume_bgm()
	progress.read["video:" + vid] = true
	core.state.read["video:" + vid] = true


## 動画を流し始める。流せなければ false。
func _start_video(args: Dictionary) -> bool:
	var vid := String(args.get("id", ""))
	var path := core.assets.resolve("video", vid)
	if path == "":
		core.assets.report_missing("video", vid)
		return false
	var stream := load(path) as VideoStream
	if stream == null:
		push_warning("[adv80s] ASSET_UNSUPPORTED: 動画を読めません: %s" % path)
		return false
	match String(args.get("bgm", "pause")):
		"pause": audio.pause_bgm()
		"stop": audio.stop_bgm()
	var vol := float(args.get("volume", 1.0)) * float(settings.get_value("bgm_volume", 1.0))
	var parent: Control = null if bool(args.get("filters", true)) else display.unfiltered_overlay()
	screen.play_video(stream, String(args.get("area", "picture")), String(args.get("fit", "contain")),
		bool(args.get("loop", false)), linear_to_db(maxf(vol, 0.0001)), parent)
	return true


# ---------------------------------------------------------------- マウスカーソル（6.5）

const CURSOR_SHAPES := {"arrow": Input.CURSOR_ARROW, "pointing_hand": Input.CURSOR_POINTING_HAND, "cross": Input.CURSOR_CROSS,
	"help": Input.CURSOR_HELP, "move": Input.CURSOR_MOVE, "busy": Input.CURSOR_BUSY, "ibeam": Input.CURSOR_IBEAM, "wait": Input.CURSOR_WAIT}


## いまのカーソルの種類（固定 → 演出中・クリック待ち → 調べられる場所 → 通常）。
func current_cursor_kind() -> String:
	if _cursor_forced is String:
		return _cursor_forced
	if _cursor_forced is Dictionary:
		return "_forced_image"
	if busy and _overlay == null:
		return "next" if screen.is_waiting_mark() else "wait"
	if screen != null and _overlay == null:
		var h := screen.hotspot_layer.hovered()
		if not h.is_empty():
			if h.has("cursor"):
				return String(h["cursor"])
			match String(h.get("type", "object")):
				"character": return "talk"
				"exit": return "exit"
			return "look"
	return "default"


func _process(_delta: float) -> void:
	if template == null or screen == null:
		return
	var cursors: Dictionary = template.get_section("ui").get("cursors", {})
	if cursors.is_empty() and _cursor_forced == null:
		return
	var k := current_cursor_kind()
	if k == _cursor_kind:
		return
	_cursor_kind = k
	var def = _cursor_forced if k == "_forced_image" else cursors.get(k, cursors.get("default"))
	_apply_cursor(def, Input.CURSOR_ARROW)


func _apply_cursor(def: Variant, shape: int) -> void:
	if def is Dictionary and def.has("image"):
		var tex := _cursor_texture(String(def["image"]))
		var hs: Array = def.get("hotspot", core.assets.entry("image", String(def["image"])).get("hotspot", [0, 0]))
		if tex != null:
			var k := maxi(1, int(display.display_scale().x))
			var img := tex.get_image()
			if k > 1:
				img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
			Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), shape, Vector2(float(hs[0]), float(hs[1])) * k)
			return
	Input.set_custom_mouse_cursor(null, shape)
	if shape == Input.CURSOR_ARROW:
		Input.set_default_cursor_shape(CURSOR_SHAPES.get(String(def) if def is String else "arrow", Input.CURSOR_ARROW))


func _cursor_texture(id: String) -> Texture2D:
	var path := core.assets.resolve("image", id)
	if path == "":
		return null
	var e := core.assets.entry("image", id)
	return AdvImages.first_texture(AdvImages.load_visual(path, AdvImages.key_color(e.get("color_key"), template)))


## 入力欄の上のカーソル（種類 text）と、テンプレートを切り替えたときの片付け。
func _apply_text_cursor() -> void:
	var cursors: Dictionary = template.get_section("ui").get("cursors", {}) if template != null else {}
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if cursors.has("text"):
		_apply_cursor(cursors["text"], Input.CURSOR_IBEAM)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_IBEAM)


# ---------------------------------------------------------------- 待ちの印（ui.wait_mark、ui.page_mark）

## 待ちの印を作る。null なら標準（「▼」の点滅）。文字列なら その文字の点滅。
## {text, blink?} か {image, anim?, blink?, offset?: [x, y], color_key?}（画像はアニメーション GIF やスプライトシートも使える）。
func _make_mark(def: Variant) -> Control:
	if def == null:
		return null
	if def is String:
		return screen._text_mark(def, true)
	if not def is Dictionary:
		return null
	var m: Control
	if def.has("image"):
		var id := String(def["image"])
		var path := core.assets.resolve("image", id)
		if path == "":
			core.assets.report_missing("image", id)
			return null
		var entry := core.assets.entry("image", id)
		var ck = AdvImages.key_color(def.get("color_key", entry.get("color_key")), template)
		m = Control.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sp := AdvSprite.new()
		sp.set_visual(AdvImages.load_visual(path, ck), entry, func(fid: String) -> Texture2D:
			return AdvImages.first_texture(AdvImages.load_visual(core.assets.resolve("image", fid), ck)))
		m.add_child(sp)
		var an := String(def.get("anim", "default"))
		if an in sp.anim_names():
			sp.play_anim(an)
		m.set_meta("size", sp.frame_size())
		m.set_meta("image", id)
		m.custom_minimum_size = sp.frame_size()
		m.set_meta("blink", bool(def.get("blink", false)))
	else:
		m = screen._text_mark(String(def.get("text", "▼")), bool(def.get("blink", true)))
	var off: Array = def.get("offset", [0, 0])
	m.set_meta("offset", Vector2(float(off[0]), float(off[1])))
	return m


# ---------------------------------------------------------------- 画像の層（重ね合わせ）

## 層に出す画像。id は素材IDか、重ねる順に並べた配列（要素は素材IDか {id, variant?, x?, y?}）。
## 配列なら、最初の画像の大きさの1枚に重ね合わせる（カラーキーも効く。アニメーション画像は最初のコマ）。
func _layer_texture(idv: Variant, variant: String = "") -> Texture2D:
	var list: Array = idv if idv is Array else [idv]
	var base: Image = null
	for e in list:
		var eid := String(e.get("id", "")) if e is Dictionary else String(e)
		var ev := String(e.get("variant", "")) if e is Dictionary else variant
		var path := core.assets.resolve("image", eid, ev)
		if path == "":
			continue
		var entry := core.assets.entry("image", eid)
		var tex := AdvImages.first_texture(AdvImages.load_visual(path, AdvImages.key_color(entry.get("color_key"), template)))
		if tex == null:
			continue
		if list.size() == 1:
			return tex
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if base == null:
			base = img.duplicate()
			continue
		var at := Vector2i(int(e.get("x", 0)), int(e.get("y", 0))) if e is Dictionary else Vector2i.ZERO
		base.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	return ImageTexture.create_from_image(base) if base != null else null


func _image_label(idv: Variant) -> String:
	if idv is Array:
		return "+".join(idv.map(func(e): return String(e.get("id", "")) if e is Dictionary else String(e)))
	return String(idv)


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
	await _finish_text()
	if _skip_held():
		return
	await _wait_input("click", 0.0)
	if bool(settings.get_value("voice_stop_on_advance", true)):
		audio.stop_voice()


## 文章を最後まで送る。窓がいっぱいになったらページ送りの印を出して待ち、文字送りのタグを実行する。
func _finish_text() -> void:
	while true:
		_click_pending = false
		while screen.is_typing():
			if _click_pending or auto_click or _skip_held():
				_click_pending = false
				screen.complete_text()
				break
			await get_tree().process_frame
		match screen.halt:
			"page":
				if screen.shown_since_wait() > 0:
					await _wait_input("page", 0.0)
				screen.next_page()
			"stop":
				var st := screen.current_stop()
				match String(st.get("kind", "")):
					"p":
						await _wait_input("click", float(st.get("value", 0.0)))
						screen.resume()
					"page":
						await _wait_input("page", float(st.get("value", 0.0)))
						screen.next_page()
					"w":
						if not _skip_held() and not auto_click:
							await get_tree().create_timer(maxf(0.0, float(st.get("value", 0.0)))).timeout
						screen.resume()
					"se":
						if not _skip_held():
							var path := core.assets.resolve("se", String(st["value"]))
							if path != "":
								audio.play_se(path, float(core.assets.entry("se", String(st["value"])).get("volume", 1.0)))
							else:
								core.assets.report_missing("se", String(st["value"]))
						screen.resume()
					"speed":
						var v := float(st.get("value", -1.0))
						screen.set_inline_speed(v if v <= 0.0 else v * float(settings.get_value("text_speed", 1.0)))
						screen.resume()
					_:
						screen.resume()
			_:
				return


## 待ちの印を出して、クリック（決定）を待つ。seconds が 0 より大きければその秒数で、オート送り中は文章の長さに応じた時間で進む。
## kind は click（クリック待ち）か page（ページ送り待ち）。
func _wait_input(kind: String, seconds: float) -> void:
	if _skip_held() or auto_click:
		screen.mark_waited()
		return
	screen.set_wait_mark(true, kind)
	_click_pending = false
	var waited := 0.0
	var auto_wait := float(settings.get_value("auto_delay", 1.2)) + \
		float(settings.get_value("auto_per_char", 0.04)) * screen.shown_since_wait()
	while not _click_pending and not auto_click and not _skip_held():
		await get_tree().process_frame
		waited += get_process_delta_time()
		if seconds > 0.0 and waited >= seconds:
			break
		if auto_mode and _overlay == null and waited >= auto_wait:
			break
	_click_pending = false
	screen.set_wait_mark(false)
	screen.mark_waited()


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


## 無効にした入力機器の操作か（モダン機能 gamepad、touch）。
## ゲームパッドのボタンとスティック、タッチと、タッチから作られたマウスの操作を見る。
func is_blocked_input(event: InputEvent) -> bool:
	if features == null:
		return false
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and not features.is_on("gamepad"):
		return true
	if not features.is_on("touch"):
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			return true
		if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
			return true
	return false


func _input(event: InputEvent) -> void:
	# ゲームパッドやキーボードで操作している間はカーソルを隠し、マウスを動かすとまた出す（6.5）
	if (event is InputEventJoypadButton or (event is InputEventKey and event.pressed)) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and not template.get_section("ui").get("cursors", {}).is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 無効にした機器の操作は、画面の部品に届く前に止める（_input は GUI より先に呼ばれる）
	if is_blocked_input(event):
		get_viewport().set_input_as_handled()
		return
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
			"text": _last_text.duplicate(), "bgm": audio.current_bgm.duplicate(), "sprites": _sprites_for_save(),
			"video": _video.duplicate(true), "cursor": _cursor_forced},
	}


## セーブに入れるスプライトの状態（動いている途中のものは終わりの値）。
func _sprites_for_save() -> Dictionary:
	for id in _sprites:
		var s := screen.sprite(String(id))
		if s != null:
			_sync_sprite_state(s)
	return _sprites.duplicate(true)


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
	_sprites = view.get("sprites", {}).duplicate(true)
	_video = view.get("video", {}).duplicate(true)
	_cursor_forced = view.get("cursor")
	_cursor_kind = ""
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
