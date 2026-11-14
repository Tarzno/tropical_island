"""Calls of the Seychelles frog (Stable Audio output -> assets/audio/frog_0..3.wav).
    python3 tools/proc8.py ~/Desktop/share/ComfyUI/beach assets/audio
Of the two takes the one whose energy lies higher is used (frog_v0: a pure tone at 3 kHz in
bouts of about eight peeps with silence between them; frog_v1 is a lower single note). The
script finds the bouts (runs of sound with gaps under 0.4 s), drops those cut off by the ends
of the file, and writes the first four. The choice was made from the
spectrum and the envelope, not by ear."""
import numpy as np, subprocess, sys
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]

def read(name):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', f'{SRC}/{name}_00001.flac', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()

def write(a, out):
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/{out}.wav'], input=a.astype(np.float32).tobytes())

def centroid(a):
    f = np.abs(np.fft.rfft(a)) ** 2; fr = np.fft.rfftfreq(len(a), 1 / SR)
    return float((f * fr).sum() / f.sum())

takes = {n: read(n) for n in ('frog_v0', 'frog_v1')}
for n, a in takes.items():
    print(f'{n}: {len(a) / SR:.1f} s, center of its spectrum {centroid(a):.0f} Hz')
name = max(takes, key=lambda n: centroid(takes[n]))
a = takes[name]
win = SR // 100
n = len(a) // win
e = np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1))
on = e > np.percentile(e, 95) * 0.06
# close gaps under 0.4 s, then list the runs
gap = 40
runs = []; start = None; quiet = 0
for i in range(n):
    if on[i]:
        if start is None: start = i
        quiet = 0
    elif start is not None:
        quiet += 1
        if quiet > gap:
            runs.append((start, i - quiet + 1)); start = None
if start is not None: runs.append((start, n))
out = 0
for s, t in runs:
    length = (t - s) / 100
    if s < 5 or t > n - 5 or not 1.2 <= length <= 4.5 or out >= 4:
        continue
    pad = int(0.06 * SR)
    seg = a[max(s * win - pad, 0):t * win + pad].copy()
    fade = int(0.04 * SR)
    seg[:fade] *= np.linspace(0, 1, fade); seg[-fade:] *= np.linspace(1, 0, fade)
    seg *= 0.5 / max(np.abs(seg).max(), 1e-9)
    peeps = int(np.sum(on[s + 1:t] & ~on[s:t - 1])) + 1
    write(seg, f'frog_{out}')
    print(f'frog_{out}.wav: {name} from {s / 100:.1f} s, {length:.1f} s long, {peeps} peeps')
    out += 1
if out < 4:
    print('only', out, 'bouts found')
