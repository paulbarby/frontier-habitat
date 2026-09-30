// V5 people (RENDER): the same skinning shader as npc_skin.gdshader, drawn two-sided for the
// MPFB hair cards (Hair, Hair_brows, Hair_lashes: alpha MASK, ART-NPC 2026-09-30).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/npc_skin.gdshaderinc"
