extends Node3D
## Life in the sea beyond the fish schools: young blacktip reef sharks that live in the shallows
## all around the island (a meter long, the black tip of the dorsal fin cutting the surface), and
## rare visitors. Every few minutes a tiger shark cruises along the reef edge
## beyond the surf, only its dorsal fin (and now and then the tip of its tail) cutting the
## surface before it sinks out of sight again. Spotted eagle rays glide through the shallows
## near the player on slow wing beats, and veer away from a wader. And one manta ray, five
## meters across, lives in the lagoon: it cruises its deeper water on long slow wing beats,
## comes up under the surface to feed now and then, and takes no notice of anybody.

@export var player_path: NodePath = ^"../Player"

const SeaModels := preload("res://scripts/sea_models.gd")
const Heights := preload("res://scripts/heights.gd")
const NO_WATER := Vector3(1e9, 0, 0)

var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _shark: MeshInstance3D
var _shark_timer := 0.0
var _shark_on := false
var _shark_d := {}
var _ray_mesh: Mesh
var _ray_mat: ShaderMaterial
var _rays: Array = []
var _ray_timer := 0.0
var _pups: Array = []


func _ready() -> void:
	_rng.randomize()
	_player = get_node_or_null(player_path)
	var shader := load("res://shaders/sea_creature.gdshader") as Shader
	_shark = MeshInstance3D.new()
	_shark.mesh = SeaModels.tiger_shark()
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.set_shader_parameter("species", 0)
	_shark.material_override = sm
	_shark.visible = false
	_shark.extra_cull_margin = 2.0
	_shark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shark)
	_ray_mesh = SeaModels.eagle_ray()
	_ray_mat = ShaderMaterial.new()
	_ray_mat.shader = shader
	_ray_mat.set_shader_parameter("species", 1)
	_shark_timer = _rng.randf_range(70.0, 160.0)
	_ray_timer = _rng.randf_range(15.0, 35.0)
	_setup_pups(shader)
	_setup_manta(shader)


## The level of the sea now (scripts/tide.gd sets it; 0 as the island was built).
## Everything in this script is worked out as if the sea stood at 0: `_ground()` gives the
## ground as it lies against today's level, the animals' heights are heights against it, and
## only when a node is placed is the level added (`_up()`).
var tide := 0.0


## The sea's surface at (x, z) in the world: the tide and the swell.
func surface(x: float, z: float) -> float:
	return tide + wave_height(x, z)


func _up(pos: Vector3) -> Vector3:
	return Vector3(pos.x, pos.y + tide, pos.z)


## Where the player is, against today's sea level.
func _pp() -> Vector3:
	if _player == null:
		return Vector3(1e6, 0, 0)
	var p := _player.global_position
	return Vector3(p.x, p.y - tide, p.z)


func _ground(x: float, z: float) -> float:
	# (the shared height map, with the .blend's rocks; beyond it the open ocean: -30)
	return Heights.with_rocks(x, z, -30.0 + tide) - tide


## A point in water between dmin and dmax deep, rmin..rmax from `around` (NO_WATER if none).
func _water_spot(around: Vector3, rmin: float, rmax: float, dmin: float, dmax: float) -> Vector3:
	for i in 60:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(rmin, rmax)
		var p := around + Vector3(cos(a) * r, 0, sin(a) * r)
		var g := _ground(p.x, p.z)
		if g < -dmin and g > -dmax:
			return Vector3(p.x, 0, p.z)
	return NO_WATER


## Height of the ocean surface at x,z: the same Gerstner sum as ocean.gdshader (vertex part,
## including its grid_spacing() fade: keep the two in step), so a swimming animal can stay a
## fixed distance below the actual waves.
const WAVES := [[Vector2(-1.0, 0.18), 21.0, 0.10], [Vector2(-1.0, -0.35), 13.0, 0.10], [Vector2(-0.8, 0.6), 7.3, 0.09],
	[Vector2(-0.9, -0.7), 4.1, 0.08], [Vector2(-0.3, 1.0), 2.6, 0.07], [Vector2(-1.0, 0.05), 1.7, 0.06], [Vector2(0.4, -1.0), 1.1, 0.05]]

var _amb: Node      # (world_time's keeper, looked up once)

## The swell at (x, z): the height of the water above the sea's level (`surface()` for the
## height in the world).
func wave_height(x: float, z: float) -> float:
	# world_time is advanced by the Ambience node (global shader params can't be read at runtime)
	if _amb == null:
		_amb = get_node_or_null("../Ambience")
	var t: float = _amb._t if _amb else 0.0
	# (the depth as the ocean's shader takes it: to the terrain, not to a rock that stands
	# on it. Read to the rock's top, the swell here was a decimeter or two smaller over a
	# sunken boulder than the sea that is drawn)
	var depth := tide - Heights.terrain(x, z, -30.0 + tide)
	var amp := lerpf(0.12, 1.0, smoothstep(0.3, 6.0, depth))
	var outside := maxf(maxf(x - 65.0, -210.0 - x), maxf(z - 262.0, -262.0 - z))
	amp *= 1.0 - smoothstep(0.0, 45.0, outside)
	var h := 0.0
	var sx := 0.45 + 0.15 * (x - 75.0) if x > 75.0 else (0.7 + 0.15 * (-215.0 - x) if x < -215.0 else (0.7 if x < -150.0 else (0.8 if x < -40.0 else 0.45)))
	var sz := 0.9 + 0.15 * (absf(z) - 268.0) if absf(z) > 268.0 else (0.9 if (z > 175.0 or z < -215.0) else 0.55)
	var spacing := maxf(sx, sz)
	for w in WAVES:
		var d: Vector2 = (w[0] as Vector2).normalized()
		var k := TAU / float(w[1])
		var fade := 1.0 - smoothstep(float(w[1]) * 0.16, float(w[1]) * 0.33, spacing)
		var c := sqrt(9.81 / k)
		h += float(w[2]) / k * amp * fade * sin(k * (d.dot(Vector2(x, z)) - c * t))
	return h


# ------------------------------------------------------------------ corals
## Corals (and the den rocks) are solid to everything here: an animal swims over one where
## there is water enough for it, and around it otherwise (until 2026-11-12 they
## swam through them). The heights come from seabed.gd's map
## (`coral_top()`: half-meter cells, each coral a little wider than it is).
## (For the tests: false is how it was.)
var avoid_corals := true
var _seabed: Node


## The top of the tallest coral at (x, z), against today's sea level; -99 where none stands.
func _coral(x: float, z: float) -> float:
	if not avoid_corals:
		return -99.0
	if _seabed == null:
		_seabed = get_node_or_null("../IslandLife/Seabed")
		if _seabed == null:
			return -99.0
	var t: float = _seabed.coral_top(x, z)
	return t - tide if t > -90.0 else -99.0


## Is the anchored boat's hull over (x, z), or within `margin` of it? Under it an animal
## keeps below the keel (seabed.gd: the boat is a ceiling).
func _boat(x: float, z: float, margin := 0.3) -> bool:
	if not avoid_corals:
		return false
	if _seabed == null:
		_seabed = get_node_or_null("../IslandLife/Seabed")
	return _seabed != null and _seabed.boat_over(x, z, margin)


## ... the tallest under an animal `half` wide to either side that swims the way `dir` at p.
func _coral_across(p: Vector3, dir: Vector3, half: float) -> float:
	var best := _coral(p.x, p.z)
	var n := maxi(int(ceil(half / 0.75)), 1)
	for k in range(1, n + 1):
		var o := half * float(k) / float(n)
		best = maxf(best, maxf(_coral(p.x - dir.z * o, p.z + dir.x * o), _coral(p.x + dir.z * o, p.z - dir.x * o)))
	return best


## How high an animal has to be at p so as to pass over the corals on its way (`dir`): the
## tallest under it, and those ahead and behind counted lower the further they are (`slope`
## meters of height for every meter beyond `body`), so that it rises to one in good time and
## sinks again behind it, without a step. -99 where nothing stands near.
func _coral_ramp(p: Vector3, dir: Vector3, half: float, body: float, reach: float, slope: float) -> float:
	var best := -99.0
	var a := -reach
	while a <= reach + 0.01:
		var t := _coral_across(p + dir * a, dir, half)
		if t > -90.0:
			best = maxf(best, t - maxf(absf(a) - body, 0.0) * slope)
		a += 1.0
	return best


func _depth_gradient(p: Vector3) -> Vector3:
	# points toward deeper water
	var e := 2.0
	return Vector3(_ground(p.x - e, p.z) - _ground(p.x + e, p.z), 0, _ground(p.x, p.z - e) - _ground(p.x, p.z + e))


# ------------------------------------------------------------------ tiger shark
## Starts a pass along the reef edge in view of the player (also callable for testing).
const SHARK_SCALE := 1.2      # a big tiger shark: ~4.3 m
const SHARK_MIN_DEPTH := 3.2  # its whole route stays in water at least this deep
const SHARK_CORAL := -1.9     # ... and clear of corals that reach higher than this (its belly is at -1.3 with the fin out)


## Starts a pass along the reef edge in view of the player (also callable for testing).
## The route is planned in advance along the depth contours, so it never crosses land.
func summon_shark() -> bool:
	if _player == null:
		return false
	var pp := _pp()
	for attempt in 12:
		# (from someone swimming it keeps well away: seen in the distance, never beside them)
		var near := 25.0 if _ground(pp.x, pp.z) > -1.2 else 55.0
		var mid := _water_spot(pp, near, near + 45.0, SHARK_MIN_DEPTH + 0.5, 16.0) if attempt < 8 else _water_spot(pp, 60.0, 140.0, SHARK_MIN_DEPTH + 0.5, 24.0)
		if mid == NO_WATER:
			continue
		# cruise roughly parallel to the shore: across the line of sight to the player
		var to_p := Vector3(pp.x - mid.x, 0, pp.z - mid.z).normalized()
		var dir := Vector3(-to_p.z, 0, to_p.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var fwd := _plan_route(mid, dir, 60.0)
		var back := _plan_route(mid, -dir, 60.0)
		back.reverse()
		var route := PackedVector3Array(back)
		route.append_array(fwd.slice(1))
		route = _meander(_smooth_route(route))
		var cum := _route_lengths(route)
		var length: float = cum[cum.size() - 1]
		if length < 45.0:
			continue
		# (smoothing cuts the corners: the water has to be deep enough there too)
		var shallowest := 99.0
		var tallest := -99.0
		for i in route.size():
			var q := route[i]
			shallowest = minf(shallowest, -_ground(q.x, q.z))
			tallest = maxf(tallest, _coral_across(q, (route[mini(i + 1, route.size() - 1)] - route[maxi(i - 1, 0)]).normalized(), 1.2))
		if shallowest < 2.3 or tallest > SHARK_CORAL:
			continue
		# (and not under the anchored boat, nor where it may swing to: its fin is out)
		var boat := false
		for q in route:
			if _boat(q.x, q.z, 4.0):
				boat = true
		if boat:
			continue
		var speed := _rng.randf_range(1.05, 1.45)
		_shark_d = {"route": route, "cum": cum, "s": 1.5, "length": length, "cruise": speed, "speed": speed, "phase": 0.0,
			"life": 0.0, "dur": length / speed, "pos": route[0] + Vector3(0, -2.6, 0), "seed": _rng.randf() * TAU,
			"glide_t": _rng.randf_range(5.0, 14.0), "glide_len": 3.0, "drive": 1.0, "kappa": 0.0, "roll": 0.0, "pitch": 0.0}
		_shark_on = true
		_shark.visible = true
		return true
	return false


## Walks from `start` in 1.5 m steps, at each step taking the straightest heading that keeps
## deep water under the shark and a few meters ahead of it. Stops where no heading works.
func _plan_route(start: Vector3, dir: Vector3, max_len: float) -> PackedVector3Array:
	var pts := PackedVector3Array([Vector3(start.x, 0, start.z)])
	var p := Vector3(start.x, 0, start.z)
	var d := dir
	var bias := _rng.randf_range(-0.04, 0.04)   # a slow, lazy curve
	var walked := 0.0
	while walked < max_len:
		var found := false
		# (it looks well ahead and turns early and gently: wide curves, no corners)
		for a in [0.0, 0.07, -0.07, 0.14, -0.14, 0.22, -0.22, 0.32, -0.32, 0.45, -0.45]:
			var c: Vector3 = d.rotated(Vector3.UP, a + bias)
			var ok := true
			for look in [1.5, 4.0, 7.0, 11.0, 15.0] if absf(a) < 0.2 else [1.5, 4.0, 7.0]:
				var q: Vector3 = p + c * look
				if -_ground(q.x, q.z) < SHARK_MIN_DEPTH or _coral_across(q, c, 1.5) > SHARK_CORAL:
					ok = false
					break
			if ok:
				d = c
				found = true
				break
		if not found:
			break
		p += d * 1.5
		walked += 1.5
		pts.append(p)
	return pts


func _smooth_route(r: PackedVector3Array) -> PackedVector3Array:
	for it in 2:   # Chaikin corner cutting
		if r.size() < 3:
			return r
		var o := PackedVector3Array([r[0]])
		for i in r.size() - 1:
			o.append(r[i].lerp(r[i + 1], 0.25))
			o.append(r[i].lerp(r[i + 1], 0.75))
		o.append(r[r.size() - 1])
		r = o
	# ... and then drawn out into long curves: a big shark does not turn on the spot
	for it in 40:
		var o := PackedVector3Array(r)
		for i in range(1, r.size() - 1):
			o[i] = (r[i - 1] + r[i] * 2.0 + r[i + 1]) * 0.25
		r = o
	return r


## A shark does not swim a ruled line: the route swings gently from side to side (a meter or
## so, over some thirty meters), wherever the water beside it is deep enough.
func _meander(r: PackedVector3Array) -> PackedVector3Array:
	var n := r.size()
	if n < 8:
		return r
	var cum := _route_lengths(r)
	var total: float = cum[n - 1]
	var ph := _rng.randf() * TAU
	var wl := _rng.randf_range(26.0, 38.0)
	var amp := _rng.randf_range(0.9, 1.5)
	var perp: Array = []
	var room := PackedFloat32Array()
	for i in n:
		var dir := (r[mini(i + 1, n - 1)] - r[maxi(i - 1, 0)]).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		perp.append(side)
		var a := r[i] + side * (amp * 1.3)
		var b := r[i] - side * (amp * 1.3)
		room.append(1.0 if -_ground(a.x, a.z) >= SHARK_MIN_DEPTH - 0.2 and -_ground(b.x, b.z) >= SHARK_MIN_DEPTH - 0.2 \
			and _coral_across(a, dir, 1.0) <= SHARK_CORAL and _coral_across(b, dir, 1.0) <= SHARK_CORAL else 0.0)
	# (no room beside it: the swing dies away well before that stretch, and comes back after it)
	for it in 2:
		var o := PackedFloat32Array(room)
		for i in n:
			var lo := 1.0
			var sum := 0.0
			for k in range(-12, 13):
				var v: float = room[clampi(i + k, 0, n - 1)]
				lo = minf(lo, v)
				sum += v
			o[i] = minf(sum / 25.0, lo if it == 0 else 1.0)
		room = o
	var out := PackedVector3Array(r)
	for i in range(1, n - 1):
		var edge := smoothstep(0.0, 14.0, cum[i]) * (1.0 - smoothstep(total - 14.0, total, cum[i]))
		var off := (sin(cum[i] / wl * TAU + ph) + 0.25 * sin(cum[i] / (wl * 0.43) * TAU + ph * 1.7)) * amp * edge * room[i]
		out[i] = r[i] + (perp[i] as Vector3) * off
	return out


## The distance along the route at each of its points.
func _route_lengths(r: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for i in r.size() - 1:
		cum.append(cum[i] + r[i].distance_to(r[i + 1]))
	return cum


## The point at distance s along the route (beyond its ends: on the straight line onward).
func _route_pt(r: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	var n := r.size()
	if s <= 0.0:
		return r[0] + (r[0] - r[1]).normalized() * -s
	if s >= cum[n - 1]:
		return r[n - 1] + (r[n - 1] - r[n - 2]).normalized() * (s - cum[n - 1])
	var i := clampi(cum.bsearch(s) - 1, 0, n - 2)
	return r[i].lerp(r[i + 1], (s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001))


func _route_dir(r: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	return (_route_pt(r, cum, s + 1.2) - _route_pt(r, cum, s - 1.2)).normalized()


## The tiger shark swims its planned route the way the young reef sharks swim: the tail beat
## follows the speed, a few strokes are followed by a glide in which the tail all but stops and
## the speed sags, and the body bends along the curve it is about to swim (the head leads).
func _update_shark(delta: float) -> void:
	if not _shark_on:
		_shark_timer -= delta
		if _shark_timer <= 0.0:
			_shark_timer = _rng.randf_range(200.0, 420.0)
			summon_shark()
		return
	var d := _shark_d
	d["life"] += delta
	var life: float = d["life"]
	var route: PackedVector3Array = d["route"]
	var cum: PackedFloat32Array = d["cum"]
	# it never stops swimming (a shark sinks if it does): the beat only eases for a moment now
	# and then, and picks up again
	d["glide_t"] -= delta
	if d["glide_t"] < -float(d["glide_len"]):
		d["glide_t"] = _rng.randf_range(10.0, 24.0)
		d["glide_len"] = _rng.randf_range(1.5, 3.0)
	var gliding: bool = d["glide_t"] < 0.0
	d["drive"] = lerpf(d["drive"], 0.55 if gliding else 1.0, 1.0 - exp(-(1.3 if gliding else 0.8) * delta))
	var drive: float = d["drive"]
	var cruise: float = float(d["cruise"]) * (1.0 + 0.1 * sin(life * 0.21 + float(d["seed"])))
	d["speed"] = lerpf(d["speed"], cruise * lerpf(0.72, 1.04, drive), 1.0 - exp(-0.35 * delta))
	var speed: float = d["speed"]
	d["s"] += speed * delta
	var s: float = d["s"]
	var pos := _route_pt(route, cum, s)
	var dir := _route_dir(route, cum, s)
	# the curve ahead (radians per meter, positive to the left)
	var kappa := _route_dir(route, cum, s + 0.5).signed_angle_to(_route_dir(route, cum, s + 4.5), Vector3.UP) / 4.0
	d["kappa"] = lerpf(d["kappa"], clampf(kappa, -0.12, 0.12), 1.0 - exp(-1.6 * delta))
	kappa = d["kappa"]
	# surface for the middle of the pass (dorsal fin out), then sink away
	var total: float = d["length"]
	var surf := smoothstep(0.0, 14.0, s) * (1.0 - smoothstep(total - 18.0, total - 2.0, s))
	# ride a fixed depth below the local wave surface (averaged over the body length), so the
	# body never breaks through a trough and only the dorsal fin cuts the water
	var half := 1.4 * SHARK_SCALE
	var wave := (wave_height(pos.x, pos.z) + wave_height(pos.x + dir.x * half, pos.z + dir.z * half)
		+ wave_height(pos.x - dir.x * half, pos.z - dir.z * half)) / 3.0
	var target_y := lerpf(-2.8, wave - 0.62 * SHARK_SCALE + sin(life * 0.7) * 0.04, surf)
	# (where it swims deep, at the ends of its pass: over the corals, not through them)
	var over := _coral_ramp(pos, dir, 1.0, 2.4 * SHARK_SCALE, 8.0, 0.25)
	if over > -90.0:
		target_y = maxf(target_y, minf(over + 0.9 * SHARK_SCALE, wave - 0.62 * SHARK_SCALE))
	var prev_y: float = (d["pos"] as Vector3).y
	pos.y = lerpf(prev_y, target_y, 1.0 - exp(-6.0 * delta)) if life > 0.2 else target_y
	d["pos"] = pos
	# one beat of the tail carries it about 0.6 of its length
	d["phase"] += delta * TAU * speed / (0.6 * 3.6 * SHARK_SCALE) * lerpf(0.75, 1.0, drive)
	# it leans a little into its turns, and noses up or down as it rises and sinks
	var climb := (pos.y - prev_y) / maxf(delta, 0.001) if life > 0.2 else 0.0
	d["pitch"] = lerpf(d["pitch"], clampf(atan2(climb, maxf(speed, 0.3)), -0.22, 0.22), 1.0 - exp(-1.5 * delta))
	d["roll"] = lerpf(d["roll"], clampf(-kappa * speed * 0.9, -0.14, 0.14), 1.0 - exp(-1.5 * delta))
	# (and it rolls a little with every sweep of the tail)
	var sb := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, d["pitch"]) * Basis(Vector3.FORWARD, float(d["roll"]) + sin(float(d["phase"]) - 1.2) * 0.035 * drive)
	_shark.global_transform = Transform3D(sb.scaled(Vector3.ONE * SHARK_SCALE), _up(pos))
	_shark.set_instance_shader_parameter("phase", d["phase"])
	_shark.set_instance_shader_parameter("amp", lerpf(0.5, 0.95, drive))
	# (the shader's bend is the sideways offset per (share of the body length) squared)
	_shark.set_instance_shader_parameter("bend", -kappa * 0.5 * 3.6 * 3.6 * SHARK_SCALE)
	if s >= total - 1.0:
		_shark_on = false
		_shark.visible = false


# ------------------------------------------------------------------ eagle rays
func summon_rays(count := 0) -> bool:
	if _player == null:
		return false
	var pp := _pp()
	var start := _water_spot(pp, 18.0, 40.0, 0.9, 4.5)
	if start == NO_WATER:
		return false
	# (not where a ray is already: the new ones would be set down in it. A group of three
	# reaches seven meters from its first)
	for o: Dictionary in _rays:
		if Vector2(start.x - (o["pos"] as Vector3).x, start.z - (o["pos"] as Vector3).z).length() < 17.0:
			return false
	if not manta.is_empty() and Vector2(start.x - (manta["pos"] as Vector3).x, start.z - (manta["pos"] as Vector3).z).length() < 17.0:
		return false
	# glide across the shallows, passing a few meters from the player
	# (in knee- to waist-deep water close to the beach, where they are seen from the shore)
	var through := _water_spot(pp, 3.0, 13.0, 0.75, 1.6)
	if through == NO_WATER:
		through = _water_spot(pp, 3.0, 22.0, 0.75, 4.5)
		if through == NO_WATER:
			return false
	var dir := Vector3(through.x - start.x, 0, through.z - start.z).normalized()
	var n: int = count if count > 0 else [1, 1, 2, 2, 3][_rng.randi() % 5]
	# (in echelon: each one out to the same side of the one before and a little behind it,
	# clear of its wings and of its tail)
	var wing_side := Vector3(-dir.z, 0, dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var off := Vector3.ZERO
	for i in n:
		# (each in water deep enough, with no coral and no rock where it is set down: a
		# companion's place was not looked at, and could lie in a boulder)
		if i > 0:
			off += wing_side * _rng.randf_range(2.6, 3.4) - dir * _rng.randf_range(0.8, 2.2)
		var at := start + off
		if _ground(at.x, at.z) > -0.75 or _coral_across(at, dir, 1.0) > -90.0:
			if i == 0:
				return false
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _ray_mesh
		mi.material_override = _ray_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = _up(start + off)       # (not at the world's origin for its first frame)
		_rays.append({"node": mi, "pos": start + off, "dir": dir, "speed": _rng.randf_range(0.8, 1.2),
			"phase": _rng.randf() * TAU, "life": 0.0, "scale": _rng.randf_range(0.85, 1.2), "beat": 1.0,
			"glide": 0.0, "group": _ray_groups})
	_ray_groups += 1
	return true


## Eagle rays keep clear of each other (until 2026-11-12 two that swam close by each other
## could pass through one another). A ray is 1.7 m across the wings and trails a tail of two
## meters (sea_models.gd: eagle_ray(), times its `scale`): its wings as a disc, its tail as
## two places behind it. `rays_apart` false is how it was (for the tests).
var rays_apart := true
## What a ray keeps clear of: the other rays, and the manta (as a ray of its width; it
## does not give way to anybody, so the rays do: an eagle ray and the manta were found
## passing through each other too, 7 s in nine minutes of an audit).
var _ray_all: Array = []

func _ray_others() -> void:
	_ray_all = _rays.duplicate()
	if not manta.is_empty():
		var yaw: float = manta["yaw"]
		_ray_all.append({"pos": manta["pos"], "dir": Vector3(-sin(yaw), 0, -cos(yaw)), "scale": (MANTA_HALF + 0.2) / RAY_WING, "no_tail": true, "group": -9})


## For scripts/fish.gd: the big animals a fish gets out of the way of, each [its place (the
## sea at 0, as fish.gd has it), half its width]: the eagle rays and the manta.
func big_bodies() -> Array:
	var out: Array = []
	for d: Dictionary in _rays:
		out.append([d["pos"], RAY_WING * float(d["scale"])])
	if not manta.is_empty():
		out.append([manta["pos"], MANTA_HALF])
	return out

var _ray_groups := 0
var _ray_frame := 0
const RAY_WING := 0.85
const RAY_GAP := 0.3          # the room they keep by steering
const RAY_OVER := 0.2          # how far over or under another's tail one passes
const RAY_HARD := 0.08        # the room between two rays' wings below which no step brings them nearer
var ray_stats := {"pair seconds": 0.0, "touching": 0.0, "nearest": 99.0, "ray seconds": 0.0, "meters": 0.0, "given up": 0}     # (for the tests)

## How much room the ray `d` has at the place `q` beside the other rays: the least gap
## between its wings and another's, as discs, in meters (below 0: they would touch). With
## `dir` given, the tails count too, both ways: its wings and another's tail, its own tail
## and another's wings.
## The hard rule goes by the wings only. Held to the tails as well, two rays that passed
## head to tail, each with the other's tail beside its wing, could neither go on nor turn
## (a turn swings two meters of tail round), and stood still for a minute and more: the
## tails are kept clear by steering, not by stopping.
func _ray_room(d: Dictionary, q: Vector3, dir := Vector3.ZERO) -> float:
	var room := 99.0
	var ms: float = d["scale"]
	var mine: float = RAY_WING * ms
	for o: Dictionary in _ray_all:
		if is_same(o, d):
			continue
		var op: Vector3 = o["pos"]
		var os: float = o["scale"]
		room = minf(room, Vector2(q.x - op.x, q.z - op.z).length() - mine - RAY_WING * os)
		if dir == Vector3.ZERO or o.has("no_tail"):
			continue
		var od: Vector3 = o["dir"]
		for back: float in [1.2, 2.2]:
			var t := op - od * (back * os)
			room = minf(room, Vector2(q.x - t.x, q.z - t.z).length() - mine - 0.12)
			var mt := q - dir * (back * ms)
			room = minf(room, Vector2(mt.x - op.x, mt.z - op.z).length() - RAY_WING * os - 0.12)
	return room


## For the tests: the rays that are out go, and a group of `n` comes.
func ray_group(n: int) -> bool:
	for d: Dictionary in _rays:
		(d["node"] as Node).queue_free()
	_rays.clear()
	return summon_rays(n)


## For the tests: a node that keeps to the middle of the rays that are out (for `chase`).
func ray_marker() -> Node3D:
	var m := get_node_or_null("RayMarker") as Node3D
	if m == null:
		m = Node3D.new()
		m.name = "RayMarker"
		add_child(m)
	var c := Vector3.ZERO
	for d: Dictionary in _rays:
		c += _up(d["pos"]) / _rays.size()
	m.global_position = c
	return m


## For the tests: the rays for `seconds` of their time, called again whenever fewer than two
## are about (so that a new group meets a ray that is there): how long two were out together,
## how long any two touched, the least gap, how fast they went, how many gave up for want
## of a way on.
func ray_soak(seconds: float) -> Dictionary:
	_ray_others()
	ray_stats = {"pair seconds": 0.0, "touching": 0.0, "nearest": 99.0, "ray seconds": 0.0, "meters": 0.0, "given up": 0}
	for i in int(seconds / 0.05):
		if _rays.size() < 2 and i % 60 == 0:
			summon_rays()
		_update_rays(0.05)
	var out := ray_stats.duplicate()
	out["mean distance to the nearest of its group"] = snappedf(float(out.get("company", 0.0)) / maxf(float(out.get("company seconds", 0.0)), 0.01), 0.01)
	out.erase("company")
	out["meters a second"] = snappedf(float(out["meters"]) / maxf(float(out["ray seconds"]), 0.01), 0.01)
	out["rays apart"] = rays_apart
	return out


## How near the tail of the ray `o` comes to the body of a ray of size `sc` at `p`: 1 where
## it touches (the body as an ellipse, 0.85 to the side and 0.6 fore and aft, times `sc`,
## whichever way it heads: the worst case), more further off.
func _ray_wake(o: Dictionary, p: Vector3, sc: float) -> float:
	if o.has("no_tail"):
		return 99.0
	var op: Vector3 = o["pos"]
	var od: Vector3 = o["dir"]
	var os: float = o["scale"]
	var least := 99.0
	for back: float in [0.9, 1.3, 1.7, 2.1, 2.5]:
		var t := op - od * (back * os)
		least = minf(least, Vector2(p.x - t.x, p.z - t.z).length() / (0.72 * sc))
	return least


## Does the tail of the ray `o` lie in the body of the ray `d` (its body an ellipse along its
## own heading)? For the tests.
func _ray_tail_in(o: Dictionary, d: Dictionary) -> bool:
	var op: Vector3 = o["pos"]
	var od: Vector3 = o["dir"]
	var os: float = o["scale"]
	var p: Vector3 = d["pos"]
	var f: Vector3 = d["dir"]
	var sc: float = d["scale"]
	for back: float in [0.9, 1.3, 1.7, 2.1, 2.5]:
		var t := op - od * (back * os) - p
		var fore := t.x * f.x + t.z * f.z
		var side := -t.x * f.z + t.z * f.x
		if pow(fore / (0.6 * sc), 2.0) + pow(side / (0.85 * sc), 2.0) < 1.0:
			return true
	return false


func _update_rays(delta: float) -> void:
	_ray_timer -= delta
	if _ray_timer <= 0.0:
		_ray_timer = _rng.randf_range(35.0, 90.0)
		if _rays.size() < 2:
			summon_rays()
	var pp := _pp()
	var wading := _ground(pp.x, pp.z) < 0.05 and pp.y < 0.5   # (in the water, not on a rock in it)
	_ray_frame += 1
	_ray_others()
	for i in range(_rays.size() - 1, -1, -1):
		var d: Dictionary = _rays[i]
		d["life"] += delta
		var pos: Vector3 = d["pos"]
		var dir: Vector3 = d["dir"]
		var dir0 := dir
		var pos0 := pos
		var y0 := pos.y
		# (its own pace, which it comes back to. The pace it wanted used to be the pace it
		# had: once hurried by a wader it stayed fast, and "a little slower to let a
		# companion catch up" would have brought it to a stop)
		if not d.has("cruise"):
			d["cruise"] = d["speed"]
		var speed: float = d["cruise"]
		# veer away from a wader
		var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
		if wading and away.length() < 4.5:
			dir = dir.slerp(away.normalized(), clampf(delta * 1.2, 0, 1)).normalized()
			speed = 1.5
		# keep to water at least 0.7 m deep
		var ahead := pos + dir * 3.0
		if _ground(ahead.x, ahead.z) > -0.7:
			var g := _depth_gradient(ahead)
			if g.length() > 0.001:
				dir = dir.slerp(g.normalized(), clampf(delta * 2.0, 0, 1)).normalized()
		dir = dir.rotated(Vector3.UP, sin(d["life"] * 0.3 + d["phase"]) * delta * 0.12)
		# another ray near: it bears away from it, early and gently
		if rays_apart:
			for o: Dictionary in _ray_all:
				if is_same(o, d):
					continue
				var off := Vector3(pos.x - (o["pos"] as Vector3).x, 0, pos.z - (o["pos"] as Vector3).z)
				var need: float = RAY_WING * (float(d["scale"]) + float(o["scale"])) + RAY_GAP
				# (the manta is seen from further off: it comes on at its own pace and does
				# not turn aside; and a ray it has come close to makes off a little faster)
				var early := 4.5 if o.has("no_tail") else 1.0
				if o.has("no_tail") and off.length() < need + 1.5:
					speed = maxf(speed, 1.5)
				if off.length() < need + early and off.length() > 0.01:
					# (to the side it is on already; one dead ahead or astern is passed on the right)
					var side := Vector3(-dir.z, 0, dir.x)
					var bear := side * (1.0 if off.dot(side) >= -0.05 else -1.0)
					var k := 1.0 - smoothstep(need, need + early, off.length())
					dir = dir.slerp((dir + bear * 0.8).normalized(), clampf(delta * 1.6 * k, 0, 1)).normalized()
				# (and out of its wake: the tail trails two meters behind a ray. One that is
				# near another's tail moves out to the side of it that it is on)
				var wake := _ray_wake(o, pos, float(d["scale"]))
				if wake < 2.2:
					var o_side := Vector3(-(o["dir"] as Vector3).z, 0, (o["dir"] as Vector3).x)
					var out_of := o_side * (1.0 if off.dot(o_side) >= 0.0 else -1.0)
					dir = dir.slerp((dir + out_of * 0.9).normalized(), clampf(delta * 2.2 * (1.0 - smoothstep(1.0, 2.2, wake)), 0, 1)).normalized()
			# ... and keeps company with those it came with: the way they go, and not far
			# from the nearest of them (bearing away alone, a group of three was three
			# single rays, each on its own course, within a minute)
			var mates := Vector3.ZERO
			var near := Vector3.ZERO
			var near_d := 1e9
			for o: Dictionary in _rays:
				if is_same(o, d) or int(o.get("group", -1)) != int(d.get("group", -2)):
					continue
				mates += o["dir"] as Vector3
				var to := Vector3((o["pos"] as Vector3).x - pos.x, 0, (o["pos"] as Vector3).z - pos.z)
				if to.length() < near_d:
					near_d = to.length()
					near = to
			if near_d < 1e8 and not (wading and away.length() < 4.5):
				if mates.length() > 0.01:
					dir = dir.slerp(mates.normalized(), clampf(delta * 0.6, 0, 1)).normalized()
				var comfy: float = RAY_WING * 2.0 * float(d["scale"]) + RAY_GAP + 1.5
				if near_d > comfy:
					dir = dir.slerp(near.normalized(), clampf(delta * 0.5 * smoothstep(comfy, comfy + 3.0, near_d), 0, 1)).normalized()
					# (one that has fallen behind beats a little faster, one that is ahead waits)
					speed *= 1.0 + 0.3 * clampf(near.dot(dir) / 3.0, -1.0, 1.0)
			# (no turn that swings its tail into a neighbor)
		d["dir"] = dir
		d["speed"] = lerpf(d["speed"], speed, delta)
		# hard rule: never onto ground shallower than 0.7 m; turn toward open water instead
		var step: float = d["speed"] * delta
		var moved := false
		var held := false         # a neighbor was in the way of a heading that was free otherwise
		# ... and never into a coral: what it is not above yet, it swims around
		var half: float = 0.6 * float(d["scale"])
		var under := pos.y - 0.14
		for a in [0.0, 0.3, -0.3, 0.7, -0.7, 1.2, -1.2, 1.8, -1.8, PI]:
			var c: Vector3 = dir.rotated(Vector3.UP, a)
			var q: Vector3 = pos + c * maxf(step, 0.6)
			if _ground(q.x, q.z) < -0.6 and _coral_across(q, c, half) <= under and _coral_across(pos + c * 1.2, c, half) <= under:
				# ... and never into another ray: no step that leaves less than the gap
				# between them, unless it is a step apart
				if rays_apart:
					var room := _ray_room(d, pos + c * step)
					if room < RAY_HARD and room < _ray_room(d, pos):
						held = true
						continue
				if a != 0.0:
					dir = dir.slerp(c, clampf(delta * 3.0, 0, 1)).normalized()
					d["dir"] = dir
				pos += c * step
				moved = true
				d["wait"] = 0.0
				break
		if not moved and held:
			# (only a neighbor is in the way: it waits for it to pass, which is not being stuck)
			d["wait"] = float(d.get("wait", 0.0)) + delta
			ray_stats["waiting"] = float(ray_stats.get("waiting", 0.0)) + delta
			ray_stats["longest wait"] = maxf(float(ray_stats.get("longest wait", 0.0)), float(d["wait"]))
			moved = true
		elif not moved:
			# (the tide has fallen under it: out, the way the ground falls)
			var out := _depth_gradient(pos)
			if out.length() > 0.001 and not (rays_apart and _ray_room(d, pos + out.normalized() * step) < minf(0.0, _ray_room(d, pos))):
				pos += out.normalized() * step
				d["dir"] = dir.slerp(out.normalized(), clampf(delta * 3.0, 0, 1)).normalized()
		d["stuck"] = 0.0 if moved else d.get("stuck", 0.0) + delta
		var g0 := _ground(pos.x, pos.z)
		var want_y := clampf(g0 * 0.45, g0 + 0.3, -0.32)
		# (over the corals on its way where there is water enough over them)
		var over := _coral_ramp(pos, d["dir"], half, 1.0, 5.0, 0.3)
		var rise := 1.0
		if over > -90.0 and over + 0.45 > want_y:
			want_y = minf(over + 0.45, -0.32)
			rise = 2.5
		# (under the anchored boat: below its keel)
		if _boat(pos.x, pos.z, half + 0.4):
			want_y = maxf(minf(want_y, -0.95), g0 + 0.3)
		# (where another's tail trails past it all the same, it rides a hand's breadth over
		# the tail, or under it, whichever the water there leaves room for)
		if rays_apart:
			for o: Dictionary in _rays:
				if is_same(o, d) or _ray_wake(o, pos, float(d["scale"])) > 1.5:
					continue
				var ty: float = (o["pos"] as Vector3).y
				var above_it := ty + RAY_OVER
				var below_it := ty - RAY_OVER
				var can_over := above_it <= -0.26
				var can_below := below_it >= g0 + 0.22
				if can_over and (not can_below or pos.y >= ty):
					want_y = maxf(want_y, above_it)
					rise = 3.0
				elif can_below:
					want_y = minf(want_y, below_it)
					rise = 3.0
		pos.y = lerpf(pos.y if d["life"] > 0.1 else want_y, want_y, 1.0 - exp(-rise * delta))
		d["pos"] = pos
		# a few strong beats, then a long glide
		d["glide"] -= delta
		if d["glide"] < -3.0:
			d["glide"] = _rng.randf_range(1.5, 4.0)
		var beating: bool = d["glide"] < 0.0 or d["speed"] > 1.6
		d["beat"] = lerpf(d["beat"], 1.0 if beating else 0.15, 1.0 - exp(-2.0 * delta))
		d["phase"] += delta * (2.3 if beating else 1.0)
		var mi: MeshInstance3D = d["node"]
		# "flying": it banks into its turns, noses up and down with the sea floor, and every
		# down-stroke of the wings lifts the body a little
		var turn := dir0.signed_angle_to(d["dir"], Vector3.UP) / maxf(delta, 0.001)
		d["bank"] = lerpf(d.get("bank", 0.0), clampf(-turn * 0.9, -0.5, 0.5) + sin(d["life"] * 0.4) * 0.05, 1.0 - exp(-2.0 * delta))
		var climb := (pos.y - y0) / maxf(delta, 0.001) if d["life"] > 0.2 else 0.0
		d["pitch"] = lerpf(d.get("pitch", 0.0), clampf(atan2(climb, maxf(d["speed"], 0.3)), -0.35, 0.35), 1.0 - exp(-2.0 * delta))
		var beat: float = d["beat"]
		var heave := -sin(d["phase"] - 0.5) * 0.05 * beat * float(d["scale"])
		var rb := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, float(d["pitch"]) + cos(d["phase"] - 0.5) * 0.04 * beat) \
			* Basis(Vector3.FORWARD, d["bank"])
		mi.global_transform = Transform3D(rb.scaled(Vector3.ONE * d["scale"]), _up(pos) + Vector3(0, heave, 0))
		mi.set_instance_shader_parameter("phase", d["phase"])
		mi.set_instance_shader_parameter("amp", d["beat"])
		ray_stats["ray seconds"] += delta
		ray_stats["meters"] += pos.distance_to(pos0)
		if d["stuck"] > 2.0:
			ray_stats["given up"] += 1
		for o: Dictionary in _rays:
			if not is_same(o, d) and int(o.get("group", -1)) == int(d.get("group", -2)):
				var gap := Vector2((o["pos"] as Vector3).x - pos.x, (o["pos"] as Vector3).z - pos.z).length()
				d["mate"] = minf(float(d.get("mate", 1e9)), gap) if d.get("mate_f", -1) == _ray_frame else gap
				d["mate_f"] = _ray_frame
		if d.get("mate_f", -1) == _ray_frame:
			ray_stats["company"] = float(ray_stats.get("company", 0.0)) + float(d["mate"]) * delta
			ray_stats["company seconds"] = float(ray_stats.get("company seconds", 0.0)) + delta
		if _ray_all.size() > 1:
			var room := _ray_room(d, pos)
			ray_stats["pair seconds"] += delta
			ray_stats["nearest"] = minf(float(ray_stats["nearest"]), room)
			for o: Dictionary in _rays:
				if not is_same(o, d) and _ray_tail_in(o, d) and absf(pos.y - (o["pos"] as Vector3).y) < RAY_OVER * 0.7:
					ray_stats["tail on a wing"] = float(ray_stats.get("tail on a wing", 0.0)) + delta
					break
			if room < 0.0:
				ray_stats["touching"] += delta
				if not d.get("touch", false) and (ray_stats.get("cases", []) as Array).size() < 12:
					# (the first moment of a touch: how old the ray is, whether it had a way on, the gap)
					ray_stats["cases"] = (ray_stats.get("cases", []) as Array) + [["life %.1f" % float(d["life"]), "moved" if moved else "no way", "held" if held else "free", "waited %.1f" % float(d.get("wait", 0.0)), "speed %.2f" % float(d["speed"]), "room %.2f from %.2f" % [room, float(d.get("room_was", 9.0))], "wader %.1f m" % away.length(), "stepped %.3f" % pos.distance_to(pos0), "turned %.3f" % dir0.angle_to(d["dir"])]]
			d["touch"] = room < 0.0
			d["room_was"] = room
		if d["life"] > 110.0 or d["stuck"] > 2.0 or g0 > -0.45 or Vector2(pos.x - pp.x, pos.z - pp.z).length() > 90.0:
			mi.queue_free()
			_rays.remove_at(i)


# ------------------------------------------------------------------ young blacktip reef sharks
## Young blacktip reef sharks keep to water a big shark cannot enter: they patrol the shallows
## along the beaches, in half a meter of water, the dorsal fin and the tip of the tail out.
const PUP_MIN_DEPTH := 0.36   # hard rule: never over ground shallower than this
const PUP_HOMES := [Vector3(9, 0, 22), Vector3(9, 0, -62), Vector3(7, 0, 100), Vector3(-178, 0, 96), Vector3(-176, 0, -112)]

func _setup_pups(shader: Shader) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("species", 2)
	var pup_mesh := SeaModels.blacktip_shark()
	for home: Vector3 in PUP_HOMES:
		var at := NO_WATER
		for r in [14.0, 30.0, 60.0]:
			at = _water_spot(home, 0.0, r, 0.5, 1.0)
			if at != NO_WATER:
				break
		if at == NO_WATER:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "ReefShark%d" % _pups.size()
		mi.mesh = pup_mesh
		mi.material_override = mat
		mi.extra_cull_margin = 1.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var a := _rng.randf() * TAU
		# (one far from the player is not moved at all: it must not wait at the world's origin,
		# full size, where its fin stood out of the sand of the start beach until 2026-11-11)
		mi.transform = Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * 0.3), at + Vector3(0, -0.4, 0))
		_pups.append({"node": mi, "pos": at + Vector3(0, -0.2, 0), "home": at, "dir": Vector3(cos(a), 0, sin(a)),
			"sense": 1.0 if _rng.randf() < 0.5 else -1.0, "speed": 0.6, "phase": _rng.randf() * TAU,
			"scale": _rng.randf_range(0.25, 0.33), "t": _rng.randf() * 30.0, "flee": 0.0, "turn_t": _rng.randf_range(15.0, 40.0)})


func _update_pups(delta: float) -> void:
	var pp := _pp()
	for d: Dictionary in _pups:
		var pos: Vector3 = d["pos"]
		var mi: MeshInstance3D = d["node"]
		var away_far := Vector2(pos.x - pp.x, pos.z - pp.z).length()
		if -_ground(pos.x, pos.z) < PUP_MIN_DEPTH - 0.04 and away_far > 70.0:
			# the tide has fallen and left this place too shallow while nobody was near: it
			# has gone out with the water (to the same stretch of shore)
			var spot := _water_spot(d["home"], 2.0, 30.0, 0.6, 1.0)
			if spot != NO_WATER:
				pos = Vector3(spot.x, pos.y, spot.z)
				d["pos"] = pos
				mi.global_transform = Transform3D(mi.global_transform.basis, _up(pos))
		if away_far > 170.0:
			continue   # far out of sight: it waits
		d["t"] += delta
		var dir: Vector3 = d["dir"]
		var dir0 := dir
		var depth := -_ground(pos.x, pos.z)
		var deeper := _depth_gradient(pos)
		deeper = deeper.normalized() if deeper.length() > 0.001 else Vector3.ZERO
		# along the beach, in water 0.5 to 1.1 m deep
		var want := Vector3(-deeper.z, 0, deeper.x) * float(d["sense"])
		if depth < 0.55:
			want = (want + deeper * 1.5).normalized()
		elif depth > 1.1:
			want = (want - deeper * clampf((depth - 1.1) * 2.0, 0.3, 2.0)).normalized()
		want = want.rotated(Vector3.UP, sin(d["t"] * 0.37 + d["phase"]) * 0.5)
		# it turns back now and then, and before it strays far from its stretch of shore
		d["turn_t"] -= delta
		var home: Vector3 = d["home"]
		var from_home := Vector3(pos.x - home.x, 0, pos.z - home.z)
		if d["turn_t"] <= 0.0 or (from_home.length() > 45.0 and from_home.dot(dir) > 0.0):
			d["sense"] = -float(d["sense"])
			d["turn_t"] = _rng.randf_range(20.0, 60.0)
		# someone coming close: it turns away toward deeper water and swims off, briskly but
		# without bolting (they keep their distance; they do not panic)
		var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
		if away.length() < 5.0 and pp.y < 2.5:
			d["flee"] = 3.0
		var speed := 0.55 + 0.2 * sin(d["t"] * 0.23)
		var rate := 1.2
		if d["flee"] > 0.0:
			d["flee"] -= delta
			want = (away.normalized() + deeper * 0.8).normalized()
			speed = 1.25
			rate = 2.2
		dir = dir.slerp(want, clampf(delta * rate, 0.0, 1.0)).normalized()
		d["speed"] = lerpf(d["speed"], speed, 1.0 - exp(-(1.6 if speed > 1.0 else 0.8) * delta))
		# hard rule: only where the ground ahead is deep enough
		var step: float = d["speed"] * delta
		for a in [0.0, 0.3, -0.3, 0.7, -0.7, 1.2, -1.2, 1.8, -1.8, 2.5, -2.5, PI]:
			var c: Vector3 = dir.rotated(Vector3.UP, a)
			var q: Vector3 = pos + c * maxf(step, 0.5)
			var q2: Vector3 = pos + c * 1.2
			if -_ground(q.x, q.z) > PUP_MIN_DEPTH and -_ground(q2.x, q2.z) > PUP_MIN_DEPTH \
					and _coral(q.x, q.z) <= pos.y - 0.14 and _coral(q2.x, q2.z) <= pos.y - 0.14:
				if a != 0.0:
					dir = dir.slerp(c, clampf(delta * 4.0, 0.0, 1.0)).normalized()
				pos += c * step
				break
			if a == PI and deeper != Vector3.ZERO:
				# (no way on: the tide is falling under it. Out, the way the ground falls)
				pos += deeper * step * 1.5
				dir = dir.slerp(deeper, clampf(delta * 4.0, 0.0, 1.0)).normalized()
		d["dir"] = dir
		# just under the surface where it is shallow (the fin shows), lower in deeper water
		depth = -_ground(pos.x, pos.z)
		var sc: float = d["scale"]
		var wave := wave_height(pos.x, pos.z)
		var want_y := maxf(wave - lerpf(0.52, 1.1, smoothstep(0.7, 1.6, depth)) * sc, -depth + 0.45 * sc)
		pos.y = lerpf(pos.y, want_y, 1.0 - exp(-3.0 * delta))
		d["pos"] = pos
		var turn := dir0.signed_angle_to(dir, Vector3.UP) / maxf(delta, 0.001)
		d["phase"] += delta * (3.0 + float(d["speed"]) * 4.5)
		mi.global_transform = Transform3D((Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.FORWARD, clampf(-turn * 0.15, -0.2, 0.2))).scaled(Vector3.ONE * sc), _up(pos))
		mi.set_instance_shader_parameter("phase", d["phase"])
		mi.set_instance_shader_parameter("amp", 0.75 + 0.25 * clampf(float(d["speed"]) / 1.3, 0.0, 1.0))
		mi.set_instance_shader_parameter("bend", clampf(-turn * 1.0, -1.0, 1.0))


# ------------------------------------------------------------------ the manta ray
## One manta, the island's biggest animal (five meters across). It wanders the deeper water of the lagoon from goal
## to goal in wide curves (a few beats of the great wings, then a glide), about half-way between
## the floor and the surface; every minute or two it swims just under the surface for a while,
## the wing tips breaking it. If someone is swimming or wading, its way often leads past them
## at a few meters: it does not flee and does not hurry, it only leaves room for its wings.
const MANTA_SCALE := 2.5          # 5 m across (4.2 m at first; made at least 15 % bigger)
const MANTA_MIN_DEPTH := 3.1      # hard rule: only over water this deep (and what is ahead of it)
const MANTA_CORAL := -1.3         # a coral that reaches higher than this it cannot pass over: around it
const MANTA_HALF := 2.3           # (half its width)
const MANTA_UNDER := 0.75         # how far below its middle the wings reach on a down-stroke
const MANTA_HOME := Vector3(70, 0, 20)
const MANTA_RANGE := 130.0

var _manta: MeshInstance3D
var manta := {}

func _setup_manta(shader: Shader) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("species", 3)
	_manta = MeshInstance3D.new()
	_manta.name = "Manta"
	_manta.mesh = SeaModels.manta_ray()
	_manta.material_override = mat
	_manta.extra_cull_margin = 2.5
	add_child(_manta)
	var at := _water_spot(MANTA_HOME, 0.0, 60.0, 3.6, 9.0)
	if at == NO_WATER:
		at = MANTA_HOME
	manta = {"pos": at + Vector3(0, -1.6, 0), "yaw": _rng.randf() * TAU, "speed": 1.0, "goal": at, "t": 0.0, "phase": 0.0,
		"drive": 1.0, "glide": _rng.randf_range(4.0, 9.0), "glide_len": 3.0, "turn": 0.0, "bank": 0.0, "pitch": 0.0,
		"up": 0.0, "up_t": _rng.randf_range(40.0, 90.0), "stuck": 0.0}
	_manta_goal()
	_place_manta()


## The headings the manta tries, as turns from the one it has (radians).
const MANTA_TURNS: Array[float] = [0.0, 0.3, -0.3, 0.6, -0.6, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2, PI]

## Deep enough water all the way from a to b?
func _manta_clear(a: Vector3, b: Vector3) -> bool:
	var n := maxi(int(a.distance_to(b) / 3.0), 1)
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		var dep := -_ground(q.x, q.z)
		if dep < MANTA_MIN_DEPTH + 0.3 or dep > 16.0:
			return false
	if avoid_corals:
		var dir := (b - a).normalized()
		n = maxi(int(a.distance_to(b) / 1.0), 1)
		for i in n + 1:
			if _coral_across(a.lerp(b, float(i) / n), dir, MANTA_HALF) > MANTA_CORAL:
				return false
	return true


## Is the way `h` free for the manta from where it is? `far`: deep water for eleven meters
## ahead, room for a swimmer's side, no coral near that it is not above yet and none ahead
## too tall to pass over. Not `far` (the way out of a corner): only the next two meters, and
## the water may be too shallow as long as it does not get shallower.
func _manta_way(flat: Vector3, y: float, h: float, pp: Vector3, far: bool) -> bool:
	var dir := Vector3(-sin(h), 0, -cos(h))
	var here := -_ground(flat.x, flat.z)
	# (0.6 and 1.6: the two places the hard rule in _update_manta() asks about)
	for look in [0.6, 1.6, 2.5, 6.0, 11.0] if far else [0.6, 1.6]:
		var q: Vector3 = flat + dir * look
		var dep := -_ground(q.x, q.z)
		if dep > 18.0 or (dep < MANTA_MIN_DEPTH and (far or dep < here)):
			return false
		# (a coral too tall to pass over, or one right ahead that it is not above yet.
		# Further off only what stands in the middle of its way counts, and beyond seven
		# meters nothing: asked for a clear way eleven meters long and as wide as itself,
		# it found none at all among the corals at low water.)
		if look < 7.0:
			var ct := _coral_across(q, dir, MANTA_HALF if look < 3.0 else 1.2)
			if ct > MANTA_CORAL or (far and look < 3.0 and ct > y - MANTA_UNDER):
				return false
		if far and look < 7.0 and Vector2(q.x - pp.x, q.z - pp.z).length() < 4.2 and absf(pp.y - y) < 3.0:
			return false
	return true


## Where to next: somewhere in the lagoon it can reach in a straight line; with someone in or
## at the water, often a place beyond them, so that its way leads past them.
func _manta_goal() -> void:
	var pos: Vector3 = manta["pos"]
	var flat := Vector3(pos.x, 0, pos.z)
	if _player:
		var pp := _pp()
		var to_p := Vector3(pp.x - pos.x, 0, pp.z - pos.z)
		if to_p.length() < 180.0 and to_p.length() > 12.0 and _ground(pp.x, pp.z) < 1.5 and _rng.randf() < 0.55:
			var side := Vector3(-to_p.z, 0, to_p.x).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
			for k in 8:
				# (past them at five to nine meters; if they stand on the beach, along the
				# deep water in front of them)
				var beyond := flat + to_p + side * _rng.randf_range(5.0, 9.0 + 6.0 * k) + to_p.normalized() * _rng.randf_range(6.0, 20.0)
				var g := _water_spot(beyond, 0.0, 6.0 + 5.0 * k, MANTA_MIN_DEPTH + 0.5, 12.0)
				if g != NO_WATER and _manta_clear(flat, g):
					manta["goal"] = g
					return
	# (its range is the lagoon off the start beach, some 130 m around its home: far enough to be
	# away for a while, near enough to be met again)
	var far := flat.distance_to(MANTA_HOME) > MANTA_RANGE
	for k in 60:
		var g := _water_spot(flat, 25.0, 90.0, MANTA_MIN_DEPTH + 0.5, 12.0)
		if g == NO_WATER or not _manta_clear(flat, g):
			continue
		var gd := g.distance_to(MANTA_HOME)
		if gd < MANTA_RANGE or (far and gd < flat.distance_to(MANTA_HOME) - 10.0):
			manta["goal"] = g
			return
	manta["goal"] = _water_spot(flat, 5.0, 25.0, MANTA_MIN_DEPTH + 0.3, 14.0)
	if manta["goal"] == NO_WATER:
		manta["goal"] = flat


func _update_manta(delta: float) -> void:
	if manta.is_empty():
		return
	var d := manta
	var pos: Vector3 = d["pos"]
	var pp := _pp()
	if Vector2(pos.x - pp.x, pos.z - pp.z).length() > 400.0:
		return
	d["t"] += delta
	var flat := Vector3(pos.x, 0, pos.z)
	var goal: Vector3 = d["goal"]
	if flat.distance_to(goal) < 6.0:
		_manta_goal()
		goal = d["goal"]
	var yaw: float = d["yaw"]
	var to_g := goal - flat
	var want := atan2(-to_g.x, -to_g.z) if to_g.length() > 0.5 else yaw
	# the straightest heading toward the goal that has deep water ahead, and leaves a swimmer
	# room for the wings
	var best := INF
	var chosen := yaw
	var found := false
	var straight := false
	var aim: float = d.get("aim", NAN)
	if not is_nan(aim) and absf(wrapf(aim - yaw, -PI, PI)) > 0.004 and _manta_way(flat, pos.y, aim, pp, true):
		# (a heading it has set out to turn to is kept until it faces it. The headings below
		# are tried a third of a radian apart, from wherever it faces: a manta that cannot
		# move until it has turned would take a step to the left, find from there that the
		# right looks better, step back, and so stand before a coral for an hour.)
		chosen = aim
		found = true
		straight = _manta_way(flat, pos.y, yaw, pp, true)
	else:
		d.erase("aim")
		# (The cheapest heading that is free: what a heading costs does not depend on whether
		# it is free, so they are tried the cheapest first and the first free one is the
		# answer; of two that cost the same, the earlier in the list, as when all twelve
		# were tried every frame. In open water that is one way looked along instead of
		# twelve: this was a sixth of all the scripts' time.)
		straight = _manta_way(flat, pos.y, yaw, pp, true)
		var costs: Array[float] = []
		for a: float in MANTA_TURNS:
			costs.append(absf(wrapf(yaw + a - want, -PI, PI)) + absf(a) * 0.15)
		for n in MANTA_TURNS.size():
			var k := -1
			for j in MANTA_TURNS.size():
				if costs[j] < INF and (k < 0 or costs[j] < costs[k]):
					k = j
			if k < 0:
				break
			if straight if k == 0 else _manta_way(flat, pos.y, yaw + MANTA_TURNS[k], pp, true):
				best = costs[k]
				chosen = yaw + MANTA_TURNS[k]
				found = true
				break
			costs[k] = INF
		if found and not straight:
			d["aim"] = chosen
	var speed_want := 1.15 + 0.15 * sin(float(d["t"]) * 0.13)
	var jammed := false
	if not found:
		# no way on with deep water ahead: it turns, slowly, toward the deepest water among
		# the ways that are free close by (no coral in the next two meters that it could
		# not pass over), and picks another goal. (Before the corals were solid it turned
		# "toward where the water is deepest": now a coral may stand just there.)
		d["stuck"] += delta
		speed_want = 0.3
		var deeper := _depth_gradient(flat)
		chosen = atan2(-deeper.x, -deeper.z) if deeper.length() > 0.001 else yaw + 1.0
		var any := false
		var out: float = d.get("way_out", NAN)
		if not is_nan(out) and absf(wrapf(out - yaw, -PI, PI)) > 0.004 and _manta_way(flat, pos.y, out, pp, false):
			chosen = out        # (kept until it faces it, as above)
			any = true
		else:
			d.erase("way_out")
			var best2 := -INF
			for a in [0.0, 0.3, -0.3, 0.6, -0.6, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2, PI]:
				var h: float = yaw + a
				if not _manta_way(flat, pos.y, h, pp, false):
					continue
				var q3: Vector3 = flat + Vector3(-sin(h), 0, -cos(h)) * 4.0
				var score := -_ground(q3.x, q3.z) - absf(a) * 0.2
				if score > best2:
					best2 = score
					chosen = h
					any = true
			if any and absf(wrapf(chosen - yaw, -PI, PI)) > 0.004:
				d["way_out"] = chosen
		# (hemmed in by corals that reach too near the surface on every side: after twenty
		# seconds it goes the way the water deepens all the same, rather than stay for good)
		d["jam"] = 0.0 if any else float(d.get("jam", 0.0)) + delta
		jammed = float(d["jam"]) > 20.0
		if d["stuck"] > 2.0:
			d["stuck"] = 0.0
			_manta_goal()
	else:
		d["stuck"] = 0.0
		d["jam"] = 0.0
		d.erase("way_out")
	var diff := wrapf(chosen - yaw, -PI, PI)
	var step := clampf(diff, -0.32 * delta, 0.32 * delta)
	yaw += step
	d["yaw"] = yaw
	d["turn"] = lerpf(d["turn"], step / maxf(delta, 0.001), 1.0 - exp(-2.0 * delta))
	# a few beats of the wings, then a glide
	d["glide"] -= delta
	if d["glide"] < -float(d["glide_len"]):
		d["glide"] = _rng.randf_range(6.0, 13.0)
		d["glide_len"] = _rng.randf_range(2.5, 5.0)
	var gliding: bool = d["glide"] < 0.0
	d["drive"] = lerpf(d["drive"], 0.18 if gliding else 1.0, 1.0 - exp(-(1.0 if gliding else 0.7) * delta))
	var drive: float = d["drive"]
	d["speed"] = lerpf(d["speed"], speed_want * lerpf(0.82, 1.03, drive), 1.0 - exp(-0.4 * delta))
	var speed: float = d["speed"]
	var dir := Vector3(-sin(yaw), 0, -cos(yaw))
	# (0.6 m ahead: the first place the headings above are tried at. It was half a meter, and
	# where the floor rose steeply between the two the manta took "straight on" for free and
	# stood still before it, for two minutes at a time.)
	var q := flat + dir * 0.6
	# (hard rule. While it is turning out of a corner it may only move where the water does not
	# get shallower)
	var here := -_ground(pos.x, pos.z)
	var ahead := -_ground(q.x, q.z)
	# (... also when the falling tide has left it in water that is too shallow everywhere:
	# then it makes its way out, toward the deeper water)
	# (nor into a coral. The headings above are tried at these same two places, so that a
	# heading that passes there is never one this rule stops: tested apart, at places a
	# meter from each other, the manta stood still before a coral for most of an hour.
	# It waits here only while it turns, or rises the last of the way over.)
	var wall := maxf(_coral_across(flat + dir * 0.6, dir, MANTA_HALF), _coral_across(flat + dir * 1.6, dir, MANTA_HALF))
	if wall > pos.y - MANTA_UNDER and not jammed:
		d["speed"] = speed * exp(-3.0 * delta)
		d["held"] = float(d.get("held", 0.0)) + delta
		d["held_now"] = float(d.get("held_now", 0.0)) + delta
		d["held_max"] = maxf(float(d.get("held_max", 0.0)), float(d["held_now"]))
	elif ahead >= MANTA_MIN_DEPTH or ahead >= here:
		d["held_now"] = 0.0
		pos.x += dir.x * speed * delta
		pos.z += dir.z * speed * delta
	# half-way down, or just under the surface for a while (feeding: the wing tips come out)
	d["up_t"] -= delta
	if d["up_t"] <= 0.0:
		d["up"] = 1.0 - float(d["up"])
		d["up_t"] = _rng.randf_range(20.0, 40.0) if float(d["up"]) > 0.5 else _rng.randf_range(60.0, 130.0)
	var g := _ground(pos.x, pos.z)
	var surface := wave_height(pos.x, pos.z)
	var cruise_y := maxf(g * 0.45, g + 1.2 * MANTA_SCALE * 0.5)
	var want_y := lerpf(cruise_y, surface - 0.58, float(d["up"]))
	# over the corals on its way, with room for the wings' down-stroke
	var over := _coral_ramp(pos, dir, MANTA_HALF, 2.5, 9.0, 0.2)
	if over > -90.0:
		want_y = maxf(want_y, over + MANTA_UNDER + 0.35)
	# (over a coral it may come a little nearer the surface than otherwise: the wing tips out)
	want_y = clampf(want_y, g + 1.0, surface - (0.4 if over + MANTA_UNDER + 0.35 > surface - 0.55 else 0.55))
	# (under the anchored boat, and coming to it: below its keel, wings and all)
	if _boat(pos.x, pos.z, MANTA_HALF + 0.5) or _boat(pos.x + dir.x * 3.0, pos.z + dir.z * 3.0, MANTA_HALF + 0.5):
		want_y = maxf(minf(want_y, surface - 1.5), g + 1.0)
	var old_y := pos.y
	pos.y += clampf((want_y - pos.y) * 0.6, -0.3, 0.3) * delta
	d["pos"] = pos
	var climb := (pos.y - old_y) / maxf(delta, 0.001)
	d["pitch"] = lerpf(d["pitch"], clampf(atan2(climb, maxf(speed, 0.4)), -0.3, 0.3), 1.0 - exp(-1.5 * delta))
	d["bank"] = lerpf(d["bank"], clampf(-float(d["turn"]) * 1.3, -0.45, 0.45), 1.0 - exp(-1.5 * delta))
	d["phase"] += delta * TAU * 0.27 * (0.6 + 0.4 * speed / 1.15) * lerpf(0.35, 1.0, drive)
	_place_manta()


func _place_manta() -> void:
	var d := manta
	var drive: float = d["drive"]
	var ph: float = d["phase"]
	# the body rises on every down-stroke
	var heave := -sin(ph - 0.5) * 0.09 * drive * MANTA_SCALE * 0.5
	var b := Basis(Vector3.UP, d["yaw"]) * Basis(Vector3.RIGHT, float(d["pitch"]) + cos(ph - 0.5) * 0.035 * drive) * Basis(Vector3.FORWARD, d["bank"])
	_manta.global_transform = Transform3D(b.scaled(Vector3.ONE * MANTA_SCALE), _up(d["pos"]) + Vector3(0, heave, 0))
	_manta.set_instance_shader_parameter("phase", ph)
	_manta.set_instance_shader_parameter("amp", lerpf(0.22, 1.0, drive))
	_manta.set_instance_shader_parameter("bend", clampf(-float(d["turn"]) * 0.5, -0.3, 0.3))


## For the tests: what the manta finds in each of the headings it tries, where it is now:
## [offset, the depths and the corals at 0.6, 1.6 and 2.5 m ahead].
func manta_probe() -> Array:
	var pos: Vector3 = manta["pos"]
	var flat := Vector3(pos.x, 0, pos.z)
	var out: Array = ["under %.2f" % (pos.y - MANTA_UNDER)]
	for a in [0.0, 0.3, -0.3, 0.6, -0.6, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2, PI]:
		var h: float = float(manta["yaw"]) + a
		var dir := Vector3(-sin(h), 0, -cos(h))
		var row := "%.1f:" % a
		for look in [0.6, 1.6, 2.5, 6.0]:
			var q: Vector3 = flat + dir * look
			row += " %.1f/%.1f" % [-_ground(q.x, q.z), _coral_across(q, dir, MANTA_HALF if look < 3.0 else 1.2)]
		out.append(row)
	return out


## For the tests: the manta's life for `seconds` in steps of 50 ms, with the player where they are.
func manta_soak(seconds: float) -> Dictionary:
	var shallowest := 99.0
	var lowest := 99.0
	var nearest := 1e9
	var traveled := 0.0
	var up := 0.0
	var boxed := 0.0
	var pp := _pp()
	var last: Vector3 = manta["pos"]
	var last0 := last
	var still := 0.0
	var still_max := 0.0
	var forced := 0.0
	manta["held"] = 0.0
	manta["held_max"] = 0.0
	for i in int(seconds / 0.05):
		_update_manta(0.05)
		var pos: Vector3 = manta["pos"]
		shallowest = minf(shallowest, -_ground(pos.x, pos.z))
		lowest = minf(lowest, pos.y - _ground(pos.x, pos.z))
		nearest = minf(nearest, Vector2(pos.x - pp.x, pos.z - pp.z).length())
		traveled += pos.distance_to(last)
		last = pos
		up += 0.05 * float(manta["up"])
		if float(manta["stuck"]) > 0.0:
			boxed += 0.05
		if float(manta.get("jam", 0.0)) > 20.0:
			forced += 0.05
		still = still + 0.05 if pos.distance_to(last0) < 0.004 else 0.0
		if still > 30.0 and not manta.has("stall"):
			manta["stall"] = [manta["yaw"], manta["stuck"], manta.get("jam", 0.0), pos, manta_probe()]     # (the first long standstill: what it found there)
		last0 = pos
		still_max = maxf(still_max, still)
		if is_nan(pos.x) or is_nan(pos.y):
			return {"nan at": i}
	return {"shallowest water": shallowest, "least height above the floor": lowest, "nearest to the player": nearest,
		"meters traveled": traveled, "seconds under the surface": up, "seconds boxed in": boxed,
		"seconds held up by a coral": manta.get("held", 0.0), "longest hold-up": manta.get("held_max", 0.0),
		"longest time without moving": still_max, "seconds forced through": forced, "at": manta["pos"]}


func _process(delta: float) -> void:
	_update_shark(delta)
	_update_rays(delta)
	_update_pups(delta)
	_update_manta(delta)


## For the tests: how much water each young reef shark has over the ground it is on now.
func pup_depths() -> Array:
	var out: Array = []
	for d: Dictionary in _pups:
		var pos: Vector3 = d["pos"]
		out.append(snappedf(-_ground(pos.x, pos.z), 0.01))
	return out
