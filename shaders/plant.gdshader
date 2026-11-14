shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// The plants of the summit granite (scripts/land_models.gd: pitcher(), orchid(), and the wild
// vanilla's ropes built by scripts/small_land.gd): colors by vertex (written as sRGB),
// UV2.x = how much a vertex moves in the wind (0 at the root), UV2.y = how waxy it is (the
// pitchers, the orchid's lip). Leathery leaves let a little light through.

global uniform float wind_strength;

varying vec3 v_col;
varying float v_wax;

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	v_wax = UV2.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = UV2.x * (0.5 + 0.5 * wind_strength);
	vec3 push = vec3(sin(TIME * 1.7 + wp.x * 1.9 + wp.z * 0.7), 0.0, cos(TIME * 1.3 + wp.z * 1.6 + wp.x * 0.5))
		+ vec3(sin(TIME * 4.3 + wp.z * 5.0), 0.0, sin(TIME * 3.7 + wp.x * 5.0)) * 0.35;
	// (the push is in the world's axes: turned back into the plant's own)
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * push) * 0.012 * w;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = mix(0.62, 0.3, v_wax);
	SPECULAR = mix(0.3, 0.5, v_wax);
	BACKLIGHT = v_col * 0.35 * (1.0 - v_wax * 0.5);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
