@tool
extends VBoxContainer
## エディタの上の「adv80s」画面。プロジェクト設定、テンプレート、マニフェストを作って編集する。
##
## - 左：同梱の JSON Schema から作ったフォーム（AdvSchemaForm）
## - 右上：確認の結果（スキーマの違反と、それぞれの読み込みの確認）。ダブルクリックでその項目へ
## - 右下：JSON の文字列。直接書き換えて「JSON を反映」でフォームに戻せる
##
## 保存すると JSON を整形して書き出し、エディタのファイル一覧に知らせる（マニフェストの自動生成もこれで動く）。

const KIND_PROJECT := 0
const KIND_TEMPLATE := 1
const KIND_MANIFEST := 2
const KIND_VARIABLES := 3
const KIND_NAMES := ["プロジェクト設定", "テンプレート", "マニフェスト", "変数の一覧"]
const SCHEMAS := ["project", "template", "manifest"]
## 新しく作るテンプレートを置くフォルダ（AdvTemplate.SEARCH_DIRS の最初）
const TEMPLATE_DIR := "res://game/templates"

var _kind: OptionButton
var _file: OptionButton
var _status: Label
var _form: AdvSchemaForm
var _diag_tree: Tree
var _json: TextEdit
var _add_files_btn: Button
var _file_buttons: Array = []   ## ファイルを編集するときだけ出すボタン
var _split: HSplitContainer
var _vars_box: VBoxContainer
var _vars_filter: LineEdit
var _vars_tree: Tree
var _vars: Array = []
var _file_dialog: EditorFileDialog
var _new_dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_base: OptionButton
var _new_register: CheckBox

var _paths: Array = []          ## _file の項目 → パス
var _path: String = ""          ## 編集中のファイル
var _root_of_manifest: String = ""
var _dirty: bool = false


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	_kind = OptionButton.new()
	for n in KIND_NAMES:
		_kind.add_item(n)
	_kind.item_selected.connect(func(_i): _refresh_files())
	bar.add_child(_kind)
	_file = OptionButton.new()
	_file.custom_minimum_size = Vector2(320, 0)
	_file.clip_text = true
	_file.fit_to_longest_item = false
	_file.item_selected.connect(func(i): _open(String(_paths[i])))
	bar.add_child(_file)
	for spec in [["新規…", _on_new, "新しく作ります"], ["再読み込み", _reload, "ファイルから読み直します（保存していない変更は消えます）"],
			["保存", save, "JSON を整形して書き出します（Ctrl+S でも保存できます）"], ["確認", validate, "スキーマと読み込みで確かめます"],
			["ファイルを表示", _show_in_fs, "FileSystem ドックでファイルを選びます"]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		b.tooltip_text = spec[2]
		bar.add_child(b)
		if spec[0] != "再読み込み":
			_file_buttons.append(b)
	_add_files_btn = Button.new()
	_add_files_btn.text = "素材ファイルから追加…"
	_add_files_btn.tooltip_text = "素材フォルダのファイルを選んで、マニフェストに項目を足します（loop_start や機種別の差し替えを書くため）"
	_add_files_btn.pressed.connect(_on_add_files)
	bar.add_child(_add_files_btn)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size = Vector2(80, 0)
	bar.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_split = split
	_vars_box = _make_vars_view()
	_vars_box.visible = false
	add_child(_vars_box)
	_form = AdvSchemaForm.new()
	_form.suggest = _suggest
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.size_flags_stretch_ratio = 3
	_form.changed.connect(_on_form_changed)
	split.add_child(_form)
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2
	split.add_child(right)
	_diag_tree = Tree.new()
	_diag_tree.columns = 2
	_diag_tree.hide_root = true
	_diag_tree.custom_minimum_size = Vector2(0, 120)
	_diag_tree.set_column_expand(0, false)
	_diag_tree.set_column_custom_minimum_width(0, 56)
	_diag_tree.item_activated.connect(_on_diag_activated)
	right.add_child(_diag_tree)
	var jbox := VBoxContainer.new()
	jbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(jbox)
	var jbar := HBoxContainer.new()
	var jl := Label.new()
	jl.text = "JSON"
	jl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jbar.add_child(jl)
	var apply := Button.new()
	apply.text = "JSON を反映"
	apply.tooltip_text = "下の JSON を読んでフォームに戻します"
	apply.pressed.connect(_apply_json)
	jbar.add_child(apply)
	jbox.add_child(jbar)
	_json = TextEdit.new()
	_json.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json.custom_minimum_size = Vector2(0, 160)
	jbox.add_child(_json)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)

	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "新しいテンプレート"
	var nb := VBoxContainer.new()
	var l1 := Label.new()
	l1.text = "ID（英小文字、数字、_）"
	nb.add_child(l1)
	_new_id = LineEdit.new()
	_new_id.custom_minimum_size = Vector2(280, 0)
	nb.add_child(_new_id)
	var l2 := Label.new()
	l2.text = "元にするテンプレート（extends）"
	nb.add_child(l2)
	_new_base = OptionButton.new()
	nb.add_child(_new_base)
	_new_register = CheckBox.new()
	_new_register.text = "プロジェクト設定の templates に加える"
	_new_register.button_pressed = true
	nb.add_child(_new_register)
	_new_dialog.add_child(nb)
	_new_dialog.confirmed.connect(_create_template)
	add_child(_new_dialog)


func _ready() -> void:
	_refresh_files()


## 画面に切り替えたとき。保存していない変更がなければ、ファイルの一覧と中身を読み直す。
func on_shown() -> void:
	if not _dirty:
		_refresh_files()


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_S and event.is_command_or_control_pressed():
		save()
		accept_event()


# ---------------------------------------------------------------- ファイルの一覧

func _refresh_files() -> void:
	_add_files_btn.visible = _kind.selected == KIND_MANIFEST
	var vars := _kind.selected == KIND_VARIABLES
	_split.visible = not vars
	_vars_box.visible = vars
	_file.visible = not vars
	for b in _file_buttons:
		b.visible = not vars
	if vars:
		_refresh_vars()
		return
	_file.clear()
	_paths.clear()
	match _kind.selected:
		KIND_PROJECT:
			_add_path(AdvProject.DEFAULT_PATH)
		KIND_TEMPLATE:
			for dir in AdvTemplate.SEARCH_DIRS:
				var d := DirAccess.open(dir)
				if d == null:
					continue
				for sub in d.get_directories():
					var p := "%s/%s/template.json" % [dir, sub]
					if FileAccess.file_exists(p):
						_add_path(p, "（アドオン）" if dir.begins_with("res://addons/") else "")
		KIND_MANIFEST:
			# アドオンの素材フォルダは最後に（読むだけ）
			var roots := Array(_manifest_roots())
			roots.sort_custom(func(a, b): return not String(a).begins_with("res://addons/") and String(b).begins_with("res://addons/"))
			for root in roots:
				_add_path(String(root) + "/" + AdvManifestGenerator.MANUAL_NAME,
					"（アドオン）" if String(root).begins_with("res://addons/") else "")
	if _paths.is_empty():
		_open("")
		return
	var keep := _paths.find(_path)
	_file.select(keep if keep >= 0 else 0)
	_open(String(_paths[_file.selected]))


func _add_path(p: String, note: String = "") -> void:
	var label := p
	if not FileAccess.file_exists(p):
		label += "（まだない）"
	_file.add_item(label + note)
	_paths.append(p)


func _manifest_roots() -> PackedStringArray:
	var diags: Array = []
	var project := AdvProject.load_project(AdvProject.DEFAULT_PATH, diags)
	return AdvManifestGenerator.project_roots(project, diags)


# ---------------------------------------------------------------- 開く・保存

func _open(path: String) -> void:
	_path = path
	_root_of_manifest = path.get_base_dir() if _kind.selected == KIND_MANIFEST else ""
	var schema := AdvSchemaValidator.load_schema(SCHEMAS[_kind.selected])
	var value: Variant = _initial_value()
	if path != "" and FileAccess.file_exists(path):
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(path)) == OK:
			value = AdvSchemaForm.normalize(j.data)
		else:
			_status.text = "JSON の書き方に誤りがあります（%d 行目）: %s" % [j.get_error_line(), j.get_error_message()]
	_form.read_only = path.begins_with("res://addons/adv80s/templates/") or path.begins_with(AdvAssets.BUILTIN_ROOT)
	_form.setup(schema, value)
	_dirty = false
	_update_json()
	validate()
	if _form.read_only:
		_status.text = "アドオンのファイルは読むだけです（新規で extends して作ってください）"


## まだないファイルを開いたときの最初の中身。
func _initial_value() -> Dictionary:
	match _kind.selected:
		KIND_PROJECT:
			return {"project_version": 1, "template": "pc98_classic", "scenarios": [], "asset_roots": [], "lang": "ja", "features": {}}
		KIND_MANIFEST:
			return {"manifest_version": 1, "assets": {}}
	return {"template_version": 1, "id": "", "name": "", "extends": "pc98_classic"}


func _reload() -> void:
	if _kind.selected == KIND_VARIABLES:
		_refresh_vars()
		return
	_open(_path)


func save() -> void:
	if _path == "" or _form.read_only:
		return
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("[adv80s] 書き出せません: %s" % _path)
		return
	f.store_string(JSON.stringify(_form.data, "  ", false) + "\n")
	f.close()
	_dirty = false
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(_path)
	_status.text = "保存しました: %s" % _path
	var sel := _file.selected
	_refresh_label(sel)
	validate()


func _refresh_label(i: int) -> void:
	if i >= 0 and i < _paths.size():
		_file.set_item_text(i, String(_paths[i]) + ("（アドオン）" if String(_paths[i]).begins_with("res://addons/") else ""))


func _show_in_fs() -> void:
	if _path != "" and FileAccess.file_exists(_path):
		EditorInterface.select_file(_path)


func _on_form_changed() -> void:
	_dirty = true
	_status.text = "変更あり（保存していません）"
	_update_json()
	validate()


func _update_json() -> void:
	_json.text = JSON.stringify(_form.data, "  ", false)


func _apply_json() -> void:
	var j := JSON.new()
	if j.parse(_json.text) != OK:
		_status.text = "JSON の書き方に誤りがあります（%d 行目）: %s" % [j.get_error_line(), j.get_error_message()]
		return
	_form.data = AdvSchemaForm.normalize(j.data)
	_form.rebuild()
	_on_form_changed()


# ---------------------------------------------------------------- 確認

func validate() -> void:
	var diags: Array = AdvSchemaValidator.check(_form.data, SCHEMAS[_kind.selected], _path)
	match _kind.selected:
		KIND_TEMPLATE:
			var ext = _form.data.get("extends") if _form.data is Dictionary else null
			if ext is String and ext != "" and AdvTemplate.find_path(ext) == "":
				diags.append(AdvDiag.make("error", "MISSING_TARGET", "元にするテンプレートが見つかりません: %s" % ext,
					"Base template not found: %s" % ext, _path, "/extends"))
			var preset = _form.data.get("display", {}).get("preset") if _form.data is Dictionary else null
			if preset is String and AdvPresets.resolve(preset).is_empty():
				diags.append(AdvDiag.make("error", "MISSING_TARGET", "プリセットが見つかりません: %s" % preset,
					"Preset not found: %s" % preset, _path, "/display/preset"))
		KIND_PROJECT:
			if _form.data is Dictionary:
				var tid := String(_form.data.get("template", ""))
				if tid != "" and AdvTemplate.find_path(tid) == "":
					diags.append(AdvDiag.make("error", "MISSING_TARGET", "テンプレートが見つかりません: %s" % tid,
						"Template not found: %s" % tid, _path, "/template"))
				var list: Array = _form.data.get("scenarios", [])
				for i in list.size():
					if not FileAccess.file_exists(String(list[i])):
						diags.append(AdvDiag.make("error", "ASSET_NOT_FOUND", "シナリオが見つかりません: %s" % list[i],
							"Scenario not found: %s" % list[i], _path, "/scenarios/%d" % i))
				var roots: Array = _form.data.get("asset_roots", [])
				for i in roots.size():
					if not DirAccess.dir_exists_absolute(String(roots[i])):
						diags.append(AdvDiag.make("warning", "ASSET_NOT_FOUND", "素材フォルダが見つかりません: %s" % roots[i],
							"Asset folder not found: %s" % roots[i], _path, "/asset_roots/%d" % i))
		KIND_MANIFEST:
			var assets = _form.data.get("assets", {}) if _form.data is Dictionary else {}
			if assets is Dictionary:
				for key in assets:
					var e = assets[key]
					if e is Dictionary and e.has("file"):
						var p := String(e["file"])
						if not p.contains("://"):
							p = _root_of_manifest + "/" + p
						if not FileAccess.file_exists(p):
							diags.append(AdvDiag.make("warning", "ASSET_NOT_FOUND", "ファイルが見つかりません: %s" % e["file"],
								"File not found: %s" % e["file"], _path, "/assets/%s/file" % AdvSchemaForm.pointer([key]).substr(1)))
	_show_diags(diags)


func _show_diags(diags: Array) -> void:
	_diag_tree.clear()
	var root := _diag_tree.create_item()
	if diags.is_empty():
		var it := _diag_tree.create_item(root)
		it.set_text(0, "OK")
		it.set_text(1, "問題は見つかりませんでした")
		it.set_custom_color(0, Color(0.5, 0.9, 0.5))
		return
	for d in diags:
		var sev := String(d["severity"])
		var it := _diag_tree.create_item(root)
		it.set_text(0, {"error": "エラー", "warning": "警告", "info": "情報"}.get(sev, sev))
		it.set_custom_color(0, Color(1, 0.4, 0.4) if sev == "error" else (Color(1, 0.8, 0.3) if sev == "warning" else Color(0.7, 0.7, 0.7)))
		it.set_text(1, "%s  %s" % [d["message"], d.get("path", "")])
		it.set_tooltip_text(1, "%s: %s" % [d["code"], d["message"]])
		it.set_metadata(0, String(d.get("path", "")))


func _on_diag_activated() -> void:
	var it := _diag_tree.get_selected()
	if it != null and String(it.get_metadata(0)) != "":
		_form.select_pointer(String(it.get_metadata(0)))


# ---------------------------------------------------------------- 新規

func _on_new() -> void:
	match _kind.selected:
		KIND_PROJECT:
			if FileAccess.file_exists(AdvProject.DEFAULT_PATH):
				_status.text = "プロジェクト設定はすでにあります"
				return
			_open(AdvProject.DEFAULT_PATH)
			save()
		KIND_TEMPLATE:
			_new_base.clear()
			for dir in AdvTemplate.SEARCH_DIRS:
				var d := DirAccess.open(dir)
				if d != null:
					for sub in d.get_directories():
						if FileAccess.file_exists("%s/%s/template.json" % [dir, sub]):
							_new_base.add_item(sub)
							if sub == "pc98_classic":
								_new_base.select(_new_base.item_count - 1)
			_new_id.text = ""
			_new_dialog.popup_centered()
			_new_id.grab_focus()
		KIND_MANIFEST:
			if _path != "" and not FileAccess.file_exists(_path) and not _form.read_only:
				save()
			else:
				_status.text = "上の一覧から「（まだない）」の素材フォルダを選んで保存すると作れます"


func _create_template() -> void:
	var id := _new_id.text.strip_edges()
	var re := RegEx.new()
	re.compile("^[a-z0-9_]+$")
	if re.search(id) == null:
		_status.text = "ID は英小文字、数字、_ で書いてください"
		return
	var path := "%s/%s/template.json" % [TEMPLATE_DIR, id]
	if FileAccess.file_exists(path) or AdvTemplate.find_path(id) != "":
		_status.text = "同じ ID のテンプレートがあります: %s" % id
		return
	var base := _new_base.get_item_text(_new_base.selected) if _new_base.selected >= 0 else "pc98_classic"
	var data := {"template_version": 1, "id": id, "name": id, "extends": base}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	f.close()
	if _new_register.button_pressed:
		_register_template(id)
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(path)
	_path = path
	_refresh_files()
	_status.text = "作りました: %s" % path


## プロジェクト設定の templates に ID を足す（ファイルがなければ作らない）。
func _register_template(id: String) -> void:
	var p := AdvProject.DEFAULT_PATH
	if not FileAccess.file_exists(p):
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(p)) != OK or not j.data is Dictionary:
		return
	var d: Dictionary = AdvSchemaForm.normalize(j.data)
	var list: Array = d.get("templates", [])
	if id in list:
		return
	list.append(id)
	d["templates"] = list
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	f.close()
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(p)


# ---------------------------------------------------------------- マニフェスト：素材ファイルから追加

func _on_add_files() -> void:
	if _root_of_manifest == "" or _form.read_only:
		return
	_file_dialog.current_dir = _root_of_manifest
	_file_dialog.popup_file_dialog()


func _on_files_selected(files: PackedStringArray) -> void:
	if _form.read_only:
		return
	var folders := AdvAssets.DEFAULT_FOLDERS
	var project := AdvProject.load_project()
	folders = project.asset_folders()
	var assets: Dictionary = _form.data.get("assets", {})
	_form.data["assets"] = assets
	var added := 0
	for p in files:
		var path := String(p)
		var entry := entry_for_file(path, _root_of_manifest, folders)
		if assets.has(entry["key"]):
			continue
		assets[entry["key"]] = entry["value"]
		added += 1
	_form.rebuild()
	_on_form_changed()
	_status.text = "%d 件を足しました（保存していません）" % added


## 素材ファイルのマニフェストの項目。キーは「種類:ID」、値は {type, file}。
## 種類は種類フォルダから決め、種類フォルダの外なら拡張子から決める。
static func entry_for_file(path: String, root: String, folders: Dictionary) -> Dictionary:
	var rel := path.trim_prefix(root.trim_suffix("/") + "/") if path.begins_with(root) else path
	var parts := rel.split("/")
	var kind := ""
	var id_parts := parts
	if parts.size() >= 2 and folders.get(parts[0]) is String:
		kind = String(folders[parts[0]])
		id_parts = parts.slice(1)
	else:
		match path.get_extension().to_lower():
			"png", "jpg", "jpeg", "webp", "svg": kind = "image"
			"wav", "ogg", "mp3": kind = "se"
			"ttf", "otf", "woff", "woff2", "fnt": kind = "font"
			"gdshader": kind = "shader"
			_: kind = "image"
		id_parts = PackedStringArray([parts[parts.size() - 1]])
	var last := String(id_parts[id_parts.size() - 1]).get_basename()
	var at := last.find("@")
	if at >= 0:
		last = last.substr(0, at)
	id_parts[id_parts.size() - 1] = last
	var id := ".".join(id_parts)
	return {"key": "%s:%s" % [kind, id], "value": {"type": kind, "file": rel}}


# ---------------------------------------------------------------- 候補（一覧から選ぶ項目）

## フォームの文字列の項目の候補。path は項目の場所（["templates", 0] など）。
func _suggest(path: Array) -> Array:
	var last = path[path.size() - 1] if not path.is_empty() else ""
	match _kind.selected:
		KIND_PROJECT:
			if path == ["template"] or (path.size() == 2 and path[0] == "templates"):
				return template_ids()
			if path.size() == 2 and path[0] == "scenarios":
				return scenario_files()
			if path.size() == 2 and path[0] == "asset_roots":
				return []
		KIND_TEMPLATE:
			if path == ["extends"]:
				var own := String(_form.data.get("id", "")) if _form.data is Dictionary else ""
				return template_ids().filter(func(t): return t != own)
			if path == ["display", "preset"]:
				return preset_ids()
			if path.size() >= 2 and path[0] == "fonts" and last == "asset":
				return asset_ids("font")
		KIND_MANIFEST:
			if path.size() >= 3 and path[0] == "assets" and String(path[path.size() - 2]) == "by_preset":
				return []
	return []


## 使えるテンプレートのID（プロジェクトの game/templates と、アドオンの標準）。
static func template_ids() -> Array:
	var out := []
	for dir in AdvTemplate.SEARCH_DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			if FileAccess.file_exists("%s/%s/template.json" % [dir, sub]) and not sub in out:
				out.append(sub)
	return out


## 画面プリセットのID（機種だけのものと「機種.画面モード」）。
static func preset_ids() -> Array:
	var out := []
	for m in AdvPresets.machines():
		out.append(m)
		for mode in AdvPresets.modes(m):
			out.append("%s.%s" % [m, mode])
	return out


## シナリオのファイル（res:// の下の *.scenario.json と *.ink.json。addons と隠しフォルダは除く）。
static func scenario_files(dir: String = "res://") -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".scenario.json") or f.ends_with(".ink.json"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with(".") or (dir == "res://" and sub == "addons"):
			continue
		out.append_array(scenario_files(dir.path_join(sub)))
	return out


## 素材のID（プロジェクトのすべての素材フォルダから、種類を指定して）。
func asset_ids(kind: String) -> Array:
	var diags: Array = []
	var project := AdvProject.load_project(AdvProject.DEFAULT_PATH, diags)
	var a := AdvAssets.new()
	a.folders = project.asset_folders()
	for root in AdvManifestGenerator.project_roots(project, diags):
		a.add_manifest(AdvManifestGenerator.scan(root, a.folders)["manifest"], root)
		var manual := String(root) + "/" + AdvManifestGenerator.MANUAL_NAME
		if FileAccess.file_exists(manual):
			var m = AdvJson.load_file(manual)
			if m is Dictionary:
				a.add_manifest(m, root)
	var ids: Array = a._entries.get(kind, {}).keys()
	ids.sort()
	return ids


# ---------------------------------------------------------------- 変数の一覧

const VAR_COLUMNS := ["名前", "種類", "元", "型", "初期値", "定義した場所", "読む", "書く", "メモ"]


func _make_vars_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	var l := Label.new()
	l.text = "絞り込み"
	bar.add_child(l)
	_vars_filter = LineEdit.new()
	_vars_filter.placeholder_text = "名前・種類・場所の一部"
	_vars_filter.custom_minimum_size = Vector2(240, 0)
	_vars_filter.text_changed.connect(func(_t): _fill_vars())
	bar.add_child(_vars_filter)
	var hint := Label.new()
	hint.text = "ダブルクリックでファイルを選びます。読む・書くの数にマウスを重ねると場所が出ます"
	hint.modulate = Color(0.7, 0.7, 0.7)
	bar.add_child(hint)
	box.add_child(bar)
	_vars_tree = Tree.new()
	_vars_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vars_tree.columns = VAR_COLUMNS.size()
	_vars_tree.column_titles_visible = true
	_vars_tree.hide_root = true
	for i in VAR_COLUMNS.size():
		_vars_tree.set_column_title(i, VAR_COLUMNS[i])
		_vars_tree.set_column_expand(i, i in [0, 4, 5, 8])
		if not i in [0, 4, 5, 8]:
			_vars_tree.set_column_custom_minimum_width(i, 64)
	_vars_tree.item_activated.connect(_on_var_activated)
	box.add_child(_vars_tree)
	return box


func _refresh_vars() -> void:
	_vars = AdvVariableIndex.collect()
	_fill_vars()
	var n := _vars.filter(func(e): return e["kind"] != "組み込み").size()
	_status.text = "変数・定数 %d 件（組み込み %d 件）" % [n, _vars.size() - n]


func _fill_vars() -> void:
	_vars_tree.clear()
	var root := _vars_tree.create_item()
	var q := _vars_filter.text.strip_edges().to_lower()
	for e in _vars:
		var where := String(e["file"])
		if int(e.get("line", 0)) > 0:
			where += ":%d" % int(e["line"])
		elif String(e.get("path", "")) != "":
			where += "  " + String(e["path"])
		var row := [String(e["name"]), String(e["kind"]), String(e["source"]), String(e.get("type", "")),
			_default_text(e),
			where, str(e["reads"].size()) if e["kind"] != "組み込み" else "", str(e["writes"].size()) if e["kind"] != "組み込み" else "",
			String(e.get("note", ""))]
		if q != "" and not " ".join(PackedStringArray(row)).to_lower().contains(q):
			continue
		var it := _vars_tree.create_item(root)
		for i in row.size():
			it.set_text(i, row[i])
		it.set_tooltip_text(0, row[0])
		it.set_tooltip_text(5, where)
		it.set_tooltip_text(8, row[8])
		it.set_tooltip_text(6, _locs_text(e["reads"]))
		it.set_tooltip_text(7, _locs_text(e["writes"]))
		var note := String(e.get("note", ""))
		if note.begins_with("宣言も"):
			it.set_custom_color(8, Color(1, 0.8, 0.3))
		if e["kind"] == "組み込み":
			for i in row.size():
				it.set_custom_color(i, Color(0.65, 0.75, 0.9))
		it.set_metadata(0, String(e["file"]))


static func _default_text(e: Dictionary) -> String:
	var v = e.get("default")
	if v == null:
		return ""
	if v is String and e["source"] == "Ink":
		return v   # .ink に書いたままの値
	return JSON.stringify(AdvSchemaForm.normalize(v))


static func _locs_text(locs: Array) -> String:
	var lines := PackedStringArray()
	for l in locs:
		lines.append("%s  %s" % [l["file"], l["path"]])
	return "\n".join(lines) if not lines.is_empty() else "なし"


func _on_var_activated() -> void:
	var it := _vars_tree.get_selected()
	if it == null:
		return
	var f := String(it.get_metadata(0))
	if f.begins_with("res://") and FileAccess.file_exists(f):
		EditorInterface.select_file(f)
