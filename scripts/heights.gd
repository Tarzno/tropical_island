@tool
extends RefCounted
## The island's height map (assets/textures/heightmap.exr: 2048 x 2048 pixels over 512 m;
## red the terrain, green the terrain with the .blend's rocks standing on it, blue where
## the swell breaks), read once and shared by everything that asks for the ground.
## Until 2026-11-12 six scripts each kept a copy of the picture (50 MB apiece) and read it
## in four ways that did not agree (the code review's finding 8).
##   const Heights := preload("res://scripts/heights.gd")
##   Heights.ground(x, z)             the terrain; beyond the map, its edge (Landscape.ground)
##   Heights.terrain(x, z, -9.0)      the terrain; beyond the map, the value given
##   Heights.with_rocks(x, z, -30.0)  the terrain with the .blend's rocks on it (the green)
## All three read between the four pixels around the place (the same sums, in the same
## order, as the scripts' own readers did: the animals' depth rules see the numbers they
## were tuned on). Heights are against the sea at 0: the tide is the asker's business.

const EXT := 256.0            # the map covers -EXT .. EXT in x and in z

static var _d: PackedFloat32Array      # red, green, blue of every pixel, row by row
static var _w := 0
static var _h := 0


## Reads the picture (again: the editor calls this when the landscape is rebuilt, since
## the map may have been baked anew).
static func read() -> void:
	var img := (load("res://assets/textures/heightmap.exr") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBF:
		img.convert(Image.FORMAT_RGBF)
	_d = img.get_data().to_float32_array()
	_w = img.get_width()
	_h = img.get_height()


static func width() -> int:
	if _w == 0:
		read()
	return _w


static func height() -> int:
	if _w == 0:
		read()
	return _h


## One pixel's channel (0 red, 1 green, 2 blue), as it is.
static func pixel(px: int, py: int, channel: int) -> float:
	if _w == 0:
		read()
	return _d[(py * _w + px) * 3 + channel]


## The terrain at (x, z); beyond the map, the height at its edge.
static func ground(x: float, z: float) -> float:
	if _w == 0:
		read()
	var u := (x + EXT) / (2.0 * EXT) * _w - 0.5
	var v := (z + EXT) / (2.0 * EXT) * _h - 0.5
	u = clampf(u, 0, _w - 2)
	v = clampf(v, 0, _h - 2)
	var x0 := int(u); var y0 := int(v)
	var fx := u - x0; var fy := v - y0
	var i := (y0 * _w + x0) * 3
	var a := lerpf(_d[i], _d[i + 3], fx)
	var b := lerpf(_d[i + _w * 3], _d[i + _w * 3 + 3], fx)
	return lerpf(a, b, fy)


## The terrain at (x, z); beyond the map, `outside`.
static func terrain(x: float, z: float, outside: float) -> float:
	if _w == 0:
		read()
	var u := (x + EXT) / (2.0 * EXT) * _w - 0.5
	var v := (z + EXT) / (2.0 * EXT) * _h - 0.5
	if u < 0 or v < 0 or u >= _w - 1 or v >= _h - 1:
		return outside
	var x0 := int(u); var y0 := int(v)
	var fx := u - x0; var fy := v - y0
	var i := (y0 * _w + x0) * 3
	var a := lerpf(_d[i], _d[i + 3], fx)
	var b := lerpf(_d[i + _w * 3], _d[i + _w * 3 + 3], fx)
	return lerpf(a, b, fy)


## The terrain with the .blend's rocks on it (the start beach's boulders count as ground)
## at (x, z); beyond the map, `outside`. What swims asks this.
static func with_rocks(x: float, z: float, outside: float) -> float:
	if _w == 0:
		read()
	var u := (x + EXT) / (2.0 * EXT) * _w - 0.5
	var v := (z + EXT) / (2.0 * EXT) * _h - 0.5
	if u < 0 or v < 0 or u >= _w - 1 or v >= _h - 1:
		return outside
	var x0 := int(u); var y0 := int(v)
	var fx := u - x0; var fy := v - y0
	var i := (y0 * _w + x0) * 3 + 1
	var a := lerpf(_d[i], _d[i + 3], fx)
	var b := lerpf(_d[i + _w * 3], _d[i + _w * 3 + 3], fx)
	return lerpf(a, b, fy)
