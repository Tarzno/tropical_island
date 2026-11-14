// Light under the sea, shared by everything that can be under water: the moving net of bright
// lines the rippled surface throws on whatever lies below it (caustics).
// The pattern is laid out on the surface and comes down along the sun's rays: a point takes
// the pattern from the place where its ray of sunlight came through the surface, so the
// light on a coral, on the fish above it and on the sand beside it is one and the same net,
// slanting with the sun. scripts/daycycle.gd sets the three globals (they are project
// settings: shader_globals).
// The including shader passes the time (world_time: it is declared there or in
// world.gdshaderinc, and may not be declared twice).

global uniform float sea_sun;       // how strongly the sun plays under water: 1 at midday .. 0
global uniform float sun_slope_x;   // the way the sunlight comes down through the water, as a slope: x / y and z / y
global uniform float sun_slope_z;
// The level of the sea: 0 as the island was built; the tide moves it (scripts/tide.gd).
// (Declared in world.gdshaderinc and in sea_light.gdshaderinc: whichever comes first.)
#ifndef SEA_LEVEL_GLOBAL
#define SEA_LEVEL_GLOBAL
global uniform float sea_level;
#endif

vec2 sl_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// a net of moving cells: 0 on the lines between them
float sl_layer(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = sl_hash22(i + g);
			o = 0.5 + 0.45 * sin(t + 6.2831 * o);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return smoothstep(0.0, 0.12, d2 - d1);
}

// Where the ray of sunlight that reaches the world point wp came through the surface.
vec2 sea_surface_point(vec3 wp) {
	return wp.xz - vec2(sun_slope_x, sun_slope_z) * (wp.y - sea_level);
}

// The net at the world point wp: 0 between the lines .. 1.5 where two of them cross.
float sea_caustics(vec3 wp, float t) {
	vec2 p = sea_surface_point(wp) * 0.9;
	float tt = t * 1.6;
	// two nets of bright lines, a coarser and a finer one, drifting against each other;
	// brightest where their lines cross. (Their product alone, as it used to be, left only
	// the crossings: scattered dashes, not a net.)
	// (the lines bend: the cells are looked up at a place pushed about by a slow wave)
	p += 0.22 * vec2(sin(p.y * 1.7 + tt * 0.5), sin(p.x * 1.9 - tt * 0.4)) + 0.09 * vec2(sin(p.y * 5.3 - tt * 0.8), sin(p.x * 4.7 + tt * 0.7));
	float a = 1.0 - sl_layer(p * 1.1, tt * 1.1);
	float b = 1.0 - sl_layer(p * 1.9 + vec2(3.1, 1.7), -tt * 0.9 + 1.3);
	return a * a * 0.5 + b * b * 0.3 + a * b * 0.7;
}

// The moving light on a surface at wp whose normal is wn (both in world space), as a factor
// for the surface's own color: add ALBEDO times this to EMISSION. Nothing above the water,
// nothing at night, less on what faces away from the sun, fading out far down.
float sea_light(vec3 wp, vec3 wn, float t) {
	float depth = sea_level - wp.y;
	if (depth <= 0.0 || sea_sun <= 0.001) {
		return 0.0;
	}
	float fade = smoothstep(0.0, 0.4, depth) * (1.0 - smoothstep(5.0, 13.0, depth));
	vec3 sun = normalize(vec3(sun_slope_x, 1.0, sun_slope_z));
	float facing = clamp(dot(normalize(wn), sun) * 0.85 + 0.3, 0.0, 1.0);
	return sea_caustics(wp, t) * fade * facing * sea_sun;
}
