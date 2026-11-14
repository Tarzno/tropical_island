# Round 4 assets: natural bushes (branching skeletons with leaf rosettes/sprays),
# jackfruit trees, giant tortoise, tiger shark, spotted eagle ray, seabirds for the
# colony (white tern, brown noddy, frigatebird, perched poses, nest), skink and day gecko.
# Run inside the open Blender: ns = {"__file__": path}; exec(open(path).read(), ns); ns['bushes']() ...
# Blender +Y = forward (head) for animals; exported with +Y up (Godot: forward = -Z).
import bpy, bmesh, numpy as np, math, json
from mathutils import Vector, Matrix, noise

import os
# The project's folder, found from this file's place. Run in Blender, give the path along:
#   ns = {"__file__": path}; exec(open(path).read(), ns)
# (or name the folder in the environment variable TROPICAL_ISLAND; failing both, the folder
# Blender was started in is taken).
ROOT = os.environ.get("TROPICAL_ISLAND") or os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__") or os.path.join(os.getcwd(), "tools", "x"))))
OUT = os.path.join(ROOT, "assets", "models") + os.sep
UP = np.array([0.0, 0.0, 1.0])


# ------------------------------------------------------------------ helpers
def new_col():
    c = bpy.data.collections.new("EXPORT_TMP"); bpy.context.scene.collection.children.link(c); return c


def drop(col):
    for o in list(col.objects):
        me = o.data
        bpy.data.objects.remove(o)
        if isinstance(me, bpy.types.Mesh) and me.users == 0:
            bpy.data.meshes.remove(me)
    bpy.data.collections.remove(col)


def export(objs, fname, vc='ACTIVE'):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=OUT + fname, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True, export_vertex_color=vc,
                              export_materials='EXPORT')


def mat(name, rgb, rough=0.6, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.use_backface_culling = False
    return m


def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-9)


def perp_basis(d):
    d = unit(d)
    a = np.cross(d, [0.0, 0.0, 1.0]) if abs(d[2]) < 0.9 else np.cross(d, [1.0, 0.0, 0.0])
    a = unit(a); b = np.cross(d, a)
    return a, b


def link(col, name, me, parent=None, loc=(0, 0, 0)):
    o = bpy.data.objects.new(name, me); col.objects.link(o)
    if parent: o.parent = parent
    o.location = loc
    return o


def bm_to_mesh(bm, name, mats, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = smooth
    for m in mats: me.materials.append(m if isinstance(m, bpy.types.Material) else bpy.data.materials[m])
    return me


def tube(bm, pts, radii, sides=7, cap=True, mat_index=0):
    rings = []
    prev_a = None
    for i, (p, r) in enumerate(zip(pts, radii)):
        p = Vector(p)
        t = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        if prev_a is None:
            a = t.orthogonal().normalized()
        else:   # parallel transport: no twisting
            a = (prev_a - t * prev_a.dot(t)).normalized()
        prev_a = a
        b = t.cross(a)
        rings.append([bm.verts.new(p + (a * math.cos(2 * math.pi * k / sides) + b * math.sin(2 * math.pi * k / sides)) * r) for k in range(sides)])
    for i in range(len(rings) - 1):
        for k in range(sides):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
            f.material_index = mat_index
    if cap:
        f = bm.faces.new(list(reversed(rings[0]))); f.material_index = mat_index
        f = bm.faces.new(rings[-1]); f.material_index = mat_index


def loft(bm, stations, nring=12, uv=None, mat_index=0, caps=True):
    """stations: list of (center Vector, half_width (x), half_height (z), along u). Body along any path.
    Ring k angle 0 = top (+z), going over +x. Returns rings."""
    uvl = bm.loops.layers.uv.verify()
    rings = []; us = []
    for c, hw, hh, u in stations:
        ring = []
        for k in range(nring):
            a = 2 * math.pi * k / nring
            ring.append(bm.verts.new(Vector(c) + Vector((math.sin(a) * hw, 0, math.cos(a) * hh))))
        rings.append(ring); us.append(u)
    faces = []
    for i in range(len(rings) - 1):
        for k in range(nring):
            k2 = (k + 1) % nring
            f = bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2]))
            f.material_index = mat_index
            vv = [(us[i], k / nring), (us[i + 1], k / nring), (us[i + 1], (k + 1) / nring), (us[i], (k + 1) / nring)]
            for l, t in zip(f.loops, vv): l[uvl].uv = t
            faces.append(f)
    if caps:
        for ring, u, rev in ((rings[0], us[0], True), (rings[-1], us[-1], False)):
            cen = bm.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
            for k in range(nring):
                k2 = (k + 1) % nring
                f = bm.faces.new((cen, ring[k2], ring[k]) if rev else (cen, ring[k], ring[k2]))
                f.material_index = mat_index
                for l in f.loops: l[uvl].uv = (u, 0.5)
    return rings


def flat_poly(bm, pts, mat_index=0, uvs=None):
    vs = [bm.verts.new(Vector(p)) for p in pts]
    f = bm.faces.new(vs); f.material_index = mat_index
    if uvs:
        uvl = bm.loops.layers.uv.verify()
        for l, t in zip(f.loops, uvs): l[uvl].uv = t
    return f


def quads_mesh(name, P, U, C, M, mats, A=None, N=None):
    n = len(P)
    me = bpy.data.meshes.new(name)
    me.vertices.add(n * 4); me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32))
    me.loops.add(n * 4); me.loops.foreach_set("vertex_index", np.arange(n * 4, dtype=np.int32))
    me.polygons.add(n); me.polygons.foreach_set("loop_start", np.arange(0, n * 4, 4, dtype=np.int32))
    me.polygons.foreach_set("material_index", M.astype(np.int32))
    me.update(calc_edges=True)
    ul = me.uv_layers.new(name="UVMap"); ul.data.foreach_set("uv", U.reshape(-1))
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    cc = np.ones((n * 4, 4)); cc[:, 0] = np.repeat(C, 4); cc[:, 1] = cc[:, 0]; cc[:, 2] = cc[:, 0]
    if A is not None: cc[:, 3] = np.repeat(A, 4)
    ca.data.foreach_set("color", cc.reshape(-1)); me.color_attributes.active_color = ca
    for mn in mats: me.materials.append(bpy.data.materials[mn])
    if N is not None:
        me.polygons.foreach_set("use_smooth", np.ones(n, dtype=bool))
        me.normals_split_custom_set(np.repeat(N, 4, axis=0).tolist())
    return me


# ------------------------------------------------------------------ leaves
def leaf_cards(base, dirs, nrm_hint, L, W):
    """Quads from base along dirs. Face normal ~ nrm_hint. UV.x across, UV.y along (0 base, 1 tip)."""
    side = unit(np.cross(dirs, nrm_hint))
    nrm = unit(np.cross(side, dirs))   # = nrm_hint made perpendicular to dirs
    side = np.cross(dirs, nrm)         # face normal of the quad == nrm
    hw = (W / 2)[:, None]; L = L[:, None]
    q = np.stack([base - side * hw, base + side * hw, base + side * hw + dirs * L, base - side * hw + dirs * L], 1)
    # flip winding so the geometric normal matches nrm: (v1-v0) x (v2-v1) = side x dirs = -nrm -> swap
    q = q[:, [1, 0, 3, 2]]
    U = np.tile(np.array([[1, 0], [0, 0], [0, 1], [1, 1]], float), (len(q), 1, 1))
    return q, U, nrm


def leaf_cluster(rng, tip, d, n, L, W, kind, droop=0.25, spray_len=0.35):
    d = unit(d); a, b = perp_basis(d)
    k = np.arange(n) / max(n - 1, 1)
    ang = np.arange(n) * 2.39996 + rng.uniform(0, 0.4, n)
    radial = np.outer(np.cos(ang), a) + np.outer(np.sin(ang), b)
    if kind == "rosette":
        base = tip - np.outer(k * L * 0.55, d) + radial * 0.01
        sp = 0.2 + k * 1.25 + rng.normal(0, 0.12, n)
        Ls = L * rng.uniform(0.75, 1.2, n) * (0.55 + 0.45 * np.minimum(1.0, k * 3))
    else:   # spray: alternate leaves along the last part of the twig
        t = rng.uniform(0, 1, n)
        base = tip - np.outer(t * spray_len, d) + radial * 0.005
        sp = rng.uniform(0.6, 1.15, n) + t * 0.2
        Ls = L * rng.uniform(0.7, 1.25, n) * (0.7 + 0.3 * t)
    dirs = np.outer(np.cos(sp), d) + radial * np.sin(sp)[:, None]
    dirs[:, 2] -= droop * np.sin(sp) * rng.uniform(0.5, 1.5, n)
    dirs = unit(dirs)
    hint = unit(UP * 0.8 + d * 0.4 + radial * 0.25 + rng.normal(0, 0.35, (n, 3)))
    Ws = W * rng.uniform(0.75, 1.25, n) * (Ls / L) ** 0.5
    q, U, nrm = leaf_cards(base, dirs, hint, Ls, Ws)
    return q, U, nrm


def grow(rng, p, d, length, radius, depth, maxd, P, out_br, out_tips, inner_tips):
    pts = [np.array(p, float)]; cur = np.array(p, float); dd = unit(d)
    nseg = 4
    for i in range(nseg):
        dd = unit(dd + rng.normal(0, P["wobble"], 3) + UP * P["photo"] - UP * P["sag"] * depth)
        cur = cur + dd * length / nseg
        pts.append(cur.copy())
    out_br.append((pts, radius, depth))
    if depth >= maxd:
        out_tips.append((cur, dd)); return
    nchild = int(rng.integers(P["kids"][0], P["kids"][1] + 1))
    for c in range(nchild):
        k = int(rng.integers(2, nseg + 1))
        a, b = perp_basis(dd)
        ang = rng.uniform(0, 2 * math.pi)
        nd = unit(dd + (a * math.cos(ang) + b * math.sin(ang)) * rng.uniform(0.5, 1.1))
        grow(rng, pts[k], nd, length * rng.uniform(0.55, 0.8), radius * 0.62, depth + 1, maxd, P, out_br, out_tips, inner_tips)
    if depth >= 1 and rng.random() < P["inner"]:
        inner_tips.append((pts[2], dd))


def add_lods(col, objs, name, q, U, C, M, A, N, mats, rng, lods=(("_lod", 0.25, 1.85), ("_lod2", 0.07, 3.2))):
    me = quads_mesh(name, q, U, C, M, mats, A, N)
    objs.append(link(col, name, me))
    for suffix, frac, scl in lods:
        keep = rng.random(len(q)) < frac
        q2 = q[keep]; cen = q2.mean(1, keepdims=True); q2 = cen + (q2 - cen) * scl
        me2 = quads_mesh(name + suffix, q2, U[keep], C[keep], M[keep], mats, A[keep], N[keep])
        objs.append(link(col, name + suffix, me2))


# ------------------------------------------------------------------ bushes
BUSHES = {
    # H, spread, extra lobes, skirt (lowest foliage as fraction of H), cluster spacing, leaf L/W, leaves per
    # cluster, kind, droop, yellow share, materials
    "A": dict(H=1.6, S=2.6, lobes=(3, 5), skirt=0.05, sp=0.2, L=0.17, W=0.075, per=22, kind="rosette", droop=0.2,
              yellow=0.08, mats=["ScaevolaLeaf", "BushLeafYellow"], seed=101),   # beach naupaka (Scaevola)
    "B": dict(H=2.5, S=3.0, lobes=(3, 6), skirt=0.08, sp=0.22, L=0.15, W=0.07, per=34, kind="spray", droop=0.35,
              yellow=0.06, mats=["BushLeaf", "BushLeafYellow"], seed=202),        # dense broadleaf shrub
    "C": dict(H=0.9, S=1.6, lobes=(2, 4), skirt=0.02, sp=0.16, L=0.12, W=0.055, per=22, kind="spray", droop=0.3,
              yellow=0.1, mats=["BushLeaf", "BushLeafYellow"], seed=303),         # low shrub
    "D": dict(H=3.3, S=2.4, lobes=(3, 5), skirt=0.4, sp=0.24, L=0.21, W=0.095, per=30, kind="spray", droop=0.45,
              yellow=0.05, mats=["BushLeaf", "BushLeafYellow"], seed=404),        # tall leggy shrub, bare stems below
    "E": dict(H=1.1, S=3.0, lobes=(4, 7), skirt=0.03, sp=0.15, L=0.085, W=0.036, per=52, kind="spray", droop=0.25,
              yellow=0.04, mats=["SilverLeaf", "BushLeafYellow"], seed=505),      # Pemphis on rocky shores
    "F": dict(H=1.3, S=1.9, lobes=(2, 4), skirt=0.12, sp=0.19, L=0.19, W=0.085, per=20, kind="rosette", droop=0.2,
              yellow=0.12, mats=["ScaevolaLeaf", "BushLeafYellow"], seed=606),    # young naupaka
}


def ensure_mats():
    mat("ScaevolaLeaf", (0.2, 0.42, 0.1), 0.35)
    mat("SilverLeaf", (0.3, 0.38, 0.25), 0.6)
    mat("JackLeaf", (0.04, 0.16, 0.03), 0.3)
    mat("Jackfruit", (0.45, 0.5, 0.12), 0.6)
    mat("PisoniaLeaf", (0.3, 0.5, 0.15), 0.5)
    mat("NestTwig", (0.25, 0.18, 0.1), 0.9)
    for m in ("BushLeaf", "BushLeafYellow", "TakamakaBark", "BushGreen"):
        assert bpy.data.materials.get(m), m


def crown(rng, lobes, P, bm, rs, stem_root, skirt_z, seed_off):
    """Foliage clusters scattered over an irregular envelope (a union of ellipsoid lobes), with
    noise-driven gaps and sprigs sticking out. Stems run from stem_root(c) to every lobe center,
    twigs from each cluster back toward the nearest stem. Returns leaf arrays."""
    S = P["S"]; H = P["H"]
    def inside(p, skip):
        return min([np.linalg.norm((p - c) / r) for j, (c, r) in enumerate(lobes) if j != skip] + [9.0])
    pts = []; nrms = []
    sp = P["sp"]
    area = sum(4 * math.pi * ((r[0] * r[1]) ** 1.6 + (r[0] * r[2]) ** 1.6 + (r[1] * r[2]) ** 1.6) ** (1 / 1.6) / 3 ** (1 / 1.6) for c, r in lobes)
    for t in range(int(area / (sp * sp) * 6)):
        j = int(rng.integers(0, len(lobes))); c, r = lobes[j]
        d = unit(rng.normal(size=3)); p = c + d * r
        if p[2] < skirt_z - 0.05 or p[2] < -0.05 or inside(p, j) < 0.98:
            continue
        if pts and np.min(np.linalg.norm(np.array(pts) - p, axis=1)) < sp:
            continue
        if noise.noise(Vector(p * P.get("gapf", 1.4)) + seed_off) < -0.3:   # blotchy gaps
            continue
        pts.append(p); nrms.append(unit((p - c) / (r * r)))
    pts = np.array(pts); nrms = np.array(nrms); n = len(pts)
    out = rng.uniform(-0.08, 0.1, n) * min(S, 3.0) / 2.5
    sprig = rng.random(n) < 0.1
    out[sprig] += rng.uniform(0.15, 0.4, sprig.sum())
    tips = pts + nrms * out[:, None]
    dirs = unit(nrms * 0.8 + UP * 0.35 + rng.normal(0, 0.25, (n, 3)))
    sizes = np.where(sprig, 0.6, 1.0) * rng.uniform(0.7, 1.3, n)
    inner_p = []; inner_d = []
    for t in range(int(n * P.get("inner", 0.35))):
        j = int(rng.integers(0, len(lobes))); c, r = lobes[j]
        d = unit(rng.normal(size=3)); p = c + d * r * rng.uniform(0.3, 0.82)
        if p[2] < skirt_z:
            continue
        inner_p.append(p); inner_d.append(unit(d + UP * 0.6))
    stem_ends = []
    for j, (c, r) in enumerate(lobes):
        for s in range(2 if j == 0 else 1):
            base = stem_root(c, rng)
            end = c + rng.normal(0, 0.15, 3) * r
            mid = (base + end) / 2 + np.array([rng.normal(0, 0.06 * H), rng.normal(0, 0.06 * H), 0]) * P.get("bend", 1.0)
            line = [base + (mid - base) * t * 2 if t < 0.5 else mid + (end - mid) * (t - 0.5) * 2 for t in np.linspace(0, 1, 6)]
            tube(bm, [Vector(p) for p in line], [rs * (1 - 0.6 * t) for t in np.linspace(0, 1, 6)], 6)
            stem_ends.append(end)
    stem_ends = np.array(stem_ends)
    for i in range(n):
        p = tips[i]
        e = stem_ends[np.argmin(np.linalg.norm(stem_ends - p, axis=1))]
        v = e - p; L = np.linalg.norm(v)
        q = p + v / max(L, 1e-6) * min(L, rng.uniform(0.35, 0.8) * P.get("twig", 1.0))
        m = (p + q) / 2 + rng.normal(0, 0.03, 3) - UP * 0.04
        tr = P.get("twig_r", rs * 0.35)
        tube(bm, [Vector(q), Vector(m), Vector(p - dirs[i] * 0.02)], [tr, tr * 0.7, tr * 0.45], 4)
    Q = []; UU = []; NN = []; CN = []; CEN = []
    allc = [(tips[i], dirs[i], nrms[i], sizes[i]) for i in range(n)] + [(p, d, d, 0.8) for p, d in zip(inner_p, inner_d)]
    for p, d, cn, sz in allc:
        k = max(5, int(P["per"] * sz * rng.uniform(0.75, 1.25)))
        q, U, nrm = leaf_cluster(rng, p, d, k, P["L"] * (0.85 + 0.15 * sz), P["W"] * (0.85 + 0.15 * sz), P["kind"],
                                 droop=P["droop"], spray_len=P.get("spray_len", 0.35))
        Q.append(q); UU.append(U); NN.append(nrm); CN.append(np.repeat(cn[None], k, 0)); CEN.append(np.repeat(p[None], k, 0))
    q = np.concatenate(Q); U = np.concatenate(UU); nrm = np.concatenate(NN); cn = np.concatenate(CN); cen = np.concatenate(CEN)
    mid = q.mean(1)
    N = unit(cn * 0.6 + unit(mid - cen + 1e-4) * 0.25 + nrm * 0.3 + UP * 0.15)
    depth = np.array([min(np.linalg.norm((m - c) / r) for c, r in lobes) for m in mid])
    zr = np.clip((mid[:, 2] - skirt_z) / max(H - skirt_z, 0.1), 0, 1)
    A = np.clip(0.2 + 0.8 * np.clip((depth - 0.5) / 0.5, 0, 1), 0.15, 1.0) * (0.75 + 0.25 * zr)
    C = rng.random(len(q))
    M = (rng.random(len(q)) < P["yellow"]).astype(np.int32)
    return q, U, C, M, A, N


def make_bush(col, key, P):
    rng = np.random.default_rng(P["seed"])
    H, S = P["H"], P["S"]
    sk = P["skirt"] * H
    lobes = [(np.array([0, 0, sk + (H - sk) * 0.5]), np.array([S * 0.32, S * 0.3, (H - sk) * 0.5]))]
    for i in range(int(rng.integers(P["lobes"][0], P["lobes"][1] + 1))):
        a = rng.uniform(0, 2 * math.pi); r = rng.uniform(0.18, 0.42) * S
        rz = rng.uniform(0.22, 0.42) * (H - sk)
        cz = sk + rng.uniform(rz * 0.8, (H - sk) - rz * 0.6)
        lobes.append((np.array([math.cos(a) * r, math.sin(a) * r, cz]),
                      np.array([rng.uniform(0.25, 0.42) * S, rng.uniform(0.25, 0.42) * S, rz])))
    bm = bmesh.new()
    rs = 0.012 + 0.012 * H
    root = lambda c, rng: np.array([rng.normal(0, 0.08 * S), rng.normal(0, 0.08 * S), -0.2])
    P = dict(P); P["inner"] = 0.9    # dense inner foliage: the hull is no longer drawn close up
    P.setdefault("twig", 0.45)          # short twigs: long ones read as spokes through the gaps
    P.setdefault("twig_r", (0.012 + 0.012 * H) * 0.25)
    q, U, C, M, A, N = crown(rng, lobes, P, bm, rs, root, sk, Vector((P["seed"] * 0.37, 1.3, 2.1)))
    objs = [link(col, "Bush" + key + "Twigs", bm_to_mesh(bm, "Bush" + key + "Twigs", ["TakamakaBark"]))]
    add_lods(col, objs, "Bush" + key + "Leaves", q, U, C, M, A, N, P["mats"], rng)
    # hull: shrunken lobes (dark depth behind the leaves; also the push-through volume)
    bm = bmesh.new()
    for c, r in lobes:
        m = Matrix.Translation(Vector(c)) @ Matrix.Diagonal((r[0] * 0.72, r[1] * 0.72, r[2] * 0.72, 1))
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=m)
    hull = bm_to_mesh(bm, "Bush" + key + "Hull", ["BushGreen"])
    objs.append(link(col, "Bush" + key + "Hull", hull))
    return objs, len(q)


def bushes():
    ensure_mats()
    col = new_col(); objs = []; info = {}
    for key, P in BUSHES.items():
        o, n = make_bush(col, key, P)
        objs += o; info[key] = n
    export(objs, "bushes.glb")
    drop(col)
    return info


# ------------------------------------------------------------------ jackfruit trees
def make_jack(col, i, seed, H):
    """Jackfruit: straight trunk, dense dark dome of big glossy leaves, huge oblong fruit
    hanging on short stalks straight from the trunk and the thick branches (cauliflory)."""
    rng = np.random.default_rng(seed)
    name = f"Jack{i}"
    bm = bmesh.new()
    r0 = H * 0.022
    lean = np.array([rng.uniform(-1, 1), rng.uniform(-1, 1), 0]) * H * 0.015
    top = np.array([0, 0, H * 0.7]) + lean
    trunk = [np.array([0, 0, -1.5]) + (top - np.array([0, 0, -1.5])) * t + lean * 0.3 * math.sin(math.pi * t) for t in np.linspace(0, 1, 10)]
    radii = [r0 * (1 + 0.7 * math.exp(-max(p[2], 0) / (H * 0.02))) * (1 - 0.6 * max(p[2], 0) / top[2]) for p in trunk]
    tube(bm, [Vector(p) for p in trunk], radii, 12)
    P = dict(H=H, S=H * 0.75, sp=0.36, L=0.25, W=0.115, per=46, kind="spray", droop=0.5, yellow=0.04, spray_len=0.5,
             twig=1.6, twig_r=0.018, bend=0.6, gapf=0.45)
    sk = H * 0.24
    lobes = [(np.array([0, 0, H * 0.6]), np.array([H * 0.33, H * 0.31, H * 0.34]))]
    for k in range(int(rng.integers(5, 8))):
        a = rng.uniform(0, 2 * math.pi); r = rng.uniform(0.12, 0.28) * H
        cz = rng.uniform(0.4, 0.85) * H
        rr = rng.uniform(0.13, 0.21) * H
        lobes.append((np.array([math.cos(a) * r, math.sin(a) * r, cz]), np.array([rr, rr * rng.uniform(0.85, 1.15), rr * 0.8])))
    def root(c, rng):
        h = np.clip(c[2] * rng.uniform(0.5, 0.75), H * 0.3, top[2] - 0.5)
        t = (h + 1.5) / (top[2] + 1.5)
        return trunk[0] + (top - trunk[0]) * t
    q, U, C, M, A, N = crown(rng, lobes, P, bm, r0 * 0.45, root, sk, Vector((seed * 0.21, 3.3, 0.7)))
    objs = [link(col, name + "Bark", bm_to_mesh(bm, name + "Bark", ["TakamakaBark"]))]
    add_lods(col, objs, name + "Leaves", q, U, C, M, A, N, ["JackLeaf", "BushLeafYellow"], rng,
             lods=(("_lod", 0.13, 2.2), ("_lod2", 0.035, 4.0)))
    # fruit on the trunk (mostly low) and on the lower branches
    bm = bmesh.new()
    cl = bm.loops.layers.color.new("Col")
    nf = int(rng.integers(10, 18))
    for f in range(nf):
        h = rng.uniform(0.9, min(top[2] * 0.85, 6.5)) if rng.random() < 0.8 else rng.uniform(6.0, top[2] * 0.9)
        t = (h + 1.5) / (top[2] + 1.5); j = min(int(t * 9), 8)
        c = trunk[j] + (trunk[j + 1] - trunk[j]) * (t * 9 - j); r = radii[j] + (radii[j + 1] - radii[j]) * (t * 9 - j)
        a = rng.uniform(0, 2 * math.pi); out = np.array([math.cos(a), math.sin(a), 0])
        L = rng.uniform(0.35, 0.65); R = L * rng.uniform(0.24, 0.3)
        attach = c + out * r * 0.95
        center = attach + out * R * 0.9 - UP * (L * 0.5 + 0.06)
        tube(bm, [Vector(attach - out * 0.03), Vector(attach + out * 0.04 - UP * 0.03), Vector(center + out * 0.0 + UP * L * 0.47)], [0.022, 0.02, 0.018], 5)
        tilt = Matrix.Rotation(rng.uniform(-0.3, 0.3), 4, Vector(np.cross(out, UP)))
        m = Matrix.Translation(Vector(center)) @ tilt @ Matrix.Diagonal((R, R * rng.uniform(0.9, 1.1), L / 2, 1))
        before = set(bm.verts)
        bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=10, radius=1.0, matrix=m)
        new = [v for v in bm.verts if v not in before]
        for v in new:
            v.co += (v.co - Vector(center)).normalized() * 0.03 * noise.noise(v.co * 5.0 + Vector((f, 0, 0)))
        ripe = rng.uniform(0, 1) ** 2
        col_ = (0.35 + 0.4 * ripe, 0.45 + 0.08 * ripe, 0.08, 1.0)
        for face in {f2 for v in new for f2 in v.link_faces}:
            for l in face.loops: l[cl] = col_
    fruit = bm_to_mesh(bm, name + "Fruit", ["Jackfruit"])
    objs.append(link(col, name + "Fruit", fruit))
    return objs, len(q)


def jackfruit():
    ensure_mats()
    col = new_col(); objs = []; info = {}
    for i, (seed, H) in enumerate([(71, 11.0), (72, 14.0), (73, 16.5)]):
        o, n = make_jack(col, i, seed, H); objs += o; info[f"Jack{i}"] = n
    export(objs, "jackfruit.glb")
    drop(col)
    return info


# ------------------------------------------------------------------ tree tips (for nests)
def tree_tips(path=os.path.join(ROOT, "tools", "assets3.py")):
    """Re-runs the deterministic tree generator from assets3 and records the leaf-cluster
    centers (Godot coordinates) so nests and perched birds can sit in the canopies."""
    ns = {"__file__": path}
    exec(open(path).read(), ns)
    rec = []
    orig = ns["leaves_cluster"]
    def spy(rng, centers, radii, counts, size):
        rec.append([[c[0], c[2], -c[1], r[0]] for c, r in zip(centers, radii)])
        return orig(rng, centers, radii, counts, size)
    ns["leaves_cluster"] = spy
    col = new_col(); out = {}
    for i, (seed, H) in enumerate([(11, 13.0), (22, 16.0), (33, 19.0), (44, 22.0), (55, 15.0)]):
        rec.clear()
        ns["make_tree"](f"Tree{i}", seed, H, col)
        out[f"Tree{i}"] = rec[0]
    drop(col)
    json.dump(out, open(OUT + "tree_tips.json", "w"))
    return {k: len(v) for k, v in out.items()}


# ------------------------------------------------------------------ giant tortoise
def tortoise():
    col = new_col(); objs = []
    shell_m = mat("TortShell", (0.16, 0.13, 0.1), 0.7)
    skin_m = mat("TortSkin", (0.2, 0.18, 0.16), 0.85)
    eye_m = mat("TortEye", (0.01, 0.01, 0.01), 0.1)
    rx, ry, top = 0.43, 0.56, 0.8
    def rim(th):
        s = math.sin(th)
        return 0.27 + 0.13 * max(0.0, s) ** 3 + 0.04 * max(0.0, -s) ** 2
    bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
    nth, ns_ = 48, 16
    pole = bm.verts.new((0, 0, top))
    rings = []
    for i in range(1, ns_ + 1):
        s = i / ns_
        ring = []
        for k in range(nth):
            th = 2 * math.pi * k / nth
            rr = math.sin(s * math.pi / 2) ** 0.85
            z = rim(th) + (top - rim(th)) * math.cos(s * math.pi / 2) ** 0.95
            flare = 1.0 + 0.05 * max(0.0, (s - 0.85) / 0.15)
            hump = 1.0 + 0.04 * math.sin(th) * s   # slightly broader at the back
            p = Vector((rx * rr * math.cos(th) * flare / hump, ry * rr * math.sin(th) * flare, z))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    # lip and underside back to the plastron
    for scl, dz in ((0.985, -0.035), (0.9, -0.06), (0.75, None)):
        ring = []
        for k in range(nth):
            q = rings[-1][k].co if dz is not None else None
            base = rings[ns_ - 1][k].co
            if dz is None:
                ring.append(bm.verts.new((base.x * scl, base.y * scl, 0.2)))
            else:
                ring.append(bm.verts.new((base.x * scl, base.y * scl, base.z + dz)))
        rings.append(ring)
    bottom = bm.verts.new((0, 0, 0.19))
    allr = rings
    for k in range(nth):
        f = bm.faces.new((pole, allr[0][k], allr[0][(k + 1) % nth]))
        for l in f.loops: l[uvl].uv = ((k + 0.5) / nth, 0.0) if l.vert == pole else (k / nth if l.vert == allr[0][k] else (k + 1) / nth, 1 / ns_)
    for i in range(len(allr) - 1):
        for k in range(nth):
            k2 = (k + 1) % nth
            f = bm.faces.new((allr[i][k], allr[i + 1][k], allr[i + 1][k2], allr[i][k2]))
            v0 = min(1.0, (i + 1) / ns_); v1 = min(1.0, (i + 2) / ns_) if i + 1 < ns_ else 1.0 + (i + 2 - ns_) * 0.05
            for l, t in zip(f.loops, [(k / nth, v0), (k / nth, v1), ((k + 1) / nth, v1), ((k + 1) / nth, v0)]): l[uvl].uv = t
    for k in range(nth):
        f = bm.faces.new((bottom, allr[-1][(k + 1) % nth], allr[-1][k]))
        for l in f.loops: l[uvl].uv = (0.5, 1.2)
    me = bm_to_mesh(bm, "TortShell", [shell_m])
    objs.append(link(col, "TortShell", me))
    # soft body filling the gap between plastron and carapace, with a short tail
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0,
                              matrix=Matrix.Translation((0, 0.02, 0.31)) @ Matrix.Diagonal((0.36, 0.48, 0.13, 1)))
    loft(bm, [(Vector((0, -0.45, 0.28)), 0.05, 0.04, 0), (Vector((0, -0.55, 0.24)), 0.03, 0.025, 0.5), (Vector((0, -0.62, 0.2)), 0.004, 0.004, 1)], 8)
    me = bm_to_mesh(bm, "TortBody", [skin_m])
    objs.append(link(col, "TortBody", me))
    # neck in three parts and the head, each a child of the one before with its origin at the joint
    # and a ball at its far end, so the neck can curve down to the grass, stretch up, and fold into
    # an S when the head is pulled in (island_life.gd: T_NECK is the length of a part).
    seg = 0.115
    rads = [0.088, 0.08, 0.072, 0.066]
    parent = None
    for i in range(3):
        bm = bmesh.new(); bm.loops.layers.uv.verify()
        st = []
        y0 = -0.1 if i == 0 else 0.0     # the first part reaches back into the shell
        for t in np.linspace(0, 1, 4):
            y = y0 + (seg - y0) * t
            r = rads[i] + (rads[i + 1] - rads[i]) * max(y, 0.0) / seg
            st.append((Vector((0, y, 0)), r * 1.05, r, 0.2 * (i + t)))
        loft(bm, st, 12)
        ball(bm, (0, seg, 0), (rads[i + 1] * 1.05, rads[i + 1], rads[i + 1]), 0, 12, 6)
        nm = "TortNeck%d" % (i + 1)
        o = link(col, nm, bm_to_mesh(bm, nm, [skin_m]), parent, (0, 0.42, 0.33) if parent is None else (0, seg, 0))
        objs.append(o); parent = o
    # head: a blunt wedge, broadest at the jaw
    bm = bmesh.new()
    st = []
    for y, hw, hh, dz in ((-0.02, 0.058, 0.056, 0.0), (0.03, 0.074, 0.07, 0.004), (0.085, 0.082, 0.07, 0.004), (0.14, 0.074, 0.058, -0.002),
                          (0.19, 0.056, 0.042, -0.01), (0.225, 0.03, 0.022, -0.018)):
        st.append((Vector((0, y, dz)), hw, hh, 0.6 + 0.4 * (y + 0.02) / 0.245))
    loft(bm, st, 12)
    for sgn in (1, -1):
        ball(bm, (sgn * 0.066, 0.125, 0.03), (0.014, 0.014, 0.014), 1, 8, 6)
    objs.append(link(col, "TortHead", bm_to_mesh(bm, "TortHead", [skin_m, eye_m]), parent, (0, seg, 0)))
    # legs in two parts, so they can bend: the upper leg (origin at the shoulder/hip, reaching up
    # into the body so no gap opens when it swings) and the lower leg (child of the upper leg, origin
    # at the elbow/knee) ending in a round, elephant-like foot. The parts meet in a ball, which hides
    # the joint, and the foot is a ball too, so it sits on the ground at any angle of the leg.
    # Godot (island_life.gd) places the feet and solves the two angles: T_UPPER, T_LOWER, T_FOOT there.
    L1, L2, RF = 0.17, 0.145, 0.078
    nring = 10

    def column(bm, stations, ys):
        rings = []
        for z, r in stations:
            rings.append([bm.verts.new(Vector((math.cos(2 * math.pi * k / nring) * r, math.sin(2 * math.pi * k / nring) * r * ys, z)))
                          for k in range(nring)])
        for i in range(len(rings) - 1):
            for k in range(nring):
                k2 = (k + 1) % nring
                bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
        bm.faces.new(list(reversed(rings[-1])))
        bm.faces.new(rings[0])

    for nm, x, y, front in (("TortLegFL", -0.25, 0.3, True), ("TortLegFR", 0.25, 0.3, True),
                            ("TortLegBL", -0.24, -0.3, False), ("TortLegBR", 0.24, -0.3, False)):
        r0 = 0.088 if front else 0.094
        ys = 0.86 if front else 1.0      # front legs are flattened fore and aft
        bm = bmesh.new(); bm.loops.layers.uv.verify()
        column(bm, [(0.07, r0 * 0.95), (0.0, r0), (-L1 * 0.5, r0 * 0.97), (-L1, r0 * 0.92)], ys)
        bmesh.ops.create_uvsphere(bm, u_segments=nring, v_segments=6, radius=1.0,
                                  matrix=Matrix.Translation((0, 0, -L1)) @ Matrix.Diagonal((r0 * 0.92, r0 * 0.92 * ys, r0 * 0.92, 1)))
        upper = link(col, nm, bm_to_mesh(bm, nm, [skin_m]), loc=(x, y, 0.36))
        objs.append(upper)
        bm = bmesh.new(); bm.loops.layers.uv.verify()
        r1 = r0 * 0.9
        column(bm, [(0.0, r1), (-L2 * 0.5, r1 * 0.9), (-L2, r1 * 0.9)], ys)
        bmesh.ops.create_uvsphere(bm, u_segments=nring, v_segments=6, radius=1.0, matrix=Matrix.Diagonal((r1, r1 * ys, r1, 1)))
        bmesh.ops.create_uvsphere(bm, u_segments=nring, v_segments=8, radius=1.0,
                                  matrix=Matrix.Translation((0, 0, -L2)) @ Matrix.Diagonal((RF, RF * (0.92 if front else 1.0), RF, 1)))
        # toenails around the front of the foot, close to the ground
        for j in range(5 if front else 4):
            a = math.pi / 2 + (j - (2 if front else 1.5)) * 0.36
            q = Vector((math.cos(a) * RF * 0.86, math.sin(a) * RF * 0.86, -L2 - RF * 0.6))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.014, radius2=0.002, depth=0.035,
                                  matrix=Matrix.Translation(q) @ Matrix.Rotation(-1.2, 4, Vector((math.sin(a), -math.cos(a), 0))))
        lo = nm.replace("Leg", "Shin")
        objs.append(link(col, lo, bm_to_mesh(bm, lo, [skin_m]), upper, (0, 0, -L1)))
    export(objs, "tortoise.glb", vc='NONE')
    drop(col)
    return len(objs)


# ------------------------------------------------------------------ tiger shark
def shark():
    col = new_col()
    m = mat("SharkSkin", (0.4, 0.4, 0.38), 0.5)
    bm = bmesh.new()
    L = 3.6
    prof = [(0.0, 0.0, 0.0), (0.03, 0.14, 0.09), (0.1, 0.27, 0.19), (0.2, 0.33, 0.25), (0.32, 0.34, 0.27), (0.45, 0.3, 0.25),
            (0.6, 0.21, 0.19), (0.72, 0.13, 0.12), (0.8, 0.07, 0.08), (0.85, 0.045, 0.06)]
    st = []
    for u, hw, hh in prof:
        y = L * (0.5 - u)
        dz = -0.03 * (1 - u) + (0.03 if u < 0.05 else 0)
        st.append((Vector((0, y, dz)), max(hw * 0.95, 0.004), max(hh, 0.004), u))
    loft(bm, st, 14)
    uvl = bm.loops.layers.uv.verify()
    def fin(pts, u):
        f = flat_poly(bm, pts, 0, [(u, 0.0)] * len(pts))
    yb = lambda u: L * (0.5 - u)
    # first dorsal, second dorsal
    fin([(0, yb(0.29), 0.25), (0, yb(0.31), 0.45), (0, yb(0.345), 0.62), (0, yb(0.39), 0.73), (0, yb(0.445), 0.79),
         (0, yb(0.43), 0.62), (0, yb(0.43), 0.45), (0, yb(0.45), 0.3), (0, yb(0.48), 0.21)], 0.4)
    fin([(0, yb(0.7), 0.11), (0, yb(0.74), 0.24), (0, yb(0.77), 0.09)], 0.74)
    # caudal: long upper lobe, short lower lobe
    fin([(0, yb(0.8), 0.06), (0, yb(0.88), 0.25), (0, yb(0.95), 0.45), (0, yb(1.0), 0.56), (0, yb(0.975), 0.47), (0, yb(0.93), 0.24),
         (0, yb(0.87), 0.03), (0, yb(0.92), -0.2), (0, yb(0.935), -0.27), (0, yb(0.88), -0.14), (0, yb(0.84), -0.05)], 0.92)
    # pectorals and pelvics
    for s in (1, -1):
        fin([(s * 0.25, yb(0.24), -0.1), (s * 0.75, yb(0.42), -0.3), (s * 0.66, yb(0.45), -0.3), (s * 0.25, yb(0.36), -0.12)], 0.3)
        fin([(s * 0.12, yb(0.63), -0.13), (s * 0.3, yb(0.7), -0.2), (s * 0.12, yb(0.7), -0.14)], 0.66)
    me = bm_to_mesh(bm, "Shark", [m])
    o = link(col, "Shark", me)
    n = len(me.vertices)
    export([o], "shark.glb", vc='NONE')
    drop(col)
    return n


# ------------------------------------------------------------------ spotted eagle ray
def ray():
    col = new_col()
    m = mat("RaySkin", (0.1, 0.1, 0.12), 0.4)
    bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
    span = 0.85; nx, ny = 16, 10
    def outline(xa):   # front and back y at |x| (body along +Y)
        t = xa / span
        front = 0.32 * (1 - t ** 1.1) + 0.02 - 0.05 * t
        back = -0.28 * (1 - t ** 0.7) - 0.02 - 0.05 * t + 0.1 * t ** 3
        return front, back
    grid_top = {}; grid_bot = {}
    xs = [span * (i / nx * 2 - 1) for i in range(nx + 1)]
    for i, x in enumerate(xs):
        f, b = outline(abs(x))
        for j in range(ny + 1):
            v = j / ny
            y = b + (f - b) * v
            body = math.exp(-(x / 0.16) ** 2)
            th = (0.11 * body + 0.012) * math.sin(math.pi * min(1, max(v, 0.02))) ** 0.6
            uv = ((x / span) * 0.5 + 0.5, v)
            grid_top[i, j] = (bm.verts.new((x, y, th * 0.6 + 0.02 * body)), uv)
            grid_bot[i, j] = (bm.verts.new((x, y, -th * 0.4)), uv) if 0 < j < ny and 0 < i < nx else grid_top[i, j]
    for g, rev in ((grid_top, False), (grid_bot, True)):
        for i in range(nx):
            for j in range(ny):
                q = [g[i, j], g[i + 1, j], g[i + 1, j + 1], g[i, j + 1]]
                vs = [a[0] for a in q]
                if len(set(vs)) < 3:
                    continue
                if rev: q = q[::-1]
                try:
                    f = bm.faces.new([a[0] for a in q])
                except ValueError:
                    continue
                for l, a in zip(f.loops, q): l[uvl].uv = (a[1][0], a[1][1] if not rev else -a[1][1])
    # head with the duck-bill snout
    loft(bm, [(Vector((0, 0.3, 0.02)), 0.08, 0.05, 0.0), (Vector((0, 0.4, 0.015)), 0.06, 0.04, 0.0), (Vector((0, 0.48, 0.0)), 0.035, 0.022, 0.0),
              (Vector((0, 0.52, -0.01)), 0.01, 0.01, 0.0)], 10)
    # whip tail
    tube(bm, [Vector((0, -0.25, 0.0)), Vector((0, -0.8, 0.0)), Vector((0, -1.6, 0.0)), Vector((0, -2.6, 0.0))], [0.025, 0.012, 0.006, 0.0015], 5)
    me = bm_to_mesh(bm, "Ray", [m])
    o = link(col, "Ray", me)
    n = len(me.vertices)
    export([o], "ray.glb", vc='NONE')
    drop(col)
    return n


# ------------------------------------------------------------------ seabirds
def ball(bm, center, radii, mat_index, seg=8, rings=6):
    """An ellipsoid with its faces on material slot `mat_index`."""
    geom = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0,
                                     matrix=Matrix.Translation(center) @ Matrix.Diagonal((*radii, 1)))
    faces = set()
    for v in geom["verts"]:
        faces.update(v.link_faces)
    for f in faces:
        f.material_index = mat_index


def tail_feathers(bm, base, length, n, spread, kind, side, mat_index, width=0.12):
    """Half a tail: `n` feathers fanned out from `base` toward one side (side 1 = right, -1 = left),
    pointing back along -Y. kind: "fork" / "deepfork" / "shallow" (outer feathers longest) or
    "wedge" (central feathers longest, with a small notch)."""
    base = Vector(base)
    for k in range(n):
        f = k / max(n - 1, 1)
        if kind == "fork":
            ln = length * (0.52 + 0.48 * f ** 1.4)
        elif kind == "deepfork":
            ln = length * (0.36 + 0.64 * f ** 1.2)
        elif kind == "shallow":
            ln = length * (0.8 + 0.2 * f ** 1.5)
        else:
            ln = length * (1.0 - 0.3 * f ** 1.4) * (0.94 if k == 0 else 1.0)
        a = spread * (k + 0.3) / n
        if kind in ("wedge", "shallow"):
            # the innermost feathers reach across the middle, so no gap opens when the halves spread
            a = -0.1 + (spread + 0.1) * (k + 0.3) / n
        d = Vector((side * math.sin(a), -math.cos(a), 0.0))
        p = Vector((math.cos(a), side * math.sin(a), 0.0)) * side
        w = length * width * (1.0 - 0.25 * f)
        z = Vector((0, 0, -0.0012 * k))
        pts = [base + z - p * w * 0.3, base + z + p * w * 0.3, base + z + d * ln * 0.55 + p * w * 0.5,
               base + z + d * ln * 0.92 + p * w * 0.3, base + z + d * ln, base + z + d * ln * 0.92 - p * w * 0.3,
               base + z + d * ln * 0.55 - p * w * 0.5]
        flat_poly(bm, pts if side > 0 else pts[::-1], mat_index)


def bird(col, prefix, length, mats, tail="fork", tail_len=0.1, tail_mat=None, tail_spread=0.3, tail_w=0.12,
         bill=0.05, bill_up=0.0, hook=False, girth=1.0, eye=1.0, crest=False, sac=None):
    """Flying bird: the body (origin at its center; slot 0 is the plumage, painted by
    shaders/bird.gdshader from the loft's UVs: UV.x from the bill back, UV.y around the body), with
    empties at the shoulders ({prefix}WingL/R: flight.gd fits the bendable wings there), a tail in two
    halves that open and close ({prefix}TailL/R, origin at the tail base) and, for a male frigatebird,
    the throat sac ({prefix}Sac, origin at the throat, drawn inflated: the game scales it)."""
    body_m, dark_m, bill_m = mats
    bm = bmesh.new()
    L = length
    K = L / 0.35
    st = []
    for u, hw, hh, dz in ((0.0, 0.006, 0.006, 0.006), (0.03, 0.022, 0.024, 0.01), (0.08, 0.032, 0.034, 0.012), (0.13, 0.031, 0.033, 0.01),
                          (0.18, 0.034, 0.037, 0.004), (0.24, 0.047, 0.05, 0.001), (0.3, 0.056, 0.058, 0.0), (0.45, 0.058, 0.055, -0.004),
                          (0.6, 0.045, 0.04, -0.002), (0.72, 0.028, 0.022, 0.0), (0.82, 0.012, 0.01, 0.004)):
        g = girth if u > 0.16 else (1 + girth) / 2
        st.append((Vector((0, L * (0.4 - u), dz * K)), hw * K * g, hh * K * g, u))
    loft(bm, st, 12)
    # bill
    b0 = L * 0.4
    pts = [Vector((0, b0 - 0.005, 0.0)), Vector((0, b0 + bill * 0.6, -0.002 + bill_up * 0.5)), Vector((0, b0 + bill, -0.006 + bill_up))]
    radii = [0.009 * K, 0.005 * K, 0.0015]
    if hook:   # a frigatebird's long bill ends in a hook
        pts = [pts[0], Vector((0, b0 + bill * 0.5, -0.002)), Vector((0, b0 + bill * 0.9, -0.004)), Vector((0, b0 + bill, -0.022))]
        radii = [0.0085 * K, 0.0055 * K, 0.004 * K, 0.0012]
    tube(bm, pts, radii, 6, mat_index=2)
    for s in (1, -1):
        ball(bm, (s * 0.027 * K * (1 + girth) / 2, L * 0.33, 0.02 * K), (0.007 * K * eye,) * 3, 1, 6, 4)
    if crest:   # shaggy feathers at the back of the cap
        for i in range(5):
            x0 = (i - 2) * 0.008 * K
            y0 = L * (0.4 - 0.16); z0 = 0.036 * K
            flat_poly(bm, [(x0 - 0.006 * K, y0, z0), (x0 + 0.006 * K, y0, z0), (x0 * 1.4, y0 - 0.05 * K, z0 + 0.003 * K * (1 + i % 2))], 1)
    me = bm_to_mesh(bm, prefix, [body_m, dark_m, bill_m])
    body = link(col, prefix, me)
    out = [body]
    for s, side in ((1, "R"), (-1, "L")):
        e = bpy.data.objects.new(f"{prefix}Wing{side}", None); col.objects.link(e)
        e.parent = body; e.location = (s * 0.03 * K, L * 0.12, 0.012)
        out.append(e)
        bm = bmesh.new()
        tail_feathers(bm, (0, 0, 0), tail_len, 6, tail_spread, tail, s, 0, tail_w)
        out.append(link(col, f"{prefix}Tail{side}", bm_to_mesh(bm, f"{prefix}Tail{side}", [tail_mat or dark_m], smooth=False),
                        body, (0, L * (0.4 - 0.74), 0.002)))
    if sac is not None:
        bm = bmesh.new()
        r = 0.125 * L
        ball(bm, (0, -0.05 * L, -0.105 * L), (r, r * 1.08, r * 1.15), 0, 14, 10)
        out.append(link(col, f"{prefix}Sac", bm_to_mesh(bm, f"{prefix}Sac", [sac]), body, (0, L * (0.4 - 0.15), -0.022 * K)))
    return out


def perched(col, name, length, mats, upright=0.5, tail="fork", tail_len=0.1, wing_dark=True, eye=1.0):
    body_m, dark_m, bill_m = mats
    bm = bmesh.new()
    L = length
    K = L / 0.35
    st = []
    for u, hw, hh, dz in ((0.0, 0.006, 0.006, 0.03), (0.03, 0.024, 0.026, 0.034), (0.08, 0.034, 0.036, 0.034), (0.13, 0.032, 0.034, 0.03),
                          (0.18, 0.036, 0.04, 0.018), (0.3, 0.062, 0.065, 0.0), (0.46, 0.064, 0.062, -0.004),
                          (0.62, 0.046, 0.04, 0.0), (0.76, 0.026, 0.02, 0.004), (0.9, 0.012, 0.008, 0.006)):
        st.append((Vector((0, L * (0.35 - u), dz * K)), hw * K, hh * K, u))
    loft(bm, st, 12)
    # folded wings: long thin slabs along the sides, crossing over the tail
    for s in (1, -1):
        loft(bm, [(Vector((s * 0.05 * K, L * 0.12, 0.02 * K)), 0.01 * K, 0.035 * K, 0.3),
                  (Vector((s * 0.06 * K, -L * 0.15, 0.02 * K)), 0.012 * K, 0.04 * K, 0.5),
                  (Vector((s * 0.02 * K, -L * 0.55, 0.015 * K)), 0.004, 0.012 * K, 0.8)], 6, mat_index=1 if wing_dark else 0)
        # the tail, closed, under the wing tips
        tail_feathers(bm, (0, L * (0.35 - 0.78), 0.004 * K), tail_len, 6, 0.16, tail, s, 1 if wing_dark else 0)
    tube(bm, [Vector((0, L * 0.34, 0.03 * K)), Vector((0, L * 0.34 + 0.045 * K, 0.026 * K))], [0.008 * K, 0.0015], 6, mat_index=2)
    for s in (1, -1):
        ball(bm, (s * 0.03 * K, L * 0.28, 0.045 * K), (0.008 * K * eye,) * 3, 2, 6, 4)
        tube(bm, [Vector((s * 0.02 * K, 0, -0.05 * K)), Vector((s * 0.02 * K, 0.01, -0.09 * K))], [0.004, 0.003], 4, mat_index=2)
    me = bm_to_mesh(bm, name, list(mats))
    # pitch the body up and put the feet at the origin
    me.transform(Matrix.Rotation(upright, 4, 'X'))
    me.transform(Matrix.Translation((0, 0, 0.09 * K)))
    return link(col, name, me)


def nest(col):
    rng = np.random.default_rng(9)
    bm = bmesh.new()
    for k in range(70):
        a = rng.uniform(0, 2 * math.pi); r = rng.uniform(0.07, 0.13); z = rng.uniform(0.0, 0.07)
        c = Vector((math.cos(a) * r, math.sin(a) * r, z))
        t = Vector((-math.sin(a), math.cos(a), rng.uniform(-0.3, 0.3))).normalized()
        t = (t + Vector(rng.normal(0, 0.4, 3))).normalized()
        l = rng.uniform(0.08, 0.2)
        tube(bm, [c - t * l / 2, c + t * l / 2], [0.006, 0.004], 4)
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0, matrix=Matrix.Translation((0, 0, 0.03)) @ Matrix.Diagonal((0.1, 0.1, 0.03, 1)))
    me = bm_to_mesh(bm, "Nest", ["NestTwig"])
    return link(col, "Nest", me)


def seabirds():
    mat("NestTwig", (0.25, 0.18, 0.1), 0.9)
    col = new_col()
    # plumage (slot 0 of every body): painted by shaders/bird.gdshader, set up in world.gd
    pl_wt = mat("PlumageWhiteTern", (0.92, 0.93, 0.93), 0.75)
    pl_nod = mat("PlumageNoddy", (0.11, 0.075, 0.05), 0.8)
    pl_fm = mat("PlumageFrigateM", (0.025, 0.025, 0.03), 0.45)
    pl_ff = mat("PlumageFrigateF", (0.03, 0.03, 0.035), 0.45)
    pl_ct = mat("PlumageCrestedTern", (0.9, 0.9, 0.9), 0.7)
    white = mat("BirdWhite", (0.92, 0.93, 0.93), 0.75)
    black = mat("BirdBlack", (0.02, 0.02, 0.02), 0.35)
    bill_b = mat("BirdBillBlack", (0.03, 0.03, 0.04), 0.3)
    bill_y = mat("TernBillYellow", (0.85, 0.62, 0.07), 0.4)
    tern_tail = mat("TernTail", (0.78, 0.8, 0.83), 0.7)
    brownd = mat("NoddyDark", (0.06, 0.04, 0.03), 0.8)
    frig = mat("FrigateBlack", (0.025, 0.025, 0.03), 0.45)
    bill_g = mat("FrigateBill", (0.45, 0.45, 0.48), 0.4)
    sac = mat("FrigateSac", (0.72, 0.02, 0.015), 0.3)
    egg = mat("TernEgg", (0.82, 0.78, 0.68), 0.5)
    objs = []
    # white tern: all white, big dark eyes, a shallow fork
    objs += bird(col, "WhiteTern", 0.3, (pl_wt, black, bill_b), tail="shallow", tail_len=0.105, tail_mat=white,
                 tail_spread=0.34, bill=0.04, bill_up=0.004, eye=1.7)
    # brown noddy: long wedge of a tail with a small notch
    objs += bird(col, "Noddy", 0.4, (pl_nod, black, bill_b), tail="wedge", tail_len=0.16, tail_mat=brownd, tail_spread=0.3, bill=0.045)
    # frigatebirds: long hooked bill, very long deeply forked tail; the male with his red throat sac
    objs += bird(col, "Frigate", 1.0, (pl_fm, black, bill_g), tail="deepfork", tail_len=0.46, tail_mat=frig, tail_spread=0.2,
                 tail_w=0.085, bill=0.115, hook=True, girth=0.6, sac=sac)
    objs += bird(col, "FrigateF", 1.0, (pl_ff, black, bill_g), tail="deepfork", tail_len=0.46, tail_mat=frig, tail_spread=0.2,
                 tail_w=0.085, bill=0.115, hook=True, girth=0.6)
    # greater crested tern (the terns fishing along the beach): black shaggy cap, yellow bill, forked tail
    objs += bird(col, "CrestedTern", 0.46, (pl_ct, black, bill_y), tail="fork", tail_len=0.17, tail_mat=tern_tail,
                 tail_spread=0.3, bill=0.062, crest=True)
    objs.append(perched(col, "WhiteTernPerched", 0.3, (pl_wt, black, bill_b), upright=0.35, tail="shallow", tail_len=0.105,
                        wing_dark=False, eye=1.7))
    objs.append(perched(col, "NoddyPerched", 0.4, (pl_nod, brownd, bill_b), upright=0.4, tail="wedge", tail_len=0.16))
    objs.append(nest(col))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=1.0, matrix=Matrix.Translation((0, 0, 0.022)) @ Matrix.Diagonal((0.021, 0.021, 0.028, 1)))
    objs.append(link(col, "TernEgg", bm_to_mesh(bm, "TernEgg", [egg])))
    export(objs, "seabirds.glb", vc='NONE')
    # drop() only removes mesh objects' data: the shoulder empties go the same way
    drop(col)
    return len(objs)


# ------------------------------------------------------------------ lizards
def lizard(col, name, L, head_w, body_w, leg_len, toe_pad=False):
    """Lizard along +Y, feet at z=0. UV.x 0 snout .. 1 tail tip; vertex color r = 1 on legs,
    g = leg id/4 (front left, front right, back left, back right) for the walking shader."""
    bm = bmesh.new()
    cl = bm.loops.layers.color.new("Col")
    h0 = leg_len * 0.6
    prof = [(0.0, 0.1, 0.1), (0.03, 0.45, 0.4), (0.08, 0.9, 0.7), (0.12, 0.75, 0.65), (0.16, 0.85, 0.7), (0.26, 1.0, 0.75),
            (0.36, 1.0, 0.72), (0.44, 0.78, 0.6), (0.52, 0.55, 0.45), (0.65, 0.35, 0.3), (0.8, 0.2, 0.18), (1.0, 0.03, 0.03)]
    st = []
    for u, w, h in prof:
        hw = (head_w if u < 0.12 else body_w) * w * 0.5
        st.append((Vector((0, L * (0.3 - u), h0 + (0.002 if u > 0.5 else 0))), hw, hw * h * 1.1, u))
    before = set(bm.faces)
    loft(bm, st, 10)
    for f in bm.faces:
        if f not in before:
            for l in f.loops: l[cl] = (0, 0, 0, 1)
    for idx, (sx, uy) in enumerate(((-1, 0.2), (1, 0.2), (-1, 0.42), (1, 0.42))):
        y = L * (0.3 - uy)
        hip = Vector((sx * body_w * 0.4, y, h0))
        knee = Vector((sx * (body_w * 0.4 + leg_len * 0.55), y + (0.15 if uy < 0.3 else -0.15) * leg_len, h0 * 0.75))
        foot = Vector((sx * (body_w * 0.4 + leg_len * 0.75), y + (0.4 if uy < 0.3 else -0.4) * leg_len, 0.002))
        before = set(bm.faces)
        tube(bm, [hip, knee, foot], [body_w * 0.16, body_w * 0.1, body_w * 0.06], 5)
        for t in range(5):
            a = (t - 2) * 0.45 + (0 if uy < 0.3 else math.pi)
            d = Vector((sx * math.cos(a) * 0.7, math.sin(a) + (0.6 if uy < 0.3 else -0.6), 0)).normalized()
            tip = foot + d * leg_len * 0.28
            tube(bm, [foot, tip], [body_w * 0.03, body_w * (0.035 if toe_pad else 0.015)], 4)
        for f in bm.faces:
            if f not in before:
                for l in f.loops:
                    l[cl] = (1.0, idx / 4.0 + 0.1, 0, 1)
    for s in (1, -1):
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=head_w * 0.13,
                                  matrix=Matrix.Translation((s * head_w * 0.32, L * (0.3 - 0.06), h0 + head_w * 0.2)))
    me = bm_to_mesh(bm, name, [mat(name + "Skin", (0.4, 0.3, 0.2), 0.4)])
    return link(col, name, me)


def lizards():
    col = new_col()
    objs = [lizard(col, "Skink", 0.24, 0.026, 0.034, 0.022), lizard(col, "Gecko", 0.17, 0.024, 0.026, 0.022, toe_pad=True)]
    export(objs, "lizards.glb", vc='ACTIVE')
    drop(col)
    return len(objs)
