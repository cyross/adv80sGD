class_name AdvDiag
extends RefCounted
## 診断（validate の結果やデバッグ警告）の形をそろえるための補助。
## 形：{severity, code, message, file, path, line?, hint?}


## 表示言語。"ja" か "en"。エディタやOSの言語から決める。
static var lang: String = ""


static func current_lang() -> String:
	if lang == "":
		lang = "ja" if OS.get_locale_language() == "ja" else "en"
	return lang


static func make(severity: String, code: String, message_ja: String, message_en: String,
		file: String = "", path: String = "") -> Dictionary:
	return {
		"severity": severity,
		"code": code,
		"message": message_ja if current_lang() == "ja" else message_en,
		"file": file,
		"path": path,
	}


## 開発中（デバッグビルド）だけ警告を出す。
static func debug_warn(code: String, message_ja: String, message_en: String) -> void:
	if OS.is_debug_build():
		push_warning("[adv80s] %s: %s" % [code, message_ja if current_lang() == "ja" else message_en])
