class_name AdvContext
extends RefCounted
## シナリオアダプタに渡す、Core の窓口（5.1）。
## 状態の読み取り、条件式の評価、素材の確認、設定、表示名、乱数、診断を提供する。

var _core_ref: WeakRef  ## Core とは弱い参照でつなぐ（循環参照でメモリが解放されなくなるのを防ぐ）

var _core: AdvCore:
	get:
		return _core_ref.get_ref()


func _init(core: AdvCore) -> void:
	_core_ref = weakref(core)


## 現在の状態（読み取り専用として扱うこと。変更は出力イベントで行う）。
var state: AdvState:
	get:
		return _core.state

var rng: AdvRng:
	get:
		return _core.rng

var dictionary: AdvDictionary:
	get:
		return _core.dictionary

var schema: AdvIntentSchema:
	get:
		return _core.schema


## 条件式を評価する。st を渡すとその状態で評価する（シナリオの下書きの状態など）。
func eval(cond: Variant, st: AdvState = null) -> bool:
	return AdvCondition.evaluate(cond, st if st != null else _core.state, extra())


## 計算式を評価する。
func eval_expr(text: String, st: AdvState = null) -> Variant:
	return AdvCondition.eval_text(text, st if st != null else _core.state, extra())


## 条件式の短い文字列の形を JSON の形に変換する。
func compile(text: String) -> Variant:
	return AdvCondition.compile(text)


## 条件式の評価に使う追加の情報。
func extra() -> Dictionary:
	return {"preset": _core.preset, "group": _core.group, "features": _core.features}


func has_asset(kind: String, id: String) -> bool:
	return _core.assets.has(kind, id)


## 設定を読む。scope は project、template、preset、group、feature。
func config(scope: String, key: String, default: Variant = null) -> Variant:
	match scope:
		"preset": return _core.preset
		"group": return _core.group
		"feature": return _core.features.get(key, default)
	return _core.config.get(scope, {}).get(key, default)


## Core への問い合わせ（Core が答えるもの、積み上げているアダプタが答えるもの）。
func query(what: String, args: Dictionary = {}) -> Variant:
	return _core.query(what, args)


func verb_label(id: String) -> String:
	return _core.dictionary.verb_label(id)


func reply(code: String, params: Dictionary = {}) -> String:
	return _core.dictionary.reply(code, params)


func warn(code: String, message_ja: String, message_en: String = "") -> void:
	AdvDiag.debug_warn(code, message_ja, message_en if message_en != "" else message_ja)
