extends Node
## For the tests (tools/shot.gd: "add_tool('res://tools/rock_stand.gd', 'Rock')"): a player who
## stands on a rock that rises out of deep water must walk there, not swim (a fault found on
## 2026-11-13). "main.get_node('Rock').spots(main, 6)" looks for such places (a rock's top at
## least half a meter above the sea, the sea floor under it deeper than a swimmer's depth),
## "put(main, i)" stands the player on one, "state(main)" says what the player is doing,
## "tap('jump')" presses a key for a moment.
var found: Array = []


func spots(main: Node, n: int) -> Array:
	found = []
	var pl := main.get_node("Player") as CharacterBody3D
	var space := pl.get_world_3d().direct_space_state
	var sea: float = pl._tide()
	for xi in range(-110, 111):
		for zi in range(-120, 121):
			var x := xi * 2.0
			var z := zi * 2.0
			var floor_y: float = pl.ground_height(Vector2(x, z))
			if sea - floor_y < 1.6 or sea - floor_y > 7.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, sea + 0.5, z), 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit.normal as Vector3).y < 0.85:
				continue
			found.append(hit.position)
	# the widest apart first: one from each stretch of shore
	found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x + a.z * 3.0 < b.x + b.z * 3.0)
	var out: Array = []
	for i in n:
		if found.size() > 0:
			out.append(found[int(float(i) / n * found.size())])
	found = out
	return out


func put(main: Node, i: int) -> Vector3:
	var pl := main.get_node("Player") as CharacterBody3D
	pl.global_position = (found[i] as Vector3) + Vector3(0, 0.05, 0)
	pl.velocity = Vector3.ZERO
	return pl.global_position


func state(main: Node) -> Dictionary:
	var pl := main.get_node("Player") as CharacterBody3D
	var sea: float = pl._tide()
	var p := pl.global_position
	return {"swimming": pl._swimming, "diving": pl.diving, "on a floor": pl.is_on_floor(), "feet above the sea (m)": snappedf(p.y - sea, 0.01),
		"water over the sea floor here (m)": snappedf(sea - pl.ground_height(Vector2(p.x, p.z)), 0.01), "eyes above the feet (m)": snappedf(pl.head.position.y, 0.01),
		"speed (m/s)": snappedf(pl.velocity.length(), 0.01), "dives so far": pl.dives, "at": p.snappedf(0.1)}


func tap(action: String) -> String:
	Input.action_press(action)
	get_tree().create_timer(0.12).timeout.connect(Input.action_release.bind(action))
	return action
