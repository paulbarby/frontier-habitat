"""
Frontier Habitat 3.0 - ART-HAB interior kit (Blender 5.2, always --background).

Core of the 3.0 room interiors (furniture lives in interior_furniture.py, room layouts in interior_rooms.py):
  * the round wall as 32 objects Wall_00..Wall_31 (docs/V3_DESIGN.md section 7.2).  Segment k spans the angle
    [k * 11.25, (k + 1) * 11.25) degrees from +X toward +Y.  Everything that stands against the wall is built INTO
    the segment it stands in, so the game hides it together with the wall where a doorway replaces that segment.
    Frontier cues on every wall: a two-pipe run above the skirting, a batten at every panel joint, a rib stub every
    45 degrees, cove and skirting light strips (round-2 critique).
  * floors: radial panel floors (habitat, comfort) and grid floors (labs, kitchens, industry, logistics)
  * Plan: the free-standing layout of one room: obstacle footprints, the clear walking ring, hidable Tall_<nn>
    parts (headboards and other tall items near the ring: the game hides them next to a doorway), anchors with
    automatic numbering, aisle waypoints, ceiling light and lamp positions, the wall-item planner
  * checks: segment spans, anchor counts against content (SIM's furniture table), anchor clearance

Anchor convention (V3_DESIGN section 6): Anchor_<Kind>_<i>; origin = the stand point with its REAL height (floor
top 0.14 already included); local +X = the direction the person faces; beds: head toward local +Y (Blender)
= -Z of the node in Godot.
"""
import math
import random
from math import sin, cos, tan, pi, radians, degrees, hypot, sqrt, atan2, asin, acos, ceil, floor
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (P, T, RX, RY, RZ, S, polar, reg_angles, ang_diff, frame_m, columns, porthole, FLOOR_Z, WALL_TOP,
                       WALL_T)

F = FLOOR_Z
NSEG = 32
SEG_DEG = 360.0 / NSEG

# NPC furniture numbers (V3_DESIGN section 3.3; astronaut_anims.json "furniture").  Heights above the floor top.
SEAT_Z, SEAT_BACK = 0.46, 0.30
BED_Z, BED_BACK = 0.55, 0.55
CONSOLE_Z, CONSOLE_AHEAD = 1.00, 0.45
BENCH_Z, BENCH_AHEAD = 0.90, 0.40
PANEL_AHEAD, PANEL_Z = 0.45, 0.40
ITEM_DEPTH = 0.42      # the deepest wall-side item
MAX_MATS_OBJECT = 14
MAX_MATS_FILE = 26


def seg_of(a):
    return int((a % 360.0) // SEG_DEG) % NSEG


def seg_mid(k):
    return (k + 0.5) * SEG_DEG


def clear_for(R, size=None):
    """Width of the free walking ring inside the wall-side items (a doorway can open anywhere on it)."""
    # L and XL: 1.10 m (critic round 4).  M: 1.00 m (RENDER / coordinator 2026-09-25: a 0.9 m lane from every
    # doorway to the aisle ring).  S keeps 0.65 m and lists its blocked door angles (ART-HAB-door_blocked.json).
    if size is not None:
        return (0.65, 1.00, 1.10, 1.10)[size]
    return 1.10 if R >= 5.7 else (1.00 if R >= 4.9 else 0.65)


# --------------------------------------------------------------------------------------
# Small geometry helpers
# --------------------------------------------------------------------------------------
def bbox(p, x0, x1, y0, y1, z0, z1, mat, bevel=0.0, mats=None):
    p.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat, bevel=bevel, mats=mats)


def plate_x(p, x, y0, y1, z0, z1, mat, facing=1):
    """Flat quad on the plane x = const, facing +X (facing > 0) or -X."""
    if facing > 0:
        p.quad((x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1), mat)
    else:
        p.quad((x, y1, z0), (x, y0, z0), (x, y0, z1), (x, y1, z1), mat)


def plate_y(p, y, x0, x1, z0, z1, mat, facing=1):
    if facing > 0:
        p.quad((x1, y, z0), (x0, y, z0), (x0, y, z1), (x1, y, z1), mat)
    else:
        p.quad((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1), mat)


def plate_z(p, z, x0, x1, y0, y1, mat):
    p.quad((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), mat)


def ui_screen(p, w, h, glow="Screen", bars="LightStrip", seed=0):
    """Screen face on the plane x = 0 facing +X, centred at (0, 0, 0) of the current frame: frame, glowing face,
    a header bar and three data bars (a simple UI pattern made of geometry)."""
    p.box((-0.02, 0, 0), (0.04, w + 0.05, h + 0.05), "Frame", mats={"-x": None})
    plate_x(p, 0.002, -w / 2, w / 2, -h / 2, h / 2, glow)
    x = 0.004
    plate_x(p, x, -w * 0.44, w * 0.44, h * 0.30, h * 0.40, bars)
    lens = ((0.62, 0.38, 0.80), (0.30, 0.70, 0.52), (0.84, 0.25, 0.44))[seed % 3]
    for j, L in enumerate(lens):
        z = h * (0.12 - 0.20 * j)
        plate_x(p, x, -w * 0.44, -w * 0.44 + w * 0.88 * L, z - h * 0.045, z + h * 0.045, bars)


# --------------------------------------------------------------------------------------
# The round wall in 32 segments
# --------------------------------------------------------------------------------------
PIPE_Z = (0.37, 0.45)
PIPE_R = 0.025


def wall_profile_v3(Rw, Ri, band="Accent", band_proud=True, wall="Hull", kick="HullDark", windows=None):
    """(r, z) profile walking up the outside, over the top and down the inside (outward normals), and the
    material tag of every edge.  Tags: a material name, 'WIN' (window row), 'IN' (inner panel)."""
    prof, mats = [], []

    def add(r, z, m=None):
        if prof:
            mats.append(m)
        prof.append((r, z))
    add(Rw + 0.04, 0.03)                 # skirt: closes the gap to the foundation ring under a flat facet
    add(Rw, 0.09, kick)
    add(Rw, 0.32, kick)
    if windows:
        add(Rw, windows[0], wall)
        add(Rw, windows[1], "WIN")
    if band:
        if band_proud:
            add(Rw, 0.92, wall)
            add(Rw + 0.03, 0.935, band)
            add(Rw + 0.03, 1.125, band)
            add(Rw, 1.14, band)
        else:
            add(Rw, 0.94, wall)
            add(Rw, 1.12, band)
    add(Rw, WALL_TOP, wall)
    add(Ri, WALL_TOP, "Frame")
    # inner face: cove light under the top edge, the panel, a dark kick and a skirting light at the floor
    add(Ri, 1.335, "IN")
    add(Ri - 0.04, 1.32, "Frame")
    add(Ri - 0.04, 1.27, "LightStrip")
    add(Ri, 1.255, "Frame")
    add(Ri, 0.31, "IN")
    add(Ri - 0.03, 0.29, "FloorDark")
    add(Ri - 0.03, F + 0.065, "FloorDark")
    add(Ri - 0.03, F + 0.02, "LightStrip")
    add(Ri - 0.03, F - 0.004, "FloorDark")
    return prof, mats


def _chord_pts(r, a0, a1, z):
    return (Vector((r * cos(radians(a0)), r * sin(radians(a0)), z)),
            Vector((r * cos(radians(a1)), r * sin(radians(a1)), z)))


def build_walls_v3(rm, band="Accent", band_proud=None, wall="Hull", kick="HullDark", windows=None, win_mat="Window",
                   win_seams=16, portholes=(), porthole_r=0.17, porthole_z=0.62, door_half=0.0, cues=True,
                   pilasters=0, pil_mat="Frame", pipe_mat=("Metal", "Metal")):
    """The wall from z 0.09 to WALL_TOP as 32 objects, one flat facet per segment (smooth shaded outside).
    door_half (deg): no wall in [-door_half, door_half] (the airlock's outer door).  cues: battens, pipes, ribs."""
    Rw, Ri = rm.Rw, rm.Ri
    rm.v3 = True
    rm.walls = [P("Wall_%02d" % k) for k in range(NSEG)]
    rm.door_half_v3 = door_half
    if band_proud is None:
        band_proud = rm.size >= 1
    prof, mats = wall_profile_v3(Rw, Ri, band=band, band_proud=band_proud, wall=wall, kick=kick, windows=windows)
    wseams = [360.0 * (k + 0.5) / win_seams for k in range(win_seams)] if windows else []
    ws_w = degrees(0.08 / Rw)
    bat_deg = degrees(0.03 / Ri)
    rib_deg = degrees(0.08 / Ri)
    pil_at = [360.0 * (k + 0.5) / pilasters for k in range(pilasters)] if pilasters else []

    def in_door(a):
        return door_half > 0 and ang_diff(a, 0.0) < door_half
    for k in range(NSEG):
        a0, a1 = k * SEG_DEG, (k + 1) * SEG_DEG
        if door_half > 0:
            # clip the span to outside the door opening
            if ang_diff(a0, 0.0) < door_half and ang_diff(a1, 0.0) < door_half:
                continue
            if k < NSEG // 2 and a0 < door_half:
                a0 = door_half
            if k >= NSEG // 2 and a1 > 360.0 - door_half:
                a1 = 360.0 - door_half
        cols = {a0, a1}
        for sa in wseams:
            for e in (sa - ws_w / 2, sa + ws_w / 2):
                if a0 + 0.2 < e < a1 - 0.2:
                    cols.add(e)
        cols = sorted(cols)

        def mfn(kk, i, cols=cols):
            m = mats[kk]
            am = 0.5 * (cols[i] + cols[i + 1])
            if m == "IN":
                return "Hull"
            if m == "WIN":
                if any(abs(am - sa) < ws_w * 0.5 + 1e-6 for sa in wseams):
                    return "Frame"
                return win_mat
            return m
        w = rm.walls[k]
        w.lathe_a(prof, cols, mfn, smooth=True, closed=False)
        full = abs((a1 - a0) - SEG_DEG) < 1e-6
        if cues and full:
            rib = (k % 4 == 0)
            # inner batten (or a rib stub every 45 degrees) at the panel joint, outer batten
            if rib:
                with w.at(RZ(a0 + rib_deg / 2)):
                    # critic round 13: the rib stub ends at WALL_TOP (it stood 12 cm over the cutaway line)
                    bbox(w, Ri - 0.085, Ri + 0.01, -0.04, 0.04, 0.29, WALL_TOP, "Frame", mats={"+x": None})
                    bbox(w, Ri - 0.085, Rw + 0.045, -0.04, 0.04, WALL_TOP - 0.065, WALL_TOP, "Frame",
                         mats={"-z": None})
            else:
                with w.at(RZ(a0 + bat_deg / 2)):
                    # batten: front face and one side (6 triangles)
                    plate_x(w, Ri - 0.018, -0.015, 0.015, 0.29, 1.255, "Frame", facing=-1)
                    plate_y(w, 0.015, Ri - 0.018, Ri, 0.29, 1.255, "Frame", facing=1)
                    plate_y(w, -0.015, Ri - 0.018, Ri, 0.29, 1.255, "Frame", facing=-1)
            with w.at(RZ(a0 + bat_deg / 2)):
                plate_x(w, Rw + 0.008, -0.015, 0.015, 0.33, 0.915 if band else 1.36, "HullDark", facing=1)
            # two-pipe run above the skirting (chords follow the flat facet), a clamp on every fourth segment
            e0, e1 = a0 + bat_deg * 1.2, a1
            for j, z in enumerate(PIPE_Z):
                p0, p1 = _chord_pts(Ri - 0.045, e0, e1, z)
                w.cyl(p0, p1, PIPE_R, seg=5, mat=pipe_mat[j], cap0=False, cap1=False)
            if k % 4 == 2:
                with w.at(RZ(0.5 * (a0 + a1))):
                    bbox(w, Ri - 0.085, Ri + 0.005, -0.03, 0.03, PIPE_Z[0] - 0.05, PIPE_Z[1] + 0.05, "Frame",
                         mats={"+x": None})
        for pa in pil_at:
            if a0 + 1.0 < pa < a1 - 1.0 and not in_door(pa):
                with w.at(RZ(pa), T(Rw, 0, 0)):
                    w.box0(0.03, 0, 0.09, 0.12, 0.16, WALL_TOP - 0.11, pil_mat, mats={"-z": None, "-x": None})
    for a in portholes:
        if in_door(a):
            continue
        w = rm.walls[seg_of(a)]
        porthole(w, Vector(polar(Rw + 0.005, a, porthole_z)), Vector(polar(1.0, a, 0.0)), porthole_r, rim=0.06,
                 depth=0.05)


def slot_width(rm, depth, margin_deg=0.45):
    """Largest item width (m) that stays inside one wall segment at `depth` metres from the inner face."""
    return 2.0 * (rm.Ri - depth) * tan(radians(SEG_DEG / 2.0 - margin_deg))


class wall_slot:
    """Context: builds into segment k.  Local frame: origin on the inner wall face at the segment centre angle
    (plus `da` degrees), local +X points into the room (toward the centre), local +Y along the wall, z = 0."""

    def __init__(self, rm, k, da=0.0, back=0.02):
        self.p = rm.walls[k]
        self.a = seg_mid(k) + da
        self.r = rm.Ri + back

    def __enter__(self):
        self._cm = self.p.at(RZ(self.a), T(self.r, 0, 0), RZ(180.0))
        self._cm.__enter__()
        return self.p

    def __exit__(self, *exc):
        return self._cm.__exit__(*exc)


def check_walls(rm, tol_deg=0.5):
    """Every vertex of Wall_k lies inside [k*11.25 - tol, (k+1)*11.25 + tol] degrees."""
    flags = []
    for k, w in enumerate(rm.walls):
        a0, a1 = k * SEG_DEG, (k + 1) * SEG_DEG
        worst = 0.0
        for v in w.verts:
            if hypot(v.x, v.y) < 1e-6:
                continue
            a = degrees(atan2(v.y, v.x)) % 360.0
            if k == 0 and a > 180.0:
                a -= 360.0
            if k == NSEG - 1 and a < 180.0:
                a += 360.0
            out = max(a0 - a, a - a1, 0.0)
            worst = max(worst, out)
        if worst > tol_deg:
            flags.append("Wall_%02d leaves its span by %.2f deg" % (k, worst))
    return flags


def route_wall_zone(rm, part=None):
    """Move faces of `part` (default Base) that sit on the wall (portholes, lamps, pilasters of the v2 exterior
    code) into the wall segment of their centroid, so they hide with the segment."""
    part = part or rm.base
    keep_f, keep_m, keep_s = [], [], []
    moved = 0
    for f, m, sm in zip(part.faces, part.fmat, part.fsmooth):
        vs = [part.verts[i] for i in f]
        c = sum(vs, Vector((0, 0, 0))) / len(vs)
        r = hypot(c.x, c.y)
        a = degrees(atan2(c.y, c.x)) % 360.0
        dh = getattr(rm, "door_half_v3", 0.0)
        if rm.Ri - 0.15 < r < rm.Rw + 0.30 and 0.13 < c.z < WALL_TOP + 0.05 and rm.walls and                 not (dh > 0 and ang_diff(a, 0.0) < dh + 2.0):
            w = rm.walls[seg_of(a)]
            idx = [_raw_v(w, v) for v in vs]
            w.faces.append(tuple(idx))
            w.fmat.append(m)
            w.fsmooth.append(sm)
            moved += 1
        else:
            keep_f.append(f)
            keep_m.append(m)
            keep_s.append(sm)
    part.faces, part.fmat, part.fsmooth = keep_f, keep_m, keep_s
    return moved


def _raw_v(p, v):
    p.verts.append(Vector(v))
    p.vover.append(False)
    return len(p.verts) - 1


# --------------------------------------------------------------------------------------
# Floors
# --------------------------------------------------------------------------------------
FLOOR_STYLES = {
    # panel, seam, edge band (under the wall-side items)
    "panel": ("Floor", "FloorDark", "FloorDark"),
    "clean": ("Floor", "Frame", "FloorDark"),
    "grate": ("FloorDark", "Frame", "Frame"),
    "dark": ("FloorDark", "Frame", "Frame"),
    "frost": ("Frost", "Frame", "FloorDark"),
}


def build_floor_v3(rm, style="panel", pattern="radial", ring_step=1.25, radial=12, edge_band=0.62, seam=0.035,
                   inner_disc=1.3, radial_phase=0.0, grid=1.2, grid_yaw=0.0):
    """Floor top at FLOOR_Z, reaching under the wall (Ri + 0.12).
    pattern 'radial': panel rings with radial seams (habitat, comfort).  'grid': square panels (seams are strips
    clipped to the disc; labs, kitchens, industry, logistics)."""
    b = rm.base
    Ri = rm.Ri
    panel, seam_m, band = FLOOR_STYLES[style]
    nf = max(24, int(round(rm.seg * 1.0 / 4.0)) * 4)
    r_edge = Ri - edge_band
    if pattern == "radial":
        rs = [(Ri + 0.12, None), (r_edge, band), (r_edge - seam, seam_m)]
        r = r_edge - seam
        while r - ring_step > inner_disc + 0.2:
            r -= ring_step
            rs.append((r, panel))
            rs.append((r - seam, seam_m))
            r -= seam
        rs.append((inner_disc, panel))
        rs.append((inner_disc - seam, seam_m))
        rs.append((0.0, panel))
        prof = [(q, F) for q, _ in rs]
        rmats = [m for _, m in rs[1:]]
        seams = [radial_phase + 360.0 * (k + 0.5) / radial for k in range(radial)] if radial else []
        cols, kind, _ = columns(nf, seams, seam_w=degrees(seam * 1.6 / max(1.0, 0.5 * (r_edge + inner_disc))))

        def fm(k, i):
            m = rmats[k]
            rin = prof[k + 1][0]
            if m == panel and kind[i] == "s" and rin >= inner_disc - 1e-6:
                return seam_m
            return m
        b.lathe_a(prof, cols, fm, smooth=False)
        return
    # grid: a plain disc + seam strips clipped to the panel area
    prof = [(Ri + 0.12, F), (r_edge, F), (r_edge - seam, F), (0.0, F)]
    b.lathe_a(prof, reg_angles(nf), lambda k, i: (band, seam_m, panel)[k], smooth=False)
    rr = r_edge - seam - 0.01
    n = int(rr // grid)
    with b.at(RZ(grid_yaw)):
        for j in range(-n, n + 1):
            c = j * grid
            if abs(c) >= rr - 0.05:
                continue
            h = sqrt(rr * rr - c * c)
            b.quad((c - seam / 2, -h, F + 0.002), (c + seam / 2, -h, F + 0.002), (c + seam / 2, h, F + 0.002),
                   (c - seam / 2, h, F + 0.002), seam_m)
            b.quad((-h, c - seam / 2, F + 0.0025), (h, c - seam / 2, F + 0.0025), (h, c + seam / 2, F + 0.0025),
                   (-h, c + seam / 2, F + 0.0025), seam_m)


# --------------------------------------------------------------------------------------
# Plan: the free-standing layout of one room
# --------------------------------------------------------------------------------------
class Plan:
    """Tracks footprints, anchors, lights and hidable parts of one room interior.

    Footprints are oriented rectangles (cx, cy, hx, hy, yaw_deg) or circles (cx, cy, r) in the room frame.
    r_max: free-standing furniture stays inside this radius (the walking ring and the wall items are outside)."""

    def __init__(self, rm, clear=None, item_depth=ITEM_DEPTH):
        self.rm = rm
        self.n = rm.interior
        self.Ri = rm.Ri
        self.item_depth = item_depth
        self.wall_front = rm.Ri + 0.02 - item_depth
        self.clear = clear if clear is not None else clear_for(rm.R, None if rm.single else rm.size)
        self.r_max = self.wall_front - self.clear
        self.rects = []
        self.circles = []
        self.count = {}
        self.tall_n = 0
        self.lamps = []
        rm.extra_parts = getattr(rm, "extra_parts", [])
        rm.plan = self

    def lane_r(self):
        """Free-standing furniture inside this radius leaves every door lane clear (door_blocked, 0.9 m lane)."""
        return 0.5 * (self.wall_front + self.r_max) - LANE_HW - 0.02

    # ---- footprints -----------------------------------------------------------------
    def rect(self, cx, cy, hx, hy, yaw=0.0, tag=""):
        self.rects.append((cx, cy, hx, hy, yaw, tag))

    def circle(self, cx, cy, r, tag=""):
        self.circles.append((cx, cy, r, tag))

    def corners(self, cx, cy, hx, hy, yaw=0.0):
        c, s = cos(radians(yaw)), sin(radians(yaw))
        return [(cx + c * sx * hx - s * sy * hy, cy + s * sx * hx + c * sy * hy) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]

    def fits(self, cx, cy, hx, hy, yaw=0.0, r=None):
        r = self.r_max if r is None else r
        return all(hypot(x, y) <= r + 1e-6 for x, y in self.corners(cx, cy, hx, hy, yaw))

    def dist(self, x, y, skip_tag=None):
        """Distance from (x, y) to the nearest footprint (0 inside)."""
        best = 99.0
        for (cx, cy, hx, hy, yaw, tag) in self.rects:
            if skip_tag and tag == skip_tag:
                continue
            c, s = cos(radians(yaw)), sin(radians(yaw))
            lx = c * (x - cx) + s * (y - cy)
            ly = -s * (x - cx) + c * (y - cy)
            dx = max(abs(lx) - hx, 0.0)
            dy = max(abs(ly) - hy, 0.0)
            best = min(best, hypot(dx, dy))
        for (cx, cy, r, tag) in self.circles:
            if skip_tag and tag == skip_tag:
                continue
            best = min(best, max(0.0, hypot(x - cx, y - cy) - r))
        return best

    # ---- hidable tall parts near the ring ------------------------------------------------------
    def tall(self, x, y):
        """A new hidable part Tall_<nn> with its origin on the floor at (x, y).  The game hides it when a doorway
        is near (docs/requests/ART-HAB-to-RENDER.md)."""
        p = P("Tall_%02d" % self.tall_n, origin=(x, y, 0.0))
        self.tall_n += 1
        self.rm.extra_parts.append(p)
        return p

    # ---- anchors ----------------------------------------------------------------------------------
    def anchor(self, kind, x, y, yaw, z=F):
        i = self.count.get(kind, 0)
        self.count[kind] = i + 1
        self.rm.anchor("%s_%d" % (kind, i), (x, y, z), yaw)

    def lamp(self, x, y, z):
        """A warm lamp position (bedside lamp, desk lamp): Anchor_Lamp_<i> for the game's small lamp pools."""
        self.lamps.append((x, y, z))
        i = self.count.get("Lamp", 0)
        self.count["Lamp"] = i + 1
        self.rm.anchor("Lamp_%d" % i, (x, y, z), 0.0)

    def lights(self, pts=None, z=None):
        """Ceiling light positions Anchor_Light_<i>: S 2, M 4, L 5, XL 6 by default (centre + a ring)."""
        n = (2, 4, 5, 6)[self.rm.size] if not self.rm.single else 2
        z = z if z is not None else 2.55 + 0.1 * self.rm.size
        if pts is None:
            pts = [(0.0, 0.0)]
            rr = self.r_max * 0.62
            for k in range(n - 1):
                a = 360.0 * k / (n - 1) + 30.0
                pts.append((rr * cos(radians(a)), rr * sin(radians(a))))
        for i, (x, y) in enumerate(pts[:n] if len(pts) >= n else pts):
            self.rm.anchor("Light_%d" % i, (x, y, z), 0.0)

    def aisles(self, spacing=1.25, ring_step=2.2, clearance=0.40, link=1.75):
        """Aisle waypoints: a ring in the walking ring + a grid of free points inside r_max, kept only when
        connected.  Graph for the game: join any two aisle points closer than `link` metres."""
        pts = []
        rr = 0.5 * (self.wall_front + self.r_max)
        n = max(8, int(round(2 * pi * rr / ring_step)))
        for k in range(n):
            a = 360.0 * k / n
            x, y = rr * cos(radians(a)), rr * sin(radians(a))
            if self.dist(x, y) >= clearance * 0.8:
                pts.append((x, y))
        m = int(self.r_max // spacing)
        for i in range(-m, m + 1):
            for j in range(-m, m + 1):
                x, y = i * spacing, j * spacing
                if hypot(x, y) > self.r_max - 0.3:
                    continue
                if self.dist(x, y) < clearance:
                    continue
                pts.append((x, y))
        # keep the points connected to the ring
        keep = set(range(min(n, len(pts))))
        grow = True
        while grow:
            grow = False
            for i, (x, y) in enumerate(pts):
                if i in keep:
                    continue
                if any(hypot(x - pts[k][0], y - pts[k][1]) < link for k in keep):
                    keep.add(i)
                    grow = True
        for i in sorted(keep):
            x, y = pts[i]
            self.anchor("Aisle", x, y, degrees(atan2(y, x)) + 90.0)

    def spot(self, cands, min_clear=0.30, min_sep=0.60, kinds=("Stand", "Seat", "Bed", "Work")):
        """First candidate (x, y, yaw) with free floor round it and away from other people anchors."""
        people = [a[1] for a in self.rm.anchors if a[0].startswith(tuple("Anchor_%s_" % k for k in kinds))]
        for (x, y, yaw) in cands:
            if hypot(x, y) > self.wall_front - 0.25:
                continue
            if self.dist(x, y) < min_clear:
                continue
            if any(hypot(x - q[0], y - q[1]) < min_sep for q in people):
                continue
            return (x, y, yaw)
        return None

    def stands(self, n, cands=()):
        """Place n Anchor_Stand: first the given candidates, then free spots in the walking ring facing the room."""
        ring = 0.5 * (self.wall_front + self.r_max)
        more = [(ring * cos(radians(a)), ring * sin(radians(a)), a + 180.0) for a in range(7, 367, 17)]
        more += [(r * cos(radians(a)), r * sin(radians(a)), a + 180.0) for r in (self.r_max * 0.5, self.r_max * 0.8)
                 for a in range(11, 371, 23)]
        cands = list(cands) + more
        placed = 0
        while placed < n:
            sp = self.spot(cands)
            if sp is None:
                raise AssertionError("%s: no free spot for %d more stands" % (self.rm.tid, n - placed))
            self.anchor("Stand", sp[0], sp[1], sp[2])
            cands.remove(sp)
            placed += 1

    # ---- wall items --------------------------------------------------------------------------------
    def wall_items(self, pattern, builders, open_kinds=("panel", "vent", "poster", "plant", None), open_every=3,
                   seed=1, skip=(), depth_of=None, once=("tap",)):
        """Fill the 32 segments.  pattern: list of kinds cycled around the wall; every `open_every`-th segment is
        open wall (a panel, a vent, a poster, a plant or nothing).  builders: {kind: fn(p, w, d, k)}; a slot is
        left open when its item would touch a free-standing footprint."""
        rng = random.Random(seed)
        rm = self.rm
        placed = {}
        j = 0
        for k in range(NSEG):
            if k in skip or not rm.walls[k].faces:
                continue
            a = seg_mid(k)
            if open_every and (k % open_every == open_every - 1):
                kind = open_kinds[rng.randrange(len(open_kinds))]
            else:
                kind = pattern[j % len(pattern)]
                j += 1
                if j > len(pattern) and kind in once:
                    kind = pattern[j % len(pattern)]
                    j += 1
            if kind is None:
                continue
            d = (depth_of or {}).get(kind, ITEM_DEPTH)
            w = min(0.80, slot_width(rm, d))
            # footprint of the item in the room frame
            rc = rm.Ri + 0.02 - d / 2
            cx, cy = rc * cos(radians(a)), rc * sin(radians(a))
            if self.dist(cx, cy) < d / 2 + 0.05 or self.rect_hits(cx, cy, d / 2, w / 2, a):
                kind = "panel" if "panel" in builders else None
                if kind is None:
                    continue
                d = 0.08
            with wall_slot(rm, k) as p:
                n0 = len(p.verts)
                builders[kind](p, w, d, k)
                fit_under_cut(p, n0)
            placed[k] = kind
        return placed

    def rect_hits(self, cx, cy, hx, hy, yaw):
        for (x, y) in self.corners(cx, cy, hx, hy, yaw) + [(cx, cy)]:
            if self.dist(x, y) < 0.02:
                return True
        return False


# --------------------------------------------------------------------------------------
# Anchors: counts and checks
# --------------------------------------------------------------------------------------
CUT_TOP = WALL_TOP - 0.004     # wall items stay under the cut (the game draws Walls / WallsIn in the cutaway)


def fit_under_cut(p, n0):
    """Paul 2026-09-26 / RENDER cut check: a wall item (the vertices added since n0) that reaches above the cut is
    scaled down in height about the floor, as a whole, so its top ends at CUT_TOP (no slanted or flattened parts)."""
    vs = p.verts[n0:]
    if not vs:
        return
    top = max(v.z for v in vs)
    if top <= CUT_TOP:
        return
    k = (CUT_TOP - F) / max(1e-6, top - F)
    for v in vs:
        if v.z > F:
            v.z = F + (v.z - F) * k


def add_anchor(rm, kind, i, pos, yaw):
    rm.anchor("%s_%d" % (kind, i), pos, yaw)


def anchor_counts(rm):
    out = {}
    for a in rm.anchors:
        name = a[0][len("Anchor_"):]
        kind = name.rsplit("_", 1)[0] if name.rsplit("_", 1)[-1].isdigit() else name
        out[kind] = out.get(kind, 0) + 1
    return out


def furniture_of(rm):
    """content/buildings.json -> <type>.furniture for this size: {beds, seats, work_slots, stands, work_pose}."""
    fu = rm.bdef.get("furniture", {})
    out = {}
    for k in ("beds", "seats", "work_slots", "stands"):
        v = fu.get(k, 0)
        out[k] = int(v[rm.size] if isinstance(v, list) else v)
    out["work_pose"] = fu.get("work_pose", "stand")
    return out


def check_furniture(rm):
    """Anchor counts must equal the SIM content arrays (docs/requests/SIM-to-ART-HAB.md)."""
    if not rm.bdef.get("furniture"):
        return ["no furniture block in content for %s" % rm.tid]
    want = furniture_of(rm)
    got = anchor_counts(rm)
    flags = []
    for key, kind in (("beds", "Bed"), ("seats", "Seat"), ("work_slots", "Work"), ("stands", "Stand")):
        if got.get(kind, 0) != want[key]:
            flags.append("Anchor_%s count %d != content %s %d" % (kind, got.get(kind, 0), key, want[key]))
    return flags


def check_anchors(rm):
    """Names unique and numbered 0..n-1 per kind; people anchors off the wall; people anchors not inside furniture
    footprints (beds and seats stand beside their furniture, so their own footprint is tagged and skipped)."""
    flags = []
    names = [a[0] for a in rm.anchors]
    if len(set(names)) != len(names):
        flags.append("duplicate anchor names")
    by = {}
    for a in rm.anchors:
        name = a[0][len("Anchor_"):]
        parts = name.rsplit("_", 1)
        if len(parts) == 2 and parts[1].isdigit():
            by.setdefault(parts[0], []).append(int(parts[1]))
    for kind, idx in by.items():
        if sorted(idx) != list(range(len(idx))):
            flags.append("anchors %s not numbered 0..%d" % (kind, len(idx) - 1))
    plan = getattr(rm, "plan", None)
    for a in rm.anchors:
        if a[0].startswith(("Anchor_Bed_", "Anchor_Seat_", "Anchor_Work_", "Anchor_Stand_", "Anchor_Aisle_")):
            x, y, z = a[1]
            if hypot(x, y) > rm.Ri - 0.25:
                flags.append("%s too close to the wall" % a[0])
            if plan is not None and a[0].startswith(("Anchor_Stand_", "Anchor_Aisle_")) and plan.dist(x, y) < 0.18:
                flags.append("%s stands in a footprint" % a[0])
    return flags


# --------------------------------------------------------------------------------------
# Door clearance (critic round 4): free floor in front of a doorway at every model angle
# --------------------------------------------------------------------------------------
TALL_TAGS = ("suit", "screen", "hood", "curtain", "backbar", "sign")     # hidden near a door by the game
DOOR_CLEAR = 1.20


LANE_HW = 0.45          # RENDER / coordinator 2026-09-25: a 0.9 m lane from every doorway to the aisle ring
DOOR_FACE = 0.56        # the room face of the door housing (door kit 3.1, HX -0.56) inside the wall line


def door_blocked(plan, half=LANE_HW, step=1.0):
    """Model angles (deg) where a doorway has no clear lane to the aisle ring: the lane `2 * half` wide runs from
    the room face of the door housing (wall line - 0.56) to the far side of the aisle ring (ring radius - half).
    Free-standing footprints block it; Tall parts do not (the game hides them near a doorway), nor do wall items
    (they hide with their wall segment).  Returns ([(a0, a1)], worst free lane depth in m)."""
    rm = plan.rm
    Rw = rm.R - 0.32
    rr = 0.5 * (plan.wall_front + plan.r_max)
    r_door = Rw - DOOR_FACE
    depth = max(0.2, r_door - (rr - half))
    keep_r = [r for r in plan.rects if r[5] not in TALL_TAGS]
    keep_c = [c for c in plan.circles if c[3] not in TALL_TAGS]

    hits, hit_ang, cur_a = {}, {}, [0.0]
    plan.lane_hit_angles = hit_ang

    def inside(x, y):
        for (cx, cy, hx, hy, yaw, tag) in keep_r:
            c, s_ = cos(radians(yaw)), sin(radians(yaw))
            lx = c * (x - cx) + s_ * (y - cy)
            ly = -s_ * (x - cx) + c * (y - cy)
            if abs(lx) <= hx and abs(ly) <= hy:
                hits[tag] = max(hits.get(tag, 0.0), round(hypot(x, y), 2))
                hit_ang.setdefault(tag, set()).add(int(cur_a[0]) % 360)
                return True
        for (cx, cy, r, tag) in keep_c:
            if hypot(x - cx, y - cy) <= r:
                hits[tag] = max(hits.get(tag, 0.0), round(hypot(x, y), 2))
                hit_ang.setdefault(tag, set()).add(int(cur_a[0]) % 360)
                return True
        return False
    plan.lane_hits = hits
    plan.lane_ring = (round(rr, 2), round(r_door, 2), round(plan.r_max, 2))
    blocked, worst = [], 9.0
    a = 0.0
    while a < 360.0 - 1e-6:
        ca, sa = cos(radians(a)), sin(radians(a))
        cur_a[0] = a
        clear = depth
        for i in range(0, 25):
            d = depth * i / 24.0
            r = r_door - d
            hit = False
            for j in range(-3, 4):
                t = half * j / 3.0
                x, y = r * ca - t * sa, r * sa + t * ca
                if inside(x, y):
                    hit = True
                    break
            if hit:
                clear = d
                break
        worst = min(worst, clear)
        if clear < depth - 1e-6:
            blocked.append(a)
        a += step
    spans = []
    for b in blocked:
        if spans and b - spans[-1][1] <= step + 1e-6:
            spans[-1][1] = b
        else:
            spans.append([b, b])
    if len(spans) > 1 and spans[0][0] <= 1e-6 and spans[-1][1] >= 360.0 - step - 1e-6:
        spans[0][0] = spans[-1][0] - 360.0
        spans.pop()
    return [(round(x0 - step / 2, 1), round(x1 + step / 2, 1)) for x0, x1 in spans], round(worst, 2)


# --------------------------------------------------------------------------------------
# Stand points (critic round 6): every Bed / Seat / Work stand point has 0.35 m of free floor round it
# --------------------------------------------------------------------------------------
STAND_FREE = 0.35
SEAT_TABLE_TAGS = ("table", "ctable", "mess", "desk", "high", "booth", "bar")


def _fp_dist(fp, x, y):
    if len(fp) == 6:
        cx, cy, hx, hy, yaw, tag = fp
        c, s_ = cos(radians(yaw)), sin(radians(yaw))
        lx = c * (x - cx) + s_ * (y - cy)
        ly = -s_ * (x - cx) + c * (y - cy)
        return hypot(max(abs(lx) - hx, 0.0), max(abs(ly) - hy, 0.0))
    cx, cy, r, tag = fp
    return max(0.0, hypot(x - cx, y - cy) - r)


def check_standpoints(rm, free=STAND_FREE):
    """A person's stand point must not stand on or next to furniture other than its own: its own item (the bed or
    seat 0.55 / 0.30 behind it, the console or bench 0.45 ahead) and, for a seat, the table it faces are allowed;
    every other footprint keeps `free` metres away.  Tall parts count (a headboard is furniture too)."""
    plan = getattr(rm, "plan", None)
    if plan is None:
        return []
    fps = list(plan.rects) + list(plan.circles)
    flags = []
    for a in rm.anchors:
        name = a[0]
        if not name.startswith(("Anchor_Bed_", "Anchor_Seat_", "Anchor_Work_")):
            continue
        x, y = a[1][0], a[1][1]
        yaw = a[2] if len(a) > 2 else 0.0
        dx, dy = cos(radians(yaw)), sin(radians(yaw))
        own_pts = []
        if name.startswith("Anchor_Bed_"):
            own_pts = [(x - BED_BACK * dx, y - BED_BACK * dy)]
        elif name.startswith("Anchor_Seat_"):
            own_pts = [(x - SEAT_BACK * dx, y - SEAT_BACK * dy), (x + 0.35 * dx, y + 0.35 * dy),
                       (x + 0.60 * dx, y + 0.60 * dy), (x + 0.85 * dx, y + 0.85 * dy)]
        else:
            own_pts = [(x + CONSOLE_AHEAD * dx, y + CONSOLE_AHEAD * dy), (x + 0.30 * dx, y + 0.30 * dy),
                       (x - SEAT_BACK * dx, y - SEAT_BACK * dy), (x + 0.60 * dx, y + 0.60 * dy)]
        own = [fp for fp in fps if any(_fp_dist(fp, px, py) <= 0.02 for px, py in own_pts)]
        if name.startswith("Anchor_Work_") and furniture_of(rm).get("work_pose", "stand") != "sit":
            # a standing worker's feet stay off the counter, bench or console he works at
            ahead = [fp for fp in fps if _fp_dist(fp, x + CONSOLE_AHEAD * dx, y + CONSOLE_AHEAD * dy) <= 0.02]
            if ahead and min(_fp_dist(fp, x, y) for fp in ahead) < 0.12:
                flags.append("%s stands %.2f m from its counter (< 0.12)" % (name, min(_fp_dist(fp, x, y) for fp in ahead)))
        if name.startswith("Anchor_Seat_"):          # the table a person sits at is part of the seat
            own += [fp for fp in fps if fp[-1] in SEAT_TABLE_TAGS and fp not in own]
        others = [fp for fp in fps if fp not in own]
        if not others:
            continue
        d = min(_fp_dist(fp, x, y) for fp in others)
        if d < free - 1e-6:
            worst = min(others, key=lambda fp: _fp_dist(fp, x, y))
            flags.append("%s has %.2f m free floor (< %.2f) next to %s" % (name, d, free, worst[-1] or "an item"))
    return flags


# --------------------------------------------------------------------------------------
# 3.1 decals per wall segment (docs/V3_1_DESIGN.md section 3.3)
# --------------------------------------------------------------------------------------
DECAL_MATS = ("Accent", "Window", "Neon", "L3Band", "L4Band", "L5Gold", "Trim", "Light", "LightStrip", "Hazard",
              "Screen", "Glow", "Plasma", "Visor", "Rubber", "Solar")
DECAL_ZMAX = 3.0            # the door housing top is 2.56; decals above 3.0 m never meet a doorway
UPPER_SHELLS = ("podium", "drum", "setback")
NAME_SIGN_DEG = 22.5        # default angle of the room-name sign (middle of segment 2)


def _face_centre(part, idx):
    vs = [part.verts[i] for i in idx]
    n = len(vs)
    return (sum(v.x for v in vs) / n, sum(v.y for v in vs) / n, sum(v.z for v in vs) / n)


def _face_normal(part, idx):
    a, b, c = part.verts[idx[0]], part.verts[idx[1]], part.verts[idx[2]]
    nv = (b - a).cross(c - a)
    return nv.normalized() if nv.length > 1e-12 else nv


def _split_at_segments(src, idx):
    """Round 12: cut a wall face (vertical, less than 180 deg wide) at every segment boundary it crosses, so each piece
    lies in one segment.  New corner vertices are appended to src.verts.  Returns [(seg, [vertex ids])]."""
    angs = [degrees(atan2(src.verts[i].y, src.verts[i].x)) for i in idx]
    base = angs[0]
    un = [base + ((a - base + 180.0) % 360.0) - 180.0 for a in angs]
    lo, hi = min(un), max(un)
    cuts = [k * SEG_DEG for k in range(int(floor(lo / SEG_DEG)) + 1, int(ceil(hi / SEG_DEG)))
            if lo + 1e-4 < k * SEG_DEG < hi - 1e-4]
    pieces = [list(idx)]
    for c in cuts:
        n = Vector((-sin(radians(c)), cos(radians(c)), 0.0))
        nxt = []
        for poly in pieces:
            d = [n.dot(src.verts[i]) for i in poly]
            if all(x >= -1e-6 for x in d) or all(x <= 1e-6 for x in d):
                nxt.append(poly)
                continue
            pos, neg = [], []
            for j in range(len(poly)):
                i0, i1 = poly[j], poly[(j + 1) % len(poly)]
                d0, d1 = d[j], d[(j + 1) % len(poly)]
                (pos if d0 >= 0 else neg).append(i0)
                if (d0 >= 0) != (d1 >= 0):
                    t = d0 / (d0 - d1)
                    q = src.verts[i0].lerp(src.verts[i1], t)
                    src.verts.append(q)
                    if hasattr(src, "vover"):
                        src.vover.append(False)
                    ni = len(src.verts) - 1
                    pos.append(ni)
                    neg.append(ni)
            nxt += [x for x in (pos, neg) if len(x) >= 3]
        pieces = nxt
    out = []
    for poly in pieces:
        c = sum((src.verts[i] for i in poly), Vector((0, 0, 0))) / len(poly)
        out.append((int((degrees(atan2(c.y, c.x)) % 360.0) // SEG_DEG) % NSEG, poly))
    return out


def split_decals(rm):
    """Move every outer-wall decal face (by material) of Base, Roof, Lights and L2..L5 that lies in the doorway zone
    (radius >= Rw - 0.45, z <= DECAL_ZMAX) into Decal_<seg>_<source> parts, and, for flat-walled shells, the upper
    wall skin at the wall line (1.40 m .. deck) into Upper_<seg> parts.  The game hides them per segment at a
    doorway.  Returns {"decals": [names], "upper": (z0, z1) or None}."""
    Rw = rm.R - 0.32
    upper_z = None
    shell = getattr(rm, "shell", None)
    if shell in ("podium", "drum") and getattr(rm, "D", None):
        upper_z = (WALL_TOP, float(rm.D) + 0.05)
    band = None
    sources = [rm.base, rm.roof, rm.lights] + ([rm.L[n] for n in (2, 3, 4, 5)] if rm.levels else [])
    out = {}
    for src in sources:
        if not src.faces:
            continue
        keep_f, keep_m, keep_s = [], [], []
        for idx, mat, sm in zip(src.faces, src.fmat, src.fsmooth):
            cx, cy, cz = _face_centre(src, idx)
            r = hypot(cx, cy)
            target = None
            skin = False
            seg = int((degrees(atan2(cy, cx)) % 360.0) // SEG_DEG) % NSEG
            if upper_z and src is rm.roof and mat == "Accent" and abs(r - Rw) < 0.12 and                     upper_z[0] < cz < upper_z[1]:
                zs_ = [src.verts[i].z for i in idx]
                band = (min(zs_), max(zs_)) if band is None else (min(band[0], min(zs_)), max(band[1], max(zs_)))
            if shell == "setback" and src is rm.roof and r >= Rw - 0.60 and WALL_TOP < cz < 3.2 and                     not (abs(_face_normal(src, idx).z) > 0.9 and cz < 1.6):
                target = "Upper_%02d" % seg           # things on the setback deck near the wall (tanks, rails)
            elif upper_z and src is rm.roof and abs(r - Rw) < 0.16 and upper_z[0] - 0.01 <= cz <= upper_z[1] \
                    and abs(_face_normal(src, idx).z) < 0.4:
                target = "Upper_%02d" % seg           # the upper wall skin and its band hide with the wall rule
                skin = True                           # cut at the segment lines (the skin faces are wider)
            elif r >= Rw - 0.45 and 0.05 <= cz <= DECAL_ZMAX:
                if mat in DECAL_MATS or src is rm.lights:
                    target = "Decal_%02d_%s" % (seg, src.name)
            if target is None:
                keep_f.append(idx)
                keep_m.append(mat)
                keep_s.append(sm)
                continue
            if skin:
                jobs_ = [("Upper_%02d" % sg, poly) for sg, poly in _split_at_segments(src, idx)]
            else:
                jobs_ = [(target, idx)]
            for target, idx_ in jobs_:
                q = out.get(target)
                if q is None:
                    q = out[target] = (P(target), {})
                part, vmap = q
                new_idx = []
                for i in idx_:
                    if i not in vmap:
                        vmap[i] = len(part.verts)
                        part.verts.append(src.verts[i].copy())
                        part.vover.append(src.vover[i] if i < len(src.vover) else False)
                    new_idx.append(vmap[i])
                part.faces.append(tuple(new_idx))
                part.fmat.append(mat)
                part.fsmooth.append(sm)
        src.faces, src.fmat, src.fsmooth = keep_f, keep_m, keep_s
    rm.decals = [q[0] for name, q in sorted(out.items())]
    return {"decals": sorted(n for n in out if n.startswith("Decal_")),
            "upper": sorted(n for n in out if n.startswith("Upper_")), "upper_z": upper_z,
            "upper_band": [round(band[0], 3), round(band[1], 3)] if band else None}


def name_sign(rm):
    """The room-name sign (object NameSign, origin at the room centre): a lit plate on the wall face at the model
    angle rm.name_sign_deg (default NAME_SIGN_DEG), 0.48..0.82 m high.  The game turns the object about the room axis
    to move it to the free segment nearest to that angle."""
    Rw = rm.R - 0.32
    p = P("NameSign")
    ang = getattr(rm, "name_sign_deg", NAME_SIGN_DEG)
    rm.name_sign_deg = ang
    with p.at(RZ(ang), T(Rw + 0.005, 0, 0)):
        bbox(p, 0.0, 0.04, -0.52, 0.52, 0.48, 0.82, "Frame")
        plate_x(p, 0.041, -0.48, 0.48, 0.51, 0.79, "Screen")
        plate_x(p, 0.043, -0.46, 0.46, 0.52, 0.535, "Accent")
    rm.decals = list(getattr(rm, "decals", [])) + [p]
    return p
