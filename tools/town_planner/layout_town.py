"""Lay the town out again from a design: a smaller map, narrower streets, rows of houses facing them.

usage: python tools/town_planner/layout_town.py <source plan.json> <town_design.json> <out.json>

- The whole map (rivers, lakes, landmarks, fields, the edge) shrinks by the design's `factor` about the town's
  middle.
- Landmarks: one the design names stands where it says, its front (door, counter, stage edge) turned `toward` the
  point given; the others keep the source plan's place and turn. `anchors` are spots for things the game sets
  down by its own code (the painting easel).
- Bridges are set square across their river, long enough to reach both banks.
- The design's dirt roads replace the source plan's. Road and street ends near a bridge end are joined to it.
- A river that ran off the map now begins in a spring pool a little inside the edge, with a rise behind it (or,
  where the design says so, ends in a bog); so no river stops at nothing.
- The houses inside the town are set out afresh: along each street, on the sides the design names, a row of
  houses stands `yard` metres back from the street's edge, front doors to the street, roofs 0.6-1.2 m apart,
  designs mixed. Nothing stands in a street, a square, water, a road, the railway or a landmark's way.
- Every real home of the source plan takes the free place nearest to where it stood, with its design, name and
  residents; the other places are background houses. Houses outside the town (the hamlets) only shrink.
- Houses are `house` (background) and `home` (real homes) of the game's size.
- The streets are written as the plan's town streets (roads of type "town"), the squares as its town ground.
"""
import json, math, random, sys
from plan_geometry import TOWN, MODEL, SCEN, shape, gap, line_dist, inside, probes, wet, along, smooth, seg_point, front_of, facing

SRC, DESIGN, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
plan = json.load(open(SRC, encoding="utf-8"))
spec = json.load(open(DESIGN, encoding="utf-8"))
FACTOR, HOUSE, HOME, YARD = spec["factor"], spec.get("house", 0.9), spec.get("home", 0.95), spec.get("yard", 0.9)
ROW_GAP = (0.6, 1.2)
LANDMARK_GAP = 2.5
MIX = {"b": 38, "c": 30, "a": 14, "f": 5, "g": 5, "h": 5, "e": 3}
rng = random.Random(spec.get("seed", 7))
g0 = plan["grounds"][0]["points"]
CX = sum(p[0] for p in g0) / len(g0); CZ = sum(p[1] for p in g0) / len(g0)
report = []


def sp(p):
    return [round(CX + (p[0] - CX) * FACTOR, 2), round(CZ + (p[1] - CZ) * FACTOR, 2)]


def move(item):
    if "x" in item:
        item["x"], item["z"] = sp([item["x"], item["z"]])
    if "points" in item:
        item["points"] = [sp(p) for p in item["points"]]
    for k in ("a", "b", "at"):
        if k in item and isinstance(item[k], list):
            item[k] = sp(item[k])


for kind in ("houses", "landmarks", "roads", "rivers", "lakes", "bridges", "flats", "notes", "edges", "grounds", "greens",
             "railways", "fields", "woods", "rail_links"):
    for item in plan.get(kind, []):
        move(item)
plan["railways"] = [r for r in plan.get("railways", []) if not r.get("outside")]
plan.pop("rail_network", None)
for r in plan.get("rivers", []):
    r["width"] = round(max(2.5, r["width"] * FACTOR), 1)
ref = plan["reference"]
ref["x"], ref["z"] = sp([ref["x"], ref["z"]]); ref["width"] = round(ref["width"] * FACTOR, 1)
terrain = plan.get("terrain", {})
for k in ("origin", "step", "columns", "rows", "low", "high", "heights"):
    terrain.pop(k, None)
for m in terrain.get("mounds", []):
    m["x"], m["z"] = sp([m["x"], m["z"]]); m["radius"] = round(m["radius"] * FACTOR, 1); m["top"] = round(m["top"] * FACTOR, 1)

# ---- landmarks and anchors ----
by_id = {l["id"]: l for l in plan["landmarks"]}
for d in spec.get("landmarks", []):
    l = by_id.get(d["id"])
    if l is None:
        if d["id"] not in SCEN:
            report.append(f"no such scenery: {d['id']}"); continue
        l = {"id": d["id"], "x": d["x"], "z": d["z"], "yaw": SCEN[d["id"]]["yaw"]}
        plan["landmarks"].append(l); by_id[d["id"]] = l
    if "x" in d:
        l["x"], l["z"] = d["x"], d["z"]
    if "toward" in d:
        l["yaw"] = round(facing(d["toward"][0] - l["x"], d["toward"][1] - l["z"]) - front_of(l["id"]), 4)
    elif "yaw" in d:
        l["yaw"] = d["yaw"]
plan["anchors"] = []
for a in spec.get("anchors", []):
    plan["anchors"].append({"id": a["id"], "label": a.get("label", a["id"]), "x": a["x"], "z": a["z"],
                            "yaw": round(facing(a["toward"][0] - a["x"], a["toward"][1] - a["z"]), 4) if "toward" in a else a.get("yaw", 0.0)})

# ---- springs: no river runs off the map ----
edge = plan["edges"][0]["points"]
EX0, EX1 = min(p[0] for p in edge), max(p[0] for p in edge); EZ0, EZ1 = min(p[1] for p in edge), max(p[1] for p in edge)


def edge_dist(p):
    return min(p[0] - EX0, EX1 - p[0], p[1] - EZ0, EZ1 - p[1])


def blob(c, rx, rz, turn_, n=14):
    pts = []
    for i in range(n):
        a = math.tau * i / n
        w = 1 + 0.12 * math.sin(3 * a + c[0]) + 0.07 * math.sin(5 * a + c[1])
        x, z = math.cos(a) * rx * w, math.sin(a) * rz * w
        pts.append([round(c[0] + x * math.cos(turn_) - z * math.sin(turn_), 2), round(c[1] + x * math.sin(turn_) + z * math.cos(turn_), 2)])
    return pts


springs = spec.get("springs", {})
for r in plan["rivers"]:
    for end in (0, -1):
        pts = r["points"] if end == 0 else r["points"][::-1]
        if edge_dist(pts[0]) > 12:
            continue
        cfg = min(springs.get("named", []), key=lambda c: math.dist(c["near"], pts[0]), default=None)
        if cfg is None or math.dist(cfg["near"], pts[0]) > 70:
            cfg = {"name": "Spring"}
        inset = cfg.get("inset", springs.get("inset", 30))
        k = 0
        while k < len(pts) - 1 and edge_dist(pts[k + 1]) < inset:
            k += 1
        if k >= len(pts) - 2:
            report.append(f"river end near {pts[0]} left alone: the whole river is near the edge"); continue
        a, b = pts[k], pts[k + 1]                         # a is nearer the edge than `inset`, b is not
        da, db = edge_dist(a), edge_dist(b)
        t = (inset - da) / ((db - da) or 1)
        E = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
        L = math.dist(a, b) or 1
        out = [(a[0] - b[0]) / L, (a[1] - b[1]) / L]      # toward the edge
        if cfg.get("kind") == "bog":
            rx, rz = cfg.get("rx", 28), cfg.get("rz", 18)
            C = [round(E[0] + out[0] * rx * 0.7, 2), round(E[1] + out[1] * rx * 0.7, 2)]
            plan["lakes"].append({"name": cfg["name"], "bog": True, "points": blob(C, rx, rz, math.atan2(out[1], out[0]), 18)})
        else:
            rad = cfg.get("radius", springs.get("radius", 6.5))
            C = [round(E[0] + out[0] * rad * 0.6, 2), round(E[1] + out[1] * rad * 0.6, 2)]
            plan["lakes"].append({"name": cfg["name"], "spring": True, "points": blob(C, rad, rad * 0.85, math.atan2(out[1], out[0]))})
            terrain.setdefault("mounds", []).append({"x": round(C[0] + out[0] * (rad + 13), 1), "z": round(C[1] + out[1] * (rad + 13), 1),
                                                    "top": 6.0, "radius": 30.0, "height": 4.5, "name": cfg["name"] + " rise"})
        plan.setdefault("notes", []).append({"x": C[0], "z": C[1], "text": cfg["name"]})
        new = [C, [round(E[0], 2), round(E[1], 2)]] + pts[k + 1:]
        r["points"] = new if end == 0 else new[::-1]
        report.append(f"river end at the edge near ({pts[0][0]:.0f}, {pts[0][1]:.0f}) -> {cfg['name']} at ({C[0]:.0f}, {C[1]:.0f})")

# ---- bridges square across their rivers ----
for b in plan.get("bridges", []):
    mid = [(b["a"][0] + b["b"][0]) / 2, (b["a"][1] + b["b"][1]) / 2]
    r = min(plan["rivers"], key=lambda r: line_dist(mid, r["points"]))
    best = min(((seg_point(mid, r["points"][i], r["points"][i + 1]), i) for i in range(len(r["points"]) - 1)), key=lambda v: v[0][0])
    (d, q), i = best
    if d > 12:
        report.append(f"bridge at ({mid[0]:.0f}, {mid[1]:.0f}) is not over a river; left as it was"); continue
    # the river's direction here: over 10 m either side, so a kink in the traced line does not set the bridge askew
    line = along(r["points"], 1.0)
    near = sorted(line, key=lambda p: math.dist(p[:2], q))[0]
    span = [p for p in line if abs(p[4] - near[4]) <= 10.0]
    tx, tz = span[-1][0] - span[0][0], span[-1][1] - span[0][1]; L = math.hypot(tx, tz) or 1; tx, tz = tx / L, tz / L
    n = [tz, -tx]
    if n[0] * (b["b"][0] - b["a"][0]) + n[1] * (b["b"][1] - b["a"][1]) < 0:
        n = [-n[0], -n[1]]
    old = math.atan2(b["b"][0] - b["a"][0], b["b"][1] - b["a"][1])
    wide = b.get("width", 3) >= 7
    hl = r["width"] / 2 + 2.4
    b["a"] = [round(q[0] - n[0] * hl, 2), round(q[1] - n[1] * hl, 2)]; b["b"] = [round(q[0] + n[0] * hl, 2), round(q[1] + n[1] * hl, 2)]
    b["width"] = 5.5 if wide else 3.6
    turned = math.degrees((math.atan2(n[0], n[1]) - old + math.pi) % math.tau - math.pi)
    report.append(f"bridge at ({q[0]:.0f}, {q[1]:.0f}): turned {turned:+.0f} degrees, {2 * hl:.1f} m long")

streets = spec["streets"]
roads = spec.get("roads", [])
ends = [(b[k], [b[k][0] - (b["a"][0] + b["b"][0]) / 2, b[k][1] - (b["a"][1] + b["b"][1]) / 2]) for b in plan.get("bridges", []) for k in ("a", "b")]
for way in streets + roads:
    for idx in (0, -1):
        p = way["points"][idx]
        e = min(ends, key=lambda e: math.dist(e[0], p), default=None)
        if e and math.dist(e[0], p) < 14:
            L = math.hypot(*e[1]) or 1
            way["points"][idx] = [round(e[0][0] - e[1][0] / L * 0.4, 2), round(e[0][1] - e[1][1] / L * 0.4, 2)]
for s in streets:
    s["line"] = smooth([list(p) for p in s["points"]], 2)
for r in roads:
    r["type"] = "dirt"; r["points"] = [[round(p[0], 2), round(p[1], 2)] for p in smooth([list(p) for p in r["points"]], 2)]
squares = spec.get("squares", [])
reserved = spec.get("reserved", [])
old_ground = plan["grounds"][0]["points"]


def in_town(h):
    p = [h["x"], h["z"]]
    return inside(old_ground, p) or min(line_dist(p, s["line"]) for s in streets) < 16


def sized(h):
    if len(h["design"]) == 1:
        h["scale"] = round(TOWN["designs"][h["design"]]["scale"] * (HOUSE if h.get("filler") else HOME), 4)
    else:
        h.pop("scale", None)
    return h


fixed_houses = [h for h in plan["houses"] if len(h["design"]) > 1]
old_town = [h for h in plan["houses"] if len(h["design"]) == 1 and in_town(h)]
outlying = [sized(h) for h in plan["houses"] if len(h["design"]) == 1 and not in_town(h)]
fixed = [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"] + fixed_houses
fixed_shapes = [shape(f) for f in fixed]
placed = []          # [(house, outline)]


def clear(h, pts, ignore=None, own=None, row_gap=ROW_GAP[0]):
    """Can this outline stand here?"""
    pr = probes(pts)
    cx, cz = pr[-1]
    for s in streets:
        need = s["width"] / 2 + (0.15 if s is own else 0.5)
        if any(line_dist(p, s["line"]) < need for p in pr):
            return False
    for sq in squares:
        if any(inside(sq["points"], p) for p in pr):
            return False
    for c in reserved:
        if any(math.dist(p, (c["x"], c["z"])) < c["radius"] for p in pr):
            return False
    for a in plan["anchors"]:
        if any(math.dist(p, (a["x"], a["z"])) < 3.0 for p in pr):
            return False
    for k, f in enumerate(fixed):
        if abs(f["x"] - cx) < 45 and abs(f["z"] - cz) < 45 and gap(pts, fixed_shapes[k]) < LANDMARK_GAP:
            return False
    for o, osh in placed:
        if o is ignore or o is h or abs(o["x"] - cx) > 22 or abs(o["z"] - cz) > 22:
            continue
        if gap(pts, osh) < row_gap:
            return False
    if wet(plan, pts, 1.5) > 0:
        return False
    for r in roads:
        if any(line_dist(p, r["points"]) < r.get("width", 2.5) / 2 + 0.8 for p in pr):
            return False
    for r in plan.get("railways", []):
        if any(line_dist(p, r["points"]) < 4.0 for p in pr):
            return False
    for b in plan.get("bridges", []):
        if any(seg_point(p, b["a"], b["b"])[0] < b.get("width", 3) / 2 + 2.0 for p in pr):
            return False
    return True


lost = []
for h in outlying:
    sh = shape(h)
    if clear(h, sh):
        placed.append((h, sh))
    else:
        # a house outside the town steps aside to the nearest clear spot (roads and bridges have moved a little)
        done = False
        for ring in range(1, 16):
            for k in range(12):
                a = math.tau * k / 12
                t = dict(h, x=h["x"] + math.cos(a) * ring * 1.5, z=h["z"] + math.sin(a) * ring * 1.5)
                if clear(t, shape(t)):
                    h["x"], h["z"] = t["x"], t["z"]; placed.append((h, shape(h))); done = True; break
            if done:
                break
        if not done and h.get("filler"):
            lost.append(h)
        elif not done:
            placed.append((h, sh)); report.append(f"real home outside the town could not be cleared: {h.get('name') or h['design']}")
outlying = [h for h in outlying if not any(h is x for x in lost)]


def stand(design, scale, front, out):
    """A house of this design with the middle of its front roof edge at `front`, its back toward `out`."""
    z1 = MODEL[design][3] * scale
    return {"design": design, "filler": True, "x": front[0] + out[0] * z1, "z": front[1] + out[1] * z1,
            "yaw": math.atan2(-out[0], -out[1]), "scale": round(scale, 4)}


def pick():
    r = rng.uniform(0, sum(MIX.values()))
    for d, w in MIX.items():
        r -= w
        if r <= 0:
            return d
    return "b"


slots = []           # [(house, front, out, street)]
for s in streets:
    sides = s.get("sides", "both")
    if sides == "none":
        continue
    pts = along(s["line"], 0.5)
    for side in ([1, -1] if sides == "both" else [1] if sides == "left" else [-1]):
        i = 0
        design = pick()
        while i < len(pts):
            scale = TOWN["designs"][design]["scale"] * HOUSE
            w = (MODEL[design][1] - MODEL[design][0]) * scale
            j = i + int(round(w / 2 / 0.5))
            k = i + int(round(w / 0.5))
            if k >= len(pts):
                break
            x, z, tx, tz, _ = pts[j]
            out = (tz * side, -tx * side)                 # away from the street on this side
            front = (x + out[0] * (s["width"] / 2 + YARD), z + out[1] * (s["width"] / 2 + YARD))
            h = stand(design, scale, front, out)
            sh = shape(h)
            if clear(h, sh, own=s):
                placed.append((h, sh)); slots.append((h, front, out, s))
                i = k + int(round(rng.uniform(*ROW_GAP) / 0.5))
                design = pick()
            else:
                i += 1

# ---- the real homes take the nearest places ----
homes = [h for h in old_town if not h.get("filler")]
homes.sort(key=lambda h: (not h.get("name"), -(MODEL[h["design"]][1] - MODEL[h["design"]][0])))
taken = set()
moved_far = []


def settle(home, n, blockers=()):
    old, front, out, s = slots[n]
    h = stand(home["design"], TOWN["designs"][home["design"]]["scale"] * HOME, front, out)
    sh = shape(h)
    global placed
    keep = placed
    placed = [(o, osh) for o, osh in placed if not any(o is b for b in blockers)]
    if not clear(h, sh, ignore=old, own=s, row_gap=0.45):
        placed = keep
        return False
    for key in ("name", "residents"):
        if key in home:
            h[key] = home[key]
    h["filler"] = False
    idx = next(i for i, (o, _) in enumerate(placed) if o is old)
    placed[idx] = (h, sh); slots[n] = (h, front, out, s); taken.add(n)
    for i, sl in enumerate(slots):
        if any(sl[0] is b for b in blockers):
            taken.add(i)
    d = math.dist(front, (home["x"], home["z"]))
    if d > 30:
        moved_far.append((home.get("name") or "vacant " + home["design"], round(d)))
    return True


for home in homes:
    order = [n for n in sorted(range(len(slots)), key=lambda n: math.dist(slots[n][1], (home["x"], home["z"]))) if n not in taken]
    done = any(settle(home, n) for n in order[:25])
    if not done:
        # make room: the nearest place takes its background neighbours' ground too
        for n in order[:8]:
            old, front, out, s = slots[n]
            h = stand(home["design"], TOWN["designs"][home["design"]]["scale"] * HOME, front, out)
            sh = shape(h)
            blockers = [o for o, osh in placed if o is not old and o.get("filler") and abs(o["x"] - h["x"]) < 22 and abs(o["z"] - h["z"]) < 22 and gap(sh, osh) < 0.45]
            if settle(home, n, blockers):
                done = True; break
    if not done:
        report.append(f"NO PLACE for {home.get('name') or 'vacant ' + home['design']}")

town_houses = [o for o, _ in placed if not any(o is h for h in outlying)]
plan["houses"] = fixed_houses + [h for h in town_houses if not h.get("filler")] + [h for h in outlying if not h.get("filler")] + \
    [h for h in town_houses if h.get("filler")] + [h for h in outlying if h.get("filler")]
for h in plan["houses"]:
    h["x"], h["z"], h["yaw"] = round(h["x"], 2), round(h["z"], 2), round(h["yaw"], 4)
plan["roads"] = [{"type": "dirt", "name": r["name"], "width": r["width"], "points": r["points"]} for r in roads] + \
    [{"type": "town", "name": s["name"], "width": s["width"], "points": [[round(p[0], 2), round(p[1], 2)] for p in s["line"]]} for s in streets]
plan["grounds"] = [{"name": p["name"], "points": p["points"]} for p in squares]
plan["greens"] = []
plan["design"] = {"from": "tools/town_planner/town_design.json", "factor": FACTOR, "house": HOUSE, "home": HOME}
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
real = [h for h in plan["houses"] if not h.get("filler")]
for line in report:
    print(" ", line)
print(f"map {ref['width']:.0f} m wide; {len(streets)} streets, {sum(math.dist(s['line'][i], s['line'][i + 1]) for s in streets for i in range(len(s['line']) - 1)):.0f} m; {len(roads)} dirt roads")
print(f"houses: {len(plan['houses'])} ({len(real)} real homes, {len(plan['houses']) - len(real)} background; {len(outlying)} outside the town, "
      f"{len(lost)} background houses outside the town left out); source plan had {len(old_town) + len(outlying) + len(lost) + len(fixed_houses)}")
if moved_far:
    print("real homes that moved more than 30 m:", moved_far)
