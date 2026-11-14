extends SceneTree
## Writes the license notices the app shows under "Licenses" (scripts/licenses.gd) to a
## text file, for the repository and a release:
##   Godot --headless --path . --script tools/licenses_txt.gd -- THIRD-PARTY-LICENSES.txt
## Run it again after a change of the Godot version (tools/build_app.sh does).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "THIRD-PARTY-LICENSES.txt"
	var lic: GDScript = load("res://scripts/licenses.gd")
	var t: String = lic.text()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", path)
		quit(1)
		return
	f.store_string(t)
	f.close()
	print("wrote %s: %d characters, %d lines" % [path, t.length(), t.count("\n")])
	quit()
