#!/usr/bin/env python3
"""(Compass: +x west, -x east, +z north, -z south; the names in here were turned around on
2026-11-12, see HANDOFF.md "Orientation": EAST was WEST, TIP_N was TIP_S, and so on.)

Second stage of the island terrain. Needs only numpy and Pillow (no Blender):

    python3 tools/terrain2.py            # preview images only (tools/terrain_preview/)
    python3 tools/terrain2.py --write    # also writes the project files

Input: tools/terrain_base.npz, the frozen output of the first stage (island.py, run inside
Blender with the original .blend: the start beach and its surroundings as modeled there, the
hill, the ridge). This stage turns that into the final island:

  * the coast: the first stage is a rectangle with ruler-straight shores. A displacement field
    bends it (a headland below the hill and two bays on the east coast, tapering south-west and
    north-west coasts, rounded tips). The start beach and everything fitted to it stay untouched.
  * the sea floor: a lagoon all around the island running out to a scalloped reef edge and a
    fore-reef slope of about 30 degrees (the first stage dropped 25 m within a few meters of the
    east beach and of the tips), coral heads in the lagoon, and no end of the sea floor in sight.
  * the land: small-scale unevenness, and bare granite (slabs with ledges) where the hill is steep.

Output: heightmap.exr (R terrain, G terrain + rocks, world x/z in [-256, 256], row 0 = z -256),
landmask.png (R forest floor, G rock / coral, B open grass), terrain_ext.glb (mesh "TerrainExt",
material "Sand"), models/island.json (adds "taper": how far the west coast was moved at each z,
so landscape.gd can move the copies of the original treeline with it).
The shaders continue the heightmap outside its area (world.gdshaderinc: ground_height): keep
`outside()` here in step with it.
"""
import json, os, struct, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets/textures/")
MOD = os.path.join(ROOT, "assets/models/")
PREVIEW = os.path.join(ROOT, "tools/terrain_preview/")
N = 2048
EXT = 256.0
PX = 2 * EXT / N
c = (np.arange(N) + 0.5) / N * 2 * EXT - EXT
X, Z = np.meshgrid(c, c)          # arrays are [row = z, column = x]

PEAK = np.array([-110.0, -12.0])   # Godot x, z
PATH = np.array([(-9, 40), (-22, 40), (-38, 35), (-54, 26), (-68, 16), (-81, 6), (-93, -2), (-102, -8), (-107, -11)], float)
# The grotto: a way through a pile of granite boulders on the hillside above the start beach.
# Nodes along it: x, z, floor height (None = the hillside as it is), half-width of the space at
# floor level, height of the space. tools/grotto2.py piles the boulders around this space.
CAVE_PATH = [
    (-53.5, 45.4, None, 1.5, 2.7),     # in front of the entrance
    (-58.0, 45.9, 5.25, 1.5, 2.9),     # entrance cleft
    (-62.2, 46.3, 5.3, 4.3, 4.7),      # front chamber
    (-64.6, 46.9, 5.35, 4.1, 4.5),
    (-68.8, 48.8, 5.8, 1.35, 2.7),     # passage
    (-74.0, 51.9, 6.8, 1.45, 2.9),
    (-78.8, 52.6, 7.5, 5.2, 6.3),      # inner chamber
    (-81.6, 52.0, 7.55, 5.0, 6.0),
    (-86.0, 48.2, 9.3, 1.4, 2.8),      # way up and out
    (-89.6, 44.9, 11.1, 1.5, 2.8),
    (-93.2, 42.0, None, 1.6, 2.7),     # above the upper exit
]
CAVE_OPEN = (3.4, 3.2)                 # meters of the path at either end that lie in the open

# The stream: a seep at the foot of the summit's granite, a gully down the valley to the
# south-west with small rock pools, and a pond behind the beach where the water sinks into the sand.
STREAM_SPRING = (-105.0, -45.0)
STREAM_LEN = 80.0
STREAM_POOLS = [(12.0, 1.15), (28.0, 1.35), (44.5, 1.2), (61.0, 1.5)]   # meters along the course, radius
STREAM_POND = (2.7, 3.7)               # half-axes of the pond at the end (along / across the course: it lies across the slope)


def cave_samples(h=None, step=0.3):
    """Points along the grotto every `step` m: x, z, floor, half-width, height, arc length."""
    nodes = []
    for (x, z, fl, w, hg) in CAVE_PATH:
        if fl is None:
            fl = float(bilinear(h, np.array([x]), np.array([z]))[0]) if h is not None else 0.0
        nodes.append((x, z, fl, w, hg))
    nodes = np.array(nodes)
    seg = np.hypot(np.diff(nodes[:, 0]), np.diff(nodes[:, 1]))
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    s = np.arange(0.0, arc[-1] + 1e-6, step)
    out = np.stack([np.interp(s, arc, nodes[:, k]) for k in range(5)] + [s], 1)
    # smooth the changes of width and height (rooms open out gradually)
    for k in (3, 4):
        out[:, k] = np.convolve(np.pad(out[:, k], 4, mode="edge"), np.ones(9) / 9.0, mode="valid")
    return out

# west coast: beyond these latitudes it turns away to the east by TAPER_K meters per meter
TAPER_S = (-135.0, 0.20)
TAPER_N = (138.0, 0.30)
TAPER_R = 12.0                     # length over which the turn sets in


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def bilinear(img, x, z):
    """Samples img (N x N, world extent) at world x, z; clamps at the border."""
    u = np.clip((x + EXT) / PX - 0.5, 0, N - 1.001)
    v = np.clip((z + EXT) / PX - 0.5, 0, N - 1.001)
    x0 = u.astype(np.int32); y0 = v.astype(np.int32)
    fx = (u - x0).astype(np.float32); fy = (v - y0).astype(np.float32)
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def vnoise(x, z, wavelength, seed):
    """Smooth value noise in [-1, 1]."""
    r = np.random.default_rng(seed)
    G = 256
    lat = r.uniform(-1, 1, (G, G)).astype(np.float32)
    ang = r.uniform(0, 6.28)
    ca, sa = np.cos(ang), np.sin(ang)
    u = (x * ca - z * sa) / wavelength + 31.7
    v = (x * sa + z * ca) / wavelength + 17.3
    iu = np.floor(u).astype(np.int64); iv = np.floor(v).astype(np.int64)
    fu = u - iu; fv = v - iv
    fu = fu * fu * fu * (fu * (fu * 6 - 15) + 10); fv = fv * fv * fv * (fv * (fv * 6 - 15) + 10)
    a = lat[iv % G, iu % G]; b = lat[iv % G, (iu + 1) % G]
    d = lat[(iv + 1) % G, iu % G]; e = lat[(iv + 1) % G, (iu + 1) % G]
    return ((a * (1 - fu) + b * fu) * (1 - fv) + (d * (1 - fu) + e * fu) * fv).astype(np.float32)


def fbm(x, z, wavelength, seed, octaves=4, gain=0.5):
    out = 0.0; amp = 1.0; tot = 0.0
    for k in range(octaves):
        out = out + amp * vnoise(x, z, wavelength / (2 ** k), seed + 13 * k)
        tot += amp; amp *= gain
    return out / tot


def curve(points, t):
    """Smooth curve through (t, value) control points (flat at each point)."""
    pts = np.array(points, float)
    i = np.clip(np.searchsorted(pts[:, 0], t) - 1, 0, len(pts) - 2)
    t0 = pts[i, 0]; t1 = pts[i + 1, 0]
    f = np.clip((t - t0) / (t1 - t0), 0, 1)
    f = f * f * (3 - 2 * f)
    return pts[i, 1] * (1 - f) + pts[i + 1, 1] * f


def path_dist(x, z):
    d = np.full(np.shape(x), 1e9)
    for a, b in zip(PATH[:-1], PATH[1:]):
        ab = b - a; L2 = (ab ** 2).sum()
        t = np.clip(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / L2, 0, 1)
        d = np.minimum(d, np.hypot(x - (a[0] + t * ab[0]), z - (a[1] + t * ab[1])))
    return d


# ------------------------------------------------------------------ the coast
def taper(z):
    """How far (m) the west coast lies east of where the first stage put it, at latitude z."""
    def ramp(u, k):
        u = np.maximum(u, 0.0)
        return k * (u - TAPER_R * (1.0 - np.exp(-u / TAPER_R)))
    return ramp(TAPER_S[0] - z, TAPER_S[1]) + ramp(z - TAPER_N[0], TAPER_N[1])


# east coast: meters the shore lies further east (+) or west (-) than the straight line
EAST = [(-256, 0), (-222, 0), (-188, 6), (-132, -15), (-74, 3), (-14, 15), (36, 10), (102, -19), (148, -9), (190, 6), (224, 0), (256, 0)]
# the tips: meters the shore is pulled in toward the middle of the island, by x
TIP_S = [(-256, 26), (-170, 26), (-138, 12), (-104, -3), (-72, 1), (-36, 13), (-6, 22), (60, 24), (256, 24)]
TIP_N = [(-256, 26), (-172, 26), (-140, 17), (-112, 9), (-82, 6), (-50, 11), (-20, 21), (40, 26), (256, 26)]


def displacement(x, z):
    """The final island at (x, z) shows what the first stage has at (x + dx, z + dz)."""
    wig = 1.6 * np.sin(z / 14.0 + 1.0) + 1.0 * np.sin(z / 6.1 + 2.5) + 0.6 * np.sin(z / 3.3 + 0.7)
    east = (curve(EAST, z) + wig * ss(232, 205, np.abs(z))) * ss(-112.0, -154.0, x)
    west = taper(z) * ss(-95.0, -55.0, x)
    wig_t = 1.4 * np.sin(x / 11.0 + 0.4) + 0.9 * np.sin(x / 5.2 + 1.9)
    south = -(curve(TIP_S, x) + wig_t) * ss(-140.0, -195.0, z)
    north = (curve(TIP_N, x) + wig_t) * ss(140.0, 195.0, z)
    return east + west, south + north


# ------------------------------------------------------------------ distance to the shore
def shore_distance(land):
    """Distance (m) from every pixel to the nearest land, 0 on land (exact transform at 0.5 m)."""
    n = N // 2
    L = land.reshape(n, 2, n, 2).any(axis=(1, 3))
    big = 1e6
    g = np.where(L, 0.0, big)
    for j in range(1, n):
        g[j] = np.minimum(g[j], g[j - 1] + 1)
    for j in range(n - 2, -1, -1):
        g[j] = np.minimum(g[j], g[j + 1] + 1)
    g2 = (g * g).astype(np.float32)
    idx = np.arange(n, dtype=np.float32)
    dx2 = (idx[:, None] - idx[None, :]) ** 2
    d2 = np.empty((n, n), np.float32)
    for j in range(n):
        d2[j] = (dx2 + g2[j][None, :]).min(axis=1)
    d = np.sqrt(d2) * (2 * PX)
    # back to full resolution, smoothed over the 0.5 m cells
    big_d = np.repeat(np.repeat(d, 2, 0), 2, 1)
    return blur(big_d, 2)


def blur(a, r):
    """Box blur of radius r pixels, applied twice (close to a Gaussian)."""
    for _ in range(2):
        for ax in (0, 1):
            cs = np.cumsum(np.pad(a, [(r + 1, r) if k == ax else (0, 0) for k in (0, 1)], mode="edge"), axis=ax, dtype=np.float64)
            if ax == 0:
                a = (cs[2 * r + 1:] - cs[:-(2 * r + 1)]) / (2 * r + 1)
            else:
                a = (cs[:, 2 * r + 1:] - cs[:, :-(2 * r + 1)]) / (2 * r + 1)
    return a.astype(np.float32)


def outside(h_edge, x, z):
    """Sea floor outside the heightmap: falls away from its border (as ground_height() in
    world.gdshaderinc)."""
    dx = np.maximum(np.abs(x) - EXT, 0.0); dz = np.maximum(np.abs(z) - EXT, 0.0)
    return np.maximum(h_edge - 0.5 * np.hypot(dx, dz), np.minimum(h_edge, -30.0))


# ------------------------------------------------------------------ the stream
def stream_cut(h, info):
    """Traces the stream down the valley from STREAM_SPRING, cuts its gully, rock pools and the
    pond at its end into h. Returns the new h, the distance to the course, masks and the data
    for the game (island.json: "stream")."""
    hs = blur(h, 20)
    gz, gx = np.gradient(hs, PX)
    x, z = STREAM_SPRING
    pts = []
    for k in range(int(STREAM_LEN / 0.5) + 1):
        pts.append((x, z))
        j = int((z + EXT) / PX); i = int((x + EXT) / PX)
        g = np.array([gx[j, i], gz[j, i]]); n = np.hypot(g[0], g[1]) + 1e-9
        x -= g[0] / n * 0.5; z -= g[1] / n * 0.5
    pts = np.array(pts)
    s = np.arange(len(pts)) * 0.5
    tan = np.gradient(pts, axis=0); tan /= np.linalg.norm(tan, axis=1, keepdims=True)
    nrm = np.stack([-tan[:, 1], tan[:, 0]], 1)
    off = 1.5 * np.sin(s / 5.3 + 0.8) + 0.9 * np.sin(s / 2.9 + 2.1)
    off *= ss(0.0, 6.0, s) * ss(STREAM_LEN, STREAM_LEN - 8.0, s)
    pts = pts + nrm * off[:, None]
    # resample evenly (0.25 m)
    seg = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 1])); arc = np.concatenate([[0.0], np.cumsum(seg)])
    s = np.arange(0.0, arc[-1], 0.25)
    pts = np.stack([np.interp(s, arc, pts[:, 0]), np.interp(s, arc, pts[:, 1])], 1)
    total = float(s[-1])
    # the bed: the valley floor as it is, falling all the way, cut in by up to 0.8 m
    hb = bilinear(h, pts[:, 0], pts[:, 1])
    hb = np.convolve(np.pad(hb, 8, mode="edge"), np.ones(17) / 17.0, mode="valid")
    hb = np.minimum.accumulate(hb)
    bed = hb - (0.2 + 0.6 * ss(0.0, 12.0, s)) * ss(total + 2.0, total - 12.0, s) - 0.25
    # ledges: the bed comes down in steps of rock, not as a ramp
    q = s / 7.3 + 0.35 * np.sin(s / 3.1)
    bed = bed + 0.16 * (ss(0.15, 0.85, q - np.floor(q)) - (q - np.floor(q))) * 2.0
    half = 1.5 + 0.9 * ss(0.0, 20.0, s)             # half-width of the gully
    half = half * (1.0 + 0.3 * np.sin(s / 4.1 + 1.0) + 0.2 * np.sin(s / 1.7 + 0.3))
    pools = []
    for (sp, r) in STREAM_POOLS:
        lip = float(np.interp(sp + r, s, bed))
        m = np.abs(s - sp) < r
        bed[m] = np.minimum(bed[m], lip - 0.42 * (1.0 - ((s[m] - sp) / r) ** 2) ** 0.7)
        up = (s > sp - r - 2.2) & (s <= sp - r)       # the fall into the pool
        half = np.maximum(half, (r + 1.3) * ss(r + 2.5, r, np.abs(s - sp)))
        px_ = float(np.interp(sp, s, pts[:, 0])); pz_ = float(np.interp(sp, s, pts[:, 1]))
        pools.append([px_, pz_, lip + 0.02, r])
    # the pond
    ra, rb = STREAM_POND
    pc = pts[-1] - (pts[-1] - pts[-9]) / np.linalg.norm(pts[-1] - pts[-9]) * 0.0
    pdir = (pts[-1] - pts[-25]); pdir /= np.linalg.norm(pdir)
    pond_c = pts[-1] + pdir * (ra - 0.6)
    level = float(bed[-1]) - 0.2                    # (the stream drops a hand's breadth into it)
    yaw = float(np.arctan2(pdir[1], pdir[0]))

    win = (slice(int((pts[:, 1].min() - 16 + EXT) / PX), int((pts[:, 1].max() + 16 + EXT) / PX)),
           slice(int((pts[:, 0].min() - 16 + EXT) / PX), int((pts[:, 0].max() + 16 + EXT) / PX)))
    xw = X[win]; zw = Z[win]
    dd = np.full(xw.shape, 99.0, np.float32); bw = np.zeros(xw.shape, np.float32); hw = np.ones(xw.shape, np.float32); sw = np.zeros(xw.shape, np.float32)
    for k in range(0, len(pts), 2):
        dk = np.hypot(xw - pts[k, 0], zw - pts[k, 1])
        m = dk < dd
        dd[m] = dk[m]; bw[m] = bed[k]; hw[m] = half[k]; sw[m] = s[k]
    hh = h[win].copy()
    # (banks of soil that slump in here and there: not a channel of one width)
    wob = 1.0 + 0.3 * vnoise(xw, zw, 3.1, 315) + 0.15 * vnoise(xw, zw, 1.2, 316)
    f = ss(1.0, 0.25, dd / (hw * wob))
    target = bw + 0.07 * vnoise(xw, zw, 1.3, 311) + 0.05 * vnoise(xw, zw, 0.6, 312) + 0.22 * np.maximum(vnoise(xw, zw, 2.4, 317), 0.0) * ss(0.2, 0.8, dd / hw)
    hh = hh * (1.0 - f) + np.minimum(hh, target) * f
    # pond: a basin, with a low bar of sand and roots on the downhill side
    ux = (xw - pond_c[0]) * pdir[0] + (zw - pond_c[1]) * pdir[1]
    uz = -(xw - pond_c[0]) * pdir[1] + (zw - pond_c[1]) * pdir[0]
    rho = np.hypot(ux / ra, uz / rb) * (1.0 + 0.12 * vnoise(xw, zw, 2.2, 313))
    basin = level - 0.55 * np.clip(1.0 - rho ** 2, 0.0, 1.0) ** 0.8
    rim = (rho - 1.0) * rb                            # meters outside the pond's edge
    # (the bar closes the basin all the way around: where the ground fell away below the water
    # level on the downhill side, the water's flat sheet stood out over it with a straight edge)
    bar = level + 0.2 - 0.3 * np.maximum(rim - 1.2, 0.0)
    hh = np.where(rho < 1.0, np.minimum(hh, basin), np.where(rim < 5.0, np.maximum(hh, np.minimum(bar, hh + 1.3)), hh))
    hh = np.where((rho >= 1.0) & (rim < 1.2), np.minimum(hh, level + 0.2 + rim * 0.5), hh)   # shelving banks
    out = h.copy(); out[win] = hh
    dist = np.full(h.shape, 99.0, np.float32); dist[win] = np.minimum(dd, np.maximum(rim, 0.0))
    # wet line: 1 on the course, falling to 0 at 2 m to either side (the shader makes the
    # trickle and the damp rock beside it from this); it starts at the seep and ends in the pond
    water = np.zeros(h.shape, np.float32)
    # (around the pond the ground is only damp: 0.68 stays below the value at which the ground
    # shader draws running water, which otherwise ran into the pond from every side)
    water[win] = np.maximum(np.clip(1.0 - dd / 2.0, 0.0, 1.0) * ss(0.4, 2.5, sw) * (rho > 1.0), np.minimum(np.clip(1.0 - np.maximum(rim, 0.0) / 2.0, 0.0, 1.0), 0.68))
    rock = np.zeros(h.shape, np.float32)
    # bare rock in the bed where the water has washed it clean: the ledges and the pools, not all of it
    bare = ss(-0.3, 0.05, vnoise(xw, zw, 5.5, 314) + 0.25 * np.sin(sw / 7.3 * 6.28) + 0.15)
    rock[win] = ss(0.7, 0.3, dd / (hw * wob)) * bare * ss(total + 1.0, total - 9.0, sw) * (rho > 1.0)
    sandbar = np.zeros(h.shape, np.float32)
    sandbar[win] = ss(0.5, 0.05, rim)                 # mud at the pond's edge and on its bottom
    js = {"course": [[round(float(pts[k, 0]), 2), round(float(pts[k, 1]), 2), round(float(bed[k]), 2)] for k in range(0, len(pts), 4)],
          "pools": [[round(v, 2) for v in p] for p in pools],
          "pond": [round(float(pond_c[0]), 2), round(float(pond_c[1]), 2), round(level, 2), ra, rb, round(yaw, 3)]}
    return {"h": out, "dist": dist, "water": water, "rock": rock, "sandbar": sandbar, "json": js}


# ------------------------------------------------------------------ build
def build():
    base = np.load(os.path.join(ROOT, "tools/terrain_base.npz"))
    R0 = base["R"].astype(np.float32)
    rocks0 = base["rocks"].astype(np.float32)      # height of the original boulders above the terrain
    info = {}

    # ---- 1. the coast
    dx, dz = displacement(X, Z)
    h = bilinear(R0, X + dx, Z + dz)
    still = (np.abs(dx) + np.abs(dz)) < 1e-6        # untouched: the start beach, the hill's west side
    h = np.where(still, R0, h)
    info["untouched_land_m2"] = float((still & (R0 > 0)).sum() * PX * PX)

    # ---- 2. the land: unevenness of the ground, granite where it is steep
    pd = path_dist(X, Z)
    calm = 1.0 - 0.75 * np.exp(-pd ** 2 / (2 * 7.0 ** 2))          # the ridge stays easy to walk
    calm *= 1.0 - 0.8 * np.exp(-((X - PEAK[0]) ** 2 + (Z - PEAK[1]) ** 2) / (2 * 14.0 ** 2))
    # (nothing changes where the objects of the original scene stand)
    orig = ss(-52.0, -40.0, X) * ss(150.0, 138.0, np.abs(Z))
    calm *= 1.0 - orig
    rough = 0.34 * fbm(X, Z, 19.0, 101, 4, 0.5) + 0.10 * fbm(X, Z, 3.4, 202, 2, 0.5)
    h = h + rough * ss(1.7, 3.2, h) * calm

    gz, gx = np.gradient(blur(h, 3), PX)
    slope = np.hypot(gx, gz)
    # (outcrops, not the whole flank: between them the forest climbs the hill as before)
    rock_n = fbm(X, Z, 34.0, 303, 3, 0.55)
    rock = ss(0.47, 0.72, slope) * ss(-0.03, 0.15, rock_n + 0.3 * (slope - 0.85)) * ss(3.0, 5.0, h) * (1.0 - orig)
    # (no specks: a patch of a few square meters on a smooth slope reads as paint)
    rock = rock * ss(0.22, 0.4, blur(rock, 14))
    # the grotto: distance from the floor of its rooms and passages (negative inside), and the
    # floor height that belongs to each place
    cs = cave_samples(h)
    win = (slice(int((cs[:, 1].min() - 22 + EXT) / PX), int((cs[:, 1].max() + 22 + EXT) / PX)),
           slice(int((cs[:, 0].min() - 22 + EXT) / PX), int((cs[:, 0].max() + 22 + EXT) / PX)))
    cave_f = np.full(h.shape, 99.0, np.float32)     # ... of the whole way, with the approaches
    cave_in = np.full(h.shape, 99.0, np.float32)    # ... of the part under the boulders
    cave_fl = np.zeros(h.shape, np.float32)
    cave_s = np.zeros(h.shape, np.float32)          # how far along the way the nearest point of it is
    xw = X[win]; zw = Z[win]
    fw = np.full(xw.shape, 99.0, np.float32); flw = np.zeros(xw.shape, np.float32); iw = fw.copy(); sw = flw.copy()
    for (cx, cz, fl, w, hg, s_) in cs:
        dd = np.hypot(xw - cx, zw - cz) - w
        m = dd < fw
        fw[m] = dd[m]; flw[m] = fl; sw[m] = s_
        if CAVE_OPEN[0] + 0.6 < s_ < cs[-1, 5] - CAVE_OPEN[1] - 0.6:
            iw = np.minimum(iw, dd)
    cave_f[win] = fw; cave_fl[win] = flw; cave_in[win] = iw; cave_s[win] = sw
    rock = blur(rock, 2)
    # slabs: broad convex backs with ledges across the slope
    slab = fbm(X, Z, 13.0, 505, 3, 0.5)
    ledge_h = 3.4
    q = (h + 2.6 * fbm(X, Z, 21.0, 606, 3)) / ledge_h
    step = (np.floor(q) + ss(0.30, 0.70, q - np.floor(q))) * ledge_h - q * ledge_h
    # ... and the rounded backs between the joints of the rock (creases every few meters)
    pil = 1.0 - np.abs(fbm(X, Z, 7.5, 808, 2, 0.5)) * 2.2
    pil = np.clip(pil, 0.0, 1.0) ** 0.6
    h = h + rock * calm * ss(2.0, 7.0, cave_f) * (0.5 * slab + 0.3 * step + 0.45 * (pil - 0.6))

    # ---- 2b. the stream
    stream = stream_cut(h, info)
    h = stream["h"]
    rock = np.maximum(rock, stream["rock"])

    # ---- 2c. whalebacks: backs of granite coming out of the forest floor
    rng_d = np.random.default_rng(909)
    dome = np.zeros_like(h); dome_m = np.zeros_like(h)
    centers = []
    for t in range(3000):
        if len(centers) >= 11:
            break
        bx = rng_d.uniform(-160, -56); bz = rng_d.uniform(-165, 165)
        j = int((bz + EXT) / PX); i = int((bx + EXT) / PX)
        if not (3.2 < h[j, i] < 30.0) or pd[j, i] < 13.0 or cave_f[j, i] < 16.0 or stream["dist"][j, i] < 9.0 or slope[j, i] > 0.55:
            continue
        if np.hypot(bx - PEAK[0], bz - PEAK[1]) < 24.0 or rock[j, i] > 0.2 or any(np.hypot(bx - a, bz - b) < 26.0 for a, b in centers):
            continue
        centers.append((bx, bz))
        for k in range(int(rng_d.integers(1, 4))):
            ang = rng_d.uniform(0, 6.28); off = 0.0 if k == 0 else rng_d.uniform(4.0, 7.5)
            cx = bx + off * np.cos(ang); cz = bz + off * np.sin(ang)
            ra = rng_d.uniform(3.2, 6.5) * (1.0 if k == 0 else 0.7); rb = ra * rng_d.uniform(0.55, 0.95)
            hh = rb * rng_d.uniform(0.26, 0.4); yaw = rng_d.uniform(0, 3.14)
            r0 = int(ra * 1.4 / PX)
            jj = int((cz + EXT) / PX); ii = int((cx + EXT) / PX)
            js = slice(jj - r0, jj + r0); is_ = slice(ii - r0, ii + r0)
            ux = (X[js, is_] - cx) * np.cos(yaw) + (Z[js, is_] - cz) * np.sin(yaw)
            uz = -(X[js, is_] - cx) * np.sin(yaw) + (Z[js, is_] - cz) * np.cos(yaw)
            q = np.hypot(ux / ra, uz / rb) * (1.0 + 0.16 * vnoise(X[js, is_], Z[js, is_], 2.6, 900 + len(centers) * 7 + k))
            cap = np.clip(1.0 - q * q, 0.0, 1.0)
            dome[js, is_] = np.maximum(dome[js, is_], hh * cap)
            dome_m[js, is_] = np.maximum(dome_m[js, is_], ss(1.06, 0.9, q))
    info["whalebacks"] = len(centers)
    h = h + dome
    rock = np.maximum(rock, dome_m)

    # ---- 2d. the east headland: bare granite running into the sea
    hd_n = vnoise(X, Z, 11.0, 71)
    head_m = np.zeros_like(h)
    for (cx, cz, ra, rb) in ((-183.0, -15.0, 13.0, 22.0), (-180.0, 9.0, 8.0, 9.0), (-181.0, -40.0, 7.0, 8.0), (-193.0, -22.0, 7.0, 6.0)):
        rho_h = np.hypot((X - cx) / ra, (Z - cz) / rb) + 0.3 * hd_n + 0.14 * vnoise(X, Z, 3.6, 72)
        head_m = np.maximum(head_m, ss(1.0, 0.74, rho_h))
    bul = np.clip(1.0 - np.abs(fbm(X, Z, 6.0, 73, 2, 0.5)) * 2.4, 0.0, 1.0) ** 0.7
    head_rise = head_m * (0.15 + 1.25 * bul * (0.55 + 0.45 * vnoise(X, Z, 15.0, 74)))
    h = np.where(h > -0.4, h + head_rise * ss(-0.4, 0.5, h), h)
    rock = np.maximum(rock, head_m * ss(-0.5, 0.0, h))
    # the floor of the grotto: sand between the boulders, cut into the slope where the rooms
    # are, with steep banks (which the boulders stand in front of)
    floor = cave_fl + 0.05 * vnoise(X, Z, 2.3, 707)
    cut = np.minimum(h, floor + np.maximum(cave_f, 0.0) * 1.25)
    inside = ss(0.6, -0.3, cave_f)
    # (at both ends the way runs out onto the hillside as it is: no level pad with a bank behind it)
    ends = ss(0.0, 3.0, cave_s) * ss(cs[-1, 5], cs[-1, 5] - 3.0, cave_s)
    h = np.where(cave_f < 12.0, h * (1.0 - ends) + (cut * (1.0 - inside) + floor * inside) * ends, h)

    land = h > 0.0

    # ---- 3. the sea floor
    d = shore_distance(land)
    # depth profile of the original beach by distance from the shore (rows around the start)
    rows = [int((zz + EXT) / PX) for zz in range(-50, 61, 10)]
    dist_s = np.arange(0.0, 61.0, 1.0)             # (further out some rows reach the first stage's drop-off)
    prof = np.zeros_like(dist_s)
    for j in rows:
        i0 = np.where(R0[j, N // 2 - 100:] <= 0.0)[0][0] + N // 2 - 100
        prof += np.interp(dist_s, (np.arange(i0, N) - i0) * PX, R0[j, i0:])
    prof /= len(rows)
    prof = np.minimum.accumulate(prof)

    def P(dist):
        return np.where(dist < 60.0, np.interp(dist, dist_s, prof), prof[-1] - 0.012 * (dist - 60.0))

    # lagoon width: wide off the west beach as before, narrower around the rest of the island
    west = ss(-95.0, -45.0, X) * ss(200.0, 140.0, np.abs(Z))
    tips = ss(150.0, 205.0, np.abs(Z))
    Lc = 46.0 + 34.0 * west - 24.0 * tips
    Lc = Lc + 5.0 * vnoise(X, Z, 90.0, 11) + 3.2 * vnoise(X, Z, 23.0, 12) + 1.6 * vnoise(X, Z, 9.0, 13)
    # (the reef edge lies inside the heightmap everywhere)
    s = np.maximum(d - Lc, np.maximum(np.abs(Z), np.abs(X)) - 245.0)
    sand_waves = 0.28 * vnoise(X, Z, 34.0, 21) * ss(22.0, 38.0, d)
    lagoon = P(d) + sand_waves
    # the original shelf off the start beach stays as it is
    keep = ss(112.0, 98.0, np.abs(Z)) * (X > -20.0)
    # close to the shore the beach runs on as it is (but never down the first stage's cliff)
    near = np.maximum(h, lagoon)
    lag = near * (1.0 - ss(4.0, 14.0, d)) + lagoon * ss(4.0, 14.0, d)
    lag = np.minimum(lag, 0.0) * (1.0 - keep) + np.minimum(np.maximum(R0, lagoon), 0.0) * keep
    # coral heads: knolls on the lagoon floor that stay well under the surface
    rng = np.random.default_rng(77)
    heads = np.zeros_like(h)
    made = 0
    for t in range(4000):
        if made >= 150:
            break
        bx = rng.uniform(-245, 120); bz = rng.uniform(-245, 245)
        j = int((bz + EXT) / PX); i = int((bx + EXT) / PX)
        room = -lag[j, i] - 3.5
        if land[j, i] or d[j, i] < 26.0 or s[j, i] > -6.0 or room < 0.35:
            continue
        hh = min(rng.uniform(0.5, 1.5), room); rr = rng.uniform(1.6, 4.2)
        r0 = int(rr * 3 / PX)
        js = slice(max(j - r0, 0), min(j + r0, N)); is_ = slice(max(i - r0, 0), min(i + r0, N))
        dd = np.hypot(X[js, is_] - bx, Z[js, is_] - bz) / rr
        lump = np.exp(-dd ** 2.6) * (1.0 + 0.25 * vnoise(X[js, is_], Z[js, is_], 1.6, 800 + made))
        heads[js, is_] = np.maximum(heads[js, is_], hh * lump)
        made += 1
    info["coral_heads"] = made
    lag = lag + heads
    # the headland's granite goes on under water for a few meters
    head_sea = head_m * ss(16.0, 4.0, d)
    lag = np.minimum(lag + head_sea * (0.2 + 1.1 * bul), -0.12 - 0.5 * ss(2.0, 9.0, d))
    # the reef crest: where the reef faces the swell (west) it comes up to within a meter of the
    # surface just inside its edge, and the waves break on it. Passes cut through it.
    gz_d, gx_d = np.gradient(blur(d, 10), PX)
    expo = ss(0.25, 0.7, gx_d / (np.hypot(gx_d, gz_d) + 1e-6)) * ss(238.0, 215.0, np.abs(Z)) * ss(40.0, 56.0, blur(Lc, 16))
    pn = vnoise(X * 0.0 + 40.0, Z, 52.0, 61) + 0.35 * vnoise(X * 0.0 + 40.0, Z, 19.0, 62)
    passes = ss(-0.42, -0.2, pn) * (1.0 - ss(0.50, 0.62, pn))
    crest = expo * passes * np.exp(-((s + 8.0) / 5.0) ** 2)
    crest_top = -0.7 + 0.22 * vnoise(X, Z, 5.0, 63) + 0.12 * vnoise(X, Z, 1.7, 64)
    lag = lag + np.maximum(crest_top - lag, 0.0) * crest
    surf = expo * passes * np.exp(-((s + 6.5) / 8.0) ** 2)
    # fore-reef: rounded edge, then about 31 degrees down to the deep sand
    sp = np.maximum(s, 0.0)
    drop = 0.6 * (sp - 5.0 * (1.0 - np.exp(-sp / 5.0)))
    # spurs and grooves run down the upper slope
    groove = 0.8 * vnoise(X, Z, 7.0, 31) * ss(0.0, 6.0, sp) * ss(40.0, 14.0, sp)
    deep = 21.5 + 0.02 * sp
    tau = 2.0
    drop_eff = -tau * np.log(np.exp(-(drop + groove) / tau) + np.exp(-deep / tau))
    sea = lag - np.maximum(drop_eff, 0.0) * (s > 0.0)
    h = np.where(land, h, np.minimum(sea, 0.0))

    # ---- 3b. tide pools: hollows in the headland's granite between the tide marks (the tide
    # moves the sea between +0.3 and -0.8: scripts/tide.gd). They hold their water when the
    # sea has fallen below their rims. Only ground that lies above -0.45 is touched, and no
    # floor goes below -0.42: scripts/seabed.gd draws its random numbers by thresholds at -0.5
    # and -0.6, and a cell that crossed one would move every coral and urchin built after it.
    # And only cells that lie below 0 with nothing but such cells around them: landscape.gd
    # finds the shore where the ground (read between the cells) rises above 0, and places the
    # mangroves, and after them every boulder, from what it finds: one carved cell at the
    # water's edge moved them all (the first try). So the pools lie in the part of the
    # platform that high water covers.
    low = h.copy()
    for dj in range(-2, 3):
        for di in range(-2, 3):
            low = np.maximum(low, np.roll(np.roll(h, dj, 0), di, 1))
    safe = low < 0.0
    prng = np.random.default_rng(88)
    made_pools = []
    cand = np.argwhere((head_m > 0.6) & (h > -0.26) & (h < -0.02) & safe)
    prng.shuffle(cand)
    W = 14                                            # cells: 3.5 m
    for (j, i) in cand:
        if len(made_pools) >= 7:
            break
        x0 = X[j, i]; z0 = Z[j, i]
        # (not on the lines the boulder groups are placed from: landscape.gd, _shore_scan())
        if min(abs(z0 + 14.0), abs(z0 + 60.0), abs(z0 - 55.0)) < 3.0:
            continue
        if any(np.hypot(x0 - q[0], z0 - q[1]) < 6.5 for q in made_pools):
            continue
        rad = prng.uniform(1.1, 1.9)
        squash = prng.uniform(0.75, 1.3)
        depth = prng.uniform(0.3, 0.44)
        win = (slice(j - W, j + W + 1), slice(i - W, i + W + 1))
        hw = h[win]
        rr = np.hypot(X[win] - x0, Z[win] - z0)
        ring = hw[(rr > rad * 1.0) & (rr < rad * 1.45)]
        # level rock all around: a rim that would hold water
        if ring.size == 0 or ring.min() < h[j, i] - 0.07 or ring.min() < -0.3 or ring.max() > h[j, i] + 0.4:
            continue
        if not safe[win][rr < rad * 0.8].all():
            continue
        ell = np.hypot((X[win] - x0) / (rad * squash), (Z[win] - z0) / rad) + 0.2 * (vnoise(X[win], Z[win], 1.3, 90) - 0.5)
        bowl = ss(1.0, 0.35, ell)
        floor_ = max(ring.min() - depth, -0.42)
        h[win] = np.where((bowl > 0.0) & safe[win], np.minimum(hw, hw * (1.0 - bowl) + floor_ * bowl), hw)
        made_pools.append((float(x0), float(z0), float(rad)))
    # what stands in each (and in the two hollows the granite had already): the level its rim
    # spills at, found by letting water in from all around
    import heapq
    pools_out = []
    for (x0, z0, rad) in made_pools + [(-187.7, -10.4, 1.5), (-187.2, -20.1, 1.2)]:
        j = int(round((z0 + EXT) / PX - 0.5)); i = int(round((x0 + EXT) / PX - 0.5))
        Wf = 26
        sub = h[j - Wf:j + Wf + 1, i - Wf:i + Wf + 1].astype(np.float64)
        fill = np.full(sub.shape, np.inf); seen = np.zeros(sub.shape, bool); heap = []
        for a in range(sub.shape[0]):
            for b in range(sub.shape[1]):
                if a in (0, sub.shape[0] - 1) or b in (0, sub.shape[1] - 1):
                    fill[a, b] = sub[a, b]; seen[a, b] = True; heap.append((sub[a, b], a, b))
        heapq.heapify(heap)
        while heap:
            lvl, a, b = heapq.heappop(heap)
            for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                aa = a + da; bb = b + db
                if 0 <= aa < sub.shape[0] and 0 <= bb < sub.shape[1] and not seen[aa, bb]:
                    seen[aa, bb] = True; fill[aa, bb] = max(lvl, sub[aa, bb]); heapq.heappush(heap, (fill[aa, bb], aa, bb))
        water = fill - sub
        # the pool at the middle: the wet cells joined to the deepest cell near it
        mid = water[Wf - 6:Wf + 7, Wf - 6:Wf + 7]
        if mid.max() < 0.1:
            continue
        a0, b0 = np.unravel_index(np.argmax(mid), mid.shape); a0 += Wf - 6; b0 += Wf - 6
        level = float(fill[a0, b0])
        wet = np.zeros(sub.shape, bool); stack = [(a0, b0)]; wet[a0, b0] = True
        while stack:
            a, b = stack.pop()
            for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                aa = a + da; bb = b + db
                if 0 <= aa < sub.shape[0] and 0 <= bb < sub.shape[1] and not wet[aa, bb] and water[aa, bb] > 0.015 and abs(fill[aa, bb] - level) < 0.005:
                    wet[aa, bb] = True; stack.append((aa, bb))
        ys_, xs_ = np.where(wet)
        if len(ys_) * PX * PX < 0.8 or level > 0.25:
            continue
        cx = (xs_.mean() + i - Wf + 0.5) * PX - EXT; cz = (ys_.mean() + j - Wf + 0.5) * PX - EXT
        pools_out.append({"x": round(float(cx), 2), "z": round(float(cz), 2), "level": round(level, 3), "depth": round(float(water[wet].max()), 3),
                          "rx": round(float((xs_.max() - xs_.min() + 1) * PX * 0.5), 2), "rz": round(float((ys_.max() - ys_.min() + 1) * PX * 0.5), 2),
                          "area": round(float(len(ys_) * PX * PX), 1)})
    info["tide_pools"] = pools_out

    # ---- 4. heightmap channels
    Rn = h.astype(np.float32)
    Gn = (Rn + rocks0).astype(np.float32)

    # ---- 5. land cover
    nrng = np.random.default_rng(5)                 # (the first stage's noise, reproduced)
    nz = np.zeros_like(X)
    for k in range(14):
        ang = nrng.uniform(0, np.pi); fr = 0.03 * (1.45 ** (k % 7)) * nrng.uniform(0.8, 1.2)
        nz += np.sin((X * np.cos(ang) + (-Z) * np.sin(ang)) * fr + nrng.uniform(0, 6.28)) / (1.0 + (k % 7))
    nz /= 2.6
    # the top of the beach: not at one height all around the island (beaches of varying width)
    beach = (0.15 + 0.8 * vnoise(X, Z, 60.0, 41)) * (1.0 - orig)
    forest = ss(1.35, 1.95, Rn + nz * 0.35 + beach) * ss(-0.2, 1.6, cave_in)     # (bare sand inside the grotto)
    summit = ss(13.0, 22.0, Rn + nz * 2.0) * ss(70.0, 40.0, np.hypot(X - PEAK[0], Z - PEAK[1]))
    corridor = ss(7.5, 4.0, pd + nz * 3.0) * ss(2.5, 6.0, Rn)
    summit = np.maximum(summit, corridor)
    # under water the green channel marks hard reef: the coral heads, the reef edge and its slope
    reef = np.maximum(ss(0.12, 0.5, heads), ss(-9.0, -1.0, s) * ss(34.0, 6.0, s) * ss(-0.35, 0.25, vnoise(X, Z, 5.0, 51) + 0.6 * vnoise(X, Z, 17.0, 52)))
    reef = np.maximum(reef, ss(0.25, 0.6, crest))
    wet_rock = ss(0.2, 0.6, head_sea)                # granite below the waterline (not coral)
    green = np.where(land, rock * ss(-0.2, 1.2, cave_in), np.maximum(reef * ss(-1.5, -3.0, Rn) * (1.0 - wet_rock), np.maximum(wet_rock, ss(0.25, 0.6, crest))))
    forest = forest * (1.0 - stream["sandbar"])
    mask = np.zeros((N, N, 4), np.float32)
    mask[..., 0] = forest; mask[..., 1] = green; mask[..., 2] = np.where(land, summit, wet_rock)
    mask[..., 3] = 1.0 - stream["water"]            # (alpha: 1 = no stream; stored inverted so an old mask reads as dry)
    info["stream"] = stream["json"]
    info["rock_m2"] = float(((rock > 0.5) & land).sum() * PX * PX)
    info["land_m2"] = float(land.sum() * PX * PX)
    info["peak"] = float(Rn.max())
    return Rn, Gn, mask, info, {"d": d, "s": s, "still": still, "rock": rock, "slope": slope, "cave": cs, "surf": surf.astype(np.float32)}


# ------------------------------------------------------------------ output
def write_exr(path, R, G, B):
    """Uncompressed 32-bit float OpenEXR with channels B (surf on the reef crest), G, R."""
    def attr(name, typ, data):
        return name.encode() + b"\0" + typ.encode() + b"\0" + struct.pack("<i", len(data)) + data
    chl = b""
    for ch in ("B", "G", "R"):
        chl += ch.encode() + b"\0" + struct.pack("<iBBBBii", 2, 0, 0, 0, 0, 1, 1)
    chl += b"\0"
    box = struct.pack("<iiii", 0, 0, N - 1, N - 1)
    head = struct.pack("<ii", 20000630, 2)
    head += attr("channels", "chlist", chl) + attr("compression", "compression", b"\0")
    head += attr("dataWindow", "box2i", box) + attr("displayWindow", "box2i", box)
    head += attr("lineOrder", "lineOrder", b"\0") + attr("pixelAspectRatio", "float", struct.pack("<f", 1.0))
    head += attr("screenWindowCenter", "v2f", struct.pack("<ff", 0, 0)) + attr("screenWindowWidth", "float", struct.pack("<f", 1.0))
    head += b"\0"
    line = 8 + 3 * 4 * N
    start = len(head) + 8 * N
    offs = struct.pack("<%dQ" % N, *[start + j * line for j in range(N)])
    with open(path, "wb") as f:
        f.write(head); f.write(offs)
        for j in range(N):
            f.write(struct.pack("<ii", j, 3 * 4 * N))
            f.write(B[j].astype("<f4").tobytes()); f.write(G[j].astype("<f4").tobytes()); f.write(R[j].astype("<f4").tobytes())


def axis(segs):
    out = []
    for a, b, st in segs:
        n = int(round((b - a) / st)); out.append(np.linspace(a, b, n + 1)[:-1])
    out.append([segs[-1][1]]); return np.concatenate(out)


def write_mesh(path, R):
    xs = axis([(-322, -258, 4.0), (-258, -200, 1.2), (-200, -150, 0.75), (-150, 60, 0.5),
               (60, 112, 1.0), (112, 190, 2.0), (190, 258, 4.0), (258, 322, 8.0)])
    zs = axis([(-322, -258, 4.0), (-258, -215, 1.2), (-215, -135, 1.0), (-135, 110, 0.5), (110, 215, 1.0),
               (215, 258, 1.2), (258, 322, 4.0)])
    XX, ZZ = np.meshgrid(xs, zs)
    H = outside(bilinear(R, XX, ZZ), XX, ZZ)
    nx, nz_ = len(xs), len(zs)
    # normals from the surface itself
    dhx = np.gradient(H, xs, axis=1); dhz = np.gradient(H, zs, axis=0)
    nrm = np.stack([-dhx, np.ones_like(H), -dhz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    pos = np.stack([XX, H, ZZ], -1).reshape(-1, 3).astype("<f4")
    nrm = nrm.reshape(-1, 3).astype("<f4")
    ix = np.arange(nx - 1); iz = np.arange(nz_ - 1)
    a = (iz[:, None] * nx + ix[None, :]).ravel()
    b = a + 1; c2 = a + nx; d2 = c2 + 1
    idx = np.stack([a, c2, b, b, c2, d2], 1).ravel().astype("<u4")     # counter-clockwise seen from above
    blob = pos.tobytes() + nrm.tobytes() + idx.tobytes()
    gltf = {
        "asset": {"version": "2.0", "generator": "terrain2.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "TerrainExt", "mesh": 0}],
        "materials": [{"name": "Sand"}],
        "meshes": [{"name": "TerrainExt", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0}]}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": pos.nbytes, "target": 34962},
            {"buffer": 0, "byteOffset": pos.nbytes, "byteLength": nrm.nbytes, "target": 34962},
            {"buffer": 0, "byteOffset": pos.nbytes + nrm.nbytes, "byteLength": idx.nbytes, "target": 34963}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": [float(v) for v in pos.min(0)], "max": [float(v) for v in pos.max(0)]},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5125, "count": len(idx), "type": "SCALAR"}],
    }
    js = json.dumps(gltf).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    blob += b"\0" * ((4 - len(blob) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)
    return len(pos)


def preview(R, mask, extra):
    os.makedirs(PREVIEW, exist_ok=True)
    gz, gx = np.gradient(R, PX)
    L = np.array([-0.5, -0.35, 0.79]); L /= np.linalg.norm(L)
    n = np.dstack([-gx, -gz, np.ones_like(R)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
    sh = np.clip((n * L).sum(2), 0, 1)[..., None]
    land = R > 0
    sand = np.array([0.93, 0.89, 0.78]); forest = np.array([0.2, 0.42, 0.16]); grass = np.array([0.62, 0.66, 0.3]); rk = np.array([0.6, 0.58, 0.56])
    col = sand * (1 - mask[..., :1]) + forest * mask[..., :1]
    col = col * (1 - mask[..., 2:3]) + grass * mask[..., 2:3]
    col = col * (1 - mask[..., 1:2]) + rk * mask[..., 1:2]
    img = col * (0.35 + 0.65 * sh)
    dep = np.clip(-R / 24.0, 0, 1)[..., None] ** 0.6
    seac = (1 - dep) * np.array([0.45, 0.9, 0.85]) + dep * np.array([0.02, 0.12, 0.35])
    seac = seac * (1 - 0.55 * mask[..., 1:2])
    seac = seac + extra["surf"][..., None] * 0.6
    col = col * mask[..., 3:4] + np.array([0.1, 0.3, 0.9]) * (1 - mask[..., 3:4])
    img = np.where(land[..., None], img, seac * (0.7 + 0.3 * sh))
    for lev in (-20, -10, -5, -3, 0, 5, 10, 20, 30, 40):
        m = np.abs(R - lev) < (0.05 if abs(lev) < 4 else 0.12)
        img[m] = (1, 0.2, 0.2) if lev == 0 else img[m] * 0.55
    big = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(big).resize((1024, 1024), Image.LANCZOS).save(PREVIEW + "map.png")
    Image.fromarray(big[500:1300, 300:1100]).save(PREVIEW + "hill.png")       # x -181..19, z -131..69
    Image.fromarray(big[760:1160, 160:460]).resize((600, 800)).save(PREVIEW + "head.png")


if __name__ == "__main__":
    R, G, mask, info, extra = build()
    preview(R, mask, extra)
    np.save(PREVIEW + "R.npy", R)
    np.save(PREVIEW + "cave.npy", extra["cave"])
    if "--write" in sys.argv:
        write_exr(TEX + "heightmap.exr", R, G, extra["surf"])
        Image.fromarray((np.clip(mask, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(TEX + "landmask.png")
        info["mesh_vertices"] = write_mesh(MOD + "terrain_ext.glb", R)
        p = MOD + "island.json"
        data = json.load(open(p))
        data["peak_height"] = float(bilinear(R, np.array([PEAK[0]]), np.array([PEAK[1]]))[0])
        data["taper"] = {"south": list(TAPER_S), "north": list(TAPER_N), "r": TAPER_R}
        data["stream"] = info["stream"]
        data["tide_pools"] = info["tide_pools"]
        json.dump(data, open(p, "w"), indent=1)
        info["written"] = True
    info["stream"] = {"pools": info["stream"]["pools"], "pond": info["stream"]["pond"], "course_points": len(info["stream"]["course"])}
    print(json.dumps(info, indent=1))
