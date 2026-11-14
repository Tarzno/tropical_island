shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/sea_light.gdshaderinc"
global uniform float world_time;

// Reef fish. Mesh: head at -Z, tail at +Z. UV.x = 0 snout .. 1 tail tip, UV.y = 0 back .. 0.5 belly .. 1 back.
// INSTANCE_CUSTOM: r = species, g = tail-beat phase (0..1, advanced by the script so the beat never
// jumps when the speed changes), b = stroke strength (0 gliding .. 1 sprinting), a = bend (0.5 straight;
// the body curves into a turn, and snaps into a C at a fast-start).

varying float v_species;
varying vec2 v_uv;
varying float v_len;

void vertex() {
	v_species = INSTANCE_CUSTOM.r * 255.0;
	v_uv = UV;
	float along = clamp(UV.x, 0.0, 1.0);
	// traveling wave along the body, growing toward the tail; the head yaws slightly against it
	float wave = sin(INSTANCE_CUSTOM.g * 6.2831 - along * 5.0);
	float amp = (along * along * 0.32 - 0.02 * (1.0 - along)) * mix(0.25, 1.0, INSTANCE_CUSTOM.b);
	VERTEX.x += wave * amp * 0.12 + (INSTANCE_CUSTOM.a - 0.5) * (along * along - 0.15) * 0.2;
	v_len = along;
}

float stripe(float x, float c, float w) {
	return 1.0 - smoothstep(w * 0.6, w, abs(x - c));
}

void fragment() {
	float u = v_uv.x;
	float v = v_uv.y;
	float top = 1.0 - smoothstep(0.0, 0.35, min(v, 1.0 - v));   // 1 on the back
	float belly = 1.0 - smoothstep(0.0, 0.25, abs(v - 0.5));
	int sp = int(round(v_species));
	vec3 c = vec3(0.7);
	float rough = 0.35;
	if (sp == 0) {
		// blue tang: royal blue, black "palette" band, yellow tail
		c = vec3(0.02, 0.16, 0.75);
		float palette = stripe(v, 0.18, 0.09) * smoothstep(0.15, 0.25, u) * (1.0 - smoothstep(0.62, 0.75, u));
		palette += stripe(1.0 - v, 0.18, 0.09) * smoothstep(0.15, 0.25, u) * (1.0 - smoothstep(0.62, 0.75, u));
		c = mix(c, vec3(0.01), clamp(palette, 0.0, 1.0));
		c = mix(c, vec3(1.0, 0.82, 0.05), smoothstep(0.8, 0.86, u));
	} else if (sp == 1) {
		// convict surgeonfish (Acanthurus triostegus): pale, greenish-gray above and white
		// below, with six thin black bars: the first through the eye, the last a short one
		// on the tail stock (thin lines on a pale disc: the sergeant's bars are broad, on
		// a yellow back)
		c = mix(vec3(0.8, 0.83, 0.6), vec3(0.6, 0.67, 0.34), top * 0.85);
		c = mix(c, vec3(0.93, 0.93, 0.84), belly * 0.7);
		float fade = 1.0 - belly * 0.55;          // (the bars thin out toward the belly)
		float cb = stripe(u, 0.105, 0.016) + stripe(u, 0.25, 0.015) * fade + stripe(u, 0.37, 0.015) * fade
			+ stripe(u, 0.49, 0.015) * fade + stripe(u, 0.61, 0.014) * fade + stripe(u, 0.72, 0.013) * top;
		c = mix(c, vec3(0.03, 0.035, 0.04), clamp(cb, 0.0, 1.0) * 0.93);
		// the tail a little dusky
		c = mix(c, vec3(0.62, 0.66, 0.56), smoothstep(0.8, 0.9, u) * 0.6);
	} else if (sp == 2) {
		// Indo-Pacific sergeant: silvery with yellow back and five dark bars
		c = mix(vec3(0.82, 0.86, 0.85), vec3(0.95, 0.85, 0.25), top);
		float bars = smoothstep(0.55, 0.7, sin(u * 31.0 + 1.0)) * smoothstep(0.08, 0.15, u) * (1.0 - smoothstep(0.7, 0.78, u));
		c = mix(c, vec3(0.04, 0.05, 0.06), bars * 0.9);
	} else if (sp == 3) {
		// parrotfish: turquoise with pink-orange scale edges
		c = mix(vec3(0.05, 0.6, 0.55), vec3(0.15, 0.75, 0.45), top);
		float scales = smoothstep(0.75, 0.95, sin(u * 70.0) * sin(v * 60.0));
		c = mix(c, vec3(0.95, 0.45, 0.45), scales * 0.5 + stripe(u, 0.28, 0.03) * 0.6);
		c = mix(c, vec3(0.95, 0.4, 0.55), smoothstep(0.82, 0.9, u) * 0.6);
		rough = 0.3;
	} else {
		// blue-green chromis
		c = mix(vec3(0.15, 0.7, 0.8), vec3(0.3, 0.85, 0.65), top);
		c = mix(c, vec3(0.6, 0.85, 0.95), belly * 0.5);
	}
	// darker back, paler belly, eye
	c *= mix(1.0, 0.75, top * 0.5);
	c = mix(c, c * 1.2 + 0.05, belly * 0.4);
	float eye = 1.0 - smoothstep(0.012, 0.02, length(vec2(u - 0.1, min(abs(v - 0.27), abs(v - 0.73)) * 0.5)));
	c = mix(c, vec3(0.01), eye);
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = 0.6;
}
