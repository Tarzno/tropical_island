shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sea_light.gdshaderinc"
global uniform float world_time;

// Sea turtles (scripts/sea_models.gd: turtle_node()). part 0: the shell; part 1: head and
// flippers. species 0: green turtle (olive-brown shell with darker rays, cream below),
// species 1: hawksbill (amber shell flamed with dark brown: tortoiseshell).
// Shell: UV.x across (-1..1), UV.y front to back (0..1), COLOR.r 1 on the underside,
// COLOR.g 0 in the middle .. 1 at the rim, COLOR.b the way around (0..1).
// Skin: COLOR.g 1 above .. 0 below (dark scales with pale seams above, plain pale below),
// COLOR.a 0 on the eyes.

uniform int part = 0;
uniform int species = 0;

varying vec3 o_pos;
varying vec3 o_nrm;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// distance to the nearest and second nearest cell center: scales
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.3));
			float d = length(g + o * 0.7 + 0.15 - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return vec2(d1, d2);
}

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
}

void fragment() {
	vec3 c;
	float rough = 0.5;
	float spec = 0.4;
	if (part == 0) {
		if (COLOR.r > 0.5) {
			// the underside: cream to yellow, a little darker at the seams
			c = species == 0 ? vec3(0.62, 0.56, 0.36) : vec3(0.6, 0.47, 0.2);
			c *= 0.9 + 0.2 * vn(o_pos.xz * 14.0);
		} else {
			// the scutes: five down the middle, four on either side, a row around the rim
			float px = UV.x;
			float pz = UV.y;
			float r = COLOR.g;
			float mid = 0.27 * (1.0 - 0.35 * abs(pz - 0.42));
			vec2 q;        // place inside the scute, from its growth center
			float id;
			float seam;    // distance to the scute's edge (roughly, in shell lengths)
			if (r > 0.86) {
				float k = COLOR.b * 24.0;
				id = floor(k) + 40.0;
				q = vec2(fract(k) - 0.5, (r - 0.93) * 6.0);
				seam = min((0.5 - abs(fract(k) - 0.5)) * 0.11, r - 0.86);
			} else if (abs(px) < mid) {
				float k = pz * 5.0 + 0.1;
				id = floor(k);
				q = vec2(px / mid * 0.5, fract(k) - 0.62);
				seam = min((mid - abs(px)) * 0.4, (0.5 - abs(fract(k) - 0.5)) * 0.2);
				seam = min(seam, (0.86 - r) * 0.5);
			} else {
				float k = pz * 4.3 - 0.25 + (abs(px) - mid) * 0.5;
				id = floor(k) + 10.0 + step(0.0, px) * 10.0;
				q = vec2((abs(px) - mid) / (0.9 - mid) - 0.25, fract(k) - 0.62);
				seam = min((abs(px) - mid) * 0.4, (0.5 - abs(fract(k) - 0.5)) * 0.23);
				seam = min(seam, (0.86 - r) * 0.5);
			}
			// rays and flames spreading from each scute's center
			float ang = atan(q.y, q.x);
			float d = length(q);
			// (rays near the rim of a scute, blotches at its center: a plain windmill of rays
			// looks drawn)
			float rays = vn(vec2(ang * 2.4 + id * 13.0, d * 3.5 + id * 3.0));
			rays = mix(rays, vn(vec2(ang * 7.0 + id * 5.0, d * 9.0)), 0.3);
			float blot = vn(vec2(px, pz) * 13.0 + id) * 0.65 + vn(vec2(px, pz) * 31.0) * 0.35;
			rays = mix(blot, rays, 0.25 + 0.4 * smoothstep(0.1, 0.5, d));
			if (species == 0) {
				vec3 olive = vec3(0.19, 0.17, 0.085);
				c = mix(olive, vec3(0.06, 0.045, 0.025), smoothstep(0.35, 0.7, rays) * 0.75);
				c = mix(c, vec3(0.3, 0.24, 0.1), smoothstep(0.62, 0.9, 1.0 - rays) * 0.5);
			} else {
				vec3 amber = vec3(0.5, 0.25, 0.05);
				c = mix(amber, vec3(0.05, 0.022, 0.01), smoothstep(0.32, 0.58, rays));
				c = mix(c, vec3(0.75, 0.5, 0.16), smoothstep(0.7, 0.92, 1.0 - rays) * 0.6);
			}
			c *= mix(0.55, 1.0, smoothstep(0.002, 0.009, seam));
			rough = 0.4;
			spec = 0.3;
		}
	} else {
		// scales: dark plates with pale seams above, plain and pale below
		vec2 p2 = abs(o_nrm.y) > 0.55 ? o_pos.xz : vec2(o_pos.z, o_pos.y + o_pos.x * 0.5);
		vec2 cd = cells(p2 * 42.0);
		float seam = smoothstep(0.03, 0.14, cd.y - cd.x);
		vec3 plate = species == 0 ? vec3(0.085, 0.07, 0.045) : vec3(0.04, 0.03, 0.022);
		vec3 pale = species == 0 ? vec3(0.55, 0.5, 0.33) : vec3(0.62, 0.5, 0.22);
		vec3 above = mix(pale, plate, seam);
		c = mix(pale * 1.1, above, smoothstep(0.25, 0.6, COLOR.g));
		rough = 0.45;
	}
	if (COLOR.a < 0.5) {
		c = vec3(0.004);
		rough = 0.12;
		spec = 0.8;
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
