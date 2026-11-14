shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#define LEAF_FAR
#include "res://shaders/leaf.gdshaderinc"
