// adv80s_mp4：OS のエンコーダーで MP4（H.264＋AAC）を書く（段階70）。
// いまは Windows（Media Foundation）だけ。ほかの環境では is_supported() が false を返す。
// open から close までは、同じスレッド（録画のスレッド）から順に呼ぶ。
#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class AdvMfWriter : public RefCounted {
	GDCLASS(AdvMfWriter, RefCounted)

	struct Impl;
	Impl *impl = nullptr;

protected:
	static void _bind_methods();

public:
	AdvMfWriter();
	~AdvMfWriter();

	// この環境で書けるか（Windows で Media Foundation と H.264 のエンコーダーがある）。
	bool is_supported() const;
	// ファイルを開く。path は OS のパス。audio_rate が 0 なら音なし（44100・48000 以外も音なし）。bitrate は映像のビット毎秒。
	Error open(const String &path, int width, int height, int fps, int audio_rate, int bitrate);
	// 音も書いているか（open のあと）。
	bool has_audio() const;
	// 1 コマ足す（RGB8 か RGBA8。大きさは open と同じ）。
	void add_video(const Ref<Image> &image);
	// 前のコマをもう一度足す。
	void repeat_video();
	// 音を足す（左右の組、-1〜1）。
	void add_audio(const PackedVector2Array &samples);
	// 書いたバイト数のめやす。
	int64_t get_size() const;
	// 閉じる。{frames, seconds, bytes}。
	Dictionary close();

	// 確かめ用：MP4 の中身 {video, width, height, fps, audio, audio_rate, channels, seconds}。読めなければ {}。
	Dictionary probe(const String &path) const;
	// 確かめ用：最初のコマ（RGB8）。読めなければ null。
	Ref<Image> read_first_frame(const String &path) const;
};

} // namespace godot
