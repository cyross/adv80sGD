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
	_test_stage1_scenario()
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
	core.setup({"seed": 1})
	core.assets.scan("res://tests/stage1/assets")
	core.use_adapter(AdvJsonAdapter.new())
	eq(core.load_scenario(["res://tests/stage1/scenario/stage1.json"]), OK, "load scenario")
	var errors := core.validate().filter(func(d): return d["severity"] == "error")
	eq(errors.size(), 0, "validate has no errors: %s" % str(errors))

	var ev := core.start()
	eq(ev[0]["type"], "scene.goto", "start: scene.goto")
	eq(ev[1]["type"], "image.show", "start: image.show")
	check(_bodies(ev).contains("うすぐらい"), "start: first text")
	eq(core.state.scene, "hallway", "scene is hallway")

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
	t = _bodies(_say("アイテム"))
	check(t.contains("かぎ"), "items → %s" % t)
	t = _bodies(_say("かぎを ドアに つかう"))
	check(t.contains("カチリ"), "use key on door → %s" % t)
	check(core.state.get_var("door_unlocked") == true, "door unlocked")
	t = _bodies(_say("ドアをあける"))
	check(t.contains("ドアを あけた") and t.contains("ほこりっぽい"), "open door (no space) → %s" % t)
	eq(core.state.scene, "room", "scene is room")
	t = _bodies(_say("しょうじょと はなす"))
	check(t.contains("たたいていたのは"), "talk (knocks>0) → %s" % t)
	check(t.contains("@マーク"), "@@ escape → %s" % t)
	check(core.state.talked.has("ayumi_first"), "talked mark")
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
	t = _bodies(core.submit({"verb": "OPEN", "source": "select"}))
	check(t.contains("なにを"), "missing slot → %s" % t)
	check(core.state.tried.has("LOOK:door"), "tried mark")

	# セーブとロード
	var saved := core.save_state()
	_say("ドアを あける")
	core.load_state(saved)
	eq(core.state.scene, "hallway", "load_state restores scene")
