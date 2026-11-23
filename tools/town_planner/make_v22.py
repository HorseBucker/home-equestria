"""Plan V22 (2026-11-21 play test, batch 2): from V21 at each density.

- Houses as HorseBucker moved them in V20 (at every density that has them): the C background house at (-21.4, -138.8)
  off the road, the E house at (88.1, -136.9) toward Mayor Mare's, and Mayor Mare's own.
- Low: the B at (-26.8, -117.2) a background house (as on medium; low had one real home over its target).
- Small hills between the buildings at every density, never on a street, square, door path, dirt road or house's
  ground. Built from high down: each density keeps every hill of the one above and adds more where it has fewer
  houses ("work your way down from high, only adding more as you go"). V19's own rises at the lower densities
  (greens with seed 300+, drawn over streets) are replaced by these.
  Each hill is a green with "rise": its outline an organic shape cut back from all of the above, so neither its
  rise (elevation.py) nor its grass paint (apply_paint.py) reaches a road.

usage: python tools/town_planner/make_v22.py
"""
import copy, json, math, os, subprocess, sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = ["high", "medium", "low", "minimum"]
NEW_HILLS = {"high": 8, "medium": 6, "low": 6, "minimum": 8}
MOVED = [(-21.37, -138.83), (88.07, -136.88), (90.72, -148.74)]     # V19 spots of the houses moved in V20
LOW_BACKGROUND = (-26.78, -117.23)
RES = 0.5
X0, X1, Z0, Z1 = -320.0, 520.0, -600.0, 200.0
NX, NZ = int((X1 - X0) / RES), int((Z1 - Z0) / RES)
tj = open(os.path.join(HERE, "data", "town.js"), encoding="utf-8").read()
DESIGNS = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])["designs"]
SCEN = {e["id"]: e for e in json.load(open(os.path.join(HERE, "..", "..", "world/props/ponyville/rnl_scenery.json"), encoding="utf-8"))["entries"]}

v20 = json.load(open(os.path.join(HERE, "ponyville_planV20_high.json"), encoding="utf-8"))
v19h = json.load(open(os.path.join(HERE, "ponyville_planV19_high.json"), encoding="utf-8"))
moved_to = {}
for spot in MOVED:
    old = next(h for h in v19h["houses"] if math.dist((h["x"], h["z"]), spot) < 0.1)
    new = min((h for h in v20["houses"] if h["design"] == old["design"]), key=lambda h: math.dist((h["x"], h["z"]), spot))
    moved_to[spot] = (new["x"], new["z"], new["yaw"])


def px(points):
    return np.round((np.array(points, np.float64) - [X0, Z0]) / RES * 8).astype(np.int32)


def poly(mask, pts, value=1):
    if len(pts) >= 3:
        cv2.fillPoly(mask, [px(pts)], value, shift=3)


def line(mask, pts, width, value=1):
    if len(pts) >= 2:
        cv2.polylines(mask, [px(pts)], False, value, max(1, int(round(width / RES))), shift=3)


def disc(mask, x, z, r, value=1):
    cv2.circle(mask, tuple(px([[x, z]])[0]), int(round(r / RES * 8)), value, -1, shift=3)


def turn(p, y):
    c, s = math.cos(y), math.sin(y)
    return [p[0] * c + p[1] * s, -p[0] * s + p[1] * c]


def blocked_for(plan, greens=True):
    """Where no hill may reach: houses' ground (as elevation.py keeps it), landmarks, streets, squares, door paths,
    dirt roads, bridges, railways, water and its banks, fields, wells, and the greens that already rise."""
    m = np.zeros((NZ, NX), np.uint8)
    town = np.zeros((NZ, NX), np.uint8)
    for g in plan.get("grounds", []):
        poly(town, g["points"])
    for r in plan["roads"]:
        if r.get("type", "town") == "town":
            line(town, r["points"], r["width"] + 1.0)
    m |= cv2.dilate(town, np.ones((7, 7), np.uint8))                     # 1.5 m clear of the town's paint
    for r in plan["roads"] + plan.get("bridges", []):
        pts = r.get("points") or ([r["a"], r["b"]] if "a" in r else [])
        line(m, pts, float(r.get("width", 4)) + 3.0)
    for r in plan.get("railways", []):
        if r.get("name") != "bunting" and not r.get("outside"):
            line(m, r["points"], 8.0)
    ty, tx = np.nonzero(town)
    tpts = np.stack([tx * RES + X0, ty * RES + Z0], 1)
    for h in plan["houses"]:
        d = DESIGNS[h["design"]]; k = h.get("scale") or d["scale"]
        reach = max(math.hypot(q[0] * k, q[1] * k) for q in d["footprint"])
        disc(m, h["x"], h["z"], reach + 2.5)
        if len(h["design"]) == 1 and "door" in d and len(tpts):
            # its door path (apply_paint.py: door to the nearest town ground, within 9 m), 1.5 m clear
            q = turn([d["door"][0] * k, d["door"][1] * k], h["yaw"]); door = (h["x"] + q[0], h["z"] + q[1])
            j = int(np.argmin(np.hypot(tpts[:, 0] - door[0], tpts[:, 1] - door[1])))
            if math.dist(door, tpts[j]) <= 9.0:
                line(m, [list(door), list(tpts[j])], 5.0)
    for l in plan["landmarks"]:
        # its whole footprint and 3 m round it (8 m from its middle let a hill under the Golden Oak's roots)
        e = SCEN.get(l["id"])
        reach = max(math.dist(q, (e["position"][0], e["position"][2])) for q in e["footprint"]) if e and e.get("footprint") else 5.0
        disc(m, l["x"], l["z"], max(8.0, reach + 3.0))
    water = np.zeros((NZ, NX), np.uint8)
    for lk in plan.get("lakes", []):
        poly(water, lk["points"])
    for rv in plan.get("rivers", []):
        line(water, rv["points"], float(rv.get("width", 4)))
    m |= cv2.dilate(water, np.ones((int(8 / RES) + 1,) * 2, np.uint8))  # 4 m off the banks
    for f in plan.get("fields", []):
        poly(m, f["points"])
    for a in plan.get("anchors", []):                                      # the painting easel's spot: 8 m
        disc(m, a["x"], a["z"], 8.0)
    for w in plan.get("wells", []):
        disc(m, w[0], w[1], 4.0)
    for g in (plan.get("greens", []) if greens else []):
        if float(g.get("rise", 0) or 0) > 0:
            gm = np.zeros((NZ, NX), np.uint8); poly(gm, g["points"])
            m |= cv2.dilate(gm, np.ones((9, 9), np.uint8))               # 2 m apart from a rise already there
    village = np.zeros((NZ, NX), np.uint8)
    for r in plan["roads"]:
        if r.get("type", "town") == "town":
            line(village, r["points"], r["width"] + 40.0)                  # between the buildings: near the streets
    return m.astype(bool), village.astype(bool)


def blob(cx, cz, radius, turn_, rng):
    pts = []
    a1, a2 = rng.uniform(0, 6.3, 2)
    for i in range(32):
        a = math.tau * i / 32
        r = radius * (1 + 0.16 * math.cos(2 * a + a1) + 0.09 * math.cos(3 * a + a2))
        x, z = r * math.cos(a), r * math.sin(a)
        c, s = math.cos(turn_), math.sin(turn_)
        pts.append([cx + x * c - z * s, cz + x * s + z * c])
    return pts


def add_hills(plan, count, seed):
    """`count` new hills in the widest open ground between the buildings, each cut back from everything in the way."""
    rng = np.random.default_rng(seed)
    blocked, village = blocked_for(plan)
    free = (village & ~blocked).astype(np.uint8)
    made = []
    for _ in range(count * 4):
        if len(made) >= count:
            break
        dist = cv2.distanceTransform(free, cv2.DIST_L2, 5) * RES
        r_, c_ = np.unravel_index(int(np.argmax(dist)), dist.shape)
        room = float(dist[r_, c_])
        if room < 4.0:
            break
        cx, cz = c_ * RES + X0, r_ * RES + Z0
        radius = min(room + 3.0, float(rng.uniform(7.0, 12.0)))
        shape = np.zeros((NZ, NX), np.uint8)
        poly(shape, blob(cx, cz, radius, float(rng.uniform(0, math.tau)), rng))
        shape &= free
        n, lab, stats, _ = cv2.connectedComponentsWithStats(shape)
        if n < 2:
            disc(free, cx, cz, room, 0); continue
        keep = (lab == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))).astype(np.uint8)
        keep = cv2.erode(keep, np.ones((3, 3), np.uint8))                 # a hair inside: off the paint's edge
        contours, _ = cv2.findContours(keep, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            disc(free, cx, cz, room, 0); continue
        c = max(contours, key=cv2.contourArea)
        c = cv2.approxPolyDP(c, 1.2, True)
        if cv2.contourArea(c) * RES * RES < 40 or len(c) < 4:
            disc(free, cx, cz, room, 0); continue
        pts = [[round(float(p[0][0]) * RES + X0, 2), round(float(p[0][1]) * RES + Z0, 2)] for p in c]
        area = cv2.contourArea(c) * RES * RES
        rise = round(float(np.clip((0.45 + math.sqrt(area) / 16.0) * rng.uniform(0.75, 1.25), 0.6, 1.8)), 1)
        made.append({"points": pts, "rise": rise, "seed": seed * 100 + len(made), "hill": "V22"})
        # nothing else this close: a hill's own ground and 6 m round it
        grown = cv2.dilate(keep, np.ones((int(12 / RES) + 1,) * 2, np.uint8))
        free &= (1 - grown).astype(np.uint8)
    return made


plans = {s: json.load(open(os.path.join(HERE, f"ponyville_planV21_{s}.json"), encoding="utf-8")) for s in SETTINGS}
hills = []
for s in SETTINGS:
    plan = plans[s]
    for h in plan["houses"]:
        for spot, (x, z, yaw) in moved_to.items():
            if math.dist((h["x"], h["z"]), spot) < 0.1:
                h["x"], h["z"], h["yaw"] = x, z, yaw
        if s == "low" and math.dist((h["x"], h["z"]), LOW_BACKGROUND) < 0.1:
            h["filler"] = True; h.pop("vacant", None); h.pop("residents", None); h["name"] = ""
    plan["greens"] = [g for g in plan["greens"] if int(g.get("seed", 0)) < 300]
    plan["greens"] += copy.deepcopy(hills)                                # every hill of the density above
    new = add_hills(plan, NEW_HILLS[s], {"high": 41, "medium": 42, "low": 43, "minimum": 44}[s])
    plan["greens"] += new
    hills += new
    plan["version"] = 22
    plan["built_from"] = f"ponyville_planV21_{s}.json + make_v22.py"
    out = os.path.join(HERE, f"ponyville_planV22_{s}.json")
    json.dump(plan, open(out, "w", encoding="utf-8"), separators=(",", ":"), ensure_ascii=False)
    run = subprocess.run([sys.executable, os.path.join(HERE, "elevation.py"), out], capture_output=True, text=True)
    risen = [l for l in run.stdout.splitlines() if l.startswith("greens risen")]
    print(f"{s:8s} real homes {sum(1 for h in plan['houses'] if not h.get('filler', True))}, new hills {len(new)} "
          f"(all hills of V22 {len(hills)}) at " + ", ".join(f"({np.mean([p[0] for p in g['points']]):.0f}, {np.mean([p[1] for p in g['points']]):.0f})" for g in new),
          "|", risen[0] if risen else run.stderr[-300:])
