shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sea_light.gdshaderinc"
#include "res://shaders/world.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"
// Barnacles on the granite between the tide marks (scripts/barnacles.gd: one small cone of
// plates each, in a MultiMesh; the vertex color is the shell's light and dark, the
// instance's color its tint). Wet, and so darker and shining, while the sea has just been
// over them and in rain; under water they take the net of light like everything else.

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// (the swell runs a hand's width up the rock: wet to a little above the sea's level)
	float wet = max(1.0 - smoothstep(sea_level + 0.06, sea_level + 0.22, w_pos.y), rain_wet * 0.8);
	vec3 c = COLOR.rgb;
	ALBEDO = c * mix(1.0, 0.62, wet);
	ROUGHNESS = mix(0.95, 0.45, wet);
	SPECULAR = mix(0.12, 0.4, wet);
	EMISSION = ALBEDO * sea_light(w_pos, w_nrm, world_time) * 2.0;
}
