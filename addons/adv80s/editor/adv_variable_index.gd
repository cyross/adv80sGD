@tool
class_name AdvVariableIndex
extends RefCounted
## 変数と定数の一覧（エディタの「変数の一覧」で使う）。
##
## 集めるもの：
## - JSON シナリオ：variables で宣言した変数と、宣言せずに読み書きしている変数（読む場所・書く場所つき）
## - Ink：変換した .ink.json のグローバル変数（VAR）。元の .ink があれば、VAR・CONST・LIST の行も読む（CONST は変換すると消えるため）
## - 組み込み：条件式でいつでも使える名前（scene、has(…) など）
##
## 1件の形：{name, kind, source, type, default, file, path, line, reads: [{file, path}], writes: [{file, path}], note}
##   kind：「変数」「定数」「リスト」「組み込み」
##   source：「JSON」「Ink」「組み込み」

const BUILTINS := [
	["scene", "いまのシーンのID（scene == hallway のように比べる）"],
	["preset", "画面プリセットのID（例 98.640x400。機種だけでも比べられる）"],
	["group", "機種のグループID"],
	["has(アイテム)", "アイテムを持っているか"],
	["count(アイテム)", "アイテムの個数"],
	["visited(シーン)", "そのシーンに入ったことがあるか"],
	["talked(会話)", "その会話をしたことがあるか"],
	["read(行ID)", "その文章を読んだことがあるか"],
	["chosen(選択肢/項目)", "その選択肢の項目を選んだことがあるか"],
	["feature(機能)", "モダン機能が有効か"],
]

const _INK_LINE := "^\\s*(VAR|CONST|LIST)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.*?)\\s*(//.*)?$"


static func collect(project_path: String = AdvProject.DEFAULT_PATH) -> Array:
	var diags: Array = []
	var project := AdvProject.load_project(project_path, diags)
	var core := AdvCore.new()
	core.setup(project.core_config())
	core.use_adapter(AdvJsonAdapter.new())
	core.load_scenario(PackedStringArray(project.get_value("scenarios", [])))
	var out: Array = []
	var json_names := {}
	var main = core.adapters_by_name.get("main")
	if main is AdvJsonAdapter:
		for e in main.variables_info():
			e["kind"] = "変数"
			e["source"] = "JSON"
			e["line"] = 0
			e["note"] = "" if e["declared"] else "宣言なし"
			if not e["declared"] and e["writes"].is_empty():
				e["note"] = "宣言も変更もなし"
			out.append(e)
			json_names[e["name"]] = true

	# JSON の変数のうち、Ink にも同じ名前があるもの
	var ink_names := {}
	var ink0 = core.adapters_by_name.get("ink")
	if ink0 != null:
		for f in ink0.files:
			for n in ink0.stories[f].globals:
				ink_names[n] = true
	for e in out:
		if ink_names.has(e["name"]):
			e["note"] = ("Ink と同期" if e["note"] == "" else e["note"] + "、Ink と同期")

	# Ink の元の .ink（あれば）
	var ink_src := {}
	for f in _ink_sources_for(PackedStringArray(project.get_value("scenarios", []))):
		for e in _parse_ink(f):
			e["note"] = "JSON と同期" if json_names.has(e["name"]) and e["kind"] == "変数" else ""
			out.append(e)
			ink_src[e["name"]] = true
	# 変換した .ink.json のグローバル変数（元の .ink に見つからなかったもの）
	var ink = core.adapters_by_name.get("ink")
	if ink != null:
		for f in ink.files:
			var s: AdvInkStory = ink.stories[f]
			for n in s.globals:
				if ink_src.has(n):
					continue
				var v = s.globals[n]
				out.append({"name": n, "kind": "変数", "source": "Ink", "type": type_name(v), "default": _value_text(v),
					"file": f, "path": "", "line": 0, "reads": [], "writes": [],
					"note": "JSON と同期" if json_names.has(n) else ""})

	for b in BUILTINS:
		out.append({"name": b[0], "kind": "組み込み", "source": "組み込み", "type": "", "default": null,
			"file": "", "path": "", "line": 0, "reads": [], "writes": [], "note": b[1]})
	return out


## シナリオの .ink.json の元になった .ink。ファイル名（拡張子を除いたもの）が同じものと、そこから INCLUDE しているもの。
static func _ink_sources_for(scenarios: PackedStringArray) -> PackedStringArray:
	var want := {}
	for sc in scenarios:
		if String(sc).ends_with(".ink.json"):
			want[String(sc).get_file().trim_suffix(".ink.json")] = true
	var all := _ink_sources()
	var out := PackedStringArray()
	for f in all:
		if want.has(f.get_file().trim_suffix(".ink")):
			out.append(f)
	var i := 0
	while i < out.size():
		for line in FileAccess.get_file_as_string(out[i]).split("\n"):
			var t := line.strip_edges()
			if t.begins_with("INCLUDE "):
				var inc := out[i].get_base_dir().path_join(t.substr(8).strip_edges())
				if FileAccess.file_exists(inc) and not inc in out:
					out.append(inc)
		i += 1
	return out


## res:// の下の .ink（addons と隠しフォルダは除く）。
static func _ink_sources(dir: String = "res://") -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".ink"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with(".") or (dir == "res://" and sub == "addons"):
			continue
		out.append_array(_ink_sources(dir.path_join(sub)))
	return out


static func _parse_ink(path: String) -> Array:
	var re := RegEx.create_from_string(_INK_LINE)
	var out := []
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var m := re.search(lines[i])
		if m == null:
			continue
		var kw := m.get_string(1)
		var val := m.get_string(3)
		out.append({"name": m.get_string(2), "kind": {"VAR": "変数", "CONST": "定数", "LIST": "リスト"}[kw], "source": "Ink",
			"type": _ink_type(val) if kw != "LIST" else "list", "default": val, "file": path, "path": "", "line": i + 1,
			"reads": [], "writes": []})
	return out


static func _ink_type(v: String) -> String:
	if v == "true" or v == "false":
		return "bool"
	if v.is_valid_int():
		return "int"
	if v.is_valid_float():
		return "float"
	if v.begins_with("\""):
		return "string"
	if v.begins_with("->"):
		return "divert"
	return ""


static func type_name(v: Variant) -> String:
	if v is bool:
		return "bool"
	if v is int:
		return "int"
	if v is float:
		return "float"
	if v is String:
		return "string"
	if v is AdvInkStory.DivertTarget:
		return "divert"
	return ""


static func _value_text(v: Variant) -> Variant:
	if v is AdvInkStory.DivertTarget:
		return "-> " + v.path
	return v
