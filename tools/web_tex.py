#!/usr/bin/env python3
"""The orb web of the palm spider as a texture (assets/textures/spider_web.png, RGBA: golden
threads in alpha). Needs numpy and Pillow:  python3 tools/web_tex.py
The hub lies above the middle (at 0.40 of the height): scripts/critters.gd puts the spider there."""
import math, os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 512; K = 4; N = S * K
img = Image.new('L', (N, N), 0); d = ImageDraw.Draw(img)
rng = np.random.default_rng(12)
hub = np.array([0.5, 0.40]) * N
nr = 30
angs = np.sort(np.linspace(0, 2 * math.pi, nr, endpoint=False) + rng.uniform(-0.05, 0.05, nr))


def frame_r(a):
    return (0.47 + 0.02 * math.sin(3 * a + 1.0) + 0.015 * math.sin(5 * a)) * N


def ray_end(a):
    dirv = np.array([math.cos(a), math.sin(a)])
    c = np.array([0.5, 0.5]) * N
    t = 0.0
    for k in range(2000):
        p = hub + dirv * t
        if np.linalg.norm(p - c) > frame_r(math.atan2(p[1] - c[1], p[0] - c[0])):
            break
        t += N / 2000
    return hub + dirv * t, t


ends = [ray_end(a) for a in angs]
for (e, t) in ends:                               # the radii
    d.line([tuple(hub), tuple(e)], fill=150, width=3)
pts = [tuple(e) for e, _ in ends]                 # the frame threads
d.line(pts + [pts[0]], fill=200, width=4)
r = 0.035 * N                                     # the sticky spiral: chords between neighboring radii
while True:
    done = True
    for i in range(nr):
        a0 = angs[i]; a1 = angs[(i + 1) % nr]
        t0 = ends[i][1]; t1 = ends[(i + 1) % nr][1]
        rr0 = r * (1 + 0.04 * math.sin(i * 1.7 + r * 0.01)); rr1 = r * (1 + 0.04 * math.sin((i + 1) * 1.7 + r * 0.01))
        if rr0 < t0 * 0.97 and rr1 < t1 * 0.97:
            done = False
            p0 = hub + np.array([math.cos(a0), math.sin(a0)]) * rr0; p1 = hub + np.array([math.cos(a1), math.sin(a1)]) * rr1
            mid = (p0 + p1) / 2 + (hub - (p0 + p1) / 2) * 0.02
            d.line([tuple(p0), tuple(mid), tuple(p1)], fill=110 if r > 0.07 * N else 170, width=2)
    r += (0.0105 if r > 0.07 * N else 0.006) * N
    if done or r > N:
        break
a = np.asarray(img.resize((S, S), Image.LANCZOS)).astype(np.float32) / 255
a = np.clip(a * 2.2, 0, 1)
out = np.zeros((S, S, 4), np.uint8)
out[..., 0] = 255; out[..., 1] = 232; out[..., 2] = 150; out[..., 3] = (a * 255).astype(np.uint8)
Image.fromarray(out, 'RGBA').save(os.path.join(ROOT, 'assets/textures/spider_web.png'))
