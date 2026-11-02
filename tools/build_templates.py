#!/usr/bin/env python3
"""機種ごとの画面テンプレート（addons/adv80s/templates/<ID>/）を作る開発用の道具。

プリセット（addons/adv80s/presets/presets.json）の代表モードの解像度から、画面の区割り・フォント・色・窓の枠を決めて
template.json を書き出す。家庭用ゲーム機・携帯機・現代の機種は、窓の枠の画像（9分割）も作り、
テンプレートの素材フォルダ assets/ に置く（ui/frame_<ID>.png）。素材フォルダには手書き用の manifest.json も置く
（manifest.auto.json はエディタかコマンドラインで作る）。

  python3 tools/build_templates.py addons/adv80s

必要なもの：Python 3、Pillow
すでにある pc98_classic と pc88_classic は書き換えない（素材フォルダと manifest.json だけ足す）。
"""
import json
import os
import re
import sys

from PIL import Image, ImageDraw

# 8色（デジタル8色の並び：黒、青、赤、紫、緑、水色、黄、白）。文章の色などの番号はこの並びで指定する
DIGITAL8 = ["#000000", "#0000ff", "#ff0000", "#ff00ff", "#00ff00", "#00ffff", "#ffff00", "#ffffff"]

FONT_16 = [{"asset": "dot16", "size": 16}, {"asset": "pixelmplus12", "size": 12, "line_height": 16}]
FONT_12 = [{"asset": "pixelmplus12", "size": 12, "line_height": 14}]
FONT_10 = [{"asset": "pixelmplus10", "size": 10, "line_height": 12}]
FONT_10_TIGHT = [{"asset": "pixelmplus10", "size": 10, "line_height": 11}]


def modern_font(scale):
    return [{"asset": "tekuplus", "size": 12 * scale, "line_height": 16 * scale}]


# ID、表示名、プリセット、元にするテンプレート、区割りの種類、フォント、文章の行数、色、窓、余白の倍率
#   区割り：pc（絵の下に文章とコマンド、入力欄あり）、console（絵の右にコマンド、下に文章。入力欄なし）
#   色：None ならプリセットのパレット（番号は 8色の並び）。リストなら独自の色（palette.source = colors）
#   窓：box（パレットの色の枠線）か、9分割画像の作り方の名前
TEMPLATES = [
    # 80年代パソコン
    ("sx1_classic", "SX1 クラシック", "SX1", "pc88_classic", None, None, None, None, "box", 1),
    ("sx1t_classic", "SX1T クラシック", "SX1T", "pc98_classic", "pc", FONT_16, 5, None, "box", 1),
    ("sx1tz_classic", "SX1TZ クラシック", "SX1TZ", "pc98_classic", "pc", FONT_10, 4, DIGITAL8, "box", 1),
    ("f7_classic", "F7 クラシック", "F7", "pc88_classic", None, None, None, None, "box", 1),
    ("f77a_classic", "F77A クラシック", "F77A", "pc98_classic", "pc", FONT_10, 4, DIGITAL8, "box", 1),
    ("mx_classic", "MX クラシック", "MX", "pc98_classic", "console", FONT_10_TIGHT, 3, "MX", "box", 1),
    ("mx2_classic", "MX2 クラシック", "MX2", "pc98_classic", "console", FONT_10, 3, DIGITAL8, "box", 1),
    ("m2p_classic", "M2P クラシック", "M2P", "pc98_classic", "console", FONT_10, 3, DIGITAL8, "box", 1),
    # 90年代パソコン
    ("x68k_classic", "X68K クラシック", "X68K", "pc98_classic", "pc", FONT_16, 6, DIGITAL8, "box", 1),
    ("ftns_classic", "FTNS クラシック", "FTNS", "pc98_classic", "pc", FONT_16, 5, DIGITAL8, "box", 1),
    ("mtr_classic", "MTR クラシック", "MTR", "pc98_classic", "console", FONT_10, 3, DIGITAL8, "box", 1),
    ("vga_classic", "VGA クラシック", "VGA", "pc98_classic", "pc", FONT_16, 5, DIGITAL8, "box", 1),
    ("win_classic", "WIN クラシック", "WIN", "pc98_classic", "pc", FONT_16, 5, DIGITAL8, "bevel", 1),
    # 家庭用ゲーム機
    ("fc_classic", "FC クラシック", "FC", "pc98_classic", "console", FONT_10, 3, DIGITAL8, "fc", 1),
    ("pce_classic", "PCE クラシック", "PCE", "pc98_classic", "console", FONT_12, 3, DIGITAL8, "pce", 1),
    ("sfc_classic", "SFC クラシック", "SFC", "pc98_classic", "console", FONT_12, 3, DIGITAL8, "sfc", 1),
    ("ps1_classic", "PS1 クラシック", "PS1", "pc98_classic", "console", FONT_12, 4, DIGITAL8, "ps1", 1),
    ("ps2_classic", "PS2 クラシック", "PS2", "pc98_classic", "console", FONT_16, 5, DIGITAL8, "ps2", 2),
    # 携帯機
    ("gb_classic", "GB クラシック", "GB", "pc98_classic", "console", FONT_10_TIGHT, 3, "GB", "gb", 1),
    ("gbc_classic", "GBC クラシック", "GBC", "pc98_classic", "console", FONT_10_TIGHT, 3, DIGITAL8, "gbc", 1),
    ("gba_classic", "GBA クラシック", "GBA", "pc98_classic", "console", FONT_10, 3, DIGITAL8, "gba", 1),
    # 現代
    ("hd_modern", "HD モダン", "HD", "pc98_classic", "pc", modern_font(2), 4, DIGITAL8, "modern", 2),
    ("fhd_modern", "FHD モダン", "FHD", "pc98_classic", "pc", modern_font(3), 4, DIGITAL8, "modern", 3),
    ("4k_modern", "4K モダン", "4K", "pc98_classic", "pc", modern_font(6), 4, DIGITAL8, "modern", 6),
]

# パレットを持つプリセットで、文章などの色に使う番号（text, name, highlight, fill, border, dim）
COLOR_INDEX = {
    "digital": {"text": 7, "name": 6, "highlight": 1, "fill": 0, "border": 7},
    "MX": {"text": 15, "name": 11, "highlight": 4, "fill": 1, "border": 15},
    "GB": {"text": 0, "name": 1, "highlight": 2, "fill": 3, "border": 0},
    "light": {"text": 0, "name": 1, "highlight": 5, "fill": 7, "border": 0},   # 明るい窓（GBC）
}

# 明るい窓を使うもの（文字を暗い色にする）
LIGHT_WINDOWS = {"gbc"}


def load_presets(addon):
    with open(os.path.join(addon, "presets", "presets.json"), encoding="utf-8") as f:
        return json.load(f)["machines"]


def preset_mode(machines, mid):
    m = machines[mid]
    mode = m["modes"][m["default_mode"]]
    w, h = mode["size"]
    vis = mode.get("visible", [0, 0, w, h])
    return w, h, vis


def layout(kind, w, h, vis, font, lines, scale):
    """区割りを決める。座標はテンプレートの元の解像度のピクセル。"""
    line = font[0].get("line_height", font[0]["size"])
    char = font[0]["size"]
    vx, vy, vw, vh = vis
    m = max(4, round(w / 80))           # 外側の余白
    gap = max(2, round(w / 160))        # 窓どうしの間
    top = vy + max(4, round(h / 100))
    bottom = vy + vh - max(4, round(h / 100))
    pad_y = 4 * scale
    msg_h = lines * line + pad_y * 2
    regions = {}
    if kind == "pc":
        input_h = line + 12 * scale
        cmd_w = max(char * 9 + 16 * scale, round(w * 0.29))
        bottom_h = msg_h + gap + input_h
        pic_h = bottom - top - gap - bottom_h
        regions["picture"] = {"rect": [vx + m, top, vw - 2 * m, pic_h]}
        y0 = top + pic_h + gap
        msg_w = vw - 2 * m - cmd_w - gap
        regions["message"] = {"rect": [vx + m, y0, msg_w, msg_h], "window": "main"}
        regions["input"] = {"rect": [vx + m, y0 + msg_h + gap, msg_w, input_h]}
        regions["commands"] = {"rect": [vx + m + msg_w + gap, y0, cmd_w, bottom - y0], "window": "main"}
    else:
        cmd_w = max(char * 5 + 16 * scale, round(vw * 0.3))
        pic_h = bottom - top - gap - msg_h
        pic_w = vw - 2 * m - cmd_w - gap
        regions["picture"] = {"rect": [vx + m, top, pic_w, pic_h]}
        regions["commands"] = {"rect": [vx + m + pic_w + gap, top, cmd_w, pic_h], "window": "main"}
        regions["message"] = {"rect": [vx + m, top + pic_h + gap, vw - 2 * m, msg_h], "window": "main"}
        regions["input"] = {"visible": False}
    named = {"fullscreen_cg": {"regions": {
        "picture": {"rect": [vx, vy, vw, vh]}, "message": {"visible": False},
        "input": {"visible": False}, "commands": {"visible": False}}}}
    return {"regions": regions, "named": named}


# ---------------------------------------------------------------- 窓の枠（9分割画像）

def frame(style, scale):
    """(画像, 余白 [左, 上, 右, 下], 文章の内側の余白 [x, y]) を返す。"""
    s = scale
    if style == "fc":
        n = 16
        im = Image.new("RGBA", (n, n), (0, 0, 0, 255))
        d = ImageDraw.Draw(im)
        d.rectangle([1, 1, n - 2, n - 2], outline=(252, 252, 252, 255), width=2)
        return im, [4, 4, 4, 4], [8, 6]
    if style == "pce":
        n = 16
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([0, 0, n - 1, n - 1], radius=4, fill=(16, 24, 96, 255), outline=(200, 200, 216, 255), width=1)
        d.rounded_rectangle([2, 2, n - 3, n - 3], radius=3, outline=(96, 104, 160, 255), width=1)
        return im, [5, 5, 5, 5], [8, 6]
    if style == "sfc":
        n = 32
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        for y in range(n):
            c = int(152 - 104 * y / (n - 1))
            ImageDraw.Draw(im).line([(0, y), (n - 1, y)], fill=(0, 0, c, 255))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, n - 1, n - 1], outline=(96, 96, 112, 255), width=1)
        d.rectangle([1, 1, n - 2, n - 2], outline=(240, 240, 240, 255), width=1)
        return im, [4, 4, 4, 4], [8, 6]
    if style == "ps1":
        n = 32
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        mask = Image.new("L", (n, n), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, n - 1, n - 1], radius=6, fill=255)
        grad = Image.new("RGBA", (n, n))
        for y in range(n):
            c = int(96 - 64 * y / (n - 1))
            ImageDraw.Draw(grad).line([(0, y), (n - 1, y)], fill=(0, 0, c, 216))
        im.paste(grad, (0, 0), mask)
        ImageDraw.Draw(im).rounded_rectangle([0, 0, n - 1, n - 1], radius=6, outline=(208, 208, 224, 255), width=1)
        return im, [8, 8, 8, 8], [10, 7]
    if style == "ps2":
        n = 16 * s
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([0, 0, n - 1, n - 1], radius=4 * s, fill=(8, 12, 24, 200), outline=(200, 210, 230, 255), width=s)
        return im, [6 * s, 6 * s, 6 * s, 6 * s], [12, 8]
    if style == "gb":
        n = 16
        im = Image.new("RGBA", (n, n), (155, 188, 15, 255))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, n - 1, n - 1], outline=(15, 56, 15, 255), width=1)
        d.rectangle([2, 2, n - 3, n - 3], outline=(48, 98, 48, 255), width=1)
        return im, [4, 4, 4, 4], [6, 3]
    if style == "gbc":
        n = 16
        im = Image.new("RGBA", (n, n), (248, 248, 248, 255))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, n - 1, n - 1], outline=(24, 40, 120, 255), width=2)
        return im, [4, 4, 4, 4], [6, 3]
    if style == "gba":
        n = 16
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([0, 0, n - 1, n - 1], radius=3, fill=(24, 48, 120, 224), outline=(232, 240, 248, 255), width=1)
        return im, [4, 4, 4, 4], [7, 4]
    if style == "bevel":
        n = 16
        im = Image.new("RGBA", (n, n), (0, 0, 128, 255))
        d = ImageDraw.Draw(im)
        d.line([(0, 0), (n - 1, 0)], fill=(255, 255, 255, 255))
        d.line([(0, 0), (0, n - 1)], fill=(255, 255, 255, 255))
        d.line([(1, 1), (n - 2, 1)], fill=(192, 192, 192, 255))
        d.line([(1, 1), (1, n - 2)], fill=(192, 192, 192, 255))
        d.line([(0, n - 1), (n - 1, n - 1)], fill=(0, 0, 0, 255))
        d.line([(n - 1, 0), (n - 1, n - 1)], fill=(0, 0, 0, 255))
        d.line([(1, n - 2), (n - 2, n - 2)], fill=(128, 128, 128, 255))
        d.line([(n - 2, 1), (n - 2, n - 2)], fill=(128, 128, 128, 255))
        return im, [3, 3, 3, 3], [8, 4]
    if style == "modern":
        r = 8 * s
        n = r * 4
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([0, 0, n - 1, n - 1], radius=r, fill=(10, 14, 28, 208), outline=(220, 228, 240, 230), width=max(1, s // 2))
        return im, [r, r, r, r], [12 * s, 6 * s]
    raise ValueError(style)


# ---------------------------------------------------------------- 書き出し

# 標準のマウスカーソル（アドオンの素材 ui/cursor_*.png。tools/build_cursors.py で作る）。
# マウスが当たり前になった 90年代のパソコンと、家庭用・携帯機・現代の機種のテンプレートで使う
CURSORS = {
    "default": {"image": "cursor_arrow", "hotspot": [0, 0]},
    "look": {"image": "cursor_look", "hotspot": [5, 6]},
    "talk": {"image": "cursor_talk", "hotspot": [6, 5]},
    "take": {"image": "cursor_hand", "hotspot": [5, 0]},
    "use": {"image": "cursor_hand", "hotspot": [5, 0]},
    "exit": {"image": "cursor_exit", "hotspot": [13, 8]},
    "wait": {"image": "cursor_wait", "hotspot": [6, 7]},
    "next": {"image": "cursor_next", "hotspot": [5, 7]},
    "text": "ibeam",
}
CURSOR_TEMPLATES = {"x68k_classic", "ftns_classic", "mtr_classic", "vga_classic", "win_classic",
                    "fc_classic", "pce_classic", "sfc_classic", "ps1_classic", "ps2_classic",
                    "gb_classic", "gbc_classic", "gba_classic", "hd_modern", "fhd_modern", "4k_modern"}


def compact(obj):
    """JSON を、数の配列だけ1行にまとめて整形する。"""
    text = json.dumps(obj, ensure_ascii=False, indent=2)
    return re.sub(r"\[\s*([-\d.,\s]+?)\s*\]", lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]", text) + "\n"


def write_assets(tdir, tid, style, scale, manifest_note):
    adir = os.path.join(tdir, "assets")
    os.makedirs(adir, exist_ok=True)
    skin = None
    if style != "box":
        im, margins, pad = frame(style, scale)
        os.makedirs(os.path.join(adir, "ui"), exist_ok=True)
        name = "frame_%s" % tid
        im.save(os.path.join(adir, "ui", name + ".png"))
        skin = ({"type": "nine_patch", "image": name, "margins": margins}, pad)
    mpath = os.path.join(adir, "manifest.json")
    if not os.path.exists(mpath):
        with open(mpath, "w", encoding="utf-8") as f:
            f.write(compact({"manifest_version": 1, "assets": {}}))
    return skin


def main():
    addon = sys.argv[1] if len(sys.argv) > 1 else "addons/adv80s"
    machines = load_presets(addon)
    tpl_root = os.path.join(addon, "templates")
    # すでにあるテンプレートにも素材フォルダを用意する
    for tid in ("pc98_classic", "pc88_classic"):
        write_assets(os.path.join(tpl_root, tid), tid, "box", 1, "")
    for tid, name, preset, base, kind, font, lines, colors, style, scale in TEMPLATES:
        tdir = os.path.join(tpl_root, tid)
        os.makedirs(tdir, exist_ok=True)
        d = {"template_version": 1, "id": tid, "name": name, "extends": base,
             "display": {"preset": preset}}
        if kind is not None:
            w, h, vis = preset_mode(machines, preset)
            d["display"]["scale"] = "integer"
            if colors == "MX":
                idx = COLOR_INDEX["MX"]
            elif colors == "GB":
                idx = COLOR_INDEX["GB"]
            else:
                idx = COLOR_INDEX["light" if style in LIGHT_WINDOWS else "digital"]
                if isinstance(colors, list):
                    d["palette"] = {"source": "colors", "colors": colors}
            d["fonts"] = {"main": font}
            d["layout"] = layout(kind, w, h, vis, font, lines, scale)
            d["layout"]["background"] = idx["fill"]
            if kind == "console":
                d["inputs"] = {"enabled": ["select"], "parser_profile": "ja"}
                # コマンドの窓が狭ければ1列にする（5文字の動詞が2列並ぶ幅がないとき）
                cmd_w = d["layout"]["regions"]["commands"]["rect"][2]
                if cmd_w < font[0]["size"] * 10 + 24:
                    d["inputs"]["command_columns"] = 1
            d["text"] = {"color": idx["text"], "name_color": idx["name"]}
        skin = write_assets(tdir, tid, style, scale, "")
        if kind is not None:
            ui = {"highlight": idx["highlight"]}
            if skin is not None:
                ui["window_skin"] = skin[0]
                ui["window_padding"] = skin[1]
            else:
                ui["window_skin"] = {"type": "box", "border": 1, "pal": idx["border"], "fill": idx["fill"]}
            if tid in CURSOR_TEMPLATES:
                ui["cursors"] = CURSORS
            d["ui"] = ui
        elif skin is not None:
            d["ui"] = {"window_skin": skin[0], "window_padding": skin[1]}
        d["assets"] = {"root": "assets/", "manifest": "manifest.json"}
        with open(os.path.join(tdir, "template.json"), "w", encoding="utf-8") as f:
            f.write(compact(d))
        print("wrote", tid)


if __name__ == "__main__":
    main()
