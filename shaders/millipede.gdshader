shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// The Seychelles giant millipede: one body ring per MultiMesh instance (the mesh is
// scripts/land_models.gd: millipede(); scripts/small_land.gd lays the rings along the way
// the head has gone). INSTANCE_CUSTOM: x = the ring's place in the step cycle (radians: the
// script adds the ground covered and the ring's number, so that the steps run along the
// body in waves), y = how much it is walking (0 .. 1), z = which ring this is (0 a body
// ring, 1 the head, 2 the tail, 3 a ring without legs), w = spare.
// COLOR.r says what a vertex belongs to: 0 ring, 0.33 leg, 0.66 head, 1 tail.

uniform vec3 body : source_color = vec3(0.022, 0.016, 0.014);
uniform vec3 band : source_color = vec3(0.1, 0.045, 0.025);
uniform vec3 legs : source_color = vec3(0.34, 0.12, 0.05);

varying float v_part;
varying float v_u;
varying float v_kind;

void vertex() {
	float part = COLOR.r;
	float kind = INSTANCE_CUSTOM.z;
	v_part = part;
	v_u = UV.x;
	v_kind = kind;
	vec3 inside = vec3(0.0, 0.0082, 0.0);
	if (part > 0.2 && part < 0.5) {
		if (kind > 0.5) {
			VERTEX = inside;          // head, tail and collar carry no legs
		} else {
			// each leg swings about its hip: back while its tip is on the ground, forward
			// and a little up while it is lifted
			vec3 hip = vec3(UV.x, 0.0035, UV.y);
			float ph = INSTANCE_CUSTOM.x + UV2.x * 0.9;
			float amt = INSTANCE_CUSTOM.y;
			float a = sin(ph) * 0.5 * amt * sign(UV.x);
			vec3 rel = VERTEX - hip;
			float out_k = COLOR.g;
			rel = vec3(rel.x * cos(a) - rel.z * sin(a), rel.y, rel.x * sin(a) + rel.z * cos(a));
			rel.y += max(-cos(ph), 0.0) * 0.0016 * amt * out_k;
			VERTEX = hip + rel;
		}
	} else if (part > 0.5 && part < 0.8) {
		if (abs(kind - 1.0) > 0.5) {
			VERTEX = inside;
		} else {
			// the feelers tap the ground ahead, in turn
			float w = COLOR.g;
			float me = MODEL_MATRIX[3].x * 11.0;
			VERTEX.y += sin(TIME * 5.0 + me + sign(VERTEX.x) * 1.6) * 0.0022 * w;
			VERTEX.x += sin(TIME * 3.1 + me + sign(VERTEX.x)) * 0.0016 * w;
		}
	} else if (part > 0.8) {
		if (abs(kind - 2.0) > 0.5) {
			VERTEX = inside;
		}
	}
}

void fragment() {
	vec3 c = body;
	float rough = 0.22;
	if (v_part < 0.2) {
		// the hind edge of every ring is a shade browner, and matt in the groove
		float edge = smoothstep(0.62, 0.95, v_u);
		c = mix(body, band, edge * 0.8);
		rough = mix(0.2, 0.5, edge);
	} else if (v_part < 0.5) {
		c = legs;
		rough = 0.45;
	} else if (v_part < 0.8) {
		c = mix(body, legs, 0.25);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
