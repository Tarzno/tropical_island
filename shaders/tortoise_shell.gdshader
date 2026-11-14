shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Aldabra giant tortoise carapace. The scute layout (5 vertebrals, 4 costal pairs,
// a ring of marginals) is derived from the object-space position on the dome; each
// scute gets dark seams, concentric growth rings and a smooth, worn, paler center.
// Mesh: forward = -Z, up = +Y, origin on the ground. Blender v = 0 at the top .. 1 at the rim (>1 underside).

uniform vec3 base_color : source_color = vec3(0.15, 0.12, 0.085);
uniform vec3 worn_color : source_color = vec3(0.42, 0.37, 0.3);
uniform vec3 seam_color : source_color = vec3(0.02, 0.017, 0.014);
uniform vec3 dust_color : source_color = vec3(0.55, 0.48, 0.38);

varying vec3 o_pos;
varying vec3 o_nrm;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
}

void fragment() {
	float s = 1.0 - UV.y;   // glTF flips V: Blender v (0 top .. 1 rim) arrives as 1 - v
	// position on the unit disk seen from above (x across, y along; head at -Z)
	vec2 d = vec2(o_pos.x / 0.43, -o_pos.z / 0.56);
	float ang = atan(d.y, d.x);
	vec2 p = normalize(d + 1e-5) * min(s, 1.0);
	float edge;      // distance to the nearest scute seam
	float cell;      // scute id (for per-scute variation)
	float ring_r = 0.84;
	if (s > ring_r) {
		// marginals: 24 around the rim
		float k = ang / 6.28318 * 24.0;
		float fk = fract(k);
		edge = min(min(fk, 1.0 - fk) * 0.22, (s - ring_r) * 0.9);
		edge = min(edge, max(1.02 - s, 0.0));
		cell = floor(k) + 100.0;
	} else {
		float vw = 0.2 + 0.03 * cos(p.y * 3.0);    // half width of the vertebral row
		float yb = (p.y + ring_r) / (2.0 * ring_r);  // 0 back .. 1 front
		if (abs(p.x) < vw) {
			float k = yb * 5.0;
			float fk = fract(k);
			edge = min(min(fk, 1.0 - fk) * 2.0 * ring_r / 5.0, vw - abs(p.x));
			cell = floor(k);
		} else {
			// costals: 4 per side, seams slightly fanned outward
			float yy = p.y + (abs(p.x) - vw) * 0.25 * sign(p.y);
			float k = (yy + ring_r) / (2.0 * ring_r) * 4.0;
			float fk = fract(k);
			edge = min(min(fk, 1.0 - fk) * 2.0 * ring_r / 4.0, abs(p.x) - vw);
			cell = floor(k) + (p.x > 0.0 ? 10.0 : 20.0);
		}
		edge = min(edge, ring_r - s);
	}
	float rnd = h21(vec2(cell, 3.7));
	float seam = 1.0 - smoothstep(0.006, 0.018, edge);
	// concentric growth annuli, strongest near the seams, smoothed away in the worn center
	float rings = sin(edge * 330.0) * 0.5 + 0.5;
	float center = smoothstep(0.03, 0.09, edge);
	vec3 c = base_color * (0.85 + 0.3 * rnd);
	c = mix(c, c * (0.6 + 0.6 * rings), 1.0 - center * 0.85);
	c = mix(c, worn_color * (0.9 + 0.2 * rnd), center * 0.45 * smoothstep(0.9, 0.2, s));
	c = mix(c, seam_color, seam);
	// dust and dried mud on the lower flanks and in the seams
	float up = clamp(o_nrm.y, 0.0, 1.0);
	c = mix(c, dust_color * 0.6, smoothstep(0.75, 1.0, s) * 0.35 + seam * 0.15 * up);
	if (s > 1.0) c = vec3(0.16, 0.13, 0.1);   // plastron
	ALBEDO = c;
	ROUGHNESS = mix(0.45, 0.85, 1.0 - center * 0.6);
	SPECULAR = 0.35;
	// seams cut slightly into the surface
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.0;
	AO = 1.0 - seam * 0.6;
	AO_LIGHT_AFFECT = 0.3;
}
