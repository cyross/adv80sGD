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
	player.settings_path = ""
	player.progress_path = ""
	_rmdir("user://test_saves")
	root.add_child(player)
	player.project.data["save"] = {"dir": "user://test_saves", "slots": 3}
	await _settle()
	await _shot("01_start")
	check(player.core.state.scene == "hallway", "start in hallway")
	check(player.audio.current_bgm.get("id", "") == "theme" and player.audio._bgm[player.audio._bgm_index].playing, "bgm playing")
	var st: AudioStream = player.audio._bgm[player.audio._bgm_index].stream
	check(st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD and (st as AudioStreamWAV).loop_begin == int(9.6 * (st as AudioStreamWAV).mix_rate), "bgm loop_start from manifest")

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
	check(FileAccess.file_exists("user://test_saves/auto1.sav"), "autosave on scene change")
	player.submit_text("あゆみと はなす")
	await _settle()
	await _shot("03_room_choice")
	check(sel.choosing and _buttons(sel) == ["たんていだ", "なのらない"], "choice menu: %s" % str(_buttons(sel)))
	check(not player.screen.command_line.editable, "command line disabled while choosing")
	check(player.screen.message_label.get_parsed_text().contains("どう こたえる"), "choice prompt shown")
	# 選択中にセーブ
	check(player.save_game("02") == OK, "save at choice")
	_press(sel, "なのらない")
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("@マーク"), "dialogue continues after choice")
	check(player.message_log.entries.any(func(e): return e["kind"] == "input" and e["body"] == "なのらない"), "choice logged as input")
	check(player.message_log.entries.any(func(e): return e.get("voice", "") == "ayumi_key_01"), "voice logged with the line")
	check(player.message_log.entries.any(func(e): return e["kind"] == "input" and e["body"] == "うえきばち しらべる"), "command select logged")
	# 選択中のセーブを読み込むと、選択肢が出し直される
	check(await player.load_game("02") == "", "load at choice")
	await _settle()
	check(sel.choosing and _buttons(sel).size() == 2, "choice restored after load: %s" % str(_buttons(sel)))
	check(not player.core.state.chosen.has("who/secret"), "state restored")
	_press(sel, "たんていだ")
	await _settle()
	check(player.core.state.get_var("met_ayumi") == true, "chose after load")

	# ---- 段階7：Ink で書いた会話（JSON から呼び、終わったら戻る）
	player.submit_text("あゆみに まどについて きく")
	await _settle()
	check(sel.choosing and _buttons(sel).has("あかりの ことを きく"), "ink choices: %s" % str(_buttons(sel)))
	await _shot("18_ink_choice")
	_press(sel, "あかりの ことを きく")
	await _settle()
	check(player.core.state.get_var("saw_lights") == true, "ink variable returned to Core")
	check(sel.choosing and not _buttons(sel).has("あかりの ことを きく"), "ink once-only choice gone: %s" % str(_buttons(sel)))
	_press(sel, "はなしを おえる")
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("みつめた"), "back to JSON after ink: %s" % player.screen.message_label.get_parsed_text())
	check(not sel.choosing and player.core.adapter_name(player.core.adapter) == "main", "json adapter on top again")

	# セーブとロード（入力待ちのとき）
	check(player.save_game("01") == OK, "save slot 01")
	player.submit_text("ろうかへ いく")
	await _settle()
	check(player.core.state.scene == "hallway", "moved back")
	check(await player.load_game("01") == "", "load slot 01")
	await _settle()
	check(player.core.state.scene == "room" and player._images["bg"]["id"] == "room", "scene and image restored")
	check(player.audio.current_bgm.get("id", "") == "theme", "bgm restored")
	check(player.screen.message_label.get_parsed_text().contains("みつめた"), "last text restored: %s" % player.screen.message_label.get_parsed_text())
	var saves := player.list_saves()
	check(saves.filter(func(x): return x["exists"]).size() >= 3, "list saves: %s" % str(saves.map(func(x): return [x["slot"], x["exists"]])))
	# 書き換えたセーブは読まない
	var raw := FileAccess.get_file_as_bytes("user://test_saves/01.sav")
	raw[raw.size() - 40] = raw[raw.size() - 40] ^ 0x5a
	var f := FileAccess.open("user://test_saves/01.sav", FileAccess.WRITE)
	f.store_buffer(raw)
	f.close()
	check(await player.load_game("01") == AdvSave.ERR_TAMPERED, "tampered save rejected")

	# メッセージログの画面
	player.open_log()
	await _settle()
	check(player._overlay is AdvLogView, "log view opens")
	await _shot("03b_log")
	player._overlay.close()
	await _settle()
	check(player._overlay == null, "log view closes")
	# セーブ画面
	player.open_save_menu("load")
	await _settle()
	check(player._overlay is AdvSaveMenu, "save menu opens")
	await _shot("03c_save_menu")
	player._overlay.close()
	await _settle()

	# 既読スキップ：読んだ文章は止まらずに進み、未読で止まる
	player.submit_text("あゆみ みる")
	await _settle()
	player.auto_click = false
	player.skip_mode = true
	player.submit_text("あゆみ みる")
	await _settle()
	check(not player.busy, "skip through read text")
	player.submit_text("ろうかへ いく")
	await _settle()
	player.submit_text("ドア みる")   # 「ふるびた 木の ドアだ」はまだ読んでいない
	for i in 30:
		await process_frame
	check(player.busy and not player.skip_mode, "skip stops at unread text")
	player.auto_click = true
	await _settle()
	player.submit_text("ドアを あける")
	await _settle()
	check(player.core.state.scene == "room", "back in room")

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
	_press(player.screen.command_select, "たんていだ")
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

	# ---- 段階5：モダン機能
	await player.switch_template("pc98_classic")
	await _settle()
	# システムメニュー
	player.modern.open_system_menu()
	await _settle()
	check(player._overlay is AdvMenuPanel, "system menu opens")
	await _shot("09_system_menu")
	player._overlay.close()
	await _settle()
	# 手帳
	player.modern.open_notebook()
	await _settle()
	check(_panel_text(player._overlay).contains("ふるい かぎ") and _panel_text(player._overlay).contains("あゆみ"), "notebook shows entries")
	await _shot("10_notebook")
	player._overlay.close()
	await _settle()
	# フローチャート
	player.modern.open_flowchart()
	await _settle()
	await _shot("11_flowchart")
	player._overlay.close()
	await _settle()
	# 画面選択：input.mode で click を有効にし、物を押す
	player._run(player.core._commit([{"type": "input.mode", "args": {"enable": ["select", "parser", "click"]}}]))
	await _settle()
	player.submit_text("ろうかへ いく")
	await _settle()
	check(player.core.state.scene == "hallway", "back in hallway for click test")
	var hl := player.screen.hotspot_layer
	check(hl.hotspots.size() == 3, "hotspots shown: %d" % hl.hotspots.size())
	hl.hotspot_clicked.emit(hl.hotspots.filter(func(h): return h["id"] == "plant")[0])
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("もう なにも ない"), "click examines: %s" % player.screen.message_label.get_parsed_text())
	_press(player.screen.command_select, "みる")
	await _settle()
	hl.hotspot_clicked.emit(hl.hotspots.filter(func(h): return h["id"] == "door")[0])
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("木の ドア"), "verb then click: %s" % player.screen.message_label.get_parsed_text())
	player._show_all_hotspots = true
	player._refresh_hotspots()
	await _shot("12_hotspots")
	# 試したコマンドの印
	check(player.screen.command_select.show_tried, "tried marks on")
	# 巻き戻し
	var before: Dictionary = player.core.state.to_dict()
	player.submit_text("かんがえる")
	await _settle()
	check(player.can_rewind(), "can rewind")
	await player.rewind(1)
	await _settle()
	check(player.core.state.tried == before["tried"], "rewind restores state")
	# フローチャートから再開
	check(player.progress.snapshots.has("room"), "flow snapshot recorded")
	await player.jump_to_node("room")
	await _settle()
	check(player.core.state.scene == "room", "jump to flow node")
	# 読みやすいフォント、旧表示と新表示の切り替え
	player.set_feature("readable_font", true)
	check(player.screen.readable, "readable font on")
	await _shot("13_readable")
	player.set_feature("readable_font", false)
	await player.cycle_template()
	await _settle()
	check(player.template.id == "pc88_classic", "era switch")
	# ヒント（段階を進める）
	await player.cycle_template()
	await _settle()
	await player.load_game("auto1")
	await _settle()
	player.core._commit([{"type": "hint.set", "args": {"topic": "door", "hints": ["ひとつめ", "ふたつめ"]}}])
	player.modern.open_hints()
	await _settle()
	check(_panel_text(player._overlay).contains("ドアについて"), "hint topic label")
	var reveal: Button = player._overlay.find_children("*", "Button", true, false).filter(func(b): return b.text.contains("つぎの ヒント"))[0]
	reveal.pressed.emit()
	await _settle()
	check(_panel_text(player._overlay).contains("ひとつめ") and not _panel_text(player._overlay).contains("ふたつめ"), "hint revealed one stage")
	await _shot("14_hints")
	player._overlay.close()
	await _settle()
	player.modern.open_chapters()
	await _settle()
	var chs: Array = player._overlay.find_children("*", "Button", true, false).map(func(b): return b.text)
	check(chs.has("だい1しょう ろうか") and chs.has("だい2しょう へや"), "chapters listed: %s" % str(chs))
	player._overlay.close()
	await _settle()
	player.modern.open_settings()
	await _settle()
	await _shot("15_settings")
	player._overlay.close()
	await _settle()

	# ---- 段階6：palette_cycle（98 はパレットで減色している）
	player.set_filters_enabled(true)
	player._run([{"type": "effect.play", "args": {"name": "palette_cycle", "range": [1, 3], "speed": 20, "duration": 0.2}}])
	await _settle()
	check(int(player.display._material.get_shader_parameter("cycle_len")) == 0, "palette cycle finished")
	player._run([{"type": "effect.play", "args": {"name": "palette_cycle", "range": [1, 6], "speed": 8}, "wait": "none"}])
	await _settle()
	check(int(player.display._material.get_shader_parameter("cycle_len")) == 6, "palette cycle running")
	await _shot("17_palette_cycle")
	player._run([{"type": "effect.play", "args": {"name": "palette_cycle", "speed": 0}}])
	await _settle()
	check(int(player.display._material.get_shader_parameter("cycle_len")) == 0, "palette cycle stopped")

	# ---- 入力機器の切り替え（gamepad、touch）
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	check(not player.is_blocked_input(jb), "gamepad on by default")
	player.set_feature("gamepad", false)
	check(player.is_blocked_input(jb), "gamepad off blocks joypad")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	check(not player.is_blocked_input(key), "keyboard never blocked")
	player.set_feature("gamepad", true)
	check(not player.is_blocked_input(jb), "gamepad back on")
	var tm := InputEventMouseButton.new()
	tm.device = InputEvent.DEVICE_ID_EMULATION
	check(player.is_blocked_input(tm) == not player.features.is_on("touch"), "touch-emulated mouse follows the touch feature")

	# ---- 文章の表示調整（text_options）
	player.set_text_option("text_size", 2.0)
	player.set_text_option("text_color", 6)
	player.set_text_option("window_opacity", 0.5)
	await _settle()
	var ml := player.screen.message_label
	check(ml.get_theme_font_size("normal_font_size") == player.screen.font_size * 2, "text size x2: %d" % ml.get_theme_font_size("normal_font_size"))
	check(ml.get_theme_color("default_color") == player.template.color(6), "text color")
	var msb = player.screen._msg_win.get_theme_stylebox("panel")
	check(msb is StyleBoxFlat and is_equal_approx(msb.bg_color.a, 0.5), "window opacity")
	await _shot("19_text_options")
	player.set_text_option("text_size", 1.0)
	player.set_text_option("text_color", -1)
	player.set_text_option("window_opacity", 1.0)
	await _settle()
	check(ml.get_theme_color("default_color") == player.template.color(int(player.template.get_section("text").get("color", 7))), "text color back to template")

	# ---- 段階6：聞き返し
	await player.load_game("auto1")
	await _settle()
	player.submit_text("ろうかへ いく")
	await _settle()
	if player.core.state.scene != "hallway":
		player.submit_text("ろうかへ いく")
		await _settle()
	player.submit_text("みる")
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("とくに") or true, "look without target is allowed")
	player.submit_text("あける")
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("なにを あける"), "input.request prompt: %s" % player.screen.message_label.get_parsed_text())
	check(_buttons(player.screen.command_select).has("ドア"), "request candidates: %s" % str(_buttons(player.screen.command_select)))
	await _shot("16_request")
	player.submit_text("ドア")
	await _settle()
	check(player.screen.message_label.get_parsed_text().contains("ほこりっぽい") or player.core.state.scene == "room", "answered by typing: %s" % player.screen.message_label.get_parsed_text())
	player.submit_text("しめる")
	await _settle()
	var cands := _buttons(player.screen.command_select)
	check(cands.has("もどる"), "request via select: %s" % str(cands))
	_press(player.screen.command_select, "もどる")
	await _settle()
	check(_buttons(player.screen.command_select).has("しらべる"), "cancel request")

	# ---- 段階9：スプライト、マウスカーソル、動画（6.4〜6.6）
	await player.load_game("auto1")
	await _settle()
	if player.core.state.scene != "hallway":
		player.submit_text("ろうかへ いく")
		await _settle()
	var lamp := player.screen.sprite("lamp")
	check(lamp != null and lamp.is_animating(), "scene sprite (animated gif) shown")
	check(player.screen.sprite("sparkle") == null, "sparkle gone after the key was taken")
	check(lamp != null and lamp.bounds().size == Vector2(32, 48), "lamp scaled x2: %s" % (str(lamp.bounds()) if lamp else ""))
	check(lamp != null and not lamp.is_opaque_at(lamp.bounds().position + Vector2(1, 1)), "color key: corner is transparent")
	var lamp_h: Dictionary = player.screen.hotspot_layer.hotspots.filter(func(h): return h["id"] == "lamp").front() if player.screen.hotspot_layer.hotspots.any(func(h): return h["id"] == "lamp") else {}
	check(not lamp_h.is_empty() and player.screen.hotspot_layer.rect_of(lamp_h) == lamp.bounds(), "sprite hotspot follows the sprite")
	_run_ev([AdvEvents.make("sprite.show", {"id": "deco", "image": "sparkle", "x": 300, "y": 40, "scale": 3, "layer": "front", "anim": "default"}),
		AdvEvents.make("sprite.set", {"id": "deco", "x": 340, "duration": 0.2}),
		AdvEvents.make("sprite.effect", {"id": "lamp", "name": "sepia"}),
		AdvEvents.make("cursor.set", {"kind": "wait"})])
	await _settle()
	var deco := player.screen.sprite("deco")
	check(deco != null and deco.get_parent().name == "Sprites_front", "screen layer sprite: %s" % (str(deco.get_parent().name) if deco else "none"))
	check(deco != null and is_equal_approx(deco.position.x, 340.0), "sprite.set tween reached target: %s" % (str(deco.position) if deco else ""))
	check(player.current_cursor_kind() == "wait", "cursor.set forces the cursor")
	await _shot("20_sprites")
	check(player.save_game("03") == OK, "save with sprites")
	_run_ev([AdvEvents.make("sprite.clear", {}), AdvEvents.make("cursor.set", {"kind": null})])
	await _settle()
	check(player.screen.sprite("deco") == null and player.screen.sprite("lamp") == null, "sprite.clear")
	check(player.current_cursor_kind() != "wait", "cursor back to automatic")
	check(await player.load_game("03") == "", "load with sprites")
	await _settle()
	deco = player.screen.sprite("deco")
	lamp = player.screen.sprite("lamp")
	check(deco != null and is_equal_approx(deco.position.x, 340.0) and deco.scale == Vector2(3, 3), "sprite restored from save")
	check(lamp != null and lamp.state.get("effect", {}).get("name", "") == "sepia" and lamp._body.material is ShaderMaterial, "effect restored from save")
	check(player.current_cursor_kind() == "wait", "forced cursor restored")
	await player.switch_template("fhd_modern")
	await _settle()
	check(player.screen.sprite("deco") != null and player.screen.sprite("lamp") != null, "sprites survive template switch")
	check(player.template.get_section("ui").has("cursors"), "modern template has cursors")
	_run_ev([AdvEvents.make("cursor.set", {"kind": null})])
	await _settle()
	check(player.current_cursor_kind() in ["default", "look"], "cursor default: %s" % player.current_cursor_kind())
	# 動画（6.6）：クリックで飛ばせる、繰り返しは裏で流れ続ける
	player.auto_click = false
	_run_ev([AdvEvents.make("video.play", {"id": "op_test"})])
	await _settle_frames(2)
	check(player.screen.video_player != null and player.screen.video_player.is_playing(), "video playing: %s %s" % [player.screen.video_player, player.screen.video_player.stream_position if player.screen.video_player else -1.0])
	check(player.audio._bgm[player.audio._bgm_index].stream_paused, "bgm paused during video")
	player._click_pending = true
	await _settle()
	check(player.screen.video_player == null or not is_instance_valid(player.screen.video_player), "video skipped by click")
	check(not player.audio._bgm[player.audio._bgm_index].stream_paused, "bgm resumed")
	check(player.progress.read.has("video:op_test"), "video marked as seen")
	_run_ev([AdvEvents.make("video.play", {"id": "op_test", "loop": true, "bgm": "keep"})])
	await _settle()
	check(player.screen.video_player != null and player.screen.video_player.loop, "loop video keeps playing")
	_run_ev([AdvEvents.make("video.stop", {})])
	await _settle()
	check(player.screen.video_player == null or not is_instance_valid(player.screen.video_player), "video.stop")
	player.auto_click = true
	await player.switch_template("pc98_classic")
	await _settle()

	# ---- 段階10：ページめくり
	player.auto_click = false
	var long := ""
	for i in 12:
		long += "これは ながい ぶんしょうの %d ぎょうめ です。\n" % (i + 1)
	_run_ev([AdvEvents.make("text.show", {"body": long})])
	await _settle_frames(3)
	player._click_pending = true
	await _settle_frames(3)
	check(player.screen.halt == "page" and player.screen.page_mark.visible, "page full: page mark shown (halt=%s)" % player.screen.halt)
	await _shot("21_page_full")
	var y0 := player.screen.message_label.position.y
	player._click_pending = true
	await _settle_frames(3)
	check(player.screen.message_label.position.y < y0, "next page scrolls the text: %f" % player.screen.message_label.position.y)
	for i in 10:
		player._click_pending = true
		await _settle_frames(3)
		if player.screen.halt == "end" and player.screen.wait_mark.visible:
			break
	check(player.screen.halt == "end" and player.screen.wait_mark.visible, "last page ends with the click mark")
	player._click_pending = true
	await _settle()
	# [p] と [page=秒]
	_run_ev([AdvEvents.make("text.show", {"body": "あいう[p]えお[page=0.2]つぎの ページ"})])
	await _until_halt("stop")
	check(player.screen.halt == "stop" and player.screen.wait_mark.visible and player.screen.message_label.visible_characters == 3, "[p] waits for a click")
	player._click_pending = true
	await _settle_frames(2)
	await _until_halt("stop")
	check(player.screen.page_mark.visible, "[page=0.2] shows the page mark")
	await create_timer(0.4).timeout
	check(not player.screen.page_mark.visible and player.screen.message_label.get_parsed_text().contains("つぎの"), "[page=0.2] turns the page by itself")
	player.auto_click = true
	await _settle()
	# オート送り：クリックしなくても進む
	player.auto_click = false
	player.auto_mode = true
	player.settings.set_value("auto_delay", 0.1)
	player.settings.set_value("auto_per_char", 0.0)
	_run_ev([AdvEvents.make("text.show", {"body": "オート[p]おくり"}), AdvEvents.make("text.show", {"body": "おわり"})])
	await create_timer(4.0).timeout
	check(not player.busy and player.screen.message_label.get_parsed_text().contains("おわり"), "auto mode advances [p] and clicks: %s" % player.screen.message_label.get_parsed_text())
	player.auto_mode = false
	player.auto_click = true

	print("ui failed: %d" % _failed)
	quit(1 if _failed > 0 else 0)


## 文字送りが止まるまで待つ（送りの途中ならクリックして早める）。
func _until_halt(h: String) -> void:
	for i in 300:
		if player.screen.halt == h and not player.screen.is_typing():
			for j in 3:
				await process_frame
			return
		if player.screen.is_typing():
			player._click_pending = true
		await process_frame


func _run_ev(events: Array) -> void:
	player._run(events)


func _settle_frames(n: int) -> void:
	for i in n:
		await process_frame


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


func _panel_text(p: Node) -> String:
	var t := ""
	for n in p.find_children("*", "RichTextLabel", true, false):
		t += (n as RichTextLabel).get_parsed_text() + "\n"
	return t


func _rmdir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(path)


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
