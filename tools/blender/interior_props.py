"""Frontier Habitat 5.0 shared interior prop kit (V5_DESIGN 15.3, Paul 2026-10-01: "highly detailed, pop culture
references and some grounding in 2026 ... ridiculous to highlight the crazy AI boom").

Everything is geometry with the existing materials (no textures: one texture per GLB would be copied into every
file of the pck).  Text is a 5 x 7 pixel font built from quads (one quad per horizontal run of pixels), so a
poster headline costs about 20 triangles per letter.  All names, slogans and art are ORIGINAL parodies: no real
logos, brands, characters or lyrics.

Frames: every builder works in the current frame of Part p.  Wall pieces stand on the plane x = 0 (the wall) and
face +X (into the room); text reads along +Y.  Free-standing props stand on z = F with their front to +X.

Kit:
  text / text_lines            pixel-font text on a plane facing +X
  poster(kind)                 'ai' motivational posters, 'film' parody films, 'band' gig posters, 'notice'
  screen_content(kind)         chat bubbles, loss curve, bar chart, code; text screens
  desk_clutter                 mug or mega tumbler, sticky notes, phone, a tiny plant or a figurine
  desk_plate                   "PROMPT ENGINEER" and other job plates
  kettle_bot, sub_toaster      a kettle with a chatbot screen; a toaster that asks for a subscription
  sourdough, oat_carton        2026 kitchen grounding
  gpu_shrine                   a graphics card on an altar with candles and offerings ("PRAY FOR VRAM")
  neon_text                    an emissive sign on a back rail
  agents_screen                a booking screen where two agents argue about a meeting room
  wall kinds (WALL_KINDS)      ready-made wall_set builders: aiposter, filmposter, notice, kettle, shrine,
                               agents, neon_<text>, menu
"""
import random
from math import sin, cos, radians, pi

from rooms_kit import T, RX, RY, RZ, S
from interior_kit import F, bbox, plate_x, plate_z

# --------------------------------------------------------------------------------------
# 5 x 7 pixel font
# --------------------------------------------------------------------------------------
_G = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11100", "10010", "10001", "10001", "10001", "10010", "11100"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "10001", "11001", "10101", "10011", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
    ",": ("00000", "00000", "00000", "00000", "01100", "00100", "01000"),
    "!": ("00100", "00100", "00100", "00100", "00100", "00000", "00100"),
    "?": ("01110", "10001", "00001", "00010", "00100", "00000", "00100"),
    ":": ("00000", "01100", "01100", "00000", "01100", "01100", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "+": ("00000", "00100", "00100", "11111", "00100", "00100", "00000"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000"),
    "'": ("00100", "00100", "01000", "00000", "00000", "00000", "00000"),
    "%": ("11001", "11010", "00010", "00100", "01000", "01011", "10011"),
    "&": ("01100", "10010", "10100", "01000", "10101", "10010", "01101"),
    "$": ("00100", "01111", "10100", "01110", "00101", "11110", "00100"),
    "#": ("01010", "01010", "11111", "01010", "11111", "01010", "01010"),
    "(": ("00010", "00100", "01000", "01000", "01000", "00100", "00010"),
    ")": ("01000", "00100", "00010", "00010", "00010", "00100", "01000"),
    "=": ("00000", "00000", "11111", "00000", "11111", "00000", "00000"),
    ">": ("01000", "00100", "00010", "00001", "00010", "00100", "01000"),
    "<": ("00010", "00100", "01000", "10000", "01000", "00100", "00010"),
    "*": ("00000", "00100", "10101", "01110", "10101", "00100", "00000"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    " ": ("00000",) * 7,
}


def text_width(s, h):
    px = h / 7.0
    return max(0.0, (6 * len(s) - 1) * px)


def text(p, s, yc, zc, h, mat, x=0.0, align="c"):
    """Pixel text on the plane x (facing +X), reading along +Y; (yc, zc) = the centre (align 'c'), the left end
    ('l') or the right end ('r') of the line; h = cap height."""
    s = s.upper()
    px = h / 7.0
    W = text_width(s, h)
    y0 = yc - W / 2 if align == "c" else (yc if align == "l" else yc - W)
    z0 = zc + h / 2
    for i, ch in enumerate(s):
        gy = y0 + 6 * px * i
        for (c0, c1, r0, r1) in _rects(ch):
            plate_x(p, x, gy + px * c0, gy + px * c1, z0 - px * r1, z0 - px * r0, mat)
    return W


_RECTS = {}


def _rects(ch):
    """The glyph as rectangles (c0, c1, r0, r1): horizontal runs, merged downward while the next row has the same
    run (about 35 % fewer quads than one quad per run)."""
    if ch in _RECTS:
        return _RECTS[ch]
    g = _G.get(ch, _G["?"])
    runs = []
    for r, row in enumerate(g):
        c = 0
        while c < 5:
            if row[c] == "1":
                c1 = c
                while c1 + 1 < 5 and row[c1 + 1] == "1":
                    c1 += 1
                runs.append((r, c, c1 + 1))
                c = c1 + 1
            else:
                c += 1
    used = set()
    out = []
    for (r, c0, c1) in runs:
        if (r, c0, c1) in used:
            continue
        r1 = r + 1
        while (r1, c0, c1) in runs and (r1, c0, c1) not in used:
            used.add((r1, c0, c1))
            r1 += 1
        out.append((c0, c1, r, r1))
    _RECTS[ch] = out
    return out


def text_lines(p, lines, yc, ztop, h, mat, x=0.0, gap=0.45, align="c"):
    """Several lines from ztop down; returns the z under the last line."""
    z = ztop - h / 2
    for ln in lines:
        text(p, ln, yc, z, h, mat, x=x, align=align)
        z -= h * (1.0 + gap)
    return z + h / 2


def fit_h(lines, w, h_max):
    """The largest cap height <= h_max at which every line fits the width w."""
    n = max(len(l) for l in lines) if lines else 1
    return min(h_max, w / max(1.0, (6 * n - 1) / 7.0))


# --------------------------------------------------------------------------------------
# posters (wall pieces, x = 0 at the wall)
# --------------------------------------------------------------------------------------
AI_SLOGANS = (("TRUST", "THE MODEL"), ("PROMPT", "HARDER"), ("AGI", "NEXT WEEK"), ("BE THE", "AGENT"),
              ("SYNERGY", ".EXE"), ("TOKENS", "ARE LOVE"), ("HUMANS", "WELCOME*"), ("ASK THE", "KETTLE"),
              ("FAIL", "FASTER"), ("100%", "AI-FREE*"), ("DREAM", "IN VECTORS"), ("SHIP IT", "ANYWAY"))
FILMS = (("REVENGE OF", "THE CHATBOT"), ("SPACE", "TACOS III"), ("THE LAST", "PROMPT"), ("GRAVITY", "OPTIONAL"),
         ("MARS OR", "BUST 2"), ("ATTACK OF", "THE TOASTERS"), ("NIGHT OF", "THE GPU"), ("LOVE IN", "LOW ORBIT"))
BANDS = (("THE", "HALLUCINATIONS"), ("DJ", "LATENCY"), ("NEURAL", "NOISE"), ("OVERFIT", "LIVE"),
         ("THE DUST", "DEVILS"), ("CTRL+Z", "TOUR"))
NOTICES = (("WIFI PW:", "PROMPT123"), ("LOST: MY", "API KEY"), ("SOURDOUGH", "CLUB TUE"), ("NO DRONES", "IN HALL"),
           ("PICKLEBALL", "8PM DECK 2"), ("KETTLE IS", "SULKING"))
POSTER_BG = ("Accent", "Cushion", "Fabric", "CushionLight", "HullDark", "Wood", "PlantDark", "Hull")


def _sparkle(p, x, yc, zc, r, mat):
    """The 4-point 'AI sparkle' (an original star), facing +X."""
    pts = []
    for k in range(8):
        a = radians(90.0 + 45.0 * k)
        rr = r if k % 2 == 0 else r * 0.28
        pts.append((yc + rr * cos(a), zc + rr * sin(a)))
    ids = [p.v((x, y, z)) for (y, z) in pts]
    c = p.v((x, yc, zc))
    for k in range(8):
        p.f([c, ids[k], ids[(k + 1) % 8]], mat)


WALL_OFF = 0.035      # the wall panel stands proud of the slot plane by up to 3 cm: wall pieces start in front of it


def poster(p, w=0.70, kind="ai", seed=0, z0=None, hh=0.62, off=WALL_OFF):
    """A framed poster on the wall: background, a picture made of shapes, a two-line headline."""
    with p.at(T(off, 0.0, 0.0)):
        _poster(p, w, kind, seed, z0, hh)


def _poster(p, w, kind, seed, z0, hh):
    rng = random.Random(seed * 7 + len(kind))
    ww = min(0.56, w - 0.12)
    z0 = F + 0.66 if z0 is None else z0
    z1 = min(z0 + hh, F + 1.24)
    bbox(p, 0.0, 0.025, -ww / 2, ww / 2, z0, z1, "Frame")
    bg = POSTER_BG[(seed + {"ai": 0, "film": 3, "band": 5, "notice": 1}.get(kind, 0)) % len(POSTER_BG)]
    if kind == "notice":
        bg = "Wood"
    x = 0.027
    plate_x(p, x, -ww / 2 + 0.02, ww / 2 - 0.02, z0 + 0.02, z1 - 0.02, bg)
    ink = "Hull" if bg in ("Accent", "Cushion", "Fabric", "HullDark", "PlantDark", "Wood") else "HullDark"
    x2 = x + 0.002
    H = z1 - z0
    if kind == "ai":
        lines = AI_SLOGANS[seed % len(AI_SLOGANS)]
        _sparkle(p, x2, 0.0, z0 + H * 0.68, H * 0.16, "LightStrip" if seed % 2 else "Neon")
        h = fit_h(lines, ww - 0.08, 0.050)
        text_lines(p, lines, 0.0, z0 + H * 0.42, h, ink, x=x2 + 0.001)
        if lines[-1].endswith("*"):
            text(p, "*BETA", 0.0, z0 + 0.045, 0.014, ink, x=x2 + 0.001)
    elif kind == "film":
        lines = FILMS[seed % len(FILMS)]
        # a planet, a ship streak, a horizon
        with p.at(T(x2, ww * 0.12, z0 + H * 0.66), RY(90.0)):
            p.cap_disc(H * 0.15, 0.0, ("Hazard", "Glow", "WaterBlue", "Fabric")[seed % 4], seg=14)
        plate_x(p, x2, -ww / 2 + 0.03, ww / 2 - 0.03, z0 + H * 0.46, z0 + H * 0.475, "Window")
        bbox(p, x2 - 0.001, x2 + 0.004, -ww * 0.30, -ww * 0.05, z0 + H * 0.74, z0 + H * 0.76, "LightStrip")
        h = fit_h(lines, ww - 0.08, 0.042)
        text_lines(p, lines, 0.0, z0 + H * 0.38, h, "Hazard" if bg != "Hazard" else "Hull", x=x2 + 0.001)
    elif kind == "band":
        lines = BANDS[seed % len(BANDS)]
        for j in range(5):                       # sound bars
            hb = H * (0.10 + 0.22 * ((j * 37 + seed * 11) % 7) / 7.0)
            yy = -ww * 0.30 + ww * 0.15 * j
            plate_x(p, x2, yy - ww * 0.05, yy + ww * 0.05, z0 + H * 0.52, z0 + H * 0.52 + hb, "Neon")
        h = fit_h(lines, ww - 0.08, 0.044)
        text_lines(p, lines, 0.0, z0 + H * 0.40, h, ink, x=x2 + 0.001)
        text(p, "LIVE ON PHOBOS", 0.0, z0 + 0.05, 0.016, ink, x=x2 + 0.001)
    else:                                         # notice board: pinned notes, one with text
        for j in range(4):
            yy = -ww * 0.28 + ww * 0.19 * j + rng.uniform(-0.02, 0.02)
            zz = z0 + H * (0.62 if j % 2 else 0.70) + rng.uniform(-0.03, 0.03)
            plate_x(p, x2, yy - 0.05, yy + 0.05, zz - 0.05, zz + 0.05, ("Hull", "Hazard", "CushionLight", "Glow")[j])
            bbox(p, x2, x2 + 0.008, yy - 0.006, yy + 0.006, zz + 0.035, zz + 0.047, "Fabric")
        lines = NOTICES[seed % len(NOTICES)]
        plate_x(p, x2, -ww * 0.42, ww * 0.42, z0 + 0.05, z0 + H * 0.46, "Hull")
        h = fit_h(lines, ww * 0.80, 0.034)
        text_lines(p, lines, 0.0, z0 + H * 0.40, h, "HullDark", x=x2 + 0.002)


# --------------------------------------------------------------------------------------
# screens
# --------------------------------------------------------------------------------------
def screen_content(p, w, h, kind=0, x=0.0, yc=0.0, zc=0.0):
    """UI drawn on a screen face (plane x, facing +X), centred (yc, zc), w x h.  kind: 0 chat bubbles, 1 a falling
    loss curve, 2 a bar chart, 3 code lines."""
    kind %= 4
    if kind == 0:
        for j in range(4):
            left = j % 2 == 0
            L = w * (0.55 if left else 0.40) * (1.0 - 0.15 * (j % 3))
            z = zc + h * (0.30 - 0.20 * j)
            y0 = yc - w * 0.42 if left else yc + w * 0.42 - L
            plate_x(p, x, y0, y0 + L, z - h * 0.07, z + h * 0.07, "LightStrip" if left else "Neon")
    elif kind == 1:
        n = 9
        for j in range(n):
            t = j / (n - 1)
            zz = zc + h * (0.30 - 0.55 * (1.0 - (1.0 - t) ** 3)) + (h * 0.04 if j % 3 == 1 else 0.0)
            y = yc - w * 0.42 + w * 0.84 * t
            plate_x(p, x, y - w * 0.04, y + w * 0.04, zz - h * 0.025, zz + h * 0.025, "LightStrip")
        plate_x(p, x, yc - w * 0.44, yc - w * 0.42, zc - h * 0.38, zc + h * 0.38, "LightStrip")
        plate_x(p, x, yc - w * 0.44, yc + w * 0.44, zc - h * 0.38, zc - h * 0.35, "LightStrip")
    elif kind == 2:
        for j in range(6):
            hb = h * (0.15 + 0.55 * (((j + 2) * 5) % 7) / 7.0)
            y = yc - w * 0.36 + w * 0.144 * j
            plate_x(p, x, y - w * 0.05, y + w * 0.05, zc - h * 0.36, zc - h * 0.36 + hb,
                    "Neon" if j == 5 else "LightStrip")
    else:
        for j in range(5):
            ind = (0.0, 0.08, 0.16, 0.08, 0.0)[j]
            L = w * (0.25 + 0.45 * (((j + 1) * 3) % 5) / 5.0)
            z = zc + h * (0.32 - 0.16 * j)
            plate_x(p, x, yc - w * 0.42 + w * ind, yc - w * 0.42 + w * ind + L, z - h * 0.04, z + h * 0.04,
                    "LightStrip" if j % 2 == 0 else "Neon")


def text_screen(p, lines, w, h, x=0.0, yc=0.0, zc=0.0, mat="LightStrip"):
    """Lines of text centred on a screen face."""
    hh = fit_h(lines, w * 0.90, h / (1.6 * len(lines)))
    text_lines(p, lines, yc, zc + (len(lines) * hh * 1.45) / 2 - hh * 0.2, hh, mat, x=x)


# --------------------------------------------------------------------------------------
# desk things (desk frame of interior_furniture.desk: top at F + 0.74, front edge x = 0, the sitter at +X)
# --------------------------------------------------------------------------------------
JOB_PLATES = ("PROMPT ENGINEER", "CHIEF VIBE OFFICER", "HEAD OF AGENTS", "AI WHISPERER", "INTERN (HUMAN)",
              "VP OF TOKENS")


def desk_plate(p, x, y, z, txt):
    """A small name plate: a dark wedge with light text facing +X."""
    L = max(0.16, text_width(txt, 0.016) + 0.03)
    p.convex([(x - 0.03, y - L / 2, z), (x + 0.02, y - L / 2, z), (x - 0.03, y - L / 2, z + 0.05),
              (x - 0.03, y + L / 2, z), (x + 0.02, y + L / 2, z), (x - 0.03, y + L / 2, z + 0.05)],
             [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)], "HullDark")
    with p.at(T(x - 0.005, y, z + 0.025), RY(-45.0), T(0.0, 0.0, 0.0)):
        text(p, txt, 0.0, 0.0, 0.016, "LightStrip", x=0.0035)


def mug(p, x, y, z, mat="Hull", tall=False):
    """A mug, or the 2026 'mega tumbler' (tall, with a straw)."""
    if tall:
        p.vcyl(x, y, z, z + 0.20, 0.035, 0.045, seg=8, mat=mat, cap0=False)
        p.vcyl(x, y, z + 0.20, z + 0.22, 0.047, seg=8, mat="Frame")
        p.vcyl(x + 0.01, y, z + 0.22, z + 0.28, 0.005, seg=4, mat="Fabric", cap0=False)
        bbox(p, x + 0.04, x + 0.06, y - 0.01, y + 0.01, z + 0.06, z + 0.16, mat)
    else:
        p.vcyl(x, y, z, z + 0.09, 0.04, seg=8, mat=mat, cap0=False)
        p.cap_disc(0.034, z + 0.085, "Wood", seg=8)
        bbox(p, x + 0.04, x + 0.06, y - 0.008, y + 0.008, z + 0.02, z + 0.07, mat)


def tiny_plant(p, x, y, z, seed=0):
    p.vcyl(x, y, z, z + 0.07, 0.035, 0.045, seg=6, mat=("Fabric", "Hull", "Accent")[seed % 3], cap0=False)
    for k in range(4):
        a = radians(90.0 * k + 20.0 * seed)
        p.beam((x, y, z + 0.06), (x + 0.07 * cos(a), y + 0.07 * sin(a), z + 0.12 + 0.03 * (k % 2)), 0.03, 0.006,
               "Plant", up=(0, 0, 1))


def figurine(p, x, y, z, seed=0):
    """A tiny robot desk toy (an original design: a box head with antenna)."""
    m = ("Accent", "Hazard", "Glow")[seed % 3]
    bbox(p, x - 0.02, x + 0.02, y - 0.025, y + 0.025, z, z + 0.05, m)
    bbox(p, x - 0.022, x + 0.022, y - 0.03, y + 0.03, z + 0.05, z + 0.09, "Hull")
    plate_x(p, x + 0.0225, y - 0.02, y + 0.02, z + 0.06, z + 0.08, "Screen")
    p.vcyl(x, y, z + 0.09, z + 0.12, 0.003, seg=4, mat="Frame", cap0=False)


def desk_clutter(p, d=0.62, w=1.2, seed=0, plate=None):
    """Things on a desk top (desk frame): a mug or tumbler, sticky notes, a phone, a plant / figurine, and a job
    plate on some desks."""
    rng = random.Random(seed * 13 + 5)
    zt = F + 0.74
    side = 1 if seed % 2 else -1
    mug(p, -0.16, side * (w / 2 - 0.16), zt, mat=("Hull", "Accent", "Fabric", "CushionLight")[seed % 4],
        tall=seed % 3 == 0)
    bbox(p, -0.20, -0.06, -side * (w / 2 - 0.20) - 0.04, -side * (w / 2 - 0.20) + 0.04, zt, zt + 0.008, "HullDark")
    for j in range(2 + seed % 2):                 # sticky notes on the desk top
        yy = -side * 0.05 + 0.07 * j
        plate_z(p, zt + 0.002, -d + 0.20 + 0.03 * j, -d + 0.27 + 0.03 * j, yy, yy + 0.06,
                ("Hazard", "Glow", "CushionLight")[j % 3])
    if rng.random() < 0.5:
        tiny_plant(p, -d + 0.12, -side * (w / 2 - 0.12), zt, seed)
    else:
        figurine(p, -d + 0.14, -side * (w / 2 - 0.14), zt, seed)
    if plate is None and seed % 3 == 1:
        plate = JOB_PLATES[(seed // 3) % len(JOB_PLATES)]
    if plate:
        desk_plate(p, -0.04, -side * 0.30, zt, plate)


# --------------------------------------------------------------------------------------
# kitchen satire and 2026 kitchen things (free-standing on a counter top at z)
# --------------------------------------------------------------------------------------
def kettle_bot(p, x, y, z, seed=0):
    """A kettle with a chatbot: a round body, a spout to +Y, a handle, and a small screen with a speech bubble."""
    with p.at(T(x, y, 0.0)):
        p.lathe([(0.075, z), (0.085, z + 0.05), (0.08, z + 0.14), (0.05, z + 0.18), (0.02, z + 0.19),
                 (0.0, z + 0.195)], ("Metal", "Hull", "Accent")[seed % 3], seg=10)
    p.cyl((x, y + 0.06, z + 0.08), (x, y + 0.13, z + 0.15), 0.018, 0.010, seg=5, mat="Metal", cap0=False)
    p.beam((x, y - 0.07, z + 0.06), (x, y - 0.10, z + 0.12), 0.02, 0.02, "Frame")
    p.beam((x, y - 0.10, z + 0.12), (x, y - 0.05, z + 0.17), 0.02, 0.02, "Frame")
    p.vcyl(x, y, z - 0.012, z, 0.09, seg=10, mat="HullDark")
    bbox(p, x + 0.07, x + 0.085, y - 0.04, y + 0.04, z + 0.07, z + 0.12, "HullDark")
    plate_x(p, x + 0.086, y - 0.035, y + 0.035, z + 0.075, z + 0.115, "Screen")
    text(p, ("HI!", "BOIL?", "SURE!")[seed % 3], y, z + 0.095, 0.014, "LightStrip", x=x + 0.088)
    # the speech bubble floating on a stalk over the kettle (a sticker-like card)
    bbox(p, x - 0.003, x + 0.003, y - 0.07, y + 0.07, z + 0.24, z + 0.30, "Hull")
    text(p, "HOW CAN I", y, z + 0.283, 0.012, "HullDark", x=x + 0.0035)
    text(p, "HELP BOIL?", y, z + 0.258, 0.012, "HullDark", x=x + 0.0035)
    p.vcyl(x, y, z + 0.195, z + 0.24, 0.003, seg=4, mat="Frame", cap0=False)


def sub_toaster(p, x, y, z, seed=0):
    """A toaster that asks for a subscription: two slots, a lever, a red screen 'TOAST+ SUBSCRIBE'."""
    bbox(p, x - 0.09, x + 0.09, y - 0.14, y + 0.14, z, z + 0.18, ("Hull", "Accent", "Metal")[seed % 3], bevel=0.03)
    for sy in (-0.05, 0.05):
        bbox(p, x - 0.06, x + 0.06, y + sy - 0.013, y + sy + 0.013, z + 0.178, z + 0.182, "Rubber")
    bbox(p, x - 0.01, x + 0.01, y + 0.14, y + 0.17, z + 0.10, z + 0.12, "Frame")
    plate_x(p, x + 0.091, y - 0.11, y + 0.11, z + 0.05, z + 0.12, "Screen")
    text(p, "TOAST+", y, z + 0.10, 0.018, "Neon", x=x + 0.093)
    text(p, "SUBSCRIBE", y, z + 0.068, 0.013, "LightStrip", x=x + 0.093)


def sourdough(p, x, y, z):
    """A sourdough starter jar with a rubber band (2026 grounding)."""
    p.vcyl(x, y, z, z + 0.16, 0.05, seg=8, mat="Glass", cap0=False, cap1=False)
    p.vcyl(x, y, z + 0.003, z + 0.10, 0.046, seg=8, mat="Cargo", cap0=False)
    p.vcyl(x, y, z + 0.16, z + 0.18, 0.054, seg=8, mat="Wood")
    p.vcyl(x, y, z + 0.11, z + 0.12, 0.051, seg=8, mat="Fabric", cap0=False, cap1=False)


def oat_carton(p, x, y, z):
    bbox(p, x - 0.035, x + 0.035, y - 0.035, y + 0.035, z, z + 0.19, "Hull")
    p.convex([(x - 0.035, y - 0.035, z + 0.19), (x + 0.035, y - 0.035, z + 0.19), (x - 0.035, y + 0.035, z + 0.19),
              (x + 0.035, y + 0.035, z + 0.19), (x, y - 0.035, z + 0.23), (x, y + 0.035, z + 0.23)],
             [(0, 1, 4), (2, 5, 3), (0, 4, 5, 2), (1, 3, 5, 4)], "Hull")
    plate_x(p, x + 0.036, y - 0.03, y + 0.03, z + 0.05, z + 0.12, "PlantDark")


def counter_set(p, x, y0, y1, z, seed=0):
    """Kitchen counter top things along +Y from y0 to y1 at height z (front +X): kettle bot, subscription toaster,
    sourdough and an oat carton, whatever fits."""
    y = y0 + 0.12
    items = [("kettle", 0.22), ("toaster", 0.32), ("dough", 0.14), ("oat", 0.10)]
    for k, (kind, wd) in enumerate(items[seed % 2:] + items[:seed % 2]):
        if y + wd > y1 - 0.04:
            break
        cy = y + wd / 2
        if kind == "kettle":
            kettle_bot(p, x, cy, z, seed)
        elif kind == "toaster":
            sub_toaster(p, x, cy, z, seed)
        elif kind == "dough":
            sourdough(p, x, cy, z)
        else:
            oat_carton(p, x, cy, z)
        y += wd + 0.04


# --------------------------------------------------------------------------------------
# signs and shrines
# --------------------------------------------------------------------------------------
def neon_text(p, txt, yc, zc, h, mat="Neon", x=0.0, rail=True):
    """An emissive sign on two thin back rails (wall piece, x = 0 at the wall)."""
    W = text_width(txt, h)
    if rail:
        for dz in (-h * 0.30, h * 0.30):
            bbox(p, x, x + 0.02, yc - W / 2 - 0.03, yc + W / 2 + 0.03, zc + dz - 0.006, zc + dz + 0.006, "Frame")
    text(p, txt, yc, zc, h, mat, x=x + 0.025)


def gpu_card(p, x, y, z, L=0.30):
    """A graphics card standing on its edge (original design): a dark shroud, three fans, an accent stripe."""
    bbox(p, x - 0.02, x + 0.02, y - L / 2, y + L / 2, z, z + 0.12, "HullDark", bevel=0.006)
    for k in range(3):
        yy = y - L / 3 + L / 3 * k
        with p.at(T(x + 0.021, yy, z + 0.06), RY(90.0)):
            p.cap_disc(0.038, 0.0, "Frame", seg=10)
            p.cap_disc(0.012, 0.001, "Metal", seg=6)
    plate_x(p, x + 0.022, y - L / 2 + 0.01, y + L / 2 - 0.01, z + 0.112, z + 0.118, "Neon")


def gpu_shrine(p, w=0.80, d=0.40, seed=0):
    """Wall piece: a small altar with a graphics card on a cushion, candles, energy-drink offerings, incense and a
    framed sign 'PRAY FOR VRAM' (x = 0 at the wall)."""
    zt = F + 0.80
    bbox(p, 0.02, d, -w / 2 + 0.04, w / 2 - 0.04, zt - 0.04, zt, "Wood", bevel=0.01)
    for sy in (-1, 1):
        bbox(p, 0.04, d - 0.03, sy * (w / 2 - 0.08) - 0.025, sy * (w / 2 - 0.08) + 0.025, F, zt - 0.04, "Wood")
    plate_x(p, d - 0.025, -w / 2 + 0.10, w / 2 - 0.10, zt - 0.12, zt - 0.06, "Fabric")      # altar cloth
    bbox(p, 0.10, 0.28, -0.16, 0.16, zt, zt + 0.04, "Fabric", bevel=0.015)                 # the cushion
    gpu_card(p, 0.19, 0.0, zt + 0.04, L=0.28)
    for k, yy in enumerate((-0.30, -0.24, 0.24, 0.30)):
        if abs(yy) > w / 2 - 0.06:
            continue
        hh = 0.08 + 0.04 * (k % 2)
        p.vcyl(d * 0.55, yy, zt, zt + hh, 0.016, seg=6, mat="Hull", cap0=False)
        p.vcyl(d * 0.55, yy, zt + hh, zt + hh + 0.025, 0.007, seg=4, mat="Window", cap0=False)
    for k, yy in enumerate((-0.12, 0.12)):                                                  # offerings
        p.vcyl(d - 0.07, yy, zt, zt + 0.11, 0.022, seg=6, mat=("Glow", "Hazard")[k], cap0=False)
    p.vcyl(0.06, 0.20, zt, zt + 0.16, 0.003, seg=3, mat="Wood", cap0=False)                 # incense
    o = WALL_OFF
    bbox(p, o, o + 0.02, -0.20, 0.20, zt + 0.16, CUT_SIGN, "Frame")
    plate_x(p, o + 0.021, -0.18, 0.18, zt + 0.18, CUT_SIGN - 0.02, "HullDark")
    text(p, "PRAY FOR", 0.0, zt + 0.32, 0.034, "Window", x=o + 0.023)
    text(p, "VRAM", 0.0, zt + 0.25, 0.044, "Window", x=o + 0.023)


CUT_SIGN = F + 1.24       # wall pieces stay under the cutaway cut (1.40) with their frame


def agents_screen(p, w=0.80, seed=0):
    """Wall piece: a room-booking screen where two agents argue about the meeting room."""
    with p.at(T(WALL_OFF, 0.0, 0.0)):
        _agents_screen(p, w, seed)


def _agents_screen(p, w, seed):
    ww = min(0.72, w - 0.06)
    z0, z1 = F + 0.70, F + 1.22
    bbox(p, 0.0, 0.04, -ww / 2, ww / 2, z0, z1, "Frame")
    plate_x(p, 0.041, -ww / 2 + 0.02, ww / 2 - 0.02, z0 + 0.02, z1 - 0.02, "Screen")
    x = 0.043
    text(p, "ROOM 2B: BOOKED x47", 0.0, z1 - 0.06, 0.022, "Neon", x=x)
    lines = (("AGENT A:", "MINE 10:00"), ("AGENT B:", "NO, MINE"), ("AGENT A:", "ESCALATING"),
             ("AGENT C:", "I SUMMARISED"), ("AGENT B:", "OBJECTION"))
    z = z1 - 0.12
    for j, (who, what) in enumerate(lines[seed % 2:seed % 2 + 4]):
        left = j % 2 == 0
        yc = -ww * 0.20 if left else ww * 0.20
        text(p, who, yc, z, 0.017, "LightStrip", x=x)
        text(p, what, yc, z - 0.03, 0.017, "LightStrip" if left else "Neon", x=x)
        z -= 0.085
    text(p, "HUMANS: 0 SEATS", 0.0, z0 + 0.05, 0.018, "Window", x=x)


def menu_board(p, w=0.80, seed=0):
    """Wall piece (kitchen, cantina): a lit menu screen with parody dishes."""
    with p.at(T(WALL_OFF, 0.0, 0.0)):
        _menu_board(p, w, seed)


def _menu_board(p, w, seed):
    ww = min(0.72, w - 0.06)
    z0, z1 = F + 0.72, F + 1.22
    bbox(p, 0.0, 0.04, -ww / 2, ww / 2, z0, z1, "Frame")
    plate_x(p, 0.041, -ww / 2 + 0.02, ww / 2 - 0.02, z0 + 0.02, z1 - 0.02, "HullDark")
    menus = (("TODAY", "ALGAE 3 WAYS", "AI SOUP*", "VIBE TEA"), ("SPECIALS", "TOFU BYTES", "LATENCY LATTE",
                                                                   "DUST CAKE"))
    lines = menus[seed % 2]
    text(p, lines[0], 0.0, z1 - 0.07, 0.034, "Neon", x=0.043)
    for j, ln in enumerate(lines[1:]):
        text(p, ln, 0.0, z1 - 0.15 - 0.075 * j, 0.024, "LightStrip", x=0.043)
    text(p, "*SOUP MAY HALLUCINATE", 0.0, z0 + 0.05, 0.012, "LightStrip", x=0.043)


def kettle_station(p, w=0.80, d=0.42, seed=0):
    """Wall piece: a low cabinet with the kettle bot, the subscription toaster and the sourdough jar on top, and an
    'AI-POWERED' sticker on the door."""
    h = 0.90
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h - 0.03, "Hull", bevel=0.015)
    bbox(p, -0.005, d + 0.02, -w / 2 - 0.01, w / 2 + 0.01, F + h - 0.03, F + h, "Wood")
    plate_x(p, d + 0.004, -w / 2 + 0.03, w / 2 - 0.03, F + 0.08, F + h - 0.10, "FloorDark")
    plate_x(p, d + 0.006, -0.12, 0.12, F + 0.55, F + 0.62, "Accent")
    text(p, "AI-POWERED", 0.0, F + 0.585, 0.016, "Hull", x=d + 0.008)
    counter_set(p, d * 0.55, -w / 2 + 0.02, w / 2 - 0.02, F + h, seed=seed)


# --------------------------------------------------------------------------------------
# floor graphics
# --------------------------------------------------------------------------------------
TIMELINE = ("1956 THE WORD AI", "1997 CHESS", "2016 GO", "2022 CHAT", "2025 AGENTS", "2026 KETTLES",
            "2031 MARS WIFI", "2048 THIS COLONY")


def floor_text(p, txt, x, y, yaw, h, mat):
    """Pixel text lying on the floor, readable from local -X (text along local +Y of the yaw frame)."""
    with p.at(T(x, y, F + 0.006), RZ(yaw), RY(-90.0)):
        text(p, txt, 0.0, 0.0, h, mat, x=0.0)


# --------------------------------------------------------------------------------------
# wall_set builders (fn(p, w, d, k)) and their depths
# --------------------------------------------------------------------------------------
def neon_kind(txt, mat="Neon"):
    def fn(p, w, d, k):
        h = min(0.09, (w - 0.10) / max(1.0, (6 * len(txt) - 1) / 7.0))
        neon_text(p, txt, 0.0, F + 1.12, h, mat, x=WALL_OFF)
        plate_x(p, 0.001, -w / 2 + 0.06, w / 2 - 0.06, F + 0.10, F + 0.14, "Frame")
    return fn


WALL_KINDS = {
    "aiposter": lambda p, w, d, k: poster(p, w=w, kind="ai", seed=k),
    "filmposter": lambda p, w, d, k: poster(p, w=w, kind=("film", "band")[k % 2], seed=k),
    "notice": lambda p, w, d, k: poster(p, w=w, kind="notice", seed=k),
    "kettle": lambda p, w, d, k: kettle_station(p, w=w, d=min(d, 0.42), seed=k),
    "shrine": lambda p, w, d, k: gpu_shrine(p, w=w, d=min(d, 0.40), seed=k),
    "agents": lambda p, w, d, k: agents_screen(p, w=w, seed=k),
    "menu": lambda p, w, d, k: menu_board(p, w=w, seed=k),
}
WALL_DEPTHS = {"aiposter": 0.08, "filmposter": 0.08, "notice": 0.08, "kettle": 0.42, "shrine": 0.40,
               "agents": 0.08, "menu": 0.08}
