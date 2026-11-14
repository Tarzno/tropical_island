// The rain shower, for the shaders it touches (scripts/weather.gd sets the two globals; they
// are project settings: shader_globals).
// The including shader passes the time (world_time may not be declared twice).

global uniform float rain;       // how hard it is raining now: 0 .. 1
global uniform float rain_wet;   // how wet the ground is: rises in the rain, dries off afterward

vec2 wr_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// One drop in every cell of a grid, again and again at a new place in the cell: a ring that
// runs outward and dies. xy: how it tilts the surface, z: the white of it.
vec3 wr_layer(vec2 p, float t, float cell, float seed) {
	vec2 g = p / cell + seed;
	vec2 i = floor(g);
	vec2 h = wr_hash22(i);
	float clock = t * (1.5 + 0.7 * h.x) + h.y * 9.0;
	float life = fract(clock);
	vec2 c = (wr_hash22(i + floor(clock) * 7.3) - 0.5) * 0.44;
	vec2 d = fract(g) - 0.5 - c;
	float r = length(d);
	float w = (r - life * 0.34) * 24.0;
	float ring = sin(w) * exp(-w * w * 0.3) * (1.0 - life) * (1.0 - life);
	float splash = (1.0 - smoothstep(0.0, 0.06, r)) * (1.0 - smoothstep(0.0, 0.16, life));
	// (z: what shows as white: the splash, and the crest of the ring)
	return vec3(d / max(r, 0.001) * ring, splash + max(ring, 0.0) * 0.55);
}

// Rain on water at p (world x, z; meters): the rings of the drops. xy tilts the normal, z is
// the whiteness of fresh splashes. Scaled by how hard it rains; nothing when it does not.
vec3 rain_rings(vec2 p, float t) {
	if (rain <= 0.002) {
		return vec3(0.0);
	}
	vec3 a = wr_layer(p, t, 0.3, 0.0);
	vec3 b = wr_layer(p, t * 1.13, 0.43, 13.7);
	// (in light rain not every cell has its drop)
	float thin = smoothstep(0.0, 0.6, rain);
	return (a + b * thin) * min(rain * 1.6, 1.0);
}
