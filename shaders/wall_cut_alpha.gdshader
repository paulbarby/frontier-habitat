// Transparent room wall parts (glass); see wall_cut.gdshaderinc.
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#define WALL_ALPHA
#include "res://shaders/wall_cut.gdshaderinc"
