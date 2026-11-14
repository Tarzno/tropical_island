extends Node3D
## A passing rain shower: a rare event, at its natural pace.
## The sky closes from windward and the wind gets up (three minutes); then it rains for a
## quarter of an hour or a little more, swelling and easing; toward the end the sun comes
## through again while the last light rain falls, and if it stands low enough there is a
## rainbow, which stays for some minutes over the rain moving off. Afterward the ground is
## dark and dries, the trees drip, and the frogs call.
## By itself: never in the first twenty minutes, then by chance about once in a hundred
## minutes of play, and never two within an hour and a half. The N key calls one (and,
## pressed again while it rains, lets it pass).
##
## What it drives: the sky's cloud and the light (daycycle.gd: `overcast`, `haze`), the
## shader globals `rain` (rings on the sea and the pools, the dull sea) and `rain_wet` (dark
## wet ground and rock), the streaks of falling rain around the camera (shaders/rain.gdshader),
## the gray of the rain over the distance and the rainbow (shaders/weather_veil.gdshader),
## the rain's shadow under the grotto's roof (_bake_roofs), the drops that fall from the
## rims of its gaps and from the roots that hang through them (_find_drips),
## the sounds (rain on leaves, rain on the sea, dripping), the wind (ambience.gd: `storm`),
## the frogs (ambience.gd, critters.gd) and who takes cover (lizards, butterflies and
## dragonflies). The node is created by island_life.gd.

const GATHER := 180.0          # the sky closes
const EASE := 270.0            # the last of the rain: lighter, the sun coming back
const AFTER := 250.0           # after the rain: the cloud breaks up, the bow fades
const STREAKS := 7000

var time_scale := 1.0          # (for the tests)
var t := -1.0                  # seconds into the shower; below 0: there is none
var rain_len := 960.0          # how long this one rains
var rain := 0.0                # how hard it rains now: 0 .. 1
var overcast := 0.0
var wet := 0.0                 # the ground: rises in the rain, dries off afterward
var bow := 0.0                 # the rainbow
var frogs := 0.0               # how much the frogs have to say
var showers := 0
var next_in := 0.0             # seconds of play until one comes by itself

var _ls: Node
var _player: Node3D
var _daycycle: Node
var _ambience: Node
var _critters: Node
var _life: Node
var _sun: DirectionalLight3D
var _rng := RandomNumberGenerator.new()
var _swell := 0.0
var _streaks: MeshInstance3D
var _streak_mat: ShaderMaterial
var _veil: MeshInstance3D
var _veil_mat: ShaderMaterial
var _snd_rain: AudioStreamPlayer
var _snd_sea: AudioStreamPlayer
var _snd_drips: AudioStreamPlayer
## The rain's shadow under the grotto's boulders (see _bake_roofs): where rock is overhead
## along the way the rain falls, no streak is drawn and the ground stays dry; through the
## gaps in the roof the same rain falls as everywhere else.
const ROOF_CELL := 0.1                       # meters per texel of the map
const ROOF_SLANTS := [0.2, 0.35, 0.5]        # sideways per meter of fall: light rain .. gusts
## Where the rain is blown to (x, z), fair wind (m/s): the way the island's wind blows, in
## off the sea (flight.gd `WIND_DIR` (-0.97, 0, 0.24), the lean of the palms and the leaves,
## the swell: keep them in step). Until 2026-11-12 it was (1.5, 0.65), out to sea: in a
## shower the fronds streamed east and the rain slanted west, and the dry lee of every
## boulder lay to windward (found by the code review).
const RAIN_WIND := Vector2(-1.586, 0.396)
var gaps: Array = []           # the grotto's roof gaps: where rain reaches the floor, and how much of it (for the tests)
var roofs_ready := false
var _roof_rect := Rect2()      # the map's place on the level `_roof_y0` (x, z)
var _roof_y0 := 0.0
var _roof_top := 0.0
var _roof_bottom := 0.0
var _roof_w := 0
var _roof_h := 0
var _roof_i := 0
var _roof_data := PackedFloat32Array()
var _roof_tex: ImageTexture
var _open_img: Image           # the ground's share of the rain (1 open .. 0 roofed), 2 texels per meter .. see _open_ground()
var _open_ms := 0
var _open_task := -1
var _open_out := {}
## The same for the rest of the island (see _isle_mark): every boulder keeps the rain off the
## ground in its lee and under its overhang. A second, coarser map, of rock only (the ground
## never overhangs, and a trunk's lee is no shelter), worked out around the boulders only.
const ISLE_CELL := 0.25
const ISLE_LEVEL := 0.0
const OPEN := -1e4             # nothing over this line of rain
var isle_ready := false
var isle_rays := 0             # (for the tests)
var _isle_stage := 0           # 0 the boulders' places, 1 the rays, 2 the ground's map, 3 done
var _isle_rect := Rect2()
var _isle_w := 0
var _isle_h := 0
var _isle_top := 0.0
var _isle_bottom := 0.0
var _isle_data := PackedFloat32Array()
var _isle_marks := PackedByteArray()
var _isle_todo := PackedInt32Array()     # texel * 4 + slant
var _isle_i := 0
var _isle_rock := 0
var _isle_tex: ImageTexture
var _isle_task := -1
var _isle_out := {}
var _isle_ms := 0
var _rocks: Array = []         # the boulders' boxes (AABB, in the world)
var _kinds := {}               # collider -> {shape: what it is for the rain (0 a trunk, 1 the ground, 2 rock)}
var _open_bytes := PackedByteArray()     # the grotto's ground map (see _open_ground)
var _open_w := 0
var _open_h := 0
var _open_corner := Vector2.ZERO         # the ground map's corner (x, z); 20 cm a texel

## Water that runs off the rock into the grotto: the rain that falls on the pile around a gap
## runs down into it and falls from its rim, where the rock turns under, and from the tips
## of the roots that hang through it, drop by drop: heavier than rain, and still for some
## minutes when the rain is over (see _find_drips, _update_drips).
const DROPS := 256
var runoff := 0.0              # how much water runs: 0 .. 1 (up within a minute of rain, down over some minutes)
var drip_points: Array = []    # {"at", "land", "every" (s, in full flow), "from" (runs while runoff is above this), "next", "root", "gap"}
var drips_landed := 0          # (for the tests)
var drips_heard := 0
var root_ends: Array = []      # every root's lowest point: [place, height over the ground, hangs in the cave's air] (for the tests)
var _drops: Array = []         # in the air: [point, seconds since it let go, size]
var _splashes: Array = []      # [place, seconds since, size, a number of its own]
var _drip_mm: MultiMesh
var _drip_node: MultiMeshInstance3D
var _drip_mat: ShaderMaterial
var _drip_sounds: Array[AudioStream] = []
var _drip_players: Array[AudioStreamPlayer3D] = []
var _drip_quiet := 0.0
var _drip_ms := 0
var _drip_stage := 0
var _drift := Vector2.ZERO     # how far the wind has carried the rain sideways so far
var _shelter := 0.0            # under the forest's roof (0 .. 1), in the grotto (1)
var _in_cave := 0.0


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_life = get_parent()
	_daycycle = get_node_or_null("../../DayCycle")
	_ambience = get_node_or_null("../../Ambience")
	_critters = get_node_or_null("../Critters")
	_sun = get_node_or_null("../../Sun")
	_rng.randomize()
	next_in = 1200.0 + _wait()
	_make_streaks()
	_make_veil()
	_snd_rain = _sound("rain.wav")
	_snd_sea = _sound("rain_sea.wav")
	_snd_drips = _sound("drips.wav")
	_make_drips()
	if not InputMap.has_action("rain_shower"):
		InputMap.add_action("rain_shower")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_N
		InputMap.action_add_event("rain_shower", e)


## How long until the next shower, once one may come: by chance, a hundred minutes on average.
func _wait() -> float:
	return -log(maxf(_rng.randf(), 0.001)) * 6000.0


func _sound(file: String) -> AudioStreamPlayer:
	var path := "res://assets/audio/" + file
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = "Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else "Master"
	p.volume_db = -80.0
	add_child(p)
	return p


func _make_streaks() -> void:
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var g := RandomNumberGenerator.new()
	g.seed = 31
	for i in STREAKS:
		var c := Color(g.randf(), g.randf(), g.randf(), (i + 0.5) / STREAKS)
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(Vector3.ZERO)
			colors.append(c)
			uvs.append(corner)
		idx.append_array([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = load("res://shaders/rain.gdshader")
	_streak_mat.render_priority = 20
	_streaks = MeshInstance3D.new()
	_streaks.name = "Rain"
	_streaks.mesh = mesh
	_streaks.material_override = _streak_mat
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streaks.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_streaks.visible = false
	add_child(_streaks)


func _make_veil() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = load("res://shaders/weather_veil.gdshader")
	_veil_mat.render_priority = 60
	_veil = MeshInstance3D.new()
	_veil.name = "WeatherVeil"
	_veil.mesh = q
	_veil.material_override = _veil_mat
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_veil.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_veil.visible = false
	add_child(_veil)


func _physics_process(_delta: float) -> void:
	# (the rain's shadow is found with ray casts: the collision shapes are there after a few
	# physics frames; a few milliseconds of rays in every frame until the map is full)
	if _ls == null or Engine.get_physics_frames() < 40:
		return
	if not roofs_ready:
		_bake_roofs(3000)
	elif _drip_stage < 3:
		# (then the drips, a part in each frame, and the ground's map beside the game)
		_find_drips(_drip_stage)
		_drip_stage += 1
		if _drip_stage == 3 and _roof_w > 0:
			_open_task = WorkerThreadPool.add_task(_open_ground)
	elif _open_task >= 0:
		if WorkerThreadPool.is_task_completed(_open_task):
			_apply_open()
	elif _isle_stage == 0:
		_isle_mark(3000)
	elif _isle_stage == 1:
		_isle_rays(3000)
	elif _isle_stage == 2:
		if _isle_task < 0 or WorkerThreadPool.is_task_completed(_isle_task):
			_apply_isle()
	else:
		set_physics_process(false)


## The grotto: rain comes in where the roof is open to the sky, and nowhere else under it.
## A map of the rain's shadow, like a shadow map with the rain for a light: for every tenth
## of a meter of a level plane through the cave (`_roof_y0`) a ray is sent down the way the
## rain falls, from above everything, and the height at which it first meets rock or ground
## is kept. A drop on that line exists above that height and not below it. The rain's slant
## changes with the wind, and a gap that leans takes more or less rain with it: so there are
## three such maps, for three slants (the texture's red, green and blue), and the rain's
## shader goes by the two nearest to each streak's own slant.
## `budget`: microseconds to spend in this call (0: all of it now).
func _bake_roofs(budget := 0) -> void:
	if roofs_ready:
		return
	var grotto := _ls.get_node_or_null("Grotto") as MeshInstance3D
	if grotto == null or not ("cave" in _ls) or not (_ls.cave as Dictionary).has("skylights"):
		roofs_ready = true
		_drip_stage = 3
		return
	var dir := RAIN_WIND.normalized()
	if _roof_w == 0:
		var box := grotto.get_aabb()
		_roof_y0 = float(_ls.cave["front"][1]) + 1.0
		# every line of rain that touches the pile crosses the plane inside this rectangle
		var steep: float = ROOF_SLANTS[ROOF_SLANTS.size() - 1]
		var lee := dir * steep * (box.end.y - _roof_y0)
		var luv := dir * steep * (_roof_y0 - box.position.y)
		# (whichever way the wind blows: the rectangle was laid out for a wind toward +x
		# and +z only, and with the wind turned around it missed the pile's weather side)
		var lo2 := Vector2(box.position.x, box.position.z) + Vector2(minf(minf(lee.x, -luv.x), 0.0), minf(minf(lee.y, -luv.y), 0.0)) - Vector2(1.0, 1.0)
		var hi2 := Vector2(box.end.x, box.end.z) + Vector2(maxf(maxf(lee.x, -luv.x), 0.0), maxf(maxf(lee.y, -luv.y), 0.0)) + Vector2(1.0, 1.0)
		_roof_rect = Rect2(lo2, hi2 - lo2)
		_roof_w = int(ceil(_roof_rect.size.x / ROOF_CELL))
		_roof_h = int(ceil(_roof_rect.size.y / ROOF_CELL))
		_roof_rect.size = Vector2(_roof_w, _roof_h) * ROOF_CELL
		var hi := box.end.y
		var lo := box.position.y
		var x := _roof_rect.position.x
		while x <= _roof_rect.end.x:
			var z := _roof_rect.position.y
			while z <= _roof_rect.end.y:
				var g: float = _ls.ground(x, z)
				hi = maxf(hi, g)
				lo = minf(lo, g)
				z += 2.0
			x += 2.0
		_roof_top = hi + 15.0
		_roof_bottom = lo - 2.0
		_roof_data.resize(_roof_w * _roof_h * 4)
		_roof_i = 0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	var t0 := Time.get_ticks_usec()
	var total := _roof_w * _roof_h
	var up := _roof_top - _roof_y0
	var down := _roof_y0 - _roof_bottom
	while _roof_i < total:
		var at := _roof_rect.position + (Vector2(_roof_i % _roof_w, _roof_i / _roof_w) + Vector2(0.5, 0.5)) * ROOF_CELL
		for k in 3:
			var lean: Vector2 = dir * (ROOF_SLANTS[k] as float)
			q.from = Vector3(at.x - lean.x * up, _roof_top, at.y - lean.y * up)
			q.to = Vector3(at.x + lean.x * down, _roof_bottom, at.y + lean.y * down)
			var hit := space.intersect_ray(q)
			_roof_data[_roof_i * 4 + k] = (hit["position"] as Vector3).y if not hit.is_empty() else _roof_bottom
		_roof_data[_roof_i * 4 + 3] = 1.0
		_roof_i += 1
		if budget > 0 and (_roof_i & 63) == 0 and Time.get_ticks_usec() - t0 > budget:
			return
	# the map is full
	roofs_ready = true
	var img := Image.create_from_data(_roof_w, _roof_h, false, Image.FORMAT_RGBAF, _roof_data.to_byte_array())
	_roof_tex = ImageTexture.create_from_image(img)
	_streak_mat.set_shader_parameter("roof_map", _roof_tex)
	_streak_mat.set_shader_parameter("roof_rect", Vector4(_roof_rect.position.x, _roof_rect.position.y, 1.0 / _roof_rect.size.x, 1.0 / _roof_rect.size.y))
	_streak_mat.set_shader_parameter("roof_slants", Vector4(ROOF_SLANTS[0], ROOF_SLANTS[1], ROOF_SLANTS[2], _roof_y0))
	_streak_mat.set_shader_parameter("roofs", true)
	# the rock under the roof stays dry (triplanar_rock.gdshader: by this map too, since rock
	# is at any height)
	var world := _ls.get_parent()
	var rock: ShaderMaterial = world.get_material("SeyGranite") if world and world.has_method("get_material") else null
	if rock:
		rock.set_shader_parameter("rain_roof_map", _roof_tex)
		rock.set_shader_parameter("rain_roof_rect", Vector4(_roof_rect.position.x, _roof_rect.position.y, 1.0 / _roof_rect.size.x, 1.0 / _roof_rect.size.y))
		rock.set_shader_parameter("rain_roof_slants", Vector4(ROOF_SLANTS[0], ROOF_SLANTS[1], ROOF_SLANTS[2], _roof_y0))
		rock.set_shader_parameter("rain_lee", dir)
		rock.set_shader_parameter("rain_roofs", true)


## The first thing the rain meets on its line through the place `p`, at slant number `k`:
## its height (far below everything where the line is outside the map).
func _roof_height(p: Vector3, k: int) -> float:
	var at := Vector2(p.x, p.z) + RAIN_WIND.normalized() * (ROOF_SLANTS[k] as float) * (p.y - _roof_y0)
	var c := ((at - _roof_rect.position) / ROOF_CELL).floor()
	if c.x < 0.0 or c.y < 0.0 or c.x >= _roof_w or c.y >= _roof_h:
		return -1e4
	return _roof_data[(int(c.y) * _roof_w + int(c.x)) * 4 + k]


## The ground under the roof stays dry, except where the rain comes through: a second, small
## map for the ground's shader (sand.gdshader: `rain_open`), from above, 1 where the rain
## reaches the ground at any of the three slants (over a shower the wind tries them all),
## 0 where rock is over it, with a soft edge. And what the gaps let through, for the tests.
## (Runs on a worker thread: it only reads, and leaves its result in `_open_out`.)
func _open_ground() -> void:
	var t0 := Time.get_ticks_msec()
	var cell := 0.2
	var w := int(ceil(_roof_rect.size.x / cell))
	var h := int(ceil(_roof_rect.size.y / cell))
	var open := PackedFloat32Array()
	open.resize(w * h)
	var cave: Dictionary = _ls.cave
	var lights: Array = cave["skylights"]
	var found: Array = []
	for sk: Dictionary in lights:
		found.append({"at": Vector3.ZERO, "r": 0.0, "open floor (m2) by slant": [0.0, 0.0, 0.0], "open floor (m2), any slant": 0.0})
	for j in h:
		for i in w:
			var x := _roof_rect.position.x + (i + 0.5) * cell
			var z := _roof_rect.position.y + (j + 0.5) * cell
			var p := Vector3(x, _ls.ground(x, z), z)
			var any := false
			var inside := -1
			for k in 3:
				# (the ground itself is the first thing met: the terrain's mesh lies within a
				# hand's width of the height map; a roof is meters over it)
				if _roof_height(p, k) < p.y + 0.45:
					if not any and _ls.cave_inside(p + Vector3(0, 0.3, 0)):
						for n in lights.size():
							var fl: Array = lights[n]["floor"]
							if Vector2(x - float(fl[0]), z - float(fl[2])).length() < 4.5:
								inside = n
					any = true
					if inside >= 0:
						(found[inside]["open floor (m2) by slant"] as Array)[k] += cell * cell
			if any and inside >= 0:
				found[inside]["open floor (m2), any slant"] += cell * cell
				found[inside]["at"] += p
			open[j * w + i] = 1.0 if any else 0.0
	for g: Dictionary in found:
		var cells: float = float(g["open floor (m2), any slant"]) / (cell * cell)
		if cells > 0.0:
			g["at"] = (g["at"] as Vector3) / cells
			g["r"] = sqrt(float(g["open floor (m2), any slant"]) / PI)
	# (a trunk keeps the rain off a strip of ground a hand wide in its lee, by this map: in
	# truth the wind does not hold its line so well. Dry places narrower than 0.8 m are closed)
	for grow: bool in [true, false]:
		var from := open.duplicate()
		for j in range(2, h - 2):
			for i in range(2, w - 2):
				var v: float = from[j * w + i]
				for dj in range(-2, 3):
					for di in range(-2, 3):
						var o: float = from[(j + dj) * w + i + di]
						v = maxf(v, o) if grow else minf(v, o)
				open[j * w + i] = v
	# (where a drop keeps landing the ground is wet too: a dot under every drip)
	for d: Dictionary in drip_points:
		var land: Vector3 = d["land"]
		if absf(land.y - float(_ls.ground(land.x, land.z))) > 0.3:
			continue
		var ci := int((land.x - _roof_rect.position.x) / cell)
		var cj := int((land.z - _roof_rect.position.y) / cell)
		if ci > 6 and cj > 6 and ci < w - 6 and cj < h - 6:
			open[cj * w + ci] = 1.0
	for j in h:
		for i in w:
			if i < 6 or j < 6 or i >= w - 6 or j >= h - 6:
				open[j * w + i] = 1.0      # (the map's rim is open ground: no step where it ends)
	# a soft edge (the wind moves the place where the rain lands by a hand's width or two)
	for pass_ in 2:
		var src := open.duplicate()
		for j in range(1, h - 1):
			for i in range(1, w - 1):
				var sum := 0.0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						sum += src[(j + dj) * w + i + di]
				open[j * w + i] = sum / 9.0
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for n in w * h:
		bytes[n] = int(clampf(open[n], 0.0, 1.0) * 255.0)
	_open_out = {"bytes": bytes, "w": w, "h": h, "cell": cell, "gaps": found, "ms": Time.get_ticks_msec() - t0}


## The ground's map is worked out: to the ground's shader with it.
func _apply_open() -> void:
	if _open_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_open_task)
	_open_task = -1
	var w: int = _open_out["w"]
	var h: int = _open_out["h"]
	var cell: float = _open_out["cell"]
	gaps = _open_out["gaps"]
	_open_ms = _open_out["ms"]
	_open_bytes = _open_out["bytes"]
	_open_w = w
	_open_h = h
	_open_img = Image.create_from_data(w, h, false, Image.FORMAT_R8, _open_bytes)
	_open_corner = _roof_rect.position
	_open_out = {}
	var world := _ls.get_parent()
	var sand: ShaderMaterial = world.get_material("Sand") if world and world.has_method("get_material") else null
	if sand:
		sand.set_shader_parameter("rain_open", ImageTexture.create_from_image(_open_img))
		sand.set_shader_parameter("rain_open_rect", Vector4(_roof_rect.position.x, _roof_rect.position.y, 1.0 / (w * cell), 1.0 / (h * cell)))
		sand.set_shader_parameter("rain_roofs", true)


# ------------------------------------------------------------------ the rest of the island
## What a ray has met, for the rain: 2 rock that keeps rain off (a boulder, the grotto), 1 the
## ground, 0 anything else (a trunk, a log: the rain goes around it). The collision shapes say
## so themselves (meta "rain": world.gd, landscape.gd).
func _kind(hit: Dictionary) -> int:
	var body: Object = hit["collider"]
	var shape: int = hit["shape"]
	if not _kinds.has(body):
		_kinds[body] = {}
	var of: Dictionary = _kinds[body]
	if not of.has(shape):
		var co := body as CollisionObject3D
		var node: Object = co.shape_owner_get_owner(co.shape_find_owner(shape)) if co else null
		of[shape] = int(node.get_meta("rain", 0)) if node else 0
	return of[shape]


## Where on the map's plane the rain's lines lie that can touch this box, at slant number `k`.
func _isle_shadow(box: AABB, k: int) -> Rect2:
	var lean: Vector2 = RAIN_WIND.normalized() * (ROOF_SLANTS[k] as float)
	var a := lean * (box.position.y - ISLE_LEVEL)
	var b := lean * (box.end.y - ISLE_LEVEL)
	var r := Rect2(box.position.x + minf(a.x, b.x), box.position.z + minf(a.y, b.y), box.size.x + absf(b.x - a.x), box.size.z + absf(b.y - a.y))
	return r.grow(ISLE_CELL * 1.5)


## The boulders, and the map's texels whose lines of rain can touch one: only those get a ray
## (some hundred thousand, of two million). `budget`: microseconds for this call (0: all).
func _isle_mark(budget := 0) -> void:
	var t0 := Time.get_ticks_usec()
	if _rocks.is_empty() and _isle_rock == 0:
		var from: Array = []
		var boulders := _ls.get_node_or_null("Boulders")
		if boulders:
			from.append_array(boulders.find_children("*", "MeshInstance3D", true, false))
		var rocks := _ls.get_parent().get_node_or_null("Rocks") if _ls.get_parent() else null
		if rocks:
			from.append_array(rocks.find_children("*", "MeshInstance3D", true, false))
		var all := Rect2()
		_isle_top = -1e6
		_isle_bottom = 1e6
		for mi: MeshInstance3D in from:
			if mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			_rocks.append(box)
			_isle_top = maxf(_isle_top, box.end.y + 1.0)
			_isle_bottom = minf(_isle_bottom, box.position.y - 1.0)
			for k in 3:
				var r := _isle_shadow(box, k)
				all = r if _rocks.size() == 1 and k == 0 else all.merge(r)
		if _rocks.is_empty():
			_isle_stage = 3
			return
		_isle_rect = all.grow(1.0)
		_isle_w = int(ceil(_isle_rect.size.x / ISLE_CELL))
		_isle_h = int(ceil(_isle_rect.size.y / ISLE_CELL))
		_isle_rect.size = Vector2(_isle_w, _isle_h) * ISLE_CELL
		_isle_data.resize(_isle_w * _isle_h * 4)
		_isle_data.fill(OPEN)
		_isle_marks.resize(_isle_w * _isle_h)
		_isle_marks.fill(0)
	while _isle_rock < _rocks.size():
		var box: AABB = _rocks[_isle_rock]
		_isle_rock += 1
		for k in 3:
			var r := _isle_shadow(box, k)
			var i0 := clampi(int((r.position.x - _isle_rect.position.x) / ISLE_CELL), 0, _isle_w - 1)
			var i1 := clampi(int((r.end.x - _isle_rect.position.x) / ISLE_CELL), 0, _isle_w - 1)
			var j0 := clampi(int((r.position.y - _isle_rect.position.y) / ISLE_CELL), 0, _isle_h - 1)
			var j1 := clampi(int((r.end.y - _isle_rect.position.y) / ISLE_CELL), 0, _isle_h - 1)
			var bit := 1 << k
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var n := j * _isle_w + i
					if _isle_marks[n] & bit == 0:
						_isle_marks[n] |= bit
						_isle_todo.append(n * 4 + k)
		if budget > 0 and Time.get_ticks_usec() - t0 > budget:
			return
	_isle_marks.resize(0)
	_isle_stage = 1


## The rays: down the way the rain falls, from above every boulder; the first rock met is
## kept. The ground ends a ray (nothing was over it), a trunk does not (the ray goes on).
func _isle_rays(budget := 0) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	var dir := RAIN_WIND.normalized()
	var t0 := Time.get_ticks_usec()
	var up := _isle_top - ISLE_LEVEL
	var down := ISLE_LEVEL - _isle_bottom
	while _isle_i < _isle_todo.size():
		var e := _isle_todo[_isle_i]
		_isle_i += 1
		var n := e >> 2
		var k := e & 3
		var at := _isle_rect.position + (Vector2(n % _isle_w, n / _isle_w) + Vector2(0.5, 0.5)) * ISLE_CELL
		var lean: Vector2 = dir * (ROOF_SLANTS[k] as float)
		var from := Vector3(at.x - lean.x * up, _isle_top, at.y - lean.y * up)
		var to := Vector3(at.x + lean.x * down, _isle_bottom, at.y + lean.y * down)
		var step := (to - from).normalized() * 0.05
		for tries in 6:
			q.from = from
			q.to = to
			var hit := space.intersect_ray(q)
			isle_rays += 1
			if hit.is_empty():
				break
			var kind := _kind(hit)
			if kind == 2:
				_isle_data[n * 4 + k] = (hit["position"] as Vector3).y
				break
			if kind == 1:
				break
			from = (hit["position"] as Vector3) + step
			if from.y <= _isle_bottom:
				break
		if budget > 0 and (_isle_i & 31) == 0 and Time.get_ticks_usec() - t0 > budget:
			return
	_isle_todo.resize(0)
	var img := Image.create_from_data(_isle_w, _isle_h, false, Image.FORMAT_RGBAF, _isle_data.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	_isle_tex = ImageTexture.create_from_image(img)
	var rect := Vector4(_isle_rect.position.x, _isle_rect.position.y, 1.0 / _isle_rect.size.x, 1.0 / _isle_rect.size.y)
	var world := _ls.get_parent()
	var rock: ShaderMaterial = world.get_material("SeyGranite") if world and world.has_method("get_material") else null
	for m: ShaderMaterial in [_streak_mat, rock]:
		if m:
			m.set_shader_parameter("isle_map", _isle_tex)
			m.set_shader_parameter("isle_rect", rect)
			m.set_shader_parameter("isle_level", ISLE_LEVEL)
			m.set_shader_parameter("isles", true)
	if rock:
		rock.set_shader_parameter("rain_roof_slants", Vector4(ROOF_SLANTS[0], ROOF_SLANTS[1], ROOF_SLANTS[2], _roof_y0))
		rock.set_shader_parameter("rain_lee", dir)
	_streak_mat.set_shader_parameter("roof_slants", Vector4(ROOF_SLANTS[0], ROOF_SLANTS[1], ROOF_SLANTS[2], _roof_y0))
	_isle_stage = 2
	_isle_task = WorkerThreadPool.add_task(_isle_ground)


## The first thing the rain meets on its line through `p` at slant `k`, anywhere on the
## island: by the grotto's fine map where that covers the line, else by the island's.
func _first_roof(p: Vector3, k: int) -> float:
	var lean: Vector2 = RAIN_WIND.normalized() * (ROOF_SLANTS[k] as float)
	if _roof_w > 0:
		var c := ((Vector2(p.x, p.z) + lean * (p.y - _roof_y0) - _roof_rect.position) / ROOF_CELL).floor()
		if c.x >= 0.0 and c.y >= 0.0 and c.x < _roof_w and c.y < _roof_h:
			return _roof_data[(int(c.y) * _roof_w + int(c.x)) * 4 + k]
	var d := ((Vector2(p.x, p.z) + lean * (p.y - ISLE_LEVEL) - _isle_rect.position) / ISLE_CELL).floor()
	if d.x < 0.0 or d.y < 0.0 or d.x >= _isle_w or d.y >= _isle_h:
		return OPEN
	return _isle_data[(int(d.y) * _isle_w + int(d.x)) * 4 + k]


## The ground's map for the whole island (sand.gdshader: `rain_open`), in place of the
## grotto's own, which is copied into it: 20 cm a texel, 1 open to the rain. Worked out
## only in the 4 m squares a boulder's lee can reach; everywhere else the ground is open.
## (Runs on a worker thread: it only reads, and leaves its result in `_isle_out`.)
func _isle_ground() -> void:
	var t0 := Time.get_ticks_msec()
	var cell := 0.2
	var lee := RAIN_WIND.normalized()
	var steep: float = ROOF_SLANTS[2]
	# where each boulder can keep the ground dry: under it and in its lee
	var lands: Array = []
	var all := _roof_rect
	for box: AABB in _rocks:
		var reach := lee * steep * (box.size.y + 1.5)
		# (under it and to leeward, whichever way that is: with `+ reach` on the far corner
		# only, a wind toward -x left the lee out)
		var r := Rect2(box.position.x - 0.8 + minf(reach.x, 0.0), box.position.z - 0.8 + minf(reach.y, 0.0), box.size.x + 1.6 + absf(reach.x), box.size.z + 1.6 + absf(reach.y))
		lands.append(r)
		all = r if all.size == Vector2.ZERO else all.merge(r)
	all = all.grow(2.0)
	# (texel on texel with the grotto's map)
	var origin := _roof_rect.position if _roof_w > 0 else all.position
	var i_off := int(floor((all.position.x - origin.x) / cell))
	var j_off := int(floor((all.position.y - origin.y) / cell))
	var corner := origin + Vector2(i_off, j_off) * cell
	var w := int(ceil((all.end.x - corner.x) / cell))
	var h := int(ceil((all.end.y - corner.y) / cell))
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	bytes.fill(255)
	for j in _open_h:
		for i in _open_w:
			bytes[(j - j_off) * w + i - i_off] = _open_bytes[j * _open_w + i]
	var tile := 20
	var tiles := {}
	for r: Rect2 in lands:
		var a := ((r.position - corner) / (cell * tile)).floor()
		var b := ((r.end - corner) / (cell * tile)).floor()
		for tj in range(int(a.y), int(b.y) + 1):
			for ti in range(int(a.x), int(b.x) + 1):
				tiles[Vector2i(ti, tj)] = true
	var apron := 3
	var side := tile + 2 * apron
	var open := PackedFloat32Array()
	open.resize(side * side)
	var cells := 0
	for t: Vector2i in tiles:
		var any_dry := false
		for j in side:
			for i in side:
				var x := corner.x + (t.x * tile + i - apron + 0.5) * cell
				var z := corner.y + (t.y * tile + j - apron + 0.5) * cell
				var p := Vector3(x, _ls.ground(x, z), z)
				var reached := false
				for k in 3:
					if _first_roof(p, k) < p.y + 0.45:
						reached = true
						break
				open[j * side + i] = 1.0 if reached else 0.0
				any_dry = any_dry or not reached
		if not any_dry:
			continue
		for pass_ in 2:
			var src := open.duplicate()
			for j in range(1, side - 1):
				for i in range(1, side - 1):
					var sum := 0.0
					for dj in range(-1, 2):
						for di in range(-1, 2):
							sum += src[(j + dj) * side + i + di]
					open[j * side + i] = sum / 9.0
		for j in range(apron, side - apron):
			for i in range(apron, side - apron):
				var ci := t.x * tile + i - apron
				var cj := t.y * tile + j - apron
				if ci < 0 or cj < 0 or ci >= w or cj >= h:
					continue
				# (the grotto's own, finer answer stands)
				var gi := ci + i_off
				var gj := cj + j_off
				if gi >= 0 and gj >= 0 and gi < _open_w and gj < _open_h:
					continue
				bytes[cj * w + ci] = int(clampf(open[j * side + i], 0.0, 1.0) * 255.0)
				cells += 1
	_isle_out = {"bytes": bytes, "w": w, "h": h, "cell": cell, "corner": corner, "tiles": tiles.size(), "cells": cells, "ms": Time.get_ticks_msec() - t0}


func _apply_isle() -> void:
	_isle_stage = 3
	set_physics_process(false)
	if _isle_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_isle_task)
	_isle_task = -1
	var w: int = _isle_out["w"]
	var h: int = _isle_out["h"]
	var cell: float = _isle_out["cell"]
	var corner: Vector2 = _isle_out["corner"]
	_isle_ms = _isle_out["ms"]
	_open_img = Image.create_from_data(w, h, false, Image.FORMAT_R8, _isle_out["bytes"])
	_open_corner = corner
	_isle_out = {"tiles": _isle_out["tiles"], "cells": _isle_out["cells"]}
	var world := _ls.get_parent()
	var sand: ShaderMaterial = world.get_material("Sand") if world and world.has_method("get_material") else null
	if sand:
		sand.set_shader_parameter("rain_open", ImageTexture.create_from_image(_open_img))
		sand.set_shader_parameter("rain_open_rect", Vector4(corner.x, corner.y, 1.0 / (w * cell), 1.0 / (h * cell)))
		sand.set_shader_parameter("rain_roofs", true)
	isle_ready = true


func _make_drips() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_drip_mm = MultiMesh.new()
	_drip_mm.transform_format = MultiMesh.TRANSFORM_3D
	_drip_mm.use_custom_data = true
	_drip_mm.mesh = quad
	_drip_mm.instance_count = DROPS
	_drip_mm.visible_instance_count = 0
	_drip_mat = ShaderMaterial.new()
	_drip_mat.shader = load("res://shaders/drip.gdshader")
	_drip_mat.render_priority = 21
	_drip_node = MultiMeshInstance3D.new()
	_drip_node.name = "GrottoDrips"
	_drip_node.multimesh = _drip_mm
	_drip_node.material_override = _drip_mat
	_drip_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drip_node.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_drip_node.visible = false
	add_child(_drip_node)
	for i in 8:
		var path := "res://assets/audio/drip_%d.wav" % i
		if ResourceLoader.exists(path):
			_drip_sounds.append(load(path))
	for i in 4:
		var dp := AudioStreamPlayer3D.new()
		dp.unit_size = 2.2
		dp.max_distance = 20.0
		dp.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
		add_child(dp)
		_drip_players.append(dp)


## Where the water that runs off the rock falls into the grotto.
## (a) The rims of the gaps. From the floor around each gap rays are sent straight up to the
## roof. Where the roof's height leaps up from one ray to the next, the lower one has met a
## lip: rock that turns under. If rain can reach the air just beyond that lip (the rain's
## shadow map says so), the lip belongs to a gap the rain comes through, its upper side is
## rained on, and what runs down it lets go there.
## (b) The roots that hang through the big gap (the mesh GrottoRoots: a tube each): the
## lowest point of each that ends in the air of the cave. Water runs down a root to its tip.
## Every drip has its own pace, and its own share of the run-off below which it stops.
## `stage`: 0 the big gap's rim, 1 the small one's, 2 the roots (a frame each: 10-25 ms).
func _find_drips(stage: int) -> void:
	var t0 := Time.get_ticks_msec()
	if stage == 0:
		drip_points.clear()
	if _roof_w == 0:
		return
	var cave: Dictionary = _ls.cave
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	var g := RandomNumberGenerator.new()
	g.seed = 99 + stage
	var lights: Array = cave["skylights"]
	var step := 0.125
	for n in lights.size():
		if n != stage:
			continue
		var sk: Dictionary = lights[n]
		var fl := Vector3(sk["floor"][0], sk["floor"][1], sk["floor"][2])
		var axis := Vector3(sk["dir"][0], sk["dir"][1], sk["dir"][2]).normalized()
		var room: Array = cave["inner_size"] if n == 0 else cave["front_size"]
		var up_there := fl + axis * (float(room[1]) / maxf(axis.y, 0.3))
		var rect := Rect2(fl.x, fl.z, 0.0, 0.0).expand(Vector2(up_there.x, up_there.z)).grow(2.5)
		var w := int(rect.size.x / step) + 1
		var h := int(rect.size.y / step) + 1
		# the roof's height over every place of the floor (-1: no place of the cave's; 1e4: the sky)
		var roof := PackedFloat32Array()
		roof.resize(w * h)
		for j in h:
			for i in w:
				var x := rect.position.x + i * step
				var z := rect.position.y + j * step
				var p := Vector3(x, float(_ls.ground(x, z)) + 0.15, z)
				roof[j * w + i] = -1.0
				if not _ls.cave_inside(p + Vector3(0, 0.3, 0)):
					continue
				q.from = p
				q.to = Vector3(x, _roof_top, z)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					roof[j * w + i] = 1e4
				elif (hit["position"] as Vector3).y > p.y + 1.2:      # (not the inside of a stone on the floor)
					roof[j * w + i] = (hit["position"] as Vector3).y
		var lips: Array = []
		for j in range(1, h - 1):
			for i in range(1, w - 1):
				var c := roof[j * w + i]
				if c < 0.0 or c > 9e3:
					continue
				var lip := false
				for nb: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var cb := roof[(j + nb.y) * w + i + nb.x]
					if cb < c + 0.5:
						continue
					# (does the rain come by, just beyond the lip?)
					var beyond := Vector3(rect.position.x + (i + nb.x) * step, c + 0.25, rect.position.y + (j + nb.y) * step)
					for k in 3:
						if _roof_height(beyond, k) < beyond.y:
							lip = true
				if lip:
					lips.append(Vector3(rect.position.x + i * step, c - 0.02, rect.position.y + j * step))
		# some of them, not too close together
		var want := 12 if n == 0 else 7
		var taken: Array = []
		for tries in lips.size() * 3:
			if taken.size() >= want or lips.is_empty():
				break
			var c: Vector3 = lips[g.randi() % lips.size()]
			var free := true
			for o: Vector3 in taken:
				if o.distance_to(c) < 0.32:
					free = false
			if free:
				taken.append(c)
		for c: Vector3 in taken:
			_add_drip(c, false, n, g, space, q)
	# the roots' tips: every tube of the mesh by itself (corners that share a triangle belong together)
	var roots := _ls.get_node_or_null("GrottoRoots") as MeshInstance3D
	if stage == 2 and roots and roots.mesh and roots.mesh.get_surface_count() > 0:
		var arr := roots.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var of := PackedInt32Array()
		of.resize(verts.size())
		for i in verts.size():
			of[i] = i
		var k := 0
		while k + 2 < idx.size():
			for e in 2:
				var a := idx[k + e]
				var b := idx[k + e + 1]
				while of[a] != a:
					of[a] = of[of[a]]
					a = of[a]
				while of[b] != b:
					of[b] = of[of[b]]
					b = of[b]
				if a != b:
					of[a] = b
			k += 3
		var lowest := {}
		for i in verts.size():
			var a := i
			while of[a] != a:
				a = of[a]
			if not lowest.has(a) or verts[i].y < (lowest[a] as Vector3).y:
				lowest[a] = verts[i]
		for a: int in lowest:
			var tip: Vector3 = lowest[a]
			# (one that ends in the air of the cave, the gap's throat too: over the cave's floor,
			# clear of it, and with nothing between the floor and itself. Rock is solid to a
			# ray from outside only: so the ray comes up from the floor)
			var under := Vector3(tip.x, float(_ls.ground(tip.x, tip.z)) + 0.15, tip.z)
			var hangs := false
			if _ls.cave_inside(under + Vector3(0, 0.15, 0)) and tip.y > under.y + 0.03:
				q.from = under
				q.to = tip
				hangs = space.intersect_ray(q).is_empty()
			root_ends.append([tip, snappedf(tip.y - under.y + 0.15, 0.01), hangs])
			if hangs:
				_add_drip(tip - Vector3(0, 0.01, 0), true, 0, g, space, q)
	_drip_ms = maxi(_drip_ms, Time.get_ticks_msec() - t0)


func _add_drip(at: Vector3, root: bool, gap: int, g: RandomNumberGenerator, space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D) -> void:
	q.from = at - Vector3(0, 0.05, 0)
	q.to = Vector3(at.x, _roof_bottom, at.z)
	var hit := space.intersect_ray(q)
	var land: Vector3 = hit["position"] if not hit.is_empty() else Vector3(at.x, _ls.ground(at.x, at.z), at.z)
	if at.y - land.y < 0.15:
		return
	# (a drop every third of a second where most runs, every two or three where little does;
	# roots hold their water longer)
	var every := exp(g.randf_range(log(0.5), log(2.6))) if root else exp(g.randf_range(log(0.32), log(2.2)))
	drip_points.append({"at": at, "land": land, "every": every, "from": g.randf_range(0.02, 0.22) if root else g.randf_range(0.04, 0.4),
		"next": g.randf() * every, "root": root, "gap": gap})


## The drops in the air, and the splash of each on the ground.
func _update_drips(dt: float, light: float, pp: Vector3) -> void:
	# the run-off: it takes the rock most of a minute to shed what falls on it, and some
	# minutes to drain when the rain is over
	var want := clampf(rain * 1.7, 0.0, 1.0)
	runoff += (want - runoff) * (1.0 - exp(-dt / (35.0 if want > runoff else 140.0)))
	if runoff < 0.012 and want == 0.0:
		runoff = 0.0
	if drip_points.is_empty():
		return
	var near := pp.distance_to(drip_points[0]["at"] as Vector3) < 55.0
	if (runoff <= 0.0 and _drops.is_empty() and _splashes.is_empty()) or not near:
		if _drip_node.visible:
			_drip_node.visible = false
			_drops.clear()
			_splashes.clear()
		return
	_drip_quiet -= dt
	for n in drip_points.size():
		var d: Dictionary = drip_points[n]
		var from: float = d["from"]
		if runoff <= from:
			continue
		# (faster the more runs; the last drops of a drying drip come far apart)
		var flow := clampf((runoff - from) / (1.0 - from), 0.0, 1.0)
		d["next"] = float(d["next"]) - dt * (0.08 + 0.92 * pow(flow, 0.7))
		if float(d["next"]) <= 0.0:
			d["next"] = float(d["every"]) * _rng.randf_range(0.75, 1.3)
			if _drops.size() < DROPS - 48:
				_drops.append([n, 0.0, _rng.randf_range(0.8, 1.25)])
	var count := 0
	var i := 0
	while i < _drops.size():
		var dr: Array = _drops[i]
		var d: Dictionary = drip_points[int(dr[0])]
		var age: float = float(dr[1]) + dt
		dr[1] = age
		var at: Vector3 = d["at"]
		var land: Vector3 = d["land"]
		var fallen := 4.9 * age * age
		if at.y - fallen <= land.y:
			_drops.remove_at(i)
			drips_landed += 1
			if _splashes.size() < 44:
				_splashes.append([land + Vector3(0, 0.012, 0), 0.0, float(dr[2]), _rng.randf()])
			_drip_sound(land, at.y - land.y, pp)
			continue
		# (as long as it falls in a 45th of a second: a bead when it lets go, a streak further down)
		var speed := 9.8 * age
		var length := maxf(0.014, speed * 0.022) * float(dr[2])
		_drip_mm.set_instance_transform(count, Transform3D(Basis.IDENTITY, Vector3(at.x, at.y - fallen + length * 0.5, at.z)))
		_drip_mm.set_instance_custom_data(count, Color(length, 0.008 * float(dr[2]), 0.85, 0.0))
		count += 1
		i += 1
	i = 0
	while i < _splashes.size():
		var sp: Array = _splashes[i]
		var age: float = float(sp[1]) + dt
		sp[1] = age
		if age > 0.22:
			_splashes.remove_at(i)
			continue
		var f := age / 0.22
		_drip_mm.set_instance_transform(count, Transform3D(Basis.IDENTITY, sp[0] as Vector3))
		_drip_mm.set_instance_custom_data(count, Color(lerpf(0.02, 0.085, sqrt(f)) * float(sp[2]), float(sp[3]), 0.7 * (1.0 - f), 1.0))
		count += 1
		i += 1
	_drip_mm.visible_instance_count = count
	_drip_node.visible = count > 0
	_drip_mat.set_shader_parameter("light", light)


## A drop is heard where it lands: not every one (there are many), the near ones rather; one
## that has fallen far is louder.
func _drip_sound(land: Vector3, fall: float, pp: Vector3) -> void:
	if _drip_quiet > 0.0 or _drip_sounds.is_empty():
		return
	var dist := land.distance_to(pp)
	if dist > 16.0 or _rng.randf() > 1.0 / (1.0 + dist * 0.25):
		return
	for dp in _drip_players:
		if not dp.playing:
			dp.stream = _drip_sounds[_rng.randi() % _drip_sounds.size()]
			dp.global_position = land
			dp.pitch_scale = _rng.randf_range(0.8, 1.15)
			dp.volume_db = lerpf(-12.0, -3.0, clampf(fall / 6.0, 0.0, 1.0)) + _rng.randf_range(-2.0, 2.0)
			dp.play()
			drips_heard += 1
			_drip_quiet = _rng.randf_range(0.25, 0.7)
			return


## For the tests.
func drip_report() -> Dictionary:
	var rims := [0, 0]
	var roots := 0
	var running := 0
	var lowest := 1e6
	var highest := 0.0
	for d: Dictionary in drip_points:
		if d["root"]:
			roots += 1
		else:
			rims[int(d["gap"])] += 1
		if runoff > float(d["from"]):
			running += 1
		var fall: float = (d["at"] as Vector3).y - (d["land"] as Vector3).y
		lowest = minf(lowest, fall)
		highest = maxf(highest, fall)
	return {"rim drips (big gap, small gap)": rims, "root tips": roots, "running now": running, "runoff": snappedf(runoff, 0.001), "in the air": _drops.size(),
		"splashes": _splashes.size(), "landed": drips_landed, "heard": drips_heard, "falls (m)": [snappedf(lowest, 0.01), snappedf(highest, 0.01)], "found in (ms, longest part)": _drip_ms}


## For the tests: how open to the rain the ground is at a place (1 open .. 0 under rock), by
## the ground's map; and the driest place within `r` meters of it.
func open_at(x: float, z: float) -> float:
	if _open_img == null:
		return 1.0
	var c := ((Vector2(x, z) - _open_corner) / 0.2).floor()
	if c.x < 0.0 or c.y < 0.0 or c.x >= _open_img.get_width() or c.y >= _open_img.get_height():
		return 1.0
	return _open_img.get_pixel(int(c.x), int(c.y)).r


## For the tests: is the map right? At `n` places in the air around the boulders (and, with
## `grotto`, in and around the grotto) a ray is sent down the rain's own line to the place,
## and what it says (rock on the way or not) is held against what the maps say there.
## Places within 30 cm of a shadow's edge (where the next texel says otherwise) are counted
## apart: there the two may differ by the map's grain.
func roof_check(n := 2000, grotto := false) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var g := RandomNumberGenerator.new()
	g.seed = 5
	var dir := RAIN_WIND.normalized()
	var same := 0
	var differ := 0
	var differ_edge := 0
	var sheltered := 0
	var first_bad: Array = []
	for i in n:
		var p: Vector3
		if grotto:
			var c: Array = _ls.cave_path[g.randi() % _ls.cave_path.size()]
			p = (c[0] as Vector3) + Vector3(g.randf_range(-6.0, 6.0), g.randf_range(0.3, 9.0), g.randf_range(-6.0, 6.0))
		else:
			var box: AABB = _rocks[g.randi() % _rocks.size()]
			p = Vector3(g.randf_range(box.position.x - 3.0, box.end.x + 3.0), 0.0, g.randf_range(box.position.z - 3.0, box.end.z + 3.0))
			p.y = float(_ls.ground(p.x, p.z)) + g.randf_range(0.3, 4.0)
		var k := g.randi() % 3
		var lean: Vector2 = dir * (ROOF_SLANTS[k] as float)
		var up := maxf(_isle_top, _roof_top) - p.y
		var from := p + Vector3(-lean.x * up, up, -lean.y * up)
		var truth := false
		for tries in 6:
			q.from = from
			q.to = p
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			# (in the grotto's own map everything counts, the ground and trunks too)
			if _kind(hit) == 2 or grotto:
				truth = true
				break
			from = (hit["position"] as Vector3) + (p - from).normalized() * 0.05
		var said := _first_roof(p, k) > p.y
		if truth:
			sheltered += 1
		if said == truth:
			same += 1
		else:
			var edge := false
			for off: Vector3 in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3), Vector3(0, 0.3, 0), Vector3(0, -0.3, 0)]:
				if (_first_roof(p + off, k) > p.y + off.y) == truth:
					edge = true
			if edge:
				differ_edge += 1
			else:
				differ += 1
				if first_bad.size() < 5:
					first_bad.append([p, k, "ray says rock over it" if truth else "ray says open", _first_roof(p, k)])
	return {"places": n, "with rock over them": sheltered, "map and ray agree": same, "differ at an edge": differ_edge, "differ elsewhere": differ, "examples": first_bad}


## For the tests: each boulder's place, size, how much ground it keeps dry beside itself
## (m2 with less than half the rain, outside its own foot) and what the ground is there.
func lee_report(from := 0, to := 1000) -> Array:
	var out: Array = []
	var spots: Array = _ls.boulder_spots
	for n in range(from, mini(to, spots.size())):
		var at: Vector3 = spots[n][0]
		var size: float = spots[n][1]
		var dry := 0.0
		var x := at.x - size
		while x <= at.x + size * 2.0:
			var z := at.z - size
			while z <= at.z + size * 2.0:
				if open_at(x, z) < 0.5 and Vector2(x - at.x, z - at.z).length() > size * 0.5:
					dry += 0.04
				z += 0.2
			x += 0.2
		out.append([n, Vector3(snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)), snappedf(size, 0.1), snappedf(dry, 0.1), snappedf((_ls.cover(at.x, at.z) as Color).r, 0.01)])
	return out


## For the tests: the rest of the map at once; and pictures of both maps (`dir`: a folder).
func finish_roofs(dir := "") -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var before := _roof_i
	_bake_roofs(0)
	while _drip_stage < 3:
		_find_drips(_drip_stage)
		_drip_stage += 1
		if _drip_stage == 3 and _roof_w > 0:
			_open_task = WorkerThreadPool.add_task(_open_ground)
	_apply_open()
	var t1 := Time.get_ticks_msec()
	var rays_before := isle_rays
	if _isle_stage == 0:
		_isle_mark(0)
	if _isle_stage == 1:
		_isle_rays(0)
	if _isle_stage == 2:
		_apply_isle()
	var isle := {"boulders": _rocks.size(), "map": [_isle_w, _isle_h], "rect": _isle_rect, "rays in all": isle_rays, "rays now": isle_rays - rays_before, "ms now": Time.get_ticks_msec() - t1,
		"ground map ms": _isle_ms, "ground map": _isle_out, "ground map size": _open_img.get_size() if _open_img else Vector2i.ZERO}
	var out := {"map": [_roof_w, _roof_h], "rays now": (_roof_w * _roof_h - before) * 3, "ms": Time.get_ticks_msec() - t0, "rect": _roof_rect,
		"level": _roof_y0, "from": _roof_top, "to": _roof_bottom, "ground map ms": _open_ms, "gaps": gaps, "island": isle}
	if dir != "" and _open_img:
		_open_img.save_png(dir.path_join("rain_open_ground.png"))
		var pic := Image.create(_roof_w, _roof_h, false, Image.FORMAT_RGB8)
		for j in _roof_h:
			for i in _roof_w:
				var n := (j * _roof_w + i) * 4
				pic.set_pixel(i, j, Color(inverse_lerp(_roof_bottom, _roof_top - 15.0, _roof_data[n]), inverse_lerp(_roof_bottom, _roof_top - 15.0, _roof_data[n + 1]),
					inverse_lerp(_roof_bottom, _roof_top - 15.0, _roof_data[n + 2])))
		pic.save_png(dir.path_join("rain_roof_map.png"))
	return out


func _unhandled_input(event: InputEvent) -> void:
	# (not with ⌘ held: see daycycle.gd)
	if event is InputEventKey and event.meta_pressed:
		return
	if event.is_action_pressed("rain_shower"):
		if t < 0.0:
			call_shower()
			if _daycycle:
				_daycycle.show_message("A shower is coming")
		elif t < GATHER + rain_len - EASE:
			pass_over()
			if _daycycle:
				_daycycle.show_message("The shower passes")


## A shower begins now (the sky closes first). `length`: how long it is to rain (seconds).
func call_shower(length := -1.0) -> void:
	if t >= 0.0:
		return
	t = 0.0
	rain_len = length if length > 0.0 else _rng.randf_range(900.0, 1080.0)
	_swell = _rng.randf() * 100.0
	showers += 1


## The rain eases off now: on to its last minutes.
func pass_over() -> void:
	if t >= 0.0:
		t = maxf(t, GATHER + rain_len - EASE)


## For the tests: straight to a moment of the shower (seconds from its beginning), with the
## ground as wet as it would be by then.
func jump(to: float) -> void:
	if t < 0.0:
		call_shower()
	t = to
	wet = clampf((to - GATHER) / 120.0, 0.0, 1.0)
	_levels()
	rain = _want_rain
	overcast = _want_overcast
	runoff = clampf(rain * 1.7, 0.0, 1.0)


var _want_rain := 0.0
var _want_overcast := 0.0
var _want_bow := 0.0


## Where the shower stands at `t`: how hard it rains, how closed the sky is, the rainbow.
func _levels() -> void:
	if t < 0.0:
		_want_rain = 0.0
		_want_overcast = 0.0
		_want_bow = 0.0
		return
	var end := GATHER + rain_len
	# the first drops come as the sky closes; then it swells and eases in slow waves; the
	# last minutes are light rain, and a few drops still fall when the sun is out again
	var r := smoothstep(GATHER - 30.0, GATHER + 70.0, t)
	r *= 0.78 + 0.22 * sin(t * 0.031 + _swell) * sin(t * 0.0113 + _swell * 0.7)
	r *= 1.0 - 0.78 * smoothstep(end - EASE, end - 30.0, t)
	r *= 1.0 - smoothstep(end, end + 70.0, t)
	_want_rain = clampf(r, 0.0, 1.0)
	var o := smoothstep(0.0, GATHER, t)
	o *= 1.0 - 0.76 * smoothstep(end - EASE, end - 60.0, t)
	o *= 1.0 - smoothstep(end, end + 200.0, t)
	_want_overcast = o
	# the rainbow: when the sun is out again and it still rains, here or on the far side, by day
	var b := smoothstep(end - 200.0, end - 90.0, t) * (1.0 - smoothstep(end + AFTER - 80.0, end + AFTER, t))
	var up := 0.0
	if _daycycle:
		var elev: float = _daycycle.sun_elev
		# (only if the sun is low enough for the bow to stand above the horizon: its top is
		# 42 degrees less the sun's height up)
		up = smoothstep(41.0, 35.0, elev) * smoothstep(0.5, 2.0, elev)
	var night: float = _daycycle.night if _daycycle else 0.0
	# (and it needs the sun: not while the cloud is still closed)
	_want_bow = b * up * (1.0 - night) * (1.0 - smoothstep(0.35, 0.6, overcast))


func _process(delta: float) -> void:
	if _player == null:
		return
	var dt := minf(delta, 0.1) * time_scale
	if t >= 0.0:
		t += dt
		if t > GATHER + rain_len + AFTER:
			t = -1.0
			next_in = 5400.0 + _wait()
	else:
		next_in -= dt
		if next_in <= 0.0:
			call_shower()
	_levels()
	rain = lerpf(rain, _want_rain, 1.0 - exp(-dt * 0.5))
	overcast = lerpf(overcast, _want_overcast, 1.0 - exp(-dt * 0.5))
	bow = lerpf(bow, _want_bow, 1.0 - exp(-dt * 0.5))
	if rain < 0.0005 and _want_rain == 0.0:
		rain = 0.0
	if overcast < 0.0005 and _want_overcast == 0.0:
		overcast = 0.0
	var night: float = _daycycle.night if _daycycle else 0.0
	# the ground: wet within a minute of real rain, dry again in some ten minutes of sun
	# (slower at night)
	wet += (rain * (1.0 - wet) / 45.0 - (1.0 - minf(rain * 8.0, 1.0)) * wet / lerpf(260.0, 520.0, night)) * dt
	wet = clampf(wet, 0.0, 1.0)
	if wet < 0.002 and rain == 0.0:
		wet = 0.0
	# the frogs: from well into the rain until some eight minutes after it
	var frogs_on := t >= GATHER + 200.0 or (t < 0.0 and wet > 0.25)
	frogs = move_toward(frogs, 1.0 if frogs_on else 0.0, dt / (40.0 if frogs_on else 150.0))
	RenderingServer.global_shader_parameter_set("rain", rain)
	RenderingServer.global_shader_parameter_set("rain_wet", wet)
	if _daycycle:
		_daycycle.overcast = overcast
		_daycycle.haze = rain
	# where the walker stands: under the forest's roof, in the grotto, in the sea
	var pp := _player.global_position
	var forest: float = (_ls.cover(pp.x, pp.z) as Color).r if _ls.has_method("cover") else 0.0
	var in_cave: bool = _ls.cave_inside(pp) if _ls.has_method("cave_inside") else false
	_in_cave = move_toward(_in_cave, 1.0 if in_cave else 0.0, delta * 1.5)
	_shelter = lerpf(_shelter, clampf(forest, 0.0, 1.0), 1.0 - exp(-delta * 1.5))
	var under: bool = _player.get("underwater") == true
	var light := lerpf(1.0, 0.07, night)
	# falling rain: thinner under the trees, none in the grotto or with the face under water
	# (in the grotto it is the same rain: the shader leaves out every streak that has rock
	# over it, so that it falls through the gaps in the roof and outside the mouths, and
	# nowhere else; until that map is made, none in there at all)
	var fall := rain * (1.0 - 0.5 * _shelter) * (0.0 if under else 1.0)
	if not roofs_ready:
		fall *= 1.0 - _in_cave
	var gust: float = _ambience.gust if _ambience else 1.0
	var wind := RAIN_WIND * (0.5 + 0.8 * gust)
	# (the wind carries the rain along: summed up here, so that a gust changes the streaks'
	# slant and not, at one blow, the place of every drop)
	_drift += wind * dt
	_drift = Vector2(fposmod(_drift.x, 22.0), fposmod(_drift.y, 22.0))
	_streaks.visible = fall > 0.004
	if _streaks.visible:
		_streak_mat.set_shader_parameter("amount", pow(fall, 0.8))
		_streak_mat.set_shader_parameter("wind", wind)
		_streak_mat.set_shader_parameter("drift", _drift)
		_streak_mat.set_shader_parameter("light", lerpf(1.0, 0.12, night) * lerpf(1.0, 0.8, overcast))
	# what runs off the rock into the grotto
	_update_drips(dt, lerpf(1.0, 0.12, night) * lerpf(1.0, 0.8, overcast), pp)
	# the gray of the rain over the distance, and the bow
	_veil.visible = (rain > 0.004 or bow > 0.004) and not under
	if _veil.visible:
		_veil_mat.set_shader_parameter("haze", rain * (1.0 - _in_cave))
		_veil_mat.set_shader_parameter("bow", bow)
		_veil_mat.set_shader_parameter("light", light)
		if _daycycle:
			_veil_mat.set_shader_parameter("away_from_sun", -(_daycycle.to_sun as Vector3))
			_veil_mat.set_shader_parameter("sun_light", _daycycle.sun_light)
	# the wind: a gust front ahead of the rain, a fresh wind while it rains
	if _ambience:
		# (while it rains the wind is about twice what it is in fair weather: the low cloud
		# drives across the sky, and the trees must show it)
		_ambience.storm = 0.5 * smoothstep(60.0, GATHER, t) * (1.0 - smoothstep(GATHER + 60.0, GATHER + 260.0, t)) + 1.1 * smoothstep(0.0, 0.45, rain) if t >= 0.0 else 0.0
		_ambience.frogs_after_rain = frogs
	if _critters:
		_critters.frog_chorus = frogs
		_critters.raining = rain > 0.12
	_life.raining = rain > 0.12
	# the sounds: rain on leaves and ground everywhere, on the sea near the shore, and the
	# dripping from the trees when it has stopped (the grotto muffles them: the Ambient bus)
	var loud := pow(rain, 0.6)
	var near_sea := 1.0 - smoothstep(1.5, 14.0, float(_ls.ground(pp.x, pp.z)))
	_level(_snd_rain, lerpf(-40.0, 4.0, loud) + 2.0 * _shelter, rain > 0.003)
	_level(_snd_sea, lerpf(-42.0, 1.0, loud * near_sea), rain * near_sea > 0.003)
	var drip := clampf(wet * 1.3, 0.0, 1.0) * (1.0 - minf(rain * 3.0, 1.0)) * (0.35 + 0.65 * _shelter)
	_level(_snd_drips, lerpf(-44.0, -15.0, drip), drip > 0.02)


func _level(p: AudioStreamPlayer, db: float, on: bool) -> void:
	if p == null:
		return
	if on:
		p.volume_db = db
		if not p.playing:
			p.play(_rng.randf() * 20.0)
	elif p.playing:
		p.stop()


## For the tests.
func report() -> Dictionary:
	return {"t": snappedf(t, 0.1), "rain for (s)": snappedf(rain_len, 1.0), "rain": snappedf(rain, 0.001), "overcast": snappedf(overcast, 0.001),
		"wet": snappedf(wet, 0.001), "bow": snappedf(bow, 0.001), "frogs": snappedf(frogs, 0.01), "showers": showers,
		"next by itself in (min)": snappedf(next_in / 60.0, 0.1), "falling": _streaks.visible, "veil": _veil.visible, "roof map": roofs_ready, "island's roof map": isle_ready,
		"sounds": [_snd_rain != null and _snd_rain.playing, _snd_sea != null and _snd_sea.playing, _snd_drips != null and _snd_drips.playing]}


## For the tests: a whole shower in steps of a quarter of a second, with nothing drawn; says
## how long each part took and what the ground and the frogs did afterward.
func soak() -> Dictionary:
	t = -1.0
	rain = 0.0
	overcast = 0.0
	wet = 0.0
	frogs = 0.0
	call_shower()
	var first_drop := -1.0
	var last_drop := -1.0
	var closed := -1.0
	var hardest := 0.0
	var bow_from := -1.0
	var bow_to := -1.0
	var clock := 0.0
	var dry_at := -1.0
	var frogs_until := -1.0
	var wettest := 0.0
	while clock < 4000.0:
		_process(0.1)
		clock += 0.1 * time_scale
		if rain > 0.02 and first_drop < 0.0:
			first_drop = clock
		if rain > 0.02:
			last_drop = clock
		if overcast > 0.9 and closed < 0.0:
			closed = clock
		hardest = maxf(hardest, rain)
		wettest = maxf(wettest, wet)
		if bow > 0.3 and bow_from < 0.0:
			bow_from = clock
		if bow > 0.3:
			bow_to = clock
		if t < 0.0 and wet < 0.05 and dry_at < 0.0:
			dry_at = clock
		if frogs > 0.3:
			frogs_until = clock
	return {"rain set for (s)": rain_len, "sky closed at": closed, "rain from": first_drop, "rain until": last_drop, "minutes of rain": (last_drop - first_drop) / 60.0,
		"hardest": hardest, "rainbow from": bow_from, "rainbow until": bow_to, "ground wettest": wettest, "ground dry at": dry_at, "frogs until": frogs_until,
		"over (t < 0)": t < 0.0, "next by itself in (min)": next_in / 60.0}
