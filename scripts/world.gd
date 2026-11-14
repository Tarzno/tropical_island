@tool
extends Node3D
## Builds materials, the ocean surface and collision for the beach scene.
## Runs in the editor too so the viewport shows the finished look.

const SUN_TO := Vector3(-0.505, 0.788, -0.353) # direction *toward* the sun (from Blender scene)

@export var rebuild := false:
	set(v):
		if v and is_inside_tree():
			_setup()

var _mats := {}

## The forest's dense leaves come in four files, because GitHub takes no file over 100 MiB
## (tools/split_glb.py cut the one leaves.glb of 160 MB, 2026-11-13; not a byte of the meshes
## changed). "Leaves" in the scene is the first of them; the other three are put under it here,
## before anybody asks for its children (a child's _ready runs before ours, so: on entering
## the tree). In the editor too; the nodes added have no owner, so a saved scene does not
## hold them.
const LEAF_PARTS := ["res://assets/models/leaves_b.glb", "res://assets/models/leaves_c.glb", "res://assets/models/leaves_d.glb"]


func _enter_tree() -> void:
	_join_leaves()


func _join_leaves() -> void:
	var leaves := get_node_or_null("Leaves")
	if leaves == null:
		return
	for path: String in LEAF_PARTS:
		var scene := load(path) as PackedScene
		if scene == null:
			push_error("the forest's leaves are incomplete: cannot load " + path)
			continue
		var part := scene.instantiate()
		for c in part.get_children():
			part.remove_child(c)
			# (there already: the editor comes through here again when the scene's tab is shown)
			if leaves.has_node(NodePath(c.name)):
				c.free()
				continue
			c.owner = null
			leaves.add_child(c)
		part.free()


func _ready() -> void:
	_setup()


func _setup() -> void:
	_sea_globals()
	# (the materials may exist already: a child's _ready runs before ours and may have asked for one)
	if _mats.is_empty() or Engine.is_editor_hint():
		_build_materials()
	_apply_materials(self)
	# (before anything takes copies of these meshes: the far islands are built from them)
	_right_side_out()
	_setup_sun()
	_setup_lods()
	_build_ocean()
	var ls := get_node_or_null("Landscape")
	if ls and ls.has_method("build"):
		ls.build(self)
	_far_materials(self, false)
	_close_rocks(ls)
	if not Engine.is_editor_hint():
		_build_collision()


## The globals of shaders/sea_light.gdshaderinc are project settings (shader_globals); an
## editor that was open when they were added does not know them until it is restarted, and
## every shader that uses them would fail there. This adds what is missing.
static func _sea_globals() -> void:
	# (only in the editor: the game always has them, and the list may not be asked for there)
	if not Engine.is_editor_hint():
		return
	var have := RenderingServer.global_shader_parameter_get_list()
	for g: Array in [["sea_sun", 1.0], ["sun_slope_x", -0.64], ["sun_slope_z", -0.45], ["rain", 0.0], ["rain_wet", 0.0], ["sea_level", 0.0], ["tide_wet", 0.0]]:
		if not have.has(StringName(g[0])):
			RenderingServer.global_shader_parameter_add(g[0], RenderingServer.GLOBAL_VAR_TYPE_FLOAT, g[1])


## Which way a mesh's faces look, as a volume: positive when their fronts look outward (as
## they should), negative when the mesh is inside out. (Front faces are wound clockwise.)
static func facing_volume(mesh: Mesh, surf := 0) -> float:
	var arr := mesh.surface_get_arrays(surf)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if arr[Mesh.ARRAY_INDEX] == null or v.is_empty():
		return 0.0
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var mid := Vector3.ZERO
	for p in v:
		mid += p
	mid /= v.size()
	var vol := 0.0
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		vol += (a - mid).dot((v[idx[t + 2]] - a).cross(v[idx[t + 1]] - a))
	return vol / 6.0


## One of the two rock meshes from the .blend (Rocks/Boulders_001: eight boulders, each a
## ball of 128 x 24 quads) is inside out: its faces and normals look inward. In Blender both
## sides are drawn and nobody saw it; here the near wall is not drawn at all and one looks
## through it at the inside of the far wall and of the bottom: from the beach a dark rock,
## from the water a broken shell (seen in pictures of 2026-11-12: rocks that
## looked open or broken). Any mesh under Rocks that is inside out is turned right side out here
## (corners swapped, normals turned), and the small holes at its poles, where the ball's
## top and bottom rings were pulled apart, are closed.
## The coconuts in the crowns of the start beach's palms (Palms/*/Nuts*) have the same fault
## from the same file, and are turned too.
func _right_side_out() -> void:
	var which: Array = []
	var rocks := get_node_or_null("Rocks")
	if rocks:
		which.append_array(rocks.find_children("*", "MeshInstance3D", true, false))
	var palms := get_node_or_null("Palms")
	if palms:
		which.append_array(palms.find_children("Nuts*", "MeshInstance3D", true, false))
	# The dark masses behind the forest's edge and on the headland (Hills/Treeline_001,
	# Hills/Headland_001: sixty balls each, the body of the foliage from the .blend; the far
	# islands are built from copies of the second) are inside out as well, every ball of
	# them. Their open rims are left as they are (they are gaps between faces of thinned-out
	# balls, not poles). Turned, they are drawn smaller (MASS_SHRINK); their full size is
	# kept in the meta "solid" for the collision shapes (the volumes of "in the bushes").
	var hills := get_node_or_null("Hills")
	var masses := {}
	if hills:
		for mi: MeshInstance3D in hills.find_children("*", "MeshInstance3D", true, false):
			which.append(mi)
			masses[mi] = true
	for mi: MeshInstance3D in which:
		if mi.mesh == null or mi.name == "Feet" or mi.has_meta("turned"):
			continue
		var fixed := ArrayMesh.new()
		var solid := ArrayMesh.new()
		var turned := 0
		for surf in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(surf)
			if arr[Mesh.ARRAY_INDEX] != null and arr[Mesh.ARRAY_NORMAL] != null and facing_volume(mi.mesh, surf) < 0.0:
				arr = _turned(arr, not masses.has(mi))
				turned += 1
				if masses.has(mi):
					solid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
					arr = _drawn_in(arr, MASS_SHRINK)
			fixed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			fixed.surface_set_material(surf, mi.mesh.surface_get_material(surf))
			fixed.surface_set_name(surf, mi.mesh.surface_get_name(surf))
		if turned > 0:
			mi.mesh = fixed
			mi.set_meta("turned", turned)
			if solid.get_surface_count() > 0:
				# (what counts as "in the bushes" stays the size it was: _build_collision)
				mi.set_meta("solid", solid)


## The foliage's dark body is drawn smaller than it is: inside out, one saw the far side of
## each ball, well behind the leaves, and the forest's edge had depth. Right side out and
## at full size the near sides stand among the leaves, and from a distance, where the
## leaves are fewer, the edge of the forest is a row of smooth green balls. So every ball is
## drawn in about its own middle: its surface lies behind the leaves again. (Tried
## 2026-11-12: at 0.75 one ball still showed among the sparse leaves by the boulders south
## of the start, seen from the sea; at 0.6 none did, from the beach, the sea, above, at
## midday, golden hour and sunset, nor on the far islands.)
const MASS_SHRINK := 0.6


## Every separate part of the surface made smaller about its own middle, by the factor k.
func _drawn_in(arr: Array, k: float) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var link := PackedInt32Array()
	link.resize(v.size())
	var seen := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
		if not seen.has(key):
			seen[key] = i
		link[i] = seen[key]
	for t in range(0, idx.size(), 3):
		for e in 2:
			var ra := idx[t]
			while link[ra] != ra:
				ra = link[ra]
			var rb := idx[t + e + 1]
			while link[rb] != rb:
				rb = link[rb]
			if ra != rb:
				link[rb] = ra
	var sums := {}
	for i in v.size():
		var r := i
		while link[r] != r:
			r = link[r]
		link[i] = r
		if not sums.has(r):
			sums[r] = [Vector3.ZERO, 0]
		sums[r][0] += v[i]
		sums[r][1] += 1
	for i in v.size():
		var mid: Vector3 = (sums[link[i]][0] as Vector3) / float(sums[link[i]][1])
		v[i] = mid + (v[i] - mid) * k
	arr[Mesh.ARRAY_VERTEX] = v
	return arr


## The surface inside out: every triangle's corners the other way around, every normal
## turned; and every small open rim drawn together to its middle (the poles of a ball).
func _turned(arr: Array, close_poles := true) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in nr.size():
		nr[i] = -nr[i]
	for t in range(0, idx.size(), 3):
		var k := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = k
	if not close_poles:
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_INDEX] = idx
		return arr
	# the open rims: edges that belong to one triangle only (vertices at the same place
	# count as one), each with the way its triangle goes around
	var weld := PackedInt32Array()
	weld.resize(v.size())
	var seen := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
		if not seen.has(key):
			seen[key] = i
		weld[i] = seen[key]
	var count := {}
	var way := {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var a := weld[idx[t + k]]
			var b := weld[idx[t + (k + 1) % 3]]
			if a == b:
				continue
			var key := Vector2i(mini(a, b), maxi(a, b))
			count[key] = int(count.get(key, 0)) + 1
			way[key] = Vector2i(a, b)
	var next := {}
	for key: Vector2i in count:
		if int(count[key]) == 1:
			next[(way[key] as Vector2i).x] = (way[key] as Vector2i).y
	var closed := 0
	var done := {}
	for start: int in next:
		if done.has(start):
			continue
		var loop := PackedInt32Array()
		var cur := start
		while next.has(cur) and not done.has(cur):
			done[cur] = true
			loop.append(cur)
			cur = next[cur]
		if loop.size() < 3 or cur != start:
			continue
		var mid := Vector3.ZERO
		var normal := Vector3.ZERO
		for i in loop.size():
			mid += v[loop[i]]
		mid /= loop.size()
		# (the cap goes around the other way than the triangles along the rim, so that it
		# faces as they do)
		for i in loop.size():
			normal += (v[loop[(i + 1) % loop.size()]] - mid).cross(v[loop[i]] - mid)
		normal = -normal.normalized() if normal.length() > 0.0 else Vector3.UP
		var wide := 0.0
		for i in loop.size():
			wide = maxf(wide, v[loop[i]].distance_to(mid))
		if wide > 2.5:
			continue      # (not a pole: an opening that size wants more than a fan)
		# (drawn together to one point: the pole of the ball as it was meant. A fan over the
		# ragged ring left a puckered scar)
		var in_loop := {}
		for i in loop.size():
			in_loop[loop[i]] = true
		for i in v.size():
			if in_loop.has(weld[i]):
				v[i] = mid
				nr[i] = normal
		closed += 1
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## The big granite boulders at the south end of the start beach (Rocks, from the .blend) were
## made to be seen from the beach: each is a shell with a hole underneath, set on the sea
## floor of the original scene. Where the floor now lies lower, the outer ones hang a meter or
## two over it, and a snorkeler looks under them and into them. This gives every boulder
## that hangs a foot: the boulder's own outline a quarter of the way up, carried down into
## the ground as rock, a little wider and uneven toward the bottom (one mesh, `Feet`, a
## child of the boulders' node, so that it is solid too: _build_collision() takes every mesh
## under Rocks).
func _close_rocks(ls: Node) -> void:
	var rocks := get_node_or_null("Rocks")
	if rocks == null or ls == null or not ls.has_method("ground"):
		return
	for mi: MeshInstance3D in rocks.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Feet" or mi.mesh == null:
			continue
		for old_name: String in ["Feet", "Skirt"]:
			var old := mi.get_node_or_null(old_name)
			if old:
				mi.remove_child(old)
				old.free()
		var xf := mi.global_transform
		var inv := xf.affine_inverse()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var feet := 0
		for surf in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(surf)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_INDEX] == null:
				continue
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			# the single boulders: vertices joined by triangles (vertices at the same place
			# count as one)
			var link := PackedInt32Array()
			link.resize(v.size())
			var seen := {}
			for i in v.size():
				var key := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
				if not seen.has(key):
					seen[key] = i
				link[i] = seen[key]
			for t in range(0, idx.size(), 3):
				for k in 2:
					var ra := idx[t]
					while link[ra] != ra:
						ra = link[ra]
					var rb := idx[t + k + 1]
					while link[rb] != rb:
						rb = link[rb]
					if ra != rb:
						link[rb] = ra
			var parts := {}
			for i in v.size():
				var r := i
				while link[r] != r:
					r = link[r]
				link[i] = r
				# (a plain Array: a packed array taken out of a dictionary with a cast is a copy)
				if not parts.has(r):
					parts[r] = []
				(parts[r] as Array).append(xf * v[i])
			for r: int in parts:
				var pts: Array = parts[r]
				if pts.size() < 40:
					continue
				var lo := 1e9
				var hi := -1e9
				for p: Vector3 in pts:
					lo = minf(lo, p.y)
					hi = maxf(hi, p.y)
				var y0 := lo + 0.25 * (hi - lo)
				# its underside: does it hang over the sea floor anywhere?
				var under := PackedVector2Array()
				var hangs := 0.0
				for p: Vector3 in pts:
					if p.y <= y0:
						under.append(Vector2(p.x, p.z))
						var g: float = ls.ground(p.x, p.z)
						if g < 0.2:
							hangs = maxf(hangs, p.y - g)
				if hangs < 0.12 or under.size() < 6:
					continue
				# The foot goes down from where the boulder is widest, if that is under water
				# at any tide: then boulder and foot have one outline and read as one rock
				# with steep sides. (From a quarter of the way up, as it was first, a round
				# boulder bulges out over its foot like a mushroom over its stalk.) A boulder
				# whose widest part is above the water keeps the quarter: its look from the
				# beach is not to change.
				var full := _hull_area(pts, 1e9)
				for f: float in [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6]:
					var y1 := lo + f * (hi - lo)
					if y1 > -0.95:
						break
					y0 = y1
					if _hull_area(pts, y1) >= 0.94 * full:
						break
				under = PackedVector2Array()
				for p: Vector3 in pts:
					if p.y <= y0:
						under.append(Vector2(p.x, p.z))
				var hull := Geometry2D.convex_hull(under)
				var c := Vector2.ZERO
				for h in hull:
					c += h
				c /= hull.size()
				# rings from the outline down to the ground
				var n := 40
				var rings := 5
				var grid: Array = []
				for k in rings:
					grid.append([])
				for j in n:
					var ang := TAU * j / n
					var d := Vector2.from_angle(ang)
					# how far the outline lies from the middle this way
					var rad := 1e9
					for e in hull.size() - 1:
						var hit: Variant = Geometry2D.segment_intersects_segment(c, c + d * 200.0, hull[e], hull[e + 1])
						if hit != null:
							rad = minf(rad, c.distance_to(hit))
					if rad > 1e8:
						rad = 0.5
					var wob := 0.5 * sin(ang * 3.0 + float(r)) + 0.3 * sin(ang * 7.0 + 1.7 * float(r)) + 0.2 * sin(ang * 13.0)
					var foot := c + d * rad * (1.05 + 0.05 * wob)
					var bottom: float = minf(float(ls.ground(foot.x, foot.y)) - 0.5, y0 - 0.3)
					for k in rings:
						var f := float(k) / (rings - 1)
						# (the top ring lies inside the boulder; lower down it widens and goes uneven)
						var q := c + d * rad * (lerpf(0.97, 1.04, sqrt(f)) + 0.04 * wob * f + 0.02 * sin(ang * 9.0 + f * 5.0) * f)
						(grid[k] as Array).append(Vector3(q.x, lerpf(y0, bottom, f), q.y))
				var raw: Array = grid.duplicate(true)
				for k in rings:
					for j in n:
						var p: Vector3 = raw[k][j]
						var du: Vector3 = (raw[k][(j + 1) % n] as Vector3) - (raw[k][(j + n - 1) % n] as Vector3)
						var dv: Vector3 = (raw[mini(k + 1, rings - 1)][j] as Vector3) - (raw[maxi(k - 1, 0)][j] as Vector3)
						var nrm := du.cross(dv).normalized()
						if nrm.dot(Vector3(p.x - c.x, 0.0, p.z - c.y)) < 0.0:
							nrm = -nrm
						grid[k][j] = [p, nrm]
				for k in rings - 1:
					for j in n:
						var j1 := (j + 1) % n
						var quad := [grid[k][j], grid[k][j1], grid[k + 1][j1], grid[k + 1][j]]
						for tri: Array in [[0, 1, 2], [0, 2, 3]]:
							var pa: Vector3 = quad[tri[0]][0]
							var pb: Vector3 = quad[tri[1]][0]
							var pc: Vector3 = quad[tri[2]][0]
							# (front faces are clockwise: put the corners in the order the normals ask for)
							var front := (pc - pa).cross(pb - pa)
							var order: Array = tri if front.dot(quad[tri[0]][1]) >= 0.0 else [tri[0], tri[2], tri[1]]
							for o: int in order:
								st.set_normal(inv.basis * (quad[o][1] as Vector3))
								st.add_vertex(inv * (quad[o][0] as Vector3))
				feet += 1
		if feet == 0:
			continue
		var node := MeshInstance3D.new()
		node.name = "Feet"
		node.mesh = st.commit()
		node.material_override = mi.get_active_material(0)
		node.set_meta("count", feet)
		mi.add_child(node)


## The area of the outline, seen from above, of those of the points that lie below `top`.
func _hull_area(pts: Array, top: float) -> float:
	var flat := PackedVector2Array()
	for p: Vector3 in pts:
		if p.y <= top:
			flat.append(Vector2(p.x, p.z))
	if flat.size() < 3:
		return 0.0
	var hull := Geometry2D.convex_hull(flat)
	var area := 0.0
	for i in hull.size() - 1:
		area += hull[i].x * hull[i + 1].y - hull[i + 1].x * hull[i].y
	return absf(area) * 0.5


# ---------------------------------------------------------------- helpers
static func lin(r: float, g: float, b: float) -> Color:
	return Color(r, g, b).linear_to_srgb()


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _noise_tex(freq: float, size: int, normal := false, cellular := false, noise_seed := 0, bump := 8.0, octaves := 5) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = freq
	n.fractal_octaves = octaves
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	return t


func _shader_mat(path: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


# ---------------------------------------------------------------- materials
func _build_materials() -> void:
	_sea_globals()
	_far_twins.clear()
	var macro := _noise_tex(0.004, 512, false, false, 11, 8.0, 6)
	var sand_n := _noise_tex(0.05, 512, true, false, 3, 6.0, 4)

	_mats["Sand"] = _shader_mat("res://shaders/sand.gdshader", {
		"sand_albedo": _tex("res://assets/textures/sand_albedo.png"),
		"sand_wet_albedo": _tex("res://assets/textures/sand_wet_albedo.png"),
		"sand_normal": _tex("res://assets/textures/sand_normal.png") if _tex("res://assets/textures/sand_normal.png") else sand_n,
		"macro_noise": macro,
		"landmask": _tex("res://assets/textures/landmask.png"),
		"litter_albedo": _tex("res://assets/textures/litter_albedo.png"),
		"grass_albedo": _tex("res://assets/textures/grass_albedo.png"),
		"litter_normal": _tex("res://assets/textures/litter_normal.png"),
		"grass_normal": _tex("res://assets/textures/grass_normal.png"),
		"granite_albedo": _tex("res://assets/textures/granite_albedo.png"),
		"water_normal": _noise_tex(0.02, 256, true, false, 37, 6.0, 3),
		"sun_dir_world": SUN_TO.normalized(),
	})

	var granite := _tex("res://assets/textures/granite_albedo.png")
	_mats["SeyGranite"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": granite, "noise_tex": macro, "scale": 0.28,
		"tint": Color(0.93, 0.9, 0.88), "roughness": 0.72, "bump": 1.0, "moss": 0.4,
	})
	_mats["PalmBark"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 0.9,
		"tint": Color(0.82, 0.76, 0.68), "roughness": 0.85, "bump": 1.4, "waterline_effects": 0.0,
	})
	_mats["Driftwood"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 1.6,
		"tint": Color(0.72, 0.65, 0.56), "roughness": 0.9, "bump": 1.6, "waterline_effects": 0.0,
	})
	_mats["TakamakaBark"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 0.6,
		"tint": Color(0.62, 0.58, 0.52), "roughness": 0.85, "bump": 1.0, "waterline_effects": 0.0, "moss": 0.6,
	})

	_mats["BushLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.02, 0.07, 0.015), "color_b": lin(0.10, 0.27, 0.05),
		"backlight_color": lin(0.25, 0.42, 0.04),
	})
	_mats["BushLeafYellow"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.07, 0.16, 0.02), "color_b": lin(0.26, 0.38, 0.06),
		"backlight_color": lin(0.4, 0.5, 0.06),
	})
	_mats["TwigBrown"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.09, 0.055, 0.03), "color_b": lin(0.16, 0.1, 0.05),
		"backlight_color": lin(0.05, 0.03, 0.01), "shape_width": 0.2, "shape_power": 0.05, "vein": 0.0, "flutter": 0.0,
	})
	_mats["BushFlower"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.85, 0.78, 0.8), "color_b": lin(0.95, 0.9, 0.92),
		"backlight_color": lin(0.5, 0.45, 0.45), "is_flat_card": 1.0, "vein": 0.0, "hue_var": 0.05,
	})
	_mats["TakamakaFruit"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.25, 0.35, 0.08), "color_b": lin(0.35, 0.45, 0.1),
		"backlight_color": lin(0.1, 0.12, 0.02), "is_flat_card": 1.0, "vein": 0.0, "flutter": 0.0,
	})
	# beach naupaka (Scaevola): fleshy, glossy, light yellow-green rosettes
	_mats["ScaevolaLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.07, 0.17, 0.03), "color_b": lin(0.24, 0.42, 0.09),
		"backlight_color": lin(0.4, 0.55, 0.08), "roughness": 0.45, "specular_amount": 0.35,
		"shape_width": 0.5, "shape_power": 0.55, "vein": 0.5, "hue_var": 0.18,
	})
	# Pemphis: small gray-green leaves of the rocky shores
	_mats["SilverLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.09, 0.13, 0.07), "color_b": lin(0.26, 0.32, 0.2),
		"backlight_color": lin(0.2, 0.28, 0.1), "roughness": 0.6, "specular_amount": 0.3,
		"shape_width": 0.42, "shape_power": 0.45, "vein": 0.2, "hue_var": 0.2,
	})
	# jackfruit: big, dark, leathery and glossy
	_mats["JackLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.012, 0.05, 0.01), "color_b": lin(0.06, 0.19, 0.035),
		"backlight_color": lin(0.18, 0.3, 0.03), "roughness": 0.55, "specular_amount": 0.2,
		"shape_width": 0.44, "shape_power": 0.42, "vein": 0.8, "hue_var": 0.18, "flutter": 0.02,
	})
	# Pisonia (the seabird tree): large soft pale-green leaves
	_mats["PisoniaLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.1, 0.22, 0.04), "color_b": lin(0.32, 0.5, 0.12),
		"backlight_color": lin(0.45, 0.6, 0.1), "roughness": 0.5,
	})
	# (the grove's own trees, tools/assets7.py: pisonia(): leafy-twig cards like the takamaka's,
	# with bigger, softer, paler leaves; far away single big leaves)
	_mats["PisoniaSprig"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.07, 0.17, 0.03), "color_b": lin(0.26, 0.44, 0.1),
		"backlight_color": lin(0.42, 0.58, 0.09), "roughness": 0.5, "specular_amount": 0.2,
		"shape_width": 0.52, "shape_power": 0.5, "vein": 0.5, "hue_var": 0.2, "ao": 0.5,
		"sprig": 1.0, "sprig_aspect": 0.86, "sprig_leaf": 0.46, "sprig_angle": 1.05,
	})
	_mats["PisoniaSprigOld"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.25, 0.27, 0.04), "color_b": lin(0.5, 0.48, 0.1),
		"backlight_color": lin(0.6, 0.55, 0.1), "roughness": 0.5, "specular_amount": 0.2,
		"shape_width": 0.52, "shape_power": 0.5, "vein": 0.5, "hue_var": 0.25, "ao": 0.4,
		"sprig": 1.0, "sprig_aspect": 0.86, "sprig_leaf": 0.46, "sprig_angle": 1.05,
	})
	_mats["PisoniaLeafFar"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.07, 0.17, 0.03), "color_b": lin(0.26, 0.44, 0.1),
		"backlight_color": lin(0.42, 0.58, 0.09), "roughness": 0.5, "specular_amount": 0.2,
		"shape_width": 0.52, "shape_power": 0.45, "vein": 0.0, "hue_var": 0.2, "ao": 0.5,
	})
	# takamaka: stiff, dark, very glossy ellipses with a pale midrib
	_mats["TakamakaLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.02, 0.09, 0.016), "color_b": lin(0.1, 0.3, 0.05),
		"backlight_color": lin(0.25, 0.44, 0.045), "roughness": 0.42, "specular_amount": 0.32,
		"shape_width": 0.46, "shape_power": 0.5, "vein": 0.55, "hue_var": 0.2, "ao": 0.55,
		"sprig": 1.0, "sprig_aspect": 0.86, "sprig_leaf": 0.42, "sprig_angle": 1.05,
	})
	# (far away a takamaka's remaining cards are single big leaves: see tools/assets7.py)
	_mats["TakamakaLeafFar"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.02, 0.09, 0.016), "color_b": lin(0.1, 0.3, 0.05),
		"backlight_color": lin(0.25, 0.44, 0.045), "roughness": 0.42, "specular_amount": 0.32,
		"shape_width": 0.5, "shape_power": 0.45, "vein": 0.0, "hue_var": 0.2, "ao": 0.55,
	})
	# (the few yellowing takamaka twigs)
	_mats["TakamakaLeafOld"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.07, 0.16, 0.02), "color_b": lin(0.28, 0.38, 0.06),
		"backlight_color": lin(0.4, 0.5, 0.06), "roughness": 0.4, "specular_amount": 0.4,
		"shape_width": 0.46, "shape_power": 0.5, "vein": 0.55, "hue_var": 0.25, "ao": 0.4,
		"sprig": 1.0, "sprig_aspect": 0.86, "sprig_leaf": 0.42, "sprig_angle": 1.05,
	})
	# badamier (Indian almond): big leaves, widest near the tip, a few of them red before they fall
	_mats["BadamierLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.04, 0.15, 0.025), "color_b": lin(0.17, 0.4, 0.07),
		"backlight_color": lin(0.42, 0.6, 0.07), "roughness": 0.48, "specular_amount": 0.28,
		"shape_width": 0.47, "shape_power": 0.38, "skew": 1.5, "vein": 0.9, "hue_var": 0.22, "flutter": 0.025, "ao": 0.45,
	})
	_mats["BadamierRed"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.32, 0.035, 0.012), "color_b": lin(0.72, 0.24, 0.035),
		"backlight_color": lin(0.85, 0.3, 0.04), "roughness": 0.5, "specular_amount": 0.3,
		"shape_width": 0.47, "shape_power": 0.38, "skew": 1.5, "vein": 0.9, "hue_var": 0.25, "flutter": 0.025, "ao": 0.3,
	})
	# vacoa (screwpine): long keeled sword leaves; the old ones hang dead under the tuft
	_mats["VacoaLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.035, 0.15, 0.025), "color_b": lin(0.2, 0.42, 0.08),
		"backlight_color": lin(0.4, 0.58, 0.08), "roughness": 0.4, "specular_amount": 0.4,
		"blade": 1.0, "vein": 0.0, "hue_var": 0.2, "flutter": 0.012, "sway": 0.04,
	})
	_mats["VacoaDead"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.2, 0.13, 0.065), "color_b": lin(0.42, 0.3, 0.15),
		"backlight_color": lin(0.25, 0.15, 0.05), "roughness": 0.9, "specular_amount": 0.1,
		"blade": 1.0, "vein": 0.0, "hue_var": 0.2, "flutter": 0.006, "sway": 0.03,
	})
	var vfruit := StandardMaterial3D.new()
	vfruit.albedo_color = lin(0.78, 0.36, 0.05)
	vfruit.roughness = 0.6
	_mats["VacoaFruit"] = vfruit
	_mats["BadamierBark"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 0.8,
		"tint": Color(0.78, 0.74, 0.68), "roughness": 0.85, "bump": 0.9, "waterline_effects": 0.0, "moss": 0.35,
	})
	# Pisonia: pale gray, smooth, soft-wooded
	_mats["PisoniaBark"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 0.6,
		"tint": Color(0.92, 0.9, 0.84), "roughness": 0.8, "bump": 0.5, "waterline_effects": 0.0, "moss": 0.25,
	})
	_mats["VacoaBark"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 2.2,
		"tint": Color(0.86, 0.78, 0.66), "roughness": 0.85, "bump": 1.2, "waterline_effects": 0.0, "moss": 0.1,
	})
	# jackfruit: warty green-yellow skin
	var jf := StandardMaterial3D.new()
	jf.albedo_color = lin(0.4, 0.46, 0.1)
	jf.normal_enabled = true
	jf.normal_texture = _noise_tex(0.25, 256, true, true, 5, 14.0, 2)
	jf.normal_scale = 1.6
	jf.uv1_triplanar = true
	jf.uv1_scale = Vector3(6, 6, 6)
	jf.roughness = 0.7
	_mats["Jackfruit"] = jf
	# ferns of the forest floor and the bird's-nest fern
	_mats["FernLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.025, 0.09, 0.018), "color_b": lin(0.13, 0.33, 0.05),
		"backlight_color": lin(0.35, 0.55, 0.06), "shape_width": 0.44, "shape_power": 0.55,
		"vein": 0.35, "roughness": 0.6, "specular_amount": 0.25, "flutter": 0.02, "sway": 0.03,
	})
	_mats["NestFernLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.1, 0.28, 0.04), "color_b": lin(0.3, 0.55, 0.1),
		"backlight_color": lin(0.4, 0.6, 0.08), "shape_width": 0.48, "shape_power": 0.12,
		"vein": 1.0, "roughness": 0.32, "specular_amount": 0.45, "flutter": 0.01, "sway": 0.02,
	})
	# red mangrove: small, thick, glossy dark leaves; gray bark darkened by the tides
	_mats["MangroveLeaf"] = _shader_mat("res://shaders/leaf.gdshader", {
		"color_a": lin(0.012, 0.055, 0.01), "color_b": lin(0.07, 0.2, 0.035),
		"backlight_color": lin(0.16, 0.3, 0.035), "shape_width": 0.46, "shape_power": 0.45,
		"vein": 0.5, "roughness": 0.5, "specular_amount": 0.22,
	})
	_mats["MangroveBark"] = _shader_mat("res://shaders/triplanar_rock.gdshader", {
		"albedo_tex": _tex("res://assets/textures/palm_bark.png"), "noise_tex": macro, "scale": 1.3,
		"tint": Color(0.55, 0.5, 0.45), "roughness": 0.8, "bump": 0.8, "moss": 0.2,
	})
	# wet calcite flowstone of the stalactites
	var flow := StandardMaterial3D.new()
	flow.albedo_color = lin(0.8, 0.75, 0.66)
	flow.albedo_texture = _noise_tex(0.08, 256, false, false, 61, 8.0, 3)
	flow.uv1_triplanar = true
	flow.uv1_scale = Vector3(3, 3, 3)
	flow.normal_enabled = true
	flow.normal_texture = _noise_tex(0.08, 256, true, false, 61, 6.0, 3)
	flow.roughness = 0.16
	_mats["Flowstone"] = flow
	# endemic palms (palm_frond shader: sway grows with the distance from the crown)
	_mats["CocoDeMerLeaf"] = _shader_mat("res://shaders/palm_frond.gdshader", {
		"color_a": lin(0.13, 0.27, 0.05), "color_b": lin(0.36, 0.5, 0.12),
		"dry_color": lin(0.5, 0.42, 0.18), "backlight_color": lin(0.4, 0.5, 0.08),
		"sway_amount": 0.05, "flutter_amount": 0.015,
	})
	_mats["LatanierLeaf"] = _shader_mat("res://shaders/palm_frond.gdshader", {
		"color_a": lin(0.07, 0.22, 0.04), "color_b": lin(0.22, 0.42, 0.08),
		"dry_color": lin(0.55, 0.32, 0.12), "backlight_color": lin(0.35, 0.5, 0.06),
		"sway_amount": 0.12, "flutter_amount": 0.02,
	})
	_mats["PalmisteLeaf"] = _shader_mat("res://shaders/palm_frond.gdshader", {
		"color_a": lin(0.06, 0.22, 0.04), "color_b": lin(0.2, 0.42, 0.09),
		"dry_color": lin(0.5, 0.42, 0.18), "backlight_color": lin(0.35, 0.5, 0.08),
		"sway_amount": 0.15,
	})
	_mats["PalmDeadLeaf"] = _shader_mat("res://shaders/palm_frond.gdshader", {
		"color_a": lin(0.24, 0.17, 0.09), "color_b": lin(0.4, 0.3, 0.16),
		"dry_color": lin(0.3, 0.22, 0.12), "backlight_color": lin(0.2, 0.12, 0.05),
		"sway_amount": 0.03, "flutter_amount": 0.0,
	})
	var shaft := StandardMaterial3D.new()
	shaft.albedo_color = lin(0.5, 0.52, 0.42)
	shaft.roughness = 0.55
	_mats["PalmisteShaft"] = shaft
	# coco de mer: the green husk of the fruit on the palm, the bare dark double nut on the ground,
	# a weathered fallen fruit, and the brown male catkins (also the fruit stalks and bract caps)
	for cm in [["CocoDeMerNut", lin(0.2, 0.3, 0.07), 0.5, 0.5, 5.0], ["CocoDeMerSeed", lin(0.13, 0.075, 0.04), 0.55, 0.8, 9.0],
			["CocoDeMerHuskOld", lin(0.24, 0.2, 0.1), 0.85, 1.0, 5.0], ["CocoDeMerCatkin", lin(0.24, 0.15, 0.075), 0.85, 1.6, 22.0]]:
		var nut := StandardMaterial3D.new()
		nut.albedo_color = cm[1]
		nut.roughness = cm[2]
		nut.normal_enabled = true
		nut.normal_texture = _noise_tex(0.2 if cm[0] == "CocoDeMerCatkin" else 0.06, 256, true, cm[0] == "CocoDeMerCatkin", 83, 10.0, 3)
		nut.normal_scale = cm[3]
		nut.uv1_triplanar = true
		nut.uv1_scale = Vector3.ONE * cm[4]
		_mats[cm[0]] = nut
	_mats["TortShell"] =_shader_mat("res://shaders/tortoise_shell.gdshader", {})
	var tskin := StandardMaterial3D.new()
	tskin.albedo_color = lin(0.13, 0.12, 0.11)
	tskin.normal_enabled = true
	tskin.normal_texture = _noise_tex(0.18, 256, true, true, 41, 16.0, 2)
	tskin.normal_scale = 1.4
	tskin.uv1_triplanar = true
	tskin.uv1_scale = Vector3(14, 14, 14)
	tskin.roughness = 0.9
	_mats["TortSkin"] = tskin
	var teye := StandardMaterial3D.new()
	teye.albedo_color = Color(0.01, 0.008, 0.006)
	teye.roughness = 0.08
	_mats["TortEye"] = teye
	var nest := StandardMaterial3D.new()
	nest.albedo_color = lin(0.22, 0.16, 0.1)
	nest.roughness = 0.95
	_mats["NestTwig"] = nest
	_mats["PalmFrond"] = _shader_mat("res://shaders/palm_frond.gdshader", {
		"color_a": lin(0.08, 0.26, 0.04), "color_b": lin(0.30, 0.52, 0.10),
		"dry_color": lin(0.45, 0.36, 0.13), "backlight_color": lin(0.35, 0.5, 0.08),
	})

	# bush bodies peek through gaps in the leaves: give them a leafy, mottled look
	var bush := StandardMaterial3D.new()
	var bn := _noise_tex(0.06, 256, false, true, 77, 8.0, 3)
	var grad := Gradient.new()
	grad.set_color(0, lin(0.015, 0.05, 0.01))
	grad.set_color(1, lin(0.09, 0.24, 0.045))
	bn.color_ramp = grad
	bush.albedo_texture = bn
	bush.normal_enabled = true
	bush.normal_texture = _noise_tex(0.06, 256, true, true, 77, 12.0, 3)
	bush.normal_scale = 1.5
	bush.uv1_triplanar = true
	bush.uv1_world_triplanar = true
	bush.uv1_scale = Vector3(0.9, 0.9, 0.9)
	bush.roughness = 0.75
	bush.backlight_enabled = true
	bush.backlight = lin(0.05, 0.1, 0.01)
	# close up the leaves are dense enough on their own and the solid body would read as a green
	# blob (and wall you in when you push through a bush): dither it out near the camera
	bush.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	bush.distance_fade_min_distance = 8.0
	bush.distance_fade_max_distance = 25.0
	_mats["BushGreen"] = bush

	var coco := StandardMaterial3D.new()
	coco.albedo_color = lin(0.22, 0.16, 0.05)
	coco.roughness = 0.55
	_mats["Coconut"] = coco

	var mgleaf := StandardMaterial3D.new()
	mgleaf.albedo_color = lin(0.06, 0.24, 0.04)
	mgleaf.roughness = 0.55
	mgleaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	mgleaf.backlight_enabled = true
	mgleaf.backlight = lin(0.2, 0.35, 0.05)
	_mats["MGLeaf"] = mgleaf

	var mgflower := StandardMaterial3D.new()
	mgflower.albedo_color = lin(0.75, 0.18, 0.5)
	mgflower.roughness = 0.5
	mgflower.cull_mode = BaseMaterial3D.CULL_DISABLED
	mgflower.backlight_enabled = true
	mgflower.backlight = lin(0.6, 0.15, 0.4)
	_mats["MGFlower"] = mgflower

	var vine := StandardMaterial3D.new()
	vine.albedo_color = lin(0.09, 0.22, 0.05)
	vine.roughness = 0.8
	_mats["VineGreen"] = vine

	var sand_prints := StandardMaterial3D.new()
	sand_prints.albedo_color = lin(0.6, 0.53, 0.42)
	sand_prints.roughness = 0.95
	_mats["SandPrint"] = sand_prints

	# gray-brown, clearly darker than the sand; the shader moves the legs (driven by fauna.gd)
	_mats["CrabShell"] = _shader_mat("res://shaders/crab.gdshader", {"albedo": lin(0.16, 0.12, 0.075), "roughness": 0.6})
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.02, 0.02, 0.02)
	eye.roughness = 0.15
	_mats["CrabEye"] = eye
	var tw := StandardMaterial3D.new()
	tw.albedo_color = Color(0.97, 0.97, 0.97)
	tw.roughness = 0.7
	tw.cull_mode = BaseMaterial3D.CULL_DISABLED
	tw.backlight_enabled = true
	tw.backlight = Color(0.5, 0.5, 0.5)
	_mats["TernWhite"] = tw
	var tb := StandardMaterial3D.new()
	tb.albedo_color = Color(0.05, 0.05, 0.05)
	_mats["TernBlack"] = tb
	# bendable wings (assets/models/wings.glb, posed by flight.gd): arm, hand and tip color,
	# roughness, how much light shines through, feather lines, and a differently colored underside
	var tern_gray := Color(0.5, 0.52, 0.56)
	for w in [["Tern", tern_gray, tern_gray, Color(0.3, 0.31, 0.34), 0.7, 0.45, 1.0, Color(0.96, 0.96, 0.97)],
			["Noddy", lin(0.11, 0.075, 0.05), lin(0.06, 0.04, 0.03), lin(0.04, 0.028, 0.022), 0.8, 0.3, 1.0, null],
			["WhiteTern", lin(0.92, 0.93, 0.93), lin(0.92, 0.93, 0.93), lin(0.86, 0.88, 0.9), 0.75, 0.7, 0.7, null],
			["Frigate", lin(0.025, 0.025, 0.03), lin(0.025, 0.025, 0.03), lin(0.02, 0.02, 0.024), 0.45, 0.05, 1.0, null],
			["Bat", Color(0.035, 0.025, 0.02), Color(0.035, 0.025, 0.02), Color(0.03, 0.022, 0.018), 0.8, 2.5, 0.0, null]]:
		var wm := _shader_mat("res://shaders/wing.gdshader", {"color_in": w[1], "color_out": w[2],
			"color_tip": w[3], "roughness": w[4], "backlight": w[5], "feathers": w[6]})
		if w[7] != null:
			wm.set_shader_parameter("color_under", w[7])
			wm.set_shader_parameter("under", 1.0)
		_mats["Wing" + w[0]] = wm
	# plumage of the seabirds' bodies (shaders/bird.gdshader paints it from the body's UVs)
	var bird := "res://shaders/bird.gdshader"
	var white := lin(0.92, 0.93, 0.93)
	var brown := lin(0.11, 0.075, 0.05)
	var frigate := lin(0.025, 0.025, 0.03)
	_mats["PlumageWhiteTern"] = _shader_mat(bird, {"upper": white, "under": white})
	# brown noddy: the pale ashy forehead fades back over the crown into the brown
	_mats["PlumageNoddy"] = _shader_mat(bird, {"upper": brown, "under": brown, "roughness": 0.8,
		"cap": lin(0.72, 0.71, 0.69), "cap_from": 0.0, "cap_to": 0.2, "cap_soft": 0.15, "cap_side": 0.66})
	_mats["PlumageFrigateM"] = _shader_mat(bird, {"upper": frigate, "under": frigate, "roughness": 0.4})
	# the female frigatebird's white breast
	_mats["PlumageFrigateF"] = _shader_mat(bird, {"upper": frigate, "under": frigate, "roughness": 0.45,
		"breast": lin(0.85, 0.85, 0.83), "breast_from": 0.1, "breast_to": 0.42})
	# greater crested tern: white with a gray back and a black cap behind a white forehead
	_mats["PlumageCrestedTern"] = _shader_mat(bird, {"upper": tern_gray, "under": Color(0.96, 0.96, 0.97), "roughness": 0.7,
		"upper_from": 0.25, "under_edge": 0.05, "cap": Color(0.03, 0.03, 0.035), "cap_from": 0.06, "cap_to": 0.2,
		"cap_soft": 0.03, "cap_side": 0.45})
	var sac := StandardMaterial3D.new()
	sac.albedo_color = lin(0.72, 0.02, 0.015)
	sac.roughness = 0.3
	sac.backlight_enabled = true
	sac.backlight = Color(0.22, 0.012, 0.008)   # the stretched skin glows a little against the light
	_mats["FrigateSac"] = sac

	_mats["Ocean"] = _shader_mat("res://shaders/ocean.gdshader", {
		"normal_a": _noise_tex(0.012, 512, true, false, 21, 10.0, 4),
		"normal_b": _noise_tex(0.02, 512, true, false, 37, 6.0, 3),
		"foam_tex": _noise_tex(0.03, 512, false, true, 5, 8.0, 3),
	})


func get_material(mat_name: String) -> Material:
	if _mats.is_empty():
		_build_materials()
	return _mats.get(mat_name)


func _apply_materials(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var key := src.resource_name
			if _mats.has(key):
				mi.set_surface_override_material(s, _mats[key])
	for c in n.get_children():
		_apply_materials(c)


# ---------------------------------------------------------------- LOD
## Leaves further away than this are drawn without soft (alpha-to-coverage) edges. That
## antialiasing is what foliage costs most: without it on the distant LODs the view over the whole
## island from the summit runs about twice as fast, and at that distance nobody sees the difference.
const FAR_LEAF_DIST := 25.0
var _far_twins := {}

## The same material on the far variant of the leaf shader.
func far_material(m: Material) -> Material:
	var sm := m as ShaderMaterial
	if sm == null or sm.shader == null or sm.shader.resource_path != "res://shaders/leaf.gdshader":
		return m
	if not _far_twins.has(sm):
		var twin := sm.duplicate() as ShaderMaterial
		twin.shader = load("res://shaders/leaf_far.gdshader")
		_far_twins[sm] = twin
	return _far_twins[sm]


## Gives every distant leaf LOD under n (anything that only appears beyond FAR_LEAF_DIST, and the
## offshore islands) the far variant of its materials.
func _far_materials(n: Node, always: bool) -> void:
	if n.name == "Islands":
		always = true
	var gi := n as GeometryInstance3D
	if gi and (always or gi.visibility_range_begin >= FAR_LEAF_DIST):
		if gi.material_override:
			gi.material_override = far_material(gi.material_override)
		var mi := n as MeshInstance3D
		if mi and mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m:
					mi.set_surface_override_material(s, far_material(m))
	for c in n.get_children():
		_far_materials(c, always)


const LEAF_LOD_DIST := 34.0
const LEAF_LOD2_DIST := 95.0
const FROND_LOD_DIST := 30.0

func _setup_lods() -> void:
	for pair in [["Leaves", 0.0, LEAF_LOD_DIST], ["LeavesLod", LEAF_LOD_DIST, LEAF_LOD2_DIST], ["LeavesLod2", LEAF_LOD2_DIST, 0.0]]:
		var root := get_node_or_null(pair[0])
		if root == null:
			continue
		for m in root.find_children("*", "MeshInstance3D", true, false):
			var gi := m as GeometryInstance3D
			gi.visibility_range_begin = pair[1]
			gi.visibility_range_begin_margin = 3.0 if pair[1] > 0.0 else 0.0
			gi.visibility_range_end = pair[2]
			gi.visibility_range_end_margin = 3.0 if pair[2] > 0.0 else 0.0
	# near the camera, the dense leaves skip the shadow pass; a shadow-only copy of the
	# sparser LOD1 casts the dappled shade instead (4x fewer leaves in 4 cascades).
	var hi_root := get_node_or_null("Leaves")
	var lo_root := get_node_or_null("LeavesLod")
	if hi_root and lo_root and not lo_root.has_node("ShadowProxies"):
		for m in hi_root.find_children("*", "MeshInstance3D", true, false):
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var proxies := Node3D.new()
		proxies.name = "ShadowProxies"
		lo_root.add_child(proxies)
		for m in lo_root.find_children("L_*", "MeshInstance3D", true, false):
			var src := m as MeshInstance3D
			var sp := MeshInstance3D.new()
			sp.mesh = src.mesh
			for si in src.mesh.get_surface_count():
				sp.set_surface_override_material(si, src.get_surface_override_material(si))
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sp.visibility_range_end = LEAF_LOD_DIST
			sp.visibility_range_end_margin = 3.0
			proxies.add_child(sp)
			sp.global_transform = src.global_transform
	var t := get_node_or_null("Terrain")
	if t:
		for m in t.find_children("*", "MeshInstance3D", true, false):
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# palm frond LODs (decimated meshes appear beyond FROND_LOD_DIST)
	var lod_scene := load("res://assets/models/fronds_lod.glb") as PackedScene
	var palms := get_node_or_null("Palms")
	if lod_scene == null or palms == null:
		return
	var tmp := lod_scene.instantiate()
	var lod_meshes := {}
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		var digits := (m.name as String).trim_prefix("PalmFronds").get_slice("_", 0)
		lod_meshes[int(digits)] = (m as MeshInstance3D).mesh
	tmp.free()
	for f in palms.find_children("Fronds*", "MeshInstance3D", true, false):
		var fm := f as MeshInstance3D
		var idx := int((fm.name as String).trim_prefix("Fronds"))
		if not lod_meshes.has(idx) or fm.get_parent().has_node("FrondsLod"):
			continue
		var lod := MeshInstance3D.new()
		lod.name = "FrondsLod"
		lod.mesh = lod_meshes[idx]
		lod.material_override = _mats["PalmFrond"]
		lod.transform = fm.transform
		lod.visibility_range_begin = FROND_LOD_DIST
		lod.visibility_range_begin_margin = 3.0
		fm.visibility_range_end = FROND_LOD_DIST
		fm.visibility_range_end_margin = 3.0
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fm.get_parent().add_child(lod)
		var sh := MeshInstance3D.new()
		sh.name = "FrondsShadow"
		sh.mesh = lod.mesh
		sh.material_override = lod.material_override
		sh.transform = fm.transform
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sh.visibility_range_end = FROND_LOD_DIST
		sh.visibility_range_end_margin = 3.0
		fm.get_parent().add_child(sh)


# ---------------------------------------------------------------- sun
func _setup_sun() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		var d := -SUN_TO.normalized()
		sun.global_transform.basis = Basis.looking_at(d, Vector3.UP)


# ---------------------------------------------------------------- ocean
func _axis(fine_min: float, fine_max: float, step: float, far: float, growth: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	# coarse part below
	var neg := PackedFloat32Array()
	var s := step
	var x := fine_min
	while x > -far:
		s *= growth
		x -= s
		neg.append(x)
	neg.reverse()
	a.append_array(neg)
	x = fine_min
	while x <= fine_max + 0.001:
		a.append(x)
		x += step
	s = step
	x = a[a.size() - 1]
	while x < far:
		s *= growth
		x += s
		a.append(x)
	return a


## Like _axis but with several contiguous fine segments [start, end, step].
func _axis_segments(segs: Array, far: float, growth: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	var neg := PackedFloat32Array()
	var s: float = segs[0][2]
	var x: float = segs[0][0]
	while x > -far:
		s *= growth
		x -= s
		neg.append(x)
	neg.reverse()
	a.append_array(neg)
	for seg in segs:
		x = seg[0]
		while x < seg[1] - 0.001:
			a.append(x)
			x += seg[2]
	a.append(segs[segs.size() - 1][1])
	s = segs[segs.size() - 1][2]
	x = a[a.size() - 1]
	while x < far:
		s *= growth
		x += s
		a.append(x)
	return a


func _build_ocean() -> void:
	var ocean := get_node_or_null("Ocean") as MeshInstance3D
	if ocean == null:
		ocean = MeshInstance3D.new()
		ocean.name = "Ocean"
		add_child(ocean)
	var cache := "res://assets/ocean_mesh.res"
	var mesh: ArrayMesh
	if ResourceLoader.exists(cache):
		mesh = load(cache)
	else:
		var xs := _axis_segments([[-215.0, -150.0, 0.7], [-150.0, -40.0, 0.8], [-40.0, 75.0, 0.45]], 30000.0, 1.15)
		var zs := _axis_segments([[-268.0, -215.0, 0.9], [-215.0, 175.0, 0.55], [175.0, 268.0, 0.9]], 30000.0, 1.15)
		var nx := xs.size()
		var nz := zs.size()
		var verts := PackedVector3Array()
		verts.resize(nx * nz)
		var i := 0
		for zi in nz:
			for xi in nx:
				verts[i] = Vector3(xs[xi], 0.0, zs[zi])
				i += 1
		var idx := PackedInt32Array()
		idx.resize((nx - 1) * (nz - 1) * 6)
		var k := 0
		for zi in nz - 1:
			for xi in nx - 1:
				var a := zi * nx + xi
				var b := a + 1
				var c := a + nx
				var d := c + 1
				idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
				idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
				k += 6
		var norms := PackedVector3Array()
		norms.resize(verts.size())
		norms.fill(Vector3.UP)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.custom_aabb = AABB(Vector3(-30000, -3, -30000), Vector3(60000, 6, 60000))
		ResourceSaver.save(mesh, cache)
	ocean.mesh = mesh
	ocean.material_override = _mats["Ocean"]
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.extra_cull_margin = 4.0


# ---------------------------------------------------------------- collision
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	add_child(body)
	# bushes are not solid (you push through them); they sit on layer 2 so the
	# player can tell when it is inside one
	var bush_body := StaticBody3D.new()
	bush_body.name = "BushVolumes"
	bush_body.collision_layer = 2
	bush_body.collision_mask = 0
	add_child(bush_body)
	for path in ["Terrain", "Rocks", "Hills", "Palms", "Groundcover"]:
		var root := get_node_or_null(path)
		if root == null:
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if path == "Groundcover" and not m.name.begins_with("Takamaka"):
				continue
			if path == "Palms" and not m.name.begins_with("Trunk"):
				continue
			var shape := ((m.get_meta("solid") as Mesh) if m.has_meta("solid") else m.mesh).create_trimesh_shape()
			var cs := CollisionShape3D.new()
			cs.shape = shape
			# (for the rain's shadow, scripts/weather.gd: 1 the ground, 2 rock that can keep rain off)
			cs.set_meta("rain", 1 if path == "Terrain" else (2 if path == "Rocks" else 0))
			(bush_body if path == "Hills" else body).add_child(cs)
			cs.global_transform = m.global_transform
