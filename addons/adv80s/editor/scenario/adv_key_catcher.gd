@tool
class_name AdvKeyCatcher
extends Node
## 窓（Window）の中に置いて、文字の欄より先にキーを受け取る（段階62）。
## handler(event) が true を返せば、その入力はそこで止める（欄には渡らない）。

var handler: Callable


func _input(event: InputEvent) -> void:
	if handler.is_valid() and bool(handler.call(event)):
		get_viewport().set_input_as_handled()
