// Shared world helpers: terrain heightmap lookup and the shore swash model.
// Heightmap covers world x,z in [-256, 256]. R = terrain height, G = terrain+rocks.

global uniform sampler2D heightmap : filter_linear, repeat_disable;
global uniform float wind_strength;
global uniform float swash_period;
global uniform float world_time;
// The level of the sea: 0 as the island was built; the tide moves it (scripts/tide.gd).
// (Declared in world.gdshaderinc and in sea_light.gdshaderinc: whichever comes first.)
#ifndef SEA_LEVEL_GLOBAL
#define SEA_LEVEL_GLOBAL
global uniform float sea_level;
#endif

const float HM_EXT = 256.0;

vec2 hm_uv(vec2 xz) {
	return (xz + HM_EXT) / (2.0 * HM_EXT);
}

// height of ground (terrain only) at world xz
float ground_height(vec2 xz) {
	float h = textureLod(heightmap, clamp(hm_uv(xz), 0.0, 1.0), 0.0).r;
	// outside the baked area the sea floor falls away from its border, down to the deep sand
	// (the terrain mesh does the same: tools/terrain2.py, outside())
	vec2 o = max(abs(xz) - HM_EXT, 0.0);
	return max(h - 0.5 * length(o), min(h, -30.0));
}

// how hard the swell breaks here (0..1): the blue channel marks the crest of the reef where it
// faces the open sea (tools/terrain2.py)
float surf_at(vec2 xz) {
	vec2 uv = hm_uv(xz);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
	return textureLod(heightmap, uv, 0.0).b;
}

float obstacle_height(vec2 xz) {
	vec2 uv = hm_uv(xz);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return ground_height(xz);
	return textureLod(heightmap, uv, 0.0).g;
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash11(i), hash11(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// Swash: periodic run-up of the water edge. Returns 0..1 (1 = maximum run-up).
// Varies along the beach (z) so the edge is not a perfectly straight line.
float swash(float z, float t) {
	float ph = t / swash_period + noise1(z * 0.035) * 0.6 + noise1(z * 0.11 + 7.0) * 0.15;
	float f = fract(ph);
	// fast run-up (0..0.3), slow backwash (0.3..1)
	float up = smoothstep(0.0, 0.3, f);
	float down = 1.0 - smoothstep(0.3, 1.0, f);
	float s = up * down;
	// each wave a slightly different size
	float amp = 0.65 + 0.35 * noise1(floor(ph) * 1.7 + z * 0.02);
	return s * amp;
}

// water level offset at the shore caused by swash
const float SWASH_HEIGHT = 0.16;
