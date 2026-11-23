"""Build step 5 (planning half): where every piece of the town's baked scenery goes.

usage: python tools/town_planner/build/plan_scenery.py <project> <plan.json>
Writes build/out/scenery_moves.json for apply_scenery.gd, and updates world/props/ponyville/rnl_scenery.json
and the bridge list in world/navigation/river_crossings.gd to match.

- The plan's landmarks go exactly where the plan puts them (same node names, so the walk-in homes, the
  spa, the Hayburger and the Trixie show still find them).
- Each landmark's own dressing (its sign, statue, pots, benches, lamps) moves with it as one piece, as do
  the props round the fountain, the Town Hall's banners, Sugarcube Corner's party things, the carrot farm's
  crop patches and hay, Sweet Apple Acres' sheds, well, barrels and hay, Fluttershy's henhouse and flowers.
  A moved prop that would stand in a house, a landmark, the water or a road is left out.
- The second market (the food stalls' kiosks and tents) moves to a free spot by the plaza; Twilight's
  balloon and its picnic tables to a free spot of grass near the library (Balloon Hill).
- The plan's bridges replace the old four: the old bridge nodes are reused and copied, each stretched
  to its span and set level with its banks.
- Everything else inside the plan's edge (old lamps, banners, yard clutter, hay in old fields, the old
  river picnic spot) is taken out; step 6 sets new lamps and benches.
Heights (from the scenery's own nodes, build/out/scenery_nodes.json from dump_scenery.gd, not the list): a
building's floor stands 12 cm clear of the highest ground under it; the Cloudominium keeps its height in the
sky; everything else keeps its height above the ground. The fountain's benches turn their backs to it;
Trixie's trunk and cannon stand beside her walk-in wagon. Stalls' goods and banners go with the nearest stall.
"""
import json, math, os, re, subprocess, sys
import numpy as np

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
plan = json.load(open(PLAN, encoding="utf-8"))
scen_path = os.path.join(ROOT, "world/props/ponyville/rnl_scenery.json")
raw = open(scen_path, encoding="utf-8").read()
scen = json.loads(raw)
E = {e["id"]: e for e in scen["entries"]}
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
DESIGNS = TOWN["designs"]
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}

# ---- ground: the new 1 m grid and the old 2 m one ----
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; GX0, GZ0 = int(grid["origin"][0]), int(grid["origin"][1])
new_ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
gj = json.load(open(os.path.join(HERE, "..", "data", "ground.json")))
old_ground = np.fromfile(os.path.join(HERE, "..", "data", "heights.f32"), "<f4").reshape(gj["rows"], gj["columns"])
edge = plan["edges"][0]["points"]
BX0, BX1 = min(p[0] for p in edge), max(p[0] for p in edge)
BZ0, BZ1 = min(p[1] for p in edge), max(p[1] for p in edge)


def in_box(x, z):
    return BX0 <= x <= BX1 and BZ0 <= z <= BZ1


def g_new(x, z):
    return float(new_ground[min(NZ - 1, max(0, round(z) - GZ0)), min(NX - 1, max(0, round(x) - GX0))])


def g_old(x, z):
    return float(old_ground[min(gj["rows"] - 1, max(0, round((z - gj["bounds"][2]) / 2))), min(gj["columns"] - 1, max(0, round((x - gj["bounds"][0]) / 2)))])


# where each piece really stands (dump_scenery.gd): the list keeps a building's lowest ground, not its floor
NODES = json.load(open(os.path.join(OUT, "scenery_nodes.json")))
PAD_LIFT = {k.rsplit("/", 1)[-1]: float(v) for k, v in json.load(open(os.path.join(ROOT, "world/towns/ponyville/pad_lifts.json"), encoding="utf-8")).get("nodes", {}).items()
            if k.startswith("RNLScenery/")}
FLOOR_CLEAR = 0.12            # a building's floor above the highest ground under it
# buildings whose model stands into the ground (the old town had them so): the Golden Oak's roots and doorstep
# (set 12 cm clear, its trunk floated, a brown board ran out from its door and Twilight could not walk out), the
# henhouse's fence feet
# The barn's floor stands half a metre over the ground, its ramp's toe on the ground: 12 cm clear, the toe (where a
# pony stands to go in) lay 0.33 m under the grass, and going in or out never finished.
# Fourth round: the barn and the stage by Trixie's wagon stand down in the ground until their cobble foundations
# (top 5 cm over the node) do not show; the barn's ramp toe is then under the grass, and house_interior.gd lifts
# the spot a pony goes in from onto the ground.
SEAT = {"goldenoaklibrary_01": -0.62,  # (2026-11-21: -0.46 -> -0.62, its door ramp mostly underground)
        "henhouse_02": -0.22, "henhouse_01": -0.1, "appleacres_barned_01": -0.22, "schoolhouse_theatre_01": -0.07,
        "rarityboutique_01": -0.07,                    # (fifth round: the boutique's foundation showed too)
        # (2026-11-23: the Hayburger is built for a floor 4 cm over the street (its door markers lie 4 cm under the floor,
        # hayburger_runtime.gd); 12 cm clear, the step from the street up onto its floor was 0.16 m, over a pony's 0.117 m
        # step: every customer it took in gave up at the door, "No safe route", and none ever ate there)
        "burger_joint_01": 0.0,
        # (2026-11-18 play test: "lower the day spa, the school house, and the windmill next to the school house until
        # the cobblestone base isn't visible": the spa's cobble plate, the school's band under its walls and the
        # windmill's under its plinth, each 0.1-0.15 m, and the ground under them not quite level)
        "spa_01": -0.18, "schoolhouse_01": -0.1, "windmill_02": -0.3,
        # (2026-11-21 play test: "lower the hospital, Carrot Top's farmhouse, and the windmill next to it just enough
        # that the cobblestone underneath each is no longer visible": the hospital's stone base runs to a ledge 0.4 m
        # up its node, the farmhouse's and the windmill's (the same model as windmill_02) about 0.3 m)
        "general_hospital_01": -0.4, "sweetappleacres_carrot_farmhouse_01": -0.3, "windmill_01": -0.3}
# pieces set level on the ground (their old tilt dropped), at this height from it (2026-11-21 play test: the small
# hay pile by Carrot Top's farm stood tilted, 0.4 m up in the air)
LEVEL = {"hay_pile_small_01": -0.03}
# (round 8, 2026-11-18: the barn's cobble apron and door step still showed 0.1-0.15 m: -0.07 -> -0.22)
# pieces that are not buildings and whose model stands over its own node: the Town Square fountain's base is
# 0.18 m above it, and floated
# and the picnic tables, whose model stands on its node: they kept the old pads' lift and stood 9-12 cm off the
# new ground (2026-11-22 play test: the one before the Hayburger "is floating")
SINK = {"fountain_01": 0.2, "picnictable_01": 0.086, "picnictable_03": 0.121, "picnictable_04": 0.096}
# what the old dressing groups leave behind: the round crop patches (14 m discs of soil that stood on the new
# ground like mounds; the fields get rows of crops instead, plan_props.py)
# and the 12 x 9 m bush clump behind Fluttershy's cottage: one piece, it hung in the air over the mound's side, and
# there is no ground level enough for it near the cottage
# and the spa's plant pot that came to stand in the middle of the Town Square
DROP = {"carrotfarm_01", "cabbagefarm_01", "plantfarm_01", "bush1_small_01", "plantpot_01"}
DOOR_STEP = {"goldenoaklibrary_01": 0.57}      # its door sill above its node (old floor -12.59, node -13.16)
BANNER_SIZE = 1.45            # the Town Hall's street banners, taller than the old ones (bunting hangs from their tops)


def wet(x, z):
    r, c = round(z) - GZ0, round(x) - GX0
    return 0 <= r < NZ and 0 <= c < NX and water[r, c]


def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def local_footprint(e):
    fp = e.get("footprint") or []
    if len(fp) < 3:
        return [[-1, -1], [1, -1], [1, 1], [-1, 1]]
    return turn([[p[0] - e["position"][0], p[1] - e["position"][2]] for p in fp], -e.get("yaw", 0.0))


def footprint_at(e, x, z, yaw):
    return [[x + p[0], z + p[1]] for p in turn(local_footprint(e), yaw)]


# ---- where the Town Hall and Sugarcube Corner were and are (they live in town.tscn) ----
old_town = subprocess.run(["git", "-C", ROOT, "show", "43f4c21:world/towns/ponyville/town.tscn"], capture_output=True, text=True, encoding="utf-8").stdout


def old_transform(name):
    m = re.search(r'\[node name="' + name + r'"[^\]]*\]\s*transform = Transform3D\(([^)]*)\)', old_town)
    v = [float(t) for t in m.group(1).split(",")]
    s = math.sqrt(v[0] ** 2 + v[3] ** 2 + v[6] ** 2)
    return v[9], v[11], math.atan2(v[2], v[8])


anchors_old, anchors_new = {}, {}
for name, design in (("town_hall", "town_hall"), ("sugarcube_corner", "sugarcube")):
    anchors_old[name] = old_transform(name)
    h = next(h for h in plan["houses"] if h["design"] == design)
    anchors_new[name] = (h["x"], h["z"], h["yaw"])
planned = {l["id"]: (l["x"], l["z"], l["yaw"]) for l in plan["landmarks"]}
for i, e in E.items():
    anchors_old[i] = (e["position"][0], e["position"][2], e.get("yaw", 0.0))
for i, v in planned.items():
    anchors_new[i] = v

# each group's anchor: what its other members move with
GROUP_ANCHOR = {
    "west/station": "trainstation_01", "west/library": "goldenoaklibrary_01", "west/carrot-farm": "sweetappleacres_carrot_farmhouse_01",
    "south/school": "schoolhouse_01", "south/hospital": "general_hospital_01", "east/plaza": "fountain_01",
    "east/fair": "tent_friagram_red_01", "east/trixie": "trixie_wagon_01", "east/shops": "spa_01",
    "town/town-hall": "town_hall", "central/boutique": "rarityboutique_01",
    "everfree/fluttershy": "snazzys_fluttershy_cottage_01", "town/sugarcube-party": "sugarcube_corner",
    "sweet-apple-acres/farmyard": "appleacres_barned_01", "sweet-apple-acres/hay": "appleacres_barned_01",
    "sweet-apple-acres/cider": "appleacres_barned_01", "sweet-apple-acres/harvest": "appleacres_barned_01",
    "sweet-apple-acres/clubhouse": "cutiemarkcrusaders_clubhouse_01", "east/sky": "cloudominium_01",
}
# (east/square and east/boutique were the old east town's second square and second boutique site, far from the
# buildings they are named for: carried along with those they came to stand in the southern meadows and under the
# Cloudominium, a statue, benches and lamps in open country)
CLEAR = {"east/streets", "east/gateways", "east/junctions", "town/gateways", "town/junctions", "town/yards", "town/south-green",
         "river/picnic", "fields/hay", "east/square", "east/boutique"}

# ---- what is solid in the new town: houses (their whole models), the plan's landmarks, roads ----
solid = []
for h in plan["houses"]:
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    if h["design"] in MODEL:
        x0, x1, z0, z1 = MODEL[h["design"]]
        pts = [[x0 * k, z0 * k], [x1 * k, z0 * k], [x1 * k, z1 * k], [x0 * k, z1 * k]]
    else:
        pts = [[p[0] * k, p[1] * k] for p in d["footprint"]]
    solid.append([[h["x"] + p[0], h["z"] + p[1]] for p in turn(pts, h["yaw"])])
solid_of = {}
for i, (x, z, yaw) in planned.items():
    if i in E and i != "cloudominium_01":
        solid_of[i] = footprint_at(E[i], x, z, yaw)
        solid.append(solid_of[i])


def inside(poly, p):
    hit = False; j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
        j = i
    return hit


def seg_dist(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / ((dx * dx + dz * dz) or 1)))
    return math.hypot(a[0] + t * dx - p[0], a[1] + t * dz - p[1])


def samples(poly):
    xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
    out = list(poly)
    for x in np.arange(min(xs), max(xs) + 0.01, 1.0):
        for z in np.arange(min(zs), max(zs) + 0.01, 1.0):
            if inside(poly, (x, z)):
                out.append((x, z))
    return out


ROADS = [r for r in plan.get("roads", []) if r.get("type") == "dirt"] + [dict(r, width=4.0) for r in plan.get("railways", []) if not r.get("outside") and r.get("name") != "bunting"]
# the town's streets: dressing that moves with its landmark must not come to stand in one (the fountain's, the Town
# Hall's and the market's own things stand in their squares on purpose)
STREETS = [r for r in plan.get("roads", []) if r.get("type", "town") == "town" and len(r["points"]) > 1]
IN_SQUARES = {"east/plaza", "town/town-hall", "east/fair", "town/market", "east/trixie"}


def blocked(poly, own=None, streets=False):
    pts = samples(poly)
    if streets:
        for r in STREETS:
            if any(min(seg_dist(p, r["points"][i], r["points"][i + 1]) for i in range(len(r["points"]) - 1)) < r["width"] / 2 + 0.4 for p in pts):
                return "street"
    for s in solid:
        if s is own:
            continue
        if any(inside(s, p) for p in pts) or any(inside(poly, p) for p in s):
            return "building"
    if any(wet(*p) for p in pts):
        return "water"
    for r in ROADS:
        if any(min(seg_dist(p, r["points"][i], r["points"][i + 1]) for i in range(len(r["points"]) - 1)) < r["width"] / 2 for p in pts):
            return "road"
    return None


moves, report = {}, {"exact": 0, "with its landmark": 0, "left out (in the way)": [], "cleared": 0, "kept outside": 0}


def place(i, x, z, yaw, old=None):
    """Its node's new place. Height: a building's floor stands just clear of the highest ground under it (the
    old town cut each one a pad; the list's own height is the lowest ground there, well under the floor); a
    sky building keeps its height above the ground; everything else keeps its node's height above the old
    ground (the old pads' lifts included)."""
    e = E[i]
    ox, oy, oz = e["position"]
    node_y = float(NODES[i][1]) if i in NODES else oy
    if e.get("fit") == "building":
        under = [g_new(*p) for p in samples(footprint_at(e, x, z, yaw))]
        # (a pad the plan sets the height of is level at that height; the rise to its door is not its floor)
        level = plan.get("terrain", {}).get("pad_levels", {}).get(i)
        y = (max(under) if level is None else float(level)) + SEAT.get(i, FLOOR_CLEAR)
    elif e.get("fit") == "sky":
        y = g_new(x, z) + (node_y - g_old(ox, oz))
    elif i in LEVEL:
        y = g_new(x, z) + LEVEL[i]
    else:
        y = g_new(x, z) + (node_y - oy) - SINK.get(i, 0.0)   # the list's height is the ground it was set on
    moves[i] = {"action": "move", "x": round(x, 3), "z": round(z, 3), "y": round(y, 3), "yaw": round(yaw, 5), "list_y": round(y - (node_y - oy), 3)}
    if i in LEVEL:
        moves[i]["level"] = True
    if i == "appleacres_barned_01" and isinstance(e.get("door"), dict):
        # "the barn" as a place to meet is the farmyard before its door, not its middle (place_directory.gd reads a
        # NavigationAnchor child): 9 m out from the door
        q = turn([[e["door"]["point"][0] - ox, e["door"]["point"][1] - oz]], yaw - e.get("yaw", 0.0))[0]
        d = math.hypot(*q) or 1.0
        moves[i]["nav_anchor"] = [round(x + q[0] * (d + 9.0) / d, 2), round(z + q[1] * (d + 9.0) / d, 2)]


# the Town Hall's banners stand where the plan's "banner" notes are, facing the hall
banner_notes = [n for n in plan.get("notes", []) if str(n.get("text", "")).strip().lower() == "banner"]

# 1. the plan's landmarks
for i, (x, z, yaw) in planned.items():
    if i in E:
        place(i, x, z, yaw); report["exact"] += 1
# 2. dressing with its landmark
for i, e in E.items():
    if i in moves or e["group"] == "bridges":
        continue
    if i in DROP or (banner_notes and e["group"] == "town/town-hall" and "banner" in e["model"]):
        moves[i] = {"action": "remove"}; continue
    ox, oz = e["position"][0], e["position"][2]
    anchor = GROUP_ANCHOR.get(e["group"])
    if e["group"] in ("east/fair", "town/market", "east/balloon-hill"):
        # a stall's own goods and banners go with the nearest tent, kiosk or stand the plan places
        near = [j for j, o in E.items() if o["group"] == e["group"] and j in planned and j != i]
        anchor = min(near, key=lambda j: math.dist((E[j]["position"][0], E[j]["position"][2]), (ox, oz))) if near else None
    if anchor and anchor in anchors_new and anchor != i:
        ax, az, ayaw = anchors_old[anchor]; nx_, nz_, nyaw = anchors_new[anchor]
        dyaw = nyaw - ayaw
        rx, rz = turn([[ox - ax, oz - az]], dyaw)[0]
        x, z = nx_ + rx, nz_ + rz
        yaw = e.get("yaw", 0.0) + dyaw
        # goods on a stall's counter stand inside its outline: its own outline is not in their way
        no_streets = e["group"] not in IN_SQUARES
        why = blocked(footprint_at(e, x, z, yaw), own=solid_of.get(anchor), streets=no_streets)
        loose = e["group"] in ("east/fair", "town/market") and e.get("class") == "none"
        if loose and math.dist((ox, oz), (ax, az)) > 3.5:
            # loose goods that lay about the old fairground, not at a stall: with the stalls set out afresh they
            # would lie in the middle of a street
            why = why or "not by a stall"
        if why and not loose:
            # step aside, up to 8 m, before giving up (a stall's loose goods are left out instead: bananas that
            # cannot lie by their stall should not lie in the street)
            for ring in range(1, 9):
                spots = [(x + math.cos(k * math.pi / 6) * ring, z + math.sin(k * math.pi / 6) * ring) for k in range(12)]
                free = [s for s in spots if not blocked(footprint_at(e, s[0], s[1], yaw), streets=no_streets)]
                if free:
                    x, z = free[0]; why = None; report.setdefault("stepped aside", []).append(i); break
        if why:
            moves[i] = {"action": "remove"}; report["left out (in the way)"].append(f"{i} ({why})")
        else:
            if e["model"] == "props_mlpprops__lyrasbench" and e["group"] == "east/plaza":
                # the fountain's benches sit with their backs to it (the model's seat faces its +x)
                yaw = math.atan2(x - nx_, z - nz_) - math.pi / 2
            place(i, x, z, yaw); report["with its landmark"] += 1
            solid.append(footprint_at(e, x, z, yaw)) if e.get("class") in ("building", "walk") else None


# the fountain's three benches evenly round it (2026-11-21 play test: "I want those to be symmetrical around the
# fountain"; one stood 14 degrees round and 1.5 m further out than the others): all at the same distance, a quarter
# turn apart, the middle one where it is, backs to the fountain
_fb = [i for i, e in E.items() if e["model"] == "props_mlpprops__lyrasbench" and e["group"] == "east/plaza" and moves.get(i, {}).get("action") == "move"]
if len(_fb) == 3 and "fountain_01" in anchors_new:
    _fx, _fz = anchors_new["fountain_01"][0], anchors_new["fountain_01"][1]
    _ang = {i: math.atan2(moves[i]["x"] - _fx, moves[i]["z"] - _fz) for i in _fb}
    _wrap = lambda a: math.atan2(math.sin(a), math.cos(a))
    _mid = min(_fb, key=lambda i: sum(abs(abs(_wrap(_ang[j] - _ang[i])) - math.pi / 2) for j in _fb if j != i))
    _r = sorted(math.dist((moves[i]["x"], moves[i]["z"]), (_fx, _fz)) for i in _fb)[1]
    _targets = [_ang[_mid] + math.pi / 2, _ang[_mid] - math.pi / 2]
    for i in _fb:
        if i == _mid:
            a = _ang[i]
        else:
            a = min(_targets, key=lambda t: abs(_wrap(t - _ang[i]))); _targets.remove(a)
        place(i, _fx + _r * math.sin(a), _fz + _r * math.cos(a), a - math.pi / 2)
    report["fountain benches evened"] = _fb

# Trixie's trunk and cannon: beside the walk-in wagon the game builds at the plan's spot (trixie_wagon.gd, 1.65 times
# the scenery wagon, its door and steps at -z), on its right, clear of its body and its steps
if "trixie_wagon_01" in planned:
    wx, wz, wyaw = planned["trixie_wagon_01"]
    for i, local in (("trixie_trunk_01", (3.6, 1.8)), ("trixie_cannon_01", (4.6, -2.4))):
        if i in E:
            dx, dz = turn([list(local)], wyaw)[0]
            side_yaw = E[i].get("yaw", 0.0) + wyaw - anchors_old["trixie_wagon_01"][2]
            place(i, wx + dx, wz + dz, side_yaw)
            report["left out (in the way)"] = [s for s in report["left out (in the way)"] if not s.startswith(i + " ")]

# 3. the second market and the balloon: free spots (only where the plan does not place them itself)
def find_spot(members, centre, rings, prefer_town=None):
    """The first spot on rings round `centre` where the group (ids, kept in their old layout) fits."""
    ax, az = (sum(E[m]["position"][0] for m in members) / len(members), sum(E[m]["position"][2] for m in members) / len(members))
    for r in rings:
        for k in range(36):
            a = k * math.pi / 18
            cx, cz = centre[0] + math.cos(a) * r, centre[1] + math.sin(a) * r
            polys = [footprint_at(E[m], cx + E[m]["position"][0] - ax, cz + E[m]["position"][2] - az, E[m].get("yaw", 0.0)) for m in members]
            if any(blocked(p) for p in polys):
                continue
            if any(not in_box(*q) for p in polys for q in p):
                continue
            return cx - ax, cz - az
    return None


market = [i for i, e in E.items() if e["group"] == "town/market" and i not in moves]
if any(e["group"] == "town/market" and i in planned for i, e in E.items()):
    market = []; report["second market"] = "where the plan puts it"
fountain = planned.get("fountain_01")
spot = find_spot(market, (fountain[0], fountain[1]), range(18, 90, 3)) if market else None
if spot:
    for m in market:
        e = E[m]; place(m, e["position"][0] + spot[0], e["position"][2] + spot[1], e.get("yaw", 0.0))
        solid.append(footprint_at(e, e["position"][0] + spot[0], e["position"][2] + spot[1], e.get("yaw", 0.0)))
    report["second market"] = f"by the plaza, {math.dist(fountain[:2], (E[market[0]]['position'][0] + spot[0], E[market[0]]['position'][2] + spot[1])):.0f} m from the fountain"
balloon = [i for i, e in E.items() if e["group"] == "east/balloon-hill" and i not in moves]
if "airballoon_01" in planned:
    balloon = []; report["balloon"] = "where the plan puts it"
lib = planned.get("goldenoaklibrary_01")
town_poly = plan["grounds"][0]["points"] if plan.get("grounds") else []


def off_town(members, centre, rings):
    ax, az = (sum(E[m]["position"][0] for m in members) / len(members), sum(E[m]["position"][2] for m in members) / len(members))
    for r in rings:
        for k in range(36):
            a = k * math.pi / 18
            cx, cz = centre[0] + math.cos(a) * r, centre[1] + math.sin(a) * r
            if inside(town_poly, (cx, cz)):
                continue
            polys = [footprint_at(E[m], cx + E[m]["position"][0] - ax, cz + E[m]["position"][2] - az, E[m].get("yaw", 0.0)) for m in members]
            if any(blocked(p) for p in polys) or any(not in_box(*q) for p in polys for q in p):
                continue
            return cx - ax, cz - az
    return None


spot = off_town(balloon, (lib[0], lib[1]), range(30, 160, 4)) if balloon else None
if spot:
    for m in balloon:
        e = E[m]; place(m, e["position"][0] + spot[0], e["position"][2] + spot[1], e.get("yaw", 0.0))
    report["balloon"] = f"Balloon Hill at ({E['airballoon_01']['position'][0] + spot[0]:.0f}, {E['airballoon_01']['position'][2] + spot[1]:.0f})"

# 3a. the Town Hall's banners: copies of the old ones, taller, one at each "banner" note, facing the hall
hall_at = anchors_new["town_hall"]
banner_kinds = [next(j for j, o in E.items() if o["model"] == m) for m in ("rnl_ponyville_banner_pink", "rnl_ponyville_banner_blue", "rnl_ponyville_banner_green")
                if any(o["model"] == m for o in E.values())]
for k, n in enumerate(banner_notes):
    src = banner_kinds[k % len(banner_kinds)]
    sink = (float(NODES[src][1]) - E[src]["position"][1]) if src in NODES else 0.0
    moves[f"hall_banner_{k + 1:02d}"] = {"action": "copy", "copy_of": src, "x": round(n["x"], 3), "z": round(n["z"], 3),
                                         "y": round(g_new(n["x"], n["z"]) + sink * BANNER_SIZE, 3),
                                         "yaw": round(math.atan2(hall_at[0] - n["x"], hall_at[1] - n["z"]), 4), "size": BANNER_SIZE, "group": "town/town-hall"}
report["hall banners"] = len(banner_notes)

# 3b. springs: boulders and pebbles round the head of each spring pool, on the side its rise stands, so the river
# is seen to come out of the rocks (copies of the old river bank's boulders)
ROCKS = [("boulder_large_01", 0.0, 1.4, 1.25), ("boulder_medium_02", 0.62, 0.9, 1.2), ("boulder_medium_02", -0.7, 1.0, 1.0),
         ("boulder_small_02", 1.15, 0.6, 1.3), ("boulder_small_02", -1.25, 0.5, 1.1), ("boulder_large_02", 0.3, 3.4, 1.0),
         ("pebbles_large_01", -0.3, 0.2, 1.2), ("pebbles_medium_01", 0.9, 0.1, 1.2), ("pebbles_small_01", -0.95, 0.1, 1.3)]
rises = {m.get("name", ""): m for m in plan.get("terrain", {}).get("mounds", [])}
spring_rocks = 0
for n, lake in enumerate(plan.get("lakes", [])):
    rise = rises.get(str(lake.get("name")) + " rise")
    if not lake.get("spring") or rise is None:
        continue
    cx = sum(p[0] for p in lake["points"]) / len(lake["points"]); cz = sum(p[1] for p in lake["points"]) / len(lake["points"])
    reach = max(math.dist(p, (cx, cz)) for p in lake["points"])
    toward = math.atan2(rise["z"] - cz, rise["x"] - cx)
    for k, (src, off, back, size) in enumerate(ROCKS):
        if src not in E:
            continue
        a = toward + off
        # out from the middle until the ground is dry
        r = reach * 0.75
        while r < reach + 6 and wet(cx + math.cos(a) * r, cz + math.sin(a) * r):
            r += 0.4
        x, z = cx + math.cos(a) * (r + back), cz + math.sin(a) * (r + back)
        rid = f"spring_{n:02d}_{src.rsplit('_', 1)[0]}_{k}"
        sink = float(NODES[src][1]) - E[src]["position"][1] if src in NODES else -0.3
        moves[rid] = {"action": "copy", "copy_of": src, "x": round(x, 3), "z": round(z, 3), "y": round(g_new(x, z) + sink * size, 3),
                      "yaw": round((n * 1.7 + k * 2.3) % 6.283, 4), "size": size}
        spring_rocks += 1
report["spring rocks"] = spring_rocks

# 4. bridges: the plan's, the old nodes reused and copied
BRIDGE_CLIMB = 0.34          # the steepest a bridge's deck may be, rise over run (19 degrees)
# The three bridges to Town Hall arch higher, rounder as the show draws them (2026-11-22 play test): 1.3 times the
# climb (24 degrees at the feet, a rise of about 1.8 m). Timed with qc/lab_bridge_climb.gd, a pony trotting across took
# as long as before at canon size and at 1.35; at 1.4 times and over she stalled on the steep feet at 1.35 (20 s).
ROUND_BRIDGES = {"bridge_03", "bridge_04", "bridge_07"}
ROUND_CLIMB = BRIDGE_CLIMB * 1.3
# The model's four posts end 4.24 model units under its node in flat feet (the only vertices that low); squashed to a
# bridge's height they stopped half way down the stream. Each post reaches the ground under it (round_bridges.gd):
# its foot's centre in the model's own units, its half size, and how far into the ground it goes (metres).
POST_FEET = [(-5.905, 4.54), (5.905, 4.54), (-5.905, -4.55), (5.905, -4.55)]
POST_HALF = (0.475, 0.33)
POST_SINK = 0.25
template = E["bridge_01"]
SPAN = math.dist(*template["ends"])                 # the model's span at x scale 1 (local x runs end to end)
bridges = []
for k, b in enumerate(plan.get("bridges", [])):
    bid = f"bridge_{k + 1:02d}"
    (ax_, az_), (bx_, bz_) = b["a"], b["b"]
    length = math.dist(b["a"], b["b"])
    yaw = math.atan2(-(bz_ - az_), bx_ - ax_)        # local +x along the span: (cos yaw, -sin yaw)
    ha, hb = g_new(ax_, az_), g_new(bx_, bz_)
    sx = length / SPAN
    sz = max(0.55, min(1.2, b["width"] / 6.0))
    # the model's deck climbs 0.58 m a metre at its feet; squeezed to a short span at full height it was twice
    # as steep, more than a pony or the player can climb. Its height goes down with its length and further, so
    # the feet climb no steeper than BRIDGE_CLIMB
    sy = max(0.14, min(0.6, sx * (ROUND_CLIMB if bid in ROUND_BRIDGES else BRIDGE_CLIMB) / 0.58))
    # both feet stand on ground levelled to one height (elevation.py); a little under it, so no lip shows
    roll = math.atan2(hb - ha, length) if abs(hb - ha) > 0.08 else 0.0
    moves[bid] = {"action": "bridge", "x": round((ax_ + bx_) / 2, 3), "z": round((az_ + bz_) / 2, 3), "y": round((ha + hb) / 2 - 0.04, 3),
                  "yaw": round(yaw, 5), "roll": round(roll, 5), "scale": [round(sx, 4), round(sy, 4), round(sz, 4)],
                  "copy_of": None if bid in E else "bridge_01", "ends": [b["a"], b["b"]]}
    if bid in ROUND_BRIDGES:
        # the ground under each post (its footprint's lowest point), for round_bridges.gd
        cx_, cz_ = (ax_ + bx_) / 2, (az_ + bz_) / 2
        ux, uz = math.cos(yaw), -math.sin(yaw)        # local +x
        vx, vz = math.sin(yaw), math.cos(yaw)         # local +z
        floors = []
        for fx, fz in POST_FEET:
            under = []
            for dx in (-POST_HALF[0], 0.0, POST_HALF[0]):
                for dz in (-POST_HALF[1], 0.0, POST_HALF[1]):
                    lx, lz = (fx + dx) * sx, (fz + dz) * sz
                    under.append(g_new(cx_ + ux * lx + vx * lz, cz_ + uz * lx + vz * lz))
            floors.append(round(min(under) - POST_SINK, 3))
        moves[bid]["post_floors"] = floors
    bridges.append((bid, b["a"], b["b"]))
for i, e in E.items():
    if e["group"] == "bridges" and i not in moves:
        moves[i] = {"action": "remove"}

# 5. everything else inside the edge goes
for i, e in E.items():
    if i in moves:
        continue
    if in_box(e["position"][0], e["position"][2]):
        moves[i] = {"action": "remove"}; report["cleared"] += 1
    else:
        report["kept outside"] += 1

json.dump(moves, open(os.path.join(OUT, "scenery_moves.json"), "w"), indent=1)

# ---- the scenery list follows ----
new_entries = []
for e in scen["entries"]:
    m = moves.get(e["id"])
    if m is None:
        new_entries.append(e); continue
    if m["action"] == "remove":
        continue
    old_local = local_footprint(e)
    e = dict(e)
    old_pos, old_yaw = e["position"], e.get("yaw", 0.0)
    e["position"] = [m["x"], m.get("list_y", m["y"]), m["z"]]; e["yaw"] = m["yaw"]
    e["footprint"] = [[round(p[0], 2), round(p[1], 2)] for p in [[m["x"] + q[0], m["z"] + q[1]] for q in turn(old_local, m["yaw"])]]
    if m["action"] == "bridge":
        e["ends"] = [[round(v, 2) for v in p] for p in m["ends"]]
    if isinstance(e.get("door"), dict) and "point" in e["door"]:
        # the door goes with the building; its floor is the node's height, the ground the new ground at the door
        d = dict(e["door"])
        q = turn([[d["point"][0] - old_pos[0], d["point"][1] - old_pos[2]]], m["yaw"] - old_yaw)[0]
        d["point"] = [round(m["x"] + q[0], 2), round(m["z"] + q[1], 2)]
        d["floor"] = round(m["y"] + DOOR_STEP.get(e["id"], 0.0), 2); d["ground"] = round(g_new(*d["point"]), 2)
        e["door"] = d
    e["moved_by"] = "tools/town_planner (Ponyville overhaul)"
    new_entries.append(e)
for rid, m in moves.items():
    if m["action"] == "copy":
        e = dict(E[m["copy_of"]]); e["id"] = rid; e["group"] = m.get("group", "river/springs")
        e["position"] = [m["x"], m["y"], m["z"]]; e["yaw"] = m["yaw"]; e["moved_by"] = "tools/town_planner (Ponyville overhaul)"
        e.pop("footprint", None); e.pop("label", None)
        new_entries.append(e)
for bid, m in moves.items():
    if m["action"] == "bridge" and m["copy_of"]:
        e = dict(template); e["id"] = bid; e["label"] = f"Bridge {bid[-2:]}"
        e["position"] = [m["x"], m["y"], m["z"]]; e["yaw"] = m["yaw"]; e["roll"] = m["roll"]
        e["ends"] = [[round(v, 2) for v in p] for p in m["ends"]]; e["moved_by"] = "tools/town_planner (Ponyville overhaul)"
        e.pop("footprint", None)
        new_entries.append(e)
scen["entries"] = new_entries
nl = "\r\n" if "\r\n" in raw else "\n"
open(scen_path, "w", encoding="utf-8", newline="").write(json.dumps(scen, indent="\t", ensure_ascii=False).replace("\n", nl) + (nl if raw.endswith(("\n", "\r\n")) else ""))

# ---- the bridges pony trips use ----
rc_path = os.path.join(ROOT, "world/navigation/river_crossings.gd")
rc = open(rc_path, encoding="utf-8").read()
block = "const BRIDGE_ENDS := {\n" + "".join(
    f'\t"{bid}": [Vector2({a[0]:.2f}, {a[1]:.2f}), Vector2({b[0]:.2f}, {b[1]:.2f})],\n' for bid, a, b in bridges) + "}"
rc = re.sub(r"const BRIDGE_ENDS := \{.*?\n\}", lambda m: block, rc, count=1, flags=re.S)
rc = rc.replace("## Water: the town canal grid", "## Bridges since the Ponyville overhaul (tools/town_planner/build/plan_scenery.py): the plan's bridges.\n## Water: the town canal grid", 1) if "Ponyville overhaul" not in rc else rc
open(rc_path, "w", encoding="utf-8", newline="").write(rc)

# ---- pad lifts: props raised at load onto the old town's building pads; the new ground has none ----
lifts_path = os.path.join(ROOT, "world/towns/ponyville/pad_lifts.json")
if os.path.exists(lifts_path):
    lifts_raw = open(lifts_path, encoding="utf-8").read()
    lifts = json.loads(lifts_raw)
    before = len(lifts.get("nodes", {})) + len(lifts.get("kit", {}))
    lifts["nodes"] = {k: v for k, v in lifts.get("nodes", {}).items()
                      if not (k.startswith("TownTrees/") or (k.startswith("RNLScenery/") and k.rsplit("/", 1)[-1] in moves))}
    lifts["kit"] = {}
    lifts["_overhaul"] = "Ponyville overhaul (tools/town_planner): the lifts onto the old town's pads are gone with the pads."
    lifts_nl = "\r\n" if "\r\n" in lifts_raw else "\n"
    open(lifts_path, "w", encoding="utf-8", newline="").write(json.dumps(lifts, indent="\t").replace("\n", lifts_nl) + lifts_nl)
    print(f"pad lifts: {before} -> {len(lifts['nodes']) + len(lifts['kit'])}")

print(f"landmarks placed exactly: {report['exact']}; dressing moved with its landmark: {report['with its landmark']}; "
      f"cleared from the old town: {report['cleared']}; kept outside the edge: {report['kept outside']}; bridges: {len(bridges)}")
print("stepped aside to stand clear:", ", ".join(report.get("stepped aside", [])) or "none")
print("Town Hall banners at the plan's notes:", report.get("hall banners", 0))
print("boulders and pebbles at the springs:", report.get("spring rocks", 0))
print("second market:", report.get("second market", "NO SPOT")); print("balloon:", report.get("balloon", "NO SPOT"))
print(f"left out because they would stand in something ({len(report['left out (in the way)'])}):", ", ".join(report["left out (in the way)"]))

# ---- the town scene's own pins: world/props/ponyville/rnl_scenery_defaults.tscn (what town.tscn instances) sets a few
# of these nodes' positions over the baked scene's; they follow the moves, and a removed node's pin goes ----
defaults_path = os.path.join(ROOT, "world/props/ponyville/rnl_scenery_defaults.tscn")
text = open(defaults_path, encoding="utf-8").read()
nl = "\r\n" if "\r\n" in text else "\n"
blocks = re.split(r"(?=^\[)", text, flags=re.M)
kept, pinned = [], []
for b in blocks:
    m = re.match(r'\[node name="([^"]+)" parent=', b)
    if m and m.group(1) in moves:
        mv = moves[m.group(1)]
        if mv["action"] == "remove":
            pinned.append(m.group(1) + " (unpinned)"); continue
        b = re.sub(r"^position = Vector3\([^)]*\)", f"position = Vector3({mv['x']}, {mv['y']}, {mv['z']})", b, flags=re.M)
        pinned.append(m.group(1))
    kept.append(b)
open(defaults_path, "w", encoding="utf-8", newline="").write("".join(kept))
print("town scene pins:", ", ".join(pinned))
