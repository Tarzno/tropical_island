shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// The Seychelles snail's body (the mesh is scripts/land_models.gd: snail(); the shell is a
// mesh of its own). `out_k`: 1 crawling, stretched out, the eye stalks up; 0 drawn into
// the shell. The eye stalks go in first and come out last, rolling in from their tips as a
// snail's do. `crawl` is the ground covered: the foot stretches and gathers a little with it.
// COLOR.r = how far a vertex is from the shell (it is drawn in by that much), COLOR.g = how
// far along a tentacle, COLOR.b = 1 on the eyes; UV, UV2.x = the tentacle's root.

instance uniform float out_k = 1.0;
instance uniform float crawl = 0.0;

const vec3 AP = vec3(0.0, 0.012, 0.004);

varying vec3 o_pos;
varying float v_tent;

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
	bool tent = COLOR.g > 0.0 || COLOR.b > 0.5 || UV2.x > 0.0;
	v_tent = tent ? 1.0 : 0.0;
	float me = MODEL_MATRIX[3].x * 9.0 + MODEL_MATRIX[3].z * 5.0;
	if (tent) {
		// the stalks: full length only when the snail is well out; they sway slowly
		vec3 root = vec3(UV.x, UV2.x, UV.y);
		float len_k = smoothstep(0.55, 1.0, out_k);
		vec3 rel = (VERTEX - root) * len_k;
		rel.x += sin(TIME * 0.9 + me + sign(root.x) * 1.7) * 0.0025 * COLOR.g * len_k;
		rel.z += sin(TIME * 0.7 + me * 1.3 + sign(root.x)) * 0.002 * COLOR.g * len_k;
		VERTEX = root + rel;
	} else {
		// the foot stretches at the front and gathers at the back as it glides
		VERTEX.z += sin(crawl * 80.0 + VERTEX.z * 90.0) * 0.0012 * out_k * COLOR.r;
	}
	// drawn in: head and tail pull back under the shell, the body shrinks into the mouth
	float pull = (1.0 - smoothstep(0.0, 0.85, out_k)) * (tent ? 1.0 : COLOR.r * 0.5 + 0.5);
	VERTEX = mix(VERTEX, AP + (VERTEX - AP) * vec3(0.5, 0.45, 0.22), pull);
}

void fragment() {
	// dark slate-brown, grainy, moist; a paler fringe to the foot
	vec3 c = vec3(0.07, 0.058, 0.05) * (0.75 + 0.5 * vn(o_pos * 900.0));
	c = mix(c, vec3(0.2, 0.17, 0.14), smoothstep(0.004, 0.0005, o_pos.y) * (1.0 - v_tent) * 0.7);
	c = mix(c, vec3(0.11, 0.09, 0.08), v_tent * 0.5);
	float rough = 0.42;
	if (COLOR.b > 0.5) {
		c = vec3(0.006);
		rough = 0.1;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
