extends CanvasLayer
## About, Licenses, the manual and Help. On macOS the items go into the real menu bar: "About
## Tropical Island" and under it "Licenses" (and a dividing line) in the application menu,
## "Manual" and "Keyboard Shortcuts" in the Help menu, in that order; H toggles
## the shortcut panel anywhere (the menu bar is hidden in fullscreen). Esc or a click outside
## closes a panel. Every word the player reads is in American English.
## "Licenses" shows the notices Godot's license and those of its third-party parts ask for
## (scripts/licenses.gd): a long text that scrolls (wheel, the bar, Page Up / Down).
## "Manual" opens the PDF field guide in the Mac's PDF reader. It lies inside the app, in
## Contents/Resources (tools/build_app.sh puts it there and signs the app again); run from the
## project, the one in manual/ is opened.
## Panels are laid out for a 1080-pixel-high viewport and scaled to the real one, so they keep the
## same share of the screen on any display (the game renders at full Retina / 6K resolution).

const APP_NAME := "Tropical Island"
const ICON := "res://icon.png"
const MANUAL := "Tropical Island - Manual.pdf"
const Licenses := preload("res://scripts/licenses.gd")
const SHORTCUTS := [
	["W A S D  /  arrow keys", "walk"],
	["Shift", "jog"],
	["Space", "hop;  while swimming: dive on one breath (45 s, 4.5 m)"],
	["C  (hold)", "crouch"],
	["In deep water", "you swim; look down and your face goes under: the snorkeler's view"],
	["Mouse", "look around (click to capture the mouse)"],
	["Esc", "release the mouse / close this panel"],
	["T", "time of day: by your clock, midday, afternoon, golden hour, sunset, night"],
	["N", "call a rain shower (one comes by itself too, rarely); again: let it pass"],
	["G", "the tide: high water, half tide, low water, by the moon (as it starts)"],
	["M", "the moon: full, half, crescent, new, by the date (as it starts)"],
	["B", "the sea's glow at night: call it, or send it away (by itself: about one night in three)"],
	["F", "free camera  (E / Space up,  C / Ctrl down,  Shift faster)"],
	["R", "unstuck: back to the last firm ground you stood on"],
	["P", "photo (saved to your Pictures folder)"],
	["⌃ ⌘ F  /  ⌥ Enter", "fullscreen"],
	["H", "show / hide this help"],
	["⌘ Q", "quit"],
]

var _panel: Control
var _box: Control
var _which := ""
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE   # what the mouse did when a panel opened
var _build := {}


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open("res://build_info.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_build = d
	_setup_native_menus()
	get_viewport().size_changed.connect(_fit)
	# (for a check of the built app, whose menu bar no script may click:
	# "Tropical Island" --quit-after 60 -- --menus-report --open-manual)
	if "--menus-report" in OS.get_cmdline_user_args():
		printerr("menus: ", menu_items(), "  manual: ", manual_path())   # (the built app prints nothing to stdout)
	if "--open-manual" in OS.get_cmdline_user_args():
		_on_manual()


func _setup_native_menus() -> void:
	if not NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		return
	# macOS already has "About Tropical Island" in the application menu; it sends
	# NOTIFICATION_WM_ABOUT (handled in _notification), so no second item is added.
	# What is added to the application menu lands below "About ..." (and a dividing line).
	var app := NativeMenu.get_system_menu(NativeMenu.APPLICATION_MENU_ID)
	if app.is_valid():
		NativeMenu.add_item(app, "Licenses", _on_menu.bind("licenses"))
		NativeMenu.add_separator(app)   # (the usual line above "Services")
	var help := NativeMenu.get_system_menu(NativeMenu.HELP_MENU_ID)
	if help.is_valid():
		if manual_path() != "":
			NativeMenu.add_item(help, "Manual", _on_manual)
		NativeMenu.add_item(help, "Keyboard Shortcuts", _on_menu.bind("help"), Callable(), null, KEY_MASK_META | KEY_SLASH)


## Is a panel open? (scripts/player.gd asks: a click in a panel must not take the mouse back)
func is_open() -> bool:
	return _panel != null


## For the tests: what was added to the application menu and to the Help menu, in order.
func menu_items() -> Dictionary:
	var out := {}
	if NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		for pair: Array in [["application", NativeMenu.APPLICATION_MENU_ID], ["help", NativeMenu.HELP_MENU_ID]]:
			var menu := NativeMenu.get_system_menu(pair[1])
			var items := []
			for i in NativeMenu.get_item_count(menu):
				items.append(NativeMenu.get_item_text(menu, i))
			out[pair[0]] = items
	return out


## Where the manual lies: inside the app (Contents/Resources, beside the game's data), or,
## run from the project, in manual/. "" when there is none (then the menu has no entry).
func manual_path() -> String:
	var in_app := OS.get_executable_path().get_base_dir().path_join("../Resources").path_join(MANUAL).simplify_path()
	for p: String in [in_app, ProjectSettings.globalize_path("res://manual/" + MANUAL)]:
		if FileAccess.file_exists(p):
			return p
	return ""


func _on_manual(_tag: Variant = null) -> void:
	var p := manual_path()
	if p == "" or OS.shell_open(p) != OK:
		push_warning("the manual could not be opened: " + p)


func _on_menu(_tag: Variant, which: String) -> void:
	_show(which)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_ABOUT:
		_show.call_deferred("about")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		# (a click outside closes; the wheel does not: the licenses scroll)
		if _panel and event is InputEventMouseButton and event.pressed and event.button_index <= MOUSE_BUTTON_MIDDLE:
			var r: Rect2 = _box.get_global_transform() * Rect2(Vector2.ZERO, _box.size)
			if not r.has_point(event.position):
				_close()
				get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_H and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed):
		if _which == "help":
			_close()
		else:
			_show("help")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _panel:
		_close()
		get_viewport().set_input_as_handled()


func _close(give_back := true) -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
		_box = null
		# (the mouse goes back to looking around, if that is what it was doing)
		if give_back:
			Input.mouse_mode = _mouse_before
	_which = ""


# ------------------------------------------------------------------ panels
func _show(which: String) -> void:
	if _panel == null:
		_mouse_before = Input.mouse_mode
	_close(false)
	_which = which
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.06, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var box := PanelContainer.new()
	box.name = "Box"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.11, 0.15, 0.92)
	sb.border_color = Color(0.45, 0.85, 0.85, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(34)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 24
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var content: Control
	match which:
		"about": content = _about_content()
		"licenses": content = _licenses_content()
		_: content = _help_content()
	box.add_child(content)
	add_child(root)
	_panel = root
	_box = box
	_fit()
	if which == "licenses":
		(content.get_node("Text") as Control).grab_focus()   # Page Up / Down, Home, End


## Scales the open panel so it covers the same share of the screen as on a 1080p display.
func _fit() -> void:
	if not _panel:
		return
	var vp := get_viewport().get_visible_rect().size
	var s: float = maxf(1.0, vp.y / 1080.0)
	_panel.scale = Vector2(s, s)
	_panel.position = Vector2.ZERO
	_panel.size = vp / s


func _label(text: String, size: int, color := Color(1, 1, 1, 0.92), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _about_content() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(560, 0)
	if ResourceLoader.exists(ICON):
		var tr := TextureRect.new()
		tr.texture = load(ICON)
		tr.custom_minimum_size = Vector2(200, 200)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(tr)
	v.add_child(_label(APP_NAME, 42))
	v.add_child(_label("A walk on a granite island in the Indian Ocean", 22, Color(0.75, 0.9, 0.9, 0.85)))
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 16)
	v.add_child(sep)
	var generated: String = _build.get("generated", "2026-11-08")
	v.add_child(_label("Version %s  ·  generated %s" % [_build.get("version", "1.0"), generated], 22))
	# (the credits, word for word as agreed on 2026-11-12)
	v.add_child(_label("Idea and direction by Hanno Teeling.", 23, Color(1.0, 0.86, 0.6, 0.95)))
	v.add_child(_label("Concept extension and initial implementation by Claude Opus 5.5.", 23, Color(1.0, 0.86, 0.6, 0.95)))
	v.add_child(_label("Further substantial extension and refinement by Claude Fable 5.2.", 23, Color(1.0, 0.86, 0.6, 0.95)))
	# (the license's line: under the credits, above "Built with Godot")
	v.add_child(_label("Application licensed under CC BY-NC-SA 4.0", 19, Color(1, 1, 1, 0.6)))
	v.add_child(_label("Built with Godot %s" % Engine.get_version_info()["string"].get_slice(" ", 0), 19, Color(1, 1, 1, 0.6)))
	v.add_child(_label("Models scripted in Blender and in code · textures by Z Image Turbo · sounds by Stable Audio 3", 17, Color(1, 1, 1, 0.55)))
	v.add_child(_label("Esc or click outside to close", 16, Color(1, 1, 1, 0.45)))
	return v


func _help_content() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_label("Keyboard Shortcuts", 36))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 7)
	for s in SHORTCUTS:
		grid.add_child(_label(s[0], 23, Color(1.0, 0.86, 0.6, 0.95), HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_label(s[1], 23, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(grid)
	v.add_child(_label("Bushes are not solid: push through them.  The manual, a field guide to the island, is in the Help menu.", 18, Color(1, 1, 1, 0.6)))
	v.add_child(_label("H, Esc or click outside to close", 16, Color(1, 1, 1, 0.45)))
	return v


## The license notices (Godot, its third-party parts, the addon): headings in the panel's
## amber, the texts as they are, in a field that scrolls.
func _licenses_content() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_label("Licenses", 36))
	var t := RichTextLabel.new()
	t.name = "Text"
	t.custom_minimum_size = Vector2(800, 540)
	t.bbcode_enabled = false
	t.scroll_active = true
	t.focus_mode = Control.FOCUS_ALL
	t.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	t.add_theme_font_size_override("normal_font_size", 17)
	t.add_theme_color_override("default_color", Color(1, 1, 1, 0.86))
	var first := true
	for s: Array in Licenses.sections():
		if not first:
			t.add_text("\n\n\n")
		first = false
		t.push_font_size(24)
		t.push_color(Color(1.0, 0.86, 0.6, 0.95))
		t.add_text(s[0])
		t.pop()
		t.pop()
		t.add_text("\n\n" + (s[1] as String))
	v.add_child(t)
	v.add_child(_label("Scroll to read on  ·  Esc or click outside to close", 16, Color(1, 1, 1, 0.45)))
	return v
