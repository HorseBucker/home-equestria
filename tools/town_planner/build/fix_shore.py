"""Natural shorelines (2026-11-23 player report: "The river edges look really rough"; play test the same day: "It
needs to be considerably smoothed out and look natural").

usage: python tools/town_planner/build/fix_shore.py <project>
then:  godot --headless --xr-mode off --path . --script res://tools/town_planner/build/apply_ground_half.gd
and the repaint (README), whose river bed now follows the waterline this makes.

elevation.py cuts the water into the ground cell by cell on its 1 m grid, and apply_ground.py lays the water surface on
the same cells, so where a river runs on a slant its bank and its surface's edge step a metre at a time: a sawtooth.
This reshapes every shore from a smooth outline of the water instead: the signed distance to the plan's rivers
and lakes drawn four times finer, whose zero line is a smooth curve. Across the shore the ground follows that distance: down into the
water at BED_SLOPE down to DEEP m, up out of it at BANK_SLOPE (a low lip, as a stream's
bank has) until it meets the land beyond (the old ground away from the water, smoothed), blending back into the old
ground over the last metres of the band. The ground under houses, landmarks and bridges' feet stays as it was.
Writes, for every town density: the build's ground grid (build/out[/density_<setting>]/ground.f32) and the published
sculpt overlays (world/terrain/sculpt/<region>/ponyville_overhaul_20261113[_<setting>]/height.f32); and the water
surface (world/water/ponyville_canals.json) over the new outline, reaching 2 m under the banks as before.
Run once, on the ground apply_ground.py wrote.
"""
import base64, json, math, os, sys

import cv2
import numpy as np
from scipy import ndimage

ROOT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TAG = "ponyville_overhaul_20261113"
REGION = 1024
BANK_SLOPE = 0.32      # rise per metre out of the water (0.6 until 2026-11-24's second pass: "less trench-like")
BED_SLOPE = 0.7        # fall per metre into it (0.8, then 0.5; 2026-11-24 third pass: "deepen the carved riverbed slightly")
DEEP = 1.4
BAND_DRY, FADE_DRY = 5.0, 2.0
BAND_WET, FADE_WET = 2.5, 1.5

grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
level = np.fromfile(os.path.join(OUT, "surface.f32"), "<f4").reshape(NZ, NX)

# ---- the smooth outline: the plan's rivers and lakes drawn SS times finer, their signed distance read at each cell
# (rivers keep their width; a blur of the cells' own distance narrowed the 3 m streams to 1 m). Held within OFF m of
# the water's cells, which also has the springs and the river ends elevation.py cut, and softened a little. ----
SS, OFF = 4, 1.0
d_out = ndimage.distance_transform_edt(~water); d_in = ndimage.distance_transform_edt(water)
cells = np.where(water, -(d_in - 0.5), d_out - 0.5).astype(np.float32)
plan = json.load(open(os.path.join(HERE, "..", "ponyville_planV28_high.json"), encoding="utf-8"))
fine = np.zeros((NZ * SS, NX * SS), np.uint8)
hp = lambda pts: np.round((np.array(pts, np.float64) - [X0, Z0]) * SS * 8).astype(np.int32)
for r in plan.get("rivers", []):
    cv2.polylines(fine, [hp(r["points"])], False, 1, max(1, int(round(float(r["width"]) * SS))), shift=3)
for lake in plan.get("lakes", []):
    cv2.fillPoly(fine, [hp(lake["points"])], 1, shift=3)
fine = fine.astype(bool)
traced = ((ndimage.distance_transform_edt(~fine) - ndimage.distance_transform_edt(fine)) / SS)[::SS, ::SS].astype(np.float32)
del fine
s = ndimage.gaussian_filter(np.clip(traced, cells - OFF, cells + OFF), 0.6)
_, (nz_, nx_) = ndimage.distance_transform_edt(~water, return_indices=True)
W = level[nz_, nx_]                                    # the level of the nearest water

# ---- where the shore may change ----
w = np.ones((NZ, NX), np.float32)
t = np.clip((s - BAND_DRY) / FADE_DRY, 0, 1); w *= 1 - t * t * (3 - 2 * t)
t = np.clip((-s - BAND_WET) / FADE_WET, 0, 1); w *= 1 - t * t * (3 - 2 * t)
keep = np.zeros((NZ, NX), np.uint8)
px = lambda pts: np.round((np.array(pts, np.float64) - [X0, Z0]) * 8).astype(np.int32)
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
DESIGNS = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])["designs"]
FOOTPRINTS = {}


def _feet(node):
    if isinstance(node, dict):
        if node.get("id") and node.get("footprint"):
            FOOTPRINTS[node["id"]] = node["footprint"]
        for v in node.values():
            _feet(v)
    elif isinstance(node, list):
        for v in node:
            _feet(v)


_feet(json.load(open(os.path.join(ROOT, "world/props/ponyville/rnl_scenery.json"), encoding="utf-8")))
landmark_feet = np.zeros((NZ, NX), np.uint8)
for setting in ("high", "medium", "low", "minimum"):
    plan = json.load(open(os.path.join(HERE, "..", f"ponyville_planV28_{setting}.json"), encoding="utf-8"))
    for h in plan["houses"]:
        d = DESIGNS.get(h["design"])
        if not d or "footprint" not in d:
            continue
        k = h.get("scale") or d["scale"]; c, s_ = math.cos(h["yaw"]), math.sin(h["yaw"])
        xs = [p[0] * k for p in d["footprint"]]; zs = [p[1] * k for p in d["footprint"]]
        x0, x1, z0, z1 = min(xs) - 1.5, max(xs) + 1.5, min(zs) - 1.5, max(zs) + 1.5
        cv2.fillPoly(keep, [px([[h["x"] + x * c + z * s_, h["z"] - x * s_ + z * c] for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))])], 1, shift=3)
    for m in plan.get("landmarks", []):
        # its own footprint (the baked scenery's, rnl_scenery.json) and 0.75 m round it (its base is drawn to it); an 8 m circle
        # (until 2026-11-24) kept the old cliff of the lake beside the farmyard's windmill, whose base stands 2.5 m from
        # the water, flush with the water ("the water is coming up higher than the bank in that spot")
        foot = FOOTPRINTS.get(m["id"])
        if foot:
            cv2.fillPoly(landmark_feet, [px(foot)], 1, shift=3)
        else:
            cv2.circle(keep, tuple(int(v) for v in px([[m["x"], m["z"]]])[0]), 8 * 8, 1, -1, shift=3)
    for b in plan.get("bridges", []):
        for end in (b["a"], b["b"]):
            cv2.circle(keep, tuple(int(v) for v in px([end])[0]), int(3.5 * 8), 1, -1, shift=3)
keep |= (ndimage.distance_transform_edt(~landmark_feet.astype(bool)) <= 0.75).astype(np.uint8)
# the streets and roads beside the water, too (the wider, gentler banks would tilt their edges), but not where one
# crosses the water at a bridge
roads_ = np.zeros((NZ, NX), np.uint8)
for r in json.load(open(os.path.join(HERE, "..", "ponyville_planV28_high.json"), encoding="utf-8")).get("roads", []):
    cv2.polylines(roads_, [px(r["points"])], False, 1, max(1, int(round(float(r.get("width", 4)) + 1))), shift=3)
keep = keep.astype(bool) | (roads_.astype(bool) & (s > 0.8))
w[keep] = 0.0
w = ndimage.gaussian_filter(w, 1.0); w[keep] = 0.0
w[:12, :] = w[-12:, :] = w[:, :12] = w[:, -12:] = 0.0     # where the box meets the game's own ground


def reshape(G):
    """The shore across `G` (a ground grid of the plan's box)."""
    # the land beyond the shore: the old ground away from the water, carried in to the shore and smoothed
    far = ~water & (d_out >= BAND_DRY + 1)
    _, (fz, fx) = ndimage.distance_transform_edt(~far, return_indices=True)
    land = ndimage.gaussian_filter(G[fz, fx], 2.0)
    bank = np.minimum(W + BANK_SLOPE * np.maximum(s, 0), np.maximum(land, W + 0.15))
    # one smooth profile across every stream, DEEP m at most (the plan's rivers are 1.2-1.8 m deep, and the band
    # fades back into the old bed further in); keeping the old bed where it was shallower left its 1 m steps as
    # shelves in the shallows, which with the old river bed paint showed as separate blue puddles (2026-11-24)
    bed = W - np.minimum(BED_SLOPE * np.maximum(-s, 0), DEEP)
    new = np.where(s >= 0, bank, bed)
    return (G + (new - G) * w).astype("<f4")


high_ground = None
for setting in ("", "low", "medium", "minimum"):
    gdir = os.path.join(OUT, f"density_{setting}") if setting else OUT
    gpath = os.path.join(gdir, "ground.f32")
    G = np.fromfile(gpath, "<f4").reshape(NZ, NX)
    new = reshape(G)
    # the overlays: the plan's box of each region (checked against the grid first, so it never runs twice)
    tiles = []
    for lz in range(math.floor(Z0 / REGION), math.floor((Z0 + NZ - 1) / REGION) + 1):
        for lx in range(math.floor(X0 / REGION), math.floor((X0 + NX - 1) / REGION) + 1):
            path = os.path.join(ROOT, "world/terrain/sculpt", f"{lx}_{lz}", TAG + (f"_{setting}" if setting else ""), "height.f32")
            if not os.path.exists(path):
                continue
            heights = np.fromfile(path, "<f4").reshape(REGION, REGION).copy()
            rx0, rz0 = lx * REGION, lz * REGION
            ax0, ax1 = max(X0, rx0), min(X0 + NX, rx0 + REGION)
            az0, az1 = max(Z0, rz0), min(Z0 + NZ, rz0 + REGION)
            if ax0 >= ax1 or az0 >= az1:
                continue
            if np.abs(heights[az0 - rz0:az1 - rz0, ax0 - rx0:ax1 - rx0] - G[az0 - Z0:az1 - Z0, ax0 - X0:ax1 - X0]).max() > 0.01:
                sys.exit(f"{path} is not the ground of {gpath}: rebuild the ground first")
            tiles.append((path, heights, rx0, rz0, ax0, ax1, az0, az1))
    for path, heights, rx0, rz0, ax0, ax1, az0, az1 in tiles:
        heights[az0 - rz0:az1 - rz0, ax0 - rx0:ax1 - rx0] = new[az0 - Z0:az1 - Z0, ax0 - X0:ax1 - X0]
        heights.tofile(path)
    new.tofile(gpath)
    if not setting:
        high_ground = new
    moved = np.abs(new - G)
    print(f"{setting or 'high'}: {int((moved > 0.02).sum())} ground cells along the shores reshaped (largest {moved.max():.2f} m), {len(tiles)} overlays")

# ---- the water surface over the new outline (apply_ground.py's rule: the water's level where the ground is under
# it, and 2 m out under the banks, where it follows the ground down so its edge never hangs above it) ----
wet = ((high_ground < level - 0.02) & (s < 1.0)) | (water & (w == 0))      # (only at the shores: no hollow elsewhere floods)
band = cv2.dilate(wet.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0
surface = np.where(wet, level, np.where(band, np.minimum(level, high_ground - 0.05), np.nan)).astype("<f4")
canal_path = os.path.join(ROOT, "world/water/ponyville_canals.json")
canals = json.load(open(canal_path))
assert canals["width"] == NX and canals["depth"] == NZ
canals["heights"] = base64.b64encode(surface.tobytes()).decode()
canals["note"] = canals["note"].split(" (shores:")[0] + " (shores: tools/town_planner/build/fix_shore.py)"
json.dump(canals, open(canal_path, "w"))
np.save(os.path.join(OUT, "shore_distance.npy"), s)
print(f"water: {int(wet.sum())} m2 under water ({int(water.sum())} before), surface over {int(band.sum())} m2")
