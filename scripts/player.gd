extends CharacterBody3D
## First-person walker for the beach.
## WASD / arrows walk, Shift jogs, Space hops, C (or Ctrl) crouches, mouse looks,
## F toggles a free-fly camera, R unsticks (back to the last firm ground stood on), Esc releases the mouse.
## In water deeper than a wader can stand in you swim, head up; look down and your face goes
## under: the snorkeler's view of the lagoon (the reef edge is as far out as you can go).
## Space while swimming: a dive on one breath, where you look, down to 4.5 m; after 45 s (or
## Space again, or swimming up) you are back at the surface and take a deep breath.
## Bushes are not solid: you push through them (slower, with rustling). A safety net
## puts you back on the beach if you ever end up wedged somewhere.

signal footstep(surface: String, strength: float)
signal landed(strength: float)
signal surfaced(seconds: float)       # back from a dive, after so long under

@export var walk_speed := 2.0
@export var run_speed := 4.6
@export var crouch_speed := 1.0
@export var jump_velocity := 3.4
@export var mouse_sensitivity := 0.0022
@export var eye_height := 1.65
@export var crouch_eye_height := 0.95
@export var max_wading_depth := 1.15
@export var swim_depth := 1.28          # deeper than this you float
@export var swim_speed := 1.1
@export var swim_fast := 1.9
@export var max_swim_depth := 8.0       # not out over the drop-off beyond the reef
@export var dive_depth := 4.5           # how far down a dive goes (the eyes, below the surface)
@export var dive_time := 45.0           # how long one breath lasts
@export var dive_rest := 10.0           # at the surface before the next dive

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D
@onready var shape_node: CollisionShape3D = $CollisionShape3D

const Heights := preload("res://scripts/heights.gd")
const BUSH_LAYER := 2          # collision layer of the bush bodies (not solid for the player)
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1

var _pitch := 0.0
var _yaw := 0.0
var _fly := false
var _crouching := false
var _crouch_amount := 0.0
var _step_phase := 0.0
var _sway_t := 0.0
var _cam_roll := 0.0
var _air_time := 0.0
var _land_dip := 0.0
var _in_bush := 0.0
var _safe_pos := Vector3.ZERO
var _safe_timer := 0.0
var _stuck_timer := 0.0
var _ocean_mat: ShaderMaterial
var _brush: AudioStreamPlayer
var _capsule: CapsuleShape3D
var _swimming := false
var _face_down := 0.0
var _stroke := 0.0
var _sea: Node
var _veil: MeshInstance3D
var _veil_mat: ShaderMaterial
var _muffle := -1
var _muffle_bus := 0
## true while the camera is below the surface of the sea
var underwater := false
## true during a dive on one breath (from the duck dive until the head is out again)
var diving := false
var dive_seconds := 0.0        # how long this dive has lasted
var dives := 0
var breaths := 0               # how often the breath at the surface was played
var _rising := false           # on the way up: out of air, or by choice
var _duck := 0.0               # the duck dive: the first moments carry you under
var _rest := 0.0               # getting the breath back
var _breath: AudioStreamPlayer
var _shrimp: AudioStreamPlayer         # the reef's crackle, heard with the head under water
const CRACKLE_DB := -16.0              # its level where the coral stands thickest (it was -8 everywhere)
var crackle := 0.0                     # how much of it there is here: 0 .. 1 (by the coral around the swimmer)
var _crackle_t := 0.0
var _bubble: AudioStreamPlayer         # the air that goes up when a dive begins
var _seabed: Node


func _ready() -> void:
	_add_input("move_forward", [KEY_W, KEY_UP, KEY_Z])
	_add_input("move_back", [KEY_S, KEY_DOWN])
	_add_input("move_left", [KEY_A, KEY_LEFT, KEY_Q])
	_add_input("move_right", [KEY_D, KEY_RIGHT])
	_add_input("sprint", [KEY_SHIFT])
	_add_input("jump", [KEY_SPACE])
	_add_input("crouch", [KEY_C, KEY_CTRL])
	_add_input("fly_toggle", [KEY_F])
	_add_input("fly_up", [KEY_E, KEY_SPACE])
	_add_input("fly_down", [KEY_C, KEY_CTRL])
	_add_input("reset_position", [KEY_R])
	_yaw = rotation.y
	rotation = Vector3.ZERO
	head.position.y = eye_height
	_capsule = (shape_node.shape as CapsuleShape3D).duplicate()
	shape_node.shape = _capsule
	collision_mask = 1
	_safe_pos = global_position
	if ResourceLoader.exists("res://assets/audio/brush.wav"):
		_brush = AudioStreamPlayer.new()
		var s := load("res://assets/audio/brush.wav") as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
		_brush.stream = s
		_brush.volume_db = -60.0
		add_child(_brush)
		_brush.play()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _add_input(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


## The level of the sea now (the tide: SeaLife has it from scripts/tide.gd).
func _tide() -> float:
	if _sea == null:
		_sea = get_node_or_null("../SeaLife")
	return float(_sea.tide) if _sea and "tide" in _sea else 0.0


func ground_height(xz: Vector2) -> float:
	# (the shared height map: the terrain, -9 beyond it)
	return Heights.terrain(xz.x, xz.y, -9.0)


func _message(text: String) -> void:
	var dc := get_node_or_null("../DayCycle")
	if dc and dc.has_method("show_message"):
		dc.show_message(text)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.45, 1.45)
		return
	if event is InputEventMouseButton and event.pressed:
		# (not while a panel is open: a click in it, on the licenses' scroll bar say, is the panel's)
		var menus := get_node_or_null("../Menus")
		if menus == null or not menus.is_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: Key = event.keycode
	if k == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif k == KEY_F11 or (k == KEY_ENTER and event.alt_pressed) or (k == KEY_F and event.ctrl_pressed and event.meta_pressed):
		_toggle_fullscreen()
	elif k == KEY_F12 or (k == KEY_P and not event.meta_pressed):
		_save_screenshot()
	elif event.is_action("reset_position") and not event.meta_pressed:
		_reset_to_safe("Unstuck: back on firm ground")
	elif event.is_action("fly_toggle") and not (event.ctrl_pressed or event.meta_pressed):
		_fly = not _fly
		diving = false
		shape_node.disabled = _fly
		velocity = Vector3.ZERO
		_message("Free camera" if _fly else "Walking")


func _toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor():
		_message("Fullscreen needs its own window: turn off \"Embed Game on Next Play\" in the editor's Game tab")
		return
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _reset_to_safe(msg := "") -> void:
	global_position = _safe_pos + Vector3(0, 0.15, 0)
	velocity = Vector3.ZERO
	_stuck_timer = 0.0
	if msg != "":
		_message(msg)


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	head.rotation = Vector3(_pitch, _yaw, 0.0)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_y := Basis(Vector3.UP, _yaw)

	if _fly:
		var dir := (Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(input.x, 0, input.y))
		dir.y += Input.get_axis("fly_down", "fly_up")
		var sp := 9.0 if Input.is_action_pressed("sprint") else 3.0
		velocity = velocity.lerp(dir * sp, 1.0 - exp(-4.0 * delta))
		global_position += velocity * delta
		# (the free camera has no body: the rustle of a bush one stood in when F was
		# pressed dies away)
		_in_bush = 0.0
		_rustle(delta, 0.0)
		_update_camera(delta, 0.0)
		_update_world_feedback()
		return

	_update_crouch(delta)
	_in_bush = lerpf(_in_bush, 1.0 if _inside_bush() else 0.0, 1.0 - exp(-6.0 * delta))

	# The water over the sea floor here, and how deep one's feet really are in it: standing on
	# a boulder that rises out of deep water they are dry, whatever lies beneath (until
	# 2026-11-13 on the shore's boulders one was a swimmer, with a swimmer's pace and a
	# dive into the rock on Space).
	var sea := _tide()
	var depth := sea - ground_height(Vector2(global_position.x, global_position.z))
	var immersed := sea - global_position.y
	var wet := minf(depth, immersed)
	var wading := clampf(wet / max_wading_depth, 0.0, 1.0)
	var speed := run_speed if Input.is_action_pressed("sprint") and not _crouching else walk_speed
	if _crouching:
		speed = crouch_speed
	speed *= lerpf(1.0, 0.45, wading) * lerpf(1.0, 0.55, _in_bush)
	var wish := basis_y * Vector3(input.x, 0.0, input.y) * speed

	# deep water: swim. Not while something solid holds one up in water one can stand in (a
	# boulder, a rock shelf under the surface), and not before one is in the water (stepping
	# off a rock one falls first).
	var held_up := is_on_floor() and immersed < swim_depth - 0.12
	var was_swimming := _swimming
	if _swimming:
		_swimming = depth > swim_depth - 0.12 and not held_up
	else:
		_swimming = depth > swim_depth and not held_up and immersed > 0.6
	if _swimming:
		if not was_swimming and _air_time > 0.25:
			footstep.emit("water", clampf(_air_time / 0.7, 0.4, 1.0))   # in from above: a splash
		_swim(delta, input, basis_y)
		return
	if diving:
		_end_dive()        # swum into water one can stand in

	var on_floor := is_on_floor()
	var accel := 9.0 if on_floor else 2.5
	velocity.x = lerpf(velocity.x, wish.x, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, wish.z, 1.0 - exp(-accel * delta))
	if on_floor:
		if Input.is_action_just_pressed("jump") and not _crouching and wading < 0.8:
			velocity.y = jump_velocity * lerpf(1.0, 0.6, wading)
		else:
			velocity.y = -0.5
	else:
		velocity.y -= 9.81 * delta
	var before := global_position
	move_and_slide()

	# landing
	if is_on_floor():
		if _air_time > 0.25:
			var strength := clampf(_air_time / 0.7, 0.3, 1.0)
			_land_dip = 0.07 * strength
			landed.emit(strength)
			footstep.emit(_surface(wet), strength)
		_air_time = 0.0
	else:
		_air_time += delta

	_footsteps(delta, wet)
	_safety(delta, before, wish)
	_update_camera(delta, Vector2(velocity.x, velocity.z).length())
	_update_world_feedback()


func _surface(depth: float) -> String:
	if depth > 0.05:
		return "water"
	elif depth > -0.25:
		return "wet"
	return "sand"


func _update_crouch(delta: float) -> void:
	var want := Input.is_action_pressed("crouch")
	if want != _crouching:
		if want:
			_crouching = true
		else:
			# only stand up if there is head room
			var probe := global_transform
			if not test_move(probe, Vector3(0, STAND_HEIGHT - CROUCH_HEIGHT + 0.05, 0)):
				_crouching = false
	# (a swimmer lies in the water: the short capsule, the eyes just above or below the surface)
	_crouch_amount = move_toward(_crouch_amount, 1.0 if (_crouching or _swimming) else 0.0, delta * (2.5 if _swimming else 5.0))
	var hgt := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_amount)
	_capsule.height = hgt
	shape_node.position.y = hgt * 0.5
	head.position.y = lerpf(eye_height, crouch_eye_height, _crouch_amount)


func _inside_bush() -> bool:
	# bush bodies live on their own (non-solid) layer. Count how many of their
	# surfaces a ray from the chest crosses on its way up: an odd count = inside.
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.6, 0)
	var to := from + Vector3(0, 9, 0)
	var crossings := 0
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 << (BUSH_LAYER - 1))
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		crossings += 1
		from = hit.position + Vector3(0, 0.02, 0)
	return crossings % 2 == 1


func _footsteps(delta: float, depth: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.3:
		var freq := 1.8 if hspeed < 3.0 else 2.6
		if _crouching:
			freq = 1.3
		var prev := _step_phase
		_step_phase += delta * freq
		_sway_t += delta * freq * PI
		if floorf(_step_phase) != floorf(prev):
			footstep.emit(_surface(depth), clampf(hspeed / run_speed, 0.3, 1.0) * (0.6 if _crouching else 1.0))
	else:
		# settle at the top of the stride when stopping
		var f := _step_phase - floorf(_step_phase)
		if f > 0.0 and f < 0.5:
			_step_phase = move_toward(_step_phase, floorf(_step_phase) + 0.5, delta * 2.0)
	_rustle(delta, hspeed)


## The rustle of leaves brushed through: by how deep in a bush and how fast. Called on
## every way through a physics step (walking, swimming, the free camera), or the sound
## keeps the level it had when the walking stopped.
func _rustle(delta: float, hspeed: float) -> void:
	if _brush:
		var target := lerpf(-60.0, -8.0, clampf(_in_bush * hspeed / 1.2, 0.0, 1.0))
		_brush.volume_db = lerpf(_brush.volume_db, target, 1.0 - exp(-8.0 * delta))


func _safety(delta: float, before: Vector3, wish: Vector3) -> void:
	# remember good spots: standing on the ground, outside bushes, on the beach side
	_safe_timer += delta
	if _safe_timer > 0.5 and is_on_floor() and _in_bush < 0.1 and get_floor_angle() < 0.6:
		_safe_timer = 0.0
		_safe_pos = global_position
	# fell through the world
	if global_position.y < ground_height(Vector2(global_position.x, global_position.z)) - 2.0:
		_reset_to_safe()
		return
	# wedged: trying to move, not moving, and blocked in every direction
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if wish.length() > 0.3 and moved < wish.length() * delta * 0.1:
		_stuck_timer += delta
		if _stuck_timer > 1.0:
			var blocked := 0
			for d in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)]:
				if test_move(global_transform, d):
					blocked += 1
			if blocked >= 3:
				_reset_to_safe("Unstuck")
			_stuck_timer = 0.0
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta)


## Swimming: floating at the surface, slowly. Looking down puts the face in the water.
## The lagoon is the swimmer's: not out over the reef's drop-off (the part of the motion that
## heads for deeper water there is taken away).
func _keep_in_lagoon(wish: Vector3) -> Vector3:
	var flat := Vector3(wish.x, 0, wish.z)
	if flat.length() < 0.01:
		return wish
	var ahead := global_position + flat.normalized() * 2.5
	if -ground_height(Vector2(ahead.x, ahead.z)) > max_swim_depth:
		var grad := Vector3(
			ground_height(Vector2(global_position.x + 1.5, global_position.z)) - ground_height(Vector2(global_position.x - 1.5, global_position.z)),
			0.0,
			ground_height(Vector2(global_position.x, global_position.z + 1.5)) - ground_height(Vector2(global_position.x, global_position.z - 1.5)))
		if grad.length() > 0.0001:
			var downhill := -grad.normalized()
			var into := flat.dot(downhill)
			if into > 0.0:
				wish -= downhill * into
		else:
			wish = Vector3(0, wish.y, 0)
	return wish


## (for the tests) Is the breath being played, and how loud do its bus and the master carry
## it just now (dB)?
func breath_report() -> Dictionary:
	var hy := AudioServer.get_bus_index("Hydro")
	return {"breaths played": breaths, "playing now": _breath != null and _breath.playing, "at (s)": _breath.get_playback_position() if _breath else -1.0,
		"its bus": String(_breath.bus) if _breath else "", "reef crackle (dB)": snappedf(_shrimp.volume_db, 0.1) if _shrimp else -99.0, "coral about (0..1)": snappedf(crackle, 0.01),
		"bubbles loaded": _bubble != null, "Hydro peak (dB)": AudioServer.get_bus_peak_volume_left_db(hy, 0) if hy >= 0 else -999.0,
		"Master peak (dB)": AudioServer.get_bus_peak_volume_left_db(0, 0), "stream (s)": _breath.stream.get_length() if _breath and _breath.stream else 0.0}


## Starts a dive (Space while swimming; also for the tests).
func start_dive() -> bool:
	if diving or not _swimming or _rest > 0.0:
		return false
	diving = true
	_rising = false
	dive_seconds = 0.0
	_duck = 1.4
	dives += 1
	footstep.emit("water", 0.7)       # the splash of the duck dive
	if _bubble == null and ResourceLoader.exists("res://assets/audio/dive_bubbles.wav"):
		_bubble = AudioStreamPlayer.new()
		_bubble.stream = load("res://assets/audio/dive_bubbles.wav")
		_bubble.bus = &"Hydro" if AudioServer.get_bus_index("Hydro") >= 0 else &"Master"
		_bubble.volume_db = -6.0
		add_child(_bubble)
	if _bubble:
		get_tree().create_timer(0.6).timeout.connect(_bubble.play)
	return true


func _end_dive() -> void:
	diving = false
	_rising = false
	_rest = dive_rest
	surfaced.emit(dive_seconds)
	# the snorkel blown clear, and a deep breath
	if _breath == null and ResourceLoader.exists("res://assets/audio/dive_breath.wav"):
		_breath = AudioStreamPlayer.new()
		_breath.stream = load("res://assets/audio/dive_breath.wav")
		# (one's own breath is heard in the head, face in the water or not: with the sounds
		# of the water, which are not muffled)
		_breath.bus = &"Hydro" if AudioServer.get_bus_index("Hydro") >= 0 else &"Master"
		add_child(_breath)
	if _breath:
		# (a long dive ends in a deeper breath than a short one; even the short one must
		# carry over the surf: at -3 to -12 dB the first version was not heard)
		_breath.volume_db = lerpf(-4.0, 1.0, clampf(dive_seconds / 30.0, 0.0, 1.0))
		_breath.play()
		breaths += 1
	footstep.emit("water", 0.5)


## Under water on one breath: you swim where you look. Not deeper than `dive_depth`, not
## into the sea floor or the corals (one glides up and over them); when the breath is used
## up, or Space is pressed again, you rise calmly to the surface.
func _dive(delta: float, input: Vector2, surf: float) -> void:
	dive_seconds += delta
	_face_down = 1.0
	var look := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var speed := swim_fast if Input.is_action_pressed("sprint") else swim_speed
	var wish := look * Vector3(input.x, 0.0, input.y) * speed
	if _duck > 0.0:
		# the duck dive: head down, legs up, and under
		_duck -= delta
		wish.y = minf(wish.y, -0.85)
	if dive_seconds >= dive_time or (Input.is_action_just_pressed("jump") and dive_seconds > 0.8):
		_rising = true
	if _rising:
		wish = Vector3(wish.x * 0.5, 0.9, wish.z * 0.5)
	wish = _keep_in_lagoon(wish)
	velocity = velocity.lerp(wish, 1.0 - exp(-2.4 * delta))
	# the lowest the eyes may be: above the floor and whatever stands on it, and the dive's depth
	var p2 := Vector2(global_position.x, global_position.z)
	var floor_y := ground_height(p2)
	if _seabed == null:
		_seabed = get_node_or_null("../IslandLife/Seabed")
	if _seabed and _seabed.has_method("top_at"):
		floor_y = maxf(floor_y, float(_seabed.top_at(p2, 1.0, false)))
	var eye := global_position.y + head.position.y
	var lowest := maxf(floor_y + 0.45, surf - dive_depth)
	if eye < lowest:
		velocity.y = maxf(velocity.y, minf((lowest - eye) * 5.0, 1.6))
		if lowest - eye > 0.3:
			# (something tall right ahead: up first, then on)
			velocity.x *= 0.5
			velocity.z *= 0.5
	# (one does not swim through a fish the size of the giant grouper: it is in the way)
	var rl := get_node_or_null("../IslandLife/ReefLife")
	if rl and "grouper" in rl and not (rl.grouper as Dictionary).is_empty():
		var off: Vector3 = Vector3(global_position.x, eye, global_position.z) - (rl.grouper["pos"] as Vector3)
		var gap := off.length()
		if gap < 1.0 and gap > 0.01:
			velocity += off / gap * ((1.0 - gap) * 6.0)
	move_and_slide()
	_air_time = 0.0
	# the head is out again
	eye = global_position.y + head.position.y
	if eye > surf - 0.1 and _duck <= 0.0 and (velocity.y > -0.05 or _rising):
		_end_dive()
	_update_camera(delta, 0.0)
	_update_world_feedback()


func _swim(delta: float, input: Vector2, basis_y: Basis) -> void:
	if _sea == null:
		_sea = get_node_or_null("../SeaLife")
	var surf0: float = _sea.surface(global_position.x, global_position.z) if _sea and _sea.has_method("surface") else 0.0
	_rest = maxf(_rest - delta, 0.0)
	if not diving and Input.is_action_just_pressed("jump"):
		if not start_dive() and _rest > 0.0:
			_message("Catching your breath")
	_rustle(delta, 0.0)
	if diving:
		_dive(delta, input, surf0)
		return
	var speed := swim_fast if Input.is_action_pressed("sprint") else swim_speed
	var wish := _keep_in_lagoon(basis_y * Vector3(input.x, 0.0, input.y) * speed)
	velocity.x = lerpf(velocity.x, wish.x, 1.0 - exp(-2.2 * delta))
	velocity.z = lerpf(velocity.z, wish.z, 1.0 - exp(-2.2 * delta))
	if _sea == null:
		_sea = get_node_or_null("../SeaLife")
	var surf: float = _sea.surface(global_position.x, global_position.z) if _sea and _sea.has_method("surface") else 0.0
	_face_down = lerpf(_face_down, smoothstep(0.1, 0.36, -_pitch), 1.0 - exp(-4.0 * delta))
	var want_y := surf + lerpf(0.3, -0.3, _face_down) - head.position.y
	# (riding the swell closely: a slack float left the eyes dipping in and out of the surface)
	velocity.y = clampf((want_y - global_position.y) * 14.0, -2.5, 2.5)
	move_and_slide()
	_air_time = 0.0
	# strokes: a soft splash now and then while moving with the head up
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3:
		var prev := _stroke
		_stroke += delta * 0.7
		if floorf(_stroke) != floorf(prev) and _face_down < 0.5:
			footstep.emit("water", 0.3)
	_update_camera(delta, 0.0)
	_update_world_feedback()


# ------------------------------------------------------------------ camera
func _update_camera(delta: float, hspeed: float) -> void:
	# walking bob: lowest when a foot lands, highest mid-stride; side sway every two steps
	var amp := clampf(hspeed / walk_speed, 0.0, 1.6) if is_on_floor() else 0.0
	var phase := _step_phase - floorf(_step_phase)
	var bob_y := -(0.5 + 0.5 * cos(TAU * phase)) * 0.038 * amp
	var bob_x := sin(_sway_t) * 0.022 * amp
	var breathe := sin(Time.get_ticks_msec() * 0.0011) * 0.006
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.35)
	var target := Vector3(bob_x, bob_y + breathe - _land_dip, 0.0)
	cam.position = cam.position.lerp(target, 1.0 - exp(-14.0 * delta))
	# slight forward nod on each step and roll when strafing
	cam.rotation.x = -0.008 * amp * cos(TAU * phase)
	var side: float = Basis(Vector3.UP, _yaw).x.dot(velocity) / maxf(run_speed, 0.01)
	_cam_roll = lerpf(_cam_roll, -side * 0.025 + sin(_sway_t) * 0.004 * amp, 1.0 - exp(-5.0 * delta))
	cam.rotation.z = _cam_roll


func _update_world_feedback() -> void:
	if _ocean_mat == null:
		var w := get_parent()
		if w and w.has_method("get_material"):
			_ocean_mat = w.get_material("Ocean")
	if _ocean_mat:
		_ocean_mat.set_shader_parameter("player_pos", global_position)
		_ocean_mat.set_shader_parameter("player_speed", Vector2(velocity.x, velocity.z).length())
	_update_underwater()


## Is the camera under the sea's surface? Then the veil of water color goes over the picture
## and every sound is muffled.
func _update_underwater() -> void:
	var c := get_viewport().get_camera_3d()
	if c == null:
		return
	var cp := c.global_position
	if _sea == null:
		_sea = get_node_or_null("../SeaLife")
	var under := false
	var g := ground_height(Vector2(cp.x, cp.z))
	var tide := _tide()
	if cp.y < tide + 0.6 and g < tide - 0.3 and cp.y > g - 0.2:
		var lvl: float = _sea.surface(cp.x, cp.z) if _sea and _sea.has_method("surface") else 0.0
		under = cp.y < lvl - 0.03
	if _veil == null:
		_veil = MeshInstance3D.new()
		_veil.name = "UnderwaterVeil"
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		_veil.mesh = q
		_veil_mat = ShaderMaterial.new()
		_veil_mat.shader = load("res://shaders/underwater.gdshader")
		_veil_mat.render_priority = 100
		_veil.material_override = _veil_mat
		_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_veil.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		_veil.visible = false
		add_child(_veil)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 520.0
		lp.resonance = 0.6
		# (on the bus of everything heard through the air, not on the master: what is made in
		# the water itself stays clear. ambience.gd makes the buses)
		_muffle_bus = maxi(AudioServer.get_bus_index("World"), 0)
		_muffle = AudioServer.get_bus_effect_count(_muffle_bus)
		AudioServer.add_bus_effect(_muffle_bus, lp)
		AudioServer.set_bus_effect_enabled(_muffle_bus, _muffle, false)
	# the crackle of the snapping shrimp: the reef's own sound, heard with the head under
	# water, and as loud as there is coral about: at its fullest in the coral garden, less
	# over the ordinary reef, a far-off remainder beside a lone coral head, nothing over open
	# sand and seagrass (it carries in water: the wider circle is for what comes from afar)
	if _shrimp == null and ResourceLoader.exists("res://assets/audio/reef_crackle.wav"):
		_shrimp = AudioStreamPlayer.new()
		var cs := load("res://assets/audio/reef_crackle.wav") as AudioStreamWAV
		cs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		cs.loop_end = int(cs.get_length() * cs.mix_rate)
		_shrimp.stream = cs
		_shrimp.bus = &"Hydro" if AudioServer.get_bus_index("Hydro") >= 0 else &"Master"
		_shrimp.volume_db = -60.0
		add_child(_shrimp)
		_shrimp.play()
	if _shrimp:
		var want_db := -60.0
		if _seabed == null:
			_seabed = get_node_or_null("../IslandLife/Seabed")
		if under and _seabed and _seabed.has_method("coral_cover"):
			_crackle_t -= get_physics_process_delta_time()
			if _crackle_t <= 0.0:
				_crackle_t = 0.25
				var here := Vector2(global_position.x, global_position.z)
				# (the garden has some 0.7 of its floor under coral within 16 m, the ordinary
				# reef edge 0.45, the lagoon with its coral heads 0.15 and less)
				var near_k := clampf(float(_seabed.coral_cover(here, 16.0)) / 0.7, 0.0, 1.0)
				var far_k := clampf(float(_seabed.coral_cover(here, 40.0)) / 0.4, 0.0, 1.0)
				# (falling off faster than the coral thins out: over sand and seagrass only a
				# remainder is left)
				crackle = pow(0.85 * near_k + 0.15 * far_k, 1.5)
			want_db = CRACKLE_DB + linear_to_db(maxf(crackle, 0.006))
		else:
			_crackle_t = 0.0
		_shrimp.volume_db = lerpf(_shrimp.volume_db, want_db, 0.03)
	if under != underwater:
		underwater = under
		_veil.visible = under
		if under and _muffle_bus > 0:
			# whatever still plays straight to the master is a sound of the air too
			var world := get_parent()
			for n in world.find_children("*", "AudioStreamPlayer", true, false) + world.find_children("*", "AudioStreamPlayer3D", true, false):
				if n.get("bus") == &"Master":
					n.set("bus", &"World")
		AudioServer.set_bus_effect_enabled(_muffle_bus, _muffle, under)
	if under:
		var dc := get_node_or_null("../DayCycle")
		var light := lerpf(1.0, 0.08, dc.night if dc else 0.0)
		_veil_mat.set_shader_parameter("light", light)
		# (the last ten seconds of a breath: the edges of the picture grow dim)
		_veil_mat.set_shader_parameter("faint", smoothstep(dive_time - 10.0, dive_time, dive_seconds) if diving else 0.0)
		if _ocean_mat:
			_ocean_mat.set_shader_parameter("under_light", light)


func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "":
		dir = OS.get_user_data_dir()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := dir.path_join("tropical_island_%s.png" % stamp)
	img.save_png(path)
	# where it was taken (handy for reproducing a view): position, yaw and pitch next to the image
	var cp := cam.global_position
	var f := FileAccess.open(path.get_basename() + ".txt", FileAccess.WRITE)
	if f:
		f.store_line("camera %.2f %.2f %.2f  yaw %.1f  pitch %.1f  fov %.0f" % [cp.x, cp.y, cp.z,
			rad_to_deg(_yaw), rad_to_deg(_pitch), cam.fov])
	_message("Screenshot saved to Pictures")
