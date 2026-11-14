# Round 7 assets (flora): the trees of the forest as real Seychelles species, grown branch by
# branch instead of the umbrella-shaped stand-ins of assets3, and the screwpine.
#   takamaka (Calophyllum inophyllum): short thick trunk, heavy spreading limbs, dense dark crown
#   badamier (Terminalia catappa): straight trunk, branches in horizontal tiers (pagoda), big leaves
#     in rosettes, a few of them red before they fall
#   vacoa (Pandanus): stilt roots, forked stems, tufts of long sword leaves, orange fruit heads
#   pisonia (Pisonia grandis): the seabirds' tree, for the colony's grove: pisonia_trees() -> pisonia.glb
# Run inside Blender (the empty start-up scene is fine):
#   ns = {"__file__": path}; exec(open(path).read(), ns); ns['forest_trees']()
# Blender +Z up. Trees are exported with their origin on the ground (roots below it).
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


def ensure_tree_mats():
    mat("TakamakaBark", (0.3, 0.27, 0.24), 0.9)
    mat("BadamierBark", (0.42, 0.4, 0.37), 0.9)
    mat("VacoaBark", (0.45, 0.4, 0.33), 0.9)
    mat("TakamakaLeaf", (0.05, 0.2, 0.04), 0.3)
    mat("BadamierLeaf", (0.12, 0.35, 0.06), 0.4)
    mat("BadamierRed", (0.7, 0.2, 0.04), 0.4)
    mat("TakamakaLeafOld", (0.3, 0.4, 0.08), 0.4)
    mat("TakamakaLeafFar", (0.05, 0.2, 0.04), 0.3)
    mat("VacoaLeaf", (0.15, 0.4, 0.08), 0.4)
    mat("VacoaDead", (0.4, 0.3, 0.17), 0.9)
    mat("VacoaFruit", (0.75, 0.4, 0.08), 0.6)
    mat("PisoniaBark", (0.6, 0.58, 0.54), 0.8)
    mat("PisoniaSprig", (0.2, 0.42, 0.1), 0.5)
    mat("PisoniaSprigOld", (0.5, 0.5, 0.12), 0.5)
    mat("PisoniaLeafFar", (0.2, 0.42, 0.1), 0.5)


class Wood:
    """Two bark meshes: the trunk and big limbs (solid: they get collision) and the thin twigs."""
    def __init__(self):
        self.thick = bmesh.new(); self.thin = bmesh.new()

    def tube(self, pts, radii, sides, thin=False):
        tube(self.thin if thin else self.thick, [Vector(p) for p in pts], radii, sides)

    def objects(self, col, name, bark):
        objs = [link(col, name + "Bark", bm_to_mesh(self.thick, name + "Bark", [bark]))]
        if len(self.thin.verts):
            objs.append(link(col, name + "Twigs", bm_to_mesh(self.thin, name + "Twigs", [bark])))
        return objs


def grow_branch(rng, wood, p, d, L, r, depth, P, tips):
    """One branch and, recursively, everything that grows from it. Side branches leave it
    alternately along its outer part; its own end carries on as a thinner branch."""
    nseg = P["nseg"][depth]
    pts = [np.array(p, float)]; dd = unit(d)
    for i in range(nseg):
        t = (i + 1) / nseg
        dd = unit(dd + rng.normal(0, P["wob"], 3) + UP * (P["up"][depth] * t - P["sag"][depth]))
        nxt = pts[-1] + dd * L / nseg
        if nxt[2] < P.get("floor", -9.0):
            # no wood at head height: a branch heading down there levels out instead (you walk
            # under the trees; only the leaves may brush your head)
            nxt[2] = P["floor"] + rng.uniform(0.0, 0.25)
            dd = unit(nxt - pts[-1])
        pts.append(nxt)
    rend = max(r * P["taper"], 0.006)
    radii = [r + (rend - r) * i / nseg for i in range(nseg + 1)]
    wood.tube(pts, radii, P["sides"][depth], thin=depth >= P["thin_from"])
    if depth >= P.get("shoots_from", 99):
        # short leafy side shoots all along the thin branches: they fill the crown between the tips
        s = rng.uniform(0.25, 0.55)
        while s < L - 0.2:
            f = s / L * nseg; i0 = min(int(f), nseg - 1); f -= i0
            q = pts[i0] * (1 - f) + pts[i0 + 1] * f
            tang = unit(pts[i0 + 1] - pts[i0])
            a, b = perp_basis(tang)
            ang = rng.uniform(0, 2 * math.pi)
            sd = unit(a * math.cos(ang) + b * math.sin(ang) + tang * 0.5 + UP * 0.45)
            sl = rng.uniform(0.3, 0.55)
            wood.tube([q, q + sd * sl], [0.012, 0.007], 3, thin=True)
            tips.append((q + sd * sl, sd, -sl))   # (negative length marks a side shoot)
            s += rng.uniform(0.35, 0.65)
    if depth >= P["maxd"]:
        tips.append((pts[-1], unit(pts[-1] - pts[-2]), L))
        return
    nk = int(rng.integers(P["kids"][depth][0], P["kids"][depth][1] + 1))
    a0 = rng.uniform(0, 2 * math.pi)
    for k in range(nk):
        t = P["first"] + (0.97 - P["first"]) * (k + rng.uniform(0.25, 0.75)) / nk
        f = t * nseg; i0 = min(int(f), nseg - 1); f -= i0
        q = pts[i0] * (1 - f) + pts[i0 + 1] * f
        if "forks" in P:
            P["forks"].append((q.copy(), depth))   # (where a branch leaves this one: pisonia())
        tang = unit(pts[i0 + 1] - pts[i0])
        a, b = perp_basis(tang)
        ang = a0 + k * 2.39996 + rng.uniform(-0.5, 0.5)
        side = unit(a * math.cos(ang) + b * math.sin(ang) + UP * P["lift"])
        sp = rng.uniform(*P["spread"][depth])
        nd = unit(tang * math.cos(sp) + side * math.sin(sp))
        grow_branch(rng, wood, q, nd, L * rng.uniform(*P["lenf"][depth]) * (1.15 - 0.45 * t),
                    (r + (rend - r) * t) * P["kidr"], depth + 1, P, tips)
    grow_branch(rng, wood, pts[-1], unit(dd + rng.normal(0, 0.12, 3)), L * rng.uniform(0.36, 0.5), rend * 0.92,
                depth + 1, P, tips)


def sprig_cards(rng, tip, d, n, L, W, spray):
    """n leafy-twig cards (the leaf shader draws pairs of leaves along each one) set around the last
    `spray` meters of a twig that ends at tip. Their planes face every way, so the crown looks as
    full from the side as from below."""
    d = unit(d); a, b = perp_basis(d)
    t = rng.uniform(0, 1, n)
    ang = np.arange(n) * 2.39996 + rng.uniform(0, 0.6, n)
    radial = np.outer(np.cos(ang), a) + np.outer(np.sin(ang), b)
    base = tip - np.outer(t * spray, d)
    sp = rng.uniform(0.45, 1.15, n) * (0.3 + 0.7 * t)   # at the tip the cards carry the twig on
    dirs = np.outer(np.cos(sp), d) + radial * np.sin(sp)[:, None]
    dirs[:, 2] -= rng.uniform(0.0, 0.3, n)
    dirs = unit(dirs)
    hint = unit(rng.normal(0, 1, (n, 3)) + UP * 0.7)
    return leaf_cards(base, dirs, hint, L * rng.uniform(0.8, 1.2, n), W * rng.uniform(0.85, 1.15, n))


def foliage(rng, clusters, yellow):
    """Leaf arrays for a list of clusters (tip, direction, leaves, length, width, kind, droop,
    spray length): shading normals that around the whole crown, and the leaves deep inside it darker
    (vertex alpha). kind "sprig": leafy-twig cards instead of single leaves."""
    Q = []; UU = []; NN = []
    for tip, d, n, L, W, kind, droop, spray in clusters:
        if kind == "sprig":
            q, U, nrm = sprig_cards(rng, np.array(tip), d, n, L, W, spray)
        else:
            q, U, nrm = leaf_cluster(rng, np.array(tip), d, n, L, W, kind, droop=droop, spray_len=spray)
        Q.append(q); UU.append(U); NN.append(nrm)
    q = np.concatenate(Q); U = np.concatenate(UU); nrm = np.concatenate(NN)
    mid = q.mean(1)
    cen = (mid.max(0) + mid.min(0)) / 2
    rad = np.maximum((mid.max(0) - mid.min(0)) / 2, 0.5)
    rel = (mid - cen) / rad
    depth = np.linalg.norm(rel, axis=1)
    N = unit(unit(rel / rad) * 0.55 + nrm * 0.3 + UP * 0.25)
    zr = np.clip((mid[:, 2] - mid[:, 2].min()) / max(np.ptp(mid[:, 2]), 0.1), 0, 1)
    A = np.clip(0.2 + 0.8 * np.clip((depth - 0.3) / 0.5, 0, 1), 0.15, 1.0) * (0.7 + 0.3 * zr)
    C = rng.random(len(q))
    M = (rng.random(len(q)) < yellow).astype(np.int32)
    return q, U, C, M, A, N


def trunk_base(rng, wood, top, r0, H, sides=12, roots=(4, 7)):
    """A trunk from below the ground up to `top`, flared where it meets the ground, with a few
    surface roots running out from the flare."""
    base = np.array([0.0, 0.0, -1.4])
    pts = []; radii = []
    w = rng.normal(0, 0.02 * H, 2)
    for t in np.linspace(0, 1, 8):
        p = base + (np.array(top) - base) * t
        p[:2] += w * math.sin(math.pi * t)
        pts.append(p)
        radii.append(r0 * (1 + 0.45 * math.exp(-max(p[2], 0.0) / (0.035 * H))) * (1 - 0.12 * t))
    wood.tube(pts, radii, sides)
    for k in range(int(rng.integers(roots[0], roots[1]))):
        a = rng.uniform(0, 2 * math.pi)
        out = np.array([math.cos(a), math.sin(a), 0.0])
        reach = r0 * rng.uniform(3.5, 6.0)
        p0 = np.array([0, 0, r0 * 1.6]) + out * r0 * 0.5
        p2 = out * reach + np.array([0, 0, -0.5])
        p1 = out * reach * 0.45 + np.array([0, 0, r0 * 0.5])
        rp = [p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t for t in np.linspace(0, 1, 6)]
        wood.tube(rp, [r0 * 0.5 * (1 - 0.75 * i / 5) for i in range(6)], 6)
    return pts, radii


# ------------------------------------------------------------------ takamaka
TAKA = dict(maxd=4, thin_from=3, shoots_from=3, floor=2.7, nseg={1: 6, 2: 5, 3: 4, 4: 2}, sides={1: 10, 2: 7, 3: 5, 4: 4}, wob=0.12,
            taper=0.55, up={1: 0.07, 2: 0.12, 3: 0.1, 4: 0.05}, sag={1: 0.02, 2: 0.05, 3: 0.04, 4: 0.03},
            kids={1: (3, 5), 2: (2, 4), 3: (2, 3)}, first=0.25, lift=0.45, kidr=0.62,
            spread={1: (0.6, 1.15), 2: (0.6, 1.1), 3: (0.5, 1.0)}, lenf={1: (0.5, 0.7), 2: (0.5, 0.68), 3: (0.5, 0.7)})


def takamaka(col, name, seed, H):
    rng = np.random.default_rng(seed)
    wood = Wood(); tips = []
    r0 = 0.02 * H + 0.07
    lean = unit([rng.normal(), rng.normal(), 0]) * rng.uniform(0.05, 0.32)
    h0 = max(H * rng.uniform(0.17, 0.25), 2.9)
    fork = np.array([lean[0] * h0, lean[1] * h0, h0])
    trunk_base(rng, wood, fork + np.array([0, 0, 0.3]), r0, H)
    nl = int(rng.integers(3, 6))
    a0 = rng.uniform(0, 2 * math.pi)
    for i in range(nl):
        az = a0 + 2 * math.pi * i / nl + rng.uniform(-0.35, 0.35)
        incl = rng.uniform(0.6, 1.15) if i else rng.uniform(0.15, 0.45)   # one limb carries the top
        d = np.array([math.cos(az) * math.sin(incl), math.sin(az) * math.sin(incl), math.cos(incl)]) + lean * 0.6
        L = H * rng.uniform(0.36, 0.44) * (1.12 - 0.2 * incl)
        grow_branch(rng, wood, fork - unit(d) * 0.1, d, L, r0 * rng.uniform(0.5, 0.62), 1, TAKA, tips)
    clusters = []
    for p, d, L in tips:
        if L < 0:   # side shoot
            clusters.append((p, d, int(rng.uniform(11, 16)), 0.44, 0.38, "sprig", 0.0, -L))
        else:
            clusters.append((p, d, int(rng.uniform(22, 30)), 0.44, 0.38, "sprig", 0.0, min(0.9, L * 0.9)))
    q, U, C, M, A, N = foliage(rng, clusters, 0.04)
    objs = wood.objects(col, name, "TakamakaBark")
    # The twig cards are big, and what they cost is the area they cover on screen. So far fewer of
    # them further away; beyond 85 m the few that remain are drawn as single big leaves (no twigs to
    # work out per pixel).
    add_lods(col, objs, name + "Leaves", q, U, C, M, A, N, ["TakamakaLeaf", "TakamakaLeafOld"], rng, lods=(("_lod", 0.15, 1.6),))
    keep = rng.random(len(q)) < 0.055
    q2 = q[keep]; cen = q2.mean(1, keepdims=True); q2 = cen + (q2 - cen) * 2.1
    nm = name + "Leaves_lod2"
    objs.append(link(col, nm, quads_mesh(nm, q2, U[keep], C[keep], M[keep] * 0, ["TakamakaLeafFar"], A[keep], N[keep])))
    return objs, len(q), len(tips)


# ------------------------------------------------------------------ badamier
def badamier(col, name, seed, H):
    rng = np.random.default_rng(seed)
    wood = Wood(); clusters = []
    r0 = 0.014 * H + 0.05
    lean = np.array([rng.normal(), rng.normal(), 0.0]) * 0.025 * H
    top = np.array([lean[0], lean[1], H * 0.9])
    tp, tr = trunk_base(rng, wood, top, r0, H, sides=10, roots=(3, 6))
    # the trunk thins out to the leading shoot above the last tier
    wood.tube([tp[-1], tp[-1] + np.array([0, 0, H * 0.05]), tp[-1] + np.array([0.05, 0, H * 0.1])], [tr[-1], tr[-1] * 0.5, 0.02], 8)
    clusters.append((tp[-1] + np.array([0.05, 0, H * 0.1]), UP, 18, 0.25, 0.13, "rosette", 0.3, 0.3))

    def on_trunk(z):
        t = (z + 1.4) / (top[2] + 1.4) * 7; i = min(int(t), 6); f = t - i
        return tp[i] * (1 - f) + tp[i + 1] * f, tr[i] * (1 - f) + tr[i + 1] * f

    def rosette(p, d, big=1.0):
        clusters.append((p, unit(d), int(rng.uniform(24, 34) * big), 0.3 * rng.uniform(0.85, 1.1), 0.16, "rosette", 0.3, 0.3))

    def spurs(pts, rr, start):
        """Short upright shoots along the outer part of a branch, each with its rosette."""
        length = sum(np.linalg.norm(pts[i + 1] - pts[i]) for i in range(len(pts) - 1))
        s = start * length + rng.uniform(0.1, 0.4)
        while s < length - 0.15:
            acc = 0.0
            for i in range(len(pts) - 1):
                seg = np.linalg.norm(pts[i + 1] - pts[i])
                if acc + seg >= s:
                    p = pts[i] + (pts[i + 1] - pts[i]) * (s - acc) / seg
                    side = unit(np.cross(pts[i + 1] - pts[i], UP)) * rng.uniform(-0.12, 0.12)
                    e = p + UP * rng.uniform(0.1, 0.22) + side
                    wood.tube([p, e], [0.014, 0.01], 4, thin=True)
                    rosette(e, UP + side * 2 + rng.normal(0, 0.15, 3), 0.85)
                    break
                acc += seg
            s += rng.uniform(0.32, 0.5)

    def arm(p, az, elev, L, r, level):
        """A tier branch: nearly level, turning up at the end; side arms fan out in its plane."""
        out = np.array([math.cos(az), math.sin(az), 0.0])
        nseg = 6 if level == 0 else 4
        pts = [np.array(p, float)]
        for i in range(nseg):
            t = (i + 1) / nseg
            e = elev - 0.12 * math.sin(math.pi * min(t * 1.3, 1.0)) + (0.55 * max(0.0, t - 0.75) / 0.25)
            az2 = az + rng.normal(0, 0.06)
            dd = np.array([math.cos(az2) * math.cos(e), math.sin(az2) * math.cos(e), math.sin(e)])
            pts.append(pts[-1] + dd * L / nseg)
        rend = max(r * 0.4, 0.014)
        wood.tube(pts, [r + (rend - r) * i / nseg for i in range(nseg + 1)], 7 if level == 0 else 5, thin=level > 0)
        rosette(pts[-1], unit(pts[-1] - pts[-2]) * 0.6 + UP)
        spurs(pts, r, 0.3 if level == 0 else 0.15)
        if level < (2 if L > 2.2 else 1):
            side = 1 if rng.random() < 0.5 else -1
            for t in ((0.38, 0.66, 0.86) if level == 0 else (0.5,)):
                f = t * nseg; i0 = min(int(f), nseg - 1); f -= i0
                q = pts[i0] * (1 - f) + pts[i0 + 1] * f
                arm(q, az + side * rng.uniform(0.6, 0.95), elev + rng.uniform(0.0, 0.12), L * (1 - t) * rng.uniform(0.9, 1.25) + 0.5,
                    (r + (rend - r) * t) * 0.6, level + 1)
                side = -side

    z = max(H * rng.uniform(0.24, 0.3), 3.3)   # the lowest tier clears a walker's head
    z0 = z
    while z < top[2] - 0.02 * H:
        t = (z - z0) / (top[2] - z0)
        nb = int(rng.integers(4, 6))
        ph = rng.uniform(0, 2 * math.pi)
        for i in range(nb):
            p, r = on_trunk(z + rng.uniform(-0.12, 0.12))
            az = ph + 2 * math.pi * i / nb + rng.uniform(-0.2, 0.2)
            arm(p, az, rng.uniform(0.03, 0.2) + 0.3 * t, H * (0.4 - 0.27 * t) * rng.uniform(0.85, 1.1), max(r * 0.42, 0.03), 0)
        z += H * rng.uniform(0.1, 0.135)
    q, U, C, M, A, N = foliage(rng, clusters, 0.055)
    objs = wood.objects(col, name, "BadamierBark")
    add_lods(col, objs, name + "Leaves", q, U, C, M, A, N, ["BadamierLeaf", "BadamierRed"], rng,
             lods=(("_lod", 0.27, 1.75), ("_lod2", 0.07, 3.0)))
    return objs, len(q), len(clusters)


# ------------------------------------------------------------------ pisonia (the seabird tree)
PISO = dict(maxd=3, thin_from=4, shoots_from=3, floor=2.7, nseg={1: 6, 2: 5, 3: 4}, sides={1: 10, 2: 7, 3: 5}, wob=0.15,
            taper=0.5, up={1: 0.05, 2: 0.1, 3: 0.1}, sag={1: 0.03, 2: 0.06, 3: 0.04},
            kids={1: (3, 4), 2: (2, 4)}, first=0.3, lift=0.4, kidr=0.62,
            spread={1: (0.6, 1.15), 2: (0.6, 1.1)}, lenf={1: (0.5, 0.7), 2: (0.5, 0.7)})


def pisonia(col, name, seed, H):
    """Pisonia grandis, the tree the seabirds nest in: a massive pale trunk that divides low into
    a few heavy limbs, a broad round crown, big soft light-green leaves in whorls at the ends of
    the branches. All its branches are in <name>Bark (the colony sets nests and birds on it); only
    the leafy side shoots are in <name>Twigs.
    Returns the objects, the leaf count, and the places for nests: [x, y, z, r] in Blender
    coordinates, forks of the limbs (r 0.6) and the top of the crown (r 1.0)."""
    rng = np.random.default_rng(seed)
    wood = Wood(); tips = []
    P = dict(PISO); P["forks"] = []
    r0 = 0.028 * H + 0.1
    lean = unit([rng.normal(), rng.normal(), 0]) * rng.uniform(0.03, 0.2)
    h0 = max(H * rng.uniform(0.2, 0.27), 2.9)
    fork = np.array([lean[0] * h0, lean[1] * h0, h0])
    trunk_base(rng, wood, fork + np.array([0, 0, 0.3]), r0, H, sides=14, roots=(3, 6))
    nl = int(rng.integers(3, 5))
    a0 = rng.uniform(0, 2 * math.pi)
    for i in range(nl):
        az = a0 + 2 * math.pi * i / nl + rng.uniform(-0.35, 0.35)
        incl = rng.uniform(0.55, 1.05) if i else rng.uniform(0.1, 0.4)   # one limb carries the top
        d = np.array([math.cos(az) * math.sin(incl), math.sin(az) * math.sin(incl), math.cos(incl)]) + lean * 0.6
        L = H * rng.uniform(0.38, 0.46) * (1.12 - 0.2 * incl)
        grow_branch(rng, wood, fork - unit(d) * 0.1, d, L, r0 * rng.uniform(0.5, 0.6), 1, P, tips)
    # the crown is a closed, shady roof: leafy-twig cards (the leaf shader draws pairs of big
    # leaves along each) around the end of every branch and on the side shoots along it
    clusters = []
    for p, d, L in tips:
        if L < 0:   # side shoot
            clusters.append((p, d, int(rng.uniform(12, 17)), 0.62, 0.52, "sprig", 0.0, -L))
        else:
            clusters.append((p, d, int(rng.uniform(24, 32)), 0.62, 0.52, "sprig", 0.0, min(0.9, L * 0.9)))
    q, U, C, M, A, N = foliage(rng, clusters, 0.03)
    objs = wood.objects(col, name, "PisoniaBark")
    add_lods(col, objs, name + "Leaves", q, U, C, M, A, N, ["PisoniaSprig", "PisoniaSprigOld"], rng, lods=(("_lod", 0.16, 1.6),))
    keep = rng.random(len(q)) < 0.06
    q2 = q[keep]; cen = q2.mean(1, keepdims=True); q2 = cen + (q2 - cen) * 2.1
    nm = name + "Leaves_lod2"
    objs.append(link(col, nm, quads_mesh(nm, q2, U[keep], C[keep], M[keep] * 0, ["PisoniaLeafFar"], A[keep], N[keep])))
    tips = [t for t in tips if t[2] > 0]
    # places for nests: forks, well apart; and the top of the crown (for the displaying frigatebirds)
    # (on the big limbs first, under the roof of leaves, where the birds are seen from the ground;
    # further up the nests are hidden in the foliage)
    forks = [(f, depth) for f, depth in P["forks"] if f[2] > H * 0.3 and math.hypot(f[0], f[1]) > 0.8]
    forks.sort(key=lambda fd: (fd[1], -math.hypot(fd[0][0], fd[0][1])))
    spots = []
    for f, depth in forks:
        if all(np.linalg.norm(f - np.array(o[:3])) > 1.4 for o in spots) and len(spots) < 15:
            spots.append([float(f[0]), float(f[1]), float(f[2]), 0.6])
    top = max(tips, key=lambda t: t[0][2])[0]
    spots.append([float(top[0]), float(top[1]), float(top[2]), 1.0])
    return objs, len(q), spots


def pisonia_trees(fname="pisonia.glb", keep=False):
    """Pis0-2: <Name>Bark, <Name>Twigs and <Name>Leaves(+_lod, _lod2), for the grove of the seabird colony.
    Adds their nest places to assets/models/tree_tips.json (in Godot's coordinates, like the
    entries of the trees they replace)."""
    import json
    ensure_tree_mats()
    col = new_col(); objs = []; info = {}; tips = {}
    for i, (seed, H) in enumerate([(731, 10.5), (732, 11.5), (733, 12.5)]):
        o, n, spots = pisonia(col, f"Pis{i}", seed, H)
        objs += o; info[f"Pis{i}"] = [n, len(spots)]
        tips[f"Pis{i}"] = [[x, z, -y, r] for x, y, z, r in spots]
    info["polys"] = {o.name: len(o.data.polygons) for o in objs}
    if keep:
        return info, col
    export(objs, fname)
    drop(col)
    path = os.path.join(ROOT, "assets", "models", "tree_tips.json")
    data = json.load(open(path))
    data.update(tips)
    json.dump(data, open(path, "w"))
    return info


# ------------------------------------------------------------------ vacoa (screwpine)
def sword_leaves(rng, heads, lod):
    """Tufts of long, keeled sword leaves in a spiral: the young ones upright in the middle, the
    older ones arching out and bending down halfway along. UV.x across, UV.y along (blade shader)."""
    P = []; U = []; C = []; M = []
    for c, axis, size in heads:
        axis = unit(axis); a, b = perp_basis(axis)
        n = int((40 if not lod else 18) * size)
        for i in range(n):
            age = (i + rng.uniform(0, 0.8)) / n
            dead = age > 0.88 and rng.random() < 0.6
            az = i * 2.39996
            radial = a * math.cos(az) + b * math.sin(az)
            L = size * rng.uniform(0.95, 1.4) * (0.6 + 0.4 * min(1.0, age * 4))
            W = 0.075 * size * (2.0 if lod else 1.0)
            tilt = 0.25 + 1.25 * age          # angle from the stem axis at the base
            d = unit(axis * math.cos(tilt) + radial * math.sin(tilt))
            base = np.array(c) - axis * (0.28 * size * age) + radial * 0.035 * size
            bend = (0.9 + 1.4 * age) * rng.uniform(0.7, 1.2)   # how far the outer half folds down
            if dead:
                d = unit(radial * 0.22 - axis); bend = 0.15; L *= 0.75; W *= 0.6
            nseg = 3 if lod else 6
            side = unit(np.cross(d, UP) if abs(d[2]) < 0.95 else np.cross(d, radial))
            pts = [base]; dirs = [d]
            for s in range(nseg):
                t = (s + 1) / nseg
                k = bend * max(0.0, t - 0.4) / 0.6 * (1.6 / nseg)
                d = unit(d - UP * k)
                pts.append(pts[-1] + d * L / nseg); dirs.append(d)
            cr = rng.random()
            for s in range(nseg):
                y0 = s / nseg; y1 = (s + 1) / nseg
                rows = []
                for p, dd, y in ((pts[s], dirs[s], y0), (pts[s + 1], dirs[s + 1], y1)):
                    up = unit(np.cross(side, dd))
                    w = W * (1 - 0.25 * y)
                    rows.append((p - side * w + up * w * 0.45, p, p + side * w + up * w * 0.45))
                if lod:
                    P.append([rows[0][0], rows[0][2], rows[1][2], rows[1][0]])
                    U.append([[0, y0], [1, y0], [1, y1], [0, y1]]); C.append(cr); M.append(1 if dead else 0)
                else:
                    for k, (x0, x1) in enumerate(((0.0, 0.5), (0.5, 1.0))):
                        P.append([rows[0][k], rows[0][k + 1], rows[1][k + 1], rows[1][k]])
                        U.append([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]); C.append(cr); M.append(1 if dead else 0)
    return np.array(P, float), np.array(U, float), np.array(C), np.array(M)


def vacoa(col, name, seed, H, fruit):
    rng = np.random.default_rng(seed)
    wood = Wood()
    r0 = 0.05 + 0.012 * H
    hs = rng.uniform(0.7, 1.2) * (0.6 + H / 10)        # where the stilt roots join the stem
    lean = np.array([rng.normal(), rng.normal(), 0.0]) * 0.08
    heads = []; fruit_at = []

    def stem(p, d, L, r, level):
        pts = [np.array(p, float)]; dd = unit(d)
        for i in range(4):
            dd = unit(dd + rng.normal(0, 0.06, 3) + UP * 0.22)
            pts.append(pts[-1] + dd * L / 4)
        wood.tube(pts, [r * (1 - 0.06 * i) for i in range(5)], 8)
        if level < 2 and (level == 0 or rng.random() < 0.55) and L > 0.7:
            nb = int(rng.integers(2, 4))
            a0 = rng.uniform(0, 2 * math.pi)
            for k in range(nb):
                az = a0 + 2 * math.pi * k / nb + rng.uniform(-0.4, 0.4)
                nd = unit(dd * 0.75 + np.array([math.cos(az), math.sin(az), 0.15]))
                stem(pts[-1] - dd * 0.05, nd, L * rng.uniform(0.5, 0.75), r * 0.8, level + 1)
        else:
            heads.append((pts[-1] + dd * 0.1, unit(dd + UP * 0.5), rng.uniform(0.85, 1.15)))
            fruit_at.append((pts[-1], dd))

    foot = np.array([0, 0, -0.4])
    stem(foot, UP + lean, H * 0.5 + 0.4, r0, 0)
    # the cone of stilt roots
    for k in range(int(rng.integers(9, 15))):
        a = 2 * math.pi * k / 11 + rng.uniform(-0.25, 0.25)
        out = np.array([math.cos(a), math.sin(a), 0.0])
        h = rng.uniform(hs * 0.45, hs * 1.15)
        reach = (0.3 + 0.75 * h) * rng.uniform(0.75, 1.2)
        p0 = np.array([lean[0] * h, lean[1] * h, h]) + out * r0 * 0.5
        p2 = out * reach + np.array([0, 0, -0.45])
        p1 = (p0 + p2) / 2 + out * reach * 0.12 + np.array([0, 0, 0.12 * h])
        pts = [p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t for t in np.linspace(0, 1, 6)]
        rr = r0 * rng.uniform(0.3, 0.42)
        wood.tube(pts, [rr] * 6, 6)
    objs = wood.objects(col, name, "VacoaBark")
    for lod in (False, True):
        lr = np.random.default_rng(seed + 7)
        P, U, C, M = sword_leaves(lr, heads, lod)
        nm = name + "Leaves" + ("_lod" if lod else "")
        A = np.ones(len(P))
        objs.append(link(col, nm, quads_mesh(nm, P, U, C, M, ["VacoaLeaf", "VacoaDead"], A)))
    if fruit:
        bm = bmesh.new()
        for p, dd in fruit_at[:: 2]:
            a, b = perp_basis(dd)
            az = rng.uniform(0, 2 * math.pi)
            out = a * math.cos(az) + b * math.sin(az)
            top = np.array(p) + out * 0.1 - dd * 0.05
            c = top + out * 0.12 - UP * 0.3
            tube(bm, [Vector(top), Vector(top + out * 0.1 - UP * 0.05), Vector(c + UP * 0.1)], [0.022, 0.02, 0.018], 5)
            before = set(bm.verts)
            R = rng.uniform(0.1, 0.13)
            bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0,
                                       matrix=Matrix.Translation(Vector(c)) @ Matrix.Diagonal((R, R, R * 1.15, 1)))
            for v in bm.verts:
                if v not in before:   # the knobbly segments of the fruit head
                    dv = (v.co - Vector(c)).normalized()
                    v.co += dv * 0.012 * noise.cell(dv * 4.5 + Vector((seed, 0, 0)))
        objs.append(link(col, name + "Fruit", bm_to_mesh(bm, name + "Fruit", ["VacoaFruit"])))
    return objs, len(heads)


# ------------------------------------------------------------------ export
def forest_trees(fname="forest_trees.glb", keep=False, only=None):
    """<Name>Bark (trunk and limbs, origin on the ground), <Name>Twigs, <Name>Leaves(+_lod, _lod2)
    for Taka0-2 and Bad0-2; Vacoa0-2 with Bark, Leaves(+_lod) and (two of them) Fruit."""
    ensure_tree_mats()
    col = new_col(); objs = []; info = {}
    for i, (seed, H) in enumerate([(701, 12.5), (702, 15.0), (703, 17.0)]):
        if only and not f"Taka{i}" in only: continue
        o, n, t = takamaka(col, f"Taka{i}", seed, H); objs += o; info[f"Taka{i}"] = [n, t]
    for i, (seed, H) in enumerate([(711, 10.5), (712, 13.0), (713, 15.5)]):
        if only and not f"Bad{i}" in only: continue
        o, n, t = badamier(col, f"Bad{i}", seed, H); objs += o; info[f"Bad{i}"] = [n, t]
    for i, (seed, H, fruit) in enumerate([(721, 3.6, True), (722, 5.2, False), (723, 6.4, True)]):
        if only and not f"Vacoa{i}" in only: continue
        o, t = vacoa(col, f"Vacoa{i}", seed, H, fruit); objs += o; info[f"Vacoa{i}"] = t
    info["polys"] = {o.name: len(o.data.polygons) for o in objs}
    if keep:
        return info, col
    export(objs, fname)
    drop(col)
    return info
