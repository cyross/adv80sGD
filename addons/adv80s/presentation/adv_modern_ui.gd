class_name AdvModernUI
extends RefCounted
## モダン機能の画面（第10章）：システムメニュー、ヒント、目的、手帳、フローチャート、チャプター選択、設定。
## どの画面も、有効になっている機能だけを出す。

var player: AdvPlayer


func _init(p: AdvPlayer) -> void:
	player = p


func _panel(title: String) -> AdvMenuPanel:
	return AdvMenuPanel.new().setup(title, player.template, player.template.visible_rect().size)   # 見える範囲の大きさ（段階63）


func _on(key: String) -> bool:
	return player.features != null and player.features.is_on(key)


## システムメニュー（F1、右クリック、ゲームパッドの Start）。
func open_system_menu() -> void:
	var m := _panel("メニュー")
	var idle := not player.busy
	m.add_button("セーブ", func(): m.close(); player.open_save_menu("save"), idle or player.core.query("pending_choice") != null)
	m.add_button("ロード", func(): m.close(); player.open_save_menu("load"))
	if _on("message_log"):
		m.add_button("ログ", func(): m.close(); player.open_log())
	if _on("rewind"):
		m.add_button("まきもどす", func(): m.close(); player.rewind(1), idle and player.can_rewind())
	if _on("hint"):
		m.add_button("ヒント", func(): m.close(); open_hints(), not player.core.query("hints").is_empty())
	if _on("objective"):
		m.add_button("もくてき", func(): m.close(); open_objective())
	if _on("notebook"):
		m.add_button("てちょう", func(): m.close(); open_notebook())
	if _on("flowchart") and player.core.query("flow") != null:
		m.add_button("フローチャート", func(): m.close(); open_flowchart())
	if _on("chapter_select") and player.core.query("chapters") != null:
		m.add_button("チャプター", func(): m.close(); open_chapters())
	if has_endings():
		m.add_button("エンディング", func(): m.close(); open_endings())
	m.add_button("せってい", func(): m.close(); open_settings())
	if String(player.project.get_value("title_screen", "")) != "":
		m.add_button("タイトルへ", func(): m.close(); player.go_title(), idle or player.core.query("pending_choice") != null)
	m.add_back()
	m.focus_first()
	await player.show_overlay(m)


## 段階式ヒント：話題ごとに、見た段階までを出し、次の段階を開くボタンを付ける。
func open_hints() -> void:
	var m := _panel("ヒント")
	_fill_hints(m)
	m.focus_first()
	await player.show_overlay(m)


func _fill_hints(m: AdvMenuPanel) -> void:
	m.clear_items()
	for h in player.core.query("hints"):
		var label := String(player.project.get_value("hint_topics", {}).get(h["topic"], h["topic"]))
		m.add_text("[%s]" % label, int(player.template.get_section("text").get("name_color", 6)))
		for t in h["texts"]:
			m.add_text("  " + AdvTextMarkup.to_bbcode(String(t), player.core.state, player.template))
		var more: bool = int(h["revealed"]) < int(h["stages"])
		var topic := String(h["topic"])
		m.add_button("  つぎの ヒントを みる（%d/%d）" % [h["revealed"], h["stages"]],
			func():
				player.core.reveal_hint(topic)
				_fill_hints(m)
				m.focus_first(), more)
	m.add_back()


func open_objective() -> void:
	var m := _panel("もくてき")
	var o = player.core.query("objective")
	m.add_text(AdvTextMarkup.to_bbcode(String(o["text"]), player.core.state, player.template) if o is Dictionary else "いまは とくに ない。")
	m.add_back()
	m.focus_first()
	await player.show_overlay(m)


func open_notebook() -> void:
	var m := _panel("てちょう")
	var cat := ""
	var name_c := int(player.template.get_section("text").get("name_color", 6))
	var list: Array = player.core.query("notebook")
	if list.is_empty():
		m.add_text("まだ なにも かいていない。")
	for n in list:
		if n["category"] != cat:
			cat = n["category"]
			if cat != "":
				m.add_text("【%s】" % cat, name_c)
		m.add_text("・%s" % AdvTextMarkup.to_bbcode(String(n["title"]), player.core.state, player.template))
		m.add_text("　%s" % AdvTextMarkup.to_bbcode(String(n["body"]), player.core.state, player.template))
	m.add_back()
	m.focus_first()
	await player.show_overlay(m)


func open_flowchart() -> void:
	var m := _panel("フローチャート")
	var flow = player.core.query("flow")
	if not flow is Dictionary:   # フローチャートのないゲーム（段階65。前はここで止まっていた）
		m.add_text("フローチャートは ありません。")
		m.add_back()
		m.focus_first()
		await player.show_overlay(m)
		return
	var v := AdvFlowView.new()
	v.setup(player.template, flow)
	v.node_chosen.connect(func(id: String):
		m.close()
		player.jump_to_node(id))
	m.add_control(v)
	m.add_text("とうたつした ばしょを えらぶと、そこから やりなおせる。")
	m.add_back()
	await player.show_overlay(m)


func open_chapters() -> void:
	var m := _panel("チャプター")
	var chs = player.core.query("chapters")
	if not chs is Array or chs.is_empty():   # チャプターのないゲーム（段階65）
		m.add_text("チャプターは ありません。")
		chs = []
	for c in chs:
		var node := String(c["node"])
		var ok: bool = c["unlocked"] and c["can_jump"]
		m.add_button(String(c["label"]) if c["unlocked"] else "？？？", func(): m.close(); player.jump_to_node(node), ok)
	m.add_back()
	m.focus_first()
	await player.show_overlay(m)


## おまけ（プロジェクト設定 extras）：ギャラリー（gallery）と音楽（music）。
## 項目は {id, label, when?, hint?}。when がなければ、一度でも出した画像・鳴らした曲なら開く。開いていない項目は「？？？」。
func open_extras() -> void:
	var ex: Dictionary = player.project.get_value("extras", {})
	var labels := {"gallery": String(ex.get("gallery_label", "ギャラリー")), "music": String(ex.get("music_label", "おんがく")),
		"endings": String(ex.get("endings_label", "エンディング")), "opening": String(ex.get("opening_label", "オープニング"))}
	while true:
		var pick := [""]
		var m := _panel(String(ex.get("title", "おまけ")))
		for k in player.extras_menu():
			if k == "opening" and not _at_title():
				continue   # 遊んでいる途中の状態を消さないため、タイトルからだけ
			var key: String = k
			m.add_button(labels[key], func(): pick[0] = key; m.close())
		m.add_back()
		m.focus_first()
		await player.show_overlay(m)
		match pick[0]:
			"gallery":
				await open_gallery()
			"music":
				await open_music()
			"endings":
				await open_endings()
			"opening":
				await player.replay_opening()
				return
			_:
				return


## タイトル（タイトルのシーンかタイトル画面）から開いているか。
func _at_title() -> bool:
	return player.core.state.scene == "" or player.core.query("scene_kind") == "title"


## ギャラリーの項目の見本の画像（thumb、なければ見た最初の画像）。
func gallery_thumb(e: Dictionary) -> Texture2D:
	var id := String(e.get("thumb", ""))
	if id == "":
		var pages: Array = player.extra_pages(e)
		if pages.is_empty():
			return null
		id = String(pages[0])
	return player._layer_texture(id)


## ボタンの左に見本を出す（開いていない項目は同じ大きさの空き）。
func _set_thumb(b: Button, tex: Texture2D) -> void:
	if tex == null:
		var img := Image.create(THUMB_SIZE, THUMB_SIZE * 5 / 8, false, Image.FORMAT_RGBA8)
		img.fill(player.template.color(1))
		tex = ImageTexture.create_from_image(img)
	b.icon = tex
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", THUMB_SIZE)
	b.custom_minimum_size.y = THUMB_SIZE * 5 / 8 + 4
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _extra_text(e: Dictionary, unlocked: bool) -> String:
	if unlocked:
		return String(e.get("label", e.get("id", "")))
	var hint := String(e.get("hint", ""))
	return "？？？" + ("　" + hint if hint != "" else "")


const THUMB_SIZE := 64


## ギャラリー：開いている項目を選ぶと、画像を画面いっぱいに出す（images があれば、めくれる）。
## extras.thumbnails（既定 true）なら、開いている項目の横に小さな見本（thumb、なければ最初の画像）を出す。
func open_gallery() -> void:
	var ex: Dictionary = player.project.get_value("extras", {})
	var list: Array = ex.get("gallery", [])
	var thumbs := bool(ex.get("thumbnails", true))
	while true:
		var pick := [-1]
		var m := _panel(String(ex.get("gallery_label", "ギャラリー")))
		player.fill_extras_sys()
		for i in list.size():
			var e = list[i]
			if not e is Dictionary or not player.extra_listed(e, "image"):
				continue
			var ok: bool = player.extra_unlocked(e, "image")
			var idx := i
			var b := m.add_button(_extra_text(e, ok), func(): pick[0] = idx; m.close(), ok)
			if thumbs:
				_set_thumb(b, gallery_thumb(e) if ok else null)
		var sys: Dictionary = player.core.state.sys
		m.add_text("%d / %d" % [int(sys.get("gallery_opened", 0)), int(sys.get("gallery_total", 0))])
		m.add_back()
		m.focus_first()
		await player.show_overlay(m)
		if pick[0] < 0:
			return
		var e: Dictionary = list[pick[0]]
		var texs := []
		for id in player.extra_pages(e):
			var tex: Texture2D = player._layer_texture(String(id))
			if tex != null:
				texs.append(tex)
		if not texs.is_empty():
			await player.show_overlay(AdvImageViewer.new().setup(texs, player.template, String(e.get("label", ""))))


const MUSIC_MODES := ["one", "next", "all"]
const MUSIC_MODE_NAMES := {"one": "1きょく くりかえし", "next": "つづけて", "all": "ぜんぶ くりかえし"}

var _music_list: Array = []
var _music_index := -1
var _music_now: RichTextLabel
var _music_desc: RichTextLabel


## 音楽の鳴らし方（one：1曲をくりかえす、next：開いている曲を順に鳴らして止まる、all：順に鳴らしてくりかえす）。
## プレイヤー設定 music_mode（なければ extras.music_mode、既定 one）。
func music_mode() -> String:
	var ex: Dictionary = player.project.get_value("extras", {})
	var m := String(player.settings.get_value("music_mode", ex.get("music_mode", "one")))
	return m if m in MUSIC_MODES else "one"


## 音楽：開いている曲を選ぶと鳴らす。閉じると、開く前の曲に戻す。
func open_music() -> void:
	var ex: Dictionary = player.project.get_value("extras", {})
	player.fill_extras_sys()
	_music_list = ex.get("music", []).filter(func(e): return e is Dictionary and player.extra_listed(e, "bgm"))
	_music_index = -1
	var before: Dictionary = player.audio.current_bgm.duplicate()
	var m := _panel(String(ex.get("music_label", "おんがく")))
	_music_now = m.add_text("")
	_music_desc = m.add_text("", int(player.template.get_section("text").get("name_color", 6))) if bool(ex.get("music_desc", true)) else null
	_update_music_now()
	for i in _music_list.size():
		var e: Dictionary = _music_list[i]
		var idx := i
		m.add_button(_extra_text(e, player.extra_unlocked(e, "bgm")), func(): music_play(idx), player.extra_unlocked(e, "bgm"))
	var mb := [null]
	mb[0] = m.add_button("さいせい：%s" % MUSIC_MODE_NAMES[music_mode()], func():
		var nxt: String = MUSIC_MODES[(MUSIC_MODES.find(music_mode()) + 1) % MUSIC_MODES.size()]
		player.settings.set_value("music_mode", nxt)
		player.save_settings()
		(mb[0] as Button).text = "さいせい：%s" % MUSIC_MODE_NAMES[nxt]
		if _music_index >= 0:
			player.audio.set_bgm_loop(nxt == "one"))
	m.add_button("とめる", func():
		_music_index = -1
		player.audio.stop_bgm(0.3)
		_update_music_now())
	m.add_back()
	m.focus_first()
	player.audio.bgm_finished.connect(_on_music_finished)
	await player.show_overlay(m)
	player.audio.bgm_finished.disconnect(_on_music_finished)
	_music_index = -1
	_music_now = null
	_music_desc = null
	if before.is_empty():
		player.audio.stop_bgm(0.3)
	else:
		player.audio.stop_bgm()
		await player._play(AdvEvents.make("bgm.play", before))


## 音楽の i 番目の曲を鳴らす（鳴らし方が one ならくりかえす）。
func music_play(i: int) -> void:
	if i < 0 or i >= _music_list.size():
		return
	_music_index = i
	player.audio.stop_bgm()
	_update_music_now()
	await player._play(AdvEvents.make("bgm.play", {"id": String(_music_list[i].get("id", "")), "loop": music_mode() == "one"}))


func _on_music_finished() -> void:
	if _music_index < 0:
		return
	var mode := music_mode()
	if mode == "one":
		return
	var n := _next_music(_music_index + 1, _music_list.size())
	if n < 0 and mode == "all":
		n = _next_music(0, _music_index + 1)
	if n < 0:
		_music_index = -1
		player.audio.stop_bgm()
		_update_music_now()
		return
	music_play(n)


func _next_music(from: int, to: int) -> int:
	for i in range(from, to):
		if player.extra_unlocked(_music_list[i], "bgm"):
			return i
	return -1


func _update_music_now() -> void:
	if _music_now == null:
		return
	var name := String(_music_list[_music_index].get("label", _music_list[_music_index].get("id", ""))) if _music_index >= 0 else "―"
	_music_now.text = "いま：%s" % name
	if _music_desc != null:
		var desc := String(_music_list[_music_index].get("desc", "")) if _music_index >= 0 else ""
		_music_desc.text = AdvTextMarkup.to_bbcode(desc, player.core.state, player.template) if desc != "" else ""
		_music_desc.visible = desc != ""


## プロジェクト設定 endings があるか。
func has_endings() -> bool:
	var e = player.project.get_value("endings", [])
	return e is Array and not e.is_empty()


## エンディング一覧（6.9）：プロジェクト設定 endings の順に、見たものは名前、見ていないものは「？？？」とヒントを出す。
func open_endings() -> void:
	var m := _panel("エンディング")
	var list: Array = player.project.get_value("endings", [])
	var seen := 0
	for e in list:
		if e is Dictionary and player.progress.endings.has(String(e.get("id", ""))):
			seen += 1
	m.add_text("みた エンディング：%d / %d" % [seen, list.size()], int(player.template.get_section("text").get("name_color", 6)))
	for e in list:
		if not e is Dictionary:
			continue
		var id := String(e.get("id", ""))
		if player.progress.endings.has(id):
			var rec: Dictionary = player.progress.endings[id]
			var label := AdvTextMarkup.to_bbcode(String(e.get("label", id)), player.core.state, player.template)
			m.add_text("・%s%s" % [label, "（%dかい）" % int(rec.get("count", 1)) if int(rec.get("count", 1)) > 1 else ""])
		else:
			var hint := String(e.get("hint", ""))
			m.add_text("・？？？" + ("　" + AdvTextMarkup.to_bbcode(hint, player.core.state, player.template) if hint != "" else ""))
	# オープニングを見返すのは、タイトルから開いたときだけ（遊んでいる途中の状態を消さないため）
	if player.can_replay_opening() and (player.core.state.scene == "" or player.core.query("scene_kind") == "title"):
		m.add_button("オープニングを みる", func(): m.close(); player.replay_opening())
	m.add_back()
	m.focus_first()
	await player.show_overlay(m)


## 設定（文字の表示調整、オート送り、スキップ、フィルター、旧表示と新表示、読みやすいフォント、読み上げ、印の表示）。
func open_settings() -> void:
	var custom: bool = await player._open_custom_system("settings")
	if custom:
		return
	var m := _panel("せってい")
	_fill_settings(m)
	m.focus_first()
	await player.show_overlay(m)


func _fill_settings(m: AdvMenuPanel) -> void:
	m.clear_items()
	var s := player.settings
	var refill := func(): _fill_settings(m); m.focus_first()
	if _on("text_options"):
		var speeds := [0.5, 1.0, 2.0, 0.0]
		var cur := float(s.get_value("text_speed", 1.0))
		var label := "いっしゅん" if cur == 0.0 else "x%s" % str(cur)
		m.add_button("もじの はやさ：%s" % label, func():
			player.set_text_speed(_next(speeds, cur))
			refill.call())
		var sizes := [1.0, 1.5, 2.0]
		var cur_size := float(s.get_value("text_size", 1.0))
		m.add_button("もじの おおきさ：x%s" % str(cur_size), func():
			player.set_text_option("text_size", _next(sizes, cur_size))
			refill.call())
		var colors := [-1, 7, 6, 5, 4]
		var color_names := {-1: "ひょうじゅん", 7: "しろ", 6: "きいろ", 5: "みずいろ", 4: "みどり"}
		var cur_color := int(s.get_value("text_color", -1))
		m.add_button("もじの いろ：%s" % color_names.get(cur_color, str(cur_color)), func():
			var i := colors.find(cur_color)
			player.set_text_option("text_color", colors[(i + 1) % colors.size()])
			refill.call())
		var opacities := [1.0, 0.75, 0.5, 0.25]
		var cur_op := float(s.get_value("window_opacity", 1.0))
		m.add_button("まどの こさ：%d%%" % int(round(cur_op * 100)), func():
			player.set_text_option("window_opacity", _next(opacities, cur_op))
			refill.call())
	if _on("auto_advance"):
		var delays := [0.6, 1.2, 2.0, 3.0]
		var cur := float(s.get_value("auto_delay", 1.2))
		m.add_button("オートの まちじかん：%sびょう" % str(cur), func():
			s.set_value("auto_delay", _next(delays, cur))
			player.save_settings()
			refill.call())
	if _on("skip"):
		m.add_button("みどくも スキップ：%s" % _onoff(s.get_value("skip_unread", false)), func():
			s.set_value("skip_unread", not bool(s.get_value("skip_unread", false)))
			player.save_settings()
			refill.call())
	if _on("filter_toggle"):
		m.add_button("フィルター：%s" % _onoff(player.display.filters_enabled), func():
			player.set_filters_enabled(not player.display.filters_enabled)
			refill.call())
	if _on("era_switch"):
		m.add_button("がめんの じだい：%s" % String(player.template.data.get("name", player.template.id)), func():
			await player.cycle_template()
			refill.call())
	if _on("readable_font") or player.features.allowed.get("readable_font", true) and player.template.get_section("fonts").has("readable"):
		m.add_button("よみやすい もじ：%s" % _onoff(player.screen.readable), func():
			player.set_feature("readable_font", not player.screen.readable)
			refill.call())
	if player.features.allowed.get("gamepad", true):
		m.add_button("コントローラー：%s" % _onoff(_on("gamepad")), func():
			player.set_feature("gamepad", not _on("gamepad"))
			refill.call())
	if player.features.allowed.get("touch", true) and DisplayServer.is_touchscreen_available():
		m.add_button("タッチそうさ：%s" % _onoff(_on("touch")), func():
			player.set_feature("touch", not _on("touch"))
			refill.call())
	if player.features.allowed.get("tts", true) and AdvPlayer._tts_available():
		m.add_button("よみあげ：%s" % _onoff(_on("tts")), func():
			player.set_feature("tts", not _on("tts"))
			refill.call())
	for vk in [["bgm_volume", "おんがく"], ["se_volume", "こうかおん"], ["voice_volume", "こえ"]]:
		var key: String = vk[0]
		var levels := [0.0, 0.25, 0.5, 0.75, 1.0]
		var cur := float(s.get_value(key, 1.0))
		m.add_button("%sの おおきさ：%d%%" % [vk[1], int(round(cur * 100))], func():
			s.set_value(key, _next(levels, cur))
			player.save_settings()
			player.apply_volumes()
			refill.call())
	for key in ["hotspot", "tried_marks"]:
		if player.features.allowed.get(key, true):
			var k: String = key
			var name := "しらべられる ばしょ" if k == "hotspot" else "ためした コマンドの しるし"
			m.add_button("%s：%s" % [name, _onoff(_on(k))], func():
				player.set_feature(k, not _on(k))
				refill.call())
	m.add_back()


static func _next(list: Array, cur: float) -> float:
	var i := list.find(cur)
	return float(list[(i + 1) % list.size()])


static func _onoff(v: Variant) -> String:
	return "ON" if bool(v) else "OFF"
