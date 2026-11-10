@tool
class_name AdvSceneGraphView
extends Panel
## シーングラフのインタラクティブ表示・詳細確認・SVG/PNG出力を行うUIコントロール（デバッグ・エディタ専用）。
##
## 主な機能:
## 1. シーン(ノード)間のグラフ表示と矢印による遷移方向の可視化
## 2. 矢印上への遷移条件概要の表示
## 3. ノードクリックによる該当シーン中心の詳細遷移・条件・データ表示
## 4. 遷移クリックによる接続ノードと詳細な条件・データ表示（そこからノードクリックでノード詳細へ遷移）
## 5. ノード詳細・遷移詳細表示時のノード外遷移の点線表示
## 6. 「全体図へ戻る」ボタン・「シーングラフを閉じる」ボタン
## 7. ESCキーによるクリック履歴の逆順辿り（全体図でESCキーを押すとシーングラフを閉じる）
## 8. 「SVG・PNGで出力」ボタンと保存設定ダイアログ表示

signal closed()
signal scene_jump_requested(scene_id: String)

const SceneGraph = preload("res://addons/adv80s/debug/adv_scene_graph.gd")

var graph: Dictionary = {"nodes": {}, "node_order": [], "edges": [], "edge_map": {}, "start_scene": "", "current_scene": ""}
var current_scene_id: String = ""
var allow_close: bool = true

var _mode: String = SceneGraph.MODE_OVERVIEW
var _focus_id: String = ""
## 履歴スタック: Array of {"mode": String, "focus_id": String}
var _history: Array[Dictionary] = []
var _layout: Dictionary = {}

# UI references
var _title_label: Label
var _history_label: Label
var _back_btn: Button
var _overview_btn: Button
var _reset_zoom_btn: Button
var _export_btn: Button
var _close_btn: Button
var _split: HSplitContainer
var _canvas: _GraphCanvas
var _detail_panel: PanelContainer
var _detail_scroll: ScrollContainer
var _detail_vbox: VBoxContainer
var _status_label: Label

# Export dialog references
var _export_modal: ColorRect
var _fmt_opt: OptionButton
var _target_opt: OptionButton
var _scale_opt: OptionButton
var _bg_check: CheckBox
var _detail_check: CheckBox
var _path_edit: LineEdit
var _export_msg: Label
var _file_dialog: FileDialog


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("#0f172a")
	bg_style.border_color = Color("#334155")
	bg_style.set_border_width_all(1)
	add_theme_stylebox_override("panel", bg_style)
	_build_ui()


func _ready() -> void:
	var nodes_dict: Dictionary = graph.get("nodes", {})
	if not nodes_dict.is_empty() and _layout.is_empty():
		_rebuild_layout(true)


## AdvCore からシナリオデータを読み込んでグラフを構築する。
func setup_from_core(core: AdvCore, active_scene: String = "") -> void:
	current_scene_id = active_scene if active_scene != "" else (core.state.scene if core != null and core.state != null else "")
	graph = SceneGraph.build_from_core(core)
	graph["current_scene"] = current_scene_id
	_history.clear()
	_mode = SceneGraph.MODE_OVERVIEW
	_focus_id = ""
	_rebuild_layout(true)


## プロジェクトパスからグラフを構築する（エディタ用）。
func setup_from_project(project_path: String = "res://adv80s.project.json", active_scene: String = "") -> void:
	current_scene_id = active_scene
	graph = SceneGraph.build_from_project(project_path)
	if active_scene != "":
		graph["current_scene"] = active_scene
	_history.clear()
	_mode = SceneGraph.MODE_OVERVIEW
	_focus_id = ""
	_rebuild_layout(true)


## 現在のシーン数を返す。
func node_count() -> int:
	var nds: Dictionary = graph.get("nodes", {})
	return nds.size()


## 現在の遷移数を返す。
func edge_count() -> int:
	var eds: Array = graph.get("edges", [])
	return eds.size()


## 閉じるボタンの表示可否を設定する。
func set_close_button_visible(vis: bool) -> void:
	allow_close = vis
	if _close_btn != null:
		_close_btn.visible = vis


## ESCキー処理（AdvPlayer のオーバーレイ制御からも呼び出される）。
## 処理した場合は true を返す。
func handle_escape() -> bool:
	if _file_dialog != null and _file_dialog.visible:
		_file_dialog.hide()
		return true
	if _export_modal != null and _export_modal.visible:
		_export_modal.visible = false
		return true
	if not _history.is_empty():
		_step_back_history()
		return true
	if _mode != SceneGraph.MODE_OVERVIEW:
		_set_view(SceneGraph.MODE_OVERVIEW, "", false)
		return true
	if allow_close:
		close()
		return true
	return false


func close() -> void:
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if handle_escape():
				accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if handle_escape():
				get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# --- Top Toolbar ---
	var toolbar_panel := PanelContainer.new()
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = Color("#1e293b")
	tb_style.content_margin_left = 10
	tb_style.content_margin_right = 10
	tb_style.content_margin_top = 6
	tb_style.content_margin_bottom = 6
	toolbar_panel.add_theme_stylebox_override("panel", tb_style)
	root_vbox.add_child(toolbar_panel)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	toolbar_panel.add_child(toolbar)

	_title_label = Label.new()
	_title_label.text = "シーングラフ: 全体図"
	_title_label.clip_text = true
	_title_label.add_theme_color_override("font_color", Color("#f8fafc"))
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_title_label)

	_history_label = Label.new()
	_history_label.text = ""
	_history_label.add_theme_color_override("font_color", Color("#94a3b8"))
	_history_label.add_theme_font_size_override("font_size", 11)
	toolbar.add_child(_history_label)

	_back_btn = Button.new()
	_back_btn.text = "← 戻る(ESC)"
	_back_btn.tooltip_text = "直前に表示していたノード・遷移・全体図に戻ります (ESCキー)"
	_back_btn.add_theme_font_size_override("font_size", 11)
	_back_btn.pressed.connect(_step_back_history)
	toolbar.add_child(_back_btn)

	_overview_btn = Button.new()
	_overview_btn.text = "全体図へ戻る"
	_overview_btn.tooltip_text = "シーングラフの全体図表示へ戻ります"
	_overview_btn.add_theme_font_size_override("font_size", 11)
	_overview_btn.pressed.connect(_on_overview_pressed)
	toolbar.add_child(_overview_btn)

	_reset_zoom_btn = Button.new()
	_reset_zoom_btn.text = "中央表示"
	_reset_zoom_btn.tooltip_text = "ズームとスクロール位置を中央にリセットします"
	_reset_zoom_btn.add_theme_font_size_override("font_size", 11)
	_reset_zoom_btn.pressed.connect(func() -> void:
		if _canvas != null:
			_canvas.fit_to_view()
	)
	toolbar.add_child(_reset_zoom_btn)

	_export_btn = Button.new()
	_export_btn.text = "SVG・PNG出力…"
	_export_btn.tooltip_text = "保存設定ダイアログを開き、シーングラフをSVGまたはPNGファイルに出力します"
	_export_btn.add_theme_font_size_override("font_size", 11)
	_export_btn.pressed.connect(_open_export_dialog)
	toolbar.add_child(_export_btn)

	_close_btn = Button.new()
	_close_btn.text = "閉じる(ESC)"
	_close_btn.tooltip_text = "シーングラフを閉じます"
	_close_btn.add_theme_font_size_override("font_size", 11)
	_close_btn.pressed.connect(close)
	toolbar.add_child(_close_btn)

	# --- Legend / Help Bar ---
	var legend_panel := PanelContainer.new()
	var lg_style := StyleBoxFlat.new()
	lg_style.bg_color = Color("#152033")
	lg_style.content_margin_left = 10
	lg_style.content_margin_right = 10
	lg_style.content_margin_top = 4
	lg_style.content_margin_bottom = 4
	legend_panel.add_theme_stylebox_override("panel", lg_style)
	root_vbox.add_child(legend_panel)

	var legend_hb := HBoxContainer.new()
	legend_hb.add_theme_constant_override("separation", 14)
	legend_panel.add_child(legend_hb)

	var hint_lbl := Label.new()
	hint_lbl.text = "操作: [ノードクリック] シーン中心の詳細表示  [矢印/条件クリック] 遷移詳細表示  [ドラッグ] 移動  [ホイール] 拡大縮小  [ESC] 履歴を戻る / 全体図で閉じる"
	hint_lbl.clip_text = true
	hint_lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend_hb.add_child(hint_lbl)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color("#38bdf8"))
	_status_label.add_theme_font_size_override("font_size", 12)
	legend_hb.add_child(_status_label)

	# --- Main Split (Graph Canvas + Detail Inspector) ---
	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.split_offset = -230
	root_vbox.add_child(_split)

	_canvas = _GraphCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.node_clicked.connect(_on_node_clicked)
	_canvas.edge_clicked.connect(_on_edge_clicked)
	_split.add_child(_canvas)

	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size = Vector2(210, 0)
	var dp_style := StyleBoxFlat.new()
	dp_style.bg_color = Color("#1e293b")
	dp_style.border_color = Color("#334155")
	dp_style.border_width_left = 1
	dp_style.content_margin_left = 10
	dp_style.content_margin_right = 10
	dp_style.content_margin_top = 8
	dp_style.content_margin_bottom = 8
	_detail_panel.add_theme_stylebox_override("panel", dp_style)
	_split.add_child(_detail_panel)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(_detail_scroll)

	_detail_vbox = VBoxContainer.new()
	_detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_vbox.add_theme_constant_override("separation", 6)
	_detail_scroll.add_child(_detail_vbox)

	# --- Export Settings Modal Dialog ---
	_build_export_modal()


func _build_export_modal() -> void:
	_export_modal = ColorRect.new()
	_export_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_export_modal.color = Color(0, 0, 0, 0.65)
	_export_modal.visible = false
	add_child(_export_modal)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_export_modal.add_child(center)

	var dlg_panel := PanelContainer.new()
	dlg_panel.custom_minimum_size = Vector2(420, 240)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1e293b")
	st.border_color = Color("#60a5fa")
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	dlg_panel.add_theme_stylebox_override("panel", st)
	center.add_child(dlg_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	dlg_panel.add_child(vb)

	var title := Label.new()
	title.text = "シーングラフ 保存設定ダイアログ (SVG / PNG 出力)"
	title.add_theme_color_override("font_color", Color("#f8fafc"))
	title.add_theme_font_size_override("font_size", 15)
	vb.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)

	# Format
	var fmt_lbl := Label.new()
	fmt_lbl.text = "出力フォーマット:"
	grid.add_child(fmt_lbl)

	_fmt_opt = OptionButton.new()
	_fmt_opt.add_item("SVG (ベクター画像 .svg)", 0)
	_fmt_opt.add_item("PNG (ラスター画像 .png)", 1)
	_fmt_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fmt_opt.item_selected.connect(_on_export_format_changed)
	grid.add_child(_fmt_opt)

	# Target view
	var tgt_lbl := Label.new()
	tgt_lbl.text = "出力対象:"
	grid.add_child(tgt_lbl)

	_target_opt = OptionButton.new()
	_target_opt.add_item("現在表示中のグラフ", 0)
	_target_opt.add_item("全体図 (すべてのシーン)", 1)
	_target_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_target_opt)

	# Scale
	var sc_lbl := Label.new()
	sc_lbl.text = "出力スケール (解像度):"
	grid.add_child(sc_lbl)

	_scale_opt = OptionButton.new()
	_scale_opt.add_item("100% (標準 1x)", 0)
	_scale_opt.add_item("150% (高精細 1.5x)", 1)
	_scale_opt.add_item("200% (超高精細 2x)", 2)
	_scale_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_scale_opt)

	# Options
	var opt_lbl := Label.new()
	opt_lbl.text = "オプション:"
	grid.add_child(opt_lbl)

	var opt_vb := VBoxContainer.new()
	_bg_check = CheckBox.new()
	_bg_check.text = "背景色を含める（オフで透過背景）"
	_bg_check.button_pressed = true
	opt_vb.add_child(_bg_check)

	_detail_check = CheckBox.new()
	_detail_check.text = "選択中ノード・遷移の詳細パネル情報を含める"
	_detail_check.button_pressed = true
	opt_vb.add_child(_detail_check)
	grid.add_child(opt_vb)

	# File path
	var path_lbl := Label.new()
	path_lbl.text = "保存先ファイルパス:"
	grid.add_child(path_lbl)

	var path_hb := HBoxContainer.new()
	path_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.text = "user://scene_graph.svg"
	path_hb.add_child(_path_edit)

	var browse_btn := Button.new()
	browse_btn.text = "参照…"
	browse_btn.pressed.connect(_on_browse_export_path)
	path_hb.add_child(browse_btn)
	grid.add_child(path_hb)

	_export_msg = Label.new()
	_export_msg.text = ""
	_export_msg.add_theme_color_override("font_color", Color("#fbbf24"))
	_export_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_export_msg)

	var btn_hb := HBoxContainer.new()
	btn_hb.alignment = BoxContainer.ALIGNMENT_END
	btn_hb.add_theme_constant_override("separation", 10)
	vb.add_child(btn_hb)

	var cancel_btn := Button.new()
	cancel_btn.text = "キャンセル (ESC)"
	cancel_btn.pressed.connect(func() -> void: _export_modal.visible = false)
	btn_hb.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "出力して保存"
	save_btn.pressed.connect(_execute_export)
	btn_hb.add_child(save_btn)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_selected.connect(func(p: String) -> void:
		_path_edit.text = p
	)
	add_child(_file_dialog)


func _on_export_format_changed(idx: int) -> void:
	var cur := _path_edit.text.strip_edges()
	if idx == 0:
		if cur.ends_with(".png"):
			_path_edit.text = cur.substr(0, cur.length() - 4) + ".svg"
		elif not cur.ends_with(".svg"):
			_path_edit.text = cur + ".svg"
	else:
		if cur.ends_with(".svg"):
			_path_edit.text = cur.substr(0, cur.length() - 4) + ".png"
		elif not cur.ends_with(".png"):
			_path_edit.text = cur + ".png"


func _on_browse_export_path() -> void:
	if _file_dialog == null:
		return
	_file_dialog.clear_filters()
	if _fmt_opt.selected == 0:
		_file_dialog.add_filter("*.svg ; SVG Image")
		_file_dialog.current_file = "scene_graph.svg"
	else:
		_file_dialog.add_filter("*.png ; PNG Image")
		_file_dialog.current_file = "scene_graph.png"
	_file_dialog.popup_centered(Vector2i(600, 420))


func _open_export_dialog() -> void:
	_export_msg.text = ""
	if _fmt_opt.selected == 0 and not _path_edit.text.ends_with(".svg"):
		_path_edit.text = "user://scene_graph.svg"
	elif _fmt_opt.selected == 1 and not _path_edit.text.ends_with(".png"):
		_path_edit.text = "user://scene_graph.png"
	_export_modal.visible = true


func _execute_export() -> void:
	var path := _path_edit.text.strip_edges()
	if path == "":
		_export_msg.text = "保存先ファイルパスを入力してください。"
		return
	var is_svg := (_fmt_opt.selected == 0)
	var use_overview := (_target_opt.selected == 1)
	var scale_mult := 1.0
	if _scale_opt.selected == 1:
		scale_mult = 1.5
	elif _scale_opt.selected == 2:
		scale_mult = 2.0
	var include_bg := _bg_check.button_pressed
	var include_details := _detail_check.button_pressed

	var target_layout := _layout
	if use_overview and _mode != SceneGraph.MODE_OVERVIEW:
		target_layout = SceneGraph.compute_layout(graph, SceneGraph.MODE_OVERVIEW, "", ThemeDB.fallback_font, 13)

	var opts := {
		"scale": scale_mult,
		"transparent_bg": not include_bg,
		"include_details": include_details
	}

	if is_svg:
		if not path.to_lower().ends_with(".svg"):
			path += ".svg"
		var svg_text := SceneGraph.to_svg(graph, target_layout, opts)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_export_msg.text = "ファイルの書き込みに失敗しました: " + path
			return
		f.store_string(svg_text)
		f.close()
	else:
		if not path.to_lower().ends_with(".png"):
			path += ".png"
		var img := await _render_png_with_text(target_layout, opts)
		if img == null:
			img = SceneGraph.to_png_image(graph, target_layout, opts)
		var err := img.save_png(path)
		if err != OK:
			_export_msg.text = "PNGの保存に失敗しました (エラーコード %d): %s" % [err, path]
			return

	var global_path := ProjectSettings.globalize_path(path) if (path.begins_with("user://") or path.begins_with("res://")) else path
	_export_modal.visible = false
	_status_label.text = "出力完了: " + global_path


func _render_png_with_text(target_layout: Dictionary, opts: Dictionary) -> Image:
	if not is_inside_tree():
		return SceneGraph.to_png_image(graph, target_layout, opts)
	var scale_mult: float = float(opts.get("scale", 1.0))
	var bounds: Rect2 = target_layout.get("bounds", Rect2(0, 0, 800, 480))
	var vp_size := Vector2i(
		clampi(int(ceil(bounds.size.x * scale_mult)), 320, 4096),
		clampi(int(ceil(bounds.size.y * scale_mult)), 240, 4096)
	)
	var sub_vp := SubViewport.new()
	sub_vp.size = vp_size
	sub_vp.transparent_bg = bool(opts.get("transparent_bg", false))
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(sub_vp)

	var render_canvas := _GraphCanvas.new()
	render_canvas.size = Vector2(vp_size)
	render_canvas.set_layout_for_export(target_layout, scale_mult, not sub_vp.transparent_bg)
	sub_vp.add_child(render_canvas)

	await RenderingServer.frame_post_draw
	var tex := sub_vp.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	sub_vp.queue_free()
	return img


# --- Navigation & History ---

func _on_node_clicked(node_id: String) -> void:
	var nodes_dict: Dictionary = graph.get("nodes", {})
	if node_id == "" or not nodes_dict.has(node_id):
		return
	if _mode == SceneGraph.MODE_NODE_DETAIL and _focus_id == node_id:
		return
	_set_view(SceneGraph.MODE_NODE_DETAIL, node_id, true)


func _on_edge_clicked(edge_id: String) -> void:
	var edge_map: Dictionary = graph.get("edge_map", {})
	if edge_id == "" or not edge_map.has(edge_id):
		return
	if _mode == SceneGraph.MODE_EDGE_DETAIL and _focus_id == edge_id:
		return
	_set_view(SceneGraph.MODE_EDGE_DETAIL, edge_id, true)


func _on_overview_pressed() -> void:
	if _mode == SceneGraph.MODE_OVERVIEW:
		if _canvas != null:
			_canvas.fit_to_view()
		return
	_set_view(SceneGraph.MODE_OVERVIEW, "", true)


func _set_view(new_mode: String, new_focus: String, record_history: bool) -> void:
	if record_history:
		if _history.is_empty() or String(_history.back().get("mode", "")) != _mode or String(_history.back().get("focus_id", "")) != _focus_id:
			_history.append({"mode": _mode, "focus_id": _focus_id})
	_mode = new_mode
	_focus_id = new_focus
	_rebuild_layout(true)


func _step_back_history() -> void:
	if _history.is_empty():
		if _mode != SceneGraph.MODE_OVERVIEW:
			_set_view(SceneGraph.MODE_OVERVIEW, "", false)
		return
	var prev: Dictionary = _history.pop_back()
	_mode = String(prev.get("mode", SceneGraph.MODE_OVERVIEW))
	_focus_id = String(prev.get("focus_id", ""))
	_rebuild_layout(true)


func _rebuild_layout(reset_camera: bool) -> void:
	_layout = SceneGraph.compute_layout(graph, _mode, _focus_id, ThemeDB.fallback_font, 13)
	if _canvas != null:
		_canvas.set_graph_data(_layout, reset_camera)
	_update_toolbar()
	_rebuild_detail_panel()


func _update_toolbar() -> void:
	if _title_label == null:
		return
	var nodes_dict: Dictionary = graph.get("nodes", {})
	var edges_list: Array = graph.get("edges", [])
	var edge_map: Dictionary = graph.get("edge_map", {})
	match _mode:
		SceneGraph.MODE_OVERVIEW:
			_title_label.text = "シーングラフ: 全体図 (%d シーン / %d 遷移)" % [nodes_dict.size(), edges_list.size()]
		SceneGraph.MODE_NODE_DETAIL:
			var nd: Dictionary = nodes_dict.get(_focus_id, {})
			var nm := String(nd.get("name", _focus_id))
			_title_label.text = "シーングラフ: ノード詳細 [%s (%s)] — ノード外の遷移は点線表示" % [nm, _focus_id]
		SceneGraph.MODE_EDGE_DETAIL:
			var ed: Dictionary = edge_map.get(_focus_id, {})
			var f_id := String(ed.get("from", ""))
			var t_id := String(ed.get("to", ""))
			_title_label.text = "シーングラフ: 遷移詳細 [%s → %s] — 対象外の遷移は点線表示" % [f_id, t_id]
	if _history_label != null:
		_history_label.text = ("履歴: %d" % _history.size()) if not _history.is_empty() else ""
	if _back_btn != null:
		_back_btn.disabled = _history.is_empty() and _mode == SceneGraph.MODE_OVERVIEW
	if _overview_btn != null:
		_overview_btn.disabled = (_mode == SceneGraph.MODE_OVERVIEW)


# --- Right Detail Inspector ---

func _rebuild_detail_panel() -> void:
	if _detail_vbox == null:
		return
	for ch in _detail_vbox.get_children():
		ch.queue_free()

	var nodes_dict: Dictionary = graph.get("nodes", {})
	if nodes_dict.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "シーンデータがありません。"
		_detail_vbox.add_child(empty_lbl)
		return

	match _mode:
		SceneGraph.MODE_OVERVIEW:
			_build_overview_inspector()
		SceneGraph.MODE_NODE_DETAIL:
			_build_node_detail_inspector(_focus_id)
		SceneGraph.MODE_EDGE_DETAIL:
			_build_edge_detail_inspector(_focus_id)


func _add_section_header(title_text: String, color: Color = Color("#93c5fd")) -> void:
	var lbl := Label.new()
	lbl.text = title_text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 14)
	_detail_vbox.add_child(lbl)


func _add_info_line(text: String, color: Color = Color("#e2e8f0")) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 12)
	_detail_vbox.add_child(lbl)


func _build_overview_inspector() -> void:
	var nodes_dict: Dictionary = graph.get("nodes", {})
	var edges_list: Array = graph.get("edges", [])
	var start_sc := String(graph.get("start_scene", ""))

	_add_section_header("■ 全体図サマリー", Color("#60a5fa"))
	_add_info_line("開始シーン: %s" % (start_sc if start_sc != "" else "(未設定)"))
	if current_scene_id != "":
		_add_info_line("現在実行中のシーン: %s" % current_scene_id, Color("#34d399"))
	_add_info_line("シーン数: %d / 遷移数: %d" % [nodes_dict.size(), edges_list.size()])
	_detail_vbox.add_child(HSeparator.new())

	_add_section_header("■ シーン一覧 (クリックで詳細図へ)", Color("#93c5fd"))
	var order: Array = graph.get("node_order", nodes_dict.keys())
	for sid_v in order:
		var sid := String(sid_v)
		if not nodes_dict.has(sid):
			continue
		var nd: Dictionary = nodes_dict[sid]
		var sname := String(nd.get("name", sid))
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var badge := ""
		if sid == start_sc:
			badge += "[START] "
		if sid == current_scene_id and current_scene_id != "":
			badge += "[現在] "
		btn.text = "%s%s (%s)" % [badge, sname, sid]
		btn.pressed.connect(func() -> void: _on_node_clicked(sid))
		_detail_vbox.add_child(btn)

	_detail_vbox.add_child(HSeparator.new())
	_add_section_header("■ 遷移一覧 (クリックで遷移詳細へ)", Color("#f59e0b"))
	for ed in edges_list:
		if not (ed is Dictionary):
			continue
		var eid := String(ed.get("id", ""))
		var f_id := String(ed.get("from", ""))
		var t_id := String(ed.get("to", ""))
		var summary := String(ed.get("summary", "移動"))
		var ebtn := Button.new()
		ebtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ebtn.text = "%s → %s [%s]" % [f_id, t_id, summary]
		ebtn.pressed.connect(func() -> void: _on_edge_clicked(eid))
		_detail_vbox.add_child(ebtn)


func _build_node_detail_inspector(node_id: String) -> void:
	var nodes_dict: Dictionary = graph.get("nodes", {})
	var edges_list: Array = graph.get("edges", [])
	var nd: Dictionary = nodes_dict.get(node_id, {})
	if nd.is_empty():
		_add_info_line("指定されたノードが見つかりません: " + node_id)
		return

	_add_section_header("■ シーン詳細: %s (%s)" % [String(nd.get("name", node_id)), node_id], Color("#60a5fa"))
	_add_info_line("定義ファイル: %s" % String(nd.get("file", "")), Color("#94a3b8"))
	_add_info_line("背景画像: %s" % String(nd.get("image", "（なし）")))

	# Sprites
	var sprites: Array = nd.get("sprites", [])
	if not sprites.is_empty():
		_add_section_header("▼ レイヤースプライト (%d)" % sprites.size(), Color("#a78bfa"))
		for sp in sprites:
			if sp is Dictionary:
				var w := String(sp.get("when", ""))
				_add_info_line("・[%s] %s (条件: %s)" % [
					String(sp.get("id", "")),
					String(sp.get("image", "")),
					w if w != "" else "無条件"
				])

	# First / Enter effects
	var first_info: Dictionary = nd.get("first", {})
	var enter_info: Dictionary = nd.get("enter", {})
	var first_fx: Array = first_info.get("effects", [])
	var enter_fx: Array = enter_info.get("effects", [])
	if not first_fx.is_empty() or not enter_fx.is_empty():
		_add_section_header("▼ 入室時データ変更 (first / enter)", Color("#34d399"))
		if not first_fx.is_empty():
			_add_info_line("初回入室 (first): " + ", ".join(PackedStringArray(first_fx)))
		if not enter_fx.is_empty():
			_add_info_line("毎回入室 (enter): " + ", ".join(PackedStringArray(enter_fx)))

	# Outgoing transitions
	_detail_vbox.add_child(HSeparator.new())
	var out_edges: Array = []
	var in_edges: Array = []
	for ed in edges_list:
		if ed is Dictionary:
			if String(ed.get("from", "")) == node_id:
				out_edges.append(ed)
			if String(ed.get("to", "")) == node_id:
				in_edges.append(ed)

	_add_section_header("▼ このシーンからの遷移 (%d)" % out_edges.size(), Color("#60a5fa"))
	if out_edges.is_empty():
		_add_info_line("（遷移先なし）", Color("#94a3b8"))
	for ed in out_edges:
		var eid := String(ed.get("id", ""))
		var to_id := String(ed.get("to", ""))
		var to_nd: Dictionary = nodes_dict.get(to_id, {})
		var to_name := String(to_nd.get("name", to_id))
		var hb := HBoxContainer.new()
		var edge_btn := Button.new()
		edge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edge_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		edge_btn.text = "→ %s (%s) : %s" % [to_name, to_id, String(ed.get("summary", ""))]
		edge_btn.pressed.connect(func() -> void: _on_edge_clicked(eid))
		hb.add_child(edge_btn)

		var node_btn := Button.new()
		node_btn.text = "ノードへ"
		node_btn.pressed.connect(func() -> void: _on_node_clicked(to_id))
		hb.add_child(node_btn)
		_detail_vbox.add_child(hb)

		var trigs: Array = ed.get("triggers", [])
		for trig in trigs:
			if trig is Dictionary:
				var fx: Array = trig.get("effects", [])
				var fx_str := (" / データ変更: " + ", ".join(PackedStringArray(fx))) if not fx.is_empty() else ""
				_add_info_line("   ・[%s / %s] 条件: %s%s" % [
					String(trig.get("source", "")),
					String(trig.get("verb", "")),
					String(trig.get("condition", "（無条件）")),
					fx_str
				], Color("#cbd5e1"))

	# Incoming transitions
	_detail_vbox.add_child(HSeparator.new())
	_add_section_header("▼ このシーンへの流入遷移 (%d)" % in_edges.size(), Color("#34d399"))
	if in_edges.is_empty():
		_add_info_line("（流入遷移なし）", Color("#94a3b8"))
	for ed in in_edges:
		var eid := String(ed.get("id", ""))
		var from_id := String(ed.get("from", ""))
		var from_nd: Dictionary = nodes_dict.get(from_id, {})
		var from_name := String(from_nd.get("name", from_id))
		var hb := HBoxContainer.new()
		var edge_btn := Button.new()
		edge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edge_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		edge_btn.text = "← %s (%s) : %s" % [from_name, from_id, String(ed.get("summary", ""))]
		edge_btn.pressed.connect(func() -> void: _on_edge_clicked(eid))
		hb.add_child(edge_btn)

		var node_btn := Button.new()
		node_btn.text = "ノードへ"
		node_btn.pressed.connect(func() -> void: _on_node_clicked(from_id))
		hb.add_child(node_btn)
		_detail_vbox.add_child(hb)

	# Objects & conditions/data in this scene
	_detail_vbox.add_child(HSeparator.new())
	var objs: Array = nd.get("objects", [])
	_add_section_header("▼ シーン内オブジェクト・条件・データ (%d)" % objs.size(), Color("#fbbf24"))
	for obj in objs:
		if not (obj is Dictionary):
			continue
		var oid := String(obj.get("id", ""))
		var olabel := String(obj.get("label", oid))
		var owhen := String(obj.get("when", ""))
		_add_info_line("● %s (%s) [表示条件: %s]" % [olabel, oid, owhen if owhen != "" else "無条件"], Color("#fde68a"))
		var actions: Array = obj.get("actions", [])
		for act in actions:
			if act is Dictionary:
				var vname := String(act.get("verb", ""))
				var conds: Array = act.get("conditions", [])
				var fxs: Array = act.get("effects", [])
				var c_str := ", ".join(PackedStringArray(conds)) if not conds.is_empty() else "無条件"
				var f_str := (" → " + ", ".join(PackedStringArray(fxs))) if not fxs.is_empty() else ""
				_add_info_line("   [%s] 条件: %s%s" % [vname, c_str, f_str], Color("#cbd5e1"))


func _build_edge_detail_inspector(edge_id: String) -> void:
	var nodes_dict: Dictionary = graph.get("nodes", {})
	var edge_map: Dictionary = graph.get("edge_map", {})
	var ed: Dictionary = edge_map.get(edge_id, {})
	if ed.is_empty():
		_add_info_line("指定された遷移が見つかりません: " + edge_id)
		return

	var from_id := String(ed.get("from", ""))
	var to_id := String(ed.get("to", ""))
	var from_nd: Dictionary = nodes_dict.get(from_id, {})
	var to_nd: Dictionary = nodes_dict.get(to_id, {})
	var from_name := String(from_nd.get("name", from_id))
	var to_name := String(to_nd.get("name", to_id))

	_add_section_header("■ 遷移詳細: %s → %s" % [from_name, to_name], Color("#f59e0b"))
	_add_info_line("条件概要: %s" % String(ed.get("summary", "")), Color("#fde68a"))

	_detail_vbox.add_child(HSeparator.new())
	_add_section_header("▼ 接続ノード (クリックでノード詳細図へ)", Color("#60a5fa"))

	var from_btn := Button.new()
	from_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	from_btn.text = "遷移元ノード: %s (%s) の詳細図を開く" % [from_name, from_id]
	from_btn.pressed.connect(func() -> void: _on_node_clicked(from_id))
	_detail_vbox.add_child(from_btn)

	var to_btn := Button.new()
	to_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	to_btn.text = "遷移先ノード: %s (%s) の詳細図を開く" % [to_name, to_id]
	to_btn.pressed.connect(func() -> void: _on_node_clicked(to_id))
	_detail_vbox.add_child(to_btn)

	_detail_vbox.add_child(HSeparator.new())
	var trigs: Array = ed.get("triggers", [])
	_add_section_header("▼ 遷移トリガー・詳細条件・データ変更 (%d件)" % trigs.size(), Color("#34d399"))
	var idx := 1
	for trig in trigs:
		if not (trig is Dictionary):
			continue
		_add_info_line("#%d 発生箇所: %s" % [idx, String(trig.get("source", ""))], Color("#93c5fd"))
		_add_info_line("   動詞/種別: %s" % String(trig.get("verb", "")))
		_add_info_line("   遷移条件: %s" % String(trig.get("condition", "（無条件）")), Color("#fde68a"))
		var fx: Array = trig.get("effects", [])
		if not fx.is_empty():
			_add_info_line("   データ変更: %s" % ", ".join(PackedStringArray(fx)), Color("#34d399"))
		else:
			_add_info_line("   データ変更: (なし)", Color("#94a3b8"))
		var code_str := String(trig.get("code", ""))
		if code_str != "":
			var code_box := CodeEdit.new()
			code_box.editable = false
			var line_cnt := code_str.split("\n").size()
			code_box.custom_minimum_size = Vector2(0, clampf(line_cnt * 19.0 + 16.0, 48.0, 140.0))
			code_box.text = code_str
			_detail_vbox.add_child(code_box)
		idx += 1


# =============================================================================
# Inner Class: _GraphCanvas (Custom 2D Graph Renderer + Hit Testing + Pan/Zoom)
# =============================================================================

class _GraphCanvas extends Control:
	signal node_clicked(node_id: String)
	signal edge_clicked(edge_id: String)

	var _layout: Dictionary = {}
	var _zoom: float = 1.0
	var _pan: Vector2 = Vector2.ZERO
	var _dragging: bool = false
	var _drag_start_mouse: Vector2 = Vector2.ZERO
	var _drag_start_pan: Vector2 = Vector2.ZERO
	var _press_pos: Vector2 = Vector2.ZERO
	var _hovered_node: String = ""
	var _hovered_edge: String = ""
	var _draw_bg: bool = true

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_graph_data(layout_dict: Dictionary, reset_view: bool) -> void:
		_layout = layout_dict
		_hovered_node = ""
		_hovered_edge = ""
		if reset_view:
			call_deferred("fit_to_view")
		queue_redraw()

	func set_layout_for_export(layout_dict: Dictionary, export_scale: float, draw_bg: bool) -> void:
		_layout = layout_dict
		_zoom = export_scale
		_pan = Vector2.ZERO
		_draw_bg = draw_bg
		queue_redraw()

	func fit_to_view() -> void:
		if _layout.is_empty():
			_zoom = 1.0
			_pan = Vector2.ZERO
			queue_redraw()
			return
		var bounds: Rect2 = _layout.get("bounds", Rect2(0, 0, 800, 480))
		var csize := bounds.size
		var view_sz := size
		if view_sz.x <= 10.0 or view_sz.y <= 10.0:
			view_sz = Vector2(760, 520)
		var zx := (view_sz.x - 24.0) / maxf(csize.x, 1.0)
		var zy := (view_sz.y - 24.0) / maxf(csize.y, 1.0)
		_zoom = clampf(minf(zx, zy), 0.45, 1.35)
		_pan = (view_sz - csize * _zoom) * 0.5
		queue_redraw()

	func _screen_to_world(pt: Vector2) -> Vector2:
		return (pt - _pan) / maxf(_zoom, 0.05)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_zoom_at(mb.position, 1.12)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_zoom_at(mb.position, 1.0 / 1.12)
				accept_event()
			elif (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT):
				if mb.pressed:
					_dragging = true
					_drag_start_mouse = mb.position
					_drag_start_pan = _pan
					_press_pos = mb.position
				else:
					var was_click := mb.button_index == MOUSE_BUTTON_LEFT and mb.position.distance_to(_press_pos) < 6.0
					_dragging = false
					if was_click:
						_handle_click(_screen_to_world(mb.position))
				accept_event()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _dragging:
				_pan = _drag_start_pan + (mm.position - _drag_start_mouse)
				queue_redraw()
			else:
				_update_hover(_screen_to_world(mm.position))

	func _zoom_at(screen_pt: Vector2, factor: float) -> void:
		var world_before := _screen_to_world(screen_pt)
		_zoom = clampf(_zoom * factor, 0.3, 2.75)
		_pan = screen_pt - world_before * _zoom
		queue_redraw()

	func _handle_click(world_pt: Vector2) -> void:
		var hit_node := _hit_test_node(world_pt)
		if hit_node != "":
			node_clicked.emit(hit_node)
			return
		var hit_edge := _hit_test_edge(world_pt)
		if hit_edge != "":
			edge_clicked.emit(hit_edge)

	func _update_hover(world_pt: Vector2) -> void:
		var hn := _hit_test_node(world_pt)
		var he := "" if hn != "" else _hit_test_edge(world_pt)
		if hn != _hovered_node or he != _hovered_edge:
			_hovered_node = hn
			_hovered_edge = he
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (hn != "" or he != "") else Control.CURSOR_ARROW
			queue_redraw()

	func _hit_test_node(world_pt: Vector2) -> String:
		var layout_nodes: Dictionary = _layout.get("nodes", {})
		for nid_v in layout_nodes.keys():
			var nid := String(nid_v)
			var nd: Dictionary = layout_nodes[nid]
			var r: Rect2 = nd.get("rect", Rect2())
			if r.has_point(world_pt):
				return nid
		return ""

	func _hit_test_edge(world_pt: Vector2) -> String:
		var layout_edges: Array = _layout.get("edges", [])
		for ed in layout_edges:
			if not (ed is Dictionary):
				continue
			var lrect: Rect2 = ed.get("label_rect", Rect2()).grow(3.0)
			if lrect.has_point(world_pt):
				return String(ed.get("id", ""))
		for ed in layout_edges:
			if not (ed is Dictionary):
				continue
			var p1: Vector2 = ed.get("start", Vector2.ZERO)
			var p2: Vector2 = ed.get("end", Vector2.ZERO)
			var closest := Geometry2D.get_closest_point_to_segment(world_pt, p1, p2)
			if world_pt.distance_to(closest) <= 9.0:
				return String(ed.get("id", ""))
		return ""

	func _draw() -> void:
		if _draw_bg:
			draw_rect(Rect2(Vector2.ZERO, size), Color("#0f172a"), true)

		if _layout.is_empty():
			return

		draw_set_transform(_pan, 0.0, Vector2(_zoom, _zoom))

		var font := ThemeDB.fallback_font
		var layout_nodes: Dictionary = _layout.get("nodes", {})
		var layout_edges: Array = _layout.get("edges", [])

		# 1. Draw Edge Lines & Arrowheads (dashed external edges first, then solid focused edges)
		for pass_idx in range(2):
			for ed in layout_edges:
				if not (ed is Dictionary):
					continue
				var dashed := bool(ed.get("dashed", false))
				if (pass_idx == 0 and not dashed) or (pass_idx == 1 and dashed):
					continue
				var eid := String(ed.get("id", ""))
				var highlighted := bool(ed.get("highlighted", false)) or (eid == _hovered_edge)
				var p1: Vector2 = ed.get("start", Vector2.ZERO)
				var p2: Vector2 = ed.get("end", Vector2.ZERO)
				var arrow: PackedVector2Array = ed.get("arrow", PackedVector2Array())

				var line_col := Color("#64748b") if dashed else (Color("#f59e0b") if highlighted else Color("#60a5fa"))
				if eid == _hovered_edge:
					line_col = Color("#fbbf24")
				var line_w := 1.6 if dashed else (3.0 if highlighted else 2.2)

				if dashed:
					draw_dashed_line(p1, p2, line_col, line_w, 7.0, true)
				else:
					draw_line(p1, p2, line_col, line_w, true)

				if arrow.size() >= 3:
					draw_colored_polygon(arrow, line_col)

		# 2. Draw Scene Nodes
		for nid_v in _layout.get("node_order", layout_nodes.keys()):
			var nid := String(nid_v)
			if not layout_nodes.has(nid):
				continue
			var nd: Dictionary = layout_nodes[nid]
			var rect: Rect2 = nd.get("rect", Rect2())
			var role := String(nd.get("role", "normal"))
			var focused := (role == "focus")
			var external := bool(nd.get("dashed", false))
			var is_start := bool(nd.get("is_start", false))
			var is_cur := bool(nd.get("is_current", false))
			var is_hover := (nid == _hovered_node)

			var fill_col := Color("#172033") if external else (Color("#1e3a8a") if focused else Color("#1e293b"))
			var border_col := Color("#475569") if external else (Color("#ffd166") if focused else (Color("#34d399") if is_cur else Color("#60a5fa")))
			if is_hover:
				border_col = Color("#fbbf24")
			var border_w := 2.8 if (focused or is_hover) else 1.8

			draw_rect(rect, fill_col, true)
			if external:
				_draw_dashed_rect(rect, border_col, border_w, 6.0)
			else:
				draw_rect(rect, border_col, false, border_w)

			if font != null:
				var title := String(nd.get("name", nid))
				var badge := ""
				if is_start:
					badge += "[START] "
				if is_cur:
					badge += "[現在] "
				var header_str := "%s%s (%s)" % [badge, title, nid]
				var title_col := Color("#94a3b8") if external else Color("#f8fafc")
				draw_string(
					font,
					Vector2(rect.position.x + 10.0, rect.position.y + 22.0),
					header_str,
					HORIZONTAL_ALIGNMENT_LEFT,
					rect.size.x - 16.0,
					13,
					title_col
				)

				var sub_col := Color("#64748b") if external else Color("#cbd5e1")
				var sy := rect.position.y + 42.0
				for sl in nd.get("sub_lines", []):
					draw_string(
						font,
						Vector2(rect.position.x + 10.0, sy),
						String(sl),
						HORIZONTAL_ALIGNMENT_LEFT,
						rect.size.x - 16.0,
						11,
						sub_col
					)
					sy += 18.0

		# 3. Draw Edge Transition Labels on top of nodes (multi-line so they never hide behind nodes)
		for pass_idx in range(2):
			for ed in layout_edges:
				if not (ed is Dictionary):
					continue
				var dashed := bool(ed.get("dashed", false))
				if (pass_idx == 0 and not dashed) or (pass_idx == 1 and dashed):
					continue
				var eid := String(ed.get("id", ""))
				var highlighted := bool(ed.get("highlighted", false)) or (eid == _hovered_edge)
				var pill_rect: Rect2 = ed.get("label_rect", Rect2())
				var line_col := Color("#64748b") if dashed else (Color("#f59e0b") if highlighted else Color("#60a5fa"))
				if eid == _hovered_edge:
					line_col = Color("#fbbf24")

				var pill_bg := Color("#0f172a", 0.92) if dashed else Color("#1e293b", 0.96)
				draw_rect(pill_rect, pill_bg, true)
				if dashed:
					_draw_dashed_rect(pill_rect, line_col, 1.2, 5.0)
				else:
					draw_rect(pill_rect, line_col, false, 1.4)

				if font != null:
					var text_col := Color("#94a3b8") if dashed else (Color("#fef08a") if highlighted else Color("#e2e8f0"))
					var s_lines: Array = ed.get("summary_lines", [])
					if s_lines.is_empty():
						s_lines = [String(ed.get("summary", ""))]
					var ly := pill_rect.position.y + 15.0
					for sl_v in s_lines:
						var line_str := String(sl_v)
						draw_string(
							font,
							Vector2(pill_rect.position.x + 6.0, ly),
							line_str,
							HORIZONTAL_ALIGNMENT_LEFT,
							pill_rect.size.x - 10.0,
							12,
							text_col
						)
						ly += 16.0

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_dashed_rect(r: Rect2, col: Color, width: float, dash: float) -> void:
		var tl := r.position
		var tr := Vector2(r.end.x, r.position.y)
		var br := r.end
		var bl := Vector2(r.position.x, r.end.y)
		draw_dashed_line(tl, tr, col, width, dash, true)
		draw_dashed_line(tr, br, col, width, dash, true)
		draw_dashed_line(br, bl, col, width, dash, true)
		draw_dashed_line(bl, tl, col, width, dash, true)
