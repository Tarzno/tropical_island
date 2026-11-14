"""Calls of the tropicbirds, the turnstones and the heron (Stable Audio output -> assets/audio).
    python3 tools/proc9.py ~/Desktop/share/ComfyUI/beach assets/audio
For each bird one of the two takes was chosen from its spectrum and envelope (printed by the
analysis in the session notes): tropicbird_v1 (chattering bursts at 2-4 kHz), turnstone_v1
(short sharp notes at 2-7 kHz), heron_v0 (hoarse notes of 0.7 s at 1-2 kHz). The script cuts
runs of sound (gaps shorter than `gap` belong to a run) of a fitting length. The results
were chosen by that analysis, not by ear."""
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

# name of the take, band kept, threshold (share of the loudest), longest gap inside a run (s),
# shortest and longest run (s), how many, name of the files
for take, lo, hi, thr, gap, lmin, lmax, count, out in (
        ('tropicbird_v1', 1200, 9000, 0.12, 0.22, 0.45, 3.2, 5, 'tropicbird'),
        ('turnstone_v1', 1500, 10000, 0.2, 0.3, 0.12, 1.6, 4, 'turnstone'),
        ('heron_v0', 600, 6000, 0.15, 0.1, 0.3, 1.3, 4, 'heron')):
    a = band(read(take), lo, hi)
    win = SR // 100
    n = len(a) // win
    e = np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1))
    on = e > np.percentile(e, 98) * thr
    runs = []; start = None; quiet = 0; g = int(gap * 100)
    for i in range(n):
        if on[i]:
            if start is None: start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet > g:
                runs.append((start, i - quiet + 1)); start = None
    if start is not None: runs.append((start, n))
    good = [(s, t) for s, t in runs if s > 5 and t < n - 5 and lmin <= (t - s) / 100 <= lmax]
    # the loudest first, then in the order they come
    good.sort(key=lambda r: -float(e[r[0]:r[1]].mean()))
    good = sorted(good[:count])
    for k, (s, t) in enumerate(good):
        pad = int(0.05 * SR)
        seg = a[max(s * win - pad, 0):t * win + pad].copy()
        fade = int(0.03 * SR)
        seg[:fade] *= np.linspace(0, 1, fade); seg[-fade:] *= np.linspace(1, 0, fade)
        seg *= 0.5 / max(np.abs(seg).max(), 1e-9)
        write(seg, f'{out}_{k}')
        print(f'{out}_{k}.wav: {take} from {s / 100:.1f} s, {(t - s) / 100:.1f} s long')
    if len(good) < count:
        print(f'{out}: only {len(good)} of {count} found ({len(runs)} runs in all)')
