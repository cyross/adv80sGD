@tool
extends EditorExportPlugin
## ゲームの書き出しへの割り込み。
## - 書き出しの直前に manifest.auto.json を必ず生成し直す
## - JSON は素材ではないので、そのままだと書き出しに含まれない。すべての JSON を含める
## - セーブの元鍵（環境変数 ADV80S_MASTER_KEY か master.key）を、平文ではない形で res://adv80s_key.bin として含める
##   （master.key そのものは含めない）
## - 配布用（非デバッグ）エクスポート時は res://addons/adv80s/debug/ 配下のデバッグ専用機能を除外する

var plugin: EditorPlugin
var _is_debug_export: bool = true

const _SKIP_DIRS := [".godot", ".vscode", ".git", ".import"]
const _DEBUG_DIR_PREFIX := "res://addons/adv80s/debug/"


func _get_name() -> String:
	return "adv80s"


func _export_begin(_features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
	_is_debug_export = is_debug
	if plugin != null and plugin.has_method("generate"):
		var res: Dictionary = plugin.generate()
		for d in res.get("diags", []):
			if d["severity"] == "error":
				push_error("[adv80s] %s: %s (%s %s)" % [d["code"], d["message"], d.get("file", ""), d.get("path", "")])
	var files: Array = []
	_collect("res://", files)
	for f in files:
		add_file(f, FileAccess.get_file_as_bytes(f), false)
	var key := AdvEmbeddedKeyProvider.find_master_key()
	if key.size() == 32:
		add_file(AdvEmbeddedKeyProvider.EMBEDDED_FILE, AdvEmbeddedKeyProvider.mask(key), false)
	else:
		push_warning("[adv80s] セーブの鍵がないまま書き出します。製品版ではセーブできません（ツールメニュー「adv80s: セーブの鍵を生成」）")


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if not _is_debug_export and path.begins_with(_DEBUG_DIR_PREFIX):
		skip()


func _collect(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_directories():
		if name in _SKIP_DIRS or name.begins_with("."):
			continue
		var sub_path := dir_path.path_join(name)
		if not _is_debug_export and (sub_path == "res://addons/adv80s/debug" or sub_path.begins_with(_DEBUG_DIR_PREFIX)):
			continue
		_collect(sub_path, out)
	for file in dir.get_files():
		if file.get_extension().to_lower() == "json" and not file.begins_with("."):
			out.append(dir_path.path_join(file))
