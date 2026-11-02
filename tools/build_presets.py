# 開発用の補助スクリプト（フレームワークの実行には不要）。
# 画面プリセット（7.1）の presets.json を書き出す。直すときはこのファイルを直して再生成する。
# 使い方: python3 tools/build_presets.py addons/adv80s/presets/presets.json
import json, sys

DIG8 = ["#000000", "#0000ff", "#ff0000", "#ff00ff", "#00ff00", "#00ffff", "#ffff00", "#ffffff"]
PC98_16 = DIG8 + ["#777777", "#000077", "#770000", "#770077", "#007700", "#007777", "#777700", "#aaaaaa"]
MONO2 = ["#000000", "#ffffff"]
MX16 = ["#000000", "#000000", "#21c842", "#5edc78", "#5455ed", "#7d76fc", "#d4524d", "#42ebf5",
        "#fc5554", "#ff7978", "#d4c154", "#e6ce80", "#21b03b", "#c95bba", "#cccccc", "#ffffff"]
GB4 = ["#0f380f", "#306230", "#8bac0f", "#9bbc0f"]


def m(w, h, colors, **kw):
    d = {"size": [w, h], "colors": colors}
    d.update(kw)
    return d


GROUPS = {
    "pc80": {"name": "80年代パソコン", "ruby": "paren",
             "filters": [{"type": "scanline", "intensity": 0.35}, {"type": "reduce"}, {"type": "crt", "curvature": 0.0, "vignette": 0.15}]},
    "pc90": {"name": "90年代パソコン", "ruby": "above",
             "filters": [{"type": "crt", "curvature": 0.01, "vignette": 0.08}]},
    "console": {"name": "家庭用ゲーム機", "ruby": "above",
                "filters": [{"type": "reduce"}, {"type": "bleed", "amount": 0.5}, {"type": "scanline", "intensity": 0.25}]},
    "handheld": {"name": "携帯機", "ruby": "above",
                 "filters": [{"type": "reduce"}, {"type": "lcd", "grid": 0.25}]},
    "modern": {"name": "現代", "ruby": "above", "filters": []},
}

SAME_M2P = {
    "256x212": m(256, 212, "19268色", bits=[5, 5, 5]),
    "256x212_12499": m(256, 212, "12499色＋16色", bits=[5, 5, 5]),
    "256x212_16": m(256, 212, "512色中16色", bits=[3, 3, 3]),
    "256x212_256": m(256, 212, "256色", bits=[3, 3, 2]),
    "512x212": m(512, 212, "512色中16色", bits=[3, 3, 3]),
}

MACHINES = {
    "88": ("pc80", 0.83, "640x200", {
        "640x200": m(640, 200, "512色中8色", palette=DIG8, bits=[3, 3, 3], line_double=True),
        "640x400": m(640, 400, "512色中2色", palette=MONO2)}),
    "98": ("pc80", 0.83, "640x400", {
        "640x400": m(640, 400, "4096色中16色", palette=PC98_16, bits=[4, 4, 4]),
        "640x400_8": m(640, 400, "デジタル8色", palette=DIG8),
        "640x200": m(640, 200, "8色", palette=DIG8, line_double=True)}),
    "SX1": ("pc80", 0.83, "640x200", {
        "640x200": m(640, 200, "8色", palette=DIG8, line_double=True),
        "320x200": m(320, 200, "8色", palette=DIG8, pixel_aspect=1.67)}),
    "SX1T": ("pc80", 0.83, "640x400", {
        "640x400": m(640, 400, "8色", palette=DIG8),
        "640x200": m(640, 200, "8色", palette=DIG8, line_double=True)}),
    "SX1TZ": ("pc80", 0.83, "320x200", {
        "320x200": m(320, 200, "4096色", bits=[4, 4, 4], pixel_aspect=1.67),
        "640x400": m(640, 400, "8色", palette=DIG8),
        "640x200": m(640, 200, "8色", palette=DIG8, line_double=True)}),
    "F7": ("pc80", 0.83, "640x200", {
        "640x200": m(640, 200, "8色", palette=DIG8, line_double=True)}),
    "F77A": ("pc80", 0.83, "320x200", {
        "320x200": m(320, 200, "4096色", bits=[4, 4, 4], pixel_aspect=1.67),
        "320x200_262144": m(320, 200, "26万色", bits=[6, 6, 6], pixel_aspect=1.67),
        "640x400": m(640, 400, "8色", palette=DIG8),
        "640x200": m(640, 200, "8色", palette=DIG8, line_double=True)}),
    "MX": ("pc80", 1.0, "256x192", {
        "256x192": m(256, 192, "固定16色", palette=MX16)}),
    "MX2": ("pc80", 1.10, "256x212", {
        "256x212": m(256, 212, "512色中16色", bits=[3, 3, 3]),
        "256x212_256": m(256, 212, "256色", bits=[3, 3, 2]),
        "512x212": m(512, 212, "512色中16色", bits=[3, 3, 3], pixel_aspect=0.55)}),
    "M2P": ("pc80", 1.10, "256x212", SAME_M2P),
    "X68K": ("pc90", 0.89, "768x512", {
        "768x512": m(768, 512, "65536色中16色", bits=[5, 5, 5]),
        "512x512": m(512, 512, "65536色", bits=[5, 5, 5], pixel_aspect=1.33),
        "256x256": m(256, 256, "65536色", bits=[5, 5, 5], pixel_aspect=1.33)}),
    "FTNS": ("pc90", 1.0, "640x480", {
        "640x480": m(640, 480, "1677万色中256色"),
        "640x480_16": m(640, 480, "4096色中16色", bits=[4, 4, 4]),
        "320x240": m(320, 240, "32768色", bits=[5, 5, 5])}),
    "MTR": ("pc90", 1.10, "256x212", SAME_M2P),
    "VGA": ("pc90", 1.0, "640x480", {
        "640x480": m(640, 480, "262144色中16色", bits=[6, 6, 6]),
        "320x200": m(320, 200, "256色", bits=[6, 6, 6], pixel_aspect=0.83)}),
    "WIN": ("pc90", 1.0, "640x480", {
        "640x480": m(640, 480, "1677万色中256色"),
        "640x480_65536": m(640, 480, "65536色", bits=[5, 6, 5]),
        "800x600": m(800, 600, "1677万色中256色"),
        "800x600_65536": m(800, 600, "65536色", bits=[5, 6, 5]),
        "1024x768": m(1024, 768, "1677万色中256色"),
        "1024x768_65536": m(1024, 768, "65536色", bits=[5, 6, 5]),
        "1280x1024": m(1280, 1024, "1677万色中256色"),
        "1280x1024_65536": m(1280, 1024, "65536色", bits=[5, 6, 5])}),
    "FC": ("console", 1.143, "256x240", {
        "256x240": m(256, 240, "約52色中25色", bits=[2, 2, 2], visible=[0, 8, 256, 224])}),
    "PCE": ("console", 1.143, "256x224", {
        "256x224": m(256, 224, "512色中482色", bits=[3, 3, 3]),
        "336x224": m(336, 224, "512色中482色", bits=[3, 3, 3], pixel_aspect=0.87),
        "512x224": m(512, 224, "512色中482色", bits=[3, 3, 3], pixel_aspect=0.57)}),
    "SFC": ("console", 1.143, "256x224", {
        "256x224": m(256, 224, "32768色中256色", bits=[5, 5, 5]),
        "512x448": m(512, 448, "32768色中256色（インターレース）", bits=[5, 5, 5])}),
    "PS1": ("console", 1.0, "320x240", {
        "320x240": m(320, 240, "1677万色"),
        "256x224": m(256, 224, "1677万色", pixel_aspect=1.143),
        "640x480": m(640, 480, "1677万色（インターレース）")}),
    "PS2": ("console", 1.0, "640x480", {
        "640x480": m(640, 480, "RGBA各8ビット"),
        "1920x1080": m(1920, 1080, "RGBA各8ビット（1080i）"),
        "1280x1024": m(1280, 1024, "RGBA各8ビット（VESA）")}),
    "GB": ("handheld", 1.0, "160x144", {
        "160x144": m(160, 144, "4階調", palette=GB4)}),
    "GBC": ("handheld", 1.0, "160x144", {
        "160x144": m(160, 144, "32768色中56色", bits=[5, 5, 5])}),
    "GBA": ("handheld", 1.0, "240x160", {
        "240x160": m(240, 160, "32768色", bits=[5, 5, 5])}),
    "HD": ("modern", 1.0, "1280x720", {"1280x720": m(1280, 720, "フルカラー")}),
    "FHD": ("modern", 1.0, "1920x1080", {"1920x1080": m(1920, 1080, "フルカラー")}),
    "4K": ("modern", 1.0, "3840x2160", {"3840x2160": m(3840, 2160, "フルカラー")}),
}

out = {"presets_version": 1, "groups": GROUPS, "machines": {}}
for mid, (group, aspect, default, modes) in MACHINES.items():
    mm = {}
    for name, d in modes.items():
        d = dict(d)
        d.setdefault("pixel_aspect", aspect)
        mm[name] = d
    out["machines"][mid] = {"group": group, "default_mode": default, "modes": mm}

with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(len(MACHINES), "machines")
