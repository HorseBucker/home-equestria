"""How wide the streets are: free ground between buildings (roofs, porches and steps included), with
gaps narrower than ALLEY between neighbours counted as part of the row, not as a street.

usage: python tools/town_planner/street_check.py <plan.json> <picture.png> [--around x z radius]
Prints the street widths along the middle of every street, and draws them: red under 4 m, orange 4-6,
yellow 6-8, green 8 m and over.
"""
import json, math, sys
import cv2, numpy as np
from scipy import ndimage

SRC, PIC = sys.argv[1], sys.argv[2]
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
plan = json.load(open(SRC, encoding="utf-8"))
tj = open(HERE + "/data/town.js", encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
SCEN = {s["id"]: s for s in TOWN["scenery"]}
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}
ALLEY = 3.0
RES = 0.5


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


g = np.array(plan["edges"][0]["points"])
X0, Z0 = g[:, 0].min(), g[:, 1].min()
X1, Z1 = g[:, 0].max(), g[:, 1].max()
W, H = int((X1 - X0) / RES) + 1, int((Z1 - Z0) / RES) + 1


def px(pts):
    return np.round((np.array(pts) - [X0, Z0]) / RES * 8).astype(np.int32)


def fill(polys):
    m = np.zeros((H, W), np.uint8)
    for p in polys:
        cv2.fillPoly(m, [px(p)], 1, shift=3)
    return m.astype(bool)


items = [h for h in plan["houses"]] + [l for l in plan["landmarks"] if l["id"] != "cloudominium_01"]
build = fill([shape(i) for i in items])
water = np.zeros((H, W), np.uint8)
for r in plan["rivers"]:
    cv2.polylines(water, [px(r["points"])], False, 1, max(1, int(round(r["width"] / RES))), shift=3)
water = water.astype(bool) | fill([l["points"] for l in plan["lakes"]])
deck = np.zeros((H, W), np.uint8)
for b in plan["bridges"]:
    cv2.polylines(deck, [px([b["a"], b["b"]])], False, 1, max(1, int(round(b["width"] / RES))), shift=3)
water &= ~deck.astype(bool)
town = fill([gr["points"] for gr in plan["grounds"]])
area = np.ones((H, W), bool)
# rows: gaps under ALLEY between buildings close up
k = int(round(ALLEY / 2 / RES))
rows = ndimage.binary_closing(build, structure=np.ones((3, 3)), iterations=k) | build
free = area & ~rows & ~water
clear = ndimage.distance_transform_edt(free) * RES * 2         # street width at each spot (2 x distance to the nearest wall)


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


# the middles of the streets: the skeleton of the free ground, inside the town and its edge
mid = thin(free & (clear >= 2.0)) & ndimage.binary_dilation(town, iterations=int(6 / RES))
w = clear[mid]
print(f"street middles: {int(mid.sum() * RES)} m; width there: under 4 m {np.mean(w < 4) * 100:.0f}%, 4-6 m {np.mean((w >= 4) & (w < 6)) * 100:.0f}%, "
      f"6-8 m {np.mean((w >= 6) & (w < 8)) * 100:.0f}%, 8 m+ {np.mean(w >= 8) * 100:.0f}%; median {np.median(w):.1f} m")
# picture
img = np.full((H, W, 3), (60, 90, 60), np.uint8)
img[town] = (150, 178, 160)
img[water] = (200, 120, 50)
img[rows & ~build] = (120, 130, 120)
img[build] = (90, 90, 100)
col = np.zeros((H, W, 3), np.uint8)
for lo, hi, c in ((0, 4, (0, 0, 230)), (4, 6, (0, 140, 255)), (6, 8, (0, 230, 230)), (8, 999, (0, 200, 0))):
    sel = ndimage.binary_dilation(mid & (clear >= lo) & (clear < hi), iterations=2)
    img[sel] = c
cv2.imwrite(PIC, img)
# ---- the widest way from every spot to the town centre (in front of the Town Hall) ----
hall = next((h for h in plan["houses"] if h["design"] == "town_hall"), None)
cz_, cx_ = (int(round((hall["z"] - Z0) / RES)), int(round((hall["x"] + 14 - X0) / RES))) if hall else (H // 2, W // 2)
route = np.zeros((H, W), np.float32)
for t in np.arange(1.0, 12.01, 0.5):
    lab, _ = ndimage.label(free & (clear >= t))
    k = lab[cz_, cx_]
    if k:
        route[lab == k] = t


def way_out(p, reach=4.0):
    r, c = int(round((p[1] - Z0) / RES)), int(round((p[0] - X0) / RES)); n = int(reach / RES)
    win = route[max(0, r - n):r + n + 1, max(0, c - n):c + n + 1]
    return float(win.max()) if win.size else 0.0


towns = ndimage.binary_dilation(town, iterations=int(30 / RES))
EXITS = []
for r in plan["roads"]:
    for p in (r["points"][0], r["points"][-1]):
        EXITS.append(("road", p))
for b in plan["bridges"]:
    EXITS.append(("bridge", b["a"])); EXITS.append(("bridge", b["b"]))
EXITS = [(k, p) for k, p in EXITS if 0 <= (p[1] - Z0) / RES < H and 0 <= (p[0] - X0) / RES < W and towns[int((p[1] - Z0) / RES), int((p[0] - X0) / RES)]]
DOORS = []
for h in plan["houses"]:
    if len(h["design"]) > 1:
        continue
    d = TOWN["designs"][h["design"]]; k = h.get("scale") or d["scale"]
    c, s = math.cos(h["yaw"]), math.sin(h["yaw"])
    lx, lz = d["door"][0] * k, d["door"][1] * k + 3.0
    DOORS.append((h, (h["x"] + lx * c + lz * s, h["z"] - lx * s + lz * c)))
ex_w = [(k, p, way_out(p, 8.0)) for k, p in EXITS]
door_w = [(h, p, way_out(p)) for h, p in DOORS]
print("ways in from the roads and bridges near town: narrowest", sorted(round(w, 1) for _, _, w in ex_w)[:8])
print("front doors: way out to the centre narrower than 3 m:", sum(1 for _, _, w in door_w if w < 3), "of", len(door_w),
      "| narrower than 4 m:", sum(1 for _, _, w in door_w if w < 4))
for k, p, w in sorted(ex_w, key=lambda e: e[2])[:12]:
    if w < 5:
        print(f"  {k} end at ({p[0]:.0f}, {p[1]:.0f}): {w:.1f} m")
np.savez_compressed(PIC + ".npz", route=route, clear=clear, mid=mid, rows=rows, build=build, town=town, water=water, origin=[X0, Z0], res=RES)
