class_name AdvProgress
extends RefCounted
## 全プレイ共通の進行の記録（セーブとは別のファイル）。
## - フローチャートで到達した点と、そこから再開するための状態（flowchart、chapter_select）
## - 読んだ行（既読スキップを、別のプレイやセーブをまたいでも効かせる）
## - 見たエンディング（エンディング一覧）

const PATH := "user://adv80s_progress.dat"

var reached: Dictionary = {}     ## 点ID → true
var snapshots: Dictionary = {}   ## 点ID → セーブと同じ形のデータ（そこから再開する）
var read: Dictionary = {}        ## 行ID → true
var endings: Dictionary = {}     ## エンディングID → {time: 最初に見た時刻, count: 見た回数}
var openings: Dictionary = {}    ## 見終わったオープニングのシーンID → true（2回目からの飛ばし方に使う）
var seen: Dictionary = {"image": {}, "bgm": {}}  ## 一度でも出した画像・鳴らした曲（おまけのギャラリーと音楽で使う）
var path: String = PATH
var _dirty := false


static func load_progress(file: String = PATH) -> AdvProgress:
	var p := AdvProgress.new()
	p.path = file
	if file != "" and FileAccess.file_exists(file):
		var d = bytes_to_var(FileAccess.get_file_as_bytes(file))
		if d is Dictionary:
			p.reached = d.get("reached", {})
			p.snapshots = d.get("snapshots", {})
			p.read = d.get("read", {})
			p.endings = d.get("endings", {})
			p.openings = d.get("openings", {})
			p.seen = d.get("seen", {"image": {}, "bgm": {}})
	return p


func mark_reached(node: String, snapshot: Dictionary) -> void:
	reached[node] = true
	snapshots[node] = snapshot.duplicate(true)
	_dirty = true


## 画像を出した・曲を鳴らした記録を付ける（kind は image か bgm。bonus は知らせた特典）。初めてなら true。
func mark_seen(kind: String, id: String) -> bool:
	if id == "":
		return false
	if not seen.has(kind):
		seen[kind] = {}
	if not seen[kind].has(id):
		seen[kind][id] = true
		_dirty = true
		return true
	return false


## おまけの記録（見た画像、聞いた曲、知らせた特典）を消す。
func clear_extras() -> void:
	seen = {"image": {}, "bgm": {}}
	_dirty = true


## 既読の記録を消す。
func clear_read() -> void:
	read.clear()
	_dirty = true


## フローチャートとチャプター選択の到達点（と再開の状態）を消す。
func clear_flow() -> void:
	reached.clear()
	snapshots.clear()
	_dirty = true


## 見終わったオープニングの記録を消す（2回目からの飛ばし方が、1回目に戻る）。
func clear_openings() -> void:
	openings.clear()
	_dirty = true


## 見たエンディングの記録を消す。
func clear_endings() -> void:
	endings.clear()
	_dirty = true


## オープニングを見た記録を付ける。
func mark_opening(id: String) -> void:
	if not openings.has(id):
		openings[id] = true
		_dirty = true


## エンディングを見た記録を付ける。初めて見たなら true。
func mark_ending(id: String) -> bool:
	var first := not endings.has(id)
	var e: Dictionary = endings.get(id, {"time": int(Time.get_unix_time_from_system()), "count": 0})
	e["count"] = int(e.get("count", 0)) + 1
	endings[id] = e
	_dirty = true
	return first


func merge_read(ids: Dictionary) -> void:
	for id in ids:
		if not read.has(id):
			read[id] = true
			_dirty = true


func save() -> Error:
	if not _dirty or path == "":
		return OK
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(var_to_bytes({"reached": reached, "snapshots": snapshots, "read": read, "endings": endings, "openings": openings, "seen": seen}))
	f.close()
	_dirty = false
	return OK


func clear() -> void:
	reached.clear()
	snapshots.clear()
	read.clear()
	endings.clear()
	openings.clear()
	seen = {"image": {}, "bgm": {}}
	_dirty = true
