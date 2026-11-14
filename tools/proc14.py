"""Voices for the land birds and the crab plover, the reef's crackle and the diver's bubbles
(Stable Audio output -> assets/audio).   python3 tools/proc14.py ~/Desktop/share/ComfyUI/beach assets/audio
Calls: a take is band-limited, its loud runs found (pauses up to `gap` closed), the runs of
a fitting length kept, the loudest first, each faded and brought to a common RMS level (not
to its peak: see proc12.py). Loop: the steadier of the takes, 20 s, crossfaded. Bubbles: the
loudest 2 s. Chosen by numbers, not by ear."""
import numpy as np, subprocess, sys, os
SR = 48000
SRC = sys.argv[1]; DST = sys.argv[2]
db = lambda x: 20 * np.log10(max(float(x), 1e-9))

def read(name):
    path = f'{SRC}/{name}_00001.flac'
    if not os.path.exists(path):
        return None
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', path, '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()

def write(a, out):
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-i', '-', '-c:a', 'pcm_s16le', f'{DST}/{out}.wav'], input=a.astype(np.float32).tobytes())

def band(a, lo, hi):
    f = np.fft.rfft(a); fr = np.fft.rfftfreq(len(a), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(a))

def level(a, rms_db):
    a = a * (10 ** (rms_db / 20) / (np.sqrt((a ** 2).mean()) + 1e-9))
    return np.tanh(a * 1.2) / 1.2

def calls(takes, out, lo, hi, dmin, dmax, count, gap, rms_db):
    found = []
    for take in takes:
        a = read(take)
        if a is None: continue
        a = band(a, lo, hi)
        win = SR // 50; n = len(a) // win
        e = np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1))
        on = e > np.percentile(e, 98) * 0.2
        runs = []; start = None; quiet = 0
        for i in range(n):
            if on[i]:
                if start is None: start = i
                quiet = 0
            elif start is not None:
                quiet += 1
                if quiet > gap / 0.02:
                    runs.append((start, i - quiet + 1)); start = None
        if start is not None: runs.append((start, n))
        for s, t in runs:
            d = (t - s) * 0.02
            if dmin <= d <= dmax:
                found.append((float((e[s:t] ** 2).mean()), take, s, t, a))
    found.sort(key=lambda x: -x[0])
    lens = []
    for k, (_, take, s, t, a) in enumerate(found[:count]):
        c = a[max(s * SR // 50 - SR // 40, 0):min(t * SR // 50 + SR // 5, len(a))].copy()
        fi = SR // 100; fo = SR // 6
        c[:fi] *= np.linspace(0, 1, fi); c[-fo:] *= np.linspace(1, 0, fo) ** 2
        write(level(c, rms_db), f'{out}_{k}')
        lens.append(round(len(c) / SR, 2))
    print(f'{out}: {len(found)} runs fit, wrote {len(lens)}: {lens} s')

calls(['mynah_v0', 'mynah_v1'], 'mynah', 500, 9000, 0.5, 3.5, 5, 0.3, -17)
calls(['zebra_dove_v0'], 'zebra_dove', 250, 4000, 0.6, 4.0, 3, 0.35, -19)
calls(['fody_v0'], 'fody', 1200, 10000, 0.15, 2.5, 4, 0.25, -19)
calls(['magpie_robin_v0'], 'magpie_robin', 800, 9000, 0.8, 5.0, 3, 0.4, -17)
calls(['crab_plover_v0'], 'crab_plover', 400, 7000, 0.3, 3.0, 3, 0.3, -18)
# (four more, added later: the turtle's breath, the sand she
# throws, the white tern's own call, a coconut's thud)
calls(['turtle_breath_v0'], 'turtle_breath', 150, 8000, 0.6, 4.5, 3, 0.4, -18)
calls(['sand_fling_v0'], 'sand_fling', 300, 12000, 0.2, 2.0, 4, 0.2, -20)
calls(['white_tern_v0'], 'white_tern', 500, 9000, 0.3, 3.0, 4, 0.3, -18)
calls(['coconut_thud_v0'], 'coconut_thud', 40, 4000, 0.1, 1.6, 3, 0.25, -15)
# the reef's crackle: the steadier take, 20 s loop
best = None
for take in ['shrimp_v0', 'shrimp_v1']:
    a = read(take)
    if a is None: continue
    a = band(a, 800, 16000)
    win = SR // 4; n = len(a) // win
    e = 20 * np.log10(np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1)) + 1e-9)
    spread = float(np.percentile(e, 95) - np.percentile(e, 5))
    print(f'{take}: spread {spread:.1f} dB')
    if best is None or spread < best[0]: best = (spread, take, a)
if best:
    a = best[2]; xf = 2 * SR; n = 20 * SR; st = (len(a) - n - xf) // 2
    body = a[st:st + n + xf]; t = np.linspace(0, np.pi / 2, xf)
    out = body[:n].copy(); out[:xf] = body[:xf] * np.sin(t) + body[n:n + xf] * np.cos(t)
    write(level(out, -20), 'reef_crackle'); print('reef_crackle:', best[1])
a = read('bubbles_v0')
if a is not None:
    win = SR // 10; n = len(a) // win
    e = np.sqrt((a[:n * win].reshape(n, win) ** 2).mean(1))
    k = int(np.argmax(np.convolve(e, np.ones(20), 'valid')))
    c = a[k * win:k * win + 2 * SR].copy(); fi = SR // 50; fo = SR // 2
    c[:fi] *= np.linspace(0, 1, fi); c[-fo:] *= np.linspace(1, 0, fo) ** 2
    write(level(c, -18), 'dive_bubbles'); print('dive_bubbles: from %.1f s' % (k * 0.1))
