class_name AdvParsers
extends RefCounted
## パーサープロファイルを名前で選ぶ（4.2）。"ja"（日本式、標準）、"en"（英語式）、
## またはスクリプトのパス（static func parse(text: String, core: AdvCore) -> Dictionary を持つもの）。
## 結果の形は AdvParserJa.parse と同じ（{"intent": …} か {"reply": …, "code": …}）。


static func parse(profile: String, text: String, core: AdvCore) -> Dictionary:
	match profile:
		"", "ja":
			return AdvParserJa.parse(text, core)
		"en":
			return AdvParserEn.parse(text, core)
	var s = load(profile)
	if s != null and s.has_method("parse"):
		return s.parse(text, core)
	if s != null:
		var inst = s.new()
		if inst.has_method("parse"):
			return inst.parse(text, core)
	push_error("[adv80s] パーサープロファイルが見つかりません: %s" % profile)
	return AdvParserJa.parse(text, core)
