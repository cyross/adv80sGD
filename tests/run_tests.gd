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
	_test_ink_story()
	_test_ink_conformance()
	_test_ink_random()
	_test_mag()
	_test_ink_adapter()
	_test_editor_form()
	_test_templates()
	_test_media()
	_test_layers_and_globals()
	_test_text_stops()
	_test_setup()
	_test_scenario_model()
	_test_stage12()
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

# ---------------------------------------------------------------- 段階12：外字、text.append

func _test_stage12() -> void:
	# [gaiji=ID]：画像は1文字として数え、文字で表すときは alt を使う
	AdvTextMarkup.gaiji_resolver = func(id: String) -> Dictionary:
		return {"path": "res://x/%s.png" % id, "alt": "<%s>" % id} if id == "heart" else {"alt": ""}
	var r := AdvTextMarkup.to_bbcode_stops("すき[gaiji=heart][p]です", null, null)
	eq(r["bbcode"], "すき[img]res://x/heart.png[/img]です", "gaiji: [img] in bbcode")
	eq(r["stops"][0]["at"], 3, "gaiji: counted as one character")
	eq(AdvTextMarkup.to_plain("すき[gaiji=heart]です", null, null), "すき<heart>です", "gaiji: alt in plain text")
	eq(AdvTextMarkup.to_plain("[gaiji=none]なし", null, null), "なし", "gaiji: unknown ID")
	eq(AdvTextMarkup.to_bbcode("[gaiji=none]なし", null, null), "なし", "gaiji: unknown ID in bbcode")
	eq(AdvTextMarkup.to_speech("すき[gaiji=heart]", null), "すき<heart>", "gaiji: alt is read aloud")
	AdvTextMarkup.gaiji_resolver = Callable()
	eq(AdvTextMarkup.to_bbcode("a[gaiji=heart]b", null, null), "ab", "gaiji: no resolver")
	# 減色しない外字の写し：色と点滅を外し、ほかの画像は透明にする
	var kp := AdvTextMarkup.GAIJI_KEEP_PREFIX + "k.tex"
	eq(AdvScreen.keep_bbcode("[color=#ff0000]あ[/color][img]%s[/img][pulse freq=2.0 color=#ffffff00 ease=-8.0]い[/pulse][img]res://x.png[/img]" % kp),
		"あ[img]%s[/img]い[img color=#00000000]res://x.png[/img]" % kp, "gaiji keep mirror bbcode")

	# メッセージログ：text.append は最後の文章に足す。入力をはさんだら新しい記録
	var log := AdvMessageLog.new()
	log.add_text("ドアには", "あゆみ")
	log.append_text("かぎが ある。")
	eq(log.entries.size(), 1, "log append: same entry")
	eq(log.entries[0]["body"], "ドアにはかぎが ある。", "log append: joined")
	log.add_input("しらべる")
	log.append_text("つづき")
	eq(log.entries.size(), 3, "log append: new entry after input")

	# JSON シナリオ：手順に書いた text.append に行のIDがつき、既読になる。validate は外字の素材を確かめる
	var base := "res://tests/_tmp_stage12"
	_rmdir(base)
	DirAccess.make_dir_recursive_absolute(base)
	var sf := FileAccess.open(base + "/a.scenario.json", FileAccess.WRITE)
	sf.store_string(JSON.stringify({"scenario_version": 1, "start": "a", "scenes": {"a": {"enter": [
		"ランプ[gaiji=lamp]", {"text.append": {"body": "が [gaiji=nothing] ある。{gold}"}}]}}}))
	sf.close()
	var c := AdvCore.new()
	c.setup({"seed": 1})
	c.use_adapter(AdvJsonAdapter.new())
	eq(c.load_scenario([base + "/a.scenario.json"]), OK, "stage12: scenario loads")
	var evs := c.start()
	var ap: Array = evs.filter(func(e): return e["type"] == "text.append")
	check(ap.size() == 1 and String(ap[0].get("id", "")) != "", "text.append gets a line id: %s" % str(ap))
	check(ap.size() == 1 and c.state.read.has(String(ap[0]["id"])), "text.append is marked as read")
	var diags := c.validate()
	var missing := diags.filter(func(d): return d["code"] == "ASSET_NOT_FOUND").map(func(d): return d["message"])
	check(missing.any(func(m): return String(m).contains("nothing")) and missing.any(func(m): return String(m).contains("lamp")),
		"validate: gaiji assets are checked: %s" % str(missing))
	check(diags.any(func(d): return d["code"] == "UNKNOWN_VARIABLE" and String(d["message"]).contains("gold")), "validate: variables in text.append")
	_rmdir(base)


# ---------------------------------------------------------------- シナリオエディタのデータ（6.8）

func _test_scenario_model() -> void:
	var base := "res://tests/_tmp_scmodel"
	var pj := base + "/adv80s.project.json"
	_rmdir(base)
	DirAccess.make_dir_recursive_absolute(base)
	var f := FileAccess.open(pj, FileAccess.WRITE)
	f.store_string(JSON.stringify({"project_version": 1, "scenarios": ["res://tests/ink/random.ink.json"]}))
	f.close()
	var m := AdvScenarioModel.new(pj)
	eq(m.root, "", "scmodel: no root yet")
	eq(m.set_root(base + "/scenario"), OK, "scmodel: set root")
	eq(AdvScenarioModel.new(pj).root, base + "/scenario", "scmodel: root stored in the project")
	DirAccess.make_dir_recursive_absolute(base + "/scenario/assets")
	var sid := m.create_scenario("Mansion")
	eq(sid, "mansion", "scmodel: scenario id from name")
	eq(m.create_scenario("やかた"), "scenario", "scmodel: Japanese name gets a fallback id")
	eq(m.scenarios().map(func(s): return s["id"]), ["mansion", "scenario"], "scmodel: scenario order")
	eq(m.scenario("mansion")["name"], "Mansion", "scmodel: scenario name")
	eq(m.chapters("mansion").map(func(c): return c["id"]), ["chapter1"], "scmodel: first chapter")
	var cid := m.create_chapter("mansion", "Second")
	eq(cid, "second", "scmodel: chapter created")
	var sc := m.create_scene("mansion", "second", "Hall")
	eq(sc, "hall", "scmodel: scene created")
	var d := m.load_chapter_data("mansion", "second")
	d["scenes"]["hall"]["exits"] = {"mansion_start": {"label": "もどる"}}
	d["scenes"]["hall"]["on"] = {"LOOK": [{"if": "visited(hall) and talked(chat)", "then": [{"goto": "mansion_start"}]}, {"call": "chat"}]}
	d["dialogues"] = {"chat": ["@a やあ"]}
	m.save_chapter_data("mansion", "second", d)
	eq(m.scenes("mansion", "second").map(func(x): return x["id"]), ["hall"], "scmodel: scene list")
	eq(m.rename("scene", ["mansion", "second", "hall"], "大広間"), OK, "scmodel: rename scene")
	eq(m.scenes("mansion", "second")[0]["name"], "大広間", "scmodel: renamed scene")
	m.rename("chapter", ["mansion", "second"], "第二章")
	eq(m.chapter("mansion", "second")["name"], "第二章", "scmodel: renamed chapter")
	# プロジェクト設定の scenarios：フォルダの外の Ink は残し、シナリオのファイルを並び順で書く
	var p: Dictionary = AdvJson.load_file(pj)
	eq(p["scenarios"][0], "res://tests/ink/random.ink.json", "scmodel: keep files outside the root")
	eq(p["scenarios"].slice(1), [base + "/scenario/mansion/_scenario.scenario.json", base + "/scenario/mansion/chapter1.scenario.json",
		base + "/scenario/mansion/second.scenario.json", base + "/scenario/scenario/_scenario.scenario.json",
		base + "/scenario/scenario/chapter1.scenario.json"], "scmodel: synced scenarios")
	eq(p.get("entry"), "mansion_start", "scmodel: entry is the first scenario's start")
	# シーンの複写：ID は新しく、自分への参照は付け替える
	var made := m.duplicate_scenes("mansion", "second", ["hall"], 2)
	eq(made, ["hall_copy", "hall_copy_2"], "scmodel: duplicated scenes")
	var hc: Dictionary = m.load_chapter_data("mansion", "second")["scenes"]["hall_copy"]
	eq(hc["on"]["LOOK"][0]["if"], "visited(hall_copy) and talked(chat)", "scmodel: self reference remapped")
	eq(hc["name"], "大広間 のコピー", "scmodel: copy name")
	m.duplicate_scenes("mansion", "second", ["hall"], 1, "scenario", "chapter1")
	check(m.load_chapter_data("scenario", "chapter1")["scenes"].has("hall_copy_3"), "scmodel: copy a scene to another scenario")
	# チャプターの複写（別のシナリオへ）：シーン・会話の ID と参照を付け替える
	var mc := m.duplicate_chapters("mansion", ["second"], 1, "scenario")
	eq(mc, ["second"], "scmodel: chapter copied to another scenario")
	var cd := m.load_chapter_data("scenario", "second")
	check(cd["scenes"].has("hall_copy_4") and cd["dialogues"].has("chat_copy"), "scmodel: new ids in the copied chapter: %s" % str(cd["scenes"].keys()))
	var look: Array = cd["scenes"]["hall_copy_4"]["on"]["LOOK"]
	eq(look[0]["if"], "visited(hall_copy_4) and talked(chat_copy)", "scmodel: condition remapped")
	eq(look[1]["call"], "chat_copy", "scmodel: call remapped")
	eq(look[0]["then"][0]["goto"], "mansion_start", "scmodel: references outside are kept")
	# シナリオの複写：start と exits も付け替える
	var ms := m.duplicate_scenarios(["mansion"])
	eq(ms, ["mansion_copy"], "scmodel: scenario copied")
	eq(m.load_scenario_data("mansion_copy").get("start"), "mansion_start_copy", "scmodel: start remapped")
	var c2 := m.load_chapter_data("mansion_copy", "second")
	check(c2["scenes"].values().any(func(x): return x.get("exits", {}).has("mansion_start_copy")), "scmodel: exits remapped")
	eq(m.scenario("mansion_copy")["name"], "Mansion のコピー", "scmodel: scenario copy name")
	# ゲームとして読める（ID がぶつからない）
	var core := AdvCore.new()
	core.setup({"seed": 1})
	core.use_adapter(AdvJsonAdapter.new())
	var files: Array = AdvJson.load_file(pj)["scenarios"].filter(func(x): return String(x).ends_with(".scenario.json"))
	eq(core.load_scenario(files), OK, "scmodel: all files load")
	eq(core.validate().filter(func(x): return x["code"] == "DUPLICATE_ID").size(), 0, "scmodel: no duplicate ids")
	# 消す
	m.delete_scenes("mansion", "second", ["hall_copy_2"])
	check(not m.load_chapter_data("mansion", "second")["scenes"].has("hall_copy_2"), "scmodel: scene deleted")
	m.delete_chapters("scenario", ["second"])
	eq(m.chapters("scenario").map(func(x): return x["id"]), ["chapter1"], "scmodel: chapter deleted")
	# 古い形（フォルダの直下のファイル）：「フォルダの外」のシナリオとして見え、プロジェクト設定では元の順のまま
	var lp := base + "/scenario/zz_old.scenario.json"
	AdvScenarioModel._save_json(lp, {"scenario_version": 1, "start": "old", "scenes": {"old": {"enter": "むかし"}}})
	var pp: Dictionary = AdvJson.load_file(pj)
	pp["scenarios"].insert(1, lp)
	AdvScenarioModel._save_json(pj, pp)
	check(m.scenarios().any(func(x): return x["loose"] and x["id"] == AdvScenarioModel.LOOSE_ID), "scmodel: loose files are a scenario")
	eq(m.chapters(AdvScenarioModel.LOOSE_ID).map(func(x): return x["id"]), ["zz_old"], "scmodel: loose file is a chapter")
	m.sync_project()
	eq(AdvJson.load_file(pj)["scenarios"][1], lp, "scmodel: loose file keeps its place")
	check(not m.scenarios().any(func(x): return x["id"] == "assets"), "scmodel: folders without scenario files are not listed")
	DirAccess.remove_absolute(lp)
	m.sync_project()
	m.delete_scenarios(["mansion_copy"])
	eq(m.scenarios().map(func(x): return x["id"]), ["mansion", "scenario"], "scmodel: scenario deleted")
	check(not AdvJson.load_file(pj)["scenarios"].any(func(x): return String(x).contains("mansion_copy")), "scmodel: project synced after delete")
	_rmdir(base)


# ---------------------------------------------------------------- セットアップ（6.7）とコマンド方式（4.5）

func _test_setup() -> void:
	var base := "res://tests/_tmp_setup"
	var pj := base + "/adv80s.project.json"
	_rmdir(base)
	eq(AdvSetup.to_id("My Game 2"), "my_game_2", "setup: id from title")
	check(AdvSetup.to_id("やかたの なぞ") != "", "setup: id from a Japanese title is not empty")
	check(AdvSetup.template_list().any(func(t): return t["id"] == "pc98_classic"), "setup: template list")
	var opts := {"game_id": "yakata", "title": "やかたの なぞ", "template": "pc98_classic", "command": "verb_click",
		"devices": ["keyboard", "mouse"], "base_dir": base + "/game"}
	eq(Array(AdvSetup.check(opts)), [], "setup: options ok")
	check(not AdvSetup.check(opts.merged({"game_id": "1bad"}, true)).is_empty(), "setup: bad game id")
	check(not AdvSetup.check(opts.merged({"title": " "}, true)).is_empty(), "setup: empty title")
	check(not AdvSetup.check(opts.merged({"template": "zzz"}, true)).is_empty(), "setup: unknown template")
	check(not AdvSetup.check(opts.merged({"devices": []}, true)).is_empty(), "setup: no devices")
	check(not AdvSetup.check(opts.merged({"command": "verb_cursor", "devices": ["keyboard"]}, true)).is_empty(), "setup: verb_cursor needs a pointer")
	check(not AdvSetup.check(opts.merged({"command": "parser", "devices": ["mouse"]}, true)).is_empty(), "setup: parser needs a keyboard")
	check(not AdvSetup.check(opts.merged({"base_dir": "res://addons/x"}, true)).is_empty(), "setup: base dir under addons")
	var pl := AdvSetup.plan(opts, pj)
	eq(pl["settings"].get("display/window/size/viewport_width"), 640, "setup: viewport from the template")
	eq(pl["settings"].get("application/run/main_scene"), base + "/game/main.tscn", "setup: main scene")
	var res := AdvSetup.apply(opts, pj, false)
	eq(res["errors"], [], "setup: apply")
	for d in AdvSetup.ASSET_DIRS:
		check(DirAccess.dir_exists_absolute("%s/game/assets/%s" % [base, d]), "setup: asset folder %s" % d)
	check(FileAccess.file_exists(base + "/game/main.tscn") and FileAccess.file_exists(base + "/game/assets/manifest.json"), "setup: entry scene and manifest")
	var p = AdvJson.load_file(pj)
	check(p is Dictionary, "setup: project written")
	eq(p.get("game_id"), "yakata", "setup: game_id")
	eq(p.get("title"), "やかたの なぞ", "setup: title")
	eq(p.get("template"), "pc98_classic", "setup: template")
	eq(p.get("inputs", {}).get("enabled"), ["verb_click"], "setup: command method")
	eq(p.get("input_devices"), ["keyboard", "mouse"], "setup: devices")
	eq(p.get("scenarios"), [base + "/game/scenario/main/_scenario.scenario.json", base + "/game/scenario/main/chapter1.scenario.json"], "setup: scenarios")
	eq(p.get("ext", {}).get("adv80s_editor", {}).get("scenario_root"), base + "/game/scenario", "setup: scenario root")
	eq(_codes(AdvSchemaValidator.check(p, "project")), [], "setup: project matches schema")
	for f in p["scenarios"]:
		eq(_codes(AdvSchemaValidator.check(AdvJson.load_file(f), "scenario")), [], "setup: scenario matches schema " + String(f).get_file())
	eq(_codes(AdvSchemaValidator.check(AdvJson.load_file(base + "/game/assets/manifest.json"), "manifest")), [], "setup: manifest matches schema")
	var c := AdvCore.new()
	c.setup({"seed": 1})
	c.use_adapter(AdvJsonAdapter.new())
	eq(c.load_scenario(p["scenarios"]), OK, "setup: scenario loads")
	eq(c.validate().filter(func(d): return d["severity"] == "error").size(), 0, "setup: scenario validates")
	var evs := c.start()
	check(_bodies(evs).contains("やかたの なぞ"), "setup: scenario starts: %s" % _bodies(evs))
	var scene = load(base + "/game/main.tscn")
	check(scene is PackedScene, "setup: main scene loads")
	# 2回目：あるファイルは残し、プロジェクト設定はセットアップの項目だけを書き換える
	p["x.keep"] = 1
	p["inputs"]["click_verb"] = "LOOK"
	var f := FileAccess.open(pj, FileAccess.WRITE)
	f.store_string(JSON.stringify(p))
	f.close()
	var res2 := AdvSetup.apply(opts.merged({"command": "template", "title": "べつの なまえ"}, true), pj, false)
	eq(res2["errors"], [], "setup: apply again")
	check((res2["skipped"] as Array).has(base + "/game/main.tscn") and (res2["created"] as Array).is_empty(), "setup: existing files kept: %s" % str(res2["created"]))
	var p2 = AdvJson.load_file(pj)
	eq(p2.get("x.keep"), 1, "setup: other project keys kept")
	eq(p2.get("title"), "べつの なまえ", "setup: title updated")
	eq(p2.get("inputs"), {"click_verb": "LOOK"}, "setup: enabled removed for the template default")
	eq(AdvSetup.defaults(pj).get("command"), "template", "setup: defaults read the project")

	# 物の click は hotspots の verb になる
	var sf := FileAccess.open(base + "/click.scenario.json", FileAccess.WRITE)
	sf.store_string(JSON.stringify({"scenario_version": 1, "start": "a", "scenes": {"a": {"objects": {
		"box": {"region": [0, 0, 10, 10], "click": "OPEN", "on": {"OPEN": "あいた。"}}, "cat": {"region": [20, 0, 10, 10]}}}}}))
	sf.close()
	var c2 := AdvCore.new()
	c2.setup({"seed": 1})
	c2.use_adapter(AdvJsonAdapter.new())
	eq(c2.load_scenario([base + "/click.scenario.json"]), OK, "click: scenario loads")
	c2.start()
	var hs: Array = c2.query("hotspots")
	eq(hs.filter(func(h): return h["id"] == "box")[0].get("verb"), "OPEN", "hotspots: click verb")
	check(not hs.filter(func(h): return h["id"] == "cat")[0].has("verb"), "hotspots: no verb without click")
	_rmdir(base)

	# プロジェクトの inputs はテンプレートの inputs を上書きする
	var t := AdvTemplate.load_template("pc98_classic")
	var before: Array = t.get_section("inputs").get("enabled", [])
	t.overrides = {"inputs": {"enabled": ["context"], "click_verb": "LOOK"}}
	eq(t.get_section("inputs").get("enabled"), ["context"], "template overrides: enabled")
	eq(t.get_section("inputs").get("click_verb"), "LOOK", "template overrides: new key")
	t.overrides = {}
	eq(t.get_section("inputs").get("enabled", []), before, "template overrides: cleared")
	eq(_codes(AdvSchemaValidator.check({"template": "pc98_classic", "game_id": "a_1", "title": "T", "input_devices": ["mouse"],
		"inputs": {"enabled": ["verb_cursor"], "context_verbs": {"look": "LOOK"}, "verb_cursors": {"TAKE": "take"}, "item_verb": "USE", "context_alt_verb": "LOOK"}}, "project")), [], "schema: project inputs")
	check(not AdvSchemaValidator.check({"game_id": "Bad Id"}, "project").is_empty(), "schema: bad game_id")


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
	# シーンのスプライト（6.4）
	var shows := ev.filter(func(e): return e["type"] == "sprite.show").map(func(e): return e["args"]["id"])
	eq(shows, ["lamp", "sparkle"], "scene sprites shown")
	var lamp_ev: Dictionary = ev.filter(func(e): return e["type"] == "sprite.show")[0]
	check(lamp_ev["args"]["keep"] == false and lamp_ev["args"]["scene"] == "hallway" and not lamp_ev["args"].has("when"), "sprite.show args: %s" % str(lamp_ev["args"]))
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
	check(hs.size() == 3 and hs.all(func(h): return h["new"]), "hotspots new")
	check(hs.any(func(h): return h["id"] == "lamp" and h.get("sprite") == "lamp"), "sprite hotspot: %s" % str(hs))
	check(hs.any(func(h): return h["id"] == "plant" and h.get("cursor") == "take"), "hotspot cursor")
	check(_bodies(_say("かんがえる")).contains("きになる"), "THINK (extended verb)")
	check(_bodies(_say("プッシュ")).contains("わからない"), "PUSH not in dictionary words")
	core._commit([AdvEvents.make("verbs.update", {"verbs": ["THINK"], "mode": "remove"}),
		AdvEvents.make("hotspots.update", {"objects": ["plant"], "mode": "remove"})])
	check(not "THINK" in core.query("verbs").map(func(v): return v["id"]), "verbs.update remove")
	eq(core.query("hotspots").size(), 2, "hotspots.update remove")
	core._commit([AdvEvents.make("verbs.update", {"verbs": ["THINK"], "mode": "add"}), AdvEvents.make("hotspots.update", {"objects": ["plant"], "mode": "add"})])
	check("THINK" in core.query("verbs").map(func(v): return v["id"]) and core.query("hotspots").size() == 3, "updates add back")

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
	var key_ev := _say("うえきばちを シラベル")
	t = _bodies(key_ev)
	check(t.contains("かぎを みつけた"), "find key → %s" % t)
	var hides := key_ev.filter(func(e): return e["type"] == "sprite.hide")
	check(hides.size() == 1 and hides[0]["args"]["id"] == "sparkle" and hides[0]["args"]["transition"] == "fade", "sprite hidden when condition fails: %s" % str(hides))
	eq(_bodies(_say("ランプを しらべる")).contains("あつい"), true, "sprite object reacts")
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
	var open_ev := _say("ドアをあける")
	t = _bodies(open_ev)
	check(t.contains("ドアを あけた") and t.contains("ほこりっぽい"), "open door (no space) → %s" % t)
	check(open_ev.any(func(e): return e["type"] == "sprite.hide" and e["args"]["id"] == "lamp"), "scene sprites leave with the scene")
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


# ---------------------------------------------------------------- Ink（段階7）
# inklecate が手元にないため、tests/ink/*.ink.json は inklecate の出力の形に合わせて手で書いたもの。

func _texts(lines: Array) -> Array:
	return lines.map(func(l): return l["text"])


func _test_ink_story() -> void:
	var j = AdvInkJson.parse('{"a": 1, "b": 1.5, "c": [true, null, "x\\u3042"]}')
	check(j["a"] is int and j["b"] is float and j["c"][2] == "x\u3042", "ink json keeps int/float: %s" % str(j))
	eq(AdvInkStory._clean("  a   b \n  c  "), "a b\nc", "clean whitespace")

	var s := AdvInkStory.new()
	eq(s.load_json(FileAccess.get_file_as_string("res://tests/ink/sample.ink.json")), OK, "ink load")
	eq(s.globals, {"met": false, "coins": 3}, "ink global decl")
	var lines := s.continue_maximally()
	eq(_texts(lines), ["Hello world!", "First time."], "ink glue + conditional")
	eq(lines[0]["tags"], ["greeting"], "ink line tag")
	var ch := s.current_choices
	eq(ch.map(func(c): return c["text"]), ["Ask about the key", "Leave"], "ink choices (choice-only and start content)")
	eq(ch[0]["tags"], ["intent:ASK:ayumi"], "ink choice tag")
	eq(s.globals["met"], true, "ink assignment")
	s.choose_choice_index(0)
	lines = s.continue_maximally()
	eq(_texts(lines), ["\"The key?\"", "She nods.", "Again."], "ink choice output and loop")
	eq(lines[0]["tags"], ["intent:ASK"], "ink tag after text")
	eq(s.current_choices.map(func(c): return c["text"]), ["Leave"], "ink once-only choice hidden")
	var saved := s.save_state()
	s.choose_choice_index(0)
	eq(_texts(s.continue_maximally()), ["Leave", "Quietly."], "ink start content replayed")
	check(not s.can_continue() and s.errors.is_empty(), "ink end")
	s.load_state(saved)
	eq(s.current_choices.size(), 1, "ink load_state restores choices")
	s.choose_choice_index(0)
	eq(_texts(s.continue_maximally()), ["Leave", "Quietly."], "ink after load")

	var calls := []
	s.external_functions["event"] = func(a): calls.append(a); return null
	s.choose_path("shop")
	lines = s.continue_maximally()
	# タグだけの行は、本文が空の行になる（C# 版と同じ）
	eq(_texts(lines), ["", "Coins: 5", "Visited start 1 times.", "Poor."], "ink function, CNT?, conditional")
	eq(lines[0]["tags"], ["shop_tag"], "ink knot tag")
	eq(calls, [["se.play", "{\"id\":\"knock\"}"]], "ink external function args")
	eq(s.tags_at_path("shop"), ["shop_tag"], "ink tags_at_path")
	s.choose_path("auto")
	eq(_texts(s.continue_maximally()), ["Auto."], "ink invisible default choice")
	s.choose_path("tun")
	eq(_texts(s.continue_maximally()), ["Inside.", "Back."], "ink tunnel")
	check(s.errors.is_empty(), "ink no errors: %s" % str(s.errors))
	var changed := []
	s.on_variable_changed = func(n, v): changed.append([n, v])
	s.set_global("coins", 4)
	s.choose_path("shop")
	s.continue_maximally()
	eq(changed, [["coins", 6]], "ink variable change callback")


## MAG（MAKI02）の画像を読む：tools/build_test_mag.py で作った画像と、同じ内容の PNG を比べる。
func _test_mag() -> void:
	for n in ["mag16", "mag256"]:
		var m := AdvMag.new()
		var img := m.decode(FileAccess.get_file_as_bytes("res://tests/media/%s.mag" % n))
		var want := Image.new()
		want.load_png_from_buffer(FileAccess.get_file_as_bytes("res://tests/media/%s.png" % n))
		want.convert(Image.FORMAT_RGBA8)
		check(img != null and img.get_data() == want.get_data(), "mag %s decodes pixel-exact: %s" % [n, m.error])
	eq(AdvMag.new().colors, 16, "mag default colours")
	var bad := AdvMag.new()
	check(bad.decode(PackedByteArray([1, 2, 3])) == null and bad.error != "", "mag: not a MAG file")
	var cut := FileAccess.get_file_as_bytes("res://tests/media/mag16.mag").slice(0, 200)
	var bad2 := AdvMag.new()
	check(bad2.decode(cut) == null and bad2.error != "", "mag: truncated file: %s" % bad2.error)
	var r = load("res://tests/media/mag16.mag")
	check(r is AdvImageFrames and r.frames.size() == 1 and r.size == Vector2i(64, 40), "mag imports as a still image")


## RANDOM、SEED_RANDOM、シャッフルが本家（inklecate -p、tests/ink/random.expected.txt）と同じになるか。
func _test_ink_random() -> void:
	eq([AdvDotNetRandom.new(0).next(), AdvDotNetRandom.new(42).next(), AdvDotNetRandom.new(1).next()], [1559595546, 1434747710, 534011718], ".NET Random first values")
	var r := AdvDotNetRandom.new(-7)
	var r2 := AdvDotNetRandom.new(7)
	eq([r.next(), r.next()], [r2.next(), r2.next()], ".NET Random: negative seed uses its absolute value")
	eq(AdvDotNetRandom.wrap32(2147483647 + 1), -2147483648, "wrap32 overflow")
	var s := AdvInkStory.new()
	s.load_json(FileAccess.get_file_as_string("res://tests/ink/random.ink.json"))
	var out := PackedStringArray()
	for l in s.continue_maximally():
		out.append(l["text"])
	var want := FileAccess.get_file_as_string("res://tests/ink/random.expected.txt").replace("\r", "").strip_edges()
	var got := "\n".join(out).strip_edges()
	check(got == want, "ink RANDOM and shuffle match inklecate -p:\n%s" % got)
	check(s.errors.is_empty(), "ink random no errors: %s" % str(s.errors))


## inklecate -p の出力（tests/ink/conformance.expected.txt）と同じになるか。
func _test_ink_conformance() -> void:
	var s := AdvInkStory.new()
	s.load_json(FileAccess.get_file_as_string("res://tests/ink/conformance.ink.json"))
	var picks := [1, 2, 1, 2, 1, 1, 2]
	var out := PackedStringArray()
	var prefix := ""
	while true:
		for l in s.continue_maximally():
			out.append(prefix + l["text"])
			prefix = ""
			if not l["tags"].is_empty():
				out.append("# tags: " + ", ".join(PackedStringArray(l["tags"])))
		var ch := s.current_choices
		if ch.is_empty() or picks.is_empty():
			break
		out.append("")
		for c in ch:
			out.append("%d: %s" % [c["index"] + 1, c["text"]])
		prefix = "?> "
		s.choose_choice_index(int(picks.pop_front()) - 1)
	var want := FileAccess.get_file_as_string("res://tests/ink/conformance.expected.txt").replace("\r", "").strip_edges()
	var got := "\n".join(out).strip_edges()
	check(got == want, "ink conformance with inklecate -p:\n%s" % got)
	check(s.errors.is_empty(), "ink conformance no errors: %s" % str(s.errors))


func _test_ink_adapter() -> void:
	var c := AdvCore.new()
	c.setup({"seed": 1})
	c.add_asset_roots(["res://tests/stage1/assets"])
	c.use_adapter(AdvJsonAdapter.new())
	eq(c.load_scenario(["res://tests/ink/hand.scenario.json", "res://tests/ink/sample.ink.json"]), OK, "ink: load")
	check(c.adapters_by_name.has("ink"), "ink adapter registered")
	var errs := c.validate().filter(func(d): return d["severity"] == "error")
	eq(errs.size(), 0, "ink: validate %s" % str(errs))
	c.start()
	var ev := c.submit({"verb": "TALK", "target": "ayumi"})
	eq(_bodies(ev), "まえおき。 / First time.", "ink: JSON hands over to ink")
	var cs := ev.filter(func(e): return e["type"] == "choice.show")
	check(cs.size() == 1 and cs[0]["args"]["choices"].size() == 2, "ink: choice.show")
	check(ev.all(func(e): return not String(e["type"]).begins_with("adapter.")), "ink: adapter events are hidden")
	eq(c.state.get_var("met"), true, "ink: variable written back to Core")
	eq(c.adapter, c.adapters_by_name["ink"], "ink: ink adapter is on top")
	var pc = c.query("pending_choice")
	check(pc is Dictionary and pc["accepts_intents"], "ink: pending choice accepts intents")
	ev = c.submit({"verb": "ASK", "target": "ayumi", "topic": "key"})
	eq(_bodies(ev), "\"The key?\" / She nods. / Again.", "ink: intent tag picks a choice")
	var saved := c.save_state()
	ev = c.submit({"verb": "CHOOSE", "target": "c0"})
	eq(_bodies(ev), "Leave / Quietly. / はなしおえた。", "ink: back to JSON after END")
	eq(c.adapter, c.adapters_by_name["main"], "ink: JSON is on top again")
	c.load_state(saved)
	eq(c.adapter, c.adapters_by_name["ink"], "ink: load restores adapter stack")
	ev = c.submit({"verb": "CHOOSE", "target": "c0"})
	eq(_bodies(ev), "Leave / Quietly. / はなしおえた。", "ink: resume after load")
	ev = c.submit({"verb": "LOOK", "target": "register"})
	eq(_bodies(ev), "Coins: 12 / Visited start 1 times. / Rich. / レジを はなれた。", "ink: Core variables copied into ink")
	eq(c.state.get_var("coins"), 12, "ink: changed variable returned")
	check(ev.any(func(e): return e["type"] == "se.play" and e["args"]["id"] == "knock"), "ink: event() external")
	ev = c.submit({"verb": "OPEN", "target": "register"})
	var shows := ev.filter(func(e): return e["type"] == "text.show")
	eq(shows[0]["args"].get("speaker"), "ayumi", "ink: @speaker")
	eq(shows[0]["args"].get("name"), "あゆみ", "ink: speaker name from JSON characters")
	eq(shows[1]["args"].get("speaker"), "ayumi", "ink: speaker tag")
	check(ev.any(func(e): return e["type"] == "voice.play"), "ink: voice tag")
	check(ev.any(func(e): return e["type"] == "image.show" and e["args"]["layer"] == "bg"), "ink: bg tag")
	check(ev.any(func(e): return e["type"] == "bgm.play"), "ink: JSON event tag")
	eq(shows[2]["ext"].get("tags"), ["custom"], "ink: other tags in ext")
	var ev2 := c.submit({"verb": "LOOK", "target": "register"})
	var shows2 := ev2.filter(func(e): return e["type"] == "text.show")
	eq(shows2[0]["ext"].get("tags"), ["shop_tag"], "ink: tag-only line carried to the next line")
	check(String(shows[0]["id"]).begins_with("ink:talk#"), "ink: line id")
	eq(_bodies(ev), "Hi there. / Narration. / Mood. / No key. / おわり。", "ink: two ink calls in a row")
	c.state.items["key"] = 1
	ev = c.submit({"verb": "OPEN", "target": "register"})
	check(_bodies(ev).contains("Have key.") and c.state.has_item("coin"), "ink: has_item / item_add")

	# 段階1のサンプルに足した Ink の会話
	var c4 := AdvCore.new()
	c4.setup({"seed": 1})
	c4.add_asset_roots(["res://tests/stage1/assets"])
	c4.use_adapter(AdvJsonAdapter.new())
	c4.load_scenario(["res://tests/stage1/scenario/stage1.scenario.json", "res://tests/stage1/scenario/stage1_talk.ink.json"])
	var e4 := c4.validate().filter(func(d): return d["severity"] != "info")
	eq(e4.size(), 0, "stage1 + ink: validate %s" % str(e4))
	c4.start("room")
	ev = c4.submit({"verb": "ASK", "target": "ayumi", "topic": "window"})
	eq(_bodies(ev), "まどの そと？ / ……しらない ひとには はなせない。 / あゆみは また まどの そとを みつめた。", "stage1 ink: not met yet")
	c4._commit([AdvEvents.make("state.set", {"name": "met_ayumi", "value": true}), AdvEvents.make("item.add", {"id": "key"})])
	ev = c4.submit({"verb": "ASK", "target": "ayumi", "topic": "window"})
	var cs4 := ev.filter(func(e): return e["type"] == "choice.show")
	eq(cs4[0]["args"]["choices"].map(func(x): return x["label"]), ["あかりの ことを きく", "かぎを みせる", "はなしを おえる"], "stage1 ink: choices")
	ev = c4.submit({"verb": "CHOOSE", "target": "c0"})
	check(c4.state.get_var("saw_lights") == true and c4.state.notebook.has("lights"), "stage1 ink: variable and notebook")
	ev = c4.submit({"verb": "CHOOSE", "target": "c1"})
	eq(_bodies(ev), "あの やかたに、 なにか あるのかも しれない。 / あゆみは また まどの そとを みつめた。", "stage1 ink: end and back to JSON")

	# Ink だけのゲーム
	var c2 := AdvCore.new()
	c2.setup({})
	c2.use_adapter(AdvJsonAdapter.new())
	c2.load_scenario(["res://tests/ink/sample.ink.json"])
	eq(c2.adapter_name(c2.adapter), "ink", "ink only: ink is the main adapter")
	ev = c2.start()
	eq(_bodies(ev), "Hello world! / First time.", "ink only: start")

	# 確認
	var c3 := AdvCore.new()
	c3.setup({})
	c3.use_adapter(AdvJsonAdapter.new())
	c3.load_scenario(["res://tests/ink/bad.scenario.json", "res://tests/ink/list.ink.json"])
	var codes := _codes(c3.validate())
	check("INK_MISSING_KNOT" in codes and "INK_LIST" in codes, "ink validate codes: %s" % str(codes))


# ---------------------------------------------------------------- エディタの編集フォーム

func _test_editor_form() -> void:
	var f := AdvSchemaForm.new()
	var schema := AdvSchemaValidator.load_schema("template")
	var data := {"template_version": 1, "id": "t", "fonts": {"main": [{"asset": "dot16", "size": 16}]}}
	f.setup(schema, data)
	var fonts_main = f._schema_at(["fonts", "main"])
	eq(f.kind_of(f.pick_branch(fonts_main, data["fonts"]["main"])), "array", "form: anyOf picks array for a list")
	eq(f.kind_of(f.pick_branch(fonts_main, {"asset": "x"})), "object", "form: anyOf picks object")
	eq(f.kind_of(f.pick_branch(fonts_main, null)), "object", "form: default branch skips null")
	f.set_at(["fonts", "main", 0, "size"], 12)
	eq(data["fonts"]["main"][0]["size"], 12, "form: set_at")
	f.remove_at(["fonts", "main", 0, "size"])
	check(not data["fonts"]["main"][0].has("size"), "form: remove_at")
	eq(AdvSchemaForm.pointer(["assets", "se:knock/x"]), "/assets/se:knock~1x", "form: JSON Pointer escape")
	eq(AdvSchemaForm.normalize({"a": 1.0, "b": null, "c": [2.5]}), {"a": 1, "b": null, "c": [2.5]}, "form: normalize keeps null")
	var ps := AdvSchemaValidator.load_schema("project")
	f.setup(ps, {})
	eq(f.default_for(f.pick_branch(f._schema_at(["missing_asset"]), null)), "placeholder", "form: enum default")
	check(f.get_root() != null and f.get_root().get_child_count() > 5, "form: absent properties listed")
	f.free()
	var scr = load("res://addons/adv80s/editor/adv_editor_screen.gd")
	eq(scr.entry_for_file("res://g/assets/bgm/town@night.ogg", "res://g/assets", AdvAssets.DEFAULT_FOLDERS),
		{"key": "bgm:town", "value": {"type": "bgm", "file": "bgm/town@night.ogg"}}, "editor: entry from file in a kind folder")
	# 候補（一覧から選ぶ項目）
	check("pc98_classic" in scr.template_ids() and "pc88_classic" in scr.template_ids(), "editor: template ids")
	check("98" in scr.preset_ids() and scr.preset_ids().any(func(p): return String(p).begins_with("98.")), "editor: preset ids")
	check("res://tests/stage1/scenario/stage1_talk.ink.json" in scr.scenario_files(), "editor: scenario files")
	var f2 := AdvSchemaForm.new()
	f2.suggest = func(path): return ["a", "b"] if path == ["template"] else []
	f2.setup(AdvSchemaValidator.load_schema("project"), {"template": "zzz"})
	var row: TreeItem = null
	for it in f2.get_root().get_children():
		if it.get_text(0) == "template":
			row = it
	check(row != null and row.get_cell_mode(1) == TreeItem.CELL_MODE_RANGE and row.get_text(1) == "zzz,a,b", "form: suggestions as a dropdown keeping the current value")
	f2.free()
	# 継承した値
	var f3 := AdvSchemaForm.new()
	f3.inherited = AdvTemplate.load_template("pc88_classic").data
	f3.setup(AdvSchemaValidator.load_schema("template"), {"template_version": 1, "id": "x", "extends": "pc88_classic"})
	var fonts_row: TreeItem = null
	for it in f3.get_root().get_children():
		if it.get_text(0) == "fonts":
			fonts_row = it
	check(fonts_row != null and fonts_row.get_text(1).begins_with("継承："), "form: inherited value shown: %s" % (fonts_row.get_text(1) if fonts_row else ""))
	f3._on_button(fonts_row, 1, AdvSchemaForm.BTN_ADD, 1)
	check(f3.data.has("fonts") and f3.data["fonts"] == f3.inherited["fonts"] and not is_same(f3.data["fonts"], f3.inherited["fonts"]), "form: override starts from a copy of the inherited value")
	eq(AdvSchemaForm.lookup({"a": {"b": null}}, ["a", "b"]), [true, null], "form: lookup finds null values")
	f3.free()
	# 変数の一覧
	var vars := AdvVariableIndex.collect()
	var by_name := {}
	for v in vars:
		by_name["%s/%s" % [v["source"], v["name"]]] = v
	check(by_name.has("JSON/knocks") and by_name["JSON/knocks"]["declared"] and by_name["JSON/knocks"]["writes"].size() >= 1 and by_name["JSON/knocks"]["reads"].size() >= 1,
		"vars: JSON variable with reads and writes")
	check(by_name.has("Ink/saw_lights") and by_name["Ink/saw_lights"]["line"] > 0 and by_name["Ink/saw_lights"]["note"] == "JSON と同期", "vars: ink VAR from source, synced")
	check(by_name.has("組み込み/has(アイテム)"), "vars: builtins")
	eq(scr.entry_for_file("res://other/logo.png", "res://g/assets", AdvAssets.DEFAULT_FOLDERS)["key"], "image:logo", "editor: entry by extension")


# ---------------------------------------------------------------- 同梱のテンプレート

func _test_templates() -> void:
	var ids: Array = load("res://addons/adv80s/editor/adv_editor_screen.gd").template_ids()
	check(ids.size() >= 26, "templates: one per machine (%d)" % ids.size())
	var machines := {}
	for id in ids:
		var diags: Array = []
		var t := AdvTemplate.load_template(String(id), diags)
		if t == null:
			check(false, "template loads: %s %s" % [id, str(diags)])
			continue
		var raw = AdvJson.load_file(AdvTemplate.find_path(String(id)))
		var sv := AdvSchemaValidator.check(raw, "template", String(id)).filter(func(d): return d["severity"] != "info")
		check(sv.is_empty() and diags.is_empty(), "template valid: %s %s %s" % [id, str(sv), str(diags)])
		machines[String(t.preset.get("machine", ""))] = true
		var screen := Rect2i(Vector2i.ZERO, t.preset["size"])
		var rects := []
		for r in ["picture", "message", "commands", "input"]:
			var rr := t.region_rect(r)
			if rr.size == Vector2i.ZERO:
				continue
			check(screen.encloses(rr), "template %s: %s inside the screen %s" % [id, r, str(rr)])
			for o in rects:
				check(not o.intersects(rr), "template %s: %s does not overlap" % [id, r])
			rects.append(rr)
		# 素材：窓の枠の画像と、フォントの候補（dot16 は同梱しない）
		var a := AdvAssets.new()
		a.add_root(AdvAssets.BUILTIN_ROOT)
		if t.asset_root() != "":
			a.add_root(t.asset_root())
		var skin: Dictionary = t.get_section("ui").get("window_skin", {})
		if String(skin.get("type", "box")) == "nine_patch":
			check(a.resolve("image", String(skin.get("image", ""))) != "", "template %s: frame image" % id)
		var main = t.get_section("fonts").get("main")
		var cands: Array = main if main is Array else [main]
		var found := false
		for c in cands:
			if a.resolve("font", String(c.get("asset", "")).trim_prefix("font.")) != "":
				found = true
		check(found, "template %s: a bundled font is found" % id)
	for m in AdvPresets.machines():
		check(machines.has(m), "template for machine %s" % m)


# ---------------------------------------------------------------- アニメーション画像とスプライト（6.4）

func _test_media() -> void:
	for f in ["anim.gif", "anim.apng", "anim.mng"]:
		var fr: AdvImageFrames = AdvGif.load_frames("res://tests/media/" + f) if f.ends_with(".gif") else AdvPngAnim.load_frames("res://tests/media/" + f)
		check(fr != null and fr.frames.size() == 3, "%s: 3 frames" % f)
		if fr != null:
			check(is_equal_approx(fr.delays[0], 0.1) and is_equal_approx(fr.delays[2], 0.3) and fr.loop_count == 0, "%s: delays and loop %s" % [f, str(fr.delays)])
	var st: AdvImageFrames = AdvGif.load_frames("res://tests/media/static.gif")
	check(st != null and st.frames.size() == 1 and st.loop_count == 1, "static gif")
	var lamp: AdvImageFrames = AdvGif.load_frames("res://tests/media/lamp.gif")
	eq(lamp.size, Vector2i(16, 24), "lamp size")
	# 取り込み（.import）を通すと AdvImageFrames になる
	var imported = load("res://tests/media/lamp.gif")
	check(imported is AdvImageFrames and imported.frames.size() == 4, "imported gif is AdvImageFrames")
	# カラーキー：黒を抜く
	var keyed = AdvImages.load_visual("res://tests/media/lamp.gif", Color.BLACK)
	var img: Image = (keyed as AdvImageFrames).frames[0].get_image()
	eq(img.get_pixel(0, 0).a, 0.0, "color key makes black transparent")
	eq(AdvImages.key_color("#ff00ff"), Color(1, 0, 1), "key color from hex")
	eq(AdvImages.key_color(null), null, "no key color")
	# スプライト
	var s := AdvSprite.new()
	s.set_visual(keyed, {}, Callable())
	s.apply({"x": 10, "y": 20, "scale": 2, "opacity": 0.5, "anchor": "bottom"})
	eq(s.frame_size(), Vector2(16, 24), "sprite frame size")
	eq(s.bounds().size, Vector2(32, 48), "sprite bounds scaled")
	check(is_equal_approx(s.modulate.a, 0.5), "sprite opacity")
	check("default" in s.anim_names(), "animated image gets default anim")
	check(s.play_anim("default") and s.is_animating(), "play anim")
	s.free()
	# スプライトシート（grid と anims）
	var sheet := AdvSprite.new()
	sheet.set_visual(load("res://tests/stage1/assets/sprite/sparkle.png"),
		{"grid": [3, 1], "anims": {"twinkle": {"frames": [0, 1, 2], "fps": 6, "loop": true}}}, Callable())
	eq(sheet.frame_size(), Vector2(8, 8), "grid frame size")
	check("twinkle" in sheet.anim_names(), "manifest anims")
	sheet.free()
	# マニフェストの生成：動画と、再生できない動画
	check("ogv" in AdvManifestGenerator.ASSET_EXT and "gif" in AdvManifestGenerator.ASSET_EXT, "manifest generator knows gif/ogv")
	eq(preload("res://addons/adv80s/editor/adv_editor_screen.gd").entry_for_file("res://x/movie/op.ogv", "res://x", AdvAssets.DEFAULT_FOLDERS)["key"], "video:op", "editor entry for video")
	eq(preload("res://addons/adv80s/editor/adv_editor_screen.gd").entry_for_file("res://x/a.gif", "res://x", {})["key"], "image:a", "editor entry for gif outside folders")


# ---------------------------------------------------------------- 背景の重ね合わせと共通の変数・定数（段階10）

func _test_layers_and_globals() -> void:
	var sc := {
		"start": "a",
		"constants": {"LIMIT": 3},
		"scenes": {
			"a": {"image": ["base", {"id": "lamp", "x": 10, "y": 20, "when": "lit"}, {"id": "night", "when": "not lit"}],
				"image_transition": "fade",
				"on": {"WAIT": [{"set": {"lit": true}}, "ついた。"], "LOOK": [{"set": {"LIMIT": 5}}, "{player}は {MAX_HP}。"],
					"THINK": "x"}},
		}}
	var path := "user://_layers.scenario.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(sc))
	f.close()
	var c := AdvCore.new()
	c.setup({"seed": 1, "verbs": ["WAIT", "THINK"], "variables": {"lit": {"type": "bool", "default": false}, "player": {"type": "string", "default": "ゆうじ"}},
		"constants": {"MAX_HP": 99}})
	c.use_adapter(AdvJsonAdapter.new())
	eq(c.load_scenario([path]), OK, "layers: load")
	var ev := c.start()
	var shows := ev.filter(func(e): return e["type"] == "image.show")
	check(shows.size() == 1 and shows[0]["args"]["id"] == ["base", "night"], "image array filtered by when: %s" % str(shows))
	eq(c.state.get_var("player"), "ゆうじ", "project variable default")
	eq(c.state.get_var("MAX_HP"), 99, "project constant")
	eq(c.state.get_var("LIMIT"), 3, "scenario constant")
	var r := c.submit({"verb": "WAIT"})
	var s2 := r.filter(func(e): return e["type"] == "image.show")
	check(s2.size() == 1 and s2[0]["args"]["id"].size() == 2 and s2[0]["args"]["id"][1]["id"] == "lamp" and s2[0]["args"]["id"][1]["x"] == 10 and s2[0]["args"]["transition"] == "fade",
		"image re-composed when condition changes: %s" % str(s2))
	check(c.submit({"verb": "THINK"}).filter(func(e): return e["type"] == "image.show").is_empty(), "no redraw when unchanged")
	c.submit({"verb": "LOOK"})
	eq(c.state.get_var("LIMIT"), 3, "constant cannot be changed")
	var diags := c.validate()
	check(diags.any(func(d): return d["code"] == "CONST_WRITE"), "validate: CONST_WRITE")
	check(not diags.any(func(d): return d["code"] == "UNKNOWN_VARIABLE"), "validate: project variables are known: %s" % str(diags.filter(func(d): return d["code"] == "UNKNOWN_VARIABLE")))
	# セーブして戻しても、重ね合わせの状態が残る
	var saved := c.save_state()
	var c2 := AdvCore.new()
	c2.setup({"seed": 1, "verbs": ["WAIT", "THINK"], "variables": {"lit": {"type": "bool", "default": false}}, "constants": {"MAX_HP": 99}})
	c2.use_adapter(AdvJsonAdapter.new())
	c2.load_scenario([path])
	c2.load_state(saved)
	check(c2.submit({"verb": "THINK"}).filter(func(e): return e["type"] == "image.show").is_empty(), "image state restored from save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_text_stops() -> void:
	var r := AdvTextMarkup.to_bbcode_stops("あい[p]うえ[page=2]お[w=0.5]か[se=knock][speed=5]き[/speed][instant]く[/instant]{{x}}[blink]け[/blink]", null, null)
	var kinds: Array = r["stops"].map(func(st): return "%s@%d" % [st["kind"], st["at"]])
	eq(kinds, ["p@2", "page@5", "w@6", "se@7", "speed@7", "speed@8", "speed@8", "speed@9"], "stops: %s" % str(kinds))
	check(String(r["bbcode"]).contains("うえ\nお"), "page inserts a line break: %s" % r["bbcode"])
	check(String(r["bbcode"]).contains("[pulse"), "blink becomes pulse")
	eq(r["stops"][1]["value"], 2.0, "page seconds")
	eq(AdvTextMarkup.to_plain("あ[p]い[page]う", null, null), "あい\nう", "plain text drops stops")
	var r2 := AdvTextMarkup.to_bbcode_stops("[ruby=かんじ]漢字[/ruby][p]あ", null, null)
	eq(r2["stops"][0]["at"], 7, "ruby paren counted before stop")
