class_name AdvMessageLog
extends RefCounted
## メッセージログ（第9章）。表示した文章と、プレイヤーの入力を記録する。セーブデータに含める。
## 記録の形：{kind: "text" | "input", name?, body, id?, voice?}

var entries: Array = []
var max_entries: int = 500


func add_text(body: String, speaker_name: String = "", id: String = "", voice: String = "") -> void:
	var e := {"kind": "text", "body": body}
	if speaker_name != "":
		e["name"] = speaker_name
	if id != "":
		e["id"] = id
	if voice != "":
		e["voice"] = voice
	_add(e)


func add_input(text: String) -> void:
	_add({"kind": "input", "body": text})


func _add(e: Dictionary) -> void:
	entries.append(e)
	while max_entries > 0 and entries.size() > max_entries:
		entries.pop_front()


func last_text() -> Dictionary:
	for i in range(entries.size() - 1, -1, -1):
		if entries[i]["kind"] == "text":
			return entries[i]
	return {}


func clear() -> void:
	entries.clear()


func to_array() -> Array:
	return entries.duplicate(true)


func from_array(a: Array) -> void:
	entries = a.duplicate(true)
