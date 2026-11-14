"""Loops for the stream and the surf on the reef (Stable Audio output -> assets/audio).
    python3 tools/proc7.py ~/Desktop/share/ComfyUI/beach assets/audio
Of the two takes of each sound the steadier one is used (the envelope's spread is printed)."""
import numpy as np, subprocess, os, sys
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]

def read(name):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', f'{SRC}/{name}_00001.flac', '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()

def write(a, out, mono=False):
    if mono: a = a.mean(1, keepdims=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', str(a.shape[1]), '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/{out}.wav'], input=a.astype(np.float32).tobytes())

def spread(a):
    m = a.mean(1); win = SR // 4; n = len(m) // win
    e = 20 * np.log10(np.sqrt((m[:n * win].reshape(n, win) ** 2).mean(1)) + 1e-9)
    return float(np.percentile(e, 95) - np.percentile(e, 5)), float(e.mean())

def loop(a, out, xf=4.0, db=-20.0, mono=False):
    m = np.abs(a).max(1); idx = np.where(m > 1e-3)[0]
    a = a[int(0.4 * SR):idx[-1] + 1]
    X = int(xf * SR); L = len(a)
    t = np.linspace(0, np.pi / 2, X)[:, None]
    o = a[:L - X].copy()
    o[:X] = a[:X] * np.sin(t) + a[L - X:] * np.cos(t)
    o *= 10 ** (db / 20) / max(np.sqrt((o ** 2).mean()), 1e-9)
    write(o, out, mono)
    print(out, round(len(o) / SR, 1), 's')

for name, out, mono, xf in (('stream', 'stream', True, 3.0), ('reef_surf', 'reef_surf', False, 6.0)):
    takes = [(spread(read(f'{name}_v{k}')), k) for k in (0, 1)]
    for (sp, lvl), k in takes:
        print(f'{name}_v{k}: envelope spread {sp:.1f} dB, level {lvl:.1f} dB')
    best = min(takes)[1]
    loop(read(f'{name}_v{best}'), out, xf=xf, mono=mono)
