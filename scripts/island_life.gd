extends Node3D
## Animals of the inner island: a pair of Aldabra giant tortoises grazing on the open grassy ridge,
## Seychelles skinks basking on boulders and the forest floor, and green day geckos on
## the palm trunks. The lizards only show up by day and dart off when you come close.

const A := "res://assets/audio/"
const SmallModels := preload("res://scripts/small_models.gd")

@export var player_path: NodePath = ^"../Player"
@export var skink_count := 18
@export var gecko_count := 10

var _player: Node3D
var _ls: Node
var _rng := RandomNumberGenerator.new()
var _ready_done := false


## it is raining (scripts/weather.gd sets this): the lizards take cover
var raining := false


func _ready() -> void:
	_rng.randomize()
	_player = get_node_or_null(player_path)
	_setup.call_deferred()   # the landscape is built in the root's _ready, after ours


func _setup() -> void:
	_ls = get_node_or_null("../Landscape")
	if _ls == null:
		return
	_setup_tortoises()
	_setup_lizards()
	_setup_grotto()
	# the tide (first: the others ask the landscape for the sea's level)
	var ti := Node.new()
	ti.name = "Tide"
	ti.set_script(load("res://scripts/tide.gd"))
	add_child(ti)
	ti.setup(_ls)
	# rock crabs, palm spiders, termites, the flying foxes' roost, the stream's sound
	var cr := Node3D.new()
	cr.name = "Critters"
	cr.set_script(load("res://scripts/critters.gd"))
	add_child(cr)
	cr.setup(_ls, _player)
	# seagrass and corals on the lagoon floor
	var sb := Node3D.new()
	sb.name = "Seabed"
	sb.set_script(load("res://scripts/seabed.gd"))
	add_child(sb)
	sb.setup(_ls)
	# two sea turtles in the lagoon: a green turtle on the seagrass, a hawksbill on the reef
	var tu := Node3D.new()
	tu.name = "Turtles"
	tu.set_script(load("res://scripts/turtles.gd"))
	add_child(tu)
	tu.setup(_ls, _player, sb)
	# the reef's small characters: anemonefish, garden eels, morays, octopuses, lionfish
	var rl := Node3D.new()
	rl.name = "ReefLife"
	rl.set_script(load("res://scripts/reef_life.gd"))
	add_child(rl)
	rl.setup(_ls, _player, sb)
	# a passing rain shower, rarely (N calls one)
	var we := Node3D.new()
	we.name = "Weather"
	we.set_script(load("res://scripts/weather.gd"))
	add_child(we)
	we.setup(_ls, _player)
	# bubbles under water: around the mask, from the swimmer's strokes, from the seagrass in the sun
	var bu := Node3D.new()
	bu.name = "Bubbles"
	bu.set_script(load("res://scripts/bubbles.gd"))
	add_child(bu)
	bu.setup(_ls, _player, sb)
	# a hawksbill that comes ashore to nest by day, her tracks, and hatchlings
	var ne := Node3D.new()
	ne.name = "Nesting"
	ne.set_script(load("res://scripts/nesting.gd"))
	add_child(ne)
	ne.setup(_ls, _player)
	# tropicbirds about the granite, turnstones and crab plovers on the shore, a heron at the pond
	var sbd := Node3D.new()
	sbd.name = "ShoreBirds"
	sbd.set_script(load("res://scripts/shorebirds.gd"))
	add_child(sbd)
	sbd.setup(_ls, _player)
	# hermit crabs on the beaches, millipedes and the snail on the forest floor at dusk, the
	# pitcher plant, orchids and wild vanilla on the summit granite
	var sl := Node3D.new()
	sl.name = "SmallLand"
	sl.set_script(load("res://scripts/small_land.gd"))
	add_child(sl)
	sl.setup(_ls, _player)
	# life in the tide pools of the east headland: rockskippers, urchins, a sea star, nerites
	var pl := Node3D.new()
	pl.name = "PoolLife"
	pl.set_script(load("res://scripts/pool_life.gd"))
	add_child(pl)
	pl.setup(_ls, _player, sb)
	# barnacles on the granite between the tide marks
	var ba := Node3D.new()
	ba.name = "Barnacles"
	ba.set_script(load("res://scripts/barnacles.gd"))
	add_child(ba)
	ba.setup(_ls, _player)
	# mynahs, barred ground doves, Seychelles fodies and the rare magpie-robin
	var lb := Node3D.new()
	lb.name = "LandBirds"
	lb.set_script(load("res://scripts/land_birds.gd"))
	add_child(lb)
	lb.setup(_ls, _player, sbd)
	# moon jellyfish drifting in the lagoon
	var jf := Node3D.new()
	jf.name = "Jellyfish"
	jf.set_script(load("res://scripts/jellyfish.gd"))
	add_child(jf)
	jf.setup(_ls, _player, sb)
	# two great barracudas at the reef's edge
	var bc := Node3D.new()
	bc.name = "Barracudas"
	bc.set_script(load("res://scripts/barracudas.gd"))
	add_child(bc)
	bc.setup(_ls, _player, sb)
	# a few Moorish idols, in twos and threes at their coral heads
	var mo := Node3D.new()
	mo.name = "Idols"
	mo.set_script(load("res://scripts/moorish_idols.gd"))
	add_child(mo)
	mo.setup(_ls, _player, sb)
	# spinner dolphins passing beyond the reef, rarely
	var dl := Node3D.new()
	dl.name = "Dolphins"
	dl.set_script(load("res://scripts/dolphins.gd"))
	add_child(dl)
	dl.setup(_ls, _player)
	_ready_done = true


func _night() -> float:
	var dc := get_node_or_null("../DayCycle")
	return dc.night if dc else 0.0


## Terrain normal from the heightmap.
func _normal(x: float, z: float) -> Vector3:
	var e := 0.4
	return Vector3(_ls.ground(x - e, z) - _ls.ground(x + e, z), 2.0 * e, _ls.ground(x, z - e) - _ls.ground(x, z + e)).normalized()


func _ray_down(p: Vector3, from_h := 6.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * from_h, p - Vector3.UP * 3.0)
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(q)


# ================================================================== giant tortoises
## A pair of Aldabra giant tortoises on the grassy ridge: a big male and a smaller female. They
## keep to the same patch of grass, graze, wander, now and then plod over to each other, and
## walk around one another rather than through.
##
## Gait: a slow walk in diagonal pairs (left fore with right hind), each foot on the ground for
## most of the stride. The feet are placed on the ground and the two-part legs (upper leg and
## lower leg, see tools/assets4.py) are bent to reach them, so planted feet do not slide and the
## legs fold under the shell when the tortoise pulls in. Lengths are in model units (x "size").
const T_UPPER := 0.17     # shoulder/hip to elbow/knee
const T_LOWER := 0.145    # elbow/knee to the middle of the foot
const T_FOOT := 0.075     # height of the middle of the foot when it stands on the ground
const T_DUTY := 0.78      # share of the stride a foot stays planted
const T_STEP := 0.24      # ground a planted foot covers under the body at a full walking pace
const T_LEGS := {"TortLegFL": 0.0, "TortLegBR": 0.08, "TortLegFR": 0.5, "TortLegBL": 0.58}   # touch-down in the stride

var _torts: Array = []
var _t_home := Vector3.ZERO   # the middle of their patch of grass


func _setup_tortoises() -> void:
	var scene := load("res://assets/models/tortoise.glb") as PackedScene
	if scene == null:
		return
	# home: a grassy spot on the open ridge a little way up from the beach
	var trail: PackedVector2Array = _ls._trail
	var home := Vector2(-60.0, 22.0)
	if trail.size() > 4:
		home = trail[3].lerp(trail[4], 0.4)
	for i in 40:
		var q := home + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
		if _ls.cover(q.x, q.y).b > 0.4 and _slope(q) < 0.35:
			home = q
			break
	_t_home = Vector3(home.x, _ls.ground(home.x, home.y), home.y)
	for size in [1.0, 0.84]:
		var node := Node3D.new()
		node.name = "Tortoise%d" % _torts.size()
		add_child(node)
		var m := scene.instantiate() as Node3D
		node.add_child(m)
		node.scale = Vector3.ONE * size
		get_parent()._apply_materials(m)
		var parts := {}
		for n in ["TortShell", "TortBody", "TortNeck1", "TortNeck2", "TortNeck3", "TortHead",
				"TortLegFL", "TortLegFR", "TortLegBL", "TortLegBR", "TortShinFL", "TortShinFR", "TortShinBL", "TortShinBR"]:
			var part := m.find_child(n, true, false) as Node3D
			if part:
				parts[n] = part
				parts[n + "_rest"] = part.transform
		if size < 1.0 and parts.has("TortShell"):
			# her shell: a little paler and more worn than his
			var shell := parts["TortShell"] as MeshInstance3D
			var sm := (get_parent().get_material("TortShell") as ShaderMaterial).duplicate() as ShaderMaterial
			sm.set_shader_parameter("base_color", Color(0.19, 0.15, 0.105))
			sm.set_shader_parameter("worn_color", Color(0.47, 0.42, 0.34))
			shell.set_surface_override_material(0, sm)
		# the shell is solid: you walk around a 250 kg tortoise, not through it
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		var cs := CollisionShape3D.new()
		var sh := CapsuleShape3D.new()
		sh.radius = 0.42 * size
		sh.height = 1.15 * size
		cs.shape = sh
		cs.rotation.x = PI / 2
		cs.position = Vector3(0, 0.45 * size, 0)
		body.add_child(cs)
		add_child(body)
		var munch := AudioStreamPlayer3D.new()
		if ResourceLoader.exists(A + "tortoise_munch.wav"):
			var s := load(A + "tortoise_munch.wav") as AudioStreamWAV
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = int(s.get_length() * s.mix_rate)
			munch.stream = s
		munch.unit_size = 1.2
		munch.max_distance = 14.0
		munch.volume_db = -6.0
		munch.pitch_scale = 1.0 if size >= 1.0 else 1.12
		node.add_child(munch)
		munch.position = Vector3(0, 0.15, -0.9)
		var t := {"node": node, "body": body, "parts": parts, "munch": munch, "size": size,
			"state": "graze", "timer": _rng.randf_range(5.0, 20.0), "target": Vector3.ZERO, "yaw": _rng.randf() * TAU,
			"withdraw": 0.0, "head_yaw": 0.0, "head_pitch": -0.5, "speed": 0.0,
			"phase": _rng.randf(), "step": T_STEP * 0.35, "short": false, "graze_left": 10.0,
			"bite_t": _rng.randf_range(0.0, 3.0), "bite_side": 0.2, "bite_len": 4.0, "bites": 0, "bites_goal": 3}
		var start := _t_home
		if not _torts.is_empty():
			start = _tortoise_spot(t, _t_home + Vector3(2.8, 0, 0.5), 2.5, 4.5)
			start.y = _ls.ground(start.x, start.z)
		node.global_position = start
		t["target"] = start
		_torts.append(t)


func _slope(q: Vector2) -> float:
	var n := _normal(q.x, q.y)
	return 1.0 - n.y


## A grassy, level spot `rmin`..`rmax` from the middle of their patch, clear of the other tortoise.
func _tortoise_spot(t: Dictionary, fallback: Vector3, rmin := 3.0, rmax := 14.0) -> Vector3:
	for i in 30:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(rmin, rmax)
		var q := Vector2(_t_home.x, _t_home.z) + Vector2(cos(a), sin(a)) * r
		if _ls.cover(q.x, q.y).b > 0.3 and _slope(q) < 0.3 and _ls.ground(q.x, q.y) > 1.0 and _tortoise_clear(t, Vector3(q.x, 0, q.y), 2.2):
			return Vector3(q.x, 0, q.y)
	return fallback


## True if `p` is at least `gap` from every other tortoise and from where it is heading.
func _tortoise_clear(t: Dictionary, p: Vector3, gap: float) -> bool:
	for o in _torts:
		if is_same(o, t):
			continue
		var op: Vector3 = (o["node"] as Node3D).global_position
		var ot: Vector3 = o["target"]
		if Vector2(op.x - p.x, op.z - p.z).length() < gap or Vector2(ot.x - p.x, ot.z - p.z).length() < gap:
			return false
	return true


## The other tortoise (the nearest one, if there were more), or an empty dictionary.
func _companion(t: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1e9
	var pos: Vector3 = (t["node"] as Node3D).global_position
	for o in _torts:
		if is_same(o, t):
			continue
		var d := pos.distance_to((o["node"] as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## Where to walk next: usually a fresh patch of grass, now and then over to its companion.
func _tortoise_goal(t: Dictionary) -> Vector3:
	var mate := _companion(t)
	if not mate.is_empty() and _rng.randf() < 0.3:
		var mp: Vector3 = (mate["node"] as Node3D).global_position
		var pos: Vector3 = (t["node"] as Node3D).global_position
		var from := Vector3(pos.x - mp.x, 0, pos.z - mp.z)
		if from.length() > 3.5:
			# stops a tortoise-length or two short of it
			var q: Vector3 = mp + from.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)) * _rng.randf_range(1.9, 2.6)
			if _ls.cover(q.x, q.z).b > 0.3 and _slope(Vector2(q.x, q.z)) < 0.3:
				return Vector3(q.x, 0, q.z)
	return _tortoise_spot(t, (t["node"] as Node3D).global_position)


## One bite: neck down to the grass, a mouthful torn off with a jerk of the head, then chewing
## with the head half raised.
func _graze(t: Dictionary, delta: float) -> void:
	t["bite_t"] += delta
	var bt: float = t["bite_t"]
	var side: float = t["bite_side"]
	var pitch := -0.3
	var yaw := side * 0.5
	var rate := 2.5
	if bt < 1.2:
		pitch = -0.64
		yaw = side
		rate = 2.2
	elif bt < 1.45:
		pitch = -0.46
		yaw = side + (0.25 if side < 0.0 else -0.25)
		rate = 13.0
	else:
		pitch = -0.3 + sin((bt - 1.45) * TAU * 1.5) * 0.035
		if bt > t["bite_len"]:
			t["bite_t"] = 0.0
			t["bites"] += 1
			t["bite_side"] = _rng.randf_range(-0.4, 0.4)
			t["bite_len"] = _rng.randf_range(3.2, 5.5)
	t["head_pitch"] = lerpf(t["head_pitch"], pitch, 1.0 - exp(-rate * delta))
	t["head_yaw"] = lerpf(t["head_yaw"], yaw, 1.0 - exp(-rate * delta))


func _update_tortoises(delta: float) -> void:
	for t in _torts:
		_update_tortoise(t, delta)


func _update_tortoise(t: Dictionary, delta: float) -> void:
	var node: Node3D = t["node"]
	var parts: Dictionary = t["parts"]
	var size: float = t["size"]
	var pos := node.global_position
	var pp := _player.global_position if _player else Vector3(1e6, 0, 0)
	var dist := Vector2(pp.x - pos.x, pp.z - pos.z).length()
	var fwd := Vector3(-sin(t["yaw"]), 0, -cos(t["yaw"]))
	var mate := _companion(t)
	var to_mate := Vector3(1e6, 0, 0)
	if not mate.is_empty():
		var mp: Vector3 = (mate["node"] as Node3D).global_position
		to_mate = Vector3(mp.x - pos.x, 0, mp.z - pos.z)
	t["timer"] -= delta
	# startled when someone is right next to it: head and legs pulled in, shell lowered
	var scared := dist < 1.7
	t["withdraw"] = move_toward(t["withdraw"], 1.0 if scared else 0.0, delta * (2.5 if scared else 0.25))
	var w: float = t["withdraw"]
	var yaw_rate := 0.0
	if w > 0.05:
		t["speed"] = 0.0
	else:
		match t["state"]:
			"graze":
				_graze(t, delta)
				if t["timer"] <= 0.0:
					t["state"] = "walk" if _rng.randf() < 0.6 else "look"
					t["timer"] = _rng.randf_range(6.0, 14.0)
					t["target"] = _tortoise_goal(t)
					t["short"] = false
				elif t["bites"] >= t["bites_goal"]:
					# the grass within reach is cropped: a step or two on to the next mouthful
					t["bites"] = 0
					t["bites_goal"] = _rng.randi_range(2, 4)
					var q: Vector3 = pos + fwd.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7)) * _rng.randf_range(0.5, 1.1)
					if _ls.cover(q.x, q.z).b > 0.3 and _slope(Vector2(q.x, q.z)) < 0.3 and _ls.ground(q.x, q.z) > 1.0 and _tortoise_clear(t, q, 1.8):
						t["target"] = q
						t["state"] = "walk"
						t["short"] = true
						t["graze_left"] = t["timer"]
			"look":
				t["head_pitch"] = lerpf(t["head_pitch"], 0.5, delta * 0.8)   # neck stretched up
				# curious: looks toward a nearby visitor, else at its companion, else around
				var want := sin(Time.get_ticks_msec() * 0.0005 + size * 7.0) * 0.6
				if dist < 10.0:
					want = clampf(fwd.signed_angle_to(Vector3(pp.x - pos.x, 0, pp.z - pos.z).normalized(), Vector3.UP), -0.7, 0.7)
				elif to_mate.length() < 12.0 and fmod(Time.get_ticks_msec() * 0.001 + size * 31.0, 14.0) < 7.0:
					want = clampf(fwd.signed_angle_to(to_mate.normalized(), Vector3.UP), -0.7, 0.7)
				t["head_yaw"] = lerpf(t["head_yaw"], want, delta * 0.8)
				if t["timer"] <= 0.0:
					t["state"] = "graze" if _rng.randf() < 0.7 else "walk"
					t["timer"] = _rng.randf_range(10.0, 25.0)
					t["target"] = _tortoise_goal(t)
					t["short"] = false
			"walk":
				var to := Vector3(t["target"].x - pos.x, 0, t["target"].z - pos.z)
				# it turns by stepping round, a few degrees with every stride
				var diff := angle_difference(t["yaw"], atan2(-to.x, -to.z))
				yaw_rate = clampf(diff * 0.8, -0.3, 0.3)
				t["yaw"] += yaw_rate * delta
				var facing := absf(diff) < 0.6
				var pace := 0.11 * size
				t["speed"] = move_toward(t["speed"], pace if facing else pace * 0.27, delta * 0.1)
				t["head_pitch"] = lerpf(t["head_pitch"], -0.1, delta)
				t["head_yaw"] = lerpf(t["head_yaw"], clampf(diff * 0.6, -0.4, 0.4), delta)   # looks where it is turning
				# don't plod into the visitor
				if dist < 2.6 and fwd.dot(Vector3(pp.x - pos.x, 0, pp.z - pos.z).normalized()) > 0.5:
					t["speed"] = move_toward(t["speed"], 0.0, delta * 0.3)
				# nor into the other tortoise: stop short and graze here instead
				var blocked := to_mate.length() < 1.75 and fwd.dot(to_mate.normalized()) > 0.3
				if blocked or to.length() < (0.25 if t["short"] else 0.6) or t["timer"] <= -20.0:
					t["state"] = "graze"
					t["timer"] = maxf(t["graze_left"], 4.0) if t["short"] else _rng.randf_range(10.0, 30.0)
					t["short"] = false
					t["bite_t"] = 0.0
					t["target"] = pos
		if t["state"] != "walk":
			t["speed"] = move_toward(t["speed"], 0.0, delta * 0.2)
	# each diagonal pair shoves the body on in turn: it surges twice per stride
	var speed: float = float(t["speed"]) * (1.0 + 0.25 * sin(2.0 * TAU * float(t["phase"]) + 0.5))
	# the stride: driven by the ground the feet cover, walking or stepping around on the spot
	var drive := speed + absf(yaw_rate) * 0.38 * size
	if drive > 0.004:
		t["step"] = move_toward(t["step"], T_STEP * clampf(drive / (0.06 * size), 0.35, 1.0), delta * 0.06)
	var step: float = t["step"]
	t["phase"] = fposmod(t["phase"] + drive * delta * T_DUTY / (step * size), 1.0)
	var phase: float = t["phase"]
	var amt := clampf(drive / (0.05 * size), 0.0, 1.0) * (1.0 - w)
	pos += fwd * speed * delta
	# body follows the ground, tilted with the slope
	pos.y = _ls.ground(pos.x, pos.z)
	node.global_position = pos
	var n := _normal(pos.x, pos.z)
	# a heavy, rolling walk: the shell tips toward the corner whose legs are in the air and swings
	# from side to side; at rest it rises and sinks a little with each slow breath
	var rock := -cos(TAU * (phase - 0.92)) * 0.04 * amt
	var sway := sin(TAU * (phase - 0.92)) * 0.035 * amt
	var nod := sin(2.0 * TAU * phase + 1.0) * 0.012 * amt
	var bob := (0.5 - 0.5 * cos(2.0 * TAU * phase)) * 0.012 * amt
	var breath := sin(Time.get_ticks_msec() * 0.0012 + size * 5.0) * 0.003 * (1.0 - amt) * (1.0 - w)
	var ground_basis := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, t["yaw"])
	# the shell, body and hips rock; the feet stay where they stand
	var rocking := Basis(Vector3.UP, sway) * Basis(Vector3.FORWARD, rock) * Basis(Vector3.RIGHT, nod)
	node.basis = ground_basis.scaled(Vector3.ONE * size)
	var drop := w * 0.17
	var lift_body := Vector3(0, bob + breath - drop, 0)
	for part in ["TortShell", "TortBody"]:
		if parts.has(part):
			var r: Transform3D = parts[part + "_rest"]
			parts[part].transform = Transform3D(rocking * r.basis, rocking * r.origin + lift_body)
	# legs: each foot is planted for most of the stride while the body passes over it, then lifted
	# and brought forward; in a turn every foot follows its own arc around the body. Pulled in, the
	# feet are drawn under the shell and the legs fold.
	for leg in T_LEGS:
		if not parts.has(leg):
			continue
		var r: Transform3D = parts[leg + "_rest"]
		var hind: bool = r.origin.z > 0.0
		var u := fposmod(phase - float(T_LEGS[leg]), 1.0)   # 0 at touch-down
		var sw := 1.0 - 2.0 * u / T_DUTY
		var lift := 0.0
		if u >= T_DUTY:
			var s := (u - T_DUTY) / (1.0 - T_DUTY)
			sw = -cos(PI * s)
			lift = sin(PI * s)
		# the way the ground moves under this hip (forward speed plus the turn), as a share of the stride
		var k := Vector2.ZERO
		if drive > 0.004:
			k = Vector2(yaw_rate * r.origin.z * size, -(speed + yaw_rate * r.origin.x * size)) / drive
			if k.length() > 1.0:
				k = k.normalized()
			t[leg] = k
		else:
			k = t.get(leg, Vector2(0, -1))
		var side := signf(r.origin.x)
		var stand := Vector3(r.origin.x + side * 0.035, T_FOOT, r.origin.z + (0.03 if hind else -0.02))
		var foot := stand + Vector3(k.x, 0, k.y) * (sw * 0.5 * step) + Vector3(0, lift * 0.05 * k.length(), 0)
		foot = foot.lerp(Vector3(r.origin.x * 0.8, T_FOOT, r.origin.z * 0.86), w)
		var hip: Vector3 = rocking * r.origin + lift_body
		# two-bone reach: lean the leg sideways to the foot, then bend it (knees forward, elbows back)
		var v := foot - hip
		var down := sqrt(v.x * v.x + v.y * v.y)
		var d := clampf(sqrt(down * down + v.z * v.z), 0.05, T_UPPER + T_LOWER - 0.003)
		var a1 := acos(clampf((T_UPPER * T_UPPER + d * d - T_LOWER * T_LOWER) / (2.0 * T_UPPER * d), -1.0, 1.0))
		var a2 := acos(clampf((T_UPPER * T_UPPER + T_LOWER * T_LOWER - d * d) / (2.0 * T_UPPER * T_LOWER), -1.0, 1.0))
		var bend := 1.0 if hind else -1.0
		parts[leg].transform = Transform3D(Basis(Vector3.BACK, atan2(v.x, -v.y)) * Basis(Vector3.RIGHT, atan2(-v.z, down) + bend * a1), hip)
		var shin: String = leg.replace("Leg", "Shin")
		if parts.has(shin):
			parts[shin].transform = Transform3D(Basis(Vector3.RIGHT, -bend * (PI - a2)), (parts[shin + "_rest"] as Transform3D).origin)
	# neck and head: a chain of three neck parts and the head (tools/assets4.py). It curves down to
	# the grass, arches forward when walking, stretches up to look around, and folds into an S
	# inside the shell when the head is pulled in.
	if parts.has("TortNeck1"):
		var p: float = float(t["head_pitch"]) - nod * 2.0
		# angles of the parts against the horizontal, from the shell outward, and of the head
		var c1 := 0.56 * p + 0.14
		var c2 := 1.03 * p + 0.04
		var c3 := 1.4 * p - 0.08
		var ch := 1.17 * p if p < 0.0 else 0.15 * p
		# pulled in: back and up, forward again, the head level in the opening of the shell
		c1 = lerpf(c1, 2.3, w)
		c2 = lerpf(c2, -0.25, w)
		c3 = lerpf(c3, 0.0, w)
		ch = lerpf(ch, 0.05, w)
		var yaw: float = (float(t["head_yaw"]) - sway * 1.3) * (1.0 - w)
		var r: Transform3D = parts["TortNeck1_rest"]
		parts["TortNeck1"].transform = Transform3D(rocking * r.basis * Basis(Vector3.UP, yaw * 0.4) * Basis(Vector3.RIGHT, c1),
			rocking * r.origin + Vector3(0, bob - drop * 0.6 + breath, 0.2 * w - breath * 1.5))
		for joint in [["TortNeck2", c2 - c1, 0.3], ["TortNeck3", c3 - c2, 0.3], ["TortHead", ch - c3, 0.0]]:
			if parts.has(joint[0]):
				parts[joint[0]].transform = Transform3D(Basis(Vector3.UP, yaw * float(joint[2])) * Basis(Vector3.RIGHT, joint[1]),
					(parts[joint[0] + "_rest"] as Transform3D).origin)
	# munching sound while grazing
	var munch: AudioStreamPlayer3D = t["munch"]
	var grazing: bool = t["state"] == "graze" and w < 0.05 and dist < 16.0
	if grazing and not munch.playing and munch.stream:
		munch.play(_rng.randf() * 10.0)
	elif not grazing and munch.playing:
		munch.stop()
	(t["body"] as AnimatableBody3D).global_transform = Transform3D(Basis(Vector3.UP, t["yaw"]), pos)


# ================================================================== skinks and geckos
var _liz_mesh := {}
var _liz_mat := {}
var _skinks: Array = []
var _geckos: Array = []


func _setup_lizards() -> void:
	for n in ["Skink", "Gecko"]:
		_liz_mesh[n] = SmallModels.lizard(n == "Gecko")
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/lizard.gdshader")
		m.set_shader_parameter("species", 0 if n == "Skink" else 1)
		_liz_mat[n] = m
	for i in skink_count:
		_skinks.append(_new_lizard("Skink"))
	for i in gecko_count:
		_geckos.append(_new_lizard("Gecko"))


func _new_lizard(kind: String) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = _liz_mesh[kind]
	mi.material_override = _liz_mat[kind]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	mi.scale = Vector3.ONE * _rng.randf_range(0.95, 1.3)
	add_child(mi)
	return {"node": mi, "state": "hidden", "timer": _rng.randf_range(1.0, 6.0), "gait": 0.0, "moving": 0.0,
		"speed": 0.0, "dash": 0.0, "going": false,
		"pos": Vector3.ZERO, "up": Vector3.UP, "fwd": Vector3.FORWARD, "dir": Vector3.ZERO, "trunk": -1, "s": 0.0, "ang": 0.0}


## Skink basking spot near the player: the top of a boulder or a patch of ground.
func _skink_spot(pp: Vector3) -> Dictionary:
	for i in 12:
		var on_rock: bool = _rng.randf() < 0.6 and not _ls.boulder_spots.is_empty()
		var p := Vector3.ZERO
		var max_h := 0.4
		if on_rock:
			var b: Array = _ls.boulder_spots[_rng.randi() % _ls.boulder_spots.size()]
			var c: Vector3 = b[0]
			if Vector2(c.x - pp.x, c.z - pp.z).length() > 20.0:
				continue
			p = c + Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4)) * b[1]
			max_h = b[1] * 1.2
		else:
			# mostly ahead of the walker and close by: they are small, and bold
			var a := _rng.randf() * TAU
			var yaw: Variant = _player.get("_yaw")
			if yaw != null and _rng.randf() < 0.75:
				a = -float(yaw) - PI * 0.5 + _rng.randf_range(-0.9, 0.9)
			var r := _rng.randf_range(3.0, 12.0)
			p = pp + Vector3(cos(a) * r, 0, sin(a) * r)
		var d := Vector2(p.x - pp.x, p.z - pp.z).length()
		if d < 2.6 or d > 22.0 or _ls.ground(p.x, p.z) < 0.8:
			continue
		# not in the fresh water or on its wet banks: skinks keep to dry ground
		if _wet(p):
			continue
		var hit := _ray_down(p, 8.0 if on_rock else 2.0)
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.55:
			continue
		if (hit["position"] as Vector3).y - _ls.ground(p.x, p.z) > max_h:
			continue   # a branch, not a rock
		return {"pos": hit["position"], "up": hit["normal"]}
	return {}


## For the tests: how many skinks show, and how near the fresh water the nearest of them is.
func skink_report() -> Dictionary:
	var shown := 0
	var nearest := 99.0
	var wet := 0
	for d: Dictionary in _skinks:
		if (d["node"] as Node3D).visible:
			shown += 1
			nearest = minf(nearest, float(_ls.stream_dist(Vector2((d["pos"] as Vector3).x, (d["pos"] as Vector3).z))))
			if _wet(d["pos"]):
				wet += 1
	return {"skinks showing": shown, "of them within 3.5 m of fresh water": wet, "the nearest to it (m)": nearest}


## Fresh water or its wet banks at p: the stream, its pools and the pond, and 3.5 m to
## either side.
func _wet(p: Vector3) -> bool:
	return float(_ls.stream_dist(Vector2(p.x, p.z))) < 3.5


func _orient(mi: Node3D, pos: Vector3, up: Vector3, fwd: Vector3) -> void:
	var f := (fwd - up * fwd.dot(up)).normalized()
	if f.length() < 0.01:
		f = up.cross(Vector3.RIGHT).normalized()
	var z := -f
	var x := up.cross(z).normalized()
	mi.global_transform = Transform3D(Basis(x, up, z).scaled(mi.scale), pos)


func _update_skinks(delta: float, pp: Vector3, day: bool) -> void:
	for d in _skinks:
		var mi: MeshInstance3D = d["node"]
		d["timer"] -= delta
		var dist := Vector2(d["pos"].x - pp.x, d["pos"].z - pp.z).length()
		match d["state"]:
			"hidden":
				if d["timer"] <= 0.0 and day and _ls.ground(pp.x, pp.z) > 0.3:
					# (by the stream there are few: its boulders drew every skink of the island to
					# the walker there)
					if float(_ls.stream_dist(Vector2(pp.x, pp.z))) < 14.0 and _rng.randf() < 0.75:
						d["timer"] = _rng.randf_range(6.0, 14.0)
						continue
					var s := _skink_spot(pp)
					if not s.is_empty():
						d["pos"] = s["pos"]
						d["up"] = s["up"]
						var a := _rng.randf() * TAU
						d["fwd"] = Vector3(cos(a), 0, sin(a))
						d["state"] = "bask"
						d["timer"] = _rng.randf_range(4.0, 12.0)
						mi.visible = true
					else:
						d["timer"] = 1.0
			"bask", "pause":
				d["moving"] = move_toward(d["moving"], 0.0, delta * 6.0)
				d["speed"] = 0.0
				d["going"] = false
				d["dash"] = 0.0
				if dist < 1.8:
					# dash away from the intruder and disappear into the litter / a crevice
					var away := Vector3(d["pos"].x - pp.x, 0, d["pos"].z - pp.z).normalized()
					d["dir"] = away.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
					d["state"] = "flee"
					d["timer"] = _rng.randf_range(1.8, 2.6)
				elif d["timer"] <= 0.0:
					# a quick little scuttle to a new spot nearby
					var a := _rng.randf() * TAU
					d["dir"] = Vector3(cos(a), 0, sin(a))
					d["state"] = "scuttle"
					d["timer"] = _rng.randf_range(0.5, 1.6)
				if dist > 26.0:
					d["state"] = "hidden"
					mi.visible = false
					d["timer"] = _rng.randf_range(0.5, 3.0)
				elif not day:
					# Rain or dusk: it runs for cover, as it does from somebody too near, and is
					# gone into the litter or a crevice (it used to be switched off where it sat).
					# Not all at the same moment.
					if not d.has("cover") or float(d["cover"]) < 0.0:
						d["cover"] = _rng.randf_range(0.2, 4.0)
					d["cover"] = float(d["cover"]) - delta
					if float(d["cover"]) <= 0.0:
						d["cover"] = -1.0
						var ca := _rng.randf() * TAU
						d["dir"] = Vector3(cos(ca), 0, sin(ca))
						d["state"] = "flee"
						d["timer"] = _rng.randf_range(1.8, 2.6)
				else:
					d["cover"] = -1.0
			"scuttle", "flee":
				var fast: bool = d["state"] == "flee"
				# a skink runs in jerks: a dash of a few body lengths, a beat of stillness, the next
				# dash. Making off from someone it does the same, a little faster and with shorter
				# stops, weaving for cover (it keeps its distance; it does not shoot away)
				d["dash"] -= delta
				if d["dash"] <= 0.0:
					d["going"] = not d["going"]
					if fast:
						d["dash"] = _rng.randf_range(0.3, 0.55) if d["going"] else _rng.randf_range(0.08, 0.18)
					else:
						d["dash"] = _rng.randf_range(0.18, 0.4) if d["going"] else _rng.randf_range(0.12, 0.35)
					if d["going"] and not fast:
						d["dir"] = (d["dir"] as Vector3).rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
				var spd: float = (1.5 if fast else 0.9) if d["going"] else 0.0
				d["speed"] = move_toward(d["speed"], spd, delta * (12.0 if spd > d["speed"] else 14.0))
				d["moving"] = move_toward(d["moving"], clampf(float(d["speed"]) / 1.6, 0.0, 1.0), delta * 12.0)
				if fast:
					d["dir"] = (d["dir"] as Vector3).rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.006 + mi.get_instance_id()) * 1.2 * delta)
				var step: float = float(d["speed"]) * delta
				var np: Vector3 = d["pos"] + d["dir"] * step
				var hit := _ray_down(np, 0.5)
				if hit.is_empty() or (hit["normal"] as Vector3).y < 0.4 or _wet(np):
					d["dir"] = -d["dir"].rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8))
				else:
					d["pos"] = hit["position"]
					d["up"] = d["up"].lerp(hit["normal"], 0.3).normalized()
					# the body's S goes to and fro three or four times a second at a run (it was ten: a blur)
					d["gait"] = fmod(d["gait"] + TAU * step / (0.24 + 0.09 * float(d["speed"])), TAU * 64.0)
				d["fwd"] = d["fwd"].lerp(d["dir"], 1.0 - exp(-14.0 * delta))
				if d["timer"] <= 0.0:
					if fast:
						d["state"] = "hidden"
						mi.visible = false
						d["timer"] = _rng.randf_range(4.0, 10.0)
					elif not day:
						d["state"] = "flee"         # (rain or dusk came while it was on its way: on, into cover)
						d["timer"] = _rng.randf_range(1.2, 2.0)
					else:
						d["state"] = "pause"
						d["timer"] = _rng.randf_range(2.0, 9.0)
		if mi.visible:
			# still lizards bob their heads now and then
			var nod := 0.0
			if d["moving"] < 0.1:
				nod = maxf(sin(Time.get_ticks_msec() * 0.004 + mi.get_instance_id()), 0.85) - 0.85
			_orient(mi, d["pos"], d["up"], d["fwd"].rotated(d["up"], nod))
			mi.set_instance_shader_parameter("gait", d["gait"])
			mi.set_instance_shader_parameter("moving", d["moving"])


## For the tests: what the skinks and geckos are doing now.
func lizard_report() -> Dictionary:
	var sk := {}
	for d in _skinks:
		sk[d["state"]] = int(sk.get(d["state"], 0)) + 1
	var gk := {}
	for d in _geckos:
		gk[d["state"]] = int(gk.get(d["state"], 0)) + 1
	return {"skinks": sk, "geckos": gk, "raining": raining}


## A gecko sits on the bark itself (until 2026-11-12 one that ran around a trunk sometimes
## went into the bark or into a termite trail). `_trunk_frame()` only
## knows a trunk's middle line and 0.9 of its mean radius (Landscape.palm_trunks, made for
## collisions): set by that, a gecko lay up to some centimeters in the wood wherever the
## trunk is thicker than its mean, swells or leans. Now two rays find the bark under its
## shoulders and under its hips, and it lies on the line between them. False: as it was
## (for the tests).
var geckos_on_bark := true
var gecko_stats := {"seconds": 0.0, "sunk": 0.0, "deepest": 0.0, "hovering": 0.0, "highest": 0.0, "no bark": 0.0}   # (for the tests: `gecko_audit`)
var gecko_audit := false

## The bark under a gecko at p (outward n, heading fwd, size sc): [place, outward, heading],
## or [] where no bark is found there.
func _on_bark(p: Vector3, n: Vector3, fwd: Vector3, sc: float) -> Array:
	var space := get_world_3d().direct_space_state
	var at: Array[Vector3] = []
	var nrm := Vector3.ZERO
	for along: float in [0.035 * sc, -0.07 * sc]:
		var a := p + fwd * along
		var q := PhysicsRayQueryParameters3D.create(a + n * 0.4, a - n * 0.25, 1)
		if _player is CollisionObject3D:
			q.exclude = [(_player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["normal"] as Vector3).dot(n) < 0.5:
			return []
		var h := ((hit["position"] as Vector3) - a).dot(n)
		if h < -0.12 or h > 0.2:
			return []           # (something else stands before the trunk there)
		at.append(hit["position"])
		nrm += hit["normal"]
	var f := (at[0] - at[1]).normalized()
	nrm = (nrm - f * nrm.dot(f)).normalized()
	return [at[1].lerp(at[0], 2.0 / 3.0) + nrm * 0.003, nrm, f]


## For the tests: how a gecko lies on its trunk: the height of its belly over the bark at
## the nose, the middle, the hips and the root of the tail (below 0: in the wood).
func _gecko_audit(pos: Vector3, n: Vector3, fwd: Vector3, sc: float, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var low := 9.0
	var high := -9.0
	for along: float in [0.045, 0.0, -0.06, -0.1]:
		var a := pos + fwd * (along * sc)
		var q := PhysicsRayQueryParameters3D.create(a + n * 0.3, a - n * 0.3, 1)
		if _player is CollisionObject3D:
			q.exclude = [(_player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			gecko_stats["no bark"] += delta
			return
		var h := (a - (hit["position"] as Vector3)).dot(n)
		low = minf(low, h)
		high = maxf(high, h)
	gecko_stats["seconds"] += delta
	if low < -0.004:
		gecko_stats["sunk"] += delta
	if low > 0.012:
		gecko_stats["hovering"] += delta
	gecko_stats["deepest"] = minf(float(gecko_stats["deepest"]), low)
	gecko_stats["highest"] = maxf(float(gecko_stats["highest"]), low)


## For the tests: every gecko that is out runs around its trunk as from a walker; and what
## the audit has found since `start` (true: begin anew, with the audit on).
func gecko_scare() -> int:
	var n := 0
	for d in _geckos:
		if d["state"] == "still" or d["state"] == "climb":
			d["flee_ang"] = float(d["ang"]) + PI * 0.85
			d["state"] = "flee"
			d["head"] = 0.0
			d["timer"] = 2.6
			n += 1
	return n


## For the tests: a gecko that is out (for the driver's `chase` and `look`).
func gecko_node() -> Node3D:
	for d in _geckos:
		if d["state"] != "hidden":
			return d["node"]
	return null


func gecko_report(start := false) -> Dictionary:
	var out := gecko_stats.duplicate()
	var seen := 0
	for d in _geckos:
		if d["state"] != "hidden":
			seen += 1
	out["out now"] = seen
	out["on bark"] = geckos_on_bark
	if start:
		gecko_audit = true
		gecko_stats = {"seconds": 0.0, "sunk": 0.0, "deepest": 0.0, "hovering": 0.0, "highest": 0.0, "no bark": 0.0}
	return out


## Is this palm one a gecko keeps off: one with a termites' nest and runways on its bark
## (critters.gd: the gecko ran through them), or one a millipede is climbing?
var _termite_palms := {}       # index in Landscape.palm_trunks -> true
var _termite_palms_known := false

func _palm_taken(ti: int, base: Vector3) -> bool:
	if not _termite_palms_known:
		var cr := get_node_or_null("Critters")
		if cr and "termite_nests" in cr and not (cr.termite_nests as Array).is_empty():
			_termite_palms_known = true
			var trunks: Array = _ls.palm_trunks
			for nest: Vector3 in cr.termite_nests:
				for k in trunks.size():
					for p: Vector3 in trunks[k]["pts"]:
						if absf(p.y - nest.y) < 1.5 and Vector2(p.x - nest.x, p.z - nest.z).length() < 0.8:
							_termite_palms[k] = true
	if _termite_palms.has(ti):
		return true
	var sl := get_node_or_null("SmallLand")
	if sl and "millipedes" in sl:
		for m: Dictionary in sl.millipedes:
			if m.get("state", "hidden") != "hidden" and m.has("pos") and Vector2((m["pos"] as Vector3).x - base.x, (m["pos"] as Vector3).z - base.z).length() < 1.5:
				return true
	return false


## For small_land.gd: does the palm that stands at `base` carry a termites' nest?
func termite_palm_at(base: Vector3) -> bool:
	var trunks: Array = _ls.palm_trunks
	for k: int in _termite_palms:
		var b: Vector3 = trunks[k]["pts"][0]
		if Vector2(b.x - base.x, b.z - base.z).length() < 1.5:
			return true
	return false


## For small_land.gd: is a gecko out on the palm that stands at `base`?
func gecko_at(base: Vector3) -> bool:
	var trunks: Array = _ls.palm_trunks
	for d in _geckos:
		if d["state"] != "hidden" and int(d.get("trunk", -1)) >= 0:
			var b: Vector3 = trunks[d["trunk"]]["pts"][0]
			if Vector2(b.x - base.x, b.z - base.z).length() < 1.5:
				return true
	return false


## Gecko on a palm trunk: position, outward normal and the trunk's upward direction.
func _trunk_frame(t: Dictionary, s: float, ang: float) -> Array:
	var pts: PackedVector3Array = t["pts"]
	var rad: PackedFloat32Array = t["r"]
	var f := clampf(s, 0.0, 0.999) * (pts.size() - 1)
	var i := int(f)
	var k := f - i
	var c := pts[i].lerp(pts[i + 1], k)
	var r := lerpf(rad[i], rad[i + 1], k)
	var up := (pts[i + 1] - pts[i]).normalized()
	var ref := up.cross(Vector3.RIGHT).normalized()
	var radial := ref.rotated(up, ang)
	return [c + radial * (r + 0.012), radial, up]


func _update_geckos(delta: float, pp: Vector3, day: bool) -> void:
	var trunks: Array = _ls.palm_trunks
	if trunks.is_empty():
		return
	for d in _geckos:
		var mi: MeshInstance3D = d["node"]
		d["timer"] -= delta
		if d["state"] == "hidden":
			if d["timer"] > 0.0 or not day:
				continue
			d["timer"] = 1.5
			# a trunk 4..25 m away
			for k in 10:
				var ti := _rng.randi() % trunks.size()
				var base: Vector3 = trunks[ti]["pts"][0]
				var dd := Vector2(base.x - pp.x, base.z - pp.z).length()
				if dd < 2.5 or dd > 16.0:
					continue
				var taken := false
				for o in _geckos:
					if o != d and o["trunk"] == ti and o["state"] != "hidden":
						taken = true
				if taken or _palm_taken(ti, base):
					continue
				var top: Vector3 = trunks[ti]["pts"][trunks[ti]["pts"].size() - 1]
				var h := top.y - base.y
				d["trunk"] = ti
				d["s"] = clampf(_rng.randf_range(0.9, 2.3) / maxf(h, 1.0), 0.05, 0.8)
				d["ang"] = _rng.randf() * TAU
				d["head"] = 0.0 if _rng.randf() < 0.7 else PI   # mostly head-up
				d["state"] = "still"
				d["timer"] = _rng.randf_range(3.0, 10.0)
				d["last"] = null
				d["nrm"] = null
				mi.visible = true
				break
			continue
		var t: Dictionary = trunks[d["trunk"]]
		var fr := _trunk_frame(t, d["s"], d["ang"])
		var dist := Vector2(fr[0].x - pp.x, fr[0].z - pp.z).length()
		var h: float = (t["pts"][t["pts"].size() - 1] as Vector3).y - (t["pts"][0] as Vector3).y
		match d["state"]:
			"still":
				d["moving"] = move_toward(d["moving"], 0.0, delta * 6.0)
				if dist < 1.5:
					# shy: up and around to the far side of the trunk, at a quick walk
					var to_p := Vector3(pp.x - fr[0].x, 0, pp.z - fr[0].z).normalized()
					d["flee_ang"] = d["ang"] + PI * (0.7 + _rng.randf() * 0.3) * (1.0 if fr[1].cross(to_p).dot(fr[2]) > 0 else -1.0)
					d["state"] = "flee"
					d["head"] = 0.0
					d["timer"] = 2.6
				elif d["timer"] <= 0.0:
					d["state"] = "climb"
					d["climb"] = _rng.randf_range(-0.5, 0.7) / maxf(h, 1.0)
					d["head"] = 0.0 if d["climb"] > 0.0 else PI
					d["timer"] = _rng.randf_range(0.4, 1.0)
				if dist > 22.0:
					d["state"] = "hidden"
					mi.visible = false
					d["timer"] = _rng.randf_range(0.5, 3.0)
				elif not day:
					# Rain or dusk: up the trunk and in among the frond bases (it used to be
					# switched off where it sat). Not all at the same moment.
					if not d.has("cover") or float(d["cover"]) < 0.0:
						d["cover"] = _rng.randf_range(0.2, 4.0)
					d["cover"] = float(d["cover"]) - delta
					if float(d["cover"]) <= 0.0:
						d["cover"] = -1.0
						d["state"] = "retire"
						d["head"] = 0.0
				else:
					d["cover"] = -1.0
			"climb":
				d["moving"] = move_toward(d["moving"], 1.0, delta * 8.0)
				d["s"] = clampf(d["s"] + d["climb"] * delta / 0.7, 0.03, 0.85)
				if d["timer"] <= 0.0:
					d["state"] = "still"
					d["timer"] = _rng.randf_range(3.0, 12.0)
			"retire":
				# a steady climb, half a meter a second, to the crown
				d["moving"] = move_toward(d["moving"], 1.0, delta * 6.0)
				d["s"] = float(d["s"]) + 0.5 / maxf(h, 1.0) * delta
				if float(d["s"]) > 0.93:
					d["state"] = "hidden"
					mi.visible = false
					d["timer"] = _rng.randf_range(2.0, 6.0)
			"flee":
				d["moving"] = move_toward(d["moving"], 1.0, delta * 6.0)
				d["ang"] = lerp_angle(d["ang"], d["flee_ang"], 1.0 - exp(-1.3 * delta))
				d["s"] = clampf(d["s"] + 0.3 / maxf(h, 1.0) * delta, 0.03, 0.9)
				if d["timer"] <= 0.0:
					d["state"] = "still"
					d["timer"] = _rng.randf_range(6.0, 15.0)
		if mi.visible:
			fr = _trunk_frame(t, d["s"], d["ang"])
			# steps as long as the bark covered
			if d.get("last") != null:
				d["gait"] = fmod(d["gait"] + TAU * minf((fr[0] as Vector3).distance_to(d["last"]), 0.1) / 0.15, TAU * 64.0)
			d["last"] = fr[0]
			var look: float = sin(Time.get_ticks_msec() * 0.0007 + mi.get_instance_id()) * 0.3 * (1.0 - d["moving"])
			var fwd: Vector3 = (fr[2] as Vector3).rotated(fr[1], d["head"] + look)
			var seat: Array = _on_bark(fr[0], fr[1], fwd, mi.scale.x) if geckos_on_bark else []
			if seat.is_empty():
				seat = [fr[0], fr[1], fwd]
			elif d.get("nrm") != null:
				# (the bark's facets: it does not tip over from one to the next at once)
				seat[1] = (d["nrm"] as Vector3).lerp(seat[1], 1.0 - exp(-14.0 * delta)).normalized()
			d["nrm"] = seat[1]
			_orient(mi, seat[0], seat[1], seat[2])
			if gecko_audit:
				_gecko_audit(seat[0], seat[1], seat[2], mi.scale.x, delta)
			mi.set_instance_shader_parameter("gait", d["gait"])
			mi.set_instance_shader_parameter("moving", d["moving"])


# ================================================================== grotto
var _cave_in := 0.0
var _drips: Array[AudioStream] = []
var _drip_players: Array[AudioStreamPlayer3D] = []
var _drip_timer := 1.0
var _drip_spots: Array = []
var _cave_front := Vector3.ZERO
var _sun_soft := -1.0


func _setup_grotto() -> void:
	if _ls.cave_path.is_empty():
		return
	_cave_front = _ls.cave_xf.origin
	# reverb for sounds made inside (drips, footsteps)
	if AudioServer.get_bus_index("Cave") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Cave")
		AudioServer.set_bus_send(bi, "World" if AudioServer.get_bus_index("World") >= 0 else "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.5
		rv.damping = 0.35
		rv.spread = 0.8
		rv.wet = 0.38
		rv.dry = 0.9
		rv.predelay_msec = 18.0
		AudioServer.add_bus_effect(bi, rv)
	var area := Area3D.new()
	area.name = "GrottoAcoustics"
	area.monitoring = false
	area.reverb_bus_enabled = true
	area.reverb_bus_name = &"Cave"
	area.reverb_bus_amount = 0.85
	area.reverb_bus_uniformity = 0.6
	# a box around every few meters of the way through
	var last := -99.0
	for c in _ls.cave_path:
		if c[3] < _ls._cave_roofed.x or c[3] > _ls._cave_roofed.y or c[3] - last < 2.5:
			continue
		last = c[3]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0 * c[1] + 1.0, c[2] + 1.0, 2.0 * c[1] + 1.0)
		cs.shape = box
		cs.position = (c[0] as Vector3) + Vector3(0, c[2] * 0.5, 0)
		area.add_child(cs)
	area.collision_layer = 0
	add_child(area)
	# water seeps through the joints between the boulders and drips from the roof
	for t in _ls.cave["drips"]:
		_drip_spots.append(Vector3(t[0], t[1], t[2]))
	# a slow drip loop and single drops from the ceiling
	var loop := AudioStreamPlayer3D.new()
	if ResourceLoader.exists(A + "cave_drips.wav"):
		var st := load(A + "cave_drips.wav") as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = int(st.get_length() * st.mix_rate)
		loop.stream = st
	loop.unit_size = 2.5
	loop.max_distance = 22.0
	loop.volume_db = -4.0
	add_child(loop)
	var inner: Array = _ls.cave["inner"]
	loop.global_position = Vector3(inner[0], inner[1] + 1.0, inner[2])
	loop.play()
	for i in 8:
		var path := A + "drip_%d.wav" % i
		if ResourceLoader.exists(path):
			_drips.append(load(path))
	for i in 3:
		var dp := AudioStreamPlayer3D.new()
		dp.unit_size = 2.0
		dp.max_distance = 18.0
		add_child(dp)
		_drip_players.append(dp)


var _grotto_amb: Node
var _grotto_glows: Array[OmniLight3D] = []
var _grotto_beam: MeshInstance3D
var _grotto_sun: DirectionalLight3D
var _step_bus := &""

func _update_grotto(delta: float) -> void:
	if _ls.cave_path.is_empty() or _player == null:
		return
	var inside: bool = _ls.cave_inside(_player.global_position)
	_cave_in = move_toward(_cave_in, 1.0 if inside else 0.0, delta * 1.5)
	# the outside world goes quiet and dull; your own steps echo
	var amb := AudioServer.get_bus_index("Ambient")
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, lerpf(0.0, -10.0, _cave_in))
		var lpf := AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter
		if lpf:
			lpf.cutoff_hz = lerpf(20000.0, 1800.0, _cave_in)
	# (the grotto's nodes are looked up once, not by name every frame)
	if _grotto_amb == null:
		_grotto_amb = get_node_or_null("../Ambience")
	var step_bus := &"Cave" if _cave_in > 0.5 else &"Master"
	if _grotto_amb and step_bus != _step_bus:
		_step_bus = step_bus
		for sp in _grotto_amb._step_players:
			sp.bus = step_bus
	# daylight through the gaps in the roof fades with the day; the shaft of sunlight is there
	# only while the sun stands in line with the big gap
	var night := _night()
	if _grotto_glows.is_empty():
		for k in 2:
			var gl := _ls.get_node_or_null("GrottoSkyGlow%d" % k) as OmniLight3D
			if gl:
				_grotto_glows.append(gl)
	for glow in _grotto_glows:
		glow.light_energy = lerpf(float(glow.get_meta("energy")), 0.03, night)
	if _grotto_beam == null:
		_grotto_beam = _ls.get_node_or_null("GrottoBeam") as MeshInstance3D
	if _grotto_sun == null:
		_grotto_sun = get_node_or_null("../Sun") as DirectionalLight3D
	var beam := _grotto_beam
	var sun := _grotto_sun
	if sun:
		# Inside, the sun's shadows are drawn without the widening penumbra (light_angular_distance).
		# With it, a low sun or the moon lit up the whole inner room through solid rock: the
		# penumbra is worked out from the distance to whatever stands in the light, and anything
		# far off toward the sun (trees, other boulders) is flattened onto the near plane of the
		# shadow map, which makes that distance, and the penumbra, endless. The rock itself is
		# light-tight (tools/grotto2.py checks it). See HANDOFF "Light leaking into the grotto".
		if _sun_soft < 0.0:
			_sun_soft = sun.light_angular_distance
		var soft := 0.0 if _cave_in > 0.02 else _sun_soft
		if not is_equal_approx(sun.light_angular_distance, soft):
			sun.light_angular_distance = soft
	if beam and sun:
		var dir: Vector3 = beam.get_meta("dir")
		var lined := smoothstep(0.955, 0.992, sun.global_transform.basis.z.dot(dir))
		(beam.material_override as ShaderMaterial).set_shader_parameter("strength", 0.04 * lined * (1.0 - night) * clampf(sun.light_energy / 2.4, 0.0, 1.0))
	_drip_timer -= delta
	if _drip_timer <= 0.0 and not _drips.is_empty():
		_drip_timer = _rng.randf_range(0.8, 4.0)
		if _player.global_position.distance_to(_cave_front) < 45.0 and not _drip_spots.is_empty():
			for dp in _drip_players:
				if not dp.playing:
					dp.stream = _drips[_rng.randi() % _drips.size()]
					# the one nearest-ish to the listener, so the drips are heard where you are
					var best: Vector3 = _drip_spots[_rng.randi() % _drip_spots.size()]
					for k in 4:
						var c: Vector3 = _drip_spots[_rng.randi() % _drip_spots.size()]
						if c.distance_to(_player.global_position) < best.distance_to(_player.global_position):
							best = c
					dp.global_position = best
					dp.pitch_scale = _rng.randf_range(0.85, 1.2)
					dp.volume_db = _rng.randf_range(-14.0, -4.0)
					dp.play()
					break


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_update_tortoises(delta)
	_update_grotto(delta)


func _physics_process(delta: float) -> void:
	if not _ready_done or _player == null:
		return
	# (skinks and geckos are out by day, and not in the rain)
	var day := _night() < 0.35 and not raining
	var pp := _player.global_position
	_update_skinks(delta, pp, day)
	_update_geckos(delta, pp, day)
