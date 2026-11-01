class_name AdvAssets
extends RefCounted
## 素材の解決（5.5）。素材フォルダごとに manifest.auto.json（自動生成）と manifest.json（手書き）を読み、
## プロジェクト → テンプレート → シナリオ の順に重ねる。後に読んだものが同じIDを上書きする。
##
## 実行中はフォルダを読まない。ただしデバッグビルドで manifest.auto.json がないときだけ、
## 警告を出したうえでフォルダを読んで補う。

## 最上位フォルダ名 → 種類（プロジェクト設定 asset_folders で追加・変更できる）
const DEFAULT_FOLDERS := {
	"bg": "image", "chara": "image", "cg": "image", "ui": "image",
	"bgm": "bgm", "se": "se", "voice": "voice", "font": "font", "shader": "shader",
}

var folders: Dictionary = DEFAULT_FOLDERS
var missing_asset: String = "placeholder"   ## placeholder / error
var preset_id: String = ""                  ## 例 "98.640x400"
var group: String = ""                      ## 例 "pc80"
var roots: PackedStringArray = []

var _entries: Dictionary = {}   ## 種類 → {ID → エントリ（パスは絶対パス）}
var _warned: Dictionary = {}


## 素材フォルダを1つ重ねる。
func add_root(root: String, diags: Array = []) -> void:
	var r := root.trim_suffix("/")
	roots.append(r)
	var auto_path := r + "/" + AdvManifestGenerator.AUTO_NAME
	if FileAccess.file_exists(auto_path):
		var d = AdvJson.load_file(auto_path, diags)
		if d is Dictionary:
			add_manifest(d, r)
	elif OS.is_debug_build() and DirAccess.dir_exists_absolute(r):
		AdvDiag.debug_warn("MANIFEST_MISSING", "manifest.auto.json がないので、フォルダを読んで補います: %s" % r,
			"manifest.auto.json is missing; scanning the folder instead: %s" % r)
		add_manifest(AdvManifestGenerator.scan(r, folders)["manifest"], r)
	var manual_path := r + "/" + AdvManifestGenerator.MANUAL_NAME
	if FileAccess.file_exists(manual_path):
		var d = AdvJson.load_file(manual_path, diags)
		if d is Dictionary:
			add_manifest(d, r)


## マニフェストの中身を重ねる。root はマニフェストのあるフォルダ。
func add_manifest(manifest: Dictionary, root: String) -> void:
	var base := AdvManifestGenerator.base_dir(manifest, root)
	var assets: Dictionary = manifest.get("assets", {})
	for key in assets:
		var e = assets[key]
		if not e is Dictionary:
			continue
		var kind := String(e.get("type", ""))
		var id := String(key)
		var colon := id.find(":")
		if colon >= 0:
			if kind == "":
				kind = id.substr(0, colon)
			id = id.substr(colon + 1)
		if kind == "":
			kind = "image"
		var abs_e := _absolute(e, base)
		if not _entries.has(kind):
			_entries[kind] = {}
		var cur = _entries[kind].get(id)
		_entries[kind][id] = AdvJson.merge(cur, abs_e) if cur is Dictionary else abs_e


func _absolute(e: Dictionary, base: String) -> Dictionary:
	var r := e.duplicate(true)
	if r.has("file"):
		r["file"] = _join(base, String(r["file"]))
	if r.has("variants"):
		for k in r["variants"]:
			r["variants"][k] = _join(base, String(r["variants"][k]))
	if r.has("by_preset"):
		for k in r["by_preset"]:
			var v = r["by_preset"][k]
			r["by_preset"][k] = _join(base, v) if v is String else _absolute(v, base)
	return r


static func _join(base: String, p: String) -> String:
	if p.contains("://"):
		return p
	return base + "/" + p


## 1つだけ登録する（テストや、コードから素材を足すとき用）。
func register(kind: String, id: String, path: String) -> void:
	if not _entries.has(kind):
		_entries[kind] = {}
	_entries[kind][id] = {"type": kind, "file": path}


## 画面プリセットを設定する（機種別の差し替えに使う）。
func set_preset(full_id: String, group_id: String) -> void:
	preset_id = full_id
	group = group_id


## ID かパスから、読み込むパスを返す。見つからなければ空文字。
## 機種別の差し替えは「98.640x400 のような完全一致 → 機種ID → グループID → file」の順に探す。
func resolve(kind: String, id: String, variant: String = "") -> String:
	if id.begins_with("res://") or id.begins_with("user://") or id.contains("/"):
		var p := id if id.contains("://") else "res://" + id
		return p if _exists(p) else ""
	var e = _entries.get(kind, {}).get(id)
	if not e is Dictionary:
		return ""
	var bp: Dictionary = e.get("by_preset", {})
	for key in [preset_id, preset_id.get_slice(".", 0), group]:
		if key == "" or not bp.has(key):
			continue
		var v = bp[key]
		if v is String:
			if variant == "":
				return v
		elif v is Dictionary:
			if variant != "" and v.get("variants", {}).has(variant):
				return String(v["variants"][variant])
			if variant == "" and v.has("file"):
				return String(v["file"])
	if variant != "":
		if e.get("variants", {}).has(variant):
			return String(e["variants"][variant])
		_warn_once("VARIANT_NOT_FOUND:%s:%s@%s" % [kind, id, variant],
			"差分が見つからないので既定のファイルを使います: %s@%s" % [id, variant],
			"Variant not found; using the default file: %s@%s" % [id, variant])
	return String(e.get("file", ""))


func has(kind: String, id: String) -> bool:
	if id.begins_with("res://") or id.begins_with("user://") or id.contains("/"):
		return resolve(kind, id) != ""
	return _entries.get(kind, {}).has(id)


func ids(kind: String) -> PackedStringArray:
	return PackedStringArray(_entries.get(kind, {}).keys())


## 素材が見つからないときの処理。missing_asset が error なら true を返す（呼び出し側で止める）。
func report_missing(kind: String, id: String) -> bool:
	_warn_once("MISSING:%s:%s" % [kind, id], "素材が見つかりません: %s（%s）" % [id, kind],
		"Asset not found: %s (%s)" % [id, kind])
	if missing_asset == "error":
		push_error("[adv80s] ASSET_NOT_FOUND: %s (%s)" % [id, kind])
		return true
	return false


func _warn_once(key: String, ja: String, en: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	AdvDiag.debug_warn("ASSET_NOT_FOUND", ja, en)


static func _exists(p: String) -> bool:
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)
