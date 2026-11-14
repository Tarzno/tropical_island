shader_type spatial;
// Still fresh water: the rock pools of the stream and the pond at its end. A flat sheet at the
// water level; where the ground rises above it nothing is drawn, so the bank is the terrain's.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 inflow = vec3(0.0, -100.0, 0.0);   // where the stream falls in (world)
uniform float inflow_strength = 1.0;
uniform vec3 tint : source_color = vec3(0.05, 0.065, 0.03);
// the basin: center (x, z), half-axes, direction of the first axis. Nothing is drawn outside it,
// whatever the ground does there (below a pool the gully falls away under the sheet).
uniform vec4 basin = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 basin_dir = vec2(1.0, 0.0);
// a tide pool: clear sea water over pale rock, a bright line where it meets the rock (0: the
// forest's dark fresh water)
uniform float clear = 0.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz;
	float depth = w_pos.y - ground_height(p);
	vec2 bd = p - basin.xy;
	float rho = length(vec2(dot(bd, basin_dir), dot(bd, vec2(-basin_dir.y, basin_dir.x))) / basin.zw);
	if (depth < 0.0 || rho > 1.0) {
		discard;
	}
	float t = world_time;
	vec2 n1 = texture(normal_tex, p * 0.9 + vec2(t * 0.02, t * 0.013)).xy * 2.0 - 1.0;
	vec2 n2 = texture(normal_tex, p * 2.3 - vec2(t * 0.017, -t * 0.021)).xy * 2.0 - 1.0;
	// rings spreading from where the water falls in
	vec2 dv = p - inflow.xz;
	float dl = length(dv);
	float ring_a = exp(-dl * 1.3) * inflow_strength;
	vec2 rn = dv / max(dl, 0.01) * cos(dl * 16.0 - t * 7.0) * ring_a * 0.22;
	// rain on the pool
	vec3 drops = rain_rings(p, t);
	rn += drops.xy * 0.6;
	vec3 n = normalize(vec3(n1.x * 0.07 + n2.x * 0.05 + rn.x, 1.0, n1.y * 0.07 + n2.y * 0.05 + rn.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	// bubbles under the fall
	float froth = smoothstep(0.55, 0.0, dl) * inflow_strength * smoothstep(0.3, 0.7, texture(normal_tex, p * 5.0 + vec2(t * 0.3, -t * 0.2)).x);
	ALBEDO = mix(tint, vec3(0.8, 0.85, 0.85), max(froth * 0.7, clamp(drops.z, 0.0, 1.0) * 0.5));
	ALPHA = clamp(mix(0.1, 0.82, smoothstep(0.0, 0.45, depth)) + fres * 0.6 + froth * 0.5, 0.0, 0.96) * smoothstep(0.0, 0.02, depth) * smoothstep(1.0, 0.93, rho);
	if (clear > 0.0) {
		// the meniscus: a thin bright rim; the water itself thin and clear, greener with depth
		float rim = (1.0 - smoothstep(0.004, 0.03, depth)) * smoothstep(0.0, 0.004, depth);
		ALBEDO = mix(mix(vec3(0.16, 0.34, 0.3), tint, smoothstep(0.0, 0.3, depth)), vec3(0.75, 0.82, 0.8), rim * 0.8);
		ALPHA = mix(ALPHA, clamp(mix(0.16, 0.5, smoothstep(0.0, 0.3, depth)) + fres * 0.75 + rim * 0.5, 0.0, 0.95) * smoothstep(0.0, 0.004, depth) * smoothstep(1.0, 0.93, rho), clear);
	}
	ROUGHNESS = mix(0.04, 0.5, froth);
	SPECULAR = 0.6;
}
