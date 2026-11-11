#!/usr/bin/env python3
"""テスト用の MAG（MAKI02）画像を作る（開発用。アドオンでは使わない）。

tests/media/ に次を書き出す：
  mag16.mag  / mag16.png   … 16色、64x40（左端を4ドットずらした範囲。写し元の各ベクトルを使う）
  mag256.mag / mag256.png  … 256色、32x24
PNG は読み込んだときに同じになるはずの画像（比べるため）。
"""
import struct, zlib, os, sys

VECTORS = [(0,0),(-1,0),(-2,0),(-4,0),(0,-1),(-1,-1),(0,-2),(-1,-2),(-2,-2),(0,-4),(-1,-4),(-2,-4),(0,-8),(-1,-8),(-2,-8),(0,-16)]

def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + bytes(sum((list(rgb[y*w+x]) + [255] for x in range(w)), [])) for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

def encode(idx, w, h, pal, colors, x1=0, y1=0):
    """idx：単位の境目にそろえた幅 w の色番号の並び。"""
    per = 4 if colors == 16 else 2
    units = w // per
    data = []  # 行ごとの単位（2バイト）
    for y in range(h):
        row = []
        for u in range(units):
            px = idx[y*w + u*per : y*w + u*per + per]
            if colors == 16:
                row.append(bytes([(px[0] << 4) | px[1], (px[2] << 4) | px[3]]))
            else:
                row.append(bytes(px))
        data.append(row)
    prev = [0] * (units // 2)
    flag_a_bits, flag_b, pixels = [], bytearray(), bytearray()
    for y in range(h):
        nib = []
        for u in range(units):
            f = 0
            for k in range(1, 16):
                dx, dy = VECTORS[k]
                sx, sy = u + dx, y + dy
                if sx >= 0 and sy >= 0 and data[sy][sx] == data[y][u]:
                    f = k
                    break
            if f == 0:
                pixels += data[y][u]
            nib.append(f)
        cur = [(nib[2*i] << 4) | nib[2*i+1] for i in range(units // 2)]
        for i in range(units // 2):
            x = cur[i] ^ prev[i]
            flag_a_bits.append(1 if x else 0)
            if x:
                flag_b.append(x)
        prev = cur
    while len(flag_a_bits) % 8:
        flag_a_bits.append(0)
    flag_a = bytes(int("".join(map(str, flag_a_bits[i:i+8])), 2) for i in range(0, len(flag_a_bits), 8))
    palette = b"".join(bytes([g, r, b]) for (r, g, b) in pal)
    head_len = 32 + len(palette)
    fa = head_len
    fb = fa + len(flag_a)
    pxo = fb + len(flag_b)
    x2 = x1 + w - 1 if colors == 256 else x1 + w - 1
    header = struct.pack("<BBBBHHHHIIIII", 0, 0, 0, 0x80 if colors == 256 else 0, x1, y1, x1 + w - 1, y1 + h - 1,
                         fa, fb, len(flag_b), pxo, len(pixels))
    top = b"MAKI02  " + b"PC98" + b"adv80s test       " + b"test image" + b"\x1a"
    return top + header + palette + flag_a + bytes(flag_b) + bytes(pixels)

def main(out):
    os.makedirs(out, exist_ok=True)
    # 16色：縞、市松、斜めの線、ランダムな点を混ぜ、写し元のいろいろなベクトルが出るようにする
    import random
    random.seed(7)
    pal16 = [((i * 37) % 256, (i * 91) % 256, (i * 53 + 40) % 256) for i in range(16)]
    w, h = 64, 40
    idx = []
    for y in range(h):
        for x in range(w):
            if y < 8: c = (x // 4) % 16
            elif y < 16: c = ((x // 2 + y) % 2) * 9 + 3
            elif y < 24: c = 5 if x == y * 2 - 30 else 1
            elif y < 32: c = (x * y) % 16
            else: c = random.randrange(16)
            idx.append(c)
    with open(os.path.join(out, "mag16.mag"), "wb") as f:
        f.write(encode(idx, w, h, pal16, 16))
    png(os.path.join(out, "mag16.png"), w, h, [pal16[c] for c in idx])
    # 256色
    pal256 = [((i * 7) % 256, (i * 13) % 256, (255 - i) % 256) for i in range(256)]
    w, h = 32, 24
    idx = [((x // 2) * 16 + y * 3 + (7 if (x + y) % 5 == 0 else 0)) % 256 if y % 6 else (x * 8) % 256 for y in range(h) for x in range(w)]
    with open(os.path.join(out, "mag256.mag"), "wb") as f:
        f.write(encode(idx, w, h, pal256, 256))
    png(os.path.join(out, "mag256.png"), w, h, [pal256[c] for c in idx])

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "tests/media")
