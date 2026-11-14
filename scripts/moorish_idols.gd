extends Node3D
## Moorish idols (Zanclus cornutus): a few, as one meets them on any reef of the Indian
## Ocean: not in schools but in twos and threes that stay together for life. Each little
## group has a coral head for a home and keeps within a few meters of it. They travel in a
## loose file, the first choosing the way over the corals and the others following where it
## went, sculling with the breast fins, the long white streamer of the back fin trailing
## behind. Every so often the first one stops, tips head down and picks at the reef (they
## eat sponges), and those behind do the same where they are. They let a swimmer come to a
## couple of meters and then move off together, without haste. At night they rest low
## beside their coral.
## Nobody passes through a coral, a rock or another of the group: each one rises over
## whatever stands before it (Seabed.top_at()), and they give each other room.
## (The node is created by island_life.gd; the fish are set down once the sea floor and the
## reef's other residents have their places.) For the tests: report(), soak(), marker().

const SeaModels := preload("res://scripts/sea_models.gd")
# about where each group lives, and how many it is (the first is the easiest to find: straight
# out from the start beach, forty meters; the second in the coral garden; the third to the north)
const HOMES := [[Vector2(38.0, 12.0), 2], [Vector2(72.0, -8.0), 3], [Vector2(44.0, 62.0), 2]]
const RANGE := 8.0             # how far from home they go
const KEEP := 2.3              # a swimmer nearer than this: they move off
const GAP := 0.7               # from one to the next in the file
const MIN := 0.36              # they come no nearer each other than this (middle to middle)
const ROOM := 0.64             # ... and begin to make room at this

var groups: Array = []
var placed := false
var mates_apart := true        # (for the tests: false is how it would be without the rule)
var _ls: Node
var _player: Node3D
var _seabed: Node
var _reef: Node
var _daycycle: Node
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial
var _everybody := false        # (the soak test: nobody is left out for being far away)


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed
	_reef = get_node_or_null("../ReefLife")
	_daycycle = get_node_or_null("../../DayCycle")
	_rng.randomize()


func _process(delta: float) -> void:
	if _player == null or _seabed == null:
		return
	if not placed:
		if _seabed.done() and (_reef == null or bool(_reef.get("_placed"))):
			_place()
		return
	var eye := _player.global_position + Vector3(0, 0.95, 0)
	var night: float = _daycycle.night if _daycycle and "night" in _daycycle else 0.0
	delta = minf(delta, 0.1)
	for g: Dictionary in groups:
		_update_group(g, delta, eye, night)


# ------------------------------------------------------------------ places

## The top of whatever stands at p (a coral, a rock, the floor).
func _top(p: Vector3, skirt := 1.0) -> float:
	return float(_seabed.top_at(Vector2(p.x, p.z), skirt))


## The top of what is solid at a place, from the seabed's map of corals and rocks (half a
## meter a cell, a coral counted 0.3 m wider than it is) and the floor: cheap.
func _solid(x: float, z: float) -> float:
	return maxf(float(_seabed.coral_top(x, z)), float(_ls.ground(x, z)))


## The reef's residents that have a place of their own: [where, how far to keep off].
func _others() -> Array:
	var out: Array = []
	if _reef == null:
		return out
	var gr: Dictionary = _reef.get("grouper")
	if not gr.is_empty():
		out.append([Vector2((gr["home"] as Vector3).x, (gr["home"] as Vector3).z), 5.5])
	for c: Dictionary in _reef.get("colonies"):
		out.append([Vector2((c["pos"] as Vector3).x, (c["pos"] as Vector3).z), 5.5])
	return out


## May they swim at q: water enough over whatever stands there (at low water the tops of
## the corals come near the surface), within their range, not under the boat, not over the
## garden eels (they would all go down) nor into the grouper's patch.
func _ok(g: Dictionary, q: Vector2) -> bool:
	var y: float = _ls.ground(q.x, q.y)
	if y > -1.9 or y < -8.0:
		return false
	if q.distance_to(g["home"]) > RANGE + 1.0:
		return false
	for o: Array in g["others"]:
		if q.distance_to(o[0]) < float(o[1]):
			return false
	if _seabed.has_method("boat_over") and _seabed.boat_over(q.x, q.y, 2.0):
		return false
	return float(_seabed.top_at(q, 1.0)) + 0.5 < float(_ls.sea) - 0.55


func _place() -> void:
	placed = true
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/sea_creature.gdshader")
	_mat.set_shader_parameter("species", 9)
	var mesh: ArrayMesh = SeaModels.moorish_idol()
	var keep: Array = _others()
	if _reef:
		for t: Dictionary in _reef.get("triggers"):
			keep.append([t["home"], 5.5])
	var taken: Array = []
	for spec: Array in HOMES:
		# a big coral near the place wanted, in three to six meters of water, well away from
		# the other residents and from the other groups
		var want: Vector2 = spec[0]
		var best := Vector2.ZERO
		var best_d := 1e9
		for c: Array in _seabed.big_corals:
			var q: Vector2 = c[0]
			var gy := float(c[3]) if c.size() > 3 else float(_ls.ground(q.x, q.y))
			if gy > -3.0 or gy < -6.2 or q.distance_to(want) > best_d:
				continue
			var apart := true
			for o: Array in keep:
				if q.distance_to(o[0]) < float(o[1]) + 7.0:
					apart = false
			for o: Vector2 in taken:
				if q.distance_to(o) < 22.0:
					apart = false
			if apart:
				best_d = q.distance_to(want)
				best = q
		if best_d > 30.0:
			continue
		taken.append(best)
		# the corals of their patch: [where, how wide]
		var near: Array = []
		for c: Array in _seabed.big_corals:
			if (c[0] as Vector2).distance_to(best) < RANGE:
				near.append([c[0], float(c[1])])
		var g := {"home": best, "others": _others(), "fish": [], "state": "cruise", "t": _rng.randf_range(4.0, 10.0), "look": 0.0, "target": Vector3(best.x, 0, best.y),
			"h": 0.7, "corals": near, "coral": -1.0, "trail": [], "nearest": 1e9, "fastest": 0.0, "feeds": 0, "name": "Idols%d" % groups.size()}
		var yaw := _rng.randf() * TAU
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		for i in int(spec[1]):
			var mi := MeshInstance3D.new()
			mi.name = "MoorishIdol%d_%d" % [groups.size(), i]
			mi.mesh = mesh
			mi.material_override = _mat
			mi.extra_cull_margin = 0.4
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var at := Vector3(best.x, 0, best.y) - fwd * (GAP * i)
			at.y = minf(_top(at) + 0.8, float(_ls.sea) - 0.6)
			var f := {"node": mi, "len": _rng.randf_range(0.27, 0.32), "pos": at, "yaw": yaw, "pitch": 0.0, "speed": 0.0, "phase": _rng.randf() * TAU, "bend": 0.0,
				"side": (0.0 if i == 0 else _rng.randf_range(0.07, 0.16) * (1.0 if i % 2 == 1 else -1.0)), "drop": 0.1 * i, "still": 0.0, "stood": 0.0, "way": 0.0}
			(g["fish"] as Array).append(f)
			_pose(f, 1.0)
		groups.append(g)
		_goal(g, null)


func _pose(f: Dictionary, amp: float) -> void:
	var mi: MeshInstance3D = f["node"]
	var b := Basis(Vector3.UP, float(f["yaw"])) * Basis(Vector3.RIGHT, float(f["pitch"]))
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * (float(f["len"]) / 3.6)), f["pos"])
	mi.set_instance_shader_parameter("phase", f["phase"])
	mi.set_instance_shader_parameter("amp", amp)
	mi.set_instance_shader_parameter("bend", f["bend"])


## Where to swim next: somewhere near home with water enough over it; with a swimmer too
## near (`from`), the such place furthest from them.
func _goal(g: Dictionary, from: Variant) -> void:
	var home: Vector2 = g["home"]
	var best := home
	var best_d := -1.0
	for k in 12:
		var a := _rng.randf() * TAU
		var q := home + Vector2(cos(a), sin(a)) * (sqrt(_rng.randf()) * RANGE)
		if not _ok(g, q):
			continue
		var d := _rng.randf() if from == null else q.distance_to(Vector2((from as Vector3).x, (from as Vector3).z))
		if d > best_d:
			best_d = d
			best = q
	g["target"] = Vector3(best.x, 0, best.y)
	g["h"] = _rng.randf_range(0.45, 1.1)
	g["coral"] = -1.0
	# mostly it is a coral they make for (they are fish of the reef, and it is there they
	# feed): up to it, to stop a little before it
	var corals: Array = g["corals"]
	if from == null and not corals.is_empty() and _rng.randf() < 0.8:
		for k in 6:
			var c: Array = corals[_rng.randi() % corals.size()]
			if _ok(g, c[0]):
				g["target"] = Vector3((c[0] as Vector2).x, 0, (c[0] as Vector2).y)
				g["coral"] = float(c[1])
				g["h"] = _rng.randf_range(0.35, 0.8)
				break


# ------------------------------------------------------------------ their day

func _update_group(g: Dictionary, delta: float, eye: Vector3, night: float) -> void:
	var fish: Array = g["fish"]
	var lead: Dictionary = fish[0]
	var lpos: Vector3 = lead["pos"]
	if not _everybody and lpos.distance_to(eye) > 60.0:
		return
	var d := 1e9
	for f: Dictionary in fish:
		d = minf(d, (f["pos"] as Vector3).distance_to(eye))
	g["nearest"] = minf(float(g["nearest"]), d)
	g["t"] = float(g["t"]) - delta
	g["look"] = float(g["look"]) - delta
	var asleep := night > 0.6
	var shy := d < KEEP and not asleep
	var want_speed := 0.0
	var want_h: float = g["h"]
	var nose_down := false
	var to := Vector3((g["target"] as Vector3).x - lpos.x, 0, (g["target"] as Vector3).z - lpos.z)
	match g["state"]:
		"cruise", "away":
			want_speed = 0.3 if g["state"] == "cruise" else 0.62
			if shy and (g["state"] == "cruise" or float(g["look"]) <= -1.2):
				# (and again every second and a half while they stay so near)
				g["state"] = "away"
				_goal(g, eye)
				g["t"] = 12.0
				g["look"] = 0.3
			elif to.length() < (0.4 if float(g["coral"]) < 0.0 else float(g["coral"]) + 0.5) or float(g["t"]) <= 0.0 \
					or (int(lead.get("why", 0)) == 2 and float(lead["still"]) > 0.8):
				# (there, or the time is up, or the coral it made for is in its way)
				var at_coral := float(g["coral"]) >= 0.0 and to.length() < float(g["coral"]) + 1.2
				if asleep:
					g["state"] = "rest"
				elif g["state"] == "cruise" and (at_coral or _rng.randf() < 0.15):
					# head down, and at the reef
					g["state"] = "feed"
					g["t"] = _rng.randf_range(5.0, 11.0)
					g["feeds"] = int(g["feeds"]) + 1
				else:
					g["state"] = "cruise"
					_goal(g, eye if shy else null)
					g["t"] = _rng.randf_range(12.0, 28.0)
			elif float(g["look"]) <= 0.0 and (not shy or g["state"] == "cruise"):
				g["look"] = 0.3
				# the way ahead: water enough over the corals there?
				var ahead := to.normalized()
				if not _ok(g, Vector2(lpos.x + ahead.x * 1.2, lpos.z + ahead.z * 1.2)):
					_goal(g, eye if shy else null)
		"feed":
			want_h = 0.26
			nose_down = true
			if shy or asleep or float(g["t"]) <= 0.0:
				g["state"] = "away" if shy else "cruise"
				_goal(g, eye if shy else null)
				g["t"] = _rng.randf_range(10.0, 24.0)
		"rest":
			want_h = 0.26
			if not asleep:
				g["state"] = "cruise"
				_goal(g, null)
				g["t"] = 20.0
	var slow := 0.3 if g["state"] == "rest" else 1.0
	# the first one: toward the place it has chosen
	_swim(g, lead, 0, lpos + to, want_speed, 1.5, want_h, -0.85 if nose_down else NAN, delta, slow)
	g["fastest"] = maxf(float(g["fastest"]), float(lead["speed"]))
	# its way, for the others to follow
	var trail: Array = g["trail"]
	lpos = lead["pos"]
	if trail.is_empty() or (trail[0] as Vector3).distance_to(lpos) > 0.08:
		trail.push_front(lpos)
		if trail.size() > 48:
			trail.pop_back()
	var lyaw: float = lead["yaw"]
	var lright := Vector3(cos(lyaw), 0, -sin(lyaw))
	for i in range(1, fish.size()):
		var f: Dictionary = fish[i]
		var pos: Vector3 = f["pos"]
		var slot := _behind(g, GAP * i)
		# (where the first one has turned back on its own way, "behind it along its way" is
		# before it, or on it: then straight behind it. Two stood face to face for 18 s
		# like that, each in the other's way.)
		var lfwd := Vector3(-sin(lyaw), 0, -cos(lyaw))
		var rel := slot - lpos
		if rel.dot(lfwd) > -0.1 or Vector2(rel.x, rel.z).length() < GAP * i * 0.7:
			slot = lpos - lfwd * (GAP * i)
		slot += lright * float(f["side"])
		var gap := Vector2(slot.x - pos.x, slot.z - pos.z).length()
		# (its pace goes by the first one's pace and by how far behind it is, never by its own)
		var pace := clampf(float(lead["speed"]) + (gap - 0.1) * 1.4, 0.0, 0.95) if gap > 0.14 else float(lead["speed"]) * 0.9
		var at_place := gap < 0.35
		# (while the first one feeds or rests, those behind do the same where they are,
		# if they are near: one that still made for its place behind a feeding one was
		# kept from it by the third for seven seconds)
		if (g["state"] == "feed" or g["state"] == "rest") and pos.distance_to(lpos) < 1.9:
			pace = 0.0
			at_place = true
		var h := want_h if (g["state"] == "feed" or g["state"] == "rest") else maxf(slot.y - float(f["drop"]) - _solid(pos.x, pos.z), 0.3)
		_swim(g, f, i, slot if (gap > 0.14 and pace > 0.0) else pos + Vector3(-sin(float(f["yaw"])), 0, -cos(float(f["yaw"]))), pace, 2.1, h, -0.75 if (nose_down and at_place) else NAN, delta, slow)


## The place `dist` back along the first one's way.
func _behind(g: Dictionary, dist: float) -> Vector3:
	var trail: Array = g["trail"]
	var lead: Dictionary = (g["fish"] as Array)[0]
	var at: Vector3 = lead["pos"]
	var left := dist
	for p: Vector3 in trail:
		var step := at.distance_to(p)
		if step >= left and step > 0.0001:
			return at.lerp(p, left / step)
		left -= step
		at = p
	# (the way is not that long yet: straight behind it)
	var yaw: float = lead["yaw"]
	return at + Vector3(sin(yaw), 0, cos(yaw)) * left


## One fish, one step: it turns toward `toward` and swims at `pace`, rises over whatever
## stands under it and just ahead, makes room for the others of its group, and takes no
## step into a coral or nearer than MIN to another.
func _swim(g: Dictionary, f: Dictionary, index: int, toward: Vector3, pace: float, turn: float, want_h: float, pitch_to: float, delta: float, slow: float) -> void:
	var pos: Vector3 = f["pos"]
	var yaw: float = f["yaw"]
	var to := Vector3(toward.x - pos.x, 0, toward.z - pos.z)
	# Held by a coral that stands too high to swim over (at low water there are such on the
	# reef's crest, and one of three stood boxed in for twelve seconds): the open way
	# nearest to where it wants to go, kept for a second and a half (a way chosen anew
	# every frame is no way: it dithers).
	f["detour_t"] = float(f.get("detour_t", 0.0)) - delta
	if float(f["detour_t"]) <= 0.0 and float(f["still"]) > 0.7 and int(f.get("why", 0)) == 2 and to.length() > 0.05:
		var want := atan2(-to.x, -to.z)
		var deck := float(_ls.sea) - 0.5 - 0.13 * float(f["len"]) / 0.27
		for k: float in [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4, PI]:
			var dir := Vector3(-sin(want + k), 0, -cos(want + k))
			if _solid(pos.x + dir.x * 0.35, pos.z + dir.z * 0.35) < deck and _solid(pos.x + dir.x * 0.75, pos.z + dir.z * 0.75) < deck:
				f["detour"] = want + k
				f["detour_t"] = 1.5
				f["still"] = 0.0
				break
	if float(f["detour_t"]) > 0.0:
		var dy: float = f["detour"]
		to = Vector3(-sin(dy), 0, -cos(dy))
		pace = maxf(pace, 0.25)
		turn = 3.0
	var dyaw := 0.0
	if pace > 0.0 and to.length() > 0.04:
		var diff := angle_difference(yaw, atan2(-to.x, -to.z))
		dyaw = clampf(diff, -turn * delta, turn * delta)
		yaw += dyaw
		pace *= 1.0 - clampf(absf(diff) / 1.4, 0.0, 0.8)
	f["yaw"] = yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var body := 0.13 * float(f["len"]) / 0.27          # (the fin below reaches this far under its middle)
	# What stands under it, half a meter ahead and under its snout: from the seabed's map
	# (cheap, and the very thing the hard rule in _free() asks, at the same places: a rule
	# and a look-ahead that ask differently can hold a fish for ever), and, every fourth
	# frame, the corals' own outlines with a skirt, which let it glide up before it is there.
	# (Asked with top_at() alone, a dozen times a fish a frame, seven idols cost 0.43 ms a
	# frame: more than all the fish schools.)
	var ahead := pos + fwd * 0.5
	var tip0 := _nose(f, pos, float(f["pitch"]))
	f["tick"] = int(f.get("tick", index)) + 1
	if int(f["tick"]) % 4 == 0 or not f.has("soft"):
		f["soft"] = maxf(_top(pos), _top(ahead))
	var here := _solid(pos.x, pos.z)
	var floor_y := maxf(maxf(float(f["soft"]), here), maxf(_solid(ahead.x, ahead.z), _solid(tip0.x, tip0.z)))
	var want_y := minf(floor_y + want_h + body, float(_ls.sea) - 0.5)
	if pos.y < here + body + 0.06:
		pace *= 0.25               # (up first, then on)
	f["speed"] = move_toward(float(f["speed"]), pace, delta * 0.6)
	var speed: float = f["speed"]
	var vy := clampf((want_y - pos.y) * 2.0, -0.3, 0.55)
	# room for the others: a push apart that grows as they come near
	var push := Vector3.ZERO
	var fish: Array = g["fish"]
	if mates_apart:
		for k in fish.size():
			if k == index:
				continue
			var off: Vector3 = pos - (fish[k]["pos"] as Vector3)
			var dd := off.length()
			if dd < ROOM:
				var dir := off / dd if dd > 0.001 else Vector3(cos(index * 2.4), 0.3, sin(index * 2.4))
				var k_near := (ROOM - dd) / ROOM
				push += dir * k_near * (0.25 if index == 0 else 0.5)
				# ... and around it, when it is in the way: a step to the side (two that meet
				# head on both step to their own right, and pass)
				if pace > 0.05 and to.length() > 0.05 and to.normalized().dot(dir) < -0.2:
					var round_it := Vector3(-dir.z, 0, dir.x)
					var lean := round_it.dot(to.normalized())
					if absf(lean) > 0.25:
						round_it *= signf(lean)
					push += round_it * k_near * 0.9
	var step := fwd * (speed * delta) + Vector3(0, vy * delta, 0)
	var moved := pos
	# (the way ahead; if that is shut, along whatever shuts it, to one side or the other: a
	# coral that stands up to the surface cannot be swum over, and one of three waited six
	# seconds before such a one; then only out of the others' way, or up)
	var slide := Vector3(fwd.z, 0, -fwd.x) * (maxf(speed, 0.12) * delta * (-1.0 if float(f["side"]) < 0.0 else 1.0))
	var rise := Vector3(0, vy * delta, 0)
	for attempt: Vector3 in [step + push * delta, slide + rise + push * delta, -slide + rise + push * delta, push * delta + rise, Vector3(0, maxf(vy, 0.0) * delta, 0)]:
		var np := pos + attempt
		var why := _free(g, index, pos, np, body)
		if why == 0:
			moved = np
			break
		f["why"] = why
	f["way"] = float(f["way"]) + moved.distance_to(pos)
	# (for the tests: how long it has stood while it meant to swim)
	if pace > 0.08 and moved.distance_to(pos) < 0.02 * delta:
		f["still"] = float(f["still"]) + delta
		if float(f["still"]) > float(f["stood"]):
			f["stood"] = f["still"]
			f["stood_how"] = [index, g["state"], ["", "the surface", "a coral", "another of them"][int(f.get("why", 0))], pos.snapped(Vector3.ONE * 0.01), want_y, vy]
	else:
		f["still"] = 0.0
	f["pos"] = moved
	var want_pitch := pitch_to
	if is_nan(pitch_to):
		want_pitch = clampf(atan2(vy, maxf(speed, 0.15)) * 0.7, -0.5, 0.5)
	var new_pitch := lerpf(float(f["pitch"]), want_pitch, 1.0 - exp(-2.4 * delta))
	# (it does not tip its snout into a coral either)
	var tip := _nose(f, moved, new_pitch)
	if new_pitch > float(f["pitch"]) or tip.y >= _solid(tip.x, tip.z) + 0.01:
		f["pitch"] = new_pitch
	f["phase"] = fmod(float(f["phase"]) + delta * (3.0 + speed * 22.0) * slow, TAU * 40.0)
	f["bend"] = lerpf(float(f["bend"]), clampf(-dyaw / maxf(delta, 0.001) * 0.22, -0.4, 0.4), 1.0 - exp(-4.0 * delta))
	_pose(f, 0.5 + speed * 1.6)


## May the fish go from `pos` to `np`: not down into a coral or the floor (unless it is
## on its way out of one), not up through the surface, and no nearer another of its group
## than MIN (unless the step takes them apart).
func _free(g: Dictionary, index: int, pos: Vector3, np: Vector3, body: float) -> int:
	if np.y > float(_ls.sea) - 0.42 and np.y > pos.y:
		return 1
	# (its snout is as long again as the half of it: that too goes into nothing)
	var f: Dictionary = (g["fish"] as Array)[index]
	var nose := _nose(f, np, float(f["pitch"]))
	if nose.y < _solid(nose.x, nose.z) and nose.y - np.y + pos.y >= _solid(nose.x - np.x + pos.x, nose.z - np.z + pos.z):
		return 2
	var top := _solid(np.x, np.z)
	if np.y - body < top and np.y - top < pos.y - _solid(pos.x, pos.z) + 0.0005:
		return 2
	if mates_apart:
		var fish: Array = g["fish"]
		for k in fish.size():
			if k == index:
				continue
			var m: Vector3 = fish[k]["pos"]
			var dn := np.distance_to(m)
			if dn < MIN and dn < pos.distance_to(m):
				return 3
	return 0


## The tip of the snout of a fish at `pos`, pitched so.
func _nose(f: Dictionary, pos: Vector3, pitch: float) -> Vector3:
	var yaw: float = f["yaw"]
	var l: float = f["len"]
	return pos + Vector3(-sin(yaw), 0, -cos(yaw)) * (0.5 * l * cos(pitch)) + Vector3(0, 0.5 * l * sin(pitch) - 0.083 * l * cos(pitch), 0)


# ------------------------------------------------------------------ for the tests

## A node that stays with the first fish of group i (for the driver's `chase`).
func marker(i := 0) -> Node3D:
	if i >= groups.size():
		return null
	return ((groups[i]["fish"] as Array)[0] as Dictionary)["node"]


func report() -> Array:
	var out: Array = []
	for g: Dictionary in groups:
		var lead: Dictionary = (g["fish"] as Array)[0]
		var p: Vector3 = lead["pos"]
		out.append({"home": g["home"], "floor at home": _ls.ground((g["home"] as Vector2).x, (g["home"] as Vector2).y), "fish": (g["fish"] as Array).size(), "at": p,
			"state": g["state"], "fed": g["feeds"], "nearest a swimmer has been (m)": g["nearest"], "fastest (m/s)": g["fastest"]})
	return out


## Their lives in a moment. `swimmer`: 0 nobody, 1 somebody circles three meters from each
## group's home at their depth, 2 somebody hangs right at their home (in their way).
func soak(seconds := 1800.0, swimmer := 0) -> Dictionary:
	_everybody = true
	var dt := 0.05
	var samples := 0
	var in_coral := 0
	var nose_in := 0
	var too_high := 0
	var astray := 0
	var touching := 0.0
	var closest := 1e9
	var lagging := 0
	var way := 0.0
	var stood := 0.0
	var how: Array = []
	var states := {}
	for g: Dictionary in groups:
		g["nearest"] = 1e9
		g["fastest"] = 0.0
		var fish: Array = g["fish"]
		for f: Dictionary in fish:
			f["way"] = 0.0
			f["stood"] = 0.0
			f["still"] = 0.0
		var home: Vector2 = g["home"]
		for s in int(seconds / dt):
			var eye := Vector3(1e5, 0, 0)
			if swimmer == 1:
				eye = Vector3(home.x + cos(s * dt * 0.03) * 3.0, float(_ls.ground(home.x, home.y)) + 1.2, home.y + sin(s * dt * 0.03) * 3.0)
			elif swimmer == 2:
				eye = Vector3(home.x, float(_ls.ground(home.x, home.y)) + 1.2, home.y)
			_update_group(g, dt, eye, 0.0)
			if s % 10 == 0:
				samples += 1
				states[g["state"]] = int(states.get(g["state"], 0)) + 1
				for i in fish.size():
					var p: Vector3 = fish[i]["pos"]
					var body := 0.13 * float(fish[i]["len"]) / 0.27
					if p.y - body < float(_seabed.top_at(Vector2(p.x, p.z), 0.0)) - 0.01:
						in_coral += 1
					var tip := _nose(fish[i], p, float(fish[i]["pitch"]))
					if tip.y < float(_seabed.top_at(Vector2(tip.x, tip.z), 0.0)) - 0.01:
						nose_in += 1
					if p.y > float(_ls.sea) - 0.3:
						too_high += 1
					if Vector2(p.x, p.z).distance_to(home) > RANGE + 3.5:
						astray += 1
					if i > 0 and p.distance_to(fish[0]["pos"]) > 3.0:
						lagging += 1
					for k in range(i + 1, fish.size()):
						var dd := p.distance_to(fish[k]["pos"])
						closest = minf(closest, dd)
						if dd < 0.3:
							touching += dt * 10.0
		for f: Dictionary in fish:
			way += float(f["way"])
			if float(f["stood"]) > stood:
				stood = f["stood"]
				how = f.get("stood_how", [])
	_everybody = false
	return {"samples": samples, "states": states, "swum, all together (m)": way, "longest standstill while meaning to swim (s)": stood, "who, in what state, kept by what, where": how,
		"samples in a coral or the floor": in_coral, "samples with the snout in one": nose_in, "samples at the surface": too_high, "samples far from home": astray,
		"samples of one more than 3 m behind the first": lagging, "seconds two were nearer than 0.3 m": touching, "nearest two have been (m)": closest, "now": report()}
