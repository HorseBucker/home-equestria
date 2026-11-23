"""A performance experiment (2026-11-17): the town scene with every vacant real home swapped for the background
house of its design, same place and size (no interior, no door, no furniture). Writes a copy; never edits the
real town.tscn.

usage: python tools/town_planner/build/qc/perf_variant.py <town.tscn> <out.tscn>
"""
import re, sys

src, out = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
ext = {path: rid for path, rid in re.findall(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', t)}
real_ids = {rid: re.search(r"house_(\w)\.", path).group(1) for path, rid in ext.items() if re.search(r"/ponyville/house_\w\.t?scn$", path)}
bg_ids = {re.search(r"house_(\w)_bg", path).group(1): rid for path, rid in ext.items() if "_bg.scn" in path}
added = []
for design in set(real_ids.values()):
    if design not in bg_ids:
        rid = f"9{len(added)}_perf"
        bg_ids[design] = rid
        added.append(f'[ext_resource type="PackedScene" path="res://world/towns/ponyville/background/house_{design}_bg.scn" id="{rid}"]\n')
if added:
    first = t.index("[ext_resource")
    t = t[:first] + "".join(added) + t[first:]
    t = re.sub(r"load_steps=(\d+)", lambda m: f"load_steps={int(m.group(1)) + len(added)}", t, count=1)

swapped = 0


def swap(m):
    global swapped
    block = m.group(0)
    if "metadata/vacant = true" not in block:
        return block
    name, rid = m.group(1), m.group(2)
    design = real_ids.get(rid)
    if design is None:
        return block
    transform = re.search(r"transform = Transform3D\([^)]*\)", block).group(0)
    swapped += 1
    return f'[node name="vacant_{name}" parent="BackgroundHouses" instance=ExtResource("{bg_ids[design]}")]\n{transform}\n\n'


# a node block runs from its header to the next header
t = re.sub(r'\[node name="(plot_\d+)" parent="\." instance=ExtResource\("([^"]+)"\)\]\n(?:(?!\n\[).)*\n\n', swap, t, flags=re.S)
# the swapped houses are added under BackgroundHouses: move them after that node's own header
blocks = re.findall(r'\[node name="vacant_plot_\d+"[^\n]*\n[^\n]*\n\n', t)
for b in blocks:
    t = t.replace(b, "", 1)
t = t.rstrip("\n") + "\n\n" + "".join(blocks)
open(out, "w", encoding="utf-8", newline="").write(t)
print(f"swapped {swapped} vacant real homes for background houses; added ext resources: {len(added)}")
