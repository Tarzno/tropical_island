"""A parrotfish biting coral, heard under water (Stable Audio output -> assets/audio).
    python3 tools/proc10.py ~/Desktop/share/ComfyUI/beach assets/audio
The takes (parrotfish_v0-2) are trains of sharp clicks at 1-4 kHz. A bite is a short run of
them: the script groups clicks that follow each other within `gap` and keeps runs of a
fitting length, the loudest first. Chosen by envelope and spectrum, not by ear."""
import numpy as np, subprocess, sys
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]

def read(name):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', f'{SRC}/{name}_00001.flac', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()

def write(a, out):
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/{out}.wav'], input=a.astype(np.float32).tobytes())

def band(a, lo, hi):
    f = np.fft.rfft(a); fr = np.fft.rfftfreq(len(a), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(a))

found = []
for take in sys.argv[3:] or ['parrotfish_v1', 'parrotfish_v0']:
    a = band(read(take), 350, 9000)
    win = SR // 200                                   # 5 ms
    n = len(a) // win
    e = np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1))
    on = e > np.percentile(e, 99) * 0.22
    gap = 24                                          # 0.12 s
    runs = []; start = None; quiet = 0
    for i in range(n):
        if on[i]:
            if start is None: start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet > gap:
                runs.append((start, i - quiet + 1)); start = None
    for s, t in runs:
        dur = (t - s) / 200
        clicks = int(np.sum(np.diff(on[s:t].astype(int)) == 1)) + 1
        if s > 20 and t < n - 20 and 0.12 <= dur <= 0.75 and clicks >= 3:
            found.append((float(e[s:t].mean()) * min(clicks, 8), take, s, t, clicks, a))
    print(f'{take}: {len(runs)} runs')
found.sort(key=lambda r: -r[0])
for k, (score, take, s, t, clicks, a) in enumerate(found[:6]):
    win = SR // 200
    pad = int(0.03 * SR)
    seg = a[max(s * win - pad, 0):t * win + int(0.08 * SR)].copy()
    fade = int(0.01 * SR)
    seg[:fade] *= np.linspace(0, 1, fade); seg[-fade * 4:] *= np.linspace(1, 0, fade * 4)
    seg *= 0.6 / max(np.abs(seg).max(), 1e-9)
    write(seg, f'crunch_{k}')
    print(f'crunch_{k}.wav: {take} from {s / 200:.2f} s, {(t - s) / 200:.2f} s long, {clicks} clicks')
if len(found) < 6:
    print(f'only {len(found)} bites found')
