class_name AdvModernUI
extends RefCounted
## モダン機能の画面（第10章）：システムメニュー、ヒント、目的、手帳、フローチャート、チャプター選択、設定。
## どの画面も、有効になっている機能だけを出す。

var player: AdvPlayer


func _init(p: AdvPlayer) -> void:
	player = p


func _panel(title: String) -> AdvMenuPanel:
	return AdvMenuPanel.new().setup(title, player.template, Vector2(player.template.screen_size))


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
	m.add_button("せってい", func(): m.close(); open_settings())
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
	var v := AdvFlowView.new()
	v.setup(player.template, player.core.query("flow"))
	v.node_chosen.connect(func(id: String):
		m.close()
		player.jump_to_node(id))
	m.add_control(v)
	m.add_text("とうたつした ばしょを えらぶと、そこから やりなおせる。")
	m.add_back()
	await player.show_overlay(m)


func open_chapters() -> void:
	var m := _panel("チャプター")
	for c in player.core.query("chapters"):
		var node := String(c["node"])
		var ok: bool = c["unlocked"] and c["can_jump"]
		m.add_button(String(c["label"]) if c["unlocked"] else "？？？", func(): m.close(); player.jump_to_node(node), ok)
	m.add_back()
	m.focus_first()
	await player.show_overlay(m)


## 設定（文字の表示調整、オート送り、スキップ、フィルター、旧表示と新表示、読みやすいフォント、読み上げ、印の表示）。
func open_settings() -> void:
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
	if player.features.allowed.get("tts", true) and AdvPlayer._tts_available():
		m.add_button("よみあげ：%s" % _onoff(_on("tts")), func():
			player.set_feature("tts", not _on("tts"))
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
