class_name AdvEmbeddedKeyProvider
extends AdvKeyProvider
## プロジェクトに埋め込んだ鍵を使う（標準、8.1）。元鍵は次の順に探す。
##   1. 環境変数 ADV80S_MASTER_KEY（16進数64文字。CI で書き出すとき用）
##   2. res://adv80s_key.bin（書き出し時にプラグインが作る。平文ではない形で入れる）
##   3. res://master.key（16進数64文字。開発用。Git の管理対象から外しておく）
## エディタのツールメニュー「adv80s: セーブの鍵を生成」で master.key を作れる。

const ENV_NAME := "ADV80S_MASTER_KEY"
const KEY_FILE := "res://master.key"
const EMBEDDED_FILE := "res://adv80s_key.bin"
const _MASK_SEED := "adv80s-embedded-key-mask-v1"

var _cache := PackedByteArray()


func get_master_key() -> PackedByteArray:
	if _cache.is_empty():
		_cache = AdvEmbeddedKeyProvider.find_master_key()
	return _cache


## 元鍵を探す（上の順）。見つからなければ空の配列。
static func find_master_key() -> PackedByteArray:
	var env := OS.get_environment(ENV_NAME).strip_edges()
	if env.length() == 64 and env.is_valid_hex_number():
		return env.hex_decode()
	if FileAccess.file_exists(EMBEDDED_FILE):
		var k := unmask(FileAccess.get_file_as_bytes(EMBEDDED_FILE))
		if k.size() == 32:
			return k
	if FileAccess.file_exists(KEY_FILE):
		var hex := FileAccess.get_file_as_string(KEY_FILE).strip_edges()
		if hex.length() == 64 and hex.is_valid_hex_number():
			return hex.hex_decode()
	return PackedByteArray()


## master.key を乱数で作る。すでにあれば作らない（鍵を変えると、それまでのセーブが読めなくなるため）。
static func generate_key_file(path: String = KEY_FILE) -> Error:
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var key := Crypto.new().generate_random_bytes(32)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(key.hex_encode() + "\n")
	f.close()
	return OK


## 書き出すゲームに入れる形（平文のままにしない）。
static func mask(key: PackedByteArray) -> PackedByteArray:
	var m := AdvKeyProvider.sha256(_MASK_SEED.to_utf8_buffer())
	var out := PackedByteArray()
	out.resize(key.size())
	for i in key.size():
		out[key.size() - 1 - i] = key[i] ^ m[i % m.size()] ^ (i * 37 & 0xff)
	return out


static func unmask(data: PackedByteArray) -> PackedByteArray:
	var m := AdvKeyProvider.sha256(_MASK_SEED.to_utf8_buffer())
	var out := PackedByteArray()
	out.resize(data.size())
	for i in data.size():
		out[i] = data[data.size() - 1 - i] ^ m[i % m.size()] ^ (i * 37 & 0xff)
	return out
