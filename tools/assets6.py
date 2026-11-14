# Round 6 assets: wings for the birds and the flying fox. Run inside Blender:
#   ns = {"__file__": path}; exec(open(path).read(), ns); ns['wings']()
# Reuses the helpers from assets4.py.
#
# One right wing per kind, lying flat with its origin at the shoulder: +X out along the span,
# +Y forward. It is a grid of quads (UV.x = 0 shoulder .. 1 tip, UV.y = 0 leading .. 1 trailing
# edge) with a little camber, which shaders/wing.gdshader bends, folds and twists; the left wing is
# the same mesh mirrored by the shader. flight.gd swaps these in for the old flat wing parts.
import bpy, bmesh, numpy as np, math
from mathutils import Vector, Matrix

import os
# The project's folder, found from this file's place. Run in Blender, give the path along:
#   ns = {"__file__": path}; exec(open(path).read(), ns)
# (or name the folder in the environment variable TROPICAL_ISLAND; failing both, the folder
# Blender was started in is taken).
ROOT = os.environ.get("TROPICAL_ISLAND") or os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__") or os.path.join(os.getcwd(), "tools", "x"))))
exec(open(os.path.join(ROOT, "tools", "assets4.py")).read(), globals())


def edge(pts, s, smooth=True):
    """y of an edge at span fraction s, through the points (s, y): a smooth curve, or straight lines."""
    xs = np.array([q[0] for q in pts], float); ys = np.array([q[1] for q in pts], float)
    if not smooth:
        return float(np.interp(s, xs, ys))
    # cubic Hermite with finite-difference tangents, limited so the curve does not overshoot
    d = np.diff(ys) / np.diff(xs)
    m = np.concatenate(([d[0]], (d[:-1] + d[1:]) / 2, [d[-1]]))
    i = int(np.clip(np.searchsorted(xs, s) - 1, 0, len(xs) - 2))
    h = xs[i + 1] - xs[i]; t = (s - xs[i]) / h
    return float((2 * t ** 3 - 3 * t ** 2 + 1) * ys[i] + (t ** 3 - 2 * t ** 2 + t) * h * m[i]
                 + (-2 * t ** 3 + 3 * t ** 2) * ys[i + 1] + (t ** 3 - t ** 2) * h * m[i + 1])


def wing(col, name, half, lead, trail, material, nspan=16, nchord=4, camber=0.06, smooth_trail=True):
    bm = bmesh.new(); uvl = bm.loops.layers.uv.verify()
    grid = []
    for i in range(nspan + 1):
        s = i / nspan
        yl = edge(lead, s); yt = edge(trail, s, smooth_trail)
        row = []
        for j in range(nchord + 1):
            c = j / nchord
            row.append(bm.verts.new((s * half, yl + (yt - yl) * c, camber * (yl - yt) * 4 * c * (1 - c))))
        grid.append(row)
    for i in range(nspan):
        for j in range(nchord):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            for l, t in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                l[uvl].uv = (t[0] / nspan, t[1] / nchord)
    me = bm_to_mesh(bm, name, [material])
    return link(col, name, me)


def wings():
    col = new_col(); objs = []
    m = lambda n: mat(n, (0.8, 0.8, 0.8), 0.7)
    # greater crested tern (the beach terns; 1.28 m across): long, narrow, pointed
    objs.append(wing(col, "TernWing", 0.585,
                     [(0, 0.054), (0.2, 0.063), (0.42, 0.072), (0.7, 0.024), (1.0, -0.115)],
                     [(0, -0.098), (0.25, -0.091), (0.42, -0.078), (0.7, -0.082), (0.9, -0.102), (1.0, -0.122)], m("WingTern")))
    # brown noddy: broader
    objs.append(wing(col, "NoddyWing", 0.353,
                     [(0, 0.032), (0.42, 0.042), (0.7, 0.014), (1.0, -0.082)],
                     [(0, -0.06), (0.42, -0.054), (0.7, -0.057), (0.9, -0.074), (1.0, -0.09)], m("WingNoddy")))
    # white tern: broad, rounded, almost translucent wings
    objs.append(wing(col, "WhiteTernWing", 0.347,
                     [(0, 0.03), (0.42, 0.038), (0.7, 0.014), (1.0, -0.07)],
                     [(0, -0.054), (0.42, -0.05), (0.7, -0.054), (0.9, -0.068), (1.0, -0.078)], m("WingWhiteTern")))
    # frigatebird: very long and narrow, sharply angled at the wrist
    objs.append(wing(col, "FrigateWing", 0.982,
                     [(0, 0.06), (0.2, 0.078), (0.42, 0.105), (0.7, 0.02), (1.0, -0.3)],
                     [(0, -0.105), (0.42, -0.085), (0.7, -0.1), (0.9, -0.215), (1.0, -0.31)], m("WingFrigate"), nspan=18))
    # flying fox: a membrane scalloped between the fingers
    objs.append(wing(col, "BatWing", 0.62,
                     [(0, 0.03), (0.29, 0.07), (0.55, 0.05), (0.8, 0.0), (1.0, -0.06)],
                     [(0, -0.16), (0.16, -0.22), (0.35, -0.13), (0.48, -0.2), (0.65, -0.08), (0.76, -0.14), (1.0, -0.07)],
                     m("WingBat"), nspan=24, camber=0.1, smooth_trail=False))
    export(objs, "wings.glb", vc='NONE')
    drop(col)
    return len(objs)


def flying_fox():
    """Seychelles fruit bat: dark body, golden mantle and russet, fox-like head, hind legs trailing.
    Empties BatWingL/R at the shoulders take the bendable wings (flight.gd)."""
    col = new_col()
    fur = mat("BatFur", (0.02, 0.012, 0.008), 0.9)
    mane = mat("BatMane", (0.4, 0.2, 0.055), 0.85)
    eye = mat("BatEye", (0.005, 0.005, 0.005), 0.2)
    bm = bmesh.new()
    # body: rump to shoulders
    loft(bm, [(Vector((0, -0.15, 0.0)), 0.012, 0.012, 0.0), (Vector((0, -0.12, 0.0)), 0.04, 0.035, 0.1), (Vector((0, -0.05, -0.003)), 0.062, 0.056, 0.3),
              (Vector((0, 0.03, -0.002)), 0.07, 0.062, 0.5), (Vector((0, 0.08, 0.002)), 0.06, 0.055, 0.6), (Vector((0, 0.11, 0.006)), 0.045, 0.045, 0.7)], 12, mat_index=0)
    # mantle, head and the long muzzle
    loft(bm, [(Vector((0, 0.065, 0.004)), 0.061, 0.057, 0.6), (Vector((0, 0.11, 0.01)), 0.052, 0.052, 0.7), (Vector((0, 0.15, 0.016)), 0.042, 0.045, 0.8),
              (Vector((0, 0.185, 0.016)), 0.037, 0.039, 0.86), (Vector((0, 0.21, 0.01)), 0.023, 0.023, 0.92), (Vector((0, 0.245, 0.006)), 0.016, 0.015, 0.97),
              (Vector((0, 0.262, 0.004)), 0.008, 0.008, 1.0)], 12, mat_index=1)
    for s in (1, -1):
        ball(bm, (s * 0.028, 0.196, 0.03), (0.0075, 0.0075, 0.0075), 2, 6, 4)
        # pointed ears
        tube(bm, [Vector((s * 0.024, 0.162, 0.045)), Vector((s * 0.034, 0.156, 0.082))], [0.013, 0.002], 5, mat_index=0)
        # hind legs trailing behind, feet together
        tube(bm, [Vector((s * 0.03, -0.11, -0.012)), Vector((s * 0.052, -0.19, -0.004)), Vector((s * 0.04, -0.262, -0.01))],
             [0.015, 0.009, 0.006], 5, mat_index=0)
        ball(bm, (s * 0.04, -0.27, -0.012), (0.009, 0.014, 0.006), 0, 5, 4)
    body = link(col, "Bat", bm_to_mesh(bm, "Bat", [fur, mane, eye]))
    objs = [body]
    for s, side in ((1, "R"), (-1, "L")):
        e = bpy.data.objects.new("BatWing" + side, None); col.objects.link(e)
        e.parent = body; e.location = (s * 0.05, 0.04, 0.02)
        objs.append(e)
    export(objs, "flying_fox.glb", vc='NONE')
    drop(col)
    return len(objs)
