shader_type spatial;
// Falling rain near the eye (scripts/weather.gd; mesh: thousands of small quads, each with a
// random place of its own in COLOR.rgb and its rank in COLOR.a). Each is a streak that
// falls through a box around the camera and comes in again at the top: the box goes with the
// camera, the rain does not (it stays in the world as the camera moves through it).
// world_vertex_coords: the vertices are placed in the world directly.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

global uniform float world_time;
uniform float amount = 0.0;        // how many of the streaks fall: 0 .. 1
uniform vec2 wind = vec2(1.2, 0.5);   // how far the rain is blown sideways (m/s)
uniform float light = 1.0;         // daylight
global uniform float sea_level;
uniform vec2 drift = vec2(0.0);      // how far the wind has carried the rain so far (m)
// The rain's shadow under the grotto's boulders (weather.gd: _bake_roofs): for every place on
// the level roof_slants.w, the height at which rain that falls through that place first
// meets rock or ground, at three slants (r, g, b: roof_slants.xyz, meters sideways per meter
// of fall). A streak below that height has a roof over it and is not drawn.
uniform bool roofs = false;
uniform sampler2D roof_map : filter_nearest, repeat_disable;
uniform vec4 roof_rect;            // the map's corner (x, z), one over its size
uniform vec4 roof_slants = vec4(0.2, 0.35, 0.5, 0.0);
// The same for the rest of the island (weather.gd: _isle_mark): rock only, coarser, on the
// level isle_level; where no rock is over a line of rain it holds a height far below.
uniform bool isles = false;
uniform sampler2D isle_map : filter_nearest, repeat_disable;
uniform vec4 isle_rect;
uniform float isle_level = 0.0;
const vec3 BOX = vec3(22.0, 15.0, 22.0);

varying float v_alpha;
varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	vec3 seed = COLOR.rgb;
	float speed = 7.5 + 2.5 * seed.x;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 p = seed * BOX;
	p.y -= world_time * speed;
	p.xz += drift;
	p = mod(p - cam, BOX) - BOX * 0.5 + cam;
	vec3 vel = vec3(wind.x, -speed, wind.y);
	vec3 fall = normalize(vel);
	vec3 to_cam = cam - p;
	float dist = length(to_cam);
	vec3 side = normalize(cross(fall, to_cam));
	// a streak as long as the drop falls while the eye holds it; never much thinner than a pixel
	float len = speed * 0.04;
	float width = max(0.006, dist * 0.0017);
	vec3 wp = p + fall * ((UV.y - 0.5) * len) + side * ((UV.x - 0.5) * width);
	// only as many as it rains; none close to the eye, none beyond the box, none under the sea
	float on = step(COLOR.a, amount) * smoothstep(0.4, 1.5, dist) * (1.0 - smoothstep(BOX.x * 0.38, BOX.x * 0.5, dist)) * step(sea_level + 0.1, wp.y);
	if (roofs && on > 0.0) {
		float slant = length(wind) / speed;
		vec2 lee = length(wind) > 0.001 ? normalize(wind) : vec2(1.0, 0.0);
		float above = p.y - roof_slants.w;
		float open_sky = 0.0;
		float weights = 0.0;
		float gap = roof_slants.y - roof_slants.x;
		for (int k = 0; k < 3; k++) {
			// (how near this streak's slant is to the map's: the two nearest count)
			float nearness = max(1.0 - abs(clamp(slant, roof_slants.x, roof_slants.z) - roof_slants[k]) / gap, 0.0);
			if (nearness <= 0.0) {
				continue;
			}
			vec2 uv = (p.xz + lee * roof_slants[k] * above - roof_rect.xy) * roof_rect.zw;
			float clear = 1.0;
			if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
				clear = step(textureLod(roof_map, uv, 0.0)[k], p.y);
			} else if (isles) {
				vec2 iuv = (p.xz + lee * roof_slants[k] * (p.y - isle_level) - isle_rect.xy) * isle_rect.zw;
				if (iuv.x > 0.0 && iuv.x < 1.0 && iuv.y > 0.0 && iuv.y < 1.0) {
					clear = step(textureLod(isle_map, iuv, 0.0)[k], p.y);
				}
			}
			open_sky += clear * nearness;
			weights += nearness;
		}
		on *= open_sky / max(weights, 0.001);
	}
	v_alpha = on * (0.45 + 0.35 * seed.z);
	VERTEX = on > 0.0 ? wp : cam + vec3(0.0, -1000.0, 0.0);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float across = 1.0 - abs(v_uv.x - 0.5) * 2.0;
	float along = sin(v_uv.y * 3.14159);
	ALBEDO = vec3(0.86, 0.9, 0.94) * light;
	ALPHA = v_alpha * across * along;
}
