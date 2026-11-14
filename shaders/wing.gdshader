shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// A bird's (or flying fox's) wing that bends like one. The mesh (tools/assets6.py) is a flat right
// wing: origin at the shoulder, +X out along the span, +Z back, UV.x = 0 shoulder .. 1 tip,
// UV.y = 1 leading .. 0 trailing edge (glTF flips V), VERTEX.y = camber. The vertex shader walks out along the
// spar, raising or lowering it at the shoulder, bending it at the wrist and on toward the tip,
// folding it (the arm swings a little forward, the hand wing sweeps back from the wrist) and
// twisting it, and hangs the feathers on it. The left wing is the same mesh mirrored (side = -1).
// flight.gd sets `pose` every frame.

uniform vec3 color_in : source_color = vec3(1.0);    // arm
uniform vec3 color_out : source_color = vec3(1.0);   // hand
uniform vec3 color_tip : source_color = vec3(1.0);   // tips of the primaries
uniform vec3 color_under : source_color = vec3(1.0); // the underside ...
uniform float under = 0.0;                           // ... as far as it differs from the upper side (0..1)
uniform float roughness = 0.7;
uniform float backlight = 0.4;     // light shining through
uniform float span = 0.5;          // length of the wing in mesh units (set by flight.gd)
uniform float wrist = 0.42;        // where the hand wing starts, as a fraction of the span
uniform float feathers = 1.0;      // strength of the feather lines (0 for a bat's membrane)
// markings (off unless set; scripts/shorebirds.gd uses them): a bar across the wing from
// (span, chord) to (span, chord), chord 0 at the leading edge, e.g. the tropicbird's black
// diagonal or the turnstone's white wing bar; and the flight feathers along the rear in
// another color (the crab plover's black ones on a white wing)
uniform vec3 color_bar : source_color = vec3(0.0);
uniform vec4 bar_line = vec4(0.0);
uniform float bar_width = 0.0;     // 0: no bar
uniform float bar_upper = 1.0;     // 1: on the upper side only
uniform vec3 color_rear : source_color = vec3(0.0);
uniform float rear_from = 2.0;     // chord from which the rear color holds (above 1: none)

instance uniform vec4 pose = vec4(0.0);   // x: shoulder (up +), y: wrist/tip bend (up +), z: fold 0..1, w: twist (leading edge down +)
instance uniform float side = 1.0;

varying vec3 v_nrm;

vec3 spar(float s, out float sweep) {
	float w = smoothstep(wrist - 0.1, wrist + 0.1, s);
	float elev = pose.x + pose.y * (0.65 * w + 0.35 * s * s);
	sweep = pose.z * mix(-0.3, 1.15, w);
	return vec3(cos(elev) * cos(sweep), sin(elev), cos(elev) * sin(sweep));
}

void vertex() {
	float s = UV.x;
	float sw;
	vec3 p = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		p += spar(s * (float(i) + 0.5) / 8.0, sw);
	}
	p *= s * span / 8.0;
	vec3 t = spar(s, sw);
	// the feathers lie back across the spar
	vec3 c = vec3(-sin(sw), 0.0, cos(sw));
	c = normalize(c - t * dot(c, t));
	vec3 n = cross(c, t);
	float tw = pose.w * s * s;
	vec3 c2 = c * cos(tw) + n * sin(tw);
	vec3 n2 = n * cos(tw) - c * sin(tw);
	p += c2 * VERTEX.z + n2 * VERTEX.y;
	VERTEX = vec3(p.x * side, p.y, p.z);
	v_nrm = (MODELVIEW_MATRIX * vec4(n2.x * side, n2.y, n2.z, 0.0)).xyz;
}

void fragment() {
	float s = UV.x;
	float c = 1.0 - UV.y;   // glTF flips V: 0 at the leading edge again
	// both faces are drawn (and the left wing is a mirror image): color and light the one that is seen
	vec3 nn = normalize(v_nrm);
	bool below = dot(nn, VIEW) < 0.0;
	vec3 col = mix(color_in, color_out, smoothstep(wrist - 0.05, wrist + 0.15, s));
	if (below) {
		col = mix(col, color_under, under);
	}
	col = mix(col, color_tip, smoothstep(0.7, 0.98, s) * (below ? 1.0 - 0.5 * under : 1.0));
	if (rear_from < 1.0) {
		col = mix(col, color_rear, smoothstep(rear_from - 0.06, rear_from + 0.06, c));
	}
	if (bar_width > 0.0) {
		vec2 a = bar_line.xy;
		vec2 ab = bar_line.zw - a;
		vec2 q = vec2(s, c) - a;
		float along = clamp(dot(q, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
		float dist = length(q - ab * along);
		float k = 1.0 - smoothstep(bar_width * 0.7, bar_width, dist);
		col = mix(col, color_bar, k * (below ? 1.0 - bar_upper : 1.0));
	}
	// flight feathers: soft lines across the rear of the wing, fading out with distance
	float lines = s * 16.0 + c * 0.8;
	float f = smoothstep(0.0, 0.25, abs(fract(lines) - 0.5));
	float fade = clamp(1.0 - fwidth(lines) * 2.5, 0.0, 1.0);
	col *= 1.0 - feathers * 0.16 * (1.0 - f) * smoothstep(0.3, 0.9, c) * fade;
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	BACKLIGHT = col * backlight;
	NORMAL = below ? -nn : nn;
}
