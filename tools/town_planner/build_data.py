"""Town planner: gathers what the game knows about Ponyville into the files the planner page loads.

    python tools/town_planner/build_data.py

Reads the game's own data (town layout, scenery, water, terrain textures) and the ground exported
by export_ground.gd, and writes into tools/town_planner/data/:
  town.js      everything placed in town today, as `window.TOWN = {...}`
  relief.png   shaded ground heights, one pixel per ground sample
  paths.png    where the ground is painted as a path (the texture ponies prefer to walk on)
  water.png    the town's canal water
Coordinates are the game's world metres: x east, z south (north is -z), y up.
"""
import base64
import json
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tools", "town_planner", "data")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as file:
        return json.load(file)


def houses():
    """The houses standing in town.tscn (the scene the game loads), with the layout's design names."""
    layout = read("world/towns/ponyville/layout.json")
    by_id = {row["id"]: row for row in layout["placements"]}
    text = open(os.path.join(ROOT, "world/towns/ponyville/town.tscn"), encoding="utf-8").read()
    resources = dict(re.findall(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text))
    resources = {ident: path for path, ident in resources.items()}
    found = []
    pattern = re.compile(r'\[node name="(plot_\d+(?:_outer)?)" type="Node3D" parent="\." instance=ExtResource\("([^"]+)"\)\]\ntransform = Transform3D\(([^)]+)\)')
    for name, ident, numbers in pattern.findall(text):
        t = [float(v) for v in numbers.split(",")]
        scene = resources.get(ident, "")
        design = re.sub(r"^.*house_([a-z])\.t?scn$", r"\1", scene) if "house_" in scene else os.path.basename(scene).split(".")[0]
        row = by_id.get(name.replace("_outer", ""), {})
        # Godot's Transform3D lists the basis by rows: x axis is (t0, t3, t6), z axis is (t2, t5, t8).
        scale = (t[0] ** 2 + t[3] ** 2 + t[6] ** 2) ** 0.5
        yaw = float(np.arctan2(t[2], t[8]))
        found.append({"id": name, "design": design, "x": round(t[9], 3), "y": round(t[10], 3), "z": round(t[11], 3),
                      "yaw": round(yaw, 5), "scale": round(scale, 4),
                      "roof": [[round(p[0], 2), round(p[1], 2)] for p in row.get("roof_polygon", [])]})
    designs = {}
    for key, model in layout["models"].items():
        scales = [h["scale"] for h in found if h["design"] == key]
        designs[key] = {"footprint": model.get("footprint", []), "door": model.get("door", [0, 0]),
                        "scale": round(float(np.median(scales)), 4) if scales else float(model.get("world_scale", 10.0)),
                        "scene": model.get("scene", "")}
    plots = [{"id": p["id"], "x": round(p["reference_position"][0], 2), "z": round(p["reference_position"][2], 2),
              "status": p.get("status", "")} for p in layout["plots"]]
    sites = [{"name": s["name"], "x": round(s["position"][0], 2), "z": round(s["position"][2], 2)} for s in layout["reserved_sites"]]
    return found, designs, plots, sites


def railway():
    """The game's track (world/railway/network.json) within 900 m of the town, labelled with its line."""
    data = read("world/railway/network.json")
    lines = {}
    for line in data["lines"]:
        for leg in line["legs"]:
            for seg, _ in leg["path"]:
                lines.setdefault(seg, line["name"])
    out = []
    for seg in data["segments"]:
        pts = [[round(p[0], 1), round(p[1], 1)] for p in seg["points"] if -800 <= p[0] <= 1000 and -1100 <= p[1] <= 700]
        if len(pts) > 1:
            out.append({"id": seg["id"], "label": lines.get(seg["id"], "") + " (" + seg["a"] + " - " + seg["b"] + ")", "points": pts})
    return out


def scenery():
    data = read("world/props/ponyville/rnl_scenery.json")
    rows = []
    for entry in data["entries"]:
        position = entry.get("position", [0, 0, 0])
        rows.append({"id": entry.get("id", ""), "label": entry.get("label", entry.get("ai_label", "")), "group": entry.get("group", ""),
                     "kind": entry.get("class", ""), "model": entry.get("model", ""),
                     "x": round(position[0], 2), "y": round(position[1], 2), "z": round(position[2], 2),
                     "yaw": round(float(entry.get("yaw", 0.0)), 4),
                     "footprint": [[round(p[0], 2), round(p[1], 2)] for p in (entry.get("footprint") or [])],
                     "ends": entry.get("ends") or []})
    return rows


def water():
    canals = read("world/water/ponyville_canals.json")
    width, depth = int(canals["width"]), int(canals["depth"])
    grid = np.frombuffer(base64.b64decode(canals["heights"]), dtype="<f4").reshape(depth, width)
    wet = np.isfinite(grid)
    image = np.zeros((depth, width, 4), dtype=np.uint8)
    image[wet] = (60, 140, 220, 190)
    Image.fromarray(image, "RGBA").save(os.path.join(OUT, "water.png"))
    rivers = [{"id": r["id"], "width": r["width"], "points": [[round(p[0], 1), round(p[2], 1)] for p in r["points"]]}
              for r in read("world/water/rivers.json")["rivers"]]
    lakes = read("world/water/lakes.json")
    return {"canals": {"origin": canals["origin"], "cell": canals["cell"], "width": width, "depth": depth,
                       "level": round(float(np.nanmedian(grid)), 2)},
            "rivers": rivers, "lakes": lakes.get("lakes", []), "sea_level": lakes.get("sea_level")}


def ground():
    meta_path = os.path.join(OUT, "ground.json")
    if not os.path.exists(meta_path):
        print("no ground.json yet: run export_ground.gd with Godot first; the page will show no relief")
        return None
    meta = json.load(open(meta_path))
    columns, rows = int(meta["columns"]), int(meta["rows"])
    heights = np.fromfile(os.path.join(OUT, "heights.f32"), dtype="<f4").reshape(rows, columns)
    control = np.fromfile(os.path.join(OUT, "control.u32"), dtype="<u4").reshape(rows, columns)
    known = np.isfinite(heights)
    low, high = float(np.nanpercentile(heights, 1)), float(np.nanpercentile(heights, 99))
    filled = np.where(known, heights, low)
    # Hillshade from the north-west, over a green-to-tan height tint.
    step = float(meta["step"])
    dz, dx = np.gradient(filled, step)
    shade = np.clip(0.72 + 1.6 * (-dx - dz) / np.sqrt(1.0 + dx * dx + dz * dz), 0.25, 1.25)
    level = np.clip((filled - low) / max(high - low, 1e-6), 0.0, 1.0)
    low_tint = np.array([118, 168, 96], dtype=np.float32)
    high_tint = np.array([206, 190, 150], dtype=np.float32)
    colour = low_tint[None, None, :] * (1.0 - level[..., None]) + high_tint[None, None, :] * level[..., None]
    colour = np.clip(colour * shade[..., None], 0, 255).astype(np.uint8)
    colour[~known] = (40, 40, 48)
    Image.fromarray(colour, "RGB").save(os.path.join(OUT, "relief.png"))
    # Path paint: Terrain3D control word = base texture (5 bits at 27), overlay (5 bits at 22), blend (8 bits at 14).
    trail = {int(t["id"]) for t in read("world/terrain/textures.json")["textures"] if t.get("navigation_trail")}
    base = (control >> 27) & 31
    overlay = (control >> 22) & 31
    blend = ((control >> 14) & 255).astype(np.float32) / 255.0
    weight = np.isin(base, list(trail)) * (1.0 - blend) + np.isin(overlay, list(trail)) * blend
    paths = np.zeros((rows, columns, 4), dtype=np.uint8)
    paths[..., 0:3] = (222, 196, 140)
    paths[..., 3] = np.clip(weight * 230, 0, 255).astype(np.uint8)
    Image.fromarray(paths, "RGBA").save(os.path.join(OUT, "paths.png"))
    # Heights for the page's read-out, at a quarter of the samples, as 16-bit steps.
    small = filled[::2, ::2]
    packed = np.clip((small - low) / max(high - low, 1e-6) * 65535.0, 0, 65535).astype("<u2")
    return {"bounds": meta["bounds"], "step": step, "columns": columns, "rows": rows, "low": round(low, 2), "high": round(high, 2),
            "sample_step": step * 2, "sample_columns": int(small.shape[1]), "sample_rows": int(small.shape[0]),
            "samples": base64.b64encode(packed.tobytes()).decode("ascii")}


def main():
    os.makedirs(OUT, exist_ok=True)
    placed, designs, plots, sites = houses()
    town = {"houses": placed, "designs": designs, "plots": plots, "sites": sites, "scenery": scenery(), "water": water(), "ground": ground(),
            "railway": railway()}
    with open(os.path.join(OUT, "town.js"), "w", encoding="utf-8", newline="\n") as file:
        file.write("window.TOWN = " + json.dumps(town, separators=(",", ":")) + ";\n")
    print("houses %d, designs %d, plots %d, sites %d, scenery %d, ground %s" % (
        len(placed), len(designs), len(plots), len(sites), len(town["scenery"]), "yes" if town["ground"] else "no"))


if __name__ == "__main__":
    sys.exit(main())
