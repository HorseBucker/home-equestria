"""A garden mailbox at every real home, clear of everything (2026-11-24 play test: "make sure that there is a red
mailbox at each real home, while making sure it doesn't collide with other houses or props ... and make sure they're
off the road").

usage: python tools/town_planner/build/fix_mailboxes.py <project>
(after the gardens are built: plan_props.py, build_density.py; and after fix_shore.py, whose ground it stands on)

plan_props.py tried a few fixed spots before each real home's front and left the mailbox out where none was clear of
the street (a quarter of the full town's homes had none, and Anon's Mailbox then took a neighbour's), and it did not
look at the street lamps, benches and trees, so one stood inside a lamp post. For every town density this checks each
real home's mailbox (kit rows kind "mailbox" of its garden group "house:<plot name>", in placements.json or
density/<setting>.json) and, where there is none or it is not clear, sets one at the best clear spot before the house:
- not on any street, square, dirt road or water, and at least STREET m from them;
- not on the house's own door path (DOOR_PATH m either side of it), nor within HOUSE m of any house;
- at least PROP m from the street lamps, benches, tables and flowerbeds, TREE m from trees, and KIT m from the
  garden's other plants and things;
- of those, the one nearest the house's front corner on the door's right, then left, at the house's front.
The real homes, their names and where they stand are read from each density's town scene (town[_<setting>].tscn).
"""
import json, math, os, re, sys

import cv2
import numpy as np
from scipy import ndimage

ROOT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
STREET, DOOR_PATH, HOUSE, PROP, TREE, KIT = 0.6, 0.9, 0.35, 0.9, 1.3, 0.6
SS = 4                                   # the street mask, SS cells a metre
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
DESIGNS = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])["designs"]
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
props = json.load(open(os.path.join(OUT, "props.json")))
fixed = [(p["x"], p["z"]) for p in props["outdoor"] if p["kind"] in ("streetlamp", "bench", "table", "flowerbed")]


def turn(x, z, y):
    c, s = math.cos(y), math.sin(y)
    return x * c + z * s, -x * s + z * c


def rect(h):
    # the walls (the design's footprint, as plan_props.py's walls mask), not the model's extents, which take in the
    # roof's overhang: a mailbox may stand under the eaves
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    xs = [p[0] * k for p in d["footprint"]]; zs = [p[1] * k for p in d["footprint"]]
    return min(xs), max(xs), min(zs), max(zs)


def gap(h, x, z):
    lx, lz = turn(x - h["x"], z - h["z"], -h["yaw"])
    x0, x1, z0, z1 = rect(h)
    return math.hypot(max(x0 - lx, 0.0, lx - x1), max(z0 - lz, 0.0, lz - z1))


def street_distance(plan):
    m = np.zeros((NZ * SS, NX * SS), np.uint8)
    hp = lambda pts: np.round((np.array(pts, np.float64) - [X0, Z0]) * SS * 8).astype(np.int32)
    for g in plan.get("grounds", []):
        cv2.fillPoly(m, [hp(g["points"])], 1, shift=3)
    for r in plan.get("roads", []):
        width = float(r.get("width", 4)) + (1.0 if r.get("type", "town") == "town" else 0.0)
        cv2.polylines(m, [hp(r["points"])], False, 1, max(1, int(round(width * SS))), shift=3)
    m |= cv2.resize(water.astype(np.uint8), (NX * SS, NZ * SS), interpolation=cv2.INTER_NEAREST)
    return ndimage.distance_transform_edt(m == 0) / SS


for setting in ("high", "medium", "low", "minimum"):
    plan = json.load(open(os.path.join(HERE, "..", f"ponyville_planV28_{setting}.json"), encoding="utf-8"))
    houses = [h for h in plan["houses"] if len(h["design"]) == 1]
    scene = open(os.path.join(ROOT, "world/towns/ponyville", "town.tscn" if setting == "high" else f"town_{setting}.tscn"), encoding="utf-8").read()
    homes = []
    for name, t in re.findall(r'\[node name="(plot_\d+)"[^\]]*\]\s*\ntransform = Transform3D\(([^)]*)\)', scene):
        v = [float(a) for a in t.split(",")]
        own = min(houses, key=lambda h: math.dist((h["x"], h["z"]), (v[9], v[11])))
        if math.dist((own["x"], own["z"]), (v[9], v[11])) < 0.5:
            homes.append((name, own))
    gdir = OUT if setting == "high" else os.path.join(OUT, f"density_{setting}")
    ground = np.fromfile(os.path.join(gdir, "ground.f32"), "<f4").reshape(NZ, NX)
    trees = [(t["x"], t["z"]) for t in props["trees"]]
    tpath = os.path.join(OUT, f"trees_{setting}.json")
    if os.path.exists(tpath):
        trees += [(t["x"], t["z"]) for t in json.load(open(tpath))["trees"]]
    kit_path = os.path.join(ROOT, "world/props/ponyville_kit", "placements.json" if setting == "high" else f"density/{setting}.json")
    raw = open(kit_path, encoding="utf-8").read()
    kit = json.loads(raw)
    rows = kit["entries"]
    from_street = street_distance(plan)
    near = lambda pts, x, z, r: any(abs(px - x) < r and abs(pz - z) < r and math.dist((px, pz), (x, z)) < r for px, pz in pts)
    placed, moved, kept = 0, 0, 0
    # a garden row's id ends _ovNNNN: at a lower density town_density.gd kit_entries drops the full town's garden rows by
    # that ending, so a mailbox named otherwise stood at the lower town too, beside its own (2026-11-24 play test: "two
    # red mailboxes", "a random mailbox that isn't near a real house", "a mailbox in front of a background house")
    used = [int(m.group(1)) for r in rows for m in [re.search(r"_ov(\d+)$", str(r.get("id", "")))] if m]
    counter = [max(used, default=0)]
    def next_id():
        counter[0] += 1
        return counter[0]
    for name, h in homes:
        group = "house:" + name
        mine = [r for r in rows if r.get("group") == group and r.get("kind") == "mailbox"]
        others = [(float(r["x"]), float(r["z"])) for r in rows if r.get("group") != group or r.get("kind") != "mailbox"]
        others = [p for p in others if abs(p[0] - h["x"]) < 20 and abs(p[1] - h["z"]) < 20]
        d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
        door_x = d["door"][0] * k
        x0, x1, z0, z1 = rect(h)
        nearby = [o for o in houses if math.dist((o["x"], o["z"]), (h["x"], h["z"])) < 30]

        def clear(x, z, local=None):
            c, r = int(round(x)) - X0, int(round(z)) - Z0
            if not (0 <= r < NZ and 0 <= c < NX):
                return False
            if from_street[min(NZ * SS - 1, max(0, int(round((z - Z0) * SS)))), min(NX * SS - 1, max(0, int(round((x - X0) * SS))))] < STREET:
                return False
            if any(gap(o, x, z) < HOUSE for o in nearby):
                return False
            lx, lz = local if local else turn(x - h["x"], z - h["z"], -h["yaw"])
            if lz > z1 - 0.2 and abs(lx - door_x) < DOOR_PATH:
                return False
            return not (near(fixed, x, z, PROP) or near(trees, x, z, TREE) or near(others, x, z, KIT))

        if len(mine) == 1 and clear(float(mine[0]["x"]), float(mine[0]["z"])):
            kept += 1
            continue
        best = None
        for side in (1, -1):
            for lz in np.arange(z1 - 1.5, z1 + 3.01, 0.25):
                for lx in np.arange(-2.5, 2.51, 0.25):
                    cx = (x1 + 0.45) if side == 1 else (x0 - 0.45)
                    px, pz = cx + lx, lz
                    if side * (px - door_x) < DOOR_PATH:
                        continue
                    wx, wz = turn(px, pz, h["yaw"])
                    wx += h["x"]; wz += h["z"]
                    if not clear(wx, wz, (px, pz)):
                        continue
                    score = math.hypot(px - cx, pz - (z1 + 0.9)) + (0.0 if side == 1 else 0.6)
                    if best is None or score < best[0]:
                        best = (score, wx, wz)
        if best is None:
            print(f"  {setting} {name}: no clear spot for a mailbox")
            continue
        _, wx, wz = best
        rows[:] = [r for r in rows if r not in mine]
        r_, c_ = int(round(wz)) - Z0, int(round(wx)) - X0
        rows.append({"blocking": True, "group": group, "id": f"mailbox_ov{next_id():04d}", "kind": "mailbox", "origin": "base",
                     "radius": 0.3, "x": round(wx, 3), "y": round(float(ground[r_, c_]), 3), "yaw": round(h["yaw"], 4), "z": round(wz, 3)})
        moved += 1 if mine else 0
        placed += 0 if mine else 1
    out = json.dumps(kit, indent="\t") + ("\n" if raw.endswith("\n") else "")
    open(kit_path, "w", encoding="utf-8", newline="\n").write(out)
    print(f"{setting}: {len(homes)} real homes: {kept} mailboxes kept, {moved} moved clear, {placed} added")
