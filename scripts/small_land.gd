extends Node3D
## Small things on land (item 7 of the work list; the node is created by island_life.gd):
##  * land hermit crabs on the beaches: a few abroad by day at the top of the beach, many from
##    the golden hour through the night and whenever the ground is wet with rain. They walk
##    forward, dragging their shells, stop, pick at the sand; when someone comes within a
##    step they snap back into the shell and wait until the coast is clear,
##  * giant millipedes (Sechelleptus seychellarum) and, rarely, the Seychelles snail
##    (Stylodonta unidentata) on the forest floor: out at dusk, at night and after rain,
##  * on the granite slabs beside the summit: mats of the pitcher plant Nepenthes pervillei,
##    tropicbird orchids, and the leafless ropes of the wild vanilla.
## The animals are put near the walker, mostly ahead (small things are not found otherwise).
## For the tests: `force` (1: everybody out whatever the hour, -1: nobody), report(),
## soak(seconds), nearest(kind).

const LM := preload("res://scripts/land_models.gd")

const HERMITS := 14
const HERMITS_BY_DAY := 3
const MILLIPEDES := 7
const RINGS := 38
const SNAILS := 2
const M_STOUT := 1.28

var force := 0
var hermits: Array = []
var millipedes: Array = []
var snails: Array = []
var pitcher_spots: Array = []
var orchid_spots: Array = []
var vanilla_spots: Array = []
var turtle_gap := 1e6      # the nearest a hermit crab has been to the nesting turtle (for the tests)
var turtle_test: Variant = null    # (for the tests) a place where the turtle is taken to be

var _ls: Node
var _player: Node3D
var _daycycle: Node
var _weather: Node
var _rng := RandomNumberGenerator.new()
var _frame := 0
var _planted := false
var _last_pp := Vector3.ZERO
var _still := 0.0          # how long the walker has been standing still (s)
var _birds: Node


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_daycycle = get_node_or_null("../../DayCycle")
	_rng.seed = 20261112
	_make_hermits()
	_make_millipedes()
	_make_snails()


# ------------------------------------------------------------------ what everybody asks
func _ray(from: Vector3, to: Vector3, mask := 1) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _ground(x: float, z: float) -> float:
	return float(_ls.ground(x, z))


func _normal(x: float, z: float) -> Vector3:
	var e := 0.3
	return Vector3(_ground(x - e, z) - _ground(x + e, z), 2.0 * e, _ground(x, z - e) - _ground(x, z + e)).normalized()


## Does something solid stand here: a boulder, a trunk, driftwood? (as in shorebirds.gd)
func _solid(x: float, z: float) -> bool:
	var g := _ground(x, z)
	var hit := _ray(Vector3(x, g + 2.5, z), Vector3(x, g - 0.5, z))
	return not hit.is_empty() and (hit["position"] as Vector3).y > g + 0.05


## How much the small animals are abroad: 0 by day .. 1 from the golden hour on and through
## the night, and while the ground is wet with rain.
func activity() -> float:
	if force != 0:
		return 1.0 if force > 0 else 0.0
	var dusk := 0.0
	if _daycycle:
		dusk = 1.0 - smoothstep(9.0, 20.0, float(_daycycle.sun_elev))
	if _weather == null:
		_weather = get_node_or_null("../Weather")
	var damp := 0.0
	if _weather:
		damp = smoothstep(0.2, 0.55, float(_weather.wet))
	return maxf(dusk, damp)


func _look_dir() -> Vector3:
	var yaw: Variant = _player.get("_yaw") if _player else null
	var a := float(yaw) if yaw != null else 0.0
	return Vector3(-sin(a), 0, -cos(a))


## A place around the walker: mostly ahead of them (within `spread` of the way they look).
func _near(pp: Vector3, rmin: float, rmax: float, spread := 1.0) -> Vector3:
	var look := _look_dir()
	var a := _rng.randf() * TAU
	if _rng.randf() < 0.75:
		a = atan2(look.z, look.x) + _rng.randf_range(-spread, spread)
	var r := _rng.randf_range(rmin, rmax)
	return Vector3(pp.x + cos(a) * r, 0.0, pp.z + sin(a) * r)


func _in_view(pp: Vector3, p: Vector3) -> bool:
	var to := Vector3(p.x - pp.x, 0, p.z - pp.z)
	return to.length() < 0.5 or to.normalized().dot(_look_dir()) > 0.3


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame == 30 and not _planted:
		_planted = true
		_plant_granite()
	if _frame > 30 and _player:
		_step(delta, _player.global_position)
		_update_coconuts(delta, _player.global_position)


## `pp`: where the walker is. Somebody who stands still is no threat: after a while the
## animals carry on at their feet.
func _step(delta: float, pp: Vector3) -> void:
	_still = 0.0 if pp.distance_to(_last_pp) > 0.25 * delta else _still + delta
	_last_pp = pp
	var act := activity()
	_update_hermits(delta, pp, act)
	_update_millipedes(delta, pp, act)
	_update_snails(delta, pp, act)


# ================================================================== hermit crabs
## Land hermit crabs (Coenobita rugosus, the common one of these beaches: sandy, brown or
## gray; and here and there the red strawberry hermit crab, C. perlatus). Each carries a
## snail shell from the beach: turban, nerite, top shell or cerith.
var _hermit_mat: ShaderMaterial

func _make_hermits() -> void:
	var body: ArrayMesh = LM.hermit()
	_hermit_mat = ShaderMaterial.new()
	_hermit_mat.shader = load("res://shaders/hermit.gdshader")
	var smat := LM.shell_material()
	var shells: Array = []
	for k in 4:
		shells.append(LM.shell(k, LM.shell_size_for(k, 0.0155)))
	var tints := [Color(0.62, 0.5, 0.36), Color(0.45, 0.33, 0.22), Color(0.44, 0.38, 0.42), Color(0.7, 0.62, 0.5), Color(0.52, 0.4, 0.3)]
	for i in HERMITS:
		var kind: int = [0, 1, 0, 2, 0, 3, 1, 2][i % 8]
		var h: Dictionary = LM.hermit_node(body, _hermit_mat, shells[kind], smat)
		var root: Node3D = h["root"]
		root.name = "Hermit%d" % i
		add_child(root)
		root.visible = false
		root.position = Vector3(0, -50, 0)
		var bmi: MeshInstance3D = h["body"]
		bmi.layers = 2            # decals (footprints, burrows) do not stain it
		(h["shell"] as MeshInstance3D).layers = 2
		# (a cerith is a long shell for its mouth: small crabs live in them)
		# (shown as the biggest of their kind are, and a little over: a shell of 5 to 8 cm.
		# Smaller ones are not seen from walking height)
		var sc := _rng.randf_range(0.95, 1.45) if kind != 3 else _rng.randf_range(0.7, 0.9)
		var red := i % 6 == 4
		bmi.set_instance_shader_parameter("tint", Color(0.72, 0.15, 0.07) if red else tints[_rng.randi() % tints.size()])
		bmi.set_instance_shader_parameter("speckle", 1.0 if red else 0.0)
		hermits.append({"node": root, "body": bmi, "sc": sc, "state": "hidden", "timer": _rng.randf_range(0.5, 6.0),
			"pos": Vector3.ZERO, "yaw": 0.0, "want": 0.0, "look": 0.0, "side": 1.0 if _rng.randf() < 0.5 else -1.0,
			"pace": _rng.randf_range(0.035, 0.065), "speed": 0.0, "gait": _rng.randf() * TAU, "stride": 0.0, "tuck": 0.0, "feed": 0.0,
			"shy": _rng.randf_range(0.9, 1.4), "wait": 5.0, "retire": false, "stuck": 0.0})


## Can a hermit crab be at p: loose sand of a beach, above the reach of the swash, nothing
## solid there. One the water has caught may go wherever the ground is higher.
func _hermit_ok(p: Vector3, from_h := -99.0, retire := false) -> bool:
	var g := _ground(p.x, p.z)
	var sea: float = _ls.sea
	if g - sea < 0.22 and g < from_h + 0.0004:
		return false
	if g > 2.6 and not retire:
		return false
	if not _ls.sandy(Vector2(p.x, p.z)) or float(_ls.cave_dist(Vector2(p.x, p.z))) < 12.0:
		return false
	# (not among the sooty terns on their eggs)
	if _birds == null:
		_birds = get_node_or_null("../ShoreBirds")
	if _birds and _birds.in_sooty_patch(p):
		return false
	return not _solid(p.x, p.z)


func _place_hermit(d: Dictionary, pp: Vector3, by_day: bool) -> bool:
	for k in 5:
		var p := _near(pp, 3.5, 12.0)
		var g := _ground(p.x, p.z)
		# by day at the top of the beach, near the bushes; at dusk anywhere down to the wet sand
		if by_day and g < 0.85:
			continue
		if g - float(_ls.sea) < 0.3 or not _hermit_ok(p):
			continue
		if _normal(p.x, p.z).y < 0.9:
			continue
		var crowded := false
		for o: Dictionary in hermits:
			if not is_same(o, d) and o["state"] != "hidden" and (o["pos"] as Vector3).distance_to(Vector3(p.x, g, p.z)) < 0.6:
				crowded = true
		if crowded:
			continue
		d["pos"] = Vector3(p.x, g, p.z)
		d["yaw"] = _rng.randf() * TAU
		d["want"] = d["yaw"]
		d["state"] = "walk" if _rng.randf() < 0.6 else "pause"
		d["timer"] = _rng.randf_range(2.0, 8.0)
		d["tuck"] = 0.0
		d["speed"] = 0.0
		d["retire"] = false
		d["stuck"] = 0.0
		_pose_hermit(d)
		(d["node"] as Node3D).visible = true
		return true
	return false


func _pose_hermit(d: Dictionary) -> void:
	var n: Node3D = d["node"]
	var pos: Vector3 = d["pos"]
	var sc: float = d["sc"]
	var tuck: float = d["tuck"]
	var up := _normal(pos.x, pos.z)
	var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, float(d["yaw"]))
	# walking, the body is held up and the shell just clears the sand; drawn in, the shell
	# lies on it
	var lift := 0.003 * (1.0 - tuck)
	n.global_transform = Transform3D(b.scaled(Vector3.ONE * sc), pos + up * ((lift - 0.0022 * tuck) * sc))
	var bmi: MeshInstance3D = d["body"]
	bmi.set_instance_shader_parameter("gait", d["gait"])
	bmi.set_instance_shader_parameter("stride", d["stride"])
	bmi.set_instance_shader_parameter("lift", lift)
	bmi.set_instance_shader_parameter("tuck", tuck)
	bmi.set_instance_shader_parameter("feed", d["feed"])


func _hide_hermit(d: Dictionary) -> void:
	d["state"] = "hidden"
	d["timer"] = _rng.randf_range(2.0, 7.0)
	(d["node"] as Node3D).visible = false


## Where the nesting hawksbill is while she is on the beach (far away if she is not): the
## hermit crabs make way for her.
func _turtle_at() -> Vector3:
	if turtle_test is Vector3:
		return turtle_test
	var nest := get_node_or_null("../Nesting")
	if nest and str(nest.state) != "away" and nest.turtle and (nest.turtle as Node3D).visible:
		return (nest.turtle as Node3D).global_position
	return Vector3(1e6, 0, 0)


func _update_hermits(delta: float, pp: Vector3, act: float) -> void:
	var want_n := HERMITS_BY_DAY + int(round((HERMITS - HERMITS_BY_DAY) * act))
	var turtle := _turtle_at()
	for i in hermits.size():
		var d: Dictionary = hermits[i]
		var allowed := i < want_n
		d["timer"] -= delta
		if d["state"] == "hidden":
			if allowed and d["timer"] <= 0.0:
				d["timer"] = _rng.randf_range(1.0, 3.0)
				if _place_hermit(d, pp, act < 0.5) and Vector2((d["pos"] as Vector3).x - turtle.x, (d["pos"] as Vector3).z - turtle.z).length() < 4.0:
					_hide_hermit(d)
			continue
		var pos: Vector3 = d["pos"]
		var from_turtle := Vector3(pos.x - turtle.x, 0, pos.z - turtle.z)
		var crowded := from_turtle.length() < 2.6
		turtle_gap = minf(turtle_gap, from_turtle.length())
		var dist := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if dist > 36.0 or (not allowed and (dist > 20.0 or not _in_view(pp, pos))):
			_hide_hermit(d)
			continue
		if not allowed and not d["retire"] and d["state"] == "walk":
			# the day has come back: up the beach and under the bushes
			d["retire"] = true
			d["timer"] = 90.0
		var near: bool = dist < float(d["shy"]) and absf(pp.y - pos.y) < 2.5 and _still < 1.0
		var sc: float = d["sc"]
		var want_stride := 0.0
		var feed := 0.0
		match d["state"]:
			"walk":
				var yaw: float = d["yaw"]
				var g := _ground(pos.x, pos.z)
				var caught := g - float(_ls.sea) < 0.22
				d["look"] -= delta
				if d["look"] <= 0.0:
					d["look"] = 0.2
					var uphill := -Vector3(_ground(pos.x + 0.5, pos.z) - _ground(pos.x - 0.5, pos.z), 0, _ground(pos.x, pos.z + 0.5) - _ground(pos.x, pos.z - 0.5))
					if (caught or d["retire"]) and uphill.length() > 0.001:
						# the water has reached it (or the day): up the beach
						d["want"] = atan2(uphill.x, uphill.z) + PI + _rng.randf_range(-0.3, 0.3)
					elif crowded:
						# the turtle is coming: out of her way
						d["want"] = atan2(-from_turtle.x, -from_turtle.z) + _rng.randf_range(-0.3, 0.3)
					var reach := 0.13 * sc
					var free := false
					for a: float in [0.0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0, PI]:
						var w: float = float(d["want"]) + a * float(d["side"])
						var q := pos + Vector3(-sin(w), 0, -cos(w)) * reach
						if _hermit_ok(q, g, d["retire"]) and _hermit_ok(pos.lerp(q, 0.5), g, d["retire"]) and _clear_of_others(d, q):
							d["want"] = w
							free = true
							break
						if d["retire"] and not _ls.sandy(Vector2(q.x, q.z)) and a == 0.0:
							_hide_hermit(d)       # it has reached the edge of the bushes
							break
					if d["state"] == "hidden":
						continue
					d["stuck"] = 0.0 if free else float(d["stuck"]) + 0.2
					if not free:
						d["want"] = _rng.randf() * TAU
					elif _rng.randf() < 0.12:
						d["want"] = float(d["want"]) + _rng.randf_range(-0.6, 0.6)
				var diff := angle_difference(yaw, float(d["want"]))
				yaw += clampf(diff, -1.7 * delta, 1.7 * delta)
				d["yaw"] = yaw
				var pace: float = float(d["pace"]) * sc * (1.5 if caught or crowded else 1.0)
				var v := pace * (1.0 - clampf(absf(diff) / 0.9, 0.0, 0.85)) if float(d["stuck"]) < 0.1 else 0.0
				d["speed"] = move_toward(float(d["speed"]), v, delta * 0.2)
				var np := pos + Vector3(-sin(yaw), 0, -cos(yaw)) * (float(d["speed"]) * delta)
				np.y = _ground(np.x, np.z)
				pos = np
				d["pos"] = pos
				d["gait"] = fmod(float(d["gait"]) + float(d["speed"]) * delta / (0.044 * sc) * TAU, TAU * 64.0)
				want_stride = clampf(float(d["speed"]) / (0.03 * sc), 0.0, 1.0)
				if d["retire"] and d["timer"] <= 0.0:
					_hide_hermit(d)
					continue
				if d["timer"] <= 0.0 and not caught and not crowded and not d["retire"]:
					d["state"] = "pause" if _rng.randf() < 0.5 else "feed"
					d["timer"] = _rng.randf_range(1.5, 6.0) if d["state"] == "pause" else _rng.randf_range(4.0, 10.0)
				if near:
					d["state"] = "in"
					d["wait"] = _rng.randf_range(4.0, 9.0)
					d["timer"] = d["wait"]
			"pause", "feed":
				d["speed"] = 0.0
				feed = 1.0 if d["state"] == "feed" else 0.0
				if d["timer"] <= 0.0 or crowded or _ground(pos.x, pos.z) - float(_ls.sea) < 0.2:
					d["state"] = "walk"
					d["want"] = float(d["yaw"]) + _rng.randf_range(-1.3, 1.3)
					d["timer"] = _rng.randf_range(3.0, 11.0)
				if near:
					d["state"] = "in"
					d["wait"] = _rng.randf_range(4.0, 9.0)
					d["timer"] = d["wait"]
			"in":
				# in the shell, the big claw across the door, until whoever it was has gone
				d["speed"] = 0.0
				d["tuck"] = move_toward(float(d["tuck"]), 1.0, delta * 6.0)
				if dist < float(d["shy"]) + 0.8 and _still < 1.5:
					d["timer"] = d["wait"]
				elif d["timer"] <= 0.0:
					d["state"] = "peek"
					d["timer"] = _rng.randf_range(1.5, 3.5)
			"peek":
				# half out: eyes and feelers first
				d["tuck"] = move_toward(float(d["tuck"]), 0.5, delta * 0.7)
				if dist < float(d["shy"]) + 0.3 and _still < 1.0:
					d["state"] = "in"
					d["timer"] = d["wait"]
				elif d["timer"] <= 0.0:
					d["state"] = "out"
			"out":
				d["tuck"] = move_toward(float(d["tuck"]), 0.0, delta * 1.1)
				if near:
					d["state"] = "in"
					d["timer"] = d["wait"]
				elif float(d["tuck"]) < 0.02:
					d["state"] = "pause"
					d["timer"] = _rng.randf_range(1.0, 3.0)
		d["stride"] = move_toward(float(d["stride"]), want_stride, delta * 4.0)
		d["feed"] = move_toward(float(d["feed"]), feed, delta * 2.0)
		_pose_hermit(d)


func _clear_of_others(d: Dictionary, q: Vector3) -> bool:
	for o: Dictionary in hermits:
		if not is_same(o, d) and o["state"] != "hidden" and Vector2((o["pos"] as Vector3).x - q.x, (o["pos"] as Vector3).z - q.z).length() < 0.1:
			return false
	return true


# ================================================================== the forest floor
## Firm ground of the forest floor at p, found with a ray: {} if there is none (a trunk, the
## side of a boulder, too steep).
func _floor(p: Vector3) -> Dictionary:
	var hit := _ray(Vector3(p.x, p.y + 0.3, p.z), Vector3(p.x, p.y - 0.4, p.z))
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.55:
		return {}
	return hit


## May a millipede or a snail be at p: forest floor, not the fresh water or its banks, not
## the grotto; `open`: also clear of the ferns' fronds and of the bushes (to be seen).
func _floor_ok(p: Vector3, open: bool) -> bool:
	var v := Vector2(p.x, p.z)
	if _ground(p.x, p.z) < 1.0 or (_ls.cover(p.x, p.z) as Color).r < 0.35:
		return false
	if float(_ls.stream_dist(v)) < 2.5 or float(_ls.cave_dist(v)) < 11.0 or float(_ls.cave_way(v)) < 3.0:
		return false
	if _ls.ferny(v, 0.12 if open else 0.0, 0.8 if open else 0.55):
		return false
	if open:
		# (the bushes' volumes are on layer 2)
		var g := _ground(p.x, p.z)
		for o: Vector2 in [Vector2.ZERO, Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)]:
			if not _ray(Vector3(p.x + o.x, g + 14.0, p.z + o.y), Vector3(p.x + o.x, g - 0.2, p.z + o.y), 2).is_empty():
				return false
	return true


## A place on the open forest floor near the walker, with its ground: {} if none was found.
func _floor_spot(pp: Vector3, rmin: float, rmax: float) -> Dictionary:
	for k in 4:
		var p := _near(pp, rmin, rmax, 0.75)
		p.y = _ground(p.x, p.z)
		if not _floor_ok(p, true):
			continue
		var hit := _floor(p)
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.8 or absf((hit["position"] as Vector3).y - p.y) > 0.06:
			continue
		return hit
	return {}


# ------------------------------------------------------------------ giant millipedes
## The Seychelles giant millipede: glossy black-brown with red-brown legs, as long as a hand
## (shown a little longer). It walks the forest floor at an even, unhurried pace, its legs
## moving in waves that run up the body, the feelers tapping ahead; it goes around what
## stands in its way, and stops for a while when somebody stands over it. The body is a
## chain of rings laid along the way the head has gone: every ring follows the head exactly.
func _make_millipedes() -> void:
	var mesh: ArrayMesh = LM.millipede()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/millipede.gdshader")
	for i in MILLIPEDES:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = RINGS
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Millipede%d" % i
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.layers = 2
		mmi.visible = false
		add_child(mmi)
		# (a marker at the head, for the tests' camera)
		var head := Node3D.new()
		head.name = "Head"
		mmi.add_child(head)
		head.position = Vector3(0, -50, 0)
		millipedes.append({"node": mmi, "mm": mm, "head": head, "sc": _rng.randf_range(0.9, 1.25), "state": "hidden", "timer": _rng.randf_range(1.0, 10.0),
			"pos": Vector3.ZERO, "up": Vector3.UP, "yaw": 0.0, "want": 0.0, "look": 0.0, "side": 1.0 if _rng.randf() < 0.5 else -1.0,
			"pace": _rng.randf_range(0.016, 0.027), "speed": 0.0, "dist": 0.0, "moving": 0.0, "pts": [], "nrm": [], "stuck": 0.0, "turn_t": 3.0, "halt": 0.0})


## One step of `len` from pos along yaw: where the ground is there, or {} if the way is shut.
func _milli_step(pos: Vector3, yaw: float, len: float) -> Dictionary:
	var q := pos + Vector3(-sin(yaw), 0, -cos(yaw)) * len
	var hit := _floor(q)
	if hit.is_empty() or absf((hit["position"] as Vector3).y - pos.y) > 0.012 + len * 1.1:
		return {}
	return hit


func _place_millipede(d: Dictionary, pp: Vector3) -> bool:
	var spot := _floor_spot(pp, 2.5, 8.5)
	if spot.is_empty():
		return false
	for o: Dictionary in millipedes:
		if not is_same(o, d) and o["state"] != "hidden" and (o["pos"] as Vector3).distance_to(spot["position"]) < 1.5:
			return false
	# walk the body's length unseen, so that every ring has ground it came over
	var yaw := _rng.randf() * TAU
	var pos: Vector3 = spot["position"]
	var pts: Array = [pos]
	var nrm: Array = [spot["normal"]]
	var need := int(RINGS * LM.M_PITCH * float(d["sc"]) / 0.004) + 12
	for i in need:
		var hit := _milli_step(pos, yaw, 0.004)
		if hit.is_empty():
			return false
		pos = hit["position"]
		pts.push_front(pos)
		nrm.push_front(hit["normal"])
		yaw += 0.006 * float(d["side"])
	if not _floor_ok(pos, true):
		return false
	d["pts"] = pts
	d["nrm"] = nrm
	d["pos"] = pos
	d["up"] = nrm[0]
	d["yaw"] = yaw
	d["want"] = yaw
	d["state"] = "walk"
	d["timer"] = _rng.randf_range(20.0, 60.0)
	d["stuck"] = 0.0
	d["halt"] = 0.0
	_lay_millipede(d)
	(d["node"] as Node3D).visible = true
	return true


## Lays the rings along the way the head has gone.
func _lay_millipede(d: Dictionary) -> void:
	var mm: MultiMesh = d["mm"]
	var pts: Array = d["pts"]
	var nrm: Array = d["nrm"]
	var sc: float = d["sc"]
	var pitch := LM.M_PITCH * sc
	var head: Vector3 = d["pos"]
	# the line: the head's place now, then where it has been (newest first)
	var k := 0                      # the stretch pts[k-1] (or the head) -> pts[k]
	var a := head
	var b: Vector3 = pts[0]
	var seg := a.distance_to(b)
	var done := 0.0                 # the line's length up to a
	var prev := head
	var step: float = TAU * float(d["dist"]) / (0.0154 * sc)
	for i in RINGS:
		var s := (i + 0.5) * pitch
		while s > done + seg and k < pts.size() - 1:
			done += seg
			k += 1
			a = b
			b = pts[k]
			seg = a.distance_to(b)
		var f := clampf((s - done) / maxf(seg, 0.00001), 0.0, 1.0) if k < pts.size() - 1 or s <= done + seg else (s - done) / maxf(seg, 0.00001)
		var p := a.lerp(b, f)
		var up: Vector3 = nrm[mini(k, nrm.size() - 1)]
		var fwd := (prev - p)
		prev = p
		if fwd.length() < 0.00001:
			fwd = Vector3(-sin(float(d["yaw"])), 0, -cos(float(d["yaw"])))
		var z := -fwd.normalized()
		var x := up.cross(z).normalized()
		var y := z.cross(x)
		var kind := 0.0
		var taper := 1.0
		if i == 0:
			kind = 1.0
			taper = 0.92
		elif i == 1:
			kind = 3.0
			taper = 0.98
		elif i == RINGS - 1:
			kind = 2.0
			taper = 0.78
		elif i == RINGS - 2:
			kind = 3.0
			taper = 0.9
		# (the rings are a quarter wider than they are built: a stout animal)
		mm.set_instance_transform(i, Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3(M_STOUT * taper, M_STOUT * taper, 1.0) * sc), p))
		mm.set_instance_custom_data(i, Color(fmod(step + i * 1.15, TAU), d["moving"], kind, 0.0))
	(d["head"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, float(d["yaw"])), head)


func _hide_millipede(d: Dictionary) -> void:
	d["state"] = "hidden"
	d["timer"] = _rng.randf_range(4.0, 14.0)
	(d["node"] as Node3D).visible = false


func _update_millipedes(delta: float, pp: Vector3, act: float) -> void:
	var want_n := int(round(MILLIPEDES * act))
	for i in millipedes.size():
		var d: Dictionary = millipedes[i]
		var allowed := i < want_n
		d["timer"] -= delta
		if d["state"] == "hidden":
			if allowed and d["timer"] <= 0.0:
				d["timer"] = _rng.randf_range(1.5, 4.0)
				# (every third one climbs: on a trunk at eye height it is found)
				d["trunk"] = i % 3 == 0 and _place_on_trunk(d, pp)
				if not d["trunk"]:
					_place_millipede(d, pp)
			continue
		if d.get("trunk", false):
			var tp: Vector3 = d["pos"]
			var td := Vector2(pp.x - tp.x, pp.z - tp.z).length()
			# (one that can get no further rests where it is, and is taken away unseen)
			if td > 30.0 or (not allowed and (td > 14.0 or not _in_view(pp, tp))) or (float(d["stuck"]) > 25.0 and not _in_view(pp, tp)):
				_hide_millipede(d)
			else:
				_update_trunk_millipede(d, delta)
			continue
		var pos: Vector3 = d["pos"]
		var dist := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if dist > 30.0 or (not allowed and (dist > 14.0 or not _in_view(pp, pos))) or float(d["stuck"]) > 25.0:
			_hide_millipede(d)
			continue
		# somebody standing over it: it stops, and goes on a while after they have stepped back
		if dist < 0.7 and absf(pp.y - pos.y) < 2.5 and _still < 0.5:
			d["halt"] = _rng.randf_range(2.0, 5.0)
		else:
			d["halt"] = maxf(float(d["halt"]) - delta, 0.0)
		var yaw: float = d["yaw"]
		d["look"] -= delta
		d["turn_t"] -= delta
		if d["turn_t"] <= 0.0:
			d["turn_t"] = _rng.randf_range(4.0, 9.0)
			d["want"] = float(d["want"]) + _rng.randf_range(-0.7, 0.7)
		if d["look"] <= 0.0:
			d["look"] = 0.25
			# the way ahead: a body's width on, and a finger's length on
			var free := false
			for a: float in [0.0, 0.7, -0.7, 1.4, -1.4, 2.2, -2.2, PI]:
				var w: float = float(d["want"]) + a * float(d["side"])
				var h1 := _milli_step(pos, w, 0.03)
				if h1.is_empty() or not _floor_ok(h1["position"], false):
					continue
				var h2 := _milli_step(h1["position"], w, 0.05)
				if h2.is_empty() or not _floor_ok(h2["position"], false):
					continue
				# (around the walker's feet, not through them)
				if Vector2((h2["position"] as Vector3).x - pp.x, (h2["position"] as Vector3).z - pp.z).length() < 0.3 and dist >= 0.3:
					continue
				d["want"] = w
				free = true
				break
			d["stuck"] = 0.0 if free else float(d["stuck"]) + 0.25
			if not free:
				d["want"] = _rng.randf() * TAU
		var diff := angle_difference(yaw, float(d["want"]))
		yaw += clampf(diff, -0.55 * delta, 0.55 * delta)
		d["yaw"] = yaw
		var v := float(d["pace"]) * float(d["sc"]) * (1.0 - clampf(absf(diff) / 1.6, 0.0, 0.6))
		if float(d["halt"]) > 0.0 or float(d["stuck"]) > 0.2:
			v = 0.0
		d["speed"] = move_toward(float(d["speed"]), v, delta * 0.03)
		d["moving"] = clampf(float(d["speed"]) / (0.012 * float(d["sc"])), 0.0, 1.0)
		var move: float = float(d["speed"]) * delta
		if move > 0.0:
			var hit := _milli_step(pos, yaw, move)
			if hit.is_empty():
				d["speed"] = 0.0
				d["look"] = 0.0
			else:
				pos = hit["position"]
				d["pos"] = pos
				d["dist"] = fmod(float(d["dist"]) + move, 1000.0)
				var pts: Array = d["pts"]
				if pos.distance_to(pts[0]) >= 0.003:
					pts.push_front(pos)
					(d["nrm"] as Array).push_front(((d["nrm"] as Array)[0] as Vector3).lerp(hit["normal"], 0.35).normalized())
					var keep := int(RINGS * LM.M_PITCH * float(d["sc"]) / 0.003) + 16
					if pts.size() > keep:
						pts.resize(keep)
						(d["nrm"] as Array).resize(keep)
		_lay_millipede(d)


# ------------------------------------------------------------------ ... on a trunk
## At dusk the giant millipedes climb: every third one is put on the trunk of a palm or a
## tree a few steps from the walker, on the side that faces them, between knee and head
## height. It walks on the bark as on the ground, found with rays (a walker on any
## surface: each step is taken along the bark, and a ray across the step finds the bark
## again): up in a slow spiral, round at about 2.6 m, down again, round at half a meter.
var _trunks: Array = []       # where trunks stand: Vector3 (a palm's foot or a tree's)


func _trunk_step(pos: Vector3, nrm: Vector3, dir: Vector3, step: float) -> Dictionary:
	var guess := pos + dir * step
	var hit := _ray(guess + nrm * 0.1, guess - nrm * 0.2)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(nrm) < 0.6 or absf((hit["normal"] as Vector3).y) > 0.8:
		return {}       # (an edge, a root, a branch, the ground: not that way)
	return hit


func _trunk_dir(nrm: Vector3, phi: float) -> Vector3:
	var up := Vector3.UP - nrm * nrm.y
	return up.normalized().rotated(nrm, phi) if up.length() > 0.05 else Vector3.UP


func _place_on_trunk(d: Dictionary, pp: Vector3) -> bool:
	if _trunks.is_empty():
		for t: Dictionary in _ls.palm_trunks:
			_trunks.append((t["pts"] as PackedVector3Array)[0])
		for t: Dictionary in _ls.tree_spots:
			_trunks.append((t["xf"] as Transform3D).origin)
	var near: Array = []
	for b: Vector3 in _trunks:
		var dd := Vector2(b.x - pp.x, b.z - pp.z).length()
		if dd > 2.5 and dd < 9.0 and _in_view(pp, b) and float(_ls.cave_dist(Vector2(b.x, b.z))) > 10.0:
			near.append(b)
	for k in mini(near.size(), 4):
		var b: Vector3 = near[_rng.randi() % near.size()]
		var taken := false
		for o: Dictionary in millipedes:
			if not is_same(o, d) and o["state"] != "hidden" and (o["pos"] as Vector3).distance_to(b) < 3.5:
				taken = true
		# (nor on a palm with a gecko out on it, or with the termites' runways on its bark:
		# island_life.gd)
		var il := get_parent()
		if il and il.has_method("gecko_at") and (il.gecko_at(b) or il.termite_palm_at(b)):
			taken = true
		if taken:
			continue
		var to_p := Vector3(pp.x - b.x, 0, pp.z - b.z).normalized().rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8))
		var y := _ground(b.x, b.z) + _rng.randf_range(0.55, 1.0)
		var axis := Vector3(b.x, y, b.z)
		var hit := _ray(axis + to_p * 1.8, axis - to_p * 0.3)
		if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.5 or Vector2((hit["position"] as Vector3).x - b.x, (hit["position"] as Vector3).z - b.z).length() > 1.3:
			continue
		# (only where the walker can see it: nothing solid and no shrub between their eyes
		# and the place on the bark)
		if not _ray(pp + Vector3(0, 1.6, 0), (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.05, 3).is_empty():
			continue
		# up the bark for its own length, unseen, so that every ring has bark it came over
		var pos: Vector3 = hit["position"]
		var nrm: Vector3 = hit["normal"]
		var phi := _rng.randf_range(-0.3, 0.3)
		var pts: Array = [pos]
		var nrms: Array = [nrm]
		var ok := true
		for i in int(RINGS * LM.M_PITCH * float(d["sc"]) / 0.003) + 14:
			var h := _trunk_step(pos, nrm, _trunk_dir(nrm, phi), 0.003)
			if h.is_empty():
				ok = false
				break
			pos = h["position"]
			nrm = nrm.lerp(h["normal"], 0.4).normalized()
			pts.push_front(pos)
			nrms.push_front(nrm)
		if not ok:
			continue
		d["pts"] = pts
		d["nrm"] = nrms
		d["pos"] = pos
		d["up"] = nrm
		d["phi"] = phi
		d["phi_want"] = phi
		d["state"] = "walk"
		d["timer"] = _rng.randf_range(20.0, 60.0)
		d["stuck"] = 0.0
		d["halt"] = 0.0
		d["turn_t"] = _rng.randf_range(5.0, 12.0)
		_lay_millipede(d)
		(d["node"] as Node3D).visible = true
		return true
	return false


func _update_trunk_millipede(d: Dictionary, delta: float) -> void:
	var pos: Vector3 = d["pos"]
	var nrm: Vector3 = d["up"]
	var height := pos.y - _ground(pos.x, pos.z)
	d["turn_t"] = float(d["turn_t"]) - delta
	var want: float = d["phi_want"]
	var going_up := absf(angle_difference(0.0, want)) < PI * 0.5
	if (height > 2.6 and going_up) or (height < 0.5 and not going_up):
		want = (PI if going_up else 0.0) + _rng.randf_range(-0.3, 0.3)       # round, and back
	elif float(d["turn_t"]) <= 0.0:
		d["turn_t"] = _rng.randf_range(5.0, 12.0)
		want = (0.0 if going_up else PI) + _rng.randf_range(-0.4, 0.4)      # the spiral's slant
	d["phi_want"] = want
	var phi: float = d["phi"]
	phi += clampf(angle_difference(phi, want), -0.5 * delta, 0.5 * delta)
	d["phi"] = phi
	var dir := _trunk_dir(nrm, phi)
	d["speed"] = move_toward(float(d["speed"]), float(d["pace"]) * float(d["sc"]), delta * 0.03)
	d["moving"] = clampf(float(d["speed"]) / (0.012 * float(d["sc"])), 0.0, 1.0)
	var move: float = float(d["speed"]) * delta
	# (the bark is felt for a few millimeters ahead, however small this frame's step)
	var probe := maxf(move, 0.004)
	var hit := _trunk_step(pos, nrm, dir, probe)
	d["blocked_t"] = maxf(float(d.get("blocked_t", 0.0)) - delta, 0.0)
	if hit.is_empty():
		# no bark that way: it turns around where it is (once, and then gives the turn time)
		d["stuck"] = float(d["stuck"]) + delta
		d["speed"] = 0.0
		d["moving"] = 0.0
		if float(d["blocked_t"]) <= 0.0:
			d["blocked_t"] = 5.0
			d["phi_want"] = phi + PI + _rng.randf_range(-0.5, 0.5)
	else:
		d["stuck"] = 0.0
		pos = pos.lerp(hit["position"], clampf(move / probe, 0.0, 1.0))
		d["pos"] = pos
		d["up"] = nrm.lerp(hit["normal"], 0.4).normalized()
		d["dist"] = fmod(float(d["dist"]) + move, 1000.0)
		var pts: Array = d["pts"]
		if pos.distance_to(pts[0]) >= 0.003:
			pts.push_front(pos)
			(d["nrm"] as Array).push_front(d["up"])
			var keep := int(RINGS * LM.M_PITCH * float(d["sc"]) / 0.003) + 16
			if pts.size() > keep:
				pts.resize(keep)
				(d["nrm"] as Array).resize(keep)
	d["yaw"] = atan2(-dir.x, -dir.z)
	_lay_millipede(d)


# ------------------------------------------------------------------ the Seychelles snail
## Stylodonta unidentata: a big brown land snail of the granite islands' forests, found
## nowhere else. Rare: two at most near the walker. It glides over the leaf litter, eye
## stalks out; when somebody comes within a step it draws in, stalks first, and waits.
func _make_snails() -> void:
	var body: ArrayMesh = LM.snail()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/snail.gdshader")
	var sh: Dictionary = LM.shell(4, 0.058)
	var smat := LM.shell_material()
	for i in SNAILS:
		var s: Dictionary = LM.snail_node(body, mat, sh, smat)
		var root: Node3D = s["root"]
		root.name = "Snail%d" % i
		add_child(root)
		root.visible = false
		root.position = Vector3(0, -50, 0)
		(s["body"] as MeshInstance3D).layers = 2
		(s["shell"] as MeshInstance3D).layers = 2
		snails.append({"node": root, "body": s["body"], "shell": s["shell"], "shell_y": (s["shell"] as Node3D).position.y, "sc": _rng.randf_range(1.0, 1.25), "state": "hidden", "timer": _rng.randf_range(8.0, 30.0),
			"pos": Vector3.ZERO, "up": Vector3.UP, "yaw": 0.0, "want": 0.0, "look": 0.0, "side": 1.0 if _rng.randf() < 0.5 else -1.0,
			"pace": _rng.randf_range(0.0035, 0.006), "speed": 0.0, "crawl": 0.0, "out": 1.0, "wait": 8.0, "stuck": 0.0, "turn_t": 6.0, "pend": 0.0})


func _place_snail(d: Dictionary, pp: Vector3) -> bool:
	var spot := _floor_spot(pp, 2.5, 7.0)
	if spot.is_empty():
		return false
	d["pos"] = spot["position"]
	d["up"] = spot["normal"]
	d["yaw"] = _rng.randf() * TAU
	d["want"] = d["yaw"]
	d["state"] = "crawl"
	d["timer"] = _rng.randf_range(20.0, 50.0)
	d["out"] = 1.0
	d["stuck"] = 0.0
	_pose_snail(d)
	(d["node"] as Node3D).visible = true
	return true


func _pose_snail(d: Dictionary) -> void:
	var n: Node3D = d["node"]
	var up: Vector3 = d["up"]
	var fwd := Vector3(-sin(float(d["yaw"])), 0, -cos(float(d["yaw"])))
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var z := -fwd
	var x := up.cross(z).normalized()
	n.global_transform = Transform3D(Basis(x, up, z).scaled(Vector3.ONE * float(d["sc"])), d["pos"])
	var bmi: MeshInstance3D = d["body"]
	bmi.set_instance_shader_parameter("out_k", d["out"])
	bmi.set_instance_shader_parameter("crawl", d["crawl"])
	# (drawn in, the shell comes down to lie on the ground)
	(d["shell"] as Node3D).position.y = float(d["shell_y"]) - 0.004 * (1.0 - smoothstep(0.0, 0.7, float(d["out"])))


func _update_snails(delta: float, pp: Vector3, act: float) -> void:
	var want_n := int(round(SNAILS * act))
	for i in snails.size():
		var d: Dictionary = snails[i]
		var allowed := i < want_n
		d["timer"] -= delta
		if d["state"] == "hidden":
			if allowed and d["timer"] <= 0.0:
				d["timer"] = _rng.randf_range(3.0, 8.0)
				_place_snail(d, pp)
			continue
		var pos: Vector3 = d["pos"]
		var dist := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if dist > 28.0 or (not allowed and (dist > 12.0 or not _in_view(pp, pos))) or float(d["stuck"]) > 40.0:
			d["state"] = "hidden"
			d["timer"] = _rng.randf_range(15.0, 45.0)
			(d["node"] as Node3D).visible = false
			continue
		var near := dist < 0.75 and absf(pp.y - pos.y) < 2.5 and _still < 1.0
		match d["state"]:
			"crawl":
				d["out"] = move_toward(float(d["out"]), 1.0, delta * 0.3)
				var yaw: float = d["yaw"]
				d["look"] -= delta
				d["turn_t"] -= delta
				if d["turn_t"] <= 0.0:
					d["turn_t"] = _rng.randf_range(8.0, 20.0)
					d["want"] = float(d["want"]) + _rng.randf_range(-0.8, 0.8)
				if d["look"] <= 0.0:
					d["look"] = 0.6
					var free := false
					for a: float in [0.0, 0.7, -0.7, 1.4, -1.4, 2.2, -2.2, PI]:
						var w: float = float(d["want"]) + a * float(d["side"])
						var h1 := _milli_step(pos, w, 0.04)
						if h1.is_empty() or not _floor_ok(h1["position"], false):
							continue
						d["want"] = w
						free = true
						break
					d["stuck"] = 0.0 if free else float(d["stuck"]) + 0.6
					if not free:
						d["want"] = _rng.randf() * TAU
				var diff := angle_difference(yaw, float(d["want"]))
				yaw += clampf(diff, -0.12 * delta, 0.12 * delta)
				d["yaw"] = yaw
				var v := float(d["pace"]) * float(d["sc"]) if float(d["stuck"]) < 0.5 and float(d["out"]) > 0.9 else 0.0
				d["speed"] = move_toward(float(d["speed"]), v, delta * 0.004)
				# (it moves a millimeter in a quarter of a second: the ground is asked for
				# every two millimeters)
				d["pend"] = float(d["pend"]) + float(d["speed"]) * delta
				if float(d["pend"]) >= 0.002:
					var hit := _milli_step(pos, yaw, float(d["pend"]))
					if hit.is_empty():
						d["speed"] = 0.0
						d["look"] = 0.0
					else:
						d["pos"] = hit["position"]
						d["up"] = (d["up"] as Vector3).lerp(hit["normal"], 0.2).normalized()
						d["crawl"] = fmod(float(d["crawl"]) + float(d["pend"]), 100.0)
					d["pend"] = 0.0
				if d["timer"] <= 0.0:
					d["state"] = "rest"
					d["timer"] = _rng.randf_range(8.0, 25.0)
				if near:
					d["state"] = "in"
					d["wait"] = _rng.randf_range(6.0, 12.0)
					d["timer"] = d["wait"]
			"rest":
				d["speed"] = 0.0
				if d["timer"] <= 0.0:
					d["state"] = "crawl"
					d["timer"] = _rng.randf_range(25.0, 70.0)
				if near:
					d["state"] = "in"
					d["wait"] = _rng.randf_range(6.0, 12.0)
					d["timer"] = d["wait"]
			"in":
				d["speed"] = 0.0
				d["out"] = move_toward(float(d["out"]), 0.0, delta * 0.9)
				if dist < 1.4 and _still < 1.5:
					d["timer"] = d["wait"]
				elif d["timer"] <= 0.0:
					d["state"] = "crawl"       # (it comes out slowly: see "crawl")
					d["timer"] = _rng.randf_range(25.0, 70.0)
		_pose_snail(d)


# ================================================================== the summit granite
## Bare granite at p (the land mask's green), 0 .. 1.
func _granite(p: Vector2) -> float:
	var mk: Image = _ls._mask
	if mk == null or _ground(p.x, p.y) < 0.5:
		return 0.0
	var u := int(clampf((p.x + 256.0) / 512.0 * mk.get_width(), 0, mk.get_width() - 1))
	var v := int(clampf((p.y + 256.0) / 512.0 * mk.get_height(), 0, mk.get_height() - 1))
	return mk.get_pixel(u, v).g


func _plant_xf(p: Vector2, rng: RandomNumberGenerator, lo: float, hi: float) -> Transform3D:
	var n := _normal(p.x, p.y)
	var b := Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(n, 0.85).normalized())) * Basis(Vector3.UP, rng.randf() * TAU)
	return Transform3D(b.scaled(Vector3.ONE * rng.randf_range(lo, hi)), Vector3(p.x, _ground(p.x, p.y) - 0.006, p.y))


## The plants of the granite slabs beside the summit. The lookout itself (the grass of the
## top) stays as it is, and so does the ridge the walker comes up; everything here is lower
## than a knee. Pitcher plants root where soil meets the rock and sprawl out over it, in
## colonies; orchids sit on the bare rock; the vanilla runs over it in green ropes.
func _plant_granite() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407
	var peak: Vector2 = _ls._peak
	var top := _ground(peak.x, peak.y)
	var edges: Array = []
	var inner: Array = []
	# (the slabs that lie around the top: within 45 m of it and no more than 22 m below it)
	for i in 9000:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 45.0
		var p := peak + Vector2(cos(a), sin(a)) * r
		if r < 6.0 or _granite(p) < 0.6 or float(_ls.trail_distance(p)) < 2.0 or _ground(p.x, p.y) < top - 22.0:
			continue
		if _normal(p.x, p.y).y < 0.8 or _solid(p.x, p.y):
			continue
		var edge := false
		for k in 6:
			if _granite(p + Vector2(cos(k * 1.047), sin(k * 1.047)) * 1.3) < 0.3:
				edge = true
		(edges if edge else inner).append(p)
	var parent := Node3D.new()
	parent.name = "Granite"
	add_child(parent)
	# --- pitcher plants: colonies along the slabs' edges
	# (the colonies nearest the top first: those are the ones a walker at the lookout finds)
	var by_peak: Array = edges.duplicate()
	by_peak.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_to(peak) < q.distance_to(peak))
	var centers: Array = []
	for p: Vector2 in by_peak:
		if centers.size() >= 9:
			break
		var far := true
		for c: Vector2 in centers:
			if c.distance_to(p) < 9.0:
				far = false
		if far:
			centers.append(p)
	var both: Array = edges + inner
	var lists := [[], [], []]
	for c: Vector2 in centers:
		var n := rng.randi_range(3, 6)
		var got := 0
		for p: Vector2 in both:
			if got >= n:
				break
			if p.distance_to(c) > 4.5:
				continue
			var free := true
			for q: Vector3 in pitcher_spots:
				if Vector2(q.x, q.z).distance_to(p) < 1.15:
					free = false
			if not free:
				continue
			var xf := _plant_xf(p, rng, 0.85, 1.25)
			(lists[rng.randi() % 3] as Array).append(xf)
			pitcher_spots.append(xf.origin)
			got += 1
	var mat := LM.plant_material()
	for k in 3:
		_plant_multimesh(parent, "Pitchers%d" % k, LM.pitcher(k)["mesh"], lists[k], mat)
	# --- tropicbird orchids on the rock, apart from each other and from the pitcher plants
	lists = [[], [], []]
	for p: Vector2 in both:
		if orchid_spots.size() >= 16:
			break
		var free := true
		for q: Vector3 in orchid_spots:
			if Vector2(q.x, q.z).distance_to(p) < 5.0:
				free = false
		for q: Vector3 in pitcher_spots:
			if Vector2(q.x, q.z).distance_to(p) < 1.6:
				free = false
		if not free:
			continue
		var xf := _plant_xf(p, rng, 1.1, 1.45)
		(lists[orchid_spots.size() % 3] as Array).append(xf)
		orchid_spots.append(xf.origin)
		# (an old plant is a clump of several fans)
		for extra in rng.randi_range(0, 2):
			var q := p + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
			if _granite(q) > 0.5:
				(lists[rng.randi() % 3] as Array).append(_plant_xf(q, rng, 0.9, 1.3))
	for k in 3:
		_plant_multimesh(parent, "Orchids%d" % k, LM.orchid(k)["mesh"], lists[k], mat)
	# --- the wild vanilla
	_plant_vanilla(parent, rng, edges, mat)


func _plant_multimesh(parent: Node3D, name_: String, mesh: Mesh, xforms: Array, mat: Material) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)


## The wild vanilla (Vanilla phalaenopsis: a leafless orchid of the Seychelles' granite): green
## ropes as thick as a finger that run over the bare rock, forking here and there, with a
## few large white flowers, apricot in the throat, where a rope's end lifts off the stone.
func _plant_vanilla(parent: Node3D, rng: RandomNumberGenerator, edges: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.3, 0.5, 0.18)
	var starts: Array = []
	for p: Vector2 in edges:
		if starts.size() >= 7:
			break
		var free := true
		for q: Vector2 in starts:
			if q.distance_to(p) < 11.0:
				free = false
		for q: Vector3 in pitcher_spots:
			if Vector2(q.x, q.z).distance_to(p) < 2.5:
				free = false
		if free:
			starts.append(p)
	for s: Vector2 in starts:
		# toward the middle of the rock: away from the soil it roots in
		var best := rng.randf() * TAU
		var most := -1.0
		for k in 8:
			var a := k * TAU / 8.0
			var gsum := _granite(s + Vector2(cos(a), sin(a)) * 2.0) + _granite(s + Vector2(cos(a), sin(a)) * 4.0)
			if gsum > most:
				most = gsum
				best = a
		var ropes := [[s, best, rng.randi_range(45, 80)]]
		var made := 0
		while not ropes.is_empty() and made < 4:
			var job: Array = ropes.pop_back()
			made += 1
			var p: Vector2 = job[0]
			var a: float = job[1]
			var pts: Array = []
			var turn := rng.randf_range(-0.12, 0.12)
			var shut := 0
			for i in int(job[2]):
				var q := p + Vector2(cos(a), sin(a)) * 0.07
				if _granite(q) < 0.25 or _solid(q.x, q.y):
					a += 0.6 * (1.0 if turn > 0.0 else -1.0)
					shut += 1
					if shut > 5:
						break
					continue
				shut = 0
				p = q
				a += turn + rng.randf_range(-0.1, 0.1)
				if rng.randf() < 0.08:
					turn = rng.randf_range(-0.14, 0.14)
				pts.append(Vector3(p.x, _ground(p.x, p.y) + 0.006, p.y))
				if i > 12 and rng.randf() < 0.03 and ropes.size() < 2:
					ropes.append([p, a + (0.7 if rng.randf() < 0.5 else -0.7), rng.randi_range(20, 45)])
			if pts.size() < 8:
				continue
			# the end lifts off the rock; one rope in two flowers there
			var n := pts.size()
			for i in range(n - 5, n):
				pts[i] = (pts[i] as Vector3) + Vector3(0, 0.016 * (i - (n - 6)) * (i - (n - 6)) * 0.3, 0)
			LM._stalk(st, pts, 0.0075, 0.006, green, green.lerp(Color(0.45, 0.6, 0.25), 0.5), 0.0, 0.0, 6)
			vanilla_spots.append(pts[n - 1])
			if rng.randf() < 0.6:
				var tip: Vector3 = pts[n - 1]
				var out := ((pts[n - 1] as Vector3) - (pts[n - 4] as Vector3)).normalized()
				for f in rng.randi_range(1, 3):
					var dir := (out + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.5, 1.0), rng.randf_range(-0.6, 0.6))).normalized()
					var at := tip + dir * 0.035
					LM._stalk(st, [tip, at], 0.003, 0.003, green, green, 0.3, 0.5, 4)
					LM.vanilla_flower(st, at, dir, rng.randf_range(0.055, 0.07))
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = "Vanilla"
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)


# ================================================================== for the tests
func report() -> Dictionary:
	var hs := {}
	for d: Dictionary in hermits:
		hs[d["state"]] = int(hs.get(d["state"], 0)) + 1
	var ms := 0
	var climbers: Array = []
	for d: Dictionary in millipedes:
		if d["state"] != "hidden":
			ms += 1
			if d.get("trunk", false):
				climbers.append(snappedf((d["pos"] as Vector3).y - _ground((d["pos"] as Vector3).x, (d["pos"] as Vector3).z), 0.01))
	var ss := {}
	for d: Dictionary in snails:
		ss[d["state"]] = int(ss.get(d["state"], 0)) + 1
	return {"activity": activity(), "hermit crabs": hs, "millipedes out": ms, "of them on trunks, at (m above the ground)": climbers, "snails": ss,
		"pitcher clumps": pitcher_spots.size(), "orchids": orchid_spots.size(), "vanilla ropes": vanilla_spots.size()}


## (for the tests) The head of a millipede that is on a trunk, or null.
func climber() -> Node3D:
	for d: Dictionary in millipedes:
		if d["state"] != "hidden" and d.get("trunk", false):
			return d["head"]
	return null


## The nearest one that shows: kind 0 a hermit crab, 1 a millipede (its head), 2 a snail.
func nearest(kind: int) -> Node3D:
	var pp := _player.global_position
	var best: Node3D = null
	var best_d := 1e9
	for d: Dictionary in [hermits, millipedes, snails][kind]:
		if d["state"] == "hidden":
			continue
		var dd := (d["pos"] as Vector3).distance_to(pp)
		if dd < best_d:
			best_d = dd
			best = d["head"] if kind == 1 else d["node"]
	return best


## Half an hour of their lives in a moment (the walker stands where they are): how far each
## got, how long anybody stood still while meaning to walk, whether anybody ended up where it
## must not be.
func soak(seconds := 1800.0, dt := 0.05) -> Dictionary:
	var was := force
	force = 1
	var start := {}
	var travel := {}
	var last := {}
	var worst_still := 0.0
	var still := {}
	var wet_feet := 0
	var on_trunks := 0
	var in_solid := 0
	var off_floor := 0
	var bad := 0
	var shown := [0, 0, 0]
	var steps := int(seconds / dt)
	var who := ""
	var pp := _player.global_position
	for s in steps:
		_step(dt, pp)
		var all: Array = hermits + millipedes + snails
		for k in all.size():
			var d: Dictionary = all[k]
			if d["state"] == "hidden":
				last.erase(k)
				still[k] = 0.0
				continue
			var p: Vector3 = d["pos"]
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
				bad += 1
			if last.has(k):
				var moved := p.distance_to(last[k])
				travel[k] = float(travel.get(k, 0.0)) + moved
				var walking: bool = d["state"] == "walk" or d["state"] == "crawl"
				still[k] = float(still.get(k, 0.0)) + dt if walking and moved < 0.00001 else 0.0
				if float(still[k]) > worst_still:
					worst_still = float(still[k])
					who = (d["node"] as Node).name
			last[k] = p
			if s % 20 == 0:
				if k < hermits.size():
					shown[0] += 1
					if _ground(p.x, p.z) - float(_ls.sea) < 0.1:
						wet_feet += 1
					if _solid(p.x, p.z):
						in_solid += 1
				else:
					shown[1 if k < hermits.size() + millipedes.size() else 2] += 1
					if d.get("trunk", false):
						on_trunks += 1
						continue
					if not _floor_ok(p, false):
						off_floor += 1
					if p.y - _ground(p.x, p.z) > 0.35:
						in_solid += 1
	force = was
	var far := 0.0
	var least := 1e9
	for k in travel:
		far = maxf(far, float(travel[k]))
		least = minf(least, float(travel[k]))
	return {"steps": steps, "samples of hermits / millipedes / snails showing": shown, "longest way (m)": far, "shortest way (m)": least,
		"longest standstill while walking (s)": worst_still, "who stood": who, "hermit samples in the water": wet_feet, "samples on something solid": in_solid,
		"samples off the forest floor": off_floor, "millipede samples on a trunk": on_trunks, "NaN": bad, "now": report()}


## Somebody walks up to the nearest animal of a kind, stands over it for `stay` seconds and
## walks off again: what it did, second by second (state, and how far it is drawn in).
func react_test(kind: int, stay := 20.0) -> Array:
	var was := force
	force = 1
	var log: Array = []
	var best: Dictionary = {}
	var pp := _player.global_position
	for d: Dictionary in [hermits, millipedes, snails][kind]:
		if d["state"] != "hidden" and (best.is_empty() or (d["pos"] as Vector3).distance_to(pp) < (best["pos"] as Vector3).distance_to(pp)):
			best = d
	if best.is_empty():
		return ["nobody is out"]
	var from := pp
	var t := 0.0
	var dt := 0.05
	var total := 6.0 + stay + 14.0
	while t < total:
		var at: Vector3 = best["pos"]
		var goal := at + (from - at).normalized() * 0.45
		var w := pp
		if t < 6.0:
			w = from.lerp(goal, t / 6.0)              # walking up
		elif t < 6.0 + stay:
			w = goal                                  # standing there
		else:
			w = goal.lerp(from, (t - 6.0 - stay) / 14.0)   # walking off
		w.y = at.y + 0.9
		_step(dt, w)
		if fmod(t, 2.0) < dt:
			var k: float = float(best.get("tuck", 1.0 - float(best.get("out", 1.0)))) if kind != 1 else float(best["halt"])
			log.append("%.0f s: %s %.2f at %.2f m" % [t, best["state"], k, Vector2(w.x - at.x, w.z - at.z).length()])
		t += dt
	force = was
	return log


## Sends the nearest animal of a kind into its shell at once (for pictures).
func scare(kind: int) -> void:
	var pp := _player.global_position
	var best: Dictionary = {}
	for d: Dictionary in [hermits, [], snails][kind]:
		if d["state"] != "hidden" and (best.is_empty() or (d["pos"] as Vector3).distance_to(pp) < (best["pos"] as Vector3).distance_to(pp)):
			best = d
	if not best.is_empty():
		best["state"] = "in"
		best["wait"] = 30.0
		best["timer"] = 30.0
		if kind == 0:
			best["tuck"] = 1.0
		else:
			best["out"] = 0.0


# ================================================================== a coconut falls
## Every few minutes a ripe coconut drops from a palm somewhere near the walker (never
## nearer than nine meters: nothing here is to frighten): it falls, lands with a thud and
## lies there. At most five lie about; the oldest is taken for the next fall.
var _nut_mesh: Mesh
var _nuts: Array = []          # {"node", "vy", "to_y", "falling", "spin"}
var _nut_t := 150.0
var _nut_voice: AudioStreamPlayer3D
var _nut_sounds: Array[AudioStream] = []
var nuts_fallen := 0


func drop_coconut(pp: Vector3) -> bool:
	if _nut_mesh == null:
		var scene := load("res://assets/models/debris.glb") as PackedScene
		if scene == null:
			return false
		var tmp := scene.instantiate()
		var src := tmp.find_child("Coconut", true, false) as MeshInstance3D
		if src:
			_nut_mesh = src.mesh
		tmp.free()
		for i in 6:
			var path := "res://assets/audio/coconut_thud_%d.wav" % i
			if ResourceLoader.exists(path):
				_nut_sounds.append(load(path))
		_nut_voice = AudioStreamPlayer3D.new()
		_nut_voice.bus = "Ambient"
		_nut_voice.unit_size = 6.0
		_nut_voice.max_distance = 60.0
		_nut_voice.volume_db = -3.0
		add_child(_nut_voice)
	if _nut_mesh == null:
		return false
	var near: Array = []
	for t: Dictionary in _ls.palm_trunks:
		var pts: PackedVector3Array = t["pts"]
		var top := pts[pts.size() - 1]
		var d := Vector2(top.x - pp.x, top.z - pp.z).length()
		if d > 9.0 and d < 32.0 and top.y - pts[0].y > 4.0:
			near.append(top)
	if near.is_empty():
		return false
	var top: Vector3 = near[_rng.randi() % near.size()]
	var a := _rng.randf() * TAU
	var from := top + Vector3(cos(a) * 0.5, -0.4, sin(a) * 0.5)
	var hit := _ray(from, from - Vector3(0, 40.0, 0))
	if hit.is_empty() or (hit["position"] as Vector3).y < float(_ls.sea) + 0.1:
		return false       # (into the sea: not this one)
	var d: Dictionary = {}
	if _nuts.size() < 5:
		var mi := MeshInstance3D.new()
		mi.name = "FallenCoconut%d" % _nuts.size()
		mi.mesh = _nut_mesh
		add_child(mi)
		d = {"node": mi}
		_nuts.append(d)
	else:
		d = _nuts[nuts_fallen % _nuts.size()]
	(d["node"] as Node3D).global_position = from
	d.merge({"vy": 0.0, "to_y": (hit["position"] as Vector3).y + 0.08, "falling": true, "spin": Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))}, true)
	nuts_fallen += 1
	return true


func _update_coconuts(delta: float, pp: Vector3) -> void:
	_nut_t -= delta
	if _nut_t <= 0.0:
		_nut_t = _rng.randf_range(240.0, 600.0) if drop_coconut(pp) else 30.0
	for d: Dictionary in _nuts:
		if not d["falling"]:
			continue
		var n: Node3D = d["node"]
		d["vy"] = float(d["vy"]) - 9.81 * delta
		var p := n.global_position + Vector3(0, float(d["vy"]) * delta, 0)
		n.rotation += (d["spin"] as Vector3) * delta
		if p.y <= float(d["to_y"]):
			p.y = float(d["to_y"])
			d["falling"] = false
			if not _nut_sounds.is_empty():
				_nut_voice.global_position = p
				_nut_voice.stream = _nut_sounds[_rng.randi() % _nut_sounds.size()]
				_nut_voice.pitch_scale = _rng.randf_range(0.9, 1.08)
				_nut_voice.play()
		n.global_position = p
