extends Node3D
## What lives on the floor of the lagoon, modeled (the ground shader only paints it): seagrass
## where the shader paints its dark meadows; corals on the coral heads, the reef edge and its
## slope (staghorn thickets, cauliflower and finger corals, boulder and brain corals, tables,
## whorls of plates, fire coral, leather corals, sea fans), growing in patches of one kind as
## they do; and black long-spined sea urchins (Diadema setosum) in clusters on the hard ground,
## in its hollows, at the foot of the big corals and of the shore rocks; sea stars (blue ones and
## cushion stars on the reef, red-knobbed ones on the sand and in the seagrass) and giant clams
## set in the reef, their lips a little open and the bright mantle showing; sea anemones (the
## carpet anemone on the reef, the magnificent anemone on the tops of coral heads: the
## anemonefish that live in them are scripts/reef_life.gd's).
##
## Seen by a snorkeler (player.gd: swim out, look down) and, as shapes and colors, through the
## surface from above. Everything is built in code, a few 8 m cells of sea floor per frame after
## the start (nearest the start beach first), so nothing stalls; each cell is one MultiMesh per
## kind with a visibility range (the corals in two levels of detail).
## The node is created by island_life.gd.

const ReefModels := preload("res://scripts/reef_models.gd")
const HM_EXT := 256.0
const CELL := 8.0
const GRASS_PER_M2 := 8.0
const CORAL_PER_M2 := 4.6          # candidates per m2 of hard ground; about half find room
const URCHIN_SEEDS_PER_M2 := 0.1   # places where a cluster of urchins may sit
const CELLS_PER_FRAME := 3
const NEAR := 24.0                 # corals: the full models to here, simple stand-ins beyond
const FAR := 75.0
const BUCKET := 2.2

var _ls: Node
var _world: Node
var _rng := RandomNumberGenerator.new()
var _prng := RandomNumberGenerator.new()   # per patch of reef: which coral rules there
var _noise: Image              # the ground shader's macro noise: the meadows lie where it paints them
var _mask: Image
var _queue: Array = []         # cells still to build: Vector2 (corner)
var _grass_mesh: ArrayMesh
var _grass_mat: ShaderMaterial
var _kinds: Array = []         # the corals: one dictionary per kind (see setup())
var _far_meshes: Array = []    # stand-ins beyond NEAR: a branching tuft, a dome, a plate on a stalk
var _coral_mat: ShaderMaterial
var _urchin_mesh: ArrayMesh
var _urchin_mat: ShaderMaterial
var _uv := Vector2.ZERO        # what the mesh builders write as UV (y: how much the part sways)
var _rocks_left := true        # urchins around the shore rocks: placed once the cells are done
var _xr := RandomNumberGenerator.new()     # sea stars and clams: seeded per cell (so they can be
                                           # changed without moving a single coral or urchin)
var _stars: Array = []         # [mesh, colors, where: "reef" / "sand", share of the candidates, footprint]
var _clam_shell: ArrayMesh
var _clam_mantle: ArrayMesh
## numbers for the notes and the tests
var grass_tufts := 0
var corals := 0
var urchins := 0
var urchin_spots: Array = []   # Vector3: one per cluster (for the tests, and for looking at them)
var forage_spots: Array = []   # [Vector2, radius, height]: sizeable corals a hawksbill may feed at (turtles.gd)
var cells_done := 0
var stars := 0
var clams := 0
var star_spots: Array = []     # Vector3, the first hundred (for looking at them)
var clam_spots: Array = []
var _anem_meshes: Array = []   # carpet anemone, magnificent anemone
var _anem_mats: Array = []
var anemone_spots: Array = []  # [Vector3 the middle of the disc, its radius, kind (0 carpet, 1 magnificent)]: reef_life.gd
var big_corals: Array = []     # [Vector2, radius, height, ground]: every large colony (reef_life.gd: the lionfish)
var den_spots: Array = []      # Vector3: gaps between the corals, 0.36 m of room around each (reef_life.gd)
var edge_spots: Array = []     # Vector3: open sand 1-2 m from the reef (reef_life.gd: the octopuses' dens)
var sand_spots: Array = []     # Vector3: middles of patches of bare level sand 3.3-6.3 m down (reef_life.gd: garden eels)
var overhangs: Array = []      # [Vector2, radius]: corals that reach out further than they stand (tables, plates, fans)
var _occupied := {}            # everything that stands on the floor, all cells together (room())
## The coral garden: one stretch of reef that is covered with coral from end to end. The reef
## crest off the start beach, some 75 m out (the ridge the swell breaks on, with the pass
## through it), its back and the top of the slope beyond: a belt 70 m long and some 22 m
## wide along this line. Elsewhere corals stand on the hard ground only, which is a lattice
## with sand between; here they stand on the sand between too, and closer.
## It is grown AFTER everything else, the reef's animals included (reef_life.gd calls
## grow_garden() when its dens, lionfish and eels have their places), with random numbers of
## its own: no coral, urchin, clam, den or fish that was there before stands anywhere else
## for it (tools/reef_placements.gd shows that).
const GARDEN: Array[Vector2] = [Vector2(71.5, -56.0), Vector2(71.5, -44.0), Vector2(73.5, -36.0), Vector2(75.5, -28.0), Vector2(78.5, -20.0), Vector2(80.5, -12.0),
	Vector2(82.5, -4.0), Vector2(83.5, 4.0), Vector2(83.5, 14.0)]
const GARDEN_HALF := 11.0
const GARDEN_PER_M2 := 7.0         # candidates per m2 of the garden; most of the floor is taken already or soon
var garden_corals := 0
var _gr := RandomNumberGenerator.new()
var _garden_queue: Array = []
var _garden_started := false
var _garden_keep := {}             # what the garden's corals keep off (buckets like _occupied): [Vector2, radius]
var _garden_keep_wide: Array = []  # the same, for wide circles (an eel colony, the grouper's home)
var _garden_painted := false
## Urchins that would lie dry at low water (the sea falls to -0.80 at spring tides; they were
## placed when it stood at 0, down to 0.45 m): they are kept back when their cell is built
## and set further down the slope, under water at any tide, when everything else has its
## place (_move_dry_urchins). The places they were given first stay taken on the floor's map:
## nothing else moves for it.
const URCHIN_DRY := -1.1           # an urchin on ground above this would show at low water
var urchins_moved := 0
var urchins_dropped := 0           # no deeper ground within reach (a hollow in the rock)
var urchin_highest := -99.0        # the highest ground an urchin sits on (for the tests)
var _dry_urchins: Array = []       # Transform3D
var _ur := RandomNumberGenerator.new()
var _moved_put := {}
var _rock_urchins_done := false
## How much of the floor lies under coral, by 8 m cell (the share of each cell): for the
## reef's sound (player.gd), which is as loud as there is coral about.
var _cover := {}

const GRASS_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sea_light.gdshaderinc"
// Seagrass: the blades lean and swing with the swell passing overhead, the tips most.
global uniform float world_time;
varying float v_h;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = UV.y * UV.y;
	float a = sin(world_time * 1.25 + w.x * 0.55 + w.z * 0.31) * 0.11 + sin(world_time * 0.47 + w.z * 0.2) * 0.07;
	float b = sin(world_time * 0.9 + w.x * 0.23 - w.z * 0.4) * 0.05;
	w.x += (a - 0.05) * k * 1.0;
	w.z += b * k;
	w.y -= abs(a) * k * 0.12;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	v_h = UV.y;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.0;
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
	// light shining through the blades
	BACKLIGHT = vec3(0.1, 0.16, 0.04) * v_h;
}"""

const CORAL_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sea_light.gdshaderinc"
// Corals. COLOR.rgb: the colony's color (vertex shade x instance color, sRGB). COLOR.a names
// the surface: 1 plain, 0.8 brain coral (meandering ridges), 0.6 boulder coral (mottled),
// 0.4 table (rings of growth), 0.2 the mantle of a giant clam. UV.y > 0: a soft part that sways with the swell (sea fans,
// leather corals), more the higher it stands.
global uniform float world_time;
varying vec3 o_pos;
float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	o_pos = VERTEX;
	if (UV.y > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = UV.y * VERTEX.y * VERTEX.y;
		float a = sin(world_time * 1.25 + w.x * 0.55 + w.z * 0.31) * 0.11 + sin(world_time * 0.47 + w.z * 0.2) * 0.07;
		VERTEX.z += a * k;
		VERTEX.x += sin(world_time * 0.9 + w.x * 0.23 - w.z * 0.4) * 0.04 * k;
	}
}
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float pat = COLOR.a;
	float dist = -VERTEX.z;
	// the polyps: a fine grain on everything, seen from close by
	float close = 1.0 - smoothstep(3.0, 9.0, dist);
	c *= mix(1.0, 0.78 + 0.44 * vn(o_pos * 170.0), close);
	float mid = 1.0 - smoothstep(8.0, 22.0, dist);
	if (pat < 0.9) {
		if (pat > 0.7) {
			// brain coral: ridges that wander and never cross, dark valleys between them
			float m = vn(o_pos * 11.0) * 2.0 + vn(o_pos * 27.0) * 0.8;
			float ridge = abs(fract(m * 8.0) - 0.5) * 2.0;
			c *= mix(0.85, mix(0.42, 1.2, smoothstep(0.2, 0.7, ridge)), mid);
		} else if (pat > 0.5) {
			// boulder coral: mottled, with paler patches
			c *= mix(1.0, 0.8 + 0.4 * vn(o_pos * 11.0), mid);
		} else if (pat > 0.3) {
			// table: rings of growth around the middle, the branchlets as a coarse grain
			float r = length(o_pos.xz - vec2(0.03, 0.02));
			c *= mix(1.0, (0.95 + 0.07 * sin(r * 70.0 + vn(o_pos * 9.0) * 5.0)) * (0.82 + 0.36 * vn(o_pos * 60.0)), mid * mid);
		} else {
			// a giant clam's mantle: dark blotches, a scatter of bright points, a dark slit
			// along the middle where it opens
			float blot = vn(o_pos * 55.0);
			c *= mix(1.0, 0.35 + 1.1 * blot, mid);
			float dots = smoothstep(0.72, 0.8, vn(o_pos * 210.0 + 7.0));
			c = mix(c, c * 1.6 + vec3(0.1, 0.22, 0.2), dots * close);
			c *= mix(1.0, 0.25, (1.0 - smoothstep(0.004, 0.011, abs(o_pos.z))) * (1.0 - smoothstep(0.05, 0.09, abs(o_pos.x))));
		}
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
void light() {
	// the sea scatters the light: it comes from all around, and the side away from the sun is
	// dim, not black
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.75) / 1.75, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * (0.35 + 0.65 * ATTENUATION) * LIGHT_COLOR / PI;
}"""

const URCHIN_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Long-spined sea urchin. UV.x >= 0 marks a spine (its own phase), UV.y runs along it.
global uniform float world_time;
void vertex() {
	if (UV.x >= 0.0) {
		// the spines turn slowly, each for itself
		float k = UV.y * UV.y;
		float ph = UV.x * 6.283 + float(INSTANCE_ID) * 1.7;
		VERTEX.x += sin(world_time * 0.7 + ph * 3.0) * 0.024 * k;
		VERTEX.z += cos(world_time * 0.55 + ph * 5.0) * 0.024 * k;
		// and are never drawn much thinner than a pixel: from a few meters away they would
		// flicker and vanish, and the animal would be a bare black ball
		float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		VERTEX += NORMAL * clamp(dist * 0.0006 - 0.002, 0.0, 0.005);
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
}"""


func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func setup(ls: Node) -> void:
	_ls = ls
	_world = ls.get_parent()
	_rng.seed = 7711
	_mask = ls._mask
	_grass_mesh = _tuft_mesh()
	_grass_mat = _shader_mat(GRASS_SHADER)
	_coral_mat = _shader_mat(CORAL_SHADER)
	_urchin_mesh = _urchin()
	_urchin_mat = _shader_mat(URCHIN_SHADER)
	_far_meshes = [_branching_mesh(1, true), _massive_mesh(3, true, false), _table_mesh(4, true)]
	_stars = [
		# the blue sea star, on the reef (now and then an orange one)
		[_star_mesh(0), [Color(0.1, 0.26, 0.8), Color(0.12, 0.32, 0.85), Color(0.16, 0.22, 0.72), Color(0.1, 0.28, 0.78), Color(0.75, 0.4, 0.14)], "reef", 0.07, 0.1],
		# the red-knobbed sea star, on sand and in the seagrass
		[_star_mesh(1), [Color(0.76, 0.7, 0.6), Color(0.68, 0.62, 0.55), Color(0.8, 0.72, 0.58)], "sand", 0.012, 0.13],
		# cushion stars, on the reef
		[_star_mesh(2), [Color(0.6, 0.45, 0.4), Color(0.5, 0.5, 0.4), Color(0.62, 0.4, 0.45), Color(0.45, 0.4, 0.5)], "reef", 0.02, 0.11],
	]
	_anem_meshes = [ReefModels.carpet_anemone(), ReefModels.magnificent_anemone()]
	for k in 2:
		var am := ShaderMaterial.new()
		am.shader = load("res://shaders/anemone.gdshader")
		am.set_shader_parameter("sway", 0.05 if k == 0 else 0.3)
		am.set_shader_parameter("flap", 0.035 if k == 0 else 0.0)
		am.set_shader_parameter("vivid_column", k == 1)
		_anem_mats.append(am)
	var cm := _clam_meshes()
	_clam_shell = cm[0]
	_clam_mantle = cm[1]
	# mesh; which stand-in beyond NEAR (and its size against the model's); the colors it comes
	# in; depth range; share; size range; how often a colony is a big old one, and how big at
	# most; its footprint and height at size 1
	var tan_ := Color(0.62, 0.5, 0.34)
	_kinds = [
		# staghorn thickets: tan, brown-yellow, pale blue, pink
		{"mesh": _branching_mesh(1, false), "far": 0, "fs": 1.0, "cols": [tan_, Color(0.6, 0.52, 0.26), Color(0.5, 0.56, 0.72), Color(0.72, 0.5, 0.5)],
			"d0": 1.5, "d1": 14.0, "w": 0.2, "s0": 0.7, "s1": 1.5, "big": 0.14, "bigx": 2.3, "rad": 0.26, "top": 0.38},
		{"mesh": _branching_mesh(2, false), "far": 0, "fs": 1.0, "cols": [tan_, Color(0.55, 0.6, 0.4), Color(0.74, 0.55, 0.42)],
			"d0": 1.5, "d1": 14.0, "w": 0.12, "s0": 0.7, "s1": 1.5, "big": 0.14, "bigx": 2.3, "rad": 0.26, "top": 0.38},
		# boulder corals: also on the shallow crest; old ones are bommies a man's height across
		{"mesh": _massive_mesh(3, false, false), "far": 1, "fs": 1.0, "cols": [Color(0.6, 0.55, 0.28), Color(0.45, 0.5, 0.3), Color(0.62, 0.5, 0.4), Color(0.5, 0.42, 0.5)],
			"d0": 0.6, "d1": 18.0, "w": 0.14, "s0": 0.5, "s1": 1.6, "big": 0.16, "bigx": 3.2, "rad": 0.3, "top": 0.29, "foot": true},
		# brain corals
		{"mesh": _massive_mesh(6, false, true), "far": 1, "fs": 0.95, "cols": [Color(0.42, 0.5, 0.3), Color(0.6, 0.5, 0.3), Color(0.5, 0.48, 0.42), Color(0.55, 0.42, 0.36)],
			"d0": 0.8, "d1": 16.0, "w": 0.08, "s0": 0.5, "s1": 1.4, "big": 0.12, "bigx": 2.4, "rad": 0.28, "top": 0.27, "foot": true},
		# tables
		{"mesh": _table_mesh(4, false), "far": 2, "fs": 1.0, "cols": [Color(0.62, 0.52, 0.36), Color(0.5, 0.55, 0.42), Color(0.6, 0.48, 0.5)],
			"d0": 2.2, "d1": 14.0, "w": 0.09, "s0": 0.7, "s1": 1.5, "big": 0.2, "bigx": 2.4, "rad": 0.42, "top": 0.3},
		# sea fans
		{"mesh": _fan_mesh(5), "far": -1, "fs": 1.0, "cols": [Color(0.5, 0.22, 0.55), Color(0.82, 0.32, 0.14), Color(0.8, 0.62, 0.2)],
			"d0": 3.0, "d1": 18.0, "w": 0.05, "s0": 0.7, "s1": 1.6, "big": 0.0, "bigx": 1.0, "rad": 0.1, "top": 0.6},
		# cauliflower corals: pink, cream-brown, lavender
		{"mesh": _cauli_mesh(7), "far": 1, "fs": 0.85, "cols": [Color(0.74, 0.52, 0.5), Color(0.66, 0.54, 0.4), Color(0.6, 0.52, 0.64), Color(0.5, 0.5, 0.34)],
			"d0": 0.6, "d1": 10.0, "w": 0.12, "s0": 0.6, "s1": 1.3, "big": 0.0, "bigx": 1.0, "rad": 0.24, "top": 0.27},
		# finger corals: yellow-tan, lavender
		{"mesh": _finger_mesh(8), "far": 0, "fs": 0.95, "cols": [Color(0.7, 0.6, 0.3), Color(0.6, 0.54, 0.66), Color(0.62, 0.5, 0.34)],
			"d0": 1.2, "d1": 10.0, "w": 0.08, "s0": 0.7, "s1": 1.6, "big": 0.1, "bigx": 2.0, "rad": 0.24, "top": 0.34},
		# whorls of thin plates
		{"mesh": _plate_mesh(9), "far": 2, "fs": 0.8, "cols": [Color(0.58, 0.6, 0.32), Color(0.56, 0.44, 0.3), Color(0.52, 0.46, 0.52)],
			"d0": 2.5, "d1": 18.0, "w": 0.06, "s0": 0.8, "s1": 1.8, "big": 0.15, "bigx": 2.2, "rad": 0.33, "top": 0.26},
		# fire coral: mustard blades, in the shallows
		{"mesh": _fire_mesh(10), "far": 0, "fs": 0.9, "cols": [Color(0.74, 0.6, 0.24), Color(0.66, 0.52, 0.26)],
			"d0": 0.6, "d1": 6.0, "w": 0.05, "s0": 0.7, "s1": 1.4, "big": 0.1, "bigx": 1.8, "rad": 0.22, "top": 0.3},
		# leather corals (soft): cream, ochre-gray, pale green
		{"mesh": _leather_mesh(11), "far": 1, "fs": 0.75, "cols": [Color(0.74, 0.68, 0.5), Color(0.62, 0.58, 0.46), Color(0.6, 0.66, 0.46)],
			"d0": 1.5, "d1": 12.0, "w": 0.05, "s0": 0.6, "s1": 1.5, "big": 0.0, "bigx": 1.0, "rad": 0.23, "top": 0.21},
	]
	# (how far each kind reaches out from where it stands, at size 1)
	for kd: Dictionary in _kinds:
		var bb: AABB = (kd["mesh"] as Mesh).get_aabb()
		kd["reach"] = maxf(maxf(absf(bb.position.x), absf(bb.end.x)), maxf(absf(bb.position.z), absf(bb.end.z)))
	# cells that hold sea floor at a depth where anything grows, nearest the start beach first
	var x := -250.0
	while x < 140.0:
		var z := -250.0
		while z < 250.0:
			var deepest := 0.0
			var shallowest := 99.0
			for o in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
				var d: float = -_ls.ground(x + o.x * CELL, z + o.y * CELL)
				deepest = maxf(deepest, d)
				shallowest = minf(shallowest, d)
			if deepest > 0.5 and shallowest < 17.0:
				_queue.append(Vector2(x, z))
			z += CELL
		x += CELL
	var start := Vector2(4.0, 40.0)
	_queue.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(start) > b.distance_squared_to(start))


func _process(_delta: float) -> void:
	if _queue.is_empty():
		if _garden_queue.is_empty():
			# (last of all: the rocks that stand in the water, for whatever swims)
			if garden_done() and not rocks_done():
				if not _rocks_listed:
					_list_rocks()
				_measure_rocks(500)
				return
			set_process(false)
			return
		for k in 2:
			if not _garden_queue.is_empty():
				_build_garden_cell(_garden_queue.pop_back())
		return
	if _noise == null:
		# (the noise texture is generated in the background: wait for it)
		var sand: ShaderMaterial = _world.get_material("Sand") if _world.has_method("get_material") else null
		var tex: Texture2D = sand.get_shader_parameter("macro_noise") if sand else null
		_noise = tex.get_image() if tex else null
		if _noise == null:
			return
		if _noise.is_compressed():
			_noise.decompress()
		_paint_garden_floor()
	for k in CELLS_PER_FRAME:
		if _queue.is_empty():
			break
		_build_cell(_queue.pop_back())
		cells_done += 1


func _physics_process(_delta: float) -> void:
	# (the shore rocks are found with ray casts: their collision shapes must be there)
	if _rocks_left and _queue.is_empty() and Engine.get_physics_frames() > 30:
		_rocks_left = false
		_rock_urchins()
		set_physics_process(false)


## The noise as the ground shader reads it: texture(macro_noise, uv).r, repeating, bilinear.
func _n(uv: Vector2) -> float:
	var w := _noise.get_width()
	var h := _noise.get_height()
	var u := fposmod(uv.x, 1.0) * w - 0.5
	var v := fposmod(uv.y, 1.0) * h - 0.5
	var x0 := int(floorf(u))
	var y0 := int(floorf(v))
	var fx := u - x0
	var fy := v - y0
	var a := lerpf(_noise.get_pixel(posmod(x0, w), posmod(y0, h)).r, _noise.get_pixel(posmod(x0 + 1, w), posmod(y0, h)).r, fx)
	var b := lerpf(_noise.get_pixel(posmod(x0, w), posmod(y0 + 1, h)).r, _noise.get_pixel(posmod(x0 + 1, w), posmod(y0 + 1, h)).r, fx)
	return lerpf(a, b, fy)


func _mask_at(p: Vector2) -> Color:
	var u := int(clampf((p.x + HM_EXT) / (2.0 * HM_EXT) * _mask.get_width(), 0, _mask.get_width() - 1))
	var v := int(clampf((p.y + HM_EXT) / (2.0 * HM_EXT) * _mask.get_height(), 0, _mask.get_height() - 1))
	return _mask.get_pixel(u, v)


## How thick the seagrass stands at p (0 none .. 1), as sand.gdshader paints it (keep the two in
## step). Only valid once the noise image is there (`ready_for_meadows()`).
func meadow(p: Vector2) -> float:
	var y: float = _ls.ground(p.x, p.y)
	var band := smoothstep(-1.9, -2.7, y) * smoothstep(-7.0, -5.2, y)
	if band < 0.05 or _noise == null:
		return 0.0
	if _mask_at(p).g > 0.3:
		return 0.0
	return smoothstep(0.5, 0.58, _n(p * 0.027 + Vector2(0.21, 0.21)) + (_n(p * 0.29) - 0.5) * 0.3) * band


func ready_for_meadows() -> bool:
	return _noise != null


## Hard reef at p (coral rock under water, not the headland's granite)?
func reef(p: Vector2) -> bool:
	var mk := _mask_at(p)
	return mk.g >= 0.5 and mk.b <= 0.3 and _ls.ground(p.x, p.y) < -0.6


## Is the whole sea floor built?
func done() -> bool:
	return _queue.is_empty() and _noise != null


## Is there room on the floor at p for something of radius r, among everything that stands
## there (corals, urchins, sea stars, clams, anemones)? Only valid for cells already built.
func room(p: Vector2, r: float, f := 1.0) -> bool:
	return _room(_occupied, p, r, f)


## Does a coral that spreads out above its foot (a table, a plate, a fan) reach to within r
## of p? (`room()` knows only where things stand.)
func overhung(p: Vector2, r: float) -> bool:
	for o: Array in overhangs:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + r:
			return true
	return false


func occupy(p: Vector2, r: float) -> void:
	_put(_occupied, p, r)


const TOP_CELL := 3.0
var _tops := {}     # Vector2i cell -> [[Vector2, radius, height of its top (absolute)]]


## Something stands at p, `rad` wide, reaching up to the height `y` (corals; reef_life.gd adds
## its den rocks): a diver keeps above it.
func add_top(p: Vector2, rad: float, y: float, rock := false) -> void:
	var c := Vector2i(int(floorf(p.x / TOP_CELL)), int(floorf(p.y / TOP_CELL)))
	if not _tops.has(c):
		_tops[c] = []
	(_tops[c] as Array).append([p, rad, y, rock])
	# ... and into the map of heights (coral_top())
	if _coral_map.is_empty():
		_coral_map.resize(GRID_N * GRID_N)
		_coral_map.fill(-99.0)
	if rock and _rock_map.is_empty():
		_rock_map.resize(GRID_N * GRID_N)
		_rock_map.fill(-99.0)
	var r := rad + 0.3
	var x0 := clampi(int(floorf((p.x - r + GRID_EXT) / GRID_CELL)), 0, GRID_N - 1)
	var x1 := clampi(int(floorf((p.x + r + GRID_EXT) / GRID_CELL)), 0, GRID_N - 1)
	var z0 := clampi(int(floorf((p.y - r + GRID_EXT) / GRID_CELL)), 0, GRID_N - 1)
	var z1 := clampi(int(floorf((p.y + r + GRID_EXT) / GRID_CELL)), 0, GRID_N - 1)
	for iz in range(z0, z1 + 1):
		var dz := (iz + 0.5) * GRID_CELL - GRID_EXT - p.y
		for ix in range(x0, x1 + 1):
			var dx := (ix + 0.5) * GRID_CELL - GRID_EXT - p.x
			if dx * dx + dz * dz > r * r:
				continue
			# (rocks have a map of their own: the tests can take them out again)
			if rock:
				if y > _rock_map[iz * GRID_N + ix]:
					_rock_map[iz * GRID_N + ix] = y
			elif y > _coral_map[iz * GRID_N + ix]:
				_coral_map[iz * GRID_N + ix] = y


## The same as a map, for the animals that swim (sealife.gd, fish.gd: they ask many times a
## frame, and a shark plans a whole route): the top of the tallest coral or den rock over
## each half meter of the sea floor (absolute height; -99 where nothing stands). A coral
## counts 0.3 m wider than it is, so that the map never says "free" inside one.
const GRID_EXT := 256.0
const GRID_CELL := 0.5
const GRID_N := 1024
var _coral_map := PackedFloat32Array()


func coral_top(x: float, z: float) -> float:
	if _coral_map.is_empty():
		return -99.0
	var ix := int((x + GRID_EXT) / GRID_CELL)
	var iz := int((z + GRID_EXT) / GRID_CELL)
	if ix < 0 or iz < 0 or ix >= GRID_N or iz >= GRID_N:
		return -99.0
	var v := _coral_map[iz * GRID_N + ix]
	if rocks_solid:
		if not _rock_map.is_empty():
			v = maxf(v, _rock_map[iz * GRID_N + ix])
	return v


# ------------------------------------------------------------------ rocks in the water
## The boulders that stand in the sea or at its edge are solid to whatever swims, as the
## corals are: the 236 that landscape.gd scatters around the coast, and the big ones of the
## start beach from the .blend. They had bodies for the walker only (found by the code
## review of 2026-11-12: a young reef shark's home lay among four of them). Each is
## measured where it stands, with rays from above, a column of rock for every half meter
## of its outline, and written into `_tops` and into a map of its own beside the corals'.
## Done last (after reef_life.gd has placed its animals and the coral garden has grown), so
## that nothing on the sea floor is placed differently for it.
## (For the tests: false is how it was.)
var rocks_solid := true
var rock_columns := 0
var _rock_map := PackedFloat32Array()
var _rock_queue: Array = []
var _rocks_listed := false


func rocks_done() -> bool:
	return _rocks_listed and _rock_queue.is_empty()


## Every half-meter place where a rock may stand in or at the water: the outlines of the
## boulders, where the ground is not above the highest tide's reach.
func _list_rocks() -> void:
	_rocks_listed = true
	var rects: Array = []
	for b: Array in _ls.boulder_spots:
		var c: Vector3 = b[0]
		var r := float(b[1]) * 0.8 + 0.5
		rects.append(Rect2(c.x - r, c.z - r, 2.0 * r, 2.0 * r))
	var rocks := _world.get_node_or_null("Rocks")
	if rocks:
		for mi: MeshInstance3D in rocks.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh:
				var box: AABB = mi.global_transform * mi.mesh.get_aabb()
				rects.append(Rect2(box.position.x - 0.5, box.position.z - 0.5, box.size.x + 1.0, box.size.z + 1.0))
	_mangrove_roots()
	var seen := {}
	for rc: Rect2 in rects:
		var x0 := int(floorf((rc.position.x + GRID_EXT) / GRID_CELL))
		var x1 := int(floorf((rc.end.x + GRID_EXT) / GRID_CELL))
		var z0 := int(floorf((rc.position.y + GRID_EXT) / GRID_CELL))
		var z1 := int(floorf((rc.end.y + GRID_EXT) / GRID_CELL))
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var key := Vector2i(ix, iz)
				if seen.has(key) or ix < 0 or iz < 0 or ix >= GRID_N or iz >= GRID_N:
					continue
				seen[key] = true
				var p := Vector2((ix + 0.5) * GRID_CELL - GRID_EXT, (iz + 0.5) * GRID_CELL - GRID_EXT)
				if float(_ls.ground(p.x, p.y)) < 0.4:
					_rock_queue.append(p)


## The mangroves that stand in the water: the cage of stilt roots around each trunk is
## solid to whatever swims, as a rock is (a fish could slip between the roots; nothing here
## is small and careful enough to be shown doing it). How wide the cage is, is read off the
## tree's own mesh: the furthest a root reaches at the ground.
var mangroves_solid := 0

func _mangrove_roots() -> void:
	var grove := _ls.get_node_or_null("Mangroves")
	if grove == null:
		return
	var reach := {}
	for mi: MeshInstance3D in grove.find_children("*", "MeshInstance3D", true, false):
		# (the bark: the one part of a mangrove that is drawn at every distance)
		if mi.mesh == null or mi.visibility_range_begin != 0.0 or mi.visibility_range_end != 0.0:
			continue
		if not reach.has(mi.mesh):
			var far := 0.0
			for s in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					if v.y < 0.5:
						far = maxf(far, Vector2(v.x, v.z).length())
			reach[mi.mesh] = far
		var at := mi.global_position
		var sc := mi.global_transform.basis.get_scale().x
		if float(reach[mi.mesh]) < 0.2 or float(_ls.ground(at.x, at.z)) > 0.4:
			continue
		add_top(Vector2(at.x, at.z), float(reach[mi.mesh]) * sc, at.y + 2.4 * sc, true)
		mangroves_solid += 1


# The anchored boat floats, and swings at its anchor: fauna.gd says where its hull lies,
# every frame (`set_boat()`). To whatever swims it is a ceiling, not a thing on the floor:
# under it an animal keeps below the keel (`boat_over()`: the fish, the turtles that come up
# to breathe, the manta, the rays, the jellyfish ask), and passes. (Tried first as a column
# from the floor to above the surface, like a rock: the animals answer a thing that stands
# under them by rising over it, and rose into the hull.)
const BOAT_DRAFT := 0.5
var _boat_c := Vector2.ZERO
var _boat_ax := Vector2.RIGHT
var _boat_half := Vector2.ZERO
var _boat_r2 := 0.0


## `xf`: the boat's place and heading; `box`: its hull in its own space (the flat outline).
func set_boat(xf: Transform3D, box: Rect2) -> void:
	var c := xf * Vector3(box.get_center().x, 0, box.get_center().y)
	_boat_c = Vector2(c.x, c.z)
	_boat_ax = Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
	_boat_half = box.size * 0.5
	_boat_r2 = pow(_boat_half.length() + 2.0, 2.0)


## How far (x, z) lies outside the hull's outline (0 or less: under the boat; 99: far off).
func _boat_dist(x: float, z: float) -> float:
	var dx := x - _boat_c.x
	var dz := z - _boat_c.y
	if dx * dx + dz * dz > _boat_r2:
		return 99.0
	return maxf(absf(dx * _boat_ax.x + dz * _boat_ax.y) - _boat_half.x, absf(-dx * _boat_ax.y + dz * _boat_ax.x) - _boat_half.y)


## The next `n` of those places: is there rock, and how high does it stand?
func _measure_rocks(n: int) -> void:
	var space := get_world_3d().direct_space_state
	for k in n:
		if _rock_queue.is_empty():
			return
		var p: Vector2 = _rock_queue.pop_back()
		var g: float = _ls.ground(p.x, p.y)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.y), Vector3(p.x, g - 0.5, p.y))
		ray.collision_mask = 1
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or (hit["position"] as Vector3).y < g + 0.25:
			continue
		# (rock only: the bodies of the rocks are marked for the rain's shadow, scripts/weather.gd)
		var body := hit["collider"] as CollisionObject3D
		if body == null:
			continue
		var shape := body.shape_owner_get_owner(body.shape_find_owner(int(hit["shape"]))) as Node
		if shape == null or int(shape.get_meta("rain", 0)) != 2:
			continue
		add_top(p, 0.36, (hit["position"] as Vector3).y, true)
		rock_columns += 1


## (for the tests) The top of the rock at p, whether the animals are told of it or not; -99
## where none stands.
func rock_at(p: Vector2) -> float:
	var best := -99.0
	var c := Vector2i(int(floorf(p.x / TOP_CELL)), int(floorf(p.y / TOP_CELL)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for t: Array in _tops.get(c + Vector2i(dx, dz), []):
				if t.size() > 3 and t[3] and (t[0] as Vector2).distance_to(p) <= float(t[1]):
					best = maxf(best, float(t[2]))
	return best


## Is (x, z) under the boat's hull, or within `margin` of its outline?
func boat_over(x: float, z: float, margin := 0.0) -> bool:
	return rocks_solid and _boat_r2 > 0.0 and _boat_dist(x, z) <= margin


## (for the tests: whether the animals are told of it or not)
func boat_at(x: float, z: float) -> bool:
	return _boat_r2 > 0.0 and _boat_dist(x, z) <= 0.0


## The height below which a diver at p would be in a coral or a rock (or in the sea floor):
## the top of what stands there, falling away over `skirt` meters beyond its edge, so that
## one glides up and over rather than being stopped.
func top_at(p: Vector2, skirt := 1.0, rocks := true) -> float:
	var best: float = _ls.ground(p.x, p.y)
	var c := Vector2i(int(floorf(p.x / TOP_CELL)), int(floorf(p.y / TOP_CELL)))
	var with_rocks := rocks and rocks_solid
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for t: Array in _tops.get(c + Vector2i(dx, dz), []):
				# (`rocks` false: the corals only. The diver asks so: the rocks stop a
				# swimmer with their own bodies, and one can dive along a boulder's flank)
				if not with_rocks and t.size() > 3 and t[3]:
					continue
				var d := (t[0] as Vector2).distance_to(p) - float(t[1])
				if d < skirt:
					best = maxf(best, float(t[2]) - maxf(d, 0.0) / skirt * 1.4)
	return best


func _normal(p: Vector2) -> Vector3:
	var e := 0.4
	return Vector3(_ls.ground(p.x - e, p.y) - _ls.ground(p.x + e, p.y), 2.0 * e, _ls.ground(p.x, p.y - e) - _ls.ground(p.x, p.y + e)).normalized()


## Which coral grows at this depth, for a random number r (0..1): by the kinds' shares.
func _pick(depth: float, r: float) -> int:
	var total := 0.0
	for kd: Dictionary in _kinds:
		if depth >= float(kd["d0"]) and depth <= float(kd["d1"]):
			total += float(kd["w"])
	r *= total
	for k in _kinds.size():
		var kd: Dictionary = _kinds[k]
		if depth < float(kd["d0"]) or depth > float(kd["d1"]):
			continue
		r -= float(kd["w"])
		if r <= 0.0:
			return k
	return -1


## Is there room at p for something of radius r? (`placed`: what stands in this cell already, in
## buckets; two things may overlap by the share 1 - f of their radii.)
func _room(placed: Dictionary, p: Vector2, r: float, f: float) -> bool:
	var bx := floori(p.x / BUCKET)
	var by := floori(p.y / BUCKET)
	for ix in range(bx - 1, bx + 2):
		for iy in range(by - 1, by + 2):
			for o: Array in placed.get(Vector2i(ix, iy), []):
				if (o[0] as Vector2).distance_to(p) < (float(o[1]) + r) * f:
					return false
	return true


func _put(placed: Dictionary, p: Vector2, r: float) -> void:
	var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	if not placed.has(key):
		placed[key] = []
	(placed[key] as Array).append([p, r])


func _build_cell(corner: Vector2) -> void:
	var grass: Array = []
	# --- seagrass: where sand.gdshader paints it (keep the two in step)
	for i in int(CELL * CELL * GRASS_PER_M2):
		var p := corner + Vector2(_rng.randf(), _rng.randf()) * CELL
		var y: float = _ls.ground(p.x, p.y)
		var band := smoothstep(-1.9, -2.7, y) * smoothstep(-7.0, -5.2, y)
		if band < 0.05:
			continue
		var m := smoothstep(0.5, 0.58, _n(p * 0.027 + Vector2(0.21, 0.21)) + (_n(p * 0.29) - 0.5) * 0.3) * band
		if m < 0.25 + _rng.randf() * 0.5 or _mask_at(p).g > 0.3:
			continue
		var sc := _rng.randf_range(0.75, 1.35) * lerpf(0.7, 1.0, m)
		grass.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * _rng.randf_range(0.8, 1.25), sc)), Vector3(p.x, y - 0.02, p.y)))
	# --- corals: on hard ground (land mask g under water, not the headland's granite). A patch
	# of reef a few meters across belongs mostly to one kind in one color (a thicket)
	var cands: Array = []
	for i in int(CELL * CELL * CORAL_PER_M2):
		var p := corner + Vector2(_rng.randf(), _rng.randf()) * CELL
		var y: float = _ls.ground(p.x, p.y)
		if y > -0.6 or y < -18.0:
			continue
		var mk := _mask_at(p)
		if mk.g < 0.5 or mk.b > 0.3:
			continue
		var depth := -y
		# (thinner on the wave-beaten crest and far down the slope)
		if _rng.randf() > lerpf(0.4, 1.0, smoothstep(0.8, 2.2, depth)) * lerpf(1.0, 0.55, smoothstep(10.0, 16.0, depth)):
			continue
		var kind := -1
		var ci := 0
		if _rng.randf() < 0.62:
			_prng.seed = hash(Vector2i(floori((p.x + sin(p.y * 0.4) * 1.3) / 3.6), floori((p.y + sin(p.x * 0.37) * 1.3) / 3.6)))
			kind = _pick(depth, _prng.randf())
			ci = _prng.randi() % 1000
		else:
			kind = _pick(depth, _rng.randf())
			ci = _rng.randi() % 1000
		if kind < 0:
			continue
		var kd: Dictionary = _kinds[kind]
		var sc := _rng.randf_range(kd["s0"], kd["s1"])
		if _rng.randf() < float(kd["big"]):
			sc *= _rng.randf_range(1.5, kd["bigx"])
		# (nothing grows to within 0.35 m of the surface)
		sc = minf(minf(sc, 3.4), (depth - 0.35) / float(kd["top"]))
		if sc < float(kd["s0"]) * 0.5:
			continue
		var cols: Array = kd["cols"]
		var col: Color = cols[ci % cols.size()]
		cands.append([sc * float(kd["rad"]), p, y, kind, sc, col.lerp(Color(0.5, 0.45, 0.35), 0.08 + _rng.randf() * 0.34)])
	# the big ones first; the others where there is room left
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var placed := {}
	var near: Array = []
	var far: Array = []
	for k in _kinds.size():
		near.append([[], []])
	for k in _far_meshes.size():
		far.append([[], []])
	var feet: Array = []        # big rounded corals: urchins shelter at their foot
	var coral_area := 0.0
	for c: Array in cands:
		var p: Vector2 = c[1]
		var r: float = c[0]
		if not _room(placed, p, r, 0.64):
			continue
		_put(placed, p, r)
		coral_area += PI * r * r
		var kind: int = c[3]
		var kd: Dictionary = _kinds[kind]
		var sc: float = c[4]
		var b := Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(_normal(p), 0.5).normalized())) * Basis(Vector3.UP, _rng.randf() * TAU)
		var at := Vector3(p.x, float(c[2]) - 0.03 * sc, p.y)
		near[kind][0].append(Transform3D(b.scaled(Vector3.ONE * sc), at))
		near[kind][1].append(c[5])
		var fi: int = kd["far"]
		if fi >= 0:
			far[fi][0].append(Transform3D(b.scaled(Vector3.ONE * sc * float(kd["fs"])), at))
			far[fi][1].append(c[5])
		if kd.get("foot", false) and r > 0.3:
			feet.append([p, r])
		if r > 0.28 and float(c[2]) < -2.0 and float(c[2]) > -9.0 and forage_spots.size() < 6000:
			forage_spots.append([p, r, float(kd["top"]) * sc])
		if float(kd["reach"]) * sc > r + 0.12:
			overhangs.append([p, float(kd["reach"]) * sc])
		if r > 0.5 and float(c[2]) < -1.6 and float(c[2]) > -7.0:
			big_corals.append([p, r, float(kd["top"]) * sc, float(c[2])])
		# (for a diver: how high whatever stands here reaches)
		if float(kd["top"]) * sc > 0.2:
			add_top(p, maxf(r, float(kd["reach"]) * sc), float(c[2]) + float(kd["top"]) * sc)
	if coral_area > 0.0:
		_cover[Vector2i(floori(corner.x / CELL), floori(corner.y / CELL))] = minf(coral_area / (CELL * CELL), 1.0)
	# --- sea urchins: clusters on hard ground (reef, or the headland's granite), each animal
	# in the lowest spot it finds; some at the foot of a big coral
	var seeds: Array = []
	for i in int(CELL * CELL * URCHIN_SEEDS_PER_M2):
		var p := corner + Vector2(_rng.randf(), _rng.randf()) * CELL
		var y: float = _ls.ground(p.x, p.y)
		if y > -0.5 or y < -9.0:
			continue
		var mk := _mask_at(p)
		if (mk.g < 0.3 and mk.b < 0.3) or _rng.randf() > 0.6:
			continue
		seeds.append(p)
	for f: Array in feet:
		if _rng.randf() < 0.3:
			seeds.append((f[0] as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * (float(f[1]) + 0.1))
	var urch: Array = []
	for s: Vector2 in seeds:
		var n: int = [1, 2, 3, 3, 4, 4, 5, 6, 7, 9][_rng.randi() % 10]
		var got := _urchin_cluster(s, n, placed, urch)
		if got > 0:
			urchin_spots.append(Vector3(s.x, _ls.ground(s.x, s.y), s.y))
	# --- sea stars and giant clams (their own random numbers, the same for a cell every time)
	_xr.seed = hash(Vector2i(int(corner.x), int(corner.y))) + 991
	var star_xf: Array = []
	var star_col: Array = []
	for k in _stars.size():
		star_xf.append([])
		star_col.append([])
		var kind: Array = _stars[k]
		for i in int(ceilf(CELL * CELL * float(kind[3]))):
			var p := corner + Vector2(_xr.randf(), _xr.randf()) * CELL
			var y: float = _ls.ground(p.x, p.y)
			var mk := _mask_at(p)
			var on_reef := mk.g >= 0.5 or mk.b > 0.3
			if kind[2] == "reef":
				if not on_reef or y > -0.5 or y < -10.0:
					continue
			else:
				# (out of the swash; most of them where the seagrass grows)
				if mk.g > 0.2 or mk.b > 0.2 or y > -0.7 or y < -5.5:
					continue
				if meadow(p) < 0.3 and _xr.randf() > 0.4:
					continue
			if not _room(placed, p, float(kind[4]), 0.8):
				continue
			_put(placed, p, float(kind[4]))
			var sc := _xr.randf_range(0.8, 1.25)
			var b := Basis(Quaternion(Vector3.UP, _normal(p))) * Basis(Vector3.UP, _xr.randf() * TAU)
			star_xf[k].append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(p.x, y + 0.002, p.y)))
			var cols: Array = kind[1]
			star_col[k].append(cols[_xr.randi() % cols.size()])
			if star_spots.size() < 100:
				star_spots.append(Vector3(p.x, y, p.y))
	var clam_xf: Array = []
	var shell_col: Array = []
	var mantle_col: Array = []
	for i in int(ceilf(CELL * CELL * 0.22)):
		var p := corner + Vector2(_xr.randf(), _xr.randf()) * CELL
		var y: float = _ls.ground(p.x, p.y)
		var mk := _mask_at(p)
		if mk.g < 0.5 or mk.b > 0.3 or y > -0.8 or y < -9.0:
			continue
		var sc := _xr.randf_range(0.6, 1.5) * (0.7 if y > -1.3 else 1.0)
		if not _room(placed, p, 0.13 * sc, 0.75):
			continue
		_put(placed, p, 0.13 * sc)
		var b := Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(_normal(p), 0.6).normalized())) * Basis(Vector3.UP, _xr.randf() * TAU)
		# (set into the reef: only the upper half stands out)
		clam_xf.append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(p.x, y - 0.05 * sc, p.y)))
		shell_col.append(Color(0.74, 0.7, 0.6).lerp(Color(0.5, 0.52, 0.42), _xr.randf() * 0.6))
		mantle_col.append([Color(0.08, 0.3, 0.85), Color(0.06, 0.55, 0.6), Color(0.12, 0.55, 0.25), Color(0.55, 0.4, 0.14), Color(0.42, 0.2, 0.62), Color(0.1, 0.4, 0.75)][_xr.randi() % 6])
		if clam_spots.size() < 100:
			clam_spots.append(Vector3(p.x, y, p.y))
	# --- sea anemones: carpet anemones anywhere on the reef where there is room, magnificent
	# anemones on the high points of it (every try draws the same random numbers, whatever
	# comes of it)
	var anem_xf: Array = [[], []]
	var anem_col: Array = [[], []]
	for i in 40:
		var p := corner + Vector2(_xr.randf(), _xr.randf()) * CELL
		var roll := _xr.randf()
		var sc := _xr.randf()
		var yaw := _xr.randf() * TAU
		var ci := _xr.randi()
		var y: float = _ls.ground(p.x, p.y)
		var mk := _mask_at(p)
		if roll > 0.2 or mk.g < 0.5 or mk.b > 0.3 or y > -1.25 or y < -5.5:
			continue
		# (a high point: nothing higher within a meter and a half)
		var high := true
		for k in 6:
			var q := p + Vector2.from_angle(TAU * k / 6.0) * 1.5
			if _ls.ground(q.x, q.y) > y + 0.12:
				high = false
		var kind := 1 if high and roll < 0.17 else 0
		var rad := lerpf(0.3, 0.46, sc) if kind == 0 else lerpf(0.2, 0.29, sc)
		if not _room(placed, p, rad * (0.9 if kind == 0 else 0.85), 0.8):
			continue
		_put(placed, p, rad)
		var up := Vector3.UP.lerp(_normal(p), 0.85 if kind == 0 else 0.4).normalized()
		var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
		var at := Vector3(p.x, y - (0.0 if kind == 0 else 0.01), p.y)
		anem_xf[kind].append(Transform3D(b.scaled(Vector3.ONE * rad), at))
		anem_col[kind].append([Color(0.4, 0.4, 0.33), Color(0.34, 0.42, 0.32), Color(0.45, 0.4, 0.35), Color(0.31, 0.4, 0.34)][ci % 4] if kind == 0
			else [Color(0.56, 0.5, 0.38), Color(0.46, 0.5, 0.36), Color(0.62, 0.57, 0.48), Color(0.52, 0.45, 0.33)][ci % 4])
		anemone_spots.append([at + up * (rad * (0.08 if kind == 0 else 0.78)), rad, kind])
	# --- gaps in the reef with room for a lump of old reef rock: the dens of the morays and the
	# octopuses, which reef_life.gd chooses among them
	for i in 24:
		var p := corner + Vector2(_xr.randf(), _xr.randf()) * CELL
		var y: float = _ls.ground(p.x, p.y)
		var mk := _mask_at(p)
		if mk.g < 0.5 or mk.b > 0.3 or y > -1.5 or y < -4.8:
			continue
		if not _room(placed, p, 0.36, 0.72):
			continue
		den_spots.append(Vector3(p.x, y, p.y))
	# --- and bare, level sand away from the seagrass: where a colony of garden eels may live
	# --- and open sand at the foot of the reef, a step or two from it: where an octopus has
	# its den (its arms lie around its rock: it needs the floor there to itself)
	for i in 8:
		var p := corner + Vector2(_xr.randf(), _xr.randf()) * CELL
		var y: float = _ls.ground(p.x, p.y)
		var mk := _mask_at(p)
		if mk.g > 0.25 or mk.b > 0.25 or y > -1.5 or y < -5.0 or meadow(p) > 0.08:
			continue
		var reef_near := false
		var reef_close := false
		for k in 8:
			var dir := Vector2.from_angle(TAU * k / 8.0)
			if reef(p + dir * 2.0):
				reef_near = true
			var mc := _mask_at(p + dir * 1.0)
			if mc.g > 0.35 or mc.b > 0.35 or meadow(p + dir * 0.8) > 0.2:
				reef_close = true
		if reef_near and not reef_close:
			edge_spots.append(Vector3(p.x, y, p.y))
	for quarter in 4:
		var mid := corner + Vector2(0.25 + 0.5 * (quarter % 2), 0.25 + 0.5 * (quarter / 2)) * CELL
		var my: float = _ls.ground(mid.x, mid.y)
		if my > -3.3 or my < -6.3:
			continue
		var bare := true
		for k in 13:
			var q := mid if k == 0 else mid + Vector2.from_angle(TAU * k / 6.0) * (1.8 if k < 7 else 3.4)
			var mk := _mask_at(q)
			if mk.g > 0.25 or mk.b > 0.25 or meadow(q) > 0.08 or absf(float(_ls.ground(q.x, q.y)) - my) > 0.6:
				bare = false
				break
		if bare:
			sand_spots.append(Vector3(mid.x, my, mid.y))
	var center := Vector3(corner.x + CELL * 0.5, 0, corner.y + CELL * 0.5)
	center.y = _ls.ground(center.x, center.z)
	for k in 2:
		if not (anem_xf[k] as Array).is_empty():
			_add(_anem_meshes[k], _anem_mats[k], anem_xf[k], anem_col[k], center, 0.0, 45.0)
	for key: Vector2i in placed:
		if _occupied.has(key):
			(_occupied[key] as Array).append_array(placed[key])
		else:
			_occupied[key] = placed[key]
	for k in _stars.size():
		if not (star_xf[k] as Array).is_empty():
			_add(_stars[k][0], _coral_mat, star_xf[k], star_col[k], center, 0.0, 40.0)
			stars += (star_xf[k] as Array).size()
	if not clam_xf.is_empty():
		_add(_clam_shell, _coral_mat, clam_xf, shell_col, center, 0.0, 45.0)
		_add(_clam_mantle, _coral_mat, clam_xf, mantle_col, center, 0.0, 45.0)
		clams += clam_xf.size()
	if not grass.is_empty():
		_add(_grass_mesh, _grass_mat, grass, [], center, 0.0, 30.0)
		grass_tufts += grass.size()
	for k in near.size():
		if not (near[k][0] as Array).is_empty():
			_add(_kinds[k]["mesh"], _coral_mat, near[k][0], near[k][1], center, 0.0, NEAR if int(_kinds[k]["far"]) >= 0 else 40.0)
			corals += (near[k][0] as Array).size()
	for k in far.size():
		if not (far[k][0] as Array).is_empty():
			_add(_far_meshes[k], _coral_mat, far[k][0], far[k][1], center, NEAR, FAR)
	urch = _keep_wet(urch)
	if not urch.is_empty():
		_add(_urchin_mesh, _urchin_mat, urch, [], center, 0.0, 45.0)
		urchins += urch.size()


# ------------------------------------------------------------------ the coral garden
## How far inside the garden's outline p lies: 0 outside, 1 well inside (the outline wavers).
func garden(p: Vector2) -> float:
	if p.x < 50.0 or p.x > 106.0 or p.y < -76.0 or p.y > 34.0:
		return 0.0
	var d := 1e9
	for i in GARDEN.size() - 1:
		d = minf(d, Geometry2D.get_closest_point_to_segment(p, GARDEN[i], GARDEN[i + 1]).distance_to(p))
	var half := GARDEN_HALF + 2.0 * sin(p.y * 0.31 + 1.3) + 1.3 * sin(p.x * 0.47 + p.y * 0.19)
	return 1.0 - smoothstep(half - 2.5, half, d)


## The same, where a coral of the garden may stand: under water to nine meters or so, not in
## the seagrass (the meadow behind the crest stays), not on granite.
func _garden_ground(p: Vector2) -> float:
	var s := garden(p)
	if s <= 0.0:
		return 0.0
	var depth: float = -_ls.ground(p.x, p.y)
	if depth < 0.6 or depth > 9.5 or _mask_at(p).b > 0.3:
		return 0.0
	return s * (1.0 - smoothstep(7.5, 9.5, depth)) * (1.0 - smoothstep(0.08, 0.22, meadow(p)))


## The garden's floor is reef rock all over, not rock with sand between: the ground's shader
## gets a copy of the land mask with the rock painted in (the mask the placements go by is
## not touched: they stay as they are).
func _paint_garden_floor() -> void:
	if _garden_painted or _mask == null:
		return
	_garden_painted = true
	var sand: ShaderMaterial = _world.get_material("Sand") if _world.has_method("get_material") else null
	if sand == null:
		return
	var img := _mask.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var i0 := int((50.0 + HM_EXT) / (2.0 * HM_EXT) * w)
	var i1 := int((106.0 + HM_EXT) / (2.0 * HM_EXT) * w)
	var j0 := int((-76.0 + HM_EXT) / (2.0 * HM_EXT) * h)
	var j1 := int((34.0 + HM_EXT) / (2.0 * HM_EXT) * h)
	for j in range(j0, j1):
		for i in range(i0, i1):
			var p := Vector2((i + 0.5) / w * 2.0 * HM_EXT - HM_EXT, (j + 0.5) / h * 2.0 * HM_EXT - HM_EXT)
			var g := smoothstep(0.15, 0.6, _garden_ground(p))
			if g > 0.0:
				var c := img.get_pixel(i, j)
				if g > c.g:
					c.g = g
					img.set_pixel(i, j, c)
	sand.set_shader_parameter("landmask", ImageTexture.create_from_image(img))


## The garden may grow now. `keep`: [Vector2, radius] of what its corals are to keep off (the
## dens, the lionfish's stations, the eels' sand, the big fishes' homes: reef_life.gd).
func grow_garden(keep: Array) -> void:
	if _garden_started:
		return
	_garden_started = true
	# (the reef's animals have their places: the urchins kept back may be set down, before
	# the garden's corals, which then keep off them)
	_move_dry_urchins()
	for k: Array in keep:
		if float(k[1]) > 1.0:
			_garden_keep_wide.append(k)
		else:
			_put(_garden_keep, k[0], k[1])
	# (anemones: the fish that live in them dance a hand's width over and around them)
	for a: Array in anemone_spots:
		_put(_garden_keep, Vector2((a[0] as Vector3).x, (a[0] as Vector3).z), float(a[1]) + 0.3)
	var x := 48.0
	while x < 106.0:
		var z := -80.0
		while z < 34.0:
			var inside := false
			for o: Vector2 in [Vector2(0.5, 0.5), Vector2(0.05, 0.05), Vector2(0.95, 0.05), Vector2(0.05, 0.95), Vector2(0.95, 0.95), Vector2(0.5, 0.05), Vector2(0.5, 0.95), Vector2(0.05, 0.5), Vector2(0.95, 0.5)]:
				if garden(Vector2(x, z) + o * CELL) > 0.0:
					inside = true
			if inside:
				_garden_queue.append(Vector2(x, z))
			z += CELL
		x += CELL
	set_process(true)


func garden_done() -> bool:
	return _garden_started and _garden_queue.is_empty()


## Room for a coral of the garden at p? Among what stands there it may crowd another coral
## (their edges interlock, as in a thicket) but not sit on a small animal (an urchin, a clam,
## a sea star); and it keeps off the `keep` circles altogether.
func _garden_room(p: Vector2, r: float) -> bool:
	var bx := floori(p.x / BUCKET)
	var by := floori(p.y / BUCKET)
	for ix in range(bx - 1, bx + 2):
		for iy in range(by - 1, by + 2):
			for o: Array in _occupied.get(Vector2i(ix, iy), []):
				var f := 0.6 if float(o[1]) > 0.2 else 0.95
				if (o[0] as Vector2).distance_to(p) < (float(o[1]) + r) * f:
					return false
			for o: Array in _garden_keep.get(Vector2i(ix, iy), []):
				if (o[0] as Vector2).distance_to(p) < float(o[1]) + r:
					return false
	for o: Array in _garden_keep_wide:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + r:
			return false
	return true


## One 8 m cell of the garden: more corals where there is room, on rock and on the sand
## between, the kinds and colors of the patches that are there already (a thicket grows
## denser, it does not change its kind), and small ones in the gaps. Every candidate draws
## the same random numbers whatever comes of it.
func _build_garden_cell(corner: Vector2) -> void:
	_gr.seed = hash(Vector2i(int(corner.x), int(corner.y))) + 4177
	var cands: Array = []
	for i in int(CELL * CELL * GARDEN_PER_M2):
		var p := corner + Vector2(_gr.randf(), _gr.randf()) * CELL
		var roll := _gr.randf()
		var thin := _gr.randf()
		var own := _gr.randf()
		var pick := _gr.randf()
		var ci := _gr.randi() % 1000
		var size := _gr.randf()
		var big := _gr.randf()
		var bigx := _gr.randf()
		var small := _gr.randf()
		var smallx := _gr.randf()
		var tint := _gr.randf()
		var yaw := _gr.randf() * TAU
		if roll > _garden_ground(p):
			continue
		var y: float = _ls.ground(p.x, p.y)
		var depth := -y
		# (the top of the crest, where the swell breaks, stays a little thinner)
		if thin > lerpf(0.55, 1.0, smoothstep(0.8, 2.0, depth)):
			continue
		var kind := -1
		if own < 0.7:
			_prng.seed = hash(Vector2i(floori((p.x + sin(p.y * 0.4) * 1.3) / 3.6), floori((p.y + sin(p.x * 0.37) * 1.3) / 3.6)))
			kind = _pick(depth, _prng.randf())
			ci = _prng.randi() % 1000
		else:
			kind = _pick(depth, pick)
		if kind < 0:
			continue
		var kd: Dictionary = _kinds[kind]
		var sc := lerpf(kd["s0"], kd["s1"], size)
		if big < float(kd["big"]) * 0.7:
			sc *= lerpf(1.5, kd["bigx"], bigx)
		elif small < 0.35:
			sc *= lerpf(0.5, 0.8, smallx)        # (young colonies in the gaps)
		sc = minf(minf(sc, 3.4), (depth - 0.35) / float(kd["top"]))
		if sc < float(kd["s0"]) * 0.4:
			continue
		var cols: Array = kd["cols"]
		var col: Color = cols[ci % cols.size()]
		cands.append([sc * float(kd["rad"]), p, y, kind, sc, col.lerp(Color(0.5, 0.45, 0.35), 0.08 + tint * 0.34), yaw])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var near: Array = []
	var far: Array = []
	for k in _kinds.size():
		near.append([[], []])
	for k in _far_meshes.size():
		far.append([[], []])
	var area := 0.0
	var count := 0
	for c: Array in cands:
		var p: Vector2 = c[1]
		var r: float = c[0]
		if not _garden_room(p, r):
			continue
		_put(_occupied, p, r)
		area += PI * r * r
		count += 1
		var kind: int = c[3]
		var kd: Dictionary = _kinds[kind]
		var sc: float = c[4]
		var b := Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(_normal(p), 0.5).normalized())) * Basis(Vector3.UP, float(c[6]))
		var at := Vector3(p.x, float(c[2]) - 0.03 * sc, p.y)
		near[kind][0].append(Transform3D(b.scaled(Vector3.ONE * sc), at))
		near[kind][1].append(c[5])
		var fi: int = kd["far"]
		if fi >= 0:
			far[fi][0].append(Transform3D(b.scaled(Vector3.ONE * sc * float(kd["fs"])), at))
			far[fi][1].append(c[5])
		if float(kd["reach"]) * sc > r + 0.12:
			overhangs.append([p, float(kd["reach"]) * sc])
		if float(kd["top"]) * sc > 0.2:
			add_top(p, maxf(r, float(kd["reach"]) * sc), float(c[2]) + float(kd["top"]) * sc)
	if count == 0:
		return
	var cell := Vector2i(floori(corner.x / CELL), floori(corner.y / CELL))
	_cover[cell] = minf(float(_cover.get(cell, 0.0)) + area / (CELL * CELL), 1.0)
	var center := Vector3(corner.x + CELL * 0.5, 0, corner.y + CELL * 0.5)
	center.y = _ls.ground(center.x, center.z)
	for k in near.size():
		if not (near[k][0] as Array).is_empty():
			_add(_kinds[k]["mesh"], _coral_mat, near[k][0], near[k][1], center, 0.0, NEAR if int(_kinds[k]["far"]) >= 0 else 40.0)
	for k in far.size():
		if not (far[k][0] as Array).is_empty():
			_add(_far_meshes[k], _coral_mat, far[k][0], far[k][1], center, NEAR, FAR)
	corals += count
	garden_corals += count


## How much of the floor around p lies under coral (0 .. 1): the cells within `radius`, the
## near ones counting most. (The reef's sound goes by this.)
func coral_cover(p: Vector2, radius: float) -> float:
	var c0 := Vector2i(floori((p.x - radius) / CELL), floori((p.y - radius) / CELL))
	var c1 := Vector2i(floori((p.x + radius) / CELL), floori((p.y + radius) / CELL))
	var sum := 0.0
	var weights := 0.0
	for ix in range(c0.x, c1.x + 1):
		for iy in range(c0.y, c1.y + 1):
			var d := Vector2((ix + 0.5) * CELL, (iy + 0.5) * CELL).distance_to(p)
			var wgt := 1.0 - smoothstep(radius * 0.5, radius + CELL * 0.5, d)
			if wgt <= 0.0:
				continue
			weights += wgt
			sum += wgt * float(_cover.get(Vector2i(ix, iy), 0.0))
	return sum / weights if weights > 0.0 else 0.0


## For the tests.
func garden_report() -> Dictionary:
	var floor_m2 := 0.0
	var rock_before := 0.0
	var x := 50.0
	while x < 106.0:
		var z := -76.0
		while z < 34.0:
			if _garden_ground(Vector2(x, z)) > 0.5:
				floor_m2 += 0.25
				if reef(Vector2(x, z)):
					rock_before += 0.25
			z += 0.5
		x += 0.5
	return {"grown": garden_done(), "its corals": garden_corals, "all corals": corals, "floor (m2)": floor_m2, "of it hard reef before (m2)": rock_before,
		"cover at its middle (16 m)": snappedf(coral_cover(Vector2(75.5, -28.0), 16.0), 0.01), "cover on the reef edge further north (16 m)": snappedf(coral_cover(Vector2(84.0, 100.0), 16.0), 0.01),
		"cover in the lagoon (16 m)": snappedf(coral_cover(Vector2(50.0, -10.0), 16.0), 0.01), "cover off the beach (16 m)": snappedf(coral_cover(Vector2(20.0, 0.0), 16.0), 0.01)}


## Of these urchins, those that stay under water where they are; the others are kept back
## for _move_dry_urchins().
func _keep_wet(xfs: Array) -> Array:
	var wet: Array = []
	for xf: Transform3D in xfs:
		if xf.origin.y > URCHIN_DRY:
			_dry_urchins.append(xf)
		else:
			wet.append(xf)
			urchin_highest = maxf(urchin_highest, xf.origin.y)
	return wet


## The urchins that were kept back, each set down the slope from where it was: the way the
## ground falls, to ground 1.12-1.45 m under the old sea level (0.3 m and more of water over
## it at the lowest tide; above the dens and the eels' sand, which begin at 1.5 m). The ones
## of a cluster go the same way and end up together. Where the ground does not fall that far
## within 20 m (a hollow in the shore's rock) the urchin is left out. May be called again.
func _move_dry_urchins() -> void:
	if _dry_urchins.is_empty():
		return
	_ur.seed = 5150 + urchins_moved
	var per_cell := {}
	for xf: Transform3D in _dry_urchins:
		var at := Vector2(xf.origin.x, xf.origin.z)
		var want := _ur.randf_range(-1.45, -1.12)
		var found := false
		for step in 50:
			var y: float = _ls.ground(at.x, at.y)
			if y <= want:
				found = true
				break
			var e := 0.5
			var down := Vector2(float(_ls.ground(at.x - e, at.y)) - float(_ls.ground(at.x + e, at.y)), float(_ls.ground(at.x, at.y - e)) - float(_ls.ground(at.x, at.y + e)))
			if down.length() < 0.002:
				break
			at += down.normalized() * 0.4
		if not found:
			urchins_dropped += 1
			continue
		# a free place there (not on a coral, a clam, another urchin), and not deeper than meant
		var set_down := false
		for attempt in 10:
			var q := at + Vector2.from_angle(_ur.randf() * TAU) * (0.08 * attempt)
			var qy: float = _ls.ground(q.x, q.y)
			if qy > URCHIN_DRY or qy < -1.5 or not _room(_occupied, q, 0.07, 0.9) or not _room(_moved_put, q, 0.07, 0.9):
				continue
			_put(_moved_put, q, 0.07)
			_put(_occupied, q, 0.07)
			var sc := xf.basis.get_scale().x
			var b := Basis(Quaternion(Vector3.UP, _normal(q))) * Basis(Vector3.UP, _ur.randf() * TAU)
			var key := Vector2(floorf(q.x / CELL) * CELL, floorf(q.y / CELL) * CELL)
			if not per_cell.has(key):
				per_cell[key] = []
			(per_cell[key] as Array).append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(q.x, qy + 0.004, q.y)))
			urchin_highest = maxf(urchin_highest, qy)
			set_down = true
			break
		if set_down:
			urchins_moved += 1
		else:
			urchins_dropped += 1
	_dry_urchins.clear()
	for key: Vector2 in per_cell:
		var xfs: Array = per_cell[key]
		var center := Vector3(key.x + CELL * 0.5, 0, key.y + CELL * 0.5)
		center.y = _ls.ground(center.x, center.z)
		_add(_urchin_mesh, _urchin_mat, xfs, [], center, 0.0, 45.0)
		urchins += xfs.size()


## For the tests.
func urchin_report() -> Dictionary:
	return {"urchins": urchins, "moved down": urchins_moved, "left out": urchins_dropped, "still waiting": _dry_urchins.size(),
		"highest ground one sits on": snappedf(urchin_highest, 0.01)}


## Up to n urchins around s, each in the lowest of a few spots tried, none inside a coral or on
## top of another. Appends their transforms to `out`, returns how many found a place.
func _urchin_cluster(s: Vector2, n: int, placed: Dictionary, out: Array) -> int:
	var got := 0
	for k in n:
		for attempt in 3:
			var best := s
			var by := 1e9
			for t in 4:
				var q := s + Vector2.from_angle(_rng.randf() * TAU) * (sqrt(_rng.randf()) * (0.14 + 0.15 * sqrt(float(n))))
				var qy: float = _ls.ground(q.x, q.y)
				if qy < by:
					by = qy
					best = q
			if by > -0.45 or by < -10.0 or not _room(placed, best, 0.07, 0.85):
				continue
			_put(placed, best, 0.07)
			var sc := _rng.randf_range(0.7, 1.25)
			var b := Basis(Quaternion(Vector3.UP, _normal(best))) * Basis(Vector3.UP, _rng.randf() * TAU)
			out.append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(best.x, by + 0.004, best.y)))
			got += 1
			break
	return got


## Urchins at the foot of the shore rocks that stand in the water (boulders are separate
## meshes: a ray cast from above tells where the rock ends and the sea floor begins).
func _rock_urchins() -> void:
	var space := get_world_3d().direct_space_state
	var per_cell := {}
	for b: Array in _ls.boulder_spots:
		var c: Vector3 = b[0]
		var size: float = b[1]
		var gy: float = _ls.ground(c.x, c.z)
		if gy > -0.45 or gy < -5.0 or _rng.randf() > 0.75:
			continue
		var n := 2 + _rng.randi() % 5
		var a0 := _rng.randf() * TAU
		var got := 0
		for k in n:
			# (they keep together, on one side of the rock)
			var dir := Vector2.from_angle(a0 + _rng.randf_range(-0.6, 0.6))
			var r := size * 0.15
			var at := Vector2(1e9, 0)
			while r < size * 1.6 + 1.0:
				var q := Vector2(c.x, c.z) + dir * r
				var qy: float = _ls.ground(q.x, q.y)
				var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, qy + 6.0, q.y), Vector3(q.x, qy - 1.0, q.y))
				ray.collision_mask = 1
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or (hit["position"] as Vector3).y < qy + 0.05:
					at = q + dir * 0.07
					break
				r += 0.06
			if at.x > 1e8:
				continue
			var y: float = _ls.ground(at.x, at.y)
			if y > -0.45:
				continue
			var key := Vector2(floorf(at.x / CELL) * CELL, floorf(at.y / CELL) * CELL)
			if not per_cell.has(key):
				per_cell[key] = [[], {}]
			if not _room(per_cell[key][1], at, 0.07, 0.85):
				continue
			_put(per_cell[key][1], at, 0.07)
			var sc := _rng.randf_range(0.7, 1.25)
			var bs := Basis(Quaternion(Vector3.UP, _normal(at))) * Basis(Vector3.UP, _rng.randf() * TAU)
			(per_cell[key][0] as Array).append(Transform3D(bs.scaled(Vector3.ONE * sc), Vector3(at.x, y + 0.004, at.y)))
			got += 1
		if got > 0:
			urchin_spots.append(Vector3(c.x, gy, c.z))
	for key: Vector2 in per_cell:
		var xfs: Array = _keep_wet(per_cell[key][0])
		if xfs.is_empty():
			continue
		var center := Vector3(key.x + CELL * 0.5, 0, key.y + CELL * 0.5)
		center.y = _ls.ground(center.x, center.z)
		_add(_urchin_mesh, _urchin_mat, xfs, [], center, 0.0, 45.0)
		urchins += xfs.size()
	_rock_urchins_done = true
	# (if the garden has begun, everything else has its place: these may be set down now)
	if _garden_started:
		_move_dry_urchins()


func _add(mesh: Mesh, mat: Material, xfs: Array, cols: Array, center: Vector3, from: float, to: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	var inv := Transform3D(Basis(), -center)
	for i in xfs.size():
		mm.set_instance_transform(i, inv * (xfs[i] as Transform3D))
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (the range is measured to the node: it sits in the middle of its cell. No margins: with
	# them both levels of detail can be gone in the band where they hand over)
	mi.visibility_range_begin = from
	mi.visibility_range_end = to
	mi.position = center
	add_child(mi)


# ------------------------------------------------------------------ meshes
## A gray for a vertex; the alpha names the surface for the coral shader (see there).
func _g(v: float, pat := 1.0) -> Color:
	return Color(v, v, v, pat)


## One triangle of [position, normal, color] (and optionally the UV as a fourth entry). The
## materials are double-sided, and Godot turns the normal around on faces it sees from behind
## (front faces are clockwise): so the winding has to agree with the normals, or the face is
## lit as if from inside. This puts the corners in the order the normals ask for.
func _emit(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var front := ((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3))
	var tri := [a, b, c] if front.dot((a[1] as Vector3) + (b[1] as Vector3) + (c[1] as Vector3)) >= 0.0 else [a, c, b]
	for q: Array in tri:
		st.set_color(q[2])
		st.set_normal(q[1])
		st.set_uv(q[3] if q.size() > 3 else _uv)
		st.add_vertex(q[0])


func _limb(st: SurfaceTool, pts: Array, r0: float, r1: float, c0: Color, c1: Color, sides := 5) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var t := (b - a).normalized()
		var u := t.cross(Vector3(0.31, 0.2, 0.93)).normalized()
		var v := t.cross(u)
		var fa := float(i) / (pts.size() - 1)
		var fb := float(i + 1) / (pts.size() - 1)
		for k in sides:
			var a0 := TAU * k / float(sides)
			var a1 := TAU * (k + 1) / float(sides)
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var q := [[a + d0 * lerpf(r0, r1, fa), d0, c0.lerp(c1, fa)], [a + d1 * lerpf(r0, r1, fa), d1, c0.lerp(c1, fa)],
				[b + d1 * lerpf(r0, r1, fb), d1, c0.lerp(c1, fb)], [b + d0 * lerpf(r0, r1, fb), d0, c0.lerp(c1, fb)]]
			_emit(st, q[0], q[1], q[2])
			_emit(st, q[0], q[2], q[3])


## The rounded end of a limb of radius r that ends at c, pointing along `axis`.
func _cap(st: SurfaceTool, c: Vector3, axis: Vector3, r: float, col: Color, sides := 5) -> void:
	var u := axis.cross(Vector3(0.31, 0.2, 0.93)).normalized()
	var v := axis.cross(u)
	var tip := c + axis * r * 0.75
	for k in sides:
		var d0 := u * cos(TAU * k / float(sides)) + v * sin(TAU * k / float(sides))
		var d1 := u * cos(TAU * (k + 1) / float(sides)) + v * sin(TAU * (k + 1) / float(sides))
		_emit(st, [c + d0 * r, (d0 + axis * 0.4).normalized(), col], [c + d1 * r, (d1 + axis * 0.4).normalized(), col], [tip, axis, col])


## Triangles for a grid of [position, color] with smooth normals. `wrap`: the columns close into
## a ring. The normals point away from the point `inside`.
func _grid(st: SurfaceTool, g: Array, wrap: bool, inside: Vector3) -> void:
	var rows := g.size()
	var cols: int = (g[0] as Array).size()
	var v: Array = []
	for i in rows:
		var row: Array = []
		for j in cols:
			var jl := (j - 1 + cols) % cols if wrap else maxi(j - 1, 0)
			var jr := (j + 1) % cols if wrap else mini(j + 1, cols - 1)
			var p: Vector3 = g[i][j][0]
			var du: Vector3 = (g[i][jr][0] as Vector3) - (g[i][jl][0] as Vector3)
			var dv: Vector3 = (g[mini(i + 1, rows - 1)][j][0] as Vector3) - (g[maxi(i - 1, 0)][j][0] as Vector3)
			var n := du.cross(dv)
			n = n.normalized() if n.length() > 1e-10 else (p - inside).normalized()
			if n.dot(p - inside) < 0.0:
				n = -n
			row.append([p, n, g[i][j][1]])
		v.append(row)
	for i in rows - 1:
		for j in (cols if wrap else cols - 1):
			var j1 := (j + 1) % cols
			if (v[i][j][0] as Vector3).distance_squared_to(v[i][j1][0]) > 1e-12:
				_emit(st, v[i][j], v[i + 1][j1], v[i][j1])
			_emit(st, v[i][j], v[i + 1][j], v[i + 1][j1])


## A tuft of seagrass: strap-shaped blades from one point, each curving outward. UV.y is the
## height along the blade (the shader bends by it).
func _tuft_mesh() -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = 11
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bl in 11:
		var ang := g.randf() * TAU
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-out.z, 0, out.x)
		var length := g.randf_range(0.22, 0.5)
		var lean := g.randf_range(0.15, 0.6)
		var width := g.randf_range(0.011, 0.016)
		var root := out * g.randf_range(0.0, 0.12)
		var segs := 3
		var prev: Array = []
		for i in segs + 1:
			var f := float(i) / segs
			var c := root + Vector3.UP * (length * f * (1.0 - 0.25 * lean * f)) + out * (length * lean * f * f)
			var w := width * (1.0 - 0.45 * f * f)
			# dark at the base, lighter above, the old tips brown with growth
			var col := Color(0.035, 0.11, 0.03).lerp(Color(0.2, 0.36, 0.08), f)
			col = col.lerp(Color(0.3, 0.27, 0.12), smoothstep(0.75, 1.0, f) * 0.6)
			var cur := [[c - side * w, col, f], [c + side * w, col, f]]
			if not prev.is_empty():
				for tri in [[prev[0], prev[1], cur[1]], [prev[0], cur[1], cur[0]]]:
					for v in tri:
						st.set_color(v[1])
						st.set_uv(Vector2(0.5, v[2]))
						st.set_normal((out * 0.6 + Vector3.UP * 0.8).normalized())
						st.add_vertex(v[0])
			prev = cur
	return st.commit()


## A thicket of branching coral: stems that fork, the tips paler. `far`: the stand-in seen from
## a distance (fewer, thicker branches).
func _branching_mesh(seed_: int, far: bool) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	var base := _g(0.7)
	var mid_c := _g(0.82)
	var tip := _g(1.0)
	var k := 1.6 if far else 1.0
	var sides := 3 if far else 5
	# (the low crust they grow from)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var tri: Array = []
		for v in [Vector3(0, 0.07, 0), Vector3(cos(a1) * 0.2, -0.02, sin(a1) * 0.2), Vector3(cos(a0) * 0.2, -0.02, sin(a0) * 0.2)]:
			tri.append([v, (v + Vector3(0, 0.3, 0)).normalized(), _g(0.56)])
		_emit(st, tri[0], tri[1], tri[2])
	for s in (9 if far else 16):
		var ang := g.randf() * TAU
		var tilt := g.randf_range(0.05, 0.7)
		var dir := Vector3(cos(ang) * sin(tilt), cos(tilt), sin(ang) * sin(tilt))
		var root := Vector3(cos(ang), 0, sin(ang)) * g.randf_range(0.0, 0.14)
		var l1 := g.randf_range(0.09, 0.17)
		var mid := root + dir * l1
		_limb(st, [root, mid], 0.024 * k, 0.018 * k, base, base, sides)
		for f in (2 if far else 3):
			var d2 := (dir + Vector3(g.randf_range(-0.6, 0.6), g.randf_range(0.2, 0.7), g.randf_range(-0.6, 0.6))).normalized()
			var l2 := g.randf_range(0.07, 0.14)
			var end := mid + d2 * l2
			if far:
				_limb(st, [mid, end + d2 * 0.05], 0.017 * k, 0.007 * k, base, tip, sides)
				continue
			_limb(st, [mid, end], 0.017, 0.012, base, mid_c, sides)
			for t in 3:
				var d3 := (d2 + Vector3(g.randf_range(-0.7, 0.7), g.randf_range(0.1, 0.7), g.randf_range(-0.7, 0.7))).normalized()
				var e3 := end + d3 * g.randf_range(0.04, 0.09)
				_limb(st, [end, e3], 0.011, 0.006, mid_c, tip, 4)
				_cap(st, e3, d3, 0.006, tip, 4)
	return st.commit()


## A cauliflower coral: a tight dome of stubby branches, each ending in a cluster of knobs.
func _cauli_mesh(seed_: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	# (the core they grow from: it closes the gaps between them)
	var core: Array = []
	for i in 5:
		var row: Array = []
		for j in 10:
			var th := PI * 0.5 * i / 4.0
			var ph := TAU * j / 10.0
			row.append([Vector3(sin(th) * cos(ph) * 0.15, cos(th) * 0.13 - 0.02, sin(th) * sin(ph) * 0.15), _g(0.45)])
		core.append(row)
	_grid(st, core, true, Vector3(0, -0.05, 0))
	var n := 30
	for s in n:
		# spread evenly over the upper part of a sphere, a little jitter
		var th := acos(1.0 - (s + 0.5) / n * 0.78) + g.randf_range(-0.05, 0.05)
		var ph := s * 2.39996 + g.randf_range(-0.2, 0.2)
		var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var root := dir * 0.07
		var end := root + dir * g.randf_range(0.085, 0.12) * (1.0 - 0.18 * th)
		_limb(st, [root, end], 0.03, 0.035, _g(0.56), _g(0.8), 6)
		var side := dir.cross(Vector3(0.3, 0.9, 0.2)).normalized()
		var a0 := g.randf() * TAU
		for f in 3:
			var d2 := (dir * 0.8 + side.rotated(dir, a0 + f * TAU / 3.0 + g.randf_range(-0.4, 0.4)) * g.randf_range(0.6, 1.0)).normalized()
			var e2 := end + d2 * g.randf_range(0.03, 0.045)
			_limb(st, [end - dir * 0.012, e2], 0.026, 0.021, _g(0.8), _g(0.97), 6)
			_cap(st, e2, d2, 0.021, _g(1.0), 6)
	return st.commit()


## A finger coral: a stand of upright blunt fingers, a few of them forked.
func _finger_mesh(seed_: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	for s in 22:
		var ang := g.randf() * TAU
		var d := sqrt(g.randf())
		var out := Vector3(cos(ang), 0, sin(ang))
		var root := out * d * 0.19
		var lean := d * g.randf_range(0.1, 0.4)
		var dir := (Vector3.UP * cos(lean) + out * sin(lean)).normalized()
		var l := g.randf_range(0.14, 0.33) * (1.0 - 0.4 * d)
		var bend := Vector3(g.randf_range(-0.02, 0.02), 0, g.randf_range(-0.02, 0.02))
		var mid := root + dir * l * 0.5 + bend
		var end := root + dir * l + bend * 0.5
		_limb(st, [root - Vector3(0, 0.02, 0), mid, end], 0.026, 0.019, _g(0.6), _g(0.95), 5)
		_cap(st, end, (end - mid).normalized(), 0.019, _g(1.0))
		if g.randf() < 0.35:
			var d2 := (dir + out.rotated(Vector3.UP, g.randf_range(-1.5, 1.5)) * 0.8).normalized()
			var e2 := mid + d2 * l * g.randf_range(0.3, 0.5)
			_limb(st, [mid, e2], 0.02, 0.016, _g(0.75), _g(0.95), 5)
			_cap(st, e2, d2, 0.016, _g(1.0))
	return st.commit()


## A boulder coral: a lumpy dome. `brain`: rounder, and the shader draws its meanders.
func _massive_mesh(seed_: int, far: bool, brain: bool) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.frequency = 2.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	var rings := 5 if far else 16
	var segs := 10 if far else 30
	var pat := 0.8 if brain else 0.6
	var lump := 0.08 if brain else 0.22
	var grid: Array = []
	for i in rings + 1:
		var row: Array = []
		for j in segs:
			var th := PI * 0.58 * float(i) / rings
			var ph := TAU * float(j) / segs
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var bump := 1.0 + lump * noise.get_noise_3d(d.x, d.y, d.z) + lump * 0.36 * noise.get_noise_3d(d.x * 3.0, d.y * 3.0 + 4.0, d.z * 3.0)
			var p := (Vector3(d.x * 0.28, d.y * 0.27 - 0.03, d.z * 0.28) if brain else Vector3(d.x * 0.3, d.y * 0.26 - 0.03, d.z * 0.3)) * bump
			var shade := clampf(0.74 + 0.2 * noise.get_noise_3d(d.x * 6.0 + 9.0, d.y * 6.0, d.z * 6.0) + 0.16 * d.y, 0.0, 1.0)
			row.append([p, _g(shade, pat)])
		grid.append(row)
	_grid(st, grid, true, Vector3(0, -0.05, 0))
	return st.commit()


## A table coral: a plate with a wavy rim on a short stalk off its middle, dished a little,
## thick in the middle and thin at the growing edge.
func _table_mesh(seed_: int, far: bool) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	var segs := 12 if far else 26
	var rings := 2 if far else 5
	var top := Vector3(0.03, 0.2, 0.02)
	_limb(st, [Vector3(0, -0.03, 0), top], 0.07, 0.1, _g(0.55, 0.4), _g(0.6, 0.4), 5 if far else 8)
	var ph1 := g.randf() * TAU
	var ph2 := g.randf() * TAU
	var up: Array = []
	var down: Array = []
	for i in rings + 1:
		var f := float(i) / rings
		var ru: Array = []
		var rd: Array = []
		for j in segs:
			var a := TAU * j / float(segs)
			var r := 0.42 * f * (1.0 + 0.1 * sin(a * 3.0 + ph1) + 0.05 * sin(a * 7.0 + ph2))
			var p := top + Vector3(cos(a) * r, 0.05 * f * f + 0.012 * sin(a * 5.0 + ph2) * f, sin(a) * r)
			ru.append([p, _g(lerpf(0.78, 1.0, f * f), 0.4)])
			rd.append([p - Vector3(0, lerpf(0.05, 0.012, f), 0), _g(0.5, 0.4)])
		up.append(ru)
		down.append(rd)
	_grid(st, up, true, top - Vector3(0, 2.0, 0))
	_grid(st, down, true, top + Vector3(0, 2.0, 0))
	_grid(st, [down[rings], up[rings]], true, top)
	return st.commit()


## A sea fan: a flat lattice of thin branches across the current. It sways.
func _fan_mesh(seed_: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2(0, 1.2)
	_limb(st, [Vector3.ZERO, Vector3(0, 0.08, 0)], 0.012, 0.009, _g(0.7), _g(1.0), 4)
	for s in 7:
		var a := lerpf(-1.0, 1.0, s / 6.0) + g.randf_range(-0.08, 0.08)
		var d := Vector3(sin(a), cos(a), 0)
		var l := g.randf_range(0.3, 0.5) * (1.0 - 0.3 * absf(a))
		var root := Vector3(0, 0.07, 0)
		var end := root + d * l + Vector3(0, 0, g.randf_range(-0.03, 0.03))
		_limb(st, [root, root.lerp(end, 0.5) + Vector3(g.randf_range(-0.02, 0.02), 0, 0), end], 0.007, 0.003, _g(0.9), _g(0.9), 4)
		for t in 5:
			var f := 0.25 + 0.15 * t
			var p := root.lerp(end, f)
			for sd in [-1.0, 1.0]:
				var d2 := Vector3(sin(a + sd * 0.7), cos(a + sd * 0.7), 0)
				_limb(st, [p, p + d2 * g.randf_range(0.05, 0.11) * (1.1 - f)], 0.003, 0.0015, _g(0.9), _g(1.0), 3)
	return st.commit()


## A whorl of thin plates: steep ones in the middle, wide flat ones outside, each with a pale
## growing edge.
func _plate_mesh(seed_: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	var boss: Array = []
	for i in 4:
		var row: Array = []
		for j in 8:
			var th := PI * 0.5 * i / 3.0
			row.append([Vector3(sin(th) * cos(TAU * j / 8.0) * 0.09, cos(th) * 0.05 - 0.01, sin(th) * sin(TAU * j / 8.0) * 0.09), _g(0.42)])
		boss.append(row)
	_grid(st, boss, true, Vector3(0, -0.1, 0))
	for k in 7:
		var a0 := k * 2.4 + g.randf_range(-0.3, 0.3)
		var reach := 0.17 + 0.028 * k
		var rise := 0.25 - 0.024 * k
		var grid: Array = []
		for i in 5:
			var v := i / 4.0
			var row: Array = []
			for j in 8:
				var u := j / 7.0 * 2.0 - 1.0
				var ang := a0 + u * 1.15
				var r := 0.02 + 0.012 * k + v * reach * (1.0 - 0.22 * u * u)
				var y := 0.0 + pow(v, 1.5) * rise * (1.0 - 0.3 * u * u) + 0.014 * sin(u * 5.0 + k) * v
				row.append([Vector3(cos(ang) * r, y, sin(ang) * r), _g(1.0 if i == 4 else lerpf(0.5, 0.8, v))])
			grid.append(row)
		_grid(st, grid, false, Vector3(0, -1.0, 0))
	return st.commit()


## Fire coral: upright wavy blades standing across one another, the upper edge pale.
func _fire_mesh(seed_: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	for k in 6:
		var a := g.randf() * PI
		var mid := Vector3(g.randf_range(-0.08, 0.08), 0, g.randf_range(-0.08, 0.08))
		var half := g.randf_range(0.1, 0.17)
		var along := Vector3(cos(a), 0, sin(a))
		var perp := Vector3(-along.z, 0, along.x)
		var h := g.randf_range(0.18, 0.3)
		var p1 := g.randf() * TAU
		var p2 := g.randf() * TAU
		var grid: Array = []
		for i in 5:
			var v := i / 4.0
			var row: Array = []
			for j in 7:
				var u := j / 6.0 * 2.0 - 1.0
				var p := mid + along * (half * u * (1.0 - 0.15 * v)) + perp * (0.035 * sin(u * 3.0 + p1) * (0.4 + v)) \
					+ Vector3.UP * (h * v * (0.75 + 0.25 * sin(u * 4.0 + p2)) * (1.0 - 0.35 * u * u) - 0.02)
				row.append([p, _g(1.0 if i == 4 else lerpf(0.55, 0.8, v))])
			grid.append(row)
		_grid(st, grid, false, mid + perp * 5.0)
	return st.commit()


## A leather coral (a soft coral): a thick stalk and a cap with a folded rim. It sways a little.
func _leather_mesh(seed_: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2(0, 3.0)
	var top := Vector3(0.01, 0.12, 0.0)
	_limb(st, [Vector3(0, -0.03, 0), top], 0.075, 0.06, _g(0.6), _g(0.7), 8)
	var ph1 := g.randf() * TAU
	var ph2 := g.randf() * TAU
	var segs := 20
	var cap: Array = []
	var under: Array = [[], []]
	for i in 5:
		var f := i / 4.0
		var row: Array = []
		for j in segs:
			var a := TAU * j / float(segs)
			var r := 0.23 * f * (1.0 + 0.07 * sin(a * 3.0 + ph1))
			var p := top + Vector3(cos(a) * r, 0.01 + 0.065 * (1.0 - f * f) + 0.04 * f * f * sin(a * 6.0 + ph2), sin(a) * r)
			row.append([p, _g(lerpf(0.97, 0.8, f))])
			if i == 4:
				(under[0] as Array).append([p, _g(0.6)])
				(under[1] as Array).append([top + Vector3(cos(a) * 0.058, 0, sin(a) * 0.058), _g(0.5)])
		cap.append(row)
	_grid(st, cap, true, top - Vector3(0, 2.0, 0))
	_grid(st, under, true, top + Vector3(0, 0.5, 0))
	return st.commit()


## The black long-spined urchin: a small flattened test, some sixty needle-thin spines up to
## 30 cm long (the longest on top, short ones below that prop it up), the orange-ringed sac on
## top and the five pale spots around it that tell Diadema setosum from its relatives.
func _urchin() -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2(-1, 0)
	var black := Color(0.022, 0.022, 0.03)
	var c := Vector3(0, 0.026, 0)
	var rr := Vector3(0.04, 0.027, 0.04)
	var grid: Array = []
	for i in 7:
		var row: Array = []
		for j in 12:
			var th := PI * i / 6.0
			var ph := TAU * j / 12.0
			row.append([c + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * rr, black])
		grid.append(row)
	_grid(st, grid, true, c)
	# the sac on top, an orange ring around its opening
	var cs := c + Vector3(0, rr.y + 0.003, 0)
	grid = []
	for i in 5:
		var row: Array = []
		for j in 8:
			var th := PI * 0.7 * i / 4.0
			var ph := TAU * j / 8.0
			row.append([cs + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * 0.011, Color(0.9, 0.3, 0.02) if i == 1 else Color(0.03, 0.03, 0.05)])
		grid.append(row)
	_grid(st, grid, true, cs)
	# five pale spots
	for k in 5:
		var ph := TAU * k / 5.0
		var d := Vector3(sin(0.62) * cos(ph), cos(0.62), sin(0.62) * sin(ph))
		var pc := c + d * rr * 1.04
		var t1 := d.cross(Vector3.UP).normalized()
		var t2 := d.cross(t1)
		for s in 6:
			var pale := Color(0.8, 0.9, 1.0)
			_emit(st, [pc, d, pale], [pc + (t1 * cos(TAU * s / 6.0) + t2 * sin(TAU * s / 6.0)) * 0.0055, d, pale],
				[pc + (t1 * cos(TAU * (s + 1) / 6.0) + t2 * sin(TAU * (s + 1) / 6.0)) * 0.0055, d, pale])
	# the spines
	var n := 64
	for s in n:
		var th := acos(1.0 - (s + 0.5) / n * 1.42)
		var ph := s * 2.39996 + g.randf_range(-0.2, 0.2)
		var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		d = (d + Vector3(g.randf_range(-0.12, 0.12), g.randf_range(-0.12, 0.12), g.randf_range(-0.12, 0.12))).normalized()
		var root := c + d * rr * 0.9
		var l := lerpf(0.3, 0.1, pow(th / 2.01, 1.5)) * g.randf_range(0.65, 1.0)
		if d.y < -0.05:
			l = minf(l, 0.08)
		var a := root
		var b := root + d * l
		var u := d.cross(Vector3(0.31, 0.2, 0.93)).normalized()
		var v := d.cross(u)
		var phase := g.randf()
		for k in 3:
			var d0 := u * cos(TAU * k / 3.0) + v * sin(TAU * k / 3.0)
			var d1 := u * cos(TAU * (k + 1) / 3.0) + v * sin(TAU * (k + 1) / 3.0)
			var q := [[a + d0 * 0.0028, d0, black, Vector2(phase, 0.0)], [a + d1 * 0.0028, d1, black, Vector2(phase, 0.0)],
				[b + d1 * 0.0005, d1, black, Vector2(phase, 1.0)], [b + d0 * 0.0005, d0, black, Vector2(phase, 1.0)]]
			_emit(st, q[0], q[1], q[2])
			_emit(st, q[0], q[2], q[3])
	return st.commit()


## A sea star. 0: the blue sea star, five slender round arms with blunt ends. 1: the red-knobbed
## sea star, stout, with a high middle and rows of red knobs. 2: a cushion star, a five-sided
## pillow. They lie on the ground (y = 0); the instance color is the body's.
func _star_mesh(kind: int) -> ArrayMesh:
	var g := RandomNumberGenerator.new()
	g.seed = 40 + kind
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	if kind == 2:
		var rows: Array = []
		for i in 7:
			var f := i / 6.0
			var row: Array = []
			for j in 30:
				var a := TAU * j / 30.0
				var r := 0.105 * f * (1.0 + 0.09 * cos(a * 5.0))
				var y := 0.062 * pow(1.0 - pow(f, 2.6), 0.6) + 0.002
				row.append([Vector3(cos(a) * r, y, sin(a) * r), _g(0.7 + 0.3 * g.randf(), 0.6)])
			rows.append(row)
		_grid(st, rows, true, Vector3(0, -0.2, 0))
		return st.commit()
	var arm_len := 0.14 if kind == 0 else 0.115
	var r0 := 0.017 if kind == 0 else 0.036
	var r1 := 0.012 if kind == 0 else 0.013
	var knob := Color(1.0, 0.16, 0.1)
	# the middle
	var disc: Array = []
	var dr := 0.026 if kind == 0 else 0.06
	var dh := 0.018 if kind == 0 else 0.05
	for i in 5:
		var f := i / 4.0
		var row: Array = []
		for j in 15:
			var a := TAU * j / 15.0
			row.append([Vector3(cos(a) * dr * f, dh * (1.0 - f * f) + 0.004, sin(a) * dr * f), _g(0.95)])
		disc.append(row)
	_grid(st, disc, true, Vector3(0, -0.2, 0))
	for arm in 5:
		var a := TAU * arm / 5.0 + g.randf_range(-0.08, 0.08)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var bend := g.randf_range(-0.3, 0.3)
		var pts: Array = []
		for k in 5:
			var f := k / 4.0
			# (the arm lies on the ground, a little curved, its end slightly raised)
			var r := lerpf(r0, r1, f)
			pts.append(out * (0.01 + arm_len * f) + side * (bend * arm_len * f * f) + Vector3(0, r * 0.62 + (0.004 * f * f if kind == 0 else 0.0), 0))
		_limb(st, pts, r0, r1, _g(0.92), _g(1.0), 8)
		_cap(st, pts[4], ((pts[4] as Vector3) - (pts[3] as Vector3)).normalized(), r1, _g(0.85) if kind == 0 else Color(0.5, 0.12, 0.08), 8)
		if kind == 1:
			# knobs along the top of the arm, and a ring of big ones around the middle
			for k in 3:
				var f := 0.3 + 0.27 * k
				var p: Vector3 = (pts[0] as Vector3).lerp(pts[4], f)
				var r := lerpf(r0, r1, f)
				var base := p + Vector3(0, r * 0.75, 0)
				_limb(st, [base, base + Vector3(0, 0.012 - 0.003 * k, 0)], 0.008 - 0.0015 * k, 0.003, knob, knob, 6)
			var bp := out * 0.034 + Vector3(0, 0.036, 0)
			_limb(st, [bp, bp + Vector3(0, 0.024, 0) + out * 0.004], 0.011, 0.0035, knob, knob, 6)
	if kind == 1:
		_limb(st, [Vector3(0, 0.048, 0), Vector3(0, 0.07, 0)], 0.01, 0.003, knob, knob, 6)
	return st.commit()


## A giant clam: [the two fluted valves, standing a little open; the mantle between their lips].
## About 26 cm long; the hinge is at the bottom (it sits in the reef), the wavy lips are up.
func _clam_meshes() -> Array:
	var length := 0.26
	var height := 0.15
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv = Vector2.ZERO
	var lips: Array = [[], []]
	for side in 2:
		var sg := 1.0 if side == 0 else -1.0
		var rows: Array = []
		for i in 8:
			var v := i / 7.0
			var row: Array = []
			for j in 25:
				var u := j / 24.0 * 2.0 - 1.0
				# five folds run from the hinge to the lip; where they meet the lip it zigzags
				var fold := cos(u * PI * 4.5)
				var x := length * 0.5 * u * (0.62 + 0.38 * v)
				var y := height * pow(v, 0.8) * (1.0 - 0.3 * u * u) + 0.016 * fold * v * v
				var z := sg * (0.062 * sin(PI * pow(v, 0.62) * 0.92) * (1.0 - 0.45 * u * u) + 0.011 * fold * v + 0.012 * v)
				var p := Vector3(x, y, z)
				row.append([p, _g(lerpf(0.6, 0.95, v) * (0.85 + 0.15 * fold))])
				if i == 7:
					(lips[side] as Array).append(p)
			rows.append(row)
		_grid(st, rows, false, Vector3(0, 0.05, 0))
	var shell := st.commit()
	# the mantle: fills the gap between the lips and lies a little over them
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for i in 7:
		var w := i / 6.0 * 2.0 - 1.0
		var row: Array = []
		for j in 25:
			var a: Vector3 = lips[0][j]
			var b: Vector3 = lips[1][j]
			var p := a.lerp(b, w * 0.5 + 0.5)
			p.z *= 1.12
			p.y = lerpf(a.y, b.y, w * 0.5 + 0.5) + 0.004 + 0.012 * (1.0 - w * w) + 0.003 * sin(j * 1.9 + i * 1.3)
			row.append([p, _g(lerpf(1.0, 0.7, absf(w)), 0.2)])
		rows.append(row)
	_uv = Vector2.ZERO
	_grid(sm, rows, false, Vector3(0, -0.2, 0))
	return [shell, sm.commit()]
