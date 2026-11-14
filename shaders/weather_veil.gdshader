shader_type spatial;
// What a rain shower puts between the eye and the distance (a quad that always fills the
// screen; scripts/weather.gd shows it while there is weather): the gray of the falling rain,
// thicker the further one looks, and the rainbow: a ring of 42 degrees around the point
// straight away from the sun, red outside, with the fainter second bow at 51 degrees the
// other way around and the sky a little brighter inside the first. It stands in the rain,
// not on the sky: so it shows in front of far hills and islands too, and not in front of
// what is near.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float haze = 0.0;                  // how thick the rain hangs in the air: 0 .. 1
uniform vec3 haze_color : source_color = vec3(0.42, 0.46, 0.5);
uniform float bow = 0.0;                   // the rainbow: 0 .. 1
uniform vec3 away_from_sun = vec3(0.0, -0.5, 0.86);
uniform float light = 1.0;
global uniform float sea_level;
uniform vec3 sun_light = vec3(1.0);        // the sun's color and strength: a bow at sunset is red and dim

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// the colors across a bow, 0 violet (inside) .. 1 red (outside)
vec3 spectrum(float x) {
	vec3 c = clamp(vec3(1.5 - abs(4.0 * x - 3.0), 1.5 - abs(4.0 * x - 2.0), 1.5 - abs(4.0 * x - 1.0)), 0.0, 1.0);
	c.r += 0.45 * (1.0 - smoothstep(0.0, 0.22, x));
	return c;
}

void fragment() {
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	float dist = length(v.xyz);
	vec3 dir = (INV_VIEW_MATRIX * vec4(normalize(v.xyz), 0.0)).xyz;
	bool sky = d < 0.000001;
	// The sea is not in the depth picture (it is drawn after it): there the depth is the sea
	// floor's, and beyond the modeled floor nothing at all. Taking that for the distance
	// left the rain's gray lying on the sea as a rectangle, the outline of the floor's mesh,
	// with clear dark water around it. So: a ray that goes down from above the sea ends at
	// the sea, whatever the depth picture says.
	if (dir.y < -0.0005 && CAMERA_POSITION_WORLD.y > sea_level) {
		float to_sea = (CAMERA_POSITION_WORLD.y - sea_level) / -dir.y;
		if (sky || to_sea < dist) {
			dist = to_sea;
			sky = false;
		}
	}
	// the rain in the air: near things clear, far things gray (the sky has its own cloud)
	float a = sky ? 0.0 : (1.0 - exp(-dist * mix(0.0015, 0.011, haze))) * haze;
	vec3 col = haze_color * light;
	// the rainbow
	float b = 0.0;
	vec3 bcol = vec3(0.0);
	if (bow > 0.001) {
		float ang = degrees(acos(clamp(dot(dir, normalize(away_from_sun)), -1.0, 1.0)));
		float x1 = (ang - 40.4) / 2.0;                 // the first bow: 40.4 (violet) .. 42.4 (red)
		float w1 = smoothstep(-0.25, 0.2, x1) * (1.0 - smoothstep(0.8, 1.25, x1));
		float x2 = (53.4 - ang) / 3.0;                 // the second, reversed: 50.4 (red) .. 53.4 (violet)
		float w2 = smoothstep(-0.25, 0.2, x2) * (1.0 - smoothstep(0.8, 1.25, x2));
		float inside = (1.0 - smoothstep(34.0, 40.6, ang)) * 0.045 + (1.0 - smoothstep(0.0, 40.0, ang)) * 0.02;
		// A rainbow looks far away: it stands in the rain that has moved off, kilometers out,
		// so it is seen on the sky and in front of far islands only, never in front of what
		// is near; and its feet fade out before they reach the horizon: one does not see a
		// rainbow's lower ends reach the ground. Drawn in near rain and below the horizon it was a ring close by.
		float where = (sky ? 1.0 : smoothstep(900.0, 3000.0, dist)) * smoothstep(0.004, 0.085, dir.y);
		// (stronger near the ground, where there is most rain to look through)
		where *= mix(1.0, 0.72, smoothstep(0.1, 0.6, dir.y));
		// (a rainbow is a faint thing: it tints the sky, it does not cover it)
		bcol = spectrum(clamp(x1, 0.0, 1.0)) * w1 * 0.26 + spectrum(clamp(x2, 0.0, 1.0)) * w2 * 0.06 + vec3(inside) * 0.6;
		bcol *= where * bow * light * sun_light;
		b = max(max(bcol.r, bcol.g), bcol.b);
	}
	// (blended over the picture: the bow's light is carried by the color)
	float alpha = clamp(a + b * 0.6, 0.0, 1.0);
	ALBEDO = (col * a + bcol * 1.5) / max(alpha, 0.001);
	ALPHA = alpha;
}
