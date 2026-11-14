shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Palm fronds. Mesh is in crown-local space (crown at origin).
// UV: x along the leaflet (0 base -> 1 tip), y across. COLOR.r = per-leaflet random.

global uniform float wind_strength;
global uniform float rain_wet;      // how wet everything is (scripts/weather.gd)

uniform vec3 color_a : source_color = vec3(0.10, 0.32, 0.05);
uniform vec3 color_b : source_color = vec3(0.32, 0.58, 0.12);
uniform vec3 dry_color : source_color = vec3(0.55, 0.45, 0.18);
uniform vec3 backlight_color : source_color = vec3(0.45, 0.6, 0.12);
uniform float sway_amount = 0.22;
uniform float flutter_amount = 0.05;

varying float v_rand;
varying float v_r;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void vertex() {
	v_rand = COLOR.r;
	float t = TIME;
	vec3 origin = NODE_POSITION_WORLD;
	float seed = origin.x * 0.37 + origin.z * 0.23;
	float r = length(VERTEX.xz);
	v_r = r;
	float w = wind_strength;
	// gusts
	float gust = 0.65 + 0.35 * sin(t * 0.7 + seed) * sin(t * 0.31 + seed * 2.0);
	float rr = r * r * 0.06;
	// whole-frond bobbing (vertical), each frond direction gets a different phase
	float ang = atan(VERTEX.z, VERTEX.x);
	float bob = sin(t * 1.7 + ang * 3.0 + seed) * 0.6 + sin(t * 2.9 + ang * 5.0) * 0.25;
	vec3 off = vec3(0.0);
	off.y += bob * rr * sway_amount * gust;
	// lateral push in wind direction (world -x/+z wind from the sea blows inland)
	vec3 wind_dir = (inverse(MODEL_MATRIX) * vec4(normalize(vec3(-1.0, 0.0, 0.25)), 0.0)).xyz;
	off += wind_dir * rr * sway_amount * 0.8 * (gust + 0.25 * sin(t * 2.2 + ang * 2.0));
	// leaflet flutter
	off += NORMAL * sin(t * 9.0 + v_rand * 60.0 + r * 2.0) * flutter_amount * UV.x * (0.5 + gust) * min(r * 0.4, 1.0);
	// a fresh wind (a rain shower): the fronds stream with it and whip
	float blow = max(w - 1.3, 0.0);
	off += wind_dir * rr * sway_amount * blow * (0.9 + 0.7 * sin(t * 2.6 + seed + ang));
	off.y += sin(t * 4.3 + ang * 4.0 + seed) * rr * sway_amount * blow * 0.5;
	VERTEX += off * w;
}

void fragment() {
	float r = v_rand;
	vec3 c = mix(color_a, color_b, clamp(0.35 + (h11(r * 37.0) - 0.5) * 0.9, 0.0, 1.0));
	c *= 0.85 + 0.35 * r;
	// midrib of the leaflet
	float dv = abs(UV.y - 0.5);
	c = mix(c * 1.25 + vec3(0.04, 0.04, 0.0), c, smoothstep(0.0, 0.07, dv));
	// dry tips on some leaflets
	float tip = smoothstep(0.72, 0.98, UV.x) * step(0.65, r);
	c = mix(c, dry_color, tip * 0.8);
	// (wet fronds shine)
	ALBEDO = c * mix(1.0, 0.85, rain_wet);
	ROUGHNESS = mix(0.42, 0.14, rain_wet * 0.85);
	SPECULAR = mix(0.5, 0.75, rain_wet);
	BACKLIGHT = backlight_color * 0.7;
}
