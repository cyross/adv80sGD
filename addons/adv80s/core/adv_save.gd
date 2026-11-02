class_name AdvSave
extends RefCounted
## セーブデータの読み書き（第8章）。
## 正式な形式はバイナリ（HMAC-SHA256 の署名、任意で AES-CBC の暗号化）、デバッグ用にテキスト（JSON）も扱う。
##
## バイナリの形：
##   [ヘッダー] "ADV80SAV"（8） / 形式バージョン（2） / 保護レベル（1） / key_id の長さ（1） / key_id / IV（16、暗号化時のみ） / 本体の長さ（4）
##   [本体]     var_to_bytes のデータ（暗号化時は AES-256-CBC、PKCS#7 の詰め物）
##   [署名]     ヘッダーと本体に対する HMAC-SHA256（32、保護レベルが none 以外）

const MAGIC := "ADV80SAV"
const FORMAT_VERSION := 1
const LEVELS := {"none": 0, "hmac": 1, "hmac_aes": 2}

## 読み込みの結果のエラーコード
const OK_CODE := ""
const ERR_FORMAT := "FORMAT"           ## 形式が違う・壊れている
const ERR_TAMPERED := "TAMPERED"       ## 署名が一致しない（改ざんの疑い）
const ERR_KEY_MISMATCH := "KEY_MISMATCH" ## 違う鍵で保存されたセーブ
const ERR_NO_KEY := "NO_KEY"           ## 鍵を用意できない
const ERR_TEXT_DENIED := "TEXT_DENIED" ## テキスト形式の読み込みが許可されていない
const ERR_IO := "IO"


## データをバイナリにする。protection は "none"、"hmac"、"hmac_aes"。
static func encode(data: Dictionary, protection: String, kp: AdvKeyProvider) -> PackedByteArray:
	var level: int = LEVELS.get(protection, 1)
	if level > 0 and (kp == null or not kp.is_available()):
		return PackedByteArray()
	var body := var_to_bytes(data)
	var iv := PackedByteArray()
	if level == 2:
		iv = Crypto.new().generate_random_bytes(16)
		var aes := AESContext.new()
		aes.start(AESContext.MODE_CBC_ENCRYPT, kp.derive("aes"), iv)
		body = aes.update(_pad(body))
		aes.finish()
	var kid := (kp.key_id() if level > 0 else "").to_ascii_buffer()
	var out := StreamPeerBuffer.new()
	out.big_endian = true
	out.put_data(MAGIC.to_ascii_buffer())
	out.put_u16(FORMAT_VERSION)
	out.put_u8(level)
	out.put_u8(kid.size())
	out.put_data(kid)
	if level == 2:
		out.put_data(iv)
	out.put_u32(body.size())
	out.put_data(body)
	var bytes := out.data_array
	if level > 0:
		bytes.append_array(AdvKeyProvider.hmac_sha256(kp.derive("hmac"), bytes))
	return bytes


## バイナリかテキストを読み、{ok, data, error, warning} を返す。
## on_tamper が "warn" なら、署名が一致しなくても警告つきで読み込む（暗号化されていない場合だけ）。
static func decode(bytes: PackedByteArray, kp: AdvKeyProvider, allow_text: bool = false, on_tamper: String = "reject") -> Dictionary:
	if bytes.size() > 0 and bytes[0] == 0x7b:  # "{" で始まればテキスト形式
		if not allow_text:
			return _fail(ERR_TEXT_DENIED)
		var d = JSON.parse_string(bytes.get_string_from_utf8())
		if not d is Dictionary or not d.has("adv80s_save"):
			return _fail(ERR_FORMAT)
		return {"ok": true, "data": AdvJson._strip_nulls(d.get("data", {})), "error": OK_CODE, "warning": "", "text": true}
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = bytes
	if bytes.size() < 16 or buf.get_data(8)[1].get_string_from_ascii() != MAGIC:
		return _fail(ERR_FORMAT)
	var version := buf.get_u16()
	if version > FORMAT_VERSION:
		return _fail(ERR_FORMAT)
	var level := buf.get_u8()
	var kid_len := buf.get_u8()
	var kid: String = buf.get_data(kid_len)[1].get_string_from_ascii()
	var iv := PackedByteArray()
	if level == 2:
		iv = buf.get_data(16)[1]
	var body_len := buf.get_u32()
	var body_start := buf.get_position()
	if body_start + body_len > bytes.size():
		return _fail(ERR_FORMAT)
	var body := bytes.slice(body_start, body_start + body_len)
	var warning := ""
	if level > 0:
		if kp == null or not kp.is_available():
			return _fail(ERR_NO_KEY)
		if kid != kp.key_id():
			return _fail(ERR_KEY_MISMATCH)
		var signed := bytes.slice(0, body_start + body_len)
		var sig := bytes.slice(body_start + body_len)
		if sig != AdvKeyProvider.hmac_sha256(kp.derive("hmac"), signed):
			if on_tamper != "warn" or level == 2:
				return _fail(ERR_TAMPERED)
			warning = ERR_TAMPERED
		if level == 2:
			var aes := AESContext.new()
			aes.start(AESContext.MODE_CBC_DECRYPT, kp.derive("aes"), iv)
			body = _unpad(aes.update(body))
			aes.finish()
			if body.is_empty():
				return _fail(ERR_TAMPERED)
	var data = bytes_to_var(body)
	if not data is Dictionary:
		return _fail(ERR_FORMAT)
	return {"ok": true, "data": data, "error": OK_CODE, "warning": warning, "text": false}


## テキスト形式（デバッグ用）。
static func encode_text(data: Dictionary) -> PackedByteArray:
	return (JSON.stringify({"adv80s_save": FORMAT_VERSION, "data": data}, "  ") + "\n").to_utf8_buffer()


static func write_file(path: String, bytes: PackedByteArray) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	# 書き込みの途中で落ちても前のセーブが壊れないように、一時ファイルから置き換える
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


static func read_file(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": code, "warning": "", "text": false}


static func _pad(b: PackedByteArray) -> PackedByteArray:
	var n := 16 - (b.size() % 16)
	var r := b.duplicate()
	for i in n:
		r.append(n)
	return r


static func _unpad(b: PackedByteArray) -> PackedByteArray:
	if b.is_empty():
		return b
	var n := b[b.size() - 1]
	if n < 1 or n > 16 or n > b.size():
		return PackedByteArray()
	for i in n:
		if b[b.size() - 1 - i] != n:
			return PackedByteArray()
	return b.slice(0, b.size() - n)
