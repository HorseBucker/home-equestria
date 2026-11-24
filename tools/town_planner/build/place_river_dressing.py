"""Reeds, shore grass and stones along Ponyville's streams and lakes (2026-11-24 play test: "more natural clusters
of rocks, reeds/cattails, and shoreline grass tufts - especially around river forks, bends, and near bridges").

usage: python tools/town_planner/build/place_river_dressing.py <project>
(after fix_shore.py, whose smooth shore distance it follows; after make_river_dressing.gd, whose kinds it places;
again after plan_props.py, which rewrites placements.json's rows inside the plan's edge)

Writes kit rows (group "river", ids *_rvNNNN, not blocking, so no pony is stopped by them) into
world/props/ponyville_kit/placements.json, which every town density shares. Clusters, not a scatter:
- where the water forks, at its sharp bends, and beside each bridge's feet, a cluster of HOT_ITEMS;
- along the rest of every bank, a small cluster every ALONG m or so, on one bank or the other, some stretches bare;
each cluster a mix by place on the bank: reeds at the waterline (from a little in the water to 0.6 m out), shore
grass on the damp bank behind them, stones half in the water. Nothing on a street, square or dirt road, under or
on a bridge (BRIDGE_CLEAR m round its deck), on the fishing dock, near a house of any density, a landmark, a tree, a
lamp, a bench or another kit row. Seeded, the same every run.
"""
import json, math, os, re, sys

import cv2
import numpy as np
from scipy import ndimage

ROOT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
ALONG = 11.0
HOT_ITEMS = (5, 9)
BRIDGE_CLEAR = 1.2
# (2026-11-24 second pass: the stones on the waterline and the bed, not up on the grass)
SPOTS = {"reed_clump": (-0.25, 0.6), "shore_grass": (0.6, 1.8), "river_rocks": (-0.6, 0.35), "river_pebbles": (-0.9, 0.1)}
RADIUS = {"reed_clump": 0.45, "shore_grass": 0.35, "river_rocks": 0.5, "river_pebbles": 0.2}
rng = np.random.default_rng(2411)

grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
s = np.load(os.path.join(OUT, "shore_distance.npy"))
ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
DESIGNS = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])["designs"]
plan = json.load(open(os.path.join(HERE, "..", "ponyville_planV28_high.json"), encoding="utf-8"))

# ---- where nothing goes ----
block = np.zeros((NZ, NX), np.uint8)
px = lambda pts: np.round((np.array(pts, np.float64) - [X0, Z0]) * 8).astype(np.int32)
for g in plan.get("grounds", []):
    cv2.fillPoly(block, [px(g["points"])], 1, shift=3)
for r in plan.get("roads", []):
    cv2.polylines(block, [px(r["points"])], False, 1, max(1, int(round(float(r.get("width", 4)) + 2))), shift=3)
for b in plan.get("bridges", []):
    a_, b_ = np.array(b["a"], float), np.array(b["b"], float); u = (b_ - a_) / max(1e-6, np.linalg.norm(b_ - a_))
    cv2.polylines(block, [px([a_ - u * 1.5, b_ + u * 1.5])], False, 1, int(round(float(b["width"]) + 2 * BRIDGE_CLEAR)), shift=3)
for setting in ("high", "medium", "low", "minimum"):
    p = json.load(open(os.path.join(HERE, "..", f"ponyville_planV28_{setting}.json"), encoding="utf-8"))
    for h in p["houses"]:
        d = DESIGNS.get(h["design"])
        if not d or "footprint" not in d:
            continue
        k = h.get("scale") or d["scale"]; c, s_ = math.cos(h["yaw"]), math.sin(h["yaw"])
        xs = [q[0] * k for q in d["footprint"]]; zs = [q[1] * k for q in d["footprint"]]
        x0, x1, z0, z1 = min(xs) - 2, max(xs) + 2, min(zs) - 2, max(zs) + 3
        cv2.fillPoly(block, [px([[h["x"] + x * c + z * s_, h["z"] - x * s_ + z * c] for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))])], 1, shift=3)
for m in plan.get("landmarks", []):
    cv2.circle(block, tuple(int(v) for v in px([[m["x"], m["z"]]])[0]), 9 * 8, 1, -1, shift=3)
dock = json.load(open(os.path.join(ROOT, "world/minigames/fishing/dock_spec.json")))
o, bd = np.array(dock["origin"])[[0, 2]], np.array(dock["bank_direction"])[[0, 2]]
cv2.polylines(block, [px([o - bd * 2, o + bd * (dock["length"] + 2)])], False, 1, int(dock["width"] + 4), shift=3)
block = block.astype(bool)
props = json.load(open(os.path.join(OUT, "props.json")))
points = [(p["x"], p["z"], 1.2) for p in props["outdoor"]] + [(t["x"], t["z"], 1.5) for t in props["trees"]]
for setting in ("high", "medium", "low", "minimum"):
    tp = os.path.join(OUT, f"trees_{setting}.json")
    if os.path.exists(tp):
        points += [(t["x"], t["z"], 1.5) for t in json.load(open(tp))["trees"]]
kit_path = os.path.join(ROOT, "world/props/ponyville_kit/placements.json")
raw = open(kit_path, encoding="utf-8").read()
kit = json.loads(raw)
kit["entries"] = [e for e in kit["entries"] if e.get("group") != "river"]
for path in [kit_path] + [os.path.join(ROOT, f"world/props/ponyville_kit/density/{d}.json") for d in ("medium", "low", "minimum")]:
    for e in json.load(open(path, encoding="utf-8"))["entries"]:
        if e.get("group") != "river":
            points.append((float(e["x"]), float(e["z"]), 0.8))
pts_arr = np.array([(x, z) for x, z, _ in points]); pts_r = np.array([r for _, _, r in points])


def cell(x, z):
    return int(round(z)) - Z0, int(round(x)) - X0


def sample_s(x, z):
    """The shore distance at (x, z), bilinear."""
    fx, fz = x - X0, z - Z0
    c0, r0 = int(math.floor(fx)), int(math.floor(fz))
    if not (0 <= r0 < NZ - 1 and 0 <= c0 < NX - 1):
        return 99.0
    tx, tz = fx - c0, fz - r0
    return float(s[r0, c0] * (1 - tx) * (1 - tz) + s[r0, c0 + 1] * tx * (1 - tz) + s[r0 + 1, c0] * (1 - tx) * tz + s[r0 + 1, c0 + 1] * tx * tz)


placed = []


def ground_at(x, z):
    """The ground at (x, z), bilinear."""
    fx, fz = x - X0, z - Z0
    c0, r0 = int(math.floor(fx)), int(math.floor(fz))
    tx, tz = fx - c0, fz - r0
    return float(ground[r0, c0] * (1 - tx) * (1 - tz) + ground[r0, c0 + 1] * tx * (1 - tz) + ground[r0 + 1, c0] * (1 - tx) * tz + ground[r0 + 1, c0 + 1] * tx * tz)


def free(x, z, r):
    r_, c_ = cell(x, z)
    if not (12 <= r_ < NZ - 12 and 12 <= c_ < NX - 12) or block[r_, c_]:
        return False
    if len(pts_arr) and (np.hypot(pts_arr[:, 0] - x, pts_arr[:, 1] - z) < pts_r).any():
        return False
    return all(math.dist((x, z), (px_, pz_)) >= r + pr for px_, pz_, pr in placed)


def put(kind, x, z, near_x, near_z, tries=40):
    """`kind` near (near_x, near_z) on its band of the shore, or nothing."""
    lo, hi = SPOTS[kind]
    for _ in range(tries):
        a = rng.uniform(0, math.tau); d = rng.uniform(0, 1.6)
        cx, cz = near_x + math.cos(a) * d, near_z + math.sin(a) * d
        sd = sample_s(cx, cz)
        if not (lo <= sd <= hi) or not free(cx, cz, RADIUS[kind]):
            continue
        r_, c_ = cell(cx, cz)
        # stones sit on the lowest ground under them, so on a bank none hangs over its downhill side
        y = float(ground[r_, c_])
        if kind in ("river_rocks", "river_pebbles"):
            rad = RADIUS[kind]
            y = min(ground_at(cx + dx * rad, cz + dz * rad) for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)))
        placed.append((cx, cz, RADIUS[kind]))
        rows.append({"blocking": False, "group": "river", "id": f"{kind}_rv{len(rows):04d}", "kind": kind, "origin": "base",
                     "radius": RADIUS[kind], "x": round(cx, 3), "y": round(y, 3), "yaw": round(float(rng.uniform(0, math.tau)), 4), "z": round(cz, 3)})
        return True
    return False


def cluster(x, z, items):
    kinds = ["reed_clump"] * 5 + ["shore_grass"] * 4 + ["river_rocks"] * 2 + ["river_pebbles"] * 2
    n = 0
    for k in range(items):
        kind = kinds[int(rng.integers(len(kinds)))] if k else "reed_clump"
        n += put(kind, x, z, x, z)
    return n


rows = []
# ---- hot spots: forks (a river's end on another's water), sharp bends, bridges' feet ----
hot = []
rivers = plan.get("rivers", [])
for i, r in enumerate(rivers):
    pts = r["points"]
    for end in (pts[0], pts[-1]):
        for j, o in enumerate(rivers):
            if j != i and any(math.dist(end, q) < float(o["width"]) + 3 for q in o["points"]):
                hot.append(end); break
    for k in range(1, len(pts) - 1):
        a, b, c = np.array(pts[k - 1]), np.array(pts[k]), np.array(pts[k + 1])
        u, v = b - a, c - b
        if np.linalg.norm(u) > 0 and np.linalg.norm(v) > 0 and np.degrees(math.acos(np.clip(u.dot(v) / np.linalg.norm(u) / np.linalg.norm(v), -1, 1))) > 28:
            hot.append(list(b))
for b in plan.get("bridges", []):
    a_, b_ = np.array(b["a"], float), np.array(b["b"], float); u = (b_ - a_) / max(1e-6, np.linalg.norm(b_ - a_))
    side = np.array([-u[1], u[0]])
    for foot in (a_, b_):
        for sgn in (1, -1):
            hot.append(list(foot + side * sgn * (float(b["width"]) / 2 + BRIDGE_CLEAR + 1.2)))
hot_n = 0
for x, z in hot:
    # the cluster's middle at the waterline near the spot
    best = None
    for _ in range(30):
        cx, cz = x + rng.uniform(-3, 3), z + rng.uniform(-3, 3)
        sd = sample_s(cx, cz)
        if abs(sd - 0.2) < 0.5 and free(cx, cz, 0.3):
            best = (cx, cz); break
    if best:
        hot_n += cluster(best[0], best[1], int(rng.integers(HOT_ITEMS[0], HOT_ITEMS[1] + 1)))
# ---- along the banks: the waterline traced, a small cluster every ALONG m or so on a bank ----
line = (np.abs(s) < 0.5) & ~block
_, n_lines = ndimage.label(line)
zz, xx = np.nonzero(line)
order = rng.permutation(len(zz))
taken = []
along_n = 0
for i in order:
    x, z = float(xx[i] + X0), float(zz[i] + Z0)
    if any(math.dist((x, z), t) < ALONG for t in taken):
        continue
    taken.append((x, z))
    if rng.random() < 0.3:           # some stretches bare
        continue
    along_n += cluster(x, z, int(rng.integers(2, 5)))
kit["entries"].extend(rows)
out = json.dumps(kit, indent="\t") + ("\n" if raw.endswith("\n") else "")
open(kit_path, "w", encoding="utf-8", newline="\n").write(out)
from collections import Counter
print(f"river dressing: {len(rows)} rows ({dict(Counter(r['kind'] for r in rows))}), {hot_n} at {len(hot)} forks, bends and bridges, {along_n} along the banks")
