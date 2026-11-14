extends RefCounted
## Shared flight model for the birds and flying foxes.
##
## A bird is a dictionary with "pos", "yaw", "bank", "vy" and "speed" (its airspeed). `steer()`
## flies it toward a goal the way a real bird has to: it rolls into a bank, the bank turns it
## (coordinated turn: rate = g * tan(bank) / speed), climbing costs speed and diving gains it, and
## the trade wind carries it, so it points a little into the wind to hold its track.
## `beat()` gives the wing-beat pose: a slower down-stroke, a quicker up-stroke with the wrist
## flexed and the hand wing trailing, and the body heaving against the wings.
## The wings themselves are bendable meshes (assets/models/wings.glb, shaders/wing.gdshader):
## `wings()` fits a pair to a model in place of its old flat wing parts, `pose()` sets their shape.

const G := 9.81
## The trade wind blows off the sea, the way the palm fronds lean (palm_frond.gdshader).
const WIND_DIR := Vector3(-0.9701, 0.0, 0.2425)


## Wind at `height` above the sea for the current gust strength (Ambience.gust).
static func wind(gust: float, height: float) -> Vector3:
	return WIND_DIR * (1.6 + 1.9 * clampf(height / 30.0, 0.0, 1.0)) * clampf(gust, 0.3, 1.6)


static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func make(pos: Vector3, yaw: float, speed: float) -> Dictionary:
	return {"pos": pos, "yaw": yaw, "bank": 0.0, "vy": 0.0, "speed": speed, "gvel": forward(yaw) * speed}


## One step toward `goal`. `p`: "cruise" airspeed, "max_bank", "roll" (how fast it rolls, 1/s),
## "climb" and "sink" (m/s). Optional `speed_goal` overrides the cruise speed (landing, hovering).
static func steer(b: Dictionary, goal: Vector3, delta: float, w: Vector3, p: Dictionary, speed_goal := -1.0) -> void:
	var pos: Vector3 = b["pos"]
	var v: float = maxf(b["speed"], 0.5)
	var to := goal - pos
	var d := Vector2(to.x, to.z)
	var err := 0.0
	if d.length() > 0.05:
		d = d.normalized()
		# heading that holds the track to the goal against the crosswind
		var w2 := Vector2(w.x, w.z)
		var hp := -(w2 - d * w2.dot(d)) / v
		if hp.length() > 0.85:
			hp = hp.normalized() * 0.85
		var h := hp + d * sqrt(1.0 - hp.length_squared())
		err = angle_difference(b["yaw"], atan2(-h.x, -h.y))
	# bank > 0: right wing down, turning right (yaw decreasing)
	var max_bank: float = p["max_bank"]
	var want_bank := clampf(-err * 1.7, -max_bank, max_bank)
	b["bank"] = lerpf(b["bank"], want_bank, 1.0 - exp(-float(p["roll"]) * delta))
	b["yaw"] = wrapf(b["yaw"] - G * tan(b["bank"]) / maxf(v, 2.5) * delta, -PI, PI)
	var want_vy := clampf(to.y * 0.9, -float(p["sink"]), float(p["climb"]))
	b["vy"] = lerpf(b["vy"], want_vy, 1.0 - exp(-2.2 * delta))
	# height is paid for with speed, and a steep bank costs a little too
	var cruise: float = speed_goal if speed_goal >= 0.0 else float(p["cruise"]) - 0.45 * float(b["vy"]) - 1.2 * absf(b["bank"])
	b["speed"] = lerpf(b["speed"], cruise, 1.0 - exp(-1.4 * delta))
	var gvel: Vector3 = forward(b["yaw"]) * b["speed"] + Vector3(0.0, b["vy"], 0.0) + w
	b["gvel"] = gvel
	b["pos"] = pos + gvel * delta


## Body attitude: heading, nose up or down with the climb (plus `pitch`), rolled into the turn.
static func attitude(b: Dictionary, pitch := 0.0) -> Basis:
	var climb := atan2(float(b["vy"]), maxf(float(b["speed"]), 2.0)) * 0.85
	return Basis(Vector3.UP, b["yaw"]) * Basis(Vector3.RIGHT, climb + pitch) * Basis(Vector3.FORWARD, b["bank"])


## Wing-beat pose at phase `ph` (radians, wings at the top at 0). Returns [shoulder, wrist, fold,
## heave, twist]: shoulder angle (up positive, x `amp`), bend at the wrist and on to the tip, how far
## the wing is folded (0..1: the hand wing swept back), the body's heave (-1 lowest .. 1 highest) and
## the twist of the wing (leading edge down positive).
static func beat(ph: float, amp: float) -> Array:
	# the down-stroke takes ~57 % of the beat
	var s := ph + 0.25 * (cos(ph) - 1.0)
	var up := maxf(-sin(s), 0.0)             # 0 on the down-stroke, peaks mid up-stroke
	var down := maxf(sin(s), 0.0)
	var shoulder := amp * cos(s)
	# the hand wing trails the arm: bent up under load going down, hanging and folded coming up
	var wrist := amp * (0.55 * cos(s - 0.95) + 0.25 * down - 0.5 * up)
	return [shoulder, wrist, 0.75 * up * clampf(amp * 2.0, 0.0, 1.0), -cos(s - 0.35), amp * (0.45 * down - 0.3 * up)]


static var _wing_meshes := {}


## Fits a pair of bendable wings of `kind` ("Tern", "Noddy", "WhiteTern", "Frigate", "Bat") to
## `model` at its shoulders, replacing the placeholder nodes named `left` and `right`. `world`
## supplies the material ("Wing" + kind). Returns [left wing, right wing] for `pose()`.
static func wings(model: Node3D, kind: String, left: String, right: String, world: Node, shadows := true) -> Array:
	if _wing_meshes.is_empty():
		var tmp := (load("res://assets/models/wings.glb") as PackedScene).instantiate()
		for m in tmp.find_children("*", "MeshInstance3D", true, false):
			_wing_meshes[String(m.name)] = (m as MeshInstance3D).mesh
		tmp.free()
	var mesh: Mesh = _wing_meshes[kind + "Wing"]
	var mat: ShaderMaterial = world.get_material("Wing" + kind)
	var length := mesh.get_aabb().end.x
	mat.set_shader_parameter("span", length)
	var out := []
	for side in [[left, -1.0], [right, 1.0]]:
		var old := model.find_child(side[0], true, false) as Node3D
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.extra_cull_margin = length * 1.2   # the shader swings it far out of its flat bounding box
		old.get_parent().add_child(mi)
		mi.position = old.position
		mi.set_instance_shader_parameter("side", side[1])
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		old.get_parent().remove_child(old)
		old.free()
		out.append(mi)
	return out


## Shapes both wings: shoulder angle `arm` and wrist/tip bend `hand` (up positive), `fold` (0 spread
## .. 1 folded back) and `twist`. `roll` raises one wing and lowers the other.
static func pose(pair: Array, arm: float, hand: float, fold: float, twist: float, roll := 0.0) -> void:
	(pair[0] as MeshInstance3D).set_instance_shader_parameter("pose", Vector4(arm - roll, hand, fold, twist))
	(pair[1] as MeshInstance3D).set_instance_shader_parameter("pose", Vector4(arm + roll, hand, fold, twist))


## The two halves of a model's tail ({prefix}TailL / {prefix}TailR), for `tail()`.
static func tail_of(model: Node3D, prefix: String) -> Array:
	return [model.find_child(prefix + "TailL", true, false), model.find_child(prefix + "TailR", true, false)]


## Opens the tail (`spread`, radians each side: the fork opens, the fan widens) and lowers it (`down`).
static func tail(pair: Array, spread: float, down := 0.0) -> void:
	if pair[0] == null or pair[1] == null:
		return
	(pair[0] as Node3D).rotation = Vector3(down, -spread, 0.0)
	(pair[1] as Node3D).rotation = Vector3(down, spread, 0.0)
