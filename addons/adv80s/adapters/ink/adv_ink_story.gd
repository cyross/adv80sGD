class_name AdvInkStory
extends RefCounted
## Ink の変換済み JSON（inklecate の出力）を再生する実行部分（5.3）。
## inkle 社の C# 版の実行部分（MIT ライセンス）の動きにそろえて、GDScript で書いたもの。
## 元にした ink（https://github.com/inkle/ink）：Copyright (c) 2017 inkle Ltd. MIT License
##
## 対応：文章、グルー、タグ、選択肢（条件、一度だけ、見えない既定の選択肢）、分岐、変数（グローバル、一時、参照渡し）、
## 計算、関数、トンネル、スレッド、訪問回数、ターン数、シーケンス（シャッフルを含む）、乱数、外部関数。
## 未対応：LIST 型（使うとエラーになる）。
##
## 使い方：
##   var s := AdvInkStory.new()
##   s.load_json(text)
##   s.choose_path("knot")             # 省略すると最初から
##   var lines := s.continue_maximally()  # [{text, tags}]
##   s.current_choices                  # [{text, tags, index}]
##   s.choose_choice_index(0)

# ---------------------------------------------------------------- 実行時の部品

class InkContainer:
	var name: String = ""
	var content: Array = []
	var named: Dictionary = {}
	var flags: int = 0
	var _parent_ref: WeakRef = null
	## 親は弱い参照で持つ（親子で参照し合って解放されなくなるのを避ける）
	var parent: InkContainer:
		get:
			return _parent_ref.get_ref() if _parent_ref != null else null
		set(v):
			_parent_ref = weakref(v) if v != null else null
	var _path: String = "\u0001"

	func visits_counted() -> bool:
		return flags & 1 != 0

	func turns_counted() -> bool:
		return flags & 2 != 0

	func count_start_only() -> bool:
		return flags & 4 != 0

	func path() -> String:
		if _path == "\u0001":
			if parent == null:
				_path = ""
			else:
				var comp := name if name != "" else str(parent.content.find(self))
				var pp := parent.path()
				_path = comp if pp == "" else pp + "." + comp
		return _path


## コンテナ以外の中身。kind ごとに a〜e の意味が変わる。
class InkObj:
	var kind: int
	var _parent_ref: WeakRef = null
	var parent: InkContainer:
		get:
			return _parent_ref.get_ref() if _parent_ref != null else null
		set(v):
			_parent_ref = weakref(v) if v != null else null
	var a: Variant
	var b: Variant
	var c: Variant
	var d: Variant
	var e: Variant

	func _init(k: int, va: Variant = null, vb: Variant = null, vc: Variant = null, vd: Variant = null, ve: Variant = null) -> void:
		kind = k
		a = va
		b = vb
		c = vc
		d = vd
		e = ve

	func path() -> String:
		var i := parent.content.find(self)
		var pp := parent.path()
		return str(i) if pp == "" else pp + "." + str(i)


class DivertTarget:
	var path: String
	func _init(p: String) -> void:
		path = p


class VarPointer:
	var name: String
	var ci: int
	func _init(n: String, c: int) -> void:
		name = n
		ci = c


class VoidValue:
	pass


class TagValue:
	var text: String
	func _init(t: String) -> void:
		text = t


const K_STR := 0        ## a = 文字列（"\n" は改行）
const K_GLUE := 1
const K_VALUE := 2      ## a = int / float / bool
const K_DIVTARGET := 3  ## a = パス
const K_VARPTR := 4     ## a = 名前、b = ci
const K_VOID := 5
const K_CMD := 6        ## a = 命令の名前
const K_NATIVE := 7     ## a = 演算の名前
const K_DIVERT := 8     ## a = 行き先、b = 変数の行き先か、c = 条件つきか、d = ""/"f"/"t"/"x"、e = 外部関数の引数の数
const K_CHOICE := 9     ## a = 選んだときのパス、b = フラグ
const K_VARREF := 10    ## a = 変数名
const K_CNT := 11       ## a = 訪問回数を数えるパス
const K_ASSIGN := 12    ## a = 変数名、b = グローバルか、c = 新しい宣言か
const K_TAG := 13       ## a = 文字列（古い形式のタグ）
const K_LIST := 14

const COMMANDS := ["ev", "out", "/ev", "du", "pop", "~ret", "->->", "str", "/str", "nop", "choiceCnt", "turn",
	"turns", "readc", "rnd", "srnd", "visit", "seq", "thread", "done", "end", "listInt", "range", "lrnd", "#", "/#"]
const NATIVES := {"+": 2, "-": 2, "/": 2, "*": 2, "%": 2, "_": 1, "==": 2, ">": 2, "<": 2, ">=": 2, "<=": 2,
	"!=": 2, "!": 1, "&&": 2, "||": 2, "MIN": 2, "MAX": 2, "POW": 2, "FLOOR": 1, "CEILING": 1, "INT": 1,
	"FLOAT": 1, "?": 2, "!?": 2, "L^": 2, "LIST_MIN": 1, "LIST_MAX": 1, "LIST_ALL": 1, "LIST_COUNT": 1,
	"LIST_VALUE": 1, "LIST_INVERT": 1}

const T_TUNNEL := 0
const T_FUNCTION := 1
const T_GAME := 2

## 出力の流れに入るもの：[0, 文字列] [1]（グルー） [2, 命令] [3, タグの文字列]
const O_TEXT := 0
const O_GLUE := 1
const O_CMD := 2
const O_TAG := 3

# ---------------------------------------------------------------- 状態

var root: InkContainer
var ink_version: int = 0
var has_lists: bool = false         ## LIST を定義している（未対応）
var errors: PackedStringArray = []
var warnings: PackedStringArray = []

var globals: Dictionary = {}
var _choices: Array = []            ## 作られた選択肢すべて（見えない既定の選択肢を含む）

## 見えている選択肢。[{text, tags, index}]（index は choose_choice_index に渡す番号）
var current_choices: Array:
	get:
		var r := []
		for ch in _choices:
			if not ch["invisible"]:
				r.append({"text": ch["text"], "tags": ch["tags"], "index": r.size(), "_ch": ch})
		return r
var external_functions: Dictionary = {}  ## 名前 → Callable(args: Array) -> Variant
var on_variable_changed: Callable    ## 変数が変わったとき func(name, value)

var _threads: Array = []
var _thread_counter: int = 0
var _eval: Array = []
var _output: Array = []
var _visit_counts: Dictionary = {}
var _turn_indices: Dictionary = {}
var _turn_index: int = -1
var _seed: int = 0
var _prev_random: int = 0
var _diverted = null                 ## [container, index] か null
var _did_safe_exit: bool = false
var _global_names: Dictionary = {}


func load_json(text: String) -> Error:
	var d = AdvInkJson.parse(text)
	if not d is Dictionary or not d.has("root"):
		errors.append("not an ink JSON file")
		return ERR_PARSE_ERROR
	ink_version = int(d.get("inkVersion", 0))
	var ld = d.get("listDefs", {})
	has_lists = ld is Dictionary and not ld.is_empty()
	if ink_version < 19 or ink_version > 21:
		warnings.append("inkVersion %d is not tested (expected 19-21)" % ink_version)
	root = _to_container(d["root"], null)
	_seed = AdvDotNetRandom.new(int(Time.get_ticks_msec() % 1000)).next() % 100   # 本家と同じく、時刻から 0〜99
	reset_callstack()
	# グローバル変数の初期値（"global decl" を実行する）
	if root.named.has("global decl"):
		choose_path("global decl", false, false)
		_run_until_stop()
		for k in globals:
			_global_names[k] = true
		_output.clear()
	reset_callstack()
	return OK


# ---------------------------------------------------------------- JSON から部品へ

func _to_container(arr: Array, parent: InkContainer) -> InkContainer:
	var c := InkContainer.new()
	c.parent = parent
	var last = arr.back() if not arr.is_empty() else null
	var n := arr.size() - 1 if not arr.is_empty() else 0
	for i in n:
		var obj = _to_obj(arr[i], c)
		if obj != null:
			c.content.append(obj)
			if obj is InkContainer and obj.name != "":
				c.named[obj.name] = obj
	if last is Dictionary:
		for k in last:
			match k:
				"#f":
					c.flags = int(last[k])
				"#n":
					c.name = String(last[k])
				_:
					var sub = _to_obj(last[k], c)
					if sub is InkContainer:
						sub.name = k
						c.named[k] = sub
	return c


func _to_obj(t: Variant, parent: InkContainer) -> Variant:
	if t is Array:
		return _to_container(t, parent)
	var o: InkObj = null
	if t is int or t is float or t is bool:
		o = InkObj.new(K_VALUE, t)
	elif t is String:
		var s: String = t
		if s.begins_with("^"):
			o = InkObj.new(K_STR, s.substr(1))
		elif s == "\n":
			o = InkObj.new(K_STR, "\n")
		elif s == "<>":
			o = InkObj.new(K_GLUE)
		elif s in COMMANDS:
			o = InkObj.new(K_CMD, s)
		elif NATIVES.has(s):
			o = InkObj.new(K_NATIVE, s)
		elif s == "void":
			o = InkObj.new(K_VOID)
		else:
			errors.append("unknown token: %s" % s)
			return null
	elif t is Dictionary:
		var d: Dictionary = t
		if d.has("^->"):
			o = InkObj.new(K_DIVTARGET, String(d["^->"]))
		elif d.has("^var"):
			o = InkObj.new(K_VARPTR, String(d["^var"]), int(d.get("ci", -1)))
		elif d.has("->"):
			o = InkObj.new(K_DIVERT, String(d["->"]), d.has("var"), d.has("c"), "")
		elif d.has("f()"):
			o = InkObj.new(K_DIVERT, String(d["f()"]), d.has("var"), d.has("c"), "f")
		elif d.has("->t->"):
			o = InkObj.new(K_DIVERT, String(d["->t->"]), d.has("var"), d.has("c"), "t")
		elif d.has("x()"):
			o = InkObj.new(K_DIVERT, String(d["x()"]), false, d.has("c"), "x", int(d.get("exArgs", 0)))
		elif d.has("*"):
			o = InkObj.new(K_CHOICE, String(d["*"]), int(d.get("flg", 0)))
		elif d.has("VAR?"):
			o = InkObj.new(K_VARREF, String(d["VAR?"]))
		elif d.has("CNT?"):
			o = InkObj.new(K_CNT, String(d["CNT?"]))
		elif d.has("VAR="):
			o = InkObj.new(K_ASSIGN, String(d["VAR="]), true, not d.has("re"))
		elif d.has("temp="):
			o = InkObj.new(K_ASSIGN, String(d["temp="]), false, not d.has("re"))
		elif d.has("#"):
			o = InkObj.new(K_TAG, String(d["#"]))
		elif d.has("list"):
			o = InkObj.new(K_LIST, d)
		else:
			errors.append("unknown object: %s" % JSON.stringify(d))
			return null
	elif t == null:
		return null
	if o != null:
		o.parent = parent
	return o


# ---------------------------------------------------------------- パス

## パスの中身を探す。見つからなければ null。base は相対パスの基点（中身かコンテナ）。
func content_at_path(path: String, base: Variant = null) -> Variant:
	if path == "":
		return root
	var comps := path.split(".")
	var cur: Variant
	var start := 0
	if path.begins_with("."):
		# 相対パス：中身からなら、最初の "^" はその中身の入っているコンテナを指す
		start = 1
		if base is InkContainer:
			cur = base
		else:
			cur = base.parent
			if comps.size() > 1 and comps[1] == "^":
				start = 2
	else:
		cur = root
	for i in range(start, comps.size()):
		var comp: String = comps[i]
		if not cur is InkContainer:
			return null
		var cc: InkContainer = cur
		if comp == "^":
			cur = cc.parent
		elif comp.is_valid_int():
			var idx := int(comp)
			if idx < 0 or idx >= cc.content.size():
				return null
			cur = cc.content[idx]
		elif cc.named.has(comp):
			cur = cc.named[comp]
		else:
			return null
	return cur


## パスの指す位置（[コンテナ, 番号]）。最後が番号ならその番号の位置、そうでなければコンテナそのもの（番号 -1）。C# 版の PointerAtPath と同じ。
func pointer_at_path(path: String, base: Variant = null) -> Variant:
	var dot := path.rfind(".")
	var last := path.substr(dot + 1)
	if last.is_valid_int():
		var cpath := path.substr(0, maxi(dot, 0))
		var cont: Variant
		if cpath == "":
			if path.begins_with("."):
				cont = base if base is InkContainer else base.parent
			else:
				cont = root
		else:
			cont = content_at_path(cpath, base)
		return [cont, int(last)] if cont is InkContainer else null
	var obj = content_at_path(path, base)
	if obj is InkContainer:
		return [obj, -1]
	if obj is InkObj:
		return [obj.parent, obj.parent.content.find(obj)]
	return null


static func _resolve(p: Variant) -> Variant:
	if p == null:
		return null
	var c: InkContainer = p[0]
	var i: int = p[1]
	if i < 0 or c.content.is_empty():
		return c
	return c.content[i] if i < c.content.size() else null


# ---------------------------------------------------------------- 呼び出しの積み重ね（スレッド）

func reset_callstack() -> void:
	_threads = [{"cs": [_element(T_TUNNEL, [root, 0])], "idx": 0, "prev": null}]
	_thread_counter = 0


func _element(type: int, p: Variant) -> Dictionary:
	return {"p": p.duplicate() if p is Array else null, "exp": false, "temps": {}, "type": type, "eh": 0, "fs": -1}


static func _copy_thread(t: Dictionary) -> Dictionary:
	var cs := []
	for e in t["cs"]:
		cs.append({"p": e["p"].duplicate() if e["p"] is Array else null, "exp": e["exp"], "temps": e["temps"].duplicate(),
			"type": e["type"], "eh": e["eh"], "fs": e["fs"]})
	return {"cs": cs, "idx": t["idx"], "prev": t["prev"].duplicate() if t["prev"] is Array else null}


func _thread() -> Dictionary:
	return _threads.back()


func _cs() -> Array:
	return _thread()["cs"]


func _el() -> Dictionary:
	return _cs().back()


var _ptr: Variant:
	get:
		return _el()["p"]
	set(v):
		_el()["p"] = v.duplicate() if v is Array else null


var _in_expr: bool:
	get:
		return _el()["exp"]
	set(v):
		_el()["exp"] = v


func _can_pop(type: int = -1) -> bool:
	if _cs().size() <= 1:
		return false
	return type == -1 or _el()["type"] == type


func _can_pop_thread() -> bool:
	return _threads.size() > 1 and _el()["type"] != T_GAME


func _push(type: int) -> void:
	var e := _element(type, _ptr)
	e["fs"] = _output.size()
	_cs().append(e)


func _pop_callstack() -> void:
	if _el()["type"] == T_FUNCTION:
		_trim_function_end()
	_cs().pop_back()


func _fork_thread() -> Dictionary:
	var t := _copy_thread(_thread())
	_thread_counter += 1
	t["idx"] = _thread_counter
	return t


# ---------------------------------------------------------------- 外向けの操作

func can_continue() -> bool:
	return _ptr != null and errors.is_empty()


## 指定したノット（またはパス）へ移る。reset が true なら呼び出しの積み重ねを初めに戻す。
func choose_path(path: String, reset: bool = true, inc_turn: bool = true) -> bool:
	if reset:
		reset_callstack()
	var p = pointer_at_path(path)
	if p == null:
		errors.append("path not found: %s" % path)
		return false
	_set_chosen(p, inc_turn)
	return true


func has_path(path: String) -> bool:
	return content_at_path(path) != null


## すべての中身（コンテナ以外）を返す。確認（validate）で使う。
func all_objects() -> Array:
	var out := []
	_collect(root, out)
	return out


func _collect(c: InkContainer, out: Array) -> void:
	for o in c.content:
		if o is InkContainer:
			_collect(o, out)
		else:
			out.append(o)
	for k in c.named:
		if not c.named[k] in c.content:
			_collect(c.named[k], out)


## ノットの名前の一覧（"global decl" を除く）。
func knot_names() -> Array:
	return root.named.keys().filter(func(k): return k != "global decl")


## パス（ノットなど）の始めに書かれたタグ。C# 版の TagsForContentAtPath と同じ。
func tags_at_path(path: String) -> Array:
	var c = content_at_path(path)
	var tags := []
	while c is InkContainer and not c.content.is_empty() and c.content[0] is InkContainer:
		c = c.content[0]
	if not c is InkContainer:
		return tags
	var in_tag := false
	var buf := ""
	for o in c.content:
		if not o is InkObj:
			break
		if o.kind == K_CMD and o.a == "#":
			in_tag = true
			buf = ""
		elif o.kind == K_CMD and o.a == "/#":
			tags.append(_clean(buf))
			in_tag = false
		elif in_tag and o.kind == K_STR:
			buf += o.a
		elif o.kind == K_TAG:
			tags.append(o.a)
		else:
			break
	return tags


func choose_choice_index(i: int) -> void:
	var vis := current_choices
	if i < 0 or i >= vis.size():
		errors.append("choice out of range: %d" % i)
		return
	var ch: Dictionary = vis[i]["_ch"]
	_threads = [_copy_thread(ch["thread"])]
	_set_chosen(pointer_at_path(ch["target"]), true)


func _set_chosen(p: Variant, inc_turn: bool) -> void:
	_choices.clear()
	if p is Array and p[1] == -1:
		p = [p[0], 0]
	_ptr = p
	if inc_turn:
		_turn_index += 1
	_visit_changed_due_to_divert()


## 選択肢か終わりまで進め、その間に出た行を返す。[{text, tags}]
func continue_maximally() -> Array:
	_run_until_stop()
	return take_lines()


func _run_until_stop() -> void:
	_did_safe_exit = false
	var guard := 0
	while can_continue():
		_step()
		if not can_continue() and _el()["type"] != T_GAME:
			_try_follow_default_invisible_choice()
		guard += 1
		if guard > 2000000:
			errors.append("too many steps (infinite loop?)")
			break
	if _ptr == null and _choices.is_empty() and not _did_safe_exit and errors.is_empty():
		if _can_pop(T_TUNNEL):
			errors.append("unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?")
		elif _can_pop(T_FUNCTION):
			errors.append("unexpectedly reached end of content. Do you need a '~ return'?")
		elif not _can_pop():
			errors.append("ran out of content. Do you need a '-> DONE' or '-> END'?")


## 出力の流れを行に分けて取り出し、流れを空にする（外部関数の前で途中まで取り出すのにも使う）。
func take_lines() -> Array:
	var lines := []
	var text := ""
	var tags := []
	var in_tag := false
	var tag_buf := ""
	for o in _output:
		match int(o[0]):
			O_TEXT:
				if in_tag:
					tag_buf += o[1]
				elif o[1] == "\n":
					lines.append({"text": _clean(text), "tags": tags})
					text = ""
					tags = []
				else:
					text += o[1]
			O_CMD:
				if o[1] == "#":
					if in_tag and tag_buf != "":
						tags.append(_clean(tag_buf))
					tag_buf = ""
					in_tag = true
				elif o[1] == "/#":
					if tag_buf != "":
						tags.append(_clean(tag_buf))
					tag_buf = ""
					in_tag = false
			O_TAG:
				tags.append(o[1])
	if tag_buf != "":
		tags.append(_clean(tag_buf))
	if _clean(text) != "" or not tags.is_empty():
		lines.append({"text": _clean(text), "tags": tags})
	_output.clear()
	for t in _threads:
		for e in t["cs"]:
			if int(e["fs"]) > 0:
				e["fs"] = 0
	return lines.filter(func(l): return l["text"] != "" or not l["tags"].is_empty())


## 空白の整理：行頭と行末の空白を消し、続く空白は1つにする（C# 版の CleanOutputWhitespace と同じ）。
static func _clean(s: String) -> String:
	var out := ""
	var ws_start := -1
	var line_start := 0
	for i in s.length():
		var c := s[i]
		var ws := c == " " or c == "\t"
		if ws and ws_start == -1:
			ws_start = i
		if not ws:
			if c != "\n" and ws_start > 0 and ws_start != line_start:
				out += " "
			ws_start = -1
		if c == "\n":
			line_start = i + 1
		if not ws:
			out += c
	return out


func variable(name: String) -> Variant:
	return _get_var(name)


## グローバル変数を書き換える（Core の状態から同期するときに使う）。宣言されていない名前は無視する。
func set_global(name: String, value: Variant) -> void:
	if globals.has(name):
		globals[name] = _coerce_in(value)


func global_names() -> Array:
	return globals.keys()


static func _coerce_in(v: Variant) -> Variant:
	if v is int or v is float or v is bool or v is String:
		return v
	return str(v)


# ---------------------------------------------------------------- 1歩進める

func _step() -> void:
	var p = _ptr
	if p == null:
		return
	# コンテナなら、その最初の中身まで入る
	var cont = _resolve(p)
	while cont is InkContainer:
		_visit_container(cont, true)
		if cont.content.is_empty():
			break
		p = [cont, 0]
		cont = _resolve(p)
	_ptr = p
	var obj = _resolve(p)
	var is_flow := _perform(obj)
	if _ptr == null:
		return
	var add := not is_flow
	if obj is InkObj and obj.kind == K_CHOICE:
		var ch = _process_choice(obj)
		if ch != null:
			_choices.append(ch)
		obj = null
		add = false
	if obj is InkContainer:
		add = false
	if add and obj != null:
		var v = _obj_value(obj)
		if v is VarPointer and v.ci == -1:
			v = VarPointer.new(v.name, _context_for(v.name))
		if _in_expr:
			_eval.append(v)
		else:
			_push_output_value(v, obj)
	_next_content()
	if obj is InkObj and obj.kind == K_CMD and obj.a == "thread":
		var t := _copy_thread(_thread())
		_thread_counter += 1
		t["idx"] = _thread_counter
		_threads.append(t)


## 中身を評価用の値にする。
func _obj_value(o: InkObj) -> Variant:
	match o.kind:
		K_STR: return o.a
		K_VALUE: return o.a
		K_DIVTARGET: return DivertTarget.new(_abs_path(o.a, o))
		K_VARPTR: return VarPointer.new(o.a, o.b)
		K_VOID: return VoidValue.new()
		K_GLUE: return "<>"
		K_TAG: return TagValue.new(o.a)
	return null


func _abs_path(path: String, base: Variant) -> String:
	if not path.begins_with("."):
		return path
	var t = content_at_path(path, base)
	if t is InkContainer:
		return t.path()
	if t is InkObj:
		return t.path()
	return path


func _push_output_value(v: Variant, o: InkObj) -> void:
	if o != null and o.kind == K_GLUE:
		_push_output([O_GLUE])
	elif o != null and o.kind == K_TAG:
		_push_output([O_TAG, o.a])
	elif v is String:
		_push_text(v)
	else:
		_push_text(_to_str(v))


func _visit_container(c: InkContainer, at_start: bool) -> void:
	if not c.count_start_only() or at_start:
		if c.visits_counted():
			_visit_counts[c.path()] = int(_visit_counts.get(c.path(), 0)) + 1
		if c.turns_counted():
			_turn_indices[c.path()] = _turn_index


func _visit_changed_due_to_divert() -> void:
	var prev = _thread()["prev"]
	var p = _ptr
	if p == null or p[1] == -1:
		return
	var prev_containers := []
	if prev != null:
		var anc = _resolve(prev)
		if not anc is InkContainer:
			anc = prev[0]
		while anc != null:
			prev_containers.append(anc)
			anc = anc.parent
	var child = _resolve(p)
	if child == null:
		return
	var anc2: InkContainer = child.parent
	var all_start := true
	while anc2 != null and (not prev_containers.has(anc2) or anc2.count_start_only()):
		var entering_start: bool = not anc2.content.is_empty() and child == anc2.content[0] and all_start
		if not entering_start:
			all_start = false
		_visit_container(anc2, entering_start)
		child = anc2
		anc2 = anc2.parent


func _next_content() -> void:
	_thread()["prev"] = _ptr.duplicate() if _ptr is Array else null
	if _diverted != null:
		_ptr = _diverted
		_diverted = null
		_visit_changed_due_to_divert()
		if _ptr != null:
			return
	if not _increment_pointer():
		var did_pop := false
		if _can_pop(T_FUNCTION):
			_pop_callstack()
			if _in_expr:
				_eval.append(VoidValue.new())
			did_pop = true
		elif _can_pop_thread():
			_threads.pop_back()
			did_pop = true
		elif _el()["type"] == T_GAME:
			_ptr = null
			_did_safe_exit = true
		if did_pop and _ptr != null:
			_next_content()


func _increment_pointer() -> bool:
	var p = _el()["p"]
	if p == null:
		return false
	var c: InkContainer = p[0]
	var i: int = p[1] + 1
	var ok := true
	while i >= c.content.size():
		ok = false
		var anc := c.parent
		if anc == null:
			break
		var idx := anc.content.find(c)
		if idx == -1:
			break
		c = anc
		i = idx + 1
		ok = true
	_el()["p"] = [c, i] if ok else null
	return ok


func _try_follow_default_invisible_choice() -> bool:
	if _choices.is_empty():
		return false
	for ch in _choices:
		if not ch["invisible"]:
			return false
	var ch: Dictionary = _choices[0]
	_threads = [_copy_thread(ch["thread"])]
	_set_chosen(pointer_at_path(ch["target"]), false)
	return true


func _process_choice(cp: InkObj) -> Variant:
	var flags: int = cp.b
	var show := true
	if flags & 1:
		if not _truthy(_eval.pop_back()):
			show = false
	var start_text := ""
	var only_text := ""
	var tags := []
	if flags & 4:
		only_text = _pop_choice_string(tags)
	if flags & 2:
		start_text = _pop_choice_string(tags)
	var target := _abs_path(cp.a, cp)
	if flags & 16:
		var tc = content_at_path(target)
		if tc is InkContainer and int(_visit_counts.get(tc.path(), 0)) > 0:
			show = false
	if not show:
		return null
	return {"text": (start_text + only_text).strip_edges(), "tags": tags, "target": target,
		"thread": _fork_thread(), "invisible": flags & 8 != 0}


func _pop_choice_string(tags: Array) -> String:
	var v = _eval.pop_back()
	while not _eval.is_empty() and _eval.back() is TagValue:
		tags.insert(0, _eval.pop_back().text)
	return str(v) if not v is String else v


# ---------------------------------------------------------------- 出力の流れ（C# 版の StoryState と同じ考え方）

func _push_text(s: String) -> void:
	var parts = _split_head_tail(s)
	if parts == null:
		_push_output([O_TEXT, s])
	else:
		for p in parts:
			_push_output([O_TEXT, p])


func _split_head_tail(s: String) -> Variant:
	var head_first := -1
	var head_last := -1
	for i in s.length():
		var c := s[i]
		if c == "\n":
			if head_first == -1:
				head_first = i
			head_last = i
		elif c == " " or c == "\t":
			continue
		else:
			break
	var tail_last := -1
	var tail_first := -1
	for i in range(s.length() - 1, -1, -1):
		var c := s[i]
		if c == "\n":
			if tail_last == -1:
				tail_last = i
			tail_first = i
		elif c == " " or c == "\t":
			continue
		else:
			break
	if head_first == -1 and tail_last == -1:
		return null
	var out := []
	var inner_start := 0
	var inner_end := s.length()
	if head_first != -1:
		if head_first > 0:
			out.append(s.substr(0, head_first))
		out.append("\n")
		inner_start = head_last + 1
	if tail_last != -1:
		inner_end = tail_first
	if inner_end > inner_start:
		out.append(s.substr(inner_start, inner_end - inner_start))
	if tail_last != -1 and tail_first > head_last:
		out.append("\n")
		if tail_last < s.length() - 1:
			out.append(s.substr(tail_last + 1))
	return out


static func _is_newline(o: Array) -> bool:
	return o[0] == O_TEXT and o[1] == "\n"


static func _is_nonws(o: Array) -> bool:
	if o[0] != O_TEXT:
		return false
	for c in String(o[1]):
		if c != " " and c != "\t" and c != "\n":
			return true
	return false


func _push_output(o: Array) -> void:
	var include := true
	if o[0] == O_GLUE:
		_trim_newlines()
	elif o[0] == O_TEXT:
		var func_trim := -1
		if _el()["type"] == T_FUNCTION:
			func_trim = int(_el()["fs"])
		var glue_trim := -1
		for i in range(_output.size() - 1, -1, -1):
			var x: Array = _output[i]
			if x[0] == O_GLUE:
				glue_trim = i
				break
			elif x[0] == O_CMD and x[1] == "str":
				if i >= func_trim:
					func_trim = -1
				break
		var trim := -1
		if glue_trim != -1 and func_trim != -1:
			trim = mini(func_trim, glue_trim)
		elif glue_trim != -1:
			trim = glue_trim
		else:
			trim = func_trim
		if trim != -1:
			if _is_newline(o):
				include = false
			elif _is_nonws(o):
				if glue_trim > -1:
					_remove_glue()
				if func_trim > -1:
					var cs := _cs()
					for i in range(cs.size() - 1, -1, -1):
						if cs[i]["type"] == T_FUNCTION:
							cs[i]["fs"] = -1
						else:
							break
		elif _is_newline(o):
			if _ends_in_newline() or not _contains_content():
				include = false
	if include:
		_output.append(o)


func _trim_newlines() -> void:
	var remove_from := -1
	var i := _output.size() - 1
	while i >= 0:
		var x: Array = _output[i]
		if x[0] == O_CMD or _is_nonws(x):
			break
		elif _is_newline(x):
			remove_from = i
		i -= 1
	if remove_from >= 0:
		i = remove_from
		while i < _output.size():
			if _output[i][0] == O_TEXT:
				_output.remove_at(i)
			else:
				i += 1


func _remove_glue() -> void:
	for i in range(_output.size() - 1, -1, -1):
		var x: Array = _output[i]
		if x[0] == O_GLUE:
			_output.remove_at(i)
		elif x[0] == O_CMD:
			break


func _ends_in_newline() -> bool:
	for i in range(_output.size() - 1, -1, -1):
		var x: Array = _output[i]
		if x[0] == O_CMD:
			break
		if x[0] == O_TEXT:
			if x[1] == "\n":
				return true
			elif _is_nonws(x):
				break
	return false


func _contains_content() -> bool:
	for x in _output:
		if x[0] == O_TEXT:
			return true
	return false


func _in_string_eval() -> bool:
	for i in range(_output.size() - 1, -1, -1):
		if _output[i][0] == O_CMD and _output[i][1] == "str":
			return true
	return false


func _trim_function_end() -> void:
	var start := int(_el()["fs"])
	if start == -1:
		start = 0
	for i in range(_output.size() - 1, start - 1, -1):
		var x: Array = _output[i]
		if x[0] != O_TEXT:
			continue
		var s: String = x[1]
		if s == "\n" or s.strip_edges() == "":
			_output.remove_at(i)
		else:
			break


# ---------------------------------------------------------------- 分岐と命令

func _perform(obj: Variant) -> bool:
	if not obj is InkObj:
		return false
	var o: InkObj = obj
	match o.kind:
		K_DIVERT:
			if o.c and not _truthy(_eval.pop_back()):
				return true
			if o.d == "x":
				_call_external(o.a, int(o.e))
				return true
			if o.b:
				var v = _get_var(o.a)
				if not v is DivertTarget:
					errors.append("variable %s is not a divert target" % o.a)
					return true
				_diverted = pointer_at_path(v.path)
			else:
				_diverted = pointer_at_path(o.a, o)
				if _diverted != null and _diverted[1] == -1:
					_diverted = [_diverted[0], 0]
			if o.d == "f":
				_push(T_FUNCTION)
			elif o.d == "t":
				_push(T_TUNNEL)
			if _diverted == null:
				errors.append("divert target not found: %s" % o.a)
			return true
		K_CMD:
			_command(o)
			return true
		K_ASSIGN:
			_assign(o.a, _eval.pop_back(), o.b, o.c)
			return true
		K_VARREF:
			var v = _get_var(o.a)
			if v == null:
				warnings.append("variable not found: %s" % o.a)
				v = 0
			_eval.append(v)
			return true
		K_CNT:
			var c = content_at_path(o.a, o)
			_eval.append(int(_visit_counts.get(c.path(), 0)) if c is InkContainer else 0)
			return true
		K_NATIVE:
			var n: int = NATIVES[o.a]
			var args := []
			for i in n:
				args.push_front(_eval.pop_back())
			_eval.append(_native(o.a, args))
			return true
		K_LIST:
			errors.append("LIST is not supported by the adv80s ink runtime")
			return true
	return false


func _command(o: InkObj) -> void:
	match String(o.a):
		"ev":
			_in_expr = true
		"/ev":
			_in_expr = false
		"out":
			if not _eval.is_empty():
				var v = _eval.pop_back()
				if not v is VoidValue:
					_push_text(_to_str(v))
		"nop", "thread":
			pass
		"du":
			_eval.append(_eval.back())
		"pop":
			_eval.pop_back()
		"~ret", "->->":
			var type := T_FUNCTION if o.a == "~ret" else T_TUNNEL
			var override = null
			if type == T_TUNNEL:
				var popped = _eval.pop_back()
				if popped is DivertTarget:
					override = popped
			if _el()["type"] == T_GAME:
				_ptr = null
				_did_safe_exit = true
			elif _el()["type"] != type or not _can_pop():
				errors.append("unexpected %s" % o.a)
			else:
				_pop_callstack()
				if override != null:
					_diverted = pointer_at_path(override.path)
		"str":
			_push_output([O_CMD, "str"])
			_in_expr = false
		"#":
			_push_output([O_CMD, "#"])
		"/#":
			if _in_string_eval():
				var parts := []
				var consumed := 0
				for i in range(_output.size() - 1, -1, -1):
					var x: Array = _output[i]
					consumed += 1
					if x[0] == O_CMD:
						break
					if x[0] == O_TEXT:
						parts.push_front(x[1])
				_output.resize(_output.size() - consumed)
				_eval.append(TagValue.new(_clean("".join(parts))))
			else:
				_push_output([O_CMD, "/#"])
		"/str":
			var parts := []
			var keep := []
			var consumed := 0
			for i in range(_output.size() - 1, -1, -1):
				var x: Array = _output[i]
				consumed += 1
				if x[0] == O_CMD and x[1] == "str":
					break
				if x[0] == O_TAG:
					keep.push_front(x)
				if x[0] == O_TEXT:
					parts.push_front(x[1])
			_output.resize(_output.size() - consumed)
			for k in keep:
				_push_output(k)
			_in_expr = true
			_eval.append("".join(parts))
		"choiceCnt":
			_eval.append(_choices.size())
		"turn":
			_eval.append(_turn_index + 1)
		"turns", "readc":
			var t = _eval.pop_back()
			if not t is DivertTarget:
				errors.append("%s expected a divert target" % o.a)
				return
			var c = content_at_path(t.path)
			var n: int
			if c is InkContainer:
				if o.a == "turns":
					n = _turn_index - int(_turn_indices[c.path()]) if _turn_indices.has(c.path()) else -1
				else:
					n = int(_visit_counts.get(c.path(), 0))
			else:
				n = -1 if o.a == "turns" else 0
			_eval.append(n)
		"rnd":
			var mx := int(_eval.pop_back())
			var mn := int(_eval.pop_back())
			# 本家（C#）と同じ：種 + 前の乱数で System.Random を作り、最初の値を使う
			var next := AdvDotNetRandom.new(AdvDotNetRandom.wrap32(_seed + _prev_random)).next()
			var span := mx - mn + 1
			if span <= 0 or span > 2147483647:
				errors.append("RANDOM was called with minimum as %d and maximum as %d. The maximum must be larger" % [mn, mx])
				span = maxi(1, mini(span, 2147483647))
			_eval.append(next % span + mn)
			_prev_random = next
		"srnd":
			_seed = int(_eval.pop_back())
			_prev_random = 0
			_eval.append(VoidValue.new())
		"visit":
			_eval.append(int(_visit_counts.get(_ptr[0].path(), 0)) - 1)
		"seq":
			_eval.append(_shuffle_index())
		"done":
			if _can_pop_thread():
				_threads.pop_back()
			else:
				_did_safe_exit = true
				_ptr = null
		"end":
			reset_callstack()
			_choices.clear()
			_ptr = null
			_thread()["prev"] = null
			_did_safe_exit = true
		"listInt", "range", "lrnd":
			errors.append("LIST is not supported by the adv80s ink runtime")


func _shuffle_index() -> int:
	var num := int(_eval.pop_back())
	var count := int(_eval.pop_back())
	if num <= 0:
		return 0
	var loop_index := count / num
	var iteration := count % num
	var h := 0
	for c in _ptr[0].path():
		h += c.unicode_at(0)
	var rng := AdvDotNetRandom.new(AdvDotNetRandom.wrap32(h + loop_index + _seed))
	var unpicked := range(num)
	for i in iteration + 1:
		var chosen := rng.next() % unpicked.size()
		var idx: int = unpicked[chosen]
		unpicked.remove_at(chosen)
		if i == iteration:
			return idx
	return 0


# ---------------------------------------------------------------- 変数

func _context_for(name: String) -> int:
	if _el()["temps"].has(name):
		return _cs().size()
	return 0


func _get_raw(name: String, ci: int) -> Variant:
	if ci == 0 or ci == -1:
		if globals.has(name):
			return globals[name]
	var idx := _cs().size() if ci == -1 else ci
	if idx >= 1 and idx <= _cs().size():
		var temps: Dictionary = _cs()[idx - 1]["temps"]
		if temps.has(name):
			return temps[name]
	return null


func _get_var(name: String, ci: int = -1) -> Variant:
	var v = _get_raw(name, ci)
	var guard := 0
	while v is VarPointer and guard < 32:
		v = _get_raw(v.name, v.ci)
		guard += 1
	return v


func _assign(name: String, value: Variant, is_global: bool, is_new: bool) -> void:
	var ci := -1
	var to_global := false
	if is_new:
		to_global = is_global
		if value is VarPointer:
			# 参照渡しの引数：中身ではなく、指している先を覚える（ci を決めておく）
			var vci: int = value.ci if value.ci != -1 else (0 if globals.has(value.name) else _cs().size())
			var raw = _get_raw(value.name, vci)
			value = raw if raw is VarPointer else VarPointer.new(value.name, vci)
	else:
		to_global = globals.has(name)
		var guard := 0
		while guard < 32:
			guard += 1
			var existing = _get_raw(name, ci)
			if existing is VarPointer:
				name = existing.name
				ci = existing.ci
				to_global = ci == 0
			else:
				break
	if to_global:
		var old = globals.get(name)
		globals[name] = value
		if on_variable_changed.is_valid() and old != value and _global_names.has(name):
			on_variable_changed.call(name, value)
	else:
		var idx := _cs().size() if ci == -1 else ci
		_cs()[idx - 1]["temps"][name] = value


# ---------------------------------------------------------------- 外部関数

func _call_external(name: String, n: int) -> void:
	var args := []
	for i in n:
		args.push_front(_eval.pop_back())
	var result = null
	if external_functions.has(name):
		result = (external_functions[name] as Callable).call(args)
	elif root.named.has(name):
		# 外部関数がなければ、同じ名前の ink の関数を代わりに呼ぶ（C# 版の allowExternalFunctionFallbacks と同じ）
		for a in args:
			_eval.append(a)
		_diverted = [root.named[name], 0]
		_push(T_FUNCTION)
		return
	else:
		errors.append("external function not bound: %s" % name)
		return
	_eval.append(VoidValue.new() if result == null else _coerce_in(result))


# ---------------------------------------------------------------- 計算

func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	if v is DivertTarget:
		errors.append("divert target used as a condition")
		return false
	return false


static func _to_str(v: Variant) -> String:
	if v is bool:
		return "true" if v else "false"
	if v is float:
		var f: float = v
		if f == floorf(f) and absf(f) < 1e15:
			return str(int(f))
		return str(f)
	if v is DivertTarget:
		return v.path
	if v is VarPointer:
		return v.name
	return str(v)


func _native(op: String, args: Array) -> Variant:
	# 真偽値は計算の前に整数にする
	for i in args.size():
		if args[i] is bool:
			args[i] = 1 if args[i] else 0
	if args.size() == 1:
		var x = args[0]
		match op:
			"_": return -x
			"!": return not _truthy(x)
			"FLOOR": return floorf(x) if x is float else x
			"CEILING": return ceilf(x) if x is float else x
			"INT": return int(x)
			"FLOAT": return float(x)
		errors.append("unsupported function: %s" % op)
		return 0
	var a = args[0]
	var b = args[1]
	if a is DivertTarget or b is DivertTarget:
		match op:
			"==": return a is DivertTarget and b is DivertTarget and a.path == b.path
			"!=": return not (a is DivertTarget and b is DivertTarget and a.path == b.path)
		errors.append("bad operation on divert target")
		return 0
	if a is String or b is String:
		var sa := _to_str(a)
		var sb := _to_str(b)
		match op:
			"+": return sa + sb
			"==": return sa == sb
			"!=": return sa != sb
			"?": return sa.contains(sb)
			"!?": return not sa.contains(sb)
		errors.append("bad operation on strings: %s" % op)
		return 0
	var use_float: bool = a is float or b is float
	if use_float:
		a = float(a)
		b = float(b)
	match op:
		"+": return a + b
		"-": return a - b
		"*": return a * b
		"/":
			if b == 0:
				errors.append("division by zero")
				return 0
			return a / b
		"%":
			if b == 0:
				errors.append("division by zero")
				return 0
			return fmod(a, b) if use_float else a % b
		"==": return a == b
		"!=": return a != b
		">": return a > b
		"<": return a < b
		">=": return a >= b
		"<=": return a <= b
		"&&": return a != 0 and b != 0
		"||": return a != 0 or b != 0
		"MIN": return min(a, b)
		"MAX": return max(a, b)
		"POW": return pow(float(a), float(b))
	errors.append("unsupported function: %s" % op)
	return 0


# ---------------------------------------------------------------- セーブ

func save_state() -> Dictionary:
	var threads := []
	for t in _threads:
		threads.append(_thread_to_json(t))
	var choices := []
	for ch in _choices:
		choices.append({"text": ch["text"], "tags": ch["tags"], "target": ch["target"], "invisible": ch["invisible"],
			"thread": _thread_to_json(ch["thread"])})
	return {"threads": threads, "thread_counter": _thread_counter, "globals": _values_to_json(globals),
		"visits": _visit_counts.duplicate(), "turns": _turn_indices.duplicate(), "turn": _turn_index,
		"seed": _seed, "prev_random": _prev_random, "choices": choices}


func load_state(d: Dictionary) -> void:
	_threads = []
	for t in d.get("threads", []):
		_threads.append(_thread_from_json(t))
	if _threads.is_empty():
		reset_callstack()
	_thread_counter = int(d.get("thread_counter", 0))
	var g := _values_from_json(d.get("globals", {}))
	for k in g:
		globals[k] = g[k]
	_visit_counts = d.get("visits", {}).duplicate()
	_turn_indices = d.get("turns", {}).duplicate()
	_turn_index = int(d.get("turn", -1))
	_seed = int(d.get("seed", 0))
	_prev_random = int(d.get("prev_random", 0))
	_choices = []
	for ch in d.get("choices", []):
		_choices.append({"text": ch["text"], "tags": ch.get("tags", []), "target": ch["target"],
			"invisible": ch.get("invisible", false), "thread": _thread_from_json(ch["thread"])})
	_eval.clear()
	_output.clear()
	errors.clear()


func _thread_to_json(t: Dictionary) -> Dictionary:
	var cs := []
	for e in t["cs"]:
		cs.append({"p": _ptr_to_json(e["p"]), "exp": e["exp"], "type": e["type"], "temps": _values_to_json(e["temps"]),
			"eh": e["eh"], "fs": e["fs"]})
	return {"cs": cs, "idx": t["idx"], "prev": _ptr_to_json(t["prev"])}


func _thread_from_json(d: Dictionary) -> Dictionary:
	var cs := []
	for e in d.get("cs", []):
		cs.append({"p": _ptr_from_json(e.get("p")), "exp": bool(e.get("exp", false)), "type": int(e.get("type", 0)),
			"temps": _values_from_json(e.get("temps", {})), "eh": int(e.get("eh", 0)), "fs": int(e.get("fs", -1))})
	return {"cs": cs, "idx": int(d.get("idx", 0)), "prev": _ptr_from_json(d.get("prev"))}


func _ptr_to_json(p: Variant) -> Variant:
	if p == null:
		return null
	return [p[0].path(), p[1]]


func _ptr_from_json(v: Variant) -> Variant:
	if not v is Array:
		return null
	var c = root if String(v[0]) == "" else content_at_path(String(v[0]))
	return [c, int(v[1])] if c is InkContainer else null


static func _values_to_json(d: Dictionary) -> Dictionary:
	var r := {}
	for k in d:
		var v = d[k]
		if v is DivertTarget:
			r[k] = {"^->": v.path}
		elif v is VarPointer:
			r[k] = {"^var": v.name, "ci": v.ci}
		elif v is float:
			r[k] = {"f": v}
		else:
			r[k] = v
	return r


static func _values_from_json(d: Dictionary) -> Dictionary:
	var r := {}
	for k in d:
		var v = d[k]
		if v is Dictionary:
			if v.has("^->"):
				r[k] = DivertTarget.new(String(v["^->"]))
			elif v.has("^var"):
				r[k] = VarPointer.new(String(v["^var"]), int(v.get("ci", 0)))
			elif v.has("f"):
				r[k] = float(v["f"])
		elif v is float and v == floorf(v):
			r[k] = int(v)
		else:
			r[k] = v
	return r
