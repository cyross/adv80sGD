@tool
class_name AdvPngAnim
extends RefCounted
## APNG（アニメーション PNG）と MNG の読み込み。中のコマを1枚ずつの PNG（JNG は JPEG）に組み直し、
## Godot の PNG・JPEG の読み込みで画像にしてから、重ね方に従って重ねる。
## MNG は MNG-LC・MNG-VLC の範囲（中の PNG・JNG、FRAM の表示時間、TERM の繰り返し、MHDR の時間の単位、DEFI の位置）。
## それ以外の機能（差分 DHDR、LOOP、BASI、CLON、PAST、MAGN など）は読まず、error に理由を入れる。

const PNG_SIG := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const MNG_SIG := [0x8A, 0x4D, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const MNG_UNSUPPORTED := ["DHDR", "PROM", "IPNG", "PPLT", "IJNG", "DROP", "DBYK", "ORDR", "LOOP", "ENDL",
	"BASI", "CLON", "PAST", "DISC", "BACK", "MOVE", "CLIP", "SHOW", "SAVE", "SEEK", "eXPI", "fPRI", "nEED", "MAGN"]

var error: String = ""
static var _crc_table: PackedInt64Array = []


static func load_frames(path: String) -> AdvImageFrames:
	var b := FileAccess.get_file_as_bytes(path)
	var d := AdvPngAnim.new()
	var r: AdvImageFrames = null
	if _starts(b, MNG_SIG):
		r = d.decode_mng(b)
	elif _starts(b, PNG_SIG):
		r = d.decode_apng(b)
	else:
		d.error = "not a PNG or MNG"
	if r == null:
		push_error("[adv80s] ASSET_UNSUPPORTED: 読めない画像です: %s（%s）" % [path, d.error])
	return r


static func _starts(b: PackedByteArray, sig: Array) -> bool:
	if b.size() < sig.size():
		return false
	for i in sig.size():
		if b[i] != sig[i]:
			return false
	return true


## チャンクの一覧 [{type, data}]（署名の後から）。
static func chunks(b: PackedByteArray, from: int = 8) -> Array:
	var out := []
	var pos := from
	while pos + 8 <= b.size():
		var n := _u32(b, pos)
		var t := b.slice(pos + 4, pos + 8).get_string_from_ascii()
		out.append({"type": t, "data": b.slice(pos + 8, pos + 8 + n)})
		pos += 12 + n
		if t == "IEND" and from == 8 and _starts(b, PNG_SIG):
			break
		if t == "MEND":
			break
	return out


static func _u32(b: PackedByteArray, p: int) -> int:
	return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]


static func _u16(b: PackedByteArray, p: int) -> int:
	return (b[p] << 8) | b[p + 1]


static func _be32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])


static func _crc(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in 256:
			var c := n
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if c & 1 else (c >> 1)
			_crc_table[n] = c
	var crc := 0xFFFFFFFF
	for x in data:
		crc = _crc_table[(crc ^ x) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


static func _chunk(t: String, data: PackedByteArray) -> PackedByteArray:
	var body := t.to_ascii_buffer()
	body.append_array(data)
	var out := _be32(data.size())
	out.append_array(body)
	out.append_array(_be32(_crc(body)))
	return out


## PNG を組み立てる。
static func _png(ihdr: PackedByteArray, extra: Array, idat: Array) -> PackedByteArray:
	var out := PackedByteArray(PNG_SIG)
	out.append_array(_chunk("IHDR", ihdr))
	for c in extra:
		out.append_array(_chunk(c["type"], c["data"]))
	for d in idat:
		out.append_array(_chunk("IDAT", d))
	out.append_array(_chunk("IEND", PackedByteArray()))
	return out


# ---------------------------------------------------------------- APNG

func decode_apng(b: PackedByteArray) -> AdvImageFrames:
	var list := chunks(b)
	var ihdr := PackedByteArray()
	var extra := []          # PLTE、tRNS など、IDAT より前の付属のチャンク
	var plays := 1
	var frames := []         # [{fc: PackedByteArray, data: [PackedByteArray]}]
	var cur = null
	var seen_idat := false
	for c in list:
		match String(c["type"]):
			"IHDR":
				ihdr = c["data"]
			"acTL":
				plays = _u32(c["data"], 4)
			"fcTL":
				cur = {"fc": c["data"], "data": []}
				frames.append(cur)
			"IDAT":
				seen_idat = true
				if cur != null:
					cur["data"].append(c["data"])
			"fdAT":
				if cur != null:
					cur["data"].append(c["data"].slice(4))
			"IEND":
				break
			_:
				if not seen_idat and c["type"] in ["PLTE", "tRNS", "gAMA", "cHRM", "sRGB", "iCCP", "sBIT"]:
					extra.append(c)
	if ihdr.is_empty():
		error = "no IHDR"
		return null
	var w := _u32(ihdr, 0)
	var h := _u32(ihdr, 4)
	var res := AdvImageFrames.new()
	res.size = Vector2i(w, h)
	res.loop_count = plays
	if frames.is_empty():
		# acTL のない普通の PNG
		var img := Image.new()
		if img.load_png_from_buffer(b) != OK:
			error = "bad PNG"
			return null
		res.frames.append(ImageTexture.create_from_image(img))
		res.delays.append(0.1)
		return res
	var canvas := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for f in frames:
		var fc: PackedByteArray = f["fc"]
		var fw := _u32(fc, 4)
		var fh := _u32(fc, 8)
		var fx := _u32(fc, 12)
		var fy := _u32(fc, 16)
		var dn := _u16(fc, 20)
		var dd := _u16(fc, 22)
		var dispose := fc[24]
		var blend := fc[25]
		if f["data"].is_empty():
			continue
		var fihdr := ihdr.duplicate()
		var wb := _be32(fw)
		var hb := _be32(fh)
		for i in 4:
			fihdr[i] = wb[i]
			fihdr[4 + i] = hb[i]
		var img := Image.new()
		if img.load_png_from_buffer(_png(fihdr, extra, f["data"])) != OK:
			error = "bad frame"
			return null
		img.convert(Image.FORMAT_RGBA8)
		var before := canvas.duplicate() if dispose == 2 else null
		var rect := Rect2i(0, 0, fw, fh)
		if blend == 1:
			canvas.blend_rect(img, rect, Vector2i(fx, fy))
		else:
			canvas.blit_rect(img, rect, Vector2i(fx, fy))
		res.frames.append(ImageTexture.create_from_image(canvas.duplicate()))
		var sec := float(dn) / float(dd if dd != 0 else 100)
		res.delays.append(sec if sec > 0.0 else 0.1)
		if dispose == 1:
			canvas.fill_rect(Rect2i(fx, fy, fw, fh), Color(0, 0, 0, 0))
		elif dispose == 2:
			canvas = before
	return res


# ---------------------------------------------------------------- MNG

func decode_mng(b: PackedByteArray) -> AdvImageFrames:
	var list := chunks(b)
	if list.is_empty() or list[0]["type"] != "MHDR":
		error = "no MHDR"
		return null
	var mh: PackedByteArray = list[0]["data"]
	var w := _u32(mh, 0)
	var h := _u32(mh, 4)
	var ticks := _u32(mh, 8)
	if ticks == 0:
		ticks = 1000
	var res := AdvImageFrames.new()
	res.size = Vector2i(w, h)
	res.loop_count = 1
	var canvas := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var delay := 0.1
	var pos := Vector2i.ZERO
	var global_plte = null
	var global_trns = null
	var i := 1
	while i < list.size():
		var c: Dictionary = list[i]
		var t := String(c["type"])
		var d: PackedByteArray = c["data"]
		if t in MNG_UNSUPPORTED:
			error = "unsupported MNG chunk %s" % t
			return null
		match t:
			"MEND":
				break
			"TERM":
				if d.size() >= 10 and d[0] == 3:
					var it := _u32(d, 6)
					res.loop_count = 0 if it >= 0x7FFFFFFF else it
				elif d.size() >= 1 and d[0] == 3:
					res.loop_count = 0
			"FRAM":
				var p := 1
				while p < d.size() and d[p] != 0:
					p += 1
				p += 1
				if d.size() >= p + 4:
					var change_delay := d[p]
					p += 4
					if change_delay != 0 and d.size() >= p + 4:
						delay = float(_u32(d, p)) / float(ticks)
			"DEFI":
				if d.size() >= 12:
					pos = Vector2i(_s32(d, 4), _s32(d, 8))
			"PLTE":
				global_plte = d
			"tRNS":
				global_trns = d
			"IHDR", "JHDR":
				# 中の画像（IEND まで）を取り出す
				var parts := [c]
				var j := i + 1
				while j < list.size() and list[j]["type"] != "IEND":
					parts.append(list[j])
					j += 1
				i = j
				var img := _embedded(parts, global_plte, global_trns)
				if img == null:
					return null
				img.convert(Image.FORMAT_RGBA8)
				canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
				res.frames.append(ImageTexture.create_from_image(canvas.duplicate()))
				res.delays.append(delay if delay > 0.0 else 0.1)
		i += 1
	if res.frames.is_empty():
		error = "no image"
		return null
	return res


static func _s32(b: PackedByteArray, p: int) -> int:
	var v := _u32(b, p)
	return v - 0x100000000 if v >= 0x80000000 else v


func _embedded(parts: Array, global_plte: Variant, global_trns: Variant) -> Image:
	var img := Image.new()
	if parts[0]["type"] == "JHDR":
		var jpg := PackedByteArray()
		for p in parts:
			if p["type"] == "JDAT":
				jpg.append_array(p["data"])
		if img.load_jpg_from_buffer(jpg) != OK:
			error = "bad JNG"
			return null
		return img
	var extra := []
	var idat := []
	for k in range(1, parts.size()):
		var p: Dictionary = parts[k]
		match String(p["type"]):
			"IDAT":
				idat.append(p["data"])
			"PLTE":
				extra.append({"type": "PLTE", "data": p["data"] if p["data"].size() > 0 else global_plte})
			"tRNS":
				extra.append({"type": "tRNS", "data": p["data"] if p["data"].size() > 0 else global_trns})
			"gAMA", "cHRM", "sRGB", "iCCP", "sBIT":
				extra.append(p)
	if img.load_png_from_buffer(_png(parts[0]["data"], extra, idat)) != OK:
		error = "bad PNG in MNG"
		return null
	return img
