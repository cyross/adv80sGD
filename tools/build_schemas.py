# adv80s の JSON Schema（draft-07）を日本語版と英語版で書き出す。
# 開発用の補助スクリプト（フレームワークの実行には不要）。スキーマを直すときはこのファイルを直して再生成する。
# 使い方: python3 build_schemas.py <addons/adv80s/schemas>
import json, os, sys, copy

OUT = sys.argv[1]
LANG = None  # "ja" / "en"


def t(ja, en):
    return {"__t": True, "ja": ja, "en": en}


def resolve(o):
    if isinstance(o, dict):
        if o.get("__t"):
            return o[LANG]
        return {k: resolve(v) for k, v in o.items()}
    if isinstance(o, list):
        return [resolve(v) for v in o]
    return o


def obj(props, desc=None, required=None, extra=True, **kw):
    """additionalProperties は false。ext と x.* の項目は自由に書ける。"""
    p = dict(props)
    s = {"type": "object", "properties": p, "additionalProperties": False}
    if extra:
        p.setdefault("ext", {"type": "object", "description": t("拡張領域。中身は自由", "Extension area. Free-form")})
        s["patternProperties"] = {"^x\\.": {"description": t("自作の項目（x.名前）", "Custom property (x.name)")}}
    if desc:
        s["description"] = desc
    if required:
        s["required"] = required
    s.update(kw)
    return s


def mapof(value, desc=None, key_pattern=None):
    s = {"type": "object", "additionalProperties": value}
    if key_pattern:
        s = {"type": "object", "patternProperties": {key_pattern: value}, "additionalProperties": False}
    if desc:
        s["description"] = desc
    return s


STR = {"type": "string"}
INT = {"type": "integer"}
NUM = {"type": "number"}
BOOL = {"type": "boolean"}
STRS = {"type": "array", "items": STR}
RECT = {"type": "array", "items": INT, "minItems": 4, "maxItems": 4,
        "description": t("[x, y, 幅, 高さ]（元の解像度のピクセル）", "[x, y, width, height] in native pixels")}
VERB_ID = "^[A-Z][A-Z0-9_]*$"
FEATURE_KEYS = ["message_log", "hint", "objective", "hotspot", "tried_marks", "autosave", "skip",
                "auto_advance", "rewind", "flowchart", "chapter_select", "notebook", "era_switch",
                "readable_font", "text_options", "tts", "gamepad", "touch", "filter_toggle"]
EVENT_TYPES = ["text.show", "text.append", "text.clear", "image.show", "image.hide", "effect.play",
               "bgm.play", "bgm.stop", "se.play", "voice.play", "state.set", "item.add", "item.remove",
               "scene.goto", "wait", "group", "choice.show", "input.request", "game.end", "verbs.update",
               "hotspots.update", "input.mode", "notebook.add", "objective.set", "hint.set", "flow.mark",
               "checkpoint", "template.switch", "layout.set", "save.request"]
WAIT = {"anyOf": [{"type": "string", "enum": ["none", "click", "end", "input"]}, {"type": "number", "minimum": 0}],
        "description": t("次に進む条件。none、click、end、input、または秒数", "When to continue: none, click, end, input, or seconds")}

# ---------------------------------------------------------------- 共通の定義

COND_DEFS = {
    "condition": {
        "description": t("条件式（5.8）。JSONの形か、短い文字列の形（例：\"has_key and money >= 100\"）",
                         "Condition (5.8). JSON form or short string form (e.g. \"has_key and money >= 100\")"),
        "anyOf": [
            {"type": "string", "minLength": 1},
            {"type": "boolean"},
            {"type": "array", "items": {"$ref": "#/definitions/condition"}},
            obj({
                "all": {"type": "array", "items": {"$ref": "#/definitions/condition"}, "description": t("すべて満たす", "All must hold")},
                "any": {"type": "array", "items": {"$ref": "#/definitions/condition"}, "description": t("どれかを満たす", "Any must hold")},
                "not": {"$ref": "#/definitions/condition", "description": t("満たさない", "Must not hold")},
                "var": {"type": "string", "description": t("比べる変数", "Variable to compare")},
                "calc": {"type": "string", "description": t("比べる計算式", "Expression to compare")},
                "count": {"type": "string", "description": t("アイテムの個数", "Item count")},
                "has": {"type": "string", "description": t("アイテムを持っているか", "Has the item")},
                "scene": {"type": "string", "description": t("現在のシーン", "Current scene")},
                "visited": {"type": "string", "description": t("訪れたシーン", "Visited scene")},
                "talked": {"type": "string", "description": t("見た会話", "Seen dialogue")},
                "read": {"type": "string", "description": t("読んだ行", "Read line")},
                "chosen": {"type": "array", "items": STR, "minItems": 2, "maxItems": 2,
                           "description": t("[選択肢ID, 項目ID]", "[choice ID, option ID]")},
                "preset": {"type": "string", "description": t("画面プリセット", "Screen preset")},
                "group": {"type": "string", "description": t("プリセットのグループ", "Preset group")},
                "feature": {"type": "string", "description": t("有効なモダン機能", "Enabled modern feature")},
                "eq": {"description": t("等しい", "Equal")},
                "ne": {"description": t("等しくない", "Not equal")},
                "lt": {"description": t("未満", "Less than")},
                "le": {"description": t("以下", "Less or equal")},
                "gt": {"description": t("より大きい", "Greater than")},
                "ge": {"description": t("以上", "Greater or equal")},
                "in": {"type": "array", "description": t("いずれかと一致", "Equals one of")},
            }, extra=False),
        ],
    },
}

STEP_DEFS = {
    "step": {
        "description": t("手順。文字列（地の文、\"@話者ID 文章\"）、手順の配列、または手順のオブジェクト",
                         "Step. A string (narration or \"@speaker text\"), an array of steps, or a step object"),
        "anyOf": [
            {"type": "string"},
            {"type": "array", "items": {"$ref": "#/definitions/step"}},
            {"$ref": "#/definitions/step_object"},
        ],
    },
    "step_object": {
        "anyOf": [
            obj({"if": {"$ref": "#/definitions/condition"}, "then": {"$ref": "#/definitions/step"},
                 "else": {"$ref": "#/definitions/step"}}, t("条件分岐", "Conditional"), ["if"], extra=False),
            obj({"set": {"type": "object", "description": t("変数の変更。値が \"=\" で始まる文字列なら計算式",
                                                             "Variable changes. A string value starting with \"=\" is an expression")}},
                t("変数の変更", "Set variables"), ["set"], extra=False),
            obj({"let": {"type": "string", "description": t("\"変数 = 式; …\"", "\"var = expr; ...\"")}},
                t("計算式による変更", "Assign by expressions"), ["let"], extra=False),
            obj({"say": STR, "text": STR, "id": STR, "voice": STR},
                t("台詞（IDやボイスを付けられる書き方）", "Line of dialogue with ID or voice"), ["say", "text"], extra=False),
            obj({"goto": {"type": "string", "description": t("移る先（会話ID、またはシーンID）。戻らない", "Jump target (dialogue or scene). Does not return")}},
                None, ["goto"], extra=False),
            obj({"call": {"type": "string", "description": t("呼ぶ会話ID。終わったら戻る", "Dialogue to call. Returns afterwards")}},
                None, ["call"], extra=False),
            obj({"dialogue": {"type": "string", "description": t("呼ぶ会話ID", "Dialogue to run")}}, None, ["dialogue"], extra=False),
            obj({"ink": {"type": "string", "description": t("Inkのノット名", "Ink knot name")}}, None, ["ink"], extra=False),
            obj({"choice": obj({
                "id": STR, "prompt": STR,
                "options": {"type": "array", "items": obj({
                    "id": STR, "label": STR, "do": {"$ref": "#/definitions/step"},
                    "when": {"$ref": "#/definitions/condition"}, "once": BOOL}, None, ["label"])},
            }, None, ["options"])}, t("選択肢", "Choice"), ["choice"], extra=False),
            {"$ref": "#/definitions/event"},
            {"type": "object", "description": t("出力イベントの短い書き方（{\"image.show\": {…}}）", "Output event shorthand ({\"image.show\": {...}})"),
             "properties": {"checkpoint": {"type": "object"}, "wait": {"type": "object"}, "group": {"type": "object"}},
             "patternProperties": {"^(x\\.)?[a-z_]+\\.[a-z_]+$": {"type": "object"}}, "additionalProperties": False},
        ]
    },
    "event": obj({
        "type": {"type": "string", "description": t("イベントの種類（分類.動作）", "Event type (category.action)"),
                 "anyOf": [{"enum": EVENT_TYPES}, {"pattern": "^x\\."}]},
        "args": {"type": "object"},
        "wait": WAIT,
        "id": STR,
        "log": BOOL,
    }, t("出力イベント（5.4）", "Output event (5.4)"), ["type"], extra=True),
}

ON_MAP = {"type": "object", "description": t("動詞ごとの反応。\"USE+door\" のように with の対象を指定できる",
                                             "Reaction per verb. \"USE+door\" narrows by the with target"),
          "patternProperties": {"^[A-Z][A-Z0-9_]*(\\+[^+]+)?$": {"$ref": "#/definitions/step"}},
          "additionalProperties": False}

EVENT_DEFAULTS = {"type": "object", "description": t("出力イベントの既定値（wait など）の書き換え", "Overrides for output event defaults (wait, etc.)"),
                  "additionalProperties": obj({"wait": WAIT, "log": BOOL}, extra=False)}

# ---------------------------------------------------------------- scenario

scene_props = {
    "name": {"type": "string", "description": t("表示名", "Display name")},
    "image": {"type": "string", "description": t("背景の画像ID（またはパス）", "Background image ID (or path)")},
    "first": {"$ref": "#/definitions/step", "description": t("初めて入ったときの手順", "Steps on first visit")},
    "enter": {"$ref": "#/definitions/step", "description": t("入ったときの手順（first があれば2回目以降）", "Steps on entering (after the first visit if first exists)")},
    "objects": mapof(obj({
        "names": {**STRS, "description": t("コマンド入力で認識する呼び名", "Names recognized by the parser")},
        "label": {"type": "string", "description": t("コマンド選択に出す名前", "Label shown in command select")},
        "region": RECT,
        "character": {"type": "string", "description": t("人物として扱うときの話者ID", "Speaker ID when this is a character")},
        "when": {"$ref": "#/definitions/condition", "description": t("表示する条件", "Visible when")},
        "on": ON_MAP,
    }), t("シーンの中の物や人物", "Objects and characters in the scene")),
    "exits": mapof({"anyOf": [{"type": "boolean"}, obj({
        "names": STRS, "label": STR, "when": {"$ref": "#/definitions/condition"}, "on": ON_MAP})]},
        t("出口（行き先のシーンID → 設定）", "Exits (target scene ID -> settings)")),
    "on": ON_MAP,
}

SCENARIO = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "adv80s/scenario.schema.json",
    "title": t("adv80s シナリオ", "adv80s scenario"),
    "description": t("JSONシナリオ（5.2、5.7、5.8）", "JSON scenario (5.2, 5.7, 5.8)"),
    **obj({
        "$schema": STR,
        "scenario_version": INT,
        "start": {"type": "string", "description": t("開始シーンID", "Start scene ID")},
        "scene": {"type": "string", "description": t("シーン1つだけのファイルのときのシーンID", "Scene ID for a single-scene file")},
        **scene_props,
        "variables": mapof(obj({"type": {"enum": ["bool", "int", "float", "string"]}, "default": {}}, extra=False),
                           t("変数の宣言（任意）", "Variable declarations (optional)")),
        "characters": mapof(obj({"name": STR, "names": STRS, "pal": INT, "voice": STR}), t("話者", "Speakers")),
        "items": mapof(obj({"name": STR, "names": STRS, "on": ON_MAP}), t("アイテム", "Items")),
        "scenes": mapof(obj(scene_props), t("シーン", "Scenes")),
        "dialogues": mapof({"$ref": "#/definitions/step"}, t("会話（手順の配列）", "Dialogues (arrays of steps)")),
        "topics": mapof({"type": "array", "items": obj({"id": STR, "label": STR, "names": STRS, "dialogue": STR,
                                                        "when": {"$ref": "#/definitions/condition"}}, None, ["id", "dialogue"])},
                        t("話題（話者ID → 話題の一覧）", "Topics (speaker ID -> topics)")),
        "nouns": mapof(STRS, t("名詞の言い換え", "Noun synonyms")),
        "replies": mapof(STR, t("決まった返事の上書き", "Override fixed replies")),
        "verbs": {"type": "object", "description": t("辞書の動詞の上書き", "Override dictionary verbs")},
        "particles": STRS,
        "intent_schema": {"type": "object", "description": t("このシナリオの意図スキーマの層", "Intent schema layer of this scenario")},
        "event_defaults": EVENT_DEFAULTS,
        "assets": obj({"root": STR, "manifest": STR}, t("シナリオが持つ素材フォルダ", "Asset folder of this scenario"), extra=False),
        "flow": obj({
            "nodes": {"type": "array", "items": obj({"id": STR, "label": STR, "chapter": STR}, None, ["id"])},
            "edges": {"type": "array", "items": obj({"from": STR, "to": STR}, None, ["from", "to"], extra=False)},
        }, t("フローチャートの構造。点への到達は flow.mark で記録する", "Flowchart structure. Reaching a node is recorded with flow.mark")),
        "chapters": {"type": "array", "description": t("チャプター（node はフローチャートの点。到達すると選べるようになる）", "Chapters (node is a flowchart node; unlocked when reached)"),
                     "items": obj({"id": STR, "label": STR, "node": STR, "unlocked": BOOL}, None, ["id", "label"])},
    }),
    "definitions": {**COND_DEFS, **STEP_DEFS},
}

# ---------------------------------------------------------------- template

SKIN = obj({
    "type": {"enum": ["box", "nine_patch"], "description": t("box：パレットの色で枠線、nine_patch：9分割画像", "box: palette border, nine_patch: 9-slice image")},
    "border": INT, "pal": INT, "fill": INT,
    "image": STR, "margins": {"type": "array", "items": INT, "minItems": 4, "maxItems": 4},
}, extra=False)

REGION = obj({"rect": RECT, "window": STR, "visible": {"type": "boolean", "description": t("false でこの区割りを隠す（名前付きのレイアウト用）", "false hides this region (for named layouts)")}}, extra=False)

TEMPLATE = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "adv80s/template.schema.json",
    "title": t("adv80s 画面テンプレート", "adv80s screen template"),
    **obj({
        "$schema": STR,
        "template_version": INT,
        "id": {"type": "string", "description": t("テンプレートID", "Template ID")},
        "name": {"type": "string", "description": t("表示名", "Display name")},
        "extends": {"type": ["string", "null"], "description": t("継承元のテンプレートID", "Parent template ID")},
        "display": obj({
            "preset": {"type": "string", "description": t("画面プリセット（機種ID または 機種ID.モード名）", "Screen preset (machine ID or machine.mode)")},
            "scale": {"enum": ["integer", "fit", "none"]},
            "aspect_correction": BOOL,
        }, extra=False),
        "palette": obj({"source": {"enum": ["preset", "colors"]},
                        "colors": {"type": "array", "items": {"type": "string", "pattern": "^#?[0-9a-fA-F]{6}$"}}}, extra=False),
        "fonts": mapof({"anyOf": [
                           {"type": "null"},
                           {"$ref": "#/definitions/font_entry"},
                           {"type": "array", "items": {"$ref": "#/definitions/font_entry"}, "minItems": 1}]},
                       t("フォント（main、readable）。候補の配列で書くと、素材が見つかった最初のものを使う", "Fonts (main, readable). With an array of candidates, the first one found is used")),
        "layout": obj({
            "background": {"type": "integer", "description": t("背景のパレット番号", "Background palette index")},
            "layers": {**STRS, "description": t("画像の層（奥から順）", "Image layers (back to front)")},
            "regions": mapof({"anyOf": [REGION, {"type": "null"}]}, t("画面の区割り", "Screen regions")),
            "named": mapof(obj({"regions": mapof({"anyOf": [REGION, {"type": "null"}]})}, extra=False), t("名前付きのレイアウト", "Named layouts")),
        }, extra=False),
        "inputs": obj({"enabled": {"type": "array", "items": {"enum": ["select", "parser", "icon", "click"]}},
                       "parser_profile": STR,
                       "command_columns": {"type": "integer", "minimum": 1, "description": t("コマンド選択の列の数（既定 2）", "Columns of the command list (default 2)")}}, extra=False),
        "text": obj({
            "speed": {"type": "number", "minimum": 0, "description": t("1秒あたりの文字数（0で一度に表示）", "Characters per second (0 = instant)")},
            "markup": STR,
            "ruby": {"enum": ["above", "paren", "none"]},
            "emphasis": {"enum": ["above", "paren", "none"]},
            "color": INT, "name_color": INT,
            "denied_tags": STRS,
        }, extra=False),
        "filters": {"anyOf": [
            obj({"mode": {"enum": ["default", "append", "replace", "none"]},
                 "list": {"type": "array", "items": {"$ref": "#/definitions/filter"}}}, extra=False),
            {"type": "array", "items": {"$ref": "#/definitions/filter"}, "description": t("配列で書くと replace と同じ", "An array means replace")}]},
        "transitions": obj({"default": STR, "named": {"type": "object"}, "replace": mapof(STR)}, extra=False),
        "features": {"type": "object", "description": t("モダン機能の既定値の上書き", "Override modern feature defaults")},
        "assets": obj({"root": STR, "manifest": STR}, extra=False),
        "ui": obj({"window_skin": SKIN, "cursor": STR, "highlight": INT,
                   "window_padding": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2,
                                      "description": t("窓の内側の余白 [横, 縦]（既定 [8, 4]）", "Inner padding of windows [x, y] (default [8, 4])")}}),
    }, required=["template_version", "id"]),
    "definitions": {
        "font_entry": {"type": "object", "additionalProperties": False, "properties": {
            "asset": {"type": "string", "description": t("フォントの素材ID（font フォルダのファイル名）", "Font asset ID (file name in the font folder)")},
            "size": INT,
            "line_height": {"type": "integer", "description": t("行の高さ（省略時は size）", "Line height (defaults to size)")}}},
        "filter": {"anyOf": [
            {"type": "string"},
            {"type": "object", "required": ["type"], "description": t("フィルター（type と引数）", "Filter (type and arguments)"),
             "properties": {
                 "type": {"type": "string", "description": t("scanline、reduce、dither、bleed、crt、rgb_mask、mono、lcd、aspect、または自作のID",
                                                             "scanline, reduce, dither, bleed, crt, rgb_mask, mono, lcd, aspect, or a custom ID")},
                 "intensity": NUM, "amount": NUM, "curvature": NUM, "vignette": NUM, "grid": NUM,
                 "color": STR, "bits": {"type": "array", "items": INT}, "colors": STRS, "dither": NUM}},
        ]},
    },
}

# ---------------------------------------------------------------- intent_schema

SLOT = obj({"name": STR, "type": STR, "particles": STRS, "required": BOOL}, required=["name", "type"], extra=False)
INTENT_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "adv80s/intent_schema.schema.json",
    "title": t("adv80s 意図スキーマ", "adv80s intent schema"),
    **obj({
        "$schema": STR,
        "schema_version": INT,
        "types": mapof({"anyOf": [{"type": "null"}, obj({
            "base": STR, "handler": STR, "min": NUM, "max": NUM, "values": {"type": "array"},
            "pattern": STR, "min_length": INT, "max_length": INT}, extra=False)]},
            t("自作の型（base＋制約、または handler）。null で取り除く", "Custom types (base + constraints, or handler). null removes")),
        "verbs": {"type": "object", "description": t("動詞ID → スロットの定義。null で取り除く", "Verb ID -> slot definitions. null removes"),
                  "patternProperties": {VERB_ID: {"anyOf": [
                      {"type": "null"},
                      obj({"slots": {"type": "array", "items": SLOT}}, t("完全形", "Full form"), ["slots"], extra=False),
                      {"type": "object", "description": t("省略形（\"target\": \"object\"、\"with\": \"item?\"）", "Shorthand (\"target\": \"object\", \"with\": \"item?\")"),
                       "additionalProperties": {"type": "string", "pattern": "^[a-z_][a-z0-9_]*\\??$"}},
                  ]}}, "additionalProperties": False},
    }, required=["schema_version"]),
}

# ---------------------------------------------------------------- manifest

def asset_entry():
    return obj({
        "type": {"enum": ["image", "bgm", "se", "voice", "font", "shader"]},
        "file": {"type": "string", "description": t("既定のファイル（base からの相対パス）", "Default file (relative to base)")},
        "by_preset": mapof({"anyOf": [STR, obj({"file": STR, "variants": mapof(STR)}, extra=False)]},
                           t("機種別の差し替え（プリセットID、機種ID、グループID）", "Per-preset overrides (preset, machine or group ID)")),
        "variants": mapof(STR, t("差分（表情など）", "Variants (expressions, etc.)")),
        "pivot": {"type": "array", "items": NUM, "minItems": 2, "maxItems": 2},
        "region": RECT,
        "loop_start": {"type": "number", "minimum": 0, "description": t("ループの開始位置（秒）", "Loop start (seconds)")},
        "volume": NUM,
    })


MANIFEST = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "adv80s/manifest.schema.json",
    "title": t("adv80s 素材マニフェスト", "adv80s asset manifest"),
    **obj({
        "$schema": STR,
        "manifest_version": INT,
        "generated": {"type": "boolean", "description": t("自動生成されたマニフェストなら true", "true for generated manifests")},
        "base": {"type": "string", "description": t("ファイルの基準フォルダ（省略時はマニフェストのあるフォルダ）", "Base folder (defaults to the manifest folder)")},
        "assets": {"type": "object", "description": t("ID（または 種類:ID）→ 素材", "ID (or kind:ID) -> asset"),
                   "patternProperties": {"^[^/]+$": asset_entry()}, "additionalProperties": False},
    }, required=["manifest_version"], extra=False),
}

# ---------------------------------------------------------------- project

FEATURE = obj({"allow": BOOL, "default": BOOL, "options": {"type": "object"}}, extra=False)
PROJECT = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "adv80s/project.schema.json",
    "title": t("adv80s プロジェクト設定", "adv80s project settings"),
    **obj({
        "$schema": STR,
        "project_version": INT,
        "template": {"type": "string", "description": t("使う画面テンプレートのID", "Screen template ID")},
        "templates": {**STRS, "description": t("登録するテンプレート", "Registered templates")},
        "scenarios": {**STRS, "description": t("シナリオファイル（.ink.json は Ink のアダプタが読む）", "Scenario files (.ink.json files go to the Ink adapter)")},
        "ink": obj({"sync_variables": {"type": "boolean", "description": t("Ink の中で変わったグローバル変数を Core の状態に返す（既定 true）", "Write ink global variable changes back to Core state (default true)")}}, extra=False),
        "entry": {"type": "string", "description": t("開始シーン（空ならシナリオの start）", "Entry scene (empty = scenario start)")},
        "asset_roots": {**STRS, "description": t("プロジェクトの素材フォルダ", "Project asset folders")},
        "asset_folders": mapof({"type": ["string", "null"], "enum": ["image", "bgm", "se", "voice", "font", "shader", None]},
                               t("種類フォルダの対応表への追加・変更（null で削除）", "Kind folder table changes (null removes)")),
        "missing_asset": {"enum": ["placeholder", "error"], "description": t("見つからない素材の扱い", "How to treat missing assets")},
        "lang": {"enum": ["ja", "en"]},
        "dictionaries": STRS,
        "verbs": {**STRS, "description": t("標準で使う動詞に足す拡張の動詞（GIVE、SHOW、PUSH、PULL、HIT、CALL、THINK、WAIT など）", "Extended verbs to enable in addition to the basic ones")},
        "slot_mode": {"enum": ["named", "standard"]},
        "intent_schema": obj({"entry": STR, "layers": {"type": "array", "items": obj({
            "file": STR, "when": {"$ref": "#/definitions/condition"}}, None, ["file"], extra=False)}}, extra=False),
        "event_defaults": EVENT_DEFAULTS,
        "features": {"type": "object", "properties": {k: FEATURE for k in FEATURE_KEYS},
                     "patternProperties": {"^x\\.": FEATURE}, "additionalProperties": False,
                     "description": t("モダン機能（許可、既定値、細かい設定）", "Modern features (allow, default, options)")},
        "seed": INT,
        "hint_topics": mapof(STR, t("ヒントの話題の表示名（話題 → 表示名）", "Display names of hint topics")),
        "transitions": obj({"named": mapof({"anyOf": [STR, {"type": "object", "properties": {"type": STR}}]},
                                           t("名前付きの切り替え演出（名前 → 演出と引数）", "Named transitions (name -> type and arguments)"))}, extra=False),
        "effects": {**STRS, "description": t("自作のフィルター・切り替え演出・画面効果の定義ファイル（*.effect.json）", "Custom filter / transition / effect definitions (*.effect.json)")},
        "save": obj({
            "protection": {"enum": ["hmac", "hmac_aes", "none"], "description": t("保護レベル：hmac（検知のみ、標準）、hmac_aes（検知＋暗号化）、none", "Protection: hmac (detect, default), hmac_aes (detect + encrypt), none")},
            "on_tamper": {"enum": ["reject", "warn"], "description": t("署名が一致しないとき：reject（読み込まない）、warn（警告して読み込む。暗号化時は不可）", "On signature mismatch: reject, or warn and load (not for encrypted saves)")},
            "text_format": {"type": "boolean", "description": t("テキスト形式（JSON）で書き出す。製品版でも読み書きを許可する", "Write text (JSON) saves; also allows them in release builds")},
            "dir": STR,
            "slots": {"type": "integer", "minimum": 1},
            "key_provider": {"type": "string", "description": t("embedded（標準）、per_user、または AdvKeyProvider を継承したスクリプトのパス", "embedded (default), per_user, or a script extending AdvKeyProvider")},
        }, t("セーブの設定（第8章）", "Save settings (chapter 8)"), extra=False),
    }),
    "definitions": COND_DEFS,
}

# ---------------------------------------------------------------- effect_def

PARAM = obj({
    "type": {"enum": ["float", "int", "bool", "color", "vec2", "enum", "texture", "string"]},
    "default": {}, "min": NUM, "max": NUM, "values": {"type": "array"},
    "label": STR, "description": STR,
}, required=["type"], extra=False)
EFFECT_DEF = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "adv80s/effect_def.schema.json",
    "title": t("adv80s 自作のフィルター・切り替え演出・画面効果", "adv80s custom filter / transition / effect"),
    **obj({
        "$schema": STR,
        "effect_version": INT,
        "id": STR,
        "kind": {"enum": ["filter", "transition", "effect"]},
        "name": {"type": "string", "description": t("表示名", "Display name")},
        "shader": {"type": "string", "description": t("シェーダーのファイルか素材ID", "Shader file or asset ID")},
        "handler": {"type": "string", "description": t("GDScriptのハンドラー（シェーダーだけで書きにくいとき）", "GDScript handler")},
        "params": mapof(PARAM, t("設定項目", "Parameters")),
        "duration": {"type": "number", "minimum": 0},
        "era": {"enum": ["common", "80s", "90s", "modern"]},
    }, required=["effect_version", "id", "kind"]),
}

SCHEMAS = {"scenario": SCENARIO, "template": TEMPLATE, "intent_schema": INTENT_SCHEMA,
           "manifest": MANIFEST, "project": PROJECT, "effect_def": EFFECT_DEF}

for LANG in ["ja", "en"]:
    d = os.path.join(OUT, LANG)
    os.makedirs(d, exist_ok=True)
    for name, s in SCHEMAS.items():
        with open(os.path.join(d, name + ".schema.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(resolve(copy.deepcopy(s)), f, ensure_ascii=False, indent=2)
            f.write("\n")
print("ok")
