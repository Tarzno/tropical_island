extends Node3D
## The small characters of the reef, each with a home of its own that it never leaves:
##  * anemonefish: a pair and their young in every sea anemone (the Seychelles anemonefish in
##    the carpet anemones, the skunk anemonefish in the magnificent ones). They hover over the
##    disc, waggling, dart to and fro and slip in among the tentacles; with a swimmer overhead
##    the small ones go down into the anemone and the big female comes up a little to look;
##  * garden eels: colonies on bare sand, each eel in its burrow, swaying like a field of
##    question marks, all facing the same way. They sink into the sand as a swimmer comes
##    near, the nearest first, and rise again when it has gone;
##  * morays and day octopuses in holes in lumps of old reef rock, and lionfish that hang by a
##    big coral (further down).
## Nothing here hunts, lunges or bolts: a snorkeler looks down on all of it from the surface.
## The anemones themselves and the places with room for a den are found by seabed.gd while it
## builds the sea floor; this node (created by island_life.gd) takes them over when that is
## done. The models are scripts/reef_models.gd.

const ReefModels := preload("res://scripts/reef_models.gd")
## The lagoon off the start beach, where people snorkel: homes are chosen here first.
const ZONE := Rect2(22, -78, 62, 172)
const FISH_MAX := 420

var _ls: Node
var _player: Node3D
var _seabed: Node
var _sealife: Node
var _daycycle: Node
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _placed := false
var _everybody := false       # (the soak test: nobody is left out for being far away)

var anemones: Array = []       # one dictionary each: pos, r, kind, fish (their dictionaries)
var _anem_seen := 0
var _afish_mm: MultiMesh
var fish_shown := 0

var colonies: Array = []       # garden eels: pos, eels (dictionaries), mm
var morays: Array = []         # one dictionary each (see _make_den())
var octopuses: Array = []
var lionfish: Array = []
var _lion_mm: MultiMesh
var open_dens := 0             # how many places there were for an octopus's den (for the tests)


func setup(ls: Node, player: Node3D, seabed: Node) -> void:
	_ls = ls
	_player = player
	_seabed = seabed
	_sealife = get_node_or_null("../../SeaLife")
	_daycycle = get_node_or_null("../../DayCycle")
	_rng.seed = 90210
	_afish_mm = MultiMesh.new()
	_afish_mm.transform_format = MultiMesh.TRANSFORM_3D
	_afish_mm.use_custom_data = true
	_afish_mm.mesh = ReefModels.anemonefish()
	_afish_mm.instance_count = FISH_MAX
	_afish_mm.visible_instance_count = 0
	_afish_mm.custom_aabb = AABB(Vector3(-300, -40, -300), Vector3(600, 80, 600))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Anemonefish"
	mi.multimesh = _afish_mm
	mi.material_override = _mat("res://shaders/reef_fish.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _wave(x: float, z: float) -> float:
	return float(_sealife.surface(x, z)) if _sealife else 0.0


func _process(delta: float) -> void:
	if _player == null or _seabed == null:
		return
	delta = minf(delta, 0.1)
	_time += delta
	# (the eyes of whoever is in the water: the animals judge their distance from these)
	var eye := _player.global_position + Vector3(0, 0.95, 0)
	var night: float = _daycycle.night if _daycycle else 0.0
	_take_anemones()
	_update_anemonefish(delta, eye, night)
	if not _placed and _seabed.done():
		_placed = true
		_place_colonies()
		_place_dens()
		_place_lionfish()
		_place_grouper()
		_place_triggerfish()
		# (everybody has a place: now the coral garden may grow around them)
		if _seabed.has_method("grow_garden"):
			_seabed.grow_garden(_garden_keep())
	_update_eels(delta, eye, night)
	_update_morays(delta, eye)
	_update_octopuses(delta, eye, night)
	_update_lionfish(delta, eye, night)
	_update_grouper(delta, eye, night)
	_update_triggerfish(delta, eye, night)


# ------------------------------------------------------------------ anemonefish
## The anemones that seabed.gd has built since the last look: each gets its family.
func _take_anemones() -> void:
	var spots: Array = _seabed.anemone_spots
	while _anem_seen < spots.size():
		var s: Array = spots[_anem_seen]
		_anem_seen += 1
		var pos: Vector3 = s[0]
		var kind: int = s[2]
		var g := RandomNumberGenerator.new()
		g.seed = hash(Vector2i(int(pos.x * 10.0), int(pos.z * 10.0)))    # the same family every time
		var a := {"pos": pos, "r": float(s[1]), "kind": kind, "fish": []}
		# a pair, the female the bigger of the two, and often one or two young; now and then an
		# anemone has nobody
		var n := 0 if g.randf() < 0.1 else 2 + (g.randi() % 3 if g.randf() < 0.75 else 0)
		for k in n:
			var length: float = float([0.125, 0.095, 0.062, 0.05][k]) * g.randf_range(0.92, 1.08) * (1.0 if kind == 0 else 0.8)
			var f := {"p": Vector3(g.randf_range(-0.1, 0.1), 0.1, g.randf_range(-0.1, 0.1)), "v": Vector3.ZERO, "goal": Vector3(0, 0.1, 0),
				"t": g.randf() * 2.0, "len": length, "rank": k, "phase": g.randf(), "amp": 0.4, "dir": Vector3.FORWARD.rotated(Vector3.UP, g.randf() * TAU), "turn": 0.5}
			(a["fish"] as Array).append(f)
		anemones.append(a)


func _update_anemonefish(delta: float, eye: Vector3, night: float) -> void:
	var n := 0
	for a: Dictionary in anemones:
		var pos: Vector3 = a["pos"]
		if Vector2(pos.x - eye.x, pos.z - eye.z).length_squared() > 34.0 * 34.0 or (a["fish"] as Array).is_empty():
			continue
		var dist := pos.distance_to(eye)
		var alert := dist < 3.4
		var kind: int = a["kind"]
		var reach: float = float(a["r"]) * (0.8 if kind == 0 else 1.0)
		# (the swell rocks them with the tentacles)
		var surge := sin(_time * 1.25 + pos.x * 0.55 + pos.z * 0.31) * 0.65 + sin(_time * 0.47 + pos.z * 0.2) * 0.4
		var top := _wave(pos.x, pos.z) - 0.4 - pos.y
		for f: Dictionary in a["fish"]:
			_move_fish(f, delta, a, reach, alert, night > 0.6, eye - pos, top)
			if n >= FISH_MAX:
				continue
			var d: Vector3 = f["dir"]
			var sc: float = float(f["len"]) / 3.6
			var at: Vector3 = pos + (f["p"] as Vector3) + Vector3(surge * 0.022, 0, 0)
			_afish_mm.set_instance_transform(n, Transform3D(Basis.looking_at(d, Vector3.UP).scaled(Vector3.ONE * sc), at))
			_afish_mm.set_instance_custom_data(n, Color(float(kind) / 255.0, f["phase"], f["amp"], f["turn"]))
			n += 1
	_afish_mm.visible_instance_count = n
	fish_shown = n


## One anemonefish for one step. `p` is its place relative to the middle of its anemone's disc.
## Hard rule: it never leaves the space over its anemone (`reach` wide, half a meter high at
## the most, and well under the surface).
func _move_fish(f: Dictionary, delta: float, a: Dictionary, reach: float, alert: bool, asleep: bool, to_eye: Vector3, top: float) -> void:
	var p: Vector3 = f["p"]
	var rank: int = f["rank"]
	var kind: int = a["kind"]
	# (the magnificent anemone's tentacles reach higher than the carpet's)
	var low := 0.035 if kind == 0 else 0.13
	f["t"] -= delta
	if f["t"] <= 0.0:
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * reach
		var high: float = [0.3, 0.22, 0.14, 0.1][rank]
		var y := _rng.randf_range(low, low + high)
		f["t"] = _rng.randf_range(0.5, 2.4)
		if asleep:
			# at night they lie among the tentacles
			rad *= 0.4
			y = low * 0.6
			f["t"] = _rng.randf_range(4.0, 9.0)
		elif alert and rank > 0:
			# somebody overhead: the small ones go down into the anemone
			rad *= 0.55
			y = _rng.randf_range(low * 0.5, low)
			f["t"] = _rng.randf_range(0.8, 2.0)
		elif alert:
			# ... and the female comes up a little way to look at whoever it is
			var flat := Vector2(to_eye.x, to_eye.z)
			var side := flat.normalized() * (reach * 0.7) if flat.length() > 0.2 else Vector2.ZERO
			ang = atan2(side.y, side.x) + _rng.randf_range(-0.7, 0.7)
			rad = reach * _rng.randf_range(0.3, 0.8)
			y = _rng.randf_range(0.28, 0.5)
			f["t"] = _rng.randf_range(1.0, 2.6)
		elif _rng.randf() < 0.22:
			# a dip into the tentacles
			y = low * 0.6
		f["goal"] = Vector3(cos(ang) * rad, y, sin(ang) * rad)
	var goal: Vector3 = f["goal"]
	var v: Vector3 = f["v"]
	var want: Vector3 = (goal - p) * 2.6
	var vmax := 0.1 if asleep else 0.34
	if want.length() > vmax:
		want = want.normalized() * vmax
	v = v.lerp(want, 1.0 - exp(-4.5 * delta))
	p += v * delta
	var flat_p := Vector2(p.x, p.z)
	if flat_p.length() > reach * 1.15:
		flat_p = flat_p.normalized() * reach * 1.15
	p = Vector3(flat_p.x, clampf(p.y, low * 0.5, maxf(minf(0.55, top), low * 0.5)), flat_p.y)
	f["p"] = p
	f["v"] = v
	# it looks where it swims; hovering, the female keeps an eye on the swimmer
	var d: Vector3 = f["dir"]
	var speed := v.length()
	var tgt := d
	if speed > 0.05:
		tgt = Vector3(v.x, v.y * 0.5, v.z).normalized()
	elif alert and rank == 0 and to_eye.length() > 0.3:
		tgt = (to_eye.normalized() * Vector3(1, 0.45, 1)).normalized()
	else:
		tgt = Vector3(d.x, 0.0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.05 else Vector3.FORWARD
	# (not for a turn too small to see: between two directions that are all but the same the
	# engine's slerp cannot find a clean axis, and said so 800 times a minute at night, when
	# the fish lie still among the tentacles)
	var same := d.dot(tgt)
	var nd := d.slerp(tgt, 1.0 - exp(-6.0 * delta)) if (same > -0.98 and same < 0.99999) else tgt
	nd.y = clampf(nd.y, -0.6, 0.6)
	nd = nd.normalized()
	var yaw_rate := d.cross(nd).y / maxf(delta, 0.001)
	f["dir"] = nd
	f["turn"] = lerpf(f["turn"], 0.5 - clampf(yaw_rate * 0.12, -0.5, 0.5), 1.0 - exp(-8.0 * delta))
	# anemonefish never stop waggling
	f["phase"] = fposmod(float(f["phase"]) + (0.5 if asleep else 2.1 + speed * 9.0) * delta, 1.0)
	f["amp"] = lerpf(f["amp"], 0.12 if asleep else clampf(0.4 + speed * 2.4, 0.0, 1.0), 1.0 - exp(-5.0 * delta))


# ------------------------------------------------------------------ garden eels
func _bare(p: Vector2) -> bool:
	var mk: Color = _seabed._mask_at(p)
	return mk.g < 0.25 and mk.b < 0.25 and float(_seabed.meadow(p)) < 0.05 and float(_ls.ground(p.x, p.y)) < -3.0


## Chooses where the colonies live among the patches of bare sand seabed.gd has found: some
## off the start beach, the others around the island, well apart.
func _place_colonies() -> void:
	var sites: Array = (_seabed.sand_spots as Array).duplicate()
	var g := RandomNumberGenerator.new()
	g.seed = 5150
	for i in range(sites.size() - 1, 0, -1):
		var j := g.randi() % (i + 1)
		var tmp: Vector3 = sites[i]
		sites[i] = sites[j]
		sites[j] = tmp
	var chosen: Array = []
	for pass_ in 2:
		for s: Vector3 in sites:
			var in_zone := ZONE.has_point(Vector2(s.x, s.z))
			if (pass_ == 0) != in_zone or chosen.size() >= (4 if pass_ == 0 else 12):
				continue
			var free := true
			for c: Vector3 in chosen:
				if c.distance_to(s) < (30.0 if in_zone else 55.0):
					free = false
					break
			if free:
				chosen.append(s)
	var mesh := ReefModels.garden_eel()
	var mat := _mat("res://shaders/garden_eel.gdshader")
	for c: Vector3 in chosen:
		var eels: Array = []
		var want := g.randi_range(24, 38)
		# they all face the same way, into the current: out to sea
		var out := Vector2(c.x, c.z).normalized()
		var face := atan2(-out.y, out.x)
		for i in 600:
			if eels.size() >= want:
				break
			var p := Vector2(c.x, c.z) + Vector2.from_angle(g.randf() * TAU) * (sqrt(g.randf()) * 3.8)
			if not _bare(p):
				continue
			var near := false
			for e: Dictionary in eels:
				if Vector2((e["pos"] as Vector3).x, (e["pos"] as Vector3).z).distance_to(p) < 0.5:
					near = true
					break
			if near:
				continue
			var r_in := g.randf_range(2.7, 3.7)
			eels.append({"pos": Vector3(p.x, _ls.ground(p.x, p.y), p.y), "yaw": face + g.randf_range(-0.5, 0.5), "size": g.randf_range(1.0, 1.3),
				"out": 1.0, "mood": g.randf_range(0.7, 1.0), "mood_t": g.randf() * 8.0, "phase": g.randf(), "hook": g.randf_range(0.6, 1.0),
				"hook_want": 0.8, "nod": 0.0, "nod_want": 0.0, "r_in": r_in, "r_out": r_in + g.randf_range(2.4, 3.4), "wait": 0.0})
		if eels.size() < 8:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = eels.size()
		for i in eels.size():
			var e: Dictionary = eels[i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, e["yaw"]).scaled(Vector3.ONE * float(e["size"])), (e["pos"] as Vector3) - c))
			mm.set_instance_custom_data(i, Color(1.0, e["phase"], e["hook"], 0.0))
		mm.custom_aabb = AABB(Vector3(-5, -1.5, -5), Vector3(10, 3, 10))
		var mi := MultiMeshInstance3D.new()
		mi.name = "GardenEels%d" % colonies.size()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = c
		mi.visibility_range_end = 42.0
		add_child(mi)
		colonies.append({"pos": c, "eels": eels, "mm": mm})


func _update_eels(delta: float, eye: Vector3, night: float) -> void:
	for col: Dictionary in colonies:
		var c: Vector3 = col["pos"]
		if Vector2(c.x - eye.x, c.z - eye.z).length_squared() > 46.0 * 46.0:
			continue
		var mm: MultiMesh = col["mm"]
		var eels: Array = col["eels"]
		for i in eels.size():
			var e: Dictionary = eels[i]
			_move_eel(e, delta, eye, night > 0.6)
			mm.set_instance_custom_data(i, Color(e["out"], e["phase"], e["hook"], e["nod"]))


## One garden eel for one step: how far it stands out of its burrow. It never leaves it.
func _move_eel(e: Dictionary, delta: float, eye: Vector3, asleep: bool) -> void:
	# its own ups and downs: now it stretches, now it sinks back half way; now it picks at
	# what drifts past
	e["mood_t"] -= delta
	if e["mood_t"] <= 0.0:
		e["mood_t"] = _rng.randf_range(4.0, 14.0)
		e["mood"] = _rng.randf_range(0.55, 1.0)
		e["hook_want"] = _rng.randf_range(0.5, 1.0)
		e["nod_want"] = 1.0 if _rng.randf() < 0.5 else 0.0
	var d := eye.distance_to((e["pos"] as Vector3) + Vector3(0, 0.15, 0))
	var safe := 0.0 if asleep else smoothstep(float(e["r_in"]), float(e["r_out"]), d)
	var want := safe * float(e["mood"])
	var out: float = e["out"]
	if want < out:
		# down: at once, but as a sinking, not a snap
		out = maxf(want, out - (0.55 if safe < out else 0.12) * delta)
		if safe < out + 0.02:
			e["wait"] = _rng.randf_range(2.5, 6.0)
	else:
		# up again: after a wait, slowly
		e["wait"] -= delta
		if e["wait"] <= 0.0:
			out = minf(want, out + 0.1 * delta)
	e["out"] = out
	e["hook"] = lerpf(e["hook"], e["hook_want"], 1.0 - exp(-0.8 * delta))
	e["nod"] = lerpf(e["nod"], e["nod_want"], 1.0 - exp(-1.5 * delta))


# ------------------------------------------------------------------ for the tests
func report() -> Dictionary:
	var eye := _player.global_position
	var in_zone := 0
	var with_fish := 0
	var fish := 0
	var kinds := [0, 0]
	var nearest := Vector3.ZERO
	var best := 1e9
	for a: Dictionary in anemones:
		var p: Vector3 = a["pos"]
		kinds[int(a["kind"])] += 1
		if ZONE.has_point(Vector2(p.x, p.z)):
			in_zone += 1
		if not (a["fish"] as Array).is_empty():
			with_fish += 1
		fish += (a["fish"] as Array).size()
		if p.distance_to(eye) < best:
			best = p.distance_to(eye)
			nearest = p
	var eels := 0
	var cols: Array = []
	for col: Dictionary in colonies:
		eels += (col["eels"] as Array).size()
		cols.append([col["pos"], (col["eels"] as Array).size()])
	var mor: Array = []
	for m: Dictionary in morays:
		mor.append([m["pos"], m["species"], m["state"], snappedf(float(m["out"]), 0.01)])
	var oct: Array = []
	for o: Dictionary in octopuses:
		oct.append([o["pos"], o["state"], snappedf(float(o["k"]), 0.01), snappedf(float(o["back"]), 0.01)])
	var lio: Array = []
	for l: Dictionary in lionfish:
		lio.append(l["pos"])
	return {"open den spots": open_dens, "morays": mor, "octopuses": oct, "lionfish": lio, "anemones": anemones.size(), "carpet / magnificent": kinds, "off the start beach": in_zone, "with fish": with_fish, "anemonefish": fish,
		"shown now": fish_shown, "nearest anemone": nearest, "eel colonies": cols, "garden eels": eels,
		"den spots": (_seabed.den_spots as Array).size(), "sand spots": (_seabed.sand_spots as Array).size(), "big corals": (_seabed.big_corals as Array).size()}


## What the corals of the garden (seabed.gd) are to keep off: [Vector2, radius].
func _garden_keep() -> Array:
	var keep: Array = []
	for m: Dictionary in morays:
		keep.append([_xz(m["pos"]), 0.8])
		keep.append([_xz((m["root"] as Node3D).global_position), 0.8])
	for o: Dictionary in octopuses:
		keep.append([_xz(o["pos"]), 1.5])      # (its arms lie on the floor around its rock)
		keep.append([_xz((o["root"] as Node3D).global_position), 1.5])
	for l: Dictionary in lionfish:
		keep.append([l["c"], float(l["rad"]) + 0.45])     # (it goes around its coral)
	for c: Dictionary in colonies:
		keep.append([_xz(c["pos"]), 4.5])
	if not grouper.is_empty():
		keep.append([_xz(grouper["home"]), 4.5])
	for t: Dictionary in triggers:
		keep.append([_xz(t["home"]), 2.5])
	return keep


func _xz(v: Variant) -> Vector2:
	return v if v is Vector2 else Vector2((v as Vector3).x, (v as Vector3).z)


# ------------------------------------------------------------------ dens: morays and octopuses
## Chooses the dens among the places seabed.gd has found: the octopuses' (the rarer) on open
## sand at the foot of the reef, the morays' in gaps in the reef itself; of each, some in the
## lagoon off the start beach and the others around the island; an animal's den well away
## from the next of its kind.
func _place_dens() -> void:
	var spots: Array = (_seabed.den_spots as Array).duplicate()
	var g := RandomNumberGenerator.new()
	g.seed = 777
	for i in range(spots.size() - 1, 0, -1):
		var j := g.randi() % (i + 1)
		var tmp: Vector3 = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	# the morays' dens: gaps in the reef, those with the most room around them first (a den is
	# not to lie under a table coral)
	var roomy: Array = []
	for want: float in [1.05, 0.85, 0.7, 0.58, 0.0]:
		for s: Vector3 in spots:
			var q := Vector2(s.x, s.z)
			if not roomy.has(s) and (want == 0.0 or (_seabed.room(q, want, 1.0) and not _seabed.overhung(q, 0.2))):
				roomy.append(s)
	# the octopuses' dens: on open sand at the foot of the reef, where nothing stands or
	# reaches within 0.8 m: its arms lie on its rock and on the floor around it, and are not
	# to meet a coral there
	var open_spots: Array = []
	for s: Vector3 in _seabed.edge_spots:
		var q := Vector2(s.x, s.z)
		if _seabed.room(q, 0.8, 1.0) and not _seabed.overhung(q, 0.8):
			open_spots.append(s)
	for i in range(open_spots.size() - 1, 0, -1):
		var j := g.randi() % (i + 1)
		var tmp: Vector3 = open_spots[i]
		open_spots[i] = open_spots[j]
		open_spots[j] = tmp
	open_dens = open_spots.size()
	var lists := [open_spots, roomy]
	var tint := Color(0.6, 0.55, 0.45)
	var seeds := [[11, 12], [21, 22]]
	var rocks := [[ReefModels.den_rock(11, true, tint), ReefModels.den_rock(12, true, tint)], [ReefModels.den_rock(21, false, tint), ReefModels.den_rock(22, false, tint)]]
	var chosen: Array = []
	for kind in 2:
		for pass_ in 2:
			var count := 0
			var limit: int = [[5, 9], [7, 13]][kind][pass_]
			for s: Vector3 in lists[kind]:
				if count >= limit:
					break
				if (pass_ == 0) != ZONE.has_point(Vector2(s.x, s.z)):
					continue
				var free := true
				for c: Array in chosen:
					var apart := 7.0 if c[1] != kind else (30.0 if kind == 0 else 20.0)
					if (c[0] as Vector3).distance_to(s) < apart:
						free = false
						break
				if free:
					chosen.append([s, kind])
					count += 1
	var moray_mesh := ReefModels.moray()
	var moray_mats: Array = []
	for sp in 2:
		var mm := _mat("res://shaders/moray.gdshader")
		mm.set_shader_parameter("species", sp)
		moray_mats.append(mm)
	var octo_mesh := ReefModels.octopus()
	var octo_mat := _mat("res://shaders/octopus.gdshader")
	for c: Array in chosen:
		var p: Vector3 = c[0]
		var kind: int = c[1]
		var sc := g.randf_range(1.2, 1.45)
		# the mouth looks out from the reef: downhill, more or less
		var n: Vector3 = _seabed._normal(Vector2(p.x, p.z))
		var down := Vector2(n.x, n.z)
		var d := (down.normalized() if down.length() > 0.06 else Vector2.from_angle(g.randf() * TAU)).rotated(g.randf_range(-0.7, 0.7))
		var basis := Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(n, 0.5).normalized())) * Basis(Vector3.UP, atan2(-d.x, -d.y))
		var root := Node3D.new()
		root.name = ("OctopusDen%d" % octopuses.size()) if kind == 0 else ("MorayDen%d" % morays.size())
		root.transform = Transform3D(basis, p)
		add_child(root)
		var rock := MeshInstance3D.new()
		var which := g.randi() % 2
		rock.mesh = rocks[kind][which]
		rock.material_override = _seabed._coral_mat
		rock.scale = Vector3.ONE * sc
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rock.visibility_range_end = 70.0
		root.add_child(rock)
		_seabed.occupy(Vector2(p.x, p.z), 0.4 * sc)
		var mouth: Vector3 = ReefModels.DEN_MOUTH * sc
		var mouth_b := Basis(Vector3.RIGHT, deg_to_rad(40.0))
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 48.0
		mi.custom_aabb = AABB(Vector3(-0.9, -0.9, -0.9), Vector3(1.8, 1.8, 1.8))
		root.add_child(mi)
		if kind == 1:
			var species := morays.size() % 2
			# (big animals, both kinds: they have to be made out from the surface)
			var size := g.randf_range(1.45, 1.7) * (1.1 if species == 1 else 1.0)
			mi.name = "Moray"
			mi.mesh = moray_mesh
			mi.material_override = moray_mats[species]
			mi.transform = Transform3D(mouth_b.scaled(Vector3.ONE * size), mouth)
			morays.append({"node": mi, "root": root, "pos": root.to_global(mouth), "species": species, "state": "look", "t": g.randf_range(15.0, 50.0),
				"out": 0.3, "out_want": 0.3, "turn": 0.0, "turn_want": 0.0, "lift": -0.2, "lift_want": -0.2, "aim_t": 0.0, "sway": g.randf() * TAU,
				"ph": g.randf() * TAU, "shy": false, "max_out": 0.0})
		else:
			var size := g.randf_range(1.4, 1.7)
			mi.name = "Octopus"
			mi.mesh = octo_mesh
			mi.material_override = octo_mat
			mi.set_instance_shader_parameter("seed", g.randf() * 50.0)
			# its seat is the top of its own rock; its arms are kept on that rock's surface
			# (the shader has the rock's shape: see reef_models.gd: den_radius())
			var shape: Vector2 = ReefModels.den_shape(seeds[kind][which])
			var seat: Vector3 = (ReefModels.DEN_CENTER + Vector3.UP * ReefModels.den_radius(Vector3.UP, shape)) * sc + Vector3(0, 0.008 * size, 0)
			octopuses.append({"node": mi, "root": root, "pos": root.to_global(mouth), "sc": size, "mouth": mouth, "mouth_b": mouth_b,
				"rock_sc": sc, "shape": shape, "floor": (basis.inverse() * n).normalized(),
				"perch": seat, "perch_yaw": g.randf_range(-0.8, 0.8), "state": "den", "t": g.randf_range(20.0, 70.0),
				"k": 0.0, "back": 0.0, "calm": 0.0, "pale": 0.2, "pale_want": 0.2, "pale_t": 0.0, "look": 0.0, "hurry": false})
	# (a diver keeps above the den rocks as above the corals)
	for den: Dictionary in morays + octopuses:
		var rp: Vector3 = (den["root"] as Node3D).global_position
		_seabed.add_top(Vector2(rp.x, rp.z), 0.6, rp.y + 0.85)
	_update_morays(0.0, Vector3(1e5, 0, 0))
	_update_octopuses(0.0, Vector3(1e5, 0, 0), 0.0)


## The morays: each looks out of its hole, the mouth opening and closing as it breathes, the
## neck weaving slowly; it turns its head toward a swimmer who comes within a few meters,
## and draws back into the hole when one is close. Now and then it draws back by itself for
## a while. It never comes further out than 0.45 m: it never leaves the hole.
func _update_morays(delta: float, eye: Vector3) -> void:
	for m: Dictionary in morays:
		var pos: Vector3 = m["pos"]
		if delta > 0.0 and not _everybody and Vector2(pos.x - eye.x, pos.z - eye.z).length_squared() > 50.0 * 50.0:
			continue
		var d := pos.distance_to(eye)
		m["t"] -= delta
		if d < 2.5:
			# somebody close: back into the hole, and no hurry to come out again
			if m["state"] != "in" or not m["shy"]:
				m["t"] = _rng.randf_range(5.0, 9.0)
			m["state"] = "in"
			m["shy"] = true
			m["t"] = maxf(m["t"], 3.0)
		elif m["state"] == "in" and m["shy"] and d < 3.4:
			m["t"] = maxf(m["t"], 3.0)
		if m["state"] == "look":
			m["aim_t"] -= delta
			if m["aim_t"] <= 0.0:
				m["aim_t"] = _rng.randf_range(4.0, 9.0)
				m["out_want"] = _rng.randf_range(0.2, 0.42)
				m["turn_want"] = _rng.randf_range(-0.8, 0.8)
				m["lift_want"] = _rng.randf_range(-0.5, 0.05)
			if d < 9.0:
				# it keeps an eye on the swimmer
				var to: Vector3 = (m["node"] as Node3D).global_transform.basis.orthonormalized().inverse() * (eye - pos)
				m["turn_want"] = clampf(atan2(-to.x, -to.z), -1.0, 1.0) * 0.8
				m["lift_want"] = clampf(atan2(to.y, Vector2(to.x, to.z).length()) * 0.6 - 0.15, -0.5, 0.35)
			if m["t"] <= 0.0:
				m["state"] = "in"
				m["shy"] = false
				m["t"] = _rng.randf_range(6.0, 15.0)
		else:
			m["out_want"] = 0.05
			m["turn_want"] = 0.0
			m["lift_want"] = -0.1
			if m["t"] <= 0.0:
				m["state"] = "look"
				m["t"] = _rng.randf_range(25.0, 60.0)
				m["aim_t"] = 0.0
		var out: float = m["out"]
		var want: float = m["out_want"]
		if want < out:
			out = maxf(want, out - (0.26 if m["shy"] and m["state"] == "in" else 0.09) * delta)
		else:
			out = minf(want, out + 0.07 * delta)
		out = clampf(out, 0.03, 0.45)
		m["out"] = out
		m["max_out"] = maxf(m["max_out"], out)
		m["turn"] = lerpf(m["turn"], m["turn_want"], 1.0 - exp(-1.1 * delta))
		m["lift"] = lerpf(m["lift"], m["lift_want"], 1.0 - exp(-1.1 * delta))
		m["sway"] += delta * 0.8
		m["ph"] += delta * 2.0
		var node: MeshInstance3D = m["node"]
		node.set_instance_shader_parameter("out_len", out)
		node.set_instance_shader_parameter("turn", m["turn"])
		node.set_instance_shader_parameter("lift", m["lift"])
		node.set_instance_shader_parameter("gape", 0.08 + 0.15 * (0.5 + 0.5 * sin(float(m["ph"]))))
		node.set_instance_shader_parameter("sway", m["sway"])


## The day octopuses. `k`: where it is between the mouth of its den (0) and its seat on top
## of the rock (1); `back`: how far it has drawn back into the hole (0..1).
## In the den it sits in the mouth and watches, breathing, an arm or two over the lip, the
## skin changing between paler and darker mottling. When nobody has been near for a while it
## climbs out and sits on top of its rock, arms spread, then goes in again. It turns its head
## to a swimmer a few meters off and darkens; one who comes close sends it back into the
## hole, pale as the rock, until some seconds after they have gone. It sleeps in the den at
## night. It never goes further from the hole than the top of its own rock, and its arms lie
## on that rock and on the sea floor around it, never in them (the shader sees to that).
func _update_octopuses(delta: float, eye: Vector3, night: float) -> void:
	for o: Dictionary in octopuses:
		var pos: Vector3 = o["pos"]
		if delta > 0.0 and not _everybody and Vector2(pos.x - eye.x, pos.z - eye.z).length_squared() > 50.0 * 50.0:
			continue
		var root: Node3D = o["root"]
		var d := pos.distance_to(eye)
		var asleep := night > 0.6
		var state: String = o["state"]
		o["calm"] = float(o["calm"]) + delta if d > 3.3 else 0.0
		match state:
			"den":
				# (a swimmer at the surface over a den four meters down does not keep it in)
				if d > 4.2 and not asleep:
					o["t"] -= delta
				if o["t"] <= 0.0 and float(o["back"]) < 0.05:
					state = "climb"
			"climb":
				o["k"] = minf(float(o["k"]) + delta / 7.0, 1.0)
				if d < 3.2 or asleep:
					state = "return"
					o["hurry"] = true
				elif float(o["k"]) >= 1.0:
					state = "out"
					o["t"] = _rng.randf_range(25.0, 60.0)
			"out":
				o["t"] -= delta
				if d < 3.2 or asleep:
					state = "return"
					o["hurry"] = true
				elif o["t"] <= 0.0:
					state = "return"
					o["hurry"] = false
			"return":
				# back the way it came, flowing over the edge: quicker with somebody near, never a dash
				o["k"] = maxf(float(o["k"]) - delta / (3.6 if o["hurry"] else 6.5), 0.0)
				if float(o["k"]) <= 0.0:
					state = "den"
					o["t"] = _rng.randf_range(40.0, 90.0)
		o["state"] = state
		var k: float = o["k"]
		var want_back := 1.0 if (state == "den" and (d < 2.3 or asleep or (float(o["back"]) > 0.05 and float(o["calm"]) < 6.0))) else 0.0
		o["back"] = move_toward(float(o["back"]), want_back, (0.5 if want_back > 0.5 else 0.22) * delta)
		var back: float = o["back"]
		# the skin
		o["pale_t"] -= delta
		if o["pale_t"] <= 0.0:
			o["pale_t"] = _rng.randf_range(5.0, 12.0)
			o["pale_want"] = _rng.randf_range(0.05, 0.4) if k < 0.5 else _rng.randf_range(0.0, 0.25)
		var pale_want: float = o["pale_want"]
		if back > 0.4:
			pale_want = 0.85
		elif d < 4.5:
			pale_want = 0.0
		o["pale"] = lerpf(o["pale"], pale_want, 1.0 - exp(-1.8 * delta))
		# the head turns to whoever is near; else it looks about
		var facing: Basis = (o["mouth_b"] as Basis).slerp(Basis(Vector3.UP, o["perch_yaw"]), smoothstep(0.0, 1.0, k))
		var look_want := 0.4 * sin(_time * 0.13 + pos.x)
		if d < 7.0:
			var to: Vector3 = (root.global_transform.basis.orthonormalized() * facing).inverse() * (eye - pos)
			look_want = clampf(atan2(-to.x, -to.z), -0.75, 0.75)
		o["look"] = lerpf(o["look"], look_want, 1.0 - exp(-1.3 * delta))
		var sc: float = o["sc"]
		var e := smoothstep(0.0, 1.0, k)
		var mouth: Vector3 = o["mouth"]
		# (drawing back, the arms come in first (`reel`, in the first half), then the body
		# sinks into the hole: see shaders/octopus.gdshader)
		var reel := smoothstep(0.0, 0.5, back)
		var at: Vector3 = (mouth + ReefModels.DEN_AXIS * ((0.06 - 0.2 * smoothstep(0.3, 1.0, back)) * sc)).lerp(o["perch"], e) + ReefModels.DEN_AXIS * (0.07 * sin(e * PI))
		var node: MeshInstance3D = o["node"]
		node.transform = Transform3D((facing * Basis(Vector3.UP, o["look"])).scaled(Vector3.ONE * sc), at)
		node.set_instance_shader_parameter("curl", lerpf(1.9, 0.75 + 0.15 * sin(_time * 0.21 + pos.z), e) + 0.7 * back + 5.0 * reel)
		node.set_instance_shader_parameter("tuck", lerpf(0.55, 0.0, e) + 0.45 * back)
		# (in the mouth of the den the arms hang down the face of the rock; on top they bend over it)
		# (gathered in, they coil beside the body: they do not hang)
		node.set_instance_shader_parameter("droop", lerpf(1.5, 1.0, e) * (1.0 - 0.95 * smoothstep(0.0, 0.6, reel)))
		node.set_instance_shader_parameter("writhe", lerpf(0.6, 1.0, e) * (1.0 - 0.6 * back))
		node.set_instance_shader_parameter("pale", o["pale"])
		# the rock, as the animal's own space sees it; the arms are kept out of it always
		var to_rock := Transform3D(node.transform.basis / float(o["rock_sc"]), node.transform.origin / float(o["rock_sc"]))
		var shape: Vector2 = o["shape"]
		node.set_instance_shader_parameter("rock0", Vector4(to_rock.basis.x.x, to_rock.basis.y.x, to_rock.basis.z.x, to_rock.origin.x))
		node.set_instance_shader_parameter("rock1", Vector4(to_rock.basis.x.y, to_rock.basis.y.y, to_rock.basis.z.y, to_rock.origin.y))
		node.set_instance_shader_parameter("rock2", Vector4(to_rock.basis.x.z, to_rock.basis.y.z, to_rock.basis.z.z, to_rock.origin.z))
		node.set_instance_shader_parameter("rock_k", Vector4(shape.x, shape.y, 1.0, reel))
		node.set_instance_shader_parameter("floor_n", o["floor"])


# ------------------------------------------------------------------ lionfish
## A few lionfish, each at a big coral of its own: it hangs beside the coral's edge, head a
## little down, the fans spread, and now and then drifts around to another side of it. A
## swimmer close by: it moves around to the far side, slowly. At night it hangs further out.
## Its place is always given as a bearing around its coral: it cannot stray.
func _place_lionfish() -> void:
	var corals: Array = (_seabed.big_corals as Array).duplicate()
	var g := RandomNumberGenerator.new()
	g.seed = 4242
	for i in range(corals.size() - 1, 0, -1):
		var j := g.randi() % (i + 1)
		var tmp: Array = corals[i]
		corals[i] = corals[j]
		corals[j] = tmp
	for pass_ in 2:
		var count := 0
		for c: Array in corals:
			if count >= (6 if pass_ == 0 else 10):
				break
			var p: Vector2 = c[0]
			var r: float = c[1]
			if (pass_ == 0) != ZONE.has_point(p) or r < 0.65 or float(c[3]) > -2.3 or float(c[3]) < -6.5:
				continue
			var free := true
			for l: Dictionary in lionfish:
				if (l["c"] as Vector2).distance_to(p) < 26.0:
					free = false
					break
			for o: Dictionary in octopuses + morays:
				if Vector2((o["pos"] as Vector3).x, (o["pos"] as Vector3).z).distance_to(p) < r + 1.2:
					free = false
			if not free:
				continue
			# the sides of the coral where nothing else stands
			var rad := r + 0.25
			var sides: Array = []
			for k in 12:
				var a := TAU * k / 12.0
				if _seabed.room(p + Vector2.from_angle(a) * rad, 0.15, 0.9):
					sides.append(a)
			if sides.size() < 3:
				continue
			var a0: float = sides[g.randi() % sides.size()]
			lionfish.append({"c": p, "r": r, "rad": rad, "gy": float(c[3]), "h": clampf(float(c[2]) * 0.8, 0.3, 0.75), "sides": sides, "ang": a0, "ang_want": a0,
				"t": g.randf_range(8.0, 30.0), "pos": Vector3(p.x, c[3], p.y), "dir": Vector3.FORWARD, "phase": g.randf(), "amp": 0.2, "turn": 0.5,
				"len": g.randf_range(0.27, 0.34), "spin": 1.0 if g.randf() < 0.5 else -1.0, "bob": g.randf() * TAU})
			count += 1
	# A coral can reach out further than its foot (the leaves of a cabbage coral, a table's
	# plate): a lionfish hangs clear of all that, a little further out if need be, and only
	# at the sides where nothing else reaches either. (Done here, after everybody has their
	# coral and without a random number, so that nobody's place depends on it.)
	for l: Dictionary in lionfish:
		var y := float(l["gy"]) + float(l["h"]) - 0.15
		for extra in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
			var open: Array = []
			for a: float in l["sides"]:
				if float(_seabed.top_at((l["c"] as Vector2) + Vector2.from_angle(a) * (float(l["rad"]) + float(extra)), 0.01)) < y:
					open.append(a)
			# (the nearest to its coral at which a side is free: it is to hang beside it)
			if not open.is_empty() or float(extra) > 0.95:
				if not open.is_empty():
					l["rad"] = float(l["rad"]) + float(extra)
					l["sides"] = open
					if not open.has(l["ang"]):
						l["ang"] = open[0]
						l["ang_want"] = open[0]
				break
		# ... and from one side to the next only where the way between them is free too (a
		# neighbor can reach in between two free sides); and further out at night only if
		# it is free there as well
		var links: Array = []
		var out_ok := true
		for a: float in l["sides"]:
			var free := false
			for b: float in l["sides"]:
				if absf(wrapf(b - a - TAU / 12.0, -PI, PI)) < 0.01:
					free = true
			for k in [1, 2, 3, 4, 5]:
				if float(_seabed.top_at((l["c"] as Vector2) + Vector2.from_angle(a + TAU / 12.0 * k / 6.0) * float(l["rad"]), 0.01)) >= y:
					free = false
			if free:
				links.append(a)
			if float(_seabed.top_at((l["c"] as Vector2) + Vector2.from_angle(a) * (float(l["rad"]) + 0.6), 0.01)) >= y + 0.15:
				out_ok = false
		l["links"] = links
		l["night_out"] = 0.6 if out_ok else 0.0
	_lion_mm = MultiMesh.new()
	_lion_mm.transform_format = MultiMesh.TRANSFORM_3D
	_lion_mm.use_custom_data = true
	_lion_mm.mesh = ReefModels.lionfish()
	_lion_mm.instance_count = lionfish.size()
	_lion_mm.custom_aabb = AABB(Vector3(-300, -40, -300), Vector3(600, 80, 600))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Lionfish"
	mi.multimesh = _lion_mm
	mi.material_override = _mat("res://shaders/reef_fish.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for l: Dictionary in lionfish:
		_move_lionfish(l, 0.0, Vector3(1e5, 0, 0), 0.0)
		l["dir"] = Vector3(-sin(float(l["ang"])), -0.15, cos(float(l["ang"]))).normalized()
	_update_lionfish(0.0, Vector3(1e5, 0, 0), 0.0)


func _update_lionfish(delta: float, eye: Vector3, night: float) -> void:
	if _lion_mm == null:
		return
	for i in lionfish.size():
		var l: Dictionary = lionfish[i]
		var c: Vector2 = l["c"]
		if delta > 0.0 and Vector2(c.x - eye.x, c.y - eye.z).length_squared() < 50.0 * 50.0:
			_move_lionfish(l, delta, eye, night)
		var d: Vector3 = l["dir"]
		_lion_mm.set_instance_transform(i, Transform3D(Basis.looking_at(d, Vector3.UP).scaled(Vector3.ONE * (float(l["len"]) / 3.6)), l["pos"]))
		_lion_mm.set_instance_custom_data(i, Color(2.0 / 255.0, l["phase"], l["amp"], l["turn"]))


## The sides of its coral a lionfish can drift to from the one it is at (or bound for) without
## passing a side where something else stands, and which way around each lies (+1, -1; 0 the
## side itself): it used to take the short way around, through a neighboring coral if need be.
func _lion_ways(l: Dictionary) -> Dictionary:
	var from: float = l["ang_want"]
	var out := {from: 0.0}
	for way: float in [1.0, -1.0]:
		var a := from
		for k in 11:
			# (the step from one side to the next has to be free: `links` holds the sides
			# from which the next one, counted up, can be reached)
			var lower := a if way > 0.0 else wrapf(a - TAU / 12.0, 0.0, TAU)
			var linked := false
			for s: float in l.get("links", l["sides"]):
				if absf(wrapf(s - lower, -PI, PI)) < 0.01:
					linked = true
			if not linked:
				break
			a = wrapf(a + way * TAU / 12.0, 0.0, TAU)
			var side := NAN
			for s: float in l["sides"]:
				if absf(wrapf(s - a, -PI, PI)) < 0.01:
					side = s
			if is_nan(side):
				break
			if not out.has(side):
				out[side] = way
	return out


func _move_lionfish(l: Dictionary, delta: float, eye: Vector3, night: float) -> void:
	var c: Vector2 = l["c"]
	var sides: Array = l["sides"]
	var old: Vector3 = l["pos"]
	l["t"] -= delta
	var near := old.distance_to(eye) < 2.7
	if near:
		# round to the side away from the swimmer (the nearest free side to that)
		var away := atan2(c.y - eye.z, c.x - eye.x)
		var ways := _lion_ways(l)
		var best: float = l["ang_want"]
		for a: float in ways:
			if absf(wrapf(a - away, -PI, PI)) < absf(wrapf(best - away, -PI, PI)):
				best = a
		if best != float(l["ang_want"]):
			l["way"] = ways[best]
			l["ang_want"] = best
		l["t"] = maxf(l["t"], 10.0)
	elif l["t"] <= 0.0:
		l["t"] = _rng.randf_range(15.0, 40.0)
		var ways := _lion_ways(l)
		var to: float = ways.keys()[_rng.randi() % ways.size()]
		if to != float(l["ang_want"]):
			l["way"] = ways[to]
			l["ang_want"] = to
	var out := float(l.get("night_out", 0.6)) * smoothstep(0.5, 0.9, night)
	var rad: float = float(l["rad"]) + out
	var diff := wrapf(float(l["ang_want"]) - float(l["ang"]), -PI, PI)
	# (the way around that is free, which may be the long one)
	var way: float = l.get("way", 0.0)
	if absf(diff) > 0.02 and way != 0.0 and signf(diff) != way:
		diff += way * TAU
	var w := (0.14 if near else 0.06) / rad
	var step := clampf(diff, -w * delta, w * delta)
	l["ang"] = wrapf(float(l["ang"]) + step, 0.0, TAU)
	var ang: float = l["ang"]
	var p := c + Vector2.from_angle(ang) * rad
	var surge := sin(_time * 1.25 + p.x * 0.55 + p.y * 0.31) * 0.65 + sin(_time * 0.47 + p.y * 0.2) * 0.4
	var ground: float = _ls.ground(p.x, p.y)
	var y := float(l["gy"]) + float(l["h"]) + 0.25 * out + 0.035 * sin(_time * 0.5 + float(l["bob"]))
	# hard rule: clear of the ground under it, well under the surface
	y = clampf(y, ground + 0.22, maxf(_wave(p.x, p.y) - 0.6, ground + 0.22))
	var pos := Vector3(p.x + surge * 0.025, y, p.y)
	l["pos"] = pos
	var speed := absf(step) * rad / maxf(delta, 0.001)
	# it looks the way it drifts; hanging still, along the coral's edge with the head turned
	# in a little, and down
	if absf(step) > 1e-6:
		l["spin"] = signf(step)
	var tangent := Vector3(-sin(ang), 0.0, cos(ang)) * float(l["spin"])
	var inward := Vector3(-cos(ang), 0.0, -sin(ang))
	var tgt := (tangent + inward * (0.15 if speed > 0.02 else 0.55) + Vector3(0, -0.2, 0)).normalized()
	var d: Vector3 = l["dir"]
	var nd := d.slerp(tgt, 1.0 - exp(-0.9 * delta)) if d.dot(tgt) > -0.98 else tgt
	nd = nd.normalized()
	var yaw_rate := d.cross(nd).y / maxf(delta, 0.001)
	l["dir"] = nd
	l["turn"] = lerpf(l["turn"], 0.5 - clampf(yaw_rate * 0.3, -0.5, 0.5), 1.0 - exp(-3.0 * delta))
	l["phase"] = fposmod(float(l["phase"]) + (0.2 + speed * 2.5) * delta, 1.0)
	l["amp"] = lerpf(l["amp"], clampf(0.2 + speed * 4.0, 0.0, 1.0), 1.0 - exp(-2.0 * delta))


# ------------------------------------------------------------------ soak test
## For the tests: runs everybody for `seconds` of their lives in steps of 50 ms: first with
## nobody about, then with a swimmer hanging right over each animal in turn, then with
## nobody again. Reports what they did and whether anybody left the place it must keep to.
func soak(seconds: float) -> Dictionary:
	var far := Vector3(1e5, 0, 0)
	var n := int(seconds / 0.05)
	_everybody = true
	var res := {}
	var moray_states := {}
	var octo_states := {}
	var fish_far := 0.0
	var fish_high := -99.0
	var lion_far := 0.0
	var lion_low := 99.0
	var lion_turned := 0.0
	var eel_min := 9.0
	var eel_max := 0.0
	var nan := 0
	var lion_start: Array = []
	for l: Dictionary in lionfish:
		lion_start.append(l["ang"])
	for i in n:
		_time += 0.05
		for a: Dictionary in anemones:
			var reach: float = float(a["r"]) * (0.8 if int(a["kind"]) == 0 else 1.0)
			var top := -0.4 - float((a["pos"] as Vector3).y)
			for f: Dictionary in a["fish"]:
				_move_fish(f, 0.05, a, reach, false, false, far, top)
				var p: Vector3 = f["p"]
				fish_far = maxf(fish_far, Vector2(p.x, p.z).length() / reach)
				fish_high = maxf(fish_high, p.y + float((a["pos"] as Vector3).y))
				if is_nan(p.x + p.y + p.z):
					nan += 1
		for col: Dictionary in colonies:
			for e: Dictionary in col["eels"]:
				_move_eel(e, 0.05, far, false)
				eel_min = minf(eel_min, e["out"])
				eel_max = maxf(eel_max, e["out"])
		_update_morays(0.05, far)
		_update_octopuses(0.05, far, 0.0)
		for m: Dictionary in morays:
			moray_states[m["state"]] = float(moray_states.get(m["state"], 0.0)) + 0.05 / morays.size()
		for o: Dictionary in octopuses:
			octo_states[o["state"]] = float(octo_states.get(o["state"], 0.0)) + 0.05 / octopuses.size()
		for l: Dictionary in lionfish:
			_move_lionfish(l, 0.05, far, 0.0)
			var lp: Vector3 = l["pos"]
			lion_far = maxf(lion_far, Vector2(lp.x, lp.z).distance_to(l["c"]) - float(l["rad"]))
			lion_low = minf(lion_low, lp.y - float(_ls.ground(lp.x, lp.z)))
			if is_nan(lp.x + lp.y + lp.z):
				nan += 1
	for k in lionfish.size():
		lion_turned = maxf(lion_turned, absf(float(lionfish[k]["ang"]) - float(lion_start[k])))
	var moray_out := 0.0
	for m: Dictionary in morays:
		moray_out = maxf(moray_out, m["max_out"])
	res["alone"] = {"moray: seconds in each state (mean)": moray_states, "moray: furthest out (m)": moray_out, "octopus: seconds in each state (mean)": octo_states,
		"anemonefish: furthest from the middle (1 = edge of its space, 1.15 the limit)": fish_far, "anemonefish: highest (sea level 0)": fish_high,
		"eels: out, least and most": [eel_min, eel_max], "lionfish: furthest outside its circle (m)": lion_far, "lionfish: least height over the ground": lion_low,
		"lionfish: one at least has moved around its coral by (rad)": lion_turned, "nan": nan}
	# a swimmer over each of them for 12 s, then gone for 40 s
	var in_after := 0
	var out_again := 0
	var octo_back := 0
	var octo_again := 0
	for m: Dictionary in morays:
		m["state"] = "look"
		m["t"] = 100.0
		m["out"] = 0.35
	for o: Dictionary in octopuses:
		o["state"] = "den"
		o["k"] = 0.0
		o["back"] = 0.0
		o["t"] = 100.0
	for i in 240:
		for m: Dictionary in morays:
			_update_morays_one(m, 0.05, (m["pos"] as Vector3) + Vector3(0.5, 1.8, 0))
		for o: Dictionary in octopuses:
			_update_octopus_one(o, 0.05, (o["pos"] as Vector3) + Vector3(0.5, 1.8, 0))
	for m: Dictionary in morays:
		if float(m["out"]) < 0.08:
			in_after += 1
	for o: Dictionary in octopuses:
		if float(o["back"]) > 0.9:
			octo_back += 1
	for i in 800:
		_update_morays(0.05, far)
		_update_octopuses(0.05, far, 0.0)
	for m: Dictionary in morays:
		if float(m["out"]) > 0.15:
			out_again += 1
	for o: Dictionary in octopuses:
		if float(o["back"]) < 0.1:
			octo_again += 1
	var eels_in := 0
	var eels_all := 0
	var eels_again := 0
	for col: Dictionary in colonies:
		var c: Vector3 = col["pos"]
		for i in 200:
			for e: Dictionary in col["eels"]:
				_move_eel(e, 0.05, c + Vector3(0, 2.2, 0), false)
		for e: Dictionary in col["eels"]:
			eels_all += 1
			if float(e["out"]) < 0.3:
				eels_in += 1
		for i in 800:
			for e: Dictionary in col["eels"]:
				_move_eel(e, 0.05, far, false)
		for e: Dictionary in col["eels"]:
			if float(e["out"]) > 0.5:
				eels_again += 1
	res["with a swimmer over them"] = {"morays drawn back": "%d of %d" % [in_after, morays.size()], "morays out again 40 s later": out_again,
		"octopuses drawn back": "%d of %d" % [octo_back, octopuses.size()], "octopuses forward again 40 s later": octo_again,
		"eels sunk (a swimmer 2.2 m over the middle of the colony)": "%d of %d" % [eels_in, eels_all], "eels up again 40 s later": eels_again}
	_everybody = false
	return res


func _update_morays_one(m: Dictionary, delta: float, eye: Vector3) -> void:
	var all := morays
	morays = [m]
	_update_morays(delta, eye)
	morays = all


func _update_octopus_one(o: Dictionary, delta: float, eye: Vector3) -> void:
	var all := octopuses
	octopuses = [o]
	_update_octopuses(delta, eye, 0.0)
	octopuses = all


# ------------------------------------------------------------------ the giant grouper
## One giant grouper (Epinephelus lanceolatus, the biggest fish of the reef; shown 1.7 m long:
## they grow to 2.7 m). Its home is a patch of open sand at the foot of the reef, 4 to 6 m
## down, off the start beach: a dive brings a swimmer level with it. It hangs over the sand,
## sculling with its breast fins, and now and then moves a few meters to another place of its
## patch. It watches a swimmer who comes within 7 m, and when one comes within two and a
## half it moves aside, without haste; only crowded (nearer than 1.2 m) it gives one shove
## of the tail. At night it lies close to the sand. It never leaves home for long.
const GROUPER_LEN := 1.7
var grouper := {}


func _grouper_free(q: Vector2, r: float) -> bool:
	var y: float = _ls.ground(q.x, q.y)
	return y < -3.4 and y > -7.0 and _seabed.room(q, r, 1.0) and not _seabed.overhung(q, r)


func _place_grouper() -> void:
	var cands: Array = (_seabed.edge_spots as Array) + (_seabed.sand_spots as Array)
	var near := Vector2(50.0, 15.0)        # out from the start beach
	var best := Vector3.ZERO
	var best_r := 0.0
	for want: float in [3.2, 2.6, 2.1]:
		var best_d := 1e9
		for s: Vector3 in cands:
			var q := Vector2(s.x, s.z)
			var y: float = _ls.ground(q.x, q.y)
			if not ZONE.has_point(q) or y > -4.2 or y < -6.2 or not _grouper_free(q, want):
				continue
			var apart := true
			for c: Dictionary in colonies + morays + octopuses:
				if Vector2((c["pos"] as Vector3).x - q.x, (c["pos"] as Vector3).z - q.y).length() < 7.0:
					apart = false
			for l: Dictionary in lionfish:
				if (l["c"] as Vector2).distance_to(q) < 6.0:
					apart = false
			if apart and q.distance_to(near) < best_d:
				best_d = q.distance_to(near)
				best = Vector3(q.x, y, q.y)
				best_r = want
		if best_r > 0.0:
			break
	if best_r <= 0.0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Grouper"
	mi.mesh = load("res://scripts/sea_models.gd").giant_grouper()
	var m := _mat("res://shaders/sea_creature.gdshader")
	m.set_shader_parameter("species", 4)
	mi.material_override = m
	mi.extra_cull_margin = 1.0
	add_child(mi)
	var pos := best + Vector3(0, 1.0, 0)
	grouper = {"node": mi, "home": best, "roam": best_r - 1.0, "pos": pos, "yaw": _rng.randf() * TAU, "want": 0.0, "target": pos, "state": "hover",
		"t": _rng.randf_range(15.0, 40.0), "speed": 0.0, "phase": 0.0, "amp": 0.12, "bend": 0.0, "retarget": 0.0, "nearest": 1e9, "fastest": 0.0}
	grouper["want"] = grouper["yaw"]
	_pose_grouper()


func _pose_grouper() -> void:
	var g := grouper
	var mi: MeshInstance3D = g["node"]
	mi.global_transform = Transform3D(Basis(Vector3.UP, float(g["yaw"])).scaled(Vector3.ONE * (GROUPER_LEN / 3.6)), g["pos"])
	mi.set_instance_shader_parameter("phase", g["phase"])
	mi.set_instance_shader_parameter("amp", g["amp"])
	mi.set_instance_shader_parameter("bend", g["bend"])


## A place for the grouper to go to: in its patch, or (`from` given: somebody is too near) the
## free place furthest from them, a little way off but not far from home, with a free way to it.
func _grouper_goal(from: Variant = null) -> Vector3:
	var g := grouper
	var home: Vector3 = g["home"]
	var pos: Vector3 = g["pos"]
	var best := Vector3(home.x, 0, home.z)
	var best_d := -1.0
	for k in 14:
		var a := _rng.randf() * TAU
		var q := Vector2(home.x, home.z) + Vector2(cos(a), sin(a)) * (sqrt(_rng.randf()) * float(g["roam"]))
		if from != null and k >= 6:
			q = Vector2(pos.x, pos.z) + Vector2(cos(a), sin(a)) * _rng.randf_range(2.5, 4.0)
			if q.distance_to(Vector2(home.x, home.z)) > 9.0 or not _grouper_free(q, 1.1):
				continue
			var p0 := Vector2(pos.x, pos.z)
			if not _grouper_free(p0.lerp(q, 0.33), 0.9) or not _grouper_free(p0.lerp(q, 0.66), 0.9):
				continue
		var d := _rng.randf() if from == null else q.distance_to(Vector2((from as Vector3).x, (from as Vector3).z))
		if d > best_d:
			best_d = d
			best = Vector3(q.x, 0, q.y)
	return best


func _update_grouper(delta: float, eye: Vector3, night: float) -> void:
	if grouper.is_empty():
		return
	var g := grouper
	var pos: Vector3 = g["pos"]
	var to_eye := eye - pos
	var d := to_eye.length()
	if not _everybody and d > 50.0:
		return
	g["nearest"] = minf(float(g["nearest"]), d)
	g["t"] -= delta
	g["retarget"] -= delta
	var asleep := night > 0.6
	var home: Vector3 = g["home"]
	var want_speed := 0.0
	var turn := 0.35
	match g["state"]:
		"hover":
			if not asleep and d < 7.0:
				g["want"] = atan2(-to_eye.x, -to_eye.z)        # it turns to look at the swimmer
			if not asleep and d < 2.5:
				g["state"] = "away"
				g["target"] = _grouper_goal(eye)
				g["t"] = 30.0
			elif g["t"] <= 0.0:
				if asleep or Vector2(pos.x - home.x, pos.z - home.z).length() > float(g["roam"]) + 0.5:
					g["target"] = Vector3(home.x, 0, home.z) if not asleep else pos
				else:
					g["target"] = _grouper_goal()
				g["state"] = "move"
				g["t"] = 60.0
		"move", "away":
			var to := Vector3((g["target"] as Vector3).x - pos.x, 0, (g["target"] as Vector3).z - pos.z)
			if to.length() < 0.3 or g["t"] <= 0.0:
				g["state"] = "hover"
				g["t"] = _rng.randf_range(20.0, 55.0) if d > 8.0 else _rng.randf_range(6.0, 12.0)
			else:
				g["want"] = atan2(-to.x, -to.z)
				want_speed = 0.2
				if g["state"] == "away":
					want_speed = 0.38 if d > 1.3 else 1.3
					turn = 0.7 if d > 1.2 else 1.4
			if not asleep and d < 2.5 and float(g["retarget"]) <= 0.0:
				# still (or again) too near: the place furthest from them
				g["state"] = "away"
				g["target"] = _grouper_goal(eye)
				g["retarget"] = 2.0
				g["t"] = 30.0
	var yaw: float = g["yaw"]
	var diff := angle_difference(yaw, float(g["want"]))
	var dyaw := clampf(diff, -turn * delta, turn * delta)
	yaw += dyaw
	g["yaw"] = yaw
	g["speed"] = move_toward(float(g["speed"]), want_speed * (1.0 - clampf(absf(diff) / 1.6, 0.0, 0.75)), delta * (0.8 if want_speed > 0.5 else 0.2))
	var speed: float = g["speed"]
	g["fastest"] = maxf(float(g["fastest"]), speed)
	pos += Vector3(-sin(yaw), 0, -cos(yaw)) * (speed * delta)
	var floor_y: float = _ls.ground(pos.x, pos.z)
	pos.y = move_toward(pos.y, floor_y + (0.42 if asleep else 0.95 + 0.08 * sin(_time * 0.21)), delta * 0.12)
	pos.y = maxf(pos.y, floor_y + 0.38)
	g["pos"] = pos
	g["phase"] = fmod(float(g["phase"]) + delta * (1.1 + speed * 7.0), TAU * 16.0)
	g["amp"] = lerpf(float(g["amp"]), lerpf(0.1, 0.95, clampf(speed / 0.45, 0.0, 1.0)), 1.0 - exp(-2.0 * delta))
	g["bend"] = lerpf(float(g["bend"]), clampf(-dyaw / maxf(delta, 0.001) * 0.5, -0.5, 0.5), 1.0 - exp(-3.0 * delta))
	_pose_grouper()


func grouper_report() -> Dictionary:
	if grouper.is_empty():
		return {"grouper": "no home found"}
	return {"home": grouper["home"], "room (m)": float(grouper["roam"]) + 1.0, "at": grouper["pos"], "state": grouper["state"],
		"from home (m)": Vector2((grouper["pos"] as Vector3).x - (grouper["home"] as Vector3).x, (grouper["pos"] as Vector3).z - (grouper["home"] as Vector3).z).length(),
		"nearest a swimmer has been (m)": grouper["nearest"], "fastest (m/s)": grouper["fastest"]}


## The grouper's life in a moment. `swimmer`: 0 nobody; 1 somebody hangs 1.5 m from its home
## and circles it slowly; 2 somebody swims straight at it again and again at a snorkeler's pace.
func grouper_soak(seconds := 1800.0, swimmer := 0) -> Dictionary:
	if grouper.is_empty():
		return {"grouper": "no home found"}
	_everybody = true
	var g := grouper
	g["nearest"] = 1e9
	g["fastest"] = 0.0
	var home: Vector3 = g["home"]
	var dt := 0.05
	var bad := 0
	var far := 0.0
	var way := 0.0
	var states := {}
	var eye := Vector3(1e5, 0, 0)
	var last: Vector3 = g["pos"]
	for s in int(seconds / dt):
		var t := s * dt
		if swimmer == 1:
			eye = home + Vector3(cos(t * 0.05) * 1.5, 1.0, sin(t * 0.05) * 1.5)
		elif swimmer == 2:
			var gp: Vector3 = g["pos"]
			eye = gp + Vector3(8.0, 0, 0) if s == 0 or eye.distance_to(gp) > 12.0 else eye + (gp - eye).normalized() * (1.1 * dt)
		_update_grouper(dt, eye, 0.0)
		var p: Vector3 = g["pos"]
		way += p.distance_to(last)
		last = p
		far = maxf(far, Vector2(p.x - home.x, p.z - home.z).length())
		if s % 10 == 0:
			states[g["state"]] = int(states.get(g["state"], 0)) + 1
			if not _grouper_free(Vector2(p.x, p.z), 0.7):
				bad += 1
	_everybody = false
	return {"states": states, "swum (m)": way, "furthest from home (m)": far, "samples with a coral within 0.7 m": bad,
		"nearest the swimmer came (m)": g["nearest"], "fastest (m/s)": g["fastest"]}


# ------------------------------------------------------------------ triggerfish
## Two triggerfish, each alone in a territory of its own on the reef off the start beach: a
## titan triggerfish (Balistoides viridescens, the biggest of them: 0.7 m) in the shallower
## reef of the lagoon, and a clown triggerfish (Balistoides conspicillum: black with big
## white spots, 0.45 m) further out where it is deeper. A triggerfish swims with the fin on
## its back and the one below, the body stiff. It cruises over the corals from place to
## place, and every so often tips head down over a bit of open floor to pick at it. It
## keeps two to three meters from a swimmer, swimming off without haste. At night it rests
## low beside its reef. (The titan's attacks on divers near its nest are left out: nothing
## here is to frighten.)
var triggers: Array = []


## The lowest a triggerfish may be at p: above the floor and whatever stands there.
func _trig_floor(p: Vector3) -> float:
	return float(_seabed.top_at(Vector2(p.x, p.z), 1.0))


## Water enough over p for a fish to pass (at low water the tops of the corals come near the
## surface), and not too deep or too shallow a floor.
func _trig_ok(t: Dictionary, q: Vector2) -> bool:
	var y: float = _ls.ground(q.x, q.y)
	if y > -2.0 or y < -8.0:
		return false
	# (not over the garden eels' colonies: they would all be down their burrows; nor into
	# the grouper's patch)
	for c: Dictionary in colonies:
		if Vector2((c["pos"] as Vector3).x - q.x, (c["pos"] as Vector3).z - q.y).length() < 5.5:
			return false
	if not grouper.is_empty() and Vector2((grouper["home"] as Vector3).x - q.x, (grouper["home"] as Vector3).z - q.y).length() < 5.5:
		return false
	return float(_seabed.top_at(q, 1.0)) + 0.45 < float(_ls.sea) - 0.55 and q.distance_to(t["home"]) < float(t["range"]) + 1.0


func _place_triggerfish() -> void:
	var mesh: ArrayMesh = load("res://scripts/sea_models.gd").triggerfish()
	var cands: Array = (_seabed.edge_spots as Array) + (_seabed.sand_spots as Array)
	# [species, length, about where, depth of the floor from .. to]
	for spec: Array in [[5, 0.7, Vector2(40.0, -22.0), -2.6, -4.6], [6, 0.45, Vector2(68.0, 44.0), -4.2, -6.6]]:
		var best := Vector2.ZERO
		var best_d := 1e9
		for s: Vector3 in cands:
			var q := Vector2(s.x, s.z)
			if not ZONE.has_point(q) or s.y > float(spec[3]) or s.y < float(spec[4]):
				continue
			var apart := true
			if not grouper.is_empty() and Vector2((grouper["home"] as Vector3).x, (grouper["home"] as Vector3).z).distance_to(q) < 18.0:
				apart = false
			for o: Dictionary in triggers:
				if (o["home"] as Vector2).distance_to(q) < 24.0:
					apart = false
			for c: Dictionary in colonies:
				if Vector2((c["pos"] as Vector3).x - q.x, (c["pos"] as Vector3).z - q.y).length() < 11.0:
					apart = false
			if apart and q.distance_to(spec[2]) < best_d:
				best_d = q.distance_to(spec[2])
				best = q
		if best_d > 1e8:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Triggerfish%d" % triggers.size()
		mi.mesh = mesh
		var m := _mat("res://shaders/sea_creature.gdshader")
		m.set_shader_parameter("species", int(spec[0]))
		mi.material_override = m
		mi.extra_cull_margin = 0.5
		add_child(mi)
		var pos := Vector3(best.x, float(_ls.ground(best.x, best.y)) + 0.9, best.y)
		var t := {"node": mi, "species": int(spec[0]), "len": float(spec[1]), "home": best, "range": 9.0, "pos": pos, "yaw": _rng.randf() * TAU, "pitch": 0.0,
			"target": pos, "state": "cruise", "t": _rng.randf_range(4.0, 12.0), "speed": 0.0, "phase": _rng.randf() * TAU, "bend": 0.0, "h": 0.6,
			"nearest": 1e9, "fastest": 0.0, "feeds": 0, "look": 0.0}
		triggers.append(t)
		_trig_goal(t, null)
		_pose_trigger(t)


func _pose_trigger(t: Dictionary) -> void:
	var mi: MeshInstance3D = t["node"]
	var b := Basis(Vector3.UP, float(t["yaw"])) * Basis(Vector3.RIGHT, float(t["pitch"]))
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * (float(t["len"]) / 3.6)), t["pos"])
	mi.set_instance_shader_parameter("phase", t["phase"])
	mi.set_instance_shader_parameter("amp", 1.0)
	mi.set_instance_shader_parameter("bend", t["bend"])


## Where to swim next: somewhere in its territory with water enough over it; with a swimmer
## too near (`from`), the such place furthest from them.
func _trig_goal(t: Dictionary, from: Variant) -> void:
	var home: Vector2 = t["home"]
	var best := home
	var best_d := -1.0
	for k in 12:
		var a := _rng.randf() * TAU
		var q := home + Vector2(cos(a), sin(a)) * (sqrt(_rng.randf()) * float(t["range"]))
		if not _trig_ok(t, q):
			continue
		var d := _rng.randf() if from == null else q.distance_to(Vector2((from as Vector3).x, (from as Vector3).z))
		if d > best_d:
			best_d = d
			best = q
	t["target"] = Vector3(best.x, 0, best.y)


func _update_triggerfish(delta: float, eye: Vector3, night: float) -> void:
	for t: Dictionary in triggers:
		_update_trigger(t, delta, eye, night)


func _update_trigger(t: Dictionary, delta: float, eye: Vector3, night: float) -> void:
	var pos: Vector3 = t["pos"]
	var d := pos.distance_to(eye)
	if not _everybody and d > 50.0:
		return
	t["nearest"] = minf(float(t["nearest"]), d)
	t["t"] -= delta
	t["look"] -= delta
	var asleep := night > 0.6
	var shy := d < 2.8 and not asleep
	var want_speed := 0.0
	var want_h := 0.6
	var want_pitch := 0.0
	var to := Vector3((t["target"] as Vector3).x - pos.x, 0, (t["target"] as Vector3).z - pos.z)
	match t["state"]:
		"cruise", "away":
			want_speed = 0.34 if t["state"] == "cruise" else 0.75
			if shy and (t["state"] == "cruise" or float(t["look"]) <= -1.2):
				# (and again every second and a half while they stay so near)
				t["state"] = "away"
				_trig_goal(t, eye)
				t["t"] = 12.0
				t["look"] = 0.3
			elif to.length() < 0.5 or t["t"] <= 0.0:
				if asleep:
					t["state"] = "rest"
				elif t["state"] == "cruise" and _rng.randf() < 0.55 and _grouper_free(Vector2(pos.x, pos.z), 0.55):
					# a bit of open floor under it: head down, and at it
					t["state"] = "feed"
					t["t"] = _rng.randf_range(5.0, 12.0)
					t["feeds"] = int(t["feeds"]) + 1
				else:
					t["state"] = "cruise"
					_trig_goal(t, eye if shy else null)
					t["t"] = _rng.randf_range(15.0, 35.0)
			elif float(t["look"]) <= 0.0 and (not shy or t["state"] == "cruise"):
				t["look"] = 0.3
				# the way ahead: water enough over the corals there?
				var fwd := to.normalized()
				if not _trig_ok(t, Vector2(pos.x + fwd.x * 1.2, pos.z + fwd.z * 1.2)):
					_trig_goal(t, eye if shy else null)
		"feed":
			want_h = 0.3
			want_pitch = -0.95
			if shy or asleep or t["t"] <= 0.0:
				t["state"] = "away" if shy else "cruise"
				_trig_goal(t, eye if shy else null)
				t["t"] = _rng.randf_range(12.0, 30.0)
		"rest":
			want_h = 0.3
			if not asleep:
				t["state"] = "cruise"
				_trig_goal(t, null)
				t["t"] = 20.0
	var yaw: float = t["yaw"]
	var dyaw := 0.0
	if want_speed > 0.0 and to.length() > 0.05:
		var diff := angle_difference(yaw, atan2(-to.x, -to.z))
		dyaw = clampf(diff, -1.3 * delta, 1.3 * delta)
		yaw += dyaw
		want_speed *= 1.0 - clampf(absf(diff) / 1.4, 0.0, 0.8)
	t["yaw"] = yaw
	# over whatever stands here and just ahead; never up into the last half meter under the surface
	var fwd3 := Vector3(-sin(yaw), 0, -cos(yaw))
	var floor_y := maxf(_trig_floor(pos), _trig_floor(pos + fwd3 * 0.7))
	var want_y := minf(floor_y + want_h + 0.12 * float(t["len"]), float(_ls.sea) - 0.5)
	var low := pos.y < _trig_floor(pos) + 0.2
	if low:
		want_speed *= 0.25         # (up first, then on)
	t["speed"] = move_toward(float(t["speed"]), want_speed, delta * 0.5)
	var speed: float = t["speed"]
	t["fastest"] = maxf(float(t["fastest"]), speed)
	var vy := clampf((want_y - pos.y) * 2.0, -0.35, 0.6)
	pos += fwd3 * (speed * delta) + Vector3(0, vy * delta, 0)
	t["pos"] = pos
	if t["state"] != "feed":
		want_pitch = clampf(atan2(vy, maxf(speed, 0.15)) * 0.7, -0.5, 0.5)
	t["pitch"] = lerpf(float(t["pitch"]), want_pitch, 1.0 - exp(-2.2 * delta))
	t["phase"] = fmod(float(t["phase"]) + delta * (2.5 + speed * 14.0) * (0.3 if t["state"] == "rest" else 1.0), TAU * 16.0)
	t["bend"] = lerpf(float(t["bend"]), clampf(-dyaw / maxf(delta, 0.001) * 0.25, -0.4, 0.4), 1.0 - exp(-4.0 * delta))
	_pose_trigger(t)


func trigger_report() -> Array:
	var out: Array = []
	for t: Dictionary in triggers:
		out.append({"species": "titan" if t["species"] == 5 else "clown", "home": t["home"], "at": t["pos"], "state": t["state"], "fed": t["feeds"],
			"nearest a swimmer has been (m)": t["nearest"], "fastest (m/s)": t["fastest"]})
	return out


## Their lives in a moment. `swimmer`: 0 nobody, 1 somebody hangs in the middle of each
## one's territory in turn, at its depth.
func trigger_soak(seconds := 1800.0, swimmer := 0) -> Dictionary:
	_everybody = true
	var dt := 0.05
	var in_coral := 0
	var too_high := 0
	var astray := 0
	var samples := 0
	var way := 0.0
	var states := {}
	for t: Dictionary in triggers:
		t["nearest"] = 1e9
		t["fastest"] = 0.0
		var last: Vector3 = t["pos"]
		var home: Vector2 = t["home"]
		for s in int(seconds / dt):
			var eye := Vector3(1e5, 0, 0)
			if swimmer == 1:
				eye = Vector3(home.x + cos(s * dt * 0.03) * 3.0, float(_ls.ground(home.x, home.y)) + 1.2, home.y + sin(s * dt * 0.03) * 3.0)
			_update_trigger(t, dt, eye, 0.0)
			var p: Vector3 = t["pos"]
			way += p.distance_to(last)
			last = p
			if s % 10 == 0:
				samples += 1
				states[t["state"]] = int(states.get(t["state"], 0)) + 1
				if p.y < float(_seabed.top_at(Vector2(p.x, p.z), 0.0)) + 0.1:
					in_coral += 1
				if p.y > float(_ls.sea) - 0.3:
					too_high += 1
				if Vector2(p.x, p.z).distance_to(home) > float(t["range"]) + 3.0:
					astray += 1
	_everybody = false
	return {"samples": samples, "states": states, "swum (m)": way, "samples in a coral or the floor": in_coral, "samples at the surface": too_high,
		"samples far from home": astray, "now": trigger_report()}
