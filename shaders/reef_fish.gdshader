shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/sea_light.gdshaderinc"

// The small fish of the reef that are built in scripts/reef_models.gd and drawn as MultiMeshes
// by scripts/reef_life.gd: the Seychelles anemonefish (species 0), the skunk anemonefish (1),
// the lionfish (2). Forward = -Z, the body 3.6 long (the instance is scaled to life size).
// INSTANCE_CUSTOM: r = species / 255, g = the phase of the tail beat (0..1, advanced by the
// script), b = how hard it beats (0..1), a = the bend of the body into a turn (0.5 straight).
// Anemonefish: UV.x = snout 0 .. tail 1, UV.y = the way around the trunk (0 belly, 0.5 back),
// -1 on fins and eyes; COLOR.r = 1 dorsal and tail fin, COLOR.b = 1 the paired fins and the
// anal fin, COLOR.g = 1 on the back .. 0 on the belly, COLOR.a = 0 the eyes.
// Lionfish: COLOR.rgb is the color itself (the bands are in the mesh), COLOR.a < 0.5: a ray
// or spine, with UV.y = how far out along it (0 at the body .. 1 at its end) and UV.x its
// own phase: they wave slowly.

global uniform float world_time;

varying float v_species;
varying vec3 o_pos;

void vertex() {
	v_species = INSTANCE_CUSTOM.r * 255.0;
	o_pos = VERTEX;
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	float beat = mix(0.25, 1.0, INSTANCE_CUSTOM.b);
	float turn = INSTANCE_CUSTOM.a - 0.5;
	if (v_species < 1.5) {
		float u = clamp(VERTEX.z / 3.6 + 0.5, 0.0, 1.0);
		// anemonefish waggle with the whole body, the head swinging against the tail
		VERTEX.x += sin(ph - u * 4.2) * (u * u * 0.62 - 0.07 * (1.0 - u)) * beat + turn * (u * u - 0.15) * 1.6;
		// the pectoral fins paddle all the time, each on its own side
		if (COLOR.b > 0.5 && abs(o_pos.x) > 0.27 && o_pos.y > -0.5) {
			float outb = abs(o_pos.x) - 0.27;
			VERTEX.z += sin(ph * 2.0 + sign(o_pos.x) * 1.4) * outb * 0.75;
			VERTEX.x -= sign(o_pos.x) * (0.5 + 0.5 * sin(ph * 2.0 + sign(o_pos.x) * 1.4)) * outb * 0.4;
		}
	} else {
		float u = clamp(VERTEX.z / 3.6 + 0.5, 0.0, 1.0);
		// the lionfish hangs in the water: a slow, slight wave, mostly the tail
		VERTEX.x += sin(ph - u * 3.5) * u * u * u * 0.4 * beat + turn * (u * u - 0.15) * 1.2;
		if (COLOR.a < 0.5) {
			// rays and spines wave, each a little after its neighbor
			float k = UV.y * UV.y;
			float w = world_time * 1.1 + UV.x * 6.2831 + float(INSTANCE_ID) * 1.3;
			VERTEX.z += sin(w) * 0.16 * k;
			VERTEX.y += cos(w * 0.8) * 0.1 * k;
			VERTEX.x += sin(w * 0.6 + 1.0) * 0.1 * k * sign(o_pos.x + 0.0001);
		}
	}
}

float bar(float x, float a, float b, float soft) {
	return smoothstep(a - soft, a + soft, x) * (1.0 - smoothstep(b - soft, b + soft, x));
}

void fragment() {
	int sp = int(round(v_species));
	float u = clamp(o_pos.z / 3.6 + 0.5, 0.0, 1.0);
	vec3 c;
	float rough = 0.4;
	if (sp == 0) {
		// Seychelles anemonefish: dark brown to black with three white bars; snout, breast,
		// belly and the lower fins yellow; a dusky tail with pale edges
		vec3 dark = vec3(0.03, 0.019, 0.013);
		vec3 yellow = vec3(0.86, 0.5, 0.045);
		vec3 white = vec3(0.86, 0.9, 0.93);
		float back = COLOR.g;
		c = mix(yellow, dark, smoothstep(0.22, 0.5, back) * smoothstep(0.03, 0.12, u));
		// the bars (the one on the head is the broadest; they bend back a little toward the belly)
		float ub = u + (0.5 - back) * 0.03;
		float bars = bar(ub, 0.175, 0.25, 0.008) + bar(ub, 0.44, 0.51, 0.008) + bar(ub, 0.735, 0.79, 0.008) * smoothstep(0.1, 0.3, back + 0.3);
		if (UV.y < -0.5) {
			// fins
			c = COLOR.b > 0.5 ? yellow : dark;
			if (COLOR.r > 0.5) {
				// the middle bar runs up into the dorsal fin; the tail is dusky with pale edges
				bars = bar(u, 0.44, 0.5, 0.008) * step(u, 0.75);
				float edge = smoothstep(0.26, 0.4, abs(o_pos.y)) * step(0.8, u);
				c = mix(c, vec3(0.75, 0.7, 0.5), edge * 0.85);
			} else {
				bars = 0.0;
			}
		}
		c = mix(c, white, clamp(bars, 0.0, 1.0));
	} else if (sp == 1) {
		// skunk anemonefish: pinkish orange, a white stripe along the top of the head and the
		// back, the fins pale
		float back = COLOR.g;
		c = mix(vec3(0.95, 0.62, 0.4), vec3(0.88, 0.4, 0.2), smoothstep(0.2, 0.8, back));
		float stripe = smoothstep(0.42, 0.46, 0.5 - abs(UV.y - 0.5)) * smoothstep(0.03, 0.06, u);
		if (UV.y < -0.5) {
			c = vec3(0.96, 0.7, 0.5);
			stripe = COLOR.r > 0.5 ? (u < 0.76 ? 1.0 - smoothstep(0.62, 0.8, o_pos.y) : 0.6) : 0.0;
		}
		c = mix(c, vec3(0.94, 0.95, 0.93), clamp(stripe, 0.0, 1.0));
	} else if (COLOR.a > 0.9) {
		// lionfish, the trunk: red-brown bars on white, broad and narrow by turns, slanting on
		// the head; paler below
		float back = COLOR.g;
		float ub = u * 15.0 + (back - 0.5) * (u < 0.2 ? 2.2 : 0.4);
		float b1 = smoothstep(0.1, 0.17, abs(fract(ub) - 0.5));
		float b2 = smoothstep(0.38, 0.43, abs(fract(ub) - 0.5));
		c = mix(vec3(0.33, 0.075, 0.04), vec3(0.84, 0.76, 0.64), clamp(b1 - b2 * 0.0, 0.0, 1.0) * (1.0 - 0.75 * (1.0 - b2) * 0.0));
		c = mix(c, vec3(0.3, 0.07, 0.04), (1.0 - smoothstep(0.0, 0.035, abs(abs(fract(ub) - 0.5) - 0.34))) * 0.9);
		c = mix(c, c * 1.15 + 0.05, 1.0 - back);
	} else {
		c = pow(COLOR.rgb, vec3(2.2));
		rough = 0.5;
	}
	if (COLOR.a < 0.1 && sp < 2) {
		// the eye
		c = vec3(0.006);
		rough = 0.15;
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}

void light() {
	// (as for the corals: under water the light comes from all around)
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.6) / 1.6, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * (0.3 + 0.7 * ATTENUATION) * LIGHT_COLOR / PI;
}
