// adv80s_mp4：OS のエンコーダーで MP4（H.264＋AAC）を書く（段階70）。
#include "adv_mf_writer.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <vector>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#endif

using namespace godot;

#ifdef _WIN32

namespace {

template <class T>
void safe_release(T *&p) {
	if (p) {
		p->Release();
		p = nullptr;
	}
}

// COM と Media Foundation をこのスレッドで使えるようにする（閉じるときに戻す）。
struct MfScope {
	bool com = false;
	bool mf = false;
	bool start() {
		HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
		com = SUCCEEDED(hr); // S_OK・S_FALSE なら後で CoUninitialize。RPC_E_CHANGED_MODE はもう初期化済み
		mf = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
		return mf;
	}
	void stop() {
		if (mf) {
			MFShutdown();
			mf = false;
		}
		if (com) {
			CoUninitialize();
			com = false;
		}
	}
};

// Media Foundation の DLL があるか（Windows の N エディションでは、メディア機能パックがないとない）。
bool mf_dlls_present() {
	static int present = -1;
	if (present < 0) {
		HMODULE a = LoadLibraryW(L"mfplat.dll");
		HMODULE b = LoadLibraryW(L"mfreadwrite.dll");
		present = (a && b) ? 1 : 0;
		if (a) {
			FreeLibrary(a);
		}
		if (b) {
			FreeLibrary(b);
		}
	}
	return present == 1;
}

// RGB8・RGBA8 を NV12（BT.709、16〜235）にする。
void rgb_to_nv12(const uint8_t *src, int px, int w, int h, std::vector<uint8_t> &out) {
	out.resize((size_t)w * h * 3 / 2);
	uint8_t *y_plane = out.data();
	uint8_t *uv_plane = out.data() + (size_t)w * h;
	for (int y = 0; y < h; y++) {
		const uint8_t *row = src + (size_t)y * w * px;
		uint8_t *yr = y_plane + (size_t)y * w;
		for (int x = 0; x < w; x++) {
			const uint8_t *p = row + (size_t)x * px;
			yr[x] = (uint8_t)((47 * p[0] + 157 * p[1] + 16 * p[2] + 128) / 256 + 16);
		}
	}
	for (int y = 0; y < h; y += 2) {
		const uint8_t *r0 = src + (size_t)y * w * px;
		const uint8_t *r1 = src + (size_t)(y + 1) * w * px;
		uint8_t *uv = uv_plane + (size_t)(y / 2) * w;
		for (int x = 0; x < w; x += 2) {
			int r = 0, g = 0, b = 0;
			const uint8_t *q[4] = { r0 + (size_t)x * px, r0 + (size_t)(x + 1) * px, r1 + (size_t)x * px, r1 + (size_t)(x + 1) * px };
			for (int i = 0; i < 4; i++) {
				r += q[i][0];
				g += q[i][1];
				b += q[i][2];
			}
			r /= 4;
			g /= 4;
			b /= 4;
			int u = 128 + (-26 * r - 87 * g + 112 * b) / 256;
			int v = 128 + (112 * r - 102 * g - 10 * b) / 256;
			uv[x] = (uint8_t)(u < 16 ? 16 : (u > 240 ? 240 : u));
			uv[x + 1] = (uint8_t)(v < 16 ? 16 : (v > 240 ? 240 : v));
		}
	}
}

// 色の決まり（BT.709、16〜235）を型に書く。
void set_bt709(IMFMediaType *t) {
	t->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
	t->SetUINT32(MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709);
	t->SetUINT32(MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709);
	t->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235);
}

} // namespace

struct AdvMfWriter::Impl {
	MfScope scope;
	IMFSinkWriter *writer = nullptr;
	DWORD vstream = 0;
	DWORD astream = 0;
	bool audio = false;
	int width = 0;
	int height = 0;
	int fps = 30;
	int rate = 0;
	int64_t frames = 0;
	int64_t audio_frames = 0;
	std::vector<uint8_t> last;
	std::vector<int16_t> pcm;

	HRESULT write_video(const std::vector<uint8_t> &nv12) {
		IMFMediaBuffer *buf = nullptr;
		IMFSample *sample = nullptr;
		HRESULT hr = MFCreateMemoryBuffer((DWORD)nv12.size(), &buf);
		if (SUCCEEDED(hr)) {
			BYTE *dst = nullptr;
			hr = buf->Lock(&dst, nullptr, nullptr);
			if (SUCCEEDED(hr)) {
				memcpy(dst, nv12.data(), nv12.size());
				buf->Unlock();
				hr = buf->SetCurrentLength((DWORD)nv12.size());
			}
		}
		if (SUCCEEDED(hr)) {
			hr = MFCreateSample(&sample);
		}
		if (SUCCEEDED(hr)) {
			hr = sample->AddBuffer(buf);
		}
		if (SUCCEEDED(hr)) {
			LONGLONG t0 = frames * 10000000LL / fps;
			LONGLONG t1 = (frames + 1) * 10000000LL / fps;
			sample->SetSampleTime(t0);
			sample->SetSampleDuration(t1 - t0);
			hr = writer->WriteSample(vstream, sample);
		}
		if (SUCCEEDED(hr)) {
			frames++;
		}
		safe_release(sample);
		safe_release(buf);
		return hr;
	}

	void release() {
		safe_release(writer);
		scope.stop();
	}
};

AdvMfWriter::AdvMfWriter() {
	impl = new Impl();
}

AdvMfWriter::~AdvMfWriter() {
	if (impl->writer) {
		impl->writer->Finalize();
	}
	impl->release();
	delete impl;
}

bool AdvMfWriter::is_supported() const {
	static int supported = -1;
	if (supported >= 0) {
		return supported == 1;
	}
	supported = 0;
	if (!mf_dlls_present()) {
		return false;
	}
	MfScope s;
	if (s.start()) {
		MFT_REGISTER_TYPE_INFO out = { MFMediaType_Video, MFVideoFormat_H264 };
		IMFActivate **acts = nullptr;
		UINT32 count = 0;
		UINT32 flags = MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER;
		if (SUCCEEDED(MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, flags, nullptr, &out, &acts, &count))) {
			for (UINT32 i = 0; i < count; i++) {
				acts[i]->Release();
			}
			CoTaskMemFree(acts);
			supported = count > 0 ? 1 : 0;
		}
	}
	s.stop();
	return supported == 1;
}

Error AdvMfWriter::open(const String &path, int width, int height, int fps, int audio_rate, int bitrate) {
	if (impl->writer) {
		return ERR_ALREADY_IN_USE;
	}
	if (!is_supported()) {
		return ERR_UNAVAILABLE;
	}
	if (width < 2 || height < 2 || (width & 1) || (height & 1) || fps < 1) {
		return ERR_INVALID_PARAMETER;
	}
	Impl &m = *impl;
	m.width = width;
	m.height = height;
	m.fps = fps;
	m.frames = 0;
	m.audio_frames = 0;
	m.audio = audio_rate == 44100 || audio_rate == 48000; // AAC のエンコーダーが受け取れる速さだけ
	m.rate = m.audio ? audio_rate : 0;
	if (!m.scope.start()) {
		m.release();
		return ERR_UNAVAILABLE;
	}
	IMFAttributes *attr = nullptr;
	IMFMediaType *vout = nullptr, *vin = nullptr, *aout = nullptr, *ain = nullptr;
	HRESULT hr = MFCreateAttributes(&attr, 3);
	if (SUCCEEDED(hr)) {
		attr->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
		attr->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);
		attr->SetGUID(MF_TRANSCODE_CONTAINERTYPE, MFTranscodeContainerType_MPEG4);
		hr = MFCreateSinkWriterFromURL((LPCWSTR)path.wide_string().get_data(), nullptr, attr, &m.writer);
	}
	// 映像：書き出すのは H.264、渡すのは NV12
	if (SUCCEEDED(hr)) {
		hr = MFCreateMediaType(&vout);
	}
	if (SUCCEEDED(hr)) {
		vout->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
		vout->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
		vout->SetUINT32(MF_MT_AVG_BITRATE, (UINT32)(bitrate > 0 ? bitrate : 8000000));
		vout->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
		vout->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_High);
		MFSetAttributeSize(vout, MF_MT_FRAME_SIZE, width, height);
		MFSetAttributeRatio(vout, MF_MT_FRAME_RATE, fps, 1);
		MFSetAttributeRatio(vout, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
		set_bt709(vout);
		hr = m.writer->AddStream(vout, &m.vstream);
	}
	if (SUCCEEDED(hr)) {
		hr = MFCreateMediaType(&vin);
	}
	if (SUCCEEDED(hr)) {
		vin->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
		vin->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
		vin->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
		vin->SetUINT32(MF_MT_DEFAULT_STRIDE, (UINT32)width);
		MFSetAttributeSize(vin, MF_MT_FRAME_SIZE, width, height);
		MFSetAttributeRatio(vin, MF_MT_FRAME_RATE, fps, 1);
		MFSetAttributeRatio(vin, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
		set_bt709(vin);
		hr = m.writer->SetInputMediaType(m.vstream, vin, nullptr);
	}
	// 音：書き出すのは AAC（192 kbps）、渡すのは 16 ビットの PCM
	if (SUCCEEDED(hr) && m.audio) {
		HRESULT ah = MFCreateMediaType(&aout);
		if (SUCCEEDED(ah)) {
			aout->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
			aout->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
			aout->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
			aout->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, (UINT32)m.rate);
			aout->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
			aout->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);
			aout->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 0);
			ah = m.writer->AddStream(aout, &m.astream);
		}
		if (SUCCEEDED(ah)) {
			ah = MFCreateMediaType(&ain);
		}
		if (SUCCEEDED(ah)) {
			ain->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
			ain->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
			ain->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
			ain->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, (UINT32)m.rate);
			ain->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
			ain->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
			ain->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, (UINT32)m.rate * 4);
			ah = m.writer->SetInputMediaType(m.astream, ain, nullptr);
		}
		hr = ah;
	}
	if (SUCCEEDED(hr)) {
		hr = m.writer->BeginWriting();
	}
	safe_release(attr);
	safe_release(vout);
	safe_release(vin);
	safe_release(aout);
	safe_release(ain);
	if (FAILED(hr)) {
		m.release();
		return ERR_CANT_CREATE;
	}
	return OK;
}

bool AdvMfWriter::has_audio() const {
	return impl->writer && impl->audio;
}

void AdvMfWriter::add_video(const Ref<Image> &image) {
	Impl &m = *impl;
	if (!m.writer || image.is_null() || image->get_width() != m.width || image->get_height() != m.height) {
		return;
	}
	Image::Format f = image->get_format();
	if (f != Image::FORMAT_RGB8 && f != Image::FORMAT_RGBA8) {
		return;
	}
	PackedByteArray data = image->get_data();
	rgb_to_nv12(data.ptr(), f == Image::FORMAT_RGB8 ? 3 : 4, m.width, m.height, m.last);
	m.write_video(m.last);
}

void AdvMfWriter::repeat_video() {
	Impl &m = *impl;
	if (m.writer && !m.last.empty()) {
		m.write_video(m.last);
	}
}

void AdvMfWriter::add_audio(const PackedVector2Array &samples) {
	Impl &m = *impl;
	int64_t n = samples.size();
	if (!m.writer || !m.audio || n == 0) {
		return;
	}
	m.pcm.resize((size_t)n * 2);
	const Vector2 *s = samples.ptr();
	for (int64_t i = 0; i < n; i++) {
		float l = s[i].x < -1.0f ? -1.0f : (s[i].x > 1.0f ? 1.0f : s[i].x);
		float r = s[i].y < -1.0f ? -1.0f : (s[i].y > 1.0f ? 1.0f : s[i].y);
		m.pcm[(size_t)i * 2] = (int16_t)(l * 32767.0f);
		m.pcm[(size_t)i * 2 + 1] = (int16_t)(r * 32767.0f);
	}
	DWORD bytes = (DWORD)(n * 4);
	IMFMediaBuffer *buf = nullptr;
	IMFSample *sample = nullptr;
	HRESULT hr = MFCreateMemoryBuffer(bytes, &buf);
	if (SUCCEEDED(hr)) {
		BYTE *dst = nullptr;
		hr = buf->Lock(&dst, nullptr, nullptr);
		if (SUCCEEDED(hr)) {
			memcpy(dst, m.pcm.data(), bytes);
			buf->Unlock();
			hr = buf->SetCurrentLength(bytes);
		}
	}
	if (SUCCEEDED(hr)) {
		hr = MFCreateSample(&sample);
	}
	if (SUCCEEDED(hr)) {
		hr = sample->AddBuffer(buf);
	}
	if (SUCCEEDED(hr)) {
		LONGLONG t0 = m.audio_frames * 10000000LL / m.rate;
		LONGLONG t1 = (m.audio_frames + n) * 10000000LL / m.rate;
		sample->SetSampleTime(t0);
		sample->SetSampleDuration(t1 - t0);
		hr = m.writer->WriteSample(m.astream, sample);
	}
	if (SUCCEEDED(hr)) {
		m.audio_frames += n;
	}
	safe_release(sample);
	safe_release(buf);
}

int64_t AdvMfWriter::get_size() const {
	if (!impl->writer) {
		return 0;
	}
	MF_SINK_WRITER_STATISTICS st = {};
	st.cb = sizeof(st);
	if (SUCCEEDED(impl->writer->GetStatistics((DWORD)MF_SINK_WRITER_ALL_STREAMS, &st))) {
		return (int64_t)st.qwByteCountProcessed;
	}
	return 0;
}

Dictionary AdvMfWriter::close() {
	Impl &m = *impl;
	Dictionary d;
	if (!m.writer) {
		return d;
	}
	int64_t bytes = get_size();
	HRESULT hr = m.writer->Finalize();
	d["ok"] = SUCCEEDED(hr);
	d["frames"] = m.frames;
	d["seconds"] = (double)m.frames / m.fps;
	d["bytes"] = bytes;
	m.release();
	m.last.clear();
	return d;
}

static String subtype_name(const GUID &g) {
	if (g == MFVideoFormat_H264) {
		return "h264";
	}
	if (g == MFAudioFormat_AAC) {
		return "aac";
	}
	if (g == MFAudioFormat_PCM) {
		return "pcm";
	}
	return "other";
}

Dictionary AdvMfWriter::probe(const String &path) const {
	Dictionary d;
	if (!is_supported()) {
		return d;
	}
	MfScope s;
	if (!s.start()) {
		return d;
	}
	IMFSourceReader *reader = nullptr;
	if (SUCCEEDED(MFCreateSourceReaderFromURL((LPCWSTR)path.wide_string().get_data(), nullptr, &reader))) {
		IMFMediaType *t = nullptr;
		if (SUCCEEDED(reader->GetNativeMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &t))) {
			GUID g = {};
			t->GetGUID(MF_MT_SUBTYPE, &g);
			UINT32 w = 0, h = 0, num = 0, den = 1;
			MFGetAttributeSize(t, MF_MT_FRAME_SIZE, &w, &h);
			MFGetAttributeRatio(t, MF_MT_FRAME_RATE, &num, &den);
			d["video"] = subtype_name(g);
			d["width"] = (int64_t)w;
			d["height"] = (int64_t)h;
			d["fps"] = den ? (double)num / den : 0.0;
			safe_release(t);
		}
		if (SUCCEEDED(reader->GetNativeMediaType((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, &t))) {
			GUID g = {};
			t->GetGUID(MF_MT_SUBTYPE, &g);
			d["audio"] = subtype_name(g);
			d["audio_rate"] = (int64_t)MFGetAttributeUINT32(t, MF_MT_AUDIO_SAMPLES_PER_SECOND, 0);
			d["channels"] = (int64_t)MFGetAttributeUINT32(t, MF_MT_AUDIO_NUM_CHANNELS, 0);
			safe_release(t);
		}
		PROPVARIANT pv;
		PropVariantInit(&pv);
		if (SUCCEEDED(reader->GetPresentationAttribute((DWORD)MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &pv)) && pv.vt == VT_UI8) {
			d["seconds"] = (double)pv.uhVal.QuadPart / 10000000.0;
		}
		PropVariantClear(&pv);
		safe_release(reader);
	}
	s.stop();
	return d;
}

Ref<Image> AdvMfWriter::read_first_frame(const String &path) const {
	Ref<Image> img;
	if (!is_supported()) {
		return img;
	}
	MfScope s;
	if (!s.start()) {
		return img;
	}
	IMFAttributes *attr = nullptr;
	IMFSourceReader *reader = nullptr;
	IMFMediaType *want = nullptr, *cur = nullptr;
	IMFSample *sample = nullptr;
	IMFMediaBuffer *buf = nullptr;
	HRESULT hr = MFCreateAttributes(&attr, 1);
	if (SUCCEEDED(hr)) {
		attr->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
		hr = MFCreateSourceReaderFromURL((LPCWSTR)path.wide_string().get_data(), attr, &reader);
	}
	if (SUCCEEDED(hr)) {
		hr = MFCreateMediaType(&want);
	}
	if (SUCCEEDED(hr)) {
		want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
		want->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
		hr = reader->SetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, want);
	}
	if (SUCCEEDED(hr)) {
		hr = reader->GetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &cur);
	}
	DWORD flags = 0;
	if (SUCCEEDED(hr)) {
		hr = reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, &flags, nullptr, &sample);
	}
	if (SUCCEEDED(hr) && sample) {
		hr = sample->ConvertToContiguousBuffer(&buf);
	}
	if (SUCCEEDED(hr) && buf) {
		UINT32 w = 0, h = 0;
		MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &w, &h);
		LONG stride = (LONG)MFGetAttributeUINT32(cur, MF_MT_DEFAULT_STRIDE, w * 4);
		BYTE *src = nullptr;
		DWORD len = 0;
		if (w > 0 && h > 0 && SUCCEEDED(buf->Lock(&src, nullptr, &len)) && len >= w * h * 4) {
			PackedByteArray out;
			out.resize((int64_t)w * h * 3);
			uint8_t *o = out.ptrw();
			LONG pitch = stride < 0 ? -stride : stride;
			for (UINT32 y = 0; y < h; y++) {
				// 幅の負の値は下から上の並び
				const BYTE *row = src + (size_t)(stride < 0 ? (h - 1 - y) : y) * pitch;
				for (UINT32 x = 0; x < w; x++) {
					o[((size_t)y * w + x) * 3 + 0] = row[x * 4 + 2];
					o[((size_t)y * w + x) * 3 + 1] = row[x * 4 + 1];
					o[((size_t)y * w + x) * 3 + 2] = row[x * 4 + 0];
				}
			}
			buf->Unlock();
			img = Image::create_from_data((int32_t)w, (int32_t)h, false, Image::FORMAT_RGB8, out);
		}
	}
	safe_release(buf);
	safe_release(sample);
	safe_release(cur);
	safe_release(want);
	safe_release(reader);
	safe_release(attr);
	s.stop();
	return img;
}

#else // ほかの環境：まだない（is_supported が false）

struct AdvMfWriter::Impl {};
AdvMfWriter::AdvMfWriter() { impl = new Impl(); }
AdvMfWriter::~AdvMfWriter() { delete impl; }
bool AdvMfWriter::is_supported() const { return false; }
Error AdvMfWriter::open(const String &, int, int, int, int, int) { return ERR_UNAVAILABLE; }
bool AdvMfWriter::has_audio() const { return false; }
void AdvMfWriter::add_video(const Ref<Image> &) {}
void AdvMfWriter::repeat_video() {}
void AdvMfWriter::add_audio(const PackedVector2Array &) {}
int64_t AdvMfWriter::get_size() const { return 0; }
Dictionary AdvMfWriter::close() { return Dictionary(); }
Dictionary AdvMfWriter::probe(const String &) const { return Dictionary(); }
Ref<Image> AdvMfWriter::read_first_frame(const String &) const { return Ref<Image>(); }

#endif

void AdvMfWriter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &AdvMfWriter::is_supported);
	ClassDB::bind_method(D_METHOD("open", "path", "width", "height", "fps", "audio_rate", "bitrate"), &AdvMfWriter::open);
	ClassDB::bind_method(D_METHOD("has_audio"), &AdvMfWriter::has_audio);
	ClassDB::bind_method(D_METHOD("add_video", "image"), &AdvMfWriter::add_video);
	ClassDB::bind_method(D_METHOD("repeat_video"), &AdvMfWriter::repeat_video);
	ClassDB::bind_method(D_METHOD("add_audio", "samples"), &AdvMfWriter::add_audio);
	ClassDB::bind_method(D_METHOD("get_size"), &AdvMfWriter::get_size);
	ClassDB::bind_method(D_METHOD("close"), &AdvMfWriter::close);
	ClassDB::bind_method(D_METHOD("probe", "path"), &AdvMfWriter::probe);
	ClassDB::bind_method(D_METHOD("read_first_frame", "path"), &AdvMfWriter::read_first_frame);
}
