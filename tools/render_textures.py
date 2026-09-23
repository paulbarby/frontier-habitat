"""RENDER agent: generates the tileable terrain textures for Frontier Habitat 2.0.

    python tools/render_textures.py

Writes assets/textures/terrain/*.png (512 x 512, tileable by construction: every noise is
built in the frequency domain or on a periodic lattice, so the right edge meets the left).

  sand_albedo.png   gravel_albedo.png   rock_albedo.png   ore_albedo.png
      RGB = albedo (sRGB), A = height (for height blending between layers)
  nrm_a.png         RG = sand normal XY, BA = gravel normal XY   (0.5 = flat)
  nrm_b.png         RG = rock normal XY, BA = ore normal XY
  macro.png         R, G, B, A = four independent low-frequency noise fields
                    (A is stretched along X for wind streaks)

The layers are near neutral in brightness; the terrain shader tints them per planet.
Deterministic: fixed seeds, so a re-run gives the same files.
"""
import os
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

N = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'textures', 'terrain')
os.makedirs(OUT, exist_ok=True)


def norm01(a):
    a = a - a.min()
    m = a.max()
    return a / m if m > 0 else a


def spectral(rng, beta, n=N, aniso=(1.0, 1.0), lo=0.0):
    """Tileable noise with a 1/f^beta spectrum. aniso stretches the frequencies."""
    w = rng.standard_normal((n, n))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    F = F / (f ** beta)
    if lo > 0:
        F[f < lo] = 0
    F[0, 0] = 0
    return norm01(np.real(np.fft.ifft2(F)))


def worley(rng, count, n=N):
    """Periodic Worley noise. Returns F1, F2 (in pixels) and the nearest point index."""
    pts = rng.random((count, 2))
    tree = cKDTree(pts, boxsize=1.0)
    yy, xx = np.mgrid[0:n, 0:n]
    q = np.stack([(xx + 0.5) / n, (yy + 0.5) / n], axis=-1).reshape(-1, 2)
    d, idx = tree.query(q, k=2)
    f1 = d[:, 0].reshape(n, n) * n
    f2 = d[:, 1].reshape(n, n) * n
    return f1, f2, idx[:, 0].reshape(n, n), pts


def normal_xy(h, strength):
    """Tangent-space normal XY from a height field (periodic finite differences).
    X follows +u (columns), Y follows +v (rows); flat = (0.5, 0.5)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5


def to8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def save_rgba(name, r, g, b, a):
    img = np.stack([to8(r), to8(g), to8(b), to8(a)], axis=-1)
    Image.fromarray(img, 'RGBA').save(os.path.join(OUT, name), optimize=True)
    print('wrote', name)


def blur(a, k=1):
    out = a.copy()
    for _ in range(k):
        out = (out + np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 5.0
    return out


yy, xx = np.mgrid[0:N, 0:N]
U = (xx + 0.5) / N
V = (yy + 0.5) / N

# ------------------------------------------------------------------ sand
rng = np.random.default_rng(101)
low = spectral(rng, 2.2)
mid = spectral(rng, 1.4)
grain = spectral(rng, 0.2)
amp = 0.35 + 0.65 * spectral(rng, 2.4)
# Wind ripples: integer wave numbers keep them tileable; a warp keeps them organic.
warp = spectral(rng, 2.0) * 2.0 - 1.0
rip_phase = 2 * np.pi * (19 * U + 6 * V) + warp * 2.6
ripple = (np.sin(rip_phase) * 0.5 + 0.5) ** 1.6
sand_h = norm01(0.35 * low + 0.25 * mid + 0.12 * grain + 0.28 * ripple * amp)
base = np.array([0.71, 0.42, 0.26])
dark = np.array([0.54, 0.30, 0.18])
light = np.array([0.82, 0.55, 0.37])
t = np.clip(0.5 + (mid - 0.5) * 1.3 + (ripple - 0.5) * 0.25 * amp, 0, 1)[..., None]
sand = dark * (1 - t) + base * t
sand = sand * (0.9 + 0.2 * grain[..., None])
speck = rng.random((N, N))
sand = np.where((speck > 0.992)[..., None], light, sand)
sand = np.where((speck < 0.006)[..., None], dark * 0.7, sand)
save_rgba('sand_albedo.png', sand[..., 0], sand[..., 1], sand[..., 2], sand_h)
sand_nx, sand_ny = normal_xy(sand_h, 5.0)

# ------------------------------------------------------------------ gravel
rng = np.random.default_rng(202)
f1, f2, idx, pts = worley(rng, 260)
radius = 7.0 + rng.random(len(pts)) * 9.0          # pebble radius in pixels
r = radius[idx]
peb = np.clip(1.0 - (f1 / r) ** 2, 0, 1)
dome = np.sqrt(peb)
f1b, f2b, idxb, ptsb = worley(rng, 900)
rb = 2.5 + rng.random(len(ptsb)) * 4.0
pebb = np.sqrt(np.clip(1.0 - (f1b / rb[idxb]) ** 2, 0, 1))
fine = spectral(rng, 1.0)
between = spectral(rng, 1.8)
grav_h = norm01(np.maximum(dome * (0.75 + 0.25 * fine), pebb * 0.55) + 0.18 * between + 0.06 * fine)
palette = np.array([[0.46, 0.36, 0.30], [0.36, 0.26, 0.21], [0.60, 0.48, 0.38], [0.30, 0.25, 0.24], [0.55, 0.36, 0.24], [0.42, 0.40, 0.38]])
pc = palette[rng.integers(0, len(palette), len(pts))][idx]
pcb = palette[rng.integers(0, len(palette), len(ptsb))][idxb]
sand_g = np.array([0.66, 0.43, 0.28]) * (0.85 + 0.3 * between[..., None])
shade = (0.78 + 0.35 * dome)[..., None] * (0.9 + 0.2 * fine[..., None])
grav = np.where((dome > 0.02)[..., None], pc * shade, np.where((pebb > 0.05)[..., None], pcb * (0.8 + 0.3 * pebb[..., None]), sand_g))
# Dark contact shadow around each pebble.
ring = np.clip((f1 - r) / 3.0, 0, 1)
grav = grav * np.where((dome <= 0.02)[..., None], (0.7 + 0.3 * ring)[..., None], 1.0)
save_rgba('gravel_albedo.png', grav[..., 0], grav[..., 1], grav[..., 2], grav_h)
grav_nx, grav_ny = normal_xy(grav_h, 7.0)

# ------------------------------------------------------------------ rock
rng = np.random.default_rng(303)
big = spectral(rng, 2.0)
det = spectral(rng, 1.2)
warp = spectral(rng, 2.2) * 2 - 1
strata = np.sin(2 * np.pi * (3 * V + 1 * U) * 3 + warp * 3.5) * 0.5 + 0.5
c1, c2, cidx, cp = worley(rng, 70)
crack = np.clip((c2 - c1) / 5.0, 0, 1)                 # 0 on the crack lines
c1s, c2s, _, _ = worley(rng, 300)
crack_s = np.clip((c2s - c1s) / 3.0, 0, 1)
rock_h = norm01(0.45 * big + 0.2 * det + 0.2 * strata + 0.15 * crack * crack_s)
rock_h = rock_h * (0.55 + 0.45 * crack) * (0.8 + 0.2 * crack_s)
rock_h = norm01(rock_h)
rbase = np.array([0.50, 0.33, 0.24])
rlight = np.array([0.66, 0.47, 0.35])
rdark = np.array([0.30, 0.19, 0.14])
tt = np.clip(strata * 0.5 + det * 0.5, 0, 1)[..., None]
rock = rbase * (1 - tt) + rlight * tt
rock = rock * (0.8 + 0.3 * big[..., None])
rock = rock * (1 - (1 - crack[..., None]) * 0.38) * (1 - (1 - crack_s[..., None]) * 0.18)
# Dust caught in low spots.
dust = np.clip((0.35 - rock_h) * 3.0, 0, 1)[..., None]
rock = rock * (1 - dust) + np.array([0.70, 0.45, 0.29]) * dust
save_rgba('rock_albedo.png', rock[..., 0], rock[..., 1], rock[..., 2], rock_h)
rock_nx, rock_ny = normal_xy(rock_h, 9.0)

# ------------------------------------------------------------------ ore field
rng = np.random.default_rng(404)
o1, o2, oidx, op = worley(rng, 520)
orad = 5.0 + rng.random(len(op)) * 9.0
chunk = np.sqrt(np.clip(1.0 - (o1 / orad[oidx]) ** 2, 0, 1))
edge = np.clip((o2 - o1) / 2.5, 0, 1)
blob = spectral(rng, 1.6)
fine = spectral(rng, 0.6)
ore_h = norm01(0.55 * chunk * (0.8 + 0.2 * fine) + 0.3 * blob + 0.15 * fine)
obase = np.array([0.23, 0.19, 0.18])
orust = np.array([0.40, 0.21, 0.14])
t = np.clip(spectral(rng, 2.0) * 1.4 - 0.2, 0, 1)[..., None]
ore = obase * (1 - t) + orust * t
tone = rng.random(len(op))[oidx][..., None]
ore = ore * (0.8 + 0.35 * tone) * (0.8 + 0.3 * chunk[..., None]) * (0.9 + 0.2 * fine[..., None])
ore = ore * (0.82 + 0.18 * edge[..., None])
dustm = np.clip((0.3 - chunk) * 3.0, 0, 1)[..., None] * 0.5
ore = ore * (1 - dustm) + np.array([0.52, 0.33, 0.22]) * dustm
glint = (rng.random((N, N)) > 0.992) & (chunk > 0.3)
ore = np.where(glint[..., None], np.array([0.72, 0.70, 0.66]), ore)
save_rgba('ore_albedo.png', ore[..., 0], ore[..., 1], ore[..., 2], ore_h)
ore_nx, ore_ny = normal_xy(ore_h, 7.0)

save_rgba('nrm_a.png', sand_nx, sand_ny, grav_nx, grav_ny)
save_rgba('nrm_b.png', rock_nx, rock_ny, ore_nx, ore_ny)

# ------------------------------------------------------------------ macro
rng = np.random.default_rng(505)
m_r = spectral(rng, 2.6)
m_g = spectral(rng, 1.9)
ridge = 1.0 - np.abs(spectral(rng, 2.2) * 2 - 1)
m_b = norm01(ridge ** 2)
m_a = spectral(rng, 1.7, aniso=(0.12, 1.0))      # stretched along X (u): wind streaks
save_rgba('macro.png', m_r, m_g, m_b, m_a)
print('done ->', os.path.abspath(OUT))
