extends Node
## Test tool (tools/shot.gd: "add_tool('res://tools/heights_check.gd', 'HC')"): the shared
## height map (scripts/heights.gd) against a script's own reader, at `n` random places
## (some beyond the map's edge): "main.get_node('HC').against(node, '_ground', 'with_rocks', -30.0, tide, n)".
## Gives the greatest difference; 0 means the same numbers to the last bit.
## `sample(n)` gives a checksum of what the game's readers answer at fixed places: the same
## before and after a change means nothing an animal asks has moved.
const Heights := preload("res://scripts/heights.gd")

func against(node: Object, method: String, mine: String, outside: float, minus: float, n: int, vec := false) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var differ := 0
	var at := Vector2.ZERO
	for i in n:
		var x := rng.randf_range(-262.0, 262.0)
		var z := rng.randf_range(-262.0, 262.0)
		if i % 3 == 0:        # (more of them where it matters: the island and its lagoon)
			x = rng.randf_range(-120.0, 100.0)
			z = rng.randf_range(-230.0, 230.0)
		var old: float = node.call(method, Vector2(x, z)) if vec else node.call(method, x, z)
		var new_: float
		if mine == "ground":
			new_ = Heights.ground(x, z)
		elif mine == "terrain":
			new_ = Heights.terrain(x, z, outside) - minus
		else:
			new_ = Heights.with_rocks(x, z, outside) - minus
		var d := absf(old - new_)
		if d > 0.0:
			differ += 1
		if d > worst:
			worst = d
			at = Vector2(x, z)
	return "%s.%s against Heights.%s: %d of %d places differ, at the most by %.6f m (at %s)" % [node.name, method, mine, differ, n, worst, at]


func sample(nodes: Array, methods: Array, n: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var out := ""
	for k in nodes.size():
		var sum := 0.0
		rng.seed = 11
		for i in n:
			var x := rng.randf_range(-262.0, 262.0)
			var z := rng.randf_range(-262.0, 262.0)
			sum += float(nodes[k].call(methods[k], Vector2(x, z)) if methods[k] == "ground_height" else nodes[k].call(methods[k], x, z))
		out += "%s.%s %.9f  " % [nodes[k].name, methods[k], sum]
	return out


## What one more copy of the picture costs in memory (MB): what each of the six scripts
## held until 2026-11-12.
func copy_cost() -> String:
	var before := OS.get_static_memory_usage()
	var held: Array = []
	for i in 3:
		held.append((load("res://assets/textures/heightmap.exr") as Texture2D).get_image())
	var each := float(OS.get_static_memory_usage() - before) / 3.0 / 1048576.0
	var fmt: int = (held[0] as Image).get_format()
	held.clear()
	return "a copy of the height map: %.1f MB (format %d); the game holds %.0f MB now" % [each, fmt, OS.get_static_memory_usage() / 1048576.0]


## Where the .blend's rocks stand in the water (green above red there): how many pixels,
## and at the rock that stands highest over its floor, how deep the water is to the rock
## and to the floor, and what share of the open swell each depth gives (sealife.gd
## `wave_height()` took the first until 2026-11-12, the ocean's shader the second).
func rock_swell() -> String:
	var n := 0
	var best := 0.0
	var at := Vector2.ZERO
	var w := Heights.width()
	for py in range(0, Heights.height(), 2):
		for px in range(0, w, 2):
			var r := Heights.pixel(px, py, 0)
			var g := Heights.pixel(px, py, 1)
			if r < -0.3 and g - r > 0.05 and g < 0.0:
				n += 1
				if g - r > best:
					best = g - r
					at = Vector2((px + 0.5) / w * 512.0 - 256.0, (py + 0.5) / w * 512.0 - 256.0)
	var r0 := Heights.terrain(at.x, at.y, 0.0)
	var g0 := Heights.with_rocks(at.x, at.y, 0.0)
	return "%d pixels of sunken rock; at %s the water is %.2f m deep to the rock and %.2f m to the floor: the swell's share %.2f against %.2f" % [n * 4, at, -g0, -r0,
		lerpf(0.12, 1.0, smoothstep(0.3, 6.0, -g0)), lerpf(0.12, 1.0, smoothstep(0.3, 6.0, -r0))]
