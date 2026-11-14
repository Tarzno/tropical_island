extends Node3D
## A hawksbill turtle comes ashore to nest, by day, as they do in the Seychelles (elsewhere
## turtles nest at night). She hauls herself out of the water and up the beach with the
## alternating gait of her kind, leaving the track of a small tractor; digs a body pit with her
## front flippers and an egg chamber with the hind ones; lays; covers and disguises the nest,
## flinging sand; and goes back to the sea by another way, so that the two tracks make a U
## with the nest at its top. Now and then an older nest hatches: forty-odd hatchlings boil out
## of the sand and run for the water.
##
## Someone who comes within three meters while she is still crawling up or digging the body
## pit turns her back (a "false crawl": she returns to the sea without laying). Once she digs
## the egg chamber and lays, nothing disturbs her. The hatchlings take no notice of anybody.
## One fresh track with its nest (this morning's) and one old nest are on the start beach
## from the beginning. Only old nests hatch: the eggs need two months. The node is created by island_life.gd.

const SeaModels := preload("res://scripts/sea_models.gd")
const A := "res://assets/audio/"
const TURTLE_SCALE := 0.84            # carapace 84 cm
const STRIDE := 0.5                   # meters per cycle of the four flippers
const TRACK_WIDTH := 0.98
const TRACK_LIFE := 1500.0            # seconds a track stays in dry sand
const WET_LIFE := 22.0                # ... and where the swash reaches
const TRACK_POOL := 200
const HATCHLINGS := 44

const HATCHLING_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// A turtle hatchling. UV.x = 1 on the flippers, UV.y = which pair swings together (+1 / -1);
// INSTANCE_CUSTOM.x = its own phase, .y = how hard it is paddling (0 still .. 1).
void vertex() {
	if (UV.x > 0.5) {
		float s = sin(TIME * 17.0 + INSTANCE_CUSTOM.x) * UV.y * INSTANCE_CUSTOM.y;
		float reach = abs(VERTEX.x) * 0.9;
		VERTEX.z += s * reach;
		VERTEX.y += max(-s * UV.y, 0.0) * reach * 0.25;
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.45;
	SPECULAR = 0.3;
}"""

var _ls: Node
var _player: Node3D
var _sealife: Node
var _rng := RandomNumberGenerator.new()
var _time := 0.0
## tests set this to run through a nesting quickly
var time_scale := 1.0

# tracks and nests
var _track_alb: ImageTexture
var _track_nor: ImageTexture
var _pit_alb: ImageTexture
var _pit_nor: ImageTexture
var _decals: Array[Decal] = []
var _born: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _next_decal := 0
var nests: Array = []                 # {"pos": Vector3, "decal": Decal, "laid": time (-1e6: before the game), "eggs": bool}

# the nesting turtle
var turtle: Node3D
var state := "away"
var st := {}                          # what the current visit carries (path, place on it, ...)
var _next_visit := 0.0
var _sand: Array[CPUParticles3D] = []
var _sand_i := 0
var _voice: AudioStreamPlayer3D
var _steps: Array[AudioStream] = []
var _flings: Array[AudioStream] = []      # sand thrown with a flipper
var _breaths: Array[AudioStream] = []     # her heavy breath on land
var _breath_voice: AudioStreamPlayer3D
var _breath_t := 6.0
var breaths := 0                          # (for the tests)
var visits := 0
var false_crawls := 0

# hatchlings
var _hatch_mm: MultiMesh
var _hatch_node: MultiMeshInstance3D
var hatch: Array = []
var _next_hatch := 0.0
var hatchings := 0
var reached_sea := 0


func setup(ls: Node, player: Node3D) -> void:
	_ls = ls
	_player = player
	_sealife = get_node_or_null("../../SeaLife")
	_rng.randomize()
	_make_textures()
	for i in TRACK_POOL:
		var d := Decal.new()
		d.size = Vector3(TRACK_WIDTH, 0.5, STRIDE * 1.06)
		d.texture_albedo = _track_alb
		d.texture_normal = _track_nor
		d.albedo_mix = 1.0
		d.normal_fade = 0.3
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 55.0
		d.distance_fade_length = 15.0
		d.visible = false
		add_child(d)
		_decals.append(d)
		_born.append(-1e9)
		_life.append(TRACK_LIFE)
	turtle = SeaModels.turtle_node(false)
	turtle.name = "NestingTurtle"
	turtle.visible = false
	add_child(turtle)
	for c in turtle.get_children():
		(c as MeshInstance3D).extra_cull_margin = 0.6
		(c as MeshInstance3D).layers = 2       # (the track's decals do not stain her)
	_setup_sand()
	for i in 10:
		var path := A + "step_sand_%d.wav" % i
		if ResourceLoader.exists(path):
			_steps.append(load(path))
	for i in 6:
		for pair: Array in [["sand_fling_%d.wav", _flings], ["turtle_breath_%d.wav", _breaths]]:
			var fp: String = "res://assets/audio/" + str(pair[0]) % i
			if ResourceLoader.exists(fp):
				(pair[1] as Array).append(load(fp))
	_breath_voice = AudioStreamPlayer3D.new()
	_breath_voice.bus = "Ambient"
	_breath_voice.unit_size = 5.0
	_breath_voice.max_distance = 35.0
	_breath_voice.volume_db = -5.0
	add_child(_breath_voice)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "Ambient"
	_voice.unit_size = 4.0
	_voice.max_distance = 30.0
	_voice.volume_db = -10.0
	add_child(_voice)
	_setup_hatchlings()
	_next_visit = _rng.randf_range(100.0, 170.0)
	_next_hatch = _rng.randf_range(330.0, 520.0)


func _physics_process(_delta: float) -> void:
	# (the ray casts need the collision shapes: they are there after a few physics frames)
	if _ls == null or Engine.get_physics_frames() < 24:
		return
	set_physics_process(false)
	_find_shrubs()
	# what the beach shows from the start: this morning's track with its nest, and an old nest
	var fresh := _find_site(Vector2(-2.0, 66.0), 0.0, 16.0)
	if fresh.is_empty():
		fresh = _find_site(Vector2(-2.0, 30.0), 0.0, 60.0)
	if not fresh.is_empty():
		var up: PackedVector3Array = fresh["path"]
		_lay_track(up, false)
		var down := _return_path(fresh["nest"], _dir_at(up, _length(up)), 1.0 if _rng.randf() < 0.5 else -1.0)
		if not down.is_empty():
			_lay_track(down, false)
		_add_nest(fresh["nest"], 1.0, 0.0)
	var old := _find_site(Vector2(-4.0, -18.0), 0.0, 16.0)
	if old.is_empty():
		old = _find_site(Vector2(-2.0, 30.0), 0.0, 60.0)
	if not old.is_empty():
		_add_nest(old["nest"], 0.45, -1e6)


## The shrubs, screwpines and mangroves that stand on or beside the sand, as discs: [center,
## radius]. Their leaves reach further than anything a ray could hit, and a turtle that crawls
## in under them is not seen again (she did, in the first tests).
var _shrubs: Array = []

func _find_shrubs() -> void:
	var seen := {}
	for group in ["BushClusters", "Vacoas", "Mangroves"]:
		var parent := _ls.get_node_or_null(group)
		if parent == null:
			continue
		for mi in parent.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var ab := m.global_transform * m.get_aabb()
			var c := Vector2(ab.position.x + ab.size.x * 0.5, ab.position.z + ab.size.z * 0.5)
			var g := _ground(c.x, c.y)
			if g > 2.6 or g < -0.6 or ab.size.x > 12.0 or ab.size.z > 12.0:
				continue
			var key := Vector2i(roundi(c.x * 2.0), roundi(c.y * 2.0))
			var r := maxf(ab.size.x, ab.size.z) * 0.5
			if not seen.has(key) or float(seen[key][1]) < r:
				seen[key] = [c, r]
	_shrubs = seen.values()
	# (young palms: their fronds sweep the sand)
	for t: Dictionary in _ls.palm_trunks:
		var pts: PackedVector3Array = t["pts"]
		if pts[pts.size() - 1].y - pts[0].y < 3.5 and _ground(pts[0].x, pts[0].z) < 2.6:
			_shrubs.append([Vector2(pts[0].x, pts[0].z), 2.4])


func _night() -> float:
	var dc := get_node_or_null("../../DayCycle")
	return dc.night if dc else 0.0


func _ground(x: float, z: float) -> float:
	return float(_ls.ground(x, z))


## The height of the ground above the sea as it stands now (the tide moves the waterline).
func _h(x: float, z: float) -> float:
	return float(_ls.ground(x, z)) - float(_ls.sea)


func _normal(x: float, z: float) -> Vector3:
	var e := 0.35
	return Vector3(_ground(x - e, z) - _ground(x + e, z), 2.0 * e, _ground(x, z - e) - _ground(x, z + e)).normalized()


## Down the beach at p (unit vector, flat), or zero where the sand is level.
func _downhill(x: float, z: float) -> Vector3:
	var e := 1.0
	var g := Vector3(_ground(x - e, z) - _ground(x + e, z), 0, _ground(x, z - e) - _ground(x, z + e))
	return g.normalized() if g.length() > 0.004 else Vector3.ZERO


## Can a turtle crawl over p? Loose sand (or the shallows), no rock, no trunk or boulder near.
func _open(p: Vector3) -> bool:
	# (the turtle does not plow through the sooty terns' colony)
	var birds := get_node_or_null("../ShoreBirds")
	if birds and birds.has_method("in_sooty_patch") and birds.in_sooty_patch(p, 3.0):
		return false
	var q := Vector2(p.x, p.z)
	var g := _h(p.x, p.z)
	if g > 0.12 and (not _ls.sandy(q) or _ls.rocky(q, 0.9)):
		return false
	if g <= 0.12 and _ls.rocky(q, 0.6):
		return false
	for b: Array in _ls.boulder_spots:
		var c: Vector3 = b[0]
		if Vector2(c.x, c.z).distance_to(q) < float(b[1]) * 0.75 + 0.9:
			return false
	for m: Vector2 in _ls.mangrove_spots:
		if m.distance_to(q) < 3.2:
			return false
	for t: Dictionary in _ls.palm_trunks:
		var base: Vector3 = t["pts"][0]
		if Vector2(base.x, base.z).distance_to(q) < 1.1:
			return false
	for v in _ls.vacoa_spots:
		var vp := Vector2((v as Vector3).x, (v as Vector3).z) if v is Vector3 else (v as Vector2)
		if vp.distance_to(q) < 2.2:
			return false
	for sh: Array in _shrubs:
		if (sh[0] as Vector2).distance_to(q) < float(sh[1]) + 0.75:
			return false
	# rocks, shrubs, the treeline's bushes, driftwood: whatever has a body here or within her
	# width of here (they are not in any list: ray casts find them). On the sand and in the
	# water alike: until 2026-11-12 only above the waterline, and from seven meters up, so
	# that she crawled through rocks in the shallows and through boulders taller than that.
	if _rock_at(p, 0.75):
		return false
	return true


## Does anything solid stand at p or within r of it: a rock, a trunk, driftwood (whatever has
## a body: the ground itself does not count)? Asked from high above, because a ray that
## starts inside a big boulder goes out through its far side and finds nothing.
func _rock_at(p: Vector3, r: float) -> bool:
	var space := get_world_3d().direct_space_state
	for k in 7:
		var o := Vector3.ZERO if k == 0 else Vector3(cos(TAU * k / 6.0), 0, sin(TAU * k / 6.0)) * r
		var gg := _ground(p.x + o.x, p.z + o.z)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x + o.x, gg + 40.0, p.z + o.z), Vector3(p.x + o.x, gg - 0.5, p.z + o.z))
		ray.collision_mask = 1
		if _player is CollisionObject3D:
			ray.exclude = [(_player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and (hit["position"] as Vector3).y > gg + 0.14:
			return true
	return false


## Something solid right at p (for a hatchling: a thing as high as itself is in its way)?
func _stone_at(p: Vector3, afloat := -99.0) -> bool:
	var gg := _ground(p.x, p.z)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, gg + 40.0, p.z), Vector3(p.x, gg - 0.5, p.z))
	ray.collision_mask = 1
	if _player is CollisionObject3D:
		ray.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	# (`afloat`: the height it swims at: a rock that lies deeper is not in its way)
	return not hit.is_empty() and (hit["position"] as Vector3).y > maxf(gg + 0.05, afloat - 0.02)


## (for the tests) with `hatch_audit` on, the hatchlings' seconds inside something solid
var hatch_audit := false
var hatch_avoid := true
var hatch_in_stone := 0.0


## For the tests: hatches all around the island, one after the other (a nest every `step`
## meters of open sand), each run to its end in steps of 50 ms: did all 44 reach the sea,
## and how long were hatchlings inside something solid? `avoid`: false is how it was (they
## ran straight down the beach).
func hatch_test(step := 14.0, avoid := true) -> Dictionary:
	hatch_audit = true
	hatch_avoid = avoid
	hatch_in_stone = 0.0
	var runs := 0
	var short: Array = []
	var total := 0.0
	var x := -230.0
	while x <= 60.0:
		var z := -250.0
		while z <= 250.0:
			var g := _ground(x, z)
			if g > 0.42 and g < 1.15 and _ls.sandy(Vector2(x, z)):
				hatch.clear()
				var before := reached_sea
				if hatch_now(Vector2(x, z)):
					runs += 1
					var t := 0.0
					while not hatch.is_empty() and t < 400.0:
						_time += 0.05
						_update_hatchlings(0.05)
						t += 0.05
					total += t
					if reached_sea - before < HATCHLINGS:
						short.append([Vector2(x, z), reached_sea - before])
					hatch.clear()
			z += step
		x += step
	hatch_audit = false
	hatch_avoid = true
	return {"hatches": runs, "hatchling-seconds inside something solid": snappedf(hatch_in_stone, 0.1), "hatches where not all reached the sea": short.size(),
		"which": short.slice(0, 8), "seconds a hatch takes (mean)": snappedf(total / maxf(runs, 1), 1.0)}


## Nothing solid anywhere on the way as it will be crawled (smoothed: asked every quarter
## meter, her own width wide)?
func _way_clear(w: PackedVector3Array) -> bool:
	var l := _length(w)
	var sd := 0.0
	while sd <= l:
		if _rock_at(_at(w, sd), 0.6):
			return false
		sd += 0.25
	return true


## For the tests: nest sites all around the island (one sought near every stretch of open
## sand, `step` meters apart), the way up to each and the way back down, and whether any
## of them leads through something solid (asked every quarter meter, her own width wide).
func path_test(step := 8.0) -> Dictionary:
	var sites := 0
	var bad: Array = []
	var worst := {}
	var x := -230.0
	while x <= 60.0:
		var z := -250.0
		while z <= 250.0:
			var g := _ground(x, z)
			if g > 0.42 and g < 1.15 and _ls.sandy(Vector2(x, z)):
				var site := _find_site(Vector2(x, z), 0.0, step * 0.6)
				if not site.is_empty():
					sites += 1
					var up: PackedVector3Array = site["path"]
					var ways: Array = [up]
					var top := up[up.size() - 1]
					var fwd := _dir_at(up, _length(up))
					for sgn: float in [1.0, -1.0]:
						var back := _return_path(top, fwd, sgn)
						if not back.is_empty():
							ways.append(back)
					for w: PackedVector3Array in ways:
						var l := _length(w)
						var sd := 0.0
						while sd <= l:
							var q := _at(w, sd)
							if _rock_at(q, 0.6):
								var key := Vector2(snappedf(q.x, 2.0), snappedf(q.z, 2.0))
								if not worst.has(key):
									worst[key] = true
									bad.append([Vector3(q.x, _ground(q.x, q.z), q.z).snappedf(0.1), "ground %.2f over the sea" % _h(q.x, q.z), "way %d" % ways.find(w)])
							sd += 0.25
			z += step
		x += step
	return {"sites": sites, "places where a way leads through something solid": bad.size(), "where": bad.slice(0, 14)}


## Is there nothing but loose sand (or sea) within r of p? The treeline's foliage hangs out
## over the top of the beach and has no body a ray could hit: the only way to stay out from
## under it is to keep a distance from where the sand ends.
func _all_sand(p: Vector3, r: float) -> bool:
	for k in 10:
		var q := Vector2(p.x, p.z) + Vector2.from_angle(TAU * k / 10.0) * r
		if _h(q.x, q.y) > 0.12 and not _ls.sandy(q):
			return false
	return true


## From `from` straight down the beach into the sea, in half-meter steps, as far as the water
## is 1.1 m deep. Empty if something is in the way or the beach is not a simple slope.
func _walk_down(from: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array([from])
	var p := from
	var dir := _downhill(p.x, p.z)
	if dir == Vector3.ZERO:
		return PackedVector3Array()
	for i in 90:
		var d := _downhill(p.x, p.z)
		if d != Vector3.ZERO:
			dir = dir.slerp(d, 0.35).normalized()
		p += dir * 0.5
		var g := _ground(p.x, p.z)
		if g > _ground(pts[pts.size() - 1].x, pts[pts.size() - 1].z) + 0.06 or not _open(p) or not _all_sand(p, 2.2):
			return PackedVector3Array()
		pts.append(Vector3(p.x, 0, p.z))
		if _h(p.x, p.z) < -1.1:
			return pts
	return PackedVector3Array()


func _smooth(r: PackedVector3Array) -> PackedVector3Array:
	for it in 2:
		if r.size() < 3:
			return r
		var o := PackedVector3Array([r[0]])
		for i in r.size() - 1:
			o.append(r[i].lerp(r[i + 1], 0.25))
			o.append(r[i].lerp(r[i + 1], 0.75))
		o.append(r[r.size() - 1])
		r = o
	return r


func _length(r: PackedVector3Array) -> float:
	var l := 0.0
	for i in r.size() - 1:
		l += r[i].distance_to(r[i + 1])
	return l


func _at(r: PackedVector3Array, s: float) -> Vector3:
	var acc := 0.0
	for i in r.size() - 1:
		var seg := r[i].distance_to(r[i + 1])
		if acc + seg >= s:
			return r[i].lerp(r[i + 1], (s - acc) / maxf(seg, 0.0001))
		acc += seg
	return r[r.size() - 1]


func _dir_at(r: PackedVector3Array, s: float) -> Vector3:
	var l := _length(r)
	var a := _at(r, clampf(s - 0.25, 0.0, l))
	var b := _at(r, clampf(s + 0.25, 0.0, l))
	return (b - a).normalized() if a.distance_to(b) > 0.001 else Vector3.FORWARD


## A place to nest within rmin..rmax of `around`: the top of the open sand, six meters or more
## from the water, with a clear way straight up to it from the sea.
## {"nest": Vector3, "path": from the sea up to the nest}, or {} if there is none.
func _find_site(around: Vector2, rmin: float, rmax: float) -> Dictionary:
	for attempt in 140:
		var p2 := around + Vector2.from_angle(_rng.randf() * TAU) * lerpf(rmin, rmax, sqrt(_rng.randf()))
		var g := _ground(p2.x, p2.y)
		if g < 0.42 or g > 1.15:
			continue
		var top := Vector3(p2.x, 0, p2.y)
		if not _open(top) or not _all_sand(top, 4.2) or not _all_sand(top, 2.5):
			continue
		var apart := true
		for n: Dictionary in nests:
			if Vector2((n["pos"] as Vector3).x, (n["pos"] as Vector3).z).distance_to(p2) < 7.0:
				apart = false
		if not apart:
			continue
		var down := _walk_down(top)
		if down.is_empty():
			continue
		# how far is it to the waterline?
		var dry := 0.0
		for i in down.size() - 1:
			if _h(down[i + 1].x, down[i + 1].z) > 0.0:
				dry += 0.5
		if dry < 5.0 or dry > 26.0:
			continue
		down.reverse()
		var way := _smooth(down)
		if not _way_clear(way):
			continue
		return {"nest": Vector3(p2.x, g, p2.y), "path": way}
	return {}


## The way back to the sea from `from`, where she faces `fwd`: she turns around in a tight
## half circle to the side `sgn` and goes down the beach beside the way she came. Empty if
## that side is blocked.
func _return_path(from: Vector3, fwd: Vector3, sgn: float) -> PackedVector3Array:
	var right := Vector3(-fwd.z, 0, fwd.x) * sgn
	var radius := 0.95
	var center := Vector3(from.x, 0, from.z) + right * radius
	var pts := PackedVector3Array()
	for k in 9:
		var a := PI * k / 8.0
		var q := center - right * (cos(a) * radius) + fwd * (sin(a) * radius)
		if not _open(q) or not _all_sand(q, 2.0):
			return PackedVector3Array()
		pts.append(q)
	var down := _walk_down(pts[pts.size() - 1])
	if down.is_empty():
		return PackedVector3Array()
	pts.append_array(down.slice(1))
	var way := _smooth(pts)
	return way if _way_clear(way) else PackedVector3Array()


# ------------------------------------------------------------------ tracks and nests
## The track, one stride of it (it repeats along the way): the smooth drag of the plastron down
## the middle, the scrapes of the front flippers alternately left and right outside it with
## the sand they pushed back, the smaller marks of the hind ones. And the nest: a churned
## hollow with thrown sand around it.
func _make_textures() -> void:
	var w := 96
	var h := 56
	var hm := PackedFloat32Array()
	hm.resize(w * h)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.09
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := (y + 0.5) / h
			var d := 0.0
			# plastron
			var mid := absf(u - 0.5)
			d -= 0.5 * (1.0 - smoothstep(0.14, 0.21, mid)) * (0.86 + 0.07 * sin(u * 120.0 + sin(v * TAU) * 2.0) + 0.14 * noise.get_noise_2d(x * 9.0, y * 2.0))
			d += 0.3 * (1.0 - smoothstep(0.0, 0.04, absf(mid - 0.225)))        # (its edges: little ridges)
			# flippers: [u, v, half-length across, half-width along, slant, depth]: long slanting
			# scrapes that run out from the edge of the plastron's drag
			for m: Array in [[0.19, 0.27, 0.19, 0.12, 0.75, 1.0], [0.81, 0.77, 0.19, 0.12, -0.75, 1.0], [0.31, 0.8, 0.09, 0.1, 0.4, 0.6], [0.69, 0.3, 0.09, 0.1, -0.4, 0.6]]:
				for wrap: float in [-1.0, 0.0, 1.0]:
					var du := u - float(m[0])
					var dv: float = v - float(m[1]) + wrap
					var a := du / float(m[2])
					var b: float = (dv - du * float(m[4])) / float(m[3])
					var r := sqrt(a * a + b * b)
					d -= float(m[5]) * (1.0 - smoothstep(0.55, 1.0, r))
					# the sand it pushed back lies behind the scrape (v grows backward)
					var rb := sqrt(a * a + pow(b - 1.15, 2.0) * 2.5)
					d += float(m[5]) * 0.8 * (1.0 - smoothstep(0.3, 1.0, rb))
			d += noise.get_noise_2d(x * 3.0, y * 3.0) * 0.06 * (1.0 - smoothstep(0.42, 0.5, mid))
			# (nothing at the outer edges: the decal must end without a seam)
			d *= 1.0 - smoothstep(0.42, 0.5, mid)
			hm[y * w + x] = d
	var tex := _height_to_textures(hm, w, h, true)
	_track_alb = tex[0]
	_track_nor = tex[1]
	w = 96
	h = 96
	hm = PackedFloat32Array()
	hm.resize(w * h)
	noise.frequency = 0.05
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
			var r := p.length() * (1.0 + 0.2 * noise.get_noise_2d(x * 2.0 + 40.0, y * 2.0))
			var lump := 0.6 * noise.get_noise_2d(x * 2.3, y * 2.9) + 0.4 * noise.get_noise_2d(x * 6.1 + 9.0, y * 5.3)
			var d := -0.9 * (1.0 - smoothstep(0.15, 0.5, r)) + 0.8 * (1.0 - smoothstep(0.0, 0.2, absf(r - 0.62))) * (0.6 + 0.9 * lump)
			d += 0.5 * lump * (1.0 - smoothstep(0.4, 0.9, r)) + 0.25 * noise.get_noise_2d(x * 11.0, y * 11.0) * (1.0 - smoothstep(0.5, 0.9, r))
			d *= 1.0 - smoothstep(0.8, 0.98, r)
			hm[y * w + x] = d
	tex = _height_to_textures(hm, w, h, false, 0.64)
	_pit_alb = tex[0]
	_pit_nor = tex[1]


func _height_to_textures(hm: PackedFloat32Array, w: int, h: int, wrap_v: bool, dark := 0.42) -> Array:
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var nor := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var hc := hm[y * w + x]
			var y0 := posmod(y - 1, h) if wrap_v else maxi(y - 1, 0)
			var y1 := posmod(y + 1, h) if wrap_v else mini(y + 1, h - 1)
			var hx := hm[y * w + mini(x + 1, w - 1)] - hm[y * w + maxi(x - 1, 0)]
			var hy := hm[y1 * w + x] - hm[y0 * w + x]
			var n := Vector3(-hx * 5.0, -hy * 5.0, 1.0).normalized()
			var a := clampf(absf(hc) * 2.4, 0.0, 1.0)
			# where the sand was scraped away it is darker and damper; thrown sand is a little paler
			var shade := lerpf(0.9, dark, clampf(-hc * 1.6, 0.0, 1.0)) if hc < 0.0 else 1.08
			alb.set_pixel(x, y, Color(shade * 0.88, shade * 0.83, shade * 0.74, a * (0.88 if hc < 0.0 else 0.4)))
			nor.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, a))
	alb.generate_mipmaps()
	nor.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nor)]


## One stride of track at p, going along dir.
func _stamp(p: Vector3, dir: Vector3) -> void:
	var g := _ground(p.x, p.z)
	var h := g - float(_ls.sea)
	if h < -0.04:
		return
	var n := _normal(p.x, p.z)
	var f := (dir - n * dir.dot(n)).normalized()
	var right := f.cross(n).normalized()
	var d := _decals[_next_decal]
	_born[_next_decal] = _time
	_life[_next_decal] = WET_LIFE if h < 0.26 else TRACK_LIFE
	_next_decal = (_next_decal + 1) % TRACK_POOL
	# (the texture's v runs along the decal's z: v = 0 is the front)
	d.global_transform = Transform3D(Basis(right, n, -f), Vector3(p.x, g + 0.03, p.z))
	d.modulate = Color(1, 1, 1, 1)
	d.visible = true


## A whole track along a path at once (what was made before the game began). `wet`: also where
## the swash reaches.
func _lay_track(path: PackedVector3Array, wet: bool) -> void:
	var l := _length(path)
	var s := STRIDE * 0.5
	while s < l:
		var p := _at(path, s)
		if wet or _h(p.x, p.z) >= 0.26:
			_stamp(p, _dir_at(path, s))
		s += STRIDE


func _add_nest(pos: Vector3, strength: float, laid: float) -> Dictionary:
	var d := Decal.new()
	d.size = Vector3(2.1, 0.6, 2.1)
	d.texture_albedo = _pit_alb
	d.texture_normal = _pit_nor
	d.albedo_mix = 1.0
	d.normal_fade = 0.3
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 55.0
	d.distance_fade_length = 15.0
	d.modulate = Color(1, 1, 1, strength)
	add_child(d)
	var g := _ground(pos.x, pos.z)
	d.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(pos.x, g + 0.03, pos.z))
	var n := {"pos": Vector3(pos.x, g, pos.z), "decal": d, "laid": laid, "eggs": true}
	nests.append(n)
	# (no more than four nests: the oldest goes)
	if nests.size() > 4:
		(nests[0]["decal"] as Decal).queue_free()
		nests.remove_at(0)
	return n


# ------------------------------------------------------------------ the nesting turtle
func _setup_sand() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.011, 0.011)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.9, 0.85, 0.74)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.roughness = 1.0
	quad.material = sm
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.3))
	for i in 4:
		var sp := CPUParticles3D.new()
		sp.emitting = false
		sp.one_shot = true
		sp.amount = 220
		sp.lifetime = 0.8
		sp.explosiveness = 0.85
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 0.11
		sp.spread = 30.0
		sp.initial_velocity_min = 1.2
		sp.initial_velocity_max = 2.8
		sp.gravity = Vector3(0, -9.8, 0)
		sp.scale_amount_min = 0.5
		sp.scale_amount_max = 1.5
		sp.scale_amount_curve = shrink
		sp.mesh = quad
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)
		_sand.append(sp)


## A flipperful of sand thrown from `at` in direction `dir`.
func _fling(at: Vector3, dir: Vector3, power: float) -> void:
	var sp := _sand[_sand_i]
	_sand_i = (_sand_i + 1) % _sand.size()
	sp.global_position = at
	sp.direction = dir.normalized()
	sp.initial_velocity_min = 1.0 * power
	sp.initial_velocity_max = 2.6 * power
	sp.restart()
	sp.emitting = true
	if not _flings.is_empty() and _player and at.distance_to(_player.global_position) < 30.0:
		_voice.global_position = at
		_voice.stream = _flings[_rng.randi() % _flings.size()]
		_voice.pitch_scale = _rng.randf_range(0.9, 1.1)
		_voice.play()
	elif not _steps.is_empty() and _player and at.distance_to(_player.global_position) < 30.0:
		_voice.global_position = at
		_voice.stream = _steps[_rng.randi() % _steps.size()]
		_voice.pitch_scale = _rng.randf_range(0.7, 0.9)
		_voice.play()


## A visit begins: she comes in from the sea toward a place near `around` (near the player
## if none is given). False if there is no beach for it there.
func summon(around := Vector2(1e9, 0)) -> bool:
	if state != "away" or _player == null:
		return false
	var pp := _player.global_position
	var given := around.x < 1e8
	var site := _find_site(around if given else Vector2(pp.x, pp.z), 0.0 if given else 16.0, 14.0 if given else 46.0)
	if site.is_empty():
		return false
	var path: PackedVector3Array = site["path"]
	# (not where someone is standing in her way)
	if not given:
		for q in path:
			if Vector2(q.x - pp.x, q.z - pp.z).length() < 9.0:
				return false
	st = {"path": path, "len": _length(path), "s": 0.0, "nest": site["nest"], "phase": 0.0, "stamped": 0.0, "t": 0.0,
		"yaw": 0.0, "sink": 0.0, "spin": 0.0, "creep": 0.0, "going_up": true, "laid": false, "strokes": 0, "nest_d": {}}
	var dir := _dir_at(path, 0.0)
	st["yaw"] = atan2(-dir.x, -dir.z)
	state = "crawl"
	turtle.visible = true
	visits += 1
	_pose_crawl(0.0)
	return true


func _turn_back() -> void:
	var path: PackedVector3Array = st["path"]
	var s: float = st["s"]
	var here := _at(path, s)
	var fwd := Vector3(-sin(float(st["yaw"])), 0, -cos(float(st["yaw"])))
	var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
	var back := _return_path(here, fwd, sgn)
	if back.is_empty():
		back = _return_path(here, fwd, -sgn)
	if back.is_empty():
		# (no room to either side: back down the way she came)
		back = PackedVector3Array()
		var ss := s
		while ss > 0.0:
			back.append(_at(path, ss))
			ss -= 0.5
		back.append(path[0])
	st["path"] = back
	st["len"] = _length(back)
	st["s"] = 0.0
	st["stamped"] = 0.0
	st["going_up"] = false
	st["sink"] = 0.0
	st["spin"] = 0.0
	st["creep"] = 0.0
	state = "crawl"


func _update_turtle(delta: float) -> void:
	if state == "away":
		_next_visit -= delta
		if _next_visit <= 0.0:
			# by day only; if there is no beach near the player now, she tries again soon
			_next_visit = _rng.randf_range(480.0, 840.0) if _night() < 0.4 and summon() else 25.0
		return
	st["t"] += delta
	var pp := _player.global_position if _player else Vector3(1e6, 0, 0)
	var pos := turtle.global_position
	var near := Vector2(pos.x - pp.x, pos.z - pp.z).length() < 3.0 and absf(pp.y - pos.y) < 3.0
	# on land she breathes heavily: a hissing breath out and a gasp in, every quarter minute
	_breath_t -= delta
	if _breath_t <= 0.0 and turtle.visible:
		_breath_t = _rng.randf_range(9.0, 17.0)
		if not _breaths.is_empty() and pos.distance_to(pp) < 35.0 and not _breath_voice.playing:
			_breath_voice.global_position = pos + Vector3(0, 0.25, 0)
			_breath_voice.stream = _breaths[_rng.randi() % _breaths.size()]
			_breath_voice.pitch_scale = _rng.randf_range(0.88, 1.0)
			_breath_voice.play()
			breaths += 1
	match state:
		"crawl":
			var path: PackedVector3Array = st["path"]
			var s: float = st["s"]
			var p := _at(path, s)
			var g := _h(p.x, p.z)
			# she is quick while the water carries her, slow and labored on the sand: every
			# stride two heaves, and after a few of them a rest
			var base := lerpf(0.21, 0.42, smoothstep(-0.25, -0.75, g))
			var ph: float = st["phase"]
			var rest := 0.0 if (g < 0.0 or fmod(s, 3.4) > 0.5) else 0.65
			var v := base * (1.0 + 0.7 * sin(ph * 2.0 - 0.6)) * (1.0 - rest)
			s += v * delta
			st["s"] = s
			st["phase"] = ph + v * delta / STRIDE * TAU
			if s - float(st["stamped"]) >= STRIDE:
				st["stamped"] = float(st["stamped"]) + STRIDE
				var back := float(st["stamped"]) - STRIDE * 0.5
				_stamp(_at(path, back), _dir_at(path, back))
			if st["going_up"] and near and g > 0.05:
				false_crawls += 1
				_turn_back()
			elif s >= float(st["len"]):
				if st["going_up"]:
					state = "pit"
					st["t"] = 0.0
					st["nest_d"] = _add_nest(st["nest"], 0.0, _time)
					(st["nest_d"] as Dictionary)["eggs"] = false
				else:
					state = "away"
					turtle.visible = false
					return
			_pose_crawl(delta)
		"pit":
			# the body pit: the front flippers throw the dry sand back, one after the other, and
			# she shuffles around a little as she sinks into it
			var t: float = st["t"]
			st["sink"] = 0.07 * smoothstep(0.0, 34.0, t)
			st["spin"] = 0.3 * sin(t * 0.12)
			((st["nest_d"] as Dictionary)["decal"] as Decal).modulate.a = 0.75 * smoothstep(0.0, 34.0, t)
			_pose_dig(t, "front", 1.0)
			if near:
				false_crawls += 1
				_turn_back()
			elif t > 36.0:
				state = "chamber"
				st["t"] = 0.0
		"chamber":
			# the egg chamber: the hind flippers scoop in turn, the sand goes out to the sides
			_pose_dig(st["t"], "hind", 1.0)
			if st["t"] > 34.0:
				state = "lay"
				st["t"] = 0.0
		"lay":
			_pose_dig(st["t"], "still", 0.0)
			if st["t"] > 38.0:
				state = "cover"
				st["t"] = 0.0
				st["laid"] = true
				(st["nest_d"] as Dictionary)["eggs"] = true
				(st["nest_d"] as Dictionary)["laid"] = _time
		"cover":
			# first the hind flippers fill and press the chamber, then the front ones throw
			# sand over everything while she creeps forward: the nest is hidden
			var t: float = st["t"]
			if t < 16.0:
				_pose_dig(t, "hind", 0.5)
			else:
				st["creep"] = 0.7 * smoothstep(16.0, 42.0, t)
				st["sink"] = 0.07 * (1.0 - smoothstep(16.0, 34.0, t))
				_pose_dig(t, "front", 1.5)
			((st["nest_d"] as Dictionary)["decal"] as Decal).modulate.a = lerpf(0.75, 1.0, smoothstep(0.0, 42.0, t))
			if t > 42.0:
				# back to the sea, from where she is now
				var fwd := Vector3(-sin(float(st["yaw"]) + float(st["spin"])), 0, -cos(float(st["yaw"]) + float(st["spin"])))
				var here := turtle.global_position
				st["path"] = PackedVector3Array([Vector3(here.x, 0, here.z), Vector3(here.x, 0, here.z) + fwd * 0.01])
				st["s"] = 0.0
				st["yaw"] = float(st["yaw"]) + float(st["spin"])
				_turn_back()


## Where the turtle's parts go while she crawls along her path.
func _pose_crawl(delta: float) -> void:
	var path: PackedVector3Array = st["path"]
	var s: float = st["s"]
	var p := _at(path, s)
	var dir := _dir_at(path, s)
	var want := atan2(-dir.x, -dir.z)
	st["yaw"] = lerp_angle(float(st["yaw"]), want, 1.0 - exp(-4.0 * delta)) if delta > 0.0 else want
	var ph: float = st["phase"]
	_place_body(p, float(st["yaw"]) + 0.05 * sin(ph), 0.0, 0.012 * sin(ph * 2.0 - 0.6))
	# alternating gait: the right front and left hind flipper together, then the other two.
	# A flipper is planted and pushes back, then lifts and swings forward
	for k in 2:
		var th := ph + PI * k
		var lift := maxf(-sin(th), 0.0)
		var sweep := 0.5 * cos(th) + 0.05
		var flap := -0.34 + 0.3 * lift
		var sg := 1.0 if k == 0 else -1.0
		(turtle.get_node("FlipFR" if k == 0 else "FlipFL") as Node3D).basis = Basis(Vector3.UP, sweep * sg) * Basis(Vector3.BACK, flap * sg) * Basis(Vector3.RIGHT, -0.5 + 0.3 * lift)
		(turtle.get_node("FlipRL" if k == 0 else "FlipRR") as Node3D).basis = Basis(Vector3.UP, (0.28 * cos(th)) * -sg) * Basis(Vector3.BACK, (-0.12 + 0.12 * lift) * -sg)
	(turtle.get_node("Head") as Node3D).basis = Basis(Vector3.RIGHT, 0.2 + 0.06 * sin(ph * 2.0)) * Basis(Vector3.UP, 0.1 * sin(ph))


## ... and at the nest. `what`: "front" (the front flippers throw sand back), "hind" (the hind
## flippers scoop), "still" (laying). `power`: how hard.
func _pose_dig(t: float, what: String, power: float) -> void:
	var nest: Vector3 = st["nest"]
	var yaw: float = float(st["yaw"]) + float(st["spin"])
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var p := nest + fwd * (0.25 + float(st["creep"]))
	var breath := 0.004 * sin(t * 1.4)
	var roll := 0.0
	var fr := Basis(Vector3.UP, 0.1) * Basis(Vector3.BACK, -0.3) * Basis(Vector3.RIGHT, -0.4)
	var fl := Basis(Vector3.UP, -0.1) * Basis(Vector3.BACK, 0.3) * Basis(Vector3.RIGHT, -0.4)
	var rr := Basis(Vector3.UP, -0.1) * Basis(Vector3.BACK, -0.1)
	var rl := Basis(Vector3.UP, 0.1) * Basis(Vector3.BACK, 0.1)
	var head := Basis(Vector3.RIGHT, 0.12)
	if what == "front":
		# one flipper at a time: forward and down, a hard sweep back, the sand flies
		var period := 2.3 / (0.8 + 0.2 * power)
		var n := int(t / period)
		var c := fposmod(t, period) / period
		var sg := 1.0 if n % 2 == 0 else -1.0
		var sweep := lerpf(0.75, -0.7, smoothstep(0.3, 0.52, c)) if c < 0.6 else lerpf(-0.7, 0.75, smoothstep(0.6, 1.0, c))
		var flap := -0.42 if c < 0.55 else -0.42 + 0.5 * sin((c - 0.55) / 0.45 * PI)
		var b := Basis(Vector3.UP, sweep * sg) * Basis(Vector3.BACK, flap * sg) * Basis(Vector3.RIGHT, -0.7)
		if sg > 0.0:
			fr = b
		else:
			fl = b
		roll = -0.05 * sg * sin(c * PI)
		if c > 0.42 and int(st["strokes"]) != n + 1000:
			st["strokes"] = n + 1000
			var at := p + right * (0.5 * sg) + fwd * 0.05 + Vector3(0, 0.1, 0)
			_fling(Vector3(at.x, _ground(at.x, at.z) + 0.1 - float(st["sink"]), at.z), -fwd * 1.0 + right * (0.45 * sg) + Vector3(0, 0.75, 0), power)
		head = Basis(Vector3.RIGHT, 0.2)
	elif what == "hind":
		var period := 2.6
		var n := int(t / period)
		var c := fposmod(t, period) / period
		var sg := 1.0 if n % 2 == 0 else -1.0
		# reach down and in under the tail, curl, lift out to the side, tip it out
		var down := sin(minf(c / 0.5, 1.0) * PI) * 0.55
		var out := smoothstep(0.5, 0.75, c) * (1.0 - smoothstep(0.85, 1.0, c))
		var b := Basis(Vector3.UP, (0.35 * down - 0.5 * out) * -sg) * Basis(Vector3.BACK, (-0.6 * down + 0.25 * out) * sg)
		if sg > 0.0:
			rr = b
		else:
			rl = b
		roll = 0.06 * sg * (down - out)
		if power > 0.9 and c > 0.72 and int(st["strokes"]) != n + 2000:
			st["strokes"] = n + 2000
			var at := p - fwd * 0.42 + right * (0.3 * sg)
			_fling(Vector3(at.x, _ground(at.x, at.z) + 0.06, at.z), right * (0.9 * sg) - fwd * 0.3 + Vector3(0, 0.55, 0), 0.5)
	else:
		# laying: quite still; the head sinks, the hind flippers cover the chamber and twitch
		head = Basis(Vector3.RIGHT, -0.05 + 0.04 * sin(t * 0.5))
		var tw := maxf(sin(t * 1.9), 0.0) * 0.08
		rr = Basis(Vector3.UP, 0.25) * Basis(Vector3.BACK, -0.3 - tw)
		rl = Basis(Vector3.UP, -0.25) * Basis(Vector3.BACK, 0.3 + tw)
	_place_body(Vector3(p.x, 0, p.z), yaw, roll, breath - float(st["sink"]), 0.16 * minf(float(st["sink"]) / 0.07, 1.0))
	(turtle.get_node("FlipFR") as Node3D).basis = fr
	(turtle.get_node("FlipFL") as Node3D).basis = fl
	(turtle.get_node("FlipRR") as Node3D).basis = rr
	(turtle.get_node("FlipRL") as Node3D).basis = rl
	(turtle.get_node("Head") as Node3D).basis = head


## The body on the sand at p: lying on the slope, the plastron on the ground. `tilt`: the hind
## end lower than the front (in the pit).
func _place_body(p: Vector3, yaw: float, roll: float, lift: float, tilt := 0.0) -> void:
	var g := _ground(p.x, p.z)
	var n := _normal(p.x, p.z)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var f := (fwd - n * fwd.dot(n)).normalized()
	var x := f.cross(n).normalized()
	var b := Basis(x, n, -f) * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.FORWARD, roll)
	turtle.global_transform = Transform3D(b.scaled(Vector3.ONE * TURTLE_SCALE), Vector3(p.x, g + (0.085 + lift) * TURTLE_SCALE, p.z))


# ------------------------------------------------------------------ hatchlings
func _setup_hatchlings() -> void:
	var stl := SurfaceTool.new()
	stl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color(0.075, 0.065, 0.055)
	var edge := Color(0.2, 0.17, 0.13)
	# the shell (4.2 cm), the head, and four flippers as flat blades
	for part: Array in [[Vector3(0, 0.006, 0.002), Vector3(0.0155, 0.0075, 0.021)], [Vector3(0, 0.007, -0.025), Vector3(0.0065, 0.006, 0.008)]]:
		var c: Vector3 = part[0]
		var r: Vector3 = part[1]
		for i in 5:
			for j in 8:
				var quad: Array = []
				for k in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var th := PI * float(i + k[0]) / 5.0
					var phi := TAU * float(j + k[1]) / 8.0
					var d := Vector3(sin(th) * cos(phi), cos(th), sin(th) * sin(phi))
					quad.append([c + d * r, d, dark.lerp(edge, smoothstep(0.3, 0.9, sin(th)) * (1.0 - absf(d.y)))])
				for idx in [0, 2, 1, 0, 3, 2]:
					stl.set_color(quad[idx][2])
					stl.set_normal((quad[idx][1] as Vector3 / r).normalized())
					stl.set_uv(Vector2.ZERO)
					stl.add_vertex(quad[idx][0])
	for fl: Array in [[1.0, -0.012, 0.03, 1.0], [-1.0, -0.012, 0.03, -1.0], [1.0, 0.016, 0.016, -1.0], [-1.0, 0.016, 0.016, 1.0]]:
		var sx: float = fl[0]
		var root := Vector3(sx * 0.011, 0.004, fl[1])
		var tip := Vector3(sx * (0.011 + float(fl[2])), 0.002, float(fl[1]) + 0.012)
		var wide := 0.0055
		for tri in [[root + Vector3(0, 0, -wide), tip, root + Vector3(0, 0, wide)], [root + Vector3(0, 0, wide), tip, root + Vector3(0, 0, -wide)]]:
			for v: Vector3 in tri:
				stl.set_color(dark)
				stl.set_normal(Vector3.UP)
				stl.set_uv(Vector2(1.0, fl[3]))
				stl.add_vertex(v)
	_hatch_mm = MultiMesh.new()
	_hatch_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hatch_mm.use_custom_data = true
	_hatch_mm.mesh = stl.commit()
	_hatch_mm.instance_count = HATCHLINGS
	_hatch_mm.visible_instance_count = 0
	var sh := Shader.new()
	sh.code = HATCHLING_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_hatch_node = MultiMeshInstance3D.new()
	_hatch_node.name = "Hatchlings"
	_hatch_node.multimesh = _hatch_mm
	_hatch_node.material_override = mat
	_hatch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hatch_node.custom_aabb = AABB(Vector3(-40, -3, -40), Vector3(80, 6, 80))
	_hatch_node.visible = false
	add_child(_hatch_node)


## A nest hatches: an old one (laid long before the game began; eggs take two months) near
## `around`, or near the player. Old nests show next to nothing on the surface, so if none is
## known near by, there turns out to have been one. False if there is no beach for it there.
func hatch_now(around := Vector2(1e9, 0)) -> bool:
	if not hatch.is_empty() or _player == null:
		return false
	var pp := _player.global_position
	var given := around.x < 1e8
	var from := around if given else Vector2(pp.x, pp.z)
	var best := {}
	var bd := 45.0
	for n: Dictionary in nests:
		var np: Vector3 = n["pos"]
		var dd := Vector2(np.x, np.z).distance_to(from)
		if n["eggs"] and float(n["laid"]) < -1e5 and dd < bd and (given or np.distance_to(pp) > 4.0):
			bd = dd
			best = n
	if best.is_empty():
		var site := _find_site(from, 0.0 if given else 7.0, 14.0 if given else 34.0)
		if site.is_empty():
			return false
		best = _add_nest(site["nest"], 0.35, -1e6)
	best["eggs"] = false
	var nest: Vector3 = best["pos"]
	_hatch_node.global_position = nest
	_hatch_node.visible = true
	_hatch_mm.visible_instance_count = HATCHLINGS
	hatch.clear()
	for i in HATCHLINGS:
		# they come up in bursts, the first few alone
		var wait := _rng.randf_range(0.0, 3.0) if i < 4 else 4.0 + float(i / 9) * _rng.randf_range(2.5, 4.5) + _rng.randf_range(0.0, 2.5)
		var a := _rng.randf() * TAU
		hatch.append({"pos": nest + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.0, 0.14), "wait": wait, "yaw": _rng.randf() * TAU, "speed": _rng.randf_range(0.2, 0.3),
			"go": _rng.randf_range(1.5, 4.0), "pause": 0.0, "wander": _rng.randf() * TAU, "state": "wait", "fade": 1.0, "ph": _rng.randf() * TAU, "size": _rng.randf_range(0.9, 1.1)})
		_hatch_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		_hatch_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	# (the sand over the nest falls in where they came out)
	(best["decal"] as Decal).modulate.a = 0.8
	hatchings += 1
	return true


func _update_hatchlings(delta: float) -> void:
	if hatch.is_empty():
		_next_hatch -= delta
		if _next_hatch <= 0.0 and _player:
			# where someone is near enough to see it; if they are not on a beach now, soon again
			_next_hatch = _rng.randf_range(700.0, 1200.0) if hatch_now() else 30.0
		return
	var origin := _hatch_node.global_position
	var left := 0
	for i in hatch.size():
		var d: Dictionary = hatch[i]
		var state_h: String = d["state"]
		if state_h == "gone":
			continue
		left += 1
		if state_h == "wait":
			d["wait"] -= delta
			if d["wait"] <= 0.0:
				d["state"] = "run"
			continue
		var pos: Vector3 = d["pos"]
		var g := _h(pos.x, pos.z)
		var moving := 1.0
		# to the sea: down the beach, each on its own wavering line, a few seconds' scramble
		# and a moment's rest
		var down := _downhill(pos.x, pos.z)
		var want: float = d["yaw"]
		if down != Vector3.ZERO:
			want = atan2(-down.x, -down.z) + 0.5 * sin(_time * 0.9 + float(d["wander"]))
		d["yaw"] = lerp_angle(float(d["yaw"]), want, 1.0 - exp(-2.5 * delta))
		var speed: float = d["speed"]
		if state_h == "run":
			d["go"] -= delta
			if d["go"] <= 0.0:
				d["pause"] = _rng.randf_range(0.3, 1.1)
				d["go"] = _rng.randf_range(1.5, 4.5)
			if d["pause"] > 0.0:
				d["pause"] -= delta
				speed = 0.0
				moving = 0.0
			if g < -0.02:
				d["state"] = "swim"
				reached_sea += 1
		else:
			# afloat: paddling out, soon out of sight
			speed *= 1.5
			if g < -0.4:
				d["fade"] -= delta / 1.5
				if d["fade"] <= 0.0:
					d["state"] = "gone"
					_hatch_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
					continue
		var fwd := Vector3(-sin(float(d["yaw"])), 0, -cos(float(d["yaw"])))
		# a stone or a root in its way: around it, to the side that is free (its own side
		# first), and on down the beach beyond
		var afloat := pos.y if d["state"] == "swim" else -99.0
		if hatch_avoid and speed > 0.0 and (_stone_at(pos + fwd * 0.14, afloat) or _stone_at(pos + fwd * 0.04, afloat)):
			var side := 1.0 if sin(float(d["wander"])) > 0.0 else -1.0
			var free := false
			for a: float in [0.8, -0.8, 1.5, -1.5, 2.3, -2.3]:
				var f2 := fwd.rotated(Vector3.UP, a * side)
				if not _stone_at(pos + f2 * 0.14, afloat) and not _stone_at(pos + f2 * 0.04, afloat):
					fwd = f2
					d["yaw"] = atan2(-f2.x, -f2.z)
					free = true
					break
			if not free:
				speed = 0.0
				moving = 0.0
		pos += fwd * speed * delta
		if hatch_audit and _stone_at(pos, afloat):
			hatch_in_stone += delta
		g = _ground(pos.x, pos.z)
		var y := g + 0.002
		var n := _normal(pos.x, pos.z)
		if d["state"] == "swim":
			var surface: float = _sealife.surface(pos.x, pos.z) if _sealife else 0.0
			if surface - 0.008 > y:
				y = surface - 0.008
				n = Vector3.UP
		pos.y = y
		d["pos"] = pos
		var f := (fwd - n * fwd.dot(n)).normalized()
		var x := f.cross(n).normalized()
		var sc: float = float(d["size"]) * maxf(float(d["fade"]), 0.0)
		_hatch_mm.set_instance_transform(i, Transform3D(Basis(x, n, -f).scaled(Vector3.ONE * sc), pos - origin))
		_hatch_mm.set_instance_custom_data(i, Color(float(d["ph"]), moving, 0, 0))
	if left == 0:
		hatch.clear()
		_hatch_node.visible = false
		_hatch_mm.visible_instance_count = 0


func _process(delta: float) -> void:
	if _ls == null:
		return
	delta = minf(delta, 0.1) * time_scale
	_time += delta
	_update_turtle(delta)
	_update_hatchlings(delta)
	# tracks fade in the end; where the swash reaches they are gone in seconds
	if Engine.get_process_frames() % 20 == 0:
		for i in TRACK_POOL:
			var d := _decals[i]
			if not d.visible:
				continue
			var age := _time - _born[i]
			# (the rising tide takes a track as the swash does)
			if d.global_position.y - float(_ls.sea) < 0.27 and _life[i] > age + WET_LIFE:
				_life[i] = age + WET_LIFE
			var a := 1.0 - smoothstep(_life[i] * 0.7, _life[i], age)
			if a <= 0.0:
				d.visible = false
			else:
				d.modulate.a = a
