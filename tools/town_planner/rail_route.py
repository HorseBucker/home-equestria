"""Join the plan's railway to the game's network outside the map, and say how each line then runs.

usage: python tools/town_planner/rail_route.py <project> <plan.json> [<out.json>]

The official map has one line: in from the north-west ("to the Equestrian Heartlands"), past the station,
out to the south-west into a tunnel (the Frontier Loop to Ghastly Gorge), with a second tunnel beside it.
In the game today the Ponyville track leaves to the north-east instead (seg0, Ponyville - Junction 5,
across the north of the map) and four lines start on it. This works out new track, all outside the
map's edge, so that every line still runs:
- "Heartland link": from the map's north-west track end to the Meadowline main line (seg2, Junction 8 -
  Heartland), joining it heading for Heartland. seg0 is taken up.
- "Canterlot chord": a short curve near Junction 8 from seg2 onto seg33, so the Canterlot Express can
  still turn north (before, it came up seg1 from the south).
- "Ghastly Gorge link": from the map's west tunnel to the Frontier Loop (seg17) beyond the edge.
Each is a smooth curve tested against the network's own rules (curves no tighter than its minimum
radius, slopes no steeper than its adhesion grade, using the ground heights the track was built on).
The results go into plan["railways"] (marked "outside") and plan["rail_network"].
"""
import json, math, sys
import numpy as np

ROOT, SRC = sys.argv[1], sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 else SRC
plan = json.load(open(SRC, encoding="utf-8"))
net = json.load(open(ROOT + "/world/railway/network.json", encoding="utf-8"))
built = json.load(open(ROOT + "/world/railway/network_built.json", encoding="utf-8"))
RULES = built["rules"]
R_MIN = RULES["min_radius"] * 1.15          # a margin over the network's minimum
G_MAX = RULES["adhesion_grade"] * 0.9
BUILT = {s["id"]: s for s in built["segments"]}
# the built track's own points (x, y, z) are the ones to join; SEG gives their x, z
SEG = {sid: {"points": [[p[0], p[2]] for p in s["points"]]} for sid, s in BUILT.items()}
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
gj = json.load(open(HERE + "/data/ground.json"))
ground = np.fromfile(HERE + "/data/heights.f32", np.float32).reshape(gj["rows"], gj["columns"])
edge = plan["edges"][0]["points"]
BX0, BX1 = min(p[0] for p in edge), max(p[0] for p in edge)
BZ0, BZ1 = min(p[1] for p in edge), max(p[1] for p in edge)


def ground_at(x, z):
    c = (x - gj["bounds"][0]) / gj["step"]; r = (z - gj["bounds"][2]) / gj["step"]
    c = min(max(c, 0), gj["columns"] - 1.001); r = min(max(r, 0), gj["rows"] - 1.001)
    c0, r0 = int(c), int(r); fc, fr = c - c0, r - r0
    g = ground
    return float(g[r0, c0] * (1 - fc) * (1 - fr) + g[r0, c0 + 1] * fc * (1 - fr) + g[r0 + 1, c0] * (1 - fc) * fr + g[r0 + 1, c0 + 1] * fc * fr)


def rail_y(sid, i):
    """Rail height at a point of a built segment (its points carry y)."""
    return BUILT[sid]["points"][i][1]


def unit(v):
    n = math.hypot(*v) or 1.0
    return (v[0] / n, v[1] / n)


def bezier(p0, t0, p1, t1, h0, h1, n=160):
    a = np.array(p0); d = np.array(p1)
    b = a + np.array(t0) * h0; c = d - np.array(t1) * h1
    s = np.linspace(0, 1, n)[:, None]
    pts = (1 - s) ** 3 * a + 3 * (1 - s) ** 2 * s * b + 3 * (1 - s) * s ** 2 * c + s ** 3 * d
    d1 = 3 * (1 - s) ** 2 * (b - a) + 6 * (1 - s) * s * (c - b) + 3 * s ** 2 * (d - c)
    d2 = 6 * (1 - s) * (c - 2 * b + a) + 6 * s * (d - 2 * c + b)
    k = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / np.maximum(np.hypot(d1[:, 0], d1[:, 1]) ** 3, 1e-9)
    radius = float(1 / max(k.max(), 1e-9))
    length = float(np.sum(np.hypot(*np.diff(pts, axis=0).T)))
    return pts, radius, length


def inside_map(p, pad=0.0):
    return BX0 + pad < p[0] < BX1 - pad and BZ0 + pad < p[1] < BZ1 - pad


def best_link(start, start_dir, y0, sid, indices, forward, keep_out=True):
    """The shortest good curve from `start` (heading start_dir) onto segment `sid` at one of `indices`,
    arriving in its direction of travel (forward: towards its end b)."""
    pts = SEG[sid]["points"]
    best = None
    for i in indices:
        q = pts[i]
        nxt = pts[min(len(pts) - 1, i + 2)] if forward else pts[max(0, i - 2)]
        prv = pts[max(0, i - 2)] if forward else pts[min(len(pts) - 1, i + 2)]
        t1 = unit((nxt[0] - prv[0], nxt[1] - prv[1]))
        span = math.dist(start, q)
        for f0 in (0.2, 0.3, 0.4, 0.5, 0.6):
            for f1 in (0.2, 0.3, 0.4, 0.5, 0.6):
                curve, radius, length = bezier(start, start_dir, q, t1, span * f0, span * f1)
                if radius < R_MIN:
                    continue
                if keep_out and any(inside_map(p, 1.0) for p in curve[3:]):
                    continue
                grade = abs(rail_y(sid, i) - y0) / length
                if grade > G_MAX:
                    continue
                if best is None or length < best["length"]:
                    best = {"points": curve, "radius": radius, "length": length, "grade": grade, "at": i, "end": q}
    return best


def track_end(railway, near):
    pts = railway["points"]
    k = 0 if math.dist(pts[0], near) < math.dist(pts[-1], near) else -1
    p = pts[k]; q = pts[1] if k == 0 else pts[-2]
    return p, unit((p[0] - q[0], p[1] - q[1]))


links = {l["joins"].split(":")[0]: l for l in plan.get("rail_links", [])}
rails = plan["railways"]
plan["railways"] = [r for r in rails if not r.get("outside")]
rails = plan["railways"]
report = []
village_y = float(plan.get("terrain", {}).get("base", -12.0)) + 1.0     # rail top on the village's flat

# Heartland link: north-west end -> seg2 heading for Heartland
nw = next(l for l in plan["rail_links"] if l["joins"].startswith("The Meadowline"))
p0, d0 = track_end(rails[nw["railway"]], nw["at"])
seg2 = SEG["seg2"]["points"]
north = best_link(p0, d0, village_y, "seg2", range(4, len(seg2) - 2, 3), True)
# Ghastly Gorge link: west tunnel end -> seg17 heading away from Ponyville
wt = next(l for l in plan["rail_links"] if l["joins"].startswith("The Frontier Loop"))
p1, d1 = track_end(rails[wt["railway"]], wt["at"])
seg17 = SEG["seg17"]["points"]
far = [i for i, q in enumerate(seg17) if not inside_map(q) and q[0] < BX0 - 40][:150]
west = best_link(p1, d1, village_y, "seg17", far, True)
# Canterlot chord: seg2 (eastbound, towards Junction 8) -> seg33 (northbound)
chord = None
for i in range(6, 160, 3):
    a = seg2[i]; b = seg2[i - 2]
    t0 = unit((b[0] - a[0], b[1] - a[1]))          # eastbound along seg2 means towards its start
    c = best_link(a, t0, rail_y("seg2", i), "seg33", range(3, min(len(SEG["seg33"]["points"]) - 2, 220), 3), True, keep_out=False)
    if c and (chord is None or c["length"] < chord["length"]):
        chord = dict(c, start=i)

ok = all([north, west, chord])
for name, r in (("Heartland link", north), ("Ghastly Gorge link", west), ("Canterlot chord", chord)):
    if not r:
        report.append(f"{name}: no curve fits the rules - needs a hand-drawn route")
        continue
    rails.append({"points": [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in r["points"][::4]] + [[round(r["end"][0], 1), round(r["end"][1], 1)]],
                  "outside": True, "name": name})
    report.append(f"{name}: {r['length']:.0f} m, tightest curve radius {r['radius']:.0f} m (rule {RULES['min_radius']:.0f}), "
                  f"steepest {r['grade'] * 100:.1f}% (rule {RULES['adhesion_grade'] * 100:.1f}%)")

if ok:
    plan["rail_network"] = {
        "take_up": ["seg0 (Ponyville - Junction 5): crosses the north of the map; replaced by the map's line and the Heartland link"],
        "new": [
            {"name": "Heartland link", "from": "the map's north-west track end", "to": f"seg2 at point {north['at']} (about {SEG['seg2']['points'][north['at']][0]:.0f}, {SEG['seg2']['points'][north['at']][1]:.0f})"},
            {"name": "Ghastly Gorge link", "from": "the map's west tunnel", "to": f"seg17 at point {west['at']}"},
            {"name": "Canterlot chord", "from": f"seg2 at point {chord['start']}", "to": f"seg33 at point {chord['at']}"}],
        "station": "Ponyville station moves to the map's R1, beside the traced track",
        "lines": {
            "The Meadowline": "Ponyville - Heartland link - seg2 - Heartland - Vanhoover (shorter than before)",
            "The Frontier Loop": "Ponyville - west tunnel - Ghastly Gorge ... round the loop ... Heartland - seg2 - Heartland link - Ponyville",
            "The Seaboard Line": "Ponyville - Heartland link - seg2 east to Junction 8 - seg1 - Junction 5 - seg14 - Saddle Lake ...",
            "The Canterlot Express": "Ponyville - Heartland link - seg2 east - Canterlot chord - seg33 - Canterlot"}}
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
print("\n".join(report))
