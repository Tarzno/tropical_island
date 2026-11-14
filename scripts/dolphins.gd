extends Node3D
## Spinner dolphins beyond the reef: now and then a pod of seven passes along the coast in
## the deep water just outside the reef's edge: ten meters and more beyond where the floor
## is ten meters down (a swimmer is stopped at eight), so that somebody at the reef's edge
## has them at fifteen to thirty meters and somebody on the start beach at about a hundred.
## (Until 2026-11-12 they passed twenty meters further out and half as often, and came
## whether or not anybody could see them: they were hardly ever seen.)
## They travel at an easy pace, each coming up to breathe every few seconds
## (the back and the tall fin roll over the surface), and every so often one leaps clear and
## spins about its own length before it falls back with a splash: the spinner's leap.
## By day only. Seen from the beach, a snorkeler's place in the lagoon, or the summit.
## (The node is created by island_life.gd.) For the tests: summon(), report().

const LEN := 2.6           # (a spinner is 2 m: shown a little over life, as the other far-off animals are)
const POD := 7
const OUTSIDE := 10.0      # their line: so far outside the place where the floor is 10 m down (it was 28)

var passing := false
var passes := 0
var leaps := 0
var _ls: Node
var _player: Node3D
var _sealife: Node
var _daycycle: Node
var _fauna: Node
var _rng := RandomNumberGenerator.new()
var _pod: Array = []
var _path: PackedVector3Array = PackedVector3Array()     # along the coast, outside the reef (y unused)
var _len := 0.0
var _s := 0.0
var _dir := 1.0
var _next := 0.0
var _time := 0.0


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_sealife = get_node_or_null("../../SeaLife")
	_daycycle = get_node_or_null("../../DayCycle")
	_fauna = get_node_or_null("../../Fauna")
	_rng.randomize()
	_next = _rng.randf_range(180.0, 360.0)
	var mesh: ArrayMesh = load("res://scripts/sea_models.gd").dolphin()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea_creature.gdshader")
	mat.set_shader_parameter("species", 7)
	for i in POD:
		var mi := MeshInstance3D.new()
		mi.name = "Dolphin%d" % i
		mi.mesh = mesh
		mi.material_override = mat
		mi.visible = false
		mi.position = Vector3(0, -80, 0)
		add_child(mi)
		# (its place in the pod: none within a dolphin's length of another along the way
		# unless a good meter and a half to the side of it. Two could be given the same
		# place, and swam in each other: found by tools/coral_audit.gd, 2026-11-12)
		var along := -i * _rng.randf_range(3.0, 5.5)
		var side := _rng.randf_range(-6.0, 6.0)
		for k in 40:
			var free := true
			for o: Dictionary in _pod:
				if absf(float(o["along"]) - along) < 2.8 and absf(float(o["side"]) - side) < 1.6:
					free = false
			if free:
				break
			along = -i * _rng.randf_range(3.0, 5.5)
			side = _rng.randf_range(-6.0, 6.0)
		_pod.append({"node": mi, "along": along, "side": side, "size": _rng.randf_range(0.85, 1.05),
			"t": _rng.randf_range(0.0, 6.0), "roll_len": 1.5, "leap": false, "spin": 0.0, "wet": true})
	# the way: outside the reef on the sea side (+x), from the island's one end to the other
	var z := -230.0
	while z <= 250.0:
		var x := 60.0
		while x < 300.0 and float(_ls.ground(x, z)) > -10.0:
			x += 4.0
		_path.append(Vector3(x + OUTSIDE, 0, z))
		z += 16.0
	# (smooth it: the reef's edge is ragged)
	for k in 4:
		for i in range(1, _path.size() - 1):
			_path[i] = Vector3((_path[i - 1].x + _path[i].x * 2.0 + _path[i + 1].x) * 0.25, 0, _path[i].z)
	for i in _path.size() - 1:
		_len += _path[i].distance_to(_path[i + 1])


func _at(s: float) -> Array:
	# (beyond either end the way goes straight on: held to its ends, every dolphin that
	# had come to the end stayed on that one spot, in the others, until the last was there)
	if s < 0.0:
		var d0 := (_path[1] - _path[0]).normalized()
		return [_path[0] + d0 * s, d0]
	if s > _len - 0.01:
		var n := _path.size() - 1
		var d1 := (_path[n] - _path[n - 1]).normalized()
		return [_path[n] + d1 * (s - _len), d1]
	var left := s
	for i in _path.size() - 1:
		var seg := _path[i].distance_to(_path[i + 1])
		if left <= seg:
			var d := (_path[i + 1] - _path[i]).normalized()
			return [_path[i] + d * left, d]
		left -= seg
	return [_path[_path.size() - 1], Vector3(0, 0, 1)]


func summon() -> bool:
	if passing or _path.size() < 3:
		return false
	passing = true
	passes += 1
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	# (they come into view a little way up the coast from the walker, not from the far end)
	var pz := _player.global_position.z if _player else 0.0
	var start_z := clampf(pz - _dir * 150.0, -220.0, 240.0)
	_s = clampf((start_z + 230.0) / 480.0, 0.0, 1.0) * _len
	for d: Dictionary in _pod:
		(d["node"] as Node3D).visible = true
		d["t"] = _rng.randf_range(0.0, 6.0)
		d["leap"] = false
	return true


## Is the walker where the pod's line can be seen from: on the sea side of the island (the
## start beach, the lagoon, the reef), or high on the hill?
func _in_view() -> bool:
	if _player == null:
		return true
	var p := _player.global_position
	return p.x > -45.0 or p.y > 26.0


func _surface(x: float, z: float) -> float:
	return float(_sealife.surface(x, z)) if _sealife and _sealife.has_method("surface") else float(_ls.sea)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_time += delta
	if not passing:
		_next -= delta
		if _next <= 0.0:
			var night: float = _daycycle.night if _daycycle else 0.0
			# (they come when somebody can see them: the walker on the island's sea side, in
			# the lagoon, or high up; otherwise they wait a minute and look again)
			_next = _rng.randf_range(480.0, 840.0) if night < 0.3 and _in_view() and summon() else 60.0
		return
	_s += _dir * 2.9 * delta
	var gone := true
	for d: Dictionary in _pod:
		var s := _s + _dir * float(d["along"])
		if s > 0.0 and s < _len:
			gone = false
		var fr := _at(s)
		var fwd: Vector3 = (fr[1] as Vector3) * _dir
		var right := Vector3(-fwd.z, 0, fwd.x)
		var p: Vector3 = (fr[0] as Vector3) + right * float(d["side"])
		var top := _surface(p.x, p.z)
		var size: float = d["size"]
		# under water between breaths; a roll over the surface to breathe; now and then a leap
		d["t"] = float(d["t"]) - delta
		var t: float = d["t"]
		var y := top - 1.1
		var pitch := 0.0
		var spin := 0.0
		var rl: float = d["roll_len"]
		if t <= 0.0:
			var u := -t / rl            # 0 .. 1 through the roll or the leap
			if u >= 1.0:
				if d["leap"] and _fauna and _fauna.has_method("_splash"):
					_fauna._splash(Vector3(p.x, top + 0.1, p.z))
				elif _fauna and _fauna.has_method("_splash") and _rng.randf() < 0.3:
					_fauna._splash(Vector3(p.x, top + 0.05, p.z))       # (the blow, and the water off its back)
				d["leap"] = _rng.randf() < 0.12
				d["roll_len"] = 1.3 if d["leap"] else _rng.randf_range(1.4, 1.9)
				d["t"] = _rng.randf_range(2.5, 6.0) if not d["leap"] else 0.6
				if d["leap"]:
					leaps += 1
			else:
				var arc := sin(u * PI)
				if d["leap"]:
					y = top - 1.1 + arc * (1.1 + 2.3 * size)
					pitch = cos(u * PI) * 0.9
					spin = u * TAU * 3.0
				else:
					y = top - 1.1 + arc * (1.1 + 0.3 * size)
					pitch = cos(u * PI) * 0.45
		var b := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, spin)
		(d["node"] as Node3D).global_transform = Transform3D(b.scaled(Vector3.ONE * (LEN / 3.6 * size)), Vector3(p.x, y, p.z))
	if gone:
		passing = false
		for d: Dictionary in _pod:
			(d["node"] as Node3D).visible = false


## (for the tests) One of them leaps now.
func leap_now(i := 3) -> void:
	var d: Dictionary = _pod[i]
	d["leap"] = true
	d["roll_len"] = 1.3
	d["t"] = 0.0
	leaps += 1


func report() -> Dictionary:
	var at := (_pod[0]["node"] as Node3D).global_position if passing else Vector3.ZERO
	var pp := _player.global_position if _player else Vector3.ZERO
	return {"passing": passing, "passes": passes, "leaps": leaps, "next by itself in (min)": snappedf(_next / 60.0, 0.1), "the first one at": at,
		"from the walker (m)": snappedf(Vector2(at.x - pp.x, at.z - pp.z).length(), 1.0) if passing else -1.0,
		"the way lies at x": [snappedf(_path[2].x, 1.0), snappedf(_path[_path.size() / 2].x, 1.0), snappedf(_path[_path.size() - 3].x, 1.0)]}
