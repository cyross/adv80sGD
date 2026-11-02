#!/usr/bin/env python3
"""サンプルの BGM（tests/stage1/assets/bgm/theme.wav）を作る開発用の道具。

FM 音源以前の PSG 風の音（矩形波・三角波・ノイズ）で、イントロ 4 小節のあとに
A（8）→ B（8）→ A'（8）→ C（8）の 32 小節を繰り返す曲を書き出す。
繰り返しの始まり（イントロの終わり）の秒数を表示するので、マニフェストの loop_start に書く。

  python3 tools/build_sample_bgm.py tests/stage1/assets/bgm/theme.wav

必要なもの：Python 3、numpy
"""
import sys
import wave

import numpy as np

RATE = 22050
BPM = 100
EIGHTH = 60.0 / BPM / 2          # 8分音符の長さ（秒）
BAR = EIGHTH * 8

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name):
    """"A4" → 440Hz。"""
    n, o = name[:-1], int(name[-1])
    midi = 12 * (o + 1) + NOTE[n]
    return 440.0 * 2 ** ((midi - 69) / 12)


# ---------------------------------------------------------------- 曲

CHORDS = {
    "Am": ["A", "C", "E"], "F": ["F", "A", "C"], "G": ["G", "B", "D"], "Em": ["E", "G", "B"],
    "Dm": ["D", "F", "A"], "E": ["E", "G#", "B"], "C": ["C", "E", "G"],
}

INTRO = ["Am", "Am", "F", "E"]
A = ["Am", "F", "G", "Em", "Am", "F", "Dm", "E"]
B = ["F", "G", "Am", "Am", "Dm", "Em", "F", "E"]
C = ["Dm", "Am", "Dm", "E", "F", "C", "Dm", "E"]

# 旋律：1小節に8分音符8つ。"=" は前の音をのばす、"-" は休み。
MEL_A = [
    "E5 = = A4 C5 E5 D5 C5", "C5 = = A4 F4 A4 C5 =", "D5 = = B4 G4 B4 D5 E5", "B4 = = = G4 = E4 =",
    "A4 C5 E5 = A5 = G5 E5", "F5 = E5 D5 C5 = A4 =", "D5 = F5 = E5 D5 C5 B4", "B4 = = = G#4 = = -",
]
MEL_B = [
    "A5 = = = G5 = F5 =", "G5 = = = F5 = E5 =", "E5 = = C5 = = A4 =", "B4 C5 D5 = E5 = = =",
    "F5 = = = E5 = D5 =", "E5 = = = D5 = B4 =", "C5 = A4 = C5 = F5 =", "E5 = = = D5 C5 B4 G#4",
]
MEL_A2 = MEL_A[:6] + ["D5 F5 A5 = G5 F5 E5 D5", "E5 = = = = = - -"]
MEL_C = [
    "D5 = A4 = F4 = A4 =", "C5 = A4 = E4 = A4 =", "F5 = D5 = A4 = D5 =", "E5 = = = B4 = G#4 =",
    "A4 = C5 = F5 = = E5", "E5 = D5 = C5 = G4 =", "F4 = A4 = D5 = F5 =", "E5 = = = = = = -",
]

SECTIONS = [  # (和音, 旋律, 盛り上がり 0〜1)
    (INTRO, ["- - - - - - - -"] * 4, 0.0),
    (A, MEL_A, 0.5),
    (B, MEL_B, 1.0),
    (A, MEL_A2, 0.6),
    (C, MEL_C, 0.3),
]


# ---------------------------------------------------------------- 音色

def square(f, n, duty=0.5):
    t = np.arange(n) / RATE
    ph = (t * f) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def triangle(f, n):
    t = np.arange(n) / RATE
    ph = (t * f) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def envelope(n, attack=0.005, decay=0.15, sustain=0.6, release=0.04):
    env = np.full(n, sustain)
    a = max(1, int(attack * RATE))
    d = max(1, int(decay * RATE))
    r = max(1, int(release * RATE))
    env[:a] = np.linspace(0, 1, a)[: len(env[:a])]
    end = min(n, a + d)
    env[a:end] = np.linspace(1, sustain, d)[: end - a]
    if n > r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def lead_note(f, n, idx):
    t = np.arange(n) / RATE
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.25) * 4, 0, 1)  # のばした音にだけビブラート
    ph = np.cumsum(f * vib / RATE) % 1.0
    duty = 0.25 if idx % 2 == 0 else 0.5
    s = np.where(ph < duty, 1.0, -1.0)
    return s * envelope(n, decay=0.2, sustain=0.55, release=0.05)


def kick(n):
    t = np.arange(n) / RATE
    f = 120 * np.exp(-t * 30) + 45
    ph = np.cumsum(f / RATE)
    return np.sin(2 * np.pi * ph) * np.exp(-t * 18)


def hat(n, rng):
    t = np.arange(n) / RATE
    noise = rng.uniform(-1, 1, n)
    noise = noise - np.concatenate(([0], noise[:-1]))  # 高い成分だけ残す
    return noise * np.exp(-t * 60)


# ---------------------------------------------------------------- 組み立て

def render():
    bars = sum(len(s[0]) for s in SECTIONS)
    total = int(bars * BAR * RATE) + RATE
    lead = np.zeros(total)
    bass = np.zeros(total)
    arp = np.zeros(total)
    drum = np.zeros(total)
    rng = np.random.default_rng(80)
    e8 = int(EIGHTH * RATE)
    e16 = e8 // 2
    bar_i = 0
    for chords, mel, energy in SECTIONS:
        for ch, line in zip(chords, mel):
            start = int(bar_i * BAR * RATE)
            tones = CHORDS[ch]
            # 旋律
            steps = line.split()
            i = 0
            while i < 8:
                s = steps[i]
                if s in ("-", "="):
                    i += 1
                    continue
                ln = 1
                while i + ln < 8 and steps[i + ln] == "=":
                    ln += 1
                n = e8 * ln
                p = start + e8 * i
                lead[p:p + n] += lead_note(freq(s), n, bar_i)
                i += ln
            # ベース：根音と5度を8分で
            root = tones[0]
            pattern = [root + "2", root + "3", tones[2] + "2", root + "3"] * 2
            for k, nm in enumerate(pattern):
                n = e8
                p = start + e8 * k
                bass[p:p + n] += triangle(freq(nm), n) * envelope(n, decay=0.1, sustain=0.7, release=0.02)
            # 分散和音：16分で和音の音を上下に
            seq = [tones[0] + "4", tones[1] + "4", tones[2] + "4", tones[1] + "4"]
            for k in range(16):
                n = e16
                p = start + e16 * k
                nm = seq[k % 4]
                arp[p:p + n] += square(freq(nm), n, 0.125) * envelope(n, decay=0.05, sustain=0.2, release=0.01)
            # 打楽器：盛り上がりに合わせて足す
            if bar_i >= 2 or energy > 0:
                for k in range(8):
                    p = start + e8 * k
                    if k in (0, 4) or (energy >= 1.0 and k == 6):
                        n = int(0.25 * RATE)
                        drum[p:p + n] += kick(n)[: len(drum[p:p + n])] * 0.9
                    if k % 2 == 1:
                        n = int(0.06 * RATE)
                        drum[p:p + n] += hat(n, rng) * (0.25 + 0.25 * energy)
            bar_i += 1
    # 旋律に軽いこだま（3/16拍あと）
    delay = int(EIGHTH * 1.5 * RATE)
    echo = np.zeros_like(lead)
    echo[delay:] = lead[:-delay] * 0.25
    lead = lead + echo
    mix = lead * 0.20 + bass * 0.30 + arp * 0.06 + drum * 0.10
    # 耳に痛い高い成分をやわらげる（1次のローパス）
    out = np.empty_like(mix)
    acc = 0.0
    k = 0.35
    for i in range(len(mix)):
        acc += k * (mix[i] - acc)
        out[i] = acc
    out = out / max(1e-6, np.max(np.abs(out))) * 0.8
    loop_start = len(INTRO) * BAR
    loop_end = int(bars * BAR * RATE)
    return out[:loop_end], loop_start


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "theme.wav"
    data, loop_start = render()
    pcm = (data * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)
    print("%s: %.1f 秒、loop_start = %.3f" % (path, len(data) / RATE, loop_start))


if __name__ == "__main__":
    main()
