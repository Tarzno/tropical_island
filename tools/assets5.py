# Round 5 assets: endemic Seychelles palms (coco de mer, latanier feuille, palmiste)
# and a granite boulder grotto. Run inside Blender: ns = {"__file__": path}; exec(open(path).read(), ns); ns['palms']()
# Reuses the helpers from assets4.py. Blender +Z up; crowns are exported with their origin at
# the top of the trunk (the palm_frond shader sways leaves by distance from that origin).
import bpy, bmesh, numpy as np, math
from mathutils import Vector, Matrix, noise

import os
# The project's folder, found from this file's place. Run in Blender, give the path along:
#   ns = {"__file__": path}; exec(open(path).read(), ns)
# (or name the folder in the environment variable TROPICAL_ISLAND; failing both, the folder
# Blender was started in is taken).
ROOT = os.environ.get("TROPICAL_ISLAND") or os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__") or os.path.join(os.getcwd(), "tools", "x"))))
exec(open(os.path.join(ROOT, "tools", "assets4.py")).read(), globals())

UPV = np.array([0.0, 0.0, 1.0])


class Quads:
    """Collects quads (4 corner points), UVs, a per-quad random and a material index."""
    def __init__(self):
        self.P = []; self.U = []; self.C = []; self.M = []

    def add(self, p, uv, c, m=0):
        self.P.append(p); self.U.append(uv); self.C.append(c); self.M.append(m)

    def mesh(self, name, mats):
        P = np.array(self.P, float); U = np.array(self.U, float)
        return quads_mesh(name, P, U, np.array(self.C), np.array(self.M), mats)


def frame(az, elev):
    """Forward (leaf direction), side and blade-up vectors for a leaf at azimuth/elevation."""
    f = np.array([math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev)])
    s = unit(np.cross(f, UPV)); u = unit(np.cross(s, f))
    return f, s, u


def petiole(q, base, f, length, width, c, droop=0.0, m=0):
    """Two crossed narrow strips (UV.x = 0: no flutter)."""
    s = unit(np.cross(f, UPV)); u = unit(np.cross(s, f))
    n = 4
    pts = [base + f * length * t - UPV * droop * (t * length) ** 2 for t in np.linspace(0, 1, n + 1)]
    for a, b in ((s, u), (u, s)):
        for i in range(n):
            w0 = width * (1 - 0.4 * i / n); w1 = width * (1 - 0.4 * (i + 1) / n)
            q.add([pts[i] - a * w0, pts[i] + a * w0, pts[i + 1] + a * w1, pts[i + 1] - a * w1],
                  [[0, 0], [0, 1], [0, 1], [0, 0]], c, m)
    return pts[-1], unit(pts[-1] - pts[-2])


def fan_leaf(q, rng, base, az, elev, P, R, span, npleat, nseg, droop, fold, split, m=0):
    """Costapalmate fan (coco de mer): pleated V-folded segments radiating from the end of the
    petiole, the outer part of each segment free and drooping."""
    f, s, u = frame(az, elev)
    O, fd = petiole(q, base, f, P, 0.07 * R / 3.0, rng.random(), droop=0.02, m=m)
    f = unit(fd * 0.6 + f * 0.4)
    s = unit(np.cross(f, UPV)); u = unit(np.cross(s, f))
    da = span / npleat
    for i in range(npleat):
        a = -span / 2 + (i + 0.5) * da
        c = rng.random()
        Ri = R * rng.uniform(0.86, 1.0) * (1 - 0.18 * (abs(a) / (span / 2)) ** 2)
        tipdrop = rng.uniform(0.6, 1.4)
        def pt(r, aa, lift):
            t = r / Ri
            d = f * math.cos(aa) + s * math.sin(aa)
            p = O + d * r + u * lift * r
            # the costa arches the blade over; free segment tips hang down
            p = p - UPV * (droop * R * t * t * (0.6 + 0.4 * math.cos(a)))
            p = p - UPV * max(0.0, t - (1 - split)) / split * 0.35 * R * tipdrop * 0.4
            return p
        rows = []
        for j in range(nseg + 1):
            r = Ri * j / nseg
            t = j / nseg
            # beyond the split the segment narrows: gaps open between neighbors
            half = da / 2 * (1.0 if t < 1 - split else 1.0 - 0.55 * (t - (1 - split)) / split)
            rows.append([pt(r, a - half, 0.0), pt(r, a, fold), pt(r, a + half, 0.0)])
        for j in range(nseg):
            x0 = j / nseg; x1 = (j + 1) / nseg
            for k, (y0, y1) in enumerate(((0.0, 0.5), (0.5, 1.0))):
                q.add([rows[j][k], rows[j][k + 1], rows[j + 1][k + 1], rows[j + 1][k]],
                      [[x0, y0], [x0, y1], [x1, y1], [x1, y0]], c, m)


def entire_leaf(q, rng, base, az, elev, P, L, W, nseg, ncol, droop, m=0):
    """Latanier feuille: a large undivided, pleated, wedge-shaped blade split at the tip."""
    f, s, u = frame(az, elev)
    O, fd = petiole(q, base, f, P, 0.035, rng.random(), droop=0.05, m=m)
    f = unit(fd * 0.5 + f * 0.5)
    s = unit(np.cross(f, UPV)); u = unit(np.cross(s, f))
    c = rng.random()
    grid = []
    for j in range(nseg + 1):
        t = j / nseg
        w = W / 2 * (0.08 + 0.92 * t ** 0.55) * (1 - 0.12 * t) * (1 - 0.1 * (t * 9 % 1.0) * (t > 0.3))
        row = []
        for k in range(ncol + 1):
            sv = k / ncol * 2 - 1
            corr = 0.035 * (1 if k % 2 else -1) * min(1.0, t * 3)
            p = O + f * L * t + s * sv * w + u * (abs(sv) * w * 0.25 + corr) - UPV * droop * (t * L) ** 2 / L
            row.append(p)
        grid.append(row)
    for j in range(nseg):
        for k in range(ncol):
            t = (j + 0.5) / nseg; sv = ((k + 0.5) / ncol) * 2 - 1
            if t > 0.8 and abs(sv) < 0.12:
                continue   # bifid tip
            q.add([grid[j][k], grid[j][k + 1], grid[j + 1][k + 1], grid[j + 1][k]],
                  [[j / nseg, k / ncol], [j / nseg, (k + 1) / ncol], [(j + 1) / nseg, (k + 1) / ncol], [(j + 1) / nseg, k / ncol]],
                  (c + k * 0.13) % 1.0, m)


def pinnate_frond(q, rng, base, az, elev, L, pairs, lf, droop, width=0.035, m=0, step=1, wmul=1.0):
    """Palmiste: arching feather leaf with long, drooping leaflets."""
    f, s, u = frame(az, elev)
    pts = []; tans = []
    for t in np.linspace(0, 1, 25):
        p = base + f * L * t - UPV * droop * (t * L) ** 2 / L
        pts.append(p)
    for i in range(len(pts)):
        tans.append(unit(pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]))
    # rachis
    for i in range(len(pts) - 1):
        w = 0.03 * (1 - i / len(pts))
        q.add([pts[i] - s * w, pts[i] + s * w, pts[i + 1] + s * w * 0.9, pts[i + 1] - s * w * 0.9],
              [[0, 0], [0, 1], [0, 1], [0, 0]], 0.5, m)
    for i in range(0, pairs, step):
        t = 0.08 + 0.9 * i / pairs
        fi = t * (len(pts) - 1); k = int(fi); fr = fi - k
        p = pts[k] * (1 - fr) + pts[min(k + 1, len(pts) - 1)] * fr
        tg = tans[k]
        ls = unit(np.cross(tg, UPV))
        ln = lf * math.sin(math.pi * min(1.0, t * 1.1)) ** 0.5 * rng.uniform(0.9, 1.1)
        for side in (-1, 1):
            d = unit(ls * side * 0.75 + tg * 0.45 - UPV * rng.uniform(0.35, 0.65))
            nrm = unit(np.cross(d, tg) * side + UPV * 0.3)
            wv = unit(np.cross(nrm, d)) * width * wmul
            tip = p + d * ln - UPV * 0.12 * ln
            mid = p + d * ln * 0.5
            c = rng.random()
            q.add([p - wv * 0.5, p + wv * 0.5, mid + wv, mid - wv], [[0, 0], [0, 1], [0.5, 1], [0.5, 0]], c, m)
            q.add([mid - wv, mid + wv, tip + wv * 0.15, tip - wv * 0.15], [[0.5, 0], [0.5, 1], [1, 1], [1, 0]], c, m)


# ------------------------------------------------------------------ trunks
def trunk(name, H, r0, rtop, bend, flare=0.0, sides=10, mats=("PalmBark",), shaft=None):
    bm = bmesh.new()
    pts = []; radii = []
    for t in np.linspace(0, 1, 14):
        z = -1.2 + (H + 1.2) * t
        off = np.array(bend) * math.sin(math.pi * 0.5 * max(t, 0)) * t
        pts.append(Vector((off[0], off[1], z)))
        h = max(z, 0.0)
        radii.append((r0 + (rtop - r0) * t) * (1 + flare * math.exp(-h / 0.6)))
    tube(bm, pts, radii, sides)
    if shaft:   # crownshaft: smooth sheath at the top
        L, R = shaft
        top = pts[-1]; d = (pts[-1] - pts[-2]).normalized()
        tube(bm, [top - d * L, top - d * L * 0.5, top + d * 0.05], [R * 0.95, R, R * 0.9], sides, mat_index=1)
    me = bm_to_mesh(bm, name, list(mats))
    return me, pts[-1]


def ensure_palm_mats():
    mat("PalmBark", (0.35, 0.3, 0.25), 0.85)
    mat("CocoDeMerLeaf", (0.3, 0.45, 0.12), 0.4)
    mat("LatanierLeaf", (0.18, 0.4, 0.1), 0.4)
    mat("PalmisteLeaf", (0.15, 0.38, 0.08), 0.45)
    mat("PalmDeadLeaf", (0.4, 0.3, 0.17), 0.9)
    mat("PalmisteShaft", (0.55, 0.58, 0.45), 0.5)
    mat("CocoDeMerNut", (0.2, 0.3, 0.08), 0.5)
    mat("CocoDeMerSeed", (0.06, 0.04, 0.03), 0.4)
    mat("CocoDeMerHuskOld", (0.25, 0.2, 0.1), 0.8)
    mat("CocoDeMerCatkin", (0.3, 0.2, 0.1), 0.8)


def coco_de_mer(col, name, seed, H, female, lod):
    rng = np.random.default_rng(seed)
    q = Quads()
    n = 14 if not lod else 11
    for i in range(n):
        az = i * 2.39996 + rng.uniform(-0.2, 0.2)
        age = i / n   # older leaves lower and more horizontal
        elev = math.radians(65 - 75 * age + rng.uniform(-8, 8))
        fan_leaf(q, rng, np.array([0, 0, -0.3 * age]), az, elev, rng.uniform(2.0, 3.2), rng.uniform(2.4, 3.1),
                 math.radians(rng.uniform(150, 175)), 9 if lod else 26, 3 if lod else 9, 0.18 + 0.15 * age, 0.12, 0.25)
    # dead leaves hanging against the trunk
    for i in range(int(rng.integers(2, 4))):
        az = rng.uniform(0, 2 * math.pi)
        fan_leaf(q, rng, np.array([0, 0, -0.6]), az, math.radians(-75), 1.2, 2.2, math.radians(70),
                 5 if lod else 12, 2 if lod else 5, 0.05, 0.05, 0.3, m=1)
    objs = [link(col, name + "Crown" + ("_lod" if lod else ""), q.mesh(name + "Crown" + ("_lod" if lod else ""), ["CocoDeMerLeaf", "PalmDeadLeaf"]))]
    if female and not lod:
        # the fruit: one or two stout zigzag stalks hanging from among the leaf bases, each with a
        # few huge green two-lobed fruits at different stages
        bm = bmesh.new()
        a0 = rng.uniform(0, 2 * math.pi)
        for s in range(2):
            a = a0 + s * rng.uniform(2.2, 3.6)
            out = Vector((math.cos(a), math.sin(a), 0)); tang = Vector((-math.sin(a), math.cos(a), 0))
            nfr = int(rng.integers(3, 6)) if s == 0 else int(rng.integers(2, 4))
            nodes = [Vector((0, 0, -0.25)) + out * 0.16, Vector((0, 0, -0.3)) + out * 0.45]
            for k in range(nfr):
                side = 1 if k % 2 else -1
                nodes.append(out * rng.uniform(0.56, 0.66) + tang * side * rng.uniform(0.1, 0.16) + Vector((0, 0, -0.62 - 0.37 * k)))
            tube(bm, nodes, [0.06] + [0.055 - 0.015 * i / len(nodes) for i in range(len(nodes) - 1)], 7, mat_index=1)
            for k in range(nfr):
                side = 1 if k % 2 else -1
                sz = rng.uniform(0.85, 1.05) * (1.0 if k < nfr - 1 or rng.random() < 0.4 else 0.6)   # the youngest at the end
                top = nodes[2 + k] + tang * side * 0.12 + out * rng.uniform(-0.04, 0.1) - Vector((0, 0, 0.1))
                rot = Matrix.Rotation(a + math.pi / 2 + rng.uniform(-0.5, 0.5), 4, 'Z') @ Matrix.Rotation(rng.uniform(-0.2, 0.2), 4, 'X') \
                    @ Matrix.Rotation(rng.uniform(-0.15, 0.15), 4, 'Y')
                tube(bm, [nodes[2 + k], top + Vector((0, 0, 0.03))], [0.03, 0.028], 6, mat_index=1)
                coco_fruit(bm, rng, Matrix.Translation(top) @ rot, sz, husk=True)
        objs.append(link(col, name + "Nuts", bm_to_mesh(bm, name + "Nuts", ["CocoDeMerNut", "CocoDeMerCatkin"])))
    if not female and not lod:
        # the male flowers: arm-long brown catkins arching out from among the leaf bases
        bm = bmesh.new()
        a0 = rng.uniform(0, 2 * math.pi)
        for s in range(int(rng.integers(2, 4))):
            a = a0 + s * rng.uniform(1.6, 2.6)
            out = Vector((math.cos(a), math.sin(a), 0))
            L = rng.uniform(1.2, 1.8)
            p0 = Vector((0, 0, -0.2)) + out * 0.15
            p1 = out * (0.25 + L * 0.4) + Vector((0, 0, 0.05))
            p2 = out * (0.3 + L * 0.5) + Vector((0, 0, -L * 0.85))
            pts = [p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t for t in np.linspace(0, 1, 12)]
            rad = [0.03, 0.033] + [0.06] * 8 + [0.052, 0.025]   # a short stalk, then the thick flowering part
            tube(bm, pts, rad, 9)
        objs.append(link(col, name + "Flowers", bm_to_mesh(bm, name + "Flowers", ["CocoDeMerCatkin"])))
    return objs


# The nut of the coco de mer in meters, stalk end up (+Z), the two lobes side by side along X:
# two long lobes joined by a shoulder at the top, a deep cleft between them below.
NUT_LOBES = [((-0.087, 0, -0.035), (0.082, 0.086, 0.135)), ((0.087, 0, -0.035), (0.082, 0.086, 0.135)),
             ((0, 0, 0.055), (0.128, 0.082, 0.075))]


def lobed_surface(bm, lobes, k, mtx, nu=22, nv=15, mat_index=0, rng=None, rough=0.0):
    """Smooth union of ellipsoids [(center, radii)] meshed as a sphere around the origin: every
    vertex is pushed out along its ray to where the field sum(exp(-k (|(p - c) / r|^2 - 1))) falls
    to 1 (a small k rounds the lobes into one body, a large k keeps the cleft between them)."""
    C = np.array([l[0] for l in lobes], float); R = np.array([l[1] for l in lobes], float)
    rmax = float(np.max(np.linalg.norm(C, axis=1) + R.max(axis=1))) * 1.3
    def field(p):
        return float(np.sum(np.exp(-k * (np.sum(((p - C) / R) ** 2, axis=1) - 1.0))))
    off = rng.uniform(0, 50, 3) if rng is not None else np.zeros(3)
    def radius(d):
        hi = rmax
        while hi > 0 and field(d * hi) < 1.0:
            hi -= rmax / 48
        lo, hi = hi, hi + rmax / 48
        for _ in range(12):
            mid = (lo + hi) / 2
            if field(d * mid) >= 1.0: lo = mid
            else: hi = mid
        r = lo
        if rough:
            r *= 1.0 + rough * noise.noise(Vector(d * 2.3 + off))
        return r
    top = bm.verts.new(mtx @ Vector((0, 0, radius(np.array([0, 0, 1.0])))))
    bot = bm.verts.new(mtx @ Vector((0, 0, -radius(np.array([0, 0, -1.0])))))
    rings = []
    for j in range(1, nv):
        th = math.pi * j / nv
        ring = []
        for i in range(nu):
            ph = 2 * math.pi * i / nu
            d = np.array([math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)])
            ring.append(bm.verts.new(mtx @ Vector(d * radius(d))))
        rings.append(ring)
    for i in range(nu):
        i2 = (i + 1) % nu
        bm.faces.new((top, rings[0][i], rings[0][i2])).material_index = mat_index
        bm.faces.new((bot, rings[-1][i2], rings[-1][i])).material_index = mat_index
        for j in range(len(rings) - 1):
            bm.faces.new((rings[j][i], rings[j + 1][i], rings[j + 1][i2], rings[j][i2])).material_index = mat_index


def coco_fruit(bm, rng, mtx, size, husk):
    """husk=True: the fruit as it hangs on the palm, the nut inside its thick green husk (a heavy
    heart shape, the two lobes showing at the bottom), with the cap of bracts it hangs from;
    origin at the stalk. husk=False: the bare double nut, origin at its center."""
    if husk:
        s = size * 1.38
        lobes = [(np.array(c) * s, np.array(r) * s * 1.1) for c, r in NUT_LOBES]
        lobed_surface(bm, lobes, 3.0, mtx @ Matrix.Translation((0, 0, -0.165 * s)), rng=rng, rough=0.035)
        tube(bm, [mtx @ Vector((0, 0, 0.03)), mtx @ Vector((0, 0, -0.01 * s)), mtx @ Vector((0, 0, -0.07 * s))],
             [0.035 * s, 0.09 * s, 0.112 * s], 9, mat_index=1)
    else:
        lobes = [(np.array(c) * size, np.array(r) * size) for c, r in NUT_LOBES]
        lobed_surface(bm, lobes, 7.0, mtx, nu=26, nv=18, rng=rng, rough=0.02)


def coco_juvenile(col, name, seed, lod):
    """A young coco de mer: no trunk yet, a handful of enormous fans on very long stalks rising
    straight from the ground (it stays like this for decades)."""
    rng = np.random.default_rng(seed)
    q = Quads()
    n = int(rng.integers(4, 7))
    for i in range(n):
        az = i * 2.39996 + rng.uniform(-0.3, 0.3)
        elev = math.radians(rng.uniform(52, 80) - 12 * i / n)
        fan_leaf(q, rng, np.array([0, 0, -0.25]), az, elev, rng.uniform(2.3, 3.6), rng.uniform(1.9, 2.6),
                 math.radians(rng.uniform(140, 170)), 9 if lod else 24, 3 if lod else 8, 0.14, 0.12, 0.22)
    if rng.random() < 0.7:   # an old leaf collapsed to the ground
        fan_leaf(q, rng, np.array([0, 0, -0.1]), rng.uniform(0, 2 * math.pi), math.radians(8), 1.6, 1.9, math.radians(120),
                 5 if lod else 12, 2 if lod else 5, 0.1, 0.05, 0.4, m=1)
    nm = name + "Crown" + ("_lod" if lod else "")
    return [link(col, nm, q.mesh(nm, ["CocoDeMerLeaf", "PalmDeadLeaf"]))]


def latanier(col, name, seed, lod):
    rng = np.random.default_rng(seed)
    q = Quads()
    n = 12 if not lod else 9
    for i in range(n):
        az = i * 2.39996 + rng.uniform(-0.2, 0.2)
        age = i / n
        elev = math.radians(70 - 60 * age + rng.uniform(-8, 8))
        entire_leaf(q, rng, np.array([0, 0, -0.2 * age]), az, elev, rng.uniform(1.0, 1.6), rng.uniform(2.1, 2.8),
                    rng.uniform(1.3, 1.8), 4 if lod else 10, 3 if lod else 8, 0.25 + 0.3 * age)
    for i in range(int(rng.integers(1, 3))):
        entire_leaf(q, rng, np.array([0, 0, -0.4]), rng.uniform(0, 2 * math.pi), math.radians(-70), 0.6, 1.6, 0.9,
                    3 if lod else 6, 2 if lod else 4, 0.05, m=1)
    nm = name + "Crown" + ("_lod" if lod else "")
    return [link(col, nm, q.mesh(nm, ["LatanierLeaf", "PalmDeadLeaf"]))]


def palmiste(col, name, seed, lod):
    rng = np.random.default_rng(seed)
    q = Quads()
    n = 10 if not lod else 8
    for i in range(n):
        az = i * 2.39996 + rng.uniform(-0.2, 0.2)
        age = i / n
        elev = math.radians(60 - 55 * age + rng.uniform(-6, 6))
        pinnate_frond(q, rng, np.array([0, 0, -0.1 * age]), az, elev, rng.uniform(3.0, 3.8), 46, rng.uniform(0.7, 0.9),
                      0.35 + 0.35 * age, step=3 if lod else 1, wmul=2.4 if lod else 1.0)
    nm = name + "Crown" + ("_lod" if lod else "")
    return [link(col, nm, q.mesh(nm, ["PalmisteLeaf"]))]


def palms(fname="endemic_palms.glb", keep=False):
    """Exports endemic_palms.glb: per variant <Name>Trunk (origin on the ground), <Name>Crown and
    <Name>Crown_lod (origin at the trunk top), optional <Name>Nuts (the fruit on a female coco de mer)
    and <Name>Flowers (a male's catkins). Trunkless young coco de mer: CocoJ0/1 Crown(+_lod), origin
    on the ground. Loose on the forest floor: CocoSeed (the bare double nut, origin at its center,
    stalk end +Z, lobes along X) and CocoFruitOld (a fallen fruit still in its husk)."""
    ensure_palm_mats()
    col = new_col(); objs = []
    specs = [  # name, kind, seed, height, trunk radius base/top, bend
        ("CocoA", "coco", 501, 14.0, 0.24, 0.2, (0.3, 0.2), False),
        ("CocoB", "coco", 502, 10.0, 0.25, 0.21, (-0.2, 0.3), True),
        ("LatA", "lat", 511, 9.0, 0.11, 0.09, (0.6, 0.1), False),
        ("LatB", "lat", 512, 6.5, 0.1, 0.085, (-0.3, 0.5), False),
        ("PalmA", "palmiste", 521, 18.0, 0.16, 0.12, (0.4, -0.3), False),
        ("PalmB", "palmiste", 522, 13.0, 0.15, 0.115, (-0.5, 0.2), False),
    ]
    for name, kind, seed, H, r0, r1, bend, female in specs:
        me, top = trunk(name + "Trunk", H, r0, r1, bend, flare=0.5 if kind == "coco" else 0.25,
                        mats=("PalmBark", "PalmisteShaft") if kind == "palmiste" else ("PalmBark",),
                        shaft=(1.6, r1 * 1.35) if kind == "palmiste" else None)
        objs.append(link(col, name + "Trunk", me))
        for lod in (False, True):
            if kind == "coco":
                parts = coco_de_mer(col, name, seed, H, female, lod)
            elif kind == "lat":
                parts = latanier(col, name, seed, lod)
            else:
                parts = palmiste(col, name, seed, lod)
            for o in parts:
                o.location = top
            objs += parts
    for i, seed in enumerate((531, 532)):
        for lod in (False, True):
            objs += coco_juvenile(col, f"CocoJ{i}", seed, lod)
    rng = np.random.default_rng(540)
    bm = bmesh.new()
    coco_fruit(bm, rng, Matrix.Identity(4), 1.0, husk=False)
    objs.append(link(col, "CocoSeed", bm_to_mesh(bm, "CocoSeed", ["CocoDeMerSeed"])))
    bm = bmesh.new()
    lobes = [(np.array(c) * 1.38, np.array(r) * 1.38 * 1.1) for c, r in NUT_LOBES]
    lobed_surface(bm, lobes, 3.0, Matrix.Identity(4), rng=rng, rough=0.06)
    objs.append(link(col, "CocoFruitOld", bm_to_mesh(bm, "CocoFruitOld", ["CocoDeMerHuskOld"])))
    export(objs, fname)
    info = {o.name: len(o.data.polygons) for o in objs}
    if keep:
        return info, col
    drop(col)
    return info


# ------------------------------------------------------------------ grotto
def _blob(name, col, center, radii, seed, amp, subdiv=5, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = Vector((seed * 3.7, seed * 1.3, seed * 2.9))
    for v in bm.verts:
        d = v.co.normalized()
        n = noise.noise(d * 1.4 + off) * amp + noise.noise(d * 3.6 + off * 1.7) * amp * 0.35 + noise.noise(d * 9.0 + off) * amp * 0.08
        p = Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2])) * (1.0 + n)
        # granite exfoliation: slightly flattened facets on the upper surfaces
        v.co = Matrix.Rotation(rot[0], 3, 'X') @ Matrix.Rotation(rot[1], 3, 'Y') @ Matrix.Rotation(rot[2], 3, 'Z') @ p + Vector(center)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return link(col, name, me)


def grotto():
    """SUPERSEDED on 2026-11-10 by tools/grotto2.py (boulders piled around a laid-out space; this
    one carved a hollow out of fused blobs and needed tools/grotto_terrain.json). Kept for reference.
    A walkable granite boulder cave: fused weathered boulders with a front chamber, an entrance
    cleft at the front (-Y), a passage climbing back (+Y) into the hillside to an inner chamber,
    two narrow skylight cracks, stalactites (hanging, no collision) and stalagmites (solid).
    Origin = floor level of the front chamber. The passage follows the terrain heights exported
    from Godot (tools/grotto_terrain.json, Godot local x/z), so the hillside is its floor."""
    import json
    from mathutils.bvhtree import BVHTree
    T = json.load(open(os.path.join(ROOT, "tools", "grotto_terrain.json")))
    rows = np.array(T["rows"])
    def g(xb, yb):   # terrain height above the origin at Blender local (x, y) = Godot (x, -y)
        gx = (xb - T["x0"]) / T["step"]; gz = (T["z0"] - (-yb)) / T["step"]
        gx = min(max(gx, 0), rows.shape[1] - 1.001); gz = min(max(gz, 0), rows.shape[0] - 1.001)
        i, j = int(gz), int(gx); fz, fx = gz - i, gx - j
        return (rows[i, j] * (1 - fx) + rows[i, j + 1] * fx) * (1 - fz) + (rows[i + 1, j] * (1 - fx) + rows[i + 1, j + 1] * fx) * fz
    col = new_col()
    granite = bpy.data.materials.get("SeyGranite")
    flow = mat("Flowstone", (0.62, 0.58, 0.52), 0.25)
    solids = [
        _blob("GrottoA", col, (0.6, 0.9, 1.0), (6.2, 5.0, 4.3), 1, 0.17, rot=(0.08, 0.1, 0.3)),
        _blob("GrottoB", col, (-4.2, -1.2, 0.6), (3.8, 3.4, 3.4), 2, 0.2, rot=(0.15, -0.35, 0.8)),
        _blob("GrottoC", col, (4.4, 1.2, 0.3), (4.0, 3.8, 3.3), 3, 0.2, rot=(-0.1, 0.25, -0.5)),
        _blob("GrottoD", col, (-1.0, 4.2, 2.2), (4.5, 3.0, 3.0), 7, 0.2, rot=(0.0, 0.2, 1.1)),
    ]
    holes = [
        _blob("GrottoRoom", col, (0.0, 0.6, 0.55), (3.6, 3.0, 2.45), 4, 0.13),
        _blob("GrottoTunnel", col, (-0.9, -3.6, 0.6), (1.05, 2.9, 2.2), 5, 0.22, rot=(0.0, -0.32, 0.12)),
        _blob("GrottoNotch", col, (-0.2, -4.6, 1.9), (0.7, 1.6, 1.0), 8, 0.25, subdiv=4, rot=(0.3, 0.5, 0.0)),
        _blob("GrottoSky", col, (1.3, 1.5, 4.3), (0.42, 1.4, 1.7), 6, 0.2, subdiv=4, rot=(0.1, 0.25, 0.4)),
    ]
    # the passage back into the hill: rock cover and carved tunnel follow the rising ground
    path = [(-0.6, 3.2), (-1.1, 6.0), (-1.7, 8.8), (-2.2, 11.6), (-2.6, 14.0)]
    for k, (x, y) in enumerate(path):
        gz = g(x, y)
        solids.append(_blob(f"GrottoP{k}", col, (x + 0.3, y, gz + 1.1), (3.8, 3.6, 3.4), 20 + k, 0.2,
                            rot=(0.1 * k, -0.15, 0.3 * k)))
        # the carve reaches well below the ground, so the hillside itself is the floor (no rock lips)
        holes.append(_blob(f"GrottoT{k}", col, (x, y, gz + 0.95), (1.35, 2.2, 1.85), 40 + k, 0.12, subdiv=4,
                           rot=(-0.12, 0.0, 0.2 * (k % 2) - 0.1)))
    ic = (-2.8, 17.0); gi = g(*ic)
    solids.append(_blob("GrottoInnerRock", col, (ic[0] + 0.4, ic[1] + 0.6, gi + 1.0), (5.4, 5.0, 4.6), 30, 0.18, rot=(0.0, 0.1, 0.6)))
    holes.append(_blob("GrottoInner", col, (ic[0], ic[1], gi + 1.0), (3.1, 2.9, 2.8), 31, 0.13, rot=(0.0, 0.0, 0.3)))
    holes.append(_blob("GrottoSky2", col, (ic[0] + 1.0, ic[1] + 0.9, gi + 4.4), (0.35, 1.1, 1.8), 32, 0.22, subdiv=4, rot=(0.15, -0.2, 1.0)))
    def apply_bool(target, other, op):
        mod = target.modifiers.new("b", 'BOOLEAN'); mod.operation = op; mod.object = other; mod.solver = 'EXACT'
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
        target.modifiers.remove(mod)
        old = target.data; target.data = me; bpy.data.meshes.remove(old)
    A = solids[0]
    for o in solids[1:]:
        apply_bool(A, o, 'UNION')
    for o in holes:
        apply_bool(A, o, 'DIFFERENCE')
    for o in solids[1:] + holes:
        me = o.data; bpy.data.objects.remove(o); bpy.data.meshes.remove(me)
    bm = bmesh.new(); bm.from_mesh(A.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(A.data); bm.free()
    A.data.materials.clear(); A.data.materials.append(granite)
    for p in A.data.polygons: p.use_smooth = True
    A.name = "Grotto"; A.data.name = "Grotto"
    # ---- stalactites and stalagmites: find the ceiling above sample points on the floor
    bm = bmesh.new(); bm.from_mesh(A.data); bm.transform(A.matrix_world)
    tree = BVHTree.FromBMesh(bm); bm.free()
    rng = np.random.default_rng(77)
    walk = [(0.0, -2.0), (-0.3, 0.6)] + path + [ic]   # keep the walking line clear
    def walk_dist(x, y):
        best = 9.0
        for i in range(len(walk) - 1):
            a = np.array(walk[i]); b = np.array(walk[i + 1]); pnt = np.array((x, y))
            t = np.clip(np.dot(pnt - a, b - a) / max(np.dot(b - a, b - a), 1e-6), 0, 1)
            best = min(best, np.linalg.norm(pnt - (a + (b - a) * t)))
        return best
    tites = bmesh.new(); mites = bmesh.new()
    tips = []
    zones = [((0.0, 0.6), (3.2, 2.6), 26), (ic, (2.7, 2.5), 30), ((-1.6, 9.0), (1.0, 5.0), 14)]
    for (cx, cy), (rx, ry), n in zones:
        made = 0
        for t in range(n * 6):
            if made >= n:
                break
            x = cx + rng.uniform(-rx, rx); y = cy + rng.uniform(-ry, ry)
            fl = g(x, y)
            hit = tree.ray_cast(Vector((x, y, fl + 0.3)), Vector((0, 0, 1)), 8.0)
            if hit[0] is None:
                continue
            ceil = hit[0]
            if hit[1].z > -0.3:      # not a ceiling (wall facing up / outside)
                continue
            head = ceil.z - fl
            clear = walk_dist(x, y)
            room = head - (2.15 if clear < 1.3 else 0.5)
            if room < 0.12:
                continue
            L = min(rng.uniform(0.12, 0.85) * (1.0 if clear > 1.3 else 0.5), room)
            r = L * rng.uniform(0.12, 0.2) + 0.02
            top = ceil + Vector((0, 0, 0.15))
            m = Matrix.Translation(top - Vector((0, 0, (L + 0.15) / 2)))
            bmesh.ops.create_cone(tites, cap_ends=True, segments=7, radius1=r * 0.15, radius2=r, depth=L + 0.15, matrix=m)
            tips.append([x, ceil.z - L, y])
            made += 1
            # a stalagmite growing up beneath some of them, away from the path
            if clear > 1.5 and rng.random() < 0.45 and head > 1.2:
                Lm = min(rng.uniform(0.15, 0.6), head - L - 0.3)
                if Lm > 0.12:
                    rm = Lm * rng.uniform(0.25, 0.4) + 0.04
                    mm = Matrix.Translation(Vector((x, y, fl - 0.1 + (Lm + 0.1) / 2)))
                    bmesh.ops.create_cone(mites, cap_ends=True, segments=7, radius1=rm, radius2=rm * 0.2, depth=Lm + 0.1, matrix=mm)
    for b in (tites, mites):
        for v in b.verts:   # lumpy, not perfect cones
            v.co += Vector((noise.noise(v.co * 7.0), noise.noise(v.co * 7.0 + Vector((5, 1, 2))), 0)) * 0.015
    objs = [A]
    for b, nm in ((tites, "GrottoStalactites"), (mites, "GrottoStalagmites")):
        if len(b.faces):
            me = bm_to_mesh(b, nm, [flow]); objs.append(link(col, nm, me))
        else:
            b.free()
    # drip points (Godot local: x, y, z = -y_blender)
    json.dump({"tips": [[t[0], t[1], -t[2]] for t in tips], "inner": [ic[0], gi, -ic[1]]},
              open(OUT + "grotto_tips.json", "w"))
    info = {"faces": len(A.data.polygons), "stalactites": len(tips)}
    export(objs, "grotto.glb", vc='NONE')
    drop(col)
    return info


# ------------------------------------------------------------------ ferns
def _strip_leaf(q, base, dirs_pts, width, c, a, m=0):
    """A curved leaf card through a polyline (UV.y 0 base .. 1 tip, UV.x across) for the leaf shader."""
    n = len(dirs_pts) - 1
    for i in range(n):
        p0 = dirs_pts[i]; p1 = dirs_pts[i + 1]
        t = unit(p1 - p0)
        side = unit(np.cross(t, UPV)) * width
        q.add([p0 - side, p0 + side, p1 + side, p1 - side], [[0, i / n], [1, i / n], [1, (i + 1) / n], [0, (i + 1) / n]], c, m)
        q.A.append(a)


class QuadsA(Quads):
    def __init__(self):
        super().__init__(); self.A = []; self.N = []

    def mesh(self, name, mats):
        P = np.array(self.P, float); U = np.array(self.U, float)
        A = np.array(self.A) if self.A else None
        return quads_mesh(name, P, U, np.array(self.C), np.array(self.M), mats, A)


def fern_pinnate(name, seed, lod):
    """Ground fern: a rosette of arching pinnate fronds with lance-shaped pinnae."""
    rng = np.random.default_rng(seed)
    P = []; U = []; C = []; M = []; A = []
    nfr = int(rng.integers(11, 16)) if not lod else 8
    for i in range(nfr):
        az = i * 2.39996 + rng.uniform(-0.3, 0.3)
        elev = math.radians(rng.uniform(25, 70))
        L = rng.uniform(0.7, 1.25)
        f = np.array([math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev)])
        droop = rng.uniform(0.35, 0.7)
        rach = [f * L * t - UPV * droop * (t * L) ** 2 / L for t in np.linspace(0, 1, 30)]
        pairs = 18 if not lod else 7
        for k in range(pairs):
            t = 0.12 + 0.86 * k / pairs
            j = int(t * 29); p = rach[j]; tg = unit(rach[min(j + 1, 29)] - rach[j])
            side = unit(np.cross(tg, UPV))
            lp = 0.2 * L * math.sin(math.pi * min(t * 1.05, 1.0)) ** 0.6 * (1.0 if not lod else 1.4)
            for sgn in (-1, 1):
                d = unit(side * sgn + tg * 0.45 - UPV * 0.1)
                up = unit(np.cross(d, tg) * sgn + UPV * 0.5)
                q, uv, nrm = leaf_cards(p[None], d[None], up[None], np.array([lp]), np.array([lp * 0.3]))
                P.append(q[0]); U.append(uv[0]); C.append(rng.random()); M.append(0)
                A.append(0.45 + 0.55 * t)
    me = quads_mesh(name, np.array(P), np.array(U), np.array(C), np.array(M), ["FernLeaf"], np.array(A))
    return me


def fern_nest(name, seed, lod):
    """Bird's-nest fern (Asplenium nidus): a vase of broad, glossy, undivided fronds."""
    rng = np.random.default_rng(seed)
    q = QuadsA()
    nfr = int(rng.integers(10, 15)) if not lod else 8
    for i in range(nfr):
        az = i * 2.39996 + rng.uniform(-0.2, 0.2)
        elev = math.radians(rng.uniform(40, 72))
        L = rng.uniform(0.7, 1.15)
        f = np.array([math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev)])
        out = np.array([math.cos(az), math.sin(az), 0.0])
        pts = [out * 0.05 + f * L * t - UPV * 0.35 * (t * L) ** 2 / L for t in np.linspace(0, 1, 6 if not lod else 3)]
        _strip_leaf(q, None, pts, rng.uniform(0.07, 0.1), rng.random(), 0.8)
    return q.mesh(name, ["NestFernLeaf"])


def ferns():
    mat("FernLeaf", (0.15, 0.4, 0.08), 0.6)
    mat("NestFernLeaf", (0.25, 0.5, 0.1), 0.3)
    col = new_col(); objs = []
    for nm, fn, seed in (("FernA", fern_pinnate, 801), ("FernB", fern_pinnate, 802), ("NestFern", fern_nest, 803)):
        for lod in (False, True):
            n2 = nm + ("_lod" if lod else "")
            objs.append(link(col, n2, fn(n2, seed, lod)))
    export(objs, "ferns.glb")
    info = {o.name: len(o.data.polygons) for o in objs}
    drop(col)
    return info


# ------------------------------------------------------------------ mangrove
def mangrove(col, name, seed, H):
    """Red mangrove (Rhizophora): a short trunk on a tangle of arching stilt roots, a few aerial
    roots dropping from the branches, and a dense dome of glossy dark leaves."""
    rng = np.random.default_rng(seed)
    bm = bmesh.new()
    th = H * rng.uniform(0.22, 0.3)        # height where the trunk leaves the root cage
    r0 = 0.09 + 0.01 * H
    trunk = [Vector((0, 0, th * 0.55)), Vector((0, 0, th)), Vector((0.1, 0.05, H * 0.45))]
    tube(bm, trunk, [r0 * 1.1, r0, r0 * 0.8], 8)
    for k in range(int(rng.integers(9, 14))):
        a = 2 * math.pi * k / 12 + rng.uniform(-0.25, 0.25)
        out = Vector((math.cos(a), math.sin(a), 0))
        h = rng.uniform(th * 0.45, th * 1.05)
        reach = rng.uniform(1.0, 2.2) * H / 6.0
        p0 = Vector((0, 0, h)) + out * r0 * 0.6
        p2 = out * reach + Vector((0, 0, -0.5))
        p1 = p0 + out * reach * 0.55 + Vector((0, 0, h * 0.35))
        pts = [p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t for t in np.linspace(0, 1, 9)]
        rr = r0 * rng.uniform(0.32, 0.45)
        tube(bm, pts, [rr * (1 - 0.35 * i / 8) for i in range(9)], 5)
    for k in range(int(rng.integers(3, 6))):     # aerial roots hanging from the lower branches
        a = rng.uniform(0, 2 * math.pi); out = Vector((math.cos(a), math.sin(a), 0))
        top = Vector((0, 0, H * rng.uniform(0.4, 0.55))) + out * rng.uniform(0.8, 1.8)
        tube(bm, [top, top + out * 0.15 - Vector((0, 0, top.z * 0.5)), Vector((top.x * 1.1, top.y * 1.1, -0.4))], [0.035, 0.03, 0.028], 5)
    P = dict(H=H, S=H * 0.95, sp=0.26, L=0.14, W=0.065, per=30, kind="rosette", droop=0.25, yellow=0.07, twig=0.45,
             twig_r=0.012, bend=0.5, gapf=1.0, inner=0.9)
    lobes = [(np.array([0, 0, H * 0.68]), np.array([H * 0.45, H * 0.42, H * 0.3]))]
    for i in range(int(rng.integers(3, 6))):
        a = rng.uniform(0, 2 * math.pi); r = rng.uniform(0.2, 0.42) * H
        lobes.append((np.array([math.cos(a) * r, math.sin(a) * r, H * rng.uniform(0.55, 0.78)]),
                      np.array([H * 0.26, H * 0.26, H * 0.2])))
    root = lambda c, rng: np.array([0.0, 0.0, H * 0.42])
    q, U, C, M, A, N = crown(rng, lobes, P, bm, r0 * 0.6, root, H * 0.4, Vector((seed * 0.11, 2.2, 0.4)))
    objs = [link(col, name + "Bark", bm_to_mesh(bm, name + "Bark", ["MangroveBark"]))]
    add_lods(col, objs, name + "Leaves", q, U, C, M, A, N, ["MangroveLeaf", "BushLeafYellow"], rng)
    return objs


def mangroves():
    mat("MangroveLeaf", (0.05, 0.2, 0.04), 0.3)
    mat("MangroveBark", (0.3, 0.25, 0.2), 0.8)
    col = new_col(); objs = []
    for i, (seed, H) in enumerate([(901, 5.5), (902, 7.0), (903, 4.2)]):
        objs += mangrove(col, f"Mangrove{i}", seed, H)
    export(objs, "mangroves.glb")
    info = {o.name: len(o.data.polygons) for o in objs}
    drop(col)
    return info
