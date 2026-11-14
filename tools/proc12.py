"""The diver's breath on coming up (Stable Audio output -> assets/audio/dive_breath.wav).
    python3 tools/proc12.py ~/Desktop/share/ComfyUI/beach assets/audio [take]
The takes (dive_breath_v0-3: "a blast of air clearing a snorkel, then a deep breath") have
a short loud burst near their start and a longer rush of air one to two seconds later. The
script takes the burst, closes the pause to a quarter of a second, takes the breath, and
brings the breath to -12 dB RMS (as loud as the surf is at its loudest; the first version,
peak-normalized and played at -3 to -12 dB, lay 8-15 dB under the waves and was not heard,
2026-11-11). Peaks are rounded off, not clipped. Default take: v2 (the clearest
burst, the most air-like spectrum). Chosen by numbers, not by ear."""
import numpy as np, subprocess, sys
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]
take = sys.argv[3] if len(sys.argv) > 3 else 'dive_breath_v2'

raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', f'{SRC}/{take}_00001.flac', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'], capture_output=True).stdout
a = np.frombuffer(raw, dtype=np.float32).copy()
win = SR // 50                                        # 20 ms
n = len(a) // win
e = np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1))
loud = e > e.max() * 0.16
# runs of loud windows (gaps up to 0.16 s closed)
runs = []; start = None; quiet = 0
for i in range(n):
    if loud[i]:
        if start is None: start = i
        quiet = 0
    elif start is not None:
        quiet += 1
        if quiet > 8:
            runs.append([start, i - quiet + 1]); start = None
if start is not None:
    runs.append([start, n])
runs = [r for r in runs if r[1] - r[0] >= 3]
print(take, 'loud parts (s):', [(round(r[0] * 0.02, 2), round(r[1] * 0.02, 2)) for r in runs])
breath = max(runs, key=lambda r: r[1] - r[0])
before = [r for r in runs if r[1] <= breath[0]]
def cut(r, lead=0.03, tail=0.25):
    s = max(int((r[0] * 0.02 - lead) * SR), 0); t = min(int((r[1] * 0.02 + tail) * SR), len(a))
    c = a[s:t].copy()
    fi = int(0.01 * SR); fo = int(min(tail, 0.25) * SR)
    c[:fi] *= np.linspace(0, 1, fi); c[-fo:] *= np.linspace(1, 0, fo) ** 2
    return c
b = cut(breath, tail=0.5)
rms = np.sqrt((b[:int((breath[1] - breath[0]) * 0.02 * SR)] ** 2).mean())
gain = 10 ** (-12 / 20) / rms
parts = []
if before:
    blast = cut(before[0], tail=0.12)
    # (the burst no louder than the breath's loudest moments)
    parts += [blast * min(gain, 0.6 / np.abs(blast).max()), np.zeros(int(0.25 * SR), dtype=np.float32)]
parts.append(b * gain)
out = np.concatenate(parts)
out = np.tanh(out * 1.1) / 1.1 * 0.97                 # around the peaks off
db = lambda x: 20 * np.log10(max(x, 1e-9))
print(f'{len(out) / SR:.2f} s, peak {db(np.abs(out).max()):.1f} dB, rms {db(np.sqrt((out ** 2).mean())):.1f} dB, with a burst first: {bool(before)}')
subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/dive_breath.wav'], input=out.astype(np.float32).tobytes())
