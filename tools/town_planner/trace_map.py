"""Trace the official Ponyville map (data/reference.jpg) into a planner plan.

usage: trace.py <repo root> <out plan json>
Everything is read off the picture by colour: buildings (tan), town ground (sage), water (blue),
bridges (lavender) and dirt roads (pale yellow). R5, R6 and R7 are left out (not in season 2).
"""
import cv2, numpy as np, json, sys, math, random

ROOT, OUT = sys.argv[1], sys.argv[2]
PLANNER = ROOT + "/tools/town_planner"
im = cv2.imread(PLANNER + "/data/reference.jpg")
H, W = im.shape[:2]
REF = {"x": 100, "z": -200, "width": 820, "turn": 0, "opacity": 0.45}
MPP = REF["width"] / W
rgb = im[:, :, ::-1].astype(np.int32)
random.seed(7)

town = open(PLANNER + "/data/town.js", encoding="utf-8").read()
TOWN = json.loads(town[town.index("{"):town.rindex("}") + 1])


def world(px, py):
    return [round(REF["x"] + (px - W / 2) * MPP, 1), round(REF["z"] + (py - H / 2) * MPP, 1)]


def near(c, t):
    return (np.abs(rgb - np.array(c)).sum(2) <= t).astype(np.uint8)


def ell(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def box(x0, y0, x1, y1):
    m = np.zeros((H, W), np.uint8)
    m[y0:y1, x0:x1] = 1
    return m


# ---- places on the picture that are not traced (full-size pixels) ----
SKIP = box(0, 0, 800, 340) | box(0, 1780, 440, H)            # title, compass
R6 = box(930, 150, 1425, 680)                                 # castle grounds (R6) with its moat and gate
R6[560:680, 930:1010] = 0
R7 = box(1440, 300, 1570, 440)
SKIP |= R6 | R7 | box(140, 580, 340, 740)                   # ... and the "Equestrian Heartlands" lettering
MOAT = box(1215, 314, 1342, 570)                              # the castle's inner moat loop
R5 = np.zeros((H, W), np.uint8)
cv2.fillPoly(R5, [cv2.boxPoints(((1183, 849), (175, 62), -17)).astype(np.int32)], 1)

tan = near((231, 203, 155), 45)
road = near((222, 217, 122), 36)
dark = (rgb.sum(2) < 400).astype(np.uint8)
pink = near((240, 190, 200), 40)
sage = near((136, 180, 147), 26)
water = near((50, 143, 181), 50)
causeway = near(tuple(int(v) for v in rgb[690, 1276]), 30)
bridge = near((200, 190, 225), 36)

# ---- buildings: every tan blob as a turned rectangle ----
n, lab, stats, _ = cv2.connectedComponentsWithStats(tan, connectivity=4)
blobs = []
for i in range(1, n):
    x, y, w, h, area = stats[i]
    if area < 40:
        continue
    pts = (np.argwhere(lab[y:y + h, x:x + w] == i)[:, ::-1] + np.array([x, y])).astype(np.float32)
    (cx, cy), (rw, rh), ang = cv2.minAreaRect(pts)
    rw += 2.5; rh += 2.5                                     # the brown outline belongs to the building
    hull = cv2.contourArea(cv2.convexHull(pts))
    # buildings are drawn with a dark outline; flowers and field strips are not
    y0, y1, x0, x1 = max(0, y - 4), min(H, y + h + 4), max(0, x - 4), min(W, x + w + 4)
    own = (lab[y0:y1, x0:x1] == i).astype(np.uint8)
    rim = cv2.dilate(own, ell(3)) & (1 - own)
    lined = float((dark[y0:y1, x0:x1][rim > 0]).mean()) if rim.sum() else 0.0
    blobs.append({"cx": cx, "cy": cy, "w": rw, "h": rh, "ang": math.radians(ang), "area": area, "hull": hull,
                  "L": max(rw, rh) * MPP, "S": min(rw, rh) * MPP, "lined": lined, "roady": float(road[y:y + h, x:x + w][lab[y:y + h, x:x + w] == i].mean())})


def blob_at(px, py, reach=22):
    best = min(blobs, key=lambda b: math.hypot(b["cx"] - px, b["cy"] - py))
    return best if math.hypot(best["cx"] - px, best["cy"] - py) <= reach else None


# ---- landmarks: the game's buildings at the map's labelled places ----
# (map label, scenery id, or "design:<name>" for a town building placed as a house, picture position, snap to the
#  drawn building there). Places confirmed by HorseBucker 2026-11-13.
MARKS = [
    ("R1", "trainstation_01", (738, 1050), True),
    ("R2", "goldenoaklibrary_01", (848, 1035), True),
    ("S2", "schoolhouse_01", (1040, 1568), False),         # the school is bigger than the S2 drawing: kept clear of the lake
    ("R4", "general_hospital_01", (951, 859), True),
    ("D9", "design:sugarcube", (958, 1335), True),
    ("D7", "rarityboutique_01", (1221, 1463), False),
    ("D18", "burger_joint_01", (893, 1193), True),
    ("D2", "spa_01", (1328, 1107), True),
    ("D1", "design:town_hall", (1313, 1245), False),
    ("D8", "fountain_01", (1237, 1218), True),
    ("E2", "snazzys_fluttershy_cottage_01", (2096, 1726), True),
    ("S4", "appleacres_barned_01", (833, 1915), True),
    ("S3", "cutiemarkcrusaders_clubhouse_01", (949, 1714), True),
    ("E4", "sweetappleacres_carrot_farmhouse_01", (1971, 1214), True),
    ("E5", "windmill_01", (1827, 1180), True),
    ("S1", "windmill_02", (906, 1507), True),        # HorseBucker 2026-11-13: a second windmill by Tranquility Lake
]
NAMES = {"sugarcube": "Sugarcube Corner", "town_hall": "Town Hall"}
# the market just east of the spa (D2): tents first, then the stalls, nearest free spot to each aim (pixels)
MARKET = [("tent_friagram_red_01", (1392, 1098)), ("tent_friagram_purple_01", (1392, 1150)), ("tent_friagram_orange_01", (1440, 1125)),
          ("kiosk_02_01", (1360, 1150)), ("cloudsdale_hotdogstand_01", (1365, 1175)), ("kiosk_01_01", (1420, 1180)),
          ("trixie_wagon_01", (1400, 1200))]                     # Trixie's wagon is her home: by the market
# kept where they stand in the game: Rainbow Dash's Cloudominium floats over the east meadow
KEEP = ["cloudominium_01"]
scenery = {s["id"]: s for s in TOWN["scenery"]}
taken = set()
for label, sid, (px, py), snap in MARKS:
    b = blob_at(px, py, 22 if snap else 40)
    if b is not None:
        taken.add(id(b))

open_ground = ((sage | road) & (1 - tan)).astype(np.uint8)
far_open = cv2.distanceTransform(1 - open_ground, cv2.DIST_L2, 5)


def openness(px, py, fx, fz, start_px):
    """How open the ground is ahead of a front: share of sage/road along 8 m, less the way to open ground."""
    hits = 0; total = 0
    for step in np.arange(0.5, 8.01, 0.5):
        x = int(round(px + fx * (start_px + step / MPP))); y = int(round(py + fz * (start_px + step / MPP)))
        if 0 <= x < W and 0 <= y < H:
            total += 1; hits += int(open_ground[y, x])
    x = int(np.clip(round(px + fx * (start_px + 3 / MPP)), 0, W - 1)); y = int(np.clip(round(py + fz * (start_px + 3 / MPP)), 0, H - 1))
    return (hits / max(1, total)) - 0.02 * far_open[y, x] * MPP


def local_shape(points, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in points]


DESIGNS = {}
for name, d in TOWN["designs"].items():
    if len(name) != 1:
        continue
    fp = [[p[0] * d["scale"], p[1] * d["scale"]] for p in d["footprint"]]
    xs = [p[0] for p in fp]; zs = [p[1] for p in fp]
    DESIGNS[name] = {"fp": fp, "bw": max(xs) - min(xs), "bd": max(zs) - min(zs), "mid": [(max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2],
                     "scale": d["scale"], "area": abs(sum(fp[i][0] * fp[(i + 1) % len(fp)][1] - fp[(i + 1) % len(fp)][0] * fp[i][1] for i in range(len(fp)))) / 2}
FLOOR = 0.85          # smallest a house is ever shrunk to
SLACK = 0.7           # metres a house may stick out of its drawn rectangle


def poly_of(h):
    d = DESIGNS[h["design"]]
    k = h["k"]
    pts = [[(p[0] - d["mid"][0]) * k, (p[1] - d["mid"][1]) * k] for p in d["fp"]]
    return [[h["cx"] + p[0], h["cz"] + p[1]] for p in local_shape(pts, h["yaw"])]


def fit(b, only=None, penalty=None):
    """The design, facing and size that best match a drawn rectangle."""
    u = (math.cos(b["ang"]), math.sin(b["ang"])); v = (-u[1], u[0])
    best = None
    for name, d in DESIGNS.items():
        if only and name not in only:
            continue
        jitter = random.random() * 0.2
        for front, along, across in ((u, b["w"], b["h"]), ((-u[0], -u[1]), b["w"], b["h"]), (v, b["h"], b["w"]), ((-v[0], -v[1]), b["h"], b["w"])):
            k = min(1.0, (along * MPP + SLACK) / d["bd"], (across * MPP + SLACK) / d["bw"])
            waste = abs(b["w"] * b["h"] * MPP * MPP - d["area"] * k * k) / (b["w"] * b["h"] * MPP * MPP)
            look = openness(b["cx"], b["cy"], front[0], front[1], along / 2)
            cost = (penalty or {}).get(name, 0.0) + 2.0 * (1 - max(k, 0.5)) + (4.0 * (FLOOR - k) if k < FLOOR else 0) + 0.6 * (1 - look) + 0.5 * waste + jitter
            if best is None or cost < best[0]:
                best = (cost, name, front, k, look)
    _, name, front, k, look = best
    return {"design": name, "yaw": math.atan2(front[0], front[1]), "k": max(k, FLOOR), "want": k, "look": look}


houses = []
skipped = {"small": 0, "shape": 0, "left out": 0}
for b in blobs:
    px, py = int(b["cx"]), int(b["cy"])
    if SKIP[py, px] or R5[py, px] or id(b) in taken:
        skipped["left out"] += 1; continue
    if b["S"] < 2.3 or b["L"] < 3.6:
        skipped["small"] += 1; continue
    if b["lined"] < 0.3 or b["roady"] > 0.5 or b["hull"] / max(1.0, (b["w"] - 2.5) * (b["h"] - 2.5)) < 0.72 or b["area"] / max(1.0, b["hull"]) < 0.55 or (b["L"] / b["S"] > 3.2 and b["S"] < 4.2) or b["L"] > 24:
        skipped["shape"] += 1; continue
    h = fit(b)
    h["cx"], h["cz"] = REF["x"] + (b["cx"] - W / 2) * MPP, REF["z"] + (b["cy"] - H / 2) * MPP
    h["blob"] = b
    houses.append(h)


def variety(h, everyone):
    """Extra cost for a design the nearby houses already use, and for a design used too much overall."""
    near = [o["design"] for o in everyone if o is not h and math.hypot(o["cx"] - h["cx"], o["cz"] - h["cz"]) < 16]
    total = {}
    for o in everyone:
        total[o["design"]] = total.get(o["design"], 0) + 1
    out = {}
    for name in DESIGNS:
        same = sum(1 for d in near if d == name)
        out[name] = 0.9 * same / max(1, len(near)) + 1.2 * max(0.0, total.get(name, 0) / len(everyone) - 0.4)
    return out


for _ in range(3):
    random.shuffle(houses)
    for h in houses:
        keep = {k: h[k] for k in ("cx", "cz", "blob")}
        h.update(fit(h["blob"], penalty=variety(h, houses))); h.update(keep)
print("outline share percentiles", [round(float(np.percentile([b["lined"] for b in blobs], q)), 2) for q in (5, 15, 25, 50, 75)])
print("blobs", len(blobs), "-> houses", len(houses), skipped)

# ---- overlaps ----
def seg_hit(a, b, c, d):
    def side(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    return (side(a, b, c) > 0) != (side(a, b, d) > 0) and (side(c, d, a) > 0) != (side(c, d, b) > 0)


def inside(poly, x, z):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a[1] > z) != (b[1] > z) and x < (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
        j = i
    return hit


def grow(poly, by):
    mx = sum(p[0] for p in poly) / len(poly); mz = sum(p[1] for p in poly) / len(poly)
    out = []
    for p in poly:
        d = math.hypot(p[0] - mx, p[1] - mz) or 1
        out.append([p[0] + (p[0] - mx) / d * by, p[1] + (p[1] - mz) / d * by])
    return out


def polys_hit(p, q):
    for i in range(len(p)):
        for j in range(len(q)):
            if seg_hit(p[i], p[(i + 1) % len(p)], q[j], q[(j + 1) % len(q)]):
                return True
    return inside(q, p[0][0], p[0][1]) or inside(p, q[0][0], q[0][1])


# ---- landmarks and notes ----
landmarks = []; notes = []; solid = []        # solid: outlines and circles houses must stay out of


def landmark_shape(sid, x, z, yaw):
    s = scenery[sid]
    c, sn = math.cos(-s["yaw"]), math.sin(-s["yaw"])
    loc = [[(p[0] - s["x"]) * c + (p[1] - s["z"]) * sn, -(p[0] - s["x"]) * sn + (p[1] - s["z"]) * c] for p in s["footprint"]]
    return [[x + p[0], z + p[1]] for p in local_shape(loc, yaw)]


def design_shape(name, x, z, yaw):
    d = TOWN["designs"][name]
    return [[x + p[0], z + p[1]] for p in local_shape([[q[0] * d["scale"], q[1] * d["scale"]] for q in d["footprint"]], yaw)]


STAY_DRY = cv2.dilate(((water | bridge) & (1 - SKIP)).astype(np.uint8), ell(7))     # water and bridges, with 2.4 m of bank


WET = cv2.dilate(((water | bridge) & (1 - SKIP)).astype(np.uint8), ell(2))          # water and bridges, 0.7 m round


def touches_water(poly, mask=None):
    mask = STAY_DRY if mask is None else mask
    pts = np.array([[(p[0] - REF["x"]) / MPP + W / 2, (p[1] - REF["z"]) / MPP + H / 2] for p in poly], np.int32)
    x0, y0 = max(0, pts[:, 0].min() - 2), max(0, pts[:, 1].min() - 2)
    x1, y1 = min(W, pts[:, 0].max() + 3), min(H, pts[:, 1].max() + 3)
    m = np.zeros((y1 - y0, x1 - x0), np.uint8)
    cv2.fillPoly(m, [pts - [x0, y0]], 1)
    return bool((m & mask[y0:y1, x0:x1]).any())


specials = []
for label, sid, (px, py), snap in MARKS:
    b = blob_at(px, py) if snap else None
    cx, cy = (b["cx"], b["cy"]) if b is not None else (px, py)
    x, z = world(cx, cy)
    # face the most open of eight directions
    best = max(range(8), key=lambda i: openness(cx, cy, math.sin(i * math.pi / 4), math.cos(i * math.pi / 4), 6 / MPP))
    yaw = round(best * math.pi / 4, 4)
    if label == "D1":
        # the town hall fronts the plaza and its fountain (D8)
        fx, fy = 1237 - cx, 1218 - cy
        yaw = round(math.atan2(fx, fy), 4)
    if sid.startswith("design:"):
        name = sid[7:]
        specials.append({"design": name, "filler": False, "x": x, "z": z, "yaw": yaw, "name": NAMES[name]})
        solid.append(("poly", design_shape(name, x, z, yaw)))
        continue
    shape = landmark_shape(sid, x, z, yaw)
    for r in range(3, 90, 3):
        if not touches_water(shape):
            break
        spots = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in range(0, 360, 15)]
        dry = [q for q in spots if not touches_water(landmark_shape(sid, *world(*q), yaw))]
        if dry:
            x, z = world(*dry[0]); shape = landmark_shape(sid, x, z, yaw); break
    landmarks.append({"id": sid, "x": x, "z": z, "yaw": yaw})
    solid.append(("poly", shape))


def hits_any(poly, pad):
    for s2 in solid:
        if polys_hit(grow(poly, pad), s2[1]):
            return True
    return touches_water(poly)




for sid in KEEP:
    s0 = scenery[sid]
    landmarks.append({"id": sid, "x": s0["x"], "z": s0["z"], "yaw": s0["yaw"]})
MARKET_PLACED = []
for sid, (px, py) in MARKET:
    face = max(range(8), key=lambda i: openness(px, py, math.sin(i * math.pi / 4), math.cos(i * math.pi / 4), 4 / MPP))
    yaw = round(face * math.pi / 4, 4)
    done = False
    for r in range(0, 90, 3):
        for a in range(0, 360, 20 if r else 360):
            qx, qy = px + r * math.cos(math.radians(a)), py + r * math.sin(math.radians(a))
            x, z = world(qx, qy)
            if not sage[int(qy), int(qx)] and not tan[int(qy), int(qx)]:
                continue                                          # the market stays in town, this side of the river
            shape = landmark_shape(sid, x, z, yaw)
            if not hits_any(shape, 0.8):
                landmarks.append({"id": sid, "x": x, "z": z, "yaw": yaw}); solid.append(("poly", shape)); MARKET_PLACED.append(sid); done = True
                break
        if done:
            break
    if not done:
        print("no room for", sid)


GAP = 0.25            # metres kept between any two buildings (each outline grown by half of it... and a bit)


def blocked(h):
    p = grow(poly_of(h), GAP)
    if touches_water(p, WET):
        return True
    for s in solid:
        if s[0] == "circle":
            if any(math.hypot(q[0] - s[1], q[1] - s[2]) < s[3] for q in p) or math.hypot(h["cx"] - s[1], h["cz"] - s[2]) < s[3]:
                return True
        elif polys_hit(p, grow(s[1], 1.0)):
            return True
    return False


before = len(houses)
houses = [h for h in houses if not blocked(h)]
print("dropped for landmarks and water:", before - len(houses))


def clashes():
    out = []
    shapes = [grow(poly_of(h), GAP) for h in houses]
    for i in range(len(houses)):
        for j in range(i + 1, len(houses)):
            if math.hypot(houses[i]["cx"] - houses[j]["cx"], houses[i]["cz"] - houses[j]["cz"]) > 18:
                continue
            if polys_hit(shapes[i], shapes[j]):
                out.append((i, j))
    return out


def area(h):
    return DESIGNS[h["design"]]["area"] * h["k"] ** 2


first = len(clashes())
dropped = 0
for round_ in range(160):
    pairs = clashes()
    if not pairs:
        break
    count = {}
    for i, j in pairs:
        count[i] = count.get(i, 0) + 1; count[j] = count.get(j, 0) + 1
    changed = set(); drop = set()
    for i, j in pairs:
        big = i if area(houses[i]) >= area(houses[j]) else j
        if big in changed or i in drop or j in drop:
            continue
        h = houses[big]
        if h["k"] > FLOOR + 1e-6:
            h["k"] = max(FLOOR, h["k"] - 0.05); changed.add(big)
        elif h["design"] not in ("b", "c") and round_ < 40 and not h.get("swapped"):
            h["swapped"] = True
            new = fit(h["blob"], only=("a", "b", "c"), penalty=variety(h, houses)); new["k"] = max(FLOOR, min(new["k"], 0.95))
            h.update(new); changed.add(big)
        elif houses[i].get("moved", 0) < 1.4 and houses[j].get("moved", 0) < 1.4 and i not in changed and j not in changed:
            # as small as they go: ease the two apart a little
            a, b2 = houses[i], houses[j]
            dx, dz = b2["cx"] - a["cx"], b2["cz"] - a["cz"]; d = math.hypot(dx, dz) or 1
            for one, sign in ((a, -1), (b2, 1)):
                one["cx"] += sign * dx / d * 0.35; one["cz"] += sign * dz / d * 0.35; one["moved"] = one.get("moved", 0) + 0.35
            changed.add(i); changed.add(j)
        elif i not in changed and j not in changed:
            # still touching: the one tangled with more neighbours goes
            worst = i if (count[i], -houses[i]["look"]) >= (count[j], -houses[j]["look"]) else j
            drop.add(worst)
    if drop:
        dropped += len(drop)
        houses = [h for k, h in enumerate(houses) if k not in drop]
left = len(clashes())
print("overlapping pairs at first", first, "-> left", left, "; houses dropped", dropped, "; kept", len(houses),
      "; shrunk", sum(1 for h in houses if h["k"] < 0.999), "; nudged", sum(1 for h in houses if h.get("moved")))
houses = [h for h in houses if not blocked(h)]

plan_houses = list(specials)
for h in houses:
    d = DESIGNS[h["design"]]
    k = h["k"]
    off = local_shape([[-d["mid"][0] * k, -d["mid"][1] * k]], h["yaw"])[0]
    row = {"design": h["design"], "filler": True, "x": round(h["cx"] + off[0], 2), "z": round(h["cz"] + off[1], 2), "yaw": round(h["yaw"], 4), "name": ""}
    if k < 0.999:
        row["scale"] = round(d["scale"] * k, 3)
    plan_houses.append(row)

# ---- town ground (sage) and the grass inside it ----
tan_town = tan & (1 - R5)
body = cv2.morphologyEx(((sage | tan_town | bridge) & (1 - SKIP)).astype(np.uint8), cv2.MORPH_CLOSE, ell(5))
n, lab, stats, _ = cv2.connectedComponentsWithStats((sage & (1 - SKIP)).astype(np.uint8), connectivity=8)
keep = np.zeros((H, W), np.uint8)
for i in range(1, n):
    if stats[i][4] > 2500:
        keep |= (lab == i).astype(np.uint8)
seeded = cv2.morphologyEx(keep, cv2.MORPH_CLOSE, ell(9))
# whole sage areas: closed sage, with the buildings standing in it
n, lab, stats, _ = cv2.connectedComponentsWithStats(body, connectivity=8)
filled = np.zeros((H, W), np.uint8)
grounds = []; greens = []
for i in range(1, n):
    comp = (lab == i).astype(np.uint8)
    if (comp & keep).sum() < 2500:
        continue
    comp = cv2.morphologyEx(comp, cv2.MORPH_OPEN, ell(3))
    contours, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in contours:
        if cv2.contourArea(c) < 2500:
            continue
        c = cv2.approxPolyDP(c, 3.0, True)
        cv2.fillPoly(filled, [c], 1)
        grounds.append({"points": [world(p[0][0], p[0][1]) for p in c]})
grass = (filled & (1 - cv2.dilate(cv2.morphologyEx((sage | tan_town | bridge | water).astype(np.uint8), cv2.MORPH_CLOSE, ell(4)), ell(2)))).astype(np.uint8)
grass = cv2.morphologyEx(grass, cv2.MORPH_OPEN, ell(4))
contours, _ = cv2.findContours(grass, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
for c in contours:
    if cv2.contourArea(c) < 420:                             # under about 50 m2: a tree or a tuft, not a lawn
        continue
    c = cv2.approxPolyDP(c, 2.5, True)
    if len(c) >= 3:
        greens.append({"points": [world(p[0][0], p[0][1]) for p in c]})
print("grounds", len(grounds), [len(g["points"]) for g in grounds], "greens", len(greens))

# ---- water ----
wet = ((water | bridge) & (1 - MOAT) & (1 - box(0, 0, 800, 340))).astype(np.uint8)
wet = cv2.morphologyEx(wet, cv2.MORPH_CLOSE, ell(4))
# Sparkling Lake without the castle's causeway and gate standing in it
lake_box = box(1030, 575, 1470, 830)
wet |= cv2.morphologyEx(wet & lake_box, cv2.MORPH_CLOSE, ell(22)) & lake_box
# holes (lily pads, lettering) fill in
contours, hier = cv2.findContours(wet, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
for c, hr in zip(contours, hier[0]):
    if hr[3] >= 0 and cv2.contourArea(c) < 6000:
        cv2.fillPoly(wet, [c], 1)
n, lab, stats, _ = cv2.connectedComponentsWithStats(wet, connectivity=8)
for i in range(1, n):
    if stats[i][4] < 1500:
        wet[lab == i] = 0
LAKES = {"Sparkling Lake": (1109, 690, 19), "Marigold Lake": (1528, 1393, 19), "Tranquility Lake": (968, 1524, 11)}
lake_mask = np.zeros((H, W), np.uint8)
lakes = []
for name, (px, py, r) in LAKES.items():
    opened = cv2.morphologyEx(wet, cv2.MORPH_OPEN, ell(r))
    n, lab, _, _ = cv2.connectedComponentsWithStats(opened, connectivity=8)
    ys, xs = np.nonzero(opened[py - 40:py + 41, px - 40:px + 41])
    if not len(ys):
        print("no lake at", name); continue
    k = np.argmin((ys - 40) ** 2 + (xs - 40) ** 2)
    i = lab[py - 40 + ys[k], px - 40 + xs[k]]
    one = cv2.dilate((lab == i).astype(np.uint8), ell(r + 2)) & wet
    lake_mask |= one
    contours, _ = cv2.findContours(one, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    c = cv2.approxPolyDP(max(contours, key=cv2.contourArea), 3.0, True)
    lakes.append({"name": name, "points": [world(p[0][0], p[0][1]) for p in c]})
    notes.append({"x": world(px, py)[0], "z": world(px, py)[1], "text": name})


def thin(img):
    img = img.astype(bool).copy()
    while True:
        gone = 0
        for step in (0, 1):
            p = np.pad(img, 1)
            P2 = p[:-2, 1:-1]; P3 = p[:-2, 2:]; P4 = p[1:-1, 2:]; P5 = p[2:, 2:]; P6 = p[2:, 1:-1]; P7 = p[2:, :-2]; P8 = p[1:-1, :-2]; P9 = p[:-2, :-2]
            ring = [P2, P3, P4, P5, P6, P7, P8, P9, P2]
            B = sum(r.astype(np.uint8) for r in ring[:8])
            A = sum((~ring[k] & ring[k + 1]).astype(np.uint8) for k in range(8))
            if step == 0:
                rule = ~(P2 & P4 & P6) & ~(P4 & P6 & P8)
            else:
                rule = ~(P2 & P4 & P8) & ~(P2 & P6 & P8)
            kill = img & (B >= 2) & (B <= 6) & (A == 1) & rule
            gone += int(kill.sum())
            img[kill] = False
        if not gone:
            return img


def lines(mask, spur_px, eps):
    """Centre lines of a mask: [(points in pixels, median width in pixels)]."""
    ys, xs = np.nonzero(mask)
    if not len(ys):
        return []
    y0, y1, x0, x1 = max(0, ys.min() - 2), ys.max() + 3, max(0, xs.min() - 2), xs.max() + 3
    sub = mask[y0:y1, x0:x1]
    dist = cv2.distanceTransform(sub, cv2.DIST_L2, 5)
    sk = thin(sub)
    p = np.pad(sk, 1).astype(np.uint8)
    deg = sum(p[1 + dy:p.shape[0] - 1 + dy, 1 + dx:p.shape[1] - 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx) * sk
    node = (sk & (deg != 2)).astype(np.uint8)
    nn, nlab, _, ncent = cv2.connectedComponentsWithStats(node, connectivity=8)
    seen = np.zeros(sk.shape, bool)
    edges = []
    hh, ww = sk.shape

    def around(y, x):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if (dy or dx) and 0 <= y + dy < hh and 0 <= x + dx < ww and sk[y + dy, x + dx]:
                    yield y + dy, x + dx

    for (y, x) in np.argwhere(node):
        for (ay, ax) in around(y, x):
            if node[ay, ax] or seen[ay, ax]:
                continue
            path = [(y, x), (ay, ax)]; seen[ay, ax] = True
            end = None
            while True:
                cy, cx = path[-1]
                step = None
                for (by, bx) in around(cy, cx):
                    if node[by, bx] and (len(path) > 2 or nlab[by, bx] != nlab[y, x]):
                        end = (by, bx); break
                if end:
                    break
                for (by, bx) in around(cy, cx):
                    if not node[by, bx] and not seen[by, bx]:
                        step = (by, bx); break
                if step is None:
                    break
                seen[step] = True; path.append(step)
            if end:
                path.append(end)
            edges.append({"path": path, "a": int(nlab[y, x]), "b": int(nlab[end]) if end else -len(edges) - 1})
    # node clusters count as one place; a cluster of a lone end pixel is a free end
    for _ in range(3):
        use = {}
        for e in edges:
            use[e["a"]] = use.get(e["a"], 0) + 1; use[e["b"]] = use.get(e["b"], 0) + 1
        edges = [e for e in edges if not (len(e["path"]) < spur_px and (use[e["a"]] == 1 or use[e["b"]] == 1))]
    # join edges through each place, straightest pair first
    for e in edges:
        e["pts"] = [(float(q[1]), float(q[0])) for q in e["path"]]
        e["wide"] = float(np.median([dist[q[0], q[1]] for q in e["path"]])) * 2
    def heading(e, at):
        pts = e["pts"] if e["a"] == at else e["pts"][::-1]
        q = pts[min(len(pts) - 1, 12)]
        return math.atan2(q[1] - pts[0][1], q[0] - pts[0][0])
    places = set(e["a"] for e in edges) | set(e["b"] for e in edges)
    for place in places:
        while True:
            here = [e for e in edges if (e["a"] == place) != (e["b"] == place)]
            if len(here) < 2:
                break
            best = None
            for i in range(len(here)):
                for j in range(i + 1, len(here)):
                    turn = abs(math.remainder(heading(here[i], place) - heading(here[j], place) - math.pi, 2 * math.pi))
                    ratio = max(here[i]["wide"], here[j]["wide"]) / max(0.5, min(here[i]["wide"], here[j]["wide"]))
                    if ratio > 1.7:
                        continue
                    if best is None or turn < best[0]:
                        best = (turn, here[i], here[j])
            if best is None:
                break
            turn, e1, e2 = best
            if turn > math.radians(55) and len(here) > 2:
                break
            p1 = e1["pts"] if e1["b"] == place else e1["pts"][::-1]
            p2 = e2["pts"] if e2["a"] == place else e2["pts"][::-1]
            a1 = e1["a"] if e1["b"] == place else e1["b"]
            b2 = e2["b"] if e2["a"] == place else e2["a"]
            edges.remove(e1); edges.remove(e2)
            edges.append({"pts": p1 + p2, "a": a1, "b": b2, "path": [], "wide": (e1["wide"] * len(p1) + e2["wide"] * len(p2)) / (len(p1) + len(p2))})
    out = []
    for e in edges:
        pts = np.array(e["pts"], np.float32)
        if len(pts) < 2:
            continue
        wide = e["wide"]
        simple = cv2.approxPolyDP(pts.reshape(-1, 1, 2), eps, False).reshape(-1, 2)
        length = float(np.sum(np.hypot(*np.diff(simple, axis=0).T)))
        out.append(([(float(q[0]) + x0, float(q[1]) + y0) for q in simple], wide, length))
    return out


stream = (wet & (1 - cv2.erode(lake_mask, ell(9)))).astype(np.uint8)
rivers = []
for pts, wide, length in lines(stream, 28, 2.0):
    if length * MPP < 12:
        continue
    rivers.append({"width": round(min(16.0, max(2.5, wide * MPP)), 1), "points": [world(*q) for q in pts]})
print("lakes", len(lakes), "rivers", len(rivers), "widths", sorted(r["width"] for r in rivers))

# ---- dirt roads ----
way = (road & (1 - SKIP) & (1 - filled)).astype(np.uint8)
way = cv2.morphologyEx(way, cv2.MORPH_CLOSE, ell(3))
yard = cv2.dilate(cv2.morphologyEx(way, cv2.MORPH_OPEN, ell(11)), ell(4))        # farm yards are not roads
way &= (1 - yard)
n, lab, stats, _ = cv2.connectedComponentsWithStats(way, connectivity=8)
for i in range(1, n):
    if stats[i][4] < 500 or max(stats[i][2], stats[i][3]) < 45:
        way[lab == i] = 0
roads = []
for pts, wide, length in lines(way, 22, 2.0):
    if length * MPP < 9:
        continue
    roads.append({"type": "dirt", "width": round(min(5.0, max(2.5, wide * MPP)), 1), "points": [world(*q) for q in pts]})
print("dirt roads", len(roads), "total m", round(sum(sum(math.hypot(r["points"][i + 1][0] - r["points"][i][0], r["points"][i + 1][1] - r["points"][i][1]) for i in range(len(r["points"]) - 1)) for r in roads)))

# ---- bridges ----
n, lab, stats, _ = cv2.connectedComponentsWithStats((bridge & (1 - SKIP)).astype(np.uint8), connectivity=8)
bridges = []
for i in range(1, n):
    if stats[i][4] < 60:
        continue
    pts = np.argwhere(lab == i)[:, ::-1].astype(np.float32)
    (cx, cy), (rw, rh), ang = cv2.minAreaRect(pts)
    a = math.radians(ang)
    best = None
    for (dx, dy), span, wide in (((math.cos(a), math.sin(a)), rw, rh), ((-math.sin(a), math.cos(a)), rh, rw)):
        dry = 0
        for sign in (-1, 1):
            for extra in (4, 7, 10):
                x = int(np.clip(round(cx + sign * dx * (span / 2 + extra)), 0, W - 1)); y = int(np.clip(round(cy + sign * dy * (span / 2 + extra)), 0, H - 1))
                dry += int(not wet[y, x])
        if best is None or dry > best[0]:
            best = (dry, dx, dy, span, wide)
    dry, dx, dy, span, wide = best
    reach = span / 2 + 1.5 / MPP
    bridges.append({"width": round(max(3.0, min(8.0, wide * MPP)), 1), "a": world(cx - dx * reach, cy - dy * reach), "b": world(cx + dx * reach, cy + dy * reach)})
print("bridges", len(bridges))

# ---- the railway: brown sleepers ----
r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]
sleepers = ((r_ > 60) & (r_ < 175) & (g_ > 30) & (g_ < 100) & (b_ < 75) & (r_ - g_ > 25)).astype(np.uint8) & (1 - SKIP) & (1 - filled)
track = cv2.morphologyEx(sleepers, cv2.MORPH_CLOSE, ell(7))
n, lab, stats, _ = cv2.connectedComponentsWithStats(track, connectivity=8)
keep = np.zeros((H, W), np.uint8)
for i in range(1, n):
    if stats[i][4] > 4000 and max(stats[i][2], stats[i][3]) > 300:
        keep[lab == i] = 1
railways = []
for pts, wide, length in lines(keep, 45, 2.5):
    if length * MPP >= 25:
        railways.append({"points": [world(*q) for q in pts]})
print("railway pieces", len(railways), [round(sum(math.dist(r["points"][i], r["points"][i + 1]) for i in range(len(r["points"]) - 1))) for r in railways])

# ---- the edge of the rebuilt area: everything traced, with room round it ----
edge_box = [world(30, 30), world(W - 30, 30), world(W - 30, H - 30), world(30, H - 30)]
every = [p for h in plan_houses for p in [[h["x"], h["z"]]]] + [p for g in grounds for p in g["points"]] + [p for l in lakes for p in l["points"]] \
    + [p for r in rivers + roads for p in r["points"]] + [[l["x"], l["z"]] for l in landmarks]
hull = cv2.convexHull(np.array(every, np.float32)).reshape(-1, 2)
mid = hull.mean(0)
edge = []
gb = TOWN["ground"]["bounds"] if TOWN.get("ground") else [-700, 1100, -900, 500]
for p in cv2.approxPolyDP(hull.reshape(-1, 1, 2), 12.0, True).reshape(-1, 2):
    d = p - mid; d = d / (np.linalg.norm(d) or 1)
    q = p + d * 30
    edge.append([round(float(np.clip(q[0], gb[0] + 30, gb[1] - 30)), 1), round(float(np.clip(q[1], gb[2] + 30, gb[3] - 30)), 1)])

plan = {"version": 1, "reference": REF, "houses": plan_houses, "landmarks": landmarks, "roads": roads, "rivers": rivers,
        "lakes": [{"points": l["points"]} for l in lakes], "bridges": bridges, "flats": [], "notes": notes,
        "edges": [{"flatten": True, "height": None, "points": edge_box}], "grounds": grounds, "greens": greens,
        "railways": railways}
json.dump(plan, open(OUT, "w"), separators=(",", ":"))
print("houses by design", {d: sum(1 for h in plan_houses if h["design"] == d) for d in sorted(DESIGNS)})
print("edge points", len(edge), "plan bytes", len(json.dumps(plan)))

# ---- a picture of the result over the map, for checking ----
show = (im * 0.55).astype(np.uint8)


def pix(p):
    return [int(round((p[0] - REF["x"]) / MPP + W / 2)), int(round((p[1] - REF["z"]) / MPP + H / 2))]


for g in grounds:
    cv2.polylines(show, [np.array([pix(p) for p in g["points"]])], True, (200, 255, 200), 2)
for g in greens:
    cv2.polylines(show, [np.array([pix(p) for p in g["points"]])], True, (0, 200, 0), 2)
for l in lakes:
    cv2.polylines(show, [np.array([pix(p) for p in l["points"]])], True, (255, 255, 0), 2)
for r in rivers:
    cv2.polylines(show, [np.array([pix(p) for p in r["points"]])], False, (255, 160, 0), max(1, int(r["width"] / MPP / 3)))
for r in roads:
    cv2.polylines(show, [np.array([pix(p) for p in r["points"]])], False, (0, 220, 255), 3)
for b in bridges:
    cv2.line(show, pix(b["a"]), pix(b["b"]), (255, 0, 255), 5)
for h, row in zip(houses, plan_houses):
    poly = np.array([pix(p) for p in poly_of(h)])
    cv2.polylines(show, [poly], True, (255, 255, 255) if "scale" not in row else (150, 200, 255), 2)
    door = [h["cx"] + math.sin(h["yaw"]) * 4, h["cz"] + math.cos(h["yaw"]) * 4]
    cv2.line(show, pix([h["cx"], h["cz"]]), pix(door), (0, 0, 255), 2)
for l in landmarks:
    cv2.polylines(show, [np.array([pix(p) for p in landmark_shape(l["id"], l["x"], l["z"], l["yaw"])])], True, (0, 128, 255), 3)
cv2.polylines(show, [np.array([pix(p) for p in edge_box])], True, (0, 0, 255), 3)
cv2.imwrite("check_all.png", cv2.resize(show, None, fx=0.62, fy=0.62, interpolation=cv2.INTER_AREA))
cv2.imwrite("check_town_w.png", show[780:1500, 680:1330])
cv2.imwrite("check_town_e.png", show[650:1370, 1130:1780])
cv2.imwrite("check_south.png", show[1150:1870, 760:1500])
