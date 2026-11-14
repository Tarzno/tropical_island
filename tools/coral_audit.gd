extends Node
## Test tool: watches everything that swims and counts, kind by kind, the time an animal has
## a part of itself inside a coral (Seabed.top_at(), the coral itself: no skirt).
##   main.add_child(load('res://tools/coral_audit.gd').new())   (in the shot driver's `expr`)
## It moves the player from place to place in the lagoon (the fish schools, the rays and the
## tiger shark go by where the player is), calls the tiger shark and the rays again and again,
## and runs the game at three times its pace. `report()` gives the figures.

var spots: Array = [Vector3(45, -0.4, 0), Vector3(62, -0.4, -38), Vector3(72, -0.4, 4), Vector3(38, -0.4, 55),
	Vector3(20, -0.4, 20), Vector3(76, -0.4, -20), Vector3(55, -0.4, 30), Vector3(30, -0.4, -45), Vector3(91, -0.4, -10),
	Vector3(14, -0.4, 95), Vector3(16, -0.4, -70), Vector3(30, -0.4, -78)]       # (the last three: among boulders that stand in the water)
var hop := 40.0            # seconds (of the game's time) at each place
var pace := 3.0
var stats := {}
var seconds := 0.0
var shark_asked := 0
var _track := {}           # an animal's node -> [where it was, seconds it has not moved]
var motion := {}           # kind -> [seconds watched, meters, longest standstill]
var shark_came := 0
var shark_ms := 0.0        # the longest the planning of its route has taken
var _t := 1e9
var _i := -1
var _main: Node
var _seabed: Node
var _ls: Node


func _ready() -> void:
	_main = get_parent()
	_seabed = _main.get_node("IslandLife/Seabed")
	_ls = _main.get_node("Landscape")
	Engine.time_scale = pace


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _in(p: Vector3) -> float:
	var top := float(_seabed.top_at(Vector2(p.x, p.z), 0.01, false))
	if top < float(_ls.ground(p.x, p.z)) + 0.05:
		return -1.0
	return top - p.y


## Animal against animal (2026-11-12, after two eagle rays were seen passing through each
## other): every animal's points of this frame with a thickness for its kind; two animals
## meet where a point of one is nearer a point of the other than their two thicknesses.
## Rough (three to five points an animal, a ball at each): it finds bodies that pass
## through each other, not a fin that brushes a tail. `pair_report()` gives the list.
const THICK := {"tiger shark": 0.4, "eagle rays": 0.4, "young reef sharks": 0.1, "manta": 0.8, "lagoon turtles": 0.25,
	"nesting turtle in the water": 0.3, "lionfish": 0.1, "grouper": 0.35, "triggerfish": 0.1, "barracudas": 0.08, "moorish idols": 0.04,
	"dolphins": 0.25, "reef fish": 0.03}
const TAILED := ["eagle rays", "manta"]
const TAIL := 0.05
var pairs := {}            # "kind + kind" -> [seconds, the deepest overlap, where]
var _bodies: Array = []

func _meetings(dt: float) -> void:
	for i in _bodies.size():
		var a: Array = _bodies[i]
		for j in range(i + 1, _bodies.size()):
			var b: Array = _bodies[j]
			if a[0] == "reef fish" and b[0] == "reef fish":
				continue
			var deep := 0.0
			var at := Vector3.ZERO
			var pa: Array = a[1]
			var pb: Array = b[1]
			for m in pa.size():
				var p: Vector3 = pa[m]
				for n in pb.size():
					var q: Vector3 = pb[n]
					# (the third point of a ray lies on its tail, which is a whip, not a body)
					var gap := p.distance_to(q) - (TAIL if m == 2 and TAILED.has(a[0]) else float(a[2])) - (TAIL if n == 2 and TAILED.has(b[0]) else float(b[2]))
					if gap < deep:
						deep = gap
						at = p
			if deep < 0.0:
				var key: String = "%s + %s" % ([a[0], b[0]] if String(a[0]) <= String(b[0]) else [b[0], a[0]])
				if not pairs.has(key):
					pairs[key] = [0.0, 0.0, Vector3.ZERO]
				pairs[key][0] += dt
				if deep < float(pairs[key][1]):
					pairs[key][1] = deep
					pairs[key][2] = at
	_bodies.clear()


func pair_report() -> Dictionary:
	var out := {}
	for k: String in pairs:
		out[k] = "%.1f s, at the most %.2f m into each other (at %s)" % [pairs[k][0], -float(pairs[k][1]), (pairs[k][2] as Vector3).snappedf(0.1)]
	return out


func _note(kind: String, dt: float, pts: Array) -> void:
	# (not what is put away far under the world: the dolphins between two passes)
	if (pts[0] as Vector3).y > -40.0:
		_bodies.append([kind, pts, THICK.get(kind, 0.1)])
	if not stats.has(kind):
		stats[kind] = {"watched": 0.0, "inside": 0.0, "deepest": 0.0, "cases": [], "rock": 0.0, "rock_deep": 0.0, "rock_cases": [], "boat": 0.0}
	var st: Dictionary = stats[kind]
	st["watched"] += dt
	# (rocks standing in the water: counted apart from the corals)
	var rw := 0.0
	var rat := Vector3.ZERO
	for p: Vector3 in pts:
		var rd := float(_seabed.rock_at(Vector2(p.x, p.z))) - p.y
		if rd > rw:
			rw = rd
			rat = p
	# (the boat: in its hull, not merely under it. It draws less than half a meter)
	for p: Vector3 in pts:
		if p.y > float(_ls.sea) - 0.45 and _seabed.boat_at(p.x, p.z):
			st["boat"] += dt
			break
	if rw > 0.03:
		st["rock"] += dt
		st["rock_deep"] = maxf(st["rock_deep"], rw)
		var rc: Array = st["rock_cases"]
		if rc.size() < 3 and (rc.is_empty() or (rc[rc.size() - 1][0] as Vector3).distance_to(rat) > 3.0):
			rc.append([rat.snappedf(0.1), snappedf(rw, 0.01)])
	var worst := 0.0
	var at := Vector3.ZERO
	for p: Vector3 in pts:
		var d := _in(p)
		if d > worst:
			worst = d
			at = p
	if worst > 0.03:
		st["inside"] += dt
		st["deepest"] = maxf(st["deepest"], worst)
		var cases: Array = st["cases"]
		if cases.size() < 4 and (cases.is_empty() or (cases[cases.size() - 1][0] as Vector3).distance_to(at) > 3.0):
			cases.append([at.snappedf(0.1), snappedf(worst, 0.01)])


## Does it still move? (A rule that keeps an animal out of something can leave it standing
## before it for ever, and "seconds inside" then reads a perfect nought.)
func _moved(kind: String, n: Node3D, dt: float) -> void:
	var p := n.global_position
	if not motion.has(kind):
		motion[kind] = [0.0, 0.0, 0.0]
	var m: Array = motion[kind]
	var id := n.get_instance_id()
	if _track.has(id):
		var t: Array = _track[id]
		var d := p.distance_to(t[0])
		if d < 40.0:            # (not a jump to another place)
			m[1] += d
		t[1] = float(t[1]) + dt if d < 0.002 * dt * 60.0 else 0.0
		m[2] = maxf(m[2], t[1])
		t[0] = p
	else:
		_track[id] = [p, 0.0]
	m[0] += dt


## Points of a mesh's body in the world: belly, nose, tail (and the wing tips).
func _pts(mi: MeshInstance3D, wide: bool) -> Array:
	var b := mi.mesh.get_aabb()
	var c := b.get_center()
	var y := b.position.y + 0.3 * b.size.y
	var xf := mi.global_transform
	var out: Array = [xf * Vector3(c.x, y, c.z), xf * Vector3(c.x, y, b.position.z + 0.12 * b.size.z), xf * Vector3(c.x, y, b.end.z - 0.25 * b.size.z)]
	if wide:
		out.append(xf * Vector3(b.position.x + 0.15 * b.size.x, c.y, c.z))
		out.append(xf * Vector3(b.end.x - 0.15 * b.size.x, c.y, c.z))
	return out


func _process(delta: float) -> void:
	seconds += delta
	var player := _main.get_node("Player") as Node3D
	var sea := _main.get_node("SeaLife")
	_t += delta
	if _t > hop:
		_t = 0.0
		_i = (_i + 1) % spots.size()
	var sp: Vector3 = spots[_i]
	player.global_position = Vector3(sp.x, float(_ls.sea) + sp.y, sp.z)
	player.set("velocity", Vector3.ZERO)
	if not sea.get("_shark_on") and fmod(seconds, 20.0) < delta:
		shark_asked += 1
		var t0 := Time.get_ticks_usec()
		if sea.summon_shark():
			shark_came += 1
		shark_ms = maxf(shark_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	if (sea.get("_rays") as Array).size() < 2 and fmod(seconds, 7.0) < delta:
		sea.summon_rays()
	if sea.get("_shark_on"):
		_note("tiger shark", delta, _pts(sea.get("_shark"), false))
	for d: Dictionary in sea.get("_rays"):
		_note("eagle rays", delta, _pts(d["node"], true))
		_moved("eagle rays", d["node"], delta)
	for d: Dictionary in sea.get("_pups"):
		var mi: MeshInstance3D = d["node"]
		if mi.global_position.distance_to(player.global_position) < 170.0:
			_note("young reef sharks", delta, _pts(mi, false))
			_moved("young reef sharks", mi, delta)
	_note("manta", delta, _pts(sea.get("_manta"), true))
	_moved("manta", sea.get("_manta"), delta)
	var fish := _main.get_node("Fish")
	var tide := float(_ls.sea)
	for s: Dictionary in fish.get("_schools"):
		for f: Dictionary in s["fish"]:
			var p: Vector3 = f["pos"]
			_note("reef fish", delta, [Vector3(p.x, p.y + tide - 0.03, p.z)])
	var life := _main.get_node("IslandLife")
	for d: Dictionary in life.get_node("Turtles").get("turtles"):
		var n: Node3D = d["node"]
		_moved("lagoon turtles", n, delta)
		_note("lagoon turtles", delta, [n.global_position - Vector3(0, 0.1 * float(d["sc"]), 0), n.global_position - n.global_transform.basis.z.normalized() * (0.45 * float(d["sc"])) - Vector3(0, 0.1 * float(d["sc"]), 0)])
	var nt := life.get_node("Nesting").get("turtle") as Node3D
	if nt and nt.visible and float(_ls.ground(nt.global_position.x, nt.global_position.z)) < tide - 0.3:
		_note("nesting turtle in the water", delta, [nt.global_position])
	var reef := life.get_node("ReefLife")
	for l: Dictionary in reef.get("lionfish"):
		_note("lionfish", delta, [l["pos"]])
	var gr := reef.get_node_or_null("Grouper") as MeshInstance3D
	if gr:
		_note("grouper", delta, _pts(gr, false))
	for t: Dictionary in reef.get("triggers"):
		if t.has("pos"):
			_note("triggerfish", delta, [t["pos"]])
	var bc := life.get_node_or_null("Barracudas")
	if bc:
		for f: Dictionary in bc.get("fish"):
			_note("barracudas", delta, _pts(f["node"], false))
	var mo := life.get_node_or_null("Idols")
	if mo:
		for g: Dictionary in mo.get("groups"):
			for f: Dictionary in g["fish"]:
				_note("moorish idols", delta, [f["pos"]])
	var dl := life.get_node("Dolphins")
	if dl.get("passing"):
		for d: Dictionary in dl.get("_pod"):
			_note("dolphins", delta, _pts(d["node"], false))
	_meetings(delta)


func report() -> Dictionary:
	var out := {"seconds": snappedf(seconds, 1.0), "tiger shark came": "%d of %d calls, planning took %.0f ms at the most" % [shark_came, shark_asked, shark_ms]}
	for k: String in stats:
		var st: Dictionary = stats[k]
		out[k] = "watched %.0f s, inside a coral %.1f s (%.2f %%), deepest %.2f m; %s; INSIDE A ROCK %.1f s (%.2f %%), deepest %.2f m; %s; IN THE BOAT %.1f s" % [st["watched"], st["inside"], 100.0 * float(st["inside"]) / maxf(float(st["watched"]), 0.001), st["deepest"], str(st["cases"]),
			st["rock"], 100.0 * float(st["rock"]) / maxf(float(st["watched"]), 0.001), st["rock_deep"], str(st["rock_cases"]), st["boat"]]
	for k: String in motion:
		var m: Array = motion[k]
		out[k + ": motion"] = "%.2f m/s on average, longest standstill %.0f s" % [float(m[1]) / maxf(float(m[0]), 0.001), m[2]]
	return out
