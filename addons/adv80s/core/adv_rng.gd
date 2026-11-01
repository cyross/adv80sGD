class_name AdvRng
extends RefCounted
## Core が管理する乱数。シナリオは必ずこれを使う（セーブ・巻き戻しで同じ結果を再現するため）。

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf() -> float:
	return _rng.randf()


func pick(list: Array) -> Variant:
	if list.is_empty():
		return null
	return list[_rng.randi_range(0, list.size() - 1)]


func save_state() -> Dictionary:
	return {"seed": _rng.seed, "state": _rng.state}


func load_state(d: Dictionary) -> void:
	_rng.seed = int(d.get("seed", 0))
	_rng.state = int(d.get("state", 0))
