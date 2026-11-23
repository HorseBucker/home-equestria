"""Shape the ground for a plan: a flat village, gently rolling countryside, and beds for its water.

usage: python tools/town_planner/elevation.py <plan.json> [<out.json>] [--preview <png>] [--export <dir>]

The ground inside the plan's edge is made anew (the game's old hills and old river trenches inside it
are gone); over the last 60 m inside the edge it blends into the game's real ground outside.
- The village (the town ground, the town streets with their rows of houses, and 10 m round them) is flat at `base`.
- The countryside rolls: the official map draws higher ground in darker greens (the ridge the railway
  tunnels into, the hills north of Sparkling Lake); those shades set broad, low hills, with a little
  gentle unevenness on top. Nothing is steep.
- Valleys: the ground comes down to `base` along every river and lake, over 30 m.
- Fluttershy's cottage sits on a low mound (`mounds`).
- Buildings outside the village stand on level pads (at the height the land has there, or at `pad_levels[id]`); each bridge's two feet stand on level ground at one height;
  the ground rises gently to a door listed in `door_slopes`; a building in `plinths` stands on a low rise with its
  front cut down to the square for its steps.
- Rivers and lakes are cut in last: one water level for all of them (`water_level`, 0.7 m below the
  village), so every channel and lake can be filled; beds 1.2-1.8 m deep in rivers, up to 3 m in lakes.

Settings live in plan["terrain"] and can be changed there and the script run again. The result is
stored in the plan as a 2 m height grid (for the planner); the build runs this same script at 1 m.
"""
import base64, json, math, sys
import cv2, numpy as np
from scipy import ndimage

args = []
for i, a in enumerate(sys.argv[1:], 1):
    if not a.startswith("--") and sys.argv[i - 1] not in ("--preview", "--export"):
        args.append(a)
SRC = args[0]
OUT = args[1] if len(args) > 1 else SRC
PREVIEW = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
EXPORT = sys.argv[sys.argv.index("--export") + 1] if "--export" in sys.argv else None   # full 1 m grids for the build
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
plan = json.load(open(SRC, encoding="utf-8"))
T = plan.setdefault("terrain", {})
T.setdefault("base", -12.0)
T.setdefault("water_offset", 0.7)
T.setdefault("hill_step", 3.2)          # metres per shade of the map's greens
T.setdefault("roll", 1.6)               # metres of gentle unevenness in the countryside
T.setdefault("blend", 60.0)             # metres over which it meets the game's ground at the edge
T.setdefault("valley", 30.0)            # metres over which the ground comes down to the water
cottage = next((l for l in plan.get("landmarks", []) if l["id"] == "snazzys_fluttershy_cottage_01"), None)
if "mounds" not in T:
    T["mounds"] = [{"x": cottage["x"], "z": cottage["z"], "top": 14.0, "radius": 45.0, "height": 2.5, "name": "Fluttershy's cottage"}] if cottage else []
# The planner's notes `hill <height> <radius>` and `mound <height> <radius>` (2026-11-19 play test: a big grassy hill
# to overlook the town from, where the flower meadow was, and small mounds on the town's open lawns): a hill has a
# flat top HILL_TOP m across for a picnic and a gentle profile (no steeper than max_slope); a mound stands in the
# village too (the village ground is otherwise kept level), on open lawn.
HILL_TOP = 10.0
def note_mounds(notes):
    out = []
    for n in notes:
        words = str(n.get("text", "")).lower().split()
        if not words or words[0] not in ("hill", "mound"):
            continue
        nums = [float(w) for w in words[1:] if w.replace(".", "", 1).isdigit()]
        if words[0] == "hill":
            h, r = (nums + [11.0, 85.0])[:2] if len(nums) < 2 else nums[:2]
            out.append({"x": n["x"], "z": n["z"], "height": h, "radius": r, "top": 0.0, "profile": "smooth", "name": "hill"})
        else:
            h, r = (nums + [1.2, 9.0])[:2] if len(nums) < 2 else nums[:2]
            out.append({"x": n["x"], "z": n["z"], "height": h, "radius": r, "top": r * 0.25, "profile": "gentle", "town": True, "name": "mound"})
    return out
NOTE_MOUNDS = note_mounds(plan.get("notes", []))
BASE = float(T["base"]); WATER = BASE - float(T["water_offset"])
T["water_level"] = round(WATER, 2)

# ---- the grid: 1 m over the edge's box ----
edge = plan["edges"][0]["points"]
x0 = math.floor(min(p[0] for p in edge)); x1 = math.ceil(max(p[0] for p in edge))
z0 = math.floor(min(p[1] for p in edge)); z1 = math.ceil(max(p[1] for p in edge))
STEP = 1.0
NX, NZ = int((x1 - x0) / STEP) + 1, int((z1 - z0) / STEP) + 1
xs = x0 + np.arange(NX) * STEP; zs = z0 + np.arange(NZ) * STEP
X, Z = np.meshgrid(xs, zs)


def to_px(points):
    return np.array([[(p[0] - x0) / STEP, (p[1] - z0) / STEP] for p in points], np.float32)


def fill(polys):
    m = np.zeros((NZ, NX), np.uint8)
    for poly in polys:
        cv2.fillPoly(m, [np.round(to_px(poly) * 8).astype(np.int32)], 1, shift=3)
    return m.astype(bool)


def smoothstep(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---- the game's ground (for the edge) ----
gj = json.load(open(HERE + "/data/ground.json"))
real = np.fromfile(HERE + "/data/heights.f32", np.float32).reshape(gj["rows"], gj["columns"])
gx = (X - gj["bounds"][0]) / gj["step"]; gz = (Z - gj["bounds"][2]) / gj["step"]
real_here = ndimage.map_coordinates(real, [gz, gx], order=1, mode="nearest")

# ---- the map's shades of green: higher ground is darker ----
REF = plan["reference"]
img = cv2.imread(HERE + "/data/reference.jpg")
H, W = img.shape[:2]
MPP = REF["width"] / W
rgb = img[:, :, ::-1].astype(np.float32)
SHADES = [((168, 204, 108), 0.0), ((156, 204, 108), 0.0), ((144, 192, 72), 1.0), ((108, 168, 60), 2.0),
          ((108, 156, 60), 2.0), ((96, 132, 60), 3.0), ((96, 96, 144), 4.0)]
dist = np.stack([np.abs(rgb - np.array(c, np.float32)).sum(2) for c, _ in SHADES])
best = dist.argmin(0); known = dist.min(0) < 40
# the town's own colours count as the valley floor
for c in ((136, 180, 147), (231, 203, 155), (222, 217, 122)):
    near = np.abs(rgb - np.array(c, np.float32)).sum(2) < 40
    best[near] = 0; known |= near
level = np.array([v for _, v in SHADES], np.float32)[best]
small = 4
lv = cv2.resize(level * known, (W // small, H // small), interpolation=cv2.INTER_AREA)
kn = cv2.resize(known.astype(np.float32), (W // small, H // small), interpolation=cv2.INTER_AREA)
sig = 12.0 / MPP / small                 # fill the gaps (trees, words) from round about
lv = cv2.GaussianBlur(lv, (0, 0), sig); kn = cv2.GaussianBlur(kn, (0, 0), sig)
level_map = lv / np.maximum(kn, 1e-4)
level_map = cv2.GaussianBlur(level_map, (0, 0), 40.0 / MPP / small)     # broad hills, no steps
mx = ((X - REF["x"]) / MPP + W / 2) / small; mz = ((Z - REF["z"]) / MPP + H / 2) / small
hills = ndimage.map_coordinates(level_map, [mz, mx], order=1, mode="nearest") * float(T["hill_step"])

# gentle unevenness, the same every run
rng = np.random.default_rng(int(T.get("seed", 7)))
roll = np.zeros((NZ, NX), np.float32)
for size, share in ((90.0, 0.7), (40.0, 0.3)):
    noise = ndimage.gaussian_filter(rng.standard_normal((NZ, NX)).astype(np.float32), size / STEP / 2.5)
    roll += share * noise / (noise.std() or 1)
roll *= float(T["roll"])

# ---- the plan's pieces ----
town = fill([g["points"] for g in plan.get("grounds", [])])
# a plan laid out along streets (layout_town.py): the village is its squares, its streets with the rows of
# houses either side, and the blocks they enclose
streets = [r for r in plan.get("roads", []) if r.get("type", "town") == "town"]
if streets:
    strokes = np.zeros((NZ, NX), np.uint8)
    for r in streets:
        cv2.polylines(strokes, [np.round(to_px(r["points"]) * 8).astype(np.int32)], False, 1, max(1, int(round((float(r.get("width", 5)) + 26.0) / STEP))), shift=3)
    k = int(round(22.0 / STEP))
    yy, xx = np.ogrid[-k:k + 1, -k:k + 1]
    town = ndimage.binary_closing(town | strokes.astype(bool), structure=(xx * xx + yy * yy <= k * k), border_value=0)
lakes = fill([l["points"] for l in plan.get("lakes", [])])
river_mask = np.zeros((NZ, NX), np.uint8)
river_depth = np.zeros((NZ, NX), np.float32)
for r in plan.get("rivers", []):
    w = float(r["width"])
    one = np.zeros((NZ, NX), np.uint8)
    cv2.polylines(one, [np.round(to_px(r["points"]) * 8).astype(np.int32)], False, 1, max(1, int(round(w / STEP))), shift=3)
    river_mask |= one
    # depth across the channel: deepest in the middle
    d_in = ndimage.distance_transform_edt(one) * STEP
    deep = 1.2 + min(0.6, max(0.0, (w - 3) * 0.1))
    river_depth = np.maximum(river_depth, (0.3 + (deep - 0.3) * np.clip(d_in / max(0.5, w / 2), 0, 1) ** 0.7) * one)
water = river_mask.astype(bool) | lakes
# a river that would have to climb (or drop) more than `edge_rise` to meet the game's ground where it leaves
# the map stops short of the edge instead, rising from (or ending in) a small spring pool
T.setdefault("edge_rise", 6.0)
edge_ring = np.zeros((NZ, NX), bool); edge_ring[0, :] = edge_ring[-1, :] = edge_ring[:, 0] = edge_ring[:, -1] = True
parts, _ = ndimage.label(water)
ends, n_ends = ndimage.label(water & edge_ring)
springs = []
for k in range(1, n_ends + 1):
    zz, xx = np.nonzero(ends == k)
    ez, ex = zz[len(zz) // 2], xx[len(xx) // 2]
    rise = float(real_here[ez, ex]) - 0.6 - WATER
    if abs(rise) <= float(T["edge_rise"]):
        continue
    cut_at = float(T["blend"]) + 15.0
    d = np.hypot(X - xs[ex], Z - zs[ez])
    mine = (parts == parts[ez, ex]) & ~lakes
    gone = mine & (d < cut_at)
    rim_cells = mine & (d >= cut_at) & (d < cut_at + 3.0)
    river_mask[gone] = 0; river_depth[gone] = 0.0
    if rim_cells.any():
        pz, px = np.nonzero(rim_cells)
        cx_, cz_ = xs[int(px.mean())], zs[int(pz.mean())]
        pool = np.hypot(X - cx_, Z - cz_) < 6.0
        lakes = lakes | pool
        springs.append((float(xs[ex]), float(zs[ez]), rise, float(cx_), float(cz_)))
water = river_mask.astype(bool) | lakes
from_water, (near_z, near_x) = ndimage.distance_transform_edt(~water, return_indices=True)
from_water = from_water * STEP

# ---- the water's surface: one level everywhere, except where a river runs off the map onto the game's
# higher or lower ground: there the surface rises or falls to just under that ground at the edge, over
# the blend (longer for a big rise, no steeper than 15%), like a stream coming down out of the hills ----
surface = np.full((NZ, NX), WATER, np.float32)
rim = np.zeros((NZ, NX), bool); rim[0, :] = rim[-1, :] = rim[:, 0] = rim[:, -1] = True
runs, n_runs = ndimage.label(water & rim)
exits = []
for k in range(1, n_runs + 1):
    zz, xx = np.nonzero(runs == k)
    ez, ex = zz[len(zz) // 2], xx[len(xx) // 2]
    rise = float(real_here[ez, ex]) - 0.6 - WATER
    if abs(rise) < 0.3:
        continue
    reach = max(float(T["blend"]), abs(rise) / 0.15)
    d = np.hypot(X - xs[ex], Z - zs[ez])
    surface += np.where(water, rise * (1 - smoothstep(0.0, reach, d)), 0.0).astype(np.float32)
    exits.append((float(xs[ex]), float(zs[ez]), rise, reach))
near_surface = surface[near_z, near_x]          # the water surface beside every cell (its own, on water)
T.setdefault("max_slope", 10.0)
KSLOPE = math.tan(math.radians(float(T["max_slope"]))) * STEP


def spread(seed, take_max, mask=None):
    """From the water outwards, a level that changes by at most the slope limit per metre: the highest
    (take_max) or lowest of every water cell's own surface, less (or plus) the slope times the distance."""
    out = np.where(water if mask is None else mask, seed, -np.inf if take_max else np.inf).astype(np.float32)
    for _ in range(600):
        before = out.copy()
        for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            n = np.roll(np.roll(out, dz, 0), dx, 1)
            step_ = KSLOPE * math.hypot(dz, dx)
            n = n - step_ if take_max else n + step_
            if dz == 1: n[0, :] = before[0, :]
            if dz == -1: n[-1, :] = before[-1, :]
            if dx == 1: n[:, 0] = before[:, 0]
            if dx == -1: n[:, -1] = before[:, -1]
            out = np.maximum(out, n) if take_max else np.minimum(out, n)
        with np.errstate(invalid="ignore"):
            moved = np.abs(np.where(np.isfinite(before) & np.isfinite(out), before - out, 0.0))
        if moved.max() < 0.005 and np.isfinite(out).sum() == np.isfinite(before).sum():
            break
    return out


water_up = spread(surface, True)      # land near water stands at least this high (falling away at the slope)
# and no higher than this (rising away at the slope from level water; the stretches running down to the
# map's edge only hold their banks up)
water_cap = spread(surface, False, water & (np.abs(surface - WATER) < 0.05))
from_town = ndimage.distance_transform_edt(~town) * STEP

# ---- shape it ----
country = smoothstep(10.0, 90.0, from_town)                  # hills grow away from the village
ground = BASE + (hills + roll * smoothstep(20.0, 120.0, from_town)) * country
floor_ = np.maximum(BASE, water_up + float(T["water_offset"]))
ground = floor_ + (ground - floor_) * smoothstep(0.0, float(T["valley"]), from_water)
def mound_shape(m):
    r = np.hypot(X - m["x"], Z - m["z"])
    top = m.get("top", 12.0)
    if m.get("profile") == "smooth":
        # (2026-11-19 play test: "the elevation should naturally level out as it gets to the top, rather than being
        # like a set degree incline and then transitioning to a smaller incline") smoothstep over the whole radius:
        # the slope grows from the foot, is steepest halfway, and eases away to a rounded top
        return m["height"] * smoothstep(0.0, 1.0, 1.0 - r / m["radius"])
    if m.get("profile") == "gentle":
        # a steady slope with rounded shoulders: steepest about 1.25 x the average (smoothstep's is 1.5 x)
        u = np.clip((r - top) / max(1e-6, m["radius"] - top), 0.0, 1.0)
        w = 0.2
        f = np.where(u < w, 1.0 - u * u / (2 * w * (1 - w)), np.where(u > 1 - w, (1 - u) ** 2 / (2 * w * (1 - w)), 1.0 - (u - w / 2) / (1 - w)))
        return m["height"] * f
    return m["height"] * (1 - smoothstep(top, m["radius"], r))
for m in T["mounds"] + [m for m in NOTE_MOUNDS if not m.get("town")]:
    ground += mound_shape(m)
ground[from_town <= 10] = BASE
for m in NOTE_MOUNDS:
    if m.get("town"):
        ground += mound_shape(m)
# level pads for buildings in the countryside
names = {}
town_js = open(HERE + "/data/town.js", encoding="utf-8").read()
TOWN = json.loads(town_js[town_js.index("{"):town_js.rindex("}") + 1])
scen = {s["id"]: s for s in TOWN["scenery"]}
pads = []
for l in plan.get("landmarks", []):
    s = scen.get(l["id"])
    if not s or l["id"] == "cloudominium_01" or not s.get("footprint"):
        continue
    reach = max(math.dist(p, (s["x"], s["z"])) for p in s["footprint"])
    pads.append((l["x"], l["z"], reach, T.get("pad_levels", {}).get(l["id"])))
for h in plan.get("houses", []):
    d = TOWN["designs"][h["design"]]
    sc = h.get("scale") or d["scale"]
    pads.append((h["x"], h["z"], max(math.hypot(p[0] * sc, p[1] * sc) for p in d["footprint"]), None))
for x, z, reach, own_level in pads:
    r = np.hypot(X - x, Z - z)
    if from_town[min(NZ - 1, max(0, int((z - z0) / STEP))), min(NX - 1, max(0, int((x - x0) / STEP)))] <= 10:
        continue
    core = r <= reach + 2
    if not core.any():
        continue
    level_at = float(np.median(ground[core])) if own_level is None else float(own_level)
    t = 1 - smoothstep(reach + 2, reach + 16, r)
    ground = ground * (1 - t) + level_at * t
# nothing steeper than `max_slope`: hilltops are shaved (only ever lowered) until no slope is steeper
rise = math.tan(math.radians(float(T["max_slope"]))) * STEP
ground = ground.astype(np.float32)
for _ in range(400):
    before = ground.copy()
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        n = np.roll(np.roll(ground, dz, 0), dx, 1)
        lim = n + rise * math.hypot(dz, dx)
        if dz == 1: lim[0, :] = np.inf
        if dz == -1: lim[-1, :] = np.inf
        if dx == 1: lim[:, 0] = np.inf
        if dx == -1: lim[:, -1] = np.inf
        ground = np.minimum(ground, lim)
    if np.abs(before - ground).max() < 0.01:
        break
# the banks never drop below the water plus half a metre, then the water is cut in
# ---- rises on the greens (2026-11-19 play test: small hills in and round the town, each its own shape, fitted
# into the ground): a green (lawn) with "rise" (metres) swells to that height inside its own outline, highest
# where it is furthest from its edge (and from anything it must keep clear of), easing to nothing at the edge with
# no step, its top rounded. It keeps clear of houses, landmarks, streets, paths and water by CLEAR m; where the
# green is too narrow for a slope no steeper than max_slope, it rises less (the build reports it).
# (small rises may be steeper than the countryside: up to LAND_SLOPE_DEG, still an easy walk for a pony; they are
# made after the slope limit below, so it does not shave them)
LAND_CLEAR = 1.5
LAND_SLOPE_DEG = 15.0
LAND_SLOPE = math.tan(math.radians(LAND_SLOPE_DEG))
landform_report = []
greens_up = [g for g in plan.get("greens", []) if float(g.get("rise", 0) or 0) > 0]
if greens_up:
    keep = np.zeros((NZ, NX), np.uint8)
    tj_ = open(HERE + "/data/town.js", encoding="utf-8").read()
    designs_ = json.loads(tj_[tj_.index("{"):tj_.rindex("}") + 1])["designs"]
    for h in plan.get("houses", []):
        d = designs_[h["design"]]; sc = h.get("scale") or d["scale"]
        reach = max(math.hypot(q[0] * sc, q[1] * sc) for q in d["footprint"])
        cv2.circle(keep, tuple(np.round(to_px([[h["x"], h["z"]]])[0] * 8).astype(int)), int(round((reach + 2.5) / STEP * 8)), 1, -1, shift=3)
    for l in plan.get("landmarks", []):
        cv2.circle(keep, tuple(np.round(to_px([[l["x"], l["z"]]])[0] * 8).astype(int)), int(round(8.0 / STEP * 8)), 1, -1, shift=3)
    for r in plan.get("roads", []) + plan.get("bridges", []):
        pts = r.get("points") or []
        if len(pts) >= 2:
            cv2.polylines(keep, [np.round(to_px(pts) * 8).astype(np.int32)], False, 1, max(1, int(round((float(r.get("width", 4)) + 2 * LAND_CLEAR) / STEP))), shift=3)
    blocked = keep.astype(bool) | ndimage.binary_dilation(water, iterations=max(1, int(round(4.0 / STEP))))
    lift = np.zeros((NZ, NX), np.float32)
    for gi, g in enumerate(plan.get("greens", [])):
        want = float(g.get("rise", 0) or 0)
        if want <= 0:
            continue
        inside = fill([g["points"]]) & ~blocked
        if not inside.any():
            landform_report.append((gi, want, 0.0)); continue
        d = ndimage.distance_transform_edt(inside) * STEP
        room = float(d.max())
        # the widest rise its outline allows: smoothstep's steepest is 1.5 x its average
        height = min(want, room * LAND_SLOPE / 1.5)
        if height < 0.25:
            landform_report.append((gi, want, 0.0)); continue
        run = height * 1.5 / LAND_SLOPE
        shape = height * smoothstep(0.0, 1.0, np.minimum(d / run, 1.0))
        # a little life: a slow swell across it, so no two are alike and the top is not dead level
        seed = int(g.get("seed", gi))
        noise = np.random.default_rng(seed).normal(0, 1, (NZ // 8 + 2, NX // 8 + 2)).astype(np.float32)
        noise = cv2.resize(cv2.GaussianBlur(noise, (0, 0), 2.0), (NX, NZ), interpolation=cv2.INTER_CUBIC)
        shape *= np.clip(1.0 + 0.12 * noise, 0.8, 1.2)
        lift = np.maximum(lift, shape)
        landform_report.append((gi, want, round(height, 2)))
    ground = ground + lift
    short = [r for r in landform_report if r[2] < r[1] - 0.05]
    print(f"greens risen: {sum(1 for r in landform_report if r[2] > 0)} of {len(landform_report)}" +
          (f"; lower than asked (too narrow for a gentle slope): " + ", ".join(f"#{i} {w} -> {h} m" for i, w, h in short) if short else ""))
    T["landform_report"] = [{"green": i, "asked": w, "made": h} for i, w, h in landform_report]
ground = np.where(water, ground, np.maximum(ground, water_up + 0.5))
T.setdefault("lake_depth", 6.0)         # metres at the deepest; lakes shelve down from 0.3 m at the shore
lake_deep = np.minimum(float(T["lake_depth"]), 0.3 + ndimage.distance_transform_edt(lakes) * STEP * 0.25) * lakes
# a bog is shallow all over; a spring pool is a pony's depth at most
shallow = [(l["points"], 0.9 if l.get("bog") else 1.6) for l in plan.get("lakes", []) if l.get("bog") or l.get("spring")]
for pts, cap in shallow:
    one = fill([pts])
    lake_deep[one] = np.minimum(lake_deep[one], cap)
bed = surface - np.maximum(river_depth, lake_deep)
ground = np.where(water, np.minimum(ground, bed), ground)
# meet the game's ground at the edge
inner = np.minimum.reduce([X - x0, x1 - X, Z - z0, z1 - Z])
t = smoothstep(0.0, float(T["blend"]), inner)
ground = real_here * (1 - t) + ground * t
# where the game's ground outside is lower than the water, the banks are held up to the edge so the
# rivers stay in their channels all the way out
hold = (from_water <= float(T["valley"])) & ~water
shore_cap = water_cap - 0.3
ground = np.where(hold, np.maximum(ground, np.minimum(water_up + 0.5, shore_cap)), ground)
ground = np.where(water, np.minimum(np.maximum(ground, bed), surface - 0.3), ground)
# shores slope into the water instead of standing as a wall: no higher than a `max_slope` rise from 0.3 m
# under the water at its edge (the water surface reaches 2 m under the bank, where the ground has just
# come up through it; a hill by the water is cut back to the same slope)
ground = np.where(~water, np.minimum(ground, shore_cap), ground)
# the last 12 m meet the game's ground exactly, whatever the shores and banks did to them
seam = smoothstep(0.0, 12.0, inner)
ground = np.where(water, ground, real_here * (1 - seam) + ground * seam)
# every bank rises out of its own river's water, even where the river runs downhill to the map's edge
ground = np.where(~water & (from_water <= 4.0), np.maximum(ground, near_surface - 0.3 + KSLOPE / STEP * from_water), ground)

# the pads again, last: the valley and shore steps above tilt the ground under a building that stands near water
# (Fluttershy's cottage by its stream stood 1.6 m proud of its low side); level where it stands, eased out over 7 m
for x, z, reach, own_level in pads:
    if from_town[min(NZ - 1, max(0, int((z - z0) / STEP))), min(NX - 1, max(0, int((x - x0) / STEP)))] <= 10:
        continue
    r = np.hypot(X - x, Z - z)
    core = (r <= reach + 1) & ~water
    if not core.any():
        continue
    level_at = float(np.median(ground[core])) if own_level is None else float(own_level)
    t = (1 - smoothstep(reach + 1, reach + 8, r)) * smoothstep(1.0, 4.0, from_water)
    ground = np.where(water, ground, ground * (1 - t) + level_at * t)

# the pads' edges are eased last: where a pad was levelled into a hillside the hill stood over it as a scarp (30
# degrees and more, trees hanging off it); the ground round each pad is shaved (only ever lowered) to `pad_slope`,
# the pads themselves and the banks within 6 m of water staying as they are
T.setdefault("pad_slope", 14.0)
fixed = water | (from_water <= 6.0)
for x, z, reach, _ in pads:
    fixed |= np.hypot(X - x, Z - z) <= reach + 1
keep = ground.copy()
ease = math.tan(math.radians(float(T["pad_slope"]))) * STEP
near_pad = np.zeros((NZ, NX), bool)
for x, z, reach, _ in pads:
    near_pad |= np.hypot(X - x, Z - z) <= reach + 45
for _ in range(120):
    before = ground.copy()
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        n = np.roll(np.roll(ground, dz, 0), dx, 1)
        lim = n + ease * math.hypot(dz, dx)
        if dz == 1: lim[0, :] = np.inf
        if dz == -1: lim[-1, :] = np.inf
        if dx == 1: lim[:, 0] = np.inf
        if dx == -1: lim[:, -1] = np.inf
        ground = np.where(near_pad & ~fixed & (inner > 12.0), np.minimum(ground, lim), ground)
    if np.abs(before - ground).max() < 0.01:
        break
# a bridge's two feet stand on level ground at one height (its deck is a level arch: a bridge laid from a low bank
# to a high one was too steep to climb, and one foot hung in the air), eased out over 5 m; not the bank's last
# 2 m, which slope into the water
for b in plan.get("bridges", []):
    at = [(int(round((e[1] - z0) / STEP)), int(round((e[0] - x0) / STEP))) for e in (b["a"], b["b"])]
    if not all(0 <= i < NZ and 0 <= j < NX for i, j in at):
        continue
    # the height of the land each foot leads onto: 5 m on from the foot, past the bank's slope to the water
    span = math.dist(b["a"], b["b"])
    on = [(e[0] + (e[0] - o[0]) / span * 5.0, e[1] + (e[1] - o[1]) / span * 5.0) for e, o in ((b["a"], b["b"]), (b["b"], b["a"]))]
    level_at = max(float(ground[min(NZ - 1, max(0, int(round((q[1] - z0) / STEP)))), min(NX - 1, max(0, int(round((q[0] - x0) / STEP))))]) for q in on)
    for e in (b["a"], b["b"]):
        r = np.hypot(X - e[0], Z - e[1])
        t = (1 - smoothstep(2.5, 7.5, r)) * smoothstep(0.5, 2.0, from_water)
        ground = np.where(water, ground, ground * (1 - t) + level_at * t)
# a building made to stand on a low plinth with steps down its front (the Town Hall: its floor is 0.9 m over the
# foot of its steps, where a pony stands to go in; on flat ground that spot lay 0.9 m under the square): the
# ground is raised under it, falling away over 2.2 m round its sides and back, and cut straight down to the
# square across its front, where the steps come down
for s in T.get("plinths", []):
    r = np.hypot(X - s["x"], Z - s["z"])
    off = np.abs((np.arctan2(X - s["x"], Z - s["z"]) - s["front"] + np.pi) % (2 * np.pi) - np.pi)      # the angle from its front
    front = 1 - smoothstep(math.radians(32), math.radians(55), off)
    R = float(s["radius"])
    side = 1 - smoothstep(R, R + 2.2, r)
    ahead = 1 - smoothstep(R - 1.4, R - 0.2, r)
    ground = np.where(water, ground, ground + float(s["height"]) * (side * (1 - front) + ahead * front))
# a door whose sill stands a step above the ground: the ground rises gently to it, outside the door only
for s in T.get("door_slopes", []):
    r = np.hypot(X - s["x"], Z - s["z"])
    outward = (X - s["x"]) * s["out"][0] + (Z - s["z"]) * s["out"][1]
    lift = float(s["rise"]) * (1 - smoothstep(1.2, float(s["reach"]), r)) * smoothstep(-2.2, -0.7, outward)
    ground = np.where(water, ground, ground + lift)
ground = ground.astype(np.float32)

# ---- checks ----
gy, gx2 = np.gradient(ground, STEP)
slope = np.degrees(np.arctan(np.hypot(gx2, gy)))
dry = ~ndimage.binary_dilation(water, iterations=4) & (inner > float(T["blend"]))
print(f"ground {ground.min():.1f} .. {ground.max():.1f} m; village {BASE} m; water level {WATER} m")
print(f"slope on dry land inside the blend: median {np.median(slope[dry]):.1f} deg, 99% under {np.percentile(slope[dry], 99):.1f}, steepest {slope[dry].max():.1f}")
sy, sx = np.unravel_index(np.argmax(np.where(dry, slope, 0)), slope.shape)
print(f"countryside heights inside the blend: {ground[dry].min() - BASE:.1f} .. {ground[dry].max() - BASE:.1f} m above the village")
print(f"steepest dry spot at x {xs[sx]:.0f}, z {zs[sy]:.0f}")
print(f"water cells {int(water.sum())} m2; all beds below the water: {bool((ground[water] < surface[water] - 0.2).all())}")
banks = ndimage.binary_dilation(water, iterations=7) & ~ndimage.binary_dilation(water, iterations=6)
print(f"dry land 6-7 m from the water: lowest {(ground - near_surface)[banks].min():.2f} m")
# the same, lake by lake and river end by river end: a pool whose bank falls below its water is standing on a slope
low = (ground - near_surface) * banks + 99.0 * ~banks
for l in plan.get("lakes", []):
    cx = sum(p[0] for p in l["points"]) / len(l["points"]); cz = sum(p[1] for p in l["points"]) / len(l["points"])
    reach = max(math.dist(p, (cx, cz)) for p in l["points"]) + 8
    near = np.hypot(X - cx, Z - cz) <= reach
    if near.any() and low[near].min() < -0.3:
        print(f"  bank below the water round {l.get('name') or 'a lake'} at ({cx:.0f}, {cz:.0f}): {low[near].min():.2f} m")
zz, xx = np.nonzero(low < -0.3)
if len(zz):
    print(f"  banks below the water: {len(zz)} cells, x {xs[xx.min()]:.0f}..{xs[xx.max()]:.0f}, z {zs[zz.min()]:.0f}..{zs[zz.max()]:.0f}")
for x, z, rise, cx_, cz_ in springs:
    print(f"  river at the map's edge ({x:.0f}, {z:.0f}) would {'climb' if rise > 0 else 'drop'} {abs(rise):.1f} m to the ground outside: it {'rises from' if rise > 0 else 'ends in'} a spring pool at ({cx_:.0f}, {cz_:.0f}) instead")
for x, z, rise, reach in exits:
    print(f"  river leaving the map at ({x:.0f}, {z:.0f}): its surface {'rises' if rise > 0 else 'falls'} {abs(rise):.1f} m over the last {reach:.0f} m to meet the ground outside")
if cottage:
    i, j = int((cottage["z"] - z0) / STEP), int((cottage["x"] - x0) / STEP)
    print(f"Fluttershy's cottage stands {ground[i, j] - BASE:.1f} m above the village")

# ---- store a 2 m copy in the plan ----
k = int(round(2.0 / STEP))
g2 = ground[::k, ::k]
low, high = float(g2.min()), float(g2.max())
q = np.round((g2 - low) / ((high - low) or 1) * 65535).astype("<u2")
T.update({"origin": [float(x0), float(z0)], "step": 2.0, "columns": int(g2.shape[1]), "rows": int(g2.shape[0]),
          "low": round(low, 3), "high": round(high, 3), "heights": base64.b64encode(q.tobytes()).decode()})
plan["edges"][0]["height"] = BASE
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))

if EXPORT:
    import os
    os.makedirs(EXPORT, exist_ok=True)
    ground.astype("<f4").tofile(os.path.join(EXPORT, "ground.f32"))
    water.astype(np.uint8).tofile(os.path.join(EXPORT, "water.u8"))
    near_surface.astype("<f4").tofile(os.path.join(EXPORT, "surface.f32"))   # the water surface, carried to every cell
    json.dump({"origin": [float(x0), float(z0)], "step": STEP, "columns": NX, "rows": NZ, "water_level": WATER, "base": BASE,
               "blend": float(T["blend"])}, open(os.path.join(EXPORT, "grid.json"), "w"), indent=1)
    print("exported", NX, "x", NZ, "to", EXPORT)

if PREVIEW:
    shade = cv2.normalize(ground, None, 0, 1, cv2.NORM_MINMAX)
    light = np.clip(0.6 + (-gx2 - gy) * 0.35, 0, 1.4)
    col = np.dstack([0.35 + 0.4 * shade, 0.55 + 0.35 * shade, 0.3 + 0.2 * shade]) * light[..., None]
    col[water] = (0.25, 0.45, 0.8)
    col[town & ~water] *= (0.85, 1.0, 0.95)
    lines = (np.floor((ground - BASE) / 1.0) != np.floor((np.roll(ground, 1, 0) - BASE) / 1.0)) & ~water
    col[lines] *= 0.75
    cv2.imwrite(PREVIEW, cv2.resize((np.clip(col, 0, 1)[..., ::-1] * 255).astype(np.uint8), None, fx=0.75, fy=0.75, interpolation=cv2.INTER_AREA))
