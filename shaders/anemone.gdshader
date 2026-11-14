shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sea_light.gdshaderinc"

// Sea anemones (meshes: scripts/reef_models.gd, placed by scripts/seabed.gd as MultiMeshes with
// an instance color: the color of disc and tentacles).
// UV.y = how far up its tentacle a vertex is (0 on the disc and the column), UV.x = the
// tentacle's own phase; COLOR.rgb = a shade times the instance color; COLOR.a = 1 tentacles
// and disc, 0.5 the column (it has a color of its own, picked by the instance's number).
// On the disc the vertex's blue is 1 at the margin, which lifts and falls.

global uniform float world_time;
uniform float sway = 0.3;          // how far the tips go (in units of the disc's radius)
uniform float flap = 0.04;         // the margin of the disc
uniform bool vivid_column = false; // the magnificent anemone's column: purple, magenta, blue ..

varying float v_tip;
varying float v_id;
varying vec3 o_pos;

float h11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	o_pos = VERTEX;
	v_tip = UV.y;
	v_id = float(INSTANCE_ID);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = world_time;
	float ph = UV.x * 6.2831;
	if (UV.y > 0.0) {
		// the swell passing overhead lays all the tentacles over one way and back again; each
		// one also writhes a little by itself
		float k = UV.y * UV.y;
		float surge = sin(t * 1.25 + w.x * 0.55 + w.z * 0.31) * 0.65 + sin(t * 0.47 + w.z * 0.2) * 0.4;
		VERTEX.x += (surge * 0.75 + sin(t * 0.9 + ph) * 0.4) * sway * k;
		VERTEX.z += (-surge * 0.2 + cos(t * 0.7 + ph * 1.7) * 0.4) * sway * k;
		VERTEX.y -= (abs(surge) * 0.3 + 0.1) * sway * k;
	} else if (COLOR.a > 0.9) {
		float m = smoothstep(0.7, 1.0, length(VERTEX.xz));
		VERTEX.y += m * sin(t * 0.8 + UV.x * 3.0 + w.x * 0.5) * flap;
	}
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float rough = 0.5;
	if (COLOR.a < 0.75) {
		if (vivid_column) {
			float pick = h11(v_id + 3.7);
			vec3 col = pick < 0.34 ? vec3(0.28, 0.035, 0.42) : (pick < 0.6 ? vec3(0.55, 0.03, 0.22) : (pick < 0.8 ? vec3(0.06, 0.1, 0.5) : vec3(0.4, 0.12, 0.06)));
			c = col * (0.75 + 0.5 * vn(o_pos * 9.0));
			rough = 0.3;
		} else {
			// the carpet anemone's underside: pale, with small orange warts
			c = vec3(0.6, 0.55, 0.45);
			c = mix(c, vec3(0.75, 0.25, 0.1), smoothstep(0.7, 0.78, vn(o_pos * 38.0)));
		}
	} else {
		// tentacles: paler toward the ends; the disc between them a little darker, mottled
		c *= mix(0.62 + 0.4 * vn(o_pos * 21.0), 1.0, smoothstep(0.0, 0.3, v_tip));
		c = mix(c, c * 1.3 + vec3(0.05, 0.06, 0.04), smoothstep(0.55, 1.0, v_tip));
		// the mouth: a dark slit in the middle of the disc
		c *= mix(0.3, 1.0, max(smoothstep(0.03, 0.07, length(o_pos.xz * vec2(1.0, 2.2))), step(0.001, v_tip)));
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	// (light shines through the tentacles)
	BACKLIGHT = c * 0.3 * smoothstep(0.1, 0.6, v_tip);
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.75) / 1.75, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * (0.35 + 0.65 * ATTENUATION) * LIGHT_COLOR / PI;
}
