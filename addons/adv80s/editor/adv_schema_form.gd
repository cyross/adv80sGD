@tool
class_name AdvSchemaForm
extends Tree
## JSON Schema（同梱のスキーマ）から作る、JSON の編集フォーム。
## プロジェクト設定、テンプレート、マニフェストの編集画面で使う。
##
## - スキーマにある項目は、書かれていなくても灰色で並べ、＋で足せる
## - 文字列・数・真偽・選択肢（enum）はその場で編集できる。形の決まっていない値は JSON の文字列で編集する
## - 配列と、自由な名前の項目（patternProperties、additionalProperties）は ＋ で足し、− で消す
## - 型を選べる項目（anyOf、oneOf）は ⇄ で型を切り替える
## - 説明（description）はマウスを重ねると出る

signal changed

const BTN_ADD := 1
const BTN_REMOVE := 2
const BTN_SWITCH := 3

var schema_root: Dictionary = {}
var data: Variant = {}
var read_only: bool = false

var _expanded: Dictionary = {}      ## JSON Pointer → 開いているか
var _key_dialog: ConfirmationDialog
var _key_edit: LineEdit
var _key_target: Array = []         ## 名前を聞いて足す先（オブジェクトのパス）


func _init() -> void:
	columns = 2
	column_titles_visible = true
	set_column_title(0, "項目")
	set_column_title(1, "値")
	set_column_expand_ratio(0, 2)
	set_column_expand_ratio(1, 3)
	hide_root = true
	select_mode = Tree.SELECT_ROW
	item_edited.connect(_on_edited)
	button_clicked.connect(_on_button)
	item_collapsed.connect(_on_collapsed)
	_key_dialog = ConfirmationDialog.new()
	_key_dialog.title = "項目の名前"
	_key_edit = LineEdit.new()
	_key_edit.custom_minimum_size = Vector2(240, 0)
	_key_dialog.add_child(_key_edit)
	_key_dialog.register_text_enter(_key_edit)
	_key_dialog.confirmed.connect(_on_key_confirmed)
	add_child(_key_dialog)


## スキーマと値を受け取って、フォームを作り直す。
func setup(schema: Dictionary, value: Variant) -> void:
	schema_root = schema
	data = value
	_expanded.clear()
	rebuild()


func rebuild() -> void:
	var sel := ""
	var cur := get_selected()
	if cur != null and cur.get_metadata(0) is Dictionary and cur.get_metadata(0).has("path"):
		sel = pointer(cur.get_metadata(0)["path"])
	clear()
	var root := create_item()
	_build_children(root, data, schema_root, [])
	if sel != "":
		select_pointer(sel)


# ---------------------------------------------------------------- スキーマの読み方

## $ref をたどる（説明は参照元のものを優先する）。
func resolve(s: Variant) -> Dictionary:
	if not s is Dictionary:
		return {}
	var d: Dictionary = s
	var guard := 0
	while d.has("$ref") and guard < 16:
		guard += 1
		var ref := String(d["$ref"])
		var target: Variant = schema_root
		for part in ref.trim_prefix("#/").split("/"):
			target = target.get(part, {}) if target is Dictionary else {}
		var merged: Dictionary = (target as Dictionary).duplicate() if target is Dictionary else {}
		if d.has("description"):
			merged["description"] = d["description"]
		d = merged
	return d


## 型の候補（anyOf / oneOf を開いたもの）。
func branches(s: Variant) -> Array:
	var r := resolve(s)
	for key in ["anyOf", "oneOf"]:
		if r.has(key):
			var out := []
			for b in r[key]:
				var rb := resolve(b)
				if not rb.has("description") and r.has("description"):
					rb["description"] = r["description"]
				for sub in branches(rb):
					out.append(sub)
			return out
	return [r]


## 値に合う候補。値がなければ、null 以外の最初の候補。
func pick_branch(s: Variant, value: Variant) -> Dictionary:
	var bs := branches(s)
	if value != null:
		for b in bs:
			if _matches(b, value):
				return b
	for b in bs:
		if kind_of(b) != "null":
			return b
	return bs[0] if not bs.is_empty() else {}


func _matches(b: Dictionary, v: Variant) -> bool:
	if b.has("enum"):
		return v in b["enum"]
	if b.has("const"):
		return b["const"] == v
	var k := kind_of(b)
	match k:
		"object": return v is Dictionary
		"array": return v is Array
		"string": return v is String
		"integer": return v is int or (v is float and v == floorf(v))
		"number": return v is int or v is float
		"boolean": return v is bool
		"null": return v == null
	return true


## 編集の種類：object、array、string、integer、number、boolean、enum、null、any（形の決まっていない値）。
func kind_of(b: Dictionary) -> String:
	if b.has("enum"):
		return "enum"
	var t = b.get("type")
	if t is Array:
		for x in t:
			if x != "null":
				t = x
				break
	if t is String:
		return t
	if b.has("properties") or b.has("patternProperties"):
		return "object"
	if b.has("items"):
		return "array"
	return "any"


## 新しく足すときの値。
func default_for(b: Dictionary) -> Variant:
	if b.has("default"):
		return b["default"]
	match kind_of(b):
		"object":
			var d := {}
			for k in b.get("required", []):
				var ps: Dictionary = b.get("properties", {})
				if ps.has(k):
					d[k] = default_for(pick_branch(ps[k], null))
			return d
		"array": return []
		"string": return ""
		"integer": return 0
		"number": return 0.0
		"boolean": return false
		"enum":
			for e in b["enum"]:
				if e != null:
					return e
			return null
		"null": return null
	return {}


## 自由な名前の項目のスキーマ。なければ null。
func _child_schema(b: Dictionary, key: String) -> Variant:
	if b.get("properties", {}).has(key):
		return b["properties"][key]
	for pat in b.get("patternProperties", {}):
		var re := RegEx.new()
		if re.compile(String(pat)) == OK and re.search(key) != null:
			return b["patternProperties"][pat]
	var ap = b.get("additionalProperties", true)
	if ap is Dictionary:
		return ap
	if ap is bool and ap == false:
		return null
	return {}


func _allows_free_keys(b: Dictionary) -> bool:
	var ap = b.get("additionalProperties", true)
	return b.has("patternProperties") or not (ap is bool and ap == false)


# ---------------------------------------------------------------- 値の読み書き

## JSON から読んだ値の整数を int にそろえる（null はそのまま残す。テンプレートの "extends": null などで意味があるため）。
static func normalize(v: Variant) -> Variant:
	if v is Dictionary:
		var r := {}
		for k in v:
			r[k] = normalize(v[k])
		return r
	if v is Array:
		var a := []
		for x in v:
			a.append(normalize(x))
		return a
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	return v


static func pointer(path: Array) -> String:
	var parts := PackedStringArray()
	for p in path:
		parts.append(str(p).replace("~", "~0").replace("/", "~1"))
	return "" if parts.is_empty() else "/" + "/".join(parts)


func get_at(path: Array) -> Variant:
	var cur: Variant = data
	for p in path:
		if cur is Dictionary and cur.has(p):
			cur = cur[p]
		elif cur is Array and p is int and p < cur.size():
			cur = cur[p]
		else:
			return null
	return cur


func set_at(path: Array, value: Variant) -> void:
	if path.is_empty():
		data = value
		return
	var parent = get_at(path.slice(0, path.size() - 1))
	var key = path[path.size() - 1]
	if parent is Dictionary:
		parent[key] = value
	elif parent is Array and key is int:
		if key < parent.size():
			parent[key] = value
		else:
			parent.append(value)


func remove_at(path: Array) -> void:
	var parent = get_at(path.slice(0, path.size() - 1))
	var key = path[path.size() - 1]
	if parent is Dictionary:
		parent.erase(key)
	elif parent is Array and key is int and key < parent.size():
		parent.remove_at(key)


# ---------------------------------------------------------------- 組み立て

func _icon(name: String) -> Texture2D:
	if Engine.is_editor_hint():
		var th := EditorInterface.get_editor_theme()
		if th != null and th.has_icon(name, "EditorIcons"):
			return th.get_icon(name, "EditorIcons")
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _build_children(item: TreeItem, value: Variant, s: Variant, path: Array) -> void:
	var b := pick_branch(s, value)
	match kind_of(b):
		"object":
			var obj: Dictionary = value if value is Dictionary else {}
			var props: Dictionary = b.get("properties", {})
			var req: Array = b.get("required", [])
			for k in props:
				if k == "$schema":
					continue
				if obj.has(k):
					_build_item(item, k, obj[k], props[k], path + [k], not k in req)
				elif not read_only:
					_build_absent(item, k, props[k], path + [k])
			for k in obj:
				if props.has(k):
					continue
				var cs = _child_schema(b, String(k))
				_build_item(item, String(k), obj[k], cs if cs != null else {}, path + [k], true,
					cs == null)
			if _allows_free_keys(b) and not read_only:
				var add := create_item(item)
				add.set_text(0, "＋ 項目を足す")
				add.set_custom_color(0, Color(0.6, 0.8, 1.0))
				add.set_metadata(0, {"add_key": path})
				add.add_button(0, _icon("Add"), BTN_ADD, false, "名前を決めて項目を足します")
		"array":
			var arr: Array = value if value is Array else []
			var items_s = b.get("items", {})
			for i in arr.size():
				_build_item(item, "[%d]" % i, arr[i], items_s, path + [i], true)
			if not read_only:
				var add := create_item(item)
				add.set_text(0, "＋ 追加")
				add.set_custom_color(0, Color(0.6, 0.8, 1.0))
				add.set_metadata(0, {"append": path, "schema": items_s})
				add.add_button(0, _icon("Add"), BTN_ADD, false, "要素を足します")


func _build_absent(parent: TreeItem, key: String, s: Variant, path: Array) -> void:
	var it := create_item(parent)
	it.set_text(0, key)
	it.set_custom_color(0, Color(0.55, 0.55, 0.55))
	it.set_text(1, "（未設定）")
	it.set_custom_color(1, Color(0.55, 0.55, 0.55))
	var desc := String(resolve(s).get("description", ""))
	if desc == "":
		var bs := branches(s)
		if not bs.is_empty():
			desc = String(bs[0].get("description", ""))
	it.set_tooltip_text(0, desc)
	it.set_metadata(0, {"absent": path, "schema": s})
	it.add_button(1, _icon("Add"), BTN_ADD, false, "この項目を足します")


func _build_item(parent: TreeItem, key: String, value: Variant, s: Variant, path: Array, removable: bool,
		unknown: bool = false) -> void:
	var it := create_item(parent)
	var b := pick_branch(s, value)
	var k := kind_of(b)
	it.set_text(0, key)
	var desc := String(b.get("description", resolve(s).get("description", "")))
	if unknown:
		desc = "スキーマにない項目です。" + desc
		it.set_custom_color(0, Color(1, 0.75, 0.3))
	it.set_tooltip_text(0, desc)
	it.set_metadata(0, {"path": path, "schema": s, "kind": k, "branch": b})
	if not read_only:
		if branches(s).size() > 1:
			it.add_button(1, _icon("Reload"), BTN_SWITCH, false, "型を切り替えます（%s）" % _branch_names(s))
		if removable:
			it.add_button(1, _icon("Remove"), BTN_REMOVE, false, "この項目を消します")
	match k:
		"object", "array":
			it.set_text(1, _summary(value))
			it.set_custom_color(1, Color(0.6, 0.6, 0.6))
			_build_children(it, value, s, path)
			var ptr := pointer(path)
			it.collapsed = not _expanded.get(ptr, path.size() <= 1)
		"string":
			it.set_cell_mode(1, TreeItem.CELL_MODE_STRING)
			it.set_text(1, str(value))
			it.set_editable(1, not read_only)
		"integer", "number":
			it.set_cell_mode(1, TreeItem.CELL_MODE_RANGE)
			var mn := float(b.get("minimum", -1000000))
			var mx := float(b.get("maximum", 1000000))
			it.set_range_config(1, mn, mx, 1.0 if k == "integer" else 0.001)
			it.set_range(1, float(value) if value != null else 0.0)
			it.set_editable(1, not read_only)
		"boolean":
			it.set_cell_mode(1, TreeItem.CELL_MODE_CHECK)
			it.set_checked(1, bool(value))
			it.set_text(1, "有効" if bool(value) else "無効")
			it.set_editable(1, not read_only)
		"enum":
			var labels := PackedStringArray()
			for e in b["enum"]:
				labels.append("（なし）" if e == null else str(e))
			it.set_cell_mode(1, TreeItem.CELL_MODE_RANGE)
			it.set_text(1, ",".join(labels))
			it.set_range(1, max(0, b["enum"].find(value)))
			it.set_editable(1, not read_only)
		"null":
			it.set_text(1, "null")
		_:
			it.set_cell_mode(1, TreeItem.CELL_MODE_STRING)
			it.set_text(1, JSON.stringify(value))
			it.set_tooltip_text(1, "JSON で書きます")
			it.set_editable(1, not read_only)


func _branch_names(s: Variant) -> String:
	var names := PackedStringArray()
	for b in branches(s):
		names.append(kind_of(b))
	return " / ".join(names)


static func _summary(v: Variant) -> String:
	if v is Dictionary:
		return "{ %d 項目 }" % v.size()
	if v is Array:
		return "[ %d 個 ]" % v.size()
	return str(v)


# ---------------------------------------------------------------- 操作

func _on_edited() -> void:
	var it := get_edited()
	if it == null:
		return
	var m = it.get_metadata(0)
	if not m is Dictionary or not m.has("path"):
		return
	var b: Dictionary = m["branch"]
	var v: Variant
	match String(m["kind"]):
		"string":
			v = it.get_text(1)
		"integer":
			v = int(it.get_range(1))
		"number":
			v = it.get_range(1)
		"boolean":
			v = it.is_checked(1)
			it.set_text(1, "有効" if v else "無効")
		"enum":
			v = b["enum"][int(it.get_range(1))]
		_:
			var j := JSON.new()
			if j.parse(it.get_text(1)) != OK:
				push_warning("[adv80s] JSON として読めません: %s" % it.get_text(1))
				it.set_text(1, JSON.stringify(get_at(m["path"])))
				return
			v = normalize(j.data)
	set_at(m["path"], v)
	changed.emit()


func _on_button(it: TreeItem, _col: int, id: int, _mouse: int) -> void:
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	match id:
		BTN_ADD:
			if m.has("absent"):
				set_at(m["absent"], default_for(pick_branch(m["schema"], null)))
				_expanded[pointer(m["absent"])] = true
			elif m.has("append"):
				var arr = get_at(m["append"])
				if not arr is Array:
					arr = []
					set_at(m["append"], arr)
				arr.append(default_for(pick_branch(m["schema"], null)))
			elif m.has("add_key"):
				_key_target = m["add_key"]
				_key_edit.text = ""
				_key_dialog.popup_centered()
				_key_edit.grab_focus()
				return
		BTN_REMOVE:
			remove_at(m["path"])
		BTN_SWITCH:
			var bs := branches(m["schema"])
			var cur: Dictionary = m["branch"]
			var i := 0
			for j in bs.size():
				if bs[j] == cur:
					i = j
			var next: Dictionary = bs[(i + 1) % bs.size()]
			set_at(m["path"], default_for(next))
		_:
			return
	changed.emit()
	rebuild()


func _on_key_confirmed() -> void:
	var key := _key_edit.text.strip_edges()
	if key == "":
		return
	var obj = get_at(_key_target)
	if not obj is Dictionary:
		return
	if obj.has(key):
		push_warning("[adv80s] すでにある項目です: %s" % key)
		return
	var b := pick_branch(_schema_at(_key_target), obj)
	var cs = _child_schema(b, key)
	obj[key] = default_for(pick_branch(cs if cs != null else {}, null))
	_expanded[pointer(_key_target + [key])] = true
	changed.emit()
	rebuild()


## path の位置のスキーマ（値に合わせて候補を選びながらたどる）。
func _schema_at(path: Array) -> Variant:
	var s: Variant = schema_root
	var cur: Variant = data
	for p in path:
		var b := pick_branch(s, cur)
		if kind_of(b) == "array":
			s = b.get("items", {})
		else:
			var cs = _child_schema(b, str(p))
			s = cs if cs != null else {}
		cur = cur[p] if (cur is Dictionary and cur.has(p)) or (cur is Array and p is int and p < cur.size()) else null
	return s


func _on_collapsed(it: TreeItem) -> void:
	var m = it.get_metadata(0)
	if m is Dictionary and m.has("path"):
		_expanded[pointer(m["path"])] = not it.collapsed


## JSON Pointer の場所の項目を選ぶ（確認の結果から飛ぶのに使う）。見つからなければ近い親を選ぶ。
func select_pointer(ptr: String) -> void:
	var best: TreeItem = null
	var best_len := -1
	var it := get_root()
	while it != null:
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("path"):
			var p := pointer(m["path"])
			if (ptr == p or ptr.begins_with(p + "/")) and p.length() > best_len:
				best = it
				best_len = p.length()
		it = it.get_next_in_tree()
	if best != null:
		var up := best.get_parent()
		while up != null:
			up.collapsed = false
			up = up.get_parent()
		best.select(0)
		scroll_to_item(best)
