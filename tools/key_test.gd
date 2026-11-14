extends Node
## For the tests (tools/shot.gd: "add_tool('res://tools/key_test.gd', 'Keys')"): presses a
## key as the keyboard would, with or without ⌘: "main.get_node('Keys').key(77, true)" is ⌘M.
## The game sees it on the next frame: read what it did in a later job.
func key(code: int, meta := false) -> String:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code as Key
		e.physical_keycode = code as Key
		e.meta_pressed = meta
		e.pressed = down
		Input.parse_input_event(e)
	return ("⌘" if meta else "") + OS.get_keycode_string(code as Key)


## A mouse button pressed and let go at a place in the window (button 1 left, 4 wheel up,
## 5 wheel down): "main.get_node('Keys').click(800, 450, 5)".
func click(x: float, y: float, button := 1) -> String:
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button as MouseButton
		e.position = Vector2(x, y)
		e.global_position = Vector2(x, y)
		e.pressed = down
		Input.parse_input_event(e)
	return "button %d at (%d, %d)" % [button, x, y]


func mouse(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func mouse_is() -> String:
	return "captured" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "free"
