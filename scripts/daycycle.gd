extends Node
## The time of day: by the computer's clock (the default: the island's day is the player's
## day, sunrise about 6:20, sunset about 18:20, as near the equator all the year), or one of
## the presets (T cycles: by the clock, midday, afternoon, golden hour, sunset, night), with
## smooth transitions, plus a small on-screen hint. Drives the sun light, sky shader, fog, exposure and the
## sun direction uniform used by the sand glints.

@export var sun_path: NodePath = ^"../Sun"
@export var env_path: NodePath = ^"../WorldEnvironment"
@export var transition_time := 5.0

# elevation / azimuth in degrees; azimuth 0 = toward -z, 90 = toward +x (the start beach's
# sea). The sun sets over that sea, so +x is WEST and -z SOUTH (+z north, -x east): this
# "azimuth" runs from south over west, a compass bearing plus 180 degrees. (Until 2026-11-12
# the comments called -z north and +x east.) By the clock the sun goes the way it goes over
# the Seychelles on the day's date (sky_at(), below). T's looks: "Midday" keeps the sun it
# has here (in the south-east, 52 degrees up: a mid-morning sun of December, and the one the
# grotto's roof gap looks at); the others keep their height and take their bearing from the
# day's true path (set_preset()).
var presets := [
	{"name": "Midday", "elev": 52.0, "azim": -55.0, "sun": Color(1.0, 0.95, 0.86), "energy": 2.4,
	 "zenith": Color(0.10, 0.27, 0.62), "mid": Color(0.30, 0.55, 0.88), "horizon": Color(0.72, 0.84, 0.95),
	 "fog": Color(0.72, 0.83, 0.94), "ambient": 1.0, "exposure": 1.0, "glow": 0.45, "night": 0.0, "cirrus": 0.55, "cumulus": 0.42},
	{"name": "Afternoon", "elev": 28.0, "azim": 70.0, "sun": Color(1.0, 0.9, 0.76), "energy": 2.3,
	 "zenith": Color(0.12, 0.28, 0.6), "mid": Color(0.34, 0.56, 0.86), "horizon": Color(0.78, 0.84, 0.9),
	 "fog": Color(0.76, 0.82, 0.9), "ambient": 0.95, "exposure": 1.0, "glow": 0.5, "night": 0.0, "cirrus": 0.55, "cumulus": 0.42},
	{"name": "Golden hour", "elev": 11.0, "azim": 95.0, "sun": Color(1.0, 0.72, 0.42), "energy": 2.0,
	 "zenith": Color(0.13, 0.24, 0.5), "mid": Color(0.42, 0.5, 0.7), "horizon": Color(1.0, 0.76, 0.52),
	 "fog": Color(0.95, 0.78, 0.6), "ambient": 0.75, "exposure": 1.15, "glow": 0.7, "night": 0.0, "cirrus": 0.55, "cumulus": 0.42},
	{"name": "Sunset", "elev": 2.5, "azim": 100.0, "sun": Color(1.0, 0.48, 0.24), "energy": 1.6,
	 "zenith": Color(0.1, 0.14, 0.34), "mid": Color(0.45, 0.36, 0.52), "horizon": Color(1.0, 0.55, 0.3),
	 "fog": Color(0.9, 0.55, 0.38), "ambient": 0.5, "exposure": 1.35, "glow": 0.9, "night": 0.0, "cirrus": 0.55, "cumulus": 0.42},
	# moonlit night. "elev" and "azim" are the sun's, as in the others: it has gone down where
	# it set and stands far below the horizon. The moon is another body with a place of its
	# own; the one directional light is the sun while the sun is up and the moon when
	# the night has come, and dark in between
	{"name": "Night", "elev": -30.0, "azim": 100.0, "sun": Color(0.62, 0.73, 1.0), "energy": 0.32,
	 "zenith": Color(0.006, 0.012, 0.035), "mid": Color(0.014, 0.026, 0.065), "horizon": Color(0.04, 0.065, 0.12),
	 "fog": Color(0.025, 0.04, 0.075), "ambient": 0.35, "exposure": 1.9, "glow": 0.85, "night": 1.0, "cirrus": 0.3, "cumulus": 0.22},
]

## The moon: over the sea, to the left of where the sun went down.

## By the clock the sky is that of the island's true place on the day's date: LATITUDE
## degrees north (the granitic Seychelles lie 4.6 degrees south of the equator), the sun
## highest at NOON (hours). It comes up in the east behind the island and goes down in the
## west over the start beach's sea: due east and west at the equinoxes, up to 23.5 degrees
## to the south of them in December and to the north in June; at noon it stands a little
## north of overhead at the equinoxes, 19 degrees south of it in December, 28 north in June.
## Day and night are nearly equal all year (the day is a quarter of an hour longer in
## December than in June). The moon and the stars turn about the same axis, which points
## 4.6 degrees above the southern horizon.
## (Until 2026-11-12 the sun went a path of its own: 10 degrees south of overhead at noon,
## setting 10 degrees north of west, the same every day: the sky of a place 10 degrees
## north of the equator. Not in it, and planned for a later stage (HANDOFF.md, "Work list"):
## the equation of time (noon by the sun wanders a quarter of an hour through the year), the
## moon's own orbit (five degrees off the sun's road), the stars by the season and real
## constellations: the stars are a painted sky that turns about the true axis.)
const NOON := 12.35
const LATITUDE := -4.6
const OBLIQUITY := 23.44
var sun_unix := -1.0            # (for the tests: a moment to take for today, in Unix seconds; below 0: now)
## The presets by the height of the sun (degrees): the look of the hour is mixed from the two
## the sun stands between. The morning takes the evening's looks in reverse.
const LADDER := [[-10.0, 4], [2.5, 3], [11.0, 2], [28.0, 1], [48.0, 0]]
## The moon's phase: by the date of the computer (the default), or set by hand (M cycles).
## It goes the sun's way across the sky, later than the sun by its phase (a full moon rises
## as the sun sets, a waxing crescent follows the sun down in the evening, a new moon is
## not in the night sky at all); the stars turn with the hours. With a preset of T the hour
## is taken as PRESET_HOURS says.
const PRESET_HOURS := [12.35, 15.9, 17.6, 18.2, 20.4]
var moon_elev := 0.0            # where the moon stands now (degrees above the horizon)
var shown_hour := -1.0          # the hour of the day the sky shows now (the clock's, or a preset's)
const SYNODIC := 2551442.9          # seconds from new moon to new moon (29.530589 days)
const NEW_MOON := 947182440.0       # a new moon: 6 January 2000, 18:14 UTC
const MOON_STATES := [["Moon by the date", NAN], ["Full moon", 0.5], ["Half moon", 0.25], ["Crescent moon", 0.1], ["New moon", 0.0]]
var moon_state := 0
## (for the tests) a time to take for the date's, in Unix seconds; below 0: now
var moon_unix := -1.0
var by_clock := true
## (for the tests) an hour to take for the clock's, 0 .. 24; below 0: the real one
var clock_hour := -1.0
var _clock_t := 0.0

## 0 = day .. 1 = night; read by the ambience, fauna and footprints
var night := 0.0
## how strongly the sun plays under water (1 at midday .. 0): shafts, caustics, the seagrass's bubbles
var sea_sun := 1.0
## where the sun really is (the light may be the moon's): the rainbow asks
var to_sun := Vector3.UP
var sun_elev := 52.0
var sun_light := Color(1, 1, 1)     # its color times its strength (1 at midday)
## a rain shower (scripts/weather.gd sets these): the cloud over the sky, 0 .. 1, and how
## thick the rain hangs in the air
var overcast := 0.0
var haze := 0.0
var _weather_applied := Vector2(-1, -1)
var _idx := 0
var _from := {}
var _to := {}
var _t := 1.0
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _label: Label
var _hint: Label
var _hint_time := 0.0
var _sand_mat: ShaderMaterial


func _ready() -> void:
	_sun = get_node_or_null(sun_path)
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we:
		_env = we.environment
		_sky_mat = _env.sky.sky_material as ShaderMaterial
		# (the clouds go with the island's wind, in off the sea: flight.gd `WIND_DIR`
		# (-0.97, 0, 0.24); see sky.gdshader for the vector's odd sense. The scene file
		# still holds the old (0.8, 0.35), which was the other way for the rain cloud.)
		if _sky_mat:
			_sky_mat.set_shader_parameter("wind_dir", Vector2(0.97, 0.24))
	var world := get_parent()
	if world.has_method("get_material"):
		_sand_mat = world.get_material("Sand")
	if not InputMap.has_action("time_of_day"):
		InputMap.add_action("time_of_day")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_T
		InputMap.action_add_event("time_of_day", e)
	_build_ui()
	for i in presets.size():
		presets[i]["hour"] = PRESET_HOURS[i]
	_from = presets[0].duplicate()
	_to = presets[0].duplicate()
	if by_clock:
		_idx = -1
		_to = clock_look(hour_now())
		_from = _to.duplicate()
		_label.text = "%s, by the clock" % _to["name"]
		_label_time = 0.0
		_label_hold = 7.0         # (said for a few seconds longer than a change is)
	_glow_want = glow_wanted()
	glow = 1.0 if _glow_want else 0.0
	_first_apply.call_deferred()


## (deferred from _ready: whatever has been chosen by then, the clock's hour or a preset)
func _first_apply() -> void:
	_apply(_current())


## The moon's phase now: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
func moon_phase() -> float:
	var set_p: float = MOON_STATES[moon_state][1]
	if not is_nan(set_p):
		return set_p
	var now := moon_unix if moon_unix >= 0.0 else Time.get_unix_time_from_system()
	return fposmod((now - NEW_MOON) / SYNODIC, 1.0)


## How much of the moon's disc is lit, 0 .. 1.
func moon_lit() -> float:
	return 0.5 - 0.5 * cos(moon_phase() * TAU)


static func moon_name(p: float) -> String:
	var names := ["new moon", "waxing crescent", "first quarter", "waxing gibbous", "full moon", "waning gibbous", "last quarter", "waning crescent"]
	return names[int(floor(fposmod(p + 0.0625, 1.0) * 8.0)) % 8]


## The hour T's night preset is taken to be: the hour of this night at which the moon, in
## its phase, stands best: over the sea in the west with its path on the water, or failing
## that (a waning moon) over the island in the east; with no moon in the night sky, midnight.
func night_hour() -> float:
	var p := moon_phase()
	for at: float in [17.1, 7.6]:
		var h := fposmod(at + p * 24.0, 24.0)
		if sun_at(h).x < -12.0:
			return h
	return 0.35


func set_moon(state: int) -> void:
	moon_state = posmod(state, MOON_STATES.size())
	if not by_clock and _idx == presets.size() - 1:
		_to["hour"] = night_hour()
	var text: String = MOON_STATES[moon_state][0]
	if moon_state == 0:
		text += ": %s" % moon_name(moon_phase())
	show_message(text)
	_apply(_current())


## The hour of the day the sky shows: the clock's, or the hour of the preset chosen with T
## (the tide goes by it: scripts/tide.gd).
func sky_hour() -> float:
	return shown_hour if shown_hour >= 0.0 else hour_now()


## The hour by the computer's clock (or the tests'), 0 .. 24.
func hour_now() -> float:
	if clock_hour >= 0.0:
		return fposmod(clock_hour, 24.0)
	var t := Time.get_time_dict_from_system()
	return float(t["hour"]) + float(t["minute"]) / 60.0 + float(t["second"]) / 3600.0


## How far along its yearly road the sun is (its ecliptic longitude, radians: 0 at the
## March equinox, a quarter turn at the June solstice), by the date. The almanac's short
## formula: good to a hundredth of a degree for a century either side of 2000.
func sun_longitude() -> float:
	var unix := sun_unix if sun_unix >= 0.0 else Time.get_unix_time_from_system()
	var days := (unix - 946728000.0) / 86400.0          # since 1 January 2000, 12:00 UTC
	var g := deg_to_rad(fposmod(357.528 + 0.9856003 * days, 360.0))
	return deg_to_rad(fposmod(280.46 + 0.9856474 * days + 1.915 * sin(g) + 0.02 * sin(2.0 * g), 360.0))


## The sun's declination today, degrees: how far north (+) or south (-) of the sky's
## equator it stands (-23.4 at the December solstice, 0 at the equinoxes, +23.4 in June).
func sun_decl() -> float:
	return rad_to_deg(asin(sin(deg_to_rad(OBLIQUITY)) * sin(sun_longitude())))


## The moon's: it goes the sun's road, ahead of the sun by its phase (a full moon stands
## where the sun will stand in half a year: high in the north in December).
func moon_decl() -> float:
	return rad_to_deg(asin(sin(deg_to_rad(OBLIQUITY)) * sin(sun_longitude() + moon_phase() * TAU)))


## Where a body of declination `decl` (degrees) stands in the island's sky when the hour by
## it is `hour` (it stands highest at NOON): Vector2(elevation, azimuth), degrees; the
## azimuth as everywhere here (0 toward -z, the south; 90 toward +x, the west).
func sky_at(hour: float, decl: float) -> Vector2:
	var h := deg_to_rad((hour - NOON) * 15.0)
	var lat := deg_to_rad(LATITUDE)
	var dc := deg_to_rad(decl)
	var up := sin(lat) * sin(dc) + cos(lat) * cos(dc) * cos(h)
	var north := cos(lat) * sin(dc) - sin(lat) * cos(dc) * cos(h)
	var west := cos(dc) * sin(h)
	return Vector2(rad_to_deg(asin(clampf(up, -1.0, 1.0))), rad_to_deg(atan2(west, -north)))


## Where the sun stands at an hour of the clock, today: Vector2(elevation, azimuth), degrees.
func sun_at(hour: float) -> Vector2:
	return sky_at(hour, sun_decl())


## Where the moon stands at an hour of the clock: on its own height, behind the sun by its phase.
func moon_at(hour: float) -> Vector2:
	return sky_at(hour - moon_phase() * 24.0, moon_decl())


## The hour of the afternoon at which today's sun stands `elev` degrees high.
func hour_of_elev(elev: float) -> float:
	var lat := deg_to_rad(LATITUDE)
	var dc := deg_to_rad(sun_decl())
	var c := (sin(deg_to_rad(elev)) - sin(lat) * sin(dc)) / (cos(lat) * cos(dc))
	return NOON + rad_to_deg(acos(clampf(c, -1.0, 1.0))) / 15.0


## One of T's looks as it is today: "Midday" as it stands in `presets`; the others with
## their sun at its height, on the day's true path (its bearing and its hour from that).
func preset_today(i: int) -> Dictionary:
	var d: Dictionary = presets[i].duplicate()
	if i > 0:
		var h := hour_of_elev(float(d["elev"]))
		d["azim"] = sun_at(h).y
		d["hour"] = h
	return d


## What the hour looks like: the presets mixed by the height of the sun, with the sun where
## the clock puts it.
func clock_look(hour: float) -> Dictionary:
	var s := sun_at(hour)
	var el := s.x
	var d: Dictionary = presets[4].duplicate()
	if el >= float(LADDER[LADDER.size() - 1][0]):
		d = presets[0].duplicate()
	elif el > float(LADDER[0][0]):
		for k in LADDER.size() - 1:
			var lo: float = LADDER[k][0]
			var hi: float = LADDER[k + 1][0]
			if el >= lo and el < hi:
				d = _mix(presets[int(LADDER[k][1])], presets[int(LADDER[k + 1][1])], (el - lo) / (hi - lo))
	d["elev"] = el
	d["azim"] = s.y
	d["hour"] = hour
	var morning := fposmod(hour - NOON, 24.0) > 12.0
	var name_ := "Night"
	if el > 55.0:
		name_ = "Midday"
	elif el > 20.0:
		name_ = "Morning" if morning else "Afternoon"
	elif el > 6.0:
		name_ = "Early morning" if morning else "Golden hour"
	elif el > -6.0:
		name_ = "Sunrise" if morning else "Sunset"
	d["name"] = name_
	return d


## Back to the time of day by the clock.
func set_clock(instant := false) -> void:
	_from = _current()
	by_clock = true
	_idx = -1
	_to = clock_look(hour_now())
	_t = 1.0 if instant else 0.0
	_label.text = "%s, by the clock" % _to["name"]
	_label_time = 0.0
	if instant:
		_from = _to.duplicate()
		_apply(_to)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.text = "WASD  walk     Shift  jog     Space  hop / dive     C  crouch     Mouse  look\nT  time of day     F  free camera     R  unstuck     P  photo     ⌃⌘F  fullscreen     H  help     Esc  release mouse"
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -84
	_hint.offset_bottom = -30
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_hint)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.0))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.offset_top = 40
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_label)
	_hint_time = 0.0
	get_viewport().size_changed.connect(_scale_ui)
	_scale_ui()


## Keeps the on-screen text the same share of the screen as on a 1080p display (6K / Retina).
func _scale_ui() -> void:
	var s: float = maxf(1.0, get_viewport().get_visible_rect().size.y / 1080.0)
	_hint.add_theme_font_size_override("font_size", roundi(18 * s))
	_hint.offset_top = -84 * s
	_hint.offset_bottom = -30 * s
	_label.add_theme_font_size_override("font_size", roundi(30 * s))
	_label.offset_top = 40 * s
	for l: Label in [_hint, _label]:
		l.add_theme_constant_override("shadow_offset_x", maxi(1, roundi(s * (1 if l == _hint else 2))))
		l.add_theme_constant_override("shadow_offset_y", maxi(1, roundi(s * (1 if l == _hint else 2))))


# ------------------------------------------------------------------ the sea's glow
## The glow of the sea at night (Noctiluca: in the surf, in a wader's wake, on the sand the
## swash has just left, in wet footprints) is not there every night: a bloom comes and goes.
## Here it comes on one night in three, by the date as the moon's phase is (until
## 2026-11-12 it was there every night): the night that begins on a date has its answer
## from that noon to the next, and the nights are not counted off in threes: two glowing
## nights can follow each other, and four dark ones. B calls the glow for the night that
## is, or sends it away, as N does with the rain; the next night decides for itself again.
const GLOW_SHARE := 3
var glow := 0.0               # 0 .. 1: how much of it there is now (it comes and goes over some seconds)
var glow_unix := -1.0         # (for the tests: a moment to take for now, in Unix seconds; below 0: now)
var _glow_choice := -1        # -1: as the night has it; 0 sent away, 1 called with B ...
var _glow_choice_night := -1  # ... for this night only
var _glow_t := 0.0
var _glow_want := false


## The number of the night that is, or is to come: it changes at noon by the computer's clock.
func glow_night(unix := -1.0) -> int:
	if unix < 0.0:
		unix = glow_unix if glow_unix >= 0.0 else Time.get_unix_time_from_system()
	var bias: float = float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	return int(floor((unix + bias - 43200.0) / 86400.0))


## Does the sea glow by itself on night number `id`?
static func glow_by_night(id: int) -> bool:
	var h := (id * 2654435761) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 2246822519) & 0xFFFFFFFF
	h ^= h >> 13
	return h % GLOW_SHARE == 0


## Is the glow there tonight: as the night has it, or as B has said for this night?
func glow_wanted() -> bool:
	var id := glow_night()
	if _glow_choice >= 0 and _glow_choice_night == id:
		return _glow_choice == 1
	return glow_by_night(id)


## B: the glow called, or sent away, for this night.
func toggle_glow() -> void:
	var on := not glow_wanted()
	_glow_choice = 1 if on else 0
	_glow_choice_night = glow_night()
	_glow_t = 0.0
	if on:
		show_message("The sea glows tonight" if night > 0.5 else "The sea will glow tonight")
	else:
		show_message("No glow in the sea tonight")


func _glow_step(delta: float) -> void:
	_glow_t -= delta
	if _glow_t <= 0.0:
		_glow_t = 2.0
		_glow_want = glow_wanted()
	var target := 1.0 if _glow_want else 0.0
	if glow != target:
		glow = move_toward(glow, target, delta / 5.0)
		_apply_glow()


func _apply_glow() -> void:
	var k := smoothstep(0.6, 1.0, night) * glow
	if get_parent().has_method("get_material"):
		var om: ShaderMaterial = get_parent().get_material("Ocean")
		if om:
			om.set_shader_parameter("biolum", k)
	if _sand_mat:
		_sand_mat.set_shader_parameter("biolum", k)


## For the tests: tonight, and which of the next thirty nights glow by themselves.
func glow_report() -> Dictionary:
	var id := glow_night()
	var days: Array = []
	for k in 30:
		if glow_by_night(id + k):
			days.append(Time.get_date_string_from_unix_time((id + k) * 86400 + 43200))
	return {"tonight by itself": glow_by_night(id), "tonight": glow_wanted(), "glow now": snappedf(glow, 0.01), "night": snappedf(night, 0.01),
		"B has said": ["nothing", "no glow", "glow"][_glow_choice + 1] if _glow_choice_night == id else "nothing",
		"glowing nights of the next thirty (the date the night begins on)": days}


func _unhandled_input(event: InputEvent) -> void:
	# (with ⌘ held a key belongs to the system: ⌘M minimizes the window and must not
	# turn the moon on as well. Ctrl stays free: it is "down" for the free camera)
	if event is InputEventKey and event.meta_pressed:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		set_moon(moon_state + 1)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		toggle_glow()
	if event.is_action_pressed("time_of_day"):
		# by the clock, then the presets in turn, then the clock again
		if _idx >= presets.size() - 1:
			set_clock()
		else:
			set_preset(_idx + 1)


func set_preset(i: int, instant := false) -> void:
	_from = _current()
	by_clock = false
	_idx = i
	_to = preset_today(i)
	if i == presets.size() - 1:
		_to["hour"] = night_hour()
	_t = 1.0 if instant else 0.0
	_label.text = presets[i]["name"]
	_label_time = 0.0
	if instant:
		_apply(_to)


var _label_time := 99.0
var _label_hold := 2.0


func show_message(text: String) -> void:
	_label.text = text
	_label_time = 0.0


func _current() -> Dictionary:
	return _mix(_from, _to, _ease(_t))


func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var d := {}
	for key in b:
		if key == "name":
			continue
		if b[key] is Color:
			d[key] = (a[key] as Color).lerp(b[key], k)
		elif key == "azim":
			d[key] = rad_to_deg(lerp_angle(deg_to_rad(a[key]), deg_to_rad(b[key]), k))
		elif key == "hour":
			# (the short way around the clock: from 23 h to 1 h is two hours, not twenty-two back.
			# The moon and the stars swung through most of a turn on such a change.)
			d[key] = fposmod(float(a[key]) + wrapf(float(b[key]) - float(a[key]), -12.0, 12.0) * k, 24.0)
		else:
			d[key] = lerpf(a[key], b[key], k)
	return d


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _process(delta: float) -> void:
	_hint_time += delta
	_hint.modulate.a = clampf(1.0 - (_hint_time - 9.0) / 2.0, 0.0, 1.0)
	_glow_step(delta)
	_label_time += delta
	var la := clampf(1.0 - (_label_time - _label_hold) / 1.0, 0.0, 1.0) * clampf(_label_time * 3.0, 0.0, 1.0)
	if _label_time > _label_hold + 1.0:
		_label_hold = 2.0
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92 * la))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4 * la))
	if by_clock:
		# the sun moves a quarter of a degree a minute: looked up every two seconds
		_clock_t -= delta
		if _t < 1.0 or _clock_t <= 0.0:
			_to = clock_look(hour_now())
			if _t >= 1.0:
				_clock_t = 2.0
				_from = _to
				_apply(_to)
	if _t < 1.0:
		_t = minf(1.0, _t + delta / transition_time)
		_apply(_current())
	elif absf(overcast - _weather_applied.x) > 0.0004 or absf(haze - _weather_applied.y) > 0.002:
		# (a shower is passing: the light follows the cloud)
		_apply(_current())


func _apply(d: Dictionary) -> void:
	var el := deg_to_rad(d["elev"])
	var az := deg_to_rad(d["azim"])
	# direction toward the sun
	to_sun = Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()
	sun_elev = float(d["elev"])
	sun_light = Color(d["sun"]) * (float(d["energy"]) / 2.4)
	# the moon: on the sun's way, behind it by its phase
	var hour: float = d.get("hour", 12.35)
	shown_hour = fposmod(hour, 24.0)
	var ms := moon_at(hour)
	moon_elev = ms.x
	var mel := deg_to_rad(ms.x)
	var maz := deg_to_rad(ms.y)
	var to_moon := Vector3(sin(maz) * cos(mel), sin(mel), -cos(maz) * cos(mel)).normalized()
	# whose light it is: the sun's until it has gone under, the moon's once it is night
	var night_p: Dictionary = presets[presets.size() - 1]
	var sun_f := smoothstep(-5.0, 1.5, sun_elev)
	var moon_f := smoothstep(0.7, 1.0, float(d["night"]))
	# (the moon's light goes with its phase: at new moon a third of the full moon's is left,
	# the light of the stars: the island must stay walkable)
	# (and only while it is up: with the moon down the night has the stars' light alone,
	# which comes from all the sky: a faint light from high up)
	var mlit := moon_lit() * smoothstep(-2.0, 7.0, moon_elev)
	var moon_e: float = float(night_p["energy"]) * lerpf(0.3, 1.0, mlit)
	var by_moon := moon_f * moon_e > sun_f * float(d["energy"])
	var moon_dir := Vector3(0.25, 0.94, 0.2).normalized().slerp(Vector3(to_moon.x, maxf(to_moon.y, 0.14), to_moon.z).normalized(), smoothstep(0.02, 0.2, mlit))
	var to_light := moon_dir if by_moon else Vector3(to_sun.x, maxf(to_sun.y, -0.03), to_sun.z).normalized()
	var light_col: Color = night_p["sun"] if by_moon else d["sun"]
	var light_energy: float = moon_e * moon_f if by_moon else float(d["energy"]) * sun_f
	# under a shower's cloud: little direct light and a grayer one, a gray sky and distance
	var o := overcast
	_weather_applied = Vector2(overcast, haze)
	# (the moon behind the cloud leaves no path on the sea)
	var dim := lerpf(1.0, lerpf(0.13, 0.02, float(d["night"])), o)
	var dark := lerpf(1.0, 0.06, float(d["night"]))
	if _sun:
		_sun.global_transform.basis = Basis.looking_at(-to_light, Vector3.UP if absf(to_light.y) < 0.99 else Vector3.FORWARD)
		_sun.light_color = light_col.lerp(Color(0.86, 0.9, 0.95), o * 0.7)
		_sun.light_energy = light_energy * dim
		# (no glitter path on the sea from a sun or moon behind the cloud: on so smooth a
		# surface even a fiftieth of the light still dazzles)
		# (nor from a sun that has gone under: its last light still comes over the horizon)
		# (a thin moon lays no path on the sea)
		_sun.light_specular = (1.0 - o) * (smoothstep(0.15, 0.6, mlit) if by_moon else smoothstep(-1.2, 0.8, sun_elev))
	night = d["night"]
	if _sky_mat:
		_sky_mat.set_shader_parameter("night", night)
		# the two discs, each at its own place: the sun goes down, the moon comes out with the stars
		_sky_mat.set_shader_parameter("sun_pos", to_sun)
		_sky_mat.set_shader_parameter("sun_disc", Color(d["sun"]) * maxf(float(d["energy"]), 1.2))
		_sky_mat.set_shader_parameter("moon_pos", to_moon)
		_sky_mat.set_shader_parameter("moon_vis", smoothstep(0.35, 0.95, night))
		# by day it shows pale while it is well up and enough of it is lit (a thin crescent
		# near the sun is lost in the glare)
		_sky_mat.set_shader_parameter("moon_day", (1.0 - smoothstep(0.0, 0.5, night)) * smoothstep(3.0, 12.0, moon_elev) * smoothstep(0.06, 0.25, moon_lit()))
		# its phase, and its lit side: toward the sun, wherever that is under the horizon
		var ph := moon_phase()
		var mx := Vector3.UP.cross(to_moon).normalized()
		var my := to_moon.cross(mx)
		var flat := to_sun - to_moon * to_sun.dot(to_moon)
		var lit2 := Vector2(flat.dot(mx), flat.dot(my))
		_sky_mat.set_shader_parameter("moon_phase", ph)
		_sky_mat.set_shader_parameter("moon_lit", lit2.normalized() if lit2.length() > 0.001 else Vector2(1, 0))
		# the stars turn about the same axis as the sun and the moon, once a day: the sky's
		# south pole, which stands LATITUDE degrees above the southern horizon (-z)
		var pole := Vector3(0.0, -sin(deg_to_rad(LATITUDE)), -cos(deg_to_rad(LATITUDE)))
		_sky_mat.set_shader_parameter("star_rot", Basis(pole, TAU * (hour - 20.4) / 24.0).inverse())
		_sky_mat.set_shader_parameter("cirrus_cover", d["cirrus"])
		_sky_mat.set_shader_parameter("cumulus_cover", d["cumulus"])
		_sky_mat.set_shader_parameter("zenith_color", d["zenith"])
		_sky_mat.set_shader_parameter("mid_color", d["mid"])
		_sky_mat.set_shader_parameter("horizon_color", (d["horizon"] as Color).lerp(Color(0.52, 0.55, 0.59) * dark, o))
		_sky_mat.set_shader_parameter("overcast", o)
	if _env:
		_env.fog_light_color = (d["fog"] as Color).lerp(Color(0.44, 0.48, 0.52) * dark, maxf(o, haze))
		_env.fog_density = lerpf(0.00045, 0.0022, haze)
		_env.ambient_light_energy = float(d["ambient"]) * lerpf(1.0, 0.8, o) * lerpf(1.0, lerpf(0.72, 1.0, mlit), float(d["night"]))
		_env.tonemap_exposure = d["exposure"]
		_env.glow_intensity = d["glow"]
		# color vision fades in moonlight
		_env.adjustment_saturation = lerpf(1.1, 0.7, d["night"])
	if get_parent().has_method("get_material"):
		var om: ShaderMaterial = get_parent().get_material("Ocean")
		if om:
			om.set_shader_parameter("sun_dir_world", to_light)
			om.set_shader_parameter("sun_tint", light_col * light_energy / 2.4 * dim)
			om.set_shader_parameter("biolum", smoothstep(0.6, 1.0, night) * glow)
	# the play of sunlight under water (shaders/sea_light.gdshaderinc): where it comes from and
	# how strong it is. The moon throws a faint net too
	# (under water the rays stand steeper than in the air: the surface bends them toward the
	# vertical, never more than 48.6 degrees off it, however low the sun)
	var flat := Vector2(to_light.x, to_light.z)
	var sin_w := flat.length() / 1.33
	var slope := flat.normalized() * (sin_w / sqrt(1.0 - sin_w * sin_w)) if flat.length() > 0.001 else Vector2.ZERO
	RenderingServer.global_shader_parameter_set("sun_slope_x", slope.x)
	RenderingServer.global_shader_parameter_set("sun_slope_z", slope.y)
	sea_sun = smoothstep(0.03, 0.4, to_light.y) * clampf(light_energy / 2.4, 0.0, 1.0) * lerpf(1.0, 0.6, float(d["night"])) * (1.0 - 0.92 * o)
	RenderingServer.global_shader_parameter_set("sea_sun", sea_sun)
	if _sand_mat == null and get_parent().has_method("get_material"):
		_sand_mat = get_parent().get_material("Sand")
	if _sand_mat:
		_sand_mat.set_shader_parameter("sun_dir_world", to_light)
		_sand_mat.set_shader_parameter("biolum", smoothstep(0.6, 1.0, night) * glow)
