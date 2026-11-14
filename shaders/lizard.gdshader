shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Seychelles skink (species 0) and green day gecko (species 1).
// Mesh (scripts/small_models.gd: lizard()): forward = -Z, up = +Y, feet at y = 0. UV.x = 0 snout ..
// 1 tail tip, UV.y = the way around the body (0 belly, 0.5 back). COLOR.r = 1 on legs, COLOR.g = leg id
// (0.1 front left, 0.35 front right, 0.6 back left, 0.85 back right), COLOR.b = 1 on the eyes.

uniform int species = 0;
instance uniform float gait = 0.0;    // walk cycle phase (radians)
instance uniform float moving = 0.0;  // 0 still .. 1 running

varying vec3 o_pos;
varying float v_leg;
varying vec2 v_uv;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	o_pos = VERTEX;
	v_leg = COLOR.r;
	v_uv = UV;
	float len = species == 0 ? 0.24 : 0.17;
	float t = clamp((VERTEX.z + len * 0.3) / len, 0.0, 1.0);   // 0 snout .. 1 tail
	// lateral S-wave of the spine while running, a slow tail curl at rest
	// (0.25 was too much of a wriggle. A running skink's body swings
	// a little; it is the tail that waves)
	float wave = sin(gait - t * 6.0) * moving * 0.25 * len * mix(0.4, 0.8, smoothstep(0.45, 0.95, t));
	float rest = sin(TIME * 0.4 + 1.3) * 0.08 * len * (1.0 - moving);
	VERTEX.x += (wave + rest * t * t);
	if (COLOR.r <= 0.5) {
		// at rest the flanks pump with each quick breath
		float flank = smoothstep(0.12, 0.3, t) * (1.0 - smoothstep(0.42, 0.6, t));
		float breath = sin(TIME * 7.5 + dot(MODEL_MATRIX[3].xyz, vec3(1.3, 2.1, 3.7)));
		VERTEX.x *= 1.0 + 0.07 * breath * flank * (1.0 - moving);
	}
	if (COLOR.r > 0.5) {
		// legs: diagonal pairs swing forward/back and lift
		float id = floor(COLOR.g * 4.0);
		float ph = gait + ((id == 0.0 || id == 3.0) ? 0.0 : 3.14159);
		float reach = clamp(abs(VERTEX.x) / (len * 0.25), 0.0, 1.0);
		VERTEX.z += sin(ph) * moving * 0.18 * len * reach;
		VERTEX.y += max(cos(ph), 0.0) * moving * 0.05 * len * reach;
	}
}

void fragment() {
	vec3 c;
	float u = v_uv.x;
	// the way around the body: 0 on the middle of the back .. 0.5 on the middle of the belly
	float down = abs(v_uv.y - 0.5);
	float n = h21(floor(vec2(u * 260.0, v_uv.y * 60.0)));
	float rough = 0.3;
	if (species == 0) {
		// Seychelles skink: bronze back finely speckled, a dark band along the flank from the
		// eye to the root of the tail with a pale line below it, cream belly; glossy
		c = vec3(0.4, 0.29, 0.13) * (0.8 + 0.4 * n);
		c = mix(c, vec3(0.5, 0.4, 0.2), (1.0 - smoothstep(0.02, 0.05, abs(down - 0.1))) * 0.5);
		float band = smoothstep(0.13, 0.16, down) * (1.0 - smoothstep(0.23, 0.26, down)) * smoothstep(0.03, 0.06, u) * (1.0 - smoothstep(0.5, 0.75, u));
		c = mix(c, vec3(0.06, 0.042, 0.03) * (0.8 + 0.6 * n), band);
		float pale = smoothstep(0.25, 0.27, down) * (1.0 - smoothstep(0.3, 0.33, down)) * (1.0 - smoothstep(0.45, 0.7, u));
		c = mix(c, vec3(0.72, 0.66, 0.48), max(pale * 0.8, smoothstep(0.31, 0.36, down)));
		if (v_leg > 0.5) c = vec3(0.3, 0.22, 0.11) * (0.8 + 0.4 * n);
		rough = 0.22;
	} else {
		// green day gecko: vivid green, rust-red spots on the lower back and a red line from the
		// nostril through the eye, the tail turning turquoise, the belly pale
		c = vec3(0.075, 0.5, 0.085) * (0.9 + 0.2 * n);
		vec2 cell = vec2(u * 34.0, v_uv.y * 9.0);
		float spot = step(0.62, h21(floor(cell) + 7.0)) * (1.0 - smoothstep(0.25, 0.42, length(fract(cell) - 0.5)));
		spot *= smoothstep(0.26, 0.32, u) * (1.0 - smoothstep(0.6, 0.7, u)) * (1.0 - smoothstep(0.1, 0.14, down));
		float line = (1.0 - smoothstep(0.012, 0.022, abs(down - 0.13))) * (1.0 - smoothstep(0.09, 0.12, u));
		c = mix(c, vec3(0.7, 0.13, 0.04), max(spot, line));
		c = mix(c, vec3(0.1, 0.55, 0.5), smoothstep(0.6, 0.95, u));
		c = mix(c, vec3(0.78, 0.84, 0.66), smoothstep(0.27, 0.36, down));
		if (v_leg > 0.5) c = vec3(0.09, 0.44, 0.1);
		rough = 0.45;
	}
	if (COLOR.b > 0.5) {
		c = vec3(0.005);
		rough = 0.1;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.6;
}
