shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Plumage of the seabirds' bodies. The body is a loft (tools/assets4.py: bird(), perched()):
// UV.x runs from the base of the bill (0) back to the rump (~0.8), UV.y around the body (0 and 1
// along the back, 0.5 along the belly). The colors are painted from these: a back and an
// underside, an optional cap on the head (the crested tern's black cap, the noddy's pale
// forehead fading back into brown) and an optional breast patch (the female frigatebird's white).

uniform vec3 upper : source_color = vec3(1.0);
uniform vec3 under : source_color = vec3(1.0);
uniform float upper_from = 0.0;     // the back color starts here (a white neck in front of it)
uniform float under_edge = -0.2;    // how far down the sides the back color reaches (1 back .. -1 belly)
uniform vec3 cap : source_color = vec3(0.0);
uniform float cap_from = 0.0;
uniform float cap_to = 0.0;         // 0: no cap
uniform float cap_soft = 0.03;      // how gradually it ends toward the nape
uniform float cap_side = 0.3;       // how far down the sides of the head it reaches
uniform vec3 breast : source_color = vec3(1.0);
uniform float breast_from = 0.0;
uniform float breast_to = 0.0;      // 0: no breast patch
uniform float roughness = 0.75;
// (off unless set; the birds of scripts/shorebirds.gd use them) a stripe along the side of the
// head through the eye (the tropicbird's black mask), and a mottling of the upper side with
// pale feather edges (turnstone, heron)
uniform vec3 stripe : source_color = vec3(0.0);
uniform float stripe_from = 0.0;
uniform float stripe_to = 0.0;      // 0: no stripe
uniform float stripe_at = 0.25;     // where on the side (1 back .. -1 belly)
uniform float stripe_w = 0.2;
uniform float mottle = 0.0;
uniform vec3 mottle_color : source_color = vec3(1.0);

float bh21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// A head that bobs as the bird walks (the barred ground dove: scripts/land_birds.gd sets
// `bob` on the standing body): everything further forward than bob_z is pushed along the
// body's axis, the neck stretching with it. (shaders/bird_parts.gdshader does the same.)
uniform float bob_z = 1000.0;
instance uniform float bob = 0.0;

void vertex() {
	VERTEX.z -= bob * smoothstep(bob_z * 0.65, bob_z, -VERTEX.z);
}

void fragment() {
	float u = UV.x;
	float top = cos(UV.y * 6.2831);
	float back = smoothstep(under_edge - 0.2, under_edge + 0.2, top) * smoothstep(upper_from - 0.04, upper_from + 0.04, u);
	vec3 c = mix(under, upper, back);
	float b = smoothstep(breast_from - 0.03, breast_from + 0.03, u) * (1.0 - smoothstep(breast_to - 0.06, breast_to + 0.06, u))
		* (1.0 - smoothstep(-0.35, 0.25, top));
	c = mix(c, breast, b * step(0.001, breast_to));
	float k = smoothstep(cap_from - 0.012, cap_from + 0.012, u) * (1.0 - smoothstep(cap_to - cap_soft, cap_to, u))
		* smoothstep(cap_side - 0.12, cap_side + 0.12, top);
	c = mix(c, cap, k * step(0.001, cap_to));
	if (mottle > 0.0) {
		// rows of feathers, each with a pale edge
		vec2 f = vec2(u * 46.0, UV.y * 22.0);
		f.y += 0.5 * floor(f.x);
		vec2 g = fract(f) - 0.5;
		float edge = smoothstep(0.25, 0.48, length(g * vec2(1.0, 0.8)) + 0.12 * (bh21(floor(f)) - 0.5));
		c = mix(c, mix(c * 0.7, mottle_color, edge), mottle * back * smoothstep(0.16, 0.24, u));
	}
	if (stripe_to > 0.0) {
		float st = smoothstep(stripe_from - 0.01, stripe_from + 0.01, u) * (1.0 - smoothstep(stripe_to - 0.03, stripe_to, u))
			* (1.0 - smoothstep(stripe_w * 0.6, stripe_w, abs(top - stripe_at + (u - stripe_from) * 1.2)));
		c = mix(c, stripe, st);
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}
