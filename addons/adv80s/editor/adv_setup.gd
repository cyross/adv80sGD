@tool
class_name AdvSetup
extends RefCounted
## 新しいゲームの初期設定（セットアップ画面の中身。6.7）。
## ゲームID、タイトル、画面テンプレート、コマンド方式、入力機器を決めて、
## プロジェクト設定（adv80s.project.json）、素材フォルダ、最初のシナリオ、メインシーン（エントリポイント）を作る。
## すでにあるファイルは上書きしない（プロジェクト設定だけは、セットアップの項目を書き換える）。

const DEVICES := ["keyboard", "mouse", "gamepad", "touch"]
const DEVICE_LABELS := {"keyboard": "キーボード", "mouse": "マウス", "gamepad": "ゲームパッド", "touch": "タッチ"}
const ASSET_DIRS := ["bg", "chara", "sprite", "ui", "bgm", "se", "voice", "font", "movie"]

## コマンド方式（inputs.enabled に書く値）。needs はどれか1つが必要な入力機器。
const COMMAND_STYLES := [
	{"id": "template", "label": "テンプレートのまま", "enabled": [], "needs": [],
		"note": "画面テンプレートが決めている方式をそのまま使います。"},
	{"id": "select", "label": "コマンド選択（動詞 → 対象を一覧から選ぶ）", "enabled": ["select"], "needs": [],
		"note": "日本のアドベンチャーゲームで一般的な方式です。どの入力機器でも遊べます。"},
	{"id": "parser", "label": "コマンド入力（文字で入力する）", "enabled": ["parser"], "needs": ["keyboard"],
		"note": "「ドアを あける」のように文字で入力します。入力欄のあるテンプレートが必要です。"},
	{"id": "select_parser", "label": "コマンド選択 ＋ コマンド入力", "enabled": ["select", "parser"], "needs": [],
		"note": "一覧から選ぶことも、文字で入力することもできます。"},
	{"id": "verb_click", "label": "動詞リスト ＋ クリック（動詞を選んでから絵の中の対象をクリック）", "enabled": ["verb_click"], "needs": ["mouse", "touch", "keyboard", "gamepad"],
		"note": "動詞と持ち物を出したままにし、動詞 → 絵の中の対象の順に選びます。海外のポイント＆クリック型で多い方式です。"},
	{"id": "verb_cursor", "label": "アイコン切り替え（カーソルの動詞を切り替えて対象をクリック）", "enabled": ["verb_cursor"], "needs": ["mouse", "touch"],
		"note": "右クリックかボタンでカーソルの動詞（見る・取る・話すなど）を切り替え、対象をクリックします。"},
	{"id": "context", "label": "コンテキスト（対象に合わせてカーソルと動作が決まる）", "enabled": ["context"], "needs": ["mouse", "touch", "keyboard", "gamepad"],
		"note": "対象にカーソルを合わせると形が変わり、クリックするとその対象に合った動作をします。右クリックは「見る」です。"},
]


## 画面テンプレートの一覧 [{id, name, size}]。
static func template_list() -> Array:
	var out := []
	var seen := {}
	for dir_path in AdvTemplate.SEARCH_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var names := Array(dir.get_directories())
		names.sort()
		for n in names:
			if seen.has(n) or not FileAccess.file_exists("%s/%s/template.json" % [dir_path, n]):
				continue
			seen[n] = true
			var t := AdvTemplate.load_template(n)
			if t == null:
				continue
			out.append({"id": n, "name": String(t.data.get("name", n)), "size": t.screen_size})
	return out


static func command_style(id: String) -> Dictionary:
	for s in COMMAND_STYLES:
		if s["id"] == id:
			return s
	return COMMAND_STYLES[0]


## いまのプロジェクト設定から、セットアップ画面の最初の値を作る。
static func defaults(project_path: String = AdvProject.DEFAULT_PATH) -> Dictionary:
	var d := {"game_id": "", "title": "", "template": "pc98_classic", "command": "template",
		"devices": DEVICES.duplicate(), "base_dir": "res://game", "set_main_scene": true, "set_display": true}
	var name := String(ProjectSettings.get_setting("application/config/name", ""))
	d["title"] = name
	d["game_id"] = to_id(name)
	if FileAccess.file_exists(project_path):
		var p = AdvJson.load_file(project_path)
		if p is Dictionary:
			for k in ["game_id", "title", "template"]:
				if String(p.get(k, "")) != "":
					d[k] = String(p[k])
			if p.get("input_devices") is Array and not p["input_devices"].is_empty():
				d["devices"] = p["input_devices"].duplicate()
			var en = p.get("inputs", {}).get("enabled") if p.get("inputs") is Dictionary else null
			if en is Array:
				for s in COMMAND_STYLES:
					if s["enabled"] == en:
						d["command"] = s["id"]
	return d


## 表示名からゲームIDの候補を作る（英小文字、数字、_ だけ。作れなければ "my_game"）。
static func to_id(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	out = out.trim_suffix("_")
	if out == "" or (out[0] >= "0" and out[0] <= "9"):
		return "my_game"
	return out


## 入力の間違い（日本語の文の配列。空なら問題なし）。
static func check(opts: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var gid := String(opts.get("game_id", ""))
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]{1,63}$")
	if re.search(gid) == null:
		errs.append("ゲームIDは、英小文字で始まる 2〜64 文字の英小文字・数字・_ で書いてください。")
	if String(opts.get("title", "")).strip_edges() == "":
		errs.append("タイトルを入力してください。")
	var tid := String(opts.get("template", ""))
	var t: AdvTemplate = AdvTemplate.load_template(tid) if tid != "" else null
	if t == null:
		errs.append("画面テンプレートが見つかりません: %s" % tid)
	var devices: Array = opts.get("devices", [])
	if devices.is_empty():
		errs.append("入力機器を1つ以上選んでください。")
	for dv in devices:
		if not dv in DEVICES:
			errs.append("知らない入力機器です: %s" % dv)
	var style := command_style(String(opts.get("command", "template")))
	var needs: Array = style["needs"]
	if not needs.is_empty() and not devices.is_empty() and not needs.any(func(n): return n in devices):
		errs.append("「%s」には %s のどれかが必要です。" % [style["label"], "、".join(needs.map(func(n): return DEVICE_LABELS[n]))])
	if t != null:
		var modes: Array = style["enabled"] if not (style["enabled"] as Array).is_empty() else t.get_section("inputs").get("enabled", ["select", "parser"])
		if "parser" in modes and t.region_rect("input").size == Vector2i.ZERO and modes.size() == 1:
			errs.append("このテンプレートには入力欄がないので、コマンド入力だけにはできません。")
		if modes.any(func(m): return m in ["select", "icon", "verb_click", "verb_cursor", "context"]) and not "parser" in modes \
				and t.region_rect("commands").size == Vector2i.ZERO:
			errs.append("このテンプレートにはコマンドの窓がありません。")
		if "parser" in modes and not "keyboard" in devices and modes.size() == 1:
			errs.append("コマンド入力にはキーボードが必要です。")
	var base := String(opts.get("base_dir", "res://game"))
	if not base.begins_with("res://") or base.trim_suffix("/") == "res:/" or base.begins_with("res://addons"):
		errs.append("作成先のフォルダは res:// の下（addons 以外）にしてください。")
	return errs


## これから作るもの。{dirs: [パス], files: {パス: 中身}, project: プロジェクト設定, settings: {Godot の設定名: 値}}
static func plan(opts: Dictionary, project_path: String = AdvProject.DEFAULT_PATH) -> Dictionary:
	var base := String(opts.get("base_dir", "res://game")).trim_suffix("/")
	var gid := String(opts["game_id"])
	var title := String(opts["title"]).strip_edges()
	var tid := String(opts["template"])
	var devices: Array = opts.get("devices", DEVICES)
	var style := command_style(String(opts.get("command", "template")))
	var scenario := base + "/scenario/main.scenario.json"
	var assets := base + "/assets"
	var scene := base + "/main.tscn"

	# プロジェクト設定：あればセットアップの項目だけを書き換える
	var p := {"project_version": 1}
	if FileAccess.file_exists(project_path):
		var old = AdvJson.load_file(project_path)
		if old is Dictionary:
			p = old.duplicate(true)
	p["game_id"] = gid
	p["title"] = title
	p["template"] = tid
	var tlist: Array = p.get("templates", [])
	if not tlist.is_empty() and not tid in tlist:
		tlist.insert(0, tid)
		p["templates"] = tlist
	var inputs: Dictionary = p.get("inputs", {}) if p.get("inputs") is Dictionary else {}
	if (style["enabled"] as Array).is_empty():
		inputs.erase("enabled")
	else:
		inputs["enabled"] = (style["enabled"] as Array).duplicate()
	if inputs.is_empty():
		p.erase("inputs")
	else:
		p["inputs"] = inputs
	p["input_devices"] = DEVICES.filter(func(dv): return dv in devices)
	var scenarios: Array = p.get("scenarios", [])
	if scenarios.is_empty():
		scenarios.append(scenario)
	p["scenarios"] = scenarios
	var roots: Array = p.get("asset_roots", [])
	if roots.is_empty():
		roots.append(assets)
	p["asset_roots"] = roots
	if not p.has("lang"):
		p["lang"] = "ja"

	var dirs := [base, base + "/scenario", assets]
	for d in ASSET_DIRS:
		dirs.append("%s/%s" % [assets, d])
	var files := {}
	for d in ASSET_DIRS:
		files["%s/%s/.gitkeep" % [assets, d]] = ""
	files[assets + "/manifest.json"] = JSON.stringify({"manifest_version": 1, "assets": {}}, "  ") + "\n"
	files[scenario] = JSON.stringify(_first_scenario(title, scenario), "  ", false) + "\n"
	files[scene] = _main_scene()

	var settings := {}
	if bool(opts.get("set_main_scene", true)):
		settings["application/run/main_scene"] = scene
	settings["application/config/name"] = title
	if bool(opts.get("set_display", true)):
		var t := AdvTemplate.load_template(tid)
		if t != null:
			# 大きな解像度のテンプレートはそのままの大きさ、小さなものは整数倍で 640x400 以上になるようにする
			var size := t.screen_size
			var k := 1
			while size.x * k < 640 or size.y * k < 400:
				k += 1
			settings["display/window/size/viewport_width"] = size.x
			settings["display/window/size/viewport_height"] = size.y
			if k > 1:
				settings["display/window/size/window_width_override"] = size.x * k
				settings["display/window/size/window_height_override"] = size.y * k
			settings["display/window/stretch/mode"] = "canvas_items"
			settings["display/window/stretch/aspect"] = "keep"
			settings["display/window/stretch/scale_mode"] = "integer"
	return {"dirs": dirs, "files": files, "project": p, "project_path": project_path, "settings": settings,
		"scenario": scenario, "assets": assets, "scene": scene}


## 作る。{created: [作ったファイル], skipped: [すでにあって残したファイル], errors: [失敗]}
## write_settings が false なら、Godot のプロジェクト設定（メインシーン、画面の大きさ）は書き換えない。
static func apply(opts: Dictionary, project_path: String = AdvProject.DEFAULT_PATH, write_settings: bool = true) -> Dictionary:
	var res := {"created": [], "skipped": [], "errors": Array(check(opts))}
	if not (res["errors"] as Array).is_empty():
		return res
	var pl := plan(opts, project_path)
	for d in pl["dirs"]:
		var e := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
		if e != OK:
			res["errors"].append("フォルダを作れません: %s" % d)
	for path in pl["files"]:
		if FileAccess.file_exists(path):
			res["skipped"].append(path)
			continue
		if not _write(path, String(pl["files"][path])):
			res["errors"].append("ファイルを書けません: %s" % path)
		elif not String(path).ends_with(".gitkeep"):
			res["created"].append(path)
	var existed := FileAccess.file_exists(project_path)
	if _write(project_path, JSON.stringify(pl["project"], "  ", false) + "\n"):
		res["created" if not existed else "updated"] = (res.get("created" if not existed else "updated", []) as Array) + [project_path]
	else:
		res["errors"].append("ファイルを書けません: %s" % project_path)
	if write_settings:
		for k in pl["settings"]:
			ProjectSettings.set_setting(k, pl["settings"][k])
		if ProjectSettings.save() != OK:
			res["errors"].append("Godot のプロジェクト設定を保存できません。")
	res["plan"] = pl
	return res


static func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


static func _first_scenario(title: String, path: String) -> Dictionary:
	return {
		"scenario_version": 1,
		"start": "start",
		"variables": {},
		"scenes": {
			"start": {
				"name": "はじまり",
				"first": [
					"「%s」の はじまりです。" % title,
					"%s を かきかえて、ゲームを つくりましょう。" % path.trim_prefix("res://"),
				],
				"enter": "はじまりの ばしょに もどってきた。",
				"objects": {
					"note": {
						"names": ["メモ", "かみ", "note"],
						"on": {
							"LOOK": "つくえの うえに メモが ある。",
							"EXAMINE": "「シーン、もの、でぐちを ふやしていこう」と かいてある。",
						},
					},
				},
				"exits": {},
			},
		},
	}


static func _main_scene() -> String:
	return "\n".join([
		"[gd_scene load_steps=2 format=3]",
		"",
		"[ext_resource type=\"Script\" path=\"res://addons/adv80s/adv_player.gd\" id=\"1_player\"]",
		"",
		"[node name=\"Main\" type=\"Control\"]",
		"layout_mode = 3",
		"anchors_preset = 15",
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"grow_horizontal = 2",
		"grow_vertical = 2",
		"script = ExtResource(\"1_player\")",
		"",
	])
