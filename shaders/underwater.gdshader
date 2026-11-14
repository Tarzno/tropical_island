shader_type spatial;
// The veil over the picture while the camera is under water: everything fades into the water's
// own color with distance (a quad that always fills the screen; scripts/player.gd shows it).
// And the shafts of sunlight: where the rippled surface gathers the light, a beam of it goes
// down through the water along the sun's rays, seen because the water scatters it. The veil
// walks along each line of sight and adds up the light of the beams it passes through
// (the beams stand where the bright patches of a slow pattern lie on the surface: the same
// surface the net of light on the sea floor comes from, shaders/sea_light.gdshaderinc).
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/sea_light.gdshaderinc"
global uniform float world_time;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 water_color : source_color = vec3(0.04, 0.36, 0.42);
uniform float light = 1.0;        // daylight (1 day .. 0.08 night)
uniform float density = 0.075;    // per meter: about 25 m of sight
uniform float shafts = 1.0;       // how strong the shafts of sunlight are (0: none)
uniform float faint = 0.0;        // 0 .. 1: a diver at the end of a breath (scripts/player.gd)

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Where the beams stand: bright patches that drift and change slowly, a few meters apart.
float beam(vec2 p, float t) {
	float a = sin(p.x * 1.15 + sin(p.y * 0.9 + t * 0.33) * 1.3 + t * 0.21);
	float b = sin(p.y * 1.35 + sin(p.x * 0.75 - t * 0.27) * 1.4 - t * 0.17);
	float s = a * b * 0.5 + 0.5;
	return smoothstep(0.52, 0.92, s);
}

void fragment() {
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	float dist = length(v.xyz);
	// looking up, the water ends at the surface: what lies above it is seen through the
	// surface (ocean.gdshader draws that), not through more water
	vec3 dir = (INV_VIEW_MATRIX * vec4(normalize(v.xyz), 0.0)).xyz;
	if (dir.y > 0.002) {
		dist = min(dist, (sea_level - CAMERA_POSITION_WORLD.y) / dir.y);
	}
	// deeper down it is darker and bluer
	float deep = clamp(-(CAMERA_POSITION_WORLD.y + dir.y * dist * 0.5) / 12.0, 0.0, 1.0);
	vec3 col = mix(water_color, water_color * vec3(0.35, 0.6, 0.8), deep) * light;
	float a = clamp(0.07 + 0.93 * (1.0 - exp(-max(dist, 0.0) * density)), 0.0, 1.0);
	// the shafts
	float sh = 0.0;
	if (shafts * sea_sun > 0.001) {
		vec3 sun = normalize(vec3(sun_slope_x, 1.0, sun_slope_z));
		float reach = min(max(dist, 0.0), 18.0);
		// (each pixel starts its walk at a different place, and a different one in every
		// frame: no bands, and no pattern that stands still)
		float jit = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453 + world_time * 7.31);
		const int N = 16;
		for (int i = 0; i < N; i++) {
			float s = (float(i) + jit) / float(N) * reach;
			vec3 p = CAMERA_POSITION_WORLD + dir * s;
			float depth = sea_level - p.y;
			if (depth < 0.0) {
				continue;
			}
			// a beam weakens as it goes down, and its light is veiled on the way to the eye
			// (and none is counted from further than 18 m: it fades out toward there)
			float far = 1.0 - s / 18.0;
			sh += beam(sea_surface_point(p) * 1.0, world_time) * exp(-depth * 0.22) * exp(-s * density * 1.5) * far * far;
		}
		sh *= reach / float(N) * 1.25;
		// seen best looking toward the sun: the water scatters most of the light forward
		float fwd = max(dot(dir, sun), 0.0);
		sh *= (0.4 + 1.0 * fwd * fwd * fwd) * shafts * sea_sun * 0.14;
	}
	// (the veil is blended over the picture: light added to it is carried by its color)
	// the end of a held breath: the edges of the picture grow dim
	vec2 e = SCREEN_UV * 2.0 - 1.0;
	float dim = faint * smoothstep(0.35, 1.25, length(e)) * 0.85;
	ALBEDO = mix(col + vec3(0.72, 0.95, 0.88) * light * sh / a, vec3(0.0, 0.01, 0.02), dim);
	ALPHA = mix(a, 1.0, dim);
}
