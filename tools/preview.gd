extends SceneTree
## Throw-away viewer for the models that are built in code (scripts/sea_models.gd,
## scripts/small_models.gd): renders one of them from six sides on a plain background and saves
## the six pictures as one sheet. No game is started, so it takes a few seconds.
##   godot --path . --resolution 1400x800 --script tools/preview.gd -- <what> <species> <out.png> [phase amp bend]
##   <what>: tiger_shark (species 0), blacktip_shark (2), eagle_ray (1): any function of
##           sea_models.gd that returns a mesh, drawn with sea_creature.gdshader (phase, amp, bend:
##           its swimming pose);
##           turtle (0 green, 1 hawksbill); crab (then: gait stride lift tuck); lizard (0 skink,
##           1 gecko); mudskipper; frog; bird (then the kind as <species>: tropicbird, turnstone,
##           crab_plover, heron; and "fly" after the file name for the flying bird);
##           reef <name> <out.png> [four numbers] [distance]: the reef's characters
##           (scripts/reef_models.gd): anemonefish0, anemonefish1, lionfish, carpet,
##           magnificent, eel, den, moray0, moray1, octopus.
##           land <what> <out.png> [numbers]: the small things on land (scripts/land_models.gd):
##           shell <kind 0-4>, hermit [shell kind, gait, stride, tuck, lift], millipede [gait,
##           moving], snail [out_k], pitcher / orchid / vanilla [seed]. PDIST=0.5 in the
##           environment halves the viewing distance.
## It quits by itself after 240 frames if something goes wrong.
var _mi: MeshInstance3D
var _cam: Camera3D
var _views := [[Vector3(6, 0.3, 0), "side"], [Vector3(0.01, 7, 0), "top"], [Vector3(0.01, -7, 0), "below"], [Vector3(3.5, 2.0, -4.0), "front"], [Vector3(-3.0, 1.2, 4.5), "rear"], [Vector3(0.0, 0.3, -5.0), "head-on"]]
var _i := -1
var _wait := 8
var _imgs: Array = []
var _args: PackedStringArray
var _frames := 0

func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	var models = load("res://scripts/sea_models.gd")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.5, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.8, 0.9)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	root.add_child(sun)
	if _args[0].begins_with("turtle"):
		var t: Node3D = models.turtle_node(_args[1] == "0")
		root.add_child(t)
		_views = [[Vector3(2.2, 0.3, 0), "side"], [Vector3(0.01, 2.6, 0), "top"], [Vector3(0.01, -2.6, 0), "below"], [Vector3(1.3, 0.9, -1.6), "front"], [Vector3(-1.2, 0.6, 1.8), "rear"], [Vector3(0.0, 0.25, -2.2), "head-on"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "jelly":
		# the moon jellyfish: jelly <where in its beat, 0..1> <out.png>
		_mi = MeshInstance3D.new()
		var jmm := MultiMesh.new()
		jmm.transform_format = MultiMesh.TRANSFORM_3D
		jmm.use_custom_data = true
		jmm.mesh = load("res://scripts/jellyfish.gd").mesh()
		jmm.instance_count = 1
		jmm.set_instance_transform(0, Transform3D())
		jmm.set_instance_custom_data(0, Color(float(_args[1]), 0.3, 0.0, 0.0))
		var jmi := MultiMeshInstance3D.new()
		jmi.multimesh = jmm
		var jm := ShaderMaterial.new()
		jm.shader = load("res://shaders/jellyfish.gdshader")
		jm.set_shader_parameter("under", false)
		jm.set_shader_parameter("still", 1.0)
		jmi.material_override = jm
		root.add_child(jmi)
		e.background_color = Color(0.05, 0.3, 0.42)
		_views = [[Vector3(4.2, 0.0, 0), "side"], [Vector3(0.01, 4.6, 0), "top"], [Vector3(0.01, -4.6, 0), "below"], [Vector3(2.6, 1.8, -2.8), "from above"], [Vector3(-2.4, -1.6, 3.0), "from below"], [Vector3(0.0, -0.4, -4.2), "front"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "lizard":
		_mi = MeshInstance3D.new()
		_mi.mesh = load("res://scripts/small_models.gd").lizard(_args[1] == "1")
		var lm := ShaderMaterial.new()
		lm.shader = load("res://shaders/lizard.gdshader")
		lm.set_shader_parameter("species", int(_args[1]))
		_mi.material_override = lm
		root.add_child(_mi)
		_mi.position = Vector3(0, -0.01, -0.03)
		_views = [[Vector3(0.3, 0.03, 0.0), "side"], [Vector3(0.0005, 0.33, 0), "top"], [Vector3(0.0005, -0.33, 0), "below"], [Vector3(0.14, 0.1, -0.2), "front"], [Vector3(-0.15, 0.08, 0.2), "rear"], [Vector3(0.06, 0.03, -0.16), "head"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.005
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "mudskipper":
		_mi = MeshInstance3D.new()
		_mi.mesh = load("res://scripts/small_models.gd").mudskipper()
		var mm := StandardMaterial3D.new()
		mm.vertex_color_use_as_albedo = true
		mm.vertex_color_is_srgb = true
		mm.roughness = 0.25
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mi.material_override = mm
		root.add_child(_mi)
		_mi.position = Vector3(0, -0.012, -0.015)
		_views = [[Vector3(0.14, 0.02, 0.0), "side"], [Vector3(0.0005, 0.16, 0), "top"], [Vector3(0.0, 0.03, -0.14), "head-on"], [Vector3(0.08, 0.05, -0.1), "front"], [Vector3(-0.08, 0.05, 0.1), "rear"], [Vector3(0.05, 0.02, -0.09), "head"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.005
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "bird":
		# <kind> as the second argument; third extra: "fly" for the flying bird, wings spread
		var BirdModels = load("res://scripts/bird_models.gd")
		var Fl = load("res://scripts/flight.gd")
		var b: Dictionary = BirdModels.make(_args[1])
		var flying := _args.size() > 3 and _args[3] == "fly"
		root.add_child(b["root"])
		var len: float = b["L"]
		if flying:
			(b["stand"] as Node3D).visible = false
			(b["fly"] as Node3D).visible = true
			for lg in b["legs"]:
				(lg[0] as Node3D).visible = false
			Fl.pose(b["wings"], 0.25, 0.1, 0.05, 0.0)
		else:
			(b["tilt"] as Node3D).position.y = b["hip"]
			(b["tilt"] as Node3D).rotation.x = b["upright"]
			(b["root"] as Node3D).position.y = -float(b["hip"])
		var r := len * (3.6 if flying else 2.4)
		_views = [[Vector3(r, r * 0.1, 0.0), "side"], [Vector3(0.001, r * 1.2, 0), "top"], [Vector3(0.001, -r * 1.2, 0), "below"], [Vector3(r * 0.6, r * 0.35, -r * 0.7), "front"], [Vector3(-r * 0.6, r * 0.3, r * 0.75), "rear"], [Vector3(r * 0.25, r * 0.08, -r * 0.6), "head"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.01
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "reef":
		# reef <name> <out.png> [four numbers: the instance's custom data, or what the animal's
		# shader takes: see below] [view distance]
		var RM = load("res://scripts/reef_models.gd")
		var what := _args[1]
		var nums: Array = []
		for k in range(3, _args.size()):
			nums.append(float(_args[k]))
		var mesh: Mesh
		var mat := ShaderMaterial.new()
		var custom := Color(0, 0, 0.5, 0.5)
		var r := 0.5
		var sc := 1.0
		var multi := true
		var col := Color(1, 1, 1)
		match what:
			"anemonefish0", "anemonefish1":
				mesh = RM.anemonefish()
				mat.shader = load("res://shaders/reef_fish.gdshader")
				custom = Color((1.0 if what.ends_with("1") else 0.0) / 255.0, 0.2, 0.6, 0.5)
				sc = 0.11 / 3.6
				r = 0.3
			"lionfish":
				mesh = RM.lionfish()
				mat.shader = load("res://shaders/reef_fish.gdshader")
				custom = Color(2.0 / 255.0, 0.2, 0.3, 0.5)
				sc = 0.3 / 3.6
				r = 0.95
			"carpet", "magnificent":
				mesh = RM.carpet_anemone() if what == "carpet" else RM.magnificent_anemone()
				mat.shader = load("res://shaders/anemone.gdshader")
				mat.set_shader_parameter("sway", 0.05 if what == "carpet" else 0.3)
				mat.set_shader_parameter("vivid_column", what != "carpet")
				col = Color(0.5, 0.52, 0.3) if what == "carpet" else Color(0.62, 0.55, 0.36)
				sc = 0.4 if what == "carpet" else 0.26
				r = 1.6
			"eel":
				mesh = RM.garden_eel()
				mat.shader = load("res://shaders/garden_eel.gdshader")
				custom = Color(1.0, 0.3, 0.9, 0.0)
				r = 0.75
			"den":
				mesh = RM.den_rock(3, true)
				var sh := Shader.new()
				sh.code = load("res://scripts/seabed.gd").CORAL_SHADER
				mat.shader = sh
				col = Color(0.55, 0.5, 0.42)
				r = 2.2
			"moray0", "moray1":
				multi = false
				mesh = RM.moray()
				mat.shader = load("res://shaders/moray.gdshader")
				mat.set_shader_parameter("species", 1 if what.ends_with("1") else 0)
				r = 1.5
			"octopus":
				multi = false
				mesh = RM.octopus()
				mat.shader = load("res://shaders/octopus.gdshader")
				r = 1.6
		if nums.size() >= 4:
			custom = Color(nums[0], nums[1], nums[2], nums[3])
		if nums.size() >= 5:
			r = nums[4]
		var arr := mesh.surface_get_arrays(0)
		print("vertices ", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " aabb ", mesh.get_aabb())
		if multi:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = 1
			var c := mesh.get_aabb().get_center() * sc
			mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * sc), -c))
			mm.set_instance_color(0, col)
			mm.set_instance_custom_data(0, custom)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.custom_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
			root.add_child(mmi)
		else:
			_mi = MeshInstance3D.new()
			_mi.mesh = mesh
			_mi.material_override = mat
			_mi.custom_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
			root.add_child(_mi)
			var names: Array = ["out_len", "turn", "lift", "gape"] if what.begins_with("moray") else ["curl", "droop", "tuck", "pale"]
			for k in mini(nums.size(), 4):
				_mi.set_instance_shader_parameter(names[k], nums[k])
			_mi.position = Vector3(0, -0.1, 0.2) if what.begins_with("moray") else Vector3(0, -0.05, 0)
		_views = [[Vector3(r, r * 0.1, 0.0), "side"], [Vector3(0.001, r * 1.15, 0), "top"], [Vector3(r * 0.5, r * 0.75, -r * 0.5), "from the surface"], [Vector3(r * 0.6, r * 0.35, -r * 0.7), "front"], [Vector3(-r * 0.6, r * 0.3, r * 0.75), "rear"], [Vector3(0.0, r * 0.1, -r), "head-on"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.01
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "land":
		# land <what> <out.png> [numbers]: the small things on land (scripts/land_models.gd):
		#   shell <kind 0-4>; hermit [shell kind, gait, stride, tuck, lift]; millipede [gait, moving];
		#   snail [out_k]; pitcher / orchid / vanilla [seed]
		var LM = load("res://scripts/land_models.gd")
		var what := _args[1]
		var nums: Array = []
		for k in range(3, _args.size()):
			nums.append(float(_args[k]))
		var r := 0.2
		var mid := Vector3.ZERO
		match what:
			"shell":
				var sh: Dictionary = LM.shell(int(nums[0]) if nums.size() > 0 else 0, 0.05)
				_mi = MeshInstance3D.new()
				_mi.mesh = sh["mesh"]
				_mi.material_override = LM.shell_material()
				root.add_child(_mi)
				mid = (_mi.mesh as Mesh).get_aabb().get_center()
				print("mouth ", sh["ap"], " r ", sh["r"], " aabb ", (_mi.mesh as Mesh).get_aabb())
				r = 0.2
			"hermit":
				var kind := int(nums[0]) if nums.size() > 0 else 0
				var hm := ShaderMaterial.new()
				hm.shader = load("res://shaders/hermit.gdshader")
				var h: Dictionary = LM.hermit_node(LM.hermit(), hm, LM.shell(kind, LM.shell_size_for(kind, 0.0155)), LM.shell_material())
				root.add_child(h["root"])
				var names := ["gait", "stride", "tuck", "lift"]
				for k in range(1, mini(nums.size(), 5)):
					(h["body"] as MeshInstance3D).set_instance_shader_parameter(names[k - 1], nums[k])
				(h["body"] as MeshInstance3D).set_instance_shader_parameter("tint", Color(0.5, 0.4, 0.3))
				mid = Vector3(0, 0.025, 0.01)
				r = 0.3
			"millipede":
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_custom_data = true
				mm.mesh = LM.millipede()
				var n := 40
				mm.instance_count = n
				for i in n:
					# (a gentle bend, to see the rings follow)
					var a := 0.9 * float(i) / n
					var p := Vector3(sin(a) * 0.14, 0, -0.1 + (1.0 - cos(a)) * 0.14 + float(i) * LM.M_PITCH * 0.55)
					p = Vector3(sin(a) * 0.25, 0, 0.25 - cos(a) * 0.25 + 0.0) + Vector3(-0.05, 0, -0.1)
					var sc := 1.0
					if i < 2:
						sc = 0.86 + 0.07 * i
					elif i > n - 5:
						sc = 0.62 + 0.095 * (n - 1 - i)
					mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -a).scaled(Vector3.ONE * sc), p))
					mm.set_instance_custom_data(i, Color((nums[0] if nums.size() > 0 else 0.0) - i * 0.7, nums[1] if nums.size() > 1 else 1.0, 1.0 if i == 0 else (2.0 if i == n - 1 else (3.0 if i == 1 else 0.0)), 0.0))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				var mat := ShaderMaterial.new()
				mat.shader = load("res://shaders/millipede.gdshader")
				mmi.material_override = mat
				root.add_child(mmi)
				print("ring vertices ", ((mm.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				mid = Vector3(0.0, 0.006, 0.0)
				r = 0.5
			"snail":
				var sm := ShaderMaterial.new()
				sm.shader = load("res://shaders/snail.gdshader")
				var s: Dictionary = LM.snail_node(LM.snail(), sm, LM.shell(4, 0.058), LM.shell_material())
				root.add_child(s["root"])
				(s["body"] as MeshInstance3D).set_instance_shader_parameter("out_k", nums[0] if nums.size() > 0 else 1.0)
				mid = Vector3(0, 0.02, 0.0)
				r = 0.28
			_:
				var pl: Dictionary = LM.call(what, int(nums[0]) if nums.size() > 0 else 1)
				_mi = MeshInstance3D.new()
				_mi.mesh = pl["mesh"]
				_mi.material_override = LM.plant_material()
				root.add_child(_mi)
				var bb: AABB = (_mi.mesh as Mesh).get_aabb()
				print("vertices ", ((_mi.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " aabb ", bb)
				mid = bb.get_center()
				r = bb.size.length() * 1.5
		for c in root.get_children():
			if c is Node3D and not (c is Camera3D) and not (c is DirectionalLight3D):
				(c as Node3D).position -= mid
		if OS.has_environment("PDIST"):
			r *= float(OS.get_environment("PDIST"))
		_views = [[Vector3(r, r * 0.12, 0.0), "side"], [Vector3(0.001, r * 1.1, 0), "top"], [Vector3(r * 0.6, r * 0.4, -r * 0.7), "front"], [Vector3(-r * 0.6, r * 0.35, r * 0.75), "rear"], [Vector3(0.0, r * 0.15, -r), "head-on"], [Vector3(-r, r * 0.12, 0.0), "other side"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.005
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "frog":
		_mi = MeshInstance3D.new()
		_mi.mesh = load("res://scripts/small_models.gd").frog()
		var fm := ShaderMaterial.new()
		var fs := Shader.new()
		fs.code = load("res://scripts/critters.gd").FROG_SHADER
		fm.shader = fs
		_mi.material_override = fm
		root.add_child(_mi)
		_mi.position = Vector3(0, -0.004, 0)
		_views = [[Vector3(0.045, 0.008, 0.0), "side"], [Vector3(0.0002, 0.05, 0), "top"], [Vector3(0.0, 0.01, -0.045), "head-on"], [Vector3(0.028, 0.02, -0.03), "front"], [Vector3(-0.028, 0.02, 0.032), "rear"], [Vector3(0.02, 0.008, -0.03), "head"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.002
		root.add_child(_cam)
		_cam.make_current()
		return
	if _args[0] == "crab":
		_mi = MeshInstance3D.new()
		_mi.mesh = load("res://scripts/small_models.gd").crab()
		var cm := ShaderMaterial.new()
		cm.shader = load("res://shaders/crab.gdshader")
		cm.set_shader_parameter("albedo", Color(0.45, 0.38, 0.28))
		_mi.material_override = cm
		root.add_child(_mi)
		_mi.position.y = -0.05
		for k in ["gait", "stride", "lift", "tuck"]:
			var i := ["gait", "stride", "lift", "tuck"].find(k) + 3
			_mi.set_instance_shader_parameter(k, float(_args[i]) if _args.size() > i else 0.0)
		_views = [[Vector3(0.0, 0.12, 0.7), "front"], [Vector3(0.001, 0.75, 0), "top"], [Vector3(0.7, 0.1, 0.0), "side"], [Vector3(0.45, 0.35, 0.5), "3/4"], [Vector3(-0.4, 0.3, -0.5), "rear"], [Vector3(0.3, 0.05, 0.6), "low"]]
		_cam = Camera3D.new()
		_cam.fov = 34
		_cam.near = 0.01
		root.add_child(_cam)
		_cam.make_current()
		print("aabb ", _mi.mesh.get_aabb())
		return
	_mi = MeshInstance3D.new()
	_mi.mesh = models.call(_args[0])
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sea_creature.gdshader")
	m.set_shader_parameter("species", int(_args[1]))
	_mi.material_override = m
	root.add_child(_mi)
	_mi.set_instance_shader_parameter("phase", float(_args[3]) if _args.size() > 3 else 0.0)
	_mi.set_instance_shader_parameter("amp", float(_args[4]) if _args.size() > 4 else 0.0)
	_mi.set_instance_shader_parameter("bend", float(_args[5]) if _args.size() > 5 else 0.0)
	_cam = Camera3D.new()
	_cam.fov = float(OS.get_environment("PFOV")) if OS.has_environment("PFOV") else 24.0
	root.add_child(_cam)
	_cam.make_current()
	var tris := 0
	var arr := _mi.mesh.surface_get_arrays(0)
	print("vertices ", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " aabb ", _mi.mesh.get_aabb())

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames > 240:
		return true   # (something went wrong: do not hang)
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= 0:
		_imgs.append(root.get_texture().get_image())
	_i += 1
	if _i >= _views.size():
		var w: int = (_imgs[0] as Image).get_width() / 2
		var h: int = (_imgs[0] as Image).get_height() / 2
		var sheet := Image.create(w * 3, h * 2, false, (_imgs[0] as Image).get_format())
		for k in _imgs.size():
			var im: Image = _imgs[k]
			im.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((k % 3) * w, (k / 3) * h))
		sheet.save_png(_args[2])
		return true
	_cam.global_position = _views[_i][0]
	var vp: Vector3 = _views[_i][0]
	_cam.look_at(Vector3.ZERO, Vector3.UP if absf(vp.y) < 6.0 and absf(vp.x) + absf(vp.z) > 0.02 else Vector3(0, 0, -1))
	_wait = 4
	return false
