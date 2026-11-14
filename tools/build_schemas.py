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
               "checkpoint", "template.switch", "layout.set", "save.request",
               "sprite.show", "sprite.set", "sprite.hide", "sprite.anim", "sprite.effect", "sprite.clear",
               "cursor.set", "video.play", "video.stop",
               "scene.call", "scene.return", "ending.reach", "credits.roll",
               "game.new", "game.title", "game.continue", "game.quit", "endings.open", "chapters.open", "settings.open",
               "system.save", "system.load", "system.close", "settings.set", "fin.show", "opening.play", "extras.open", "notice.show"]
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
            obj({"call_scene": {"type": "string", "description": t("呼ぶサブシーンのID（kind: sub）。return で戻る", "Subscene to call (kind: sub). Comes back on return")},
                 "args": {"type": "object", "description": t("引数（名前 → 値。\"=\" で始まる文字列は呼び出し元で計算する式）。サブシーンの中では arg.名前 で読む",
                                                             "Arguments (name -> value; a string starting with \"=\" is evaluated by the caller). Read as arg.name inside the subscene")},
                 "into": {"type": "string", "description": t("戻り値を入れる変数", "Variable that receives the return value")}},
                t("サブシーンの呼び出し（6.9）", "Subscene call (6.9)"), ["call_scene"], extra=False),
            obj({"return": {"description": t("サブシーンから戻る。値（\"=\" で始まる文字列は式）は呼び出しの into に入る。値がなければ null",
                                             "Return from the subscene. The value (a string starting with \"=\" is an expression) goes into the caller's into; null for none")}},
                t("サブシーンから戻る（6.9）", "Return from a subscene (6.9)"), ["return"], extra=False),
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

# ---------------------------------------------------------------- 出力イベントの引数（エディタのフォームで使う）

def _p(desc_ja, desc_en, base=None):
    s = dict(base) if base else {}
    s["description"] = t(desc_ja, desc_en)
    return s

ANY = {}
TRANS = _p("切り替え演出（名前か {type, duration, …}）", "Transition (name or {type, duration, ...})")
DUR = _p("秒", "Seconds", NUM)
ID_OR_LIST = {"anyOf": [STR, {"type": "array"}]}


def EA(props, required=None):
    s = {"type": "object", "properties": props}
    if required:
        s["required"] = required
    return s


EVENT_ARGS = {
    "text.show": EA({"body": _p("本文", "Body", STR), "speaker": _p("話者のID", "Speaker ID", STR), "name": _p("出す名前", "Shown name", STR), "voice": _p("ボイスの素材ID", "Voice asset ID", STR)}, ["body"]),
    "text.append": EA({"body": _p("足す本文", "Text to append", STR)}, ["body"]),
    "text.clear": EA({}),
    "image.show": EA({"layer": _p("層（既定 bg）", "Layer (default bg)", STR), "id": _p("素材ID（配列で重ねる）", "Asset ID (array to layer)", ID_OR_LIST), "variant": STR, "transition": TRANS, "duration": DUR}, ["id"]),
    "image.hide": EA({"layer": STR, "transition": TRANS, "duration": DUR}),
    "effect.play": EA({"name": _p("効果（flash、shake、invert、tint、palette_cycle、scroll、zoom、raster など）", "Effect name", STR), "duration": DUR}, ["name"]),
    "sprite.show": EA({"id": STR, "image": STR, "variant": STR, "layer": _p("層（既定 char）", "Layer (default char)", STR), "x": NUM, "y": NUM, "anchor": ANY, "z": INT,
                       "scale": ANY, "rotation": NUM, "opacity": NUM, "flip": ANY, "blend": STR, "tint": ANY, "smooth": BOOL, "color_key": ANY, "anim": STR,
                       "transition": TRANS, "duration": DUR, "keep": BOOL, "mute": BOOL, "volume": NUM}, ["id", "image"]),
    "sprite.set": EA({"id": STR, "x": NUM, "y": NUM, "scale": ANY, "rotation": NUM, "opacity": NUM, "duration": DUR, "ease": STR,
                      "loop": _p("くりかえし（-1 で終わりなし）", "Repeat (-1 = forever)", INT), "yoyo": BOOL, "path": ANY}, ["id"]),
    "sprite.hide": EA({"id": _p("ID（配列も可）", "ID (array allowed)", ID_OR_LIST), "transition": TRANS, "duration": DUR}, ["id"]),
    "sprite.anim": EA({"id": STR, "anim": _p("アニメーション（null で止める）", "Animation (null stops)", ANY), "loop": BOOL}, ["id"]),
    "sprite.effect": EA({"id": STR, "name": _p("flash、shake、blink、mono、sepia、silhouette、mosaic、none、シェーダーのパス", "Effect name or shader path", STR), "duration": DUR, "params": ANY}, ["id", "name"]),
    "sprite.clear": EA({"layer": _p("層（省くとすべて）", "Layer (all if omitted)", STR)}),
    "cursor.set": EA({"kind": STR, "image": STR, "hotspot": ANY}),
    "video.play": EA({"id": STR, "area": {"enum": ["picture", "screen"]}, "fit": {"enum": ["contain", "cover", "stretch"]}, "loop": BOOL, "skippable": BOOL,
                      "volume": NUM, "bgm": {"enum": ["pause", "keep", "stop"]}, "filters": BOOL, "transition": TRANS}, ["id"]),
    "video.stop": EA({"transition": TRANS}),
    "bgm.play": EA({"id": _p("曲の素材ID", "BGM asset ID", STR), "loop": _p("くりかえす（既定 true）", "Loop (default true)", BOOL), "fade": DUR, "volume": NUM}, ["id"]),
    "bgm.stop": EA({"fade": DUR}),
    "se.play": EA({"id": STR, "volume": NUM}, ["id"]),
    "voice.play": EA({"id": STR, "speaker": STR}, ["id"]),
    "state.set": EA({"name": STR, "value": ANY, "op": STR}, ["name"]),
    "item.add": EA({"id": STR, "count": INT}, ["id"]),
    "item.remove": EA({"id": STR, "count": INT}, ["id"]),
    "scene.goto": EA({"scene": STR, "transition": TRANS}, ["scene"]),
    "scene.call": EA({"scene": _p("呼ぶサブシーン", "Subscene to call", STR), "args": {"type": "object"}, "into": _p("戻り値を入れる変数", "Variable for the return value", STR)}, ["scene"]),
    "scene.return": EA({"value": _p("戻り値", "Return value", ANY)}),
    "wait": EA({"seconds": DUR}, ["seconds"]),
    "group": EA({"events": _p("同時に実行するイベント", "Events run together", {"type": "array"})}, ["events"]),
    "choice.show": EA({"choices": {"type": "array"}, "prompt": STR}, ["choices"]),
    "input.request": EA({"slot": STR, "prompt": STR}, ["slot"]),
    "game.end": EA({"ending": STR}),
    "verbs.update": EA({"verbs": ANY, "mode": {"enum": ["replace", "add", "remove"]}}, ["verbs"]),
    "hotspots.update": EA({"objects": ANY, "mode": {"enum": ["replace", "add", "remove"]}}, ["objects"]),
    "input.mode": EA({"enable": {"type": "array", "items": {"enum": ["parser", "select", "click"]}}}, ["enable"]),
    "notebook.add": EA({"id": STR, "category": STR, "title": STR, "body": STR}, ["id", "title", "body"]),
    "objective.set": EA({"id": STR, "text": _p("目的（空で消す）", "Objective (empty clears)", STR)}, ["text"]),
    "hint.set": EA({"topic": STR, "hints": STRS}, ["topic", "hints"]),
    "flow.mark": EA({"node": STR}, ["node"]),
    "checkpoint": EA({"id": STR, "autosave": BOOL}),
    "layout.set": EA({"layout": STR, "transition": TRANS}, ["layout"]),
    "template.switch": EA({"template": STR, "transition": TRANS}, ["template"]),
    "save.request": EA({}),
    "credits.roll": EA({"items": {"type": "array"}, "lines": STRS, "text": STR, "speed": _p("1秒あたりの画素（既定 30）", "Pixels per second (default 30)", NUM),
                        "duration": DUR, "align": STR, "pal": INT, "size": NUM, "margin": NUM, "fill": ANY, "background": ANY, "skippable": BOOL, "bgm": ANY}),
    "ending.reach": EA({"id": STR}, ["id"]),
    "game.new": EA({"scene": STR}),
    "game.title": EA({}), "game.continue": EA({}), "game.quit": EA({}),
    "endings.open": EA({}), "chapters.open": EA({}), "settings.open": EA({}),
    "fin.show": {"$ref": "#/definitions/fin"},
    "opening.play": EA({"scene": STR}),
    "extras.open": EA({}),
    "system.save": EA({"slot": STR}, ["slot"]),
    "system.load": EA({"slot": STR}, ["slot"]),
    "system.close": EA({}),
    "settings.set": EA({"key": _p("text_speed、bgm_volume、features.<キー> など", "text_speed, bgm_volume, features.<key>, ...", STR), "value": ANY}, ["key"]),
    "notice.show": EA({"text": _p("お知らせの文（文字の書き方が使える）", "Notice text (markup allowed)", STR), "seconds": _p("出しておく秒数（既定は見た目の設定）", "Seconds shown (default: notice style)", NUM),
                         "icon": _p("絵の素材ID", "Icon image asset ID", STR), "log": _p("メッセージログにも残すか（既定は見た目の設定）", "Also add to the message log (default: notice style)", BOOL),
                         "position": _p("このお知らせだけの位置（既定は見た目の設定）", "Position of this notice only", {"enum": ["top_right", "top_left", "bottom_right", "bottom_left", "top", "bottom", "center"]})}, ["text"]),
}
EVENT_ARGS_DEFS = {"event_args": {"type": "object", "description": t("出力イベントごとの引数（エディタのフォームで使う）", "Arguments per output event (used by the editor form)"),
                                  "properties": EVENT_ARGS}}


ON_MAP = {"type": "object", "description": t("動詞ごとの反応。\"USE+door\" のように with の対象を指定できる",
                                             "Reaction per verb. \"USE+door\" narrows by the with target"),
          "patternProperties": {"^[A-Z][A-Z0-9_]*(\\+[^+]+)?$": {"$ref": "#/definitions/step"}},
          "additionalProperties": False}

EVENT_DEFAULTS = {"type": "object", "description": t("出力イベントの既定値（wait など）の書き換え", "Overrides for output event defaults (wait, etc.)"),
                  "additionalProperties": obj({"wait": WAIT, "log": BOOL}, extra=False)}

# ---------------------------------------------------------------- scenario

NOTICE_ENTRY = {"type": "object", "additionalProperties": False, "required": ["text"], "properties": {
    "text": {"type": "string", "description": t("文言", "Text")},
    "icon": {"type": "string", "description": t("絵の素材ID", "Icon image asset ID")},
    "log": {"type": "boolean", "description": t("メッセージログにも残すか", "Also add to the message log")},
    "position": {"enum": ["top_right", "top_left", "bottom_right", "bottom_left", "top", "bottom", "center"], "description": t("このお知らせだけの位置", "Position of this notice only")}}}

NOTICE_STYLE_DEFS = {"notice_style": obj({
    "position": {"enum": ["top_right", "top_left", "bottom_right", "bottom_left", "top", "bottom", "center"], "description": t("位置（既定 top_right）", "Position (default top_right)")},
    "fg": {"type": "integer", "description": t("文字の色（パレットの番号。既定 7）", "Text color (palette index, default 7)")},
    "bg": {"type": "integer", "description": t("地の色（既定 0）", "Background color (default 0)")},
    "border": {"type": "integer", "description": t("枠の色（既定 7。-1 で枠なし）", "Border color (default 7; -1 = none)")},
    "se": {"type": "string", "description": t("出すときの効果音（素材ID）", "Sound effect when shown (asset ID)")},
    "seconds": {"type": "number", "description": t("出しておく秒数（既定 2.5。0 なら時間では消えない）", "Seconds shown (default 2.5; 0 = until clicked)")},
    "click_close": {"type": "boolean", "description": t("クリックで消せるか（既定 true）", "Click to dismiss (default true)")},
    "max": {"type": "integer", "minimum": 0, "description": t("同時に出す数の上限（既定 5。超えたら古いものから消す。0 で上限なし）", "Max notices at once (default 5; oldest removed; 0 = no limit)")},
    "overflow": {"enum": ["instant", "fade"], "description": t("上限で消すときの消え方（instant：すぐ（既定）、fade：すっと）", "How notices over the limit disappear (instant (default) or fade)")},
    "log_labels": obj({"all": STR, "text": STR, "notice": STR}, t("ログの画面の切り替えの文言（既定「ひょうじ：すべて」など）", "Labels of the log screen filter"), extra=False),
    "log_filter": {"enum": ["all", "text", "notice"], "description": t("ログの画面を開いたときに出すもの（all：すべて、text：お知らせ以外、notice：お知らせだけ）", "What the log screen shows first")},
    "log_mark": {"type": "string", "description": t("メッセージログでお知らせの前に付ける印（既定「◆ 」）", "Mark before notices in the message log (default ◆)")},
    "log_color": {"type": "integer", "description": t("メッセージログでのお知らせの色（パレットの番号）", "Notice color in the message log (palette index)")},
    "margin": {"type": "number", "description": t("画面の端からの間（既定 12）", "Margin from the screen edge (default 12)")},
    "icon_size": {"type": "number", "description": t("絵の大きさ（既定 24）", "Icon size (default 24)")},
    "log": {"type": "boolean", "description": t("メッセージログにも残すか（既定 false）", "Also add notices to the message log (default false)")},
}, t("お知らせの見た目", "Notice appearance"), extra=False)}

FIN_DEFS = {"fin": obj({
    "show": BOOL, "text": STR, "pal": INT, "size": INT, "fill": INT, "image": STR, "text_y": NUM,
    "transition": {"description": t("出るとき・消えるときの切り替え演出", "Transition in and out")},
    "advance": {"type": "array", "items": {"anyOf": [{"type": "string", "pattern": "^(click|key|key:.+|trigger:.+)$"}, {"type": "number", "minimum": 0}]},
                "description": t("閉じる条件：click、key、key:キー名、秒数、trigger:名前（既定 [\"click\", \"key\"]）",
                                 "Close on: click, key, key:name, seconds, trigger:name (default [\"click\", \"key\"])")},
    "min_time": {"type": "number", "minimum": 0, "description": t("閉じられるようになるまでの秒数（既定 1）", "Seconds before it can be closed (default 1)")},
    "then": {"type": "string", "description": t("閉じたあと：title（既定）、new、quit、stay、またはシーンID", "After closing: title (default), new, quit, stay, or a scene ID")},
    "reset": {"type": "boolean", "description": t("then がシーンIDのとき、始める前の状態に戻してから移る", "Reset to the initial state before going to the then scene")},
    "items": {"type": "array", "description": t("複数の行と画像（スタッフロールの items と同じ）。書けば text の代わりに縦の真ん中に並べる", "Rows and images (same as credits items), centered instead of text")},
    "lines": {"type": "array", "description": t("複数の行（文字列の配列）", "Lines (array of strings)")},
    "margin": NUM, "align": STR, "line_gap": INT,
    "save_prompt": {"type": "boolean", "description": t("閉じたあと、クリアデータをセーブするか聞く（既定 false）", "Ask to save clear data after closing (default false)")},
    "save_prompt_title": STR, "save_prompt_text": STR,
    "save_resume": {"type": "string", "description": t("クリアデータをロードしたときに始めるシーン（既定は開始シーン）", "Scene to start when clear data is loaded (default: entry)")},
    "save_carry": {"anyOf": [{"enum": ["all", "none"]}, obj({
        "vars": {"anyOf": [{"enum": ["all", "none"]}, STRS]}, "items": {"anyOf": [{"enum": ["all", "none"]}, STRS]},
        "visited": BOOL, "talked": BOOL, "notebook": BOOL, "chosen": BOOL}, extra=False)],
        "description": t("クリアデータで引き継ぐもの：all（全部、既定）、none（何も引き継がない）、{vars, items, visited, talked, notebook, chosen}（書かなかったものは引き継がない）",
                         "What clear data carries over: all (default), none, or {vars, items, visited, talked, notebook, chosen} (unlisted parts are not carried)")},
}, t("「おわり」の画面（6.9）", "FIN screen (6.9)"), extra=False)}

ALIASES = mapof({"anyOf": [STR, obj({"params": STRS, "text": STR}, None, ["text"], extra=False)]},
                t("エイリアス（5.4）。文中の [alias=名前 引数…] を置き換える。値は文か {params, text}（text の中で {arg.引数名} を使う）",
                  "Aliases (5.4). [alias=name args...] in text is replaced. Value is text or {params, text} ({arg.param} inside text)"))

INPUTS = obj({
    "enabled": {"type": "array", "items": {"enum": ["select", "parser", "icon", "click", "verb_click", "verb_cursor", "context"]},
                "description": t("使うコマンド方式。select=コマンド選択、parser=コマンド入力、icon=アイコン、click=絵のクリック、verb_click=動詞を選んで対象をクリック、verb_cursor=カーソルの動詞を切り替えてクリック、context=対象に合わせて自動で決める",
                                 "Command methods. select, parser, icon, click, verb_click (pick a verb, then click a target), verb_cursor (cycle the cursor verb, then click), context (verb chosen from the target)")},
    "parser_profile": {"type": "string", "description": t("コマンド入力の読み方。ja=日本式（標準）、en=英語式、free=自由文、またはパーサーのスクリプトのパス",
                                                        "How typed commands are read. ja (Japanese, default), en (English), free (free sentences), or a parser script path")},
    "command_columns": {"type": "integer", "minimum": 1, "description": t("コマンド選択の列の数（既定 2）", "Columns of the command list (default 2)")},
    "click_verb": {"type": "string", "description": t("絵をクリックしたときの動詞（既定 EXAMINE）", "Verb used when the picture is clicked (default EXAMINE)")},
    "item_verb": {"type": "string", "description": t("持ち物をクリックして持ったときに使う動詞（既定 USE）", "Verb used when an inventory item is picked up by clicking (default USE)")},
    "context_alt_verb": {"type": "string", "description": t("右クリックで使う動詞（既定 LOOK）", "Verb used on right click (default LOOK)")},
    "context_verbs": mapof({"type": "string"}, t("context で、カーソルの種類から決める動詞（種類 → 動詞ID。空は click_verb）", "For context: verb per cursor kind (kind -> verb ID; empty = click_verb)")),
    "verb_cursors": mapof({"type": "string"}, t("動詞に合わせるカーソルの種類（動詞ID → 種類）", "Cursor kind per verb (verb ID -> kind)")),
}, extra=False)

scene_props = {
    "name": {"type": "string", "description": t("表示名", "Display name")},
    "kind": {"enum": ["normal", "title", "opening", "ending", "sub", "system"],
             "description": t("シーンの種類（6.9）。normal（標準）、title（タイトル）、opening（オープニング）、ending（エンディング）、sub（サブシーン）、system（システムシーン）",
                              "Scene kind (6.9): normal (default), title, opening, ending, sub (subscene), system (system scene)")},
    "params": mapof({"anyOf": [{"type": ["boolean", "integer", "number", "string", "null"]},
                               obj({"default": {}, "required": BOOL, "description": STR}, extra=False)]},
                    t("サブシーンの引数（名前 → 既定値か {default, required, description}）", "Subscene parameters (name -> default or {default, required, description})")),
    "menu": {"type": "array", "description": t("メニュー（title・system のシーン）。選択肢として出し、選んだ項目の手順が終わるとまた出す",
                                               "Menu (title / system scenes). Shown as a choice; shown again after the chosen item's steps"),
             "items": obj({"id": STR, "label": STR, "do": {"$ref": "#/definitions/step"},
                           "when": {"$ref": "#/definitions/condition"}, "once": BOOL}, None, ["label"])},
    "ending": {"type": "string", "description": t("エンディングID（kind: ending）。入ると見た記録を付ける", "Ending ID (kind: ending). Recorded as seen on entry")},
    "replay": {"enum": ["always", "once", "skippable"],
               "description": t("オープニング（kind: opening）の2回目から：always（毎回流す、既定）、once（1回目だけ流し、2回目からは飛ばす）、skippable（2回目からは Esc で飛ばせ、Ctrl で早送りできる）",
                                "Opening (kind: opening) from the second time: always (default), once (play only the first time), skippable (Esc skips, Ctrl fast-forwards)")},
    "next": {"type": "string", "description": t("オープニングを飛ばしたとき・終わったときに移るシーン（なければタイトルか開始シーン）", "Scene to go to when the opening is skipped or ends (title or entry when omitted)")},
    "bgm": {"anyOf": [{"type": ["string", "null"]}, obj({"id": STR, "fade": NUM, "loop": BOOL, "volume": NUM}, None, ["id"], extra=False)],
            "description": t("入ったときに鳴らす BGM（ID か {id, fade, loop, volume}。同じ曲ならそのまま。null で止める）", "BGM on entering (ID or {id, fade, loop, volume}; kept if the same; null stops)")},
    "bgm_fade": {"type": "number", "description": t("bgm: null で止めるときのフェードの秒数", "Fade seconds when bgm is null")},
    "transition": {"description": t("このシーンに入るときの切り替え演出", "Transition when entering this scene")},
    "variants": {"type": "array", "items": obj({"when": {"$ref": "#/definitions/condition"}, "image": {}, "bgm": {}, "bgm_fade": NUM,
                                                "menu": {"type": "array", "description": t("メニューの差し替え（menu と同じ形）", "Menu override (same as menu)")}}, extra=False),
                 "description": t("入ったときの背景と BGM の差し替え。when に合うものを順に重ねる（後ろほど優先）。タイトルを見たエンディングの数（sys.endings_seen など）で変えるのに使う",
                                  "Background / BGM overrides on entry; matching entries are applied in order (later wins). E.g. change the title by endings seen (sys.endings_seen)")},
    "fin": {"anyOf": [BOOL, {"$ref": "#/definitions/fin"}],
            "description": t("エンディング（kind: ending）を最後まで進めたときの「おわり」の画面（false で出さない）。プロジェクト設定の fin に重ねる",
                             "The FIN screen after an ending (kind: ending) finishes (false hides it). Merged over the project fin")},
    "image": {"anyOf": [STR, {"type": "array", "items": {"anyOf": [STR, {"type": "object", "required": ["id"], "additionalProperties": False,
                  "properties": {"id": STR, "variant": STR, "x": INT, "y": INT, "when": {"$ref": "#/definitions/condition"}}}]}}],
              "description": t("背景の画像ID（またはパス）。配列なら when に合う画像を順に重ねる", "Background image ID (or path). An array overlays the entries whose when holds")},
    "image_transition": {"description": t("配列の image が条件で変わったときの切り替え演出（既定 cut）", "Transition when an image array changes (default cut)")},
    "first": {"$ref": "#/definitions/step", "description": t("初めて入ったときの手順", "Steps on first visit")},
    "enter": {"$ref": "#/definitions/step", "description": t("入ったときの手順（first があれば2回目以降）", "Steps on entering (after the first visit if first exists)")},
    "objects": mapof(obj({
        "names": {**STRS, "description": t("コマンド入力で認識する呼び名", "Names recognized by the parser")},
        "label": {"type": "string", "description": t("コマンド選択に出す名前", "Label shown in command select")},
        "region": RECT,
        "sprite": {"type": "string", "description": t("結び付けるスプライトID（見えている範囲が調べられる場所になる）", "Sprite ID whose visible area becomes the hotspot")},
        "cursor": {"type": "string", "description": t("マウスを重ねたときのカーソルの種類", "Cursor kind on hover")},
        "click": {"type": "string", "description": t("クリックしたときに使う動詞（context と click の方式で使う）", "Verb used on click (context and click methods)")},
        "character": {"type": "string", "description": t("人物として扱うときの話者ID", "Speaker ID when this is a character")},
        "when": {"$ref": "#/definitions/condition", "description": t("表示する条件", "Visible when")},
        "on": ON_MAP,
    }), t("シーンの中の物や人物", "Objects and characters in the scene")),
    "exits": mapof({"anyOf": [{"type": "boolean"}, obj({
        "names": STRS, "label": STR, "when": {"$ref": "#/definitions/condition"}, "on": ON_MAP,
        "region": RECT, "sprite": STR, "cursor": STR, "click": STR})]},
        t("出口（行き先のシーンID → 設定）", "Exits (target scene ID -> settings)")),
    "sprites": {"type": "array", "description": t("シーンに置くスプライト（条件に合うものを出し、合わなくなったら消す）", "Sprites placed in the scene (shown while when holds)"),
                "items": {"type": "object", "required": ["id", "image"], "properties": {
                    "id": STR, "image": STR, "variant": STR, "layer": STR, "x": NUM, "y": NUM, "anchor": STR, "z": INT,
                    "scale": {"anyOf": [NUM, {"type": "array", "items": NUM}]}, "rotation": NUM, "opacity": NUM,
                    "flip": STR, "blend": {"enum": ["normal", "add", "multiply"]}, "tint": STR, "smooth": BOOL,
                    "color_key": {"anyOf": [STR, INT]}, "anim": {"type": ["string", "null"]},
                    "when": {"$ref": "#/definitions/condition"},
                    "show": {"description": t("出すときの切り替え演出", "Transition when shown")},
                    "hide": {"description": t("消すときの切り替え演出", "Transition when hidden")}},
                    "additionalProperties": False}},
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
        "aliases": ALIASES,
        "constants": mapof({"type": ["boolean", "integer", "number", "string"]}, t("定数（名前 → 値。書き換えられない）", "Constants (name -> value; read-only)")),
        "characters": mapof(obj({"name": STR, "names": STRS, "pal": INT, "voice": STR}), t("話者", "Speakers")),
        "items": mapof(obj({"name": STR, "names": STRS, "on": ON_MAP,
                            "icon": {"type": "string", "description": t("絵の素材ID（お知らせなどに出す）", "Image asset ID (shown in notices, etc.)")}}), t("アイテム", "Items")),
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
    "definitions": {**COND_DEFS, **STEP_DEFS, **FIN_DEFS, **EVENT_ARGS_DEFS},
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
            "screen_layers": {**STRS, "description": t("画面全体のスプライトの層。名前が back で始まる層は絵の窓より奥、ほかは窓より前（既定 [\"back\", \"front\"]）", "Screen-space sprite layers; names starting with back are behind the picture, others in front of windows")},
            "regions": mapof({"anyOf": [REGION, {"type": "null"}]}, t("画面の区割り", "Screen regions")),
            "named": mapof(obj({"regions": mapof({"anyOf": [REGION, {"type": "null"}]})}, extra=False), t("名前付きのレイアウト", "Named layouts")),
        }, extra=False),
        "inputs": INPUTS,
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
                   "cursors": mapof({"anyOf": [{"enum": ["arrow", "pointing_hand", "cross", "help", "move", "busy", "ibeam", "wait"]},
                                               obj({"image": STR, "hotspot": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2}}, extra=False)]},
                                    t("マウスカーソルの形（種類 → OS標準の形か {image, hotspot}）", "Mouse cursor shapes (kind -> OS shape or {image, hotspot})")),
                   "wait_mark": {"anyOf": [STR, obj({"text": STR, "image": STR, "anim": STR, "blink": BOOL, "color_key": {"anyOf": [STR, INT]},
                                                    "offset": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2}}, extra=False)],
                                 "description": t("クリック待ちの印（文字か {text|image, anim, blink, offset}。既定は「▼」の点滅）", "Click-wait marker (text or {text|image, anim, blink, offset}; default blinking ▼)")},
                   "page_mark": {"anyOf": [STR, obj({"text": STR, "image": STR, "anim": STR, "blink": BOOL, "color_key": {"anyOf": [STR, INT]},
                                                    "offset": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2}}, extra=False)],
                                 "description": t("ページ送り待ちの印（書き方は wait_mark と同じ。省略すると wait_mark）", "Page-turn marker (same format as wait_mark; defaults to wait_mark)")},
                   "window_padding": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2,
                                      "description": t("窓の内側の余白 [横, 縦]（既定 [8, 4]）", "Inner padding of windows [x, y] (default [8, 4])")}}),
        "notice": {"$ref": "#/definitions/notice_style"},
    }, required=["template_version", "id"]),
    "definitions": {
        **NOTICE_STYLE_DEFS,
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
        "type": {"enum": ["image", "bgm", "se", "voice", "font", "shader", "video"]},
        "file": {"type": "string", "description": t("既定のファイル（base からの相対パス）", "Default file (relative to base)")},
        "by_preset": mapof({"anyOf": [STR, obj({"file": STR, "variants": mapof(STR)}, extra=False)]},
                           t("機種別の差し替え（プリセットID、機種ID、グループID）", "Per-preset overrides (preset, machine or group ID)")),
        "variants": mapof(STR, t("差分（表情など）", "Variants (expressions, etc.)")),
        "pivot": {"type": "array", "items": NUM, "minItems": 2, "maxItems": 2},
        "region": RECT,
        "loop_start": {"type": "number", "minimum": 0, "description": t("ループの開始位置（秒）", "Loop start (seconds)")},
        "volume": NUM,
        "color_key": {"anyOf": [STR, INT], "description": t("透明にする色（\"#ff00ff\" かパレット番号）", "Color made transparent (\"#ff00ff\" or palette index)")},
        "grid": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2, "description": t("スプライトシートの切り方 [横の数, 縦の数]", "Sprite sheet grid [columns, rows]")},
        "anims": mapof(obj({"frames": {"type": "array", "items": {"anyOf": [INT, STR]}}, "fps": NUM,
                            "loop": {"anyOf": [BOOL, INT]}}, extra=False),
                       t("コマ送りアニメーション（名前 → frames、fps、loop）", "Frame animations (name -> frames, fps, loop)")),
        "hotspot": {"type": "array", "items": INT, "minItems": 2, "maxItems": 2, "description": t("カーソル画像の指す位置", "Cursor image hotspot")},
        "alt": {"type": "string", "description": t("外字（[gaiji=ID]）を文字で表すときの文字（メッセージログ、読み上げ）", "Text used for the image as gaiji ([gaiji=ID]) in the message log and speech")},
        "keep_colors": {"type": "boolean", "description": t("色をそのまま出す。有効なら、外字（[gaiji=ID]）として出すときに減色フィルターをかけない（既定 無効。走査線などはかかる）", "Keep the image's own colours: when shown as gaiji ([gaiji=ID]), skip the colour-reduction filter (default false; scanlines etc. still apply)")},
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
        "game_id": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$", "description": t("ゲームID。ほかのゲームと重ならない名前（セーブデータの見分けに使う）", "Game ID, unique per game (used to tell save data apart)")},
        "title": {"type": "string", "description": t("ゲームのタイトル（ウィンドウのタイトルにも使う）", "Game title (also used as the window title)")},
        "inputs": {**INPUTS, "description": t("コマンド方式。書いた項目だけ、テンプレートの inputs を上書きする", "Command methods; the keys written here override the template inputs")},
        "input_devices": {"type": "array", "items": {"enum": ["keyboard", "mouse", "gamepad", "touch"]}, "uniqueItems": True,
                          "description": t("使う入力機器（書かなければすべて）", "Input devices in use (all when omitted)")},
        "template": {"type": "string", "description": t("使う画面テンプレートのID", "Screen template ID")},
        "templates": {**STRS, "description": t("登録するテンプレート", "Registered templates")},
        "scenarios": {**STRS, "description": t("シナリオファイル（.ink.json は Ink のアダプタが読む）", "Scenario files (.ink.json files go to the Ink adapter)")},
        "ink": obj({"sync_variables": {"type": "boolean", "description": t("Ink の中で変わったグローバル変数を Core の状態に返す（既定 true）", "Write ink global variable changes back to Core state (default true)")}}, extra=False),
        "entry": {"type": "string", "description": t("開始シーン（空ならシナリオの start）", "Entry scene (empty = scenario start)")},
        "title_screen": {"type": "string", "description": t("タイトル画面（6.9）。空ならタイトルなしで始める、\"template\" ならテンプレートのタイトル画面、それ以外はタイトルのシーンID",
                                                              "Title screen (6.9): empty = start without a title, \"template\" = template title screen, otherwise a title scene ID")},
        "title_image": {"type": "string", "description": t("テンプレートのタイトル画面の背景の画像ID", "Background image ID of the template title screen")},
        "title_bgm": {"anyOf": [STR, obj({"id": STR, "fade": NUM, "loop": BOOL, "volume": NUM}, None, ["id"], extra=False)],
                      "description": t("テンプレートのタイトル画面の BGM", "BGM of the template title screen")},
        "title_bgm_fade": {"type": "number", "description": t("はじめからでタイトルの BGM を止めるフェードの秒数（既定 0.5）", "Fade seconds when the title BGM stops on new game (default 0.5)")},
        "title_transition": {"description": t("テンプレートのタイトル画面が出るとき・消えるときの切り替え演出", "Transition when the template title screen appears and leaves")},
        "opening": {"type": "string", "description": t("起動したときに最初に流すオープニングのシーンID（kind: opening）", "Opening scene played first at startup (kind: opening)")},
        "opening_replay": {"anyOf": [{"enum": ["seen", "always", "never", "any_ending", "all_endings"]},
                                     obj({"endings": STRS, "seen": BOOL, "when": {"$ref": "#/definitions/condition"}}, extra=False)],
                           "description": t("オープニングを見返せる条件：seen（見たことがあれば、既定）、always、never、any_ending、all_endings、{endings, seen, when}",
                                            "When the opening can be replayed: seen (default), always, never, any_ending, all_endings, {endings, seen, when}")},
        "notices": obj({
            "enabled": {"type": "boolean", "description": t("自動のお知らせを使うか（既定 true。false で全部止める）", "Use automatic notices (default true; false stops all)")},
            "item_add": {"anyOf": [STR, NOTICE_ENTRY], "description": t("持ち物を手に入れたとき（{name}、{count}）", "On item.add ({name}, {count})")},
            "item_remove": {"anyOf": [STR, NOTICE_ENTRY], "description": t("持ち物を手放したとき（{name}、{count}）", "On item.remove ({name}, {count})")},
            "notebook_add": {"anyOf": [STR, NOTICE_ENTRY], "description": t("手帳に書いたとき（{title}）", "On notebook.add ({title})")},
            "objective_set": {"anyOf": [STR, NOTICE_ENTRY], "description": t("目的が変わったとき（{text}。目的を消したときは出さない）", "On objective.set ({text}; not when cleared)")},
            "hint_set": {"anyOf": [STR, NOTICE_ENTRY], "description": t("ヒントが増えたとき（{topic}）", "On hint.set ({topic})")},
            "autosave": {"anyOf": [STR, NOTICE_ENTRY], "description": t("オートセーブしたとき", "On autosave")},
        }, t("自動のお知らせ。項目に文言を書いた場面だけ出す（書かなければ出さない）。シナリオからは notice.show でも出せる",
             "Automatic notices; shown only for entries with text. Scenarios can also use notice.show"), extra=False),
        "notice_style": {"$ref": "#/definitions/notice_style"},
        "debug": obj({
            "auto_reload": {"type": "boolean", "description": t("デバッグ実行中、ファイルを保存したら自動で読み直すか（既定 false）", "Reload automatically when files are saved during a debug run (default false)")},
            "reload_reenter": {"type": "boolean", "description": t("読み直したあと、いまのシーンに入り直すか（既定 false。Shift+F8 はいつも入り直す）", "Re-enter the current scene after reloading (default false; Shift+F8 always does)")},
            "notice_files": {"type": "integer", "minimum": 0, "description": t("読み直したときのお知らせに名前を出すファイルの数（既定 2。0 で名前を出さない）", "Files named in the reload notice (default 2; 0 = none)")},
            "watch_interval": {"type": "number", "minimum": 0.25, "description": t("ファイルを確かめる間隔（秒。既定 1）", "Seconds between file checks (default 1)")},
            "pre_set_notice": {"type": "boolean", "description": t("「設定を先に」で入った値をお知らせに出すか（既定 true）", "Show the values set first by \"set first\" in a notice (default true)")},
            "pre_set_seconds": {"type": "number", "minimum": 0, "description": t("「設定を先に」のお知らせを出しておく秒数（0 でクリックするまで。書かなければほかのお知らせと同じ）", "Seconds the \"set first\" notice stays (0 = until clicked; default = like other notices)")},
            "pre_set_position": {"enum": ["top_right", "top_left", "bottom_right", "bottom_left", "top", "bottom", "center"], "description": t("「設定を先に」のお知らせを出す位置（書かなければほかのお知らせと同じ）", "Position of the \"set first\" notice (default = like other notices)")},
            "run_group_order": {"type": "array", "items": STR, "description": t("「実行：」の一覧での組の並び（書いていない組はそのあとに名前の順）。シナリオエディタの「組…」の ↑↓ で書ける", "Order of preset groups in the run list (unlisted groups follow by name)")},
            "notices": obj({
                "run_from": {"type": "boolean", "description": t("「シーンから実行」（既定 true）", "\"Run from scene\" (default true)")},
                "pre_set": {"type": "boolean", "description": t("「先に設定」（既定 true。pre_set_notice も見る）", "\"Set first\" (default true; pre_set_notice also applies)")},
                "reload": {"type": "boolean", "description": t("「読み直しました」（既定 true）", "\"Reloaded\" (default true)")},
                "editor": {"type": "boolean", "description": t("「エディタで開きます」「エディタにつながっていません」（既定 true）", "Open-in-editor notices (default true)")},
                "preset": {"type": "boolean", "description": t("「ひな形にしました」など（既定 true）", "Preset notices (default true)")},
                "auto_reload": {"type": "boolean", "description": t("「保存したら読み直す：入／切」（既定 true）", "Auto-reload on/off notice (default true)")},
            }, t("デバッグのお知らせを種類ごとに出すか（false にした種類は出さない）", "Show each kind of debug notice (false = hide)"), extra=False),
            "notice_style": obj({
                "fg": {"type": "integer", "description": t("文字の色（パレットの番号）", "Text color (palette index)")},
                "bg": {"type": "integer", "description": t("地の色", "Background color")},
                "border": {"type": "integer", "description": t("枠の色（-1 で枠なし）", "Border color (-1 = none)")},
                "se": {"type": "string", "description": t("出すときの効果音（素材ID。\"\" で鳴らさない）", "Sound effect (asset ID; \"\" = none)")},
                "icon": {"type": "string", "description": t("頭に付ける絵（素材ID）", "Icon (asset ID)")},
                "position": {"enum": ["top_right", "top_left", "bottom_right", "bottom_left", "top", "bottom", "center"], "description": t("出す位置", "Position")},
                "seconds": {"type": "number", "minimum": 0, "description": t("出しておく秒数（0 でクリックするまで）", "Seconds shown (0 = until clicked)")},
            }, t("デバッグのお知らせ（シーンから実行・先に設定・読み直し・エディタで開く・ひな形にしました など）の見た目。書いたものだけ、ほかのお知らせの見た目から変える。「先に設定」は pre_set_style・pre_set_position・pre_set_seconds が先", "Look of debug notices (only the keys written override the notice style; pre_set_* win for the \"set first\" notice)"), extra=False),
            "pre_set_style": obj({
                "fg": {"type": "integer", "description": t("文字の色（パレットの番号）", "Text color (palette index)")},
                "bg": {"type": "integer", "description": t("地の色", "Background color")},
                "border": {"type": "integer", "description": t("枠の色（-1 で枠なし）", "Border color (-1 = none)")},
                "se": {"type": "string", "description": t("出すときの効果音（素材ID。\"\" で鳴らさない）", "Sound effect (asset ID; \"\" = none)")},
                "icon": {"type": "string", "description": t("頭に付ける絵（素材ID）", "Icon (asset ID)")},
            }, t("「設定を先に」のお知らせの見た目（書いたものだけ、ほかのお知らせの見た目から変える）", "Look of the \"set first\" notice (only the keys written override the notice style)"), extra=False),
            "pre_set_log": {"type": "boolean", "description": t("「設定を先に」で入った値をメッセージログに出すか（既定 true）", "Write the values set first by \"set first\" to the message log (default true)")},
            "run_presets": mapof(obj({
                "vars": mapof({}, t("フラグと変数（名前 → 値）", "Flags and variables (name -> value)")),
                "items": mapof({"type": "integer"}, t("持ち物（ID → 個数。0 なら持たない）", "Items (ID -> count; 0 = not held)")),
            }, None, extra=False), t("「このシーンから実行」のひな形（名前 → {vars, items}）。シナリオエディタの「ひな形…」で書ける", "Presets for \"run from this scene\" (name -> {vars, items}); editable with the scenario editor's Presets... button")),
        }, t("デバッグ実行の設定（配布するゲームでは使わない）", "Debug run settings (unused in release builds)"), extra=False),
        "title_labels": mapof(STR, t("テンプレートのタイトル画面のメニューの文言（項目 → 文）", "Labels of the template title menu (item -> text)")),
        "extras": obj({
            "show": {"type": "boolean", "description": t("出すか（既定 true）", "Show it (default true)")},
            "when": {"$ref": "#/definitions/condition"},
            "title": STR, "gallery_label": STR, "music_label": STR, "endings_label": STR, "opening_label": STR,
            "menu": {"type": "array", "items": {"enum": ["gallery", "music", "endings", "opening"]},
                     "description": t("並べる項目と順番（既定 [\"gallery\", \"music\"]）。endings はエンディング一覧、opening はオープニングを見返す",
                                      "Items and their order (default [\"gallery\", \"music\"]); endings = ending list, opening = replay the opening")},
            "thumbnails": {"type": "boolean", "description": t("ギャラリーに見本の画像を出すか（既定 true）", "Show thumbnails in the gallery (default true)")},
            "music_desc": {"type": "boolean", "description": t("音楽で曲の説明（desc）を出すか（既定 true）", "Show track descriptions (desc) in the music room (default true)")},
            "bonus": {"type": "boolean", "description": t("特典（bonus: true の項目）を使うか（既定 true）", "Use bonus entries (default true)")},
            "notify": {"type": "boolean", "description": t("特典が開いたとき、お知らせを出すか（既定 true）", "Show a notice when a bonus entry unlocks (default true)")},
            "notify_text": {"type": "string", "description": t("お知らせの文言（既定「おまけが ふえました」）", "Notice text")},
            "notify_icon": {"type": "string", "description": t("お知らせの絵（素材ID）", "Notice icon (asset ID)")},
            "title_count": {"type": "boolean", "description": t("テンプレートのタイトル画面の「おまけ」に開いた数を出すか（既定 false）", "Show the opened count on the template title's extras item (default false)")},
            "music_mode": {"enum": ["one", "next", "all"],
                           "description": t("音楽の鳴らし方の初め（one：1曲くりかえし、next：つづけて、all：ぜんぶくりかえし）",
                                            "Initial music room play mode (one: repeat one, next: play on, all: repeat all)")},
            "gallery": {"type": "array", "items": obj({"id": STR, "label": STR, "hint": STR, "when": {"$ref": "#/definitions/condition"},
                                                       "images": {"type": "array", "items": STR, "description": t("めくれる画像の並び（どれかを見ていれば開く）", "Images to page through (unlocks when any was seen)")},
                                                       "thumb": {"type": "string", "description": t("見本の画像（既定は見た最初の画像）", "Thumbnail image (default: the first seen image)")},
                                                       "bonus": {"type": "boolean", "description": t("特典の項目（数えない。when が既定 sys.gallery_all か sys.music_all、開くまで出さない）", "Bonus entry (not counted; `when` defaults to sys.gallery_all / sys.music_all; hidden until unlocked)")},
                                                       "hidden": {"type": "boolean", "description": t("特典を開くまで出さないか（既定 true。false なら「？？？」で出す）", "Hide the bonus entry until unlocked (default true; false shows ???)")},},
                                                      None, None, extra=False, anyOf=[{"required": ["id"]}, {"required": ["images"]}])},
            "music": {"type": "array", "items": obj({"id": STR, "label": STR, "hint": STR, "when": {"$ref": "#/definitions/condition"},
                                                     "desc": {"type": "string", "description": t("曲の説明（鳴らしている間に出す。文字の書き方が使える）", "Description shown while playing (text markup allowed)")},
                                                     "bonus": {"type": "boolean", "description": t("特典の項目（数えない。when が既定 sys.gallery_all か sys.music_all、開くまで出さない）", "Bonus entry (not counted; `when` defaults to sys.gallery_all / sys.music_all; hidden until unlocked)")},
                                                     "hidden": {"type": "boolean", "description": t("特典を開くまで出さないか（既定 true。false なら「？？？」で出す）", "Hide the bonus entry until unlocked (default true; false shows ???)")},}, None, ["id"], extra=False)},
        }, t("おまけ（ギャラリーと音楽）。when（既定 sys.all_endings）に合えばタイトルから開ける。項目は when がなければ、一度でも出した画像・鳴らした曲なら開く",
             "Extras (gallery and music). Opens from the title when `when` (default sys.all_endings) holds; entries unlock when seen/heard unless `when` is given"), extra=False),
        "title_variants": {"type": "array", "items": obj({"when": {"$ref": "#/definitions/condition"}, "image": STR, "bgm": {}, "transition": {},
                                                      "menu": {"type": "array", "items": STR}, "labels": mapof(STR)}, extra=False),
                           "description": t("テンプレートのタイトル画面の背景・BGM・演出の差し替え（when に合うものを順に重ねる。sys.endings_seen、sys.ending_<ID>、sys.all_endings が使える）",
                                            "Template title overrides (matching entries applied in order; sys.endings_seen, sys.ending_<ID>, sys.all_endings available)")},
        "fin": {"anyOf": [BOOL, {"$ref": "#/definitions/fin"}], "description": t("「おわり」の画面の既定（false で出さない）", "Defaults of the FIN screen (false hides it)")},
        "opening_hint": {"type": "string", "description": t("2回目からのオープニングに出す案内（既定「Esc：とばす　Ctrl：はやおくり」）", "Hint shown on a skippable opening")},
        "title_menu": {"type": "array", "items": {"enum": ["new", "continue", "chapters", "endings", "opening", "extras", "settings", "quit"]},
                       "description": t("テンプレートのタイトル画面のメニュー（並べる順）", "Menu of the template title screen (in order)")},
        "endings": {"type": "array", "description": t("エンディングの一覧（並べる順）。label は見たあとに出す名前、hint は見る前に出すヒント",
                                                      "Endings (in display order). label is shown once seen, hint before"),
                    "items": obj({"id": STR, "label": STR, "hint": STR}, None, ["id"], extra=False)},
        "system_scenes": obj({k: {"type": "string"} for k in ["save", "load", "settings", "log"]},
                             t("システム画面の差し替え（画面 → .tscn のパスかシステムシーンのID）", "System screen replacements (screen -> .tscn path or system scene ID)"), extra=False),
        "subscene_max_depth": {"type": "integer", "minimum": 0, "description": t("サブシーンの呼び出しの深さの上限（既定 10。0 で無制限）", "Subscene call depth limit (default 10; 0 = unlimited)")},
        "aliases": ALIASES,
        "variables": mapof(obj({"type": {"enum": ["bool", "int", "float", "string"]}, "default": {}}, extra=False),
                           t("全シナリオで共通の変数（名前 → {type, default}）", "Variables shared by all scenarios (name -> {type, default})")),
        "constants": mapof({"type": ["boolean", "integer", "number", "string"]}, t("全シナリオで共通の定数（名前 → 値。書き換えられない）", "Constants shared by all scenarios (name -> value; read-only)")),
        "asset_roots": {**STRS, "description": t("プロジェクトの素材フォルダ", "Project asset folders")},
        "asset_folders": mapof({"type": ["string", "null"], "enum": ["image", "bgm", "se", "voice", "font", "shader", "video", None]},
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
    "definitions": {**COND_DEFS, **FIN_DEFS, **NOTICE_STYLE_DEFS},
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
