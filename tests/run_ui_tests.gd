extends SceneTree
## 画面つきの動作確認。段階1のサンプルを読み込み、コマンド入力とコマンド選択で遊んでみる。
##   godot --path . --script res://tests/run_ui_tests.gd -- [スクリーンショットの保存先フォルダ]
## ヘッドレスでも動く（その場合スクリーンショットは保存しない）。

var _failed := 0
var _shot_dir := ""
var player: AdvPlayer


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_shot_dir = args[0]
	_main.call_deferred()


func check(cond: bool, label: String) -> void:
	if not cond:
		_failed += 1
		printerr("FAIL: " + label)
	else:
		print("ok: " + label)


func _main() -> void:
	var scene: PackedScene = load("res://tests/stage1/stage1_main.tscn")
	player = scene.instantiate()
	player.auto_click = true
	root.add_child(player)
	await _settle()
	await _shot("01_start")
	check(player.core.state.scene == "hallway", "start in hallway")

	# コマンド選択：「しらべる」→「うえきばち」
	var sel := player.screen.command_select
	check(sel != null, "command select exists")
	var verbs := _buttons(sel)
	check(verbs.has("しらべる"), "verb list has しらべる: %s" % str(verbs))
	_press(sel, "しらべる")
	await _settle()
	var targets := _buttons(sel)
	check(targets.has("うえきばち") and targets.has("もどる"), "targets: %s" % str(targets))
	await _shot("02_select_targets")
	_press(sel, "うえきばち")
	await _settle()
	check(player.core.state.has_item("key"), "got key via command select")

	# コマンド入力
	player.submit_text("かぎを ドアに つかう")
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("カチリ"), "use key: %s" % player.screen.message_label.get_parsed_text())
	player.submit_text("ドアを あける")
	await _settle()
	check(player.core.state.scene == "room", "moved to room")
	player.submit_text("あゆみと はなす")
	await _settle()
	await _shot("03_room_talk")
	check(player.screen.message_label.get_parsed_text().contains("@マーク"), "dialogue last line")

	# 切り替え演出と画面効果（すべての種類を一通り動かす）
	for t in ["fade", "wipe", "blinds", "line_draw", "interlace", "plane_draw", "mosaic", "dissolve", "blocks", "iris", "fade_color"]:
		player._run([{"type": "image.show", "args": {"layer": "bg", "id": "room", "transition": {"type": t, "duration": 0.1, "speed": 4000}}}])
		await _settle()
	check(player.screen.layers["bg"].get_child_count() == 1, "one image after transitions")
	for e in ["flash", "shake", "invert", "raster", "scroll", "zoom"]:
		player._run([{"type": "effect.play", "args": {"name": e, "duration": 0.1}}])
		await _settle()
	player._run([{"type": "effect.play", "args": {"name": "tint", "color": "#c08040", "amount": 0.8, "duration": 0.1}}])
	await _settle()
	await _shot("04_tint")
	player._run([{"type": "effect.play", "args": {"name": "tint", "amount": 0.0, "duration": 0.05}},
		{"type": "image.show", "args": {"layer": "bg", "id": "room"}}])
	await _settle()
	check(player.screen.layers["bg"].position == Vector2.ZERO, "layer reset after new image")

	# レイアウトの切り替え
	player._run([{"type": "layout.set", "args": {"layout": "fullscreen_cg"}}])
	await _settle()
	check(player.screen.picture.size == Vector2(640, 400), "named layout")
	await _shot("05_fullscreen_cg")
	player._run([{"type": "layout.set", "args": {"layout": ""}}])
	await _settle()

	# 88 のテンプレートに切り替える（素材は機種別の差し替えに変わる）
	await player.switch_template("pc88_classic")
	await _settle()
	check(player.template.preset["id"] == "88.640x200", "switched to 88")
	check(player.core.assets.resolve("image", "room").contains("presets/88"), "by_preset image for 88")
	check(player.display.display_scale().y == player.display.display_scale().x * 2.0, "88 line doubling")
	player.submit_text("あゆみと はなす")
	await _settle()
	await _shot("06_pc88")
	# 自作フィルター（*.effect.json）を足す
	player.display.set_filters(AdvVisuals.resolve_filters(player.template, {"mode": "append", "list": [{"type": "sepia", "amount": 0.9}]}))
	await _settle()
	check(player.display._passes.size() == 2, "custom filter pass added")
	await _shot("07_pc88_sepia")
	player.set_filters_enabled(false)
	await _shot("08_pc88_nofilter")

	# キー入力が SubViewport の中の入力欄に届くか
	player.screen.command_line.grab_focus()
	for ch in "あゆみ みる":
		var k := InputEventKey.new()
		k.pressed = true
		k.unicode = ch.unicode_at(0)
		Input.parse_input_event(k)
		await process_frame
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	Input.parse_input_event(enter)
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("ながい かみ"), "typed command reaches the parser: %s" % player.screen.message_label.get_parsed_text())

	print("ui failed: %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _settle() -> void:
	for i in 5:
		await process_frame
	while player.busy:
		await process_frame


func _shot(name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_shot_dir, name])


func _buttons(sel: AdvCommandSelect) -> Array:
	var r := []
	for b in sel.get_child(0).get_children():
		if b is Button and not b.is_queued_for_deletion():
			r.append(b.text)
	return r


func _press(sel: AdvCommandSelect, label: String) -> void:
	for b in sel.get_child(0).get_children():
		if b is Button and b.text == label and not b.is_queued_for_deletion():
			b.pressed.emit()
			return
	check(false, "button not found: %s" % label)
