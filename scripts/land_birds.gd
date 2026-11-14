extends Node3D
## Four birds of the land (models: scripts/bird_models.gd; the node is created by
## island_life.gd; it flies and poses them with the shore birds' helpers):
##  * common mynahs, a pair: they strut about open ground near the walker, wary;
##  * barred ground doves (zebra doves), three: they patter about picking at the ground,
##    and let one come close;
##  * Seychelles fodies, three: on the forest floor, hopping, almost underfoot;
##  * the Seychelles magpie-robin, one, and rare: it turns up on the forest floor now and
##    then, hops about turning the leaf litter, and is away again for minutes.
## Each kind keeps together. A group flies in and comes down near the walker; pressed, it
## flies a little way off; left behind, it turns up again somewhere ahead. None at night.
## For the tests: report(), summon(), soak().

const BirdModels := preload("res://scripts/bird_models.gd")
const NONE := Vector3(1e9, 0, 0)
const KINDS := [
	# ("call": seconds between calls, from .. to; "voice": unit size, how far it is heard, dB)
	{"kind": "mynah", "n": 2, "open": true, "walk": 0.38, "wary": 4.5, "flush": 2.4, "beat": 6.0, "peck": 0.45, "speed": 7.5, "hops": false, "rare": false,
		"call": [5.0, 16.0], "voice": [7.0, 80.0, -3.0]},
	{"kind": "zebra_dove", "n": 3, "open": true, "walk": 0.22, "wary": 2.2, "flush": 1.1, "beat": 8.5, "peck": 0.75, "speed": 8.0, "hops": false, "rare": false,
		"call": [14.0, 40.0], "voice": [4.0, 45.0, -9.0]},
	{"kind": "fody", "n": 3, "open": false, "walk": 0.3, "wary": 1.6, "flush": 0.85, "beat": 11.0, "peck": 0.6, "speed": 6.5, "hops": true, "rare": false,
		"call": [9.0, 28.0], "voice": [3.0, 32.0, -11.0]},
	{"kind": "magpie_robin", "n": 1, "open": false, "walk": 0.4, "wary": 2.4, "flush": 1.2, "beat": 7.5, "peck": 0.55, "speed": 7.0, "hops": true, "rare": true,
		"call": [10.0, 28.0], "voice": [5.0, 60.0, -6.0]},
]

var groups: Array = []
var _ls: Node
var _player: Node3D
var _sb: Node            # ShoreBirds: _pose_ground, _start_hop, _update_hop, _free, _way_free
var _daycycle: Node
var _rng := RandomNumberGenerator.new()
var _shrubs: Array = []
var _started := false


func setup(ls: Node, player: Node3D, shorebirds: Node) -> void:
	_ls = ls
	_player = player
	_sb = shorebirds
	_daycycle = get_node_or_null("../../DayCycle")
	_rng.seed = 31337
	for prm: Dictionary in KINDS:
		var g := {"prm": prm, "birds": [], "center": NONE, "wait": _rng.randf_range(4.0, 25.0) if not prm["rare"] else _rng.randf_range(60.0, 200.0),
			"far_t": 0.0, "flushes": 0, "arrivals": 0, "calls": 0, "call_t": _rng.randf_range(2.0, 8.0),
			"voice": shorebirds._voice(self, float(prm["voice"][0]), float(prm["voice"][1]), float(prm["voice"][2]))}
		for i in int(prm["n"]):
			var b: Dictionary = BirdModels.make(prm["kind"])
			add_child(b["root"])
			(b["root"] as Node3D).scale = Vector3.ONE * _rng.randf_range(0.95, 1.08)
			(b["root"] as Node3D).visible = false
			(b["root"] as Node3D).position = Vector3(0, -50, 0)
			b.merge({"pos": Vector3.ZERO, "yaw": _rng.randf() * TAU, "state": "stand", "goal": NONE, "wait": _rng.randf_range(0.5, 3.0), "gait": _rng.randf() * TAU,
				"peck": 0.0, "peck_t": 0.0, "flap": _rng.randf() * TAU, "amp": 0.0, "leaving": false})
			(g["birds"] as Array).append(b)
		groups.append(g)


func _ground(x: float, z: float) -> float:
	return float(_ls.ground(x, z))


## May a bird of this kind stand at p? Dry, level, nothing solid, not under a fern or a
## shrub, away from the fresh water and the grotto, in its kind's country: open ground
## (the top of the beach, grass) or the forest floor.
func _ok(prm: Dictionary, p: Vector3) -> bool:
	var v := Vector2(p.x, p.z)
	var g := _ground(p.x, p.z)
	if g < 0.9 or absf(_ground(p.x + 0.4, p.z) - _ground(p.x - 0.4, p.z)) > 0.22 or absf(_ground(p.x, p.z + 0.4) - _ground(p.x, p.z - 0.4)) > 0.22:
		return false
	if float(_ls.stream_dist(v)) < 2.5 or float(_ls.cave_dist(v)) < 11.0 or _ls.ferny(v, 0.15) or _sb.in_sooty_patch(p, 2.0):
		return false
	var c: Color = _ls.cover(p.x, p.z)
	if bool(prm["open"]) != (_ls.sandy(v) or c.b > 0.35 or c.r < 0.45):
		return false
	return not _in_bush(p) and _sb._free(p.x, p.z, 0.3)


## Can the walker see the place from where they stand: nothing solid and no shrub between
## their eyes and it? (Birds that come down behind the hedge are not met.)
func _seen(pp: Vector3, at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 1.6, 0), at + Vector3(0, 0.15, 0), 3)
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Is p under a shrub? (Their volumes are bodies on layer 2; the ray comes from above the
## tallest of them. A first version asked a list of the shrubs' boxes, which was empty: the
## doves and mynahs came down inside the bushes behind the beach.)
func _in_bush(p: Vector3) -> bool:
	var g := _ground(p.x, p.z)
	var space := get_world_3d().direct_space_state
	for o: Vector2 in [Vector2.ZERO, Vector2(0.45, 0), Vector2(-0.45, 0), Vector2(0, 0.45), Vector2(0, -0.45)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x + o.x, g + 14.0, p.z + o.y), Vector3(p.x + o.x, g - 0.2, p.z + o.y), 2)
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func _spot(prm: Dictionary, around: Vector3, r0: float, r1: float, from := NONE) -> Vector3:
	for i in 16:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r0, r1)
		var p := Vector3(around.x + cos(a) * r, 0, around.z + sin(a) * r)
		if from != NONE and Vector2(p.x - from.x, p.z - from.z).length() < Vector2(around.x - from.x, around.z - from.z).length() + r0 * 0.5:
			continue
		if _ok(prm, p):
			p.y = _ground(p.x, p.z)
			return p
	return NONE


## The group flies to `center` and comes down around it.
func _fly_to(g: Dictionary, center: Vector3, from_far: bool) -> void:
	var prm: Dictionary = g["prm"]
	g["center"] = center
	g["far_t"] = 0.0
	var a := _rng.randf() * TAU
	for i in (g["birds"] as Array).size():
		var b: Dictionary = g["birds"][i]
		var to := center
		for k in 10:
			var q := center + Vector3(_rng.randf_range(-1.3, 1.3), 0, _rng.randf_range(-1.3, 1.3))
			if i == 0 or _sb._free(q.x, q.z, 0.25) and _ground(q.x, q.z) > 0.9:
				to = Vector3(q.x, _ground(q.x, q.z), q.z) if i > 0 else center
				break
		if from_far:
			b["pos"] = center + Vector3(cos(a) * 14.0 + i * 0.6, 6.0 + i * 0.4, sin(a) * 14.0)
		(b["root"] as Node3D).visible = true
		b["leaving"] = false
		b["goal"] = NONE
		_sb._start_hop(b, to, 0.8 if not from_far else 0.2, float(prm["speed"]), Vector3.ZERO, i * 0.25 if not from_far else i * 0.4)


## The group goes: up and away over the trees, and is not seen for a while.
func _leave(g: Dictionary, away_from: Vector3) -> void:
	var prm: Dictionary = g["prm"]
	var c: Vector3 = g["center"]
	var dir := Vector3(c.x - away_from.x, 0, c.z - away_from.z).normalized()
	for i in (g["birds"] as Array).size():
		var b: Dictionary = g["birds"][i]
		b["leaving"] = true
		_sb._start_hop(b, (b["pos"] as Vector3) + dir * 22.0 + Vector3(i * 0.7, 9.0, 0), 1.0, float(prm["speed"]), Vector3.ZERO, i * 0.2)
	g["center"] = NONE
	g["wait"] = _rng.randf_range(20.0, 50.0) if not prm["rare"] else _rng.randf_range(240.0, 600.0)


func _physics_process(_delta: float) -> void:
	# (places are tested with rays: the collision shapes are there after a few frames)
	if not _started and Engine.get_physics_frames() > 40:
		_started = true
		_shrubs = _sb._shrub_list()


func _process(delta: float) -> void:
	if not _started or _player == null:
		return
	_step(minf(delta, 0.1), _player.global_position)


func _step(delta: float, pp: Vector3) -> void:
	var night: float = _daycycle.night if _daycycle else 0.0
	var life := get_parent()
	var asleep: bool = night > 0.5 or (life != null and life.get("raining") == true)
	for g: Dictionary in groups:
		var prm: Dictionary = g["prm"]
		var center: Vector3 = g["center"]
		if center == NONE:
			# birds still on their way off; then, after a while, in again near the walker
			var busy := false
			for b: Dictionary in g["birds"]:
				if b["state"] == "fly":
					busy = true
					if _sb._update_hop(b, delta, float(prm["beat"])):
						(b["root"] as Node3D).visible = false
			g["wait"] = float(g["wait"]) - delta
			if not busy and float(g["wait"]) <= 0.0 and not asleep:
				g["wait"] = 1.5
				g["tries"] = int(g.get("tries", 0)) + 1
				var look: Variant = _player.get("_yaw")
				var ahead := pp + (Vector3(-sin(float(look)), 0, -cos(float(look))) * 9.0 if look != null else Vector3.ZERO)
				var at := _spot(prm, ahead, 3.0, 14.0)
				if at != NONE and Vector2(at.x - pp.x, at.z - pp.z).length() > float(prm["wary"]) + 3.0 and (_seen(pp, at) or int(g["tries"]) > 14):
					# (in sight of the walker; after twenty seconds of finding no such place, anywhere near)
					g["tries"] = 0
					g["arrivals"] = int(g["arrivals"]) + 1
					_fly_to(g, at, true)
			continue
		var dist := Vector2(pp.x - center.x, pp.z - center.z).length()
		g["far_t"] = float(g["far_t"]) + delta if dist > 45.0 else 0.0
		if asleep or float(g["far_t"]) > 8.0:
			_leave(g, pp)
			if not asleep and not prm["rare"]:
				g["wait"] = _rng.randf_range(4.0, 12.0)
			continue
		# its voice, from one of the birds on the ground, now and then
		g["call_t"] = float(g["call_t"]) - delta
		if float(g["call_t"]) <= 0.0:
			g["call_t"] = _rng.randf_range(float(prm["call"][0]), float(prm["call"][1]))
			var who: Dictionary = g["birds"][_rng.randi() % (g["birds"] as Array).size()]
			var voice: AudioStreamPlayer3D = g["voice"]
			if who["state"] != "fly" and not voice.playing:
				voice.global_position = (who["pos"] as Vector3) + Vector3(0, 0.15, 0)
				_sb._call(voice, prm["kind"])
				if voice.playing:
					g["calls"] = int(g["calls"]) + 1
		var pressed := false
		for b: Dictionary in g["birds"]:
			if b["state"] == "fly":
				_sb._update_hop(b, delta, float(prm["beat"]))
				continue
			var pos: Vector3 = b["pos"]
			var to_p := Vector3(pp.x - pos.x, 0, pp.z - pos.z)
			var d := to_p.length()
			if d < float(prm["flush"]) and absf(pp.y - pos.y) < 3.0:
				pressed = true
			b["wait"] = float(b["wait"]) - delta
			b["peck_t"] = float(b["peck_t"]) - delta
			var moving := 0.0
			if b["state"] == "stand":
				if d < float(prm["wary"]):
					# somebody is coming: it walks off, without haste
					var away := -to_p.normalized().rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
					var q := pos + away * _rng.randf_range(1.2, 2.4)
					if _ok(prm, q):
						b["goal"] = q
						b["state"] = "walk"
						b["hurry"] = 1.5
				elif float(b["wait"]) <= 0.0:
					if _rng.randf() < float(prm["peck"]):
						b["peck_t"] = _rng.randf_range(0.25, 0.5)
						b["wait"] = _rng.randf_range(0.6, 1.6)
					else:
						var q := center + Vector3(_rng.randf_range(-2.2, 2.2), 0, _rng.randf_range(-2.2, 2.2))
						if _ok(prm, q) and Vector2(q.x - pos.x, q.z - pos.z).length() > 0.3:
							b["goal"] = q
							b["state"] = "walk"
							b["hurry"] = 1.0
						else:
							b["wait"] = 0.5
			if b["state"] == "walk":
				var goal: Vector3 = b["goal"]
				var to := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
				var dir := to.normalized()
				if to.length() < 0.06 or not _sb._way_free(pos, dir, 0.22):
					b["state"] = "stand"
					b["wait"] = _rng.randf_range(0.4, 2.5)
				else:
					var speed: float = float(prm["walk"]) * float(b.get("hurry", 1.0))
					pos += dir * minf(speed * delta, to.length())
					b["yaw"] = lerp_angle(float(b["yaw"]), atan2(-dir.x, -dir.z), 1.0 - exp(-8.0 * delta))
					b["gait"] = fmod(float(b["gait"]) + speed * delta / (float(b["hip"]) * 2.4 + 0.02) * TAU, TAU * 64.0)
					moving = 1.0
			pos.y = _ground(pos.x, pos.z)
			if prm["hops"] and moving > 0.0:
				# (a hopping bird: both feet together, the body up with every hop)
				pos.y += absf(sin(float(b["gait"]) * 0.5)) * 0.022
				moving = 0.25
			b["pos"] = pos
			b["peck"] = move_toward(float(b["peck"]), 1.0 if float(b["peck_t"]) > 0.0 else 0.0, delta * 7.0)
			_sb._pose_ground(b, moving)
			if prm["kind"] == "zebra_dove":
				# a dove's head bobs as it walks: with every step it is thrust forward and
				# then stays where it is while the body walks up under it
				var ph := fposmod(float(b["gait"]) / PI, 1.0)
				var want_bob := 0.0
				if moving > 0.5:
					want_bob = lerpf(0.014, -0.014, ph / 0.75) if ph < 0.75 else lerpf(-0.014, 0.014, (ph - 0.75) / 0.25)
				b["bob"] = lerpf(float(b.get("bob", 0.0)), want_bob, 1.0 - exp(-40.0 * delta))
				(b["stand"] as MeshInstance3D).set_instance_shader_parameter("bob", b["bob"])
		if pressed:
			# too near: all of them fly a little way off
			g["flushes"] = int(g["flushes"]) + 1
			var at := _spot(prm, center, 9.0, 18.0, pp)
			if at != NONE:
				_fly_to(g, at, false)
			else:
				_leave(g, pp)


func report() -> Array:
	var out: Array = []
	for g: Dictionary in groups:
		var states := {}
		for b: Dictionary in g["birds"]:
			states[b["state"]] = int(states.get(b["state"], 0)) + 1
		out.append({"kind": (g["prm"] as Dictionary)["kind"], "here": g["center"] != NONE, "center": g["center"] if g["center"] != NONE else "away",
			"birds": states, "arrivals": g["arrivals"], "flushes": g["flushes"], "calls": g["calls"], "back in (s)": snappedf(float(g["wait"]), 1.0)})
	return out


## Somebody walks straight into the middle of a group and stands there for `seconds`: what
## the group did.
func flush_test(i: int, seconds := 6.0) -> Dictionary:
	var g: Dictionary = groups[i]
	if g["center"] == NONE:
		return {"group": "away"}
	var c: Vector3 = g["center"]
	var t := 0.0
	while t < seconds:
		_step(0.05, c + Vector3(0, 0.9, 0))
		t += 0.05
	var states := {}
	for b: Dictionary in g["birds"]:
		states[b["state"]] = int(states.get(b["state"], 0)) + 1
	return {"flushes": g["flushes"], "moved (m)": c.distance_to(g["center"]) if g["center"] != NONE else -1.0, "birds": states}


## Brings every kind in now (the rare one too).
func summon() -> void:
	for g: Dictionary in groups:
		if g["center"] == NONE:
			g["wait"] = 0.0


## Their lives in a moment, the walker standing where they are: do they keep moving, does
## anybody stand in something solid, is anything not a number?
func soak(seconds := 900.0) -> Dictionary:
	var pp := _player.global_position
	var dt := 0.05
	var solid := 0
	var samples := 0
	var bad := 0
	var way := 0.0
	var last := {}
	for s in int(seconds / dt):
		_step(dt, pp)
		for g: Dictionary in groups:
			if g["center"] == NONE:
				continue
			for b: Dictionary in g["birds"]:
				var p: Vector3 = b["pos"]
				if is_nan(p.x) or is_nan(p.y):
					bad += 1
				var id := (b["root"] as Node).get_instance_id()
				if last.has(id) and b["state"] != "fly":
					way += minf(p.distance_to(last[id]), 0.5)
				last[id] = p
				if s % 20 == 0 and b["state"] != "fly":
					samples += 1
					if _sb._solid(p.x, p.z):
						solid += 1
	return {"samples on the ground": samples, "of them in something solid": solid, "NaN": bad, "walked in all (m)": way, "now": report()}
