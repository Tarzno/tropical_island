extends Node
## For the tests (tools/shot.gd: "add_tool('res://tools/leaf_check.gd', 'LeafCheck')"): are the
## forest's dense leaves whole after the join of their four files (scripts/world.gd:
## _join_leaves())? "main.get_node('LeafCheck').report(main)".
func report(main: Node) -> String:
	var leaves := main.get_node("Leaves")
	var n := 0
	var ranged := 0
	var dressed := 0
	var no_shadow := 0
	var verts := 0
	var names := {}
	for m in leaves.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		n += 1
		names[mi.name] = true
		if is_equal_approx(mi.visibility_range_end, 34.0):
			ranged += 1
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			no_shadow += 1
		var all := true
		for s in mi.mesh.get_surface_count():
			verts += mi.mesh.surface_get_array_len(s)
			if mi.get_surface_override_material(s) == null:
				all = false
		if all:
			dressed += 1
	return "%d meshes (%d names), %d vertices; range to 34 m: %d; every surface with the game's material: %d; no shadow: %d; direct children: %d" % [
		n, names.size(), verts, ranged, dressed, no_shadow, leaves.get_child_count()]
