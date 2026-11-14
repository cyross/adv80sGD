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
const MENU_CHANGE_ID := 6
const MENU_MIGRATE := 7

## 設定のタブ：[タブ名, [項目名…]]。最後の「その他」には、ほかのタブにない項目が入る
const GAME_TABS := [
	["初期設定", ["title", "game_id", "template", "templates", "entry", "lang", "seed", "input_devices", "features"]],
	["変数", ["variables", "constants"]],
	["コマンド", ["verbs", "inputs", "dictionaries", "slot_mode", "intent_schema"]],
	["セリフ", ["event_defaults", "hint_topics"]],
	["アセット", ["asset_roots", "asset_folders", "missing_asset"]],
	["タイトル", ["title_screen", "title_image", "title_bgm", "title_bgm_fade", "title_transition", "title_menu", "title_labels",
		"title_variants", "opening", "opening_replay", "opening_hint"]],
	["おわり・おまけ", ["endings", "fin", "extras"]],
	["システム", ["system_scenes", "subscene_max_depth", "aliases", "save", "notices", "notice_style", "debug"]],
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
## シーンの種類（kind）の表示名（カードに出す）
const KIND_NAMES := {"title": "タイトル", "opening": "オープニング", "ending": "エンディング", "system": "システム", "sub": "サブシーン"}

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
var region_editor: AdvRegionEditor
var _undo_b: Button
var _redo_b: Button
var _start_row: HBoxContainer
var _start_pick: OptionButton
# 新規作成（名前と ID）
var _new_dialog: ConfirmationDialog
var _new_name: LineEdit
var _new_id: LineEdit
var _new_msg: Label
var _new_level: String = ""
var _new_id_touched: bool = false
var _new_done: Callable


func _init(project_path: String = AdvProject.DEFAULT_PATH) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_set_model(AdvScenarioModel.new(project_path))
	_build()


## エディタの画面に出したとき。ファイルから読み直す。
func reload() -> void:
	_set_model(AdvScenarioModel.new(model.project_path))
	_sync_auto_reload_toggle()
	_ext_snap = files_snapshot()
	if check_panel != null and check_panel.visible:
		refresh_check.call_deferred()
	_refresh_expr_candidates()
	if not model.has_root():
		_show(Page.ROOT)
	elif page == Page.ROOT:
		_show(Page.GAME)
	else:
		_show(page)


func set_project_path(path: String) -> void:
	_set_model(AdvScenarioModel.new(path))


func _set_model(m: AdvScenarioModel) -> void:
	model = m
	model.files_changed.connect(_on_files_changed)


var _recheck_pending := false
var _ext_snap: Dictionary = {}


## エディタが扱うファイル（プロジェクト設定、シナリオのファイル、Ink のソース）→ 更新時刻。
func files_snapshot() -> Dictionary:
	var snap := {}
	var files: Array = [model.project_path]
	files.append_array(model.all_files())
	files.append_array(all_ink_sources())
	for f in files:
		if FileAccess.file_exists(String(f)):
			snap[String(f)] = AdvPlayer.file_stamp(String(f))
	return snap


## エディタの外で書き換えられたファイルがあれば読み直す（書きかけがあれば画面はそのまま、ID の確認だけ）。
## 書き換えられていたファイルを返す。
func check_external_changes() -> Array:
	var now := files_snapshot()
	var changed := []
	for p in now:
		if not _ext_snap.has(p) or _ext_snap[p] != now[p]:
			changed.append(p)
	for p in _ext_snap:
		if not now.has(p):
			changed.append(p)
	if changed.is_empty():
		return []
	changed.sort()
	if _dirty:
		_ext_snap = now
		if check_panel.visible:
			refresh_check()
		_set_status("ほかで書き換えられたファイルがあります（書きかけを保存してから読み直してください）")
	else:
		reload()
		if check_panel.visible:
			refresh_check()
		_set_status("ほかで書き換えられたファイルを読み直しました：%s" % AdvPlayer.changes_text(changed))
	return changed


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_visible_in_tree():
		if not _ext_snap.is_empty():
			check_external_changes.call_deferred()
		if FileAccess.file_exists(AdvPlayer.GAME_PRESETS_FILE):
			import_game_presets.call_deferred()
		if FileAccess.file_exists(AdvPlayer.GAME_SETTINGS_FILE):
			import_game_settings.call_deferred()


## ゲームの「エディタで開く」：シーンを開き、会話（dialogue）か Ink のノットがあれば、そのセリフを開く。開けたら true。
func open_location(scene: String, location: Dictionary = {}) -> bool:
	var ok := open_scene_by_id(scene)
	var dl := String(location.get("dialogue", ""))
	var knot := String(location.get("knot", ""))
	if dl != "" and sid != "":
		for c in model.chapters(sid):
			var cidc := String(c["id"]) if c is Dictionary else String(c)
			if model.load_chapter_data(sid, cidc).get("dialogues", {}).has(dl):
				cid = cidc
				_open_dialogue({"kind": "json", "id": dl})
				_set_status("会話を開きました：%s" % dl)
				return true
	if knot != "":
		var name := knot.get_slice(".", 0)
		var re := RegEx.create_from_string("^\\s*={2,}\\s*" + _re_escape(name) + "\\b")
		for f in all_ink_sources():
			var lines := FileAccess.get_file_as_string(f).split("\n")
			for li in lines.size():
				if re.search(lines[li]) != null:
					_open_dialogue({"kind": "ink", "id": String(f).get_file().trim_suffix(".ink"), "path": f})
					_ink_code.set_caret_line(li)
					_ink_code.center_viewport_to_caret()
					_set_status("Ink のノットを開きました：%s" % knot)
					return true
	return ok


## エディタの「このシーンから実行」：ゲームに始めるシーンを知らせ（user:// のファイル）、エディタからゲームを動かす。
func run_from_scene(id: String, play: bool = true) -> bool:
	return run_from({"scene": id}, play)


# ---------------------------------------------------------------- 実行（段階36：途中から、ひな形、履歴）

const RUN_HISTORY_FILE := "user://adv80s_run_history.json"
const RUN_HISTORY_MAX := 10

var run_preset_pick: OptionButton     ## 実行に使うひな形（0 は「ひな形なし」）
var run_history_menu: MenuButton      ## 最近の実行（選ぶとすぐ動かす）
var selected_preset: String = ""      ## いま選んでいるひな形の名前（"" はなし）
var _preset_dialog: ConfirmationDialog
var _preset_name: LineEdit
var _preset_vars: TextEdit
var _preset_items: TextEdit
var _preset_msg: Label
var _preset_group: LineEdit            ## 組（"" は組なし）
var _preset_dates: Label               ## 作った日時・最後に使った日時
var _preset_run_last: Button           ## そこから動かす（段階53）
var _start_vals: Dictionary = {}       ## いつもの始まりの変数（名前 → 初めの値）。窓を開いたときに読む
const PRESET_CMP_START := "\u0001start"   ## 「比べる：」の「いつもの始まり」
var _preset_cmp: OptionButton          ## 比べるひな形（0 は「比べない」）
var _preset_diff: RichTextLabel        ## 違うところ
var _preset_export_dialog: FileDialog
var _preset_export_pick: ConfirmationDialog   ## 書き出すひな形を選ぶ窓
var _export_checks: Dictionary = {}           ## 名前 → CheckBox
var _export_list: VBoxContainer
var export_names: Array = []                  ## 選んだ名前（[] は全部）
var _preset_import_dialog: FileDialog
var run_pre_sets: bool = false         ## 会話の途中から実行するとき、そこまでの「設定する」を先に動かす
var run_pre_cond: bool = false         ## そのとき、前にある「もし」も条件を見て動かす（run_pre_sets のときだけ）
var _pre_sets_check: CheckBox
var _pre_cond_check: CheckBox


## 頼み {scene, dialogue?, line?, knot?, preset?} でゲームを動かす。preset を書かなければ、いま選んでいるひな形を使う。
## ひな形の vars・items はこのときの値を入れる。履歴にも足す。
func run_from(req: Dictionary, play: bool = true) -> bool:
	var id := String(req.get("scene", ""))
	if id == "":
		_set_status("始めるシーンがありません")
		return false
	if _dirty:
		save()
	var r := {"scene": id}
	for k in ["dialogue", "knot"]:
		if String(req.get(k, "")) != "":
			r[k] = String(req[k])
	if r.has("dialogue"):
		match pre_sets_mode(req.get("pre_sets", false)):
			"plain":
				r["pre_sets"] = true
			"cond":
				r["pre_sets"] = "cond"
		var path: Array = req["path"] if req.get("path") is Array else []
		if path.size() > 1:
			r["path"] = path.duplicate()
		elif (path.size() == 1 and int(path[0]) > 0) or (path.is_empty() and int(req.get("line", 0)) > 0):
			r["line"] = int(path[0]) if path.size() == 1 else int(req["line"])
	var pn := String(req.get("preset", selected_preset))
	var note := ""
	if pn != "":
		var ps: Dictionary = run_presets()
		if ps.get(pn) is Dictionary:
			r["preset"] = pn
			var at := r.duplicate(true)
			at.erase("preset")
			_mark_preset_used(pn, -1.0, AdvPlayer.run_place_text(r).trim_suffix("から"), id, at)
			for k in ["vars", "items"]:
				if ps[pn].get(k) is Dictionary and not ps[pn][k].is_empty():
					r[k] = ps[pn][k].duplicate(true)
		else:
			note = "（ひな形 %s は見つからないので、なしで）" % pn
	var f := FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
	if f == null:
		_set_status("書けません：%s" % AdvPlayer.RUN_FROM_FILE)
		return false
	var w := r.duplicate(true)
	w["time"] = Time.get_unix_time_from_system()
	f.store_string(JSON.stringify(w))
	f.close()
	_add_history(r)
	if play and Engine.is_editor_hint():
		EditorInterface.play_main_scene()
	_set_status("実行します：%s%s" % [history_label(r), note])
	return true


## 開いている会話・Ink から実行：JSON の会話は選んでいる手順から（選んでいなければ頭から）、Ink はカーソルのあるノットから。
## シーンは開いていたシーン（なければチャプターの最初のシーン、それもなければ開始のシーン）。
func run_from_dialogue(play: bool = true) -> bool:
	var scene := run_scene_for_dialogue()
	if String(dlg.get("kind", "")) == "ink":
		var knot := ink_knot_at(_ink_code.text, _ink_code.get_caret_line())
		if knot == "":
			_set_status("カーソルの上にノット（== 名前）がありません")
			return false
		return run_from({"scene": scene, "knot": knot}, play)
	return run_from({"scene": scene, "dialogue": String(dlg.get("id", "")), "path": _dlg_steps.selected_path(),
		"pre_sets": ("cond" if run_pre_cond else true) if run_pre_sets else false}, play)


## 頼みの pre_sets を「""（しない）」「plain（設定するだけ）」「cond（もしも見る）」に。
static func pre_sets_mode(v: Variant) -> String:
	if v is bool:
		return "plain" if v else ""
	return "cond" if str(v) == "cond" else ""


func run_scene_for_dialogue() -> String:
	if scene_id != "" and model.all_scene_ids().has(scene_id):
		return scene_id
	var sc := model.scenes(sid, cid) if sid != "" and cid != "" else []
	if not sc.is_empty():
		return String(sc[0]["id"])
	return String(model.load_project().get("entry", ""))


## Ink のソースの line 行目（0 から）を含むノットの名前。上に「= ステッチ」があれば「ノット.ステッチ」。なければ ""。
static func ink_knot_at(text: String, line: int) -> String:
	var lines := text.split("\n")
	var knot_re := RegEx.create_from_string("^\\s*={2,}\\s*(?:function\\s+)?([A-Za-z_][A-Za-z0-9_]*)")
	var stitch_re := RegEx.create_from_string("^\\s*=\\s*([A-Za-z_][A-Za-z0-9_]*)")
	var stitch := ""
	for i in range(mini(line, lines.size() - 1), -1, -1):
		var m := knot_re.search(lines[i])
		if m != null:
			return m.get_string(1) + ("." + stitch if stitch != "" else "")
		if stitch == "":
			var s := stitch_re.search(lines[i])
			if s != null:
				stitch = s.get_string(1)
	return ""


## ゲームの「ひな形に」（コンソールの preset）で書かれたひな形（AdvPlayer.GAME_PRESETS_FILE）を取り込んで、ファイルを消す。
## 同じ名前は上書き。ひとまとまりで書く（元に戻せる）。最後のものを選ぶ。取り込んだ名前を返す。
func import_game_presets() -> Array:
	if not FileAccess.file_exists(AdvPlayer.GAME_PRESETS_FILE):
		return []
	var list = AdvJson.load_file(AdvPlayer.GAME_PRESETS_FILE, [])
	DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
	if not list is Array:
		return []
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary:
		d = {}
	var ps = d.get("run_presets", {})
	if not ps is Dictionary:
		ps = {}
	var names: Array = []
	for e in list:
		if not e is Dictionary or String(e.get("name", "")).strip_edges() == "":
			continue
		var v := {}
		if e.get("vars") is Dictionary and not e["vars"].is_empty():
			v["vars"] = e["vars"]
		if e.get("items") is Dictionary and not e["items"].is_empty():
			var its := {}
			for k in e["items"]:
				its[k] = int(e["items"][k])
			v["items"] = its
		if preset_group(e) != "":
			v["group"] = preset_group(e)
		v["created"] = float(e.get("time", 0)) if float(e.get("time", 0)) > 0.0 else Time.get_unix_time_from_system()
		var n := String(e["name"]).strip_edges()
		ps[n] = v
		if not names.has(n):
			names.append(n)
	if names.is_empty():
		return []
	d["run_presets"] = ps
	p["debug"] = d
	model.begin("ゲームからひな形：%s" % "、".join(names))
	model.write_json(model.project_path, p)
	model.end()
	selected_preset = String(names.back())
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("ゲームからひな形を取り込みました：%s" % "、".join(names))
	return names


## ゲームのコンソールの notice save・noticestyle save で書かれたもの（AdvPlayer.GAME_SETTINGS_FILE）を、
## プロジェクト設定 debug.notices・debug.notice_style に書いてファイルを消す（知らない種類・キーは飛ばす）。
## ひとまとまりで書く（元に戻せる）。書いたもの {notices?: {…}, notice_style?: {…}} を返す（なければ {}）。
func import_game_settings() -> Dictionary:
	if not FileAccess.file_exists(AdvPlayer.GAME_SETTINGS_FILE):
		return {}
	var s = AdvJson.load_file(AdvPlayer.GAME_SETTINGS_FILE, [])
	DirAccess.remove_absolute(AdvPlayer.GAME_SETTINGS_FILE)
	if not s is Dictionary:
		return {}
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary:
		d = {}
	var got := {}
	if s.get("notices") is Dictionary:
		var ns = d.get("notices", {})
		if not ns is Dictionary:
			ns = {}
		var g1 := {}
		for k in s["notices"]:
			if AdvPlayer.DEBUG_NOTICE_KINDS.has(String(k)):
				ns[String(k)] = bool(s["notices"][k])
				g1[String(k)] = ns[String(k)]
		if not g1.is_empty():
			d["notices"] = ns
			got["notices"] = g1
	if s.get("notice_style") is Dictionary:
		var st = d.get("notice_style", {})
		if not st is Dictionary:
			st = {}
		var g2 := {}
		for k in s["notice_style"]:
			if AdvPlayer.DEBUG_NOTICE_STYLE_KEYS.has(String(k)):
				var v = s["notice_style"][k]
				if String(k) in ["fg", "bg", "border"]:
					v = int(v)
				st[String(k)] = v
				g2[String(k)] = v
		if not g2.is_empty():
			d["notice_style"] = st
			got["notice_style"] = g2
	if s.get("game_notice_style") is Dictionary:
		# ふつうのお知らせの見た目：プロジェクト設定のいちばん上の notice_style へ
		var gst = p.get("notice_style", {})
		if not gst is Dictionary:
			gst = {}
		var g3 := {}
		for k in s["game_notice_style"]:
			if AdvPlayer.GAME_NOTICE_STYLE_KEYS.has(String(k)):
				var v = s["game_notice_style"][k]
				if String(k) in ["fg", "bg", "border", "margin", "icon_size", "max"]:
					v = int(v)
				gst[String(k)] = v
				g3[String(k)] = v
		if not g3.is_empty():
			p["notice_style"] = gst
			got["game_notice_style"] = g3
	if got.is_empty():
		return {}
	if got.has("notices") or got.has("notice_style"):
		p["debug"] = d
	model.begin("ゲームからお知らせの設定")
	model.write_json(model.project_path, p)
	model.end()
	_update_undo_buttons()
	var parts: Array = []
	for k in got.get("notices", {}):
		parts.append("%s=%s" % [k, "出す" if got["notices"][k] else "出さない"])
	for k in got.get("notice_style", {}):
		parts.append("%s=%s" % [k, str(got["notice_style"][k])])
	for k in got.get("game_notice_style", {}):
		parts.append("お知らせ.%s=%s" % [k, str(got["game_notice_style"][k])])
	_set_status("ゲームからお知らせの設定を書きました：%s" % "、".join(parts))
	return got


## ひな形（プロジェクト設定 debug.run_presets：名前 → {vars, items}）。
func run_presets() -> Dictionary:
	var d = model.load_project().get("debug", {})
	var ps = d.get("run_presets", {}) if d is Dictionary else {}
	return ps if ps is Dictionary else {}


func save_run_preset(pname: String, vars: Dictionary, items: Dictionary, group: String = "") -> Error:
	pname = pname.strip_edges()
	if pname == "":
		return ERR_INVALID_PARAMETER
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary:
		d = {}
	var ps = d.get("run_presets", {})
	if not ps is Dictionary:
		ps = {}
	var v := {}
	if not vars.is_empty():
		v["vars"] = vars
	if not items.is_empty():
		v["items"] = items
	if group.strip_edges() != "":
		v["group"] = group.strip_edges()
	# 作った時刻：書きかえなら前のまま、新しければいま
	v["created"] = float(ps[pname].get("created", 0)) if ps.get(pname) is Dictionary and float(ps[pname].get("created", 0)) > 0.0 else Time.get_unix_time_from_system()
	ps[pname] = v
	d["run_presets"] = ps
	p["debug"] = d
	model.begin("ひな形を保存：%s" % pname)
	var err := model.write_json(model.project_path, p)
	model.end()
	selected_preset = pname
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("ひな形を保存しました：%s" % pname)
	return err


func delete_run_preset(pname: String) -> Error:
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary or not d["run_presets"].has(pname):
		return ERR_DOES_NOT_EXIST
	d["run_presets"].erase(pname)
	if d["run_presets"].is_empty():
		d.erase("run_presets")
	p["debug"] = d
	model.begin("ひな形を消す：%s" % pname)
	var err := model.write_json(model.project_path, p)
	model.end()
	if selected_preset == pname:
		selected_preset = ""
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("ひな形を消しました：%s" % pname)
	return err


func select_preset(pname: String) -> void:
	selected_preset = pname if run_presets().has(pname) else ""
	_fill_preset_pick()


## ひな形の組（"" は組なし）。
static func preset_group(v: Variant) -> String:
	return String(v.get("group", "")).strip_edges() if v is Dictionary else ""


## 「実行：」の一覧に出す順：組なし（名前の順）、そのあと組ごと（組の名前の順。組の中は名前の順）。
## filter（名前か組の一部。大文字・小文字は区別しない）に合うものだけ。keep は合わなくても入れる（選んでいるもの）。
## [[組, [名前…]], …] を返す（組なしは ""）。
static func preset_pick_layout(ps: Dictionary, filter: String = "", keep: String = "", order: Array = [], used: Dictionary = {}) -> Array:
	var t := filter.strip_edges().to_lower()
	var groups := {}
	for n in ps:
		var g := preset_group(ps[n])
		if t != "" and String(n) != keep and not String(n).to_lower().contains(t) and not g.to_lower().contains(t):
			continue
		if not groups.has(g):
			groups[g] = []
		groups[g].append(String(n))
	var keys: Array = groups.keys()
	keys.sort()
	# 組の並び：組なしが先、そのあと order に書いた順、残りは名前の順
	var sorted_keys: Array = []
	if keys.has(""):
		sorted_keys.append("")
	for g in order:
		if keys.has(String(g)) and String(g) != "" and not sorted_keys.has(String(g)):
			sorted_keys.append(String(g))
	for g in keys:
		if not sorted_keys.has(g):
			sorted_keys.append(g)
	var out: Array = []
	for g in sorted_keys:
		var names: Array = groups[g]
		names.sort()
		if not used.is_empty():
			# 使った順：新しく使ったものが上、使っていないものは下（同じなら名前の順）
			names.sort_custom(func(a, b):
				var ta := float(used.get(a, 0))
				var tb := float(used.get(b, 0))
				return ta > tb if ta != tb else String(a) < String(b))
		out.append([g, names])
	return out


const RUN_UI_FILE := "user://adv80s_run_ui.json"   ## 「実行：」の一覧の見た目（たたんだ組）。パソコンごと


## たたんだ組の名前。
static func folded_groups() -> Array:
	var d := _run_ui()
	return d.get("folded", []) if d.get("folded") is Array else []


static func _save_folded(list: Array) -> void:
	var d := _run_ui()
	d["folded"] = list
	_save_run_ui(d)


## 「実行：」の見た目の覚え書き（たたんだ組 folded、ひな形を最後に使った時刻 last_used）。
static func _run_ui() -> Dictionary:
	var d = AdvJson.load_file(RUN_UI_FILE, []) if FileAccess.file_exists(RUN_UI_FILE) else {}
	return d if d is Dictionary else {}


static func _save_run_ui(d: Dictionary) -> void:
	var f := FileAccess.open(RUN_UI_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


const RUN_SORTS := ["name", "used", "created"]
const RUN_SORT_LABELS := ["名前の順", "使った順", "作った順"]


## 「実行：」の一覧の並べ方（"name"・"used"・"created"。パソコンごと）。
static func run_sort() -> String:
	var s := String(_run_ui().get("sort", "name"))
	return s if RUN_SORTS.has(s) else "name"


static func run_sort_by_used() -> bool:
	return run_sort() == "used"


func set_run_sort(mode: String) -> void:
	if not RUN_SORTS.has(mode):
		mode = "name"
	var d := _run_ui()
	d["sort"] = mode
	_save_run_ui(d)
	if _sort_pick != null and _sort_pick.selected != RUN_SORTS.find(mode):
		_sort_pick.select(RUN_SORTS.find(mode))
	_fill_preset_pick()


func set_run_sort_by_used(on: bool) -> void:
	set_run_sort("used" if on else "name")


## ひな形を作った時刻（Unix 秒。わからなければ 0）。
func preset_created(name: String) -> float:
	var v = run_presets().get(name)
	return float(v.get("created", 0)) if v is Dictionary else 0.0


var _sort_pick: OptionButton


## しばらく使っていないひな形：最後に使ってから days 日より前のもの（include_unused なら一度も使っていないものも）。名前の順。
## group が "*" なら全部の組、"" なら組なし、ほかはその組だけ。
func stale_presets(days: int, include_unused: bool = false, now: float = -1.0, group: String = "*") -> Array:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	var out: Array = []
	var ps := run_presets()
	for n in ps:
		if group != "*" and preset_group(ps[n]) != group:
			continue
		var t := preset_last_used(String(n))
		if (t <= 0.0 and include_unused) or (t > 0.0 and now - t >= days * 86400.0):
			out.append(String(n))
	out.sort()
	return out


## ひな形をまとめて消す。ひとまとまりで書く（元に戻せる）。消した数。
func delete_run_presets(names: Array) -> int:
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary:
		return 0
	var n := 0
	for k in names:
		if d["run_presets"].has(k):
			d["run_presets"].erase(k)
			n += 1
	if n == 0:
		return 0
	if d["run_presets"].is_empty():
		d.erase("run_presets")
	p["debug"] = d
	model.begin("ひな形をまとめて消す（%d）" % n)
	model.write_json(model.project_path, p)
	model.end()
	if names.has(selected_preset):
		selected_preset = ""
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("ひな形をまとめて消しました（%d）" % n)
	return n


## ひな形をまとめて組 g に入れる（ほかのものはそのまま）。ひとまとまりで書く（元に戻せる）。入れた数。
func set_presets_group(names: Array, g: String) -> int:
	g = g.strip_edges()
	if g == "":
		return 0
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary:
		return 0
	var n := 0
	for k in names:
		var v = d["run_presets"].get(k)
		if v is Dictionary and preset_group(v) != g:
			v["group"] = g
			n += 1
	if n == 0:
		return 0
	p["debug"] = d
	model.begin("ひな形を組に寄せる：%s（%d）" % [g, n])
	model.write_json(model.project_path, p)
	model.end()
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("ひな形を組「%s」に寄せました（%d）" % [g, n])
	return n


var _tidy_dialog: AcceptDialog
var _tidy_days: SpinBox
var _tidy_unused: CheckBox
var _tidy_preview: RichTextLabel             ## 片付けの窓：印を付けたひな形の中身
var _tidy_compare: CheckBox                   ## 片付けの窓：中身の欄を「二つを比べる」にする
var _tidy_group_pick: OptionButton            ## 片付けの窓：どの組から探すか（"*" 全部、"" 組なし）
var _tidy_list: VBoxContainer
var _tidy_checks: Dictionary = {}
var _tidy_group: LineEdit
var _tidy_confirm: ConfirmationDialog


## 片付けの窓：しばらく使っていないひな形を並べる（初めは全部に印）。
func open_tidy_dialog(group: String = "*") -> void:
	_tidy_group_pick.clear()
	_tidy_group_pick.add_item("すべての組")
	_tidy_group_pick.set_item_metadata(0, "*")
	_tidy_group_pick.add_item("組なし")
	_tidy_group_pick.set_item_metadata(1, "")
	for g in preset_group_order():
		_tidy_group_pick.add_item("組：%s" % g)
		_tidy_group_pick.set_item_metadata(_tidy_group_pick.item_count - 1, g)
	set_tidy_group(group)
	_refresh_tidy()
	_tidy_dialog.popup_centered(Vector2i(560, 540))


func _refresh_tidy() -> void:
	for c in _tidy_list.get_children():
		c.queue_free()
	_tidy_checks.clear()
	var names := stale_presets(int(_tidy_days.value), _tidy_unused.button_pressed, -1.0, tidy_group())
	for n in names:
		var cb := CheckBox.new()
		var t := preset_last_used(n)
		var g := preset_group(run_presets().get(n, {}))
		cb.text = "%s　〔%s〕%s" % [n, used_label(t), "（組：%s）" % g if g != "" else ""]
		fit_check(cb, preset_summary(n))
		cb.button_pressed = true
		cb.toggled.connect(func(_on): _update_tidy_preview())
		_tidy_list.add_child(cb)
		_tidy_checks[n] = cb
	if names.is_empty():
		var l := Label.new()
		l.text = "（しばらく使っていないひな形はありません）"
		_tidy_list.add_child(l)
	_update_tidy_preview()


## 一覧の印の行：長い名前は「…」で切り、全文を説明（ツールチップ）に出す（段階60）。extra は説明の下に足す。
static func fit_check(cb: CheckBox, extra: String = "") -> void:
	cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cb.clip_text = true
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.tooltip_text = cb.text + ("\n" + extra if extra != "" else "")


## 一覧を入れる箱：横には広げず、窓の幅に合わせる。
static func fit_list_scroll(sc: ScrollContainer) -> void:
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


## 片付けの窓を並べ直す（印はそのまま。新しく出てきたものは初めの形で印を付ける）。開いたまま元に戻す・やり直すをしたときなど。
func refresh_tidy_keep() -> void:
	var was := {}
	for n in _tidy_checks:
		was[n] = (_tidy_checks[n] as CheckBox).button_pressed
	_refresh_tidy()
	for n in _tidy_checks:
		if was.has(n):
			(_tidy_checks[n] as CheckBox).set_pressed_no_signal(was[n])
	_update_tidy_preview()


## 印を付けたひな形の中身（名前の順）。印がなければ ""。
## 「二つを比べる」のときは、印が二つなら違うところ（diff_text）、ほかは「印を二つ付けてください」。
func tidy_preview_text() -> String:
	var lines: Array = []
	var names: Array = tidy_selection()
	names.sort()
	if _tidy_compare != null and _tidy_compare.button_pressed:
		if names.size() != 2:
			return "印を二つ付けてください（いま %d）" % names.size()
		var ps := run_presets()
		return tidy_diff_text(ps.get(names[0], {}), ps.get(names[1], {}), names[0], names[1])
	for n in names:
		lines.append("[b]%s[/b]：%s" % [n, preset_summary(n)])
	return "\n".join(lines)


## 片付けの比べ：違う行ごとに「← 左へ」（右の値を左へ）・「右へ →」（左の値を右へ）を付ける。
static func tidy_diff_text(a: Dictionary, b: Dictionary, an: String, bn: String) -> String:
	var d := diff_presets(a, b)
	if d.is_empty():
		return diff_text(a, b, an, bn)
	var lines: Array = ["[b]%s[/b] ／ [b]%s[/b] の違い（%d）" % [an, bn, d.size()]]
	for e in d:
		var k := String(e["key"]).uri_encode()
		lines.append("%s %s：%s ／ %s　[url=tidy:L:%s:%s]← 左へ[/url]　[url=tidy:R:%s:%s]右へ →[/url]" % ["変数" if e["kind"] == "vars" else "持ち物", e["key"],
			"なし" if e["a"] == null else AdvPlayer.value_text(e["a"]), "なし" if e["b"] == null else AdvPlayer.value_text(e["b"]), e["kind"], k, e["kind"], k])
	lines.append("[url=tidyall:L]［← 全部左へ］[/url]　[url=tidyall:R]［全部右へ →］[/url]　[color=#9ca3af]押すと写して保存します（元に戻せます）[/color]")
	return "\n".join(lines)


func _on_tidy_preview_meta(m: String) -> void:
	if m.begins_with("tidyall:"):
		tidy_copy_all(m == "tidyall:L")
		return
	var parts := m.split(":", true, 3)
	if parts.size() != 4 or parts[0] != "tidy":
		return
	var names: Array = tidy_selection()
	names.sort()
	if names.size() != 2:
		return
	var to_left := parts[1] == "L"
	tidy_copy_value(names[1] if to_left else names[0], names[0] if to_left else names[1], parts[2], parts[3].uri_decode())


## ひな形 from の kind（"vars" か "items"）の key の値を、ひな形 to へ写して保存する（from になければ to から消す）。元に戻せる。写したら true。
func tidy_copy_value(from: String, to: String, kind: String, key: String) -> bool:
	return tidy_copy_values(from, to, [[kind, key]], "%s の %s → %s" % [from, key, to]) == 1


## 片付けの「全部左へ」（to_left）・「全部右へ」：印を付けた二つ（名前の順）の違いを全部写す。一度の「元に戻す」で戻る。写した数。
func tidy_copy_all(to_left: bool) -> int:
	var names: Array = tidy_selection()
	names.sort()
	if names.size() != 2:
		return 0
	var from: String = names[1] if to_left else names[0]
	var to: String = names[0] if to_left else names[1]
	var ps := run_presets()
	var keys: Array = []
	for e in diff_presets(ps.get(from, {}), ps.get(to, {})):
		keys.append([e["kind"], e["key"]])
	return tidy_copy_values(from, to, keys, "%s の違いを全部 → %s" % [from, to])


## from の [[kind, key], …] を to へ写してひとまとまりで保存する（from になければ to から消す。空になった vars・items は消す）。写した数。
func tidy_copy_values(from: String, to: String, keys: Array, label: String) -> int:
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary:
		return 0
	var ps: Dictionary = d["run_presets"]
	if not ps.get(from) is Dictionary or not ps.get(to) is Dictionary or from == to:
		return 0
	var n := 0
	for kk in keys:
		var kind := String(kk[0])
		var key := String(kk[1])
		if not kind in ["vars", "items"]:
			continue
		var src = ps[from].get(kind, {})
		var dst = ps[to].get(kind, {})
		if not dst is Dictionary:
			dst = {}
		var has_src: bool = src is Dictionary and src.has(key)
		if not has_src and not dst.has(key):
			continue
		if has_src and dst.has(key) and _same_value(src[key], dst[key]):
			continue
		if has_src:
			dst[key] = src[key]
		else:
			dst.erase(key)
		if dst.is_empty():
			ps[to].erase(kind)
		else:
			ps[to][kind] = dst
		n += 1
	if n == 0:
		return 0
	p["debug"] = d
	model.begin("ひな形の値を写す：%s" % label)
	model.write_json(model.project_path, p)
	model.end()
	_update_undo_buttons()
	_update_tidy_preview()
	_set_status("写しました（%d）：%s（元に戻せます）" % [n, label])
	return n


func _update_tidy_preview() -> void:
	if _tidy_preview != null:
		_tidy_preview.text = tidy_preview_text()


func tidy_group() -> String:
	return String(_tidy_group_pick.get_item_metadata(_tidy_group_pick.selected)) if _tidy_group_pick.selected >= 0 else "*"


## 片付けの窓で探す組を選ぶ（"*" 全部、"" 組なし）。
func set_tidy_group(g: String) -> void:
	for i in _tidy_group_pick.item_count:
		if String(_tidy_group_pick.get_item_metadata(i)) == g:
			_tidy_group_pick.select(i)
			_refresh_tidy()
			return
	_tidy_group_pick.select(0)
	_refresh_tidy()


func tidy_selection() -> Array:
	var out: Array = []
	for n in _tidy_checks:
		if (_tidy_checks[n] as CheckBox).button_pressed:
			out.append(n)
	return out


func set_tidy_check(n: String, on: bool) -> void:
	if _tidy_checks.has(n):
		(_tidy_checks[n] as CheckBox).button_pressed = on


## 片付けの窓の「組に寄せる」。寄せた数。
func tidy_to_group() -> int:
	var c := set_presets_group(tidy_selection(), _tidy_group.text)
	_refresh_tidy()
	return c


## 片付けの窓の「消す」（確かめたあと）。消した数。
func tidy_delete() -> int:
	var c := delete_run_presets(tidy_selection())
	_refresh_tidy()
	return c


func _build_tidy_dialog() -> void:
	_tidy_dialog = AcceptDialog.new()
	_add_keys(_tidy_dialog, _on_tidy_key)
	_tidy_dialog.title = "ひな形の片付け"
	_tidy_dialog.ok_button_text = "閉じる"
	var b := VBoxContainer.new()
	_tidy_dialog.add_child(b)
	var r := HBoxContainer.new()
	b.add_child(r)
	var l := Label.new()
	l.text = "使っていない日数"
	r.add_child(l)
	_tidy_days = SpinBox.new()
	_tidy_days.min_value = 1
	_tidy_days.max_value = 3650
	_tidy_days.value = 30
	_tidy_days.suffix = "日以上"
	_tidy_days.custom_minimum_size = Vector2(130, 0)
	_tidy_days.value_changed.connect(func(_v): _refresh_tidy())
	r.add_child(_tidy_days)
	_tidy_unused = CheckBox.new()
	_tidy_unused.text = "一度も使っていないものも"
	_tidy_unused.toggled.connect(func(_on): _refresh_tidy())
	r.add_child(_tidy_unused)
	var rg := HBoxContainer.new()
	b.add_child(rg)
	var lg := Label.new()
	lg.text = "探す組"
	rg.add_child(lg)
	_tidy_group_pick = OptionButton.new()
	_tidy_group_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tidy_group_pick.item_selected.connect(func(_i): _refresh_tidy())
	rg.add_child(_tidy_group_pick)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, 220)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 窓を広げると一覧が伸びる（段階62）
	fit_list_scroll(sc)
	b.add_child(sc)
	_tidy_list = VBoxContainer.new()
	_tidy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_tidy_list)
	var pr := HBoxContainer.new()
	b.add_child(pr)
	var pl := Label.new()
	pl.text = "印を付けたひな形の中身"
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(pl)
	_tidy_compare = CheckBox.new()
	_tidy_compare.text = "二つを比べる"
	_tidy_compare.tooltip_text = "印を二つ付けると、二つのひな形の違うところだけを並べます"
	_tidy_compare.toggled.connect(func(_on): _update_tidy_preview())
	pr.add_child(_tidy_compare)
	_tidy_preview = RichTextLabel.new()
	_tidy_preview.bbcode_enabled = true
	_tidy_preview.scroll_active = true
	_tidy_preview.custom_minimum_size = Vector2(440, 120)
	_tidy_preview.meta_underlined = false
	_tidy_preview.meta_clicked.connect(func(m): _on_tidy_preview_meta(String(m)))
	b.add_child(_tidy_preview)
	var r2 := HBoxContainer.new()
	b.add_child(r2)
	_tidy_group = LineEdit.new()
	_tidy_group.text = "使っていない"
	_tidy_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_tidy_group)
	var gb := Button.new()
	gb.text = "この組に寄せる"
	gb.pressed.connect(func(): tidy_to_group())
	r2.add_child(gb)
	var db := Button.new()
	db.text = "消す…"
	db.pressed.connect(func():
		var n := tidy_selection().size()
		if n > 0:
			_tidy_confirm.dialog_text = "印を付けたひな形 %d 個を消します（元に戻せます）" % n
			_tidy_confirm.popup_centered())
	r2.add_child(db)
	_tidy_confirm = ConfirmationDialog.new()
	_tidy_confirm.ok_button_text = "消す"
	_tidy_confirm.cancel_button_text = "やめる"
	_tidy_confirm.confirmed.connect(func(): tidy_delete())
	add_child(_tidy_confirm)
	add_child(_tidy_dialog)


## ひな形を最後に使った時刻（Unix 秒。使っていなければ 0）。パソコンごと。
static func preset_last_used(name: String) -> float:
	var lu = _run_ui().get("last_used", {})
	return float(lu.get(name, 0)) if lu is Dictionary else 0.0


## place は「会話 talk の 3 番目」など（シーンの途中から始めたとき）。scene は run_from の頼みのシーン。
## req は run_from の頼み（ひな形の名前と値を除く）。「そこから動かす」で使う。
static func _mark_preset_used(name: String, when: float = -1.0, place: String = "", scene: String = "", req: Dictionary = {}) -> void:
	var d := _run_ui()
	var lu = d.get("last_used", {})
	if not lu is Dictionary:
		lu = {}
	lu[name] = Time.get_unix_time_from_system() if when < 0.0 else when
	d["last_used"] = lu
	if scene != "" or place != "":
		var lw = d.get("last_where", {})
		if not lw is Dictionary:
			lw = {}
		lw[name] = {"scene": scene, "place": place}
		if not req.is_empty():
			lw[name]["req"] = req.duplicate(true)
		d["last_where"] = lw
	_save_run_ui(d)


## 最後に使ったときの場所：「hall」「hall ／ 会話 talk の 3 番目」。わからなければ ""。
static func preset_last_where(name: String) -> String:
	var lw = _run_ui().get("last_where", {})
	var w = lw.get(name) if lw is Dictionary else null
	if not w is Dictionary:
		return ""
	var s := String(w.get("scene", ""))
	var p := String(w.get("place", ""))
	return s + (" ／ " + p if p != "" else "")


## 最後に使ったときの頼み（{scene, dialogue?, path?, line?, knot?, pre_sets?}）。場所しか残っていなければ {scene}。なければ {}。
static func preset_last_request(name: String) -> Dictionary:
	var lw = _run_ui().get("last_where", {})
	var w = lw.get(name) if lw is Dictionary else null
	if not w is Dictionary or String(w.get("scene", "")) == "":
		return {}
	var req: Dictionary = w["req"].duplicate(true) if w.get("req") is Dictionary else {}
	req["scene"] = String(w["scene"])
	if req.get("path") is Array:
		req["path"] = (req["path"] as Array).map(func(x): return int(x))
	if req.has("line"):
		req["line"] = int(req["line"])
	return req


## ひな形を最後に使った場所から、もう一度動かす（保存してある中身で）。
func run_preset_from_last(name: String, play: bool = true) -> bool:
	var req := preset_last_request(name)
	if req.is_empty():
		_set_status("ひな形 %s を使った場所がありません" % name)
		return false
	if not run_presets().has(name):
		_set_status("ひな形がありません：%s" % name)
		return false
	req["preset"] = name
	return run_from(req, play)


## 最後に使った時の短い言い方：「今日」「昨日」「3日前」「5週前」「2か月前」、使っていなければ「未使用」。
static func used_label(t: float, now: float = -1.0) -> String:
	if t <= 0.0:
		return "未使用"
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	var today := floorf((now + _tz_offset()) / 86400.0)
	var day := floorf((t + _tz_offset()) / 86400.0)
	var days := int(today - day)
	if days <= 0:
		return "今日"
	if days == 1:
		return "昨日"
	if days < 14:
		return "%d日前" % days
	if days < 60:
		return "%d週前" % (days / 7)
	return "%dか月前" % (days / 30)


static func _tz_offset() -> float:
	return float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0


## 最後に使った日時（「2026-11-13 10:42」、使っていなければ「未使用」）。
static func used_datetime(t: float) -> String:
	if t <= 0.0:
		return "未使用"
	return Time.get_datetime_string_from_unix_time(int(t + _tz_offset()), true).left(16)


## 組をたたむ・開く（on を省くと入れ替え）。たたんだら true。
func set_group_folded(g: String, on: Variant = null) -> bool:
	var list := folded_groups()
	var fold: bool = (not list.has(g)) if on == null else bool(on)
	list.erase(g)
	if fold:
		list.append(g)
	_save_folded(list)
	_fill_preset_pick()
	return fold


## 「実行：」の右クリックのメニュー（段階54）。
var _preset_ctx: PopupMenu
var preset_ctx_name: String = ""    ## メニューを開いたひな形
enum PresetCtx { RUN_LAST, RUN_HERE, OPEN, DUP, GROUP }
var _move_group_dialog: ConfirmationDialog   ## 組を変える…（段階55）
var _move_group_pick: OptionButton
var _move_group_new: LineEdit
var move_group_name: String = ""            ## 組を変えるひな形


## 右クリックのメニューの中身 [[id, 文字, 押せるか]]。
func preset_context_items(name: String) -> Array:
	var w := preset_last_where(name)
	var here := scene_id if page >= Page.SCENE else ""   # シーン（とその中）を開いているときだけ
	return [
		[PresetCtx.RUN_LAST, "▶ そこから動かす（%s）" % w if w != "" else "▶ そこから動かす（まだ使っていません）", w != ""],
		[PresetCtx.RUN_HERE, "▶ いまのシーンから実行（%s）" % here if here != "" else "▶ いまのシーンから実行（シーンを開いていません）", here != ""],
		[PresetCtx.OPEN, "ひな形を開く…", true],
		[PresetCtx.DUP, "複製", true],
		[PresetCtx.GROUP, "組を変える…（いまは %s）" % (preset_group(run_presets()[name]) if preset_group(run_presets().get(name, {})) != "" else "組なし"), true],
	]


## name のひな形の右クリックのメニューを開く（"" や ないひな形なら開かない）。開いたら true。
func open_preset_context(name: String, at: Vector2 = Vector2(-1, -1)) -> bool:
	if name == "" or not run_presets().has(name) or _preset_ctx == null:
		return false
	preset_ctx_name = name
	_preset_ctx.clear()
	for it in preset_context_items(name):
		_preset_ctx.add_item(it[1], it[0])
		_preset_ctx.set_item_disabled(_preset_ctx.item_count - 1, not it[2])
	if is_inside_tree() and at.x >= 0:
		_preset_ctx.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	return true


func preset_context_pressed(id: int, play: bool = true) -> bool:
	var n := preset_ctx_name
	match id:
		PresetCtx.RUN_LAST:
			return run_preset_from_last(n, play)
		PresetCtx.RUN_HERE:
			return run_from({"scene": scene_id, "preset": n}, play)
		PresetCtx.OPEN:
			open_preset_dialog(n)
			return true
		PresetCtx.DUP:
			return duplicate_run_preset(n) != ""
		PresetCtx.GROUP:
			return open_move_group_dialog(n)
	return false


## 「組を変える…」の窓：組なし・いまある組・新しい組（欄に書く）から選ぶ。
func open_move_group_dialog(name: String) -> bool:
	if not run_presets().has(name):
		return false
	if _move_group_dialog == null:
		_move_group_dialog = ConfirmationDialog.new()
		_add_keys(_move_group_dialog, func(e): return _ok_key(_move_group_dialog, e))
		_move_group_dialog.ok_button_text = "移す"
		_move_group_dialog.cancel_button_text = "やめる"
		var b := VBoxContainer.new()
		_move_group_dialog.add_child(b)
		_move_group_pick = OptionButton.new()
		_move_group_pick.item_selected.connect(func(_i): select_move_group(String(_move_group_pick.get_item_metadata(_move_group_pick.selected))))
		b.add_child(_move_group_pick)
		_move_group_new = LineEdit.new()
		_move_group_new.placeholder_text = "新しい組の名前"
		b.add_child(_move_group_new)
		_move_group_dialog.confirmed.connect(func(): set_preset_group(move_group_name, move_group_choice()))
		add_child(_move_group_dialog)
	move_group_name = name
	var now := preset_group(run_presets()[name])
	_move_group_dialog.title = "組を変える：%s" % name
	_move_group_pick.clear()
	_move_group_pick.add_item("（組なし）")
	_move_group_pick.set_item_metadata(0, "")
	for g in run_preset_groups():
		_move_group_pick.add_item("組：%s" % g)
		_move_group_pick.set_item_metadata(_move_group_pick.item_count - 1, String(g))
	_move_group_pick.add_item("新しい組…")
	_move_group_pick.set_item_metadata(_move_group_pick.item_count - 1, "#new")
	select_move_group(now)
	_move_group_new.text = ""
	if is_inside_tree():
		_move_group_dialog.popup_centered(Vector2i(360, 120))
	return true


## 窓で g を選ぶ（"" は組なし、"#new" は新しい組）。
func select_move_group(g: String) -> void:
	for i in _move_group_pick.item_count:
		if String(_move_group_pick.get_item_metadata(i)) == g:
			_move_group_pick.select(i)
	_move_group_new.editable = g == "#new"
	_move_group_new.visible = g == "#new"


## 窓で選んでいる組（新しい組なら欄の名前）。
func move_group_choice() -> String:
	var m := String(_move_group_pick.get_item_metadata(_move_group_pick.selected))
	return _move_group_new.text.strip_edges() if m == "#new" else m


## ひな形 name を組 g に移す（"" で組なし）。元に戻せる。変えたら true。
func set_preset_group(name: String, g: String) -> bool:
	g = g.strip_edges()
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary or not d["run_presets"].get(name) is Dictionary:
		return false
	var v: Dictionary = d["run_presets"][name]
	if preset_group(v) == g:
		_set_status("組はそのままです：%s" % (g if g != "" else "組なし"))
		return false
	if g == "":
		v.erase("group")
	else:
		v["group"] = g
	p["debug"] = d
	model.begin("組を変える：%s → %s" % [name, g if g != "" else "組なし"])
	model.write_json(model.project_path, p)
	model.end()
	_fill_preset_pick()
	_set_status("%s を %s に移しました" % [name, "組 " + g if g != "" else "組なし"])
	return true


func _on_preset_picked(i: int) -> void:
	var m := String(run_preset_pick.get_item_metadata(i))
	if m.begins_with("#group:"):
		set_group_folded(m.substr(7))   # 見出しは開く・たたむだけ。選んでいたひな形はそのまま
		return
	selected_preset = m


## 組の名前（組なしは入れない。並び順＝preset_group_order()）。
func run_preset_groups() -> Array:
	return preset_group_order()


## 組の並び順：プロジェクト設定 debug.run_group_order に書いた順（いまある組だけ）、書いていない組はそのあとに名前の順。
func preset_group_order() -> Array:
	var have: Array = []
	var ps := run_presets()
	for n in ps:
		var g := preset_group(ps[n])
		if g != "" and not have.has(g):
			have.append(g)
	have.sort()
	var d = model.load_project().get("debug", {})
	var saved = d.get("run_group_order", []) if d is Dictionary else []
	var out: Array = []
	if saved is Array:
		for g in saved:
			if have.has(String(g)) and not out.has(String(g)):
				out.append(String(g))
	for g in have:
		if not out.has(g):
			out.append(g)
	return out


## 組を並びの上（delta < 0）・下（delta > 0）へ動かす。プロジェクト設定に書く（元に戻せる）。動いたら true。
func move_preset_group(g: String, delta: int) -> bool:
	var order := preset_group_order()
	var i := order.find(g)
	var j := i + delta
	if i < 0 or j < 0 or j >= order.size() or delta == 0:
		return false
	order.remove_at(i)
	order.insert(j, g)
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary:
		d = {}
	d["run_group_order"] = order
	p["debug"] = d
	model.begin("組の並びを変える：%s" % g)
	model.write_json(model.project_path, p)
	model.end()
	_fill_preset_pick()
	_update_undo_buttons()
	return true


## 組の中身を決める：names を組 g に入れ、ほかでいま g に入っているものは組から外す。ひとまとまりで書く（元に戻せる）。変えた数。
func apply_group_members(g: String, names: Array) -> int:
	g = g.strip_edges()
	if g == "":
		return 0
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary:
		return 0
	var n := 0
	for k in d["run_presets"]:
		var v = d["run_presets"][k]
		if not v is Dictionary:
			continue
		var want := names.has(String(k))
		var now := preset_group(v)
		if want and now != g:
			v["group"] = g
			n += 1
		elif not want and now == g:
			v.erase("group")
			n += 1
	if n == 0:
		return 0
	p["debug"] = d
	model.begin("組の中身を変える：%s" % g)
	model.write_json(model.project_path, p)
	model.end()
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("組「%s」の中身を変えました（%d）" % [g, n])
	return n


func preset_names_in_group(g: String) -> Array:
	var out: Array = []
	var ps := run_presets()
	for n in ps:
		if preset_group(ps[n]) == g:
			out.append(String(n))
	out.sort()
	return out


## 組の名前を変える（new が "" なら組を外す）。ひとまとまりで書く（元に戻せる）。変えた数。
func rename_preset_group(old: String, new_name: String) -> int:
	new_name = new_name.strip_edges()
	if old == "" or old == new_name:
		return 0
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary:
		return 0
	var n := 0
	for k in d["run_presets"]:
		var v = d["run_presets"][k]
		if preset_group(v) == old:
			if new_name == "":
				v.erase("group")
			else:
				v["group"] = new_name
			n += 1
	if n == 0:
		return 0
	# 並び順の中の名前も変える（組を外すなら並びから外す）
	if d.get("run_group_order") is Array:
		var ord: Array = d["run_group_order"]
		var at := ord.find(old)
		if at >= 0:
			if new_name == "" or ord.has(new_name):
				ord.remove_at(at)
			else:
				ord[at] = new_name
	p["debug"] = d
	model.begin("組の名前を変える：%s → %s" % [old, new_name if new_name != "" else "（組なし）"])
	model.write_json(model.project_path, p)
	model.end()
	if folded_groups().has(old):
		var fl := folded_groups()
		fl.erase(old)
		if new_name != "":
			fl.append(new_name)
		_save_folded(fl)
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("組の名前を変えました：%s → %s（%d）" % [old, new_name if new_name != "" else "（組なし）", n])
	return n


## 組のひな形をまとめて消す。ひとまとまりで書く（元に戻せる）。消した数。
func delete_preset_group(g: String) -> int:
	if g == "":
		return 0
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary or not d.get("run_presets") is Dictionary:
		return 0
	var names: Array = []
	for k in d["run_presets"]:
		if preset_group(d["run_presets"][k]) == g:
			names.append(k)
	if names.is_empty():
		return 0
	for k in names:
		d["run_presets"].erase(k)
	if d["run_presets"].is_empty():
		d.erase("run_presets")
	p["debug"] = d
	model.begin("組を消す：%s" % g)
	model.write_json(model.project_path, p)
	model.end()
	if names.has(selected_preset):
		selected_preset = ""
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("組「%s」のひな形を消しました（%d）" % [g, names.size()])
	return names.size()


var _group_dialog: AcceptDialog
var _group_pick: OptionButton
var _group_new: LineEdit
var _group_info: Label
var _group_delete_confirm: ConfirmationDialog
var _group_member_list: VBoxContainer
var _group_run_pick: OptionButton             ## 組の窓の「このひな形で実行」
var _group_member_checks: Dictionary = {}     ## ひな形の名前 → CheckBox（組の窓の出し入れ）


## 組の窓：組を選んで、名前を変える・書き出す・消す。
func open_group_dialog(g: String = "") -> void:
	_group_pick.clear()
	var gs := run_preset_groups()
	for x in gs:
		_group_pick.add_item(x)
		if x == g:
			_group_pick.select(_group_pick.item_count - 1)
	_update_group_info()
	_group_dialog.popup_centered(Vector2i(480, 460))


## 組の窓の「▶ 実行」：選んだひな形で実行して窓を閉じる。
func run_group_pick(play: bool = true) -> bool:
	if _group_run_pick.selected < 0 or _group_run_pick.item_count == 0:
		return false
	var ok := run_with_preset(String(_group_run_pick.get_item_metadata(_group_run_pick.selected)), play)
	if ok:
		_group_dialog.hide()
	return ok


func picked_group() -> String:
	return _group_pick.get_item_text(_group_pick.selected) if _group_pick.selected >= 0 and _group_pick.item_count > 0 else ""


func _update_group_info() -> void:
	var g := picked_group()
	_group_new.text = g
	_group_info.text = ("ひな形：%s" % "、".join(preset_names_in_group(g))) if g != "" else "（組がありません。ひな形の窓の「組」で付けられます）"
	# 出し入れの一覧：全部のひな形、いまこの組のものに印（ほかの組のものは組の名前を添える）
	for c in _group_member_list.get_children():
		c.queue_free()
	_group_member_checks.clear()
	var ps := run_presets()
	var names: Array = ps.keys()
	names.sort()
	for n in names:
		var cg := preset_group(ps[n])
		var cb := CheckBox.new()
		cb.text = String(n) + ("" if cg == "" or cg == g else "（組：%s）" % cg) + "　〔%s〕" % used_label(preset_last_used(String(n)))
		cb.button_pressed = g != "" and cg == g
		cb.disabled = g == ""
		fit_check(cb, preset_summary(String(n)))
		_group_member_list.add_child(cb)
		_group_member_checks[String(n)] = cb
	# この組のひな形から選んで実行
	_group_run_pick.clear()
	for n in preset_names_in_group(g):
		_group_run_pick.add_item("%s　〔%s〕" % [n, used_label(preset_last_used(n))])
		_group_run_pick.set_item_metadata(_group_run_pick.item_count - 1, n)
		if n == selected_preset:
			_group_run_pick.select(_group_run_pick.item_count - 1)
	_group_run_pick.disabled = _group_run_pick.item_count == 0


## ひな形を選んで、いま開いているシーン（なければチャプターの最初、開始のシーン）から実行する。「実行：」の選びもそのひな形にする。
func run_with_preset(name: String, play: bool = true) -> bool:
	if not run_presets().has(name):
		_set_status("ひな形がありません：%s" % name)
		return false
	select_preset(name)
	return run_from({"scene": run_scene_for_dialogue(), "preset": name}, play)


## 組の窓の出し入れの印（テスト・道具用）。
func set_group_member_check(n: String, on: bool) -> void:
	if _group_member_checks.has(n):
		(_group_member_checks[n] as CheckBox).button_pressed = on


## 組の窓の「この中身にする」：印の付いたひな形をこの組に（ほかの組からも移す）、印を外したものは組から外す。
func confirm_group_members() -> int:
	var g := picked_group()
	var sel: Array = []
	for n in _group_member_checks:
		if (_group_member_checks[n] as CheckBox).button_pressed:
			sel.append(n)
	var c := apply_group_members(g, sel)
	_update_group_info()
	return c


## 組の窓の「書き出す…」：その組のひな形だけを書き出す（ファイルを選ぶ窓を開く）。
func export_group(g: String, path: String = "") -> Error:
	export_names = preset_names_in_group(g)
	if export_names.is_empty():
		return ERR_DOES_NOT_EXIST
	if path != "":
		return export_run_presets(path, export_names)
	_preset_export_dialog.current_file = "%s.json" % g
	_preset_export_dialog.popup_centered(Vector2i(720, 480))
	return OK


func _build_group_dialog() -> void:
	_group_dialog = AcceptDialog.new()
	_group_dialog.title = "ひな形の組"
	_group_dialog.ok_button_text = "閉じる"
	var b := VBoxContainer.new()
	_group_dialog.add_child(b)
	var r := HBoxContainer.new()
	b.add_child(r)
	var l := Label.new()
	l.text = "組"
	r.add_child(l)
	_group_pick = OptionButton.new()
	_group_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_pick.item_selected.connect(func(_i): _update_group_info())
	r.add_child(_group_pick)
	_group_info = Label.new()
	_group_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_group_info.custom_minimum_size = Vector2(420, 0)
	b.add_child(_group_info)
	var r2 := HBoxContainer.new()
	b.add_child(r2)
	_group_new = LineEdit.new()
	_group_new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_new.placeholder_text = "新しい組の名前（空なら組を外す）"
	r2.add_child(_group_new)
	var rn := Button.new()
	rn.text = "名前を変える"
	rn.pressed.connect(func():
		var g := picked_group()
		if g != "":
			rename_preset_group(g, _group_new.text)
			open_group_dialog(_group_new.text.strip_edges()))
	r2.add_child(rn)
	var r3 := HBoxContainer.new()
	b.add_child(r3)
	for spec in [["↑ 上へ", -1], ["↓ 下へ", 1]]:
		var mb := Button.new()
		mb.text = spec[0]
		var dl_: int = spec[1]
		mb.tooltip_text = "「実行：」の一覧での組の並びを変えます"
		mb.pressed.connect(func():
			var g := picked_group()
			if g != "" and move_preset_group(g, dl_):
				open_group_dialog(g))
		r3.add_child(mb)
	var ex := Button.new()
	ex.text = "この組を書き出す…"
	ex.pressed.connect(func():
		if picked_group() != "":
			export_group(picked_group()))
	r3.add_child(ex)
	var dl := Button.new()
	dl.text = "この組を消す…"
	dl.pressed.connect(func():
		var g := picked_group()
		if g != "":
			_group_delete_confirm.dialog_text = "組「%s」のひな形 %d 個を消します（元に戻せます）" % [g, preset_names_in_group(g).size()]
			_group_delete_confirm.popup_centered())
	r3.add_child(dl)
	var ml := Label.new()
	ml.text = "この組に入れるひな形（印を外すと組から外れます。ほかの組のものに印を付けると、この組へ移ります）"
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.custom_minimum_size = Vector2(420, 0)
	b.add_child(ml)
	var msc := ScrollContainer.new()
	msc.custom_minimum_size = Vector2(420, 140)
	msc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fit_list_scroll(msc)
	b.add_child(msc)
	_group_member_list = VBoxContainer.new()
	_group_member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msc.add_child(_group_member_list)
	var ap := Button.new()
	ap.text = "この中身にする"
	ap.pressed.connect(func(): confirm_group_members())
	b.add_child(ap)
	var rr := HBoxContainer.new()
	b.add_child(rr)
	var rl := Label.new()
	rl.text = "この組のひな形で："
	rr.add_child(rl)
	_group_run_pick = OptionButton.new()
	_group_run_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rr.add_child(_group_run_pick)
	var rb := Button.new()
	rb.text = "▶ 実行"
	rb.tooltip_text = "選んだひな形で、いま開いているシーンからゲームを動かします"
	rb.pressed.connect(func(): run_group_pick())
	rr.add_child(rb)
	_group_delete_confirm = ConfirmationDialog.new()
	_group_delete_confirm.ok_button_text = "消す"
	_group_delete_confirm.cancel_button_text = "やめる"
	_group_delete_confirm.confirmed.connect(func():
		delete_preset_group(picked_group())
		open_group_dialog())
	add_child(_group_delete_confirm)
	add_child(_group_dialog)


var run_preset_filter := ""        ## 「実行：」の一覧の絞り込み
var _preset_filter_edit: LineEdit


func set_preset_filter(text: String) -> void:
	run_preset_filter = text
	if _preset_filter_edit != null and _preset_filter_edit.text != text:
		_preset_filter_edit.text = text
	_fill_preset_pick()


func _fill_preset_pick() -> void:
	if run_preset_pick == null:
		return
	var ps := run_presets()
	if not ps.has(selected_preset):
		selected_preset = ""
	run_preset_pick.clear()
	run_preset_pick.add_item("ひな形なし")
	run_preset_pick.set_item_metadata(0, "")
	run_preset_pick.select(0)
	var folded := folded_groups()
	var used := {}
	match run_sort():
		"used":
			var lu = _run_ui().get("last_used", {})
			if lu is Dictionary:
				used = lu
		"created":
			for n in ps:
				used[n] = float(ps[n].get("created", 0)) if ps[n] is Dictionary else 0.0
	for gl in preset_pick_layout(ps, run_preset_filter, selected_preset, preset_group_order(), used):
		var g := String(gl[0])
		var fold := g != "" and folded.has(g)
		if g != "":
			# 組の見出し：選ぶと開く・たたむ（ひな形は選ばない）
			run_preset_pick.add_item(("▸ 組：%s（%d）" % [g, gl[1].size()]) if fold else ("▾ 組：%s" % g))
			run_preset_pick.set_item_metadata(run_preset_pick.item_count - 1, "#group:" + g)
		for n in gl[1]:
			if fold and String(n) != selected_preset:
				continue   # たたんだ組は、選んでいるものだけ出す
			var lu := preset_last_used(String(n))
			run_preset_pick.add_item(("　" if g != "" else "") + String(n) + "　〔%s〕" % used_label(lu))
			run_preset_pick.set_item_metadata(run_preset_pick.item_count - 1, String(n))
			run_preset_pick.set_item_tooltip(run_preset_pick.item_count - 1, "最後に使った日時：%s\n作った日時：%s" % [used_datetime(lu), used_datetime(float(ps[n].get("created", 0)) if ps[n] is Dictionary else 0.0).replace("未使用", "不明")])
			if String(n) == selected_preset:
				run_preset_pick.select(run_preset_pick.item_count - 1)


## 「名前 = 値」の行を辞書に（値は JSON として読めればその値、読めなければ文字列。# から後ろと空の行は飛ばす）。
static func parse_assign_lines(text: String) -> Dictionary:
	var out := {}
	for raw in text.split("\n"):
		var s := String(raw).strip_edges()
		if s == "" or s.begins_with("#"):
			continue
		var at := s.find("=")
		if at <= 0:
			continue
		var k := s.substr(0, at).strip_edges()
		var vs := s.substr(at + 1).strip_edges()
		var j := JSON.new()
		out[k] = j.data if vs != "" and j.parse(vs) == OK else vs
	return out


static func assign_lines_text(d: Dictionary) -> String:
	var lines: Array = []
	for k in d:
		lines.append("%s = %s" % [k, JSON.stringify(d[k])])
	return "\n".join(lines)


## ひな形を書く窓を開く（pname が "" なら新しく）。
func open_preset_dialog(pname: String = "") -> void:
	var ps: Dictionary = run_presets()
	var v: Dictionary = ps.get(pname, {}) if ps.get(pname) is Dictionary else {}
	_preset_name.text = pname
	_preset_group.text = preset_group(v)
	_preset_dates.text = preset_dates_text(pname)
	_preset_run_last.disabled = preset_last_request(pname).is_empty()
	preset_edit_undo = {}
	_update_preset_undo_btn()
	_start_vals = start_values()
	_preset_vars.text = assign_lines_text(v.get("vars", {}) if v.get("vars") is Dictionary else {})
	_preset_items.text = assign_lines_text(v.get("items", {}) if v.get("items") is Dictionary else {})
	_preset_msg.text = ""
	_fill_preset_cmp(pname)
	_preset_dialog.popup_centered(Vector2i(600, 600))


const PRESET_FILE_FORMAT := "adv80s_run_presets"


## 書き出すひな形を選ぶ窓を開く（初めは全部に印）。
func open_export_pick() -> void:
	for c in _export_list.get_children():
		c.queue_free()
	_export_checks.clear()
	var names: Array = run_presets().keys()
	names.sort()
	for n in names:
		var cb := CheckBox.new()
		cb.text = String(n)
		cb.button_pressed = true
		fit_check(cb, preset_summary(String(n)))
		_export_list.add_child(cb)
		_export_checks[String(n)] = cb
	if names.is_empty():
		var l := Label.new()
		l.text = "（ひな形がありません）"
		_export_list.add_child(l)
	_preset_export_pick.popup_centered(Vector2i(400, 340))


func set_export_all(on: bool) -> void:
	for n in _export_checks:
		(_export_checks[n] as CheckBox).button_pressed = on


func set_export_check(n: String, on: bool) -> void:
	if _export_checks.has(n):
		(_export_checks[n] as CheckBox).button_pressed = on


## 選んだものを export_names に（全部なら []）。一つも選んでいなければ false。
func confirm_export_pick() -> bool:
	var sel: Array = []
	for n in _export_checks:
		if (_export_checks[n] as CheckBox).button_pressed:
			sel.append(n)
	if sel.is_empty():
		_preset_msg.text = "書き出すひな形を選んでください"
		return false
	export_names = [] if sel.size() == _export_checks.size() else sel
	return true


## ひな形をファイルに書き出す（names を省くと全部）。{format, version, presets: {名前: {vars, items}}}。
func export_run_presets(path: String, names: Array = []) -> Error:
	var ps := run_presets()
	var out := {}
	for n in ps:
		if names.is_empty() or names.has(n):
			out[n] = ps[n]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var go: Array = []   # 書き出すひな形の組の並び（読み込む側で、新しい組をこの順に足す）
	for g in preset_group_order():
		for n in out:
			if preset_group(out[n]) == g:
				go.append(g)
				break
	var body := {"format": PRESET_FILE_FORMAT, "version": 1, "presets": out}
	if not go.is_empty():
		body["group_order"] = go
	f.store_string(JSON.stringify(body, "\t"))
	f.close()
	_set_status("ひな形を書き出しました（%d）：%s" % [out.size(), path])
	return OK


## ひな形のファイル（書き出したもの、またはひな形の辞書だけの JSON）を読む。名前 → {vars, items}（持ち物の個数は整数）。
## 読めなければ null。名前が空のもの・中身が辞書でないものは飛ばす。
static func read_preset_file(path: String) -> Variant:
	var d = AdvJson.load_file(path, []) if FileAccess.file_exists(path) else null
	if d is Dictionary and d.has("presets"):
		d = d["presets"]
	if not d is Dictionary:
		return null
	var out := {}
	for n in d:
		var src = d[n]
		var name := String(n).strip_edges()
		if not src is Dictionary or name == "":
			continue
		var v := {}
		if src.get("vars") is Dictionary and not src["vars"].is_empty():
			v["vars"] = src["vars"]
		if src.get("items") is Dictionary and not src["items"].is_empty():
			var its := {}
			for k in src["items"]:
				its[k] = int(src["items"][k])
			v["items"] = its
		if preset_group(src) != "":
			v["group"] = preset_group(src)
		if float(src.get("created", 0)) > 0.0:
			v["created"] = float(src["created"])
		out[name] = v
	return out


## ひな形のファイルの組の並び（段階57から書き出す。なければ []）。
static func read_preset_file_group_order(path: String) -> Array:
	var d = AdvJson.load_file(path, []) if FileAccess.file_exists(path) else null
	var out: Array = []
	if d is Dictionary and d.get("group_order") is Array:
		for g in d["group_order"]:
			var s := String(g).strip_edges()
			if s != "" and not out.has(s):
				out.append(s)
	return out


## 読み込むとどうなるか："new"（新しく足す）・"same"（同じものがある。飛ばす）・"rename"（中身が違う。「（読み込み）」で足す）・
## "overwrite"（overwrite のとき、中身が違うものをその名前で上書きする）。
## 足すときは、前に読み込んだ「（読み込み）」の名前に同じ中身があっても "same"。上書きのときは、その名前の中身だけと比べる。
static func import_status(ps: Dictionary, name: String, v: Dictionary, overwrite: bool = false) -> String:
	if not ps.has(name):
		return "new"
	if overwrite:
		return "same" if diff_presets(ps[name] if ps[name] is Dictionary else {}, v).is_empty() else "overwrite"
	var n := name
	var i := 1
	while ps.has(n):
		if diff_presets(ps[n] if ps[n] is Dictionary else {}, v).is_empty():
			return "same"
		n = "%s（読み込み）" % name if i == 1 else "%s（読み込み %d）" % [name, i]
		i += 1
	return "rename"


## 中身が違うときに付ける名前：「名前（読み込み）」「名前（読み込み 2）」…のうち、まだないもの。
static func import_rename_target(ps: Dictionary, base: String) -> String:
	var name := "%s（読み込み）" % base
	var i := 2
	while ps.has(name):
		name = "%s（読み込み %d）" % [base, i]
		i += 1
	return name


## 書き出したファイル（またはひな形の辞書だけの JSON）を読み込む（names を省くと全部）。同じものは飛ばし、
## 中身が違えば「名前（読み込み）」「名前（読み込み 2）」…で足す。ひとまとまりで書く（元に戻せる）。足した名前を返す。
## group_to が null ならファイルの組のまま、"" なら組なし、ほかはその組へ入れる。
func import_run_presets(path: String, names: Array = [], overwrite: bool = false, group_to: Variant = null) -> Array:
	var d = read_preset_file(path)
	if d == null:
		_set_status("ひな形のファイルとして読めません：%s" % path)
		return []
	var p := model.load_project()
	var dbg = p.get("debug", {})
	if not dbg is Dictionary:
		dbg = {}
	var ps = dbg.get("run_presets", {})
	if not ps is Dictionary:
		ps = {}
	var added: Array = []
	var had_groups: Array = []
	for n in ps:
		if ps[n] is Dictionary and not had_groups.has(preset_group(ps[n])):
			had_groups.append(preset_group(ps[n]))
	for base in d:
		if not names.is_empty() and not names.has(base):
			continue
		var v: Dictionary = d[base]
		if group_to != null:
			if String(group_to).strip_edges() == "":
				v.erase("group")
			else:
				v["group"] = String(group_to).strip_edges()
		if not v.has("created"):
			v["created"] = Time.get_unix_time_from_system()
		match import_status(ps, base, v, overwrite):
			"same":
				continue
			"new", "overwrite":
				ps[base] = v
				added.append(base)
			"rename":
				var name := import_rename_target(ps, base)
				ps[name] = v
				added.append(name)
	if added.is_empty():
		return []
	var new_groups: Array = []   # このプロジェクトになかった組を、ファイルの並びの順に並びの終わりへ足す
	var file_order: Array = read_preset_file_group_order(path) if group_to == null else [String(group_to).strip_edges()]
	for g in file_order:
		if g == "" or had_groups.has(g):
			continue
		for n in added:
			if preset_group(ps[n]) == g:
				new_groups.append(g)
				break
	if not new_groups.is_empty():
		var ord := preset_group_order()
		for g in new_groups:
			if not ord.has(g):
				ord.append(g)
		dbg["run_group_order"] = ord
	dbg["run_presets"] = ps
	p["debug"] = dbg
	model.begin("ひな形を読み込む：%s" % "、".join(added))
	model.write_json(model.project_path, p)
	model.end()
	_fill_preset_pick()
	_update_undo_buttons()
	_set_status("ひな形を読み込みました：%s" % "、".join(added))
	return added


var _preset_import_pick: ConfirmationDialog   ## 読み込むひな形を選ぶ窓
var _import_checks: Dictionary = {}           ## 名前 → CheckBox
var _import_list: VBoxContainer
var _import_path := ""
var _import_data: Dictionary = {}
var import_overwrite := false                 ## 中身が違うものを上書きする（読み込む窓の印）
var _import_overwrite_check: CheckBox
var _import_preview: RichTextLabel             ## 上書きされるひな形の、いまの中身との違い


## ファイルの中のひな形を並べて、読み込むものを選ぶ窓を開く（同じものがあるものは印なしで押せない）。読めなければ false。
func open_import_pick(path: String) -> bool:
	var d = read_preset_file(path)
	if d == null:
		_preset_msg.text = "ひな形のファイルとして読めません：%s" % path
		return false
	_import_path = path
	_import_data = d
	for c in _import_list.get_children():
		c.queue_free()
	_import_checks.clear()
	_fill_import_group_pick()
	var names: Array = d.keys()
	names.sort()
	for n in names:
		var cb := CheckBox.new()
		cb.toggled.connect(func(_on): _update_import_preview())
		_import_list.add_child(cb)
		_import_checks[String(n)] = cb
	_refresh_import_pick(true)
	if names.is_empty():
		var l := Label.new()
		l.text = "（ひな形がありません）"
		_import_list.add_child(l)
	_preset_import_pick.popup_centered(Vector2i(520, 340))
	return true


## 上書きするかを変える（窓の名前の横の説明と、押せるかを付け直す）。
func set_import_overwrite(on: bool) -> void:
	import_overwrite = on
	if _import_overwrite_check != null and _import_overwrite_check.button_pressed != on:
		_import_overwrite_check.set_pressed_no_signal(on)
	_refresh_import_pick(false)


## 読み込む窓の組の説明：「　［組：G］」（このプロジェクトにない組なら「（新しい組）」）。組なしなら ""。
static func import_group_text(ps: Dictionary, v: Dictionary) -> String:
	var g := preset_group(v)
	if g == "":
		return ""
	for n in ps:
		if ps[n] is Dictionary and preset_group(ps[n]) == g:
			return "　［組：%s］" % g
	return "　［組：%s（新しい組）］" % g


## 読み込む窓のそれぞれの説明を付け直す。reset なら印も初めの形に（同じもの以外に印）。押せなかったものが押せるようになったら印を付ける。
func _refresh_import_pick(reset: bool) -> void:
	var ps := run_presets()
	for n in _import_checks:
		var cb := _import_checks[n] as CheckBox
		var st := import_status(ps, n, _import_data.get(n, {}), import_overwrite)
		var tail := "（新しい）"
		match st:
			"same":
				tail = "（同じものがあります）"
			"rename":
				tail = "（中身が違う：「%s」で足す）" % import_rename_target(ps, n)
			"overwrite":
				tail = "（中身が違う：上書きする）"
		cb.text = String(n) + import_group_text(ps, _import_with_group(_import_data.get(n, {}))) + tail
		fit_check(cb, import_row_tip(String(n)))
		var was_disabled := cb.disabled
		cb.disabled = st == "same"
		if reset or (was_disabled and not cb.disabled):
			cb.set_pressed_no_signal(st != "same")
		elif cb.disabled:
			cb.set_pressed_no_signal(false)
	_update_import_preview()


## 上書きされるもの（印あり・上書き）の、いまの中身 → ファイルの中身の違い（BBCode）。上書きがなければ ""。
func import_overwrite_preview() -> String:
	if not import_overwrite:
		return ""
	var ps := run_presets()
	var lines: Array = []
	var names: Array = _import_checks.keys()
	names.sort()
	for n in names:
		var cb := _import_checks[n] as CheckBox
		if cb.disabled or not cb.button_pressed or import_status(ps, n, _import_data.get(n, {}), true) != "overwrite":
			continue
		lines.append("[b]%s[/b] を上書き（いま → 読み込み）" % n)
		for e in diff_presets(ps[n] if ps[n] is Dictionary else {}, _import_data.get(n, {})):
			lines.append("　%s %s：%s → %s" % ["変数" if e["kind"] == "vars" else "持ち物", e["key"],
				"なし" if e["a"] == null else AdvPlayer.value_text(e["a"]), "なし" if e["b"] == null else AdvPlayer.value_text(e["b"])])
	return "\n".join(lines)


func _update_import_preview() -> void:
	if _import_preview != null:
		_import_preview.text = import_overwrite_preview()
		_import_preview.visible = _import_preview.text != ""


func set_import_all(on: bool) -> void:
	for n in _import_checks:
		var cb := _import_checks[n] as CheckBox
		if not cb.disabled:
			cb.button_pressed = on


func set_import_check(n: String, on: bool) -> void:
	if _import_checks.has(n) and not (_import_checks[n] as CheckBox).disabled:
		(_import_checks[n] as CheckBox).button_pressed = on


var _import_group_pick: OptionButton   ## 読み込む組（段階59）：メタデータ "#file" はファイルのまま、"" は組なし、"#new" は新しい組
var _import_group_new: LineEdit


## 読み込む窓で選んでいる組：null（ファイルのまま）・""（組なし）・組の名前（新しい組なら欄の名前。空なら null）。
func import_group_choice() -> Variant:
	if _import_group_pick == null or _import_group_pick.selected < 0:
		return null
	var m := String(_import_group_pick.get_item_metadata(_import_group_pick.selected))
	if m == "#file":
		return null
	if m == "#new":
		var s := _import_group_new.text.strip_edges()
		return s if s != "" else null
	return m


## 読み込む組を選ぶ（"#file"・""・組の名前・"#new"）。一覧の説明も付け直す。
func set_import_group(m: String) -> void:
	for i in _import_group_pick.item_count:
		if String(_import_group_pick.get_item_metadata(i)) == m:
			_import_group_pick.select(i)
	_import_group_new.editable = m == "#new"
	_import_group_new.visible = m == "#new"
	_refresh_import_pick(false)


func _fill_import_group_pick() -> void:
	_import_group_pick.clear()
	_import_group_pick.add_item("ファイルの組のまま")
	_import_group_pick.set_item_metadata(0, "#file")
	_import_group_pick.add_item("（組なし）")
	_import_group_pick.set_item_metadata(1, "")
	for g in preset_group_order():
		_import_group_pick.add_item("組：%s" % g)
		_import_group_pick.set_item_metadata(_import_group_pick.item_count - 1, String(g))
	_import_group_pick.add_item("新しい組…")
	_import_group_pick.set_item_metadata(_import_group_pick.item_count - 1, "#new")
	_import_group_pick.select(0)
	_import_group_new.text = ""
	_import_group_new.editable = false
	_import_group_new.visible = false
	# 前に読み込んだときの組（パソコンごと）。その組がもうなければ「新しい組」にその名前を入れる
	var last = _run_ui().get("import_group")
	if last is String:
		var found := false
		for i in _import_group_pick.item_count:
			var m := String(_import_group_pick.get_item_metadata(i))
			if m == last and m != "#new":
				_import_group_pick.select(i)
				found = true
		if not found and last != "":
			_import_group_pick.select(_import_group_pick.item_count - 1)
			_import_group_new.text = last
			_import_group_new.editable = true
			_import_group_new.visible = true


## 読み込んだときの組を覚える（null は "#file"）。
static func _remember_import_group(g: Variant) -> void:
	var d := _run_ui()
	d["import_group"] = "#file" if g == null else String(g)
	_save_run_ui(d)


## 読み込む窓の行の説明：ファイルの中身と、同じ名前がこのプロジェクトにあればいまの中身（段階61）。
func import_row_tip(n: String) -> String:
	var t := "ファイル：" + preset_value_summary(_import_data.get(n, {}))
	if run_presets().has(n):
		t += "\nいま　　：" + preset_summary(n)
	return t


## 読み込む組を当てた中身（一覧の説明に使う）。
func _import_with_group(v: Dictionary) -> Dictionary:
	var g = import_group_choice()
	if g == null:
		return v
	var w := v.duplicate()
	if String(g) == "":
		w.erase("group")
	else:
		w["group"] = String(g)
	return w


## 印を付けたものを読み込む。足した名前を返す（一つも選んでいなければ []）。
func confirm_import_pick() -> Array:
	var sel: Array = []
	for n in _import_checks:
		var cb := _import_checks[n] as CheckBox
		if cb.button_pressed and not cb.disabled:
			sel.append(n)
	if sel.is_empty():
		_preset_msg.text = "読み込むひな形を選んでください"
		return []
	var got := import_run_presets(_import_path, sel, import_overwrite, import_group_choice())
	if not got.is_empty():
		_remember_import_group(import_group_choice())
	_preset_msg.text = ("読み込みました：%s" % "、".join(got)) if not got.is_empty() else "読み込めるひな形がありません"
	_fill_preset_cmp(_preset_name.text.strip_edges())
	return got


# ---------------------------------------------------------------- 取っておいたお知らせの見た目（段階52）

var _style_dialog: AcceptDialog
var _style_kind: OptionButton        ## 0：ふつうのお知らせ、1：デバッグのお知らせ
var _style_pick: OptionButton
var _style_show: RichTextLabel
var _style_msg: Label
var _style_rename: LineEdit           ## 新しい名前（段階53）
var _style_cmp: OptionButton          ## 比べる相手（段階55）
var style_cmp_name: String = ""       ## 比べている見た目（"" は比べない）
var _style_last_pick: String = ""     ## 前に選んでいた見た目（比べている方を選んだら入れかえる）
var _style_restore: Button            ## 一つ戻す（最後に消した・写した見た目を戻す）
var style_last_erased: Dictionary = {}   ## 最後に消した見た目 {game, name, values}（戻すため）


## 取っておいた見た目の窓を開く（ゲームのコンソールの noticestyle [game] keep で取っておいたもの）。
func open_style_sets_dialog(game: bool = true) -> void:
	_style_kind.select(0 if game else 1)
	_fill_style_pick()
	_style_msg.text = ""
	_style_dialog.popup_centered(Vector2i(620, 360))


func style_kind_is_game() -> bool:
	return _style_kind.selected == 0


func _fill_style_pick() -> void:
	_style_pick.clear()
	var sets := AdvPlayer.notice_style_sets(style_kind_is_game())
	var names: Array = sets.keys()
	names.sort()
	for n in names:
		_style_pick.add_item(String(n))
	_style_pick.disabled = names.is_empty()
	_update_style_show()


func select_style_set(name: String) -> void:
	for i in _style_pick.item_count:
		if _style_pick.get_item_text(i) == name:
			_style_pick.select(i)
	_update_style_show()


func _style_picked() -> String:
	return _style_pick.get_item_text(_style_pick.selected) if _style_pick.item_count > 0 and _style_pick.selected >= 0 else ""


## 取っておいた見た目の名前を変える。できれば ""、できなければ理由（窓にも出す）。
func rename_style_set(game: bool, old: String, new_name: String) -> String:
	var why := AdvPlayer.rename_notice_style_set(game, old, new_name)
	if why == "":
		if style_last_erased.get("game") == game and String(style_last_erased.get("name", "")) == new_name.strip_edges():
			style_last_erased = {}   # 同じ名前を使ったので、戻すと上書きになる
		elif style_last_erased.get("game") == game and style_last_erased.get("kind") == "copy" and String(style_last_erased.get("name", "")) == old:
			style_last_erased["name"] = new_name.strip_edges()   # 写したものは新しい名前で戻す
		_after_style_change(game, new_name.strip_edges(), "名前を変えました：%s → %s" % [old, new_name.strip_edges()])
	elif _style_msg != null:
		_style_msg.text = why
	return why


## 取っておいた見た目を消す（「一つ戻す」で一つだけ戻せる）。
func erase_style_set(game: bool, name: String) -> bool:
	var sets := AdvPlayer.notice_style_sets(game)
	if not sets.get(name) is Dictionary or not AdvPlayer.erase_notice_style_set(game, name):
		return false
	style_last_erased = {"kind": "erase", "game": game, "name": name, "values": (sets[name] as Dictionary).duplicate(true)}
	_after_style_change(game, "", "消しました：%s（「一つ戻す」で戻せます）" % name)
	return true


## プロジェクト設定のいまの見た目を name で取っておく。取っておいた名前（同じ名前があれば「名前 2」…。空なら「いまの設定」）。できなければ ""。
func keep_project_style(game: bool, name: String) -> String:
	var p := model.load_project()
	var now = p.get("notice_style", {}) if game else (p.get("debug", {}).get("notice_style", {}) if p.get("debug") is Dictionary else {})
	if not now is Dictionary or now.is_empty():
		var why := "プロジェクト設定（%s）に見た目が書いてありません" % ("notice_style" if game else "debug.notice_style")
		if _style_msg != null:
			_style_msg.text = why
		_set_status(why)
		return ""
	var base := name.strip_edges() if name.strip_edges() != "" else "いまの設定"
	var sets := AdvPlayer.notice_style_sets(game)
	var n := base
	var i := 2
	while sets.has(n):
		n = "%s %d" % [base, i]
		i += 1
	if not AdvPlayer.put_notice_style_set(game, n, now):
		return ""
	_after_style_change(game, n, "取っておきました：%s（%d）" % [n, now.size()])
	return n


## 最後に消した見た目を戻す。戻した名前（同じ名前がもうあれば「（戻す）」を付ける。なければ ""）。
func restore_erased_style_set() -> String:
	if style_last_erased.is_empty():
		return ""
	var game: bool = style_last_erased["game"]
	var n := String(style_last_erased["name"])
	var sets := AdvPlayer.notice_style_sets(game)
	var copied := String(style_last_erased.get("kind", "erase")) == "copy"
	if not copied:   # 消したもの：同じ名前がもうあれば「（戻す）」を付ける。写したもの：同じ名前に書き戻す
		while sets.has(n):
			n += "（戻す）"
	if not AdvPlayer.put_notice_style_set(game, n, style_last_erased["values"]):
		return ""
	var what := "写す前に戻しました：%s" % n if copied else "戻しました：%s" % n
	style_last_erased = {}
	_after_style_change(game, n, what)
	return n


func _after_style_change(game: bool, pick: String, msg: String) -> void:
	_set_status("お知らせの見た目：" + msg)
	if _style_dialog == null:
		return
	if style_kind_is_game() == game:
		_fill_style_pick()
		if pick != "":
			select_style_set(pick)
	_style_msg.text = msg
	_update_style_buttons()


func _update_style_buttons() -> void:
	if _style_restore != null:
		_style_restore.disabled = style_last_erased.is_empty()
		if style_last_erased.is_empty():
			_style_restore.tooltip_text = "戻せるものはありません（消す・写すをすると、最後の一つを戻せます）"
		elif String(style_last_erased.get("kind", "erase")) == "copy":
			_style_restore.tooltip_text = "%s を、%s を写す前に戻します（Ctrl+Z）" % [style_last_erased["name"], style_last_erased.get("key", "")]
		else:
			_style_restore.tooltip_text = "最後に消した見た目（%s）を戻します（Ctrl+Z）" % style_last_erased["name"]


func _update_style_show() -> void:
	if _style_msg != null:
		_style_msg.text = ""   # 選び直したら前の知らせは消す（書く・消すなどは、このあとで知らせを出す）
	var game := style_kind_is_game()
	var sets := AdvPlayer.notice_style_sets(game)
	var n := _style_picked()
	if _style_rename != null:
		_style_rename.text = n
	if n != "" and n == style_cmp_name:
		style_cmp_name = _style_last_pick   # 比べている方を選んだら、二つを入れかえる
	_style_last_pick = n
	if _style_cmp != null:
		_style_cmp.clear()
		_style_cmp.add_item("比べない")
		_style_cmp.set_item_metadata(0, "")
		var others: Array = sets.keys()
		others.sort()
		for o in others:
			if String(o) != n:
				_style_cmp.add_item(String(o))
				_style_cmp.set_item_metadata(_style_cmp.item_count - 1, String(o))
				if String(o) == style_cmp_name:
					_style_cmp.select(_style_cmp.item_count - 1)
		if _style_cmp.selected <= 0:
			style_cmp_name = ""
		_style_cmp.disabled = _style_cmp.item_count < 2
	if n != "" and style_cmp_name != "" and sets.get(style_cmp_name) is Dictionary:
		_style_show.text = style_diff_text(n, sets[n], style_cmp_name, sets[style_cmp_name], true)
		return
	if n == "":
		_style_show.text = "（取っておいた見た目がありません。ゲームのデバッグコンソールで noticestyle %skeep 名前 と打つと取っておけます）" % ("game " if game else "")
		return
	var p := model.load_project()
	var now = p.get("notice_style", {}) if game else (p.get("debug", {}).get("notice_style", {}) if p.get("debug") is Dictionary else {})
	if not now is Dictionary:
		now = {}
	var lines: Array = ["[b]%s[/b]（書く先：%s）" % [n, "notice_style" if game else "debug.notice_style"]]
	for k in sets[n]:
		var v = sets[n][k]
		var cur = now.get(k)
		lines.append("　%s：%s%s" % [k, AdvPlayer.value_text(v), "" if cur != null and AdvPlayer.value_text(cur) == AdvPlayer.value_text(v) else "（いま %s）" % ("なし" if cur == null else AdvPlayer.value_text(cur))])
	_style_show.text = "\n".join(lines)


## 比べる相手を選ぶ（"" で比べない）。
func compare_style_with(other: String) -> void:
	style_cmp_name = other
	_update_style_show()


## 二つの見た目の違うところ（BBCode）。片方にしかないキーは「なし」。
## links なら違う行を押せるようにする（[url=copy:キー]。押すと右の値を左へ写す）。
static func style_diff_text(a_name: String, a: Dictionary, b_name: String, b: Dictionary, links: bool = false) -> String:
	var keys: Array = a.keys()
	for k in b:
		if not keys.has(k):
			keys.append(k)
	var lines: Array = []
	for k in keys:
		var va := AdvPlayer.value_text(a[k]) if a.has(k) else "なし"
		var vb := AdvPlayer.value_text(b[k]) if b.has(k) else "なし"
		if va != vb:
			var line := "%s：%s ／ %s" % [k, va, vb]
			lines.append("　" + ("[url=copy:%s]%s[/url]" % [String(k).uri_encode(), line] if links else line))
	var head := "[b]%s[/b] ／ [b]%s[/b] の違い（%d）" % [a_name, b_name, lines.size()]
	if lines.is_empty():
		return head + "\n　違うところはありません"
	var tail := "\n[color=#9ca3af]行を押すと、%s の値を %s へ写します　[url=copyall]［全部写す］[/url][/color]" % [b_name, a_name] if links else ""
	return head + "\n" + "\n".join(lines) + tail


func _on_style_show_meta(m: String) -> void:
	if m.begins_with("copy:"):
		copy_style_key(m.substr(5).uri_decode())
	elif m == "copyall":
		copy_all_style_keys()


## 「全部写す」：選んでいる見た目を、比べている相手と同じ中身にする（「一つ戻す」で一度に戻せる）。写したキーの数。
func copy_all_style_keys() -> int:
	var game := style_kind_is_game()
	var sets := AdvPlayer.notice_style_sets(game)
	var a_name := _style_picked()
	if a_name == "" or style_cmp_name == "" or not sets.get(a_name) is Dictionary or not sets.get(style_cmp_name) is Dictionary:
		return 0
	var a: Dictionary = sets[a_name]
	var b: Dictionary = sets[style_cmp_name]
	var n := 0
	for k in a:
		if not b.has(k):
			n += 1
	for k in b:
		if not a.has(k) or AdvPlayer.value_text(a[k]) != AdvPlayer.value_text(b[k]):
			n += 1
	if n == 0 or not AdvPlayer.put_notice_style_set(game, a_name, b):
		return 0
	style_last_erased = {"kind": "copy", "game": game, "name": a_name, "values": a.duplicate(true), "key": "全部"}
	_after_style_change(game, a_name, "全部写しました：%s → %s（%d）" % [style_cmp_name, a_name, n])
	return n


## 比べているとき、key の値を右（比べる相手）から左（選んでいる見た目）へ写す。右になければ左から消す。
## 「一つ戻す」で写す前に戻せる。写したら true。
func copy_style_key(key: String) -> bool:
	var game := style_kind_is_game()
	var sets := AdvPlayer.notice_style_sets(game)
	var a_name := _style_picked()
	if a_name == "" or style_cmp_name == "" or not sets.get(a_name) is Dictionary or not sets.get(style_cmp_name) is Dictionary:
		return false
	var a: Dictionary = (sets[a_name] as Dictionary).duplicate(true)
	var b: Dictionary = sets[style_cmp_name]
	var before := a.duplicate(true)
	if b.has(key) and a.has(key) and AdvPlayer.value_text(a[key]) == AdvPlayer.value_text(b[key]):
		return false
	if b.has(key):
		a[key] = b[key]
	elif a.has(key):
		a.erase(key)
	else:
		return false
	if a.is_empty():
		_style_msg.text = "写すと %s が空になるので写しません" % a_name
		return false
	if not AdvPlayer.put_notice_style_set(game, a_name, a):
		return false
	style_last_erased = {"kind": "copy", "game": game, "name": a_name, "values": before, "key": key}
	_after_style_change(game, a_name, "写しました：%s の %s を %s へ（%s）" % [style_cmp_name, key, a_name, AdvPlayer.value_text(b[key]) if b.has(key) else "消す"])
	return true


## 取っておいた見た目 name を、プロジェクト設定（ふつうなら notice_style、デバッグなら debug.notice_style）に書く。
## 書いたキーだけ変える（ほかのキーはそのまま）。元に戻せる。書いたキーの数。
func apply_style_set(game: bool, name: String) -> int:
	var sets := AdvPlayer.notice_style_sets(game)
	if not sets.get(name) is Dictionary or sets[name].is_empty():
		return 0
	var p := model.load_project()
	var target: Dictionary
	if game:
		target = p.get("notice_style", {}) if p.get("notice_style") is Dictionary else {}
	else:
		var d = p.get("debug", {})
		if not d is Dictionary:
			d = {}
		target = d.get("notice_style", {}) if d.get("notice_style") is Dictionary else {}
		p["debug"] = d
	for k in sets[name]:
		var v = sets[name][k]
		target[k] = int(v) if String(k) in ["fg", "bg", "border", "margin", "icon_size", "max"] else v
	if game:
		p["notice_style"] = target
	else:
		p["debug"]["notice_style"] = target
	model.begin("お知らせの見た目「%s」を書く" % name)
	model.write_json(model.project_path, p)
	model.end()
	_update_undo_buttons()
	_set_status("お知らせの見た目「%s」をプロジェクト設定（%s）に書きました" % [name, "notice_style" if game else "debug.notice_style"])
	if _style_dialog != null and _style_dialog.visible:
		_update_style_show()
	return sets[name].size()


func _build_style_sets_dialog() -> void:
	_style_dialog = AcceptDialog.new()
	_add_keys(_style_dialog, _on_style_key)
	_style_dialog.title = "取っておいたお知らせの見た目"
	_style_dialog.ok_button_text = "閉じる"
	var b := VBoxContainer.new()
	_style_dialog.add_child(b)
	var r := HBoxContainer.new()
	b.add_child(r)
	_style_kind = OptionButton.new()
	_style_kind.add_item("ふつうのお知らせ")
	_style_kind.add_item("デバッグのお知らせ")
	_style_kind.item_selected.connect(func(_i): _fill_style_pick())
	r.add_child(_style_kind)
	_style_pick = OptionButton.new()
	_style_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_pick.item_selected.connect(func(_i): _update_style_show())
	r.add_child(_style_pick)
	var cl := Label.new()
	cl.text = "比べる："
	r.add_child(cl)
	_style_cmp = OptionButton.new()
	_style_cmp.tooltip_text = "取っておいたほかの見た目と、違うところだけを並べます"
	_style_cmp.item_selected.connect(func(i): compare_style_with(String(_style_cmp.get_item_metadata(i))))
	r.add_child(_style_cmp)
	_style_show = RichTextLabel.new()
	_style_show.bbcode_enabled = true
	_style_show.scroll_active = true
	_style_show.custom_minimum_size = Vector2(480, 160)
	_style_show.meta_underlined = false
	_style_show.meta_clicked.connect(func(m): _on_style_show_meta(String(m)))
	b.add_child(_style_show)
	var ab := Button.new()
	ab.text = "プロジェクト設定に書く"
	ab.tooltip_text = "選んだ見た目のキーだけを、プロジェクト設定に書きます（元に戻せます）"
	ab.pressed.connect(func():
		if _style_pick.item_count > 0 and _style_pick.selected >= 0:
			var c := apply_style_set(style_kind_is_game(), _style_pick.get_item_text(_style_pick.selected))
			_style_msg.text = "書きました（%d）" % c if c > 0 else "書けるものがありません")
	var ar := HBoxContainer.new()
	b.add_child(ar)
	ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(ab)
	var kb := Button.new()
	kb.text = "いまの設定を取っておく"
	kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kb.tooltip_text = "プロジェクト設定のいまの見た目（ふつうは notice_style、デバッグは debug.notice_style）を、下の名前で取っておきます（同じ名前があれば番号を付けます）"
	kb.pressed.connect(func(): keep_project_style(style_kind_is_game(), _style_rename.text))
	ar.add_child(kb)
	var nr := HBoxContainer.new()
	b.add_child(nr)
	var nl := Label.new()
	nl.text = "名前"
	nr.add_child(nl)
	_style_rename = LineEdit.new()
	_style_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_rename.text_submitted.connect(func(t): rename_style_set(style_kind_is_game(), _style_picked(), t))
	nr.add_child(_style_rename)
	var rb := Button.new()
	rb.text = "名前を変える"
	rb.pressed.connect(func(): rename_style_set(style_kind_is_game(), _style_picked(), _style_rename.text))
	nr.add_child(rb)
	var db := Button.new()
	db.text = "消す"
	db.tooltip_text = "選んだ見た目を消します（「一つ戻す」で一つだけ戻せます）"
	db.pressed.connect(func():
		if _style_picked() != "":
			erase_style_set(style_kind_is_game(), _style_picked()))
	nr.add_child(db)
	_style_restore = Button.new()
	_style_restore.text = "一つ戻す"
	_style_restore.pressed.connect(func(): restore_erased_style_set())
	nr.add_child(_style_restore)
	_style_msg = Label.new()
	b.add_child(_style_msg)
	add_child(_style_dialog)
	_update_style_buttons()


## 「作った日時：2026-11-13 10:42（今日）　最後に使った日時：…（3日前）」。まだないひな形なら「（新しいひな形）」。
func preset_dates_text(name: String) -> String:
	if name == "" or not run_presets().has(name):
		return "（新しいひな形）"
	var c := preset_created(name)
	var u := preset_last_used(name)
	var w := preset_last_where(name)
	return "作った日時：%s　最後に使った日時：%s%s" % [
		"不明" if c <= 0.0 else "%s（%s）" % [used_datetime(c), used_label(c)],
		"未使用" if u <= 0.0 else "%s（%s）" % [used_datetime(u), used_label(u)],
		"\n最後に使った場所：%s" % w if w != "" else ""]


## ひな形の中身を一行で：「a = 1、b = true ／ 持ち物 key × 2」。中身がなければ「（中身なし）」。
func preset_summary(name: String) -> String:
	return preset_value_summary(run_presets().get(name, {}))


## ひな形の中身の短い言い方（「a = 1、b = true ／ 持ち物 key × 2」。なければ「（中身なし）」）。
static func preset_value_summary(v: Variant) -> String:
	if not v is Dictionary:
		return "（中身なし）"
	var parts: Array = []
	var vs = v.get("vars", {})
	if vs is Dictionary and not vs.is_empty():
		var a: Array = []
		for k in vs:
			a.append("%s = %s" % [k, AdvPlayer.value_text(vs[k])])
		parts.append("、".join(a))
	var its = v.get("items", {})
	if its is Dictionary and not its.is_empty():
		var b: Array = []
		for k in its:
			b.append("%s × %d" % [k, int(its[k])])
		parts.append("持ち物 " + "、".join(b))
	return " ／ ".join(parts) if not parts.is_empty() else "（中身なし）"


## まだない名前：「名前 のコピー」「名前 のコピー 2」…
func unique_preset_name(base: String) -> String:
	var ps := run_presets()
	var n := "%s のコピー" % base
	var i := 2
	while ps.has(n):
		n = "%s のコピー %d" % [base, i]
		i += 1
	return n


## 保存してあるひな形を別の名前で写す（new_name が "" なら「のコピー」）。写した名前（できなければ ""）。
func duplicate_run_preset(src: String, new_name: String = "") -> String:
	var ps := run_presets()
	if not ps.get(src) is Dictionary:
		_set_status("ひな形がありません：%s" % src)
		return ""
	var n := new_name.strip_edges() if new_name.strip_edges() != "" else unique_preset_name(src)
	var v: Dictionary = ps[src].duplicate(true)
	save_run_preset(n, v.get("vars", {}) if v.get("vars") is Dictionary else {}, v.get("items", {}) if v.get("items") is Dictionary else {}, preset_group(v))
	return n


## 窓の「複製」：いま書いている中身を「名前 のコピー」で保存し、窓をその写しにする（もとと比べた形で開く）。
func duplicate_preset_in_dialog() -> String:
	var base := _preset_name.text.strip_edges()
	if base == "":
		base = "ひな形"
	var n := unique_preset_name(base)
	var cur := _preset_in_dialog()
	save_run_preset(n, cur["vars"], cur["items"], _preset_group.text)
	open_preset_dialog(n)
	if run_presets().has(base):
		compare_preset_with(base)
	return n


## 比べる相手の一覧（書いているひな形のほか）。
func _fill_preset_cmp(exclude: String) -> void:
	_preset_cmp.clear()
	_preset_cmp.add_item("比べない")
	_preset_cmp.set_item_metadata(0, "")
	_preset_cmp.add_item("いつもの始まり（ひな形なし）")
	_preset_cmp.set_item_metadata(1, PRESET_CMP_START)
	var names: Array = run_presets().keys()
	names.sort()
	for n in names:
		if String(n) != exclude:
			_preset_cmp.add_item(String(n))
			_preset_cmp.set_item_metadata(_preset_cmp.item_count - 1, String(n))
	_preset_cmp.select(0)
	_update_preset_diff()


## ひな形の窓を開いたままプロジェクトが変わったとき（元に戻す・やり直すなど）：比べる相手の一覧・違い・日時を並べ直す。
## 窓に書いている中身と、選んでいた比べる相手（まだあれば）はそのまま。
func refresh_preset_dialog_keep() -> void:
	var was := String(_preset_cmp.get_item_metadata(_preset_cmp.selected)) if _preset_cmp.selected >= 0 else ""
	var name := _preset_name.text.strip_edges()
	_fill_preset_cmp(name)
	compare_preset_with(was)
	_preset_dates.text = preset_dates_text(name)
	_preset_run_last.disabled = preset_last_request(name).is_empty()


## 比べる相手を名前で選ぶ（"" で比べない）。
func compare_preset_with(other: String) -> void:
	for i in _preset_cmp.item_count:
		if String(_preset_cmp.get_item_metadata(i)) == other:
			_preset_cmp.select(i)
	_update_preset_diff()


## いま窓に書いている中身 {vars, items}。
func _on_preset_diff_meta(m: String) -> void:
	if m.begins_with("add:"):
		add_start_var_to_dialog(m.substr(4).uri_decode())
	elif m == "addall":
		add_all_start_vars_to_dialog()
	elif m == "takeall":
		take_all_preset_values()
	elif m.begins_with("take:"):
		var parts := m.split(":", true, 2)
		if parts.size() == 3:
			take_preset_value(parts[1], parts[2].uri_decode())


## 「全部足す」：ひな形にない変数（初めの値のあるもの。並べきれなかったものも）を、名前の順にいつもの値で窓の欄に足す（保存はしない）。足した数。
func add_all_start_vars_to_dialog() -> int:
	var have: Dictionary = _preset_in_dialog()["vars"]
	var keys: Array = []
	for k in _start_vals:
		if not have.has(k):
			keys.append(String(k))
	if keys.is_empty():
		return 0
	keys.sort()
	_remember_preset_edit("全部足す")
	var t := _preset_vars.text
	if t != "" and not t.ends_with("\n"):
		t += "\n"
	var lines: Array = []
	for k in keys:
		lines.append("%s = %s" % [k, AdvPlayer.value_text(_start_vals[k])])
	_preset_vars.text = t + "\n".join(lines)
	_update_preset_diff()
	_set_status("ひな形に %d 個の変数を足しました（保存すると残ります）" % keys.size())
	return keys.size()


## 「ひな形にない変数」を押したとき：その変数をいつもの値で窓のフラグと変数の欄に足す（保存はしない）。足したら true。
var preset_edit_undo: Dictionary = {}   ## 写す・足す前の窓の欄 {vars, items, what}（一つだけ。窓を開き直すと消える）
var _preset_undo_btn: Button


## 窓にキーを受け取るものを入れる（段階63）。
func _add_keys(w: Window, handler: Callable) -> void:
	var kc := AdvKeyCatcher.new()
	kc.name = "Keys"
	kc.handler = handler
	w.add_child(kc)


## Ctrl（mac は Cmd）＋ key か。Shift なし。
static func _is_ctrl_key(e: InputEvent, keys: Array) -> bool:
	return e is InputEventKey and e.pressed and not e.echo and (e.ctrl_pressed or e.meta_pressed) and not e.shift_pressed and (e as InputEventKey).keycode in keys


## Ctrl+Enter で窓の OK ボタンを押す（組を変える・書き出す。段階66）。
func _ok_key(w: AcceptDialog, e: InputEvent) -> bool:
	if _is_ctrl_key(e, [KEY_ENTER, KEY_KP_ENTER]):
		w.get_ok_button().pressed.emit()
		return true
	return false


## 片付けの窓のキー：Ctrl+Z で元に戻す、Ctrl+Y・Ctrl+Shift+Z でやり直す（写す・消す・寄せるなどの保存したもの）。
func _on_tidy_key(e: InputEvent) -> bool:
	if _is_ctrl_key(e, [KEY_Z]):
		if not model.can_undo():
			return false
		undo()
		return true
	var redo_key: bool = e is InputEventKey and e.pressed and not e.echo and (e.ctrl_pressed or e.meta_pressed) and ((e as InputEventKey).keycode == KEY_Y or ((e as InputEventKey).keycode == KEY_Z and e.shift_pressed))
	if redo_key:
		if not model.can_redo():
			return false
		redo()
		return true
	return false


## 読み込む窓のキー：Ctrl+Enter で読み込む。
func _on_import_key(e: InputEvent) -> bool:
	if _is_ctrl_key(e, [KEY_ENTER, KEY_KP_ENTER]):
		_preset_import_pick.get_ok_button().pressed.emit()
		return true
	return false


## 見た目の窓のキー：Ctrl+Z で「一つ戻す」（名前の欄に自分の取り消しが残っていればそちらを先に）。
func _on_style_key(e: InputEvent) -> bool:
	if not _is_ctrl_key(e, [KEY_Z]):
		return false
	var f := _style_dialog.gui_get_focus_owner()
	if f is LineEdit and f.has_method("has_undo") and bool(f.call("has_undo")):
		return false
	return restore_erased_style_set() != ""


## ひな形の窓のキー（段階62）：Ctrl+Enter で保存、Ctrl+Z で「写す前に戻す」（文字の欄に自分の取り消しが残っていればそちらを先に）。
## Esc でやめるのは窓のもとからの動き。受け取ったら true。
func _on_preset_key(e: InputEvent) -> bool:
	if not (e is InputEventKey and e.pressed and not e.echo) or not (e.ctrl_pressed or e.meta_pressed):
		return false
	var k := (e as InputEventKey).keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		_preset_dialog.get_ok_button().pressed.emit()
		return true
	if k == KEY_Z and not e.shift_pressed:
		var f := _preset_dialog.gui_get_focus_owner()
		if f is TextEdit and (f as TextEdit).has_undo():
			return false
		return undo_preset_edit()
	return false


## 写す・足す前の欄を覚える（「写す前に戻す」で戻す）。
func _remember_preset_edit(what: String) -> void:
	preset_edit_undo = {"vars": _preset_vars.text, "items": _preset_items.text, "what": what}
	_update_preset_undo_btn()


func _update_preset_undo_btn() -> void:
	if _preset_undo_btn == null:
		return
	_preset_undo_btn.disabled = preset_edit_undo.is_empty()
	_preset_undo_btn.tooltip_text = "「%s」の前の欄に戻します（Ctrl+Z）" % preset_edit_undo["what"] if not preset_edit_undo.is_empty() else "写す・足すをすると、その前の欄に戻せます"


## 最後の写す・足すの前の欄に戻す（手で書きかえたところもその時点に戻る）。戻したら true。
func undo_preset_edit() -> bool:
	if preset_edit_undo.is_empty():
		return false
	_preset_vars.text = preset_edit_undo["vars"]
	_preset_items.text = preset_edit_undo["items"]
	var what := String(preset_edit_undo["what"])
	preset_edit_undo = {}
	_update_preset_undo_btn()
	_update_preset_diff()
	_set_status("「%s」の前に戻しました" % what)
	return true


func add_start_var_to_dialog(var_name: String) -> bool:
	if not _start_vals.has(var_name) or _preset_in_dialog()["vars"].has(var_name):
		return false
	_remember_preset_edit("%s を足す" % var_name)
	var t := _preset_vars.text
	if t != "" and not t.ends_with("\n"):
		t += "\n"
	_preset_vars.text = t + "%s = %s" % [var_name, AdvPlayer.value_text(_start_vals[var_name])]
	_update_preset_diff()
	_set_status("ひな形に %s を足しました（保存すると残ります）" % var_name)
	return true


func _preset_in_dialog() -> Dictionary:
	var items := {}
	var raw := parse_assign_lines(_preset_items.text)
	for k in raw:
		items[k] = int(raw[k]) if (raw[k] is int or raw[k] is float or String(raw[k]).is_valid_int()) else 1
	return {"vars": parse_assign_lines(_preset_vars.text), "items": items}


func _update_preset_diff() -> void:
	if _preset_diff == null:
		return
	var other := String(_preset_cmp.get_item_metadata(_preset_cmp.selected)) if _preset_cmp.selected >= 0 else ""
	if other == "":
		_preset_diff.text = ""
		return
	var name := _preset_name.text.strip_edges()
	if other == PRESET_CMP_START:
		_preset_diff.text = start_diff_text(_preset_in_dialog(), _start_vals, name if name != "" else "この窓",
			String(model.load_project().get("entry", "")), preset_last_where(name))
		return
	var o = run_presets().get(other, {})
	_preset_diff.text = diff_text(_preset_in_dialog(), o if o is Dictionary else {}, name if name != "" else "この窓", other, true)


## 比べる相手を「いつもの始まり」に。
func compare_preset_with_start() -> void:
	compare_preset_with(PRESET_CMP_START)


## いつもの始まりの変数（名前 → 初めの値）：プロジェクト設定・シナリオの宣言の default と Ink の VAR。初めの値のないものは入れない。
func start_values() -> Dictionary:
	var out := {}
	for e in AdvVariableIndex.collect(model.project_path):
		if String(e.get("kind", "")) != "変数" or e.get("default") == null or out.has(e["name"]):
			continue
		var v = e["default"]
		if v is String and String(e.get("source", "")) == "Ink":
			var j := JSON.new()
			if j.parse(v) == OK:
				v = j.data
		out[String(e["name"])] = v
	return out


## ひな形と同じキーだけの「いつもの始まり」：変数は初めの値（ないものは入れない）、持ち物は 0 個。
static func start_base(preset: Dictionary, start_vars: Dictionary) -> Dictionary:
	var bv := {}
	var pv = preset.get("vars", {})
	if pv is Dictionary:
		for k in pv:
			if start_vars.has(k):
				bv[k] = start_vars[k]
	var bi := {}
	var pi = preset.get("items", {})
	if pi is Dictionary:
		for k in pi:
			bi[k] = 0
	return {"vars": bv, "items": bi}


## ひな形といつもの始まりの違い（BBCode）。頭に始めるシーン（いつもの開始と、最後に使った場所）。
static func start_diff_text(preset: Dictionary, start_vars: Dictionary, name: String, entry: String, last_where: String = "") -> String:
	var head := "始めるシーン：いつもは %s%s" % [entry if entry != "" else "（未設定）", "　このひな形は最後に %s" % last_where if last_where != "" else ""]
	var t := head + "\n" + diff_text(preset, start_base(preset, start_vars), name, "いつもの始まり", true)
	var o := start_others_text(preset, start_vars)
	return t + ("\n" + o if o != "" else "")


const START_OTHERS_MAX := 20


## ひな形にない変数（初めの値のあるもの）を薄く：「ひな形にない変数（いつもの値のまま 3）：a = 1、b = false …」。なければ ""。
static func start_others_text(preset: Dictionary, start_vars: Dictionary) -> String:
	var pv = preset.get("vars", {})
	var keys: Array = []
	for k in start_vars:
		if not (pv is Dictionary and pv.has(k)):
			keys.append(String(k))
	if keys.is_empty():
		return ""
	keys.sort()
	var parts: Array = []
	for k in keys.slice(0, START_OTHERS_MAX):
		parts.append("[url=add:%s]%s = %s[/url]" % [k.uri_encode(), k, AdvPlayer.value_text(start_vars[k])])
	var more := " …ほか %d" % (keys.size() - START_OTHERS_MAX) if keys.size() > START_OTHERS_MAX else ""
	return "[color=#9ca3af]ひな形にない変数（いつもの値のまま %d）：%s%s　[url=addall]［全部足す］[/url][/color]" % [keys.size(), "、".join(parts), more]


## 二つのひな形の違うところ：[{kind: "vars"|"items", key, a, b}]（ない方は null）。数は 3 と 3.0 を同じと見る。並びは種類・名前の順。
static func diff_presets(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for kind in ["vars", "items"]:
		var da: Dictionary = a.get(kind, {}) if a.get(kind) is Dictionary else {}
		var db: Dictionary = b.get(kind, {}) if b.get(kind) is Dictionary else {}
		var keys: Array = da.keys()
		for k in db:
			if not keys.has(k):
				keys.append(k)
		keys.sort()
		for k in keys:
			var va = da.get(k)
			var vb = db.get(k)
			if not _same_value(va, vb):
				out.append({"kind": kind, "key": String(k), "a": va, "b": vb})
	return out


static func _same_value(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return JSON.stringify(a) == JSON.stringify(b)


## 違うところを人の読む形に（BBCode）。同じなら「違うところはありません」。
## links なら違う行を押せるようにする（[url=take:vars|items:キー]。押すと bn の値を an（窓）へ写す）。
static func diff_text(a: Dictionary, b: Dictionary, an: String, bn: String, links: bool = false) -> String:
	var d := diff_presets(a, b)
	if d.is_empty():
		return "[color=#34d399]%s と %s に違うところはありません[/color]" % [an, bn]
	var lines: Array = ["[b]%s[/b] ／ [b]%s[/b] の違い（%d）" % [an, bn, d.size()]]
	for e in d:
		var line := "%s %s：%s ／ %s" % ["変数" if e["kind"] == "vars" else "持ち物", e["key"],
			"なし" if e["a"] == null else AdvPlayer.value_text(e["a"]), "なし" if e["b"] == null else AdvPlayer.value_text(e["b"])]
		lines.append("[url=take:%s:%s]%s[/url]" % [e["kind"], String(e["key"]).uri_encode(), line] if links else line)
	if links:
		lines.append("[color=#9ca3af]行を押すと、%s の値を窓へ写します　[url=takeall]［全部写す］[/url][/color]" % bn)
	return "\n".join(lines)


## 窓で比べている相手の中身（いつもの始まりなら start_base）。比べていなければ null。
func _preset_cmp_target() -> Variant:
	var other := String(_preset_cmp.get_item_metadata(_preset_cmp.selected)) if _preset_cmp != null and _preset_cmp.selected >= 0 else ""
	if other == "":
		return null
	if other == PRESET_CMP_START:
		return start_base(_preset_in_dialog(), _start_vals)
	var o = run_presets().get(other)
	return o if o is Dictionary else null


## 違いの行を押したとき：比べている相手の kind（"vars" か "items"）の key の値を窓の欄へ写す（相手になければ窓から消す）。保存はしない。写したら true。
func take_preset_value(kind: String, key: String, remember: bool = true) -> bool:
	var t = _preset_cmp_target()
	if t == null or not kind in ["vars", "items"]:
		return false
	var src = t.get(kind, {})
	var mine = _preset_in_dialog().get(kind, {})
	var has_b: bool = src is Dictionary and src.has(key)
	var has_a: bool = mine is Dictionary and mine.has(key)
	if not has_a and not has_b:
		return false
	if has_a and has_b and _same_value(mine[key], src[key]):
		return false
	if remember:
		_remember_preset_edit("%s を写す" % key)
	var edit_box: TextEdit = _preset_vars if kind == "vars" else _preset_items
	edit_box.text = set_assign_line(edit_box.text, key, (AdvPlayer.value_text(src[key]) if kind == "vars" else str(int(src[key]))) if has_b else null)
	_update_preset_diff()
	_set_status("%s を写しました（保存すると残ります）" % key)
	return true


## 「全部写す」：違うところを全部、比べている相手に合わせる（ひな形の変数・持ち物を相手と同じにする）。写した数。
func take_all_preset_values() -> int:
	var t = _preset_cmp_target()
	if t == null:
		return 0
	var d := diff_presets(_preset_in_dialog(), t)
	if d.is_empty():
		return 0
	_remember_preset_edit("全部写す")
	var n := 0
	for e in d:
		if take_preset_value(String(e["kind"]), String(e["key"]), false):
			n += 1
	return n


## 「名前 = 値」の行の書きかえ：key の行を value に（null なら行を消す）。なければ終わりに足す。ほかの行（# の行・空の行も）はそのまま。
static func set_assign_line(text: String, key: String, value: Variant) -> String:
	var lines: Array = Array(text.split("\n"))
	var found := false
	var out: Array = []
	for raw in lines:
		var s := String(raw).strip_edges()
		var at := s.find("=")
		if not s.begins_with("#") and at > 0 and s.substr(0, at).strip_edges() == key:
			if not found and value != null:
				out.append("%s = %s" % [key, value])
			found = true
			continue
		out.append(raw)
	if not found and value != null:
		while not out.is_empty() and String(out[-1]).strip_edges() == "":
			out.pop_back()
		out.append("%s = %s" % [key, value])
	return "\n".join(out)


func _confirm_preset() -> void:
	var pname := _preset_name.text.strip_edges()
	if pname == "":
		_set_status("ひな形の名前を書いてください")
		return
	var items := {}
	var raw := parse_assign_lines(_preset_items.text)
	for k in raw:
		items[k] = int(raw[k]) if (raw[k] is int or raw[k] is float or String(raw[k]).is_valid_int()) else 1
	save_run_preset(pname, parse_assign_lines(_preset_vars.text), items, _preset_group.text)


func _build_preset_dialog() -> void:
	_preset_dialog = ConfirmationDialog.new()
	_preset_dialog.title = "実行のひな形"
	_preset_dialog.ok_button_text = "保存"
	_preset_dialog.cancel_button_text = "やめる"
	var b := VBoxContainer.new()
	_preset_dialog.add_child(b)
	var r := HBoxContainer.new()
	b.add_child(r)
	var l := Label.new()
	l.text = "名前"
	r.add_child(l)
	_preset_name = LineEdit.new()
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(_preset_name)
	var gl := Label.new()
	gl.text = "組"
	r.add_child(gl)
	_preset_group = LineEdit.new()
	_preset_group.placeholder_text = "（なし）"
	_preset_group.custom_minimum_size = Vector2(140, 0)
	_preset_group.tooltip_text = "同じ組のひな形は「実行：」の一覧でまとめて並びます"
	r.add_child(_preset_group)
	var dr := HBoxContainer.new()
	b.add_child(dr)
	_preset_dates = Label.new()
	_preset_dates.modulate = Color(1, 1, 1, 0.7)
	_preset_dates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dr.add_child(_preset_dates)
	_preset_run_last = Button.new()
	_preset_run_last.text = "そこから動かす"
	_preset_run_last.tooltip_text = "このひな形を最後に使った場所から、もう一度ゲームを動かします（保存してある中身で）"
	_preset_run_last.size_flags_vertical = Control.SIZE_SHRINK_END
	_preset_run_last.pressed.connect(func():
		if run_preset_from_last(_preset_name.text.strip_edges()):
			_preset_dialog.hide())
	dr.add_child(_preset_run_last)
	var lv := Label.new()
	lv.text = "フラグと変数（1行に「名前 = 値」。値は true、3、\"文字\" など）"
	b.add_child(lv)
	_preset_vars = TextEdit.new()
	_preset_vars.custom_minimum_size = Vector2(0, 120)
	_preset_vars.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(_preset_vars)
	var li := Label.new()
	li.text = "持ち物（1行に「ID = 個数」。0 なら持たない）"
	b.add_child(li)
	_preset_items = TextEdit.new()
	_preset_items.custom_minimum_size = Vector2(0, 80)
	b.add_child(_preset_items)
	var cr := HBoxContainer.new()
	b.add_child(cr)
	var cl := Label.new()
	cl.text = "比べる："
	cr.add_child(cl)
	_preset_cmp = OptionButton.new()
	_preset_cmp.tooltip_text = "ほかのひな形と比べて、値の違うところだけを並べます"
	_preset_cmp.item_selected.connect(func(_i): _update_preset_diff())
	cr.add_child(_preset_cmp)
	_preset_diff = RichTextLabel.new()
	_preset_diff.bbcode_enabled = true
	_preset_diff.scroll_active = true
	_preset_diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_diff.custom_minimum_size = Vector2(480, 150)
	_preset_diff.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 窓を広げると違いの欄が伸びる（段階61。欄より多めに）
	_preset_diff.size_flags_stretch_ratio = 4.0
	_preset_diff.meta_underlined = false
	_preset_diff.meta_clicked.connect(func(m): _on_preset_diff_meta(String(m)))
	b.add_child(_preset_diff)
	_preset_vars.text_changed.connect(_update_preset_diff)
	_preset_items.text_changed.connect(_update_preset_diff)
	var io := HBoxContainer.new()
	b.add_child(io)
	var ex := Button.new()
	ex.text = "書き出す…"
	ex.tooltip_text = "このプロジェクトのひな形を、ほかのプロジェクトで読み込めるファイル（.json）に書き出します（全部か、選んだものだけ）"
	ex.pressed.connect(func(): open_export_pick())
	io.add_child(ex)
	var im := Button.new()
	im.text = "読み込む…"
	im.tooltip_text = "書き出したひな形のファイルから、読み込むものを選んで読み込みます（同じ名前で中身が違うものは「（読み込み）」を付けて足します）"
	im.pressed.connect(func(): _preset_import_dialog.popup_centered(Vector2i(720, 480)))
	io.add_child(im)
	_preset_undo_btn = Button.new()
	_preset_undo_btn.text = "写す前に戻す"
	_preset_undo_btn.pressed.connect(func(): undo_preset_edit())
	io.add_child(_preset_undo_btn)
	_update_preset_undo_btn()
	_preset_export_dialog = FileDialog.new()
	_preset_export_dialog.title = "ひな形を書き出す"
	_preset_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_preset_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_preset_export_dialog.filters = PackedStringArray(["*.json ; ひな形"])
	_preset_export_dialog.current_file = "run_presets.json"
	_preset_export_dialog.file_selected.connect(func(path):
		var err := export_run_presets(path, export_names)
		_preset_msg.text = ("書き出しました：%s" % path) if err == OK else ("書き出せません：%s" % error_string(err)))
	add_child(_preset_export_dialog)
	_preset_export_pick = ConfirmationDialog.new()
	_add_keys(_preset_export_pick, func(e): return _ok_key(_preset_export_pick, e))
	_preset_export_pick.title = "書き出すひな形"
	_preset_export_pick.ok_button_text = "書き出す…"
	_preset_export_pick.cancel_button_text = "やめる"
	var pb := VBoxContainer.new()
	_preset_export_pick.add_child(pb)
	var pr := HBoxContainer.new()
	pb.add_child(pr)
	for spec in [["全部", true], ["なし", false]]:
		var bb := Button.new()
		bb.text = spec[0]
		var on: bool = spec[1]
		bb.pressed.connect(func(): set_export_all(on))
		pr.add_child(bb)
	var esc := ScrollContainer.new()
	esc.custom_minimum_size = Vector2(360, 220)
	esc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fit_list_scroll(esc)
	pb.add_child(esc)
	_export_list = VBoxContainer.new()
	_export_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esc.add_child(_export_list)
	_preset_export_pick.confirmed.connect(func():
		if confirm_export_pick():
			_preset_export_dialog.popup_centered(Vector2i(720, 480)))
	add_child(_preset_export_pick)
	_preset_import_dialog = FileDialog.new()
	_preset_import_dialog.title = "ひな形を読み込む"
	_preset_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_preset_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_preset_import_dialog.filters = PackedStringArray(["*.json ; ひな形"])
	_preset_import_dialog.file_selected.connect(func(path): open_import_pick(path))
	add_child(_preset_import_dialog)
	_preset_import_pick = ConfirmationDialog.new()
	_preset_import_pick.title = "読み込むひな形"
	_preset_import_pick.ok_button_text = "読み込む"
	_preset_import_pick.cancel_button_text = "やめる"
	var ib := VBoxContainer.new()
	_preset_import_pick.add_child(ib)
	var ir := HBoxContainer.new()
	ib.add_child(ir)
	for spec in [["全部", true], ["なし", false]]:
		var bb := Button.new()
		bb.text = spec[0]
		var on: bool = spec[1]
		bb.pressed.connect(func(): set_import_all(on))
		ir.add_child(bb)
	_import_overwrite_check = CheckBox.new()
	_import_overwrite_check.text = "中身が違うものは上書きする"
	_import_overwrite_check.tooltip_text = "印を付けると、同じ名前で中身が違うひな形を「（読み込み）」で足すかわりに、その名前のまま書きかえます（元に戻せます）"
	_import_overwrite_check.toggled.connect(func(on): set_import_overwrite(on))
	ib.add_child(_import_overwrite_check)
	var igr := HBoxContainer.new()
	ib.add_child(igr)
	var igl := Label.new()
	igl.text = "読み込む組"
	igr.add_child(igl)
	_import_group_pick = OptionButton.new()
	_import_group_pick.tooltip_text = "読み込むひな形をまとめて入れる組（ファイルの組のまま・組なし・いまある組・新しい組）"
	_import_group_pick.item_selected.connect(func(i): set_import_group(String(_import_group_pick.get_item_metadata(i))))
	igr.add_child(_import_group_pick)
	_import_group_new = LineEdit.new()
	_import_group_new.placeholder_text = "新しい組の名前"
	_import_group_new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_import_group_new.text_changed.connect(func(_t): _refresh_import_pick(false))
	igr.add_child(_import_group_new)
	var isc := ScrollContainer.new()
	isc.custom_minimum_size = Vector2(460, 220)
	isc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fit_list_scroll(isc)
	ib.add_child(isc)
	_import_list = VBoxContainer.new()
	_import_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	isc.add_child(_import_list)
	_import_preview = RichTextLabel.new()
	_import_preview.bbcode_enabled = true
	_import_preview.scroll_active = true
	_import_preview.custom_minimum_size = Vector2(460, 90)
	_import_preview.visible = false
	ib.add_child(_import_preview)
	_preset_import_pick.confirmed.connect(func(): confirm_import_pick())
	_add_keys(_preset_import_pick, _on_import_key)
	_preset_import_pick.get_ok_button().tooltip_text = "印を付けたものを読み込みます（Ctrl+Enter）"
	add_child(_preset_import_pick)
	_preset_msg = Label.new()
	b.add_child(_preset_msg)
	var del := _preset_dialog.add_button("消す", true, "delete")
	del.tooltip_text = "この名前のひな形を消します"
	var dup := _preset_dialog.add_button("複製", true, "dup")
	dup.tooltip_text = "窓に書いている中身を「名前 のコピー」として保存し、その写しを開きます"
	_preset_dialog.custom_action.connect(func(a):
		if a == "delete":
			delete_run_preset(_preset_name.text.strip_edges())
			_preset_dialog.hide()
		elif a == "dup":
			duplicate_preset_in_dialog())
	_preset_dialog.confirmed.connect(_confirm_preset)
	var kc := AdvKeyCatcher.new()
	kc.name = "Keys"
	kc.handler = _on_preset_key
	_preset_dialog.add_child(kc)
	_preset_dialog.get_ok_button().tooltip_text = "保存します（Ctrl+Enter）"
	add_child(_preset_dialog)


## 最近の実行（新しい順。最大 RUN_HISTORY_MAX 件）。
static func run_history() -> Array:
	var d = AdvJson.load_file(RUN_HISTORY_FILE, []) if FileAccess.file_exists(RUN_HISTORY_FILE) else []
	return d if d is Array else []


static func clear_run_history() -> void:
	if FileAccess.file_exists(RUN_HISTORY_FILE):
		DirAccess.remove_absolute(RUN_HISTORY_FILE)


## 同じ頼み（シーン・会話・行・道筋・ノット・ひな形が同じ）は前のを消して先頭に（お気に入りの印はそのまま）。
## お気に入り（fav）はいつも上に並べ、数えない。ほかは RUN_HISTORY_MAX 件まで。ひな形の値は入れない（実行のときに読み直す）。
func _add_history(r: Dictionary) -> void:
	var e := {}
	for k in ["scene", "dialogue", "line", "path", "knot", "preset", "pre_sets"]:
		if r.has(k):
			e[k] = r[k]
	var h: Array = run_history()
	for x in h:
		if x is Dictionary and _same_run(x, e) and bool(x.get("fav", false)):
			e["fav"] = true
	h = h.filter(func(x): return x is Dictionary and not _same_run(x, e))
	h.push_front(e)
	_write_history(h)


## お気に入りを上に（それぞれの中の並びはそのまま）、お気に入りでないものは RUN_HISTORY_MAX 件までにして書く。
func _write_history(h: Array) -> void:
	var favs: Array = h.filter(func(x): return bool(x.get("fav", false)))
	var rest: Array = h.filter(func(x): return not bool(x.get("fav", false)))
	if rest.size() > RUN_HISTORY_MAX:
		rest.resize(RUN_HISTORY_MAX)
	var f := FileAccess.open(RUN_HISTORY_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(favs + rest))
		f.close()
	_fill_history_menu()


## 履歴の i 番目のお気に入りの印を付ける・外す。付いたら true。
func toggle_favorite(i: int) -> bool:
	var h := run_history()
	if i < 0 or i >= h.size() or not h[i] is Dictionary:
		return false
	var on := not bool(h[i].get("fav", false))
	if on:
		h[i]["fav"] = true
	else:
		h[i].erase("fav")
	_write_history(h)
	_set_status("%s：%s" % ["お気に入りにしました" if on else "お気に入りから外しました", history_label(h[i])])
	return on


static func _same_run(a: Dictionary, b: Dictionary) -> bool:
	for k in ["scene", "dialogue", "knot", "preset"]:
		if str(a.get(k, "")) != str(b.get(k, "")):
			return false
	return int(a.get("line", 0)) == int(b.get("line", 0)) and _path_key(a.get("path", [])) == _path_key(b.get("path", [])) \
		and pre_sets_mode(a.get("pre_sets", false)) == pre_sets_mode(b.get("pre_sets", false))


static func _path_key(p: Variant) -> String:
	if not p is Array:
		return ""
	return ",".join(p.map(func(e): return str(int(e)) if (e is int or e is float) else "'" + String(e)))


## 「hall ／ 会話 talk の 3 番目から ／ ひな形 終盤」（お気に入りは頭に ★）
static func history_label(r: Dictionary) -> String:
	var parts: Array = [("★ " if bool(r.get("fav", false)) else "") + String(r.get("scene", ""))]
	var place := AdvPlayer.run_place_text(r)
	if place != "":
		parts.append(place)
	if String(r.get("preset", "")) != "":
		parts.append("ひな形 %s" % r["preset"])
	return " ／ ".join(parts)


## 履歴の i 番目をもう一度動かす（ひな形はいまの値で。その記録の preset がなければ「なし」）。
func run_history_entry(i: int, play: bool = true) -> bool:
	var h := run_history()
	if i < 0 or i >= h.size() or not h[i] is Dictionary:
		return false
	var r: Dictionary = h[i].duplicate()
	r.erase("fav")
	if not r.has("preset"):
		r["preset"] = ""
	return run_from(r, play)


func _fill_history_menu() -> void:
	if run_history_menu == null:
		return
	var pm := run_history_menu.get_popup()
	pm.clear()
	var h := run_history()
	if h.is_empty():
		pm.add_item("（まだありません）", 0)
		pm.set_item_disabled(0, true)
		return
	for i in h.size():
		pm.add_item(history_label(h[i]) if h[i] is Dictionary else "?", i)
	pm.add_separator()
	# お気に入りの印：子のメニューで選んだものを付ける・外す
	var sub := pm.get_node_or_null("Fav") as PopupMenu
	if sub == null:
		sub = PopupMenu.new()
		sub.name = "Fav"
		sub.id_pressed.connect(func(id): toggle_favorite(id))
		pm.add_child(sub)
	sub.clear()
	for i in h.size():
		sub.add_check_item(history_label(h[i]).trim_prefix("★ ") if h[i] is Dictionary else "?", i)
		sub.set_item_checked(i, h[i] is Dictionary and bool(h[i].get("fav", false)))
	pm.add_submenu_node_item("★ お気に入りの印…", sub, 1001)
	pm.add_item("履歴を消す（お気に入りは残す）", 1000)


## お気に入りでないものを消す。お気に入りも消すなら keep_favorites = false。
func clear_history_keep_favorites(keep_favorites: bool = true) -> void:
	var favs: Array = run_history().filter(func(x): return x is Dictionary and bool(x.get("fav", false))) if keep_favorites else []
	if favs.is_empty():
		clear_run_history()
		_fill_history_menu()
	else:
		_write_history(favs)


func _on_history_menu(id: int) -> void:
	if id == 1000:
		clear_history_keep_favorites()
		_set_status("実行の履歴を消しました（お気に入りは残しました）")
		return
	if id >= 1000:
		return
	run_history_entry(id)


## 実行の列（シーンの画面と会話の画面で使う）：ひな形・ひな形…・履歴。
func _build_run_row(parent: Control) -> void:
	var l := Label.new()
	l.text = "実行："
	parent.add_child(l)
	run_preset_pick = OptionButton.new()
	run_preset_pick.tooltip_text = "実行のときに入れるフラグ・変数・持ち物のひな形"
	run_preset_pick.item_selected.connect(_on_preset_picked)
	run_preset_pick.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			open_preset_context(selected_preset, run_preset_pick.get_screen_position() + e.position)
			run_preset_pick.accept_event())
	var pp := run_preset_pick.get_popup()
	pp.window_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var fi := pp.get_focused_item()
			var m := String(run_preset_pick.get_item_metadata(fi)) if fi >= 0 else ""
			if m != "" and not m.begins_with("#group:"):
				pp.hide()
				open_preset_context(m, Vector2(pp.position) + e.position))
	parent.add_child(run_preset_pick)
	_preset_ctx = PopupMenu.new()
	_preset_ctx.id_pressed.connect(preset_context_pressed)
	parent.add_child(_preset_ctx)
	_preset_filter_edit = LineEdit.new()
	_preset_filter_edit.placeholder_text = "絞り込み"
	_preset_filter_edit.custom_minimum_size = Vector2(100, 0)
	_preset_filter_edit.clear_button_enabled = true
	_preset_filter_edit.tooltip_text = "ひな形の一覧を、名前か組の一部で絞り込みます"
	_preset_filter_edit.text_changed.connect(func(t): set_preset_filter(t))
	parent.add_child(_preset_filter_edit)
	_sort_pick = OptionButton.new()
	for lb in RUN_SORT_LABELS:
		_sort_pick.add_item(lb)
	_sort_pick.select(RUN_SORTS.find(run_sort()))
	_sort_pick.tooltip_text = "それぞれの組の中の並べ方：名前の順・最後に使った順（使っていないものは下）・新しく作った順（作った時刻のわからない古いものは下）"
	_sort_pick.item_selected.connect(func(i): set_run_sort(RUN_SORTS[i]))
	parent.add_child(_sort_pick)
	var tb := Button.new()
	tb.text = "片付け…"
	tb.tooltip_text = "しばらく使っていないひな形を、まとめて消すか一つの組に寄せます"
	tb.pressed.connect(func(): open_tidy_dialog())
	parent.add_child(tb)
	var gb := Button.new()
	gb.text = "組…"
	gb.tooltip_text = "ひな形の組の名前を変える・組ごと書き出す・組ごと消す"
	gb.pressed.connect(func(): open_group_dialog(preset_group(run_presets().get(selected_preset, {}))))
	parent.add_child(gb)
	var pe := Button.new()
	pe.text = "ひな形…"
	pe.tooltip_text = "選んでいるひな形を書きかえます（ひな形なしなら新しく作ります）"
	pe.pressed.connect(func(): open_preset_dialog(selected_preset))
	parent.add_child(pe)
	run_history_menu = MenuButton.new()
	run_history_menu.text = "履歴 ▾"
	run_history_menu.flat = false
	run_history_menu.tooltip_text = "最近の実行。選ぶとすぐもう一度動かします"
	run_history_menu.get_popup().id_pressed.connect(_on_history_menu)
	run_history_menu.about_to_popup.connect(_fill_history_menu)
	parent.add_child(run_history_menu)
	_fill_preset_pick()
	_fill_history_menu()


## シーンの ID でシーンの画面を開く（ゲームの「エディタで開く」、ID の確認の一覧から）。開けたら true。
func open_scene_by_id(id: String) -> bool:
	var at: Dictionary = model.all_scene_ids().get(id, {})
	if at.is_empty():
		_set_status("シーンが見つかりません：%s" % id)
		return false
	if _dirty:
		save()
	sid = String(at["scenario"])
	cid = String(at["chapter"])
	scene_id = id
	_show(Page.SCENE)
	_set_status("シーンを開きました：%s" % id)
	return true


## エディタでファイルを書いたとき：ID の確認の一覧を出していれば、確かめ直す（まとめて1回）。
func _on_files_changed() -> void:
	_ext_snap = files_snapshot()
	if _tidy_dialog != null and _tidy_dialog.visible:
		refresh_tidy_keep()
	if _preset_dialog != null and _preset_dialog.visible:
		refresh_preset_dialog_keep()
	if check_panel == null or not check_panel.visible or _recheck_pending:
		return
	_recheck_pending = true
	(func():
		_recheck_pending = false
		if check_panel.visible:
			refresh_check()).call_deferred()


# ---------------------------------------------------------------- 画面を作る

func _build() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	_crumbs = HFlowContainer.new()
	_crumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumbs.size_flags_stretch_ratio = 3.0   # 場所の表示を優先して広くとる（右の文言は切れてもよい）
	top.add_child(_crumbs)
	_status = Label.new()
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(120, 0)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)
	_undo_b = Button.new()
	_undo_b.text = "↶ 元に戻す"
	_undo_b.pressed.connect(undo)
	top.add_child(_undo_b)
	_redo_b = Button.new()
	_redo_b.text = "↷ やり直す"
	_redo_b.pressed.connect(redo)
	top.add_child(_redo_b)
	check_toggle = Button.new()
	check_toggle.text = "ID の確認"
	check_toggle.toggle_mode = true
	check_toggle.tooltip_text = "プロジェクト全体で、見つからない素材・シーン・持ち物の ID を一覧にします（もう一度押すと隠します）"
	check_toggle.toggled.connect(show_check_panel)
	top.add_child(check_toggle)
	auto_reload_toggle = CheckButton.new()
	auto_reload_toggle.text = "保存で読み直す"
	auto_reload_toggle.tooltip_text = "デバッグ実行中のゲームが、ファイルを保存したら自動で読み直します（プロジェクト設定 debug.auto_reload）。\n実行中のゲームにも、数秒で伝わります"
	auto_reload_toggle.toggled.connect(set_auto_reload_setting)
	top.add_child(auto_reload_toggle)
	var stb := Button.new()
	stb.text = "見た目…"
	stb.tooltip_text = "ゲームのコンソール（noticestyle … keep 名前）で取っておいたお知らせの見た目を選んで、プロジェクト設定に書きます"
	stb.pressed.connect(func(): open_style_sets_dialog())
	top.add_child(stb)
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
	region_editor = AdvRegionEditor.new()
	add_child(region_editor)
	_scene_form.expr_mode = _expr_mode_of
	_scene_form.expr_requested.connect(_on_form_expr.bind(_scene_form))
	_build_check_panel()
	_sync_auto_reload_toggle()
	_ext_snap = files_snapshot()
	_update_undo_buttons()


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
	_start_row = HBoxContainer.new()
	left.add_child(_start_row)
	var sl := Label.new()
	sl.text = "開始シナリオ"
	sl.tooltip_text = "ゲームをこのシナリオの start（開始シーン）から始めます（プロジェクト設定の entry）"
	_start_row.add_child(sl)
	_start_pick = OptionButton.new()
	_start_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_pick.item_selected.connect(_on_start_picked)
	_start_row.add_child(_start_pick)
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
	_grid.reordered.connect(_on_reordered)
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
	var reg_b := Button.new()
	reg_b.text = "範囲を絵で決める…"
	reg_b.tooltip_text = "背景の上をドラッグして、もの・出口の範囲（region）を決めます"
	reg_b.pressed.connect(_open_region_editor)
	sb.add_child(reg_b)
	var run_b := Button.new()
	run_b.text = "▶ このシーンから実行"
	run_b.tooltip_text = "ゲームを動かして、オープニングとタイトルを飛ばし、このシーンから始めます（デバッグ実行）"
	run_b.pressed.connect(func(): run_from_scene(scene_id))
	sb.add_child(run_b)
	var rr := HBoxContainer.new()
	left.add_child(rr)
	_build_run_row(rr)

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
	var rd := Button.new()
	rd.name = "RunHere"
	rd.text = "▶ ここから実行"
	rd.tooltip_text = "会話は選んでいる手順から、Ink はカーソルのあるノットから、ゲームを動かします（シーンの画面で選んだひな形を使います）"
	rd.pressed.connect(func(): run_from_dialogue())
	row.add_child(rd)
	_pre_sets_check = CheckBox.new()
	_pre_sets_check.text = "設定を先に"
	_pre_sets_check.tooltip_text = "JSON の会話の途中から実行するとき、そこまでに通るはずの「設定する」（set・let）を先に動かします（「もし」の中までは見ません）"
	_pre_sets_check.toggled.connect(func(on):
		run_pre_sets = on
		_pre_cond_check.disabled = not on)
	row.add_child(_pre_sets_check)
	_pre_cond_check = CheckBox.new()
	_pre_cond_check.text = "条件も"
	_pre_cond_check.disabled = true
	_pre_cond_check.tooltip_text = "前にある「もし」も、中の「設定する」だけを、そのときの値で条件を見て動かします（文や選択肢は出しません）"
	_pre_cond_check.toggled.connect(func(on): run_pre_cond = on)
	row.add_child(_pre_cond_check)
	_dlg_msg = Label.new()
	_dlg_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dlg_msg.clip_text = true
	row.add_child(_dlg_msg)
	_dlg_steps = AdvStepEditor.new()
	_dlg_steps.id_source = id_candidates
	_dlg_steps.image_source = _thumb
	_dlg_steps.audio_player = play_audio
	_dlg_steps.changed.connect(func(): _dirty = true)
	box.add_child(_dlg_steps)
	_ink_code = CodeEdit.new()
	_ink_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ink_code.gutters_draw_line_numbers = true
	_ink_code.text_changed.connect(func():
		_dirty = true
		if not ink_completion_items(_ink_line_before_caret()).is_empty():
			_ink_code.request_code_completion(true))
	_ink_code.code_completion_enabled = true
	_ink_code.code_completion_requested.connect(_fill_ink_completion)
	box.add_child(_ink_code)
	return box


func _ink_line_before_caret() -> String:
	return _ink_code.get_line(_ink_code.get_caret_line()).substr(0, _ink_code.get_caret_column())


## Ink の call_scene("…") と goto_scene("…") の行き先の候補 [{label, insert}]。
## call_scene ではサブシーン（kind: sub）だけ、goto_scene ではすべてのシーン。
func ink_completion_items(line: String) -> Array:
	var m := RegEx.create_from_string("(call_scene|goto_scene)\\(\\s*\"([A-Za-z0-9_\\-]*)$").search(line)
	if m == null or model == null:
		return []
	var only_sub := m.get_string(1) == "call_scene"
	var typed := m.get_string(2)
	var out := []
	for s in model.scenarios():
		for c in model.chapters(s["id"]):
			var scs = model.load_chapter_data(s["id"], c["id"]).get("scenes", {})
			if not scs is Dictionary:
				continue
			for id in scs:
				var sc = scs[id]
				var kind := String(sc.get("kind", "normal")) if sc is Dictionary else "normal"
				if only_sub and kind != "sub":
					continue
				if typed != "" and not String(id).begins_with(typed):
					continue
				out.append({"label": "%s  — %s" % [id, kind], "insert": String(id)})
	return out


func _fill_ink_completion() -> void:
	for it in ink_completion_items(_ink_line_before_caret()):
		_ink_code.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, String(it["label"]), String(it["insert"]))
	_ink_code.update_code_completion_options(true)


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
	_cmd_steps.id_source = id_candidates
	_cmd_steps.image_source = _thumb
	_cmd_steps.audio_player = play_audio
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

	# 新規作成：名前と ID
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "新規作成"
	var nb := GridContainer.new()
	nb.columns = 2
	_new_dialog.add_child(nb)
	var nl := Label.new()
	nl.text = "名前"
	nb.add_child(nl)
	_new_name = LineEdit.new()
	_new_name.custom_minimum_size = Vector2(300, 0)
	_new_name.text_changed.connect(func(t: String):
		if not _new_id_touched:
			_new_id.text = model.suggest_id(_new_level, t, sid)
		_check_new_id())
	nb.add_child(_new_name)
	var il := Label.new()
	il.text = "ID"
	nb.add_child(il)
	_new_id = LineEdit.new()
	_new_id.placeholder_text = "英小文字・数字・_"
	_new_id.text_changed.connect(func(_t):
		_new_id_touched = true
		_check_new_id())
	nb.add_child(_new_id)
	nb.add_child(Control.new())
	_new_msg = Label.new()
	_new_msg.modulate = Color(1, 0.6, 0.5)
	nb.add_child(_new_msg)
	_new_dialog.register_text_enter(_new_name)
	_new_dialog.register_text_enter(_new_id)
	_new_dialog.confirmed.connect(func():
		if _new_done.is_valid() and _check_new_id():
			_new_done.call(_new_name.text.strip_edges(), _new_id.text.strip_edges()))
	add_child(_new_dialog)
	_build_preset_dialog()
	_build_group_dialog()
	_build_tidy_dialog()
	_build_style_sets_dialog()


## 名前と ID を聞いて作る。level は scenario・chapter・scene・dialogue。done は func(name, id)。
func ask_new(level: String, default_name: String, done: Callable, show_name: bool = true) -> void:
	_new_level = level
	_new_done = done
	_new_id_touched = false
	_new_dialog.title = "新規作成（%s）" % {"scenario": "シナリオ", "chapter": "チャプター", "scene": "シーン", "dialogue": "セリフ"}.get(level, level)
	_new_name.text = default_name
	_new_name.get_parent().get_child(0).visible = show_name
	_new_name.visible = show_name
	_new_id.text = model.suggest_id(level, default_name, sid)
	_check_new_id()
	_new_dialog.popup_centered()
	(_new_name if show_name else _new_id).grab_focus.call_deferred()
	if show_name:
		_new_name.select_all.call_deferred()


func _check_new_id() -> bool:
	var id := _new_id.text.strip_edges()
	var msg := ""
	if not AdvScenarioModel.is_valid_id(id):
		msg = "ID には英小文字・数字・_・- を使ってください"
	elif model.taken_ids(_new_level, sid).has(id):
		msg = "その ID はもう使われています"
	elif _new_name.visible and _new_name.text.strip_edges() == "":
		msg = "名前を書いてください"
	_new_msg.text = msg
	_new_dialog.get_ok_button().disabled = msg != ""
	return msg == ""


# ---------------------------------------------------------------- 元に戻す

func undo() -> void:
	if _dirty:
		save()
	var label := model.undo()
	_after_history("元に戻しました：%s" % label if label != "" else "元に戻すものはありません")


func redo() -> void:
	var label := model.redo()
	_after_history("やり直しました：%s" % label if label != "" else "やり直すものはありません")


func _after_history(msg: String) -> void:
	_dirty = false
	_sync_auto_reload_toggle()
	# 開いていたものがなくなっていたら、上の一覧へ
	if page >= Page.SCENARIO and model.scenario(sid).is_empty():
		page = Page.GAME
	elif page >= Page.CHAPTER and model.chapter(sid, cid).is_empty():
		page = Page.SCENARIO
	elif page >= Page.SCENE and not model.all_scene_ids().has(scene_id):
		page = Page.CHAPTER
	_show(page)
	_refresh_expr_candidates()
	_set_status(msg)


func _update_undo_buttons() -> void:
	if _undo_b == null:
		return
	_undo_b.disabled = not model.can_undo()
	_redo_b.disabled = not model.can_redo()
	_undo_b.tooltip_text = "元に戻す：%s（Ctrl+Z）" % model.undo_label() if model.can_undo() else "元に戻すものはありません"
	_redo_b.tooltip_text = "やり直す：%s（Ctrl+Shift+Z）" % model.redo_label() if model.can_redo() else "やり直すものはありません"


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	var k: InputEventKey = event
	if not k.is_command_or_control_pressed() or not (k.keycode == KEY_Z or k.keycode == KEY_Y):
		return
	# 文字を書く欄は、その欄の元に戻すを使う
	var f := get_viewport().gui_get_focus_owner()
	if f is TextEdit or f is LineEdit:
		return
	if f != null and not is_ancestor_of(f):
		return
	if k.keycode == KEY_Y or k.shift_pressed:
		redo()
	else:
		undo()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 式（フォームから）

## フォームの項目が式なら、その種類（"condition"・"let"）。
func _expr_mode_of(path: Array, s: Variant) -> String:
	if not path.is_empty() and str(path.back()) == "let":
		return AdvExprEditor.MODE_LET
	if s is Dictionary and String(s.get("$ref", "")).ends_with("/condition"):
		return AdvExprEditor.MODE_CONDITION
	return ""


func _on_form_expr(path: Array, value: String, mode: String, form: AdvSchemaForm) -> void:
	expr_editor.open(value, mode, func(t: String): form.set_value_at(path, t))


# ---------------------------------------------------------------- 開始シナリオ

func _fill_start_pick() -> void:
	_start_pick.clear()
	var cur := model.start_scenario()
	for s in model.scenarios():
		if s["loose"]:
			continue
		_start_pick.add_item(String(s["name"]))
		_start_pick.set_item_metadata(_start_pick.item_count - 1, s["id"])
		if s["id"] == cur:
			_start_pick.select(_start_pick.item_count - 1)
	if cur == "":
		_start_pick.add_item("（%s）" % String(model.load_project().get("entry", "未設定")))
		_start_pick.set_item_metadata(_start_pick.item_count - 1, "")
		_start_pick.select(_start_pick.item_count - 1)


func _on_start_picked(i: int) -> void:
	var id := String(_start_pick.get_item_metadata(i))
	if id == "":
		return
	if _dirty:
		save()
	if model.set_start_scenario(id) == OK:
		_set_status("開始シナリオ：%s（%s から始めます）" % [_start_pick.get_item_text(i), model.load_project().get("entry", "")])
		_fill_list()
	else:
		_set_status("、".join(model.errors))
	_update_undo_buttons()


# ---------------------------------------------------------------- 並べ替え・範囲

func _on_reordered(ids: Array) -> void:
	if _dirty:
		save()
	match page:
		Page.GAME:
			model.set_order("scenario", ids)
		Page.SCENARIO:
			if model.scenario(sid).get("loose", false):
				_set_status("フォルダの外のファイルは並べ替えられません")
				return
			model.set_order("chapter", ids, sid)
		Page.CHAPTER:
			model.set_order("scene", ids, sid, cid)
	_fill_list()
	_set_status("並べ替えました")
	_update_undo_buttons()


func _open_region_editor() -> void:
	var cur: Dictionary = merge_steps(_scene_form.data if _scene_form.data is Dictionary else {}, _load_scene())
	var targets := []
	for group in [["objects", "もの"], ["exits", "出口"]]:
		var g = cur.get(group[0], {})
		if not g is Dictionary:
			continue
		for id in g:
			var o = g[id]
			var label := String(o.get("label", id)) if o is Dictionary else String(id)
			targets.append({"key": "%s/%s" % [group[0], id], "label": "%s：%s" % [group[1], label],
				"region": o.get("region") if o is Dictionary else null})
	if targets.is_empty():
		_set_status("もの・出口がありません（コマンドエディタの「＋ もの」「＋ 出口」か、左の設定で足してください）")
		return
	var tex := AdvScenarioModel.load_texture(model.image_path(AdvScenarioModel.image_id_of(cur.get("image"))))
	region_editor.open(tex, targets, func(regions: Dictionary):
		var v: Dictionary = _scene_form.data if _scene_form.data is Dictionary else {}
		for key in regions:
			var group := String(key).get_slice("/", 0)
			var id := String(key).get_slice("/", 1)
			var g: Dictionary = v.get(group, {})
			var o = g.get(id, {})
			if not o is Dictionary:
				o = {}
			if regions[key] == null:
				o.erase("region")
			else:
				o["region"] = regions[key]
			g[id] = o
			v[group] = g
		_scene_form.setup(scene_schema(), v)
		_dirty = true
		save())


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
	_update_undo_buttons()


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
			_settings_data = model.load_project()
			_list_title.text = "シナリオ（%s）" % model.root
			var start_s := model.start_scenario()
			for s in model.scenarios():
				var chs := model.chapters(s["id"])
				var thumb_img = null
				if not chs.is_empty():
					var scs := model.scenes(s["id"], chs[0]["id"])
					thumb_img = scs[0].get("image") if not scs.is_empty() else null
				items.append({"id": s["id"], "name": ("▶ " if s["id"] == start_s else "") + String(s["name"]),
					"sub": "%s ・ チャプター %d" % [s["id"], chs.size()], "image": _thumb(thumb_img)})
			_fill_start_pick()
			_settings_note.text = "ゲーム全体の設定（%s）。シナリオの一覧はシナリオエディタが書きます。" % model.project_path
		Page.SCENARIO:
			_settings_data = model.load_scenario_data(sid)
			_list_title.text = "チャプター"
			for c in model.chapters(sid):
				var scs := model.scenes(sid, c["id"])
				items.append({"id": c["id"], "name": c["name"], "sub": "%s ・ シーン %d" % [c["id"], c["scenes"]],
					"image": _thumb(scs[0].get("image") if not scs.is_empty() else null)})
			if model.scenario(sid).get("loose", false):
				_settings_note.text = "フォルダに分けていないファイルです。設定は、それぞれのチャプターで書いてください。"
			else:
				_settings_note.text = "このシナリオの全チャプターで使う設定（%s）。" % AdvScenarioModel.MAIN_FILE
		Page.CHAPTER:
			_settings_data = model.load_chapter_data(sid, cid)
			_list_title.text = "シーン"
			for s in model.scenes(sid, cid):
				var kind := String(KIND_NAMES.get(String(s.get("kind", "")), ""))
				items.append({"id": s["id"], "name": s["name"], "sub": "%s%s%s" % [s["id"], "" if kind == "" else " ・ " + kind,
					"" if s.get("image") == null else " ・ " + AdvScenarioModel.image_id_of(s["image"])],
					"image": _thumb(s.get("image"))})
			_settings_note.text = "このチャプターの設定（%s）。" % model.chapter_path(sid, cid).get_file()
			tabs = tabs.map(func(t): return [t[0], (t[1] as Array).filter(func(k): return k != "start")])
	_build_tabs(AdvSchemaValidator.load_schema(schema_name), tabs, hidden, _settings_data)
	_tabs.visible = not (page == Page.SCENARIO and model.scenario(sid).get("loose", false))
	_start_row.visible = page == Page.GAME
	_grid.reorderable = not (page == Page.SCENARIO and model.scenario(sid).get("loose", false))
	_grid.set_items(items)


var _thumb_cache: Dictionary = {}


## シーンの背景（image の値）の小さな絵。なければ null。
func _thumb(image: Variant) -> Variant:
	var id := AdvScenarioModel.image_id_of(image)
	if id == "":
		return null
	if not _thumb_cache.has(id):
		_thumb_cache[id] = AdvScenarioModel.load_texture(model.image_path(id))
	return _thumb_cache[id]


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
		f.preview = form_preview
		f.audio_kind = form_audio_kind
		f.check = form_check
		f.play_requested.connect(play_audio)
		f.expr_mode = _expr_mode_of
		f.expr_requested.connect(_on_form_expr.bind(f))
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
	if _dirty:
		save()
	var level := _level()
	var default_name: String = {"scenario": "新しいシナリオ", "chapter": "新しいチャプター", "scene": "新しいシーン"}.get(level, "")
	ask_new(level, default_name, func(name: String, new_id: String): create_item(name, new_id))


## 名前と ID を決めて、いまの一覧に作る（ask_new の続き。テストからも呼ぶ）。
func create_item(name: String, new_id: String) -> String:
	var id := ""
	match page:
		Page.GAME:
			id = model.create_scenario(name, new_id)
		Page.SCENARIO:
			id = model.create_chapter(sid, name, new_id)
		Page.CHAPTER:
			id = model.create_scene(sid, cid, name, new_id)
	if id == "":
		_set_status("作れませんでした")
		return ""
	_fill_list()
	_grid.select_only(id)
	_set_status("作りました：%s（%s）" % [name, id])
	_refresh_expr_candidates()
	_update_undo_buttons()
	return id


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
	_update_undo_buttons()


func _on_card_menu(ids: Array, at: Vector2) -> void:
	_menu_ids = ids
	_menu.clear()
	var one := ids.size() == 1
	_menu.add_item("開く", MENU_OPEN)
	_menu.set_item_disabled(_menu.get_item_index(MENU_OPEN), not one)
	_menu.add_item("名前を変更", MENU_RENAME)
	_menu.set_item_disabled(_menu.get_item_index(MENU_RENAME), not one)
	_menu.add_item("ID を変更…", MENU_CHANGE_ID)
	_menu.set_item_disabled(_menu.get_item_index(MENU_CHANGE_ID), not one or (page == Page.GAME and ids[0] == AdvScenarioModel.LOOSE_ID))
	_menu.add_item("新規作成", MENU_NEW)
	if page == Page.SCENARIO and model.scenario(sid).get("loose", false):
		_menu.add_item("シナリオのフォルダの形に移す…", MENU_MIGRATE)
		_menu.set_item_disabled(_menu.get_item_index(MENU_MIGRATE), not one)
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
		MENU_CHANGE_ID:
			_ask_change_id(String(_menu_ids[0]))
		MENU_MIGRATE:
			_ask_migrate(String(_menu_ids[0]))


func _ask_change_id(old: String) -> void:
	_ask("新しい ID（%s。参照している手順も書き換えます）" % old, old, func(t: String): change_id(old, t))


## ID を変える（テストからも呼ぶ）。
func change_id(old: String, new_id: String) -> Error:
	if _dirty:
		save()
	var ids := []
	match page:
		Page.GAME:
			ids = [old]
		Page.SCENARIO:
			ids = [sid, old]
		Page.CHAPTER:
			ids = [sid, cid, old]
	var err := model.change_id(_level(), ids, new_id)
	_set_status("ID を変えました：%s → %s" % [old, new_id] if err == OK else "、".join(model.errors))
	_thumb_cache.clear()
	_fill_list()
	_refresh_expr_candidates()
	_update_undo_buttons()
	return err


func _ask_migrate(chapter_id: String) -> void:
	var path := model.chapter_path(sid, chapter_id)
	ask_new("scenario", chapter_id, func(name: String, new_id: String): migrate(path, new_id, name))


## 古い形のファイルを、シナリオのフォルダの形に移す（テストからも呼ぶ）。
func migrate(path: String, new_id: String, name: String) -> Error:
	var err := model.migrate_loose(path, new_id, name)
	_set_status("移しました：%s → %s/" % [path.get_file(), new_id] if err == OK else "、".join(model.errors))
	if err == OK:
		sid = new_id
		_show(Page.SCENARIO)
	_update_undo_buttons()
	return err


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
	_fill_preset_pick()
	_scene_form.setup(scene_schema(), AdvSchemaForm.normalize(strip_steps(_scene_data)))
	_scene_form.suggest = _suggest
	_scene_form.preview = form_preview
	_scene_form.audio_kind = form_audio_kind
	_scene_form.check = form_check
	_scene_form.play_requested.connect(play_audio)
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
	if _dirty:
		save()
	var ink := _dlg_kind.selected == 1
	ask_new("dialogue", "", func(_name: String, id: String): create_dialogue(id, ink), false)


## セリフを作って開く（テストからも呼ぶ）。
func create_dialogue(id: String, ink: bool) -> Error:
	if ink:
		var s := model.scenario(sid)
		if s.get("loose", true):
			_set_status("Ink のセリフは、フォルダに分けたシナリオで作れます")
			return ERR_UNAVAILABLE
		var path := String(s["dir"]) + "/ink/" + id + ".ink"
		if FileAccess.file_exists(path):
			_set_status("もうあります：%s" % path)
			return ERR_ALREADY_EXISTS
		model.begin("Ink のセリフの作成（%s）" % id)
		model.write_text(path, "=== %s ===\nここに セリフを かきます。\n-> DONE\n" % id)
		model.end()
		_open_dialogue({"kind": "ink", "id": id, "path": path})
	else:
		var d := model.load_chapter_data(sid, cid)
		var dl: Dictionary = d.get("dialogues", {})
		if dl.has(id) or model.all_dialogue_ids().has(id):
			_set_status("その会話IDは、もう使われています：%s" % id)
			return ERR_ALREADY_EXISTS
		dl[id] = []
		d["dialogues"] = dl
		model.begin("セリフの作成（%s）" % id)
		model.save_chapter_data(sid, cid, d)
		model.end()
		_refresh_expr_candidates()
		_open_dialogue({"kind": "json", "id": id})
	return OK


func _on_delete_dialogue() -> void:
	var sel := _dlg_list.get_selected_items()
	if sel.is_empty():
		return
	var m: Dictionary = _dlg_list.get_item_metadata(sel[0])
	model.begin("セリフの削除（%s）" % m["id"])
	if m["kind"] == "json":
		var d := model.load_chapter_data(sid, cid)
		d.get("dialogues", {}).erase(m["id"])
		model.save_chapter_data(sid, cid, d)
	else:
		model.remove_path(String(m["path"]))
		if FileAccess.file_exists(String(m["path"]) + ".json"):
			model.remove_path(String(m["path"]) + ".json")
		model.sync_project()
	model.end()
	_update_undo_buttons()
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
	_update_undo_buttons()


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
		var err := model.write_text(String(dlg["path"]), _ink_code.text)
		_dlg_msg.text = "保存しました（ゲームで使うには「Ink をコンパイル」）" if err == OK else "保存できません"
		return err
	var d := model.load_chapter_data(sid, cid)
	var old := String(dlg["id"])
	var id := _dlg_id.text.strip_edges()
	var dl: Dictionary = d.get("dialogues", {})
	dl[old] = _dlg_steps.get_steps()
	d["dialogues"] = dl
	model.begin("セリフの保存（%s）" % old)
	var err := model.save_chapter_data(sid, cid, d)
	# 会話ID を変えたら、呼んでいる手順（call、talked など）もまとめて書き換える
	if err == OK and id != "" and id != old:
		if model.change_id("dialogue", [sid, cid, old], id) == OK:
			dlg["id"] = id
			_refresh_expr_candidates()
			_set_status("会話IDを変えました：%s → %s" % [old, id])
		else:
			_set_status("、".join(model.errors))
			_dlg_id.text = old
	model.end()
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
	for v in model.load_project().get("verbs", []):
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
	if page == Page.ROOT or (page == Page.SCENARIO and model.scenario(sid).get("loose", false)):
		return
	var err := OK
	model.begin("%sの保存" % {Page.GAME: "ゲームの設定", Page.SCENARIO: "シナリオの設定", Page.CHAPTER: "チャプターの設定",
		Page.SCENE: "シーン", Page.DIALOGUE: "セリフ", Page.COMMAND: "コマンド"}.get(page, ""))
	match page:
		Page.GAME:
			err = model.save_project(_merge_tabs(model.load_project()))
		Page.SCENARIO:
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
	model.end()
	_dirty = false
	_update_undo_buttons()
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
	var keys := path.filter(func(p): return p is String)
	var kind := asset_kind_of(keys)
	if kind != "":
		return Array(model.asset_ids(kind))
	if keys in [["opening"], ["next"], ["fin", "then"]] or (keys.size() == 2 and keys[0] == "system_scenes"):
		return model.all_scene_ids().keys()
	return []


var _audio: AudioStreamPlayer
var playing_audio: String = ""   ## 試しに鳴らしている音（"種類:ID"。止まっていれば ""）


# ---------------------------------------------------------------- 全体の ID の確認

var check_toggle: Button
var auto_reload_toggle: CheckButton
var check_panel: VBoxContainer
var check_list: ItemList
var _check_label: Label
var check_results: Array = []
var fix_pick: OptionButton
var fix_confirm: ConfirmationDialog
var export_dialog: FileDialog
var check_kind_pick: OptionButton
var check_file_pick: OptionButton
var check_view: Array = []        ## 一覧の行 → check_results の番号（絞り込んだあと）
var _pending_fix: Array = []
var _pending_fix_id: String = ""


## 選んだ行の種類の候補を、直す ID の一覧に入れる。
func _fill_fix_choices() -> void:
	fix_pick.clear()
	var sel := check_list.get_selected_items()
	if sel.is_empty():
		return
	var kind := String(check_results[check_view[sel[0]]].get("kind", ""))
	for id in id_candidates(kind):
		fix_pick.add_item(String(id))


## 選んだ行の ID を、直す ID の一覧で選んだものに書き換える。same_id なら、同じ種類・同じ ID の行すべて
## （絞り込みにかかわらず）。まとめて直すときは、書き換える場所を出して確かめてから直す（confirm が false なら確かめない）。
## 書き換える（書き換える予定の）数を返す。
func fix_selected(same_id: bool, confirm: bool = true) -> int:
	var sel := check_list.get_selected_items()
	if sel.is_empty() or fix_pick.selected < 0:
		_set_status("直す行と、直す ID を選んでください")
		return 0
	var new_id := fix_pick.get_item_text(fix_pick.selected)
	var targets := []
	for i in sel:
		targets.append(check_results[check_view[i]])
	if same_id:
		var keys := {}
		for r in targets:
			keys["%s:%s" % [r["kind"], r["id"]]] = true
		targets = check_results.filter(func(r): return keys.has("%s:%s" % [r["kind"], r["id"]]))
		if confirm:
			_pending_fix = targets
			_pending_fix_id = new_id
			var lines := PackedStringArray()
			for r in targets.slice(0, 12):
				lines.append("・%s → %s　%s（%s）" % [r["id"], new_id, r["where"], String(r["file"]).get_file()])
			if targets.size() > 12:
				lines.append("…ほか %d か所" % (targets.size() - 12))
			fix_confirm.dialog_text = "%d か所を書き換えます。\n\n%s" % [targets.size(), "\n".join(lines)]
			fix_confirm.popup_centered()
			return targets.size()
	return _do_fix(targets, new_id)


func _do_fix(targets: Array, new_id: String) -> int:
	var n := apply_fixes(targets, new_id)
	_set_status("%d か所を %s に直しました" % [n, new_id])
	refresh_check()
	_show(page)
	return n


## 確認の結果の場所の ID を new_id に書き換える（ファイルごとにまとめて書く。元に戻せる）。直した数を返す。
func apply_fixes(targets: Array, new_id: String) -> int:
	var by_file := {}
	for r in targets:
		if not by_file.has(r["file"]):
			by_file[r["file"]] = []
		by_file[r["file"]].append(r)
	var n := 0
	model.begin("ID を直す")
	for f in by_file:
		var list: Array = by_file[f]
		if String(f).ends_with(".ink"):
			var lines := FileAccess.get_file_as_string(f).split("\n")
			for r in list:
				var li := int(r["line"])
				if li >= 0 and li < lines.size():
					var before: String = lines[li]
					lines[li] = _replace_ink_ref(before, String(r["id"]), new_id)
					n += 1 if lines[li] != before else 0
			model.write_text(f, "\n".join(lines))
		else:
			var data = model.load_project() if f == model.project_path else AdvScenarioModel._load(String(f))
			for r in list:
				if _set_in(data, r["fix_path"], new_id):
					n += 1
			model.write_json(f, data)
	model.end()
	_thumb_cache.clear()
	return n


## Ink の行の中の、ID の書いてあるところ（tag:ID、"ID"）だけを書き換える。
static func _replace_ink_ref(line: String, old: String, new_id: String) -> String:
	var re := RegEx.create_from_string("(:\\s*|\")" + _re_escape(old) + "(?=\\s|\"|#|$)")
	return re.sub(line, "$1" + new_id, true)


static func _re_escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in ".^$*+?()[]{}|\\" else c
	return out


static func _set_in(data: Variant, path: Array, value: Variant) -> bool:
	var cur = data
	for i in path.size() - 1:
		var k = path[i]
		if (cur is Dictionary and cur.has(k)) or (cur is Array and k is int and k < cur.size()):
			cur = cur[k]
		else:
			return false
	var last = path[path.size() - 1]
	if cur is Dictionary or (cur is Array and last is int and last < cur.size()):
		cur[last] = value
		return true
	return false


func _build_check_panel() -> void:
	check_panel = VBoxContainer.new()
	check_panel.name = "CheckPanel"
	check_panel.visible = false
	check_panel.custom_minimum_size = Vector2(0, 160)
	add_child(check_panel)
	var bar := HBoxContainer.new()
	check_panel.add_child(bar)
	_check_label = Label.new()
	_check_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_check_label)
	var kl := Label.new()
	kl.text = "種類："
	bar.add_child(kl)
	check_kind_pick = OptionButton.new()
	check_kind_pick.item_selected.connect(func(_i): _fill_check_list())
	bar.add_child(check_kind_pick)
	var fl2 := Label.new()
	fl2.text = "ファイル："
	bar.add_child(fl2)
	check_file_pick = OptionButton.new()
	check_file_pick.custom_minimum_size = Vector2(160, 0)
	check_file_pick.item_selected.connect(func(_i): _fill_check_list())
	bar.add_child(check_file_pick)
	var export_b := Button.new()
	export_b.text = "書き出す…"
	export_b.tooltip_text = "いま出している一覧を、CSV かテキストのファイルに書き出します"
	export_b.pressed.connect(func(): export_dialog.popup_centered_ratio(0.6))
	bar.add_child(export_b)
	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.title = "ID の確認の結果を書き出す"
	export_dialog.filters = PackedStringArray(["*.csv ; CSV", "*.txt ; テキスト"])
	export_dialog.current_file = "id_check.csv"
	export_dialog.file_selected.connect(func(p: String):
		var err := export_check(p)
		_set_status("書き出しました：%s" % p if err == OK else "書き出せませんでした：%s" % p))
	add_child(export_dialog)
	var again := Button.new()
	again.text = "もう一度確かめる"
	again.pressed.connect(refresh_check)
	bar.add_child(again)
	var hide_b := Button.new()
	hide_b.text = "隠す"
	hide_b.pressed.connect(func(): check_toggle.button_pressed = false)
	bar.add_child(hide_b)
	check_list = ItemList.new()
	check_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	check_list.select_mode = ItemList.SELECT_MULTI
	check_list.tooltip_text = "ダブルクリックで、そのシーンを開きます"
	check_list.item_activated.connect(open_check_result)
	check_list.multi_selected.connect(func(_i, _s): _fill_fix_choices())
	check_list.item_selected.connect(func(_i): _fill_fix_choices())
	check_panel.add_child(check_list)
	var fix := HBoxContainer.new()
	check_panel.add_child(fix)
	var fl := Label.new()
	fl.text = "直す ID："
	fix.add_child(fl)
	fix_pick = OptionButton.new()
	fix_pick.custom_minimum_size = Vector2(200, 0)
	fix_pick.tooltip_text = "選んだ行と同じ種類の ID の候補"
	fix.add_child(fix_pick)
	var fix_one := Button.new()
	fix_one.text = "選んだ行を直す"
	fix_one.pressed.connect(func(): fix_selected(false))
	fix.add_child(fix_one)
	var fix_all := Button.new()
	fix_all.text = "同じ ID をまとめて直す"
	fix_all.tooltip_text = "選んだ行と同じ種類・同じ ID のものを、すべて直します"
	fix_all.pressed.connect(func(): fix_selected(true))
	fix.add_child(fix_all)
	fix_confirm = ConfirmationDialog.new()
	fix_confirm.title = "ID をまとめて直す"
	fix_confirm.ok_button_text = "書き換える"
	fix_confirm.cancel_button_text = "やめる"
	fix_confirm.confirmed.connect(func(): _do_fix(_pending_fix, _pending_fix_id))
	add_child(fix_confirm)


## プロジェクト設定 debug.auto_reload を書く（元に戻せる）。
func set_auto_reload_setting(on: bool) -> void:
	var p := model.load_project()
	var d = p.get("debug", {})
	if not d is Dictionary:
		d = {}
	if bool(d.get("auto_reload", false)) == on:
		return
	d["auto_reload"] = on
	p["debug"] = d
	model.begin("保存で読み直す：%s" % ("入" if on else "切"))
	model.write_json(model.project_path, p)
	model.end()
	_set_status("保存したら読み直す：%s（デバッグ実行中のゲーム）" % ("入" if on else "切"))
	_update_undo_buttons()


func _sync_auto_reload_toggle() -> void:
	if auto_reload_toggle == null:
		return
	var d = model.load_project().get("debug", {})
	auto_reload_toggle.set_pressed_no_signal(d is Dictionary and bool(d.get("auto_reload", false)))


## ID の確認の一覧を出す・隠す。出すときは確かめ直す。
func show_check_panel(on: bool) -> void:
	if check_toggle.button_pressed != on:
		check_toggle.set_pressed_no_signal(on)
	check_panel.visible = on
	if on:
		refresh_check()


func refresh_check() -> void:
	check_results = scan_missing_ids()
	# 絞り込みの候補（いま選んでいるものは残す）
	var cur_kind := _pick_meta(check_kind_pick)
	var cur_file := _pick_meta(check_file_pick)
	check_kind_pick.clear()
	check_kind_pick.add_item("すべて")
	check_kind_pick.set_item_metadata(0, "")
	var kinds := []
	for r in check_results:
		if not String(r["kind"]) in kinds:
			kinds.append(String(r["kind"]))
	for k in kinds:
		check_kind_pick.add_item(String(ID_KIND_NAMES.get(k, k)))
		check_kind_pick.set_item_metadata(check_kind_pick.item_count - 1, k)
	check_file_pick.clear()
	check_file_pick.add_item("すべて")
	check_file_pick.set_item_metadata(0, "")
	var files := []
	for r in check_results:
		if not String(r["file"]) in files:
			files.append(String(r["file"]))
	for f in files:
		check_file_pick.add_item(String(f).get_file())
		check_file_pick.set_item_metadata(check_file_pick.item_count - 1, f)
	_select_meta(check_kind_pick, cur_kind)
	_select_meta(check_file_pick, cur_file)
	_fill_check_list()


## 絞り込みに合う結果だけを一覧に出す。
func _fill_check_list() -> void:
	var kind := _pick_meta(check_kind_pick)
	var file := _pick_meta(check_file_pick)
	check_list.clear()
	check_view = []
	for i in check_results.size():
		var r: Dictionary = check_results[i]
		if (kind != "" and r["kind"] != kind) or (file != "" and r["file"] != file):
			continue
		check_view.append(i)
		check_list.add_item("%s　%s　（%s）" % [r["message"], r["where"], String(r["file"]).get_file()])
		check_list.set_item_custom_fg_color(check_list.item_count - 1, AdvSchemaForm.WARN_COLOR)
	if check_results.is_empty():
		_check_label.text = "見つからない ID はありません"
	elif check_view.size() == check_results.size():
		_check_label.text = "見つからない ID：%d 件" % check_results.size()
	else:
		_check_label.text = "見つからない ID：%d 件（全部で %d 件）" % [check_view.size(), check_results.size()]
	fix_pick.clear()


## いま出している一覧（絞り込んだもの）をファイルに書き出す。拡張子が .csv なら CSV（UTF-8、BOM つき）、それ以外はテキスト。
func export_check(path: String) -> Error:
	var csv := path.get_extension().to_lower() == "csv"
	var lines := PackedStringArray()
	if csv:
		lines.append("種類,ID,内容,場所,ファイル")
	for i in check_view:
		var r: Dictionary = check_results[i]
		var kind_name := String(ID_KIND_NAMES.get(String(r["kind"]), r["kind"]))
		if csv:
			lines.append(",".join([kind_name, String(r["id"]), String(r["message"]), String(r["where"]), String(r["file"])].map(_csv_cell)))
		else:
			lines.append("%s\t%s\t%s" % [r["message"], r["where"], r["file"]])
	if not csv:
		lines.insert(0, "見つからない ID：%d 件" % check_view.size())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if csv:
		f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return OK


static func _csv_cell(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


## 絞り込みを選ぶ（テストからも呼ぶ）。kind・file は "" ならすべて。
func set_check_filter(kind: String, file: String) -> void:
	_select_meta(check_kind_pick, kind)
	_select_meta(check_file_pick, file)
	_fill_check_list()


static func _pick_meta(ob: OptionButton) -> String:
	return String(ob.get_item_metadata(ob.selected)) if ob.selected >= 0 and ob.item_count > 0 else ""


static func _select_meta(ob: OptionButton, v: String) -> void:
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == v:
			ob.select(i)
			return
	if ob.item_count > 0:
		ob.select(0)


## 一覧の i 番目を開く（シーンの中なら、そのシーンの画面へ）。
func open_check_result(i: int) -> void:
	if i < 0 or i >= check_view.size():
		return
	var r: Dictionary = check_results[check_view[i]]
	var sc := String(r.get("scene", ""))
	if sc == "":
		_set_status("%s（%s）" % [r["where"], String(r["file"]).get_file()])
		return
	open_scene_by_id(sc)


## プロジェクト設定とシナリオのファイルすべてで、見つからない ID を探す。
## [{file, where（項目の道筋）, message, scene?（シーンの中なら、そのID）}]
func scan_missing_ids() -> Array:
	_cand_cache = {}
	var items := []
	for s in model.scenarios():
		for k in model.load_scenario_data(s["id"]).get("items", {}):
			if not k in items:
				items.append(k)
	_cand_cache["item"] = items
	var out := []
	_scan_value(model.load_project(), [], [], model.project_path, "", out)
	for f in model.all_files():
		var d := AdvScenarioModel._load(String(f))
		if d.has("scene"):
			# シーン1つのファイル
			var body := d.duplicate()
			_scan_value(body, [], [], String(f), String(d["scene"]), out)
		else:
			for k in d:
				if k == "scenes" and d[k] is Dictionary:
					for scid in d[k]:
						_scan_value(d[k][scid], [], ["scenes", scid], String(f), String(scid), out)
				else:
					_scan_value(d[k], [k], [], String(f), "", out)
	for f in all_ink_sources():
		_scan_ink(f, out)
	_cand_cache = null
	return out


## すべてのシナリオの Ink のソース（シナリオのフォルダの ink/*.ink）。
func all_ink_sources() -> Array:
	var out := []
	for s in model.scenarios():
		var dir := String(s.get("dir", "")) + "/ink"
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".ink"):
				out.append(dir + "/" + f)
	out.sort()
	return out


const INK_TAG_KINDS := {"bg": "image", "bgm": "bgm", "se": "se", "voice": "voice"}


## Ink のソースの行を確かめる：タグ（# bg:ID など）、JSON のタグ（# {"image.show": {…}}）、call_scene・goto_scene の行き先。
func _scan_ink(file: String, out: Array) -> void:
	var lines := FileAccess.get_file_as_string(file).split("\n")
	var call_re := RegEx.create_from_string("(call_scene|goto_scene)\\(\\s*\"([^\"]+)\"")
	for li in lines.size():
		var line: String = lines[li]
		var where := "%d 行目" % (li + 1)
		for m in call_re.search_all(line):
			_ink_found(file, li, where, "scene", m.get_string(2), out)
		var hp := line.find("#")
		if hp < 0 or line.strip_edges().begins_with("//"):
			continue
		for tag in line.substr(hp).split("#", false):
			var t := String(tag).strip_edges()
			if t.begins_with("{"):
				var j := JSON.new()
				if j.parse(t) == OK and j.data is Dictionary and j.data.size() == 1:
					var ev := String(j.data.keys()[0])
					if j.data[ev] is Dictionary:
						for k in j.data[ev]:
							var kind := AdvStepEditor.arg_id_kind(ev, [k])
							if kind != "" and j.data[ev][k] is String:
								_ink_found(file, li, where, kind, String(j.data[ev][k]), out)
				continue
			var kv := t.split(":", true, 1)
			if kv.size() == 2 and INK_TAG_KINDS.has(kv[0].strip_edges()):
				_ink_found(file, li, where, INK_TAG_KINDS[kv[0].strip_edges()], kv[1].strip_edges(), out)


func _ink_found(file: String, li: int, where: String, kind: String, id: String, out: Array) -> void:
	if id == "" or id.contains(" ") or id.contains("{"):
		return
	var msg := missing_message(kind, id, id_candidates(kind))
	if msg != "":
		out.append({"file": file, "where": where, "message": msg, "scene": "", "kind": kind, "id": id, "line": li})


## form_check が使った ID の種類（素材かシーン）。
func _kind_of_check(path: Array) -> String:
	var keys := path.filter(func(p): return p is String)
	var k := asset_kind_of(keys)
	return k if k != "" else "scene"


## 値をたどって確かめる。path は確かめに使う道筋（シーンの中ならシーンからの道筋）、prefix は表示に足す前の部分。
func _scan_value(v: Variant, path: Array, prefix: Array, file: String, scene: String, out: Array) -> void:
	if v is Dictionary:
		# 手順の出力イベント（{"image.show": {...}}）は、そのイベントの引数として確かめる
		if v.size() == 1:
			var ev := String(v.keys()[0])
			if ev.contains(".") and v[ev] is Dictionary and AdvStepEditor.ARG_ID_KINDS.has(ev):
				_scan_event(ev, v[ev], [], path, prefix, file, scene, out)
				return
		for k in v:
			_scan_value(v[k], path + [k], prefix, file, scene, out)
	elif v is Array:
		for i in v.size():
			_scan_value(v[i], path + [i], prefix, file, scene, out)
	elif v is String:
		var msg := form_check(path, v)
		if msg != "":
			out.append({"file": file, "where": _where(prefix + path), "message": msg, "scene": scene,
				"kind": _kind_of_check(path), "id": v, "fix_path": prefix + path})


func _scan_event(ev: String, args: Dictionary, sub: Array, path: Array, prefix: Array, file: String, scene: String, out: Array) -> void:
	for k in args:
		var v = args[k]
		if v is Dictionary or v is Array:
			var items: Array = v.values() if v is Dictionary else v
			for i in items.size():
				var key = v.keys()[i] if v is Dictionary else i
				if items[i] is Dictionary:
					_scan_event(ev, items[i], sub + [k, key], path, prefix, file, scene, out)
				elif items[i] is String:
					_check_event_value(ev, sub + [k, key], items[i], path, prefix, file, scene, out)
		elif v is String:
			_check_event_value(ev, sub + [k], v, path, prefix, file, scene, out)


func _check_event_value(ev: String, sub: Array, value: String, path: Array, prefix: Array, file: String, scene: String, out: Array) -> void:
	var kind := AdvStepEditor.arg_id_kind(ev, sub)
	if kind == "" or (kind == "scene" and value in ["title", "new", "quit", "stay"]):
		return
	var msg := missing_message(kind, value, id_candidates(kind))
	if msg != "":
		out.append({"file": file, "where": _where(prefix + path + [ev] + sub), "message": msg, "scene": scene,
			"kind": kind, "id": value, "fix_path": prefix + path + [ev] + sub})


static func _where(path: Array) -> String:
	return ".".join(path.map(func(p): return "[%d]" % p if p is int else String(p))).replace(".[", "[")


## ID の種類の名前（注意の文に使う）
const ID_KIND_NAMES := {"image": "画像", "bgm": "曲", "se": "効果音", "voice": "ボイス", "video": "動画", "scene": "シーン", "item": "持ち物"}


## ID が一覧になければ注意の文（あれば ""）。画像の「ID@違い」は ID だけで確かめる。
static func missing_message(kind: String, id: String, known: Array) -> String:
	if id == "" or kind == "":
		return ""
	var base := id.get_slice("@", 0) if kind == "image" else id
	if base in known:
		return ""
	return "%sが見つかりません：%s" % [ID_KIND_NAMES.get(kind, kind), id]


## フォームの値を確かめる：素材・シーンの ID が見つからなければ注意の文。
func form_check(path: Array, value: Variant) -> String:
	if not value is String or value == "":
		return ""
	var keys := path.filter(func(p): return p is String)
	var kind := asset_kind_of(keys)
	if kind == "" and (keys in [["start"], ["entry"], ["opening"], ["next"], ["fin", "then"]] or (keys.size() == 2 and keys[0] in ["system_scenes", "exits"])):
		if keys == ["fin", "then"] and value in ["title", "new", "quit", "stay"]:
			return ""
		if keys.size() == 2 and keys[0] == "system_scenes" and String(value).ends_with(".tscn"):
			return ""
		kind = "scene"
	return missing_message(kind, String(value), id_candidates(kind)) if kind != "" else ""


## 音の ID の項目の種類（bgm・se・voice。音でなければ ""）。
func form_audio_kind(path: Array) -> String:
	var k := asset_kind_of(path.filter(func(p): return p is String))
	return k if k in ["bgm", "se", "voice"] else ""


## 音を試しに鳴らす。同じ音を鳴らしている間にもう一度呼ぶと止める。
func play_audio(kind: String, id: String) -> void:
	if _audio == null:
		_audio = AudioStreamPlayer.new()
		_audio.name = "Preview"
		add_child(_audio)
		_audio.finished.connect(func(): playing_audio = "")
	var key := "%s:%s" % [kind, id]
	if playing_audio == key:
		_audio.stop()
		playing_audio = ""
		_set_status("止めました")
		return
	var path := model.asset_path(kind, id)
	var s := AdvAudio.load_stream(path, false, 0.0) if path != "" else null
	if s == null:
		_set_status("鳴らせません：%s（%s）" % [id, kind])
		playing_audio = ""
		return
	_audio.stop()
	_audio.stream = s
	_audio.play()
	playing_audio = key
	_set_status("鳴らしています：%s（もう一度押すと止めます）" % id)


## フォームの見本の絵：画像の ID の項目なら、その絵。
func form_preview(path: Array, value: Variant) -> Variant:
	if not value is String or value == "":
		return null
	if asset_kind_of(path.filter(func(p): return p is String)) != "image":
		return null
	return _thumb(value)


## 手順のエディタの ID の候補（kind は image・bgm・se・voice・video・scene・item）。
func id_candidates(kind: String) -> Array:
	if _cand_cache != null and _cand_cache.has(kind):
		return _cand_cache[kind]
	var out := _id_candidates(kind)
	if _cand_cache != null:
		_cand_cache[kind] = out
	return out


var _cand_cache = null   ## 全体の確認の間だけ、候補を取っておく


func _id_candidates(kind: String) -> Array:
	match kind:
		"scene":
			return model.all_scene_ids().keys()
		"item":
			return model.load_scenario_data(sid).get("items", {}).keys() if sid != "" else []
		_:
			return Array(model.asset_ids(kind))


## 項目の道筋（キーだけ）から、素材の種類（image・bgm）を決める。素材でなければ ""。
static func asset_kind_of(keys: Array) -> String:
	return AdvIdCheck.asset_kind_of(keys)


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
