@tool
class_name AdvDebugConsole
extends Panel
## ゲーム実行中のデバッグコンソール（デバッグビルド専用・配布アプリには含めない）。
##
## 画面を2x2で区切った1領域（最大で画面の1/4サイズ：640x400時は320x200）に収まるコンパクト設計。
## 主な機能:
## 1. 現在のゲーム状態データ（変数・フラグ・所持アイテム・シーン・進行状況）の表示
## 2. 現在位置・直近実行箇所および現在シーン内の前後のシナリオコード表示
## 3. シナリオのスクリプトファイル自体は一切変更せず、メモリ上のデータを変更するコマンド＆GUI操作
## 4. 変更後に再開すると、変更後のデータでゲーム処理（スプライト・背景・UI・ホットスポット等）を即時反映
## 5. 閉じるボタン、またはコマンド入力待ち時のESCキー押下でコンソールを閉じてゲーム再開

signal closed()
signal open_scene_graph_requested()
signal data_modified(scene_changed: bool)

const SceneGraph = preload("res://addons/adv80s/debug/adv_scene_graph.gd")

const QUADRANT_NAMES: Array[String] = ["左上↖", "右上↗", "左下↙", "右下↘"]

var core: AdvCore
var _dirty_data: bool = false
var _dirty_scene: bool = false
## 2x2で区切った4領域のどこに表示するか (0:左上, 1:右上, 2:左下, 3:右下)
var _quadrant: int = 3
var _active_page: int = 0

# Command history
var _cmd_history: Array[String] = []
var _cmd_history_idx: int = -1

# Scenario code targets in current scene: Array of {"label": String, "path": String, "steps": Array, "active_idx": int}
var _code_targets: Array[Dictionary] = []

# UI elements
var _header_status: Label
var _quad_btn: Button
var _tab_btns: Array[Button] = []
var _pages: Array[Control] = []
var _state_summary_lbl: Label
var _vars_vbox: VBoxContainer
var _items_vbox: VBoxContainer
var _scene_opt: OptionButton
var _code_target_opt: OptionButton
var _code_view: CodeEdit
var _log_view: RichTextLabel
var _cmd_input: LineEdit


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.09, 0.16, 0.96)
	bg_style.border_color = Color("#38bdf8")
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", bg_style)
	_build_ui()
	_apply_quadrant_layout()


func _ready() -> void:
	_apply_quadrant_layout()
	refresh_all()
	if _cmd_input != null:
		_cmd_input.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_quadrant_layout()


## 画面を2x2で区切った1領域（最大で画面の1/4）にアンカーとサイズを収める。
func _apply_quadrant_layout() -> void:
	var col: int = _quadrant % 2
	var row: int = _quadrant / 2
	anchor_left = 0.0 if col == 0 else 0.5
	anchor_right = 0.5 if col == 0 else 1.0
	anchor_top = 0.0 if row == 0 else 0.5
	anchor_bottom = 0.5 if row == 0 else 1.0
	offset_left = 2.0
	offset_top = 2.0
	offset_right = -2.0
	offset_bottom = -2.0
	if _quad_btn != null and _quadrant >= 0 and _quadrant < QUADRANT_NAMES.size():
		_quad_btn.text = QUADRANT_NAMES[_quadrant]


func _cycle_quadrant() -> void:
	_quadrant = (_quadrant + 1) % 4
	_apply_quadrant_layout()


func setup(p_core: AdvCore) -> void:
	core = p_core
	_dirty_data = false
	_dirty_scene = false
	refresh_all()
	if _log_view != null:
		_log_view.clear()
	_append_log("[color=#38bdf8]== adv80s デバッグコンソール (help:一覧 / ESC:閉) ==[/color]")
	_print_compact_snapshot()
	if _cmd_input != null:
		_cmd_input.call_deferred("grab_focus")


## ESCキー処理（コマンド入力待ちのときにESCキーを押すとコンソールを閉じる）。
func handle_escape() -> bool:
	close_and_resume()
	return true


func close_and_resume() -> void:
	if _dirty_data or _dirty_scene:
		data_modified.emit(_dirty_scene)
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_and_resume()
			accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_and_resume()
			get_viewport().set_input_as_handled()


func _style_compact_button(btn: Button, font_sz: int = 9) -> void:
	btn.add_theme_font_size_override("font_size", font_sz)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b")
	sb.border_color = Color("#475569")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color("#334155")
	sb_hover.border_color = Color("#38bdf8")
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color("#0f172a")
	sb_pressed.border_color = Color("#38bdf8")
	btn.add_theme_stylebox_override("pressed", sb_pressed)


func _style_compact_line_edit(le: LineEdit, font_sz: int = 9) -> void:
	le.add_theme_font_size_override("font_size", font_sz)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#090d16")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	le.add_theme_stylebox_override("normal", sb)
	var sb_focus := sb.duplicate() as StyleBoxFlat
	sb_focus.border_color = Color("#38bdf8")
	le.add_theme_stylebox_override("focus", sb_focus)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.clip_contents = true
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.clip_contents = true
	root_vbox.add_theme_constant_override("separation", 2)
	margin.add_child(root_vbox)

	# --- 1. Header Bar ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 3)
	root_vbox.add_child(top_bar)

	var title_lbl := Label.new()
	title_lbl.text = "DBG"
	title_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	title_lbl.add_theme_font_size_override("font_size", 10)
	top_bar.add_child(title_lbl)

	_header_status = Label.new()
	_header_status.text = ""
	_header_status.clip_text = true
	_header_status.add_theme_color_override("font_color", Color("#fbbf24"))
	_header_status.add_theme_font_size_override("font_size", 9)
	_header_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_header_status)

	_quad_btn = Button.new()
	_quad_btn.text = QUADRANT_NAMES[_quadrant]
	_quad_btn.tooltip_text = "表示位置を画面4分割(2x2)の別領域へ移動します"
	_style_compact_button(_quad_btn, 9)
	_quad_btn.pressed.connect(_cycle_quadrant)
	top_bar.add_child(_quad_btn)

	var graph_btn := Button.new()
	graph_btn.text = "図(F11)"
	graph_btn.tooltip_text = "シーングラフを開く (F11)"
	_style_compact_button(graph_btn, 9)
	graph_btn.pressed.connect(func() -> void:
		open_scene_graph_requested.emit()
	)
	top_bar.add_child(graph_btn)

	var close_btn := Button.new()
	close_btn.text = "閉(ESC)"
	close_btn.tooltip_text = "デバッグコンソールを閉じて再開 (ESC)"
	_style_compact_button(close_btn, 9)
	close_btn.pressed.connect(close_and_resume)
	top_bar.add_child(close_btn)

	# --- 2. Compact Mode Switcher Bar ---
	var mode_bar := HBoxContainer.new()
	mode_bar.add_theme_constant_override("separation", 2)
	root_vbox.add_child(mode_bar)

	var tab_titles: Array[String] = ["ログ・状態", "前後コード", "変数変更", "所持・移動"]
	_tab_btns.clear()
	for i in range(tab_titles.size()):
		var idx: int = i
		var tbtn := Button.new()
		tbtn.text = tab_titles[i]
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_compact_button(tbtn, 9)
		tbtn.pressed.connect(func() -> void: _switch_page(idx))
		mode_bar.add_child(tbtn)
		_tab_btns.append(tbtn)

	# --- 3. Content Area (Pages 0..3) ---
	var page_holder := Control.new()
	page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_holder.clip_contents = true
	root_vbox.add_child(page_holder)

	_pages.clear()

	# === Page 0: ログ・状態 (Current state header + Console Output) ===
	var page_log := VBoxContainer.new()
	page_log.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_log.clip_contents = true
	page_log.add_theme_constant_override("separation", 2)
	page_holder.add_child(page_log)
	_pages.append(page_log)

	_state_summary_lbl = Label.new()
	_state_summary_lbl.text = "現在シーン: -"
	_state_summary_lbl.clip_text = true
	_state_summary_lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	_state_summary_lbl.add_theme_font_size_override("font_size", 9)
	page_log.add_child(_state_summary_lbl)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.clip_contents = true
	var lp_style := StyleBoxFlat.new()
	lp_style.bg_color = Color("#090d16")
	lp_style.border_color = Color("#334155")
	lp_style.set_border_width_all(1)
	lp_style.content_margin_left = 4
	lp_style.content_margin_right = 4
	lp_style.content_margin_top = 2
	lp_style.content_margin_bottom = 2
	log_panel.add_theme_stylebox_override("panel", lp_style)
	page_log.add_child(log_panel)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_font_size_override("normal_font_size", 9)
	_log_view.add_theme_font_size_override("bold_font_size", 9)
	log_panel.add_child(_log_view)

	# === Page 1: 前後コード (Surrounding Scenario Code Viewer) ===
	var page_code := VBoxContainer.new()
	page_code.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_code.clip_contents = true
	page_code.add_theme_constant_override("separation", 2)
	page_holder.add_child(page_code)
	_pages.append(page_code)

	_code_target_opt = OptionButton.new()
	_code_target_opt.clip_text = true
	_code_target_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_compact_button(_code_target_opt, 9)
	_code_target_opt.item_selected.connect(_on_code_target_selected)
	page_code.add_child(_code_target_opt)

	_code_view = CodeEdit.new()
	_code_view.editable = false
	_code_view.gutters_draw_line_numbers = false
	_code_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_view.add_theme_font_size_override("font_size", 9)
	page_code.add_child(_code_view)

	# === Page 2: 変数変更 (Variables & Flags GUI Editor) ===
	var page_vars := VBoxContainer.new()
	page_vars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_vars.clip_contents = true
	page_vars.add_theme_constant_override("separation", 2)
	page_holder.add_child(page_vars)
	_pages.append(page_vars)

	var vars_scroll := ScrollContainer.new()
	vars_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vars_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vars_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_vars.add_child(vars_scroll)

	_vars_vbox = VBoxContainer.new()
	_vars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vars_vbox.add_theme_constant_override("separation", 2)
	vars_scroll.add_child(_vars_vbox)

	# === Page 3: 所持・移動 (Scene Jump & Items GUI Editor) ===
	var page_items := VBoxContainer.new()
	page_items.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_items.clip_contents = true
	page_items.add_theme_constant_override("separation", 2)
	page_holder.add_child(page_items)
	_pages.append(page_items)

	var scene_jump_hb := HBoxContainer.new()
	scene_jump_hb.add_theme_constant_override("separation", 2)
	var sj_lbl := Label.new()
	sj_lbl.text = "移動:"
	sj_lbl.add_theme_font_size_override("font_size", 9)
	scene_jump_hb.add_child(sj_lbl)

	_scene_opt = OptionButton.new()
	_scene_opt.clip_text = true
	_scene_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_compact_button(_scene_opt, 9)
	scene_jump_hb.add_child(_scene_opt)

	var jump_btn := Button.new()
	jump_btn.text = "変更"
	_style_compact_button(jump_btn, 9)
	jump_btn.pressed.connect(_on_scene_jump_pressed)
	scene_jump_hb.add_child(jump_btn)
	page_items.add_child(scene_jump_hb)

	var items_scroll := ScrollContainer.new()
	items_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_items.add_child(items_scroll)

	_items_vbox = VBoxContainer.new()
	_items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_vbox.add_theme_constant_override("separation", 2)
	items_scroll.add_child(_items_vbox)

	# --- 4. Bottom Command Bar (Always visible) ---
	var cmd_hb := HBoxContainer.new()
	cmd_hb.add_theme_constant_override("separation", 3)
	root_vbox.add_child(cmd_hb)

	var prompt_lbl := Label.new()
	prompt_lbl.text = ">"
	prompt_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	prompt_lbl.add_theme_font_size_override("font_size", 9)
	cmd_hb.add_child(prompt_lbl)

	_cmd_input = LineEdit.new()
	_cmd_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd_input.placeholder_text = "cmd (set/toggle/give/scene/code/help) ESC:閉"
	_style_compact_line_edit(_cmd_input, 9)
	_cmd_input.text_submitted.connect(_on_command_submitted)
	_cmd_input.gui_input.connect(_on_cmd_input_gui_input)
	cmd_hb.add_child(_cmd_input)

	var exec_btn := Button.new()
	exec_btn.text = "実行"
	_style_compact_button(exec_btn, 9)
	exec_btn.pressed.connect(func() -> void:
		_on_command_submitted(_cmd_input.text)
	)
	cmd_hb.add_child(exec_btn)

	_switch_page(0)


func _switch_page(page_idx: int) -> void:
	_active_page = clampi(page_idx, 0, _pages.size() - 1)
	for i in range(_pages.size()):
		_pages[i].visible = (i == _active_page)
	for i in range(_tab_btns.size()):
		var active: bool = (i == _active_page)
		_tab_btns[i].add_theme_color_override("font_color", Color("#38bdf8") if active else Color("#cbd5e1"))


func _on_cmd_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			close_and_resume()
			_cmd_input.accept_event()
		elif ke.keycode == KEY_UP:
			if not _cmd_history.is_empty():
				if _cmd_history_idx < 0:
					_cmd_history_idx = _cmd_history.size() - 1
				else:
					_cmd_history_idx = maxi(0, _cmd_history_idx - 1)
				_cmd_input.text = _cmd_history[_cmd_history_idx]
				_cmd_input.caret_column = _cmd_input.text.length()
			_cmd_input.accept_event()
		elif ke.keycode == KEY_DOWN:
			if not _cmd_history.is_empty() and _cmd_history_idx >= 0:
				_cmd_history_idx += 1
				if _cmd_history_idx >= _cmd_history.size():
					_cmd_history_idx = -1
					_cmd_input.text = ""
				else:
					_cmd_input.text = _cmd_history[_cmd_history_idx]
					_cmd_input.caret_column = _cmd_input.text.length()
			_cmd_input.accept_event()


# =============================================================================
# State & Scenario Code Refresh
# =============================================================================

func refresh_all() -> void:
	if core == null or core.state == null:
		return
	var dbg_ctx := _get_debug_context()
	_refresh_summary_and_scenes(dbg_ctx)
	_refresh_vars_ui()
	_refresh_items_ui(dbg_ctx)
	_refresh_scenario_code_targets(dbg_ctx)
	_update_header_status()


func _update_header_status() -> void:
	if _header_status == null:
		return
	var sc := core.state.scene if core != null and core.state != null else "-"
	if _dirty_data or _dirty_scene:
		_header_status.text = "[%s] *変更あり(閉で反映)" % sc
	else:
		_header_status.text = "[%s]" % sc


func _get_debug_context() -> Dictionary:
	if core == null:
		return {}
	var res: Variant = core.query("debug_context")
	if res is Dictionary:
		return res
	return {}


func _print_compact_snapshot() -> void:
	if core == null or core.state == null:
		return
	var st := core.state
	var var_parts := PackedStringArray()
	var keys := st.vars.keys()
	keys.sort()
	for k in keys:
		var_parts.append("%s=%s" % [String(k), JSON.stringify(st.vars[k])])
	var vars_str := ", ".join(var_parts) if not var_parts.is_empty() else "(なし)"
	var item_parts := PackedStringArray()
	for iid in st.items.keys():
		var c := st.item_count(String(iid))
		if c > 0:
			item_parts.append("%s:%d" % [String(iid), c])
	var items_str := ", ".join(item_parts) if not item_parts.is_empty() else "(なし)"
	_append_log("[color=#93c5fd][現在データ][/color] scene=[b]%s[/b] | vars: %s | items: %s" % [st.scene, vars_str, items_str])
	if not _code_targets.is_empty():
		var t0: Dictionary = _code_targets[0]
		var steps: Array = t0.get("steps", [])
		var aidx: int = int(t0.get("active_idx", -1))
		_append_log("[color=#fde68a][前後コード][/color] %s" % String(t0.get("label", "")))
		var from_i: int = maxi(0, (aidx if aidx >= 0 else 0) - 1)
		var to_i: int = mini(steps.size() - 1, from_i + 3)
		for i in range(from_i, to_i + 1):
			var mark: String = ">>>" if i == aidx else "   "
			var one_line: String = JSON.stringify(steps[i])
			if one_line.length() > 54:
				one_line = one_line.substr(0, 52) + "…"
			_append_log("  %s[%02d] %s" % [mark, i, one_line])


func _refresh_summary_and_scenes(dbg_ctx: Dictionary) -> void:
	if _state_summary_lbl == null or core == null:
		return
	var st := core.state
	var cur_scene := st.scene
	var scenes_dict: Dictionary = dbg_ctx.get("scenes", {})
	var cur_scene_data: Dictionary = scenes_dict.get(cur_scene, dbg_ctx.get("scene_data", {}))
	var sname := String(cur_scene_data.get("name", cur_scene))
	var visited_cnt: int = st.visited.size()
	_state_summary_lbl.text = "シーン: %s(%s) | 訪問:%d | 変数:%d | 所持:%d" % [
		sname, cur_scene, visited_cnt, st.vars.size(), st.items.size()
	]

	if _scene_opt != null:
		_scene_opt.clear()
		var sids := scenes_dict.keys()
		sids.sort()
		var sel_idx := 0
		var i := 0
		for sid_v in sids:
			var sid := String(sid_v)
			var sd: Dictionary = scenes_dict[sid]
			var nm := String(sd.get("name", sid))
			_scene_opt.add_item("%s (%s)" % [nm, sid], i)
			_scene_opt.set_item_metadata(i, sid)
			if sid == cur_scene:
				sel_idx = i
			i += 1
		if _scene_opt.item_count > 0:
			_scene_opt.select(sel_idx)


func _refresh_vars_ui() -> void:
	if _vars_vbox == null or core == null:
		return
	for ch in _vars_vbox.get_children():
		ch.queue_free()

	var st := core.state
	var all_names: Dictionary = {}
	for k in st.declared.keys():
		all_names[String(k)] = true
	for k in st.vars.keys():
		all_names[String(k)] = true
	var keys := all_names.keys()
	keys.sort()

	# Quick add new variable row
	var add_hb := HBoxContainer.new()
	add_hb.add_theme_constant_override("separation", 2)
	var new_name := LineEdit.new()
	new_name.placeholder_text = "変数名"
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_compact_line_edit(new_name, 9)
	var new_val := LineEdit.new()
	new_val.placeholder_text = "値"
	new_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_compact_line_edit(new_val, 9)
	var add_btn := Button.new()
	add_btn.text = "設定"
	_style_compact_button(add_btn, 9)
	add_btn.pressed.connect(func() -> void:
		var k := new_name.text.strip_edges()
		if k != "":
			_apply_var_change(k, _parse_literal_or_expr(new_val.text))
			new_name.text = ""
			new_val.text = ""
	)
	add_hb.add_child(new_name)
	add_hb.add_child(new_val)
	add_hb.add_child(add_btn)
	_vars_vbox.add_child(add_hb)

	if keys.is_empty():
		var empty_l := Label.new()
		empty_l.text = "変数がありません。"
		empty_l.add_theme_font_size_override("font_size", 9)
		_vars_vbox.add_child(empty_l)
		return

	for k_v in keys:
		var k := String(k_v)
		var val: Variant = st.get_var(k)
		var decl: Dictionary = st.declared.get(k, {})
		var vtype := String(decl.get("type", ""))
		if vtype == "":
			vtype = _infer_type_name(val)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var name_lbl := Label.new()
		name_lbl.text = k
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.tooltip_text = "%s [型: %s / 初期値: %s]" % [k, vtype, str(decl.get("default", null))]
		name_lbl.add_theme_font_size_override("font_size", 9)
		row.add_child(name_lbl)

		if val is bool or vtype == "bool":
			var bval := bool(val)
			var toggle_btn := Button.new()
			toggle_btn.text = "TRUE" if bval else "FALSE"
			_style_compact_button(toggle_btn, 9)
			toggle_btn.add_theme_color_override("font_color", Color("#34d399") if bval else Color("#f87171"))
			toggle_btn.pressed.connect(func() -> void:
				_apply_var_change(k, not bool(core.state.get_var(k)))
			)
			row.add_child(toggle_btn)
		else:
			var val_edit := LineEdit.new()
			val_edit.text = str(val)
			val_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_compact_line_edit(val_edit, 9)
			val_edit.text_submitted.connect(func(new_txt: String) -> void:
				_apply_var_change(k, _coerce_to_declared_type(k, new_txt))
			)
			row.add_child(val_edit)

			var set_btn := Button.new()
			set_btn.text = "適用"
			_style_compact_button(set_btn, 9)
			set_btn.pressed.connect(func() -> void:
				_apply_var_change(k, _coerce_to_declared_type(k, val_edit.text))
			)
			row.add_child(set_btn)

		if decl.has("default"):
			var rst_btn := Button.new()
			rst_btn.text = "初期"
			rst_btn.tooltip_text = "初期値 (%s) に戻します" % str(decl.get("default"))
			_style_compact_button(rst_btn, 9)
			rst_btn.pressed.connect(func() -> void:
				_apply_var_change(k, decl.get("default"))
			)
			row.add_child(rst_btn)

		_vars_vbox.add_child(row)


func _refresh_items_ui(dbg_ctx: Dictionary) -> void:
	if _items_vbox == null or core == null:
		return
	for ch in _items_vbox.get_children():
		ch.queue_free()

	var st := core.state
	var items_defs: Dictionary = dbg_ctx.get("items", {})
	var all_ids: Dictionary = {}
	for iid in items_defs.keys():
		all_ids[String(iid)] = true
	for iid in st.items.keys():
		all_ids[String(iid)] = true
	var ids := all_ids.keys()
	ids.sort()

	var add_hb := HBoxContainer.new()
	add_hb.add_theme_constant_override("separation", 2)
	var id_edit := LineEdit.new()
	id_edit.placeholder_text = "アイテムID"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_compact_line_edit(id_edit, 9)
	var add_btn := Button.new()
	add_btn.text = "+1"
	_style_compact_button(add_btn, 9)
	add_btn.pressed.connect(func() -> void:
		var iid := id_edit.text.strip_edges()
		if iid != "":
			_apply_item_change(iid, 1)
			id_edit.text = ""
	)
	add_hb.add_child(id_edit)
	add_hb.add_child(add_btn)
	_items_vbox.add_child(add_hb)

	for iid_v in ids:
		var iid := String(iid_v)
		var idef: Dictionary = items_defs.get(iid, {})
		var iname := String(idef.get("name", iid))
		var cnt := st.item_count(iid)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var lbl := Label.new()
		lbl.text = "%s (%s)" % [iname, iid]
		lbl.clip_text = true
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color("#34d399") if cnt > 0 else Color("#94a3b8"))
		lbl.add_theme_font_size_override("font_size", 9)
		row.add_child(lbl)

		var cnt_lbl := Label.new()
		cnt_lbl.text = "x%d" % cnt
		cnt_lbl.add_theme_font_size_override("font_size", 9)
		row.add_child(cnt_lbl)

		var plus_btn := Button.new()
		plus_btn.text = "+1"
		_style_compact_button(plus_btn, 9)
		plus_btn.pressed.connect(func() -> void: _apply_item_change(iid, 1))
		row.add_child(plus_btn)

		var minus_btn := Button.new()
		minus_btn.text = "-1"
		minus_btn.disabled = (cnt <= 0)
		_style_compact_button(minus_btn, 9)
		minus_btn.pressed.connect(func() -> void: _apply_item_change(iid, -1))
		row.add_child(minus_btn)

		_items_vbox.add_child(row)


func _refresh_scenario_code_targets(dbg_ctx: Dictionary) -> void:
	_code_targets.clear()
	if _code_target_opt == null:
		return
	_code_target_opt.clear()

	# 1. Active execution stack frames (if paused inside a script or choice)
	var stack: Array = dbg_ctx.get("stack", [])
	if not stack.is_empty():
		for i in range(stack.size() - 1, -1, -1):
			var frame: Dictionary = stack[i]
			var fpath := String(frame.get("path", "stack"))
			var fsteps: Array = frame.get("steps", [])
			var fidx := int(frame.get("index", 0)) - 1
			_code_targets.append({
				"label": "[実行中] %s (#%d)" % [fpath, maxi(0, fidx)],
				"path": fpath,
				"steps": fsteps,
				"active_idx": maxi(0, fidx)
			})

	# 2. Last executed trace (most recently executed block & step)
	var last_trace: Dictionary = dbg_ctx.get("last_trace", {})
	if not last_trace.is_empty():
		var lpath := String(last_trace.get("path", ""))
		var lsteps: Array = last_trace.get("steps", [])
		var lidx := int(last_trace.get("index", 0))
		if not lsteps.is_empty():
			_code_targets.append({
				"label": "[直近] %s (#%d)" % [lpath, lidx],
				"path": lpath,
				"steps": lsteps,
				"active_idx": lidx
			})

	# 3. Current scene blocks (first, enter, objects.<id>.on.<verb>, scene.on.<verb>)
	var cur_scene := core.state.scene if core != null and core.state != null else ""
	var scene_data: Dictionary = dbg_ctx.get("scene_data", {})
	if not scene_data.is_empty():
		for hook in ["first", "enter"]:
			if scene_data.has(hook) and scene_data[hook] is Array:
				_code_targets.append({
					"label": "[%s] %s" % [cur_scene, hook],
					"path": "%s/%s" % [cur_scene, hook],
					"steps": scene_data[hook],
					"active_idx": -1
				})
		var objs: Dictionary = scene_data.get("objects", {})
		for oid_v in objs.keys():
			var oid := String(oid_v)
			var odef: Variant = objs[oid_v]
			if odef is Dictionary:
				var oname := String((odef as Dictionary).get("name", oid))
				var on_map: Variant = (odef as Dictionary).get("on", {})
				if on_map is Dictionary:
					for verb_v in (on_map as Dictionary).keys():
						var verb := String(verb_v)
						var vsteps: Variant = (on_map as Dictionary)[verb_v]
						if vsteps is Array:
							_code_targets.append({
								"label": "[%s] %s/%s" % [cur_scene, oname, verb],
								"path": "%s/%s/%s" % [cur_scene, oid, verb],
								"steps": vsteps,
								"active_idx": -1
							})
		var scene_on: Variant = scene_data.get("on", {})
		if scene_on is Dictionary:
			for verb_v in (scene_on as Dictionary).keys():
				var verb := String(verb_v)
				var vsteps: Variant = (scene_on as Dictionary)[verb_v]
				if vsteps is Array:
					_code_targets.append({
						"label": "[%s] scene/%s" % [cur_scene, verb],
						"path": "%s/scene/%s" % [cur_scene, verb],
						"steps": vsteps,
						"active_idx": -1
					})

	# 4. Dialogues
	var dlgs: Dictionary = dbg_ctx.get("dialogues", {})
	for did_v in dlgs.keys():
		var did := String(did_v)
		var ddef: Variant = dlgs[did_v]
		if ddef is Dictionary and (ddef as Dictionary).get("steps") is Array:
			_code_targets.append({
				"label": "[会話] %s" % did,
				"path": "dlg:%s" % did,
				"steps": (ddef as Dictionary).get("steps"),
				"active_idx": -1
			})

	# 5. Ink adapter context if active
	var ink_info: Dictionary = dbg_ctx.get("ink", {})
	if not ink_info.is_empty() and bool(ink_info.get("active", false)):
		var ink_lines: Array = ink_info.get("lines", [])
		_code_targets.insert(0, {
			"label": "[Ink] %s (%s)" % [String(ink_info.get("file", "")), String(ink_info.get("knot", ""))],
			"path": String(ink_info.get("file", "ink")),
			"steps": ink_lines,
			"active_idx": int(ink_info.get("active_idx", -1))
		})

	for i in range(_code_targets.size()):
		_code_target_opt.add_item(String(_code_targets[i].get("label", "")), i)

	if not _code_targets.is_empty():
		_code_target_opt.select(0)
		_render_code_target(_code_targets[0])
	else:
		_code_view.text = "// 表示可能なシナリオコードがありません。"


func _on_code_target_selected(idx: int) -> void:
	if idx < 0 or idx >= _code_targets.size():
		return
	_render_code_target(_code_targets[idx])


func _render_code_target(target: Dictionary) -> void:
	if _code_view == null:
		return
	var path := String(target.get("path", ""))
	var steps: Array = target.get("steps", [])
	var active_idx := int(target.get("active_idx", -1))

	var lines: Array[String] = []
	lines.append("// %s (%d steps)" % [path, steps.size()])

	var active_line := 0
	for i in range(steps.size()):
		var marker := ">>>" if i == active_idx else "   "
		if i == active_idx:
			active_line = lines.size()
		var formatted := _format_scenario_step(steps[i], 0)
		var sub_lines := formatted.split("\n")
		lines.append("%s[%02d] %s" % [marker, i, sub_lines[0]])
		for s_i in range(1, sub_lines.size()):
			lines.append("      " + sub_lines[s_i])

	_code_view.text = "\n".join(lines)
	if active_line > 0:
		_code_view.set_caret_line(active_line)
		_code_view.center_viewport_to_caret()


func _format_scenario_step(step: Variant, indent: int) -> String:
	var pad := "  ".repeat(indent)
	if step is String:
		return pad + JSON.stringify(step)
	if not (step is Dictionary):
		return pad + JSON.stringify(step)
	var d := step as Dictionary
	if d.has("if"):
		var out: Array[String] = []
		out.append("%sif (%s) {" % [pad, SceneGraph.cond_to_text(d.get("if"))])
		var then_arr: Variant = d.get("then", [])
		if then_arr is Array:
			for sub in then_arr:
				out.append(_format_scenario_step(sub, indent + 1))
		var else_arr: Variant = d.get("else", [])
		if else_arr is Array and not (else_arr as Array).is_empty():
			out.append("%s} else {" % pad)
			for sub in else_arr:
				out.append(_format_scenario_step(sub, indent + 1))
		out.append("%s}" % pad)
		return "\n".join(out)
	return pad + JSON.stringify(d)


# =============================================================================
# Data Modification Helpers & Commands (Never touches scenario files!)
# =============================================================================

func _apply_var_change(var_name: String, new_val: Variant) -> void:
	if core == null or core.state == null:
		return
	var old_val: Variant = core.state.get_var(var_name)
	core.state.set_var(var_name, new_val)
	_dirty_data = true
	_append_log("[color=#34d399][変更][/color] [b]%s[/b]: %s → [b]%s[/b]" % [
		var_name,
		JSON.stringify(old_val),
		JSON.stringify(core.state.get_var(var_name))
	])
	refresh_all()


func _apply_item_change(item_id: String, delta: int) -> void:
	if core == null or core.state == null:
		return
	var before := core.state.item_count(item_id)
	if delta >= 0:
		core.state.apply_event({"type": "item.add", "args": {"id": item_id, "count": delta}})
	else:
		core.state.apply_event({"type": "item.remove", "args": {"id": item_id, "count": -delta}})
	var after := core.state.item_count(item_id)
	_dirty_data = true
	_append_log("[color=#34d399][所持品][/color] [b]%s[/b]: %d → [b]%d[/b]" % [item_id, before, after])
	refresh_all()


func _apply_scene_change(scene_id: String) -> void:
	if core == null or core.state == null:
		return
	var old_scene := core.state.scene
	core.state.scene = scene_id
	core.state.visited[scene_id] = true
	_dirty_data = true
	_dirty_scene = true
	_append_log("[color=#38bdf8][シーン][/color] %s → [b]%s[/b]" % [old_scene, scene_id])
	refresh_all()


func _on_scene_jump_pressed() -> void:
	if _scene_opt == null or _scene_opt.selected < 0:
		return
	var sid := String(_scene_opt.get_item_metadata(_scene_opt.selected))
	if sid != "":
		_apply_scene_change(sid)


func _on_command_submitted(raw_line: String) -> void:
	var line := raw_line.strip_edges()
	if _cmd_input != null:
		_cmd_input.text = ""
	if line == "":
		return
	if _cmd_history.is_empty() or _cmd_history.back() != line:
		_cmd_history.append(line)
	_cmd_history_idx = -1

	_switch_page(0)
	_append_log("[color=#94a3b8]> %s[/color]" % line)
	execute_command(line)


func execute_command(line: String) -> void:
	if core == null or core.state == null:
		_append_log("[color=#f87171]エラー: AdvCore 未接続[/color]")
		return

	var tokens := _tokenize_command(line)
	if tokens.is_empty():
		return

	# Support shorthand `var_name = value`
	if tokens.size() >= 3 and tokens[1] == "=":
		var vname := tokens[0]
		var rhs := line.substr(line.find("=") + 1).strip_edges()
		_apply_var_change(vname, _coerce_to_declared_type(vname, rhs))
		return

	var cmd := tokens[0].to_lower()
	match cmd:
		"help", "?":
			_print_help()
		"vars", "state", "data":
			_print_current_data()
		"get", "print":
			if tokens.size() < 2:
				_append_log("使い方: get <変数名または式>")
				return
			var expr_str := line.substr(tokens[0].length()).strip_edges()
			var val: Variant = core.state.get_var(expr_str) if core.state.has_var(expr_str) else AdvCondition.eval_text(expr_str, core.state)
			_append_log("%s = [b]%s[/b]" % [expr_str, JSON.stringify(val)])
		"set":
			if tokens.size() < 3:
				_append_log("使い方: set <変数名> <値>")
				return
			var var_name := tokens[1]
			var val_str := line.substr(line.find(var_name) + var_name.length()).strip_edges()
			if val_str.begins_with("="):
				val_str = val_str.substr(1).strip_edges()
			_apply_var_change(var_name, _coerce_to_declared_type(var_name, val_str))
		"toggle":
			if tokens.size() < 2:
				_append_log("使い方: toggle <フラグ名>")
				return
			var f_name := tokens[1]
			var cur := bool(core.state.get_var(f_name))
			_apply_var_change(f_name, not cur)
		"reset":
			if tokens.size() < 2:
				_append_log("使い方: reset <変数名 | all>")
				return
			var target := tokens[1]
			if target == "all":
				for k in core.state.declared.keys():
					var decl: Dictionary = core.state.declared[k]
					core.state.set_var(String(k), decl.get("default"))
				_dirty_data = true
				_append_log("[color=#34d399]全変数を初期値にリセットしました。[/color]")
				refresh_all()
			elif core.state.declared.has(target):
				var decl: Dictionary = core.state.declared[target]
				_apply_var_change(target, decl.get("default"))
			else:
				_append_log("[color=#f87171]変数 '%s' に初期値がありません。[/color]" % target)
		"items", "inventory", "inv":
			_print_items()
		"give", "add_item":
			if tokens.size() < 2:
				_append_log("使い方: give <item_id> [個数]")
				return
			var iid := tokens[1]
			var cnt := int(tokens[2]) if tokens.size() >= 3 and tokens[2].is_valid_int() else 1
			_apply_item_change(iid, maxi(1, cnt))
		"take", "remove_item":
			if tokens.size() < 2:
				_append_log("使い方: take <item_id> [個数]")
				return
			var iid := tokens[1]
			var cnt := int(tokens[2]) if tokens.size() >= 3 and tokens[2].is_valid_int() else 1
			_apply_item_change(iid, -maxi(1, cnt))
		"scene", "goto":
			if tokens.size() < 2:
				_append_log("現在シーン: [b]%s[/b] (scene <id>)" % core.state.scene)
				return
			_apply_scene_change(tokens[1])
		"visit":
			var sid := tokens[1] if tokens.size() >= 2 else core.state.scene
			core.state.visited[sid] = true
			_dirty_data = true
			_append_log("[color=#34d399]訪問済みに設定: %s[/color]" % sid)
			refresh_all()
		"unvisit":
			var sid := tokens[1] if tokens.size() >= 2 else core.state.scene
			core.state.visited.erase(sid)
			_dirty_data = true
			_append_log("[color=#34d399]未訪問に設定: %s[/color]" % sid)
			refresh_all()
		"code", "list":
			_print_current_code_to_log()
		"graph":
			open_scene_graph_requested.emit()
		"clear", "cls":
			if _log_view != null:
				_log_view.clear()
		"resume", "close", "exit", "quit":
			close_and_resume()
		_:
			_append_log("[color=#f87171]不明: '%s' (help参照)[/color]" % cmd)


func _print_help() -> void:
	var help_lines := [
		"[color=#38bdf8]--- コマンド一覧 ---[/color]",
		" [b]vars[/b]/[b]state[/b] : 現データ表示 | [b]code[/b] : 前後コード表示",
		" [b]get <名|式>[/b] : 値参照 | [b]set <名> <値>[/b] : 値変更",
		" [b]toggle <名>[/b] : 真偽反転 | [b]reset <名|all>[/b] : 初期化",
		" [b]give/take <id> [数][/b] : 所持品増減 | [b]scene <id>[/b] : 移動",
		" [b]resume[/b] / [b]ESC[/b] : コンソールを閉じて変更データで再開"
	]
	_append_log("\n".join(help_lines))


func _print_current_data() -> void:
	if core == null or core.state == null:
		return
	var st := core.state
	_append_log("[color=#38bdf8]--- 現在のデータ (scene=%s) ---[/color]" % st.scene)
	var keys := st.vars.keys()
	keys.sort()
	for k in keys:
		_append_log("  %s = [b]%s[/b]" % [String(k), JSON.stringify(st.vars[k])])
	_print_items()


func _print_items() -> void:
	if core == null or core.state == null:
		return
	var st := core.state
	if st.items.is_empty():
		_append_log("所持品: (なし)")
	else:
		_append_log("所持品: %s" % JSON.stringify(st.items))


func _print_current_code_to_log() -> void:
	if _code_view == null:
		return
	_append_log("[color=#93c5fd]--- 前後のシナリオコード ---[/color]\n" + _code_view.text)


func _append_log(bbcode_text: String) -> void:
	if _log_view == null:
		return
	_log_view.append_text(bbcode_text + "\n")


func _tokenize_command(line: String) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	var in_quote := false
	var quote_char := ""
	for i in range(line.length()):
		var ch := line[i]
		if in_quote:
			if ch == quote_char:
				in_quote = false
			else:
				cur += ch
		else:
			if ch == "\"" or ch == "'":
				in_quote = true
				quote_char = ch
			elif ch == " " or ch == "\t":
				if cur != "":
					out.append(cur)
					cur = ""
			else:
				cur += ch
	if cur != "":
		out.append(cur)
	return out


func _infer_type_name(val: Variant) -> String:
	match typeof(val):
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		_:
			return "var"


func _parse_literal_or_expr(raw: String) -> Variant:
	var s := raw.strip_edges()
	if s.begins_with("=") and s.length() > 1 and core != null and core.state != null:
		return AdvCondition.eval_text(s.substr(1).strip_edges(), core.state)
	var low := s.to_lower()
	if low == "true":
		return true
	if low == "false":
		return false
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	if (s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'")):
		return s.substr(1, s.length() - 2)
	return s


func _coerce_to_declared_type(var_name: String, raw_str: String) -> Variant:
	var parsed: Variant = _parse_literal_or_expr(raw_str)
	if core == null or core.state == null:
		return parsed
	var decl: Dictionary = core.state.declared.get(var_name, {})
	var t := String(decl.get("type", ""))
	match t:
		"bool":
			if parsed is bool:
				return parsed
			var low := String(parsed).to_lower().strip_edges()
			return low == "true" or low == "1" or low == "on" or low == "yes"
		"int":
			return int(parsed)
		"float":
			return float(parsed)
		"string":
			return String(parsed)
	return parsed
