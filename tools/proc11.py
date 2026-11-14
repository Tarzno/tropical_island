"""Loops for the rain shower (Stable Audio output -> assets/audio).
    python3 tools/proc11.py ~/Desktop/share/ComfyUI/beach assets/audio
rain.wav: rain on leaves and ground (the steadier of two takes); rain_sea.wav: rain on the
sea; drips.wav: dripping from the leaves afterward (of two takes the one with the more
separate drops: the higher crest factor). Nobody has listened to the results."""
import numpy as np, subprocess, sys
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]

def read(name):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', f'{SRC}/{name}_00001.flac', '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()

def write(a, out):
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', str(a.shape[1]), '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/{out}.wav'], input=a.astype(np.float32).tobytes())

def env(a, win=SR // 4):
    m = a.mean(1); n = len(m) // win
    return 20 * np.log10(np.sqrt((m[:n * win].reshape(n, win) ** 2).mean(1)) + 1e-9)

def spread(a):
    e = env(a)
    return float(np.percentile(e, 95) - np.percentile(e, 5))

def crest(a):
    m = a.mean(1)
    return float(20 * np.log10(np.percentile(np.abs(m), 99.9) / (np.sqrt((m ** 2).mean()) + 1e-9)))

def loop(a, out, xf=5.0, db=-20.0):
    m = np.abs(a).max(1); idx = np.where(m > 1e-3)[0]
    a = a[int(0.5 * SR):idx[-1] + 1 - int(0.3 * SR)]
    X = int(xf * SR); L = len(a)
    t = np.linspace(0, np.pi / 2, X)[:, None]
    o = a[:L - X].copy()
    o[:X] = a[:X] * np.sin(t) + a[L - X:] * np.cos(t)
    o *= 10 ** (db / 20) / max(np.sqrt((o ** 2).mean()), 1e-9)
    o = np.clip(o, -0.98, 0.98)
    write(o, out)
    print(f'{out}.wav: {len(o) / SR:.1f} s')

def bands(a):
    m = a.mean(1); F = np.abs(np.fft.rfft(m)) ** 2; fr = np.fft.rfftfreq(len(m), 1 / SR)
    tot = F.sum()
    return [int(100 * F[(fr >= lo) & (fr < hi)].sum() / tot) for lo, hi in ((0, 250), (250, 1000), (1000, 4000), (4000, 24000))]

r = [(spread(read(f'rain_v{k}')), k) for k in (0, 1)]
for sp, k in r:
    print(f'rain_v{k}: envelope spread {sp:.1f} dB, bands % (<250, <1k, <4k, above) {bands(read(f"rain_v{k}"))}')
loop(read(f'rain_v{min(r)[1]}'), 'rain')
a = read('rain_sea_v0')
print(f'rain_sea_v0: envelope spread {spread(a):.1f} dB, bands {bands(a)}')
loop(a, 'rain_sea')
d = [(crest(read(f'drips_v{k}')), k) for k in (0, 1)]
for c, k in d:
    print(f'drips_v{k}: crest {c:.1f} dB, envelope spread {spread(read(f"drips_v{k}")):.1f} dB, bands {bands(read(f"drips_v{k}"))}')
loop(read(f'drips_v{max(d)[1]}'), 'drips', xf=4.0, db=-26.0)
