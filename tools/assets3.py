# Closed granite boulders and individual tropical broadleaf trees (with canopy LODs).
import bpy, bmesh, numpy as np, math, mathutils
from mathutils import Vector, noise

import os
# The project's folder, found from this file's place. Run in Blender, give the path along:
#   ns = {"__file__": path}; exec(open(path).read(), ns)
# (or name the folder in the environment variable TROPICAL_ISLAND; failing both, the folder
# Blender was started in is taken).
ROOT = os.environ.get("TROPICAL_ISLAND") or os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__") or os.path.join(os.getcwd(), "tools", "x"))))
OUT = os.path.join(ROOT, "assets", "models") + os.sep


def new_col():
    c = bpy.data.collections.new("EXPORT_TMP"); bpy.context.scene.collection.children.link(c); return c


def export(objs, fname, vc='ACTIVE'):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=OUT + fname, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True, export_vertex_color=vc,
                              export_materials='EXPORT')


# ------------------------------------------------------------------ boulders
def boulders():
    col = new_col(); objs = []
    specs = [  # name, radii (x, y, z), seed, flatten
        ("Boulder0", (1.0, 0.85, 0.7), 1, 0.15),
        ("Boulder1", (1.0, 0.7, 0.55), 2, 0.25),
        ("Boulder2", (1.0, 0.95, 0.9), 3, 0.05),
        ("Boulder3", (1.0, 0.6, 0.45), 4, 0.3),
        ("Boulder4", (1.0, 0.9, 0.6), 5, 0.2),
    ]
    for name, (rx, ry, rz), seed, flat in specs:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=5, radius=1.0)
        off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
        for v in bm.verts:
            d = v.co.normalized()
            # big lumps + medium bumps, kept smooth (weathered granite)
            n1 = noise.noise(d * 1.3 + off)
            n2 = noise.noise(d * 3.1 + off * 1.7)
            r = 1.0 + 0.22 * n1 + 0.06 * n2
            p = Vector((d.x * rx, d.y * ry, d.z * rz)) * r
            # vertical weathering flutes on the upper flanks
            ang = math.atan2(d.y, d.x)
            flute = math.sin(ang * (9 + seed) + n1 * 2.0) * 0.025 * max(0.0, 1.0 - abs(d.z)) * (d.z > -0.2)
            p += Vector((d.x, d.y, 0)).normalized() * flute if (d.x or d.y) else Vector()
            # slightly flattened top, broad base that continues under the sand
            if p.z > rz * (1 - flat):
                p.z = rz * (1 - flat) + (p.z - rz * (1 - flat)) * 0.4
            v.co = p
        # origin at the ground line: 30 % of the height below
        zmin = min(v.co.z for v in bm.verts); zmax = max(v.co.z for v in bm.verts)
        ground = zmin + 0.3 * (zmax - zmin)
        for v in bm.verts:
            v.co.z -= ground
        me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
        for p in me.polygons: p.use_smooth = True
        me.materials.append(bpy.data.materials["SeyGranite"])
        o = bpy.data.objects.new(name, me); col.objects.link(o); objs.append(o)
    export(objs, "boulders.glb", vc='NONE')
    for o in objs: bpy.data.objects.remove(o)
    bpy.data.collections.remove(col)
    return len(objs)


# ------------------------------------------------------------------ trees
def tube(bm, pts, radii, sides=9):
    """Tapered tube through points (list of Vector) with given radii."""
    rings = []
    for i, (p, r) in enumerate(zip(pts, radii)):
        if i < len(pts) - 1:
            t = (pts[i + 1] - p).normalized()
        else:
            t = (p - pts[i - 1]).normalized()
        a = t.orthogonal().normalized(); b = t.cross(a)
        ring = [bm.verts.new(p + (a * math.cos(2 * math.pi * k / sides) + b * math.sin(2 * math.pi * k / sides)) * r) for k in range(sides)]
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    bm.faces.new(rings[-1])


def curve(p0, p1, bend, n=6):
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(p0.lerp(p1, t) + bend * math.sin(math.pi * t))
    return pts


def leaves_cluster(rng, centers, radii, counts, size):
    P = []; U = []; C = []; M = []
    for cen, rad, cnt in zip(centers, radii, counts):
        cen = np.array(cen); rad = np.array(rad)
        d = rng.normal(size=(cnt, 3)); d /= np.linalg.norm(d, axis=1, keepdims=True)
        r = rng.random(cnt) ** 0.35
        pos = cen + d * rad * r[:, None]
        nrm = d + rng.normal(size=(cnt, 3)) * 0.5; nrm[:, 2] += 0.6; nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
        up = np.cross(nrm, rng.normal(size=(cnt, 3))); up /= np.linalg.norm(up, axis=1, keepdims=True)
        up = up + d * 0.6; up[:, 2] -= 0.25
        up -= nrm * (up * nrm).sum(1, keepdims=True); up /= np.linalg.norm(up, axis=1, keepdims=True)
        side = np.cross(nrm, up)
        L = size[0] * rng.uniform(0.75, 1.3, (cnt, 1)); W = size[1] * rng.uniform(0.75, 1.25, (cnt, 1))
        P.append(np.stack([pos - side * W / 2, pos + side * W / 2, pos + side * W / 2 + up * L, pos - side * W / 2 + up * L], 1))
        U.append(np.tile(np.array([[0, 0], [1, 0], [1, 1], [0, 1]], float), (cnt, 1, 1)))
        C.append(rng.random(cnt)); M.append((rng.random(cnt) < 0.06).astype(np.int32))
    return np.concatenate(P), np.concatenate(U), np.concatenate(C), np.concatenate(M)


def quads_mesh(name, P, U, C, M, mats):
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
    ca.data.foreach_set("color", cc.reshape(-1)); me.color_attributes.active_color = ca
    for mn in mats: me.materials.append(bpy.data.materials[mn])
    return me


def make_tree(name, seed, H, col):
    rng = np.random.default_rng(seed)
    bm = bmesh.new()
    r0 = H * 0.032
    lean = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * H * 0.05
    top = Vector((0, 0, H * rng.uniform(0.38, 0.48))) + lean
    # trunk starts 1.5 m below ground so slopes never show its end; flared at the ground
    trunk = curve(Vector((0, 0, -1.5)), top, lean * 0.3, 8)
    radii = []
    for p in trunk:
        h = max(p.z, 0.0)
        flare = 1.0 + 0.9 * math.exp(-h / (H * 0.03))
        radii.append(r0 * flare * (1.0 - 0.35 * h / max(top.z, 0.1)))
    tube(bm, trunk, radii, 12)
    # buttress roots
    for k in range(int(rng.integers(3, 6))):
        a = rng.uniform(0, 2 * math.pi)
        d = Vector((math.cos(a), math.sin(a), 0))
        root = curve(Vector((0, 0, H * 0.05)), d * r0 * rng.uniform(3.0, 4.5) + Vector((0, 0, -0.6)), Vector((0, 0, 0.15)), 4)
        tube(bm, root, [r0 * 0.7, r0 * 0.55, r0 * 0.4, r0 * 0.25, r0 * 0.12], 6)
    tips = []
    nmain = int(rng.integers(4, 7))
    for i in range(nmain):
        a = 2 * math.pi * i / nmain + rng.uniform(-0.4, 0.4)
        out = Vector((math.cos(a), math.sin(a), 0))
        start = trunk[-2].lerp(trunk[-1], rng.uniform(0.2, 1.0))
        elev = rng.uniform(0.35, 0.8)
        L = H * rng.uniform(0.28, 0.38)
        end = start + (out * math.cos(elev) + Vector((0, 0, math.sin(elev)))) * L
        br = curve(start, end, Vector((0, 0, L * 0.08)), 5)
        rr = r0 * rng.uniform(0.45, 0.6)
        tube(bm, br, [rr * (1 - 0.5 * t / 5) for t in range(6)], 8)
        for j in range(int(rng.integers(2, 4))):
            a2 = a + rng.uniform(-0.9, 0.9)
            out2 = Vector((math.cos(a2), math.sin(a2), 0))
            s2 = br[int(rng.integers(3, 6))]
            L2 = H * rng.uniform(0.12, 0.2)
            e2 = s2 + (out2 * 0.8 + Vector((0, 0, rng.uniform(0.3, 0.9)))).normalized() * L2
            b2 = curve(s2, e2, Vector((0, 0, L2 * 0.1)), 3)
            tube(bm, b2, [rr * 0.5, rr * 0.4, rr * 0.3, rr * 0.2], 6)
            tips.append(e2)
        tips.append(end)
    bme = bpy.data.meshes.new(name + "Bark"); bm.to_mesh(bme); bm.free()
    for p in bme.polygons: p.use_smooth = True
    bme.materials.append(bpy.data.materials["TakamakaBark"])
    o = bpy.data.objects.new(name + "Bark", bme); col.objects.link(o)
    objs = [o]
    centers = [tuple(t + Vector((0, 0, H * 0.03))) for t in tips]
    radii_c = [(H * rng.uniform(0.08, 0.12), H * rng.uniform(0.08, 0.12), H * rng.uniform(0.05, 0.07)) for _ in tips]
    counts = [int(H * rng.uniform(55, 75)) for _ in tips]
    P, U, C, M = leaves_cluster(rng, centers, radii_c, counts, (0.19, 0.1))
    for suffix, frac, scl in [("", 1.0, 1.0), ("_lod", 0.25, 1.85), ("_lod2", 0.07, 3.2)]:
        keep = rng.random(len(P)) < frac
        q = P[keep]; cen = q.mean(1, keepdims=True); q = cen + (q - cen) * scl
        me = quads_mesh(name + "Leaves" + suffix, q, U[keep], C[keep], M[keep], ["BushLeaf", "BushLeafYellow"])
        lo = bpy.data.objects.new(name + "Leaves" + suffix, me); col.objects.link(lo); objs.append(lo)
    return objs, len(P)


def trees():
    col = new_col(); objs = []; info = {}
    for i, (seed, H) in enumerate([(11, 13.0), (22, 16.0), (33, 19.0), (44, 22.0), (55, 15.0)]):
        o, n = make_tree(f"Tree{i}", seed, H, col)
        objs += o; info[f"Tree{i}"] = n
    export(objs, "trees.glb")
    for o in objs: bpy.data.objects.remove(o)
    bpy.data.collections.remove(col)
    return info
