"""Frontier Habitat 5.0 distillery (SIM 2026-10-01, docs/requests/SIM-to-ART-HAB.md): the roof.
Content: room, category food (Accent green), family industry, sizes S-XL, radius 6 / 7.5 / 9.6 / 11.7 (the polymer
plant's), work 1/1/2/3, stands 1/2/2/3.  Silhouette (content): copper stills and tanks under a low roof, pipe racks.

Identity from the game camera: a low white still house with a green malt-kiln pagoda roof; copper pot stills with
swan necks and condensers under a low glass canopy on the open deck; a tall copper column still; two spirit
receivers on cradles; a pipe rack; a cask stack; a malt silo (M and up); the distillery badge (a bottle and a
glass) on the deck quarter toward the game camera.  Interior: interior_distillery.py."""
from math import sin, cos, radians, hypot

import rooms_kit as K
from rooms_kit import T, RX, RY, RZ, hall, tank_v, levels_podium, auto_sites, capsule
import rooms_identity as RI
from rooms_v4ind import _deck
from rooms_industry import rect_obstacles

COPPER = "Copper"


def pot_still(p, x, y, z0, r, H, arm_dx, mat=COPPER):
    """An onion pot still on a dark firebox plinth, a boil ball and a tapering swan neck (top at z0 + H), a lyne arm
    falling toward +X by arm_dx to a copper condenser.  Returns the top z."""
    p.vcyl(x, y, z0, z0 + 0.32, r + 0.14, seg=14, mat="HullDark")
    p.box((x + r + 0.12, y, z0 + 0.17), (0.04, 0.34, 0.16), "Ember", mats={"-x": None})     # firebox door glow
    zb = z0 + 0.32
    neck = max(0.10, 0.20 * r)
    prof = [(r * 0.80, zb), (r * 0.96, zb + 0.20 * r), (r, zb + 0.48 * r), (r * 0.94, zb + 0.78 * r),
            (r * 0.72, zb + 1.02 * r), (r * 0.44, zb + 1.18 * r), (r * 0.30, zb + 1.26 * r), (r * 0.40, zb + 1.40 * r),
            (r * 0.28, zb + 1.56 * r), (neck * 1.25, zb + 1.72 * r), (neck, z0 + H), (0.0, z0 + H + 0.03)]
    with p.at(T(x, y, 0.0)):
        p.lathe(prof, mat, seg=14)
        # a riveted Frame ring at the pot's shoulder and the manway door
        p.vcyl(0.0, 0.0, zb + 0.74 * r, zb + 0.80 * r, r * 0.955, seg=14, mat="Frame", cap0=False, cap1=False)
    p.box((x - r * 0.93, y, zb + 0.5 * r), (0.05, 0.36 * r, 0.30 * r), "Frame")
    # the lyne arm and the condenser (shell-and-tube, copper, Frame bands)
    cx = x + arm_dx
    zc = z0 + H - 0.55
    p.tube([(x, y, z0 + H - 0.04), (x + 0.28, y, z0 + H - 0.02), (cx, y, zc + 0.10)], max(0.06, neck * 0.6),
           seg=8, mat=mat, caps=False)
    p.vcyl(cx, y, z0, zc + 0.18, 0.22 + 0.04 * r, seg=10, mat=mat)
    for zz in (0.35, zc - z0 - 0.3):
        p.vcyl(cx, y, z0 + zz, z0 + zz + 0.07, 0.24 + 0.04 * r, seg=10, mat="Frame", cap0=False, cap1=False)
    return z0 + H + 0.05


def pagoda(p, lt, cx, cy, z0, w, h):
    """A malt-kiln pagoda: a square louvred kiln block, a flared pyramid roof in the family green (Accent), a
    raised ventilator cap and a lantern finial.  Returns the top z."""
    hw = w / 2
    zb = z0 + 0.30 * h
    p.box0(cx, cy, z0, w, w, zb - z0, "Hull")
    for (ox, oy, sx, sy) in ((hw + 0.01, 0.0, 0.02, w * 0.70), (-hw - 0.01, 0.0, 0.02, w * 0.70),
                             (0.0, hw + 0.01, w * 0.70, 0.02), (0.0, -hw - 0.01, w * 0.70, 0.02)):
        for j in range(3):
            p.box((cx + ox, cy + oy, z0 + 0.12 + 0.12 * j * (zb - z0) / 0.45), (sx, sy, 0.05), "Frame")

    def sq(half, z):
        return [(cx + half, cy - half, z), (cx + half, cy + half, z), (cx - half, cy + half, z),
                (cx - half, cy - half, z)]
    rings = [sq(hw * 1.30, zb), sq(hw * 1.02, zb + 0.10 * h), sq(hw * 0.52, zb + 0.45 * h), sq(hw * 0.36, zb + 0.52 * h)]
    p.loft(rings, "Accent", smooth=False, closed=True)
    p.f([p.v(q) for q in reversed(rings[0])], "Frame")            # eave soffit (faces down)
    # the ventilator: a short open collar (dark gap), a small green pyramid cap, a lantern finial
    zt = zb + 0.52 * h
    p.box0(cx, cy, zt, hw * 0.60, hw * 0.60, 0.20 * h, "Rubber")
    cap = [sq(hw * 0.52, zt + 0.20 * h), [(cx, cy, zt + 0.42 * h)]]
    p.loft(cap, "Accent", smooth=False, closed=True)
    p.f([p.v(q) for q in reversed(cap[0])], "Frame")
    p.vcyl(cx, cy, zt + 0.42 * h, zt + 0.42 * h + 0.45, 0.03, seg=5, mat="Frame")
    p.sphere((cx, cy, zt + 0.42 * h + 0.50), 0.08, "Light", seg=6, rings=3)
    # ridge hips (Frame) on the main roof
    for k in range(4):
        a, b = rings[0][k], rings[2][k]
        p.beam(a, b, 0.06, 0.05, "Frame")
    return zt + 0.42 * h + 0.6


def glass_canopy(p, x0, x1, y0, y1, zf, z_lo, z_hi, lamps):
    """A low mono-pitch glass roof on posts (high side +X), Frame rafters and edge beams; lamps under the eave."""
    for xx in (x0, x1):
        zz = z_lo if xx == x0 else z_hi
        for yy in (y0, y1):
            p.vcyl(xx, yy, zf, zz, 0.07, seg=6, mat="Frame")
    p.quad((x0, y0, z_lo), (x1, y0, z_hi), (x1, y1, z_hi), (x0, y1, z_lo), "Glass")
    p.quad((x0, y1, z_lo - 0.01), (x1, y1, z_hi - 0.01), (x1, y0, z_hi - 0.01), (x0, y0, z_lo - 0.01), "Glass")
    n = max(2, int((y1 - y0) / 0.9))
    for k in range(n + 1):
        yy = y0 + (y1 - y0) * k / n
        p.beam((x0 - 0.1, yy, z_lo + 0.03), (x1 + 0.1, yy, z_hi + 0.03), 0.06, 0.06, "Frame")
    for xx, zz in ((x0, z_lo), (x1, z_hi)):
        p.beam((xx, y0 - 0.1, zz + 0.04), (xx, y1 + 0.1, zz + 0.04), 0.10, 0.12, "Frame")
    for yy in (y0 + 0.3, y1 - 0.3):
        p.sphere((x1 - 0.05, yy, z_hi - 0.12), 0.08, "Light", seg=6, rings=3)


def cask(p, x, y, z, yaw=0.0, L=0.80, r=0.30):
    """A cask lying on its side (axis along local X after the yaw): bulged Wood staves, two Frame hoops each end."""
    with p.at(T(x, y, z + r), RZ(yaw), RY(90.0)):
        p.lathe([(0.0, -L / 2), (r * 0.84, -L / 2), (r * 0.96, -L / 4), (r, 0.0), (r * 0.96, L / 4),
                 (r * 0.84, L / 2), (0.0, L / 2)], "Wood", seg=10)
        for zz in (-L * 0.36, L * 0.30):
            p.vcyl(0.0, 0.0, zz, zz + 0.05, r * 0.99, seg=10, mat="Frame", cap0=False, cap1=False)


def cask_stack(p, x, y, z0, yaw, n_base=3):
    """A two-tier cask stack on a rack (n_base below, n_base - 1 on top in the grooves)."""
    r = 0.30
    c, s = cos(radians(yaw)), sin(radians(yaw))
    with p.at(T(x, y, 0.0), RZ(yaw)):
        span = 2 * r * n_base + 0.1
        for sx in (-1, 1):
            p.box0(0.0, sx * 0.30, z0, span, 0.10, 0.10, "Frame")
    for i in range(n_base):
        ly = -(n_base - 1) * r + 2 * r * i
        cask(p, x - s * ly, y + c * ly, z0 + 0.08, yaw)
    for i in range(n_base - 1):
        ly = -(n_base - 2) * r + 2 * r * i
        cask(p, x - s * ly, y + c * ly, z0 + 0.08 + 1.70 * r, yaw)


def build_distillery(rm):
    ro, D = _deck(rm, wall="HullDark", deck="Frame")
    Rw, s = rm.Rw, rm.size
    lt = rm.lights
    obst = []
    # the still house: low white walls, a dark gable roof, lit windows, the green band
    hx, hy, ha, hb = -0.24 * Rw, 0.36 * Rw, 0.33 * Rw, 0.19 * Rw
    eave = D + 1.55 + 0.1 * s
    top = hall(ro, hx, hy, ha, hb, D + 0.02, eave, roof="gable", wall="Hull", roof_mat="Frame", band="Accent",
               windows=True, win_mat="Window")
    obst += rect_obstacles(hx, hy, ha, hb)
    ridge = eave + hb * 0.45
    # the pagoda on the ridge, toward +X (seen by the game camera from -Y)
    pw = 1.05 + 0.18 * s
    top = max(top, pagoda(ro, lt, hx + 0.35 * ha, hy, ridge - 0.25, pw, 2.2 + 0.35 * s))
    # the still yard on +X: pot stills in a row along Y with their condensers, under a low glass canopy
    nst = 2 if s < 2 else 3
    r = 0.72 + 0.10 * s
    H = 2.75 + 0.35 * s
    sx = 0.40 * Rw
    ys = [(-0.04 + (0.46 if nst == 2 else 0.26) * k) * Rw for k in range(nst)]
    arm = r + 0.55
    for k, y in enumerate(ys):
        rr = r * (1.0 if k % 2 == 0 else 0.84)              # wash still and the smaller spirit still
        top = max(top, pot_still(ro, sx, y, D + 0.02, rr, H * (1.0 if k % 2 == 0 else 0.92), arm))
    x0, x1 = sx - r - 0.45, sx + arm + 0.50
    y0, y1 = ys[0] - r - 0.40, ys[-1] + r + 0.40
    z_lo = D + H + 0.35
    glass_canopy(ro, x0, x1, y0, y1, D + 0.02, z_lo, z_lo + 0.45, lt)
    top = max(top, z_lo + 0.6)
    obst.append(((x0 + x1) / 2, (y0 + y1) / 2, hypot(x1 - x0, y1 - y0) / 2 + 0.1))
    # the column still (copper, sight-glass bands) and its rectifier, on a plinth at -X
    cxs, cys = -0.52 * Rw, -0.06 * Rw
    ch = 4.2 + 0.7 * s
    cr = 0.30 + 0.04 * s
    ro.box0(cxs + 0.25, cys, D, 1.5, 0.95, 0.20, "HullDark")
    ro.vcyl(cxs, cys, D + 0.2, D + ch, cr, seg=12, mat=COPPER)
    with ro.at(T(cxs, cys, 0.0)):
        ro.lathe([(cr, D + ch), (cr * 0.55, D + ch + 0.35), (0.08, D + ch + 0.45), (0.0, D + ch + 0.46)], COPPER,
                 seg=12)
    nb = int(ch / 0.9)
    for j in range(1, nb):
        zz = D + 0.2 + j * (ch - 0.2) / nb
        ro.vcyl(cxs, cys, zz, zz + 0.08, cr + 0.02, seg=12, mat="Frame", cap0=False, cap1=False)
        if j % 2:
            ro.box((cxs, cys - cr - 0.005, zz + 0.3), (0.16, 0.02, 0.22), "Window", mats={"+y": None})
    rx_ = cxs + 0.62
    ro.vcyl(rx_, cys, D + 0.2, D + ch * 0.78, cr * 0.62, seg=10, mat=COPPER)
    ro.cap_disc(cr * 0.62, D + ch * 0.78, "Frame", seg=10)
    ro.tube([(cxs, cys, D + ch + 0.30), (cxs, cys, D + ch + 0.55), (rx_, cys, D + ch + 0.55),
             (rx_, cys, D + ch * 0.78)], 0.07, seg=6, mat=COPPER, caps=False)
    ro.sphere((cxs, cys, D + ch + 0.55), 0.09, "Light", seg=6, rings=3)
    top = max(top, D + ch + 0.7)
    obst.append((cxs + 0.3, cys, 1.0))
    # two spirit receivers on cradles between the column and the still yard
    rcx, rcy = -0.14 * Rw, 0.02 * Rw
    rl = 1.3 + 0.25 * s
    for dy in (-0.42, 0.42):
        for sxx in (-rl * 0.32, rl * 0.32):
            ro.box0(rcx + sxx, rcy + dy, D, 0.12, 0.62, 0.30, "Frame")
        capsule(ro, (rcx - rl / 2 + 0.3, rcy + dy, D + 0.62), (rcx + rl / 2 - 0.3, rcy + dy, D + 0.62), 0.30,
                mat=COPPER if dy < 0 else "Metal", seg=10, rings=2)
        ro.vcyl(rcx, rcy + dy, D + 0.9, D + 1.05, 0.08, seg=6, mat="Frame")
    obst.append((rcx, rcy, rl / 2 + 0.5))
    # the pipe rack: from the column along -Y of the receivers to the still yard, three pipes on T posts
    ry = -0.15 * Rw
    xa, xb = cxs + 0.3, x0 + 0.2
    zr = D + 2.05
    npost = max(2, int((xb - xa) / 1.6))
    for k in range(npost + 1):
        xx = xa + (xb - xa) * k / npost
        ro.box0(xx, ry, D, 0.14, 0.14, zr - D - 0.02, "Frame")
        ro.box0(xx, ry, zr - 0.08, 0.14, 0.70, 0.10, "Frame")
    for j, (dy, m) in enumerate(((-0.22, COPPER), (0.0, "Metal"), (0.22, "Accent"))):
        ro.cyl((xa - 0.05, ry + dy, zr + 0.10), (xb + 0.05, ry + dy, zr + 0.10), 0.07, seg=6, mat=m, cap0=False,
               cap1=False)
    ro.tube([(xb, ry, zr + 0.10), (xb + 0.35, ry, zr + 0.10), (xb + 0.35, ys[0] - r, zr + 0.10),
             (xb + 0.35, ys[0] - r, D + 0.05)], 0.07, seg=6, mat=COPPER, caps=False)
    ro.tube([(xa, ry - 0.22, zr + 0.10), (cxs, ry - 0.22, zr + 0.10), (cxs, cys - cr - 0.05, D + 1.2)], 0.07, seg=6,
            mat=COPPER, caps=False)
    # the cask stack behind the still house (+Y)
    kx, ky = 0.14 * Rw, 0.68 * Rw
    cask_stack(ro, kx, ky, D, 90.0 - 35.0, n_base=3 + (1 if s >= 2 else 0))
    obst.append((kx, ky, 1.2))
    # a cask yard on the open deck toward the game camera (+X, -Y): two racks, rows running out from the centre
    yx, yy = 0.52 * Rw, -0.36 * Rw
    ya = -124.7
    for off in ((-0.72, 0.72) if s >= 1 else (0.0,)):
        cask_stack(ro, yx + off * cos(radians(ya)), yy + off * sin(radians(ya)), D, ya, n_base=3 + (1 if s >= 2 else 0))
    obst.append((yx, yy, 1.5))
    # a malt silo on legs with a conical hopper (M and up)
    if s >= 1:
        mx, my = 0.64 * Rw, -0.12 * Rw
        mr = 0.45 + 0.05 * s
        for k in range(4):
            a = radians(45.0 + 90.0 * k)
            ro.vcyl(mx + mr * 0.8 * cos(a), my + mr * 0.8 * sin(a), D, D + 1.15, 0.05, seg=5, mat="Frame")
        with ro.at(T(mx, my, 0.0)):
            ro.lathe([(0.10, D + 0.55), (mr, D + 1.15), (mr, D + 3.1 + 0.3 * s), (mr * 0.5, D + 3.45 + 0.3 * s),
                      (0.0, D + 3.5 + 0.3 * s)], "Hull", seg=12)
        ro.vcyl(mx, my, D + 2.35 + 0.15 * s, D + 2.55 + 0.15 * s, mr + 0.015, seg=12, mat="Accent", cap0=False,
                cap1=False)
        top = max(top, D + 3.6 + 0.3 * s)
        obst.append((mx, my, mr + 0.4))
    rm.top_z = max(rm.top_z, top)
    # the badge place: the deck quarter on -Y toward the game camera (as the 4.0 industry rooms)
    obst.append((0.0, -0.52 * Rw, 0.34 * Rw + 0.3))
    levels_podium(rm, auto_sites(rm, obst, D))
    rm.badge_done = True
    RI.badge(rm.roof, "distillery", 0.0, -0.52 * Rw, 0.30 * Rw, lambda x, y: D + 0.02, lift=0.015)


BUILDERS = {"distillery": build_distillery}
