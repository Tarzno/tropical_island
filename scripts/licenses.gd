extends RefCounted
## The license notices that have to go with the game: the project's own (CC BY-NC-SA 4.0),
## Godot's (MIT), those of the
## third-party software inside the engine, the Godot AI addon's, and a line on what the
## textures and sounds were made with. Everything about the engine comes from the engine
## itself at run time (Engine.get_license_text(), get_copyright_info(), get_license_info()),
## so it is always that of the Godot the app was built with.
## Preloaded by scripts/menus.gd (the application menu's "Licenses"; no class_name) and by tools/licenses_txt.gd,
## which writes the same words to THIRD-PARTY-LICENSES.txt.

## The project's own license (chosen 2026-11-13; its full text is the LICENSE file
## at the project's top).
const PROJECT_LICENSE := "Tropical Island © 2026 Hanno Teeling is licensed under the Creative Commons " \
	+ "Attribution-NonCommercial-ShareAlike 4.0 International License (CC BY-NC-SA 4.0). You may copy, " \
	+ "share and change it, as long as you give credit, do not use it commercially, and pass on " \
	+ "what you make of it under the same license.\nhttps://creativecommons.org/licenses/by-nc-sa/4.0/"

const ADDON_LICENSE := """MIT License

Copyright (c) 2025 Godot AI contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""


## The notices as a list of [heading, text], in the order they are shown.
static func sections() -> Array:
	var out: Array = []
	var godot: String = Engine.get_version_info()["string"].get_slice(" ", 0)
	out.append(["Tropical Island",
		PROJECT_LICENSE + "\n\n"
		+ "Tropical Island is built with Godot Engine %s and holds software written by others. " % godot
		+ "Their licenses ask that the notices below go with the game."])
	out.append(["Godot Engine",
		"This game uses Godot Engine, available under the following license:\n\n"
		+ Engine.get_license_text().strip_edges()])

	# the third-party software inside the engine: who holds the copyright, under which license
	var parts := PackedStringArray()
	parts.append("Godot Engine holds the following third-party software. The licenses named here "
		+ "are given in full under \"License texts\" below (\"Expat\" is the MIT License).")
	for comp: Dictionary in Engine.get_copyright_info():
		if comp["name"] == "Godot Engine":
			continue
		var lines := PackedStringArray()
		lines.append(comp["name"])
		for part: Dictionary in comp["parts"]:
			for c: String in part["copyright"]:
				lines.append("    © " + c)
			lines.append("    License: " + part["license"])
		parts.append("\n".join(lines))
	out.append(["Third-party software in Godot Engine", "\n\n".join(parts)])

	out.append(["Godot AI",
		"The editor addon Godot AI (addons/godot_ai) is in the app and does nothing there. "
		+ "It is available under the following license:\n\n" + ADDON_LICENSE])
	out.append(["Textures and sounds",
		"The textures and the app's icon were made with Z Image Turbo (Tongyi-MAI; the model is "
		+ "under the Apache License 2.0). The sounds were made with Stable Audio 3 Medium "
		+ "(Stability AI), used under the Stability AI Community License. Neither model is "
		+ "part of the app."])

	var texts := PackedStringArray()
	var info: Dictionary = Engine.get_license_info()
	for id: String in info:
		texts.append(id + "\n" + "-".repeat(id.length()) + "\n\n" + (info[id] as String).strip_edges())
	out.append(["License texts", "\n\n\n".join(texts)])
	return out


## All of it as one plain text (for the file that goes with a release).
static func text() -> String:
	var out := PackedStringArray()
	for s: Array in sections():
		var head: String = s[0]
		out.append(head.to_upper() + "\n" + "=".repeat(head.length()) + "\n\n" + (s[1] as String))
	return "\n\n\n".join(out) + "\n"
