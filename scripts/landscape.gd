@tool
extends Node3D
## Turns the original Blender beach into a whole island by re-using its vegetation:
## a second treeline north of the beach, a mirrored headland, jungle layers, a forest
## of large takamaka trees, palms along every shore, bush clusters, extra granite
## rocks, a trail to the summit lookout, distant islands and beach debris.
## All copies share the source meshes (no extra memory).

const HM_EXT := 256.0
const Heights := preload("res://scripts/heights.gd")

var _mask: Image
var _rng := RandomNumberGenerator.new()
## A second stream for later additions, so that they leave everything placed from _rng where it is.
var _frng := RandomNumberGenerator.new()
var _world: Node3D
var _collide: Array = []   # [mesh, transform, is_bush?, is_rock?]
var _trail: PackedVector2Array = PackedVector2Array()
var _peak := Vector2(-110, -12)
var _east_shore := -168.0
## Compass: +x is WEST (the start beach and its sea, where the sun sets), -x east, +z NORTH,
## -z south. (Until 2026-11-12 the names here had it the other way around: `west_shift()` was
## `east_shift()`, `_east_shore` was `_west_shore`, and so on. See HANDOFF.md, "Orientation".)
## How the west coast turns away to the east south and north of the start beach
## (island.json "taper", written by tools/terrain2.py).
var _taper := {}

# --- data the animals use (filled by build)
var palm_trunks: Array = []    # [{"pts": PackedVector3Array (base -> crown, world), "r": PackedFloat32Array}]
var tree_spots: Array = []     # [{"xf": Transform3D, "kind": "Tree3" / "Jack1", "colony": bool}]
var boulder_spots: Array = []  # [Vector3 center on the ground, size]
## the seabird colony: a grove of Pisonia trees on the wooded southern headland
var colony_center := Vector2(-96.0, -188.0)
const COLONY_R := 22.0
## The grotto: a way through a pile of granite boulders on the hillside above the start beach,
## from the entrance facing west through two rooms to a second mouth higher up the hill. Its
## layout comes from assets/models/grotto.json (tools/terrain2.py: CAVE_PATH cuts the floor into
## the terrain, tools/grotto2.py piles the boulders around it), all in world coordinates.
var cave := {}
## The level of the sea now (0 as the island was built; scripts/tide.gd moves it). Everything
## that asks how deep the water is, or where the waterline lies, takes the ground against this.
var sea := 0.0
## Points along the way through, about a meter apart: [floor point, half-width, height, arc length]
var cave_path: Array = []
var _cave_roofed := Vector2.ZERO    # the stretch of arc length that lies under the boulders
var _cave_way := PackedVector2Array()   # the whole way through, and 7 m on beyond both mouths
var _cave_rect := Rect2()
var cave_center := Vector2(-62.2, 46.3)   # the front room
var cave_xf := Transform3D()              # origin on its floor, +Z out through the entrance
const CAVE_R := 9.0


func _load_cave() -> void:
	cave_path.clear()
	var f := FileAccess.open("res://assets/models/grotto.json", FileAccess.READ)
	if f == null:
		return
	cave = JSON.parse_string(f.get_as_text())
	for p in cave["path"]:
		cave_path.append([Vector3(p[0], p[1], p[2]), float(p[3]), float(p[4]), float(p[5])])
		var at := Vector2(p[0], p[2])
		_cave_rect = Rect2(at, Vector2.ZERO) if cave_path.size() == 1 else _cave_rect.expand(at)
	_cave_rect = _cave_rect.grow(30.0)
	_cave_way.clear()
	var n := cave_path.size()
	for i in n:
		var q: Vector3 = cave_path[i][0]
		_cave_way.append(Vector2(q.x, q.z))
	for e in [[0, mini(2, n - 1)], [n - 1, maxi(n - 3, 0)]]:
		var a: Vector2 = _cave_way[e[0]]
		var dir := (a - _cave_way[e[1]]).normalized()
		for k in range(1, 8):
			_cave_way.append(a + dir * float(k))
	_cave_roofed = Vector2(cave["roofed"][0], cave["roofed"][1])
	var fr: Array = cave["front"]
	cave_center = Vector2(fr[0], fr[2])
	cave_xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(fr[0], fr[1], fr[2]))


## Distance (x/z) from the floor of the grotto's rooms and passages: negative inside them.
func cave_edge(p: Vector2) -> float:
	if not _cave_rect.has_point(p):
		return 99.0
	var best := 99.0
	for c in cave_path:
		if c[3] < _cave_roofed.x or c[3] > _cave_roofed.y:
			continue
		var q: Vector3 = c[0]
		best = minf(best, Vector2(q.x, q.z).distance_to(p) - float(c[1]))
	return best


## Distance (x/z) from the middle of the way into, through and out of the grotto. Trunks, boulders
## and big bushes keep off it, so that both mouths stay open.
func cave_way(p: Vector2) -> float:
	if not _cave_rect.has_point(p):
		return 99.0
	var best := 99.0
	for q in _cave_way:
		best = minf(best, q.distance_to(p))
	return best


## Distance from the grotto as the placement code uses it (against CAVE_R): the boulders stand
## several meters deep around the rooms.
func cave_dist(p: Vector2) -> float:
	return cave_edge(p) + 1.5


## Is this point inside the grotto (under the boulders)?
func cave_inside(pos: Vector3) -> bool:
	if not _cave_rect.has_point(Vector2(pos.x, pos.z)):
		return false
	for c in cave_path:
		if c[3] < _cave_roofed.x or c[3] > _cave_roofed.y:
			continue
		var q: Vector3 = c[0]
		if Vector2(q.x, q.z).distance_to(Vector2(pos.x, pos.z)) < float(c[1]) + 0.3 and pos.y > q.y - 1.0 and pos.y < q.y + float(c[2]) + 0.5:
			return true
	return false


func build(world: Node3D) -> void:
	_world = world
	for c in get_children():
		c.free()
	_collide.clear()
	palm_trunks.clear()
	tree_spots.clear()
	boulder_spots.clear()
	_rng.seed = 1234
	_frng.seed = 4321
	_coco_spots.clear()
	_legacy_spots.clear()
	# (the height map is shared: scripts/heights.gd. In the editor it is read anew with
	# every rebuild: it may have been baked again)
	if Engine.is_editor_hint():
		Heights.read()
	var mt := load("res://assets/textures/landmask.png") as Texture2D
	_mask = mt.get_image() if mt else null
	if _mask and _mask.is_compressed():
		_mask.decompress()
	_load_island_data()
	_load_cave()

	var treeline := _collect("Treeline*", "L_Tree")
	var headland := _collect("Headland*", "L_Head")

	# --- second treeline continuing the beach to the north (leaves a gap for the trail)
	# (these copies were laid out along a straight coast; follow_coast moves them to where it is now)
	_place_group(treeline, Transform3D(Basis(), Vector3(-1.5, 0.15, 112.0)), "TreelineNorth", true, true, true)
	# --- and to the south beyond the headland
	_place_group(treeline, Transform3D(Basis(), Vector3(-6.0, 0.4, -150.0)), "TreelineSouth", true, true, true)
	# --- mirrored headland closing off the north end of the beach
	var mirror := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	_place_group(headland, Transform3D(mirror, Vector3(0.5, 0.2, 78.0)), "HeadlandNorth", true, true, true)

	# --- inland jungle layers: bushes scaled about their base so they sit on the ground
	var tl_pivot := Vector3(-14.0, 0.0, -18.0)
	for zoff in [-115.0, -5.0, 105.0, 205.0]:
		_place_group(treeline, _pivot_xf(tl_pivot, Vector3(-30.0, 0.0, zoff - 18.0), Vector3(1.2, 1.5, 1.0), 0.0), "JungleA", false, true, true)

	_palms()
	_forest()
	_endemic_palms()
	_mangroves()
	_bushes()
	_rocks()
	_stream()
	_tide_pools()
	_vacoas()
	_grotto()
	_grass()
	_ferns()
	_morning_glory()
	_islands(headland)
	_debris()
	if not Engine.is_editor_hint():
		_build_collision()


# ------------------------------------------------------------------ data helpers
func _load_island_data() -> void:
	var f := FileAccess.open("res://assets/models/island.json", FileAccess.READ)
	if f == null:
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	_trail.clear()
	for p in d["path"]:
		_trail.append(Vector2(p[0], p[1]))
	_peak = Vector2(d["peak"][0], d["peak"][1])
	_east_shore = d.get("east_shore", -168.0)
	_taper = d.get("taper", {})
	stream_course.clear()
	stream_pools.clear()
	_stream_rect = Rect2()
	var st: Dictionary = d.get("stream", {})
	for c in st.get("course", []):
		stream_course.append(Vector3(c[0], c[2], c[1]))
		var at := Vector2(c[0], c[1])
		_stream_rect = Rect2(at, Vector2.ZERO) if stream_course.size() == 1 else _stream_rect.expand(at)
	for c in st.get("pools", []):
		stream_pools.append({"at": Vector3(c[0], c[2], c[1]), "rx": float(c[3]), "rz": float(c[3]), "yaw": 0.0, "pond": false})
	if st.has("pond"):
		var c: Array = st["pond"]
		stream_pools.append({"at": Vector3(c[0], c[2], c[1]), "rx": float(c[3]), "rz": float(c[4]), "yaw": float(c[5]), "pond": true})
		_stream_rect = _stream_rect.expand(Vector2(c[0], c[1]))
	_stream_rect = _stream_rect.grow(14.0)


## The stream (island.json "stream", written by tools/terrain2.py): points along its bed from the
## seep down to the pond (x, bed height, z), about a meter apart, and its pools: the water level
## is the y of "at".
var stream_course := PackedVector3Array()
var stream_pools: Array = []
var _stream_rect := Rect2()


## Distance (x/z) from the stream's course or the edge of its pond; 99 when far from it.
func stream_dist(p: Vector2) -> float:
	if stream_course.is_empty() or not _stream_rect.has_point(p):
		return 99.0
	var best := 99.0
	for c in stream_course:
		best = minf(best, Vector2(c.x, c.z).distance_to(p))
	for pl in stream_pools:
		var o: Vector3 = pl["at"]
		best = minf(best, maxf(Vector2(o.x, o.z).distance_to(p) - maxf(pl["rx"], pl["rz"]), 0.0))
	return best


## How deep the water is at (x, z) now: negative on dry ground.
func depth(x: float, z: float) -> float:
	return sea - ground(x, z)


## Loose sand at p (the beaches, the floor of the grotto): where a foot leaves a print.
func sandy(p: Vector2) -> bool:
	if _mask == null:
		return ground(p.x, p.y) < 1.7
	var u := int(clampf((p.x + HM_EXT) / (2.0 * HM_EXT) * _mask.get_width(), 0, _mask.get_width() - 1))
	var v := int(clampf((p.y + HM_EXT) / (2.0 * HM_EXT) * _mask.get_height(), 0, _mask.get_height() - 1))
	var c := _mask.get_pixel(u, v)
	return c.r < 0.35 and c.g < 0.3 and c.b < 0.3 and c.a > 0.6


## Bare granite at p or within r of it (land mask g)?
func rocky(p: Vector2, r := 1.2) -> bool:
	if _mask == null:
		return false
	for k in 7:
		var q := p if k == 0 else p + Vector2(cos(k * 1.0472), sin(k * 1.0472)) * r
		var u := int(clampf((q.x + HM_EXT) / (2.0 * HM_EXT) * _mask.get_width(), 0, _mask.get_width() - 1))
		var v := int(clampf((q.y + HM_EXT) / (2.0 * HM_EXT) * _mask.get_height(), 0, _mask.get_height() - 1))
		if _mask.get_pixel(u, v).g > 0.3 and ground(q.x, q.y) > 0.0:
			return true
	return false


## How far (m) the west coast at z lies east of the straight line it follows along the start
## beach (the same as taper() in tools/terrain2.py).
func west_shift(z: float) -> float:
	if _taper.is_empty():
		return 0.0
	var r: float = _taper["r"]
	var s := 0.0
	var un: float = float(_taper["south"][0]) - z
	if un > 0.0:
		s += float(_taper["south"][1]) * (un - r * (1.0 - exp(-un / r)))
	var us: float = z - float(_taper["north"][0])
	if us > 0.0:
		s += float(_taper["north"][1]) * (us - r * (1.0 - exp(-us / r)))
	return s


## The rigid motion that carries the surroundings of c, a point on the straight west coast of the
## first terrain stage, to where the coast is now (moved east by west_shift and turned with it).
func _coast_xf(c: Vector3) -> Transform3D:
	var s := west_shift(c.z)
	if s < 0.01:
		return Transform3D()
	var turn := Basis(Vector3.UP, atan(-(west_shift(c.z + 1.0) - west_shift(c.z - 1.0)) * 0.5))
	return Transform3D(Basis(), Vector3(c.x - s, 0.0, c.z)) * Transform3D(turn, Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, 0.0, -c.z))


## The height of the terrain at (x, z), against the sea at 0 (beyond the map: its edge).
func ground(x: float, z: float) -> float:
	return Heights.ground(x, z)


## Land cover at x,z: r = forest floor, g = trail, b = open summit.
func cover(x: float, z: float) -> Color:
	if _mask == null:
		return Color(1, 0, 0)
	var u := int(clampf((x + HM_EXT) / (2.0 * HM_EXT) * _mask.get_width(), 0, _mask.get_width() - 1))
	var v := int(clampf((z + HM_EXT) / (2.0 * HM_EXT) * _mask.get_height(), 0, _mask.get_height() - 1))
	var c := _mask.get_pixel(u, v)
	# g on land is bare granite: nothing grows there
	if c.g > 0.3 and ground(x, z) > 0.0:
		var bare := 1.0 - smoothstep(0.3, 0.6, c.g)
		c.r *= bare
		c.b *= bare
	return c


func trail_distance(p: Vector2) -> float:
	var best := 1e9
	for i in _trail.size() - 1:
		var a := _trail[i]
		var b := _trail[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Places where tall vegetation must stay away: the trail, the open summit, water.
func blocked(x: float, z: float, trail_clear := 6.0, summit_clear := 48.0) -> bool:
	if trail_distance(Vector2(x, z)) < trail_clear:
		return true
	if Vector2(x, z).distance_to(_peak) < summit_clear:
		return true
	if cave_dist(Vector2(x, z)) < CAVE_R or cave_way(Vector2(x, z)) < 3.5:
		return true
	# nothing tall roots in bare granite or stands in the stream
	if rocky(Vector2(x, z)) or stream_dist(Vector2(x, z)) < 2.4:
		return true
	return ground(x, z) < 0.4


## Transform that scales/rotates a group about `pivot` (on the ground) and moves that
## pivot to `target` (whose height is taken from the terrain).
func _pivot_xf(pivot: Vector3, target: Vector3, scale_: Vector3, yaw: float) -> Transform3D:
	var p := Vector3(pivot.x, ground(pivot.x, pivot.z), pivot.z)
	var t := Vector3(target.x, ground(target.x, target.z) - 0.2, target.z)
	var b := Basis(Vector3.UP, yaw).scaled(scale_)
	return Transform3D(b, t) * Transform3D(Basis(), -p)


## Collects the body mesh plus matching leaf chunks (all LOD levels) into one list.
func _collect(body_pattern: String, prefix: String) -> Array:
	var out: Array = []
	var hills := _world.get_node_or_null("Hills")
	if hills:
		out.append_array(hills.find_children(body_pattern, "MeshInstance3D", true, false))
	for root_name in ["Leaves", "LeavesLod", "LeavesLod2"]:
		var r := _world.get_node_or_null(root_name)
		if r == null:
			continue
		out.append_array(r.find_children(prefix + "*", "MeshInstance3D", true, false))
	var lod := _world.get_node_or_null("LeavesLod/ShadowProxies")
	if lod:
		for sp in lod.get_children():
			var mi := sp as MeshInstance3D
			if mi and mi.mesh and mi.mesh.resource_name.begins_with(prefix):
				out.append(mi)
	return out


func _copy(src: GeometryInstance3D, xf: Transform3D, parent: Node3D, shadows: bool) -> MeshInstance3D:
	var s_mi := src as MeshInstance3D
	if s_mi == null:
		return null
	if not shadows and src.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return null
	var m := MeshInstance3D.new()
	m.mesh = s_mi.mesh
	for s in s_mi.mesh.get_surface_count():
		m.set_surface_override_material(s, s_mi.get_surface_override_material(s))
	m.material_override = s_mi.material_override
	m.visibility_range_begin = src.visibility_range_begin
	m.visibility_range_begin_margin = src.visibility_range_begin_margin
	m.visibility_range_end = src.visibility_range_end
	m.visibility_range_end_margin = src.visibility_range_end_margin
	m.cast_shadow = src.cast_shadow if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.global_transform = xf * src.global_transform
	return m


func _place_group(group: Array, xf: Transform3D, name_: String, shadows: bool, collide: bool, follow_coast := false) -> void:
	var parent := Node3D.new()
	parent.name = name_
	add_child(parent)
	var hills := _world.get_node("Hills")
	# leaf chunks (16 m blocks) that would cover the trail or the summit, or sit in the
	# sea, are left out. If any are, the group's solid inner body would show through
	# the gap, so it is left out too (the remaining leaves are dense enough on their own).
	var skip := {}
	var moved := {}   # each leaf chunk goes with the coast where it stands; the one long body cannot bend
	var bent := false
	for src in group:
		var center: Vector3 = xf * (src as MeshInstance3D).get_aabb().get_center()
		moved[src] = (_coast_xf(center) if follow_coast else Transform3D()) * xf
		if src.get_parent() == hills:
			var ab: AABB = xf * (src as MeshInstance3D).get_aabb()
			var mid := west_shift(center.z)
			bent = follow_coast and maxf(absf(west_shift(ab.position.z) - mid), absf(west_shift(ab.end.z) - mid)) > 0.75
			continue
		center = moved[src] * (src as MeshInstance3D).get_aabb().get_center()
		if blocked(center.x, center.z, 9.0, 45.0):
			skip[src] = true
	for src in group:
		var is_body: bool = src.get_parent() == hills
		if skip.has(src) or (is_body and (bent or not skip.is_empty())):
			continue
		var m := _copy(src, moved[src], parent, shadows)
		if m == null:
			continue
		if collide and is_body:
			# (the body is drawn smaller than it is since it was turned right side out:
			# world.gd, _right_side_out(); what counts as "in the bushes" keeps its size)
			var whole: Mesh = (src.get_meta("solid") as Mesh) if src.has_meta("solid") else (src as MeshInstance3D).mesh
			_collide.append([whole, m.global_transform, true])


# ------------------------------------------------------------------ palms
func _palm_sources() -> Array:
	var out: Array = []
	var palms_root := _world.get_node_or_null("Palms")
	if palms_root == null:
		return out
	for i in range(0, 7):
		var p := palms_root.get_node_or_null("Palm%d" % i) as Node3D
		if p == null:
			continue
		var trunk := p.find_child("Trunk*", false, false) as MeshInstance3D
		var crown := p.find_child("Crown*", false, false) as Node3D
		if trunk == null or crown == null:
			continue
		var aabb := trunk.get_aabb()
		# the trunk base is the lowest ring of vertices
		var base := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		var arr := trunk.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var acc := Vector3.ZERO
		var n := 0
		for v in verts:
			if v.y < aabb.position.y + 0.25:
				acc += v
				n += 1
		if n > 0:
			base = acc / n
		var lean := crown.position - base
		lean.y = 0.0
		var line := _trunk_line(verts, aabb)
		var tp := PackedVector3Array()
		for v in line[0]:
			tp.append(trunk.transform * v)   # trunk mesh space -> palm space
		line[0] = tp
		# the bottom ring of the trunk (cut square to the trunk, so tilted on a leaning palm): it
		# has to end up fully below the ground wherever the palm is planted
		var axis: Vector3 = ((line[0] as PackedVector3Array)[1] - (line[0] as PackedVector3Array)[0]).normalized()
		# (the 14 vertices furthest down the trunk axis; the axis from the ring centers is only
		# approximate on a strongly bent trunk, so take a few more vertices close to that ring)
		var proj: Array = []
		for v in verts:
			var pv: Vector3 = trunk.transform * v
			proj.append([pv.dot(axis), pv])
		proj.sort_custom(func(u, w): return u[0] < w[0])
		var lim: float = proj[mini(13, proj.size() - 1)][0] + 0.03
		var ring := PackedVector3Array()
		for e in proj:
			if e[0] > lim:
				break
			ring.append(e[1])
		out.append({"node": p, "trunk": trunk, "base": base, "lean": lean, "line": line, "ring": ring})
		# the original palms by the start beach take part too (geckos climb them)
		_add_trunk(p.global_transform, line)
	return out


## Center line of a palm trunk (in the palm's own space): ring centers and radii, base to crown.
func _trunk_line(verts: PackedVector3Array, aabb: AABB) -> Array:
	var n := 10
	var sums: Array = []
	var cnt: Array = []
	for i in n:
		sums.append(Vector3.ZERO)
		cnt.append(0)
	for v in verts:
		var i := clampi(int((v.y - aabb.position.y) / aabb.size.y * n), 0, n - 1)
		sums[i] += v
		cnt[i] += 1
	var pts := PackedVector3Array()
	var idx_of: Array = []
	for i in n:
		idx_of.append(pts.size() if cnt[i] > 0 else -1)
		if cnt[i] > 0:
			pts.append(sums[i] / cnt[i])
	# mean distance from the ring center (a leaning ring's horizontal extent would overestimate)
	var rad := PackedFloat32Array()
	rad.resize(pts.size())
	var rc := PackedInt32Array()
	rc.resize(pts.size())
	for v in verts:
		var i: int = idx_of[clampi(int((v.y - aabb.position.y) / aabb.size.y * n), 0, n - 1)]
		if i >= 0:
			var ax := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var d := v - pts[i]
			rad[i] += (d - ax * d.dot(ax)).length()
			rc[i] += 1
	for i in rad.size():
		rad[i] /= maxf(rc[i], 1)
	return [pts, rad]


func _add_trunk(xf: Transform3D, line: Array) -> void:
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var sc := xf.basis.get_scale().x
	for i in (line[0] as PackedVector3Array).size():
		pts.append(xf * line[0][i])
		rad.append(line[1][i] * sc * 0.9)
	palm_trunks.append({"pts": pts, "r": rad})


func _place_palm(src: Dictionary, parent: Node3D, at: Vector2, lean_toward: Vector2, scale_: float, collide: bool) -> void:
	var lean: Vector3 = src["lean"]
	var yaw := 0.0
	if lean_toward.length() > 0.01 and lean.length() > 0.3:
		# rotate the palm so its natural lean points the way we want (e.g. out over the sea)
		var have := atan2(lean.x, lean.z)
		var want := atan2(lean_toward.x, lean_toward.y)
		yaw = want - have + _rng.randf_range(-0.35, 0.35)
	else:
		yaw = _rng.randf() * TAU
	var base: Vector3 = src["base"]
	var target := Vector3(at.x, ground(at.x, at.y) - 0.35, at.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_), target) * Transform3D(Basis(), -base)
	# sink the palm until its whole bottom ring is at least 25 cm under the ground (slopes, lean)
	var rise := -INF
	for v in src["ring"]:
		var wv: Vector3 = xf * v
		rise = maxf(rise, wv.y - ground(wv.x, wv.z) + 0.25 * scale_)
	if rise > 0.0:
		xf.origin.y -= rise
	var copy := (src["node"] as Node3D).duplicate() as Node3D
	parent.add_child(copy)
	copy.transform = xf
	_world._apply_materials(copy)
	_add_trunk(copy.global_transform, src["line"])
	if collide:
		var trunk: MeshInstance3D = src["trunk"]
		_collide.append([trunk.mesh, copy.global_transform * trunk.transform])


func _palms() -> void:
	var srcs := _palm_sources()
	if srcs.is_empty():
		return
	var parent := Node3D.new()
	parent.name = "Palms"
	add_child(parent)
	# a few more on the west beach edge north and south of the start
	for z in [52.0, 59.0, 66.0, 74.0, 81.0, 88.0, 96.0, 103.0, 110.0, -122.0, -130.0, -138.0, -154.0, -170.0, -180.0, -190.0]:
		var p := Vector2(_rng.randf_range(-16.0, -9.0) - west_shift(z), z + _rng.randf_range(-3, 3))
		if ground(p.x, p.y) > 0.6 and not blocked(p.x, p.y, 4.0, 0.0):
			_place_palm(srcs[_rng.randi() % srcs.size()], parent, p, Vector2(1, 0), _rng.randf_range(1.0, 1.25), true)
	# between the original palms of the start beach: a few more, some of them young
	var crowns: Array = []
	for s in srcs:
		var cn := (s["node"] as Node3D).find_child("Crown*", false, false) as Node3D
		var g := cn.global_position if cn else (s["node"] as Node3D).global_position
		crowns.append(Vector2(g.x, g.z))
	for z in [-48.0, -36.0, -24.0, -14.0, 4.0, 18.0, 31.0, 44.0]:
		var p := Vector2(_rng.randf_range(-17.0, -11.0), z + _rng.randf_range(-3, 3))
		var free := true
		for c in crowns:
			if (c as Vector2).distance_to(p) < 6.0:
				free = false
		if free and ground(p.x, p.y) > 0.6 and not blocked(p.x, p.y, 4.0, 0.0):
			var young := _rng.randf() < 0.4
			_place_palm(srcs[_rng.randi() % srcs.size()], parent, p, Vector2(1, 0),
				_rng.randf_range(0.42, 0.62) if young else _rng.randf_range(0.95, 1.2), true)
			crowns.append(p)
	# every shore: walk around the coastline and plant coconut palms leaning out over the water
	var z := -215.0
	while z < 215.0:
		for side in [-1, 1]:
			if side == 1 and absf(z) < 140.0:
				continue   # the west beach already has its palms
			var sx := _shore_scan(z, side)
			if is_nan(sx):
				continue
			var inland := 3.0 + _rng.randf_range(0.0, 9.0)
			var p := Vector2(sx - side * inland, z + _rng.randf_range(-2.0, 2.0))
			if ground(p.x, p.y) < 0.5 or blocked(p.x, p.y, 4.0, 0.0):
				continue
			_place_palm(srcs[_rng.randi() % srcs.size()], parent, p, Vector2(side, 0), _rng.randf_range(1.0, 1.35), true)
			# palms often grow in clumps: sometimes a second, often younger one close by
			if _rng.randf() < 0.35:
				var q := p + Vector2(-side * _rng.randf_range(2.5, 5.0), _rng.randf_range(-3.0, 3.0))
				if ground(q.x, q.y) > 0.5 and not blocked(q.x, q.y, 4.0, 0.0):
					_place_palm(srcs[_rng.randi() % srcs.size()], parent, q, Vector2(side, _rng.randf_range(-0.5, 0.5)),
						_rng.randf_range(0.45, 0.8), true)
		z += _rng.randf_range(5.0, 9.5)
	# along the south and north tips the shore runs west-east
	for side in [-1, 1]:
		var x := -175.0
		while x < -5.0:
			var sz := _shore_scan_z(x, side)
			if not is_nan(sz):
				var p := Vector2(x + _rng.randf_range(-2, 2), sz - side * (3.0 + _rng.randf_range(0.0, 8.0)))
				if ground(p.x, p.y) > 0.5 and not blocked(p.x, p.y, 4.0, 0.0):
					_place_palm(srcs[_rng.randi() % srcs.size()], parent, p, Vector2(0, side), _rng.randf_range(1.0, 1.3), true)
			x += _rng.randf_range(5.5, 10.0)
	# inland grove rising above the bushes
	for i in 70:
		var p := Vector2(_rng.randf_range(-150.0, -22.0), _rng.randf_range(-200.0, 200.0))
		if ground(p.x, p.y) < 1.2 or cover(p.x, p.y).r < 0.5 or blocked(p.x, p.y, 5.0, 40.0):
			continue
		_place_palm(srcs[_rng.randi() % srcs.size()], parent, p, Vector2.ZERO, _rng.randf_range(1.2, 1.7), true)


## x of the shoreline at z, scanning from the sea inward (side = 1 west, -1 east).
func _shore_scan(z: float, side: int) -> float:
	var x := 60.0 if side == 1 else -200.0
	for i in 600:
		if ground(x, z) > 0.0:
			return x
		x -= 0.5 * side
	return NAN


## z of the shoreline at x, scanning from the sea inward (side = 1 north, -1 south).
func _shore_scan_z(x: float, side: int) -> float:
	var z := 262.0 if side == 1 else -262.0
	for i in 400:
		if ground(x, z) > 0.0:
			return z
		z -= 0.5 * side
	return NAN


# ------------------------------------------------------------------ forest
## Lowest ground in a small ring around a point: trunks and rocks are seated there so
## no part of their base hangs in the air on a slope.
func ground_min(x: float, z: float, r: float) -> float:
	var h := ground(x, z)
	for k in 8:
		var a := TAU * k / 8.0
		h = minf(h, ground(x + cos(a) * r, z + sin(a) * r))
	return h


func _forest() -> void:
	# takamaka canopy for the original trunks by the start beach
	var canopy_scene := load("res://assets/models/takamaka_canopy.glb") as PackedScene
	var canopy_lod_scene := load("res://assets/models/takamaka_canopy_lod.glb") as PackedScene
	if canopy_scene:
		var c := canopy_scene.instantiate()
		c.name = "TakamakaCanopy"
		add_child(c)
		_world._apply_materials(c)
		for m in c.find_children("*", "MeshInstance3D", true, false):
			m.visibility_range_end = 40.0
			m.visibility_range_end_margin = 4.0
	if canopy_lod_scene:
		var c2 := canopy_lod_scene.instantiate()
		c2.name = "TakamakaCanopyLod"
		add_child(c2)
		_world._apply_materials(c2)
		for m in c2.find_children("*", "MeshInstance3D", true, false):
			if (m.name as String).ends_with("lod2"):
				m.visibility_range_begin = 110.0
				m.visibility_range_begin_margin = 6.0
			else:
				m.visibility_range_begin = 40.0
				m.visibility_range_begin_margin = 4.0
				m.visibility_range_end = 110.0
				m.visibility_range_end_margin = 6.0
	# individual broadleaf trees (modeled with roots below ground) across the interior
	var scene := load("res://assets/models/trees.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	var parts := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		parts[m.name] = (m as MeshInstance3D).mesh
	tmp.free()
	# jackfruit trees grow among them
	var jscene := load("res://assets/models/jackfruit.glb") as PackedScene
	if jscene:
		var jt := jscene.instantiate()
		for m in jt.find_children("*", "MeshInstance3D", true, false):
			parts[m.name] = (m as MeshInstance3D).mesh
		jt.free()
	# the forest proper: takamaka and badamier grown branch by branch, and the screwpines (_vacoas)
	var fscene := load("res://assets/models/forest_trees.glb") as PackedScene
	if fscene:
		var ft := fscene.instantiate()
		for m in ft.find_children("*", "MeshInstance3D", true, false):
			parts[m.name] = (m as MeshInstance3D).mesh
		ft.free()
	# ... and the Pisonia trees of the seabird colony's grove
	var pscene := load("res://assets/models/pisonia.glb") as PackedScene
	if pscene:
		var pt := pscene.instantiate()
		for m in pt.find_children("*", "MeshInstance3D", true, false):
			parts[m.name] = (m as MeshInstance3D).mesh
		pt.free()
	_tree_parts = parts
	var forest := Node3D.new()
	forest.name = "Forest"
	add_child(forest)
	_bark_cells.clear()
	for key in parts:
		if (key as String).ends_with("Bark"):
			_bark_cells[key] = _point_cells((parts[key] as Mesh).get_faces())
	var gz := -215.0
	while gz < 215.0:
		var gx := -34.0
		while gx > -178.0:
			var x := gx + _rng.randf_range(-5.0, 5.0)
			var z := gz + _rng.randf_range(-5.0, 5.0)
			gx -= _rng.randf_range(10.0, 15.0)
			if ground(x, z) < 1.4 or cover(x, z).r < 0.7 or blocked(x, z, 7.0, 46.0):
				continue
			if Vector2(x, z).distance_to(colony_center) < COLONY_R:
				continue   # the colony grove is planted separately
			var pick := _rng.randi() % 5
			var kind := "Tree%d" % pick
			if parts.has("Taka0Bark"):
				# badamier keeps to the lowland and the coast; the hill forest is takamaka
				kind = ["Taka0", "Bad0", "Taka1", "Bad1", "Taka2"][pick]
				if kind.begins_with("Bad") and ground(x, z) > 9.0:
					kind = "Taka%d" % (pick % 3)
				elif pick == 4 and ground(x, z) < 4.0:
					kind = "Bad2"
			var sc := _rng.randf_range(0.85, 1.25)
			if _rng.randf() < 0.17 and parts.has("Jack0Bark"):
				kind = "Jack%d" % (_rng.randi() % 3)
				sc = _rng.randf_range(0.85, 1.1)
			_plant_tree(forest, parts, kind, sc, x, z, x > -80.0, null, false, "Tree%d" % pick if kind.begins_with("Taka") or kind.begins_with("Bad") else "")
		gz += _rng.randf_range(9.0, 14.0)
	# Pisonia grove for the seabird colony: paler, softer canopies, nests in them (colony.gd)
	var pis: Material = _world.get_material("PisoniaLeaf")
	var placed: Array = []
	for i in 80:
		if placed.size() >= 15:
			break
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * COLONY_R * 0.9
		var q := colony_center + Vector2(cos(a), sin(a)) * r
		if ground(q.x, q.y) < 1.0 or blocked(q.x, q.y, 7.0, 46.0):
			continue
		var ok := true
		for o in placed:
			if (o as Vector2).distance_to(q) < 7.5:
				ok = false
		if not ok:
			continue
		placed.append(q)
		# (Pisonia grown branch by branch: tools/assets7.py: pisonia(); the stand-in each one has
		# replaced is passed on so that everything placed after the forest stays where it was)
		var pick := _rng.randi() % 3
		var psc := _rng.randf_range(0.8, 1.05)
		if parts.has("Pis0Bark"):
			_plant_tree(forest, parts, "Pis%d" % pick, psc, q.x, q.y, true, null, true, "Tree%d" % [0, 1, 4][pick])
		else:
			_plant_tree(forest, parts, "Tree%d" % [0, 1, 4][pick], psc, q.x, q.y, true, pis, true)


## `legacy`: the stand-in tree kind (trees.glb) this tree has replaced. Whether THAT one would have
## been planted here is what the placement of everything after the forest was rolled against
## (_legacy_spots): keeping to it leaves palms, bushes, rocks and mangroves exactly where they were.
func _plant_tree(forest: Node3D, parts: Dictionary, kind: String, sc: float, x: float, z: float, near_beach: bool,
		leaf_mat: Material, colony := false, legacy := "") -> void:
	var y := ground_min(x, z, 1.4 * sc) - 0.15
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, y, z))
	if not _hits_palm(xf, "%sBark" % (legacy if legacy != "" else kind)):
		_legacy_spots.append(Vector2(x, z))
	if _hits_palm(xf, "%sBark" % kind):
		return   # a (leaning) palm trunk would run through this tree's trunk or branches
	tree_spots.append({"xf": xf, "kind": kind, "colony": colony})
	for part in [["Bark", 0.0, 0.0], ["Twigs", 0.0, 60.0], ["Fruit", 0.0, 75.0], ["Leaves", 0.0, 32.0], ["Leaves_lod", 32.0, 85.0], ["Leaves_lod2", 85.0, 0.0]]:
		var key := "%s%s" % [kind, part[0]]
		if not parts.has(key):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = parts[key]
		mi.visibility_range_begin = part[1]
		mi.visibility_range_end = part[2]
		# (no hysteresis margins: in the overlap band both LODs of a crown could be hidden at once)
		if part[0] == "Leaves" or part[0] == "Leaves_lod2" or part[0] == "Twigs" or not near_beach:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		forest.add_child(mi)
		mi.global_transform = xf
		_world._apply_materials(mi)
		if leaf_mat and (part[0] as String).begins_with("Leaves"):
			mi.set_surface_override_material(0, leaf_mat)
		if part[0] == "Bark":
			_collide.append([mi.mesh, xf])
	# the dense near canopy skips the shadow pass; its sparse LOD casts the shade
	var sk := "%sLeaves_lod" % kind
	if parts.has(sk) and near_beach:
		var sp := MeshInstance3D.new()
		sp.mesh = parts[sk]
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sp.visibility_range_end = 32.0
		forest.add_child(sp)
		sp.global_transform = xf
		_world._apply_materials(sp)


## Bark vertices of each tree kind, bucketed in 2 m cells (tree space), for the palm test.
var _bark_cells := {}
var _tree_parts := {}   # mesh name -> Mesh (trees.glb, jackfruit.glb, forest_trees.glb)
var _legacy_spots: Array = []   # Vector2: see _plant_tree

func _point_cells(pts: PackedVector3Array) -> Dictionary:
	var cells := {}
	var seen := {}
	for v in pts:
		if seen.has(v):
			continue   # (get_faces() lists every vertex once per triangle)
		seen[v] = true
		var c := Vector3i(floori(v.x * 0.5), floori(v.y * 0.5), floori(v.z * 0.5))
		if not cells.has(c):
			cells[c] = []   # a plain Array (by reference); a packed array would be appended as a copy
		(cells[c] as Array).append(v)
	return cells


## True if any palm trunk passes within a meter of the tree's bark (trunk or branches).
func _hits_palm(xf: Transform3D, bark: String) -> bool:
	var cells: Dictionary = _bark_cells.get(bark, {})
	if cells.is_empty():
		return false
	var inv := xf.affine_inverse()
	var sc := xf.basis.get_scale().x
	for t in palm_trunks:
		var pts: PackedVector3Array = t["pts"]
		if Vector2(pts[0].x - xf.origin.x, pts[0].z - xf.origin.z).length() > 30.0:
			continue
		var rad: PackedFloat32Array = t["r"]
		for i in pts.size() - 1:
			var n := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / 0.3))
			for j in n + 1:
				var f := float(j) / n
				var q: Vector3 = inv * pts[i].lerp(pts[i + 1], f)
				var lim: float = (lerpf(rad[i], rad[i + 1], f) + 1.0) / sc
				var c := Vector3i(floori(q.x * 0.5), floori(q.y * 0.5), floori(q.z * 0.5))
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						for dz in range(-1, 2):
							var cell: Variant = cells.get(c + Vector3i(dx, dy, dz))
							if cell == null:
								continue
							for v: Vector3 in cell:
								if v.distance_to(q) < lim:
									return true
	return false


# ------------------------------------------------------------------ bush clusters
var _interior_mat: Material

## The bush body seen through gaps in the leaves: the same leafy pattern, but in the
## shade of the canopy, so at a distance it reads as depth instead of a solid lump.
func _bush_interior() -> Material:
	if _interior_mat == null:
		var src := _world.get_material("BushGreen") as StandardMaterial3D
		var m := src.duplicate() as StandardMaterial3D
		m.albedo_color = Color(0.5, 0.58, 0.45)
		m.backlight_enabled = false
		m.roughness = 1.0
		_interior_mat = m
	return _interior_mat

func _pick(options: Array) -> String:
	return options[_rng.randi() % options.size()]


func _bushes() -> void:
	var scene := load("res://assets/models/bushes.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	var parts := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		parts[m.name] = (m as MeshInstance3D).mesh
	tmp.free()
	var parent := Node3D.new()
	parent.name = "BushClusters"
	add_child(parent)
	var spots: Array = []   # [pos, kind, scale]
	# vegetation line behind every non-west shore
	var z := -210.0
	while z < 210.0:
		var sx := _shore_scan(z, -1)
		if not is_nan(sx):
			for k in 2:
				var p := Vector2(sx + _rng.randf_range(14.0, 30.0), z + _rng.randf_range(-3, 3))
				spots.append([p, _pick(["A", "A", "E", "F", "C", "B"]), _rng.randf_range(0.8, 1.4)])
			# beach naupaka and Pemphis right at the top of the beach
			if _rng.randf() < 0.55:
				var p := Vector2(sx + _rng.randf_range(7.0, 13.0), z + _rng.randf_range(-3, 3))
				spots.append([p, _pick(["A", "E", "F"]), _rng.randf_range(0.7, 1.2)])
		z += _rng.randf_range(5.0, 9.0)
	# the start beach: a ragged fringe of shrubs in front of the original treeline,
	# so its edge is no longer one continuous wall of foliage
	z = -60.0
	while z < 125.0:
		var sx := _shore_scan(z, 1)
		if not is_nan(sx) and not (z > 30.0 and z < 50.0):   # keep the opening to the ridge free
			var p := Vector2(sx - _rng.randf_range(13.0, 18.0), z + _rng.randf_range(-2, 2))
			if ground(p.x, p.y) > 0.9:
				spots.append([p, _pick(["A", "A", "F", "E", "C"]), _rng.randf_range(0.65, 1.15)])
		z += _rng.randf_range(4.0, 11.0)
	# low shrubs around the open summit and along the trail
	for i in 110:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(14.0, 55.0)
		spots.append([_peak + Vector2(cos(a), sin(a)) * r, _pick(["C", "C", "E", "F"]), _rng.randf_range(0.6, 1.1)])
	# denser scrub further down the hill slopes (the summit itself stays open)
	for i in 170:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, 85.0)
		var p := _peak + Vector2(cos(a), sin(a)) * r
		if cave_dist(p) < CAVE_R + 1.0:
			continue
		spots.append([p, _pick(["C", "E", "F", "A", "B", "D"]), _rng.randf_range(0.7, 1.3)])
	for i in _trail.size() - 1:
		var a := _trail[i]
		var b := _trail[i + 1]
		var n := int(a.distance_to(b) / 7.0)
		for j in n:
			var p := a.lerp(b, (j + 0.5) / maxf(n, 1))
			var nrm := Vector2(-(b - a).y, (b - a).x).normalized()
			var side := 1.0 if _rng.randf() > 0.5 else -1.0
			spots.append([p + nrm * side * _rng.randf_range(3.5, 6.0), _pick(["A", "C", "F", "E"]), _rng.randf_range(0.6, 1.0)])
	# understory in the forest
	for i in 160:
		var p := Vector2(_rng.randf_range(-170.0, -30.0), _rng.randf_range(-210.0, 210.0))
		if cover(p.x, p.y).r > 0.7 and not blocked(p.x, p.y, 4.0, 15.0):
			spots.append([p, _pick(["B", "B", "D", "D", "C"]), _rng.randf_range(0.8, 1.4)])
	for s in spots:
		var p: Vector2 = s[0]
		var h := ground(p.x, p.y)
		if h < 0.5 or trail_distance(p) < 2.8 or cave_dist(p) < CAVE_R - 1.5 or cave_way(p) < 3.0:
			continue
		if rocky(p, 0.9) or stream_dist(p) < 1.2:
			continue   # (no shrub roots in a bare slab, or stands in the stream)
		var kind: String = s[1]
		var sc: float = s[2]
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * _rng.randf_range(0.85, 1.15), sc)), Vector3(p.x, ground_min(p.x, p.y, 0.7 * sc) - 0.08 * sc, p.y))
		# the hull (the bush's inner volume) is only drawn far away, where the sparse LOD leaves need
		# some body behind them; close up it would show through the gaps as a dark solid blob, so
		# there it only casts the shadow. Hand-overs have no margins (no gaps in the overlap band).
		for part in [["Hull", 28.0, 0.0], ["HullShadow", 0.0, 28.0], ["Twigs", 0.0, 24.0], ["Leaves", 0.0, 26.0],
				["Leaves_lod", 26.0, 70.0], ["Leaves_lod2", 70.0, 0.0]]:
			var is_hull: bool = (part[0] as String).begins_with("Hull")
			var key := "Bush%s%s" % [kind, "Hull" if is_hull else part[0]]
			if not parts.has(key):
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = parts[key]
			mi.visibility_range_begin = part[1]
			mi.visibility_range_end = part[2]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part[0] in ["Leaves", "Leaves_lod2", "Twigs"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if part[0] == "HullShadow":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			parent.add_child(mi)
			mi.global_transform = xf
			if is_hull:
				mi.global_transform = xf * Transform3D(Basis().scaled(Vector3(0.86, 0.86, 0.86)), Vector3.ZERO)
			_world._apply_materials(mi)
			if is_hull:
				mi.material_override = _bush_interior()
			if part[0] == "Hull":
				_collide.append([mi.mesh, xf, true])


# ------------------------------------------------------------------ summit grass
func _grass_clump_mesh(seed_: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	for b in 16:
		var ang := r.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var base := dir * r.randf_range(0.0, 0.1)
		var h := r.randf_range(0.12, 0.42)
		var tilt := r.randf_range(0.1, 0.6)
		# two segments so the blade arcs over
		var mid := base + dir * h * tilt * 0.35 + Vector3(0, h * 0.6, 0)
		var tip := base + dir * h * tilt + Vector3(0, h * (1.0 - tilt * 0.3), 0)
		var side := Vector3(-dir.z, 0, dir.x) * r.randf_range(0.008, 0.016)
		var c := Color(r.randf(), 0, 0)
		var n := (Vector3.UP * 2.0 + dir).normalized()
		var verts := [[base - side, Vector2(0, 0)], [base + side, Vector2(1, 0)],
			[mid + side * 0.8, Vector2(1, 0.6)], [mid - side * 0.8, Vector2(0, 0.6)],
			[tip + side * 0.15, Vector2(1, 1)], [tip - side * 0.15, Vector2(0, 1)]]
		for idx in [0, 1, 2, 0, 2, 3, 3, 2, 4, 3, 4, 5]:
			st.set_color(c)
			st.set_normal(n)
			st.set_uv(verts[idx][1])
			st.add_vertex(verts[idx][0])
	st.generate_tangents()
	return st.commit()


func _grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/leaf.gdshader")
	mat.set_shader_parameter("color_a", Color(0.15, 0.24, 0.05))
	mat.set_shader_parameter("color_b", Color(0.36, 0.40, 0.13))
	mat.set_shader_parameter("backlight_color", Color(0.18, 0.24, 0.05))
	mat.set_shader_parameter("specular_amount", 0.15)
	mat.set_shader_parameter("shape_width", 0.5)
	mat.set_shader_parameter("shape_power", 0.05)
	mat.set_shader_parameter("vein", 0.0)
	mat.set_shader_parameter("hue_var", 0.45)
	mat.set_shader_parameter("blade", 1.0)
	mat.set_shader_parameter("flutter", 0.015)
	mat.set_shader_parameter("sway", 0.04)
	mat.set_shader_parameter("roughness", 0.95)
	var meshes := [_grass_clump_mesh(99), _grass_clump_mesh(7), _grass_clump_mesh(321)]
	# chunks of 24 m so only the grass around the player is drawn
	var chunks := {}   # Vector3i(cx, cz, mesh) -> Array[Transform3D]
	var tries := 0
	var placed := 0
	while placed < 30000 and tries < 120000:
		tries += 1
		var p := Vector2.ZERO
		var on_slope := _rng.randf() < 0.35
		if on_slope and _trail.size() > 1:
			# the open grassy slope that leads up to the summit
			var i := _rng.randi() % (_trail.size() - 1)
			var q := _trail[i].lerp(_trail[i + 1], _rng.randf())
			p = q + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-7, 7))
			if ground(p.x, p.y) < 2.0 or cover(p.x, p.y).b < 0.35 + _rng.randf() * 0.4:
				continue
		else:
			var a := _rng.randf() * TAU
			p = _peak + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * 70.0
			if cover(p.x, p.y).b < 0.35 + _rng.randf() * 0.4:
				continue
		if cave_dist(p) < CAVE_R:
			continue
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1, _rng.randf_range(0.7, 1.4), 1) * _rng.randf_range(0.8, 1.3))
		var key := Vector3i(int(floorf(p.x / 24.0)), int(floorf(p.y / 24.0)), placed % 3)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(Transform3D(b, Vector3(p.x, ground(p.x, p.y) - 0.02, p.y)))
		placed += 1
	var parent := Node3D.new()
	parent.name = "Grass"
	add_child(parent)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.z]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 48.0
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		parent.add_child(mmi)


# ------------------------------------------------------------------ endemic palms
var _epalm_parts := {}

## Coco de mer, latanier feuille and palmiste (the Seychelles' own palms) on the hill slopes
## and through the forest. The summit (24 m around the lookout) stays open.
func _endemic_palms() -> void:
	var scene := load("res://assets/models/endemic_palms.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		_epalm_parts[m.name] = [(m as MeshInstance3D).mesh, (m as Node3D).transform]
	tmp.free()
	var parent := Node3D.new()
	parent.name = "EndemicPalms"
	add_child(parent)
	var placed: Array = []
	# hill slopes: only the shorter lataniers high up, so the view from the lookout stays free
	var n := 0
	var tries := 0
	while n < 75 and tries < 3000:
		tries += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, 90.0)
		var p := _peak + Vector2(cos(a), sin(a)) * r
		if not _epalm_ok(p, placed, 4.5):
			continue
		var kind := _pick(["LatA", "LatB", "LatB"]) if r < 45.0 else _pick(["LatA", "LatB", "CocoA", "CocoB", "PalmA", "PalmB"])
		_plant_epalm(parent, kind, p)
		placed.append(p)
		n += 1
	# forest: latanier in the understorey, palmiste rising above the canopy, coco de mer groves
	n = 0
	tries = 0
	while n < 110 and tries < 4000:
		tries += 1
		var p := Vector2(_rng.randf_range(-172.0, -28.0), _rng.randf_range(-205.0, 205.0))
		if cover(p.x, p.y).r < 0.6 or not _epalm_ok(p, placed, 5.0):
			continue
		var kind := _pick(["LatA", "LatB", "LatA", "CocoA", "CocoB", "PalmA", "PalmB"])
		_plant_epalm(parent, kind, p)
		placed.append(p)
		n += 1
		# coco de mer grow in groves: a few more close by
		if kind.begins_with("Coco"):
			for k in _rng.randi_range(1, 4):
				var q := p + Vector2(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9))
				if _epalm_ok(q, placed, 4.0):
					_plant_epalm(parent, _pick(["CocoA", "CocoB"]), q)
					placed.append(q)
	_coco_extras(parent, placed)


## Around the coco de mer: young palms that have no trunk yet (enormous fans on long stalks straight
## from the ground), and under the female palms the fallen nuts: a fruit still in its husk here and
## there, mostly the bare dark double nut the husk has rotted away from.
func _coco_extras(parent: Node3D, placed: Array) -> void:
	var seeds: Array = []
	var fruits: Array = []
	for spot in _coco_spots.duplicate():
		var c: Vector2 = spot[0]
		for k in _frng.randi_range(0, 2):
			var a := _frng.randf() * TAU
			var q := c + Vector2(cos(a), sin(a)) * _frng.randf_range(3.0, 8.0)
			var free := _epalm_ok(q, placed, 2.6)
			for pt in palm_trunks:   # its fans must not wrap around a coconut palm
				var pb: Vector3 = pt["pts"][0]
				if Vector2(pb.x, pb.z).distance_to(q) < 3.5:
					free = false
			if free:
				_plant_epalm(parent, "CocoJ%d" % (_frng.randi() % 2), q, _frng)
				placed.append(q)
		if spot[1] != "CocoB":
			continue
		for k in _frng.randi_range(1, 3):
			var a := _frng.randf() * TAU
			var q := c + Vector2(cos(a), sin(a)) * _frng.randf_range(0.7, 3.2)
			if ground(q.x, q.y) < 0.8 or cave_dist(q) < CAVE_R:
				continue
			var sc := _frng.randf_range(0.85, 1.1)
			var old := _frng.randf() < 0.22
			var n := Vector3(ground(q.x - 0.3, q.y) - ground(q.x + 0.3, q.y), 0.6, ground(q.x, q.y - 0.3) - ground(q.x, q.y + 0.3)).normalized()
			# lying on one of its flat faces (the model stands on end: stalk end up, lobes side by side)
			var b := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, _frng.randf() * TAU) \
				* Basis(Vector3.RIGHT, (PI / 2.0 if _frng.randf() < 0.5 else -PI / 2.0) + _frng.randf_range(-0.2, 0.2))
			var lift := (0.11 if old else 0.07) * sc
			(fruits if old else seeds).append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(q.x, ground(q.x, q.y), q.y) + n * lift))
	for pair in [["CocoSeed", seeds], ["CocoFruitOld", fruits]]:
		if not _epalm_parts.has(pair[0]) or (pair[1] as Array).is_empty():
			continue
		var mesh: Mesh = _epalm_parts[pair[0]][0]
		_multimesh(parent, mesh, pair[1], true)
		var mmi := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
		mmi.name = pair[0]
		var src := mesh.surface_get_material(0)
		if src and _world.get_material(src.resource_name):
			mmi.material_override = _world.get_material(src.resource_name)


func _epalm_ok(p: Vector2, placed: Array, spacing: float) -> bool:
	if ground(p.x, p.y) < 1.2 or blocked(p.x, p.y, 5.0, 24.0):
		return false
	for q in placed:
		if (q as Vector2).distance_to(p) < spacing:
			return false
	for o: Vector2 in _legacy_spots:
		if o.distance_to(p) < 3.5:
			return false
	return true


## True if a palm standing at p (trunk `height` meters tall) would run through the trunk or a limb
## of a forest tree.
func _palm_hits_tree(p: Vector2, height: float) -> bool:
	var y0 := ground(p.x, p.y)
	for t in tree_spots:
		var xf: Transform3D = t["xf"]
		var d := Vector2(xf.origin.x, xf.origin.z).distance_to(p)
		if d > 13.0:
			continue
		if d < 3.5:
			return true
		var cells: Dictionary = _bark_cells.get("%sBark" % t["kind"], {})
		var inv := xf.affine_inverse()
		var lim: float = 0.75 / xf.basis.get_scale().x
		var n := int(height / 0.6)
		for i in n + 1:
			var q: Vector3 = inv * Vector3(p.x, y0 + height * i / n, p.y)
			var c := Vector3i(floori(q.x * 0.5), floori(q.y * 0.5), floori(q.z * 0.5))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var cell: Variant = cells.get(c + Vector3i(dx, dy, dz))
						if cell == null:
							continue
						for v: Vector3 in cell:
							if v.distance_to(q) < lim:
								return true
	return false


const EPALM_HEIGHT := {"CocoA": 14.0, "CocoB": 10.0, "LatA": 9.0, "LatB": 6.5, "PalmA": 18.0, "PalmB": 13.0, "CocoJ0": 3.0, "CocoJ1": 3.0}

var _coco_spots: Array = []   # [position (x, z), kind] of every coco de mer with a trunk

func _plant_epalm(parent: Node3D, kind: String, p: Vector2, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = _rng
	var sc := rng.randf_range(0.85, 1.15)
	var y := ground_min(p.x, p.y, 0.4 * sc) - 0.1
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, y, p.y))
	if _palm_hits_tree(p, float(EPALM_HEIGHT.get(kind, 8.0)) * sc):
		return   # (decided only after the random numbers are drawn: the stream stays the same)
	if kind == "CocoA" or kind == "CocoB":
		_coco_spots.append([p, kind])
	for part in [["Trunk", 0.0, 0.0], ["Crown", 0.0, 45.0], ["Crown_lod", 45.0, 0.0], ["Nuts", 0.0, 80.0], ["Flowers", 0.0, 80.0]]:
		var key: String = kind + part[0]
		if not _epalm_parts.has(key):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _epalm_parts[key][0]
		# no hysteresis margins: crown and LOD must hand over at exactly the same distance
		mi.visibility_range_begin = part[1]
		mi.visibility_range_end = part[2]
		if part[0] == "Crown_lod" or part[0] == "Flowers":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_transform = xf * (_epalm_parts[key][1] as Transform3D)
		_world._apply_materials(mi)
		if part[0] == "Trunk":
			_collide.append([mi.mesh, mi.global_transform])


# ------------------------------------------------------------------ mangroves
## Red mangroves on their stilt roots where the forest comes right down to the sea: small stands
## standing in the shallows and on the wet sand at the water's edge.
func _mangroves() -> void:
	var scene := load("res://assets/models/mangroves.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	var parts := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		parts[m.name] = (m as MeshInstance3D).mesh
	tmp.free()
	var parent := Node3D.new()
	parent.name = "Mangroves"
	add_child(parent)
	# shore points (with the direction out to sea) where forest or tall vegetation is close inland
	var cands: Array = []
	var z := -212.0
	while z < 212.0:
		for side in [-1, 1]:
			var sx := _shore_scan(z, side)
			if is_nan(sx):
				continue
			var shore := Vector2(sx, z)
			var woody := false
			for d in [10.0, 18.0, 26.0]:
				var inland: Vector2 = shore - Vector2(side, 0) * d
				if cover(inland.x, inland.y).r > 0.6:
					woody = true
			for o: Vector2 in _legacy_spots:
				if o.distance_to(shore) < 30.0:
					woody = true
					break
			# (not where the shore is bare granite: mangroves root in mud and sand)
			for off in [-12.0, -6.0, 0.0, 6.0, 12.0]:
				if rocky(shore + Vector2(0, off), 3.0):
					woody = false
			if woody:
				cands.append([shore, Vector2(side, 0)])
		z += 3.0
	var stands: Array = []
	_rng_shuffle(cands)
	for c in cands:
		if stands.size() >= 8:
			break
		var ok := true
		for st in stands:
			if (st[0] as Vector2).distance_to(c[0]) < 48.0:
				ok = false
		if ok:
			stands.append(c)
	var trunks: Array = []
	for st in stands:
		var shore: Vector2 = st[0]
		var sea: Vector2 = st[1]
		var tang := Vector2(-sea.y, sea.x)
		var n := _rng.randi_range(4, 8)
		var placed: Array = []
		for k in n * 4:
			if placed.size() >= n:
				break
			var p := shore + tang * _rng.randf_range(-11.0, 11.0) + sea * _rng.randf_range(-3.5, 2.5)
			var h := ground(p.x, p.y)
			if h < -0.75 or h > 0.7 or rocky(p, 2.0):
				continue
			var free := true
			for q in placed + trunks:
				if (q as Vector2).distance_to(p) < 3.2:
					free = false
			for pt in palm_trunks:
				var b: Vector3 = pt["pts"][0]
				if Vector2(b.x, b.z).distance_to(p) < 2.5:
					free = false
			if not free:
				continue
			placed.append(p)
			var kind := "Mangrove%d" % (_rng.randi() % 3)
			var sc := _rng.randf_range(0.8, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, h, p.y))
			for part in [["Bark", 0.0, 0.0], ["Leaves", 0.0, 30.0], ["Leaves_lod", 30.0, 80.0], ["Leaves_lod2", 80.0, 0.0]]:
				var key: String = kind + part[0]
				if not parts.has(key):
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = parts[key]
				mi.visibility_range_begin = part[1]
				mi.visibility_range_end = part[2]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if part[0] in ["Bark", "Leaves_lod"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(mi)
				mi.global_transform = xf
				_world._apply_materials(mi)
				if part[0] == "Bark":
					_collide.append([mi.mesh, xf])
		trunks.append_array(placed)
	mangrove_spots = trunks


var mangrove_spots: Array = []


func _rng_shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ------------------------------------------------------------------ ferns
## Ferns on the forest floor (most of them), around the grotto and here and there on the hill;
## bird's-nest ferns among them. Multimesh chunks with a near and a coarse far version.
const FERN_CELL := 2.0
var _fern_cells := {}    # Vector2i cell -> [Vector3(x, z, reach)]


## Do a fern's fronds cover the ground at p (or within `margin` of it)? `part`: the share of
## a fern's spread that counts (its fronds thin out toward their tips).
func ferny(p: Vector2, margin := 0.0, part := 0.8) -> bool:
	var c := Vector2i(int(floorf(p.x / FERN_CELL)), int(floorf(p.y / FERN_CELL)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var list: Array = _fern_cells.get(c + Vector2i(dx, dz), [])
			for f: Vector3 in list:
				if Vector2(f.x, f.y).distance_to(p) < f.z * part + margin:
					return true
	return false


func _ferns() -> void:
	var scene := load("res://assets/models/ferns.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	var meshes := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		meshes[m.name] = (m as MeshInstance3D).mesh
	tmp.free()
	var kinds := ["FernA", "FernB", "NestFern"]
	var reach := [0.6, 0.6, 0.6]    # how far each kind's fronds spread from its middle
	for k in 3:
		if meshes.has(kinds[k]):
			var bb: AABB = (meshes[kinds[k]] as Mesh).get_aabb()
			reach[k] = maxf(maxf(absf(bb.position.x), absf(bb.end.x)), maxf(absf(bb.position.z), absf(bb.end.z)))
	var chunks := {}   # Vector3i(cx, cz, kind) -> Array[Transform3D]
	var placed := 0
	var tries := 0
	while placed < 14000 and tries < 90000:
		tries += 1
		var p := Vector2.ZERO
		var r := _rng.randf()
		if r < 0.05:
			# moist ground around the grotto entrance and along the rocks above it
			var a := _rng.randf() * TAU
			if cave_path.is_empty():
				continue
			var cp: Array = cave_path[_rng.randi() % cave_path.size()]
			var c3: Vector3 = cp[0]
			p = Vector2(c3.x, c3.z) + Vector2(cos(a), sin(a)) * (float(cp[1]) + _rng.randf_range(1.0, 9.0))
			if cave_dist(p) < 4.5:
				continue
		elif r < 0.09 and stream_course.size() > 2:
			# the damp banks of the stream and the rim of the pond
			var sc := stream_course[_rng.randi() % stream_course.size()]
			var a := _rng.randf() * TAU
			p = Vector2(sc.x, sc.z) + Vector2(cos(a), sin(a)) * _rng.randf_range(0.9, 6.5)
			if _rng.randf() < 0.2:
				var pond: Dictionary = stream_pools[stream_pools.size() - 1]
				p = Vector2(pond["at"].x, pond["at"].z) + Vector2(cos(a), sin(a)) * _rng.randf_range(3.6, 8.0)
			if cover(p.x, p.y).r < 0.3 or stream_dist(p) < 0.8:
				continue
		else:
			p = Vector2(_rng.randf_range(-178.0, -12.0), _rng.randf_range(-215.0, 215.0))
			var cv := cover(p.x, p.y)
			# mostly under the forest; sparse on the open grass of the hill
			if cv.r < 0.55 and not (cv.b > 0.4 and _rng.randf() < 0.12):
				continue
			if cave_dist(p) < 5.0 or stream_dist(p) < 0.8:
				continue
		var h := ground(p.x, p.y)
		if h < 0.8 or trail_distance(p) < 2.2 or p.distance_to(_peak) < 22.0 or cave_way(p) < 1.0:
			continue
		var kind := 2 if _rng.randf() < 0.12 else _rng.randi() % 2
		var sc := _rng.randf_range(0.7, 1.35) * (1.0 if kind < 2 else _rng.randf_range(0.8, 1.3))
		var n := Vector3(ground(p.x - 0.4, p.y) - ground(p.x + 0.4, p.y), 0.8, ground(p.x, p.y - 0.4) - ground(p.x, p.y + 0.4)).normalized()
		var b := Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(n, 0.6).normalized())) * Basis(Vector3.UP, _rng.randf() * TAU)
		var key := Vector3i(int(floorf(p.x / 24.0)), int(floorf(p.y / 24.0)), kind)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(p.x, h - 0.04, p.y)))
		placed += 1
		# (for the small animals of the forest floor: where the ferns cover the ground)
		var cell := Vector2i(int(floorf(p.x / FERN_CELL)), int(floorf(p.y / FERN_CELL)))
		if not _fern_cells.has(cell):
			_fern_cells[cell] = []
		(_fern_cells[cell] as Array).append(Vector3(p.x, p.y, float(reach[kind]) * sc))
	var parent := Node3D.new()
	parent.name = "Ferns"
	add_child(parent)
	for key in chunks:
		var list: Array = chunks[key]
		for lod in [false, true]:
			var mname: String = kinds[key.z] + ("_lod" if lod else "")
			if not meshes.has(mname):
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[mname]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_begin = 22.0 if lod else 0.0
			mmi.visibility_range_end = 55.0 if lod else 22.0
			parent.add_child(mmi)
			_world._apply_materials(mmi)
			var src := (meshes[mname] as Mesh).surface_get_material(0)
			if src and _world.get_material(src.resource_name):
				mmi.material_override = _world.get_material(src.resource_name)


# ------------------------------------------------------------------ grotto
## A walkable cave under fused granite boulders on the hillside. Ambient light inside comes
## from an interior reflection probe, so the chamber is properly dim (sunlight only falls in
## through the entrance and the crack in the roof).
func _grotto() -> void:
	var scene := load("res://assets/models/grotto.glb") as PackedScene
	if scene == null or cave_path.is_empty():
		return
	var tmp := scene.instantiate()
	var meshes := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		meshes[m.name] = (m as MeshInstance3D).mesh
	tmp.free()
	# (the meshes are in world coordinates; the roots hanging through the roof are not solid)
	for k in ["Grotto", "GrottoRoots"]:
		if not meshes.has(k):
			continue
		var mi := MeshInstance3D.new()
		mi.name = k
		mi.mesh = meshes[k]
		add_child(mi)
		_world._apply_materials(mi)
		if k == "Grotto" and not Engine.is_editor_hint():
			# a body of its own: with its many triangles it does not fit into the compound of
			# the hundreds of other shapes (Jolt runs out of sub-shape id bits there)
			var body := StaticBody3D.new()
			body.name = "GrottoCollision"
			var cs := CollisionShape3D.new()
			cs.shape = meshes[k].create_trimesh_shape()
			cs.set_meta("rain", 2)
			body.add_child(cs)
			add_child(body)
	# The tree whose roots hang through the roof: a takamaka in a hollow between the boulders
	# on top of the pile, beside the big gap (tools/grotto2.py lays the roots from its foot)
	if cave.has("fig") and _tree_parts.has("Taka1Bark"):
		var fa: Array = cave["fig"]["at"]
		var txf := Transform3D(Basis(Vector3.UP, 2.2).scaled(Vector3.ONE * 0.72), Vector3(fa[0], fa[1], fa[2]))
		tree_spots.append({"xf": txf, "kind": "Taka1", "colony": false})
		for part in [["Bark", 0.0, 0.0], ["Twigs", 0.0, 60.0], ["Leaves", 0.0, 32.0], ["Leaves_lod", 32.0, 85.0], ["Leaves_lod2", 85.0, 0.0]]:
			var key: String = "Taka1" + part[0]
			if not _tree_parts.has(key):
				continue
			var tm := MeshInstance3D.new()
			tm.name = "GrottoTree" + part[0]
			tm.mesh = _tree_parts[key]
			tm.visibility_range_begin = part[1]
			tm.visibility_range_end = part[2]
			if part[0] == "Leaves_lod2" or part[0] == "Twigs":
				tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(tm)
			tm.global_transform = txf
			_world._apply_materials(tm)
			if part[0] == "Bark":
				_collide.append([tm.mesh, txf])
	# The sky's ambient light does not stop at rock: interior reflection probes along the way
	# through replace it with a dim one, a little brighter toward the two mouths.
	var last := -99.0
	var n := 0
	for c in cave_path:
		var s: float = c[3]
		if s < _cave_roofed.x + 1.0 or s > _cave_roofed.y - 1.0 or s - last < 4.0:
			continue
		last = s
		var w: float = c[1]
		var h: float = c[2]
		var probe := ReflectionProbe.new()
		probe.name = "GrottoProbe%d" % n
		n += 1
		probe.interior = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.ambient_color = Color(0.16, 0.15, 0.14)
		probe.ambient_color_energy = lerpf(0.65, 0.45, clampf(minf(s - _cave_roofed.x, _cave_roofed.y - s) / 9.0, 0.0, 1.0))
		probe.size = Vector3(2.0 * w + 4.0, h + 2.5, 2.0 * w + 4.0)
		probe.blend_distance = 1.5
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.max_distance = 30.0
		add_child(probe)
		probe.global_position = (c[0] as Vector3) + Vector3(0, h * 0.5, 0)
	# daylight through the two gaps in the roof: a soft glow under each (dimmed at night by
	# island_life), and under the big one, which points at the midday sun, a shaft of light
	var k := 0
	for sk in cave["skylights"]:
		var fl := Vector3(sk["floor"][0], sk["floor"][1], sk["floor"][2])
		var dir := Vector3(sk["dir"][0], sk["dir"][1], sk["dir"][2])
		var room: Array = cave["inner_size"] if k == 0 else cave["front_size"]
		var up: float = float(room[1]) / maxf(dir.y, 0.3)
		var glow := OmniLight3D.new()
		glow.name = "GrottoSkyGlow%d" % k
		glow.light_color = Color(0.85, 0.9, 1.0)
		glow.light_energy = 0.9 if k == 0 else 0.5
		glow.omni_range = 9.0 if k == 0 else 6.0
		glow.omni_attenuation = 1.4
		glow.shadow_enabled = false
		glow.light_specular = 0.5
		glow.set_meta("energy", glow.light_energy)
		add_child(glow)
		glow.global_position = fl + dir * (up * 0.8)
		if k == 0:
			var beam := MeshInstance3D.new()
			beam.name = "GrottoBeam"
			var cyl := CylinderMesh.new()
			cyl.top_radius = float(sk["r"]) * 0.8
			cyl.bottom_radius = float(sk["r"]) * 1.15
			cyl.height = up + 1.0
			cyl.radial_segments = 24
			cyl.cap_top = false
			cyl.cap_bottom = false
			beam.mesh = cyl
			var sh := Shader.new()
			sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.0;
void fragment() {
	// dust in a shaft of sunlight: brightest seen along its length, fading out at its edge
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = vec3(1.0, 0.95, 0.82);
	ALPHA = strength * edge * edge * smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.75, UV.y);
}"""
			var bm := ShaderMaterial.new()
			bm.shader = sh
			beam.material_override = bm
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.set_meta("dir", dir)
			add_child(beam)
			beam.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), fl + dir * (up * 0.5 + 0.3))
		k += 1


# ------------------------------------------------------------------ rocks
func _rocks() -> void:
	var scene := load("res://assets/models/boulders.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	var meshes: Array = []
	for m in tmp.find_children("Boulder*", "MeshInstance3D", true, false):
		meshes.append((m as MeshInstance3D).mesh)
	tmp.free()
	var parent := Node3D.new()
	parent.name = "Boulders"
	add_child(parent)
	# [center (x, z), count, spread radius, size min, size max]
	var groups: Array = [
		[Vector2(7, 92), 6, 7.0, 1.0, 3.2],          # west beach, north of the start
		# east shore: at the waterline, and the granite of the headland below the hill and of the
		# points that close off the two bays
		[Vector2(_shore_scan(-60, -1) - 3.0, -60), 7, 9.0, 1.2, 4.5],
		[Vector2(_shore_scan(55, -1) - 1.0, 55), 6, 8.0, 1.0, 3.8],
		[Vector2(_shore_scan(140, -1) + 1.0, 140), 8, 10.0, 1.2, 5.0],
		[Vector2(_shore_scan(-165, -1) + 7.0, -165), 7, 9.0, 1.2, 4.5],
		[Vector2(_shore_scan(-14, -1) - 5.0, -14), 11, 13.0, 1.6, 6.0],
		[Vector2(_shore_scan(-186, -1) - 2.0, -186), 7, 8.0, 1.2, 5.0],
		[Vector2(_shore_scan(188, -1) - 2.0, 188), 7, 8.0, 1.2, 5.0],
		[Vector2(-40, _shore_scan_z(-40, 1) + 1.0), 8, 11.0, 1.5, 5.5],      # northern tip
		[Vector2(-60, _shore_scan_z(-60, -1) - 1.0), 8, 11.0, 1.5, 5.5],     # southern tip
		[Vector2(-121, _shore_scan_z(-121, -1) + 6.0), 6, 8.0, 1.0, 4.0],
		[Vector2(-131, _shore_scan_z(-131, 1) - 6.0), 6, 8.0, 1.0, 4.0],
		[_peak + Vector2(9, 3), 4, 4.0, 2.5, 5.5],    # granite outcrops around the summit
		[_peak + Vector2(-8, -9), 4, 4.0, 2.0, 5.0],
		[_peak + Vector2(-4, 12), 3, 3.0, 2.0, 4.5],
	]
	# boulders scattered over the hill and through the forest
	for i in 26:
		var a := _rng.randf() * TAU
		groups.append([_peak + Vector2(cos(a), sin(a)) * _rng.randf_range(15.0, 60.0), 1, 0.0, 0.8, 2.6])
	for i in 45:
		var p := Vector2(_rng.randf_range(-165.0, -40.0), _rng.randf_range(-200.0, 200.0))
		if cover(p.x, p.y).r > 0.7:
			groups.append([p, _rng.randi_range(1, 3), 2.5, 0.6, 2.0])
	# loose boulders lying on the slabs and whalebacks and at their feet
	var on_rock := 0
	for i in 2500:
		if on_rock >= 46:
			break
		var p := Vector2(_frng.randf_range(-172.0, -52.0), _frng.randf_range(-170.0, 170.0))
		if ground(p.x, p.y) > 3.0 and rocky(p, 2.2) and p.distance_to(_peak) > 9.0:
			groups.append([p, 1, 0.0, 0.6, 2.4])
			on_rock += 1
	# the seep the stream starts from: under boulders at the foot of the summit's granite; and
	# boulders along the gully
	if stream_course.size() > 8:
		var s0 := stream_course[0]
		groups.append([Vector2(s0.x, s0.z) + Vector2(0.2, 1.6), 5, 2.4, 1.2, 3.0])
		for i in range(6, stream_course.size() - 5, 5):
			var sc := stream_course[i]
			var side := (stream_course[i + 1] - stream_course[i - 1]).cross(Vector3.UP).normalized()
			var off := _frng.randf_range(1.5, 3.4) * (1.0 if _frng.randf() < 0.5 else -1.0)
			groups.append([Vector2(sc.x + side.x * off, sc.z + side.z * off), 1, 0.4, 0.5, 1.7])
	for g in groups:
		var c: Vector2 = g[0]
		for i in int(g[1]):
			var a := _rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * _rng.randf_range(0.0, g[2])
			if ground(p.x, p.y) < -1.5 or cave_dist(p) < CAVE_R + 2.0:
				continue
			if stream_dist(p) < 0.9:
				continue   # (never in the water's way)
			var size := _rng.randf_range(g[3], g[4])
			if trail_distance(p) < 1.5 + size * 0.5 or cave_way(p) < 2.0 + size * 0.6:
				continue   # the ridge, the natural way up to the summit, and the way to the grotto stay clear
			# radius of the boulder footprint; seat it on the lowest point under it
			var y := ground_min(p.x, p.y, size * 0.75) + size * 0.05
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * size * 0.5)
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[_rng.randi() % meshes.size()]
			parent.add_child(mi)
			mi.global_transform = Transform3D(b, Vector3(p.x, y, p.y))
			_world._apply_materials(mi)
			_collide.append([mi.mesh, mi.global_transform, false, true])
			boulder_spots.append([Vector3(p.x, y, p.y), size])


# ------------------------------------------------------------------ the stream
## Fresh water: a seep at the foot of the summit's granite, a gully down the valley to the
## south-west and a pond behind the beach. The gully and the basins are part of the terrain and
## the running water is painted by the ground shader (land mask alpha); here the still water of
## the rock pools and the pond is added: flat sheets at the water level (shaders/pool.gdshader).
func _stream() -> void:
	if stream_pools.is_empty():
		return
	var parent := Node3D.new()
	parent.name = "Stream"
	add_child(parent)
	var k := 0
	for pl in stream_pools:
		var at: Vector3 = pl["at"]
		var rx: float = float(pl["rx"]) + 1.6
		var rz: float = float(pl["rz"]) + 1.6
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(2.0 * rx, 2.0 * rz)
		var mi := MeshInstance3D.new()
		mi.name = "Pond" if pl["pond"] else "Pool%d" % k
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/pool.gdshader")
		var src: ShaderMaterial = _world.get_material("Sand")
		if src:
			mat.set_shader_parameter("normal_tex", src.get_shader_parameter("water_normal"))
		# the water comes in at the uphill end
		var best := 0
		for i in stream_course.size():
			if Vector2(stream_course[i].x, stream_course[i].z).distance_to(Vector2(at.x, at.z)) < Vector2(stream_course[best].x, stream_course[best].z).distance_to(Vector2(at.x, at.z)):
				best = i
		var up := stream_course[maxi(best - 1, 0)]
		if pl["pond"]:
			up = stream_course[stream_course.size() - 1]
		mat.set_shader_parameter("inflow", Vector3(up.x, at.y, up.z))
		mat.set_shader_parameter("inflow_strength", 0.7 if pl["pond"] else 1.0)
		var grow := 0.8 if pl["pond"] else 0.3
		mat.set_shader_parameter("basin", Vector4(at.x, at.z, float(pl["rx"]) + grow, float(pl["rz"]) + grow))
		mat.set_shader_parameter("basin_dir", Vector2(cos(float(pl["yaw"])), sin(float(pl["yaw"]))))
		if pl["pond"]:
			mat.set_shader_parameter("tint", Color(0.045, 0.06, 0.025))
		mi.material_override = mat
		parent.add_child(mi)
		mi.global_transform = Transform3D(Basis(Vector3.UP, -float(pl["yaw"])), at)
		k += 1


# ------------------------------------------------------------------ tide pools
## Tide pools: hollows in the east headland's granite between the tide marks (cut by
## tools/terrain2.py, which also works out the level each spills at: island.json,
## "tide_pools"). Each gets a sheet of still water at that level (shaders/pool.gdshader, as
## the stream's pools). scripts/tide.gd shows a sheet when the sea has fallen below it; while
## the sea stands higher the hollow is part of the sea floor.
var tide_pools: Array = []       # {"at": Vector3 (the middle, at the water's level), "rx", "rz", "node"}

func _tide_pools() -> void:
	tide_pools.clear()
	var f := FileAccess.open("res://assets/models/island.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary) or not (data as Dictionary).has("tide_pools"):
		return
	var parent := Node3D.new()
	parent.name = "TidePools"
	add_child(parent)
	var src: ShaderMaterial = _world.get_material("Sand")
	for p: Dictionary in data["tide_pools"]:
		var at := Vector3(float(p["x"]), float(p["level"]) - 0.012, float(p["z"]))
		var rx: float = float(p["rx"]) + 0.5
		var rz: float = float(p["rz"]) + 0.5
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(2.0 * rx + 1.0, 2.0 * rz + 1.0)
		var mi := MeshInstance3D.new()
		mi.name = "TidePool%d" % tide_pools.size()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/pool.gdshader")
		if src:
			mat.set_shader_parameter("normal_tex", src.get_shader_parameter("water_normal"))
		mat.set_shader_parameter("inflow_strength", 0.0)
		# (close around the hollow: a wider basin put slivers of water on the rock beside it)
		mat.set_shader_parameter("basin", Vector4(at.x, at.z, rx - 0.15, rz - 0.15))
		mat.set_shader_parameter("basin_dir", Vector2(1, 0))
		# (sea water over pale granite: clearer and greener than the forest's pond)
		mat.set_shader_parameter("tint", Color(0.06, 0.2, 0.18))
		mat.set_shader_parameter("clear", 1.0)
		mi.material_override = mat
		mi.visible = false
		parent.add_child(mi)
		mi.global_position = at
		tide_pools.append({"at": at, "rx": rx, "rz": rz, "node": mi})
	# the sea keeps out of a pool that the tide has cut off (shaders/ocean.gdshader)
	var ocean: ShaderMaterial = _world.get_material("Ocean")
	if ocean:
		var discs := PackedVector4Array()
		var levels := PackedFloat32Array()
		for k in 8:
			if k < tide_pools.size():
				var tp: Dictionary = tide_pools[k]
				discs.append(Vector4((tp["at"] as Vector3).x, (tp["at"] as Vector3).z, float(tp["rx"]) + 0.1, float(tp["rz"]) + 0.1))
				levels.append((tp["at"] as Vector3).y)
			else:
				discs.append(Vector4(0, 0, 1, 1))
				levels.append(-99.0)
		ocean.set_shader_parameter("tide_pool", discs)
		ocean.set_shader_parameter("tide_pool_level", levels)
		ocean.set_shader_parameter("tide_pool_count", mini(tide_pools.size(), 8))


# ------------------------------------------------------------------ screwpines
## Vacoa (screwpine) on its cone of stilt roots: among the granite boulders of the shores and the
## hill, and here and there along the top of the beaches.
func _vacoas() -> void:
	if not _tree_parts.has("Vacoa0Bark"):
		return
	var parent := Node3D.new()
	parent.name = "Vacoas"
	add_child(parent)
	var cands: Array = []
	for b in boulder_spots:
		var c: Vector3 = b[0]
		var size: float = b[1]
		for k in _frng.randi_range(0, 2):
			var a := _frng.randf() * TAU
			cands.append(Vector2(c.x, c.z) + Vector2(cos(a), sin(a)) * (size * 0.6 + _frng.randf_range(0.8, 3.0)))
	var z := -205.0
	while z < 205.0:
		for side in [-1, 1]:
			if _frng.randf() < 0.3:
				var sx := _shore_scan(z, side)
				if not is_nan(sx):
					cands.append(Vector2(sx - side * _frng.randf_range(9.0, 16.0), z + _frng.randf_range(-3.0, 3.0)))
		z += _frng.randf_range(8.0, 14.0)
	for i in range(cands.size() - 1, 0, -1):
		var j := _frng.randi() % (i + 1)
		var t: Vector2 = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	var placed: Array = []
	for p: Vector2 in cands:
		if placed.size() >= 70:
			break
		if ground(p.x, p.y) < 0.7 or blocked(p.x, p.y, 4.0, 24.0):
			continue
		var free := true
		for q in placed:
			if (q as Vector2).distance_to(p) < 3.5:
				free = false
		for pt in palm_trunks:
			var pb: Vector3 = pt["pts"][0]
			if Vector2(pb.x, pb.z).distance_to(p) < 2.5:
				free = false
		for t in tree_spots:
			var o: Vector3 = t["xf"].origin
			if Vector2(o.x, o.z).distance_to(p) < 3.0:
				free = false
		for b in boulder_spots:
			var c: Vector3 = b[0]
			if Vector2(c.x, c.z).distance_to(p) < float(b[1]) * 0.55 + 0.5:
				free = false
		if not free:
			continue
		placed.append(p)
		var kind := "Vacoa%d" % (_frng.randi() % 3)
		var sc := _frng.randf_range(0.8, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, _frng.randf() * TAU).scaled(Vector3.ONE * sc),
			Vector3(p.x, ground_min(p.x, p.y, 0.8 * sc) - 0.05, p.y))
		for part in [["Bark", 0.0, 0.0], ["Leaves", 0.0, 40.0], ["Leaves_lod", 40.0, 0.0], ["Fruit", 0.0, 60.0]]:
			var key: String = kind + part[0]
			if not _tree_parts.has(key):
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = _tree_parts[key]
			mi.visibility_range_begin = part[1]
			mi.visibility_range_end = part[2]
			if part[0] == "Leaves_lod" or part[0] == "Fruit":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			mi.global_transform = xf
			_world._apply_materials(mi)
			if part[0] == "Bark":
				_collide.append([mi.mesh, xf])
	vacoa_spots = placed


var vacoa_spots: Array = []


# ------------------------------------------------------------------ distant islands
## Beach morning glory (Ipomoea pes-caprae) also creeps over the east beach: a copy of the patch at
## the start (Groundcover MG*/VineStems from the .blend), turned to face the eastern sea and
## re-draped onto the sand there (each vertex keeps its height above the ground).
func _morning_glory() -> void:
	var gc := _world.get_node_or_null("Groundcover")
	if gc == null:
		return
	var z_from := 15.0
	var z_to := 22.0
	var from := Vector3(_shore_scan(z_from, 1) - 8.0, 0.0, z_from)
	var sx := _shore_scan(z_to, -1)
	if is_nan(sx) or is_nan(from.x):
		return
	var to := Vector3(sx + 8.0, 0.0, z_to)
	var xf := Transform3D(Basis(Vector3.UP, PI + 0.25), to) * Transform3D(Basis(), -from)
	var parent := Node3D.new()
	parent.name = "MorningGloryEast"
	add_child(parent)
	for src in gc.get_children():
		var mi := src as MeshInstance3D
		if mi == null or not ((mi.name as String).begins_with("MG") or (mi.name as String).begins_with("Vine")):
			continue
		var mesh := ArrayMesh.new()
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var tangs = arr[Mesh.ARRAY_TANGENT]
			var full := xf * mi.global_transform
			for i in verts.size():
				var w: Vector3 = mi.global_transform * verts[i]
				var n: Vector3 = full * verts[i]
				n.y = ground(n.x, n.z) + (w.y - ground(w.x, w.z))
				verts[i] = n
				if i < norms.size():
					norms[i] = (full.basis * norms[i]).normalized()
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			if tangs is PackedFloat32Array and (tangs as PackedFloat32Array).size() == verts.size() * 4:
				var t: PackedFloat32Array = tangs
				for i in verts.size():
					var tv := (full.basis * Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])).normalized()
					t[i * 4] = tv.x
					t[i * 4 + 1] = tv.y
					t[i * 4 + 2] = tv.z
				arr[Mesh.ARRAY_TANGENT] = t
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(si, mi.get_active_material(si))
		var m := MeshInstance3D.new()
		m.name = mi.name
		m.mesh = mesh
		m.cast_shadow = mi.cast_shadow
		m.visibility_range_end = mi.visibility_range_end
		parent.add_child(m)


func _islands(headland: Array) -> void:
	var parent := Node3D.new()
	parent.name = "Islands"
	add_child(parent)
	var rocks: Array = []
	var rr := _world.get_node_or_null("Rocks")
	if rr:
		rocks = rr.find_children("*", "MeshInstance3D", true, false)
	var placements := [
		[Vector3(1500, -3.0, -1400), 5.0, 0.6],
		[Vector3(1800, -3.0, 950), 4.2, 4.0],
		[Vector3(-1600, -3.0, -900), 4.5, 1.9],
		[Vector3(-2100, -3.0, 700), 3.8, 3.1],
	]
	var base_mat := StandardMaterial3D.new()
	base_mat.vertex_color_use_as_albedo = true
	base_mat.roughness = 1.0
	base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for p in placements:
		var first := parent.get_child_count()
		var sc: float = p[1]
		var b := Basis(Vector3.UP, p[2]).scaled(Vector3(sc, sc * 1.6, sc))
		var xf := Transform3D(b, p[0]) * Transform3D(Basis(), Vector3(8, 0, 105))
		for src in headland:
			if src.visibility_range_end > 0.0:
				continue   # only the coarsest leaves and the hill body
			var m := _copy(src, xf, parent, false)
			if m == null:
				continue
			m.visibility_range_begin = 0.0
			m.visibility_range_begin_margin = 0.0
		var rb := Basis(Vector3.UP, p[2] + 1.0).scaled(Vector3.ONE * sc * 1.3)
		var rxf := Transform3D(rb, p[0] + Basis(Vector3.UP, p[2]) * Vector3(sc * 14.0, 0, 0)) * Transform3D(Basis(), Vector3(-15, 0, 50))
		for src in rocks:
			_copy(src, rxf, parent, false)
		_island_base(parent, first, p[2], base_mat)


## What a distant island stands on. Its hill and its rocks end a few meters under the surface;
## seen from under water (the free camera gets there) they hung in open water. This puts a
## shoal under everything the island is made of (the parent's children from `first` on): flat
## just below the surface, then falling away into the deep on all sides. From above nothing of
## it shows (out there the sea is drawn deep).
func _island_base(parent: Node3D, first: int, yaw: float, mat: Material) -> void:
	var inv := Basis(Vector3.UP, -yaw)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in range(first, parent.get_child_count()):
		var mi := parent.get_child(i) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab := mi.get_aabb()
		for k in 8:
			var c: Vector3 = inv * (mi.global_transform * ab.get_endpoint(k))
			lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
			hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
	if lo.x > hi.x:
		return
	var mid := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5 * 1.08
	var noise := FastNoiseLite.new()
	noise.seed = 77 + first
	noise.frequency = 0.012
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# rings: [share of the island's size, depth]
	var rings := [[0.0, -0.9], [0.6, -0.9], [1.0, -1.3], [1.18, -4.0], [1.45, -11.0], [1.9, -22.0], [2.6, -36.0], [3.6, -50.0]]
	var segs := 40
	var grid: Array = []
	for r: Array in rings:
		var row: Array = []
		for j in segs:
			var a := TAU * j / float(segs)
			# (a rounded rectangle rather than an ellipse: the island is a long ridge)
			var q := Vector2(signf(cos(a)) * pow(absf(cos(a)), 0.6) * half.x, signf(sin(a)) * pow(absf(sin(a)), 0.6) * half.y) * float(r[0])
			var grow := 1.0 + 0.14 * noise.get_noise_2d(q.x + 50.0, q.y) * minf(float(r[0]), 1.5)
			var w: Vector3 = Basis(Vector3.UP, yaw) * Vector3(mid.x + q.x * grow, 0.0, mid.y + q.y * grow)
			w.y = float(r[1]) + 1.5 * noise.get_noise_2d(w.x * 3.0, w.z * 3.0) * clampf(float(r[0]) - 0.9, 0.0, 1.0)
			var shade := 0.8 + 0.25 * noise.get_noise_2d(w.x * 6.0, w.z * 6.0)
			row.append([w, Color(0.3 * shade, 0.27 * shade, 0.2 * shade)])
		grid.append(row)
	for i in rings.size() - 1:
		for j in segs:
			var j1 := (j + 1) % segs
			var quad := [grid[i][j], grid[i][j1], grid[i + 1][j1], grid[i + 1][j]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(quad[idx][1])
				st.add_vertex(quad[idx][0])
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.name = "IslandBase"
	m.mesh = st.commit()
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


# ------------------------------------------------------------------ debris
func _debris() -> void:
	var scene := load("res://assets/models/debris.glb") as PackedScene
	if scene == null:
		return
	var tmp := scene.instantiate()
	var meshes := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		meshes[m.name] = (m as MeshInstance3D).mesh
	tmp.free()
	var parent := Node3D.new()
	parent.name = "Debris"
	add_child(parent)
	var shells := ["Shell0", "Shell1", "Shell2", "Shell3", "Coral0", "Coral1"]
	var per_mesh := {}
	for k in shells:
		per_mesh[k] = []
	# strand lines on both main beaches: where the highest waves leave their treasures
	for i in 3600:
		var east := i % 3 == 2
		var z := _rng.randf_range(-75.0, 128.0) if not east else _rng.randf_range(-180.0, 180.0)
		var sx := _shore_scan(z, -1 if east else 1)
		if is_nan(sx):
			continue
		var band := _rng.randf_range(-1.2, 4.0) if _rng.randf() < 0.7 else _rng.randf_range(-1.0, 18.0)
		var x := sx - band * (-1.0 if east else 1.0)
		var h := ground(x, z)
		if h < 0.12 or h > 2.0:
			continue
		var k: String = shells[_rng.randi() % shells.size()]
		if k.begins_with("Coral") and _rng.randf() < 0.4:
			k = "Shell%d" % (_rng.randi() % 4)
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		if _rng.randf() < 0.3:
			b = b * Basis(Vector3.FORWARD, PI)   # upside down
		b = b.scaled(Vector3.ONE * _rng.randf_range(0.7, 1.4))
		per_mesh[k].append(Transform3D(b, Vector3(x, h - 0.004, z)))
	for k in per_mesh:
		if meshes.has(k):
			_multimesh(parent, meshes[k], per_mesh[k], false)
	# coconuts under the palms near the shore
	var nuts: Array = []
	for crown in _world.find_children("Crown*", "Node3D", true, false):
		var c := (crown as Node3D).global_position
		if cover(c.x, c.z).r > 0.6:
			continue
		for j in _rng.randi_range(1, 4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.5, 3.5)
			var x := c.x + cos(a) * r
			var z := c.z + sin(a) * r
			var h := ground(x, z)
			if h < 0.3:
				continue
			var b := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
			nuts.append(Transform3D(b, Vector3(x, h + 0.08, z)))
	if meshes.has("Coconut"):
		_multimesh(parent, meshes["Coconut"], nuts, true)
	# weathered driftwood logs on the upper beaches, resting along the slope
	var lengths := [1.6, 2.4, 3.2]
	var radii := [0.08, 0.11, 0.14]
	var wood: Material = _world.get_material("Driftwood")
	for i in 16:
		var east := i >= 9
		var z := _rng.randf_range(-50.0, 120.0) if not east else _rng.randf_range(-170.0, 170.0)
		var sx := _shore_scan(z, -1 if east else 1)
		if is_nan(sx):
			continue
		var x := sx - _rng.randf_range(4.0, 11.0) * (-1.0 if east else 1.0)
		var ki := _rng.randi() % 3
		var k := "Driftwood%d" % ki
		if not meshes.has(k):
			continue
		var yaw := _rng.randf() * TAU
		var axis := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var half: float = lengths[ki] * 0.45
		var h0 := ground(x - axis.x * half, z - axis.z * half)
		var h1 := ground(x + axis.x * half, z + axis.z * half)
		var hc := ground(x, z)
		var pitch := atan2(h1 - h0, half * 2.0)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k]
		if wood:
			mi.material_override = wood
		parent.add_child(mi)
		var y: float = minf(hc, (h0 + h1) * 0.5) - float(radii[ki]) * 0.3
		mi.global_transform = Transform3D(b, Vector3(x, y, z))
		_collide.append([mi.mesh, mi.global_transform])


func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array, shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# no visibility range: it is measured to the center of the multimesh, and these span the whole
	# island (with a 60 m range, shells and coconuts were only drawn near the middle of the island)
	parent.add_child(mmi)


# ------------------------------------------------------------------ collision
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "LandscapeCollision"
	add_child(body)
	var bush_body := StaticBody3D.new()
	bush_body.name = "LandscapeBushVolumes"
	bush_body.collision_layer = 2
	bush_body.collision_mask = 0
	add_child(bush_body)
	var cache := {}
	for pair in _collide:
		var mesh: Mesh = pair[0]
		if not cache.has(mesh):
			cache[mesh] = mesh.create_trimesh_shape()
		var cs := CollisionShape3D.new()
		cs.shape = cache[mesh]
		var is_bush: bool = pair.size() > 2 and pair[2]
		if pair.size() > 3 and pair[3]:
			cs.set_meta("rain", 2)      # (rock that can keep rain off: scripts/weather.gd)
		(bush_body if is_bush else body).add_child(cs)
		cs.global_transform = pair[1]
