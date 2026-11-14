extends Node3D
## Moon jellyfish (Aurelia) in the lagoon: a few loose groups that drift with the water a
## meter or two under the surface, each animal beating its bell every three seconds or so
## and getting a little way with every beat. Clear bells 20-34 cm across with the four
## pale violet rings, a fringe of fine tentacles and four frilled arms.
## They go nowhere in particular: a group wanders slowly about its part of the lagoon, an
## animal about its group. They do not notice a swimmer (they have no eyes for one): the
## water a swimmer pushes ahead moves them aside. They keep under the surface, over the
## corals and the floor, and out of water shallower than two meters.
## One MultiMesh; the beat and the swaying are the shader's (shaders/jellyfish.gdshader).
## The node is created by island_life.gd.

const GROUPS := [
	# [middle of its water (x, z), how far it wanders from there, how many]
	[Vector2(46.0, -6.0), 20.0, 6],       # off the start beach, on the way out to the reef
	[Vector2(48.0, 58.0), 18.0, 4],       # further north in the same lagoon
	[Vector2(44.0, -62.0), 16.0, 3],      # and south of it
]
const MIN_WATER := 2.0           # they keep to water at least this deep
const UNDER_SURFACE := 0.35      # the bell's top stays this far under the sea's level

var jellies: Array = []          # one dictionary each
var groups: Array = []           # {"home", "range", "at", "to"}
var touched := 0                 # how often a swimmer has pushed one aside (for the tests)

var _ls: Node
var _player: Node3D
var _seabed: Node
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _was_under := true
var _everybody := false          # (the soak test: nobody is left out for being far away)


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed
	_rng.seed = 8128
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/jellyfish.gdshader")
	_mat.render_priority = 101
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh()
	var total := 0
	for g: Array in GROUPS:
		total += int(g[2])
	_mm.instance_count = total
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "MoonJellies"
	_mmi.multimesh = _mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-1e4, -100, -1e4), Vector3(2e4, 200, 2e4))
	add_child(_mmi)
	for gi in GROUPS.size():
		var g: Array = GROUPS[gi]
		var home: Vector2 = g[0]
		groups.append({"home": home, "range": float(g[1]), "at": home, "to": home, "moved": Vector2.ZERO})
		for i in int(g[2]):
			var at := home + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * 5.0)
			var deep := _rng.randf_range(0.6, 2.0)
			var size := _rng.randf_range(0.1, 0.17)      # the bell's radius
			jellies.append({"group": gi, "pos": Vector3(at.x, -deep, at.y), "up": Vector3.UP, "want_up": Vector3.UP, "size": size,
				"phase": _rng.randf(), "every": lerpf(2.4, 3.8, inverse_lerp(0.1, 0.17, size)) * _rng.randf_range(0.9, 1.15),
				"deep": deep, "head": _rng.randf() * TAU, "t": _rng.randf_range(2.0, 9.0), "seed": _rng.randf(), "spin": _rng.randf() * TAU,
				"off": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.0, 5.5)})
	_write()


## The mesh: a bell a meter in radius (the instances scale it), its top at 0.45.
static func mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var rings := 8
	# the bell's outside and inside
	for layer in 2:
		var grid: Array = []
		for i in rings + 1:
			var v := float(i) / rings
			var a := v * PI * 0.5
			var r := pow(sin(a), 0.8) * (1.0 if layer == 0 else 0.93)
			var y := 0.45 * pow(cos(a), 0.9) * (1.0 if layer == 0 else 0.7) - (0.0 if layer == 0 else 0.02)
			var row: Array = []
			for j in segs + 1:
				var th := TAU * j / segs
				var p := Vector3(cos(th) * r, y, sin(th) * r)
				var n := Vector3(cos(th) * sin(a), cos(a) + 0.2, sin(th) * sin(a)).normalized() * (1.0 if layer == 0 else -1.0)
				row.append([p, n, Color(v, 0.0 if layer == 0 else 0.25, 0.0), Vector2(p.x, p.z) * 0.5 + Vector2(0.5, 0.5), Vector2(float(j) / segs, 0.0)])
			grid.append(row)
		_quads(st, grid)
	# the fringe: a short curtain from the rim
	var fringe: Array = []
	for i in 4:
		var l := float(i) / 3.0
		var row: Array = []
		for j in segs * 2 + 1:
			var th := TAU * j / (segs * 2)
			var r := 1.0 + 0.02 * l
			var p := Vector3(cos(th) * r, -0.17 * l, sin(th) * r)
			row.append([p, Vector3(cos(th), 0.0, sin(th)), Color(1.0, 0.5, l), Vector2(0.5, 0.5), Vector2(float(j) / (segs * 2), 0.0)])
		fringe.append(row)
	_quads(st, fringe)
	# the four arms: frilled ribbons from under the middle
	for k in 4:
		var th := TAU * k / 4.0
		var out := Vector3(cos(th), 0.0, sin(th))
		var side := Vector3(-sin(th), 0.0, cos(th))
		var arm: Array = []
		for i in 17:
			var l := float(i) / 16.0
			var mid := out * (0.1 + 0.16 * sin(l * PI * 0.8)) + Vector3(0, 0.2 - 0.85 * l, 0)
			var wide := lerpf(0.17, 0.04, l) * (1.0 + 0.2 * sin(l * 9.0 + k))
			var row: Array = []
			for j in 5:
				var sd := float(j) * 0.5 - 1.0
				# (the frill: the edges wave in and out)
				var p := mid + side * (sd * wide) + out * (absf(sd) * absf(sd) * 0.06 * sin(l * 11.0 + k * 1.7 + sd * 2.0))
				row.append([p, out, Color(0.0, 0.75, l), Vector2(0.5, 0.5), Vector2(0.0, float(k))])
			arm.append(row)
		_quads(st, arm)
	return st.commit()


static func _quads(st: SurfaceTool, grid: Array) -> void:
	for i in grid.size() - 1:
		for j in (grid[i] as Array).size() - 1:
			for q: Array in [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]]:
				st.set_color(q[2])
				st.set_normal(q[1])
				st.set_uv(q[3])
				st.set_uv2(q[4])
				st.add_vertex(q[0])


func _process(delta: float) -> void:
	if _player == null or jellies.is_empty():
		return
	delta = minf(delta, 0.1)
	# (the eye under water or over it: see the shader's head)
	var under: bool = _player.get("underwater") == true
	if under != _was_under:
		_was_under = under
		_mat.render_priority = 101 if under else -1
		_mat.set_shader_parameter("under", under)
	var veil: ShaderMaterial = _player.get("_veil_mat")
	var night := 0.0
	var dc := get_node_or_null("../../DayCycle")
	if dc:
		night = dc.night
	_mat.set_shader_parameter("light", float(veil.get_shader_parameter("light")) if veil and under and veil.get_shader_parameter("light") != null else lerpf(1.0, 0.1, night))
	step(delta, _player.global_position)
	_write()


## Everybody a moment further. `swimmer`: where the swimmer's feet are (the body reaches
## 1.7 m up from there, or along the surface: both ends count).
func step(delta: float, swimmer: Vector3) -> void:
	var sea: float = _ls.sea
	for g: Dictionary in groups:
		# the group's middle wanders about its water, a few centimeters a second
		var at: Vector2 = g["at"]
		var to: Vector2 = g["to"]
		if at.distance_to(to) < 1.0:
			for tries in 12:
				var q: Vector2 = (g["home"] as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * float(g["range"]))
				if sea - float(_ls.ground(q.x, q.y)) > MIN_WATER + 1.0:
					g["to"] = q
					break
		else:
			g["at"] = at.move_toward(to, 0.035 * delta)
		# (it is the water that moves: it carries every animal of the group along)
		g["moved"] = (g["at"] as Vector2) - at
	for j: Dictionary in jellies:
		var pos: Vector3 = j["pos"]
		var g: Dictionary = groups[int(j["group"])]
		if not _everybody and Vector2(pos.x - swimmer.x, pos.z - swimmer.z).length() > 70.0:
			continue
		var size: float = j["size"]
		var here := Vector2(pos.x, pos.z)
		# its beat, and the way it gets with it: a push as the bell closes, then gliding
		var ph: float = fposmod(float(j["phase"]) + delta / float(j["every"]), 1.0)
		j["phase"] = ph
		var push := smoothstep(0.05, 0.3, ph) * (1.0 - smoothstep(0.3, 0.95, ph))
		var up: Vector3 = j["up"]
		# (it beats harder when it is under the depth it keeps, and lets itself sink when it
		# is over it: `effort`, set further down)
		var vel := up * (0.012 + 0.085 * push) * float(j.get("effort", 0.5)) + Vector3(0, -0.012, 0)
		# where it means to go: about its place in the group, at its depth
		j["t"] = float(j["t"]) - delta
		if float(j["t"]) <= 0.0:
			j["t"] = _rng.randf_range(30.0, 90.0)
			j["off"] = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.5, 7.0)
			j["deep"] = _rng.randf_range(0.6, 2.3)
		var goal: Vector2 = (g["at"] as Vector2) + (j["off"] as Vector2)
		var floor_y: float = _ls.ground(here.x, here.y)
		if _seabed and _seabed.has_method("top_at"):
			floor_y = maxf(floor_y, float(_seabed.top_at(here, 1.0)))
		# (the arms hang a bell's width under it: they are to clear what stands below)
		var lowest := floor_y + 0.35 + size * 1.3
		var highest := sea - UNDER_SURFACE - size * 0.45
		# (under the anchored boat: under its keel)
		if _seabed and _seabed.has_method("boat_over") and _seabed.boat_over(here.x, here.y, 0.5):
			highest -= 0.6
		var want_y := clampf(sea - float(j["deep"]), lowest, maxf(highest, lowest))
		var away := goal - here
		# out of the shallows: toward deeper water
		var water: float = sea - float(_ls.ground(here.x, here.y))
		if water < MIN_WATER + 0.6:
			var e := 1.5
			var deeper := Vector2(float(_ls.ground(here.x - e, here.y)) - float(_ls.ground(here.x + e, here.y)), float(_ls.ground(here.x, here.y - e)) - float(_ls.ground(here.x, here.y + e)))
			if deeper.length() > 0.001:
				away = deeper.normalized() * 6.0
		# the bell leans the way it wants to go: mostly upright, tipped over to rise less
		var rise := clampf((want_y - pos.y) * 1.2, -0.45, 1.0)
		j["effort"] = lerpf(float(j.get("effort", 0.5)), clampf(0.35 + (want_y - pos.y) * 1.6, 0.05, 1.0), 1.0 - exp(-delta * 0.5))
		# (a quarter of the way over at most when it has far to go; nearly upright at its place)
		var lean := (Vector3(away.x, 0.0, away.y) / 4.0).limit_length(1.0) * 0.5
		j["want_up"] = (Vector3(0, 0.6 + maxf(rise, 0.0), 0) + lean + Vector3(0, minf(rise, 0.0), 0)).normalized()
		up = up.slerp(j["want_up"], 1.0 - exp(-delta * 0.35)).normalized()
		j["up"] = up
		var before := pos
		pos += vel * delta + Vector3((g["moved"] as Vector2).x, 0.0, (g["moved"] as Vector2).y)
		# the water a swimmer pushes ahead moves it aside
		for part: Vector3 in [swimmer + Vector3(0, 0.3, 0), swimmer + Vector3(0, 1.2, 0)]:
			var off := pos + Vector3(0, -size * 0.3, 0) - part
			var reach := 0.55 + size
			if off.length() < reach:
				pos += off.normalized() * minf((reach - off.length()), 0.5 * delta)
				touched += 1
		# and they give each other room (a bell does not go through a bell)
		for o: Dictionary in jellies:
			if o == j or int(o["group"]) != int(j["group"]):
				continue
			var gap: Vector3 = pos - (o["pos"] as Vector3)
			var room := (size + float(o["size"])) * 1.25 + 0.12
			if gap.length() < room and gap.length() > 0.001:
				pos += gap.normalized() * minf(room - gap.length(), 0.08 * delta)
		# not over ground or a coral that leaves it no room under the surface: it stays
		# where it was (the water goes around such a place, and so does what drifts in it)
		var there := Vector2(pos.x, pos.z)
		var floor_there: float = _ls.ground(there.x, there.y)
		if _seabed and _seabed.has_method("top_at"):
			floor_there = maxf(floor_there, float(_seabed.top_at(there, 1.0)))
		if sea - floor_there < 1.3:
			pos.x = before.x
			pos.z = before.z
		else:
			lowest = floor_there + 0.35 + size * 1.3
		# never out of the water, never into what stands on the floor
		pos.y = clampf(pos.y, lowest, maxf(highest, lowest))
		j["pos"] = pos
		j["spin"] = float(j["spin"]) + delta * 0.05


func _write() -> void:
	for i: int in _markers:
		(_markers[i] as Node3D).global_position = jellies[i]["pos"]
	for i in jellies.size():
		var j: Dictionary = jellies[i]
		var size: float = j["size"]
		var b := Basis(Quaternion(Vector3.UP, j["up"] as Vector3)) * Basis(Vector3.UP, float(j["spin"]))
		_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * size), j["pos"] as Vector3))
		_mm.set_instance_custom_data(i, Color(float(j["phase"]), float(j["seed"]), 0.0, 0.0))


## For the tests: a node that goes with jellyfish number i (for the driver's `chase` and `look`).
var _markers := {}
func marker(i: int) -> Node3D:
	if not _markers.has(i):
		var n := Node3D.new()
		add_child(n)
		_markers[i] = n
		n.global_position = jellies[i]["pos"]
	return _markers[i]


## For the tests.
func report() -> Dictionary:
	var sea: float = _ls.sea
	var out: Array = []
	for j: Dictionary in jellies:
		var p: Vector3 = j["pos"]
		out.append([int(j["group"]), Vector3(snappedf(p.x, 0.1), snappedf(p.y, 0.01), snappedf(p.z, 0.1)), snappedf(sea - p.y, 0.01), snappedf(float(j["size"]) * 2.0, 0.01)])
	return {"jellies": jellies.size(), "sea": sea, "pushed aside (frames)": touched, "group, place, depth under the surface, bell (m)": out}


## For the tests: `seconds` of their life without drawing, a swimmer crossing the first
## group's water to and fro if `swimmer`; says where they got to and whether anybody was
## ever out of the water, in the floor or a coral, in the shallows or far from its group.
func soak(seconds: float, swimmer := false) -> Dictionary:
	_everybody = true
	var t := 0.0
	var surfaced := 0
	var grounded := 0
	var shallow := 0
	var strayed := 0.0
	var nan := 0
	var traveled := 0.0
	var start: Vector3 = jellies[0]["pos"]
	var least_clear := 99.0
	var nearest_swimmer := 99.0
	var nearest_pair := 99.0
	while t < seconds:
		var sw := Vector3(0, -50, 0)
		if swimmer:
			var g0: Vector2 = groups[0]["at"]
			sw = Vector3(g0.x + sin(t * 0.05) * 14.0, float(_ls.sea) - 1.2, g0.y + sin(t * 0.031) * 9.0)
		step(0.1, sw)
		t += 0.1
		for j: Dictionary in jellies:
			var p: Vector3 = j["pos"]
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
				nan += 1
				continue
			var size: float = j["size"]
			if p.y + size * 0.45 > float(_ls.sea) - 0.2:
				surfaced += 1
			var here := Vector2(p.x, p.z)
			var top: float = maxf(float(_ls.ground(p.x, p.z)), float(_seabed.top_at(here, 0.01)) if _seabed else -99.0)
			least_clear = minf(least_clear, p.y - size * 1.3 - top)
			if p.y - size * 1.3 < top:
				grounded += 1
			if float(_ls.sea) - float(_ls.ground(p.x, p.z)) < MIN_WATER - 0.3:
				shallow += 1
			strayed = maxf(strayed, here.distance_to(groups[int(j["group"])]["at"] as Vector2))
			if swimmer:
				nearest_swimmer = minf(nearest_swimmer, (p - sw - Vector3(0, 0.7, 0)).length())
			for o: Dictionary in jellies:
				if o != j:
					nearest_pair = minf(nearest_pair, p.distance_to(o["pos"] as Vector3) - size - float(o["size"]))
	traveled = (jellies[0]["pos"] as Vector3).distance_to(start)
	_everybody = false
	var depths: Array = []
	for j: Dictionary in jellies:
		depths.append(snappedf(float(_ls.sea) - (j["pos"] as Vector3).y, 0.01))
	return {"seconds": seconds, "depths now": depths, "out of the water (samples)": surfaced, "in the floor or a coral": grounded, "least room under one (m)": snappedf(least_clear, 0.01), "in the shallows": shallow,
		"furthest from its group (m)": snappedf(strayed, 0.1), "not a number": nan, "the first one got (m)": snappedf(traveled, 0.1), "nearest to the swimmer (m)": snappedf(nearest_swimmer, 0.01), "least room between two bells (m)": snappedf(nearest_pair, 0.01),
		"groups at": [groups[0]["at"], groups[1]["at"], groups[2]["at"]]}
