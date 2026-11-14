extends Node3D
## Two sea turtles live in the lagoon off the start beach, the two species of the Seychelles:
## a green turtle that grazes the seagrass meadows, lying on the bottom and cropping the
## blades, and a smaller hawksbill that noses about the coral heads. Each swims with slow
## beats of its front flippers ("flying" under water) and long glides, the hind flippers
## trailing as rudders, and every minute or two comes up to breathe: the head breaks the
## surface for a few seconds, then it goes down again. They let a snorkeler come close; from
## within arm's length they move off without haste.
## At night they sleep: each lies on the bottom where it fed last (the hawksbill beside its
## coral), does not feed, and comes up for air only every four or five minutes.
## The node is created by island_life.gd; the models are built by sea_models.gd.

const SeaModels := preload("res://scripts/sea_models.gd")
const MIN_DEPTH := 1.3        # hard rule: never over ground shallower than this
const MAX_DEPTH := 13.0       # ... and not out over the reef slope
const OVER := 0.5             # water it keeps between a coral's top and its own underside
const WATER_OVER := 1.15     # a coral with less water than this over its top is gone round, not over

## Corals and rocks on the sea floor are solid to the turtles (until 2026-11-12 a
## turtle could swim right through a larger coral). (For the tests: false is how it was.)
var avoid_corals := true

var _player: Node3D
var _ls: Node
var _seabed: Node
var _sealife: Node
var _rng := RandomNumberGenerator.new()
var turtles: Array = []       # one dictionary each
var asleep := false           # it is night (set in _process; the tests may set it)
var _daycycle: Node


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed
	_sealife = get_node_or_null("../../SeaLife")
	_rng.randomize()
	_add(true, Vector2(50, 28))
	_add(false, Vector2(52, -34))


func _add(green: bool, home: Vector2) -> void:
	var node := SeaModels.turtle_node(green)
	node.name = "GreenTurtle" if green else "Hawksbill"
	var sc := 0.95 if green else 0.78
	add_child(node)
	for c in node.get_children():
		(c as MeshInstance3D).extra_cull_margin = 0.7
	var start := _water_near(home, 30.0, 2.4, 6.0)
	var d := {"node": node, "green": green, "sc": sc, "home": home, "pos": Vector3(start.x, _ground(start.x, start.y) + 1.0, start.y),
		"yaw": _rng.randf() * TAU, "pitch": 0.0, "roll": 0.0, "speed": 0.3, "vy": 0.0, "state": "cruise", "t": 0.0, "goal": start,
		"look": null, "feed_h": 0.3, "feed_len": 40.0, "breath": _rng.randf_range(25.0, 80.0), "phase": _rng.randf() * TAU, "stroke": 1.0,
		"glide": _rng.randf_range(3.0, 7.0), "bite": 0.0, "shuffle": 0.0, "next_shuffle": 10.0, "head": Vector2.ZERO, "turn": 0.0, "wait": 0.0}
	_new_goal(d)
	turtles.append(d)
	_place(d, 0.0)


## (Everything here is worked out as if the sea stood at 0: `_ground()` is the ground against
## the sea's level now, and the node is lifted to that level in _process().)
func _ground(x: float, z: float) -> float:
	return float(_ls.ground(x, z)) - float(_ls.sea)


func _depth(p: Vector2) -> float:
	return -_ground(p.x, p.y)


func _wave(x: float, z: float) -> float:
	return float(_sealife.wave_height(x, z)) if _sealife else 0.0


## A point within r of `around` over water between d0 and d1 deep (or `around` itself).
func _water_near(around: Vector2, r: float, d0: float, d1: float) -> Vector2:
	for i in 80:
		var p := around + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * r)
		var dep := _depth(p)
		if dep > d0 and dep < d1:
			return p
	return around


## The top of what stands at p: a coral, a rock or the ground (seabed.gd: top_at()), as if
## the sea stood at 0. `skirt`: over how many meters beyond its edge a coral's height falls
## away (wide: the slope the turtle climbs to pass over it; narrow: the coral itself).
func _top(p: Vector2, skirt: float) -> float:
	if avoid_corals and _seabed and _seabed.has_method("top_at"):
		return float(_seabed.top_at(p, skirt)) - float(_ls.sea)
	return _ground(p.x, p.y)


## The top of a coral or rock standing at p (within a hand's breadth of it), or -99 where
## there is only the ground.
func _coral(p: Vector2, skirt := 0.3) -> float:
	if not avoid_corals or _seabed == null:
		return -99.0
	var t := float(_seabed.top_at(p, skirt)) - float(_ls.sea)
	return t if t > _ground(p.x, p.y) + 0.05 else -99.0


## Deep enough water all the way from a to b, and no coral on the way that comes too near
## the surface to be swum over?
func _clear(a: Vector2, b: Vector2) -> bool:
	var n := maxi(int(a.distance_to(b) / 2.0), 1)
	for i in n + 1:
		var dep := _depth(a.lerp(b, float(i) / n))
		if dep < MIN_DEPTH + 0.3 or dep > MAX_DEPTH:
			return false
	if avoid_corals:
		n = maxi(int(a.distance_to(b) / 0.5), 1)
		for i in n + 1:
			if _top(a.lerp(b, float(i) / n), 0.3) > -WATER_OVER:
				return false
	return true


## Where to feed next. The green turtle: a spot where the seagrass stands thick. The hawksbill:
## beside a sizeable coral, facing it.
func _new_goal(d: Dictionary) -> void:
	var home: Vector2 = d["home"]
	var from := Vector2((d["pos"] as Vector3).x, (d["pos"] as Vector3).z)
	d["look"] = null
	d["good"] = true
	if d["green"]:
		d["feed_h"] = 0.1 * float(d["sc"])
		if _seabed and _seabed.ready_for_meadows():
			for i in 80:
				var p := home + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * 55.0)
				# (grass, and no coral within reach: it lies on the bottom to graze)
				if _seabed.meadow(p) > 0.6 and p.distance_to(from) > 6.0 and _coral(p, 0.8) < -90.0 and _clear(from, p):
					d["goal"] = p
					return
	else:
		var spots: Array = _seabed.forage_spots if _seabed else []
		for i in mini(spots.size(), 60):
			var s: Array = spots[_rng.randi() % spots.size()]
			var c: Vector2 = s[0]
			if c.distance_to(home) > 65.0 or c.distance_to(from) < 5.0:
				continue
			var out := Vector2.from_angle(_rng.randf() * TAU)
			var p := c + out * (float(s[1]) + 0.5 * float(d["sc"]))
			# (its place is beside the coral, its nose toward it and clear of all the coral
			# reaches over: a little further out where the coral is wider than its foot)
			var tries := 0
			while tries < 15 and _coral(p - out * (0.5 * float(d["sc"]))) > -90.0:
				p += out * 0.1
				tries += 1
			if tries < 15 and _coral(p) < -90.0 and _depth(p) > 1.9 and _clear(from, p):
				d["goal"] = p
				d["look"] = c
				d["feed_h"] = clampf(float(s[2]) * 0.6, 0.4, 0.6)
				return
		d["feed_h"] = 0.4
	# (nothing found yet, the sea floor is still being built: somewhere in the lagoon)
	d["good"] = false
	for i in 30:
		var p := _water_near(home, 45.0, 2.4, 6.0)
		if _clear(from, p):
			d["goal"] = p
			return
	d["goal"] = from


func _process(delta: float) -> void:
	if _player == null:
		return
	delta = minf(delta, 0.1)
	position.y = float(_ls.sea)
	if _daycycle == null:
		_daycycle = get_node_or_null("../../DayCycle")
	asleep = _daycycle != null and float(_daycycle.get("night")) > 0.6
	var pp := _player.global_position - Vector3(0, float(_ls.sea), 0)
	for d: Dictionary in turtles:
		var pos: Vector3 = d["pos"]
		if Vector2(pos.x - pp.x, pos.z - pp.z).length() > 260.0:
			continue       # far out of sight: it waits
		_update(d, delta, pp)
		_place(d, delta)


func _update(d: Dictionary, delta: float, pp: Vector3) -> void:
	var pos: Vector3 = d["pos"]
	var sc: float = d["sc"]
	var state: String = d["state"]
	d["t"] += delta
	# (asleep on the bottom a turtle's breath lasts three times as long)
	d["breath"] -= delta * (0.3 if asleep and state == "feed" else 1.0)
	var at := Vector2(pos.x, pos.z)
	var g: float = _ground(pos.x, pos.z)
	var surface := _wave(pos.x, pos.z)
	var goal: Vector2 = d["goal"]
	var want_yaw: float = d["yaw"]
	var to := goal - at
	if to.length() > 0.3:
		want_yaw = atan2(-to.x, -to.y)
	var want_speed := 0.0
	var want_y := pos.y
	var nose := 0.0             # attitude on top of the climb: nose down when feeding
	var stroke := 1.0
	var turn_rate := 0.7
	var vmax := 0.3
	var head := Vector2.ZERO    # the head's pitch and yaw against the body
	# somebody within arm's length: it moves off, without haste
	var away := Vector2(pos.x - pp.x, pos.z - pp.z)
	if state != "flee" and away.length() < 2.3 and absf(pos.y - pp.y) < 3.5:
		state = "flee"
		d["t"] = 0.0
	match state:
		"cruise":
			want_speed = 0.5 if d["green"] else 0.45
			want_y = g + 1.5
			# a few beats, then a glide
			d["glide"] -= delta
			if d["glide"] < -2.4:
				d["glide"] = _rng.randf_range(3.5, 7.0)
			if d["glide"] < 0.0:
				stroke = 0.12
				want_speed *= 0.8
			if d["breath"] <= 0.0:
				state = "rise"
			elif not d["good"] and d["t"] > 4.0:
				# (it set out before the sea floor was built: now it knows where the food is)
				_new_goal(d)
				d["t"] = 0.0
			elif to.length() < 1.0:
				state = "settle"
		"settle":
			want_speed = 0.14 if to.length() > 0.25 else 0.0
			want_y = g + float(d["feed_h"])
			stroke = 0.4
			vmax = 0.16
			if d["look"] != null and to.length() < 0.5:
				var lk: Vector2 = (d["look"] as Vector2) - at
				want_yaw = atan2(-lk.x, -lk.y)
			if absf(pos.y - want_y) < 0.06 or d["t"] > 14.0:
				state = "feed"
				d["feed_len"] = _rng.randf_range(35.0, 75.0)
				d["next_shuffle"] = _rng.randf_range(7.0, 13.0)
		"feed":
			want_y = g + float(d["feed_h"])
			stroke = 0.0
			turn_rate = 0.35
			if asleep:
				# the night: on the bottom, the head low, nothing moving
				want_y = g + 0.1 * sc
				nose = -0.04
				head.x = -0.12
				want_yaw = d["yaw"]
			elif d["green"]:
				# lying on the bottom, cropping the grass: reach down, tear, lift the head to
				# swallow; every so often a pull of the flippers on to fresh grass
				nose = -0.1
				d["bite"] += delta
				var cyc := fposmod(float(d["bite"]), 2.6) / 2.6
				head.x = -0.2 - 0.4 * smoothstep(0.0, 0.3, cyc) * (1.0 - smoothstep(0.55, 0.8, cyc))
				head.y = 0.22 * sin(cyc * TAU * 4.0) * smoothstep(0.3, 0.4, cyc) * (1.0 - smoothstep(0.5, 0.6, cyc))
				d["next_shuffle"] -= delta
				if d["next_shuffle"] <= 0.0:
					d["next_shuffle"] = _rng.randf_range(8.0, 15.0)
					d["shuffle"] = _rng.randf_range(2.0, 3.5)
					d["yaw"] += _rng.randf_range(-0.5, 0.5) * 0.0
					want_yaw = float(d["yaw"]) + _rng.randf_range(-0.7, 0.7)
					d["goal"] = at + Vector2(-sin(want_yaw), -cos(want_yaw)) * 3.0
				if d["shuffle"] > 0.0:
					d["shuffle"] -= delta
					want_speed = 0.16
					stroke = 0.45
					head.x = -0.1
				else:
					want_yaw = d["yaw"]
			else:
				# hanging nose down at a coral, picking at it
				nose = -0.5
				d["bite"] += delta
				var cyc := fposmod(float(d["bite"]), 3.4) / 3.4
				head.x = -0.15 - 0.3 * smoothstep(0.0, 0.25, cyc) * (1.0 - smoothstep(0.5, 0.7, cyc))
				head.y = 0.3 * sin(cyc * TAU * 3.0) * smoothstep(0.25, 0.35, cyc) * (1.0 - smoothstep(0.45, 0.55, cyc))
				stroke = 0.15
				if d["look"] != null:
					var lk: Vector2 = (d["look"] as Vector2) - at
					want_yaw = atan2(-lk.x, -lk.y)
			if d["breath"] <= 0.0:
				state = "rise"
			elif d["t"] > float(d["feed_len"]) and not asleep:
				_new_goal(d)
				state = "cruise"
		"rise":
			# up to breathe: straight on and up
			want_speed = 0.42
			want_yaw = d["yaw"]
			want_y = surface - 0.3 * sc
			vmax = 0.34
			head.x = 0.15
			if pos.y > surface - 0.4 * sc:
				state = "breathe"
				d["wait"] = _rng.randf_range(3.0, 6.0)
		"breathe":
			# the head out, a breath or two
			want_speed = 0.1
			want_yaw = d["yaw"]
			want_y = surface - 0.3 * sc
			vmax = 0.6
			nose = 0.3
			stroke = 0.25
			head.x = 0.42 + 0.1 * sin(float(d["t"]) * 2.3)
			if d["t"] > float(d["wait"]):
				state = "dive"
				d["breath"] = _rng.randf_range(70.0, 130.0)
				if _rng.randf() < 0.4 or at.distance_to(goal) > 25.0:
					_new_goal(d)
		"dive":
			want_speed = 0.5
			want_y = g + 1.5
			vmax = 0.36
			if pos.y < g + 1.9 or d["t"] > 30.0:
				state = "cruise"
		"flee":
			want_speed = 1.05
			stroke = 1.25
			turn_rate = 1.4
			if away.length() > 0.1:
				want_yaw = atan2(-away.x, -away.y)
			want_y = clampf(pos.y, g + 0.8, surface - 0.8)
			if d["t"] > 4.5:
				_new_goal(d)
				state = "cruise"
	if state != d["state"]:
		d["state"] = state
		d["t"] = 0.0
		if state == "breathe":
			_breathe_sound(pos)
	# corals: on its way it climbs over them in good time (their height falling away over
	# 3 m all around, looked for where it is and a little ahead); at rest it may lie beside
	# one but not in it
	var fwd := Vector2(-sin(float(d["yaw"])), -cos(float(d["yaw"])))
	if state == "cruise" or state == "dive" or state == "flee":
		want_y = maxf(want_y, maxf(_top(at, 3.0), _top(at + fwd * 1.2, 3.0)) + OVER + 0.1 * sc)
	else:
		want_y = maxf(want_y, _top(at, 0.3) + 0.08 * sc)
	# never into the surface from below except to breathe, never into the ground
	if state != "rise" and state != "breathe":
		want_y = minf(want_y, surface - 0.45)
	# (nor up into the anchored boat: under its hull, and coming to it, it keeps below the
	# keel, swims on, and breathes beyond)
	if avoid_corals and _seabed and _seabed.has_method("boat_over") \
			and (_seabed.boat_over(pos.x, pos.z, 0.8) or _seabed.boat_over(pos.x + fwd.x * 1.2, pos.z + fwd.y * 1.2, 0.8)):
		want_y = minf(want_y, surface - 1.05)
	want_y = maxf(want_y, g + 0.08 * sc)
	# turn, banking a little
	var diff := wrapf(want_yaw - float(d["yaw"]), -PI, PI)
	var step_yaw := clampf(diff, -turn_rate * delta, turn_rate * delta)
	# hard rule: not into a coral, neither swimming nor turning. What counts is its middle
	# and its nose (lower when it noses down), against what stands there.
	var under := pos.y - 0.1 * sc
	var nose_under := under + sin(minf(float(d["pitch"]), 0.0)) * 0.5 * sc
	var wall := -99.0
	if avoid_corals and step_yaw != 0.0 and float(d.get("held", 0.0)) < 20.0:
		var ny := float(d["yaw"]) + step_yaw
		var beside := _coral(at + Vector2(-sin(ny), -cos(ny)) * (0.5 * sc))
		if beside > nose_under and _coral(at + fwd * (0.5 * sc)) <= nose_under:
			# (the turn would put its nose into a coral beside it: it keeps its heading, and
			# rises if it can; after 20 s of getting nowhere it may turn all the same)
			step_yaw = 0.0
			wall = beside
	d["yaw"] += step_yaw
	d["turn"] = lerpf(d["turn"], step_yaw / maxf(delta, 0.001), 1.0 - exp(-3.0 * delta))
	d["speed"] = lerpf(d["speed"], want_speed, 1.0 - exp(-(1.6 if state == "flee" else 0.7) * delta))
	var speed: float = d["speed"]
	var dir := Vector2(-sin(float(d["yaw"])), -cos(float(d["yaw"])))
	# hard rule: only over water deep enough, and not out over the reef slope
	var q := at + dir * maxf(speed * delta, 0.6)
	var dq := _depth(q)
	# (... or, if the tide has fallen and left it in water too shallow, wherever it gets deeper)
	var deep_enough := (dq > MIN_DEPTH and dq < MAX_DEPTH) or (dq < MAX_DEPTH and dq > _depth(at))
	var front := -99.0
	var c_nose := -99.0
	var c_mid := -99.0
	if deep_enough and avoid_corals:
		var step := dir * maxf(speed * delta, 0.02)
		c_nose = _coral(at + step + dir * (0.5 * sc))
		c_mid = _coral(at + step)
		if c_nose > nose_under or c_mid > under:
			front = maxf(c_nose, c_mid)
	if deep_enough and front < -90.0:
		at += dir * speed * delta
		d["held"] = 0.0
	elif deep_enough:
		# a coral ahead and it is not above it yet: it waits and rises; where the coral comes
		# too near the surface to pass over, it turns to somewhere else
		d["speed"] = speed * exp(-5.0 * delta)
		wall = maxf(wall, front)
		if (state == "settle" or state == "feed") and c_nose > nose_under:
			# at its coral, nosing down to pick at it: the beak comes to the coral, not into it
			# (it backs off as its nose goes down, if there is room behind)
			var back := at - dir * (0.12 * delta)
			if _coral(back - dir * (0.45 * sc)) <= under and _depth(back) > MIN_DEPTH:
				at = back
		elif want_speed > 0.05 and state != "settle" and state != "feed":
			d["held"] = float(d.get("held", 0.0)) + delta
			d["held_all"] = float(d.get("held_all", 0.0)) + delta
			d["held_max"] = maxf(float(d.get("held_max", 0.0)), float(d["held"]))
		if front + OVER + 0.1 * sc < surface - 0.45:
			pass
		elif state == "cruise" or state == "dive" or state == "flee":
			d["regoal"] = float(d.get("regoal", 0.0)) - delta
			if float(d["regoal"]) <= 0.0:
				d["regoal"] = 2.5
				_new_goal(d)
				if state == "flee":
					d["state"] = "cruise"
					d["t"] = 0.0
		elif state == "rise" or state == "breathe":
			d["yaw"] += 0.8 * delta
	else:
		d["speed"] = speed * 0.5
		if state == "cruise" or state == "dive" or state == "flee":
			_new_goal(d)
			if state == "flee":
				d["state"] = "cruise"
				d["t"] = 0.0
		elif state == "rise" or state == "breathe":
			d["yaw"] += 0.8 * delta
	if wall > -90.0 and wall + OVER + 0.1 * sc < surface - 0.45 and d["state"] != "settle" and d["state"] != "feed":
		want_y = maxf(want_y, wall + OVER + 0.1 * sc)       # up and over what is in the way
	pos.x = at.x
	pos.z = at.y
	d["vy"] = lerpf(d["vy"], clampf((want_y - pos.y) * 1.4, -vmax, vmax), 1.0 - exp(-2.5 * delta))
	pos.y += float(d["vy"]) * delta
	pos.y = maxf(pos.y, _top(at, 0.3) + (0.07 if _coral(at) < -90.0 else 0.12) * sc)
	# (nor does it sink with its nose into a coral it hangs over: it stays above it, and at
	# rest backs off it, above, until its nose can go down beside it)
	var c_below := _coral(at + dir * (0.5 * sc))
	if c_below > -90.0:
		pos.y = maxf(pos.y, c_below + 0.11 * sc - sin(minf(float(d["pitch"]), 0.0)) * 0.5 * sc)
	d["pos"] = pos
	# the attitude follows the way it swims; close to the bottom the nose cannot go down further
	# than there is water under it
	var climb := atan2(float(d["vy"]), maxf(speed, 0.4))
	var room := pos.y - _ground(pos.x, pos.z)
	var low := -minf(0.7, atan(maxf(room - 0.06 * sc, 0.0) / (0.62 * sc)))
	d["pitch"] = lerpf(d["pitch"], clampf(climb + nose, low, 0.6), 1.0 - exp(-1.8 * delta))
	d["roll"] = lerpf(d["roll"], clampf(-float(d["turn"]) * 0.35, -0.3, 0.3), 1.0 - exp(-2.0 * delta))
	d["stroke"] = lerpf(d["stroke"], stroke, 1.0 - exp(-1.5 * delta))
	d["phase"] += delta * TAU * 0.42 * (0.55 + 0.9 * speed) * (0.35 + 0.65 * minf(float(d["stroke"]), 1.0))
	d["head"] = (d["head"] as Vector2).lerp(head, 1.0 - exp(-6.0 * delta))


## Sets the nodes: the body, the flippers' beat, the head.
func _place(d: Dictionary, _delta: float) -> void:
	var node: Node3D = d["node"]
	var sc: float = d["sc"]
	var st: float = d["stroke"]
	var ph: float = d["phase"]
	var pos: Vector3 = d["pos"]
	# the body rises a little on every down-stroke and noses up and down with the beat
	var b := Basis(Vector3.UP, d["yaw"]) * Basis(Vector3.RIGHT, float(d["pitch"]) + 0.03 * st * cos(ph)) * Basis(Vector3.FORWARD, d["roll"])
	node.transform = Transform3D(b.scaled(Vector3.ONE * sc), pos + Vector3(0, 0.022 * st * sin(ph - 0.7) * sc, 0))
	# front flippers: up and forward, then down and back with the leading edge turned down;
	# held out and swept back a little in a glide; propped on the bottom when grazing
	var rest := 1.0 - clampf(st, 0.0, 1.0)
	var flap := 0.62 * st * sin(ph) - 0.1 * rest
	var sweep := 0.3 * st * cos(ph) - 0.3 * rest
	var twist := 0.42 * st * cos(ph)
	if d["state"] == "feed" and d["green"]:
		flap = -0.22
		sweep = -0.15
	(node.get_node("FlipFR") as Node3D).basis = Basis(Vector3.UP, sweep) * Basis(Vector3.BACK, flap) * Basis(Vector3.RIGHT, twist)
	(node.get_node("FlipFL") as Node3D).basis = Basis(Vector3.UP, -sweep) * Basis(Vector3.BACK, -flap) * Basis(Vector3.RIGHT, twist)
	# hind flippers: trailing, steering in the turns
	var rudder := clampf(float(d["turn"]) * 0.5, -0.4, 0.4)
	var paddle := 0.12 * st * sin(ph + 1.6)
	(node.get_node("FlipRR") as Node3D).basis = Basis(Vector3.UP, rudder - 0.1) * Basis(Vector3.BACK, paddle - 0.05)
	(node.get_node("FlipRL") as Node3D).basis = Basis(Vector3.UP, rudder + 0.1) * Basis(Vector3.BACK, -paddle + 0.05)
	var hd: Vector2 = d["head"]
	(node.get_node("Head") as Node3D).basis = Basis(Vector3.RIGHT, hd.x - 0.5 * minf(float(d["pitch"]), 0.0) * 0.0) * Basis(Vector3.UP, hd.y)


## For the tests: runs one turtle for `seconds` of its life in steps of 50 ms with nobody near,
## and reports where it has been.
func soak(index: int, seconds: float) -> Dictionary:
	var d: Dictionary = turtles[index]
	var states := {}
	var shallowest := 99.0
	var deepest := 0.0
	var lowest := 99.0        # least water between the turtle and the ground
	var breaths := 0
	var far := 0.0
	var last := ""
	var in_coral := 0.0       # seconds with its middle or its nose inside a coral
	var deepest_in := 0.0     # ... and how far below the coral's top at the worst
	var moved := 0.0
	var corals_on := avoid_corals
	var cases: Array = []
	var last_case := -999
	d["held_all"] = 0.0
	d["held_max"] = 0.0
	var n := int(seconds / 0.05)
	for i in n:
		var before: Vector3 = d["pos"]
		_update(d, 0.05, Vector3(1e5, 0, 0))
		var pos: Vector3 = d["pos"]
		var st: String = d["state"]
		moved += Vector2(pos.x - before.x, pos.z - before.z).length()
		# (against the corals themselves, whether it minds them or not)
		avoid_corals = true
		var fw := Vector2(-sin(float(d["yaw"])), -cos(float(d["yaw"])))
		var sc: float = d["sc"]
		var under := pos.y - 0.1 * sc
		var in_mid := _coral(Vector2(pos.x, pos.z), 0.01) - under
		var in_nose := _coral(Vector2(pos.x, pos.z) + fw * (0.45 * sc), 0.01) - (under + sin(minf(float(d["pitch"]), 0.0)) * 0.45 * sc)
		var inside := maxf(in_mid, in_nose)
		avoid_corals = corals_on
		if inside > 0.02 and inside < 50.0 and cases.size() < 6 and (cases.is_empty() or i - last_case > 200):
			cases.append([st, pos.snappedf(0.1), "nose" if in_nose > in_mid else "middle", snappedf(inside, 0.01), "held %.0f s" % float(d.get("held", 0.0))])
			last_case = i
		if inside > 0.02:
			in_coral += 0.05
			deepest_in = maxf(deepest_in, inside)
		states[st] = float(states.get(st, 0.0)) + 0.05
		if st == "breathe" and last != "breathe":
			breaths += 1
		last = st
		var dep := _depth(Vector2(pos.x, pos.z))
		shallowest = minf(shallowest, dep)
		deepest = maxf(deepest, dep)
		lowest = minf(lowest, pos.y + dep)
		far = maxf(far, Vector2(pos.x, pos.z).distance_to(d["home"]))
		if is_nan(pos.x) or is_nan(pos.y):
			return {"nan at": i}
	_place(d, 0.0)
	return {"seconds in each state": states, "breaths": breaths, "shallowest water": shallowest, "deepest water": deepest,
		"least height above the ground": lowest, "furthest from home": far, "meters swum": moved,
		"seconds inside a coral": in_coral, "deepest inside a coral": deepest_in,
		"seconds held up by a coral": d["held_all"], "longest hold-up": d["held_max"], "cases": cases}


## For the tests: turtle `index` is put under the middle of the anchored boat, out of
## breath, and left to itself for a minute: how high did it come while under the hull, and
## did it get its breath beyond it? `mind`: false is how it was (it came up into the boat).
func boat_test(index := 0, mind := true) -> Dictionary:
	var d: Dictionary = turtles[index]
	var c: Vector2 = _seabed.get("_boat_c")
	var keep := avoid_corals
	avoid_corals = mind
	d["pos"] = Vector3(c.x, -2.0, c.y)
	d["state"] = "cruise"
	d["breath"] = 0.0
	d["speed"] = 0.4
	var highest := -99.0
	var breathed_at := Vector3.ZERO
	var breathed_t := -1.0
	for i in 1200:
		_update(d, 0.05, Vector3(1e5, 0, 0))
		var pos: Vector3 = d["pos"]
		if _seabed.boat_at(pos.x, pos.z):
			highest = maxf(highest, pos.y)
		if d["state"] == "breathe" and breathed_t < 0.0:
			breathed_t = i * 0.05
			breathed_at = pos
	avoid_corals = keep
	return {"highest under the hull (sea = 0)": snappedf(highest, 0.01), "first breath after (s)": breathed_t, "at": breathed_at.snappedf(0.1),
		"meters from the boat's middle": snappedf(Vector2(breathed_at.x, breathed_at.z).distance_to(c), 0.1)}


# ------------------------------------------------------------------ a breath at the surface
var _breath_voice: AudioStreamPlayer3D
var _breath_sounds: Array[AudioStream] = []
var breaths_heard := 0          # (for the tests)


## The head breaks the surface: a short blow and a breath in, heard through the air near by.
func _breathe_sound(at: Vector3) -> void:
	if _breath_voice == null:
		for i in 6:
			var path := "res://assets/audio/turtle_breath_%d.wav" % i
			if ResourceLoader.exists(path):
				_breath_sounds.append(load(path))
		_breath_voice = AudioStreamPlayer3D.new()
		_breath_voice.bus = "Ambient"
		_breath_voice.unit_size = 4.0
		_breath_voice.max_distance = 32.0
		_breath_voice.volume_db = -9.0
		add_child(_breath_voice)
	if _breath_sounds.is_empty() or _breath_voice.playing:
		return
	_breath_voice.global_position = at + Vector3(0, 0.3, 0)
	_breath_voice.stream = _breath_sounds[randi() % _breath_sounds.size()]
	# (a smaller animal in the water than the one on the beach: shorter and higher)
	_breath_voice.pitch_scale = randf_range(1.15, 1.3)
	_breath_voice.play()
	breaths_heard += 1
