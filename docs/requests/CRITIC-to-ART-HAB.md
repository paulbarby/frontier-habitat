# CRITIC → ART-HAB

## 2026-10-02 — critic round 41 (`docs/critic/round_41_v5_run3.md` / `.json`)

interiors_close 0.64 FAIL; hr_office 0.68 PASS (provisional, Blender only). Most important first.

1. **Residence tube ceiling shards.** The RoofCeil liner fails under the half-tube vault: big grey triangles hang
   into the room (`residence_tube_l_eye0/1`, `residence_tube_executive_l_eye1/2`). Make the liner follow the
   vault, or skip it there. Reject any liner triangle longer than 1.5 m.
2. **Eye-view evidence for every room.** The camera is inside geometry in `airlock_m_eye0..2`,
   `junction_eye0..2`, `water_recycler_m_eye0..2`, `storehouse_m_eye2` and `cold_storage_m_eye0`. The stand-in
   is inside a rack in `cold_storage_m_eye2`, and behind a 2 m cabinet in `medical_m_eye0/1`. Place the eye
   camera automatically on free aisle points, at least 0.4 m from any face. Re-render, and look at every view
   before you report it.
3. **Texture, decal and light pass.** Today every surface is a flat colour and every room has the same white
   light.
   - One shared atlas: painted panel with scuffs, brushed metal, rubber floor, fabric.
   - Decals: floor paint, grime at the wall foot, labels.
   - Light colour per role: warm in the cantina, lounge and housing; cool in labs and medical; amber in
     industry.
   - Stay within the +25 MB allocation.
4. **Apartment block.** From floor 1 the upper floors' furniture shows through the slabs
   (`apartment_block_m_eye0..2`). Add a down-facing slab underside under every upper floor (in the floor-cut
   group).
5. **Residences and apartments.**
   - Raise the partitions to 2.1 m (needs RENDER's answer).
   - Give each unit a 2.4 m ceiling with a pendant.
   - Put 2 satire pieces in each unit (a chatbot fridge, a toaster with a subscription, a VR headset).
6. **Industry family variety.** Today the 17 types are one room. Add 3 ceiling variants (crane bay, duct grid,
   open truss), move the console and bench per type, and add a type-coloured wall band. Fill the floor ring
   (pipe runs, pallets, tool carts) so no tile field stays bare.
7. **The 5 weakest rooms.**
   - water_recycler: add a hero filter column, a joke board and a filled floor.
   - cold_storage / storehouse: aisles ≥ 1.6 m, aisle-end signs, floor numbers, 2–3 jokes.
   - junction: benches, a wayfinding totem, a lost-and-found shelf.
   - airlock: suit rack and checklist in view.
8. **HR office.**
   - Replace the 8 scattered benches (L) with a waiting area: 2 rows facing the reception.
   - Make the interview booths 2.1 m rooms.
   - Put 2 jokes at the reception, for example a "RATE YOUR COMPLAINT 1-5 STARS" tablet and a "MANDATORY FUN"
     calendar.
   - Give the roof badge a heart that does not read as "3".
9. **Security office.** Make it black and red (dark panels, red accent), as the room identity asks.
