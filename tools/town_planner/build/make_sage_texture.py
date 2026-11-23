"""Paint Ponyville's town ground texture, as the show draws it: flat dusty sage green packed earth, with
pale rounded patches and a few short dark scuff strokes (colours sampled from show backgrounds).

usage: python tools/town_planner/build/make_sage_texture.py <project>
Writes world/terrain/textures_gen/pv_town_sage.png: 1024 px for a 6 m tile (as sharp underfoot as the game's
dirt roads; at 12 m it was blurred), seamless, alpha = blend height (patches and pebbles a little high,
strokes low) like the game's other hand-painted Ponyville layers. Over the flat sage: a fine grain, soft
lighter and darker drifts, faint pale patches, small flat pebbles and a few dark scuff strokes. The game turns
and shifts the tile from place to place (textures.json: detiling_rotation, detiling_shift), so no row of the
same patch runs down a street.
"""
import math, os, random, sys
import cv2, numpy as np

ROOT = sys.argv[1]
OUT = os.path.join(ROOT, "world/terrain/textures_gen/pv_town_sage.png")
N = 1024
TILE_M = 6.0
PX = N / TILE_M                       # pixels per metre
BASE = (145, 178, 157)
PATCH = (186, 214, 190)
STROKE = (82, 116, 98)
rng = random.Random(1402)
nrng = np.random.default_rng(1402)

# work on a 3x3 canvas and keep the middle, so everything wraps across the tile's edges
big = np.zeros((3 * N, 3 * N, 3), np.float32)
big[:] = BASE
height = np.full((3 * N, 3 * N), 128.0, np.float32)


def stamp(draw):
    """Draw the same shape at all nine copies of the tile."""
    for ox in (0, N, 2 * N):
        for oy in (0, N, 2 * N):
            draw(ox, oy)


# gentle large-scale unevenness in the earth itself
for scale, amp in ((260.0, 3.0), (90.0, 2.2), (22.0, 1.4), (5.0, 1.1)):
    noise = nrng.standard_normal((N, N)).astype(np.float32)
    k = int(scale) | 1
    noise = cv2.GaussianBlur(np.tile(noise, (3, 3)), (0, 0), scale / 3)[N:2 * N, N:2 * N]
    noise /= noise.std() or 1
    big += np.tile(noise, (3, 3))[..., None] * amp * np.array([0.9, 1.0, 0.9], np.float32)

# pale patches: soft-edged rounded blobs, mostly 0.25-0.9 m, some grouped in little clusters
patch_mask = np.zeros((3 * N, 3 * N), np.uint8)
for _ in range(9):
    cx, cy = rng.uniform(0, N), rng.uniform(0, N)
    for _ in range(rng.choice([1, 1, 2, 2, 3])):
        x = cx + rng.uniform(-0.5, 0.5) * PX; y = cy + rng.uniform(-0.4, 0.4) * PX
        w = rng.uniform(0.14, 0.4) * PX; h = w * rng.uniform(0.4, 0.75)
        ang = rng.uniform(0, 180)
        stamp(lambda ox, oy: cv2.ellipse(patch_mask, (int(x + ox), int(y + oy)), (int(w), int(h)), ang, 0, 360, 255, -1, cv2.LINE_AA))
# soft and faint: strong round patches in a tile that repeats every 6 m stood in straight rows down a street
soft = cv2.GaussianBlur(patch_mask.astype(np.float32) / 255.0, (0, 0), 7.0) * 0.5
big = big * (1 - soft[..., None]) + np.array(PATCH, np.float32) * soft[..., None]
height += soft * 22.0

# small flat pebbles pressed into the earth: rounded, a shade lighter or darker, a thin dark rim on one side
pebble = np.zeros((3 * N, 3 * N), np.float32); rim = np.zeros((3 * N, 3 * N), np.uint8)
for _ in range(70):
    x, y = rng.uniform(0, N), rng.uniform(0, N)
    w = rng.uniform(0.025, 0.07) * PX; h = w * rng.uniform(0.6, 0.9); ang = rng.uniform(0, 180)
    tone = rng.choice([-1.0, 1.0, 1.0]) * rng.uniform(0.5, 1.0)
    one = np.zeros((3 * N, 3 * N), np.uint8)
    stamp(lambda ox, oy: cv2.ellipse(one, (int(x + ox), int(y + oy)), (max(2, int(w)), max(2, int(h))), ang, 0, 360, 255, -1, cv2.LINE_AA))
    stamp(lambda ox, oy: cv2.ellipse(rim, (int(x + ox), int(y + oy + 1)), (max(2, int(w)), max(2, int(h))), ang, 20, 160, 255, 1, cv2.LINE_AA))
    pebble += one.astype(np.float32) / 255.0 * tone
pebble = cv2.GaussianBlur(pebble, (0, 0), 0.8)
big += pebble[..., None] * np.array([14.0, 13.0, 12.0], np.float32)
rs = cv2.GaussianBlur(rim.astype(np.float32) / 255.0, (0, 0), 0.7) * 0.45
big = big * (1 - rs[..., None]) + np.array(STROKE, np.float32) * rs[..., None]
height += np.abs(pebble) * 14.0

# short dark scuffs: thin arcs and little "v" ticks, as the show's ground scribbles
stroke_mask = np.zeros((3 * N, 3 * N), np.uint8)
for _ in range(7):
    x, y = rng.uniform(0, N), rng.uniform(0, N)
    length = rng.uniform(0.2, 0.5) * PX
    bend = rng.uniform(-0.35, 0.35)
    ang = rng.uniform(-0.25, 0.25)
    pts = []
    for i in range(12):
        t = i / 11.0
        px = x + math.cos(ang) * (t - 0.5) * length
        py = y + math.sin(ang) * (t - 0.5) * length - math.sin(t * math.pi) * bend * length * 0.5
        pts.append((px, py))
    thick = rng.choice([3, 4, 4])
    pts_a = np.array(pts)
    stamp(lambda ox, oy: cv2.polylines(stroke_mask, [np.round(pts_a + (ox, oy)).astype(np.int32)], False, 255, thick, cv2.LINE_AA))
    if rng.random() < 0.35:            # a little tick beside it
        tx, ty = x + length * 0.6, y - 4
        stamp(lambda ox, oy: cv2.polylines(stroke_mask, [np.array([[tx + ox, ty + oy], [tx + 8 + ox, ty + 6 + oy], [tx + 16 + ox, ty - 2 + oy]], np.int32)], False, 255, 2, cv2.LINE_AA))
sm = cv2.GaussianBlur(stroke_mask.astype(np.float32) / 255.0, (0, 0), 0.8) * 0.8
big = big * (1 - sm[..., None]) + np.array(STROKE, np.float32) * sm[..., None]
height -= sm * 30.0

# a fine grain, so the ground is not a flat fill up close
grain = nrng.standard_normal((N, N)).astype(np.float32)
grain = cv2.GaussianBlur(np.tile(grain, (3, 3)), (0, 0), 0.9) * 2.4
big += grain[..., None]
tile = np.clip(big[N:2 * N, N:2 * N], 0, 255).astype(np.uint8)
alpha = np.clip(height[N:2 * N, N:2 * N], 0, 255).astype(np.uint8)
rgba = np.dstack([tile[..., ::-1], alpha])                      # BGR(A) for OpenCV
cv2.imwrite(OUT, rgba)
print("wrote", OUT, "mean colour", tile.reshape(-1, 3).mean(0).round(1))
