extends SceneTree
## Throw-away driver: loads main.tscn, runs the jobs of a JSON file and quits.
##   godot --path . --script shot.gd -- job.json
## Compass: +x west (out to sea from the start beach), -x east, +z north, -z south; a shot's
## yaw 0 looks south (-z), -90 west, 90 east, 180 north.
## Job kinds: shot (camera picture), walk (the player walks waypoints with collision), fps, uncap,
## expr (GDScript expressions on main / the Landscape node), tree, hm, tod, chase (the camera
## follows a node for a while and saves a picture every few frames; look: a picture from the
## walker's eyes at a node or a place, {"kind": "look", "at": "<expression>", "fov": 72, "out": "x.png"}:
## {"kind": "chase", "node": "<expression giving a Node3D>", "offset": [x, y, z], "n": 12, "every": 15,
##  "out": "name_%02d.png", "local": true (offset in the node's own axes), "fov": 50}).

var _jobs: Array = []
var _main: Node
var _cam: Camera3D
var _player: CharacterBody3D
var _i := -1
var _wait := 0
var _out_dir := ""
# walking
var _walk: Dictionary = {}
var _wp := 0
var _walk_t := 0.0
var _last := Vector3.ZERO
var _still := 0.0
var _max_still := 0.0
var _jumps := 0
var _travel := 0.0
var _avoid := 0.0
var _avoid_sign := 1.0
var _holdups := 0
var _wp_holdups := 0
var _skipped := 0
var _reached := 0
# chasing
var _chase: Dictionary = {}
var _chase_node: Node3D
var _chase_f := 0
# frame timing
var _t0 := 0
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var f := FileAccess.open(args[0], FileAccess.READ)
	var job: Dictionary = JSON.parse_string(f.get_as_text())
	_jobs = job["jobs"]
	_out_dir = job["out"]
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_cam = Camera3D.new()
	_cam.far = 40000.0
	_cam.near = 0.05
	root.add_child(_cam)
	_cam.make_current()
	_player = _main.get_node("Player")
	# (the game starts at the hour of the computer's clock: the driver's pictures are taken
	# at midday unless a "tod" or a "clock" job says otherwise)
	_main.get_node("DayCycle").call_deferred("set_preset", 0, true)
	_player.set_process_unhandled_input(false)
	_player.set("_fly", true)
	_wait = int(job.get("warmup", 40))


func _process(dt: float) -> bool:
	if not _walk.is_empty():
		_walk_step(dt)
		return false
	if not _chase.is_empty():
		_chase_step()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= 0:
		_finish(_jobs[_i])
	_i += 1
	if _i >= _jobs.size():
		return true
	_begin(_jobs[_i])
	return false


func _ground(x: float, z: float) -> float:
	return float(_main.get_node("Landscape").call("ground", x, z))


func _begin(j: Dictionary) -> void:
	var kind: String = j.get("kind", "shot")
	_wait = int(j.get("frames", 6))
	if kind == "shot":
		var pos: Array = j["pos"]
		var cpos := Vector3(pos[0], pos[1], pos[2])
		if j.get("above", false):      # y is height above the ground
			cpos.y += _ground(cpos.x, cpos.z)
		_cam.global_position = cpos
		_cam.rotation = Vector3(deg_to_rad(j.get("pitch", 0.0)), deg_to_rad(j.get("yaw", 0.0)), 0.0)
		_cam.fov = j.get("fov", 72.0)
		if j.has("ortho"):
			_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			_cam.size = j["ortho"]
		else:
			_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.make_current()
		_player.set("_fly", true)
		_player.get_node("CollisionShape3D").set("disabled", true)
		var pp: Array = j.get("player", [cpos.x, cpos.y, cpos.z])
		_player.global_position = Vector3(pp[0], pp[1] - 1.65, pp[2])
		for path in j.get("hide", []):
			var n := _main.get_node_or_null(path)
			if n:
				n.set("visible", false)
		for path in j.get("show", []):
			var n := _main.get_node_or_null(path)
			if n:
				n.set("visible", true)
	elif kind == "look":
		# from the walker's eyes at whatever the expression "at" gives (a Node3D or a place):
		# what a player standing there sees of it
		var ex := Expression.new()
		var target: Variant = null
		if ex.parse(j["at"], ["main", "ls"]) == OK:
			target = ex.execute([_main, _main.get_node("Landscape")], self)
		var eye := _player.global_position + Vector3(0, 1.65, 0)
		if target is Node3D:
			target = (target as Node3D).global_position
		if target is Vector3:
			_cam.global_position = eye
			_cam.look_at(target, Vector3.UP)
			_cam.fov = j.get("fov", 72.0)
			_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			_cam.make_current()
			print("LOOK ", j["at"], ": %.1f m away" % eye.distance_to(target))
		else:
			print("LOOK: nothing for ", j["at"])
	elif kind == "tod":
		_main.get_node("DayCycle").call("set_preset", int(j["preset"]), true)
	elif kind == "clock":
		# the time of day by the clock, at the hour given: {"kind": "clock", "hour": 6.5}
		_main.get_node("DayCycle").set("clock_hour", float(j["hour"]))
		_main.get_node("DayCycle").call("set_clock", true)
	elif kind == "walk":
		_walk = j
		_wp = 1
		_walk_t = 0.0
		_still = 0.0
		_max_still = 0.0
		_jumps = 0
		_travel = 0.0
		_holdups = 0
		_avoid = 0.0
		_wp_holdups = 0
		_skipped = 0
		_reached = 0
		var a: Array = j["points"][0]
		_player.set("_fly", false)
		_player.get_node("CollisionShape3D").set("disabled", false)
		if not j.get("keep", false):       # ("keep": go on from where the player is, as it is moving)
			_player.velocity = Vector3.ZERO
			_player.global_position = Vector3(a[0], _ground(a[0], a[1]) + 0.3, a[1])
			_player.set("_safe_pos", _player.global_position)
		_last = _player.global_position
		(_player.get_node("Head/Camera3D") as Camera3D).make_current()
	elif kind == "chase":
		var ex := Expression.new()
		if ex.parse(j["node"], ["main", "ls"]) == OK:
			_chase_node = ex.execute([_main, _main.get_node("Landscape")], self) as Node3D
		if _chase_node == null:
			print("CHASE: no node for ", j["node"])
		else:
			_chase = j
			_chase_f = 0
			_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			_cam.fov = j.get("fov", 50.0)
			_cam.make_current()
	elif kind == "fps":
		_t0 = Time.get_ticks_usec()
		_frames = _wait
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	elif kind == "uncap":
		# (frame times below the 60 fps cap: to see what something costs)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0


func _chase_step() -> void:
	var o: Array = _chase.get("offset", [0, 6, 6])
	var off := Vector3(o[0], o[1], o[2])
	var t := _chase_node.global_transform
	var at := t.origin + ((t.basis.orthonormalized() * off) if _chase.get("local", false) else off)
	_cam.global_position = at
	_cam.look_at(t.origin, Vector3.UP if absf(off.x) + absf(off.z) > 0.05 else Vector3(0, 0, -1))
	var every := int(_chase.get("every", 15))
	if _chase_f > 0 and _chase_f % every == 0:
		var k := _chase_f / every - 1
		root.get_texture().get_image().save_png(_out_dir.path_join(str(_chase["out"]) % k))
		if k + 1 >= int(_chase.get("n", 8)):
			print("chased ", _chase["node"], ": ", k + 1, " pictures")
			_chase = {}
			_wait = 2
			return
	_chase_f += 1


func _walk_step(dt: float) -> void:
	var pts: Array = _walk["points"]
	var pos := _player.global_position
	var step := pos.distance_to(_last)
	if step > 2.5:
		_jumps += 1
	else:
		_travel += step
	if step < 0.3 * dt:
		_still += dt
		_max_still = maxf(_max_still, _still)
	else:
		_still = 0.0
	if _still > 0.45 and _avoid <= 0.0:
		_avoid = 1.1
		_avoid_sign = -_avoid_sign
		_holdups += 1
		_wp_holdups += 1
		if _wp_holdups >= int(_walk.get("skip_after", 99)) and _wp < pts.size() - 1:
			_wp += 1          # this waypoint cannot be reached (it lies in the rock): on to the next
			_wp_holdups = 0
			_skipped += 1
		if _walk.get("verbose", false):
			print("   held up at (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
	_avoid -= dt
	_last = pos
	_walk_t += dt
	var t: Array = pts[_wp]
	var d := Vector2(t[0] - pos.x, t[1] - pos.z)
	if d.length() < float(_walk.get("reach", 0.7)):
		_wp += 1
		_wp_holdups = 0
		_reached += 1
	var done := _wp >= pts.size()
	var timeout := _walk_t > float(_walk.get("timeout", 120.0)) or _still > 8.0 or _holdups > int(_walk.get("max_holdups", 40))
	if done or timeout:
		Input.action_release("move_forward")
		Input.action_release("sprint")
		print("WALK ", _walk.get("name", "?"), ": ", "arrived" if done else "STOPPED at waypoint %d/%d" % [_wp, pts.size() - 1],
			"  %.0f s, %.0f m, held up %d times, longest standstill %.1f s, resets %d, waypoints reached %d, given up %d, at (%.1f, %.1f, %.1f)" % [_walk_t, _travel, _holdups, _max_still, _jumps, _reached, _skipped, pos.x, pos.y, pos.z])
		if _walk.has("out"):
			root.get_texture().get_image().save_png(_out_dir.path_join(_walk["out"]))
		_walk = {}
		_cam.make_current()
		_wait = 2
		return
	t = pts[_wp]
	d = Vector2(t[0] - pos.x, t[1] - pos.z)
	_player.set("_yaw", atan2(-d.x, -d.y) + (_avoid_sign * 1.25 if _avoid > 0.0 else 0.0))
	if _walk.get("still", false):      # ("still": wait where the player is, with its physics running)
		Input.action_release("move_forward")
		_still = 0.0
		return
	Input.action_press("move_forward")
	if _walk.get("run", true):
		Input.action_press("sprint")


func _finish(j: Dictionary) -> void:
	var kind: String = j.get("kind", "shot")
	if kind == "shot" or kind == "look":
		var img := root.get_texture().get_image()
		img.save_png(_out_dir.path_join(j["out"]))
		print("saved ", j["out"])
	elif kind == "fps":
		var ms := float(Time.get_ticks_usec() - _t0) / 1000.0 / maxf(_frames, 1)
		# (the frame rate is capped by the display; the render times say what a frame really costs)
		var vp := root.get_viewport_rid()
		print("FPS ", j.get("name", "?"), ": %.2f ms/frame (%.0f fps); render cpu %.2f ms, gpu %.2f ms" % [ms, 1000.0 / ms,
			RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	elif kind == "hm":
		var tex := load("res://assets/textures/heightmap.exr") as Texture2D
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGF)
		var f := FileAccess.open(_out_dir.path_join(j["out"]), FileAccess.WRITE)
		f.store_buffer(img.get_data())
		print("hm ", img.get_width(), "x", img.get_height())
	elif kind == "check":
		_check()
	elif kind == "sea":
		_sea(j)
	elif kind == "tree":
		_dump(_main, 0, int(j.get("depth", 2)))
	elif kind == "expr":
		for e in j["exprs"]:
			var ex := Expression.new()
			if ex.parse(e, ["main", "ls"]) != OK:
				print(e, " => PARSE ERROR ", ex.get_error_text())
				continue
			var r: Variant = ex.execute([_main, _main.get_node("Landscape")], self)
			print(e, " => ", r)


## For `expr` jobs (an Expression cannot load a script): adds a test tool to the game, e.g.
## "add_tool('res://tools/coral_audit.gd', 'CoralAudit')", then "main.get_node('CoralAudit').report()".
func add_tool(path: String, name_: String) -> Node:
	var n := (load(path) as Script).new() as Node
	n.name = name_
	_main.add_child(n)
	return n


func _dump(n: Node, d: int, maxd: int) -> void:
	var extra := ""
	if n is Node3D:
		extra = " @ %s" % (n as Node3D).global_position
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		extra += " aabb %s" % (n as MeshInstance3D).get_aabb()
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", extra, " children=", n.get_child_count())
	if d < maxd:
		for c in n.get_children():
			_dump(c, d + 1, maxd)


func _stats(label: String, vals: Array) -> void:
	if vals.is_empty():
		print("CHECK ", label, ": none")
		return
	vals.sort()
	print("CHECK ", label, ": n=%d  min %.2f  median %.2f  max %.2f" % [vals.size(), vals[0], vals[vals.size() / 2], vals[vals.size() - 1]])


func _check() -> void:
	var ls := _main.get_node("Landscape")
	var g: Array = []
	for t in ls.get("tree_spots"):
		var o: Vector3 = (t["xf"] as Transform3D).origin
		g.append(_ground(o.x, o.z))
	_stats("ground under trees", g)
	g = []
	var d: Array = []
	for t in ls.get("tree_spots"):
		var o: Vector3 = (t["xf"] as Transform3D).origin
		d.append(o.y - _ground(o.x, o.z))
	_stats("tree base minus ground", d)
	g = []
	for t in ls.get("palm_trunks"):
		var o: Vector3 = (t["pts"] as PackedVector3Array)[0]
		g.append(o.y - _ground(o.x, o.z))
	_stats("palm trunk base minus ground", g)
	g = []
	for t in ls.get("palm_trunks"):
		var o: Vector3 = (t["pts"] as PackedVector3Array)[0]
		g.append(_ground(o.x, o.z))
	_stats("ground under palms", g)
	g = []
	for t in ls.get("mangrove_spots"):
		var o: Vector3 = t if t is Vector3 else (t[0] if t is Array else Vector3.ZERO)
		g.append(_ground(o.x, o.z))
	_stats("ground under mangroves", g)
	g = []
	for t in ls.get("boulder_spots"):
		var o: Vector3 = t[0]
		g.append(_ground(o.x, o.z))
	_stats("ground under boulders", g)
	g = []
	for t in ls.get("vacoa_spots"):
		var o: Vector3 = t if t is Vector3 else (t[0] if t is Array else Vector3.ZERO)
		g.append(_ground(o.x, o.z))
	_stats("ground under screwpines", g)
	var il := _main.get_node("IslandLife")
	for t in il.get("_torts"):
		var n: Node3D = t["node"] if t.has("node") else null
		if n:
			var p := n.global_position
			print("CHECK tortoise at ", p, " ground ", _ground(p.x, p.z), " grass ", (ls.call("cover", p.x, p.z) as Color).b)
		else:
			print("CHECK tortoise keys ", t.keys())
	var col := _main.get_node("Colony")
	print("CHECK colony center ", col.get("_center"), " children ", col.get_child_count())


func _sea(j: Dictionary) -> void:
	var sl := _main.get_node("SeaLife")
	for p in j["from"]:
		_player.global_position = Vector3(p[0], _ground(p[0], p[1]) + 0.1, p[1])
		var ok_n := 0
		var worst := 99.0
		var shortest := 1e9
		var tightest := 0.0
		for k in int(j.get("tries", 10)):
			if sl.call("summon_shark"):
				ok_n += 1
				var d: Dictionary = sl.get("_shark_d")
				var route: PackedVector3Array = d["route"]
				for q in route:
					worst = minf(worst, -_ground(q.x, q.z))
				shortest = minf(shortest, float(d["length"]))
				# the tightest turn on the route: the angle between points 3 m apart
				var cum: PackedFloat32Array = d["cum"]
				var at := 3.0
				while at < float(d["length"]) - 3.0:
					var a: Vector3 = sl.call("_route_dir", route, cum, at - 1.5)
					var b: Vector3 = sl.call("_route_dir", route, cum, at + 1.5)
					tightest = maxf(tightest, a.angle_to(b) / 3.0)
					at += 1.0
		var rays_ok: bool = sl.call("summon_rays")
		var ray_min := 99.0
		for r in sl.get("_rays"):
			var rp: Vector3 = r["pos"] if r.has("pos") else Vector3.ZERO
			ray_min = minf(ray_min, -_ground(rp.x, rp.z))
		print("SEA from (%.0f, %.0f): shark routes %d/%d, shallowest water on a route %.1f m, shortest %.0f m, tightest turn radius %.0f m; rays %s, shallowest %.1f m" % [
			p[0], p[1], ok_n, int(j.get("tries", 10)), worst, shortest, 1.0 / maxf(tightest, 0.0001), str(rays_ok), ray_min])
