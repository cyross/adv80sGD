class_name AdvProgress
extends RefCounted
## 全プレイ共通の進行の記録（セーブとは別のファイル）。
## - フローチャートで到達した点と、そこから再開するための状態（flowchart、chapter_select）
## - 読んだ行（既読スキップを、別のプレイやセーブをまたいでも効かせる）

const PATH := "user://adv80s_progress.dat"

var reached: Dictionary = {}     ## 点ID → true
var snapshots: Dictionary = {}   ## 点ID → セーブと同じ形のデータ（そこから再開する）
var read: Dictionary = {}        ## 行ID → true
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
	return p


func mark_reached(node: String, snapshot: Dictionary) -> void:
	reached[node] = true
	snapshots[node] = snapshot.duplicate(true)
	_dirty = true


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
	f.store_buffer(var_to_bytes({"reached": reached, "snapshots": snapshots, "read": read}))
	f.close()
	_dirty = false
	return OK


func clear() -> void:
	reached.clear()
	snapshots.clear()
	read.clear()
	_dirty = true
