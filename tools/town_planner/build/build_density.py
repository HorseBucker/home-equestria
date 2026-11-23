"""Town density (2026-11-17): the town at each density setting, built from its plan beside the full town.

usage: python tools/town_planner/build/build_density.py <project> <high plan.json> <plan_minimum.json> <plan_low.json> <plan_medium.json>
(after the full build of the high plan: town.tscn, build/out's ground grid and placements.json are that build's)

The game offers a town density setting (Settings > Graphics > Town density; world/towns/ponyville/town_density.gd)
for weaker PCs. High is the built town (town.tscn). Each lower setting is its own plan (make_density_plans.py,
fill_vacant_homes.py): the same streets, landmarks and lived-in homes, fewer houses. This writes for each:

- world/towns/ponyville/town_<setting>.tscn: town.tscn with the plan's houses in place of the full town's. A
  house the full town also has, as the same kind (real or background) and size, is its node exactly as built.
  One that changed kind or size is made the way build_town.py makes it (height from the ground under it, a
  background house's lean). Every house keeps one name at every setting, so whatever names a house (a pony's
  garden, the player's home) finds it at any density: the full town's names as they are, plot_5NN / bg_5NN
  for a house that is real or background only at the lower settings.
- world/props/ponyville_kit/density/<setting>.json: the gardens of that town's houses (plan_props.py's own
  gardens step run on the plan, nothing written by it), which replace the full town's garden rows.
- world/towns/ponyville/density/houses.json: every house that is a real home at any setting (name, design,
  scene, transform, the settings it is real at) and each design's footprint, so the game can put the player's
  home back at a setting that does not have it (town_density.gd keep_homes()).
Trees, street furniture, the bunting, the farm and the vegetation are the full town's at every setting.
"""
import json, math, os, re, statistics, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import plan_geometry as G

ROOT, HIGH = sys.argv[1], sys.argv[2]
LOWER = sys.argv[3:]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TOWN_DIR = os.path.join(ROOT, "world/towns/ponyville")
TOWN = os.path.join(TOWN_DIR, "town.tscn")
REAL = {"a": "house_a.tscn", "b": "house_b.tscn", "c": "house_c.tscn", "d": "house_d.tscn",
        "e": "house_e.scn", "f": "house_f.scn", "g": "house_g.scn", "h": "house_h.scn"}
DESIGNS = G.TOWN["designs"]
grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
ground = np.fromfile(os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
high = json.load(open(HIGH, encoding="utf-8"))
text = open(TOWN, encoding="utf-8").read()
nl = "\r\n" if "\r\n" in text else "\n"
text = text.rstrip(nl) + nl + nl


def num(v):
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def transform_vals(yaw, scale, x, y, z):
    c, s = math.cos(yaw) * scale, math.sin(yaw) * scale
    return [c, 0, s, 0, scale, 0, -s, 0, c, x, y, z]


def ground_under(design, scale, h):
    """As build_town.py: the median of the ground under the footprint and halfway in."""
    d = DESIGNS[design]
    c, s = math.cos(h["yaw"]), math.sin(h["yaw"])
    heights = []
    for p in d["footprint"]:
        for t in (0.0, 0.5):
            lx, lz = p[0] * scale * (1 - t), p[1] * scale * (1 - t)
            wx, wz = h["x"] + lx * c + lz * s, h["z"] - lx * s + lz * c
            heights.append(float(ground[min(NZ - 1, max(0, round(wz) - Z0)), min(NX - 1, max(0, round(wx) - X0))]))
    return statistics.median(heights)


def scale_of(h):
    return h.get("scale") or DESIGNS[h["design"]]["scale"]


# ---- the full town's houses: plan index -> its node (build_town.py names them in the plan's order) ----
blocks = {}
for m in re.finditer(r'\[node name="((?:plot|bg)_\d+)" parent="(?:\.|BackgroundHouses)" instance=ExtResource\("([^"]+)"\)\]' + re.escape(nl) + r'(?:(?!' + re.escape(nl) + r'\[).)*?' + re.escape(nl + nl), text, re.S):
    blocks[m.group(1)] = m.group(0)
high_name = {}
real_n = bg_n = 0
for i, h in enumerate(high["houses"]):
    if len(h["design"]) != 1:
        continue
    if not h.get("filler", True):
        real_n += 1; high_name[i] = f"plot_{real_n:03d}"
    else:
        bg_n += 1; high_name[i] = f"bg_{bg_n:03d}"
assert len(blocks) == len(high_name), f"town.tscn has {len(blocks)} houses, the plan {len(high_name)}: build the high plan first"
for i, name in high_name.items():      # the scene is the plan's build: the same spot for every house
    t = [float(v) for v in re.search(r"Transform3D\(([^)]*)\)", blocks[name]).group(1).split(",")]
    assert abs(t[9] - high["houses"][i]["x"]) < 0.02 and abs(t[11] - high["houses"][i]["z"]) < 0.02, (name, t[9:], high["houses"][i])
spot = {(h["design"], round(h["x"], 2), round(h["z"], 2)): i for i, h in enumerate(high["houses"]) if len(h["design"]) == 1}

# ext resources
ext = {path: rid for path, rid in re.findall(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text)}

plans = {}
for path in LOWER:
    p = json.load(open(path, encoding="utf-8"))
    plans[p["density"]["setting"]] = (path, p)
order = [s for s in ("minimum", "low", "medium") if s in plans]

# one name per house at every setting: houses real (or background) only at lower settings get 5NN names, in the
# full plan's order
extra_real, extra_bg = {}, {}
for setting in order:
    for h in plans[setting][1]["houses"]:
        if len(h["design"]) != 1:
            continue
        i = spot[(h["design"], round(h["x"], 2), round(h["z"], 2))]
        was_real = not high["houses"][i].get("filler", True)
        if not h.get("filler", True) and not was_real: extra_real[i] = None
        if h.get("filler", True) and was_real: extra_bg[i] = None
for k, i in enumerate(sorted(extra_real), 501): extra_real[i] = f"plot_{k}"
for k, i in enumerate(sorted(extra_bg), 501): extra_bg[i] = f"bg_{k}"

houses_out = {}           # every real home at any setting
footprints = {d: DESIGNS[d]["footprint"] for d in REAL}


def note_real(name, design, vals, setting):
    row = houses_out.setdefault(name, {"design": design, "scene": f"res://world/towns/ponyville/{REAL[design]}", "transform": [round(v, 6) for v in vals], "settings": []})
    row["settings"].append(setting)


for i, name in high_name.items():
    h = high["houses"][i]
    if not h.get("filler", True):
        t = [float(v) for v in re.search(r"Transform3D\(([^)]*)\)", blocks[name]).group(1).split(",")]
        note_real(name, h["design"], t, "high")

# ---- the gardens: plan_props.py's own steps up to its gardens, run on another plan, nothing written ----
SRC = open(os.path.join(HERE, "plan_props.py"), encoding="utf-8").read()
a_end = SRC.index('bundle_path = os.path.join(ROOT, "world/biomes/authored/bundle.json")')
b0 = SRC.index("# ---- spacing helper")
b1 = SRC.index('json.dump(props, open(os.path.join(OUT, "props.json"), "w"), indent=1)')
c0 = SRC.index("# ---- 4. gardens")
c1 = SRC.index("def row(kind, x, z, yaw, group")
GARDEN_CODE = compile(SRC[:a_end] + SRC[b0:b1] + SRC[c0:c1], "plan_props.py (gardens)", "exec")


def gardens(plan_path):
    argv = sys.argv
    sys.argv = [os.path.join(HERE, "plan_props.py"), ROOT, plan_path]
    scope = {"__name__": "plan_props_gardens", "__file__": os.path.join(HERE, "plan_props.py")}
    try:
        exec(GARDEN_CODE, scope)
    finally:
        sys.argv = argv
    return scope["rows"]


os.makedirs(os.path.join(ROOT, "world/props/ponyville_kit/density"), exist_ok=True)
os.makedirs(os.path.join(TOWN_DIR, "density"), exist_ok=True)
for setting in order:
    path, plan = plans[setting]
    leans = G.house_leans(plan)
    new_ext = []

    def ext_id(scene):
        if scene not in ext:
            rid = f"{200 + len(ext)}_density"
            ext[scene] = rid
            new_ext.append(f'[ext_resource type="PackedScene" path="{scene}" id="{rid}"]{nl}')
        return ext[scene]

    nodes, names_by_index = [], {}
    real = vacant = bg = copied = made = 0
    real_ordinal = []
    for n, h in enumerate(plan["houses"]):
        design = h["design"]
        if len(design) != 1:
            continue
        i = spot[(design, round(h["x"], 2), round(h["z"], 2))]
        hh = high["houses"][i]
        is_real = not h.get("filler", True)
        was_real = not hh.get("filler", True)
        same = is_real == was_real and abs(scale_of(h) - scale_of(hh)) < 1e-4 and abs(h["yaw"] - hh["yaw"]) < 1e-6
        if is_real:
            real += 1; real_ordinal.append(n)
            name = high_name[i] if was_real else extra_real[i]
        else:
            bg += 1
            name = extra_bg[i] if was_real else high_name[i]
        names_by_index[n] = name
        if same:
            nodes.append(blocks[name]); copied += 1
            if is_real and not h.get("residents"): vacant += 1
            if is_real:
                t = [float(v) for v in re.search(r"Transform3D\(([^)]*)\)", blocks[name]).group(1).split(",")]
                note_real(name, design, t, setting)
            continue
        made += 1
        scale = scale_of(h)
        vals = transform_vals(h["yaw"], scale, h["x"], ground_under(design, scale, h), h["z"])
        tf = "Transform3D(" + ", ".join(num(v) for v in vals) + ")"
        if is_real:
            lines = [f'[node name="{name}" parent="." instance=ExtResource("{ext_id("res://world/towns/ponyville/" + REAL[design])}")]', f"transform = {tf}",
                     f'metadata/building_design = "{design}"', f'metadata/residential_plot = "{name}"']
            assert not h.get("residents"), f"{name}: a lived-in home changed ({setting})"
            lines.append("metadata/vacant = true"); vacant += 1
            note_real(name, design, vals, setting)
        else:
            lines = [f'[node name="{name}" parent="BackgroundHouses" instance=ExtResource("{ext_id(f"res://world/towns/ponyville/background/house_{design}_bg.scn")}")]', f"transform = {tf}"]
            if leans[n] != (0.0, 0.0): lines.append(f"lean = Vector2({leans[n][0]}, {leans[n][1]})")
        nodes.append(nl.join(lines) + nl + nl)
    # the full town without its houses, then these
    body = text
    for b in blocks.values():
        body = body.replace(b, "", 1)
    body = re.sub(r"metadata/residential_count = \d+", f"metadata/residential_count = {real}", body, count=1)
    body = re.sub(r"metadata/background_count = \d+", f"metadata/background_count = {bg}", body, count=1)
    body = re.sub(r'metadata/layout_source = "[^"]*"', f'metadata/layout_source = "tools/town_planner/{os.path.basename(path)}"' + nl + f'metadata/town_density = "{setting}"', body, count=1)
    if new_ext:
        last = list(re.finditer(r"\[ext_resource [^\n]*\]" + re.escape(nl), body))[-1]
        body = body[:last.end()] + "".join(new_ext) + body[last.end():]
    count = len(re.findall(r"^\[(?:ext|sub)_resource ", body, re.M))
    body = re.sub(r"load_steps=\d+", f"load_steps={count + 1}", body, count=1)
    # its own trees (plan_density_trees.py: the full town's and more in its open lawns)
    body = body.replace('path="res://world/props/ponyville/town_trees.scn"', f'path="res://world/props/ponyville/town_trees_{setting}.scn"')
    out_path = os.path.join(TOWN_DIR, f"town_{setting}.tscn")
    open(out_path, "w", encoding="utf-8", newline="").write((body.rstrip(nl) + nl + nl + "".join(nodes)).rstrip(nl) + nl)

    # gardens, their groups by the house names above
    rows = gardens(path)
    garden = []
    tag = {"minimum": "m", "low": "l", "medium": "d"}[setting]
    for k, r in enumerate(rows):
        g = str(r["group"])
        m = re.fullmatch(r"house:plot_(\d+)", g)
        if m:
            r["group"] = "house:" + names_by_index[real_ordinal[int(m.group(1)) - 1]]
        else:
            m = re.fullmatch(r"house:overhaul_(\d+)", g)
            if m:
                h = plan["houses"][int(m.group(1))]
                r["group"] = f"house:overhaul_{spot[(h['design'], round(h['x'], 2), round(h['z'], 2))]:03d}"
        r["id"] = re.sub(r"_ov(\d+)$", lambda mm: f"_ov{tag}{mm.group(1)}", r["id"])
        garden.append(r)
    json.dump({"setting": setting, "note": "Gardens of the town at this density (tools/town_planner/build/build_density.py): they replace "
               "placements.json's garden rows (group house:*, id *_ovNNNN) when the town is loaded at this setting.", "entries": garden},
              open(os.path.join(ROOT, f"world/props/ponyville_kit/density/{setting}.json"), "w", encoding="utf-8"), indent="\t")
    print(f"{setting:8s} town_{setting}.tscn: {real} real homes ({vacant} vacant), {bg} background ({copied} as built, {made} remade); "
          f"gardens {len(garden)} rows")

# The Board Games mod's public chess table (2026-11-18 play test: it floated at the old town's spot, x 252 z -258):
# the high plan's note "chess table [degrees]", on the ground there, its seats either side of the line from the
# fountain so both players have the fountain beside them (or turned by the note's degrees, 0 = seats along x).
# town_root.gd moves the table there as the mod sets it up (plaza_table_spot.gd).
chess = None
for note in high.get("notes", []):
    words = str(note.get("text", "")).lower().split()
    if words[:2] != ["chess", "table"]:
        continue
    cx, cz = float(note["x"]), float(note["z"])
    fountain = next((l for l in high["landmarks"] if l["id"] == "fountain_01"), None)
    if len(words) > 2:
        yaw = math.radians(float(words[2]))
    elif fountain is not None:
        yaw = math.atan2(-(cx - fountain["x"]), -(cz - fountain["z"]))
    else:
        yaw = 0.0
    y = float(ground[min(NZ - 1, max(0, round(cz) - Z0)), min(NX - 1, max(0, round(cx) - X0))])
    chess = {"x": round(cx, 2), "y": round(y, 3), "z": round(cz, 2), "yaw": round(yaw, 4)}
print("chess table:", chess)
json.dump({"note": "Every house that is a real home at any town density (build_density.py): where it stands at every setting it "
           "is real at, and each design's footprint at scale 1 (x, z), for town_density.gd keep_homes(). chess_table: where the "
           "Board Games mod's public table stands (plaza_table_spot.gd).",
           "houses": houses_out, "footprints": footprints, "chess_table": chess}, open(os.path.join(TOWN_DIR, "density/houses.json"), "w", encoding="utf-8"), indent="\t")
print(f"houses.json: {len(houses_out)} houses real at some setting ({len(extra_real)} only below high); {len(extra_bg)} of the full town's homes are background below high")

# each density's own ground (its own rises: apply_ground.py --density) and paint (door paths only to the houses it
# builds: apply_paint.py --density)
import subprocess
for path in LOWER:
    setting = json.load(open(path, encoding="utf-8")).get("density", {}).get("setting", "")
    if not setting:
        continue
    run = subprocess.run([sys.executable, os.path.join(HERE, "apply_ground.py"), ROOT, path, "--density", setting], capture_output=True, text=True)
    print(f"{setting:8s} ground:", (run.stdout.strip().splitlines() or [run.stderr[-300:]])[-1])
    run = subprocess.run([sys.executable, os.path.join(HERE, "apply_paint.py"), ROOT, path, "--density", setting], capture_output=True, text=True)
    print(f"{setting:8s} paint:", (run.stdout.strip().splitlines() or [run.stderr[-300:]])[-1])

# each density's own trees (2026-11-21 play test: the low settings "flat and empty"): plan_density_trees.py picks the
# spots on each density's ground (built above), apply_props.gd builds world/props/ponyville/town_trees_<setting>.scn
by_setting = {json.load(open(p_, encoding="utf-8")).get("density", {}).get("setting", ""): p_ for p_ in LOWER}
run = subprocess.run([sys.executable, os.path.join(HERE, "plan_density_trees.py"), ROOT, HIGH, by_setting["medium"], by_setting["low"], by_setting["minimum"]],
                     capture_output=True, text=True)
print(run.stdout.strip() or run.stderr[-600:])
for setting in ("high", "medium", "low", "minimum"):
    # (high: the full town's own town_trees.scn, rebuilt from build/out/props.json's trees and its added ones)
    out_scn = "res://world/props/ponyville/town_trees.scn" if setting == "high" else f"res://world/props/ponyville/town_trees_{setting}.scn"
    run = subprocess.run(["C:/Tools/Godot/godot.exe", "--headless", "--xr-mode", "off", "--path", ROOT, "--script", "res://tools/town_planner/build/apply_props.gd", "--",
                          f"res://tools/town_planner/build/out/trees_{setting}.json", out_scn],
                         capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
    print(f"{setting:8s}", next((l for l in run.stdout.splitlines() if l.startswith("TREES")), run.stdout[-300:] + run.stderr[-300:]))
