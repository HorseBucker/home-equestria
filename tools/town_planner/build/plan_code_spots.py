"""Build step 7 (second half): the spots the game's own code holds as fixed world coordinates.

usage: python tools/town_planner/build/plan_code_spots.py <project> <plan.json>
(after plan_scenery.py and plan_props.py; safe to run again: each constant is found by name, not by its old value)

Some things are not nodes in the town scene: a script sets them down at coordinates written into it, measured in
the old town. Left alone they stay there: Trixie's walk-in wagon stood in mid-air where the old fair was, the
painting easel hung over the new houses where Balloon Hill had been, the town bell rang from an empty field.
Each is moved to its place in the plan:
- world/buildings/trixie_wagon.gd SPOT, YAW: the plan's trixie_wagon_01 (the game stands it on the ground itself)
- world/painting/station_install.gd POSE: the plan's painting_easel anchor
- world/audio/soundscape.gd TOWN, BELL_AT (the Town Hall), ROOSTER_AT (the barn)
- world/life/arrival_story.gd FOREST_EDGE (where Twilight's teleport lands: the most open spot of the Town Square),
  GOLDEN_OAK (the library's door)
- world/ui/title_vista.gd: the title screen's views of the town, the library, Fluttershy's cottage, the square and
  Sweet Apple Acres
- world/mechanics/stations/saa_sites.gd PRESS_AT (the cider press, by the barn as before),
  planting_plot.gd SLOT_X, SLOT_Z, SIGN_AT (Anon's row of saplings: eight level, open spots near the farm, clear
  of the orchard, roads, water and buildings), world/props/ponyville/farm_dressing.gd's ground probe
- data files that hold the same kind of spot: world/mechanics/data/stations.json (the cider press, Anon's row, the
  orchard chore), jobs.json (the cider stand's fallback), events.json (Hearth's Warming's garland arch and tree),
  world/world_layout.json (the Ponyville region's middle and spawn point), world/main.tscn (PlayerSpawn),
  world/ui/named_map_places.json (the map's fallback markers for the Town Hall and Sugarcube Corner)
A point that belonged to a building (a door, the press) keeps its place relative to that building.
"""
import json, math, os, re, subprocess, sys
import cv2, numpy as np
from scipy import ndimage

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
plan = json.load(open(PLAN, encoding="utf-8"))
moves = json.load(open(os.path.join(OUT, "scenery_moves.json")))
nodes = json.load(open(os.path.join(OUT, "scenery_nodes.json")))          # where things stood: [x, y, z, yaw]
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
water = np.fromfile(os.path.join(OUT, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
scen = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "world/props/ponyville/rnl_scenery.json"), encoding="utf-8"))["entries"]}
old_scen = {e["id"]: e for e in json.loads(subprocess.run(["git", "-C", ROOT, "show", "6b17658:world/props/ponyville/rnl_scenery.json"],
                                                          capture_output=True, text=True, encoding="utf-8", check=True).stdout)["entries"]}
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
DESIGNS = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])["designs"]


def g(x, z):
    return float(ground[min(NZ - 1, max(0, round(z) - Z0)), min(NX - 1, max(0, round(x) - X0))])


def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def carry(x, z, anchor):
    """Where a point that belonged to a building is now: the same place relative to it."""
    ox, _, oz, _ = nodes[anchor]
    oyaw = old_scen[anchor].get("yaw", 0.0)
    m = moves[anchor]
    dx, dz = turn([[x - ox, z - oz]], m["yaw"] - oyaw)[0]
    return m["x"] + dx, m["z"] + dz


def px(points):
    return np.round((np.array(points, np.float64) - [X0, Z0]) * 8).astype(np.int32)


def fill(polys):
    m = np.zeros((NZ, NX), np.uint8)
    for p in polys:
        if len(p) >= 3:
            cv2.fillPoly(m, [px(p)], 1, shift=3)
    return m.astype(bool)


def lines(items, width_of):
    m = np.zeros((NZ, NX), np.uint8)
    for it in items:
        cv2.polylines(m, [px(it["points"])], False, 1, max(1, int(round(width_of(it)))), shift=3)
    return m.astype(bool)


def house_walls(h):
    d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
    return [[h["x"] + p[0], h["z"] + p[1]] for p in turn([[q[0] * k, q[1] * k] for q in d["footprint"]], h["yaw"])]


buildings = fill([house_walls(h) for h in plan["houses"]] + [e["footprint"] for e in scen.values() if len(e.get("footprint") or []) >= 3 and e.get("class") in ("building", "box", "walk")])
roads = lines([r for r in plan["roads"] if r.get("type") == "dirt"], lambda r: r["width"]) | lines([r for r in plan.get("railways", []) if not r.get("outside") and r.get("name") != "bunting"], lambda r: 6.0)
from_building = ndimage.distance_transform_edt(~buildings)
from_water = ndimage.distance_transform_edt(~water)
from_road = ndimage.distance_transform_edt(~roads)
hall = next(h for h in plan["houses"] if h["design"] == "town_hall")
barn, library, cottage, fountain, wagon = (moves[i] for i in ("appleacres_barned_01", "goldenoaklibrary_01", "snazzys_fluttershy_cottage_01", "fountain_01", "trixie_wagon_01"))
easel = next(a for a in plan.get("anchors", []) if a["id"] == "painting_easel")
done = []


def v3(x, y, z):
    f = lambda v: (f"{v:.3f}".rstrip("0").rstrip(".") if "." in f"{v:.3f}" else f"{v:.3f}")
    fmt = lambda v: f(v) + (".0" if "." not in f(v) else "")
    return f"Vector3({fmt(x)}, {fmt(y)}, {fmt(z)})"


def v2(x, z):
    return f"Vector2({x:.1f}, {z:.1f})"


def edit(path, pattern, replacement, what):
    full = os.path.join(ROOT, path)
    text = open(full, encoding="utf-8").read()
    new, n = re.subn(pattern, lambda m: replacement, text, count=1, flags=re.M)
    if n != 1:
        raise SystemExit(f"{path}: could not find {what}")
    if new != text:
        open(full, "w", encoding="utf-8", newline="").write(new)
    done.append(f"{path}: {what} -> {replacement.split(':= ')[-1][:90]}")


# ---- Trixie's wagon and the easel ----
edit("world/buildings/trixie_wagon.gd", r"^const SPOT := Vector3\([^)]*\)", f"const SPOT := {v3(wagon['x'], g(wagon['x'], wagon['z']), wagon['z'])}", "SPOT")
edit("world/buildings/trixie_wagon.gd", r"^const YAW := [-0-9.e]+", f"const YAW := {wagon['yaw']:.6f}", "YAW")
edit("world/painting/station_install.gd", r"^const POSE := Transform3D\(Basis\(Vector3\.UP, [-0-9.e]+\), Vector3\([^)]*\)\)",
     f"const POSE := Transform3D(Basis(Vector3.UP, {easel['yaw']:.4f}), {v3(easel['x'], g(easel['x'], easel['z']), easel['z'])})", "POSE")

# ---- sounds ----
edit("world/audio/soundscape.gd", r"^const TOWN := Vector3\([^)]*\)", f"const TOWN := {v3(hall['x'], 0.0, hall['z'])}", "TOWN")
edit("world/audio/soundscape.gd", r"^const BELL_AT := Vector3\([^)]*\)", f"const BELL_AT := {v3(hall['x'], 0.0, hall['z'])}", "BELL_AT")
edit("world/audio/soundscape.gd", r"^const ROOSTER_AT := Vector3\([^)]*\)", f"const ROOSTER_AT := {v3(barn['x'], 0.0, barn['z'])}", "ROOSTER_AT")

# ---- arrival: Twilight's teleport lands on the most open ground of the Town Square ----
square = max(plan["grounds"], key=lambda s: len(s["points"]))
inside_sq = fill([square["points"]])
open_ = np.where(inside_sq & ~water, np.minimum(from_building, ndimage.distance_transform_edt(inside_sq) + 2.0), 0.0)
r, c = np.unravel_index(np.argmax(open_), open_.shape)
land = (float(c + X0), float(r + Z0))
edit("world/life/arrival_story.gd", r"^const FOREST_EDGE := Vector3\([^)]*\)", f"const FOREST_EDGE := {v3(land[0], 0.0, land[1])}", "FOREST_EDGE")
door = carry(-24.5, -259.2, "goldenoaklibrary_01")
door_y = library["y"] + (-11.3 - nodes["goldenoaklibrary_01"][1])
edit("world/life/arrival_story.gd", r"^const GOLDEN_OAK := Vector3\([^)]*\)", f"const GOLDEN_OAK := {v3(door[0], door_y, door[1])}", "GOLDEN_OAK")

# ---- the title screen's views ----
cot = carry(156.12, -12.05, "snazzys_fluttershy_cottage_01")
cot_y = cottage["y"] + (-19.01 - nodes["snazzys_fluttershy_cottage_01"][1])
away = (fountain["x"] - hall["x"], fountain["z"] - hall["z"]); L = math.hypot(*away) or 1
stand = (fountain["x"] + away[0] / L * 15.0, fountain["z"] + away[1] / L * 15.0)
farm_stand = carry(30.0, -420.0, "appleacres_barned_01"); farm_look = carry(13.0, -440.0, "appleacres_barned_01")
edit("world/ui/title_vista.gd", r'"above_ponyville": \{"stand": Vector2\([^)]*\), "height": [0-9.]+, "look": Vector3\([^)]*\)\}',
     f'"above_ponyville": {{"stand": {v2(hall["x"] - 105.0, hall["z"] + 95.0)}, "height": 38.0, "look": {v3(hall["x"] - 35.0, 0.0, hall["z"] - 30.0)}}}', "above_ponyville")
edit("world/ui/title_vista.gd", r'"golden_oak": \{"door": Vector3\([^)]*\)', f'"golden_oak": {{"door": {v3(door[0], door_y, door[1])}', "golden_oak")
edit("world/ui/title_vista.gd", r'"fluttershy_cottage": \{"door": Vector3\([^)]*\)', f'"fluttershy_cottage": {{"door": {v3(cot[0], cot_y, cot[1])}', "fluttershy_cottage")
edit("world/ui/title_vista.gd", r'"town_square": \{"stand": Vector2\([^)]*\), "height": [0-9.]+, "look": Vector3\([^)]*\)\}',
     f'"town_square": {{"stand": {v2(*stand)}, "height": 1.2, "look": {v3(fountain["x"], 1.5, fountain["z"])}}}', "town_square")
edit("world/ui/title_vista.gd", r'"sweet_apple_acres": \{"stand": Vector2\([^)]*\), "look": Vector3\([^)]*\)\}',
     f'"sweet_apple_acres": {{"stand": {v2(*farm_stand)}, "look": {v3(farm_look[0], 4.0, farm_look[1])}}}', "sweet_apple_acres")

# ---- Sweet Apple Acres' stations ----
press = carry(42.5, -447.0, "appleacres_barned_01")
pr, pc = round(press[1]) - Z0, round(press[0]) - X0
if buildings[pr, pc] or water[pr, pc] or from_building[pr, pc] < 1.5:
    # step aside to the nearest clear ground
    ok = ~buildings & ~water & (from_building > 2.0) & (from_road > 1.5)
    rr, cc = np.nonzero(ok)
    k = np.argmin((rr - pr) ** 2 + (cc - pc) ** 2)
    press = (float(cc[k] + X0), float(rr[k] + Z0))
edit("world/mechanics/stations/saa_sites.gd", r"^const PRESS_AT := Vector3\([^)]*\)", f"const PRESS_AT := {v3(press[0], 0.0, press[1])}", "PRESS_AT")
edit("world/props/ponyville/farm_dressing.gd", r"_ground\(Vector3\([-0-9., ]*\)\)\n(\tif not probe\.is_finite\(\))",
     f"_ground(Vector3({barn['x']:.0f}, 0, {barn['z']:.0f}))\n\tif not probe.is_finite()", "the ground probe")
# Anon's row: four columns 7.5 m apart, two rows 12 m apart (as it was), on level open grass near the farm
farm = json.load(open(os.path.join(ROOT, "world/props/ponyville/farm_layout.json"), encoding="utf-8"))
orchard = fill([farm["orchard"]["inside"]]) if farm.get("orchard", {}).get("inside") else np.zeros((NZ, NX), bool)
yard = fill([f["points"] for f in plan.get("fields", []) if f["crop"] in ("farmyard", "carrots", "vegetable rows", "wheat")])
bad = ndimage.binary_dilation(orchard, iterations=5) | ndimage.binary_dilation(water, iterations=5) | ndimage.binary_dilation(roads, iterations=3) | \
    (from_building < 6) | ndimage.binary_dilation(yard, iterations=2)
inner = np.minimum.reduce(np.meshgrid(np.minimum(np.arange(NX), NX - 1 - np.arange(NX)), np.minimum(np.arange(NZ), NZ - 1 - np.arange(NZ))))
bad |= inner < 70
best = None
for z0 in range(int(barn["z"]) - 130, int(barn["z"]) + 130, 2):
    for x0 in range(int(barn["x"]) - 130, int(barn["x"]) + 130, 2):
        pts = [(x0 + 7.5 * i, z0 + 12.0 * j) for j in range(2) for i in range(4)]
        cells = [(round(p[1]) - Z0, round(p[0]) - X0) for p in pts] + [(round(z0 + 6) - Z0, round(x0 - 4.4) - X0)]
        if any(not (0 <= r_ < NZ and 0 <= c_ < NX) or bad[r_, c_] for r_, c_ in cells):
            continue
        hs = [float(ground[r_, c_]) for r_, c_ in cells]
        if max(hs) - min(hs) > 0.8:
            continue
        d = math.dist((x0 + 11.25, z0 + 6.0), (barn["x"], barn["z"]))
        score = abs(d - 45.0) + 0.3 * float(from_road[cells[0]])          # about 45 m from the barn, near a road
        if best is None or score < best[0]:
            best = (score, x0, z0)
if best is None:
    raise SystemExit("no place for Anon's row near the farm")
_, x0, z0 = best
edit("world/mechanics/stations/planting_plot.gd", r"^const SLOT_X := \[[^\]]*\]", "const SLOT_X := [" + ", ".join(f"{x0 + 7.5 * i:.1f}" for i in range(4)) + "]", "SLOT_X")
edit("world/mechanics/stations/planting_plot.gd", r"^const SLOT_Z := \[[^\]]*\]", f"const SLOT_Z := [{float(z0):.1f}, {z0 + 12.0:.1f}]", "SLOT_Z")
edit("world/mechanics/stations/planting_plot.gd", r"^const SIGN_AT := Vector3\([^)]*\)", f"const SIGN_AT := {v3(x0 - 4.4, 0.0, z0 + 6.0)}", "SIGN_AT")

# ---- the same kind of spot, kept in data files ----
slot_mid = (x0 + 11.25, z0 + 6.0)
orch_pts = np.argwhere(orchard & (from_building > 4) & ~water)
orch_mid = orch_pts[np.argmin((orch_pts[:, 0] + Z0 - barn["z"]) ** 2 + (orch_pts[:, 1] + X0 - barn["x"]) ** 2)] if len(orch_pts) else None
orch_at = (float(orch_mid[1] + X0), float(orch_mid[0] + Z0)) if orch_mid is not None else (barn["x"], barn["z"])
stand_at = carry(62.6, -460.3, "appleacres_barned_01")
# world/mechanics/data/stations.json: where each station's work is done when no live node says otherwise, and
# (the cider press) the point ponies must be within 80 m of to be offered the work
for path, sid, at in (("world/mechanics/data/stations.json", "cider_press", press), ("world/mechanics/data/stations.json", "saa_plot", slot_mid),
                      ("world/mechanics/data/stations.json", "orchard_tree", orch_at), ("world/mechanics/data/jobs.json", "cider_stand", stand_at)):
    full = os.path.join(ROOT, path)
    text = open(full, encoding="utf-8").read()
    m = re.search(r'"id": *"' + sid + r'"', text)
    if not m:
        raise SystemExit(f"{path}: no {sid}")
    w = re.compile(r'"world": *\[[^\]]*\]').search(text, m.end())
    if not w:
        raise SystemExit(f"{path}: {sid} has no world point")
    new_point = f'"world": [{at[0]:.1f}, 0, {at[1]:.1f}]'
    text = text[:w.start()] + new_point + text[w.end():]
    open(full, "w", encoding="utf-8", newline="").write(text)
    done.append(f"{path}: {sid} -> {new_point}")

# world/mechanics/data/events.json, Hearth's Warming: the garland arch over the south road into town, the big tree
# on open ground in the Town Square (the game takes the first spot that is level and clear)
gate = next((r for r in plan["roads"] if r.get("name") == "South Gate"), None)
if gate:
    gp = gate["points"][len(gate["points"]) // 2]
    q0, q1 = gate["points"][0], gate["points"][-1]
    arch_yaw = math.atan2(q1[1] - q0[1], q1[0] - q0[0]) - math.pi / 2          # its posts either side of the road
    edit("world/mechanics/data/events.json", r'("id": "garland_arch"[^{}]*?"at": )\[[^\]]*\], "yaw": [-0-9.]+',
         f'"id": "garland_arch", "scene": "res://world/props/rnl/rnl_wirearch_v2/prefab.scn", "at": [{gp[0]:.2f}, {g(gp[0], gp[1]):.2f}, {gp[1]:.2f}], "yaw": {arch_yaw:.4f}',
         "garland_arch")
spots = []
field = open_.copy()
yy, xx = np.ogrid[0:NZ, 0:NX]
field[(yy - (land[1] - Z0)) ** 2 + (xx - (land[0] - X0)) ** 2 < 12 ** 2] = 0       # not where new arrivals land
for k in range(4):
    r_, c_ = np.unravel_index(np.argmax(field), field.shape)
    if field[r_, c_] < 3.0:
        break
    spots.append((float(c_ + X0), float(r_ + Z0)))
    yy, xx = np.ogrid[0:NZ, 0:NX]
    field[(yy - r_) ** 2 + (xx - c_) ** 2 < 12 ** 2] = 0
if spots:
    text_spots = ", ".join(f"[{x:.1f}, {g(x, z):.2f}, {z:.1f}, {0.4 + k * 0.7:.1f}]" for k, (x, z) in enumerate(spots))
    full = os.path.join(ROOT, "world/mechanics/data/events.json")
    text = open(full, encoding="utf-8").read()
    m = re.search(r'"id": *"square_tree"', text)
    w = re.compile(r'"spots": *\[(?:\[[^\]]*\](?:, *)?)*\]').search(text, m.end())
    text = text[:w.start()] + f'"spots": [{text_spots}]' + text[w.end():]
    open(full, "w", encoding="utf-8", newline="").write(text)
    done.append(f"world/mechanics/data/events.json: square_tree -> {len(spots)} spots in the Town Square")

# world/world_layout.json: the Ponyville region's middle and spawn point (the map's marker, where ponies sent "to
# Ponyville" go); world/main.tscn: where a new game first puts the player; both the open ground of the Town Square
full = os.path.join(ROOT, "world/world_layout.json")
text = open(full, encoding="utf-8").read()
m = re.search(r'"id": *"ponyville"', text)
lo = text.rfind("{", 0, m.start()); hi = text.find('"id":', m.end())
block = text[lo:hi if hi > 0 else len(text)]
block2 = re.sub(r'"center": *\[[^\]]*\]', f'"center": [{hall["x"]:.0f}, 0, {hall["z"]:.0f}]', block, count=1)
block2 = re.sub(r'"spawn": *\[[^\]]*\]', f'"spawn": [{land[0]:.1f}, {land[1]:.1f}]', block2, count=1)
if block2 == block and f'"spawn": [{land[0]:.1f}, {land[1]:.1f}]' not in block:
    raise SystemExit("world_layout.json: ponyville centre and spawn not found")
open(full, "w", encoding="utf-8", newline="").write(text[:lo] + block2 + text[lo + len(block):])
done.append(f"world/world_layout.json: ponyville center, spawn -> ({hall['x']:.0f}, {hall['z']:.0f}), ({land[0]:.1f}, {land[1]:.1f})")
edit("world/main.tscn", r'(\[node name="PlayerSpawn" type="Marker3D" parent="\."\]\r?\ntransform = Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, )[-0-9., ]+\)',
     f'[node name="PlayerSpawn" type="Marker3D" parent="."]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {land[0]:.0f}, {g(*land) + 20:.0f}, {land[1]:.0f})', "PlayerSpawn")

# world/ui/named_map_places.json: the map's fallback markers for the Town Hall and Sugarcube Corner
full = os.path.join(ROOT, "world/ui/named_map_places.json")
text = open(full, encoding="utf-8").read()
cube = next(h for h in plan["houses"] if h["design"] == "sugarcube")
for pid, h in (("landmark:town_hall", hall), ("landmark:sugarcube_corner", cube)):
    m = re.search(r'"id": *"' + pid + r'"[^{}]*?"x": *[-0-9.]+,\s*"z": *[-0-9.]+', text)
    if not m:
        raise SystemExit(f"named_map_places.json: no {pid}")
    fixed = re.sub(r'"x": *[-0-9.]+(,\s*)"z": *[-0-9.]+', lambda q: f'"x": {h["x"]}{q.group(1)}"z": {h["z"]}', m.group(0))
    text = text[:m.start()] + fixed + text[m.end():]
open(full, "w", encoding="utf-8", newline="").write(text)
done.append("world/ui/named_map_places.json: Town Hall and Sugarcube Corner markers")
for line in done:
    print(line)
