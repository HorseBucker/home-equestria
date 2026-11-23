"""A performance experiment (2026-11-17): the town scene trimmed to KEEP houses. Every lived-in real home stays,
plus one vacant real home of each design, plus background houses; the rest go. What stays is spread evenly over
the whole map (each pick the house farthest from everything kept so far), not cut out of one part of town.
Landmarks (Town Hall, Sugarcube Corner and the scenery buildings) are not houses and are untouched. Writes a copy;
never edits the real town.tscn. (Gardens and mailboxes of the houses taken out stay where they were: a test.)

usage: python tools/town_planner/build/qc/perf_trim.py <town.tscn> <out.tscn> [KEEP]
"""
import math, re, sys

src, out = sys.argv[1], sys.argv[2]
KEEP = int(sys.argv[3]) if len(sys.argv) > 3 else 75
t = open(src, encoding="utf-8").read().rstrip("\n") + "\n\n"   # (the last node block ends the file)
ext = {rid: path for path, rid in re.findall(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', t)}
block_re = re.compile(r'\[node name="((?:plot|bg)_\d+)" parent="(?:\.|BackgroundHouses)" instance=ExtResource\("([^"]+)"\)\]\n(?:(?!\n\[).)*\n\n', re.S)
houses = []
for m in block_re.finditer(t):
    name, rid, block = m.group(1), m.group(2), m.group(0)
    v = [float(x) for x in re.search(r"Transform3D\(([^)]*)\)", block).group(1).split(",")]
    houses.append({"name": name, "design": re.search(r"house_(\w)", ext[rid]).group(1), "at": (v[9], v[11]), "block": block,
                   "kind": "bg" if name.startswith("bg_") else ("vacant" if "metadata/vacant = true" in block else "owned")})
kept = [h for h in houses if h["kind"] == "owned"]


def far(cands):
    return max(cands, key=lambda h: min(math.dist(h["at"], k["at"]) for k in kept))


for design in sorted({h["design"] for h in houses if h["kind"] == "vacant"}):
    kept.append(far([h for h in houses if h["kind"] == "vacant" and h["design"] == design]))
pool = [h for h in houses if h["kind"] == "bg"]
while len(kept) < KEEP and pool:
    pick = far(pool); kept.append(pick); pool.remove(pick)
names = {h["name"] for h in kept}
for h in houses:
    if h["name"] not in names:
        t = t.replace(h["block"], "", 1)
open(out, "w", encoding="utf-8", newline="").write(t)
count = lambda kind: sum(1 for h in kept if h["kind"] == kind)
print(f"kept {len(kept)} of {len(houses)}: {count('owned')} lived-in real, {count('vacant')} vacant real, {count('bg')} background; "
      f"vacant kept by design {sorted(h['design'] for h in kept if h['kind'] == 'vacant')}")
