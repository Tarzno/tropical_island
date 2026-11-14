extends Node
## For the tests (tools/shot.gd: "add_tool('res://tools/perf.gd', 'Perf')"): what a call
## costs. "main.get_node('Perf').time(main.get_node('SeaLife'), '_update_manta', [0.0166], 600)"
## calls it 600 times and gives the mean and the worst time in microseconds. (The calls are
## real: an update called 600 times moves its animal on by 600 frames.)
func time(node: Object, method: String, args: Array, n: int) -> String:
	var worst := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		var t := Time.get_ticks_usec()
		node.callv(method, args)
		worst = maxi(worst, Time.get_ticks_usec() - t)
	return "%s: mean %.1f us, worst %d us (%d calls)" % [method, float(Time.get_ticks_usec() - t0) / n, worst, n]


## The time all scripts' _process and _physics_process took, as the engine counts it: the
## mean over the last `n` frames it was asked in (call `sample()` once a frame through a
## long `shot`: it does so itself in _process).
var _proc: Array[float] = []
var _phys: Array[float] = []

func _process(_dt: float) -> void:
	_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func frame(reset := true) -> String:
	var a := 0.0
	var b := 0.0
	var worst := 0.0
	for v in _proc:
		a += v
		worst = maxf(worst, v)
	for v in _phys:
		b += v
	var n := maxi(_proc.size(), 1)
	var out := "process %.2f ms (worst %.2f), physics %.2f ms, over %d frames" % [a / n, worst, b / n, _proc.size()]
	if reset:
		_proc.clear()
		_phys.clear()
	return out


## Every script's cost per frame: "main.get_node('Perf').all(main, 200)" asks for it, the
## next physics step measures (each node's _process and _physics_process called `n` times
## over), and `table()` in a later job gives the list, the dearest first, in microseconds a
## call. Whoever is far from the player and skips its work shows as cheap: measure from
## several places.
var _want: Node
var _want_n := 0
var _table: Array = []

func all(from: Node, n: int) -> void:
	_want = from
	_want_n = n


func _physics_process(_dt: float) -> void:
	if _want == null:
		return
	var nodes: Array = [_want]
	nodes.append_array(_want.find_children("*", "", true, false))
	_want = null
	_table = []
	for node: Node in nodes:
		if node == self or node.get_script() == null:
			continue
		for m: String in ["_process", "_physics_process"]:
			if not node.has_method(m) or not (node.is_processing() if m == "_process" else node.is_physics_processing()):
				continue
			var t0 := Time.get_ticks_usec()
			for i in _want_n:
				node.call(m, 1.0 / 60.0)
			_table.append([float(Time.get_ticks_usec() - t0) / _want_n, "%s.%s" % [node.name, m]])
	_table.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])


func table(top := 14) -> String:
	var sum := 0.0
	for r in _table:
		sum += r[0]
	var out := "all scripts %.0f us a frame:" % sum
	for i in mini(top, _table.size()):
		out += "  %s %.0f" % [_table[i][1], _table[i][0]]
	return out
