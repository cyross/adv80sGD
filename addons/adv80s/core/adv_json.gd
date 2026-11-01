class_name AdvJson
extends RefCounted
## JSONの読み込みと、層の重ね合わせ（後の層が上書き、null で取り除く）の共通処理。


## JSONファイルを読む。失敗したら null を返し、diags に診断を追加する。
static func load_file(path: String, diags: Array = []) -> Variant:
	if not FileAccess.file_exists(path):
		diags.append(AdvDiag.make("error", "ASSET_NOT_FOUND", "ファイルが見つかりません: %s" % path,
			"File not found: %s" % path, path))
		return null
	var text := FileAccess.get_file_as_string(path)
	return parse_text(text, path, diags)


## JSON文字列を読む。失敗したら null。
static func parse_text(text: String, path: String = "", diags: Array = []) -> Variant:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		var d := AdvDiag.make("error", "JSON_PARSE",
			"JSONの書き方に誤りがあります: %s" % json.get_error_message(),
			"JSON parse error: %s" % json.get_error_message(), path)
		d["line"] = json.get_error_line()
		diags.append(d)
		return null
	return json.data


## base に over を重ねた新しい辞書を返す。
## 辞書どうしは項目ごとに再帰的に重ね、値が null の項目は取り除く。配列や値は丸ごと置き換える。
static func merge(base: Variant, over: Variant) -> Variant:
	if over == null:
		return null
	if base is Dictionary and over is Dictionary:
		var result: Dictionary = (base as Dictionary).duplicate(true)
		for key in over:
			var v = over[key]
			if v == null:
				result.erase(key)
			elif result.has(key):
				result[key] = merge(result[key], v)
			else:
				result[key] = _strip_nulls(v)
		return result
	return _strip_nulls(over)


## 1段だけ重ねる（項目単位の置き換え。動詞・型ごとの上書きに使う）。
static func merge_shallow(base: Dictionary, over: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in over:
		if over[key] == null:
			result.erase(key)
		else:
			result[key] = _strip_nulls(over[key])
	return result


static func _strip_nulls(v: Variant) -> Variant:
	if v is Dictionary:
		var r := {}
		for k in v:
			if v[k] != null:
				r[k] = _strip_nulls(v[k])
		return r
	if v is Array:
		var a := []
		for x in v:
			a.append(_strip_nulls(x))
		return a
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		# JSON の数値は float で読まれるので、整数値は int にそろえる
		return int(v)
	return v
