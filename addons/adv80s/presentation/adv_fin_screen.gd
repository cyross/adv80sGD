class_name AdvFinScreen
extends Control
## 「おわり」の画面（6.9）。エンディングのシーンを最後まで進めたとき（シーンやプロジェクト設定の fin）や、
## 出力イベント fin.show で出す。決めた操作か時間か合図で閉じ、AdvPlayer が then に従って次へ進む。
##
## 設定（プロジェクト設定 fin、エンディングのシーンの fin、fin.show の引数の順に重ねる。false なら出さない）：
##   show      出すか（既定 true）
##   text      文（既定「おわり」。装飾記法とエイリアスも使える）  pal・size  文字の色と大きさ
##   items     複数の行と画像（スタッフロールの items と同じ書き方）。書けば text の代わりに、画面の縦の真ん中に並べる
##   image     背景の画像ID                                         fill       背景の色（パレット番号）
##   transition 出るとき・消えるときの切り替え演出
##   advance   閉じる条件の配列（既定 ["click", "key"]）：
##               "click"（クリック・決定）、"key"（どのキー・ボタンでも）、"key:Enter" など（そのキーだけ）、
##               秒数（その時間がたったら）、"trigger:名前"（AdvPlayer.fire_trigger(名前) で）
##   min_time  閉じられるようになるまでの秒数（既定 1.0。押しっぱなしで飛ばさないため）
##   then      閉じたあと："title"（既定。タイトルへ）、"new"（はじめから）、"quit"（終わる）、"stay"（そのまま）、
##             シーンID（そのシーンへ。特殊シーンも可）
##   reset     then がシーンIDのとき、始める前の状態に戻してから移るか（既定 false）
##   save_prompt  閉じたあと、クリアデータをセーブするか聞くか（既定 false）。save_prompt_text で聞く文を変えられる
##   save_resume  クリアデータをロードしたときに始めるシーン（既定は開始シーン。変数などはそのまま引き継ぐ）

signal closed

const DEFAULTS := {"show": true, "text": "おわり", "pal": 7, "size": 32, "fill": 0, "image": "",
	"transition": "cut", "advance": ["click", "key"], "min_time": 1.0, "then": "title", "reset": false,
	"save_prompt": false, "save_prompt_text": "クリアデータを セーブしますか？", "save_resume": ""}

var settings: Dictionary = {}
var reason: String = ""         ## 閉じた理由（click、key、time、trigger:名前）
var group: CanvasGroup
var _player: Node
var _transition: Dictionary = {}
var _elapsed := 0.0
var _closing := false
var _ready_to_close := false


## 設定を重ねる（false は {show: false}、true は {}）。
static func merge_settings(layers: Array) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for l in layers:
		if l is bool:
			out["show"] = l
		elif l is Dictionary:
			for k in l:
				out[k] = l[k]
	return out


func setup(player: Node, s: Dictionary) -> AdvFinScreen:
	_player = player
	settings = s
	var tpl: AdvTemplate = player.template
	var sz := Vector2(tpl.screen_size)
	position = Vector2.ZERO
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP
	_transition = player._transition_for(s.get("transition", "cut"))
	group = CanvasGroup.new()
	add_child(group)
	var bg := ColorRect.new()
	bg.color = tpl.color(int(s.get("fill", 0)))
	bg.size = sz
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(bg)
	if String(s.get("image", "")) != "":
		var tex: Texture2D = player._layer_texture(String(s["image"]))
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.size = sz
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.add_child(tr)
	if s.get("items") is Array or s.get("lines") is Array:
		# 複数の行と画像：縦の真ん中に並べる
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var margin := float(s.get("margin", 16))
		box.position = Vector2(margin, 0)
		box.size = Vector2(sz.x - margin * 2, 10)
		group.add_child(box)
		var a := s.duplicate()
		a.erase("text")
		AdvCredits.build_items(box, a, tpl, player.core.state, func(id: String) -> Texture2D: return player._layer_texture(id), sz.x - margin * 2)
		_center.call_deferred(box)
		return self
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("default_color", tpl.color(int(s.get("pal", 7))))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		label.add_theme_font_size_override(k, int(s.get("size", 32)))
	label.text = "[center]%s[/center]" % AdvTextMarkup.to_bbcode(String(s.get("text", "")), player.core.state, tpl)
	label.size = Vector2(sz.x, 10)
	label.position = Vector2(0, sz.y * float(s.get("text_y", 0.45)))
	group.add_child(label)
	return self


func _center(box: VBoxContainer) -> void:
	await get_tree().process_frame
	var h := box.get_combined_minimum_size().y
	box.size.y = h
	box.position.y = (size.y - h) / 2.0


## 出す（切り替え演出が終わるまで待つ）。
func reveal() -> void:
	await _player.screen.transition_group(group, _transition, false)


func _process(delta: float) -> void:
	if _closing:
		return
	_elapsed += delta
	_ready_to_close = _elapsed >= float(settings.get("min_time", 1.0))
	for a in settings.get("advance", []):
		if (a is float or a is int) and _elapsed >= float(a) and float(a) > 0.0:
			finish("time")
			return


func _input(event: InputEvent) -> void:
	if _closing or not event.is_pressed() or event.is_echo():
		return
	var adv: Array = settings.get("advance", [])
	var kind := ""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		kind = "click"
	elif event is InputEventKey:
		var name := OS.get_keycode_string(event.keycode)
		if ("key:" + name) in adv:
			kind = "key:" + name
		elif "key" in adv:
			kind = "key"
		elif "click" in adv and event.is_action_pressed("ui_accept"):
			kind = "click"
	elif event is InputEventJoypadButton:
		if "key" in adv:
			kind = "key"
		elif "click" in adv and event.button_index == JOY_BUTTON_A:
			kind = "click"
	elif event is InputEventScreenTouch and "click" in adv:
		kind = "click"
	if kind == "" or not (kind in adv or kind.begins_with("key:") or kind == "key"):
		return
	get_viewport().set_input_as_handled()
	if _ready_to_close:
		finish(kind)


## 合図（AdvPlayer.fire_trigger）。advance に "trigger:名前" があれば閉じる。
func trigger(name: String) -> bool:
	if _closing or not ("trigger:" + name) in settings.get("advance", []):
		return false
	finish("trigger:" + name)
	return true


## Esc も「キー」として扱う（advance に key があるときだけ）。
func handle_escape() -> void:
	if "key" in settings.get("advance", []) and _ready_to_close:
		finish("key")


func finish(why: String) -> void:
	if _closing:
		return
	_closing = true
	reason = why
	await _player.screen.transition_group(group, _transition, true)
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
