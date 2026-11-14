extends Node3D
## Life in the tide pools of the east headland (the node is created by island_life.gd). When
## the tide has fallen below a pool's rim the pool is its own small sea: a few rockskippers
## (little blennies, the mudskipper's shape and size, darker) lie on its floor and
## dart off in short jerks, a cushion star, long-spined urchins in its deepest corners, and
## nerite snails on the rock around its rim. With the sea over the pools none of it is shown
## (it is all still there, under the waves). For the tests: report(), soak().

const SmallModels := preload("res://scripts/small_models.gd")
const LM := preload("res://scripts/land_models.gd")

var pools: Array = []      # {"pool": the landscape's entry, "node", "floor": [Vector3], "fish": [dict], "mm"}
var _ls: Node
var _player: Node3D
var _rng := RandomNumberGenerator.new()


var _seabed: Node
var _built := false


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed


## The pool's floor as it is drawn and walked on (the terrain's mesh is coarser than the
## height map: by the map's heights everything in the deep middle of a pool lay buried).
func _floor_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1.5, z), Vector3(x, -1.5, z))
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else float(_ls.ground(x, z))


func _physics_process(_delta: float) -> void:
	# (the floor is found with rays: the collision shapes are there after a few frames)
	if not _built and Engine.get_physics_frames() > 32:
		_built = true
		_build(_seabed)


func _build(seabed: Node) -> void:
	_rng.seed = 60606
	var fish_mesh: ArrayMesh = SmallModels.mudskipper()
	var fish_mat := StandardMaterial3D.new()
	fish_mat.vertex_color_use_as_albedo = true
	fish_mat.vertex_color_is_srgb = true
	fish_mat.albedo_color = Color(0.5, 0.46, 0.4)
	fish_mat.roughness = 0.3
	fish_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var star_mesh: ArrayMesh = seabed._star_mesh(2)
	var star_mat := StandardMaterial3D.new()
	star_mat.vertex_color_use_as_albedo = true
	star_mat.roughness = 0.7
	var urchin_mesh: ArrayMesh = seabed._urchin_mesh
	var urchin_w := maxf(urchin_mesh.get_aabb().size.x, 0.001)
	var shell: Dictionary = LM.shell(1, 0.021)
	var shell_mat := LM.shell_material()
	for tp: Dictionary in _ls.tide_pools:
		var at: Vector3 = tp["at"]
		var rx: float = tp["rx"]
		var rz: float = tp["rz"]
		# the pool's floor: places with a hand's depth of water over them, deepest first
		var floor_pts: Array = []
		var rim: Array = []
		for i in 400:
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 1.15
			var p := Vector3(at.x + cos(a) * r * rx, 0, at.z + sin(a) * r * rz)
			p.y = _floor_y(p.x, p.z)
			if r < 0.85 and at.y - p.y > 0.05:
				floor_pts.append(p)
			elif p.y > at.y + 0.015 and p.y < at.y + 0.2 and rim.size() < 40:
				rim.append(p)
		if floor_pts.size() < 6:
			continue
		floor_pts.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.y < q.y)
		var node := Node3D.new()
		node.name = "Pool%d" % pools.size()
		add_child(node)
		node.visible = false
		var used: Array = []
		# urchins in the deepest places, a cushion star in every other pool
		var things: Array = []
		for p: Vector3 in floor_pts:
			if things.size() >= _rng.randi_range(2, 3):
				break
			if _apart(p, used, 0.3):
				used.append(p)
				things.append(p)
		_multi(node, "Urchins", urchin_mesh, seabed._urchin_mat, things, 0.2 / urchin_w, 0.26 / urchin_w, false)
		if pools.size() % 2 == 0:
			for k in 40:
				var p: Vector3 = floor_pts[_rng.randi() % floor_pts.size()]
				if _apart(p, used, 0.22):
					used.append(p)
					var mmi := _multi(node, "Star", star_mesh, star_mat, [p], 0.55, 0.7, true)
					mmi.multimesh.set_instance_color(0, [Color(0.6, 0.42, 0.36), Color(0.5, 0.5, 0.4), Color(0.62, 0.4, 0.45)][pools.size() / 2 % 3])
					break
		# nerites on the rock of the rim, mouth down
		var snails := MultiMesh.new()
		snails.transform_format = MultiMesh.TRANSFORM_3D
		snails.mesh = shell["mesh"]
		var where: Array = []
		for p: Vector3 in rim:
			if where.size() < 7 and _apart(p, where, 0.12):
				where.append(p)
		snails.instance_count = where.size()
		for i in where.size():
			var a := _rng.randf() * TAU
			var b: Basis = LM.shell_basis(Vector3(0.0, -1.0, 0.0), Vector3(cos(a), 0.25, sin(a))).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.2))
			var xf := Transform3D(b, where[i])
			xf.origin.y += (where[i] as Vector3).y + 0.001 - LM._lowest(shell["mesh"], xf)
			snails.set_instance_transform(i, xf)
		var smi := MultiMeshInstance3D.new()
		smi.name = "Nerites"
		smi.multimesh = snails
		smi.material_override = shell_mat
		node.add_child(smi)
		# the rockskippers
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = fish_mesh
		var fish: Array = []
		for k in 60:
			if fish.size() >= clampi(floor_pts.size() / 25, 2, 4):
				break
			var p: Vector3 = floor_pts[_rng.randi() % floor_pts.size()]
			if _apart(p, used, 0.22):
				used.append(p)
				fish.append({"pos": p, "to": p, "yaw": _rng.randf() * TAU, "t": _rng.randf_range(3.0, 14.0), "speed": 0.0, "calm": 0.0,
					"size": _rng.randf_range(0.9, 1.15), "way": 0.0})
		mm.instance_count = fish.size()
		var fmi := MultiMeshInstance3D.new()
		fmi.name = "Rockskippers"
		fmi.multimesh = mm
		fmi.material_override = fish_mat
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(fmi)
		var entry := {"pool": tp, "node": node, "floor": floor_pts, "fish": fish, "mm": mm, "fixed": used.slice(0, used.size() - fish.size())}
		pools.append(entry)
		for i in fish.size():
			_pose(entry, i)


func _apart(p: Vector3, others: Array, gap: float) -> bool:
	for o: Vector3 in others:
		if Vector2(o.x - p.x, o.z - p.z).length() < gap:
			return false
	return true


func _multi(parent: Node3D, name_: String, mesh: Mesh, mat: Material, at: Array, s0: float, s1: float, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(s0, s1)), at[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _pose(e: Dictionary, i: int) -> void:
	var f: Dictionary = e["fish"][i]
	(e["mm"] as MultiMesh).set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(f["yaw"])).scaled(Vector3.ONE * float(f["size"])), (f["pos"] as Vector3) + Vector3(0, 0.002, 0)))


## A place on the pool's floor for a fish to go to: `from` given, the free place furthest
## from it (somebody is standing there); else one a hand or two away.
func _goal(e: Dictionary, f: Dictionary, from: Variant) -> Vector3:
	var best: Vector3 = f["pos"]
	var best_d := -1.0
	var others: Array = (e["fixed"] as Array).duplicate()
	for o: Dictionary in e["fish"]:
		if not is_same(o, f):
			others.append(o["to"])
	for k in 14:
		var p: Vector3 = e["floor"][_rng.randi() % (e["floor"] as Array).size()]
		if not _apart(p, others, 0.13):
			continue
		var d := 0.0
		if from != null:
			d = Vector2(p.x - (from as Vector3).x, p.z - (from as Vector3).z).length()
		else:
			var step := Vector2(p.x - (f["pos"] as Vector3).x, p.z - (f["pos"] as Vector3).z).length()
			d = 1.0 - absf(step - 0.2) if step > 0.06 and step < 0.45 else -1.0
		if d > best_d:
			best_d = d
			best = p
	return best


func _process(delta: float) -> void:
	if _player == null:
		return
	_step(minf(delta, 0.1), _player.global_position)


func _step(delta: float, pp: Vector3) -> void:
	for e: Dictionary in pools:
		var shown: bool = ((e["pool"] as Dictionary)["node"] as Node3D).visible
		(e["node"] as Node3D).visible = shown
		var at: Vector3 = (e["pool"] as Dictionary)["at"]
		if not shown or Vector2(pp.x - at.x, pp.z - at.z).length() > 30.0:
			continue
		for i in (e["fish"] as Array).size():
			var f: Dictionary = e["fish"][i]
			var pos: Vector3 = f["pos"]
			f["t"] = float(f["t"]) - delta
			f["calm"] = maxf(float(f["calm"]) - delta, 0.0)
			var to := Vector3((f["to"] as Vector3).x - pos.x, 0, (f["to"] as Vector3).z - pos.z)
			var near := Vector2(pp.x - pos.x, pp.z - pos.z).length() < 1.2 and absf(pp.y - pos.y) < 2.5
			if to.length() < 0.012:
				f["speed"] = 0.0
				if near and float(f["calm"]) <= 0.0:
					# a shadow over the pool: off to its far side, and still again
					f["to"] = _goal(e, f, pp)
					f["speed"] = 0.6
					f["calm"] = _rng.randf_range(2.5, 5.0)
				elif float(f["t"]) <= 0.0:
					f["to"] = _goal(e, f, null)
					f["speed"] = 0.3
					f["t"] = _rng.randf_range(4.0, 16.0)
				continue
			# a rockskipper moves in jerks: a dart, and it lies still
			var step := minf(float(f["speed"]) * delta, to.length())
			f["yaw"] = atan2(-to.x, -to.z)
			var np := pos + to.normalized() * step
			np.y = _floor_y(np.x, np.z)
			if at.y - np.y < 0.04:
				# (a hump in the floor with hardly any water over it: it stays on this side)
				f["to"] = pos
				continue
			pos = np
			f["pos"] = pos
			f["way"] = float(f["way"]) + step
			_pose(e, i)


func report() -> Dictionary:
	var out := {"pools with life": pools.size(), "shown": 0, "fish": 0, "at": []}
	for e: Dictionary in pools:
		out["fish"] += (e["fish"] as Array).size()
		if (e["node"] as Node3D).visible:
			out["shown"] += 1
		(out["at"] as Array).append(((e["pool"] as Dictionary)["at"] as Vector3).snapped(Vector3(0.1, 0.01, 0.1)))
	return out


## Ten minutes of the fishes' lives with somebody walking from pool to pool: how far they
## swam, and whether one ever left the water of its pool.
func soak(seconds := 600.0) -> Dictionary:
	if pools.is_empty():
		return {"pools": 0}
	var dry := 0
	var samples := 0
	var way := 0.0
	var dt := 0.05
	for s in int(seconds / dt):
		var e: Dictionary = pools[int(s * dt / 40.0) % pools.size()]
		var at: Vector3 = (e["pool"] as Dictionary)["at"]
		var a := s * dt * 0.2
		_step(dt, at + Vector3(cos(a) * 0.9, 1.0, sin(a) * 0.9))
		if s % 10 == 0:
			for f: Dictionary in e["fish"]:
				samples += 1
				if at.y - (f["pos"] as Vector3).y < 0.03:
					dry += 1
	for e: Dictionary in pools:
		for f: Dictionary in e["fish"]:
			way += float(f["way"])
	return {"samples": samples, "fish out of the water": dry, "swum in all (m)": way}
