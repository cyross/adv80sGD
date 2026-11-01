@tool
extends EditorExportPlugin
## ゲームの書き出しへの割り込み。
## - 書き出しの直前に manifest.auto.json を必ず生成し直す
## - JSON は素材ではないので、そのままだと書き出しに含まれない。すべての JSON を含める

var plugin: EditorPlugin

const _SKIP_DIRS := [".godot", ".vscode", ".git", ".import"]


func _get_name() -> String:
	return "adv80s"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if plugin != null and plugin.has_method("generate"):
		var res: Dictionary = plugin.generate()
		for d in res.get("diags", []):
			if d["severity"] == "error":
				push_error("[adv80s] %s: %s (%s %s)" % [d["code"], d["message"], d.get("file", ""), d.get("path", "")])
	var files: Array = []
	_collect("res://", files)
	for f in files:
		add_file(f, FileAccess.get_file_as_bytes(f), false)


func _collect(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_directories():
		if name in _SKIP_DIRS or name.begins_with("."):
			continue
		_collect(dir_path.path_join(name), out)
	for file in dir.get_files():
		if file.get_extension().to_lower() == "json" and not file.begins_with("."):
			out.append(dir_path.path_join(file))
