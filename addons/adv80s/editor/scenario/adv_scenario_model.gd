@tool
class_name AdvScenarioModel
extends RefCounted

## シナリオエディタのデータ（6.8）。シナリオ・チャプター・シーンを、シナリオのフォルダのファイルとして扱う。
##
##   <シナリオのフォルダ>/                  … 既定 res://game/scenario（プロジェクト設定 ext.adv80s_editor.scenario_root）
##     <シナリオID>/                        … シナリオ
##       _scenario.scenario.json            … シナリオ共通の設定（start、characters、variables、items、verbs、assets など）
##       <チャプターID>.scenario.json       … チャプター（チャプターの設定、scenes、dialogues）
##       ink/<名前>.ink、<名前>.ink.json     … Ink のセリフ
##     <ファイル>.scenario.json             … フォルダに分けていない古い形のファイル（シナリオ「（フォルダの外）」のチャプターとして扱う）
##
## シナリオとチャプターの表示名と並び順は ext.adv80s_editor（name、chapter_order）に書く（ゲームは読まない）。
## 実行のときは、これらのファイルをまとめて読む（プロジェクト設定の scenarios を、この形に合わせて書き直す）。
## 並び順は、シナリオはプロジェクト設定の ext.adv80s_editor.scenario_order、チャプターはシナリオ共通の設定の
## ext.adv80s_editor.chapter_order、シーンはチャプターのファイルの scenes に書いた順。
##
## 元に戻す：ファイルを書き換える前の中身を、操作ごとにまとめて覚えておく（undo・redo）。覚えるのはこのモデルを
## 通した書き換えだけで、エディタを閉じると消える。

## ファイルを書いた（ひとまとまりの書き換え、元に戻す、やり直すのあと）
signal files_changed

const MAIN_FILE := "_scenario.scenario.json"
const EXT := ".scenario.json"
const LOOSE_ID := "_loose"           ## フォルダの外のファイルをまとめたシナリオのID
const DEFAULT_ROOT := "res://game/scenario"
const EXT_KEY := "adv80s_editor"
const MAX_HISTORY := 100
## シナリオ共通の設定に入れる項目（古い形のファイルを移すとき）。ほかはチャプターに入れる
const MAIN_KEYS := ["start", "variables", "constants", "characters", "items", "verbs", "nouns", "replies", "particles",
	"topics", "assets", "flow", "chapters", "event_defaults", "intent_schema"]
const ID_PATTERN := "^[a-z0-9_\\-]+$"

var project_path: String = AdvProject.DEFAULT_PATH
var root: String = DEFAULT_ROOT
var errors: Array = []               ## 最後の操作で起きたこと（表示用）

var _undo: Array = []                ## [{label, files: {パス: 前の中身（PackedByteArray か null）}}]
var _redo: Array = []
var _batch = null                    ## いまの操作で覚えている中身
var _batch_label: String = ""
var _depth: int = 0


func _init(p_project_path: String = AdvProject.DEFAULT_PATH) -> void:
	project_path = p_project_path
	root = stored_root()


# ---------------------------------------------------------------- 元に戻す

## 操作の始まり（入れ子にできる。いちばん外の end でひとまとまりになる）。
func begin(label: String) -> void:
	if _depth == 0:
		_batch = {}
		_batch_label = label
	_depth += 1


func end() -> void:
	_depth = maxi(0, _depth - 1)
	if _depth == 0 and _batch != null:
		if not (_batch as Dictionary).is_empty():
			_undo.append({"label": _batch_label, "files": _batch})
			if _undo.size() > MAX_HISTORY:
				_undo.pop_front()
			_redo.clear()
			files_changed.emit()
		_batch = null


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_label() -> String:
	return String(_undo.back()["label"]) if can_undo() else ""


func redo_label() -> String:
	return String(_redo.back()["label"]) if can_redo() else ""


## 最後の操作を元に戻す。戻した操作の名前を返す（なければ ""）。
func undo() -> String:
	if not can_undo():
		return ""
	var e: Dictionary = _undo.pop_back()
	_redo.append({"label": e["label"], "files": _restore(e["files"])})
	files_changed.emit()
	return String(e["label"])


func redo() -> String:
	if not can_redo():
		return ""
	var e: Dictionary = _redo.pop_back()
	_undo.append({"label": e["label"], "files": _restore(e["files"])})
	files_changed.emit()
	return String(e["label"])


## files の中身に戻し、戻す前の中身を返す。
func _restore(files: Dictionary) -> Dictionary:
	var now := {}
	for path in files:
		now[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	for path in files:
		var b = files[path]
		if b == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			DirAccess.make_dir_recursive_absolute(String(path).get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(b)
				f.close()
	return now


func _record(path: String) -> void:
	if _batch == null or (_batch as Dictionary).has(path):
		return
	_batch[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


# ---------------------------------------------------------------- 書き込み（覚えてから書く）

## JSON を書く（整数の値は整数のまま書く。Godot の JSON は数をすべて小数で読むため）。
func write_json(path: String, data: Variant) -> Error:
	return write_text(path, JSON.stringify(AdvSchemaForm.normalize(data), "  ", false) + "\n")


func write_text(path: String, text: String) -> Error:
	var own := _batch == null
	if own:
		begin("書き換え")
	_record(path)
	var err := _save_text(path, text)
	if own:
		end()
	return err


func write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var own := _batch == null
	if own:
		begin("書き換え")
	_record(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	var err := OK
	if f == null:
		err = FileAccess.get_open_error()
	else:
		f.store_buffer(bytes)
		f.close()
	if own:
		end()
	return err


## ファイルかフォルダを消す（OS のごみ箱へ。中身は覚えておくので元に戻せる）。
func remove_path(path: String) -> void:
	var own := _batch == null
	if own:
		begin("削除")
	if DirAccess.dir_exists_absolute(path):
		for f in _files_under(path):
			_record(f)
	else:
		_record(path)
	_trash(path)
	if own:
		end()


static func _files_under(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.include_hidden = true
	for f in d.get_files():
		out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_files_under(dir + "/" + sub))
	return out


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
	_set_ext(p, "scenario_root", path)
	write_json(project_path, p)
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
		out.append({"id": String(data["scene"]), "name": String(data.get("name", data["scene"])), "image": data.get("image"), "kind": String(data.get("kind", "")), "single": true})
	var sc: Dictionary = data.get("scenes", {})
	for id in sc:
		var v: Dictionary = sc[id] if sc[id] is Dictionary else {}
		out.append({"id": String(id), "name": String(v.get("name", id)), "image": v.get("image"), "kind": String(v.get("kind", ""))})
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


## JSON シナリオのファイルすべて（シナリオのフォルダの中と、プロジェクト設定に書いた外のもの）。
func all_files() -> Array:
	var out := []
	for s in scenarios():
		if not s["loose"] and FileAccess.file_exists(String(s["main"])):
			out.append(s["main"])
		for c in chapters(s["id"]):
			out.append(c["path"])
	for f in _project().get("scenarios", []):
		if String(f).ends_with(EXT) and not f in out and FileAccess.file_exists(String(f)):
			out.append(String(f))
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
	return write_json(String(s["main"]), data)


func load_chapter_data(scenario_id: String, chapter_id: String) -> Dictionary:
	var c := chapter(scenario_id, chapter_id)
	return _load(String(c["path"])) if not c.is_empty() else {}


func save_chapter_data(scenario_id: String, chapter_id: String, data: Dictionary) -> Error:
	var c := chapter(scenario_id, chapter_id)
	if c.is_empty():
		return ERR_DOES_NOT_EXIST
	return write_json(String(c["path"]), data)


func chapter_path(scenario_id: String, chapter_id: String) -> String:
	return String(chapter(scenario_id, chapter_id).get("path", ""))


func load_project() -> Dictionary:
	return _project()


func save_project(p: Dictionary) -> Error:
	return write_json(project_path, p)


# ---------------------------------------------------------------- ID

## ID として使えるか（英小文字・数字・_・-）。
static func is_valid_id(id: String) -> bool:
	return RegEx.create_from_string(ID_PATTERN).search(id) != null


## 名前から作った、まだ使われていない ID（作れなければ fallback に番号）。
func suggest_id(level: String, name: String, scenario_id: String = "") -> String:
	var fallback: String = {"scenario": "scenario", "chapter": "chapter", "scene": "scene", "dialogue": "talk"}.get(level, "id")
	return _unique(_id_from(name, fallback), taken_ids(level, scenario_id))


## そのレベルで使われている ID。
func taken_ids(level: String, scenario_id: String = "") -> Dictionary:
	match level:
		"scenario":
			return _scenario_ids()
		"chapter":
			var ids := {}
			for c in chapters(scenario_id):
				ids[c["id"]] = true
			return ids
		"scene":
			return all_scene_ids()
		"dialogue":
			return all_dialogue_ids()
	return {}


## ID を変える。シーンと会話は、すべてのファイルの参照（goto、call、exits のキー、条件の visited など）も変える。
## ids：scenario は [シナリオ]、chapter は [シナリオ, チャプター]、scene は [シナリオ, チャプター, シーン]、
## dialogue は [シナリオ, チャプター, 会話]。
func change_id(level: String, ids: Array, new_id: String) -> Error:
	errors.clear()
	if not is_valid_id(new_id):
		errors.append("ID には英小文字・数字・_・- を使ってください：%s" % new_id)
		return ERR_INVALID_PARAMETER
	var old := String(ids.back())
	if old == new_id:
		return OK
	if taken_ids(level, String(ids[0])).has(new_id):
		errors.append("その ID はもう使われています：%s" % new_id)
		return ERR_ALREADY_EXISTS
	begin("ID の変更（%s → %s）" % [old, new_id])
	match level:
		"scene", "dialogue":
			var maps := {"scenes": {}, "dialogues": {}}
			maps["scenes" if level == "scene" else "dialogues"][old] = new_id
			for f in all_files():
				var d := _load(f)
				var nd = _remap(d, maps)
				if JSON.stringify(nd) != JSON.stringify(d):
					write_json(f, nd)
			if level == "scene":
				var p := _project()
				if String(p.get("entry", "")) == old:
					p["entry"] = new_id
					write_json(project_path, p)
		"chapter":
			var s := scenario(String(ids[0]))
			var from := chapter_path(String(ids[0]), old)
			var to := String(s["dir"]) + "/" + new_id + EXT
			write_bytes(to, FileAccess.get_file_as_bytes(from))
			remove_path(from)
			var pj := _project()
			var lst: Array = pj.get("scenarios", [])
			var at := lst.find(from)
			if at >= 0:
				lst[at] = to
				write_json(project_path, pj)
			if not s["loose"]:
				var d := load_scenario_data(String(ids[0]))
				var order: Array = d.get("ext", {}).get(EXT_KEY, {}).get("chapter_order", [])
				var i := order.find(old)
				if i >= 0:
					order[i] = new_id
				else:
					order.append(new_id)
				_set_ext(d, "chapter_order", order)
				save_scenario_data(String(ids[0]), d)
			sync_project()
		"scenario":
			var s := scenario(old)
			if s.is_empty() or s["loose"]:
				end()
				return ERR_UNAVAILABLE
			var dir := String(s["dir"])
			var to_dir := root + "/" + new_id
			for f in _files_under(dir):
				write_bytes(to_dir + String(f).substr(dir.length()), FileAccess.get_file_as_bytes(f))
			remove_path(dir)
			var p := _project()
			var order: Array = p.get("ext", {}).get(EXT_KEY, {}).get("scenario_order", [])
			var i := order.find(old)
			if i >= 0:
				order[i] = new_id
			_set_ext(p, "scenario_order", order)
			# プロジェクト設定の scenarios の古いパスも書き直す
			var list: Array = p.get("scenarios", [])
			for j in list.size():
				if String(list[j]).begins_with(dir + "/"):
					list[j] = to_dir + String(list[j]).substr(dir.length())
			write_json(project_path, p)
			sync_project()
	end()
	return OK


# ---------------------------------------------------------------- 作る・名前を変える

## シナリオを作る。ID を渡さなければ名前から作る。最初のチャプターと開始のシーンも作る。
func create_scenario(name: String, id: String = "") -> String:
	if not has_root():
		return ""
	if id == "":
		id = suggest_id("scenario", name)
	if _scenario_ids().has(id) or not is_valid_id(id):
		return ""
	begin("シナリオの作成（%s）" % name)
	var dir := root + "/" + id
	DirAccess.make_dir_recursive_absolute(dir)
	var scene_id := _unique(id + "_start", all_scene_ids())
	write_json(dir + "/" + MAIN_FILE, {"scenario_version": 1, "start": scene_id,
		"ext": {EXT_KEY: {"name": name, "chapter_order": ["chapter1"]}}})
	write_json(dir + "/chapter1" + EXT, {"scenario_version": 1, "ext": {EXT_KEY: {"name": "第1章"}},
		"scenes": {scene_id: {"name": "はじまり", "enter": ["%s が はじまった。" % name]}}})
	_append_order(id)
	sync_project()
	end()
	return id


func create_chapter(scenario_id: String, name: String, id: String = "") -> String:
	var s := scenario(scenario_id)
	if s.is_empty():
		return ""
	if id == "":
		id = suggest_id("chapter", name, scenario_id)
	if taken_ids("chapter", scenario_id).has(id) or not is_valid_id(id):
		return ""
	begin("チャプターの作成（%s）" % name)
	write_json(String(s["dir"]) + "/" + id + EXT, {"scenario_version": 1, "ext": {EXT_KEY: {"name": name}}, "scenes": {}})
	_add_chapter_order(scenario_id, id)
	sync_project()
	end()
	return id


func create_scene(scenario_id: String, chapter_id: String, name: String, id: String = "") -> String:
	var data := load_chapter_data(scenario_id, chapter_id)
	if data.is_empty() and chapter(scenario_id, chapter_id).is_empty():
		return ""
	if id == "":
		id = suggest_id("scene", name)
	if all_scene_ids().has(id) or not is_valid_id(id):
		return ""
	var sc: Dictionary = data.get("scenes", {})
	sc[id] = {"name": name, "enter": []}
	data["scenes"] = sc
	begin("シーンの作成（%s）" % name)
	save_chapter_data(scenario_id, chapter_id, data)
	end()
	return id


## 表示名を変える（ID は変えない。ID を変えるのは change_id）。
func rename(level: String, ids: Array, name: String) -> Error:
	begin("名前の変更（%s）" % name)
	var err := ERR_INVALID_PARAMETER
	match level:
		"scenario":
			if ids[0] == LOOSE_ID:
				err = ERR_UNAVAILABLE
			else:
				var d := load_scenario_data(ids[0])
				_set_ext(d, "name", name)
				err = save_scenario_data(ids[0], d)
		"chapter":
			var d := load_chapter_data(ids[0], ids[1])
			_set_ext(d, "name", name)
			err = save_chapter_data(ids[0], ids[1], d)
		"scene":
			var d := load_chapter_data(ids[0], ids[1])
			if String(d.get("scene", "")) == ids[2]:
				d["name"] = name
				err = save_chapter_data(ids[0], ids[1], d)
			else:
				var sc: Dictionary = d.get("scenes", {})
				if not sc.has(ids[2]):
					err = ERR_DOES_NOT_EXIST
				else:
					sc[ids[2]]["name"] = name
					err = save_chapter_data(ids[0], ids[1], d)
	end()
	return err


## 並べ替える。ids は新しい順のすべての ID。
func set_order(level: String, ids: Array, scenario_id: String = "", chapter_id: String = "") -> void:
	begin("並べ替え")
	match level:
		"scenario":
			var p := _project()
			_set_ext(p, "scenario_order", ids.filter(func(x): return x != LOOSE_ID))
			write_json(project_path, p)
			sync_project()
		"chapter":
			var d := load_scenario_data(scenario_id)
			if not d.is_empty():
				_set_ext(d, "chapter_order", ids.duplicate())
				save_scenario_data(scenario_id, d)
				sync_project()
		"scene":
			var d := load_chapter_data(scenario_id, chapter_id)
			var sc: Dictionary = d.get("scenes", {})
			var out := {}
			for id in ids:
				if sc.has(id):
					out[id] = sc[id]
			for id in sc:
				if not out.has(id):
					out[id] = sc[id]
			d["scenes"] = out
			save_chapter_data(scenario_id, chapter_id, d)
	end()


# ---------------------------------------------------------------- 消す

## 消す。ファイルとフォルダは OS のごみ箱へ移す（元に戻すこともできる）。
func delete_scenarios(ids: Array) -> void:
	begin("シナリオの削除")
	for id in ids:
		var s := scenario(String(id))
		if s.is_empty() or s["loose"]:
			continue
		remove_path(String(s["dir"]))
		_remove_order(String(id))
	sync_project()
	end()


func delete_chapters(scenario_id: String, ids: Array) -> void:
	begin("チャプターの削除")
	for id in ids:
		var p := chapter_path(scenario_id, String(id))
		if p != "":
			remove_path(p)
	var s := scenario(scenario_id)
	if not s.is_empty() and not s["loose"]:
		var d := load_scenario_data(scenario_id)
		var order: Array = d.get("ext", {}).get(EXT_KEY, {}).get("chapter_order", [])
		for id in ids:
			order.erase(id)
		_set_ext(d, "chapter_order", order)
		save_scenario_data(scenario_id, d)
	sync_project()
	end()


func delete_scenes(scenario_id: String, chapter_id: String, ids: Array) -> void:
	begin("シーンの削除")
	var d := load_chapter_data(scenario_id, chapter_id)
	var sc: Dictionary = d.get("scenes", {})
	for id in ids:
		sc.erase(id)
	save_chapter_data(scenario_id, chapter_id, d)
	end()


# ---------------------------------------------------------------- 複写

## シナリオを count 個ずつ複写する。シーンと会話の ID は新しくし、シナリオの中の参照も付け替える。返り値は作ったID。
func duplicate_scenarios(ids: Array, count: int = 1) -> Array:
	var made := []
	begin("シナリオの複写")
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
				write_json(dir + "/" + String(path).get_file(), d)
			for f in _files_under(String(s["dir"]) + "/ink"):
				if not String(f).ends_with(".import") and not String(f).ends_with(".uid"):
					write_bytes(dir + "/ink/" + String(f).get_file(), FileAccess.get_file_as_bytes(f))
			_append_order(new_id)
			made.append(new_id)
	sync_project()
	end()
	return made


## チャプターを count 個ずつ複写する（to_scenario を渡すと、そのシナリオへ）。
func duplicate_chapters(scenario_id: String, ids: Array, count: int = 1, to_scenario: String = "") -> Array:
	var target := scenario(to_scenario if to_scenario != "" else scenario_id)
	if target.is_empty():
		return []
	var made := []
	begin("チャプターの複写")
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
			write_json(String(target["dir"]) + "/" + new_id + EXT, d)
			if not target["loose"]:
				_add_chapter_order(String(target["id"]), new_id)
			made.append(new_id)
	sync_project()
	end()
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
	begin("シーンの複写")
	save_chapter_data(ts, tc, dst)
	end()
	return made


# ---------------------------------------------------------------- 古い形のファイルを移す

## フォルダの直下の古い形のファイルを、シナリオのフォルダの形（<id>/_scenario.scenario.json と chapter1）に移す。
## 移したシナリオは、シナリオの並びの最後に入る（開始シーンはプロジェクト設定の entry で決まる）。
func migrate_loose(path: String, new_id: String, name: String = "") -> Error:
	errors.clear()
	if not FileAccess.file_exists(path):
		return ERR_DOES_NOT_EXIST
	if not is_valid_id(new_id) or _scenario_ids().has(new_id):
		errors.append("その ID は使えません：%s" % new_id)
		return ERR_INVALID_PARAMETER
	var d := _load(path)
	var main := {"scenario_version": 1}
	var ch := {"scenario_version": 1}
	for k in d:
		if k in MAIN_KEYS:
			main[k] = d[k]
		elif k == "ext":
			continue
		elif k != "scenario_version" and k != "$schema":
			ch[k] = d[k]
	# シーン1つのファイルは scenes の形にする
	if ch.has("scene"):
		var sid := String(ch["scene"])
		var body := _single_scene_body(ch)
		for k in ["scene", "name", "image", "image_transition", "first", "enter", "objects", "exits", "sprites", "on"]:
			ch.erase(k)
		var sc: Dictionary = ch.get("scenes", {})
		var out := {sid: body}
		out.merge(sc)
		ch["scenes"] = out
	# 素材フォルダの相対パスは、元のファイルの場所から res:// のパスにする
	if main.get("assets") is Dictionary and main["assets"].has("root"):
		var r := String(main["assets"]["root"])
		if not r.contains("://"):
			main["assets"]["root"] = path.get_base_dir().path_join(r).simplify_path()
	var ext: Dictionary = d.get("ext", {}) if d.get("ext") is Dictionary else {}
	var mine: Dictionary = ext.get(EXT_KEY, {}).duplicate()
	mine["name"] = name if name != "" else String(mine.get("name", path.get_file().trim_suffix(EXT)))
	mine["chapter_order"] = ["chapter1"]
	ext[EXT_KEY] = mine
	main["ext"] = ext
	ch["ext"] = {EXT_KEY: {"name": "第1章"}}
	begin("フォルダの形に移す（%s）" % path.get_file())
	var dir := root + "/" + new_id
	var main_path := dir + "/" + MAIN_FILE
	var ch_path := dir + "/chapter1" + EXT
	write_json(main_path, main)
	write_json(ch_path, ch)
	remove_path(path)
	var p := _project()
	var list: Array = p.get("scenarios", [])
	var i := list.find(path)
	if i >= 0:
		list.remove_at(i)
		list.insert(i, ch_path)
		list.insert(i, main_path)
	p["scenarios"] = list
	var order: Array = p.get("ext", {}).get(EXT_KEY, {}).get("scenario_order", [])
	if not new_id in order:
		order.append(new_id)
	_set_ext(p, "scenario_order", order)
	write_json(project_path, p)
	sync_project()
	end()
	return OK


# ---------------------------------------------------------------- プロジェクト設定と合わせる

## プロジェクト設定の scenarios を、シナリオのフォルダのファイルに合わせて書き直す。
## フォルダの外のファイル（ほかの場所の Ink など）と、フォルダの直下の古い形のファイルは、元の順のまま残す
## （start は最後のファイルのものになるため）。開始シーン entry が空か、もうないシーンなら、最初のシナリオの start にする。
func sync_project() -> void:
	if not has_root():
		return
	var p := _project()
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
	# いまの並びで、同じものなら書かない
	var new_list := keep + files
	var changed: bool = JSON.stringify(new_list) != JSON.stringify(p.get("scenarios", []))
	p["scenarios"] = new_list
	var entry := String(p.get("entry", ""))
	if entry == "" or not all_scene_ids().has(entry):
		var first := start_of_first_scenario()
		if first != "" and first != entry:
			p["entry"] = first
			changed = true
	if changed:
		write_json(project_path, p)


func start_of_first_scenario() -> String:
	for s in scenarios():
		if not s["loose"]:
			var st := String(load_scenario_data(s["id"]).get("start", ""))
			if st != "":
				return st
	return ""


## 開始するシナリオ（プロジェクト設定の entry のシーンがあるシナリオ）。
func start_scenario() -> String:
	var entry := String(_project().get("entry", ""))
	var where = all_scene_ids().get(entry)
	return String(where["scenario"]) if where is Dictionary else ""


## このシナリオから始める（プロジェクト設定の entry を、そのシナリオの start にする）。
func set_start_scenario(scenario_id: String) -> Error:
	var st := String(load_scenario_data(scenario_id).get("start", ""))
	if st == "":
		errors.append("このシナリオには start（開始シーン）がありません")
		return ERR_DOES_NOT_EXIST
	var p := _project()
	p["entry"] = st
	begin("開始シナリオの変更")
	write_json(project_path, p)
	end()
	return OK


# ---------------------------------------------------------------- 素材

## 画像の素材 ID からファイルのパスを探す（プロジェクトの素材フォルダと、シナリオの素材フォルダ）。なければ ""。
func image_path(id: String) -> String:
	if id == "":
		return ""
	var a := _assets()
	return a.resolve("image", id.get_slice("@", 0), id.get_slice("@", 1) if id.contains("@") else "")


var _assets_cache: AdvAssets = null


## 素材のパス（なければ ""）。
func asset_path(kind: String, id: String) -> String:
	return _assets().resolve(kind, id) if id != "" else ""


## 素材の ID の一覧（kind は image・bgm・se・voice など）。
func asset_ids(kind: String) -> PackedStringArray:
	return _assets().ids(kind)


func _assets() -> AdvAssets:
	if _assets_cache != null:
		return _assets_cache
	var diags: Array = []
	var project := AdvProject.load_project(project_path, diags)
	var a := AdvAssets.new()
	a.folders = project.asset_folders()
	var roots: Array = AdvManifestGenerator.project_roots(project, diags)
	for f in all_files():
		var d := _load(f)
		if d.get("assets") is Dictionary and d["assets"].has("root"):
			var r := String(d["assets"]["root"])
			if not r.contains("://"):
				r = String(f).get_base_dir().path_join(r).simplify_path()
			roots.append(r)
	for r in roots:
		a.add_manifest(AdvManifestGenerator.scan(r, a.folders)["manifest"], r)
		var manual := String(r) + "/" + AdvManifestGenerator.MANUAL_NAME
		if FileAccess.file_exists(manual):
			var m = AdvJson.load_file(manual)
			if m is Dictionary:
				a.add_manifest(m, r)
	_assets_cache = a
	return a


## シーンの背景の素材 ID（image が配列なら最初のもの）。
static func image_id_of(image: Variant) -> String:
	if image is String:
		return image
	if image is Array and not image.is_empty():
		return image_id_of(image[0])
	if image is Dictionary:
		return String(image.get("id", ""))
	return ""


## 画像を読み込む（取り込みが済んでいなくても読む）。読めなければ null。
static func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var ext := path.get_extension().to_lower()
	if ext == "mag":
		var fr := AdvMag.load_frames(path)
		return fr.frames[0] if fr != null else null
	if ext in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			return r
		if r is AdvImageFrames and not r.frames.is_empty():
			return r.frames[0]
	return null


# ---------------------------------------------------------------- 並び順

func _append_order(id: String) -> void:
	var p := _project()
	var order: Array = p.get("ext", {}).get(EXT_KEY, {}).get("scenario_order", [])
	if not id in order:
		order.append(id)
	_set_ext(p, "scenario_order", order)
	write_json(project_path, p)


func _remove_order(id: String) -> void:
	var p := _project()
	var order: Array = p.get("ext", {}).get(EXT_KEY, {}).get("scenario_order", [])
	if id in order:
		order.erase(id)
		_set_ext(p, "scenario_order", order)
		write_json(project_path, p)


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
	var ext: Dictionary = d.get("ext", {}) if d.get("ext") is Dictionary else {}
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
				"start", "scene", "visited", "entry":
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
	return _load(project_path)


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
	return AdvSchemaForm.normalize(d) if d is Dictionary else {}


static func _save_json(path: String, data: Variant) -> Error:
	return _save_text(path, JSON.stringify(AdvSchemaForm.normalize(data), "  ", false) + "\n")


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
