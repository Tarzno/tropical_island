shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Bill, eyes, folded wings, tail and legs of a code-built bird (scripts/bird_models.gd),
// colored by vertex, for a bird whose head bobs as it walks (the barred ground dove):
// the same push as in bird.gdshader, so that bill and eyes go with the head.

uniform float bob_z = 1000.0;        // vertices further forward than this are the head
instance uniform float bob = 0.0;    // how far the head is pushed forward now (m; negative: back)

varying vec3 v_col;

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	VERTEX.z -= bob * smoothstep(bob_z * 0.65, bob_z, -VERTEX.z);
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.6;
}
