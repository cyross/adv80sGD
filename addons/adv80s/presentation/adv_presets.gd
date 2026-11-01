class_name AdvPresets
extends RefCounted
## 画面プリセット（7.1）。ID は「機種ID.モード名」。機種IDだけなら代表モード。
## 段階1では 98 だけを収録する。

const PATH := "res://addons/adv80s/presets/presets.json"

static var _data: Dictionary = {}


static func _load() -> void:
	if _data.is_empty():
		var d = AdvJson.load_file(PATH)
		_data = d if d is Dictionary else {}


## プリセットを解決する。{id, machine, mode, group, size, palette, pixel_aspect} を返す。見つからなければ空。
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
	return {
		"id": "%s.%s" % [machine, mode],
		"machine": machine,
		"mode": mode,
		"group": String(mdef.get("group", "")),
		"size": Vector2i(int(size[0]), int(size[1])),
		"palette": palette,
		"pixel_aspect": float(def.get("pixel_aspect", 1.0)),
	}


static func group_def(group_id: String) -> Dictionary:
	_load()
	return _data.get("groups", {}).get(group_id, {})
