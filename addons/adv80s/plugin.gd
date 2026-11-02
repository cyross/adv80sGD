@tool
extends EditorPlugin
## adv80s エディタプラグイン。
## - 素材フォルダを読んで manifest.auto.json を書き出す（ファイルが変わったとき、書き出しの直前、手動）
## - 確認の結果をドック「adv80s」に一覧表示する（エラーと警告を区別）
## - ゲームの書き出しに JSON（シナリオ、マニフェストなど）を必ず含める
## - VS Code 用の JSON Schema の結び付け設定を書き出す
## - 上の「adv80s」画面で、プロジェクト設定・テンプレート・マニフェストを作って編集する

const DOCK_SCRIPT := preload("res://addons/adv80s/editor/adv_dock.gd")
const EXPORT_SCRIPT := preload("res://addons/adv80s/editor/adv_export_plugin.gd")
const SCREEN_SCRIPT := preload("res://addons/adv80s/editor/adv_editor_screen.gd")
const ANIM_IMPORTER := preload("res://addons/adv80s/editor/adv_anim_importer.gd")

const MENU_GENERATE := "adv80s: マニフェストを生成"
const MENU_VSCODE := "adv80s: VS Code の設定を書き出す"
const MENU_KEY := "adv80s: セーブの鍵を生成"

var _dock: Control
var _screen: Control
var _gif: EditorImportPlugin
var _export: EditorExportPlugin
var _timer: Timer
var _busy := false


func _enter_tree() -> void:
	_gif = ANIM_IMPORTER.new()
	add_import_plugin(_gif)

	_dock = DOCK_SCRIPT.new()
	_dock.name = "adv80s"
	_dock.generate_requested.connect(generate)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	_screen = SCREEN_SCRIPT.new()
	_screen.name = "adv80s"
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_screen.visible = false

	_export = EXPORT_SCRIPT.new()
	_export.plugin = self
	add_export_plugin(_export)

	add_tool_menu_item(MENU_GENERATE, generate)
	add_tool_menu_item(MENU_VSCODE, write_vscode_settings)
	add_tool_menu_item(MENU_KEY, generate_save_key)

	# ファイルが変わったら、少し待ってから生成する（続けて変わったときにまとめるため）
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 1.0
	_timer.timeout.connect(generate)
	add_child(_timer)
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null and fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)
	remove_tool_menu_item(MENU_GENERATE)
	remove_tool_menu_item(MENU_VSCODE)
	remove_tool_menu_item(MENU_KEY)
	if _export != null:
		remove_export_plugin(_export)
		_export = null
	if _gif != null:
		remove_import_plugin(_gif)
		_gif = null
	if _screen != null:
		_screen.queue_free()
		_screen = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _screen != null:
		_screen.visible = visible
		if visible:
			_screen.on_shown()


func _get_plugin_name() -> String:
	return "adv80s"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("FileList", "EditorIcons")


func _on_filesystem_changed() -> void:
	if not _busy:
		_timer.start()


## マニフェストを生成して、結果をドックに出す。書き出したファイルがあればエディタに知らせる。
func generate() -> Dictionary:
	_busy = true
	AdvDiag.lang = _editor_lang()
	var res := AdvManifestGenerator.generate_project()
	if _dock != null:
		_dock.show_result(res)
	if not res["written"].is_empty():
		var fs := EditorInterface.get_resource_filesystem()
		for p in res["written"]:
			fs.update_file(p)
	_busy = false
	return res


## セーブの鍵（res://master.key）を乱数で作る。すでにあれば作らない（鍵を変えると、それまでのセーブが読めなくなる）。
## master.key は Git の管理対象から外しておくこと（.gitignore に master.key を書く）。
func generate_save_key() -> void:
	var err := AdvEmbeddedKeyProvider.generate_key_file()
	match err:
		OK:
			print("[adv80s] %s を作りました。Git にコミットしないでください（.gitignore に master.key を加えてください）" % AdvEmbeddedKeyProvider.KEY_FILE)
		ERR_ALREADY_EXISTS:
			push_warning("[adv80s] %s はすでにあります。鍵を変えるとそれまでのセーブが読めなくなるため、作り直しません" % AdvEmbeddedKeyProvider.KEY_FILE)
		_:
			push_error("[adv80s] 鍵を作れませんでした（%s）" % error_string(err))
	if not FileAccess.file_exists("res://.gitignore") or not FileAccess.get_file_as_string("res://.gitignore").contains("master.key"):
		push_warning("[adv80s] .gitignore に master.key がありません。鍵を公開しないよう加えてください")


## VS Code の json.schemas 設定（res://.vscode/settings.json）を書き出す。
## エディタの言語に合わせて schemas/ja か schemas/en を結び付ける。既存の設定は残し、json.schemas だけ置き換える。
func write_vscode_settings() -> void:
	var path := "res://.vscode/settings.json"
	var settings: Dictionary = {}
	if FileAccess.file_exists(path):
		var d = AdvJson.load_file(path)
		if d is Dictionary:
			settings = d
	settings["json.schemas"] = vscode_schema_map(_editor_lang())
	DirAccess.make_dir_recursive_absolute("res://.vscode")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[adv80s] %s を書き出せません" % path)
		return
	f.store_string(JSON.stringify(settings, "  ") + "\n")
	f.close()
	print("[adv80s] %s を書き出しました（%s）" % [path, _editor_lang()])


## ファイル名の決まりとスキーマの対応。
static func vscode_schema_map(lang: String) -> Array:
	var dir := "./addons/adv80s/schemas/%s" % lang
	return [
		{"fileMatch": ["*.scenario.json"], "url": dir + "/scenario.schema.json"},
		{"fileMatch": ["template.json", "*.template.json"], "url": dir + "/template.schema.json"},
		{"fileMatch": ["*.intent_schema.json", "intent_schema.*.json"], "url": dir + "/intent_schema.schema.json"},
		{"fileMatch": ["manifest.json", "manifest.auto.json"], "url": dir + "/manifest.schema.json"},
		{"fileMatch": ["adv80s.project.json", "*.project.json"], "url": dir + "/project.schema.json"},
		{"fileMatch": ["*.effect.json"], "url": dir + "/effect_def.schema.json"},
	]


static func _editor_lang() -> String:
	var es := EditorInterface.get_editor_settings()
	var l := String(es.get_setting("interface/editor/editor_language")) if es != null else ""
	return "ja" if l.begins_with("ja") else "en"
