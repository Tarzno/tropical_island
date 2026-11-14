shader_type sky;


// Tropical daytime sky: deep blue zenith, bright hazy horizon, wispy cirrus streaks
// and small fair-weather cumulus near the horizon.

uniform vec3 zenith_color : source_color = vec3(0.10, 0.27, 0.62);
uniform vec3 mid_color : source_color = vec3(0.30, 0.55, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.95);
uniform vec3 ground_color : source_color = vec3(0.32, 0.45, 0.55);
uniform float sky_energy = 1.0;
uniform float sun_disk_size = 0.9995;
uniform float sun_glow = 0.35;
uniform float cirrus_cover : hint_range(0.0, 1.0) = 0.55;
uniform float cumulus_cover : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_speed = 0.004;
// The wind, as the clouds have it: it comes from (wind_dir.x, -wind_dir.y) and blows to
// (-wind_dir.x, wind_dir.y) (the cirrus is laid out turned by this vector's angle, which is
// how the mirrored z comes about). daycycle.gd sets it from the island's wind (flight.gd):
// (0.97, 0.24) = in off the sea.
uniform vec2 wind_dir = vec2(0.97, 0.24);
// a rain shower's cloud over the sky: 0 none .. 1 closed (scripts/daycycle.gd, from weather.gd)
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
// 0 = day, 1 = night (LIGHT0 then is the moon)
uniform float night : hint_range(0.0, 1.0) = 0.0;
// The sun and the moon are two bodies, each with its place (scripts/daycycle.gd): the sun's
// disc goes down below the horizon, the moon's comes out with the stars. (They used to be
// one disc at the light's place, and the setting sun turned into the moon.)
uniform vec3 sun_pos = vec3(-0.5, 0.79, -0.35);
uniform vec3 sun_disc : source_color = vec3(2.4);
uniform vec3 moon_pos = vec3(0.83, 0.34, -0.44);
uniform float moon_vis : hint_range(0.0, 1.0) = 0.0;
// the moon's phase: 0 new .. 0.5 full .. 1 new again, and which way its lit side points on
// the disc (x to the right, y up, as seen in the sky): scripts/daycycle.gd sets both
uniform float moon_day = 0.0;       // the moon by day: pale against the blue while it is up (0: not shown)
uniform float moon_phase = 0.5;
// the turn of the sky: the stars and the Milky Way go around with the hours (daycycle.gd)
uniform mat3 star_rot = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
uniform vec2 moon_lit = vec2(1.0, 0.0);
uniform float star_brightness = 1.0;
uniform vec3 galactic_normal = vec3(0.52, 0.18, -0.83);
uniform vec3 galactic_center = vec3(0.62, 0.5, 0.6);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < oct; i++) {
		v += a * vnoise(p);
		p = r * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// one layer of point stars on a 3D grid; density in [0,1]
vec3 star_layer(vec3 dir, float scale, float density, float px) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 h = hash33(cell);
	vec3 h2 = hash33(cell + 17.3);
	if (h2.x > density) return vec3(0.0);
	vec3 o = 0.2 + 0.6 * h;
	float d = length(f - o) / scale;            // ~ angular distance in radians
	float mag = pow(h2.y, 9.0) * 14.0 + pow(h2.z, 3.0) * 0.6;
	float core = exp(-d * d / (px * px * 0.9));
	// color temperature: most white, some blue, some orange
	vec3 c = mix(vec3(1.0, 0.82, 0.62), vec3(0.72, 0.82, 1.0), h.z);
	c = mix(vec3(1.0), c, 0.6);
	float tw = 0.78 + 0.22 * sin(TIME * (2.0 + 6.0 * h.x) + h.y * 60.0);
	return c * mag * core * tw;
}

vec3 night_sky(vec3 dir, bool cube) {
	vec3 n = normalize(galactic_normal);
	float g = dot(dir, n);
	vec3 gc = normalize(galactic_center - n * dot(galactic_center, n));
	vec3 e2 = cross(n, gc);
	float u = atan(dot(dir, e2), dot(dir, gc));
	// Milky Way: wide glow, mottled star clouds, dark dust rifts, bright southern core
	float core = exp(-(u * u) / 0.35) * exp(-g * g / 0.05);
	float band = exp(-g * g / 0.018);
	// clumpy star clouds (roughly isotropic) with fine granulation and dark dust lanes along the band
	vec2 gp = vec2(u * 16.0, g * 22.0);
	float clouds = fbm(gp + 11.0, 5);
	float grain = fbm(gp * 4.3 + 4.0, 3);
	float lane = fbm(vec2(u * 9.0, g * 30.0) + 2.0, 5);
	float dust = smoothstep(0.48, 0.7, lane) * exp(-g * g / 0.006);
	float mw = band * (0.25 + 1.1 * clouds * clouds * clouds * 2.0 + 0.25 * grain) + core * (1.2 + 1.5 * clouds);
	mw *= 1.0 - dust * 0.9;
	vec3 mw_col = mix(vec3(0.62, 0.68, 0.85), vec3(1.0, 0.88, 0.72), clamp(core * 1.2, 0.0, 1.0));
	vec3 col = mw_col * mw * 0.013;
	if (!cube) {
		float px = 0.0011;
		float dens = 0.35 + 0.65 * band;
		col += star_layer(dir, 150.0, 0.018, px) * 1.6;
		col += star_layer(dir, 300.0, 0.010 * dens, px) * 0.9;
		col += star_layer(dir, 520.0, 0.006 * dens, px) * 0.6;
		col += star_layer(dir, 800.0, 0.008 * band, px) * 0.4;
	}
	return col * star_brightness;
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	float t = TIME * cloud_speed;

	// --- base gradient ---
	float h = clamp(y, 0.0, 1.0);
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.18, h));
	col = mix(col, zenith_color, smoothstep(0.12, 0.85, h));
	// below horizon (seen only from height / reflections)
	col = mix(col, ground_color, smoothstep(0.0, -0.15, y));

	// --- sun ---
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = dot(dir, sun_dir);
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	float mie = pow(max(sd, 0.0), 8.0) * sun_glow + pow(max(sd, 0.0), 120.0) * 0.6;
	col += sun_col * mie * 0.25 * (1.0 - overcast * 0.85);
	// horizon haze brightening toward sun
	col += horizon_color * 0.15 * pow(max(sd, 0.0), 2.0) * (1.0 - h);

	// --- stars, Milky Way and the moon ---
	if ((night > 0.0 || moon_day > 0.0) && y > -0.05) {
		float ext = smoothstep(-0.02, 0.25, y);   // atmospheric extinction near the horizon
		if (night > 0.0) {
			col += night_sky(star_rot * dir, AT_CUBEMAP_PASS) * night * ext;
		}
		// moon disk with maria, plus a soft halo
		vec3 md = normalize(moon_pos);
		float th = sqrt(max(2.0 * (1.0 - dot(dir, md)), 0.0));
		float r = 0.0125;
		if (th < r * 1.2) {
			vec3 up = abs(md.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 mx = normalize(cross(up, md));
			vec3 my = cross(md, mx);
			vec2 mp = vec2(dot(dir, mx), dot(dir, my)) / r;
			float maria = smoothstep(0.45, 0.7, fbm(mp * 2.2 + 3.0, 4));
			float limb = sqrt(max(1.0 - dot(mp, mp), 0.0));
			float disk = 1.0 - smoothstep(r * 0.96, r, th);
			vec3 mc = vec3(1.0, 0.98, 0.93) * mix(1.0, 0.62, maria) * (0.55 + 0.45 * limb);
			// the phase: the disc is a ball lit by a sun that stands behind it at new moon
			// and behind the eye at full moon; its dark part shows faintly (earthshine)
			float el = moon_phase * TAU;
			vec3 to_sun_m = vec3(normalize(moon_lit) * abs(sin(el)), -cos(el));
			float lit = smoothstep(-0.04, 0.1, dot(vec3(mp, limb), to_sun_m));
			mc *= mix(0.0012, 1.0, lit);
			col = mix(col, mc * 9.0, disk * moon_vis * (AT_CUBEMAP_PASS ? 0.3 : 1.0));
			// by day: only its lit part shows, a pale white a little brighter than the blue
			// around it; the dark part is the sky's own color
			vec3 pale = max(col, vec3(0.86, 0.89, 0.93)) * mix(1.0, 0.9, maria);
			col = mix(col, pale, lit * disk * moon_day * 0.6);
		}
		float moon_k = 0.5 - 0.5 * cos(moon_phase * TAU);
		col += vec3(0.6, 0.7, 0.9) * (exp(-th * 40.0) * 0.25 + exp(-th * 6.0) * 0.03) * moon_vis * moon_k;
	}

	// --- clouds (only above horizon) ---
	if (y > 0.0) {
		// project onto a cloud plane
		vec2 uv = dir.xz / (y + 0.06);
		vec2 wd = normalize(wind_dir);
		mat2 align = mat2(vec2(wd.x, wd.y), vec2(-wd.y, wd.x));
		vec2 cuv = align * uv;

		// cirrus: streaky, stretched along wind
		vec2 cu = cuv * vec2(0.35, 2.2) + vec2(t * 6.0, 0.0);
		float warp = fbm(cuv * 0.8 + t, 3);
		float c1 = fbm(cu + warp * 1.6, AT_CUBEMAP_PASS ? 4 : 6);
		float cir = smoothstep(1.0 - cirrus_cover, 1.05 - cirrus_cover * 0.45, c1);
		// fine streak detail
		float streak = fbm(cuv * vec2(0.6, 9.0) + vec2(t * 8.0, warp), 3);
		cir *= mix(0.55, 1.15, streak);
		cir *= smoothstep(0.02, 0.25, y);

		// cumulus: puffy patches, densest in a band above the horizon
		vec2 qu = uv * 1.6 + vec2(t * 10.0, t * 3.0);
		float c2 = fbm(qu + fbm(qu * 0.5, 3) * 0.8, AT_CUBEMAP_PASS ? 4 : 6);
		float band = smoothstep(0.0, 0.05, y) * (1.0 - smoothstep(0.12, 0.45, y));
		float cum = smoothstep(1.0 - cumulus_cover, 1.0 - cumulus_cover + 0.22, c2) * band;
		// shading: darker undersides
		float shade = mix(0.72, 1.0, smoothstep(0.35, 0.85, c2));

		// clouds take the color of the light: white at noon, gold/pink at sunset
		float day = smoothstep(0.02, 0.45, sun_dir.y);
		vec3 lc = normalize(LIGHT0_COLOR + 0.001) * 1.732;
		vec3 low_sun = mix(horizon_color * 0.9, lc * vec3(1.0, 0.75, 0.62), 0.55) * (0.7 + 0.8 * pow(max(sd, 0.0), 3.0));
		vec3 cloud_lit = mix(low_sun, vec3(1.0, 0.99, 0.97) * (0.92 + 0.35 * pow(max(sd, 0.0), 4.0)), day);
		shade = mix(mix(0.55, 1.0, smoothstep(0.35, 0.85, c2)) * 0.85, shade, day);
		vec3 cumc = cloud_lit * shade;
		// silver lining toward sun
		cumc += sun_col * 0.08 * pow(max(sd, 0.0), 16.0);

		// at night the clouds are only faintly moonlit
		float nl = mix(1.0, 0.03, night);
		cloud_lit *= nl;
		cumc = cumc * nl + sun_col * 0.02 * pow(max(sd, 0.0), 6.0) * night;
		float cir_a = cir * mix(0.6, 0.75, day);
		col = mix(col, cloud_lit * mix(0.85, 0.98, day), cir_a);
		col = mix(col, cumc, cum * 0.95);
		// distant aerial perspective on clouds
		col = mix(col, horizon_color, (1.0 - smoothstep(0.0, 0.1, y)) * 0.6 * max(cir_a, cum));
	}

	// --- a shower's cloud: a gray deck that draws over the whole sky, from windward first ---
	float hidden = 0.0;
	if (overcast > 0.0 && y > -0.03) {
		float yy = max(y, 0.0);
		vec2 uv = dir.xz / (yy + 0.1);
		vec2 wd = normalize(wind_dir);
		// (the deck drifts with the wind, its two layers at their own paces, and closes in from
		// windward: over the sea. It used to come from over the island, its layers drifting
		// two ways, neither of them the trees' way)
		vec2 to = vec2(-wd.x, wd.y);
		float d1 = fbm(uv * 0.55 - to * t * 17.0, AT_CUBEMAP_PASS ? 3 : 5);
		float d2 = fbm(uv * 1.7 - to * t * 24.0 + d1 * 1.5, AT_CUBEMAP_PASS ? 3 : 5);
		float lead = dot(normalize(dir.xz + vec2(0.0001)), -to) * 0.5 + 0.5;      // 1 looking to windward
		float o = clamp(overcast * 1.6 - (1.0 - lead) * 0.6 * (1.0 - overcast), 0.0, 1.0);
		// (patches first, that grow together: a third of the sky at a third of the way)
		float lo = mix(0.74, 0.2, o);
		float cover = smoothstep(lo, lo + 0.13, d1 * 0.65 + d2 * 0.35);
		// gray, darkest where it is thick, paler toward the horizon; lit by what light there is
		float daylight = mix(0.3 + 0.7 * smoothstep(-0.02, 0.3, sun_dir.y), 0.035, night);
		vec3 deck = mix(vec3(0.17, 0.19, 0.23), vec3(0.47, 0.5, 0.54), smoothstep(0.3, 0.72, d2)) * mix(1.0, 0.7, overcast * (1.0 - d1));
		deck = mix(deck, vec3(0.55, 0.58, 0.62), (1.0 - smoothstep(0.0, 0.22, yy)) * 0.6) * daylight;
		// (at a low sun the deck takes some of its color)
		deck *= mix(vec3(1.0), normalize(LIGHT0_COLOR + 0.001) * 1.732, 0.35 * (1.0 - smoothstep(0.1, 0.5, sun_dir.y)) * (1.0 - night));
		col = mix(col, deck, cover);
		hidden = cover;
	}

	// sun disk (not in cubemap to avoid hot specular)
	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(sun_disk_size, sun_disk_size + 0.0002, dot(dir, normalize(sun_pos)));
		// (gone where it is below the horizon, whatever is or is not in front of it there)
		col += sun_disc * disk * 12.0 * (1.0 - hidden) * smoothstep(-0.012, -0.002, y);
	}

	COLOR = col * sky_energy;
}
