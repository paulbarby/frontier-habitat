"""Frontier Habitat 5.0 (docs/V5_DESIGN.md section 17.1) - ART-HAB: the HR office exterior, sizes S / M / L.

A friendly civic drum: a light wall with big windows and a coral band, a glazed hexagonal 'wellness pavilion' on
the deck with a ficus inside, a lit two-sided roof sign "WE ARE LISTENING*" over the deck toward the game camera, a
warm glow ring under the parapet; the badge is a speech bubble with a heart (rooms_identity 'hr').
Interior: interior_v5hr.py.
"""
from math import sin, cos, radians

import rooms_kit as K
from rooms_kit import T, RZ, FLOOR_Z
import rooms_v5civ as CIV
import interior_props as PR

F = FLOOR_Z


def build_hr_office(rm):
    s = rm.size
    CIV._base(rm, band="Fabric", wall="Hull")
    rm.badge_family = "hr"
    D = 2.9
    CIV._civic_drum(rm, D, band="Fabric", wall="Hull", coping="Accent")
    ro = rm.roof
    Rw = rm.Rw
    # the wellness pavilion on the deck: a glazed hex pod with a ficus showing through
    cx, cy = 0.36 * Rw * cos(radians(140.0)), 0.36 * Rw * sin(radians(140.0))
    pr = 0.9 + 0.25 * s
    K.hex_pod(ro, cx, cy, pr, D + 0.02, 1.35, rot=0.0, wall="Hull", band="Fabric", win="Window", top="Frame",
              windows=(0, 1, 2, 3, 4, 5))
    ro.vcyl(cx, cy, D + 1.37, D + 1.55, 0.30, 0.38, seg=8, mat="Wood")
    for k in range(5):
        a = radians(72.0 * k)
        ro.sphere((cx + 0.22 * cos(a), cy + 0.22 * sin(a), D + 1.85 + 0.10 * (k % 2)), 0.26, "Plant", seg=7, rings=4)
    ro.sphere((cx, cy, D + 2.10), 0.30, "PlantDark", seg=7, rings=4)
    # the roof sign over the deck, facing the game camera (-Y), lit, two-sided
    sx, sy = 0.15 * Rw, -0.30 * Rw
    w = 2.6 + 0.4 * s
    for dx in (-w / 2 + 0.2, w / 2 - 0.2):
        ro.vcyl(sx + dx, sy, D + 0.02, D + 1.1, 0.05, seg=6, mat="Frame")
    with rm.porch.at(T(sx, sy, 0.0), RZ(-90.0)):
        rm.porch.box((0.0, 0.0, D + 1.32), (0.10, w, 0.50), "Frame", mats={"+x": "Fabric", "-x": "Fabric"})
        for rot in (0.0, 180.0):
            with rm.porch.at(RZ(rot)):
                h = PR.fit_h(["WE ARE LISTENING*"], w - 0.3, 0.24)
                PR.text(rm.porch, "WE ARE LISTENING*", 0.0, D + 1.36, h, "Light", x=0.052)
                PR.text(rm.porch, "*TO MUSIC", 0.0, D + 1.13, 0.06, "Hull", x=0.052)
    rm.top_z = max(rm.top_z, D + 2.45)
    CIV._glow_ring(rm, D - 0.30, mat="Window")
    rm.no_extras = True


BUILDERS = {"hr_office": build_hr_office}
