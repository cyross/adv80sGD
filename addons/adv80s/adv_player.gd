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
##   F7  画面の写真   F10  録画の開始・停止（モダン機能 screenshot・recording。デバッグ実行中はいつも使える）

signal game_ended
signal idle                     ## 出力イベントを実行し終えて、入力を待つ状態になった
signal saved(slot: String)
signal loaded(slot: String)
signal fin_shown                 ## 「おわり」の画面を出した
signal reloaded                  ## デバッグ実行中に読み直した
signal system_scene_closed       ## JSON のシステムシーンを閉じた（ロードしたときは、ロードのあと）

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
var capture: AdvCapture          ## 画面の写真と録画（段階68）

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
var _gaiji_cache: Dictionary = {}      ## 外字：素材のパス → {path, alt}（読み込んだ画像を持っておく）
var _video_volume: float = 1.0         ## 流している動画の音量（BGM の音量をかける前。0〜1）
var _cursor_forced: Variant = null     ## cursor.set で固定した形（種類の文字列か {image, hotspot}）
var _cursor_kind: String = ""          ## いま出しているカーソルの種類
var _devices: Variant = null            ## 使う入力機器（プロジェクト設定の input_devices。null ならすべて）
var _notices: Array = []
## 起動時の確認で見つからなかった ID の診断（素材・シーン・サブシーン）。デバッグコンソールの ids で一覧にする
var missing_ids: Array = []
var _allow_reload_in_release := false   ## テスト用
var run_from_scene := ""                 ## エディタの「このシーンから実行」で始めたシーン
var run_from: Dictionary = {}            ## そのときの頼み {scene, dialogue, line, knot, preset, vars, items}
const MISSING_CODES := ["ASSET_NOT_FOUND", "MISSING_TARGET", "SUBSCENE_KIND"]
var _debug_layer: Control = null       ## デバッグ専用UI層（配布アプリでは生成しない）
var _initial_data: Dictionary = {}     ## 始める前の状態（はじめから・タイトルへ戻るときに戻す）
var _pending_action: Callable          ## 実行中に届いた、流れを切る操作（はじめから、ロード、システム画面を閉じるなど）
var _sys: Dictionary = {}              ## 開いている JSON のシステム画面 {id, mode, snapshot}（6.9）
var _opening: Dictionary = {}          ## 再生中のオープニング {id, next, mode, seen, boot}（6.9）
var _opening_hint: Control = null      ## 2回目からのオープニングに出す「とばす」の案内
var _opening_replay := false           ## タイトルなどから見返しているオープニングか（終わったらタイトルへ戻る）
var _fin_scene: String = ""            ## 「おわり」を出したエンディングのシーン（同じ入り方で2回出さない）
var _clear_meta: Dictionary = {}       ## クリアデータをセーブするあいだ、セーブの meta に足すもの {clear, ending, resume}


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
	AdvTextMarkup.gaiji_resolver = _gaiji

	AdvVisuals.load_custom(project.get_value("effects", []), diags)
	var tid := template_id if template_id != "" else String(project.get_value("template", "pc98_classic"))
	template = AdvTemplate.load_template(tid, diags)
	if template == null:
		_report(diags)
		return
	_apply_project_overrides(template)
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
	diags.append_array(AdvIdCheck.check_project(project.data, func(k: String, id: String) -> bool: return core.assets.has(k, id), project_path))
	missing_ids = diags.filter(func(d): return String(d.get("code", "")) in MISSING_CODES)
	_report(diags)
	if OS.is_debug_build() and not missing_ids.is_empty():
		print("[adv80s] 見つからない ID: %d 件（デバッグコンソールの ids で一覧）" % missing_ids.size())

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
	capture = AdvCapture.new()
	capture.name = "Capture"
	add_child(capture)
	capture.recording_stopped.connect(_on_recording_stopped)
	capture.converted.connect(_on_recording_converted)
	if OS.is_debug_build():
		_setup_debug_ui()
		_watch_snap = watch_snapshot()
		if bool(_debug_conf().get("auto_reload", false)):
			set_auto_reload(true)
		_start_debug_poll()
	var title := String(project.get_value("title", ""))
	if title != "" and get_window() != null and get_parent() == get_tree().root:
		get_window().title = title
	if _devices is Array and not "mouse" in _devices:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	AdvTextMarkup.set_aliases(core.aliases())
	AdvTextMarkup.cond_evaluator = func(t: String, st: AdvState) -> bool: return core.ctx.eval(t, st)
	_initial_data = _make_save_data()
	_boot()


## 起動の流れ：プロジェクト設定 title_screen が "" ならそのまま始める、"template" ならテンプレートのタイトル画面、
## それ以外ならタイトルのシーン（シーンID）から始める（6.9）。
func _boot() -> void:
	_fill_title_sys()
	if OS.is_debug_build():
		var req := take_run_from()
		var rf := String(req.get("scene", ""))
		if rf != "" and core.query("scene_info", {"id": rf}) != null:
			# エディタの「このシーンから実行」：オープニングとタイトルを飛ばして、そのシーンから始める
			run_from_scene = rf
			run_from = req
			apply_run_values(req)
			var at := {}
			for k in ["dialogue", "line", "path", "knot", "pre_sets"]:
				if req.has(k) and str(req[k]) != "" and str(req[k]) != "[]":
					at[k] = req[k]
			_run(core.start_at(rf, at))
			show_debug_notice(run_from_text(req), {}, -1.0, "", null, "run_from")
			var pl = core.query("pre_set_log")
			if pl is Dictionary and not pl.is_empty():
				# 先に動かした「設定する」で入った値：お知らせは短く、ログには全部（debug.pre_set_notice・pre_set_log で切り替え）
				if bool(_debug_conf().get("pre_set_notice", true)):
					var pst = _debug_conf().get("pre_set_style", {})
					show_debug_notice(pre_set_text(pl, 4), pst if pst is Dictionary else {}, float(_debug_conf().get("pre_set_seconds", -1.0)),
						String(_debug_conf().get("pre_set_position", "")), false, "pre_set")
				if bool(_debug_conf().get("pre_set_log", true)):
					message_log.add_notice(pre_set_text(pl, 0))
			return
	var op := String(project.get_value("opening", ""))
	if entry == "" and op != "":
		# 起動時のオープニング。1回だけ流す設定で、もう見ていれば飛ばす
		var sc = core.query("scene_info", {"id": op})
		var mode := String(sc.get("replay", "always")) if sc is Dictionary else "always"
		if mode == "once" and progress.openings.has(op):
			_after_opening(String(sc.get("next", "")) if sc is Dictionary else "")
			return
		_opening_boot = true
		_run(core.start(op))
		return
	_start_title_or_entry()


var _opening_boot := false   ## いまのオープニングは起動時に流したものか


## タイトル（あれば）か、開始シーンから始める。
func _start_title_or_entry() -> void:
	_fill_title_sys()
	var ts := String(project.get_value("title_screen", ""))
	if entry != "" or ts == "":
		_run(core.start(_entry_scene()))
	elif ts == "template":
		open_title_screen()
	else:
		_run(core.start(ts))


## オープニングのあと：next があればそのシーン、なければタイトル（あれば）か開始シーン。
func _after_opening(next: String) -> void:
	_opening_boot = false
	if next != "":
		_run(core.start(next))
	else:
		_start_title_or_entry()


## オープニングを飛ばす（2回目からの Esc・右クリック、1回だけの設定で見たことがあるとき）。
func skip_opening() -> void:
	if _opening.is_empty():
		return
	var next := String(_opening.get("next", ""))
	var was_replay := bool(_opening.get("replay", false))
	_end_opening()
	if was_replay:
		await go_title()
		return
	skip_mode = false
	_after_opening(next)


## オープニングを見た記録を付けて、案内を消す。
func _end_opening() -> void:
	if _opening.is_empty():
		return
	progress.mark_opening(String(_opening["id"]))
	if progress_path != "":
		progress.save()
	_opening = {}
	if _opening_hint != null and is_instance_valid(_opening_hint):
		_opening_hint.queue_free()
	_opening_hint = null


## オープニングを見返せるか（プロジェクト設定 opening_replay）：
##   "seen"（既定。見たことがあれば）、"always"、"never"、"any_ending"（エンディングを1つでも見たら）、
##   "all_endings"（すべて見たら）、{"endings": [ID…], "when": 条件式}（そのエンディングをすべて見ていて、条件にも合えば）
func can_replay_opening(scene: String = "") -> bool:
	var op := scene if scene != "" else String(project.get_value("opening", ""))
	if op == "" or core.query("scene_info", {"id": op}) == null:
		return false
	var rule = project.get_value("opening_replay", "seen")
	if rule is Dictionary:
		for e in rule.get("endings", []):
			if not progress.endings.has(String(e)):
				return false
		if rule.has("seen") and bool(rule["seen"]) and not progress.openings.has(op):
			return false
		if rule.has("when") and not core.ctx.eval(rule["when"], core.state):
			return false
		return true
	match String(rule):
		"always":
			return true
		"never":
			return false
		"any_ending":
			return not progress.endings.is_empty()
		"all_endings":
			var list = project.get_value("endings", [])
			if not list is Array or list.is_empty():
				return false
			for e in list:
				if e is Dictionary and not progress.endings.has(String(e.get("id", ""))):
					return false
			return true
	return progress.openings.has(op)


## オープニングを見返す（始める前の状態に戻して流し、終わったら・飛ばしたらタイトルへ戻る）。
func replay_opening(scene: String = "") -> void:
	var op := scene if scene != "" else String(project.get_value("opening", ""))
	if not can_replay_opening(op):
		return
	if _overlay != null:
		_overlay.call("close")
	await _reset_state()
	_opening_replay = true
	_run(core.start(op))


## 「おわり」の画面の設定（プロジェクト設定 fin → layers の順に重ねる）。
func fin_settings(layers: Array = []) -> Dictionary:
	return AdvFinScreen.merge_settings([project.get_value("fin")] + layers)


## 「おわり」の画面を出し、閉じたら then に従って進む。
func show_fin(s: Dictionary) -> void:
	var f := AdvFinScreen.new().setup(self, s)
	f.reveal.call_deferred()
	fin_shown.emit()
	await show_overlay(f)
	if bool(s.get("save_prompt", false)):
		await offer_clear_save(s)
	var then := String(s.get("then", "title"))
	match then:
		"title", "":
			await go_title()
		"new":
			await new_game()
		"quit":
			get_tree().quit()
		"stay":
			_enter_idle()
		_:
			if bool(s.get("reset", false)):
				await _reset_state()
			_run(core.start(then))


## クリアデータをセーブするか聞き、はいならセーブ画面を開く（「おわり」の画面の save_prompt）。
## クリアデータをロードすると、save_resume のシーン（なければ開始シーン）から、変数などを引き継いで始まる。
func offer_clear_save(s: Dictionary = {}) -> void:
	var m := modern._panel(String(s.get("save_prompt_title", "クリアデータ")))
	var answer := [false]
	m.add_text(String(s.get("save_prompt_text", "クリアデータを セーブしますか？")))
	m.add_button("はい", func(): answer[0] = true; m.close())
	m.add_button("いいえ", func(): m.close())
	m.focus_first()
	await show_overlay(m)
	if not answer[0]:
		return
	var info = core.query("scene_info")
	_clear_meta = {"clear": true, "ending": String(info.get("ending", "")) if info is Dictionary else "",
		"resume": String(s.get("save_resume", "")), "carry": s.get("save_carry", "all")}
	await open_save_menu("save")
	_clear_meta = {}


## クリアデータから引き継ぐ（いまの状態はロードしたクリアデータ）。carry：
##   "all"（全部引き継ぐ）、"none"（全部引き継がない：始める前の状態から）、
##   {"vars": "all" | "none" | [名前…], "items": "all" | "none" | [ID…], "visited": bool, "notebook": bool}
##   （書かなかったものは引き継がない）
func _carry_over(carry: Variant) -> void:
	if carry is String and carry == "all":
		return
	var old: AdvState = core.state.duplicate_state()
	await _apply_save_data(_initial_data)
	if not carry is Dictionary:
		return   # "none"
	var st := core.state
	for part in ["vars", "items"]:
		var spec = carry.get(part, "none")
		var src: Dictionary = old.vars if part == "vars" else old.items
		var dst: Dictionary = st.vars if part == "vars" else st.items
		if spec is String and spec == "all":
			for k in src:
				dst[k] = src[k]
		elif spec is Array:
			for k in spec:
				if src.has(String(k)):
					dst[String(k)] = src[String(k)]
				elif part == "items":
					dst.erase(String(k))
	for part in ["visited", "talked", "notebook", "chosen"]:
		if bool(carry.get(part, false)):
			st.set(part, old.get(part).duplicate(true))


## 合図を送る（「おわり」の画面の advance の "trigger:名前" など）。受け取ったものがあれば true。
func fire_trigger(name: String) -> bool:
	if _overlay is AdvFinScreen:
		return (_overlay as AdvFinScreen).trigger(name)
	return false


## おまけ（プロジェクト設定 extras）を開けるか。show が false なら出さない。when（既定 "sys.all_endings"）に合えば開ける。
func can_open_extras() -> bool:
	var ex = project.get_value("extras")
	if not ex is Dictionary or not bool(ex.get("show", true)):
		return false
	if extras_menu().is_empty():
		return false
	_fill_title_sys_basic()
	fill_extras_sys()
	return core.ctx.eval(ex.get("when", "sys.all_endings"), core.state)


## おまけの画面に並べる項目（extras.menu の順。既定は gallery、music）のうち、出せるもの。
## endings はプロジェクト設定 endings があるとき、opening はタイトルからオープニングを見返せるときだけ。
func extras_menu() -> Array:
	var ex = project.get_value("extras")
	if not ex is Dictionary:
		return []
	var out := []
	for k in ex.get("menu", ["gallery", "music"]):
		match String(k):
			"gallery", "music":
				if not ex.get(String(k), []).is_empty():
					out.append(String(k))
			"endings":
				if modern.has_endings():
					out.append("endings")
			"opening":
				if can_replay_opening():
					out.append("opening")
	return out


const EXTRA_LISTS := {"image": "gallery", "bgm": "music"}


## おまけの特典（bonus: true の項目）を使うか（extras.bonus、既定 true）。
func extras_bonus_on() -> bool:
	var ex = project.get_value("extras")
	return ex is Dictionary and bool(ex.get("bonus", true))


## おまけの開き具合を sys に入れる（特典の条件に使う）。特典の項目は数えない。
## sys.gallery_opened、sys.gallery_total、sys.gallery_all、sys.music_opened、sys.music_total、sys.music_all。
func fill_extras_sys() -> void:
	var ex = project.get_value("extras")
	for kind in EXTRA_LISTS:
		var key: String = EXTRA_LISTS[kind]
		var opened := 0
		var total := 0
		if ex is Dictionary:
			for e in ex.get(key, []):
				if e is Dictionary and not bool(e.get("bonus", false)):
					total += 1
					opened += 1 if extra_unlocked(e, kind) else 0
		core.state.sys[key + "_opened"] = opened
		core.state.sys[key + "_total"] = total
		core.state.sys[key + "_all"] = total > 0 and opened == total
	core.state.sys["extras_opened"] = int(core.state.sys["gallery_opened"]) + int(core.state.sys["music_opened"])
	core.state.sys["extras_total"] = int(core.state.sys["gallery_total"]) + int(core.state.sys["music_total"])


## 新しく開いた特典があれば知らせる（extras.notify、既定 true。文言は extras.notify_text）。
## 知らせた特典は進行の記録（seen の bonus）に残し、二度は知らせない。知らせた特典の名前を返す。
func check_bonus_unlocks() -> Array:
	var ex = project.get_value("extras")
	if not ex is Dictionary or not bool(ex.get("notify", true)) or not extras_bonus_on():
		return []
	var has_bonus := false
	for kind in EXTRA_LISTS:
		for e in ex.get(EXTRA_LISTS[kind], []):
			has_bonus = has_bonus or (e is Dictionary and bool(e.get("bonus", false)))
	if not has_bonus:
		return []
	_fill_title_sys_basic()
	fill_extras_sys()
	var news := []
	for kind in EXTRA_LISTS:
		var key: String = EXTRA_LISTS[kind]
		for e in ex.get(key, []):
			if e is Dictionary and bool(e.get("bonus", false)) and extra_unlocked(e, kind):
				var label := String(e.get("label", e.get("id", "")))
				if progress.mark_seen("bonus", "%s:%s" % [key, label if label != "" else str(extra_ids(e))]):
					news.append(label)
	if not news.is_empty():
		show_notice(String(ex.get("notify_text", "おまけが ふえました")), -1.0, String(ex.get("notify_icon", "")))
	return news


## 自動のお知らせの種類（出力イベント → プロジェクト設定 notices の項目）
const AUTO_NOTICES := {"item.add": "item_add", "item.remove": "item_remove", "notebook.add": "notebook_add",
	"objective.set": "objective_set", "hint.set": "hint_set"}


## 場面ごとの自動のお知らせ（プロジェクト設定 notices の項目に文言を書いたものだけ。enabled: false で全部止める）。
## 項目は文言か {text, icon, log}。文言の {name}（持ち物の名前）、{count}（数）、{title}（手帳の題）、{text}（目的）、
## {topic}（ヒントの話題）を置き換える。持ち物のお知らせは、icon がなければ持ち物の icon を出す。
func _auto_notice(type: String, args: Dictionary) -> void:
	var key := String(AUTO_NOTICES.get(type, ""))
	if key == "":
		return
	var entry := notice_entry(key)
	var text := String(entry.get("text", ""))
	if text == "":
		return
	var icon := String(entry.get("icon", ""))
	match type:
		"item.add", "item.remove":
			var id := String(args.get("id", ""))
			var info = core.query("item_info", {"id": id})
			var name := id
			if info is Dictionary:
				name = String(info.get("label", id))
				if icon == "":
					icon = String(info.get("icon", ""))
			text = text.replace("{name}", name).replace("{count}", str(int(args.get("count", 1))))
		"notebook.add":
			text = text.replace("{title}", String(args.get("title", "")))
		"objective.set":
			if String(args.get("text", "")) == "":
				return   # 目的を消したときは出さない
			text = text.replace("{text}", String(args.get("text", "")))
		"hint.set":
			text = text.replace("{topic}", String(args.get("topic", "")))
	show_notice(AdvTextMarkup.to_plain(text, core.state, template), -1.0, icon, entry.get("log"), String(entry.get("position", "")))


## 自動のお知らせの項目 {text, icon?, log?}（書いていない・止めているなら {}）。
func notice_entry(key: String) -> Dictionary:
	var conf = project.get_value("notices")
	if not conf is Dictionary or not bool(conf.get("enabled", true)):
		return {}
	var v = conf.get(key, "")
	if v is Dictionary:
		return v
	return {"text": String(v)} if String(v) != "" else {}


## 自動のお知らせの文言（書いていない・止めているなら ""）。
func notice_text(key: String) -> String:
	return String(notice_entry(key).get("text", ""))


## お知らせの見た目：テンプレートの notice に、プロジェクト設定 notice_style を重ねる。
## position（top_right・top_left・bottom_right・bottom_left・top・bottom・center）、fg・bg・border（パレットの番号。border は -1 で枠なし）、
## se（効果音の素材ID）、seconds（出しておく秒数。0 なら時間では消えない）、margin（画面の端からの間）、icon_size（絵の大きさ）、
## log（メッセージログにも残すか）、log_mark・log_color（ログでの印と色）、click_close（クリックで消せるか）、
## max（同時に出す数の上限。超えたら古いものから消す。0 なら上限なし）、overflow（上限で消すとき instant：すぐ、fade：すっと）、
## log_labels（ログの画面の切り替えの文言 {all, text, notice}）。
func notice_style() -> Dictionary:
	var s := {"position": "top_right", "fg": 7, "bg": 0, "border": 7, "se": "", "seconds": 2.5, "margin": 12, "icon_size": 24, "log": false,
		"log_mark": "◆ ", "click_close": true, "max": 5, "overflow": "instant"}
	s.merge(template.get_section("notice"), true)
	var p = project.get_value("notice_style")
	if p is Dictionary:
		s.merge(p, true)
	s.merge(notice_style_override, true)   # コンソールの noticestyle game で試しているもの
	return s


## 画面に短いお知らせを出し、しばらくして消す。seconds が負なら見た目の設定の秒数。
## icon は絵の素材ID（文の左に出す）。log はメッセージログにも残すか（null なら見た目の設定の log）。
## at はこのお知らせだけの位置（"" なら見た目の設定の position）。
func show_notice(text: String, seconds: float = -1.0, icon: String = "", log: Variant = null, at: String = "", style: Dictionary = {}) -> void:
	var st := notice_style()
	for k in style:
		if k in ["fg", "bg", "border", "se"]:   # このお知らせだけの見た目（書いたものだけ変える）
			st[k] = style[k]
	if at != "":
		st["position"] = at
	if seconds < 0.0:
		seconds = float(st["seconds"])
	if bool(log if log != null else st["log"]):
		message_log.add_notice(text)
	var p := PanelContainer.new()
	p.name = "Notice"
	var sb := StyleBoxFlat.new()
	sb.bg_color = template.color(int(st["bg"]))
	if int(st["border"]) >= 0:
		sb.border_color = template.color(int(st["border"]))
		sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE   # クリックは _input で受け取る（文字送りより先に）
	p.set_meta("click_close", bool(st["click_close"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var tex: Texture2D = _layer_texture(icon) if icon != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.name = "Icon"
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2.ONE * float(st["icon_size"])
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.add_theme_color_override("font_color", template.color(int(st["fg"])))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	p.z_index = 50
	var on_window := _notice_on_window(String(style.get("layer", "")))
	p.set_meta("window", on_window)
	(_debug_layer if on_window else screen).add_child(p)
	p.reset_size()
	# 画面の幅に収まらない長い文は折り返す（段階61。左右の余白 margin を残す）
	var area_w := minf(_window_layer_size().x, NOTICE_WINDOW_MAX_WIDTH) if on_window else template.visible_rect().size.x
	var max_w := maxf(48.0, area_w - float(st["margin"]) * 2.0)   # GB（160 幅）でも収まるように
	if p.size.x > max_w:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = maxf(80.0, max_w - (p.size.x - l.size.x))
		p.reset_size()
	p.set_meta("position", String(st["position"]))
	p.set_meta("margin", float(st["margin"]))
	p.resized.connect(_relayout_notices)   # 折り返した文の高さが後から決まっても重ならないように（段階62）
	_notices.append(p)
	# 出せる数（max。0 なら上限なし）を超えたら、古いものから消す
	var limit := int(st["max"])
	if limit > 0:
		var live := _notices.filter(func(n): return is_instance_valid(n) and not n.has_meta("closing"))
		for i in maxi(0, live.size() - limit):
			if String(st["overflow"]) == "fade":
				dismiss_notice(live[i], 0.3)
			else:
				_dismiss_now(live[i])
	_relayout_notices()
	var se := String(st["se"])
	if se != "" and not skipping:
		var path := core.assets.resolve("se", se)
		if path != "":
			audio.play_se(path, float(core.assets.entry("se", se).get("volume", 1.0)))
	if seconds > 0.0:
		var tw := p.create_tween()
		tw.tween_interval(seconds)
		tw.tween_callback(func(): dismiss_notice(p, 0.4))


## デバッグのお知らせ（シーンから実行・先に設定・読み直し・エディタで開く・ひな形にしました など）。
## 見た目はプロジェクト設定 debug.notice_style（fg・bg・border・se・icon・position・seconds・layer。書いたものだけ）、
## その上に kind_style（「先に設定」なら debug.pre_set_style）。seconds・at を渡せばそれが先。
## kind（run_from・pre_set・reload・editor・preset・auto_reload）を debug.notices で false にした種類は出さない。
func show_debug_notice(text: String, kind_style: Dictionary = {}, seconds: float = -1.0, at: String = "", log: Variant = null, kind: String = "") -> void:
	if not debug_notice_on(kind):
		return
	var ds = _debug_conf().get("notice_style", {})
	var st: Dictionary = ds.duplicate() if ds is Dictionary else {}
	for k in debug_notice_style_override:   # コンソールの noticestyle で試しているもの
		st[k] = debug_notice_style_override[k]
	for k in kind_style:
		st[k] = kind_style[k]
	if seconds < 0.0 and st.has("seconds"):
		seconds = float(st["seconds"])
	if at == "":
		at = String(st.get("position", ""))
	st["layer"] = String(st.get("layer", "auto"))   # デバッグのお知らせだけ：ゲームの画面の外（ウィンドウの層）にも出せる（段階64）
	show_notice(text, seconds, String(st.get("icon", "")), log, at, st)


const NOTICE_LAYERS := ["auto", "screen", "window"]
const NOTICE_WINDOW_AUTO_WIDTH := 320.0   ## auto のとき、見える範囲の幅がこれより狭ければウィンドウの層に出す
const NOTICE_WINDOW_TOP := 36.0           ## ウィンドウの層の上の位置は、デバッグのボタンの下から
const NOTICE_WINDOW_MAX_WIDTH := 480.0    ## ウィンドウの層のお知らせの幅の上限（広い窓で横いっぱいにしない）


## お知らせをウィンドウの層（デバッグの層。ゲームの画面の外）に出すか。layer：auto・screen・window（デバッグのお知らせだけが渡す）。
func _notice_on_window(layer: String) -> bool:
	if _debug_layer == null or layer == "" or layer == "screen":
		return false
	if layer == "window":
		return true
	return template.visible_rect().size.x < NOTICE_WINDOW_AUTO_WIDTH


## ウィンドウの層の大きさ（テストなどで大きさが 0 ならビューポートの大きさ）。
func _window_layer_size() -> Vector2:
	if _debug_layer != null and _debug_layer.size.x > 0.0 and _debug_layer.size.y > 0.0:
		return _debug_layer.size
	return get_viewport_rect().size


const DEBUG_NOTICE_KINDS := ["run_from", "pre_set", "reload", "editor", "preset", "auto_reload", "capture"]
var debug_notice_override: Dictionary = {}   ## コンソールの notice で切り替えたもの（種類 → bool。動かしている間だけ。設定より先）


## デバッグのお知らせの種類を出すか（コンソールで切り替えたもの、なければプロジェクト設定 debug.notices。書かなければ出す）。
func debug_notice_on(kind: String) -> bool:
	if kind == "":
		return true
	if debug_notice_override.has(kind):
		return bool(debug_notice_override[kind])
	var ns = _debug_conf().get("notices", {})
	return not (ns is Dictionary and ns.get(kind) is bool and ns[kind] == false)


## コンソールの notice：kind（"all" で全部）を on・off、"reset" で設定に戻す（kind を省くと全部）。変えた種類を返す（知らない種類なら []）。
func set_debug_notice(kind: String, on: Variant) -> Array:
	var kinds: Array = DEBUG_NOTICE_KINDS.duplicate() if kind == "all" or kind == "" else ([kind] if DEBUG_NOTICE_KINDS.has(kind) else [])
	for k in kinds:
		if on == null:
			debug_notice_override.erase(k)
		else:
			debug_notice_override[k] = bool(on)
	return kinds


const DEBUG_NOTICE_STYLE_KEYS := ["fg", "bg", "border", "se", "icon", "position", "seconds", "layer"]
const NOTICE_POSITIONS := ["top_right", "top_left", "bottom_right", "bottom_left", "top", "bottom", "center"]
var debug_notice_style_override: Dictionary = {}   ## コンソールの noticestyle で試している見た目（動かしている間だけ）


## コンソールの noticestyle キー 値：デバッグのお知らせの見た目を試す。値は fg・bg・border が整数、seconds が数、
## position が位置の名前、se・icon が素材ID（"" で無し）。value が null ならそのキーを試すのをやめる。できたら ""、だめなら理由。
func set_debug_notice_style(key: String, value: Variant) -> String:
	return _try_style(debug_notice_style_override, DEBUG_NOTICE_STYLE_KEYS, key, value)


## ふつうのお知らせ（遊ぶ人が見るもの）の見た目で試せるキー。
const GAME_NOTICE_STYLE_KEYS := ["position", "fg", "bg", "border", "se", "seconds", "margin", "icon_size", "max", "overflow", "click_close", "log"]
var notice_style_override: Dictionary = {}   ## コンソールの noticestyle game で試している、ふつうのお知らせの見た目（動かしている間だけ）


## コンソールの noticestyle game キー 値：ふつうのお知らせの見た目を試す（プロジェクト設定 notice_style の上に重なる）。
## margin・icon_size・max は整数、overflow は instant・fade、click_close・log は true・false。できたら ""、だめなら理由。
func set_game_notice_style(key: String, value: Variant) -> String:
	return _try_style(notice_style_override, GAME_NOTICE_STYLE_KEYS, key, value)


## コンソールの noticestyle game save：試している見た目をプロジェクト設定 notice_style に書くようエディタへ渡す。
func save_game_notice_style_to_editor() -> int:
	if notice_style_override.is_empty():
		return 0
	return 1 if _write_game_settings("game_notice_style", notice_style_override) else -1


## 名前を付けて取っておいた見た目（user:// のファイル。{debug: {名前: {…}}, game: {名前: {…}}}。パソコンごと）。
const NOTICE_STYLE_SETS_FILE := "user://adv80s_notice_styles.json"
var _style_set_current := {"debug": "", "game": ""}   ## いま use・next で使っている名前


static func _style_sets_all() -> Dictionary:
	var d = AdvJson.load_file(NOTICE_STYLE_SETS_FILE, []) if FileAccess.file_exists(NOTICE_STYLE_SETS_FILE) else {}
	return d if d is Dictionary else {}


## 取っておいた見た目（名前 → {キー: 値}）。game なら ふつうのお知らせ、そうでなければデバッグのお知らせ。
static func notice_style_sets(game: bool) -> Dictionary:
	var s = _style_sets_all().get("game" if game else "debug", {})
	return s if s is Dictionary else {}


static func _save_style_sets(game: bool, sets: Dictionary) -> bool:
	var all := _style_sets_all()
	all["game" if game else "debug"] = sets
	var f := FileAccess.open(NOTICE_STYLE_SETS_FILE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(all))
	f.close()
	return true


## いま試している見た目に名前を付けて取っておく（同じ名前は上書き）。試しているものがなければ false。
func keep_notice_style(game: bool, name: String) -> bool:
	var over: Dictionary = notice_style_override if game else debug_notice_style_override
	name = name.strip_edges()
	if name == "" or over.is_empty():
		return false
	var sets := notice_style_sets(game)
	sets[name] = over.duplicate()
	_style_set_current["game" if game else "debug"] = name
	return _save_style_sets(game, sets)


## 取っておいた見た目を試す（いま試しているものと入れかえる）。なければ false。
func use_notice_style(game: bool, name: String) -> bool:
	var sets := notice_style_sets(game)
	if not sets.get(name) is Dictionary:
		return false
	var over: Dictionary = notice_style_override if game else debug_notice_style_override
	over.clear()
	for k in sets[name]:
		var v = sets[name][k]
		over[k] = int(v) if String(k) in ["fg", "bg", "border", "margin", "icon_size", "max"] else v
	_style_set_current["game" if game else "debug"] = name
	return true


## 取っておいた見た目を名前の順に一つずつ試す（いまのものの次。終わりまで行くと頭へ）。試した名前（なければ ""）。
func next_notice_style(game: bool) -> String:
	var names: Array = notice_style_sets(game).keys()
	if names.is_empty():
		return ""
	names.sort()
	var cur := String(_style_set_current["game" if game else "debug"])
	var i := names.find(cur)
	var n := String(names[(i + 1) % names.size()])
	use_notice_style(game, n)
	return n


func drop_notice_style(game: bool, name: String) -> bool:
	if not erase_notice_style_set(game, name):
		return false
	if String(_style_set_current["game" if game else "debug"]) == name:
		_style_set_current["game" if game else "debug"] = ""
	return true


## 取っておいた見た目を消す（エディタの「見た目…」からも使う）。なければ false。
static func erase_notice_style_set(game: bool, name: String) -> bool:
	var sets := notice_style_sets(game)
	if not sets.has(name):
		return false
	sets.erase(name)
	return _save_style_sets(game, sets)


## 取っておいた見た目を名前ごと書く（同じ名前は上書き）。消したものを戻すときにも使う。
static func put_notice_style_set(game: bool, name: String, values: Dictionary) -> bool:
	name = name.strip_edges()
	if name == "" or values.is_empty():
		return false
	var sets := notice_style_sets(game)
	sets[name] = values.duplicate(true)
	return _save_style_sets(game, sets)


## 取っておいた見た目の名前を変える。できれば ""、できなければ理由。
static func rename_notice_style_set(game: bool, old: String, new_name: String) -> String:
	new_name = new_name.strip_edges()
	var sets := notice_style_sets(game)
	if not sets.get(old) is Dictionary:
		return "見た目がありません：%s" % old
	if new_name == "":
		return "新しい名前を書いてください"
	if new_name == old:
		return "同じ名前です"
	if sets.has(new_name):
		return "その名前はもうあります：%s" % new_name
	var out := {}
	for k in sets:   # 並びを保つ
		out[new_name if k == old else k] = sets[k]
	return "" if _save_style_sets(game, out) else "書けません：%s" % NOTICE_STYLE_SETS_FILE


func _try_style(target: Dictionary, keys: Array, key: String, value: Variant) -> String:
	if not keys.has(key):
		return "知らないキー：%s（%s）" % [key, "・".join(keys)]
	if value == null:
		target.erase(key)
		return ""
	var s := str(value).strip_edges()
	match key:
		"fg", "bg", "border", "margin", "icon_size", "max":
			if not s.is_valid_int():
				return "%s は整数で" % key
			if key in ["margin", "icon_size", "max"] and int(s) < (1 if key == "max" else 0):
				return "%s は %d 以上で" % [key, 1 if key == "max" else 0]
			target[key] = int(s)
		"seconds":
			if not s.is_valid_float() or float(s) < 0.0:
				return "seconds は 0 以上の数で（0 でクリックするまで）"
			target[key] = float(s)
		"position":
			if not NOTICE_POSITIONS.has(s):
				return "position は %s のどれか" % "・".join(NOTICE_POSITIONS)
			target[key] = s
		"layer":
			if not NOTICE_LAYERS.has(s):
				return "layer は %s のどれか（auto は画面が狭ければゲームの画面の外に）" % "・".join(NOTICE_LAYERS)
			target[key] = s
		"overflow":
			if not s in ["instant", "fade"]:
				return "overflow は instant・fade のどれか"
			target[key] = s
		"click_close", "log":
			if not s.to_lower() in ["true", "false"]:
				return "%s は true・false で" % key
			target[key] = s.to_lower() == "true"
		_:
			target[key] = "" if s == "\"\"" else s
	return ""


## いま効いているデバッグのお知らせの見た目（プロジェクト設定 debug.notice_style に、試しているものを重ねたもの）。
func debug_notice_style_now() -> Dictionary:
	var ds = _debug_conf().get("notice_style", {})
	var st: Dictionary = ds.duplicate() if ds is Dictionary else {}
	for k in debug_notice_style_override:
		st[k] = debug_notice_style_override[k]
	return st


## コンソールの noticestyle save：試している見た目を debug.notice_style に書くようエディタへ渡す。渡したキーの数（なければ 0、書けなければ -1）。
func save_debug_notice_style_to_editor() -> int:
	if debug_notice_style_override.is_empty():
		return 0
	return 1 if _write_game_settings("notice_style", debug_notice_style_override) else -1


func _write_game_settings(section: String, values: Dictionary) -> bool:
	var cur = AdvJson.load_file(GAME_SETTINGS_FILE, []) if FileAccess.file_exists(GAME_SETTINGS_FILE) else {}
	if not cur is Dictionary:
		cur = {}
	var sec = cur.get(section, {})
	if not sec is Dictionary:
		sec = {}
	for k in values:
		sec[k] = values[k]
	cur[section] = sec
	var f := FileAccess.open(GAME_SETTINGS_FILE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(cur))
	f.close()
	if EngineDebugger.is_active():
		EngineDebugger.send_message("adv80s:settings_saved", [])
	return true


## ゲームからエディタへ渡す設定の書きかえ（user:// のファイル。{notices: {種類: bool}, notice_style: {キー: 値}}）。エディタが取り込んで消す。
const GAME_SETTINGS_FILE := "user://adv80s_game_settings.json"


## コンソールの notice save：コンソールで切り替えた種類を、プロジェクト設定 debug.notices に書くようエディタへ渡す。
## 渡した種類の数（切り替えたものがなければ 0、書けなければ -1）。
func save_debug_notices_to_editor() -> int:
	if debug_notice_override.is_empty():
		return 0
	var ns := {}
	for k in debug_notice_override:
		ns[k] = bool(debug_notice_override[k])
	return debug_notice_override.size() if _write_game_settings("notices", ns) else -1


## 種類ごとに「出す／出さない（どこで決めたか）」の一覧の文。
func debug_notice_report() -> String:
	var parts: Array = []
	for k in DEBUG_NOTICE_KINDS:
		parts.append("%s：%s%s" % [k, "出す" if debug_notice_on(k) else "出さない", "（コンソール）" if debug_notice_override.has(k) else ""])
	return "、".join(parts)


## お知らせを消す（少しずつ薄くしてから）。クリックで消すときにも使う。
func dismiss_notice(p: Control, fade: float = 0.15) -> void:
	if not is_instance_valid(p) or p.has_meta("closing"):
		return
	p.set_meta("closing", true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 0.0, fade)
	tw.tween_callback(func():
		_notices.erase(p)
		p.queue_free()
		_relayout_notices())


## 上限を超えたお知らせを、すぐに消す。
func _dismiss_now(p: Control) -> void:
	p.set_meta("closing", true)
	_notices.erase(p)
	p.queue_free()


## お知らせを並べ直す。位置ごとに、出した順に上の位置なら下へ、下の位置なら上へ並べる（消えたものの隙間を詰める）。
## 見える範囲（FC などは上下を隠す）の中に置く（段階64）。
## ウィンドウの層のお知らせは、ウィンドウ（上はデバッグのボタンの下から）に並べる（段階64）。
func _relayout_notices() -> void:
	var vr := template.visible_rect()
	var ws := _window_layer_size()
	var wr := Rect2(Vector2(0, NOTICE_WINDOW_TOP), ws - Vector2(0, NOTICE_WINDOW_TOP))
	var next_y := {}   # 位置（と層）→ 次に置く y
	for n in _notices:
		if not is_instance_valid(n) or n.has_meta("closing"):
			continue
		var win := bool(n.get_meta("window", false))
		var org := wr.position if win else vr.position
		var scr := wr.size if win else vr.size
		var pos := String(n.get_meta("position", "top_right"))
		var key := pos + ("@window" if win else "")
		var margin := float(n.get_meta("margin", 12.0))
		var size: Vector2 = (n as Control).size
		var x := scr.x - size.x - margin
		if pos.ends_with("left"):
			x = margin
		elif pos in ["top", "bottom", "center"]:
			x = (scr.x - size.x) / 2.0
		var from_bottom := pos.begins_with("bottom")
		var y: float
		if next_y.has(key):
			y = float(next_y[key]) - (size.y if from_bottom else 0.0)
		elif pos == "center":
			y = (scr.y - size.y) / 2.0
		else:
			y = margin if not from_bottom else scr.y - size.y - margin
		(n as Control).position = org + Vector2(x, y)
		next_y[key] = y - 6 if from_bottom else y + size.y + 6


## その位置にある、クリックで消せるお知らせ（なければ null）。
func notice_at(pos: Vector2) -> Control:
	for n in _notices:
		if is_instance_valid(n) and bool(n.get_meta("click_close", false)) and not n.has_meta("closing") and (n as Control).get_global_rect().has_point(pos):
			return n
	return null


## いま出ているお知らせの文言。
func notices() -> Array:
	return _notices.filter(func(n): return is_instance_valid(n)).map(func(n): return (n.find_child("Text", true, false) as Label).text)


## おまけの一覧に出すか：特典は、特典を使わないなら出さず、hidden（既定 true）なら開くまで出さない。
func extra_listed(entry: Dictionary, kind: String) -> bool:
	if not bool(entry.get("bonus", false)):
		return true
	if not extras_bonus_on():
		return false
	return not bool(entry.get("hidden", true)) or extra_unlocked(entry, kind)


## おまけの項目が開いているか：when があればそれ、なければ一度でも見た・聞いたか（kind は image か bgm）。
## ギャラリーの項目に images（画像の並び）があれば、そのどれかを見ていれば開く。
## 特典（bonus: true）は when（既定 sys.gallery_all か sys.music_all）。先に fill_extras_sys で数えておく。
func extra_unlocked(entry: Dictionary, kind: String) -> bool:
	if bool(entry.get("bonus", false)):
		if not extras_bonus_on():
			return false
		return core.ctx.eval(entry.get("when", "sys.%s_all" % EXTRA_LISTS.get(kind, "gallery")), core.state)
	if entry.has("when"):
		return core.ctx.eval(entry["when"], core.state)
	for id in extra_ids(entry):
		if progress.seen.get(kind, {}).has(id):
			return true
	return false


## おまけの項目の素材 ID（images があればその並び、なければ id）。
func extra_ids(entry: Dictionary) -> Array:
	var list = entry.get("images", [])
	if list is Array and not list.is_empty():
		return list.map(func(x): return String(x))
	return [String(entry.get("id", ""))]


## ギャラリーでめくる画像：when で開いた項目（特典を含む）は全部、そうでなければ見たものだけ。
func extra_pages(entry: Dictionary) -> Array:
	var ids := extra_ids(entry)
	if entry.has("when") or bool(entry.get("bonus", false)):
		return ids
	return ids.filter(func(id): return progress.seen.get("image", {}).has(id))


## タイトルで使う値（sys.opening_replay：オープニングを見返せるか、sys.endings_seen：見たエンディングの数）。
func _fill_title_sys() -> void:
	if not _sys.is_empty():
		return
	_fill_title_sys_basic()
	core.state.sys["opening_replay"] = can_replay_opening()
	core.state.sys["extras"] = can_open_extras()


func _fill_title_sys_basic() -> void:
	if not _sys.is_empty():
		return
	core.state.sys["endings_seen"] = progress.endings.size()
	var list = project.get_value("endings", [])
	var total := 0
	var all := true
	if list is Array:
		for e in list:
			if e is Dictionary:
				total += 1
				var seen := progress.endings.has(String(e.get("id", "")))
				core.state.sys["ending_" + String(e.get("id", ""))] = seen
				all = all and seen
	for id in progress.endings:
		core.state.sys["ending_" + String(id)] = true
	core.state.sys["endings_total"] = total
	core.state.sys["all_endings"] = total > 0 and all


## テンプレートのタイトル画面の差し替え（プロジェクト設定 title_variants）。when に合うものを順に重ねる（後ろほど優先）。
## [{when: "sys.endings_seen >= 2", image: ID, bgm: ID か {id, …}, transition: 演出}]
func title_variant() -> Dictionary:
	_fill_title_sys()
	var out := {}
	var vs = project.get_value("title_variants", [])
	if vs is Array:
		for v in vs:
			if v is Dictionary and core.ctx.eval(v.get("when", true), core.state):
				for k in v:
					if k != "when":
						out[k] = v[k]
	return out


## オープニングを飛ばせるか（2回目から、replay が skippable）。
func can_skip_opening() -> bool:
	return not _opening.is_empty() and bool(_opening.get("skippable", false))


## シーンに入ったとき、オープニングなら記録の準備をする（入れ替わったら、前のオープニングは見たことにする）。
func _track_opening(scene_id: String) -> void:
	if scene_id != _fin_scene:
		_fin_scene = ""
	if not _opening.is_empty() and String(_opening["id"]) != scene_id:
		var was_replay := bool(_opening.get("replay", false))
		_end_opening()
		if was_replay:
			_pending_action = go_title   # 見返していたオープニングが次のシーンへ進んだ：タイトルへ戻る
			return
	if not _opening.is_empty() or not _sys.is_empty():
		return
	var sc = core.query("scene_info", {"id": scene_id})
	if not sc is Dictionary or String(sc.get("kind", "")) != "opening":
		return
	var mode := String(sc.get("replay", "always"))
	var seen := progress.openings.has(scene_id)
	_opening = {"id": scene_id, "next": String(sc.get("next", "")), "mode": mode, "seen": seen,
		"skippable": _opening_replay or (seen and mode == "skippable"), "boot": _opening_boot, "replay": _opening_replay}
	if _opening_replay:
		_opening_replay = false
		_show_opening_hint()
	elif seen and mode == "once":
		_pending_action = skip_opening
	elif can_skip_opening():
		_show_opening_hint()


func _show_opening_hint() -> void:
	var l := Label.new()
	l.text = String(project.get_value("opening_hint", "Esc：とばす　Ctrl：はやおくり"))
	l.add_theme_color_override("font_color", template.color(int(template.get_section("text").get("name_color", 6))))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(template.screen_size.x - 8, 20)
	l.position = Vector2(0, 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(l)
	_opening_hint = l


func _entry_scene() -> String:
	return entry if entry != "" else String(project.get_value("entry", ""))


## はじめから（状態を始める前に戻して、開始位置から）。scene を渡すと、そのシーンから。
func new_game(scene: String = "") -> void:
	await _reset_state()
	_run(core.start(scene if scene != "" else _entry_scene()))


## タイトルへ戻る（状態を始める前に戻して、タイトルから）。タイトルがなければ、はじめから。
func go_title() -> void:
	await _reset_state()
	_fill_title_sys()
	var ts := String(project.get_value("title_screen", ""))
	if ts == "":
		_run(core.start(_entry_scene()))
	elif ts == "template":
		open_title_screen()
	else:
		_run(core.start(ts))


func _reset_state() -> void:
	_end_opening()
	_opening_boot = false
	_opening_replay = false
	_fin_scene = ""
	_history.clear()
	var had_sys := not _sys.is_empty()
	_sys = {}
	core.state.sys = {}
	if had_sys:
		system_scene_closed.emit()
	_request = {}
	skip_mode = false
	auto_mode = false
	ended = false
	await _apply_save_data(_initial_data)


## テンプレートで作るタイトル画面（title_screen: "template"）。メニューで選んだ操作を行う。
func open_title_screen() -> void:
	var tv := title_variant()
	var tb = tv.get("bgm", project.get_value("title_bgm", template.get_section("title").get("bgm")))
	while true:
		if tb != null and String(tb.get("id", "") if tb is Dictionary else tb) != "":
			await _play(AdvEvents.make("bgm.play", tb.duplicate(true) if tb is Dictionary else {"id": str(tb)}))
		var t := AdvTitleScreen.new().setup(self)
		t.reveal.call_deferred()
		await show_overlay(t)
		match t.action:
			"new":
				if tb != null:
					audio.stop_bgm(float(project.get_value("title_bgm_fade", 0.5)))
				_run(core.start(_entry_scene()))
				return
			"continue":
				await open_save_menu("load")
			"chapters":
				await modern.open_chapters()
			"endings":
				await modern.open_endings()
			"opening":
				await replay_opening()
				return
			"extras":
				await modern.open_extras()
			"settings":
				await modern.open_settings()
			"quit":
				get_tree().quit()
				return
		if core.state.scene != "":
			return   # ロードやチャプターで始まった


func _resolve_features(diags: Array = []) -> void:
	var env := {
		"templates": max(1, project.get_value("templates", []).size()),
		"readable_font": template.get_section("fonts").has("readable"),
		"tts": _tts_available(),
		"touch": DisplayServer.is_touchscreen_available(),
	}
	features = AdvFeatures.resolve(project.get_value("features", {}), template.get_section("features"), env,
		settings.get_value("features", {}), diags)
	# 使う入力機器（プロジェクト設定の input_devices）にないものは、機能ごと止める
	var devs = project.get_value("input_devices")
	_devices = devs if devs is Array and not devs.is_empty() else null
	if _devices is Array:
		for k in ["gamepad", "touch"]:
			if not k in _devices:
				features.allowed[k] = false
				features.enabled[k] = false
	core.features = features.enabled
	message_log.max_entries = int(features.options.get("message_log", {}).get("max_entries", 500))


## プロジェクト設定でテンプレートを上書きする（inputs：コマンド方式など）。
func _apply_project_overrides(t: AdvTemplate) -> void:
	var inp = project.get_value("inputs", {})
	t.overrides = {"inputs": inp} if inp is Dictionary and not inp.is_empty() else {}


func _build_screen() -> void:
	display.setup(template)
	display.set_filters_enabled(bool(settings.get_value("filters", true)) or not features.is_on("filter_toggle"))
	screen.set_text_speed(float(template.get_section("text").get("speed", 40)) * float(settings.get_value("text_speed", 1.0)))
	if screen.command_select != null and not screen.command_select.intent_selected.is_connected(submit_intent):
		screen.command_select.intent_selected.connect(submit_intent)
		screen.command_select.verb_changed.connect(func(): _cursor_kind = "")
		screen.command_select.item_long_pressed.connect(func(t: Dictionary): _pointer_alt({}, t))
		screen.command_select.menu_requested.connect(func(): modern.open_system_menu())
		screen.command_select.target_clicked.connect(func(t: Dictionary):
			_on_hotspot_clicked({"id": t["id"], "target": t["id"], "type": "exit" if t["type"] == "scene" else t["type"], "label": t["label"]}))
	if screen.command_line != null and not screen.command_line.command_entered.is_connected(submit_text):
		screen.command_line.command_entered.connect(submit_text)
	if not screen.hotspot_layer.hotspot_clicked.is_connected(_on_hotspot_clicked):
		screen.hotspot_layer.hotspot_clicked.connect(_on_hotspot_clicked)
		screen.hotspot_layer.long_pressed.connect(func(h: Dictionary): _pointer_alt(h))
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
	_apply_project_overrides(t)
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
		screen.show_image(layer, _image_label(im["id"]), "", {"type": "cut"}, _layer_visual(im["id"], String(im.get("variant", ""))))
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


func _exit_tree() -> void:
	if AdvTextMarkup.gaiji_resolver.is_valid() and AdvTextMarkup.gaiji_resolver.get_object() == self:
		AdvTextMarkup.gaiji_resolver = Callable()


## 外字（[gaiji=ID]）の画像を探す。画像は読み込んで、文中の [img] から使える仮のパスに置く。
func _gaiji(id: String) -> Dictionary:
	if core == null:
		return {}
	var e := core.assets.entry("image", id)
	var alt := String(e.get("alt", ""))
	var p := core.assets.resolve("image", id)
	if p == "":
		core.assets.report_missing("image", id)
		return {"alt": alt}
	var keep := bool(e.get("keep_colors", false))   # 減色しない（画像の色をそのまま出す）
	var key := ("keep:" if keep else "") + p
	if _gaiji_cache.has(key):
		return _gaiji_cache[key]
	var ck = AdvImages.key_color(e.get("color_key"), template)
	var tex := AdvImages.first_texture(AdvImages.load_visual(p, ck))
	var g := {"alt": alt}
	if tex != null and keep:
		# 写しを作って、減色しない外字の仮のパスに置く（読み込んだ画像そのものは動かさない）
		var im := tex.get_image()
		var copy: Texture2D = ImageTexture.create_from_image(im) if im != null else tex.duplicate()
		var kp := AdvTextMarkup.GAIJI_KEEP_PREFIX + "%s.tex" % p.md5_text()
		copy.take_over_path(kp)
		g["path"] = kp
		g["texture"] = copy   # 消えないように持っておく
	elif tex != null:
		if tex.resource_path != "":
			g["path"] = tex.resource_path   # 取り込んだ画像はそのパスで使う
		else:
			# 読み込んで作った画像（カラーキー、アニメーション画像の最初のコマ）は、仮のパスに置く
			var vp := "res://.adv80s_gaiji/%s.tex" % p.md5_text()
			tex.take_over_path(vp)
			g["path"] = vp
		g["texture"] = tex   # 消えないように持っておく
	_gaiji_cache[key] = g
	return g


## 音量（プレイヤー設定）を反映する。
func apply_volumes() -> void:
	audio.bgm_volume = float(settings.get_value("bgm_volume", 1.0))
	audio.se_volume = float(settings.get_value("se_volume", 1.0))
	audio.voice_volume = float(settings.get_value("voice_volume", 1.0))
	audio.apply_volumes()
	if screen == null:
		return
	# 動画の音も BGM の音量に従う
	for sid in screen.sprite_ids():
		var sp := screen.sprite(sid)
		if sp != null:
			sp.apply_video_audio(audio.bgm_volume)
	if screen.video_player != null and is_instance_valid(screen.video_player):
		screen.video_player.volume_db = linear_to_db(maxf(_video_volume * audio.bgm_volume, 0.0001))


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
		"recording":
			if not capture_on("recording") and is_recording():
				stop_recording()
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


## コマンド入力の文字列を読む（テンプレートの inputs.parser_profile："ja"、"en"、"free"、またはスクリプトのパス）。
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
		if ended or _pending_action.is_valid():
			break
	skipping = false
	busy = false
	if _pending_action.is_valid():
		var act := _pending_action
		_pending_action = Callable()
		_autosave_pending = false
		_flow_pending.clear()
		if progress_path != "":
			progress.save()
		await act.call()
		return
	if ended:
		game_ended.emit()
		return
	if _sys.is_empty():
		# システム画面の中では、オートセーブ・到達点・既読を記録しない
		if _autosave_pending:
			autosave()
		if not _flow_pending.is_empty():
			var snap := _make_save_data()
			for node in _flow_pending:
				progress.mark_reached(node, snap)
		progress.merge_read(core.state.read)
	_autosave_pending = false
	_flow_pending.clear()
	if progress_path != "":
		progress.save()
	if not _opening.is_empty() and core.state.scene == String(_opening["id"]) and core.query("pending_choice") == null:
		# オープニングの手順が終わった：次へ進む（next、なければタイトルか開始シーン）
		var next := String(_opening.get("next", ""))
		var was_replay := bool(_opening.get("replay", false))
		_end_opening()
		if was_replay:
			go_title()
		else:
			_after_opening(next)
		return
	if _sys.is_empty() and _fin_scene != core.state.scene and core.query("scene_kind") == "ending" \
			and core.query("pending_choice") == null:
		# エンディングを最後まで進めた：「おわり」の画面（シーンの fin、プロジェクト設定の fin）
		var info = core.query("scene_info")
		var fs := fin_settings([info.get("fin") if info is Dictionary else null])
		if bool(fs.get("show", true)):
			_fin_scene = core.state.scene
			await show_fin(fs)
			return
	_enter_idle()


## 入力を待つ状態にする。選択肢を出しているときは、選択肢だけを選べるようにする。
func _enter_idle() -> void:
	var choice = core.query("pending_choice")
	_apply_input_modes()
	_set_inputs_enabled(true)
	var intents: bool = choice is Dictionary and choice.get("accepts_intents", false)
	if choice is Dictionary and not (intents and choice.get("choices", []).is_empty()):
		if screen.command_select != null:
			# 選択肢の文にも、変数・エイリアス・条件を使える（表示する文字だけにする）
			var shown: Array = []
			for c in choice.get("choices", []):
				var cc: Dictionary = c.duplicate()
				cc["label"] = AdvTextMarkup.to_plain(String(c.get("label", "")), core.state, template)
				shown.append(cc)
			screen.command_select.show_choices(shown)
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
	var modes := _input_modes()
	if screen.command_line != null:
		screen.command_line.visible = "parser" in modes and template.region_rect("input").size != Vector2i.ZERO
	var pointer := _pointer_mode()
	var inp: Dictionary = template.get_section("inputs")
	if screen.command_select != null:
		screen.command_select.get_parent().visible = ("select" in modes or "icon" in modes or pointer != "") and template.region_rect("commands").size != Vector2i.ZERO
		screen.command_select.icons = "icon" in modes
		screen.command_select.show_tried = features.is_on("tried_marks")
		screen.command_select.mode = pointer if pointer != "" else "menu"
		screen.command_select.item_verb = String(inp.get("item_verb", "USE"))
		screen.command_select.alt_verb = String(inp.get("context_alt_verb", "LOOK"))
	_cursor_kind = ""
	var click: bool = "click" in modes or pointer != ""
	screen.hotspot_layer.mouse_filter = Control.MOUSE_FILTER_STOP if click or features.is_on("hotspot") else Control.MOUSE_FILTER_IGNORE
	screen.hotspot_layer.set_meta("click", click)
	screen.hotspot_layer.long_press = pointer != ""   # タッチを使わない設定なら、タッチの操作はここまで届かない


## いまの入力UIの一覧（input.mode で変えていればそれ、なければテンプレートとプロジェクト設定の inputs.enabled）。
func _input_modes() -> Array:
	# タイトル・オープニング・エンディング・システムのシーンでは、選択肢を出しているときだけ選べる（ほかの入力UIは出さない）
	var kind = core.query("scene_kind")
	if kind is String and kind in ["title", "opening", "ending", "system"]:
		return ["select"] if core.query("pending_choice") != null else []
	var modes = core.state.ui.get("input_modes")
	if not modes is Array:
		modes = template.get_section("inputs").get("enabled", ["select", "parser"])
	return modes


## 絵の中の対象を選ぶコマンド方式（4.5）："verbs"（verb_click）、"cursor"（verb_cursor）、"context"。なければ空。
func _pointer_mode() -> String:
	var modes := _input_modes()
	if "verb_click" in modes:
		return "verbs"
	if "verb_cursor" in modes:
		return "cursor"
	if "context" in modes:
		return "context"
	return ""


func _refresh_hotspots() -> void:
	var hs = core.query("hotspots")
	var layer := screen.hotspot_layer
	layer.set_hotspots(hs if hs is Array else [])
	if screen.command_select != null:
		var keys := {}
		for h in layer.hotspots:
			keys["%s:%s" % ["scene" if h.get("type") == "exit" else h.get("type", "object"), h.get("target", h["id"])]] = true
		var changed: bool = keys != screen.command_select.hotspot_keys
		screen.command_select.hotspot_keys = keys
		if changed and screen.command_select.is_pointer() and not busy and not screen.command_select.choosing:
			screen.command_select._show_verbs()
	layer.show_hover = features.is_on("hotspot")
	layer.show_all = _show_all_hotspots and features.is_on("hotspot")
	layer.show_new = features.is_on("tried_marks")
	layer.queue_redraw()


## 画面選択：コマンド選択で対象を選んでいる途中ならその対象に、そうでなければ既定の動詞で調べる。
func _on_hotspot_clicked(h: Dictionary, alt: bool = false) -> void:
	if busy or _overlay != null or not bool(screen.hotspot_layer.get_meta("click", false)):
		return
	var t := {"type": String(h.get("type", "object")), "id": String(h.get("target", h["id"])), "label": String(h.get("label", h["id"]))}
	if screen.command_select != null and screen.command_select.is_picking() and not alt:
		var cs := screen.command_select
		var picked := cs.pick_target(t)
		if not picked and t["type"] == "exit":
			t["type"] = "scene"
			picked = cs.pick_target(t)
		if not picked and cs.is_pointer() and cs._filled.is_empty():
			# その動詞の対象にならないものを押した：そのまま出して、シナリオの「できない」の返事を見せる
			var vid := cs.current_verb_id()
			if cs.mode != "cursor":
				cs.cancel()
			submit_intent({"verb": vid, "slots": {"target": {"type": t["type"], "id": t["id"]}}, "source": "click",
				"ext": {"label": "%s %s" % [t["label"], core.dictionary.verb_label(vid)]}})
		return
	var verb := _context_verb(h, alt)
	if verb == "":
		return
	if t["type"] == "exit":
		t["type"] = "scene"
	submit_intent({"verb": verb, "slots": {"target": {"type": t["type"], "id": t["id"]}}, "source": "click",
		"ext": {"label": "%s %s" % [t["label"], core.dictionary.verb_label(verb)]}})


## 動詞を選ばずに対象を選んだときの動詞（4.5 コンテキスト型）。
## 物・出口の click → 出口は MOVE → カーソルの種類（cursor、なければ人物は talk）から inputs.context_verbs で決める → inputs.click_verb。
## alt（右クリック）は inputs.context_alt_verb（既定 LOOK。出口には使わない）。
func _context_verb(h: Dictionary, alt: bool = false) -> String:
	var inp: Dictionary = template.get_section("inputs")
	var is_exit := String(h.get("type", "object")) == "exit"
	if alt:
		return "" if is_exit else String(inp.get("context_alt_verb", "LOOK"))
	if h.has("verb"):
		return String(h["verb"])
	if is_exit:
		return "MOVE"
	var fallback := String(inp.get("click_verb", "EXAMINE"))
	if _pointer_mode() == "":
		return fallback
	var kind := String(h.get("cursor", "talk" if h.get("type") == "character" else "look"))
	var map: Dictionary = AdvJson.merge(CONTEXT_VERBS, inp.get("context_verbs", {}))
	var v := String(map.get(kind, ""))
	return v if v != "" else fallback


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
	if _sys.is_empty():
		# おまけのギャラリーと音楽のために、出した画像と鳴らした曲を全プレイ共通で記録する
		if type == "image.show":
			var iv = args.get("id", "")
			var fresh := false
			for one in (iv if iv is Array else [iv]):
				fresh = progress.mark_seen("image", String(one.get("id", "")) if one is Dictionary else str(one)) or fresh
			if fresh:
				check_bonus_unlocks()
		elif type == "bgm.play":
			if progress.mark_seen("bgm", String(args.get("id", ""))):
				check_bonus_unlocks()
		_auto_notice(type, args)
	match type:
		"text.show", "text.append":
			var appending := type == "text.append"
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
			var plain := AdvTextMarkup.to_plain(raw, core.state, template)
			var conv := AdvTextMarkup.to_bbcode_stops(raw, core.state, template)
			if appending and not _last_text.is_empty():
				# いまの文章の続きに足す（話者はそのまま）
				_last_text["body"] = String(_last_text.get("body", "")) + raw
				who = ""
				message_log.append_text(plain)
				screen.append_text(conv["bbcode"], skipping, conv["stops"])
			else:
				_last_text = {"body": raw, "name": who}
				message_log.add_text(plain, who, String(ev.get("id", "")), voice)
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
				job = screen.show_image.bind(layer, _image_label(idv), "", tr, _layer_visual(idv, variant))
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
		"scene.goto", "scene.call", "scene.return":
			_scene_transition = args.get("transition")
			if type != "scene.return":
				_track_opening(String(args.get("scene", "")))
				if _pending_action.is_valid():
					return
			_apply_input_modes()   # タイトルやオープニングでは、入ったときからコマンドを出さない
			# "keep": false のスプライトはシーンを移ると消える（6.4）
			for id in _sprites.keys():
				if _sprites[id].get("keep", true) == false and not _sprites[id].has("scene"):
					_sprites.erase(id)
					screen.remove_sprite(String(id))
			if type == "scene.goto" and features.is_on("autosave") and "scene" in _autosave_on():
				_autosave_pending = true
			wait = "none"
		"ending.reach":
			if _sys.is_empty():
				progress.mark_ending(String(args.get("id", "")))
				check_bonus_unlocks()
			wait = "none"
		"credits.roll":
			await _roll_credits(args)
			wait = "none"
		"game.new":
			var at := String(args.get("scene", ""))
			_pending_action = func(): await new_game(at)
			return
		"game.title":
			_pending_action = go_title
			return
		"game.continue":
			_pending_action = func(): _enter_idle(); await open_save_menu("load")
			return
		"game.quit":
			_pending_action = func(): get_tree().quit()
			return
		"fin.show":
			var fs := fin_settings([args])
			_pending_action = func(): await show_fin(fs)
			return
		"opening.play":
			_pending_action = func(): await replay_opening(String(args.get("scene", "")))
			return
		"extras.open":
			_pending_action = func(): _enter_idle(); await modern.open_extras()
			return
		"endings.open":
			_pending_action = func(): _enter_idle(); await modern.open_endings()
			return
		"chapters.open":
			_pending_action = func(): _enter_idle(); await modern.open_chapters()
			return
		"settings.open":
			_pending_action = func(): _enter_idle(); await modern.open_settings()
			return
		"system.save":
			if not _sys.is_empty():
				save_game(String(args.get("slot", "")))
				_fill_sys_vars()
			wait = "none"
		"system.load":
			var slot := String(args.get("slot", ""))
			_pending_action = func():
				await close_system_scene(false)
				await load_game(slot)
				system_scene_closed.emit()
			return
		"system.close":
			_pending_action = close_system_scene
			return
		"settings.set":
			apply_setting(String(args.get("key", "")), args.get("value"))
			if not _sys.is_empty():
				_fill_sys_vars()
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
		"notice.show":
			show_notice(AdvTextMarkup.to_plain(String(args.get("text", "")), core.state, template), float(args.get("seconds", -1.0)),
				String(args.get("icon", "")), args.get("log"), String(args.get("position", "")))
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
			var tr := _transition_for(args.get("transition"))
			if not ev.has("wait") or (wait is String and wait == "end"):
				await screen.stop_video_with(tr)
			else:
				screen.stop_video_with(tr)
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
				if ended or _pending_action.is_valid():
					return
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
	"color_key", "wait", "ease", "loop", "yoyo", "path", "mute", "volume"]


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
	if s.has_video():
		s.video_mute = bool(args.get("mute", true))
		s.video_volume = float(args.get("volume", 1.0)) * float(entry.get("volume", 1.0))
		s.apply_video_audio(audio.bgm_volume)
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
	var tr := _transition_for(args.get("transition"))
	if loop:
		_video = args.duplicate(true)
		screen.reveal_video(tr)   # 繰り返しの動画は待たない
		return
	await screen.reveal_video(tr)
	var vid := String(args.get("id", ""))
	var skippable := bool(args.get("skippable", true))
	_click_pending = false
	while screen.video_player != null and is_instance_valid(screen.video_player) and screen.video_player.is_playing():
		if skippable and (_click_pending or _skip_held()):
			break
		await get_tree().process_frame
	_click_pending = false
	# 終わったら（飛ばしたときも）同じ演出で消す
	await screen.stop_video_with(_transition_for(args.get("transition")))
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
	_video_volume = float(args.get("volume", 1.0)) * float(core.assets.entry("video", vid).get("volume", 1.0))
	var vol := _video_volume * float(settings.get_value("bgm_volume", 1.0))
	var parent: Control = null if bool(args.get("filters", true)) else display.unfiltered_overlay()
	screen.play_video(stream, String(args.get("area", "picture")), String(args.get("fit", "contain")),
		bool(args.get("loop", false)), linear_to_db(maxf(vol, 0.0001)), parent)
	return true


# ---------------------------------------------------------------- マウスカーソル（6.5）

const CURSOR_SHAPES := {"arrow": Input.CURSOR_ARROW, "pointing_hand": Input.CURSOR_POINTING_HAND, "cross": Input.CURSOR_CROSS,
	"help": Input.CURSOR_HELP, "move": Input.CURSOR_MOVE, "busy": Input.CURSOR_BUSY, "ibeam": Input.CURSOR_IBEAM, "wait": Input.CURSOR_WAIT}


## コンテキスト型で、カーソルの種類から決める動詞の既定（inputs.context_verbs で変える。空は inputs.click_verb）
const CONTEXT_VERBS := {"look": "", "talk": "TALK", "take": "TAKE", "exit": "MOVE"}
## 動詞から決めるカーソルの種類の既定（inputs.verb_cursors で変える）
const VERB_CURSORS := {"LOOK": "look", "EXAMINE": "look", "TALK": "talk", "ASK": "talk", "CALL": "talk", "TAKE": "take",
	"USE": "use", "OPEN": "use", "CLOSE": "use", "PUSH": "use", "PULL": "use", "HIT": "use", "GIVE": "use", "SHOW": "use", "MOVE": "exit"}
## テンプレートに ui.cursors がなく、絵の中の対象を選ぶコマンド方式のときに使うカーソル（アドオンの標準の画像）
const DEFAULT_CURSORS := {
	"default": {"image": "cursor_arrow", "hotspot": [0, 0]}, "look": {"image": "cursor_look", "hotspot": [5, 6]},
	"talk": {"image": "cursor_talk", "hotspot": [6, 5]}, "take": {"image": "cursor_hand", "hotspot": [5, 0]},
	"use": {"image": "cursor_hand", "hotspot": [5, 0]}, "exit": {"image": "cursor_exit", "hotspot": [13, 8]},
	"wait": {"image": "cursor_wait", "hotspot": [6, 7]}, "next": {"image": "cursor_next", "hotspot": [5, 7]}}


## カーソルの定義（テンプレートの ui.cursors。なければ、絵の中の対象を選ぶ方式のときだけ標準のもの）。
func _cursor_defs() -> Dictionary:
	var cursors: Dictionary = template.get_section("ui").get("cursors", {})
	if cursors.is_empty() and core != null and _pointer_mode() != "":
		return DEFAULT_CURSORS
	return cursors


## 動詞に合うカーソルの種類。
func _verb_cursor(verb: String) -> String:
	var map: Dictionary = AdvJson.merge(VERB_CURSORS, template.get_section("inputs").get("verb_cursors", {}))
	return String(map.get(verb, "default"))


## いまのカーソルの種類（固定 → 演出中・クリック待ち → 選んでいる動詞 → 調べられる場所 → 通常）。
func current_cursor_kind() -> String:
	if _cursor_forced is String:
		return _cursor_forced
	if _cursor_forced is Dictionary:
		return "_forced_image"
	if busy and _overlay == null:
		return "next" if screen.is_waiting_mark() else "wait"
	if screen != null and _overlay == null:
		if screen.command_select != null and screen.command_select.is_pointer() and screen.command_select.current_verb_id() != "":
			return _verb_cursor(screen.command_select.current_verb_id())
		var h := screen.hotspot_layer.hovered()
		if not h.is_empty():
			if h.has("cursor"):
				return String(h["cursor"])
			if h.has("verb"):
				return _verb_cursor(String(h["verb"]))
			match String(h.get("type", "object")):
				"character": return "talk"
				"exit": return "exit"
			return "look"
	return "default"


func _process(_delta: float) -> void:
	if template == null or screen == null:
		return
	var cursors := _cursor_defs()
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

## 層に出す画像。id は素材IDか、重ねる順に並べた配列（要素は素材IDか {id, variant?, x?, y?, anim?}）。
## 動く画像（GIF・APNG・MNG、マニフェストの grid・anims）がなければ、最初の画像の大きさの1枚に重ね合わせた Texture2D を返す。
## 動く画像があれば、要素ごとにスプライトを重ねた Control を返す（それぞれのアニメーションを再生する）。
func _layer_visual(idv: Variant, variant: String = "") -> Variant:
	var list: Array = idv if idv is Array else [idv]
	var items := []   # [{res, entry, ck, at, anim}]
	var animated := false
	for e in list:
		var eid := String(e.get("id", "")) if e is Dictionary else String(e)
		var ev := String(e.get("variant", "")) if e is Dictionary else variant
		var path := core.assets.resolve("image", eid, ev)
		if path == "":
			continue
		var entry := core.assets.entry("image", eid)
		var ck = AdvImages.key_color(entry.get("color_key"), template)
		var res := AdvImages.load_visual(path, ck)
		if res == null:
			continue
		if (res is AdvImageFrames and (res as AdvImageFrames).frames.size() > 1) or entry.has("grid") or entry.has("anims"):
			animated = true
		items.append({"res": res, "entry": entry, "ck": ck,
			"at": Vector2(float(e.get("x", 0)), float(e.get("y", 0))) if e is Dictionary else Vector2.ZERO,
			"anim": String(e.get("anim", "")) if e is Dictionary else ""})
	if items.is_empty():
		return null
	if animated:
		return _layer_anim_node(items)
	return _layer_texture(list, variant)


## 動く画像を含む重ね合わせ：要素ごとのスプライトを、最初の画像の大きさの枠に重ね、絵の窓に合わせて拡大する。
func _layer_anim_node(items: Array) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = screen.picture.size
	root.clip_contents = true
	var holder := Node2D.new()
	holder.name = "Layers"
	root.add_child(holder)
	var base := Vector2.ZERO
	for it in items:
		var ck = it["ck"]
		var sp := AdvSprite.new()
		sp.set_visual(it["res"], it["entry"], func(fid: String) -> Texture2D:
			return AdvImages.first_texture(AdvImages.load_visual(core.assets.resolve("image", fid), ck)))
		sp.xy = it["at"]
		holder.add_child(sp)
		var an := String(it["anim"]) if String(it["anim"]) != "" else "default"
		if an in sp.anim_names():
			sp.play_anim(an)
		if base == Vector2.ZERO:
			base = sp.frame_size()
	if base.x > 0 and base.y > 0:
		var k := minf(root.size.x / base.x, root.size.y / base.y)
		holder.scale = Vector2(k, k)
		holder.position = ((root.size - base * k) * 0.5).round()
	root.set_meta("animated", true)
	return root


## 動かない画像を、最初の画像の大きさの1枚に重ね合わせる（カラーキーも効く）。1つだけならそのまま返す。
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
	if _pending_action.is_valid():
		return true   # 流れを切る操作を待っている：いまのイベントの待ちは飛ばす
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


## 絵の中の対象を選ぶコマンド方式（4.5）の操作。扱ったら true。
## - 右クリック：選びかけをやめる → cursor なら次の動詞 → 持ち物や調べられる場所の上なら調べる（context_alt_verb）→ メニュー
## - Tab（Shift で逆）、ゲームパッドの L・R：調べられる場所を順に選ぶ。決定で、その場所をクリックしたことにする
func _pointer_input(event: InputEvent) -> bool:
	var mode := _pointer_mode()
	var cs := screen.command_select
	if mode == "" or cs == null or ended:
		return false
	var layer := screen.hotspot_layer
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var h := layer.hotspot_at(layer.get_local_mouse_position()) if layer.get_global_rect().has_point(layer.get_global_mouse_position()) else {}
		return _pointer_alt(h, cs.item_at_mouse())
	var dir := 0
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		dir = -1 if event.shift_pressed else 1
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		dir = -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
	if dir != 0:
		if not layer.focus_next(dir).is_empty():
			screen.get_viewport().gui_release_focus()
			_cursor_kind = ""
		return true
	if event.is_action_pressed("ui_accept") and not layer.focused().is_empty():
		_on_hotspot_clicked(layer.focused())
		return true
	if event.is_action_pressed("ui_cancel") and cs.has_partial() and not cs.choosing:
		cs.cancel()
		return true
	return false


## 右クリックと、タッチの長押しの操作（h は押した場所、item は押した持ち物。なければ空）。扱ったら true。
## 選びかけをやめる → cursor なら次の動詞 → 持ち物や調べられる場所なら調べる（context_alt_verb）。
func _pointer_alt(h: Dictionary, item: Dictionary = {}) -> bool:
	var mode := _pointer_mode()
	var cs := screen.command_select
	if mode == "" or cs == null or ended or busy or _overlay != null or cs.choosing:
		return false
	if cs.has_partial():
		cs.cancel()
		return true
	if mode == "cursor":
		cs.cycle_verb(1)
		return true
	if not item.is_empty():
		cs.alt_item(item)
		return true
	if not h.is_empty() and _context_verb(h, true) != "":
		_on_hotspot_clicked(h, true)
		return true
	return false


## 無効にした入力機器の操作か（モダン機能 gamepad、touch）。
## ゲームパッドのボタンとスティック、タッチと、タッチから作られたマウスの操作を見る。
func is_blocked_input(event: InputEvent) -> bool:
	if features == null:
		return false
	if _devices is Array:
		if event is InputEventKey and not "keyboard" in _devices and not (OS.is_debug_build() and event.keycode in [KEY_F8, KEY_F11, KEY_F12]):
			return true
		if event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION and not "mouse" in _devices:
			return true
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and not features.is_on("gamepad"):
		return true
	if not features.is_on("touch"):
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			return true
		if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
			return true
	return false


func _input(event: InputEvent) -> void:
	# お知らせの上のクリックは、お知らせを消すだけ（文字送りなどには使わない）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var n := notice_at(event.position)
		if n != null:
			dismiss_notice(n)
			get_viewport().set_input_as_handled()
			return
	# ひな形にするものを選ぶ窓（デバッグ）は Esc で閉じる
	if preset_picker != null and event.is_action_pressed("ui_cancel"):
		close_preset_picker()
		get_viewport().set_input_as_handled()
		return
	# ゲームパッドやキーボードで操作している間はカーソルを隠し、マウスを動かすとまた出す（6.5）
	if (event is InputEventJoypadButton or (event is InputEventKey and event.pressed)) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and not _cursor_defs().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN and not (_devices is Array and not "mouse" in _devices):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 無効にした機器の操作は、画面の部品に届く前に止める（_input は GUI より先に呼ばれる）
	if is_blocked_input(event):
		get_viewport().set_input_as_handled()
		return
	# 画面の写真・録画（開いている画面の中でも使える）
	if event is InputEventKey and event.pressed and not event.echo and capture_key(event.keycode) != "":
		var ck := capture_key(event.keycode)
		get_viewport().set_input_as_handled()
		if ck == "screenshot":
			take_screenshot()
		else:
			toggle_recording()
		return
	if _overlay != null:
		if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F12 and _overlay.has_method("close_and_resume"):
				_overlay.call("close_and_resume")
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_F11 and _overlay.has_method("handle_escape") and not _overlay.has_method("close_and_resume"):
				_overlay.call("close")
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("ui_cancel") and _overlay.has_method("handle_escape"):
			_overlay.call("handle_escape")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_F4):
			_overlay.call("close")
			get_viewport().set_input_as_handled()
		return
	if can_skip_opening() and _overlay == null:
		var sk: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START])
		if sk:
			get_viewport().set_input_as_handled()
			if busy:
				_pending_action = skip_opening
				_click_pending = true
			else:
				skip_opening()
			return
	if not _sys.is_empty():
		# JSON のシステムシーンの中：Esc・右クリックで閉じる。ほかのショートカットは使わない
		var cancel: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F1, KEY_F4]) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START])
		if cancel:
			get_viewport().set_input_as_handled()
			if not busy:
				close_system_scene()
			return
		if event is InputEventKey and event.pressed and event.keycode in [KEY_F2, KEY_F3, KEY_F5, KEY_F6, KEY_F9]:
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
					var cs := screen.command_select
					if cs != null and cs.is_pointer() and cs.has_partial() and not cs.choosing:
						cs.cancel()   # 選びかけの動詞・持ち物をやめる
					else:
						open_save_menu("save")
			KEY_F1:
				modern.open_system_menu()
			KEY_F6:
				_show_all_hotspots = not _show_all_hotspots
				_refresh_hotspots()
			_:
				pass
		if OS.is_debug_build() and event.keycode in [KEY_F8, KEY_F11, KEY_F12]:
			if event.keycode == KEY_F12:
				open_debug_console()
			elif event.keycode == KEY_F8:
				debug_reload(true if event.shift_pressed else null)   # Shift+F8 はシーンに入り直す
			else:
				open_scene_graph()
			get_viewport().set_input_as_handled()
			return
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
		if _pointer_input(event):
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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
	if _overlay != null or not features.is_on("message_log") or not _sys.is_empty():
		return
	var custom: bool = await _open_custom_system("log")
	if custom:
		return
	var v := AdvLogView.new()
	v.open(message_log, template, template.visible_rect().size, features.is_on("rewind") and not busy, notice_style())
	v.rewind_requested.connect(func(i: int): v.close(); rewind_to(i))
	v.voice_requested.connect(_play_voice)
	await show_overlay(v)


## 画面全体に重ねる画面（ログ、セーブ、メニューなど）を出し、閉じるまで待つ。
func show_overlay(c: Control) -> void:
	if _overlay != null:
		_overlay.call("close")
	_overlay = c
	screen.add_child(c)
	# 見える範囲の大きさで作った画面（メニュー・ログ・セーブ）は、見える範囲に置く（FC などは上下が隠れるので。段階63）
	var vr := template.visible_rect()
	if c.position == Vector2.ZERO and c.size.is_equal_approx(vr.size):
		c.position = vr.position
	await c.closed
	_overlay = null


# ---------------------------------------------------------------- セーブとロード

## セーブ・ロードの画面を開く。閉じるまで待つ（await できる）。
func open_save_menu(mode: String = "save") -> void:
	if _overlay != null or not _sys.is_empty():
		return
	var custom: bool = await _open_custom_system(mode)
	if custom:
		return
	var m := AdvSaveMenu.new()
	m.open(mode, list_saves(), template, template.visible_rect().size)
	m.slot_chosen.connect(func(md: String, slot: String):
		if md == "save":
			save_game(slot)
		else:
			load_game(slot)
		m.close())
	await show_overlay(m)


# ---------------------------------------------------------------- システム画面の差し替え（6.9）

## プロジェクト設定 system_scenes で差し替えた画面を開く。差し替えていなければ false（標準の画面を出す）。
## .tscn なら重ねて出し、それ以外はシーンIDとして JSON のシステムシーンを開く。
func _open_custom_system(mode: String) -> bool:
	var defs = project.get_value("system_scenes", {})
	var spec := String(defs.get(mode, "")) if defs is Dictionary else ""
	if spec == "":
		return false
	if spec.ends_with(".tscn") or spec.ends_with(".scn"):
		var ps = load(spec) if ResourceLoader.exists(spec) else null
		if not ps is PackedScene:
			push_warning("[adv80s] システム画面のシーンが読めません: %s" % spec)
			return false
		var node: Node = ps.instantiate()
		if not node is Control or not node.has_signal("closed"):
			push_warning("[adv80s] システム画面は closed シグナルを持つ Control にしてください（AdvSystemScreen を継ぐ）: %s" % spec)
			node.queue_free()
			return false
		if node.has_method("open"):
			node.call("open", self, mode)
		await show_overlay(node)
		return true
	if busy:
		return false   # 実行中は JSON のシステムシーンを開けない（標準の画面を出す）
	await open_system_scene(spec, mode)
	if is_system_scene_open():
		await system_scene_closed   # 閉じるまで待つ（標準の画面と同じ）
	return true


## JSON のシステムシーンを開く。いまの状態を取っておき、閉じたら戻す（システムシーンの中で変えた変数などは捨てる）。
## シーンの中では sys.mode、sys.slot_count、sys.slot_<枠>（説明）、sys.slot_<枠>_exists、sys.slot_<枠>_label、
## sys.<設定のキー>（text_speed、bgm_volume など）が読める。
func open_system_scene(id: String, mode: String) -> void:
	if not _sys.is_empty() or busy:
		return
	_sys = {"id": id, "mode": mode, "snapshot": _make_save_data()}
	_fill_sys_vars()
	await _run(core.start(id))


## システムシーンを閉じて、開く前の状態に戻す。
func close_system_scene(notify: bool = true) -> void:
	if _sys.is_empty():
		return
	var snap: Dictionary = _sys["snapshot"]
	_sys = {}
	core.state.sys = {}
	_fill_title_sys()
	await _apply_save_data(snap)
	if notify:
		system_scene_closed.emit()


func is_system_scene_open() -> bool:
	return not _sys.is_empty()


func _fill_sys_vars() -> void:
	var v := {"mode": String(_sys.get("mode", ""))}
	var saves := list_saves()
	v["slot_count"] = saves.size()
	for s in saves:
		var k := "slot_" + String(s["slot"])
		v[k] = String(s["info"])
		v[k + "_exists"] = bool(s["exists"])
		v[k + "_label"] = String(s["label"])
	for key in settings.data:
		if not settings.data[key] is Dictionary:
			v[String(key)] = settings.data[key]
	for key in features.allowed:
		v["feature_" + String(key)] = features.is_on(String(key))
	core.state.sys = v


## 設定の値を変える（設定画面、システムシーンの settings.set、自作のシステム画面から）。
## features.<キー> はモダン機能の切り替え。
func apply_setting(key: String, value: Variant) -> void:
	match key:
		"":
			return
		"text_speed":
			set_text_speed(float(value))
		"text_size", "text_color", "window_opacity":
			set_text_option(key, value)
		"filters":
			set_filters_enabled(bool(value))
		"bgm_volume", "se_volume", "voice_volume":
			settings.set_value(key, clampf(float(value), 0.0, 1.0))
			save_settings()
			apply_volumes()
		_:
			if key.begins_with("features.") or key.begins_with("feature_"):
				set_feature(key.substr(9 if key.begins_with("features.") else 8), bool(value))
			else:
				settings.set_value(key, value)
				save_settings()


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
			info = "%s%s  %s" % ["クリア  " if bool(meta.get("clear", false)) else "",
				Time.get_datetime_string_from_unix_time(local, true), meta.get("scene_name", "")]
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
	if not _sys.is_empty():
		# システムシーンの中でセーブするのは、開く前の状態
		var d: Dictionary = _sys["snapshot"].duplicate(true)
		d["meta"]["time"] = int(Time.get_unix_time_from_system())
		return d
	var sc = core.query("scene")
	return {
		"save_version": 1,
		"game": String(project.get_value("game_id", "")),
		"meta": {
			"time": int(Time.get_unix_time_from_system()),
			"scene": core.state.scene,
			"scene_name": String(sc.get("name", "")) if sc is Dictionary else "",
		}.merged(_clear_meta),
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
	if save_game("auto%d" % oldest) == OK and notice_text("autosave") != "":
		var ne := notice_entry("autosave")
		show_notice(AdvTextMarkup.to_plain(notice_text("autosave"), core.state, template), -1.0, String(ne.get("icon", "")), ne.get("log"), String(ne.get("position", "")))


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
	# ほかのゲーム（ゲームIDが違う）のセーブは読まない
	var gid := String(project.get_value("game_id", ""))
	var saved_gid := String(res["data"].get("game", ""))
	if gid != "" and saved_gid != "" and gid != saved_gid:
		push_warning("[adv80s] GAME_MISMATCH: ほかのゲームのセーブデータです: %s（%s）" % [slot, saved_gid])
		return "GAME_MISMATCH"
	_history.clear()
	await _apply_save_data(res["data"])
	var lmeta: Dictionary = res["data"].get("meta", {})
	if bool(lmeta.get("clear", false)):
		# クリアデータ：save_carry で選んだものだけ引き継いで、save_resume のシーン（なければ開始シーン）から始める
		_fin_scene = ""
		await _carry_over(lmeta.get("carry", "all"))
		message_log.clear()
		var resume := String(lmeta.get("resume", ""))
		_run(core.start(resume if resume != "" else _entry_scene()))
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
	if not features.is_on("rewind") or not _sys.is_empty():
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


# ---------------------------------------------------------------- スタッフロール（6.9）

func _roll_credits(args: Dictionary) -> void:
	var b = args.get("bgm")
	if b != null:
		await _play(AdvEvents.make("bgm.play", b.duplicate(true) if b is Dictionary else {"id": str(b)}))
	var c := AdvCredits.new().setup(args, template, core.state, func(id: String) -> Texture2D: return _layer_texture(id))
	screen.add_child(c)
	var done := [false]
	c.finished.connect(func(): done[0] = true)
	c.roll(args)
	var skippable := bool(args.get("skippable", true))
	_click_pending = false
	while not done[0]:
		await get_tree().process_frame
		if skippable and (_click_pending or _skip_held()):
			_click_pending = false
			c.skip()
	c.queue_free()


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
# ---------------------------------------------------------------- 画面の写真と録画（段階68）

var _as_release := false     ## テスト用：デバッグ実行でも、配布アプリと同じに決める（モダン機能だけを見る）
var _rec_title := ""         ## 録画中に窓の名前を変える前の名前


## 写真（kind "screenshot"）・録画（"recording"）を使えるか。
## デバッグ実行中はいつも使える（プロジェクト設定 debug.capture: false で止めると、配布アプリと同じ）。
## 配布アプリでは、モダン機能 screenshot・recording が入っているときだけ。
func capture_on(kind: String) -> bool:
	if features == null or capture == null:
		return false
	if OS.is_debug_build() and not _as_release and bool(_debug_conf().get("capture", true)):
		return true
	return features.is_on(kind)


## 写真・録画の細かい設定（モダン機能の options に既定値を重ねたもの）。
func capture_options(kind: String) -> Dictionary:
	return AdvCapture.options_for(kind, features.options.get(kind, {}) if features != null else {})


## 押したキーが写真・録画のキーなら、その種類（"screenshot"・"recording"）。違えば ""。
func capture_key(keycode: Key) -> String:
	for kind in ["screenshot", "recording"]:
		if capture_on(kind) and keycode == AdvCapture.keycode_of(kind, capture_options(kind)):
			return kind
	return ""


## 設定の画面に、写真・録画の切り替えを出すか（プロジェクト設定 features に書いてあり、禁止していないとき）。
func capture_in_menu(kind: String) -> bool:
	var pf = project.get_value("features", {})
	return pf is Dictionary and pf.has(kind) and bool(features.allowed.get(kind, true)) and bool(capture_options(kind).get("menu", true))


## 写す画像。source が "screen" なら元の解像度の画面（フィルターの前）、それ以外は窓の全体（見えているとおり）。
func capture_image(source: String) -> Image:
	var vp: Viewport = display.viewport if source == "screen" and display != null else get_viewport()
	var tex := vp.get_texture() if vp != null else null
	return tex.get_image() if tex != null else null


## 画面の写真を撮って PNG で保存する（await できる）。保存したパス（だめなら ""）。
## デバッグのボタンは写さない。お知らせは撮ったあとに出す。
func take_screenshot() -> String:
	if not capture_on("screenshot"):
		return ""
	var opts := capture_options("screenshot")
	var bar := _debug_layer.get_node_or_null("DebugButtonBar") if _debug_layer != null else null
	var bar_shown: bool = bar != null and bar.visible
	if bar_shown:
		bar.visible = false
	await RenderingServer.frame_post_draw
	var img := capture_image(String(opts.get("source", "window")))
	if bar_shown and is_instance_valid(bar) and not is_recording():
		bar.visible = true
	var p := capture.save_screenshot(img, opts)
	if p == "":
		print("[adv80s] 画面の写真を撮れません（%s）" % capture.last_error)
		return ""
	print("[adv80s] 画面の写真：%s" % ProjectSettings.globalize_path(p))
	if bool(opts.get("notice", true)):
		_capture_notice("がめんを ほぞんしました（%s）" % p.get_file())
	return p


## 開いている画面（デバッグコンソールなど）が閉じてから写真を撮る・録画を始める（kind "screenshot"・"recording"）。
func capture_after_close(kind: String) -> void:
	await get_tree().process_frame
	if kind == "screenshot":
		await take_screenshot()
	else:
		start_recording()


func is_recording() -> bool:
	return capture != null and capture.is_recording()


## 録画を始める・止める。始めたら録画のパス、止めたら閉じたパス（だめなら ""）。
func toggle_recording() -> String:
	return stop_recording() if is_recording() else start_recording()


## 録画を始める。始めるお知らせは出さない（動画に写らないように）。窓の名前に ● REC を付ける。
func start_recording() -> String:
	if is_recording() or not capture_on("recording"):
		return ""
	var opts := capture_options("recording")
	var p := capture.start_recording(opts, capture_image)
	if p == "":
		print("[adv80s] 録画を始められません（%s）" % capture.last_error)
		return ""
	print("[adv80s] 録画を始めました：%s" % ProjectSettings.globalize_path(p))
	if capture.last_note != "":
		print("[adv80s] 形式 %s では書き出せないので AVI で録ります（%s）" % [opts.get("format"), capture.last_note])
	var bar := _debug_layer.get_node_or_null("DebugButtonBar") if _debug_layer != null else null
	if bar != null:
		bar.visible = false
	if String(opts.get("indicator", "title")) == "title" and get_window() != null and get_parent() == get_tree().root:
		_rec_title = get_window().title
		get_window().title = "● REC  " + _rec_title
	return p


## 録画を止めてファイルを閉じる。閉じたパス（録画していなければ ""）。
func stop_recording() -> String:
	return capture.stop_recording("stop") if is_recording() else ""


func _on_recording_stopped(path: String, reason: String) -> void:
	var bar := _debug_layer.get_node_or_null("DebugButtonBar") if _debug_layer != null else null
	if bar != null and is_instance_valid(bar):
		bar.visible = true
	if _rec_title != "" and get_window() != null:
		get_window().title = _rec_title
	_rec_title = ""
	if reason == "exit" or not is_inside_tree():
		return
	print("[adv80s] 録画を保存しました：%s（%s）" % [ProjectSettings.globalize_path(path), reason])
	var why := {"max_seconds": "（ながさの じょうげんで とめました）", "max_size": "（おおきさの じょうげんで とめました）"}.get(reason, "")
	if not bool(capture_options("recording").get("notice", true)):
		return
	if capture.is_converting(path):
		_capture_notice("ろくがを MP4 に して います%s" % why)
	else:
		_capture_notice("ろくがを ほぞんしました%s（%s）" % [why, path.get_file()])


## ffmpeg で MP4 に変え終えた（ok でなければ AVI を残した）。
func _on_recording_converted(path: String, ok: bool) -> void:
	if not is_inside_tree():
		return
	print("[adv80s] %s：%s" % ["MP4 にしました" if ok else "MP4 にできません（%s）。AVI を残しました" % capture.last_error, ProjectSettings.globalize_path(path)])
	if bool(capture_options("recording").get("notice", true)):
		_capture_notice(("ろくがを ほぞんしました（%s）" if ok else "MP4 に できなかったので AVI で のこしました（%s）") % path.get_file())


## 写真・録画のお知らせ。デバッグ実行中はデバッグのお知らせ（種類 capture）、配布アプリではふつうのお知らせ。
func _capture_notice(text: String) -> void:
	if OS.is_debug_build() and not _as_release:
		show_debug_notice(text, {}, -1.0, "", false, "capture")
	else:
		show_notice(text, -1.0, "", false)


# ---------------------------------------------------------------- デバッグ専用機能（デバッグコンソール・シーングラフ）

func _setup_debug_ui() -> void:
	if not OS.is_debug_build():
		return
	_debug_layer = Control.new()
	_debug_layer.name = "DebugLayer"
	_debug_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_layer.z_index = 100
	add_child(_debug_layer)

	var btn_bar := HBoxContainer.new()
	btn_bar.name = "DebugButtonBar"
	btn_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn_bar.offset_left = -280
	btn_bar.offset_right = -6
	btn_bar.offset_top = 4
	btn_bar.offset_bottom = 28
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	btn_bar.add_theme_constant_override("separation", 4)
	btn_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_layer.add_child(btn_bar)

	var graph_btn := Button.new()
	graph_btn.text = "シーングラフ (F11)"
	graph_btn.tooltip_text = "シーングラフを表示します (ショートカット: F11)"
	graph_btn.focus_mode = Control.FOCUS_NONE
	graph_btn.add_theme_font_size_override("font_size", 11)
	graph_btn.pressed.connect(open_scene_graph)
	btn_bar.add_child(graph_btn)

	var edit_btn := Button.new()
	edit_btn.text = "エディタで開く"
	edit_btn.tooltip_text = "いまのシーンを、エディタのシナリオエディタで開きます（エディタから実行したときだけ）"
	edit_btn.focus_mode = Control.FOCUS_NONE
	edit_btn.add_theme_font_size_override("font_size", 11)
	edit_btn.pressed.connect(func():
		if not request_open_in_editor():
			show_debug_notice("エディタにつながっていません", {}, -1.0, "", null, "editor"))
	btn_bar.add_child(edit_btn)

	var preset_btn := Button.new()
	preset_btn.text = "ひな形に"
	preset_btn.tooltip_text = "いまのフラグ・変数・持ち物から入れるものを選んで、シナリオエディタの実行のひな形にします（全部をすぐ送るならコンソールの preset 名前）"
	preset_btn.focus_mode = Control.FOCUS_NONE
	preset_btn.add_theme_font_size_override("font_size", 11)
	preset_btn.pressed.connect(func(): open_preset_picker())
	btn_bar.add_child(preset_btn)

	var reload_btn := Button.new()
	reload_btn.text = "読み直す (F8)"
	reload_btn.tooltip_text = "シナリオ・プロジェクト設定・素材の一覧を読み直します（遊んでいる状態はそのまま）"
	reload_btn.focus_mode = Control.FOCUS_NONE
	reload_btn.add_theme_font_size_override("font_size", 11)
	reload_btn.pressed.connect(debug_reload)
	btn_bar.add_child(reload_btn)

	var console_btn := Button.new()
	console_btn.text = "デバッグコンソール (F12)"
	console_btn.tooltip_text = "デバッグコンソールを表示します (ショートカット: F12)"
	console_btn.focus_mode = Control.FOCUS_NONE
	console_btn.add_theme_font_size_override("font_size", 11)
	console_btn.pressed.connect(open_debug_console)
	btn_bar.add_child(console_btn)


## デバッグ実行中に、プロジェクト設定・シナリオ・素材の一覧を読み直す（遊んでいる状態と画面はそのまま。デバッグビルド専用）。
## 素材はフォルダを読み直す（manifest.auto.json が古くても新しいファイルを見つける）。成功なら ""、だめなら理由。
## reenter が true なら（null ならプロジェクト設定 debug.reload_reenter）、読み直したあと、いまのシーンに入り直す（入ったときの手順を動かす）。
func debug_reload(reenter: Variant = null) -> String:
	if not OS.is_debug_build() and not _allow_reload_in_release:
		return "NOT_DEBUG"
	if busy and core.query("pending_choice") == null:
		return "BUSY"
	if not _sys.is_empty():
		return "SYSTEM_SCENE"   # システム画面の中では読み直さない（開く前の状態に戻れなくなるため）
	var data := _make_save_data()
	var diags: Array = []
	var p := AdvProject.load_project(project_path, diags)
	if p == null:
		_report(diags)
		return "PROJECT"
	project = p
	_apply_project_overrides(template)
	# 素材：いまの素材フォルダを読み直す
	var old := core.assets
	var a := AdvAssets.new()
	a.folders = project.asset_folders()
	a.missing_asset = old.missing_asset
	a.set_preset(core.preset, core.group)
	for r in old.roots:
		a.roots.append(r)
		a.add_manifest(AdvManifestGenerator.scan(r, a.folders)["manifest"], r)
		var manual := String(r) + "/" + AdvManifestGenerator.MANUAL_NAME
		if FileAccess.file_exists(manual):
			var m = AdvJson.load_file(manual, diags)
			if m is Dictionary:
				a.add_manifest(m, r)
	core.assets = a
	# シナリオ
	core.diagnostics.clear()
	core.use_adapter(AdvJsonAdapter.new())
	var paths := scenario_paths if not scenario_paths.is_empty() else PackedStringArray(project.get_value("scenarios", []))
	core.load_scenario(paths)
	diags.append_array(core.validate())
	diags.append_array(AdvIdCheck.check_project(project.data, func(k: String, id: String) -> bool: return core.assets.has(k, id), project_path))
	missing_ids = diags.filter(func(d): return String(d.get("code", "")) in MISSING_CODES)
	_report(diags)
	AdvTextMarkup.set_aliases(core.aliases())
	await _apply_save_data(data)
	var now := watch_snapshot()
	last_reload_changes = watch_changes(now) if not _watch_snap.is_empty() else []
	_watch_snap = now
	# プロジェクト設定の debug.auto_reload が書き換わっていたら合わせる（コンソールで入・切したものは、変わらなければそのまま）
	var auto_now := bool(_debug_conf().get("auto_reload", false))
	if _poll_auto != null and auto_now != bool(_poll_auto) and auto_now != is_auto_reload():
		set_auto_reload(auto_now)
	_poll_auto = auto_now
	_poll_mtime = FileAccess.get_modified_time(project_path) if FileAccess.file_exists(project_path) else -1
	for c in last_reload_changes:
		print("[adv80s] 読み直し：%s" % c)
	var re := bool(reenter if reenter != null else _debug_conf().get("reload_reenter", false))
	var sc := core.state.scene
	if re and sc != "" and core.query("scene_info", {"id": sc}) != null:
		_run(core.start(sc))
	reloaded.emit()
	var ct := changes_text(last_reload_changes, int(_debug_conf().get("notice_files", 2)))
	show_debug_notice("読み直しました" + ("：" + ct if ct != "" else "") + ("（入り直しました）" if re else "") + ("（見つからない ID：%d 件）" % missing_ids.size() if not missing_ids.is_empty() else ""), {}, -1.0, "", null, "reload")
	return ""


# ---------------------------------------------------------------- デバッグ：ファイルの見張り（自動で読み直す）

var _watch_timer: Timer = null
var _watch_snap: Dictionary = {}     ## 見張っているファイル → 更新時刻
var _watch_pending := false
var last_reload_changes: Array = []  ## 前に読み直したときに変わっていたファイル（足した・消したも）
var _poll_timer: Timer = null
var _poll_mtime := -1
var _poll_auto: Variant = null


## プロジェクト設定の debug（auto_reload、reload_reenter、watch_interval）。
func _debug_conf() -> Dictionary:
	var d = project.get_value("debug", {})
	return d if d is Dictionary else {}


## ファイルの変更を見張って、保存したら自動で読み直すか（デバッグビルド専用）。
func set_auto_reload(on: bool) -> void:
	if not OS.is_debug_build() and not _allow_reload_in_release:
		return
	if on and _watch_timer == null:
		_watch_timer = Timer.new()
		_watch_timer.name = "ReloadWatch"
		_watch_timer.wait_time = maxf(0.25, float(_debug_conf().get("watch_interval", 1.0)))
		_watch_timer.timeout.connect(check_watch)
		add_child(_watch_timer)
		_watch_snap = watch_snapshot()
		_watch_timer.start()
	elif not on and _watch_timer != null:
		_watch_timer.queue_free()
		_watch_timer = null


func is_auto_reload() -> bool:
	return _watch_timer != null


## 見張っているファイルが変わっていれば読み直す（忙しいときは、次に空いたときに）。読み直したら true。
func check_watch() -> bool:
	if not _watch_pending and watch_changes(watch_snapshot()).is_empty():
		return false
	_watch_pending = true
	if (busy and core.query("pending_choice") == null) or not _sys.is_empty():
		return false
	_watch_pending = false
	await debug_reload()
	return true


## 見張るファイル（プロジェクト設定、シナリオ、素材フォルダの中）→ 更新時刻。
func watch_snapshot() -> Dictionary:
	var snap := {}
	var files: Array = [project_path]
	var paths := scenario_paths if not scenario_paths.is_empty() else PackedStringArray(project.get_value("scenarios", []))
	files.append_array(Array(paths))
	for f in files:
		if FileAccess.file_exists(String(f)):
			snap[String(f)] = file_stamp(String(f))
	for r in core.assets.roots:
		if String(r).begins_with(AdvAssets.BUILTIN_ROOT):
			continue
		_watch_dir(String(r), snap, 0)
	return snap


## ファイルの印（更新時刻と大きさ）。更新時刻は秒の単位なので、同じ秒の中の書き換えも大きさで気づけるようにする。
static func file_stamp(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	return "%d:%d" % [FileAccess.get_modified_time(path), size]


## 前の見張りから変わったファイル（足した・消した・書き換えた）。
func watch_changes(now: Dictionary) -> Array:
	var out := []
	for p in now:
		if not _watch_snap.has(p) or _watch_snap[p] != now[p]:
			out.append(p)
	for p in _watch_snap:
		if not now.has(p):
			out.append(p)
	out.sort()
	return out


func _watch_dir(dir: String, snap: Dictionary, depth: int) -> void:
	var d := DirAccess.open(dir)
	if d == null or depth > 6:
		return
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		var p := dir.path_join(f)
		snap[p] = FileAccess.get_modified_time(p)
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_watch_dir(dir.path_join(sub), snap, depth + 1)


## エディタ（デバッグ実行のもと）のシナリオエディタで、いまのシーン（scene_id を渡せばそのシーン）を開いてもらう。
## デバッガにつながっていなければ false。
## いまの会話（dialogue）や Ink のノットも知らせ、エディタはそこを開く。
func request_open_in_editor(scene_id: String = "") -> bool:
	var loc := current_location()
	var id := scene_id if scene_id != "" else String(loc.get("scene", ""))
	if scene_id != "":
		loc = {"scene": scene_id}
	if id == "" or not EngineDebugger.is_active():
		return false
	EngineDebugger.send_message("adv80s:open_scene", [id, loc])
	var at := String(loc.get("dialogue", "")) if String(loc.get("dialogue", "")) != "" else String(loc.get("knot", ""))
	show_debug_notice("エディタで開きます：%s" % (id + ("・" + at if at != "" else "")), {}, -1.0, "", null, "editor")
	return true


## ゲームからエディタへ渡すひな形（user:// のファイル。[{name, vars, items, time}]）。エディタは窓に戻ったときか、デバッガの知らせで取り込んで消す。
const GAME_PRESETS_FILE := "user://adv80s_game_presets.json"


## いまのフラグ・変数・持ち物を、名前を付けて実行のひな形としてエディタへ送る（名前を省くと「シーン 時:分:秒」）。
## ファイルに書き足し、デバッガにつながっていれば知らせる。書けたら名前、書けなければ ""。
func send_preset_to_editor(pname: String = "", only: Variant = null) -> String:
	return send_preset_data(pname, preset_from_state(core.state, only))


## 中身 {vars, items} をそのまま、名前を付けてエディタへ送る（選ぶ窓で値を書きかえたとき）。
func send_preset_data(pname: String, data: Dictionary) -> String:
	if pname.strip_edges() == "":
		pname = default_preset_name()
	pname = pname.strip_edges()
	var e := data.duplicate(true)
	e["name"] = pname
	e["time"] = Time.get_unix_time_from_system()
	var list = AdvJson.load_file(GAME_PRESETS_FILE, []) if FileAccess.file_exists(GAME_PRESETS_FILE) else []
	if not list is Array:
		list = []
	list.append(e)
	var f := FileAccess.open(GAME_PRESETS_FILE, FileAccess.WRITE)
	if f == null:
		show_debug_notice("ひな形を書けません", {}, -1.0, "", null, "preset")
		return ""
	f.store_string(JSON.stringify(list))
	f.close()
	if EngineDebugger.is_active():
		EngineDebugger.send_message("adv80s:preset_saved", [pname])
	show_debug_notice("ひな形にしました：%s" % pname, {}, -1.0, "", null, "preset")
	return pname


func default_preset_name() -> String:
	return "%s %s" % [core.state.scene, Time.get_time_string_from_system()]


## 状態からひな形の中身 {vars, items}（変数は書かれたものだけ。定数・sys は入れない）。
## only に {vars: [名前], items: [ID]} を渡すと、そこに挙げたものだけ（null なら全部）。
static func preset_from_state(st: AdvState, only: Variant = null) -> Dictionary:
	var out := {}
	var vs := {}
	var pick_v: Array = only.get("vars", []) if only is Dictionary else []
	var pick_i: Array = only.get("items", []) if only is Dictionary else []
	for k in st.vars:
		if not st.constants.has(k) and (only == null or pick_v.has(k)):
			vs[k] = st.vars[k]
	if not vs.is_empty():
		out["vars"] = vs
	var its := {}
	for k in st.items:
		if only == null or pick_i.has(k):
			its[k] = st.items[k]
	if not its.is_empty():
		out["items"] = its
	return out


# ---------------------------------------------------------------- ひな形にするものを選ぶ窓（デバッグ）

var preset_picker: PanelContainer        ## 開いている間だけある
var _picker_name: LineEdit
var _picker_checks: Dictionary = {}      ## "v:名前" / "i:ID" → CheckBox
var _picker_filter: LineEdit
var _picker_list: VBoxContainer
var _picker_none: Label
var _picker_new_kind: OptionButton
var _picker_new_name: LineEdit
var _picker_new_value: LineEdit
var _picker_removed: Dictionary = {}     ## 外した行：key → {text, value, on}（「外したものを戻す」用。外したときの値）
var _picker_restore_btn: Button
var picker_keep_open := false            ## 送ったあとも窓を閉じない（続けて送る。名前は次の番号にする）
var _picker_keep_check: CheckBox
var _picker_group: LineEdit              ## 組（エディタの「実行：」でまとめて並ぶ。"" は組なし）
var _picker_values: Dictionary = {}      ## "v:名前" → LineEdit（値。JSON として読めればその値）、"i:ID" → SpinBox（個数）


## いまの変数・持ち物の一覧を出し、印を付けたものだけをひな形にする窓を開く（初めは全部に印）。
func open_preset_picker() -> void:
	close_preset_picker()
	if _debug_layer == null:
		return
	var full := preset_from_state(core.state)
	preset_picker = PanelContainer.new()
	preset_picker.name = "PresetPicker"
	preset_picker.custom_minimum_size = Vector2(460, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, 0.96)
	sb.border_color = Color(0.5, 0.6, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	preset_picker.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	preset_picker.add_child(box)
	var title := Label.new()
	title.text = "ひな形にするものを選ぶ"
	box.add_child(title)
	_picker_name = LineEdit.new()
	_picker_name.placeholder_text = "名前（空なら「シーン 時:分:秒」）"
	_picker_name.text = default_preset_name()
	box.add_child(_picker_name)
	_picker_filter = LineEdit.new()
	_picker_filter.placeholder_text = "絞り込み（名前の一部。空なら全部）"
	_picker_filter.clear_button_enabled = true
	_picker_filter.text_changed.connect(func(t): filter_picker(t))
	box.add_child(_picker_filter)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 150)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 横には広げない（段階61）
	box.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	_picker_list = list
	_picker_checks.clear()
	var vs: Dictionary = full.get("vars", {})
	var keys: Array = vs.keys()
	keys.sort()
	for k in keys:
		_add_picker_row(list, "v:" + String(k), "変数 %s" % k, vs[k])
	var its: Dictionary = full.get("items", {})
	keys = its.keys()
	keys.sort()
	for k in keys:
		_add_picker_row(list, "i:" + String(k), "持ち物 %s ×" % k, int(its[k]))
	if _picker_checks.is_empty():
		_picker_none = Label.new()
		_picker_none.text = "（まだ書かれた変数も持ち物もありません。下で足せます）"
		list.add_child(_picker_none)
	# 新しく足す：まだゲームで書かれていない変数・持ち物も入れられる
	var add_row := HBoxContainer.new()
	box.add_child(add_row)
	_picker_new_kind = OptionButton.new()
	_picker_new_kind.add_item("変数")
	_picker_new_kind.add_item("持ち物")
	_picker_new_kind.focus_mode = Control.FOCUS_NONE
	add_row.add_child(_picker_new_kind)
	_picker_new_name = LineEdit.new()
	_picker_new_name.placeholder_text = "名前・ID"
	_picker_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_picker_new_name)
	_picker_new_value = LineEdit.new()
	_picker_new_value.placeholder_text = "値・個数"
	_picker_new_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_picker_new_value)
	var add_b := Button.new()
	add_b.text = "足す"
	add_b.focus_mode = Control.FOCUS_NONE
	add_b.pressed.connect(func():
		if picker_add("i" if _picker_new_kind.selected == 1 else "v", _picker_new_name.text, _picker_new_value.text):
			_picker_new_name.text = ""
			_picker_new_value.text = "")
	add_row.add_child(add_b)
	_picker_keep_check = CheckBox.new()
	_picker_keep_check.text = "送っても閉じない（続けて送る）"
	_picker_keep_check.focus_mode = Control.FOCUS_NONE
	_picker_keep_check.button_pressed = picker_keep_open
	_picker_keep_check.toggled.connect(func(on):
		picker_keep_open = on
		# 続けて送るなら、いまの名前を組にしておく（まとめて並ぶように）
		if on and _picker_group.text.strip_edges() == "":
			_picker_group.text = _picker_name.text.strip_edges())
	var krow := HBoxContainer.new()
	box.add_child(krow)
	krow.add_child(_picker_keep_check)
	_picker_group = LineEdit.new()
	_picker_group.placeholder_text = "組（なくてよい）"
	_picker_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_group.tooltip_text = "同じ組のひな形は、エディタの「実行：」の一覧でまとめて並びます"
	krow.add_child(_picker_group)
	var row := HBoxContainer.new()
	box.add_child(row)
	for spec in [["全部", func(): set_picker_all(true)], ["なし", func(): set_picker_all(false)], ["外したものを戻す", func(): picker_restore_removed()], ["送る", func(): confirm_preset_picker()], ["やめる", func(): close_preset_picker()]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)
		if spec[0] == "外したものを戻す":
			_picker_restore_btn = b
			b.disabled = true
	_debug_layer.add_child(preset_picker)
	# デバッグの層は大きさを持たないので、画面の大きさから真ん中に置く
	preset_picker.reset_size()
	preset_picker.position = ((get_viewport().get_visible_rect().size - preset_picker.size) / 2).floor()


## 一行：印・名前・値（変数は書きかえられる欄、持ち物は個数）。
func _add_picker_row(list: Control, key: String, text: String, value: Variant) -> void:
	var row := HBoxContainer.new()
	list.add_child(row)
	var rm := Button.new()
	rm.text = "×"
	rm.flat = true
	rm.focus_mode = Control.FOCUS_NONE
	rm.tooltip_text = "この行を一覧から外します（送りません）"
	rm.pressed.connect(func(): picker_remove(key))
	row.add_child(rm)
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = true
	cb.focus_mode = Control.FOCUS_NONE
	# 長い名前は「…」で切り、全文は説明に（段階61）。値の欄と幅を分け合う
	cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cb.clip_text = true
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.size_flags_stretch_ratio = 1.0 if key.begins_with("v:") else 3.0
	cb.tooltip_text = text
	row.add_child(cb)
	_picker_checks[key] = cb
	if key.begins_with("i:"):
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = 9999
		sp.value = int(value)
		sp.custom_minimum_size = Vector2(90, 0)
		row.add_child(sp)
		_picker_values[key] = sp
	else:
		var le := LineEdit.new()
		le.text = value_text(value)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.tooltip_text = "値を書きかえて送れます（true、3、\"文字\" など。JSON として読めなければ文字）"
		row.add_child(le)
		_picker_values[key] = le


## 一覧から行を外す（送らない。ゲームの値は変えない。足した行も、もとからの行も）。外せたら true。
func picker_remove(key: String) -> bool:
	if not _picker_checks.has(key):
		return false
	var cb := _picker_checks[key] as CheckBox
	var row := cb.get_parent()
	var c = _picker_values.get(key)
	var val: Variant = null
	if c is LineEdit:
		val = parse_value_text(c.text)
	elif c is SpinBox:
		val = int(c.value)
	_picker_removed[key] = {"text": cb.text, "value": val, "on": cb.button_pressed}
	if _picker_restore_btn != null:
		_picker_restore_btn.disabled = false
	_picker_checks.erase(key)
	_picker_values.erase(key)
	if row != null:
		row.get_parent().remove_child(row)
		row.queue_free()
	return true


## 外した行をまとめて一覧に戻す（外したときの値と印で。その間に同じ名前を足していれば、それはそのまま）。戻した数。
func picker_restore_removed() -> int:
	var n := 0
	for key in _picker_removed:
		if _picker_checks.has(key) or _picker_list == null:
			continue
		var e: Dictionary = _picker_removed[key]
		if _picker_none != null:
			_picker_none.queue_free()
			_picker_none = null
		_add_picker_row(_picker_list, key, String(e["text"]), e["value"])
		set_picker_check(key, bool(e["on"]))
		n += 1
	_picker_removed.clear()
	if _picker_restore_btn != null:
		_picker_restore_btn.disabled = true
	if _picker_filter != null and _picker_filter.text != "":
		filter_picker(_picker_filter.text)
	return n


## 一覧に足す（kind は "v" 変数・"i" 持ち物。value は欄の文字か値。持ち物の個数は空なら 1）。印を付けて足し、
## すでにあれば値を書きかえて印を付ける。名前が空なら足さない。足せたら true。
func picker_add(kind: String, name: String, value: Variant = "") -> bool:
	name = name.strip_edges()
	if name == "" or _picker_list == null:
		return false
	var key := ("i:" if kind == "i" else "v:") + name
	var v: Variant = parse_value_text(value) if value is String else value
	if kind == "i":
		v = 1 if (value is String and String(value).strip_edges() == "") else int(v) if (v is int or v is float or String(v).is_valid_int()) else 1
	if not _picker_checks.has(key):
		if _picker_none != null:
			_picker_none.queue_free()
			_picker_none = null
		_add_picker_row(_picker_list, key, ("持ち物 %s ×" if kind == "i" else "変数 %s") % name, v)
	else:
		set_picker_value(key, v)
	set_picker_check(key, true)
	if _picker_filter != null and _picker_filter.text != "":
		filter_picker(_picker_filter.text)
	return true


## 値を欄に書く形に（整数の小数は整数で）。
static func value_text(v: Variant) -> String:
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return str(int(v))
	return JSON.stringify(v)


## 欄の文字を値に（JSON として読めればその値、読めなければ文字）。
static func parse_value_text(s: String) -> Variant:
	var t := s.strip_edges()
	var j := JSON.new()
	return j.data if t != "" and j.parse(t) == OK else t


## 窓の値の欄を書きかえる（テスト・道具用）。
func set_picker_value(key: String, value: Variant) -> void:
	var c = _picker_values.get(key)
	if c is LineEdit:
		c.text = value if value is String else value_text(value)
	elif c is SpinBox:
		c.value = int(value)


## 印の付いたものを、欄の値で {vars, items} に（持ち物は 0 なら持たないとして入れる）。
func picker_preset() -> Dictionary:
	var out := {}
	var vs := {}
	var its := {}
	for k in _picker_checks:
		if not (_picker_checks[k] as CheckBox).button_pressed:
			continue
		var c = _picker_values.get(k)
		if String(k).begins_with("v:"):
			vs[String(k).substr(2)] = parse_value_text(c.text) if c is LineEdit else null
		else:
			its[String(k).substr(2)] = int(c.value) if c is SpinBox else 1
	if not vs.is_empty():
		out["vars"] = vs
	if not its.is_empty():
		out["items"] = its
	return out


func _picker_row_visible(key: String) -> bool:
	var cb = _picker_checks.get(key)
	return cb != null and (cb as CheckBox).get_parent().visible


## 窓の印：key は "v:名前" か "i:ID"。
func set_picker_check(key: String, on: bool) -> void:
	if _picker_checks.has(key):
		(_picker_checks[key] as CheckBox).button_pressed = on


## 「全部」「なし」：絞り込みで見えているものだけに付け外しする（隠れているものの印はそのまま）。
func set_picker_all(on: bool) -> void:
	for k in _picker_checks:
		if _picker_row_visible(k):
			(_picker_checks[k] as CheckBox).button_pressed = on


## 名前の一部（大文字・小文字は区別しない）で一覧を絞る。印は隠れても残り、送るときに入る。見えている数を返す。
func filter_picker(text: String) -> int:
	if _picker_filter != null and _picker_filter.text != text:
		_picker_filter.text = text
	var t := text.strip_edges().to_lower()
	var n := 0
	for k in _picker_checks:
		var row := (_picker_checks[k] as CheckBox).get_parent() as Control
		row.visible = t == "" or String(k).substr(2).to_lower().contains(t)
		if row.visible:
			n += 1
	return n


## 印の付いたもの {vars: [名前], items: [ID]}。
func picker_selection() -> Dictionary:
	var out := {"vars": [], "items": []}
	for k in _picker_checks:
		if (_picker_checks[k] as CheckBox).button_pressed:
			out["vars" if String(k).begins_with("v:") else "items"].append(String(k).substr(2))
	return out


## 印の付いたものだけでひな形にして送り、窓を閉じる。何も選んでいなければ送らない。送った名前（送らなければ ""）。
func confirm_preset_picker() -> String:
	if preset_picker == null:
		return ""
	var data := picker_preset()
	if data.is_empty():
		show_debug_notice("ひな形に入れるものを選んでください", {}, -1.0, "", null, "preset")
		return ""
	if _picker_group != null and _picker_group.text.strip_edges() != "":
		data["group"] = _picker_group.text.strip_edges()
	var pn := send_preset_data(_picker_name.text, data)
	if picker_keep_open and pn != "":
		_picker_name.text = next_preset_name(pn)   # 同じ名前で上書きしないよう、次の名前にしておく
	else:
		close_preset_picker()
	return pn


## 続けて送るときの次の名前：「名前 2」「名前 3」…（末尾が「 数」ならその次）。
static func next_preset_name(pn: String) -> String:
	var re := RegEx.create_from_string("^(.*) (\\d+)$")
	var m := re.search(pn)
	if m != null:
		return "%s %d" % [m.get_string(1), int(m.get_string(2)) + 1]
	return pn + " 2"


func close_preset_picker() -> void:
	if preset_picker != null:
		preset_picker.queue_free()
		preset_picker = null
	_picker_checks.clear()
	_picker_values.clear()
	_picker_list = null
	_picker_none = null
	_picker_removed.clear()
	_picker_restore_btn = null


## いまの場所 {scene, dialogue?（JSON の会話）, knot?（Ink のノット）}。
func current_location() -> Dictionary:
	var loc := {"scene": core.state.scene}
	for n in core.adapters_by_name:
		var q = core.adapters_by_name[n].query("location")
		if q is Dictionary:
			for k in q:
				if String(q[k]) != "":
					loc[k] = q[k]
	return loc


## エディタの「このシーンから実行」の頼み（user:// のファイル）。あれば読んで消し、始めるシーンを返す（30 秒より古いものは使わない）。
const RUN_FROM_FILE := "user://adv80s_run_from.json"


static func take_run_from_request() -> String:
	return String(take_run_from().get("scene", ""))


## 頼みをまるごと読む（読んで消す。30 秒より古いもの・形の違うものは {}）。
## {scene, time, dialogue?, line?, knot?, preset?, vars?: {名前: 値}, items?: {ID: 個数}}
static func take_run_from() -> Dictionary:
	if not FileAccess.file_exists(RUN_FROM_FILE):
		return {}
	var d = AdvJson.load_file(RUN_FROM_FILE, [])
	DirAccess.remove_absolute(RUN_FROM_FILE)
	if not d is Dictionary:
		return {}
	if absf(Time.get_unix_time_from_system() - float(d.get("time", 0))) > 30.0:
		return {}
	# JSON の数は小数で返るので、行と道筋の番目は整数に（選択肢の項目の番目は文字のまま）
	if d.has("line"):
		d["line"] = int(d["line"])
	if d.get("path") is Array:
		d["path"] = d["path"].map(func(e): return int(e) if (e is int or e is float) else e)
	return d


## 「先に設定：a = 1、b = true …ほか 3」（limit が 0 以下なら全部）。
static func pre_set_text(log: Dictionary, limit: int = 4) -> String:
	var parts: Array = []
	for k in log:
		if limit > 0 and parts.size() >= limit:
			break
		var v = log[k]
		parts.append("%s = %s" % [k, str(int(v)) if v is float and v == floorf(v) and absf(v) < 1e15 else JSON.stringify(v)])
	var rest := log.size() - parts.size()
	return "先に設定：%s%s" % ["、".join(parts), " …ほか %d" % rest if rest > 0 else ""]


## どこから始めるか：「会話 talk から」「会話 talk の 3 番目から」「会話 talk の 3 › そうなら › 1 番目から」「ノット k から」。なければ ""。
static func run_place_text(req: Dictionary) -> String:
	var dl := String(req.get("dialogue", ""))
	if dl != "":
		var path: Array = req["path"] if req.get("path") is Array and not req["path"].is_empty() else [int(req.get("line", 0))]
		var ps = req.get("pre_sets", false)
		var tail := "（設定を先に・条件も）" if str(ps) == "cond" else ("（設定を先に）" if ps is bool and ps else "")
		if path.size() == 1 and int(path[0]) <= 0:
			return "会話 %s から%s" % [dl, tail]
		return "会話 %s の %s 番目から%s" % [dl, path_text(path), tail]
	if String(req.get("knot", "")) != "":
		return "ノット %s から" % String(req["knot"])
	return ""


## 道筋を人の読む形に：[2, "then", 0] → 「3 › そうなら › 1」、[1, "choice", "options", "0", "do", 2] → 「2 › 選択肢 1 › 3」。
static func path_text(path: Array) -> String:
	var out: Array = []
	var i := 0
	while i < path.size():
		var e = path[i]
		if e is int or e is float:
			out.append(str(int(e) + 1))
		elif String(e) == "then":
			out.append("そうなら")
		elif String(e) == "else":
			out.append("そうでないなら")
		elif String(e) == "choice" and i + 3 < path.size() and String(path[i + 1]) == "options":
			out.append("選択肢 %d" % (int(String(path[i + 2])) + 1))
			i += 3   # "options", 番目, "do" を飛ばす
		else:
			out.append(String(e))
		i += 1
	return " › ".join(out)


## 頼みの vars・items を、始める前の状態に入れる（変数は set_var、持ち物は個数。0 以下なら持たない）。
func apply_run_values(req: Dictionary) -> void:
	var vs = req.get("vars", {})
	if vs is Dictionary:
		for k in vs:
			core.state.set_var(String(k), vs[k])
	var its = req.get("items", {})
	if its is Dictionary:
		for k in its:
			var n := int(its[k])
			if n > 0:
				core.state.items[String(k)] = n
			else:
				core.state.items.erase(String(k))


## 「シーンから実行：hall（会話 talk の 3 番目から、ひな形 終盤）」
static func run_from_text(req: Dictionary) -> String:
	var s := "シーンから実行：%s" % String(req.get("scene", ""))
	var parts: Array = []
	var place := run_place_text(req)
	if place != "":
		parts.append(place)
	if String(req.get("preset", "")) != "":
		parts.append("ひな形 %s" % String(req["preset"]))
	return s + ("（%s）" % "、".join(parts) if not parts.is_empty() else "")


## 変わったファイルを短く（「a.json、b.png ほか 2 件」）。limit は名前を出す数（プロジェクト設定 debug.notice_files、既定 2）。
static func changes_text(changes: Array, limit: int = 2) -> String:
	if changes.is_empty() or limit <= 0:
		return ""
	var names := changes.slice(0, limit).map(func(p): return String(p).get_file())
	var t := "、".join(names)
	if changes.size() > limit:
		t += " ほか %d 件" % (changes.size() - limit)
	return t


## デバッグ実行中、プロジェクト設定の debug.auto_reload が書き換わったら（シナリオエディタの「保存で読み直す」など）、
## 自動の読み直しを入・切する（2秒ごとにプロジェクト設定のファイルだけを見る）。
func _start_debug_poll() -> void:
	if _poll_timer != null:
		return
	_poll_timer = Timer.new()
	_poll_timer.name = "DebugPoll"
	_poll_timer.wait_time = 2.0
	_poll_timer.timeout.connect(poll_debug_settings)
	add_child(_poll_timer)
	_poll_mtime = FileAccess.get_modified_time(project_path) if FileAccess.file_exists(project_path) else -1
	_poll_auto = bool(_debug_conf().get("auto_reload", false))
	_poll_timer.start()


## プロジェクト設定のファイルが変わっていて、debug.auto_reload が前と違えば、それに合わせる。合わせたら true。
func poll_debug_settings() -> bool:
	var mt := FileAccess.get_modified_time(project_path) if FileAccess.file_exists(project_path) else -1
	if mt == _poll_mtime:
		return false
	_poll_mtime = mt
	var data = AdvJson.load_file(project_path, [])
	if not data is Dictionary:
		return false
	var dbg = data.get("debug", {})
	var on := dbg is Dictionary and bool(dbg.get("auto_reload", false))
	if _poll_auto != null and on == bool(_poll_auto):
		return false
	_poll_auto = on
	if on != is_auto_reload():
		set_auto_reload(on)
		show_debug_notice("保存したら読み直す：%s" % ("入" if on else "切"), {}, -1.0, "", null, "auto_reload")
		return true
	return false


## デバッグコンソールを開く（デバッグビルド専用）。
func open_debug_console() -> void:
	if not OS.is_debug_build() or _debug_layer == null:
		return
	if _overlay != null:
		if _overlay.has_method("close_and_resume"):
			_overlay.call("close_and_resume")
			return
		_overlay.call("close")
	var script: Script = load("res://addons/adv80s/debug/adv_debug_console.gd")
	if script == null:
		return
	var console: Control = script.new()
	console.set("player", self)
	console.call("setup", core)
	console.connect("data_modified", apply_debug_changes)
	console.connect("open_scene_graph_requested", func() -> void:
		console.call("close_and_resume")
		call_deferred("open_scene_graph")
	)
	_overlay = console
	_debug_layer.add_child(console)
	await console.closed
	if is_instance_valid(console):
		console.queue_free()
	if _overlay == console:
		_overlay = null


## シーングラフを開く（デバッグビルド専用）。
func open_scene_graph() -> void:
	if not OS.is_debug_build() or _debug_layer == null:
		return
	if _overlay != null:
		if _overlay.has_method("handle_escape") and not _overlay.has_method("close_and_resume"):
			_overlay.call("close")
			return
		_overlay.call("close")
	var script: Script = load("res://addons/adv80s/debug/adv_scene_graph_view.gd")
	if script == null:
		return
	var view: Control = script.new()
	view.call("setup_from_core", core, core.state.scene if core != null and core.state != null else "")
	_overlay = view
	_debug_layer.add_child(view)
	await view.closed
	if is_instance_valid(view):
		view.queue_free()
	if _overlay == view:
		_overlay = null


## デバッグコンソールでデータを変更した後に再開した際、そのデータで画面・スプライト・コマンド候補を更新する。
func apply_debug_changes(scene_changed: bool = false) -> void:
	if core == null or screen == null:
		return
	var evs: Array[Dictionary] = core.sync_debug_state(scene_changed)
	for ev in evs:
		await _play(ev)
	_redraw_view()
	if not busy:
		_enter_idle()


## 開発中だけ使う仮の鍵（製品版では使わない）。
class _DevKeyProvider extends AdvKeyProvider:
	var _k: PackedByteArray
	func _init(seed_text: String) -> void:
		_k = AdvKeyProvider.sha256(("adv80s-dev-key:" + seed_text).to_utf8_buffer())
	func get_master_key() -> PackedByteArray:
		return _k
