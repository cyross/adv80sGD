class_name AdvAviEncoder
extends AdvVideoEncoder
## 本体が持つ録画の書き出し（段階69）：コマを JPEG にして、AVI（AdvAviWriter）に書く。どの環境でも使える。

var writer := AdvAviWriter.new()


func extension() -> String:
	return "avi"


func open(path: String, width: int, height: int, fps: int, audio_rate: int) -> Error:
	return writer.open(path, width, height, fps, audio_rate)


func add_video(img: Image) -> void:
	writer.add_video(img.save_jpg_to_buffer(clampf(float(options.get("quality", 0.85)), 0.05, 1.0)))


func repeat_video() -> void:
	writer.repeat_video()


func add_audio(samples: PackedVector2Array) -> void:
	writer.add_audio(AdvAviWriter.pcm16(samples))


func size() -> int:
	return writer.size()


func close() -> Dictionary:
	return writer.close()
