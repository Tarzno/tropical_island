shader_type spatial;
// Drops that fall from the rims of the grotto's roof gaps and from the tips of the roots
// that hang through them, and the small splash where each lands (scripts/weather.gd: a
// MultiMesh of quads; the instance's place is the drop's, INSTANCE_CUSTOM: x its length (a
// drop is drawn as long as it falls while the eye holds it) or the splash's width, y its
// width (a splash: a number of its own, for its shape), z how well it shows, w 0 a drop /
// 1 a splash).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform float light = 1.0;         // daylight

varying float v_alpha;
varying float v_kind;
varying vec2 v_uv;
varying float v_seed;

void vertex() {
	v_uv = UV;
	v_alpha = INSTANCE_CUSTOM.z;
	v_kind = INSTANCE_CUSTOM.w;
	v_seed = INSTANCE_CUSTOM.y;
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float dist = length(to_cam);
	vec3 wp;
	if (v_kind < 0.5) {
		// upright, turned to the eye; never much thinner than a pixel
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		float wide = max(INSTANCE_CUSTOM.y, dist * 0.0019);
		wp = center + side * (VERTEX.x * wide) + vec3(0.0, VERTEX.y * INSTANCE_CUSTOM.x, 0.0);
	} else {
		// flat on the ground
		wp = center + vec3(VERTEX.x, 0.0, VERTEX.y) * INSTANCE_CUSTOM.x;
	}
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	float a;
	if (v_kind < 0.5) {
		// the drop at the lower end, its trail fading out above it
		float across = 1.0 - abs(v_uv.x - 0.5) * 2.0;
		a = across * pow(v_uv.y, 1.6) * smoothstep(1.0, 0.86, v_uv.y);
	} else {
		// what the drop throws up from the sand: a broken ring of specks that widens (z fades
		// it), each splash its own (v_seed), and the drop's own speck in the middle
		vec2 c = v_uv - 0.5;
		float r = length(c) * 2.0;
		float ang = atan(c.y, c.x);
		float specks = smoothstep(0.35, 0.9, 0.5 + 0.5 * sin(ang * 7.0 + v_seed * 60.0)) * (0.6 + 0.4 * sin(ang * 3.0 + v_seed * 23.0));
		a = smoothstep(0.5, 0.78, r) * smoothstep(1.0, 0.84, r) * specks * 0.8 + smoothstep(0.3, 0.0, r) * 0.5;
	}
	ALBEDO = vec3(0.86, 0.9, 0.94) * light;
	ALPHA = v_alpha * a;
}
