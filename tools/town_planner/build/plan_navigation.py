"""Build step 7: what pony routing and the river dock need from the new town.

usage: python tools/town_planner/build/plan_navigation.py <project> <plan.json>
(after the other build steps)

- The walk grids are cached per install, keyed on a fingerprint of the files that shape the ground
  (world/terrain/world_terrain.gd, navigation_revision). The overhaul changed some files that fingerprint did
  not cover: the town scene, the background houses, the ground's paint and vegetation (bundle.json) and Sweet
  Apple Acres' fences. They join it, so every install rebuilds its walk grids for the new town.
- The river fishing dock (world/minigames/fishing/dock_spec.json) stood on the old town river. It moves to the
  town side of Marigold Lake: a free stretch of shore, the deck half over the water, its top half a metre above
  the water, its bank end on dry ground.
"""
import json, math, os, re, sys
import numpy as np
from scipy import ndimage

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
plan = json.load(open(PLAN, encoding="utf-8"))

# ---- the walk-grid fingerprint ----
wt_path = os.path.join(ROOT, "world/terrain/world_terrain.gd")
wt = open(wt_path, encoding="utf-8").read()
MARK = "# Ponyville overhaul (tools/town_planner)"
if MARK not in wt:
    anchor = '\t\tnavigation_revision += ":town:"+FileAccess.get_md5("res://world/towns/ponyville/layout.json")\n'
    assert anchor in wt
    addition = (anchor + f"\t{MARK}: the town scene, its background houses, the ground's paint and vegetation and the\n"
                "\t# farm's fences shape the walk grid too.\n"
                '\tfor overhaul: String in ["res://world/towns/ponyville/town.tscn", "res://world/biomes/authored/bundle.json",\n'
                '\t\t\t"res://world/props/ponyville/farm_layout.json", "res://world/props/ponyville/farm_dressing.gd"]:\n'
                '\t\tif FileAccess.file_exists(overhaul): navigation_revision += ":overhaul:" + FileAccess.get_md5(overhaul)\n'
                '\tfor design: String in ["a", "b", "c", "d", "e", "f", "g", "h"]:\n'
                '\t\tvar background := "res://world/towns/ponyville/background/house_%s_bg.scn" % design\n'
                '\t\tif FileAccess.file_exists(background): navigation_revision += ":background:" + FileAccess.get_md5(background)\n')
    wt = wt.replace(anchor, addition, 1)
    open(wt_path, "w", encoding="utf-8", newline="").write(wt)
    print("walk-grid fingerprint: + town.tscn, bundle.json, farm layout, background houses")

# ---- the fishing dock ----
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
props = json.load(open(os.path.join(OUT, "props.json")))
WL = grid["water_level"]
hall = next(h for h in plan["houses"] if h["design"] == "town_hall")
lake = min(plan["lakes"][1:] or plan["lakes"], key=lambda l: math.dist(np.mean(l["points"], axis=0), (hall["x"], hall["z"])))
pts = np.array(lake["points"]); centre = pts.mean(0)
things = [(h["x"], h["z"]) for h in plan["houses"]] + [(l["x"], l["z"]) for l in plan["landmarks"]] + [(p["x"], p["z"]) for p in props["outdoor"]]
best = None
# walk the shore in 1 m steps
shore = []
for i in range(len(pts)):
    a, b = pts[i], pts[(i + 1) % len(pts)]
    for t in np.arange(0, 1, 1 / max(1, math.dist(a, b))):
        shore.append(a + (b - a) * t)
for p in shore:
    out = p - centre; out /= (np.linalg.norm(out) or 1)                 # from the water toward the bank
    deck = p - out * 2.0                                                # deck middle 2 m out over the water
    land_end = deck + out * 6.0                                         # 4 m deck half + 2 m ramp
    r, c = int(round(land_end[1])) - Z0, int(round(land_end[0])) - X0
    if not (0 <= r < NZ and 0 <= c < NX) or water[r, c]:
        continue
    wr, wc = int(round((deck - out * 3.5)[1])) - Z0, int(round((deck - out * 3.5)[0])) - X0
    if not water[wr, wc]:
        continue
    clear = min(math.dist(land_end, q) for q in things)
    score = clear - 0.05 * math.dist(p, (hall["x"], hall["z"]))           # roomy, and on the town's side
    if clear > 9 and (best is None or score > best[0]):
        best = (score, deck, out, float(ground[r, c]))
dock_path = os.path.join(ROOT, "world/minigames/fishing/dock_spec.json")
spec = json.load(open(dock_path, encoding="utf-8"))
if plan.get("fishing_pier"):
    # where the plan draws it (2026-11-21 play test: plan V21's "fishing_pier", [shore end, water end]): the deck's
    # middle on the drawn line's middle, its land end toward the shore
    shore_end, water_end = np.array(plan["fishing_pier"][0], float), np.array(plan["fishing_pier"][1], float)
    out = shore_end - water_end; out /= np.linalg.norm(out)
    deck = (shore_end + water_end) / 2
    r, c = int(round(deck[1] + out[1] * 6)) - Z0, int(round(deck[0] + out[0] * 6)) - X0
    best = (0.0, deck, out, float(ground[r, c]))
if best:
    _, deck, out, land = best
    spec["origin"] = [round(float(deck[0]), 2), round(WL + 0.5, 2), round(float(deck[1]), 2)]
    spec["bank_direction"] = [round(float(out[0]), 3), 0.0, round(float(out[1]), 3)]
    spec["survey"] = "tools/town_planner/build/plan_navigation.py (Ponyville overhaul: Marigold Lake)"
    json.dump(spec, open(dock_path, "w", encoding="utf-8"), indent=2)
    print(f"fishing dock: Marigold Lake shore at ({deck[0]:.0f}, {deck[1]:.0f}), facing the water {(-out).round(2)}, bank ground {land:.2f} m, water {WL} m")
else:
    print("fishing dock: no free shore found; left as it was")
