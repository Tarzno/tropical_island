# Bush clusters (with LODs), tropical fish bodies and a flying fox for the Godot beach.
import bpy, bmesh, numpy as np, math, mathutils

import os
# The project's folder, found from this file's place. Run in Blender, give the path along:
#   ns = {"__file__": path}; exec(open(path).read(), ns)
# (or name the folder in the environment variable TROPICAL_ISLAND; failing both, the folder
# Blender was started in is taken).
ROOT = os.environ.get("TROPICAL_ISLAND") or os.path.dirname(os.path.dirname(os.path.abspath(
    globals().get("__file__") or os.path.join(os.getcwd(), "tools", "x"))))
OUT = os.path.join(ROOT, "assets", "models") + os.sep
rng = np.random.default_rng(77)


def new_col():
    c = bpy.data.collections.new("EXPORT_TMP"); bpy.context.scene.collection.children.link(c); return c


def export(objs, fname, vc='ACTIVE'):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=OUT + fname, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True, export_vertex_color=vc,
                              export_materials='EXPORT')


def mat(name, rgb, rough=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    return m


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


def leaves_on_hull(hull_pts, hull_nrm, count, size=(0.2, 0.1), yellow=0.07):
    idx = rng.integers(0, len(hull_pts), count)
    nrm = hull_nrm[idx] + rng.normal(size=(count, 3)) * 0.45; nrm[:, 2] += 0.35
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    pos = hull_pts[idx] + hull_nrm[idx] * rng.uniform(-0.05, 0.2, (count, 1))
    up = np.cross(nrm, rng.normal(size=(count, 3))); up /= np.linalg.norm(up, axis=1, keepdims=True)
    up = up + hull_nrm[idx] * 0.5; up[:, 2] -= 0.2
    up -= nrm * (up * nrm).sum(1, keepdims=True); up /= np.linalg.norm(up, axis=1, keepdims=True)
    side = np.cross(nrm, up)
    L = size[0] * rng.uniform(0.7, 1.35, (count, 1)); Wd = size[1] * rng.uniform(0.7, 1.3, (count, 1))
    q = np.stack([pos - side * Wd / 2, pos + side * Wd / 2, pos + side * Wd / 2 + up * L, pos - side * Wd / 2 + up * L], 1)
    U = np.tile(np.array([[0, 0], [1, 0], [1, 1], [0, 1]], float), (count, 1, 1))
    C = rng.random(count)
    M = (rng.random(count) < yellow).astype(np.int32)
    return q, U, C, M


def lod_of(q, U, C, M, frac, scl):
    keep = rng.random(len(q)) < frac
    q = q[keep]; cen = q.mean(1, keepdims=True); q = cen + (q - cen) * scl
    return q, U[keep], C[keep], M[keep]


def bushes():
    col = new_col(); objs = []; lods = []
    specs = [("BushA", (2.2, 1.8, 1.5), 16000), ("BushB", (3.2, 2.5, 2.1), 28000), ("BushC", (1.5, 1.3, 1.1), 9000)]
    for name, (rx, ry, rz), count in specs:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
        for v in bm.verts:
            p = v.co
            n = 1 + 0.18 * math.sin(p.x * 3.1 + 1.0) * math.sin(p.y * 2.7) + 0.12 * math.sin(p.z * 4.3 + p.x * 2.0)
            v.co = mathutils.Vector((p.x * rx * n, p.y * ry * n, max(p.z, -0.35) * rz * n + rz * 0.55))
        bm.normal_update()
        pts = np.array([v.co[:] for v in bm.verts]); nr = np.array([v.normal[:] for v in bm.verts])
        hull = bpy.data.meshes.new(name + "Hull"); bm.to_mesh(hull); bm.free()
        hull.materials.append(bpy.data.materials["BushGreen"])
        for p in hull.polygons: p.use_smooth = True
        o = bpy.data.objects.new(name + "Hull", hull); col.objects.link(o); objs.append(o)
        # bias leaves to the upper hull
        keep = pts[:, 2] > rz * -0.05
        q, U, C, M = leaves_on_hull(pts[keep], nr[keep], count, size=(0.26, 0.13))
        lm = quads_mesh(name + "Leaves", q, U, C, M, ["BushLeaf", "BushLeafYellow"])
        o = bpy.data.objects.new(name + "Leaves", lm); col.objects.link(o); objs.append(o)
        for suffix, frac, scl in [("_lod", 0.25, 1.85), ("_lod2", 0.07, 3.2)]:
            q2, U2, C2, M2 = lod_of(q, U, C, M, frac, scl)
            lm2 = quads_mesh(name + "Leaves" + suffix, q2, U2, C2, M2, ["BushLeaf", "BushLeafYellow"])
            o2 = bpy.data.objects.new(name + "Leaves" + suffix, lm2); col.objects.link(o2); objs.append(o2)
    export(objs, "bushes.glb")
    for o in objs: bpy.data.objects.remove(o)
    bpy.data.collections.remove(col)
    return len(objs)


def curve(pts, t):
    """Smooth curve through (t, value) points (cubic Hermite with averaged slopes)."""
    xs = np.array([q[0] for q in pts], float); ys = np.array([q[1] for q in pts], float)
    d = np.diff(ys) / np.diff(xs)
    m = np.concatenate(([d[0]], (d[:-1] + d[1:]) / 2, [d[-1]]))
    i = int(np.clip(np.searchsorted(xs, t) - 1, 0, len(xs) - 2))
    h = xs[i + 1] - xs[i]; u = min(max((t - xs[i]) / h, 0.0), 1.0)
    return float((2 * u ** 3 - 3 * u ** 2 + 1) * ys[i] + (u ** 3 - 2 * u ** 2 + u) * h * m[i]
                 + (-2 * u ** 3 + 3 * u ** 2) * ys[i + 1] + (u ** 3 - u ** 2) * h * m[i + 1])


def loft_fish(name, L, up, down, width, dorsal, anal, tail, matname):
    """Fish along +Y (head) .. -Y (tail), length L. UV.x = 0 at the snout .. 1 at the tail tip, UV.y round
    the body (0 on the back, 0.5 on the belly): shaders/fish.gdshader paints the species from these.
    up / down / width: profile of the back, the belly and the thickness as (t, fraction of L) points
    along the body (t 0 snout .. 0.82 tail stalk). dorsal / anal: (t0, t1, height, lean) of a fin
    that grows out of the back / belly along its whole base (lean > 0: highest toward the rear).
    tail: (height, fork) of the tail fin. Pectoral fins on the sides."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    uv = {}
    nseg = 20; nring = 12; T = 0.82
    y_of = lambda t: L * (0.5 - t)
    rings = []
    for i in range(nseg + 1):
        t = T * i / nseg
        zu = curve(up, t) * L; zd = curve(down, t) * L; w = curve(width, t) * L
        ring = []
        for j in range(nring):
            a = 2 * math.pi * j / nring
            c = math.cos(a)
            v = bm.verts.new((math.sin(a) * w * 0.5, y_of(t), c * (zu if c > 0 else zd)))
            ring.append(v); uv[v] = (t, j / nring)
        rings.append(ring)
    for i in range(nseg):
        for j in range(nring):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % nring], rings[i + 1][(j + 1) % nring], rings[i + 1][j]))
    bm.faces.new(rings[0]); bm.faces.new(list(reversed(rings[-1])))

    def fin(spec, sign, v_uv):
        # a strip standing on the back (sign 1) or hanging from the belly (sign -1), rooted inside the body
        t0, t1, h, lean = spec
        n = 10; prev = None
        for k in range(n + 1):
            s = k / n; t = t0 + (t1 - t0) * s
            edge = (curve(up, t) if sign > 0 else curve(down, t)) * L
            shape = math.sin(math.pi * min(1.0, s * (1.0 - 0.45 * lean) + 0.45 * lean * s * s) ** 0.9) ** 0.6 if 0 < s < 1 else 0.0
            a = bm.verts.new((0, y_of(t), sign * (edge - 0.012 * L)))
            b = bm.verts.new((0, y_of(t) - lean * h * L * 0.5 * s, sign * (edge + h * L * shape)))
            uv[a] = (t, v_uv); uv[b] = (t, v_uv)
            if prev:
                bm.faces.new((prev[0], a, b, prev[1]))
            prev = (a, b)

    fin(dorsal, 1, 0.0)
    fin(anal, -1, 0.5)
    # tail fin: two lobes and a notch, standing on the tail stalk
    th, fork = tail
    ped = curve(up, T) * L
    p0 = bm.verts.new((0, y_of(T - 0.03), ped)); p1 = bm.verts.new((0, y_of(T - 0.03), -curve(down, T) * L))
    tu = bm.verts.new((0, y_of(1.0), th * L)); td = bm.verts.new((0, y_of(1.0), -th * L))
    mu = bm.verts.new((0, y_of(0.93), th * L * 0.82)); md = bm.verts.new((0, y_of(0.93), -th * L * 0.82))
    nt = bm.verts.new((0, y_of(1.0 - fork * 0.16), 0))
    for v, t, vv in ((p0, T, 0.1), (p1, T, 0.4), (tu, 1.0, 0.1), (td, 1.0, 0.4), (mu, 0.93, 0.1), (md, 0.93, 0.4), (nt, 1.0 - fork * 0.16, 0.25)):
        uv[v] = (t, vv)
    bm.faces.new((p0, mu, tu, nt)); bm.faces.new((p0, nt, p1)); bm.faces.new((p1, nt, td, md))
    # pectoral fins: small fans low on the sides behind the gill cover, slanting back and out
    for sx in (1, -1):
        t = 0.27
        x0 = sx * curve(width, t) * L * 0.47
        a = bm.verts.new((x0, y_of(t), -0.03 * L)); b = bm.verts.new((x0, y_of(t + 0.05), -0.07 * L))
        c = bm.verts.new((x0 + sx * 0.07 * L, y_of(t + 0.2), -0.1 * L)); d = bm.verts.new((x0 + sx * 0.09 * L, y_of(t + 0.17), -0.03 * L))
        for v, tt in ((a, t), (b, t + 0.05), (c, t + 0.2), (d, t + 0.17)):
            uv[v] = (tt, 0.3 if sx > 0 else 0.7)
        bm.faces.new((a, b, c, d))
    for f in bm.faces:
        for l in f.loops:
            l[uv_layer].uv = uv.get(l.vert, (0.5, 0.5))
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if len(f.verts) == 4 and abs(f.calc_center_median().x) > 1e-5])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    me.materials.append(mat(matname, (0.8, 0.8, 0.8), 0.35))
    return me


def fish():
    """Three body types; the five species are painted on them by shaders/fish.gdshader (fish.gd: SPECIES)."""
    col = new_col(); objs = []
    shapes = {
        # surgeonfish (blue tang, yellow tang): a tall oval disc, small pointed mouth, long fins along back and belly
        "FishDisc": (0.22, [(0, 0.015), (0.06, 0.12), (0.18, 0.27), (0.34, 0.33), (0.5, 0.3), (0.66, 0.2), (0.76, 0.09), (0.82, 0.05)],
                     [(0, 0.015), (0.06, 0.08), (0.18, 0.23), (0.34, 0.31), (0.5, 0.3), (0.66, 0.2), (0.76, 0.09), (0.82, 0.05)],
                     [(0, 0.02), (0.08, 0.09), (0.25, 0.16), (0.45, 0.15), (0.65, 0.09), (0.82, 0.03)],
                     (0.16, 0.78, 0.1, 0.5), (0.3, 0.78, 0.09, 0.5), (0.22, 0.5)),
        # damselfish (sergeant major, chromis): oval, forked tail
        "FishOval": (0.18, [(0, 0.02), (0.06, 0.11), (0.2, 0.21), (0.36, 0.25), (0.52, 0.22), (0.68, 0.13), (0.82, 0.045)],
                     [(0, 0.02), (0.06, 0.09), (0.2, 0.19), (0.36, 0.23), (0.52, 0.21), (0.68, 0.13), (0.82, 0.045)],
                     [(0, 0.03), (0.1, 0.12), (0.28, 0.2), (0.48, 0.18), (0.68, 0.1), (0.82, 0.035)],
                     (0.22, 0.76, 0.09, 0.9), (0.46, 0.76, 0.08, 0.9), (0.2, 1.0)),
        # parrotfish: long, blunt-headed, low fins, a broad tail
        "FishLong": (0.32, [(0, 0.045), (0.05, 0.1), (0.16, 0.15), (0.34, 0.165), (0.52, 0.15), (0.68, 0.1), (0.82, 0.05)],
                     [(0, 0.04), (0.05, 0.085), (0.16, 0.13), (0.34, 0.15), (0.52, 0.14), (0.68, 0.095), (0.82, 0.05)],
                     [(0, 0.05), (0.08, 0.13), (0.26, 0.19), (0.46, 0.18), (0.66, 0.11), (0.82, 0.045)],
                     (0.22, 0.76, 0.05, 0.2), (0.5, 0.76, 0.045, 0.2), (0.14, 0.35)),
    }
    for name, (L, up, down, width, dorsal, anal, tail) in shapes.items():
        me = loft_fish(name, L, up, down, width, dorsal, anal, tail, "FishSkin")
        o = bpy.data.objects.new(name, me); col.objects.link(o); objs.append(o)
    export(objs, "fish.glb", vc='NONE')
    for o in objs:
        me = o.data; bpy.data.objects.remove(o); bpy.data.meshes.remove(me)
    bpy.data.collections.remove(col)
    return len(objs)


# (The flying fox below is the first version; the current model comes from assets6.py: flying_fox().)
def flying_fox():
    col = new_col()
    fur = mat("BatFur", (0.12, 0.07, 0.04), 0.9)
    mane = mat("BatMane", (0.45, 0.25, 0.1), 0.9)
    wingm = mat("BatWing", (0.06, 0.04, 0.035), 0.7)
    # body: elongated ellipsoid along +Y (head forward)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1)
    body = bpy.context.active_object; body.name = "Bat"; body.scale = (0.07, 0.15, 0.065)
    bpy.ops.object.transform_apply(scale=True); body.data.materials.append(fur)
    for c in body.users_collection: c.objects.unlink(body)
    col.objects.link(body)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=1, location=(0, 0.16, 0.02))
    head = bpy.context.active_object; head.name = "BatHead"; head.scale = (0.045, 0.06, 0.042)
    bpy.ops.object.transform_apply(scale=True, location=False); head.data.materials.append(mane)
    for c in head.users_collection: c.objects.unlink(head)
    col.objects.link(head); head.parent = body
    for sgn in (1, -1):
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.015, depth=0.04, location=(sgn * 0.02, 0.17, 0.065))
        ear = bpy.context.active_object; ear.name = "BatEar"; ear.data.materials.append(fur)
        for c in ear.users_collection: c.objects.unlink(ear)
        col.objects.link(ear); ear.parent = body
    # wings: membrane fans from the shoulder with scalloped trailing edge (origin = shoulder)
    for sgn, nm in ((1, "BatWingR"), (-1, "BatWingL")):
        bm = bmesh.new()
        span = 0.62
        lead = [(0, 0.03), (0.18, 0.07), (0.34, 0.05), (0.5, 0.0), (span, -0.06)]   # leading edge (x, y)
        trail = [(span, -0.06), (0.47, -0.14), (0.4, -0.08), (0.3, -0.2), (0.22, -0.13), (0.1, -0.22), (0.0, -0.16)]
        outline = lead + trail[1:]
        vs = [bm.verts.new((sgn * x, y, 0.0)) for x, y in outline]
        c = bm.verts.new((sgn * 0.2, -0.06, 0.0))
        for i in range(len(vs)):
            a, b = vs[i], vs[(i + 1) % len(vs)]
            f = bm.faces.new((c, a, b) if sgn > 0 else (c, b, a))
        me = bpy.data.meshes.new(nm); bm.to_mesh(me); bm.free()
        me.materials.append(wingm)
        w = bpy.data.objects.new(nm, me); col.objects.link(w); w.parent = body
        w.location = (sgn * 0.05, 0.04, 0.02)
    objs = list(col.objects)
    export(objs, "flying_fox.glb", vc='NONE')
    for o in objs: bpy.data.objects.remove(o)
    bpy.data.collections.remove(col)
    return len(objs)
