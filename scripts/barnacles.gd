extends Node3D
## Barnacles on the granite between the tide marks: on the boulders that stand at the
## water's edge and on the granite of the shore itself (the headlands, the slabs that run
## into the sea). Two kinds, in the zones they keep on a tropical shore:
##  - the volcano barnacle (Tetraclita), a ribbed gray-pink cone two or three centimeters
##    across with a small opening, in the middle of the tidal range;
##  - the small star barnacle (Chthamalus), pale, a centimeter or less, above it up to the
##    spring tides' high-water mark and a little beyond, where the swell still wets the rock
##    (shown at 11-18 mm).
## They grow in crowds with bare rock between. Below about mid-tide there are none (there
## the rock belongs to the algae, the urchins and the corals).
## The sea's level runs from -0.80 to +0.30 at spring tides, -0.54 to +0.04 at neaps
## (scripts/tide.gd): the barnacles' belt is -0.45 .. +0.42, thickest from -0.25 to +0.2.
##
## Where they sit is found on the rocks themselves: a boulder's own triangles in the belt
## give the places (a ray from outside makes sure the place is open rock, not in the sand
## or inside the next boulder), the shore's granite is asked from above. A few milliseconds
## of that in every frame after the start; one MultiMesh per 6 m of shore, drawn to 30 m.
## The node is created by island_life.gd.

const LO := -0.45
const HI := 0.42
const CELL := 6.0
const SEEDS_PER_M2 := 24.0       # crowds (and single ones) per m2 of rock in the belt
const MAX_ALL := 340000
const RANGE := 26.0

var count := 0                  # (for the tests) barnacles in all
var on_boulders := 0
var on_shore := 0
var rocks_with := 0
var done := false
var by_height := [0, 0, 0, 0, 0, 0]     # how many in each sixth of the belt, from the bottom
var spots: Array = []           # Vector3: the middle of every twelfth crowd (for looking at them)
var _crowds := 0

var _ls: Node
var _player: Node3D
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _rocks: Array = []          # MeshInstance3D still to do
var _faces := PackedVector3Array()
var _xf := Transform3D()
var _tri_i := 0
var _tris: Array = []           # [a, b, c] in the world, of the rock in hand, in the belt
var _areas := PackedFloat32Array()
var _area := 0.0
var _seeds_left := 0
var _state := 0                 # 0 next rock, 1 its triangles, 2 its crowds, 3 the shore, 4 done
var _buckets := {}              # Vector3i -> [[Transform3D], [Color]]
var _shore_cells: Array = []
var _mask: Image
var _space: PhysicsDirectSpaceState3D
var _q := PhysicsRayQueryParameters3D.new()


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_rng.seed = 90210
	_mesh = _barnacle_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/barnacle.gdshader")
	_mask = ls._mask
	_q.collision_mask = 1


## A cone of six plates, a little uneven, the opening at the top a dark pit: a meter across
## at its foot (the instances scale it).
func _barnacle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := RandomNumberGenerator.new()
	g.seed = 12
	var sides := 8
	var foot: Array = []
	var rim: Array = []
	var pit: Array = []
	for i in sides:
		var a := TAU * i / sides
		var dir := Vector3(cos(a), 0.0, sin(a))
		var wide := 0.5 * g.randf_range(0.84, 1.12)
		foot.append(dir * wide - Vector3(0, 0.06, 0))
		rim.append(dir * (0.24 * g.randf_range(0.8, 1.2)) + Vector3(0, 0.42 * g.randf_range(0.86, 1.1), 0))
		pit.append(dir * 0.15 + Vector3(0, 0.31, 0))
	for i in sides:
		var j := (i + 1) % sides
		# the wall: its plates lighter along their middles, darker in the seams between
		var light := Color(1.0, 1.0, 1.0) if i % 2 == 0 else Color(0.72, 0.7, 0.68)
		var n := ((rim[i] as Vector3) - (foot[i] as Vector3)).cross((foot[j] as Vector3) - (foot[i] as Vector3)).normalized()
		if n.dot(foot[i] as Vector3) < 0.0:
			n = -n
		_emit(st, foot[i], foot[j], rim[j], n, light * 0.86, light * 0.86, light)
		_emit(st, foot[i], rim[j], rim[i], n, light * 0.86, light, light)
		# the lip, down into the opening
		var dark := Color(0.34, 0.3, 0.26)
		var inward := -Vector3((rim[i] as Vector3).x, -0.25, (rim[i] as Vector3).z).normalized()
		_emit(st, rim[i], rim[j], pit[j], inward, light * 0.7, light * 0.7, dark)
		_emit(st, rim[i], pit[j], pit[i], inward, light * 0.7, dark, dark)
		# the valves that close it
		_emit(st, pit[i], pit[j], Vector3(0, 0.33, 0), Vector3.UP, dark, dark, Color(0.42, 0.38, 0.33))
	return st.commit()


func _emit(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# (front faces are wound clockwise: the corners are put in the order the normal asks for)
	var pts := [[a, ca], [b, cb], [c, cc]]
	if (c - a).cross(b - a).dot(n) < 0.0:
		pts = [[a, ca], [c, cc], [b, cb]]
	for p: Array in pts:
		st.set_color(p[1])
		st.set_normal(n)
		st.add_vertex(p[0])


func _physics_process(_delta: float) -> void:
	if done or _ls == null or Engine.get_physics_frames() < 70:
		return
	if _space == null:
		_space = get_world_3d().direct_space_state
		if _player is CollisionObject3D:
			_q.exclude = [(_player as CollisionObject3D).get_rid()]
		var boulders := _ls.get_node_or_null("Boulders")
		if boulders:
			_rocks.append_array(boulders.find_children("*", "MeshInstance3D", true, false))
		var rocks := _ls.get_parent().get_node_or_null("Rocks") if _ls.get_parent() else null
		if rocks:
			_rocks.append_array(rocks.find_children("*", "MeshInstance3D", true, false))
		_shore_cells = _find_shore_cells()
	_work(2500)


## For the tests: all of it now.
func finish() -> Dictionary:
	if not done and _space == null:
		_physics_process(0.0)
	while not done:
		_work(0)
	return report()


func _work(budget: int) -> void:
	var t0 := Time.get_ticks_usec()
	while not done:
		match _state:
			0:
				_next_rock()
			1:
				_read_triangles()
			2:
				_grow_on_rock()
			3:
				_grow_on_shore()
		if budget > 0 and Time.get_ticks_usec() - t0 > budget:
			return


func _next_rock() -> void:
	if _rocks.is_empty() or count >= MAX_ALL:
		_flush()
		_state = 3
		return
	var mi: MeshInstance3D = _rocks.pop_back()
	if mi.mesh == null:
		return
	var box: AABB = mi.global_transform * mi.mesh.get_aabb()
	if box.position.y > HI or box.end.y < LO or not _at_the_sea(box):
		return
	_faces = mi.mesh.get_faces()
	_xf = mi.global_transform
	_tri_i = 0
	_tris.clear()
	_areas.clear()
	_area = 0.0
	_state = 1


## Does the sea come to this rock? (A boulder in a hollow inland, or at the pond, is not for
## barnacles.) Some place close around it lies below the neap tides' high water.
func _at_the_sea(box: AABB) -> bool:
	var mid := box.get_center()
	var r := maxf(box.size.x, box.size.z) * 0.5
	if float(_ls.ground(mid.x, mid.z)) < -0.3:
		return true
	for ring: float in [r + 1.0, r + 4.0]:
		for k in 10:
			var a := TAU * k / 10.0
			if float(_ls.ground(mid.x + cos(a) * ring, mid.z + sin(a) * ring)) < -0.4:
				return true
	return false


func _read_triangles() -> void:
	var n := _faces.size() / 3
	var until := mini(_tri_i + 2500, n)
	while _tri_i < until:
		var a := _xf * _faces[_tri_i * 3]
		var b := _xf * _faces[_tri_i * 3 + 1]
		var c := _xf * _faces[_tri_i * 3 + 2]
		_tri_i += 1
		var top := maxf(a.y, maxf(b.y, c.y))
		var bottom := minf(a.y, minf(b.y, c.y))
		if top < LO or bottom > HI:
			continue
		var area := (b - a).cross(c - a).length() * 0.5
		# (a triangle that reaches out of the belt counts with the share that lies in it)
		if top - bottom > 0.001:
			area *= clampf((minf(top, HI) - maxf(bottom, LO)) / (top - bottom), 0.0, 1.0)
		if area < 1e-6:
			continue
		_area += area
		_tris.append([a, b, c])
		_areas.append(_area)
	if _tri_i >= n:
		_faces = PackedVector3Array()
		_seeds_left = int(_area * SEEDS_PER_M2)
		_state = 2 if _seeds_left > 0 else 0
		if _seeds_left > 0:
			rocks_with += 1


func _grow_on_rock() -> void:
	for step in 12:
		if _seeds_left <= 0:
			break
		_seeds_left -= 1
		# a place on the rock, by area
		var want := _rng.randf() * _area
		var lo := 0
		var hi := _areas.size() - 1
		while lo < hi:
			var m := (lo + hi) / 2
			if _areas[m] < want:
				lo = m + 1
			else:
				hi = m
		var tri: Array = _tris[lo]
		var u := _rng.randf()
		var v := _rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var a: Vector3 = tri[0]
		var p := a + ((tri[1] as Vector3) - a) * u + ((tri[2] as Vector3) - a) * v
		var n := ((tri[1] as Vector3) - a).cross((tri[2] as Vector3) - a).normalized()
		if _rng.randf() > _share(p.y) * _patch(p):
			continue
		# open rock? A ray from outside must come down on this very place (not on the sand
		# over it, nor on the next boulder); the triangle's own side is not known: both tried
		var found := false
		for side: float in [1.0, -1.0]:
			var hit := _ray(p + n * side * 0.2, p - n * side * 0.05)
			if not hit.is_empty() and (hit["position"] as Vector3).distance_to(p) < 0.03 and _rock(hit):
				n = n * side
				found = true
				break
		if not found:
			continue
		on_boulders += _crowd(p, n, true)
	if _seeds_left <= 0:
		_state = 0


## How thick they grow at this height: 0 .. 1.
func _share(y: float) -> float:
	return smoothstep(LO, -0.25, y) * (1.0 - smoothstep(0.2, HI, y))


## They do not cover the belt evenly: stretches of a meter or two are thick with them, others
## nearly bare. 0 .. 1 for a place.
func _patch(p: Vector3) -> float:
	var n := 0.5 + 0.5 * sin(p.x * 1.1 + sin(p.z * 0.83 + p.y * 2.1) * 1.9) * sin(p.z * 0.97 + sin(p.x * 0.71 - p.y * 1.7) * 1.6)
	return 0.12 + 0.88 * smoothstep(0.3, 0.62, n)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	_q.from = from
	_q.to = to
	return _space.intersect_ray(_q)


## Is it rock that the ray met (a boulder, the grotto), not the ground or a trunk? The
## collision shapes say what they are (meta "rain": world.gd, landscape.gd; 2 is rock).
var _kinds := {}
func _kind(hit: Dictionary) -> int:
	var body: Object = hit["collider"]
	var shape: int = hit["shape"]
	if not _kinds.has(body):
		_kinds[body] = {}
	var of: Dictionary = _kinds[body]
	if not of.has(shape):
		var co := body as CollisionObject3D
		var node: Object = co.shape_owner_get_owner(co.shape_find_owner(shape)) if co else null
		of[shape] = int(node.get_meta("rain", 0)) if node else 0
	return of[shape]


func _rock(hit: Dictionary) -> bool:
	return _kind(hit) == 2


## A crowd of barnacles around p (or one or two by themselves), each set on the rock where a
## ray finds it. `on_rock`: on a boulder (else on the shore's granite). Returns how many.
func _crowd(p: Vector3, n: Vector3, on_rock: bool) -> int:
	var single := _rng.randf() < 0.3
	var many := _rng.randi_range(1, 3) if single else _rng.randi_range(12, 44)
	var spread := 0.03 if single else _rng.randf_range(0.05, 0.14)
	var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := n.cross(t1)
	var placed: Array = []
	var got := 0
	for i in many:
		var d := Vector2.from_angle(_rng.randf() * TAU) * (spread * sqrt(_rng.randf()))
		var q := p + t1 * d.x + t2 * d.y
		var hit := _ray(q + n * 0.06, q - n * 0.06)
		if hit.is_empty() or (_kind(hit) == 2) != on_rock or (not on_rock and _kind(hit) != 1):
			continue
		var at: Vector3 = hit["position"]
		var up: Vector3 = hit["normal"]
		if at.y < LO or at.y > HI:
			continue
		# the volcano barnacle below, the small star barnacle above (they overlap a little)
		var high := smoothstep(-0.12, 0.12, at.y + _rng.randf_range(-0.06, 0.06))
		# (the volcano barnacle at its full size, the star barnacle a little over life: at
		# a true 6 mm it would not be seen from standing height)
		var wide := lerpf(_rng.randf_range(0.023, 0.044), _rng.randf_range(0.011, 0.018), high)
		var free := true
		for o: Array in placed:
			if (o[0] as Vector3).distance_to(at) < (float(o[1]) + wide) * 0.5:
				free = false
				break
		if not free:
			continue
		placed.append([at, wide])
		var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, _rng.randf() * TAU)
		var tall := lerpf(_rng.randf_range(0.8, 1.15), _rng.randf_range(0.55, 0.8), high)
		var xf := Transform3D(b.scaled(Vector3(wide, wide * tall, wide)), at)
		# gray-pink to gray-green below, pale gray-buff above; some greened over by algae
		# (matt shell, a shade or two paler than the wet rock it sits on: not white)
		var col := Color(0.37, 0.33, 0.31).lerp(Color(0.31, 0.33, 0.29), _rng.randf()) if high < 0.5 else Color(0.46, 0.43, 0.39).lerp(Color(0.39, 0.37, 0.34), _rng.randf())
		col = col.lerp(Color(0.2, 0.25, 0.15), _rng.randf() * 0.45 * (1.0 - high))
		col = col * _rng.randf_range(0.9, 1.26)
		if not on_rock:
			# (the shore's granite is drawn pale, not darkened like the boulders' feet: the
			# shells are a shade paler than their rock there too)
			col = (col * 1.75).lerp(Color(0.72, 0.69, 0.62), 0.35)
		var key := Vector3i(floori(at.x / CELL), 0, floori(at.z / CELL))
		if not _buckets.has(key):
			_buckets[key] = [[], []]
		(_buckets[key][0] as Array).append(xf)
		(_buckets[key][1] as Array).append(col)
		by_height[clampi(int((at.y - LO) / (HI - LO) * 6.0), 0, 5)] += 1
		got += 1
	count += got
	if got >= 6:
		_crowds += 1
		if _crowds % 12 == 0:
			spots.append(p)
	return got


## The shore's own granite: the 6 m squares that hold rock in the belt.
func _find_shore_cells() -> Array:
	var cells: Array = []
	var x := -240.0
	while x < 140.0:
		var z := -250.0
		while z < 250.0:
			var hit := false
			for i in 4:
				for j in 4:
					var p := Vector2(x + (i + 0.5) * CELL / 4.0, z + (j + 0.5) * CELL / 4.0)
					if _granite(p):
						hit = true
			if hit:
				cells.append(Vector2(x, z))
			z += CELL
		x += CELL
	return cells


## Granite of the shore in the barnacles' belt at p? (The land mask: green is bare rock on
## land, blue the same rock where the sea covers it.)
func _granite(p: Vector2) -> bool:
	var y: float = _ls.ground(p.x, p.y)
	if y < LO or y > HI or _mask == null:
		return false
	var u := int(clampf((p.x + 256.0) / 512.0 * _mask.get_width(), 0, _mask.get_width() - 1))
	var v := int(clampf((p.y + 256.0) / 512.0 * _mask.get_height(), 0, _mask.get_height() - 1))
	var mk := _mask.get_pixel(u, v)
	return mk.g > 0.5 if y >= 0.0 else mk.b > 0.3


func _grow_on_shore() -> void:
	if _shore_cells.is_empty() or count >= MAX_ALL:
		_flush()
		_state = 4
		done = true
		set_physics_process(false)
		return
	var corner: Vector2 = _shore_cells.pop_back()
	for i in int(CELL * CELL * SEEDS_PER_M2):
		var p := corner + Vector2(_rng.randf(), _rng.randf()) * CELL
		if not _granite(p):
			continue
		var y: float = _ls.ground(p.x, p.y)
		if _rng.randf() > _share(y) * _patch(Vector3(p.x, y, p.y)):
			continue
		# (the drawn ground, which is a little off the height map; and not under a boulder)
		var hit := _ray(Vector3(p.x, y + 0.5, p.y), Vector3(p.x, y - 0.5, p.y))
		if hit.is_empty() or _kind(hit) != 1:
			continue
		on_shore += _crowd(hit["position"], hit["normal"], false)
	_flush()


## The barnacles gathered so far become MultiMeshes, one per 6 m square.
func _flush() -> void:
	for key: Vector3i in _buckets:
		var xfs: Array = _buckets[key][0]
		var cols: Array = _buckets[key][1]
		if xfs.is_empty():
			continue
		var center := Vector3.ZERO
		for xf: Transform3D in xfs:
			center += xf.origin
		center /= xfs.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh
		mm.instance_count = xfs.size()
		var inv := Transform3D(Basis(), -center)
		for i in xfs.size():
			mm.set_instance_transform(i, inv * (xfs[i] as Transform3D))
			mm.set_instance_color(i, cols[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = RANGE
		mi.position = center
		add_child(mi)
	_buckets.clear()


## For the tests.
func report() -> Dictionary:
	return {"done": done, "barnacles": count, "on boulders": on_boulders, "on the shore's granite": on_shore, "boulders with any": rocks_with,
		"by height (sixths of the belt, from the bottom)": by_height, "squares": get_child_count(), "crowds noted": spots.size()}


## For the tests: the crowd nearest to a place.
func nearest(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := 1e9
	for s: Vector3 in spots:
		if s.distance_to(p) < bd:
			bd = s.distance_to(p)
			best = s
	return best
