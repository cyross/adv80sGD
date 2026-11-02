class_name AdvAudio
extends Node
## 音（5.4 の bgm.play、bgm.stop、se.play、voice.play）。
## - BGM は2つのプレイヤーで切り替え、フェードできる。素材マニフェストの loop_start（秒）と volume を使う
## - 効果音は同時に4つまで鳴らせる
## - 音量はプレイヤー設定（bgm_volume、se_volume、voice_volume。0〜1）をかける

const SE_CHANNELS := 4

var bgm_volume: float = 1.0
var se_volume: float = 1.0
var voice_volume: float = 1.0
var current_bgm: Dictionary = {}   ## 鳴らしている BGM {id, loop, volume}（セーブに含める）

var _bgm: Array[AudioStreamPlayer] = []
var _bgm_index := 0
var _bgm_base_db: Array[float] = [0.0, 0.0]
var _se: Array[AudioStreamPlayer] = []
var _se_next := 0
var _voice: AudioStreamPlayer
var _tweens: Array = [null, null]


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "BGM%d" % i
		add_child(p)
		_bgm.append(p)
	for i in SE_CHANNELS:
		var p := AudioStreamPlayer.new()
		p.name = "SE%d" % i
		add_child(p)
		_se.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)


## 素材を読み込み、マニフェストの属性（loop_start）を反映した複製を返す。
static func load_stream(path: String, loop: bool, loop_start: float) -> AudioStream:
	var s := load(path) as AudioStream
	if s == null:
		return null
	s = s.duplicate()
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if loop:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = int(loop_start * w.mix_rate)
			var bytes_per_sample := (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
			w.loop_end = w.data.size() / bytes_per_sample
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif s.get("loop") != null:
		s.set("loop", loop)
		if s.get("loop_offset") != null:
			s.set("loop_offset", loop_start)
	return s


## BGM を鳴らす。同じ BGM を鳴らしているときは何もしない。fade は秒（前の曲を消して新しい曲を出す）。
func play_bgm(id: String, path: String, loop: bool = true, fade: float = 0.0, volume: float = 1.0, loop_start: float = 0.0) -> void:
	if current_bgm.get("id", "") == id and _bgm[_bgm_index].playing:
		return
	var stream := load_stream(path, loop, loop_start) if path != "" else null
	stop_bgm(fade)
	current_bgm = {"id": id, "loop": loop, "volume": volume}
	if stream == null:
		return
	_bgm_index = 1 - _bgm_index
	var p := _bgm[_bgm_index]
	p.stream = stream
	_bgm_base_db[_bgm_index] = linear_to_db(maxf(volume, 0.0001))
	if fade > 0.0:
		p.volume_db = -60.0
		p.play()
		_fade(_bgm_index, _db(_bgm_index), fade, false)
	else:
		p.volume_db = _db(_bgm_index)
		p.play()


func stop_bgm(fade: float = 0.0) -> void:
	var p := _bgm[_bgm_index]
	current_bgm = {}
	if not p.playing:
		return
	if fade > 0.0:
		_fade(_bgm_index, -60.0, fade, true)
	else:
		p.stop()


func play_se(path: String, volume: float = 1.0) -> void:
	var s := load(path) as AudioStream
	if s == null:
		return
	var p := _se[_se_next]
	_se_next = (_se_next + 1) % SE_CHANNELS
	p.stream = s
	p.volume_db = linear_to_db(maxf(volume * se_volume, 0.0001))
	p.play()


func play_voice(path: String, volume: float = 1.0) -> void:
	var s := load(path) as AudioStream
	if s == null:
		return
	_voice.stream = s
	_voice.volume_db = linear_to_db(maxf(volume * voice_volume, 0.0001))
	_voice.play()


func stop_voice() -> void:
	_voice.stop()


func is_voice_playing() -> bool:
	return _voice.playing


## 音量を変えたとき（設定画面）に、鳴っている BGM にも反映する。
func apply_volumes() -> void:
	for i in 2:
		if _bgm[i].playing and _tweens[i] == null:
			_bgm[i].volume_db = _db(i)


func _db(i: int) -> float:
	return _bgm_base_db[i] + linear_to_db(maxf(bgm_volume, 0.0001))


func _fade(i: int, to_db: float, dur: float, stop_after: bool) -> void:
	if _tweens[i] != null:
		_tweens[i].kill()
	var tw := create_tween()
	_tweens[i] = tw
	tw.tween_property(_bgm[i], "volume_db", to_db, dur)
	await tw.finished
	_tweens[i] = null
	if stop_after:
		_bgm[i].stop()
