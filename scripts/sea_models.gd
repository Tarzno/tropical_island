extends RefCounted
## The big animals of the sea, modeled in code (no Blender needed): tiger shark, blacktip reef
## shark, eagle ray, manta ray, sea turtles. Preloaded by sealife.gd and turtles.gd (no class_name).
##
## Conventions (shaders/sea_creature.gdshader reads them):
##  * forward = -Z, up = +Y; a shark is 3.6 long (snout at z -1.8, tail tip at +1.8) and is
##    scaled to its real size by the script that places it;
##  * UV.x = how far along the body a vertex lies (0 snout .. 1 tail tip): the swimming wave;
##    UV.y = the way around the body (0 belly, 0.5 back) on the trunk, -1 on fins and eyes;
##  * COLOR.r = black fin tip (blacktip reef shark), COLOR.g = 1 on the dark back .. 0 on the
##    pale belly, COLOR.b = the pale band below a black tip, COLOR.a = 0 on the eyes.

const L := 3.6


static func _z(u: float) -> float:
	return (u - 0.5) * L


## One triangle of [position, normal, color, uv]. The material is double-sided and Godot turns
## the normal around on faces seen from behind (front faces are clockwise), so the corners are
## put in the order the normals ask for.
static func _emit(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var front := ((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3))
	var tri := [a, b, c] if front.dot((a[1] as Vector3) + (b[1] as Vector3) + (c[1] as Vector3)) >= 0.0 else [a, c, b]
	for q: Array in tri:
		st.set_color(q[2])
		st.set_normal(q[1])
		st.set_uv(q[3])
		st.add_vertex(q[0])


## Triangles for a grid of [position, color, uv] with smooth normals that point away from the
## row's point in `inside` (one per row). `ring`: the last column repeats the first (a closed
## tube with a seam for the UVs).
static func _grid(st: SurfaceTool, g: Array, inside: Array, ring: bool) -> void:
	var rows := g.size()
	var cols: int = (g[0] as Array).size()
	var v: Array = []
	for i in rows:
		var row: Array = []
		for j in cols:
			var jl := maxi(j - 1, 0)
			var jr := mini(j + 1, cols - 1)
			if ring:
				jl = cols - 2 if j == 0 else j - 1
				jr = 1 if j == cols - 1 else j + 1
			var p: Vector3 = g[i][j][0]
			var du: Vector3 = (g[i][jr][0] as Vector3) - (g[i][jl][0] as Vector3)
			var dv: Vector3 = (g[mini(i + 1, rows - 1)][j][0] as Vector3) - (g[maxi(i - 1, 0)][j][0] as Vector3)
			var n := du.cross(dv)
			var out: Vector3 = p - (inside[i] as Vector3)
			n = n.normalized() if n.length() > 1e-10 else out.normalized()
			if n.dot(out) < 0.0:
				n = -n
			row.append([p, n, g[i][j][1], g[i][j][2]])
		v.append(row)
	for i in rows - 1:
		for j in cols - 1:
			if (v[i][j][0] as Vector3).distance_squared_to(v[i][j + 1][0]) > 1e-12:
				_emit(st, v[i][j], v[i + 1][j + 1], v[i][j + 1])
			if (v[i + 1][j][0] as Vector3).distance_squared_to(v[i + 1][j + 1][0]) > 1e-12:
				_emit(st, v[i][j], v[i + 1][j], v[i + 1][j + 1])


## A smooth curve through `pts` (Catmull-Rom), t from 0 to 1 over the whole of it. The points
## are arrays of numbers or Vector3s.
static func _curve(pts: Array, t: float) -> Variant:
	var n := pts.size() - 1
	var f := clampf(t, 0.0, 1.0) * n
	var i := mini(int(f), n - 1)
	var u := f - i
	var p0: Variant = pts[maxi(i - 1, 0)]
	var p1: Variant = pts[i]
	var p2: Variant = pts[i + 1]
	var p3: Variant = pts[mini(i + 2, n)]
	return ((p1 * 2.0) + (p2 - p0) * u + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * (u * u) + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * (u * u * u)) * 0.5


## The trunk: cross-sections along the body. Each station is [u, half-width, top, bottom
## (negative), height of the midline]; between them the outline is smoothed. `flat`: how much
## flatter than an ellipse the underside is (1 = an ellipse).
static func _trunk(st: SurfaceTool, stations: Array, segs: int, sub: int, flat: float) -> void:
	var rows: Array = []
	var inside: Array = []
	var sts: Array = []
	for s: Array in stations:
		sts.append(Vector3(s[1], s[2], s[3]))
	var n := (stations.size() - 1) * sub
	for i in n + 1:
		var t := float(i) / n
		var k := mini(int(t * (stations.size() - 1)), stations.size() - 2)
		var f := t * (stations.size() - 1) - k
		var u := lerpf(stations[k][0], stations[k + 1][0], f)
		var yc := lerpf(stations[k][4], stations[k + 1][4], f * f * (3.0 - 2.0 * f))
		var d: Vector3 = _curve(sts, t)
		var w := maxf(d.x, 0.002)
		var top := maxf(d.y, 0.002)
		var bot := minf(d.z, -0.002)
		var row: Array = []
		for j in segs + 1:
			var a := TAU * (j % segs) / float(segs)      # 0 at the belly, round by the right flank
			var sx := sin(a)
			var cy := -cos(a)
			var p := Vector3(w * sx, yc + (top * cy if cy > 0.0 else -bot * signf(cy) * pow(absf(cy), flat)), _z(u))
			# dark above, pale below, the border a little under the widest line
			row.append([p, Color(0.0, smoothstep(-0.42, 0.12, cy), 0.0, 1.0), Vector2(u, float(j) / segs)])
		rows.append(row)
		inside.append(Vector3(0.0, yc, _z(u)))
	_grid(st, rows, inside, true)


## A fin: a thin blade between its leading edge `le` and its trailing edge `te` (both from the
## root to the tip, any number of points; they meet at the tip), thickest at the root and a
## third of the way back. `tip`: where along it the black tip begins (above 1: none), `band`:
## where the pale band below that begins. `under`: the shade of the side that faces down (the
## paired fins are pale below).
static func _fin(st: SurfaceTool, le: Array, te: Array, thick: float, tip := 2.0, band := 2.0, under := 1.0) -> void:
	var n := 9
	var chord := [0.0, 0.12, 0.35, 0.68, 1.0]
	var fat := [0.0, 0.8, 1.0, 0.55, 0.0]
	var lead: Array = []
	var trail: Array = []
	for i in n:
		lead.append(_curve(le, float(i) / (n - 1)))
		trail.append(_curve(te, float(i) / (n - 1)))
	var nrm_prev := Vector3.ZERO
	var sides: Array = [[], []]
	var inside: Array = [[], []]
	for i in n:
		var s := float(i) / (n - 1)
		var a: Vector3 = lead[i]
		var b: Vector3 = trail[i]
		var mid0: Vector3 = ((lead[maxi(i - 1, 0)] as Vector3) + (trail[maxi(i - 1, 0)] as Vector3)) * 0.5
		var mid1: Vector3 = ((lead[mini(i + 1, n - 1)] as Vector3) + (trail[mini(i + 1, n - 1)] as Vector3)) * 0.5
		var nrm := (b - a).cross(mid1 - mid0)
		nrm = nrm.normalized() if nrm.length() > 1e-9 else nrm_prev
		if nrm_prev != Vector3.ZERO and nrm.dot(nrm_prev) < 0.0:
			nrm = -nrm
		nrm_prev = nrm
		var th := thick * pow(1.0 - s, 0.7) + 0.003 * (1.0 - s)
		var black := smoothstep(tip, tip + 0.1, s)
		var pale := smoothstep(band, band + 0.08, s) * (1.0 - black)
		for side in 2:
			var sgn := 1.0 if side == 0 else -1.0
			var row: Array = []
			for c in chord.size():
				var p := a.lerp(b, chord[c]) + nrm * (sgn * th * float(fat[c]))
				# (the side that faces down may be paler)
				var shade := under if (nrm * sgn).y < -0.3 else 1.0
				row.append([p, Color(black, shade, pale, 1.0), Vector2(clampf(p.z / L + 0.5, 0.0, 1.0), -1.0)])
			(sides[side] as Array).append(row)
			(inside[side] as Array).append((a + b) * 0.5 - nrm * sgn * 0.5)
	_grid(st, sides[0], inside[0], false)
	_grid(st, sides[1], inside[1], false)


static func _ball(st: SurfaceTool, c: Vector3, r: Vector3, col: Color) -> void:
	var rows: Array = []
	var inside: Array = []
	for i in 6:
		var row: Array = []
		for j in 9:
			var th := PI * i / 5.0
			var ph := TAU * (j % 8) / 8.0
			row.append([c + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * r, col, Vector2(clampf(c.z / L + 0.5, 0.0, 1.0), -1.0)])
		rows.append(row)
		inside.append(c)
	_grid(st, rows, inside, true)


## Fin outlines are written as (u along the body, height) for the fins on the midline.
static func _mid(pts: Array) -> Array:
	var out: Array = []
	for p: Array in pts:
		out.append(Vector3(0.0, p[1], _z(p[0])))
	return out


## ... and as (sideways, height, u) for the paired ones, `side` +1 or -1.
static func _pair(pts: Array, side: float) -> Array:
	var out: Array = []
	for p: Array in pts:
		out.append(Vector3(float(p[0]) * side, p[1], _z(p[2])))
	return out


## The tiger shark: heavy in front, the head broad and blunt as if cut off, a slender tail
## stock with a keel, and a long upper tail lobe.
static func tiger_shark() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.004, 0.004, -0.004, -0.045], [0.006, 0.105, 0.035, -0.04, -0.045], [0.02, 0.18, 0.07, -0.075, -0.042],
		[0.05, 0.245, 0.115, -0.11, -0.035], [0.10, 0.29, 0.175, -0.15, -0.022], [0.16, 0.315, 0.23, -0.19, -0.01],
		[0.23, 0.325, 0.27, -0.22, 0.0], [0.31, 0.315, 0.285, -0.235, 0.0], [0.40, 0.28, 0.27, -0.225, 0.0],
		[0.50, 0.225, 0.235, -0.19, 0.004], [0.60, 0.165, 0.185, -0.145, 0.01], [0.68, 0.115, 0.14, -0.105, 0.015],
		[0.74, 0.08, 0.10, -0.07, 0.02], [0.78, 0.066, 0.072, -0.05, 0.02], [0.815, 0.036, 0.058, -0.04, 0.02],
		[0.845, 0.01, 0.04, -0.02, 0.02]], 18, 3, 0.8)
	# first and second dorsal fin, anal fin
	_fin(st, _mid([[0.300, 0.25], [0.335, 0.47], [0.375, 0.65], [0.405, 0.755], [0.418, 0.78]]),
		_mid([[0.465, 0.255], [0.432, 0.31], [0.418, 0.45], [0.420, 0.62], [0.421, 0.775]]), 0.035)
	_fin(st, _mid([[0.655, 0.13], [0.675, 0.22], [0.70, 0.27]]), _mid([[0.735, 0.125], [0.712, 0.16], [0.703, 0.265]]), 0.014)
	_fin(st, _mid([[0.665, -0.09], [0.685, -0.17], [0.705, -0.215]]), _mid([[0.74, -0.075], [0.72, -0.11], [0.708, -0.21]]), 0.014)
	# tail: the long upper lobe, the short lower one
	_fin(st, _mid([[0.795, 0.06], [0.86, 0.22], [0.93, 0.42], [0.985, 0.575], [1.0, 0.62]]),
		_mid([[0.865, 0.0], [0.895, 0.14], [0.94, 0.33], [0.975, 0.50], [0.998, 0.615]]), 0.032)
	_fin(st, _mid([[0.80, -0.045], [0.845, -0.15], [0.885, -0.25], [0.905, -0.30]]),
		_mid([[0.865, 0.0], [0.885, -0.09], [0.90, -0.20], [0.908, -0.295]]), 0.03)
	for side in [1.0, -1.0]:
		# pectoral and pelvic fins
		_fin(st, _pair([[0.27, -0.10, 0.215], [0.47, -0.19, 0.265], [0.66, -0.27, 0.325], [0.78, -0.32, 0.375]], side),
			_pair([[0.24, -0.13, 0.325], [0.42, -0.2, 0.345], [0.60, -0.265, 0.365], [0.775, -0.32, 0.385]], side), 0.028, 2.0, 2.0, 0.25)
		_fin(st, _pair([[0.10, -0.14, 0.555], [0.19, -0.21, 0.585], [0.23, -0.245, 0.61]], side),
			_pair([[0.08, -0.13, 0.625], [0.15, -0.18, 0.628], [0.225, -0.243, 0.62]], side), 0.014, 2.0, 2.0, 0.25)
		_ball(st, Vector3(0.232 * side, -0.012, _z(0.052)), Vector3(0.016, 0.022, 0.026), Color(0, 0, 0, 0))
	return st.commit()


## The blacktip reef shark: slim, a short rounded snout, a tall first dorsal fin with a black
## tip and a pale band below it, black on the tips of the other fins and on the lower tail lobe.
static func blacktip_shark() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.004, 0.004, -0.004, -0.035], [0.008, 0.07, 0.03, -0.035, -0.035], [0.03, 0.14, 0.065, -0.07, -0.032],
		[0.07, 0.195, 0.11, -0.105, -0.025], [0.13, 0.225, 0.16, -0.14, -0.014], [0.20, 0.24, 0.20, -0.17, -0.005],
		[0.28, 0.245, 0.225, -0.19, 0.0], [0.36, 0.235, 0.23, -0.19, 0.0], [0.46, 0.20, 0.205, -0.165, 0.004],
		[0.56, 0.155, 0.165, -0.13, 0.01], [0.65, 0.11, 0.125, -0.095, 0.014], [0.72, 0.075, 0.09, -0.065, 0.018],
		[0.77, 0.055, 0.068, -0.048, 0.02], [0.805, 0.032, 0.055, -0.038, 0.02], [0.835, 0.01, 0.04, -0.02, 0.02]], 18, 3, 0.85)
	_fin(st, _mid([[0.325, 0.2], [0.355, 0.42], [0.39, 0.60], [0.415, 0.715], [0.428, 0.75]]),
		_mid([[0.47, 0.21], [0.445, 0.27], [0.432, 0.42], [0.434, 0.60], [0.432, 0.745]]), 0.03, 0.66, 0.44)
	_fin(st, _mid([[0.64, 0.11], [0.66, 0.21], [0.685, 0.27]]), _mid([[0.72, 0.105], [0.70, 0.15], [0.69, 0.265]]), 0.013, 0.6)
	_fin(st, _mid([[0.645, -0.08], [0.665, -0.17], [0.685, -0.22]]), _mid([[0.72, -0.07], [0.70, -0.11], [0.69, -0.215]]), 0.013, 0.6)
	_fin(st, _mid([[0.79, 0.055], [0.855, 0.22], [0.925, 0.42], [0.98, 0.56], [1.0, 0.60]]),
		_mid([[0.86, 0.0], [0.89, 0.14], [0.935, 0.33], [0.972, 0.49], [0.997, 0.595]]), 0.028, 0.84)
	_fin(st, _mid([[0.795, -0.04], [0.84, -0.16], [0.875, -0.27], [0.893, -0.33]]),
		_mid([[0.86, 0.0], [0.878, -0.1], [0.89, -0.22], [0.896, -0.325]]), 0.026, 0.45)
	for side in [1.0, -1.0]:
		_fin(st, _pair([[0.2, -0.09, 0.21], [0.4, -0.19, 0.255], [0.58, -0.29, 0.315], [0.68, -0.36, 0.37]], side),
			_pair([[0.18, -0.12, 0.30], [0.34, -0.195, 0.32], [0.5, -0.275, 0.345], [0.675, -0.36, 0.378]], side), 0.022, 0.76, 2.0, 0.3)
		_fin(st, _pair([[0.08, -0.12, 0.53], [0.15, -0.19, 0.56], [0.19, -0.23, 0.585]], side),
			_pair([[0.065, -0.11, 0.595], [0.12, -0.16, 0.60], [0.185, -0.228, 0.595]], side), 0.012, 0.7, 2.0, 0.3)
		_ball(st, Vector3(0.178 * side, -0.01, _z(0.062)), Vector3(0.016, 0.022, 0.024), Color(0, 0, 0, 0))
	return st.commit()


## A spinner dolphin: slender, a long thin beak, a tall upright back fin, flukes that lie
## level. 3.6 long like the sharks; the script shows it 2.2 m long and far away.
static func dolphin() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.008, 0.008, -0.008, -0.04], [0.03, 0.03, 0.028, -0.03, -0.04], [0.085, 0.045, 0.04, -0.045, -0.035],
		[0.11, 0.1, 0.14, -0.09, -0.02], [0.17, 0.17, 0.21, -0.16, 0.0], [0.27, 0.22, 0.25, -0.22, 0.0],
		[0.38, 0.235, 0.26, -0.24, 0.0], [0.5, 0.21, 0.24, -0.22, 0.0], [0.62, 0.16, 0.19, -0.17, 0.0],
		[0.74, 0.1, 0.13, -0.12, 0.0], [0.85, 0.05, 0.085, -0.08, 0.0], [0.93, 0.03, 0.05, -0.05, 0.0],
		[0.965, 0.012, 0.03, -0.03, 0.0]], 14, 3, 1.0)
	_fin(st, _mid([[0.4, 0.24], [0.45, 0.42], [0.5, 0.55], [0.53, 0.6]]), _mid([[0.56, 0.22], [0.545, 0.33], [0.54, 0.47], [0.535, 0.6]]), 0.02)
	for side in [1.0, -1.0]:
		_fin(st, _pair([[0.02, 0.0, 0.93], [0.22, 0.0, 0.955], [0.4, 0.0, 0.995]], side), _pair([[0.02, 0.0, 0.985], [0.2, 0.0, 0.985], [0.4, 0.0, 1.0]], side), 0.02)
		_fin(st, _pair([[0.2, -0.12, 0.25], [0.32, -0.24, 0.3], [0.4, -0.34, 0.36]], side), _pair([[0.2, -0.14, 0.33], [0.3, -0.24, 0.345], [0.4, -0.34, 0.365]], side), 0.016)
		_ball(st, Vector3(0.15 * side, 0.05, _z(0.15)), Vector3(0.018, 0.022, 0.024), Color(0, 0, 0, 0))
	return st.commit()


## The great barracuda (Sphyraena barracuda): a long pike of a fish, almost round in section,
## the head a quarter of it and pointed, the lower jaw standing out beyond the upper; two
## small back fins far apart (the first over the belly fins, the second far back over the
## anal fin), small breast fins low behind the head, a broad forked tail. 3.6 long like the
## sharks; the script shows it a meter and more.
static func barracuda() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.004, 0.004, -0.004, -0.03], [0.012, 0.022, 0.02, -0.03, -0.03], [0.05, 0.055, 0.055, -0.07, -0.024],
		[0.10, 0.09, 0.095, -0.10, -0.016], [0.16, 0.12, 0.135, -0.13, -0.008], [0.23, 0.145, 0.17, -0.16, 0.0],
		[0.31, 0.16, 0.195, -0.185, 0.0], [0.42, 0.168, 0.21, -0.20, 0.0], [0.54, 0.16, 0.20, -0.19, 0.0],
		[0.65, 0.135, 0.17, -0.16, 0.0], [0.75, 0.10, 0.13, -0.12, 0.0], [0.83, 0.066, 0.09, -0.085, 0.0],
		[0.885, 0.045, 0.072, -0.068, 0.0], [0.915, 0.012, 0.05, -0.05, 0.0]], 16, 3, 0.95)
	# the two back fins and the anal fin
	_fin(st, _mid([[0.40, 0.2], [0.425, 0.31], [0.447, 0.365]]), _mid([[0.478, 0.2], [0.462, 0.26], [0.45, 0.36]]), 0.012)
	_fin(st, _mid([[0.655, 0.165], [0.675, 0.27], [0.697, 0.315]]), _mid([[0.74, 0.13], [0.713, 0.18], [0.70, 0.31]]), 0.012)
	_fin(st, _mid([[0.665, -0.155], [0.685, -0.25], [0.707, -0.295]]), _mid([[0.745, -0.12], [0.72, -0.17], [0.71, -0.29]]), 0.012)
	# the forked tail
	_fin(st, _mid([[0.885, 0.06], [0.93, 0.2], [0.975, 0.33], [1.0, 0.385]]), _mid([[0.928, 0.0], [0.948, 0.1], [0.976, 0.24], [0.998, 0.38]]), 0.022)
	_fin(st, _mid([[0.885, -0.06], [0.93, -0.2], [0.975, -0.33], [1.0, -0.385]]), _mid([[0.928, 0.0], [0.948, -0.1], [0.976, -0.24], [0.998, -0.38]]), 0.022)
	for side in [1.0, -1.0]:
		# breast fins and belly fins
		_fin(st, _pair([[0.13, -0.07, 0.255], [0.22, -0.11, 0.29], [0.29, -0.145, 0.33]], side),
			_pair([[0.12, -0.10, 0.30], [0.2, -0.125, 0.32], [0.285, -0.147, 0.335]], side), 0.01, 2.0, 2.0, 0.5)
		_fin(st, _pair([[0.05, -0.18, 0.40], [0.09, -0.25, 0.425], [0.115, -0.295, 0.452]], side),
			_pair([[0.04, -0.19, 0.447], [0.08, -0.245, 0.452], [0.112, -0.293, 0.457]], side), 0.01, 2.0, 2.0, 0.5)
		_ball(st, Vector3(0.092 * side, 0.035, _z(0.125)), Vector3(0.018, 0.03, 0.032), Color(0, 0, 0, 0))
	return st.commit()


## A triggerfish (the titan and the clown triggerfish share the shape; the shader paints
## them): a deep body flat from side to side, the eyes set high and far back, a long sloping
## snout with a small strong mouth at its tip; the short "trigger" spine on the back, and
## behind it the two fins it swims with, one on the back and one below, opposite each other:
## waves run along them while the body stays stiff (the shader does that; it finds the fins
## by where they are: keep the two in step). A rounded tail, small breast fins. 3.6 long.
static func triggerfish() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.01, 0.02, -0.03, -0.16], [0.01, 0.05, 0.07, -0.08, -0.16], [0.05, 0.10, 0.17, -0.17, -0.13],
		[0.12, 0.16, 0.34, -0.34, -0.08], [0.20, 0.21, 0.55, -0.52, -0.03], [0.30, 0.25, 0.75, -0.70, 0.0],
		[0.40, 0.27, 0.86, -0.84, 0.0], [0.50, 0.26, 0.84, -0.84, 0.0], [0.60, 0.22, 0.70, -0.70, 0.0],
		[0.70, 0.16, 0.48, -0.48, 0.0], [0.78, 0.10, 0.28, -0.28, 0.0], [0.84, 0.07, 0.20, -0.20, 0.0],
		[0.875, 0.025, 0.18, -0.18, 0.0]], 18, 3, 1.0)
	# the trigger: a short stiff spine with its skin, half raised
	_fin(st, _mid([[0.30, 0.74], [0.335, 0.98], [0.35, 1.06]]), _mid([[0.44, 0.86], [0.39, 0.92], [0.355, 1.05]]), 0.02)
	# the two fins it swims with: tallest in front, running down to the tail stock
	_fin(st, _mid([[0.50, 0.82], [0.535, 1.22], [0.60, 1.26], [0.70, 1.02], [0.79, 0.56], [0.835, 0.24]]),
		_mid([[0.52, 0.82], [0.60, 0.70], [0.68, 0.52], [0.75, 0.36], [0.81, 0.24], [0.835, 0.22]]), 0.014)
	_fin(st, _mid([[0.52, -0.82], [0.555, -1.20], [0.62, -1.22], [0.71, -0.98], [0.79, -0.54], [0.835, -0.24]]),
		_mid([[0.54, -0.82], [0.61, -0.69], [0.68, -0.52], [0.75, -0.36], [0.81, -0.24], [0.835, -0.22]]), 0.014)
	# the tail: a fan, a little hollow at its end
	_fin(st, _mid([[0.85, 0.19], [0.91, 0.42], [0.975, 0.50], [0.99, 0.2], [0.975, 0.0]]),
		_mid([[0.85, -0.19], [0.91, -0.42], [0.975, -0.50], [0.99, -0.2], [0.975, 0.0]]), 0.03)
	for side in [1.0, -1.0]:
		_fin(st, _pair([[0.25, -0.02, 0.385], [0.36, 0.04, 0.42], [0.46, 0.02, 0.455], [0.5, -0.08, 0.47]], side),
			_pair([[0.25, -0.2, 0.39], [0.33, -0.27, 0.425], [0.43, -0.25, 0.455], [0.5, -0.1, 0.472]], side), 0.012)
		_ball(st, Vector3(0.212 * side, 0.42, _z(0.285)), Vector3(0.03, 0.05, 0.052), Color(0, 0, 0, 0))
	return st.commit()


## The Moorish idol (Zanclus cornutus): a disc of a body, very flat from side to side and
## nearly as tall as it is long; a long tube of a snout with a small mouth at its tip, set
## low; the eyes high up; a tall three-cornered back fin whose front rays run out into a
## long white streamer that trails back beyond the tail (the shader lets it sway: it finds
## it by its height, above 1.8), a three-cornered fin below, a small tail like a fan. 3.6
## long like the sharks; the script shows it 0.27 to 0.32 m long (a little over life size, like the other reef fish).
static func moorish_idol() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.02, 0.035, -0.035, -0.30], [0.025, 0.045, 0.07, -0.07, -0.29], [0.08, 0.06, 0.10, -0.10, -0.25],
		[0.14, 0.085, 0.19, -0.17, -0.19], [0.19, 0.12, 0.42, -0.36, -0.11], [0.25, 0.16, 0.78, -0.66, -0.04],
		[0.33, 0.19, 1.04, -0.96, 0.0], [0.42, 0.20, 1.16, -1.12, 0.0], [0.50, 0.19, 1.14, -1.12, 0.0],
		[0.58, 0.16, 0.98, -0.98, 0.0], [0.66, 0.12, 0.70, -0.70, 0.0], [0.73, 0.08, 0.40, -0.40, 0.0],
		[0.79, 0.05, 0.22, -0.22, 0.0], [0.83, 0.04, 0.19, -0.19, 0.0], [0.855, 0.015, 0.18, -0.18, 0.0]], 18, 3, 1.0)
	# the back fin: a tall sail, its front edge running up into the streamer
	_fin(st, _mid([[0.33, 1.0], [0.39, 1.5], [0.455, 1.95], [0.50, 2.12]]), _mid([[0.74, 0.36], [0.70, 0.82], [0.62, 1.42], [0.515, 2.1]]), 0.014)
	# the streamer: a ribbon that arches back over the tail and beyond it
	_fin(st, _mid([[0.455, 1.9], [0.53, 2.4], [0.66, 2.74], [0.84, 2.86], [1.04, 2.72], [1.22, 2.44], [1.36, 2.14]]),
		_mid([[0.515, 1.9], [0.575, 2.3], [0.68, 2.6], [0.84, 2.74], [1.03, 2.63], [1.21, 2.38], [1.36, 2.12]]), 0.008)
	# the fin below, and the two small belly fins as one blade
	_fin(st, _mid([[0.44, -1.08], [0.50, -1.5], [0.555, -1.72], [0.575, -1.76]]), _mid([[0.74, -0.36], [0.70, -0.8], [0.635, -1.36], [0.585, -1.74]]), 0.014)
	_fin(st, _mid([[0.31, -0.9], [0.345, -1.22], [0.385, -1.4]]), _mid([[0.40, -1.05], [0.40, -1.24], [0.39, -1.39]]), 0.012)
	# the tail: a small fan, a little hollow at its end
	_fin(st, _mid([[0.835, 0.18], [0.89, 0.40], [0.975, 0.52], [0.968, 0.2], [0.955, 0.0]]),
		_mid([[0.835, -0.18], [0.89, -0.40], [0.975, -0.52], [0.968, -0.2], [0.955, 0.0]]), 0.02)
	for side in [1.0, -1.0]:
		# the breast fins it sculls with
		_fin(st, _pair([[0.18, -0.2, 0.37], [0.3, -0.12, 0.41], [0.4, -0.16, 0.445], [0.43, -0.26, 0.46]], side),
			_pair([[0.18, -0.36, 0.375], [0.27, -0.42, 0.41], [0.37, -0.4, 0.445], [0.43, -0.28, 0.462]], side), 0.01)
		_ball(st, Vector3(0.152 * side, 0.36, _z(0.262)), Vector3(0.026, 0.07, 0.072), Color(0, 0, 0, 0))
	return st.commit()


## The giant grouper (Epinephelus lanceolatus), the biggest fish of the reef: a deep, heavy
## body, the head a third of it with a wide mouth and thick lips, the lower jaw standing out,
## small eyes; one long back fin (low and spiny in front, a rounded lobe behind), a rounded
## tail, big round breast fins it sculls with. Built 3.6 long like the sharks.
static func giant_grouper() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, [
		[0.0, 0.01, 0.01, -0.02, -0.08], [0.006, 0.13, 0.07, -0.10, -0.08], [0.03, 0.24, 0.17, -0.20, -0.07],
		[0.08, 0.31, 0.30, -0.33, -0.05], [0.15, 0.36, 0.44, -0.44, -0.02], [0.24, 0.39, 0.55, -0.52, 0.0],
		[0.34, 0.385, 0.61, -0.55, 0.0], [0.44, 0.35, 0.60, -0.54, 0.0], [0.54, 0.29, 0.54, -0.48, 0.0],
		[0.64, 0.22, 0.43, -0.38, 0.0], [0.73, 0.155, 0.32, -0.28, 0.0], [0.80, 0.11, 0.245, -0.215, 0.0],
		[0.845, 0.085, 0.225, -0.20, 0.0], [0.875, 0.03, 0.2, -0.18, 0.0]], 20, 3, 0.9)
	# the back fin: the low spiny part, then the tall soft lobe
	_fin(st, _mid([[0.32, 0.58], [0.38, 0.74], [0.50, 0.74], [0.60, 0.70], [0.70, 0.72], [0.79, 0.60], [0.835, 0.36]]),
		_mid([[0.33, 0.56], [0.42, 0.58], [0.54, 0.52], [0.64, 0.42], [0.74, 0.31], [0.81, 0.25], [0.835, 0.34]]), 0.03)
	# the fin under the tail stock, and the tail: a broad rounded fan
	_fin(st, _mid([[0.60, -0.42], [0.66, -0.66], [0.74, -0.62], [0.80, -0.36]]), _mid([[0.61, -0.40], [0.69, -0.33], [0.76, -0.25], [0.80, -0.34]]), 0.028)
	_fin(st, _mid([[0.85, 0.21], [0.90, 0.36], [0.955, 0.36], [0.99, 0.22], [1.0, 0.0]]),
		_mid([[0.85, -0.19], [0.90, -0.34], [0.955, -0.34], [0.99, -0.21], [1.0, 0.0]]), 0.035)
	for side in [1.0, -1.0]:
		# the breast fins: round fans held out from behind the gill covers
		_fin(st, _pair([[0.36, -0.10, 0.335], [0.52, -0.08, 0.37], [0.68, -0.13, 0.42], [0.76, -0.27, 0.465]], side),
			_pair([[0.35, -0.30, 0.35], [0.47, -0.44, 0.39], [0.62, -0.47, 0.44], [0.76, -0.29, 0.47]], side), 0.02)
		# the belly fins, small, under the breast fins
		_fin(st, _pair([[0.16, -0.50, 0.36], [0.22, -0.66, 0.40], [0.25, -0.74, 0.44]], side),
			_pair([[0.14, -0.50, 0.42], [0.2, -0.6, 0.445], [0.25, -0.73, 0.45]], side), 0.016)
		_ball(st, Vector3(0.292 * side, 0.2, _z(0.105)), Vector3(0.03, 0.042, 0.046), Color(0, 0, 0, 0))
	return st.commit()


## The spotted eagle ray: a kite-shaped disc with pointed wings swept back, the head standing
## out in front with a rounded snout like a duck's bill, a small fin at the root of a whip of a
## tail three times as long as the body. Half-span 0.85; the shader beats the wings by |x|.
static func eagle_ray() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := 0.85
	var nx := 30
	var nc := 10
	for side in 2:
		var rows: Array = []
		var inside: Array = []
		for i in nx + 1:
			var x := span * (float(i) / nx * 2.0 - 1.0)
			var t := absf(x) / span
			var zf := -0.30 * (1.0 - pow(t, 1.25)) + 0.10 * t - 0.02 * (1.0 - t)
			var zb := 0.30 * pow(1.0 - t, 1.5) + 0.16 * t
			var body := exp(-pow(x / 0.15, 2.0))
			var row: Array = []
			for j in nc + 1:
				var c := float(j) / nc
				var prof := pow(sin(PI * pow(c, 0.8)), 0.7)
				var y := (0.105 * body + 0.012 * (1.0 - t) + 0.003) * prof if side == 0 else -(0.05 * body + 0.008 * (1.0 - t) + 0.002) * prof
				row.append([Vector3(x, y, lerpf(zf, zb, c)), Color(0, 1.0 - side, 0, 1), Vector2(0.5, -1.0)])
			rows.append(row)
			inside.append(Vector3(x, 2.0 if side == 1 else -2.0, 0.0))
		_grid(st, rows, inside, false)
	# head and snout (u = z / 3.6 + 0.5)
	var head: Array = []
	for h: Array in [[-0.16, 0.105, 0.105, -0.05], [-0.26, 0.095, 0.095, -0.048], [-0.34, 0.082, 0.075, -0.044], [-0.41, 0.07, 0.052, -0.038],
			[-0.47, 0.058, 0.032, -0.03], [-0.52, 0.042, 0.02, -0.022], [-0.55, 0.022, 0.011, -0.012], [-0.56, 0.003, 0.003, -0.003]]:
		head.append([float(h[0]) / L + 0.5, h[1], h[2], h[3], 0.0])
	head.reverse()
	_trunk(st, head, 12, 2, 0.9)
	# the whip tail and the small fin at its root
	var tail: Array = []
	for h: Array in [[0.2, 0.03, 0.03, -0.02], [0.32, 0.022, 0.02, -0.018], [0.6, 0.012, 0.012, -0.012], [1.2, 0.007, 0.007, -0.007], [2.0, 0.004, 0.004, -0.004], [2.6, 0.0015, 0.0015, -0.0015]]:
		tail.append([float(h[0]) / L + 0.5, h[1], h[2], h[3], 0.0])
	_trunk(st, tail, 6, 3, 1.0)
	_fin(st, [Vector3(0, 0.02, 0.29), Vector3(0, 0.06, 0.33), Vector3(0, 0.085, 0.365)], [Vector3(0, 0.02, 0.41), Vector3(0, 0.05, 0.385), Vector3(0, 0.082, 0.372)], 0.008)
	for side in [1.0, -1.0]:
		# pelvic fins, eyes
		_fin(st, [Vector3(0.04 * side, -0.01, 0.26), Vector3(0.09 * side, -0.012, 0.32), Vector3(0.12 * side, -0.014, 0.37)],
			[Vector3(0.02 * side, -0.01, 0.37), Vector3(0.06 * side, -0.012, 0.385), Vector3(0.115 * side, -0.014, 0.385)], 0.006)
		_ball(st, Vector3(0.088 * side, 0.03, -0.37), Vector3(0.012, 0.014, 0.018), Color(0, 0, 0, 0))
	return st.commit()


## The manta ray: a broad diamond with long pointed wings, a wide head with the mouth across
## its front and the two head fins on either side of it, a short whip of a tail. Half-span 1
## (the script scales it to four meters and more across); the shader beats the wings by |x|
## and paints it from the position: black above with pale shoulder marks, white below with the
## gill slits.
static func manta_ray() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 44
	var nc := 12
	var mouth: Array = [[], []]
	for side in 2:
		var rows: Array = []
		var inside: Array = []
		for i in nx + 1:
			var x := float(i) / nx * 2.0 - 1.0
			var t := absf(x)
			# the head is cut off square in front (the mouth); the wings sweep back to a point
			var head := 1.0 - smoothstep(0.13, 0.2, t)
			var zf := lerpf(-0.36 + 0.52 * pow(t, 1.6), -0.385, head)
			var zb := 0.5 * pow(1.0 - t, 1.35) + 0.2 * t
			var body := exp(-pow(x / 0.22, 2.0))
			var row: Array = []
			for j in nc + 1:
				var c := float(j) / nc
				var prof := pow(sin(PI * pow(c, 0.75)), 0.7)
				# (the mouth: in front the upper and the lower side stay apart across the head)
				prof = maxf(prof, 0.5 * head * (1.0 - smoothstep(0.0, 0.25, c)))
				var y := (0.13 * body + 0.014 * (1.0 - t) + 0.003) * prof if side == 0 else -(0.075 * body + 0.01 * (1.0 - t) + 0.002) * prof
				var p := Vector3(x, y, lerpf(zf, zb, c))
				row.append([p, Color(0, 1.0 - side, 0, 1), Vector2(0.5, -1.0)])
				if j == 0 and t < 0.17:
					(mouth[side] as Array).append(p)
			rows.append(row)
			inside.append(Vector3(x, 2.0 if side == 1 else -2.0, 0.0))
		_grid(st, rows, inside, false)
	# the dark inside of the mouth, a little way in
	var gape: Array = [[], []]
	for k in (mouth[0] as Array).size():
		var a: Vector3 = mouth[0][k]
		var b: Vector3 = mouth[1][k]
		(gape[0] as Array).append([a + Vector3(0, -0.004, 0.02), Color(0, 0, 0, 0), Vector2(0.5, -1.0)])
		(gape[1] as Array).append([b + Vector3(0, 0.004, 0.02), Color(0, 0, 0, 0), Vector2(0.5, -1.0)])
	_grid(st, gape, [Vector3(0, 0, 1), Vector3(0, 0, 1)], false)
	for side in [1.0, -1.0]:
		# the head fins: paddles that reach forward beside the mouth, curling in at the ends
		_fin(st, [Vector3(0.185 * side, 0.03, -0.33), Vector3(0.18 * side, 0.015, -0.47), Vector3(0.15 * side, -0.02, -0.585)],
			[Vector3(0.17 * side, -0.075, -0.33), Vector3(0.16 * side, -0.075, -0.46), Vector3(0.145 * side, -0.05, -0.58)], 0.028)
		_ball(st, Vector3(0.2 * side, -0.005, -0.3), Vector3(0.016, 0.018, 0.022), Color(0, 0, 0, 0))
	# the short whip tail and the small fin at its root
	var tail: Array = []
	for h: Array in [[0.4, 0.035, 0.03, -0.022], [0.5, 0.024, 0.022, -0.018], [0.7, 0.012, 0.012, -0.012], [1.0, 0.006, 0.006, -0.006], [1.25, 0.002, 0.002, -0.002]]:
		tail.append([float(h[0]) / L + 0.5, h[1], h[2], h[3], 0.0])
	_trunk(st, tail, 6, 3, 1.0)
	_fin(st, [Vector3(0, 0.02, 0.42), Vector3(0, 0.06, 0.47), Vector3(0, 0.085, 0.51)], [Vector3(0, 0.02, 0.56), Vector3(0, 0.05, 0.535), Vector3(0, 0.082, 0.518)], 0.01)
	return st.commit()


# ------------------------------------------------------------------ sea turtles
## A sea turtle as a small tree of nodes, so that the script can move its parts: `Shell`,
## `Head` (pivot at the root of the neck), the front flippers `FlipFR` / `FlipFL` (pivots at
## the shoulders) and the hind ones `FlipRR` / `FlipRL` (at the hips). Built for a carapace 1
## long; the caller scales the node (green turtle about 0.95, hawksbill 0.78).
## Green turtle: a broad oval, smooth-edged shell, a short blunt head. Hawksbill: a narrower,
## heart-shaped shell with a keel and a saw-toothed hind edge, a narrow head with a hooked beak.
## shaders/turtle.gdshader paints the scutes from the shell's UV (x: across -1..1, y: front 0
## to back 1) and COLOR (r: 1 on the underside, g: 0 middle .. 1 rim, b: the way around).
static func turtle_node(green: bool) -> Node3D:
	var root := Node3D.new()
	var shader := load("res://shaders/turtle.gdshader") as Shader
	var mats: Array = []
	for part in 2:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("part", part)
		m.set_shader_parameter("species", 0 if green else 1)
		mats.append(m)
	var width := 0.8 if green else 0.74
	var parts := {
		"Shell": [_turtle_shell(green, width), mats[0], Vector3.ZERO],
		"Head": [_turtle_head(green), mats[1], Vector3(0, 0.03, -0.44)],
		"FlipFR": [_turtle_flipper(true, 1.0, green), mats[1], Vector3(0.33 * width, -0.01, -0.3)],
		"FlipFL": [_turtle_flipper(true, -1.0, green), mats[1], Vector3(-0.33 * width, -0.01, -0.3)],
		"FlipRR": [_turtle_flipper(false, 1.0, green), mats[1], Vector3(0.2 * width, -0.02, 0.36)],
		"FlipRL": [_turtle_flipper(false, -1.0, green), mats[1], Vector3(-0.2 * width, -0.02, 0.36)],
	}
	for key: String in parts:
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = parts[key][0]
		mi.material_override = parts[key][1]
		mi.position = parts[key][2]
		root.add_child(mi)
	return root


static func _turtle_shell(green: bool, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 44
	var rings := 9
	var high := 0.2 if green else 0.18
	var heart := 0.16 if green else 0.3
	var top: Array = []
	var bot: Array = []
	var in_top: Array = []
	var in_bot: Array = []
	for i in rings + 1:
		var r := float(i) / rings
		var rt: Array = []
		var rb: Array = []
		for j in segs + 1:
			var th := TAU * (j % segs) / float(segs)       # 0 at the front, round by the right
			# the outline: widest ahead of the middle, drawn in toward the tail
			var edge := 1.0
			if not green:
				# the hawksbill's hind edge is saw-toothed
				var rear := smoothstep(0.35, 0.8, -cos(th))
				edge += 0.045 * rear * (absf(fposmod(th * 22.0 / TAU, 1.0) - 0.5) * 2.0 - 0.5)
			var x := width * 0.5 * sin(th) * (1.0 + heart * cos(th)) * edge
			var z := -0.5 * cos(th) * edge * (1.0 if cos(th) > 0.0 else 1.0 + (0.0 if green else 0.05))
			var y := high * pow(1.0 - pow(r, 2.4), 0.8)
			if not green:
				y += 0.02 * exp(-pow(x * r / 0.045, 2.0)) * (1.0 - r)     # the keel
			var uv := Vector2(x * r / (width * 0.5), (z * r + 0.5))
			rt.append([Vector3(x * r, y, z * r), Color(0.0, r, float(j) / segs, 1.0), uv])
			rb.append([Vector3(x * r * 0.93, -0.1 * pow(1.0 - r * r, 0.5), z * r * 0.93), Color(1.0, r, float(j) / segs, 1.0), uv])
		top.append(rt)
		bot.append(rb)
		in_top.append(Vector3(0, -1.0, 0))
		in_bot.append(Vector3(0, 1.0, 0))
	_grid(st, top, in_top, true)
	_grid(st, bot, in_bot, true)
	# the edge between them
	var rim: Array = [[], []]
	for j in segs + 1:
		var a: Array = top[rings][j]
		var b: Array = bot[rings][j]
		(rim[0] as Array).append([a[0], Color(0.0, 1.0, float(j) / segs, 1.0), a[2]])
		(rim[1] as Array).append([b[0], Color(1.0, 1.0, float(j) / segs, 1.0), b[2]])
	_grid(st, rim, [Vector3(0, 0.02, 0), Vector3(0, 0.02, 0)], true)
	return st.commit()


## Head and neck, from the root of the neck (the origin) forward.
static func _turtle_head(green: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = [[0.07, 0.075, 0.06, -0.06], [-0.02, 0.068, 0.058, -0.055], [-0.09, 0.07, 0.066, -0.058], [-0.14, 0.078, 0.074, -0.062],
		[-0.19, 0.07, 0.064, -0.06], [-0.225, 0.05, 0.042, -0.05], [-0.25, 0.026, 0.02, -0.036], [-0.26, 0.004, 0.004, -0.02]]
	if not green:
		rows = [[0.07, 0.062, 0.052, -0.052], [-0.02, 0.056, 0.05, -0.046], [-0.09, 0.058, 0.056, -0.05], [-0.15, 0.064, 0.062, -0.054],
			[-0.2, 0.054, 0.052, -0.05], [-0.245, 0.036, 0.034, -0.044], [-0.28, 0.018, 0.016, -0.036], [-0.3, 0.004, 0.003, -0.03]]
	var stations: Array = []
	for h: Array in rows:
		stations.append([float(h[0]) / L + 0.5, h[1], h[2], h[3], 0.0])
	stations.reverse()
	_trunk(st, stations, 14, 2, 0.9)
	for side in [1.0, -1.0]:
		var e := Vector3(0.062 * side, 0.02, -0.165) if green else Vector3(0.05 * side, 0.02, -0.175)
		_ball(st, e, Vector3(0.011, 0.012, 0.014), Color(0, 0, 0, 0))
	return st.commit()


## A flipper as a blade from its pivot: the long front wing, or the short hind paddle.
static func _turtle_flipper(front: bool, side: float, green: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := 1.0 if green else 0.95
	var le: Array = [[-0.04, 0.0, -0.03], [0.14, 0.0, -0.06], [0.33, -0.01, -0.02], [0.49, -0.02, 0.1], [0.56, -0.03, 0.235]]
	var te: Array = [[-0.04, 0.0, 0.1], [0.13, 0.0, 0.1], [0.29, -0.01, 0.15], [0.45, -0.02, 0.21], [0.555, -0.03, 0.245]]
	var thick := 0.022
	if not front:
		le = [[-0.03, 0.0, -0.03], [0.07, 0.0, 0.05], [0.125, -0.01, 0.16], [0.12, -0.01, 0.27]]
		te = [[-0.05, 0.0, 0.07], [-0.01, 0.0, 0.16], [0.045, -0.01, 0.245], [0.115, -0.01, 0.275]]
		thick = 0.016
	var a: Array = []
	var b: Array = []
	for p: Array in le:
		a.append(Vector3(float(p[0]) * side * k, p[1], float(p[2]) * k))
	for p: Array in te:
		b.append(Vector3(float(p[0]) * side * k, p[1], float(p[2]) * k))
	_fin(st, a, b, thick, 2.0, 2.0, 0.15)
	return st.commit()
