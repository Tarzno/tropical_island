extends Node3D
## Soundscape for the beach: shore waves that follow the listener along the
## waterline, wave-wash one-shots synchronized with the visible swash, distant surf,
## gusty wind (which also drives foliage sway), rustling palms, jungle birds and
## footsteps.

const A := "res://assets/audio/"
const Heights := preload("res://scripts/heights.gd")

@export var player_path: NodePath = ^"../Player"
@export var palms_path: NodePath = ^"../Palms"

var _player: Node3D
var _t := 0.0
var _swash_period := 9.0
var _last_phase_idx := {}
var _shore: Array[AudioStreamPlayer3D] = []
var _wash_players: Array[AudioStreamPlayer3D] = []
var _wash_streams: Array[AudioStream] = []
var _surf: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _wind_b: AudioStreamPlayer
var _palms: Array[AudioStreamPlayer3D] = []
var _jungle: Array[AudioStreamPlayer3D] = []
var _night_players: Array[AudioStreamPlayer3D] = []
var _steps_sand: Array[AudioStream] = []
var _steps_water: Array[AudioStream] = []
var _step_players: Array[AudioStreamPlayer] = []
var _step_idx := 0
var _rng := RandomNumberGenerator.new()
var gust := 1.0


## a rain shower (scripts/weather.gd sets these): more wind; the frogs calling after it
var storm := 0.0
var frogs_after_rain := 0.0
var _frog_players: Array = []


func _ready() -> void:
	_rng.randomize()
	_player = get_node_or_null(player_path)
	_swash_period = ProjectSettings.get_setting("shader_globals/swash_period", {"value": 9.0})["value"]

	# master limiter so overlapping layers never clip
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)
	AudioServer.set_bus_volume_db(0, -2.0)
	# Everything heard through the air goes through "World": under water player.gd muffles
	# that bus, and only what is made in the water itself ("Hydro": the parrotfish biting
	# coral) stays clear. (A bus can only send to one made before it: World comes first.)
	if AudioServer.get_bus_index("World") < 0:
		for bus_name: String in ["World", "Hydro"]:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	# outdoor ambience goes through its own bus, so it can be muffled inside the grotto
	if AudioServer.get_bus_index("Ambient") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Ambient")
		AudioServer.set_bus_send(bi, "World")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bi, lp)

	# shore waves: three emitters strung along the waterline around the listener
	var shore_streams := [_loop("waves_close.wav"), _loop("waves_close_b.wav"), _loop("waves_close.wav")]
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.stream = shore_streams[i]
		p.unit_size = 9.0
		p.max_db = 0.0
		p.volume_db = -3.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -12.0
		p.max_distance = 160.0
		add_child(p)
		p.play(_rng.randf() * 50.0)
		_shore.append(p)

	_wash_streams = [load(A + "wave_wash_a.wav"), load(A + "wave_wash_b.wav")]
	for i in 4:
		var w := AudioStreamPlayer3D.new()
		w.unit_size = 7.0
		w.max_distance = 90.0
		w.volume_db = -2.0
		add_child(w)
		_wash_players.append(w)

	_surf = _flat("surf_distant.wav", -12.0)
	_wind = _flat("wind.wav", -14.0)
	_wind_b = _flat("wind.wav", -60.0)
	_wind_b.play(27.0)
	_wind_b.pitch_scale = 0.8

	# palm rustle at every crown
	var palms := get_node_or_null(palms_path)
	if palms:
		var rustle := _loop("palm_rustle.wav")
		for crown in palms.find_children("Crown*", "Node3D", true, false):
			var p := AudioStreamPlayer3D.new()
			p.stream = rustle
			p.unit_size = 5.0
			p.max_distance = 45.0
			p.volume_db = -6.0
			p.pitch_scale = _rng.randf_range(0.9, 1.1)
			crown.add_child(p)
			p.play(_rng.randf() * 35.0)
			_palms.append(p)

	# jungle birds along the treeline (and insects/frogs at night)
	var js := [_loop("jungle.wav"), _loop("jungle_b.wav")]
	var ns: Array = []
	for f in ["night_insects.wav", "night_frogs.wav"]:
		if ResourceLoader.exists(A + f):
			ns.append(_loop(f))
	var spots := [Vector3(-26, 3, 30), Vector3(-24, 3, 0), Vector3(-22, 3, -30), Vector3(-14, 4, -75), Vector3(-30, 3, 60)]
	for i in spots.size():
		var p := AudioStreamPlayer3D.new()
		p.stream = js[i % 2]
		p.position = spots[i]
		p.unit_size = 12.0
		p.max_distance = 110.0
		p.volume_db = -4.0
		add_child(p)
		p.play(_rng.randf() * 45.0)
		_jungle.append(p)
		if not ns.is_empty():
			var q := AudioStreamPlayer3D.new()
			q.stream = ns[i % ns.size()]
			q.position = spots[i] + Vector3(-4, 0, 6)
			q.unit_size = 12.0
			q.max_distance = 110.0
			q.volume_db = -80.0
			add_child(q)
			q.play(_rng.randf() * 45.0)
			_night_players.append(q)
			if (q.stream as AudioStream).resource_path.ends_with("night_frogs.wav"):
				_frog_players.append(q)

	for i in 10:
		var s := A + "step_sand_%d.wav" % i
		if ResourceLoader.exists(s):
			_steps_sand.append(load(s))
		var w := A + "step_water_%d.wav" % i
		if ResourceLoader.exists(w):
			_steps_water.append(load(w))
	for i in 8:
		var s := A + "step_sand_b_%d.wav" % i
		if ResourceLoader.exists(s):
			_steps_sand.append(load(s))
	for i in 4:
		var sp := AudioStreamPlayer.new()
		add_child(sp)
		_step_players.append(sp)
	if _player and _player.has_signal("footstep"):
		_player.footstep.connect(_on_footstep)
	for n in find_children("*", "AudioStreamPlayer", true, false) + find_children("*", "AudioStreamPlayer3D", true, false):
		if n is AudioStreamPlayer3D or not _step_players.has(n as AudioStreamPlayer):
			n.bus = "Ambient"
	for p in _palms:
		p.bus = "Ambient"


func _loop(file: String) -> AudioStream:
	var s := load(A + file) as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _flat(file: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _loop(file)
	p.volume_db = db
	add_child(p)
	p.play(_rng.randf() * 40.0)
	return p


# --- identical to world.gdshaderinc so sound and picture agree ---
static func _hash11(p: float) -> float:
	p = fposmod(p * 0.1031, 1.0)
	p *= p + 33.33
	p *= p + p
	return fposmod(p, 1.0)


static func _noise1(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	return lerpf(_hash11(i), _hash11(i + 1.0), f * f * (3.0 - 2.0 * f))


func _swash_phase(z: float, t: float) -> float:
	return t / _swash_period + _noise1(z * 0.035) * 0.6 + _noise1(z * 0.11 + 7.0) * 0.15


func _ground(x: float, z: float) -> float:
	# (the shared height map. Until 2026-11-12 this took the nearest pixel's height:
	# up to a quarter of a meter aside)
	return Heights.terrain(x, z, -9.0)


## The level of the sea now (the tide): the waterline the waves are heard along moves with it.
var _sealife: Node

func _tide() -> float:
	if _sealife == null:
		_sealife = get_node_or_null("../SeaLife")
	return float(_sealife.tide) if _sealife and "tide" in _sealife else 0.0


func shore_x(z: float) -> float:
	var x := -30.0
	while x < 60.0:
		if _ground(x, z) < _tide():
			return x
		x += 0.5
	return 5.0


func _process(delta: float) -> void:
	_t += delta
	RenderingServer.global_shader_parameter_set("world_time", _t)

	# wind gusts: slow layered noise, shared with the foliage shaders
	gust = 0.75 + 0.55 * _noise1(_t * 0.07) + 0.25 * _noise1(_t * 0.23 + 4.0) - 0.2 + storm
	RenderingServer.global_shader_parameter_set("wind_strength", gust)
	_wind.volume_db = lerpf(-20.0, -9.0, clampf((gust - 0.6) / 0.8, 0.0, 1.0))
	_wind_b.volume_db = lerpf(-40.0, -16.0, clampf((gust - 0.9) / 0.5, 0.0, 1.0))
	# (a shower's wind is heard too)
	_wind.volume_db += storm * 4.0
	_wind_b.volume_db += storm * 5.0
	for p in _palms:
		p.volume_db = lerpf(-14.0, -2.0, clampf((gust - 0.55) / 0.8, 0.0, 1.0))

	# day/night crossfade of the forest sounds
	var dc := get_node_or_null("../DayCycle")
	var nf: float = dc.night if dc else 0.0
	for p in _jungle:
		p.volume_db = lerpf(-4.0, -60.0, nf)
	for p in _night_players:
		p.volume_db = lerpf(-60.0, -3.0, nf)
	# after rain the frogs of the night call by day too, a little less loudly
	for p in _frog_players:
		p.volume_db = lerpf(-60.0, -3.0, maxf(nf, frogs_after_rain * 0.8))
	_wind.volume_db -= nf * 5.0

	if _player == null:
		return
	var pp := _player.global_position
	# find the nearest stretch of shoreline (any side of the island) every half second
	_shore_timer -= delta
	if _shore_timer <= 0.0:
		_shore_timer = 0.5
		_update_shore_frame(pp)
		# (where the three surf sounds belong: found with the shore, twice a second, not
		# every frame: the water's edge does not move faster than that)
		var along := Vector3(-_shore_n.z, 0, _shore_n.x)
		for i in 3:
			_shore_targets[i] = _snap_to_edge(_shore_p + along * SHORE_OFFS[i]) + _shore_n * 1.5 + Vector3(0, 0.3, 0)
	var tang := Vector3(-_shore_n.z, 0, _shore_n.x)
	for i in 3:
		var target := _shore_targets[i]
		_shore[i].global_position = _shore[i].global_position.lerp(target, 1.0 - exp(-1.5 * delta)) if _t > 0.5 else target
	var dist_shore := Vector2(pp.x - _shore_p.x, pp.z - _shore_p.z).length()
	_surf.volume_db = lerpf(-11.0, -17.0, clampf(dist_shore / 60.0, 0.0, 1.0))

	# wave wash one-shots in sync with the swash run-up at several points along that shore
	var probe: Array[float] = [-12.0, 0.0, 12.0, 24.0]
	for i in probe.size():
		var q := _shore_p + tang * probe[i]
		q = Vector3(roundf(q.x / 6.0) * 6.0, 0, roundf(q.z / 6.0) * 6.0)
		var ph := _swash_phase(q.z, _t)
		var idx := int(floorf(ph))
		var key := Vector2i(int(q.x), int(q.z))
		if _last_phase_idx.has(key) and _last_phase_idx[key] != idx:
			var w := _wash_players[i]
			if not w.playing or w.get_playback_position() > 3.0:
				w.stream = _wash_streams[_rng.randi() % _wash_streams.size()]
				w.global_position = _snap_to_edge(q) - _shore_n * 0.5 + Vector3(0, 0.2, 0)
				w.pitch_scale = _rng.randf_range(0.92, 1.08)
				var amp := 0.65 + 0.35 * _noise1(float(idx) * 1.7 + q.z * 0.02)
				w.volume_db = lerpf(-10.0, -1.0, amp)
				w.play()
		_last_phase_idx[key] = idx


var _shore_timer := 0.0
const SHORE_OFFS: Array[float] = [-28.0, 0.0, 28.0]
var _shore_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _shore_p := Vector3(5, 0, 0)
var _shore_n := Vector3(1, 0, 0)


## Nearest water's edge around the listener and the direction out to sea.
func _update_shore_frame(pp: Vector3) -> void:
	var best := 1e9
	var best_p := _shore_p
	var best_d := _shore_n
	if _ground(pp.x, pp.z) < _tide():
		# standing in the water: the shore is the nearest land, the sea the other way
		for k in 24:
			var a := TAU * k / 24.0
			var d := Vector3(cos(a), 0, sin(a))
			var r := 1.0
			while r < 120.0:
				if _ground(pp.x + d.x * r, pp.z + d.z * r) > _tide():
					if r < best:
						best = r; best_p = pp + d * r; best_d = -d
					break
				r += 1.5
	else:
		for k in 24:
			var a := TAU * k / 24.0
			var d := Vector3(cos(a), 0, sin(a))
			var r := 1.0
			while r < 160.0:
				if _ground(pp.x + d.x * r, pp.z + d.z * r) < _tide():
					if r < best:
						best = r; best_p = pp + d * r; best_d = d
					break
				r += 2.0
	if best < 1e8:
		_shore_p = Vector3(best_p.x, 0, best_p.z)
		_shore_n = best_d.normalized()


## Moves a point along the shore normal until it sits on the water's edge.
func _snap_to_edge(q: Vector3) -> Vector3:
	var p := q - _shore_n * 40.0
	for i in 60:
		if _ground(p.x, p.z) < _tide():
			return p
		p += _shore_n * 1.5
	return q


func _on_footstep(surface: String, strength: float) -> void:
	var sp := _step_players[_step_idx]
	_step_idx = (_step_idx + 1) % _step_players.size()
	var list := _steps_water if surface == "water" else _steps_sand
	if list.is_empty():
		return
	sp.stream = list[_rng.randi() % list.size()]
	sp.pitch_scale = _rng.randf_range(0.88, 1.12) * (0.95 if surface == "wet" else 1.0)
	sp.volume_db = lerpf(-20.0, -10.0, strength) + (-2.0 if surface == "wet" else 0.0)
	sp.play()
	if surface == "wet" and not _steps_water.is_empty():
		var sp2 := _step_players[_step_idx]
		_step_idx = (_step_idx + 1) % _step_players.size()
		sp2.stream = _steps_water[_rng.randi() % _steps_water.size()]
		sp2.volume_db = lerpf(-30.0, -22.0, strength)
		sp2.pitch_scale = _rng.randf_range(1.0, 1.2)
		sp2.play()
