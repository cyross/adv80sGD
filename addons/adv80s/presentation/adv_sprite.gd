class_name AdvSprite
extends Node2D
## スプライト（6.4）。画像（静止画・アニメーション画像・スプライトシート）か動画を1つ持ち、
## 位置・基準点・拡大縮小・回転・不透明度・反転・合成・色・コマ送り・効果を扱う。
## 位置は整数ピクセルにそろえる（smooth のときを除く）。

const ANCHORS := {
	"top_left": Vector2(0, 0), "top": Vector2(0.5, 0), "top_right": Vector2(1, 0),
	"left": Vector2(0, 0.5), "center": Vector2(0.5, 0.5), "right": Vector2(1, 0.5),
	"bottom_left": Vector2(0, 1), "bottom": Vector2(0.5, 1), "bottom_right": Vector2(1, 1),
}
const EFFECT_MODES := {"none": 0, "mono": 1, "sepia": 2, "silhouette": 3, "mosaic": 4}

var sprite_id: String = ""
var layer_name: String = ""
var state: Dictionary = {}          ## いまの値（セーブに使う。トゥイーンは終わりの値）

var _body: Sprite2D
var _video: VideoStreamPlayer
var _frames: Array = []             ## コマの画像（アニメーション画像・連番の差分）
var _delays: PackedFloat32Array = []
var _loop_count: int = 0
var _grid: Vector2i = Vector2i.ZERO ## スプライトシートの切り方
var _anims: Dictionary = {}         ## 名前 → {frames, fps, loop}
var _anim: Dictionary = {}          ## 再生中 {name, frames, delays, loop, i, t, played}
var _anchor: Vector2 = Vector2.ZERO
var _smooth: bool = false
var _xy: Vector2 = Vector2.ZERO
var _tweens: Array = []
## 動画の音（6.6）。既定は音を出さない。volume は 0〜1 で、BGM の音量をかけて鳴らす
var video_mute: bool = true
var video_volume: float = 1.0

## トゥイーンで動かす位置（整数にそろえる）
var xy: Vector2:
	get:
		return _xy
	set(v):
		_xy = v
		position = v if _smooth else v.round()

## 色を掛ける（tint）。不透明度は modulate.a
var tint: Color:
	get:
		return _body.self_modulate if _body != null else Color.WHITE
	set(v):
		if _body != null:
			_body.self_modulate = v
		if _video != null:
			_video.self_modulate = v


func _init() -> void:
	_body = Sprite2D.new()
	_body.centered = false
	add_child(_body)


## 見た目を決める。res は Texture2D、AdvImageFrames、VideoStream。entry はマニフェストの項目（grid、anims）。
## frame_loader は連番の差分（"name@1"）を読む関数 func(id) -> Texture2D。
func set_visual(res: Resource, entry: Dictionary = {}, frame_loader: Callable = Callable()) -> void:
	_frames = []
	_delays = []
	_grid = Vector2i.ZERO
	_anims = {}
	_anim = {}
	if _video != null:
		_video.queue_free()
		_video = null
	if res is VideoStream:
		_body.texture = null
		_video = VideoStreamPlayer.new()
		_video.stream = res
		_video.loop = true
		_video.volume_db = -80.0
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_video)
		_video.play()
		_video.size = Vector2(_video.get_video_texture().get_size()) if _video.get_video_texture() != null else Vector2.ZERO
		_apply_anchor()
		return
	if res is AdvImageFrames:
		_frames = res.frames.duplicate()
		_delays = res.delays
		_loop_count = res.loop_count
		if _frames.size() > 1:
			var idx := []
			for i in _frames.size():
				idx.append(i)
			_anims["default"] = {"frames": idx, "delays": _delays, "loop": _loop_count}
	elif res is Texture2D:
		_frames = [res]
	var g = entry.get("grid")
	if g is Array and g.size() >= 2 and not _frames.is_empty():
		_grid = Vector2i(maxi(1, int(g[0])), maxi(1, int(g[1])))
	for name in entry.get("anims", {}):
		var a: Dictionary = entry["anims"][name]
		var fr: Array = []
		for f in a.get("frames", []):
			if f is String and frame_loader.is_valid():
				var t: Texture2D = frame_loader.call(f)
				if t != null:
					_frames.append(t)
					fr.append(_frames.size() - 1 if _grid == Vector2i.ZERO else -(_frames.size()))
			else:
				fr.append(int(f))
		_anims[String(name)] = {"frames": fr, "fps": float(a.get("fps", 8)), "loop": a.get("loop", true)}
	_show_frame(0)


## 出し入れの演出のあいだだけ、絵を CanvasGroup に入れる（演出のシェーダーをスプライト1枚にかけるため）。
## スプライトそのものは層に置いたままにする（ID で探せるように）。動画のスプライトでは使わない。
var _tgroup: CanvasGroup


func begin_transition_group() -> CanvasGroup:
	if _tgroup != null and is_instance_valid(_tgroup):
		return _tgroup
	_tgroup = CanvasGroup.new()
	_tgroup.name = "Transition"
	add_child(_tgroup)
	move_child(_tgroup, _body.get_index())
	remove_child(_body)
	_tgroup.add_child(_body)
	return _tgroup


func end_transition_group() -> void:
	if _tgroup == null or not is_instance_valid(_tgroup):
		_tgroup = null
		return
	var at := _tgroup.get_index()
	_tgroup.remove_child(_body)
	add_child(_body)
	move_child(_body, at)
	_tgroup.queue_free()
	_tgroup = null


## 画面（SubViewport）の中での見えている範囲。
func screen_bounds() -> Rect2:
	var par := get_parent() as CanvasItem
	return (par.get_global_transform_with_canvas() * bounds()) if par != null else bounds()


## 動画の音量を決める（bgm_volume はプレイヤー設定の BGM の音量）。
func apply_video_audio(bgm_volume: float) -> void:
	if _video == null:
		return
	_video.volume_db = -80.0 if video_mute else linear_to_db(maxf(video_volume * bgm_volume, 0.0001))


func has_video() -> bool:
	return _video != null


func video_volume_db() -> float:
	return _video.volume_db if _video != null else -80.0


func anim_names() -> Array:
	return _anims.keys()


## コマの大きさ。
func frame_size() -> Vector2:
	if _video != null:
		return _video.size
	if _body.texture == null:
		return Vector2.ZERO
	if _body.region_enabled:
		return _body.region_rect.size
	return _body.texture.get_size()


func _show_frame(i: int) -> void:
	if _frames.is_empty():
		return
	if i < 0:
		# 連番の差分を足したコマ（スプライトシートとは別の画像）
		_body.region_enabled = false
		_body.texture = _frames[-i - 1]
	elif _grid != Vector2i.ZERO:
		var sheet: Texture2D = _frames[0]
		var fs := Vector2(sheet.get_size()) / Vector2(_grid)
		var col := i % _grid.x
		var row := (i / _grid.x) % _grid.y
		_body.texture = sheet
		_body.region_enabled = true
		_body.region_rect = Rect2(Vector2(col, row) * fs, fs)
	else:
		_body.region_enabled = false
		_body.texture = _frames[clampi(i, 0, _frames.size() - 1)]
	_apply_anchor()


func _apply_anchor() -> void:
	var off := -(_anchor * frame_size()).round()
	_body.offset = off
	if _video != null:
		_video.position = off


## 値をすぐに変える（sprite.show と、duration のない sprite.set）。
func apply(args: Dictionary) -> void:
	for k in args:
		state[k] = args[k]
	if args.has("smooth"):
		_smooth = bool(args["smooth"])
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if _smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	if args.has("anchor"):
		_anchor = ANCHORS.get(String(args["anchor"]), Vector2.ZERO)
		_apply_anchor()
	if args.has("x") or args.has("y"):
		xy = Vector2(float(args.get("x", _xy.x)), float(args.get("y", _xy.y)))
	if args.has("z"):
		z_index = int(args["z"])
	if args.has("scale"):
		scale = scale_of(args["scale"])
	if args.has("rotation"):
		rotation_degrees = float(args["rotation"])
	if args.has("opacity"):
		modulate.a = clampf(float(args["opacity"]), 0.0, 1.0)
	if args.has("visible"):
		visible = bool(args["visible"])
	if args.has("flip"):
		var f := String(args["flip"]) if args["flip"] != null else ""
		_body.flip_h = f.contains("h")
		_body.flip_v = f.contains("v")
	if args.has("tint"):
		tint = Color.html(String(args["tint"])) if args["tint"] is String and Color.html_is_valid(args["tint"]) else Color.WHITE
	if args.has("blend"):
		var mat := CanvasItemMaterial.new()
		match String(args["blend"]):
			"add": mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			"multiply": mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
			_: mat = null
		if not _body.material is ShaderMaterial:
			_body.material = mat


static func scale_of(v: Variant) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ONE * float(v)


## 値をなめらかに変える（sprite.set の duration）。終わったら finished を出す Tween を返す。
func tween_to(args: Dictionary, duration: float, ease: String = "linear", loop: int = 1, yoyo: bool = false) -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	tw.set_trans(Tween.TRANS_LINEAR if ease == "linear" else Tween.TRANS_SINE)
	tw.set_ease({"in": Tween.EASE_IN, "out": Tween.EASE_OUT, "in_out": Tween.EASE_IN_OUT}.get(ease, Tween.EASE_IN_OUT))
	if loop != 1:
		tw.set_loops(maxi(0, loop) if loop >= 0 else 0)
	var start := {"xy": _xy, "scale": scale, "rotation_degrees": rotation_degrees, "modulate": modulate, "tint": tint}
	var steps: Array = []
	if args.has("path") and args["path"] is Array:
		for p in args["path"]:
			if p is Array and p.size() >= 2:
				steps.append({"xy": Vector2(float(p[0]), float(p[1]))})
	var target := {}
	if args.has("x") or args.has("y"):
		target["xy"] = Vector2(float(args.get("x", _xy.x)), float(args.get("y", _xy.y)))
	if args.has("scale"):
		target["scale"] = scale_of(args["scale"])
	if args.has("rotation"):
		target["rotation_degrees"] = float(args["rotation"])
	if args.has("opacity"):
		var m := modulate
		m.a = clampf(float(args["opacity"]), 0.0, 1.0)
		target["modulate"] = m
	if args.has("tint") and args["tint"] is String and Color.html_is_valid(args["tint"]):
		target["tint"] = Color.html(args["tint"])
	if not target.is_empty():
		steps.append(target)
	if steps.is_empty():
		steps.append({"modulate": modulate})
	var each := duration / float(steps.size())
	for st in steps:
		var first := true
		for prop in st:
			if first:
				tw.tween_property(self, prop, st[prop], each)
				first = false
			else:
				tw.parallel().tween_property(self, prop, st[prop], each)
	if yoyo:
		var first := true
		for prop in start:
			if steps.any(func(s): return s.has(prop)):
				if first:
					tw.tween_property(self, prop, start[prop], duration)
					first = false
				else:
					tw.parallel().tween_property(self, prop, start[prop], duration)
	# セーブ用の値は終わりの値
	var keep := args.duplicate()
	for k in ["duration", "ease", "loop", "yoyo", "path", "id", "wait"]:
		keep.erase(k)
	if args.has("path") and args["path"] is Array and not args["path"].is_empty():
		var lastp: Array = args["path"][args["path"].size() - 1]
		keep["x"] = lastp[0]
		keep["y"] = lastp[1]
	for k in keep:
		state[k] = keep[k]
	if loop != 1 or yoyo:
		state["_motion"] = {"args": args.duplicate(true), "duration": duration, "ease": ease, "loop": loop, "yoyo": yoyo}
	return tw


func stop_motion() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	state.erase("_motion")


# ---------------------------------------------------------------- コマ送り

## アニメーションを再生する。name が空なら止める。loop を渡すとマニフェストの設定より優先する。
func play_anim(name: String, loop: Variant = null) -> bool:
	if name == "" or not _anims.has(name):
		_anim = {}
		state.erase("anim")
		return name == ""
	var a: Dictionary = _anims[name]
	var lp = loop if loop != null else a.get("loop", true)
	var count := 0
	if lp is bool:
		count = 0 if lp else 1
	else:
		count = int(lp)
	_anim = {"name": name, "frames": a["frames"], "delays": a.get("delays", PackedFloat32Array()),
		"fps": float(a.get("fps", 8)), "loop": count, "i": 0, "t": 0.0, "played": 0}
	state["anim"] = name
	_show_frame(int(a["frames"][0]) if not a["frames"].is_empty() else 0)
	return true


## アニメーションが動いているか。
func is_animating() -> bool:
	return not _anim.is_empty()


func _process(delta: float) -> void:
	if _anim.is_empty():
		return
	var frames: Array = _anim["frames"]
	if frames.size() <= 1:
		return
	_anim["t"] += delta
	while true:
		var i: int = _anim["i"]
		var d: PackedFloat32Array = _anim["delays"]
		var dur := float(d[i]) if i < d.size() else 1.0 / maxf(0.01, _anim["fps"])
		if _anim["t"] < dur:
			break
		_anim["t"] -= dur
		i += 1
		if i >= frames.size():
			_anim["played"] += 1
			if _anim["loop"] != 0 and _anim["played"] >= _anim["loop"]:
				_anim = {}
				return
			i = 0
		_anim["i"] = i
		_show_frame(int(frames[i]))


# ---------------------------------------------------------------- 範囲と効果

## 見えている範囲（親の座標。回転は考えない）。
func bounds() -> Rect2:
	var fs := frame_size() * scale.abs()
	return Rect2(position - (_anchor * frame_size()).round() * scale.abs(), fs)


## 親の座標の点が、見えている（透明でない）部分にあるか。
func is_opaque_at(p: Vector2) -> bool:
	if not visible or modulate.a <= 0.0:
		return false
	if _video != null:
		return bounds().has_point(p)
	var par := get_parent() as Node2D
	var local: Vector2 = _body.to_local(par.to_global(p)) if par != null else p - position
	return _body.is_pixel_opaque(local)


## 効果をかける（sprite.effect）。終わるまで待てる。
func play_effect(name: String, duration: float = -1.0, params: Dictionary = {}) -> void:
	match name:
		"flash":
			var d := duration if duration > 0.0 else 0.3
			var tw := create_tween()
			_body.modulate = Color(4, 4, 4)
			tw.tween_property(_body, "modulate", Color.WHITE, d)
			await tw.finished
		"shake":
			var d := duration if duration > 0.0 else 0.4
			var amount := float(params.get("amount", 2))
			var tw := create_tween()
			var n := maxi(2, int(d / 0.04))
			for i in n:
				tw.tween_property(_body, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)).round(), d / n)
			tw.tween_property(_body, "position", Vector2.ZERO, 0.0)
			await tw.finished
		"blink":
			var d := duration if duration > 0.0 else 0.6
			var n := maxi(2, int(d / 0.1))
			for i in n:
				_body.visible = not _body.visible
				await get_tree().create_timer(d / n).timeout
			_body.visible = true
		_:
			if EFFECT_MODES.has(name):
				if name == "none":
					_body.material = null
					state.erase("effect")
					return
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://addons/adv80s/shaders/adv_sprite.gdshader")
				sm.set_shader_parameter("mode", EFFECT_MODES[name])
				if params.has("color") and Color.html_is_valid(String(params["color"])):
					sm.set_shader_parameter("silhouette_color", Color.html(String(params["color"])))
				if params.has("cells"):
					sm.set_shader_parameter("cells", float(params["cells"]))
				_body.material = sm
				state["effect"] = {"name": name, "params": params}
			elif ResourceLoader.exists(name) and name.ends_with(".gdshader"):
				var sm2 := ShaderMaterial.new()
				sm2.shader = load(name)
				for k in params:
					sm2.set_shader_parameter(k, params[k])
				_body.material = sm2
				state["effect"] = {"name": name, "params": params}
			else:
				push_warning("[adv80s] 知らないスプライトの効果です: %s" % name)
