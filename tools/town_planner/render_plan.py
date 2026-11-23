"""Draw a plan as a picture, for checking it without opening the planner.

usage: python tools/town_planner/render_plan.py <plan.json> <picture.png> [--around x z radius] [--ppm 2] [--labels]

Town ground sage, grass patches green, water blue, dirt roads brown, railway dark, bridges lilac, real homes
cream with a red door dot, background houses grey, landmarks purple with a red line out of their front.
"""
import json, math, sys
import cv2, numpy as np

SRC, PIC = sys.argv[1], sys.argv[2]
HERE = __file__.replace("\\", "/").rsplit("/", 1)[0]
plan = json.load(open(SRC, encoding="utf-8"))
tj = open(HERE + "/data/town.js", encoding="utf-8").read()
TOWN = json.loads(tj[tj.index("{"):tj.rindex("}") + 1])
SCEN = {s["id"]: s for s in TOWN["scenery"]}
sys.path.insert(0, HERE)
from plan_geometry import front_of
MODEL = {"a": (-.472, .472, -.5, .504), "b": (-.354, .354, -.438, .438), "c": (-.5, .5, -.417, .417), "d": (-.691, .691, -.703, .964),
         "e": (-.5, .5, -.286, .478), "f": (-.5, .5, -.335, .45), "g": (-.431, .431, -.5, .541), "h": (-.481, .481, -.5, .5)}
edge = plan["edges"][0]["points"]
x0, x1 = min(p[0] for p in edge), max(p[0] for p in edge); z0, z1 = min(p[1] for p in edge), max(p[1] for p in edge)
PPM = 2.0
if "--around" in sys.argv:
    i = sys.argv.index("--around"); cx, cz, r = (float(v) for v in sys.argv[i + 1:i + 4])
    x0, x1, z0, z1 = cx - r, cx + r, cz - r, cz + r; PPM = 6.0
if "--ppm" in sys.argv:
    PPM = float(sys.argv[sys.argv.index("--ppm") + 1])
LABELS = "--labels" in sys.argv
W, H = int((x1 - x0) * PPM), int((z1 - z0) * PPM)
img = np.full((H, W, 3), (120, 190, 130), np.uint8)


def P(pts):
    return np.array([[(p[0] - x0) * PPM, (p[1] - z0) * PPM] for p in pts], np.float32).round().astype(np.int32)


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
        a, b, c, e = MODEL[item["design"]]
        pts = [[a * k, c * k], [b * k, c * k], [b * k, e * k], [a * k, e * k]]
    else:
        pts = [[p[0] * k, p[1] * k] for p in d["footprint"]]
    return [[item["x"] + p[0], item["z"] + p[1]] for p in turn(pts, item["yaw"])]


def line(pts, colour, width):
    cv2.polylines(img, [P(pts)], False, colour, max(1, int(round(width * PPM))), cv2.LINE_AA)


for f in plan.get("fields", []): cv2.fillPoly(img, [P(f["points"])], (110, 170, 190))
for w in plan.get("woods", []): cv2.polylines(img, [P(w["points"])], True, (60, 130, 60), 1, cv2.LINE_AA)
for g in plan.get("grounds", []): cv2.fillPoly(img, [P(g["points"])], (200, 215, 185))
for g in plan.get("greens", []):
    cv2.fillPoly(img, [P(g["points"])], (120, 200, 135))
    for hole in g.get("holes", []): cv2.fillPoly(img, [P(hole)], (200, 215, 185))
for s in plan.get("streets", []): line(s["points"], (215, 228, 205), s.get("width", 4))
for r in plan.get("roads", []):
    if r.get("type") == "dirt": line(r["points"], (120, 160, 200), r.get("width", 2.5))
for r in plan.get("roads", []):
    if r.get("type") != "dirt": line(r["points"], (200, 215, 185), r.get("width", 4))
for r in plan.get("rivers", []): line(r["points"], (230, 150, 70), r["width"])
for l in plan.get("lakes", []): cv2.fillPoly(img, [P(l["points"])], (210, 120, 40) if l.get("spring") else (230, 150, 70))
for r in plan.get("railways", []):
    if r.get("name") == "bunting": line(r["points"], (200, 110, 170), 0.5)      # a string of pennants, not track
    else: line(r["points"], (60, 60, 70), 2.0)
for b in plan.get("bridges", []): line([b["a"], b["b"]], (220, 170, 210), b.get("width", 3))
for h in plan["houses"]:
    filler = h.get("filler")
    cv2.fillPoly(img, [P(shape(h))], (170, 170, 170) if filler else (200, 235, 250))
    cv2.polylines(img, [P(shape(h))], True, (90, 90, 90), 1, cv2.LINE_AA)
    d = TOWN["designs"][h["design"]]; k = h.get("scale") or d["scale"]
    door = turn([[d["door"][0] * k, d["door"][1] * k]], h["yaw"])[0]
    cv2.circle(img, tuple(P([[h["x"] + door[0], h["z"] + door[1]]])[0]), max(1, int(PPM * 0.5)), (40, 40, 220), -1)
    if LABELS and h.get("name"):
        cv2.putText(img, h["name"][:18], tuple(P([[h["x"] - 4, h["z"]]])[0]), cv2.FONT_HERSHEY_SIMPLEX, 0.3, (0, 0, 0), 1, cv2.LINE_AA)
for l in plan["landmarks"]:
    cv2.fillPoly(img, [P(shape(l))], (200, 130, 190))
    cv2.polylines(img, [P(shape(l))], True, (90, 40, 90), 1, cv2.LINE_AA)
    front = l["yaw"] + front_of(l["id"])
    tip = [l["x"] + math.sin(front) * 9, l["z"] + math.cos(front) * 9]
    cv2.line(img, tuple(P([[l["x"], l["z"]]])[0]), tuple(P([tip])[0]), (30, 30, 230), 2, cv2.LINE_AA)
    if LABELS:
        cv2.putText(img, l["id"][:22], tuple(P([[l["x"] - 6, l["z"] - 3]])[0]), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (60, 0, 60), 1, cv2.LINE_AA)
for p in plan.get("props", []):
    c = {"bench": (40, 90, 140), "streetlamp": (0, 220, 255), "tree": (40, 120, 40)}.get(p.get("kind"), (255, 255, 255))
    cv2.circle(img, tuple(P([[p["x"], p["z"]]])[0]), max(2, int(PPM * 0.8)), c, -1)
for a in plan.get("anchors", []):
    cv2.drawMarker(img, tuple(P([[a["x"], a["z"]]])[0]), (0, 0, 255), cv2.MARKER_DIAMOND, 10, 2)
for n in plan.get("notes", []):
    cv2.putText(img, n["text"], tuple(P([[n["x"], n["z"]]])[0]), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
# 50 m grid ticks with coordinates along the top and left
for gx in range(int(math.ceil(x0 / 50)) * 50, int(x1), 50):
    cv2.line(img, (int((gx - x0) * PPM), 0), (int((gx - x0) * PPM), 8), (0, 0, 0), 1)
    cv2.putText(img, str(gx), (int((gx - x0) * PPM) + 2, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 0, 0), 1, cv2.LINE_AA)
for gz in range(int(math.ceil(z0 / 50)) * 50, int(z1), 50):
    cv2.line(img, (0, int((gz - z0) * PPM)), (8, int((gz - z0) * PPM)), (0, 0, 0), 1)
    cv2.putText(img, str(gz), (10, int((gz - z0) * PPM) + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 0, 0), 1, cv2.LINE_AA)
cv2.imwrite(PIC, img)
print("drew", PIC, img.shape)
