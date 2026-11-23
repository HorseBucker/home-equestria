"""Join up a plan's roads, rivers, lakes, bridges and town ground, and report what is left loose.

usage: python tools/town_planner/tidy_plan.py <plan.json> [<out.json>]

Every free end of a river is carried on to the water it belongs to: the next river piece, a lake, the
river it feeds, or the edge of the map along its own heading. Every free end of a road is carried on
to the town ground, another road, a bridge or the edge. Both ends of every bridge get a road (or the
town ground). Nothing is carried across a river except over a bridge. Ends that are fine as they are
(a road stopping at a farm or a house) are listed, so a person can look at them.
"""
import json, math, sys

SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else SRC
plan = json.load(open(SRC, encoding="utf-8"))
EDGE = plan["edges"][0]["points"] if plan.get("edges") else None
GROUNDS = [g["points"] for g in plan.get("grounds", [])]
LAKES = [l["points"] for l in plan.get("lakes", [])]
report = []


# ---- geometry ----
def near_on_seg(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / ((dx * dx + dz * dz) or 1)
    t = max(0.0, min(1.0, t))
    return [a[0] + t * dx, a[1] + t * dz]


def near_on_line(p, pts, close=False):
    q = pts + [pts[0]] if close else pts
    best = None
    for i in range(len(q) - 1):
        c = near_on_seg(p, q[i], q[i + 1])
        d = math.dist(p, c)
        if best is None or d < best[0]:
            best = (d, c, i)
    return best


def inside(poly, p):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
        j = i
    return hit


def crosses(a, b, c, d):
    def side(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    return (side(a, b, c) > 0) != (side(a, b, d) > 0) and (side(c, d, a) > 0) != (side(c, d, b) > 0)


def heading(pts, at_end):
    """Unit direction a line is travelling in at one of its ends (looking outward), over its last ~12 m."""
    seq = pts[::-1] if at_end else pts
    tip = seq[0]
    for q in seq[1:]:
        if math.dist(q, tip) >= 12:
            break
    d = math.dist(q, tip) or 1
    return [(tip[0] - q[0]) / d, (tip[1] - q[1]) / d]


def angle(u, v):
    return math.degrees(math.acos(max(-1.0, min(1.0, u[0] * v[0] + u[1] * v[1]))))


def ray_to_edge(p, d):
    if not EDGE:
        return None
    best = None
    q = EDGE + [EDGE[0]]
    for i in range(len(q) - 1):
        a, b = q[i], q[i + 1]
        ex, ez = b[0] - a[0], b[1] - a[1]
        den = d[0] * ez - d[1] * ex
        if abs(den) < 1e-9:
            continue
        t = ((a[0] - p[0]) * ez - (a[1] - p[1]) * ex) / den
        s = ((a[0] - p[0]) * d[1] - (a[1] - p[1]) * d[0]) / den
        if t > 0 and 0 <= s <= 1 and (best is None or t < best[0]):
            best = (t, [p[0] + d[0] * t, p[1] + d[1] * t])
    return best


def edge_dist(p):
    if not EDGE:
        return 1e9
    return 0.0 if not inside(EDGE, p) else near_on_line(p, EDGE, True)[0]


def push_inside(poly, c, by):
    """A point `by` metres inside a polygon from boundary point c."""
    mx = sum(q[0] for q in poly) / len(poly); mz = sum(q[1] for q in poly) / len(poly)
    for step in (1, -1):
        best = None
        for k in range(16):
            a = k * math.pi / 8
            q = [c[0] + math.cos(a) * by, c[1] + math.sin(a) * by]
            if inside(poly, q):
                d = math.dist(q, [mx, mz])
                if best is None or d < best[0]:
                    best = (d, q)
        if best:
            return best[1]
    return c


def r1(p):
    return [round(p[0], 1), round(p[1], 1)]


def wet_crossing(a, b, ignore=None):
    """Does the segment a-b cross a river (other than `ignore`) away from every bridge?"""
    for k, r in enumerate(plan.get("rivers", [])):
        if k == ignore:
            continue
        pts = r["points"]
        for i in range(len(pts) - 1):
            if crosses(a, b, pts[i], pts[i + 1]):
                bridged = any(crosses(a, b, br["a"], br["b"]) or min(math.dist(a, br["a"]), math.dist(a, br["b"]), math.dist(b, br["a"]), math.dist(b, br["b"])) < 6 for br in plan.get("bridges", []))
                if not bridged:
                    return True
    for lake in LAKES:
        if inside(lake, [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]):
            return True
    return False


# ---- rivers ----
rivers = plan.get("rivers", [])


def river_end_ok(i, end):
    r = rivers[i]
    p = r["points"][-1] if end else r["points"][0]
    reach = max(1.5, r["width"] / 2)
    if edge_dist(p) <= 3:
        return "edge"
    for lake in LAKES:
        if inside(lake, p) or near_on_line(p, lake, True)[0] <= reach:
            return "lake"
    for k, o in enumerate(rivers):
        if k != i and near_on_line(p, o["points"])[0] <= max(reach, o["width"] / 2):
            return "river"
    return None


fixed = {"river": 0, "road": 0, "bridge road": 0}
for i, r in enumerate(rivers):
    for end in (False, True):
        if river_end_ok(i, end):
            continue
        pts = r["points"]
        p = pts[-1] if end else pts[0]
        h = heading(pts, end)
        options = []
        # another river piece's end, carrying on the same way
        for k, o in enumerate(rivers):
            if k == i:
                continue
            for oend in (False, True):
                q = o["points"][-1] if oend else o["points"][0]
                d = math.dist(p, q)
                if 0 < d <= 35:
                    gap = [(q[0] - p[0]) / d, (q[1] - p[1]) / d]
                    if angle(h, gap) < 70:
                        options.append((d, "joined to the next river piece", q))
            d, c, _ = near_on_line(p, o["points"])
            if d <= 40:
                gap = [(c[0] - p[0]) / (d or 1), (c[1] - p[1]) / (d or 1)]
                if d < 4 or angle(h, gap) < 80:
                    options.append((d + 3, "run into the river it feeds", c))
        for lake in LAKES:
            d, c, _ = near_on_line(p, lake, True)
            if d <= 45:
                options.append((d, "run into the lake", push_inside(lake, c, 3)))
        hit = ray_to_edge(p, h)
        if hit and hit[0] <= 260 and not any(inside(g, [p[0] + h[0] * t, p[1] + h[1] * t]) for g in GROUNDS for t in range(5, int(hit[0]), 10)):
            options.append((hit[0] * 0.6 + 10, "carried on to the edge of the map", hit[1]))
        if not options:
            report.append(f"river {i} ({r1(p)}): loose end, nothing near")
            continue
        d, why, q = min(options, key=lambda o: o[0])
        if end:
            pts.append(r1(q))
        else:
            pts.insert(0, r1(q))
        fixed["river"] += 1
        report.append(f"river {i}: end at {r1(p)} {why} ({d:.0f} m)")

# ---- roads ----
roads = plan.get("roads", [])
bridge_ends = [e for br in plan.get("bridges", []) for e in (br["a"], br["b"])]
landmark_spots = [[l["x"], l["z"]] for l in plan.get("landmarks", [])]
outside_houses = [[h["x"], h["z"]] for h in plan.get("houses", []) if not any(inside(g, [h["x"], h["z"]]) for g in GROUNDS)]


def road_end_ok(i, p):
    if edge_dist(p) <= 3:
        return "edge"
    if any(inside(g, p) for g in GROUNDS):
        return "town ground"
    if any(math.dist(p, e) <= 3 for e in bridge_ends):
        return "bridge"
    for k, o in enumerate(roads):
        if k != i and near_on_line(p, o["points"])[0] <= max(1.0, o["width"] / 2):
            return "road"
    return None


for i, r in enumerate(roads):
    for end in (False, True):
        pts = r["points"]
        p = pts[-1] if end else pts[0]
        if road_end_ok(i, p):
            continue
        h = heading(pts, end)
        options = []
        for e in bridge_ends:
            d = math.dist(p, e)
            if d <= 35:
                options.append((d * 0.7, "taken onto the bridge", e))
        for g in GROUNDS:
            d, c, _ = near_on_line(p, g, True)
            if d <= 45:
                options.append((d, "taken into the town ground", push_inside(g, c, 2)))
        for k, o in enumerate(roads):
            if k == i:
                continue
            for oend in (False, True):
                q = o["points"][-1] if oend else o["points"][0]
                d = math.dist(p, q)
                gap = [(q[0] - p[0]) / (d or 1), (q[1] - p[1]) / (d or 1)]
                if 0 < d <= 35 or (d <= 60 and angle(h, gap) < 35):
                    options.append((d * 0.8, "joined to the next road piece", q))
            d, c, _ = near_on_line(p, o["points"])
            if d <= 40:
                options.append((d, "joined to the road beside it", c))
        hit = ray_to_edge(p, h)
        if hit and hit[0] <= 70:
            options.append((hit[0], "carried on to the edge of the map", hit[1]))
        options = [o for o in sorted(options, key=lambda o: o[0]) if not wet_crossing(p, o[2])]
        if not options:
            near_place = min([math.dist(p, q) for q in landmark_spots + outside_houses] or [1e9])
            report.append(f"road {i} ({r1(p)}): stops by itself" + (f" at a building {near_place:.0f} m away (fine)" if near_place < 30 else " - look at it"))
            continue
        d, why, q = options[0]
        if end:
            pts.append(r1(q))
        else:
            pts.insert(0, r1(q))
        fixed["road"] += 1
        report.append(f"road {i}: end at {r1(p)} {why} ({d:.0f} m)")

# ---- bridges: a road at both ends ----
for b, br in enumerate(plan.get("bridges", [])):
    for key in ("a", "b"):
        p = br[key]
        if any(inside(g, p) for g in GROUNDS):
            continue
        if any(near_on_line(p, o["points"])[0] <= max(2.5, o["width"] / 2 + 1) for o in roads):
            continue
        other = br["b" if key == "a" else "a"]
        out = [p[0] - other[0], p[1] - other[1]]; n = math.hypot(*out) or 1; out = [out[0] / n, out[1] / n]
        options = []
        for g in GROUNDS:
            d, c, _ = near_on_line(p, g, True)
            if d <= 45:
                options.append((d, push_inside(g, c, 2)))
        for o in roads:
            d, c, _ = near_on_line(p, o["points"])
            if d <= 45:
                options.append((d, c))
        options = [o for o in sorted(options, key=lambda o: o[0]) if not wet_crossing(p, o[1])]
        if options:
            roads.append({"type": "dirt", "width": 3.0, "points": [r1(p), r1(options[0][1])]})
            fixed["bridge road"] += 1
            report.append(f"bridge {b}: road laid from its {key} end ({options[0][0]:.0f} m)")
        else:
            report.append(f"bridge {b}: nothing to meet at its {key} end ({r1(p)}) - look at it")

# ---- railway: pieces meet at their junction; open ends run on to the map's edge (where the track
# leaves for the rest of Equestria, or into its tunnel) ----
rails = plan.get("railways", [])
for i, r in enumerate(rails):
    for end in (False, True):
        pts = r["points"]
        p = pts[-1] if end else pts[0]
        if edge_dist(p) <= 3:
            continue
        others = []
        for k, o in enumerate(rails):
            if k == i:
                continue
            d, c, _ = near_on_line(p, o["points"])
            if d <= 15:
                others.append((d, c))
        if others:
            d, c = min(others, key=lambda o: o[0])
            if d > 0.5:
                (pts.append if end else (lambda q: pts.insert(0, q)))(r1(c))
                report.append(f"railway {i}: joined to the other track at its junction ({d:.0f} m)")
            continue
        hit = ray_to_edge(p, heading(pts, end))
        if hit and hit[0] <= 160:
            (pts.append if end else (lambda q: pts.insert(0, q)))(r1(hit[1]))
            fixed["railway"] = fixed.get("railway", 0) + 1
            report.append(f"railway {i}: end at {r1(p)} carried on to the edge of the map ({hit[0]:.0f} m)")
        else:
            report.append(f"railway {i} ({r1(p)}): loose end - look at it")

# ---- where the plan's railway meets the game's network (read off the official map: the line to the
# Equestrian Heartlands leaves to the north-west, the two south-western tracks go into tunnels) ----
LINKS = [((-300, -360), "The Meadowline to Heartland, Canterlot and Saddle Lake: new track outside the map from here round to "
          "Junction 5 (216, -611); the old Ponyville - Junction 5 track (seg0) across the north of the map is taken up"),
         ((-300, -97), "The Frontier Loop to Ghastly Gorge: tunnel portal; meets the existing track (seg17) where it leaves the map near (-306, -114)"),
         ((-300, 78), "Second tunnel on the map: no line goes this way yet, a siding into the hill for now")]
ends = [(r["points"][k], i, k) for i, r in enumerate(rails) for k in (0, -1) if edge_dist(r["points"][k]) <= 3]
links = []
# the map's three track ends all leave by its west edge: north to south they are the line to the
# Heartlands, the Ghastly Gorge tunnel and the second tunnel
west_ends = sorted([e for e in ends if e[0][0] < (min(p[0] for p in EDGE) + 5 if EDGE else 0)], key=lambda e: e[0][1])
if len(west_ends) == len(LINKS):
    for (p, i, k), (_, text) in zip(west_ends, LINKS):
        links.append({"at": r1(p), "railway": i, "joins": text})
else:
    for at, text in LINKS:
        if ends:
            p, i, k = min(ends, key=lambda e: math.dist(e[0], at))
            if math.dist(p, at) < 60:
                links.append({"at": r1(p), "railway": i, "joins": text})
plan["rail_links"] = links
station = next((l for l in plan.get("landmarks", []) if l["id"] == "trainstation_01"), None)
if station and rails:
    d = min(near_on_line([station["x"], station["z"]], r["points"])[0] for r in rails)
    report.append(f"station: {d:.0f} m from the track (its platform is built beside the track)")

# ---- what is still loose ----
loose = []
for i, r in enumerate(rivers):
    for end in (False, True):
        if not river_end_ok(i, end):
            loose.append(f"river {i} end {r1(r['points'][-1] if end else r['points'][0])}")
for i, r in enumerate(roads):
    for p in (r["points"][0], r["points"][-1]):
        if not road_end_ok(i, p):
            loose.append(f"road {i} end {r1(p)}")
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
print("\n".join(report))
print("fixed", fixed, "| still loose:", len(loose))
for x in loose:
    print("  ", x)
