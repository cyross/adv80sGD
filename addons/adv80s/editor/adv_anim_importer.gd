@tool
extends EditorImportPlugin
## アニメーション画像（.gif、.apng、.mng）を読み込む（Godot にはこれらを読む機能がないため）。
## AdvImageFrames（各コマの画像、表示時間、繰り返し回数）として保存する。静止画もコマが1つの AdvImageFrames になる。


func _get_importer_name() -> String:
	return "adv80s.anim_image"


func _get_visible_name() -> String:
	return "adv80s アニメーション画像"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gif", "apng", "mng"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_i: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(_path: String, _option: StringName, _options: Dictionary) -> bool:
	return true


## Godot の画像の読み込み（texture）も .apng を受け持とうとするので、こちらを優先する。
func _get_priority() -> float:
	return 2.0


func _get_import_order() -> int:
	return 0


func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String],
		_gen_files: Array[String]) -> Error:
	var res := AdvGif.load_frames(source_file) if source_file.get_extension().to_lower() == "gif" else AdvPngAnim.load_frames(source_file)
	if res == null:
		return ERR_PARSE_ERROR
	return ResourceSaver.save(res, "%s.%s" % [save_path, _get_save_extension()])
