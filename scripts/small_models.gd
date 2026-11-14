extends RefCounted
## Small animals modeled in code. The crab: the horn-eyed ghost crab of the beaches (the rock
## crabs of the shore use it too, darker). Preloaded by fauna.gd and critters.gd (no class_name).
##
## The crab's walking legs are jointed: shaders/crab.gdshader plants each tip and works out
## where the knee has to be. So the vertices of a leg are stored relative to their bone:
## UV = (distance along the bone, offset in the leg's plane), UV2.x = offset across it, NORMAL
## in the same three directions; COLOR.r = 0.25 upper leg / 0.5 lower leg, COLOR.g = which leg
## (0 front .. 1 back), COLOR.b = which side (1 = +x). The rest of the animal: COLOR.r = 0
## (body, eyes) or 0.75 (claw arms; UV2.y = how much of the reach to the mouth a vertex takes
## part in). COLOR.a paints: 1 shell, 0.75 pale (claw fingers), 0.5 underside, 0 the eyes.
## Size: 0.45 across the legs, like the model it replaces; the scripts scale it to life size.
## The crab walks sideways (along x); its front, with eyes and claws, is +z.

# (the shader has the same numbers: keep the two in step)
const HIP_X := 0.082
const HIP_Y := 0.05
const LEG_Z := [0.046, 0.014, -0.02, -0.054]
const LEG_FAN := [0.55, 0.15, -0.3, -0.75]
const LEG_REACH := [0.15, 0.168, 0.162, 0.14]
const L1 := 0.105
const L2 := 0.14


## One triangle of [position, normal (real), color, uv, uv2, normal to store]; the corners in
## the order the normals ask for (front faces are clockwise).
static func _emit(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var front := ((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3))
	var tri := [a, b, c] if front.dot((a[1] as Vector3) + (b[1] as Vector3) + (c[1] as Vector3)) >= 0.0 else [a, c, b]
	for q: Array in tri:
		st.set_color(q[2])
		st.set_normal(q[5] if q.size() > 5 else q[1])
		st.set_uv(q[3])
		st.set_uv2(q[4])
		st.add_vertex(q[0])


static func _quads(st: SurfaceTool, g: Array, ring: bool) -> void:
	var rows := g.size()
	var cols: int = (g[0] as Array).size()
	for i in rows - 1:
		for j in (cols if ring else cols - 1):
			var j1 := (j + 1) % cols
			if (g[i][j][0] as Vector3).distance_squared_to(g[i][j1][0]) > 1e-14:
				_emit(st, g[i][j], g[i + 1][j1], g[i][j1])
			if (g[i + 1][j][0] as Vector3).distance_squared_to(g[i + 1][j1][0]) > 1e-14:
				_emit(st, g[i][j], g[i + 1][j], g[i + 1][j1])


## A tube along points `pts` with radii [in the plane given by `flat`, across it]: a rigid part.
static func _tube(st: SurfaceTool, pts: Array, radii: Array, flat: Vector3, col: Color, weights: Array = []) -> void:
	var g: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var u := (flat - t * flat.dot(t)).normalized()
		var v := t.cross(u)
		var row: Array = []
		for k in 8:
			var a := TAU * k / 8.0
			var r: Array = radii[i]
			var off := u * (cos(a) * float(r[0])) + v * (sin(a) * float(r[1]))
			var n := (u * (cos(a) * float(r[1])) + v * (sin(a) * float(r[0]))).normalized()
			if i == pts.size() - 1 and float(r[0]) < 0.002:
				n = (n + t).normalized()
			row.append([p + off, n, col, Vector2.ZERO, Vector2(0, weights[i] if weights.size() > i else 0.0)])
		g.append(row)
	_quads(st, g, true)


static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color) -> void:
	var g: Array = []
	for i in 7:
		var row: Array = []
		for j in 10:
			var th := PI * i / 6.0
			var ph := TAU * j / 10.0
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			row.append([c + d * r, (d / r).normalized(), col, Vector2.ZERO, Vector2.ZERO])
		g.append(row)
	_quads(st, g, true)


## Where a leg's hip, knee and tip are when it stands, and the directions of its two bones:
## the same sums as the shader does.
static func _leg_rest(id: int, side: float) -> Dictionary:
	var h := Vector3(side * HIP_X, HIP_Y, LEG_Z[id])
	var fan: float = LEG_FAN[id]
	var t := h + Vector3(side * cos(fan), 0, sin(fan)) * float(LEG_REACH[id])
	t.y = 0.0
	var d := t - h
	var dist := clampf(d.length(), 0.05, L1 + L2 - 0.004)
	var dir := d.normalized()
	var u := (Vector3.UP - dir * dir.y).normalized()
	var a := (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
	var k := h + dir * a + u * sqrt(maxf(L1 * L1 - a * a, 0.0))
	var w := dir.cross(u).normalized()
	var e0 := (k - h).normalized()
	var e1 := (h + dir * dist - k).normalized()
	return {"h": h, "k": k, "w": w, "e0": e0, "v0": w.cross(e0), "e1": e1, "v1": w.cross(e1)}


static func crab() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := Color(0, 0, 0, 1)
	var under := Color(0, 0, 0, 0.5)
	# --- the carapace: a deep box with rounded corners, a little wider than long
	var top: Array = []
	var bot: Array = []
	for i in 7:
		var r := i / 6.0
		var rt: Array = []
		var rb: Array = []
		for j in 24:
			var a := TAU * j / 24.0
			var x := 0.1 * signf(cos(a)) * pow(absf(cos(a)), 0.55)
			var z := 0.082 * signf(sin(a)) * pow(absf(sin(a)), 0.55)
			var edge := pow(1.0 - pow(r, 2.6), 0.7)
			var p := Vector3(x * r, HIP_Y + 0.008 + 0.034 * edge, z * r + 0.004)
			var n := Vector3(x * r * 0.5, 0.11 * (0.25 + edge), z * r * 0.5).normalized()
			rt.append([p, n, shell, Vector2.ZERO, Vector2.ZERO])
			var pb := Vector3(x * r * 0.92, HIP_Y - 0.004 - 0.028 * pow(1.0 - r * r, 0.5), z * r * 0.92 + 0.004)
			rb.append([pb, Vector3(x * r * 0.4, -0.1, z * r * 0.4).normalized(), under, Vector2.ZERO, Vector2.ZERO])
		top.append(rt)
		bot.append(rb)
	_quads(st, top, true)
	_quads(st, bot, true)
	var rim: Array = [[], []]
	for j in 24:
		var a: Array = top[6][j]
		var b: Array = bot[6][j]
		var n := Vector3((a[0] as Vector3).x, 0.0, (a[0] as Vector3).z - 0.004).normalized()
		(rim[0] as Array).append([a[0], n, shell, Vector2.ZERO, Vector2.ZERO])
		(rim[1] as Array).append([b[0], n, shell, Vector2.ZERO, Vector2.ZERO])
	_quads(st, rim, true)
	for side in [1.0, -1.0]:
		# --- the eyes: a stalk, the long dark eye, and the horn above it
		var ex: float = 0.034 * side
		_tube(st, [Vector3(ex, 0.07, 0.074), Vector3(ex * 1.04, 0.09, 0.08), Vector3(ex * 1.06, 0.106, 0.083)], [[0.0055, 0.0055], [0.005, 0.005], [0.0045, 0.0045]], Vector3.RIGHT, shell)
		_blob(st, Vector3(ex * 1.07, 0.121, 0.0845), Vector3(0.0078, 0.017, 0.0078), Color(0, 0, 0, 0))
		_tube(st, [Vector3(ex * 1.08, 0.134, 0.085), Vector3(ex * 1.09, 0.147, 0.086), Vector3(ex * 1.1, 0.16, 0.0865)], [[0.0035, 0.0035], [0.0024, 0.0024], [0.0004, 0.0004]], Vector3.RIGHT, shell)
		# --- the claws, held in front of the face; the right one is the bigger
		var k := 1.3 if side > 0.0 else 0.95
		var claw := Color(0.75, 0, 0, 1)
		var pale := Color(0.75, 0, 0, 0.75)
		var s0 := Vector3(0.068 * side, 0.044, 0.07)
		var e0 := Vector3(0.118 * side, 0.04, 0.108)
		var p0 := Vector3(0.082 * side, 0.03, 0.14)
		var f0 := Vector3(0.04 * side, 0.022, 0.146)
		_tube(st, [s0, s0.lerp(e0, 0.5) + Vector3(0, 0.008, 0), e0], [[0.01 * k, 0.008 * k], [0.012 * k, 0.009 * k], [0.011 * k, 0.009 * k]], Vector3.UP, claw, [0.0, 0.3, 0.7])
		_tube(st, [e0, e0.lerp(p0, 0.5), p0], [[0.012 * k, 0.009 * k], [0.019 * k, 0.011 * k], [0.017 * k, 0.01 * k]], Vector3.UP, claw, [0.7, 0.9, 1.0])
		_tube(st, [p0 + Vector3(0, 0.007 * k, 0), p0.lerp(f0, 0.5) + Vector3(0, 0.008 * k, 0.002), f0 + Vector3(0, 0.001, 0)],
			[[0.007 * k, 0.006 * k], [0.005 * k, 0.004 * k], [0.0006, 0.0006]], Vector3.UP, pale, [1.0, 1.0, 1.0])
		_tube(st, [p0 - Vector3(0, 0.007 * k, 0), p0.lerp(f0, 0.5) - Vector3(0, 0.007 * k, -0.002), f0 - Vector3(0, 0.002, 0)],
			[[0.007 * k, 0.006 * k], [0.005 * k, 0.004 * k], [0.0006, 0.0006]], Vector3.UP, pale, [1.0, 1.0, 1.0])
		# --- four walking legs: an upper bone to the knee, a lower one ending in a pointed foot
		for id in 4:
			var fr := _leg_rest(id, side)
			var bones := [
				[0.25, fr["h"], fr["e0"], fr["v0"], [-0.012, 0.02, 0.06, 0.095, L1 + 0.004], [0.0135, 0.018, 0.0165, 0.0135, 0.011], [0, 0, 0, 0, 0]],
				[0.5, fr["k"], fr["e1"], fr["v1"], [-0.004, 0.02, 0.055, 0.09, 0.117, L2], [0.011, 0.012, 0.01, 0.0075, 0.0042, 0.0005], [0, 0, 0, -0.001, -0.004, -0.011]],
			]
			for bn: Array in bones:
				var org: Vector3 = bn[1]
				var e: Vector3 = bn[2]
				var v: Vector3 = bn[3]
				var w: Vector3 = fr["w"]
				var along: Array = bn[4]
				var g: Array = []
				for i in along.size():
					var ra: float = bn[5][i]
					var rb := ra * 0.62
					var row: Array = []
					for q in 8:
						var a := TAU * q / 8.0
						var oa := cos(a) * ra + float(bn[6][i])
						var ob := sin(a) * rb
						var nl := Vector3(0.0, cos(a) * rb, sin(a) * ra).normalized()
						if i == along.size() - 1 and ra < 0.002:
							nl = (nl + Vector3(1, 0, 0)).normalized()
						var pos := org + e * float(along[i]) + v * oa + w * ob
						var nreal := (e * nl.x + v * nl.y + w * nl.z).normalized()
						row.append([pos, nreal, Color(bn[0], id / 3.0, 1.0 if side > 0.0 else 0.0, 1.0 if i < along.size() - 1 or bn[0] < 0.4 else 0.75),
							Vector2(along[i], oa), Vector2(ob, 0.0), nl])
					g.append(row)
				_quads(st, g, true)
	return st.commit()


# ------------------------------------------------------------------ lizards
## Seychelles skink (`gecko` false: 24 cm, slender and smooth, a pointed head hardly wider than
## the neck, more than half of it tail, long toes) or green day gecko (17 cm, a broad flat head
## with big eyes, a thick tail, toes that end in round pads).
## For shaders/lizard.gdshader: forward = -Z, up = +Y, feet at y = 0, the snout at z = -0.3 of
## the length. UV.x = 0 snout .. 1 tail tip, UV.y = the way around (0 belly, 0.5 back).
## COLOR.r = 1 on the legs, COLOR.g = which leg (0.1 front left, 0.35 front right, 0.6 back
## left, 0.85 back right), COLOR.b = 1 on the eyes.
static func lizard(gecko: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var len := 0.17 if gecko else 0.24
	# [u, half-width, up, down, height of the middle]
	var prof: Array = [[0.0, 0.0002, 0.0002, 0.0002, 0.013], [0.004, 0.002, 0.0016, 0.0016, 0.013], [0.02, 0.0045, 0.003, 0.003, 0.013], [0.05, 0.0075, 0.0052, 0.0045, 0.0128],
		[0.085, 0.0098, 0.0068, 0.0055, 0.0125], [0.12, 0.0092, 0.0066, 0.006, 0.012], [0.18, 0.0125, 0.0082, 0.0078, 0.0112],
		[0.28, 0.0155, 0.0095, 0.009, 0.0108], [0.38, 0.0145, 0.009, 0.0085, 0.0105], [0.45, 0.0115, 0.0078, 0.0072, 0.01],
		[0.52, 0.0092, 0.007, 0.0065, 0.0088], [0.65, 0.0065, 0.0052, 0.005, 0.0065], [0.8, 0.004, 0.0033, 0.0032, 0.0045],
		[0.92, 0.002, 0.0017, 0.0017, 0.003], [1.0, 0.0004, 0.0004, 0.0004, 0.002]]
	if gecko:
		prof = [[0.0, 0.0002, 0.0002, 0.0002, 0.0095], [0.005, 0.0026, 0.0018, 0.0017, 0.0095], [0.025, 0.0058, 0.0035, 0.003, 0.0095], [0.06, 0.0095, 0.0058, 0.0042, 0.0095],
			[0.10, 0.0112, 0.0068, 0.005, 0.0092], [0.145, 0.009, 0.006, 0.005, 0.0088], [0.20, 0.0115, 0.007, 0.006, 0.0085],
			[0.30, 0.0135, 0.0078, 0.0065, 0.0085], [0.40, 0.0125, 0.0072, 0.006, 0.0082], [0.47, 0.0095, 0.0062, 0.0055, 0.0078],
			[0.53, 0.0085, 0.006, 0.0052, 0.0072], [0.68, 0.0068, 0.005, 0.0045, 0.0062], [0.84, 0.0042, 0.0033, 0.003, 0.0045],
			[0.95, 0.002, 0.0017, 0.0016, 0.003], [1.0, 0.0004, 0.0004, 0.0004, 0.0022]]
	var body := Color(0, 0, 0, 1)
	var sub := 3
	var n := (prof.size() - 1) * sub
	var g: Array = []
	for i in n + 1:
		var t := float(i) / n * (prof.size() - 1)
		var k := mini(int(t), prof.size() - 2)
		var f := t - k
		f = f * f * (3.0 - 2.0 * f) * 0.5 + f * 0.5
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		var u := lerpf(a[0], b[0], t - k)
		var w := lerpf(a[1], b[1], f)
		var up := lerpf(a[2], b[2], f)
		var dn := lerpf(a[3], b[3], f)
		var yc := lerpf(a[4], b[4], f)
		var row: Array = []
		for j in 13:
			var ang := TAU * (j % 12) / 12.0        # 0 at the belly
			var sx := sin(ang)
			var cy := -cos(ang)
			var p := Vector3(w * sx, yc + (up * cy if cy > 0.0 else dn * cy * (0.85 if not gecko else 0.75)), len * (u - 0.3))
			var nrm := Vector3(sx / maxf(w, 0.0005), cy / maxf(up if cy > 0.0 else dn, 0.0005), 0.0).normalized()
			row.append([p, nrm, body, Vector2(u, float(j) / 12.0), Vector2.ZERO])
		g.append(row)
	_quads(st, g, false)
	# --- legs: upper leg out from the body, lower leg down to the foot, five toes
	var legs := [[-1.0, 0.2, 0.1, true], [1.0, 0.2, 0.35, true], [-1.0, 0.44, 0.6, false], [1.0, 0.44, 0.85, false]]
	for lg: Array in legs:
		var sx: float = lg[0]
		var front: bool = lg[3]
		var col := Color(1.0, lg[2], 0.0, 1.0)
		var z := len * (float(lg[1]) - 0.3)
		var bw := (0.0115 if gecko else 0.0125) if front else (0.0105 if gecko else 0.012)
		var ll := (0.017 if front else 0.021) if not gecko else (0.017 if front else 0.019)
		var hy := 0.0085 if gecko else 0.0105
		var hip := Vector3(sx * bw * 0.75, hy, z)
		var knee := Vector3(sx * (bw + ll * 0.55), hy * 0.95, z + (-0.25 if front else 0.3) * ll)
		var foot := Vector3(sx * (bw + ll * 0.8), 0.0016, z + (-0.55 if front else -0.15) * ll)
		var r0 := 0.0034 if gecko else 0.0036
		_tube(st, [hip, hip.lerp(knee, 0.8) + Vector3(0, 0.001, 0), knee, knee.lerp(foot, 0.25), foot],
			[[r0, r0], [r0 * 0.85, r0 * 0.85], [r0 * 0.85, r0 * 0.85], [r0 * 0.8, r0 * 0.8], [r0 * 0.55, r0 * 0.55]], Vector3.UP, col)
		var tl := ll * ((0.42 if front else 0.6) if not gecko else 0.4)
		for toe in 5:
			var a := (toe - 2) * 0.42 + (0.5 if not front else 0.2)
			# (the toes point forward and outward)
			var d := Vector3(sx * sin(a + 0.5), 0.0, -cos(a + 0.5)).normalized()
			var tip := foot + d * tl * (1.0 - 0.12 * absf(toe - 2.5))
			tip.y = 0.0009
			if gecko:
				# a narrow toe that widens into a round pad
				_tube(st, [foot, foot.lerp(tip, 0.6), tip, tip + d * 0.0012], [[0.0008, 0.0007], [0.0008, 0.0006], [0.0019, 0.0006], [0.0003, 0.0003]], d.cross(Vector3.UP), col)
			else:
				_tube(st, [foot, tip], [[0.0009, 0.0008], [0.0003, 0.0003]], Vector3.UP, col)
	# --- eyes
	for sx in [1.0, -1.0]:
		var eye := Color(0, 0, 1, 1)
		if gecko:
			_blob(st, Vector3(sx * 0.0082, 0.0132, len * (0.078 - 0.3)), Vector3(0.0024, 0.0026, 0.003), eye)
		else:
			_blob(st, Vector3(sx * 0.0072, 0.0152, len * (0.062 - 0.3)), Vector3(0.0015, 0.0015, 0.002), eye)
	return st.commit()


# ------------------------------------------------------------------ mudskipper
## A mudskipper, 9 cm: a fish that sits out of the water on the mud between the mangrove roots,
## propped up on its arm-like pectoral fins, the bulging eyes on top of the head, the first
## back fin a little flag. Forward = -Z, the mud is y = 0. Colored by vertex (a plain material
## with vertex colors draws it).
static func mudskipper() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array = [[-0.036, 0.0003, 0.0003, 0.0003, 0.0115], [-0.0352, 0.0055, 0.0045, 0.0035, 0.012], [-0.032, 0.0082, 0.0072, 0.0052, 0.0126], [-0.026, 0.0098, 0.0088, 0.0062, 0.013],
		[-0.018, 0.0105, 0.0095, 0.0068, 0.0128], [-0.008, 0.0098, 0.0088, 0.0068, 0.012], [0.005, 0.0085, 0.008, 0.0062, 0.0105],
		[0.02, 0.0065, 0.0068, 0.0052, 0.0088], [0.035, 0.0042, 0.0052, 0.004, 0.0072], [0.046, 0.0022, 0.0036, 0.003, 0.006], [0.052, 0.0006, 0.002, 0.002, 0.0055]]
	var back := Color(0.34, 0.29, 0.2)
	var dark := Color(0.15, 0.12, 0.08)
	var belly := Color(0.66, 0.62, 0.5)
	var sub := 3
	var n := (prof.size() - 1) * sub
	var g: Array = []
	for i in n + 1:
		var t := float(i) / n * (prof.size() - 1)
		var k := mini(int(t), prof.size() - 2)
		var f := t - k
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		var z := lerpf(a[0], b[0], f)
		f = f * f * (3.0 - 2.0 * f) * 0.5 + f * 0.5
		var w := lerpf(a[1], b[1], f)
		var up := lerpf(a[2], b[2], f)
		var dn := lerpf(a[3], b[3], f)
		var yc := lerpf(a[4], b[4], f)
		var row: Array = []
		for j in 12:
			var ang := TAU * j / 12.0
			var sx := sin(ang)
			var cy := -cos(ang)
			var p := Vector3(w * sx, yc + (up * cy if cy > 0.0 else dn * cy), z)
			var nrm := Vector3(sx / maxf(w, 0.0004), cy / maxf(up if cy > 0.0 else dn, 0.0004), 0.0).normalized()
			# brown above with darker saddles across the back, pale below
			var saddle := smoothstep(0.3, 0.8, sin(z * 260.0 + 1.0)) * smoothstep(-0.1, 0.5, cy) * smoothstep(-0.02, -0.005, -absf(z + 0.03) + 0.0)
			saddle = smoothstep(0.3, 0.8, sin(z * 260.0 + 1.0)) * smoothstep(-0.1, 0.5, cy) * smoothstep(-0.024, -0.012, z)
			var col := belly.lerp(back.lerp(dark, saddle * 0.75), smoothstep(-0.45, 0.05, cy))
			row.append([p, nrm, col, Vector2.ZERO, Vector2.ZERO])
		g.append(row)
	_quads(st, g, true)
	for sx in [1.0, -1.0]:
		# the eyes, close together on top of the head, each on its own little mound
		_blob(st, Vector3(sx * 0.0046, 0.0212, -0.021), Vector3(0.0038, 0.0034, 0.0042), back)
		_blob(st, Vector3(sx * 0.0052, 0.0236, -0.0212), Vector3(0.0029, 0.0027, 0.003), Color(0.01, 0.01, 0.012))
		# the pectoral fins it props itself up on: a fleshy arm and a fan of fin on the mud
		_tube(st, [Vector3(sx * 0.008, 0.0105, -0.011), Vector3(sx * 0.0135, 0.006, -0.014), Vector3(sx * 0.018, 0.0012, -0.017), Vector3(sx * 0.0225, 0.0006, -0.016)],
			[[0.0034, 0.0026], [0.0032, 0.002], [0.0055, 0.0009], [0.0062, 0.0004]], Vector3(0, 0, 1), back.lerp(belly, 0.25))
	# fins on the middle line: the flag of the first back fin, the long low second one, the tail
	var fins := [
		[[Vector3(0, 0.02, -0.007), Vector3(0, 0.03, -0.006), Vector3(0, 0.0345, -0.001), Vector3(0, 0.031, 0.005), Vector3(0, 0.0185, 0.009)], dark.lerp(back, 0.4)],
		[[Vector3(0, 0.0165, 0.014), Vector3(0, 0.0235, 0.018), Vector3(0, 0.0215, 0.03), Vector3(0, 0.0135, 0.041), Vector3(0, 0.0115, 0.04)], back],
		[[Vector3(0, 0.006, 0.048), Vector3(0, 0.0125, 0.056), Vector3(0, 0.0125, 0.064), Vector3(0, 0.006, 0.068), Vector3(0, 0.001, 0.063), Vector3(0, 0.0015, 0.054)], back.lerp(dark, 0.3)],
	]
	for fin: Array in fins:
		var pts: Array = fin[0]
		var mid := Vector3.ZERO
		for p: Vector3 in pts:
			mid += p / pts.size()
		for i in pts.size():
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % pts.size()]
			_emit(st, [mid, Vector3.RIGHT, fin[1], Vector2.ZERO, Vector2.ZERO], [a, Vector3.RIGHT, (fin[1] as Color).lerp(belly, 0.35), Vector2.ZERO, Vector2.ZERO],
				[b, Vector3.RIGHT, (fin[1] as Color).lerp(belly, 0.35), Vector2.ZERO, Vector2.ZERO])
	return st.commit()


# ------------------------------------------------------------------ Seychelles frog
## The Seychelles frog (Sooglossus sechellensis): one of the smallest frogs there are, squat,
## warty, brown, sitting with its hind legs folded. Built 2 cm long (life size; the script
## shows it a little bigger); forward = -Z, the ground is y = 0.
## For the frog's shader (critters.gd): COLOR.r = 1 on the legs (banded), COLOR.g = how much a
## vertex takes part in the flutter of the throat, COLOR.b = 1 on the eyes.
static func frog() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array = [[-0.0105, 0.0003, 0.0003, 0.0003, 0.0046], [-0.0096, 0.0022, 0.0013, 0.0012, 0.0047], [-0.007, 0.004, 0.0024, 0.0019, 0.0051],
		[-0.004, 0.0048, 0.003, 0.0023, 0.0053], [-0.001, 0.005, 0.0034, 0.0027, 0.0051], [0.003, 0.0054, 0.0036, 0.0029, 0.0047],
		[0.0065, 0.0048, 0.003, 0.0027, 0.0041], [0.009, 0.0032, 0.002, 0.002, 0.0035], [0.0105, 0.0006, 0.0006, 0.0006, 0.0031]]
	var sub := 3
	var n := (prof.size() - 1) * sub
	var g: Array = []
	for i in n + 1:
		var t := float(i) / n * (prof.size() - 1)
		var k := mini(int(t), prof.size() - 2)
		var f := t - k
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		var z := lerpf(a[0], b[0], f)
		f = f * f * (3.0 - 2.0 * f) * 0.5 + f * 0.5
		var w := lerpf(a[1], b[1], f)
		var up := lerpf(a[2], b[2], f)
		var dn := lerpf(a[3], b[3], f)
		var yc := lerpf(a[4], b[4], f)
		var row: Array = []
		for j in 12:
			var ang := TAU * j / 12.0
			var sx := sin(ang)
			var cy := -cos(ang)
			var p := Vector3(w * sx, yc + (up * cy if cy > 0.0 else dn * cy * 0.9), z)
			var nrm := Vector3(sx / maxf(w, 0.0003), cy / maxf(up if cy > 0.0 else dn, 0.0003), 0.0).normalized()
			# (the throat: under the head)
			var throat := smoothstep(0.2, 0.8, -cy) * smoothstep(-0.0005, -0.003, z) * smoothstep(-0.0102, -0.008, z)
			row.append([p, nrm, Color(0, throat, 0, 1), Vector2.ZERO, Vector2.ZERO])
		g.append(row)
	_quads(st, g, true)
	var leg := Color(1, 0, 0, 1)
	for sx in [1.0, -1.0]:
		# (the eye: a low mound of skin with the dark eye set in its side)
		_blob(st, Vector3(sx * 0.0031, 0.0074, -0.0046), Vector3(0.0015, 0.0012, 0.0019), Color(0, 0, 0, 1))
		_blob(st, Vector3(sx * 0.0039, 0.0076, -0.0049), Vector3(0.0009, 0.0009, 0.0012), Color(0, 0, 1, 1))
		# hind leg, folded: thigh forward and out, shank back, the long foot forward again
		var hip := Vector3(sx * 0.004, 0.0036, 0.0072)
		var knee := Vector3(sx * 0.0088, 0.0032, 0.0022)
		var ankle := Vector3(sx * 0.0078, 0.0014, 0.0088)
		var toes := Vector3(sx * 0.0102, 0.0006, 0.0036)
		_tube(st, [hip, hip.lerp(knee, 0.5) + Vector3(0, 0.0006, 0), knee], [[0.0019, 0.0017], [0.0018, 0.0016], [0.0012, 0.0012]], Vector3.UP, leg)
		_tube(st, [knee, ankle], [[0.0012, 0.0012], [0.0008, 0.0008]], Vector3.UP, leg)
		_tube(st, [ankle, toes], [[0.0008, 0.0007], [0.0007, 0.0004]], Vector3.UP, leg)
		for toe in 4:
			var d := Vector3(sx * (0.25 + 0.3 * toe), 0, -1.0 + 0.25 * toe).normalized()
			_tube(st, [toes, toes + d * (0.0034 - 0.0004 * absf(toe - 1.5)) + Vector3(0, -0.0003, 0)], [[0.00035, 0.0003], [0.00018, 0.00018]], Vector3.UP, leg)
		# foreleg
		var sh := Vector3(sx * 0.004, 0.0038, -0.0036)
		var el := Vector3(sx * 0.0064, 0.0024, -0.003)
		var hand := Vector3(sx * 0.0058, 0.0005, -0.0062)
		_tube(st, [sh, el, hand], [[0.0011, 0.0011], [0.0009, 0.0009], [0.0006, 0.0005]], Vector3.UP, leg)
		for fin in 3:
			var d := Vector3(sx * (fin - 0.6) * 0.7, 0, -1.0).normalized()
			_tube(st, [hand, hand + d * 0.0022 + Vector3(0, -0.0002, 0)], [[0.0003, 0.0003], [0.00016, 0.00016]], Vector3.UP, leg)
	return st.commit()
