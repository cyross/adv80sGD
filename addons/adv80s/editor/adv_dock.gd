@tool
extends VBoxContainer
## エディタのドック「adv80s」。マニフェストの生成ボタンと、確認の結果の一覧を出す。

signal generate_requested

var _summary: Label
var _tree: Tree


func _init() -> void:
	var bar := HBoxContainer.new()
	var btn := Button.new()
	btn.text = "マニフェストを生成"
	btn.tooltip_text = "素材フォルダを読んで manifest.auto.json を書き出し、確認します"
	btn.pressed.connect(func(): generate_requested.emit())
	bar.add_child(btn)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.text = "未実行"
	bar.add_child(_summary)
	add_child(bar)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "区分")
	_tree.set_column_title(1, "内容")
	_tree.set_column_title(2, "場所")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 72)
	_tree.hide_root = true
	_tree.item_activated.connect(_on_activated)
	add_child(_tree)


func show_result(res: Dictionary) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var errors := 0
	var warnings := 0
	var diags: Array = res.get("diags", [])
	diags.sort_custom(func(a, b): return _rank(a) < _rank(b))
	for d in diags:
		var sev := String(d["severity"])
		if sev == "error":
			errors += 1
		elif sev == "warning":
			warnings += 1
		var it := _tree.create_item(root)
		it.set_text(0, {"error": "エラー", "warning": "警告", "info": "情報"}.get(sev, sev))
		it.set_custom_color(0, Color(1, 0.4, 0.4) if sev == "error" else (Color(1, 0.8, 0.3) if sev == "warning" else Color(0.7, 0.7, 0.7)))
		it.set_text(1, "%s  %s" % [d["code"], d["message"]])
		it.set_tooltip_text(1, String(d["message"]))
		var where := String(d.get("file", ""))
		if String(d.get("path", "")) != "":
			where += "  " + String(d["path"])
		it.set_text(2, where)
		it.set_metadata(0, String(d.get("file", "")))
	_summary.text = "エラー %d、警告 %d（素材フォルダ %d、書き出し %d）" % [errors, warnings,
		res.get("roots", []).size(), res.get("written", []).size()]


static func _rank(d: Dictionary) -> int:
	return {"error": 0, "warning": 1}.get(String(d["severity"]), 2)


## 項目をダブルクリックすると、そのファイルを FileSystem ドックで選ぶ。
func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var file := String(it.get_metadata(0))
	if file.begins_with("res://") and (FileAccess.file_exists(file) or DirAccess.dir_exists_absolute(file)):
		EditorInterface.select_file(file)
