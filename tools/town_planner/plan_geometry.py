"""Shared geometry for the plan tools: building outlines (roofs, porches and steps included), gaps, water."""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
_tj = open(os.path.join(HERE, "data", "town.js"), encoding="utf-8").read()
TOWN = json.loads(_tj[_tj.index("{"):_tj.rindex("}") + 1])
SCEN = {s["id"]: s for s in TOWN["scenery"]}
# each design's whole model (roof, porch, steps) in model units: x0, x1, z0 (back), z1 (front)
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}


def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def house_scale(h):
    return h.get("scale") or TOWN["designs"][h["design"]]["scale"]


def shape(item):
    """World outline of a house or landmark."""
    if "id" in item:
        s = SCEN[item["id"]]
        local = turn([[p[0] - s["x"], p[1] - s["z"]] for p in s["footprint"]], -s["yaw"])
        return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(local, item["yaw"])]
    k = house_scale(item)
    if item["design"] in MODEL:
        x0, x1, z0, z1 = MODEL[item["design"]]
        pts = [[x0 * k, z0 * k], [x1 * k, z0 * k], [x1 * k, z1 * k], [x0 * k, z1 * k]]
    else:
        pts = [[p[0] * k, p[1] * k] for p in TOWN["designs"][item["design"]]["footprint"]]
    return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(pts, item["yaw"])]


def door(h):
    d = TOWN["designs"][h["design"]]; k = house_scale(h)
    p = turn([[d["door"][0] * k, d["door"][1] * k]], h["yaw"])[0]
    return [h["x"] + p[0], h["z"] + p[1]]


def hull(pts):
    pts = sorted(map(tuple, pts))
    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (p[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(p)
        return out[:-1]
    return [list(p) for p in half(pts) + half(pts[::-1])]


def gap(A, B):
    """Separating-axis distance between two outlines' convex hulls (negative: they overlap)."""
    A, B = (hull(A) if len(A) > 4 else A), (hull(B) if len(B) > 4 else B)
    best = -1e9
    for P in (A, B):
        for i in range(len(P)):
            a, b = P[i], P[(i + 1) % len(P)]
            n = (b[1] - a[1], -(b[0] - a[0])); L = math.hypot(*n) or 1; n = (n[0] / L, n[1] / L)
            pa = [p[0] * n[0] + p[1] * n[1] for p in A]; pb = [p[0] * n[0] + p[1] * n[1] for p in B]
            best = max(best, min(pb) - max(pa), min(pa) - max(pb))
    return best


def seg_point(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / ((dx * dx + dz * dz) or 1)))
    q = [a[0] + t * dx, a[1] + t * dz]
    return math.hypot(q[0] - p[0], q[1] - p[1]), q


def line_dist(p, pts):
    return min(seg_point(p, pts[i], pts[i + 1])[0] for i in range(len(pts) - 1))


def inside(poly, p):
    hit = False; j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
        j = i
    return hit


def probes(pts):
    """Corners, edge middles and the middle of an outline."""
    n = len(pts)
    return pts + [[(pts[i][0] + pts[(i + 1) % n][0]) / 2, (pts[i][1] + pts[(i + 1) % n][1]) / 2] for i in range(n)] + \
        [[sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n]]


def wet(plan, pts, margin=1.5):
    """How far an outline pokes into water or its bank margin (0: clear)."""
    worst = 0.0
    pr = probes(pts)
    cx, cz = pr[-1]
    for r in plan["rivers"]:
        if min(abs(q[0] - cx) + abs(q[1] - cz) for q in r["points"]) > 120:
            continue
        for p in pr:
            worst = max(worst, r["width"] / 2 + margin - line_dist(p, r["points"]))
    for l in plan["lakes"]:
        for p in pr:
            if inside(l["points"], p):
                worst = max(worst, 3.0)
            else:
                worst = max(worst, margin - line_dist(p, l["points"] + l["points"][:1]))
    return worst


def along(pts, step):
    """Points every `step` metres along a line, each with its direction: [(x, z, tx, tz, s)]."""
    out = []; s = 0.0; carry = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        L = math.dist(a, b)
        if L < 1e-6:
            continue
        tx, tz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        d = carry
        while d <= L:
            out.append((a[0] + tx * d, a[1] + tz * d, tx, tz, s + d))
            d += step
        carry = d - L; s += L
    return out


def smooth(pts, rounds=2):
    """Chaikin corner cutting, ends kept."""
    for _ in range(rounds):
        out = [pts[0]]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            out.append([a[0] * .75 + b[0] * .25, a[1] * .75 + b[1] * .25]); out.append([a[0] * .25 + b[0] * .75, a[1] * .25 + b[1] * .75])
        out.append(pts[-1]); pts = out
    return pts


# Which way each landmark model's front (its door, counter or stage edge) points, as a turn from model +z.
# Read off pictures of each model (build/qc/model_shots.gd); the old station's -z side faced the track.
MODEL_FRONT = {"rnl_ponyville_trainstation": math.pi, "rnl_ponyville_burger_joint": math.pi, "rnl_rarityboutique": math.pi,
               "kiosk__rnl_ponyville_kiosk_01": math.pi, "kiosk__rnl_ponyville_kiosk_02": math.pi,
               "furniture__cloudsdale_hotdogstand": math.pi, "rnl_trixie_wagon": math.pi,
               "rnl_schoolhouse_theatre": math.pi / 2, "props_mlpprops__lyrasbench": math.pi / 2,
               "rnl_snazzys_fluttershy_cottage": math.atan2(-0.766, -0.643)}


def front_of(landmark_id):
    s = SCEN.get(landmark_id)
    return MODEL_FRONT.get(s["model"], 0.0) if s else 0.0


def facing(dx, dz):
    """The angle of a direction on the map: 0 south (+z), pi/2 east (+x), pi north, -pi/2 west."""
    return math.atan2(dx, dz)


# ---- the lean of the background houses (the show draws Ponyville's houses a little askew) ----
# where a bunting line can be tied to each design: the heart on design c's roof ridge (model units), else the roof's top
ROOF_TIE = {"c": (0.275, 0.93, -0.098)}
HOUSE_TOP = {"a": 0.95, "b": 0.95, "c": 0.97, "d": 0.95, "e": 0.9, "f": 0.9, "g": 0.95, "h": 0.95}


def house_leans(plan):
    """For each of the plan's houses, how its walls lean: (lx, lz), the sideways shift per unit of height in the
    house's own space (a shear, so its foot stays where it is and flat). Background houses only; each its own
    amount and direction (0.7 to 2.6 degrees), the same every run; never more than would carry its roof 45% of
    the way to its nearest neighbour's."""
    import hashlib
    shapes = [shape(h) for h in plan["houses"]]
    others = [shape(l) for l in plan.get("landmarks", []) if l["id"] in SCEN and SCEN[l["id"]].get("footprint")]
    out = []
    for n, h in enumerate(plan["houses"]):
        if not h.get("filler", True) or len(h["design"]) != 1:
            out.append((0.0, 0.0)); continue
        key = hashlib.md5(f"lean {h['x']:.1f},{h['z']:.1f},{h['design']}".encode()).hexdigest()
        amount = 0.012 + int(key[:4], 16) / 65535.0 * 0.033
        angle = int(key[4:8], 16) / 65535.0 * math.tau
        room = min([gap(shapes[n], shapes[m]) for m, o in enumerate(plan["houses"]) if m != n and abs(o["x"] - h["x"]) + abs(o["z"] - h["z"]) < 40]
                   + [gap(shapes[n], s) for s in others if abs(s[0][0] - h["x"]) + abs(s[0][1] - h["z"]) < 60] + [9.0])
        height = HOUSE_TOP.get(h["design"], 0.95) * house_scale(h)
        amount = min(amount, max(0.0, room) * 0.45 / height)
        out.append((round(math.cos(angle) * amount, 4), round(math.sin(angle) * amount, 4)))
    return out
