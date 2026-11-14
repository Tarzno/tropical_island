extends Node3D
## Terns fishing along the beach (patrolling, hovering on the wind, plunge-diving), ghost crabs
## on the damp sand that bolt for their burrows, flying foxes at night, and the anchored boat.

const A := "res://assets/audio/"
const Heights := preload("res://scripts/heights.gd")
const Flight := preload("res://scripts/flight.gd")
const SmallModels := preload("res://scripts/small_models.gd")

@export var player_path: NodePath = ^"../Player"
@export var tern_count := 10
@export var crab_count := 9

var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _terns: Array[Dictionary] = []
var _crabs: Array[Dictionary] = []
var _tern_calls: Array[AudioStream] = []
var _noddy_calls: Array[AudioStream] = []
var _far_player: AudioStreamPlayer3D
var _far_timer := 8.0
var far_calls := 0            # (for the tests)
var far_last := Vector3.ZERO
var _world: Node
var _sea: Node
var _amb: Node


func _ready() -> void:
	_rng.randomize()
	_player = get_node_or_null(player_path)
	_world = get_parent()
	_sea = get_node_or_null("../SeaLife")
	_amb = get_node_or_null("../Ambience")
	for i in 10:
		var p := A + "tern_%d.wav" % i
		if ResourceLoader.exists(p):
			_tern_calls.append(load(p))
	# far-off calls of the sea's birds (see _far_call())
	for i in 10:
		var np := A + "noddy_%d.wav" % i
		if ResourceLoader.exists(np):
			_noddy_calls.append(load(np))
	_far_player = AudioStreamPlayer3D.new()
	_far_player.unit_size = 40.0
	_far_player.max_distance = 700.0
	_far_player.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	add_child(_far_player)
	_spawn_terns()
	_spawn_crabs()
	_spawn_boat()
	_init_bats()


func _ground(x: float, z: float) -> float:
	return Heights.terrain(x, z, -9.0)


func _apply_mats(n: Node) -> void:
	if _world and _world.has_method("get_material") and n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src:
				var m: Material = _world.get_material(src.resource_name)
				if m:
					mi.set_surface_override_material(s, m)
	for c in n.get_children():
		_apply_mats(c)


# ------------------------------------------------------------------ terns
## Flight envelope of a crested tern (see flight.gd).
const TERN := {"cruise": 8.2, "max_bank": 0.95, "roll": 3.2, "climb": 2.6, "sink": 3.5}

## At dusk the terns fly out to sea, to roost on a sandbank beyond the reef, and at dawn they
## come back in: one after the other, each from where it is. (They used to be switched off
## in mid-air when `night` passed 0.5, and on again at dawn: the code review of 2026-11-12.)
## The place they make for, and how far from the walker a tern has to be before it is taken
## out of the sky (a speck by then, in the dusk).
const TERN_ROOST := Vector3(720.0, 16.0, -20.0)
const TERN_GONE := 600.0
var _started := 0.0

var _splashes: Array[CPUParticles3D] = []
var _splash_voice: AudioStreamPlayer3D
var _splash_sounds: Array[AudioStream] = []


func _wind(height: float) -> Vector3:
	return Flight.wind(_amb.gust if _amb else 1.0, height)


## The level of the sea now (the tide).
func _tide() -> float:
	return float(_sea.tide) if _sea and "tide" in _sea else 0.0


func _sea_level(x: float, z: float) -> float:
	return _sea.surface(x, z) if _sea else 0.0


func _spawn_terns() -> void:
	# greater crested terns (the model is in seabirds.glb with the other seabirds)
	var birds := (load("res://assets/models/seabirds.glb") as PackedScene).instantiate()
	var proto := birds.find_child("CrestedTern", true, false) as Node3D
	for i in tern_count:
		var root := Node3D.new()
		add_child(root)
		var model := proto.duplicate() as Node3D
		model.transform = Transform3D.IDENTITY
		root.add_child(model)
		_apply_mats(model)
		var wings := Flight.wings(model, "Tern", "CrestedTernWingL", "CrestedTernWingR", _world)
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = 14.0
		voice.max_distance = 220.0
		voice.volume_db = -6.0
		root.add_child(voice)
		var pos := Vector3(_rng.randf_range(4, 50), _rng.randf_range(6, 13), _rng.randf_range(-75, 65))
		var d := {
			"node": root, "model": model, "wings": wings, "tail": Flight.tail_of(model, "CrestedTern"), "voice": voice,
			"b": Flight.make(pos, _rng.randf() * TAU, TERN["cruise"]),
			"state": "patrol", "goal": pos, "timer": _rng.randf_range(8.0, 50.0),
			"flap": _rng.randf() * TAU, "amp": 0.6, "glide": _rng.randf_range(-2.5, 0.0), "beats": -3.0,
			"pitch": 0.0, "fold": 0.0, "vel": Vector3.ZERO, "hover_y": 0.0,
			"call_t": _rng.randf_range(2.0, 12.0),
			# (dusk and dawn: each has its own moment to go and to come: see _update_terns())
			"gone": false, "leaving": false, "shy": _rng.randf_range(0.0, 0.1),
			"roost": Vector3(TERN_ROOST.x + _rng.randf_range(-60.0, 60.0), _rng.randf_range(12.0, 22.0), TERN_ROOST.z + _rng.randf_range(-160.0, 160.0)),
		}
		d["goal"] = _tern_goal(pos)
		_terns.append(d)
	birds.free()
	# the splash of a plunging tern
	for i in 3:
		var sp := CPUParticles3D.new()
		sp.emitting = false
		sp.one_shot = true
		sp.amount = 48
		sp.lifetime = 0.85
		sp.explosiveness = 0.92
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 0.12
		sp.direction = Vector3.UP
		sp.spread = 26.0
		sp.initial_velocity_min = 1.8
		sp.initial_velocity_max = 5.0
		sp.gravity = Vector3(0, -9.8, 0)
		sp.scale_amount_min = 0.5
		sp.scale_amount_max = 1.3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.85))
		ramp.set_color(1, Color(1, 1, 1, 0.0))
		sp.color_ramp = ramp
		var quad := QuadMesh.new()
		quad.size = Vector2(0.11, 0.11)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color(0.86, 0.91, 0.93)
		sm.vertex_color_use_as_albedo = true
		# dithered, not blended: blended particles vanish behind the refracting sea surface
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		quad.material = sm
		sp.mesh = quad
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)
		_splashes.append(sp)
	for i in 10:
		var p := A + "step_water_%d.wav" % i
		if ResourceLoader.exists(p):
			_splash_sounds.append(load(p))
	_splash_voice = AudioStreamPlayer3D.new()
	_splash_voice.unit_size = 5.0
	_splash_voice.max_distance = 80.0
	_splash_voice.volume_db = -9.0
	add_child(_splash_voice)


## Next point of a tern's beat: mostly over the shallows and the reef, now and then across the beach.
func _tern_goal(from: Vector3) -> Vector3:
	for i in 14:
		var over_beach := _rng.randf() < 0.18
		var x := _rng.randf_range(-6.0, 4.0) if over_beach else _rng.randf_range(2.0, 55.0)
		var z := _rng.randf_range(-80.0, 70.0)
		if not over_beach and _ground(x, z) - _tide() > -0.3:
			continue
		if Vector2(x - from.x, z - from.z).length() < 18.0:
			continue
		return Vector3(x, _rng.randf_range(9.0, 14.0) if over_beach else _rng.randf_range(5.5, 12.0), z)
	return Vector3(25.0, 9.0, _rng.randf_range(-60.0, 50.0))


func _splash(at: Vector3) -> void:
	for sp in _splashes:
		if not sp.emitting:
			sp.global_position = at
			sp.restart()
			break
	if not _splash_sounds.is_empty() and not _splash_voice.playing:
		_splash_voice.global_position = at
		_splash_voice.stream = _splash_sounds[_rng.randi() % _splash_sounds.size()]
		_splash_voice.pitch_scale = _rng.randf_range(1.15, 1.4)
		_splash_voice.play()


func _update_terns(delta: float) -> void:
	var night := _night()
	var pp := _player.global_position if _player else Vector3.ZERO
	_started += delta
	for d in _terns:
		var n: Node3D = d["node"]
		var b: Dictionary = d["b"]
		var pos: Vector3 = b["pos"]
		var shy: float = d["shy"]
		if d["gone"]:
			if night > 0.4 - shy:
				continue
			# dawn: in from the sea again, to its beat over the shallows
			var from: Vector3 = d["roost"]
			from = pp + (from - pp).normalized() * (TERN_GONE - 20.0)
			from.y = float(d["roost"].y)
			b["pos"] = from
			b["yaw"] = Flight.yaw_of(Vector3(25.0, 0, 0) - from)
			b["speed"] = TERN["cruise"]
			b["vy"] = 0.0
			b["bank"] = 0.0
			pos = from
			d["gone"] = false
			d["state"] = "patrol"
			d["goal"] = _tern_goal(Vector3(25.0, 9.0, from.z * 0.2))
			d["timer"] = _rng.randf_range(60.0, 110.0)
			n.visible = true
		elif d["leaving"]:
			if night < 0.4 - shy:
				d["leaving"] = false        # (the day is back before it had gone)
			elif Vector2(pos.x - pp.x, pos.z - pp.z).length() > TERN_GONE:
				d["leaving"] = false
				d["gone"] = true
				n.visible = false
				continue
		elif night > 0.5 + shy and (d["state"] == "patrol" or d["state"] == "climb"):
			if _started < 3.0:
				# (the game has begun at night: it is at its roost already)
				d["gone"] = true
				n.visible = false
				continue
			d["leaving"] = true
			d["state"] = "patrol"
		var w := _wind(pos.y)
		d["timer"] -= delta
		var effort := 0.0      # 0 easy cruising .. 1 working hard
		var pitch := 0.0       # extra nose-up
		var fold := 0.0        # wings closed for the plunge
		var flapping := true
		match d["state"]:
			"patrol":
				# quartering the shallows with the bill pointing down, a few beats and a short glide
				var goal: Vector3 = d["goal"]
				if d["leaving"]:
					# out to sea, to roost: no more fishing today
					goal = d["roost"]
					d["timer"] = 30.0
					d["call_t"] = maxf(d["call_t"], 6.0)
				elif Vector2(goal.x - pos.x, goal.z - pos.z).length() < 6.0:
					goal = _tern_goal(pos)
					d["goal"] = goal
				Flight.steer(b, goal, delta, w, TERN)
				effort = clampf(float(b["vy"]) / 2.0, 0.0, 1.0)
				d["glide"] -= delta
				if d["glide"] < d["beats"]:
					d["glide"] = _rng.randf_range(0.4, 1.1)
					d["beats"] = -_rng.randf_range(2.5, 6.0)
				flapping = d["glide"] < 0.0 or b["vy"] > 0.4
				if b["vy"] < -1.2:
					flapping = false
				if d["timer"] <= 0.0:
					d["timer"] = _rng.randf_range(25.0, 70.0)
					var depth := _tide() - _ground(pos.x, pos.z)
					if depth > 0.5 and depth < 7.0 and pos.y > 4.5:
						d["state"] = "hover"
						d["timer"] = _rng.randf_range(1.3, 2.8)
						d["hover_y"] = pos.y
			"hover":
				# a fish below: hang on the wind, flying into it just fast enough to stay put
				var wh := Vector3(w.x, 0.0, w.z)
				var goal: Vector3 = pos - wh.normalized() * 40.0
				goal.y = d["hover_y"] + sin(Time.get_ticks_msec() * 0.004 + d["hover_y"]) * 0.25
				Flight.steer(b, goal, delta, w, TERN, maxf(wh.length(), 0.6))
				b["speed"] = lerpf(b["speed"], maxf(wh.length(), 0.6), 1.0 - exp(-3.0 * delta))   # braking on spread wings and tail
				effort = 1.0
				pitch = 0.65
				if d["timer"] <= 0.0:
					if _rng.randf() < 0.65:
						d["state"] = "dive"
						d["vel"] = Vector3(b["gvel"].x, -1.5, b["gvel"].z) + Flight.forward(b["yaw"]) * 1.2
					else:
						d["state"] = "patrol"
						d["timer"] = _rng.randf_range(6.0, 30.0)
			"dive":
				# wings half closed, straight down into the water
				var v: Vector3 = d["vel"]
				v.y -= 13.0 * delta
				v.x = lerpf(v.x, 0.0, 1.0 - exp(-0.6 * delta))
				v.z = lerpf(v.z, 0.0, 1.0 - exp(-0.6 * delta))
				d["vel"] = v
				pos += v * delta
				b["pos"] = pos
				b["vy"] = v.y
				b["speed"] = maxf(Vector2(v.x, v.z).length(), 1.0)
				b["bank"] = lerpf(b["bank"], 0.0, 1.0 - exp(-6.0 * delta))
				fold = 1.0
				flapping = false
				var surf := _sea_level(pos.x, pos.z)
				if pos.y <= surf + 0.08:
					_splash(Vector3(pos.x, surf + 0.03, pos.z))
					n.visible = false
					d["state"] = "under"
					d["timer"] = _rng.randf_range(0.5, 1.0)
			"under":
				if d["timer"] <= 0.0:
					# up again, heading into the wind, and shaking off the water on heavy wing beats
					var surf := _sea_level(pos.x, pos.z)
					b["pos"] = Vector3(pos.x, surf + 0.1, pos.z)
					b["yaw"] = Flight.yaw_of(-w)
					b["bank"] = 0.0
					b["speed"] = 2.0
					b["vy"] = 1.2
					d["pitch"] = 0.5
					d["fold"] = 0.3
					d["state"] = "climb"
					d["goal"] = _tern_goal(pos)
					n.visible = true
				else:
					continue
			"climb":
				var goal: Vector3 = d["goal"]
				Flight.steer(b, goal, delta, w, TERN, 6.5)
				effort = 1.0
				pitch = 0.25
				if b["pos"].y > minf(goal.y, 6.0) - 0.5:
					d["state"] = "patrol"
					d["timer"] = _rng.randf_range(15.0, 50.0)
		d["pitch"] = lerpf(d["pitch"], pitch, 1.0 - exp(-4.0 * delta))
		d["fold"] = lerpf(d["fold"], fold, 1.0 - exp(-7.0 * delta))
		n.global_transform = Transform3D(Flight.attitude(b, d["pitch"]), b["pos"])
		# wings: deep, springy beats; in a glide the arms a little raised and the hands drooping;
		# half closed and swept back for the plunge
		d["amp"] = lerpf(d["amp"], (0.55 + 0.25 * effort) if flapping else 0.0, 1.0 - exp(-7.0 * delta))
		d["flap"] = fmod(d["flap"] + TAU * (2.9 + 1.1 * effort) * delta, TAU)
		var pose := Flight.beat(d["flap"], d["amp"])
		var f: float = d["fold"]
		var still := 1.0 - clampf(float(d["amp"]) / 0.5, 0.0, 1.0)
		Flight.pose(d["wings"], lerpf(0.08 + 0.07 * still + float(pose[0]), 0.35, f), lerpf(-0.18 * still + float(pose[1]), -0.2, f),
			lerpf(0.1 * still + float(pose[2]), 1.0, f), float(pose[4]) * (1.0 - f))
		# the forked tail: closed to a point in level flight, opened in a turn, fanned out and
		# lowered when it hovers or brakes, shut for the plunge
		Flight.tail(d["tail"], (0.07 + 0.4 * absf(b["bank"]) + 0.75 * float(d["pitch"])) * (1.0 - f), 0.55 * float(d["pitch"]) * (1.0 - f))
		# the body rides up on every down-stroke
		(d["model"] as Node3D).position.y = float(pose[3]) * 0.018 * float(d["amp"])
		# calls
		d["call_t"] -= delta
		if d["call_t"] <= 0.0 and not _tern_calls.is_empty():
			var v: AudioStreamPlayer3D = d["voice"]
			v.stream = _tern_calls[_rng.randi() % _tern_calls.size()]
			v.pitch_scale = _rng.randf_range(0.92, 1.1)
			v.play()
			d["call_t"] = _rng.randf_range(2.5, 8.0)


## For the tests: the crested terns, and the flying foxes in the air.
func leave_report() -> Dictionary:
	var pp := _player.global_position if _player else Vector3.ZERO
	var out := {"in the air": 0, "of them leaving": 0, "gone to roost": 0, "furthest of those in the air from the walker (m)": 0.0}
	for d in _terns:
		if d["gone"]:
			out["gone to roost"] += 1
			continue
		out["in the air"] += 1
		if d["leaving"]:
			out["of them leaving"] += 1
		out["furthest of those in the air from the walker (m)"] = maxf(out["furthest of those in the air from the walker (m)"], snappedf((d["b"]["pos"] as Vector3).distance_to(pp), 1.0))
	out["flying foxes in the air"] = _bats.size()
	return out


# ------------------------------------------------------------------ crabs
## Leg cycle (radians) per meter walked by a crab of model size (45 cm across the legs): a planted
## tip covers its 7 cm reach in half a cycle. The crabs are scaled to life size (`size`), and take
## correspondingly shorter steps.
const CRAB_GAIT := 44.9

var _burrow_alb: ImageTexture
var _burrow_nor: ImageTexture


func _spawn_crabs() -> void:
	_make_burrow_textures()
	var crab_mesh: ArrayMesh = SmallModels.crab()
	for i in crab_count:
		var root := Node3D.new()
		add_child(root)
		var body := Node3D.new()
		root.add_child(body)
		# a big horn-eyed ghost crab: 20-25 cm across the legs
		var size := _rng.randf_range(0.4, 0.5)
		body.scale = Vector3.ONE * size
		var shell := MeshInstance3D.new()
		shell.mesh = crab_mesh
		if _world and _world.has_method("get_material"):
			shell.material_override = _world.get_material("CrabShell")
		shell.layers = 2   # decals (burrow, footprints) don't stain the crab
		shell.extra_cull_margin = 0.1
		body.add_child(shell)
		# its burrow: a hole in the firm sand above the reach of the waves
		var hole := Decal.new()
		hole.size = Vector3(0.5 * size, 0.3, 0.5 * size)
		hole.texture_albedo = _burrow_alb
		hole.texture_normal = _burrow_nor
		hole.albedo_mix = 1.0
		hole.normal_fade = 0.2
		hole.upper_fade = 0.2
		hole.lower_fade = 0.2
		hole.cull_mask = 1
		add_child(hole)
		var d := {"node": root, "body": body, "shell": shell, "hole": hole, "size": size, "state": "idle",
			"timer": _rng.randf_range(0.5, 3.0), "yaw": _rng.randf() * TAU, "vx": 0.0, "want": 0.0, "curve": 0.0,
			"gait": _rng.randf() * TAU, "lift": 0.0, "tuck": 0.0, "feed": 0.0, "sink": 0.0,
			"home": Vector3.ZERO, "flee_dir": Vector3.ZERO}
		_place_crab(d)
		_crabs.append(d)


## Burrow mouth as a decal: a dark hole with a crisp edge, a low rim of pale dry sand and a fan of
## damp sand pellets thrown out on one side.
func _make_burrow_textures() -> void:
	var s := 96
	var hm := PackedFloat32Array()
	hm.resize(s * s)
	var alb := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var nor := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	for y in s:
		for x in s:
			var p := Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0)
			var r := p.length() + noise.get_noise_2d(x, y) * 0.04
			var hole := 1.0 - smoothstep(0.3, 0.36, r)
			var rim := smoothstep(0.3, 0.4, r) * (1.0 - smoothstep(0.4, 0.6, r))
			var fan := smoothstep(0.36, 0.46, r) * (1.0 - smoothstep(0.6, 0.95, r)) * smoothstep(0.3, 0.85, p.x / maxf(p.length(), 0.01))
			var pellets := smoothstep(0.0, 0.35, noise.get_noise_2d(x * 3.3 + 40.0, y * 3.3))
			fan *= pellets
			hm[y * s + x] = -hole * 1.8 + rim * 0.3 + fan * 0.35
			# down the shaft it gets darker toward the far side
			var c := Color(0.06, 0.05, 0.04).lerp(Color(0.2, 0.17, 0.13), smoothstep(0.1, 0.36, r) * 0.6)
			var a := hole
			if hole < 0.5:
				# outside the hole: damp spoil (darker than the sun-bleached surface), dry rim
				c = Color(0.5, 0.44, 0.35).lerp(Color(0.9, 0.86, 0.76), clampf(rim - fan, 0.0, 1.0))
				a = clampf(fan * 0.75 + rim * 0.25, 0.0, 1.0)
			alb.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	for y in s:
		for x in s:
			var hx := hm[y * s + mini(x + 1, s - 1)] - hm[y * s + maxi(x - 1, 0)]
			var hy := hm[mini(y + 1, s - 1) * s + x] - hm[maxi(y - 1, 0) * s + x]
			var nrm := Vector3(-hx * 3.0, -hy * 3.0, 1.0).normalized()
			var p := Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0)
			var a := 1.0 - smoothstep(0.7, 0.98, p.length())
			nor.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5, a))
	alb.generate_mipmaps()
	nor.generate_mipmaps()
	_burrow_alb = ImageTexture.create_from_image(alb)
	_burrow_nor = ImageTexture.create_from_image(nor)


## Puts a crab and its burrow on the beach near the player (out of sight when it happens).
func _place_crab(d: Dictionary) -> void:
	# (a stretch of the start beach near the player; every crab has a burrow of its own, well
	# apart from the others'. Clamping the place to the ends of the beach used to put several
	# burrows on exactly the same spot when the player stood near an end: crabs sharing a hole)
	var z := _rng.randf_range(-55.0, 85.0)
	var lo := -55.0
	var hi := 90.0
	if _player:
		var pz := clampf(_player.global_position.z, lo + 25.0, hi - 25.0)
		lo = maxf(lo, pz - 40.0)
		hi = minf(hi, pz + 40.0)
	var widest := -1.0
	for attempt in 40:
		var cz := _rng.randf_range(lo, hi)
		var gap := 99.0
		for o in _crabs:
			if o != d:
				gap = minf(gap, absf((o["home"] as Vector3).z - cz))
		if gap > widest:
			widest = gap
			z = cz
		if gap >= 5.0:
			break
	# the waterline, then up the beach to firm sand for the burrow
	var x := -2.0
	for k in 120:
		if _ground(x, z) < 0.25:
			break
		x += 0.25
	var top := _rng.randf_range(0.5, 0.95)
	var bx := x
	for k in 60:
		if _ground(bx, z) >= top or x - bx > 5.5:   # on a flat beach: not up under the bushes
			break
		bx -= 0.2
	var home := Vector3(bx, _ground(bx, z), z)
	d["home"] = home
	var hole: Decal = d["hole"]
	hole.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), home + Vector3(0, 0.02, 0))
	# the crab itself is out feeding somewhere between the burrow and the wet sand
	var pos := home
	for k in 8:
		var q := home + Vector3(_rng.randf_range(-0.5, 4.5), 0, _rng.randf_range(-2.2, 2.2))
		var g := _ground(q.x, q.z)
		if g - _tide() > 0.05 and g < 1.5:
			pos = Vector3(q.x, g, q.z)
			break
	var n: Node3D = d["node"]
	n.global_position = pos
	d["yaw"] = _rng.randf() * TAU
	n.rotation.y = d["yaw"]
	n.visible = true
	d["state"] = "idle"
	d["vx"] = 0.0
	d["sink"] = 0.0
	d["tuck"] = 0.0


## Turns the crab so that one of its sides points along `dir` (whichever needs the smaller turn):
## returns +1 or -1, the side it will run to.
func _crab_face(d: Dictionary, dir: Vector3) -> float:
	var cur: float = (d["node"] as Node3D).rotation.y
	var ya := atan2(-dir.z, dir.x)
	if absf(angle_difference(cur, ya)) <= PI * 0.5:
		d["yaw"] = ya
		return 1.0
	d["yaw"] = ya + PI
	return -1.0


## Startled: to the burrow if it is near and the intruder is not in the way, otherwise away along the beach.
func _crab_startle(d: Dictionary, to_p: Vector3, to_home: Vector3) -> void:
	var hd := to_home.length()
	if hd < 14.0 and (hd < 0.6 or hd < to_p.length() * 0.5 or to_home.normalized().dot(to_p.normalized()) < 0.45):
		d["state"] = "home"
	else:
		d["state"] = "flee"
		d["flee_dir"] = -to_p.normalized()
		d["timer"] = _rng.randf_range(1.2, 2.4)


func _update_crabs(delta: float) -> void:
	var pp := _player.global_position if _player else Vector3(1e6, 0, 0)
	for d in _crabs:
		var n: Node3D = d["node"]
		var pos := n.global_position
		d["timer"] -= delta
		var to_p := Vector3(pp.x - pos.x, 0, pp.z - pos.z)
		var dist := to_p.length()
		var home: Vector3 = d["home"]
		var to_home := Vector3(home.x - pos.x, 0, home.z - pos.z)
		if dist > 70.0 and d["timer"] <= 0.0:
			_place_crab(d)
			d["timer"] = _rng.randf_range(2.0, 5.0)
			continue
		# the rising tide has reached it: home to the burrow (which lies above high water)
		if n.visible and pos.y - _tide() < 0.0 and d["state"] != "home" and d["state"] != "inside" and d["state"] != "enter" and d["state"] != "emerge":
			d["state"] = "home"
		var want_v := 0.0     # signed speed along its own x axis: crabs walk sideways
		var accel := 5.0
		var turn_k := 4.0
		var lift := 0.0
		var tuck := 0.0
		var feed := 0.0
		match d["state"]:
			"inside":
				if d["timer"] > 0.0 or dist < 11.0:
					continue
				d["state"] = "emerge"
				d["timer"] = 3.4
				d["sink"] = 0.24
				n.visible = true
				tuck = 1.0
			"emerge":
				# eye stalks first: it stops with only those above the sand and looks around
				tuck = 1.0
				var t: float = 3.4 - d["timer"]
				d["sink"] = lerpf(0.24, 0.15, smoothstep(0.0, 0.7, t)) if t < 2.3 else lerpf(0.15, 0.0, smoothstep(2.3, 3.2, t))
				if dist < 6.5:
					d["state"] = "enter"
				elif d["timer"] <= 0.0:
					d["state"] = "alert"
					d["timer"] = _rng.randf_range(1.0, 3.0)
			"enter":
				tuck = 1.0
				d["sink"] = move_toward(d["sink"], 0.25, delta * 0.6)
				if d["sink"] >= 0.25:
					n.visible = false
					d["state"] = "inside"
					d["timer"] = _rng.randf_range(8.0, 20.0)
			"idle":
				feed = 1.0
				if dist < 4.5:
					_crab_startle(d, to_p, to_home)
				elif dist < 9.0:
					d["state"] = "alert"
					d["timer"] = _rng.randf_range(0.6, 1.6)
				elif d["timer"] <= 0.0:
					var roll := _rng.randf()
					if roll < 0.62:
						# an unhurried sideways amble, back toward the burrow if it has strayed
						d["state"] = "walk"
						d["timer"] = _rng.randf_range(0.8, 2.6)
						var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
						if to_home.length() > 6.0:
							sgn = _crab_face(d, to_home.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)))
						else:
							d["yaw"] += _rng.randf_range(-0.6, 0.6)
						d["want"] = sgn * _rng.randf_range(0.14, 0.28)
						d["curve"] = _rng.randf_range(-0.35, 0.35)
					elif roll < 0.8:
						# a short sprint that stops dead
						d["state"] = "dash"
						d["timer"] = _rng.randf_range(0.35, 0.9)
						d["want"] = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.9, 1.4)
					else:
						d["yaw"] += _rng.randf_range(-1.3, 1.3)
						d["timer"] = _rng.randf_range(1.0, 3.0)
			"walk":
				want_v = d["want"]
				d["yaw"] += d["curve"] * delta
				if dist < 4.5:
					_crab_startle(d, to_p, to_home)
				elif dist < 9.0:
					d["state"] = "alert"
					d["timer"] = _rng.randf_range(0.6, 1.6)
				elif d["timer"] <= 0.0:
					d["state"] = "idle"
					d["timer"] = _rng.randf_range(1.5, 5.0)
			"dash":
				want_v = d["want"]
				accel = 12.0
				lift = 0.015
				if dist < 4.5:
					_crab_startle(d, to_p, to_home)
				elif d["timer"] <= 0.0:
					d["state"] = "idle"
					d["timer"] = _rng.randf_range(0.8, 3.0)
			"alert":
				# stock-still, up on its legs, watching
				accel = 30.0
				lift = 0.022
				if dist < 4.5:
					_crab_startle(d, to_p, to_home)
				elif dist > 10.0 and d["timer"] <= 0.0:
					d["state"] = "idle"
					d["timer"] = _rng.randf_range(0.5, 2.0)
			"home":
				accel = 16.0
				turn_k = 12.0
				lift = 0.02
				var hd := to_home.length()
				if hd < 0.2:
					# at the mouth of the burrow: straight in
					want_v = 0.0
					pos = pos.move_toward(Vector3(home.x, pos.y, home.z), delta * 1.2)
					pos.y = _ground(pos.x, pos.z)
					n.global_position = pos
					d["gait"] += delta * 40.0
					if hd < 0.025:
						d["state"] = "enter"
				else:
					want_v = _crab_face(d, to_home / hd) * clampf(hd * 5.0, 0.6, 2.3)
			"flee":
				accel = 16.0
				turn_k = 12.0
				lift = 0.02
				want_v = _crab_face(d, d["flee_dir"]) * 2.3
				if d["timer"] <= 0.0:
					if dist < 3.5:
						d["state"] = "crouch"
						d["timer"] = 1.5
					else:
						d["state"] = "alert"
						d["timer"] = _rng.randf_range(1.5, 4.0)
			"crouch":
				# cornered: pressed flat into the sand with the legs drawn in
				accel = 30.0
				lift = -0.03
				tuck = 0.55
				if dist < 1.3:
					d["state"] = "flee"
					d["flee_dir"] = -to_p.normalized()
					d["timer"] = _rng.randf_range(1.5, 2.5)
				elif dist < 5.5:
					d["timer"] = 1.5
				elif d["timer"] <= 0.0:
					d["state"] = "alert"
					d["timer"] = _rng.randf_range(1.0, 3.0)
		d["vx"] = move_toward(d["vx"], want_v, accel * delta)
		var old_yaw := n.rotation.y
		n.rotation.y = lerp_angle(old_yaw, d["yaw"], 1.0 - exp(-turn_k * delta))
		var yaw_rate := angle_difference(old_yaw, n.rotation.y) / maxf(delta, 0.001)
		var vx: float = d["vx"]
		if absf(vx) > 0.001:
			var np := n.global_position + n.global_basis.x * vx * delta
			var g := _ground(np.x, np.z)
			if g - _tide() < -0.05 or g > 1.6:
				# the sea or the bank ahead: stop, and when fleeing carry on along the beach
				d["vx"] = 0.0
				d["want"] = -d["want"]
				if d["state"] == "flee":
					var along: float = 1.0 if (d["flee_dir"] as Vector3).z >= 0.0 else -1.0
					d["flee_dir"] = Vector3(0, 0, along)
			else:
				np.y = g
				n.global_position = np
		# legs: steps as long as the ground covered; stepping around when turning on the spot
		var size: float = d["size"]
		var rate := clampf(vx * CRAB_GAIT / size, -55.0, 55.0)
		if absf(vx) < 0.05:
			rate = minf(absf(yaw_rate) * 12.0, 40.0)
		d["gait"] = fmod(d["gait"] + rate * delta, TAU)
		d["lift"] = lerpf(d["lift"], lift, 1.0 - exp(-9.0 * delta))
		d["tuck"] = move_toward(d["tuck"], tuck, delta * 5.0)
		d["feed"] = move_toward(d["feed"], feed, delta * 3.0)
		var stride := clampf(absf(vx) / (0.3 * size), 0.0, 1.0)
		var body: Node3D = d["body"]
		body.position.y = (float(d["lift"]) - float(d["sink"]) + sin(float(d["gait"]) * 2.0) * 0.003 * stride) * size
		body.rotation.z = sin(float(d["gait"])) * 0.02 * stride
		var shell: MeshInstance3D = d["shell"]
		if shell:
			shell.set_instance_shader_parameter("gait", d["gait"])
			shell.set_instance_shader_parameter("stride", stride)
			shell.set_instance_shader_parameter("turn", clampf(-yaw_rate / 2.5, -1.0, 1.0) * (1.0 if rate >= 0.0 else -1.0))
			shell.set_instance_shader_parameter("lift", d["lift"])
			shell.set_instance_shader_parameter("tuck", d["tuck"])
			shell.set_instance_shader_parameter("feed", d["feed"])


# ------------------------------------------------------------------ flying foxes (night)
var _bat_scene: PackedScene
var _bats: Array = []
var _bat_timer := 6.0
var _bat_calls: Array[AudioStream] = []
var _bat_voice: AudioStreamPlayer3D


func _init_bats() -> void:
	_bat_scene = load("res://assets/models/flying_fox.glb")
	for i in 8:
		var p := A + "flying_fox_%d.wav" % i
		if ResourceLoader.exists(p):
			_bat_calls.append(load(p))
	_bat_voice = AudioStreamPlayer3D.new()
	_bat_voice.unit_size = 18.0
	_bat_voice.max_distance = 160.0
	_bat_voice.volume_db = -8.0
	add_child(_bat_voice)


## A way for flying foxes to pass the walker at `pp` by night: three points of a curve.
func _bat_route(pp: Vector3) -> Array:
	# fly from the forest out over the beach toward the sea (or the other way)
	var z0 := pp.z + _rng.randf_range(-60.0, 60.0)
	var a := Vector3(pp.x - _rng.randf_range(70.0, 110.0), _rng.randf_range(22.0, 34.0), z0)
	var b := Vector3(pp.x + _rng.randf_range(-10.0, 15.0), _rng.randf_range(14.0, 24.0), pp.z + _rng.randf_range(-25.0, 25.0))
	var c := Vector3(pp.x + _rng.randf_range(80.0, 140.0), _rng.randf_range(20.0, 30.0), z0 + _rng.randf_range(-80.0, 80.0))
	if _rng.randf() < 0.4:
		var t := a; a = c; c = t
	# Over the land, not through it: the heights above were from the sea's level, and from
	# the start beach the way began inside the hill; from the ridge it lay far below the
	# walker's feet. Each of the three points is at least the walker's height and well over
	# the trees there, and the middle one is raised until the whole curve clears the ground.
	a.y = maxf(a.y + maxf(pp.y - 2.0, 0.0), _ground(a.x, a.z) + 24.0)
	b.y = maxf(b.y + maxf(pp.y - 2.0, 0.0), _ground(b.x, b.z) + 20.0)
	c.y = maxf(c.y + maxf(pp.y - 2.0, 0.0), _ground(c.x, c.z) + 24.0)
	for pass_ in 6:
		var low := 0.0
		for k in range(1, 12):
			var u := k / 12.0
			var q: Vector3 = (1.0 - u) * (1.0 - u) * a + 2.0 * u * (1.0 - u) * b + u * u * c
			low = maxf(low, _ground(q.x, q.z) + 19.0 - q.y)
		if low <= 0.0:
			break
		b.y += low * 2.0 + 1.0
	return [a, b, c]


func _spawn_bats() -> void:
	if _bat_scene == null or _player == null:
		return
	var count := _rng.randi_range(1, 3)
	var way := _bat_route(_player.global_position)
	var a: Vector3 = way[0]
	var b: Vector3 = way[1]
	var c: Vector3 = way[2]
	for i in count:
		var root := Node3D.new()
		add_child(root)
		var m := _bat_scene.instantiate() as Node3D
		root.add_child(m)
		var wings := Flight.wings(m, "Bat", "BatWingL", "BatWingR", _world)
		var off := Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-3, 3), _rng.randf_range(-6, 6))
		_bats.append({"node": root, "model": m, "wings": wings, "a": a + off, "b": b + off * 1.5, "c": c + off,
			"t": -i * 0.06, "dur": a.distance_to(c) / _rng.randf_range(7.0, 9.0), "flap": _rng.randf() * TAU,
			"glide": 0.0, "amp": 0.7, "bank": 0.0, "seed": _rng.randf() * TAU, "rate": _rng.randf_range(2.5, 2.9)})
	if not _bat_calls.is_empty() and _rng.randf() < 0.7:
		_bat_voice.global_position = a
		_bat_voice.stream = _bat_calls[_rng.randi() % _bat_calls.size()]
		_bat_voice.play()


## For the tests: ways for the night's flying foxes past a walker at each of `places`: the
## least room between the curve and the ground, and how the middle of it lies to the walker.
func bat_route_test(places: Array, tries := 40) -> Array:
	var out: Array = []
	for pp: Vector3 in places:
		var least := 1e9
		var below := 0
		for i in tries:
			var w := _bat_route(pp)
			for k in 25:
				var u := k / 24.0
				var q: Vector3 = (1.0 - u) * (1.0 - u) * (w[0] as Vector3) + 2.0 * u * (1.0 - u) * (w[1] as Vector3) + u * u * (w[2] as Vector3)
				least = minf(least, q.y - _ground(q.x, q.z))
			var mid: Vector3 = 0.25 * (w[0] as Vector3) + 0.5 * (w[1] as Vector3) + 0.25 * (w[2] as Vector3)
			if mid.y < pp.y + 3.0:
				below += 1
		out.append([pp.snappedf(1.0), "least room over the ground %.1f m" % least, "ways that pass below the walker's head: %d of %d" % [below, tries]])
	return out


## One flying fox on a way of its own, from a by b to c (the roost's bats leaving at dusk
## and coming home at dawn: scripts/critters.gd). It sets out after `delay` seconds; the
## answer is how many seconds from now it gets to c.
func bat_flight(a: Vector3, b: Vector3, c: Vector3, delay := 0.0) -> float:
	if _bat_scene == null:
		return 0.0
	var root := Node3D.new()
	add_child(root)
	root.global_position = a
	root.visible = false
	var m := _bat_scene.instantiate() as Node3D
	root.add_child(m)
	var wings := Flight.wings(m, "Bat", "BatWingL", "BatWingR", _world)
	var dur := (a.distance_to(b) + b.distance_to(c)) / _rng.randf_range(6.5, 8.0)
	_bats.append({"node": root, "model": m, "wings": wings, "a": a, "b": b, "c": c, "t": -delay / dur, "dur": dur, "flap": _rng.randf() * TAU,
		"glide": 0.0, "amp": 0.7, "bank": 0.0, "seed": _rng.randf() * TAU, "rate": _rng.randf_range(2.5, 2.9), "straight": true})
	return delay + dur


func _update_bats(delta: float, night: float) -> void:
	if night > 0.5:
		_bat_timer -= delta
		if _bat_timer <= 0.0:
			_spawn_bats()
			_bat_timer = _rng.randf_range(14.0, 40.0)
	for i in range(_bats.size() - 1, -1, -1):
		var d: Dictionary = _bats[i]
		d["t"] += delta / d["dur"]
		var t: float = d["t"]
		# (one that is on its way at dawn flies on to the end of it: it used to be taken out
		# of the air the moment `night` fell under 0.3)
		if t > 1.0:
			(d["node"] as Node3D).queue_free()
			_bats.remove_at(i)
			continue
		if t < 0.0:
			(d["node"] as Node3D).visible = false
			continue
		(d["node"] as Node3D).visible = true
		# quadratic bezier a -> b -> c, plus a gentle meander
		var u := 1.0 - t
		var pos: Vector3 = u * u * d["a"] + 2.0 * u * t * d["b"] + t * t * d["c"]
		# (not at the ends of a flight that begins or ends at the roost's branch)
		var wander := sin(t * PI) if d.get("straight", false) else 1.0
		pos += Vector3(sin(t * 17.0 + d["seed"]) * 1.5, sin(t * 11.0 + d["seed"]) * 1.0, 0) * wander
		var n: Node3D = d["node"]
		# heading from the path actually flown (meander included), leaning into its bends
		var vel: Vector3 = (pos - d["prev"]) / maxf(delta, 0.001) if d.has("prev") else 2.0 * u * (d["b"] - d["a"]) + 2.0 * t * (d["c"] - d["b"])
		d["prev"] = pos
		n.global_position = pos
		if vel.length() > 0.5:
			var yaw := Flight.yaw_of(vel)
			var turn: float = angle_difference(d.get("yaw", yaw), yaw) / maxf(delta, 0.001)
			d["yaw"] = yaw
			d["bank"] = lerpf(d["bank"], clampf(atan(-turn * vel.length() / Flight.G), -0.6, 0.6), 1.0 - exp(-2.5 * delta))
			var target := Basis.looking_at(vel.normalized(), Vector3.UP) * Basis(Vector3.FORWARD, d["bank"])
			n.basis = n.basis.slerp(target, 1.0 - exp(-4.0 * delta)).orthonormalized()
		# slow, deep, rowing wing beats with short glides; the heavy body bobs against them
		d["glide"] -= delta
		if d["glide"] < -3.0:
			d["glide"] = _rng.randf_range(0.6, 1.4)
		var flapping: bool = d["glide"] < 0.0
		d["amp"] = lerpf(d["amp"], 0.78 if flapping else 0.0, 1.0 - exp(-5.0 * delta))
		d["flap"] = fmod(d["flap"] + TAU * float(d["rate"]) * delta, TAU)
		var pose := Flight.beat(d["flap"], d["amp"])
		# the membrane is spread on the way down and half folded on the way up
		Flight.pose(d["wings"], 0.14 + float(pose[0]), float(pose[1]) * 1.15, 0.06 + float(pose[2]) * 1.15, float(pose[4]) * 0.8)
		(d["model"] as Node3D).position.y = float(pose[3]) * 0.035 * float(d["amp"])


# ------------------------------------------------------------------ boat
var _boat: Node3D
var _boat_base := Vector3(23.0, 0.0, -2.0)
var _boat_box := Rect2()
var _boat_mask := PackedFloat32Array()
var _boat_mask_len := 0.0
var _ocean_mat: ShaderMaterial
var _boat_seabed: Node

func _spawn_boat() -> void:
	var scene := load("res://assets/models/boat.glb") as PackedScene
	if scene == null:
		return
	_boat = Node3D.new()
	add_child(_boat)
	var m := scene.instantiate() as Node3D
	_boat.add_child(m)
	# The hull is 0.79 m deep from its keel (0.64 under the model's origin) to its rim
	# amidships (0.15 over it): it draws 0.3 m. (It was set 0.28 m DOWN, which put the rim
	# 13 cm under the waterline: the boat lay awash, the sea over its sides, since the
	# first day. Seen in the close pictures taken for the code review's finding 6.)
	m.position.y = 0.34
	_boat.global_position = _boat_base
	_boat.rotation.y = 0.5
	# its hull's outline, in its own space: for whatever swims (seabed.gd: set_boat())
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var inv := _boat.global_transform.affine_inverse()
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false) + ([m] if m is MeshInstance3D else []):
		if mi.mesh == null:
			continue
		var box: AABB = inv * mi.global_transform * mi.mesh.get_aabb()
		# (the hull: what lies in or near the water, not the mast)
		if box.position.y < 0.6:
			lo = lo.min(box.position)
			hi = hi.max(box.end)
	if hi.x > lo.x:
		_boat_box = Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z)
	# The boat is solid to the swimmer (since 2026-11-12):
	# a body that moves with it, with the boat's own shapes (the hull as the open shell it
	# is, the engine, the shaft and the pole), so that one swims around it, or dives under it.
	var body := AnimatableBody3D.new()
	body.name = "BoatBody"
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	_boat.add_child(body)
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false) + ([m] if m is MeshInstance3D else []):
		if mi.mesh == null or mi.mesh.get_faces().size() < 9 or mi.name == "BoatRibbons":
			continue
		var shape := mi.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		cs.global_transform = mi.global_transform
	# The hull's outline where the sea's surface cuts it, for the sea's shader: inside it no
	# water is drawn (an open boat that floats would otherwise show the sea's surface
	# running through it). Half the hull's width at 24 places along it, at five heights
	# from 16 cm under its waterline to 16 cm over it (the hull flares, and on a crest the
	# sea stands higher in it): from the triangles of the hull that cross each height;
	# 3 cm less, to lie within the planking.
	var hull := m.find_child("BoatHull", true, false) as MeshInstance3D
	if hull and hull.mesh:
		var to_boat := inv * hull.global_transform
		var faces := hull.mesh.get_faces()
		var hb: AABB = to_boat * hull.mesh.get_aabb()
		_boat_mask_len = maxf(absf(hb.position.x), absf(hb.end.x))
		_boat_mask.resize(120)
		_boat_mask.fill(0.0)
		for j in 5:
			var level := -0.16 + 0.08 * j
			for t in range(0, faces.size(), 3):
				for e in 3:
					var a: Vector3 = to_boat * faces[t + e]
					var b: Vector3 = to_boat * faces[t + (e + 1) % 3]
					if (a.y - level) * (b.y - level) >= 0.0:
						continue
					var p := a.lerp(b, (level - a.y) / (b.y - a.y))
					var k := clampi(int(round((p.x / _boat_mask_len * 0.5 + 0.5) * 23.0)), 0, 23)
					_boat_mask[j * 24 + k] = maxf(_boat_mask[j * 24 + k], absf(p.z) - 0.03)
		# ... and solid under the hull too, to 1.15 m below its waterline, in the hull's own
		# outline: a swimmer lies low in the water (the short capsule: its top is at the
		# keel's depth) and slipped under the hull, the eyes in its planks. A dive of a
		# meter and a half goes under it.
		var pts := PackedVector3Array()
		for k in 24:
			var w := _boat_mask[2 * 24 + k]
			if w <= 0.0:
				continue
			var x := (k / 23.0 * 2.0 - 1.0) * _boat_mask_len
			for y: float in [-1.15, 0.1]:
				pts.append(Vector3(x, y, w))
				pts.append(Vector3(x, y, -w))
		if pts.size() >= 8:
			var keel := ConvexPolygonShape3D.new()
			keel.points = pts
			var kcs := CollisionShape3D.new()
			kcs.shape = keel
			body.add_child(kcs)


## The boat rides the sea that is drawn under it: it lies at the height of the water under
## its hull (four places: toward the bow and the stern, and to either side), and pitches
## and rolls as that water slopes, a little behind it as a heavy thing is. It swings at its
## anchor as before. (It used to heave on two sine waves of its own, which had nothing to
## do with the swell: a crest cut the hull while the boat was on its way down. Code review,
## 2026-11-12.)
var _boat_y := 0.0
var _boat_tilt := Vector2.ZERO
var boat_stat := {"n": 0, "now": 0.0, "now_max": 0.0, "was": 0.0, "was_max": 0.0}      # (for the tests: see boat_report())

func _update_boat(delta: float) -> void:
	if _boat == null:
		return
	var t := Time.get_ticks_msec() * 0.001
	var yaw := 0.5 + sin(t * 0.07) * 0.25
	var at := _boat_base + Vector3(sin(t * 0.05) * 1.5, 0.0, cos(t * 0.04) * 1.2)
	var along := Vector3(cos(yaw), 0, -sin(yaw))        # the hull's long axis (the model's x)
	var across := Vector3(sin(yaw), 0, cos(yaw))
	var half_l := clampf(_boat_box.size.x * 0.28, 1.0, 2.4)
	var half_w := clampf(_boat_box.size.y * 0.4, 0.3, 0.7)
	var bow := _sea_level(at.x + along.x * half_l, at.z + along.z * half_l)
	var stern := _sea_level(at.x - along.x * half_l, at.z - along.z * half_l)
	var port := _sea_level(at.x + across.x * half_w, at.z + across.z * half_w)
	var starboard := _sea_level(at.x - across.x * half_w, at.z - across.z * half_w)
	var water := (bow + stern + port + starboard) * 0.25
	if _boat_y == 0.0 and _boat_tilt == Vector2.ZERO:
		_boat_y = water
	_boat_y = lerpf(_boat_y, water, 1.0 - exp(-7.0 * delta))
	# (x: about the long axis, the side that lies higher lifted; y: bow up or down)
	var want := Vector2(-atan2(port - starboard, 2.0 * half_w) * 0.6, atan2(bow - stern, 2.0 * half_l) * 0.85)
	_boat_tilt = _boat_tilt.lerp(want, 1.0 - exp(-4.0 * delta))
	_boat.global_position = Vector3(at.x, _boat_y, at.z)
	_boat.rotation = Vector3(_boat_tilt.x, yaw, _boat_tilt.y)
	if _boat_mask_len > 0.0:
		if _ocean_mat == null and _world and _world.has_method("get_material"):
			_ocean_mat = _world.get_material("Ocean")
			if _ocean_mat:
				_ocean_mat.set_shader_parameter("boat_w", _boat_mask)
				_ocean_mat.set_shader_parameter("boat_len", _boat_mask_len)
		if _ocean_mat:
			_ocean_mat.set_shader_parameter("boat_at", Vector4(at.x, at.z, along.x, along.z))
			# (its waterline's plane: up toward the bow by the pitch, down toward its +z side by the roll)
			_ocean_mat.set_shader_parameter("boat_plane", Vector3(_boat_y, _boat_tilt.y, -_boat_tilt.x))
	# (for the tests: how far the boat lies from the water under it, now and as it used to)
	var was := _tide() + sin(t * 0.9) * 0.07 + sin(t * 1.7 + 1.3) * 0.035
	boat_stat["n"] += 1
	boat_stat["now"] += absf(_boat_y - water)
	boat_stat["now_max"] = maxf(boat_stat["now_max"], absf(_boat_y - water))
	boat_stat["was"] += absf(was - water)
	boat_stat["was_max"] = maxf(boat_stat["was_max"], absf(was - water))
	if _boat_box.size.x > 0.0:
		if _boat_seabed == null:
			_boat_seabed = get_node_or_null("../IslandLife/Seabed")
		if _boat_seabed and _boat_seabed.has_method("set_boat"):
			_boat_seabed.set_boat(_boat.global_transform, _boat_box)


## For the tests: how far the boat's waterline has been from the water under its hull (mean
## and most, meters), as it rides now and as it would have with its old heave.
func boat_report() -> Dictionary:
	var n := maxf(float(boat_stat["n"]), 1.0)
	return {"frames": boat_stat["n"], "off the water now (mean, most)": [snappedf(float(boat_stat["now"]) / n, 0.001), snappedf(boat_stat["now_max"], 0.001)],
		"as it was (mean, most)": [snappedf(float(boat_stat["was"]) / n, 0.001), snappedf(boat_stat["was_max"], 0.001)],
		"tilt now (rad: roll, pitch)": _boat_tilt.snappedf(0.001), "far calls": far_calls, "the last from": far_last.snappedf(1.0),
		"its distance from the walker": snappedf(far_last.distance_to(_player.global_position), 1.0) if _player else 0.0}


## A far-off call of one of the sea's birds, by day: a tern or a noddy fishing out over the
## water, 150 to 320 m from the walker, wherever from there the sea lies (birds too far off
## to be drawn: ten terns are). In the place of the gull calls that played here every 5 to
## 14 seconds, always from the west of the walker whatever was there: no gull is on the
## island, and gulls are strays in the Seychelles (changed 2026-11-12). The files
## gull_0..6.wav are still in assets/audio.
func _far_call() -> void:
	if _player == null or _night() > 0.45 or _far_player.playing:
		return
	var pp := _player.global_position
	for i in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(150.0, 320.0)
		var x := pp.x + cos(a) * r
		var z := pp.z + sin(a) * r
		# (over open water, not over the island or its beaches)
		if _ground(x, z) > -1.0 or _ground(x + cos(a) * 25.0, z + sin(a) * 25.0) > -1.0 or _ground(x - cos(a) * 25.0, z - sin(a) * 25.0) > -1.0:
			continue
		var noddy := _rng.randf() < 0.4 and not _noddy_calls.is_empty()
		var from: Array[AudioStream] = _noddy_calls if noddy else _tern_calls
		if from.is_empty():
			return
		far_last = Vector3(x, _rng.randf_range(8.0, 25.0), z)
		_far_player.global_position = far_last
		_far_player.stream = from[_rng.randi() % from.size()]
		# (the samples' own levels differ: both come to what the gulls' was beside the surf)
		_far_player.volume_db = -10.0 if noddy else -3.0
		_far_player.pitch_scale = _rng.randf_range(0.94, 1.06)
		_far_player.play()
		far_calls += 1
		return


func _night() -> float:
	var dc := get_node_or_null("../DayCycle")
	return dc.night if dc else 0.0


func _process(delta: float) -> void:
	_update_boat(delta)
	# (the terns roost at night: they fly out at dusk and in at dawn, see _update_terns())
	_update_terns(delta)
	_update_bats(delta, _night())
	_update_crabs(delta)
	_far_timer -= delta
	if _far_timer <= 0.0:
		_far_timer = _rng.randf_range(7.0, 18.0)
		_far_call()
