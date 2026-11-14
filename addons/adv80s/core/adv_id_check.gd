class_name AdvIdCheck
extends RefCounted
## 設定の中の素材・シーンの ID を確かめる（シナリオエディタの「ID の確認」と、デバッグ実行の起動時に使う）。

## 項目の道筋（キーだけ）から、素材の種類（image・bgm・se）を決める。素材でなければ ""。
static func asset_kind_of(keys: Array) -> String:
	if keys.is_empty():
		return ""
	var last := String(keys[keys.size() - 1])
	if keys in [["title_image"], ["title_variants", "image"], ["variants", "image"], ["fin", "image"], ["image"],
			["extras", "gallery", "id"], ["extras", "gallery", "images"], ["extras", "gallery", "thumb"]]:
		return "image"
	if keys in [["title_bgm"], ["title_variants", "bgm"], ["variants", "bgm"], ["bgm"], ["extras", "music", "id"]]:
		return "bgm"
	if last == "image" and keys.size() >= 2 and keys[0] in ["fin", "credits"]:
		return "image"
	if (last == "icon" and keys[0] in ["items", "notices"]) or keys == ["extras", "notify_icon"]:
		return "image"
	if keys == ["notice_style", "se"]:
		return "se"
	return ""


## プロジェクト設定の素材の ID を確かめて、見つからないものの診断を返す。has_asset は func(kind, id) -> bool。
static func check_project(data: Dictionary, has_asset: Callable, file: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_walk(data, [], has_asset, file, out)
	return out


static func _walk(v: Variant, path: Array, has_asset: Callable, file: String, out: Array[Dictionary]) -> void:
	if v is Dictionary:
		for k in v:
			_walk(v[k], path + [k], has_asset, file, out)
	elif v is Array:
		for i in v.size():
			_walk(v[i], path + [i], has_asset, file, out)
	elif v is String and v != "":
		var kind := asset_kind_of(path.filter(func(p): return p is String))
		if kind == "":
			return
		var id: String = v.get_slice("@", 0) if kind == "image" else v
		if not has_asset.call(kind, id):
			var ptr := "/" + "/".join(path.map(func(p): return str(p)))
			out.append(AdvDiag.make("warning", "ASSET_NOT_FOUND", "素材が見つかりません: %s（%s）" % [v, kind],
				"Asset not found: %s (%s)" % [v, kind], file, ptr))
