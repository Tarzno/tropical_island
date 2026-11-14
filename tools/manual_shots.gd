extends Node
## Camera helper for the manual's pictures (docs/manual): added to the running game by the
## test driver (tools/shot.gd) with
##   add_tool('res://tools/manual_shots.gd', 'MS')
## and then driven from `expr` jobs:
##   main.get_node('MS').aim(<Node3D or Vector3>, Vector3(dx, dy, dz), fov)   the camera stays at
##       target + offset and looks at the target, every frame (a moving animal is followed);
##       aim(..., fov, true) takes the offset in the target's own axes (-z is its front)
##   main.get_node('MS').save('name.png')        saves what the camera sees now
##   main.get_node('MS').probe(node, 'var')      what a script keeps in a variable (for finding things)
## The player is parked `stand` meters behind the camera (animals are only updated near the
## player, and move off when the player is close).

var out_dir := ""
var stand := 14.0
var lift := Vector3.ZERO          # looked at: target + lift
var up := Vector3.UP
var clear := 0.06             # the camera keeps this far above the ground (0: it may go under)
var _target: Variant = null
var _off := Vector3(0, 1, 3)
var _local := false
var _fov := 40.0
var _park := true
var _player_at: Variant = null


func _ready() -> void:
	process_priority = 1000       # after everything that moves


func aim(target: Variant, off: Vector3, fov := 40.0, local := false) -> String:
	_target = target
	_off = off
	_fov = fov
	_local = local
	_place()
	return "aimed at %s" % str(_at())


## Where the player stands meanwhile (null: behind the camera, `stand` meters from the target).
func player(at: Variant) -> void:
	_player_at = at


func free_cam() -> void:
	_target = null


func _at() -> Vector3:
	if _target is Node3D:
		return (_target as Node3D).global_position
	if _target is Vector3:
		return _target
	if _target is Vector2:
		return on_ground((_target as Vector2).x, (_target as Vector2).y)
	if _target is Transform3D:
		return (_target as Transform3D).origin
	if _target is Array and (_target as Array).size() == 2 and _target[0] is Dictionary:
		return (_target[0] as Dictionary).get(_target[1], Vector3.ZERO)     # a place kept in a dictionary: followed
	return Vector3.ZERO


func _basis() -> Basis:
	if _target is Node3D:
		return (_target as Node3D).global_transform.basis.orthonormalized()
	if _target is Transform3D:
		return (_target as Transform3D).basis.orthonormalized()
	return Basis()


func _place() -> void:
	if _target == null or (_target is Node3D and not is_instance_valid(_target)):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := _at() + lift
	var off := (_basis() * _off) if _local else _off
	var cp := at + off
	if clear > 0.0:        # (never under the ground)
		cp.y = maxf(cp.y, float(get_parent().get_node("Landscape").call("ground", cp.x, cp.z)) + clear)
	cam.global_position = cp
	cam.look_at(at, up if absf(off.x) + absf(off.z) > 0.02 else Vector3(0, 0, -1))
	cam.fov = _fov
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var pl := get_parent().get_node("Player") as Node3D
	pl.set("_fly", true)
	pl.get_node("CollisionShape3D").set("disabled", true)
	if _player_at is Vector3:
		pl.global_position = _player_at
	elif _park:
		var flat := Vector3(off.x, 0.0, off.z)
		flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, 1)
		pl.global_position = at + flat * stand + Vector3(0, -1.65 + off.y, 0)


func _process(_dt: float) -> void:
	_place()


func save(file: String) -> String:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	return "saved " + file


## A short description of what `obj` keeps in `prop`: for finding where the animals are.
func probe(obj: Object, prop: String, n := 2) -> String:
	return prop + ": " + _describe(obj.get(prop), n, 0)


func _describe(v: Variant, n: int, depth: int) -> String:
	if v is Array or v is PackedVector3Array:
		var s := "Array[%d]" % v.size()
		if depth < 2:
			for i in mini(n, v.size()):
				s += "\n" + "  ".repeat(depth + 1) + "[%d] " % i + _describe(v[i], n, depth + 1)
		return s
	if v is Dictionary:
		var s := "{"
		for k in (v as Dictionary).keys():
			var e: Variant = v[k]
			var t := ""
			if e is Node3D:
				t = "Node3D@%s vis=%s" % [str((e as Node3D).global_position.snapped(Vector3.ONE * 0.1)), str((e as Node3D).is_visible_in_tree())]
			elif e is Vector3 or e is Vector2 or e is float or e is int or e is bool or e is String:
				t = str(e)
			elif e is Array:
				t = "Array[%d]" % (e as Array).size()
			else:
				t = type_string(typeof(e))
			s += "%s: %s, " % [str(k), t]
		return s + "}"
	if v is Node3D:
		return "Node3D %s @%s vis=%s" % [(v as Node3D).name, str((v as Node3D).global_position.snapped(Vector3.ONE * 0.1)), str((v as Node3D).is_visible_in_tree())]
	return str(v)


## The element of an array of dictionaries: its node or its place (for aim()).
func of(obj: Object, prop: String, i: int, key := "node") -> Variant:
	var a: Variant = obj.get(prop)
	if a is Array and i < (a as Array).size():
		var e: Variant = a[i]
		if e is Dictionary:
			return e.get(key)
		return e
	return null


## The i-th tree of a kind (Landscape.tree_spots): where it stands.
func tree(kind: String, i := 0) -> Vector3:
	var k := 0
	for t in get_parent().get_node("Landscape").get("tree_spots"):
		if str(t["kind"]).begins_with(kind):
			if k == i:
				return (t["xf"] as Transform3D).origin
			k += 1
	return Vector3.ZERO


## Which kinds of tree there are, and how many of each.
func tree_kinds() -> Dictionary:
	var d := {}
	for t in get_parent().get_node("Landscape").get("tree_spots"):
		d[t["kind"]] = int(d.get(t["kind"], 0)) + 1
	return d


## The names of a node's children, counted by their name without the digits.
func kids(n: Node) -> Dictionary:
	var d := {}
	for c in n.get_children():
		var nm := str(c.name).rstrip("0123456789_")
		d[nm] = int(d.get(nm, 0)) + 1
	return d


## Down into what a script keeps: g(node, 'flocks', [0, 'birds', 1, 'root']).
func g(obj: Object, prop: String, keys: Array) -> Variant:
	var v: Variant = obj.get(prop)
	for k in keys:
		if v is Array and (k is int or k is float):
			if int(k) >= (v as Array).size():
				return null
			v = v[int(k)]
		elif v is Dictionary:
			v = (v as Dictionary).get(k)
		else:
			return null
	return v


## The i-th dictionary of an array whose `key` is `value`: what it keeps under `ret`.
func pick(obj: Object, prop: String, key: String, value: Variant, i := 0, ret := "node") -> Variant:
	var k := 0
	for d in obj.get(prop):
		if d is Dictionary and (d as Dictionary).get(key) == value and (d as Dictionary).get(ret) != null:
			if k == i:
				return d[ret]
			k += 1
	return null


## The foot of the i-th coconut palm.
func palm(i: int) -> Vector3:
	return ((get_parent().get_node("Landscape").get("palm_trunks")[i] as Dictionary)["pts"] as PackedVector3Array)[0]


## A place on the ground: (x, ground, z).
func on_ground(x: float, z: float, above := 0.0) -> Vector3:
	return Vector3(x, float(get_parent().get_node("Landscape").call("ground", x, z)) + above, z)


## The names of the meshes of a node's children, counted (names cut at 14 letters).
func meshes(n: Node) -> Dictionary:
	var d := {}
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var nm := (c as MeshInstance3D).mesh.resource_name
			d[nm] = int(d.get(nm, 0)) + 1
	return d


## Where the i-th child stands whose mesh's name begins with `prefix`.
func mesh_pos(n: Node, prefix: String, i := 0) -> Vector3:
	var k := 0
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh and (c as MeshInstance3D).mesh.resource_name.begins_with(prefix):
			if k == i:
				return (c as Node3D).global_position
			k += 1
	return Vector3.ZERO


## Follows a place that a script keeps in a dictionary (a fish of a school, a rockskipper):
## aim_d(g(node, '_schools', [1, 'fish', 0]), 'pos', Vector3(...), fov).
func aim_d(d: Variant, key: String, off: Vector3, fov := 40.0) -> String:
	if not d is Dictionary:
		return "aimed at (0.0, 0.0, 0.0): no dictionary"
	return aim([d, key], off, fov, false)


## Where the i-th instance of a MultiMeshInstance3D lies.
func mm_pos(n: Node, i := 0) -> Vector3:
	var mmi := n as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null or i >= mmi.multimesh.instance_count:
		return Vector3.ZERO
	return mmi.global_transform * mmi.multimesh.get_instance_transform(i).origin


## A place where ferns stand (the i-th cell of Landscape._fern_cells with at least `least` of them).
func fern(i := 0, least := 5) -> Vector3:
	var k := 0
	for v in (get_parent().get_node("Landscape").get("_fern_cells") as Dictionary).values():
		if (v as Array).size() >= least:
			if k == i:
				var f: Vector3 = v[0]
				return on_ground(f.x, f.y)
			k += 1
	return Vector3.ZERO


var _coral_cache := {}

## The i-th biggest coral of a kind (Seabed._kinds: 0, 1 staghorn, 2 boulder, 3 brain, 4 table,
## 5 sea fan, 6 cauliflower, 7 finger, 8 plates, 9 fire, 10 leather) in the lagoon off the
## start beach: where it stands. Its size: coral_size(kind, i).
func coral(kind: int, i := 0) -> Vector3:
	var l := _corals(kind)
	return (l[i][1] as Vector3) if i < l.size() else Vector3.ZERO


func coral_size(kind: int, i := 0) -> float:
	var l := _corals(kind)
	return float(l[i][0]) if i < l.size() else 0.0


func _corals(kind: int) -> Array:
	if _coral_cache.has(kind):
		return _coral_cache[kind]
	var sb := get_parent().get_node("IslandLife/Seabed")
	var mesh: Mesh = (sb.get("_kinds")[kind] as Dictionary)["mesh"]
	var l: Array = []
	for c in sb.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh != mesh:
			continue
		for j in mmi.multimesh.instance_count:
			var xf := mmi.global_transform * mmi.multimesh.get_instance_transform(j)
			if xf.origin.x > 20.0 and xf.origin.x < 95.0 and absf(xf.origin.z) < 90.0:
				l.append([xf.basis.get_scale().x, xf.origin])
	l.sort_custom(func(a, b): return a[0] > b[0])
	_coral_cache[kind] = l
	return l


## Under a node: the names of the meshes its MultiMeshInstance3D children draw, counted.
func mm_meshes(n: Node) -> Dictionary:
	var d := {}
	for c in n.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi and mmi.multimesh and mmi.multimesh.mesh:
			var nm := mmi.multimesh.mesh.resource_name
			d[nm] = int(d.get(nm, 0)) + mmi.multimesh.instance_count
	return d


## Where the i-th instance stands that draws a mesh whose name begins with `prefix` (or, with
## a Mesh given instead of a name, that mesh), under a node; in a box of x if `x0` < `x1`.
func mm_find(n: Node, what: Variant, i := 0, x0 := 0.0, x1 := 0.0) -> Vector3:
	var k := 0
	for c in n.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		if what is Mesh and mmi.multimesh.mesh != what:
			continue
		if what is String and not mmi.multimesh.mesh.resource_name.begins_with(what):
			continue
		for j in mmi.multimesh.instance_count:
			var p := mmi.global_transform * mmi.multimesh.get_instance_transform(j).origin
			if x0 < x1 and (p.x < x0 or p.x > x1):
				continue
			if k == i:
				return p
			k += 1
	return Vector3.ZERO
