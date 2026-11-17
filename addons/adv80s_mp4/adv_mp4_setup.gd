extends Node
## 自動読み込み AdvMp4（段階70）：ゲームの始めに、MP4 の書き出しを録画（AdvCapture）に登録する。
## プロジェクト設定で "recording": {"options": {"format": "mp4"}} にすると使われる。


func _init() -> void:
	AdvMp4Encoder.register()
