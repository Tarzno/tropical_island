shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/sea_light.gdshaderinc"
global uniform float world_time;

// A moray looking out of its hole (mesh: scripts/reef_models.gd: moray(); one MeshInstance3D
// each, set by scripts/reef_life.gd at the mouth of its den with -Z pointing out of the hole).
// The mesh is the straight animal: VERTEX = (across, up, distance behind the snout). The
// shader lays `out_len` of it outside, along a line that leaves the hole straight and then
// turns the head by `turn` and `lift`; the rest stays inside, on the hole's axis.
// species 0: honeycomb moray (pale, with black blotches in a net of pale lines);
// species 1: giant moray (brown, darker blotches, small dark spots on the head).
// COLOR.r = 1: the inside of the mouth; COLOR.b = 1: the lower jaw (opens by `gape`);
// COLOR.a = 0: the eyes (UV.x = 1 in the middle: the pupil).

uniform int species = 0;
instance uniform float out_len = 0.3;   // meters of it outside the hole
instance uniform float turn = 0.0;      // the head's bearing against the hole's axis (rad, + = left)
instance uniform float lift = 0.0;      // ... and how much it is raised (rad)
instance uniform float gape = 0.15;     // the lower jaw (rad)
instance uniform float sway = 0.0;      // the phase of the slow weaving of the neck

const float HINGE = 0.115;

varying vec3 o_pos;

vec3 dir_at(float a) {
	float f = clamp(a / max(out_len, 0.02), 0.0, 1.0);
	float e = f * f * (3.0 - 2.0 * f);
	float yaw = turn * e + 0.22 * sin(sway - a * 7.0) * f;
	float pit = lift * e + 0.07 * sin(sway * 0.7 + 1.0 - a * 5.0) * f;
	return vec3(-sin(yaw) * cos(pit), sin(pit), -cos(yaw) * cos(pit));
}

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	o_pos = v;
	if (COLOR.b > 0.5) {
		// the lower jaw swings down about its hinge
		float d = HINGE - v.z;
		float yy = v.y + 0.004;
		float c = cos(gape);
		float s = sin(gape);
		v.z = HINGE - (d * c + yy * s);
		v.y = -0.004 + (yy * c - d * s);
		float nz = -n.z;
		float nn = n.y;
		n.z = -(nz * c + nn * s);
		n.y = nn * c - nz * s;
	}
	float a = out_len - v.z;       // how far out of the hole this part of the body is
	if (a <= 0.0) {
		VERTEX = vec3(v.x, v.y, -a);
		NORMAL = n;
	} else {
		vec3 p = vec3(0.0);
		float da = a / 8.0;
		for (int i = 0; i < 8; i++) {
			p += dir_at((float(i) + 0.5) * da) * da;
		}
		vec3 t = dir_at(a);
		vec3 sd = normalize(cross(t, vec3(0.0, 1.0, 0.0)));
		vec3 up = cross(sd, t);
		VERTEX = p + sd * v.x + up * v.y;
		NORMAL = normalize(sd * n.x + up * n.y - t * n.z);
	}
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// distances to the nearest and the second nearest of a scatter of points
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 9.0;
	float f2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.3));
			float d = length(g + o * 0.8 + 0.1 - f);
			if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
		}
	}
	return vec2(f1, f2);
}

void fragment() {
	// where on the skin: along the body, and the way around it
	float ang = atan(o_pos.x, o_pos.y + 0.002);
	vec2 q = vec2(o_pos.z, ang * 0.045);
	if (abs(o_pos.x) < 0.0005 && o_pos.y > 0.04) {
		q.y = (o_pos.y - 0.055) * 0.8;      // the fin on the back
	}
	float back = smoothstep(-0.02, 0.04, o_pos.y);
	vec3 c;
	float rough = 0.3;
	if (species == 0) {
		// the blotches are small on the head and grow along the body
		float k = mix(42.0, 24.0, smoothstep(0.03, 0.3, o_pos.z));
		vec2 f = cells(q * k);
		float net = smoothstep(0.05, 0.16, f.y - f.x);
		c = mix(vec3(0.84, 0.8, 0.66), vec3(0.025, 0.022, 0.02), net);
	} else {
		c = mix(vec3(0.46, 0.34, 0.16), vec3(0.3, 0.2, 0.09), back);
		vec2 f = cells(q * 17.0 + 3.0);
		float blot = (1.0 - smoothstep(0.2, 0.38, f.x)) * smoothstep(0.1, 0.25, o_pos.z) * (0.45 + 0.55 * back);
		c = mix(c, vec3(0.06, 0.04, 0.025), blot * 0.85);
		vec2 f2 = cells(q * 70.0);
		c = mix(c, vec3(0.05, 0.035, 0.02), (1.0 - smoothstep(0.12, 0.22, f2.x)) * (1.0 - smoothstep(0.12, 0.22, o_pos.z)) * 0.8);
	}
	if (COLOR.r > 0.5) {
		c = species == 0 ? vec3(0.78, 0.7, 0.66) : vec3(0.62, 0.5, 0.34);
		rough = 0.5;
	}
	if (COLOR.a < 0.5) {
		c = mix(species == 0 ? vec3(0.8, 0.78, 0.7) : vec3(0.7, 0.55, 0.2), vec3(0.01), smoothstep(0.45, 0.6, UV.x));
		rough = 0.12;
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.6) / 1.6, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * (0.3 + 0.7 * ATTENUATION) * LIGHT_COLOR / PI;
}
