"""Build step 1 and 2: put the plan's ground and water into the game.

usage: python tools/town_planner/build/apply_ground.py <project> <plan.json>

Runs elevation.py at 1 m and writes:
- Ground: the published sculpt overlays (world/terrain/sculpt). The game applies one overlay per 1024 m
  region over the generated terrain; each overlay is a full region of heights (height.f32) and a mask of
  where they apply (coverage.png). The regions under the plan's edge get a new overlay: the old overlay's
  heights everywhere it had them, and the plan's ground over the whole edge's box. index.json points at
  the new folders; the old ones stay as they were (they are the way back).
- Water: world/water/ponyville_canals.json becomes one water surface over every river and lake in the
  plan (a height grid with NaN where dry, reaching 2 m under the banks so the edges meet the ground): the
  plan's water level, rising or falling near the edge where a river leaves the map (elevation.py). The river ribbons in world/water/rivers.json that crossed the old town are cut at the edge.

Afterwards run tools/town_planner/build/apply_ground_half.gd (the "Very Low" quality copy of the
terrain) and let Godot import the new coverage images (see the README).
"""
import base64, json, math, os, subprocess, sys
import cv2, numpy as np

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "ponyville_overhaul_20261113"
REGION = 1024
SCULPT = os.path.join(ROOT, "world/terrain/sculpt")
# --density <setting> (2026-11-19 play test: "more terrain differences based on the density setting"): that
# density plan's ground (its own rises where houses are not built), written beside the full town's as
# <region>/<TAG>_<setting>; the water, the index and the build's grids are left as the full town's.
# (terrain_sculptor.gd loads it at that town density.) Run after the full town's ground.
DENSITY = sys.argv[sys.argv.index("--density") + 1] if "--density" in sys.argv else ""
WATER_DIR = os.path.join(ROOT, "world/water")
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

# ---- the ground at 1 m ----
EXPORT = os.path.join(OUT, "density_" + DENSITY) if DENSITY else OUT
os.makedirs(EXPORT, exist_ok=True)
subprocess.run([sys.executable, os.path.join(HERE, "..", "elevation.py"), PLAN, os.path.join(EXPORT, "plan_used.json"), "--export", EXPORT], check=True)
meta = json.load(open(os.path.join(EXPORT, "grid.json")))
NX, NZ = meta["columns"], meta["rows"]
X0, Z0 = int(meta["origin"][0]), int(meta["origin"][1])
ground = np.fromfile(os.path.join(EXPORT, "ground.f32"), "<f4").reshape(NZ, NX)
water = np.fromfile(os.path.join(EXPORT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
WL = float(meta["water_level"])
assert meta["step"] == 1.0 and np.isfinite(ground).all()

# ---- sculpt overlays, region by region ----
index_path = os.path.join(SCULPT, "index.json")
index = json.load(open(index_path))
written = []
for lz in range(math.floor(Z0 / REGION), math.floor((Z0 + NZ - 1) / REGION) + 1):
    for lx in range(math.floor(X0 / REGION), math.floor((X0 + NX - 1) / REGION) + 1):
        key = f"{lx}_{lz}"
        heights = np.zeros((REGION, REGION), "<f4")
        coverage = np.zeros((REGION, REGION), np.uint8)
        old = index["tiles"].get(key)
        if DENSITY:
            if not old or not old.endswith(TAG):
                continue
            base = os.path.join(SCULPT, old)
            heights = np.fromfile(os.path.join(base, "height.f32"), "<f4").reshape(REGION, REGION).copy()
            coverage = np.where(cv2.imread(os.path.join(base, "coverage.png"), cv2.IMREAD_GRAYSCALE) > 0, 255, 0).astype(np.uint8)
        elif old and not old.endswith(TAG):
            folder = os.path.join(SCULPT, old)
            heights = np.fromfile(os.path.join(folder, "height.f32"), "<f4").reshape(REGION, REGION).copy()
            coverage = cv2.imread(os.path.join(folder, "coverage.png"), cv2.IMREAD_GRAYSCALE)
            coverage = np.where(coverage > 0, 255, 0).astype(np.uint8)
        elif old:
            raise SystemExit(f"{key} already holds {old}: restore index.json to the earlier overlay first")
        # the plan's box inside this region
        rx0, rz0 = lx * REGION, lz * REGION
        ax0, ax1 = max(X0, rx0), min(X0 + NX, rx0 + REGION)
        az0, az1 = max(Z0, rz0), min(Z0 + NZ, rz0 + REGION)
        if ax0 >= ax1 or az0 >= az1:
            continue
        heights[az0 - rz0:az1 - rz0, ax0 - rx0:ax1 - rx0] = ground[az0 - Z0:az1 - Z0, ax0 - X0:ax1 - X0]
        coverage[az0 - rz0:az1 - rz0, ax0 - rx0:ax1 - rx0] = 255
        folder = os.path.join(SCULPT, key, TAG + (f"_{DENSITY}" if DENSITY else ""))
        os.makedirs(folder, exist_ok=True)
        heights.tofile(os.path.join(folder, "height.f32"))
        cv2.imwrite(os.path.join(folder, "coverage.png"), coverage)
        json.dump({"bounds": [0, 0, REGION, REGION],
                   "repair": "Ponyville overhaul (tools/town_planner): the plan's ground over x %d..%d, z %d..%d; "
                             "the earlier overlay (%s) elsewhere in the region" % (X0, X0 + NX - 1, Z0, Z0 + NZ - 1, old or "none")},
                  open(os.path.join(folder, "meta.json"), "w"), indent="\t")
        if not DENSITY:
            index["tiles"][key] = f"{key}/{TAG}"
        written.append((key, old, int((coverage > 0).sum())))
if DENSITY:
    print(f"{DENSITY}: its own ground beside the full town's in", ", ".join(k for k, _, _ in written))
    sys.exit(0)
json.dump(index, open(index_path, "w"), indent=2)

# ---- water: one surface over the plan's rivers and lakes ----
wet = cv2.dilate(water.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0
level = np.fromfile(os.path.join(OUT, "surface.f32"), "<f4").reshape(NZ, NX)
# the 2 m under the banks follows the ground down, so the water's edge never hangs above it
surface = np.where(water, level, np.where(wet, np.minimum(level, ground - 0.05), np.nan)).astype("<f4")
canals = {"version": 1, "note": "Ponyville overhaul water (tools/town_planner/build/apply_ground.py): every river and lake of the plan at one level",
          "origin": [float(X0), float(Z0)], "cell": 1.0, "width": NX, "depth": NZ,
          "heights": base64.b64encode(surface.tobytes()).decode()}
canal_path = os.path.join(WATER_DIR, "ponyville_canals.json")
json.dump(canals, open(canal_path, "w"))

# the old river ribbons through the town: keep only what lies outside the box
rivers_path = os.path.join(WATER_DIR, "rivers.json")
rivers = json.load(open(rivers_path))
kept = []
cut = []
for r in rivers["rivers"]:
    pieces, piece = [], []
    for p in r["points"]:
        if X0 <= p[0] <= X0 + NX - 1 and Z0 <= p[2] <= Z0 + NZ - 1:
            if len(piece) >= 2:
                pieces.append(piece)
            piece = []
        else:
            piece.append(p)
    if len(piece) >= 2:
        pieces.append(piece)
    if len(pieces) == 1 and len(pieces[0]) == len(r["points"]):
        kept.append(r)
        continue
    cut.append(r["id"])
    for k, piece in enumerate(pieces):
        kept.append(dict(r, id=r["id"] if len(pieces) == 1 else f"{r['id']}_{k + 1}", points=piece))
rivers["rivers"] = kept
json.dump(rivers, open(rivers_path, "w"))

print("ground:", ", ".join(f"{k} (was {o}, {n} px covered)" for k, o, n in written))
print(f"water: {int(wet.sum())} m2 of surface, at {WL} m except where rivers leave the map, in {os.path.relpath(canal_path, ROOT)}")
print("rivers cut at the edge:", cut or "none")
