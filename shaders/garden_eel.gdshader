shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/sea_light.gdshaderinc"

// Spotted garden eels (mesh: scripts/reef_models.gd: garden_eel(), a straight tube along +Y;
// one MultiMesh per colony, scripts/reef_life.gd). The eel stands in its burrow: what is not
// out of the sand is pushed down under it; what is out rises straight and then bends over
// toward +X (the instance is turned to face the current), like a question mark.
// INSTANCE_CUSTOM: r = how far it is out (0 gone .. 1 as far as it ever comes), g = its own
// phase, b = how far it bends over (0 straight .. 1), a = a nod of the head (feeding).
// UV.y = the place along the body (0 the tail end .. 1 the snout), UV.x = the way around;
// VERTEX.xz = the offset from the body's line. COLOR.a = 0: the eyes.

global uniform float world_time;
const float LEN = 0.42;

varying vec2 v_uv;
varying float v_above;

void vertex() {
	v_uv = UV;
	float outl = INSTANCE_CUSTOM.r * 0.68 * LEN;       // a third of it never leaves the burrow
	float a = UV.y * LEN - (LEN - outl);               // how far above the sand, along the body
	v_above = a;
	vec2 ring = VERTEX.xz;
	vec3 w0 = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (a <= 0.0) {
		VERTEX = vec3(ring.x, a, ring.y);
	} else {
		float f = a / max(outl, 0.01);
		float a0 = outl * 0.45;
		float hook = INSTANCE_CUSTOM.b * (1.0 + 0.35 * INSTANCE_CUSTOM.a * sin(world_time * 5.0 + INSTANCE_CUSTOM.g * 40.0));
		float rad = max(outl * 0.5, 0.03) / max(hook, 0.05);
		float beta = max(a - a0, 0.0) / rad;
		vec2 c = a < a0 ? vec2(0.0, a) : vec2(rad * (1.0 - cos(beta)), a0 + rad * sin(beta));
		// (below the bend it leans back a little: an S, not a walking stick)
		c.x -= sin(min(f * 1.7, 1.0) * 3.14159) * 0.11 * outl;
		// the stalk leans to and fro as the swell passes, and sways a little by itself
		float t = world_time;
		float ph = INSTANCE_CUSTOM.g * 6.2831;
		float lean = (sin(t * 1.25 + w0.x * 0.55 + w0.z * 0.31) * 0.11 + sin(t * 0.6 + ph) * 0.06) * f * f * outl;
		float side = sin(t * 0.83 + ph * 2.0 + a * 9.0) * 0.07 * f * outl;
		vec3 tang = vec3(sin(beta), cos(beta), 0.0);
		vec3 nrm = vec3(cos(beta), -sin(beta), 0.0);
		VERTEX = vec3(c.x + lean, c.y, side) + nrm * ring.x + vec3(0.0, 0.0, 1.0) * ring.y;
		NORMAL = normalize(nrm * NORMAL.x + tang * NORMAL.y + vec3(0.0, 0.0, 1.0) * NORMAL.z);
	}
	// never much thinner than a pixel (like the urchins' spines): from the surface they are
	// four or five meters away
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * clamp(dist * 0.0009 - 0.003, 0.0, 0.006);
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	if (v_above < -0.004) {
		discard;
	}
	// white to cream, peppered with small black spots; a big black blotch at the gill
	// opening and one half-way down the body
	vec3 c = vec3(0.82, 0.8, 0.72);
	vec2 g = vec2(v_uv.x * 7.0, v_uv.y * 95.0);
	vec2 cell = floor(g);
	vec2 o = vec2(h21(cell), h21(cell + 7.7)) * 0.5 + 0.25;
	float dot_ = 1.0 - smoothstep(0.16, 0.26, length(fract(g) - o));
	c = mix(c, vec3(0.03), dot_ * step(0.25, h21(cell + 1.3)) * step(v_uv.y, 0.97));
	float side = 1.0 - smoothstep(0.1, 0.17, min(abs(v_uv.x - 0.25), abs(v_uv.x - 0.75)));
	float blotch = (1.0 - smoothstep(0.012, 0.02, abs(v_uv.y - 0.885))) * side;
	blotch += (1.0 - smoothstep(0.01, 0.018, abs(v_uv.y - 0.6))) * (1.0 - smoothstep(0.08, 0.14, abs(v_uv.x - 0.5)));
	c = mix(c, vec3(0.02), clamp(blotch, 0.0, 1.0));
	float rough = 0.45;
	if (COLOR.a < 0.5) {
		c = vec3(0.01);
		rough = 0.15;
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.6) / 1.6, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * (0.3 + 0.7 * ATTENUATION) * LIGHT_COLOR / PI;
}
