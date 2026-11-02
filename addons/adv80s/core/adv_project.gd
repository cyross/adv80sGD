class_name AdvProject
extends RefCounted
## プロジェクト設定（adv80s.project.json）。ゲーム全体の設定をまとめる。
##
## {
##   "project_version": 1,
##   "template": "pc98_classic",                 // 使う画面テンプレート
##   "templates": ["pc98_classic"],              // 登録するテンプレート（era_switch の判定に使う）
##   "scenarios": ["res://game/main.scenario.json"],
##   "entry": "",                                // 開始シーン（空ならシナリオの start）
##   "asset_roots": ["res://game/assets"],       // プロジェクトの素材フォルダ
##   "asset_folders": { "bg": "image", ... },   // 種類フォルダの対応表への追加・変更（null で削除）
##   "missing_asset": "placeholder",             // placeholder / error
##   "lang": "ja",
##   "verbs": ["GIVE", "SHOW"],                  // 標準で使う動詞に足す拡張の動詞（4.4）
##   "dictionaries": [], "slot_mode": "named", "intent_schema": { "entry", "layers" },
##   "event_defaults": { "text.show": { "wait": "click" } },
##   "features": { "hint": { "allow": true, "default": false, "options": {} } },
##   "transitions": { "named": { "door_open": { "type": "wipe", "direction": "right", "duration": 0.8 } } },
##   "effects": ["res://game/effects/sepia.effect.json"],  // 自作のフィルター、切り替え演出、画面効果
##   "save": { "protection": "hmac", "on_tamper": "reject", "text_format": false,
##             "dir": "user://saves", "slots": 10, "key_provider": "embedded" }
## }

const DEFAULT_PATH := "res://adv80s.project.json"

const DEFAULTS := {
	"project_version": 1,
	"template": "pc98_classic",
	"templates": [],
	"scenarios": [],
	"entry": "",
	"asset_roots": [],
	"asset_folders": {},
	"missing_asset": "placeholder",
	"lang": "ja",
	"dictionaries": [],
	"slot_mode": "named",
	"event_defaults": {},
	"features": {},
	"transitions": {},
	"effects": [],
	"save": {},
}

var data: Dictionary = DEFAULTS.duplicate(true)
var path: String = ""


## 読み込む。ファイルがなければ既定値のまま（エラーにはしない）。
static func load_project(file: String = DEFAULT_PATH, diags: Array = []) -> AdvProject:
	var p := AdvProject.new()
	p.path = file
	if file != "" and FileAccess.file_exists(file):
		var d = AdvJson.load_file(file, diags)
		if d is Dictionary:
			p.data = AdvJson.merge(DEFAULTS, d)
	return p


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


## 種類フォルダの対応表（標準の表に asset_folders を重ねたもの）。
func asset_folders() -> Dictionary:
	return AdvJson.merge_shallow(AdvAssets.DEFAULT_FOLDERS, data.get("asset_folders", {}))


## Core の setup に渡す設定。
func core_config() -> Dictionary:
	var cfg := {}
	for key in ["lang", "dictionaries", "slot_mode", "intent_schema", "event_defaults", "missing_asset", "seed", "verbs"]:
		if data.has(key):
			cfg[key] = data[key]
	return cfg
