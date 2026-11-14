extends SceneTree
## Throw-away check: is any mesh in the scene inside out? For every MeshInstance3D with a
## closed-looking mesh (rocks, boulders, the grotto, trunks ...) it works out which way the
## faces look as a volume (world.gd: facing_volume(); negative: the fronts look inward) and
## counts the open edges. Prints every mesh that is inside out, and a line per group.
##   godot --headless --path . --script tools/facecheck.gd
## (2026-11-12: Rocks/Boulders_001 from the .blend was inside out for the whole life of the
## project; world.gd: _right_side_out() turns it at start-up, so it shows here as "turned".)
var _main: Node
var _wait := 60

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)

func _process(_dt: float) -> bool:
	_wait -= 1
	if _wait > 0:
		return false
	var world: Script = load("res://scripts/world.gd")
	var checked := {}
	var groups := {}
	for mi: MeshInstance3D in _main.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not (mi.mesh is ArrayMesh) or checked.has(mi.mesh):
			continue
		checked[mi.mesh] = true
		var path := str(_main.get_path_to(mi))
		var group := path.get_slice("/", 0) + ("/" + path.get_slice("/", 1) if path.get_slice_count("/") > 2 else "")
		if not groups.has(group):
			groups[group] = [0, 0]
		for surf in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(surf)
			if arr[Mesh.ARRAY_INDEX] == null:
				continue
			var vol: float = world.facing_volume(mi.mesh, surf)
			var box := mi.mesh.get_aabb()
			# (flat things, leaves and the like, have next to no volume: not judged)
			var full := box.size.x * box.size.y * box.size.z
			if full < 1e-6 or absf(vol) < full * 0.08:
				continue
			groups[group][0] += 1
			if vol < 0.0:
				groups[group][1] += 1
				print("INSIDE OUT: ", path, " surface ", surf, "  volume ", snappedf(vol, 0.01), " of a box of ", snappedf(full, 0.01))
		if mi.has_meta("turned"):
			print("turned at start-up: ", path)
	for g: String in groups:
		if int(groups[g][0]) > 0:
			print("%-40s %4d solid meshes, %d inside out" % [g, groups[g][0], groups[g][1]])
	return true
