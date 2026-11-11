class_name AdvDotNetRandom
extends RefCounted
## .NET の System.Random（種を指定したとき）と同じ乱数（Knuth の減算法）。
## Ink の本家（C#）が RANDOM、シャッフル、最初の種に使うので、同じ種なら同じ結果になるようにする。
## 値はすべて 31 ビットに収まるので、GDScript の 64 ビット整数でそのまま計算できる。

const MBIG := 2147483647
const MSEED := 161803398

var _seed_array := PackedInt64Array()
var _inext: int = 0
var _inextp: int = 21


func _init(seed: int) -> void:
	seed = AdvDotNetRandom.wrap32(seed)
	_seed_array.resize(56)
	var subtraction := MBIG if seed == -2147483648 else absi(seed)
	var mj := MSEED - subtraction
	_seed_array[55] = mj
	var mk := 1
	for i in range(1, 55):
		var ii := (21 * i) % 55
		_seed_array[ii] = mk
		mk = mj - mk
		if mk < 0:
			mk += MBIG
		mj = _seed_array[ii]
	for k in range(1, 5):
		for i in range(1, 56):
			_seed_array[i] -= _seed_array[1 + (i + 30) % 55]
			if _seed_array[i] < 0:
				_seed_array[i] += MBIG
	_inext = 0
	_inextp = 21


## 0 以上 2147483647 未満の整数（Random.Next()）。
func next() -> int:
	var a := _inext + 1
	if a >= 56:
		a = 1
	var b := _inextp + 1
	if b >= 56:
		b = 1
	var v := _seed_array[a] - _seed_array[b]
	if v == MBIG:
		v -= 1
	if v < 0:
		v += MBIG
	_seed_array[a] = v
	_inext = a
	_inextp = b
	return v


## C# の int の足し算と同じように、32 ビットであふれた値を折り返す。
static func wrap32(v: int) -> int:
	return ((v + 2147483648) & 0xFFFFFFFF) - 2147483648
