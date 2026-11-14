extends AdvSystemScreen
## 自作のシステム画面（.tscn）の例：設定画面。BGM の音量を切り替えるボタンと、閉じるボタンだけ。

var _vol: Button


func _on_opened() -> void:
	size = Vector2(player.template.screen_size)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0.3)
	bg.size = size
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(40, 40)
	add_child(box)
	var title := Label.new()
	title.text = "じさくの せってい（%s）" % mode
	box.add_child(title)
	_vol = Button.new()
	_vol.pressed.connect(_toggle)
	box.add_child(_vol)
	var back := Button.new()
	back.text = "とじる"
	back.pressed.connect(close)
	box.add_child(back)
	_refresh()


func _toggle() -> void:
	set_setting("bgm_volume", 0.5 if float(get_setting("bgm_volume", 1.0)) == 1.0 else 1.0)
	_refresh()


func _refresh() -> void:
	_vol.text = "おんがく：%d%%" % int(round(float(get_setting("bgm_volume", 1.0)) * 100))
