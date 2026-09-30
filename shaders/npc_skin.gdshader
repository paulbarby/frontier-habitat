// Astronaut GPU skinning for instanced characters (RENDER, V3_DESIGN §3.4).
// Every colonist of one model variant is ONE MultiMesh instance of one mesh: a few draw
// calls for all of them. The bone matrices of every clip frame are baked once into the
// `anim` texture (presentation/fx_npc.gd); each instance says which frames to use:
//   INSTANCE_CUSTOM.x = row of pose A (+ fraction to the next row: frame interpolation)
//   INSTANCE_CUSTOM.y = row of pose B + 0.998 x weight of B (cross-fade or run blend), -1 = none
//   INSTANCE_CUSTOM.z = look code: role * 64 + head * 8 + skin tone
//   INSTANCE_CUSTOM.w = row of the carry layer + 0.998 x its weight, -1 = none
// Row layout: slots 0..upper_start-1 hold full skin matrices (lower body and chest), slots
// upper_start.. hold matrices RELATIVE TO THE CHEST, and slot `chest_slot` holds the chest.
// So the carry layer re-parents the carry clip's upper body onto the walking chest.
// Vertex data: the imported mesh as it is: BONE_INDICES (skin bind indices, mapped to slots
// by `bind_slot`), BONE_WEIGHTS, COLOR = baked AO (instance colours are white).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/npc_skin.gdshaderinc"
