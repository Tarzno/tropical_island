extends Node
## The tide. The sea rises and falls with the moon, at the real pace: high water when the
## moon stands highest over the island and again when it stands lowest under it (every 12
## hours and 25 minutes), the range growing and shrinking between spring tides (new and full
## moon) and neaps (the half moons). It is the moon of the sky (scripts/daycycle.gd): by
## the computer's clock and date as the game starts, so that the shore a player finds
## depends on the hour and the day, and whoever stays for hours sees it move; and if the
## moon's phase is set with M or the time of day with T, the tide goes with that moon.
## The G key sets it by hand: high water, half tide, low water, and back to the moon; the
## sea then goes to the new level in half a minute or so.
##
## The island was built with the sea at 0. Its beaches are low (the foot of the palms lies
## half a meter up), so that level is taken as near high water: the tide moves between
## +0.3 m (high water at springs) and -0.8 m (low water at springs: the reef's crest, which
## lies 0.5-0.9 m down, comes out), about -0.25 m.
##
## What it sets: the shader global `sea_level` (the sea's surface, the waterline on the sand,
## the light under water, the veils) and `tide_wet` (how far up the sand is still damp from
## the falling tide), `Landscape.sea` (which every script asks that needs the depth of the
## water or the waterline) and `SeaLife.tide`. The node is created by island_life.gd.

const MEAN := -0.25
const SPRINGS := 0.55          # half the range at spring tides
const NEAPS := 0.28            # ... and at neaps
const STATES := [["Tide by the moon", NAN], ["High water", 0.3], ["Half tide", -0.25], ["Low water", -0.8]]
## (the moon's numbers are the sky's: one new moon, the month's length, the hour of noon)
const DayClock := preload("res://scripts/daycycle.gd")

var level := 0.0               # the sea's level now
var state := 0                 # 0: by the clock; 1-3: set by hand
var rate := 0.0                # how fast it is moving (m/s; + rising)
var _ls: Node
var _sealife: Node
var _daycycle: Node
var _wet := 0.0
var _started := false


func setup(ls: Node) -> void:
	_ls = ls
	_sealife = get_node_or_null("../../SeaLife")
	_daycycle = get_node_or_null("../../DayCycle")
	level = by_sky()
	_wet = level
	_apply()
	if not InputMap.has_action("tide"):
		InputMap.add_action("tide")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_G
		InputMap.action_add_event("tide", e)


## The tide under a moon of the phase `phase` (0 new, 0.5 full) at the hour `hour` of the
## day: spring tides at new and full moon, neaps at the half moons; high water when the moon
## stands highest over the island and again when it stands lowest under it, so every day
## some 50 minutes later than the day before.
static func level_at(phase: float, hour: float) -> float:
	var springs := 0.5 + 0.5 * cos(2.0 * TAU * phase)
	var moon_angle := TAU * (hour - DayClock.NOON) / 24.0 - TAU * phase        # 0 when the moon stands highest
	return MEAN + lerpf(NEAPS, SPRINGS, springs) * cos(2.0 * moon_angle)


## The tide's level at a moment of the real calendar (seconds since 1970): what a tide
## table would say.
static func by_clock(unix: float) -> float:
	var bias := float(Time.get_time_zone_from_system()["bias"]) * 60.0
	return level_at(fposmod((unix - DayClock.NEW_MOON) / DayClock.SYNODIC, 1.0), fposmod((unix + bias) / 3600.0, 24.0))


## The tide as the sky has it, now or `ahead` hours on: by the moon's phase and the hour that
## scripts/daycycle.gd shows. (Until 2026-11-12 the tide asked the computer's clock by
## itself: with a full moon set with M the sea kept the half moon's neap range, and with
## T's night the moon stood where the preset's hour put it while high water came by the
## wall clock.)
func by_sky(ahead := 0.0) -> float:
	if _daycycle == null or not _daycycle.has_method("sky_hour"):
		return by_clock(Time.get_unix_time_from_system() + ahead * 3600.0)
	return level_at(float(_daycycle.moon_phase()) + ahead * 3600.0 / DayClock.SYNODIC, float(_daycycle.sky_hour()) + ahead)


func _unhandled_input(event: InputEvent) -> void:
	# (not with ⌘ held: see daycycle.gd)
	if event is InputEventKey and event.meta_pressed:
		return
	if event.is_action_pressed("tide"):
		set_state((state + 1) % STATES.size())
		if _daycycle:
			var text: String = STATES[state][0]
			if state == 0:
				var up := by_sky(1.0 / 60.0) > by_sky()
				text += ": %s" % ("rising" if up else "falling")
			_daycycle.show_message(text)


## 0: by the clock; 1 high water, 2 half tide, 3 low water. `instant`: no half minute of moving.
func set_state(s: int, instant := false) -> void:
	state = clampi(s, 0, STATES.size() - 1)
	if instant:
		level = _target()
		_apply()


func _target() -> float:
	return by_sky() if state == 0 else float(STATES[state][1])


func _process(delta: float) -> void:
	var want := _target()
	var before := level
	# (to a level set by hand, or back to the clock's: at most 3.5 cm a second, eased in and out)
	var step := clampf((want - level) * 0.9, -0.035, 0.035) * minf(delta, 0.1)
	level = want if absf(want - level) < 0.0005 else level + step
	rate = (level - before) / maxf(delta, 0.001)
	# the sand the sea has left dries from the top down, over some twenty minutes
	_wet = maxf(level, _wet - 0.0006 * delta)
	_apply()


func _apply() -> void:
	RenderingServer.global_shader_parameter_set("sea_level", level)
	RenderingServer.global_shader_parameter_set("tide_wet", _wet)
	if _ls:
		_ls.sea = level
	if _sealife and "tide" in _sealife:
		_sealife.tide = level
	# the tide pools: their own water shows once the sea has fallen below their rims
	if _ls and "tide_pools" in _ls:
		for p: Dictionary in _ls.tide_pools:
			(p["node"] as Node3D).visible = level < (p["at"] as Vector3).y - 0.03


## For the tests.
func report() -> Dictionary:
	var next_high := 0.0
	var best := -9.0
	var worst := 9.0
	for k in 150:
		var l := by_sky(k / 12.0)
		worst = minf(worst, l)
		if l > best:
			best = l
			next_high = k * 5.0
	return {"level": snappedf(level, 0.001), "state": STATES[state][0], "by the moon now": snappedf(by_sky(), 0.001),
		"in an hour": snappedf(by_sky(1.0), 0.001), "highest in the next 12.5 h": snappedf(best, 0.001), "in (min)": next_high, "lowest in the next 12.5 h": snappedf(worst, 0.001),
		"by the real clock now": snappedf(by_clock(Time.get_unix_time_from_system()), 0.001), "wet to": snappedf(_wet, 0.001)}
