shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/sea_light.gdshaderinc"
global uniform float world_time;

// Tiger shark (species 0), spotted eagle ray (species 1), blacktip reef shark (species 2), manta
// ray (species 3), giant grouper (species 4), titan triggerfish (5), clown triggerfish (6),
// spinner dolphin (7: seen far off only; the script moves it as a whole), great barracuda (8),
// Moorish idol (9).
// The meshes are built in scripts/sea_models.gd: forward = -Z, up = +Y. Instance uniforms drive
// the swimming motion.
// Sharks: UV.x = place along the body (0 snout .. 1 tail tip), UV.y = the way around the trunk
// (0 belly, 0.5 back; -1 on fins and eyes), COLOR.r = black fin tip, COLOR.g = dark back (1)
// to pale belly (0), COLOR.b = pale band under a black tip, COLOR.a = 0 on the eyes.
// A wave runs down the body, small at the head (which swings a little against it) and growing
// to the tail; `bend` curves the whole body along the turn it is swimming.
// Ray: the pectoral "wings" beat up and down with a wave running from the body to the tips.

uniform int species = 0;
instance uniform float phase = 0.0;      // swim cycle (radians, advanced by the script)
instance uniform float amp = 1.0;        // stroke strength
instance uniform float bend = 0.0;       // turning: the body lies along the curve

varying vec3 o_pos;
varying vec3 o_nrm;
varying float v_fin;      // triggerfish: how far out on a swimming fin (0 at its root .. 1)

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec2 cell_spots(vec2 p) {
	// distance to the nearest jittered spot center and that spot's random value
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.3));
			float dd = length(g + o * 0.8 + 0.1 - f);
			if (dd < best) { best = dd; id = h21(i + g + 3.1); }
		}
	}
	return vec2(best, id);
}

// The middle of the nearest spot of the same jittered pattern (to keep or drop whole spots).
vec2 cell_center(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	vec2 at = p;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.3));
			float dd = length(g + o * 0.8 + 0.1 - f);
			if (dd < best) { best = dd; at = i + g + o * 0.8 + 0.1; }
		}
	}
	return at;
}

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
	if (species == 3) {
		// manta: long slow beats of the whole wing, the tips trailing behind the stroke
		float ax = abs(VERTEX.x);
		float wing = smoothstep(0.1, 1.0, ax);
		float lag = phase - ax * 1.7;
		VERTEX.y += (sin(lag) * 0.4 + 0.06) * amp * pow(wing, 1.5);
		VERTEX.z += cos(lag) * 0.05 * amp * wing * wing;
		float tail = smoothstep(0.5, 1.25, VERTEX.z);
		VERTEX.x += sin(phase * 0.5 - VERTEX.z * 2.0) * 0.05 * tail + bend * tail * 0.3;
	} else if (species == 7) {
		// (nothing: a dolphin beats its flukes up and down, and is too far off to show it)
	} else if (species == 8) {
		// barracuda: a stiff rod of a fish; hanging in the water only the tail sculls, and
		// when it swims the wave is in the hind third
		float t = UV.x;
		float env = 0.01 - 0.07 * t + 0.27 * t * t * t * 1.25;
		VERTEX.x += sin(phase - t * 5.4) * amp * max(env, 0.0);
		float dt = t - 0.45;
		VERTEX.x += bend * dt * dt;
		// the breast fins scull to hold it in place
		float fin = step(UV.y, -0.5) * smoothstep(0.12, 0.3, abs(VERTEX.x)) * step(t, 0.36);
		float sd = sign(VERTEX.x);
		VERTEX.z += sin(world_time * 2.3 + sd * 0.9) * 0.035 * fin;
		VERTEX.y += cos(world_time * 2.3 + sd * 0.9) * 0.03 * fin;
	} else if (species == 9) {
		// Moorish idol: a stiff disc; it sculls with its breast fins and beats a small quick
		// tail, and the streamer of its back fin trails behind and sways, late
		float t = UV.x;
		float dt = max(t - 0.6, 0.0);
		VERTEX.x += sin(phase - t * 5.0) * amp * 0.75 * dt * dt + bend * (t - 0.45) * (t - 0.45) * 0.7;
		float streamer = step(1.8, VERTEX.y) * clamp((t - 0.48) / 0.9, 0.0, 1.0);
		VERTEX.x += (sin(phase * 0.35 - t * 3.6) * 0.2 + bend * 0.9) * streamer * streamer;
		float fin = step(UV.y, -0.5) * smoothstep(0.2, 0.36, abs(VERTEX.x));
		float sd = sign(VERTEX.x);
		VERTEX.z += sin(world_time * 6.5 + sd * 0.9) * 0.035 * fin;
		VERTEX.y += cos(world_time * 6.5 + sd * 0.9) * 0.05 * fin;
	} else if (species >= 5) {
		// triggerfish: the body is stiff; waves run back along the fin on the back and the
		// fin below, which is how it swims (the tail only helps in a hurry: `bend`)
		float t = UV.x;
		float root = mix(0.82, 0.22, clamp((t - 0.5) / 0.335, 0.0, 1.0));
		float on_fin = step(UV.y, -0.5) * step(abs(VERTEX.x), 0.08) * step(0.49, t) * step(t, 0.845);
		v_fin = on_fin * clamp((abs(VERTEX.y) - root) / 0.42, 0.0, 1.0);
		VERTEX.x += sin(phase - t * 30.0 + (VERTEX.y > 0.0 ? 0.0 : 1.3)) * 0.085 * amp * v_fin;
		float tail = smoothstep(0.78, 1.0, t);
		VERTEX.x += (bend * 0.5 + sin(phase * 0.5) * 0.02 * amp) * tail * tail * 2.0;
		// the breast fins flutter
		float fin = step(UV.y, -0.5) * smoothstep(0.2, 0.42, abs(VERTEX.x));
		VERTEX.z += sin(world_time * 9.0 + sign(VERTEX.x)) * 0.03 * fin;
		VERTEX.y += cos(world_time * 9.0 + sign(VERTEX.x)) * 0.04 * fin;
	} else if (species == 4) {
		// grouper: a heavy fish that holds its place with its breast fins and swims with the
		// hind third of its body and the tail, slowly
		float t = UV.x;
		float env = 0.006 - 0.05 * t + 0.21 * t * t;
		VERTEX.x += sin(phase - t * 4.6) * amp * env;
		float dt = t - 0.45;
		VERTEX.x += bend * dt * dt;
		float fin = step(UV.y, -0.5) * smoothstep(0.34, 0.7, abs(VERTEX.x));
		float sd = sign(VERTEX.x);
		VERTEX.z += sin(world_time * 1.7 + sd * 0.8) * 0.07 * fin;
		VERTEX.y += cos(world_time * 1.7 + sd * 0.8) * 0.06 * fin;
		// the gill covers open and close as it breathes
		VERTEX.x *= 1.0 + 0.035 * (0.5 + 0.5 * sin(world_time * 1.3)) * smoothstep(0.14, 0.24, t) * (1.0 - smoothstep(0.27, 0.33, t)) * step(-0.5, UV.y);
	} else if (species != 1) {
		float t = UV.x;
		// the traveling wave: the snout swings a little, the body is stillest behind the head,
		// and from there the wave grows to the wide sweep of the tail. The big shark swims with
		// its whole body (seen from above it is an S that runs down it: with the front two
		// thirds held still it looked like a plank with a wagging tail); the small one's wave
		// is tighter and faster
		float env = species == 0 ? 0.11 - 0.44 * t + 0.82 * t * t : 0.028 - 0.11 * t + 0.42 * t * t;
		float waves = species == 0 ? 6.6 : 6.2;
		VERTEX.x += sin(phase - t * waves) * amp * env;
		// the turn: the body lies along an arc (offsets from the line the model is set on)
		float dt = t - 0.45;
		VERTEX.x += bend * dt * dt;
		VERTEX.y += sin(phase * 0.5) * 0.008;
	} else {
		float ax = abs(VERTEX.x);
		float wing = smoothstep(0.08, 0.85, ax);
		float tail = smoothstep(0.25, 2.6, VERTEX.z);
		VERTEX.y += sin(phase - ax * 2.2) * amp * 0.28 * wing * wing;
		VERTEX.y += sin(phase * 0.5 - VERTEX.z * 2.0) * 0.04 * tail;
		VERTEX.x += sin(phase * 0.3 - VERTEX.z * 1.4) * 0.08 * tail + bend * tail * 0.4;
	}
}

// The five gill slits: short dark lines on the flank in front of the pectoral fin.
float gills(vec2 uv, float u0) {
	if (uv.y < 0.0) {
		return 0.0;
	}
	float k = (uv.x - u0) / 0.0125;
	float slit = 1.0 - smoothstep(0.1, 0.2, abs(fract(k) - 0.5));
	float flank = abs(abs(uv.y - 0.5) - 0.25);     // 0 on the widest line of either side
	float side = 1.0 - smoothstep(0.045, 0.06, abs(abs(uv.y - 0.5) - 0.235));
	return slit * side * step(0.0, k) * step(k, 5.0) * (0.6 + 0.0 * flank);
}

void fragment() {
	vec3 c;
	float rough = 0.45;
	float spec = 0.35;
	bool back = o_nrm.y > -0.15;
	if (species == 0) {
		// countershaded: gray-brown back with faded dark vertical bars on the flanks and the
		// tail stock (they give the tiger shark its name), white belly
		float top = COLOR.g;
		vec3 back_c = vec3(0.105, 0.1, 0.085);
		if (UV.y >= 0.0) {
			float bar_id = floor(UV.x * 26.0);
			float wob = sin(UV.y * 34.0 + bar_id * 2.3) * 0.16 + (h21(vec2(bar_id, 3.0)) - 0.5) * 0.4;
			float bars = 1.0 - smoothstep(0.16, 0.34, abs(fract(UV.x * 26.0 + wob) - 0.5));
			// (broken into blotches high on the back, gone on the head)
			bars *= smoothstep(0.2, 0.3, UV.x) * (0.55 + 0.45 * sin(UV.y * 60.0 + bar_id * 5.1)) * 0.6;
			back_c = mix(back_c, vec3(0.034, 0.032, 0.028), clamp(bars, 0.0, 1.0));
		}
		c = mix(vec3(0.62, 0.62, 0.6), back_c, top);
		c = mix(c, vec3(0.02), gills(UV, 0.165));
		rough = 0.4;
	} else if (species == 2) {
		// blacktip reef shark: sandy gray-brown back, white belly, the tips of the fins black,
		// a pale band below the black on the first dorsal fin
		float top = COLOR.g;
		c = mix(vec3(0.74, 0.74, 0.7), vec3(0.21, 0.175, 0.13), top);
		c = mix(c, vec3(0.66, 0.64, 0.58), COLOR.b * 0.85);
		c = mix(c, vec3(0.012, 0.012, 0.012), COLOR.r);
		c = mix(c, vec3(0.02), gills(UV, 0.16));
		rough = 0.4;
	} else if (species == 8) {
		// great barracuda: bright silver, the back blue-gray to green, the belly white; a row
		// of faint dark bars slanting down from the back, and a few inky blotches scattered
		// on the lower flank toward the tail; the fins behind the middle dark
		float top = COLOR.g;
		vec3 silver = vec3(0.7, 0.74, 0.76);
		c = mix(vec3(0.86, 0.87, 0.86), silver, smoothstep(0.02, 0.3, top));
		c = mix(c, vec3(0.1, 0.16, 0.18), smoothstep(0.68, 0.97, top));
		if (UV.y >= 0.0) {
			float side = abs(UV.y - 0.5);              // 0 on the back's middle line .. 0.5 on the belly's
			float bars = 1.0 - smoothstep(0.17, 0.33, abs(fract(UV.x * 24.0 + side * 3.2) - 0.5));
			bars *= (1.0 - smoothstep(0.17, 0.27, side)) * smoothstep(0.02, 0.07, side) * smoothstep(0.24, 0.3, UV.x) * (1.0 - smoothstep(0.84, 0.9, UV.x));
			c = mix(c, vec3(0.13, 0.17, 0.19), bars * 0.5);
			float cell = floor(UV.x * 17.0);
			float has = step(0.5, h21(vec2(cell, 7.0))) * smoothstep(0.42, 0.5, UV.x) * (1.0 - smoothstep(0.86, 0.9, UV.x));
			vec2 at = vec2(fract(UV.x * 17.0) - 0.3 - 0.4 * h21(vec2(cell, 1.0)), (side - 0.29 - 0.07 * h21(vec2(cell, 4.0))) * 9.0);
			c = mix(c, vec3(0.02, 0.025, 0.03), has * (1.0 - smoothstep(0.1, 0.19 + 0.08 * h21(vec2(cell, 9.0)), length(at))) * 0.92);
		} else {
			// fins: the second back fin, the anal fin and the tail blackish with pale tips
			float dark = smoothstep(0.55, 0.62, UV.x);
			c = mix(vec3(0.3, 0.34, 0.36), vec3(0.05, 0.06, 0.07), dark);
			c = mix(c, vec3(0.7, 0.72, 0.7), dark * smoothstep(0.3, 0.37, abs(o_pos.y)));
		}
		rough = 0.28;
		spec = 0.65;
	} else if (species == 7) {
		// spinner dolphin: a dark gray cape, paler gray flanks, a white belly
		float top = COLOR.g;
		c = mix(vec3(0.8, 0.8, 0.78), mix(vec3(0.3, 0.32, 0.35), vec3(0.07, 0.075, 0.085), smoothstep(0.55, 0.9, top)), smoothstep(0.05, 0.4, top));
		rough = 0.4;
		spec = 0.4;
	} else if (species == 9) {
		// Moorish idol: white; a broad black band from the nape through the eye to the
		// breast, a second, narrower one from the back fin to the fin below, yellow behind
		// it and washing over the white between them; an orange saddle on the snout; a
		// black tail with a pale edge; the streamer white
		vec3 white = vec3(0.92, 0.92, 0.86);
		vec3 black = vec3(0.012, 0.012, 0.016);
		vec3 yellow = vec3(0.93, 0.72, 0.08);
		float u = UV.x;
		float hi = o_pos.y;
		// (the second band leans back a little as it runs out into the fins)
		float u2 = u - max(abs(hi) - 0.9, 0.0) * 0.035;
		float band2 = smoothstep(0.555, 0.565, u2) * (1.0 - smoothstep(0.675, 0.685, u2));
		if (UV.y >= 0.0) {
			c = mix(white, yellow, smoothstep(0.43, 0.56, u) * 0.5);
			c = mix(c, black, smoothstep(0.2, 0.21, u) * (1.0 - smoothstep(0.365, 0.375, u)));
			c = mix(c, black, band2);
			// a pale line behind the band, then yellow, paling to the tail stock
			c = mix(c, yellow, smoothstep(0.695, 0.705, u2) * (1.0 - smoothstep(0.76, 0.82, u)));
			// the snout: an orange saddle on its upper half, edged with black; black lips
			float rel = hi - (-0.3 + 0.85 * u);
			float sad = smoothstep(0.055, 0.07, u) * (1.0 - smoothstep(0.15, 0.175, u));
			c = mix(c, black, sad * smoothstep(-0.005, 0.01, rel) * 0.9);
			c = mix(c, vec3(0.95, 0.47, 0.05), sad * smoothstep(0.02, 0.035, rel) * smoothstep(0.065, 0.08, u) * (1.0 - smoothstep(0.14, 0.16, u)));
			c = mix(c, black, 1.0 - smoothstep(0.012, 0.022, u));
		} else if (abs(o_pos.x) > 0.17) {
			// the breast fins: pale and clear
			c = vec3(0.74, 0.74, 0.68);
		} else if (u > 0.825 && abs(hi) < 0.7) {
			// the tail: black, a pale edge
			c = mix(black, vec3(0.75, 0.8, 0.82), smoothstep(0.955, 0.972, u + (0.52 - abs(hi)) * 0.02));
		} else {
			c = mix(white, yellow, smoothstep(0.43, 0.56, u) * 0.4 * step(hi, 1.8));
			c = mix(c, black, band2 * step(hi, 1.9));
			c = mix(c, yellow, smoothstep(0.695, 0.705, u2) * step(hi, 1.2) * 0.9);
			// the small belly fins are black
			c = mix(c, black, step(hi, -0.85) * step(u, 0.415));
		}
		rough = 0.4;
		spec = 0.4;
	} else if (species == 5) {
		// titan triggerfish: every scale yellow-olive with a dark middle (a net of diamonds
		// over the whole body), a dark band above the mouth like a mustache, yellow
		// cheeks, a dark mask from the eyes down to the breast fins, the fins yellowish
		// with broad black edges
		vec2 g = vec2(o_pos.z + o_pos.y, o_pos.z - o_pos.y) * 9.0;
		vec2 f = abs(fract(g) - 0.5);
		float scale_mid = 1.0 - smoothstep(0.12, 0.3, max(f.x, f.y));
		c = mix(vec3(0.36, 0.33, 0.1), vec3(0.06, 0.07, 0.045), scale_mid * 0.85);
		if (UV.y >= 0.0) {
			float u = UV.x;
			float hi = o_pos.y;
			c = mix(c, vec3(0.5, 0.36, 0.08), (1.0 - smoothstep(0.2, 0.27, u)) * smoothstep(0.075, 0.1, u) * (1.0 - smoothstep(0.0, 0.25, hi)) * 0.85);
			c = mix(c, vec3(0.03, 0.035, 0.03), (1.0 - smoothstep(0.012, 0.02, abs(u - 0.052))) * 0.9);
			float mask = (1.0 - smoothstep(0.035, 0.06, abs(u - 0.29 - (0.42 - hi) * 0.12))) * smoothstep(-0.35, -0.15, hi);
			c = mix(c, vec3(0.035, 0.04, 0.03), mask * 0.8);
			c = mix(c, vec3(0.45, 0.4, 0.2), (1.0 - smoothstep(0.0, 0.03, u)) * 0.7);
		} else {
			float edge = max(smoothstep(0.55, 0.9, v_fin), smoothstep(0.955, 0.985, UV.x));
			c = mix(vec3(0.5, 0.42, 0.1), vec3(0.02), edge);
		}
		rough = 0.5;
		spec = 0.3;
	} else if (species == 6) {
		// clown triggerfish: black; big round white spots on the lower half; a yellow saddle
		// with small dark spots on the back; orange-yellow lips with a pale ring behind
		// them; a pale band across the snout under the eyes; a pale band on the tail
		c = vec3(0.012, 0.012, 0.014);
		if (UV.y >= 0.0) {
			float u = UV.x;
			float hi = o_pos.y;
			vec2 sq = vec2(o_pos.z * 2.6, o_pos.y * 2.6) + 3.3;
			vec2 sp = cell_spots(sq);
			// (whole spots only: those whose middle lies on the lower half and on the body)
			vec2 mid = (cell_center(sq) - 3.3) / 2.6;
			float white = (1.0 - smoothstep(0.24, 0.3, sp.x)) * step(mid.y, -0.12) * step(-0.72, mid.x) * step(mid.x, 0.86);
			c = mix(c, vec3(0.9, 0.9, 0.86), white);
			float saddle = smoothstep(0.3, 0.42, hi) * smoothstep(0.34, 0.4, u) * (1.0 - smoothstep(0.6, 0.68, u));
			vec2 dots = cell_spots(vec2(o_pos.z, o_pos.y) * 11.0);
			vec3 sad = mix(vec3(0.6, 0.52, 0.1), vec3(0.03), 1.0 - smoothstep(0.16, 0.24, dots.x));
			c = mix(c, sad, saddle);
			c = mix(c, vec3(0.82, 0.8, 0.62), (1.0 - smoothstep(0.014, 0.022, abs(u - 0.175))) * smoothstep(-0.3, -0.1, hi) * 0.9);
			c = mix(c, vec3(0.85, 0.82, 0.6), (1.0 - smoothstep(0.004, 0.009, abs(u - 0.062))));
			c = mix(c, vec3(0.9, 0.5, 0.06), 1.0 - smoothstep(0.03, 0.04, u));
			c = mix(c, vec3(0.75, 0.7, 0.4), (1.0 - smoothstep(0.012, 0.02, abs(u - 0.83))) * 0.9);
		} else {
			// the swimming fins pale and clear with a dark root, the tail black with a pale band
			c = mix(vec3(0.02), vec3(0.72, 0.7, 0.55), smoothstep(0.08, 0.3, v_fin));
			c = mix(c, vec3(0.8, 0.76, 0.5), (1.0 - smoothstep(0.02, 0.035, abs(UV.x - 0.93))) * step(0.86, UV.x));
			c = mix(c, vec3(0.7, 0.6, 0.2), smoothstep(0.2, 0.42, abs(o_pos.x)));
		}
		rough = 0.4;
		spec = 0.4;
	} else if (species == 4) {
		// giant grouper: dark olive-gray, mottled with paler blotches that run together, fine
		// dark speckles, a paler belly and throat; the fins dusky with small black spots
		float top = COLOR.g;
		vec3 dark = vec3(0.07, 0.066, 0.05);
		vec3 pale = vec3(0.22, 0.21, 0.165);
		if (UV.y >= 0.0) {
			vec2 q = vec2(UV.x * 13.0, UV.y * 11.0);
			vec2 sp = cell_spots(q + vec2(sin(UV.y * 31.0 + UV.x * 9.0), cos(UV.x * 27.0 + UV.y * 13.0)) * 0.45);
			float blotch = (1.0 - smoothstep(0.2, 0.55, sp.x)) * step(0.35, sp.y) * (0.5 + 0.5 * sp.y);
			vec2 sp2 = cell_spots(q * 3.7 + 9.0);
			c = mix(dark, pale, blotch * 0.62);
			c = mix(c, dark * 0.5, (1.0 - smoothstep(0.08, 0.16, sp2.x)) * 0.6);
			c = mix(vec3(0.3, 0.29, 0.25), c, smoothstep(0.0, 0.55, top));
			// the mouth: a dark line back from the snout, turning down at its corner, pale thick lips
			float side_y = abs(UV.y - 0.5);                  // 0 on the back .. 0.5 on the belly
			float line = 0.305 + 0.5 * UV.x * UV.x * 8.0 * 0.1;
			float m = (1.0 - smoothstep(0.006, 0.014, abs(side_y - line))) * (1.0 - smoothstep(0.115, 0.125, UV.x));
			float lip = (1.0 - smoothstep(0.014, 0.05, abs(side_y - line))) * (1.0 - smoothstep(0.1, 0.14, UV.x));
			c = mix(c, vec3(0.32, 0.3, 0.25), lip * 0.6);
			c = mix(c, vec3(0.012), m);
		} else {
			vec2 sp = cell_spots(o_pos.zy * 16.0 + o_pos.x * 5.0);
			c = mix(vec3(0.15, 0.135, 0.085), vec3(0.015), 1.0 - smoothstep(0.16, 0.26, sp.x));
		}
		rough = 0.5;
		spec = 0.3;
	} else if (species == 3) {
		// manta: black above with a pale mark on either shoulder, white below with the five
		// gill slits on either side and a dusky edge to the wings
		vec3 back_c = vec3(0.016, 0.018, 0.024);
		float ax = abs(o_pos.x);
		float mark = (1.0 - smoothstep(0.035, 0.085, abs(o_pos.z - (-0.14 + 0.42 * ax)))) * smoothstep(0.07, 0.13, ax) * (1.0 - smoothstep(0.42, 0.6, ax));
		back_c = mix(back_c, vec3(0.42, 0.45, 0.48), mark * 0.85);
		vec3 belly = vec3(0.88, 0.88, 0.86);
		float k = (o_pos.z + 0.2) / 0.062;
		float slit = (1.0 - smoothstep(0.08, 0.16, abs(fract(k) - 0.5))) * step(0.0, k) * step(k, 5.0);
		slit *= smoothstep(0.08, 0.1, ax) * (1.0 - smoothstep(0.24, 0.27, ax - 0.03 * k / 5.0));
		belly = mix(belly, vec3(0.05), slit * 0.9);
		float edge = smoothstep(0.55, 0.95, ax) * 0.55 + smoothstep(0.75, 1.0, cell_spots(o_pos.xz * 7.0).y) * smoothstep(0.0, 0.2, o_pos.z) * (1.0 - smoothstep(0.0, 0.3, ax)) * 0.7;
		belly = mix(belly, vec3(0.2, 0.2, 0.22), clamp(edge, 0.0, 0.85));
		c = back ? back_c : belly;
		rough = 0.4;
	} else {
		// eagle ray: inky blue-black back covered with small white rings and spots, white belly
		vec3 back_c = vec3(0.02, 0.025, 0.035);
		vec2 sp = cell_spots(o_pos.xz * 16.0);
		float spot = 1.0 - smoothstep(0.13, 0.2, sp.x);
		float ring = smoothstep(0.12, 0.17, sp.x) * (1.0 - smoothstep(0.2, 0.27, sp.x)) * step(0.55, sp.y);
		float on_disc = 1.0 - smoothstep(0.3, 0.45, o_pos.z);   // no spots on the tail
		vec3 dots = vec3(0.85, 0.88, 0.9);
		back_c = mix(back_c, dots, clamp(spot * step(sp.y, 0.55) + ring, 0.0, 1.0) * on_disc);
		c = back ? back_c : vec3(0.88, 0.88, 0.86);
		rough = 0.35;
	}
	if (COLOR.a < 0.5) {
		// the eye
		c = vec3(0.004);
		rough = 0.12;
		spec = 0.8;
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
