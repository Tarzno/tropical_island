extends SceneTree
## Writes down what one or more imported model files hold, mesh by mesh (names, places,
## materials, counts, and a checksum of every surface's arrays, of its LODs and of the shadow
## mesh), sorted by node name: to prove that splitting or re-exporting a model changed nothing.
##   Godot --path . --script tools/leaf_dump.gd -- out.txt res://assets/models/leaves.glb [more.glb ...]
## (with a window: the headless renderer keeps no LODs)
## Run it before and after and diff the two files (used for the split of leaves.glb, 2026-11-13).

func _md5(v: Variant) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(var_to_bytes(v))
	return h.finish().hex_encode().substr(0, 16)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var lines := PackedStringArray()
	var verts := 0
	for i in range(1, args.size()):
		var ps := load(args[i]) as PackedScene
		if ps == null:
			printerr("cannot load ", args[i])
			quit(1)
			return
		var root := ps.instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var m := mi.mesh as ArrayMesh
			var l := "%s | parent %s | xf %s | mesh %s | aabb %s | shadow %s" % [mi.name, mi.get_parent().name if mi.get_parent() != root else "(root)",
				mi.transform, m.resource_name, m.get_aabb(), _md5(m.shadow_mesh.surface_get_arrays(0)) if m.shadow_mesh else "none"]
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var mat := m.surface_get_material(s)
				verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				l += "\n    surface %d: %s | mat %s %s | format %d | verts %d | index %d | arrays %s | lods %s" % [s, m.surface_get_name(s),
					mat.resource_name if mat else "none", _md5([mat.get("albedo_color"), mat.get("roughness"), mat.get("clearcoat"), mat.get("cull_mode")]) if mat else "",
					m.surface_get_format(s), (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
					(arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else 0, _md5(arr), _md5((RenderingServer.mesh_get_surface(m.get_rid(), s) as Dictionary).get("lods", []))]
			lines.append(l)
		root.free()
	lines.sort()
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("%d meshes, %d vertices -> %s" % [lines.size(), verts, args[0]])
	quit()
