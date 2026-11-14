extends Node3D
## Two great barracudas (Sphyraena barracuda) at the reef's edge off the start beach, just
## outside the main reef where the floor falls away: over some six meters of water, which a
## swimmer can still reach. As the big ones do, they hang almost still in mid-water, a couple
## of meters under the surface, one a little behind and below the other, only the tail and
## the breast fins sculling; every minute or so they move on along the edge, slowly, to hang
## somewhere else. They let a swimmer come to four or five meters; nearer than that they
## slide off sideways, out over the deeper water where nobody can follow, without haste, and
## come back when the swimmer has gone. They do not follow anybody and show no teeth:
## nothing here is to frighten.
## Their way is a line along the edge (found at start-up from the sea floor); they move
## along it and to its sea side only, so there is nowhere they can get stuck.
## (The node is created by island_life.gd.) For the tests: report(), soak().

const SeaModels := preload("res://scripts/sea_models.gd")
const LINE_DEPTH := 6.5        # the floor under their line (a swimmer is stopped at 8 m)
const HOME_Z := -8.0           # the middle of their stretch of the edge ...
const REACH := 46.0            # ... and how far it runs to either side
const KEEP := 4.6              # a swimmer nearer than this: they move off
const SIZES := [1.25, 1.05]    # meters (the great barracuda is commonly a meter, at most two)

var fish: Array = []
var pair := {}
var _ls: Node
var _player: Node3D
var _seabed: Node
var _daycycle: Node
var _rng := RandomNumberGenerator.new()
var _line := PackedVector3Array()      # along the edge (y unused)
var _cum := PackedFloat32Array()
var _len := 0.0
var _time := 0.0


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed
	_daycycle = get_node_or_null("../../DayCycle")
	_rng.randomize()
	_find_line()
	if _line.size() < 8:
		return
	var mesh: ArrayMesh = SeaModels.barracuda()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea_creature.gdshader")
	mat.set_shader_parameter("species", 8)
	var s0 := _len * _rng.randf_range(0.35, 0.65)
	pair = {"state": "hang", "t": _rng.randf_range(15.0, 40.0), "goal": s0, "sense": 1.0 if _rng.randf() < 0.5 else -1.0, "depth": _rng.randf_range(1.7, 2.6)}
	for i in SIZES.size():
		var mi := MeshInstance3D.new()
		mi.name = "Barracuda%d" % i
		mi.mesh = mesh
		mi.material_override = mat
		mi.extra_cull_margin = 0.6
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var f := {"node": mi, "len": float(SIZES[i]), "slot": 3.4 * i, "lat0": 1.3 * i, "deep": 0.55 * i, "s": clampf(s0 - float(pair["sense"]) * 3.4 * i, 1.0, _len - 1.0),
			"lat": 1.3 * i, "y": float(_ls.sea) - float(pair["depth"]) - 0.55 * i, "face": float(pair["sense"]), "yaw": 0.0, "pitch": 0.0, "speed": 0.0, "phase": _rng.randf() * TAU,
			"bend": 0.0, "shy": 0.0, "sway": _rng.randf() * TAU, "nearest": 1e9, "fastest": 0.0, "pos": Vector3.ZERO}
		var fr := _at(float(f["s"]))
		var tan: Vector3 = (fr[1] as Vector3) * float(f["face"])
		f["yaw"] = atan2(-tan.x, -tan.z)
		fish.append(f)
	# (every node is put in its place at once: one that waits to be moved lies at the world's
	# origin, on the start beach)
	_step(0.0, Vector3(1e6, 0, 0))


## The line along the reef's edge: at every few meters of the coast the outermost place
## where the floor is LINE_DEPTH down, coming in from the deep water.
func _find_line() -> void:
	var z := HOME_Z - REACH
	while z <= HOME_Z + REACH:
		var x := 60.0
		while x < 220.0 and float(_ls.ground(x, z)) > -10.0:
			x += 0.5
		if x < 219.0:
			while x > 40.0 and float(_ls.ground(x, z)) < -LINE_DEPTH:
				x -= 0.25
			_line.append(Vector3(x + 0.6, 0, z))
		z += 3.0
	if _line.size() < 8:
		return
	# (smoothed: the edge is ragged; a point that smoothing has taken off the slope goes back)
	var raw := PackedVector3Array(_line)
	for k in 3:
		for i in range(1, _line.size() - 1):
			_line[i] = Vector3((_line[i - 1].x + _line[i].x * 2.0 + _line[i + 1].x) * 0.25, 0, _line[i].z)
	for i in _line.size():
		var g: float = _ls.ground(_line[i].x, _line[i].z)
		if g > -4.8 or g < -8.8:
			_line[i] = raw[i]
	_cum.append(0.0)
	for i in _line.size() - 1:
		_cum.append(_cum[i] + _line[i].distance_to(_line[i + 1]))
	_len = _cum[_cum.size() - 1]


## The place at s along the line, the way the line runs there, and the way out to sea.
func _at(s: float) -> Array:
	s = clampf(s, 0.0, _len - 0.01)
	var i := clampi(_cum.bsearch(s) - 1, 0, _line.size() - 2)
	var d := (_line[i + 1] - _line[i]).normalized()
	var p := _line[i].lerp(_line[i + 1], (s - _cum[i]) / maxf(_cum[i + 1] - _cum[i], 0.001))
	var out := Vector3(-d.z, 0, d.x)
	if float(_ls.ground(p.x + out.x * 3.0, p.z + out.z * 3.0)) > float(_ls.ground(p.x - out.x * 3.0, p.z - out.z * 3.0)):
		out = -out
	return [p, d, out]


## How far along the line the place nearest to p lies.
func _along(p: Vector3) -> float:
	var best := 0.0
	var best_d := 1e18
	for i in _line.size():
		var d := Vector2(_line[i].x - p.x, _line[i].z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = _cum[i]
	return best


## The top of whatever stands at p (coral, rock, the floor).
func _top(p: Vector3, skirt: float) -> float:
	if _seabed and _seabed.has_method("top_at"):
		return float(_seabed.top_at(Vector2(p.x, p.z), skirt))
	return float(_ls.ground(p.x, p.z))


func _process(delta: float) -> void:
	if fish.is_empty() or _player == null:
		return
	var eye := _player.global_position
	if eye.distance_to(fish[0]["pos"]) > 110.0:
		return          # far out of sight: they hang where they are
	_step(minf(delta, 0.1), eye)


func _step(delta: float, eye: Vector3) -> void:
	_time += delta
	var sea: float = _ls.sea
	var night: float = _daycycle.night if _daycycle and "night" in _daycycle else 0.0
	var lead: Dictionary = fish[0]
	# the pair's plan: hang, then on along the edge to another place, and hang again
	pair["t"] = float(pair["t"]) - delta
	if pair["state"] == "hang":
		if float(pair["t"]) <= 0.0:
			var way := 1.0 if _rng.randf() < 0.5 else -1.0
			# (back toward the middle of their stretch from near its ends)
			if float(lead["s"]) < _len * 0.25:
				way = 1.0
			elif float(lead["s"]) > _len * 0.75:
				way = -1.0
			pair["goal"] = clampf(float(lead["s"]) + way * _rng.randf_range(12.0, 34.0), 5.0, _len - 5.0)
			pair["sense"] = signf(float(pair["goal"]) - float(lead["s"]))
			pair["state"] = "move"
			pair["t"] = 110.0
			pair["depth"] = _rng.randf_range(1.6, 2.7)
	elif absf(float(lead["s"]) - float(pair["goal"])) < 0.6 or float(pair["t"]) <= 0.0:
		# (there, or kept from it for long enough by somebody in the way: here will do)
		pair["state"] = "hang"
		pair["goal"] = lead["s"]
		pair["t"] = _rng.randf_range(35.0, 80.0)
	var eye_s := _along(eye)
	for f: Dictionary in fish:
		var s: float = f["s"]
		var fr := _at(s)
		var tan: Vector3 = fr[1]
		var out: Vector3 = fr[2]
		var pos: Vector3 = (fr[0] as Vector3) + out * float(f["lat"])
		pos.y = f["y"]
		var dist := pos.distance_to(eye)
		f["nearest"] = minf(float(f["nearest"]), dist)
		# somebody near: it moves off, to the sea side and down a little, and stays off for
		# some seconds after they have gone
		if dist < KEEP:
			f["shy"] = 5.0
		elif float(f["shy"]) > 0.0 and dist > KEEP + 1.5:
			f["shy"] = float(f["shy"]) - delta
		var shy: bool = float(f["shy"]) > 0.0
		var want_s := float(pair["goal"]) - float(pair["sense"]) * float(f["slot"])
		# (never to a place within six meters of a swimmer along the edge: it stops short,
		# on the side it is on)
		if absf(want_s - eye_s) < 6.0 and Vector2(eye.x - pos.x, eye.z - pos.z).length() < 12.0:
			want_s = eye_s + (1.0 if s >= eye_s else -1.0) * 6.0
		want_s = clampf(want_s, 1.5, _len - 1.5)
		var want_lat: float = float(f["lat0"]) + (4.5 if shy else 0.0)
		# (out to sea only as far as the floor is not beyond ten meters: the dolphins' water)
		while want_lat > float(f["lat0"]) and float(_ls.ground(fr[0].x + out.x * want_lat, fr[0].z + out.z * want_lat)) < -9.6:
			want_lat -= 0.5
		var ds := want_s - s
		var want_speed := 0.0
		if absf(ds) > 0.35:
			f["face"] = signf(ds)
			want_speed = (0.62 if shy else 0.4) * clampf(absf(ds) / 1.5, 0.25, 1.0) * (1.3 if absf(ds) > 5.0 else 1.0)
		var lat_v := clampf((want_lat - float(f["lat"])) * 0.8, -0.3, 0.5 if shy else 0.3)
		# it looks the way it swims; hanging, the way it came, along the edge
		var vel := tan * (float(f["face"]) * maxf(float(f["speed"]), 0.12)) + out * lat_v
		var want_yaw := atan2(-vel.x, -vel.z)
		var yaw: float = f["yaw"]
		var diff := angle_difference(yaw, want_yaw)
		var dyaw := clampf(diff, -0.9 * delta, 0.9 * delta)
		yaw += dyaw
		f["yaw"] = yaw
		# (it turns first and swims then: a fish does not swim backward)
		var ahead := maxf(cos(angle_difference(yaw, atan2(-tan.x * float(f["face"]), -tan.z * float(f["face"])))), 0.0)
		want_speed *= ahead * ahead
		f["speed"] = move_toward(float(f["speed"]), want_speed, delta * 0.3)
		var speed: float = f["speed"]
		f["fastest"] = maxf(float(f["fastest"]), speed)
		# how deep: a couple of meters under the surface, lower when somebody is near and at
		# night; always well above whatever stands under it and just ahead
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var floor_y := maxf(_top(pos, 1.5), _top(pos + fwd * (0.8 * float(f["len"])), 1.5))
		var want_y := sea - float(pair["depth"]) - float(f["deep"]) - (1.0 if shy else 0.0) - 0.8 * smoothstep(0.5, 0.9, night)
		want_y = minf(maxf(want_y, floor_y + 0.9), sea - 0.9)
		var vy := clampf((want_y - pos.y) * 0.8, -0.25, 0.3)
		# hard rule: not into a coral: on only where it is above what stands there
		var step := float(f["face"]) * speed * delta
		var nxt := _at(s + step + float(f["face"]) * 0.5 * float(f["len"]))
		var np: Vector3 = (nxt[0] as Vector3) + (nxt[2] as Vector3) * float(f["lat"])
		if pos.y - 0.2 > _top(np, 0.3):
			s = clampf(s + step, 1.0, _len - 1.0)
		else:
			f["speed"] = speed * exp(-4.0 * delta)
		f["s"] = s
		f["lat"] = float(f["lat"]) + lat_v * delta
		f["y"] = pos.y + vy * delta
		fr = _at(s)
		# (hanging, it is never quite still: the swell moves it a hand's breadth)
		var drift := sin(_time * 0.31 + float(f["sway"])) * 0.12
		pos = (fr[0] as Vector3) + (fr[2] as Vector3) * (float(f["lat"]) + drift)
		pos.y = float(f["y"]) + sin(_time * 0.47 + float(f["sway"]) * 1.7) * 0.05
		f["pos"] = pos
		f["pitch"] = lerpf(float(f["pitch"]), clampf(atan2(vy, maxf(speed, 0.3)) * 0.6, -0.25, 0.25), 1.0 - exp(-2.0 * delta))
		f["bend"] = lerpf(float(f["bend"]), clampf(-dyaw / maxf(delta, 0.001) * 0.35, -0.5, 0.5), 1.0 - exp(-3.0 * delta))
		f["phase"] = fmod(float(f["phase"]) + delta * (1.3 + speed * 10.0), TAU * 64.0)
		var mi: MeshInstance3D = f["node"]
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, float(f["pitch"]))
		mi.global_transform = Transform3D(b.scaled(Vector3.ONE * (float(f["len"]) / 3.6)), pos)
		mi.set_instance_shader_parameter("phase", f["phase"])
		mi.set_instance_shader_parameter("amp", lerpf(0.22, 1.0, clampf(speed / 0.6, 0.0, 1.0)))
		mi.set_instance_shader_parameter("bend", f["bend"])


func report() -> Dictionary:
	if fish.is_empty():
		return {"none": "no line found along the reef's edge"}
	var at: Array = []
	for f: Dictionary in fish:
		var p: Vector3 = f["pos"]
		at.append([p.snappedf(0.1), "floor %.1f m down" % (float(_ls.sea) - float(_ls.ground(p.x, p.z))), "%.1f m under the surface" % (float(_ls.sea) - p.y)])
	var floors: Array = []
	for i in range(0, _line.size(), 6):
		floors.append([snappedf(_line[i].x, 0.1), snappedf(_line[i].z, 0.1), snappedf(float(_ls.ground(_line[i].x, _line[i].z)), 0.1)])
	return {"state": pair["state"], "at": at, "line length (m)": snappedf(_len, 1.0), "line (x, z, floor)": floors,
		"from the walker (m)": snappedf((fish[0]["pos"] as Vector3).distance_to(_player.global_position), 0.1)}


## For the tests: their life for `seconds` in steps of 50 ms. `swimmer`: 0 nobody; 1 somebody
## at the surface who swims at the first barracuda all the time, at a snorkeler's pace
## (and, as a swimmer, cannot go out over a floor more than 8 m down); 2 somebody who hangs
## still in the middle of their line, two meters down.
func soak(seconds := 1800.0, swimmer := 0) -> Dictionary:
	var sea: float = _ls.sea
	var mid := _at(_len * 0.5)
	var eye := Vector3(1e6, 0, 0)
	if swimmer == 1:
		eye = (fish[0]["pos"] as Vector3) + Vector3(-18, 0, 6)
		eye.y = sea - 0.3
	elif swimmer == 2:
		eye = Vector3((mid[0] as Vector3).x, sea - 2.0, (mid[0] as Vector3).z)
	for f: Dictionary in fish:
		f["nearest"] = 1e9
		f["fastest"] = 0.0
	var moved := [0.0, 0.0]
	var still := [0.0, 0.0]
	var still_max := [0.0, 0.0]
	var hang := 0.0
	var apart_max := 0.0
	var low := 1e9          # least water between a barracuda and what stands under it
	var shallow := 1e9
	var deep := 0.0
	var high := 1e9         # least water over one
	var near3 := 0.0        # seconds with a swimmer within 3 m
	for i in int(seconds / 0.05):
		if swimmer == 1:
			var to := (fish[0]["pos"] as Vector3) - eye
			to.y = 0.0
			if to.length() > 0.3:
				var nxt := eye + to.normalized() * (0.9 * 0.05)
				if float(_ls.ground(nxt.x, nxt.z)) > sea - 8.0:
					eye = nxt
		var before: Array = [fish[0]["pos"], fish[1]["pos"]]
		_step(0.05, eye)
		if pair["state"] == "hang":
			hang += 0.05
		apart_max = maxf(apart_max, (fish[0]["pos"] as Vector3).distance_to(fish[1]["pos"]))
		for k in 2:
			var p: Vector3 = fish[k]["pos"]
			var d := p.distance_to(before[k])
			moved[k] += d
			still[k] = float(still[k]) + 0.05 if d < 0.0005 else 0.0
			still_max[k] = maxf(still_max[k], still[k])
			low = minf(low, p.y - _top(p, 0.01))
			var floor_d := sea - float(_ls.ground(p.x, p.z))
			shallow = minf(shallow, floor_d)
			deep = maxf(deep, floor_d)
			high = minf(high, sea - p.y)
			if p.distance_to(eye) < 3.0:
				near3 += 0.05
			if is_nan(p.x) or is_nan(p.y):
				return {"nan at": i}
	return {"seconds hanging": hang, "meters swum": moved, "longest quite still (s)": still_max, "furthest apart (m)": apart_max,
		"least water under one (over corals too)": low, "floor under them, from .. to (m)": [shallow, deep], "least water over one": high,
		"nearest a swimmer has been (m)": [fish[0]["nearest"], fish[1]["nearest"]], "seconds a swimmer was within 3 m": near3,
		"fastest (m/s)": [fish[0]["fastest"], fish[1]["fastest"]]}
