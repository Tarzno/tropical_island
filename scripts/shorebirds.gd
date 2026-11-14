extends Node3D
## More birds (models: scripts/bird_models.gd; the node is created by island_life.gd):
##  * white-tailed tropicbirds: a few sit on their nests in nooks at the foot of the granite
##    boulders below the summit and on the east headland, the others fly about those rocks in
##    their buoyant, quick-beating way, pairs courting (one close behind and above the other),
##    and now and then one sweeps in past its nest and away again;
##  * ruddy turnstones: a small flock that works along the waterline of a beach near the
##    walker, walking, pecking, turning things over; they walk off ahead of someone who comes
##    near and, pressed, fly a little way along the shore;
##  * crab plovers: three of them on the wet sand, wary: they keep a dozen meters off;
##  * a striated heron at the pond: it stands hunched at the water's edge, stalks a few steps,
##    strikes; it flies to the far side or up the stream when someone comes close, and comes
##    back when they have gone.

const BirdModels := preload("res://scripts/bird_models.gd")
const Flight := preload("res://scripts/flight.gd")
const A := "res://assets/audio/"
const NONE := Vector3(1e9, 0, 0)
const TROPIC := {"cruise": 10.0, "max_bank": 0.85, "roll": 2.8, "climb": 3.0, "sink": 3.5}
const HEADLAND := Vector3(-186.0, 0.0, -15.0)

var _ls: Node
var _player: Node3D
var _sealife: Node
var _amb: Node
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _placed := false

var flocks: Array = []          # turnstones, crab plovers
var heron := {}
var heron_spots: Array = []     # per pool: {"pool": index, "pts": [[pos, normal], ...], "center": Vector3}
var tropics: Array = []         # the flying ones
var sitters: Array = []         # the ones on their nests: {"node", "pos", "out", "yaw", "home"}
var chicks: Array = []          # tropicbird chicks alone on their nests in the colony: {"node", "pos", "yaw0", "seed"}
var ground_noddies: Array = []  # brown noddies on nests on the ground of the colony: {"node", "pos", "yaw0", "seed"}
var sooty: Array = []           # sooty terns sitting on the ground: {"pos", "yaw0", "seed", "size"} (one MultiMesh)
var sooty_standing: Array = []  # ... and the ones that stand among them (birds of their own)
var sooty_center := Vector3.ZERO
var _sooty_mm: MultiMesh
var sooty_chicks: Array = []    # {"pos", "yaw0", "yaw", "seed", "size"} (one MultiMesh)
var sooty_eggs := 0
var _sooty_chick_mm: MultiMesh
var _sooty_voice: AudioStreamPlayer3D
var _nest_voice: AudioStreamPlayer3D
var nest_chatters := 0          # (for the tests) how often a tropicbird on its nest has scolded
var nest_rejects := {}          # (for the tests) why places for a nest on the ground were turned down
var _calls := {}


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_sealife = get_node_or_null("../../SeaLife")
	_amb = get_node_or_null("../../Ambience")
	_rng.randomize()
	for name_: String in ["tropicbird", "turnstone", "heron", "crab_plover", "mynah", "zebra_dove", "fody", "magpie_robin"]:
		var list: Array[AudioStream] = []
		for i in 6:
			var path := A + "%s_%d.wav" % [name_, i]
			if ResourceLoader.exists(path):
				list.append(load(path))
		_calls[name_] = list


func _night() -> float:
	var dc := get_node_or_null("../../DayCycle")
	return dc.night if dc else 0.0


func _ground(x: float, z: float) -> float:
	return float(_ls.ground(x, z))


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


## Does something solid stand at this place: a boulder, a trunk, a piece of driftwood? (A ray
## from above that stops well over the ground has met it.)
func _solid(x: float, z: float) -> bool:
	var g := _ground(x, z)
	var hit := _ray(Vector3(x, g + 2.5, z), Vector3(x, g - 0.5, z))
	return not hit.is_empty() and (hit["position"] as Vector3).y > g + 0.07


## Can a bird at `pos` take its next steps in the direction `dir`: nothing solid a body's
## length ahead, nor on the way there?
func _way_free(pos: Vector3, dir: Vector3, reach: float) -> bool:
	for f: float in [1.0, 0.6, 0.25]:
		if _solid(pos.x + dir.x * reach * f, pos.z + dir.z * reach * f):
			return false
	return true


## Room for a bird to stand at this place: nothing solid there or within r of it.
func _free(x: float, z: float, r := 0.3) -> bool:
	if _solid(x, z):
		return false
	for k in 4:
		if _solid(x + cos(0.4 + k * PI * 0.5) * r, z + sin(0.4 + k * PI * 0.5) * r):
			return false
	return true


func _voice(parent: Node3D, unit: float, far: float, db: float) -> AudioStreamPlayer3D:
	var v := AudioStreamPlayer3D.new()
	v.bus = "Ambient"
	v.unit_size = unit
	v.max_distance = far
	v.volume_db = db
	parent.add_child(v)
	return v


func _call(v: AudioStreamPlayer3D, kind: String) -> void:
	var list: Array = _calls.get(kind, [])
	if v == null or list.is_empty() or v.playing:
		return
	v.stream = list[_rng.randi() % list.size()]
	v.pitch_scale = _rng.randf_range(0.94, 1.07)
	v.play()


func _physics_process(_delta: float) -> void:
	# (the nests and the heron's places are found with ray casts: the collision shapes are
	# there after a few physics frames)
	if _placed or _ls == null or Engine.get_physics_frames() < 28:
		return
	_placed = true
	set_physics_process(false)
	_setup_tropicbirds()
	_setup_colony_ground()
	_setup_sooty_terns()
	_setup_heron()
	_setup_flock("turnstone", 4, {"ground": [0.02, 0.24], "walk": 0.32, "wary": 5.5, "flush": 2.6, "hop": [22.0, 40.0], "near": [24.0, 40.0],
		"far": 85.0, "spread": 2.2, "speed": 8.5, "height": 1.6, "beat": 7.5, "peck": 0.7})
	_setup_flock("crab_plover", 3, {"ground": [-0.07, 0.22], "walk": 0.4, "wary": 12.0, "flush": 6.0, "hop": [40.0, 65.0], "near": [42.0, 62.0],
		"far": 110.0, "spread": 3.5, "speed": 9.0, "height": 3.0, "beat": 4.6, "peck": 0.35})


# ================================================================== on the ground and in the air
## Shows a bird standing (or sitting) on the ground at b["pos"], facing b["yaw"].
## `moving` 0..1: how much the legs step; b["peck"] 0..1: the head down.
func _pose_ground(b: Dictionary, moving: float) -> void:
	var root: Node3D = b["root"]
	(b["stand"] as Node3D).visible = true
	(b["fly"] as Node3D).visible = false
	var pos: Vector3 = b["pos"]
	root.transform = Transform3D(Basis(Vector3.UP, b["yaw"]).scaled(root.scale), pos)
	var tilt: Node3D = b["tilt"]
	var peck: float = b.get("peck", 0.0)
	var hip: float = b["hip"]
	tilt.position = Vector3(0, hip - 0.25 * hip * peck + 0.004 * moving * sin(float(b.get("gait", 0.0)) * 2.0), -0.3 * hip * peck)
	tilt.rotation = Vector3(float(b["upright"]) - (float(b["upright"]) + 0.75) * peck, 0, 0)
	var legs: Array = b["legs"]
	for i in legs.size():
		var th: float = float(b.get("gait", 0.0)) + PI * i
		var upper: Node3D = legs[i][0]
		var lower: Node3D = legs[i][1]
		upper.visible = true
		upper.position.y = hip
		upper.rotation.x = -0.25 + 0.42 * sin(th) * moving
		lower.rotation.x = 0.42 - 0.7 * maxf(cos(th), 0.0) * moving - 0.15 * sin(th) * moving


## ... and flying: b["air"] holds "pitch" and "bank"; the wings beat by b["flap"] and b["amp"],
## `fold` 0 spread .. 1 closed, `legs_down` 0 trailing .. 1 lowered for the landing.
func _pose_air(b: Dictionary, fold: float, legs_down: float) -> void:
	var root: Node3D = b["root"]
	(b["stand"] as Node3D).visible = false
	(b["fly"] as Node3D).visible = true
	var air: Dictionary = b["air"]
	var basis := Basis(Vector3.UP, b["yaw"]) * Basis(Vector3.RIGHT, air["pitch"]) * Basis(Vector3.FORWARD, air["bank"])
	var pose := Flight.beat(b["flap"], b["amp"])
	root.transform = Transform3D(basis.scaled(root.scale), (b["pos"] as Vector3) + Vector3(0, float(pose[3]) * 0.012 * float(b["amp"]), 0))
	var tilt: Node3D = b["tilt"]
	tilt.position = Vector3.ZERO
	tilt.rotation = Vector3.ZERO
	Flight.pose(b["wings"], lerpf(0.1 + float(pose[0]), 0.3, fold), lerpf(float(pose[1]), -0.2, fold), lerpf(0.05 + float(pose[2]), 1.0, fold), float(pose[4]) * (1.0 - fold))
	var legs: Array = b["legs"]
	var trail: bool = b["kind"] != "turnstone"
	for i in legs.size():
		var upper: Node3D = legs[i][0]
		var lower: Node3D = legs[i][1]
		upper.visible = trail or legs_down > 0.3
		upper.position.y = -0.02
		upper.rotation.x = lerpf(-1.45, -0.2, legs_down)
		lower.rotation.x = lerpf(0.1, 0.3, legs_down)


## A short flight from where the bird is to `to`, rising `height` on the way and swinging
## out over the water (`side`): b["hop"] carries it.
func _start_hop(b: Dictionary, to: Vector3, height: float, speed: float, side: Vector3, delay := 0.0) -> void:
	var from: Vector3 = b["pos"]
	var dist := from.distance_to(to)
	var mid := (from + to) * 0.5 + Vector3(0, height * 2.0, 0) + side * minf(dist * 0.18, 6.0)
	b["hop"] = {"from": from, "to": to, "mid": mid, "u": 0.0, "dur": dist / speed + 0.9, "delay": delay}
	b["state"] = "fly"
	b["air"] = {"pitch": 0.3, "bank": 0.0}
	b["amp"] = 0.0


## Moves a bird along its hop. True when it has landed.
func _update_hop(b: Dictionary, delta: float, beat: float) -> bool:
	var h: Dictionary = b["hop"]
	if float(h["delay"]) > 0.0:
		h["delay"] = float(h["delay"]) - delta
		_pose_ground(b, 0.0)
		return false
	h["u"] = float(h["u"]) + delta / float(h["dur"])
	var u := minf(float(h["u"]), 1.0)
	# quick off the ground, slowing into the landing
	var e := 1.0 - pow(1.0 - u, 1.7) if u > 0.5 else u * (0.35 + 1.3 * u) / (0.35 + 0.65) * 1.0
	e = clampf(lerpf(u * u * (3.0 - 2.0 * u), 1.0 - pow(1.0 - u, 2.0), 0.5), 0.0, 1.0)
	var a: Vector3 = h["from"]
	var m: Vector3 = h["mid"]
	var c: Vector3 = h["to"]
	var p := a.lerp(m, e).lerp(m.lerp(c, e), e)
	var e2 := minf(e + 0.02, 1.0)
	var ahead := a.lerp(m, e2).lerp(m.lerp(c, e2), e2)
	var vel := ahead - p
	var old_yaw: float = b["yaw"]
	if Vector2(vel.x, vel.z).length() > 0.001:
		b["yaw"] = lerp_angle(old_yaw, atan2(-vel.x, -vel.z), 1.0 - exp(-8.0 * delta))
	var air: Dictionary = b["air"]
	var flare := smoothstep(0.8, 1.0, u)
	var climb := atan2(vel.y, maxf(Vector2(vel.x, vel.z).length(), 0.001))
	air["pitch"] = lerpf(float(air["pitch"]), clampf(climb * 0.7, -0.4, 0.5) + 0.55 * flare, 1.0 - exp(-6.0 * delta))
	air["bank"] = lerpf(float(air["bank"]), clampf(-angle_difference(old_yaw, b["yaw"]) / maxf(delta, 0.001) * 0.35, -0.6, 0.6), 1.0 - exp(-4.0 * delta))
	b["pos"] = p
	b["amp"] = lerpf(float(b["amp"]), 0.85 if u < 0.25 or flare > 0.0 else 0.62, 1.0 - exp(-6.0 * delta))
	b["flap"] = fmod(float(b["flap"]) + TAU * beat * (1.15 if u < 0.25 else 1.0) * delta, TAU)
	_pose_air(b, 0.0, flare)
	if u >= 1.0:
		b["pos"] = c
		b["state"] = "stand"
		return true
	return false


# ================================================================== turnstones and crab plovers
## A place on the wet sand at the water's edge within r0..r1 of `around`, where the ground is
## between lo and hi (NONE if there is none). `from`: it must lie further from this point than
## `around` does, if given (the way away from someone).
func _shore_point(around: Vector3, r0: float, r1: float, lo: float, hi: float, from := NONE) -> Vector3:
	for i in 60:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r0, r1)
		var p := Vector3(around.x + cos(a) * r, 0, around.z + sin(a) * r)
		var g := _ground(p.x, p.z)
		# (lo and hi: heights above the sea as it stands now. The band of wet sand goes up
		# and down the beach with the tide, and the birds with it)
		var h := g - float(_ls.sea)
		if h < lo or h > hi:
			continue
		var q := Vector2(p.x, p.z)
		if _ls.rocky(q, 0.8) or (h > 0.1 and not _ls.sandy(q)):
			continue
		if from != NONE and Vector2(p.x - from.x, p.z - from.z).length() < Vector2(around.x - from.x, around.z - from.z).length() + r * 0.6:
			continue
		var near_mangrove := false
		for m: Vector2 in _ls.mangrove_spots:
			if m.distance_to(q) < 4.0:
				near_mangrove = true
		if near_mangrove:
			continue
		# (not on or against a stone)
		if not _free(p.x, p.z):
			continue
		p.y = g
		return p
	return NONE


func _seaward(p: Vector3) -> Vector3:
	var e := 1.5
	var g := Vector3(_ground(p.x - e, p.z) - _ground(p.x + e, p.z), 0, _ground(p.x, p.z - e) - _ground(p.x, p.z + e))
	return g.normalized() if g.length() > 0.002 else Vector3.ZERO


func _setup_flock(kind: String, count: int, prm: Dictionary) -> void:
	var f := {"kind": kind, "prm": prm, "birds": [], "center": NONE, "drift": _rng.randf_range(8.0, 20.0), "away_t": 0.0, "hurry": 0.0,
		"flushes": 0, "arrivals": 0}
	var voice := _voice(self, 5.0, 60.0, -9.0)
	f["voice"] = voice
	for i in count:
		var b: Dictionary = BirdModels.make(kind)
		add_child(b["root"])
		(b["root"] as Node3D).scale = Vector3.ONE * _rng.randf_range(0.95, 1.08)
		(b["root"] as Node3D).visible = false
		b.merge({"pos": Vector3.ZERO, "yaw": _rng.randf() * TAU, "state": "stand", "goal": NONE, "wait": _rng.randf_range(0.5, 3.0), "gait": _rng.randf() * TAU,
			"peck": 0.0, "peck_t": 0.0, "flap": _rng.randf() * TAU, "amp": 0.0, "speed": 0.0})
		(f["birds"] as Array).append(b)
	flocks.append(f)


## The flock flies in from a little way off and comes down on the shore near the player.
func _arrive(f: Dictionary) -> bool:
	if _player == null:
		return false
	var prm: Dictionary = f["prm"]
	var pp := _player.global_position
	var g: Array = prm["ground"]
	var near: Array = prm["near"]
	var dest := _shore_point(Vector3(pp.x, 0, pp.z), near[0], near[1], g[0], g[1])
	if dest == NONE:
		return false
	# from over the water, on the side away from the player
	var sea := _seaward(dest)
	var along := Vector3(-sea.z, 0, sea.x)
	if along.dot(dest - pp) < 0.0:
		along = -along
	var start := dest + along * 55.0 + sea * 22.0
	start.y = 4.0
	f["center"] = dest
	var k := 0
	for b: Dictionary in f["birds"]:
		var spot := _shore_point(dest, 0.2, float(prm["spread"]), g[0], g[1])
		if spot == NONE:
			spot = dest
		(b["root"] as Node3D).visible = true
		b["pos"] = start + Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-2, 2)) - along * (k * 1.6)
		_start_hop(b, spot, 0.3, float(prm["speed"]), Vector3.ZERO, k * 0.12)
		(b["hop"] as Dictionary)["delay"] = 0.0
		b["goal"] = NONE
		k += 1
	f["arrivals"] = int(f["arrivals"]) + 1
	return true


func _update_flock(f: Dictionary, delta: float) -> void:
	var prm: Dictionary = f["prm"]
	var g: Array = prm["ground"]
	var pp := _player.global_position if _player else Vector3(1e6, 0, 0)
	var center: Vector3 = f["center"]
	var night := _night() > 0.6
	# nobody near any more (or not yet here): they fly in to a shore near the player
	if center == NONE or Vector2(center.x - pp.x, center.z - pp.z).length() > float(prm["far"]):
		f["away_t"] = float(f["away_t"]) + delta
		if float(f["away_t"]) > (2.0 if center == NONE else 9.0) and not night:
			f["away_t"] = 0.0
			var flying := false
			for b: Dictionary in f["birds"]:
				if b["state"] == "fly":
					flying = true
			if not flying:
				_arrive(f)
		if center == NONE:
			return
	else:
		f["away_t"] = 0.0
	# how close has someone come?
	var dmin := 1e9
	var flying_n := 0
	for b: Dictionary in f["birds"]:
		if b["state"] == "fly":
			flying_n += 1
		else:
			dmin = minf(dmin, Vector2((b["pos"] as Vector3).x - pp.x, (b["pos"] as Vector3).z - pp.z).length())
	f["hurry"] = maxf(float(f["hurry"]) - delta, 0.0)
	# the tide: when the water comes up around their legs faster than they walk, or has left
	# them far up the beach, they fly the few meters to where its edge is now
	var sea_now: float = _ls.sea
	var lowest := 9.0
	for b: Dictionary in f["birds"]:
		if b["state"] != "fly":
			lowest = minf(lowest, (b["pos"] as Vector3).y - sea_now)
	var center_h := _ground(center.x, center.z) - sea_now
	if flying_n == 0 and (lowest < float(g[0]) - 0.07 or center_h < float(g[0]) - 0.3 or center_h > float(g[1]) + 0.5):
		var to_edge := _shore_point(center, 1.0, 28.0, g[0], g[1])
		if to_edge != NONE:
			f["center"] = to_edge
			var k2 := 0
			for b: Dictionary in f["birds"]:
				var spot := _shore_point(to_edge, 0.2, float(prm["spread"]), g[0], g[1])
				_start_hop(b, spot if spot != NONE else to_edge, 0.7, float(prm["speed"]) * 0.7, Vector3.ZERO, k2 * _rng.randf_range(0.1, 0.3))
				b["goal"] = NONE
				k2 += 1
			return
	if flying_n == 0 and dmin < float(prm["flush"]):
		# too close: up and away along the shore, a little distance, and down again
		var hop: Array = prm["hop"]
		var dest := _shore_point(center, hop[0], hop[1], g[0], g[1], pp)
		if dest == NONE:
			dest = _shore_point(center, hop[0] * 0.6, hop[1] * 1.4, g[0], g[1], pp)
		if dest != NONE:
			f["center"] = dest
			f["flushes"] = int(f["flushes"]) + 1
			var sea := _seaward(center)
			var k := 0
			for b: Dictionary in f["birds"]:
				var spot := _shore_point(dest, 0.2, float(prm["spread"]), g[0], g[1])
				_start_hop(b, spot if spot != NONE else dest, float(prm["height"]), float(prm["speed"]), sea, k * _rng.randf_range(0.08, 0.2))
				b["goal"] = NONE
				k += 1
			(f["voice"] as AudioStreamPlayer3D).global_position = center
			_call(f["voice"], f["kind"])
	elif flying_n == 0 and dmin < float(prm["wary"]) and float(f["hurry"]) <= 0.0:
		# near enough to mind: they walk on ahead, away along the shore
		var ahead := _shore_point(center, 4.0, 9.0, g[0], g[1], pp)
		if ahead != NONE:
			f["center"] = ahead
			f["hurry"] = 4.0
			for b: Dictionary in f["birds"]:
				b["goal"] = NONE
				b["wait"] = _rng.randf_range(0.0, 0.5)
	else:
		# at ease: the flock works its way along the shore (and at once, if the tide has
		# moved the water's edge away from under it, or over it)
		var ch := _ground(center.x, center.z) - float(_ls.sea)
		if ch < float(g[0]) - 0.06 or ch > float(g[1]) + 0.1:
			f["drift"] = minf(float(f["drift"]), 1.5)
		f["drift"] = float(f["drift"]) - delta
		if float(f["drift"]) <= 0.0 and not night:
			f["drift"] = _rng.randf_range(10.0, 28.0)
			var on := _shore_point(center, 2.5, 7.0 if absf(ch) < 0.3 else 16.0, g[0], g[1])
			if on != NONE and Vector2(on.x - pp.x, on.z - pp.z).length() > float(prm["wary"]) + 2.0:
				f["center"] = on
	center = f["center"]
	var hurry: bool = float(f["hurry"]) > 0.0
	for b: Dictionary in f["birds"]:
		if b["state"] == "fly":
			_update_hop(b, delta, prm["beat"])
			continue
		var pos: Vector3 = b["pos"]
		var moving := 0.0
		b["peck_t"] = maxf(float(b["peck_t"]) - delta, 0.0)
		# (a peck: down, a jab or two, up)
		var pt: float = b["peck_t"]
		b["peck"] = sin(clampf(pt / 0.7, 0.0, 1.0) * PI) * (0.8 + 0.2 * sin(pt * 22.0)) if pt > 0.0 else 0.0
		if b["goal"] == NONE:
			b["wait"] = float(b["wait"]) - delta
			# (the water has come up around its feet: it does not wait)
			if pos.y - float(_ls.sea) < float(g[0]) - 0.01:
				b["wait"] = minf(float(b["wait"]), 0.3)
			if float(b["wait"]) <= 0.0 and not night:
				var spot := _shore_point(center, 0.2, float(prm["spread"]), g[0], g[1])
				if spot != NONE:
					b["goal"] = spot
		elif pt <= 0.0:
			var goal: Vector3 = b["goal"]
			var to := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
			if to.length() < 0.08:
				b["goal"] = NONE
				b["wait"] = _rng.randf_range(0.4, 2.5) if not hurry else 0.1
				if not hurry and _rng.randf() < float(prm["peck"]):
					b["peck_t"] = 0.7 if _rng.randf() < 0.6 else 1.2
			else:
				var v := float(prm["walk"]) * (2.4 if hurry else 1.0)
				b["speed"] = lerpf(float(b["speed"]), v, 1.0 - exp(-6.0 * delta))
				# a stone in the way: around it, on the side that is free (and the same side until it
				# is past); no way around: it stays where it is and looks for another place
				var dir := to.normalized()
				var reach := 0.16 + float(b["L"]) * 0.5
				if not _way_free(pos, dir, reach):
					var side: float = b.get("side", 1.0)
					var way := Vector3.ZERO
					for a: float in [0.6, 1.1, 1.6, 2.1, -0.6, -1.1, -1.6, -2.1]:
						var d2 := dir.rotated(Vector3.UP, a * side)
						if _way_free(pos, d2, reach):
							way = d2
							if a < 0.0:
								b["side"] = -side
							break
					dir = way
					b["blocked"] = float(b.get("blocked", 0.0)) + delta
				else:
					b["blocked"] = maxf(float(b.get("blocked", 0.0)) - delta * 0.5, 0.0)
				if dir == Vector3.ZERO or float(b["blocked"]) > 9.0:
					b["goal"] = NONE
					b["wait"] = _rng.randf_range(0.3, 1.2)
					b["blocked"] = 0.0
				else:
					b["yaw"] = lerp_angle(float(b["yaw"]), atan2(-dir.x, -dir.z), 1.0 - exp(-7.0 * delta))
					var np: Vector3 = pos + dir * minf(float(b["speed"]) * delta, to.length())
					# (and never a step that would end in the stone itself)
					if _solid(np.x, np.z):
						b["blocked"] = float(b["blocked"]) + delta
					else:
						pos = np
					pos.y = _ground(pos.x, pos.z)
					b["pos"] = pos
					# (short quick steps)
					b["gait"] = fmod(float(b["gait"]) + float(b["speed"]) * delta / (0.5 * float(b["hip"]) + 0.012) * 1.6, TAU)
					moving = 1.0
		if moving == 0.0:
			b["speed"] = 0.0
			pos.y = _ground(pos.x, pos.z)
			b["pos"] = pos
		_pose_ground(b, moving)


# ================================================================== the heron at the pond
func _setup_heron() -> void:
	var pools: Array = _ls.stream_pools
	for i in pools.size():
		var pl: Dictionary = pools[i]
		var at: Vector3 = pl["at"]
		var pts: Array = []
		var n := 20 if pl["pond"] else 10
		for k in n:
			var a := TAU * k / float(n)
			for extra in [0.25, 0.6, 1.0]:
				var r: float = maxf(pl["rx"], pl["rz"]) + extra
				var from := Vector3(at.x + cos(a) * r, at.y + 3.0, at.z + sin(a) * r)
				var hit := _ray(from, from - Vector3(0, 6.0, 0))
				if hit.is_empty() or (hit["normal"] as Vector3).y < 0.8:
					continue
				var hp: Vector3 = hit["position"]
				# at the water's edge: on the bank, hardly above the water, not in it
				if hp.y < at.y + 0.02 or hp.y > at.y + 0.45:
					continue
				pts.append([hp, hit["normal"]])
				break
		if pts.size() >= 2:
			heron_spots.append({"pool": i, "pts": pts, "center": at, "pond": pl["pond"]})
	if heron_spots.is_empty():
		return
	var site := 0
	for i in heron_spots.size():
		if heron_spots[i]["pond"]:
			site = i
	var b: Dictionary = BirdModels.make("heron")
	add_child(b["root"])
	var pts: Array = heron_spots[site]["pts"]
	var k := _rng.randi() % pts.size()
	b.merge({"pos": pts[k][0], "yaw": 0.0, "state": "wait", "site": site, "at": k, "t": _rng.randf_range(6.0, 20.0), "gait": 0.0, "peck": 0.0,
		"flap": 0.0, "amp": 0.0, "goal": -1, "strike": -1.0, "home": site, "away_t": 0.0, "flushes": 0})
	b["voice"] = _voice(b["root"], 6.0, 70.0, -8.0)
	heron = b
	_heron_face_water()
	_pose_ground(heron, 0.0)


func _heron_face_water() -> void:
	var c: Vector3 = heron_spots[heron["site"]]["center"]
	var pos: Vector3 = heron["pos"]
	heron["yaw_goal"] = atan2(-(c.x - pos.x), -(c.z - pos.z)) + _rng.randf_range(-0.5, 0.5)


func _update_heron(delta: float) -> void:
	if heron.is_empty():
		return
	var b := heron
	var pp := _player.global_position if _player else Vector3(1e6, 0, 0)
	var pos: Vector3 = b["pos"]
	if b["state"] == "fly":
		if _update_hop(b, delta, 3.6):
			b["state"] = "wait"
			b["t"] = _rng.randf_range(8.0, 20.0)
			_heron_face_water()
		return
	var dist := Vector2(pos.x - pp.x, pos.z - pp.z).length()
	b["t"] = float(b["t"]) - delta
	var moving := 0.0
	if dist < 6.5 and absf(pp.y - pos.y) < 4.0:
		# someone close: across the water if that is far enough, else to another pool
		var best := -1
		var best_site: int = b["site"]
		var bd := 9.0
		var pts: Array = heron_spots[b["site"]]["pts"]
		for k in pts.size():
			var d := Vector2((pts[k][0] as Vector3).x - pp.x, (pts[k][0] as Vector3).z - pp.z).length()
			if d > bd:
				bd = d
				best = k
		if best < 0:
			bd = 14.0
			for s in heron_spots.size():
				if s == int(b["site"]):
					continue
				var c: Vector3 = heron_spots[s]["center"]
				var d := Vector2(c.x - pp.x, c.z - pp.z).length()
				if d > bd and (best < 0 or d < 60.0):
					bd = d
					best_site = s
					best = _rng.randi() % (heron_spots[s]["pts"] as Array).size()
		if best >= 0:
			b["site"] = best_site
			b["at"] = best
			b["flushes"] = int(b["flushes"]) + 1
			_start_hop(b, heron_spots[best_site]["pts"][best][0], 2.2, 6.0, Vector3.ZERO)
			_call(b["voice"], "heron")
			return
	match b["state"]:
		"wait":
			# hunched and still; then a strike, or a few slow steps along the edge. Away from
			# the pond it goes back there once nobody is near it
			if int(b["site"]) != int(b["home"]):
				var hc: Vector3 = heron_spots[b["home"]]["center"]
				b["away_t"] = float(b["away_t"]) + delta if Vector2(hc.x - pp.x, hc.z - pp.z).length() > 22.0 else 0.0
				if float(b["away_t"]) > 14.0:
					b["away_t"] = 0.0
					b["site"] = b["home"]
					b["at"] = _rng.randi() % (heron_spots[b["home"]]["pts"] as Array).size()
					_start_hop(b, heron_spots[b["home"]]["pts"][b["at"]][0], 2.5, 6.0, Vector3.ZERO)
					return
			if float(b["t"]) <= 0.0:
				if _rng.randf() < 0.45:
					b["state"] = "strike"
					b["strike"] = 0.0
				else:
					var pts: Array = heron_spots[b["site"]]["pts"]
					var k := posmod(int(b["at"]) + (1 if _rng.randf() < 0.5 else -1), pts.size())
					if (pts[k][0] as Vector3).distance_to(pos) < 3.0:
						b["goal"] = k
						b["state"] = "stalk"
					b["t"] = _rng.randf_range(8.0, 24.0)
		"stalk":
			var pts: Array = heron_spots[b["site"]]["pts"]
			var goal: Vector3 = pts[b["goal"]][0]
			var to := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
			if to.length() < 0.05:
				b["at"] = b["goal"]
				b["state"] = "wait"
				b["t"] = _rng.randf_range(6.0, 20.0)
				_heron_face_water()
			else:
				# one slow step, a pause, the next
				var step := 0.5 + 0.5 * sin(_time * 2.2)
				b["yaw_goal"] = atan2(-to.x, -to.z)
				pos += to.normalized() * minf(0.16 * step * delta, to.length())
				var y0 := lerpf(pos.y, goal.y, clampf(delta * 2.0, 0.0, 1.0))
				pos.y = y0
				b["pos"] = pos
				b["gait"] = fmod(float(b["gait"]) + 0.16 * step * delta / 0.045, TAU)
				moving = 1.0
		"strike":
			b["strike"] = float(b["strike"]) + delta
			var s: float = b["strike"]
			# a slow lean forward, the jab, back up
			b["peck"] = 0.25 * smoothstep(0.0, 1.2, s) + 0.75 * smoothstep(1.2, 1.32, s) - smoothstep(1.7, 2.4, s)
			if s > 2.4:
				b["peck"] = 0.0
				b["state"] = "wait"
				b["t"] = _rng.randf_range(10.0, 30.0)
	b["yaw"] = lerp_angle(float(b["yaw"]), float(b.get("yaw_goal", b["yaw"])), 1.0 - exp(-2.0 * delta))
	_pose_ground(b, moving)


# ================================================================== tropicbirds
func _setup_tropicbirds() -> void:
	var peak: Vector2 = _ls._peak
	var homes := [Vector3(peak.x, _ground(peak.x, peak.y), peak.y), Vector3(HEADLAND.x, maxf(_ground(HEADLAND.x, HEADLAND.z), 0.0), HEADLAND.z)]
	# nests: in the angle between a boulder and the ground, facing out; on open grass or bare
	# rock, clear of the shrubs (a bird under a bush is not seen)
	var space := get_world_3d().direct_space_state
	var shrubs := _shrub_list()
	for hi in homes.size():
		var home: Vector3 = homes[hi]
		var cands: Array = []
		for b: Array in _ls.boulder_spots:
			var c: Vector3 = b[0]
			var d := Vector2(c.x - home.x, c.z - home.z).length()
			var gy := _ground(c.x, c.z)
			if float(b[1]) < 1.2 or gy < 0.8:
				continue
			# (not on the lookout itself, and not down in the forest)
			if (hi == 0 and d > 10.0 and d < 70.0 and gy > home.y - 22.0) or (hi == 1 and d < 45.0):
				cands.append([d, b])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var made := 0
		for cd: Array in cands:
			if made >= (3 if hi == 0 else 2):
				break
			var b: Array = cd[1]
			var c: Vector3 = b[0]
			var size: float = b[1]
			for attempt in 8:
				var dir := Vector3(cos(attempt * 0.785 + hi), 0, sin(attempt * 0.785 + hi))
				var r := size * 0.2
				var at := NONE
				while r < size * 1.5 + 1.0:
					var q := c + dir * r
					var qy := _ground(q.x, q.z)
					var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, qy + 8.0, q.z), Vector3(q.x, qy - 1.0, q.z))
					ray.collision_mask = 1
					var hit := space.intersect_ray(ray)
					if hit.is_empty() or (hit["position"] as Vector3).y < qy + 0.06:
						at = Vector3(q.x, qy, q.z) + dir * 0.16
						break
					r += 0.08
				if at == NONE or r < size * 0.25:
					continue
				at.y = _ground(at.x, at.z)
				# (level enough to sit on, and dry)
				var e := 0.3
				if absf(_ground(at.x + e, at.z) - _ground(at.x - e, at.z)) > 0.3 or absf(_ground(at.x, at.z + e) - _ground(at.x, at.z - e)) > 0.3 or at.y < 0.7:
					continue
				var near := false
				for s: Dictionary in sitters:
					if (s["pos"] as Vector3).distance_to(at) < 5.0:
						near = true
				for sh: Array in shrubs:
					if (sh[0] as Vector2).distance_to(Vector2(at.x, at.z)) < float(sh[1]) + 0.5:
						near = true
				if near or not (float((_ls.cover(at.x, at.z) as Color).b) > 0.4 or _ls.rocky(Vector2(at.x, at.z), 0.7)):
					continue
				var sb: Dictionary = BirdModels.make("tropicbird")
				add_child(sb["root"])
				sb.merge({"pos": at, "yaw": atan2(-dir.x, -dir.z), "yaw0": atan2(-dir.x, -dir.z), "out": dir, "home": hi, "seed": _rng.randf() * TAU})
				_pose_ground(sb, 0.0)
				sitters.append(sb)
				made += 1
				break
	# the fliers: three about the summit, two about the headland, two about the seabird colony
	# (where others of them sit on the ground under the trees: _setup_colony_ground())
	var c2: Vector2 = _ls.colony_center
	homes.append(Vector3(c2.x, _ground(c2.x, c2.y), c2.y))
	for i in 7:
		var hi := 0 if i < 3 else (1 if i < 5 else 2)
		var home: Vector3 = homes[hi]
		var a := _rng.randf() * TAU
		var start := home + Vector3(cos(a) * 50.0, 30.0, sin(a) * 50.0)
		var tb: Dictionary = BirdModels.make("tropicbird")
		add_child(tb["root"])
		(tb["stand"] as Node3D).visible = false
		(tb["fly"] as Node3D).visible = true
		tb.merge({"b": Flight.make(start, _rng.randf() * TAU, 9.0), "home": home, "home_i": hi, "goal": start, "timer": 0.0, "follow": -1, "follow_t": 0.0,
			"next_follow": _rng.randf_range(15.0, 50.0), "pass_t": _rng.randf_range(30.0, 110.0), "passing": false, "flap": _rng.randf() * TAU, "amp": 0.5,
			"glide": _rng.randf_range(2.0, 6.0), "call_t": _rng.randf_range(5.0, 30.0), "seed": _rng.randf() * TAU})
		tb["voice"] = _voice(tb["root"], 14.0, 170.0, -7.0)
		tropics.append(tb)


## Where the shrubs stand: [middle (x, z), radius] of each (a bird under a bush is not seen).
func _shrub_list() -> Array:
	var shrubs: Array = []
	var bushes := _ls.get_node_or_null("BushClusters")
	if bushes:
		for mi in bushes.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh:
				var ab := m.global_transform * m.get_aabb()
				shrubs.append([Vector2(ab.position.x + ab.size.x * 0.5, ab.position.z + ab.size.z * 0.5), maxf(ab.size.x, ab.size.z) * 0.5])
	return shrubs


## Level open ground at `at` for a nest: dry, not under a shrub or a fern, nothing solid on
## it, and `apart` from every other nest on the ground.
func _nest_ground(at: Vector3, shrubs: Array, apart: float) -> bool:
	var why := _nest_fault(at, shrubs, apart)
	if why != "":
		nest_rejects[why] = int(nest_rejects.get(why, 0)) + 1
	return why == ""


func _nest_fault(at: Vector3, shrubs: Array, apart: float) -> String:
	var e := 0.3
	if at.y < 0.9 or absf(_ground(at.x + e, at.z) - _ground(at.x - e, at.z)) > 0.25 or absf(_ground(at.x, at.z + e) - _ground(at.x, at.z - e)) > 0.25:
		return "low or steep"
	var v := Vector2(at.x, at.z)
	if _solid(at.x, at.z):
		return "something solid"
	if _ls.ferny(v, 0.2):
		return "a fern"
	if float(_ls.stream_dist(v)) < 3.0:
		return "the stream"
	# (not on the sand of the beach: that is the turtle's and the hermit crabs' ground)
	if _ls.sandy(v):
		return "beach sand"
	for sh: Array in shrubs:
		if (sh[0] as Vector2).distance_to(v) < float(sh[1]) + 0.4:
			return "a shrub"
	for list: Array in [sitters, chicks, ground_noddies]:
		for o: Dictionary in list:
			if (o["pos"] as Vector3).distance_to(at) < apart:
				return "another nest"
	return ""


## The ground of the seabird colony. On islands without rats or cats many seabirds nest on
## the bare ground: here white-tailed tropicbirds in the nooks between the roots at the feet
## of the colony's trees (an adult sitting, or a chick alone: a ball of gray down, while its
## parents are at sea), and brown noddies on little nests of leaves on open ground at the
## edge of the grove. None of them leaves for a walker: they watch, and stay.
func _setup_colony_ground() -> void:
	var c2: Vector2 = _ls.colony_center
	var space := get_world_3d().direct_space_state
	var shrubs := _shrub_list()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var feet: Array = []
	for t: Dictionary in _ls.tree_spots:
		var o: Vector3 = (t["xf"] as Transform3D).origin
		if Vector2(o.x, o.z).distance_to(c2) < 27.0:
			feet.append(o)
	nest_rejects["trees"] = feet.size()
	for i in range(feet.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Vector3 = feet[i]
		feet[i] = feet[j]
		feet[j] = tmp
	var chick_mesh: ArrayMesh = BirdModels.chick()
	var made := 0
	# (two rounds: a big tree may have a nest on either side of its foot)
	for o: Vector3 in feet + feet:
		if made >= 14:
			break
		for attempt in 16:
			var a := rng.randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			# in toward the trunk from two meters out, a hand above the ground: where the ray
			# meets the bark is the foot of the tree, and the nest lies against it. (A ray
			# sent down from inside the trunk meets nothing: its faces are seen from behind.)
			var r := 0.3
			var at := NONE
			var oy := _ground(o.x, o.z) + 0.3
			var ray := PhysicsRayQueryParameters3D.create(Vector3(o.x + dir.x * 2.0, oy, o.z + dir.z * 2.0), Vector3(o.x, oy, o.z))
			ray.collision_mask = 1
			var hit := space.intersect_ray(ray)
			if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.6:
				at = (hit["position"] as Vector3) + dir * 0.24
			if at == NONE or r < 0.25:
				nest_rejects["no edge of the trunk found"] = int(nest_rejects.get("no edge of the trunk found", 0)) + 1
				continue
			at.y = _ground(at.x, at.z)
			if not _nest_ground(at, shrubs, 2.2):
				continue
			# the bird sits along the foot of the tree, its side to the trunk: the long tail
			# feathers must lie free on the ground, not in the wood (whichever way around is free)
			var yaw := NAN
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			for sgn: float in [side, -side]:
				var fwd := Vector3(-dir.z, 0, dir.x) * sgn
				var free := true
				for back: float in [0.25, 0.45, 0.65, 0.85]:
					if _solid(at.x - fwd.x * back, at.z - fwd.z * back):
						free = false
				if free and not _solid(at.x + fwd.x * 0.25, at.z + fwd.z * 0.25):
					yaw = atan2(-fwd.x, -fwd.z)
					break
			if is_nan(yaw):
				nest_rejects["no room for the tail"] = int(nest_rejects.get("no room for the tail", 0)) + 1
				continue
			if made % 3 == 2:
				var mi := MeshInstance3D.new()
				mi.name = "TropicbirdChick%d" % chicks.size()
				mi.mesh = chick_mesh
				add_child(mi)
				var size := rng.randf_range(0.85, 1.15)
				mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at)
				chicks.append({"node": mi, "pos": at, "yaw0": yaw, "yaw": yaw, "seed": rng.randf() * TAU, "size": size, "up": 0.0})
			else:
				var sb: Dictionary = BirdModels.make("tropicbird")
				add_child(sb["root"])
				# ("home" 9: no flier's home: nobody sweeps in past a nest under the trees)
				sb.merge({"pos": at, "yaw": yaw, "yaw0": yaw, "out": dir, "home": 9, "seed": rng.randf() * TAU})
				_pose_ground(sb, 0.0)
				sitters.append(sb)
			made += 1
			break
	# brown noddies on the ground: open, level places in and around the grove
	var colony := get_node_or_null("../../Colony")
	if colony == null or not colony.has_method("_instance") or not (colony.get("_models") as Dictionary).has("NoddyPerched"):
		return
	var tries := 0
	while ground_noddies.size() < 12 and tries < 600:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, 29.0)
		var at := Vector3(c2.x + cos(a) * r, 0, c2.y + sin(a) * r)
		at.y = _ground(at.x, at.z)
		if not _nest_ground(at, shrubs, 2.2) or not _free(at.x, at.z, 0.5):
			continue
		var nest: Node3D = colony._instance("Nest")
		add_child(nest)
		nest.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 1.5)), at + Vector3(0, 0.01, 0))
		var bird: Node3D = colony._instance("NoddyPerched")
		add_child(bird)
		var yaw := rng.randf() * TAU
		bird.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.08, 0))
		ground_noddies.append({"node": bird, "pos": at, "yaw0": yaw, "seed": rng.randf() * TAU})


## Sooty terns (Onychoprion fuscatus): the ground breeder of the Seychelles in great numbers.
## A dense patch of them on the most open ground near the colony's grove: birds half a meter
## apart (as far as a neighbor's bill reaches), most of them sitting on their one egg, some
## standing between, all facing much the same way, into the wind; a few wheel over the
## patch. They do not leave for a walker.
const SOOTY_R := 8.0


## Is p in the sooty terns' patch (the hermit crabs and the nesting turtle keep out of it)?
func in_sooty_patch(p: Vector3, margin := 1.5) -> bool:
	return _sooty_mm != null and Vector2(p.x - sooty_center.x, p.z - sooty_center.z).length() < SOOTY_R + margin


func _sooty_ok(q: Vector2, shrubs: Array, trunks: Array) -> bool:
	# open sand at the top of the beach, well above high water: the headland itself is all
	# forest, and sooty terns want the sky over them
	var y := _ground(q.x, q.y)
	if y < 1.0 or y > 2.8 or not _ls.sandy(q):
		return false
	var e := 0.4
	if absf(_ground(q.x + e, q.y) - _ground(q.x - e, q.y)) > 0.16 or absf(_ground(q.x, q.y + e) - _ground(q.x, q.y - e)) > 0.16:
		return false
	for t: Vector2 in trunks:
		if t.distance_to(q) < 2.5:
			return false
	for sh: Array in shrubs:
		if (sh[0] as Vector2).distance_to(q) < float(sh[1]) + 0.5:
			return false
	return not _solid(q.x, q.y) and not _ls.ferny(q, 0.3)


func _setup_sooty_terns() -> void:
	var c2: Vector2 = _ls.colony_center
	var shrubs := _shrub_list()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8842
	var trunks: Array = []
	for t: Dictionary in _ls.tree_spots:
		var o: Vector3 = (t["xf"] as Transform3D).origin
		if Vector2(o.x, o.z).distance_to(c2) < 70.0:
			trunks.append(Vector2(o.x, o.z))
	for t: Dictionary in _ls.palm_trunks:
		var o: Vector3 = (t["pts"] as PackedVector3Array)[0]
		if Vector2(o.x, o.z).distance_to(c2) < 70.0:
			trunks.append(Vector2(o.x, o.z))
	# the most open place within reach of the grove
	var best := c2
	var best_n := -1
	for i in 140:
		var a := rng.randf() * TAU
		var c := c2 + Vector2(cos(a), sin(a)) * rng.randf_range(20.0, 62.0)
		var n := 0
		for k in 20:
			var b := rng.randf() * TAU
			if _sooty_ok(c + Vector2(cos(b), sin(b)) * (sqrt(rng.randf()) * 5.0), shrubs, trunks):
				n += 1
		if n > best_n:
			best_n = n
			best = c
	sooty_center = Vector3(best.x, _ground(best.x, best.y), best.y)
	var wind := rng.randf() * TAU
	var places: Array = []
	var tries := 0
	while places.size() < 72 and tries < 4000:
		tries += 1
		var b := rng.randf() * TAU
		var q := best + Vector2(cos(b), sin(b)) * (sqrt(rng.randf()) * SOOTY_R)
		if not _sooty_ok(q, shrubs, trunks):
			continue
		var near := false
		for p: Vector3 in places:
			if Vector2(p.x, p.z).distance_to(q) < 0.55:
				near = true
				break
		if not near:
			places.append(Vector3(q.x, _ground(q.x, q.y), q.y))
	var as_: Dictionary = BirdModels._assets("sooty_tern")
	_sooty_mm = MultiMesh.new()
	_sooty_mm.transform_format = MultiMesh.TRANSFORM_3D
	_sooty_mm.mesh = as_["stand"]
	var sitting: Array = []
	for i in places.size():
		var yaw := wind + rng.randf_range(-0.6, 0.6)
		if i % 5 == 4:
			var sb: Dictionary = BirdModels.make("sooty_tern")
			add_child(sb["root"])
			sb.merge({"pos": places[i], "yaw": yaw, "yaw0": yaw, "seed": rng.randf() * TAU})
			_pose_ground(sb, 0.0)
			sooty_standing.append(sb)
		else:
			sitting.append({"pos": places[i], "yaw0": yaw, "yaw": yaw, "seed": rng.randf() * TAU, "size": rng.randf_range(0.95, 1.08)})
	sooty = sitting
	_sooty_mm.instance_count = sooty.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SootyTerns"
	mmi.multimesh = _sooty_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	for i in sooty.size():
		_pose_sooty(i)
	_sooty_young(rng, places)
	# the colony's voice: a clamor that carries a long way and is loud among the birds
	if ResourceLoader.exists(A + "sooty_colony.wav"):
		var st := load(A + "sooty_colony.wav") as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = int(st.get_length() * st.mix_rate)
		_sooty_voice = AudioStreamPlayer3D.new()
		_sooty_voice.stream = st
		_sooty_voice.bus = "Ambient"
		_sooty_voice.unit_size = 11.0
		_sooty_voice.max_distance = 150.0
		_sooty_voice.volume_db = 4.0
		_sooty_voice.attenuation_filter_cutoff_hz = 7000.0
		add_child(_sooty_voice)
		_sooty_voice.global_position = sooty_center + Vector3(0, 1.2, 0)
		_sooty_voice.play(rng.randf() * 10.0)
	# a few in the air over the patch
	for i in 4:
		var a := rng.randf() * TAU
		var start := sooty_center + Vector3(cos(a) * 30.0, 18.0, sin(a) * 30.0)
		var tb: Dictionary = BirdModels.make("sooty_tern")
		add_child(tb["root"])
		(tb["stand"] as Node3D).visible = false
		(tb["fly"] as Node3D).visible = true
		for lg: Array in tb["legs"]:
			(lg[0] as Node3D).visible = false
		tb.merge({"b": Flight.make(start, rng.randf() * TAU, 9.0), "home": sooty_center, "home_i": 3, "goal": start, "timer": 0.0, "follow": -1, "follow_t": 0.0,
			"next_follow": rng.randf_range(15.0, 50.0), "pass_t": 1e9, "passing": false, "flap": rng.randf() * TAU, "amp": 0.5,
			"glide": rng.randf_range(2.0, 6.0), "call_t": 1e9, "seed": rng.randf() * TAU, "voice": null})
		tropics.append(tb)


## Eggs and chicks. A sooty tern lays one egg on the bare sand, no nest: here an egg lies at
## the feet of every bird that stands (the sitting ones are on theirs), and beside some of
## the sitting birds a chick crouches: a small ball of speckled gray-buff down.
func _sooty_young(rng: RandomNumberGenerator, places: Array) -> void:
	var eggs := MultiMesh.new()
	eggs.transform_format = MultiMesh.TRANSFORM_3D
	eggs.mesh = BirdModels.egg()
	eggs.instance_count = sooty_standing.size()
	for i in sooty_standing.size():
		var b: Dictionary = sooty_standing[i]
		var yaw: float = b["yaw0"]
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		# (beside its feet, where it shows: the bird has stood up off it)
		var at: Vector3 = (b["pos"] as Vector3) + fwd * 0.03 + Vector3(-fwd.z, 0, fwd.x) * (0.1 if rng.randf() < 0.5 else -0.1)
		at.y = _ground(at.x, at.z) - 0.004
		eggs.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at))
	sooty_eggs = eggs.instance_count
	var emi := MultiMeshInstance3D.new()
	emi.name = "SootyEggs"
	emi.multimesh = eggs
	emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emi)
	# chicks: beside every third sitting bird, on the side where there is most room
	for i in sooty.size():
		if i % 3 != 1:
			continue
		var s: Dictionary = sooty[i]
		var best := NONE
		var best_d := 0.0
		for k in 8:
			var a := TAU * k / 8.0 + rng.randf() * 0.5
			var q: Vector3 = (s["pos"] as Vector3) + Vector3(cos(a), 0, sin(a)) * 0.3
			var gap := 9.0
			for p: Vector3 in places:
				if p != (s["pos"] as Vector3):
					gap = minf(gap, Vector2(p.x - q.x, p.z - q.z).length())
			for c: Dictionary in sooty_chicks:
				gap = minf(gap, Vector2((c["pos"] as Vector3).x - q.x, (c["pos"] as Vector3).z - q.z).length())
			if gap > best_d and not _solid(q.x, q.z):
				best_d = gap
				best = q
		if best == NONE or best_d < 0.22:
			continue
		best.y = _ground(best.x, best.z)
		var yaw := rng.randf() * TAU
		sooty_chicks.append({"pos": best, "yaw0": yaw, "yaw": yaw, "seed": rng.randf() * TAU, "size": rng.randf_range(0.5, 0.68)})
	_sooty_chick_mm = MultiMesh.new()
	_sooty_chick_mm.transform_format = MultiMesh.TRANSFORM_3D
	_sooty_chick_mm.mesh = BirdModels.chick(Color(0.5, 0.45, 0.37))
	_sooty_chick_mm.instance_count = sooty_chicks.size()
	var cmi := MultiMeshInstance3D.new()
	cmi.name = "SootyChicks"
	cmi.multimesh = _sooty_chick_mm
	add_child(cmi)
	for i in sooty_chicks.size():
		_pose_sooty_chick(i)


func _pose_sooty_chick(i: int) -> void:
	var c: Dictionary = sooty_chicks[i]
	var breath := 1.0 + 0.04 * sin(_time * 3.1 + float(c["seed"]))
	_sooty_chick_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(c["yaw"])).scaled(Vector3(1.0, breath, 1.0) * float(c["size"])), c["pos"]))


## A sitting sooty tern: belly on the ground.
func _pose_sooty(i: int) -> void:
	var s: Dictionary = sooty[i]
	var size: float = s["size"]
	_sooty_mm.set_instance_transform(i, Transform3D((Basis(Vector3.UP, float(s["yaw"])) * Basis(Vector3.RIGHT, 0.1)).scaled(Vector3.ONE * size),
		(s["pos"] as Vector3) + Vector3(0, 0.058 * size, 0)))


func _update_sooty(delta: float) -> void:
	if _sooty_mm == null or _player == null:
		return
	var pp := _player.global_position
	if _sooty_voice:
		# (they call through the night too, less)
		_sooty_voice.volume_db = lerpf(4.0, -6.0, _night())
	if Vector2(pp.x - sooty_center.x, pp.z - sooty_center.z).length() > 60.0:
		return
	# they look about them, and at a walker who comes within a few steps; nobody leaves
	for i in sooty.size():
		var s: Dictionary = sooty[i]
		var want: float = float(s["yaw0"]) + 0.3 * sin(_time * 0.27 + float(s["seed"])) + 0.12 * sin(_time * 1.1 + float(s["seed"]) * 2.3)
		var to_p := Vector3(pp.x - (s["pos"] as Vector3).x, 0, pp.z - (s["pos"] as Vector3).z)
		if to_p.length() < 3.0:
			want = float(s["yaw0"]) + clampf(angle_difference(float(s["yaw0"]), atan2(-to_p.x, -to_p.z)), -0.9, 0.9)
		s["yaw"] = float(s["yaw"]) + clampf(angle_difference(float(s["yaw"]), want), -1.2 * delta, 1.2 * delta)
		_pose_sooty(i)
	# the chicks shuffle around on the spot and breathe
	for i in sooty_chicks.size():
		var c: Dictionary = sooty_chicks[i]
		var cw: float = float(c["yaw0"]) + 0.8 * sin(_time * 0.19 + float(c["seed"])) + 0.25 * sin(_time * 1.7 + float(c["seed"]) * 2.1)
		c["yaw"] = float(c["yaw"]) + clampf(angle_difference(float(c["yaw"]), cw), -1.5 * delta, 1.5 * delta)
		_pose_sooty_chick(i)
	for b: Dictionary in sooty_standing:
		var want: float = float(b["yaw0"]) + 0.4 * sin(_time * 0.21 + float(b["seed"])) + 0.15 * sin(_time * 0.8 + float(b["seed"]) * 1.7)
		b["yaw"] = float(b["yaw"]) + clampf(angle_difference(float(b["yaw"]), want), -1.2 * delta, 1.2 * delta)
		(b["root"] as Node3D).rotation.y = b["yaw"]


func sooty_report() -> Dictionary:
	return {"center": sooty_center, "sitting": sooty.size(), "standing": sooty_standing.size(), "flying": 4 if _sooty_mm else 0,
		"eggs showing": sooty_eggs, "chicks": sooty_chicks.size(), "voice": _sooty_voice != null and _sooty_voice.playing,
		"Ambient bus peak now (dB)": snappedf(AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Ambient"), 0), 0.1),
		"from the colony's middle (m)": Vector2(sooty_center.x - float(_ls.colony_center.x), sooty_center.z - float(_ls.colony_center.y)).length()}


## For the tests: the nests on the ground of the colony.
func colony_ground_report() -> Dictionary:
	var c2: Vector2 = _ls.colony_center
	var adults: Array = []
	for s: Dictionary in sitters:
		if int(s["home"]) == 9:
			adults.append(s["pos"])
	var cp: Array = []
	for c: Dictionary in chicks:
		cp.append(c["pos"])
	var np: Array = []
	for g: Dictionary in ground_noddies:
		np.append(g["pos"])
	return {"colony": c2, "tropicbirds sitting": adults, "chicks": cp, "noddies on the ground": np, "tropicbirds flying": tropics.size()}


## Somewhere to fly to about `home`: over the rocks or out over the sea beside them, well
## above the ground and the trees.
func _tropic_goal(home: Vector3) -> Vector3:
	for i in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(20.0, 105.0)
		var p := Vector3(home.x + cos(a) * r, 0, home.z + sin(a) * r)
		var g := maxf(_ground(p.x, p.z), 0.0)
		p.y = maxf(g + _rng.randf_range(15.0, 34.0), home.y + _rng.randf_range(-6.0, 22.0))
		if p.y < g + 14.0:
			continue
		return p
	return home + Vector3(0, 30.0, 0)


## For the tests: the flying tropicbirds at dusk and dawn.
func tropic_leave_report() -> Dictionary:
	var out := {"in the air": 0, "of them leaving": 0, "gone out to sea": 0, "furthest in the air from the walker (m)": 0.0}
	var pp: Vector3 = _player.global_position if _player else Vector3.ZERO
	for d: Dictionary in tropics:
		if d.get("gone", false):
			out["gone out to sea"] += 1
			continue
		out["in the air"] += 1
		if d.get("leaving", false):
			out["of them leaving"] += 1
		out["furthest in the air from the walker (m)"] = maxf(out["furthest in the air from the walker (m)"], snappedf((d["b"]["pos"] as Vector3).distance_to(pp), 1.0))
	return out


const TROPIC_GONE := 650.0     # so far from the walker a tropicbird that has left at dusk is taken out of the sky
var _tropic_age := 0.0

func _update_tropicbirds(delta: float) -> void:
	var night := _night()
	_tropic_age += delta
	var gust: float = _amb.gust if _amb and "gust" in _amb else 1.0
	for i in tropics.size():
		var d: Dictionary = tropics[i]
		var root: Node3D = d["root"]
		var b: Dictionary = d["b"]
		var pos: Vector3 = b["pos"]
		# At night they are out at sea or on the nest: none in the air. At dusk each flies
		# out over the sea, away from the island, and at dawn it comes in again (they used
		# to be switched off in the air when `night` passed 0.7).
		if not d.has("shy"):
			d["shy"] = _rng.randf_range(0.0, 0.1)
			d["gone"] = false
			d["leaving"] = false
			var home0: Vector3 = d["home"]
			var out := Vector3(home0.x + 95.0, 0, home0.z).normalized()       # (away from the middle of the island)
			if out == Vector3.ZERO:
				out = Vector3(1, 0, 0)
			d["sea"] = Vector3(home0.x, 0, home0.z) + out.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * 900.0 + Vector3(0, _rng.randf_range(30.0, 50.0), 0)
		var shy: float = d["shy"]
		var pp: Vector3 = _player.global_position if _player else Vector3.ZERO
		if d["gone"]:
			if night > 0.55 - shy:
				continue
			var from: Vector3 = d["sea"]
			from = pp + (from - pp).normalized() * (TROPIC_GONE - 20.0)
			from.y = float(d["sea"].y)
			b["pos"] = from
			b["yaw"] = Flight.yaw_of((d["home"] as Vector3) - from)
			b["vy"] = 0.0
			b["bank"] = 0.0
			pos = from
			d["gone"] = false
			d["goal"] = _tropic_goal(d["home"])
			d["timer"] = 120.0
			root.visible = true
		elif d["leaving"]:
			if night < 0.55 - shy:
				d["leaving"] = false
			elif Vector2(pos.x - pp.x, pos.z - pp.z).length() > TROPIC_GONE:
				d["leaving"] = false
				d["gone"] = true
				root.visible = false
				continue
		elif night > 0.68 + shy * 0.5:
			if _tropic_age < 3.0:
				d["gone"] = true        # (the game has begun at night)
				root.visible = false
				continue
			d["leaving"] = true
			d["follow"] = -1
			d["passing"] = false
		d["timer"] = float(d["timer"]) - delta
		var goal: Vector3 = d["goal"]
		# courtship: one follows another of the same rocks, close behind and a little above
		d["next_follow"] = float(d["next_follow"]) - delta
		if int(d["follow"]) < 0 and float(d["next_follow"]) <= 0.0:
			d["next_follow"] = _rng.randf_range(40.0, 110.0)
			for j in tropics.size():
				if j != i and int(tropics[j]["home_i"]) == int(d["home_i"]) and int(tropics[j]["follow"]) < 0 and (tropics[j]["b"]["pos"] as Vector3).distance_to(pos) < 90.0:
					d["follow"] = j
					d["follow_t"] = _rng.randf_range(16.0, 32.0)
					break
		if int(d["follow"]) >= 0:
			var lead: Dictionary = tropics[d["follow"]]["b"]
			goal = (lead["pos"] as Vector3) - Flight.forward(lead["yaw"]) * 2.4 + Vector3(0, 1.0, 0)
			d["follow_t"] = float(d["follow_t"]) - delta
			if float(d["follow_t"]) <= 0.0:
				d["follow"] = -1
				d["timer"] = 0.0
		else:
			# a sweep in past the nest, now and then
			d["pass_t"] = float(d["pass_t"]) - delta
			if float(d["pass_t"]) <= 0.0 and not d["passing"]:
				d["pass_t"] = _rng.randf_range(70.0, 160.0)
				var mine: Array = []
				for s: Dictionary in sitters:
					if int(s["home"]) == int(d["home_i"]):
						mine.append(s)
				if not mine.is_empty():
					var s: Dictionary = mine[_rng.randi() % mine.size()]
					d["goal"] = (s["pos"] as Vector3) + (s["out"] as Vector3) * 7.0 + Vector3(0, 3.5, 0)
					d["passing"] = true
					d["timer"] = 40.0
					goal = d["goal"]
			if float(d["timer"]) <= 0.0 or Vector2(goal.x - pos.x, goal.z - pos.z).length() < 9.0:
				d["goal"] = _tropic_goal(d["home"])
				d["passing"] = false
				d["timer"] = _rng.randf_range(12.0, 30.0)
				goal = d["goal"]
		if d["leaving"]:
			goal = d["sea"]
			d["goal"] = goal
			d["timer"] = 30.0
			d["pass_t"] = maxf(float(d["pass_t"]), 60.0)
			d["next_follow"] = maxf(float(d["next_follow"]), 60.0)
		# clear of the ground and the trees below and ahead (not on the pass at the nest)
		if not d["passing"] or Vector2(goal.x - pos.x, goal.z - pos.z).length() > 30.0:
			var ahead: Vector3 = pos + Flight.forward(b["yaw"]) * 22.0
			var g := maxf(maxf(_ground(pos.x, pos.z), _ground(ahead.x, ahead.z)), 0.0)
			goal.y = maxf(goal.y, g + 13.0)
		var w := Flight.wind(gust, pos.y)
		Flight.steer(b, goal, delta, w, TROPIC)
		# quick shallow beats, and short glides between them (longer when it is going down)
		d["glide"] = float(d["glide"]) - delta
		if float(d["glide"]) < -1.4:
			d["glide"] = _rng.randf_range(2.5, 7.0)
		var gliding: bool = float(d["glide"]) < 0.0 or float(b["vy"]) < -1.2
		var effort := clampf(0.55 + 0.25 * float(b["vy"]), 0.3, 0.9)
		d["amp"] = lerpf(float(d["amp"]), 0.1 if gliding else effort * 0.62, 1.0 - exp(-4.0 * delta))
		d["flap"] = fmod(float(d["flap"]) + TAU * 4.3 * delta, TAU)
		var pose := Flight.beat(d["flap"], d["amp"])
		root.global_transform = Transform3D(Flight.attitude(b), (b["pos"] as Vector3) + Vector3(0, float(pose[3]) * 0.012 * float(d["amp"]), 0))
		Flight.pose(d["wings"], 0.1 + float(pose[0]), float(pose[1]), 0.04 + float(pose[2]) * 0.8, float(pose[4]) * 0.8)
		# the streamers trail and swing with the turns
		var st: Node3D = d["streamers"]
		if st:
			st.rotation = Vector3(-0.06 - 0.5 * atan2(float(b["vy"]), 9.0) + 0.03 * sin(_time * 5.0 + float(d["seed"])),
				clampf(float(b["bank"]) * 0.5, -0.4, 0.4) + 0.05 * sin(_time * 3.1 + float(d["seed"])), 0)
		d["call_t"] = float(d["call_t"]) - delta
		if float(d["call_t"]) <= 0.0:
			d["call_t"] = _rng.randf_range(12.0, 45.0) if int(d["follow"]) < 0 else _rng.randf_range(4.0, 10.0)
			if night < 0.3 and d["voice"] != null:
				_call(d["voice"], "tropicbird")
	# the sitting birds look about them; they do not leave the nest for a walker (birds of
	# islands without enemies sit tight): one who comes near is watched, that is all
	var pp := _player.global_position if _player else NONE
	for s: Dictionary in sitters:
		# (the whole bird turns, tail and all: those that lie against a tree turn only a
		# little, or their long tail feathers would sweep through its foot)
		var swing := 0.45 if int(s["home"]) == 9 else 1.0
		var want: float = float(s["yaw0"]) + swing * (0.35 * sin(_time * 0.23 + float(s["seed"])) + 0.1 * sin(_time * 0.9 + float(s["seed"]) * 2.0))
		var to_p := Vector3(pp.x - (s["pos"] as Vector3).x, 0, pp.z - (s["pos"] as Vector3).z)
		if to_p.length() < 4.5 and absf(pp.y - (s["pos"] as Vector3).y) < 3.0:
			want = float(s["yaw0"]) + clampf(angle_difference(float(s["yaw0"]), atan2(-to_p.x, -to_p.z)), -0.5 * swing, 0.5 * swing)
		s["yaw"] = float(s["yaw"]) + clampf(angle_difference(float(s["yaw"]), want), -0.9 * delta, 0.9 * delta)
		(s["root"] as Node3D).rotation.y = s["yaw"]
		# a tropicbird on its nest scolds whoever comes close: a harsh chatter, now and then
		s["chat_t"] = float(s.get("chat_t", 2.0)) - delta
		if to_p.length() < 3.5 and float(s["chat_t"]) <= 0.0 and _night() < 0.5:
			s["chat_t"] = _rng.randf_range(5.0, 11.0)
			if _nest_voice == null:
				_nest_voice = _voice(self, 4.0, 45.0, -7.0)
			if not _nest_voice.playing:
				_nest_voice.global_position = (s["pos"] as Vector3) + Vector3(0, 0.15, 0)
				_call(_nest_voice, "tropicbird")
				nest_chatters += 1
	# the chicks: breathing balls of down that shift a little and look up at who comes by;
	# the noddies on the ground turn their heads
	for c: Dictionary in chicks:
		var n: Node3D = c["node"]
		var want: float = float(c["yaw0"]) + 0.5 * sin(_time * 0.17 + float(c["seed"]))
		var to_p := Vector3(pp.x - (c["pos"] as Vector3).x, 0, pp.z - (c["pos"] as Vector3).z)
		var near := to_p.length() < 3.5
		if near:
			want = atan2(-to_p.x, -to_p.z)
		c["yaw"] = float(c["yaw"]) + clampf(angle_difference(float(c["yaw"]), want), -0.7 * delta, 0.7 * delta)
		c["up"] = lerpf(float(c["up"]), 1.0 if near else 0.0, 1.0 - exp(-1.5 * delta))
		var breath := 1.0 + 0.035 * sin(_time * 2.6 + float(c["seed"]))
		n.transform = Transform3D((Basis(Vector3.UP, float(c["yaw"])) * Basis(Vector3.RIGHT, 0.22 * float(c["up"]))).scaled(Vector3(1.0, breath, 1.0) * float(c["size"])), c["pos"])
	for g: Dictionary in ground_noddies:
		(g["node"] as Node3D).rotation.y = float(g["yaw0"]) + 0.3 * sin(_time * 0.31 + float(g["seed"])) + 0.12 * sin(_time * 1.3 + float(g["seed"]) * 3.0)


func _process(delta: float) -> void:
	if not _placed or _player == null:
		return
	delta = minf(delta, 0.1)
	_time += delta
	_update_tropicbirds(delta)
	_update_sooty(delta)
	_update_heron(delta)
	for f: Dictionary in flocks:
		_update_flock(f, delta)


## For the tests: walks the first bird of every flock straight at each stone that stands on
## the wet sand (from 1.6 m on one side to a goal 1.6 m on the other, for 20 s of its time)
## and says whether it ever stood in the stone and whether it got around. The player must be
## some 30 m away (near enough for the flock to stay, too far to disturb it).
func stone_test() -> Dictionary:
	var res := {"stones on the wet sand": 0}
	var stones: Array = []
	for bs: Array in _ls.boulder_spots:
		var c: Vector3 = bs[0]
		var g := _ground(c.x, c.z)
		if g > -0.05 and g < 0.3 and _solid(c.x, c.z) and stones.size() < 6:
			stones.append(c)
	res["stones on the wet sand"] = stones.size()
	for f: Dictionary in flocks:
		var inside := 0
		var arrived := 0
		var gave_up := 0
		for c: Vector3 in stones:
			var along := Vector3(-_seaward(c).z, 0, _seaward(c).x)
			if along == Vector3.ZERO:
				along = Vector3(0, 0, 1)
			var b: Dictionary = (f["birds"] as Array)[0]
			for other: Dictionary in f["birds"]:
				other["state"] = "stand"
				other["goal"] = NONE
				other["wait"] = 1e6
				other["pos"] = c + along * 6.0
				(other["root"] as Node3D).visible = true
			f["center"] = c
			f["drift"] = 1e6
			f["away_t"] = -1e6
			var from := c - along * 1.6
			var goal := c + along * 1.6
			# (the far side must be free ground, or there is nowhere to go)
			if _solid(goal.x, goal.z) or _solid(from.x, from.z):
				continue
			b["pos"] = Vector3(from.x, _ground(from.x, from.z), from.z)
			b["goal"] = goal
			b["peck_t"] = 0.0
			var done := false
			for i in 400:
				_update_flock(f, 0.05)
				var p: Vector3 = b["pos"]
				if _solid(p.x, p.z):
					inside += 1
				if b["goal"] == NONE:
					done = true
					if Vector2(p.x - goal.x, p.z - goal.z).length() < 0.15:
						arrived += 1
					else:
						gave_up += 1
					break
			if not done:
				gave_up += 1
		res[f["kind"]] = {"steps inside a stone": inside, "got around": arrived, "gave up": gave_up}
	for f: Dictionary in flocks:
		f["center"] = NONE
		f["away_t"] = 0.0
		f["drift"] = 5.0
		for b: Dictionary in f["birds"]:
			b["wait"] = 1.0
	return res


## For the tests: where everybody is and what they have done.
func report() -> Dictionary:
	var pp := _player.global_position if _player else Vector3.ZERO
	var out := {}
	for f: Dictionary in flocks:
		var flying := 0
		var lo := 99.0
		var hi := -99.0
		var nearest := 1e9
		for b: Dictionary in f["birds"]:
			var p: Vector3 = b["pos"]
			if b["state"] == "fly":
				flying += 1
			else:
				lo = minf(lo, _ground(p.x, p.z))
				hi = maxf(hi, _ground(p.x, p.z))
			nearest = minf(nearest, Vector2(p.x - pp.x, p.z - pp.z).length())
		out[f["kind"]] = {"center": f["center"], "flying": flying, "ground under them": [lo, hi], "nearest to the player": nearest,
			"flushes": f["flushes"], "arrivals": f["arrivals"]}
	if not heron.is_empty():
		out["heron"] = {"state": heron["state"], "pool": heron_spots[heron["site"]]["pool"], "at home": heron["site"] == heron["home"], "pos": heron["pos"],
			"from the player": (heron["pos"] as Vector3).distance_to(pp), "flushes": heron["flushes"]}
	var clear := 1e9
	var far := 0.0
	for d: Dictionary in tropics:
		var p: Vector3 = d["b"]["pos"]
		clear = minf(clear, p.y - maxf(_ground(p.x, p.z), 0.0))
		far = maxf(far, Vector2(p.x - (d["home"] as Vector3).x, p.z - (d["home"] as Vector3).z).length())
	out["tropicbirds"] = {"flying": tropics.size(), "on nests": sitters.size(), "least height above the ground": clear, "furthest from their rocks": far}
	return out
