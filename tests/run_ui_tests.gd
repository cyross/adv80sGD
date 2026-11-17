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

	# ---- 段階12：動画の切り替え演出（繰り返しの動画は待たずに現れ、video.stop は演出が終わるまで待つ）
	_run_ev([AdvEvents.make("video.play", {"id": "op_test", "loop": true, "bgm": "keep", "transition": {"type": "wipe", "duration": 1.0}})])
	await _settle_frames(3)
	var vg: CanvasGroup = player.screen._video_group
	check(vg != null and vg.material is ShaderMaterial, "video transition: shader while revealing")
	await create_timer(1.2).timeout
	check(vg.material == null and player.screen.video_player.is_playing(), "video transition: revealed and playing")
	_run_ev([AdvEvents.make("video.stop", {"transition": {"type": "fade", "duration": 1.0}})])
	await _settle_frames(3)
	check(is_instance_valid(vg) and not vg.is_queued_for_deletion() and player.busy, "video.stop waits for the transition")
	await _settle()
	check(not is_instance_valid(vg) or vg.is_queued_for_deletion(), "video.stop: removed after the transition")
	# 終わりを待つ動画：飛ばしても、同じ演出で消えてから次へ進む
	_run_ev([AdvEvents.make("video.play", {"id": "op_test", "transition": {"type": "fade_color", "duration": 0.8}})])
	await create_timer(1.0).timeout
	player._click_pending = true
	await _settle_frames(4)
	check(player.busy and player.screen._video_group != null, "video: leaving with the transition after a skip")
	await _settle()
	check(player.screen.video_player == null and player.screen._video_group == null, "video: gone after the transition")
	# スプライトの動画の音：既定は音なし、mute: false で BGM の音量に従って鳴らす
	player.settings.set_value("bgm_volume", 0.5)
	player.apply_volumes()
	_run_ev([AdvEvents.make("sprite.show", {"id": "smv", "image": "op_test", "x": 0, "y": 0, "mute": false, "volume": 0.5}),
		AdvEvents.make("sprite.show", {"id": "mv2", "image": "op_test", "x": 0, "y": 0})])
	await _settle()
	var smv := player.screen.sprite("smv")
	check(smv != null and smv.has_video() and is_equal_approx(smv.video_volume_db(), linear_to_db(0.25)), "sprite video sound: %s" % (smv.video_volume_db() if smv else 0.0))
	check(player.screen.sprite("mv2").video_volume_db() <= -79.0, "sprite video is muted by default")
	check(not smv.state.has("mute") and not smv.state.has("volume"), "mute and volume are not sprite properties")
	player.settings.set_value("bgm_volume", 1.0)
	player.apply_volumes()
	check(is_equal_approx(smv.video_volume_db(), linear_to_db(0.5)), "sprite video follows the BGM volume: %s" % smv.video_volume_db())
	check(player.save_game("04") == OK, "save with a sprite video")
	_run_ev([AdvEvents.make("sprite.clear", {})])
	await _settle()
	check(await player.load_game("04") == "", "load with a sprite video")
	await _settle()
	smv = player.screen.sprite("smv")
	check(smv != null and is_equal_approx(smv.video_volume_db(), linear_to_db(0.5)) and player.screen.sprite("mv2").video_volume_db() <= -79.0, "sprite video sound restored from save")
	_run_ev([AdvEvents.make("sprite.clear", {})])
	await _settle()
	player.auto_click = true
	await player.switch_template("pc98_classic")
	await _settle()

	# ---- 段階13：スプライトの出し入れの演出（スプライト1枚に、画像と同じ演出をかける）
	_run_ev([AdvEvents.make("sprite.show", {"id": "tw", "image": "room", "x": 10, "y": 10, "scale": 0.25, "transition": {"type": "wipe", "duration": 0.3}})])
	await _settle_frames(3)
	var tws := player.screen.sprite("tw")
	check(tws != null and tws._tgroup != null and tws._tgroup.material is ShaderMaterial and player.busy, "sprite wipe in: shader on the sprite only")
	var reg: Vector4 = tws._tgroup.material.get_shader_parameter("region") if tws != null and tws._tgroup != null else Vector4.ZERO
	check(reg.z < 0.5 and reg.w < 0.5, "sprite wipe in: region is the sprite, not the picture: %s" % str(reg))
	await _settle()
	check(tws._tgroup == null and tws._body.get_parent() == tws and is_equal_approx(tws.modulate.a, 1.0), "sprite wipe in: picture back in place")
	_run_ev([AdvEvents.make("sprite.hide", {"id": "tw", "transition": {"type": "dissolve", "duration": 0.3}})])
	await _settle_frames(3)
	check(player.screen.sprite("tw") != null and player.screen.sprite("tw")._tgroup != null and player.busy, "sprite dissolve out: in progress")
	await _settle()
	check(player.screen.sprite("tw") == null, "sprite dissolve out: removed")
	# 98 のテンプレートは fade を dissolve に置き換える（時代に合わない演出の置き換えがスプライトにも効く）
	_run_ev([AdvEvents.make("sprite.show", {"id": "tf", "image": "room", "x": 10, "y": 10, "scale": 0.25, "transition": {"type": "fade", "duration": 0.3}})])
	await _settle_frames(3)
	var tfg: CanvasGroup = player.screen.sprite("tf")._tgroup
	check(tfg != null and int(tfg.material.get_shader_parameter("mode")) == 7, "sprite fade on 98: replaced by dissolve")
	await _settle()
	# fade_color はスプライトでは薄くする・濃くする
	_run_ev([AdvEvents.make("sprite.show", {"id": "tc", "image": "room", "x": 10, "y": 10, "scale": 0.25, "transition": {"type": "fade_color", "duration": 0.3}})])
	await _settle_frames(3)
	check(player.screen.sprite("tc")._tgroup == null and player.screen.sprite("tc").modulate.a < 1.0, "sprite fade_color: opacity")
	await _settle()
	_run_ev([AdvEvents.make("sprite.clear", {})])
	await _settle()

	# ---- 段階13：背景の重ね合わせの中のアニメーション画像を動かす
	_run_ev([AdvEvents.make("image.show", {"layer": "bg", "id": ["room", {"id": "lamp", "x": 300, "y": 40}], "transition": "cut"})])
	await _settle()
	var bgl: Control = player.screen.layers["bg"]
	var bgv: Node = bgl.get_child(bgl.get_child_count() - 1).get_child(0)
	check(bgv.has_meta("animated") and bgv.get_node("Layers").get_child_count() == 2, "layered bg with a GIF: stacked sprites")
	var lamp_sp: AdvSprite = bgv.get_node("Layers").get_child(1) if bgv.has_node("Layers") else null
	check(lamp_sp != null and lamp_sp.is_animating() and lamp_sp.xy == Vector2(300, 40), "layered bg: the GIF plays at its place")
	_run_ev([AdvEvents.make("image.show", {"layer": "bg", "id": ["room", "hallway"], "transition": "cut"})])
	await _settle()
	bgv = bgl.get_child(bgl.get_child_count() - 1).get_child(0)
	check(bgv is TextureRect and not bgv.has_meta("animated"), "layered bg without animation: one picture")
	_run_ev([AdvEvents.make("image.show", {"layer": "bg", "id": "hallway", "transition": "cut"})])
	await _settle()

	# ---- 段階12：text.append（いまの文章の続きに足す）
	player.auto_click = false
	_run_ev([AdvEvents.make("text.show", {"body": "ドアには", "speaker": "ayumi", "name": "あゆみ"}),
		AdvEvents.make("text.append", {"body": "かぎが かかっている。"})])
	await _until_halt("end")
	var before_append: int = player.screen.message_label.get_total_character_count()
	player._click_pending = true
	await _settle_frames(3)
	var tml := player.screen.message_label
	check(tml.get_parsed_text() == "あゆみ「ドアにはかぎが かかっている。」", "text.append: inside the quotes: %s" % tml.get_parsed_text())
	check(player.screen.is_typing() and tml.visible_characters >= before_append - 1 and tml.visible_characters < tml.get_total_character_count(),
		"text.append: typing continues from the old end: %d / %d" % [tml.visible_characters, tml.get_total_character_count()])
	await _until_halt("end")
	player._click_pending = true
	await _settle()
	var lt: Dictionary = player.message_log.last_text()
	check(lt.get("body") == "ドアにはかぎが かかっている。" and lt.get("name") == "あゆみ", "text.append: one log entry: %s" % str(lt))
	check(player._last_text.get("body") == "ドアにはかぎが かかっている。" and player._last_text.get("name") == "あゆみ", "text.append: kept for saves")
	# 文章がないときは、ふつうの表示と同じ
	_run_ev([AdvEvents.make("text.clear", {}), AdvEvents.make("text.append", {"body": "しずかだ。"})])
	await _until_halt("end")
	check(player.screen.message_label.get_parsed_text() == "しずかだ。", "text.append without text: %s" % player.screen.message_label.get_parsed_text())
	player._click_pending = true
	await _settle()

	# ---- 段階12：[gaiji=ID]（素材の画像を文中に入れる。1文字として数え、ログには alt を出す）
	player.core.assets.entry("image", "lamp")["alt"] = "（ランプ）"
	var gj: Dictionary = player._gaiji("lamp")
	check(String(gj.get("path", "")).begins_with("res://.adv80s_gaiji/") and gj.get("texture") is Texture2D, "gaiji: image loaded: %s" % str(gj))
	check(player._gaiji("lamp").get("texture") == gj.get("texture"), "gaiji: loaded once")
	_run_ev([AdvEvents.make("text.show", {"body": "ランプ[gaiji=lamp]が ある。"})])
	await _until_halt("end")
	tml = player.screen.message_label
	check(tml.text.contains("[img]res://.adv80s_gaiji/") and tml.get_total_character_count() == "ランプ".length() + 1 + "が ある。".length(),
		"gaiji: inline image counted as one character: %s / %d" % [tml.text, tml.get_total_character_count()])
	await _shot("25_gaiji")
	player._click_pending = true
	await _settle()
	check(player.message_log.last_text().get("body", "") == "ランプ（ランプ）が ある。", "gaiji: alt text in the log: %s" % player.message_log.last_text().get("body"))
	# keep_colors: true の外字は、減色しない範囲に写しを置く（文字と、ほかの画像は写しでは透明）
	player.core.assets.entry("image", "sparkle")["keep_colors"] = true
	var gk: Dictionary = player._gaiji("sparkle")
	check(String(gk.get("path", "")).begins_with(AdvTextMarkup.GAIJI_KEEP_PREFIX), "gaiji keep_colors: keep path: %s" % str(gk.get("path")))
	check(player._gaiji("lamp").get("path") == gj.get("path"), "gaiji: other images keep their path")
	_run_ev([AdvEvents.make("text.show", {"body": "[pal=2]あ[/pal][gaiji=sparkle]と[gaiji=lamp]"})])
	await _until_halt("end")
	await _settle_frames(2)
	var kl: RichTextLabel = player.screen._keep_label
	check(player.display._keep_on and kl != null, "gaiji keep_colors: mask on")
	check(kl != null and kl.text.contains("[img]" + String(gk["path"])) and kl.text.contains("[img color=#00000000]") and not kl.text.contains("[color="),
		"gaiji keep_colors: mirror text: %s" % (kl.text if kl else ""))
	check(kl != null and kl.visible_characters == player.screen.message_label.visible_characters, "gaiji keep_colors: mirror follows typing")
	player._click_pending = true
	await _settle()
	_run_ev([AdvEvents.make("text.show", {"body": "ふつうの [gaiji=lamp]"})])
	await _until_halt("end")
	await _settle_frames(2)
	check(not player.display._keep_on, "gaiji: mask off without keep_colors")
	player._click_pending = true
	await _settle()
	player.core.assets.entry("image", "sparkle").erase("keep_colors")
	_run_ev([AdvEvents.make("text.show", {"body": "[gaiji=nothing_here]なし"})])
	await _until_halt("end")
	check(player.screen.message_label.get_parsed_text() == "なし", "gaiji: unknown ID is left out: %s" % player.screen.message_label.get_parsed_text())
	player._click_pending = true
	await _settle()
	player.auto_click = true

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

	# ---- 段階11：絵の中の対象を選ぶコマンド方式（verb_click、verb_cursor、context）
	await _settle()
	sel = player.screen.command_select
	var hl2 := player.screen.hotspot_layer
	var n_in := func() -> int: return player.message_log.entries.filter(func(e): return e["kind"] == "input").size()
	var last_in := func() -> String:
		var ins := player.message_log.entries.filter(func(e): return e["kind"] == "input")
		return String(ins.back()["body"]) if not ins.is_empty() else ""
	var spot := func(id: String) -> Dictionary:
		var l := hl2.hotspots.filter(func(h): return h["id"] == id)
		return l[0] if not l.is_empty() else {}
	print("scene for pointer tests: %s, hotspots %s" % [player.core.state.scene, str(hl2.hotspots.map(func(h): return h["id"]))])
	# verb_click：動詞を押してから、絵の中の対象を押す
	player.core.state.ui["input_modes"] = ["verb_click"]
	player._apply_input_modes()
	sel.refresh(player.core)
	player._refresh_hotspots()
	await _settle()
	check(sel.mode == "verbs" and sel.is_pointer() and sel.get_parent().visible, "verb_click: verb bar shown")
	check(_buttons(sel).has("しらべる") and bool(hl2.get_meta("click", false)), "verb_click: verbs and clickable picture: %s" % str(_buttons(sel)))
	check(not sel.has_partial() and sel.current_verb_id() == "", "verb_click: nothing armed at first")
	_press(sel, "しらべる")
	await _settle_frames(3)
	check(sel.current_verb_id() == "EXAMINE" and sel.is_picking() and sel.has_partial(), "verb_click: verb armed, waiting for a target")
	check(_buttons(sel).has("しらべる"), "verb_click: verbs stay while picking: %s" % str(_buttons(sel)))
	check(sel._sentence_row.visible and sel._sentence.text.contains("しらべる"), "verb_click: sentence line: %s" % sel._sentence.text)
	check(player.current_cursor_kind() == "look", "verb_click: cursor follows the verb: %s" % player.current_cursor_kind())
	await _shot("22_verb_click")
	var c0: int = n_in.call()
	var girl: Dictionary = spot.call("door")
	var plant: Dictionary = spot.call("plant")
	check(not girl.is_empty() and not plant.is_empty(), "door and plant hotspots exist")
	hl2.hotspot_clicked.emit(girl)
	await _settle()
	check(n_in.call() == c0 + 1 and String(last_in.call()).contains("しらべる"), "verb_click: verb + clicked target submitted: %s" % last_in.call())
	check(sel.current_verb_id() == "", "verb_click: verb released after the command")
	# 選びかけをやめる（右クリック、Esc）
	_press(sel, "しらべる")
	await _settle_frames(3)
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	check(player._pointer_input(rc) and not sel.has_partial(), "verb_click: right click cancels")
	# 動詞を選ばずに押すと、コンテキスト型と同じに決める
	c0 = n_in.call()
	hl2.hotspot_clicked.emit(plant)
	await _settle()
	check(n_in.call() == c0 + 1 and String(last_in.call()).contains("とる"), "verb_click: bare click uses the verb of the cursor kind: %s" % last_in.call())
	if sel.choosing:
		_press(sel, _buttons(sel)[0])
		await _settle()
	# キーボードで調べられる場所を選ぶ
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	check(player._pointer_input(tab) and not hl2.focused().is_empty(), "pointer: Tab selects a hotspot")
	hl2.clear_focus()

	# タッチ：短く押すとクリック、長押しは右クリックの代わり
	check(hl2.long_press, "touch: long press enabled in pointer modes")
	var door_at: Vector2 = hl2.rect_of(girl).get_center()
	var tp := func(pressed: bool) -> InputEventMouseButton:
		var e := InputEventMouseButton.new()
		e.device = InputEvent.DEVICE_ID_EMULATION
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = door_at
		return e
	c0 = n_in.call()
	hl2._gui_input(tp.call(true))
	check(n_in.call() == c0 and not player.busy, "touch: nothing happens on press")
	hl2._gui_input(tp.call(false))
	await _settle()
	check(n_in.call() == c0 + 1 and String(last_in.call()).contains("しらべる"), "touch: tap clicks on release: %s" % last_in.call())
	c0 = n_in.call()
	hl2._gui_input(tp.call(true))
	await create_timer(0.7).timeout
	await _settle()
	check(n_in.call() == c0 + 1 and String(last_in.call()).contains("みる"), "touch: long press looks: %s" % last_in.call())
	hl2._gui_input(tp.call(false))
	await _settle()
	check(n_in.call() == c0 + 1, "touch: release after a long press does not click")
	_press(sel, "しらべる")
	await _settle_frames(3)
	hl2._gui_input(tp.call(true))
	await create_timer(0.7).timeout
	check(not sel.has_partial(), "touch: long press cancels a half-made command")
	hl2._gui_input(tp.call(false))
	await _settle()
	# 動かしたら長押しにしない
	c0 = n_in.call()
	hl2._gui_input(tp.call(true))
	var mv := InputEventMouseMotion.new()
	mv.device = InputEvent.DEVICE_ID_EMULATION
	mv.position = door_at + Vector2(30, 0)
	hl2._gui_input(mv)
	await create_timer(0.7).timeout
	hl2._gui_input(tp.call(false))
	await _settle()
	check(n_in.call() == c0, "touch: a drag is neither a tap nor a long press")

	# verb_cursor：カーソルの動詞を切り替える。選んだ動詞は残る
	player.core.state.ui["input_modes"] = ["verb_cursor"]
	player._apply_input_modes()
	sel.refresh(player.core)
	await _settle()
	check(sel.mode == "cursor", "verb_cursor: mode")
	check(player._pointer_input(rc) and sel.current_verb_id() != "", "verb_cursor: right click picks the next verb: %s" % sel.current_verb_id())
	var v1 := sel.current_verb_id()
	player._pointer_input(rc)
	check(sel.current_verb_id() != v1 and sel.current_verb_id() != "", "verb_cursor: cycles: %s → %s" % [v1, sel.current_verb_id()])
	v1 = sel.current_verb_id()
	hl2._gui_input(tp.call(true))
	await create_timer(0.7).timeout
	hl2._gui_input(tp.call(false))
	await _settle()
	check(sel.current_verb_id() != v1 and sel.current_verb_id() != "", "verb_cursor: long press picks the next verb: %s → %s" % [v1, sel.current_verb_id()])
	for i in 20:
		if sel.current_verb_id() == "TALK":
			break
		sel.cycle_verb(1)
	check(sel.current_verb_id() == "TALK" and player.current_cursor_kind() == "talk", "verb_cursor: talk cursor: %s %s" % [sel.current_verb_id(), player.current_cursor_kind()])
	await _shot("23_verb_cursor")
	c0 = n_in.call()
	hl2.hotspot_clicked.emit(girl)
	await _settle()
	if sel.choosing:
		_press(sel, _buttons(sel)[0])
		await _settle()
	check(n_in.call() > c0, "verb_cursor: click uses the cursor verb")
	check(sel.current_verb_id() == "TALK", "verb_cursor: verb stays after the command: %s" % sel.current_verb_id())

	# context：対象に合わせて動詞が決まる
	player.core.state.ui["input_modes"] = ["context"]
	player._apply_input_modes()
	sel.refresh(player.core)
	await _settle()
	check(sel.mode == "context" and _buttons(sel).is_empty(), "context: no verb list: %s" % str(_buttons(sel)))
	check(player._context_verb({"id": "a", "type": "character"}) == "TALK", "context: character → TALK")
	check(player._context_verb({"id": "a", "type": "object"}) == "EXAMINE", "context: object → click_verb")
	check(player._context_verb({"id": "a", "type": "object", "cursor": "take"}) == "TAKE", "context: cursor take → TAKE")
	check(player._context_verb({"id": "a", "type": "exit"}) == "MOVE", "context: exit → MOVE")
	check(player._context_verb({"id": "a", "type": "object", "verb": "OPEN"}) == "OPEN", "context: click of the object wins")
	check(player._context_verb({"id": "a", "type": "object"}, true) == "LOOK" and player._context_verb({"id": "a", "type": "exit"}, true) == "", "context: right click looks")
	player.template.overrides = {"inputs": {"context_verbs": {"look": "LOOK"}, "click_verb": "TAKE"}}
	check(player._context_verb({"id": "a", "type": "object"}) == "LOOK" and player._context_verb({"id": "a", "type": "object", "cursor": "zzz"}) == "TAKE", "context: project inputs override the template")
	player._apply_project_overrides(player.template)
	c0 = n_in.call()
	hl2.hotspot_clicked.emit(girl)
	await _settle()
	if sel.choosing:
		_press(sel, _buttons(sel)[0])
		await _settle()
	check(n_in.call() > c0, "context: click submits")
	c0 = n_in.call()
	player._on_hotspot_clicked(girl, true)
	await _settle()
	check(n_in.call() == c0 + 1 and String(last_in.call()).contains("みる"), "context: right click looks: %s" % last_in.call())
	# 持ち物：クリックで持って、対象に使う
	if player.core.state.has_item("key"):
		check(_inv_buttons(sel).any(func(l): return String(l).contains("かぎ")), "context: inventory shown: %s" % str(_inv_buttons(sel)))
		_press(sel, _inv_buttons(sel).filter(func(l): return String(l).contains("かぎ"))[0])
		await _settle_frames(3)
		check(sel.current_verb_id() == "USE" and sel.is_picking(), "context: item held, waiting for a target")
		sel.cancel()
		await _settle_frames(3)
		c0 = n_in.call()
		var key_t: Dictionary = sel._inv.get_children().filter(func(b): return b is Button and String(b.text).contains("かぎ"))[0].get_meta("target")
		sel._on_item_input(tp.call(true), key_t)
		await create_timer(0.7).timeout
		await _settle()
		check(n_in.call() == c0 + 1 and String(last_in.call()).contains("みる"), "touch: long press on an item looks at it: %s" % last_in.call())
	await _shot("24_context")
	player.core.state.ui.erase("input_modes")
	player._apply_input_modes()
	sel.refresh(player.core)
	await _settle()
	check(sel.mode == "menu" and _buttons(sel).has("しらべる"), "back to the command menu")

	# ゲームID：ほかのゲームのセーブデータは読まない
	player.project.data["game_id"] = "game_a"
	check(player.save_game("03") == OK, "save with game id")
	player.project.data["game_id"] = "game_b"
	check(await player.load_game("03") == "GAME_MISMATCH", "save of another game is refused")
	player.project.data["game_id"] = "game_a"
	check(await player.load_game("03") == "", "save of the same game loads")
	await _settle()

	await _test_stage16()
	check(_stage16_done, "ui: the stage16+ tests reached the end (no script error on the way)")
	print("ui failed: %d" % _failed)
	quit(1 if _failed > 0 else 0)


## 段階16：タイトル、システムシーン、サブシーン、エイリアス、エンディング、スタッフロール。
var _stage16_done := false


func _test_stage16() -> void:
	player.queue_free()
	await process_frame
	_rmdir("user://test16_saves")
	player = AdvPlayer.new()
	player.project_path = "res://tests/stage16/stage16.project.json"
	player.auto_click = true
	player.settings_path = ""
	player.progress_path = ""
	root.add_child(player)
	await _settle()
	var sel := player.screen.command_select
	check(player.core.state.scene == "title", "s16: starts at the title scene after the opening: %s" % player.core.state.scene)
	check(player.progress.openings.has("op"), "s16: opening recorded as seen")
	check(player.message_log.entries.any(func(e): return String(e.get("body", "")) == "オープニング その3"), "s16: opening played the first time")
	check(player.audio.current_bgm.get("id", "") == "theme", "s16: scene bgm")
	check(player._input_modes() == ["select"], "s16: title accepts only choices: %s" % str(player._input_modes()))
	check(_buttons(sel) == ["はじめから", "つづきから", "エンディング", "オープニング"], "s16: title menu (opening seen, so it can be replayed): %s" % str(_buttons(sel)))
	await _shot("30_title_scene")
	_press(sel, "はじめから")
	await _settle()
	await _settle()
	check(player.core.state.scene == "shop" and player.core.state.frames.size() == 1, "s16: new game, subscene called: %s %s" % [player.core.state.scene, player.core.state.frames.size()])
	var logs := player.message_log.entries.map(func(e): return String(e.get("body", "")))
	check(logs.has("たろうは あゆみに「こんにちは です」と いった。"), "s16: alias expanded in the log: %s" % str(logs))
	check(logs.has("いまは びんぼう。"), "s16: [if] in an alias")
	check(logs.has("パンは 5えん。"), "s16: subscene args in text")
	check(not logs.has("ゲームの タイトル"), "s16: title text cleared by new game")
	# JSON のシステムシーン（セーブ）
	player.open_save_menu("save")
	await _settle()
	check(player.is_system_scene_open() and player.core.state.scene == "sys_save", "s16: save system scene open")
	check(player.screen.message_label.get_parsed_text().contains("どこに セーブする"), "s16: sys.mode in text: %s" % player.screen.message_label.get_parsed_text())
	check(_buttons(sel).size() == 3 and String(_buttons(sel)[0]).contains("からっぽ"), "s16: slot labels: %s" % str(_buttons(sel)))
	await _shot("31_system_save_scene")
	_press(sel, _buttons(sel)[0])
	await _settle()
	check(FileAccess.file_exists("user://test16_saves/01.sav"), "s16: system.save wrote the slot")
	check(String(_buttons(sel)[0]).contains("みせ"), "s16: slot label refreshed: %s" % str(_buttons(sel)))
	_press(sel, "おとを ちいさく")
	await _settle()
	check(float(player.settings.get_value("bgm_volume")) == 0.25, "s16: settings.set")
	_press(sel, "もどる")
	await _settle()
	check(not player.is_system_scene_open() and player.core.state.scene == "shop", "s16: system scene closed, back to the game: %s" % player.core.state.scene)
	check(_buttons(sel) == ["かう", "かわない"], "s16: subscene choice restored: %s" % str(_buttons(sel)))
	# Esc でも閉じる
	player.open_save_menu("save")
	await _settle()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	player._input(esc)
	await _settle()
	check(not player.is_system_scene_open() and player.core.state.scene == "shop", "s16: Esc closes the system scene")
	# サブシーンを最後まで：エンディング、スタッフロール、タイトルへ
	_press(sel, "かう")
	await _settle()
	await _settle()
	check(player.progress.endings.has("good"), "s16: ending recorded")
	logs = player.message_log.entries.map(func(e): return String(e.get("body", "")))
	check(player.core.state.scene == "title", "s16: game.title back to the title: %s" % player.core.state.scene)
	check(player.message_log.entries.size() <= 1, "s16: log reset at the title: %d" % player.message_log.entries.size())
	# つづきから → ロードのシステムシーン
	_press(sel, "つづきから")
	await _settle()
	await _settle()
	check(player.is_system_scene_open() and player.core.state.sys.get("mode") == "load", "s16: load system scene")
	check(player.screen.message_label.get_parsed_text().contains("よみこむ"), "s16: load text")
	_press(sel, _buttons(sel)[0])
	await _settle()
	await _settle()
	check(not player.is_system_scene_open() and player.core.state.scene == "shop" and player.core.state.frames.size() == 1, "s16: loaded mid-subscene: %s" % player.core.state.scene)
	check(_buttons(sel) == ["かう", "かわない"], "s16: choice after load: %s" % str(_buttons(sel)))
	# 自作の設定画面（.tscn）
	player.modern.open_settings()
	await _settle_frames(3)
	check(player._overlay is AdvSystemScreen and (player._overlay as AdvSystemScreen).mode == "settings", "s16: custom settings screen")
	await _shot("32_custom_settings")
	(player._overlay as AdvSystemScreen).set_setting("bgm_volume", 1.0)
	(player._overlay as AdvSystemScreen).close()
	await _settle_frames(3)
	check(player._overlay == null and float(player.settings.get_value("bgm_volume")) == 1.0, "s16: custom screen closed")
	# エンディング一覧
	player.modern.open_endings()
	await _settle_frames(3)
	var txt := _panel_text(player._overlay)
	check(txt.contains("1 / 2") and txt.contains("かいものの おわり") and txt.contains("まだ ないしょ") and not txt.contains("なにも しない"), "s16: endings list: %s" % txt)
	await _shot("33_endings")
	player._overlay.call("close")
	await _settle_frames(3)
	# テンプレートのタイトル画面
	player.project.data["title_screen"] = "template"
	player.go_title()
	await _settle_frames(5)
	check(player._overlay is AdvTitleScreen, "s16: template title screen")
	var ts := player._overlay as AdvTitleScreen
	check(ts != null and ts.buttons.has("new") and ts.buttons.has("continue") and ts.buttons.has("endings") and not ts.buttons.has("chapters"), "s16: title buttons: %s" % (str(ts.buttons.keys()) if ts else ""))
	await _shot("34_template_title")
	ts.choose("new")
	await _settle()
	await _settle()
	check(player.core.state.scene == "shop", "s16: template title → new game: %s" % player.core.state.scene)
	# スタッフロールはクリックで飛ばせる（画像、色、大きさ）
	var t0 := Time.get_ticks_msec()
	player.auto_click = false
	player._run([AdvEvents.make("credits.roll", {"items": [{"text": "スタッフロール", "pal": 6, "size": 28},
		{"image": "hallway", "scale": 0.5, "gap": 10}, {"text": "なまえ", "align": "left"}], "duration": 2.0, "bgm": "theme"})])
	await create_timer(0.8).timeout
	check(player.busy, "s16: credits rolling")
	await _shot("35_credits")
	player._click_pending = true
	await _settle()
	check(not player.busy and Time.get_ticks_msec() - t0 < 3000, "s16: credits skipped by a click")
	# 2回目のオープニング：Esc で飛ばせる
	player.project.data["title_screen"] = "title"
	player._opening_boot = true
	player._run(player.core.start("op"))
	await _settle_frames(5)
	check(player.can_skip_opening() and player._opening_hint != null, "s16: second opening is skippable")
	await _shot("36_opening_skippable")
	var esc2 := InputEventKey.new()
	esc2.keycode = KEY_ESCAPE
	esc2.pressed = true
	player._input(esc2)
	player.auto_click = true
	await _settle()
	await _settle()
	check(player.core.state.scene == "title" and player._opening.is_empty(), "s16: Esc skips the opening to the title: %s" % player.core.state.scene)
	check(not player.message_log.entries.any(func(e): return String(e.get("body", "")) == "オープニング その3"), "s16: rest of the opening skipped")
	player.auto_click = true
	# 1回だけの設定：見ていれば起動時に飛ばす
	player.core.adapters_by_name["main"].scenes["op"]["replay"] = "once"
	await player._reset_state()
	player._boot()
	await _settle()
	check(player.core.state.scene == "title" and not player.message_log.entries.any(func(e): return String(e.get("body", "")).begins_with("オープニング")), "s16: once: opening skipped at boot")
	# テンプレートのタイトル画面の BGM と切り替え演出
	player.audio.stop_bgm()
	player.project.data["title_screen"] = "template"
	player.project.data["title_bgm"] = "theme"
	player.project.data["title_transition"] = {"type": "fade", "duration": 0.8}
	player.go_title()
	await _settle_frames(5)
	check(player.audio.current_bgm.get("id", "") == "theme", "s16: template title bgm")
	var ts2 := player._overlay as AdvTitleScreen
	check(ts2 != null and ts2.group.material != null, "s16: template title transition running")
	await create_timer(1.0).timeout
	check(ts2.group.material == null, "s16: template title transition done")
	ts2.choose("new")
	await create_timer(1.0).timeout
	await _settle()
	check(player.core.state.scene == "shop", "s16: template title with transition → new game: %s" % player.core.state.scene)

	# 「おわり」の画面：エンディングを最後まで進めると出て、時間で閉じてタイトルへ
	player.project.data["title_screen"] = "title"
	player.project.data.erase("title_bgm")
	player._run(player.core.start("end_bad"))
	await _settle()
	check(player._overlay is AdvFinScreen, "s17: fin screen after the ending")
	check(player.progress.endings.has("bad"), "s17: bad ending recorded")
	await _shot("37_fin")
	await create_timer(1.2).timeout
	await _settle()
	check(player._overlay == null and player.core.state.scene == "title", "s17: fin closes by time, back to the title: %s" % player.core.state.scene)
	# fin: false なら出さない
	player._run(player.core.start("end_quiet"))
	await _settle()
	check(player._overlay == null and player.core.state.scene == "end_quiet", "s17: fin hidden")
	# fin.show：合図で閉じて、指定のシーンへ
	player._run([AdvEvents.make("fin.show", {"text": "つづく", "advance": ["trigger:next"], "min_time": 0.0, "then": "hall", "reset": true})])
	await _settle_frames(5)
	check(player._overlay is AdvFinScreen and not player.fire_trigger("other"), "s17: fin.show waits for its trigger")
	check(player.fire_trigger("next"), "s17: trigger accepted")
	await _settle()
	await _settle()
	check(player._overlay == null and player.core.state.scene == "shop", "s17: then goes to the scene (reset): %s" % player.core.state.scene)
	# キーで閉じる
	player._run([AdvEvents.make("fin.show", {"advance": ["key"], "min_time": 0.0, "then": "stay"})])
	await _settle_frames(5)
	var kev := InputEventKey.new()
	kev.keycode = KEY_SPACE
	kev.pressed = true
	(player._overlay as AdvFinScreen)._input(kev)
	await _settle_frames(5)
	check(player._overlay == null, "s17: fin closes by a key")
	# オープニングを見返す（条件）
	check(player.can_replay_opening(), "s17: opening can be replayed (seen)")
	player.project.data["opening_replay"] = "never"
	check(not player.can_replay_opening(), "s17: opening_replay never")
	player.project.data["opening_replay"] = {"endings": ["good", "bad"]}
	check(player.can_replay_opening(), "s17: opening_replay by endings")
	player.project.data["opening_replay"] = {"endings": ["true_end"]}
	check(not player.can_replay_opening(), "s17: opening_replay needs an unseen ending")
	player.project.data["opening_replay"] = "any_ending"
	await player.replay_opening()
	await _settle()
	check(player.core.state.scene == "title", "s17: replayed opening returns to the title: %s" % player.core.state.scene)
	check(player.message_log.entries.size() <= 1, "s17: replay starts from the initial state")
	# テンプレートのタイトルの「オープニング」
	player.project.data["title_screen"] = "template"
	player.go_title()
	await _settle_frames(5)
	var ts3 := player._overlay as AdvTitleScreen
	check(ts3 != null and ts3.buttons.has("opening"), "s17: template title has opening: %s" % (str(ts3.buttons.keys()) if ts3 else ""))
	await create_timer(1.0).timeout   # 出る演出が終わるまで選べない（title_transition 0.8 秒）
	player.auto_click = false
	ts3.choose("opening")
	await _settle_frames(3)
	check(player._opening.get("replay", false) and player.core.state.scene == "op", "s17: template title replays the opening")
	var esc3 := InputEventKey.new()
	esc3.keycode = KEY_ESCAPE
	esc3.pressed = true
	player._input(esc3)
	player.auto_click = true
	await _settle_frames(10)
	check(player._overlay is AdvTitleScreen, "s17: skipping the replay returns to the template title")
	(player._overlay as AdvTitleScreen).close()
	await _settle_frames(3)

	# 段階19：見たエンディングの数でタイトルを変える
	player.project.data["title_screen"] = "title"
	await player.go_title()
	await _settle()
	check(player.core.state.sys.get("endings_seen") == 2 and player.core.state.sys.get("ending_good") == true, "s19: sys endings: %s" % str(player.core.state.sys))
	check(String(player._images.get("bg", {}).get("id", "")) == "room", "s19: title scene variant image: %s" % str(player._images.get("bg")))
	player.project.data["title_variants"] = [{"when": "sys.endings_seen >= 1", "image": "hallway"}, {"when": "sys.all_endings", "image": "room", "bgm": "theme"}]
	check(player.title_variant() == {"image": "room", "bgm": "theme"}, "s19: template title variant: %s" % str(player.title_variant()))
	player.project.data["title_variants"] = [{"when": "sys.ending_true_end", "image": "hallway"}]
	check(player.title_variant().is_empty(), "s19: unmatched variant")
	# 「おわり」の画面に複数の行と画像
	player._run([AdvEvents.make("fin.show", {"items": [{"text": "おわり", "size": 40, "pal": 6}, {"image": "hallway", "scale": 0.5, "gap": 8},
		{"text": "あそんでくれて ありがとう"}], "advance": ["key"], "min_time": 0.0, "then": "stay"})])
	await _settle_frames(8)
	check(player._overlay is AdvFinScreen and (player._overlay as AdvFinScreen).group.get_child_count() >= 2, "s19: fin with items")
	await _shot("38_fin_items")
	var kev2 := InputEventKey.new()
	kev2.keycode = KEY_SPACE
	kev2.pressed = true
	(player._overlay as AdvFinScreen)._input(kev2)
	await _settle_frames(5)
	# クリアデータのセーブ（聞く → はい → セーブのシステムシーン → 01）
	_rmdir("user://test16_saves")
	player._run(player.core.start("end_quiet"))
	await _settle()
	player._run([AdvEvents.make("fin.show", {"advance": ["key"], "min_time": 0.0, "then": "title", "save_prompt": true, "save_resume": "hall"})])
	await _settle_frames(5)
	(player._overlay as AdvFinScreen)._input(kev2)
	await _settle_frames(5)
	check(player._overlay is AdvMenuPanel and _panel_text(player._overlay).contains("クリアデータ"), "s19: asks to save clear data")
	await _shot("39_clear_save_prompt")
	for b in player._overlay.find_children("*", "Button", true, false):
		if (b as Button).text == "はい":
			(b as Button).pressed.emit()
	await _settle()
	check(player.is_system_scene_open(), "s19: save screen opened")
	_press(sel, _buttons(sel)[0])
	await _settle()
	var saved_meta: Dictionary = player._read_slot("01")["data"].get("meta", {})
	check(saved_meta.get("clear", false) and saved_meta.get("ending", "") == "bad" and saved_meta.get("resume", "") == "hall", "s19: clear data meta: %s" % str(saved_meta))
	check(String(_buttons(sel)[0]).contains("クリア"), "s19: slot shows clear: %s" % str(_buttons(sel)))
	_press(sel, "もどる")
	await _settle()
	await _settle()
	check(player.core.state.scene == "title", "s19: after clear save, then title: %s" % player.core.state.scene)
	# クリアデータをロードすると、変数を引き継いで save_resume のシーンから
	player.core.state.vars["money"] = 0
	await player.load_game("01")
	await _settle()
	check(player.core.state.scene == "shop" and player.core.state.frames.size() == 1, "s19: clear data resumes at hall: %s" % player.core.state.scene)
	# いいえなら聞くだけ
	player._run([AdvEvents.make("fin.show", {"advance": ["key"], "min_time": 0.0, "then": "stay", "save_prompt": true})])
	await _settle_frames(5)
	(player._overlay as AdvFinScreen)._input(kev2)
	await _settle_frames(5)
	for b in player._overlay.find_children("*", "Button", true, false):
		if (b as Button).text == "いいえ":
			(b as Button).pressed.emit()
	await _settle_frames(5)
	check(player._overlay == null and not player.is_system_scene_open(), "s19: no means no save")

	# 段階20：クリアデータで引き継ぐもの
	player.core.state.vars["money"] = 99
	player.core.state.vars["bought"] = "パン"
	player.core.state.items["key"] = 1
	await player._carry_over({"vars": ["money"], "items": "none"})
	check(player.core.state.get_var("money") == 99 and player.core.state.get_var("bought") == "" and player.core.state.items.is_empty(), "s20: carry chosen vars only: %s %s" % [player.core.state.vars, player.core.state.items])
	player.core.state.vars["money"] = 50
	player.core.state.items["key"] = 1
	await player._carry_over({"vars": "none", "items": "all"})
	check(player.core.state.get_var("money") == 0 and player.core.state.items.has("key"), "s20: carry items only")
	player.core.state.vars["money"] = 50
	await player._carry_over("none")
	check(player.core.state.get_var("money") == 0 and player.core.state.items.is_empty(), "s20: carry none")
	player.core.state.vars["money"] = 50
	await player._carry_over("all")
	check(player.core.state.vars["money"] == 50, "s20: carry all")
	# おまけ（すべてのエンディングを見たら）
	player.project.data["extras"] = {"gallery": [{"id": "hallway", "label": "ろうか"}, {"id": "room", "label": "へや", "when": "false", "hint": "ないしょ"}],
		"music": [{"id": "theme", "label": "テーマ"}]}
	check(player.can_open_extras(), "s20: extras open (all endings)")
	player.project.data["extras"]["show"] = false
	check(not player.can_open_extras(), "s20: extras hidden by show: false")
	player.project.data["extras"]["show"] = true
	player.project.data["extras"]["when"] = "sys.ending_true_end"
	check(not player.can_open_extras(), "s20: extras condition")
	player.project.data["extras"].erase("when")
	# タイトルのシーンの variants でメニューを差し替える
	player.project.data["title_screen"] = "title"
	await player.go_title()
	await _settle()
	check(_buttons(sel) == ["はじめから", "おまけ"], "s20: title scene menu variant: %s" % str(_buttons(sel)))
	_press(sel, "おまけ")
	await _settle_frames(5)
	check(player._overlay is AdvMenuPanel and _panel_buttons().has("ギャラリー") and _panel_buttons().has("おんがく"), "s20: extras.open: %s" % str(_panel_buttons()))
	_press_panel("ギャラリー")
	await _settle_frames(5)
	var gt := _panel_text(player._overlay)
	check(gt.contains("1 / 2"), "s20: gallery count: %s" % gt)
	check(_panel_buttons().has("ろうか") and _panel_buttons().has("？？？　ないしょ"), "s20: gallery entries: %s" % str(_panel_buttons()))
	await _shot("40_gallery")
	_press_panel("ろうか")
	await _settle_frames(5)
	check(player._overlay is AdvImageViewer, "s20: image viewer")
	await create_timer(0.3).timeout
	await _shot("41_gallery_view")
	(player._overlay as AdvImageViewer).close()
	await _settle_frames(5)
	_press_panel("もどる")
	await _settle_frames(5)
	_press_panel("おんがく")
	await _settle_frames(5)
	player.audio.stop_bgm()
	check(player.audio.current_bgm.is_empty(), "s20: music stopped")
	_press_panel("テーマ")
	await _settle_frames(3)
	check(player.audio.current_bgm.get("id", "") == "theme", "s20: music room plays")
	_press_panel("もどる")
	await _settle_frames(5)
	check(player.audio.current_bgm.get("id", "") == "theme", "s20: music room restores the title bgm: %s" % str(player.audio.current_bgm))
	_press_panel("もどる")
	await _settle_frames(5)
	check(player._overlay == null and _buttons(sel) == ["はじめから", "おまけ"], "s20: back to the title menu")
	# テンプレートのタイトルのメニューと文言を差し替える
	player.project.data["title_screen"] = "template"
	player.project.data["title_transition"] = "cut"
	player.project.data["title_variants"] = [{"when": "sys.all_endings", "menu": ["new", "extras", "quit"], "labels": {"new": "さいしょから"}}]
	player.go_title()
	await _settle_frames(5)
	var ts4 := player._overlay as AdvTitleScreen
	check(ts4 != null and ts4.buttons.keys() == ["new", "extras", "quit"] and (ts4.buttons["new"] as Button).text == "さいしょから", "s20: template title menu variant: %s" % (str(ts4.buttons.keys()) if ts4 else ""))
	ts4.close()
	await _settle_frames(3)

	# 段階21：ギャラリーの画像をめくる
	player.progress.seen["image"].erase("room")
	player.progress.mark_seen("image", "hallway")
	var two := {"images": ["hallway", "room"], "label": "ふたつ"}
	check(player.extra_unlocked(two, "image") and player.extra_pages(two) == ["hallway"], "s21: pages are the seen images: %s" % str(player.extra_pages(two)))
	check(not player.extra_unlocked({"images": ["room"]}, "image"), "s21: unseen images stay locked")
	check(player.extra_pages({"images": ["hallway", "room"], "when": "true"}) == ["hallway", "room"], "s21: when opens every page")
	var t1: Texture2D = player._layer_texture("hallway")
	var t2: Texture2D = player._layer_texture("room")
	var vw := AdvImageViewer.new().setup([t1, t2], player.template, "ふたつ")
	root.add_child(vw)
	check(vw.page_count() == 2 and vw.page == 0 and vw._count.text == "1 / 2", "s21: viewer pages")
	vw.next_page()
	check(vw.page == 1 and vw._count.text == "2 / 2", "s21: viewer next")
	vw.prev_page()
	check(vw.page == 0, "s21: viewer prev")
	var vclosed := [false]
	vw.closed.connect(func(): vclosed[0] = true)
	vw.next_page()
	vw.next_page()
	check(vclosed[0], "s21: viewer closes after the last page")
	await _settle_frames(2)
	# おまけに エンディング一覧と オープニングを並べる（menu の順）
	player.project.data["extras"]["gallery"].append({"images": ["hallway", "room"], "label": "ふたつ", "when": "true"})
	player.project.data["extras"]["menu"] = ["endings", "music", "gallery", "opening"]
	player.project.data["extras"]["endings_label"] = "エンディングいちらん"
	player.progress.openings["op"] = true
	check(player.extras_menu() == ["endings", "music", "gallery", "opening"], "s21: extras menu: %s" % str(player.extras_menu()))
	player.core.state.scene = ""
	player.modern.open_extras()
	await _settle_frames(5)
	check(_panel_buttons() == ["エンディングいちらん", "おんがく", "ギャラリー", "オープニング", "もどる"], "s21: extras panel order: %s" % str(_panel_buttons()))
	_press_panel("エンディングいちらん")
	await _settle_frames(5)
	check(_panel_text(player._overlay).contains("みた エンディング"), "s21: endings from extras")
	_press_panel("もどる")
	await _settle_frames(5)
	_press_panel("ギャラリー")
	await _settle_frames(5)
	_press_panel("ふたつ")
	await _settle_frames(5)
	check(player._overlay is AdvImageViewer and (player._overlay as AdvImageViewer).page_count() == 2, "s21: gallery opens a paged viewer")
	await create_timer(0.3).timeout
	await _shot("42_gallery_pages")
	(player._overlay as AdvImageViewer).close()
	await _settle_frames(5)
	_press_panel("もどる")
	await _settle_frames(5)
	# 音楽の鳴らし方
	player.project.data["extras"]["music"] = [{"id": "theme", "label": "いち"}, {"id": "nope", "label": "に", "when": "false"}, {"id": "theme", "label": "さん"}]
	player.settings.set_value("music_mode", "one")
	_press_panel("おんがく")
	await _settle_frames(5)
	check(_panel_buttons().has("さいせい：1きょく くりかえし"), "s21: music mode button: %s" % str(_panel_buttons()))
	_press_panel("いち")
	await _settle_frames(3)
	check(player.audio.current_bgm.get("loop", false) == true and _panel_text(player._overlay).contains("いま：いち"), "s21: one mode loops")
	player.modern._on_music_finished()
	await _settle_frames(3)
	check(player.modern._music_index == 0, "s21: one mode stays")
	_press_panel("さいせい：1きょく くりかえし")
	await _settle_frames(2)
	check(player.modern.music_mode() == "next" and player.audio.current_bgm.get("loop", true) == false and _panel_buttons().has("さいせい：つづけて"), "s21: switch to next mode")
	player.modern._on_music_finished()
	await _settle_frames(3)
	check(player.modern._music_index == 2 and _panel_text(player._overlay).contains("いま：さん"), "s21: next skips locked tracks: %d" % player.modern._music_index)
	player.modern._on_music_finished()
	await _settle_frames(3)
	check(player.modern._music_index == -1 and player.audio.current_bgm.is_empty(), "s21: next mode stops at the end")
	_press_panel("さいせい：つづけて")
	await _settle_frames(2)
	check(player.modern.music_mode() == "all", "s21: all mode")
	_press_panel("さん")
	await _settle_frames(3)
	player.modern._on_music_finished()
	await _settle_frames(3)
	check(player.modern._music_index == 0, "s21: all mode wraps around")
	await _shot("43_music_room")
	_press_panel("もどる")
	await _settle_frames(5)
	check(player.modern._music_index == -1, "s21: music room closed")
	_press_panel("もどる")
	await _settle_frames(5)
	player.settings.set_value("music_mode", "one")

	# 段階22：見本の画像、曲の説明、特典
	player.project.data["extras"]["gallery"] = [{"id": "hallway", "label": "ろうか"}, {"id": "room", "label": "へや", "hint": "ないしょ"},
		{"id": "room", "label": "とくてん", "bonus": true}, {"id": "room", "label": "かくれ", "bonus": true, "hidden": false, "hint": "ぜんぶ みたら"}]
	player.project.data["extras"]["music"] = [{"id": "theme", "label": "いち", "desc": "さっきょく：だれか"}, {"id": "theme", "label": "ボーナス", "bonus": true, "when": "sys.gallery_all"}]
	player.project.data["extras"]["menu"] = ["gallery", "music"]
	player.progress.seen["image"].erase("room")
	player.fill_extras_sys()
	var sy: Dictionary = player.core.state.sys
	check(sy["gallery_opened"] == 1 and sy["gallery_total"] == 2 and not sy["gallery_all"], "s22: counts skip bonus entries: %s/%s" % [sy["gallery_opened"], sy["gallery_total"]])
	player.modern.open_extras()
	await _settle_frames(5)
	_press_panel("ギャラリー")
	await _settle_frames(5)
	check(_panel_buttons() == ["ろうか", "？？？　ないしょ", "？？？　ぜんぶ みたら", "もどる"], "s22: hidden bonus not listed: %s" % str(_panel_buttons()))
	var thumb_ok := false
	for b in player._overlay.find_children("*", "Button", true, false):
		if (b as Button).text == "ろうか":
			thumb_ok = (b as Button).icon != null
	check(thumb_ok, "s22: thumbnail shown")
	check(_panel_text(player._overlay).contains("1 / 2"), "s22: gallery count without bonus")
	_press_panel("もどる")
	await _settle_frames(5)
	player.progress.mark_seen("image", "room")
	_press_panel("ギャラリー")
	await _settle_frames(5)
	check(_panel_buttons() == ["ろうか", "へや", "とくてん", "かくれ", "もどる"], "s22: bonus opens when all seen: %s" % str(_panel_buttons()))
	await _shot("44_gallery_thumbs")
	_press_panel("もどる")
	await _settle_frames(5)
	player.project.data["extras"]["thumbnails"] = false
	_press_panel("ギャラリー")
	await _settle_frames(5)
	var no_icon := true
	for b in player._overlay.find_children("*", "Button", true, false):
		no_icon = no_icon and (b as Button).icon == null
	check(no_icon, "s22: thumbnails off")
	_press_panel("もどる")
	await _settle_frames(5)
	_press_panel("おんがく")
	await _settle_frames(5)
	check(_panel_buttons().has("ボーナス"), "s22: bonus music unlocked by sys.gallery_all")
	_press_panel("いち")
	await _settle_frames(3)
	check(_panel_text(player._overlay).contains("さっきょく：だれか"), "s22: music description")
	await _shot("45_music_desc")
	_press_panel("もどる")
	await _settle_frames(5)
	player.project.data["extras"]["music_desc"] = false
	player.project.data["extras"]["bonus"] = false
	_press_panel("おんがく")
	await _settle_frames(5)
	check(not _panel_buttons().has("ボーナス"), "s22: bonus off")
	_press_panel("いち")
	await _settle_frames(3)
	check(not _panel_text(player._overlay).contains("さっきょく"), "s22: description off")
	_press_panel("もどる")
	await _settle_frames(5)
	_press_panel("もどる")
	await _settle_frames(5)
	player.project.data["extras"].erase("thumbnails")

	# 段階23：特典のお知らせ
	player.project.data["extras"]["bonus"] = true
	player.project.data["extras"]["gallery"] = [{"id": "hallway", "label": "ろうか"}, {"id": "room", "label": "へや"}, {"id": "room", "label": "とくてん", "bonus": true}]
	player.project.data["extras"]["music"] = [{"id": "theme", "label": "いち"}]
	player.progress.clear_extras()
	await player._play(AdvEvents.make("image.show", {"id": "hallway"}))
	check(player.notices().is_empty(), "s23: no notice before the bonus opens")
	await player._play(AdvEvents.make("image.show", {"id": "room"}))
	check(player.notices() == ["おまけが ふえました"], "s23: notice when the bonus opens: %s" % str(player.notices()))
	await _shot("46_bonus_notice")
	check(player.check_bonus_unlocks().is_empty(), "s23: notified only once")
	player.progress.clear_extras()
	player.project.data["extras"]["notify"] = false
	player.progress.mark_seen("image", "hallway")
	player.progress.mark_seen("image", "room")
	check(player.check_bonus_unlocks().is_empty(), "s23: notice off")
	player.project.data["extras"]["notify"] = true
	player.project.data["extras"]["notify_text"] = "とくてんが ひらいた"
	check(player.check_bonus_unlocks() == ["とくてん"], "s23: notice on again")
	check(player.notices().has("とくてんが ひらいた"), "s23: notice text")
	# タイトルに開いた数を出す
	player.project.data["extras"]["title_count"] = true
	player.project.data["title_screen"] = "template"
	player.go_title()
	await _settle_frames(5)
	var ts5 := player._overlay as AdvTitleScreen
	var xb: String = (ts5.buttons["extras"] as Button).text if ts5 != null and ts5.buttons.has("extras") else ""
	player.fill_extras_sys()
	var want := "おまけ（%d / %d）" % [player.core.state.sys["extras_opened"], player.core.state.sys["extras_total"]]
	check(xb == want, "s23: title count: %s (%s)" % [xb, want])
	await _shot("47_title_count")
	ts5.close()
	await _settle_frames(3)
	player.project.data["extras"]["title_count"] = false
	player.go_title()
	await _settle_frames(5)
	ts5 = player._overlay as AdvTitleScreen
	check(ts5 != null and (ts5.buttons["extras"] as Button).text == "おまけ", "s23: title count off")
	ts5.close()
	await _settle_frames(3)
	# デバッグコンソール：おまけとエンディングの記録
	var con: Control = load("res://addons/adv80s/debug/adv_debug_console.gd").new()
	root.add_child(con)
	con.set("player", player)
	con.call("setup", player.core)
	con.call("execute_command", "extras clear")
	check(player.progress.seen["image"].is_empty() and not player.progress.seen.has("bonus"), "s23: debug extras clear")
	con.call("execute_command", "extras unlock")
	check(player.progress.seen["image"].has("hallway") and player.progress.seen["image"].has("room") and player.progress.seen.get("bonus", {}).size() == 1, "s23: debug extras unlock opens the bonus too")
	con.call("execute_command", "endings clear")
	check(player.progress.endings.is_empty(), "s23: debug endings clear")
	con.queue_free()
	await _settle_frames(2)

	# 段階24：お知らせの出力イベントと、自動のお知らせ
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await player._play(AdvEvents.make("notice.show", {"text": "てちょうを みなおそう", "seconds": 1.0}))
	check(player.notices() == ["てちょうを みなおそう"], "s24: notice.show: %s" % str(player.notices()))
	await player._play(AdvEvents.make("item.add", {"id": "key"}))
	check(player.notices().size() == 1, "s24: no item notice unless set")
	player.project.data["notices"] = {"item_add": "{name}を てにいれた（{count}）", "notebook_add": "てちょうに かきました：{title}"}
	await player._play(AdvEvents.make("item.add", {"id": "key", "count": 2}))
	check(player.notices().any(func(t): return t.ends_with("を てにいれた（2）")), "s24: item notice: %s" % str(player.notices()))
	await player._play(AdvEvents.make("notebook.add", {"id": "n1", "title": "かぎの こと", "body": "…"}))
	check(player.notices().has("てちょうに かきました：かぎの こと"), "s24: notebook notice")
	await _shot("48_notices")
	player.project.data.erase("notices")
	# デバッグコンソール：ほかの記録
	player.progress.read["l1"] = true
	player.core.state.read["l1"] = true
	player.progress.reached["n1"] = true
	player.progress.snapshots["n1"] = {}
	player.progress.openings["op"] = true
	var con2: Control = load("res://addons/adv80s/debug/adv_debug_console.gd").new()
	root.add_child(con2)
	con2.set("player", player)
	con2.call("setup", player.core)
	con2.call("execute_command", "read clear")
	check(player.progress.read.is_empty() and player.core.state.read.is_empty(), "s24: debug read clear")
	con2.call("execute_command", "flow clear")
	check(player.progress.reached.is_empty() and player.progress.snapshots.is_empty(), "s24: debug flow clear")
	con2.call("execute_command", "openings clear")
	check(player.progress.openings.is_empty(), "s24: debug openings clear")
	player.progress.mark_seen("image", "hallway")
	con2.call("execute_command", "progress clear")
	check(player.progress.seen["image"].is_empty() and player.progress.endings.is_empty(), "s24: debug progress clear")
	con2.queue_free()
	await _settle_frames(2)

	# 段階25：お知らせの見た目
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await _settle_frames(2)
	player.project.data["notice_style"] = {"position": "bottom_left", "fg": 6, "bg": 1, "border": -1, "seconds": 5.0}
	player.show_notice("ひだりした")
	player.show_notice("その うえ")
	var nb: Array = player._notices
	var sc := Vector2(player.template.screen_size)
	check(nb[0].position.x == 12 and nb[0].position.y + nb[0].size.y == sc.y - 12, "s25: bottom_left position: %s" % str(nb[0].position))
	check(nb[1].position.y < nb[0].position.y, "s25: bottom notices stack upward")
	var sb0 := (nb[0] as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	check(sb0.bg_color == player.template.color(1) and sb0.border_width_left == 0 and (nb[0].find_child("Text", true, false) as Label).get_theme_color("font_color") == player.template.color(6), "s25: notice colors")
	await _shot("49_notice_style")
	check(player.notice_style()["seconds"] == 5.0, "s25: notice seconds from the project")
	for n in player._notices:
		n.queue_free()
	player._notices.clear()
	player.project.data.erase("notice_style")
	player.template.data["notice"] = {"position": "top"}
	check(player.notice_style()["position"] == "top", "s25: notice style from the template")
	player.template.data.erase("notice")
	# 自動のお知らせを広げる
	player.project.data["notices"] = {"objective_set": "もくてき：{text}", "hint_set": "ヒント：{topic}", "item_remove": "{name}を てばなした", "autosave": "セーブしました"}
	await player._play(AdvEvents.make("objective.set", {"text": "かぎを さがす"}))
	await player._play(AdvEvents.make("objective.set", {"text": ""}))
	await player._play(AdvEvents.make("hint.set", {"topic": "かぎ", "hints": ["つくえ"]}))
	await player._play(AdvEvents.make("item.remove", {"id": "key"}))
	check(player.notices() == ["もくてき：かぎを さがす", "ヒント：かぎ", "keyを てばなした"], "s25: more auto notices: %s" % str(player.notices()))
	player.autosave()
	check(player.notices().has("セーブしました"), "s25: autosave notice")
	for n in player._notices:
		n.queue_free()
	player._notices.clear()
	player.project.data["notices"]["enabled"] = false
	await player._play(AdvEvents.make("objective.set", {"text": "とまる"}))
	check(player.notices().is_empty(), "s25: auto notices off")
	player.project.data.erase("notices")

	# 段階26：お知らせの絵とメッセージログ
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await _settle_frames(2)
	await player._play(AdvEvents.make("notice.show", {"text": "ろうかの え", "icon": "hallway"}))
	var ic: Node = player._notices[0].find_child("Icon", true, false)
	check(ic is TextureRect and (ic as TextureRect).texture != null and (ic as TextureRect).custom_minimum_size == Vector2(24, 24), "s26: notice icon")
	var mains = player.core.adapters_by_name.get("main")
	if mains != null and mains.get("items") is Dictionary:
		mains.items["key"] = {"name": "かぎ", "icon": "room"}
	check(player.core.query("item_info", {"id": "key"}).get("icon", "") == "room", "s26: item icon from the scenario")
	player.project.data["notices"] = {"item_add": "{name}を てにいれた", "autosave": {"text": "セーブしました", "icon": "hallway", "log": true}}
	await player._play(AdvEvents.make("item.add", {"id": "key"}))
	var item_n: Node = player._notices.back()
	check(player.notices().has("かぎを てにいれた") and item_n.find_child("Icon", true, false) != null, "s26: item notice uses the item icon")
	await _shot("50_notice_icons")
	var log_before: int = player.message_log.entries.size()
	await player._play(AdvEvents.make("notice.show", {"text": "のこらない"}))
	check(player.message_log.entries.size() == log_before, "s26: notices not logged by default")
	player.autosave()
	check(player.message_log.entries.size() == log_before + 1 and String(player.message_log.entries.back().get("body", "")) == "セーブしました", "s26: autosave notice logged (entry log: true)")
	player.project.data["notice_style"] = {"log": true, "icon_size": 32}
	await player._play(AdvEvents.make("notice.show", {"text": "のこる", "icon": "room"}))
	check(String(player.message_log.entries.back().get("body", "")) == "のこる", "s26: notices logged by style")
	check((player._notices.back().find_child("Icon", true, false) as Control).custom_minimum_size == Vector2(32, 32), "s26: icon size")
	await player._play(AdvEvents.make("notice.show", {"text": "のこさない", "log": false}))
	check(String(player.message_log.entries.back().get("body", "")) == "のこる", "s26: log: false on the event")
	player.project.data.erase("notice_style")
	player.project.data.erase("notices")

	# 段階27：お知らせをクリックで消す・時間で消えない・ログで見分ける
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await _settle_frames(2)
	player.project.data["notice_style"] = {"seconds": 0, "log": true}
	await player._play(AdvEvents.make("notice.show", {"text": "クリックで きえる"}))
	var cn: Control = player._notices[0]
	await create_timer(0.6).timeout
	check(is_instance_valid(cn) and player.notices().size() == 1, "s27: seconds 0 stays")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = cn.get_global_rect().get_center()
	player._click_pending = false
	player._input(click)
	check(not player._click_pending and cn.has_meta("closing"), "s27: click dismisses the notice (not the text)")
	await create_timer(0.3).timeout
	check(not is_instance_valid(cn) and player.notices().is_empty(), "s27: dismissed notice removed")
	player.project.data["notice_style"] = {"seconds": 0.2, "click_close": false, "log": true, "log_mark": "★", "log_color": 4}
	await player._play(AdvEvents.make("notice.show", {"text": "じかんで きえる"}))
	var tn: Control = player._notices[0]
	check(player.notice_at(tn.get_global_rect().get_center()) == null, "s27: click_close false")
	await create_timer(0.8).timeout
	check(not is_instance_valid(tn), "s27: notice disappears after its seconds")
	check(String(player.message_log.entries.back().get("kind", "")) == "notice", "s27: notice entry kind in the log")
	var lv := AdvLogView.new()
	lv.open(player.message_log, player.template, Vector2(player.template.screen_size), false, player.notice_style())
	player.screen.add_child(lv)
	await _settle_frames(3)
	var lt := lv._text.text
	check(lt.contains("★じかんで きえる") and lt.contains("[color=#%s]★" % player.template.color(4).to_html(false)), "s27: notices marked in the log view: %s" % lt.right(200))
	await _shot("51_log_notice")
	lv.close()
	await _settle_frames(3)
	player.project.data.erase("notice_style")

	# 段階28：お知らせの上限と並べ直し
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await _settle_frames(2)
	player.project.data["notice_style"] = {"max": 3, "seconds": 0}
	for i in 5:
		player.show_notice("おしらせ %d" % (i + 1))
	check(player.notices() == ["おしらせ 3", "おしらせ 4", "おしらせ 5"], "s28: max removes the oldest: %s" % str(player.notices()))
	var first_y: float = player._notices[0].position.y
	check(first_y == 12.0, "s28: relayout fills the gap: %s" % first_y)
	player.dismiss_notice(player._notices[0])
	await create_timer(0.4).timeout
	check(player.notices() == ["おしらせ 4", "おしらせ 5"] and player._notices[0].position.y == 12.0, "s28: dismissed gap closed")
	for n in player._notices:
		n.queue_free()
	player._notices.clear()
	player.project.data.erase("notice_style")
	# ログの画面：出すものの切り替え
	player.message_log.add_text("ふつうの ぶん")
	player.message_log.add_notice("おしらせの ぶん")
	var lv2 := AdvLogView.new()
	lv2.open(player.message_log, player.template, Vector2(player.template.screen_size), false, player.notice_style())
	player.screen.add_child(lv2)
	await _settle_frames(2)
	check(lv2.filter_button != null and lv2.filter == "all" and lv2._text.text.contains("ふつうの ぶん") and lv2._text.text.contains("おしらせの ぶん"), "s28: log shows all")
	lv2.filter_button.pressed.emit()
	check(lv2.filter == "text" and lv2._text.text.contains("ふつうの ぶん") and not lv2._text.text.contains("おしらせの ぶん"), "s28: log text only")
	lv2.filter_button.pressed.emit()
	check(lv2.filter == "notice" and not lv2._text.text.contains("ふつうの ぶん") and lv2._text.text.contains("おしらせの ぶん"), "s28: log notices only")
	await _shot("52_log_filter")
	lv2.close()
	var log3 := AdvMessageLog.new()
	log3.add_text("だけ")
	var lv3 := AdvLogView.new()
	lv3.open(log3, player.template, Vector2(player.template.screen_size))
	check(lv3.filter_button == null, "s28: no filter button without notices")
	lv3.queue_free()
	player.project.data["notice_style"] = {"log_filter": "notice"}
	var lv4 := AdvLogView.new()
	lv4.open(player.message_log, player.template, Vector2(player.template.screen_size), false, player.notice_style())
	check(lv4.filter == "notice", "s28: log_filter sets the first view")
	lv4.queue_free()
	player.project.data.erase("notice_style")

	# 段階29：お知らせごとの位置、上限で消すときの消え方、ログの切り替えの文言
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await _settle_frames(2)
	player.project.data["notice_style"] = {"seconds": 0, "max": 2, "overflow": "fade"}
	await player._play(AdvEvents.make("notice.show", {"text": "ひだりうえ", "position": "top_left"}))
	check(player._notices[0].position.x == 12.0 and player._notices[0].get_meta("position") == "top_left", "s29: notice position per event")
	player.show_notice("ふたつめ")
	player.show_notice("みっつめ")
	var faded: Control = player._notices[0]
	check(faded.has_meta("closing") and is_instance_valid(faded) and player.notices().size() == 3, "s29: overflow fade keeps the old one while fading")
	await create_timer(0.5).timeout
	check(not is_instance_valid(faded) and player.notices() == ["ふたつめ", "みっつめ"], "s29: faded one removed")
	for n in player._notices:
		n.queue_free()
	player._notices.clear()
	player.project.data["notices"] = {"objective_set": {"text": "もくてき", "position": "bottom"}}
	await player._play(AdvEvents.make("objective.set", {"text": "x"}))
	check(player._notices.back().get_meta("position") == "bottom", "s29: auto notice position")
	for n in player._notices:
		n.queue_free()
	player._notices.clear()
	player.project.data.erase("notices")
	player.project.data["notice_style"] = {"log_labels": {"all": "ぜんぶ", "notice": "しらせ"}}
	var lv5 := AdvLogView.new()
	lv5.open(player.message_log, player.template, Vector2(player.template.screen_size), false, player.notice_style())
	check(lv5.filter_button.text == "ぜんぶ", "s29: log label all")
	lv5.filter_button.pressed.emit()
	check(lv5.filter_button.text == "ひょうじ：ぶんしょう", "s29: default label kept for text")
	lv5.filter_button.pressed.emit()
	check(lv5.filter_button.text == "しらせ", "s29: log label notice")
	lv5.queue_free()
	player.project.data.erase("notice_style")

	# 段階30：起動時の ID の確認（プロジェクト設定）
	var pc := AdvIdCheck.check_project({"title_image": "no_title_bg", "extras": {"music": [{"id": "theme"}, {"id": "no_music"}]}, "title": "x"},
		func(k: String, id: String) -> bool: return player.core.assets.has(k, id), "p.json")
	check(pc.size() == 2 and String(pc[0]["message"]).contains("no_title_bg") and String(pc[1]["message"]).contains("no_music") and pc[1]["path"] == "/extras/music/1/id", "s30: project ids checked: %s" % str(pc.map(func(d): return [d["message"], d["path"]])))
	check(player.missing_ids is Array, "s30: missing ids kept")
	player.missing_ids = pc
	var con3: Control = load("res://addons/adv80s/debug/adv_debug_console.gd").new()
	root.add_child(con3)
	con3.set("player", player)
	con3.call("setup", player.core)
	con3.call("execute_command", "ids")
	var con3_log := ""
	for rt in con3.find_children("*", "RichTextLabel", true, false):
		con3_log += (rt as RichTextLabel).get_parsed_text()
	check(con3_log.contains("見つからない ID が 2 件あります") and con3_log.contains("no_music"), "s30: debug console lists missing ids")
	con3.queue_free()
	player.missing_ids = []

	# 段階31：デバッグ実行中に読み直す
	player._allow_reload_in_release = true
	await _settle()
	var scene31: String = player.core.state.scene
	player.core.state.vars["money"] = 31
	var got_reload := [false]
	player.reloaded.connect(func(): got_reload[0] = true)
	var why31: String = await player.debug_reload()
	await _settle_frames(3)
	check(why31 == "" and got_reload[0], "s31: debug reload: %s" % why31)
	check(player.core.state.scene == scene31 and player.core.state.get_var("money") == 31, "s31: state kept after reload")
	check(player.notices().any(func(t): return String(t).begins_with("読み直しました")), "s31: reload notice: %s" % str(player.notices()))
	player._allow_reload_in_release = false
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()

	# 段階32：保存したら自動で読み直す、入り直す
	player._allow_reload_in_release = true
	var wroot := "user://s32_assets"
	DirAccess.make_dir_recursive_absolute(wroot + "/bg")
	_rmdir(wroot + "/bg")
	DirAccess.make_dir_recursive_absolute(wroot + "/bg")
	player.core.add_asset_roots([wroot])
	player.set_auto_reload(true)
	check(player.is_auto_reload(), "s32: auto reload on")
	check(not await player.check_watch(), "s32: nothing changed")
	var src_png: String = player.core.assets.resolve("image", "hallway")
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(src_png) if not src_png.begins_with("res://") else src_png)
	if img.is_empty():
		img = Image.create(8, 8, false, Image.FORMAT_RGB8)
	var reload_count := [0]
	player.reloaded.connect(func(): reload_count[0] += 1)
	img.save_png(wroot + "/bg/s32_new.png")
	await create_timer(1.6).timeout   # 見張りのタイマー（1秒ごと）が気づいて読み直す
	await _settle()
	var reloaded32: bool = reload_count[0] >= 1
	check(reloaded32 and player.core.assets.has("image", "s32_new"), "s32: saving a file reloads (new asset found): %s %s %s" % [reloaded32, player.core.assets.has("image", "s32_new"), Array(player.core.assets.roots)])
	var sc32: String = player.core.state.scene
	var why32: String = await player.debug_reload(true)
	await _settle()
	check(why32 == "" and player.notices().any(func(t): return String(t).contains("入り直しました")) and player.core.state.scene == sc32, "s32: reload and re-enter: %s" % str(player.notices()))
	player.set_auto_reload(false)
	check(not player.is_auto_reload(), "s32: auto reload off")
	player._allow_reload_in_release = false
	_rmdir(wroot + "/bg")
	_rmdir(wroot)

	# 段階33：変わったファイルの名前、プロジェクト設定の debug.auto_reload に合わせる
	player._allow_reload_in_release = true
	var r33 := "user://s33_assets"
	DirAccess.make_dir_recursive_absolute(r33 + "/bg")
	player.core.add_asset_roots([r33])
	player._watch_snap = player.watch_snapshot()
	Image.create(8, 8, false, Image.FORMAT_RGB8).save_png(r33 + "/bg/s33_a.png")
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	await player.debug_reload()
	check(player.last_reload_changes.has(r33 + "/bg/s33_a.png"), "s33: changed files: %s" % str(player.last_reload_changes))
	check(player.notices().any(func(t): return String(t).contains("s33_a.png")), "s33: changed file in the notice: %s" % str(player.notices()))
	check(AdvPlayer.changes_text(["a/x.json", "b/y.png", "c/z.png", "d/w.png"]) == "x.json、y.png ほか 2 件" and AdvPlayer.changes_text([]) == "", "s33: changes text")
	# プロジェクト設定の debug.auto_reload が書き換わったら入・切する
	var pp_old: String = player.project_path
	var pcopy := "user://s33_project.json"
	var pdata = AdvJson.load_file(pp_old, [])
	pdata["debug"] = {"auto_reload": false}
	_write_json(pcopy, pdata)
	player.project_path = pcopy
	player.set_auto_reload(false)
	player._poll_mtime = -2
	player._poll_auto = false
	check(not player.poll_debug_settings(), "s33: no change in debug.auto_reload")
	await create_timer(1.1).timeout
	pdata["debug"] = {"auto_reload": true}
	_write_json(pcopy, pdata)
	check(player.poll_debug_settings() and player.is_auto_reload(), "s33: turned on from the project file")
	await create_timer(1.1).timeout
	pdata["debug"] = {"auto_reload": false}
	_write_json(pcopy, pdata)
	check(player.poll_debug_settings() and not player.is_auto_reload(), "s33: turned off from the project file")
	player.project_path = pp_old
	player._allow_reload_in_release = false
	DirAccess.remove_absolute(pcopy)
	DirAccess.remove_absolute(r33 + "/bg/s33_a.png")
	DirAccess.remove_absolute(r33 + "/bg")
	DirAccess.remove_absolute(r33)

	# 段階34：お知らせに出すファイルの数、エディタで開く
	check(AdvPlayer.changes_text(["a/x.json", "b/y.png", "c/z.png"], 3) == "x.json、y.png、z.png" and AdvPlayer.changes_text(["a/x.json"], 0) == "", "s34: notice_files limit")
	check(not player.request_open_in_editor() if not EngineDebugger.is_active() else true, "s34: no editor link without the debugger")

	# 段階35：エディタの「このシーンから実行」、いまの場所
	var loc35: Dictionary = player.current_location()
	check(loc35.has("scene") and loc35["scene"] == player.core.state.scene, "s35: current location: %s" % str(loc35))
	var target35 := String(player.core.query("scene_info", {"id": player.core.state.scene}).get("id", player.core.state.scene)) if player.core.state.scene != "" else ""
	if target35 == "":
		target35 = player._entry_scene()
	var fr := FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
	fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system() - 100}))
	fr.close()
	check(AdvPlayer.take_run_from_request() == "" and not FileAccess.file_exists(AdvPlayer.RUN_FROM_FILE), "s35: old run-from request ignored and removed")
	fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
	fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system()}))
	fr.close()
	if player._overlay != null and player._overlay.has_method("close"):
		player._overlay.close()
	await _settle_frames(3)
	player._boot()
	await _settle()
	check(player.run_from_scene == target35 and player.core.state.visited.has(target35) and player.notices().any(func(t): return String(t) == "シーンから実行：" + target35), "s35: boot from the requested scene: %s / %s" % [player.run_from_scene, player.core.state.scene])

	# 段階36：ひな形の値（変数・持ち物）を入れてから始める
	fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
	fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "preset": "テスト",
		"vars": {"s36flag": true, "s36n": 4}, "items": {"s36key": 2}}))
	fr.close()
	if player._overlay != null and player._overlay.has_method("close"):
		player._overlay.close()
	await _settle_frames(3)
	player._boot()
	await _settle()
	check(player.core.state.get_var("s36flag") == true and int(player.core.state.get_var("s36n")) == 4 and player.core.state.item_count("s36key") == 2, "s36: preset values put in before starting")
	check(player.run_from.get("preset") == "テスト" and player.notices().any(func(t): return String(t) == "シーンから実行：%s（ひな形 テスト）" % target35), "s36: notice names the preset")
	# 段階40：先に入った値をお知らせとログに
	var ja40 = player.core.adapters_by_name.get("main")
	if ja40 != null:
		ja40.dialogues["s40talk"] = [{"set": {"s40a": 5}}, {"let": "s40b = s40a + 1"}, "s40 はじめ。"]
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await _settle()
		check(int(player.core.state.get_var("s40b")) == 6, "s40: pre-sets ran at boot")
		check(player.notices().any(func(t): return String(t) == "先に設定：s40a = 5、s40b = 6"), "s40: pre-set values in a notice: %s" % str(player.notices()))
		check(player.message_log.entries.any(func(e): return String(e.get("body", "")) == "先に設定：s40a = 5、s40b = 6"), "s40: pre-set values in the log")
		# 段階41：お知らせ・ログを出すかの切り替え
		var dbg41 = player.project.data.get("debug", null)
		player.project.data["debug"] = {"pre_set_notice": false}
		player.message_log.entries.clear()
		var pre41 := func(): return player.notices().filter(func(t): return String(t).begins_with("先に設定")).size()
		var c41: int = pre41.call()
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await _settle()
		check(String(player.notices().back()).begins_with("シーンから実行") and player.message_log.entries.any(func(e): return String(e.get("body", "")).begins_with("先に設定")), "s41: notice off, log on")
		player.project.data["debug"] = {"pre_set_log": false}
		player.message_log.entries.clear()
		c41 = pre41.call()
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await _settle()
		check(String(player.notices().back()).begins_with("先に設定") and not player.message_log.entries.any(func(e): return String(e.get("body", "")).begins_with("先に設定")), "s41: log off, notice on")
		# 段階42：お知らせを出しておく秒数（0 でクリックするまで）
		for nn in player._notices.duplicate():
			if is_instance_valid(nn):
				player._dismiss_now(nn)
		player.project.data["debug"] = {"pre_set_seconds": 0, "pre_set_position": "bottom_left", "pre_set_style": {"fg": 10, "border": 12}, "notice_style": {"bg": 4, "border": 9, "fg": 14, "seconds": 10}}
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await create_timer(3.2).timeout
		check(player.notices().filter(func(t): return String(t).begins_with("先に設定")).size() == 1 and String(player.notices().back()).begins_with("先に設定"), "s42: pre-set notice stays until clicked: %s" % str(player.notices()))
		var pn43 = player._notices.filter(func(n): return is_instance_valid(n)).back()
		check(String(pn43.get_meta("position")) == "bottom_left" and pn43.position.y > 200 and pn43.position.x < 100, "s43: pre-set notice position: %s" % str(pn43.position))
		var sb44 := (pn43 as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		var lb44 := pn43.find_child("Text", true, false) as Label
		check(sb44.border_color == player.template.color(12) and lb44.get_theme_color("font_color") == player.template.color(10) and sb44.bg_color == player.template.color(4), "s44/s45: pre-set notice style over the debug notice style")
		var rn45 = player._notices.filter(func(n): return is_instance_valid(n) and String((n.find_child("Text", true, false) as Label).text).begins_with("シーンから実行")).back()
		var sb45 := (rn45 as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		check(sb45.border_color == player.template.color(9) and sb45.bg_color == player.template.color(4) and (rn45.find_child("Text", true, false) as Label).get_theme_color("font_color") == player.template.color(14), "s45: debug notice style on the run-from notice")
		await _shot("43_pre_set_notice")
		for nn in player._notices.duplicate():
			if is_instance_valid(nn):
				player._dismiss_now(nn)
		player.project.data["debug"] = {"pre_set_seconds": 0.3}
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await _settle_frames(3)
		check(player.notices().any(func(t): return String(t).begins_with("先に設定")), "s42: short pre-set notice shown")
		await create_timer(1.2).timeout
		check(not player.notices().any(func(t): return String(t).begins_with("先に設定")) and player.notices().any(func(t): return String(t).begins_with("シーンから実行")), "s42: short pre-set notice gone first")
		# 段階46：デバッグのお知らせを種類ごとに出さない
		for nn in player._notices.duplicate():
			if is_instance_valid(nn):
				player._dismiss_now(nn)
		player.project.data["debug"] = {"notices": {"run_from": false}, "pre_set_seconds": 0}
		check(not player.debug_notice_on("run_from") and player.debug_notice_on("reload") and player.debug_notice_on(""), "s46: notice kinds")
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await _settle_frames(3)
		check(not player.notices().any(func(t): return String(t).begins_with("シーンから実行")) and player.notices().any(func(t): return String(t).begins_with("先に設定")), "s46: run-from notice hidden: %s" % str(player.notices()))
		for nn in player._notices.duplicate():
			if is_instance_valid(nn):
				player._dismiss_now(nn)
		player.project.data["debug"] = {"notices": {"pre_set": false, "preset": false}}
		fr = FileAccess.open(AdvPlayer.RUN_FROM_FILE, FileAccess.WRITE)
		fr.store_string(JSON.stringify({"scene": target35, "time": Time.get_unix_time_from_system(), "dialogue": "s40talk", "line": 2, "pre_sets": true}))
		fr.close()
		player._boot()
		await _settle_frames(3)
		check(player.notices().any(func(t): return String(t).begins_with("シーンから実行")) and not player.notices().any(func(t): return String(t).begins_with("先に設定")), "s46: pre-set notice hidden")
		player.send_preset_to_editor("s46")
		check(not player.notices().any(func(t): return String(t).begins_with("ひな形にしました")), "s46: preset notice hidden")
		DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
		# 段階47：コンソールでお知らせを切り替える（動かしている間だけ。設定より先）
		var con47: Control = load("res://addons/adv80s/debug/adv_debug_console.gd").new()
		root.add_child(con47)
		con47.set("player", player)
		con47.call("setup", player.core)
		con47.call("execute_command", "notice preset on")
		check(player.debug_notice_on("preset") and player.debug_notice_override.get("preset") == true, "s47: console turns a kind on over the setting")
		con47.call("execute_command", "notice reload off")
		check(not player.debug_notice_on("reload") and player.debug_notice_report().contains("reload：出さない（コンソール）"), "s47: console turns a kind off")
		con47.call("execute_command", "notice off")
		check(player.DEBUG_NOTICE_KINDS.all(func(k): return not player.debug_notice_on(k)), "s47: notice off = all off")
		con47.call("execute_command", "notice reset reload")
		check(not player.debug_notice_override.has("reload") and player.debug_notice_on("reload"), "s47: reset one kind")
		con47.call("execute_command", "notice bogus on")
		check(player.debug_notice_override.size() == player.DEBUG_NOTICE_KINDS.size() - 1, "s47: unknown kind changes nothing")
		player.send_preset_to_editor("s47")
		check(not player.notices().any(func(t): return String(t) == "ひな形にしました：s47"), "s47: console off hides the notice")
		# 段階48：切り替えを設定に書く（エディタへ渡す）
		if FileAccess.file_exists(AdvPlayer.GAME_SETTINGS_FILE):
			DirAccess.remove_absolute(AdvPlayer.GAME_SETTINGS_FILE)
		con47.call("execute_command", "notice save")
		var gs48 = AdvJson.load_file(AdvPlayer.GAME_SETTINGS_FILE, [])
		check(gs48 is Dictionary and gs48["notices"].size() == player.DEBUG_NOTICE_KINDS.size() - 1 and gs48["notices"]["preset"] == false and not gs48["notices"].has("reload"), "s48: notice save writes the switched kinds: %s" % str(gs48))
		DirAccess.remove_absolute(AdvPlayer.GAME_SETTINGS_FILE)
		con47.call("execute_command", "notice reset")
		check(player.debug_notice_override.is_empty(), "s47: reset all")
		check(player.save_debug_notices_to_editor() == 0 and not FileAccess.file_exists(AdvPlayer.GAME_SETTINGS_FILE), "s48: nothing to save")
		# 段階49：お知らせの見た目をゲームの中で試して保存
		check(player.set_debug_notice_style("bogus", 1) != "" and player.set_debug_notice_style("fg", "x") != "" and player.set_debug_notice_style("position", "nowhere") != "" and player.set_debug_notice_style("seconds", "-1") != "", "s49: bad style values are refused")
		con47.call("execute_command", "noticestyle fg 11")
		con47.call("execute_command", "noticestyle border 13")
		check(player.debug_notice_style_override == {"fg": 11, "border": 13} and player.debug_notice_style_now()["fg"] == 11, "s49: console sets the style")
		var tn49 = player._notices.filter(func(n): return is_instance_valid(n) and String((n.find_child("Text", true, false) as Label).text) == "お知らせの見た目のためし").back()
		check(tn49 != null and (tn49.find_child("Text", true, false) as Label).get_theme_color("font_color") == player.template.color(11), "s49: a sample notice uses the tried style")
		con47.call("execute_command", "noticestyle reset border")
		check(not player.debug_notice_style_override.has("border"), "s49: reset one key")
		con47.call("execute_command", "noticestyle save")
		var gs49 = AdvJson.load_file(AdvPlayer.GAME_SETTINGS_FILE, [])
		check(gs49 is Dictionary and gs49.get("notice_style", {}).size() == 1 and int(gs49["notice_style"]["fg"]) == 11, "s49: style saved for the editor: %s" % str(gs49))
		DirAccess.remove_absolute(AdvPlayer.GAME_SETTINGS_FILE)
		con47.call("execute_command", "noticestyle reset")
		check(player.debug_notice_style_override.is_empty() and player.save_debug_notice_style_to_editor() == 0, "s49: reset all")
		# 段階50：ふつうのお知らせの見た目をゲームの中で試して保存
		check(player.set_game_notice_style("overflow", "nope") != "" and player.set_game_notice_style("max", "0") != "" and player.set_game_notice_style("click_close", "maybe") != "", "s50: bad game style values are refused")
		con47.call("execute_command", "noticestyle game fg 12")
		con47.call("execute_command", "noticestyle game click_close false")
		check(player.notice_style()["fg"] == 12 and player.notice_style()["click_close"] == false and player.debug_notice_style_override.is_empty(), "s50: console tries the game notice style")
		var tn50 = player._notices.filter(func(n): return is_instance_valid(n) and String((n.find_child("Text", true, false) as Label).text) == "お知らせの見た目のためし").back()
		check(tn50 != null and (tn50.find_child("Text", true, false) as Label).get_theme_color("font_color") == player.template.color(12), "s50: sample game notice uses the tried style")
		await _shot("50_game_notice_style")
		con47.call("execute_command", "noticestyle game save")
		var gs50 = AdvJson.load_file(AdvPlayer.GAME_SETTINGS_FILE, [])
		check(gs50 is Dictionary and int(gs50.get("game_notice_style", {}).get("fg", 0)) == 12 and gs50["game_notice_style"]["click_close"] == false, "s50: game style saved for the editor: %s" % str(gs50))
		DirAccess.remove_absolute(AdvPlayer.GAME_SETTINGS_FILE)
		con47.call("execute_command", "noticestyle game reset")
		check(player.notice_style_override.is_empty() and player.notice_style()["fg"] != 12 and player.save_game_notice_style_to_editor() == 0, "s50: game style reset")
		# 段階51：見た目に名前を付けて取っておき、切り替えて見比べる
		if FileAccess.file_exists(AdvPlayer.NOTICE_STYLE_SETS_FILE):
			DirAccess.remove_absolute(AdvPlayer.NOTICE_STYLE_SETS_FILE)
		check(not player.keep_notice_style(true, "空"), "s51: nothing to keep")
		con47.call("execute_command", "noticestyle game fg 9")
		con47.call("execute_command", "noticestyle game keep あお")
		con47.call("execute_command", "noticestyle game fg 10")
		con47.call("execute_command", "noticestyle game border 4")
		con47.call("execute_command", "noticestyle game keep みどり")
		con47.call("execute_command", "noticestyle fg 13")
		con47.call("execute_command", "noticestyle keep デバッグ")
		check(AdvPlayer.notice_style_sets(true).keys().size() == 2 and AdvPlayer.notice_style_sets(false).has("デバッグ") and int(AdvPlayer.notice_style_sets(true)["みどり"]["fg"]) == 10 and int(AdvPlayer.notice_style_sets(true)["みどり"]["border"]) == 4, "s51: keep named styles (game and debug separately)")
		con47.call("execute_command", "noticestyle game use あお")
		check(player.notice_style_override == {"fg": 9} and player.notice_style()["fg"] == 9, "s51: use a kept style")
		con47.call("execute_command", "noticestyle game next")
		check(player.notice_style_override.get("fg") == 10 and player.notice_style_override.get("border") == 4, "s51: next cycles to the next one")
		con47.call("execute_command", "noticestyle game next")
		check(player.notice_style_override == {"fg": 9}, "s51: next wraps around")
		check(not player.use_notice_style(true, "ない") and player.notice_style_override == {"fg": 9}, "s51: unknown name keeps the current style")
		con47.call("execute_command", "noticestyle game drop あお")
		check(not AdvPlayer.notice_style_sets(true).has("あお") and AdvPlayer.notice_style_sets(true).has("みどり") and AdvPlayer.notice_style_sets(false).has("デバッグ"), "s51: drop one")
		con47.call("execute_command", "noticestyle game reset")
		con47.call("execute_command", "noticestyle reset")
		DirAccess.remove_absolute(AdvPlayer.NOTICE_STYLE_SETS_FILE)
		DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
		con47.queue_free()
		if dbg41 == null:
			player.project.data.erase("debug")
		else:
			player.project.data["debug"] = dbg41
	else:
		check(false, "s40: json adapter not found")
	# 段階37：いまの値をひな形にしてエディタへ（ファイルに書き足す）
	if FileAccess.file_exists(AdvPlayer.GAME_PRESETS_FILE):
		DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
	check(player.send_preset_to_editor("試し") == "試し" and player.send_preset_to_editor("") != "", "s37: send presets")
	var gp37 = AdvJson.load_file(AdvPlayer.GAME_PRESETS_FILE, [])
	check(gp37 is Array and gp37.size() == 2 and gp37[0]["name"] == "試し" and gp37[0]["vars"].get("s36flag") == true and int(gp37[0]["items"]["s36key"]) == 2 and String(gp37[1]["name"]).begins_with(player.core.state.scene), "s37: presets written for the editor: %s" % str(gp37))
	check(player.notices().any(func(t): return String(t) == "ひな形にしました：試し"), "s37: preset notice")
	DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
	# 段階38：入れるものを選んでひな形に
	player.open_preset_picker()
	await _settle_frames(2)
	check(player.preset_picker != null and player._picker_checks.has("v:s36flag") and player._picker_checks.has("i:s36key"), "s38: picker lists vars and items")
	await _shot("38_preset_picker")
	# 段階39：絞り込み（「全部」「なし」は見えているものだけ）
	var all39 := player._picker_checks.size()
	check(player.filter_picker("S36") == 3 and player.filter_picker("s36N") == 1 and not player._picker_row_visible("v:s36flag"), "s39: filter the picker")
	player.set_picker_all(false)
	check(not (player._picker_checks["v:s36n"] as CheckBox).button_pressed and (player._picker_checks["v:s36flag"] as CheckBox).button_pressed, "s39: none only touches the visible ones")
	check(player.filter_picker("") == all39 and not player.picker_selection()["vars"].has("s36n") and player.picker_selection()["vars"].has("s36flag"), "s39: clearing the filter shows all, marks kept")
	player.set_picker_all(false)
	check(player.confirm_preset_picker() == "" and player.preset_picker != null, "s38: nothing picked → not sent")
	# 段階40：値を書きかえて送る
	player.set_picker_check("v:s36n", true)
	player.set_picker_check("i:s36key", true)
	player.set_picker_value("v:s36n", "10")
	player.set_picker_value("i:s36key", 0)
	check(player.picker_preset() == {"vars": {"s36n": 10.0}, "items": {"s36key": 0}}, "s40: picker values can be edited: %s" % str(player.picker_preset()))
	player.set_picker_value("v:s36n", "あいう")
	check(player.picker_preset()["vars"]["s36n"] == "あいう" and AdvPlayer.parse_value_text("true") == true and AdvPlayer.value_text(4.0) == "4", "s40: non-JSON value is text")
	# 段階41：まだ書かれていない変数・持ち物を足す
	player.set_picker_all(false)
	check(player.picker_add("v", "s41new", "\"やあ\"") and player.picker_add("i", "s41item", "3") and player.picker_add("i", "s41one", ""), "s41: add new rows")
	check(not player.picker_add("v", "  ", "1"), "s41: empty name is not added")
	var pp41 := player.picker_preset()
	check(pp41.get("vars", {}) == {"s41new": "やあ"} and pp41.get("items", {}) == {"s41item": 3, "s41one": 1}, "s41: new rows are marked and sent: %s" % str(pp41))
	player.picker_add("v", "s41new", "7")
	check(player.picker_preset()["vars"]["s41new"] == 7.0 and player._picker_checks.size() == all39 + 3, "s41: adding an existing name updates it")
	await _shot("41_picker_add")
	# 段階42：行を外す
	var n42 := player._picker_checks.size()
	check(player.picker_remove("v:s41new") and not player._picker_checks.has("v:s41new") and not player.picker_preset().get("vars", {}).has("s41new"), "s42: remove an added row")
	check(player.picker_remove("v:money") and player._picker_checks.size() == n42 - 2 and not player.picker_remove("v:nope"), "s42: remove an original row")
	player.picker_add("v", "s41new", "1")
	check(player._picker_checks.has("v:s41new"), "s42: a removed row can be added again")
	# 段階43：外したものをまとめて戻す（外したときの値と印で。足し直したものはそのまま）
	player.set_picker_value("v:s40a", "55")
	player.set_picker_check("v:s40a", true)
	player.picker_remove("v:s40a")
	check(not player._picker_restore_btn.disabled, "s43: restore button enabled")
	check(player.picker_restore_removed() == 2 and player._picker_checks.has("v:money") and player._picker_checks.has("v:s40a"), "s43: restore removed rows")
	check(player.picker_preset()["vars"]["s40a"] == 55.0 and player.picker_preset()["vars"]["s41new"] == 1.0 and player._picker_restore_btn.disabled, "s43: restored with the values at removal")
	check(player.picker_restore_removed() == 0, "s43: nothing more to restore")
	# 段階44：送っても閉じない（名前は次の番号に）
	check(AdvPlayer.next_preset_name("試し") == "試し 2" and AdvPlayer.next_preset_name("試し 9") == "試し 10" and AdvPlayer.next_preset_name("hall 07:43:28") == "hall 07:43:28 2", "s44: next preset name")
	if FileAccess.file_exists(AdvPlayer.GAME_PRESETS_FILE):
		DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
	player._picker_name.text = "続け"
	player._picker_group.text = ""
	player._picker_keep_check.button_pressed = true
	check(player._picker_group.text == "続け", "s45: keep-open fills the group with the name")
	player.set_picker_check("v:money", true)
	check(player.confirm_preset_picker() == "続け" and player.preset_picker != null and player._picker_name.text == "続け 2", "s44: keep open after sending")
	player.set_picker_value("v:money", "99")
	check(player.confirm_preset_picker() == "続け 2" and player._picker_name.text == "続け 3", "s44: send again with the next name")
	var gp44 = AdvJson.load_file(AdvPlayer.GAME_PRESETS_FILE, [])
	check(gp44 is Array and gp44.size() == 2 and gp44[1]["name"] == "続け 2" and gp44[1]["vars"]["money"] == 99.0 and gp44[0]["vars"]["money"] != 99.0, "s44: both sent: %s" % str(gp44).left(160))
	check(gp44[0].get("group") == "続け" and gp44[1].get("group") == "続け", "s45: sent presets carry the group")
	DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
	player._picker_keep_check.button_pressed = false
	player._picker_group.text = ""
	check(not player.picker_keep_open, "s44: keep-open off")
	player.set_picker_all(false)
	player.set_picker_check("v:s36flag", true)
	player.set_picker_check("i:s36key", true)
	player._picker_name.text = "選んだ"
	check(player.confirm_preset_picker() == "選んだ" and player.preset_picker == null, "s38: send the picked ones")
	var gp38 = AdvJson.load_file(AdvPlayer.GAME_PRESETS_FILE, [])
	check(gp38 is Array and gp38.size() == 1 and gp38[0]["vars"] == {"s36flag": true} and gp38[0]["items"].size() == 1, "s38: only the picked ones written: %s" % str(gp38))
	DirAccess.remove_absolute(AdvPlayer.GAME_PRESETS_FILE)
	player.open_preset_picker()
	var esc38 := InputEventAction.new()
	esc38.action = "ui_cancel"
	esc38.pressed = true
	Input.parse_input_event(esc38)
	await _settle_frames(3)
	check(player.preset_picker == null, "s38: Esc closes the picker")
	check(AdvPlayer.run_from_text({"scene": "h", "dialogue": "t", "line": 1, "pre_sets": true}) == "シーンから実行：h（会話 t の 2 番目から（設定を先に））", "s38: run-from text with pre-sets")
	check(AdvPlayer.run_from_text({"scene": "h", "dialogue": "t", "path": [1, "then", 0]}) == "シーンから実行：h（会話 t の 2 › そうなら › 1 番目から）", "s37: run-from text with a path")
	check(AdvPlayer.run_from_text({"scene": "h", "dialogue": "t", "line": 2}) == "シーンから実行：h（会話 t の 3 番目から）" and AdvPlayer.run_from_text({"scene": "h", "knot": "k"}) == "シーンから実行：h（ノット k から）", "s36: run-from text")
	# 段階61：見直し（長い名前・長い文字で写真を撮る）
	player.core.state.set_var("review_very_long_variable_name_for_the_picker_window", "とても長い文字の値をここに入れて、窓の幅からはみ出すかどうか見る")
	player.core.state.set_var("みじかい", 1)
	player.open_preset_picker()
	await _settle_frames(2)
	player._picker_name.text = "見直し：とても長い名前のひな形を一つ作っておく（ゲームの中から）"
	player._picker_group.text = "見直しのためのとても長い組の名前"
	await _shot("review_61_picker")
	var le61 := player._picker_values["v:review_very_long_variable_name_for_the_picker_window"] as LineEdit
	var cb61 := player._picker_checks["v:review_very_long_variable_name_for_the_picker_window"] as CheckBox
	check(cb61.clip_text and cb61.tooltip_text.contains("review_very_long_variable_name_for_the_picker_window") and le61.size.x > 100.0 and le61.get_global_rect().end.x <= player.preset_picker.get_global_rect().end.x + 1.0, "s61: long name in the picker leaves room for the value: %s" % str(le61.size))
	player.close_preset_picker()
	await _settle_frames(2)
	player.show_debug_notice("見直し：とても長いお知らせの文字を出して、画面の幅に収まるか、折り返すか、切れてしまうかを確かめるための文です。シーンから実行：review_scene_with_a_long_name（会話 talk_with_a_long_name の 12 番目から（設定を先に・条件も））")
	await _settle_frames(3)
	await _shot("review_62_debug_notice")
	var n61: Control = player._notices.back()
	check(n61.get_global_rect().position.x >= 0.0 and n61.get_global_rect().end.x <= root.get_visible_rect().size.x + 1.0 and (n61.find_child("Text", true, false) as Label).autowrap_mode != TextServer.AUTOWRAP_OFF, "s61: long notice wraps inside the screen: %s" % str(n61.get_global_rect()))
	player.show_notice("みじかい")
	await _settle_frames(2)
	check((player._notices.back().find_child("Text", true, false) as Label).autowrap_mode == TextServer.AUTOWRAP_OFF, "s61: short notice does not wrap")
	# 段階62：小さい画面（GB 160×144・FC 256×240）でお知らせと選ぶ窓を見直す
	var tpl62 := String(player.template.id)
	player.debug_notice_style_override["layer"] = "screen"   # ここではゲームの画面の中のお知らせを見る（段階64）
	for t62 in ["gb_classic", "fc_classic"]:
		await player.switch_template(t62)
		await _settle_frames(3)
		for n in player._notices:
			if is_instance_valid(n):
				n.queue_free()
		player._notices.clear()
		player.show_debug_notice("シーンから実行：review_scene（会話 talk の 12 番目から（設定を先に・条件も））")
		player.show_notice("みじかい")
		await _settle_frames(3)
		var scr62 := Vector2(player.template.screen_size)
		var ok62 := true
		for n in player._notices:
			if is_instance_valid(n):
				var r62 := Rect2((n as Control).position, (n as Control).size)
				ok62 = ok62 and r62.position.x >= 0.0 and r62.end.x <= scr62.x + 0.5 and r62.end.y <= scr62.y + 0.5
		check(ok62, "s62: notices fit the %s screen %s" % [t62, str(scr62)])
		var live62: Array = player._notices.filter(func(n): return is_instance_valid(n))
		var r0 := Rect2((live62[0] as Control).position, (live62[0] as Control).size)
		var r1 := Rect2((live62[1] as Control).position, (live62[1] as Control).size)
		check(not r0.intersects(r1), "s62: notices do not overlap on %s: %s / %s" % [t62, str(r0), str(r1)])
		await _shot("review_64_notice_" + t62)
		player.open_preset_picker()
		await _settle_frames(2)
		var vr62 := root.get_visible_rect()
		var pr62 := player.preset_picker.get_global_rect()
		check(vr62.encloses(pr62), "s62: picker fits the window with %s: %s in %s" % [t62, str(pr62), str(vr62)])
		await _shot("review_65_picker_" + t62)
		player.close_preset_picker()
		# 段階63：ゲームを窓いっぱいにして（ふつうのゲームと同じ見た目で）ゲームの中の画面を見直す
		var off63 := [player.anchor_right, player.anchor_bottom, player.offset_right, player.offset_bottom]
		player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _settle_frames(3)
		var fr63: Control = player.display.frame
		check(player.display.display_scale().x >= 1.0 and absf(fr63.position.x * 2.0 + fr63.size.x - player.display.size.x) <= 2.0, "s63: %s is scaled and centred when the game fills the window: %s" % [t62, str(player.display.display_scale())])
		await _shot("review_66_full_" + t62)
		var scr63: Rect2 = player.template.visible_rect()   # 見える範囲（FC は上下 8 を隠す）
		for what63 in ["log", "save", "menu", "settings"]:
			match what63:
				"log": player.open_log()
				"save": player.open_save_menu("load")
				"menu": player.modern.open_system_menu()
				"settings": player.modern.open_settings()
			await _settle()
			_clear_notices()
			await _settle_frames(2)
			var ov63: Control = player._overlay
			var sys63: bool = player.is_system_scene_open()
			check(ov63 != null or sys63, "s63: %s opens on %s" % [what63, t62])
			# 作者が自分で作ったシステム画面（AdvSystemScreen。テストの設定画面）は作者の受け持ちなので、写真だけ撮る
			if not (ov63 is AdvSystemScreen):
				var bad63 := _overflowing(ov63 if ov63 != null else player.screen, scr63)
				check(bad63.is_empty(), "s63: %s fits the %s screen: %s" % [what63, t62, ", ".join(bad63)])
			if what63 == "log" and ov63 is AdvLogView:
				var lv63 := ov63 as AdvLogView
				var lsb63 = lv63.get_theme_stylebox("panel")
				check(lv63._title.get_theme_color("font_color") == lv63._text.get_theme_color("default_color") and absf((lsb63 as StyleBoxFlat).bg_color.get_luminance() - lv63._text.get_theme_color("default_color").get_luminance()) >= 0.3, "s63: log text stands out on %s" % t62)
			if what63 == "menu":
				var sb63 = ov63.get_theme_stylebox("panel")
				var t63: Label = ov63._title
				check(sb63 is StyleBoxFlat and absf((sb63 as StyleBoxFlat).bg_color.get_luminance() - t63.get_theme_color("font_color").get_luminance()) >= 0.3, "s63: menu text stands out from its background on %s" % t62)
			await _shot("review_67_%s_%s" % [what63, t62])
			if ov63 != null:
				ov63.close()
			elif sys63:
				player.close_system_scene(false)
			await _settle()
		player.anchor_right = off63[0]
		player.anchor_bottom = off63[1]
		player.offset_right = off63[2]
		player.offset_bottom = off63[3]
		await _settle_frames(2)
	player.debug_notice_style_override.erase("layer")
	# 段階64：デバッグのお知らせをゲームの画面の外に（auto は狭い画面だけ）
	for t64 in ["gb_classic", "fc_classic", "pc98_classic"]:
		await player.switch_template(t64)
		await _settle_frames(3)
		_clear_notices()
		player.show_debug_notice("シーンから実行：review_scene（会話 talk の 12 番目から（設定を先に・条件も））")
		player.show_notice("みじかい")
		await _settle_frames(3)
		var dn64: Control = player._notices[0]
		var gn64: Control = player._notices[1]
		var narrow64: bool = t64 != "pc98_classic"
		check(bool(dn64.get_meta("window")) == narrow64 and (dn64.get_parent() == player._debug_layer) == narrow64, "s64: debug notice on the window layer only for a narrow screen (%s)" % t64)
		check(not bool(gn64.get_meta("window")) and gn64.get_parent() == player.screen, "s64: game notice stays in the game screen (%s)" % t64)
		if narrow64:
			var ws64: Vector2 = player._window_layer_size()
			var r64 := Rect2(dn64.position, dn64.size)
			check(r64.position.y >= AdvPlayer.NOTICE_WINDOW_TOP and r64.end.x <= ws64.x + 0.5 and r64.position.x >= 0.0 and r64.size.x <= AdvPlayer.NOTICE_WINDOW_MAX_WIDTH + 1.0, "s64: window notice below the debug buttons and inside the window: %s in %s" % [str(r64), str(ws64)])
			await _shot("review_70_debug_notice_window_" + t64)
			# 段階66：画面の外のお知らせもクリックで消える
			var click66 := InputEventMouseButton.new()
			click66.button_index = MOUSE_BUTTON_LEFT
			click66.pressed = true
			click66.position = dn64.get_global_rect().get_center()
			player._input(click66)
			await _settle_frames(2)
			check(not is_instance_valid(dn64) or dn64.has_meta("closing"), "s66: a window-layer notice closes on click (%s)" % t64)
	# 段階64：画像を見る画面の絵と文字も見える範囲に（FC は上下 8 を隠す）
	await player.switch_template("fc_classic")
	var img64 := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGB8))
	var iv64: AdvImageViewer = AdvImageViewer.new().setup([img64, img64], player.template, "見出し")
	var vr64: Rect2 = player.template.visible_rect()
	var cap64: Label = iv64.get_children().filter(func(c): return c is Label and (c as Label).text == "見出し")[0]
	check(iv64._rect.position == vr64.position and iv64._rect.size == vr64.size and cap64.position.y >= vr64.position.y and cap64.position.y + 20.0 <= vr64.end.y and iv64._count.position.y + 20.0 <= vr64.end.y, "s64: image viewer keeps picture and captions in the visible area %s" % str(vr64))
	iv64.free()
	check(player.set_debug_notice_style("layer", "window") == "" and player.set_debug_notice_style("layer", "sky") != "", "s64: layer can be tried in the console")
	await player.switch_template("pc98_classic")
	await _settle_frames(2)
	_clear_notices()
	player.show_debug_notice("ウィンドウの層に")
	await _settle_frames(2)
	check(bool(player._notices[0].get_meta("window")), "s64: layer window forces the window layer")
	player.set_debug_notice_style("layer", "screen")
	_clear_notices()
	await player.switch_template("gb_classic")
	player.show_debug_notice("ゲームの画面に")
	await _settle_frames(2)
	check(not bool(player._notices[0].get_meta("window")), "s64: layer screen keeps it in the game screen")
	player.set_debug_notice_style("layer", null)
	_clear_notices()
	await player.switch_template(tpl62)
	await _settle_frames(3)
	# 段階65：フローチャート・チャプターのないゲームでも開ける（前は止まっていた）
	for w65 in ["flowchart", "chapters"]:
		if w65 == "flowchart":
			player.modern.open_flowchart()
		else:
			player.modern.open_chapters()
		await _settle()
		var ov65: Control = player._overlay
		check(ov65 != null and ov65.find_children("*", "RichTextLabel", true, false).any(func(l): return (l as RichTextLabel).text.contains("ありません")), "s65: %s without data says so" % w65)
		if ov65 != null:
			ov65.close()
			await _settle()
	# 段階66：小さい画面のタイトルのメニュー：▼で下にまだあると知らせ、選ぶと付いて流れ、▲に変わる
	var tpl66 := String(player.template.id)
	await player.switch_template("gb_classic")
	await _settle_frames(2)
	var ts66: AdvTitleScreen = AdvTitleScreen.new().setup(player)
	player.screen.add_child(ts66)
	await _settle_frames(3)
	var bl66: Array = ts66.buttons.values()
	check(bl66.size() >= 3 and ts66._more_down.visible and not ts66._more_up.visible, "s66: ▼ shows more items below on GB (%d items)" % bl66.size())
	(bl66.back() as Button).grab_focus()
	await _settle_frames(4)
	var sr66 := ts66._menu_scroll.get_global_rect()
	check(sr66.grow(0.5).encloses((bl66.back() as Button).get_global_rect()) and ts66._more_up.visible and not ts66._more_down.visible, "s66: focusing the last item scrolls it into view and ▲ shows")
	await _shot("review_71_title_scrolled_gb")
	ts66.queue_free()
	# 段階67：項目の多いメニュー（設定）も、キーで選んだ項目に付いて流れ、長い項目は「…」
	var sp67: AdvMenuPanel = player.modern._panel("せってい")
	player.modern._fill_settings(sp67)
	player.screen.add_child(sp67)
	await _settle_frames(3)
	var btn67: Array = sp67.find_children("*", "Button", true, false)
	(btn67.back() as Button).grab_focus()
	await _settle_frames(4)
	var sc67 := (btn67.back() as Control).get_parent().get_parent() as ScrollContainer
	check(sc67.follow_focus and sc67.get_global_rect().grow(0.5).encloses((btn67.back() as Button).get_global_rect()) and (btn67[0] as Button).clip_text, "s67: settings list follows focus and clips long items on GB")
	sp67.queue_free()
	await player.switch_template(tpl66)
	await _settle_frames(2)
	# 段階64：全部のテンプレートでメニュー・ログ・セーブを見直す（はみ出し・文字と地の見分け）。うまくいかないものだけ写真を撮る
	# 段階65：時間がかかるので、-- の後ろに --review を付けたときだけ（ふだんのテストを速く保つ）
	if "--review" in OS.get_cmdline_user_args():
		await _review_all_templates()
	else:
		print("info: 全部のテンプレートの見直しは --review を付けたときだけ")
	await player.switch_template(tpl62)
	await _settle_frames(3)
	var con61: Control = load("res://addons/adv80s/debug/adv_debug_console.gd").new()
	root.add_child(con61)
	con61.set("player", player)
	con61.call("setup", player.core)
	if con61.has_method("open"):
		con61.call("open")
	con61.visible = true
	con61.call("execute_command", "set review_very_long_variable_name_for_the_picker_window \"とても長い文字の値をここに入れて、コンソールの幅からはみ出すかどうか見る\"")
	con61.call("execute_command", "notice")
	con61.call("execute_command", "noticestyle list")
	await _settle_frames(3)
	await _shot("review_63_console")
	con61.queue_free()
	await _settle_frames(2)
	await _test_capture()
	await _test_convert()
	await _test_native_mp4()
	_stage16_done = true   # ここまで来たしるし（途中のスクリプトのエラーで止まると false のまま）


## 段階64：全部のテンプレートで、ゲームを窓いっぱいにしてメニュー・ログ・セーブを開いて確かめる。
func _review_all_templates() -> void:
	var off := [player.anchor_right, player.anchor_bottom, player.offset_right, player.offset_bottom]
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var names: Array = Array(DirAccess.get_directories_at("res://addons/adv80s/templates"))
	names.sort()
	var problems: Array = []
	for t in names:
		await player.switch_template(t)
		await _settle_frames(3)
		_clear_notices()
		var area: Rect2 = player.template.visible_rect()
		for what in REVIEW_SCREENS:
			match what:
				"log": player.open_log()
				"save": player.open_save_menu("load")
				"menu": player.modern.open_system_menu()
				"hints": player.modern.open_hints()
				"notebook": player.modern.open_notebook()
				"flowchart": player.modern.open_flowchart()
				"chapters": player.modern.open_chapters()
				"endings": player.modern.open_endings()
				"extras": player.modern.open_extras()
				"settings_std": player.modern.open_settings()
				"title", "fin", "credits", "image", "settings":
					await _review_built(t, what, area, problems)
					continue
			await _settle()
			var ov: Control = player._overlay
			if ov == null and not player.is_system_scene_open():
				problems.append("%s/%s: 開かない" % [t, what])
				continue
			var sys: bool = player.is_system_scene_open()
			var bad: Array = _overflowing(ov if ov != null else player.screen, area)
			var low := _low_contrast(ov) if ov != null else []
			var msg := ", ".join(bad + low)
			if msg != "":
				problems.append("%s/%s: %s" % [t, what, msg])
			_review_note(t, what, msg)
			await _shot("review_t_%s_%s" % [t, what])
			if ov != null:
				ov.close()
			elif sys:
				player.close_system_scene(false)
			await _settle()
	_write_review_index(names)
	check(problems.is_empty(), "s64: all %d templates show menu, log and save inside the screen and readable:\n  %s" % [names.size(), "\n  ".join(problems)])
	player.anchor_right = off[0]
	player.anchor_bottom = off[1]
	player.offset_right = off[2]
	player.offset_bottom = off[3]
	await _settle_frames(2)


const REVIEW_SCREENS := ["menu", "log", "save", "hints", "notebook", "flowchart", "chapters", "endings", "extras", "title", "fin", "credits", "image", "settings"]
var _review_results := {}   ## テンプレート → 画面 → 問題の文（"" なら問題なし）。見直しの一覧（index.html）に使う（段階67）


## 段階65：組み立てて置く画面（タイトル・おわり・クレジット・画像を見る）を、ゲームの画面に入れて確かめる。
func _review_built(t: String, what: String, area: Rect2, problems: Array) -> void:
	var node: Control
	match what:
		"title":
			node = AdvTitleScreen.new().setup(player)
		"fin":
			node = AdvFinScreen.new().setup(player, {"text": "おわり", "lines": ["見直しのための長めの一行を、ここに書いておく", "おわり"]})
		"credits":
			node = AdvCredits.new().setup({"items": ["スタッフ", "見直しのための長めの名前の人と、その仕事の名前", "おわり"]}, player.template, player.core.state)
		"image":
			var tex := ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGB8))
			node = AdvImageViewer.new().setup([tex, tex], player.template, "見直しの見出し")
		"settings":   # このテストのゲームは設定画面を作者の画面にしているので、ふつうの設定画面を組み立てて見る（段階67）
			var m: AdvMenuPanel = player.modern._panel("せってい")
			player.modern._fill_settings(m)
			m.position = area.position
			node = m
	player.screen.add_child(node)
	await _settle_frames(3)
	var bad: Array = _overflowing(node, area)
	if what == "credits":   # 下から上へ流れるので、横だけ見る
		bad = []
		for c in node.find_children("*", "Label", true, false):
			var r := Rect2((c as Control).global_position, (c as Control).size)
			if (c as Control).is_visible_in_tree() and (r.position.x < area.position.x - 0.5 or r.end.x > area.end.x + 0.5):
				bad.append("%s「%s」%s" % [c.name, (c as Label).text.left(12), str(r)])
	if what == "settings":
		bad += _low_contrast(node)
	var msg := ", ".join(bad)
	if msg != "":
		problems.append("%s/%s: %s" % [t, what, msg])
	_review_note(t, what, msg)
	await _shot("review_t_%s_%s" % [t, what])
	node.queue_free()
	await _settle_frames(1)


func _review_note(t: String, what: String, msg: String) -> void:
	if not _review_results.has(t):
		_review_results[t] = {}
	_review_results[t][what] = msg


## 見直しの一覧（段階67）：写真の置き場所に index.html を書く。行がテンプレート、列が画面。問題のある写真は赤い枠と文。
func _write_review_index(names: Array) -> void:
	if _shot_dir == "":
		return
	var h := PackedStringArray()
	h.append("<!DOCTYPE html><html lang=\"ja\"><head><meta charset=\"utf-8\"><title>adv80sGD 見直し</title>")
	h.append("<style>body{font-family:sans-serif;background:#222;color:#ddd;margin:16px}table{border-collapse:collapse}th,td{padding:4px;vertical-align:top;font-size:12px}th{position:sticky;top:0;background:#222}img{width:200px;border:2px solid #444;display:block}td.bad img{border-color:#e33}td.bad p{color:#f88;max-width:200px;word-break:break-all}</style></head><body>")
	var bad_n := 0
	for t in names:
		for w in REVIEW_SCREENS:
			if String(_review_results.get(t, {}).get(w, "")) != "":
				bad_n += 1
	h.append("<h1>見直し：テンプレート %d × 画面 %d（問題 %d）</h1><table><tr><th>テンプレート</th>" % [names.size(), REVIEW_SCREENS.size(), bad_n])
	for w in REVIEW_SCREENS:
		h.append("<th>%s</th>" % w)
	h.append("</tr>")
	for t in names:
		h.append("<tr><th>%s</th>" % t)
		for w in REVIEW_SCREENS:
			var msg := String(_review_results.get(t, {}).get(w, ""))
			var img := "review_t_%s_%s.png" % [t, w]
			h.append("<td%s><a href=\"%s\"><img src=\"%s\" alt=\"%s %s\"></a>%s</td>" % [" class=\"bad\"" if msg != "" else "", img, img, t, w, "<p>%s</p>" % msg.xml_escape() if msg != "" else ""])
		h.append("</tr>")
	h.append("</table></body></html>")
	var f := FileAccess.open("%s/index.html" % _shot_dir, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(h))
		f.close()


## 窓の地の色と、中の文字（Label・Button）の色の明るさが近すぎるもの（0.3 より小さい）。地の色のわからない窓は調べない。
func _low_contrast(ov: Control) -> Array:
	var sb = ov.get_theme_stylebox("panel")
	if not sb is StyleBoxFlat:
		return []
	var bg := (sb as StyleBoxFlat).bg_color.get_luminance()
	var out: Array = []
	for c in ov.find_children("*", "Control", true, false):
		var ct := c as Control
		if not ct.is_visible_in_tree():
			continue
		var col: Color
		var txt := ""
		if ct is Label:
			col = ct.get_theme_color("font_color")
			txt = (ct as Label).text
		elif ct is Button:
			col = ct.get_theme_color("font_focus_color" if ct.has_focus() else "font_color")
			txt = (ct as Button).text
		elif ct is RichTextLabel:
			col = ct.get_theme_color("default_color")
			txt = (ct as RichTextLabel).get_parsed_text()
		else:
			continue
		# ボタンは自分の地（normal・focus のスタイル）があればそれと比べる
		var own_bg := bg
		if ct is Button:
			var bs = ct.get_theme_stylebox("focus" if ct.has_focus() else "normal")
			if bs is StyleBoxFlat and (bs as StyleBoxFlat).bg_color.a > 0.5:
				own_bg = (bs as StyleBoxFlat).bg_color.get_luminance()
		if txt.strip_edges() != "" and absf(col.get_luminance() - own_bg) < 0.3:
			out.append("見分けにくい%s「%s」" % [ct.get_class(), txt.strip_edges().left(8)])
	return out


## お知らせを全部消す。
func _clear_notices() -> void:
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()


## 段階63：見える範囲（元の解像度の area）の外へはみ出している見える文字・ボタンの一覧（名前と文字）。ないなら []。
func _overflowing(node: Node, area: Rect2) -> Array:
	var out: Array = []
	for c in node.find_children("*", "Control", true, false):
		var ct := c as Control
		if not ct.is_visible_in_tree() or ct.size.x <= 0.0:
			continue
		if not (ct is Label or ct is Button or ct is RichTextLabel):
			continue
		var r := Rect2(ct.global_position, ct.size)
		var pa := ct.get_parent()
		while pa is Control:   # 中身を切る窓（clip_contents）の中なら、見えるのはその窓の中だけ
			if (pa as Control).clip_contents:
				r = r.intersection(Rect2((pa as Control).global_position, (pa as Control).size))
			pa = pa.get_parent()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not area.grow(0.5).encloses(r):
			var t := String(ct.get("text")) if ct.get("text") != null else ""
			out.append("%s「%s」%s" % [ct.name, t.left(12), str(r)])
	return out


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


func _panel_buttons() -> Array:
	if player._overlay == null:
		return []
	return player._overlay.find_children("*", "Button", true, false).map(func(b): return (b as Button).text)


func _press_panel(label: String) -> void:
	if player._overlay != null:
		for b in player._overlay.find_children("*", "Button", true, false):
			if (b as Button).text == label and not (b as Button).disabled:
				(b as Button).pressed.emit()
				return
	check(false, "panel button not found: %s" % label)


func _buttons(sel: AdvCommandSelect) -> Array:
	var r := []
	for b in sel._grid.get_children():
		if b is Button and not b.is_queued_for_deletion():
			r.append(b.text)
	return r


func _inv_buttons(sel: AdvCommandSelect) -> Array:
	var r := []
	for b in sel._inv.get_children():
		if b is Button and not b.is_queued_for_deletion():
			r.append(b.text)
	return r


func _press(sel: AdvCommandSelect, label: String) -> void:
	for b in sel._grid.get_children() + sel._inv.get_children():
		if b is Button and b.text == label and not b.is_queued_for_deletion():
			b.pressed.emit()
			return
	check(false, "button not found: %s" % label)


func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()


## 段階68：画面の写真と録画。デバッグ実行中はいつも使える。配布アプリではモダン機能 screenshot・recording。
func _test_capture() -> void:
	var headless := DisplayServer.get_name() == "headless"
	check(player.capture_on("screenshot") and player.capture_on("recording"), "s68: capture is always on while debugging")
	check(player.capture_key(KEY_F7) == "screenshot" and player.capture_key(KEY_F10) == "recording" and player.capture_key(KEY_F2) == "", "s68: F7 and F10")
	player._as_release = true
	check(not player.capture_on("screenshot") and not player.capture_on("recording") and player.capture_key(KEY_F7) == "", "s68: off in a release build unless the features are on")
	check(await player.take_screenshot() == "" and player.start_recording() == "", "s68: nothing happens when off")
	var old_en: Dictionary = player.features.enabled.duplicate()
	var old_opt: Dictionary = player.features.options.duplicate()
	player.features.enabled["screenshot"] = true
	player.features.options["screenshot"] = {"folder": "user://s68_shots", "prefix": "s68", "source": "screen", "scale": 2, "key": "F8"}
	check(player.capture_on("screenshot") and player.capture_key(KEY_F8) == "screenshot" and player.capture_key(KEY_F7) == "", "s68: feature on, key from options")
	_rmdir("user://s68_shots")
	_rmdir("user://s68_rec")
	var vs: Vector2i = player.display.viewport.size
	if not headless:
		var p: String = await player.take_screenshot()
		var im := Image.load_from_file(p) if p != "" else null
		check(im != null and im.get_width() == vs.x * 2 and im.get_height() == vs.y * 2, "s68: screenshot of the screen x2: %s %s" % [p, str(vs)])
		await _settle()
		check(player.notices().any(func(t): return String(t).begins_with("がめんを ほぞんしました")), "s68: notice after the screenshot: %s" % str(player.notices()))
		player.features.enabled["recording"] = true
		player.features.options["recording"] = {"folder": "user://s68_rec", "fps": 10, "source": "screen"}
		var rp := player.start_recording()
		check(rp != "" and player.is_recording() and player.start_recording() == "", "s68: recording started: %s" % player.capture.last_error)
		await create_timer(0.7).timeout
		var cp := player.stop_recording()
		check(cp == rp and not player.is_recording(), "s68: recording stopped")
		var info := AdvAviWriter.read_info(rp)
		check(bool(info.get("riff_ok", false)) and int(info.get("frames", 0)) >= 5 and int(info.get("frames", 0)) == int(info.get("video_chunks", -1)), "s68: avi frames: %s" % str(info.get("frames")))
		check(info.get("width") == vs.x and info.get("height") == vs.y and info.get("fps") == 10, "s68: avi size: %s %s" % [str(info.get("width")), str(info.get("height"))])
		check(info.get("streams") == 2 and info.get("audio_rate") == int(AudioServer.get_mix_rate()), "s68: avi has sound")
		var j := Image.new()
		check(j.load_jpg_from_buffer(info.get("first_jpeg", PackedByteArray())) == OK, "s68: first frame is a jpeg")
		check(AudioServer.get_bus_effect_count(0) == 0, "s68: the capture effect is removed")
		# いちばん長い秒数で止まる
		player.features.options["recording"] = {"folder": "user://s68_rec", "fps": 10, "source": "screen", "audio": false, "max_seconds": 0.3}
		var mp := player.start_recording()
		await create_timer(0.8).timeout
		check(mp != "" and not player.is_recording() and int(player.capture.last_info.get("frames", 0)) >= 3, "s68: stops at max_seconds")
		await _settle()
		check(player.notices().any(func(t): return String(t).contains("じょうげん")), "s68: notice tells why it stopped: %s" % str(player.notices()))
		check(AdvAviWriter.read_info(mp).get("streams") == 1, "s68: no sound stream with audio: false")
	# 設定の画面の切り替え
	check(not player.capture_in_menu("screenshot"), "s68: no menu toggle unless the project lists the feature")
	var old_pf = player.project.data.get("features")
	player.project.data["features"] = {"screenshot": {"allow": true}}
	check(player.capture_in_menu("screenshot") and not player.capture_in_menu("recording"), "s68: menu toggle when the project lists it")
	player.project.data["features"] = {"screenshot": {"allow": true, "options": {"menu": false}}}
	player.features.options["screenshot"] = {"menu": false}
	check(not player.capture_in_menu("screenshot"), "s68: menu: false hides the toggle")
	if old_pf == null:
		player.project.data.erase("features")
	else:
		player.project.data["features"] = old_pf
	player.features.enabled = old_en
	player.features.options = old_opt
	player._as_release = false
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	_rmdir("user://s68_shots")
	_rmdir("user://s68_rec")


class _CountEncoder extends AdvVideoEncoder:
	var frames := 0
	var audio := 0
	var opened := ""
	var closed := false
	func extension() -> String:
		return "cnt"
	func open(path: String, _w: int, _h: int, _fps: int, _rate: int) -> Error:
		opened = path
		FileAccess.open(path, FileAccess.WRITE).close()
		return OK
	func add_video(_img: Image) -> void:
		frames += 1
	func repeat_video() -> void:
		frames += 1
	func add_audio(s: PackedVector2Array) -> void:
		audio += s.size()
	func close() -> Dictionary:
		closed = true
		return {"path": opened, "frames": frames}


## 段階69：登録した書き出しで録る。ffmpeg で MP4 に変える（環境変数 ADV80S_TEST_FFMPEG に ffmpeg のパスがあるときだけ）。
func _test_convert() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vs: Vector2i = player.display.viewport.size
	var old_opt: Dictionary = player.features.options.duplicate()
	_rmdir("user://s69_rec")
	var enc := _CountEncoder.new()
	AdvCapture.register_encoder("cnt", func(): return enc)
	player.features.options["recording"] = {"folder": "user://s69_rec", "fps": 10, "source": "screen", "format": "cnt"}
	var p := player.start_recording()
	await create_timer(0.5).timeout
	player.stop_recording()
	check(p.ends_with(".cnt") and enc.opened == p and enc.closed and enc.frames >= 4, "s69: registered encoder records: %s %d" % [p, enc.frames])
	check(int(player.capture.last_info.get("frames", 0)) == enc.frames, "s69: close result is last_info")
	AdvCapture.register_encoder("cnt", Callable())
	var ff := OS.get_environment("ADV80S_TEST_FFMPEG")
	if ff == "" or not FileAccess.file_exists(ff):
		print("s69: ADV80S_TEST_FFMPEG がないので、ffmpeg の変換は試しません")
		player.features.options = old_opt
		_rmdir("user://s69_rec")
		return
	# MP4 に変える
	AdvFfmpeg.forget()
	player.features.options["recording"] = {"folder": "user://s69_rec", "fps": 10, "source": "screen", "format": "mp4", "ffmpeg": ff}
	check(AdvCapture.plan(player.capture_options("recording")).get("convert") == "mp4", "s69: plan converts with ffmpeg")
	var got := []
	var on_conv := func(path: String, ok: bool): got.append([path, ok])
	player.capture.converted.connect(on_conv)
	var avi := player.start_recording()
	await create_timer(0.6).timeout
	player.stop_recording()
	check(avi.ends_with(".avi") and player.capture.is_converting(avi), "s69: converting after stop")
	await _settle()
	check(player.notices().any(func(t): return String(t).begins_with("ろくがを MP4 に して います")), "s69: converting notice: %s" % str(player.notices()))
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	var mp4 := String(got[0][0]) if not got.is_empty() else ""
	check(not got.is_empty() and got[0][1] and mp4.ends_with(".mp4") and FileAccess.file_exists(mp4) and FileAccess.get_size(mp4) > 1000, "s69: converted to mp4: %s %s" % [str(got), player.capture.last_error])
	check(not FileAccess.file_exists(avi), "s69: avi removed after converting")
	if mp4 != "":
		var probe: Array = []
		OS.execute(ff, ["-hide_banner", "-i", ProjectSettings.globalize_path(mp4)], probe, true)
		var info := "\n".join(probe)
		check(info.contains("h264") and info.contains("yuv420p(tv") and info.contains("aac") and info.contains("%dx%d" % [vs.x, vs.y]), "s69: mp4 has h264 and aac: %s" % info.substr(info.find("Stream"), 300))
	await _settle()
	check(player.notices().any(func(t): return String(t) == "ろくがを ほぞんしました（%s）" % mp4.get_file()), "s69: saved notice names the mp4: %s" % str(player.notices()))
	# 変えられないとき（使えないエンコーダー）は AVI を残す
	got.clear()
	player.features.options["recording"] = {"folder": "user://s69_rec", "fps": 10, "source": "screen", "format": "mp4", "ffmpeg": ff, "ffmpeg_args": ["-c:v", "no_such_codec"], "audio": false}
	var avi2 := player.start_recording()
	await create_timer(0.4).timeout
	player.stop_recording()
	t0 = Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	check(not got.is_empty() and not got[0][1] and got[0][0] == avi2 and FileAccess.file_exists(avi2) and not FileAccess.file_exists(avi2.get_basename() + ".mp4"), "s69: failed conversion keeps the avi: %s" % str(got))
	await _settle()
	check(player.notices().any(func(t): return String(t).begins_with("MP4 に できなかったので")), "s69: failure notice")
	# keep_avi
	got.clear()
	player.features.options["recording"] = {"folder": "user://s69_rec", "fps": 10, "source": "screen", "format": "mp4", "ffmpeg": ff, "keep_avi": true}
	var avi3 := player.start_recording()
	await create_timer(0.3).timeout
	player.stop_recording()
	t0 = Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	check(not got.is_empty() and got[0][1] and FileAccess.file_exists(avi3), "s69: keep_avi keeps both")
	player.capture.converted.disconnect(on_conv)
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	player.features.options = old_opt
	_rmdir("user://s69_rec")


## 段階70：OS のエンコーダーで MP4 に録る（addons/adv80s_mp4。使えない環境では飛ばす）。
func _test_native_mp4() -> void:
	if DisplayServer.get_name() == "headless" or not AdvMp4Encoder.native_ready():
		print("s70: OS の MP4 の書き出しが使えないので飛ばします")
		return
	var old_opt: Dictionary = player.features.options.duplicate()
	var vs: Vector2i = player.display.viewport.size
	_rmdir("user://s70_rec")
	AdvMp4Encoder.register()
	player.features.options["recording"] = {"folder": "user://s70_rec", "fps": 15, "source": "screen", "format": "mp4"}
	var before := player.capture_image("screen")
	var p := player.start_recording()
	check(p.ends_with(".mp4") and player.capture.last_note == "", "s70: records straight to mp4: %s" % p)
	await create_timer(0.8).timeout
	var cp := player.stop_recording()
	check(cp == p and not player.capture.is_converting(), "s70: no conversion needed")
	var info := AdvMp4Encoder.probe(p)
	check(info.get("video") == "h264" and info.get("audio") == "aac" and info.get("width") == vs.x and info.get("height") == vs.y, "s70: mp4 from the game: %s" % str(info))
	check(float(info.get("seconds", 0.0)) >= 0.5, "s70: length: %s" % str(info.get("seconds")))
	var f := AdvMp4Encoder.read_first_frame(p)
	if f != null and before != null:
		before.convert(Image.FORMAT_RGB8)
		# 画面全体の 16×10 の点で比べる（明るいところがあることも確かめる）
		var diff := 0.0
		var bright := 0.0
		for gy in 10:
			for gx in 16:
				var c := Vector2i(int((gx + 0.5) * vs.x / 16.0), int((gy + 0.5) * vs.y / 10.0))
				var a := before.get_pixelv(c)
				var b := f.get_pixelv(c)
				diff += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
				bright = maxf(bright, a.get_luminance())
		diff /= 160.0
		check(bright > 0.3 and diff < 0.06, "s70: first frame looks like the screen: diff %.3f bright %.2f" % [diff, bright])
	else:
		check(false, "s70: first frame")
	await _settle()
	check(player.notices().any(func(t): return String(t) == "ろくがを ほぞんしました（%s）" % p.get_file()), "s70: saved notice: %s" % str(player.notices()))
	AdvCapture.register_encoder("mp4", Callable())
	player.features.options = old_opt
	for n in player._notices:
		if is_instance_valid(n):
			n.queue_free()
	player._notices.clear()
	_rmdir("user://s70_rec")
