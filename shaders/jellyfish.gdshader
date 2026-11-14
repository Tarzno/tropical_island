shader_type spatial;
// The moon jellyfish (scripts/jellyfish.gd: a MultiMesh; one mesh of a bell, its inner
// side, the fringe of fine tentacles around its rim and the four frilled arms under it).
// COLOR.r: how far out on the bell (0 the top .. 1 the rim); COLOR.g: which part (0 the
// bell's outside, 0.25 its inside, 0.5 the fringe, 0.75 an arm); COLOR.b: how far along a
// tentacle or an arm (0 where it hangs .. 1 its end). UV: the place seen from above, for
// the four rings. UV2.x: around the rim (the fringe's threads); UV2.y: a number per arm.
// INSTANCE_CUSTOM.x: where it is in its beat (0 .. 1); .y: a number of its own.
//
// Drawn as clear jelly, blended: so it must veil itself with the water's color (the
// veil over the picture, shaders/underwater.gdshader, goes by the depth of what is solid,
// and would hide it). The script draws it after that veil when the eye is under water,
// and before the sea's surface when the eye is above it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/sea_light.gdshaderinc"
global uniform float world_time;

uniform float light = 1.0;          // daylight (1 day .. 0.08 night), as the veil has it
uniform bool under = true;          // the eye is under water
uniform vec3 water_color : source_color = vec3(0.04, 0.36, 0.42);
uniform float density = 0.075;
uniform float still = 0.0;          // (for the previewer: 1 stops the swaying)

varying float v_part;
varying float v_out;
varying float v_len;
varying vec3 w_pos;
varying float v_beat;

// How far the bell is drawn together: quickly in, slowly out again.
float beat(float ph) {
	ph = fract(ph);
	return ph < 0.28 ? smoothstep(0.0, 0.28, ph) : 1.0 - smoothstep(0.28, 1.0, ph);
}

void vertex() {
	v_part = COLOR.g;
	v_out = COLOR.r;
	v_len = COLOR.b;
	float seed = INSTANCE_CUSTOM.y;
	// (what hangs from the bell follows it late: the beat runs down the tentacles)
	float c = beat(INSTANCE_CUSTOM.x - v_len * 0.07);
	v_beat = c;
	vec3 p = VERTEX;
	// the rim is drawn in and down, the top lifts a little
	p.xz *= 1.0 - c * 0.3 * pow(v_out, 1.5);
	p.y += c * (0.03 * (1.0 - v_out) - 0.2 * v_out * v_out);
	if (v_part > 0.4) {
		float t = world_time * (1.0 - still);
		p.x += sin(t * 1.1 + seed * 17.0 + v_len * 3.5 + UV2.y * 2.0) * 0.08 * v_len;
		p.z += cos(t * 0.9 + seed * 11.0 + v_len * 3.0 + UV2.y * 1.3) * 0.08 * v_len;
		// (drawn in under the bell as it closes, trailing out as it opens)
		p.xz *= 1.0 - c * 0.25 * v_len;
	}
	VERTEX = p;
	w_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	vec3 col = vec3(0.84, 0.92, 1.0);
	float a;
	if (v_part < 0.4) {
		// the bell: clear in the middle, milky where one looks along it; its rim a pale line
		a = (v_part < 0.1 ? 0.13 : 0.07) + 0.5 * rim + 0.3 * smoothstep(0.9, 1.0, v_out);
		// faint canals running out to the rim
		vec2 q = UV * 2.0 - 1.0;
		float ang = atan(q.y, q.x);
		a += 0.05 * smoothstep(0.75, 1.0, abs(sin(ang * 8.0))) * smoothstep(0.35, 0.6, length(q));
		// the four rings (its gonads): horseshoes, open toward the middle
		float ring = 0.0;
		for (int k = 0; k < 4; k++) {
			float ka = (float(k) + 0.5) * 1.5708;
			vec2 mid = vec2(cos(ka), sin(ka)) * 0.36;
			vec2 d = q - mid;
			float r = smoothstep(0.05, 0.022, abs(length(d) - 0.15));
			r *= smoothstep(0.75, 0.45, dot(normalize(d + vec2(1e-5)), -normalize(mid)));
			ring = max(ring, r);
		}
		col = mix(col, vec3(0.8, 0.56, 0.84), ring);
		a = max(a, ring * 0.72);
	} else if (v_part < 0.6) {
		// the fringe: many fine threads
		float thread = smoothstep(0.6, 0.95, abs(sin(UV2.x * 3.14159 * 150.0)));
		a = 0.3 * thread * (1.0 - 0.8 * v_len);
	} else {
		// the arms: frilled ribbons, clearer toward their ends
		a = (0.2 + 0.25 * rim) * (1.0 - 0.6 * v_len);
		col = vec3(0.9, 0.9, 1.0);
	}
	// lit from above, and the net of light plays on it
	float lit = light * (0.8 + 0.5 * sea_light(w_pos, vec3(0.0, 1.0, 0.0), world_time));
	col *= lit;
	if (under) {
		// the water between the eye and it (as the veil does it)
		float dist = length(VERTEX);
		float deep = clamp(-(CAMERA_POSITION_WORLD.y + (w_pos.y - CAMERA_POSITION_WORLD.y) * 0.5) / 12.0, 0.0, 1.0);
		vec3 water = mix(water_color, water_color * vec3(0.35, 0.6, 0.8), deep) * light;
		float veil = clamp(0.07 + 0.93 * (1.0 - exp(-dist * density)), 0.0, 1.0);
		col = mix(col, water, veil);
		a *= 1.0 - 0.75 * smoothstep(0.55, 1.0, veil);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
