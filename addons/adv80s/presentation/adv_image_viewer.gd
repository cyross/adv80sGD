class_name AdvImageViewer
extends Control
## 画像を画面いっぱいに出す（おまけのギャラリー）。画像が何枚かあれば、めくれる。
## - 次へ：左クリック、決定・スペース・→・↓・ホイール下、ゲームパッドのボタン（最後の画像なら閉じる）
## - 前へ：←・↑・PageUp・ホイール上
## - 閉じる：Esc、右クリック、キャンセル

signal closed

var page := 0
var _texs: Array = []
var _rect: TextureRect
var _count: Label
var _ready_time := 0.0


## texs は Texture2D か、その並び。
func setup(texs: Variant, tpl: AdvTemplate, caption: String = "") -> AdvImageViewer:
	_texs = texs if texs is Array else [texs]
	var sz := Vector2(tpl.screen_size)
	position = Vector2.ZERO
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = tpl.color(0)
	bg.size = sz
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vr := tpl.visible_rect()   # 絵と文字は見える範囲に（段階64。FC などは上下を隠す）
	_rect = TextureRect.new()
	_rect.position = vr.position
	_rect.size = vr.size
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	if caption != "":
		var l := Label.new()
		l.text = caption
		l.add_theme_color_override("font_color", tpl.color(7))
		l.position = Vector2(vr.position.x + 8, vr.end.y - 28)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	if _texs.size() > 1:
		_count = Label.new()
		_count.add_theme_color_override("font_color", tpl.color(7))
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_count.position = Vector2(vr.end.x - 108, vr.end.y - 28)
		_count.size = Vector2(100, 24)
		_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_count)
	show_page(0)
	return self


func page_count() -> int:
	return _texs.size()


func show_page(i: int) -> void:
	page = clampi(i, 0, maxi(_texs.size() - 1, 0))
	_rect.texture = _texs[page] if not _texs.is_empty() else null
	if _count != null:
		_count.text = "%d / %d" % [page + 1, _texs.size()]


## 次の画像へ。最後なら閉じる。
func next_page() -> void:
	if page + 1 >= _texs.size():
		close()
	else:
		show_page(page + 1)


func prev_page() -> void:
	if page > 0:
		show_page(page - 1)


func _process(delta: float) -> void:
	_ready_time += delta


func _input(event: InputEvent) -> void:
	if _ready_time < 0.2 or not event.is_pressed() or event.is_echo():
		return
	var handled := true
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_RIGHT:
				close()
			MOUSE_BUTTON_WHEEL_UP:
				prev_page()
			_:
				next_page()
	elif event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				close()
			KEY_LEFT, KEY_UP, KEY_PAGEUP:
				prev_page()
			_:
				next_page()
	elif event is InputEventJoypadButton or event is InputEventScreenTouch:
		if event.is_action_pressed("ui_cancel"):
			close()
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
			prev_page()
		else:
			next_page()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func handle_escape() -> void:
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
