class_name AdvFeatures
extends RefCounted
## モダン機能の有効・無効（10.1）。プロジェクト → テンプレート → 実行時 の順に決める。
## プロジェクトで禁止（allow: false）した機能は、後の段階で有効にできない。

## 機能のキー → [既定, 依存する機能, 条件]
const TABLE := {
	"message_log": [true, "", ""],
	"hint": [false, "", ""],
	"objective": [false, "", ""],
	"hotspot": [false, "", ""],
	"tried_marks": [false, "", ""],
	"autosave": [true, "", ""],
	"skip": [true, "", ""],
	"auto_advance": [true, "", ""],
	"rewind": [false, "message_log", ""],
	"flowchart": [false, "", ""],
	"chapter_select": [false, "", ""],
	"notebook": [false, "", ""],
	"era_switch": [false, "", "templates"],
	"readable_font": [false, "", "readable_font"],
	"text_options": [true, "", ""],
	"tts": [false, "", "tts"],
	"gamepad": [true, "", ""],
	"touch": [true, "", "touch"],
	"filter_toggle": [true, "", ""],
}

var allowed: Dictionary = {}    ## キー → 許可されているか
var enabled: Dictionary = {}    ## キー → 有効か
var options: Dictionary = {}    ## キー → 細かい設定


## 決める。env は条件の判定材料 {templates: 登録テンプレートの数, readable_font: bool, tts: bool, touch: bool}。
## runtime はプレイヤーの設定（キー → bool）。
static func resolve(project_features: Dictionary, template_features: Dictionary, env: Dictionary,
		runtime: Dictionary = {}, diags: Array = []) -> AdvFeatures:
	var f := AdvFeatures.new()
	var keys := TABLE.keys()
	var explicit := {}
	for k in project_features:
		if String(k).begins_with("x.") and not k in keys:
			keys.append(k)
	for key in keys:
		var row: Array = TABLE.get(key, [false, "", ""])
		var p = project_features.get(key, {})
		var pd: Dictionary = p if p is Dictionary else {"default": bool(p)}
		var allow := bool(pd.get("allow", true))
		var on := bool(pd.get("default", row[0]))
		if pd.has("default") or template_features.has(key) or runtime.has(key):
			explicit[key] = true
		if template_features.has(key):
			var tv = template_features[key]
			on = bool(tv.get("default", on)) if tv is Dictionary else bool(tv)
		if runtime.has(key):
			on = bool(runtime[key])
		f.allowed[key] = allow
		f.enabled[key] = allow and on
		f.options[key] = pd.get("options", {})
	# 条件と依存
	for key in keys:
		if not f.enabled[key]:
			continue
		var row: Array = TABLE.get(key, [false, "", ""])
		var reason := ""
		match String(row[2]):
			"templates":
				if int(env.get("templates", 1)) < 2:
					reason = "テンプレートが2つ以上必要です"
			"readable_font":
				if not bool(env.get("readable_font", false)):
					reason = "テンプレートに fonts.readable が必要です"
			"tts":
				if not bool(env.get("tts", false)):
					reason = "実行環境が読み上げに対応していません"
			"touch":
				if not bool(env.get("touch", true)):
					reason = "タッチ操作ができる端末ではありません"
		if reason == "" and row[1] != "" and not f.enabled.get(row[1], false):
			reason = "機能 %s が無効です" % row[1]
		if reason != "":
			f.enabled[key] = false
			if not explicit.has(key):
				continue  # 既定値のまま条件を満たさないだけなら、黙って無効にする
			diags.append(AdvDiag.make("warning", "FEATURE_DEPENDENCY", "機能 %s を無効にしました（%s）" % [key, reason],
				"Feature %s was disabled (dependency not met)" % key, "", "/features/%s" % key))
	return f


func is_on(key: String) -> bool:
	return bool(enabled.get(key, false))
