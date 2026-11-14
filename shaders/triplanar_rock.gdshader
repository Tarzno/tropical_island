shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sea_light.gdshaderinc"

// World-space triplanar material used for granite boulders and bark.

#include "res://shaders/world.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float scale = 0.35;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.75;
uniform float bump = 0.6;
uniform float waterline_effects = 1.0;
uniform float moss = 0.0;
uniform vec3 moss_color : source_color = vec3(0.12, 0.17, 0.05);
// The rain's shadow under the grotto's boulders (weather.gd: _bake_roofs; the same map as in
// rain.gdshader): rock that has rock over it, the way the rain falls, stays dry.
uniform bool rain_roofs = false;
uniform sampler2D rain_roof_map : filter_linear, repeat_disable;
uniform vec4 rain_roof_rect;       // the map's corner (x, z), one over its size
uniform vec4 rain_roof_slants;     // three slants (r, g, b), and the map's level
uniform vec2 rain_lee;             // where the rain is blown to
// (the rest of the island: weather.gd: _isle_mark; rock only, on the level isle_level)
uniform bool isles = false;
uniform sampler2D isle_map : filter_linear, repeat_disable;
uniform vec4 isle_rect;
uniform float isle_level = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_sample(sampler2D tex, vec3 p, vec3 bw) {
	vec3 x = texture(tex, p.zy).rgb;
	vec3 y = texture(tex, p.xz).rgb;
	vec3 z = texture(tex, p.xy).rgb;
	return x * bw.x + y * bw.y + z * bw.z;
}

float tri_noise(vec3 p, vec3 bw) {
	return texture(noise_tex, p.zy).r * bw.x + texture(noise_tex, p.xz).r * bw.y + texture(noise_tex, p.xy).r * bw.z;
}

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 p = w_pos * scale;
	vec3 c = tri_sample(albedo_tex, p, bw);
	vec3 c2 = tri_sample(albedo_tex, p * 0.31 + 0.5, bw);
	float macro = tri_noise(w_pos * 0.05, bw);
	c = mix(c, c2, 0.35) * tint * mix(0.8, 1.15, macro);

	// bump from luminance gradient (cheap)
	float e = 0.02;
	float l0 = lum(tri_sample(albedo_tex, p, bw));
	float lx = lum(tri_sample(albedo_tex, p + vec3(e, 0.0, 0.0), bw));
	float ly = lum(tri_sample(albedo_tex, p + vec3(0.0, e, 0.0), bw));
	float lz = lum(tri_sample(albedo_tex, p + vec3(0.0, 0.0, e), bw));
	vec3 g = vec3(lx - l0, ly - l0, lz - l0) / e;
	g -= n * dot(g, n);
	vec3 nn = normalize(n - g * bump * 0.05);

	// streaks of weathering running down the rock
	float streak = texture(noise_tex, vec2(w_pos.x * 0.6 + w_pos.z * 0.6, w_pos.y * 0.05)).r;
	c *= mix(1.0, 0.75, smoothstep(0.55, 0.8, streak) * (1.0 - bw.y));

	float rough = roughness;
	if (waterline_effects > 0.5) {
		float h = w_pos.y;
		// wet, dark band near the water + algae below
		float wet = 1.0 - smoothstep(0.1, 0.9 + macro * 0.5, h);
		c = mix(c, c * vec3(0.45, 0.43, 0.38), wet);
		float algae = 1.0 - smoothstep(-0.4, 0.15, h);
		c = mix(c, vec3(0.13, 0.15, 0.08), algae * 0.6);
		rough = mix(rough, 0.3, wet * (1.0 - algae));
	}
	// moss / dirt on top surfaces
	float up = smoothstep(0.55, 0.95, n.y) * moss * smoothstep(0.4, 0.6, macro);
	c = mix(c, moss_color, up);

	// wet from the rain: darker, with a sheen (the tops and the weather side most)
	float rw = rain_wet * smoothstep(-0.3, 0.5, n.y) * step(0.05, w_pos.y);
	if (rw > 0.0 && (rain_roofs || isles)) {
		// (wet where the rain reaches it at any of the three slants)
		float reached = 0.0;
		for (int k = 0; k < 3; k++) {
			vec2 ruv = (w_pos.xz + rain_lee * rain_roof_slants[k] * (w_pos.y - rain_roof_slants.w) - rain_roof_rect.xy) * rain_roof_rect.zw;
			vec2 iuv = (w_pos.xz + rain_lee * rain_roof_slants[k] * (w_pos.y - isle_level) - isle_rect.xy) * isle_rect.zw;
			if (rain_roofs && ruv.x > 0.0 && ruv.x < 1.0 && ruv.y > 0.0 && ruv.y < 1.0) {
				reached = max(reached, 1.0 - smoothstep(0.35, 1.0, textureLod(rain_roof_map, ruv, 0.0)[k] - w_pos.y));
			} else if (isles && iuv.x > 0.0 && iuv.x < 1.0 && iuv.y > 0.0 && iuv.y < 1.0) {
				reached = max(reached, 1.0 - smoothstep(0.45, 1.1, textureLod(isle_map, iuv, 0.0)[k] - w_pos.y));
			} else {
				reached = 1.0;
			}
		}
		rw *= reached;
	}
	c *= mix(1.0, 0.6, rw);
	rough = mix(rough, 0.28, rw * 0.8);
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.0;
	ROUGHNESS = rough;
	NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
}
