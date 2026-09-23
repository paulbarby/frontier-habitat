# Build report - room buildings (ART-A, Frontier Habitat 2.0)

Written by `tools/blender/rooms_build.py` (Blender 5.2.1 LTS). Rebuild command:

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/rooms_build.py -- [--only id1,id2] [--sizes s,m,l,xl] [--no-thumbs] [--review]
```

Blender coordinates (Z up). `max r` = largest horizontal distance of any vertex from the origin; `margin` = footprint radius - max r (must be >= 0.10). Budgets: S 3000, M 4500, L 6500, XL 9000 triangles (all objects, L2..L5 included). `verify` = re-import test in an empty Blender scene (objects, materials, COLOR_0, radius, trays).

| file | tris / budget | per object | size X x Y x Z (m) | max r | footprint | margin | AO min..max | anchors | bytes | flags |
|---|---:|---|---|---:|---:|---:|---|---|---:|---|
| `habitat_s` | 2858 / 3000 | Base 724, Roof 736, Interior 570, L2 156, L3 166, L4 246, L5 240, Lights 20 | 7.7 x 7.7 x 5.0 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 171140 | ok |
| `habitat_m` | 4324 / 4500 | Base 1036, Roof 1280, Interior 1034, L2 172, L3 174, L4 284, L5 304, Lights 40 | 10.7 x 10.7 x 6.1 | 5.40 | 5.50 | 0.10 | 0.18..1.00 | Door Beacon | 244984 | ok |
| `habitat_l` | 6468 / 6500 | Base 1452, Roof 2128, Interior 1792, L2 204, L3 190, L4 310, L5 352, Lights 40 | 13.7 x 13.7 x 8.2 | 6.90 | 7.00 | 0.10 | 0.18..1.00 | Door Beacon | 352692 | ok |
| `habitat_xl` | 8184 / 9000 | Base 1796, Roof 2668, Interior 2388, L2 376, L3 206, L4 326, L5 384, Lights 40 | 16.8 x 16.8 x 9.3 | 8.40 | 8.50 | 0.10 | 0.18..1.00 | Door Beacon | 440352 | ok |
| `greenhouse_s` | 2668 / 3000 | Base 568, Roof 838, Interior 342, L2 156, L3 226, L4 266, L5 232, Lights 40 | 8.3 x 8.3 x 5.4 | 4.20 | 4.30 | 0.10 | 0.18..1.00 | Door Beacon | 174988 | ok |
| `greenhouse_m` | 3706 / 4500 | Base 884, Roof 1308, Interior 530, L2 188, L3 242, L4 282, L5 232, Lights 40 | 11.7 x 11.7 x 6.3 | 5.90 | 6.00 | 0.10 | 0.18..1.00 | Door Beacon | 236328 | ok |
| `greenhouse_l` | 5088 / 6500 | Base 1298, Roof 1898, Interior 834, L2 220, L3 258, L4 308, L5 232, Lights 40 | 15.4 x 15.4 x 7.2 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 320664 | ok |
| `greenhouse_xl` | 6015 / 9000 | Base 1640, Roof 2195, Interior 1058, L2 252, L3 274, L4 324, L5 232, Lights 40 | 19.0 x 19.0 x 8.1 | 9.50 | 9.60 | 0.10 | 0.18..1.00 | Door Beacon | 370168 | ok |
| `kitchen_s` | 2950 / 3000 | Base 632, Roof 1082, Interior 388, L2 156, L3 166, L4 246, L5 240, Lights 40 | 6.9 x 6.9 x 4.9 | 3.50 | 3.60 | 0.10 | 0.18..1.00 | Door Smoke Beacon | 179212 | ok |
| `kitchen_m` | 4102 / 4500 | Base 1304, Roof 1274, Interior 598, L2 156, L3 166, L4 276, L5 288, Lights 40 | 8.9 x 8.9 x 5.5 | 4.50 | 4.60 | 0.10 | 0.18..1.00 | Door Smoke Beacon | 231088 | ok |
| `kitchen_l` | 5570 / 6500 | Base 1592, Roof 2078, Interior 778, L2 288, L3 182, L4 292, L5 320, Lights 40 | 11.7 x 11.7 x 6.3 | 5.90 | 6.00 | 0.10 | 0.18..1.00 | Door Smoke1 Smoke2 Beacon | 299356 | ok |
| `kitchen_xl` | 6466 / 9000 | Base 1826, Roof 2138, Interior 1254, L2 350, L3 198, L4 308, L5 352, Lights 40 | 14.6 x 14.6 x 6.8 | 7.30 | 7.40 | 0.10 | 0.18..1.00 | Door Smoke1 Smoke2 Beacon | 349180 | ok |
| `storehouse_s` | 2886 / 3000 | Base 756, Roof 638, Interior 596, L2 156, L3 166, L4 246, L5 288, Lights 40 | 7.7 x 7.7 x 5.1 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Hatch Beacon | 185836 | ok |
| `storehouse_m` | 3902 / 4500 | Base 996, Roof 750, Interior 1166, L2 172, L3 174, L4 284, L5 320, Lights 40 | 10.7 x 10.7 x 5.3 | 5.40 | 5.50 | 0.10 | 0.18..1.00 | Door Hatch Beacon | 246412 | ok |
| `storehouse_l` | 6010 / 6500 | Base 1428, Roof 1656, Interior 1720, L2 324, L3 190, L4 300, L5 352, Lights 40 | 13.7 x 13.7 x 6.2 | 6.90 | 7.00 | 0.10 | 0.18..1.00 | Door Hatch Beacon | 356476 | ok |
| `storehouse_xl` | 7620 / 9000 | Base 1748, Roof 2416, Interior 2134, L2 376, L3 206, L4 316, L5 384, Lights 40 | 16.8 x 16.8 x 7.0 | 8.40 | 8.50 | 0.10 | 0.18..1.00 | Door Hatch Beacon | 437976 | ok |
| `oxygen_plant_s` | 2672 / 3000 | Base 580, Roof 926, Interior 348, L2 156, L3 166, L4 236, L5 240, Lights 20 | 5.4 x 5.4 x 5.2 | 2.70 | 2.80 | 0.10 | 0.18..1.00 | Door Vent1 Beacon | 148104 | ok |
| `oxygen_plant_m` | 3482 / 4500 | Base 728, Roof 1272, Interior 576, L2 156, L3 166, L4 256, L5 288, Lights 40 | 6.9 x 6.9 x 5.8 | 3.50 | 3.60 | 0.10 | 0.18..1.00 | Door Vent1 Vent2 Beacon | 181964 | ok |
| `oxygen_plant_l` | 4174 / 6500 | Base 840, Roof 1554, Interior 784, L2 236, L3 166, L4 266, L5 288, Lights 40 | 9.3 x 9.3 x 6.4 | 4.70 | 4.80 | 0.10 | 0.18..1.00 | Door Vent1 Vent2 Vent3 Beacon | 214412 | ok |
| `oxygen_plant_xl` | 5408 / 9000 | Base 1064, Roof 2240, Interior 992, L2 288, L3 182, L4 282, L5 320, Lights 40 | 11.7 x 11.7 x 7.1 | 5.90 | 6.00 | 0.10 | 0.18..1.00 | Door Vent1 Vent2 Vent3 Vent4 Beacon | 258660 | ok |
| `research_lab_s` | 2972 / 3000 | Base 632, Roof 1060, Interior 384, L2 156, L3 166, L4 246, L5 288, Lights 40 | 7.7 x 7.7 x 4.8 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Telescope Beacon | 173460 | ok |
| `research_lab_m` | 4028 / 4500 | Base 1256, Roof 1318, Interior 528, L2 156, L3 166, L4 276, L5 288, Lights 40 | 9.7 x 9.7 x 5.0 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Telescope Beacon | 223400 | ok |
| `research_lab_l` | 5436 / 6500 | Base 1872, Roof 1706, Interior 720, L2 288, L3 182, L4 292, L5 336, Lights 40 | 12.5 x 12.5 x 6.6 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Telescope Beacon | 294264 | ok |
| `research_lab_xl` | 6644 / 9000 | Base 2354, Roof 2192, Interior 834, L2 350, L3 198, L4 308, L5 368, Lights 40 | 15.4 x 15.4 x 6.6 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Telescope Beacon | 349240 | ok |
| `mine_s` | 2986 / 3000 | Base 712, Roof 1002, Interior 424, L2 156, L3 166, L4 246, L5 240, Lights 40 | 7.7 x 7.7 x 6.4 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 183668 | ok |
| `mine_m` | 3608 / 4500 | Base 856, Roof 1342, Interior 484, L2 156, L3 166, L4 276, L5 288, Lights 40 | 9.7 x 9.7 x 7.3 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Beacon | 212556 | ok |
| `mine_l` | 4792 / 6500 | Base 1216, Roof 1904, Interior 550, L2 288, L3 182, L4 292, L5 320, Lights 40 | 12.5 x 12.5 x 8.4 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Beacon | 268876 | ok |
| `mine_xl` | 5352 / 9000 | Base 1538, Roof 1958, Interior 608, L2 350, L3 198, L4 308, L5 352, Lights 40 | 15.4 x 15.4 x 9.4 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 294776 | ok |
| `refinery_s` | 2562 / 3000 | Base 712, Roof 918, Interior 352, L2 156, L3 48, L4 48, L5 288, Lights 40 | 7.7 x 7.7 x 6.5 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Smoke Beacon | 149352 | ok |
| `refinery_m` | 2916 / 4500 | Base 856, Roof 1044, Interior 436, L2 156, L3 48, L4 48, L5 288, Lights 40 | 9.7 x 9.7 x 7.5 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Smoke Beacon | 168528 | ok |
| `refinery_l` | 4180 / 6500 | Base 1216, Roof 1564, Interior 520, L2 288, L3 64, L4 152, L5 336, Lights 40 | 12.5 x 12.5 x 8.5 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Smoke Smoke2 Beacon | 237468 | ok |
| `refinery_xl` | 5306 / 9000 | Base 1538, Roof 2124, Interior 520, L2 350, L3 198, L4 168, L5 368, Lights 40 | 15.4 x 15.4 x 9.5 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Smoke Smoke2 Smoke3 Beacon | 295644 | ok |
| `polymer_plant_s` | 2636 / 3000 | Base 712, Roof 952, Interior 196, L2 156, L3 166, L4 126, L5 288, Lights 40 | 7.7 x 7.7 x 5.2 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Vent Beacon | 155436 | ok |
| `polymer_plant_m` | 3324 / 4500 | Base 856, Roof 1332, Interior 298, L2 156, L3 166, L4 188, L5 288, Lights 40 | 9.7 x 9.7 x 5.5 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Vent Beacon | 178456 | ok |
| `polymer_plant_l` | 4612 / 6500 | Base 1216, Roof 1858, Interior 400, L2 288, L3 182, L4 292, L5 336, Lights 40 | 12.5 x 12.5 x 5.7 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Vent Beacon | 239956 | ok |
| `polymer_plant_xl` | 5640 / 9000 | Base 1538, Roof 2336, Interior 502, L2 350, L3 198, L4 308, L5 368, Lights 40 | 15.4 x 15.4 x 6.0 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Vent Beacon | 281396 | ok |
| `workshop_s` | 2786 / 3000 | Base 712, Roof 952, Interior 542, L2 156, L3 48, L4 48, L5 288, Lights 40 | 7.7 x 7.7 x 5.0 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 172004 | ok |
| `workshop_m` | 3010 / 4500 | Base 856, Roof 1052, Interior 522, L2 156, L3 48, L4 48, L5 288, Lights 40 | 9.7 x 9.7 x 5.4 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Beacon | 181608 | ok |
| `workshop_l` | 3936 / 6500 | Base 1216, Roof 1270, Interior 570, L2 288, L3 64, L4 152, L5 336, Lights 40 | 12.5 x 12.5 x 5.7 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Beacon | 231896 | ok |
| `workshop_xl` | 5078 / 9000 | Base 1538, Roof 1628, Interior 648, L2 350, L3 198, L4 308, L5 368, Lights 40 | 15.4 x 15.4 x 6.0 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 292716 | ok |
| `medical_s` | 2734 / 3000 | Base 920, Roof 724, Interior 242, L2 156, L3 166, L4 246, L5 240, Lights 40 | 6.9 x 6.9 x 4.8 | 3.50 | 3.60 | 0.10 | 0.18..1.00 | Door Beacon | 158064 | ok |
| `medical_m` | 3364 / 4500 | Base 1240, Roof 804, Interior 394, L2 156, L3 166, L4 276, L5 288, Lights 40 | 8.7 x 8.7 x 5.3 | 4.40 | 4.50 | 0.10 | 0.18..1.00 | Door Beacon | 186408 | ok |
| `medical_l` | 4474 / 6500 | Base 1538, Roof 1284, Interior 588, L2 262, L3 174, L4 284, L5 304, Lights 40 | 11.3 x 11.3 x 6.1 | 5.70 | 5.80 | 0.10 | 0.18..1.00 | Door Beacon | 239024 | ok |
| `medical_xl` | 5494 / 9000 | Base 1784, Roof 1768, Interior 752, L2 324, L3 190, L4 300, L5 336, Lights 40 | 14.1 x 14.1 x 6.7 | 7.10 | 7.20 | 0.10 | 0.18..1.00 | Door Beacon | 280040 | ok |
| `lounge_s` | 2522 / 3000 | Base 612, Roof 772, Interior 310, L2 156, L3 166, L4 246, L5 240, Lights 20 | 7.7 x 7.7 x 5.0 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 151360 | ok |
| `lounge_m` | 3196 / 4500 | Base 760, Roof 932, Interior 578, L2 156, L3 166, L4 276, L5 288, Lights 40 | 9.7 x 9.7 x 5.8 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Beacon | 187420 | ok |
| `lounge_l` | 4432 / 6500 | Base 1104, Roof 1412, Interior 794, L2 288, L3 182, L4 292, L5 320, Lights 40 | 12.5 x 12.5 x 6.5 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Beacon | 244580 | ok |
| `lounge_xl` | 5468 / 9000 | Base 1394, Roof 1804, Interior 1022, L2 350, L3 198, L4 308, L5 352, Lights 40 | 15.4 x 15.4 x 7.1 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 288812 | ok |
| `airlock` | 2454 / 4500 | Base 804, Roof 924, Interior 686, Lights 40 | 5.4 x 5.4 x 5.0 | 2.70 | 2.80 | 0.10 | 0.18..1.00 | Door Light | 142576 | ok |
| `junction` | 1594 / 4500 | Base 648, Roof 762, Interior 144, Lights 40 | 4.8 x 4.8 x 3.4 | 2.40 | 2.50 | 0.10 | 0.18..1.00 | - | 82916 | ok |
| `corridor` | 260 / 1200 | Base 36, Roof 224 | 1.0 x 2.4 x 2.5 | 1.30 | 1.20 | -0.10 | 0.18..1.00 | - | 19112 | ok |
| `glassworks_s` | 2626 / 3000 | Base 712, Roof 958, Interior 180, L2 156, L3 166, L4 126, L5 288, Lights 40 | 7.7 x 7.7 x 4.9 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Smoke Beacon | 157344 | ok |
| `glassworks_m` | 3146 / 4500 | Base 856, Roof 1132, Interior 232, L2 156, L3 166, L4 276, L5 288, Lights 40 | 9.7 x 9.7 x 5.1 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Smoke Beacon | 180604 | ok |
| `glassworks_l` | 4394 / 6500 | Base 1216, Roof 1756, Interior 284, L2 288, L3 182, L4 292, L5 336, Lights 40 | 12.5 x 12.5 x 5.2 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Smoke Smoke2 Beacon | 238488 | ok |
| `glassworks_xl` | 5230 / 9000 | Base 1538, Roof 2092, Interior 336, L2 350, L3 198, L4 308, L5 368, Lights 40 | 15.4 x 15.4 x 5.3 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Smoke Smoke2 Beacon | 280384 | ok |
| `electronics_fab_s` | 2902 / 3000 | Base 712, Roof 1192, Interior 418, L2 156, L3 48, L4 48, L5 288, Lights 40 | 7.7 x 7.7 x 4.5 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 174892 | ok |
| `electronics_fab_m` | 3422 / 4500 | Base 856, Roof 1288, Interior 698, L2 156, L3 48, L4 48, L5 288, Lights 40 | 9.7 x 9.7 x 4.7 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Beacon | 205880 | ok |
| `electronics_fab_l` | 5538 / 6500 | Base 1216, Roof 2176, Interior 1008, L2 288, L3 182, L4 292, L5 336, Lights 40 | 12.5 x 12.5 x 4.9 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Beacon | 328968 | ok |
| `electronics_fab_xl` | 6386 / 9000 | Base 1538, Roof 2460, Interior 1124, L2 350, L3 198, L4 308, L5 368, Lights 40 | 15.4 x 15.4 x 5.0 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 368628 | ok |
| `fabricator_s` | 2772 / 3000 | Base 712, Roof 1158, Interior 244, L2 156, L3 48, L4 126, L5 288, Lights 40 | 8.5 x 8.5 x 6.6 | 4.30 | 4.40 | 0.10 | 0.18..1.00 | Door Beacon | 174300 | ok |
| `fabricator_m` | 3454 / 4500 | Base 936, Roof 1462, Interior 294, L2 172, L3 174, L4 56, L5 320, Lights 40 | 10.7 x 10.7 x 7.3 | 5.40 | 5.50 | 0.10 | 0.18..1.00 | Door Beacon | 209548 | ok |
| `fabricator_l` | 4730 / 6500 | Base 1384, Roof 1846, Interior 294, L2 324, L3 190, L4 300, L5 352, Lights 40 | 13.7 x 13.7 x 7.9 | 6.90 | 7.00 | 0.10 | 0.18..1.00 | Door Beacon | 277056 | ok |
| `fabricator_xl` | 5690 / 9000 | Base 1688, Roof 2336, Interior 344, L2 376, L3 206, L4 316, L5 384, Lights 40 | 16.8 x 16.8 x 8.3 | 8.40 | 8.50 | 0.10 | 0.18..1.00 | Door Beacon | 322592 | ok |
| `fungus_farm_s` | 2868 / 3000 | Base 568, Roof 916, Interior 536, L2 156, L3 166, L4 246, L5 240, Lights 40 | 7.7 x 7.7 x 5.1 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 179400 | ok |
| `fungus_farm_m` | 4082 / 4500 | Base 696, Roof 1388, Interior 1072, L2 156, L3 166, L4 276, L5 288, Lights 40 | 9.7 x 9.7 x 5.8 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Beacon | 246512 | ok |
| `fungus_farm_l` | 5546 / 6500 | Base 1024, Roof 1872, Interior 1528, L2 288, L3 182, L4 292, L5 320, Lights 40 | 12.5 x 12.5 x 6.4 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Beacon | 323008 | ok |
| `fungus_farm_xl` | 6894 / 9000 | Base 1298, Roof 2404, Interior 1944, L2 350, L3 198, L4 308, L5 352, Lights 40 | 15.4 x 15.4 x 6.8 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 390896 | ok |
| `algae_bioreactor_s` | 2932 / 3000 | Base 632, Roof 1010, Interior 400, L2 156, L3 166, L4 280, L5 248, Lights 40 | 6.9 x 6.9 x 7.4 | 3.50 | 3.60 | 0.10 | 0.18..1.00 | Door Vent Beacon | 182288 | ok |
| `algae_bioreactor_m` | 4402 / 4500 | Base 728, Roof 1888, Interior 860, L2 156, L3 166, L4 276, L5 288, Lights 40 | 8.7 x 8.7 x 7.7 | 4.40 | 4.50 | 0.10 | 0.18..1.00 | Door Vent Beacon | 224392 | ok |
| `algae_bioreactor_l` | 5356 / 6500 | Base 930, Roof 2344, Interior 1002, L2 262, L3 174, L4 284, L5 320, Lights 40 | 11.3 x 11.3 x 8.2 | 5.70 | 5.80 | 0.10 | 0.18..1.00 | Door Vent Beacon | 268348 | ok |
| `algae_bioreactor_xl` | 6854 / 9000 | Base 1256, Roof 3248, Interior 1144, L2 324, L3 190, L4 300, L5 352, Lights 40 | 14.1 x 14.1 x 8.6 | 7.10 | 7.20 | 0.10 | 0.18..1.00 | Door Vent Beacon | 338980 | ok |
| `water_recycler_s` | 2838 / 3000 | Base 580, Roof 1018, Interior 404, L2 156, L3 166, L4 246, L5 248, Lights 20 | 6.1 x 6.1 x 4.2 | 3.10 | 3.20 | 0.10 | 0.18..1.00 | Door Vent Beacon | 172332 | ok |
| `water_recycler_m` | 3920 / 4500 | Base 728, Roof 1570, Interior 706, L2 156, L3 166, L4 266, L5 288, Lights 40 | 7.7 x 7.7 x 4.6 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Vent Beacon | 211708 | ok |
| `water_recycler_l` | 4622 / 6500 | Base 930, Roof 1814, Interior 888, L2 172, L3 174, L4 284, L5 320, Lights 40 | 10.1 x 10.1 x 5.0 | 5.10 | 5.20 | 0.10 | 0.18..1.00 | Door Vent Beacon | 247228 | ok |
| `water_recycler_xl` | 5436 / 9000 | Base 1104, Roof 2194, Interior 1100, L2 188, L3 182, L4 292, L5 336, Lights 40 | 12.5 x 12.5 x 5.4 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Vent Beacon | 281644 | ok |
| `atmo_processor_s` | 2988 / 3000 | Base 696, Roof 1070, Interior 366, L2 156, L3 166, L4 246, L5 248, Lights 40 | 7.7 x 7.7 x 6.4 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Vapour1 Vapour2 Beacon | 171704 | ok |
| `atmo_processor_m` | 4062 / 4500 | Base 856, Roof 1820, Interior 460, L2 156, L3 166, L4 276, L5 288, Lights 40 | 9.7 x 9.7 x 7.3 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Vapour1 Vapour2 Beacon | 218424 | ok |
| `atmo_processor_l` | 5526 / 6500 | Base 1216, Roof 2502, Interior 670, L2 288, L3 182, L4 292, L5 336, Lights 40 | 12.5 x 12.5 x 7.9 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Vapour1 Vapour2 Vapour3 Beacon | 284376 | ok |
| `atmo_processor_xl` | 6868 / 9000 | Base 1522, Roof 3202, Interior 880, L2 350, L3 198, L4 308, L5 368, Lights 40 | 15.4 x 15.4 x 8.5 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Vapour1 Vapour2 Vapour3 Vapour4 Beacon | 341620 | ok |
| `bio_lab_s` | 2914 / 3000 | Base 632, Roof 938, Interior 448, L2 156, L3 166, L4 246, L5 288, Lights 40 | 6.9 x 6.9 x 5.4 | 3.50 | 3.60 | 0.10 | 0.18..1.00 | Door Fume Beacon | 169052 | ok |
| `bio_lab_m` | 3636 / 4500 | Base 728, Roof 1354, Interior 628, L2 156, L3 166, L4 276, L5 288, Lights 40 | 8.7 x 8.7 x 5.8 | 4.40 | 4.50 | 0.10 | 0.18..1.00 | Door Fume Beacon | 205940 | ok |
| `bio_lab_l` | 4540 / 6500 | Base 930, Roof 1722, Interior 808, L2 262, L3 174, L4 284, L5 320, Lights 40 | 11.3 x 11.3 x 6.2 | 5.70 | 5.80 | 0.10 | 0.18..1.00 | Door Fume Beacon | 253712 | ok |
| `bio_lab_xl` | 5708 / 9000 | Base 1256, Roof 2202, Interior 1044, L2 324, L3 190, L4 300, L5 352, Lights 40 | 14.1 x 14.1 x 6.5 | 7.10 | 7.20 | 0.10 | 0.18..1.00 | Door Fume Beacon | 304420 | ok |
| `cantina_s` | 2898 / 3000 | Base 632, Roof 1054, Interior 328, L2 156, L3 166, L4 266, L5 256, Lights 40 | 7.7 x 7.7 x 5.6 | 3.90 | 4.00 | 0.10 | 0.18..1.00 | Door Beacon | 173972 | ok |
| `cantina_m` | 4042 / 4500 | Base 1336, Roof 1206, Interior 616, L2 156, L3 166, L4 266, L5 256, Lights 40 | 9.7 x 9.7 x 5.9 | 4.90 | 5.00 | 0.10 | 0.18..1.00 | Door Beacon | 227176 | ok |
| `cantina_l` | 5204 / 6500 | Base 1632, Roof 1578, Interior 904, L2 288, L3 182, L4 292, L5 288, Lights 40 | 12.5 x 12.5 x 6.3 | 6.30 | 6.40 | 0.10 | 0.18..1.00 | Door Beacon | 286548 | ok |
| `cantina_xl` | 6112 / 9000 | Base 1874, Roof 1976, Interior 1062, L2 350, L3 198, L4 308, L5 304, Lights 40 | 15.4 x 15.4 x 6.7 | 7.70 | 7.80 | 0.10 | 0.18..1.00 | Door Beacon | 330672 | ok |
| `cold_storage_s` | 2830 / 3000 | Base 682, Roof 876, Interior 376, L2 156, L3 166, L4 246, L5 288, Lights 40 | 6.9 x 6.9 x 4.2 | 3.50 | 3.60 | 0.10 | 0.18..1.00 | Door Beacon | 181040 | ok |
| `cold_storage_m` | 3466 / 4500 | Base 778, Roof 928, Interior 834, L2 156, L3 166, L4 276, L5 288, Lights 40 | 8.7 x 8.7 x 4.6 | 4.40 | 4.50 | 0.10 | 0.18..1.00 | Door Beacon | 221668 | ok |
| `cold_storage_l` | 4282 / 6500 | Base 980, Roof 1204, Interior 1018, L2 262, L3 174, L4 284, L5 320, Lights 40 | 11.3 x 11.3 x 5.9 | 5.70 | 5.80 | 0.10 | 0.18..1.00 | Door Beacon | 266812 | ok |
| `cold_storage_xl` | 5472 / 9000 | Base 1306, Roof 1616, Interior 1344, L2 324, L3 190, L4 300, L5 352, Lights 40 | 14.1 x 14.1 x 6.1 | 7.10 | 7.20 | 0.10 | 0.18..1.00 | Door Beacon | 326364 | ok |

M files are also written as `<id>.glb` (v1 file names). Thumbnails: `assets/thumbs/<id>_<size>.png` (+ `<id>.png` = M), 256 x 256, transparent, EEVEE, lens 70 mm, azimuth -42 deg, elevation 40 deg, roof on, L2..L5 hidden (same camera and light as ART-B).
