"""Bake Ponyville's river flow: which way the water runs, and how fast, for the toon water shader.

usage: python tools/town_planner/build/bake_flow.py <project> <plan.json>

Reads the build's 1 m water mask (tools/town_planner/build/out/water.u8, grid.json) and the plan's lakes
and rivers, and writes world/water/ponyville_flow.json:
  origin [x, z]   the grid's corner; texel (i, j) is centred at origin + (i + 0.5, j + 0.5) * cell
  cell            metres per texel (1)
  width, depth    texels along x and z
  rgba            base64 RGBA8, rows by z: R, G = flow direction * 0.5 + 0.5 (world x, z), B = speed 0..1, A 255
  streams         every plan river as [x, y, z] points at the water surface, about 2 m apart, the first point
                  upstream (the soundscape places the brook's voices along them)
Also writes tools/town_planner/build/out/flow_preview.png (hue = direction, brightness = speed, arrows).

How the flow is found. The water is a network of channels between pools: the plan's spring pools
("spring": true) are where it comes from, every other lake (the bog included) is where it ends up. Two
distances are measured through the water (8-neighbour Dijkstra): from the springs' middles (D_src) and
from the lakes (D_sink). The water runs down D_sink - toward the nearest lake - wherever some lake can be
reached, and up D_src elsewhere. D_sink alone and not D_src: where two springs feed one channel, the two
fronts of D_src meet partway up the smaller branch and that stretch would run back toward its own spring.
The direction is the normalised gradient, smoothed over a few metres. Speed: 1 in channels; 0 in the
middle of a spring pool rising to 1 at its outlet; fading from 1 at a lake's mouth to 0 about 8 m in; 0 in
water no spring reaches. Values reach 3 m out over the dry banks so the shader's bilinear sampling holds
at the edge (the water mesh reaches 2 m under the banks).

This file does not touch world/water/ponyville_canals.json (the navigation revision hashes it).
"""
import base64, json, math, os, sys
import cv2, numpy as np
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
CELL = 1               # (2 until 2026-11-24: "ensure the water ripple/caustic flow follows each branch direction cleanly
                       # (including around the fork)": at 2 m, with a 2 m smoothing, a 3 m branch took on its neighbour's way)
LAKE_FADE = 8.0        # metres into a lake over which the current dies away
SMOOTH = 1.2           # gaussian sigma of the direction smoothing, metres
BANK_RING = 3          # metres of dry bank that get the nearest water's values

meta = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = int(meta["columns"]), int(meta["rows"])
X0, Z0 = float(meta["origin"][0]), float(meta["origin"][1])
WL = float(meta["water_level"])
assert float(meta["step"]) == 1.0
wet = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX) > 0
plan = json.load(open(PLAN, encoding="utf-8"))


def poly_mask(points: list) -> np.ndarray:
    m = np.zeros((NZ, NX), np.uint8)
    pts = np.array([[(p[0] - X0) * 8.0, (p[1] - Z0) * 8.0] for p in points], np.int32)  # 3 fractional bits
    cv2.fillPoly(m, [pts], 1, lineType=cv2.LINE_8, shift=3)
    return m > 0


springs, lakes = [], []
for lake in plan.get("lakes", []):
    if len(lake.get("points", [])) < 3: continue
    (springs if lake.get("spring") else lakes).append((lake.get("name", "lake"), poly_mask(lake["points"]) & wet))
spring_any = np.zeros_like(wet); lake_any = np.zeros_like(wet)
for _, m in springs: spring_any |= m
for _, m in lakes: lake_any |= m

# ---- the water as a graph: 8 neighbours, diagonal steps cost sqrt 2 ----
ids = -np.ones((NZ, NX), np.int64)
zz, xx = np.nonzero(wet)
ids[zz, xx] = np.arange(zz.size)
rows, cols, costs = [], [], []
for dz, dx in [(0, 1), (1, 0), (1, 1), (1, -1)]:
    z2, x2 = zz + dz, xx + dx
    ok = (z2 >= 0) & (z2 < NZ) & (x2 >= 0) & (x2 < NX)
    a = ids[zz[ok], xx[ok]]; b = ids[z2[ok], x2[ok]]
    keep = b >= 0
    rows.append(a[keep]); cols.append(b[keep]); costs.append(np.full(keep.sum(), math.hypot(dz, dx)))
r = np.concatenate(rows); c = np.concatenate(cols); w = np.concatenate(costs)
graph = coo_matrix((np.concatenate([w, w]), (np.concatenate([r, c]), np.concatenate([c, r]))), shape=(zz.size, zz.size)).tocsr()


def field(seed: np.ndarray) -> np.ndarray:
    out = np.full((NZ, NX), np.inf)
    s = ids[seed & wet]
    if s.size == 0: return out
    d = dijkstra(graph, directed=False, indices=s, min_only=True)
    out[zz, xx] = d
    return out


# the springs' middles: the cells of each pool farthest from its bank
seeds = np.zeros_like(wet)
pool_radius = {}
for name, m in springs:
    if not m.any(): continue
    inside = ndimage.distance_transform_edt(m)
    seeds |= m & (inside >= inside.max() - 1.0)
    pool_radius[name] = float(inside.max())
d_src = field(seeds)
reached = np.isfinite(d_src)
# the lakes take in the metre of shore around their outlines too (the mask is a little wider)
lake_any = wet & ndimage.binary_dilation(lake_any, iterations=2)
lakes = [(name, wet & ndimage.binary_dilation(m, iterations=2)) for name, m in lakes]

# ---- the potential: phi = 1 at the springs' middles, 0 in the lakes, no flow through a bank, and
# harmonic in between (steady seepage). A harmonic field has no high or low point inside a channel, so
# a channel never splits or meets head-on halfway along unless a spring or lake is there. ----
fixed = seeds | lake_any
free = wet & ~fixed
fid = -np.ones((NZ, NX), np.int64)
fz, fx = np.nonzero(free)
fid[fz, fx] = np.arange(fz.size)
A_r, A_c, A_v = [], [], []
rhs = np.zeros(fz.size)
deg = np.zeros(fz.size)
for dz_, dx_ in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
    z2, x2 = fz + dz_, fx + dx_
    ok = (z2 >= 0) & (z2 < NZ) & (x2 >= 0) & (x2 < NX)
    ok[ok] &= wet[z2[ok], x2[ok]]
    deg += ok
    k = np.nonzero(ok)[0]
    nb_free = fid[z2[k], x2[k]]
    inner = nb_free >= 0
    A_r.append(k[inner]); A_c.append(nb_free[inner]); A_v.append(np.full(inner.sum(), -1.0))
    edge = k[~inner]
    rhs[edge] += seeds[z2[edge], x2[edge]].astype(float)   # a fixed neighbour: 1 at a spring, 0 in a lake
A_r.append(np.arange(fz.size)); A_c.append(np.arange(fz.size)); A_v.append(deg + 1e-9)
from scipy.sparse import csr_matrix
from scipy.sparse.linalg import spsolve
A = csr_matrix((np.concatenate(A_v), (np.concatenate(A_r), np.concatenate(A_c))), shape=(fz.size, fz.size))
phi = np.zeros((NZ, NX))
phi[seeds] = 1.0
phi[fz, fx] = spsolve(A, rhs)
phi = -phi                                      # the water runs up phi (down the potential)
use_sink = np.ones_like(wet)

# gradient over the water only: dry cells take the nearest wet cell's value (a flat bank, no pull across it)
_, (iz, ix) = ndimage.distance_transform_edt(~wet, return_indices=True)
filled = phi[iz, ix]
gz, gx = np.gradient(filled)
wt = wet.astype(float)
sm = lambda a: ndimage.gaussian_filter(a * wt, SMOOTH) / np.maximum(ndimage.gaussian_filter(wt, SMOOTH), 1e-6)
gx, gz = sm(gx), sm(gz)
mag = np.hypot(gx, gz)
dx = np.where(mag > 1e-6, gx / np.maximum(mag, 1e-6), 0.0)
dz = np.where(mag > 1e-6, gz / np.maximum(mag, 1e-6), 0.0)

# ---- speed ----
# Channels run at 1 where water really passes. A side channel with no spring of its own beyond it (a
# dead end) carries almost nothing: its gradient is a thousandth of a fed channel's. Measured against
# the typical fed channel, a hundredth and less is still water.
channel = wet & ~spring_any & ~lake_any
typical = float(np.median(mag[channel & reached])) if (channel & reached).any() else 1.0
live = np.clip((np.log10(np.maximum(mag, 1e-12) / typical) + 2.5) / 1.0, 0.0, 1.0)  # 0 at 1/316, 1 at 1/32
speed = np.where(wet & reached, live, 0.0)
print(f"channel gradient: median {typical:.2e}; percentiles 1/5/25: " + ", ".join(f"{float(np.percentile(mag[channel & reached] / typical, q)):.3f}" for q in (1, 5, 25)))
# lakes: the current comes in at each mouth (where a channel meets the lake) and dies away LAKE_FADE m
# in, keeping the direction it came in with; the rest of the lake is still
mouth = channel & ndimage.binary_dilation(lake_any, iterations=1)
if mouth.any():
    to_mouth, (mz, mx) = ndimage.distance_transform_edt(~mouth, return_indices=True)
    fade = np.clip(1.0 - to_mouth / LAKE_FADE, 0.0, 1.0)
    dx = np.where(lake_any, dx[mz, mx], dx); dz = np.where(lake_any, dz[mz, mx], dz)
    speed = np.where(lake_any, speed[mz, mx] * fade * fade * (3.0 - 2.0 * fade), speed)
# spring pools: 0 in the middle, 1 at the outlet (the pool's wet edge where a channel leaves it)
for name, m in springs:
    if not m.any(): continue
    radius = max(pool_radius[name], 2.0)
    from_middle = np.where(np.isfinite(d_src), d_src, 0.0)
    outlet = channel & ndimage.binary_dilation(m, iterations=2)
    if outlet.any():
        to_outlet = ndimage.distance_transform_edt(~outlet)
        near_outlet = 1.0 - np.clip(to_outlet / (1.5 * radius), 0.0, 1.0)
    else:
        near_outlet = np.zeros_like(speed)
    ramp = np.clip(from_middle / radius, 0.0, 1.0)
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)
    speed = np.where(m, speed * ramp * near_outlet, speed)
speed = np.clip(speed, 0.0, 1.0)

# ---- the dry ring: nearest water's values ----
ring = ~wet & (ndimage.distance_transform_edt(~wet) <= BANK_RING)
for a in (dx, dz, speed):
    a[ring] = a[iz[ring], ix[ring]]
covered = wet | ring
dx[~covered] = 0.0; dz[~covered] = 0.0; speed[~covered] = 0.0

# ---- down to CELL metres: speed-weighted mean direction per block ----
W, D = (NX + CELL - 1) // CELL, (NZ + CELL - 1) // CELL
def block(a: np.ndarray) -> np.ndarray:
    p = np.zeros((D * CELL, W * CELL)); p[:NZ, :NX] = a
    return p.reshape(D, CELL, W, CELL).sum(axis=(1, 3))
cnt = block(covered.astype(float))
bx, bz = block(dx * covered), block(dz * covered)
bs = block(speed) / np.maximum(cnt, 1.0)
bm = np.hypot(bx, bz)
ux = np.where(bm > 1e-6, bx / np.maximum(bm, 1e-6), 0.0)
uz = np.where(bm > 1e-6, bz / np.maximum(bm, 1e-6), 0.0)
bs = np.where(bm > 1e-6, bs, 0.0)
rgba = np.zeros((D, W, 4), np.uint8)
rgba[..., 0] = np.clip(np.round((ux * 0.5 + 0.5) * 255.0), 0, 255)
rgba[..., 1] = np.clip(np.round((uz * 0.5 + 0.5) * 255.0), 0, 255)
rgba[..., 2] = np.clip(np.round(bs * 255.0), 0, 255)
rgba[..., 3] = 255
# a block's samples sit at X0 + CELL*i .. +CELL-1: centre X0 + CELL*i + (CELL-1)/2, so the corner is half a metre west
origin = [X0 - 0.5, Z0 - 0.5]

# ---- streams: the plan's rivers at the surface, oriented downstream ----
surface = None
canals_path = os.path.join(ROOT, "world/water/ponyville_canals.json")
if os.path.exists(canals_path):
    cdoc = json.load(open(canals_path))
    if [float(v) for v in cdoc["origin"]] == [X0, Z0] and int(cdoc["width"]) == NX and int(cdoc["depth"]) == NZ:
        surface = np.frombuffer(base64.b64decode(cdoc["heights"]), "<f4").reshape(NZ, NX)


def phi_at(x: float, z: float) -> float:
    i, j = int(round(x - X0)), int(round(z - Z0))
    if not (0 <= i < NX and 0 <= j < NZ): return float("nan")
    if not wet[j, i]: j, i = int(iz[j, i]), int(ix[j, i])
    return float(phi[j, i]) if (reached[j, i] or use_sink[j, i]) else float("nan")


def surface_at(x: float, z: float) -> float:
    i, j = int(round(x - X0)), int(round(z - Z0))
    if surface is not None and 0 <= i < NX and 0 <= j < NZ and np.isfinite(surface[j, i]): return float(surface[j, i])
    return WL


streams = []
for river in plan.get("rivers", []):
    pts = [(float(p[0]), float(p[1])) for p in river.get("points", [])]
    if len(pts) < 2: continue
    out = [pts[0]]
    for (ax, az), (bx_, bz_) in zip(pts, pts[1:]):
        n = max(1, int(math.ceil(math.hypot(bx_ - ax, bz_ - az) / 2.0)))
        out += [(ax + (bx_ - ax) * k / n, az + (bz_ - az) * k / n) for k in range(1, n + 1)]
    # downstream = phi rises: compare the means of each end's quarter (an end may sit in a pool)
    q = max(1, len(out) // 4)
    head = np.nanmean([phi_at(x, z) for x, z in out[:q]] or [np.nan])
    tail = np.nanmean([phi_at(x, z) for x, z in out[-q:]] or [np.nan])
    if np.isfinite(head) and np.isfinite(tail) and tail < head: out.reverse()
    streams.append([[round(x, 2), round(surface_at(x, z), 2), round(z, 2)] for x, z in out])

doc = {
    "version": 1,
    "note": "Ponyville river flow (tools/town_planner/build/bake_flow.py): rgba R,G = direction*0.5+0.5 (x, z), B = speed",
    "origin": origin, "cell": float(CELL), "width": int(W), "depth": int(D),
    "rgba": base64.b64encode(rgba.tobytes()).decode("ascii"),
    "streams": streams,
}
path = os.path.join(ROOT, "world/water/ponyville_flow.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, separators=(",", ":"))

# ---- summary and preview ----
flowing = bs > 0.02
print(f"flow: {W}x{D} texels of {CELL} m, {int(flowing.sum())} with flow (mean speed {float(bs[flowing].mean()) if flowing.any() else 0.0:.2f}); "
      f"{int((wet & ~reached).sum())} wet m2 no spring reaches; {len(springs)} springs, {len(lakes)} lakes, {len(streams)} streams -> {path}")
hue = (np.degrees(np.arctan2(uz, ux)) % 360.0) / 2.0
hsv = np.stack([hue, np.full_like(hue, 255.0), 60.0 + 195.0 * bs], -1).astype(np.uint8)
img = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)
img[cnt == 0] = (40, 40, 40)
S = 4
img = cv2.resize(img, (W * S, D * S), interpolation=cv2.INTER_NEAREST)
for j in range(2, D, 5):
    for i in range(2, W, 5):
        if bs[j, i] < 0.05 or not wet[min(NZ - 1, j * CELL), min(NX - 1, i * CELL)]: continue
        cx, cy = i * S + S // 2, j * S + S // 2
        L = 7 + 7 * bs[j, i]
        cv2.arrowedLine(img, (int(cx - ux[j, i] * L), int(cy - uz[j, i] * L)), (int(cx + ux[j, i] * L), int(cy + uz[j, i] * L)), (255, 255, 255), 1, cv2.LINE_AA, tipLength=0.45)
for name, m in springs + lakes:
    ys, xs = np.nonzero(m)
    if xs.size: cv2.putText(img, name[:16], (int(xs.mean() / CELL * S) - 20, int(ys.mean() / CELL * S)), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA)
cv2.imwrite(os.path.join(OUT, "flow_preview.png"), img)
print("preview ->", os.path.join(OUT, "flow_preview.png"), "(x right, z down; hue = direction, bright = fast)")
