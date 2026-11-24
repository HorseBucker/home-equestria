"""Paint Ponyville's stream bed: damp sandy earth with pebbles lying in clusters, for the rivers' beds and the wet
bank just above them (2026-11-24 play test: the game's river_bed texture is blue painted water with pebbles strewn
evenly over it, which under the real water read as blue patches in the shallows, and grass ran down into the water).

usage: python tools/town_planner/build/make_stream_bed_texture.py <project>
Writes world/terrain/textures_gen/pv_stream_bed.png (textures.json id 23, stream_bed): 1024 px for a 6 m tile,
seamless, alpha = blend height (pebbles high, so the grass's edge breaks up round them as it blends in). Warm
sandy earth, darker and cooler where it is wet in soft drifts, pale sandy bars, and fine grit, a little gathered
here and there (no pebbles: on a slope they stretched; the stones are 3D, make_river_dressing.gd). The water above tints it; above the waterline it reads as a damp, stony bank.
"""
import math, os, random, sys
import cv2, numpy as np

ROOT = sys.argv[1]
OUT = os.path.join(ROOT, "world/terrain/textures_gen/pv_stream_bed.png")
N = 1024
TILE_M = 6.0
PX = N / TILE_M
# (2026-11-24 third pass: "switch the riverbed/bank material back from the dark road-dirt brown to the lighter,
# sandy/tan tone": lighter sand, and its damp drifts only a little darker)
SAND = (204, 186, 146)
WET = (170, 152, 120)
BAR = (222, 206, 168)
STONES = [(150, 146, 138), (176, 168, 150), (128, 116, 100), (186, 176, 158), (112, 108, 104)]
rng = random.Random(2311)
nrng = np.random.default_rng(2311)

big = np.zeros((3 * N, 3 * N, 3), np.float32); big[:] = SAND
height = np.full((3 * N, 3 * N), 110.0, np.float32)


def stamp(draw):
    for ox in (0, N, 2 * N):
        for oy in (0, N, 2 * N):
            draw(ox, oy)


def field(scale):
    noise = nrng.standard_normal((N, N)).astype(np.float32)
    noise = cv2.GaussianBlur(np.tile(noise, (3, 3)), (0, 0), scale / 3)[N:2 * N, N:2 * N]
    noise /= noise.std() or 1
    return np.tile(noise, (3, 3))


# earth: gentle unevenness, then damp drifts (darker, cooler) and pale sandy bars
for scale, amp in ((240.0, 4.0), (70.0, 3.0), (16.0, 2.0), (4.0, 1.5)):
    big += field(scale)[..., None] * amp
damp = np.clip(field(150.0) * 0.6 + 0.15, 0, 1)
damp = cv2.GaussianBlur(damp, (0, 0), 12.0)[..., None]
big = big * (1 - damp * 0.4) + np.array(WET, np.float32) * damp * 0.4
bars = np.clip(field(110.0) - 0.9, 0, 1)
bars = cv2.GaussianBlur(bars, (0, 0), 10.0)[..., None]
big = big * (1 - bars * 0.6) + np.array(BAR, np.float32) * bars * 0.6
height += bars[..., 0] * 18.0 - damp[..., 0] * 10.0


def pebble(x, y, r, colour, flat):
    """One pebble: a filled ellipse, lit on its upper side, a dark rim below, raised in the height."""
    w = r; h = r * flat; ang = rng.uniform(0, 180)
    body = np.zeros((3 * N, 3 * N), np.uint8); lit = np.zeros((3 * N, 3 * N), np.uint8); rim = np.zeros((3 * N, 3 * N), np.uint8)
    stamp(lambda ox, oy: cv2.ellipse(body, (int(x + ox), int(y + oy)), (max(2, int(w)), max(2, int(h))), ang, 0, 360, 255, -1, cv2.LINE_AA))
    stamp(lambda ox, oy: cv2.ellipse(lit, (int(x + ox - w * 0.15), int(y + oy - h * 0.25)), (max(1, int(w * 0.55)), max(1, int(h * 0.45))), ang, 0, 360, 255, -1, cv2.LINE_AA))
    stamp(lambda ox, oy: cv2.ellipse(rim, (int(x + ox), int(y + oy + max(1, h * 0.12))), (max(2, int(w)), max(2, int(h))), ang, 20, 160, 255, max(1, int(r * 0.12)), cv2.LINE_AA))
    return body, lit, rim, colour


stones = []
# only fine grit, a little gathered here and there: the terrain is painted from above, so on a bank's slope anything
# larger stretched into long ovals down it (2026-11-24 play test: "the pebbles on the sloped banks look like 2D decals
# stretched vertically down the slope"); the stones are real ones now (make_river_dressing.gd river_rocks, pebbles)
for _ in range(22):
    cx, cy = rng.uniform(0, N), rng.uniform(0, N)
    spread = rng.uniform(0.15, 0.35) * PX
    for _ in range(rng.randint(4, 9)):
        a = rng.uniform(0, math.tau); d = abs(rng.gauss(0, 0.55)) * spread
        stones.append((cx + math.cos(a) * d, cy + math.sin(a) * d, rng.uniform(0.012, 0.03) * PX))
for _ in range(120):
    stones.append((rng.uniform(0, N), rng.uniform(0, N), rng.uniform(0.008, 0.02) * PX))
stones.sort(key=lambda s: s[2], reverse=True)        # big ones first, small ones lie over their edges
for x, y, r in stones:
    body, lit, rim, colour = pebble(x, y, r, rng.choice(STONES), rng.uniform(0.6, 0.9))
    b = cv2.GaussianBlur(body.astype(np.float32) / 255.0, (0, 0), 0.7)[..., None]
    tone = np.array(colour, np.float32) * rng.uniform(0.92, 1.06)
    big = big * (1 - b) + tone * b
    l = cv2.GaussianBlur(lit.astype(np.float32) / 255.0, (0, 0), max(1.0, r * 0.25))[..., None] * 0.35
    big = big * (1 - l) + np.minimum(tone * 1.25, 255) * l
    m = cv2.GaussianBlur(rim.astype(np.float32) / 255.0, (0, 0), 0.8)[..., None] * 0.55
    big = big * (1 - m) + np.array(WET, np.float32) * 0.7 * m
    height = np.maximum(height, b[..., 0] * (150.0 + r * 0.9))

grain = cv2.GaussianBlur(np.tile(nrng.standard_normal((N, N)).astype(np.float32), (3, 3)), (0, 0), 0.9) * 3.0
big += grain[..., None]
tile = np.clip(big[N:2 * N, N:2 * N], 0, 255).astype(np.uint8)
alpha = np.clip(height[N:2 * N, N:2 * N], 0, 255).astype(np.uint8)
cv2.imwrite(OUT, np.dstack([tile[..., ::-1], alpha]))
print("wrote", OUT, "mean colour", tile.reshape(-1, 3).mean(0).round(1))
