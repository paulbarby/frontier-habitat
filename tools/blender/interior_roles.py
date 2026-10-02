"""Frontier Habitat 5.0 role props (V5_DESIGN 15.3, Paul 2026-10-01: pop culture and the 2026 AI boom, ridiculous, in
EVERY room type).  Second part of the shared prop kit (interior_props.py is the first: text, posters, screens, desk
clutter, kettle, toaster, shrine).  This file adds props BY ROOM ROLE, so a mine does not look like a nursery:

  industry   safety board, foreman bot, roster, hard hats, vending machine, gauges, extinguisher, time clock ...
  farm       seed rack, plant leaderboard, garden gnome with a visor, plant chat stake
  life       air board, rubber duck
  logistics  inventory screen, drone dock, crates with stencils
  medical    eye chart, AI diagnosis screen, peer-review poster
  civic      wanted board, tally marks, blackboard, shop signs
  housing    photos, kids' drawings, ring light
  links      route signs

All names, slogans and art are ORIGINAL parodies (no real logos, brands, characters or lyrics).  Everything is
geometry with the existing materials.  Wall pieces are built in the wall-slot frame of interior_kit (x = 0 on the wall
panel, +X into the room, text along +Y, z absolute); flat pieces live between PR.ZLO and PR.ZHI (the wall's pipe run
and cove light are outside that band; see interior_props.WALL_OFF).  Free-standing pieces (DECOR) are built in the
frame of interior_rooms.at(): +X is the front.

Hook: interior_kit.Plan.wall_items asks role_for(tid) and replaces filler wall kinds (vent, cable, panel, poster,
plant, open wall) by role pieces; the free-standing pieces register in interior_families.DECOR / NEED.
"""
import os
import random
from math import sin, cos, radians, pi

from rooms_kit import T, RX, RY, RZ
from interior_kit import F, bbox, plate_x, plate_z
import interior_props as PR
from interior_props import text, text_lines, text_width, fit_h, WALL_OFF, ZLO, ZHI

ZB = F + ZLO            # the lowest flat piece (0.50 m)
ZT = F + ZHI            # the highest (1.24 m)


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------
def board(p, w, z0, z1, bg, frame="Frame", d=0.03, off=WALL_OFF):
    """A framed flat board on the wall, centred on y = 0.  Returns the x of its face."""
    bbox(p, off, off + d, -w / 2, w / 2, z0, z1, frame)
    plate_x(p, off + d + 0.001, -w / 2 + 0.02, w / 2 - 0.02, z0 + 0.02, z1 - 0.02, bg)
    return off + d + 0.002


def disc_x(p, x, y, z, r, mat, seg=12):
    """A flat disc on the plane x, facing +X."""
    with p.at(T(x, y, z), RY(90.0)):
        p.cap_disc(r, 0.0, mat, seg=seg)


def polyline(p, x, pts, th, mat):
    """A thin line through (y, z) points on the plane x, facing +X."""
    for (y0, z0), (y1, z1) in zip(pts[:-1], pts[1:]):
        dy, dz = y1 - y0, z1 - z0
        L = (dy * dy + dz * dz) ** 0.5
        if L < 1e-6:
            continue
        ny, nz = -dz / L * th / 2, dy / L * th / 2
        p.quad((x, y0 + ny, z0 + nz), (x, y1 + ny, z1 + nz), (x, y1 - ny, z1 - nz), (x, y0 - ny, z0 - nz), mat)


def hbar(p, x, y0, y1, z, hh, mat):
    plate_x(p, x, y0, y1, z - hh / 2, z + hh / 2, mat)


def lines_box(p, lines, yc, ztop, h, mat, x, gap=0.55):
    return text_lines(p, lines, yc, ztop, h, mat, x=x, gap=gap)


# --------------------------------------------------------------------------------------
# industry
# --------------------------------------------------------------------------------------
SAFETY = (("SAFETY FIRST", ("DAYS SINCE", "LAST INCIDENT"), "0", "*AI RECOUNTING"),
          ("HARD HATS", ("WEAR ONE. THE", "AI HAS NO HEAD"), "!", "NO EXCEPTIONS"),
          ("NOTICE", ("INCIDENTS TODAY", "(SO FAR)"), "0", "KEEP IT UP"),
          ("SAFETY FIRST", ("DAYS SINCE", "THE LAST AUDIT"), "412", "BY A BOT"))


def safety(p, w, d, k):
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.06, ZB + 0.66
    x = board(p, ww, z0, z1, "Hull")
    head, lines, big, foot = SAFETY[k % len(SAFETY)]
    plate_x(p, x, -ww / 2 + 0.02, ww / 2 - 0.02, z1 - 0.15, z1 - 0.02, "Plant")
    text(p, head, 0.0, z1 - 0.085, fit_h([head], ww - 0.10, 0.060), "Hull", x=x + 0.001)
    hh = fit_h(lines, ww - 0.10, 0.044)
    zz = text_lines(p, lines, 0.0, z1 - 0.19, hh, "HullDark", x=x + 0.001)
    bw = min(ww - 0.16, 0.22 + 0.12 * len(big))
    plate_x(p, x, -bw / 2, bw / 2, z0 + 0.10, zz - 0.04, "HullDark")
    text(p, big, 0.0, 0.5 * (z0 + 0.10 + zz - 0.04), min(0.15, (zz - 0.04 - z0 - 0.10) * 0.7), "Window", x=x + 0.001)
    text(p, foot, 0.0, z0 + 0.055, 0.016, "HullDark", x=x + 0.001)


FOREMAN = (("TASKS: 4812", "HUMANS: 6", "MORALE: OPTIMISED"), ("QUEUE: 9001", "BREAKS: SOON*", "JOY: PENDING"),
           ("EFFICIENCY 340%", "SLEEP: OPTIONAL", "NAMES: LOST"))


def foreman(p, w, d, k):
    ww = min(0.72, w - 0.04)
    z0, z1 = ZB + 0.14, ZB + 0.62
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "FOREMAN-BOT 4", 0.0, z1 - 0.07, fit_h(["FOREMAN-BOT 4"], ww - 0.12, 0.034), "Neon", x=x + 0.001)
    hbar(p, x, -ww / 2 + 0.04, ww / 2 - 0.04, z1 - 0.125, 0.008, "LightStrip")
    ls = FOREMAN[k % len(FOREMAN)]
    hh = fit_h(ls, ww - 0.12, 0.034)
    text_lines(p, ls, 0.0, z1 - 0.16, hh, "LightStrip", x=x + 0.001, gap=0.7)
    text(p, "*SEE SMALL PRINT", 0.0, z0 + 0.04, 0.014, "Window", x=x + 0.001)
    disc_x(p, x + 0.001, -ww / 2 + 0.06, z1 - 0.07, 0.016, "Glow", seg=8)         # a status light


def rota(p, w, d, k):
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.04, ZB + 0.70
    x = board(p, ww, z0, z1, "Hull")
    text(p, "ROSTER (AI DRAFT)", 0.0, z1 - 0.06, fit_h(["ROSTER (AI DRAFT)"], ww - 0.10, 0.034), "HullDark", x=x + 0.001)
    cols, rows = 5, 5
    cw, ch = (ww - 0.10) / cols, (z1 - z0 - 0.20) / rows
    rng = random.Random(k * 17 + 3)
    mats = ("Plant", "WaterBlue", "Hazard", "Fabric", "CushionLight", "HullDark")
    for r in range(rows):
        for c in range(cols):
            y0 = -ww / 2 + 0.05 + c * cw
            zz = z1 - 0.13 - (r + 1) * ch
            m = mats[rng.randrange(len(mats))]
            if r == 0 or c == 0:
                m = "Frame"
            plate_x(p, x + 0.001, y0 + 0.006, y0 + cw - 0.006, zz + 0.006, zz + ch - 0.006, m)
    text(p, "ALL SHIFTS: NIGHT", 0.0, z0 + 0.04, 0.016, "HullDark", x=x + 0.002)


def hat(p, x, y, z, mat):
    """A hard hat hanging on a peg (dome, brim, ridge)."""
    with p.at(T(x, y, z)):
        p.lathe([(0.0, 0.10), (0.06, 0.092), (0.10, 0.05), (0.105, 0.0), (0.135, -0.004), (0.135, -0.012)],
                mat, seg=10, smooth=True)
    bbox(p, x - 0.012, x + 0.012, y - 0.008, y + 0.008, z + 0.05, z + 0.108, "Frame")


def hats(p, w, d, k):
    ww = min(0.76, w - 0.02)
    zp = ZB + 0.50
    bbox(p, WALL_OFF, WALL_OFF + 0.03, -ww / 2, ww / 2, zp, zp + 0.07, "Wood")
    mats = ("Hazard", "Hull", "Accent", "SignalRed")
    n = 4 if ww > 0.55 else 3
    for j in range(n):
        y = -ww / 2 + ww * (j + 0.5) / n
        bbox(p, WALL_OFF + 0.03, WALL_OFF + 0.09, y - 0.012, y + 0.012, zp + 0.025, zp + 0.045, "Frame")
        if j == n - 1 and n == 4:                    # a hi-vis vest on the last peg
            bbox(p, WALL_OFF + 0.09, WALL_OFF + 0.10, y - 0.11, y + 0.11, zp - 0.36, zp + 0.03, "Hazard")
            bbox(p, WALL_OFF + 0.101, WALL_OFF + 0.108, y - 0.11, y + 0.11, zp - 0.20, zp - 0.16, "Hull")
            bbox(p, WALL_OFF + 0.101, WALL_OFF + 0.108, y - 0.11, y + 0.11, zp - 0.30, zp - 0.26, "Hull")
        else:
            hat(p, WALL_OFF + 0.15, y, zp - 0.075, mats[(j + k) % len(mats)])
    text(p, "HEADS UP", 0.0, zp + 0.175, 0.036, "HullDark", x=WALL_OFF + 0.002)
    text(p, "(AI HAS NONE)", 0.0, zp + 0.125, 0.020, "HullDark", x=WALL_OFF + 0.002)


def gauge(p, x, y, z, r, label, needle=0.2):
    bbox(p, x - 0.02, x, y - r - 0.012, y + r + 0.012, z - r - 0.012, z + r + 0.012, "Frame")
    disc_x(p, x + 0.001, y, z, r + 0.012, "Frame", seg=14)
    disc_x(p, x + 0.003, y, z, r, "Hull", seg=14)
    for t in range(-3, 4):                                     # tick marks over a 240 degree sweep
        a = radians(90.0 + 40.0 * t)
        plate_x(p, x + 0.004, y + (r - 0.012) * cos(a) - 0.003, y + (r - 0.012) * cos(a) + 0.003,
                z + (r - 0.012) * sin(a) - 0.006, z + (r - 0.012) * sin(a) + 0.006, "HullDark")
    a = radians(90.0 - 130.0 * needle)
    p.quad((x + 0.006, y - 0.003 * sin(a), z + 0.003 * cos(a)), (x + 0.006, y + 0.003 * sin(a), z - 0.003 * cos(a)),
           (x + 0.006, y + (r - 0.015) * cos(a) + 0.003 * sin(a), z + (r - 0.015) * sin(a) - 0.003 * cos(a)),
           (x + 0.006, y + (r - 0.015) * cos(a) - 0.003 * sin(a), z + (r - 0.015) * sin(a) + 0.003 * cos(a)), "SignalRed")
    text(p, label, y, z - r - 0.05, 0.020, "HullDark", x=x + 0.003)


def gauges(p, w, d, k):
    ww = min(0.76, w - 0.02)
    x = WALL_OFF + 0.02
    bbox(p, WALL_OFF, x, -ww / 2, ww / 2, ZB + 0.14, ZB + 0.66, "HullDark", bevel=0.01)
    r = min(0.095, (ww - 0.10) / 6.4)
    labs = (("TEMP", 0.34), ("PSI", 0.62), ("VIBES", 0.15 + 0.05 * (k % 3)))
    for j, (lb, nd) in enumerate(labs):
        y = (j - 1) * (2 * r + 0.045)
        gauge(p, x, y, ZB + 0.42, r, lb, needle=nd)
    text(p, "NORMAL-ISH", 0.0, ZB + 0.20, 0.022, "Window", x=x + 0.003)


def extinguisher(p, w, d, k):
    x0 = WALL_OFF
    bbox(p, x0, x0 + 0.02, -0.17, 0.17, ZB + 0.04, ZB + 0.54, "SecBlack")
    p.vcyl(x0 + 0.10, 0.0, ZB + 0.06, ZB + 0.36, 0.062, seg=10, mat="SignalRed", cap0=False)
    p.lathe([(0.062, ZB + 0.36), (0.045, ZB + 0.41), (0.02, ZB + 0.43), (0.0, ZB + 0.43)], "SignalRed", seg=10,
            smooth=False, caps=False)
    bbox(p, x0 + 0.07, x0 + 0.13, -0.02, 0.02, ZB + 0.43, ZB + 0.47, "Frame")
    p.beam((x0 + 0.10, 0.0, ZB + 0.47), (x0 + 0.17, 0.10, ZB + 0.40), 0.014, 0.014, "Frame")
    p.tube([(x0 + 0.13, 0.03, ZB + 0.40), (x0 + 0.20, 0.10, ZB + 0.24), (x0 + 0.13, 0.06, ZB + 0.12)], 0.011, seg=5,
           mat="Rubber", caps=False)
    plate_x(p, x0 + 0.163, -0.04, 0.04, ZB + 0.18, ZB + 0.30, "Hull")                        # label
    text(p, "FIRE", 0.0, ZB + 0.24, 0.020, "SignalRed", x=x0 + 0.1635)
    # the sign above (the wall zone up to the cove light)
    plate_x(p, x0 + 0.02, -0.17, 0.17, ZB + 0.56, ZT - 0.02, "SignalRed")
    text(p, "ASK A", 0.0, ZB + 0.655, 0.034, "Hull", x=x0 + 0.021)
    text(p, "HUMAN", 0.0, ZB + 0.605, 0.034, "Hull", x=x0 + 0.021)


def agi_board(p, w, d, k):
    """A flip-card countdown that never changes (the in-joke of the colony)."""
    ww = min(0.60, w - 0.06)
    z0, z1 = ZB + 0.16, ZB + 0.58
    x = board(p, ww, z0, z1, "HullDark")
    text(p, "AGI ETA", 0.0, z1 - 0.06, 0.036, "LightStrip", x=x + 0.001)
    for j, (ch, y) in enumerate((("2", -0.13), ("W", 0.03), ("K", 0.13))):
        yy = y if j else y
        plate_x(p, x + 0.001, yy - 0.055, yy + 0.055, z0 + 0.12, z1 - 0.13, "Frame")
        hbar(p, x + 0.002, yy - 0.055, yy + 0.055, 0.5 * (z0 + 0.12 + z1 - 0.13), 0.006, "HullDark")
        text(p, ch, yy, 0.5 * (z0 + 0.12 + z1 - 0.13), 0.10, "Window", x=x + 0.003)
    text(p, "(SINCE 2022)", 0.0, z0 + 0.06, 0.020, "LightStrip", x=x + 0.001)


def vending(p, w, d, k):
    """A vending machine (0.40 m deep): a glass front over four shelves of snacks, a screen, a keypad, a flap."""
    ww = min(0.66, w - 0.10)
    dd = 0.40
    top = F + 1.14
    wy0, wy1 = -ww / 2 + 0.04, ww / 2 - 0.20          # the window (y)
    wz0, wz1 = F + 0.64, top - 0.14                   # the window (z)
    bbox(p, 0.0, dd, -ww / 2, ww / 2, F, wz0, "Hull", bevel=0.015)                       # base with the flap
    bbox(p, 0.0, dd, -ww / 2, wy0, wz0, top, "Hull")                                     # left post
    bbox(p, 0.0, dd, wy1, ww / 2, wz0, top, "Hull", bevel=0.01)                          # right column
    bbox(p, 0.0, dd, wy0, wy1, wz1, top, "Hull")                                         # head
    bbox(p, 0.0, dd - 0.10, wy0, wy1, wz0, wz1, "HullDark")                              # the cavity back
    # shelves of snacks (boxes and bottles) inside the cavity, a glass front
    rng = random.Random(k * 5 + 1)
    mats = ("Hazard", "SignalRed", "WaterBlue", "Plant", "Fabric", "Hull", "Accent")
    ny = 4
    sw = (wy1 - wy0 - 0.04) / ny
    for r in range(4):                    # size rule: snacks are cards behind the glass, shelves are lit edges
        zs = wz0 + 0.03 + 0.115 * r
        plate_x(p, dd - 0.02, wy0, wy1, zs - 0.012, zs, "Metal")
        for c in range(ny):
            y0 = wy0 + 0.02 + c * sw
            m = mats[rng.randrange(len(mats))]
            if (r + c) % 3 == 0:                                             # a bottle: body and cap
                plate_x(p, dd - 0.04, y0 + sw / 2 - 0.022, y0 + sw / 2 + 0.022, zs, zs + 0.075, m)
                plate_x(p, dd - 0.04, y0 + sw / 2 - 0.010, y0 + sw / 2 + 0.010, zs + 0.075, zs + 0.095, "Frame")
            else:
                plate_x(p, dd - 0.04, y0 + 0.012, y0 + sw - 0.012, zs, zs + 0.08, m)
    plate_x(p, dd - 0.005, wy0, wy1, wz0, wz1, "Glass")
    # right column: screen, keypad, coin slot
    yc = 0.5 * (wy1 + ww / 2)
    plate_x(p, dd + 0.001, yc - 0.07, yc + 0.07, top - 0.31, top - 0.15, "Screen")
    text(p, "SNAX", yc, top - 0.21, 0.022, "Neon", x=dd + 0.002)
    text(p, "3 TOKENS", yc, top - 0.26, 0.013, "LightStrip", x=dd + 0.002)
    for r in range(3):
        for c in range(3):
            bbox(p, dd, dd + 0.01, yc - 0.05 + 0.04 * c, yc - 0.03 + 0.04 * c, top - 0.42 - 0.04 * r,
                 top - 0.395 - 0.04 * r, "HullDark")
    plate_x(p, dd + 0.001, yc - 0.04, yc + 0.04, top - 0.58, top - 0.55, "Frame")
    # dispensing flap in the base, the sign over the window
    plate_x(p, dd + 0.001, -ww / 2 + 0.06, ww / 2 - 0.20, F + 0.08, F + 0.30, "Frame")
    plate_x(p, dd + 0.002, -ww / 2 + 0.08, ww / 2 - 0.22, F + 0.10, F + 0.28, "Rubber")
    plate_x(p, dd + 0.001, wy0, wy1, wz1 + 0.01, top - 0.015, "Neon")
    text(p, "VENDOTRON", 0.5 * (wy0 + wy1), 0.5 * (wz1 + top), fit_h(["VENDOTRON"], wy1 - wy0 - 0.06, 0.050),
         "HullDark", x=dd + 0.002)


def clock(p, w, d, k):
    """A time clock: a box with a card slot and a screen 'PUNCH IN (OR LOG IN)'."""
    x0 = WALL_OFF
    bbox(p, x0, x0 + 0.07, -0.20, 0.20, ZB + 0.22, ZB + 0.70, "HullDark", bevel=0.012)
    plate_x(p, x0 + 0.071, -0.16, 0.16, ZB + 0.45, ZB + 0.66, "Screen")
    text(p, "PUNCH IN", 0.0, ZB + 0.60, 0.030, "LightStrip", x=x0 + 0.072)
    text(p, "(OR LOG IN)", 0.0, ZB + 0.53, 0.018, "Window", x=x0 + 0.072)
    bbox(p, x0 + 0.06, x0 + 0.085, -0.10, 0.10, ZB + 0.32, ZB + 0.345, "Rubber")
    for j in range(3):
        disc_x(p, x0 + 0.072, -0.08 + 0.08 * j, ZB + 0.27, 0.012, ("Glow", "Window", "SignalRedGlow")[j], seg=8)


def whiteboard(p, w, d, k):
    ww = min(0.78, w - 0.02)
    z0, z1 = ZB + 0.06, ZB + 0.66
    x = board(p, ww, z0, z1, "Hull", frame="Metal")
    # a scribbled diagram: boxes joined by arrows, a sticky-note cluster, a headline
    heads = ("SPRINT 12: MAKE IT AI", "Q3: ADD AI", "ROADMAP: AI")
    text(p, heads[k % 3], 0.0, z1 - 0.07, fit_h([heads[k % 3]], ww - 0.10, 0.034), "HullDark", x=x + 0.001)
    zr = z1 - 0.20
    for j, (t, m) in enumerate((("DATA", "WaterBlue"), ("???", "Hazard"), ("AGI", "Plant"))):
        yc = -ww * 0.30 + ww * 0.30 * j
        plate_x(p, x + 0.001, yc - 0.085, yc + 0.085, zr - 0.07, zr + 0.07, m)
        text(p, t, yc, zr, 0.040, "HullDark", x=x + 0.002)
        if j < 2:
            plate_x(p, x + 0.001, yc + 0.095, yc + 0.205, zr - 0.007, zr + 0.007, "HullDark")
            p.tri((x + 0.001, yc + 0.205, zr - 0.03), (x + 0.001, yc + 0.205, zr + 0.03), (x + 0.001, yc + 0.245, zr),
                  "HullDark")
    for j, (m, dy, dz) in enumerate((("Hazard", 0.0, 0.0), ("Fabric", 0.11, 0.03), ("Glow", 0.22, -0.01))):
        plate_x(p, x + 0.001, ww * 0.18 + dy - 0.045, ww * 0.18 + dy + 0.045, z0 + 0.10 + dz, z0 + 0.19 + dz, m)
    lines = ("TODO: SYNERGY", "BLOCKED: ALL", "OWNER: THE BOT")
    text_lines(p, lines, -ww * 0.20, z0 + 0.255, 0.026, "HullDark", x=x + 0.001, gap=0.6)
    bbox(p, WALL_OFF, WALL_OFF + 0.06, -ww / 2 + 0.05, ww / 2 - 0.05, z0 - 0.015, z0 + 0.01, "Metal")     # tray
    for j, m in enumerate(("SignalRed", "WaterBlue", "Plant")):
        bbox(p, WALL_OFF + 0.01, WALL_OFF + 0.05, ww * 0.20 + 0.05 * j, ww * 0.20 + 0.05 * j + 0.03, z0 + 0.01,
             z0 + 0.025, m)


# --------------------------------------------------------------------------------------
# farm and life support
# --------------------------------------------------------------------------------------
def seedrack(p, w, d, k):
    """Seed packets on a wall rack, a watering can on the lowest shelf (0.26 m deep)."""
    ww = min(0.76, w - 0.02)
    dd = 0.26
    bbox(p, 0.0, 0.08, -ww / 2, ww / 2, F + 0.28, F + 1.06, "Wood")      # 8 cm: clears the pipe run
    zs_ = [F + 0.32 + 0.26 * j for j in range(3)]
    for zs in zs_:
        bbox(p, 0.0, dd, -ww / 2, ww / 2, zs - 0.02, zs, "Wood")
        bbox(p, dd - 0.02, dd, -ww / 2, ww / 2, zs, zs + 0.03, "Wood")
    rng = random.Random(k * 3 + 7)
    names = ("TOMATO", "KALE.AI", "WHEAT", "BEET", "SPUD", "BASIL")
    mats = ("Fabric", "Plant", "Hazard", "WaterBlue", "Hull", "Accent")
    for j, zs in enumerate(zs_):
        n = 4 if ww > 0.6 else 3
        for c in range(n - (1 if j == 0 else 0)):
            y = -ww / 2 + 0.07 + (ww - 0.14) * (c + 0.5) / n
            m = mats[rng.randrange(len(mats))]
            bbox(p, dd - 0.10, dd - 0.085, y - 0.055, y + 0.055, zs, zs + 0.17, m)
            plate_x(p, dd - 0.084, y - 0.045, y + 0.045, zs + 0.03, zs + 0.11, "Hull")
            nm = names[(j * 3 + c) % len(names)]
            if len(nm) <= 6:
                text(p, nm, y, zs + 0.075, 0.016, "HullDark", x=dd - 0.083)
    # a watering can at the right end of the lowest shelf
    zc = zs_[0]
    y = ww / 2 - 0.15
    bbox(p, 0.06, 0.20, y - 0.09, y + 0.09, zc, zc + 0.13, "Metal", bevel=0.015)
    p.cyl((0.20, y, zc + 0.08), (0.27, y, zc + 0.17), 0.016, 0.012, seg=5, mat="Metal")
    p.beam((0.07, y - 0.09, zc + 0.12), (0.07, y + 0.09, zc + 0.12), 0.012, 0.012, "Frame")


def plantboard(p, w, d, k):
    """The plant leaderboard (names and moods of the crops)."""
    ww = min(0.72, w - 0.04)
    z0, z1 = ZB + 0.04, ZB + 0.68
    x = board(p, ww, z0, z1, "PlantDark")
    text(p, "PLANT LEADERBOARD", 0.0, z1 - 0.06, fit_h(["PLANT LEADERBOARD"], ww - 0.10, 0.034), "Hull", x=x + 0.001)
    rows = (("1 DEBBIE", "THRIVING", "Glow"), ("2 KEVIN", "FINE", "Window"), ("3 BRIAN", "SULKING", "SignalRedGlow"),
            ("4 FERN", "I AM FERN", "LightStrip"))
    for j, (nm, mood, m) in enumerate(rows):
        zz = z1 - 0.16 - 0.115 * j
        plate_x(p, x + 0.001, -ww / 2 + 0.04, ww / 2 - 0.04, zz - 0.045, zz + 0.045, "Hull")
        text(p, nm, -ww * 0.22, zz, 0.032, "HullDark", x=x + 0.002)
        text(p, mood, ww * 0.22, zz, 0.022, "HullDark", x=x + 0.002)
        disc_x(p, x + 0.002, ww / 2 - 0.075, zz, 0.014, m, seg=8)
    text(p, "WATER = LOVE", 0.0, z0 + 0.04, 0.020, "Hull", x=x + 0.001)


def airboard(p, w, d, k):
    ww = min(0.72, w - 0.04)
    z0, z1 = ZB + 0.10, ZB + 0.60
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "AIR QUALITY", 0.0, z1 - 0.06, fit_h(["AIR QUALITY"], ww - 0.12, 0.036), "Neon", x=x + 0.001)
    ls = ("O2: 21.0%", "CO2: 0.04%", "VIBES: GOOD")
    text_lines(p, ls, 0.0, z1 - 0.12, fit_h(ls, ww - 0.14, 0.040), "LightStrip", x=x + 0.001, gap=0.6)
    for j in range(5):                                                     # a breath-rate trace
        yy = -ww * 0.34 + ww * 0.17 * j
        plate_x(p, x + 0.001, yy, yy + ww * 0.12, z0 + 0.05 + 0.02 * ((j * 3) % 4), z0 + 0.065 + 0.02 * ((j * 3) % 4),
                "Glow")
    # a ledge with a rubber duck (the debugging duck)
    bbox(p, WALL_OFF, WALL_OFF + 0.12, ww / 2 - 0.20, ww / 2, z0 - 0.02, z0 + 0.0, "Frame")
    duck(p, WALL_OFF + 0.06, ww / 2 - 0.10, z0 + 0.0)


def duck(p, x, y, z, s=1.0):
    p.sphere((x, y, z + 0.035 * s), 0.035 * s, "Hazard", seg=7, rings=4, scale=(1.2, 1.0, 0.9))
    p.sphere((x + 0.03 * s, y, z + 0.075 * s), 0.024 * s, "Hazard", seg=6, rings=3)
    bbox(p, x + 0.048 * s, x + 0.07 * s, y - 0.012 * s, y + 0.012 * s, z + 0.068 * s, z + 0.078 * s, "Fabric")


# --------------------------------------------------------------------------------------
# logistics
# --------------------------------------------------------------------------------------
def barcode(p, x, y, z, w, h, seed=0):
    rng = random.Random(seed)
    yy = y - w / 2
    while yy < y + w / 2 - 0.004:
        bw = rng.choice((0.004, 0.004, 0.008, 0.012))
        if rng.random() < 0.65:
            plate_x(p, x, yy, min(yy + bw, y + w / 2), z - h / 2, z + h / 2, "HullDark")
        yy += bw + 0.004


def inventory(p, w, d, k):
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.10, ZB + 0.62
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "STOCK CHECK", 0.0, z1 - 0.06, fit_h(["STOCK CHECK"], ww - 0.12, 0.036), "Neon", x=x + 0.001)
    ls = ("FOUND: 0", "LOST: 4812", "DRONE ETA: 5 MIN")
    text_lines(p, ls, 0.0, z1 - 0.12, fit_h(ls, ww - 0.14, 0.034), "LightStrip", x=x + 0.001, gap=0.6)
    text(p, "(IT IS ALWAYS 5 MIN)", 0.0, z0 + 0.05, 0.016, "Window", x=x + 0.001)


def barcodes(p, w, d, k):
    """A pallet-label board: three labels with barcodes and one with a joke."""
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.10, ZB + 0.58
    x = board(p, ww, z0, z1, "Hull")
    for j in range(3):
        yc = -ww * 0.28 + ww * 0.28 * j
        plate_x(p, x + 0.001, yc - 0.10, yc + 0.10, z0 + 0.07, z0 + 0.30, ("CushionLight", "Hazard", "Hull")[j])
        barcode(p, x + 0.002, yc, z0 + 0.13, 0.17, 0.09, seed=k * 3 + j)
        text(p, ("BOX 0001", "BOX 0002", "BOX ????")[j], yc, z0 + 0.25, 0.020, "HullDark", x=x + 0.002)
    text(p, "SCAN ME", 0.0, z1 - 0.07, 0.048, "HullDark", x=x + 0.001)
    text(p, "(PLEASE)", 0.0, z1 - 0.13, 0.022, "HullDark", x=x + 0.001)


# --------------------------------------------------------------------------------------
# medical
# --------------------------------------------------------------------------------------
def eyechart(p, w, d, k):
    ww = min(0.54, w - 0.10)
    z0, z1 = ZB + 0.02, ZB + 0.72
    x = board(p, ww, z0, z1, "Hull", frame="HullDark")
    rows = (("E", 0.080), ("F P", 0.062), ("T O Z", 0.050), ("L P E D", 0.040), ("P E C F D", 0.032),
            ("A I E O U", 0.026))
    z = z1 - 0.07
    for s_, hh in rows:
        text(p, s_, 0.0, z, hh, "HullDark", x=x + 0.001)
        z -= hh * 1.45 + 0.012
    text(p, "READ LINE 6", 0.0, z0 + 0.04, 0.016, "HullDark", x=x + 0.001)


def diagnose(p, w, d, k):
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.08, ZB + 0.62
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "AI DIAGNOSIS", 0.0, z1 - 0.06, fit_h(["AI DIAGNOSIS"], ww - 0.12, 0.036), "Neon", x=x + 0.001)
    # an ECG line
    zc = z1 - 0.20
    ys = [-0.38 + 0.76 * t / 12.0 for t in range(13)]
    zs = (0.0, 0.0, 0.0, 0.02, -0.02, 0.0, 0.0, 0.075, -0.05, 0.0, 0.0, 0.02, 0.0)
    polyline(p, x + 0.001, [(ww * ys[t], zc + zs[t]) for t in range(13)], 0.008, "Glow")
    text_lines(p, ("PROBABLY", "NOTHING*"), 0.0, zc - 0.07, 0.044, "LightStrip", x=x + 0.001, gap=0.5)
    text(p, "*SEE A MEDIC", 0.0, z0 + 0.045, 0.016, "Window", x=x + 0.001)


def peer(p, w, d, k):
    ww = min(0.66, w - 0.06)
    z0, z1 = ZB + 0.06, ZB + 0.70
    x = board(p, ww, z0, z1, "Cushion")
    zz = text_lines(p, ("PEER", "REVIEWED"), 0.0, z1 - 0.05, fit_h(("REVIEWED",), ww - 0.10, 0.060), "Hull", x=x + 0.001)
    text(p, "BY A MODEL", 0.0, zz - 0.04, fit_h(["BY A MODEL"], ww - 0.10, 0.040), "Window", x=x + 0.001)
    for j, (yy, zz, m) in enumerate(((-0.14, 0.0, "Glow"), (0.0, 0.02, "WaterBlue"), (0.14, -0.01, "Hazard"))):
        disc_x(p, x + 0.001, yy, z0 + 0.20 + zz, 0.062, "Hull", seg=14)
        disc_x(p, x + 0.002, yy, z0 + 0.20 + zz, 0.048, m, seg=12)
        disc_x(p, x + 0.003, yy + 0.015, z0 + 0.215 + zz, 0.012, "Hull", seg=6)
    text(p, "P < 0.05*", 0.0, z0 + 0.05, 0.022, "Hull", x=x + 0.001)


# --------------------------------------------------------------------------------------
# civic and others
# --------------------------------------------------------------------------------------
def face(p, x, y, z, r):
    """A tiny wanted-poster head: a pale disc, two eyes, a mouth line."""
    disc_x(p, x, y, z, r, "CushionLight", seg=10)
    for s_ in (-1, 1):
        disc_x(p, x + 0.001, y + s_ * r * 0.38, z + r * 0.22, r * 0.12, "HullDark", seg=5)
    plate_x(p, x + 0.001, y - r * 0.40, y + r * 0.40, z - r * 0.42, z - r * 0.34, "HullDark")


def wanted(p, w, d, k):
    ww = min(0.78, w - 0.02)
    z0, z1 = ZB + 0.02, ZB + 0.72
    x = board(p, ww, z0, z1, "Wood")
    names = (("OAT MILK", "THIEF"), ("KETTLE", "BOT"), ("WIFI", "DELETER"))
    for j in range(3):
        yc = -ww * 0.30 + ww * 0.30 * j
        plate_x(p, x + 0.001, yc - 0.105, yc + 0.105, z0 + 0.04, z1 - 0.04, "Hull")
        text(p, "WANTED", yc, z1 - 0.085, 0.034, "SignalRed", x=x + 0.002)
        face(p, x + 0.002, yc, z1 - 0.24, 0.075)
        text_lines(p, names[(j + k) % 3], yc, z1 - 0.33, fit_h(("OAT MILK",), 0.19, 0.028), "HullDark",
                   x=x + 0.002, gap=0.5)
        if j == 0:
            text(p, "REWARD: 1 TOKEN", yc, z0 + 0.075, 0.014, "HullDark", x=x + 0.002)


def tally(p, w, d, k):
    """Tally marks scratched on a wall and a joke (jail)."""
    ww = min(0.74, w - 0.04)
    for g in range(4):
        y0 = -ww / 2 + 0.10 + g * 0.18
        for t in range(4):
            plate_x(p, WALL_OFF, y0 + 0.030 * t, y0 + 0.030 * t + 0.009, ZB + 0.36, ZB + 0.62, "Frame")
        p.quad((WALL_OFF, y0 - 0.014, ZB + 0.375), (WALL_OFF, y0 + 0.012, ZB + 0.365), (WALL_OFF, y0 + 0.118, ZB + 0.605),
               (WALL_OFF, y0 + 0.092, ZB + 0.615), "Frame")
    text(p, "WIFI: LOL", 0.0, ZB + 0.22, 0.050, "Frame", x=WALL_OFF)


def blackboard(p, w, d, k):
    ww = min(0.80, w - 0.02)
    z0, z1 = ZB + 0.04, ZB + 0.70
    x = board(p, ww, z0, z1, "PlantDark", frame="Wood")
    text(p, "PROMPTING 101", 0.0, z1 - 0.07, fit_h(["PROMPTING 101"], ww - 0.12, 0.040), "Hull", x=x + 0.001)
    hbar(p, x + 0.001, -ww / 2 + 0.05, ww / 2 - 0.05, z1 - 0.115, 0.006, "Hull")
    lines = ("1 BE POLITE", "2 SAY PLEASE", "3 SAY IT AGAIN", "4 BLAME THE BOT")
    text_lines(p, lines, -ww * 0.08, z1 - 0.15, fit_h(lines, ww * 0.72, 0.030), "Hull", x=x + 0.001, gap=0.7)
    for j in range(3):                                                    # a chalk flow diagram, bottom right
        yc = ww * 0.12 + ww * 0.12 * j
        plate_x(p, x + 0.001, yc - 0.035, yc + 0.035, z0 + 0.06, z0 + 0.12, "Hull")
        plate_x(p, x + 0.002, yc - 0.03, yc + 0.03, z0 + 0.065, z0 + 0.115, "PlantDark")
    bbox(p, WALL_OFF, WALL_OFF + 0.05, -ww / 2 + 0.05, ww / 2 - 0.05, z0 - 0.012, z0 + 0.008, "Wood")
    bbox(p, WALL_OFF + 0.012, WALL_OFF + 0.04, -ww / 2 + 0.10, -ww / 2 + 0.16, z0 + 0.008, z0 + 0.02, "Hull")


def routesign(p, w, d, k):
    """Direction signs (junction, airlock): two arrows with names."""
    ww = min(0.80, w - 0.02)
    z0 = ZB + 0.30
    pairs = ((("CANTINA", 1), ("NOT THE CANTINA", -1)), (("EXIT", 1), ("OTHER EXIT", -1)), (("YOU ARE HERE", 0),
                                                                                         ("(PROBABLY)", 0)))
    for j, (lab, dr) in enumerate(pairs[k % 3]):
        zz = z0 + 0.22 * (1 - j)
        x = board(p, ww, zz - 0.08, zz + 0.08, "Plant" if j == 0 else "Hazard", d=0.025)
        ink = "Hull" if j == 0 else "HullDark"
        tw = text_width(lab, 0.040)
        sc = min(1.0, (ww - 0.20) / max(0.01, tw))
        text(p, lab, -0.03 * dr, zz, 0.040 * sc, ink, x=x + 0.001)
        if dr:
            ay = dr * (ww / 2 - 0.07)
            p.tri((x + 0.001, ay - dr * 0.035, zz - 0.04), (x + 0.001, ay - dr * 0.035, zz + 0.04),
                  (x + 0.001, ay + dr * 0.025, zz), ink) if dr > 0 else \
                p.tri((x + 0.001, ay - dr * 0.035, zz + 0.04), (x + 0.001, ay - dr * 0.035, zz - 0.04),
                      (x + 0.001, ay + dr * 0.025, zz), ink)


def fryer_station(p, w, d, k):
    """A low cabinet with an air fryer that asks 'ARE YOU STILL THERE?', a blender and a recipe card (0.42 m deep)."""
    ww = min(0.80, w - 0.02)
    dd = 0.42
    h = 0.90
    bbox(p, 0.0, dd, -ww / 2, ww / 2, F, F + h - 0.03, "Hull", bevel=0.015)
    bbox(p, -0.005, dd + 0.02, -ww / 2 - 0.01, ww / 2 + 0.01, F + h - 0.03, F + h, "Wood")
    plate_x(p, dd + 0.004, -ww / 2 + 0.03, ww / 2 - 0.03, F + 0.08, F + h - 0.10, "FloorDark")
    zt = F + h
    # the air fryer: a rounded box with a drawer, a handle and a screen
    yf = -ww * 0.16
    bbox(p, 0.06, 0.34, yf - 0.15, yf + 0.15, zt, zt + 0.32, ("Hull", "Metal", "SecBlack")[k % 3], bevel=0.05)
    plate_x(p, 0.341, yf - 0.12, yf + 0.12, zt + 0.04, zt + 0.17, "HullDark")
    bbox(p, 0.34, 0.37, yf - 0.07, yf + 0.07, zt + 0.10, zt + 0.12, "Frame")
    plate_x(p, 0.341, yf - 0.10, yf + 0.10, zt + 0.21, zt + 0.29, "Screen")
    text(p, "AI CRISP", yf, zt + 0.25, 0.030, "Neon", x=0.342)
    text(p, "STILL THERE?", yf, zt + 0.215, 0.014, "LightStrip", x=0.342)
    # a blender
    yb = ww * 0.20
    bbox(p, 0.12, 0.28, yb - 0.08, yb + 0.08, zt, zt + 0.11, "HullDark", bevel=0.02)
    p.vcyl(0.20, yb, zt + 0.11, zt + 0.40, 0.06, 0.075, seg=8, mat="Glass", cap0=False)
    p.vcyl(0.20, yb, zt + 0.40, zt + 0.43, 0.07, seg=8, mat="Frame")
    disc_x(p, 0.281, yb, zt + 0.05, 0.02, "Glow", seg=6)
    # the recipe card over it (in the flat band)
    zc0 = ZB + 0.55
    plate_x(p, WALL_OFF, ww * 0.02, ww * 0.38, zc0, zc0 + 0.20, "Hull")
    text_lines(p, ("RECIPE:", "1 ADD AI", "2 WAIT", "3 SERVE*"), ww * 0.20, zc0 + 0.19, 0.026, "HullDark", x=WALL_OFF + 0.001,
               gap=0.35)


def jukebox(p, w, d, k):
    """A jukebox: an arch of coloured light over a song list (0.36 m deep)."""
    ww = min(0.70, w - 0.06)
    dd = 0.36
    top = F + 1.12
    bbox(p, 0.0, dd, -ww / 2, ww / 2, F, F + 0.50, "Wood", bevel=0.02)
    plate_x(p, dd + 0.004, -ww / 2 + 0.05, ww / 2 - 0.05, F + 0.08, F + 0.42, "FloorDark")
    bbox(p, 0.0, dd, -ww / 2, ww / 2, F + 0.50, top - 0.18, "Frame", bevel=0.02)
    plate_x(p, dd + 0.004, -ww / 2 + 0.04, ww / 2 - 0.04, F + 0.54, top - 0.22, "HullDark")
    for j in range(5):
        zz = F + 0.58 + 0.065 * j
        plate_x(p, dd + 0.006, -ww / 2 + 0.07, ww / 2 - 0.07, zz, zz + 0.045, "Screen")
        text(p, ("DJ LATENCY", "HALLUCINATIONS", "NEURAL NOISE", "CTRL+Z", "OVERFIT")[(j + k) % 5], 0.0, zz + 0.022,
             0.020, "LightStrip" if j % 2 else "Window", x=dd + 0.008)
    # the glowing top arch (a stepped dome: three boxes) with a neon rim
    for j, (sh, m) in enumerate(((0.0, "Neon"), (0.06, "Window"), (0.12, "L3Band"))):
        bbox(p, 0.02, dd - 0.02, -ww / 2 + sh, ww / 2 - sh, top - 0.18 + 0.06 * j, top - 0.12 + 0.06 * j, m)


def recipe(p, w, d, k):
    """The kitchen's recipe screen."""
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.12, ZB + 0.66
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "TODAY: ALGAE", 0.0, z1 - 0.06, fit_h(["TODAY: ALGAE"], ww - 0.12, 0.040), "Neon", x=x + 0.001)
    ls = (("STEP 1: ADD AI", "STEP 2: STIR", "STEP 3: BLAME BOT"), ("SERVES: 40", "CHEF: THE KETTLE", "SALT: ???"))[k % 2]
    text_lines(p, ls, 0.0, z1 - 0.13, fit_h(ls, ww - 0.14, 0.034), "LightStrip", x=x + 0.001, gap=0.6)
    text(p, "*MAY HALLUCINATE", 0.0, z0 + 0.045, 0.016, "Window", x=x + 0.001)


def stilllabel(p, w, d, k):
    """The distillery's batch label board: a parody spirit label and a tasting-notes card."""
    ww = min(0.76, w - 0.04)
    z0, z1 = ZB + 0.04, ZB + 0.70
    x = board(p, ww, z0, z1, "Wood")
    plate_x(p, x + 0.001, -ww * 0.44, -ww * 0.02, z0 + 0.05, z1 - 0.05, "Hull")
    text(p, "MOONSHINE", -ww * 0.23, z1 - 0.12, fit_h(["MOONSHINE"], ww * 0.40, 0.05), "SignalRed", x=x + 0.002)
    text(p, ".AI", -ww * 0.23, z1 - 0.20, 0.05, "SignalRed", x=x + 0.002)
    disc_x(p, x + 0.002, -ww * 0.23, z1 - 0.34, 0.07, "Copper", seg=12)
    text_lines(p, ("BATCH 0001", "40% MAYBE"), -ww * 0.23, z0 + 0.20, 0.028, "HullDark", x=x + 0.002, gap=0.5)
    plate_x(p, x + 0.001, ww * 0.04, ww * 0.44, z0 + 0.12, z1 - 0.12, "CushionLight")
    text(p, "TASTING NOTES", ww * 0.24, z1 - 0.17, fit_h(["TASTING NOTES"], ww * 0.36, 0.026), "HullDark", x=x + 0.002)
    ls = ("HINTS OF ALGAE", "NOTES OF DUST", "FINISH: LATE", "SERVE: WARM")
    text_lines(p, ls, ww * 0.24, z1 - 0.23, fit_h(ls, ww * 0.36, 0.024), "HullDark", x=x + 0.002, gap=0.55)


def suitcheck(p, w, d, k):
    """The airlock's suit check screen."""
    ww = min(0.72, w - 0.04)
    z0, z1 = ZB + 0.12, ZB + 0.66
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "SUIT CHECK", 0.0, z1 - 0.06, fit_h(["SUIT CHECK"], ww - 0.12, 0.036), "Neon", x=x + 0.001)
    ls = (("SIZE: ONE", "FITS: NO ONE", "SEAL: PROBABLY"), ("O2 LEFT: SOME", "HELMET: ON?", "HAVE A NICE DAY"))[k % 2]
    text_lines(p, ls, 0.0, z1 - 0.12, fit_h(ls, ww - 0.14, 0.036), "LightStrip", x=x + 0.001, gap=0.6)
    disc_x(p, x + 0.001, ww / 2 - 0.07, z0 + 0.06, 0.018, "Glow", seg=8)
    text(p, "*NOT A WARRANTY", 0.0, z0 + 0.045, 0.014, "Window", x=x + 0.001)


def photos(p, w, d, k):
    """A row of three framed pictures (a family wall): hills and a sun, a smiling robot, a child's house."""
    ww = min(0.80, w - 0.02)
    rng = random.Random(k * 11 + 2)
    sc = ww / 0.80
    specs = ((-0.27 * sc, ZB + 0.40, 0.22 * sc, 0.32 * sc), (0.0, ZB + 0.36, 0.28 * sc, 0.22 * sc),
             (0.27 * sc, ZB + 0.41, 0.22 * sc, 0.30 * sc))          # 2026-10-02: larger, they read in the follow view
    bgs = ("WaterBlue", "Hazard", "Plant", "Fabric", "CushionLight", "Cushion")
    for j, (yc, zc, pw, ph) in enumerate(specs):
        x = board(p, pw, zc - ph / 2, zc + ph / 2, bgs[(rng.randrange(len(bgs)) + j) % len(bgs)],
                  frame=("Wood", "Frame", "Hull")[(j + k) % 3], d=0.02)
        kind = (j + k) % 3
        if kind == 0:                                        # a sun over hills
            disc_x(p, x + 0.001, yc + pw * 0.15, zc + ph * 0.18, ph * 0.12, "Window", seg=8)
            p.tri((x + 0.001, yc - pw * 0.40, zc - ph * 0.38), (x + 0.001, yc + pw * 0.05, zc - ph * 0.38),
                  (x + 0.001, yc - pw * 0.18, zc + ph * 0.02), "PlantDark")
            p.tri((x + 0.001, yc - pw * 0.10, zc - ph * 0.38), (x + 0.001, yc + pw * 0.40, zc - ph * 0.38),
                  (x + 0.001, yc + pw * 0.15, zc - ph * 0.08), "PlantDark")
        elif kind == 1:                                      # a smiling robot
            plate_x(p, x + 0.001, yc - pw * 0.22, yc + pw * 0.22, zc - ph * 0.28, zc + ph * 0.24, "Hull")
            for s_ in (-1, 1):
                disc_x(p, x + 0.002, yc + s_ * pw * 0.10, zc + ph * 0.06, ph * 0.05, "Screen", seg=6)
            plate_x(p, x + 0.002, yc - pw * 0.12, yc + pw * 0.12, zc - ph * 0.14, zc - ph * 0.10, "Screen")
        else:                                                # a kid's drawing: a house
            plate_x(p, x + 0.001, yc - pw * 0.24, yc + pw * 0.24, zc - ph * 0.34, zc + ph * 0.06, "Fabric")
            p.tri((x + 0.001, yc - pw * 0.30, zc + ph * 0.06), (x + 0.001, yc + pw * 0.30, zc + ph * 0.06),
                  (x + 0.001, yc, zc + ph * 0.34), "HullDark")
            plate_x(p, x + 0.002, yc - pw * 0.06, yc + pw * 0.06, zc - ph * 0.34, zc - ph * 0.10, "Hazard")


def shopsign(p, w, d, k):
    ww = min(0.80, w - 0.02)
    sets = (("GIZMODROME", "Neon"), ("SMART SOCKS 9", "Window"), ("50% OFF*", "SignalRedGlow"),
            ("AI-FREE AISLE**", "Glow"), ("BUY NOW PAY LATER", "L3Band"))
    txt, m = sets[k % len(sets)]
    h = fit_h([txt], ww - 0.10, 0.075)
    zc = ZB + 0.46
    W = text_width(txt, h)
    bbox(p, WALL_OFF, WALL_OFF + 0.03, -W / 2 - 0.05, W / 2 + 0.05, zc - h / 2 - 0.05, zc + h / 2 + 0.05, "Frame")
    plate_x(p, WALL_OFF + 0.031, -W / 2 - 0.04, W / 2 + 0.04, zc - h / 2 - 0.04, zc + h / 2 + 0.04, "HullDark")
    text(p, txt, 0.0, zc, h, m, x=WALL_OFF + 0.033)
    if "*" in txt:
        text(p, "*TERMS APPLY", 0.0, zc - h / 2 - 0.085, 0.016, "HullDark", x=WALL_OFF + 0.002)


def synergy(p, w, d, k):
    """The HR office's 'SYNERGY' poster: three overlapping circles (an original design) over a slogan."""
    ww = min(0.66, w - 0.06)
    z0, z1 = ZB + 0.04, ZB + 0.70
    x = board(p, ww, z0, z1, ("Cushion", "PlantDark", "Accent")[k % 3])
    for j, (dy, dz, m) in enumerate(((-0.08, 0.04, "Fabric"), (0.08, 0.04, "WaterBlue"), (0.0, -0.08, "Hazard"))):
        disc_x(p, x + 0.001 + 0.001 * j, dy, z1 - 0.26 + dz, 0.12, m, seg=14)
    text(p, "SYNERGY", 0.0, z0 + 0.17, fit_h(["SYNERGY"], ww - 0.10, 0.075), "Hull", x=x + 0.004)
    text(p, ("TOGETHER WE ALIGN", "CIRCLE BACK. ALWAYS.", "1 TEAM 1 DREAM 0 BUDGET")[k % 3], 0.0, z0 + 0.07, 0.018,
         "Hull", x=x + 0.004)


def feelings(p, w, d, k):
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.10, ZB + 0.62
    x = board(p, ww, z0, z1, "CushionLight")
    lines = ("YOUR FEELINGS", "ARE VALID")
    zz = text_lines(p, lines, 0.0, z1 - 0.05, fit_h(lines, ww - 0.10, 0.060), "HullDark", x=x + 0.001)
    text(p, "(PENDING REVIEW)", 0.0, zz - 0.07, fit_h(["(PENDING REVIEW)"], ww - 0.12, 0.034), "SignalRed", x=x + 0.001)


def survey(p, w, d, k):
    ww = min(0.74, w - 0.04)
    z0, z1 = ZB + 0.10, ZB + 0.62
    x = board(p, ww, z0, z1, "Screen", d=0.04)
    text(p, "STAFF SURVEY", 0.0, z1 - 0.06, fit_h(["STAFF SURVEY"], ww - 0.12, 0.036), "Neon", x=x + 0.001)
    ls = ("MORALE: 104%", "COMPLAINTS: 0*", "VIBES: ALIGNED")
    text_lines(p, ls, 0.0, z1 - 0.13, fit_h(ls, ww - 0.14, 0.036), "LightStrip", x=x + 0.001, gap=0.6)
    text(p, "*FILTERED", 0.0, z0 + 0.045, 0.016, "Window", x=x + 0.001)


def motto(txt, mat="Neon"):
    """A room motto as a neon sign (every room type has one in the table below)."""
    def fn(p, w, d, k):
        ww = min(0.80, w - 0.02)
        lines = txt.split("/")
        h = fit_h(lines, ww - 0.10, 0.075 if len(lines) == 1 else 0.060)
        zt = ZB + 0.30 + (0.0 if len(lines) == 1 else 0.10)
        for dz in (-0.04, 0.04 + (0.0 if len(lines) == 1 else h * 1.7)):
            bbox(p, WALL_OFF, WALL_OFF + 0.02, -ww / 2 + 0.04, ww / 2 - 0.04, zt + dz - 0.005, zt + dz + 0.005, "Frame")
        text_lines(p, lines, 0.0, zt + 0.05 + (0.0 if len(lines) == 1 else h * 1.9), h, mat, x=WALL_OFF + 0.025,
                   gap=0.45)
    return fn


# --------------------------------------------------------------------------------------
# the table: wall kinds, depths, roles
# --------------------------------------------------------------------------------------
KINDS = {
    "r_safety": safety, "r_foreman": foreman, "r_rota": rota, "r_hats": hats, "r_gauges": gauges,
    "r_extinguisher": extinguisher, "r_agi": agi_board, "r_vending": vending, "r_clock": clock,
    "r_whiteboard": whiteboard, "r_seedrack": seedrack, "r_plantboard": plantboard, "r_air": airboard,
    "r_inventory": inventory, "r_barcodes": barcodes, "r_eyechart": eyechart, "r_diagnose": diagnose,
    "r_peer": peer, "r_wanted": wanted, "r_tally": tally, "r_blackboard": blackboard, "r_route": routesign,
    "r_photos": photos, "r_shop": shopsign, "r_suitcheck": suitcheck, "r_stilllabel": stilllabel, "r_fryer": fryer_station, "r_jukebox": jukebox,
    "r_recipe": recipe, "r_synergy": synergy, "r_feelings": feelings, "r_survey": survey,
}
DEPTHS = {k: 0.08 for k in KINDS}
DEPTHS.update({"r_fryer": 0.42, "r_jukebox": 0.36, "r_hats": 0.17, "r_gauges": 0.10, "r_extinguisher": 0.20, "r_vending": 0.42, "r_seedrack": 0.28,
               "r_clock": 0.10, "r_whiteboard": 0.10})
SATIRE = {"r_floormark", "r_stilllabel", "r_chamber", "r_motto", "r_suitcheck", "r_fryer", "r_jukebox", "r_recipe", "r_foreman", "r_agi", "r_safety", "r_vending", "r_plantboard", "r_diagnose", "r_peer", "r_blackboard",
          "r_whiteboard", "r_inventory", "r_clock", "r_wanted", "r_tally", "r_shop", "r_hats", "r_extinguisher",
          "r_air", "r_barcodes", "r_route", "r_seedrack", "r_rota", "r_photos", "r_synergy", "r_feelings", "r_survey"}

MOTTOS = {
    "habitat": "HOME SWEET/POD", "lounge": "CHILL.EXE", "cantina": "NO AGENTS", "kitchen": "TASTE/THE FUTURE*",
    "research_lab": "PUBLISH/OR PERISH", "research_assembler": "ROBOTS BUILD/ROBOTS",
    "greenhouse": "GROW UP", "fungus_farm": "FUN GUY/ZONE", "algae_bioreactor": "ALGAE:/THE FUTURE SOUP",
    "oxygen_plant": "BREATHE EASY", "water_recycler": "DRINK UP/(AGAIN)", "atmo_processor": "WEATHER/OR NOT",
    "storehouse": "FIND IT./MAYBE.", "cold_storage": "COOL/STORAGE",
    "medical": "WASH. SEAL./REPEAT.", "bio_lab": "SAMPLE/RESPONSIBLY",
    "mine": "DIG DEEPER", "refinery": "CRACK ON", "polymer_plant": "POLYMER/PRESSURE", "workshop": "FIX IT/YOURSELF",
    "glassworks": "MIND THE/GLASS", "electronics_fab": "NOW WITH/MORE AI", "fabricator": "PRINT/ANYTHING*",
    "steel_mill": "STEEL/YOURSELF", "titanium_smelter": "TITANIUM:/BORING NAME", "ceramics_kiln": "KILN IT",
    "carbon_works": "CARBON/NEUTRAL*", "battery_plant": "CHARGED UP", "parts_works": "SOME ASSEMBLY/REQUIRED",
    "magnet_works": "ATTRACTIVE/OFFERS", "superconductor_lab": "ZERO/RESISTANCE",
    "metamaterial_foundry": "BENDS LIGHT/AND RULES", "distillery": "SPIRITS UP",
    "airlock": "SUIT UP", "junction": "YOU ARE HERE/(PROBABLY)",
    "residence_tube": "HOME IS WHERE/THE WIFI IS", "apartment_block": "NOW WITH/BALCONIES",
    "retail": "BUY MORE", "park": "TOUCH GRASS", "academy": "LEARN/FASTER", "security_office": "WATCHING/(POLITELY)",
    "jail": "TIME OUT", "hr_office": "WE ARE/LISTENING*",
}

# role -> wall kinds in the order they are placed (the motto first, then these round-robin)
ROLE_KINDS = {
    "industry": ["r_safety", "r_foreman", "r_hats", "r_gauges", "r_agi", "r_rota", "r_extinguisher", "r_vending",
                 "r_whiteboard", "r_clock", "vibeposter"],
    "farm": ["r_plantboard", "r_agi", "r_seedrack", "vibeposter", "r_whiteboard", "r_air", "r_extinguisher"],
    "distillery": ["r_stilllabel", "r_safety", "r_agi", "r_gauges", "r_hats", "r_foreman", "r_extinguisher", "r_vending",
                   "r_whiteboard", "r_clock", "vibeposter"],
    "kitchen": ["r_recipe", "r_fryer", "r_agi", "vibeposter", "r_whiteboard", "r_vending", "r_extinguisher"],
    "bar": ["r_jukebox", "r_agi", "vibeposter", "r_vending", "r_photos"],
    "life": ["r_air", "r_gauges", "r_safety", "r_agi", "r_foreman", "r_extinguisher", "r_whiteboard"],
    "logistics": ["r_inventory", "r_barcodes", "r_safety", "r_agi", "r_hats", "r_vending", "r_clock", "r_foreman"],
    "medical": ["r_diagnose", "r_eyechart", "r_peer", "r_agi", "r_whiteboard", "r_vending", "r_extinguisher"],
    "science": ["r_peer", "r_whiteboard", "r_agi", "r_foreman", "r_vending", "r_diagnose", "r_extinguisher"],
    "links": ["r_route", "r_agi", "r_safety", "r_extinguisher"],
    "civic": ["r_agi", "r_whiteboard", "r_blackboard", "r_wanted", "r_clock", "r_vending", "r_photos"],
    "housing": ["r_photos", "vibeposter", "r_agi", "r_fryer", "r_whiteboard"],
    "retail": ["r_shop", "r_shop", "r_agi", "r_vending", "r_shop", "r_clock"],
    "academy": ["r_blackboard", "r_agi", "r_whiteboard", "r_peer", "r_clock", "r_vending", "r_blackboard"],
    "security": ["r_wanted", "r_agi", "r_whiteboard", "r_clock", "r_vending", "r_extinguisher"],
    "jail": ["r_tally", "r_wanted", "r_agi", "r_clock", "r_tally"],
    "park": ["r_agi", "r_plantboard", "r_photos"],
    "comfort": ["r_agi", "r_jukebox", "r_vending", "vibeposter", "r_photos", "r_whiteboard"],
    "hr": ["r_synergy", "r_feelings", "r_survey", "r_agi", "r_whiteboard", "r_clock", "r_photos"],
}
ROLE_OF = {}
for _t in ("mine", "refinery", "polymer_plant", "workshop", "glassworks", "electronics_fab", "fabricator", "steel_mill",
           "titanium_smelter", "ceramics_kiln", "carbon_works", "battery_plant", "parts_works", "magnet_works",
           "superconductor_lab", "metamaterial_foundry", "distillery"):
    ROLE_OF[_t] = "industry"
for _t in ("greenhouse", "fungus_farm", "algae_bioreactor"):
    ROLE_OF[_t] = "farm"
ROLE_OF["kitchen"] = "kitchen"
ROLE_OF["distillery"] = "distillery"
ROLE_OF["cantina"] = "bar"
for _t in ("oxygen_plant", "water_recycler", "atmo_processor"):
    ROLE_OF[_t] = "life"
for _t in ("storehouse", "cold_storage"):
    ROLE_OF[_t] = "logistics"
for _t in ("medical", "bio_lab"):
    ROLE_OF[_t] = "medical"
for _t in ("research_lab", "research_assembler"):
    ROLE_OF[_t] = "science"
for _t in ("airlock", "junction"):
    ROLE_OF[_t] = "links"
for _t in ("habitat", "residence_tube", "apartment_block"):
    ROLE_OF[_t] = "housing"
for _t, _r in (("retail", "retail"), ("academy", "academy"), ("security_office", "security"), ("jail", "jail"),
               ("park", "park"), ("lounge", "comfort"), ("hr_office", "hr")):
    ROLE_OF[_t] = _r
FILLER = ("vent", "cable", "panel", "poster", "plant", "notice", None)
CAPS = {"r_agi": 1, "r_vending": 1, "r_extinguisher": 1, "r_clock": 1, "r_motto": 1, "r_fryer": 1, "r_jukebox": 1,
        "r_suitcheck": 1}      # in-jokes and machines appear once per room, the rest at most twice

# painted floor texts on the walking ring, by role (three per room, two in S): the lane markings of a colony run by bots
FLOOR_TEXTS = {
    "industry": ("MIND THE GAP", "LANE 3: HUMANS", "AI-FREE ZONE*", "NO RUNNING", "ROBOTS HAVE RIGHT OF WAY"),
    "logistics": ("PALLETS ONLY", "LOST ZONE", "WALK HERE", "FORKLIFT: ALSO WALK HERE"),
    "life": ("BREATHE HERE", "MIND THE PIPES", "KEEP CLEAR", "EXHALE THIS WAY"),
    "farm": ("WATCH YOUR STEP", "DEBBIE LIVES HERE", "NO TASTING", "ROOT ZONE"),
    "kitchen": ("WET FLOOR (PROBABLY)", "HOT PASS", "KEEP CLEAR", "SOUP LANE"),
    "medical": ("WAIT HERE", "KEEP CLEAR", "FOLLOW THE LINE", "ALL LINES LEAD TO THE MEDIC"),
    "science": ("MIND THE CABLES", "PEER REVIEW LANE", "KEEP CLEAR", "DO NOT TOUCH THE MODEL"),
    "links": ("MIND THE GAP", "SEAL BEFORE SUIT", "KEEP CLEAR"),
    "civic": ("PLEASE QUEUE", "KEEP CLEAR", "THIS WAY"),
    "housing": ("WELCOME HOME", "SHOES OFF*", "QUIET HOURS 22:00"),
    "bar": ("LAST ORDERS: NEVER", "MIND THE STOOLS", "THIS WAY"),
    "comfort": ("CHILL HERE", "PLEASE QUEUE", "THIS WAY"),
}
QUOTA = (4, 7, 10, 13)         # role wall pieces per room by size S M L XL (the motto not counted)
KIND_CAP = (1, 1, 1, 2)        # how often one kind may stand in a room, by size
HEAVY = {"r_wanted", "r_plantboard", "r_stilllabel", "r_vending", "r_seedrack", "r_whiteboard"}      # 600+ triangles: not in S


def floor_marks(plan):
    """Painted floor texts on the walking ring (called from interior_rooms.finish)."""
    from math import sqrt
    rm = plan.rm
    role = ROLE_OF.get(tid_of(rm))
    texts = FLOOR_TEXTS.get(role if role != "distillery" else "industry")
    if not texts or getattr(rm, "keep_door", False) and rm.R < 3.0:
        return 0
    rng = random.Random(sum(ord(c_) for c_ in tid_of(rm)) % 9973 + (getattr(rm, "size", 1) or 0))
    n = 2 if (getattr(rm, "size", 1) or 0) == 0 else 3
    rr = 0.5 * (plan.wall_front + plan.r_max)
    a0 = rng.uniform(0.0, 120.0)
    dark = role in ("industry", "logistics", "life", "distillery", "links")
    placed = 0
    for j in range(n):
        a = a0 + 120.0 * j + rng.uniform(-12.0, 12.0)
        x, y = rr * cos(radians(a)), rr * sin(radians(a))
        if plan.dist(x, y) < 0.35:
            continue
        txt = texts[(j + rng.randrange(len(texts))) % len(texts)]
        h = 0.10
        PR.floor_text(plan.n, txt, x, y, a + 180.0, h, "Hazard" if dark else "HullDark")
        PR.USED["r_floormark"] = PR.USED.get("r_floormark", 0) + 1
        placed += 1
    return placed


def tid_of(rm):
    t = getattr(rm, "tid", "")
    return t


def role_for(rm):
    return ROLE_OF.get(tid_of(rm))


def builders(rm):
    """Wall kinds this room adds to its builders: the role kinds and its own motto sign."""
    out = dict(KINDS)
    mt = MOTTOS.get(tid_of(rm))
    if mt:
        out["r_motto"] = motto(mt)
    return out


def depths():
    d = dict(DEPTHS)
    d["r_motto"] = 0.08
    return d


class Enricher:
    """Picks the role piece that replaces a filler wall kind: the motto first, then the role's list (its first kind,
    the signature piece, first; the rest from an offset that depends on the room type, so two industry rooms do not
    show the same set).  Size rules (ART-HAB 2026-10-02, triangle and pck budget): at most QUOTA[size] role pieces,
    spread evenly round the 32 wall slots, each kind at most KIND_CAP[size] times (CAPS: once)."""

    def __init__(self, rm, seed):
        self.rm = rm
        self.role = role_for(rm)
        self.size = min(3, getattr(rm, "size", 1) or 0)
        self.count = 0
        self.used = {}
        self.motto_done = tid_of(rm) not in MOTTOS
        self.show = [s for s in os.environ.get("FH_ROLE_SHOW", "").split(",") if s]      # showcase builds
        lst = ROLE_KINDS.get(self.role) or []
        off = sum(ord(c_) for c_ in tid_of(rm)) % max(1, len(lst) - 1)
        self.order = lst[:1] + (lst[1:][off:] + lst[1:][:off])
        self.j = 0

    def pick(self, kind, k):
        if self.show:
            self.j += 1
            return self.show[(self.j - 1) % len(self.show)]
        if self.role is None or kind not in FILLER:
            return kind
        if not self.motto_done:
            self.motto_done = True
            return "r_motto"
        if self.count >= QUOTA[self.size] * (k + 1) / 32.0:
            return kind                      # spread the pieces round the room
        for _ in range(len(self.order)):
            c = self.order[self.j % len(self.order)]
            self.j += 1
            if self.used.get(c, 0) < CAPS.get(c, KIND_CAP[self.size]) and not (self.size == 0 and c in HEAVY):
                self.used[c] = self.used.get(c, 0) + 1
                self.count += 1
                return c
        return kind
