extends RefCounted
## The small things on land, modeled in code (item 7 of the work list): snail shells (the ones
## the hermit crabs carry, and the Seychelles snail's own), the land hermit crab, the giant
## millipede's body rings, the snail, and the plants of the summit granite (the pitcher plant
## Nepenthes pervillei, the tropicbird orchid, the leafless wild vanilla).
## Preloaded by scripts/small_land.gd (no class_name). Look at them with tools/preview.gd.

const SM := preload("res://scripts/small_models.gd")


static func _v(pos: Vector3, nrm: Vector3, col: Color, uv := Vector2.ZERO, uv2 := Vector2.ZERO) -> Array:
	return [pos, nrm, col, uv, uv2]


# ------------------------------------------------------------------ shells
## A coiled snail shell: a tube that grows as it winds around and down an axis. Built with the
## apex at the origin and the axis along +Y (the shell hangs below the apex); it winds
## clockwise seen from the apex, as nearly all snails do. Returns the mesh (colors by vertex)
## and where its mouth is: {"mesh", "ap": the middle of the mouth, "dir": the way the mouth
## faces, "r": the mouth's radius, "low": the lowest y}.
## kind: 0 turban, 1 nerite, 2 top shell, 3 cerith (these four lie on the beaches and are what
## the hermit crabs live in), 4 the Seychelles snail (Stylodonta unidentata). `size`: its
## width in meters.
const SHELLS := [
	{"w": 3.6, "g": 2.0, "R": 0.50, "H": 1.15, "rr": 0.56, "ra": 0.64},
	{"w": 2.8, "g": 2.9, "R": 0.46, "H": 0.82, "rr": 0.60, "ra": 0.68},
	{"w": 5.0, "g": 1.5, "R": 0.55, "H": 1.55, "rr": 0.46, "ra": 0.44},
	{"w": 7.0, "g": 1.32, "R": 0.40, "H": 2.5, "rr": 0.42, "ra": 0.52},
	{"w": 4.4, "g": 1.75, "R": 0.50, "H": 0.98, "rr": 0.52, "ra": 0.50},
]


static func _shell_color(kind: int, th: float, ph: float, s: float) -> Color:
	var c := Color(0.7, 0.66, 0.58)
	match kind:
		0:
			# turban: cream, with green-brown flames across the whorls; bleached by the sun
			var fl := smoothstep(0.1, 0.7, sin(th * 6.0 + sin(ph * 2.0) * 1.6))
			c = Color(0.8, 0.75, 0.62).lerp(Color(0.4, 0.36, 0.22), fl * 0.75)
		1:
			# nerite: nearly black, with pale cords running along the whorl
			var cord := smoothstep(0.2, 0.75, sin(ph * 7.0)) * (0.55 + 0.45 * sin(th * 5.0 + ph))
			c = Color(0.1, 0.1, 0.11).lerp(Color(0.78, 0.76, 0.7), clampf(cord, 0.0, 1.0) * 0.8)
		2:
			# top shell: pinkish white with slanting red-brown stripes
			var stp := smoothstep(0.25, 0.75, sin(th * 9.0 + ph * 1.6))
			c = Color(0.86, 0.78, 0.72).lerp(Color(0.5, 0.2, 0.14), stp * 0.8)
		3:
			# cerith: chalky gray-white, brown lines along the whorls
			var ln := smoothstep(0.6, 0.9, sin(ph * 5.0 + 0.6))
			c = Color(0.74, 0.71, 0.64).lerp(Color(0.36, 0.26, 0.18), ln * 0.7)
		4:
			# the Seychelles snail: glossy chestnut, fine darker growth lines, a paler band round
			# the widest part, the old whorls at the top worn pale
			var gl := 0.5 + 0.5 * sin(th * 46.0 + sin(ph * 3.0) * 0.8)
			c = Color(0.4, 0.2, 0.085).lerp(Color(0.2, 0.09, 0.04), gl * 0.6)
			c = c.lerp(Color(0.66, 0.48, 0.22), smoothstep(0.86, 0.99, cos(ph - 0.15)) * 0.65)
			c = c.lerp(Color(0.6, 0.5, 0.36), (1.0 - smoothstep(0.03, 0.22, s)) * 0.7)
	if kind < 4:
		# (shells from the beach: the oldest whorls are worn white)
		c = c.lerp(Color(0.84, 0.82, 0.76), (1.0 - smoothstep(0.04, 0.3, s)) * 0.8)
	return c


static func shell(kind: int, size: float) -> Dictionary:
	var k: Dictionary = SHELLS[kind]
	var per := 20
	var n := int(float(k["w"]) * per)
	var sides := 10
	var g: Array = []
	var width := 0.0
	for i in n + 1:
		var th := -TAU * float(k["w"]) * (1.0 - float(i) / n)     # 0 at the mouth
		var s := pow(float(k["g"]), th / TAU)
		var er := Vector3(cos(th), 0, sin(th))
		var c := er * (float(k["R"]) * s) - Vector3(0, float(k["H"]) * s, 0)
		var row: Array = []
		for j in sides:
			var ph := TAU * j / sides
			# (knobs on the shoulders of the top shell and the cerith)
			var knob := 1.0
			if kind == 2 or kind == 3:
				knob += 0.07 * cos(th * 11.0) * maxf(sin(ph), 0.0)
			var off := (er * (cos(ph) * float(k["rr"])) + Vector3(0, sin(ph) * float(k["ra"]), 0)) * (s * knob)
			var nrm := (er * (cos(ph) * float(k["ra"])) + Vector3(0, sin(ph) * float(k["rr"]), 0)).normalized()
			row.append(_v(c + off, nrm, _shell_color(kind, th, ph, s)))
			width = maxf(width, absf((c + off).x))
		g.append(row)
	var sc := size / (width * 1.75)
	var low := 0.0
	for row: Array in g:
		for q: Array in row:
			q[0] = (q[0] as Vector3) * sc
			low = minf(low, (q[0] as Vector3).y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	SM._quads(st, g, true)
	# the mouth: dark inside
	var ap := Vector3(float(k["R"]), -float(k["H"]), 0) * sc
	var dir := Vector3(0, 0, 1)
	var rr: float = float(k["rr"]) * sc
	var inner := ap - dir * rr * 0.55
	var dark := Color(0.05, 0.035, 0.03)
	for j in sides:
		var a: Array = g[n][j]
		var b: Array = g[n][(j + 1) % sides]
		var lip := (a[2] as Color).lerp(dark, 0.8)
		SM._emit(st, _v(inner, dir, dark), _v(a[0], dir, lip), _v(b[0], dir, lip))
	return {"mesh": st.commit(), "ap": ap, "dir": dir, "r": rr, "low": low}


## The turn that carries the shell's mouth direction (`dir`, +Z as built) onto `face` and its
## axis (+Y, toward the apex) as near `up` as that allows.
static func shell_basis(face: Vector3, up: Vector3) -> Basis:
	var f1 := face.normalized()
	var f2 := (up - f1 * up.dot(f1)).normalized()
	var f3 := f1.cross(f2)
	# built frame: e1 = +Z (mouth), e2 = +Y (apex), e3 = e1 x e2 = -X
	return Basis(-f3, f2, f1)


# ------------------------------------------------------------------ the land hermit crab
## A land hermit crab (Coenobita) without its shell: what shows in front of the shell's mouth.
## It walks forward (-Z), unlike the true crabs; the sand is y = 0; the shell's mouth is at
## H_AP. Two pairs of long walking legs, jointed in shaders/hermit.gdshader as the ghost
## crab's are (the vertices of a leg are stored relative to their bone: UV = (along the bone,
## offset in the leg's plane), UV2.x = across; COLOR.r 0.25 upper / 0.5 lower bone, COLOR.g
## which leg (0 front, 1 second), COLOR.b which side (1 = +x, its right)). The rest:
## COLOR.r 0 (body, eye stalks, feelers: UV2.y = how much a vertex waves) or 0.75 (the claws;
## the left one is the big one, the door of the shell). COLOR.a paints: 1 the armor, 0.8 the
## big claw, 0.6 the pale eye stalks, 0.4 the dark tips of the feet, 0 the eyes.
## (the shader has the same numbers: keep the two in step)
const H_AP := Vector3(0.0, 0.019, 0.012)
const H_HIP_X := [0.008, 0.0085]
const H_HIP_Y := 0.017
const H_HIP_Z := [-0.004, 0.004]
const H_FAN := [0.7, 1.75]          # the leg's bearing from straight ahead, to its side
const H_REACH := [0.040, 0.044]
const H_L1 := 0.024
const H_L2 := 0.034


static func _hermit_leg(id: int, side: float) -> Dictionary:
	var h := Vector3(side * float(H_HIP_X[id]), H_HIP_Y, H_HIP_Z[id])
	var fan: float = H_FAN[id]
	var t := h + Vector3(side * sin(fan), 0, -cos(fan)) * float(H_REACH[id])
	t.y = 0.0
	var d := t - h
	var dist := clampf(d.length(), 0.012, H_L1 + H_L2 - 0.002)
	var dir := d.normalized()
	var u := (Vector3.UP - dir * dir.y).normalized()
	var a := (H_L1 * H_L1 - H_L2 * H_L2 + dist * dist) / (2.0 * dist)
	var k := h + dir * a + u * sqrt(maxf(H_L1 * H_L1 - a * a, 0.0))
	var w := dir.cross(u).normalized()
	var e0 := (k - h).normalized()
	var e1 := (h + dir * dist - k).normalized()
	return {"h": h, "k": k, "w": w, "e0": e0, "v0": w.cross(e0), "e1": e1, "v1": w.cross(e1)}


static func hermit() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var armor := Color(0, 0, 0, 1)
	# the shield behind the eyes, and the soft body going back into the shell
	SM._blob(st, Vector3(0, 0.0205, -0.005), Vector3(0.0095, 0.0075, 0.0115), armor)
	SM._blob(st, Vector3(0, 0.019, 0.008), Vector3(0.0105, 0.0095, 0.012), armor)
	for side: float in [1.0, -1.0]:
		# the eyes: long pale stalks side by side, the dark eye at the end
		var stalk := Color(0, 0, 0, 0.6)
		var e0 := Vector3(side * 0.0032, 0.0245, -0.0125)
		var e1 := Vector3(side * 0.0046, 0.0345, -0.0185)
		SM._tube(st, [e0, e0.lerp(e1, 0.5), e1], [[0.0017, 0.0013], [0.0016, 0.0012], [0.0017, 0.0013]], Vector3.RIGHT, stalk, [0.0, 0.05, 0.1])
		SM._blob(st, e1 + Vector3(0, 0.0012, -0.0006), Vector3(0.0021, 0.0025, 0.0019), Color(0, 0, 0, 0))
		# the long feelers, out to the front and the side; the short pair between the eyes
		var f0 := Vector3(side * 0.0065, 0.0225, -0.013)
		SM._tube(st, [f0, f0 + Vector3(side * 0.006, 0.006, -0.011), f0 + Vector3(side * 0.015, 0.006, -0.027), f0 + Vector3(side * 0.024, 0.001, -0.043)],
			[[0.0009, 0.0009], [0.0007, 0.0007], [0.0005, 0.0005], [0.0002, 0.0002]], Vector3.UP, armor, [0.0, 0.2, 0.6, 1.0])
		var g0 := Vector3(side * 0.0016, 0.024, -0.014)
		SM._tube(st, [g0, g0 + Vector3(side * 0.001, 0.007, -0.008), g0 + Vector3(side * 0.0012, 0.0055, -0.014)],
			[[0.0007, 0.0007], [0.0006, 0.0006], [0.0003, 0.0003]], Vector3.UP, armor, [0.0, 0.3, 0.7])
		# the claws: the left (-x) is the big one
		var big := side < 0.0
		var kk := 1.0 if big else 0.66
		var claw := Color(0.75, 0, 0, 0.8 if big else 1.0)
		var s0 := Vector3(side * 0.0075, 0.0155, -0.008)
		var el := Vector3(side * 0.0175, 0.0145, -0.019)
		var palm := Vector3(side * 0.0115, 0.0095, -0.031) if big else Vector3(side * 0.0105, 0.0085, -0.027)
		var tip := palm + Vector3(-side * 0.006, -0.0055, -0.0095) * kk
		SM._tube(st, [s0, s0.lerp(el, 0.55) + Vector3(0, 0.002, 0), el], [[0.0032 * kk, 0.003 * kk], [0.0036 * kk, 0.0032 * kk], [0.0034 * kk, 0.003 * kk]], Vector3.UP, claw, [0.0, 0.3, 0.6])
		SM._tube(st, [el, el.lerp(palm, 0.6), palm], [[0.0034 * kk, 0.003 * kk], [0.0056 * kk, 0.0046 * kk], [0.0062 * kk, 0.005 * kk]], Vector3.UP, claw, [0.6, 0.85, 1.0])
		SM._blob(st, palm, Vector3(0.0068, 0.0058, 0.0074) * kk, claw)
		SM._tube(st, [palm + Vector3(0, 0.002 * kk, -0.003 * kk), palm.lerp(tip, 0.6) + Vector3(0, 0.002 * kk, 0), tip],
			[[0.0036 * kk, 0.0026 * kk], [0.0026 * kk, 0.0018 * kk], [0.0003, 0.0003]], Vector3.UP, claw, [1.0, 1.0, 1.0])
		SM._tube(st, [palm + Vector3(-side * 0.002 * kk, -0.003 * kk, -0.002 * kk), palm.lerp(tip, 0.6) + Vector3(-side * 0.0015 * kk, -0.003 * kk, 0), tip + Vector3(0, -0.0006, 0)],
			[[0.003 * kk, 0.0022 * kk], [0.0022 * kk, 0.0015 * kk], [0.0003, 0.0003]], Vector3.UP, claw, [1.0, 1.0, 1.0])
		# two walking legs: an upper bone to the knee, a lower one ending in a long pointed foot
		for id in 2:
			var fr := _hermit_leg(id, side)
			var bones := [
				[0.25, fr["h"], fr["e0"], fr["v0"], [-0.003, 0.004, 0.013, 0.021, H_L1 + 0.0015], [0.003, 0.0034, 0.0032, 0.0029, 0.0027], [0, 0, 0, 0, 0]],
				[0.5, fr["k"], fr["e1"], fr["v1"], [-0.001, 0.005, 0.013, 0.021, 0.028, H_L2], [0.0028, 0.0029, 0.0026, 0.0021, 0.0013, 0.0002], [0, 0, 0, -0.0003, -0.001, -0.0025]],
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
					var rb := ra * 0.72
					var row: Array = []
					for q in 8:
						var a := TAU * q / 8.0
						var oa := cos(a) * ra + float(bn[6][i])
						var ob := sin(a) * rb
						var nl := Vector3(0.0, cos(a) * rb, sin(a) * ra).normalized()
						if i == along.size() - 1:
							nl = (nl + Vector3(1, 0, 0)).normalized()
						var pos := org + e * float(along[i]) + v * oa + w * ob
						var nreal := (e * nl.x + v * nl.y + w * nl.z).normalized()
						var paint := 1.0 if float(bn[0]) < 0.4 or i < along.size() - 2 else 0.4
						row.append([pos, nreal, Color(bn[0], float(id), 1.0 if side > 0.0 else 0.0, paint), Vector2(along[i], oa), Vector2(ob, 0.0), nl])
					g.append(row)
				SM._quads(st, g, true)
	return st.commit()


# ------------------------------------------------------------------ the giant millipede
## One body ring of the Seychelles giant millipede (Sechelleptus seychellarum) with its two
## pairs of legs, and, folded away inside it, the parts only the first and the last ring
## show: the head with its feelers, and the blunt tail. The animal is a MultiMesh of these
## rings laid along the way its head has gone (scripts/small_land.gd); shaders/millipede.gdshader
## swings the legs in waves and shows or hides the parts by INSTANCE_CUSTOM.
## Forward = -Z, the ground is y = 0, the ring is M_PITCH long.
## COLOR.r: 0 ring, 0.33 a leg, 0.66 head, 1 tail. Legs: UV = the hip (x, z), UV2.x = which
## pair (0 front, 1 back), COLOR.g = how far out along the leg. Head: COLOR.g = how much a
## vertex of a feeler waves. Rings: UV.x = 0 front .. 1 back.
const M_PITCH := 0.0056
const M_R := 0.0066
const M_Y := 0.0082       # the height of the ring's middle


static func millipede() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := Color(0, 0, 0, 1)
	var g: Array = []
	# (each ring is a shallow barrel: a groove where it meets the next)
	for i in 4:
		var u := i / 3.0
		var z := M_PITCH * (u - 0.5) * 1.3
		var r := M_R * (0.93 + 0.07 * sin(u * PI))
		var row: Array = []
		for j in 12:
			var a := TAU * j / 12.0
			var d := Vector3(sin(a), -cos(a), 0)
			# a little flat underneath
			var p := Vector3(d.x * r, M_Y + d.y * r * (0.88 if d.y < 0.0 else 1.0), z)
			row.append(_v(p, Vector3(d.x, d.y, (u - 0.5) * 0.5).normalized(), ring, Vector2(u, float(j) / 12.0)))
		g.append(row)
	SM._quads(st, g, true)
	# the legs: out and down from under the ring, a knee, the tip on the ground
	for pair in 2:
		var z := M_PITCH * (0.25 if pair == 1 else -0.25)
		for side: float in [1.0, -1.0]:
			var hip := Vector3(side * 0.0028, 0.0035, z)
			var pts := [hip, Vector3(side * 0.0072, 0.0046, z), Vector3(side * 0.0098, 0.0022, z), Vector3(side * 0.0108, 0.0, z)]
			var rad := [0.00062, 0.00055, 0.00042, 0.00022]
			var lg: Array = []
			for i in pts.size():
				var p: Vector3 = pts[i]
				var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
				var u := Vector3(0, 0, 1)
				var v := t.cross(u).normalized()
				var row: Array = []
				for q in 5:
					var a := TAU * q / 5.0
					var off := (u * cos(a) + v * sin(a))
					row.append(_v(p + off * float(rad[i]), off, Color(0.33, float(i) / 3.0, 0, 1), Vector2(hip.x, hip.z), Vector2(float(pair), 0)))
				lg.append(row)
			SM._quads(st, lg, true)
	# the head: a rounded capsule a little narrower than the body, face down; two feelers
	var head := Color(0.66, 0, 0, 1)
	var hg: Array = []
	for i in 6:
		var th := PI * 0.5 * i / 5.0
		var row: Array = []
		for j in 12:
			var a := TAU * j / 12.0
			var d := Vector3(sin(a) * cos(th), -cos(a) * cos(th), -sin(th))
			var p := Vector3(d.x * M_R * 0.97, M_Y + d.y * M_R * (0.86 if d.y < 0.0 else 0.97) - sin(th) * 0.0012, -M_PITCH * 0.5 + d.z * M_R * 0.95)
			row.append(_v(p, d, head))
		hg.append(row)
	SM._quads(st, hg, true)
	for side: float in [1.0, -1.0]:
		var a0 := Vector3(side * 0.0036, M_Y - 0.0012, -M_PITCH * 0.5 - 0.0052)
		var pts := [a0, a0 + Vector3(side * 0.003, 0.0006, -0.0034), a0 + Vector3(side * 0.0052, -0.0022, -0.0072), a0 + Vector3(side * 0.0056, -0.0048, -0.0098)]
		var rad := [0.00065, 0.0006, 0.00055, 0.0004]
		var ag: Array = []
		for i in pts.size():
			var p: Vector3 = pts[i]
			var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			var u := Vector3.UP
			var v := t.cross(u).normalized()
			u = v.cross(t)
			var row: Array = []
			for q in 5:
				var a := TAU * q / 5.0
				var off := (u * cos(a) + v * sin(a))
				row.append(_v(p + off * float(rad[i]), off, Color(0.66, float(i) / 3.0, 0, 1)))
			ag.append(row)
		SM._quads(st, ag, true)
	# the tail: the last ring closes in a blunt point
	var tail := Color(1, 0, 0, 1)
	var tg: Array = []
	for i in 6:
		var th := PI * 0.5 * i / 5.0
		var row: Array = []
		for j in 12:
			var a := TAU * j / 12.0
			var d := Vector3(sin(a) * cos(th), -cos(a) * cos(th), sin(th))
			var p := Vector3(d.x * M_R * 0.96, M_Y + d.y * M_R * (0.86 if d.y < 0.0 else 0.96), M_PITCH * 0.5 + d.z * M_R * 1.25)
			row.append(_v(p, d, tail))
		tg.append(row)
	SM._quads(st, tg, true)
	st.index()
	return st.commit()


# ------------------------------------------------------------------ the Seychelles snail
## The snail's body without the shell (Stylodonta unidentata: the big land snail of the
## granite islands' forests, found nowhere else): a long foot, the head with two long eye
## stalks and two short feelers. Forward = -Z, the ground is y = 0, the shell sits over
## S_AP. For shaders/snail.gdshader: COLOR.r = how far a vertex is drawn in when the snail
## withdraws (1: all the way to the shell), COLOR.g = 1 along a tentacle (0 at its root),
## COLOR.b = 1 on the eyes, UV = the tentacle's root (x, z) and UV2.x its root's y.
const S_AP := Vector3(0.0, 0.012, 0.004)
const S_LEN := 0.078


static func snail() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [z, half-width, height]: head end first
	var prof := [[-0.036, 0.0002, 0.003], [-0.0345, 0.0042, 0.0062], [-0.03, 0.0066, 0.0088], [-0.022, 0.0078, 0.0098], [-0.01, 0.0088, 0.0108],
		[0.004, 0.0094, 0.0112], [0.016, 0.0086, 0.0092], [0.027, 0.0066, 0.0062], [0.036, 0.0038, 0.0036], [0.042, 0.0003, 0.0012]]
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
		var h := lerpf(a[2], b[2], f)
		var pull := clampf(absf(z - S_AP.z) / 0.04, 0.0, 1.0)
		var row: Array = []
		for j in 12:
			var ang := TAU * j / 12.0
			var sx := sin(ang)
			var cy := -cos(ang)
			# a flat sole with a skirt that spreads a little, a rounded back
			var p := Vector3(w * sx * (1.12 if cy < -0.3 else 1.0), h * maxf(cy, 0.0) + 0.0004, z)
			var nrm := Vector3(sx / maxf(w, 0.0004), maxf(cy, -0.2) / maxf(h, 0.0004), 0.0).normalized()
			row.append(_v(p, nrm, Color(pull, 0, 0, 1)))
		g.append(row)
	SM._quads(st, g, true)
	# (the hump of the body that goes up into the shell's mouth)
	SM._blob(st, S_AP + Vector3(0, 0.006, 0.006), Vector3(0.0105, 0.017, 0.015), Color(0, 0, 0, 1))
	# tentacles: the two long eye stalks up and forward, the two short feelers down at the mouth
	for side: float in [1.0, -1.0]:
		for low: bool in [false, true]:
			var root := Vector3(side * (0.003 if low else 0.0034), 0.004 if low else 0.0085, -0.033 if low else -0.03)
			var tip := root + (Vector3(side * 0.0035, -0.0015, -0.006) if low else Vector3(side * 0.007, 0.011, -0.012))
			var r0 := 0.0009 if low else 0.0012
			var tg: Array = []
			for i in 4:
				var u := i / 3.0
				var p := root.lerp(tip, u) + Vector3(0, (0.0 if low else 0.002) * sin(u * PI), 0)
				var t := (tip - root).normalized()
				var uu := (Vector3.UP - t * t.y).normalized()
				var vv := t.cross(uu)
				var row: Array = []
				for q in 6:
					var a := TAU * q / 6.0
					var off := uu * cos(a) + vv * sin(a)
					row.append(_v(p + off * r0 * (1.0 - 0.35 * u), off, Color(1, u, 0, 1), Vector2(root.x, root.z), Vector2(root.y, 0)))
				tg.append(row)
			SM._quads(st, tg, true)
			if not low:
				# the eye: a dark bead at the tip of the stalk
				var e := tip + Vector3(0, 0.0004, -0.0003)
				var eg: Array = []
				for i in 5:
					var th := PI * i / 4.0
					var row: Array = []
					for q in 6:
						var a := TAU * q / 6.0
						var d := Vector3(sin(th) * cos(a), cos(th), sin(th) * sin(a))
						row.append(_v(e + d * 0.0012, d, Color(1, 1, 1, 1), Vector2(root.x, root.z), Vector2(root.y, 0)))
					eg.append(row)
				SM._quads(st, eg, true)
	return st.commit()


# ------------------------------------------------------------------ putting them together
static func shell_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.38
	m.metallic_specular = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The width a shell of this kind must have for its mouth to have the radius r.
static func shell_size_for(kind: int, r: float) -> float:
	var k: Dictionary = SHELLS[kind]
	return r * (float(k["R"]) + float(k["rr"])) * 1.75 / float(k["rr"])


static func _lowest(mesh: Mesh, xf: Transform3D) -> float:
	var low := 1e9
	for v: Vector3 in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		low = minf(low, (xf * v).y)
	return low


## A hermit crab in its shell. `sh` is what shell() gave, for a mouth of radius 0.0155 (the
## crab is built to that). The shell is carried with its mouth over the crab's body, facing
## forward and down, the spire up and back and over to the right; its lowest whorl just
## clears the sand. Returns {"root", "body", "shell", "rest": how far the shell sinks to lie
## on the sand when the crab has drawn in}.
static func hermit_node(body_mesh: Mesh, body_mat: Material, sh: Dictionary, shell_mat: Material) -> Dictionary:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = body_mat
	body.extra_cull_margin = 0.05
	root.add_child(body)
	var smi := MeshInstance3D.new()
	smi.mesh = sh["mesh"]
	smi.material_override = shell_mat
	var b := shell_basis(Vector3(0.0, -0.42, -1.0), Vector3(0.5, 1.0, 0.35))
	var xf := Transform3D(b, H_AP + Vector3(0, 0.0, 0.003) - b * (sh["ap"] as Vector3))
	var low := _lowest(sh["mesh"], xf)
	# (carried: the lowest whorl a millimeter or two over the sand)
	xf.origin.y += 0.0015 - low
	smi.transform = xf
	root.add_child(smi)
	return {"root": root, "body": body, "shell": smi, "rest": 0.0015}


## The Seychelles snail: body and shell. {"root", "body", "shell"}
static func snail_node(body_mesh: Mesh, body_mat: Material, sh: Dictionary, shell_mat: Material) -> Dictionary:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = body_mat
	body.extra_cull_margin = 0.05
	root.add_child(body)
	var smi := MeshInstance3D.new()
	smi.mesh = sh["mesh"]
	smi.material_override = shell_mat
	# the shell rides on the back: its mouth at the front, facing down onto the neck, the spire
	# out to the right and a little up and back (a right-handed shell, as nearly all are)
	var b := shell_basis(Vector3(0.0, -1.0, 0.12), Vector3(1.0, 0.45, 0.35))
	var xf := Transform3D(b, S_AP - b * (sh["ap"] as Vector3))
	xf.origin.y += 0.004 - _lowest(sh["mesh"], xf)
	smi.transform = xf
	root.add_child(smi)
	return {"root": root, "body": body, "shell": smi}


# ------------------------------------------------------------------ plants of the summit granite
static func plant_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/plant.gdshader")
	return m


## A strap of leaf from `base` along `dir`, `length` long and `width` wide at its widest:
## `rise` lifts it, `droop` bends it over toward the tip, `fold` sinks the midrib (a shallow
## V). `blunt`: 0 a pointed tip .. 1 a strap cut square. Colors c0 at the base to c1 at the
## tip; `sway`: how much the tip moves in the wind. Returns its tip.
static func _leaf(st: SurfaceTool, base: Vector3, dir: Vector3, up: Vector3, length: float, width: float, rise: float, droop: float,
		fold: float, blunt: float, c0: Color, c1: Color, sway: float, wax := 0.0) -> Vector3:
	var side := dir.cross(up).normalized()
	var n := 6
	var g: Array = []
	var tip := base
	for i in n + 1:
		var t := float(i) / n
		var mid := base + dir * (length * t) + up * (length * (rise * t - droop * t * t))
		tip = mid
		var w := width * 0.5 * pow(sin(PI * pow(t, 0.75) * (1.0 - 0.14 * blunt)), 0.6 + 0.3 * (1.0 - blunt)) + 0.0006
		if i == 0:
			w = width * 0.16
		# the leaf's own up at this point: square to the way it runs
		var tang := (dir + up * (rise - 2.0 * droop * t)).normalized()
		var nrm := side.cross(tang).normalized()
		var col := c0.lerp(c1, t)
		var row: Array = []
		for j in 3:
			var s := float(j - 1)
			var p := mid + side * (s * w) + nrm * (absf(s) * fold * w)
			var nn := (nrm - side * (s * fold * 0.8)).normalized()
			# (the midrib is a shade paler)
			row.append(_v(p, nn, col.lerp(Color(0.74, 0.76, 0.4), 0.22) if j == 1 else col, Vector2(t, 0.5 + 0.5 * s), Vector2(sway * t * t, wax)))
		g.append(row)
	SM._quads(st, g, false)
	return tip


static func _stalk(st: SurfaceTool, pts: Array, r0: float, r1: float, c0: Color, c1: Color, sway0: float, sway1: float, sides := 5) -> void:
	var g: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var u := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
		var v := t.cross(u).normalized()
		u = v.cross(t)
		var f := float(i) / maxf(pts.size() - 1, 1)
		var row: Array = []
		for q in sides:
			var a := TAU * q / sides
			var off := u * cos(a) + v * sin(a)
			row.append(_v(p + off * lerpf(r0, r1, f), off, c0.lerp(c1, f), Vector2.ZERO, Vector2(lerpf(sway0, sway1, f), 0)))
		g.append(row)
	SM._quads(st, g, true)


## One pitcher of Nepenthes pervillei standing at `base`: a goblet narrow at the foot and
## widening to a round mouth with a thin rim, open (dark inside), the small round lid held
## up behind the mouth. `age`: 0 young (yellow-green) .. 1 old (deep red). `lean`: its axis.
static func _pitcher_cup(st: SurfaceTool, base: Vector3, axis: Vector3, h: float, age: float, yaw: float, sway: float) -> void:
	var young := Color(0.62, 0.68, 0.2)
	var ripe := Color(0.85, 0.5, 0.12)
	var old := Color(0.6, 0.13, 0.07)
	var body := young.lerp(ripe, clampf(age * 2.0, 0.0, 1.0)).lerp(old, clampf(age * 2.0 - 1.0, 0.0, 1.0))
	var foot := body.lerp(Color(0.5, 0.58, 0.18), 0.6)
	var ax := axis.normalized()
	var u := (Vector3.RIGHT - ax * ax.x).normalized().rotated(ax, yaw)
	var v := ax.cross(u)
	# [height, radius] as shares of h
	var prof := [[0.0, 0.02], [0.05, 0.075], [0.15, 0.125], [0.34, 0.156], [0.58, 0.158], [0.8, 0.162], [0.94, 0.172], [1.0, 0.19], [0.985, 0.206]]
	var sides := 8
	var g: Array = []
	for i in prof.size():
		var y: float = float(prof[i][0]) * h
		var r: float = float(prof[i][1]) * h
		var col := foot.lerp(body, smoothstep(0.0, 0.55, float(prof[i][0])))
		if i >= prof.size() - 2:
			col = body.lerp(Color(0.45, 0.1, 0.05), 0.55)     # the rim
		var slope := 0.35 if i < prof.size() - 1 else -0.6
		var row: Array = []
		for q in sides:
			var a := TAU * q / sides
			var d := u * cos(a) + v * sin(a)
			row.append(_v(base + ax * y + d * r, (d - ax * slope).normalized(), col, Vector2.ZERO, Vector2(sway * float(prof[i][0]), 1.0)))
		g.append(row)
	SM._quads(st, g, true)
	# inside: the wall going down from the rim into the dark
	var ig: Array = []
	var inner := [[0.985, 0.206, 0.0], [0.99, 0.165, 0.2], [0.8, 0.14, 0.75], [0.62, 0.05, 1.0]]
	for k: Array in inner:
		var col := body.lerp(Color(0.05, 0.04, 0.02), float(k[2]))
		var row: Array = []
		for q in sides:
			var a := TAU * q / sides
			var d := u * cos(a) + v * sin(a)
			row.append(_v(base + ax * (float(k[0]) * h) + d * (float(k[1]) * h), (ax * 0.7 - d * 0.7).normalized(), col, Vector2.ZERO, Vector2(sway * float(k[0]), 1.0)))
		ig.append(row)
	SM._quads(st, ig, true)
	# the lid: a round leaf on a short neck at the back of the mouth, held up at a slant
	var back := -u
	var hinge := base + ax * (h * 1.0) + back * (h * 0.19)
	var lid_dir := (-back * 0.82 + ax * 0.57).normalized()
	var lid_side := ax.cross(lid_dir).normalized()
	var lid_n := lid_dir.cross(lid_side).normalized()
	var lc := hinge + lid_dir * (h * 0.16) + ax * (h * 0.03)
	var lcol := body.lerp(young, 0.3)
	var top := _v(lc + lid_n * (h * 0.02), lid_n, lcol, Vector2.ZERO, Vector2(sway, 1.0))
	for q in sides:
		var a0 := TAU * q / sides
		var a1 := TAU * (q + 1) / sides
		var p0 := lc + (lid_dir * cos(a0) * 1.15 + lid_side * sin(a0)) * (h * 0.15)
		var p1 := lc + (lid_dir * cos(a1) * 1.15 + lid_side * sin(a1)) * (h * 0.15)
		SM._emit(st, top, _v(p0, lid_n, lcol, Vector2.ZERO, Vector2(sway, 1.0)), _v(p1, lid_n, lcol, Vector2.ZERO, Vector2(sway, 1.0)))


## A clump of the Seychelles pitcher plant (Nepenthes pervillei: it grows only on the granite
## of these islands, scrambling over the bare rock in mats): several stems creeping out from
## one root and turning up at their ends, stiff yellow-green leaves all along them, and from
## the tips of many leaves a tendril that carries a pitcher, standing upright; more pitchers
## stand in a cluster on the rock about the root. Built around the origin on y = 0, about a
## meter across. {"mesh", "r": its radius}
static func pitcher(seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7100 + seed_ * 37
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stems := rng.randi_range(6, 9)
	var reach := 0.0
	var leaf_a := Color(0.36, 0.5, 0.14)
	var leaf_b := Color(0.56, 0.62, 0.2)
	var stem_c := Color(0.42, 0.3, 0.14)
	for s in stems:
		var az := TAU * (s + rng.randf_range(-0.3, 0.3)) / stems
		var dir := Vector3(cos(az), 0, sin(az))
		var perp := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(0.22, 0.6)
		var lift := rng.randf_range(0.05, 0.16)
		var wig := rng.randf_range(-0.12, 0.12)
		var n := 9
		var pts: Array = []
		for i in n + 1:
			var t := float(i) / n
			pts.append(dir * (length * t) + perp * (sin(t * 3.0) * wig) + Vector3(0, 0.012 + lift * pow(t, 2.4), 0))
		reach = maxf(reach, length + 0.2)
		_stalk(st, pts, 0.0065, 0.004, stem_c, Color(0.4, 0.46, 0.16), 0.0, 0.25)
		# leaves all along it, winding around the stem; they get longer toward the tip
		var leaves := rng.randi_range(9, 13)
		for l in leaves:
			var t := lerpf(0.06, 1.0, float(l) / (leaves - 1))
			var f := t * n
			var k := mini(int(f), n - 1)
			var at: Vector3 = (pts[k] as Vector3).lerp(pts[k + 1], f - k)
			var tang: Vector3 = ((pts[k + 1] as Vector3) - (pts[k] as Vector3)).normalized()
			var ang := l * 2.4 + rng.randf_range(-0.4, 0.4)
			var out := (perp * cos(ang) + Vector3.UP.lerp(tang, 0.3) * absf(sin(ang)) * 0.6 + tang * 0.55).normalized()
			if out.y < 0.05:
				out = (out + Vector3(0, 0.25, 0)).normalized()
			var ll := rng.randf_range(0.12, 0.17) * (0.75 + 0.5 * t)
			var old := rng.randf() < 0.15
			var c0 := leaf_a if not old else Color(0.42, 0.4, 0.14)
			var c1 := leaf_b if not old else Color(0.6, 0.5, 0.18)
			var tip := _leaf(st, at, out, Vector3.UP, ll, ll * 0.3, 0.5, 0.42, 0.25, 0.5, c0, c1, 0.5 + 0.5 * t)
			if rng.randf() < 0.4 and t > 0.2:
				# the tendril: on from the leaf's tip, down in a bow, and up into the pitcher's foot
				var h := rng.randf_range(0.08, 0.13)
				var hang := rng.randf_range(0.03, 0.07)
				var foot := tip + out * Vector3(1, 0, 1) * rng.randf_range(0.02, 0.05) - Vector3(0, hang, 0)
				foot.y = maxf(foot.y, 0.006)
				_stalk(st, [tip, tip.lerp(foot, 0.5) + out * 0.012 - Vector3(0, hang * 0.25, 0), foot - Vector3(0, 0.006, 0) + out * 0.006, foot], 0.0016, 0.0022,
					Color(0.5, 0.56, 0.2), Color(0.5, 0.5, 0.18), 0.5 + 0.5 * t, 0.4, 4)
				var lean := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12))
				_pitcher_cup(st, foot, lean, h, rng.randf(), atan2(out.z, out.x) + PI, 0.4)
				reach = maxf(reach, Vector2(foot.x, foot.z).length() + 0.05)
	# the pitchers on the rock about the root, each on a short tendril from a low leaf
	var low := rng.randi_range(5, 9)
	for i in low:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.06, 0.26)
		var foot := Vector3(cos(a) * r, 0.004, sin(a) * r)
		var out := Vector3(cos(a), 0, sin(a))
		var tip := _leaf(st, foot * 0.25 + Vector3(0, 0.02, 0), (out + Vector3(0, 0.5, 0)).normalized(), Vector3.UP, r * 0.8 + 0.06, 0.036, 0.3, 0.55, 0.25, 0.5, leaf_a, leaf_b, 0.3)
		_stalk(st, [tip, tip.lerp(foot, 0.6) + Vector3(0, -0.01, 0), foot], 0.0016, 0.0022, Color(0.5, 0.56, 0.2), Color(0.5, 0.5, 0.18), 0.3, 0.0, 4)
		_pitcher_cup(st, foot, Vector3(out.x * 0.1, 1.0, out.z * 0.1), rng.randf_range(0.1, 0.15), rng.randf_range(0.25, 1.0), a + PI, 0.25)
	st.index()
	return {"mesh": st.commit(), "r": reach}


## One flower of the tropicbird orchid at `at`, facing `face`: the broad white lip uppermost,
## five narrow green petals spread behind it, and the long green spur hanging down behind:
## the tropicbird's tail.
static func _orchid_flower(st: SurfaceTool, at: Vector3, face: Vector3, sz: float, sway: float) -> void:
	var f := face.normalized()
	var side := f.cross(Vector3.UP).normalized()
	var up := side.cross(f).normalized()
	var white := Color(0.97, 0.97, 0.93)
	var green := Color(0.5, 0.66, 0.26)
	# the lip: a shell-shaped white blade standing up, hollow toward the front, a point at the top
	var lip: Array = []
	for i in 4:
		var t := i / 3.0
		var half: float = sz * [0.1, 0.5, 0.42, 0.02][i]
		var row: Array = []
		for j in 3:
			var s := float(j - 1)
			var p := at + up * (sz * 0.95 * t) + side * (s * half) + f * (sz * (0.16 * absf(s) + 0.1 * t * t))
			row.append(_v(p, (f - side * s * 0.5).normalized(), white.lerp(Color(0.8, 0.9, 0.6), (1.0 - t) * 0.6), Vector2.ZERO, Vector2(sway, 1.0)))
		lip.append(row)
	SM._quads(st, lip, false)
	# the five petals
	for a: float in [-1.5708, -0.5, -2.64, 0.35, 2.79]:
		var d := (side * cos(a) + up * sin(a) - f * 0.25).normalized()
		_leaf(st, at, d, -f, sz * 0.95, sz * 0.17, 0.0, 0.12, 0.15, 0.0, green, green.lerp(Color(0.7, 0.8, 0.4), 0.5), sway * 0.4, 0.6)
	# the spur, and the flower's own stalk back to the spike
	_stalk(st, [at - f * (sz * 0.05), at - f * (sz * 0.45) - up * (sz * 0.35), at - f * (sz * 0.6) - up * (sz * 1.1), at - f * (sz * 0.45) - up * (sz * 1.75)], sz * 0.035, sz * 0.012, green, green, sway, sway, 4)


## The tropicbird orchid (Angraecum eburneum, the national flower of the Seychelles: it sits
## on the bare granite, held by thick gray roots): a fan of long leathery strap leaves in two
## ranks, and, when it flowers, one or two long arching spikes with a row of waxy flowers that
## all face the same way. `flowering`: how many spikes (0-2). {"mesh", "r"}
static func orchid(seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8200 + seed_ * 53
	var flowering := seed_ % 3            # of three plants, one is not in flower
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var facing := rng.randf() * TAU
	var fan := Vector3(cos(facing), 0, sin(facing))           # the fan spreads along this line
	var front := Vector3(-fan.z, 0, fan.x)
	var dark := Color(0.17, 0.36, 0.11)
	var light := Color(0.32, 0.5, 0.15)
	# roots: gray-white cords over the rock
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var len := rng.randf_range(0.1, 0.28)
		var d := Vector3(cos(a), 0, sin(a))
		var p := Vector3(-d.z, 0, d.x) * rng.randf_range(-0.05, 0.05)
		_stalk(st, [Vector3(0, 0.03, 0), d * (len * 0.35) + Vector3(0, 0.012, 0), d * (len * 0.7) + p + Vector3(0, 0.004, 0), d * len + p * 1.6 + Vector3(0, 0.001, 0)], 0.006, 0.0035,
			Color(0.62, 0.62, 0.56), Color(0.7, 0.7, 0.64), 0.0, 0.0)
	# the short stem and its leaves, left and right by turns, the lowest spreading widest
	var leaves := rng.randi_range(8, 11)
	_stalk(st, [Vector3(0, 0.0, 0), Vector3(0, leaves * 0.013 + 0.03, 0)], 0.014, 0.011, Color(0.3, 0.36, 0.16), dark, 0.0, 0.0, 6)
	var top := 0.0
	for l in leaves:
		var sgn := 1.0 if l % 2 == 0 else -1.0
		var t := float(l) / (leaves - 1)
		var tilt := lerpf(1.25, 0.3, t) + rng.randf_range(-0.08, 0.08)       # from the vertical
		var d := (fan * (sgn * sin(tilt)) + Vector3.UP * cos(tilt) + front * rng.randf_range(-0.06, 0.06)).normalized()
		var ll := rng.randf_range(0.3, 0.42) * (0.8 + 0.25 * sin(t * PI))
		var base := Vector3(0, 0.02 + l * 0.013, 0)
		var bend := (Vector3.UP - d * d.y).normalized()
		_leaf(st, base, d, bend, ll, 0.05, 0.0, rng.randf_range(0.2, 0.4), -0.35, 1.0, dark, light.lerp(dark, 0.4), 0.35)
		# (a strap leaf arches under its own weight: the outer half bends down)
		top = maxf(top, base.y + d.y * ll)
	# flower spikes: out of the fan, up and over in a bow, the flowers along the outer two thirds
	for s in flowering:
		var out := (front * (1.0 if s == 0 else -1.0) + fan * rng.randf_range(-0.5, 0.5)).normalized()
		var length := rng.randf_range(0.5, 0.7)
		var n := 10
		var pts: Array = []
		for i in n + 1:
			var t := float(i) / n
			pts.append(Vector3(0, 0.06, 0) + out * (length * 0.75 * t) + Vector3(0, length * (0.95 * t - 0.62 * t * t), 0))
		_stalk(st, pts, 0.004, 0.0022, Color(0.36, 0.5, 0.2), Color(0.5, 0.62, 0.26), 0.0, 1.0)
		var flowers := rng.randi_range(7, 11)
		for k in flowers:
			var t := lerpf(0.36, 0.98, float(k) / (flowers - 1))
			var f := t * n
			var i := mini(int(f), n - 1)
			var at: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], f - i)
			var sd := Vector3(-out.z, 0, out.x) * (1.0 if k % 2 == 0 else -1.0)
			var pos := at + sd * 0.03 + Vector3(0, 0.012, 0)
			_stalk(st, [at, pos], 0.0016, 0.0016, Color(0.5, 0.62, 0.26), Color(0.5, 0.62, 0.26), t * t, t * t, 4)
			_orchid_flower(st, pos, (out + sd * 0.25).normalized(), rng.randf_range(0.044, 0.054), t * t)
	st.index()
	return {"mesh": st.commit(), "r": 0.45}


## One flower of the wild vanilla at `at`, opening along `dir`: five white petals spread
## wide, and in their middle the lip rolled into a funnel, apricot inside.
static func vanilla_flower(st: SurfaceTool, at: Vector3, dir: Vector3, sz: float) -> void:
	var f := dir.normalized()
	var side := f.cross(Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(f).normalized()
	var white := Color(0.97, 0.96, 0.9)
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var d := (side * cos(a) + up * sin(a) + f * 0.45).normalized()
		_leaf(st, at, d, f, sz * 0.95, sz * 0.3, 0.0, -0.25, 0.2, 0.0, white.lerp(Color(0.8, 0.9, 0.6), 0.4), white, 0.5, 0.7)
	var g: Array = []
	var prof := [[0.0, 0.07, 0.0], [0.3, 0.12, 0.15], [0.62, 0.2, 0.6], [0.8, 0.31, 1.0]]
	for k: Array in prof:
		var row: Array = []
		for q in 7:
			var a := TAU * q / 7.0
			var d := side * cos(a) + up * sin(a)
			# (the rim is frilled)
			var r: float = float(k[1]) * sz * (1.0 + 0.12 * sin(a * 3.0) * float(k[2]))
			row.append(_v(at + f * (float(k[0]) * sz) + d * r, (d * 0.8 - f * 0.6).normalized(), white.lerp(Color(0.96, 0.6, 0.36), float(k[2])), Vector2.ZERO, Vector2(0.6, 0.7)))
		g.append(row)
	SM._quads(st, g, true)
