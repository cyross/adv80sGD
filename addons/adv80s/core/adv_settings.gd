class_name AdvSettings
extends RefCounted
## プレイヤー設定（セーブとは別のファイル、第8章）。文字の速さ、オート送りの間隔、フィルター、モダン機能の切り替えなど。

const PATH := "user://adv80s_settings.json"

var data: Dictionary = {
	"text_speed": 1.0,      ## 文字速度の倍率（テンプレートの text.speed にかける。0 なら一度に表示）
	"auto_delay": 1.2,      ## オート送り：文章を出し終えてから次へ進むまでの秒数（1文字ごとに auto_per_char を足す）
	"auto_per_char": 0.04,
	"skip_unread": false,   ## 未読の文章もスキップする
	"filters": true,        ## フィルターを使う
	"features": {},         ## モダン機能の実行時の切り替え（キー → bool）
}


static func load_settings(path: String = PATH) -> AdvSettings:
	var s := AdvSettings.new()
	if FileAccess.file_exists(path):
		var d = AdvJson.load_file(path)
		if d is Dictionary:
			s.data = AdvJson.merge(s.data, d)
	return s


func save(path: String = PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  ") + "\n")
	f.close()
	return OK


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant) -> void:
	data[key] = value
