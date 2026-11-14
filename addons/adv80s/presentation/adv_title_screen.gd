class_name AdvTitleScreen
extends Control
## テンプレートで作るタイトル画面（6.9）。プロジェクト設定 title_screen: "template" のときに出す。
## 背景（プロジェクト設定 title_image か、テンプレートの title.image）、ゲームの題名、メニューを並べる。
## メニューの項目を選ぶと action に入れて閉じる（AdvPlayer が続きを行う）。
##
## メニューの項目（プロジェクト設定 title_menu か、テンプレートの title.menu）：
##   new（はじめから）、continue（つづきから）、chapters（チャプター）、endings（エンディング）、
##   opening（オープニングを見返す。プロジェクト設定 opening_replay の条件に合うときだけ）、
##   extras（おまけ。プロジェクト設定 extras の条件に合うときだけ）、settings（せってい）、quit（おわる）
## 文言はテンプレートの title.labels、プロジェクト設定 title_labels、title_variants の labels の順に重ねる。
## title_variants の menu で、並べる項目そのものも差し替えられる。
## 切り替え演出：プロジェクト設定 title_transition（なければテンプレートの title.transition）。出るときと、
## はじめから・おわるで消えるときにかける。BGM は AdvPlayer がプロジェクト設定 title_bgm で鳴らす。

signal closed

const LABELS := {"new": "はじめから", "continue": "つづきから", "chapters": "チャプター", "endings": "エンディング",
	"opening": "オープニング", "extras": "おまけ", "settings": "せってい", "quit": "おわる"}
const DEFAULT_MENU := ["new", "continue", "chapters", "endings", "opening", "extras", "settings", "quit"]

var action: String = ""     ## 選んだ項目（閉じただけなら ""）
var buttons: Dictionary = {}  ## 項目 → Button
var group: CanvasGroup        ## 中身（切り替え演出をかける）
var transition: Dictionary = {}
var _player: Node
var _busy := false


## player：項目を出すかどうかの判断と、絵・題名・演出に使う。
func setup(player: Node) -> AdvTitleScreen:
	_player = player
	var tpl: AdvTemplate = player.template
	var size_v := Vector2(tpl.screen_size)
	position = Vector2.ZERO
	size = size_v
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sec: Dictionary = tpl.get_section("title")
	var tv: Dictionary = player.title_variant()
	transition = player._transition_for(tv.get("transition", player.project.get_value("title_transition", sec.get("transition", "cut"))))
	group = CanvasGroup.new()
	add_child(group)
	var fill := ColorRect.new()
	fill.color = tpl.color(int(sec.get("fill", 0)))
	fill.size = size_v
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(fill)
	# 背景
	var img_id := String(tv.get("image", player.project.get_value("title_image", sec.get("image", ""))))
	if img_id != "":
		var tex: Texture2D = player._layer_texture(img_id)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.size = size_v
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.add_child(tr)
	# 題名
	var title := Label.new()
	title.text = String(player.project.get_value("title", sec.get("text", "")))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, size_v.y * float(sec.get("title_y", 0.25)))
	title.size = Vector2(size_v.x, 40)
	title.add_theme_color_override("font_color", tpl.color(int(sec.get("title_pal", 7))))
	title.add_theme_font_size_override("font_size", int(sec.get("title_size", 32)))
	title.visible = bool(sec.get("show_title", true))
	group.add_child(title)
	_title = title
	# メニュー
	# 項目が多い・画面が小さいときは、見える範囲に収まるよう上へ寄せ、それでも入らなければ流せる（段階65）
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 流せるが棒は出さない（選ぶと付いて流れる）
	_menu_scroll.follow_focus = true
	var w := size_v.x * 0.4
	_menu_scroll.position = Vector2((size_v.x - w) / 2, size_v.y * float(sec.get("menu_y", 0.55)))
	_menu_scroll.size = Vector2(w, size_v.y * 0.4)
	group.add_child(_menu_scroll)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_scroll.add_child(box)
	_menu_box = box
	_area = tpl.visible_rect()
	var menu: Array = tv.get("menu", player.project.get_value("title_menu", sec.get("menu", DEFAULT_MENU)))
	var labels: Dictionary = LABELS.duplicate()
	labels.merge(sec.get("labels", {}), true)
	labels.merge(player.project.get_value("title_labels", {}), true)
	labels.merge(tv.get("labels", {}), true)
	for item in menu:
		var key := String(item)
		if not _available(player, key):
			continue
		var b := Button.new()
		b.text = String(labels.get(key, key))
		if key == "extras" and bool(player.project.get_value("extras", {}).get("title_count", false)):
			player.fill_extras_sys()
			b.text += "（%d / %d）" % [int(player.core.state.sys.get("extras_opened", 0)), int(player.core.state.sys.get("extras_total", 0))]
		b.pressed.connect(func(): choose(key))
		box.add_child(b)
		buttons[key] = b
	_fit.call_deferred()
	return self


var _title: Label
var _more_up: Label     ## メニューの上にまだ項目があるしるし（段階66）
var _more_down: Label   ## 下にまだ項目があるしるし
var _menu_scroll: ScrollContainer
var _menu_box: VBoxContainer
var _area: Rect2


## 見える範囲に収める（段階65。画面に入ってフォントが決まってから）：題名は幅に入るまで文字を小さく（8 まで）、
## メニューは幅を項目に合わせ、下がはみ出すなら上へ寄せ（題名の下まで）、それでも入らなければ流せる高さにする。
func _fit() -> void:
	if not is_inside_tree():
		return
	var a := _area
	if _title != null and _title.visible:
		var fs := _title.get_theme_font_size("font_size")
		while fs > 8 and _title.get_minimum_size().x > a.size.x - 8.0:
			fs -= 2
			_title.add_theme_font_size_override("font_size", fs)
		_title.position.x = a.position.x
		_title.size.x = a.size.x
		_title.position.y = clampf(_title.position.y, a.position.y, a.end.y - _title.get_minimum_size().y)
	var need := _menu_box.get_combined_minimum_size()
	var w := clampf(maxf(_menu_scroll.size.x, need.x), 0.0, a.size.x - 8.0)
	_menu_scroll.size.x = w
	_menu_scroll.position.x = a.position.x + (a.size.x - w) / 2.0
	var top_limit := a.position.y + 4.0
	if _title != null and _title.visible:
		top_limit = _title.position.y + _title.get_minimum_size().y + 2.0
	var bottom := a.end.y - 4.0
	var y := _menu_scroll.position.y
	var h := need.y
	if y + h > bottom:
		y = maxf(top_limit, bottom - h)
	y = maxf(y, a.position.y)
	_menu_scroll.position.y = y
	_menu_scroll.size.y = minf(h, bottom - y)
	# 流せるときは、上下にまだ項目があることを ▲・▼ で知らせる（棒は出さないので。段階66）
	if _more_up == null:
		var col := _title.get_theme_color("font_color") if _title != null else Color.WHITE
		_more_up = _make_more("▲", col)
		_more_down = _make_more("▼", col)
		_menu_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_more())
		_menu_scroll.get_v_scroll_bar().changed.connect(_update_more)
	var mw := _more_up.get_minimum_size()
	_more_up.position = Vector2(minf(_menu_scroll.position.x + _menu_scroll.size.x + 2.0, a.end.x - mw.x), _menu_scroll.position.y)
	_more_down.position = Vector2(_more_up.position.x, _menu_scroll.position.y + _menu_scroll.size.y - mw.y)
	_update_more()


func _make_more(mark: String, col: Color) -> Label:
	var l := Label.new()
	l.text = mark
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	group.add_child(l)
	return l


## ▲・▼ を、流せる余りがあるときだけ出す。
func _update_more() -> void:
	if _more_up == null:
		return
	var sb := _menu_scroll.get_v_scroll_bar()
	var room := sb.max_value - sb.page
	_more_up.visible = room > 0.5 and sb.value > 0.5
	_more_down.visible = room > 0.5 and sb.value < room - 0.5


## 出す（切り替え演出が終わるまで待つ）。
func reveal() -> void:
	_busy = true
	await _player.screen.transition_group(group, transition, false)
	_busy = false
	_focus_first()


## 項目を出すか：つづきからはセーブがあるとき、チャプターとエンディングは使えるとき。
static func _available(player: Node, key: String) -> bool:
	match key:
		"continue":
			return player.list_saves().any(func(s): return s["exists"])
		"chapters":
			return player.features.is_on("chapter_select") and player.core.query("chapters") != null
		"endings":
			var e = player.project.get_value("endings", [])
			return e is Array and not e.is_empty()
		"opening":
			return player.can_replay_opening()
		"extras":
			return player.can_open_extras()
	return true


func _focus_first() -> void:
	for k in buttons:
		(buttons[k] as Button).grab_focus()
		return


## 選ぶ。はじめから・おわるは、切り替え演出で消してから閉じる。
func choose(key: String) -> void:
	if _busy:
		return
	action = key
	if key in ["new", "quit"]:
		_busy = true
		await _player.screen.transition_group(group, transition, true)
	close()


## Esc では閉じない（タイトルから先へ進むのはメニューだけ）。
func handle_escape() -> void:
	pass


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
