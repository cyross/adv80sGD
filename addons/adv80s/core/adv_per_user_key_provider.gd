class_name AdvPerUserKeyProvider
extends AdvEmbeddedKeyProvider
## 埋め込んだ元鍵に、その端末で最初に作った乱数を混ぜる（8.1）。セーブを他の端末に持ち出せなくなる。

const DEVICE_FILE := "user://adv80s_device.bin"

var _mixed := PackedByteArray()


func get_master_key() -> PackedByteArray:
	if _mixed.is_empty():
		var base := super.get_master_key()
		if base.is_empty():
			return base
		_mixed = AdvKeyProvider.hmac_sha256(base, _device_salt())
	return _mixed


static func _device_salt() -> PackedByteArray:
	if FileAccess.file_exists(DEVICE_FILE):
		var b := FileAccess.get_file_as_bytes(DEVICE_FILE)
		if b.size() == 32:
			return b
	var salt := Crypto.new().generate_random_bytes(32)
	var f := FileAccess.open(DEVICE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_buffer(salt)
		f.close()
	return salt
