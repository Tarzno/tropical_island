shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"
#include "res://shaders/sea_light.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_wet_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D landmask : filter_linear, repeat_disable;
uniform sampler2D litter_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D granite_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D water_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 tint_dry : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 tint_dark : source_color = vec3(0.86, 0.80, 0.70);
uniform vec3 wet_tint : source_color = vec3(0.80, 0.77, 0.70);
uniform float tile_size = 2.2;
uniform float ripple_strength = 0.55;
uniform float caustic_strength = 1.4;
uniform float sparkle_strength = 3.0;
uniform vec3 sun_dir_world = vec3(0.47, 0.62, 0.62);
uniform float biolum = 0.0;
uniform vec3 biolum_color : source_color = vec3(0.15, 0.62, 1.0);
// rain: the roofed ground of the grotto stays dry (discs: x, z, radius), except where the rain
// comes in through the gaps in the roof (scripts/weather.gd sets both)
// where the rain reaches the ground around the grotto (weather.gd: _open_ground): 1 open to
// the rain, 0 under the boulders; through the gaps in the roof it reaches the floor
uniform bool rain_roofs = false;
uniform sampler2D rain_open : filter_linear, repeat_disable;
uniform vec4 rain_open_rect;       // the map's corner (x, z), one over its size
// the falling tide leaves the sand wet: up to this level it has not dried yet (scripts/tide.gd)
global uniform float tide_wet;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// asymmetric wind ripple profile
float ripple(float x) {
	float f = fract(x);
	return f < 0.7 ? smoothstep(0.0, 0.7, f) : 1.0 - smoothstep(0.7, 1.0, f);
}

// --- texture bombing: every cell of the ground gets its own random offset into the
// texture; the four cells around a point are blended with sharpened weights, so the
// tiling never lines up into a visible grid.
vec4 bomb_weights(vec2 f) {
	vec2 w = f * f * (3.0 - 2.0 * f);
	vec4 b = vec4((1.0 - w.x) * (1.0 - w.y), w.x * (1.0 - w.y), (1.0 - w.x) * w.y, w.x * w.y);
	b = b * b * b;
	return b / (b.x + b.y + b.z + b.w);
}

vec3 bomb_color(sampler2D t, vec2 uv) {
	vec2 c = floor(uv);
	vec4 w = bomb_weights(fract(uv));
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec3 a = textureGrad(t, uv + hash22(c) * 7.31, dx, dy).rgb;
	vec3 b = textureGrad(t, uv + hash22(c + vec2(1, 0)) * 7.31, dx, dy).rgb;
	vec3 d = textureGrad(t, uv + hash22(c + vec2(0, 1)) * 7.31, dx, dy).rgb;
	vec3 e = textureGrad(t, uv + hash22(c + vec2(1, 1)) * 7.31, dx, dy).rgb;
	return a * w.x + b * w.y + d * w.z + e * w.w;
}

vec3 bomb_normal(sampler2D t, vec2 uv) {
	vec2 c = floor(uv);
	vec4 w = bomb_weights(fract(uv));
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec3 a = textureGrad(t, uv + hash22(c) * 7.31, dx, dy).xyz;
	vec3 b = textureGrad(t, uv + hash22(c + vec2(1, 0)) * 7.31, dx, dy).xyz;
	vec3 d = textureGrad(t, uv + hash22(c + vec2(0, 1)) * 7.31, dx, dy).xyz;
	vec3 e = textureGrad(t, uv + hash22(c + vec2(1, 1)) * 7.31, dx, dy).xyz;
	return (a * w.x + b * w.y + d * w.z + e * w.w) * 2.0 - 1.0;
}

// The surface of a granite slab as a height (0..1): sheets a meter or so across that have
// flaked off one above the other (exfoliation), and pitting.
float granite_h(vec2 p, float pit) {
	float a = texture(macro_noise, p * 0.31 + 2.1).r;
	float tq = a * 7.0;
	float sheet = (floor(tq) + smoothstep(0.38, 0.62, fract(tq))) / 7.0;
	float b = texture(macro_noise, p * 1.9 + 0.7).r;
	return sheet * 0.5 + a * 0.2 + b * pit;
}

// One set of joints: thin cracks a few meters apart that run for a while and stop.
// x: crack 0..1, y: distance from it in meters (signed), z: is there a joint here at all
vec3 joint_set(vec2 p, vec2 dir, float spacing, float seed) {
	float wob = (texture(macro_noise, p * 0.021 + seed).r - 0.5) * 1.6;
	float u = dot(p, dir) / spacing + wob;
	float cell = floor(u);
	float jit = 0.2 + 0.6 * hash11(cell * 1.31 + seed * 7.0);
	float dm = (fract(u) - jit) * spacing;
	float v = dot(p, vec2(-dir.y, dir.x));
	float pres = smoothstep(0.4, 0.55, noise1(v * 0.09 + cell * 5.7 + seed * 3.0));
	float w = 0.012 + 0.016 * noise1(v * 0.7 + cell);
	float aa = fwidth(u) * spacing;
	return vec3((1.0 - smoothstep(w, w + aa + 0.004, abs(dm))) * pres * (1.0 - smoothstep(0.15, 0.6, aa)), dm, pres);
}

void fragment() {
	vec2 p = w_pos.xz;
	float t = world_time;
	float dist = length(CAMERA_POSITION_WORLD - w_pos);

	// --- albedo with anti-tiling: two scales, rotated ---
	vec2 uva = p / tile_size;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 uvb = rot * p / (tile_size * 2.7) + vec2(0.37, 0.71);
	vec3 ca = texture(sand_albedo, uva).rgb;
	vec3 cb = texture(sand_albedo, uvb).rgb;
	float mn = texture(macro_noise, p * 0.013).r;
	float mn2 = texture(macro_noise, p * 0.071 + 0.3).r;
	vec3 base = mix(ca, cb, smoothstep(0.35, 0.65, mn2));
	// normalize brightness of generated texture and tint
	base = base / max(0.001, dot(vec3(0.33), texture(sand_albedo, vec2(0.5), 12.0).rgb)) * 0.78;
	// fine grain detail close to the camera (individual grains, tiny shell bits)
	float near = smoothstep(9.0, 1.5, length(CAMERA_POSITION_WORLD - w_pos));
	vec3 fine = texture(sand_albedo, rot * p / 0.38 + 0.13).rgb;
	float fl = dot(fine, vec3(0.33)) / max(0.001, dot(vec3(0.33), texture(sand_albedo, vec2(0.5), 12.0).rgb));
	base *= mix(1.0, mix(0.82, 1.18, smoothstep(0.85, 1.15, fl)), near * 0.8);
	vec3 tint = mix(tint_dark, tint_dry, smoothstep(0.25, 0.75, mn));
	vec3 col = base * tint;

	// --- land cover from the baked mask: r forest floor, g bare rock / reef, b open summit ---
	vec4 lm = texture(landmask, (p + 256.0) / 512.0);
	float edge_n = (texture(macro_noise, p * 0.04 + 0.7).r - 0.5) * 0.5;
	float forest = smoothstep(0.25, 0.75, lm.r + edge_n);
	float trail = smoothstep(0.15, 0.6, lm.g + (texture(macro_noise, p * 0.6).r - 0.5) * 0.4);
	float summit = smoothstep(0.2, 0.8, lm.b + edge_n);
	vec3 floor_n = vec3(0.0);
	if (forest > 0.0) {
		// fallen leaves and humus under the trees
		vec3 lit = bomb_color(litter_albedo, p / 2.3);
		float shade_n = texture(macro_noise, p * 0.021 + 3.0).r;
		lit *= mix(0.55, 0.95, shade_n);
		// patches of moss and seedlings
		float moss = smoothstep(0.55, 0.8, texture(macro_noise, p * 0.045 + 0.5).r);
		lit = mix(lit, lit * vec3(0.45, 0.75, 0.3) + vec3(0.02, 0.05, 0.0), moss * 0.7);
		// low herbs and creepers cover much of the litter (the forest floor is not bare earth)
		float herb = smoothstep(0.42, 0.56, texture(macro_noise, p * 0.057 + 4.1).r + (texture(macro_noise, p * 0.47).r - 0.5) * 0.35);
		lit = mix(lit, bomb_color(grass_albedo, p / 1.3 + 0.37) * vec3(0.5, 0.78, 0.4) * mix(0.6, 1.0, shade_n), herb * 0.85);
		// open grassy hill: wild grass with some bare soil
		vec3 grs = bomb_color(grass_albedo, p / 1.7);
		grs *= mix(0.75, 1.1, texture(macro_noise, p * 0.03 + 1.7).r);
		float bare = smoothstep(0.62, 0.78, texture(macro_noise, p * 0.06 + 2.0).r);
		grs = mix(grs, lit * 0.9, bare * 0.6);
		vec3 ground_c = mix(lit, grs, summit);
		col = mix(col, ground_c, forest);
		floor_n = mix(bomb_normal(litter_normal, p / 2.3), bomb_normal(grass_normal, p / 1.7), summit) * forest;
	}

	// --- bare rock (mask g): granite slabs and whalebacks, hard reef under water ---
	// (the soil lies in the hollows of the rock's surface, so the edge of a slab is ragged)
	float g_h0 = granite_h(p, 0.3);
	float rock_e = lm.g + (texture(macro_noise, p * 0.11 + 5.0).r - 0.5) * 0.3 + (g_h0 - 0.5) * 0.4;
	// under water the blue channel tells granite (the headland going on below the waterline) from reef
	float sub = smoothstep(0.1, -0.5, w_pos.y);
	float wet_rock = smoothstep(0.3, 0.6, lm.b) * sub;
	float granite = smoothstep(0.42, 0.52, rock_e) * mix(1.0, wet_rock, sub);
	float reef = smoothstep(0.3, 0.62, rock_e) * smoothstep(-0.25, -0.6, w_pos.y) * (1.0 - wet_rock);
	vec3 up_n = normalize(w_nrm);
	vec2 g_grad = vec2(0.0);
	if (granite > 0.0) {
		vec3 bw = pow(abs(up_n), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec3 q = w_pos * 0.28;
		vec3 g1 = texture(granite_albedo, q.zy).rgb * bw.x + texture(granite_albedo, q.xz).rgb * bw.y + texture(granite_albedo, q.xy).rgb * bw.z;
		q = w_pos * 0.087 + 0.5;
		vec3 g2 = texture(granite_albedo, q.zy).rgb * bw.x + texture(granite_albedo, q.xz).rgb * bw.y + texture(granite_albedo, q.xy).rgb * bw.z;
		// (seen from standing height the crystals are small and the rock is nearly one tone: the
		// boulders' close-up texture, finer and with half its contrast)
		vec3 q3 = w_pos * 1.1 + 0.3;
		vec3 g3 = texture(granite_albedo, q3.zy).rgb * bw.x + texture(granite_albedo, q3.xz).rgb * bw.y + texture(granite_albedo, q3.xy).rgb * bw.z;
		vec3 gmean = textureLod(granite_albedo, vec2(0.5), 12.0).rgb;
		vec3 gc = mix(gmean, mix(g3, g1, 0.3), 0.5 - 0.2 * smoothstep(4.0, 30.0, dist)) * mix(0.9, 1.08, dot(g2, vec3(0.33)) / max(dot(gmean, vec3(0.33)), 0.01) * 0.5 + 0.5);
		// relief: the flaked sheets and the pitting, from the height function (fades with distance)
		float gfade = smoothstep(90.0, 12.0, dist);
		float ge = 0.035;
		// (the pitting only faintly: at full strength every pit was a black fleck in the sun)
		float g_h1 = granite_h(p, 0.1);
		g_grad = vec2(granite_h(p + vec2(ge, 0.0), 0.1) - g_h1, granite_h(p + vec2(0.0, ge), 0.1) - g_h1) / ge * 0.13 * gfade;
		// grain: the crystals stand out a little (close up)
		float l0 = dot(g1, vec3(0.33));
		vec2 qg = w_pos.xz * 0.28;
		g_grad += vec2(dot(texture(granite_albedo, qg + vec2(0.012, 0.0)).rgb, vec3(0.33)) - l0, dot(texture(granite_albedo, qg + vec2(0.0, 0.012)).rgb, vec3(0.33)) - l0) * 1.5 * bw.y * smoothstep(14.0, 2.0, dist);
		// weathering: pale, slightly pink where a sheet came off not long ago, gray-black films
		// of algae on the old surfaces; the lower sheet edges are always dirtier
		// (from the broad sheets only: with the fine pitting in it the stains broke up into flecks)
		float stain = smoothstep(0.3, 0.7, texture(macro_noise, p * 0.037 + 1.9).r + (texture(macro_noise, p * 0.31 + 2.1, 2.0).r - 0.5) * 0.9);
		gc *= mix(vec3(0.5, 0.47, 0.44), vec3(0.9, 0.83, 0.78), stain) * mix(0.8, 1.1, mn2);
		gc *= mix(0.72, 1.0, smoothstep(0.0, 0.25, fract(texture(macro_noise, p * 0.31 + 2.1).r * 7.0)));
		// joints: two sets of cracks, their shoulders rounded off, soil and moss in some
		vec3 j1 = joint_set(p, vec2(0.92, 0.39), 2.7, 1.0);
		vec3 j2 = joint_set(p, vec2(-0.31, 0.95), 4.4, 2.0);
		float crack = max(j1.x, j2.x);
		g_grad += (vec2(0.92, 0.39) * sign(j1.y) * smoothstep(0.08, 0.0, abs(j1.y)) * j1.z + vec2(-0.31, 0.95) * sign(j2.y) * smoothstep(0.08, 0.0, abs(j2.y)) * j2.z) * 0.9 * gfade;
		float in_joint = max(smoothstep(0.1, 0.02, abs(j1.y)) * j1.z, smoothstep(0.1, 0.02, abs(j2.y)) * j2.z);
		float jm = smoothstep(0.45, 0.6, texture(macro_noise, p * 0.07 + 6.0).r) * smoothstep(0.7, 0.92, up_n.y);
		gc = mix(gc, vec3(0.09, 0.13, 0.045), in_joint * jm * 0.85);
		gc *= mix(1.0, 0.16, crack);
		// dark streaks where the rain runs down the slabs
		vec2 hn = abs(up_n.xz) + 0.001;
		// (broad stains and narrow runnels of different widths, never evenly spaced)
		// (their lines wander, and only steep rock has them: on flat rock nothing runs off)
		float wv = (texture(macro_noise, p * 0.023 + 0.6).r - 0.5) * 11.0;
		float sx = texture(macro_noise, vec2((p.y + wv) * 0.11, w_pos.y * 0.011 + wv * 0.004)).r * 0.65 + texture(macro_noise, vec2((p.y + wv) * 0.43 + 0.3, w_pos.y * 0.019)).r * 0.35;
		float sz = texture(macro_noise, vec2((p.x + wv) * 0.11 + 0.5, w_pos.y * 0.011 + wv * 0.004)).r * 0.65 + texture(macro_noise, vec2((p.x + wv) * 0.43 + 0.7, w_pos.y * 0.019)).r * 0.35;
		float streak = (sx * hn.x + sz * hn.y) / (hn.x + hn.y);
		gc *= mix(1.0, 0.4, smoothstep(0.48, 0.58, streak) * smoothstep(0.16, 0.36, 1.0 - up_n.y));
		// crusts of lichen (pale gray-green, some orange) where the rock lies flatter
		float lz = texture(macro_noise, p * 0.83 + 2.3).r;
		float lichen = smoothstep(0.6, 0.66, lz) * smoothstep(0.5, 0.62, texture(macro_noise, p * 0.09 + 0.4).r) * smoothstep(0.6, 0.9, up_n.y);
		gc = mix(gc, mix(vec3(0.42, 0.46, 0.36), vec3(0.5, 0.33, 0.1), smoothstep(0.7, 0.74, lz)), lichen * 0.55);
		// at the waterline and below: wet, dark, with a band of algae
		float wetg = smoothstep(0.9, 0.15, w_pos.y);
		gc = mix(gc, gc * vec3(0.45, 0.43, 0.38), wetg);
		gc = mix(gc, vec3(0.1, 0.12, 0.06), smoothstep(0.15, -0.5, w_pos.y) * 0.6);
		// (a dark line of humus where the soil laps onto the rock)
		col = mix(col * mix(1.0, 0.6, smoothstep(0.0, 0.5, granite)), gc, granite);
	}
	// --- the stream (mask alpha, inverted: 1 on its course, 0 two meters to either side) ---
	float wline = 1.0 - lm.a;
	float stream_w = 0.0;
	float damp = 0.0;
	vec2 fl_n = vec2(0.0);
	if (wline > 0.01 && w_pos.y > 0.4) {
		float wn = texture(macro_noise, p * 0.9 + 3.3).r - 0.5;
		// damp rock and soil beside the water, algae and moss close to it
		damp = smoothstep(0.3, 0.75, wline + wn * 0.3);
		col = mix(col, col * vec3(0.5, 0.52, 0.46), damp);
		col = mix(col, vec3(0.06, 0.11, 0.035), smoothstep(0.5, 0.8, wline + wn * 0.6) * smoothstep(0.4, 0.62, texture(macro_noise, p * 0.33 + 1.0).r) * 0.6);
		// the water: a film over the rock, half a meter or so wide, running downhill
		stream_w = smoothstep(0.8, 0.86, wline + wn * 0.16);
		// (mud and wet leaves at the water's edge)
		col = mix(col, vec3(0.085, 0.07, 0.05), smoothstep(0.5, 0.66, wline + wn * 0.2) * (1.0 - granite) * 0.85);
		vec2 gd = vec2(ground_height(p + vec2(0.6, 0.0)) - ground_height(p - vec2(0.6, 0.0)), ground_height(p + vec2(0.0, 0.6)) - ground_height(p - vec2(0.0, 0.6))) / 1.2;
		float sl = length(gd);
		vec2 fdir = -gd / max(sl, 0.02);
		float spd = 0.5 + 1.6 * clamp(sl, 0.0, 1.0);
		float p0 = fract(t * 0.35);
		float p1 = fract(t * 0.35 + 0.5);
		vec2 f0 = texture(water_normal, p * 1.7 - fdir * p0 * spd * 1.2).xy * 2.0 - 1.0;
		vec2 f1 = texture(water_normal, p * 1.7 - fdir * p1 * spd * 1.2 + 0.41).xy * 2.0 - 1.0;
		float w0 = 1.0 - abs(1.0 - 2.0 * p0);
		fl_n = (f0 * w0 + f1 * (1.0 - w0)) * stream_w;
		col = mix(col, col * vec3(0.5, 0.54, 0.48), stream_w);
		// white where it runs fast over a ledge
		float white = smoothstep(0.32, 0.6, sl) * smoothstep(0.12, 0.4, length(fl_n));
		col = mix(col, vec3(0.8, 0.86, 0.86), white * 0.75);
	}
	// seagrass meadows on the lagoon floor
	float sgrass = smoothstep(0.5, 0.58, texture(macro_noise, p * 0.027 + 0.21).r + (texture(macro_noise, p * 0.29).r - 0.5) * 0.3);
	sgrass *= smoothstep(-1.9, -2.7, w_pos.y) * smoothstep(-7.0, -5.2, w_pos.y) * (1.0 - reef);
	col = mix(col, mix(vec3(0.035, 0.07, 0.03), vec3(0.1, 0.16, 0.06), texture(macro_noise, p * 1.9).r), sgrass * 0.9);
	if (reef > 0.0) {
		float r1 = texture(macro_noise, p * 0.83).r;
		vec3 rc = mix(vec3(0.07, 0.055, 0.035), vec3(0.24, 0.19, 0.11), smoothstep(0.3, 0.7, r1));
		rc = mix(rc, vec3(0.3, 0.17, 0.2), smoothstep(0.6, 0.78, texture(macro_noise, p * 0.23 + 0.4).r) * 0.5);    // coralline crusts
		rc = mix(rc, vec3(0.06, 0.1, 0.04), smoothstep(0.52, 0.72, texture(macro_noise, p * 0.41 + 0.9).r) * 0.65);  // algal turf
		col = mix(col, rc, reef);
	}
	float hard = max(granite, max(reef, sgrass));

	// --- height relative to water / swash ---
	// (from here on: the height above the sea as it stands now. What is painted on the ground
	// for good, the reef rock, the seagrass, the algae on the granite, goes by w_pos.y)
	float h = w_pos.y - sea_level;
	float sw = swash(p.y, t);
	float run_up = SWASH_HEIGHT * sw;
	float wet_line = SWASH_HEIGHT * 1.05 + 0.04 * noise1(p.y * 0.2);   // highest reach of the water
	// slow-drying memory: sand below the max run-up stays wet
	float wet = 1.0 - smoothstep(wet_line - 0.02, wet_line + 0.12, h);
	// (and where the tide stood not long ago: damp, less so the longer ago)
	float h_left = w_pos.y - max(tide_wet, sea_level);
	wet = max(wet, (1.0 - smoothstep(wet_line - 0.02, wet_line + 0.2, h_left)) * 0.75);
	// freshly covered sand is wetter (glossy film)
	float film = 1.0 - smoothstep(run_up - 0.03, run_up + 0.05, h);
	film *= step(-0.2, h);

	vec3 wetc = texture(sand_wet_albedo, uva * 0.9).rgb;
	wetc = wetc / max(0.001, dot(vec3(0.33), texture(sand_wet_albedo, vec2(0.5), 12.0).rgb)) * 0.55;
	// (wet sand, not the rock, the reef or the seagrass: under water this used to paint all three
	// over with sand color, so that they only showed faintly, and only from above)
	col = mix(col, wetc * wet_tint * 1.15, wet * 0.85 * (1.0 - hard * 0.8));

	// --- underwater ---
	float under = 1.0 - smoothstep(-0.25, 0.05, h);
	if (under > 0.0) {
		float depth = max(-h, 0.0);
		// (the same net as on everything else under water: shaders/sea_light.gdshaderinc)
		float c = sea_caustics(vec3(p.x, w_pos.y, p.y), t) * caustic_strength;
		float fade = smoothstep(0.0, 0.4, depth) * (1.0 - smoothstep(4.0, 12.0, depth));
		// caustic light only where sunlit (applied as emission so shadows cut it a bit less)
		// (as light falling on the floor: dark seagrass and reef rock throw back less of it than sand)
		EMISSION += vec3(0.9, 1.0, 0.95) * c * fade * 0.55 * under * sea_sun * min(dot(col, vec3(0.45)), 1.0);
		col *= mix(1.0, 0.92, under);
	}

	// --- normals: wind ripples + grain ---
	float dry = smoothstep(wet_line + 0.05, wet_line + 0.6, h);
	vec2 rdir = normalize(vec2(0.25, 1.0));
	float warp = texture(macro_noise, p * 0.05).r * 7.0 + texture(macro_noise, p * 0.17).r * 1.8;
	float rp = dot(p, rdir) * 2.6 + warp;
	float e = 0.02;
	float r0 = ripple(rp);
	float r1 = ripple(rp + e * 2.6);
	float dr = (r1 - r0) / e;
	// fade ripples with distance (avoid aliasing) and near the waterline, stronger in patches
	float rmask = dry * (1.0 - forest) * (1.0 - granite) * smoothstep(60.0, 8.0, dist) * mix(0.15, 1.0, smoothstep(0.4, 0.75, mn2));
	vec2 grad = rdir * dr * 0.025 * ripple_strength * rmask;
	// underwater sand ripples (from currents) parallel to the shore
	float uw = under * (1.0 - hard) * smoothstep(40.0, 5.0, dist);
	float rp2 = p.x * 1.9 + texture(macro_noise, p * 0.08).r * 5.0;
	float dr2 = (sin(rp2 + 0.05) - sin(rp2)) / 0.05;
	grad += vec2(1.0, 0.0) * dr2 * 0.03 * uw;

	vec3 tn = texture(sand_normal, uva * 1.7).xyz * 2.0 - 1.0;
	vec3 tn2 = texture(sand_normal, rot * p / 0.38).xyz * 2.0 - 1.0;
	// (reef: the same grain texture at a coarser scale stands in for its pitted surface)
	vec3 tn3 = texture(sand_normal, p * 0.31 + 0.2).xyz * 2.0 - 1.0;
	vec3 n = normalize(w_nrm + vec3(-grad.x, 0.0, -grad.y) + (vec3(tn.x, 0.0, tn.y) * 0.25 + vec3(tn2.x, 0.0, tn2.y) * 0.35 * near) * (1.0 - forest) * (1.0 - hard)
		+ vec3(floor_n.x, 0.0, floor_n.y) * 0.6 * (1.0 - granite) + vec3(tn3.x, 0.0, tn3.y) * 0.5 * reef
		- vec3(g_grad.x, 0.0, g_grad.y) * granite * (1.0 - 0.7 * stream_w) + vec3(fl_n.x, 0.0, fl_n.y) * 0.45);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// --- sparkles (glinting grains), only in the sun on dry sand ---
	vec2 sc = floor(p * 90.0);
	vec2 hr = hash22(sc);
	vec3 gn = normalize(vec3(hr.x - 0.5, 1.2, hr.y - 0.5));
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_pos);
	vec3 hv = normalize(v + normalize(sun_dir_world));
	float glint = pow(max(dot(gn, hv), 0.0), 900.0);
	glint *= step(0.93, hash22(sc + 17.0).x) * smoothstep(25.0, 3.0, dist) * (1.0 - wet) * (1.0 - under) * (1.0 - forest) * (1.0 - granite) * (1.0 - rain_wet);
	EMISSION += vec3(1.0, 0.97, 0.9) * glint * sparkle_strength;

	// stranded Noctiluca sparkle on the sand the swash has just left
	if (biolum > 0.0) {
		float zone = (1.0 - smoothstep(run_up - 0.01, run_up + 0.07, h)) * step(-0.08, h);
		vec2 bc = floor(p * 38.0);
		vec2 bh = hash22(bc + 3.7);
		float fl = 0.5 + 0.5 * sin(t * (3.0 + 7.0 * bh.y) + bh.x * 50.0);
		float speck = step(0.965, bh.x) * fl * smoothstep(0.42, 0.0, length(fract(p * 38.0) - 0.5));
		EMISSION += biolum_color * speck * zone * biolum * 3.5;
	}
	// rain: the ground above the sea goes dark and a little glossy, and dries off afterward
	// (sand and rock most, the forest floor under its litter less)
	float rw = rain_wet * (1.0 - under) * (1.0 - wet);
	if (rw > 0.0 && rain_roofs) {
		vec2 ruv = (p - rain_open_rect.xy) * rain_open_rect.zw;
		if (ruv.x > 0.0 && ruv.x < 1.0 && ruv.y > 0.0 && ruv.y < 1.0) {
			rw *= texture(rain_open, ruv).r;
		}
	}
	// (wet sand is not only darker but deeper in color)
	col = mix(col, col * col * mix(0.62, 0.95, forest), rw * 0.92);
	// while it rains: the drops' splashes on the ground, small pale specks that come and go
	// (near the eye only; not under the grotto's roof)
	if (rain > 0.002) {
		float open_k = rw / max(rain_wet, 0.001);
		float sp = smoothstep(0.35, 0.9, rain_rings(p, world_time).z) * open_k * smoothstep(22.0, 6.0, dist);
		col = mix(col, vec3(0.78, 0.83, 0.88), sp * 0.55);
	}
	ALBEDO = col;
	// sand covered by water gets no specular of its own (the water surface provides it)
	float covered = max(under, film);
	wet = max(wet, rw * 0.8);
	ROUGHNESS = mix(mix(mix(mix(0.92, 0.72, granite), 0.38, wet) - film * 0.3, 0.95, covered), 0.07, stream_w) - damp * (1.0 - stream_w) * 0.3;
	SPECULAR = mix(mix(0.35, 0.55, wet) * (1.0 - 0.95 * covered), 0.6, stream_w);
}
