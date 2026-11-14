#!/usr/bin/env python3
"""The grotto: a pile of granite boulders around the space laid out in terrain2.py (CAVE_PATH).
Needs only numpy; run after terrain2.py (it reads tools/terrain_preview/R.npy and cave.npy):

    python3 tools/grotto2.py            # report only
    python3 tools/grotto2.py --write    # writes assets/models/grotto.glb and grotto.json

Caves on the granite islands of the Seychelles are not hollows in the rock: they are the gaps
under and between huge boulders that lean on one another. So nothing is carved here. The space
(two rooms, the passages, both mouths) is a union of half-ellipsoids along the path; boulders
are then set against its outside, capstones first, until every point just behind its wall lies
inside some boulder: no daylight comes in except through the two mouths and the two gaps left
open in the roof on purpose. No boulder reaches into the space a person needs to walk through.
There are no stalactites: dripstone does not form in granite.

Everything is in world coordinates (Godot: x west, y up, z north).
"""
import json, os, struct, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import terrain2 as T

rng = np.random.default_rng(2026)
R = np.load(T.PREVIEW + "R.npy")
CS = np.load(T.PREVIEW + "cave.npy")          # x, z, floor, half-width, height, arc length
L = CS[-1, 5]
ROOF_FROM, ROOF_TO = T.CAVE_OPEN[0], L - T.CAVE_OPEN[1]   # the stretch of the path that lies under the boulders
SUN = np.array([-0.505, 0.788, -0.353]); SUN /= np.linalg.norm(SUN)   # world.gd: SUN_TO (midday)


def ground(x, z):
    return T.bilinear(R, np.asarray(x, float), np.asarray(z, float))


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


# ------------------------------------------------------------------ the space
EC = np.stack([CS[:, 0], CS[:, 2], CS[:, 1]], 1)     # centers of the half-ellipsoids (on the floor)
EW = CS[:, 3]; EH = CS[:, 4]; ES = CS[:, 5]
roofed = (ES >= ROOF_FROM) & (ES <= ROOF_TO)


def void_metric(p):
    """For points p (M, 3): smallest ellipsoid metric over the space (< 1 = inside it)."""
    d = p[:, None, :] - EC[None, :, :]
    m = (d[..., 0] ** 2 + d[..., 2] ** 2) / EW[None, :] ** 2 + (d[..., 1] / EH[None, :]) ** 2
    return m.min(1)


def fib_hemisphere(n):
    i = np.arange(n) + 0.5
    y = i / n
    r = np.sqrt(1 - y * y)
    a = i * 2.399963
    return np.stack([r * np.cos(a), y, r * np.sin(a)], 1)


def chamber(k):
    """Index of the path sample in the middle of room k (0 front, 1 inner)."""
    wide = np.where(EW > 3.5)[0]
    split = np.where(np.diff(wide) > 1)[0][0] + 1
    part = wide[:split] if k == 0 else wide[split:]
    return int(part[len(part) // 2])


C1, C2 = chamber(0), chamber(1)
# gaps left open in the roof: a point on the floor the light falls on, the direction up, radius
side2 = np.array([0.35, 0.0, 0.94])
SKY = [
    {"floor": EC[C2] + np.array([1.2, 0.0, -0.4]), "dir": SUN, "r": 0.95},
    {"floor": EC[C1] + np.array([-0.6, 0.0, 1.2]), "dir": unit(np.array([0.16, 0.95, 0.2])), "r": 0.5},
]


def shaft_dist(p, sk):
    """Distance of points from the axis of a roof gap, and their height along it."""
    d = p - sk["floor"]
    t = d @ sk["dir"]
    return np.linalg.norm(d - t[:, None] * sk["dir"], axis=1), t


def build_space():
    dirs = fib_hemisphere(90)
    pts, nrm, own = [], [], []
    for k in np.where(roofed)[0]:
        p = EC[k] + dirs * np.array([EW[k], EH[k], EW[k]])
        n = unit(dirs / np.array([EW[k], EH[k], EW[k]]))
        pts.append(p); nrm.append(n); own.append(np.full(len(p), k))
    pts = np.concatenate(pts); nrm = np.concatenate(nrm); own = np.concatenate(own)
    keep = void_metric(pts) > 0.995                   # on the outside of the union
    for sk in SKY:
        dist, t = shaft_dist(pts, sk)
        keep &= ~((dist < sk["r"] * 1.15) & (t > 0.5))
    pts, nrm, own = pts[keep], nrm[keep], own[keep]
    # just behind the wall: these points must end up inside rock (or in the ground)
    delta = np.clip(0.24 * EW[own], 0.7, 1.15)
    seal = pts + nrm * delta[:, None]
    ok = void_metric(seal) > 1.0
    pts, nrm, own, seal = pts[ok], nrm[ok], own[ok], seal[ok]
    return pts, nrm, own, seal


def clear_points():
    """Points that must stay free of rock: the inside of the space, the way through it, the gaps."""
    out = []
    dirs = fib_hemisphere(40)
    for k in range(len(EC)):
        out.append(EC[k] + dirs * np.array([EW[k], EH[k], EW[k]]) * 0.8)
        for v in np.arange(0.25, 2.1, 0.3):
            for lat in (-0.6, 0.0, 0.6):
                tang = EC[min(k + 1, len(EC) - 1)] - EC[max(k - 1, 0)]
                sd = unit(np.array([-tang[2], 0.0, tang[0]]))
                out.append((EC[k] + sd * lat + np.array([0, v, 0]))[None])
    for sk in SKY:
        a = unit(np.cross(sk["dir"], np.array([1.0, 0.0, 0.0]))); b = np.cross(sk["dir"], a)
        for t in np.arange(1.0, 16.0, 0.4):
            c = sk["floor"] + sk["dir"] * t
            out.append(c[None])
            for an in np.arange(0, 6.28, 1.05):
                out.append((c + (a * np.cos(an) + b * np.sin(an)) * sk["r"] * 0.9)[None])
    # the way up to both mouths, from 7 m out: nothing may lie in the doorway
    for end, k0, k1 in ((0, 0, 3), (1, len(EC) - 1, len(EC) - 4)):
        out_dir = unit((EC[k0] - EC[k1]) * np.array([1.0, 0.0, 1.0]))
        sd = np.array([-out_dir[2], 0.0, out_dir[0]])
        km = int(np.argmin(np.abs(ES - (ROOF_FROM if end == 0 else ROOF_TO))))
        length = np.linalg.norm((EC[k0] - EC[km])[[0, 2]]) + 7.0
        for t in np.arange(0.0, length, 0.4):
            base = EC[km] + out_dir * t
            gy = float(ground(base[0], base[2]))
            for v in np.arange(0.3, 2.7, 0.4):
                for lat in (-1.3, 0.0, 1.3):
                    out.append(np.array([[base[0] + sd[0] * lat, gy + v, base[2] + sd[2] * lat]]))
    return np.concatenate(out)


# ------------------------------------------------------------------ boulders
def rot_matrix(yaw, tilt, tilt_dir):
    cy, sy = np.cos(yaw), np.sin(yaw)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    ax = np.array([np.cos(tilt_dir), 0.0, np.sin(tilt_dir)])
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    Rt = np.eye(3) + np.sin(tilt) * K + (1 - np.cos(tilt)) * (K @ K)
    return Rt @ Ry


def local(p, b):
    return ((p - b["c"]) @ b["R"]) / b["r"]


def inside(p, b, scale=1.0):
    """Within the boulder's full ellipsoid (the most it can occupy): for keeping spaces clear."""
    return (local(p, b) ** 2).sum(1) < scale * scale


_count = [0]


def boulder(c, r, Rm, **kw):
    """A boulder: center, radii, rotation, and the joint planes it has split along (weathered
    granite breaks off along flat faces): [(unit normal, distance)] in its unit-sphere space."""
    _count[0] += 1
    g = np.random.default_rng(5000 + _count[0])
    cuts = [(unit(g.normal(size=3)), g.uniform(0.7, 0.92)) for _ in range(g.integers(0, 3))]
    b = {"c": np.asarray(c, float), "r": np.asarray(r, float), "R": Rm, "seed": _count[0], "cuts": cuts}
    b.update(kw)
    return b


def solid(p, b, s=0.8):
    """Certainly inside the rock of the boulder (the least it occupies, split faces and surface
    relief taken off): for what it hides and what it keeps out."""
    x = local(p, b)
    ok = (x ** 2).sum(1) < s * s
    for m, d0 in b["cuts"]:
        ok &= x @ m < s * d0
    return ok


def ray_block(o, d, b, s=0.84):
    """Which of the rays (origins o, directions d) pass through the rock of boulder b?"""
    oo = ((o - b["c"]) @ b["R"]) / b["r"]; dd = (d @ b["R"]) / b["r"]
    a = (dd * dd).sum(1); bb = 2 * (oo * dd).sum(1); cc = (oo * oo).sum(1) - s * s
    disc = bb * bb - 4 * a * cc
    hit = disc > 0
    sq = np.sqrt(np.maximum(disc, 0))
    t0 = (-bb - sq) / (2 * a); t1 = (-bb + sq) / (2 * a)
    for m, d0 in b["cuts"]:
        num = s * d0 - oo @ m; den = dd @ m
        with np.errstate(divide="ignore", invalid="ignore"):
            tc = num / den
        t1 = np.where(den > 1e-9, np.minimum(t1, tc), t1)
        t0 = np.where(den < -1e-9, np.maximum(t0, tc), t0)
        hit &= ~((np.abs(den) <= 1e-9) & (num < 0))
    return hit & (t1 > np.maximum(t0, 0.0))


def place(space, clear):
    pts, nrm, own, seal = space
    covered = seal[:, 1] < ground(seal[:, 0], seal[:, 2]) - 0.15       # earth behind the wall
    boulders = []
    order = np.argsort(-(seal[:, 1] + rng.uniform(0, 1.5, len(seal))))
    failed = 0
    for small in (False, True):
        for idx in order:
            if covered[idx]:
                continue
            n = nrm[idx]
            roof = n[1] > 0.55
            done = False
            for attempt in range(7):
                sc = 0.86 ** attempt
                if small:
                    r = rng.uniform(0.9, 1.7, 3) * sc
                    Rm = rot_matrix(rng.uniform(0, 6.28), rng.uniform(0, 0.6), rng.uniform(0, 6.28))
                elif roof:
                    r = np.array([rng.uniform(3.2, 6.0), rng.uniform(1.6, 2.7), rng.uniform(2.6, 4.6)]) * sc
                    Rm = rot_matrix(rng.uniform(0, 6.28), rng.uniform(0, 0.28), rng.uniform(0, 6.28))
                else:
                    r = np.array([rng.uniform(1.9, 3.9), rng.uniform(1.7, 3.0), rng.uniform(1.6, 3.1)]) * sc
                    r[1] = min(r[1], 1.05 * min(r[0], r[2]))     # (no standing pillars)
                    Rm = rot_matrix(rng.uniform(0, 6.28), rng.uniform(0, 0.5), rng.uniform(0, 6.28))
                ext = np.sqrt(((r * (Rm.T @ n)) ** 2).sum())
                if small:
                    c = seal[idx] + n * ext * rng.uniform(0.1, 0.4)
                else:
                    c = pts[idx] + n * ext * rng.uniform(0.94, 1.0)
                b = boulder(c, r, Rm)
                if inside(clear, b, 1.12).any():
                    continue
                boulders.append(b)
                covered |= solid(seal, b, 0.86)
                done = True
                break
            if not done:
                failed += 1
    return boulders, int((~covered).sum()), failed


def scatter(boulders, clear):
    """More boulders around the outside of the pile, so that it is not one neat mound."""
    n0 = len(boulders)
    tries = 0
    while len(boulders) < n0 + 26 and tries < 600:
        tries += 1
        k = rng.integers(0, len(EC))
        a = rng.uniform(0, 6.28)
        dist = EW[k] + rng.uniform(2.5, 9.0)
        x = EC[k, 0] + np.cos(a) * dist; z = EC[k, 2] + np.sin(a) * dist
        r = np.array([rng.uniform(0.8, 3.4), rng.uniform(0.7, 2.6), rng.uniform(0.8, 3.0)])
        r[1] = min(r[1], 0.85 * min(r[0], r[2]))
        if rng.random() < 0.4:
            r *= 0.45
        g = float(ground(x, z))
        # resting on the ground, or on top of the pile
        top = g
        for b in boulders:
            dd = np.hypot(x - b["c"][0], z - b["c"][2])
            if dd < b["r"].max() * 0.6:
                top = max(top, b["c"][1] + b["r"][1] * 0.7)
        c = np.array([x, top + r[1] * rng.uniform(0.25, 0.6), z])
        b = boulder(c, r, rot_matrix(rng.uniform(0, 6.28), rng.uniform(0, 0.3), rng.uniform(0, 6.28)))
        if inside(clear, b, 1.15).any():
            continue
        boulders.append(b)
    return boulders


def floor_rocks(boulders, clear):
    """Small rocks lying at the foot of the walls inside the two rooms."""
    for k0 in (C1, C2):
        for i in range(9):
            k = int(np.clip(k0 + rng.integers(-7, 8), 0, len(EC) - 1))
            a = rng.uniform(0, 6.28)
            d = EW[k] * rng.uniform(0.62, 0.9)
            x = EC[k, 0] + np.cos(a) * d; z = EC[k, 2] + np.sin(a) * d
            r = rng.uniform(0.22, 0.6) * np.array([1.0, rng.uniform(0.55, 0.9), rng.uniform(0.7, 1.1)])
            c = np.array([x, float(ground(x, z)) + r[1] * 0.45, z])
            b = boulder(c, r, rot_matrix(rng.uniform(0, 6.28), rng.uniform(0, 0.3), rng.uniform(0, 6.28)), small=True)
            # (keep the way through and the patch of sunlight clear)
            walk = np.array([[EC[j, 0], c[1], EC[j, 2]] for j in range(len(EC))])
            if np.hypot(walk[:, 0] - x, walk[:, 2] - z).min() < 1.3 + r.max():
                continue
            boulders.append(b)
    return boulders


# ------------------------------------------------------------------ light-tightness
def sphere_dirs(n, y_min):
    i = np.arange(n) + 0.5
    y = 1 - 2 * i / n
    r = np.sqrt(1 - y * y)
    a = i * 2.399963
    d = np.stack([r * np.cos(a), y, r * np.sin(a)], 1)
    return d[d[:, 1] > y_min]


def cave_rays():
    """Rays from inside the grotto in every direction the sun or the moon can stand in, except
    those that leave through one of the two mouths or one of the gaps in the roof."""
    ks = np.where((ES > ROOF_FROM + 2.5) & (ES < ROOF_TO - 2.5))[0][::6]
    orig = []
    for k in ks:
        tang = EC[min(k + 2, len(EC) - 1)] - EC[max(k - 2, 0)]
        sd = unit(np.array([-tang[2], 0.0, tang[0]]))
        for hf in (0.2, 0.55):
            for lat in (-0.5, 0.0, 0.5):
                orig.append(EC[k] + sd * lat * EW[k] + np.array([0.0, EH[k] * hf, 0.0]))
    orig = np.array(orig)
    dirs = sphere_dirs(700, 0.0)
    O = np.repeat(orig, len(dirs), 0); D = np.tile(dirs, (len(orig), 1))
    allowed = np.zeros(len(O), bool)
    for sk in SKY:       # through a roof gap: passes close to its axis above head height
        w = O - sk["floor"]
        b_ = (D * sk["dir"]).sum(1); d_ = (D * w).sum(1); e_ = w @ sk["dir"]
        den = np.maximum(1.0 - b_ * b_, 1e-6)
        tr = (b_ * e_ - d_) / den; ts = (e_ - b_ * d_) / den
        gap = np.linalg.norm(w + D * tr[:, None] - sk["dir"] * ts[:, None], axis=1)
        allowed |= (gap < sk["r"] * 1.3) & (ts > 2.0) & (tr > 0.0)
        allowed |= (b_ > 0.995)
    for s_m in (ROOF_FROM, ROOF_TO):    # out through a mouth
        k = int(np.argmin(np.abs(ES - s_m)))
        m_c = EC[k] + np.array([0.0, EH[k] * 0.45, 0.0])
        w = m_c - O
        tr = np.maximum((w * D).sum(1), 0.0)
        allowed |= np.linalg.norm(w - D * tr[:, None], axis=1) < EW[k] + 0.9
    O = O[~allowed]; D = D[~allowed]
    # into the hillside
    free = np.ones(len(O), bool)
    for t in np.arange(0.6, 60.0, 0.6):
        p = O + D * t
        free &= p[:, 1] > ground(p[:, 0], p[:, 2]) + 0.05
    return O[free], D[free]


def seal(boulders, clear, max_plugs=140):
    """Sets a boulder into every remaining chink the sun could shine through."""
    O, D = cave_rays()
    open_ = np.ones(len(O), bool)
    for b in boulders:
        open_ &= ~ray_block(O, D, b)
    before = int(open_.sum())
    plugs = 0
    stuck = 0
    while open_.any() and plugs < max_plugs and stuck < 60:
        i = rng.choice(np.where(open_)[0])
        # where this ray leaves the space
        ts = np.arange(0.0, 16.0, 0.2)
        vm = void_metric(O[i] + D[i] * ts[:, None])
        out = np.where(vm > 1.0)[0]
        t_exit = ts[out[0]] if len(out) else 6.0
        placed = False
        for attempt in range(8):
            r = np.array([rng.uniform(1.3, 2.4), rng.uniform(1.0, 1.9), rng.uniform(1.2, 2.2)]) * (0.9 ** attempt)
            Rm = rot_matrix(rng.uniform(0, 6.28), rng.uniform(0, 0.35), rng.uniform(0, 6.28))
            ext = np.sqrt(((r * (Rm.T @ D[i])) ** 2).sum())
            b = boulder(O[i] + D[i] * (t_exit + ext * rng.uniform(0.95, 1.25) + 0.15 * attempt), r, Rm)
            if inside(clear, b, 1.12).any() or not ray_block(O[i:i + 1], D[i:i + 1], b)[0]:
                continue
            boulders.append(b)
            open_ &= ~ray_block(O, D, b)
            plugs += 1
            placed = True
            break
        if not placed:
            stuck += 1
            open_[i] = False
    remaining = np.ones(len(O), bool)
    for b in boulders:
        remaining &= ~ray_block(O, D, b)
    return {"rays_tested": int(len(O)), "open_before": before, "plugs": plugs, "open_after": int(remaining.sum())}


# ------------------------------------------------------------------ meshes
def icosphere(sub):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
         (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    v = [np.array(p, float) / np.linalg.norm(p) for p in v]
    for _ in range(sub):
        cache = {}; nf = []

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                m = v[a] + v[b]; v.append(m / np.linalg.norm(m)); cache[key] = len(v) - 1
            return cache[key]
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(v), np.array(f, np.int64)


ICO = {s: icosphere(s) for s in (2, 3, 4)}
LAT = np.random.default_rng(9).uniform(-1, 1, (32, 32, 32))


def noise3(p):
    q = p % 32
    i = np.floor(q).astype(int); f = q - i
    f = f * f * (3 - 2 * f)
    i1 = (i + 1) % 32
    def g(a, b, c):
        return LAT[a[:, 0], b[:, 1], c[:, 2]]
    x00 = g(i, i, i) * (1 - f[:, 0]) + g(i1, i, i) * f[:, 0]
    x10 = g(i, i1, i) * (1 - f[:, 0]) + g(i1, i1, i) * f[:, 0]
    x01 = g(i, i, i1) * (1 - f[:, 0]) + g(i1, i, i1) * f[:, 0]
    x11 = g(i, i1, i1) * (1 - f[:, 0]) + g(i1, i1, i1) * f[:, 0]
    return (x00 * (1 - f[:, 1]) + x10 * f[:, 1]) * (1 - f[:, 2]) + (x01 * (1 - f[:, 1]) + x11 * f[:, 1]) * f[:, 2]


def boulder_mesh(b):
    r = np.random.default_rng(1000 + b["seed"])
    big = b["r"].max()
    V, F = ICO[4 if big > 2.4 else (3 if big > 0.8 else 2)]
    V = V.copy()
    for m, d0 in b["cuts"]:           # the flat faces it has split along
        t = np.maximum(V @ m - d0, 0.0)
        V -= np.outer(t * 0.9, m)
    off = r.uniform(0, 30, 3)
    disp = 1.0 + 0.11 * noise3(V * 1.25 + off) + 0.045 * noise3(V * 3.1 + off + 7.0)
    # the furrows rain water cuts down the flanks of the big ones
    if big > 1.6:
        az = np.arctan2(V[:, 2], V[:, 0])
        fl = (0.5 + 0.5 * np.sin(az * r.integers(7, 15) + 3.0 * noise3(V * 1.4 + off + 3.0))) ** 3
        disp -= fl * r.uniform(0.012, 0.04) * np.clip(1.0 - np.abs(V[:, 1]) * 1.1, 0, 1)
    V *= disp[:, None]
    W = (V * b["r"]) @ b["R"].T + b["c"]
    return W, F


def normals(W, F):
    fn = np.cross(W[F[:, 1]] - W[F[:, 0]], W[F[:, 2]] - W[F[:, 0]])
    n = np.zeros_like(W)
    for k in range(3):
        np.add.at(n, F[:, k], fn)
    return unit(n)


def assemble(boulders):
    pos, nrm, idx, owner = [], [], [], []
    base = 0
    hidden_tris = 0
    for i, b in enumerate(boulders):
        W, F = boulder_mesh(b)
        N = normals(W, F)
        # leave out what can never be seen: faces deep inside a neighbor or well under the ground
        hid = W[:, 1] < ground(W[:, 0], W[:, 2]) - 0.5
        reach = b["r"].max()
        for j, o in enumerate(boulders):
            if j == i or np.linalg.norm(o["c"] - b["c"]) > reach + o["r"].max():
                continue
            hid |= solid(W, o, 0.8)
        keep = ~(hid[F[:, 0]] & hid[F[:, 1]] & hid[F[:, 2]])
        hidden_tris += int((~keep).sum())
        # (and the vertices only those faces used)
        Fk = F[keep]
        used = np.zeros(len(W), bool); used[Fk.ravel()] = True
        remap = np.cumsum(used) - 1
        pos.append(W[used]); nrm.append(N[used]); idx.append(remap[Fk] + base); owner.append(np.full(int(used.sum()), i))
        base += int(used.sum())
    return np.concatenate(pos), np.concatenate(nrm), np.concatenate(idx), hidden_tris, np.concatenate(owner)


def check_clear(pos):
    """Vertices that reach into the space a walker needs (should be none)."""
    d = pos[:, None, :] - EC[None, :, :]
    dh = np.hypot(d[..., 0], d[..., 2]); v = d[..., 1]
    return ((dh < 0.5) & (v > 0.12) & (v < 1.95)).any(1)


def tube(path, radii, pos, nrm, idx, sides=6):
    """Adds a tube along `path` (points) with the given radius at each point."""
    P = np.asarray(path, float); n = len(P)
    tan = unit(np.gradient(P, axis=0))
    ref = np.array([0.0, 1.0, 0.0]) if abs(tan[0][1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = unit(np.cross(tan[0], ref))
    base = len(pos)
    for i in range(n):
        u = unit(u - tan[i] * np.dot(u, tan[i]))
        v = np.cross(tan[i], u)
        for k in range(sides):
            ang = k * 6.28318 / sides
            d = u * np.cos(ang) + v * np.sin(ang)
            pos.append(P[i] + d * radii[i]); nrm.append(d)
    for i in range(n - 1):
        for k in range(sides):
            p0 = base + i * sides + k; p1 = base + i * sides + (k + 1) % sides; q0 = p0 + sides; q1 = p1 + sides
            idx.extend([(p0, q0, p1), (p1, q0, q1)])


def roots(mesh_pos, boulders):
    """A tree stands in a crevice on top of the pile, beside the big gap in the roof. Its roots
    creep over the boulders to the rim of the gap and hang down from there into the inner room;
    others run off over the rock and into the joints between the boulders. Every root starts
    at the trunk and lies on rock all the way to where it hangs (the first version hung strands
    in the opening that were attached to nothing).
    Returns the mesh and the tree's place ("fig" in grotto.json)."""
    sk = SKY[0]
    r = np.random.default_rng(4242)
    cell = 0.2
    x0 = mesh_pos[:, 0].min() - 2.0; z0 = mesh_pos[:, 2].min() - 2.0
    nx = int((mesh_pos[:, 0].max() + 2.0 - x0) / cell) + 2; nz = int((mesh_pos[:, 2].max() + 2.0 - z0) / cell) + 2
    top = np.full((nz, nx), -99.0)
    np.maximum.at(top, (((mesh_pos[:, 2] - z0) / cell).astype(int), ((mesh_pos[:, 0] - x0) / cell).astype(int)), mesh_pos[:, 1])
    gx, gz = np.meshgrid(x0 + (np.arange(nx) + 0.5) * cell, z0 + (np.arange(nz) + 0.5) * cell)
    top = np.maximum(top, ground(gx, gz))

    def surf(x, z):
        i = int(np.clip((x - x0) / cell, 1, nx - 2)); j = int(np.clip((z - z0) / cell, 1, nz - 2))
        return float(top[j - 1:j + 2, i - 1:i + 2].max())

    near = [b for b in boulders if np.linalg.norm(b["c"] - sk["floor"]) < 16.0]

    def in_rock(p):
        q = np.asarray(p, float)[None, :]
        return any(bool(inside(q, b, 0.97)[0]) for b in near)

    # where the gap opens on top of the pile
    t = 2.0
    while t < 30.0:
        e = sk["floor"] + sk["dir"] * t
        rim_h = max(surf(e[0] + np.cos(a) * sk["r"] * 1.6, e[2] + np.sin(a) * sk["r"] * 1.6) for a in np.arange(0, 6.28, 0.52))
        if e[1] > rim_h - 0.2:
            break
        t += 0.1
    exit_ = e
    # points on the rim, and how far a root can hang straight down from each
    rims = []
    for a in np.arange(0.0, 6.28, 0.2):
        d = np.array([np.cos(a), 0.0, np.sin(a)])
        rr = 0.2
        while rr < 3.0 and surf(exit_[0] + d[0] * rr, exit_[2] + d[2] * rr) < exit_[1] - 0.9:
            rr += 0.1
        q = exit_ + d * rr
        q[1] = surf(q[0], q[2])
        h = q - d * 0.3              # just inside the opening
        drop = 0.0
        floor_y = float(ground(h[0], h[2]))
        while h[1] - drop > floor_y + 0.02 and not in_rock(h - np.array([0.0, drop + 0.25, 0.0])):
            drop += 0.1
        if drop > 1.2:
            rims.append({"p": q, "in": h, "drop": drop, "to_floor": h[1] - drop <= floor_y + 0.15, "a": a})
    # the tree: on the side away from the midday sun (so its crown does not shade the gap), in
    # the deepest hollow between the boulders there
    away = -unit(np.array([sk["dir"][0], 0.0, sk["dir"][2]]))
    best = None
    for k in range(400):
        ang = np.arctan2(away[2], away[0]) + r.uniform(-1.0, 1.0); dist = r.uniform(4.0, 7.0)
        c = np.array([exit_[0] + np.cos(ang) * dist, 0.0, exit_[2] + np.sin(ang) * dist])
        c[1] = surf(c[0], c[2])
        ring = np.mean([surf(c[0] + np.cos(a) * 1.3, c[2] + np.sin(a) * 1.3) for a in np.arange(0, 6.28, 0.7)])
        score = (ring - c[1]) - 0.15 * abs(c[1] - exit_[1])
        if best is None or score > best[0]:
            best = (score, c)
    tree = best[1].copy()
    pos, nrm, idx = [], [], []

    def creep(start, target, rad0, rad1, seed, stop_at_rim=True, length=None):
        """Along the rock from start toward target; returns the points and radii."""
        g = np.random.default_rng(seed)
        d = target - start; d[1] = 0.0
        dist = float(np.linalg.norm(d)) if length is None else length
        d = unit(d); side = np.array([-d[2], 0.0, d[0]])
        n = max(4, int(dist / 0.12))
        ph = g.uniform(0, 6.28, 2); amp = g.uniform(0.12, 0.3); fr = g.uniform(1.0, 2.2)
        pts = []
        for i in range(n + 1):
            f = i / n
            w = (amp * np.sin(fr * f * dist + ph[0]) + 0.05 * np.sin(5.0 * f * dist + ph[1])) * np.sin(np.pi * f)
            c = start + d * (f * dist) + side * w
            c[1] = surf(c[0], c[2])
            pts.append(c)
        P = np.array(pts)
        # (roots bridge the joints between two boulders instead of diving into them)
        ys = np.convolve(np.pad(P[:, 1], 4, mode="edge"), np.ones(9) / 9.0, mode="valid")
        P[:, 1] = np.maximum(P[:, 1], ys)
        P[0, 1] = start[1]
        rad = np.linspace(rad0, rad1, len(P))
        P[:, 1] += rad * 0.45
        return P, rad

    def hang(P, rad, rim, seed, frac):
        """Over the lip and down into the room."""
        g = np.random.default_rng(seed)
        length = rim["drop"] * frac
        start = rim["in"].copy()
        n = max(6, int(length / 0.14))
        ph = g.uniform(0, 6.28, 4); fr = g.uniform(1.2, 3.0, 2); amp = g.uniform(0.02, 0.07, 2)
        pts = [P[-1] + (start - P[-1]) * 0.5 + np.array([0.0, 0.03, 0.0])]
        for i in range(n + 1):
            f = i / n; y = length * f
            pts.append(start + np.array([amp[0] * np.sin(fr[0] * y + ph[0]) * f + 0.012 * np.sin(9.0 * y + ph[2]), -y,
                                         amp[1] * np.sin(fr[1] * y + ph[1]) * f + 0.012 * np.sin(11.0 * y + ph[3])]))
        r1 = rad[-1]
        rr = [r1] + list(np.linspace(r1, max(r1 * (0.75 if frac >= 0.999 else 0.3), 0.004), n + 1))
        return np.vstack([P, np.array(pts)]), np.concatenate([rad, np.array(rr)])

    info = {"rim_points": len(rims), "hanging": 0, "reach_floor": 0}
    rims.sort(key=lambda q: -q["drop"])
    use = rims[:max(1, min(len(rims), 9))]
    for i, rim in enumerate(use):
        thick = r.uniform(0.022, 0.04) * (1.3 if i < 3 else 1.0)
        P, rad = creep(tree + np.array([np.cos(i * 2.4), 0.0, np.sin(i * 2.4)]) * 0.18, rim["p"], thick * 1.9, thick, 700 + i)
        frac = 1.0 if (rim["to_floor"] and i % 3 != 2) else float(r.uniform(0.45, 0.9))
        P2, rad2 = hang(P, rad, rim, 800 + i, frac)
        tube(P2, rad2, pos, nrm, idx)
        info["hanging"] += 1; info["reach_floor"] += int(frac == 1.0)
        # a thinner root leaves it on the way and hangs beside it
        if i < 6 and len(rims) > 1:
            other = rims[int(r.integers(0, len(rims)))]
            j = int(len(P) * r.uniform(0.45, 0.8))
            Pb, radb = creep(P[j] - np.array([0.0, rad[j] * 0.45, 0.0]), other["p"], rad[j] * 0.6, 0.012, 900 + i)
            Pb2, radb2 = hang(Pb, radb, other, 950 + i, float(r.uniform(0.3, 0.8)))
            tube(Pb2, radb2, pos, nrm, idx, 5)
            info["hanging"] += 1
    # roots that run off over the rock in other directions and end in a joint
    for i in range(6):
        ang = r.uniform(0, 6.28)
        tgt = tree + np.array([np.cos(ang), 0.0, np.sin(ang)]) * 5.0
        P, rad = creep(tree + np.array([np.cos(ang), 0.0, np.sin(ang)]) * 0.15, tgt, r.uniform(0.04, 0.07), 0.006, 1000 + i, length=float(r.uniform(2.0, 4.5)))
        P[-3:, 1] -= np.array([0.03, 0.08, 0.15])
        tube(P, rad, pos, nrm, idx)
    pos = np.array(pos); nrm = np.array(nrm); idx = np.array(idx, np.int64)
    # (outward faces: checked on the first triangle)
    a0, b0, c0 = pos[idx[0]]
    if np.dot(np.cross(b0 - a0, c0 - a0), nrm[idx[0][0]]) < 0.0:
        idx = idx[:, ::-1]
    fig = {"at": [float(tree[0]), float(tree[1]) - 0.3, float(tree[2])], "gap": [float(v) for v in exit_]}
    return pos, nrm, idx, fig, info


def write_glb(path, meshes):
    """meshes: [(name, material, positions, normals, triangles)]"""
    blob = b""; views = []; acc = []; mats = []; ms = []; nodes = []
    for name, mat, pos, nrm, idx in meshes:
        pos = pos.astype("<f4"); nrm = nrm.astype("<f4"); idx = idx.astype("<u4").ravel()
        a0 = len(acc)
        for arr, target in ((pos, 34962), (nrm, 34962), (idx, 34963)):
            views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": arr.nbytes, "target": target})
            blob += arr.tobytes()
            blob += b"\0" * ((4 - len(blob) % 4) % 4)
        acc.append({"bufferView": len(views) - 3, "componentType": 5126, "count": len(pos), "type": "VEC3",
                    "min": [float(v) for v in pos.min(0)], "max": [float(v) for v in pos.max(0)]})
        acc.append({"bufferView": len(views) - 2, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        acc.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        mats.append({"name": mat})
        ms.append({"name": name, "primitives": [{"attributes": {"POSITION": a0, "NORMAL": a0 + 1}, "indices": a0 + 2, "material": len(mats) - 1}]})
        nodes.append({"name": name, "mesh": len(ms) - 1})
    gltf = {"asset": {"version": "2.0", "generator": "grotto2.py"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
            "nodes": nodes, "materials": mats, "meshes": ms, "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": acc}
    js = json.dumps(gltf).encode(); js += b" " * ((4 - len(js) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)


if __name__ == "__main__":
    space = build_space()
    clear = clear_points()
    boulders, uncovered, failed = place(space, clear)
    light = seal(boulders, clear)
    n_shell = len(boulders)
    boulders = scatter(boulders, clear)
    boulders = floor_rocks(boulders, clear)
    # anything that still reaches into the walking space is made smaller until it does not
    for rnd in range(8):
        pos, nrm, idx, hidden, owner = assemble(boulders)
        bad = check_clear(pos)
        if not bad.any():
            break
        for i in np.unique(owner[bad]):
            boulders[i]["r"] = boulders[i]["r"] * 0.93
    rp, rn, ri, fig, root_info = roots(pos, boulders)
    pts, nrm_s, own, seal = space
    # where water seeps through and drips: roof points of the two rooms and the passage between
    roofpts = pts[(nrm_s[:, 1] > 0.75) & (ES[own] > ES[C1] - 4) & (ES[own] < ES[C2] + 4)]
    drips = roofpts[rng.choice(len(roofpts), 22, replace=False)]
    info = {"boulders": len(boulders), "shell": n_shell, "wall_points": int(len(seal)), "uncovered": uncovered, "could_not_place": failed,
            "vertices": int(len(pos)), "triangles": int(len(idx)), "hidden_triangles_left_out": hidden,
            "in_walking_space": int(bad.sum()), "top": float(pos[:, 1].max()), "light": light, "roots": root_info, "fig": fig,
            "extent_x": [float(pos[:, 0].min()), float(pos[:, 0].max())], "extent_z": [float(pos[:, 2].min()), float(pos[:, 2].max())]}
    if "--write" in sys.argv:
        write_glb(T.MOD + "grotto.glb", [("Grotto", "SeyGranite", pos, nrm, idx), ("GrottoRoots", "TakamakaBark", rp, rn, ri)])
        step = max(1, int(round(1.0 / (ES[1] - ES[0]))))
        data = {
            "path": [[float(EC[k, 0]), float(EC[k, 1]), float(EC[k, 2]), float(EW[k]), float(EH[k]), float(ES[k])] for k in range(0, len(EC), step)],
            "roofed": [ROOF_FROM, ROOF_TO],
            "front": [float(v) for v in EC[C1]], "inner": [float(v) for v in EC[C2]],
            "front_size": [float(EW[C1]), float(EH[C1])], "inner_size": [float(EW[C2]), float(EH[C2])],
            "skylights": [{"floor": [float(v) for v in sk["floor"]], "dir": [float(v) for v in sk["dir"]], "r": sk["r"]} for sk in SKY],
            "drips": [[float(v) for v in p] for p in drips],
            "fig": fig,
        }
        json.dump(data, open(T.MOD + "grotto.json", "w"), indent=1)
        info["written"] = True
    print(json.dumps(info, indent=1))
