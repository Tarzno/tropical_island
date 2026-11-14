extends Node
## For the tests (tools/shot.gd: "add_tool('res://tools/nest_check.gd', 'NestCheck')"): what the
## seabird colony has in its trees: "main.get_node('NestCheck').report(main)". How many nests,
## sitting birds and eggs, how high above the ground, how big, and how far from the colony's
## middle. "nest(main, i)" is the i-th nest's node (for a picture).
func _kind(main: Node, n: Node) -> String:
	var models: Dictionary = main.get_node("Colony")._models
	for k: String in models:
		var m := models[k] as Node3D
		var a := n as MeshInstance3D
		var b := m as MeshInstance3D
		if a and b and a.mesh == b.mesh:
			return k
		if a == null and b == null and n.get_child_count() == m.get_child_count() and n.get_child_count() > 0 \
				and (n.get_child(0) as MeshInstance3D) and (m.get_child(0) as MeshInstance3D) and (n.get_child(0) as MeshInstance3D).mesh == (m.get_child(0) as MeshInstance3D).mesh:
			return k
	return "?"


func report(main: Node) -> Dictionary:
	var root := main.get_node("Colony/Nests")
	var ls := main.get_node("Landscape")
	var kinds := {}
	var heights: Array = []
	var far := 0.0
	for c in root.get_children():
		var n := c as Node3D
		var kind := _kind(main, n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var p := n.global_position
		if kind == "Nest":
			heights.append(snappedf(p.y - float(ls.ground(p.x, p.z)), 0.1))
			far = maxf(far, Vector2(p.x - ls.colony_center.x, p.z - ls.colony_center.y).length())
	heights.sort()
	return {"what": kinds, "nests above the ground (m)": heights, "furthest nest from the colony's middle (m)": snappedf(far, 0.1)}


func nest(main: Node, i: int) -> Node3D:
	var k := 0
	for c in main.get_node("Colony/Nests").get_children():
		if _kind(main, c) == "Nest":
			if k == i:
				return c as Node3D
			k += 1
	return null


## Where a walker's eyes are who stands `away` meters from under the i-th nest (to the side
## given by `turn`, radians), as an offset from the nest: for a picture of what is seen of it.
func eyes(main: Node, i: int, away := 3.5, turn := 0.0) -> Vector3:
	var p := nest(main, i).global_position
	var ls := main.get_node("Landscape")
	var q := Vector2(p.x, p.z) + Vector2.from_angle(turn) * away
	return Vector3(q.x, float(ls.ground(q.x, q.y)) + 1.65, q.y) - p


## Is a point inside a tree's wood? (How often a ray straight up from it goes through the
## bark's skin: an odd number of times means inside.) `faces`: the bark's triangles in tree
## coordinates, `q`: the point in tree coordinates.
func _inside(faces: PackedVector3Array, q: Vector3) -> bool:
	var n := 0
	for t in range(0, faces.size(), 3):
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		if maxf(a.y, maxf(b.y, c.y)) < q.y or minf(a.x, minf(b.x, c.x)) > q.x or maxf(a.x, maxf(b.x, c.x)) < q.x \
				or minf(a.z, minf(b.z, c.z)) > q.z or maxf(a.z, maxf(b.z, c.z)) < q.z:
			continue
		# the ray's place in the triangle, seen from above
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


## How many nests and sitting birds have wood where their body is: the middle of a noddy on
## its nest (12 cm over the nest's foot), of a tern (8 cm over its feet), and a ring of six
## points around the nest's rim. Tried against the two trees nearest to each.
func wood_report(main: Node) -> Dictionary:
	var co := main.get_node("Colony")
	var ls := main.get_node("Landscape")
	var trees: Array = []
	for t: Dictionary in ls.tree_spots:
		if t["colony"] and ls._tree_parts.has(String(t["kind"]) + "Bark"):
			trees.append(t)
	var faces := {}
	var res := {"nests": 0, "nests with wood through the middle": 0, "nests with wood through the rim (2 of 6 points or more)": 0,
		"sitting noddies": 0, "noddies in the wood": 0, "terns and eggs": 0, "terns in the wood": 0}
	var tests: Array = []
	for n: Node3D in co.nests:
		tests.append(["nest", n.global_position, n.scale.x])
	for p: Dictionary in co._perches:
		if p["kind"] == "WhiteTernPerched":
			tests.append(["tern", p["pos"], 1.0])
		elif p["node"] != null:
			tests.append(["noddy", p["pos"], 1.0])
	for e: Array in tests:
		var at: Vector3 = e[1]
		var near: Array = trees.duplicate()
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["xf"] as Transform3D).origin.distance_squared_to(at) < (b["xf"] as Transform3D).origin.distance_squared_to(at))
		var mid := false
		var rim := 0
		for k in mini(2, near.size()):
			var t: Dictionary = near[k]
			var key := String(t["kind"]) + "Bark"
			if not faces.has(key):
				faces[key] = (ls._tree_parts[key] as Mesh).get_faces()
			var inv := (t["xf"] as Transform3D).affine_inverse()
			if e[0] == "nest":
				mid = mid or _inside(faces[key], inv * (at + Vector3(0, 0.12, 0)))
				for i in 6:
					if _inside(faces[key], inv * (at + Vector3(cos(i * 1.047), 0.6, sin(i * 1.047)) * 0.14 * float(e[2]))):
						rim += 1
			else:
				mid = mid or _inside(faces[key], inv * (at + Vector3(0, 0.05 if e[0] == "noddy" else 0.08, 0)))
		if e[0] == "nest":
			res["nests"] += 1
			res["nests with wood through the middle"] += 1 if mid else 0
			res["nests with wood through the rim (2 of 6 points or more)"] += 1 if rim >= 2 else 0
		elif e[0] == "noddy":
			res["sitting noddies"] += 1
			res["noddies in the wood"] += 1 if mid else 0
		else:
			res["terns and eggs"] += 1
			res["terns in the wood"] += 1 if mid else 0
	res["places asked for / found / none"] = co.seat_stats
	# how much foliage hangs under each nest (cells of half a meter with leaves, in the nine
	# columns below it): 0 or 1 shows from the ground
	var below: Array = []
	for n: Node3D in co.nests:
		var at := n.global_position
		var near: Array = trees.duplicate()
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["xf"] as Transform3D).origin.distance_squared_to(at) < (b["xf"] as Transform3D).origin.distance_squared_to(at))
		var t: Dictionary = near[0]
		below.append(co._leaves_below(t["kind"], (t["xf"] as Transform3D).affine_inverse() * at))
	below.sort()
	var open := 0
	for b: int in below:
		if b <= 1:
			open += 1
	res["nests open from below"] = open
	res["leaf cells under a nest (median, most)"] = [below[below.size() / 2], below[-1]] if below.size() > 0 else []
	return res


## What a walker sees of the nests: for each nest, from how many of eight places 7 m away (the
## eyes 1.65 m over the ground) the line to it is free of leaves. The leaves are taken as the
## colony's cells of half a meter that hold any, which is coarser than leaves are: the numbers
## are for comparing one way of placing with another, not for the truth of a single nest.
func sight_report(main: Node) -> Dictionary:
	var co := main.get_node("Colony")
	var ls := main.get_node("Landscape")
	var grid := {}
	for t: Dictionary in ls.tree_spots:
		if not ls._tree_parts.has(String(t["kind"]) + "Bark"):
			continue
		var xf: Transform3D = t["xf"]
		if Vector2(xf.origin.x - ls.colony_center.x, xf.origin.z - ls.colony_center.y).length() > 45.0:
			continue
		var cells: Dictionary = co._leaves(t["kind"])
		for c: Vector3i in cells:
			var w := xf * ((Vector3(c) + Vector3(0.5, 0.5, 0.5)) * 0.5)
			grid[Vector3i(floori(w.x * 2.0), floori(w.y * 2.0), floori(w.z * 2.0))] = true
	var seen: Array = []
	for n: Node3D in co.nests:
		var at := n.global_position + Vector3(0, 0.1, 0)
		var dirs := 0
		for k in 8:
			var q := Vector2(at.x, at.z) + Vector2.from_angle(k * 0.785) * 7.0
			var eye := Vector3(q.x, float(ls.ground(q.x, q.y)) + 1.65, q.y)
			var len := eye.distance_to(at)
			var free := true
			var s := 0.0
			while s < len - 0.5:
				var p := eye.lerp(at, s / len)
				if grid.has(Vector3i(floori(p.x * 2.0), floori(p.y * 2.0), floori(p.z * 2.0))):
					free = false
					break
				s += 0.2
			if free:
				dirs += 1
		seen.append(dirs)
	seen.sort()
	var some := 0
	var half := 0
	var sum := 0
	for d: int in seen:
		some += 1 if d >= 1 else 0
		half += 1 if d >= 4 else 0
		sum += d
	return {"nests": seen.size(), "seen from at least one of 8 sides": some, "from four or more": half,
		"sides a nest is seen from (mean)": snappedf(float(sum) / maxi(1, seen.size()), 0.01), "leaf cells in the grid": grid.size()}
