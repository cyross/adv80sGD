class_name AdvKeyProvider
extends RefCounted
## セーブの鍵を渡す部品の基底クラス（8.1）。元鍵（32バイト）から、用途別の鍵を HMAC-SHA256 で作る。
## 自作する場合は、このクラスを継承して get_master_key() を実装する。


## 元鍵（32バイト）。用意できなければ空の配列。
func get_master_key() -> PackedByteArray:
	return PackedByteArray()


## 用途別の鍵（"hmac"、"aes" など）。
func derive(purpose: String) -> PackedByteArray:
	return AdvKeyProvider.hmac_sha256(get_master_key(), ("adv80s:" + purpose).to_utf8_buffer())


## 鍵の識別子（鍵そのものは含まない）。セーブのヘッダーに入れ、「鍵が違う」と「改ざん」を区別する。
func key_id() -> String:
	var k := get_master_key()
	if k.is_empty():
		return ""
	return AdvKeyProvider.hmac_sha256(k, "adv80s:key-id".to_utf8_buffer()).hex_encode().substr(0, 16)


func is_available() -> bool:
	return get_master_key().size() == 32


static func hmac_sha256(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	var h := HMACContext.new()
	if h.start(HashingContext.HASH_SHA256, key) != OK:
		return PackedByteArray()
	h.update(msg)
	return h.finish()


static func sha256(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()
