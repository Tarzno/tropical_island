// The leaf shader proper, shared by leaf.gdshader (near) and leaf_far.gdshader (distant LODs).

// Bush / jungle leaf cards (UV: x across the leaf, y along it). COLOR.r = per-leaf random.

global uniform float wind_strength;
global uniform float rain_wet;      // how wet everything is: rises in the rain, dries off afterward

uniform vec3 color_a : source_color = vec3(0.02, 0.085, 0.018);
uniform vec3 color_b : source_color = vec3(0.11, 0.30, 0.06);
uniform vec3 backlight_color : source_color = vec3(0.35, 0.55, 0.08);
uniform float shape_width = 0.46;
uniform float shape_power = 0.3;
uniform float roughness = 0.42;
uniform float specular_amount = 0.45;
uniform float vein = 1.0;
uniform float flutter = 0.035;
uniform float sway = 0.06;
uniform float is_flat_card = 0.0; // 1 = no leaf shape (twigs/flowers use simple shapes)
uniform float hue_var = 0.25;
uniform float blade = 0.0;     // 1 = grass blade: full width at the base, tapering to the tip
uniform float skew = 1.0;      // > 1: widest beyond the middle (obovate, like a badamier leaf)
// 1 = every card is a leafy twig instead of one leaf: pairs of leaves along a thin stem (UV.y along
// the twig), so a crown gets many times the leaves for the same number of cards
uniform float sprig = 0.0;
uniform float sprig_aspect = 0.86;   // card width / card length
uniform float sprig_leaf = 0.42;     // leaf length as a share of the card's length
uniform float sprig_angle = 1.05;    // angle between a leaf and the twig (radians)
uniform float ao = 0.0;        // how much the leaves deep inside a crown are darkened (COLOR.a, baked)

varying float v_ao;

varying float v_rand;
varying vec3 w_pos;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void vertex() {
	v_rand = COLOR.r;
	v_ao = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float w = wind_strength;
	// large scale gust field moving across the island
	float gust = 0.6 + 0.4 * sin(wp.x * 0.07 + wp.z * 0.05 + t * 0.9) * sin(wp.z * 0.11 - t * 0.53);
	vec3 off = vec3(0.0);
	off.x += sin(t * 1.3 + wp.z * 0.21 + wp.y * 0.4) * sway * gust;
	off.z += sin(t * 1.1 + wp.x * 0.19) * sway * 0.6 * gust;
	// per-leaf flutter (stronger at leaf tip)
	float tip = UV.y;
	float ph = v_rand * 40.0;
	off += NORMAL * sin(t * (6.0 + v_rand * 5.0) + ph) * flutter * gust * (0.4 + tip);
	// a fresh wind (a rain shower: scripts/weather.gd raises wind_strength): the foliage leans
	// with it, in from the sea, in quick pulses that run through the trees, and the leaves
	// shake faster
	float blow = max(w - 1.3, 0.0);
	if (blow > 0.0) {
		float pulse = 0.55 + 0.45 * sin(t * 2.3 + wp.x * 0.31 + wp.z * 0.17) * sin(t * 1.4 - wp.z * 0.23);
		off += vec3(-0.97, 0.0, 0.24) * sway * blow * (0.6 + 1.0 * pulse);
		off += NORMAL * sin(t * (13.0 + v_rand * 8.0) + ph * 1.7) * flutter * blow * (0.5 + tip);
	}
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off * w, 0.0)).xyz;
	w_pos = wp;
}

void fragment() {
	vec2 uv = UV;
	float au = abs(uv.x - 0.5);
	float s = pow(max(sin(pow(uv.y, skew) * PI), 0.0), shape_power) * shape_width;
	float alpha = 1.0 - smoothstep(s - 0.04, s, au);
	if (is_flat_card > 0.5) alpha = 1.0 - smoothstep(0.42, 0.5, length(uv - 0.5));
	if (blade > 0.5) alpha = 1.0 - smoothstep(0.46 * (1.0 - uv.y) - 0.04, 0.46 * (1.0 - uv.y) + 0.02, au);

	// color: per-leaf variation + gentle gradient along the leaf
	float r = v_rand;
	float curve = uv.x - 0.5;
	float twig = 0.0;
	if (sprig > 0.5) {
		// four pairs of leaves and one at the tip; a later (higher) leaf lies over the ones below it.
		// A leaf reaches at most 0.4 up the card from its node: only the two pairs at and below
		// this height can cover the pixel (and the tip leaf).
		alpha = 0.0;
		int first = clamp(int(floor((UV.y - 0.04) * 5.0)) - 1, 0, 3) * 2;
		for (int i = first; i < 9; i++) {
			if (i >= first + 4 && i < 8) continue;
			float fi = float(i);
			float side = (i % 2 == 0) ? -1.0 : 1.0;
			float hr = h11(v_rand * 53.0 + fi * 7.3);
			float y0 = 0.04 + floor(fi * 0.5) * 0.2;
			float ang = side * (sprig_angle + (hr - 0.5) * 0.45);
			float len = sprig_leaf * (0.82 + 0.3 * h11(hr * 31.0));
			if (i == 8) { y0 = 0.7; ang = (hr - 0.5) * 0.5; len *= 0.72; }
			vec2 p = vec2((UV.x - 0.5) * sprig_aspect, UV.y - y0);
			vec2 dir = vec2(sin(ang), cos(ang));
			float lu = dot(p, dir) / len;
			float lv = dot(p, vec2(dir.y, -dir.x)) / (len * shape_width * 0.62);
			if (lu <= 0.0 || lu >= 1.0) continue;
			float ls = pow(max(sin(pow(lu, skew) * PI), 0.0), shape_power);
			if (abs(lv) < ls) {
				alpha = 1.0;
				uv = vec2(0.5 + lv * shape_width, lu);   // the leaf's own coordinates: color and veins below
				s = ls * shape_width;
				au = abs(lv) * shape_width;
				r = fract(v_rand + fi * 0.37);
				curve = lv * 0.5 + (hr - 0.5) * 0.9;
			}
		}
		if (alpha < 0.5 && abs(UV.x - 0.5) * sprig_aspect < 0.011 && UV.y < 0.74) {
			alpha = 1.0;
			twig = 1.0;
		}
	}
	vec3 c = mix(color_a, color_b, clamp(r * 1.1 - 0.05 + (uv.y - 0.5) * 0.25, 0.0, 1.0));
	c *= 1.0 + (h11(r * 91.0) - 0.5) * hue_var;
	// yellowish / older leaves
	c = mix(c, c * vec3(1.35, 1.15, 0.55), step(0.93, h11(r * 13.0)) * 0.6);
	// midrib and side veins
	float rib = 1.0 - smoothstep(0.0, 0.025, au);
	float side = abs(sin((uv.y + au * 0.9) * 56.5));
	float veins = smoothstep(0.82, 1.0, side) * smoothstep(0.03, 0.12, au) * (1.0 - smoothstep(s - 0.08, s, au));
	c = mix(c, c * 1.6 + vec3(0.02, 0.03, 0.0), (rib * 0.7 + veins * 0.18) * vein);
	// darker toward the edge
	c *= mix(1.0, 0.82, smoothstep(0.0, 1.0, au / max(s, 0.01)));

	c = mix(c, vec3(0.09, 0.07, 0.045), twig);
	c *= mix(1.0 - ao, 1.0, v_ao);

	ALBEDO = c;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#ifndef LEAF_FAR
	// Soft leaf edges (alpha to coverage). It is what makes foliage expensive: leaves drawn with it
	// cost several times as much per pixel, so only the leaves near the camera get it
	// (leaf_far.gdshader is this shader without it; world.gd gives it to every distant LOD).
	ALPHA_ANTIALIASING_EDGE = 0.3;
#endif
	// wet leaves shine: smooth with the film of water on them, and a shade darker
	ROUGHNESS = mix(roughness, 0.15, rain_wet * 0.85);
	// (the shaded inside of a crown must not mirror the sky either: it would turn gray-blue)
	SPECULAR = specular_amount * mix(1.0 - ao, 1.0, v_ao) * mix(1.0, 1.6, rain_wet);
	ALBEDO *= mix(1.0, 0.85, rain_wet);
	BACKLIGHT = backlight_color * 0.6;
	// fake slight normal curvature across the leaf
	NORMAL = normalize(NORMAL + curve * 0.6 * TANGENT);
}
