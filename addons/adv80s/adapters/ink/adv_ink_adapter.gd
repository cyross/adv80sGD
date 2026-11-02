class_name AdvInkAdapter
extends AdvScenarioAdapter
## Ink のアダプタ（5.3）。inklecate で変換した JSON（.ink.json）を AdvInkStory で再生する。
##
## 受け渡し：JSON の手順 {"ink": "ノット名"} で Core がこのアダプタを積み、start(ノット名) を呼ぶ。
## Ink が選択肢なしで止まったら（-> DONE、-> END、終わりまで進んだ）adapter.exit を出し、JSON に戻る。
## .ink.json だけのゲームでは、このアダプタが主になる（start("") で最初から）。
##
## 1行ごとに text.show を出す。行の書き方とタグ：
##   "@話者ID 文章"             台詞（JSON の手順と同じ）。タグ # speaker:話者ID でもよい
##   # voice:ID                この行の前に voice.play
##   # id:行ID                 既読管理の行ID（省略すると ink:ノット名#本文のハッシュ）
##   # bg:ID / # bgm:ID / # se:ID   image.show（bg）、bgm.play、se.play
##   # {"image.show": {…}}     JSON の手順と同じ書き方の出力イベント
##   その他のタグは text.show の ext.tags に入る
## 選択肢のタグ：
##   # intent:動詞[:対象[:with]]  コマンドの意図でもこの選択肢を選べる（* は何でも）
##   # hidden                  選択肢の一覧に出さない（意図でだけ選べる）
## 変数：Ink のグローバル変数のうち Core の状態に同じ名前があるものは、Ink に入るときに Core の値を写す。
##   Ink の中で変わったグローバル変数は state.set で Core に返す（ink.sync_variables が false なら返さない）。
## 外部関数（EXTERNAL で宣言して使う）：has_item(id)、item_count(id)、item_add(id)、item_remove(id)、
##   get_var(名前)、set_var(名前, 値)、visited(シーン)、talked(ID)、cond(条件式)、event(種類, 引数のJSON)、goto_scene(ID)

const EXTERNALS := ["has_item", "item_count", "item_add", "item_remove", "get_var", "set_var", "visited",
	"talked", "cond", "event", "goto_scene"]

var stories: Dictionary = {}       ## ファイル → AdvInkStory
var files: PackedStringArray = []
var diags: Array[Dictionary] = []

var _cur: String = ""              ## 再生中のファイル
var _entry: String = ""            ## 入ったノット
var _active: bool = false
var _choice_id: String = ""

var _scratch: AdvState
var _out: Array[Dictionary] = []
var _occurrence: Dictionary = {}
var _carry_tags: Array = []        ## タグだけの行のタグ（次の行の ext.tags に入れる）


func load_sources(paths: PackedStringArray) -> Error:
	var err := OK
	for p in paths:
		var text := FileAccess.get_file_as_string(p)
		var s := AdvInkStory.new()
		if text == "" or s.load_json(text) != OK:
			diags.append(AdvDiag.make("error", "INK_LOAD", "Ink の JSON を読めません: %s" % p,
				"Cannot load ink JSON: %s" % p, p, ""))
			err = ERR_PARSE_ERROR
			continue
		_bind(s)
		stories[p] = s
		files.append(p)
	return err


func _bind(s: AdvInkStory) -> void:
	s.on_variable_changed = Callable(self, "_on_var")
	for n in EXTERNALS:
		s.external_functions[n] = Callable(self, "_x_" + n)


## entry を持つ物語のファイル。entry が空なら最初のファイル。
func _story_for(entry: String) -> String:
	for f in files:
		if entry == "" or stories[f].has_path(entry):
			return f
	return ""


var story: AdvInkStory:
	get:
		return stories.get(_cur)


# ---------------------------------------------------------------- 再生

func start(entry: String) -> Array[Dictionary]:
	_begin()
	_cur = _story_for(entry)
	if _cur == "":
		ctx.warn("INK_MISSING_KNOT", "Ink のノットが見つかりません: %s" % entry)
		_emit(AdvEvents.make("adapter.exit", {"entry": entry, "error": "missing_knot"}))
		return _out
	_entry = entry
	_active = true
	_sync_in()
	if entry != "":
		story.choose_path(entry)
	else:
		story.reset_callstack()
	_emit(AdvEvents.make("state.mark", {"kind": "talked", "id": "ink:" + (entry if entry != "" else "start")}))
	_run()
	return _out


func handle_intent(intent: Dictionary) -> Array[Dictionary]:
	_begin()
	if not _active or story == null:
		_say("", ctx.reply("nothing_happens"), "ink:none")
		return _out
	var verb := String(intent.get("verb", ""))
	var slots: Dictionary = intent.get("slots", {})
	var choices := story.current_choices
	var pick := -1
	if verb == "CHOOSE":
		var t = slots.get("target")
		var oid := String(t.get("id", "")) if t is Dictionary else str(t)
		if oid.begins_with("c") and oid.substr(1).is_valid_int():
			pick = int(oid.substr(1))
		if pick < 0 or pick >= choices.size():
			ctx.warn("CHOICE_UNKNOWN", "知らない選択肢の項目です: %s" % oid)
			return _out
	else:
		pick = _match_intent(choices, verb, slots)
		if pick < 0:
			var r := ctx.dictionary.default_reply(verb)
			_say("", r if r != "" else ctx.reply("nothing_happens"), "ink:%s/%s" % [_entry, verb])
			return _out
	_emit(AdvEvents.make("state.mark", {"kind": "chosen", "id": "%s/c%d" % [_choice_id, pick]}))
	_sync_in()
	story.choose_choice_index(pick)
	_run()
	return _out


## 意図に合う選択肢の番号。intent タグの対象を書いた選択肢を優先し、* は最後に見る。
func _match_intent(choices: Array, verb: String, slots: Dictionary) -> int:
	var target := AdvCore.slot_key(slots["target"]) if slots.has("target") else ""
	var with_v := AdvCore.slot_key(slots["with"]) if slots.has("with") else ""
	var loose := -1
	var any := -1
	for ch in choices:
		for t in ch["tags"]:
			var tag := String(t).strip_edges()
			if not tag.begins_with("intent:"):
				continue
			var parts := tag.substr(7).strip_edges().split(":")
			var v := parts[0].strip_edges()
			if v == "*":
				if any < 0:
					any = ch["index"]
				continue
			if v != verb:
				continue
			var pt := parts[1].strip_edges() if parts.size() > 1 else ""
			var pw := parts[2].strip_edges() if parts.size() > 2 else ""
			if pt != "" and pt != target:
				continue
			if pw != "" and pw != with_v:
				continue
			if pt != "":
				return ch["index"]
			if loose < 0:
				loose = ch["index"]
	return loose if loose >= 0 else any


func _begin() -> void:
	_scratch = ctx.state.duplicate_state()
	_out = []
	_occurrence = {}
	_carry_tags = []


func _run() -> void:
	var lines := story.continue_maximally()
	for l in lines:
		_line(String(l["text"]), l["tags"])
	for e in story.errors:
		ctx.warn("INK_RUNTIME", "Ink の実行中のエラー: %s" % e)
	if not story.errors.is_empty():
		story.errors.clear()
		_finish("error")
		return
	var choices := story.current_choices
	if choices.is_empty():
		_finish("")
		return
	var shown := []
	var labels := PackedStringArray()
	for ch in choices:
		labels.append(ch["text"])
		if not "hidden" in ch["tags"]:
			shown.append({"id": "c%d" % ch["index"], "label": ch["text"]})
	_choice_id = "ink:%s#c%s" % [_entry, "|".join(labels).md5_text().substr(0, 8)]
	if not shown.is_empty():
		_emit(AdvEvents.make("choice.show", {"id": _choice_id, "choices": shown}))


func _finish(error: String) -> void:
	_active = false
	var args := {"entry": _entry}
	if error != "":
		args["error"] = error
	_emit(AdvEvents.make("adapter.exit", args))


func _line(text: String, tags: Array) -> void:
	var speaker := ""
	var id := ""
	var extra_tags := []
	for t in tags:
		var tag := String(t).strip_edges()
		if tag.begins_with("{"):
			var d = JSON.parse_string(tag)
			if d is Dictionary:
				_event_step(d)
			else:
				ctx.warn("INK_TAG", "タグの JSON を読めません: %s" % tag)
			continue
		var kv := tag.split(":", true, 1)
		var key := kv[0].strip_edges() if kv.size() == 2 else ""
		var val := kv[1].strip_edges() if kv.size() == 2 else ""
		match key:
			"speaker":
				speaker = val
			"voice":
				_emit(AdvEvents.make("voice.play", {"id": val}))
			"id":
				id = val
			"bg":
				_emit(AdvEvents.make("image.show", {"layer": "bg", "id": val}))
			"bgm":
				_emit(AdvEvents.make("bgm.play", {"id": val}))
			"se":
				_emit(AdvEvents.make("se.play", {"id": val}))
			_:
				if tag.begins_with("@") and not tag.contains(" "):
					speaker = tag.substr(1)
				else:
					extra_tags.append(tag)
	if text == "":
		# タグだけの行：出力イベント以外のタグは次の行に回す
		_carry_tags.append_array(extra_tags)
		return
	extra_tags = _carry_tags + extra_tags
	_carry_tags = []
	if text.begins_with("@@"):
		text = text.substr(1)
	elif text.begins_with("@"):
		var rest := text.substr(1)
		var cut := -1
		for i in rest.length():
			if rest[i] == " " or rest[i] == "　":
				cut = i
				break
		speaker = rest if cut < 0 else rest.substr(0, cut)
		text = "" if cut < 0 else rest.substr(cut + 1).strip_edges(true, false)
	_say(speaker, text, "ink:" + (_entry if _entry != "" else "start"), id, extra_tags)


## JSON の手順と同じ書き方の出力イベント（{"type": …} か {"image.show": {…}}）。
func _event_step(d: Dictionary) -> void:
	if d.has("type"):
		_emit(d)
	elif d.size() == 1:
		var type := String(d.keys()[0])
		var args = d[type]
		_emit(AdvEvents.make(type, args if args is Dictionary else {}))


func _say(speaker: String, body: String, path: String, id: String = "", tags: Array = []) -> void:
	if id == "":
		var base := "%s#%s" % [path, body.md5_text().substr(0, 8)]
		var n: int = _occurrence.get(base, 0)
		_occurrence[base] = n + 1
		id = base if n == 0 else "%s-%d" % [base, n]
	var name := ""
	var c = null
	if speaker != "":
		c = ctx.query("character", {"id": speaker})
		name = String(c.get("name", speaker)) if c is Dictionary else speaker
	var ev := AdvEvents.text(body, speaker, name, id)
	if c is Dictionary and c.has("pal"):
		ev["args"]["pal"] = c["pal"]
	if not tags.is_empty():
		ev["ext"] = {"tags": tags}
	_emit(ev)


func _emit(ev: Dictionary) -> void:
	if AdvEvents.is_state_event(ev):
		_scratch.apply_event(ev)
	_out.append(ev)


# ---------------------------------------------------------------- 変数と外部関数

func _sync_in() -> void:
	for n in story.global_names():
		if _scratch.has_var(n):
			story.set_global(n, _scratch.get_var(n))


func _on_var(name: String, value: Variant) -> void:
	if not bool(ctx.config("ink", "sync_variables", true)):
		return
	if value is AdvInkStory.DivertTarget or value is AdvInkStory.VarPointer:
		return
	_emit(AdvEvents.make("state.set", {"name": name, "value": value}))


func _x_has_item(a: Array) -> Variant:
	return _scratch.has_item(str(a[0])) if a.size() > 0 else false


func _x_item_count(a: Array) -> Variant:
	return _scratch.item_count(str(a[0])) if a.size() > 0 else 0


func _x_item_add(a: Array) -> Variant:
	if a.size() > 0:
		_emit(AdvEvents.make("item.add", {"id": str(a[0]), "count": int(a[1]) if a.size() > 1 else 1}))
	return null


func _x_item_remove(a: Array) -> Variant:
	if a.size() > 0:
		_emit(AdvEvents.make("item.remove", {"id": str(a[0]), "count": int(a[1]) if a.size() > 1 else 1}))
	return null


func _x_get_var(a: Array) -> Variant:
	var v = _scratch.get_var(str(a[0])) if a.size() > 0 else null
	return 0 if v == null else v


func _x_set_var(a: Array) -> Variant:
	if a.size() > 1:
		_emit(AdvEvents.make("state.set", {"name": str(a[0]), "value": a[1]}))
	return null


func _x_visited(a: Array) -> Variant:
	return a.size() > 0 and _scratch.visited.has(str(a[0]))


func _x_talked(a: Array) -> Variant:
	return a.size() > 0 and _scratch.talked.has(str(a[0]))


func _x_cond(a: Array) -> Variant:
	return ctx.eval(str(a[0]), _scratch) if a.size() > 0 else false


func _x_event(a: Array) -> Variant:
	if a.size() > 0:
		var args = JSON.parse_string(str(a[1])) if a.size() > 1 else {}
		_emit(AdvEvents.make(str(a[0]), args if args is Dictionary else {}))
	return null


func _x_goto_scene(a: Array) -> Variant:
	if a.size() > 0:
		_emit(AdvEvents.make("scene.goto", {"scene": str(a[0])}))
	return null


# ---------------------------------------------------------------- 問い合わせ・セーブ

func query(what: String, _args: Dictionary = {}) -> Variant:
	match what:
		"pending_choice":
			if not _active or story == null or story.current_choices.is_empty():
				return null
			var shown := []
			var intents := false
			for ch in story.current_choices:
				if not "hidden" in ch["tags"]:
					shown.append({"id": "c%d" % ch["index"], "label": ch["text"]})
				for t in ch["tags"]:
					if String(t).strip_edges().begins_with("intent:"):
						intents = true
			return {"id": _choice_id, "choices": shown, "accepts_intents": intents}
		"ink_knots":
			var list := []
			for f in files:
				list.append_array(stories[f].knot_names())
			return list
		"ink_active":
			return _entry if _active else null
	return null


func save_state() -> Dictionary:
	var st := {}
	for f in stories:
		st[f] = stories[f].save_state()
	return {"stories": st, "cur": _cur, "entry": _entry, "active": _active, "choice_id": _choice_id}


func load_state(data: Dictionary) -> Error:
	var st: Dictionary = data.get("stories", {})
	for f in st:
		if stories.has(f):
			stories[f].load_state(st[f])
	_cur = String(data.get("cur", ""))
	_entry = String(data.get("entry", ""))
	_active = bool(data.get("active", false))
	_choice_id = String(data.get("choice_id", ""))
	return OK


# ---------------------------------------------------------------- 確認

const _TAG_ASSETS := {"bg": "image", "bgm": "bgm", "se": "se", "voice": "voice"}

func validate() -> Array[Dictionary]:
	var out: Array[Dictionary] = diags.duplicate()
	for f in files:
		var s: AdvInkStory = stories[f]
		for w in s.warnings:
			out.append(AdvDiag.make("warning", "INK_VERSION", "Ink の JSON: %s" % w, "Ink JSON: %s" % w, f, ""))
		for e in s.errors:
			out.append(AdvDiag.make("error", "INK_UNSUPPORTED", "Ink の JSON に読めない部分があります: %s" % e,
				"Unsupported content in ink JSON: %s" % e, f, ""))
		var uses_list := s.has_lists
		var missing := {}
		for o in s.all_objects():
			if o.kind == AdvInkStory.K_LIST or (o.kind == AdvInkStory.K_CMD and o.a in ["listInt", "range", "lrnd"]) \
					or (o.kind == AdvInkStory.K_NATIVE and String(o.a).begins_with("LIST")):
				uses_list = true
			if o.kind == AdvInkStory.K_DIVERT and o.d == "x" and not o.a in EXTERNALS and not s.root.named.has(o.a):
				missing[o.a] = true
			if o.kind == AdvInkStory.K_STR:
				# タグで書いた素材（bg:、bgm:、se:、voice:）
				var kv := String(o.a).strip_edges().split(":", true, 1)
				if kv.size() == 2 and _TAG_ASSETS.has(kv[0]) and not kv[1].strip_edges().contains(" "):
					var id := kv[1].strip_edges()
					if id != "" and not ctx.has_asset(_TAG_ASSETS[kv[0]], id):
						out.append(AdvDiag.make("warning", "ASSET_NOT_FOUND", "素材が見つかりません: %s（%s）" % [id, _TAG_ASSETS[kv[0]]],
							"Asset not found: %s (%s)" % [id, _TAG_ASSETS[kv[0]]], f, o.parent.path()))
		if uses_list:
			out.append(AdvDiag.make("error", "INK_LIST", "LIST は使えません（adv80s の Ink 実行部は未対応）",
				"LIST is not supported by the adv80s ink runtime", f, ""))
		for n in missing:
			out.append(AdvDiag.make("error", "INK_EXTERNAL", "外部関数がありません: %s（使えるのは %s）" % [n, ", ".join(EXTERNALS)],
				"External function not provided: %s" % n, f, ""))
	var refs = ctx.query("ink_refs")
	if refs is Array:
		for r in refs:
			if _story_for(String(r["entry"])) == "":
				out.append(AdvDiag.make("error", "INK_MISSING_KNOT", "Ink のノットが見つかりません: %s" % r["entry"],
					"Ink knot not found: %s" % r["entry"], r["file"], r["path"]))
	return out
