"""Build step 4: the plan's houses in world/towns/ponyville/town.tscn (edited as text, so every other node
keeps exactly what it had).

usage: python tools/town_planner/build/build_town.py <project> <plan.json>
(after apply_ground.py, whose 1 m ground grid in build/out gives each house its height, and after
make_background_houses.gd)

- The old town's houses, their foundations and their stair ramps go (plot_* nodes, Foundation_*,
  TerrainStairApproaches, and the meshes and shapes only they used): the ground under the new town is
  flat, or levelled pads in the country.
- Every real home of the plan (lived in or vacant) is the full house (house_X scene: rooms, door,
  see-through windows), named plot_NNN so the game's home grant and render budget treat it as a town
  house. A lived-in one carries reserved_for = its first resident: pony_population.gd gives that pony the
  house and pony_households.gd brings the family in. A vacant one carries `vacant`, and no reservation,
  so a pony can give it to the player.
- Every background house is the merged, outside-only house (background/house_X_bg.scn) under
  BackgroundHouses, named bg_NNN, leaning a little its own way as the show's houses do (`lean`,
  plan_geometry.house_leans: never far enough to touch a neighbour; its foot and its collision stay put).
- Sugarcube Corner and the Town Hall move to the plan's spots (the Town Hall 4 cm proud of the ground, so its
  lowest step does not flicker against it).
Props, scenery, the kit and the market stalls are left for later steps. Run it on the town.tscn from
git (it refuses a town it has already built).
"""
import json, math, os, re, statistics, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import plan_geometry as G

ROOT, PLAN = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
TOWN = os.path.join(ROOT, "world/towns/ponyville/town.tscn")
OUT = os.path.join(HERE, "out")
REAL = {"a": "house_a.tscn", "b": "house_b.tscn", "c": "house_c.tscn", "d": "house_d.tscn",
        "e": "house_e.scn", "f": "house_f.scn", "g": "house_g.scn", "h": "house_h.scn"}

plan = json.load(open(PLAN, encoding="utf-8"))
tj = open(os.path.join(HERE, "..", "data", "town.js"), encoding="utf-8").read()
DESIGNS = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])["designs"]
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
text = open(TOWN, encoding="utf-8").read()
if "BackgroundHouses" in text:
    raise SystemExit("town.tscn already holds a built town: check it out from git first")
nl = "\r\n" if "\r\n" in text else "\n"

# ---- sections ----
parts = re.split(r"(?m)^(?=\[)", text)
head, sections = parts[0], parts[1:]


def kind(sec):
    return sec[1:sec.index(" ") if " " in sec.split("\n", 1)[0] else sec.index("]")]


def attr(sec, key):
    m = re.match(r'\[[^\]]*\b' + key + r'="([^"]*)"', sec)
    return m.group(1) if m else None


def node_path(sec):
    name, parent = attr(sec, "name"), attr(sec, "parent")
    if parent is None:
        return ""
    return name if parent == "." else parent + "/" + name


removed_paths = []
kept = []
for sec in sections:
    if kind(sec) == "node":
        path = node_path(sec)
        top = path.split("/")[0] if path else ""
        if top.startswith("plot_") or top.startswith("Foundation_") or top == "TerrainStairApproaches":
            removed_paths.append(path)
            continue
    kept.append(sec)

# drop sub-resources nothing left refers to (the old foundations' meshes and shapes)
while True:
    body = "".join(s for s in kept)
    used = set(re.findall(r'SubResource\("([^"]+)"\)', "".join(s for s in kept if kind(s) != "sub_resource" or True)))
    before = len(kept)
    refs = {}
    for s in kept:
        if kind(s) == "sub_resource":
            refs[attr(s, "id")] = s
    # a sub-resource is used if referenced from any other kept section
    referenced = set()
    for s in kept:
        own = attr(s, "id") if kind(s) == "sub_resource" else None
        for r in re.findall(r'SubResource\("([^"]+)"\)', s):
            if r != own:
                referenced.add(r)
    kept = [s for s in kept if kind(s) != "sub_resource" or attr(s, "id") in referenced]
    if len(kept) == before:
        break
dropped_subs = sum(1 for s in sections if kind(s) == "sub_resource") - sum(1 for s in kept if kind(s) == "sub_resource")

# ---- ext resources for every scene the new houses use ----
ext = {}
for s in kept:
    if kind(s) == "ext_resource":
        ext[attr(s, "path")] = attr(s, "id")
new_ext = []


def ext_id(path):
    if path not in ext:
        rid = f"{100 + len(new_ext)}_town"
        ext[path] = rid
        new_ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{rid}"]{nl}')
    return ext[path]


def num(v):
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def transform(yaw, scale, x, y, z):
    c, s = math.cos(yaw) * scale, math.sin(yaw) * scale
    vals = [c, 0, s, 0, scale, 0, -s, 0, c, x, y, z]
    return "Transform3D(" + ", ".join(num(v) for v in vals) + ")"


def ground_under(design, scale, h):
    d = DESIGNS[design]
    c, s = math.cos(h["yaw"]), math.sin(h["yaw"])
    heights = []
    for p in d["footprint"]:
        for t in (0.0, 0.5):
            lx, lz = p[0] * scale * (1 - t), p[1] * scale * (1 - t)
            wx, wz = h["x"] + lx * c + lz * s, h["z"] - lx * s + lz * c
            heights.append(float(ground[min(NZ - 1, max(0, round(wz) - Z0)), min(NX - 1, max(0, round(wx) - X0))]))
    return statistics.median(heights)


def gd_str(v):
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'


# ---- the new houses ----
nodes = []
real = vacant = bg = 0
leans = G.house_leans(plan)
for h_index, h in enumerate(plan["houses"]):
    design = h["design"]
    if len(design) != 1:
        continue
    scale = h.get("scale") or DESIGNS[design]["scale"]
    y = ground_under(design, scale, h)
    if not h.get("filler", True):
        real += 1
        name = f"plot_{real:03d}"
        rid = ext_id(f"res://world/towns/ponyville/{REAL[design]}")
        lines = [f'[node name="{name}" parent="." instance=ExtResource("{rid}")]', f"transform = {transform(h['yaw'], scale, h['x'], y, h['z'])}",
                 f'metadata/building_design = "{design}"', f'metadata/residential_plot = "{name}"']
        lived = h.get("residents") or []
        if lived:
            lines += [f"metadata/reserved_for = {gd_str(lived[0])}",
                      "metadata/planned_residents = [" + ", ".join(gd_str(r) for r in lived) + "]",
                      f"metadata/planned_name = {gd_str(h.get('name', ''))}"]
        else:
            lines.append("metadata/vacant = true"); vacant += 1
        nodes.append(nl.join(lines) + nl + nl)
    else:
        bg += 1
        rid = ext_id(f"res://world/towns/ponyville/background/house_{design}_bg.scn")
        lean = leans[h_index]
        nodes.append(nl.join([f'[node name="bg_{bg:03d}" parent="BackgroundHouses" instance=ExtResource("{rid}")]',
                              f"transform = {transform(h['yaw'], scale, h['x'], y, h['z'])}"]
                             + ([f"lean = Vector2({lean[0]}, {lean[1]})"] if lean != (0.0, 0.0) else [])) + nl + nl)
holder = f'[node name="BackgroundHouses" type="Node3D" parent="."]{nl}{nl}'

# ---- Sugarcube Corner and the Town Hall ----
moved = []
for h in plan["houses"]:
    target = {"sugarcube": "sugarcube_corner", "town_hall": "town_hall"}.get(h["design"])
    if not target:
        continue
    for i, s in enumerate(kept):
        if kind(s) == "node" and attr(s, "name") == target and attr(s, "parent") == ".":
            m = re.search(r"transform = Transform3D\(([^)]*)\)", s)
            vals = [float(v) for v in m.group(1).split(",")]
            scale = math.sqrt(vals[0] ** 2 + vals[3] ** 2 + vals[6] ** 2)
            y = ground_under(h["design"], scale, h)
            if h["design"] == "town_hall":
                # flat on the square (third play test): its node 4 cm under the ground, so its cobble foundation and
                # the stone ramp before its steps (both below the node) stay buried and the steps rise straight from
                # the square; hall_interior.gd puts the spot a pony goes in from on the ground
                y = float(ground[min(NZ - 1, max(0, round(h["z"]) - Z0)), min(NX - 1, max(0, round(h["x"]) - X0))]) - 0.04
            kept[i] = s[:m.start()] + "transform = " + transform(h["yaw"], scale, h["x"], y, h["z"]) + s[m.end():]
            moved.append(target)

# ---- the root's counts ----
for i, s in enumerate(kept):
    if kind(s) == "node" and attr(s, "parent") is None:
        s = re.sub(r"metadata/residential_count = \d+", f"metadata/residential_count = {real}", s)
        if "metadata/background_count" not in s:
            s = s.rstrip(nl) + f"{nl}metadata/background_count = {bg}{nl}metadata/layout_source = \"tools/town_planner/{os.path.basename(PLAN)}\"{nl}{nl}"
        kept[i] = s

# ---- write: header, resources (old then new ext), nodes, the new houses ----
head += "".join(s for s in kept if kind(s) == "gd_scene")
res = [s for s in kept if kind(s) in ("ext_resource", "sub_resource")]
rest = [s for s in kept if kind(s) not in ("ext_resource", "sub_resource", "gd_scene")]
first_sub = next((i for i, s in enumerate(res) if kind(s) == "sub_resource"), len(res))
res = res[:first_sub] + new_ext + ([nl] if new_ext and first_sub < len(res) else []) + res[first_sub:]
count = sum(1 for s in res if s.startswith("[ext_resource") or s.startswith("[sub_resource"))
head = re.sub(r"load_steps=\d+", f"load_steps={count + 1}", head)
if not rest[-1].endswith(nl + nl):
    rest[-1] = rest[-1].rstrip(nl) + nl + nl
out = head + "".join(res) + "".join(rest) + holder + "".join(nodes)
open(TOWN, "w", encoding="utf-8", newline="").write(out.rstrip(nl) + nl)
print(f"removed {len(removed_paths)} old nodes and {dropped_subs} resources only they used; moved {moved}")
print(f"real homes {real} ({vacant} vacant), background houses {bg}; town.tscn {len(out) // 1024} KB")
