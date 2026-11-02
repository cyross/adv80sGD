class_name AdvPresets
extends RefCounted
## 画面プリセット（7.1）。ID は「機種ID.モード名」。機種IDだけなら代表モード。
## presets.json は tools/build_presets.py で書き出す。

const PATH := "res://addons/adv80s/presets/presets.json"

static var _data: Dictionary = {}


static func _load() -> void:
	if _data.is_empty():
		var d = AdvJson.load_file(PATH)
		_data = d if d is Dictionary else {}


## プリセットを解決する。見つからなければ空。
## {id, machine, mode, group, size, palette, bits, pixel_aspect, line_double, visible, colors, filters}
static func resolve(preset_id: String) -> Dictionary:
	_load()
	var machine := preset_id.get_slice(".", 0)
	var mdef: Dictionary = _data.get("machines", {}).get(machine, {})
	if mdef.is_empty():
		return {}
	var mode := preset_id.substr(machine.length() + 1) if preset_id.contains(".") else String(mdef.get("default_mode", ""))
	var def: Dictionary = mdef.get("modes", {}).get(mode, {})
	if def.is_empty():
		return {}
	var palette := PackedColorArray()
	for c in def.get("palette", []):
		palette.append(Color.html(String(c)))
	var size: Array = def.get("size", [640, 400])
	var group := String(mdef.get("group", ""))
	var vis: Array = def.get("visible", [0, 0, int(size[0]), int(size[1])])
	var filters: Array = def.get("filters", mdef.get("filters", group_def(group).get("filters", [])))
	return {
		"id": "%s.%s" % [machine, mode],
		"machine": machine,
		"mode": mode,
		"group": group,
		"size": Vector2i(int(size[0]), int(size[1])),
		"palette": palette,
		"bits": def.get("bits", []),
		"pixel_aspect": float(def.get("pixel_aspect", 1.0)),
		"line_double": bool(def.get("line_double", false)),
		"visible": Rect2i(int(vis[0]), int(vis[1]), int(vis[2]), int(vis[3])),
		"colors": String(def.get("colors", "")),
		"filters": filters.duplicate(true),
	}


## 収録している機種ID。
static func machines() -> PackedStringArray:
	_load()
	return PackedStringArray(_data.get("machines", {}).keys())


static func modes(machine: String) -> PackedStringArray:
	_load()
	return PackedStringArray(_data.get("machines", {}).get(machine, {}).get("modes", {}).keys())


static func group_def(group_id: String) -> Dictionary:
	_load()
	return _data.get("groups", {}).get(group_id, {})
