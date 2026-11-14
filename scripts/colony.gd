extends Node3D
## Seabird colony in the Pisonia grove on the wooded southern headland: brown noddies
## sitting on their nests and white terns perched on bare twigs, a crowd of birds wheeling
## over the trees (some commute out to sea to fish and come back, some come in to land, some
## take off), male frigatebirds displaying their red throat sacs in the treetops, now and then
## frigatebirds soaring from thermal to thermal high above, and the colony's racket. All of them fly on the shared flight model (flight.gd).

const A := "res://assets/audio/"
const Flight := preload("res://scripts/flight.gd")

@export var player_path: NodePath = ^"../Player"
@export var flyer_count := 30

var _player: Node3D
var _ls: Node
var _amb: Node
var _rng := RandomNumberGenerator.new()
var _center := Vector3.ZERO
var _ground_y := 0.0
var _models := {}            # name -> Node3D template
var _perches: Array = []     # {"pos", "yaw", "node", "kind", "nest"}
var nests: Array = []        # the nests' nodes (for the tests)
var _flyers: Array = []
var _frigates: Array = []
var _frigate_timer := 40.0
var _calls: Array[AudioStream] = []
var _call_players: Array[AudioStreamPlayer3D] = []
var _call_timer := 1.0
var _loops: Array[AudioStreamPlayer3D] = []
var _ready_done := false


func _ready() -> void:
	_rng.randomize()
	_player = get_node_or_null(player_path)
	# the landscape is built in the root's _ready (after ours): set up afterward
	_setup.call_deferred()


func _setup() -> void:
	_ls = get_node_or_null("../Landscape")
	_amb = get_node_or_null("../Ambience")
	if _ls == null:
		return
	var c2: Vector2 = _ls.colony_center
	_ground_y = _ls.ground(c2.x, c2.y)
	_center = Vector3(c2.x, _ground_y, c2.y)
	var scene := load("res://assets/models/seabirds.glb") as PackedScene
	var tmp := scene.instantiate()
	for n in ["Noddy", "WhiteTern", "Frigate", "FrigateF", "NoddyPerched", "WhiteTernPerched", "Nest", "TernEgg"]:
		var node := tmp.find_child(n, true, false) as Node3D
		if node:
			_models[n] = node
	_build_perches()
	_setup_displays()
	for i in flyer_count:
		_flyers.append(_new_flyer("Noddy" if i % 3 != 0 else "WhiteTern", true))
	# sound: two long loops of the colony and single calls from the nests
	for i in 2:
		var p := AudioStreamPlayer3D.new()
		p.stream = _loop("colony_a.wav" if i == 0 else "colony_b.wav")
		p.unit_size = 16.0
		p.max_distance = 320.0
		p.volume_db = -4.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		p.global_position = _center + Vector3(-8.0 + 16.0 * i, 9.0, _rng.randf_range(-6, 6))
		p.play(_rng.randf() * 30.0)
		_loops.append(p)
	for f in ["noddy_%d.wav", "colony_call_%d.wav"]:
		for i in 10:
			var path: String = A + f % i
			if ResourceLoader.exists(path):
				_calls.append(load(path))
	for i in 5:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 7.0
		p.max_distance = 120.0
		add_child(p)
		_call_players.append(p)
	_ready_done = true


func _loop(file: String) -> AudioStream:
	var s := load(A + file) as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _instance(n: String) -> Node3D:
	var m: Node3D = (_models[n] as Node3D).duplicate()
	m.transform = Transform3D.IDENTITY
	get_parent()._apply_materials(m)   # the plumage shaders (world.gd)
	for gi in m.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m is GeometryInstance3D:
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# ------------------------------------------------------------------ nests and perched birds
## Where a nest or a bird can sit in a tree of this kind (tree coordinates, in cells of 2 m):
## the middles of the bark's faces that look up, which is the upper side of a limb that does
## not rise too steeply, and the crotch of a fork. (Until 2026-11-13 a nest went to the nearest
## point of bark whichever way it faced: on a trunk or a steep limb that is its side, the wood
## went through the nest and the sitting bird was inside it.)
var _seats := {}
var old_seats := false        # (for the tests: how it was)
var open_seats := true        # prefer places that show from below (for the tests: without)
var seat_stats := {"asked": 0, "seated": 0, "no seat": 0}


func _limb_seats(kind: String) -> Dictionary:
	if _seats.has(kind):
		return _seats[kind]
	var cells := {}
	var mesh := _ls._tree_parts.get(kind + "Bark") as Mesh
	if mesh:
		var f := mesh.get_faces()
		# which way the faces are wound: for a closed skin the outward normals, each times its
		# face's place, add up to something positive (three times the volume)
		var sum := 0.0
		for t in range(0, f.size(), 3):
			sum += ((f[t] + f[t + 1] + f[t + 2]) / 3.0).dot((f[t + 1] - f[t]).cross(f[t + 2] - f[t]))
		var sgn := 1.0 if sum > 0.0 else -1.0
		for t in range(0, f.size(), 3):
			var n := (f[t + 1] - f[t]).cross(f[t + 2] - f[t]) * sgn
			if n.length() < 1e-9 or n.normalized().y < 0.72:
				continue
			var mid := (f[t] + f[t + 1] + f[t + 2]) / 3.0
			var c := Vector3i(floori(mid.x * 0.5), floori(mid.y * 0.5), floori(mid.z * 0.5))
			if not cells.has(c):
				cells[c] = []
			(cells[c] as Array).append(mid)
	_seats[kind] = cells
	return cells


## A tree kind's bark as triangles, sorted into columns of half a meter (tree coordinates):
## to ask quickly whether a point is inside the wood.
var _columns := {}


func _wood_columns(kind: String) -> Dictionary:
	if _columns.has(kind):
		return _columns[kind]
	var grid := {}
	var faces := PackedVector3Array()
	var mesh := _ls._tree_parts.get(kind + "Bark") as Mesh
	if mesh:
		faces = mesh.get_faces()
		for t in range(0, faces.size(), 3):
			var a := faces[t]
			var b := faces[t + 1]
			var c := faces[t + 2]
			for cx in range(floori(minf(a.x, minf(b.x, c.x)) * 2.0), floori(maxf(a.x, maxf(b.x, c.x)) * 2.0) + 1):
				for cz in range(floori(minf(a.z, minf(b.z, c.z)) * 2.0), floori(maxf(a.z, maxf(b.z, c.z)) * 2.0) + 1):
					var key := Vector2i(cx, cz)
					if not grid.has(key):
						grid[key] = []
					(grid[key] as Array).append(t)
	_columns[kind] = {"faces": faces, "grid": grid}
	return _columns[kind]


## Is this point (tree coordinates) inside the wood of a tree of this kind? A ray straight up
## from it goes through the bark's skin an odd number of times.
func _in_wood(kind: String, q: Vector3) -> bool:
	var col := _wood_columns(kind)
	var faces: PackedVector3Array = col["faces"]
	var n := 0
	for t: int in (col["grid"] as Dictionary).get(Vector2i(floori(q.x * 2.0), floori(q.z * 2.0)), []):
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 1e-12:
			continue
		var u := ((b.z - c.z) * (q.x - c.x) + (c.x - b.x) * (q.z - c.z)) / d
		var v := ((c.z - a.z) * (q.x - c.x) + (a.x - c.x) * (q.z - c.z)) / d
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		if u * a.y + v * b.y + (1.0 - u - v) * c.y > q.y:
			n += 1
	return n % 2 == 1


## Would a nest or a bird at this place (world) have wood through it: its own tree's, or a
## neighbor's limb? The middle of the body and six points around it (a nest's rim: `wide`).
func _body_in_wood(at: Vector3, wide: float, up: float) -> bool:
	var pts: Array = [at + Vector3(0, up, 0)]
	for i in 6:
		pts.append(at + Vector3(cos(i * 1.047) * wide, up * 0.7 + 0.03, sin(i * 1.047) * wide))
		if wide > 0.15:    # (a nest: its rim lower down and a little further in as well)
			pts.append(at + Vector3(cos(i * 1.047 + 0.5) * wide * 0.8, 0.07, sin(i * 1.047 + 0.5) * wide * 0.8))
	for t: Dictionary in _ls.tree_spots:
		if not t["colony"] or not _ls._tree_parts.has(String(t["kind"]) + "Bark"):
			continue
		var txf: Transform3D = t["xf"]
		if Vector2(txf.origin.x - at.x, txf.origin.z - at.z).length() > 9.0:
			continue
		var inv := txf.affine_inverse()
		for q: Vector3 in pts:
			if _in_wood(t["kind"], inv * q):
				return true
	return false


## Where a tree kind has leaves: the cells of half a meter (tree coordinates) that hold any.
## From the sparser leaf mesh, which is quick to go through and covers the same crown.
var _leaf_cells := {}


func _leaves(kind: String) -> Dictionary:
	if _leaf_cells.has(kind):
		return _leaf_cells[kind]
	var cells := {}
	var mesh := _ls._tree_parts.get(kind + "Leaves_lod", _ls._tree_parts.get(kind + "Leaves")) as Mesh
	if mesh:
		var f := mesh.get_faces()
		for t in range(0, f.size(), 3):
			var v := f[t]
			cells[Vector3i(floori(v.x * 2.0), floori(v.y * 2.0), floori(v.z * 2.0))] = true
	_leaf_cells[kind] = cells
	return cells


## How much foliage hangs between this place (tree coordinates) and someone looking up at it
## from the ground: the cells with leaves in the three by three columns below it. A nest on a
## fork under the crown has none or few: it shows from below, as the noddies' nests do.
func _leaves_below(kind: String, at: Vector3) -> int:
	var cells := _leaves(kind)
	var c := Vector3i(floori(at.x * 2.0), floori(at.y * 2.0), floori(at.z * 2.0))
	var n := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(1, 16):
				if cells.has(c + Vector3i(dx, -dy, dz)):
					n += 1
	return n


## Is there wood in the space a sitting bird needs above this place (tree coordinates)?
func _wood_above(kind: String, at: Vector3, wide: float) -> bool:
	var cells: Dictionary = _ls._bark_cells.get(kind + "Bark", {})
	var c := Vector3i(floori(at.x * 0.5), floori(at.y * 0.5), floori(at.z * 0.5))
	for dx in range(-1, 2):
		for dy in range(0, 2):
			for dz in range(-1, 2):
				var cell: Variant = cells.get(c + Vector3i(dx, dy, dz))
				if cell == null:
					continue
				for v: Vector3 in cell:
					if v.y > at.y + 0.1 and v.y < at.y + 0.5 and Vector2(v.x - at.x, v.z - at.z).length() < wide:
						return true
	return false


## The place to sit nearest to `local` (tree coordinates), in world space: on the upper side of
## a limb, with nothing above it, and not where another sits already (`taken`, tree
## coordinates; the place found is added). `wide`: how much room it needs (a nest more than a
## tern). Returns Vector3.INF when the tree has no such place within reach: then nothing is
## put there (better no nest than one in the air or in the wood).
func _seat(xf: Transform3D, kind: String, local: Vector3, wide: float, taken: Array) -> Vector3:
	seat_stats["asked"] += 1
	if old_seats:
		return _on_wood(xf, kind, local)
	var cells := _limb_seats(kind)
	var c := Vector3i(floori(local.x * 0.5), floori(local.y * 0.5), floori(local.z * 0.5))
	var near: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var cell: Variant = cells.get(c + Vector3i(dx, dy, dz))
				if cell != null:
					near.append_array(cell)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(local) < b.distance_squared_to(local))
	# First the nearest place that shows from below (hardly a leaf under it); failing that,
	# the nearest of any.
	for open_only: bool in ([true, false] if open_seats else [false]):
		var tried := 0
		for v: Vector3 in near:
			if v.distance_to(local) > (3.2 if open_only else 2.6):
				break
			if open_only and _leaves_below(kind, v) > 1:
				continue
			var free := true
			for o: Vector3 in taken:
				if o.distance_to(v) < wide * 2.2:
					free = false
					break
			if not free:
				continue
			tried += 1
			if tried > 40:
				break
			if _wood_above(kind, v, wide) or _body_in_wood(xf * v, wide * 1.15 if wide > 0.15 else 0.05, 0.12 if wide > 0.15 else 0.08):
				continue
			taken.append(v)
			seat_stats["seated"] += 1
			if open_only:
				seat_stats["open below"] = int(seat_stats.get("open below", 0)) + 1
			return xf * v
	seat_stats["no seat"] += 1
	return Vector3.INF


## (As it was until 2026-11-13, kept for the tests: `old_seats`.) The point of bark nearest to
## `local`, in world space; falls back to `local` if the tree has no wood near it.
func _on_wood(xf: Transform3D, kind: String, local: Vector3) -> Vector3:
	var cells: Dictionary = _ls._bark_cells.get(kind + "Bark", {})
	var c := Vector3i(floori(local.x * 0.5), floori(local.y * 0.5), floori(local.z * 0.5))
	var near: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var cell: Variant = cells.get(c + Vector3i(dx, dy, dz))
				if cell != null:
					near.append(cell)
	var best := local
	var bd := 1e9
	for cell in near:
		for v: Vector3 in cell:
			var d := v.distance_squared_to(local)
			if d < bd:
				bd = d
				best = v
	if bd > 1e8:
		return xf * local
	# the upper side of that branch: the highest bark within a hand's breadth of the spot
	var top := best
	for cell in near:
		for v: Vector3 in cell:
			if v.y > top.y and v.y - best.y < 0.3 and Vector2(v.x - best.x, v.z - best.z).length() < 0.07:
				top = v
	return xf * top


## (For the tests.) The trees' nests and birds built anew from the same random numbers, the
## old way or the new: to count how many had wood through them. Birds on the wing may still
## know the old places: ask and measure in one go, then end the run.
func rebuild_perches(old: bool, seed_ := 7, open := true) -> Dictionary:
	open_seats = open
	var r := get_node_or_null("Nests")
	if r:
		remove_child(r)
		r.free()
	_perches.clear()
	nests.clear()
	old_seats = old
	seat_stats = {"asked": 0, "seated": 0, "no seat": 0}
	_rng.seed = seed_
	_build_perches()
	return seat_stats.duplicate()


func _build_perches() -> void:
	var f := FileAccess.open("res://assets/models/tree_tips.json", FileAccess.READ)
	if f == null:
		return
	var tips: Dictionary = JSON.parse_string(f.get_as_text())
	var root := Node3D.new()
	root.name = "Nests"
	add_child(root)
	for t in _ls.tree_spots:
		if not t["colony"] or not tips.has(t["kind"]):
			continue
		var xf: Transform3D = t["xf"]
		var taken: Array = []          # the places taken in this tree
		for tip in tips[t["kind"]]:
			var r: float = tip[3]
			var local := Vector3(tip[0], tip[1], tip[2])
			var out := Vector3(local.x, 0, local.z).normalized()
			var out_w: Vector3 = (xf.basis * out).normalized()   # away from the trunk: the side a bird comes in from
			var roll := _rng.randf()
			if roll < 0.55:
				# a noddy nest on a fork inside the outer canopy, its owner sitting on it
				var p: Vector3 = _seat(xf, t["kind"], local + out * r * 0.45 - Vector3.UP * r * 0.75, 0.2, taken)
				# (the same numbers are drawn whether a place was found or not)
				var nest_xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(1.2, 1.6)), p)
				var yaw := _rng.randf() * TAU
				var sits := _rng.randf() < 0.85
				if p == Vector3.INF:
					continue
				var nest := _instance("Nest")
				root.add_child(nest)
				nest.global_transform = nest_xf
				nests.append(nest)
				var bird: Node3D = null
				if sits:
					bird = _instance("NoddyPerched")
					root.add_child(bird)
					bird.global_transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 0.07)
				_perches.append({"pos": p + Vector3.UP * 0.07, "yaw": yaw, "node": bird, "kind": "NoddyPerched", "out": out_w})
			elif roll < 0.8:
				# white terns lay their single egg straight onto a bare branch: no nest at all
				var p: Vector3 = _seat(xf, t["kind"], local + out * r * 0.95 - Vector3.UP * r * 0.45, 0.1, taken)
				var yaw := _rng.randf() * TAU
				var sits := _rng.randf() < 0.75
				var egg_there := not sits and _rng.randf() < 0.5
				if p == Vector3.INF:
					continue
				var bird: Node3D = null
				if sits:
					bird = _instance("WhiteTernPerched")
					root.add_child(bird)
					bird.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
				elif egg_there:
					var egg := _instance("TernEgg")
					root.add_child(egg)
					egg.global_position = p
				_perches.append({"pos": p, "yaw": yaw, "node": bird, "kind": "WhiteTernPerched", "out": out_w})


# ------------------------------------------------------------------ flying birds
## Flight envelopes (see flight.gd): "beat" is the wing-beat rate in Hz.
## "tail": how far the tail halves open (a wedge or shallow fork only fans a little).
const NODDY := {"cruise": 9.5, "max_bank": 0.9, "roll": 3.4, "climb": 2.4, "sink": 3.5, "beat": 3.5, "tail": 0.25}
const WHITE_TERN := {"cruise": 8.3, "max_bank": 1.0, "roll": 3.8, "climb": 2.6, "sink": 3.2, "beat": 4.2, "tail": 0.3}
const FRIGATE := {"cruise": 9.5, "max_bank": 0.5, "roll": 1.1, "climb": 0.9, "sink": 0.9, "beat": 2.2}


func _wind(height: float) -> Vector3:
	return Flight.wind(_amb.gust if _amb else 1.0, height)


func _new_flyer(kind: String, airborne: bool) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var m := _instance(kind)
	root.add_child(m)
	var wings := Flight.wings(m, kind, kind + "WingL", kind + "WingR", get_parent(), false)
	var spec: Dictionary = NODDY if kind == "Noddy" else WHITE_TERN
	var c := _center + Vector3(_rng.randf_range(-15, 15), _rng.randf_range(10, 34), _rng.randf_range(-15, 15))
	var radius := _rng.randf_range(12.0, 38.0)
	var a := _rng.randf() * TAU
	var turn := 1.0 if _rng.randf() < 0.5 else -1.0
	var pos := c + Vector3(cos(a), 0, sin(a)) * radius
	var d := {
		"node": root, "model": m, "kind": kind, "wings": wings, "tail": Flight.tail_of(m, kind), "spec": spec, "state": "mill",
		"b": Flight.make(pos, Flight.yaw_of(Vector3(-sin(a), 0, cos(a)) * turn), spec["cruise"]),
		"c": c, "radius": radius, "turn": turn, "sea": false, "dest": Vector3.ZERO,
		"flap": _rng.randf() * TAU, "amp": 0.6, "glide": _rng.randf_range(-2.0, 1.0), "beats": -3.0,
		"pitch": 0.0, "seed": _rng.randf() * TAU,
		"timer": _rng.randf_range(8.0, 40.0), "perch": -1, "vel": Vector3.ZERO,
	}
	if airborne:
		root.global_position = pos
	return d


## Point to fly at to hold a circle of the bird's radius round `c`: a little way ahead on the circle.
func _circle_goal(d: Dictionary, c: Vector3) -> Vector3:
	var pos: Vector3 = d["b"]["pos"]
	var a := atan2(pos.z - c.z, pos.x - c.x) + float(d["turn"]) * 0.6
	var r: float = d["radius"]
	return Vector3(c.x + cos(a) * r, c.y + sin(Time.get_ticks_msec() * 0.0004 + float(d["seed"])) * 2.5, c.z + sin(a) * r)


## Lifts a goal clear of the treetops on the land below and just ahead (the grove's trees stand
## 9-11 m tall), so a bird coming in low from the sea climbs before it reaches the shore.
func _clear_trees(goal: Vector3, b: Dictionary) -> Vector3:
	var pos: Vector3 = b["pos"]
	var ahead: Vector3 = pos + Flight.forward(b["yaw"]) * 25.0
	var g: float = maxf(maxf(_ls.ground(pos.x, pos.z), _ls.ground(goal.x, goal.z)), _ls.ground(ahead.x, ahead.z))
	if g > 0.3:
		goal.y = maxf(goal.y, g + 13.5)
	return goal


func _update_flyers(delta: float, night: float) -> void:
	for d in _flyers:
		var n: Node3D = d["node"]
		var b: Dictionary = d["b"]
		var spec: Dictionary = d["spec"]
		var pos: Vector3 = b["pos"]
		var w := _wind(pos.y - _ground_y)
		d["timer"] -= delta
		var effort := 0.0
		var pitch := 0.0
		var flapping := true
		var cruising := false
		match d["state"]:
			"mill":
				# wheeling over the trees, or over a patch of sea when it is out fishing
				var c: Vector3 = d["c"]
				var goal := _circle_goal(d, c)
				if d["sea"]:
					# quartering low over the water, dipping to the surface now and then
					goal.y = 3.5 + 2.8 * sin(Time.get_ticks_msec() * 0.0011 + float(d["seed"]))
				Flight.steer(b, _clear_trees(goal, b), delta, w, spec)
				cruising = true
				if d["timer"] <= 0.0 or night > 0.6:
					d["timer"] = _rng.randf_range(10.0, 45.0)
					if d["sea"]:
						# enough fishing: back to the colony
						d["state"] = "commute"
						d["sea"] = false
						d["dest"] = _center + Vector3(_rng.randf_range(-15, 15), _rng.randf_range(12, 30), _rng.randf_range(-15, 15))
					else:
						var roll := _rng.randf()
						if roll < 0.35 or night > 0.6:
							_try_land(d)
							if night > 0.6 and d["state"] == "mill":
								# no free perch here: off to roost somewhere else for the night
								n.visible = false
								d["state"] = "away"
								continue
						elif roll < 0.6:
							# fishing trip out over the sea (the colony sits on the south shore)
							d["state"] = "commute"
							d["sea"] = true
							d["dest"] = _center + Vector3(_rng.randf_range(-90, 90), 0, -_rng.randf_range(60, 160))
							d["dest"].y = _rng.randf_range(4.0, 9.0)
						else:
							d["radius"] = _rng.randf_range(12.0, 38.0)
							d["c"] = Vector3(c.x, _center.y + _rng.randf_range(10, 34), c.z)
							if _rng.randf() < 0.3:
								d["turn"] = -d["turn"]
			"commute":
				# a straight, purposeful flight to the fishing ground or home
				var dest: Vector3 = d["dest"]
				Flight.steer(b, _clear_trees(dest, b), delta, w, spec)
				cruising = true
				if Vector2(dest.x - pos.x, dest.z - pos.z).length() < float(d["radius"]) + 4.0:
					d["state"] = "mill"
					d["c"] = dest
					d["radius"] = _rng.randf_range(12.0, 24.0) if d["sea"] else _rng.randf_range(12.0, 38.0)
					d["timer"] = _rng.randf_range(15.0, 40.0) if d["sea"] else _rng.randf_range(10.0, 45.0)
			"approach":
				# round to a point just outside the canopy in front of its perch, slowing down
				var p: Dictionary = _perches[d["perch"]]
				var gate: Vector3 = p["pos"] + p["out"] * 3.2 + Vector3.UP * 1.2
				var dist := gate.distance_to(pos)
				Flight.steer(b, gate, delta, w, spec, clampf(dist * 0.7, 4.2, float(spec["cruise"])))
				effort = 0.3
				if dist < 2.2 or d["timer"] < -25.0:
					d["state"] = "land"
					d["vel"] = b["gvel"]
					d["timer"] = 0.0
			"land":
				# the last meters: braking with the body tipped back and the wings beating against the air
				var p: Dictionary = _perches[d["perch"]]
				var tgt: Vector3 = p["pos"]
				var to := tgt - pos
				var dist := to.length()
				var v: Vector3 = d["vel"]
				var spd := lerpf(v.length(), clampf(dist * 1.7, 0.5, 5.0), 1.0 - exp(-5.0 * delta))
				var dir := v.normalized().slerp(to.normalized(), 1.0 - exp(-(5.0 if dist > 1.0 else 14.0) * delta)) if v.length() > 0.01 else to.normalized()
				v = dir * spd
				d["vel"] = v
				var old_yaw: float = b["yaw"]
				pos += v * minf(delta, dist / maxf(spd, 0.01))
				b["pos"] = pos
				if Vector2(v.x, v.z).length() > 0.3:
					b["yaw"] = lerp_angle(old_yaw, Flight.yaw_of(v), 1.0 - exp(-8.0 * delta))
				b["bank"] = lerpf(b["bank"], clampf(-angle_difference(old_yaw, b["yaw"]) / maxf(delta, 0.001) * 0.3, -0.5, 0.5), 1.0 - exp(-6.0 * delta))
				b["vy"] = v.y
				b["speed"] = maxf(Vector2(v.x, v.z).length(), 0.5)
				effort = 1.0
				pitch = 0.8 * (1.0 - smoothstep(0.15, 2.2, dist))
				if dist < 0.06 or d["timer"] < -8.0:
					# settle: becomes a perched bird again, facing the way it came in
					var bird := _instance(p["kind"])
					add_child(bird)
					p["yaw"] = b["yaw"]
					bird.global_transform = Transform3D(Basis(Vector3.UP, p["yaw"]), tgt)
					p["node"] = bird
					n.visible = false
					d["state"] = "sitting"
					d["timer"] = _rng.randf_range(20.0, 90.0)
					continue
			"away":
				if night < 0.4:
					n.visible = true
					d["state"] = "mill"
				continue
			"sitting":
				if d["timer"] <= 0.0 and night < 0.5:
					_take_off(d)
				continue
			"takeoff":
				# drops off the branch, then climbs out clear of the canopy on hard wing beats
				Flight.steer(b, _clear_trees(d["dest"], b), delta, w, spec)
				effort = 1.0
				pitch = 0.2
				if d["timer"] <= 0.0:
					d["state"] = "mill"
					d["timer"] = _rng.randf_range(10.0, 45.0)
		if cruising:
			effort = clampf(float(b["vy"]) / 2.0, 0.0, 1.0)
			# a few beats, a short glide; gliding all the way down a descent
			d["glide"] -= delta
			if d["glide"] < d["beats"]:
				d["glide"] = _rng.randf_range(0.5, 1.6)
				d["beats"] = -_rng.randf_range(1.5, 5.0)
			flapping = (d["glide"] < 0.0 or b["vy"] > 0.4) and b["vy"] > -1.2
		d["pitch"] = lerpf(d["pitch"], pitch, 1.0 - exp(-5.0 * delta))
		n.global_transform = Transform3D(Flight.attitude(b, d["pitch"]), b["pos"])
		_flap(d, delta, effort, flapping)
		# the tail: closed in level flight, fanned in a turn, spread wide and lowered to brake
		Flight.tail(d["tail"], (0.1 + 0.35 * absf(b["bank"]) + 0.6 * float(d["pitch"])) * float(spec["tail"]), 0.5 * float(d["pitch"]))


## Wings: the bendable wings shaped by the shared wing-beat pose.
func _flap(d: Dictionary, delta: float, effort: float, flapping: bool) -> void:
	var spec: Dictionary = d["spec"]
	d["amp"] = lerpf(d["amp"], (0.58 + 0.27 * effort) if flapping else 0.0, 1.0 - exp(-7.0 * delta))
	d["flap"] = fmod(d["flap"] + TAU * float(spec["beat"]) * (1.0 + 0.25 * effort) * delta, TAU)
	var amp: float = d["amp"]
	var pose := Flight.beat(d["flap"], amp)
	# gliding: arms a little raised, hands drooping and swept back
	var still := 1.0 - clampf(amp / 0.5, 0.0, 1.0)
	Flight.pose(d["wings"], 0.07 + 0.08 * still + float(pose[0]), -0.2 * still + float(pose[1]), 0.12 * still + float(pose[2]), pose[4])
	(d["model"] as Node3D).position.y = float(pose[3]) * 0.013 * amp


func _try_land(d: Dictionary) -> void:
	var options: Array = []
	var want := "NoddyPerched" if d["kind"] == "Noddy" else "WhiteTernPerched"
	for i in _perches.size():
		var p: Dictionary = _perches[i]
		if p["node"] == null and p["kind"] == want and not p.get("claimed", false):
			options.append(i)
	if options.is_empty():
		return
	var i: int = options[_rng.randi() % options.size()]
	_perches[i]["claimed"] = true
	d["perch"] = i
	d["state"] = "approach"
	d["timer"] = 0.0


func _take_off(d: Dictionary) -> void:
	var p: Dictionary = _perches[d["perch"]]
	var yaw: float = p["yaw"]
	if p["node"]:
		yaw = (p["node"] as Node3D).rotation.y
		(p["node"] as Node3D).queue_free()
		p["node"] = null
	p["claimed"] = false
	var n: Node3D = d["node"]
	var start: Vector3 = p["pos"] + Vector3.UP * 0.1
	# turns on its perch and drops out of the tree, away from the trunk and up into the wind
	var out: Vector3 = (p["out"] as Vector3 - Flight.WIND_DIR * 0.6).normalized()
	yaw = lerp_angle(yaw, Flight.yaw_of(out), 0.8)
	var b: Dictionary = Flight.make(start, yaw, 2.5)
	b["vy"] = -1.2
	d["b"] = b
	d["pitch"] = 0.1
	d["dest"] = start + out * 30.0 + Vector3.UP * _rng.randf_range(9.0, 16.0)
	d["c"] = _center + Vector3(_rng.randf_range(-15, 15), _rng.randf_range(12, 34), _rng.randf_range(-15, 15))
	d["sea"] = false
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), start)
	n.visible = true
	d["state"] = "takeoff"
	d["timer"] = _rng.randf_range(2.5, 4.0)
	d["perch"] = -1
	_call_at(p["pos"], 0.0, p["kind"])


## Sitting birds now and then leave their nest and join the crowd above.
func _perched_take_off() -> void:
	if _flyers.size() >= flyer_count + 20:
		return
	var sitting: Array = []
	for i in _perches.size():
		if _perches[i]["node"] != null and not _perches[i].get("claimed", false):
			sitting.append(i)
	if sitting.is_empty():
		return
	var i: int = sitting[_rng.randi() % sitting.size()]
	var p: Dictionary = _perches[i]
	var d := _new_flyer("Noddy" if p["kind"] == "NoddyPerched" else "WhiteTern", false)
	d["perch"] = i
	p["claimed"] = true
	_flyers.append(d)
	_take_off(d)


## Life on the nests: a sitting bird bows (the noddies' nodding that gives them their name) or
## shuffles around a little.
func _perched_fidget() -> void:
	if _perches.is_empty():
		return
	var p: Dictionary = _perches[_rng.randi() % _perches.size()]
	var bird: Node3D = p["node"]
	if bird == null or p.get("claimed", false) or p.get("busy", 0) > Time.get_ticks_msec():
		return
	p["busy"] = Time.get_ticks_msec() + 2500
	var tw := bird.create_tween()
	if _rng.randf() < 0.6:
		var deep := _rng.randf_range(0.25, 0.45)
		for k in _rng.randi_range(1, 3):
			tw.tween_property(bird, "rotation:x", -deep, 0.22).set_trans(Tween.TRANS_SINE)
			tw.tween_property(bird, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	else:
		tw.tween_property(bird, "rotation:y", bird.rotation.y + _rng.randf_range(-0.7, 0.7), _rng.randf_range(0.4, 0.8)).set_trans(Tween.TRANS_SINE)


# ------------------------------------------------------------------ frigatebirds
var _displays: Array = []
var _frigate_calls: Array[AudioStream] = []


## A frigatebird to fly or to sit: the all-black male with his red throat sac, or the
## white-breasted female. Returns its parts.
func _new_frigate(male: bool) -> Dictionary:
	var kind := "Frigate" if male else "FrigateF"
	var root := Node3D.new()
	add_child(root)
	var m := _instance(kind)
	root.add_child(m)
	return {"node": root, "model": m, "male": male, "wings": Flight.wings(m, "Frigate", kind + "WingL", kind + "WingR", get_parent(), false),
		"tail": Flight.tail_of(m, kind), "sac": m.find_child("FrigateSac", true, false), "seed": _rng.randf() * TAU}


## Courting males on the crowns of the tallest colony trees, settled into the topmost leaves: sac
## blown up like a red balloon, wings held out and trembling, head thrown back, swaying.
func _setup_displays() -> void:
	var f := FileAccess.open("res://assets/models/tree_tips.json", FileAccess.READ)
	if f == null or not _models.has("Frigate"):
		return
	var tips: Dictionary = JSON.parse_string(f.get_as_text())
	var tops: Array = []   # [height, position]: a little above the center of each tree's highest leaf cluster
	for t in _ls.tree_spots:
		if not t["colony"] or not tips.has(t["kind"]):
			continue
		var xf: Transform3D = t["xf"]
		var best := Vector3(0, -1e9, 0)
		for tip in tips[t["kind"]]:
			# (higher than 0.4 of the cluster's radius the leaves thin out and the bird would hang in the air)
			var p: Vector3 = xf * Vector3(tip[0], tip[1], tip[2]) + Vector3.UP * float(tip[3]) * xf.basis.get_scale().y * 0.4
			if p.y > best.y:
				best = p
		tops.append([best.y, best])
	tops.sort_custom(func(a, b): return a[0] > b[0])
	for i in 8:
		var path := A + "frigate_%d.wav" % i
		if ResourceLoader.exists(path):
			_frigate_calls.append(load(path))
	for i in mini(3, tops.size()):
		var d := _new_frigate(true)
		d["yaw"] = _rng.randf() * TAU
		(d["node"] as Node3D).global_position = tops[i][1]
		(d["model"] as Node3D).position = Vector3(0, 0.1, 0.05)
		# his voice: bill rattling and a wavering warble, at the height of a display
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = 9.0
		voice.max_distance = 140.0
		voice.volume_db = -9.0
		(d["node"] as Node3D).add_child(voice)
		d["voice"] = voice
		d["call_at"] = _rng.randf_range(4.0, 20.0)
		_displays.append(d)


func _update_displays(night: float) -> void:
	var day := 1.0 - smoothstep(0.3, 0.6, night)
	for d in _displays:
		var t := Time.get_ticks_msec() * 0.001 + float(d["seed"]) * 10.0
		# he displays in bouts; between them he sits quietly with the sac still blown up
		var bout := smoothstep(0.1, 0.7, sin(t * 0.33)) * day
		var m: Node3D = d["model"]
		m.rotation = Vector3(0.95 + 0.14 * bout, 0, 0)
		(d["node"] as Node3D).rotation.y = float(d["yaw"]) + 0.3 * sin(t * 0.9) * bout
		Flight.pose(d["wings"], -0.3 + 0.2 * bout + 0.05 * sin(t * 12.0) * bout, -0.55 + 0.1 * bout, 0.5 - 0.22 * bout, 0.0,
			0.05 * sin(t * 7.3) * bout)
		Flight.tail(d["tail"], -0.08, 0.35)
		var voice: AudioStreamPlayer3D = d["voice"]
		if bout > 0.75 and t > float(d["call_at"]) and not voice.playing and not _frigate_calls.is_empty():
			voice.stream = _frigate_calls[_rng.randi() % _frigate_calls.size()]
			voice.pitch_scale = _rng.randf_range(0.94, 1.06)
			voice.play()
			d["call_at"] = t + _rng.randf_range(4.0, 9.0)
		var sac: Node3D = d["sac"]
		if sac:
			# let down at night to a wrinkled pouch
			var puff := lerpf(0.34, 1.0 + 0.035 * sin(t * 14.0) * bout, day)
			sac.scale = Vector3(puff, puff * lerpf(0.75, 1.0, day), puff)


func _update_frigates(delta: float, night: float) -> void:
	_frigate_timer -= delta
	if _frigate_timer <= 0.0 and night < 0.4:
		_frigate_timer = _rng.randf_range(120.0, 300.0)
		for i in _rng.randi_range(1, 3):
			var d := _new_frigate(_rng.randf() < 0.5)
			if d["sac"]:
				(d["sac"] as Node3D).scale = Vector3(0.32, 0.25, 0.5)   # in flight the sac is a small red pouch at the throat
			var far := Vector3(_rng.randf_range(-300, 300), 0, -_rng.randf_range(250, 400))
			var pos := _center + far + Vector3(0, _rng.randf_range(45, 80), 0)
			d.merge({"b": Flight.make(pos, Flight.yaw_of(-far), FRIGATE["cruise"]),
				"c": _center + Vector3(_rng.randf_range(-40, 70), 0, _rng.randf_range(-20, 90)), "state": "glide",
				"radius": _rng.randf_range(24.0, 42.0), "turn": 1.0 if _rng.randf() < 0.5 else -1.0,
				"top": _rng.randf_range(70.0, 110.0), "life": _rng.randf_range(100.0, 200.0)})
			_frigates.append(d)
	for i in range(_frigates.size() - 1, -1, -1):
		var d: Dictionary = _frigates[i]
		d["life"] -= delta
		var n: Node3D = d["node"]
		var b: Dictionary = d["b"]
		var pos: Vector3 = b["pos"]
		var c: Vector3 = d["c"]
		var h := pos.y - _ground_y
		var w := _wind(h)
		# soaring without a wing beat: circling up in rising air, then a long flat glide to the next
		# thermal, losing height all the way
		if d["state"] == "thermal":
			var goal := _circle_goal(d, c)
			goal.y = pos.y + 4.0
			Flight.steer(b, goal, delta, w, FRIGATE)
			if h > d["top"]:
				d["state"] = "glide"
				d["top"] = _rng.randf_range(70.0, 110.0)
				# over the island while it stays, then away out to sea again
				d["c"] = _center + (Vector3(_rng.randf_range(-60, 90), 0, _rng.randf_range(-30, 130)) if d["life"] > 30.0 else Vector3(_rng.randf_range(-200, 200), 0, -600))
				if _rng.randf() < 0.4:
					d["turn"] = -d["turn"]
		else:
			Flight.steer(b, Vector3(c.x, pos.y - 4.0 if h > 38.0 else pos.y, c.z), delta, w, FRIGATE)
			if Vector2(c.x - pos.x, c.z - pos.z).length() < float(d["radius"]) + 5.0:
				d["state"] = "thermal"
		# the long wings held in a shallow "W" (arms raised, hands drooping and swept back), flexing
		# with the turbulence; the inner wing dips a little in a turn
		var t := Time.get_ticks_msec() * 0.001 + float(d["seed"])
		var flex := sin(t * 1.3) * 0.03 + sin(t * 3.1) * 0.015
		Flight.pose(d["wings"], 0.16 + flex, -0.34 - flex * 1.5, 0.32, 0.0, -float(b["bank"]) * 0.06)
		# the long forked tail: held closed to a point, scissoring open to steer
		Flight.tail(d["tail"], -0.12 + 0.6 * absf(b["bank"]) + 0.3 * maxf(sin(t * 0.45), 0.0), 0.0)
		n.global_transform = Transform3D(Flight.attitude(b, sin(Time.get_ticks_msec() * 0.0007 + float(d["seed"])) * 0.03), b["pos"])
		if d["life"] < -80.0 or night > 0.6:
			n.queue_free()
			_frigates.remove_at(i)


# ------------------------------------------------------------------ sound
var _tern_calls: Array[AudioStream] = []
var _tern_calls_loaded := false
var tern_calls_played := 0      # (for the tests)


## `kind`: whose voice ("WhiteTern..." has its own calls; everybody else the noddies').
func _call_at(p: Vector3, extra_db: float, kind := "") -> void:
	if not _tern_calls_loaded:
		_tern_calls_loaded = true
		for i in 6:
			var path := A + "white_tern_%d.wav" % i
			if ResourceLoader.exists(path):
				_tern_calls.append(load(path))
	if _calls.is_empty():
		return
	for cp in _call_players:
		if not cp.playing:
			cp.stream = _calls[_rng.randi() % _calls.size()]
			if kind.begins_with("WhiteTern") and not _tern_calls.is_empty():
				cp.stream = _tern_calls[_rng.randi() % _tern_calls.size()]
				tern_calls_played += 1
			cp.global_position = p
			cp.pitch_scale = _rng.randf_range(0.9, 1.12)
			cp.volume_db = _rng.randf_range(-12.0, -4.0) + extra_db
			cp.play()
			return


func _process(delta: float) -> void:
	if not _ready_done:
		return
	var dc := get_node_or_null("../DayCycle")
	var night: float = dc.night if dc else 0.0
	_update_flyers(delta, night)
	_update_frigates(delta, night)
	_update_displays(night)
	if _rng.randf() < delta / 6.0 and night < 0.5:
		_perched_take_off()
	if _rng.randf() < delta * 3.0 and _player and _player.global_position.distance_to(_center) < 90.0:
		_perched_fidget()
	for p in _loops:
		p.volume_db = lerpf(-4.0, -16.0, night)
	_call_timer -= delta
	if _call_timer <= 0.0:
		_call_timer = _rng.randf_range(0.25, 1.4) * (1.0 + night * 3.0)
		var pp := _player.global_position if _player else Vector3.ZERO
		if pp.distance_to(_center) < 120.0 and not _perches.is_empty():
			var p: Dictionary = _perches[_rng.randi() % _perches.size()]
			_call_at(p["pos"], 0.0, p["kind"])
