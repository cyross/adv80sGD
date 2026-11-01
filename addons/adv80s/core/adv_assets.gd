class_name AdvAssets
extends RefCounted
## 素材の解決（5.5）。段階1では、素材フォルダを走査してIDを付ける自動登録と、
## パス（res:// で始まるか "/" を含む）の直接指定だけを扱う。マニフェストは段階2で追加する。

## 最上位フォルダ名 → 種類
const DEFAULT_FOLDERS := {
	"bg": "image", "chara": "image", "cg": "image", "ui": "image",
	"bgm": "bgm", "se": "se", "voice": "voice", "font": "font", "shader": "shader",
}
const _IMAGE_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga"]
const _AUDIO_EXT := ["ogg", "wav", "mp3"]

var _table: Dictionary = {}  ## 種類 → {ID → パス}


func register(kind: String, id: String, path: String) -> void:
	if not _table.has(kind):
		_table[kind] = {}
	_table[kind][id] = path


## フォルダの決まりに従って素材を登録する。
## ID は種類のフォルダからの相対パス（拡張子なし、"/" は "."）。例：bg/hallway.png → image の "bg.hallway"
func scan(root: String, folders: Dictionary = DEFAULT_FOLDERS) -> void:
	_scan_dir(root.trim_suffix("/"), "", folders)


func _scan_dir(dir_path: String, rel: String, folders: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_directories():
		if name.begins_with("_") or name.begins_with("."):
			continue
		_scan_dir(dir_path + "/" + name, (rel + "/" + name).trim_prefix("/"), folders)
	for file in dir.get_files():
		if file.begins_with("_") or file.begins_with("."):
			continue
		var f := file.trim_suffix(".import").trim_suffix(".remap")
		var ext := f.get_extension().to_lower()
		if not (ext in _IMAGE_EXT or ext in _AUDIO_EXT or ext in ["ttf", "otf", "fnt", "gdshader"]):
			continue
		var rel_file := (rel + "/" + f.get_basename()).trim_prefix("/")
		var top := rel_file.get_slice("/", 0)
		if not folders.has(top):
			continue
		var kind: String = folders[top]
		var id := rel_file.replace("/", ".")
		if kind != "image":
			id = id.trim_prefix(top + ".")
		register(kind, id, dir_path + "/" + f)


## ID かパスから、読み込むパスを返す。見つからなければ空文字。
func resolve(kind: String, id: String) -> String:
	if id.begins_with("res://") or id.begins_with("user://") or id.contains("/"):
		var p := id if id.contains("://") else "res://" + id
		return p if ResourceLoader.exists(p) or FileAccess.file_exists(p) else ""
	return String(_table.get(kind, {}).get(id, ""))


func has(kind: String, id: String) -> bool:
	return resolve(kind, id) != ""
