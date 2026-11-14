shader_type spatial;
// depth_draw_always: the sea is drawn in the transparent pass (it reads the screen behind it for
// refraction), where depth is not written by default. Without it the wave faces are painted in
// mesh order, and wherever a crest stands in front of the water behind it, the far face is drawn
// over the near one: jagged, blocky patches on the swell. Do not change this back.
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 absorption = vec3(0.42, 0.075, 0.055);
uniform vec3 scatter_shallow : source_color = vec3(0.12, 0.62, 0.62);
uniform vec3 scatter_deep : source_color = vec3(0.01, 0.12, 0.30);
uniform float scatter_depth = 9.0;
uniform float absorb_scale = 0.9;
uniform float refraction_strength = 0.05;
uniform float detail_normal_strength = 0.35;
uniform float roughness = 0.035;
uniform float wave_scale = 1.0;
uniform float breaker_height = 0.22;
uniform vec3 sun_dir_world = vec3(-0.505, 0.788, -0.353);
uniform vec3 sun_tint = vec3(1.0);
// Noctiluca bioluminescence (night only) and the wader's position for the glowing wake
uniform float biolum = 0.0;
uniform vec3 biolum_color : source_color = vec3(0.15, 0.62, 1.0);
uniform vec3 player_pos = vec3(0.0, -100.0, 0.0);
uniform float player_speed = 0.0;
// tide pools (scripts/landscape.gd sets them): x, z, half-width, half-length; and their levels.
// When the sea has fallen below a pool's rim the pool has its own water (a sheet of
// pool.gdshader) and the sea is not drawn in it.
uniform vec4 tide_pool[8];
uniform float tide_pool_level[8];
uniform int tide_pool_count = 0;
uniform float under_light = 1.0;      // daylight under water (1 day .. 0.08 night), set by the player script
// The anchored boat: no sea is drawn inside its hull (scripts/fauna.gd sets these every
// frame). boat_at: where its middle lies (x, z) and the way its long axis points (a unit
// vector); boat_plane: the height of its own waterline there, and how that plane slopes
// along and across it (it pitches and rolls); boat_len: half its length; boat_w: half the
// hull's width at 24 places along it (from one end to the other; 0: no hull there) at five
// heights, 8 cm apart, from 16 cm under its waterline to 16 cm over it: the hull flares,
// and the sea stands higher in it on a crest.
uniform vec4 boat_at = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec3 boat_plane = vec3(0.0);
uniform float boat_len = 0.0;
uniform float boat_w[120];

varying vec3 w_pos;
varying vec3 w_normal;
varying float v_depth;      // water depth from heightmap (m), negative on land
varying float v_depth_s;    // depth averaged over ~15 m: soft color transition at the reef edge
varying float v_breaker;    // breaker crest intensity
varying float v_swash;
varying float v_base_y;    // water height before the swash lift

// The tide. The whole shader works with the sea at 0, as it was written: the ground is taken
// as it lies against today's level (gh() for ground_height()), and only what goes out to
// the world (the vertices, w_pos) has the level added.
float gh(vec2 xz) {
	return ground_height(xz) - sea_level;
}

// direction (normalized xz), wavelength, steepness
const int NW = 7;

// Spacing of the ocean grid at p (the mesh built in world.gd: _build_ocean).
// SeaLife.wave_height() mirrors this and the wave sum below: keep the three in step.
float grid_spacing(vec2 p) {
	float sx = p.x > 75.0 ? 0.45 + 0.15 * (p.x - 75.0)
		: (p.x < -215.0 ? 0.7 + 0.15 * (-215.0 - p.x) : (p.x < -150.0 ? 0.7 : (p.x < -40.0 ? 0.8 : 0.45)));
	float az = abs(p.y);
	float sz = az > 268.0 ? 0.9 + 0.15 * (az - 268.0) : ((p.y > 175.0 || p.y < -215.0) ? 0.9 : 0.55);
	return max(sx, sz);
}

void gerstner(vec2 dir, float wl, float steep, float amp_mul, vec2 p, float t, inout vec3 disp, inout vec3 tang, inout vec3 bin) {
	// a wave the grid is too coarse to carry (fewer than ~3-6 vertices per wavelength) would
	// only show as jagged facets: fade it out there (the normal maps keep the fine ripples)
	amp_mul *= 1.0 - smoothstep(wl * 0.16, wl * 0.33, grid_spacing(p));
	float k = 6.28318 / wl;
	float c = sqrt(9.81 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k * amp_mul;
	float sf = sin(f);
	float cf = cos(f);
	disp += vec3(d.x * a * cf, a * sf, d.y * a * cf);
	float ks = steep * amp_mul;
	tang += vec3(-d.x * d.x * ks * sf, d.x * ks * cf, -d.x * d.y * ks * sf);
	bin += vec3(-d.x * d.y * ks * sf, d.y * ks * cf, -d.y * d.y * ks * sf);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	float t = world_time;
	float g = gh(p);
	float depth = -g;
	v_depth = depth;
	// blurred depth (two rings around the vertex), with a slow wobble so the blend zone
	// is not a uniform band along the drop-off
	float ds = depth;
	float wsum = 1.0;
	float rot = noise1(p.x * 0.02 + p.y * 0.015) * 3.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + rot;
		vec2 o = vec2(cos(a), sin(a));
		ds += -gh(p + o * 8.0);
		ds += -gh(p + o * 20.0) * 0.7;
		wsum += 1.7;
	}
	v_depth_s = ds / wsum;

	// waves shrink in shallow water
	float amp = mix(0.12, 1.0, smoothstep(0.3, 6.0, depth)) * wave_scale;
	// outside the finely tessellated region the grid gets coarse: fade geometric waves out
	float outside = max(max(p.x - 65.0, -210.0 - p.x), max(p.y - 262.0, -262.0 - p.y));
	amp *= 1.0 - smoothstep(0.0, 45.0, outside);
	vec3 disp = vec3(0.0);
	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	gerstner(vec2(-1.0, 0.18), 21.0, 0.10, amp, p, t, disp, tang, bin);
	gerstner(vec2(-1.0, -0.35), 13.0, 0.10, amp, p, t, disp, tang, bin);
	gerstner(vec2(-0.8, 0.6), 7.3, 0.09, amp, p, t, disp, tang, bin);
	gerstner(vec2(-0.9, -0.7), 4.1, 0.08, amp, p, t, disp, tang, bin);
	gerstner(vec2(-0.3, 1.0), 2.6, 0.07, amp, p, t, disp, tang, bin);
	gerstner(vec2(-1.0, 0.05), 1.7, 0.06, amp, p, t, disp, tang, bin);
	gerstner(vec2(0.4, -1.0), 1.1, 0.05, amp, p, t, disp, tang, bin);

	// breakers: crests that follow depth contours and travel toward the shore
	float zn = noise1(p.y * 0.03) * 6.0 + noise1(p.y * 0.13) * 1.5;
	float bph = depth * 4.2 + t * 6.28318 / swash_period + zn;
	float crest = pow(0.5 + 0.5 * sin(bph), 5.0);
	float shoal = smoothstep(3.2, 1.4, depth) * smoothstep(0.15, 0.7, depth);
	// (not on the reef crest: the surf there comes in from the open sea, see the fragment shader)
	shoal *= 1.0 - smoothstep(0.02, 0.2, surf_at(p));
	float bh = crest * shoal * breaker_height * (0.7 + 0.3 * noise1(p.y * 0.07 + floor(bph / 6.28318) * 3.1));
	disp.y += bh;
	v_breaker = crest * shoal;
	// slope of the breaker for the normal (crest travels toward -depth gradient ~ -x)
	float dcrest = 5.0 * pow(0.5 + 0.5 * sin(bph), 4.0) * 0.5 * cos(bph) * 4.2;
	tang.y += -dcrest * shoal * breaker_height * 0.1;

	// swash run-up near the waterline (also lifts the plane over the wet sand)
	float sw = swash(p.y, t);
	v_swash = sw;
	// geometry always covers the highest run-up; the fragment shader cuts the
	// actual (per-pixel) waterline so the edge is smooth instead of following triangles
	v_base_y = wp.y + disp.y - 0.03;
	disp.y += SWASH_HEIGHT * 1.08 * (1.0 - smoothstep(0.0, 1.2, depth)) - 0.03;

	wp += disp;
	wp.y += sea_level;
	w_pos = wp;
	w_normal = normalize(cross(bin, tang));
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

float linear_depth(vec2 suv, mat4 inv_proj) {
	float d = textureLod(depth_tex, suv, 0.0).r;
	vec4 v = inv_proj * vec4(suv * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	return -v.z;
}

void fragment() {
	if (boat_len > 0.0) {
		vec2 rel = w_pos.xz - boat_at.xy;
		float lx = dot(rel, boat_at.zw);
		if (abs(lx) < boat_len) {
			float lz = dot(rel, vec2(-boat_at.w, boat_at.z));
			float k = (lx / boat_len * 0.5 + 0.5) * 23.0;
			int i0 = int(floor(k));
			int i1 = min(i0 + 1, 23);
			// how high the sea stands here against the boat's own waterline
			float h = clamp((w_pos.y - (boat_plane.x + lx * boat_plane.y + lz * boat_plane.z) + 0.16) / 0.08, 0.0, 3.999);
			int j0 = int(floor(h));
			float fk = k - float(i0);
			float lo = mix(boat_w[j0 * 24 + i0], boat_w[j0 * 24 + i1], fk);
			float hi = mix(boat_w[(j0 + 1) * 24 + i0], boat_w[(j0 + 1) * 24 + i1], fk);
			if (abs(lz) < mix(lo, hi, h - float(j0))) {
				discard;
			}
		}
	}
	float t = world_time;
	vec2 p = w_pos.xz;

	// ---- normals ----
	vec2 uv1 = p * 0.11 + vec2(t * 0.021, t * 0.013);
	vec2 uv2 = p * 0.27 + vec2(-t * 0.017, t * 0.029);
	vec2 uv3 = p * 0.031 + vec2(t * 0.006, -t * 0.004);
	vec3 na = texture(normal_a, uv1).xyz * 2.0 - 1.0;
	vec3 nb = texture(normal_b, uv2).xyz * 2.0 - 1.0;
	vec3 nc = texture(normal_a, uv3).xyz * 2.0 - 1.0;
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	float detail_fade = mix(1.0, 0.35, smoothstep(30.0, 400.0, dist));
	vec2 dn = (na.xy * 0.5 + nb.xy * 0.35 + nc.xy * 0.6) * detail_normal_strength * detail_fade;
	// calm the surface right at the waterline
	dn *= mix(0.4, 1.0, smoothstep(0.0, 0.8, v_depth));
	// rain: the rings of the drops, near by; further off they are too small to see and only
	// dull the surface (below: roughness)
	vec3 drops = rain_rings(p, t) * (1.0 - smoothstep(18.0, 45.0, dist));
	dn += drops.xy * 0.55;
	vec3 n = normalize(w_normal + vec3(dn.x, 0.0, dn.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// ---- per-pixel waterline ----
	float g_px = gh(p);
	float shore_px = 1.0 - smoothstep(0.0, 1.2, -g_px);
	// right at the shore the waves are tiny: use a flat sea level there so wave height
	// interpolated from deeper vertices can never spread a sheet of water over the sand
	float base = mix(v_base_y, -0.03, smoothstep(0.0, 1.0, shore_px));
	float level = base + SWASH_HEIGHT * shore_px * swash(p.y, t);
	float water_th = level - g_px;
	if (shore_px > 0.0 && water_th < 0.0) {
		discard;
	}
	if (shore_px > 0.0) {
		for (int i = 0; i < tide_pool_count; i++) {
			vec2 q = (p - tide_pool[i].xy) / tide_pool[i].zw;
			if (sea_level < tide_pool_level[i] - 0.02 && dot(q, q) < 1.0) {
				discard;
			}
		}
	}

	// ---- thickness of water along the line of sight (foam against rocks and sand) ----
	float surf_lin = -VERTEX.z;
	float scene_lin = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick_raw = max(scene_lin - surf_lin, 0.0);
	vec3 view_dir = normalize(w_pos - CAMERA_POSITION_WORLD);
	float vert_frac = clamp(abs(view_dir.y), 0.08, 1.0);

	// ---- the way into the water ----
	// Light bends toward the vertical as it enters (never more than 49 degrees off it), so
	// even at a grazing view the sea floor you see is the floor almost straight below the
	// surface, and the color of the water follows its real depth. The sea floor is a height
	// field, so that bent ray is followed there. (Following the straight line of sight through
	// the depth buffer instead made every underwater slope a razor-sharp outline: on the near
	// side the sand a few meters down, just past it a long way through deep water. Do not go
	// back to that.)
	float wy = shore_px > 0.0 ? level : w_pos.y - sea_level;
	vec3 rdir = refract(view_dir, normalize(w_normal + vec3(dn.x, 0.0, dn.y) * 0.6), 0.75);
	float hz = max(-rdir.y, 0.5);
	float col = max(wy - g_px, 0.0);
	vec2 pf = p;
	for (int i = 0; i < 2; i++) {
		pf = p + rdir.xz * (col / hz);
		col = max(wy - gh(pf), 0.0);
	}
	float path = col / hz;
	// that point of the floor on the screen: its sand, caustics and shadows are taken from there
	vec4 fclip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(pf.x, wy - col + sea_level, pf.y, 1.0));
	vec2 fuv = fclip.xy / max(fclip.w, 0.0001) * 0.5 + 0.5;
	// Just outside the picture (the floor under water near the border lies a little beyond it)
	// the nearest point on the border stands in for it. Falling back to the straight line of
	// sight there brought the outlines back along the edges of the screen.
	vec2 over = max(max(-fuv, fuv - 1.0), vec2(0.0));
	float off = max(over.x, over.y);
	float on_screen = (1.0 - smoothstep(0.0, 0.1, off)) * step(0.0, fclip.w);
	float exact = 1.0 - step(0.0005, off);
	fuv = clamp(fuv, vec2(0.001), vec2(0.999));
	// (the depth buffer there holds the floor itself, or something standing or swimming above it)
	vec4 fv = INV_PROJECTION_MATRIX * vec4(fuv * 2.0 - 1.0, textureLod(depth_tex, fuv, 0.0).r, 1.0);
	fv.xyz /= fv.w;
	if (-fv.z < surf_lin - 0.02) {
		on_screen = 0.0;   // something in front of the water
	}
	// far off the screen, or hidden: the straight line of sight, nudged by the ripples
	vec2 ruv = SCREEN_UV + n.xz * refraction_strength * clamp(thick_raw * 0.6, 0.0, 1.0) / max(1.0, surf_lin * 0.05);
	float scene_lin_r = linear_depth(ruv, INV_PROJECTION_MATRIX);
	if (scene_lin_r < surf_lin) {
		ruv = SCREEN_UV;
		scene_lin_r = scene_lin;
	}
	vec3 refr = mix(textureLod(screen_tex, ruv, 0.0).rgb, textureLod(screen_tex, fuv, 0.0).rgb, on_screen);
	path = min(path, mix(max(scene_lin_r - surf_lin, 0.0), mix(path, length(fv.xyz - VERTEX), exact), on_screen));

	// Beer-Lambert absorption: along the bent ray, plus the sunlight's own way down to that depth
	vec3 T = exp(-absorption * path * (1.0 + hz) * absorb_scale);
	// (the deep sand, and the end of the sea-floor mesh far out, are never seen)
	T *= 1.0 - smoothstep(16.0, 26.0, col);
	float dz = clamp(mix(col, max(v_depth_s, 0.0), 0.5), 0.0, 40.0);
	vec3 scatter = mix(scatter_shallow, scatter_deep, smoothstep(0.5, scatter_depth, dz));

	// ---- foam ----
	float fa = texture(foam_tex, p * 0.21 + vec2(t * 0.02, -t * 0.015)).r;
	float fb = texture(foam_tex, p * 0.53 + vec2(-t * 0.03, t * 0.01)).r;
	float foam_pat = smoothstep(0.35, 0.75, fa * 0.6 + fb * 0.55);
	// lace: a web of thin bubble lines with open holes in between
	float fc = texture(foam_tex, p * 1.3 + vec2(t * 0.05, t * 0.03)).r;
	float lace = smoothstep(0.55, 0.85, fa * 0.5 + fc * 0.6) * smoothstep(0.25, 0.6, fb);
	// vertical water thickness (the view-ray length overstates it at grazing angles)
	float thick_v = mix(thick_raw * vert_frac, max(water_th, 0.0), shore_px);
	// waterline lace (intersection with sand / rocks)
	float edge = 1.0 - smoothstep(0.0, 0.05 + 0.06 * v_swash, thick_v);
	float edge_foam = edge * mix(0.15, 0.95, lace);
	// thin bubbly line right at the leading edge
	float line_n = texture(foam_tex, p * 2.7).r;
	edge_foam = max(edge_foam, (1.0 - smoothstep(0.0, 0.006 + 0.01 * line_n, thick_v)) * mix(0.5, 0.95, line_n));
	// breaking crests
	// only the very crest of a breaking wave turns white, as a lacy band
	float brk = smoothstep(0.6, 0.95, v_breaker) * smoothstep(1.6, 0.7, v_depth) * smoothstep(0.1, 0.4, v_depth);
	float brk_foam = brk * lace * 0.85;
	// residual foam drifting in the surf zone
	float surf_zone = smoothstep(1.6, 0.2, v_depth) * smoothstep(-0.3, 0.1, v_depth);
	float res_foam = surf_zone * smoothstep(0.7, 0.92, fa * 0.55 + fb * 0.6) * 0.3;
	// receding swash leaves foam lines on the beach
	float back_foam = smoothstep(0.35, 0.0, v_depth) * (1.0 - v_swash) * lace * 0.45;
	float foam = clamp(edge_foam + brk_foam + res_foam + back_foam, 0.0, 0.93);
	foam *= smoothstep(500.0, 50.0, dist);
	// ---- surf on the reef crest ----
	// The swell (the longest wave of the sum above) breaks where the reef comes up under it:
	// a white front at the crest of each wave with its foam trailing behind, stretch by stretch
	// and wave by wave a different size, and white water left drifting on the reef flat.
	// (the swell breaks harder on the reef's crest the less water lies over it)
	float sb = clamp(surf_at(p) * (1.0 - sea_level * 0.8), 0.0, 1.0);
	float surf_foam = 0.0;
	if (sb > 0.01) {
		// streaks of foam drawn out along the way the waves run
		float streak = texture(foam_tex, vec2(p.x * 0.045 + t * 0.012, p.y * 0.3)).r * 0.6 + texture(foam_tex, vec2(p.x * 0.13 - t * 0.02, p.y * 0.71 + 0.3)).r * 0.4;
		for (int i = 0; i < 2; i++) {
			// two trains of waves: the long swell and the shorter one that runs with it
			float wl = i == 0 ? 21.0 : 13.0;
			vec2 wd = i == 0 ? normalize(vec2(-1.0, 0.18)) : normalize(vec2(-1.0, -0.35));
			float u = (dot(wd, p) - sqrt(9.81 * wl / 6.28318) * t) / wl + (noise1(p.y * 0.05 + float(i) * 9.0) - 0.5) * 0.35;
			float behind = (1.0 - fract(u - 0.25)) * wl;       // meters behind the crest
			float size = 0.45 + 0.8 * noise1(floor(u - 0.25) * 1.7 + p.y * 0.04 + float(i) * 5.0);
			float breaking = smoothstep(0.38, 0.6, sb * size) * (i == 0 ? 1.0 : 0.75);
			// the white front of the breaking wave, and the foam it leaves, thinning into streaks
			float front = exp(-behind * 0.9);
			float trail = exp(-behind * 0.16) * smoothstep(0.3 + behind * 0.022, 0.62 + behind * 0.012, streak);
			surf_foam = max(surf_foam, breaking * max(front * mix(0.75, 1.0, lace), trail * 0.85));
		}
		// a little white water always drifting on the reef flat
		surf_foam = max(surf_foam, sb * smoothstep(0.62, 0.8, streak) * 0.35);
		surf_foam = clamp(surf_foam, 0.0, 0.97) * smoothstep(1100.0, 250.0, dist);
		foam = max(foam, surf_foam);
	}

	// ---- compose ----
	vec3 transmitted = refr * T;
	vec3 inscatter = scatter * (1.0 - T);

	// soft fade where the water is very thin so the edge isn't a hard cut
	float thin = smoothstep(0.0, 0.03, mix(thick_raw, max(water_th, 0.0), shore_px));

	// Fresnel: at grazing angles the surface reflects almost everything; the water body
	// (its color and what lies beneath) fades out and the specular sky reflection takes over
	float ndv = clamp(dot(n, -view_dir), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	ALBEDO = mix(inscatter * (1.0 - fres * 0.85), vec3(0.92, 0.95, 0.95), foam);
	EMISSION = transmitted * (1.0 - foam) * 0.92 * (1.0 - fres);
	// sub-pixel wave facets far away widen the sun's glitter path
	ROUGHNESS = mix(mix(roughness, 0.13, smoothstep(15.0, 600.0, dist)), 0.6, foam);
	SPECULAR = mix(0.5, 0.2, foam) * thin;
	// in the rain the sea is pocked and matt: no glitter, a white speck where a drop has just hit
	ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS, 0.32), min(rain * 1.5, 1.0) * smoothstep(10.0, 60.0, dist));
	ALBEDO = mix(ALBEDO, vec3(0.9, 0.93, 0.95), clamp(drops.z, 0.0, 1.0) * 0.5);
	METALLIC = 0.0;
	// subsurface-ish glow of thin breaking crests lit from behind
	// light shining through the thin crest toward the viewer
	float back = pow(clamp(dot(view_dir, normalize(sun_dir_world)), 0.0, 1.0), 4.0);
	float crest_glow = v_breaker * smoothstep(1.5, 0.5, v_depth) * smoothstep(0.0, 0.3, sun_dir_world.y);
	EMISSION += scatter_shallow * sun_tint * crest_glow * (0.08 + 0.3 * back);
	// ---- bioluminescence: Noctiluca flashes wherever the water is disturbed ----
	if (biolum > 0.0) {
		float b1 = texture(foam_tex, p * 3.3 + vec2(t * 0.35, -t * 0.27)).r;
		float b2 = texture(foam_tex, p * 5.9 - vec2(t * 0.21, t * 0.4)).r;
		float spark = smoothstep(0.5, 0.85, b1 * b2 * 1.6);
		// strongest where the wave actually breaks, a thin line at the swash front
		float front = (1.0 - smoothstep(0.0, 0.025, thick_v)) * step(0.001, thick_v);
		float agitation = brk_foam * 1.3 + front * 0.8 + edge_foam * 0.18 + res_foam * 0.15
			+ smoothstep(0.6, 1.0, v_breaker) * smoothstep(2.0, 0.6, v_depth) * 0.35;
		// the wader stirs up light around the legs
		float dp = length(p - player_pos.xz);
		float wake = (1.0 - smoothstep(0.15, 1.3, dp)) * clamp(player_speed, 0.25, 1.5)
			* step(player_pos.y - 0.4, w_pos.y);
		float bio = agitation * (0.08 + 1.2 * spark) + wake * (0.15 + 1.6 * spark);
		bio *= smoothstep(400.0, 30.0, dist);
		EMISSION += biolum_color * bio * biolum * 0.7;
	}
	ALPHA = 1.0;
	// ---- the surface seen from below (a snorkeler looking up) ----
	// Within 48.6 degrees of the vertical the sky shows through, rippled (Snell's window);
	// outside it the surface is a mirror of the water below.
	if (!FRONT_FACING) {
		vec3 nu = normalize(w_normal + vec3(dn.x, 0.0, dn.y) * 1.6);
		float cosv = clamp(dot(view_dir, nu), 0.0, 1.0);
		float window = smoothstep(0.6, 0.72, cosv);
		vec2 suv = clamp(SCREEN_UV + nu.xz * 0.07, vec2(0.001), vec2(0.999));
		vec3 above = textureLod(screen_tex, suv, 0.0).rgb * 0.92 + vec3(0.05, 0.08, 0.08) * under_light;
		vec3 mirror = mix(scatter_deep, scatter_shallow, 0.4) * (0.35 + 0.25 * nu.x) * under_light;
		ALBEDO = vec3(0.0);
		EMISSION = mix(mirror, above, window);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
}
