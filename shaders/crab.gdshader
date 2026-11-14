shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Ghost crab (and, darker, the rock crabs). The mesh is built by scripts/small_models.gd: crab():
// it walks sideways along x, its front (eyes, claws) is +z, the sand is y = 0.
// The four walking legs of each side are jointed. Every leg vertex is stored relative to its
// bone (UV = along the bone, offset in the leg's plane; UV2.x = offset across; NORMAL likewise;
// COLOR.r 0.25 upper / 0.5 lower bone, COLOR.g which leg, COLOR.b which side). Here each tip
// is planted on the sand and moved through its step, and the knee is put where the two bones
// meet above the line from hip to tip: the legs bend and stretch as the crab walks sideways,
// stands up tall or crouches. The script drives it with the instance uniforms.

uniform vec3 albedo : source_color = vec3(0.16, 0.12, 0.075);
uniform float roughness = 0.6;

instance uniform float gait = 0.0;    // step cycle (radians); runs backward when it walks to its -x side
instance uniform float stride = 0.0;  // 0 standing .. 1 full steps
instance uniform float turn = 0.0;    // stepping around on the spot (-1..1)
instance uniform float lift = 0.0;    // the script raises (+) or lowers (-) the body: the leg tips stay on the sand
instance uniform float tuck = 0.0;    // legs drawn in against the body (crouching, in the burrow)
instance uniform float feed = 0.0;    // claws taking sand to the mouth in turn

// (the same numbers as in small_models.gd: keep the two in step)
const float HIP_X = 0.082;
const float HIP_Y = 0.05;
const float LEG_Z[4] = float[4](0.046, 0.014, -0.02, -0.054);
const float LEG_FAN[4] = float[4](0.55, 0.15, -0.3, -0.75);
const float LEG_REACH[4] = float[4](0.15, 0.168, 0.162, 0.14);
const float L1 = 0.105;
const float L2 = 0.14;

varying vec3 o_pos;

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	o_pos = VERTEX;
	float part = COLOR.r;
	if (part > 0.2 && part < 0.6) {
		int id = int(COLOR.g * 3.0 + 0.5);
		float side = COLOR.b > 0.5 ? 1.0 : -1.0;
		vec3 hip = vec3(side * HIP_X, HIP_Y, LEG_Z[id]);
		vec3 out_dir = vec3(side * cos(LEG_FAN[id]), 0.0, sin(LEG_FAN[id]));
		vec3 tip = hip + out_dir * LEG_REACH[id];
		tip.y = 0.0;
		// alternating tetrapods: legs 1 and 3 of one side step together with 2 and 4 of the other.
		// A planted tip moves back against the travel; a lifted one swings forward
		float ph = gait + PI * mod(float(id) + (side > 0.0 ? 1.0 : 0.0), 2.0);
		float s = sin(ph);
		tip.x += s * 0.035 * stride;
		tip.z += s * 0.03 * turn * side;
		tip.y += max(cos(ph), 0.0) * 0.03 * max(stride, abs(turn)) - lift;
		// drawn in: the tips come in under the knees
		tip.xz = mix(tip.xz, hip.xz + out_dir.xz * 0.05, tuck * 0.85);
		// the knee: above the line from hip to tip, where the two bones meet
		vec3 d = tip - hip;
		float dist = clamp(length(d), 0.05, L1 + L2 - 0.004);
		vec3 dir = normalize(d);
		vec3 u = normalize(vec3(0.0, 1.0, 0.0) - dir * dir.y);
		float a = (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist);
		vec3 knee = hip + dir * a + u * sqrt(max(L1 * L1 - a * a, 0.0));
		vec3 w = normalize(cross(dir, u));
		vec3 org = part < 0.4 ? hip : knee;
		vec3 e = part < 0.4 ? normalize(knee - hip) : normalize(hip + dir * dist - knee);
		vec3 v = cross(w, e);
		VERTEX = org + e * UV.x + v * UV.y + w * UV2.x;
		NORMAL = normalize(e * NORMAL.x + v * NORMAL.y + w * NORMAL.z);
	} else if (part > 0.6) {
		// one claw at a time reaches down and in to the mouth
		float side = sign(VERTEX.x);
		float k = max(sin(TIME * 3.4) * side, 0.0) * feed * UV2.y;
		VERTEX += (vec3(side * 0.012, 0.028, 0.082) - vec3(side * 0.06, 0.026, 0.143)) * k * 0.8;
	}
}

void fragment() {
	vec3 c = albedo;
	float rough = roughness;
	// a fine speckle, as on sand
	c *= 0.78 + 0.44 * h31(floor(o_pos * 700.0));
	if (COLOR.a < 0.25) {
		c = vec3(0.004);          // the eyes
		rough = 0.15;
	} else if (COLOR.a < 0.6) {
		c = mix(c, vec3(0.5, 0.46, 0.38), 0.45);   // the underside
	} else if (COLOR.a < 0.9) {
		c = mix(c, vec3(0.62, 0.58, 0.5), 0.55);   // the fingers of the claws, the feet
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
