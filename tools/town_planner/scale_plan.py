"""Scale a whole plan up (or down) about the town, keeping every building its real size.

usage: python tools/town_planner/scale_plan.py <plan.json> <factor> <out.json> [--house 0.9] [--home 0.95] [--roof-gap 1.0]

--house / --home: the size of background houses / real homes against the game's own (1 = full size). A real
home's front door is 1.94 m high at full size and the player's body 1.8 m, so homes stop at 0.95.

The official map draws its houses smaller than the game's: a house's roof, porch and steps reach 1-2 m
past its walls. Laid at the map's own proportions, most roofs overlap. This spreads everything apart
by `factor` (positions, roads, rivers and their widths, lakes, bridges, fields, trees, the edge, the
tracing map), puts every house back to its full size, then eases apart any buildings whose roofs still
touch (background houses give way; a background house that cannot fit is left out, never a real
home). The ground grid and the railway's links outside the map are dropped: run elevation.py and
rail_route.py on the result.
"""
import json, math, sys

SRC, FACTOR, OUT = sys.argv[1], float(sys.argv[2]), sys.argv[3]
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
plan = json.load(open(SRC, encoding="utf-8"))
tj = open(HERE + "/data/town.js", encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
SCEN = {s["id"]: s for s in TOWN["scenery"]}
# each design's whole model (roof, porch, steps) in model units, measured from the house scenes
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}
def arg(name, default):
    return float(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default
ROOF_GAP = arg("--roof-gap", 1.0)        # metres kept between roofs
HOUSE, HOME = arg("--house", 1.0), arg("--home", 1.0)
WATER_GAP = 1.5       # metres kept between a building and a river or lake
g = plan["grounds"][0]["points"] if plan.get("grounds") else [[110, -200]]
CX = sum(p[0] for p in g) / len(g); CZ = sum(p[1] for p in g) / len(g)


def sp(p):
    return [round(CX + (p[0] - CX) * FACTOR, 2), round(CZ + (p[1] - CZ) * FACTOR, 2)]


def move(item):
    if "x" in item:
        item["x"], item["z"] = sp([item["x"], item["z"]])
    if "points" in item:
        item["points"] = [sp(p) for p in item["points"]]
    for k in ("a", "b", "at"):
        if k in item and isinstance(item[k], list):
            item[k] = sp(item[k])


for kind in ("houses", "landmarks", "roads", "rivers", "lakes", "bridges", "flats", "notes", "edges", "grounds", "greens",
             "railways", "fields", "woods", "rail_links"):
    for item in plan.get(kind, []):
        move(item)
plan["railways"] = [r for r in plan.get("railways", []) if not r.get("outside")]
plan.pop("rail_network", None)
for r in plan.get("rivers", []):
    r["width"] = round(r["width"] * FACTOR, 1)
ref = plan["reference"]
ref["x"], ref["z"] = sp([ref["x"], ref["z"]]); ref["width"] = round(ref["width"] * FACTOR, 1)
terrain = plan.get("terrain", {})
for k in ("origin", "step", "columns", "rows", "low", "high", "heights"):
    terrain.pop(k, None)
for m in terrain.get("mounds", []):
    m["x"], m["z"] = sp([m["x"], m["z"]]); m["radius"] *= FACTOR; m["top"] *= FACTOR
houses = plan["houses"]
for h in houses:
    h.pop("scale", None)                    # full size again
    k = HOUSE if h.get("filler") else HOME
    if len(h["design"]) == 1 and k != 1.0:
        h["scale"] = round(TOWN["designs"][h["design"]]["scale"] * k, 4)


# ---- roofs apart ----
def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def shape(item):
    if "id" in item:
        s = SCEN[item["id"]]
        local = turn([[p[0] - s["x"], p[1] - s["z"]] for p in s["footprint"]], -s["yaw"])
        return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(local, item["yaw"])]
    d = TOWN["designs"][item["design"]]; k = item.get("scale") or d["scale"]
    if item["design"] in MODEL:
        x0, x1, z0, z1 = MODEL[item["design"]]
        pts = [[x0 * k, z0 * k], [x1 * k, z0 * k], [x1 * k, z1 * k], [x0 * k, z1 * k]]
    else:
        pts = [[p[0] * k, p[1] * k] for p in d["footprint"]]
    return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(pts, item["yaw"])]


def gap(A, B):
    """Separating-axis distance between two convex outlines (negative: they overlap)."""
    best = -1e9
    for P in (A, B):
        for i in range(len(P)):
            a, b = P[i], P[(i + 1) % len(P)]
            n = (b[1] - a[1], -(b[0] - a[0])); L = math.hypot(*n) or 1; n = (n[0] / L, n[1] / L)
            pa = [p[0] * n[0] + p[1] * n[1] for p in A]; pb = [p[0] * n[0] + p[1] * n[1] for p in B]
            best = max(best, min(pb) - max(pa), min(pa) - max(pb))
    return best


def seg_dist(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / ((dx * dx + dz * dz) or 1)))
    return math.hypot(a[0] + t * dx - p[0], a[1] + t * dz - p[1])


def inside(poly, p):
    hit = False; j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
        j = i
    return hit


def wet(item):
    """How far the building pokes into water (0: clear by WATER_GAP)."""
    pts = shape(item)
    pts = pts + [[(pts[i][0] + pts[(i + 1) % len(pts)][0]) / 2, (pts[i][1] + pts[(i + 1) % len(pts)][1]) / 2] for i in range(len(pts))]
    pts.append([item["x"], item["z"]])
    worst = 0.0
    for r in plan["rivers"]:
        for p in pts:
            d = min(seg_dist(p, r["points"][i], r["points"][i + 1]) for i in range(len(r["points"]) - 1))
            worst = max(worst, r["width"] / 2 + WATER_GAP - d)
    for l in plan["lakes"]:
        if any(inside(l["points"], p) for p in pts):
            worst = max(worst, 3.0)
    return worst


fixed = [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"] + [h for h in houses if len(h["design"]) > 1]
movable = [h for h in houses if len(h["design"]) == 1]
dropped = []
for round_ in range(80):
    items = fixed + movable
    shapes = [shape(i) for i in items]
    push = {}
    bad = 0
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if math.dist((items[i]["x"], items[i]["z"]), (items[j]["x"], items[j]["z"])) > 30:
                continue
            gg = gap(shapes[i], shapes[j])
            if gg >= ROOF_GAP:
                continue
            bad += 1
            dx, dz = items[j]["x"] - items[i]["x"], items[j]["z"] - items[i]["z"]; L = math.hypot(dx, dz) or 1
            need = (ROOF_GAP - gg) / 2 + 0.05
            wi = 0 if i < len(fixed) else (0.3 if not items[i]["filler"] else 1.0)
            wj = 0 if j < len(fixed) else (0.3 if not items[j]["filler"] else 1.0)
            if wi + wj == 0:
                continue
            for k, sign, w in ((i, -1, wi), (j, 1, wj)):
                if w:
                    px, pz = push.get(k, (0, 0))
                    push[k] = (px + sign * dx / L * need * 2 * w / (wi + wj), pz + sign * dz / L * need * 2 * w / (wi + wj))
    for k, (px, pz) in push.items():
        it = items[k]
        step = min(0.6, math.hypot(px, pz))
        if step:
            it["x"] += px / math.hypot(px, pz) * step; it["z"] += pz / math.hypot(px, pz) * step
            it["_moved"] = it.get("_moved", 0) + step
    if not bad:
        break
    # houses that have wandered far and still clash: background ones give way for good
    if round_ in (40, 60):
        clash = set()
        for i in range(len(fixed), len(items)):
            for j in range(len(items)):
                if i != j and math.dist((items[i]["x"], items[i]["z"]), (items[j]["x"], items[j]["z"])) < 30 and gap(shapes[i], shapes[j]) < 0:
                    clash.add(i)
        for i in sorted(clash, key=lambda i: -items[i].get("_moved", 0)):
            it = items[i]
            if it["filler"] and it.get("_moved", 0) > 3 and it in movable:
                movable.remove(it); dropped.append(it)
# out of the water
for h in list(movable):
    for _ in range(12):
        w = wet(h)
        if w <= 0:
            break
        # step away from the nearest water
        best = None
        for r in plan["rivers"]:
            for i in range(len(r["points"]) - 1):
                a, b = r["points"][i], r["points"][i + 1]
                d = seg_dist([h["x"], h["z"]], a, b)
                if best is None or d < best[0]:
                    t = max(0, min(1, ((h["x"] - a[0]) * (b[0] - a[0]) + (h["z"] - a[1]) * (b[1] - a[1])) / (((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) or 1)))
                    best = (d, [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])])
        if not best:
            break
        dx, dz = h["x"] - best[1][0], h["z"] - best[1][1]; L = math.hypot(dx, dz) or 1
        h["x"] += dx / L * min(1.0, w); h["z"] += dz / L * min(1.0, w)
    if wet(h) > 0 and h["filler"]:
        movable.remove(h); dropped.append(h)
# last pass: anything still overlapping a roof goes, background first
items = fixed + movable
left = 0
for i in range(len(fixed), len(items)):
    it = items[i]
    if it not in movable:
        continue
    for j in range(len(items)):
        o = items[j]
        if o is it or (o not in fixed and o not in movable):
            continue
        if math.dist((it["x"], it["z"]), (o["x"], o["z"])) < 30 and gap(shape(it), shape(o)) < 0:
            if it["filler"]:
                movable.remove(it); dropped.append(it)
            else:
                left += 1
            break
plan["houses"] = [h for h in houses if len(h["design"]) > 1] + movable
for h in plan["houses"]:
    moved = h.pop("_moved", 0)
    h["x"], h["z"] = round(h["x"], 2), round(h["z"], 2)
for l in plan["landmarks"]:
    l.pop("_moved", None)
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
real_lost = [h.get("name") for h in dropped if not h["filler"]]
print(f"scaled {FACTOR}x about ({CX:.0f}, {CZ:.0f}); map {ref['width']:.0f} m wide")
print(f"houses: {len(houses)} -> {len(plan['houses'])} ({len(dropped)} background houses left out, real homes lost: {real_lost or 'none'}); "
      f"real homes still touching: {left}")
