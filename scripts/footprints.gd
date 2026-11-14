extends Node3D
## Leaves bare footprints (decals) behind the player. Prints slowly fade, and the
## ones in the swash zone are washed away within seconds.

@export var player_path: NodePath = ^"../Player"
@export var pool_size := 180
@export var life := 120.0

var _player: CharacterBody3D
var _pool: Array[Decal] = []
var _born: Array[float] = []
var _wet: Array[bool] = []
var _next := 0
var _left := false
var _time := 0.0
var _albedo_l: ImageTexture
var _albedo_r: ImageTexture
var _normal_l: ImageTexture
var _normal_r: ImageTexture
var _emit_l: ImageTexture
var _emit_r: ImageTexture


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_make_textures()
	for i in pool_size:
		var d := Decal.new()
		d.size = Vector3(0.13, 0.25, 0.28)
		d.visible = false
		d.albedo_mix = 1.0
		d.normal_fade = 0.3
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.cull_mask = 1
		add_child(d)
		_pool.append(d)
		_born.append(-1e9)
		_wet.append(false)
	if _player:
		_player.footstep.connect(_on_step)


func _height(u: float, v: float, mirror: bool) -> float:
	# u across (0..1), v along the foot (0 = toes, 1 = heel)
	if mirror:
		u = 1.0 - u
	var h := 0.0
	var heel := Vector2((u - 0.52) / 0.30, (v - 0.80) / 0.17)
	h = maxf(h, 1.0 - smoothstep(0.7, 1.0, heel.length()))
	var ball := Vector2((u - 0.47) / 0.40, (v - 0.38) / 0.17)
	h = maxf(h, 1.0 - smoothstep(0.7, 1.0, ball.length()))
	# outer edge of the arch
	var arch := Vector2((u - 0.66) / 0.16, (v - 0.6) / 0.25)
	h = maxf(h, (1.0 - smoothstep(0.6, 1.0, arch.length())) * 0.8)
	# toes
	var toes := [[0.30, 0.13, 0.085], [0.45, 0.10, 0.06], [0.57, 0.11, 0.055], [0.67, 0.14, 0.05], [0.76, 0.18, 0.045]]
	for t in toes:
		var d := Vector2((u - t[0]) / t[2], (v - t[1]) / (t[2] * 1.15))
		h = maxf(h, 1.0 - smoothstep(0.6, 1.0, d.length()))
	return h


func _make_textures() -> void:
	for mirror in [false, true]:
		var w := 48
		var hgt := 112
		var hm := PackedFloat32Array()
		hm.resize(w * hgt)
		for y in hgt:
			for x in w:
				var u := (x + 0.5) / w
				var v := (y + 0.5) / hgt
				var core := _height(u, v, mirror)
				# sand pushed up around the print
				var rim := 0.0
				for o in [Vector2(0.06, 0), Vector2(-0.06, 0), Vector2(0, 0.04), Vector2(0, -0.04)]:
					rim = maxf(rim, _height(u + o.x, v + o.y, mirror))
				hm[y * w + x] = -core + (rim - core) * 0.35
		var emi := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
		var alb := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
		var nor := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
		for y in hgt:
			for x in w:
				var hc := hm[y * w + x]
				var hx := hm[y * w + mini(x + 1, w - 1)] - hm[y * w + maxi(x - 1, 0)]
				var hy := hm[mini(y + 1, hgt - 1) * w + x] - hm[maxi(y - 1, 0) * w + x]
				var n := Vector3(-hx * 4.0, -hy * 4.0, 1.0).normalized()
				var a := clampf(absf(hc) * 2.2, 0.0, 1.0)
				# inside the print the sand is a touch darker and damper
				var shade := 0.45 if hc < 0.0 else 1.0
				alb.set_pixel(x, y, Color(shade * 0.9, shade * 0.86, shade * 0.78, a * (0.9 if hc < 0.0 else 0.15)))
				nor.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, a))
				var glow := a * (1.0 if hc < 0.0 else 0.0) * (0.4 + 0.6 * randf())
				emi.set_pixel(x, y, Color(0.15 * glow, 0.62 * glow, 1.0 * glow, 1.0))
		alb.generate_mipmaps()
		nor.generate_mipmaps()
		emi.generate_mipmaps()
		if mirror:
			_emit_r = ImageTexture.create_from_image(emi)
		else:
			_emit_l = ImageTexture.create_from_image(emi)
		if mirror:
			_albedo_r = ImageTexture.create_from_image(alb)
			_normal_r = ImageTexture.create_from_image(nor)
		else:
			_albedo_l = ImageTexture.create_from_image(alb)
			_normal_l = ImageTexture.create_from_image(nor)


func _on_step(surface: String, _strength: float) -> void:
	if surface == "water" or _player == null:
		return
	var pos := _player.global_position
	# prints only in loose sand: the beaches and the floor of the grotto, not on the forest
	# floor, the grass or the granite
	var ls := get_node_or_null("../Landscape")
	if ls and ls.has_method("sandy"):
		if not ls.sandy(Vector2(pos.x, pos.z)):
			return
	elif _player.has_method("ground_height") and _player.ground_height(Vector2(pos.x, pos.z)) > 1.7:
		return
	var vel := Vector3(_player.velocity.x, 0, _player.velocity.z)
	if vel.length() < 0.2:
		return
	# the feet point the way the walker faces, whichever way they are moving (backward, sideways):
	# only the place where the foot comes down leads in the direction of travel
	var fwd := vel.normalized()
	var yaw: Variant = _player.get("_yaw")
	if yaw != null:
		fwd = Basis(Vector3.UP, float(yaw)) * Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	_left = not _left
	var side := -0.11 if _left else 0.11
	var foot := pos + right * side + vel.normalized() * 0.15
	var d := _pool[_next]
	_born[_next] = _time
	_wet[_next] = surface == "wet"
	_next = (_next + 1) % pool_size
	d.texture_albedo = _albedo_l if _left else _albedo_r
	d.texture_normal = _normal_l if _left else _normal_r
	# decal texture: u along X, v along Z; v=0 is the toes -> point Z backward
	var b := Basis(right, Vector3.UP, -fwd)
	b = b.rotated(Vector3.UP, randf_range(-0.12, 0.12) + (0.08 if _left else -0.08))
	d.global_transform = Transform3D(b, foot + Vector3(0, 0.02, 0))
	d.modulate = Color(1, 1, 1, 1)
	# at night, prints in wet sand flash blue with stirred-up Noctiluca
	var dc := get_node_or_null("../DayCycle")
	var nf: float = dc.night if dc else 0.0
	# (on the nights the sea glows: daycycle.gd, `glow`)
	if _wet[(_next - 1 + pool_size) % pool_size] and nf > 0.5 and (dc == null or float(dc.get("glow")) > 0.5):
		d.texture_emission = _emit_l if _left else _emit_r
		d.emission_energy = 6.0
	else:
		d.texture_emission = null
		d.emission_energy = 0.0
	d.visible = true


func _process(delta: float) -> void:
	_time += delta
	for i in pool_size:
		var d := _pool[i]
		if not d.visible:
			continue
		var age := _time - _born[i]
		var l := 14.0 if _wet[i] else life
		var a := 1.0 - smoothstep(l * 0.6, l, age)
		if a <= 0.0:
			d.visible = false
		else:
			d.modulate = Color(1, 1, 1, a)
			if d.emission_energy > 0.0:
				d.emission_energy = 6.0 * exp(-age * 0.7)
