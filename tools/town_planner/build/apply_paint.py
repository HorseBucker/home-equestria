"""Build step 3: paint the plan's ground in the game (which ground texture lies where).

usage: python tools/town_planner/build/apply_paint.py <project> <plan.json> [--density minimum|low|medium]
(run after apply_ground.py, which leaves the 1 m grids in build/out)

Every square metre inside the plan's edge gets a texture (world/terrain/textures.json ids):
- the town: the show's sage packed earth (22, no grass blades, a path for ponies) along every town street
  (roof line to roof line), over the squares and as a short path from each front door to its street; everything
  else in the village is lawn (grass under the rows of houses and in the blocks behind them), with a ring of
  grass round the fountain and a band of grass along the Town Hall's walls (not before its steps); a landmark by
  a street gets a path to its door too
- dirt roads: the game's dirt trail (1); the railway runs on gravel (5)
- water: river bed (18) under every river and lake and up its first metre of bank
- fields: carrots and vegetable rows on field dirt (3), wheat on light grass (2), the Sweet Apple Acres
  farmyard on town dirt (4), the orchard on grass (0), the flower meadow on bright grass (17)
- countryside: grass (0) in broad drifts of light grass (2); under trees damp forest floor (11),
  thicker the thicker the trees, and the Everfree's gloomy grass (10)
Edges between textures blend over about a metre (Terrain3D base/overlay/blend, using each texture's
painted height so lawn edges break up). Written as a new published surface overlay per 1024 m region
(world/biomes/authored/surface/<region>/ponyville_overhaul_20261114), kept over the earlier overlay
everywhere outside the plan's box; bundle.json (which the game reads) and surface_index.json point at them.
To run again, first restore both from git.
--density <setting> (2026-11-19 play test: "When a home is removed, it still has the street leading to where its front
door was ... we need to have the streets painted differently for each density option"): the town's paint for that
density's plan (its own houses' door paths and lawns), written beside the full town's as
surface/<region>/ponyville_overhaul_20261114_<setting>; nothing else is touched. biome_field.gd index_at uses it when
the game's town density is that setting. Run after the full town's paint (build_density.py does it).
"""
import hashlib, json, math, os, sys
import cv2, numpy as np
from scipy import ndimage

ROOT, PLAN = sys.argv[1], sys.argv[2]
DENSITY = sys.argv[sys.argv.index("--density") + 1] if "--density" in sys.argv else ""
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TAG = "ponyville_overhaul_20261114"
SURF = os.path.join(ROOT, "world/biomes/authored")
REGION = 1024
plan = json.load(open(PLAN, encoding="utf-8"))
meta = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = meta["columns"], meta["rows"]
X0, Z0 = int(meta["origin"][0]), int(meta["origin"][1])
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
SCEN = {s["id"]: s for s in TOWN["scenery"]}

GRASS, TRAIL, GRASS_LIGHT, FIELD, TOWN_DIRT, GRAVEL = 0, 1, 2, 3, 4, 5
GLOOMY, FOREST_FLOOR, BRIGHT, RIVER_BED, SAGE = 10, 11, 17, 18, 22
CROP = {"carrots": FIELD, "vegetable rows": FIELD, "wheat": GRASS_LIGHT, "farmyard": TOWN_DIRT,
        "apple orchard": GRASS, "flower meadow": BRIGHT}
WOODS = {"scattered": 0.0, "sparse": 0.15, "medium": 0.3, "dense": 0.5, "forest": 0.75}


def px(points):
    return np.round((np.array(points, np.float64) - [X0, Z0]) * 8).astype(np.int32)


def fill(polys, value=1):
    m = np.zeros((NZ, NX), np.uint8)
    for p in polys:
        if len(p) >= 3:
            cv2.fillPoly(m, [px(p)], value, shift=3)
    return m.astype(bool)


def lines(items, width_of):
    m = np.zeros((NZ, NX), np.uint8)
    for it in items:
        cv2.polylines(m, [px(it["points"])], False, 1, max(1, int(round(width_of(it)))), shift=3, lineType=cv2.LINE_AA)
    return m.astype(bool)


def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def house_outline(h, grow=0.0):
    d = TOWN["designs"][h["design"]]; k = h.get("scale") or d["scale"]
    xs = [p[0] for p in d["footprint"]]; zs = [p[1] for p in d["footprint"]]
    x0, x1, z0, z1 = min(xs) * k - grow, max(xs) * k + grow, min(zs) * k - grow, max(zs) * k + grow
    return [[h["x"] + p[0], h["z"] + p[1]] for p in turn([[x0, z0], [x1, z0], [x1, z1], [x0, z1]], h["yaw"])]


def noise(scale_m, seed):
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal((NZ, NX)).astype(np.float32), scale_m / 2.5)
    return n / (n.std() or 1)


# ---- base: countryside grass in drifts of light grass ----
tex = np.full((NZ, NX), GRASS, np.uint8)
second = np.full((NZ, NX), GRASS_LIGHT, np.uint8)      # what the base fades towards
mix = np.clip(noise(60, 11) * 0.35 + 0.15, 0, 0.6)       # how far (0..1) towards `second`

# ---- trees: forest floor under them ----
for level in ("scattered", "sparse", "medium", "dense", "forest"):
    m = fill([w["points"] for w in plan.get("woods", []) if w["density"] == level])
    if level == "forest":
        tex[m] = GLOOMY; second[m] = FOREST_FLOOR; mix[m] = np.clip(noise(25, 12)[m] * 0.3 + 0.4, 0, 0.8)
    elif WOODS[level] > 0:
        second[m] = FOREST_FLOOR
        mix[m] = np.clip(WOODS[level] + noise(20, 13)[m] * 0.2, 0, 0.8)

# ---- fields ----
for f in plan.get("fields", []):
    m = fill([f["points"]])
    t = CROP.get(f["crop"], GRASS)
    tex[m] = t
    if t == BRIGHT:
        second[m] = GRASS; mix[m] = np.clip(noise(15, 14)[m] * 0.3 + 0.2, 0, 0.6)
    elif t == FIELD:
        second[m] = TOWN_DIRT; mix[m] = 0.15
    else:
        mix[m] = 0.0

# ---- the town: sage along its streets and over its squares, grass under the rows of houses ----
streets = [r for r in plan.get("roads", []) if r.get("type", "town") == "town"]
squares = fill([g["points"] for g in plan.get("grounds", [])])
# a street's sage runs from roof line to roof line: its width and half a metre of each side's front yard
town = squares | lines(streets, lambda r: r["width"] + 1.0)
# the plan's "paint_lawn" areas are grass, whatever street runs under them (2026-11-21 play test: the street's end
# reached out toward the Golden Oak's door: "trimmed down a bit with grass")
if plan.get("paint_lawn"):
    town &= ~fill(plan["paint_lawn"])
# the village: the streets with their rows and the blocks they enclose; its grass is lawn, not meadow
k = 22
yy, xx = np.ogrid[-k:k + 1, -k:k + 1]
village = ndimage.binary_closing(squares | lines(streets, lambda r: r["width"] + 26.0), structure=(xx * xx + yy * yy <= k * k))
lawns = fill([g["points"] for g in plan.get("greens", [])])
tex[village] = GRASS; second[village] = BRIGHT; mix[village] = np.clip(noise(18, 15)[village] * 0.12 + 0.15, 0, 0.35)
tex[town] = SAGE; mix[town] = 0.0
tex[town & lawns] = GRASS; second[town & lawns] = BRIGHT; mix[town & lawns] = 0.15
# a path of sage from every front door to its street
paths = np.zeros((NZ, NX), np.uint8)
clean_paths = np.zeros((NZ, NX), bool)


def straight_out(h, door, reach=9.0):
    """Where the street is straight out from a door, if it is within reach (2026-11-21 play test: Mayor Mare's path
    ran off at a slant to the nearest bit of street, past a lamp, not out of her door): else None, the nearest bit."""
    fx, fz = math.sin(h["yaw"]), math.cos(h["yaw"])
    for k in range(1, int(reach * 2) + 1):
        x, z = door[0] + fx * k * 0.5, door[1] + fz * k * 0.5
        r, c = int(round(z)) - Z0, int(round(x)) - X0
        if 0 <= r < NZ and 0 <= c < NX and town[r, c]:
            return [x, z]
    return None

ty, tx = np.nonzero(town)
from scipy.spatial import cKDTree
tree = cKDTree(np.stack([tx + X0, ty + Z0], 1)) if len(tx) else None
doorways = 0
def clean_strip(a, b, half=1.0):
    """Every cell within `half` m of the line a-b: a door path, kept clean of the edge blending (cell c is world X0 + c)."""
    x0_, x1_ = int(min(a[0], b[0]) - 2) - X0, int(max(a[0], b[0]) + 3) - X0
    z0_, z1_ = int(min(a[1], b[1]) - 2) - Z0, int(max(a[1], b[1]) + 3) - Z0
    gx3, gz3 = np.meshgrid(np.arange(x0_, x1_) + X0, np.arange(z0_, z1_) + Z0)
    dx3, dz3 = b[0] - a[0], b[1] - a[1]
    t3 = np.clip(((gx3 - a[0]) * dx3 + (gz3 - a[1]) * dz3) / ((dx3 * dx3 + dz3 * dz3) or 1.0), 0.0, 1.0)
    near3 = np.hypot(gx3 - (a[0] + t3 * dx3), gz3 - (a[1] + t3 * dz3)) <= half
    paths[z0_:z1_, x0_:x1_] |= near3.astype(np.uint8)
    clean_paths[z0_:z1_, x0_:x1_] |= near3


# houses with no path to their door (2026-11-21 play test: "I don't want paths leading to certain houses"): the plan's
# "no_door_path_houses" spots, each the house nearest it (within 4 m)
no_path = set()
for q_ in plan.get("no_door_path_houses", []):
    near_ = min(range(len(plan["houses"])), key=lambda i: math.dist((plan["houses"][i]["x"], plan["houses"][i]["z"]), q_))
    if math.dist((plan["houses"][near_]["x"], plan["houses"][near_]["z"]), q_) <= 4.0:
        no_path.add(near_)
for hi_, h in enumerate(plan["houses"]):
    if len(h["design"]) > 1 or tree is None or hi_ in no_path:
        continue
    d = TOWN["designs"][h["design"]]; kk = h.get("scale") or d["scale"]
    door = turn([[d["door"][0] * kk, d["door"][1] * kk]], h["yaw"])[0]
    door = [h["x"] + door[0], h["z"] + door[1]]
    dist, at = tree.query(door)
    # (out to 16 m: a D's door stands 4.5 m back behind its wing, and its path was left out, all grass; 2026-11-21)
    if 0.5 < dist <= 16.0:
        end = straight_out(h, door, 16.0) or [float(tx[at] + X0), float(ty[at] + Z0)]
        if math.dist(door, end) <= 3.0:
            cv2.line(paths, tuple(px([door])[0]), tuple(px([end])[0]), 1, 2, cv2.LINE_AA, 3)
        else:
            # a long one is laid by distance from its line, every cell within 1 m (2026-11-21 play test: the D's path,
            # 7 m from its set-back door, a 2-cell line, blended away into the lawn: "a small, clean path to the door")
            clean_strip(door, end)
        doorways += 1
# and from each landmark's door that stands by a street (their doors are in the game's scenery list as it shipped;
# each goes with its building to the plan's spot)
import subprocess
shipped = {e["id"]: e for e in json.loads(subprocess.run(["git", "-C", ROOT, "show", "6b17658:world/props/ponyville/rnl_scenery.json"],
                                                          capture_output=True, text=True, encoding="utf-8", check=True).stdout)["entries"]}
CLEAN_DOOR = {"burger_joint_01": 1.3}          # landmark: half the width of its clean door path
for l in plan["landmarks"]:
    e = shipped.get(l["id"])
    if tree is None or not e or not isinstance(e.get("door"), dict) or "point" not in e["door"] or l["id"] in plan.get("no_door_path", []):
        continue                                                # (no_door_path: it has a dirt path of its own)
    q = turn([[e["door"]["point"][0] - e["position"][0], e["door"]["point"][1] - e["position"][2]]], l["yaw"] - e.get("yaw", 0.0))[0]
    door = [l["x"] + q[0], l["z"] + q[1]]
    dist, at = tree.query(door)
    if 0.5 < dist <= 12.0:
        inner = [l["x"] + q[0] * 0.8, l["z"] + q[1] * 0.8]          # from the doorstep itself, not only the point before it
        if l["id"] in CLEAN_DOOR:
            # straight out of its door to the street, as wide as its doorway, clean (2026-11-21 play test: "improve the
            # road leading into Hay Burger": two thin lines to the nearest bit of street, blended into patches)
            n_ = math.hypot(q[0], q[1]) or 1.0; fx_, fz_ = q[0] / n_, q[1] / n_
            end = None
            for k_ in range(1, 33):
                x_, z_ = door[0] + fx_ * k_ * 0.5, door[1] + fz_ * k_ * 0.5
                r_, c_ = int(round(z_)) - Z0, int(round(x_)) - X0
                if 0 <= r_ < NZ and 0 <= c_ < NX and town[r_, c_]:
                    end = [x_ + fx_ * 0.5, z_ + fz_ * 0.5]; break
            clean_strip(inner, end or [float(tx[at] + X0), float(ty[at] + Z0)], CLEAN_DOOR[l["id"]])
        else:
            cv2.line(paths, tuple(px([inner])[0]), tuple(px([door])[0]), 1, 2, cv2.LINE_AA, 3)
            cv2.line(paths, tuple(px([door])[0]), tuple(px([[float(tx[at] + X0), float(ty[at] + Z0)]])[0]), 1, 2, cv2.LINE_AA, 3)
        doorways += 1
paths = paths.astype(bool)
tex[paths] = SAGE; mix[paths] = 0.0
town_all = town | paths
# a ring of grass round the fountain
fountain = next((l for l in plan["landmarks"] if l["id"] == "fountain_01"), None)
if fountain:
    s = SCEN["fountain_01"]
    reach = max(math.dist(p, (s["x"], s["z"])) for p in s["footprint"])
    r = np.hypot(*np.meshgrid(np.arange(NX) + X0 - fountain["x"], np.arange(NZ) + Z0 - fountain["z"]))
    ring = (r < reach + 2.2) & town
    tex[ring] = GRASS; second[ring] = BRIGHT; mix[ring] = 0.15
# grass round the Town Hall, to break up the square: an uneven band along its walls, not before its steps (the
# front third of the way round stays town ground) and not where a street runs through the square
hall = next((h for h in plan["houses"] if h["design"] == "town_hall"), None)
if hall:
    d = TOWN["designs"]["town_hall"]; kk = hall.get("scale") or d["scale"]
    outline = [[hall["x"] + p[0], hall["z"] + p[1]] for p in turn([[p[0] * kk, p[1] * kk] for p in d["footprint"]], hall["yaw"])]
    from_hall = ndimage.distance_transform_edt(~fill([outline]))
    gx_, gz_ = np.meshgrid(np.arange(NX) + X0 - hall["x"], np.arange(NZ) + Z0 - hall["z"])
    # which way each spot lies from the hall, against the way its steps face
    off = np.abs((np.arctan2(gx_, gz_) - hall["yaw"] + np.pi) % (2 * np.pi) - np.pi)
    # (fourth round: a whole ring of grass round the hall, under it too, so no town ground shows at its foot; open
    # only before the steps, a walk as wide as they are from the square to their foot)
    reach = 13.0 + 0.9 * noise(9, 21)
    fx, fz = math.sin(hall["yaw"]), math.cos(hall["yaw"])
    ahead = gx_ * fx + gz_ * fz; aside = np.abs(gx_ * fz - gz_ * fx)
    walk = (ahead > 0) & (aside < 2.3)
    band = (np.hypot(gx_, gz_) < np.clip(reach, 11.5, 14.5)) & ~walk
    tex[band] = GRASS; second[band] = BRIGHT; mix[band] = 0.15
    print(f"grass round the Town Hall: {int(band.sum())} m2")
skirted = doorways

# ---- roads and railway ----
# (a path is drawn at least 3 m wide: at 2 m every cell of it is an edge cell, half grass, and the path all but vanishes)
# (a road marked "narrow" is drawn its own width: a path that should be no wider than the door ramp it leads to)
# A narrow one is laid by distance from its line, not drawn as a line: a line 2 cells thick lies half a cell to
# one side of where it should (the library's and the station's paths missed their ramp and steps by that).
dirt = lines([r for r in plan.get("roads", []) if r.get("type") == "dirt" and not r.get("narrow")], lambda r: max(3.0, r["width"] + 0.5))
for r_ in plan.get("roads", []):
    if r_.get("type") == "dirt" and r_.get("narrow") and len(r_["points"]) > 1:
        gx2, gz2 = np.meshgrid(np.arange(NX) + X0, np.arange(NZ) + Z0)
        near_ = np.full((NZ, NX), 1e9)
        for a_, b_ in zip(r_["points"][:-1], r_["points"][1:]):
            dx_, dz_ = b_[0] - a_[0], b_[1] - a_[1]
            t_ = np.clip(((gx2 - a_[0]) * dx_ + (gz2 - a_[1]) * dz_) / ((dx_ * dx_ + dz_ * dz_) or 1.0), 0.0, 1.0)
            near_ = np.minimum(near_, np.hypot(gx2 - (a_[0] + t_ * dx_), gz2 - (a_[1] + t_ * dz_)))
        dirt |= near_ <= max(1.0, r_["width"] / 2 + 0.2)
dirt &= ~town
tex[dirt] = TRAIL; mix[dirt] = 0.0
inside = lines([r for r in plan.get("roads", []) if r.get("type") == "dirt"], lambda r: r["width"]) & town
tex[inside] = SAGE                                             # roads running into town become town ground
rail = lines([r for r in plan.get("railways", []) if not r.get("outside") and r.get("name") != "bunting"], lambda r: 4.0)
tex[rail] = GRAVEL; mix[rail] = 0.0

# ---- water: river bed under it and up the first metre of bank ----
wet = ndimage.binary_dilation(water, iterations=1)
# Shores reshaped by fix_shore.py (2026-11-23 play test: "I want the underwater terrain texture to come up a little bit
# higher so that it reaches up to the water's edge, and maybe even a bit beyond the waterline ... Right now the grass is
# going down into the water by a few inches"; 2026-11-24: the game's river bed is painted blue water with pebbles,
# which read as blue patches in the shallows): Ponyville's own stream bed (23, make_stream_bed_texture.py, damp sandy
# earth with pebble clusters) under all the water and up the bank, BANK_M m out from the waterline or WET_ABOVE m
# above the water, whichever comes first; the edge blending below fades it into the grass.
STREAM_BED = 23
# (2026-11-24 third pass: "pull the sandy bank material down inside the carved channel rather than spilling wide onto
# the flat ground beside the stream": 1.6 m and 0.6 m before)
BANK_M, WET_ABOVE = 1.0, 0.3
shore_path = os.path.join(OUT, "shore_distance.npy")
bed_id = RIVER_BED
bank_edge = None          # metres past the bank's edge (negative: on the bed), a smooth field, for the blend below
tex_dry = tex.copy()      # what each cell would be without the bed
if os.path.exists(shore_path):
    shore = np.load(shore_path)
    gpath = os.path.join(OUT, f"density_{DENSITY}", "ground.f32") if DENSITY else os.path.join(OUT, "ground.f32")
    ground_here = np.fromfile(gpath, "<f4").reshape(NZ, NX)
    level_ = np.fromfile(os.path.join(OUT, "surface.f32"), "<f4").reshape(NZ, NX)
    _, (lz_, lx_) = ndimage.distance_transform_edt(~water, return_indices=True)
    bed_id = STREAM_BED
    # the bank's edge as a distance (the height limit measured along a 0.32 slope, fix_shore.py's banks), smoothed;
    # the bed is where it is negative, so the cells painted and the blend below agree everywhere
    bank_edge = ndimage.gaussian_filter(np.minimum(np.maximum(shore - BANK_M, (ground_here - level_[lz_, lx_] - WET_ABOVE) / 0.32),
                                                   np.where(shore < 0.25, shore - 0.25, 9.0)).astype(np.float32), 0.7)
    wet = (bank_edge < 0) | water
tex[wet] = bed_id; mix[wet] = 0.0

# ---- under the bridges: the banks are grass (2026-11-23 play test: "where bridges are, the roads tend to go down
# under the bridge and into the water ... I think it'd look better as grass"). Under a bridge the bank slopes down to the
# water, and the river bed's band (the first metre of bank) and the road's paint blended into it ran from the road
# down to the water, like the road going on under the deck. The water itself keeps its bed. Only looks: ponies cross on the deck, and the walk grid
# reads a trail texture (sage, dirt) only where the floor is the ground itself, so a trail down the bank only made the
# bank under the deck cheaper to route over. Each bridge's footprint (its span, its width and BANK_SIDE either side):
# the road's ground there lower than BANK_DROP under the bridge's lower end turns to grass; the approach at deck level
# keeps the road up to the bridge.
BANK_DROP, BANK_SIDE = 0.35, 0.75
ground_ = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
gx_, gz_ = np.meshgrid(np.arange(NX) + X0 + 0.5, np.arange(NZ) + Z0 + 0.5)
banks = np.zeros((NZ, NX), bool)
for b_ in plan.get("bridges", []):
    (ax_, az_), (bx_, bz_) = b_["a"], b_["b"]
    length_ = math.dist(b_["a"], b_["b"])
    ux_, uz_ = (bx_ - ax_) / length_, (bz_ - az_) / length_
    along_ = (gx_ - ax_) * ux_ + (gz_ - az_) * uz_
    side_ = np.abs((gx_ - ax_) * -uz_ + (gz_ - az_) * ux_)
    end_ = min(ground_[int(round(az_)) - Z0, int(round(ax_)) - X0], ground_[int(round(bz_)) - Z0, int(round(bx_)) - X0])
    banks |= (along_ >= 0) & (along_ <= length_) & (side_ <= b_.get("width", 4.0) / 2 + BANK_SIDE) & (ground_ < end_ - BANK_DROP)
# (not on the stream bed's own band: there the grass poked down into the bank under the bridges, 2026-11-24)
banks &= np.isin(tex, [SAGE, TRAIL, TOWN_DIRT, RIVER_BED]) & ~water & ~wet
tex[banks] = GRASS; mix[banks] = 0.0
print(f"bridge banks: {int(banks.sum())} m2 of road under the bridges turned to grass")


# ---- blend the edges: each square metre fades towards the texture next door over ~1.2 m ----
EDGE = 1.6
base = tex.copy()
overlay = second.copy()
blend = mix.copy()
dist_other = np.full((NZ, NX), np.inf, np.float32)
other = tex.copy()
for t in np.unique(tex):
    here = tex == t
    # for cells NOT of texture t, the distance to the nearest t cell: does t lie near them?
    d = ndimage.distance_transform_edt(~here)
    near = ~here & (d < dist_other) & (d <= EDGE)
    dist_other[near] = d[near]
    other[near] = t
edge = np.isfinite(dist_other)
fade = np.clip(0.5 * (1.0 - (dist_other - 1.0) / EDGE), 0.0, 0.5)
fade[base == TRAIL] *= 0.5            # a dirt road keeps its own colour to its edge; the grass beside it fades into it
overlay[edge] = other[edge]
blend[edge] = fade[edge]
# where there is no neighbour, the overlay is the drift texture at its mix
blend = np.clip(blend, 0.0, 1.0)
blend[clean_paths & (base == SAGE)] = 0.0          # long door paths: plain sage (the lawn beside fades into them)
# The stream bed's edge on the grass (2026-11-24 play test: "the slight jagged/sawtooth edge where the dirt bank texture
# blends into the surrounding grass"): the cell-by-cell fade above follows the 1 m cells, so along a slanting bank it
# stepped. Within BANK_FEATHER m of the bank's edge, the two blend by the smooth distance to it instead: half and half
# on the edge, the bed alone BANK_FEATHER m in, the grass alone BANK_FEATHER m out. Only against grass and lawn.
BANK_FEATHER = 0.9
if bank_edge is not None:
    lawn = np.isin(tex_dry, [GRASS, GRASS_LIGHT, BRIGHT, GLOOMY]) & ~banks
    near = lawn & (np.abs(bank_edge) < BANK_FEATHER) & np.isin(tex, [STREAM_BED, GRASS, GRASS_LIGHT, BRIGHT, GLOOMY])
    t_ = np.clip(np.abs(bank_edge) / BANK_FEATHER, 0.0, 1.0)
    half = 0.5 * (1.0 - t_ * t_ * (3.0 - 2.0 * t_))
    on_bed = near & (bank_edge < 0)
    base[on_bed] = STREAM_BED; overlay[on_bed] = tex_dry[on_bed]; blend[on_bed] = half[on_bed]
    on_grass = near & (bank_edge >= 0)
    base[on_grass] = tex_dry[on_grass]; overlay[on_grass] = STREAM_BED; blend[on_grass] = half[on_grass]
    # beyond the feather the cell-by-cell fade above is not used either way (2026-11-24 third pass: "stray green grass
    # squares ... randomly poke down into the bank"): the bed's own cells are the bed alone, the grass beyond is grass
    inner = (base == STREAM_BED) & (bank_edge <= -BANK_FEATHER)
    blend[inner] = 0.0
    outer = lawn & (bank_edge >= BANK_FEATHER) & (overlay == STREAM_BED)
    blend[outer] = 0.0
    print(f"stream bank: {int(near.sum())} m2 of its edge blended by the smooth shore")
control = ((base.astype(np.uint32) & 31) << 27) | ((overlay.astype(np.uint32) & 31) << 22) | ((np.round(blend * 255).astype(np.uint32) & 255) << 14)
control.astype("<u4").tofile(os.path.join(OUT, "control.u32"))

# ---- write the overlays ----
# the game reads bundle.json first (its "surface" part), surface_index.json only without one
bundle_path = os.path.join(SURF, "bundle.json")
bundle = json.load(open(bundle_path)) if os.path.exists(bundle_path) else None
index_path = os.path.join(SURF, "surface_index.json")
index = bundle["surface"] if bundle else json.load(open(index_path))
side_index = json.load(open(index_path)) if bundle and os.path.exists(index_path) else None
written = []
for lz in range(math.floor(Z0 / REGION), math.floor((Z0 + NZ - 1) / REGION) + 1):
    for lx in range(math.floor(X0 / REGION), math.floor((X0 + NX - 1) / REGION) + 1):
        key = f"{lx}_{lz}"
        old = index["tiles"].get(key)
        ctl = np.zeros((REGION, REGION), "<u4"); cov = np.zeros((REGION, REGION), np.uint8)
        if DENSITY:
            # beside the full town's paint, from it: only the plan's box changes
            if not old or TAG not in old:
                continue
            folder = os.path.join(SURF, old)
            ctl = np.fromfile(os.path.join(folder, "control.f32"), "<u4").reshape(REGION, REGION).copy()
            cov = np.where(cv2.imread(os.path.join(folder, "coverage.png"), cv2.IMREAD_GRAYSCALE) > 0, 255, 0).astype(np.uint8)
        elif old and TAG not in old:
            folder = os.path.join(SURF, old)
            ctl = np.fromfile(os.path.join(folder, "control.f32"), "<u4").reshape(REGION, REGION).copy()
            cov = np.where(cv2.imread(os.path.join(folder, "coverage.png"), cv2.IMREAD_GRAYSCALE) > 0, 255, 0).astype(np.uint8)
        elif old:
            raise SystemExit(f"{key} already holds {old}: restore surface_index.json from git first")
        rx0, rz0 = lx * REGION, lz * REGION
        ax0, ax1 = max(X0, rx0), min(X0 + NX, rx0 + REGION)
        az0, az1 = max(Z0, rz0), min(Z0 + NZ, rz0 + REGION)
        if ax0 >= ax1 or az0 >= az1:
            continue
        ctl[az0 - rz0:az1 - rz0, ax0 - rx0:ax1 - rx0] = control[az0 - Z0:az1 - Z0, ax0 - X0:ax1 - X0]
        cov[az0 - rz0:az1 - rz0, ax0 - rx0:ax1 - rx0] = 255
        rel = f"surface/{key}/{TAG}" + (f"_{DENSITY}" if DENSITY else "")
        folder = os.path.join(SURF, rel)
        os.makedirs(folder, exist_ok=True)
        ctl.tofile(os.path.join(folder, "control.f32"))
        cv2.imwrite(os.path.join(folder, "coverage.png"), cov)
        # the byte id images the offline generator reads (as BiomeSurfaceStore.save writes them)
        for name, shift, mask in (("base", 27, 31), ("overlay", 22, 31), ("blend", 14, 255)):
            cv2.imwrite(os.path.join(folder, name + ".png"), ((ctl >> shift) & mask).astype(np.uint8))
        json.dump({"bounds": [0, 0, REGION, REGION]}, open(os.path.join(folder, "meta.json"), "w"), indent=2)
        if not DENSITY:
            index["tiles"][key] = rel
            if side_index is not None:
                side_index["tiles"][key] = rel
        written.append((key, old))
if DENSITY:
    pass
elif bundle:
    json.dump(bundle, open(bundle_path, "w", encoding="utf-8"), indent=2)
    if side_index is not None:
        json.dump(side_index, open(index_path, "w"), indent=2)
else:
    json.dump(index, open(index_path, "w"), indent=2)
names = {GRASS: "grass", TRAIL: "dirt road", GRASS_LIGHT: "light grass", FIELD: "field dirt", TOWN_DIRT: "farmyard", GRAVEL: "gravel",
         GLOOMY: "Everfree", FOREST_FLOOR: "forest floor", BRIGHT: "bright grass", RIVER_BED: "river bed", SAGE: "town sage", 23: "stream bed"}
counts = {names.get(int(t), str(t)): int((tex == t).sum()) for t in np.unique(tex)}
print("painted (m2):", dict(sorted(counts.items(), key=lambda kv: -kv[1])))
print(f"door paths: {skirted}; overlays: " + ", ".join(f"{k} (over {o})" for k, o in written))
