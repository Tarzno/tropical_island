shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/sea_light.gdshaderinc"

// The day octopus (mesh: scripts/reef_models.gd: octopus(); one MeshInstance3D each, set by
// scripts/reef_life.gd). The body is where the mesh has it; the eight arms are worked out
// here: each vertex of an arm knows which arm it is on and how far along, and the shader
// walks out along the arm's line from the head, turning as it goes: sideways (the coil),
// downward (arms that hang over an edge), and with a slow wave of its own. On the way every
// step is kept out of the animal's rock and off the sea floor around it (`rock_r()` is the
// rock's own shape, the same sum as reef_models.gd: den_radius()): the arms lie ON the
// stone, slide over its edges and down its sides, and never go through it.
// COLOR.r = 1: an arm (UV.x = which, UV.y = how far along; VERTEX.xy = the offset from its
// line; COLOR.g = 1 the upper side .. 0 the underside). Otherwise the body: COLOR.b = how
// much of the mantle's breathing a vertex takes part in; COLOR.a = 0 the pupils.

global uniform float world_time;
instance uniform float curl = 1.0;      // how tightly the arms are coiled (0.3 lying loose .. 3 rolled up)
instance uniform float droop = 0.0;     // the arms bend down over what they lie on (1: over the top of its rock)
instance uniform float tuck = 0.0;      // the arms folded back beside the body (0 .. 1), as in its hole
instance uniform float pale = 0.3;      // the skin: 0 dark red-brown .. 1 pale as the sand
instance uniform float writhe = 1.0;    // how much the arms move
instance uniform float seed = 0.0;      // this animal's own phase
// the rock it lives in: the rows of the matrix that takes this model's space to the rock's
// own (the lump at its unscaled size, the ground at y = 0); rock_k: its two shape numbers,
// in z how firmly the arms are held out of it (0: not at all: when there is no rock), and
// in w how far the arms are drawn in to the body (0 .. 1). An animal that goes back into
// its hole gathers its arms first: they shorten and coil in to the head, on the rock and
// joined to it all the while, and only then does the body sink. (Until 2026-11-12 the
// body sank into the hole first and the arms lay on the rock without it for a moment.
// Arms that slid in thick end first, leaving the thin ends out, looked like a spider's legs.)
instance uniform vec4 rock0 = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 rock1 = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 rock2 = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform vec4 rock_k = vec4(0.0);
instance uniform vec3 floor_n = vec3(0.0, 1.0, 0.0);    // the sea floor's normal there, in the rock's space

const float ALEN = 0.55;

varying vec3 o_pos;
varying vec2 v_arm;       // x: 1 on an arm; y: how far along
varying float v_under;

float h11(float n) { return fract(sin(n * 127.1 + 1.7) * 43758.5453); }

const vec3 ROCK_C = vec3(0.0, -0.04, 0.0);
const vec3 ROCK_AXIS = vec3(0.0, 0.643, -0.766);
const float ROCK_REACH = 0.56;      // (the rock is 0.4 to 0.48 across at the floor)

// the rock's surface: its distance from ROCK_C in the direction d
float rock_r(vec3 d) {
	float k1 = rock_k.x;
	float k2 = rock_k.y;
	float rad = inversesqrt(d.x * d.x / 0.1936 + d.y * d.y / 0.0961 + d.z * d.z / 0.16);
	rad *= 1.0 + 0.1 * sin(d.x * 5.3 + k1) * sin(d.z * 4.7 + k2) + 0.07 * sin(d.y * 9.0 + d.x * 6.0 + k2) + 0.04 * sin(d.z * 13.0 + k1 * 2.0);
	float al = acos(clamp(dot(d, ROCK_AXIS), -1.0, 1.0));
	float a0 = 0.5 + 0.06 * sin(atan(d.z, d.x) * 3.0 + k1);
	float dent = 1.0 - smoothstep(a0 * 0.45, a0, al);
	float lip = (al - a0 * 1.12) / 0.12;
	return rad * (1.0 - 0.6 * dent + 0.07 * exp(-lip * lip));
}

// Keeps p (in the rock's space) out of the rock and above the floor, with `gap` to spare.
// Returns the surface's normal where it touched (zero where it did not).
vec3 keep_out(inout vec3 p, float gap, float hold) {
	vec3 n = vec3(0.0);
	for (int pass = 0; pass < 2; pass++) {
		vec3 q = p - ROCK_C;
		float r = max(length(q), 0.0001);
		vec3 d = q / r;
		float want = rock_r(d) + gap;
		if (r < want) {
			p = ROCK_C + d * mix(r, want, hold);
			n = d;
		}
		float h = dot(p, floor_n) - gap;
		if (h < 0.0) {
			p -= floor_n * (h * hold);
			n = floor_n;
		}
		// and it stays at its own rock: an arm that has come down to the floor lies along
		// the foot of the rock, not out among the neighbors
		float out_ = length(p.xz);
		if (out_ > ROCK_REACH) {
			p.xz *= mix(1.0, ROCK_REACH / out_, hold);
		}
	}
	return n;
}

void vertex() {
	float t = world_time + seed;
	o_pos = VERTEX;
	v_arm = vec2(COLOR.r, UV.y);
	v_under = 1.0 - COLOR.g;
	if (COLOR.r > 0.5) {
		float arm = floor(UV.x * 8.0);
		float s = UV.y;
		float reel = rock_k.w;
		// (a drawn-in arm is shorter, and at the last thinner: it is under the body then)
		float alen = ALEN * (1.0 - 0.9 * reel);
		float thick = 1.0 - smoothstep(0.8, 1.0, reel);
		float h = h11(arm + seed * 0.37);
		// where it leaves the head: around the crown, the first arms to the front
		float az = (arm + 0.5) / 8.0 * 6.2831;
		az = az > 3.14159 ? az - 6.2831 : az;       // -pi .. pi, 0 = straight ahead
		// (folded back: all of them leave toward the rear)
		float az1 = mix(az, sign(az) * 2.7, tuck);
		mat4 to_rock = transpose(mat4(rock0, rock1, rock2, vec4(0.0, 0.0, 0.0, 1.0)));
		mat3 turn_r = mat3(to_rock);
		float size = length(turn_r[0]);            // the model's size in the rock's space
		float hold = rock_k.z;
		vec3 p = (to_rock * vec4(sin(az) * 0.042, 0.012, -cos(az) * 0.042 - 0.004, 1.0)).xyz;
		float yaw = az1;
		float pit = -0.12;
		float side = h > 0.5 ? 1.0 : -1.0;
		float ds = s / 12.0;
		vec3 prev = p;
		vec3 touch = vec3(0.0);
		vec3 dir = vec3(sin(yaw) * cos(pit), sin(pit), -cos(yaw) * cos(pit));
		for (int i = 0; i < 12; i++) {
			float si = (float(i) + 0.5) * ds;
			// the coil: gentle near the head, tight at the tip, and always a curl at the very end
			float kl = side * (curl * (1.2 + 7.0 * si * si) + 9.0 * si * si * si * si);
			kl += writhe * sin(t * (0.5 + 0.4 * h) + arm * 2.1 - si * 6.0) * (0.5 + 1.6 * si);
			float kv = -droop * 1.7 * (0.5 + si) + writhe * 0.5 * sin(t * 0.37 + arm * 1.3 - si * 4.0);
			yaw += kl * ds;
			pit = clamp(pit + kv * ds, -2.2, 0.6);
			dir = vec3(sin(yaw) * cos(pit), sin(pit), -cos(yaw) * cos(pit));
			prev = p;
			p += turn_r * dir * (alen * ds);
			if (hold > 0.0) {
				// (the arm's own thickness here, and a little)
				float gap = (0.022 * thick * (1.0 - 0.85 * pow(si, 0.7)) + 0.003) * size;
				vec3 n = keep_out(p, gap, hold);
				touch = mix(touch, n, step(0.5, dot(n, n)));
			}
		}
		// the ring of the arm here: across its line, the underside to whatever it lies on
		vec3 tg = p - prev;
		tg = dot(tg, tg) > 1e-12 ? normalize(tg) : normalize(turn_r * dir);
		vec3 up_want = dot(touch, touch) > 0.5 ? normalize(mix(turn_r[1] / size, touch, hold)) : turn_r[1] / size;
		vec3 sd = cross(tg, up_want);
		sd = dot(sd, sd) > 1e-6 ? normalize(sd) : normalize(cross(tg, vec3(0.3, 0.2, 0.93)));
		vec3 up = cross(sd, tg);
		vec3 n = NORMAL;
		vec3 at = p + (sd * VERTEX.x + up * VERTEX.y) * (size * thick);
		VERTEX = (inverse(to_rock) * vec4(at, 1.0)).xyz;
		NORMAL = normalize(transpose(turn_r) * (sd * n.x + up * n.y));
	} else {
		// breathing: the mantle fills and empties
		float b = COLOR.b * (0.5 + 0.5 * sin(t * 2.1));
		VERTEX.xy = vec2(0.0, 0.066) + (VERTEX.xy - vec2(0.0, 0.066)) * (1.0 + 0.09 * b);
	}
}

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// the skin: blotches that the animal darkens or lets fade, pale flecks, a fine grain
	vec3 q = v_arm.x > 0.5 ? vec3(o_pos.xy * 3.0, v_arm.y * 0.55 + UV.x * 7.0) : o_pos;
	float blot = vn(q * 23.0 + seed) * 0.65 + vn(q.yzx * 57.0 + 3.0) * 0.35;
	float fleck = smoothstep(0.62, 0.75, vn(q * 120.0));
	vec3 dark = mix(vec3(0.2, 0.045, 0.022), vec3(0.055, 0.02, 0.014), smoothstep(0.38, 0.62, blot));
	vec3 light = mix(vec3(0.5, 0.43, 0.33), vec3(0.3, 0.22, 0.16), smoothstep(0.4, 0.62, blot) * 0.6);
	vec3 c = mix(dark, light, pale);
	c = mix(c, c * 1.5 + vec3(0.06, 0.05, 0.04), fleck * 0.5);
	float rough = 0.4;
	if (v_arm.x > 0.5) {
		// underneath: pale, with the two rows of suckers
		float suck = smoothstep(0.25, 0.4, abs(fract(v_arm.y * 46.0) - 0.5));
		vec3 under = mix(vec3(0.74, 0.62, 0.56), vec3(0.9, 0.84, 0.8), suck);
		c = mix(c, under, smoothstep(0.45, 0.8, v_under));
	}
	if (COLOR.a < 0.5) {
		c = vec3(0.008);
		rough = 0.15;
	}
	ALBEDO = c;
	// the net of light from the rippled surface (shaders/sea_light.gdshaderinc)
	EMISSION += ALBEDO * sea_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world_time) * 2.2;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.6) / 1.6, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * (0.3 + 0.7 * ATTENUATION) * LIGHT_COLOR / PI;
}
