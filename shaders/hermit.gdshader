shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Land hermit crab (the part outside the shell). The mesh is built by scripts/land_models.gd:
// hermit(): it walks forward (-z), the sand is y = 0, the shell's mouth is at AP.
// The two walking legs of each side are jointed as the ghost crab's are (crab.gdshader):
// every leg vertex is stored relative to its bone, each tip is planted on the sand and
// moved through its step, and the knee is put where the two bones meet. `tuck` draws the
// whole animal back into the shell, the big left claw last, like a door.

instance uniform vec3 tint : source_color = vec3(0.5, 0.4, 0.3);
instance uniform float speckle = 0.0;  // white grains on the armor (the strawberry hermit crab)
instance uniform float gait = 0.0;     // step cycle (radians)
instance uniform float stride = 0.0;   // 0 standing .. 1 full steps
instance uniform float lift = 0.0;     // the script raises (+) the body: the leg tips stay on the sand
instance uniform float tuck = 0.0;     // 0 out .. 1 drawn into the shell
instance uniform float feed = 0.0;     // the small claw picking at the sand

// (the same numbers as in land_models.gd: keep the two in step)
const vec3 AP = vec3(0.0, 0.019, 0.012);
const float HIP_X[2] = float[2](0.008, 0.0085);
const float HIP_Y = 0.017;
const float HIP_Z[2] = float[2](-0.004, 0.004);
const float FAN[2] = float[2](0.7, 1.75);
const float REACH[2] = float[2](0.040, 0.044);
const float L1 = 0.024;
const float L2 = 0.034;

varying vec3 o_pos;

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	o_pos = VERTEX;
	float part = COLOR.r;
	float me = MODEL_MATRIX[3].x * 13.0 + MODEL_MATRIX[3].z * 7.0;
	if (part > 0.2 && part < 0.6) {
		int id = int(COLOR.g + 0.5);
		float side = COLOR.b > 0.5 ? 1.0 : -1.0;
		vec3 hip = vec3(side * HIP_X[id], HIP_Y, HIP_Z[id]);
		vec3 out_dir = vec3(side * sin(FAN[id]), 0.0, -cos(FAN[id]));
		vec3 tip = hip + out_dir * REACH[id];
		tip.y = 0.0;
		// the front leg of one side steps with the second leg of the other. A planted tip goes
		// back under the body; a lifted one swings forward
		float ph = gait + PI * mod(float(id) + (side > 0.0 ? 1.0 : 0.0), 2.0);
		tip.z -= sin(ph) * 0.011 * stride;
		tip.y += max(cos(ph), 0.0) * 0.007 * stride - lift;
		// drawn in: the tips come in under the body
		tip.xz = mix(tip.xz, hip.xz + out_dir.xz * 0.014, tuck);
		tip.y = mix(tip.y, hip.y - 0.006, tuck);
		vec3 d = tip - hip;
		float dist = clamp(length(d), 0.012, L1 + L2 - 0.002);
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
		// the small right claw picks at the sand and goes to the mouth
		float side = sign(VERTEX.x);
		float k = max(sin(TIME * 2.6 + me), 0.0) * feed * UV2.y * max(side, 0.0);
		VERTEX += vec3(-0.004, 0.006, 0.008) * k;
	} else {
		// the feelers are never still
		float wv = UV2.y * (1.0 - tuck);
		VERTEX.x += sin(TIME * 6.3 + me + sign(VERTEX.x) * 1.3) * 0.0035 * wv;
		VERTEX.y += sin(TIME * 4.7 + me * 1.7 + sign(VERTEX.x) * 2.1) * 0.003 * wv;
	}
	// into the shell: everything shrinks toward the mouth and slips back
	VERTEX = mix(VERTEX, AP + (VERTEX - AP) * 0.52 + vec3(0.0, 0.0, 0.009), smoothstep(0.0, 1.0, tuck));
}

void fragment() {
	vec3 c = tint;
	float rough = 0.5;
	float grain = h31(floor(o_pos * 2600.0));
	c *= 0.8 + 0.4 * h31(floor(o_pos * 1500.0));
	c = mix(c, vec3(0.85, 0.82, 0.76), step(0.86, grain) * speckle);
	if (COLOR.a < 0.2) {
		c = vec3(0.004);                       // the eyes
		rough = 0.12;
	} else if (COLOR.a < 0.5) {
		c *= 0.25;                             // the dark tips of the feet
	} else if (COLOR.a < 0.7) {
		c = mix(c, vec3(0.6, 0.52, 0.4), 0.6); // the eye stalks
	} else if (COLOR.a < 0.9) {
		c = mix(c, c * vec3(0.55, 0.4, 0.6), 0.6);   // the big claw: darker, a little purple
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
