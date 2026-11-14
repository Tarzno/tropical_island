extends Node3D
## Bubbles under water, where a snorkeler meets them:
##  * a swirl of them around the mask when the face goes under;
##  * a handful dragged down by each stroke of the arms while swimming with the face in the
##    water, which rise again at once;
##  * and from the seagrass in bright sun strings of tiny bubbles, one after another from the
##    same blade: the oxygen the grass makes ("pearling"). Not at dusk, not at night.
## (A snorkeler breathes through the snorkel: there is no stream of breath to draw.)
## Every bubble rises (the bigger the faster), wobbles, is rocked by the swell, and is gone
## when it reaches the surface. One MultiMesh of discs that face the eye, never drawn smaller
## than a pixel or two. The node is created by island_life.gd.

const MAX := 420
const SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// A bubble: a bright rim and a glint, clear in between. The instance's size is its radius.
uniform float light = 1.0;
varying float v_small;
void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float least = length(center) * 0.0016;
	v_small = step(size, least * 1.5);
	POSITION = PROJECTION_MATRIX * vec4(center + vec3(VERTEX.xy, 0.0) * max(size, least), 1.0);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float rim = smoothstep(0.56, 0.78, r) * (1.0 - smoothstep(0.9, 1.0, r));
	float glint = 1.0 - smoothstep(0.12, 0.26, length(q - vec2(-0.36, -0.38)));
	// (a bubble only a pixel or two across is a bright dot)
	float a = max(max(rim, glint), v_small * (1.0 - smoothstep(0.8, 1.0, r)));
	if (a < 0.5) {
		discard;
	}
	ALBEDO = mix(vec3(0.6, 0.86, 0.9), vec3(1.0), max(glint, v_small * 0.5)) * light;
}"""

var _player: Node3D
var _seabed: Node
var _sealife: Node
var _daycycle: Node
var _ls: Node
var _rng := RandomNumberGenerator.new()
var _mm: MultiMesh
var _mat: ShaderMaterial
var _time := 0.0
# the bubbles (parallel arrays; a dead one is replaced by the last)
var _pos := PackedVector3Array()
var _push := PackedVector3Array()     # what carried it down or along at first: dies away
var _size := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _was_under := false
var _was_diving := false
var _stroke := 0.0
var _stroke_side := 1.0
var _sources: Array = []              # the blades that pearl: pos, left (in this string), t
# for the tests
var made := {"face": 0, "strokes": 0, "pearls": 0}
var reached_surface := 0


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed
	_sealife = get_node_or_null("../../SeaLife")
	_daycycle = get_node_or_null("../../DayCycle")
	_rng.randomize()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = quad
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-300, -40, -300), Vector3(600, 80, 600))
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	var mi := MultiMeshInstance3D.new()
	mi.name = "Bubbles"
	mi.multimesh = _mm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func count() -> int:
	return _pos.size()


func _wave(x: float, z: float) -> float:
	return float(_sealife.surface(x, z)) if _sealife else 0.0


## A new bubble at `at`, of radius `size`, carried along by `push` for its first moments.
func _emit(at: Vector3, size: float, push := Vector3.ZERO) -> void:
	if _pos.size() >= MAX:
		return
	_pos.append(at)
	_push.append(push)
	_size.append(size)
	_phase.append(_rng.randf() * TAU)


func _process(delta: float) -> void:
	if _player == null:
		return
	delta = minf(delta, 0.1)
	_time += delta
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else _player.global_position
	var under: bool = _player.get("underwater") == true
	var night: float = _daycycle.night if _daycycle else 0.0
	_mat.set_shader_parameter("light", lerpf(1.0, 0.15, night))
	if under and not _was_under:
		_face_under(eye, cam)
	_was_under = under
	# a dive begins: the air in the snorkel comes out of its top in a string
	var diving: bool = _player.get("diving") == true
	if diving and not _was_diving and cam:
		var back := cam.global_transform.basis.z
		for i in _rng.randi_range(10, 16):
			_emit(eye + Vector3(0, 0.22, 0) + back * 0.12 + cam.global_transform.basis.x * 0.1 + Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(0.0, 0.25), _rng.randf_range(-0.03, 0.03)),
				_rng.randf_range(0.003, 0.008), Vector3(0, -_rng.randf_range(0.2, 0.9), 0))
			made["snorkel"] = int(made.get("snorkel", 0)) + 1
	_was_diving = diving
	if under:
		_strokes(delta, eye)
	_pearls(delta, eye)
	_rise(delta)


## The face goes into the water: the air caught around the mask comes off in a swirl.
func _face_under(eye: Vector3, cam: Camera3D) -> void:
	var fwd := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	var right := cam.global_transform.basis.x if cam else Vector3.RIGHT
	var top := _wave(eye.x, eye.z)
	for i in _rng.randi_range(16, 24):
		var at := eye + fwd * _rng.randf_range(0.25, 0.7) + right * _rng.randf_range(-0.4, 0.4)
		at.y = minf(eye.y + _rng.randf_range(-0.25, 0.12), top - 0.03)
		_emit(at, _rng.randf_range(0.002, 0.0065), Vector3(_rng.randf_range(-0.15, 0.15), -_rng.randf_range(0.15, 0.6), _rng.randf_range(-0.15, 0.15)) + fwd * 0.2)
		made["face"] += 1


## Swimming with the face in the water: every stroke a hand goes in ahead, to one side then
## the other, and takes a little air down with it.
func _strokes(delta: float, eye: Vector3) -> void:
	if _player.get("_swimming") != true or _player.get("diving") == true:
		return        # (a diver's hands take no air down: they are far below it)
	var vel: Vector3 = _player.get("velocity")
	var speed := Vector2(vel.x, vel.z).length()
	if speed < 0.3:
		return
	_stroke += delta * (0.55 + 0.25 * speed)
	if _stroke < 1.0:
		return
	_stroke -= 1.0
	_stroke_side = -_stroke_side
	var fwd := Vector3(vel.x, 0, vel.z).normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var hand := eye + fwd * 0.6 + right * (0.27 * _stroke_side)
	hand.y = _wave(hand.x, hand.z) - 0.04
	for i in _rng.randi_range(6, 11):
		var at := hand + Vector3(_rng.randf_range(-0.08, 0.08), -_rng.randf_range(0.0, 0.12), _rng.randf_range(-0.08, 0.08))
		_emit(at, _rng.randf_range(0.002, 0.006), fwd * _rng.randf_range(0.1, 0.5) + Vector3(0, -_rng.randf_range(0.5, 1.1), 0))
		made["strokes"] += 1


## The seagrass in the sun: a few blades near the swimmer give off strings of tiny bubbles.
func _pearls(delta: float, eye: Vector3) -> void:
	var sun: float = _daycycle.sea_sun if _daycycle else 1.0
	var in_sea: bool = float(_ls.ground(eye.x, eye.z)) - float(_ls.sea) < -1.0
	if sun < 0.55 or not in_sea or _seabed == null or not _seabed.ready_for_meadows():
		_sources.clear()
		return
	# blades left far behind are forgotten; new ones are found where the grass stands thick
	for i in range(_sources.size() - 1, -1, -1):
		var sp: Vector3 = _sources[i]["pos"]
		if Vector2(sp.x - eye.x, sp.z - eye.z).length() > 17.0:
			_sources.remove_at(i)
	if _sources.size() < 12:
		var p := Vector2(eye.x, eye.z) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2.5, 13.0)
		if float(_seabed.meadow(p)) > 0.55:
			_sources.append({"pos": Vector3(p.x, float(_ls.ground(p.x, p.y)) + _rng.randf_range(0.12, 0.3), p.y), "left": 0, "t": _rng.randf_range(0.0, 3.0)})
	for s: Dictionary in _sources:
		s["t"] -= delta
		if s["t"] > 0.0:
			continue
		if int(s["left"]) <= 0:
			# a string of them, then a pause
			s["left"] = _rng.randi_range(6, 16)
			s["t"] = _rng.randf_range(1.5, 6.0) * (1.7 - sun * 0.7)
			continue
		s["left"] = int(s["left"]) - 1
		s["t"] = _rng.randf_range(0.14, 0.26)
		_emit((s["pos"] as Vector3) + Vector3(_rng.randf_range(-0.01, 0.01), 0, _rng.randf_range(-0.01, 0.01)), _rng.randf_range(0.0018, 0.0034))
		made["pearls"] += 1


func _rise(delta: float) -> void:
	var n := _pos.size()
	var i := 0
	var drag := exp(-3.2 * delta)
	while i < n:
		var p := _pos[i]
		var size := _size[i]
		var ph := _phase[i]
		# up, the bigger the faster; a wobble; to and fro with the swell
		var v := Vector3(0, 0.15 + size * 27.0, 0) + _push[i]
		var wob := 0.012 + size * 4.0
		v.x += sin(_time * 7.0 + ph) * wob + sin(_time * 1.25 + p.x * 0.55 + p.z * 0.31) * 0.05
		v.z += cos(_time * 5.3 + ph * 1.7) * wob
		p += v * delta
		_push[i] = _push[i] * drag
		if p.y > float(_ls.sea) - 0.6 and p.y >= _wave(p.x, p.z) - size:
			# at the surface: gone
			reached_surface += 1
			n -= 1
			_pos[i] = _pos[n]
			_push[i] = _push[n]
			_size[i] = _size[n]
			_phase[i] = _phase[n]
			continue
		_pos[i] = p
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), p))
		i += 1
	if n != _pos.size():
		_pos.resize(n)
		_push.resize(n)
		_size.resize(n)
		_phase.resize(n)
	_mm.visible_instance_count = n


## For the tests.
func report() -> Dictionary:
	var lowest := 0.0
	var highest := -99.0
	for p in _pos:
		lowest = minf(lowest, p.y)
		highest = maxf(highest, p.y)
	return {"bubbles now": _pos.size(), "made": made, "reached the surface": reached_surface, "pearling blades": _sources.size(),
		"lowest and highest now": [lowest, highest]}
