@tool
class_name AdvScenarioModel
extends RefCounted
## シナリオエディタのデータ（6.8）。シナリオ・チャプター・シーンを、シナリオのフォルダのファイルとして扱う。
##
##   <シナリオのフォルダ>/                  … 既定 res://game/scenario（プロジェクト設定 ext.adv80s_editor.scenario_root）
##     <シナリオID>/                        … シナリオ
##       _scenario.scenario.json            … シナリオ共通の設定（start、characters、variables、items、verbs、assets など）
##       <チャプターID>.scenario.json       … チャプター（チャプターの設定、scenes、dialogues）
##   シナリオとチャプターの表示名と並び順は ext.adv80s_editor（name、chapter_order）に書く（ゲームは読まない）。
##       ink/<名前>.ink、<名前>.ink.json     … Ink のセリフ
##     <ファイル>.scenario.json             … フォルダに分けていない古い形のファイル（シナリオ「（フォルダの外）」のチャプターとして扱う）
##
## 実行のときは、これらのファイルをまとめて読む（プロジェクト設定の scenarios を、この形に合わせて書き直す）。
## 並び順は、シナリオはプロジェクト設定の ext.adv80s_editor.scenario_order、チャプターはシナリオ共通の設定の
## ext.adv80s_editor.chapter_order、シーンはチャプターのファイルの scenes に書いた順。

const MAIN_FILE := "_scenario.scenario.json"
const EXT := ".scenario.json"
const LOOSE_ID := "_loose"           ## フォルダの外のファイルをまとめたシナリオのID
const DEFAULT_ROOT := "res://game/scenario"
const EXT_KEY := "adv80s_editor"

var project_path: String = AdvProject.DEFAULT_PATH
var root: String = DEFAULT_ROOT
var errors: Array = []               ## 最後の操作で起きたこと（表示用）


func _init(p_project_path: String = AdvProject.DEFAULT_PATH) -> void:
	project_path = p_project_path
	root = stored_root()


# ---------------------------------------------------------------- シナリオのフォルダ

## プロジェクト設定に書いたシナリオのフォルダ。なければ scenarios の最初のファイルから決める（なければ ""）。
func stored_root() -> String:
	var p := _project()
	var r := String(p.get("ext", {}).get(EXT_KEY, {}).get("scenario_root", ""))
	if r != "":
		return r.trim_suffix("/")
	for s in p.get("scenarios", []):
		var path := String(s)
		if path.ends_with(EXT):
			var dir := path.get_base_dir()
			# <root>/<シナリオ>/x.scenario.json の形なら、その上
			if FileAccess.file_exists(dir + "/" + MAIN_FILE):
				return dir.get_base_dir()
			return dir
	return ""


## シナリオのフォルダを決めて、プロジェクト設定に書く（フォルダがなければ作る）。
func set_root(path: String) -> Error:
	path = path.strip_edges().trim_suffix("/")
	if path == "":
		return ERR_INVALID_PARAMETER
	if not path.begins_with("res://"):
		path = "res://" + path.trim_prefix("/")
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return err
	root = path
	var p := _project()
	var ext: Dictionary = p.get("ext", {})
	var mine: Dictionary = ext.get(EXT_KEY, {})
	mine["scenario_root"] = path
	ext[EXT_KEY] = mine
	p["ext"] = ext
	_save_json(project_path, p)
	return OK


func has_root() -> bool:
	return root != "" and DirAccess.dir_exists_absolute(root)


# ---------------------------------------------------------------- 一覧

## シナリオの一覧 [{id, name, dir, main, loose}]（並び順どおり）。
func scenarios() -> Array:
	var out := []
	if not has_root():
		return out
	var d := DirAccess.open(root)
	if d == null:
		return out
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		var dir := root + "/" + sub
		var main := dir + "/" + MAIN_FILE
		# シナリオのファイルがないフォルダ（素材など）は出さない
		if not FileAccess.file_exists(main) and _files_in(dir).is_empty():
			continue
		var data: Dictionary = _load(main) if FileAccess.file_exists(main) else {}
		out.append({"id": sub, "name": _name_of(data, sub), "dir": dir, "main": main, "loose": false})
	var loose := _files_in(root)
	if not loose.is_empty():
		out.append({"id": LOOSE_ID, "name": "（フォルダの外のファイル）", "dir": root, "main": "", "loose": true})
	var order: Array = _project().get("ext", {}).get(EXT_KEY, {}).get("scenario_order", [])
	return _sorted(out, order)


func scenario(id: String) -> Dictionary:
	for s in scenarios():
		if s["id"] == id:
			return s
	return {}


## チャプターの一覧 [{id, name, path, scenes}]。
func chapters(scenario_id: String) -> Array:
	var s := scenario(scenario_id)
	if s.is_empty():
		return []
	var out := []
	for f in _files_in(String(s["dir"])):
		var data := _load(f)
		var cid := String(f.get_file().trim_suffix(EXT))
		out.append({"id": cid, "name": _name_of(data, cid), "path": f,
			"scenes": (data.get("scenes", {}) as Dictionary).size() + (1 if data.has("scene") else 0)})
	var order: Array = [] if s["loose"] else _load(String(s["main"])).get("ext", {}).get(EXT_KEY, {}).get("chapter_order", [])
	return _sorted(out, order)


func chapter(scenario_id: String, chapter_id: String) -> Dictionary:
	for c in chapters(scenario_id):
		if c["id"] == chapter_id:
			return c
	return {}


## シーンの一覧 [{id, name, image}]（ファイルに書いた順）。
func scenes(scenario_id: String, chapter_id: String) -> Array:
	var c := chapter(scenario_id, chapter_id)
	if c.is_empty():
		return []
	var data := _load(String(c["path"]))
	var out := []
	if data.has("scene"):
		out.append({"id": String(data["scene"]), "name": String(data.get("name", data["scene"])), "image": data.get("image"), "single": true})
	var sc: Dictionary = data.get("scenes", {})
	for id in sc:
		var v: Dictionary = sc[id] if sc[id] is Dictionary else {}
		out.append({"id": String(id), "name": String(v.get("name", id)), "image": v.get("image")})
	return out


## すべてのシーンのID（どのシナリオ・チャプターにあるか）。
func all_scene_ids() -> Dictionary:
	var out := {}
	for s in scenarios():
		for c in chapters(s["id"]):
			for sc in scenes(s["id"], c["id"]):
				out[sc["id"]] = {"scenario": s["id"], "chapter": c["id"]}
	return out


func all_dialogue_ids() -> Dictionary:
	var out := {}
	for s in scenarios():
		for c in chapters(s["id"]):
			for id in _load(String(c["path"])).get("dialogues", {}):
				out[String(id)] = {"scenario": s["id"], "chapter": c["id"]}
	return out


# ---------------------------------------------------------------- 読み書き

## そのレベルのデータ（シナリオ共通の設定・チャプターのファイル）。
func load_scenario_data(scenario_id: String) -> Dictionary:
	var s := scenario(scenario_id)
	return _load(String(s.get("main", ""))) if not s.is_empty() and not s["loose"] else {}


func save_scenario_data(scenario_id: String, data: Dictionary) -> Error:
	var s := scenario(scenario_id)
	if s.is_empty() or s["loose"]:
		return ERR_UNAVAILABLE
	return _save_json(String(s["main"]), data)


func load_chapter_data(scenario_id: String, chapter_id: String) -> Dictionary:
	var c := chapter(scenario_id, chapter_id)
	return _load(String(c["path"])) if not c.is_empty() else {}


func save_chapter_data(scenario_id: String, chapter_id: String, data: Dictionary) -> Error:
	var c := chapter(scenario_id, chapter_id)
	if c.is_empty():
		return ERR_DOES_NOT_EXIST
	return _save_json(String(c["path"]), data)


func chapter_path(scenario_id: String, chapter_id: String) -> String:
	return String(chapter(scenario_id, chapter_id).get("path", ""))


# ---------------------------------------------------------------- 作る・名前を変える

## シナリオを作る。ID は名前から作る（同じものがあれば番号を付ける）。最初のチャプターと開始のシーンも作る。
func create_scenario(name: String) -> String:
	if not has_root():
		return ""
	var id := _unique(_id_from(name, "scenario"), _scenario_ids())
	var dir := root + "/" + id
	DirAccess.make_dir_recursive_absolute(dir)
	var scene_id := _unique(id + "_start", all_scene_ids())
	_save_json(dir + "/" + MAIN_FILE, {"scenario_version": 1, "start": scene_id,
		"ext": {EXT_KEY: {"name": name, "chapter_order": ["chapter1"]}}})
	_save_json(dir + "/chapter1" + EXT, {"scenario_version": 1, "ext": {EXT_KEY: {"name": "第1章"}},
		"scenes": {scene_id: {"name": "はじまり", "enter": ["%s が はじまった。" % name]}}})
	_append_order(id)
	sync_project()
	return id


func create_chapter(scenario_id: String, name: String) -> String:
	var s := scenario(scenario_id)
	if s.is_empty():
		return ""
	var ids := {}
	for c in chapters(scenario_id):
		ids[c["id"]] = true
	var id := _unique(_id_from(name, "chapter"), ids)
	_save_json(String(s["dir"]) + "/" + id + EXT, {"scenario_version": 1, "ext": {EXT_KEY: {"name": name}}, "scenes": {}})
	_add_chapter_order(scenario_id, id)
	sync_project()
	return id


func create_scene(scenario_id: String, chapter_id: String, name: String) -> String:
	var data := load_chapter_data(scenario_id, chapter_id)
	if data.is_empty() and chapter(scenario_id, chapter_id).is_empty():
		return ""
	var id := _unique(_id_from(name, "scene"), all_scene_ids())
	var sc: Dictionary = data.get("scenes", {})
	sc[id] = {"name": name, "enter": []}
	data["scenes"] = sc
	save_chapter_data(scenario_id, chapter_id, data)
	return id


## 表示名を変える（ID は変えない。ID を参照している手順が壊れないように）。
func rename(level: String, ids: Array, name: String) -> Error:
	match level:
		"scenario":
			if ids[0] == LOOSE_ID:
				return ERR_UNAVAILABLE
			var d := load_scenario_data(ids[0])
			_set_ext(d, "name", name)
			return save_scenario_data(ids[0], d)
		"chapter":
			var d := load_chapter_data(ids[0], ids[1])
			_set_ext(d, "name", name)
			return save_chapter_data(ids[0], ids[1], d)
		"scene":
			var d := load_chapter_data(ids[0], ids[1])
			if String(d.get("scene", "")) == ids[2]:
				d["name"] = name
			else:
				var sc: Dictionary = d.get("scenes", {})
				if not sc.has(ids[2]):
					return ERR_DOES_NOT_EXIST
				sc[ids[2]]["name"] = name
			return save_chapter_data(ids[0], ids[1], d)
	return ERR_INVALID_PARAMETER


# ---------------------------------------------------------------- 消す

## 消す。ファイルとフォルダは OS のごみ箱へ移す（エディタの中では元に戻せるように）。
func delete_scenarios(ids: Array) -> void:
	for id in ids:
		var s := scenario(String(id))
		if s.is_empty() or s["loose"]:
			continue
		_trash(String(s["dir"]))
		_remove_order(String(id))
	sync_project()


func delete_chapters(scenario_id: String, ids: Array) -> void:
	for id in ids:
		var p := chapter_path(scenario_id, String(id))
		if p != "":
			_trash(p)
	var s := scenario(scenario_id)
	if not s.is_empty() and not s["loose"]:
		var d := load_scenario_data(scenario_id)
		var order: Array = d.get("ext", {}).get(EXT_KEY, {}).get("chapter_order", [])
		for id in ids:
			order.erase(id)
		_set_ext(d, "chapter_order", order)
		save_scenario_data(scenario_id, d)
	sync_project()


func delete_scenes(scenario_id: String, chapter_id: String, ids: Array) -> void:
	var d := load_chapter_data(scenario_id, chapter_id)
	var sc: Dictionary = d.get("scenes", {})
	for id in ids:
		sc.erase(id)
	save_chapter_data(scenario_id, chapter_id, d)


# ---------------------------------------------------------------- 複写

## シナリオを count 個ずつ複写する。シーンと会話の ID は新しくし、シナリオの中の参照も付け替える。返り値は作ったID。
func duplicate_scenarios(ids: Array, count: int = 1) -> Array:
	var made := []
	for id in ids:
		var s := scenario(String(id))
		if s.is_empty() or s["loose"]:
			continue
		for n in count:
			var new_id := _unique(String(id) + "_copy", _scenario_ids())
			var dir := root + "/" + new_id
			DirAccess.make_dir_recursive_absolute(dir)
			var files := {}   # 元のパス → データ
			files[String(s["main"])] = load_scenario_data(String(id))
			for c in chapters(String(id)):
				files[String(c["path"])] = _load(String(c["path"]))
			var maps := _new_id_maps(files.values())
			for path in files:
				var d: Dictionary = _remap(files[path], maps)
				if path == s["main"]:
					_set_ext(d, "name", _name_of(d, String(id)) + " のコピー")
				_save_json(dir + "/" + String(path).get_file(), d)
			_copy_dir(String(s["dir"]) + "/ink", dir + "/ink")
			_append_order(new_id)
			made.append(new_id)
	sync_project()
	return made


## チャプターを count 個ずつ複写する（to_scenario を渡すと、そのシナリオへ）。
func duplicate_chapters(scenario_id: String, ids: Array, count: int = 1, to_scenario: String = "") -> Array:
	var target := scenario(to_scenario if to_scenario != "" else scenario_id)
	if target.is_empty():
		return []
	var made := []
	for id in ids:
		var src := load_chapter_data(scenario_id, String(id))
		if src.is_empty():
			continue
		for n in count:
			var existing := {}
			for c in chapters(String(target["id"])):
				existing[c["id"]] = true
			var new_id := _unique(String(id) if target["id"] != scenario_id else String(id) + "_copy", existing)
			var d: Dictionary = _remap(src, _new_id_maps([src]))
			if target["id"] == scenario_id:
				_set_ext(d, "name", _name_of(d, String(id)) + " のコピー")
			_save_json(String(target["dir"]) + "/" + new_id + EXT, d)
			if not target["loose"]:
				_add_chapter_order(String(target["id"]), new_id)
			made.append(new_id)
	sync_project()
	return made


## シーンを count 個ずつ複写する（別のシナリオ・チャプターへも）。
func duplicate_scenes(scenario_id: String, chapter_id: String, ids: Array, count: int = 1,
		to_scenario: String = "", to_chapter: String = "") -> Array:
	var ts := to_scenario if to_scenario != "" else scenario_id
	var tc := to_chapter if to_chapter != "" else chapter_id
	var src := load_chapter_data(scenario_id, chapter_id)
	var dst := src if (ts == scenario_id and tc == chapter_id) else load_chapter_data(ts, tc)
	if src.is_empty() or (dst.is_empty() and chapter(ts, tc).is_empty()):
		return []
	var made := []
	var taken := all_scene_ids()
	var dst_scenes: Dictionary = dst.get("scenes", {})
	for id in ids:
		var scene = src.get("scenes", {}).get(id)
		if scene == null and String(src.get("scene", "")) == id:
			scene = _single_scene_body(src)
		if not scene is Dictionary:
			continue
		for n in count:
			var new_id := _unique(String(id) + "_copy", taken)
			taken[new_id] = true
			var copy: Dictionary = _remap(scene, {"scenes": {String(id): new_id}, "dialogues": {}})
			copy["name"] = String(copy.get("name", id)) + " のコピー"
			dst_scenes[new_id] = copy
			made.append(new_id)
	dst["scenes"] = dst_scenes
	save_chapter_data(ts, tc, dst)
	return made


# ---------------------------------------------------------------- プロジェクト設定と合わせる

## プロジェクト設定の scenarios を、シナリオのフォルダのファイルに合わせて書き直す。
## フォルダの外にあるファイル（ほかの場所の Ink など）はそのまま残す。
func sync_project() -> void:
	if not has_root():
		return
	var p := _project()
	# フォルダの外のファイルと、フォルダの直下の古い形のファイルは、元の順のまま残す（start は最後のファイルのものになるため）
	var keep := []
	for f in p.get("scenarios", []):
		var fs := String(f)
		if not FileAccess.file_exists(fs):
			continue
		if not fs.begins_with(root + "/") or fs.get_base_dir() == root:
			keep.append(f)
	var files := []
	for s in scenarios():
		if s["loose"]:
			for c in chapters(s["id"]):
				if not c["path"] in keep:
					files.append(c["path"])
			continue
		if FileAccess.file_exists(String(s["main"])):
			files.append(s["main"])
		for c in chapters(s["id"]):
			files.append(c["path"])
		for f in _ink_json_in(String(s["dir"]) + "/ink"):
			files.append(f)
	p["scenarios"] = keep + files
	# 開始シーン：空か、もうないシーンなら、最初のシナリオの start にする
	var entry := String(p.get("entry", ""))
	if entry == "" or not all_scene_ids().has(entry):
		for s in scenarios():
			if not s["loose"]:
				var st := String(load_scenario_data(s["id"]).get("start", ""))
				if st != "":
					p["entry"] = st
					break
	_save_json(project_path, p)


# ---------------------------------------------------------------- 並び順

func _append_order(id: String) -> void:
	var p := _project()
	var ext: Dictionary = p.get("ext", {})
	var mine: Dictionary = ext.get(EXT_KEY, {})
	var order: Array = mine.get("scenario_order", [])
	if not id in order:
		order.append(id)
	mine["scenario_order"] = order
	ext[EXT_KEY] = mine
	p["ext"] = ext
	_save_json(project_path, p)


func _remove_order(id: String) -> void:
	var p := _project()
	var order: Array = p.get("ext", {}).get(EXT_KEY, {}).get("scenario_order", [])
	if id in order:
		order.erase(id)
		_save_json(project_path, p)


func _add_chapter_order(scenario_id: String, id: String) -> void:
	var d := load_scenario_data(scenario_id)
	if d.is_empty():
		return
	var order: Array = d.get("ext", {}).get(EXT_KEY, {}).get("chapter_order", [])
	if not id in order:
		order.append(id)
	_set_ext(d, "chapter_order", order)
	save_scenario_data(scenario_id, d)


static func _set_ext(d: Dictionary, key: String, value: Variant) -> void:
	var ext: Dictionary = d.get("ext", {})
	var mine: Dictionary = ext.get(EXT_KEY, {})
	mine[key] = value
	ext[EXT_KEY] = mine
	d["ext"] = ext


## シナリオ・チャプターの表示名（ext.adv80s_editor.name。シーン1つのファイルなら name）。
static func _name_of(d: Dictionary, fallback: String) -> String:
	var n = d.get("ext", {}).get(EXT_KEY, {}).get("name") if d.get("ext") is Dictionary else null
	if n == null and d.has("scene"):
		n = d.get("name")
	return String(n) if n != null and String(n) != "" else fallback


static func _sorted(list: Array, order: Array) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a, b):
		var ia := order.find(a["id"])
		var ib := order.find(b["id"])
		if ia < 0 and ib < 0:
			return String(a["id"]) < String(b["id"])
		if ia < 0 or ib < 0:
			return ia >= 0
		return ia < ib)
	return out


# ---------------------------------------------------------------- ID の付け替え

## 複写するファイルの中のシーンと会話に、新しい ID を割り当てる。
func _new_id_maps(datas: Array) -> Dictionary:
	var scenes_taken := all_scene_ids()
	var dlg_taken := all_dialogue_ids()
	var maps := {"scenes": {}, "dialogues": {}}
	for d in datas:
		var ids := []
		if d.has("scene"):
			ids.append(String(d["scene"]))
		for id in d.get("scenes", {}):
			ids.append(String(id))
		for id in ids:
			var n := _unique(id + "_copy", scenes_taken)
			scenes_taken[n] = true
			maps["scenes"][id] = n
		for id in d.get("dialogues", {}):
			var n := _unique(String(id) + "_copy", dlg_taken)
			dlg_taken[n] = true
			maps["dialogues"][String(id)] = n
	return maps


## データの中の、シーンと会話の ID への参照を付け替えた写しを返す。
## 付け替えるもの：scenes・dialogues のキー、exits のキー、goto、call、dialogue、start、scene、
## scene.goto の scene・id、条件の visited(…)・talked(…)・scene == …（文字の形とJSONの形）。
static func _remap(v: Variant, maps: Dictionary, key: String = "") -> Variant:
	var sm: Dictionary = maps.get("scenes", {})
	var dm: Dictionary = maps.get("dialogues", {})
	if v is Dictionary:
		var out := {}
		for k in v:
			var nk := String(k)
			if key == "scenes" or key == "exits":
				nk = String(sm.get(nk, nk))
			elif key == "dialogues":
				nk = String(dm.get(nk, nk))
			var val = v[k]
			match String(k):
				"goto":
					out[nk] = sm.get(val, dm.get(val, val)) if val is String else val
				"call", "dialogue", "talked":
					out[nk] = dm.get(val, val) if val is String else val
				"start", "scene", "visited":
					out[nk] = sm.get(val, val) if val is String else val
				"scene.goto":
					out[nk] = _remap_goto_args(val, sm)
				_:
					if String(k) == "args" and v.get("type") == "scene.goto":
						out[nk] = _remap_goto_args(val, sm)
					else:
						out[nk] = _remap(val, maps, String(k))
		return out
	if v is Array:
		return v.map(func(e): return _remap(e, maps, key))
	if v is String and (key in ["if", "when"] or String(v).contains("visited(") or String(v).contains("talked(")):
		return _remap_condition_text(String(v), sm, dm)
	return v


static func _remap_goto_args(val: Variant, sm: Dictionary) -> Variant:
	if not val is Dictionary:
		return val
	var o: Dictionary = val.duplicate(true)
	for k in ["scene", "id"]:
		if o.get(k) is String:
			o[k] = sm.get(o[k], o[k])
	return o


static func _remap_condition_text(s: String, sm: Dictionary, dm: Dictionary) -> String:
	var re := RegEx.create_from_string("(visited|talked)\\(\\s*([A-Za-z0-9_\\-]+)\\s*\\)|(scene\\s*==\\s*)([A-Za-z0-9_\\-]+)")
	var out := ""
	var at := 0
	for m in re.search_all(s):
		out += s.substr(at, m.get_start() - at)
		if m.get_string(1) != "":
			var map := sm if m.get_string(1) == "visited" else dm
			out += "%s(%s)" % [m.get_string(1), map.get(m.get_string(2), m.get_string(2))]
		else:
			out += m.get_string(3) + String(sm.get(m.get_string(4), m.get_string(4)))
		at = m.get_end()
	return out + s.substr(at)


static func _single_scene_body(d: Dictionary) -> Dictionary:
	var out := {}
	for k in ["name", "image", "image_transition", "first", "enter", "objects", "exits", "sprites", "on", "ext"]:
		if d.has(k):
			out[k] = d[k]
	return out


# ---------------------------------------------------------------- 下回り

func _project() -> Dictionary:
	var p = AdvJson.load_file(project_path) if FileAccess.file_exists(project_path) else null
	return p if p is Dictionary else {}


func _scenario_ids() -> Dictionary:
	var out := {}
	for s in scenarios():
		out[s["id"]] = true
	return out


static func _files_in(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(EXT) and f != MAIN_FILE:
			out.append(dir + "/" + f)
	out.sort()
	return out


static func _ink_json_in(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".ink.json"):
			out.append(dir + "/" + f)
	out.sort()
	return out


static func _load(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var d = AdvJson.load_file(path)
	return d if d is Dictionary else {}


static func _save_json(path: String, data: Variant) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	f.close()
	return OK


static func _save_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


static func _id_from(name: String, fallback: String) -> String:
	var id := AdvSetup.to_id(name)
	return fallback if id == "my_game" and not name.to_lower().contains("my") else id


static func _unique(base: String, taken: Dictionary) -> String:
	if not taken.has(base):
		return base
	var n := 2
	while taken.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


static func _trash(path: String) -> void:
	var g := ProjectSettings.globalize_path(path)
	if OS.move_to_trash(g) != OK:
		# ごみ箱がない環境（テストなど）では消す
		if DirAccess.dir_exists_absolute(path):
			_remove_dir(path)
		else:
			DirAccess.remove_absolute(path)


static func _remove_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_remove_dir(path + "/" + sub)
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


static func _copy_dir(from: String, to: String) -> void:
	var d := DirAccess.open(from)
	if d == null:
		return
	DirAccess.make_dir_recursive_absolute(to)
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		DirAccess.copy_absolute(from + "/" + f, to + "/" + f)
