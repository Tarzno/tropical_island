extends RefCounted
## The small characters of the reef, modeled in code: two sea anemones and the anemonefish
## that live in them, the lionfish, the garden eel, the moray, the day octopus, and the lump
## of old reef rock with a hole in it that the moray and the octopus live in.
## Preloaded by seabed.gd and reef_life.gd (no class_name). Look at them with tools/preview.gd
## (`reef <name>`).
##
## The fish (anemonefish, lionfish) follow the conventions of sea_models.gd, whose builders
## they use: forward = -Z, the body 3.6 long and scaled to life size by the script;
## shaders/reef_fish.gdshader paints and moves them. The others are built life size, in meters;
## what their shaders read from UV and COLOR is said at each.

const SM := preload("res://scripts/sea_models.gd")
const L := 3.6


static func _z(u: float) -> float:
	return (u - 0.5) * L


## A tube through `pts` with one radius per point (or a Vector2: across, and up and down), one
## color and one UV.x per point; UV.y runs around it. The rings stand across the tube. Rows of
## [position, color, uv] are handed to sea_models' _grid, which sets the normals.
static func _tube(st: SurfaceTool, pts: Array, radii: Array, cols: Array, us: Array, sides := 8, up := Vector3.UP) -> void:
	var rows: Array = []
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var t: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var u := t.cross(up)
		u = u.normalized() if u.length() > 0.01 else t.cross(Vector3.RIGHT).normalized()
		var v := u.cross(t)
		var r: Variant = radii[i]
		var rx: float = r.x if r is Vector2 else float(r)
		var ry: float = r.y if r is Vector2 else float(r)
		var row: Array = []
		for k in sides + 1:
			var a := TAU * (k % sides) / float(sides)
			row.append([p + u * (cos(a) * rx) + v * (sin(a) * ry), cols[i], Vector2(us[i], float(k) / sides)])
		rows.append(row)
	SM._grid(st, rows, pts, true)


# ------------------------------------------------------------------ anemonefish
## An anemonefish: a deep oval body, rounded fins. `shaders/reef_fish.gdshader` paints it as
## the Seychelles anemonefish (species 0) or the skunk anemonefish (species 1) from the
## trunk's UV (x: snout 0 .. tail 1; y: 0 belly, 0.5 back) and from COLOR on the fins
## (r = 1: dorsal and tail fin; b = 1: pectoral, pelvic and anal fins; a = 0: the eyes).
static func anemonefish() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	SM._trunk(st, [
		[0.0, 0.004, 0.004, -0.004, -0.04], [0.015, 0.09, 0.13, -0.13, -0.04], [0.06, 0.18, 0.33, -0.31, -0.02],
		[0.14, 0.25, 0.53, -0.5, 0.0], [0.26, 0.3, 0.69, -0.66, 0.0], [0.39, 0.3, 0.75, -0.72, 0.0],
		[0.52, 0.26, 0.69, -0.67, 0.0], [0.63, 0.19, 0.53, -0.51, 0.0], [0.71, 0.13, 0.35, -0.33, 0.0],
		[0.77, 0.08, 0.23, -0.22, 0.0], [0.81, 0.045, 0.19, -0.18, 0.0], [0.835, 0.01, 0.17, -0.16, 0.0]], 14, 2, 1.0)
	# dorsal fin (spiny part and the higher soft part behind it), tail, anal fin
	SM._fin(st, SM._mid([[0.2, 0.6], [0.27, 0.9], [0.4, 1.0], [0.5, 0.94], [0.58, 1.02], [0.67, 0.92], [0.735, 0.5]]),
		SM._mid([[0.22, 0.58], [0.3, 0.68], [0.42, 0.72], [0.52, 0.66], [0.6, 0.55], [0.68, 0.38], [0.735, 0.26]]), 0.03, -1.0)
	SM._fin(st, SM._mid([[0.8, 0.17], [0.87, 0.36], [0.94, 0.45], [0.99, 0.32], [1.0, 0.0]]),
		SM._mid([[0.8, -0.17], [0.87, -0.36], [0.94, -0.45], [0.99, -0.32], [1.0, 0.0]]), 0.03, -1.0)
	SM._fin(st, SM._mid([[0.5, -0.64], [0.57, -0.9], [0.66, -0.88], [0.735, -0.48]]),
		SM._mid([[0.5, -0.6], [0.58, -0.6], [0.67, -0.45], [0.735, -0.26]]), 0.025, 2.0, -1.0)
	for side in [1.0, -1.0]:
		# pelvic and pectoral fins, eyes
		SM._fin(st, SM._pair([[0.1, -0.6, 0.3], [0.14, -0.88, 0.36], [0.15, -1.04, 0.44]], side),
			SM._pair([[0.08, -0.62, 0.38], [0.11, -0.82, 0.42], [0.15, -1.02, 0.45]], side), 0.02, 2.0, -1.0)
		SM._fin(st, SM._pair([[0.28, -0.02, 0.255], [0.5, 0.06, 0.33], [0.68, 0.02, 0.42]], side),
			SM._pair([[0.28, -0.36, 0.275], [0.48, -0.38, 0.36], [0.67, -0.06, 0.43]], side), 0.018, 2.0, -1.0)
		SM._ball(st, Vector3(0.2 * side, 0.2, _z(0.1)), Vector3(0.035, 0.085, 0.085), Color(0, 0, 0, 0))
	return st.commit()


# ------------------------------------------------------------------ sea anemones
## What shaders/anemone.gdshader reads: UV.y = how far up its tentacle a vertex is (0 on the
## disc and the column: they do not sway), UV.x = the tentacle's own phase; COLOR.rgb = a shade
## (times the instance color), COLOR.b on the disc = 1 at the margin, which lifts and falls
## (there the shade is gray, so b is the shade too); COLOR.a = 1 tentacles and disc, 0.5 the
## column (painted in a color of its own).
## Built for a disc of radius 1; the instance's scale is the disc's radius in meters.

static func _tentacle(st: SurfaceTool, root: Vector3, dir: Vector3, length: float, r: float, phase: float, segs: int, sides: int, shade: float, knob: float) -> void:
	var u := dir.cross(Vector3(0.31, 0.2, 0.93)).normalized()
	var v := dir.cross(u)
	var rows: Array = []
	var inside: Array = []
	for i in segs + 2:
		var f := minf(float(i) / segs, 1.0)
		# (a blunt end, a little swollen)
		var rr := r * (1.0 - 0.3 * f + knob * smoothstep(0.6, 1.0, f)) if i <= segs else 0.0
		var c := root + dir * (length * f + (r * 0.7 if i > segs else 0.0))
		var g := shade * lerpf(0.72, 1.0, f)
		var row: Array = []
		for k in sides + 1:
			var a := TAU * (k % sides) / float(sides)
			row.append([c + (u * cos(a) + v * sin(a)) * rr, Color(g, g, 0.0, 1.0), Vector2(phase, f)])
		rows.append(row)
		inside.append(c - dir * 0.001)
	SM._grid(st, rows, inside, true)


## Mertens' carpet anemone (Stichodactyla mertensii), the host of the Seychelles anemonefish:
## a broad disc that lies on the reef and follows it, the margin in soft folds, covered with
## short blunt tentacles.
static func carpet_anemone() -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = 41
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	var rings := 10
	var top: Array = []
	var inside: Array = []
	for i in rings + 1:
		var r := float(i) / rings
		var row: Array = []
		for j in segs + 1:
			var th := TAU * (j % segs) / float(segs)
			var p := _carpet(r, th)
			var m := smoothstep(0.7, 1.0, r)
			var shade := lerpf(0.8, 1.0, r)
			row.append([p, Color(shade, shade, m, 1.0), Vector2(th, 0.0)])
		top.append(row)
		inside.append(Vector3(0, -2.0, 0))
	SM._grid(st, top, inside, true)
	# the underside: from the margin in and down to the rock
	var under: Array = [[], [], []]
	for j in segs + 1:
		var th := TAU * (j % segs) / float(segs)
		var e := _carpet(1.0, th)
		(under[0] as Array).append([e, Color(1, 1, 1, 0.5), Vector2(th, 0.0)])
		(under[1] as Array).append([Vector3(e.x * 0.93, e.y * 0.3 - 0.02, e.z * 0.93), Color(1, 1, 0, 0.5), Vector2(th, 0.0)])
		(under[2] as Array).append([Vector3(e.x * 0.75, -0.08, e.z * 0.75), Color(1, 1, 0, 0.5), Vector2(th, 0.0)])
	SM._grid(st, under, [Vector3(0, 0.3, 0), Vector3(0, 0.3, 0), Vector3(0, 0.3, 0)], true)
	# tentacles: short fingers all over the disc
	for i in 460:
		var r := sqrt(g.randf_range(0.012, 1.0)) * 0.985
		var th := g.randf() * TAU
		var p := _carpet(r, th)
		var e := 0.03
		var n := (_carpet(r, th + e / maxf(r, 0.1)) - p).cross(_carpet(r + e, th) - p)
		n = n.normalized() if n.length() > 1e-9 else Vector3.UP
		if n.y < 0.0:
			n = -n
		_tentacle(st, p - n * 0.004, (n + Vector3(g.randf_range(-0.25, 0.25), 0, g.randf_range(-0.25, 0.25))).normalized(),
			g.randf_range(0.055, 0.085), g.randf_range(0.015, 0.02), g.randf(), 1, 4, g.randf_range(0.85, 1.1), 0.15)
	return st.commit()


## The carpet's disc at radius r (0..1) and angle th.
static func _carpet(r: float, th: float) -> Vector3:
	var rad := r * (1.0 + r * (0.1 * sin(3.0 * th + 1.0) + 0.06 * sin(7.0 * th + 0.3)))
	var y := 0.07 - 0.04 * exp(-r * r * 30.0) + 0.045 * sin(r * 7.0 + 2.0 * th) * r
	y += r * r * r * (0.06 * sin(5.0 * th + 0.7) + 0.035 * sin(8.0 * th + 2.1))
	return Vector3(cos(th) * rad, y, sin(th) * rad)


## The magnificent sea anemone (Heteractis magnifica): a stout column in a vivid color, a disc
## crowded with long blunt tentacles that sway with the swell. On the tops of coral heads.
static func magnificent_anemone() -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = 43
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 20
	# the column, flaring out to the disc's edge, and the disc
	var prof := [[0.62, -0.06], [0.58, 0.12], [0.56, 0.36], [0.64, 0.54], [0.84, 0.66], [1.0, 0.7]]
	var rows: Array = []
	var inside: Array = []
	for i in prof.size():
		var row: Array = []
		for j in segs + 1:
			var th := TAU * (j % segs) / float(segs)
			var rr: float = float(prof[i][0]) * (1.0 + 0.05 * sin(4.0 * th + i))
			row.append([Vector3(cos(th) * rr, prof[i][1], sin(th) * rr), Color(1, 1, 0, 0.5), Vector2(th, 0.0)])
		rows.append(row)
		inside.append(Vector3(0, float(prof[i][1]) + 0.3, 0))
	SM._grid(st, rows, inside, true)
	rows = []
	inside = []
	for i in 5:
		var r := float(i) / 4.0
		var row: Array = []
		for j in segs + 1:
			var th := TAU * (j % segs) / float(segs)
			row.append([Vector3(cos(th) * r, 0.7 + 0.08 * (1.0 - r * r), sin(th) * r), Color(0.7, 0.7, 0, 1.0), Vector2(th, 0.0)])
		rows.append(row)
		inside.append(Vector3(0, -2.0, 0))
	SM._grid(st, rows, inside, true)
	# the tentacles: upright in the middle, splayed outward at the edge
	var placed: Array = []
	for i in 2000:
		if placed.size() >= 150:
			break
		var r := sqrt(g.randf_range(0.03, 1.0))
		var th := g.randf() * TAU
		var p := Vector3(cos(th) * r, 0.7 + 0.08 * (1.0 - r * r), sin(th) * r)
		var ok := true
		for q: Vector3 in placed:
			if q.distance_squared_to(p) < 0.0155:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var dir := (Vector3.UP + Vector3(cos(th), 0, sin(th)) * (r * r * 1.5) + Vector3(g.randf_range(-0.2, 0.2), 0, g.randf_range(-0.2, 0.2))).normalized()
		_tentacle(st, p - dir * 0.02, dir, g.randf_range(0.36, 0.5), g.randf_range(0.04, 0.05), g.randf(), 3, 5, g.randf_range(0.85, 1.1), 0.3)
	return st.commit()


# ------------------------------------------------------------------ garden eel
## A spotted garden eel (Heteroconger hassi): a straight tube along +Y, 0.42 long, the head at
## the top looking toward +X. shaders/garden_eel.gdshader lets it stand out of the sand and
## bends it over: UV.y = the place along the body (0 the tail end .. 1 the snout), UV.x = the
## way around; VERTEX.xz = the offset from the body's line; COLOR.a = 0 on the eyes.
const EEL_LEN := 0.42

static func garden_eel() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	var rows: Array = []
	var inside: Array = []
	# (height along the body, radius)
	var prof := [[0.0, 0.003], [0.04, 0.0062], [0.2, 0.0072], [0.5, 0.0076], [0.8, 0.0076], [0.9, 0.008], [0.945, 0.0098], [0.975, 0.0094], [0.992, 0.0062], [1.0, 0.001]]
	# more rings where it bends
	var ys: Array = []
	for i in prof.size() - 1:
		var n := 4 if float(prof[i][0]) >= 0.2 and float(prof[i][0]) < 0.9 else 1
		for k in n:
			ys.append(lerpf(prof[i][0], prof[i + 1][0], float(k) / n))
	ys.append(1.0)
	for s: float in ys:
		var r := 0.0
		for i in prof.size() - 1:
			if s >= float(prof[i][0]) and s <= float(prof[i + 1][0]):
				r = lerpf(prof[i][1], prof[i + 1][1], (s - float(prof[i][0])) / (float(prof[i + 1][0]) - float(prof[i][0])))
		var row: Array = []
		for k in sides + 1:
			var a := TAU * (k % sides) / float(sides)
			row.append([Vector3(cos(a) * r, s * EEL_LEN, sin(a) * r), Color(1, 1, 1, 1), Vector2(float(k) / sides, s)])
		rows.append(row)
		inside.append(Vector3(0, s * EEL_LEN - 0.0005, 0))
	SM._grid(st, rows, inside, true)
	# the eyes: large, high on the head
	for side in [1.0, -1.0]:
		var c := Vector3(0.0036, 0.957 * EEL_LEN, 0.0082 * side)
		var er: Array = []
		var ein: Array = []
		for i in 4:
			var row: Array = []
			for j in 7:
				var th := PI * i / 3.0
				var ph := TAU * (j % 6) / 6.0
				row.append([c + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * 0.0034, Color(0, 0, 0, 0), Vector2(0.0, 0.957)])
			er.append(row)
			ein.append(c)
		SM._grid(st, er, ein, true)
	return st.commit()


# ------------------------------------------------------------------ the den
## A lump of old reef rock, half a meter and more across, with a hole in it: the mouth opens
## toward -Z and upward (along DEN_AXIS), dark inside. The moray and the octopus are set at
## DEN_MOUTH and come out along the axis; what is drawn back along it disappears in the dark
## and under the ground. Drawn with the corals' shader (boulder coral's mottling; the vertex
## shade carries the dark of the hole and the pink of the crusts on the rock).
## `midden`: the shells and stones an octopus leaves in front of its door. `tint`: the rock's
## color (the corals get theirs from their instances; a den is a single mesh).
const DEN_AXIS := Vector3(0.0, 0.643, -0.766)
const DEN_MOUTH := Vector3(0.0, 0.085, -0.12)

const DEN_CENTER := Vector3(0, -0.04, 0)

## The two numbers that give the rock of this seed its lumps.
static func den_shape(seed_: int) -> Vector2:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var k1 := g.randf_range(0.0, 6.0)
	return Vector2(k1, g.randf_range(0.0, 6.0))


## How far the rock's surface is from DEN_CENTER in the direction d (a unit vector), for the
## rock with the shape numbers k. shaders/octopus.gdshader has the same sum (`rock_r()`), to
## keep the arms on the rock and out of it: change the two together.
static func den_radius(d: Vector3, k: Vector2) -> float:
	var rad := 1.0 / sqrt(pow(d.x / 0.44, 2.0) + pow(d.y / 0.31, 2.0) + pow(d.z / 0.4, 2.0))
	# lumps and hollows
	rad *= 1.0 + 0.1 * sin(d.x * 5.3 + k.x) * sin(d.z * 4.7 + k.y) + 0.07 * sin(d.y * 9.0 + d.x * 6.0 + k.y) + 0.04 * sin(d.z * 13.0 + k.x * 2.0)
	# the hole: a deep dent around the axis, a lip around it
	var al := acos(clampf(d.dot(DEN_AXIS), -1.0, 1.0))
	var a0 := 0.5 + 0.06 * sin(atan2(d.z, d.x) * 3.0 + k.x)
	var dent := 1.0 - smoothstep(a0 * 0.45, a0, al)
	return rad * (1.0 - 0.6 * dent + 0.07 * exp(-pow((al - a0 * 1.12) / 0.12, 2.0)))


static func den_rock(seed_: int, midden := false, tint := Color(1, 1, 1)) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k1 := g.randf_range(0.0, 6.0)
	var k2 := g.randf_range(0.0, 6.0)
	var center := DEN_CENTER
	var rows: Array = []
	var inside: Array = []
	var nr := 18
	var nc := 36
	for i in nr + 1:
		var th := deg_to_rad(104.0) * i / nr
		var row: Array = []
		for j in nc + 1:
			var ph := TAU * (j % nc) / float(nc)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var rad := den_radius(d, Vector2(k1, k2))
			var al := acos(clampf(d.dot(DEN_AXIS), -1.0, 1.0))
			var a0 := 0.5 + 0.06 * sin(ph * 3.0 + k1)
			var dent := 1.0 - smoothstep(a0 * 0.45, a0, al)
			var v := 0.82 + 0.18 * sin(d.x * 11.0 + k1) * sin(d.y * 7.0 + d.z * 9.0 + k2)
			var pink := smoothstep(0.2, 0.7, sin(d.x * 6.0 + k2 * 1.7) * sin(d.z * 5.0 - k1))
			var col := Color(v * tint.r, v * lerpf(1.0, 0.84, pink) * tint.g, v * lerpf(1.0, 0.9, pink) * tint.b, 0.6)
			col = col.lerp(Color(0.02, 0.02, 0.02, 0.6), smoothstep(0.15, 0.6, dent))
			row.append([center + d * rad, col, Vector2.ZERO])
		rows.append(row)
		inside.append(center)
	SM._grid(st, rows, inside, true)
	if midden:
		for i in 13:
			var a := g.randf_range(-1.2, 1.2) - PI * 0.5
			var r := g.randf_range(0.42, 0.72)
			var c := Vector3(cos(a) * r * 1.05, g.randf_range(-0.01, 0.012), sin(a) * r)
			var size := g.randf_range(0.012, 0.03)
			var v := g.randf_range(0.5, 0.78)
			var col := Color(v, v * 0.96, v * 0.88, 1.0) if g.randf() < 0.6 else Color(v * 0.8, v * 0.62, v * 0.5, 1.0)
			var rr: Array = []
			var ins: Array = []
			var flat := g.randf_range(0.35, 0.7)
			var tilt := Basis(Vector3(g.randf_range(-1, 1), 0.2, g.randf_range(-1, 1)).normalized(), g.randf_range(-0.5, 0.5))
			for a_i in 4:
				var row: Array = []
				for b_i in 7:
					var th := PI * a_i / 3.0
					var ph := TAU * (b_i % 6) / 6.0
					row.append([c + tilt * (Vector3(sin(th) * cos(ph) * g.randf_range(0.7, 1.0), cos(th) * flat, sin(th) * sin(ph) * g.randf_range(0.7, 1.0)) * size), col, Vector2.ZERO])
				rr.append(row)
				ins.append(c)
			SM._grid(st, rr, ins, true)
	return st.commit()


# ------------------------------------------------------------------ moray
## A moray's head and the first meter of it, life size: the snout at z = 0, the body running
## back along +Z (shaders/moray.gdshader lays it along the way out of its hole and bends it).
## VERTEX = (across, up, distance behind the snout). COLOR.r = 1: the inside of the mouth;
## COLOR.b = 1: the lower jaw (it opens, hinged at MORAY_HINGE behind the snout);
## COLOR.a = 0: the eyes (UV.x = 1 in the middle of the eye: the pupil).
const MORAY_HINGE := 0.115

static func moray() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# s, half-width, top, bottom
	var prof := [[0.0, 0.006, 0.004, -0.005], [0.012, 0.017, 0.013, -0.013], [0.04, 0.026, 0.024, -0.022], [0.08, 0.032, 0.034, -0.03],
		[MORAY_HINGE, 0.036, 0.044, -0.038], [0.16, 0.04, 0.053, -0.045], [0.22, 0.041, 0.059, -0.05], [0.32, 0.039, 0.06, -0.052],
		[0.45, 0.037, 0.06, -0.052], [0.6, 0.037, 0.06, -0.052], [0.75, 0.037, 0.06, -0.052], [0.9, 0.037, 0.06, -0.052], [1.05, 0.037, 0.06, -0.052]]
	var mouth_y := -0.004
	var skin := Color(0, 1, 0, 1)
	# the head in two halves, each closed toward the mouth
	for half in 2:
		var rows: Array = []
		var inside: Array = []
		for i in 5:
			var s: float = prof[i][0]
			var hw: float = float(prof[i][1]) * (1.0 if half == 0 else 0.93)
			var ext: float = (float(prof[i][2]) - mouth_y) if half == 0 else (float(prof[i][3]) - mouth_y)
			var row: Array = []
			for k in 9:
				var a := PI * k / 8.0
				row.append([Vector3(cos(a) * hw, mouth_y + sin(a) * ext, s + (0.004 if half == 1 and i == 0 else 0.0)), Color(0, 1, half, 1), Vector2(s, 0.0)])
			# back along the roof of the mouth (or the floor of it)
			for k in 4:
				var x := lerpf(-hw, hw, (k + 0.5) / 4.0) * 0.8
				row.append([Vector3(x, mouth_y + ext * 0.12, s + 0.004 * i), Color(1, 1, half, 1), Vector2(s, 0.0)])
			row.append(row[0])
			rows.append(row)
			inside.append(Vector3(0, mouth_y + ext * 0.5, s))
		SM._grid(st, rows, inside, true)
	# the body
	var body: Array = []
	var inside_b: Array = []
	var sub := 3
	for i in range(4, prof.size() - 1):
		for q in sub + (1 if i == prof.size() - 2 else 0):
			var f := float(q) / sub
			var s := lerpf(prof[i][0], prof[i + 1][0], f)
			var hw := lerpf(prof[i][1], prof[i + 1][1], f)
			var top := lerpf(prof[i][2], prof[i + 1][2], f)
			var bot := lerpf(prof[i][3], prof[i + 1][3], f)
			var row: Array = []
			for k in 17:
				var a := TAU * (k % 16) / 16.0
				var y := sin(a)
				row.append([Vector3(cos(a) * hw, mouth_y + (y * (top - mouth_y) if y > 0.0 else -y * (bot - mouth_y)), s), skin, Vector2(s, 0.0)])
			body.append(row)
			inside_b.append(Vector3(0, 0, s))
	SM._grid(st, body, inside_b, true)
	# the fin along the back, from behind the head
	var fin: Array = [[], []]
	for i in 22:
		var s := lerpf(0.2, 1.05, i / 21.0)
		var top := 0.058 if s < 0.22 else 0.06
		var h := 0.024 * smoothstep(0.2, 0.34, s)
		(fin[0] as Array).append([Vector3(0, top - 0.006, s), skin, Vector2(s, 0.0)])
		(fin[1] as Array).append([Vector3(0, top + h, s + 0.01), skin, Vector2(s, 0.0)])
	SM._grid(st, fin, [Vector3(-1, 0.06, 0.5), Vector3(-1, 0.06, 0.5)], false)
	for side in [1.0, -1.0]:
		# the eyes, and the little tubes of the nostrils at the tip of the snout
		var c := Vector3(0.026 * side, 0.017, 0.056)
		var er: Array = []
		var ein: Array = []
		for i in 5:
			var row: Array = []
			for j in 9:
				var th := PI * i / 4.0
				var ph := TAU * (j % 8) / 8.0
				# (the pole looks outward)
				row.append([c + Vector3(cos(th) * side, sin(th) * cos(ph), sin(th) * sin(ph)) * Vector3(0.0045, 0.0072, 0.0072), Color(0, 0, 0, 0), Vector2(1.0 - float(i) / 2.0, 0.0)])
			er.append(row)
			ein.append(c)
		SM._grid(st, er, ein, true)
		_tube(st, [Vector3(0.008 * side, 0.008, 0.008), Vector3(0.01 * side, 0.014, -0.006)], [0.0028, 0.0022], [skin, skin], [0.0, 0.0], 5)
	return st.commit()


# ------------------------------------------------------------------ octopus
## The day octopus (Octopus cyanea), life size: the head at the origin looking along -Z, the
## mantle behind it, eight arms. shaders/octopus.gdshader moves it.
## Body: COLOR.r = 0, COLOR.b = how much a vertex belongs to the mantle (it swells with every
## breath), COLOR.a = 0 on the pupils.
## Arms: COLOR.r = 1; a vertex holds its place in the arm, not in space: UV.x = which arm
## ((index + 0.5) / 8, counted from the front around by the right), UV.y = how far along it
## (0..1), VERTEX.xy = the offset from the arm's line (across, up), NORMAL likewise;
## COLOR.g = 1 on the upper side .. 0 on the underside with the suckers.
const ARM_LEN := 0.55

static func octopus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0, 1, 0, 1)
	# head and mantle
	var pts := [Vector3(0, 0.03, -0.04), Vector3(0, 0.04, -0.03), Vector3(0, 0.048, -0.008), Vector3(0, 0.052, 0.028), Vector3(0, 0.064, 0.07),
		Vector3(0, 0.072, 0.115), Vector3(0, 0.07, 0.16), Vector3(0, 0.063, 0.198), Vector3(0, 0.056, 0.222), Vector3(0, 0.054, 0.23)]
	var radii := [0.004, Vector2(0.026, 0.02), Vector2(0.04, 0.034), Vector2(0.037, 0.033), Vector2(0.056, 0.05), Vector2(0.067, 0.062),
		Vector2(0.061, 0.058), Vector2(0.043, 0.042), Vector2(0.02, 0.02), 0.002]
	var cols: Array = []
	var us: Array = []
	for i in pts.size():
		cols.append(Color(0, 1, smoothstep(0.02, 0.09, (pts[i] as Vector3).z), 1))
		us.append(0.0)
	_tube(st, pts, radii, cols, us, 12)
	# the crown the arms spring from
	_tube(st, [Vector3(0, 0.05, -0.008), Vector3(0, 0.03, -0.006), Vector3(0, 0.008, -0.004), Vector3(0, -0.004, -0.004)],
		[0.03, 0.05, 0.058, 0.03], [skin, skin, skin, skin], [0.0, 0.0, 0.0, 0.0], 12, Vector3.FORWARD)
	for side in [1.0, -1.0]:
		# the eyes: raised mounds on top of the head, a dark bar of a pupil on each
		var c := Vector3(0.026 * side, 0.076, -0.012)
		var er: Array = []
		var ein: Array = []
		var pr: Array = []
		for i in 5:
			var row: Array = []
			var prow: Array = []
			for j in 9:
				var th := PI * i / 4.0
				var ph := TAU * (j % 8) / 8.0
				var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				row.append([c + d * Vector3(0.013, 0.015, 0.016), skin, Vector2.ZERO])
				prow.append([c + Vector3(0.0105 * side, 0.003, 0.0) + d * Vector3(0.0035, 0.0038, 0.0095), Color(0, 0, 0, 0), Vector2.ZERO])
			er.append(row)
			pr.append(prow)
			ein.append(c)
		SM._grid(st, er, ein, true)
		SM._grid(st, pr, [c, c, c, c, c], true)
	# the siphon, on the right
	_tube(st, [Vector3(0.03, 0.04, 0.035), Vector3(0.052, 0.038, 0.012), Vector3(0.062, 0.04, -0.004)], [0.012, 0.01, 0.007], [skin, skin, skin], [0.0, 0.0, 0.0], 6)
	# the arms
	var sides := 6
	var n := 22
	for arm in 8:
		var rows: Array = []
		for i in n + 1:
			var s := float(i) / n
			var r := lerpf(0.025, 0.003, pow(s, 0.7)) if i < n else 0.0005
			var row: Array = []
			for k in sides + 1:
				var a := TAU * (k % sides) / float(sides)
				st.set_color(Color(1, smoothstep(-0.5, 0.3, sin(a)), 0, 1))
				row.append([Vector3(cos(a) * r, sin(a) * r * 0.85, s * ARM_LEN), Vector3(cos(a), sin(a), 0.0), Color(1, smoothstep(-0.5, 0.3, sin(a)), 0, 1), Vector2((arm + 0.5) / 8.0, s)])
			rows.append(row)
		# (straight to the surface tool: these normals are in the arm's own frame, and the
		# winding is known. Front faces are clockwise)
		for i in n:
			for k in sides:
				for q: Array in [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i][k], rows[i + 1][k + 1], rows[i + 1][k]]:
					st.set_color(q[2])
					st.set_normal(q[1])
					st.set_uv(q[3])
					st.add_vertex(q[0])
	return st.commit()


# ------------------------------------------------------------------ lionfish
## The lionfish of the Indian Ocean (Pterois miles), in sea_models' conventions (3.6 long,
## forward -Z): a deep body in narrow red-brown and white bars, the pectoral fins as two great
## fans of long separate rays, a row of tall spines on the back, each with its pennant.
## shaders/reef_fish.gdshader (species 2): COLOR.a = 1 on the trunk (it paints the bars from
## the place along the body); elsewhere COLOR.rgb is the color itself, and COLOR.a = 0.25
## marks rays and spines, which wave: UV.y = how far out along the ray, UV.x = its phase.
const LION_DARK := Color(0.4, 0.1, 0.05)
const LION_PALE := Color(0.86, 0.78, 0.66)

## A fan of rays from `roots` to `tips` (as many of the one as of the other): every ray a
## narrow banded strip, and a skin between neighbors as far out as `web` (0..1).
static func _rays(st: SurfaceTool, roots: Array, tips: Array, width: float, web: float, bands: int, phase0: float) -> void:
	var segs := 6
	var n := roots.size()
	for i in n:
		var r: Vector3 = roots[i]
		var t: Vector3 = tips[i]
		var j := mini(i + 1, n - 1) if i + 1 < n else i - 1
		var across: Vector3 = (roots[j] as Vector3).lerp(tips[j], 0.5) - r.lerp(t, 0.5)
		var nrm := (t - r).cross(across).normalized()
		var side := nrm.cross(t - r).normalized()
		var ph := phase0 + 0.11 * i
		for k in segs:
			var f0 := float(k) / segs
			var f1 := float(k + 1) / segs
			var c0 := LION_DARK if int(f0 * bands * 2.0) % 2 == 0 else LION_PALE
			c0.a = 0.25
			var w0 := width * lerpf(1.0, 0.25, f0)
			var w1 := width * lerpf(1.0, 0.25, f1)
			var a := [r.lerp(t, f0) - side * w0, nrm, c0, Vector2(ph, f0)]
			var b := [r.lerp(t, f0) + side * w0, nrm, c0, Vector2(ph, f0)]
			var c := [r.lerp(t, f1) + side * w1, nrm, c0, Vector2(ph, f1)]
			var d := [r.lerp(t, f1) - side * w1, nrm, c0, Vector2(ph, f1)]
			SM._emit(st, a, b, c)
			SM._emit(st, a, c, d)
			if i + 1 < n and f0 < web:
				# the skin between this ray and the next: paler, spotted where it is broad
				var r2: Vector3 = roots[i + 1]
				var t2: Vector3 = tips[i + 1]
				var g1 := minf(f1, web)
				var m := LION_PALE.lerp(LION_DARK, 0.35 if (k + i) % 2 == 0 else 0.7)
				m.a = 0.25
				var ph2 := phase0 + 0.11 * (i + 1)
				var e := [r.lerp(t, f0), nrm, m, Vector2(ph, f0)]
				var f := [r2.lerp(t2, f0), nrm, m, Vector2(ph2, f0)]
				var gq := [r2.lerp(t2, g1), nrm, m, Vector2(ph2, g1)]
				var hq := [r.lerp(t, g1), nrm, m, Vector2(ph, g1)]
				SM._emit(st, e, f, gq)
				SM._emit(st, e, gq, hq)


static func lionfish() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations := [
		[0.0, 0.004, 0.004, -0.004, -0.1], [0.02, 0.1, 0.1, -0.12, -0.1], [0.07, 0.2, 0.25, -0.27, -0.08], [0.15, 0.29, 0.43, -0.43, -0.04],
		[0.26, 0.33, 0.56, -0.56, 0.0], [0.38, 0.32, 0.59, -0.57, 0.0], [0.5, 0.27, 0.53, -0.51, 0.0], [0.6, 0.2, 0.41, -0.39, 0.0],
		[0.68, 0.13, 0.27, -0.26, 0.0], [0.74, 0.08, 0.18, -0.17, 0.0], [0.78, 0.05, 0.15, -0.14, 0.0], [0.8, 0.01, 0.13, -0.12, 0.0]]
	SM._trunk(st, stations, 14, 3, 1.0)
	# the spines of the back: tall, leaning back a little, each with a pennant of skin
	var roots: Array = []
	var tips: Array = []
	for i in 12:
		var u := lerpf(0.2, 0.57, i / 11.0)
		var top := 0.5 + 0.1 * sin((u - 0.15) * 7.0)
		var h := 0.95 * sin(lerpf(0.5, 2.6, i / 11.0)) + 0.25
		roots.append(Vector3(0, top - 0.06, _z(u)))
		tips.append(Vector3(0, top + h, _z(u + 0.05 + 0.004 * i)))
	_rays(st, roots, tips, 0.022, 0.3, 4, 0.0)
	# the soft fin behind them, the anal fin, the tail: rounded, their skin spotted
	for fin: Array in [[0.59, 0.4, 0.69, 0.24, 0.6, 1.0], [0.59, -0.38, 0.69, -0.23, 0.55, -1.0]]:
		roots = []
		tips = []
		for i in 8:
			var f := i / 7.0
			roots.append(Vector3(0, lerpf(fin[1], fin[3], f), _z(lerpf(fin[0], fin[2], f))))
			var ang := lerpf(0.5, 1.25, f)
			tips.append((roots[i] as Vector3) + Vector3(0, cos(ang) * float(fin[5]), sin(ang)) * (float(fin[4]) * (0.75 + 0.25 * sin(f * PI))) * 1.0)
		_rays(st, roots, tips, 0.01, 1.0, 5, 1.0)
	roots = []
	tips = []
	for i in 11:
		var f := i / 10.0
		var ang := lerpf(-0.6, 0.6, f)
		roots.append(Vector3(0, lerpf(-0.12, 0.13, f), _z(0.79)))
		tips.append(Vector3(0, sin(ang) * 0.75, _z(0.79) + cos(ang) * 0.78 * (0.85 + 0.15 * cos(ang * 2.6))))
	_rays(st, roots, tips, 0.01, 1.0, 5, 2.0)
	for side in [1.0, -1.0]:
		# the pectoral fan: long rays spreading outward and back, from pointing up to pointing down
		var out := Vector3(0.8 * side, 0.0, 0.6).normalized()
		var lean := (Vector3.UP * 0.8 + Vector3.FORWARD * 0.6).normalized()     # (so that the fan shows from above too)
		roots = []
		tips = []
		for i in 13:
			var f := i / 12.0
			var ang := lerpf(1.15, -1.25, f)
			var d := (out * cos(ang) + lean * sin(ang)).normalized()
			roots.append(Vector3(0.3 * side, -0.12 + 0.1 * (0.5 - f), _z(0.27 + 0.012 * f)))
			tips.append((roots[i] as Vector3) + d * (1.25 + 0.4 * sin(f * PI)))
		_rays(st, roots, tips, 0.018, 0.6, 5, 3.0 + side)
		# pelvic fins: dark, hanging
		roots = []
		tips = []
		for i in 5:
			var f := i / 4.0
			roots.append(Vector3(0.12 * side, -0.52, _z(0.31 + 0.03 * f)))
			tips.append((roots[i] as Vector3) + Vector3(0.16 * side * (1.0 - f), -0.62, 0.25 + 0.45 * f))
		_rays(st, roots, tips, 0.012, 0.9, 3, 5.0)
		# the eye, and the little banner over it
		var e := Vector3(0.22 * side, 0.2, _z(0.1))
		var er: Array = []
		for i in 5:
			var row: Array = []
			for j in 9:
				var th := PI * i / 4.0
				var ph := TAU * (j % 8) / 8.0
				row.append([e + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * Vector3(0.03, 0.075, 0.075), Color(0.01, 0.01, 0.01, 0.75), Vector2(0.0, 0.0)])
			er.append(row)
		SM._grid(st, er, [e, e, e, e, e], true)
		_rays(st, [Vector3(0.17 * side, 0.36, _z(0.1))], [Vector3(0.22 * side, 0.72, _z(0.09))], 0.02, 0.0, 3, 6.0)
	return st.commit()
