"""The sooty tern colony's voice (Stable Audio output -> assets/audio/sooty_colony.wav).
    python3 tools/proc13.py ~/Desktop/share/ComfyUI/beach assets/audio [take]
Of the takes sooty_v0-2 the steadiest is taken (the smallest spread of loudness over
quarter seconds: a colony's clamor has no pauses), unless one is named. Its middle 24 s
are made into a loop (the end faded over the beginning, 3 s, equal power), brought to
-15 dB RMS (a little over the surf's) and the peaks rounded off. Chosen by numbers,
not by ear."""
import numpy as np, subprocess, sys
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]

def read(name):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', f'{SRC}/{name}_00001.flac', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()

def stats(a):
    win = SR // 4; n = len(a) // win
    e = 20 * np.log10(np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1)) + 1e-9)
    spec = np.abs(np.fft.rfft(a[:SR * 8] * np.hanning(SR * 8))) ** 2
    fr = np.fft.rfftfreq(SR * 8, 1 / SR)
    return float(np.percentile(e, 95) - np.percentile(e, 5)), float((fr * spec).sum() / spec.sum()), float(e.mean())

best = None
for take in (sys.argv[3:] or ['sooty_v0', 'sooty_v1', 'sooty_v2']):
    a = read(take)
    spread, centroid, level = stats(a[SR:-SR])
    print(f'{take}: {len(a) / SR:.1f} s, loudness spread {spread:.1f} dB, centroid {centroid:.0f} Hz, mean {level:.1f} dB')
    if best is None or spread < best[0]:
        best = (spread, take, a)
_, take, a = best
xf = 3 * SR; n = 24 * SR
start = max((len(a) - n - xf) // 2, 0)
body = a[start:start + n + xf].copy()
t = np.linspace(0, np.pi / 2, xf)
out = body[:n].copy()
out[:xf] = body[:xf] * np.sin(t) + body[n:n + xf] * np.cos(t)
out *= 10 ** (-15 / 20) / np.sqrt((out ** 2).mean())
out = np.tanh(out * 1.2) / 1.2
db = lambda x: 20 * np.log10(max(x, 1e-9))
print(f'chosen: {take}; loop {len(out) / SR:.1f} s, rms {db(np.sqrt((out ** 2).mean())):.1f} dB, peak {db(np.abs(out).max()):.1f} dB')
subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/sooty_colony.wav'], input=out.astype(np.float32).tobytes())
