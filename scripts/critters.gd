extends Node3D
## Small life added in the eighth session (the node is created by island_life.gd, after the
## landscape has been built):
##  * rock crabs on the boulders and the granite at the waterline (they sit in the splash zone
##    and slip around to the far side of their rock when someone comes close),
##  * a few palm spiders in their golden orb webs between two trunks, above head height,
##  * termite nests on palm trunks, with their covered runways down to the ground,
##  * the day roost of the flying foxes: a tree they hang in, head down, until dusk,
##  * a few mudskippers on the wet sand where the mangroves stand thick,
##  * the rare Seychelles frog on the damp ground and the rocks by the stream's pools,
##  * the sound of the stream at its pools, and of the surf on the reef.

const A := "res://assets/audio/"
const Heights := preload("res://scripts/heights.gd")
const SmallModels := preload("res://scripts/small_models.gd")

var _player: Node3D
var _ls: Node
var _world: Node
var _rng := RandomNumberGenerator.new()
var _frame := 0


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_world = ls.get_parent()
	_rng.seed = 20261111
	_setup_webs()
	_setup_termites()
	_setup_roost()
	_setup_insects()
	_setup_mudskippers()
	_setup_sounds()


func _night() -> float:
	var dc := get_node_or_null("../../DayCycle")
	return dc.night if dc else 0.0


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _process(delta: float) -> void:
	_update_webs(delta)
	_update_termites(delta)
	_update_roost(delta)
	_update_insects(delta)
	_update_mudskippers(delta)
	_update_frogs(delta)
	_update_sounds(delta)


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_place_rock_crabs()
		_place_frogs()
	if _frame > 20:
		_update_rock_crabs(delta)


# ================================================================== rock crabs
## Rock crabs (Grapsus) live where granite meets the sea: dark, flat, quick. Each one sits on a
## rock near the waterline; it sidles a few centimeters now and then, and when someone comes
## within a few meters it runs over the rock to the side away from them.
var rock_crabs: Array = []

func _place_rock_crabs() -> void:
	var crab_mesh: ArrayMesh = SmallModels.crab()
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = load("res://shaders/crab.gdshader")
	shell_mat.set_shader_parameter("albedo", Color(0.15, 0.19, 0.15))
	shell_mat.set_shader_parameter("roughness", 0.4)
	# rocks at the waterline: [center, radius, how many crabs to try for]
	var sites: Array = [[Vector3(8, 0, -70), 15.0, 7], [Vector3(-184, 0, -15), 17.0, 9], [Vector3(-181, 0, 9), 8.0, 3], [Vector3(-181, 0, -40), 8.0, 3]]
	for b in _ls.boulder_spots:
		var c: Vector3 = b[0]
		var g: float = _ls.ground(c.x, c.z)
		if float(b[1]) >= 1.4 and g > -1.3 and g < 1.3:
			sites.append([c, float(b[1]) * 0.6, 2 if float(b[1]) > 3.0 else 1])
	for s in sites:
		var c: Vector3 = s[0]
		var made := 0
		for k in 30:
			if made >= int(s[2]) or rock_crabs.size() >= 60:
				break
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * float(s[1])
			var p := Vector3(c.x + cos(a) * r, 0, c.z + sin(a) * r)
			var hit := _ray(Vector3(p.x, 9.0, p.z), Vector3(p.x, -1.0, p.z))
			if hit.is_empty():
				continue
			var hp: Vector3 = hit["position"]
			var n: Vector3 = hit["normal"]
			var on_rock: bool = hp.y - float(_ls.ground(p.x, p.z)) > 0.25 or _ls.rocky(Vector2(p.x, p.z), 0.3)
			# (above high water: the tide comes up to +0.3 m)
			if not on_rock or hp.y < 0.42 or hp.y > 2.4 or n.y < 0.25:
				continue
			var near := false
			for o in rock_crabs:
				if (o["pos"] as Vector3).distance_to(hp) < 0.7:
					near = true
			if near:
				continue
			var root := Node3D.new()
			add_child(root)
			var size := _rng.randf_range(0.28, 0.4)
			var shell := MeshInstance3D.new()
			shell.mesh = crab_mesh
			shell.material_override = shell_mat
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shell.extra_cull_margin = 0.1
			root.add_child(shell)
			var yaw := _rng.randf() * TAU
			rock_crabs.append({"node": root, "shell": shell, "size": size, "pos": hp, "n": n, "side": Vector3(cos(yaw), 0, sin(yaw)),
				"state": "sit", "timer": _rng.randf_range(1.0, 8.0), "v": 0.0, "gait": _rng.randf() * TAU, "dir": Vector3.ZERO})
			_pose_crab(rock_crabs[rock_crabs.size() - 1])
			made += 1


func _pose_crab(d: Dictionary) -> void:
	var n: Vector3 = d["n"]
	var x: Vector3 = d["side"]
	x = (x - n * x.dot(n)).normalized()
	if x.length() < 0.5:
		x = n.cross(Vector3.FORWARD).normalized()
	d["side"] = x
	var z := x.cross(n).normalized()
	(d["node"] as Node3D).global_transform = Transform3D(Basis(x, n, z).scaled(Vector3.ONE * float(d["size"])), d["pos"])


func _update_rock_crabs(delta: float) -> void:
	if _player == null:
		return
	var pp := _player.global_position + Vector3(0, 0.9, 0)
	for d: Dictionary in rock_crabs:
		var pos: Vector3 = d["pos"]
		var dist := pos.distance_to(pp)
		if dist > 45.0:
			continue
		d["timer"] -= delta
		var want := 0.0
		match d["state"]:
			"sit":
				if dist < 4.2:
					d["state"] = "bolt"
					d["timer"] = _rng.randf_range(1.0, 2.2)
					var away := (pos - pp)
					away.y -= 0.6          # ... and down toward the water
					d["dir"] = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
				elif d["timer"] <= 0.0:
					d["state"] = "sidle"
					d["timer"] = _rng.randf_range(0.3, 1.2)
					var a := _rng.randf() * TAU
					d["dir"] = Vector3(cos(a), 0, sin(a))
			"sidle":
				want = 0.16
				if dist < 4.2:
					d["state"] = "sit"
					d["timer"] = 0.0
				elif d["timer"] <= 0.0:
					d["state"] = "sit"
					d["timer"] = _rng.randf_range(2.0, 11.0)
			"bolt":
				want = 1.3
				if d["timer"] <= 0.0:
					d["state"] = "wait"
					d["timer"] = _rng.randf_range(5.0, 10.0)
			"wait":
				if d["timer"] <= 0.0 and dist > 5.5:
					d["state"] = "sit"
					d["timer"] = _rng.randf_range(1.0, 6.0)
				elif dist < 1.6:
					d["state"] = "bolt"
					d["timer"] = 1.2
					d["dir"] = (pos - pp).normalized()
		d["v"] = move_toward(d["v"], want, delta * 8.0)
		var v: float = d["v"]
		var n: Vector3 = d["n"]
		if v > 0.005:
			var dir: Vector3 = d["dir"]
			var tang := dir - n * dir.dot(n)
			if tang.length() < 0.05:
				tang = n.cross(Vector3.RIGHT)
			tang = tang.normalized()
			var np := pos + tang * v * delta
			var hit := _ray(np + n * 0.25, np - n * 0.35)
			if hit.is_empty():
				hit = _ray(np + n * 0.25, np + n * 0.25 - Vector3.UP * 0.9)
			if hit.is_empty() or (hit["position"] as Vector3).y < float(_ls.sea) + 0.04:
				# the water, or the end of the rock: stop here
				d["v"] = 0.0
				if d["state"] == "bolt":
					d["dir"] = dir.rotated(Vector3.UP, 1.2 * (1.0 if _rng.randf() < 0.5 else -1.0))
			else:
				d["pos"] = hit["position"]
				d["n"] = n.lerp(hit["normal"], 0.35).normalized()
				# crabs run sideways: one side leads
				var side: Vector3 = d["side"]
				d["side"] = side.lerp(tang if side.dot(tang) >= 0.0 else -tang, 1.0 - exp(-10.0 * delta)).normalized()
				d["gait"] = fmod(float(d["gait"]) + v * 44.9 / float(d["size"]) * delta * (1.0 if side.dot(tang) >= 0.0 else -1.0), TAU)
			_pose_crab(d)
		var shell: MeshInstance3D = d["shell"]
		if shell:
			shell.set_instance_shader_parameter("gait", d["gait"])
			shell.set_instance_shader_parameter("stride", clampf(v / (0.3 * float(d["size"])), 0.0, 1.0))
			shell.set_instance_shader_parameter("tuck", 0.25 if d["state"] == "wait" else 0.0)
			shell.set_instance_shader_parameter("lift", -0.02 if d["state"] == "wait" else 0.0)


# ================================================================== palm spiders
## The red-legged golden orb-weaver ("palm spider"): a big, harmless spider that hangs head down
## in the middle of a meter-wide golden web strung between two trunks. On the real islands they
## are everywhere; here there are only a handful, each well above head height and none across
## the ridge, the way to the grotto or the stream.
const WEB_COUNT := 24
var webs: Array = []
var _web_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D

## Everything a web can hang between: palm trunks and the trunks of the forest trees.
## [base, the palm's trunk data or {}, the tree's entry or {}]
func _posts() -> Array:
	var out: Array = []
	for t in _ls.palm_trunks:
		var pts: PackedVector3Array = t["pts"]
		if pts[pts.size() - 1].y - pts[0].y >= 4.6:
			out.append([pts[0], t, {}])
	for t in _ls.tree_spots:
		var kind := String(t["kind"])
		if t.get("colony", false) or not (kind.begins_with("Taka") or kind.begins_with("Bad")):
			continue
		out.append([(t["xf"] as Transform3D).origin, {}, t])
	return out


## Where a tree's trunk is at height h above its foot: the middle of its bark there, and its radius.
func _tree_at(t: Dictionary, h: float) -> Array:
	var xf: Transform3D = t["xf"]
	var bark: Mesh = _ls._tree_parts.get(String(t["kind"]) + "Bark")
	var c := xf.origin + Vector3(0, h, 0)
	if bark == null:
		return [c, 0.2]
	var sum := Vector3.ZERO
	var n := 0
	var near: Array = []
	for v: Vector3 in bark.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var w := xf * v
		if absf(w.y - c.y) < 0.2 and Vector2(w.x - c.x, w.z - c.z).length() < 1.2:
			sum += w
			n += 1
			near.append(w)
	if n < 3:
		return [c, 0.2]
	var mid := sum / n
	mid.y = c.y
	var r := 0.0
	for w: Vector3 in near:
		r += Vector2(w.x - mid.x, w.z - mid.z).length() / n
	return [mid, r]


func _setup_webs() -> void:
	var tex := load("res://assets/textures/spider_web.png") as Texture2D
	if tex == null:
		return
	_web_mat = StandardMaterial3D.new()
	_web_mat.albedo_texture = tex
	_web_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_web_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_web_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_web_mat.albedo_color = Color(1, 1, 1, 0.42)
	_web_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_web_mat.distance_fade_min_distance = 26.0
	_web_mat.distance_fade_max_distance = 14.0
	_line_mat = StandardMaterial3D.new()
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(1.0, 0.92, 0.62, 0.4)
	_line_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_line_mat.distance_fade_min_distance = 18.0
	_line_mat.distance_fade_max_distance = 9.0
	var spider := _spider_mesh()
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.vertex_color_is_srgb = true
	smat.roughness = 0.45
	var posts := _posts()
	# pairs of trunks 2.4 to 5.5 m apart, away from the walker's ways
	var pairs: Array = []
	for i in posts.size():
		var a: Vector3 = posts[i][0]
		for j in range(i + 1, posts.size()):
			var b: Vector3 = posts[j][0]
			var dh := Vector2(a.x - b.x, a.z - b.z).length()
			if dh < 2.4 or dh > 5.5 or absf(a.y - b.y) > 1.0 or a.y < 1.0:
				continue
			var mid := (a + b) * 0.5
			var m2 := Vector2(mid.x, mid.z)
			if _ls.trail_distance(m2) < 5.0 or _ls.cave_way(m2) < 5.0 or _ls.stream_dist(m2) < 3.0:
				continue
			pairs.append([i, j, mid])
	# spread over the whole island, never two close together
	for i in range(pairs.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp: Array = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = tmp
	var used: Array = []
	for pr in pairs:
		if webs.size() >= WEB_COUNT:
			break
		var mid: Vector3 = pr[2]
		var free := true
		for u: Vector3 in used:
			if u.distance_to(mid) < 17.0:
				free = false
		if not free:
			continue
		used.append(mid)
		_make_web(posts[pr[0]], posts[pr[1]], spider, smat)


## Point on a palm trunk's axis at height h above its base, and the trunk's radius there.
func _trunk_at(t: Dictionary, h: float) -> Array:
	var pts: PackedVector3Array = t["pts"]
	var rad: PackedFloat32Array = t["r"]
	for i in pts.size() - 1:
		if pts[i + 1].y - pts[0].y >= h:
			var k := clampf((pts[0].y + h - pts[i].y) / maxf(pts[i + 1].y - pts[i].y, 0.01), 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], k), lerpf(rad[i], rad[i + 1], k)]
	return [pts[pts.size() - 1], rad[rad.size() - 1]]


func _make_web(post_a: Array, post_b: Array, spider: Mesh, smat: Material) -> void:
	# between palms well above head height; a forest tree has no wood below 2.7 m, so there the
	# web hangs just under its lowest limbs (its lower edge still above a walker's head)
	var palms: bool = (post_a[2] as Dictionary).is_empty() and (post_b[2] as Dictionary).is_empty()
	var h := _rng.randf_range(2.9, 3.6) if palms else _rng.randf_range(2.5, 2.7)
	var size := _rng.randf_range(0.95, 1.3) if palms else _rng.randf_range(0.9, 1.05)
	var hb := h + _rng.randf_range(-0.15, 0.15)
	var pa: Array = _trunk_at(post_a[1], h) if (post_a[2] as Dictionary).is_empty() else _tree_at(post_a[2], h)
	var pb: Array = _trunk_at(post_b[1], hb) if (post_b[2] as Dictionary).is_empty() else _tree_at(post_b[2], hb)
	var a: Vector3 = pa[0]
	var b: Vector3 = pb[0]
	var along := (b - a)
	var span := along.length()
	along /= span
	a += along * float(pa[1])
	b -= along * float(pb[1])
	var center := a.lerp(b, _rng.randf_range(0.4, 0.6))
	var up := (Vector3.UP - along * along.y).normalized()
	var nrm := along.cross(up).normalized()
	var root := Node3D.new()
	root.name = "Web%d" % webs.size()
	add_child(root)
	root.global_transform = Transform3D(Basis(along, up, nrm), center)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var web := MeshInstance3D.new()
	web.mesh = quad
	web.material_override = _web_mat
	web.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(web)
	# the threads that hold it: from the frame to both trunks, above and below
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var la := root.global_transform.affine_inverse() * a
	var lb := root.global_transform.affine_inverse() * b
	var r := size * 0.47
	for e in [[la, -1.0], [lb, 1.0]]:
		var end: Vector3 = e[0]
		for dy in [0.75, -0.6]:
			im.surface_add_vertex(Vector3(float(e[1]) * r * 0.75, r * dy, 0))
			im.surface_add_vertex(end + Vector3(0, r * dy * 1.6, 0))
		im.surface_add_vertex(Vector3(float(e[1]) * r, 0, 0))
		im.surface_add_vertex(end)
	im.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = im
	lines.material_override = _line_mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lines)
	# the spider at the hub (the hub of the texture lies above the middle), head down
	var sp := MeshInstance3D.new()
	sp.mesh = spider
	sp.material_override = smat
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_range_end = 30.0
	web.add_child(sp)      # (it rides the web when the wind moves it)
	sp.position = Vector3(0, size * 0.1, 0.004)
	sp.scale = Vector3.ONE * _rng.randf_range(1.25, 1.6)
	webs.append({"node": root, "web": web, "spider": sp, "seed": _rng.randf() * TAU, "t": 0.0, "twitch": _rng.randf_range(4.0, 20.0)})


func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, col2: Color) -> void:
	var rings := 7
	var segs := 10
	for i in rings:
		for j in segs:
			var quad: Array = []
			for k in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + k[0]) / rings
				var ph := TAU * float(j + k[1]) / segs
				var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				quad.append([c + d * r, d, col.lerp(col2, smoothstep(-0.2, 0.6, d.z))])
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_color(quad[idx][2])
				st.set_normal((quad[idx][1] as Vector3).normalized())
				st.add_vertex(quad[idx][0])


func _limb(st: SurfaceTool, pts: Array, r0: float, r1: float, cols: Array) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var t := (b - a).normalized()
		var u := t.cross(Vector3(0.3, 0.2, 1.0)).normalized()
		var v := t.cross(u)
		var ra := lerpf(r0, r1, float(i) / (pts.size() - 1))
		var rb := lerpf(r0, r1, float(i + 1) / (pts.size() - 1))
		for k in 4:
			var a0 := TAU * k / 4.0
			var a1 := TAU * (k + 1) / 4.0
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var quad := [[a + d0 * ra, d0], [a + d1 * ra, d1], [b + d1 * rb, d1], [b + d0 * rb, d0]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(cols[i])
				st.set_normal(quad[idx][1])
				st.add_vertex(quad[idx][0])


## The spider, built once: in the plane of the web (x right, y up, z toward the viewer), head down.
func _spider_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# long abdomen: silver-gray above with yellow flanks; small dark head and chest
	# (the female: a long dark abdomen with a pale band, a small black head and chest with
	# silver hair, and very long legs, orange with black joints and black feet)
	_ellipsoid(st, Vector3(0, 0.021, 0.008), Vector3(0.0085, 0.018, 0.008), Color(0.05, 0.05, 0.05), Color(0.42, 0.4, 0.3))
	_ellipsoid(st, Vector3(0, -0.006, 0.006), Vector3(0.0065, 0.0078, 0.005), Color(0.03, 0.03, 0.03), Color(0.45, 0.45, 0.45))
	var orange := Color(0.93, 0.48, 0.05)
	var black := Color(0.02, 0.018, 0.016)
	# legs: two pairs stretched forward (down), a short third pair, the fourth stretched back
	for side in [-1.0, 1.0]:
		for leg in [[0.28, 0.088], [0.72, 0.074], [1.75, 0.04], [2.78, 0.084]]:
			var ang: float = leg[0]
			var len: float = leg[1]
			var dir := Vector3(sin(ang) * side, -cos(ang), 0)
			var root := Vector3(0.005 * side, -0.006, 0.006)
			_limb(st, [root, root + dir * len * 0.36 + Vector3(0, 0, 0.014), root + dir * len * 0.43 + Vector3(0, 0, 0.0145),
				root + dir * len * 0.72 + Vector3(0, 0, 0.007), root + dir * len * 0.78 + Vector3(0, 0, 0.005), root + dir * len],
				0.0021, 0.0009, [orange, black, orange, black, black])
	return st.commit()


func _update_webs(delta: float) -> void:
	if webs.is_empty():
		return
	var night := _night()
	_web_mat.albedo_color = Color(1, 1, 1, lerpf(0.42, 0.04, night))
	_line_mat.albedo_color = Color(1.0, 0.92, 0.62, lerpf(0.4, 0.03, night))
	var amb := get_node_or_null("../../Ambience")
	var gust: float = amb.gust if amb and "gust" in amb else 0.5
	for d: Dictionary in webs:
		d["t"] += delta
		var t: float = d["t"]
		# the web bellies a little in the wind (the threads that hold it stay where they are
		# fixed to the trunks); the spider shifts now and then
		var wn: Node3D = d["web"]
		var sway: float = sin(t * 1.3 + d["seed"]) * (0.5 + gust)
		wn.position.z = sway * 0.012
		wn.rotation.y = sway * 0.012
		d["twitch"] -= delta
		var sp: Node3D = d["spider"]
		if d["twitch"] < 0.0:
			sp.rotation.z = sin(t * 9.0) * 0.12 * smoothstep(-0.9, -0.2, d["twitch"]) * (1.0 - smoothstep(-0.2, 0.0, d["twitch"]))
			if d["twitch"] < -0.9:
				d["twitch"] = _rng.randf_range(8.0, 30.0)
				sp.rotation.z = 0.0


# ================================================================== termites
## Arboreal termites: a dark, lumpy carton nest the size of a football or bigger wrapped around a
## palm trunk above head height, and their covered runways (earth-colored tubes the width of
## a finger) down the trunk to the ground. On the runways the workers themselves run up and
## down in two files: pale, 4 mm long, seen only from a step or two away.
var termite_nests: Array = []
var termite_trails: Array = []    # per nest: {"mm", "paths", "ants", "center"}
const TERMITES_PER_RUNWAY := 80

func _setup_termites() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.39, 0.28)    # (sRGB: earth brown; the nest is darkened by its vertex colors)
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 5.0
	for an: Vector2 in [Vector2(-13, 30), Vector2(-66, -92), Vector2(-128, 70)]:
		var best: Dictionary = {}
		var bd := 40.0
		for t in _ls.palm_trunks:
			var pts: PackedVector3Array = t["pts"]
			var base := pts[0]
			var top := pts[pts.size() - 1]
			if top.y - base.y < 5.0 or Vector2(top.x - base.x, top.z - base.z).length() > 1.6 or base.y < 1.2:
				continue
			var dd := Vector2(base.x, base.z).distance_to(an)
			if dd < bd and _ls.trail_distance(Vector2(base.x, base.z)) > 3.0:
				bd = dd
				best = t
		if best.is_empty():
			continue
		var h := _rng.randf_range(2.3, 3.0)
		var fr: Array = _trunk_at(best, h)
		var c: Vector3 = fr[0]
		var tr: float = fr[1]
		var ang := _rng.randf() * TAU
		var out := Vector3(cos(ang), 0, sin(ang))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# the nest: a lumpy ellipsoid hugging one side of the trunk
		var nc := c + out * (tr * 0.55)
		var rad := Vector3(tr + _rng.randf_range(0.16, 0.22), _rng.randf_range(0.3, 0.4), tr + _rng.randf_range(0.16, 0.22))
		var rings := 14
		var segs := 20
		var grid: Array = []
		for i in rings + 1:
			var row: Array = []
			for j in segs:
				var th := PI * float(i) / rings
				var ph := TAU * float(j) / segs
				var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				var bump := 1.0 + 0.2 * noise.get_noise_3d(d.x, d.y * 1.3, d.z) + 0.08 * noise.get_noise_3d(d.x * 3.1 + 5.0, d.y * 3.1, d.z * 3.1)
				# (drawn out to a point below, where the runways leave it)
				var drop := 1.0 + 0.35 * maxf(-d.y, 0.0) * maxf(-d.y, 0.0)
				row.append(nc + Vector3(d.x * rad.x * bump, d.y * rad.y * bump * drop, d.z * rad.z * bump))
			grid.append(row)
		for i in rings:
			for j in segs:
				var q := [grid[i][j], grid[i][(j + 1) % segs], grid[i + 1][(j + 1) % segs], grid[i + 1][j]]
				for idx in [0, 2, 1, 0, 3, 2]:
					var p: Vector3 = q[idx]
					st.set_color(Color(0.4, 0.4, 0.4).lerp(Color(0.6, 0.56, 0.5), 0.5 + 0.5 * noise.get_noise_3d(p.x * 4.0, p.y * 4.0, p.z * 4.0)))
					st.add_vertex(p)
		# runways down the trunk: raised strips that wander a little
		var paths: Array = []
		for k in 2 + _rng.randi() % 2:
			var a0 := ang + _rng.randf_range(-0.9, 0.9)
			var prev: Array = []
			var path: Array = []      # [point on the bark, outward, along the bark across the runway]
			var hh := h - rad.y * 0.6
			var ph := _rng.randf() * TAU
			while hh > -0.1:
				var f: Array = _trunk_at(best, maxf(hh, 0.0))
				var aa := a0 + sin(hh * 1.7 + ph) * 0.35 + sin(hh * 4.3 + ph * 2.0) * 0.1
				var o := Vector3(cos(aa), 0, sin(aa))
				var tng := Vector3(-o.z, 0, o.x)
				# (the recorded radius is 0.9 of the trunk's, for collisions, and a leaning trunk
				# is wider across than its radius: with neither allowed for, the runways lay
				# under the bark)
				var f2: Array = _trunk_at(best, maxf(hh, 0.0) + 0.2)
				var ax: Vector3 = ((f2[0] as Vector3) - (f[0] as Vector3)).normalized()
				var reach := float(f[1]) / 0.9 / sqrt(maxf(1.0 - pow(o.dot(ax), 2.0), 0.3)) + 0.004
				var pc: Vector3 = (f[0] as Vector3) + o * reach
				pc.y = (best["pts"][0] as Vector3).y + hh
				var cur := [pc - tng * 0.016 - o * 0.012, pc + o * 0.012, pc + tng * 0.016 - o * 0.012]
				path.append([pc, o, tng])
				if not prev.is_empty():
					for e in [[0, 1], [1, 2]]:
						var q := [prev[e[0]], prev[e[1]], cur[e[1]], cur[e[0]]]
						for idx in [0, 2, 1, 0, 3, 2]:
							st.set_color(Color(0.8, 0.76, 0.7))
							st.add_vertex(q[idx])
				prev = cur
				hh -= 0.12
			paths.append(path)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "TermiteNest%d" % termite_nests.size()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)
		termite_nests.append(nc)
		_termite_trail(nc, paths)


## The workers of one nest: a MultiMesh of tiny bodies, each with a runway, a place along it, a
## speed (up or down) and a side of the runway it keeps to.
func _termite_trail(center: Vector3, paths: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# abdomen and thorax pale, the head dark (forward = -z, up = +y; 4.5 mm long)
	_ellipsoid(st, Vector3(0, 0.0008, 0.0009), Vector3(0.0009, 0.0008, 0.0015), Color(0.8, 0.68, 0.46), Color(0.72, 0.58, 0.36))
	_ellipsoid(st, Vector3(0, 0.0007, -0.0008), Vector3(0.0006, 0.0006, 0.0007), Color(0.7, 0.56, 0.34), Color(0.7, 0.56, 0.34))
	_ellipsoid(st, Vector3(0, 0.0008, -0.0017), Vector3(0.0007, 0.0007, 0.0008), Color(0.3, 0.16, 0.06), Color(0.3, 0.16, 0.06))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	var ants: Array = []
	for pi in paths.size():
		var path: Array = paths[pi]
		if path.size() < 3:
			continue
		for k in TERMITES_PER_RUNWAY:
			var up := _rng.randf() < 0.5
			ants.append({"path": pi, "s": _rng.randf() * (path.size() - 1), "v": _rng.randf_range(0.02, 0.04) * (-1.0 if up else 1.0),
				"side": (1.0 if up else -1.0) * _rng.randf_range(0.002, 0.008), "ph": _rng.randf() * TAU})
	mm.instance_count = ants.size()
	var mi := MultiMeshInstance3D.new()
	mi.name = "Termites%d" % termite_trails.size()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(center.x, center.y - 1.2, center.z)
	mi.visibility_range_end = 7.0
	mi.custom_aabb = AABB(Vector3(-1.2, -2.2, -1.2), Vector3(2.4, 4.0, 2.4))
	add_child(mi)
	var trail := {"mm": mm, "node": mi, "paths": paths, "ants": ants}
	termite_trails.append(trail)
	_move_termites(trail, 0.0)


func _update_termites(delta: float) -> void:
	if _player == null:
		return
	for trail: Dictionary in termite_trails:
		# (nobody sees them from further away: they stand still until someone comes)
		if ((trail["node"] as Node3D).global_position + Vector3(0, 1.0, 0)).distance_to(_player.global_position) < 8.0:
			_move_termites(trail, delta)


func _move_termites(trail: Dictionary, delta: float) -> void:
	var mm: MultiMesh = trail["mm"]
	var origin: Vector3 = (trail["node"] as Node3D).position
	var paths: Array = trail["paths"]
	var ants: Array = trail["ants"]
	trail["t"] = float(trail.get("t", 0.0)) + delta
	var now: float = trail["t"]
	for i in ants.size():
		var a: Dictionary = ants[i]
		var path: Array = paths[a["path"]]
		var n := path.size() - 1
		# (the points are 12 cm apart: s counts them. Now and then one stops for a moment: by the
		# clock, not by the place, or it would never go on again)
		var pause := 0.0 if sin(float(a["ph"]) * 7.0 + now * (0.5 + 0.3 * sin(float(a["ph"])))) > 0.9 else 1.0
		var s: float = fposmod(float(a["s"]) + float(a["v"]) / 0.12 * delta * pause, float(n))
		a["s"] = s
		var k := mini(int(s), n - 1)
		var f := s - k
		var p0: Array = path[k]
		var p1: Array = path[k + 1]
		var out: Vector3 = (p0[1] as Vector3).lerp(p1[1], f).normalized()
		var across: Vector3 = (p0[2] as Vector3).lerp(p1[2], f).normalized()
		var along: Vector3 = ((p1[0] as Vector3) - (p0[0] as Vector3)).normalized() * signf(float(a["v"]))
		# (on the runway's ridge: 12 mm high in the middle, falling away to both sides)
		var side: float = float(a["side"]) + sin(s * 7.0 + float(a["ph"])) * 0.0015
		var pos: Vector3 = (p0[0] as Vector3).lerp(p1[0], f) + across * side + out * (0.0126 - absf(side) * 1.5)
		# forward along the runway, the back to the bark
		var z := -along
		var x := out.cross(z).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(x, z.cross(x), z), pos - origin))


# ================================================================== mudskippers
## Mudskippers: little fish that sit out of the water at its very edge among the mangroves,
## propped on their pectoral fins. Now and then one hitches itself forward a few centimeters;
## when someone comes within three steps they skip away to the water in quick hops and lie
## there, only the eyes out, until the coast is clear. A few only, where the mangroves are
## densest.
const MUDSKIPPER_MAX := 12
var mudskippers: Array = []

func _setup_mudskippers() -> void:
	var trees: Array = _ls.mangrove_spots
	if trees.is_empty():
		return
	# the densest stands: the trees with the most neighbors
	var ranked: Array = []
	for t: Vector2 in trees:
		var c := 0
		for o: Vector2 in trees:
			if o.distance_to(t) < 12.0:
				c += 1
		ranked.append([c, t])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var centers: Array = []
	for r: Array in ranked:
		var far := true
		for c: Vector2 in centers:
			if c.distance_to(r[1]) < 30.0:
				far = false
		if far and int(r[0]) >= 4 and centers.size() < 3:
			centers.append(r[1])
	if centers.is_empty():
		centers.append(ranked[0][1])
	var mesh: ArrayMesh = SmallModels.mudskipper()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.25          # wet skin
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c: Vector2 in centers:
		var made := 0
		for k in 200:
			if made >= 4 or mudskippers.size() >= MUDSKIPPER_MAX:
				break
			var p := c + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * 9.0)
			var y: float = _ls.ground(p.x, p.y)
			# the wet edge: just above the water (as the tide stands now), on sand or mud
			if y - float(_ls.sea) < 0.0 or y - float(_ls.sea) > 0.09 or _ls.rocky(p, 0.6):
				continue
			var near := false
			for m: Dictionary in mudskippers:
				if Vector2((m["pos"] as Vector3).x, (m["pos"] as Vector3).z).distance_to(p) < 0.6:
					near = true
			for t: Vector2 in trees:
				if t.distance_to(p) < 0.7:
					near = true       # (not inside a trunk)
			if near:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Mudskipper%d" % mudskippers.size()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 30.0
			mi.scale = Vector3.ONE * _rng.randf_range(0.85, 1.25)
			add_child(mi)
			var d := {"node": mi, "pos": Vector3(p.x, y, p.y), "home": Vector3(p.x, y, p.y), "yaw": _rng.randf() * TAU, "state": "sit",
				"timer": _rng.randf_range(2.0, 9.0), "hops": 0, "hop": -1.0, "from": Vector3.ZERO, "to": Vector3.ZERO, "len": 0.2, "high": 0.01, "calm": 0.0}
			mudskippers.append(d)
			_pose_mudskipper(d)
			made += 1


## Which way is down the beach (toward the water) at p.
func _downhill(p: Vector3) -> Vector3:
	var e := 0.5
	var g := Vector3(float(_ls.ground(p.x - e, p.z)) - float(_ls.ground(p.x + e, p.z)), 0, float(_ls.ground(p.x, p.z - e)) - float(_ls.ground(p.x, p.z + e)))
	return g.normalized() if g.length() > 0.0001 else Vector3(1, 0, 0)


## Starts one hop of `dist` in direction `dir` if it ends on the wet edge or in the shallowest
## water (hard rule: never up the dry beach, never out into the sea).
func _mudskipper_hop(d: Dictionary, dir: Vector3, dist: float, high: float, seconds: float) -> bool:
	var pos: Vector3 = d["pos"]
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var c: Vector3 = dir.rotated(Vector3.UP, a)
		var q: Vector3 = pos + c * dist
		var y: float = _ls.ground(q.x, q.z)
		var h := y - float(_ls.sea)
		# (on its way after the water's edge, when the tide has moved it, it may cross the beach)
		if ((h > -0.05 and h < 0.14) or (d["state"] == "follow" and h > -0.05)) and not _ls.rocky(Vector2(q.x, q.z), 0.3):
			d["from"] = pos
			d["to"] = Vector3(q.x, y, q.z)
			d["hop"] = 0.0
			d["len"] = seconds
			d["high"] = high
			d["yaw"] = atan2(-c.x, -c.z)
			return true
	return false


## A place at the water's edge as it lies now, as near `from` as there is one within 16 m,
## and half a meter from the others' places (`from` itself if there is none).
func _mudskipper_place(from: Vector3, me: Dictionary) -> Vector3:
	var best := from
	var best_d := 1e9
	for i in 260:
		var p := Vector2(from.x, from.z) + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * 16.0)
		var y: float = _ls.ground(p.x, p.y)
		var h := y - float(_ls.sea)
		var dd := p.distance_to(Vector2(from.x, from.z))
		if h < 0.0 or h > 0.09 or dd >= best_d or _ls.rocky(p, 0.6):
			continue
		var near := false
		for m: Dictionary in mudskippers:
			if m != me and Vector2((m["home"] as Vector3).x, (m["home"] as Vector3).z).distance_to(p) < 0.5:
				near = true
		if not near:
			best = Vector3(p.x, y, p.y)
			best_d = dd
	return best


func _update_mudskippers(delta: float) -> void:
	if mudskippers.is_empty() or _player == null:
		return
	var pp := _player.global_position
	var sea: float = _ls.sea
	for d: Dictionary in mudskippers:
		var pos: Vector3 = d["pos"]
		var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
		var dist := away.length()
		# the tide has moved the water's edge away from its place: a new place at the edge
		# (looked for now and then, not in every frame)
		var home_h := (d["home"] as Vector3).y - sea
		if (home_h < -0.03 or home_h > 0.13) and Engine.get_process_frames() % 30 == mudskippers.find(d) % 30:
			d["home"] = _mudskipper_place(d["home"], d)
			if dist > 32.0:
				# (nobody near enough to see: it is there already)
				d["pos"] = d["home"]
				d["hop"] = -1.0
				d["state"] = "sit"
				_pose_mudskipper(d)
			elif d["state"] != "flee" and d["state"] != "hide":
				d["state"] = "follow"
				d["timer"] = 0.0
		if dist > 45.0:
			continue
		if float(d["hop"]) >= 0.0:
			# in the air: a low arc
			d["hop"] += delta / float(d["len"])
			var t := minf(float(d["hop"]), 1.0)
			var p: Vector3 = (d["from"] as Vector3).lerp(d["to"], t)
			p.y += sin(t * PI) * float(d["high"])
			d["pos"] = p
			if t >= 1.0:
				d["hop"] = -1.0
				d["pos"] = d["to"]
			_pose_mudskipper(d)
			continue
		d["timer"] -= delta
		var state: String = d["state"]
		var near := dist < 2.8 and pp.y - pos.y < 3.0
		match state:
			"sit":
				if near:
					d["state"] = "flee"
					d["hops"] = _rng.randi_range(4, 7)
					d["timer"] = 0.0
				elif d["timer"] <= 0.0:
					# hitches itself along a little, or turns
					d["state"] = "crutch"
					d["hops"] = _rng.randi_range(1, 4)
					d["yaw"] += _rng.randf_range(-0.9, 0.9)
					d["timer"] = 0.2
			"crutch":
				if near:
					d["state"] = "flee"
					d["hops"] = _rng.randi_range(4, 7)
					d["timer"] = 0.0
				elif d["timer"] <= 0.0:
					var fwd := Vector3(-sin(float(d["yaw"])), 0, -cos(float(d["yaw"])))
					# (it does not stray from its place at the water's edge)
					var home: Vector3 = d["home"]
					if pos.distance_to(home) > 1.2:
						fwd = (home - pos).normalized()
					if d["hops"] > 0 and _mudskipper_hop(d, fwd, _rng.randf_range(0.025, 0.045), 0.006, 0.22):
						d["hops"] -= 1
						d["timer"] = _rng.randf_range(0.3, 0.7)
					else:
						d["state"] = "sit"
						d["timer"] = _rng.randf_range(4.0, 14.0)
			"follow":
				# after the water's edge, in a string of skips
				if d["timer"] <= 0.0:
					var home: Vector3 = d["home"]
					var to_home := Vector3(home.x - pos.x, 0, home.z - pos.z)
					if to_home.length() < 0.25 or not _mudskipper_hop(d, to_home.normalized(), minf(_rng.randf_range(0.16, 0.26), to_home.length()), 0.03, 0.18):
						d["state"] = "sit"
						d["timer"] = _rng.randf_range(3.0, 9.0)
					else:
						d["timer"] = _rng.randf_range(0.05, 0.5)
			"flee":
				if d["timer"] <= 0.0:
					# to the water, and away from whoever is coming
					var dir := (_downhill(pos) * 1.2 + (away / maxf(dist, 0.1))).normalized()
					var wet := pos.y - sea < -0.02
					if d["hops"] > 0 and not wet and _mudskipper_hop(d, dir, _rng.randf_range(0.16, 0.26), 0.035, 0.17):
						d["hops"] -= 1
						d["timer"] = 0.03
					else:
						d["state"] = "hide"
						d["calm"] = 0.0
			"hide":
				# in the water, the eyes out; back up the beach when nobody has been near for a while
				d["calm"] = 0.0 if dist < 6.0 else float(d["calm"]) + delta
				if near and pos.y - sea > -0.02 and d["timer"] <= 0.0:
					d["state"] = "flee"
					d["hops"] = 3
				elif float(d["calm"]) > 6.0 and d["timer"] <= 0.0:
					var home: Vector3 = d["home"]
					if pos.distance_to(home) < 0.12 or not _mudskipper_hop(d, (home - pos).normalized(), minf(0.045, pos.distance_to(home)), 0.006, 0.22):
						d["state"] = "sit"
						d["timer"] = _rng.randf_range(3.0, 10.0)
					else:
						d["timer"] = _rng.randf_range(0.25, 0.6)
		_pose_mudskipper(d)


func _pose_mudskipper(d: Dictionary) -> void:
	var mi: MeshInstance3D = d["node"]
	var pos: Vector3 = d["pos"]
	var sc := mi.scale.x
	# the nose up a little as it sits; up and then down through a hop
	var pitch := 0.08
	if float(d["hop"]) >= 0.0:
		pitch = 0.08 + cos(float(d["hop"]) * PI) * float(d["high"]) * 12.0
	# in the water it lies on the bottom, at most deep enough for the eyes to stay out
	var y := maxf(pos.y, float(_ls.sea) - 0.019 * sc)
	mi.transform = Transform3D((Basis(Vector3.UP, d["yaw"]) * Basis(Vector3.RIGHT, pitch)).scaled(Vector3.ONE * sc), Vector3(pos.x, y, pos.z))


# ================================================================== Seychelles frogs
## The Seychelles frog (Sooglossus sechellensis) lives only on a few of these islands, in the
## damp litter of the hill forest, and is rare: seven of them here, all near the fresh water,
## one or two by each of the stream's pools and by the pond. Thumbnail-sized, brown, warty. A
## frog sits; now and then it turns or shifts a little; when someone comes within a step it
## goes off in two or three unhurried hops and sits again. They are shown a little larger
## than life (2.6-3 cm for 2 cm), like the spiders: at life size nobody would find them.
const FROG_COUNT := 7
const FROG_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Seychelles frog: brown, moist, warty; dark blotches, pale warts, banded legs, a paler belly.
// COLOR.r legs, COLOR.g throat (it flutters), COLOR.b eyes.
varying vec3 o_pos;
varying vec3 o_nrm;
float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
	VERTEX.y -= COLOR.g * 0.0007 * (0.5 + 0.5 * sin(TIME * 9.0 + MODEL_MATRIX[3].x * 37.0));
}
void fragment() {
	vec3 c = vec3(0.2, 0.085, 0.035) * (0.7 + 0.6 * vn(o_pos * 1100.0));
	c = mix(c, vec3(0.05, 0.03, 0.018), smoothstep(0.5, 0.66, vn(o_pos * 430.0 + 3.0)));
	c = mix(c, vec3(0.5, 0.33, 0.15), smoothstep(0.76, 0.88, vn(o_pos * 1900.0 + 9.0)) * 0.8);
	if (COLOR.r > 0.5) {
		// the legs: dark bars across
		c = mix(c, vec3(0.05, 0.03, 0.018), smoothstep(0.2, 0.7, sin((o_pos.z + abs(o_pos.x) * 0.6) * 2600.0)) * 0.7);
	}
	c = mix(c, vec3(0.42, 0.34, 0.25), smoothstep(0.2, 0.7, -o_nrm.y) * 0.7);
	float rough = 0.5;
	if (COLOR.b > 0.5) {
		c = vec3(0.006);
		rough = 0.08;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.25;      // (more, and in the shade it mirrors the sky: a gray-blue frog)
}"""
var frogs: Array = []
var _frog_voice: AudioStreamPlayer3D
var _frog_calls: Array[AudioStream] = []
var _frog_call_t := 12.0
## (scripts/weather.gd sets these) after rain the frogs call often, and are heard further;
## in the rain the dragonflies and butterflies are gone
var frog_chorus := 0.0
var raining := false

func _place_frogs() -> void:
	var pools: Array = _ls.stream_pools
	if pools.is_empty():
		return
	var mesh: ArrayMesh = SmallModels.frog()
	var sh := Shader.new()
	sh.code = FROG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	# the pond first (it gets two), then the pools from the bottom of the stream up
	var order: Array = []
	for pl: Dictionary in pools:
		if pl["pond"]:
			order.append(pl)
			order.append(pl)
	for pl: Dictionary in pools:
		if not pl["pond"]:
			order.append(pl)
	for pl: Dictionary in pools:
		order.append(pl)
	for pl: Dictionary in order:
		if frogs.size() >= FROG_COUNT:
			break
		var at: Vector3 = pl["at"]
		for k in 90:
			var a := _rng.randf() * TAU
			var r := maxf(pl["rx"], pl["rz"]) + _rng.randf_range(0.3, 1.3 if k < 60 else 2.2)
			var hit := _frog_ground(Vector3(at.x + cos(a) * r, at.y, at.z + sin(a) * r))
			# (on a rock by the water if there is one: there it is seen; on the ground the
			# ferns hide it)
			if hit.is_empty() or (k < 60 and not hit["rock"]):
				continue
			var hp: Vector3 = hit["position"]
			var near := false
			for f: Dictionary in frogs:
				if (f["pos"] as Vector3).distance_to(hp) < 0.8:
					near = true
			if near:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Frog%d" % frogs.size()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 25.0
			mi.scale = Vector3.ONE * _rng.randf_range(1.3, 1.5)
			add_child(mi)
			var d := {"node": mi, "pos": hp, "up": hit["normal"], "home": hp, "yaw": _rng.randf() * TAU, "timer": _rng.randf_range(4.0, 20.0),
				"hops": 0, "hop": -1.0, "from": hp, "to": hp, "len": 0.28, "high": 0.03, "away": false}
			frogs.append(d)
			_pose_frog(d)
			break
	# its voice: a thin high peeping, now and then, from one of them
	for i in 4:
		var path := A + "frog_%d.wav" % i
		if ResourceLoader.exists(path):
			_frog_calls.append(load(path))
	if not _frog_calls.is_empty():
		_frog_voice = AudioStreamPlayer3D.new()
		_frog_voice.bus = "Ambient"
		_frog_voice.unit_size = 2.5
		_frog_voice.max_distance = 22.0
		_frog_voice.volume_db = -14.0
		add_child(_frog_voice)


## Somewhere a frog can sit at or near p: firm, fairly level ground or the top of a rock, out of
## the water of the pools and the wet line of the stream. {} if there is none.
func _frog_ground(p: Vector3) -> Dictionary:
	var hit := _ray(Vector3(p.x, p.y + 3.0, p.z), Vector3(p.x, p.y - 3.0, p.z))
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.72:
		return {}
	var hp: Vector3 = hit["position"]
	for pl: Dictionary in _ls.stream_pools:
		var at: Vector3 = pl["at"]
		if Vector2(hp.x - at.x, hp.z - at.z).length() < maxf(pl["rx"], pl["rz"]) + 0.1 and hp.y < at.y + 0.04:
			return {}     # in a pool
	# (the land mask's alpha is 1 on dry ground and falls to 0 on the stream's course; the ground
	# shader draws running water below about 0.2. Damp is what a frog likes; wet is not)
	var on_rock := hp.y - float(_ls.ground(hp.x, hp.z)) > 0.08
	var mk: Image = _ls._mask
	var u := int(clampf((hp.x + 256.0) / 512.0 * mk.get_width(), 0, mk.get_width() - 1))
	var v := int(clampf((hp.z + 256.0) / 512.0 * mk.get_height(), 0, mk.get_height() - 1))
	if not on_rock and mk.get_pixel(u, v).a < 0.45:
		return {}         # in the running water
	hit["rock"] = on_rock
	return hit


func _frog_hop(d: Dictionary, dir: Vector3, dist: float, high: float, seconds: float) -> bool:
	var pos: Vector3 = d["pos"]
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0]:
		var c: Vector3 = dir.rotated(Vector3.UP, a)
		var hit := _frog_ground(pos + c * dist)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - pos.y) > 0.25:
			continue
		d["from"] = pos
		d["to"] = hit["position"]
		d["to_up"] = hit["normal"]
		d["hop"] = 0.0
		d["len"] = seconds
		d["high"] = high
		d["yaw"] = atan2(-c.x, -c.z)
		return true
	return false


func _update_frogs(delta: float) -> void:
	if frogs.is_empty() or _player == null:
		return
	var pp := _player.global_position
	var nearest := 1e9
	for d: Dictionary in frogs:
		var pos: Vector3 = d["pos"]
		var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
		var dist := away.length()
		nearest = minf(nearest, dist)
		if dist > 30.0:
			continue
		if float(d["hop"]) >= 0.0:
			d["hop"] += delta / float(d["len"])
			var t := minf(float(d["hop"]), 1.0)
			var p: Vector3 = (d["from"] as Vector3).lerp(d["to"], t)
			p.y += sin(t * PI) * float(d["high"])
			d["pos"] = p
			if t >= 1.0:
				d["hop"] = -1.0
				d["pos"] = d["to"]
				d["up"] = d["to_up"]
			_pose_frog(d)
			continue
		d["timer"] -= delta
		if dist < 1.2 and absf(pp.y - pos.y) < 2.5 and not d["away"]:
			# somebody a step away: off in two or three hops, without haste
			d["away"] = true
			d["hops"] = _rng.randi_range(2, 3)
			d["timer"] = 0.15
		if d["timer"] > 0.0:
			continue
		var home: Vector3 = d["home"]
		if d["hops"] > 0:
			var dir := (away / maxf(dist, 0.05)).rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) if d["away"] else (home - pos).normalized()
			if _frog_hop(d, dir, _rng.randf_range(0.1, 0.16) if d["away"] else _rng.randf_range(0.05, 0.09), 0.035 if d["away"] else 0.018, 0.3):
				d["hops"] -= 1
				d["timer"] = _rng.randf_range(0.45, 0.9)
			else:
				d["hops"] = 0
				d["timer"] = 2.0
		else:
			# at ease: it turns a little; if it has been driven off, it comes back hop by hop
			d["away"] = false
			if pos.distance_to(home) > 0.5 and dist > 4.0:
				d["hops"] = mini(int(pos.distance_to(home) / 0.07), 4)
				d["timer"] = _rng.randf_range(3.0, 8.0)
			else:
				d["yaw"] += _rng.randf_range(-0.8, 0.8)
				d["timer"] = _rng.randf_range(8.0, 30.0)
				_pose_frog(d)
	# a call from one of the nearer ones, now and then
	var hear := lerpf(22.0, 45.0, frog_chorus)
	if _frog_voice and nearest < hear:
		_frog_call_t -= delta
		if _frog_call_t <= 0.0 and not _frog_voice.playing:
			_frog_call_t = _rng.randf_range(14.0, 45.0) * lerpf(1.0, 0.16, frog_chorus)
			_frog_voice.max_distance = hear
			var f: Dictionary = frogs[_rng.randi() % frogs.size()]
			if (f["pos"] as Vector3).distance_to(pp) < hear:
				_frog_voice.global_position = f["pos"]
				_frog_voice.stream = _frog_calls[_rng.randi() % _frog_calls.size()]
				_frog_voice.pitch_scale = _rng.randf_range(0.94, 1.06)
				_frog_voice.play()


func _pose_frog(d: Dictionary) -> void:
	var mi: MeshInstance3D = d["node"]
	var up: Vector3 = d["up"]
	var fwd := Vector3(-sin(float(d["yaw"])), 0, -cos(float(d["yaw"])))
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var z := -fwd
	var x := up.cross(z).normalized()
	# sitting, the head is up; in a hop it stretches out and comes down nose first
	var pitch := 0.3
	if float(d["hop"]) >= 0.0:
		pitch = 0.3 + cos(float(d["hop"]) * PI) * 0.5
	mi.global_transform = Transform3D((Basis(x, up, z) * Basis(Vector3.RIGHT, pitch)).scaled(mi.scale), (d["pos"] as Vector3) + up * 0.0004)


# ================================================================== flying fox roost
## By day the flying foxes hang in the crown of one tall tree: head down, wrapped in their wings,
## swaying, now and then one of them fanning itself or squabbling with its neighbor. At dusk
## they leave (the ones in the night sky are fauna.gd's), at dawn they are back.
var roost: Array = []
var roost_center := Vector3.ZERO
var _roost_voice: AudioStreamPlayer3D
var _roost_calls: Array[AudioStream] = []
var _roost_timer := 20.0

func _setup_roost() -> void:
	var scene := load("res://assets/models/flying_fox.glb") as PackedScene
	if scene == null or _ls.tree_spots.is_empty():
		return
	# a big takamaka in the forest below the ridge
	var anchor := Vector2(-58, -18)
	var best: Dictionary = {}
	var bs := -1e9
	for t in _ls.tree_spots:
		var xf: Transform3D = t["xf"]
		if not (t["kind"] as String).begins_with("Taka") or t.get("colony", false):
			continue
		var dd := Vector2(xf.origin.x, xf.origin.z).distance_to(anchor)
		var score := xf.basis.get_scale().y * 30.0 - dd
		if dd < 40.0 and score > bs and _ls.trail_distance(Vector2(xf.origin.x, xf.origin.z)) > 8.0:
			bs = score
			best = t
	if best.is_empty():
		return
	var xf: Transform3D = best["xf"]
	var bark: Mesh = _ls._tree_parts.get(String(best["kind"]) + "Bark")
	if bark == null:
		return
	# branches high in the crown to hang from
	var verts: PackedVector3Array = bark.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -1e9
	var world_v := PackedVector3Array()
	for v in verts:
		var w := xf * v
		world_v.append(w)
		top = maxf(top, w.y)
	var height := top - xf.origin.y
	var spots: Array = []
	var tries := 0
	while spots.size() < 10 and tries < 4000:
		tries += 1
		var w := world_v[_rng.randi() % world_v.size()]
		if w.y < xf.origin.y + height * 0.55 or w.y > top - 0.3:
			continue
		if Vector2(w.x - xf.origin.x, w.z - xf.origin.z).length() < 0.8:
			continue   # out on a limb, not against the trunk
		var ok := true
		for s: Vector3 in spots:
			if s.distance_to(w) < 0.55:
				ok = false
		# nothing right below it for the length of the animal
		for o in world_v:
			if o.y < w.y - 0.12 and o.y > w.y - 0.5 and Vector2(o.x - w.x, o.z - w.z).length() < 0.14:
				ok = false
				break
		if ok:
			spots.append(w)
	if spots.is_empty():
		return
	var cloak := _cloak_mesh()
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.vertex_color_is_srgb = true
	cmat.roughness = 0.5
	for s: Vector3 in spots:
		roost_center += s / spots.size()
		var root := Node3D.new()
		add_child(root)
		root.global_position = s - Vector3(0, 0.03, 0)
		var swing := Node3D.new()      # hangs from the feet: everything swings about this point
		root.add_child(swing)
		var m := scene.instantiate() as Node3D
		swing.add_child(m)
		for w in ["BatWingL", "BatWingR"]:
			var old := m.find_child(w, true, false)
			if old:
				old.get_parent().remove_child(old)
				old.free()
		if _world.has_method("_apply_materials"):
			_world._apply_materials(m)
		# head down: the model's back end (+z, the feet) up at the branch
		var yaw := _rng.randf() * TAU
		var x := Vector3(cos(yaw), 0, sin(yaw))
		m.transform = Transform3D(Basis(x, Vector3.UP.cross(x), Vector3.UP), Vector3(0, -0.28, 0))
		# the folded wings: a dark leathery cloak around the body, the head and the golden mantle free
		var c := MeshInstance3D.new()
		c.mesh = cloak
		c.material_override = cmat
		swing.add_child(c)
		c.rotation.y = -yaw
		roost.append({"root": root, "swing": swing, "cloak": c, "seed": _rng.randf() * TAU, "fan": 0.0, "fan_t": _rng.randf_range(5.0, 40.0), "yaw": yaw})
	for i in 8:
		var p := A + "flying_fox_%d.wav" % i
		if ResourceLoader.exists(p):
			_roost_calls.append(load(p))
	_roost_voice = AudioStreamPlayer3D.new()
	_roost_voice.unit_size = 9.0
	_roost_voice.max_distance = 70.0
	_roost_voice.volume_db = -14.0
	_roost_voice.bus = "Ambient"
	add_child(_roost_voice)
	_roost_voice.global_position = roost_center


## The folded wings of a hanging flying fox, in the frame it swings in (the feet at the origin,
## the animal hanging down -y, its left and right along x): the membranes wrapped around the body
## like a cloak from the ankles to the shoulders, widest at the shoulders, the arm and finger
## bones showing as ridges that run together at the wrists, the fold where one wing lies over
## the other down the front, the two wrists with their thumb claws standing out at the top, and
## the legs up to the branch.
func _cloak_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.13, 0.1, 0.085)
	var bone := Color(0.21, 0.16, 0.13)
	var rings := 12
	var segs := 20
	var grid: Array = []
	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(-0.035, -0.345, t)
		var wide := 0.016 + 0.07 * smoothstep(0.0, 0.72, t) - 0.03 * smoothstep(0.78, 1.0, t)
		var row: Array = []
		for j in segs:
			var th := TAU * float(j) / segs
			# the finger bones: ridges that fan out downward from the wrists
			var ridge := maxf(cos(th * 5.0 + 0.4), 0.0)
			var fold := exp(-pow(angle_difference(th, PI * 0.5) / 0.3, 2.0))      # down the front
			var r := 1.0 + 0.07 * ridge * smoothstep(0.05, 0.5, t) - 0.16 * fold
			var p := Vector3(cos(th) * wide * r, y, sin(th) * wide * 0.74 * r)
			row.append([p, skin.lerp(bone, ridge * ridge * 0.8) * (1.0 - 0.35 * fold)])
		grid.append(row)
	for i in rings:
		for j in segs:
			var q := [grid[i][j], grid[i][(j + 1) % segs], grid[i + 1][(j + 1) % segs], grid[i + 1][j]]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_color(q[idx][1])
				st.add_vertex(q[idx][0])
	# closed above (around the ankles) and below (around the neck)
	for e in [[0, -0.03], [rings, -0.352]]:
		for j in segs:
			var tri := [grid[e[0]][j], grid[e[0]][(j + 1) % segs], [Vector3(0, e[1], 0), skin]]
			for idx in ([0, 1, 2] if e[0] == 0 else [0, 2, 1]):
				st.set_color(tri[idx][1])
				st.add_vertex(tri[idx][0])
	st.generate_normals()
	for side in [-1.0, 1.0]:
		# wrists and thumbs
		_ellipsoid(st, Vector3(0.034 * side, -0.075, 0.012), Vector3(0.011, 0.016, 0.011), bone, bone)
		_limb(st, [Vector3(0.036 * side, -0.066, 0.016), Vector3(0.043 * side, -0.05, 0.024), Vector3(0.04 * side, -0.04, 0.03)], 0.003, 0.0012, [bone, skin])
		# legs and feet hooked over the branch
		_limb(st, [Vector3(0.016 * side, -0.05, 0.0), Vector3(0.012 * side, -0.012, 0.0), Vector3(0.011 * side, 0.012, 0.006), Vector3(0.011 * side, 0.016, -0.012)], 0.0055, 0.003, [skin, skin, skin])
	return st.commit()


var _roost_home := true
var _roost_age := 0.0

func _update_roost(delta: float) -> void:
	if roost.is_empty():
		return
	var night := _night()
	var home := night < 0.35
	var t := Time.get_ticks_msec() * 0.001
	var near := _player != null and _player.global_position.distance_to(roost_center) < 90.0
	# At dusk they leave the roost, one after the other, and fly off over the trees; at dawn
	# they come in again and hang themselves up. (They used to be switched off and on where
	# they hung.) Seen only by somebody within 160 m: otherwise the roost is simply empty or full.
	_roost_age += delta
	if home != _roost_home:
		_roost_home = home
		var seen := _roost_age > 3.0 and _player != null and _player.global_position.distance_to(roost_center) < 160.0
		var fauna := get_node_or_null("../../Fauna")
		var k := 0
		for d: Dictionary in roost:
			var root: Node3D = d["root"]
			if not seen or fauna == null or not fauna.has_method("bat_flight"):
				d["due"] = -1.0
				root.visible = home
				continue
			# a way out over the canopy, clear of the ground all along
			var perch := root.global_position - Vector3(0, 0.25, 0)
			var a := _rng.randf() * TAU
			var out := Vector3(cos(a), 0, sin(a))
			var mid := perch + out * 16.0 + Vector3(0, 7.0, 0)
			var far := perch + out * 150.0
			mid.y = maxf(mid.y, float(_ls.ground(mid.x, mid.z)) + 15.0)
			far.y = maxf(perch.y + 14.0, float(_ls.ground(far.x, far.z)) + 24.0)
			var wait := k * _rng.randf_range(2.0, 4.5) + _rng.randf_range(0.0, 2.0)
			k += 1
			if home:
				# (it shows on its branch when the flyer gets there)
				d["due"] = fauna.bat_flight(far, mid, perch, wait)
				d["show"] = true
			else:
				fauna.bat_flight(perch, mid, far, wait)
				d["due"] = wait
				d["show"] = false
	for d: Dictionary in roost:
		var root: Node3D = d["root"]
		if float(d.get("due", -1.0)) >= 0.0:
			d["due"] = float(d["due"]) - delta
			if float(d["due"]) < 0.0:
				root.visible = d["show"]
		if not root.visible or not near:
			continue
		var sw: Node3D = d["swing"]
		sw.rotation = Vector3(sin(t * 0.9 + d["seed"]) * 0.05, 0, sin(t * 0.7 + d["seed"] * 1.7) * 0.06)
		# fanning: the wings open a little and beat slowly (they do this to cool down)
		d["fan_t"] -= delta
		if d["fan_t"] < 0.0:
			d["fan"] = _rng.randf_range(2.5, 6.0)
			d["fan_t"] = _rng.randf_range(15.0, 60.0)
		var c: Node3D = d["cloak"]
		var open := 0.0
		if d["fan"] > 0.0:
			d["fan"] -= delta
			open = (0.5 + 0.5 * sin(t * 7.0 + d["seed"])) * smoothstep(0.0, 0.5, d["fan"])
		c.scale = Vector3(1.0 + 0.8 * open, 1.0, 1.0 - 0.25 * open)
	if home and near and not _roost_calls.is_empty() and (roost[0]["root"] as Node3D).visible:
		_roost_timer -= delta
		if _roost_timer <= 0.0:
			_roost_timer = _rng.randf_range(25.0, 70.0)
			_roost_voice.stream = _roost_calls[_rng.randi() % _roost_calls.size()]
			_roost_voice.pitch_scale = _rng.randf_range(0.95, 1.1)
			_roost_voice.play()


# ================================================================== flying insects
## Dragonflies (the wandering glider, Pantala flavescens: golden, a tireless flier that turns up
## on every island of the Indian Ocean) hawk over the pond, the pools, the open ridge and the
## summit: straight darts, a hover, a sharp turn. A few butterflies (the plain tiger: orange with
## black wing tips) flutter along the forest's edge near the walker. By day only.
var dragonflies: Array = []
var butterflies: Array = []

func _setup_insects() -> void:
	# --- dragonflies
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold := Color(0.78, 0.5, 0.12)
	_ellipsoid(st, Vector3(0, 0, -0.0055), Vector3(0.0034, 0.003, 0.003), Color(0.35, 0.14, 0.07), Color(0.4, 0.18, 0.09))    # the eyes
	_ellipsoid(st, Vector3(0, 0, 0.003), Vector3(0.003, 0.0034, 0.0065), gold, gold)
	_limb(st, [Vector3(0, 0.0005, 0.008), Vector3(0, 0, 0.022), Vector3(0, -0.0005, 0.042)], 0.0014, 0.0009, [gold, Color(0.7, 0.4, 0.1)])
	var body := st.commit()
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.vertex_color_is_srgb = true
	bmat.roughness = 0.35
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for w in [[-0.001, 0.045, 0.011, -0.25], [0.008, 0.042, 0.014, 0.12]]:   # root z, length, width, sweep
			var root := Vector3(0.003 * side, 0.004, w[0])
			var tip := root + Vector3(float(w[1]) * side, 0.002, float(w[1]) * float(w[3]))
			var back := Vector3(0, 0, float(w[2]))
			var q := [root, root.lerp(tip, 0.55) - back * 0.15, tip, root.lerp(tip, 0.6) + back, root + back * 0.6]
			for tri in [[0, 1, 4], [1, 3, 4], [1, 2, 3]]:
				for idx in tri:
					wst.set_normal(Vector3.UP)
					wst.add_vertex(q[idx])
	var wings := wst.commit()
	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.62, 0.56, 0.44, 0.55)
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.roughness = 0.15
	wmat.metallic_specular = 0.8
	var sites: Array = []
	if not _ls.stream_pools.is_empty():
		var pond: Vector3 = _ls.stream_pools[_ls.stream_pools.size() - 1]["at"]
		sites.append([pond, 5.5, 5])
		if _ls.stream_pools.size() > 3:
			sites.append([_ls.stream_pools[2]["at"], 4.0, 2])
			sites.append([_ls.stream_pools[0]["at"], 4.0, 2])
	var trail: PackedVector2Array = _ls._trail
	if trail.size() > 5:
		sites.append([Vector3(trail[4].x, 0, trail[4].y), 9.0, 4])
		sites.append([Vector3(trail[trail.size() - 1].x, 0, trail[trail.size() - 1].y), 9.0, 4])
		sites.append([Vector3(trail[1].x, 0, trail[1].y), 7.0, 2])
	for s in sites:
		var c: Vector3 = s[0]
		c.y = maxf(_ls.ground(c.x, c.z), c.y)
		for k in int(s[2]):
			var root := Node3D.new()
			add_child(root)
			var bm := MeshInstance3D.new()
			bm.mesh = body
			bm.material_override = bmat
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(bm)
			var wm := MeshInstance3D.new()
			wm.mesh = wings
			wm.material_override = wmat
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(wm)
			root.scale = Vector3.ONE * _rng.randf_range(1.0, 1.2)
			var d := {"node": root, "wings": wm, "home": c, "r": float(s[1]), "pos": c + Vector3(0, 1.5, 0), "vel": Vector3.ZERO,
				"target": c + Vector3(0, 1.5, 0), "hover": 0.0, "dir": Vector3.FORWARD}
			_dragonfly_target(d)
			d["pos"] = d["target"]
			_dragonfly_target(d)
			dragonflies.append(d)
	# --- butterflies
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var orange := Color(0.9, 0.42, 0.06)
	var dark := Color(0.05, 0.035, 0.025)
	# one side's fore and hind wing, seen from above (x out, z back): the forewing drawn out to a
	# point, a notch where the two meet, the hindwing round
	var outline := [Vector2(0.002, -0.013), Vector2(0.02, -0.03), Vector2(0.046, -0.035), Vector2(0.045, -0.023), Vector2(0.037, -0.009),
		Vector2(0.03, -0.003), Vector2(0.035, 0.006), Vector2(0.031, 0.02), Vector2(0.019, 0.027), Vector2(0.007, 0.022), Vector2(0.002, 0.01)]
	var mid := Vector2(0.017, -0.004)
	for i in outline.size() - 1:
		var o0: Vector2 = outline[i]
		var o1: Vector2 = outline[i + 1]
		var i0 := mid.lerp(o0, 0.72)
		var i1 := mid.lerp(o1, 0.72)
		# (black tips with a white bar on the forewing, a dark rim elsewhere)
		var c0 := dark if (i >= 1 and i <= 4) else orange.lerp(dark, 0.75)
		var c1 := dark if (i + 1 >= 1 and i + 1 <= 4) else orange.lerp(dark, 0.75)
		var pale := Color(0.92, 0.9, 0.85) if (i == 2 or i == 3) else orange
		for v in [[mid, orange], [i0, pale], [i1, orange], [i0, pale], [o0, c0], [o1, c1], [i0, pale], [o1, c1], [i1, orange]]:
			bst.set_color(v[1])
			bst.set_normal(Vector3.UP)
			bst.add_vertex(Vector3((v[0] as Vector2).x, 0, (v[0] as Vector2).y))
	var wing := bst.commit()
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.vertex_color_is_srgb = true
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.roughness = 0.8
	var kst := SurfaceTool.new()
	kst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(kst, [Vector3(0, 0, -0.012), Vector3(0, 0, 0.0), Vector3(0, 0, 0.014)], 0.0022, 0.0012, [dark, dark])
	var bbody := kst.commit()
	for i in 6:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var bm := MeshInstance3D.new()
		bm.mesh = bbody
		bm.material_override = bmat
		root.add_child(bm)
		var pair: Array = []
		for side in [1.0, -1.0]:
			var wm := MeshInstance3D.new()
			wm.mesh = wing
			wm.material_override = fmat
			wm.scale = Vector3(side, 1, 1)
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(wm)
			pair.append(wm)
		root.scale = Vector3.ONE * _rng.randf_range(0.95, 1.2)
		butterflies.append({"node": root, "wings": pair, "home": Vector3(1e6, 0, 0), "pos": Vector3.ZERO, "yaw": _rng.randf() * TAU,
			"t": _rng.randf() * 100.0, "phase": 0.0, "glide": 0.0, "seed": _rng.randf() * TAU, "h": 1.2, "wait": _rng.randf_range(0.0, 6.0)})


func _dragonfly_target(d: Dictionary) -> void:
	var home: Vector3 = d["home"]
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * float(d["r"])
	var x := home.x + cos(a) * r
	var z := home.z + sin(a) * r
	d["target"] = Vector3(x, maxf(_ls.ground(x, z), home.y - 0.3) + _rng.randf_range(0.5, 2.8), z)


func _update_insects(delta: float) -> void:
	if _player == null:
		return
	var pp := _player.global_position
	var day := _night() < 0.35 and not raining
	for d: Dictionary in dragonflies:
		var n: Node3D = d["node"]
		var home: Vector3 = d["home"]
		var near_d := Vector2(home.x - pp.x, home.z - pp.z).length() < 70.0
		# Night or rain: it flies down among the plants and settles there (it used to be
		# switched off in the air); when the day is back, or the rain over, it takes off
		# from that place.
		if not near_d:
			n.visible = false
			d["out"] = false
			continue
		if not d.has("perch"):
			var pa := _rng.randf() * TAU
			var px: float = home.x + cos(pa) * (float(d["r"]) * 0.6)
			var pz: float = home.z + sin(pa) * (float(d["r"]) * 0.6)
			d["perch"] = Vector3(px, float(_ls.ground(px, pz)) + 0.22, pz)
			d["out"] = day
			d["settle"] = 0.0
			d["down"] = false
		if day:
			d["down"] = false
			if not d["out"]:
				# (up again, a moment after the rain or the night is over: each in its own time)
				d["settle"] = float(d["settle"]) - delta
				if float(d["settle"]) > 0.0:
					continue
				d["out"] = true
				d["pos"] = d["perch"]
				d["vel"] = Vector3.ZERO
				_dragonfly_target(d)
		if not d["out"]:
			n.visible = false
			continue
		n.visible = true
		var pos: Vector3 = d["pos"]
		var vel: Vector3 = d["vel"]
		if not day:
			if not d["down"]:
				d["down"] = true
				d["settle"] = _rng.randf_range(0.5, 5.0)      # (not all at one moment)
			d["settle"] = float(d["settle"]) - delta
			if float(d["settle"]) <= 0.0:
				d["target"] = d["perch"]
				d["hover"] = 0.0
				if pos.distance_to(d["perch"]) < 0.35:
					d["out"] = false
					d["settle"] = _rng.randf_range(1.0, 8.0)
					n.visible = false
					continue
		var to: Vector3 = (d["target"] as Vector3) - pos
		if d["hover"] > 0.0:
			d["hover"] -= delta
			vel = vel.lerp(Vector3.ZERO, 1.0 - exp(-9.0 * delta))
		else:
			vel = vel.lerp(to.normalized() * minf(4.0, 1.0 + to.length() * 2.0), 1.0 - exp(-5.0 * delta))
			if to.length() < 0.4 and (day or float(d["settle"]) > 0.0):
				if _rng.randf() < 0.45:
					d["hover"] = _rng.randf_range(0.15, 1.3)
				_dragonfly_target(d)
		pos += vel * delta
		d["pos"] = pos
		d["vel"] = vel
		var flat := Vector3(vel.x, 0, vel.z)
		if flat.length() > 0.4:
			d["dir"] = (d["dir"] as Vector3).slerp(flat.normalized(), 1.0 - exp(-12.0 * delta)).normalized()
		n.global_transform = Transform3D(Basis.looking_at(d["dir"], Vector3.UP).scaled(n.scale), pos + Vector3(0, sin(Time.get_ticks_msec() * 0.02 + pos.x) * 0.004, 0))
		# the wings beat too fast to see: a flicker
		(d["wings"] as Node3D).rotation.z = _rng.randf_range(-0.3, 0.3)
	for d: Dictionary in butterflies:
		var n: Node3D = d["node"]
		var home: Vector3 = d["home"]
		if not day:
			# Night or rain: up into the leaves, and gone among them (it used to be switched
			# off where it flew).
			if not n.visible or Vector2(home.x - pp.x, home.z - pp.z).length() > 38.0:
				n.visible = false
				d["home"] = Vector3(1e6, 0, 0)
				continue
			if not d.has("up") or float(d["up"]) <= 0.0:
				d["up"] = _rng.randf_range(3.0, 7.5)
			d["up"] = float(d["up"]) - delta
			if float(d["up"]) <= 0.0:
				n.visible = false
				d["home"] = Vector3(1e6, 0, 0)
				continue
		else:
			d["up"] = 0.0
		if Vector2(home.x - pp.x, home.z - pp.z).length() > 38.0:
			# a new place near the walker, mostly ahead of them, at the edge of the forest or in it
			n.visible = false
			d["wait"] -= delta
			if d["wait"] > 0.0:
				continue
			d["wait"] = 1.5
			var a := _rng.randf() * TAU
			var yaw: Variant = _player.get("_yaw")
			if yaw != null and _rng.randf() < 0.7:
				a = -float(yaw) - PI * 0.5 + _rng.randf_range(-0.8, 0.8)
			var r := _rng.randf_range(7.0, 16.0)
			var c := Vector3(pp.x + cos(a) * r, 0, pp.z + sin(a) * r)
			var g: float = _ls.ground(c.x, c.z)
			if g < 1.0 or _ls.cave_dist(Vector2(c.x, c.z)) < 6.0 or absf(g - pp.y) > 6.0:
				continue
			c.y = g
			d["home"] = c
			d["pos"] = c + Vector3(0, 1.2, 0)
			d["wait"] = _rng.randf_range(3.0, 12.0)
			n.visible = true
		d["t"] += delta
		var t: float = d["t"]
		var pos: Vector3 = d["pos"]
		# an unsteady course: the heading wanders, and turns for home when it has strayed
		var yawr := sin(t * 1.3 + d["seed"]) * 1.6 + sin(t * 3.1 + d["seed"] * 2.0) * 1.1
		var back := Vector3(home.x - pos.x, 0, home.z - pos.z)
		if back.length() > 7.0:
			var want := atan2(-back.z, back.x)
			yawr += clampf(angle_difference(d["yaw"], want), -1.0, 1.0) * 2.5
		d["yaw"] += yawr * delta
		var dir := Vector3(cos(d["yaw"]), 0, -sin(d["yaw"]))
		pos += dir * 1.15 * delta
		# a few beats, a short glide with the wings held up, the body bouncing with every beat
		d["glide"] -= delta
		if d["glide"] < -_rng.randf_range(0.6, 2.5):
			d["glide"] = _rng.randf_range(0.2, 0.5)
		var beating: bool = d["glide"] < 0.0
		if beating:
			d["phase"] += delta * 58.0
		var ang := (0.5 + 0.85 * sin(d["phase"])) if beating else 0.55
		var want_h: float = _ls.ground(pos.x, pos.z) + 1.3 + 0.6 * sin(t * 0.7 + d["seed"]) + 0.25 * sin(t * 2.3)
		if float(d.get("up", 0.0)) > 0.0 and float(d["up"]) < 3.0:
			want_h = pos.y + 1.6       # (the last three seconds: climbing into the foliage)
		pos.y = lerpf(pos.y, want_h + (0.04 * cos(d["phase"]) if beating else 0.0), 1.0 - exp(-3.0 * delta))
		d["pos"] = pos
		n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).scaled(n.scale), pos)
		((d["wings"] as Array)[0] as Node3D).rotation.z = ang
		((d["wings"] as Array)[1] as Node3D).rotation.z = -ang


## For the tests: who of the roost, the dragonflies and the butterflies shows now.
func leave_report() -> Dictionary:
	var hanging := 0
	for d: Dictionary in roost:
		if (d["root"] as Node3D).visible:
			hanging += 1
	var df := 0
	var low := 0
	for d: Dictionary in dragonflies:
		if (d["node"] as Node3D).visible:
			df += 1
			if d.get("down", false) and float(d.get("settle", 1.0)) <= 0.0:
				low += 1
	var bf := 0
	var rising := 0
	for d: Dictionary in butterflies:
		if (d["node"] as Node3D).visible:
			bf += 1
			if float(d.get("up", 0.0)) > 0.0:
				rising += 1
	return {"flying foxes hanging in the roost": "%d of %d" % [hanging, roost.size()], "dragonflies in the air": "%d of %d (%d on their way down)" % [df, dragonflies.size(), low],
		"butterflies in the air": "%d of %d (%d leaving)" % [bf, butterflies.size(), rising]}


# ================================================================== water sounds
var _stream_players: Array[AudioStreamPlayer3D] = []
var _surf_player: AudioStreamPlayer3D
var _surf_spots: PackedVector3Array = PackedVector3Array()
var _surf_timer := 0.0

func _loop(file: String) -> AudioStream:
	if not ResourceLoader.exists(A + file):
		return null
	var s := load(A + file) as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _setup_sounds() -> void:
	var st := _loop("stream.wav")
	if st:
		for pl in _ls.stream_pools:
			var p := AudioStreamPlayer3D.new()
			p.stream = st
			p.unit_size = 2.2 if pl["pond"] else 3.0
			p.max_distance = 26.0
			p.volume_db = -9.0 if pl["pond"] else -5.0
			p.pitch_scale = _rng.randf_range(0.92, 1.1)
			p.bus = "Ambient"
			add_child(p)
			p.global_position = (pl["at"] as Vector3) + Vector3(0, 0.2, 0)
			p.play(_rng.randf() * 20.0)
			_stream_players.append(p)
	# the surf: heard from the nearest stretch of the reef crest where the swell breaks
	var hw := Heights.width()
	var hh := Heights.height()
	var step := 16
	for y in range(0, hh, step):
		for x in range(hw / 2, hw, step):
			if Heights.pixel(x, y, 2) > 0.55:
				_surf_spots.append(Vector3((x + 0.5) / hw * 512.0 - 256.0, 0.5, (y + 0.5) / hh * 512.0 - 256.0))
	var sf := _loop("reef_surf.wav")
	if sf and not _surf_spots.is_empty():
		_surf_player = AudioStreamPlayer3D.new()
		_surf_player.stream = sf
		_surf_player.unit_size = 55.0
		_surf_player.max_distance = 700.0
		_surf_player.volume_db = -3.0
		_surf_player.attenuation_filter_cutoff_hz = 9000.0
		_surf_player.bus = "Ambient"
		add_child(_surf_player)
		_surf_player.global_position = _surf_spots[0]
		_surf_player.play(_rng.randf() * 20.0)


func _update_sounds(delta: float) -> void:
	if _surf_player == null or _player == null:
		return
	_surf_timer -= delta
	if _surf_timer > 0.0:
		return
	_surf_timer = 0.5
	var pp := _player.global_position
	var best := _surf_spots[0]
	for s in _surf_spots:
		if s.distance_squared_to(pp) < best.distance_squared_to(pp):
			best = s
	_surf_player.global_position = _surf_player.global_position.lerp(best, 0.25)
