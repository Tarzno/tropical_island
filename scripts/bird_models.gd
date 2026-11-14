extends RefCounted
## Birds built in code: the white-tailed tropicbird, the ruddy turnstone, the crab plover and
## the striated heron (scripts/shorebirds.gd moves them). Preloaded, no class_name.
##
## `make(kind)` returns the bird as a small tree of nodes and the handles to move it:
##   "root"   Node3D: on the ground under the bird when it stands, at its body when it flies
##   "tilt"   Node3D: the body's own attitude (pitch for pecking, the lean of a standing bird)
##   "stand"  the standing (for the tropicbird: sitting) body with its wings folded
##   "fly"    the flying body with its tail spread (and the tropicbird's streamers)
##   "wings"  [left, right]: bendable wings for Flight.pose() (shaders/wing.gdshader)
##   "legs"   [[upper, lower], [upper, lower]] left and right, or [] (the tropicbird's are tucked away)
##   "hip"    height of the hips above the ground when it stands
##   "streamers"  the tropicbird's two long tail feathers (a node to sway), or null
## Forward is -Z, up +Y. The body is a loft whose UVs the plumage shader (shaders/bird.gdshader)
## paints from: UV.x from the base of the bill back, UV.y around the body (0 on the back, 0.5 on
## the belly). Bill, eyes, legs, folded wings and tail are colored by vertex.

const FLY := [[0.0, 0.006, 0.006, 0.006], [0.03, 0.022, 0.024, 0.01], [0.08, 0.032, 0.034, 0.012], [0.13, 0.031, 0.033, 0.01],
	[0.18, 0.034, 0.037, 0.004], [0.24, 0.047, 0.05, 0.001], [0.3, 0.056, 0.058, 0.0], [0.45, 0.058, 0.055, -0.004],
	[0.6, 0.045, 0.04, -0.002], [0.72, 0.028, 0.022, 0.0], [0.82, 0.012, 0.01, 0.004]]
const STAND := [[0.0, 0.006, 0.006, 0.03], [0.03, 0.024, 0.026, 0.034], [0.08, 0.034, 0.036, 0.034], [0.13, 0.032, 0.034, 0.03],
	[0.18, 0.036, 0.04, 0.018], [0.3, 0.062, 0.065, 0.0], [0.46, 0.064, 0.062, -0.004],
	[0.62, 0.046, 0.04, 0.0], [0.76, 0.026, 0.02, 0.004], [0.9, 0.012, 0.008, 0.006]]
## (the heron, hunched: the neck is folded and the head sits on the shoulders)
const HUNCHED := [[0.0, 0.006, 0.006, 0.052], [0.03, 0.02, 0.022, 0.056], [0.08, 0.03, 0.032, 0.056], [0.13, 0.032, 0.036, 0.046],
	[0.19, 0.044, 0.052, 0.026], [0.3, 0.062, 0.068, 0.004], [0.46, 0.062, 0.062, -0.004],
	[0.62, 0.046, 0.04, 0.0], [0.76, 0.026, 0.02, 0.004], [0.9, 0.012, 0.008, 0.006]]

const SPECS := {
	"tropicbird": {
		"L": 0.4, "girth": 1.05, "stand": STAND, "upright": 0.12, "bill": [0.052, 0.011, Color(0.95, 0.62, 0.08), -0.008], "eye": 1.2,
		"plumage": {"upper": Color(0.97, 0.97, 0.96), "under": Color(0.97, 0.97, 0.96), "roughness": 0.7,
			"stripe": Color(0.02, 0.02, 0.02), "stripe_from": 0.015, "stripe_to": 0.2, "stripe_at": 0.45, "stripe_w": 0.24},
		"fold": [Color(0.95, 0.95, 0.94), Color(0.93, 0.93, 0.92), Color(0.05, 0.05, 0.05)],
		"tail": [0.13, [Color(0.96, 0.96, 0.95), Color(0.96, 0.96, 0.95), Color(0.96, 0.96, 0.95)]], "streamers": 0.46,
		"half": 0.46, "lead": [[0, 0.05], [0.2, 0.058], [0.42, 0.066], [0.7, 0.024], [1.0, -0.1]],
		"trail": [[0, -0.094], [0.25, -0.09], [0.42, -0.08], [0.7, -0.082], [0.9, -0.096], [1.0, -0.108]],
		"wing": {"color_in": Color(0.97, 0.97, 0.96), "color_out": Color(0.97, 0.97, 0.96), "color_tip": Color(0.06, 0.06, 0.06),
			"color_under": Color(0.97, 0.97, 0.96), "under": 1.0, "backlight": 0.55,
			"color_bar": Color(0.03, 0.03, 0.03), "bar_line": Vector4(0.06, 0.8, 0.44, 0.22), "bar_width": 0.1, "bar_upper": 1.0},
	},
	"turnstone": {
		"L": 0.2, "girth": 1.18, "stand": STAND, "upright": 0.22, "bill": [0.021, 0.0075, Color(0.06, 0.05, 0.05), 0.003], "eye": 1.0,
		"plumage": {"upper": Color(0.3, 0.24, 0.18), "under": Color(0.95, 0.95, 0.93), "under_edge": -0.15, "roughness": 0.8,
			"breast": Color(0.16, 0.13, 0.1), "breast_from": 0.12, "breast_to": 0.36, "mottle": 0.75, "mottle_color": Color(0.62, 0.52, 0.4)},
		"fold": [Color(0.32, 0.26, 0.2), Color(0.26, 0.21, 0.16), Color(0.1, 0.08, 0.07)],
		"tail": [0.055, [Color(0.95, 0.95, 0.93), Color(0.07, 0.06, 0.05), Color(0.9, 0.9, 0.88)]],
		"legs": [0.024, 0.032, Color(0.92, 0.42, 0.06)],
		"half": 0.25, "lead": [[0, 0.034], [0.42, 0.042], [0.7, 0.018], [1.0, -0.06]],
		"trail": [[0, -0.064], [0.42, -0.058], [0.7, -0.058], [0.9, -0.066], [1.0, -0.072]],
		"wing": {"color_in": Color(0.25, 0.2, 0.15), "color_out": Color(0.13, 0.11, 0.09), "color_tip": Color(0.06, 0.05, 0.05),
			"color_under": Color(0.9, 0.9, 0.88), "under": 0.85, "backlight": 0.3,
			"color_bar": Color(0.95, 0.95, 0.93), "bar_line": Vector4(0.12, 0.55, 0.85, 0.5), "bar_width": 0.085, "bar_upper": 0.0},
	},
	"crab_plover": {
		"L": 0.34, "girth": 1.05, "stand": STAND, "upright": 0.3, "bill": [0.055, 0.0125, Color(0.03, 0.03, 0.03), -0.004], "eye": 1.3,
		"plumage": {"upper": Color(0.03, 0.03, 0.03), "under": Color(0.97, 0.97, 0.96), "upper_from": 0.33, "under_edge": 0.45, "roughness": 0.7},
		"fold": [Color(0.96, 0.96, 0.95), Color(0.9, 0.9, 0.9), Color(0.04, 0.04, 0.04)],
		"tail": [0.08, [Color(0.9, 0.9, 0.9), Color(0.88, 0.88, 0.88), Color(0.85, 0.85, 0.85)]],
		"legs": [0.07, 0.095, Color(0.55, 0.6, 0.68)],
		"half": 0.37, "lead": [[0, 0.034], [0.42, 0.044], [0.7, 0.016], [1.0, -0.085]],
		"trail": [[0, -0.066], [0.42, -0.058], [0.7, -0.06], [0.9, -0.078], [1.0, -0.094]],
		"wing": {"color_in": Color(0.97, 0.97, 0.96), "color_out": Color(0.04, 0.04, 0.04), "color_tip": Color(0.03, 0.03, 0.03),
			"color_under": Color(0.93, 0.93, 0.92), "under": 0.55, "backlight": 0.4, "color_rear": Color(0.04, 0.04, 0.04), "rear_from": 0.55},
	},
	# the sooty tern: black above, white below, a white forehead (painted with the shader's
	# "cap"), a slender black bill, short black legs, long narrow wings, a forked tail
	"sooty_tern": {
		"L": 0.36, "girth": 0.98, "stand": STAND, "upright": 0.16, "bill": [0.043, 0.0075, Color(0.03, 0.03, 0.03), -0.003], "eye": 1.0,
		"plumage": {"upper": Color(0.035, 0.035, 0.04), "under": Color(0.97, 0.97, 0.96), "under_edge": 0.05, "roughness": 0.7,
			"cap": Color(0.97, 0.97, 0.96), "cap_from": 0.0, "cap_to": 0.045, "cap_soft": 0.012, "cap_side": 0.45},
		"fold": [Color(0.04, 0.04, 0.045), Color(0.035, 0.035, 0.04), Color(0.03, 0.03, 0.03)],
		"tail": [0.13, [Color(0.05, 0.05, 0.05), Color(0.04, 0.04, 0.04), Color(0.03, 0.03, 0.03)]],
		"legs": [0.02, 0.028, Color(0.04, 0.04, 0.04)],
		"half": 0.43, "lead": [[0, 0.046], [0.2, 0.054], [0.42, 0.06], [0.7, 0.02], [1.0, -0.11]],
		"trail": [[0, -0.086], [0.25, -0.08], [0.42, -0.07], [0.7, -0.076], [0.9, -0.1], [1.0, -0.118]],
		"wing": {"color_in": Color(0.04, 0.04, 0.045), "color_out": Color(0.035, 0.035, 0.04), "color_tip": Color(0.03, 0.03, 0.03),
			"color_under": Color(0.93, 0.93, 0.92), "under": 0.8, "backlight": 0.25, "color_rear": Color(0.2, 0.2, 0.21), "rear_from": 0.6},
	},
	# --- four birds of the land (scripts/land_birds.gd). The common mynah: brown, the whole
	# head and throat black, bill and legs yellow, a white patch in the wing and a white tip
	# to the tail. Brought to the islands by people, like the next; both are everywhere now.
	"mynah": {
		"L": 0.25, "girth": 1.08, "stand": STAND, "upright": 0.3, "bill": [0.026, 0.009, Color(0.95, 0.75, 0.1), -0.002], "eye": 1.0,
		"plumage": {"upper": Color(0.27, 0.18, 0.12), "under": Color(0.36, 0.25, 0.19), "under_edge": -0.45, "roughness": 0.75,
			"cap": Color(0.03, 0.03, 0.03), "cap_from": 0.0, "cap_to": 0.19, "cap_soft": 0.03, "cap_side": 1.0,
			"breast": Color(0.03, 0.03, 0.03), "breast_from": 0.0, "breast_to": 0.2},
		"fold": [Color(0.26, 0.17, 0.12), Color(0.2, 0.13, 0.09), Color(0.05, 0.04, 0.04)],
		"tail": [0.085, [Color(0.05, 0.04, 0.04), Color(0.05, 0.04, 0.04), Color(0.93, 0.93, 0.9)]],
		"legs": [0.03, 0.042, Color(0.92, 0.72, 0.1)],
		"half": 0.21, "lead": [[0, 0.0328], [0.42, 0.0406], [0.7, 0.0213], [1.0, -0.0386]],
		"trail": [[0, -0.0618], [0.42, -0.0580], [0.7, -0.0580], [0.9, -0.0618], [1.0, -0.0580]],
		"wing": {"color_in": Color(0.25, 0.17, 0.12), "color_out": Color(0.06, 0.05, 0.05), "color_tip": Color(0.05, 0.04, 0.04),
			"color_under": Color(0.5, 0.42, 0.38), "under": 0.7, "backlight": 0.25,
			"color_bar": Color(0.95, 0.95, 0.93), "bar_line": Vector4(0.45, 0.55, 0.8, 0.35), "bar_width": 0.13, "bar_upper": 1.0},
	},
	# the barred ground dove (zebra dove): small, long-tailed, gray-brown and finely barred, a
	# blue-gray face, pinkish below
	"zebra_dove": {
		"L": 0.21, "girth": 1.0, "stand": STAND, "upright": 0.2, "bill": [0.014, 0.0055, Color(0.5, 0.55, 0.62), 0.0], "eye": 0.9,
		"bob": 0.2,       # the head is what lies further forward than this share of its length
		"plumage": {"upper": Color(0.4, 0.34, 0.27), "under": Color(0.72, 0.6, 0.55), "under_edge": -0.2, "roughness": 0.8,
			"cap": Color(0.55, 0.62, 0.7), "cap_from": 0.0, "cap_to": 0.1, "cap_soft": 0.03, "cap_side": 0.8,
			"mottle": 0.7, "mottle_color": Color(0.13, 0.11, 0.09)},
		"fold": [Color(0.4, 0.34, 0.27), Color(0.34, 0.29, 0.23), Color(0.2, 0.17, 0.14)],
		"tail": [0.1, [Color(0.3, 0.26, 0.21), Color(0.16, 0.14, 0.12), Color(0.85, 0.85, 0.82)]],
		"legs": [0.014, 0.02, Color(0.75, 0.42, 0.45)],
		"half": 0.14, "lead": [[0, 0.0219], [0.42, 0.0270], [0.7, 0.0142], [1.0, -0.0258]],
		"trail": [[0, -0.0412], [0.42, -0.0386], [0.7, -0.0386], [0.9, -0.0412], [1.0, -0.0386]],
		"wing": {"color_in": Color(0.4, 0.34, 0.27), "color_out": Color(0.2, 0.17, 0.14), "color_tip": Color(0.14, 0.12, 0.1),
			"color_under": Color(0.62, 0.42, 0.3), "under": 0.8, "backlight": 0.3},
	},
	# the Seychelles fody ("toc-toc"): sparrow-sized, dull olive-brown and streaked, a stout bill
	"fody": {
		"L": 0.125, "girth": 1.15, "stand": STAND, "upright": 0.28, "bill": [0.011, 0.0075, Color(0.12, 0.1, 0.08), 0.0], "eye": 1.0,
		"plumage": {"upper": Color(0.3, 0.27, 0.15), "under": Color(0.5, 0.46, 0.32), "under_edge": -0.25, "roughness": 0.85,
			"mottle": 0.6, "mottle_color": Color(0.14, 0.12, 0.07)},
		"fold": [Color(0.3, 0.27, 0.15), Color(0.24, 0.21, 0.12), Color(0.13, 0.11, 0.07)],
		"tail": [0.04, [Color(0.24, 0.21, 0.12), Color(0.2, 0.18, 0.1), Color(0.16, 0.14, 0.08)]],
		"legs": [0.016, 0.022, Color(0.4, 0.3, 0.22)],
		"half": 0.09, "lead": [[0, 0.0141], [0.42, 0.0174], [0.7, 0.0091], [1.0, -0.0166]],
		"trail": [[0, -0.0265], [0.42, -0.0248], [0.7, -0.0248], [0.9, -0.0265], [1.0, -0.0248]],
		"wing": {"color_in": Color(0.3, 0.27, 0.15), "color_out": Color(0.17, 0.15, 0.09), "color_tip": Color(0.13, 0.11, 0.07),
			"color_under": Color(0.5, 0.46, 0.34), "under": 0.7, "backlight": 0.3},
	},
	# the Seychelles magpie-robin: glossy black all over, a white patch on the shoulder,
	# long black legs; rare
	"magpie_robin": {
		"L": 0.23, "girth": 1.0, "stand": STAND, "upright": 0.34, "bill": [0.02, 0.006, Color(0.02, 0.02, 0.02), 0.0], "eye": 1.0,
		"plumage": {"upper": Color(0.02, 0.022, 0.04), "under": Color(0.02, 0.022, 0.04), "roughness": 0.4},
		"fold": [Color(0.8, 0.8, 0.8), Color(0.03, 0.03, 0.04), Color(0.02, 0.02, 0.03)],
		"tail": [0.085, [Color(0.02, 0.02, 0.035), Color(0.02, 0.02, 0.035), Color(0.02, 0.02, 0.035)]],
		"legs": [0.03, 0.046, Color(0.03, 0.03, 0.03)],
		"half": 0.17, "lead": [[0, 0.0266], [0.42, 0.0328], [0.7, 0.0172], [1.0, -0.0313]],
		"trail": [[0, -0.0500], [0.42, -0.0469], [0.7, -0.0469], [0.9, -0.0500], [1.0, -0.0469]],
		"wing": {"color_in": Color(0.02, 0.022, 0.04), "color_out": Color(0.02, 0.022, 0.04), "color_tip": Color(0.02, 0.02, 0.03),
			"color_under": Color(0.08, 0.08, 0.09), "under": 0.5, "backlight": 0.1,
			"color_bar": Color(0.95, 0.95, 0.93), "bar_line": Vector4(0.08, 0.75, 0.4, 0.55), "bar_width": 0.12, "bar_upper": 1.0},
	},
	"heron": {
		"L": 0.36, "girth": 1.0, "stand": HUNCHED, "upright": 0.42, "bill": [0.064, 0.0085, Color(0.1, 0.1, 0.08), -0.002], "eye": 1.1,
		"plumage": {"upper": Color(0.2, 0.25, 0.26), "under": Color(0.52, 0.5, 0.46), "under_edge": -0.1, "roughness": 0.7,
			"cap": Color(0.03, 0.035, 0.04), "cap_from": 0.01, "cap_to": 0.21, "cap_soft": 0.04, "cap_side": 0.5,
			"mottle": 0.55, "mottle_color": Color(0.5, 0.5, 0.42)},
		"fold": [Color(0.22, 0.27, 0.28), Color(0.2, 0.25, 0.26), Color(0.1, 0.12, 0.13)],
		"tail": [0.06, [Color(0.15, 0.18, 0.19), Color(0.13, 0.16, 0.17), Color(0.12, 0.14, 0.15)]],
		"legs": [0.05, 0.068, Color(0.72, 0.62, 0.18)],
		"half": 0.31, "lead": [[0, 0.05], [0.42, 0.064], [0.7, 0.042], [1.0, -0.04]],
		"trail": [[0, -0.1], [0.42, -0.102], [0.7, -0.106], [0.9, -0.1], [1.0, -0.066]],
		"wing": {"color_in": Color(0.21, 0.26, 0.27), "color_out": Color(0.13, 0.16, 0.18), "color_tip": Color(0.09, 0.11, 0.12),
			"color_under": Color(0.42, 0.42, 0.4), "under": 0.7, "backlight": 0.2},
	},
}

static var _cache := {}


## One triangle of [position, normal, color, uv], the corners in the order the normals ask
## for (double-sided materials: see the note on windings in HANDOFF.md).
static func _emit(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var front := ((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3))
	var tri := [a, b, c] if front.dot((a[1] as Vector3) + (b[1] as Vector3) + (c[1] as Vector3)) >= 0.0 else [a, c, b]
	for q: Array in tri:
		st.set_color(q[2])
		st.set_normal(q[1])
		st.set_uv(q[3])
		st.add_vertex(q[0])


static func _quads(st: SurfaceTool, g: Array) -> void:
	for i in g.size() - 1:
		for j in (g[0] as Array).size() - 1:
			if (g[i][j][0] as Vector3).distance_squared_to(g[i][j + 1][0]) > 1e-14:
				_emit(st, g[i][j], g[i + 1][j + 1], g[i][j + 1])
			if (g[i + 1][j][0] as Vector3).distance_squared_to(g[i + 1][j + 1][0]) > 1e-14:
				_emit(st, g[i][j], g[i + 1][j], g[i + 1][j + 1])


## The body: stations [u, half-width, half-height, height of the middle] in units of L / 0.35.
static func _loft(st: SurfaceTool, stations: Array, length: float, girth: float, front: float) -> void:
	var k := length / 0.35
	var sub := 3
	var n := (stations.size() - 1) * sub
	var g: Array = []
	for i in n + 1:
		var t := float(i) / n * (stations.size() - 1)
		var s0 := mini(int(t), stations.size() - 2)
		var f := t - s0
		var a: Array = stations[s0]
		var b: Array = stations[s0 + 1]
		var u := lerpf(a[0], b[0], f)
		f = f * f * (3.0 - 2.0 * f) * 0.5 + f * 0.5
		var gg := girth if u > 0.16 else (1.0 + girth) * 0.5
		var hw := lerpf(a[1], b[1], f) * k * gg
		var hh := lerpf(a[2], b[2], f) * k * gg
		var dz := lerpf(a[3], b[3], f) * k
		var row: Array = []
		for j in 13:
			var ang := TAU * (j % 12) / 12.0          # 0 on the back
			var p := Vector3(hw * sin(ang), dz + hh * cos(ang), length * (u - front))
			var nrm := Vector3(sin(ang) / maxf(hw, 0.0005), cos(ang) / maxf(hh, 0.0005), 0.0).normalized()
			row.append([p, nrm, Color(1, 1, 1), Vector2(u, float(j) / 12.0)])
		g.append(row)
	_quads(st, g)


## A tube through `pts` with radii [up-down, sideways] at each point and a color at each point.
static func _tube(st: SurfaceTool, pts: Array, radii: Array, cols: Array, sides := 6) -> void:
	var g: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := t.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var up := side.cross(t).normalized()
		var r: Array = radii[i] if radii[i] is Array else [radii[i], radii[i]]
		var row: Array = []
		for q in sides + 1:
			var a := TAU * (q % sides) / float(sides)
			var off := up * (cos(a) * float(r[0])) + side * (sin(a) * float(r[1]))
			var nrm := (up * (cos(a) * float(r[1])) + side * (sin(a) * float(r[0]))).normalized()
			row.append([p + off, nrm, cols[mini(i, cols.size() - 1)], Vector2.ZERO])
		g.append(row)
	_quads(st, g)


static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var g: Array = []
	for i in 6:
		var row: Array = []
		for j in 9:
			var th := PI * i / 5.0
			var ph := TAU * (j % 8) / 8.0
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			row.append([c + d * r, d, col, Vector2.ZERO])
		g.append(row)
	_quads(st, g)


## A flat feather from `base` along `dir`, lying in the plane of `dir` and `across`; the colors
## run from its base to its tip.
static func _feather(st: SurfaceTool, base: Vector3, dir: Vector3, across: Vector3, length: float, width: float, cols: Array) -> void:
	var n := dir.cross(across).normalized()
	if n.y < 0.0:
		n = -n
	var prof := [[0.0, 0.35], [0.5, 1.0], [0.9, 0.7], [1.0, 0.0]]
	for i in prof.size() - 1:
		var f0: float = prof[i][0]
		var f1: float = prof[i + 1][0]
		var c0: Color = cols[mini(int(f0 * cols.size()), cols.size() - 1)]
		var c1: Color = cols[mini(int(f1 * cols.size() - 0.01), cols.size() - 1)]
		var a0 := base + dir * (length * f0) - across * (width * float(prof[i][1]))
		var a1 := base + dir * (length * f0) + across * (width * float(prof[i][1]))
		var b0 := base + dir * (length * f1) - across * (width * float(prof[i + 1][1]))
		var b1 := base + dir * (length * f1) + across * (width * float(prof[i + 1][1]))
		_emit(st, [a0, n, c0, Vector2.ZERO], [a1, n, c0, Vector2.ZERO], [b1, n, c1, Vector2.ZERO])
		_emit(st, [a0, n, c0, Vector2.ZERO], [b1, n, c1, Vector2.ZERO], [b0, n, c1, Vector2.ZERO])


static func _edge(pts: Array, s: float) -> float:
	for i in pts.size() - 1:
		if s <= float(pts[i + 1][0]) or i == pts.size() - 2:
			var t := clampf((s - float(pts[i][0])) / maxf(float(pts[i + 1][0]) - float(pts[i][0]), 1e-5), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65
			return lerpf(pts[i][1], pts[i + 1][1], t)
	return pts[pts.size() - 1][1]


## A flat right wing for shaders/wing.gdshader (the same layout as tools/assets6.py: wing()):
## origin at the shoulder, +X along the span, +Z back; UV.x = 0 shoulder .. 1 tip, UV.y = 1 at
## the leading edge .. 0 at the trailing edge. `lead` and `trail`: [[span fraction, how far
## forward], ...].
static func wing_mesh(half: float, lead: Array, trail: Array, nspan := 16, nchord := 4, camber := 0.06) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for i in nspan + 1:
		var s := float(i) / nspan
		var yl := _edge(lead, s)
		var yt := _edge(trail, s)
		var row: Array = []
		for j in nchord + 1:
			var c := float(j) / nchord
			row.append([Vector3(s * half, camber * (yl - yt) * 4.0 * c * (1.0 - c), -(yl + (yt - yl) * c)), Vector2(s, 1.0 - c)])
		grid.append(row)
	for i in nspan:
		for j in nchord:
			for idx in [[i, j], [i + 1, j + 1], [i + 1, j], [i, j], [i, j + 1], [i + 1, j + 1]]:
				st.set_normal(Vector3.UP)
				st.set_uv(grid[idx[0]][idx[1]][1])
				st.add_vertex(grid[idx[0]][idx[1]][0])
	return st.commit()


static func _shader_mat(path: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for key: String in params:
		m.set_shader_parameter(key, params[key])
	return m


static func _parts_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The meshes and materials of a kind, made once.
static func _assets(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var sp: Dictionary = SPECS[kind]
	var length: float = sp["L"]
	var k := length / 0.35
	var girth: float = sp["girth"]
	var bill: Array = sp["bill"]
	var fold: Array = sp["fold"]
	var tail: Array = sp["tail"]
	var eye_col := Color(0.01, 0.01, 0.012)
	var plum := _shader_mat("res://shaders/bird.gdshader", sp["plumage"])
	var parts: Material = _parts_mat()
	if sp.has("bob"):
		# (a head that bobs: bill and eyes must go with it)
		plum.set_shader_parameter("bob_z", float(sp["bob"]) * length)
		parts = _shader_mat("res://shaders/bird_parts.gdshader", {"bob_z": float(sp["bob"]) * length})
	var out := {}
	for mode in ["fly", "stand"]:
		var stations: Array = FLY if mode == "fly" else sp["stand"]
		var front := 0.4 if mode == "fly" else 0.35
		var body := SurfaceTool.new()
		body.begin(Mesh.PRIMITIVE_TRIANGLES)
		_loft(body, stations, length, girth, front)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# bill and eyes
		var head_y := float(stations[1][3]) * k
		var b0 := Vector3(0, head_y, -length * front + 0.004)
		var bcol: Color = bill[2]
		_tube(st, [b0, b0 + Vector3(0, float(bill[3]) * 0.4, -float(bill[0]) * 0.6), b0 + Vector3(0, float(bill[3]), -float(bill[0]))],
			[float(bill[1]) * k, float(bill[1]) * k * 0.6, 0.001], [bcol, bcol, bcol.darkened(0.25)])
		var gg := (1.0 + girth) * 0.5
		for sx in [1.0, -1.0]:
			_ball(st, Vector3(sx * 0.027 * k * gg, float(stations[2][3]) * k + 0.01 * k, length * (0.07 - front)), 0.007 * k * float(sp["eye"]), eye_col)
		var tail_base := Vector3(0, float(stations[stations.size() - 2][3]) * k, length * (0.76 - front))
		var tail_len: float = tail[0]
		if mode == "stand":
			# folded wings: long slabs along the sides, crossing over the tail; the tail closed
			for sx in [1.0, -1.0]:
				_tube(st, [Vector3(sx * 0.05 * k * girth, 0.02 * k, -length * 0.14), Vector3(sx * 0.06 * k * girth, 0.02 * k, length * 0.15), Vector3(sx * 0.018 * k, 0.018 * k, length * 0.56)],
					[[0.035 * k, 0.01 * k], [0.04 * k, 0.012 * k], [0.012 * k, 0.004]], fold)
				for f in 3:
					_feather(st, tail_base - Vector3(0, 0.002 * f, 0), Vector3(sx * 0.05 * f, 0, 1).normalized(), Vector3(1, 0, 0), tail_len * 1.1, tail_len * 0.2, tail[1])
		else:
			# the tail a little spread
			for f in 9:
				var a := (f - 4) * 0.09
				_feather(st, tail_base - Vector3(0, 0.0012 * absf(f - 4), 0), Vector3(sin(a), 0, cos(a)), Vector3(cos(a), 0, -sin(a)),
					tail_len * (1.0 - 0.05 * absf(f - 4)), tail_len * 0.2, tail[1])
		var mesh := body.commit()
		st.commit(mesh)
		mesh.surface_set_material(0, plum)
		mesh.surface_set_material(1, parts)
		out[mode] = mesh
	# wings
	var wing := wing_mesh(sp["half"], sp["lead"], sp["trail"])
	var wparams: Dictionary = (sp["wing"] as Dictionary).duplicate()
	wparams["span"] = float(sp["half"])
	out["wing"] = wing
	out["wing_mat"] = _shader_mat("res://shaders/wing.gdshader", wparams)
	out["parts"] = parts
	# legs: the upper leg (feathered at the top) and the lower leg with its toes
	if sp.has("legs"):
		var lg: Array = sp["legs"]
		var lcol: Color = lg[2]
		var up := SurfaceTool.new()
		up.begin(Mesh.PRIMITIVE_TRIANGLES)
		var feather_col: Color = (sp["plumage"] as Dictionary)["under"]
		_tube(up, [Vector3(0, 0.012 * k, 0), Vector3(0, -float(lg[0]) * 0.45, 0), Vector3(0, -float(lg[0]), 0)],
			[0.012 * k, 0.0045 * k, 0.0032 * k], [feather_col, lcol, lcol])
		var lo := SurfaceTool.new()
		lo.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tube(lo, [Vector3.ZERO, Vector3(0, -float(lg[1]), 0)], [0.0034 * k, 0.003 * k], [lcol, lcol])
		var foot := Vector3(0, -float(lg[1]), 0)
		for toe: Array in [[0.0, 1.0], [0.55, 0.9], [-0.55, 0.9], [PI, 0.45]]:
			var d := Vector3(sin(float(toe[0])), 0, -cos(float(toe[0])))
			_tube(lo, [foot, foot + d * (0.032 * k * float(toe[1])) + Vector3(0, -0.002 * k, 0)], [0.0028 * k, 0.0012 * k], [lcol, lcol], 4)
		var um := up.commit()
		um.surface_set_material(0, parts)
		var lm := lo.commit()
		lm.surface_set_material(0, parts)
		out["leg_up"] = um
		out["leg_lo"] = lm
	if sp.has("streamers"):
		var ss := SurfaceTool.new()
		ss.begin(Mesh.PRIMITIVE_TRIANGLES)
		var white := Color(0.97, 0.97, 0.96)
		for sx in [1.0, -1.0]:
			_feather(ss, Vector3(sx * 0.004, 0, 0), Vector3(sx * 0.03, 0, 1).normalized(), Vector3(1, 0, 0), sp["streamers"], 0.008, [white, white, white])
		var sm := ss.commit()
		sm.surface_set_material(0, parts)
		out["streamers"] = sm
	_cache[kind] = out
	return out


## A tropicbird's chick: a ball of pale gray down the size of a grapefruit, a dark bill, dark
## eyes. It sits on the ground where it hatched, alone most of the day while its parents
## are at sea. Forward is -Z, the ground y = 0; colored by vertex.
## (`down`: the color of its down. The sooty tern's chick is the same shape, smaller, and
## speckled gray-buff: the script scales it.)
static func chick(down := Color(0.8, 0.8, 0.78)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ball(st, Vector3(0, 0.068, 0.0), 0.076, down)
	_ball(st, Vector3(0, 0.06, 0.052), 0.064, down.darkened(0.06))
	_ball(st, Vector3(0, 0.132, -0.05), 0.043, down.lightened(0.05))
	var bill := Color(0.13, 0.13, 0.14)
	_tube(st, [Vector3(0, 0.13, -0.086), Vector3(0, 0.127, -0.108), Vector3(0, 0.123, -0.127)], [0.0095, 0.006, 0.001], [bill, bill, bill])
	for sx in [1.0, -1.0]:
		_ball(st, Vector3(sx * 0.03, 0.142, -0.074), 0.0065, Color(0.01, 0.01, 0.012))
	var m := st.commit()
	m.surface_set_material(0, _parts_mat())
	return m


## A sooty tern's egg, 5 cm long: cream, blotched and speckled with brown (by vertex). It lies
## on its side along Z, on the ground at y = 0.
static func egg() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g: Array = []
	for i in 9:
		var row: Array = []
		for j in 13:
			var th := PI * i / 8.0
			var ph := TAU * (j % 12) / 12.0
			var d := Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
			# (blunt at one end, narrower at the other)
			var r := 0.0175 * (1.0 - 0.14 * d.z)
			var hsh := fposmod(sin(float(i * 37 + (j % 12) * 91) * 12.9898) * 43758.5453, 1.0)
			var col := Color(0.86, 0.8, 0.68).lerp(Color(0.32, 0.2, 0.12), 0.85 if hsh > 0.66 else 0.0)
			row.append([Vector3(d.x * r, d.y * r + 0.017, d.z * 0.025), d, col, Vector2.ZERO])
		g.append(row)
	_quads(st, g)
	var m := st.commit()
	m.surface_set_material(0, _parts_mat())
	return m


## A bird of `kind` ("tropicbird", "turnstone", "crab_plover", "heron"): see the top of the file.
static func make(kind: String) -> Dictionary:
	var sp: Dictionary = SPECS[kind]
	var as_: Dictionary = _assets(kind)
	var length: float = sp["L"]
	var k := length / 0.35
	var root := Node3D.new()
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	root.add_child(tilt)
	var stand := MeshInstance3D.new()
	stand.name = "Stand"
	stand.mesh = as_["stand"]
	tilt.add_child(stand)
	var fly := Node3D.new()
	fly.name = "Fly"
	tilt.add_child(fly)
	var body := MeshInstance3D.new()
	body.mesh = as_["fly"]
	fly.add_child(body)
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		w.mesh = as_["wing"]
		w.material_override = as_["wing_mat"]
		w.extra_cull_margin = float(sp["half"]) * 1.2
		w.position = Vector3(side * 0.03 * k, 0.012, -length * 0.12)
		fly.add_child(w)
		w.set_instance_shader_parameter("side", side)
		wings.append(w)
	var streamers: Node3D = null
	if as_.has("streamers"):
		var sm := MeshInstance3D.new()
		sm.name = "Streamers"
		sm.mesh = as_["streamers"]
		sm.position = Vector3(0, 0.004 * k, length * (0.76 - 0.4) + 0.03)
		fly.add_child(sm)
		streamers = sm
		# (the sitting bird has them too: they stick out behind it)
		var s2 := MeshInstance3D.new()
		s2.mesh = as_["streamers"]
		s2.position = Vector3(0, 0.006 * k, length * (0.76 - 0.35) + 0.03)
		s2.rotation = Vector3(0.12, 0, 0)
		stand.add_child(s2)
	var legs: Array = []
	var hip := 0.0
	if as_.has("leg_up"):
		var lg: Array = sp["legs"]
		hip = (float(lg[0]) + float(lg[1])) * 0.93
		for side in [-1.0, 1.0]:
			var upper := MeshInstance3D.new()
			upper.mesh = as_["leg_up"]
			upper.position = Vector3(side * 0.022 * k, hip, 0.01 * k)
			root.add_child(upper)
			var lower := MeshInstance3D.new()
			lower.mesh = as_["leg_lo"]
			lower.position = Vector3(0, -float(lg[0]), 0)
			upper.add_child(lower)
			legs.append([upper, lower])
	else:
		hip = 0.05 * k        # (sitting: the belly on the ground)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	fly.visible = false
	return {"root": root, "tilt": tilt, "stand": stand, "fly": fly, "wings": wings, "legs": legs, "hip": hip,
		"upright": float(sp["upright"]), "streamers": streamers, "kind": kind, "L": length}
