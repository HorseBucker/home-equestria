"""Trace the official map's farms, flower meadow and trees into a plan.

usage: python tools/town_planner/trace_nature.py <plan.json> [<out.json>]

- plan["fields"]: outlines with a crop. The yellow striped fields are wheat (the Equestrian
  Heartlands, north-west) or carrots (round Carrot Top's farmhouse); Sweet Apple Acres (S4) gets its
  farmyard, its three dark striped plots (vegetable rows) and an apple orchard round the yard; the
  pink-and-lilac dotted meadow east of town (E6) is a flower meadow.
- plan["woods"]: how thick the trees grow, read from how close together the map draws its tree dots
  (and the solid Everfree): "scattered", "sparse", "medium", "dense" and "forest" outlines, the thicker inside the
  thinner. Town ground, water, roads, fields and buildings stay clear of trees whatever the outline.
Existing fields and woods in the plan are replaced.
"""
import json, math, sys
import cv2, numpy as np

SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else SRC
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
plan = json.load(open(SRC, encoding="utf-8"))
REF = plan["reference"]
im = cv2.imread(HERE + "/data/reference.jpg")
H, W = im.shape[:2]
MPP = REF["width"] / W
rgb = im[:, :, ::-1].astype(np.int32)
r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]


def near(c, t):
    return (np.abs(rgb - np.array(c)).sum(2) <= t).astype(np.uint8)


def ell(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def world(px, py):
    return [round(REF["x"] + (px - W / 2) * MPP, 1), round(REF["z"] + (py - H / 2) * MPP, 1)]


def pix(p):
    return (int(round((p[0] - REF["x"]) / MPP + W / 2)), int(round((p[1] - REF["z"]) / MPP + H / 2)))


def outlines(mask, min_m2, eps_m=2.0):
    out = []
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in contours:
        if cv2.contourArea(c) * MPP * MPP < min_m2:
            continue
        c = cv2.approxPolyDP(c, eps_m / MPP, True)
        if len(c) >= 3:
            out.append([world(p[0][0], p[0][1]) for p in c])
    return out


SKIP = np.zeros((H, W), np.uint8)
SKIP[0:340, 0:800] = 1; SKIP[1780:, 0:440] = 1                   # title, compass
SKIP[150:680, 930:1425] = 1; SKIP[300:440, 1440:1570] = 1         # R6 castle grounds, R7 (not in season 2)
lettering = np.zeros((H, W), np.uint8); lettering[580:740, 140:340] = 1

marks = {l["id"]: l for l in plan.get("landmarks", [])}
fields = []

# ---- yellow striped fields: wheat, or carrots by Carrot Top's farm ----
yellow = (near((240, 224, 76), 40) | near((216, 186, 84), 34) | near((248, 224, 88), 30)).astype(np.uint8) & (1 - SKIP)
yellow = cv2.morphologyEx(yellow, cv2.MORPH_CLOSE, ell(6))
yellow = cv2.morphologyEx(yellow, cv2.MORPH_OPEN, ell(5))
carrot_farm = marks.get("sweetappleacres_carrot_farmhouse_01")
for poly in outlines(yellow, 600, 1.5):
    cx = sum(p[0] for p in poly) / len(poly); cz = sum(p[1] for p in poly) / len(poly)
    crop = "carrots" if carrot_farm and math.dist((cx, cz), (carrot_farm["x"], carrot_farm["z"])) < 160 else "wheat"
    fields.append({"crop": crop, "points": poly})

# ---- Sweet Apple Acres: farmyard, the dark striped plots, an orchard round them ----
barn = marks.get("appleacres_barned_01")
if barn:
    bx, by = pix((barn["x"], barn["z"]))
    box = np.zeros((H, W), np.uint8)
    box[max(0, by - 260):by + 260, max(0, bx - 260):bx + 260] = 1
    sand = (near((224, 212, 124), 30) | near((224, 200, 146), 26)).astype(np.uint8) & box
    plots = near((44, 88, 32), 40) & box
    plots = cv2.morphologyEx(plots, cv2.MORPH_CLOSE, ell(7))
    yard = cv2.morphologyEx(sand | plots | (near((231, 203, 155), 45) & box), cv2.MORPH_CLOSE, ell(9))
    yard = cv2.morphologyEx(yard, cv2.MORPH_OPEN, ell(9))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(yard, connectivity=8)
    if n > 1:
        i = lab[by, bx] if lab[by, bx] else 1 + int(np.argmax(stats[1:, 4]))
        yard = (lab == i).astype(np.uint8)
    for poly in outlines(yard, 400, 2.0):
        fields.append({"crop": "farmyard", "points": poly})
    for poly in outlines(plots & cv2.dilate(yard, ell(4)), 150, 1.0):
        fields.append({"crop": "vegetable rows", "points": poly})
    orchard = cv2.dilate(yard, ell(int(55 / MPP))) & (1 - cv2.dilate(yard, ell(int(5 / MPP))))
    water = near((50, 143, 181), 50)
    orchard &= (1 - cv2.dilate(water, ell(int(6 / MPP)))) & (1 - cv2.dilate(near((222, 217, 122), 36), ell(int(4 / MPP))))
    for poly in outlines(orchard, 2000, 3.0):
        fields.append({"crop": "apple orchard", "points": poly})

# ---- flower meadow: where the pink and lilac dots are ----
flowers = ((r_ > 185) & (b_ > 165) & (g_ < 215) & (r_ - g_ > 25)).astype(np.uint8) & (1 - SKIP)
flowers = cv2.GaussianBlur(flowers.astype(np.float32), (0, 0), 14 / MPP) > 0.012
flowers = cv2.morphologyEx(flowers.astype(np.uint8), cv2.MORPH_OPEN, ell(9))
for poly in outlines(flowers, 3000, 4.0):
    fields.append({"crop": "flower meadow", "points": poly})

# ---- trees: how thick the dots are ----
dots = (near((34, 152, 70), 36) | near((40, 146, 64), 30)).astype(np.float32)
known = (1 - SKIP - lettering).clip(0, 1).astype(np.float32)
sig = 12 / MPP
dens = cv2.GaussianBlur(dots * known, (0, 0), sig) / np.maximum(cv2.GaussianBlur(known, (0, 0), sig), 1e-3)
# fill what the title, compass and the left-out castle hide from round about
far = cv2.GaussianBlur(dots * known, (0, 0), 4 * sig) / np.maximum(cv2.GaussianBlur(known, (0, 0), 4 * sig), 1e-3)
dens = np.where(known > 0, dens, far)
town = np.zeros((H, W), np.uint8)
for g in plan.get("grounds", []):
    cv2.fillPoly(town, [np.array([pix(p) for p in g["points"]], np.int32)], 1)
dens[cv2.dilate(town, ell(int(8 / MPP))) > 0] = 0
LEVELS = [("scattered", 0.025), ("sparse", 0.06), ("medium", 0.16), ("dense", 0.30), ("forest", 0.55)]
woods = []
for name, cut in LEVELS:
    m = cv2.morphologyEx((dens >= cut).astype(np.uint8), cv2.MORPH_OPEN, ell(int(6 / MPP)))
    for poly in outlines(m, 1500 if name not in ("sparse", "scattered") else 4000, 4.0):
        woods.append({"density": name, "points": poly})

plan["fields"] = fields
plan["woods"] = woods
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
from collections import Counter
print("fields", dict(Counter(f["crop"] for f in fields)))
print("woods", dict(Counter(w["density"] for w in woods)))
# tree cover by thirds of the map, north to south
z0, z1 = REF["z"] - H * MPP / 2, REF["z"] + H * MPP / 2
for k, part in enumerate(("north", "middle", "south")):
    rows = dens[int(H * k / 3):int(H * (k + 1) / 3)]
    print(f"  {part} third: trees cover about {rows.mean() * 100:.0f}%")
