"""Make the town's streets walkable: widen every narrow stretch of street, exit and doorstep.

usage: python tools/town_planner/fix_streets.py <plan.json> <out.json> [--street 7] [--exit 5] [--door 3]

Streets are measured roof edge to roof edge (roofs, porches and steps included). A narrow stretch counts
as a street when it runs on for a while between buildings (a gap between two neighbours in a row is a
side gap, not a street, and is left alone). Exits are the ways from the town onto its roads and bridges;
doorsteps the ground in front of each front door.
- Doorsteps are checked for real homes only (nopony goes into a background house).
- Widths wanted: streets `--street` (6 m: two rows of houses facing each other a pony-cart apart, a
  little tighter than the show's main street), exits `--exit` (4 m), doorsteps `--door` (3 m).
- Only a stretch that front doors face is a street (the ground behind a row is back gardens).
- A house whose front door faces a wall turns to face open ground instead.
- Buildings along a narrow stretch step back from it, up to 4 m (background houses) or 2 m (real homes),
  if that leaves their own roofs 1 m clear of everything and keeps them out of the water. A background
  house that cannot step back is left out. Landmarks never move.
Repeats until nothing is narrow or nothing more can be done, and prints what changed.
"""
import json, math, sys
import cv2, numpy as np
from scipy import ndimage

SRC, OUT = sys.argv[1], sys.argv[2]
def arg(name, default):
    return float(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default
STREET, EXIT, DOOR = arg("--street", 6.0), arg("--exit", 4.0), arg("--door", 3.0)
ALLEY = 3.0           # gaps narrower than this between neighbours are inside a row
RES = 0.5
ROOF_GAP = 1.0
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
plan = json.load(open(SRC, encoding="utf-8"))
tj = open(HERE + "/data/town.js", encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
SCEN = {s["id"]: s for s in TOWN["scenery"]}
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}


def turn(pts, y):
    c, s = math.cos(y), math.sin(y)
    return [[p[0] * c + p[1] * s, -p[0] * s + p[1] * c] for p in pts]


def shape(item):
    if "id" in item:
        s = SCEN[item["id"]]
        local = turn([[p[0] - s["x"], p[1] - s["z"]] for p in s["footprint"]], -s["yaw"])
        return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(local, item["yaw"])]
    d = TOWN["designs"][item["design"]]; k = item.get("scale") or d["scale"]
    if item["design"] in MODEL:
        x0, x1, z0, z1 = MODEL[item["design"]]
        pts = [[x0 * k, z0 * k], [x1 * k, z0 * k], [x1 * k, z1 * k], [x0 * k, z1 * k]]
    else:
        pts = [[p[0] * k, p[1] * k] for p in d["footprint"]]
    return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(pts, item["yaw"])]


def door_spot(h, out=1.5):
    """A spot `out` metres beyond the front of the house's whole model (porch and steps), in line with its door."""
    d = TOWN["designs"][h["design"]]; k = h.get("scale") or d["scale"]
    c, s = math.cos(h["yaw"]), math.sin(h["yaw"])
    front = max(d["door"][1], MODEL.get(h["design"], (0, 0, 0, d["door"][1]))[3])
    lx, lz = d["door"][0] * k, front * k + out
    return (h["x"] + lx * c + lz * s, h["z"] - lx * s + lz * c)


def gap(A, B):
    best = -1e9
    for P in (A, B):
        for i in range(len(P)):
            a, b = P[i], P[(i + 1) % len(P)]
            n = (b[1] - a[1], -(b[0] - a[0])); L = math.hypot(*n) or 1; n = (n[0] / L, n[1] / L)
            pa = [p[0] * n[0] + p[1] * n[1] for p in A]; pb = [p[0] * n[0] + p[1] * n[1] for p in B]
            best = max(best, min(pb) - max(pa), min(pa) - max(pb))
    return best


# ---- the ground: the town and 60 m round it ----
g = np.array([p for gr in plan["grounds"] for p in gr["points"]])
X0, Z0 = g[:, 0].min() - 60, g[:, 1].min() - 60
X1, Z1 = g[:, 0].max() + 60, g[:, 1].max() + 60
W, H = int((X1 - X0) / RES) + 1, int((Z1 - Z0) / RES) + 1


def px(pts):
    return np.round((np.array(pts) - [X0, Z0]) / RES * 8).astype(np.int32)


def cell(p):
    return int(round((p[1] - Z0) / RES)), int(round((p[0] - X0) / RES))


def world(r, c):
    return (X0 + c * RES, Z0 + r * RES)


def fill(polys):
    m = np.zeros((H, W), np.uint8)
    for p in polys:
        cv2.fillPoly(m, [px(p)], 1, shift=3)
    return m.astype(bool)


water = np.zeros((H, W), np.uint8)
for r in plan["rivers"]:
    cv2.polylines(water, [px(r["points"])], False, 1, max(1, int(round(r["width"] / RES))), shift=3)
water = water.astype(bool) | fill([l["points"] for l in plan["lakes"]])
deck = np.zeros((H, W), np.uint8)
for b in plan["bridges"]:
    cv2.polylines(deck, [px([b["a"], b["b"]])], False, 1, max(1, int(round(b["width"] / RES))), shift=3)
water &= ~deck.astype(bool)
town = fill([gr["points"] for gr in plan["grounds"]])
near_town = ndimage.binary_dilation(town, iterations=int(8 / RES))


def thin(img):
    img = img.astype(bool).copy()
    while True:
        gone = 0
        for step in (0, 1):
            p = np.pad(img, 1)
            P2, P3, P4, P5 = p[:-2, 1:-1], p[:-2, 2:], p[1:-1, 2:], p[2:, 2:]
            P6, P7, P8, P9 = p[2:, 1:-1], p[2:, :-2], p[1:-1, :-2], p[:-2, :-2]
            ring = [P2, P3, P4, P5, P6, P7, P8, P9, P2]
            B = sum(r.astype(np.uint8) for r in ring[:8])
            A = sum((~ring[i] & ring[i + 1]).astype(np.uint8) for i in range(8))
            rule = (~(P2 & P4 & P6) & ~(P4 & P6 & P8)) if step == 0 else (~(P2 & P4 & P8) & ~(P2 & P6 & P8))
            kill = img & (B >= 2) & (B <= 6) & (A == 1) & rule
            gone += int(kill.sum()); img[kill] = False
        if not gone:
            return img


# exits: where the roads and bridges meet the town, a few metres in from the end
EXITS = []
for r in plan["roads"]:
    for p in (r["points"][0], r["points"][-1]):
        c = cell(p)
        if 0 <= c[0] < H and 0 <= c[1] < W and near_town[c]:
            EXITS.append(p)
for b in plan["bridges"]:
    for a, o in ((b["a"], b["b"]), (b["b"], b["a"])):
        d = (a[0] - o[0], a[1] - o[1]); L = math.hypot(*d) or 1
        p = (a[0] + d[0] / L * 8, a[1] + d[1] / L * 8)
        c = cell(p)
        if 0 <= c[0] < H and 0 <= c[1] < W and near_town[c]:
            EXITS.append(p)


def analyse():
    items = plan["houses"] + [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"]
    shapes = [shape(i) for i in items]
    build = fill(shapes)
    rows = ndimage.binary_closing(build, structure=np.ones((3, 3)), iterations=int(round(ALLEY / 2 / RES))) | build
    free = ~rows & ~water
    clear = ndimage.distance_transform_edt(free) * RES * 2
    global by_houses
    by_houses = ndimage.distance_transform_edt(~rows) * RES * 2       # the width the buildings alone leave
    mid = thin(free & (clear >= 1.0)) & near_town
    return items, shapes, build, free, clear, mid


def narrow_places(clear, mid):
    """[(cells, wanted width)] for every stretch of street (front doors face it) or exit that is too narrow."""
    out = []
    doors = np.zeros((H, W), bool)
    for h in plan["houses"]:
        if len(h["design"]) == 1:
            r, c = cell(door_spot(h))
            if 0 <= r < H and 0 <= c < W:
                doors[r, c] = True
    door_lab, _ = ndimage.label(doors)
    near_doors = ndimage.distance_transform_edt(~doors) * RES
    exit_zone = np.zeros((H, W), bool)
    for p in EXITS:
        r, c = cell(p)
        exit_zone[max(0, r - 50):r + 51, max(0, c - 50):c + 51] = True     # 25 m round an exit
    for want, zone, min_len in ((STREET, ~exit_zone, 5.0), (EXIT, exit_zone, 0.0)):
        # narrow because of buildings (water and bridge decks are as wide as they are)
        lab, n = ndimage.label(mid & zone & (clear < want) & (by_houses < want), structure=np.ones((3, 3)))
        for k in range(1, n + 1):
            cells = np.argwhere(lab == k)
            if len(cells) * RES < min_len:
                continue
            if want == STREET:
                # a street: at least two front doors open within 7 m of it
                rr, cc = cells[:, 0], cells[:, 1]
                box = doors[max(0, rr.min() - 14):rr.max() + 15, max(0, cc.min() - 14):cc.max() + 15]
                if box.sum() < 2 or near_doors[rr, cc].min() > 7.0:
                    continue
            out.append((cells, want))
    return out


def door_problems(free, clear):
    out = []
    for h in plan["houses"]:
        if len(h["design"]) > 1 or h["filler"]:      # background houses are never entered
            continue
        p = door_spot(h)
        r, c = cell(p)
        if not (0 <= r < H and 0 <= c < W):
            continue
        win = clear[max(0, r - 2):r + 3, max(0, c - 2):c + 3]
        if win.size and win.max() < DOOR:
            out.append((h, p))
    return out


def fits(it, all_items):
    me = shape(it)
    for o in all_items:
        if o is it or math.dist((it["x"], it["z"]), (o["x"], o["z"])) > 35:
            continue
        if gap(me, shape(o)) < ROOF_GAP:
            return False
    pts = np.array(me)
    for p in list(me) + [[it["x"], it["z"]]]:
        r, c = cell(p)
        if 0 <= r < H and 0 <= c < W and water[r, c]:
            return False
    for r in plan["rivers"]:
        for p in me:
            for i in range(len(r["points"]) - 1):
                a, b = r["points"][i], r["points"][i + 1]
                dx, dz = b[0] - a[0], b[1] - a[1]
                t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / ((dx * dx + dz * dz) or 1)))
                if math.hypot(a[0] + t * dx - p[0], a[1] + t * dz - p[1]) < r["width"] / 2 + 1.0:
                    return False
    return True


log = {"stepped back": 0, "left out": [], "real homes moved": 0}
moved_total = {}
tried = set()
for round_ in range(12):
    items, shapes, build, free, clear, mid = analyse()
    places = narrow_places(clear, mid)
    doors = door_problems(free, clear)
    print(f"round {round_ + 1}: narrow streets/exits {len(places)}, doorsteps {len(doors)}")
    if not places and not doors:
        break
    did = 0
    # who borders each narrow place, and which way is "away"
    jobs = {}
    for cells, want in places:
        centre_pts = [world(r, c) for r, c in cells[::max(1, len(cells) // 12)]]
        tight = cells[int(np.argmin(clear[cells[:, 0], cells[:, 1]]))]
        tight_pt = world(*tight)
        for it, sh in zip(items, shapes):
            if "id" in it or len(it["design"]) > 1:
                continue
            cx, cz = it["x"], it["z"]
            near = min(centre_pts, key=lambda q: math.dist(q, (cx, cz)))
            # distance from the stretch to this building's outline
            dd = min(math.dist(near, q) for q in sh + [[(sh[i][0] + sh[(i + 1) % len(sh)][0]) / 2, (sh[i][1] + sh[(i + 1) % len(sh)][1]) / 2] for i in range(len(sh))])
            if dd > want / 2 + 0.5:
                continue
            need = want / 2 - dd + 0.4
            away = (cx - near[0], cz - near[1]); L = math.hypot(*away) or 1
            key = id(it)
            blocker = min(math.dist(tight_pt, q) for q in sh) <= want / 2 + 0.3
            prev = jobs.get(key)
            if prev is None or need > prev[1]:
                jobs[key] = (it, need, (away[0] / L, away[1] / L), blocker or (prev[3] if prev else False))
    turned = []
    for h, p in doors:
        if h in turned:
            continue
        # turn the house to face open ground, if a turn fits
        best = None
        old = h["yaw"]
        for k in (1, -1, 2):
            h["yaw"] = old + k * math.pi / 2
            q = door_spot(h)
            r, c = cell(q)
            if 0 <= r < H and 0 <= c < W and clear[max(0, r - 2):r + 3, max(0, c - 2):c + 3].max() >= DOOR + 1 and fits(h, plan["houses"] + [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"]):
                best = h["yaw"]; break
        h["yaw"] = best if best is not None else old
        if best is not None:
            turned.append(h); did += 1; log["turned"] = log.get("turned", 0) + 1
    for h, p in doors:
        if h in turned:
            continue
        # what stands in front of the door: step it back from the doorstep
        for it in items:
            if it is h or "id" in it or len(it["design"]) > 1:
                continue
            sh = shape(it)
            dd = min(math.dist(p, q) for q in sh)
            if dd < DOOR + 3.0:
                # whatever stands within a few metres of a real home's front steps steps back (or goes)
                away = (it["x"] - p[0], it["z"] - p[1]); L = math.hypot(*away) or 1
                jobs[id(it)] = (it, DOOR + 3.0 - dd + 0.4, (away[0] / L, away[1] / L), True)
    all_items = plan["houses"] + [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"]
    for it, need, (ux, uz), blocker in sorted(jobs.values(), key=lambda j: -j[1]):
        if it not in plan["houses"]:
            continue
        cap = 2.0 if not it["filler"] else 4.0
        if moved_total.get(id(it), 0) >= cap - 0.05:
            if it["filler"] and blocker and id(it) not in tried:
                plan["houses"].remove(it); log["left out"].append(it); did += 1
            tried.add(id(it))
            continue
        step = min(need, cap - moved_total.get(id(it), 0))
        old = (it["x"], it["z"])
        it["x"] += ux * step; it["z"] += uz * step
        if fits(it, all_items):
            moved_total[id(it)] = moved_total.get(id(it), 0) + step
            log["stepped back"] += 1; did += 1
            if not it["filler"]:
                log["real homes moved"] += 1
        else:
            it["x"], it["z"] = old
            if it["filler"] and blocker and id(it) not in tried:
                plan["houses"].remove(it); log["left out"].append(it); did += 1
                all_items = plan["houses"] + [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"]
            tried.add(id(it))
    if not did:
        print("nothing more can be moved")
        break

for h in plan["houses"]:
    h["x"], h["z"] = round(h["x"], 2), round(h["z"], 2)
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
items, shapes, build, free, clear, mid = analyse()
left = narrow_places(clear, mid)
w = clear[mid & town]
print(f"background houses left out: {len(log['left out'])}; moves: {log['stepped back']} (real homes moved: {log['real homes moved']})")
stuck = door_problems(free, clear)
print(f"still narrow: {len(left)} places, {len(stuck)} doorsteps")
for h, p in stuck:
    near = sorted((min(math.dist(p, q) for q in shape(i)), i.get("id") or (i["design"].upper() + " " + (i.get("name") or ("vacant" if not i["filler"] else "background"))))
                  for i in plan["houses"] + plan["landmarks"] if i is not h and math.dist((i["x"], i["z"]), p) < 30)[:2]
    print(f"  doorstep of {h['design'].upper()} {h.get('name') or 'vacant'} at ({h['x']:.0f}, {h['z']:.0f}); in front: " + ", ".join(f"{n} {d:.1f} m" for d, n in near))
for cells, want in left:
    r, c = cells[len(cells) // 2]
    x, z = world(r, c)
    print(f"  ({x:.0f}, {z:.0f}): {clear[r, c]:.1f} m, wanted {want:.0f}")
print(f"street middles in town: median width {np.median(w):.1f} m; under {STREET:.0f} m on {np.mean(w < STREET) * 100:.0f}% (most of that: side gaps between houses in a row)")
