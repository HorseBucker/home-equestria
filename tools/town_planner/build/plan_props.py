"""Build step 6 (planning half): trees, vegetation, garden dressing, street furniture, the farm.

usage: python tools/town_planner/build/plan_props.py <project> <plan.json>
(after apply_ground.py and plan_scenery.py; apply_props.gd then rebuilds the town's tree and outdoor
prop scenes from build/out/props.json)

- Vegetation (world/biomes/authored, new tiles for the four regions under the plan; bundle.json and
  index.json point at them): the plan's woods as forest (scattered to dense: thicker the thicker the
  woods), the Everfree as the game's Everfree, the rest of the country as meadow; no vegetation on the town
  ground, roads, railway, water, fields, farmyards, the orchard, or within 4 m of a building.
- Town trees (town_trees.scn): on the village's lawns behind and between the rows of houses, clear of roofs,
  streets and doors, and a loose ring just outside the village.
- Street furniture (outdoor_props.scn): lamps along the edges of the town streets (alternate sides, about every
  22 m), benches in the Town Square and by the lakes; picnic tables by Marigold Lake; flowerbeds by real
  homes' doors; daisies on the lawns. (The fountain's benches are the town scenery's own.)
- Gardens (world/props/ponyville_kit/placements.json, the kit's own rows): beside about a third of the
  houses, cypress shrubs at front corners, flower clumps and grass tufts along the sides, a rose bed and a
  mailbox at real homes; nothing in front of a door, in a street, in the water or in another building. A real
  home's rows carry its node's name (house:plot_NNN), so its resident tends that garden; a well in each square.
- The schoolhouse's white picket fence along Apple Road, beds of crops over Carrot Top's fields, drifts of flowers
  over the flower meadow (all kit rows); bunting between the Town Hall, its banners and two houses (props.json).
- Sweet Apple Acres (world/props/ponyville/farm_layout.json): fences round the farmyard, open where a
  road comes in; the orchard rows inside the plan's orchard.
"""
import hashlib, json, math, os, re, sys
import cv2, numpy as np
from scipy import ndimage
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import plan_geometry as G

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TAG = "ponyville_overhaul_20261114"
plan = json.load(open(PLAN, encoding="utf-8"))
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
DESIGNS = TOWN["designs"]
scen = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "world/props/ponyville/rnl_scenery.json"), encoding="utf-8"))["entries"]}
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)


def g(x, z):
    return float(ground[min(NZ - 1, max(0, round(z) - Z0)), min(NX - 1, max(0, round(x) - X0))])


def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def px(points, res):
    return np.round((np.array(points, np.float64) - [X0, Z0]) / res * 8).astype(np.int32)


# ---- 1 m masks of the plan ----
def fill(polys):
    m = np.zeros((NZ, NX), np.uint8)
    for p in polys:
        if len(p) >= 3:
            cv2.fillPoly(m, [px(p, 1.0)], 1, shift=3)
    return m.astype(bool)


def lines(items, width_of):
    m = np.zeros((NZ, NX), np.uint8)
    for it in items:
        cv2.polylines(m, [px(it["points"], 1.0)], False, 1, max(1, int(round(width_of(it)))), shift=3)
    return m.astype(bool)


def house_rect(h, model=True):
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    if model and h["design"] in MODEL:
        x0, x1, z0, z1 = MODEL[h["design"]]
        pts = [[x0 * k, z0 * k], [x1 * k, z0 * k], [x1 * k, z1 * k], [x0 * k, z1 * k]]
    else:
        pts = [[p[0] * k, p[1] * k] for p in d["footprint"]]
    return [[h["x"] + p[0], h["z"] + p[1]] for p in turn(pts, h["yaw"])]


def landmark_shape(i, entry):
    fp = entry.get("footprint") or []
    return fp if len(fp) >= 3 else None


# the town as the paint step lays it (apply_paint.py): sage along the streets and over the squares, the village
# round them, and lawn (grass) everywhere in the village that is not sage
streets = [r for r in plan["roads"] if r.get("type", "town") == "town"]
squares = fill([gr["points"] for gr in plan["grounds"]])
town = squares | lines(streets, lambda r: r["width"] + 1.0)
_k = 22
_yy, _xx = np.ogrid[-_k:_k + 1, -_k:_k + 1]
village = ndimage.binary_closing(squares | lines(streets, lambda r: r["width"] + 26.0), structure=(_xx * _xx + _yy * _yy <= _k * _k))
lawns = (village & ~town) | fill([gr["points"] for gr in plan.get("greens", [])])
buildings = fill([house_rect(h) for h in plan["houses"]] + [s for s in (landmark_shape(i, e) for i, e in scen.items()) if s])
roads = lines([r for r in plan["roads"] if r.get("type") == "dirt"], lambda r: r["width"] + 2) | lines([r for r in plan.get("railways", []) if not r.get("outside") and r.get("name") != "bunting"], lambda r: 7.0)
fields = {}
for f in plan.get("fields", []):
    fields.setdefault(f["crop"], []).append(f["points"])
crops = fill(fields.get("carrots", []) + fields.get("vegetable rows", []) + fields.get("wheat", []) + fields.get("farmyard", []))
orchard = fill(fields.get("apple orchard", []))
meadow = fill(fields.get("flower meadow", []))
walls = fill([house_rect(h, model=False) for h in plan["houses"]] + [s for s in (landmark_shape(i, e) for i, e in scen.items()) if s])
near_building = ndimage.binary_dilation(buildings, iterations=4)
near_water = ndimage.binary_dilation(water, iterations=3)

# ---- 1. vegetation: the biome tiles ----
CELL, SIZE, REG = 4, 256, 1024
level = np.zeros((NZ, NX), np.int8)        # 0 meadow, 1..4 woods scattered..dense, 5 Everfree
for k, name in enumerate(("scattered", "sparse", "medium", "dense", "forest"), 1):
    level[fill([w["points"] for w in plan.get("woods", []) if w["density"] == name])] = k
# no trees or bushes on steep ground (a big Everfree tree on a bank stands with its roots in the air), round
# Fluttershy's henhouse, or before a landmark's door
_gz, _gx = np.gradient(ground)
steep = ndimage.binary_dilation(np.degrees(np.arctan(np.hypot(_gx, _gz))) > 9.0, iterations=3)
clear_spots = np.zeros((NZ, NX), bool)
_yy0, _xx0 = np.mgrid[0:NZ, 0:NX]
for i, e in scen.items():
    reach = 0.0
    if e["model"] == "rnl_henhouse":
        reach = 15.0; at = (e["position"][0], e["position"][2])
    elif isinstance(e.get("door"), dict) and "point" in e["door"]:
        reach = 7.0; at = tuple(e["door"]["point"])
    if reach:
        clear_spots |= np.hypot(_xx0 + X0 - at[0], _yy0 + Z0 - at[1]) <= reach
for wx_, wz_ in plan.get("wells", []):                      # a well the plan places: no tree or bush on it
    clear_spots |= np.hypot(_xx0 + X0 - wx_, _yy0 + Z0 - wz_) <= 5.0
# (2026-11-21 play test: two bushes on the picnic hill stood in the view of town: the foliage cells their roots
# are in grow nothing; streamed in the game at (363.8, -285.4) and (358.5, -289.9))
for wx_, wz_ in ((363.8, -285.4), (358.5, -289.9)):
    _r, _c = math.floor(wz_ / CELL) * CELL - Z0, math.floor(wx_ / CELL) * CELL - X0
    clear_spots[_r:_r + CELL, _c:_c + CELL] = True
bare = town | village | roads | water | near_water | crops | orchard | near_building | steep | clear_spots
FOREST, EVERFREE, MEADOW = 2, 3, 1
bundle_path = os.path.join(ROOT, "world/biomes/authored/bundle.json")
bundle = json.load(open(bundle_path, encoding="utf-8"))
index_path = os.path.join(ROOT, "world/biomes/authored/index.json")
index = json.load(open(index_path, encoding="utf-8")) if os.path.exists(index_path) else None
written = []
for lz in range(math.floor(Z0 / REG), math.floor((Z0 + NZ - 1) / REG) + 1):
    for lx in range(math.floor(X0 / REG), math.floor((X0 + NX - 1) / REG) + 1):
        key = f"{lx}_{lz}"
        old = bundle["biomes"]["tiles"].get(key)
        if old and TAG in old:
            raise SystemExit(f"biome tile {key} already holds {old}: restore bundle.json from git first")
        folder_old = os.path.join(ROOT, "world/biomes/authored", old) if old else None
        def read(name, channels):
            if folder_old and os.path.exists(os.path.join(folder_old, name)):
                im = cv2.imread(os.path.join(folder_old, name), cv2.IMREAD_UNCHANGED)
                return im if im is not None else None
            return None
        w = [read(f"weights{i}.png", 4) for i in range(4)]
        w = [x if x is not None else np.zeros((SIZE, SIZE, 4), np.uint8) for x in w]
        dens = read("density.png", 1); dens = dens if dens is not None else np.full((SIZE, SIZE), 255, np.uint8)
        boost = read("density_boost.png", 1); boost = boost if boost is not None else np.zeros((SIZE, SIZE), np.uint8)
        veg = read("vegetation.png", 1); veg = veg if veg is not None else np.zeros((SIZE, SIZE), np.uint8)
        cov = read("coverage.png", 1); cov = cov if cov is not None else np.zeros((SIZE, SIZE), np.uint8)
        touched = 0
        for cz in range(SIZE):
            wz = lz * REG + cz * CELL
            if wz < Z0 or wz + CELL > Z0 + NZ: continue
            for cx in range(SIZE):
                wx = lx * REG + cx * CELL
                if wx < X0 or wx + CELL > X0 + NX: continue
                r0, c0 = wz - Z0, wx - X0
                blk_bare = bare[r0:r0 + CELL, c0:c0 + CELL].mean()
                lv = int(np.bincount(level[r0:r0 + CELL, c0:c0 + CELL].ravel() + 0, minlength=6).argmax())
                weights = [0] * 13
                if lv == 5:
                    weights[EVERFREE] = 255; vb = EVERFREE; d = 8.0
                elif lv >= 1:
                    share = (0.35, 0.65, 1.0, 1.0)[lv - 1]
                    weights[FOREST] = int(round(255 * share)); weights[MEADOW] = 255 - weights[FOREST]
                    vb = FOREST; d = (1.0, 2.0, 3.5, 5.5)[lv - 1]
                else:
                    weights[MEADOW] = 255; vb = -1
                    d = 2.6 if meadow[r0:r0 + CELL, c0:c0 + CELL].mean() > 0.5 else 1.0
                d *= (1.0 - blk_bare) if blk_bare < 0.5 else 0.0
                # cv2 images are BGRA: weights i*4+j sit in channel order R,G,B,A -> index 2,1,0,3
                for i in range(4):
                    for j, ch in enumerate((2, 1, 0, 3)):
                        k = i * 4 + j
                        w[i][cz, cx, ch] = weights[k] if k < 13 else 0
                dens[cz, cx] = int(round(min(d, 1.0) * 255))
                boost[cz, cx] = int(round(max(0.0, d - 1.0) / 7.0 * 255))
                veg[cz, cx] = vb + 1 if vb >= 0 else 0
                cov[cz, cx] = 255
                touched += 1
        rel = f"{key}/{TAG}"
        folder = os.path.join(ROOT, "world/biomes/authored", rel)
        os.makedirs(folder, exist_ok=True)
        for i in range(4):
            cv2.imwrite(os.path.join(folder, f"weights{i}.png"), w[i])
        for name, im in (("density.png", dens), ("density_boost.png", boost), ("vegetation.png", veg), ("coverage.png", cov)):
            cv2.imwrite(os.path.join(folder, name), im)
        json.dump({"bounds": [0, 0, SIZE, SIZE], "note": "Ponyville overhaul vegetation (tools/town_planner/build/plan_props.py)"},
                  open(os.path.join(folder, "meta.json"), "w"), indent=2)
        bundle["biomes"]["tiles"][key] = rel
        if index is not None and "tiles" in index:
            index["tiles"][key] = rel
        written.append((key, touched))
json.dump(bundle, open(bundle_path, "w", encoding="utf-8"), indent=2)
if index is not None:
    json.dump(index, open(index_path, "w", encoding="utf-8"), indent=2)

# ---- spacing helper: a set of spots, nothing closer than `gap` ----
taken = []


def free(x, z, gap, mask_ok=None):
    r, c = round(z) - Z0, round(x) - X0
    if not (0 <= r < NZ and 0 <= c < NX):
        return False
    if mask_ok is not None and not mask_ok[r, c]:
        return False
    return all(math.dist((x, z), (tx, tz)) >= max(gap, tg) for tx, tz, tg in taken)


def take(x, z, gap):
    taken.append((x, z, gap))


rng = np.random.default_rng(1114)
for wx_, wz_ in plan.get("wells", []):
    take(wx_, wz_, 4.0)
# clearance from buildings, in metres (1 m grid)
from_building = ndimage.distance_transform_edt(~buildings)
from_road = ndimage.distance_transform_edt(~roads)
from_water = ndimage.distance_transform_edt(~water)
from_town_edge = ndimage.distance_transform_edt(~village)       # outside the village: metres to it
# how wide the open ground is round here: twice the farthest any spot within 5 m is from a building or water
street_room = ndimage.maximum_filter(ndimage.distance_transform_edt(~(buildings | water)), size=11) * 2

# ---- 2. town trees ----
trees = []
# in the village: on the lawns behind and between the rows, well clear of roofs, streets and doors
from_sage = ndimage.distance_transform_edt(~town)
lawn_spots = np.argwhere(lawns & (from_building > 3.5) & (from_water > 4) & (from_sage > 3.0) & (from_road > 3) & ~clear_spots)
rng.shuffle(lawn_spots)
for r, c in lawn_spots:
    x, z = c + X0 + 0.5, r + Z0 + 0.5
    if len(trees) >= 90:
        break
    if free(x, z, 10.0):
        take(x, z, 10.0); trees.append((x, z))
# and a loose ring just outside it
edge_spots = np.argwhere(~village & (from_town_edge > 2) & (from_town_edge < 10) & (from_building > 6) & (from_road > 3) & (from_water > 5) & ~crops & ~clear_spots)
rng.shuffle(edge_spots)
for r, c in edge_spots[:6000]:
    x, z = c + X0 + 0.5, r + Z0 + 0.5
    if len(trees) >= 130:
        break
    if free(x, z, 11.0):
        take(x, z, 11.0); trees.append((x, z))
# the planner's note `picnic tree` (2026-11-19 play test: a tree on top of the new hill to sit under for shade)
for n in plan.get("notes", []):
    if str(n.get("text", "")).strip().lower().startswith("picnic tree"):
        trees.append((float(n["x"]), float(n["z"])))
props = {"trees": [{"x": round(x, 2), "z": round(z, 2), "y": round(g(x, z), 3), "yaw": round(float(rng.uniform(0, 6.283)), 3)} for x, z in trees],
         "outdoor": []}


def put(kind, x, z, yaw, gap=1.5):
    props["outdoor"].append({"kind": kind, "x": round(x, 2), "z": round(z, 2), "y": round(g(x, z), 3), "yaw": round(yaw, 4)})
    take(x, z, gap)


# ---- 3. street furniture ----
fountain = next(l for l in plan["landmarks"] if l["id"] == "fountain_01")
fr = max(math.dist(p, (scen["fountain_01"]["position"][0], scen["fountain_01"]["position"][2])) for p in scen["fountain_01"]["footprint"])
# (the fountain keeps its own benches from the town scenery, their backs to it: plan_scenery.py)
hall = next(h for h in plan["houses"] if h["design"] == "town_hall")
for k in range(6):
    rng.uniform(0, 6.283); rng.uniform(14, 22)          # (the draws the old scattered benches took: the rest of the town's dressing stays where it was)
# benches against the Town Hall's walls, their backs to it: one centred on each side and one behind, not before its
# steps. (2026-11-18 play test: two a side, a pony got stuck between a bench and the curved wall. Centred, a bench
# stands where the round wall comes nearest the footprint's edge, and close enough (its centre BENCH_OUT past the
# edge; the wall stands about 0.1 m past it, lab_hall.gd; a bench is 0.47 m deep) that no pony fits behind it.)
BENCH_OUT = 0.55           # (2026-11-21 play test: 0.45 m, a pony sitting down still bumped the hall's wall)
_hk = hall.get("scale") or DESIGNS["town_hall"]["scale"]
_hf = [[p[0] * _hk, p[1] * _hk] for p in DESIGNS["town_hall"]["footprint"]]
_hx0, _hx1 = min(p[0] for p in _hf), max(p[0] for p in _hf); _hz0, _hz1 = min(p[1] for p in _hf), max(p[1] for p in _hf)
for lx, lz, out in ((_hx1 + BENCH_OUT, (_hz0 + _hz1) * 0.5, (1, 0)), (_hx0 - BENCH_OUT, (_hz0 + _hz1) * 0.5, (-1, 0)),
                    ((_hx0 + _hx1) * 0.5, _hz0 - BENCH_OUT, (0, -1))):
    (dx, dz), (ox_, oz_) = turn([[lx, lz], list(out)], hall["yaw"])
    put("bench", hall["x"] + dx, hall["z"] + dz, math.atan2(ox_, oz_), 2.0)
# lamps: along street edges that front doors face
door_spots = []
for h in plan["houses"]:
    if len(h["design"]) != 1:
        continue
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    front = max(d["door"][1], MODEL[h["design"]][3]) * k + 2.5
    dx, dz = turn([[d["door"][0] * k, front]], h["yaw"])[0]
    door_spots.append((h["x"] + dx, h["z"] + dz))
door_grid = np.zeros((NZ, NX), bool)
for x, z in door_spots:
    r, c = round(z) - Z0, round(x) - X0
    if 0 <= r < NZ and 0 <= c < NX:
        door_grid[r, c] = True
near_doors = ndimage.distance_transform_edt(~door_grid)
# the way in to every door: from the door straight out 6 m (where a pony stands to go in, and walks from), and on to
# the nearest street; and the same before each landmark's door. Nothing solid stands in it (a lamp stood 0.3 m
# from one house's doorstep, and ponies could not get in)
ways = np.zeros((NZ, NX), np.uint8)
_ty, _tx = np.nonzero(town)
from scipy.spatial import cKDTree
_streets = cKDTree(np.stack([_tx + X0, _ty + Z0], 1))
for h in plan["houses"]:
    if len(h["design"]) != 1:
        continue
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    a_ = turn([[d["door"][0] * k, d["door"][1] * k]], h["yaw"])[0]; b_ = turn([[d["door"][0] * k, d["door"][1] * k + 6.0]], h["yaw"])[0]
    a_ = (h["x"] + a_[0], h["z"] + a_[1]); b_ = (h["x"] + b_[0], h["z"] + b_[1])
    cv2.line(ways, tuple(px([a_], 1.0)[0]), tuple(px([b_], 1.0)[0]), 1, 1, cv2.LINE_8, 3)
    dist, at = _streets.query(a_)
    if dist <= 16.0:
        cv2.line(ways, tuple(px([a_], 1.0)[0]), tuple(px([[float(_tx[at] + X0), float(_ty[at] + Z0)]], 1.0)[0]), 1, 1, cv2.LINE_8, 3)
    # and straight out to the street where apply_paint.py lays the door's path that way (within 9 m)
    for k_ in range(1, 33):
        sx_, sz_ = a_[0] + math.sin(h["yaw"]) * k_ * 0.5, a_[1] + math.cos(h["yaw"]) * k_ * 0.5
        r_, c_ = int(round(sz_)) - Z0, int(round(sx_)) - X0
        if 0 <= r_ < NZ and 0 <= c_ < NX and town[r_, c_]:
            cv2.line(ways, tuple(px([a_], 1.0)[0]), tuple(px([[sx_, sz_]], 1.0)[0]), 1, 1, cv2.LINE_8, 3); break
for e in scen.values():
    if isinstance(e.get("door"), dict) and "point" in e["door"]:
        a_ = tuple(e["door"]["point"]); c_ = (e["position"][0], e["position"][2])
        cv2.line(ways, tuple(px([a_], 1.0)[0]), tuple(px([c_], 1.0)[0]), 1, 1, cv2.LINE_8, 3)
        dist, at = _streets.query(a_)
        if dist <= 14.0:
            cv2.line(ways, tuple(px([a_], 1.0)[0]), tuple(px([[float(_tx[at] + X0), float(_ty[at] + Z0)]], 1.0)[0]), 1, 1, cv2.LINE_8, 3)
from_way = ndimage.distance_transform_edt(~ways.astype(bool))
from_street = ndimage.distance_transform_edt(~town)          # metres outside the sage of any street or square
# lamps: beside the streets, on alternate sides, about every 22 m: on the grass just off the sage of EVERY street and
# square (a lamp at one street's edge stood in the middle of the street crossing it), clear of every way in to a
# door, never under a roof
lamps = 0
from_walls = ndimage.distance_transform_edt(~walls)
for s in streets:
    pts = np.array(s["points"], float)
    seg = np.hypot(*np.diff(pts, axis=0).T); total = float(seg.sum())
    if total < 14:
        continue
    side = 1 if int(hashlib.md5(s.get("name", "s").encode()).hexdigest()[:4], 16) % 2 else -1
    d = 7.0
    while d < total - 5:
        k = int(np.searchsorted(np.cumsum(seg), d)); k = min(k, len(seg) - 1)
        along_seg = d - (np.cumsum(seg)[k] - seg[k])
        a_, b_ = pts[k], pts[k + 1]; tdir = (b_ - a_) / (seg[k] or 1)
        base = a_ + tdir * along_seg
        placed_here = False
        for sd in (side, -side):
            for back in (1.1, 1.5, 2.0):
                x, z = base + np.array([tdir[1], -tdir[0]]) * sd * (s["width"] / 2 + back)
                r, c = round(z) - Z0, round(x) - X0
                if not (0 <= r < NZ and 0 <= c < NX) or water[r, c] or from_walls[r, c] < 0.9 or from_water[r, c] < 2:
                    continue
                if from_street[r, c] < 0.5 or from_way[r, c] < 2.4 or roads[r, c]:
                    continue
                if free(x, z, 1.5) and all(math.dist((x, z), (p["x"], p["z"])) > 15 for p in props["outdoor"] if p["kind"] == "streetlamp"):
                    put("streetlamp", float(x), float(z), float(rng.uniform(0, 6.283)), 1.5); lamps += 1; placed_here = True; break
            if placed_here:
                break
        side = -side
        d += 22.0
# benches about town, facing the street (2026-11-21 play test: the benches on lawn edges, facing in, came out four in a
# row west of Sugarcube Corner: "spread them out around town facing toward roads as casual seating spots. Never
# place them directly in front of front doors"): on the grass just off a street's sage, on level ground, clear of
# every door (6 m) and way in, each as far as can be from the others, at least BENCH_APART
BENCH_COUNT, BENCH_APART = 14, 35.0
_gz_, _gx_ = np.gradient(ground)
_level = np.hypot(_gx_, _gz_) < 0.08
_door_pts = np.array(door_spots) if door_spots else np.zeros((0, 2))
cand = np.argwhere((from_street >= 1.0) & (from_street <= 1.8) & (from_building > 3.0) & (from_water > 4) & (from_way > 2.0)
                   & (near_doors > 6.0) & _level & ~roads & ~water)
cand = [(float(c + X0), float(r + Z0)) for r, c in cand]
benches = [(p["x"], p["z"]) for p in props["outdoor"] if p["kind"] in ("bench", "table")]
placed_b = 0
while cand and placed_b < BENCH_COUNT:
    far = [min([math.dist(q, b_) for b_ in benches] or [1e9]) for q in cand]
    k_ = int(np.argmax(far))
    if far[k_] < BENCH_APART:
        break
    x, z = cand.pop(k_)
    if not free(x, z, 3.0):
        continue
    dist, at = _streets.query((x, z))
    sx, sz = float(_tx[at] + X0), float(_ty[at] + Z0)
    put("bench", x, z, math.atan2(sx - x, sz - z), 3.0)
    benches.append((x, z)); placed_b += 1
print(f"benches about town: {placed_b}")
# the planner's notes (2026-11-21: "reposition a bench exactly where I want it, facing the direction I want it"):
# `no bench` (anything may follow after a comma) takes away any bench within 4 m of it; `bench` moves the nearest
# bench within 8 m there (or adds one), facing the note's arrow (its yaw; without one, toward the nearest street)
def _note_is(n, word):
    return str(n.get("text", "")).split(",")[0].strip().lower() == word
for n in plan.get("notes", []):
    if _note_is(n, "no bench"):
        props["outdoor"] = [p for p in props["outdoor"] if not (p["kind"] == "bench" and math.dist((p["x"], p["z"]), (n["x"], n["z"])) < 4.0)]
for n in plan.get("notes", []):
    if _note_is(n, "bench"):
        x, z = float(n["x"]), float(n["z"])
        mine = [p for p in props["outdoor"] if p["kind"] == "bench" and math.dist((p["x"], p["z"]), (x, z)) < 8.0]
        if mine:
            props["outdoor"].remove(min(mine, key=lambda p: math.dist((p["x"], p["z"]), (x, z))))
        if n.get("yaw") is not None:
            yaw = float(n["yaw"])
        else:
            _, at = _streets.query((x, z)); yaw = math.atan2(float(_tx[at] + X0) - x, float(_ty[at] + Z0) - z)
        # on level ground off the street: its two ends (0.9 m either side) and its middle within 0.06 m of each other
        # and not on a street's sage; else the nearest such spot within 3 m, facing the same way (2026-11-21: the note
        # by Sparkling Lake was on its bank; stepped straight back, it landed in the street)
        ex, ez = math.cos(yaw) * 0.9, -math.sin(yaw) * 0.9
        def _bench_ok(bx, bz):
            hs = [g(bx + ex, bz + ez), g(bx - ex, bz - ez), g(bx, bz)]
            ok = max(hs) - min(hs) <= 0.06
            for qx, qz in ((bx, bz),):                        # (its middle: an end may reach the street's edge)
                r_, c_ = round(qz) - Z0, round(qx) - X0
                ok = ok and 0 <= r_ < NZ and 0 <= c_ < NX and from_street[r_, c_] > 0 and not water[r_, c_]
            return ok
        spots_ = sorted(((x + dx_ * 0.25, z + dz_ * 0.25) for dx_ in range(-12, 13) for dz_ in range(-12, 13) if dx_ * dx_ + dz_ * dz_ <= 144),
                        key=lambda q: math.dist(q, (x, z)))
        # (the note's own spot stands if it is level: HorseBucker chose it, at a street's edge or not)
        hs0 = [g(x + ex, z + ez), g(x - ex, z - ez), g(x, z)]
        found = (x, z) if max(hs0) - min(hs0) <= 0.06 else next((q for q in spots_ if _bench_ok(*q)), None)
        if found is None:
            print(f"bench note at ({x:.1f}, {z:.1f}): no level spot off the street within 3 m; left where it is")
        elif math.dist(found, (x, z)) > 0.01:
            print(f"bench note at ({x:.1f}, {z:.1f}): moved {math.dist(found, (x, z)):.2f} m to level ground off the street")
            x, z = found
        put("bench", x, z, yaw, 3.0)
# lakeside benches and picnic tables
for lake, kinds in ((1, ["table", "table", "bench", "bench"]), (2, ["bench", "bench"])):
    if lake >= len(plan["lakes"]):
        continue
    pts = np.array(plan["lakes"][lake]["points"]); cx, cz = pts.mean(0)
    placed = 0
    for p in pts[rng.permutation(len(pts))]:
        if placed >= len(kinds):
            break
        out = np.array(p) - [cx, cz]; out /= (np.linalg.norm(out) or 1)
        x, z = p[0] + out[0] * 6, p[1] + out[1] * 6
        r, c = round(z) - Z0, round(x) - X0
        if 0 <= r < NZ and 0 <= c < NX and not water[r, c] and from_water[r, c] > 3 and from_building[r, c] > 4 and from_road[r, c] > 2 and free(x, z, 5.0):
            put(kinds[placed], x, z, math.atan2(cx - x, cz - z), 5.0); placed += 1
# flowerbeds by real homes' doors, daisies on lawns
# (2026-11-21 play test: the H home's planter clipped its wide front step, about 2 m across: 1.8 m from the door's
# middle is on it; "as close to the steps as it can be with no clipping": the box (1.84 m long) 0.1 m clear of it)
DOOR_SIDE = {"h": 2.05, "d": 2.0}       # (d: 1.65 clipped its step)
# a design whose door is set back from its front (the D's, 4.5 m behind its wing): the planter stands against the
# wall beside the door, this far (in the design's units) in front of its middle, not out before the wing (2026-11-21:
# "almost in the path to the door. I'd rather it be where I indicated")
DOOR_WALL = {"d": 0.15225}
# and its rose bed on the step's other side ("I want the garden to the right of the steps"): its middle this far from
# the door's middle (the step's half width, 1.0 m, 0.14 m clear, the bed's 0.6 m radius)
GARDEN_APART = {"h": 1.74}
flowerbed_of = {}            # a home's planter (x, z) and its door side, so its rose bed goes on the door's other side
for h in plan["houses"]:
    if len(h["design"]) != 1 or h.get("filler", True):
        continue
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    # (a home whose rose bed goes by its step has its planter on the door's -x side, at every density: the game's
    # planters are the full town's, the gardens each density's own)
    for side in ((-1, 1) if h["design"] in GARDEN_APART else (1, -1)):
        lx = d["door"][0] * k + side * DOOR_SIDE.get(h["design"], 1.8)
        lz = DOOR_WALL[h["design"]] * k + 0.4 if h["design"] in DOOR_WALL else max(p[1] for p in d["footprint"]) * k + 0.6
        dx, dz = turn([[lx, lz]], h["yaw"])[0]
        x, z = h["x"] + dx, h["z"] + dz
        r, c = round(z) - Z0, round(x) - X0
        # (not in a street: a house whose front wall stands at the street's edge had its bed in the roadway)
        if 0 <= r < NZ and 0 <= c < NX and not water[r, c] and from_street[r, c] >= 0.8 and free(x, z, 1.2):
            put("flowerbed", x, z, h["yaw"], 1.2); flowerbed_of[id(h)] = (x, z, side, lx - d["door"][0] * k, lz); break
daisy_spots = np.argwhere(lawns & (from_building > 1.2) & (from_water > 3) & (from_sage > 1.0))
rng.shuffle(daisy_spots)
for r, c in daisy_spots[:3000]:
    x, z = c + X0 + 0.5, r + Z0 + 0.5
    if sum(1 for p in props["outdoor"] if p["kind"] == "daisy") >= 60:
        break
    if free(x, z, 5.0):
        put("daisy", x, z, float(rng.uniform(0, 6.283)), 5.0)
json.dump(props, open(os.path.join(OUT, "props.json"), "w"), indent=1)

# ---- 4. gardens: the kit's rows ----
kit_path = os.path.join(ROOT, "world/props/ponyville_kit/placements.json")
kit_raw = open(kit_path, encoding="utf-8").read()
kit = json.loads(kit_raw)
edge_pts = plan["edges"][0]["points"]
BX0, BX1 = min(p[0] for p in edge_pts), max(p[0] for p in edge_pts)
BZ0, BZ1 = min(p[1] for p in edge_pts), max(p[1] for p in edge_pts)
kept = [e for e in kit["entries"] if not (BX0 <= e["x"] <= BX1 and BZ0 <= e["z"] <= BZ1)]
rows = []
RADIUS = {"cypress": 0.5, "rose_bed": 0.6, "daisy_clump": 0.35, "lupin_clump": 0.35, "sunflower_clump": 0.35, "grass_tuft_a": 0.3, "grass_tuft_b": 0.3, "mailbox": 0.3}
BLOCKING = {"cypress": True, "rose_bed": False, "mailbox": True}
garden_houses = 0
mailboxes_moved = 0
real_number = 0           # build_town.py names the real homes plot_001.. in the plan's order


def kit_row(kind, x, z, yaw, group, by_door=False):
    r, c = round(z) - Z0, round(x) - X0
    if not (0 <= r < NZ and 0 <= c < NX) or water[r, c] or roads[r, c] or walls[r, c]:
        return False
    if (near_doors[r, c] < 1.6 and not by_door) or from_way[r, c] < (2.6 if kind == "cypress" else 0.6 if by_door else 1.2):
        return False
    if kind in ("cypress", "mailbox") and street_room[r, c] < 6.5:
        return False
    if kind == "cypress" and from_street[r, c] < 0.8:      # (2026-11-21 play test: one stood in the street by Mayor Mare's)
        return False
    if kind not in ("cypress", "mailbox") and from_street[r, c] < 0.8:       # flowers grow on the lawn, not in the street
        return False
    if any(math.dist((x, z), w) < 3.0 for w in plan.get("wells", [])):
        return False
    rows.append({"blocking": BLOCKING.get(kind, False), "group": group, "id": f"{kind}_ov{len(rows):04d}", "kind": kind,
                 "origin": "base", "radius": RADIUS.get(kind, 0.35), "x": round(x, 3), "y": round(g(x, z), 3), "yaw": round(yaw, 4), "z": round(z, 3)})
    return True


for n, h in enumerate(plan["houses"]):
    if len(h["design"]) != 1:
        continue
    keyh = int(hashlib.md5(f"garden {h['x']:.1f},{h['z']:.1f}".encode()).hexdigest()[:8], 16)
    real = not h.get("filler", True)
    if real:
        real_number += 1
    if keyh % 3 and not real:
        continue
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    xs = [p[0] * k for p in d["footprint"]]; zs = [p[1] * k for p in d["footprint"]]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    # a resident tends the garden of her own house: the kit finds it by the house node's name (kit_spots.gd)
    group = f"house:plot_{real_number:03d}" if real else f"house:overhaul_{n:03d}"
    hr = np.random.default_rng(keyh)
    local = []
    # no cypress at the front corners any more (2026-11-23 player report: they clipped through the walls; play test
    # the same day: "Just remove the cypresses entirely. They stand out in a bad way compared to the other trees around
    # them"). The draws stay, so every other garden plant lands where it did.
    for sx in (x0 - 0.7, x1 + 0.7):
        hr.random()
    # flower clumps and tufts along the sides and back
    for _ in range(int(hr.integers(3, 7))):
        side = int(hr.integers(0, 3))
        if side == 0:
            local.append((str(hr.choice(["daisy_clump", "lupin_clump", "sunflower_clump"])), x0 - 0.6, float(hr.uniform(z0, z1 - 1))))
        elif side == 1:
            local.append((str(hr.choice(["daisy_clump", "lupin_clump", "sunflower_clump"])), x1 + 0.6, float(hr.uniform(z0, z1 - 1))))
        else:
            local.append((str(hr.choice(["grass_tuft_a", "grass_tuft_b"])), float(hr.uniform(x0, x1)), z0 - 0.6))
    if real:
        bed = globals().get("flowerbed_of", {}).get(id(h))
        rx_, rz_ = x0 + 0.9, z1 + 0.9
        if h["design"] in GARDEN_APART:
            # beside the doorstep, on the planter's other side (plan_props.py runs the planters first; build_density.py
            # runs only the gardens, on its own plan: the planter's side is -x there too)
            rx_, rz_ = d["door"][0] * k + (-bed[2] if bed else 1) * GARDEN_APART[h["design"]], z1 + 0.7
            local.append(("rose_bed@door", rx_, rz_))
        # (2026-11-21 play test: a rose bed that would lie on the doorstep planter is left out)
        elif not (bed and math.dist(turn([[rx_, rz_]], h["yaw"])[0], (bed[0] - h["x"], bed[1] - h["z"])) < 1.6):
            local.append(("rose_bed", rx_, rz_))
        local.append(("mailbox", x1 + 0.4, z1 + 2.2))
    placed = 0
    for kind, lx, lz in local:
        turn_by = float(hr.uniform(-0.3, 0.3))
        spots = [(lx, lz)]
        if kind == "mailbox":
            # A mailbox stands off the street (sixth round: "move some of the mailboxes off of the road ... to keep
            # the walk path clearer"): where its usual spot, 2.2 m before the front wall, is on the town ground, it
            # comes in toward its house, and failing that goes round the front corner onto the lawn, either side.
            spots = [(lx, lz), (lx, z1 + 1.3), (lx, z1 + 0.6), (x1 + 0.8, z1 - 0.2), (x0 - 0.8, z1 - 0.2), (x1 + 0.8, z1 - 1.4), (x0 - 0.8, z1 - 1.4)]
        for sx, sz in spots:
            dx, dz = turn([[sx, sz]], h["yaw"])[0]
            if kind == "mailbox":
                r_, c_ = round(h["z"] + dz) - Z0, round(h["x"] + dx) - X0
                if not (0 <= r_ < NZ and 0 <= c_ < NX) or from_street[r_, c_] < 0.7:
                    continue
            if kit_row(kind.split("@")[0], h["x"] + dx, h["z"] + dz, h["yaw"] + turn_by, group, by_door=kind.endswith("@door")):
                placed += 1
                if kind == "mailbox" and (sx, sz) != spots[0]:
                    mailboxes_moved += 1
                break
    garden_houses += 1 if placed else 0
def row(kind, x, z, yaw, group, blocking=False, radius=0.35, origin="base"):
    rows.append({"blocking": blocking, "group": group, "id": f"{kind}_ov{len(rows):04d}", "kind": kind, "origin": origin, "radius": radius,
                 "x": round(float(x), 3), "y": round(g(x, z), 3), "yaw": round(float(yaw), 4), "z": round(float(z), 3)})


def cell(x, z):
    r, c = int(round(z)) - Z0, int(round(x)) - X0
    return (r, c) if 0 <= r < NZ and 0 <= c < NX else None


# ---- 4b. the schoolhouse's white picket fence: both sides of Apple Road from the bridge down toward Sweet Apple
# Acres (as far as the Clubhouse Path), open where a path joins the road. A bay is 1.6 m and runs along its post's
# +x; each run ends in a post.
BAY = 1.6
fence_bays = 0
_sculpt = {}


def sculpt_g(x, z):
    """The game's own ground (the sculpt overlay apply_ground.py wrote, bilinear, as the terrain reads it): by the
    bridge's feet the build's 1 m grid stands up to 0.6 m off it (2026-11-21: a fence bay half under the grass)."""
    key = f"{math.floor(x / 1024)}_{math.floor(z / 1024)}"
    if key not in _sculpt:
        path = os.path.join(ROOT, "world/terrain/sculpt", key, "ponyville_overhaul_20261113", "height.f32")
        _sculpt[key] = np.fromfile(path, "<f4").reshape(1024, 1024) if os.path.exists(path) else None
    h = _sculpt[key]
    if h is None:
        return g(x, z)
    c, r = x - math.floor(x / 1024) * 1024, z - math.floor(z / 1024) * 1024
    c0, r0 = min(1022, int(c)), min(1022, int(r)); fx, fz = c - c0, r - r0
    return float(h[r0, c0] * (1 - fx) * (1 - fz) + h[r0, c0 + 1] * fx * (1 - fz) + h[r0 + 1, c0] * (1 - fx) * fz + h[r0 + 1, c0 + 1] * fx * fz)
apple = next((r for r in plan["roads"] if r.get("name") == "Apple Road"), None)
joins = [r for r in plan["roads"] if r.get("type") == "dirt" and r is not apple and len(r["points"]) > 1]
if apple:
    pts = np.array(apple["points"], float)
    club_path = next((r for r in joins if r.get("name") == "Clubhouse Path"), None)
    stop = np.array(club_path["points"][0]) if club_path else pts[-1]
    seg = np.hypot(*np.diff(pts, axis=0).T); run_len = np.concatenate([[0], np.cumsum(seg)])
    end_at = float(run_len[int(np.argmin(np.hypot(*(pts - stop).T)))]) - 4.0

    def on_road(s, side):
        k = min(len(seg) - 1, int(np.searchsorted(run_len, s, side="right")) - 1)
        t = (pts[k + 1] - pts[k]) / (seg[k] or 1)
        return pts[k] + t * (s - run_len[k]) + np.array([t[1], -t[0]]) * side * (apple["width"] / 2 + 1.1)

    for side in (1, -1):
        # (from the bridge's end, 2026-11-21 play test: from 3.5 m up the road, foals and Cheerilee cut through the gap
        # between the bridge and the fence instead of walking up the road to the school's gate)
        # (0.9: just past the bridge's end, whose deck the first bay clipped at 0.3)
        s = 0.9; prev = None; open_run = False
        while s <= end_at:
            p = on_road(s, side); q = on_road(s + BAY, side)
            mid = (p + q) / 2
            at = cell(*mid)
            clear = at is not None and not water[at] and from_water[at] > (0.6 if s < 3.5 else 1.5) and not walls[at] and from_way[at] > 1.5 \
                and all(G.line_dist(list(mid), r["points"]) > r["width"] / 2 + 1.6 for r in joins)
            if clear:
                d = q - p
                row("white_picket", p[0], p[1], math.atan2(-d[1], d[0]), "school", True, 0.3, "post"); fence_bays += 1
                # at the highest ground along the bay (its corner post's own spot dipped into the stream bank by the
                # bridge, and the bay stood two thirds under the grass)
                rows[-1]["y"] = round(max(sculpt_g(*p), sculpt_g(*mid), sculpt_g(*q)), 3)
                open_run = True; prev = q
            elif open_run:
                row("white_picket_post", prev[0], prev[1], 0.0, "school", True, 0.2, "post"); open_run = False
            s += BAY
        if open_run:
            row("white_picket_post", prev[0], prev[1], 0.0, "school", True, 0.2, "post")

# ---- 4c. Carrot Top's fields: beds of crops in ranks over the whole of each field (the old town's three round
# crop patches stood on the new ground like mounds; plan_scenery.py takes them out). A bed is 3 x 2 m; ranks run
# along the field's length, a walking strip between them, clear of the farmhouse, the windmill, roads and water.
crop_beds = 0
for f in plan.get("fields", []):
    if f["crop"] not in ("carrots", "vegetable rows"):
        continue
    (cx_, cz_), (w_, h_), ang = cv2.minAreaRect(np.array(f["points"], np.float32))
    if w_ < h_:
        w_, h_, ang = h_, w_, ang + 90.0
    a = math.radians(ang); ux, uz = math.cos(a), math.sin(a)
    inside_field = ndimage.binary_erosion(fill([f["points"]]), iterations=2)
    for j, v in enumerate(np.arange(-h_ / 2 + 1.5, h_ / 2 - 1.0, 3.1)):
        for u in np.arange(-w_ / 2 + 2.0 + (1.8 if j % 2 else 0.0), w_ / 2 - 1.5, 3.7):
            x, z = cx_ + ux * u - uz * v, cz_ + uz * u + ux * v
            at = cell(x, z)
            if at is None or not inside_field[at] or water[at] or from_water[at] < 2.5 or from_building[at] < 3.0 or from_road[at] < 2.2 or from_way[at] < 2.5:
                continue
            row("crop_row", x, z, -a, "carrot-farm", False, 1.6); crop_beds += 1

# ---- 4d. the flower meadow: drifts of flowers all over it, each kind in its own patches, thick enough to read as
# a field of colour from the road and close up; paths of open grass wind between the drifts
flowers = {}
if meadow.any():
    frng = np.random.default_rng(417)
    drift = {}
    for kind in ("lupin_clump", "daisy_clump", "sunflower_clump"):
        nz = ndimage.gaussian_filter(frng.standard_normal((NZ, NX)).astype(np.float32), 9.0)
        drift[kind] = nz / (nz.std() or 1)
    open_grass = ndimage.gaussian_filter(frng.standard_normal((NZ, NX)).astype(np.float32), 6.0)
    open_grass = np.abs(open_grass / (open_grass.std() or 1)) < 0.16            # winding strips left as grass
    spots = np.argwhere(meadow & ~water & (from_water > 2.0) & (from_building > 3.0) & (from_road > 1.8) & ~open_grass & ~steep)
    frng.shuffle(spots)
    # (1,200 clumps over the meadow were a clump every 4 m: thin. A clump is half a metre across; a drift needs
    # them nearly touching)
    quota = {"lupin_clump": 2300, "daisy_clump": 2600, "sunflower_clump": 1200, "flowering_shrub": 140, "rose_bed": 240}
    gap = {"lupin_clump": 0.0, "daisy_clump": 0.0, "sunflower_clump": 1.0, "flowering_shrub": 5.0, "rose_bed": 4.0}
    placed_at = {k: np.zeros((NZ, NX), bool) for k in quota}
    for r, c in spots:
        x, z = c + X0 + float(frng.uniform(0.1, 0.9)), r + Z0 + float(frng.uniform(0.1, 0.9))
        best = max(drift, key=lambda k: drift[k][r, c])
        roll = frng.random()
        kind = "flowering_shrub" if roll < 0.012 else "rose_bed" if roll < 0.024 else best
        if flowers.get(kind, 0) >= quota[kind] or (kind in drift and drift[kind][r, c] < 0.15):
            continue
        k = int(math.ceil(gap[kind]))
        if k and placed_at[kind][max(0, r - k):r + k + 1, max(0, c - k):c + k + 1].any():
            continue
        placed_at[kind][r, c] = True
        row(kind, x, z, frng.uniform(0, 6.283), "flower-meadow", False, 0.6 if kind in ("flowering_shrub", "rose_bed") else 0.35)
        flowers[kind] = flowers.get(kind, 0) + 1

# the town's wells (ponies draw water for their gardens at one): in the open corners of the squares
wells = 0
for wx_, wz_ in plan.get("wells", []):                      # the plan's own wells (third play test: not beside the Town Hall)
    rows.append({"blocking": True, "group": "plaza", "id": f"well_ov{len(rows):04d}", "kind": "well", "origin": "base", "radius": 1.1,
                 "x": round(wx_, 3), "y": round(g(wx_, wz_), 3), "yaw": round(float(rng.uniform(0, 6.283)), 4), "z": round(wz_, 3)})
    wells += 1
for sq in plan["grounds"]:
    pts = np.array(sq["points"], float); c0 = pts.mean(0)
    best = None
    if any(math.dist(w, c0) < 150 for w in plan.get("wells", [])):
        continue                                             # this square's well is one of the plan's
    for q in pts:
        at = q + (c0 - q) * 0.16
        r, c = round(at[1]) - Z0, round(at[0]) - X0
        if 0 <= r < NZ and 0 <= c < NX and squares[r, c] and from_building[r, c] > 2.2 and not water[r, c] and free(float(at[0]), float(at[1]), 3.0):
            score = from_building[r, c]
            if best is None or score > best[0]:
                best = (score, at)
    if best:
        x, z = float(best[1][0]), float(best[1][1])
        rows.append({"blocking": True, "group": "plaza", "id": f"well_ov{len(rows):04d}", "kind": "well", "origin": "base", "radius": 1.1,
                     "x": round(x, 3), "y": round(g(x, z), 3), "yaw": round(float(rng.uniform(0, 6.283)), 4), "z": round(z, 3)})
        take(x, z, 4.0); wells += 1
# and one more on a lawn beside a street, well away from the first, so the far side of town has one too
have = [(r_["x"], r_["z"]) for r_ in rows if r_["kind"] == "well"]
spots = np.argwhere(lawns & (from_building > 3.2) & (from_sage > 1.2) & (from_sage < 4.0) & (near_doors > 4) & ~water)
if len(spots):
    far = [min([math.dist((c + X0, r + Z0), w) for w in have] or [200.0]) for r, c in spots]
    order = np.argsort(far)[::-1]
    for k in order[:400]:
        r, c = spots[k]
        x, z = float(c + X0 + 0.5), float(r + Z0 + 0.5)
        if far[k] < 60:
            break
        if free(x, z, 4.0):
            rows.append({"blocking": True, "group": "plaza", "id": f"well_ov{len(rows):04d}", "kind": "well", "origin": "base", "radius": 1.1,
                         "x": round(x, 3), "y": round(g(x, z), 3), "yaw": round(float(rng.uniform(0, 6.283)), 4), "z": round(z, 3)})
            take(x, z, 4.0); break
# no garden plant on a doorstep planter (2026-11-21 play test: "check if potted plants and flower gardens overlap each
# other anywhere else"): a kit plant that touches a planter steps straight away from it until clear
PLANTER_R = 0.55
beds = [(p["x"], p["z"]) for p in props["outdoor"] if p["kind"] == "flowerbed"]
nudged = 0
for r_ in rows:
    for bx, bz in beds:
        gap = math.dist((r_["x"], r_["z"]), (bx, bz)); need = PLANTER_R + r_["radius"] + 0.05
        if gap < need:
            ux, uz = ((r_["x"] - bx) / gap, (r_["z"] - bz) / gap) if gap > 1e-3 else (1.0, 0.0)
            r_["x"] = round(bx + ux * need, 3); r_["z"] = round(bz + uz * need, 3); r_["y"] = round(g(r_["x"], r_["z"]), 3)
            nudged += 1
print(f"gardens: {nudged} plants stepped off a doorstep planter")
kit["entries"] = kept + rows
kit["overhaul"] = "Ponyville overhaul (tools/town_planner/build/plan_props.py): the old town's rows inside the plan's edge replaced by gardens beside the new houses."
open(kit_path, "w", encoding="utf-8", newline="").write(json.dumps(kit, indent="\t").replace("\n", "\r\n" if "\r\n" in kit_raw else "\n") + ("\r\n" if kit_raw.endswith("\r\n") else "\n" if kit_raw.endswith("\n") else ""))

# ---- 5. Sweet Apple Acres ----
farm_path = os.path.join(ROOT, "world/props/ponyville/farm_layout.json")
farm_raw = open(farm_path, encoding="utf-8").read()
farm = json.loads(farm_raw)
yard = fields.get("farmyard", [None])[0]
orch = fields.get("apple orchard", [None])[0]
runs = []
if yard:
    ring = yard + [yard[0]]
    # fence posts every 2.4 m round the yard, 2 m out; open where a road comes in
    pts = []
    for i in range(len(ring) - 1):
        a, b = np.array(ring[i]), np.array(ring[i + 1]); L = np.linalg.norm(b - a)
        for t in np.arange(0, L, 2.4):
            pts.append(a + (b - a) * t / (L or 1))
    cx, cz = np.mean(yard, axis=0)
    run = []
    for p in pts:
        out = p - [cx, cz]; out /= (np.linalg.norm(out) or 1)
        q = p + out * 2.0
        r, c = int(round(q[1])) - Z0, int(round(q[0])) - X0
        open_here = not (0 <= r < NZ and 0 <= c < NX) or from_road[r, c] < 3.5 or water[r, c] or buildings[r, c]
        if open_here:
            if len(run) >= 2:
                runs.append(run)
            run = []
        else:
            run.append([round(float(q[0]), 1), round(float(q[1]), 1)])
    if len(run) >= 2:
        runs.append(run)
    farm["fences"] = [{"points": r} for r in runs]
if orch:
    # the orchard's rows within 30 m of the farmyard (the plan's orchard ring is wider than the farm needs)
    near_yard = fill([orch]) & ndimage.binary_dilation(fill([yard]), iterations=30) & ~ndimage.binary_dilation(fill([yard]), iterations=4) & ~roads & ~water
    # and round the Crusaders' clubhouse, which stands hidden among the apple trees
    club = next((l for l in plan["landmarks"] if l["id"] == "cutiemarkcrusaders_clubhouse_01"), None)
    if club:
        _r = np.hypot(_xx0 + X0 - club["x"], _yy0 + Z0 - club["z"])
        near_yard |= fill([orch]) & (_r <= 34) & (_r >= 7) & ~roads & ~water
    contours, _ = cv2.findContours(near_yard.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    big = max(contours, key=cv2.contourArea)
    orch = [[float(p[0][0] + X0), float(p[0][1] + Z0)] for p in cv2.approxPolyDP(big, 2.0, True)]
    o = np.array(orch)
    farm["orchard"]["x"] = [round(float(o[:, 0].min()), 1), round(float(o[:, 0].max()), 1)]
    farm["orchard"]["z"] = [round(float(o[:, 1].min()), 1), round(float(o[:, 1].max()), 1)]
    farm["orchard"]["inside"] = [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in orch]
farm["_why"] = ("Sweet Apple Acres dressing, moved for the Ponyville overhaul (tools/town_planner/build/plan_props.py): fences round the "
                "planned farmyard, open where roads come in; the orchard rows inside the planned orchard (`inside`). World XZ metres; heights "
                "come from the ground at runtime.")
open(farm_path, "w", encoding="utf-8", newline="").write(json.dumps(farm, indent="\t").replace("\n", "\r\n" if "\r\n" in farm_raw else "\n") + ("\r\n" if farm_raw.endswith("\r\n") else "\n" if farm_raw.endswith("\n") else ""))

# ---- 6. bunting: strings of pennants where the plan's "bunting" lines run (drawn with the railway tool): each
# corner of a line is tied to the Town Hall banner, the Town Hall or the house it stands at; a string hangs
# between each pair with a little sag. apply_props.gd makes them.
BANNER_TOP = 5.95                # the banner model's pole top (plan_scenery.py sets them BANNER_SIZE tall)
moves = json.load(open(os.path.join(OUT, "scenery_moves.json")))
banners = [(m["x"], m["z"], m["y"] + BANNER_TOP * m["size"]) for i, m in moves.items() if i.startswith("hall_banner_")]
leans = G.house_leans(plan)
strings = []


def tie(p, other):
    """Where a string's end at plan point p is tied: [x, y, z]."""
    near = min(banners, key=lambda b: math.dist(p, b[:2]), default=None)
    if near and math.dist(p, near[:2]) < 4.0:
        return [near[0], near[2], near[1]]
    if math.dist(p, (hall["x"], hall["z"])) < 11.0:
        # the hall is round: on its wall's rim, on the side the string leaves by
        k = hall.get("scale") or DESIGNS["town_hall"]["scale"]
        d = math.dist(other, (hall["x"], hall["z"])) or 1.0
        return [hall["x"] + (other[0] - hall["x"]) / d * 0.262 * k, g(hall["x"], hall["z"]) + 0.505 * k, hall["z"] + (other[1] - hall["z"]) / d * 0.262 * k]
    n = min(range(len(plan["houses"])), key=lambda i: math.dist(p, (plan["houses"][i]["x"], plan["houses"][i]["z"])))
    h = plan["houses"][n]
    if math.dist(p, (h["x"], h["z"])) > 9.0:
        return None
    k = h.get("scale") or DESIGNS[h["design"]]["scale"]
    lx, ly, lz = G.ROOF_TIE.get(h["design"], (0.0, G.HOUSE_TOP.get(h["design"], 0.9) * 0.9, 0.0))
    lx += leans[n][0] * ly; lz += leans[n][1] * ly
    dx, dz = turn([[lx * k, lz * k]], h["yaw"])[0]
    return [h["x"] + dx, g(h["x"], h["z"]) + ly * k, h["z"] + dz]


for line in plan.get("railways", []):
    if line.get("name") != "bunting":
        continue
    pts = line["points"]
    for i in range(len(pts) - 1):
        a_, b_ = tie(pts[i], pts[i + 1]), tie(pts[i + 1], pts[i])
        if a_ and b_ and math.dist(a_, b_) > 2.0:
            strings.append([[round(v, 3) for v in a_], [round(v, 3) for v in b_]])
props["bunting"] = strings
json.dump(props, open(os.path.join(OUT, "props.json"), "w"), indent=1)

from collections import Counter
print("vegetation tiles:", ", ".join(f"{k} ({n} cells)" for k, n in written))
print(f"town trees: {len(props['trees'])}; street furniture: {dict(Counter(p['kind'] for p in props['outdoor']))}")
print(f"gardens: {len(rows)} kit rows beside {garden_houses} houses ({dict(Counter(r['kind'] for r in rows))}); old kit rows kept outside: {len(kept)}")
print(f"mailboxes moved off the street: {mailboxes_moved}")
print(f"school fence: {fence_bays} bays; crop beds: {crop_beds}; meadow flowers: {flowers}; bunting strings: {len(strings)}")
print(f"Sweet Apple Acres: {len(runs)} fence runs, orchard {farm['orchard']['x']} x {farm['orchard']['z']}")
