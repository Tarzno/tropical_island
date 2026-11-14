extends Node3D
## Small schools of reef fish in the shallows near the player. Every fish steers for itself: it
## holds a loose place in its school, keeps clear of its neighbors and swims the way they swim,
## moves in bursts and glides, is rocked to and fro by the swell, and escapes a wader with a
## fast-start. Each species has its own habits: tangs travel in a file near the bottom, sergeant
## majors (the Indo-Pacific sergeant, Abudefduf vaigiensis) mill in mid-water, parrotfish nose down to graze, chromis hang in a cloud over one spot
## and drop to the bottom when alarmed. They stay between the sand and the surface.
## A snorkeler with the face in the water hears the parrotfish bite the coral.
## By day, that is. These are all fish of the day: at dusk each school goes down to a coral
## or a rock near by and stays there, close together and low, hardly moving, until dawn
## (tangs and parrotfish sleep in the reef's crevices, chromis among the coral's branches).
## Nobody grazes at night, and no school comes to look at a wader.

@export var player_path: NodePath = ^"../Player"
@export var school_count := 7

const Heights := preload("res://scripts/heights.gd")

# species: mesh name, pattern id, length scale range, school size range, habits
#   cruise: traveling speed (m/s); spread: size of the school; align: how strongly they swim as one;
#   level: where in the water column (0 bottom .. 1 surface); len: length of the mesh (m)
const SPECIES := [
	["FishDisc", 0, Vector2(1.2, 1.6), Vector2i(4, 8), {"cruise": 0.5, "spread": 1.1, "align": 1.0, "level": 0.3, "len": 0.22}],    # blue tang
	["FishDisc", 1, Vector2(0.95, 1.25), Vector2i(7, 12), {"cruise": 0.45, "spread": 1.0, "align": 1.0, "level": 0.28, "len": 0.22}],   # convict surgeonfish (it was a yellow tang, a fish of the Pacific, until 2026-11-12)
	["FishOval", 2, Vector2(1.2, 1.6), Vector2i(8, 14), {"cruise": 0.35, "spread": 1.3, "align": 0.5, "level": 0.62, "len": 0.176}],   # Indo-Pacific sergeant (Abudefduf vaigiensis)
	["FishLong", 3, Vector2(1.4, 2.0), Vector2i(2, 4), {"cruise": 0.35, "spread": 1.5, "align": 0.3, "level": 0.1, "len": 0.31, "graze": true}],    # parrotfish
	["FishOval", 4, Vector2(0.6, 0.8), Vector2i(14, 24), {"cruise": 0.4, "spread": 0.75, "align": 0.4, "level": 0.5, "len": 0.176, "hover": true}], # chromis
]

## The swell runs in toward the beach; fish are carried to and fro along this line.
const SURGE_DIR := Vector3(-0.984, 0.0, 0.177)

var _player: Node3D
var _sea: Node
var _big: Array = []          # the big animals fish give way to, this frame (SeaLife.big_bodies())
var _sea_knows := false     # SeaLife is there and answers for corals and the boat (asked once)
var _rng := RandomNumberGenerator.new()
var _mm := {}           # mesh name -> MultiMesh
var _schools: Array = []
var _fish_by_mesh := {} # mesh name -> Array of fish dicts
var _frame := 0
var _crunches: Array[AudioStream] = []
var _crunch_players: Array[AudioStreamPlayer3D] = []
var crunches_played := 0      # (for the tests)
var _tide := 0.0              # the sea's level now (SeaLife has it from scripts/tide.gd)
var _daycycle: Node
## A school that is brought back to the walker is set down where it cannot be watched
## appearing (false: anywhere 9-22 m off, as it was until 2026-11-12: for the tests).
var unseen_only := true
## (for the tests) schools brought back: set down near and unseen, set down further out
## to swim in, searches that found no unseen place (the school waits), and, with
## `unseen_only` off, how many were set down in plain sight
var moves := {"near": 0, "far": 0, "no place": 0, "in sight": 0}


func _ready() -> void:
	_rng.randomize()
	_player = get_node_or_null(player_path)
	_sea = get_node_or_null("../SeaLife")
	_sea_knows = _sea != null and _sea.has_method("_coral") and _sea.has_method("_boat")
	var scene := load("res://assets/models/fish.glb") as PackedScene
	var tmp := scene.instantiate()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fish.gdshader")
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		_mm[m.name] = mm
		_fish_by_mesh[m.name] = []
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 400.0
		add_child(mmi)
	tmp.free()
	# the parrotfish's bite, heard under water only ("Hydro": the one bus that is not muffled there)
	for i in 6:
		var path := "res://assets/audio/crunch_%d.wav" % i
		if ResourceLoader.exists(path):
			_crunches.append(load(path))
	if not _crunches.is_empty():
		for i in 3:
			var cp := AudioStreamPlayer3D.new()
			cp.bus = "Hydro" if AudioServer.get_bus_index("Hydro") >= 0 else "Master"
			cp.unit_size = 3.0
			cp.max_distance = 16.0
			cp.volume_db = -9.0
			add_child(cp)
			_crunch_players.append(cp)
	for i in school_count:
		_schools.append(_new_school(i % SPECIES.size()))
	for name_ in _mm:
		var mm: MultiMesh = _mm[name_]
		mm.instance_count = _fish_by_mesh[name_].size()


func _ground(x: float, z: float) -> float:
	# (the shared height map, with the .blend's rocks; beyond it -9: no water for a fish.
	# Against the sea as it stands now: everything here is worked out as if the sea were at
	# 0, and the node itself is lifted to the tide's level in _process())
	return Heights.with_rocks(x, z, -9.0 + _tide) - _tide


## The top of the coral at (x, z), as `_ground()` gives the ground (-99: none stands there).
## Corals are solid to the fish: they swim over them, or around them (sealife.gd keeps the
## map's reading: `_coral()`).
func _coral(x: float, z: float) -> float:
	return float(_sea._coral(x, z)) if _sea_knows else -99.0


const NO_WATER := Vector3(1e9, 0, 0)
## Beyond this distance from the player a school is moved at a third of the frame rate
## (for the tests: 1e9 is how it was, every school on every frame).
var far_school := 60.0

## A random point in water 0.7..4.5 m deep around `around`. Widens the search ring
## step by step; returns NO_WATER (never a point on land) if there is none.
func _water_spot(around: Vector3, rmin: float, rmax: float) -> Vector3:
	for ring in 4:
		var r0 := rmin * pow(2.0, ring)
		var r1 := rmax * pow(2.0, ring)
		for i in 30:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(r0, r1)
			var p := around + Vector3(cos(a) * r, 0, sin(a) * r)
			var g := _ground(p.x, p.z)
			# (a school's place is over open floor, not in a coral)
			if g < -0.7 and g > -4.5 and _coral(p.x, p.z) < -90.0:
				return Vector3(p.x, g * 0.5, p.z)
	return NO_WATER


## Would a school that appeared at `p` (in this node's own measure: the sea at 0) be seen
## appearing? Not if it is outside the picture (with a margin: a school is two or three
## meters across), not behind the land or a rock, and not where the water itself hides
## it: under water sight ends at some 25 m (underwater.gdshader), and from above the eye
## looks along the surface at a distance, into the sky's reflection.
func _seen(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var eye := cam.global_position
	var w := Vector3(p.x, p.y + _tide, p.z)
	var to := w - eye
	var d := to.length()
	if d < 1.0:
		return true
	var size := get_viewport().get_visible_rect().size
	var corner := atan(tan(deg_to_rad(cam.fov) * 0.5) * Vector2(size.x / maxf(size.y, 1.0), 1.0).length())
	if (-cam.global_transform.basis.z).angle_to(to) > corner + 0.2:
		return false
	if eye.y < _tide:
		if d > 34.0:
			return false
	elif d > 30.0 and (eye.y - _tide) / d < 0.105:      # (6 degrees to the surface)
		return false
	var top := Vector3(p.x, _tide, p.z)
	var q := PhysicsRayQueryParameters3D.create(eye, top, 1)
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Where to set a school down near the walker at `pp`, unseen: close by if there is such
## a place (behind the walker, behind a rock), else further out, where the water hides it.
## NO_WATER if every place tried is in sight.
func _unseen_spot(pp: Vector3) -> Vector3:
	for ring in 3:
		var r0 := 9.0 * pow(2.0, ring)
		var r1 := minf(22.0 * pow(2.0, ring), 58.0)
		for i in 24:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(r0, r1)
			var x := pp.x + cos(a) * r
			var z := pp.z + sin(a) * r
			var g := _ground(x, z)
			if g < -0.7 and g > -4.5 and _coral(x, z) < -90.0:
				var p := Vector3(x, g * 0.5, z)
				if not _seen(p):
					return p
	return NO_WATER


## A place for a school to spend the night near `c`: beside a coral or a rock that stands
## well under the surface, the nearest of some tries (or where the school is, if there is none).
func _bed_near(c: Vector3) -> Vector3:
	var best := c
	var best_d := 1e9
	for i in 40:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 14.0)
		var p := Vector3(c.x + cos(a) * r, 0, c.z + sin(a) * r)
		var g := _ground(p.x, p.z)
		if g > -0.9 or g < -5.0 or _coral(p.x, p.z) > -90.0:
			continue
		# (open floor here, and something standing within a meter of it)
		var cover := false
		for k in 6:
			var t := _coral(p.x + cos(k * 1.047) * 0.9, p.z + sin(k * 1.047) * 0.9)
			if t > -90.0 and t < -0.5:
				cover = true
		if cover and r < best_d:
			best_d = r
			best = Vector3(p.x, g * 0.5, p.z)
	return best


func _new_school(sp: int) -> Dictionary:
	var spec: Array = SPECIES[sp]
	var prm: Dictionary = spec[4]
	var center := _water_spot(_player.global_position if _player else Vector3(8, 0, 20), 4.0, 30.0)
	if center == NO_WATER:
		center = _water_spot(Vector3(12, 0, 20), 2.0, 20.0)
	var size := _rng.randi_range(spec[3].x, spec[3].y)
	var fish: Array = []
	for i in size:
		var a := _rng.randf() * TAU
		var size_k := _rng.randf_range(spec[2].x, spec[2].y)
		var f := {
			"pos": center + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1.5, 1.5)),
			"vel": Vector3(cos(a), 0, sin(a)) * 0.2,
			"head": Vector3(cos(a), 0, sin(a)),
			# its place in the school, and how it roams around that place
			"offset": Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.25, 0.25), _rng.randf_range(-1.2, 1.2)),
			"n1": _rng.randf() * TAU, "n2": _rng.randf() * TAU,
			"w1": _rng.randf_range(0.25, 0.6) * (1.6 if prm.get("hover", false) else 1.0),
			"w2": _rng.randf_range(0.2, 0.5) * (1.6 if prm.get("hover", false) else 1.0),
			"scale": size_k, "len": float(prm["len"]) * size_k,
			"phase": _rng.randf(), "amp": 0.2,
			"species": spec[1],
			"turn": 0.5,
			"thrust": _rng.randf() < 0.5, "burst_t": _rng.randf_range(0.2, 1.2),
			"startle": 0.0, "grazing": false, "graze_t": _rng.randf_range(2.0, 8.0),
			"sep": Vector3.ZERO, "ali": Vector3.ZERO, "g": -2.0,
			"basis": Basis(),
		}
		fish.append(f)
		_fish_by_mesh[spec[0]].append(f)
	return {"species": sp, "prm": prm, "center": center, "target": center, "fish": fish, "vel": Vector3.ZERO,
		"alarm": 0.0, "speed": float(prm["cruise"]) * _rng.randf_range(0.85, 1.2), "timer": _rng.randf_range(4.0, 10.0)}


func _process(delta: float) -> void:
	if _player == null:
		return
	delta = minf(delta, 0.1)
	_frame += 1
	_tide = _sea.tide if _sea and "tide" in _sea else 0.0
	if _daycycle == null:
		_daycycle = get_node_or_null("../DayCycle")
	var asleep: bool = _daycycle != null and float(_daycycle.get("night")) > 0.6
	position.y = _tide
	var pp := _player.global_position - Vector3(0, _tide, 0)
	# (in it, not on a boulder that stands in it: the feet near the surface or under it)
	var player_in_water := _ground(pp.x, pp.z) < 0.05 and pp.y < 0.5
	var moved_any := false
	_big = _sea.big_bodies() if _sea_knows and _sea.has_method("big_bodies") else []
	for s in _schools:
		var prm: Dictionary = s["prm"]
		var hover: bool = prm.get("hover", false)
		# far away schools are moved back into the shallows near the player
		var c: Vector3 = s["center"]
		var far_limit := 30.0 if player_in_water else 70.0
		var away_dist := Vector2(c.x - pp.x, c.z - pp.z).length()
		if away_dist > far_limit:
			# only follow the player if there is water near them (inland: stay in the sea),
			# and only to where nobody watches them appear: a school looks for such a
			# place once a second, and stays where it is until there is one
			var nc := NO_WATER
			if not unseen_only:
				nc = _water_spot(pp, 9.0, 22.0)
				if nc != NO_WATER and Vector2(nc.x - pp.x, nc.z - pp.z).length() < 60.0 and _seen(nc):
					moves["in sight"] += 1
			else:
				s["look_t"] = float(s.get("look_t", _rng.randf())) - delta
				if float(s["look_t"]) <= 0.0:
					s["look_t"] = 1.0
					nc = _unseen_spot(pp)
					if nc == NO_WATER:
						moves["no place"] += 1
			if nc != NO_WATER and Vector2(nc.x - pp.x, nc.z - pp.z).length() < 60.0:
				# regroup around the new center (always in water): keeping each fish's old offset
				# from the center could put a straggler on the beach
				for f in s["fish"]:
					var fp: Vector3 = nc + Vector3(f["offset"].x, 0.0, f["offset"].z) * 0.5
					# (not set down inside a coral: above it, or, if it comes up to the
					# surface, at the school's own place, which is over open floor)
					var fct := _coral(fp.x, fp.z)
					if fct > -0.4:
						fp = nc
					elif fct > -90.0:
						fp.y = maxf(fp.y, fct + 0.2)
					f["pos"] = fp
					f["vel"] = Vector3.ZERO
					f["g"] = -2.0
				s["center"] = nc
				s["target"] = nc
				s["vel"] = Vector3.ZERO
				c = nc
				# (a bed for the night is found anew, by the new place: the old one is far off)
				s.erase("bed")
				var off := Vector2(nc.x - pp.x, nc.z - pp.z).length()
				moves["near" if off <= 22.5 else "far"] += 1
				if off > 22.5:
					# set down far out, where the water hides it: it swims in to the
					# walker's shallows from there
					var goal := _water_spot(pp, 9.0, 22.0)
					if goal != NO_WATER and Vector2(goal.x - pp.x, goal.z - pp.z).length() < 30.0:
						s["target"] = goal
						s["timer"] = Vector2(goal.x - nc.x, goal.z - nc.z).length() / maxf(float(s["speed"]), 0.1) + 5.0
			elif away_dist > 120.0:
				continue   # far out of sight (the player is inland): leave them be
		# (a school more than sixty meters from anybody is a few specks at most: it is
		# moved on every third frame, by three frames' time: a twentieth of a second, the
		# step the soaks run at)
		var dt := delta
		if Vector2(c.x - pp.x, c.z - pp.z).length() > far_school:
			if _frame % 3 != 0:
				continue
			dt = minf(delta * 3.0, 0.1)
		moved_any = true
		# night: down to a bed, and there till morning (it settles over a quarter of a minute)
		s["sleep"] = move_toward(float(s.get("sleep", 0.0)), 1.0 if asleep else 0.0, dt / 15.0)
		if asleep and not s.has("bed"):
			s["bed"] = _bed_near(c)
			s["target"] = s["bed"]
		elif not asleep and s.has("bed"):
			s.erase("bed")
			s["timer"] = 0.0
		if asleep:
			s["timer"] = 5.0          # (no new place to go to, and no wader to look at)
		s["timer"] -= dt
		# (something that reaches the surface has come over the school's place: the boat,
		# swinging at its anchor. Away from under it)
		if _coral(c.x, c.z) > -0.7 and float(s["timer"]) > 0.5:
			s["timer"] = 0.0
		var to_t: Vector3 = s["target"] - c
		if s["timer"] <= 0.0 or (to_t.length() < 1.0 and not hover):
			# curious fish: while someone wades, schools roam around them at a few meters
			var nt := _water_spot(pp, 4.0, 11.0) if player_in_water and _rng.randf() < 0.75 else _water_spot(c, 3.0, 14.0)
			if nt != NO_WATER:
				s["target"] = nt
			# chromis keep to one coral head for a long while before moving on
			s["timer"] = _rng.randf_range(18.0, 40.0) if hover else _rng.randf_range(5.0, 12.0)
		var speed: float = s["speed"]
		# flee from a wader
		var away := Vector3(c.x - pp.x, 0, c.z - pp.z)
		# (asleep, they give way only to somebody right upon them, and come back to their bed)
		var fleeing := player_in_water and away.length() < (1.6 if asleep else 3.5)
		if fleeing:
			s["target"] = c + away.normalized() * 8.0
			speed = 1.1      # (they give way; they do not scatter at full speed)
		elif asleep:
			s["target"] = s["bed"]
			speed *= 0.6
		var old_c := c
		to_t = s["target"] - c
		to_t.y = 0.0
		var g := _ground(c.x, c.z)
		if to_t.length() > 0.3:
			var step: Vector3 = to_t.normalized() * speed * dt
			g = _ground(c.x + step.x, c.z + step.z)
			# (a rock or a coral that reaches up to the surface is no place for a school
			# either: its middle keeps out of it as out of the shallows, or the fish
			# would be sent to places inside it)
			if (g > -0.6 and g >= _ground(c.x, c.z) - 0.001) or (_coral(c.x + step.x, c.z + step.z) > -0.7 and _coral(c.x, c.z) <= -0.7):
				# too shallow ahead: stay put and pick a deeper goal (unless the tide has
				# fallen under the school: then any way down is the way)
				var nt2 := _water_spot(c, 2.0, 10.0)
				if nt2 != NO_WATER:
					s["target"] = nt2
				g = _ground(c.x, c.z)
			else:
				c += step
		c.y = lerpf(c.y, clampf(g * 0.5, g + 0.25, -0.3), 1.0 - exp(-dt))
		s["center"] = c
		var moved := (c - old_c) / maxf(dt, 0.001)
		moved.y = 0.0
		s["vel"] = (s["vel"] as Vector3).lerp(moved, 1.0 - exp(-2.0 * dt))
		s["alarm"] = move_toward(s["alarm"], 1.0 if fleeing else 0.0, dt * (4.0 if fleeing else 0.2))
		# the swell: under a crest the water moves with the wave, under a trough against it
		var eta: float = _sea.wave_height(c.x, c.z) if _sea else 0.0
		var surge := SURGE_DIR * clampf(eta * sqrt(9.81 / maxf(-g, 0.7)), -0.35, 0.35)
		_update_fish(s, dt, pp, player_in_water, surge, fleeing)
	if moved_any:
		_write_instances()


func _update_fish(s: Dictionary, delta: float, pp: Vector3, wading: bool, surge: Vector3, fleeing: bool) -> void:
	var prm: Dictionary = s["prm"]
	var c: Vector3 = s["center"]
	var svel: Vector3 = s["vel"]
	var alarm: float = s["alarm"]
	var fish: Array = s["fish"]
	var n := fish.size()
	var cruise: float = prm["cruise"]
	var align: float = prm["align"]
	var hover: bool = prm.get("hover", false)
	var grazer: bool = prm.get("graze", false)
	# alarmed fish close up; alarmed chromis drop down together toward the coral
	var spread: float = float(prm["spread"]) * lerpf(1.0, 0.55, alarm)
	var level: float = lerpf(float(prm["level"]), 0.1, alarm) if hover else float(prm["level"])
	# (the night: close together, low over their bed)
	var sleep: float = s.get("sleep", 0.0)
	level = lerpf(level, 0.04, sleep)
	spread *= lerpf(1.0, 0.55, sleep)
	var t := Time.get_ticks_msec() * 0.001
	# (the big animals near this school, if any)
	var big: Array = []
	for b: Array in _big:
		if Vector2((b[0] as Vector3).x - c.x, (b[0] as Vector3).z - c.z).length() < float(b[1]) + 5.0:
			big.append(b)
	for i in n:
		var f: Dictionary = fish[i]
		var pos: Vector3 = f["pos"]
		var vel: Vector3 = f["vel"]
		var fg: float = f["g"]
		# safety net: a fish over dry or ankle-deep ground goes straight back into its school
		if fg > -0.25:
			pos = c + Vector3(f["offset"].x, 0.0, f["offset"].z) * 0.3
			# (not into a coral or a rock: above it, or at the school's middle if it
			# reaches up to the surface)
			var sct := _coral(pos.x, pos.z)
			if sct > -0.4:
				pos = Vector3(c.x, pos.y, c.z)
			elif sct > -90.0:
				pos.y = maxf(pos.y, sct + 0.2)
			vel = Vector3.ZERO
			fg = _ground(pos.x, pos.z)
		# neighbors (looked at every fourth frame): keep clear of the nearest, swim as they swim
		if (i + _frame) % 4 == 0:
			var sep := Vector3.ZERO
			var ali := Vector3.ZERO
			var cnt := 0
			var reach: float = float(f["len"]) * 2.2
			for j in n:
				if j == i:
					continue
				var o: Dictionary = fish[j]
				var dv: Vector3 = pos - o["pos"]
				var dl := dv.length()
				if dl < reach * 2.5:
					ali += o["vel"]
					cnt += 1
					if dl < reach and dl > 0.001:
						sep += dv / dl * (1.0 - dl / reach)
			f["sep"] = sep
			f["ali"] = ali / cnt if cnt > 0 else svel
		# its place in the school, which it keeps roaming around
		var roam := Vector3(sin(t * float(f["w1"]) + float(f["n1"])), 0.4 * sin(t * float(f["w2"]) * 1.3 + float(f["n1"])),
			cos(t * float(f["w2"]) + float(f["n2"]))) * 0.4
		var want: Vector3 = c + ((f["offset"] as Vector3) + roam * (1.0 - 0.8 * sleep)) * spread
		# (the bottom, for a fish, is the coral under it where one stands)
		var ct := _coral(pos.x, pos.z)
		var bottom := maxf(fg, ct) + 0.12
		# (the highest it comes: just under the surface; under the anchored boat, under its keel)
		var roof := -0.75 if _sea_knows and _sea._boat(pos.x, pos.z) else -0.15
		var top := maxf(bottom, roof)
		want.y = clampf(lerpf(bottom, top, level) + ((f["offset"] as Vector3).y + roam.y) * spread, bottom, top)
		# parrotfish: bouts of grazing, nose down on the bottom
		var grazing := false
		if grazer:
			f["graze_t"] -= delta
			if f["graze_t"] <= 0.0:
				f["grazing"] = not f["grazing"]
				f["graze_t"] = _rng.randf_range(1.5, 3.5) if f["grazing"] else _rng.randf_range(3.0, 9.0)
			grazing = f["grazing"] and alarm < 0.2 and f["startle"] <= 0.0 and sleep < 0.2
			# every bite at the coral is a crunch (the bout begins with one)
			f["bite_t"] = float(f.get("bite_t", 0.0)) - delta if grazing else 0.3
			if grazing and float(f["bite_t"]) <= 0.0:
				f["bite_t"] = _rng.randf_range(0.7, 1.6)
				# (not every bite carries: a crunch every few seconds, not a rattle)
				if _rng.randf() < 0.5:
					_crunch(pos)
		var to_want := want - pos
		var desired: Vector3 = svel * align + to_want * 0.9 + (f["sep"] as Vector3) * 0.5 + ((f["ali"] as Vector3) - vel) * 0.25 * align
		if grazing:
			desired = Vector3(desired.x * 0.12, 0.0, desired.z * 0.12)
			to_want.y = bottom - 0.03 - pos.y
		desired.y = clampf(to_want.y * 1.2, -0.35, 0.35)
		# burst and glide: a few tail beats, then coasting
		f["burst_t"] -= delta
		if f["burst_t"] <= 0.0:
			f["thrust"] = not f["thrust"]
			f["burst_t"] = _rng.randf_range(0.25, 0.6) if f["thrust"] else _rng.randf_range(0.4, 1.4)
		var thrust: bool = f["thrust"] or fleeing
		desired *= 1.25 if thrust else 0.8
		if not fleeing:
			desired *= 1.0 - 0.7 * sleep         # (resting: it only keeps its place)
		var lim := 1.5 if fleeing else cruise * 2.5
		# out of a big animal's way (an eagle ray, the manta: SeaLife.big_bodies()): to the
		# side of it, and under or over it, as they would part before it. (A ray glided
		# straight through a school: 20 s in nine minutes of an audit.)
		for b: Array in big:
			var off: Vector3 = pos - (b[0] as Vector3)
			var flat := Vector2(off.x, off.z).length()
			var reach: float = float(b[1]) + 0.5
			if flat < reach and absf(off.y) < 0.5:
				var w := 1.0 - smoothstep(reach * 0.5, reach, flat)
				var aside := Vector3(off.x, 0, off.z) / maxf(flat, 0.01)
				desired += aside * (1.8 * w) + Vector3(0, (1.0 if off.y > 0.0 else -1.0) * 0.6 * w * (1.0 - absf(off.y) / 0.5), 0)
				lim = maxf(lim, 1.4)
		if desired.length() > lim:
			desired = desired.normalized() * lim
		# a wader very close: fast-start, bent into a C and gone
		var dp := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
		if wading and dp.length() < 1.6 and f["startle"] <= 0.0:
			var dir := dp.normalized() if dp.length() > 0.01 else Vector3.RIGHT
			vel = dir.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7)) * _rng.randf_range(1.0, 1.5)
			f["startle"] = _rng.randf_range(0.5, 0.9)
			f["turn"] = 0.0 if _rng.randf() < 0.5 else 1.0
			s["alarm"] = 1.0
		var rate := 2.8 if fleeing else (3.0 if thrust else 1.6)
		if f["startle"] > 0.0:
			f["startle"] -= delta
			rate = 1.2   # coasting out of the dash
		vel = vel.lerp(desired, 1.0 - exp(-rate * delta))
		# the swell carries it; a fish never swims into water shallower than 30 cm: turn it around
		var np: Vector3 = pos + (vel + surge) * delta
		var ng := _ground(np.x, np.z)
		if ng > -0.3:
			vel = -vel * 0.5 + (c - pos).normalized() * 0.3
			np = pos
			ng = fg
		# ... and never into a coral: it slips along it and rises over it, or, where the
		# coral comes up to the surface, turns back. (One that is in a coral already, set
		# down there with its school, is not held: it swims up and out.)
		if ct > pos.y - 0.08:
			np.y = minf(maxf(np.y, pos.y + 0.35 * delta), roof)
		elif _coral(np.x, np.z) > np.y - 0.08:
			var slip := Vector3(np.x, np.y, pos.z)
			if _coral(slip.x, slip.z) > np.y - 0.08 or _ground(slip.x, slip.z) > -0.3:
				slip = Vector3(pos.x, np.y, np.z)
				if _coral(slip.x, slip.z) > np.y - 0.08 or _ground(slip.x, slip.z) > -0.3:
					slip = Vector3(pos.x, np.y, pos.z)
			if _coral(np.x, np.z) + 0.2 < -0.15:
				slip.y = minf(maxf(slip.y, pos.y + 0.35 * delta), roof)
				vel.y = maxf(vel.y, 0.25)
			elif slip.x == pos.x and slip.z == pos.z:
				vel = -vel * 0.5 + (c - pos).normalized() * 0.3
			np = slip
			ng = _ground(np.x, np.z)
		np.y = clampf(np.y, ng + 0.12, maxf(ng + 0.12, roof))
		f["pos"] = np
		f["vel"] = vel
		f["g"] = ng
		# heading: along its own swimming (not the surge); hovering fish face the swell
		var head: Vector3 = f["head"]
		var sp := Vector3(vel.x, vel.y * 0.6, vel.z)
		var speed := sp.length()
		var tgt := head
		if speed > 0.07:
			tgt = sp / speed
		elif hover:
			tgt = (-SURGE_DIR + roam * 0.6).normalized()
		if grazing:
			var flat := Vector3(head.x, 0, head.z)
			flat = flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
			tgt = (flat * 0.62 + Vector3.DOWN * (0.72 + 0.12 * sin(t * 8.0 + float(f["n1"])))).normalized()
		var nh := head.slerp(tgt, 1.0 - exp(-(10.0 if f["startle"] > 0.0 else 3.5) * delta)) if head.dot(tgt) > -0.98 else tgt
		nh.y = clampf(nh.y, -0.85, 0.85)
		nh = nh.normalized()
		var yaw_rate := head.cross(nh).y / maxf(delta, 0.001)   # > 0: turning left
		f["head"] = nh
		# the body bends into the turn (tail to the inside) and rolls a little
		f["turn"] = lerpf(f["turn"], 0.5 - clampf(yaw_rate * 0.22, -0.5, 0.5), 1.0 - exp(-9.0 * delta))
		f["basis"] = Basis.looking_at(nh, Vector3.UP) * Basis(Vector3.FORWARD, clampf(-yaw_rate * 0.1, -0.3, 0.3))
		# tail: beat rate follows the speed (about 0.75 body lengths per beat); idle sculling otherwise
		var vlen := vel.length()
		var beating: bool = thrust or vlen > 1.0
		var freq := minf(0.6 + vlen / (float(f["len"]) * 0.75), 9.0) if beating else 0.5
		f["phase"] = fposmod(f["phase"] + freq * delta, 1.0)
		f["amp"] = lerpf(f["amp"], clampf(vlen / 1.4, 0.14, 1.0) if beating else 0.07, 1.0 - exp(-7.0 * delta))


## For the tests: how many schools were brought back to the walker and how (`moves`), and
## where each is now: its distance from the walker, and whether a school appearing there
## would be seen (`_seen()`).
func move_report() -> Dictionary:
	var pp := _player.global_position - Vector3(0, _tide, 0)
	var out := {"moves": moves.duplicate(), "unseen only": unseen_only, "schools": []}
	for s in _schools:
		var c: Vector3 = s["center"]
		(out["schools"] as Array).append("%.0f m at (%.0f, %.0f)%s" % [Vector2(c.x - pp.x, c.z - pp.z).length(), c.x, c.z, " in sight" if _seen(c) else ""])
	return out


## For the tests: how the schools are now: asleep or not, how high over the floor (or the
## coral) under them their fish are, how fast they swim, how far from their school's middle.
func night_report() -> Dictionary:
	var out := {"crunches so far": crunches_played, "schools": []}
	for s in _schools:
		var h := 0.0
		var v := 0.0
		var r := 0.0
		var c: Vector3 = s["center"]
		for f in s["fish"]:
			var p: Vector3 = f["pos"]
			h += p.y - maxf(_ground(p.x, p.z), _coral(p.x, p.z))
			v += (f["vel"] as Vector3).length()
			r += Vector2(p.x - c.x, p.z - c.z).length()
		var n := float((s["fish"] as Array).size())
		(out["schools"] as Array).append(["sleep %.2f" % float(s.get("sleep", 0.0)), "over the floor %.2f m" % (h / n), "speed %.2f m/s" % (v / n), "from the middle %.2f m" % (r / n), "bed" if s.has("bed") else "no bed"])
	return out


## A parrotfish has bitten off a piece of coral at `at`: whoever has the face in the water
## nearby hears it.
func _crunch(at: Vector3) -> void:
	if _crunch_players.is_empty() or _player == null or not _player.get("underwater"):
		return
	if at.distance_to(_player.global_position - Vector3(0, _tide, 0)) > 11.0:
		return
	for cp in _crunch_players:
		if not cp.playing:
			cp.stream = _crunches[_rng.randi() % _crunches.size()]
			cp.global_position = at + Vector3(0, _tide, 0)
			cp.pitch_scale = _rng.randf_range(0.82, 1.12)
			cp.play()
			crunches_played += 1
			return


func _write_instances() -> void:
	for name_ in _mm:
		var mm: MultiMesh = _mm[name_]
		var list: Array = _fish_by_mesh[name_]
		for i in list.size():
			var f: Dictionary = list[i]
			mm.set_instance_transform(i, Transform3D((f["basis"] as Basis).scaled(Vector3.ONE * f["scale"]), f["pos"]))
			mm.set_instance_custom_data(i, Color(float(f["species"]) / 255.0, f["phase"], f["amp"], f["turn"]))
