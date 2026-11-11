class_name AdvManifestGenerator
extends RefCounted
## 素材フォルダを読んで、自動生成マニフェスト（manifest.auto.json）を作る部品（5.5、5.6）。
## エディタに依存しないので、エディタプラグインとコマンドラインの両方から使う。
##
## 自動生成マニフェストの形：
## {
##   "manifest_version": 1,
##   "generated": true,
##   "assets": {
##     "image:hallway": { "type": "image", "file": "bg/hallway.png",
##                        "by_preset": { "pc80": "presets/pc80/bg/hallway.png" } },
##     "image:ayumi":   { "type": "image", "file": "chara/ayumi.png",
##                        "variants": { "smile": "chara/ayumi@smile.png" } }
##   }
## }
## キーは「種類:ID」（種類ごとに名前空間が別なので、bg/door.png と se/door.wav が両方あっても衝突しない）。
## パスはマニフェストのあるフォルダからの相対パス。

const AUTO_NAME := "manifest.auto.json"
const MANUAL_NAME := "manifest.json"
const ASSET_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "ktx", "dds", "gif", "apng", "mng", "mag", "ogv",
	"ogg", "wav", "mp3", "ttf", "otf", "woff", "woff2", "fnt", "font", "gdshader"]

## Godot が再生できない動画の拡張子（.ogv に変換してから置く）
const UNSUPPORTED_VIDEO_EXT := ["mp4", "m4v", "webm", "avi", "mov", "mkv", "mpg", "mpeg", "wmv", "flv"]

static var _name_re: RegEx


## 素材フォルダを読む。{"manifest": 辞書, "diags": 診断の配列} を返す。
static func scan(root: String, folders: Dictionary = AdvAssets.DEFAULT_FOLDERS) -> Dictionary:
	var diags: Array = []
	var files: Array = []
	var r := root.trim_suffix("/")
	if not DirAccess.dir_exists_absolute(r):
		diags.append(AdvDiag.make("error", "ASSET_NOT_FOUND", "素材フォルダがありません: %s" % r,
			"Asset folder not found: %s" % r, r))
		return {"manifest": _empty(), "diags": diags}
	_walk(r, "", files)
	files.sort()

	var entries: Dictionary = {}    # "kind:id" → エントリ
	var origin: Dictionary = {}     # "kind:id" → 最初に見つかった種類フォルダ（重複の判定用）
	var warned_folders: Dictionary = {}
	for rel in files:
		if String(rel).begins_with("!"):
			diags.append(_diag("warning", "ASSET_UNSUPPORTED", "この形式の動画は再生できません。Ogg Theora（.ogv）に変換してください: %s" % String(rel).substr(1),
				"This video format cannot be played; convert it to Ogg Theora (.ogv): %s" % String(rel).substr(1), r, String(rel).substr(1)))
			continue
		var parts: PackedStringArray = String(rel).split("/")
		var preset_key := ""
		if parts[0] == "presets":
			if parts.size() < 4:
				diags.append(_diag("warning", "UNKNOWN_FOLDER", "presets の下は「presets/プリセットIDかグループID/種類フォルダ/…」の形にしてください: %s" % rel,
					"Files under presets must be presets/<preset or group>/<kind folder>/...: %s" % rel, r, rel))
				continue
			preset_key = parts[1]
			parts = parts.slice(2)
		if parts.size() < 2:
			diags.append(_diag("warning", "UNKNOWN_FOLDER", "種類フォルダの外にある素材は登録しません: %s" % rel,
				"Files outside kind folders are not registered: %s" % rel, r, rel))
			continue
		var folder := parts[0]
		if not folders.has(folder) or folders[folder] == null:
			if not warned_folders.has(folder):
				warned_folders[folder] = true
				diags.append(_diag("warning", "UNKNOWN_FOLDER", "対応表にないフォルダです（asset_folders で追加できます）: %s" % folder,
					"Folder is not in the kind table (add it with asset_folders): %s" % folder, r, rel))
			continue
		var kind := String(folders[folder])
		_check_name(rel, r, diags)
		var name_parts := parts.slice(1)
		var last := String(name_parts[name_parts.size() - 1]).get_basename()
		var variant := ""
		var at := last.find("@")
		if at >= 0:
			variant = last.substr(at + 1)
			last = last.substr(0, at)
		name_parts[name_parts.size() - 1] = last
		var id := ".".join(name_parts)
		var key := "%s:%s" % [kind, id]

		if origin.has(key) and origin[key] != folder:
			diags.append(_diag("warning", "DUPLICATE_ID", "同じ種類の中でIDが重複しています: %s（%s と %s）。先に見つかった方を使います" % [id, origin[key], folder],
				"Duplicate ID in the same kind: %s (%s and %s). The first one is used" % [id, origin[key], folder], r, rel))
			continue
		origin[key] = folder
		if not entries.has(key):
			entries[key] = {"type": kind}
		var e: Dictionary = entries[key]
		if preset_key == "":
			if variant == "":
				e["file"] = rel
			else:
				if not e.has("variants"):
					e["variants"] = {}
				e["variants"][variant] = rel
		else:
			if not e.has("by_preset"):
				e["by_preset"] = {}
			var bp: Dictionary = e["by_preset"]
			if variant == "":
				if bp.get(preset_key) is Dictionary:
					bp[preset_key]["file"] = rel
				else:
					bp[preset_key] = rel
			else:
				var cur = bp.get(preset_key)
				var d: Dictionary = cur if cur is Dictionary else ({"file": cur} if cur is String else {})
				if not d.has("variants"):
					d["variants"] = {}
				d["variants"][variant] = rel
				bp[preset_key] = d

	for key in entries:
		var e: Dictionary = entries[key]
		if not e.has("file") and not e.has("variants"):
			diags.append(_diag("warning", "NO_DEFAULT_FILE", "機種別の差し替えだけがあり、既定のファイルがありません: %s" % key,
				"Only preset overrides exist and there is no default file: %s" % key, r, ""))
	var manifest := _empty()
	manifest["assets"] = entries
	return {"manifest": manifest, "diags": diags}


static func _empty() -> Dictionary:
	return {"manifest_version": 1, "generated": true, "assets": {}}


static func _walk(dir_path: String, rel: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = false
	for name in dir.get_directories():
		if name.begins_with("_") or name.begins_with("."):
			continue
		_walk(dir_path + "/" + name, (rel + "/" + name).trim_prefix("/"), out)
	for file in dir.get_files():
		if file.begins_with("_") or file.begins_with("."):
			continue
		var ext := file.get_extension().to_lower()
		if ext in UNSUPPORTED_VIDEO_EXT:
			out.append("!" + (rel + "/" + file).trim_prefix("/"))   # 使えない動画（scan で警告する）
			continue
		if not ext in ASSET_EXT:
			continue
		out.append((rel + "/" + file).trim_prefix("/"))


static func _check_name(rel: String, root: String, diags: Array) -> void:
	if _name_re == null:
		_name_re = RegEx.create_from_string("^[a-z0-9_\\-]+(@[a-z0-9_\\-]+)?$")
	var parts := rel.split("/")
	for i in parts.size():
		var seg := parts[i] if i < parts.size() - 1 else parts[i].get_basename()
		if _name_re.search(seg) == null:
			diags.append(_diag("warning", "NAMING", "ファイル名とフォルダ名は英小文字、数字、_、- を推奨します: %s" % rel,
				"Use lowercase letters, digits, _ and - in file and folder names: %s" % rel, root, rel))
			return


static func _diag(severity: String, code: String, ja: String, en: String, root: String, rel: String) -> Dictionary:
	return AdvDiag.make(severity, code, ja, en, root + "/" + rel if rel != "" else root)


## 手書きのマニフェスト（manifest.json）を確かめる。JSONの誤りと、存在しないファイルはエラー。
static func check_manual(root: String) -> Array:
	var diags: Array = []
	var path := root.trim_suffix("/") + "/" + MANUAL_NAME
	if not FileAccess.file_exists(path):
		return diags
	var d = AdvJson.load_file(path, diags)
	if not d is Dictionary:
		return diags
	var base := AdvManifestGenerator.base_dir(d, root)
	var assets: Dictionary = d.get("assets", {})
	for key in assets:
		var e = assets[key]
		if String(key).contains("/"):
			diags.append(AdvDiag.make("error", "INVALID_ID", "IDに / は使えません: %s" % key,
				"IDs cannot contain '/': %s" % key, path, "/assets/%s" % key))
		if not e is Dictionary:
			continue
		for f in _files_of(e):
			if not FileAccess.file_exists(base + "/" + f) and not ResourceLoader.exists(base + "/" + f):
				diags.append(AdvDiag.make("error", "ASSET_NOT_FOUND", "マニフェストに書かれたファイルがありません: %s" % f,
					"File listed in the manifest does not exist: %s" % f, path, "/assets/%s" % key))
	return diags


## マニフェストの base（省略時はマニフェストのあるフォルダ）。
static func base_dir(manifest: Dictionary, root: String) -> String:
	var b := String(manifest.get("base", ""))
	if b == "":
		return root.trim_suffix("/")
	if b.contains("://"):
		return b.trim_suffix("/")
	return (root.trim_suffix("/") + "/" + b).trim_suffix("/")


static func _files_of(e: Dictionary) -> Array:
	var r := []
	if e.has("file"):
		r.append(String(e["file"]))
	for v in e.get("variants", {}).values():
		r.append(String(v))
	for v in e.get("by_preset", {}).values():
		if v is String:
			r.append(v)
		elif v is Dictionary:
			r.append_array(_files_of(v))
	return r


## 書き出す文字列（キーを並べ替え、差分を読みやすくする）。
static func to_text(manifest: Dictionary) -> String:
	return JSON.stringify(manifest, "  ", true) + "\n"


## manifest.auto.json を書き出す。内容が同じなら書かない（ファイルの更新日時を変えないため）。
## 書いたら OK、変更なしなら ERR_ALREADY_EXISTS、失敗したらそのエラー。
static func write(root: String, manifest: Dictionary) -> Error:
	var path := root.trim_suffix("/") + "/" + AUTO_NAME
	var text := to_text(manifest)
	if FileAccess.file_exists(path) and _same(FileAccess.get_file_as_string(path), text):
		return ERR_ALREADY_EXISTS
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


## コミット済みの manifest.auto.json が、書き出すはずの内容と一致するか。
static func is_up_to_date(root: String, manifest: Dictionary) -> bool:
	var path := root.trim_suffix("/") + "/" + AUTO_NAME
	if not FileAccess.file_exists(path):
		return false
	return _same(FileAccess.get_file_as_string(path), to_text(manifest))


static func _same(a: String, b: String) -> bool:
	return a.replace("\r\n", "\n") == b.replace("\r\n", "\n")


## プロジェクト設定、テンプレート、シナリオから素材フォルダを集める（重ねる順）。
static func project_roots(project: AdvProject, diags: Array) -> PackedStringArray:
	var r := PackedStringArray()
	if DirAccess.dir_exists_absolute(AdvAssets.BUILTIN_ROOT):
		r.append(AdvAssets.BUILTIN_ROOT)
	for p in project.get_value("asset_roots", []):
		r.append(String(p).trim_suffix("/"))
	var tids: Array = project.get_value("templates", []).duplicate()
	var main_t := String(project.get_value("template", ""))
	if main_t != "" and not main_t in tids:
		tids.push_front(main_t)
	for tid in tids:
		var t := AdvTemplate.load_template(String(tid), diags)
		if t != null and t.asset_root() != "" and not t.asset_root() in r:
			r.append(t.asset_root())
	for sroot in scenario_roots(project):
		if not sroot in r:
			r.append(sroot)
	return r


static func scenario_roots(project: AdvProject) -> PackedStringArray:
	var r := PackedStringArray()
	for path in project.get_value("scenarios", []):
		var d = AdvJson.load_file(String(path))
		if d is Dictionary and d.get("assets") is Dictionary and d["assets"].has("root"):
			var root := String(d["assets"]["root"])
			if not root.contains("://"):
				root = String(path).get_base_dir() + "/" + root
			r.append(root.trim_suffix("/"))
	return r


## プロジェクトのすべての素材フォルダについて生成する（エディタプラグインから使う）。
## {"roots": [...], "diags": [...], "written": [...]} を返す。
static func generate_project(project_path: String = AdvProject.DEFAULT_PATH, write_files: bool = true) -> Dictionary:
	var diags: Array = []
	var project := AdvProject.load_project(project_path, diags)
	var folders := project.asset_folders()
	var roots := project_roots(project, diags)
	var written: Array = []
	var manifests: Dictionary = {}
	for root in roots:
		var res := scan(root, folders)
		manifests[root] = res["manifest"]
		diags.append_array(res["diags"])
		diags.append_array(check_manual(root))
		if write_files:
			var err := write(root, res["manifest"])
			if err == OK:
				written.append(root + "/" + AUTO_NAME)
			elif err != ERR_ALREADY_EXISTS:
				diags.append(AdvDiag.make("error", "TOOL_ERROR", "書き出しに失敗しました: %s（%s）" % [root, error_string(err)],
					"Failed to write: %s (%s)" % [root, error_string(err)], root))
	for d in check_scenarios(project, manifests, folders):
		if d["severity"] != "info":
			diags.append(d)
	return {"roots": Array(roots), "diags": diags, "written": written}


## シナリオを読み、参照している素材IDが（これから書き出すマニフェストに）実在するか確かめる。
## ビルドの時点では、見つからない素材はエラーにする（ゲーム実行中は missing_asset の設定に従う）。
static func check_scenarios(project: AdvProject, manifests: Dictionary, folders: Dictionary) -> Array:
	var out: Array = []
	var scen: Array = project.get_value("scenarios", [])
	if scen.is_empty():
		return out
	var core := AdvCore.new()
	core.setup(project.core_config())
	core.assets.folders = folders
	for root in manifests:
		core.assets.add_manifest(manifests[root], root)
		var manual := String(root) + "/" + MANUAL_NAME
		if FileAccess.file_exists(manual):
			var d = AdvJson.load_file(manual)
			if d is Dictionary:
				core.assets.add_manifest(d, root)
	core.use_adapter(AdvJsonAdapter.new())
	core.load_scenario(PackedStringArray(scen))
	for d in core.validate():
		if d["code"] == "ASSET_NOT_FOUND":
			d["severity"] = "error"
		out.append(d)
	return out
