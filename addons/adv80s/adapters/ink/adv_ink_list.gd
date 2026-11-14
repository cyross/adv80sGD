class_name AdvInkList
extends RefCounted
## Ink の LIST の値（C# 版の InkList と同じ動き）。
## 項目は「リスト名.項目名」→ 値。並び順は C# の Dictionary と同じにする
## （消した場所は空きになり、次に足した項目がそこに入る）。LIST_RANDOM と、値が同じ項目の扱いがこの順に従う。
## 元にした ink（https://github.com/inkle/ink）：Copyright (c) 2017 inkle Ltd. MIT License

var _keys: Array = []            ## 置き場所 → 「リスト名.項目名」（空きは null）
var _vals: Array = []            ## 置き場所 → 値
var _free: Array = []            ## 空きの置き場所（後から空いたものが先に使われる）
var _slot: Dictionary = {}       ## 「リスト名.項目名」→ 置き場所
var origins: Array = []          ## 元のリストの名前（PushEvaluationStack のときに決まる）
var _initial_origins = null      ## 空のときの元のリストの名前（Array か null）


static func from_json(d: Dictionary) -> AdvInkList:
	var l := AdvInkList.new()
	if d.get("origins") is Array:
		l._initial_origins = (d["origins"] as Array).map(func(x): return String(x))
	var items = d.get("list", {})
	if items is Dictionary:
		for k in items:
			l.add(String(k), int(items[k]))
	return l


func to_json() -> Dictionary:
	var items := {}
	for k in keys():
		items[k] = _vals[_slot[k]]
	var d := {"list": items}
	if count() == 0 and origin_names() != null and not origin_names().is_empty():
		d["origins"] = origin_names().duplicate()
	return d


## 写し（C# の new InkList(other)：並びは詰める、元のリストも写す）。
func copy() -> AdvInkList:
	var l := AdvInkList.new()
	for k in keys():
		l.add(k, _vals[_slot[k]])
	var on = origin_names()
	l._initial_origins = on.duplicate() if on != null else null
	l.origins = origins.duplicate()
	return l


func count() -> int:
	return _slot.size()


func has(key: String) -> bool:
	return _slot.has(key)


func value_of(key: String) -> int:
	return int(_vals[_slot[key]])


## 項目（並び順）。
func keys() -> Array:
	var out := []
	for i in _keys.size():
		if _keys[i] != null:
			out.append(_keys[i])
	return out


## 足す（すでにあれば値を書き換える。場所は変えない）。
func add(key: String, value: int) -> void:
	if _slot.has(key):
		_vals[_slot[key]] = value
		return
	var i: int
	if not _free.is_empty():
		i = _free.pop_back()
		_keys[i] = key
		_vals[i] = value
	else:
		i = _keys.size()
		_keys.append(key)
		_vals.append(value)
	_slot[key] = i


func remove(key: String) -> void:
	if not _slot.has(key):
		return
	var i: int = _slot[key]
	_slot.erase(key)
	_keys[i] = null
	_vals[i] = 0
	_free.append(i)


static func origin_of(key: String) -> String:
	return key.get_slice(".", 0)


static func item_of(key: String) -> String:
	return key.substr(key.find(".") + 1)


## 元のリストの名前（項目があれば項目から、なければ最初に決めた名前）。
func origin_names() -> Variant:
	if count() > 0:
		return keys().map(func(k): return origin_of(k))
	return _initial_origins


func set_initial_origin_names(names: Variant) -> void:
	_initial_origins = (names as Array).duplicate() if names is Array else null


## 値の最も大きい項目（同じ値なら先にあるもの）。なければ ""。
func max_key() -> String:
	var best := ""
	var bv := 0
	for k in keys():
		var v := value_of(k)
		if best == "" or v > bv:
			best = k
			bv = v
	return best


func min_key() -> String:
	var best := ""
	var bv := 0
	for k in keys():
		var v := value_of(k)
		if best == "" or v < bv:
			best = k
			bv = v
	return best


func max_value() -> int:
	var k := max_key()
	return value_of(k) if k != "" else 0


func min_value() -> int:
	var k := min_key()
	return value_of(k) if k != "" else 0


## 表示（値の小さい順、同じ値ならリスト名の順に、項目名を「, 」でつなぐ）。
func _to_string() -> String:
	var ks := keys()
	ks.sort_custom(func(a, b):
		var va := value_of(a)
		var vb := value_of(b)
		if va == vb:
			return origin_of(a) < origin_of(b)
		return va < vb)
	return ", ".join(ks.map(func(k): return item_of(k)))


func equals(o: AdvInkList) -> bool:
	if o.count() != count():
		return false
	for k in keys():
		if not o.has(k):
			return false
	return true


func union(o: AdvInkList) -> AdvInkList:
	var r := copy()
	for k in o.keys():
		r.add(k, o.value_of(k))
	return r


func intersect(o: AdvInkList) -> AdvInkList:
	var r := AdvInkList.new()
	for k in keys():
		if o.has(k):
			r.add(k, value_of(k))
	return r


func without(o: AdvInkList) -> AdvInkList:
	var r := copy()
	for k in o.keys():
		r.remove(k)
	return r


func contains(o: AdvInkList) -> bool:
	if o.count() == 0 or count() == 0:
		return false
	for k in o.keys():
		if not has(k):
			return false
	return true


func greater_than(o: AdvInkList) -> bool:
	if count() == 0:
		return false
	if o.count() == 0:
		return true
	return min_value() > o.max_value()


func greater_or_equal(o: AdvInkList) -> bool:
	if count() == 0:
		return false
	if o.count() == 0:
		return true
	return min_value() >= o.min_value() and max_value() >= o.max_value()


func less_than(o: AdvInkList) -> bool:
	if o.count() == 0:
		return false
	if count() == 0:
		return true
	return max_value() < o.min_value()


func less_or_equal(o: AdvInkList) -> bool:
	if o.count() == 0:
		return false
	if count() == 0:
		return true
	return max_value() <= o.max_value() and min_value() <= o.min_value()


func max_as_list() -> AdvInkList:
	var r := AdvInkList.new()
	var k := max_key()
	if k != "":
		r.add(k, value_of(k))
	return r


func min_as_list() -> AdvInkList:
	var r := AdvInkList.new()
	var k := min_key()
	if k != "":
		r.add(k, value_of(k))
	return r


## LIST_RANGE。min・max は int か AdvInkList。
func sub_range(min_bound: Variant, max_bound: Variant) -> AdvInkList:
	var r := AdvInkList.new()
	if count() == 0:
		return r
	var lo := 0
	var hi := 2147483647
	if min_bound is int:
		lo = min_bound
	elif min_bound is AdvInkList and min_bound.count() > 0:
		lo = min_bound.min_value()
	if max_bound is int:
		hi = max_bound
	elif max_bound is AdvInkList and max_bound.count() > 0:
		hi = max_bound.max_value()
	r.set_initial_origin_names(origin_names())
	for k in keys():
		var v := value_of(k)
		if v >= lo and v <= hi:
			r.add(k, v)
	return r


## 元のリストのすべての項目（all）、または入っていないもの（inverse）。defs は リスト名 → {項目名: 値}。
func all_items(defs: Dictionary, inverse: bool) -> AdvInkList:
	var r := AdvInkList.new()
	for o in origins:
		var def: Dictionary = defs.get(o, {})
		for item in def:
			var k := "%s.%s" % [o, item]
			if inverse:
				if not has(k) and not r.has(k):
					r.add(k, int(def[item]))
			else:
				r.add(k, int(def[item]))
	return r
