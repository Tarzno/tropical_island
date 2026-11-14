extends SceneTree
## Throw-away check, like tools/placements.gd but for the sea: writes what stands on the sea
## floor (every MultiMesh of the Seabed: where, how many, a hash of the places) and where the
## reef's animals live (dens, lionfish, eel colonies, the grouper, the triggerfish, anemones
## with fish) to a text file, sorted. Run before and after a change and compare: placements
## hang together through the random numbers they draw.
##   godot --path . --script tools/reef_placements.gd -- /tmp/before.txt
var _main: Node
var _frames := 0
var _settled := 0
func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
func _process(_dt: float) -> bool:
	_frames += 1
	if _frames > 4000:
		print("gave up")
		return true
	var sb := _main.get_node_or_null("IslandLife/Seabed")
	var rl := _main.get_node_or_null("IslandLife/ReefLife")
	if sb == null or rl == null or not sb.done() or not rl.get("_placed") or _frames < 60:
		return false
	if sb.has_method("garden_done") and not sb.garden_done():
		return false
	_settled += 1
	if _settled < 90:
		return false
	var out := PackedStringArray()
	for c in sb.get_children():
		var mi := c as MultiMeshInstance3D
		if mi == null:
			continue
		var mm := mi.multimesh
		var h := 0
		for i in mm.instance_count:
			var o := mm.get_instance_transform(i).origin
			h = hash([h, snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001)])
		out.append("MM %.2f %.2f %.2f n %d range %.0f-%.0f verts %d hash %d" % [mi.position.x, mi.position.y, mi.position.z, mm.instance_count, mi.visibility_range_begin,
			mi.visibility_range_end, mm.mesh.get_faces().size(), h])
	for m in rl.morays:
		out.append("MORAY %s" % str(m["pos"]))
	for m in rl.octopuses:
		out.append("OCTOPUS %s" % str(m["pos"]))
	for l in rl.lionfish:
		out.append("LIONFISH %s r %.2f sides %d" % [str(l["c"]), l["r"], (l["sides"] as Array).size()])
	for c in rl.colonies:
		out.append("EELS %s n %d" % [str(c["pos"]), (c["eels"] as Array).size()])
	if not (rl.grouper as Dictionary).is_empty():
		out.append("GROUPER %s" % str(rl.grouper["home"]))
	for t in rl.triggers:
		out.append("TRIGGER %s" % str(t["home"]))
	for a in rl.anemones:
		out.append("ANEMONE %s fish %d" % [str(a["pos"]), (a["fish"] as Array).size()])
	out.append("COUNTS corals %d urchins %d stars %d clams %d grass %d dens %d edge %d sand %d big %d anemone_spots %d" % [sb.corals, sb.urchins, sb.stars, sb.clams, sb.grass_tufts,
		(sb.den_spots as Array).size(), (sb.edge_spots as Array).size(), (sb.sand_spots as Array).size(), (sb.big_corals as Array).size(), (sb.anemone_spots as Array).size()])
	out.sort()
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("wrote ", out.size(), " lines")
	return true
