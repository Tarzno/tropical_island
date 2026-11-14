extends SceneTree
## Throw-away check: writes where every boulder, palm, tree and mangrove stands to a text file,
## one per line. Run it before and after a change to the terrain or to the placement code and
## compare the two files: placements hang together through the random numbers they draw, and
## a change in one corner of the island can move things in another (see HANDOFF.md, "Gotchas").
##   godot --headless --path . --script tools/placements.gd -- /tmp/before.txt
##   ... the change, then `godot --headless --path . --import` if the terrain was rewritten ...
##   godot --headless --path . --script tools/placements.gd -- /tmp/after.txt ; diff /tmp/before.txt /tmp/after.txt
var _main: Node
var _wait := 40
func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
func _process(_dt: float) -> bool:
	_wait -= 1
	if _wait > 0:
		return false
	var ls := _main.get_node("Landscape")
	var out := PackedStringArray()
	for b in ls.boulder_spots:
		out.append("B %.2f %.2f %.2f %.2f" % [b[0].x, b[0].y, b[0].z, b[1]])
	for t in ls.palm_trunks:
		var p: Vector3 = (t["pts"] as PackedVector3Array)[0]
		out.append("P %.2f %.2f %.2f" % [p.x, p.y, p.z])
	for t in ls.tree_spots:
		var o: Vector3 = (t["xf"] as Transform3D).origin
		out.append("T %.2f %.2f %.2f" % [o.x, o.y, o.z])
	for m in ls.mangrove_spots:
		out.append("M %s" % str(m))
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string("\n".join(out))
	return true
