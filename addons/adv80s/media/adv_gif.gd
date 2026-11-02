@tool
class_name AdvGif
extends RefCounted
## GIF（87a・89a）の読み込み。外部のライブラリを使わずに GDScript で読む。
## 対応：グローバル・ローカルのパレット、透明色、コマの表示時間、繰り返し回数（NETSCAPE2.0）、
## コマの重ね方（disposal：残す・背景に戻す・前に戻す）、インターレース。
## 背景に戻すときは透明にする（ブラウザと同じ扱い）。

var error: String = ""


## ファイルを読んで AdvImageFrames を返す。失敗したら null（error に理由）。
static func load_frames(path: String) -> AdvImageFrames:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("[adv80s] GIF を読めません: %s" % path)
		return null
	var g := AdvGif.new()
	var r := g.decode(bytes)
	if r == null:
		push_error("[adv80s] GIF を読めません: %s（%s）" % [path, g.error])
	return r


func decode(b: PackedByteArray) -> AdvImageFrames:
	if b.size() < 13 or b.slice(0, 3).get_string_from_ascii() != "GIF":
		error = "not a GIF"
		return null
	var w := b[6] | (b[7] << 8)
	var h := b[8] | (b[9] << 8)
	var packed := b[10]
	var pos := 13
	var gct := PackedByteArray()
	if packed & 0x80:
		var n := 3 * (1 << ((packed & 7) + 1))
		gct = b.slice(pos, pos + n)
		pos += n
	var canvas := PackedByteArray()
	canvas.resize(w * h * 4)
	canvas.fill(0)
	var res := AdvImageFrames.new()
	res.size = Vector2i(w, h)
	res.loop_count = -1   # NETSCAPE がなければ1回（下で 1 にする）
	var delay := 0.1
	var transparent := -1
	var disposal := 0
	while pos < b.size():
		var tag := b[pos]
		pos += 1
		if tag == 0x3B:
			break
		elif tag == 0x21:
			var label := b[pos]
			pos += 1
			if label == 0xF9 and b[pos] >= 4:
				var p := b[pos + 1]
				disposal = (p >> 2) & 7
				var d := b[pos + 2] | (b[pos + 3] << 8)
				delay = 0.1 if d <= 1 else d / 100.0
				transparent = b[pos + 4] if p & 1 else -1
			elif label == 0xFF and b[pos] == 11 and b.slice(pos + 1, pos + 12).get_string_from_ascii() == "NETSCAPE2.0":
				var q := pos + 12
				if b[q] >= 3 and b[q + 1] == 1:
					res.loop_count = b[q + 2] | (b[q + 3] << 8)
			pos = _skip_blocks(b, pos)
		elif tag == 0x2C:
			if pos + 9 > b.size():
				break
			var fx := b[pos] | (b[pos + 1] << 8)
			var fy := b[pos + 2] | (b[pos + 3] << 8)
			var fw := b[pos + 4] | (b[pos + 5] << 8)
			var fh := b[pos + 6] | (b[pos + 7] << 8)
			var fp := b[pos + 8]
			pos += 9
			var pal := gct
			if fp & 0x80:
				var n := 3 * (1 << ((fp & 7) + 1))
				pal = b.slice(pos, pos + n)
				pos += n
			var min_size := b[pos]
			pos += 1
			var data := PackedByteArray()
			while pos < b.size() and b[pos] != 0:
				var n := b[pos]
				data.append_array(b.slice(pos + 1, pos + 1 + n))
				pos += n + 1
			pos += 1
			var idx := _lzw(data, min_size, fw * fh)
			if fp & 0x40:
				idx = _deinterlace(idx, fw, fh)
			var saved := canvas.duplicate() if disposal == 3 else PackedByteArray()
			_draw(canvas, w, h, idx, pal, fx, fy, fw, fh, transparent)
			var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, canvas)
			res.frames.append(ImageTexture.create_from_image(img))
			res.delays.append(delay)
			if disposal == 2:
				_clear(canvas, w, h, fx, fy, fw, fh)
			elif disposal == 3:
				canvas = saved
			delay = 0.1
			transparent = -1
			disposal = 0
		else:
			error = "unknown block 0x%02x" % tag
			break
	if res.frames.is_empty():
		error = error if error != "" else "no image"
		return null
	if res.loop_count < 0:
		res.loop_count = 1
	return res


static func _skip_blocks(b: PackedByteArray, pos: int) -> int:
	while pos < b.size() and b[pos] != 0:
		pos += b[pos] + 1
	return pos + 1


static func _draw(canvas: PackedByteArray, w: int, h: int, idx: PackedByteArray, pal: PackedByteArray,
		fx: int, fy: int, fw: int, fh: int, transparent: int) -> void:
	var colors := pal.size() / 3
	for y in fh:
		var cy := fy + y
		if cy >= h:
			break
		var row := y * fw
		for x in fw:
			var cx := fx + x
			if cx >= w:
				break
			var c := idx[row + x]
			if c == transparent or c >= colors:
				continue
			var o := (cy * w + cx) * 4
			canvas[o] = pal[c * 3]
			canvas[o + 1] = pal[c * 3 + 1]
			canvas[o + 2] = pal[c * 3 + 2]
			canvas[o + 3] = 255


static func _clear(canvas: PackedByteArray, w: int, h: int, fx: int, fy: int, fw: int, fh: int) -> void:
	for y in range(fy, mini(fy + fh, h)):
		for x in range(fx, mini(fx + fw, w)):
			var o := (y * w + x) * 4
			canvas[o] = 0
			canvas[o + 1] = 0
			canvas[o + 2] = 0
			canvas[o + 3] = 0


## インターレースの行の順（0, 8, 16…、4, 12…、2, 6…、1, 3…）を元に戻す。
static func _deinterlace(idx: PackedByteArray, fw: int, fh: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(idx.size())
	var src := 0
	for pass_ in [[0, 8], [4, 8], [2, 4], [1, 2]]:
		var y: int = pass_[0]
		while y < fh:
			for x in fw:
				out[y * fw + x] = idx[src * fw + x] if src * fw + x < idx.size() else 0
			src += 1
			y += pass_[1]
	return out


## LZW の展開。足りないデータは 0 で埋める。
static func _lzw(data: PackedByteArray, min_size: int, npix: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(npix)
	var clear := 1 << min_size
	var eoi := clear + 1
	var size := min_size + 1
	var next := eoi + 1
	var prefix := PackedInt32Array()
	prefix.resize(4096)
	var suffix := PackedByteArray()
	suffix.resize(4096)
	var firstc := PackedByteArray()
	firstc.resize(4096)
	for i in clear:
		prefix[i] = -1
		suffix[i] = i
		firstc[i] = i
	var stack := PackedByteArray()
	stack.resize(4097)
	var op := 0
	var prev := -1
	var buf := 0
	var bits := 0
	var pos := 0
	var n := data.size()
	while op < npix:
		while bits < size:
			if pos >= n:
				return out
			buf |= data[pos] << bits
			pos += 1
			bits += 8
		var code := buf & ((1 << size) - 1)
		buf >>= size
		bits -= size
		if code == clear:
			size = min_size + 1
			next = eoi + 1
			prev = -1
			continue
		if code == eoi:
			break
		var sp := 0
		var c := code
		var extra := -1
		if code >= next:
			if prev == -1 or code != next:
				return out   # 壊れている
			extra = firstc[prev]
			c = prev
		while c >= 0 and sp < 4096:
			stack[sp] = suffix[c]
			sp += 1
			c = prefix[c] if c >= clear + 2 or prefix[c] >= 0 else -1
		var first := stack[sp - 1]
		while sp > 0 and op < npix:
			sp -= 1
			out[op] = stack[sp]
			op += 1
		if extra >= 0 and op < npix:
			out[op] = extra
			op += 1
		if prev != -1 and next < 4096:
			prefix[next] = prev
			suffix[next] = first if extra < 0 else extra
			firstc[next] = firstc[prev]
			next += 1
			if next == (1 << size) and size < 12:
				size += 1
		prev = code
	return out
