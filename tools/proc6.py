# Frigatebird display calls (bill rattling and warbling of the courting males), cut from the
# Stable Audio takes frigate_v0/v1 (comfyui_workflows/gen/sa_frigate_v*.json).
# Usage: python3 tools/proc6.py ~/Desktop/share/ComfyUI/beach assets/audio
import sys
src = open(sys.argv[0].replace('proc6.py', 'proc5.py')).read()
src = src[:src.index("loop('cave_drips_v0'")]
exec(src)


def slice_bursts(name, prefix, minlen, maxlen, db, first=0, gap=25, thr_db=-14, pre=0.04, post=0.3):
    """Like slice_events, but a burst may contain pauses of up to gap/100 s (a rattle is a train of clicks)."""
    a = trim_tail(read(name))
    e = env(a, int(0.01 * SR)); edb = 20 * np.log10(e + 1e-9)
    on = edb > np.percentile(edb, 98) + thr_db
    segs = []; i = 0
    while i < len(on):
        if on[i]:
            j = i; g = 0
            while j < len(on) and g < gap:
                g = g + 1 if not on[j] else 0
                j += 1
            segs.append((i, j - g)); i = j
        else:
            i += 1
    k = first
    for s, e2 in segs:
        if not (minlen <= (e2 - s) * 0.01 <= maxlen):
            continue
        a0 = max(0, int((s * 0.01 - pre) * SR)); a1 = min(len(a), int((e2 * 0.01 + post) * SR))
        seg = a[a0:a1].copy()
        f = np.ones(len(seg)); fi = int(0.01 * SR); fo = int(0.2 * SR)
        f[:fi] = np.linspace(0, 1, fi); f[-fo:] = np.linspace(1, 0, fo) ** 2
        seg *= f[:, None]
        seg = seg / np.abs(seg).max() * (10 ** (db / 20))
        write(seg, f'{prefix}_{k}', True)
        print(f'{prefix}_{k}', round((e2 - s) * 0.01, 2), 's')
        k += 1
    return k


n = slice_bursts('frigate_v1', 'frigate', 1.0, 3.5, -8)
slice_bursts('frigate_v0', 'frigate', 1.0, 3.5, -8, first=n)
