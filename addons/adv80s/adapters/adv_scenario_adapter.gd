class_name AdvScenarioAdapter
extends RefCounted
## シナリオエンジンとCoreをつなぐアダプタの基底クラス（5.1）。
## 返す出力イベントの配列は、入力待ち（wait が input のイベント）までをひとまとめにする。

var ctx: AdvContext


func setup(context: AdvContext) -> Error:
	ctx = context
	return OK


func load_sources(_paths: PackedStringArray) -> Error:
	return OK


func start(_entry: String) -> Array[Dictionary]:
	return []


func handle_intent(_intent: Dictionary) -> Array[Dictionary]:
	return []


## 上に積んだアダプタ（Ink など）の処理が終わり、このアダプタに戻ってきたときに呼ばれる。
## 止めていた手順の続きを実行し、出力イベントを返す。result は戻ってきたアダプタからの値。
func resume(_result: Dictionary = {}) -> Array[Dictionary]:
	return []


## 問い合わせ。知らない問い合わせには null を返す。
func query(_what: String, _args: Dictionary = {}) -> Variant:
	return null


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> Error:
	return OK


## シナリオの確認。診断の配列を返す。
func validate() -> Array[Dictionary]:
	return []
