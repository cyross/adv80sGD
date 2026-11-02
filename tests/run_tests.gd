extends SceneTree
## ヘッドレスで動かす自動テスト。
##   godot --headless --path . --script res://tests/run_tests.gd
## 失敗があれば終了コード 1 で終わる。

var _failed := 0
var _passed := 0


func _initialize() -> void:
	_test_expr()
	_test_condition()
	_test_dictionary()
	_test_markup()
	_test_manifest()
	_test_schema()
	_test_features()
	_test_visuals()
	_test_save()
	_test_stage1_scenario()
	_test_english()
	print("")
	print("passed: %d  failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


func eq(a: Variant, b: Variant, label: String) -> void:
	check(a == b, "%s  (got %s, want %s)" % [label, str(a), str(b)])


# ---------------------------------------------------------------- 式

func _test_expr() -> void:
	eq(AdvCondition.compile("has_key and money >= 100"),
		{"all": ["has_key", {"var": "money", "ge": 100}]}, "compile and/ge")
	eq(AdvCondition.compile("has_key && (visited(cellar) || has(lamp))"),
		{"all": ["has_key", {"any": [{"visited": "cellar"}, {"has": "lamp"}]}]}, "compile nested")
	eq(AdvCondition.compile("not scene == hallway"), {"not": {"scene": "hallway"}}, "compile not scene")
	eq(AdvCondition.compile("!a"), {"not": "a"}, "compile !")
	eq(AdvCondition.compile("money > price"), {"var": "money", "gt": {"var": "price"}}, "compile var rhs")
	eq(AdvCondition.compile("count(coin) >= 3"), {"count": "coin", "ge": 3}, "compile count")
	eq(AdvCondition.compile("chosen(q1, yes)"), {"chosen": ["q1", "yes"]}, "compile chosen")
	eq(AdvCondition.compile("name == \"ゆうじ\""), {"var": "name", "eq": "ゆうじ"}, "compile string")
	check(AdvCondition.compile("a and (b") == null, "compile error")
	eq(AdvExpr.parse_let("a = 1; b = a + 2").size(), 2, "parse_let")


func _test_condition() -> void:
	var s := AdvState.new()
	s.vars = {"has_key": true, "money": 120, "price": 50, "name": "ゆうじ"}
	s.items = {"lamp": 1, "coin": 3}
	s.scene = "hallway"
	s.visited = {"hallway": true}
	check(AdvCondition.evaluate("has_key and money >= 100", s), "eval and")
	check(AdvCondition.evaluate("has_key and money >= 100 and (visited(cellar) or has(lamp)) and not scene == cellar", s), "eval spec example")
	check(not AdvCondition.evaluate({"var": "money", "lt": 100}, s), "eval lt")
	check(AdvCondition.evaluate({"var": "money", "in": [100, 120]}, s), "eval in")
	check(AdvCondition.evaluate("money - price * 2 >= 20", s), "eval calc lhs")
	check(AdvCondition.evaluate("count(coin) == 3", s), "eval count")
	check(AdvCondition.evaluate("name == \"ゆうじ\"", s), "eval string eq")
	check(not AdvCondition.evaluate("undefined_flag", s), "undefined is false")
	eq(AdvCondition.eval_text("money - price * 2", s), 20, "eval_text int")
	eq(AdvCondition.eval_text("name + \"くん\"", s), "ゆうじくん", "eval_text string")
	check(AdvCondition.evaluate({"preset": "98"}, s, {"preset": "98.640x400"}), "preset prefix")


func _test_dictionary() -> void:
	var d := AdvDictionary.new()
	d.load_layer(AdvDictionary.STANDARD_JA)
	eq(d.match_verb("しらべる"), "EXAMINE", "verb exact")
	eq(d.match_verb("シラベル"), "EXAMINE", "verb katakana")
	eq(d.match_verb("しらべた"), "EXAMINE", "verb stem")
	eq(d.match_verb("ＭＩＲＵ"), "", "verb unknown")
	eq(d.normalize("ＡＢＣ　ドア"), "abc どあ", "normalize")


func _test_markup() -> void:
	var s := AdvState.new()
	s.vars = {"player": "ゆうじ"}
	var tpl := AdvTemplate.load_template("pc98_classic")
	check(tpl != null, "template loads")
	eq(tpl.screen_size, Vector2i(640, 400), "98 screen size")
	eq(AdvTextMarkup.to_bbcode("{player}くん、{{ok}", s, tpl), "ゆうじくん、{ok}", "markup var")
	eq(AdvTextMarkup.to_bbcode("[ruby=かぎ]鍵[/ruby][w=0.5]だ", s, tpl), "鍵（かぎ）だ", "markup ruby paren")
	eq(AdvTextMarkup.to_bbcode("[pal=2]赤[/pal]", s, tpl), "[color=#ff0000]赤[/color]", "markup pal")
	eq(AdvTextMarkup.to_bbcode("a[b", s, tpl), "a[lb]b", "markup escape")


# ---------------------------------------------------------------- マニフェスト

func _touch(root: String, rel: String) -> void:
	DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
	var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
	f.store_string("x")
	f.close()


func _codes(diags: Array) -> Array:
	return diags.map(func(d): return d["code"])


func _test_manifest() -> void:
	var root := "user://test_assets"
	_rmdir(root)
	for rel in ["bg/hallway.png", "bg/town/street.png", "bg/door.png", "chara/ayumi.png", "chara/ayumi@smile.png",
			"presets/88/bg/hallway.png", "presets/pc80/chara/ayumi@smile.png", "presets/98.640x400/bg/hallway.png",
			"cg/hallway.png", "se/door.wav", "misc/x.png", "_work/x.png", "bg/.hidden.png", "bg/Bad Name.png",
			"bg/notes.txt"]:
		_touch(root, rel)
	var res := AdvManifestGenerator.scan(root)
	var m: Dictionary = res["manifest"]["assets"]
	var codes := _codes(res["diags"])
	check(m.has("image:hallway") and m.has("image:town.street") and m.has("image:door") and m.has("se:door"), "manifest ids: %s" % str(m.keys()))
	eq(m["image:ayumi"].get("variants", {}).get("smile"), "chara/ayumi@smile.png", "variant")
	eq(m["image:hallway"]["by_preset"]["88"], "presets/88/bg/hallway.png", "by_preset machine")
	eq(m["image:ayumi"]["by_preset"]["pc80"]["variants"]["smile"], "presets/pc80/chara/ayumi@smile.png", "by_preset variant")
	check(codes.has("DUPLICATE_ID"), "duplicate bg/hallway and cg/hallway: %s" % str(codes))
	check(codes.has("UNKNOWN_FOLDER"), "unknown folder misc")
	check(codes.has("NAMING"), "naming warning")
	check(not m.has("image:x") and not m.has("image:.hidden") and not m.has("image:notes"), "ignored files")
	# 書き出しと最新かの確認
	eq(AdvManifestGenerator.write(root, res["manifest"]), OK, "write auto manifest")
	eq(AdvManifestGenerator.write(root, res["manifest"]), ERR_ALREADY_EXISTS, "write unchanged")
	check(AdvManifestGenerator.is_up_to_date(root, res["manifest"]), "up to date")
	# 手書きのマニフェストを重ねる
	var f := FileAccess.open(root + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"manifest_version": 1, "assets": {
		"theme1": {"type": "bgm", "file": "bgm/theme1.ogg", "loop_start": 12.5},
		"hallway": {"type": "image", "by_preset": {"pc80": "bg/door.png"}}}}))
	f.close()
	var manual := AdvManifestGenerator.check_manual(root)
	check(_codes(manual).has("ASSET_NOT_FOUND"), "manual manifest missing file")
	# 解決の順番：完全一致 → 機種 → グループ → file
	var a := AdvAssets.new()
	a.add_root(root)
	a.set_preset("98.640x400", "pc80")
	eq(a.resolve("image", "hallway"), root + "/presets/98.640x400/bg/hallway.png", "resolve exact preset")
	a.set_preset("88.640x200", "pc80")
	eq(a.resolve("image", "hallway"), root + "/presets/88/bg/hallway.png", "resolve machine")
	a.set_preset("SX1.640x200", "pc80")
	eq(a.resolve("image", "hallway"), root + "/bg/door.png", "resolve group (manual overrides)")
	eq(a.resolve("image", "ayumi", "smile"), root + "/presets/pc80/chara/ayumi@smile.png", "resolve variant by group")
	a.set_preset("FC.256x240", "console")
	eq(a.resolve("image", "hallway"), root + "/bg/hallway.png", "resolve default file")
	eq(a.resolve("image", "ayumi", "smile"), root + "/chara/ayumi@smile.png", "resolve variant")
	eq(a.resolve("se", "door"), root + "/se/door.wav", "resolve se namespace")
	check(a.has("bgm", "theme1") and not a.has("image", "theme1"), "namespaces separate")
	_rmdir(root)


func _rmdir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_rmdir(path + "/" + sub)
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------- スキーマと機能

func _test_schema() -> void:
	var good := {"start": "a", "scenes": {"a": {"objects": {"door": {"names": ["ドア"], "on": {
		"LOOK": "x", "OPEN": {"if": "k", "then": [{"goto": "a"}], "else": "y"}, "USE+key": [{"set": {"k": true}}, {"image.show": {"id": "a"}}]}}}}}}
	var d := AdvSchemaValidator.check(good, "scenario")
	eq(d.size(), 0, "valid scenario: %s" % str(d))
	var bad := {"start": 1, "scenes": {"a": {"objectz": {}, "objects": {"door": {"region": [1, 2], "on": {"look": "x"}}}}}}
	var codes := _codes(AdvSchemaValidator.check(bad, "scenario"))
	check(codes.has("SCHEMA_VIOLATION") and codes.has("UNKNOWN_KEY"), "invalid scenario: %s" % str(codes))
	var t = AdvJson.load_file("res://addons/adv80s/templates/pc98_classic/template.json")
	eq(AdvSchemaValidator.check(t, "template").size(), 0, "bundled template matches schema")
	var p = AdvJson.load_file("res://adv80s.project.json")
	eq(AdvSchemaValidator.check(p, "project").size(), 0, "project matches schema")
	var i = AdvJson.load_file("res://addons/adv80s/data/intent_schema.standard.json")
	eq(AdvSchemaValidator.check(i, "intent_schema").size(), 0, "intent schema matches schema")


func _test_features() -> void:
	var diags := []
	var f := AdvFeatures.resolve({"rewind": {"default": true}, "hint": {"allow": false}},
		{"hint": true, "message_log": false}, {"templates": 1}, {}, diags)
	check(not f.is_on("hint"), "project deny wins over template")
	check(not f.is_on("rewind") and _codes(diags).has("FEATURE_DEPENDENCY"), "rewind needs message_log")
	check(f.is_on("skip") and not f.is_on("era_switch"), "defaults")


# ---------------------------------------------------------------- 表示（プリセット、フィルター、切り替え演出）

func _test_visuals() -> void:
	var p := AdvPresets.resolve("88")
	eq(p["id"], "88.640x200", "88 default mode")
	check(p["line_double"] and p["palette"].size() == 8, "88 line double and 8 colors")
	eq(AdvPresets.resolve("X68K.512x512")["size"], Vector2i(512, 512), "X68K mode")
	eq(AdvPresets.resolve("FC")["visible"], Rect2i(0, 8, 256, 224), "FC visible area")
	eq(AdvPresets.resolve("GB")["group"], "handheld", "GB group")
	check(AdvPresets.resolve("21").is_empty(), "21 is not included")
	eq(AdvPresets.machines().size(), 26, "26 machines")

	var t98 := AdvTemplate.load_template("pc98_classic")
	var t88 := AdvTemplate.load_template("pc88_classic")
	eq(t88.screen_size, Vector2i(640, 200), "88 template size")
	eq(String(t88.get_section("ui").get("cursor", "")), "ui.cursor", "88 inherits ui from 98")
	eq(t88.region_rect("message"), Rect2i(16, 128, 416, 46), "88 overrides regions")
	t88.set_layout("fullscreen_cg")
	check(t88.region_rect("message").size == Vector2i.ZERO and t88.region_rect("picture").size == Vector2i(640, 200), "named layout hides windows")
	t88.set_layout("")

	var types := func(list: Array) -> Array: return list.map(func(f): return f["type"])
	eq(types.call(AdvVisuals.resolve_filters(t98)), ["scanline", "reduce", "crt"], "default filters for pc80")
	eq(types.call(AdvVisuals.resolve_filters(t98, {"mode": "append", "list": [{"type": "rgb_mask"}]})), ["scanline", "reduce", "crt", "rgb_mask"], "append filters")
	eq(types.call(AdvVisuals.resolve_filters(t98, [{"type": "mono", "color": "amber"}])), ["mono"], "array means replace")
	eq(AdvVisuals.resolve_filters(t98, {"mode": "none"}).size(), 0, "no filters")

	eq(AdvVisuals.resolve_transition(null, t98)["type"], "line_draw", "template default transition")
	eq(AdvVisuals.resolve_transition(null, t98, {}, false)["type"], "cut", "no default when not wanted")
	eq(AdvVisuals.resolve_transition("fade", t98)["type"], "dissolve", "replace table (fade -> dissolve)")
	var named := AdvVisuals.resolve_transition("door_open", t98, {"door_open": {"type": "wipe", "direction": "left", "duration": 0.8}})
	check(named["type"] == "wipe" and named["direction"] == "left" and is_equal_approx(float(named["duration"]), 0.8), "named transition: %s" % str(named))
	var ld := AdvVisuals.resolve_transition({"type": "line_draw", "speed": 124}, t98)
	check(is_equal_approx(float(ld["duration"]), 2.0), "line_draw duration from speed: %s" % str(ld))
	eq(AdvVisuals.resolve_transition("nonsense", t98)["type"], "cut", "unknown transition -> cut")


# ---------------------------------------------------------------- セーブ

class FixedKey extends AdvKeyProvider:
	var k: PackedByteArray
	func _init(seed_byte: int) -> void:
		k = PackedByteArray()
		for i in 32:
			k.append((i * 7 + seed_byte) & 0xff)
	func get_master_key() -> PackedByteArray:
		return k


func _test_save() -> void:
	var kp := FixedKey.new(1)
	var data := {"save_version": 1, "state": {"vars": {"money": 120, "name": "ゆうじ", "f": 1.5}, "items": {"key": 1}}, "log": [{"kind": "text", "body": "あ"}]}
	for level in ["none", "hmac", "hmac_aes"]:
		var b := AdvSave.encode(data, level, kp)
		var r := AdvSave.decode(b, kp)
		check(r["ok"] and r["data"] == data, "save round trip (%s): %s" % [level, r["error"]])
	var plain := AdvSave.encode(data, "hmac", kp)
	check(_contains_bytes(plain, "ゆうじ".to_utf8_buffer()), "hmac only: body readable")
	check(not _contains_bytes(AdvSave.encode(data, "hmac_aes", kp), "ゆうじ".to_utf8_buffer()), "hmac_aes: body encrypted")
	var tampered := plain.duplicate()
	var at := plain.hex_encode().find("ゆうじ".to_utf8_buffer().hex_encode()) / 2
	tampered[at + 2] = tampered[at + 2] ^ 0x01  # 「ゆ」の1バイトを書き換える
	eq(AdvSave.decode(tampered, kp)["error"], AdvSave.ERR_TAMPERED, "tamper detected")
	var warned := AdvSave.decode(tampered, kp, false, "warn")
	check(warned["ok"] and warned["warning"] == AdvSave.ERR_TAMPERED, "tamper warn mode loads")
	eq(AdvSave.decode(AdvSave.encode(data, "hmac", kp), FixedKey.new(2))["error"], AdvSave.ERR_KEY_MISMATCH, "key mismatch")
	var text := AdvSave.encode_text(data)
	eq(AdvSave.decode(text, kp)["error"], AdvSave.ERR_TEXT_DENIED, "text denied by default")
	var tr := AdvSave.decode(text, kp, true)
	check(tr["ok"] and tr["data"]["state"]["vars"]["money"] == 120, "text format loads")
	eq(AdvSave.decode("garbage".to_utf8_buffer(), kp)["error"], AdvSave.ERR_FORMAT, "bad format")
	# 鍵の仕組み
	check(kp.derive("hmac") != kp.derive("aes") and kp.derive("hmac").size() == 32, "derived keys differ")
	eq(kp.key_id().length(), 16, "key id length")
	var raw := FixedKey.new(3).k
	eq(AdvEmbeddedKeyProvider.unmask(AdvEmbeddedKeyProvider.mask(raw)), raw, "mask round trip")
	check(AdvEmbeddedKeyProvider.mask(raw) != raw, "masked key is not plain")
	# メッセージログ
	var log := AdvMessageLog.new()
	log.max_entries = 3
	for i in 5:
		log.add_text("line %d" % i)
	log.add_input("ドア しらべる")
	eq(log.entries.size(), 3, "log limit")
	eq(log.last_text()["body"], "line 4", "last text")
	eq(AdvTextMarkup.to_plain("[ruby=かぎ]鍵[/ruby]と[pal=2]a[b[/pal]", null, AdvTemplate.load_template("pc98_classic")), "鍵（かぎ）とa[b", "to_plain")


func _contains_bytes(hay: PackedByteArray, needle: PackedByteArray) -> bool:
	return hay.hex_encode().contains(needle.hex_encode())


# ---------------------------------------------------------------- 段階1のシナリオ

var core: AdvCore


func _say(text: String) -> Array:
	var r := AdvParserJa.parse(text, core)
	if r.has("reply"):
		return [AdvEvents.text(r["reply"])]
	return core.submit(r["intent"])


func _bodies(events: Array) -> String:
	var parts := PackedStringArray()
	for e in events:
		if e["type"] == "text.show":
			parts.append(e["args"]["body"])
	return " / ".join(parts)


func _test_stage1_scenario() -> void:
	core = AdvCore.new()
	core.setup({"seed": 1, "verbs": ["GIVE", "THINK"]})
	core.add_asset_roots(["res://tests/stage1/assets"])
	core.use_adapter(AdvJsonAdapter.new())
	eq(core.load_scenario(["res://tests/stage1/scenario/stage1.scenario.json"]), OK, "load scenario")
	var all := core.validate()
	var errors := all.filter(func(d): return d["severity"] != "info")
	eq(errors.size(), 0, "validate has no errors or warnings: %s" % str(errors))

	var ev := core.start()
	eq(ev[0]["type"], "scene.goto", "start: scene.goto")
	eq(ev[1]["type"], "image.show", "start: image.show")
	check(_bodies(ev).contains("うすぐらい"), "start: first text")
	eq(core.state.scene, "hallway", "scene is hallway")
	# モダン機能の記録と問い合わせ
	eq(core.query("objective")["text"], "ここから でる ほうほうを さがす", "objective")
	var hints: Array = core.query("hints")
	check(hints.size() == 1 and hints[0]["stages"] == 3 and hints[0]["revealed"] == 0 and hints[0]["texts"].is_empty(), "hints hidden at first: %s" % str(hints))
	check(core.reveal_hint("door") and core.query("hints", {"topic": "door"})[0]["texts"] == ["ドアには かぎが かかっている。"], "reveal hint")
	var fl: Dictionary = core.query("flow")
	check(fl["nodes"][0]["reached"] and not fl["nodes"][1]["reached"] and fl["edges"].size() == 2, "flow reached: %s" % str(fl))
	var chs: Array = core.query("chapters")
	check(chs[0]["unlocked"] and not chs[1]["unlocked"], "chapters unlocked by flow")
	var verb_ids: Array = core.query("verbs").map(func(v): return v["id"])
	check("GIVE" in verb_ids and "THINK" in verb_ids and not "PUSH" in verb_ids, "extended verbs from config: %s" % str(verb_ids))
	var hs: Array = core.query("hotspots")
	check(hs.size() == 2 and hs.all(func(h): return h["new"]), "hotspots new")
	check(_bodies(_say("かんがえる")).contains("きになる"), "THINK (extended verb)")
	check(_bodies(_say("プッシュ")).contains("わからない"), "PUSH not in dictionary words")
	core._commit([AdvEvents.make("verbs.update", {"verbs": ["THINK"], "mode": "remove"}),
		AdvEvents.make("hotspots.update", {"objects": ["plant"], "mode": "remove"})])
	check(not "THINK" in core.query("verbs").map(func(v): return v["id"]), "verbs.update remove")
	eq(core.query("hotspots").size(), 1, "hotspots.update remove")
	core._commit([AdvEvents.make("verbs.update", {"verbs": ["THINK"], "mode": "add"}), AdvEvents.make("hotspots.update", {"objects": ["plant"], "mode": "add"})])
	check("THINK" in core.query("verbs").map(func(v): return v["id"]) and core.query("hotspots").size() == 2, "updates add back")

	var t := _bodies(_say("ドア しらべる"))
	check(t.contains("かぎが かかっている"), "ドア しらべる → %s" % t)
	t = _bodies(_say("ドアを あける"))
	check(t.contains("かぎが かかっている"), "ドアを あける (locked) → %s" % t)
	eq(core.state.get_var("knocks"), 1, "knocks = 1")
	t = _bodies(_say("とびら みる"))
	check(t.contains("木の ドア"), "とびら みる → %s" % t)
	t = _bodies(_say("ほげほげ しらべる"))
	check(t.contains("わからない"), "unknown word → %s" % t)
	t = _bodies(_say("ドア"))
	check(t.contains("どう するのか"), "no verb → %s" % t)
	t = _bodies(_say("かぎ つかう"))
	check(t.contains("そんな ものは ない"), "no key yet → %s" % t)
	t = _bodies(_say("うえきばちを シラベル"))
	check(t.contains("かぎを みつけた"), "find key → %s" % t)
	check(core.state.has_item("key"), "has key")
	eq(core.query("notebook")[0]["title"], "ふるい かぎ", "notebook entry")
	eq(core.query("hints")[0]["revealed"], 0, "hint.set replaced hints")
	var hs2: Array = core.query("hotspots").filter(func(h): return h["id"] == "plant")
	check(not hs2[0]["new"] and "EXAMINE" in hs2[0]["tried_verbs"], "tried verbs on hotspot")
	t = _bodies(_say("アイテム"))
	check(t.contains("かぎ"), "items → %s" % t)
	t = _bodies(_say("かぎを ドアに つかう"))
	check(t.contains("カチリ"), "use key on door → %s" % t)
	check(core.state.get_var("door_unlocked") == true, "door unlocked")
	t = _bodies(_say("ドアをあける"))
	check(t.contains("ドアを あけた") and t.contains("ほこりっぽい"), "open door (no space) → %s" % t)
	eq(core.state.scene, "room", "scene is room")
	var ev2 := _say("しょうじょと はなす")
	t = _bodies(ev2)
	check(t.contains("たたいていたのは"), "talk (knocks>0) → %s" % t)
	check(ev2.back()["type"] == "choice.show", "stops at choice")
	eq(ev2.back()["args"]["choices"].size(), 2, "two choices")
	check(core.state.talked.has("ayumi_first"), "talked mark")
	eq(core.query("pending_choice")["id"], "who", "pending choice query")
	# 選択中にセーブして、別の項目を選んでから戻す
	var at_choice := core.save_state()
	t = _bodies(core.submit({"verb": "CHOOSE", "target": "secret"}))
	check(t.contains("……そう") and t.contains("きのうの よる") and t.contains("@マーク"), "choose secret (call returns) → %s" % t)
	check(core.state.chosen.has("who/secret"), "chosen mark")
	var ev3 := _say("しょうじょと はなす")
	check(ev3.back()["type"] == "choice.show" and ev3.back()["args"]["choices"].size() == 1, "once option hidden: %s" % str(ev3.back()))
	core.load_state(at_choice)
	eq(core.query("pending_choice")["id"], "who", "choice restored by load")
	t = _bodies(core.submit({"verb": "CHOOSE", "target": "detective"}))
	check(t.contains("よかった") and t.contains("@マーク"), "choose detective → %s" % t)
	check(core.state.get_var("met_ayumi") == true, "set inside choice")
	check(core.query("objective") == null, "objective cleared")
	check(core.query("flow")["nodes"].all(func(n): return n["reached"]), "all flow nodes reached")
	eq(core.query("notebook", {"category": "じんぶつ"}).size(), 1, "notebook by category")
	t = _bodies(_say("あゆみに メモ きく"))
	check(t.contains("まって") and t.contains("きのうの よる") and not t.contains("でない"), "goto dialogue does not return → %s" % t)
	t = _bodies(_say("あゆみに じけんについて きく"))
	check(t.contains("きのうの よる"), "ask topic → %s" % t)
	t = _bodies(_say("あゆみに じけん きく"))
	check(t.contains("きのうの よる"), "ask topic short → %s" % t)
	t = _bodies(_say("ろうかへ いく"))
	check(t.contains("もどってきた"), "move back → %s" % t)
	eq(core.state.scene, "hallway", "scene is hallway again")

	# 省略形の意図（コマンド選択などから）
	t = _bodies(core.submit({"verb": "LOOK", "target": "door", "source": "select"}))
	check(t.contains("木の ドア"), "shorthand intent → %s" % t)
	var req := core.submit({"verb": "OPEN", "source": "select"})
	check(req.size() == 1 and req[0]["type"] == "input.request" and req[0]["args"]["slot"] == "target" and String(req[0]["args"]["prompt"]).contains("なにを"), "missing slot → input.request: %s" % str(req))
	check(core.state.tried.has("LOOK:door"), "tried mark")

	# セーブとロード
	var saved := core.save_state()
	_say("ドアを あける")
	core.load_state(saved)
	eq(core.state.scene, "hallway", "load_state restores scene")


# ---------------------------------------------------------------- 英語式パーサー

func _en(text: String) -> String:
	var r := AdvParsers.parse("en", text, core)
	if r.has("reply"):
		return String(r["reply"])
	return _bodies(core.submit(r["intent"]))


func _test_english() -> void:
	core = AdvCore.new()
	core.setup({"seed": 1, "lang": "en", "verbs": ["GIVE"]})
	core.use_adapter(AdvJsonAdapter.new())
	core.load_scenario(["res://tests/stage1/scenario/stage1.scenario.json"])
	core.start()
	var r := AdvParsers.parse("en", "Open the door", core)
	check(r.has("intent") and r["intent"]["verb"] == "OPEN" and r["intent"]["slots"]["target"]["id"] == "door", "en: open the door")
	check(_en("x door").contains("かぎが かかっている"), "en: x door (scenario text)")
	check(_en("look at the door").contains("木の ドア"), "en: look at")
	eq(_en("frobnicate door"), "I don't know that word.", "en: unknown verb")
	eq(_en("open the key"), "You don't see that here.", "en: noun not here")
	check(_en("search flower pot").contains("かぎを みつけた"), "en: multiword noun")
	check(_en("use key on door").contains("カチリ"), "en: use key on door")
	check(_en("open door").contains("ほこりっぽい"), "en: open door → room")
	check(_en("give brass key to girl").contains("これは"), "en: give key to girl")
	var t := _en("talk to ayumi")
	check(t.contains("だれ"), "en: talk to (two-word verb)")
	core.submit({"verb": "CHOOSE", "target": "detective"})
	check(_en("ask ayumi about case").contains("きのうの よる"), "en: ask about topic")
	check(_en("i").contains("You are carrying"), "en: inventory abbreviation")
	check(_en("go to hallway").contains("もどってきた"), "en: go to")
