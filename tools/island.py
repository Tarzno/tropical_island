# Builds the extended island terrain, land-cover mask, extra rock placements and the
# heightmap for the Godot beach. Run inside Blender with tropical_beach.blend open.
#
# SINCE 2026-11-10 THIS IS ONLY THE FIRST STAGE. Its output of 2026-11-08 is frozen in
# tools/terrain_base.npz (R = terrain height, rocks = height of the original boulders above it,
# 2048 x 2048, world x/z in [-256, 256]); tools/terrain2.py (plain Python, no Blender) makes the
# final heightmap.exr, landmask.png, terrain_ext.glb and the "taper" entry of island.json from
# that. build() below still writes those files directly: running it overwrites the final terrain
# with the first stage. If the first stage must ever be rebuilt, save R and Gc - R into
# terrain_base.npz instead and run terrain2.py and grotto2.py afterward.
import bpy, numpy as np, mathutils, time, math, json

import os
# The project's folder, found from this file's place. Run in Blender, give the path along:
#   ns = {"__file__": path}; exec(open(path).read(), ns)
# (or name the folder in the environment variable TROPICAL_ISLAND; failing both, the folder
# Blender was started in is taken).
ROOT = os.environ.get("TROPICAL_ISLAND") or os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__") or os.path.join(os.getcwd(), "tools", "x"))))
OUT = os.path.join(ROOT, "assets", "models") + os.sep
TEX = os.path.join(ROOT, "assets", "textures") + os.sep

terr = bpy.data.objects["BeachTerrain"]; me = terr.data
co = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
order = np.lexsort((co[:, 0], co[:, 1]))
G = co[order, 2].reshape(400, 400)
gx = np.linspace(-100, 100, 400)
prof = G.mean(0)


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


def orig(x, y):
    fx = (np.clip(x, -100, 100) + 100) / 200 * 399; fy = (np.clip(y, -100, 100) + 100) / 200 * 399
    x0 = np.clip(np.floor(fx).astype(int), 0, 398); y0 = np.clip(np.floor(fy).astype(int), 0, 398)
    tx = fx - x0; ty = fy - y0
    a = G[y0, x0] * (1 - tx) + G[y0, x0 + 1] * tx; b = G[y0 + 1, x0] * (1 - tx) + G[y0 + 1, x0 + 1] * tx
    return a * (1 - ty) + b * ty


def E(x):
    x = np.asarray(x, float)
    p = np.interp(np.clip(x, -100, 100), gx, prof)
    p = np.where(x < -100, prof[0] + (-100 - x) * 0.03, p)
    p = np.where(x > 100, prof[-1] - (x - 100) * 0.02, p)
    return p


EAST = -168.0


def W(x):
    return E(3.0 + (EAST - x))


def vnoise(x, y, seed):
    r = np.random.default_rng(seed); ph = r.uniform(0, 6.28, 6); fr = r.uniform(0.7, 1.3, 6)
    return (np.sin(x * 0.031 * fr[0] + y * 0.023 * fr[1] + ph[0]) * 0.5 + np.sin(x * 0.057 * fr[2] - y * 0.049 * fr[3] + ph[1]) * 0.3
            + np.sin(-x * 0.097 * fr[4] + y * 0.083 * fr[5] + ph[2]) * 0.2)


# trail from the west beach up to the summit (Blender x, y)
PATH = np.array([(-9, -40), (-22, -40), (-38, -35), (-54, -26), (-68, -16), (-81, -6), (-93, 2), (-102, 8), (-107, 11)], float)
PEAK = np.array([-110.0, 12.0])


def path_dist(x, y):
    d = np.full(np.shape(x), 1e9)
    for a, b in zip(PATH[:-1], PATH[1:]):
        ab = b - a; L2 = (ab ** 2).sum()
        t = np.clip(((x - a[0]) * ab[0] + (y - a[1]) * ab[1]) / L2, 0, 1)
        d = np.minimum(d, np.hypot(x - (a[0] + t * ab[0]), y - (a[1] + t * ab[1])))
    return d


def H(x, y, with_noise=True):
    base = np.minimum(E(x), W(x))
    inland = ss(1.3, 2.6, base)
    r2 = (x - PEAK[0]) ** 2 + (y - PEAK[1]) ** 2
    peak = 36.0 * np.exp(-r2 / (2 * 34.0 ** 2)) + 6.0 * np.exp(-r2 / (2 * 11.0 ** 2))
    hills = (5.0 * vnoise(x, y, 1) + 3.0 * vnoise(x * 1.9, y * 1.9, 2)
             + 7.0 * np.exp(-((x + 70) ** 2 + (y + 95) ** 2) / (2 * 30 ** 2))
             + 9.0 * np.exp(-((x + 120) ** 2 + (y - 110) ** 2) / (2 * 35 ** 2))
             + 5.0 * np.exp(-((x + 60) ** 2 + (y - 150) ** 2) / (2 * 28 ** 2)))
    hills = np.maximum(hills, -2.0)
    if not with_noise:
        hills = hills * 0.25
    land = base + inland * (peak + hills)
    near_orig = (np.abs(y) <= 100) & (x >= -100) & (x <= 100)
    blend_inland = ss(-25, -45, x)
    h = np.where(near_orig, orig(x, y) * (1 - blend_inland) + land * blend_inland, land)
    # beyond the original square, fade from its edge to the new land
    dy = np.maximum(np.abs(y) - 100, 0)
    w = ss(0, 30, dy)
    edge = orig(x, np.clip(y, -100, 100)) * (1 - blend_inland) + land * blend_inland
    h = np.where((~near_orig) & (x > -100) & (x < 100) & (dy > 0), edge * (1 - w) + land * w, h)
    f = 1.0 - ss(185, 245, np.abs(y))
    h = np.where(h > 0, h * f - (1 - f) * 4.0, h - (1 - f) * 2.0)
    # reef drop-off: the sea floor falls away into deep water well before the edge of
    # the terrain mesh, so its border is never visible through the clear water
    ax = np.where(x > -70.0, 150.0, 108.0)
    ang = np.arctan2(y, x + 70.0)
    wob = 0.06 * np.sin(ang * 5.0 + 1.3) + 0.04 * np.sin(ang * 11.0 + 0.4) + 0.025 * np.sin(ang * 23.0 + 2.0)
    d = np.sqrt(((x + 70.0) / ax) ** 2 + (y / 228.0) ** 2) + wob
    drop = ss(0.98, 1.12, d)
    h = h - drop * 22.0 * ss(-0.5, -3.0, h)
    return h


def Hfinal(x, y):
    h = H(x, y, True)
    hs = H(x, y, False)
    pw = np.exp(-path_dist(x, y) ** 2 / (2 * 5.0 ** 2))
    return h * (1 - pw) + hs * pw


def axis(segs):
    out = []
    for a, b, st in segs:
        n = int(round((b - a) / st)); out.append(np.linspace(a, b, n + 1)[:-1])
    out.append([segs[-1][1]]); return np.concatenate(out)


def build():
    t0 = time.time()
    res = {}
    # ---------------- terrain mesh
    X = axis([(-195, -150, 0.75), (-150, -40, 1.25), (-40, 60, 0.5), (60, 170, 2.0)])
    Y = axis([(-262, -110, 1.25), (-110, 110, 0.5), (110, 262, 1.25)])
    XX, YY = np.meshgrid(X, Y); ZZ = Hfinal(XX, YY)
    nx = len(X); ny = len(Y)
    verts = np.stack([XX, YY, ZZ], -1).reshape(-1, 3)
    ix = np.arange(nx - 1); iy = np.arange(ny - 1)
    a = (iy[:, None] * nx + ix[None, :]).ravel()
    quads = np.stack([a, a + 1, a + nx + 1, a + nx], 1)
    m = bpy.data.meshes.new("TerrainExt")
    m.vertices.add(len(verts)); m.vertices.foreach_set("co", verts.ravel().astype(np.float32))
    nq = len(quads)
    m.loops.add(nq * 4); m.loops.foreach_set("vertex_index", quads.ravel().astype(np.int32))
    m.polygons.add(nq); m.polygons.foreach_set("loop_start", np.arange(0, nq * 4, 4, dtype=np.int32))
    m.update(calc_edges=True); m.shade_smooth()
    m.materials.append(bpy.data.materials["Sand"])
    col = bpy.data.collections.new("EXPORT_TMP"); bpy.context.scene.collection.children.link(col)
    ob = bpy.data.objects.new("TerrainExt", m); col.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=OUT + "terrain_ext.glb", export_format='GLB', use_selection=True, export_yup=True,
                              export_normals=True, export_texcoords=False, export_materials='EXPORT')
    bpy.data.objects.remove(ob)
    res["terrain_verts"] = len(verts)

    # ---------------- extra rocks (linked duplicates of the two original rock meshes)
    dg = bpy.context.evaluated_depsgraph_get()
    rock_meshes = {}
    for n in ["Boulders", "GraniteBoulders"]:
        src = bpy.data.objects[n]
        rock_meshes[n] = bpy.data.meshes.new_from_object(src.evaluated_get(dg), depsgraph=dg)
        rock_meshes[n].name = "Rock" + n
    # bounding-box centers of the source clusters (to place them by their middle)
    centers = {}
    for n, mm in rock_meshes.items():
        c = np.array([v.co[:] for v in mm.vertices]); centers[n] = (c.min(0) + c.max(0)) / 2; centers[n][2] = c[:, 2].min() + 0.4 * (c[:, 2].max() - c[:, 2].min())
    rng = np.random.default_rng(21)
    placements = []
    # summit dome: big granite slabs around the top
    placements.append(("GraniteBoulders", (PEAK[0] + 3, PEAK[1] - 2), 0.32, 0.4, -6.0))
    placements.append(("Boulders", (PEAK[0] - 10, PEAK[1] + 12), 0.35, 2.0, -2.5))
    placements.append(("Boulders", (-92, -18), 0.25, 1.0, -1.5))
    placements.append(("Boulders", (-75, 45), 0.3, 4.0, -1.5))
    # east (back) shore and the island tips
    for (px, py, sc, rot, sink) in [(-170, 60, 0.45, 0.3, -1.6), (-168, -55, 0.4, 2.5, -1.6), (-166, -140, 0.5, 1.2, -1.8),
                                    (-160, 165, 0.45, 4.0, -1.8), (-40, -225, 0.55, 0.8, -2.0), (-60, 228, 0.5, 2.2, -2.0),
                                    (-120, 205, 0.4, 5.0, -1.8), (-130, -200, 0.45, 3.3, -1.8)]:
        placements.append(("Boulders", (px, py), sc, rot, sink))
    # a small group on the west beach north of the start, in the water
    placements.append(("Boulders", (7, -92), 0.22, 1.7, -1.2))
    rocks_out = []
    rcol = []
    for k, (n, (px, py), sc, rot, sink) in enumerate(placements):
        o = bpy.data.objects.new(f"Rock_{k}", rock_meshes[n]); col.objects.link(o)
        gz = float(Hfinal(np.array([px]), np.array([py]))[0])
        cen = centers[n]
        M = (mathutils.Matrix.Translation((px, py, gz + sink * sc * 0.3)) @ mathutils.Matrix.Rotation(rot, 4, 'Z')
             @ mathutils.Matrix.Scale(sc, 4) @ mathutils.Matrix.Translation((-cen[0], -cen[1], -cen[2])))
        o.matrix_world = M
        rocks_out.append(o)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in rocks_out: o.select_set(True)
    bpy.context.view_layer.objects.active = rocks_out[0]
    # (extra rocks are now placed in Godot from closed boulder meshes)
    res["rocks"] = len(rocks_out)

    # ---------------- heightmap (R terrain, G terrain+rocks), saved as raw data
    N = 2048; EXT = 256.0
    c = (np.arange(N) + 0.5) / N * 2 * EXT - EXT
    HX, HY = np.meshgrid(c, c)
    R = Hfinal(HX, HY)
    R = np.where(HX < -195, -6.0, R); R = np.where(np.abs(HY) > 262, np.minimum(R, -6.0), R)
    Gc = R.copy()
    dg = bpy.context.evaluated_depsgraph_get()
    rocks_all = [bpy.data.objects[n].evaluated_get(dg) for n in ["Boulders", "GraniteBoulders"]]
    down = mathutils.Vector((0, 0, -1))
    for r in rocks_all:
        bb = [r.matrix_world @ mathutils.Vector(v) for v in r.bound_box]
        xs = [v.x for v in bb]; ys = [v.y for v in bb]
        jx = np.where((c > min(xs)) & (c < max(xs)))[0]; jy = np.where((c > min(ys)) & (c < max(ys)))[0]
        inv = r.matrix_world.inverted()
        for j in jy:
            for i in jx:
                o_w = mathutils.Vector((c[i], c[j], 120.0))
                o_l = inv @ o_w; d_l = (inv.to_3x3() @ down).normalized()
                hit, loc, _, _ = r.ray_cast(o_l, d_l)
                if hit:
                    z = (r.matrix_world @ loc).z
                    if z > Gc[j, i]: Gc[j, i] = z
    img = np.zeros((N, N, 4), dtype=np.float32); img[..., 0] = R; img[..., 1] = Gc; img[..., 3] = 1
    im = bpy.data.images.new("hm_island", N, N, alpha=True, float_buffer=True)
    im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(img.ravel())
    im.filepath_raw = TEX + "heightmap.exr"; im.file_format = 'OPEN_EXR'; im.save(); bpy.data.images.remove(im)

    # ---------------- land-cover mask: R forest floor, G trail, B rocky/grassy summit
    # irregular noise: many sine waves in random directions (no visible stripes)
    nrng = np.random.default_rng(5)
    nz = np.zeros_like(HX)
    for k in range(14):
        ang = nrng.uniform(0, np.pi); fr = 0.03 * (1.45 ** (k % 7)) * nrng.uniform(0.8, 1.2)
        nz += np.sin((HX * np.cos(ang) + HY * np.sin(ang)) * fr + nrng.uniform(0, 6.28)) / (1.0 + (k % 7))
    nz /= 2.6
    forest = ss(1.35, 1.95, R + nz * 0.35)
    trail = np.zeros_like(R)   # no trail: nobody has ever set foot on this island
    summit = ss(13.0, 22.0, R + nz * 2.0) * ss(70.0, 40.0, np.hypot(HX - PEAK[0], HY - PEAK[1]))
    # the natural way up: an open, grassy ridge with ragged edges (no path)
    corridor = ss(7.5, 4.0, path_dist(HX, HY) + nz * 3.0) * ss(2.5, 6.0, R)
    summit = np.maximum(summit, corridor)
    rockiness = np.clip((Gc - R) * 2.0, 0, 1)
    mask = np.zeros((N, N, 4), dtype=np.float32)
    mask[..., 0] = forest; mask[..., 1] = trail; mask[..., 2] = np.maximum(summit, rockiness * 0.0); mask[..., 3] = 1
    im = bpy.data.images.new("landmask", N, N, alpha=True, float_buffer=False)
    im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(mask.ravel())
    im.filepath_raw = TEX + "landmask.png"; im.file_format = 'PNG'; im.save(); bpy.data.images.remove(im)

    # placement data for Godot (trail polyline + peak), in Godot coordinates (x, z = -y)
    data = {"path": [[float(p[0]), float(-p[1])] for p in PATH], "peak": [float(PEAK[0]), float(-PEAK[1])],
            "peak_height": float(Hfinal(np.array([PEAK[0]]), np.array([PEAK[1]]))[0]), "east_shore": EAST}
    json.dump(data, open(OUT + "island.json", "w"), indent=1)
    for o in list(col.objects): bpy.data.objects.remove(o)
    bpy.data.collections.remove(col)
    res["peak"] = data["peak_height"]
    res["t"] = round(time.time() - t0, 1)
    return res
