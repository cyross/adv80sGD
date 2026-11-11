@tool
class_name AdvMag
extends RefCounted
## MAG 形式（MAKI02）の画像を読む。16色と256色に対応する。
## 読んだ画像はコマが1つの AdvImageFrames にする（GIF と同じく、静止画として使える）。
## 200ライン用の画像（画面モードの最下位ビット）も、そのままの縦横で読む（縦横比はテンプレートの表示で合わせる）。
##
## 形式のあらまし：
##   "MAKI02  " ＋ 機種コード(4) ＋ ユーザー名(18) ＋ コメント … 0x1A
##   ヘッダー(32バイト)：先頭(0) 機種 機種依存フラグ 画面モード 左X 上Y 右X 下Y(各2バイト)
##                      フラグAの位置 フラグBの位置 フラグBの大きさ ピクセルの位置 ピクセルの大きさ(各4バイト。位置はヘッダーの先頭から)
##   パレット：16色か256色ぶん、G R B の順に1バイトずつ
##   画素は2バイト（16色なら4ドット、256色なら2ドット）を1単位にし、1単位ごとにフラグの4ビットで
##   「新しい2バイトを読む（0）」か「決まった位置（左や上）から写す（1〜15）」かを決める。
##   フラグは行ごとに、フラグAの1ビットが1ならフラグBから1バイトを読み、前の行のフラグと XOR する。

const SIGNATURE := "MAKI02"
## フラグの値ごとの写し元（x は単位、y は行）
const VECTORS := [
	Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-4, 0),
	Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, -2), Vector2i(-1, -2),
	Vector2i(-2, -2), Vector2i(0, -4), Vector2i(-1, -4), Vector2i(-2, -4),
	Vector2i(0, -8), Vector2i(-1, -8), Vector2i(-2, -8), Vector2i(0, -16),
]

var error: String = ""
var colors: int = 16
var line200: bool = false


static func load_frames(path: String) -> AdvImageFrames:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("[adv80s] ASSET_UNSUPPORTED: MAG を読めません: %s" % path)
		return null
	var m := AdvMag.new()
	var img := m.decode(bytes)
	if img == null:
		push_error("[adv80s] ASSET_UNSUPPORTED: MAG を読めません: %s（%s）" % [path, m.error])
		return null
	var f := AdvImageFrames.new()
	f.frames.append(ImageTexture.create_from_image(img))
	f.delays = PackedFloat32Array([0.0])
	f.loop_count = 1
	f.size = img.get_size()
	return f


## MAG のバイト列を画像（RGBA8）にする。読めなければ null（error に理由）。
func decode(b: PackedByteArray) -> Image:
	if b.size() < 40 or b.slice(0, 6).get_string_from_ascii() != SIGNATURE:
		error = "MAKI02 の印がありません"
		return null
	# コメントの終わり（0x1A）の次がヘッダー
	var h := b.find(0x1A, 8)
	if h < 0 or h + 1 + 32 > b.size():
		error = "ヘッダーが見つかりません"
		return null
	h += 1
	var mode := b[h + 3]
	colors = 256 if (mode & 0x80) != 0 else 16
	line200 = (mode & 0x01) != 0
	var x1 := _u16(b, h + 4)
	var y1 := _u16(b, h + 6)
	var x2 := _u16(b, h + 8)
	var y2 := _u16(b, h + 10)
	var fa := h + _u32(b, h + 12)
	var fb := h + _u32(b, h + 16)
	var px := h + _u32(b, h + 24)
	var px_size := _u32(b, h + 28)
	# 横は単位の境目にそろえる（16色は8ドット、256色は4ドット）
	var align := 8 if colors == 16 else 4
	var left := x1 - (x1 % align)
	var right := x2 + (align - 1 - (x2 % align))
	var w := right - left + 1
	var hgt := y2 - y1 + 1
	if w <= 0 or hgt <= 0 or w > 8192 or hgt > 8192:
		error = "画像の大きさが正しくありません（%d x %d）" % [w, hgt]
		return null
	var pal_at := h + 32
	var pal_n := colors
	if pal_at + pal_n * 3 > b.size():
		error = "パレットが足りません"
		return null
	var pal := PackedByteArray()   # RGBA を並べる
	pal.resize(pal_n * 4)
	for i in pal_n:
		pal[i * 4] = b[pal_at + i * 3 + 1]       # R
		pal[i * 4 + 1] = b[pal_at + i * 3]       # G
		pal[i * 4 + 2] = b[pal_at + i * 3 + 2]   # B
		pal[i * 4 + 3] = 255
	var units := w / (4 if colors == 16 else 2)    # 1行の単位（2バイト）の数
	var flag_bytes := units / 2                    # 1行のフラグのバイト数（1バイトで2単位）
	var flags := PackedByteArray()
	flags.resize(flag_bytes)
	var data := PackedByteArray()                  # 単位ごとの2バイト（行 × 単位 × 2）
	data.resize(units * 2 * hgt)
	var bit := 0
	var px_end := mini(b.size(), px + px_size)
	for y in hgt:
		# この行のフラグ
		for i in flag_bytes:
			if fa + (bit >> 3) >= b.size():
				error = "フラグAが足りません"
				return null
			var on := (b[fa + (bit >> 3)] >> (7 - (bit & 7))) & 1
			bit += 1
			if on == 1:
				if fb >= b.size():
					error = "フラグBが足りません"
					return null
				flags[i] = flags[i] ^ b[fb]
				fb += 1
		# この行の画素
		var row := y * units * 2
		for u in units:
			var f := (flags[u >> 1] >> 4) if (u & 1) == 0 else (flags[u >> 1] & 0x0F)
			var at := row + u * 2
			if f == 0:
				if px + 1 >= px_end:
					error = "ピクセルが足りません"
					return null
				data[at] = b[px]
				data[at + 1] = b[px + 1]
				px += 2
			else:
				var v: Vector2i = VECTORS[f]
				var sx := u + v.x
				var sy := y + v.y
				if sx < 0 or sy < 0:
					error = "写し元が画像の外です（%d, %d）" % [sx, sy]
					return null
				var src := (sy * units + sx) * 2
				data[at] = data[src]
				data[at + 1] = data[src + 1]
	# 色を並べる
	var rgba := PackedByteArray()
	rgba.resize(w * hgt * 4)
	var o := 0
	for i in data.size():
		var v := data[i]
		if colors == 16:
			for idx in [v >> 4, v & 0x0F]:
				rgba[o] = pal[idx * 4]
				rgba[o + 1] = pal[idx * 4 + 1]
				rgba[o + 2] = pal[idx * 4 + 2]
				rgba[o + 3] = 255
				o += 4
		else:
			rgba[o] = pal[v * 4]
			rgba[o + 1] = pal[v * 4 + 1]
			rgba[o + 2] = pal[v * 4 + 2]
			rgba[o + 3] = 255
			o += 4
	var img := Image.create_from_data(w, hgt, false, Image.FORMAT_RGBA8, rgba)
	# 単位の境目にそろえた分を切り落とす
	if left != x1 or right != x2:
		img = img.get_region(Rect2i(x1 - left, 0, x2 - x1 + 1, hgt))
	return img


static func _u16(b: PackedByteArray, p: int) -> int:
	return b[p] | (b[p + 1] << 8)


static func _u32(b: PackedByteArray, p: int) -> int:
	return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)
