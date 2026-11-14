extends SceneTree
## Throw-away check: which rock meshes are open underneath and hang over the sea floor?
##   godot --path . --script tools/rockcheck.gd
## For every MeshInstance3D that reaches under the sea (not the terrain, not the sea itself) it
## finds the open edges of the mesh (edges that belong to one triangle only) and compares the
## height of their ends with the ground under them. Prints the meshes whose open rim hangs
## clear of the floor under water, and by how much.
var _main: Node
var _wait := 90

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)

func _process(_dt: float) -> bool:
	_wait -= 1
	if _wait > 0:
		return false
	var ls := _main.get_node("Landscape")
	var n_open := 0
	var worst := 0.0
	var by_parent := {}
	for mi: MeshInstance3D in _main.find_children("*", "MeshInstance3D", true, false):
		var path := str(_main.get_path_to(mi))
		if mi.mesh == null or not (path.begins_with("Rocks") or path.begins_with("Hills") or path.begins_with("Landscape/Boulders") or path.begins_with("Landscape/Grotto")):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if box.position.y > 0.2:
			continue
		var gap := 0.0
		var at := Vector3.ZERO
		var rim := 0
		var lowest := 1e9
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				continue
			# (vertices at the same place count as one: a split for the UVs is not an open edge)
			var ids := PackedInt32Array()
			ids.resize(v.size())
			var seen := {}
			for i in v.size():
				var key := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
				if not seen.has(key):
					seen[key] = i
				ids[i] = seen[key]
			var edges := {}
			for t in range(0, idx.size(), 3):
				for k in 3:
					var a := ids[idx[t + k]]
					var b := ids[idx[t + (k + 1) % 3]]
					var e := Vector2i(mini(a, b), maxi(a, b))
					edges[e] = int(edges.get(e, 0)) + 1
			for e: Vector2i in edges:
				if edges[e] != 1:
					continue
				for i in [e.x, e.y]:
					var w: Vector3 = mi.global_transform * v[i]
					rim += 1
					lowest = minf(lowest, w.y)
					var g: float = ls.ground(w.x, w.z)
					if g < -0.3 and w.y - g > gap:
						gap = w.y - g
						at = w
		if rim > 0 and gap > 0.08:
			n_open += 1
			worst = maxf(worst, gap)
			var par := path.get_base_dir()
			by_parent[par] = int(by_parent.get(par, 0)) + 1
			if gap > 0.08:
				print("  rim vertices %d, lowest rim %.2f, surfaces %d, vertices %d" % [rim, lowest, mi.mesh.get_surface_count(), (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()])
				print("%-40s rim hangs %.2f m over the floor at (%.1f, %.1f, %.1f), size %s" % [path, gap, at.x, at.y, at.z, box.size.snappedf(0.1)])
	print("meshes with an open rim hanging over the sea floor: ", n_open, "; worst ", worst, "; by parent ", by_parent)
	return true
