@tool
class_name AdvImageFrames
extends Resource
## コマの並んだ画像（アニメーション GIF を読み込んだもの）。
## frames：各コマの画像、delays：各コマの表示時間（秒）、loop_count：繰り返す回数（0 で終わりなし）。

@export var frames: Array[Texture2D] = []
@export var delays: PackedFloat32Array = []
@export var loop_count: int = 0
@export var size: Vector2i = Vector2i.ZERO


func frame_count() -> int:
	return frames.size()


## 最初のコマ（静止画として使うとき）。
func first() -> Texture2D:
	return frames[0] if not frames.is_empty() else null
