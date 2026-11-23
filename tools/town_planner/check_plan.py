"""Check a plan before it is built: will everything stand clear, and can everything be reached on foot?

usage: python tools/town_planner/check_plan.py <plan.json> [<picture.png>]

- roofs: houses whose roofs overlap or nearly touch; houses against landmarks
- in the way: houses standing in a town street, a square, a dirt road, a bridge approach, the railway or water;
  landmarks in water or a street
- on foot: from the Town Square, over ground a pony can walk (not through walls, landmarks or water; bridges
  cross), can every real home's doorstep and every landmark be reached, and is every doorstep clear
- bridges: both ends on dry land, the deck square across the river, a road or street at each end
- homes: residents named twice, a vacant home of every design, house sizes
The picture marks each problem in red on the plan.
"""
import json, math, sys, collections
import numpy as np, cv2
from scipy import ndimage
from plan_geometry import TOWN, SCEN, MODEL, shape, gap, line_dist, inside, probes, wet, turn, house_scale, door, seg_point, along, front_of

plan = json.load(open(sys.argv[1], encoding="utf-8"))
PIC = sys.argv[2] if len(sys.argv) > 2 else None
H = plan["houses"]; L = plan["landmarks"]
streets = [r for r in plan["roads"] if r.get("type", "town") == "town"]
dirt = [r for r in plan["roads"] if r.get("type") == "dirt"]
squares = plan.get("grounds", [])
marks = []           # (x, z, text)
problems = collections.OrderedDict()


def say(group, text, at=None):
    problems.setdefault(group, []).append(text)
    if at:
        marks.append((at[0], at[1], group))


def label(h):
    return (h.get("name") or ("vacant home " if not h.get("filler") else "background ") + h["design"]) + f" at ({h['x']:.0f}, {h['z']:.0f})"


def walls(h):
    """The house's walls (not its roof): what a pony cannot walk through."""
    d = TOWN["designs"][h["design"]]; k = house_scale(h)
    return [[h["x"] + p[0], h["z"] + p[1]] for p in turn([[q[0] * k, q[1] * k] for q in d["footprint"]], h["yaw"])]


# ---- roofs ----
shapes = [shape(h) for h in H]
for i in range(len(H)):
    for j in range(i + 1, len(H)):
        if abs(H[i]["x"] - H[j]["x"]) < 26 and abs(H[i]["z"] - H[j]["z"]) < 26:
            g = gap(shapes[i], shapes[j])
            if g < 0.25:
                wg = gap(walls(H[i]), walls(H[j]))
                say("roofs overlap" if g < -0.05 else "roofs nearly touch (under 0.25 m)",
                    f"{label(H[i])} and {label(H[j])}: roofs {g:+.2f} m, walls {wg:+.2f} m", ((H[i]["x"] + H[j]["x"]) / 2, (H[i]["z"] + H[j]["z"]) / 2))
lshapes = [shape(l) for l in L]
for i, l in enumerate(L):
    if l["id"] == "cloudominium_01":
        continue
    for j, h in enumerate(H):
        if abs(l["x"] - h["x"]) < 45 and abs(l["z"] - h["z"]) < 45:
            g = gap(lshapes[i], shapes[j])
            if g < 0.8:
                say("house against a landmark (under 0.8 m)", f"{label(h)} and {l['id']}: {g:+.2f} m", (h["x"], h["z"]))
    for j in range(i + 1, len(L)):
        if L[j]["id"] != "cloudominium_01" and math.dist((l["x"], l["z"]), (L[j]["x"], L[j]["z"])) < 60 and gap(lshapes[i], lshapes[j]) < 0.3:
            say("landmarks overlap", f"{l['id']} and {L[j]['id']}: {gap(lshapes[i], lshapes[j]):+.2f} m", (l["x"], l["z"]))

# ---- in the way ----
for h, sh in zip(H, shapes):
    pr = probes(walls(h))
    for s in streets:
        d = min(line_dist(p, s["points"]) for p in pr) - s["width"] / 2
        if d < -0.4:
            say("house walls in a town street", f"{label(h)}: {-d:.1f} m into {s.get('name', 'a street')}", (h["x"], h["z"]))
    for r in dirt:
        d = min(line_dist(p, r["points"]) for p in pr) - r["width"] / 2
        if d < 0:
            say("house walls on a dirt road", f"{label(h)}: {-d:.1f} m into {r.get('name', 'a road')}", (h["x"], h["z"]))
    w = wet(plan, sh, 0.5)
    if w > 0:
        say("house in or at the water", f"{label(h)}: roof within {0.5 - w:.1f} m of the water" if w < 0.5 else f"{label(h)}: roof over the water", (h["x"], h["z"]))
    for r in plan.get("railways", []):
        if r.get("name") == "bunting":
            continue
        if min(line_dist(p, r["points"]) for p in pr) < 3.0:
            say("house on the railway", label(h), (h["x"], h["z"]))
    for b in plan.get("bridges", []):
        if min(seg_point(p, b["a"], b["b"])[0] for p in pr) < b.get("width", 3) / 2 + 0.5:
            say("house on a bridge", label(h), (h["x"], h["z"]))
for l, sh in zip(L, lshapes):
    if l["id"] == "cloudominium_01":
        continue
    if wet(plan, sh, 0.0) > 0:
        say("landmark in the water", l["id"], (l["x"], l["z"]))
    for s in streets:
        d = min(line_dist(p, s["points"]) for p in probes(sh)) - s["width"] / 2
        if d < -1.0 and not any(inside(q["points"], [l["x"], l["z"]]) for q in squares):
            say("landmark in a town street", f"{l['id']}: {-d:.1f} m into {s.get('name', 'a street')}", (l["x"], l["z"]))

# ---- on foot ----
RES = 0.5
edge = plan["edges"][0]["points"]
x0, x1 = min(p[0] for p in edge), max(p[0] for p in edge); z0, z1 = min(p[1] for p in edge), max(p[1] for p in edge)
NX, NZ = int((x1 - x0) / RES), int((z1 - z0) / RES)


def P(pts):
    return np.round(np.array([[(p[0] - x0) / RES, (p[1] - z0) / RES] for p in pts]) * 8).astype(np.int32)


solid = np.zeros((NZ, NX), np.uint8)
for h in H:
    cv2.fillPoly(solid, [P(walls(h))], 1, shift=3)
for l, sh in zip(L, lshapes):
    if l["id"] != "cloudominium_01":
        cv2.fillPoly(solid, [P(sh)], 1, shift=3)
water = np.zeros((NZ, NX), np.uint8)
for r in plan["rivers"]:
    cv2.polylines(water, [P(r["points"])], False, 1, max(1, int(round(r["width"] / RES))), shift=3)
for l in plan["lakes"]:
    cv2.fillPoly(water, [P(l["points"])], 1, shift=3)
deck = np.zeros((NZ, NX), np.uint8)
for b in plan.get("bridges", []):
    d = [b["b"][0] - b["a"][0], b["b"][1] - b["a"][1]]; n = math.hypot(*d) or 1
    a = [b["a"][0] - d[0] / n * 1.5, b["a"][1] - d[1] / n * 1.5]; c = [b["b"][0] + d[0] / n * 1.5, b["b"][1] + d[1] / n * 1.5]
    cv2.polylines(deck, [P([a, c])], False, 1, max(1, int(round(b.get("width", 3) / RES))), shift=3)
blocked = (solid.astype(bool) | (water.astype(bool) & ~deck.astype(bool)))
BODY = 0.6            # a pony's half width
free = ~ndimage.binary_dilation(blocked & ~deck.astype(bool), iterations=int(round(BODY / RES))) | (deck.astype(bool) & ~solid.astype(bool))
parts, _ = ndimage.label(free, structure=np.ones((3, 3)))


def cell(p):
    return min(NZ - 1, max(0, int((p[1] - z0) / RES))), min(NX - 1, max(0, int((p[0] - x0) / RES)))


hall = next((h for h in H if h["design"] == "town_hall"), None)
start = None
if squares:
    sq = max(squares, key=lambda s: len(s["points"]))
    c = [sum(p[0] for p in sq["points"]) / len(sq["points"]), sum(p[1] for p in sq["points"]) / len(sq["points"])]
    zz, xx = np.nonzero(free)
    k = np.argmin((xx * RES + x0 - c[0]) ** 2 + (zz * RES + z0 - c[1]) ** 2)
    start = parts[zz[k], xx[k]]
main = parts == start


def reachable(p, reach=1.5):
    r, c = cell(p); k = int(reach / RES)
    return bool(main[max(0, r - k):r + k + 1, max(0, c - k):c + k + 1].any())


for h in H:
    if h.get("filler") or h["design"] == "town_hall":
        continue
    d = door(h)
    out = turn([[0, 1]], h["yaw"])[0]
    step = [d[0] + out[0] * 1.6, d[1] + out[1] * 1.6]
    if not reachable(step, 1.0):
        say("real home's front door cannot be reached on foot", label(h), (h["x"], h["z"]))
    else:
        # how much open ground in front of the door
        ahead = 0.0
        while ahead < 6 and not blocked[cell([d[0] + out[0] * (1.3 + ahead), d[1] + out[1] * (1.3 + ahead)])]:
            ahead += 0.5
        if ahead < 2.5:
            say("real home's doorstep is tight (under 2.5 m of open ground ahead)", f"{label(h)}: {ahead:.1f} m", (h["x"], h["z"]))
    # is there a street within a short walk of the door
    near = min([line_dist(d, s["points"]) - s["width"] / 2 for s in streets] + [0.0 if inside(q["points"], d) else line_dist(d, q["points"] + q["points"][:1]) for q in squares] +
               [line_dist(d, r["points"]) - r["width"] / 2 for r in dirt])
    if near > 9:
        say("real home's door is more than 9 m from any street, square or road", f"{label(h)}: {near:.0f} m", (h["x"], h["z"]))
for l, sh in zip(L, lshapes):
    if l["id"] == "cloudominium_01":
        continue
    reach = max(math.dist(p, (l["x"], l["z"])) for p in sh) + 1.5
    f = l["yaw"] + front_of(l["id"])
    if not reachable([l["x"] + math.sin(f) * reach, l["z"] + math.cos(f) * reach], 2.5):
        say("landmark's front cannot be reached on foot", l["id"], (l["x"], l["z"]))
for a in plan.get("anchors", []):
    if blocked[cell([a["x"], a["z"]])] or not reachable([a["x"], a["z"]], 2.0):
        say("anchor is not on open, reachable ground", a.get("label", a["id"]), (a["x"], a["z"]))
    for h, sh in zip(H, shapes):
        if abs(h["x"] - a["x"]) < 20 and abs(h["z"] - a["z"]) < 20 and (inside(sh, [a["x"], a["z"]]) or line_dist([a["x"], a["z"]], sh + sh[:1]) < 1.2):
            say("anchor is under or against a roof", f"{a.get('label', a['id'])}: {label(h)}", (a["x"], a["z"]))
# streets a pony cannot get along: the middle of every street should be open
for s in streets:
    shut = [p for p in along(s["points"], 1.0) if blocked[cell(p)] and not deck[cell(p)]]
    if shut:
        say("town street blocked", f"{s.get('name', 'a street')}: {len(shut)} m of its middle, first at ({shut[0][0]:.0f}, {shut[0][1]:.0f})", shut[0][:2])
    cut = [p for p in along(s["points"], 1.0) if not main[cell(p)] and not blocked[cell(p)]]
    if len(cut) > 3:
        say("town street cut off from the square", f"{s.get('name', 'a street')}: {len(cut)} m, first at ({cut[0][0]:.0f}, {cut[0][1]:.0f})", cut[0][:2])

# ---- bridges ----
ways = streets + dirt
for b in plan.get("bridges", []):
    mid = [(b["a"][0] + b["b"][0]) / 2, (b["a"][1] + b["b"][1]) / 2]
    r = min(plan["rivers"], key=lambda r: line_dist(mid, r["points"]))
    line = along(r["points"], 1.0)
    near = min(line, key=lambda p: math.dist(p[:2], mid))
    span = [p for p in line if abs(p[4] - near[4]) <= 10.0]
    tx, tz = span[-1][0] - span[0][0], span[-1][1] - span[0][1]; n = math.hypot(tx, tz) or 1
    dx, dz = b["b"][0] - b["a"][0], b["b"][1] - b["a"][1]; m = math.hypot(dx, dz) or 1
    skew = abs(math.degrees(math.asin(min(1.0, abs((tx * dx + tz * dz) / (n * m))))))
    where = f"bridge at ({mid[0]:.0f}, {mid[1]:.0f})"
    if line_dist(mid, r["points"]) > r["width"] / 2 + 1:
        say("bridge is not over its river", f"{where}: its middle is {line_dist(mid, r['points']):.1f} m from the river's middle", mid)
    if skew > 12:
        say("bridge is askew (more than 12 degrees from square across)", f"{where}: {skew:.0f} degrees", mid)
    for k in ("a", "b"):
        if water[cell(b[k])]:
            say("bridge end is over the water", f"{where}: end at ({b[k][0]:.0f}, {b[k][1]:.0f})", b[k])
        d = min(min(math.dist(w["points"][0], b[k]), math.dist(w["points"][-1], b[k]), line_dist(b[k], w["points"])) for w in ways)
        if d > 4:
            say("no road or street at a bridge end", f"{where}: end at ({b[k][0]:.0f}, {b[k][1]:.0f}), nearest {d:.0f} m", b[k])

# ---- homes ----
seen = collections.Counter(r for h in H for r in (h.get("residents") or []))
for r, n in seen.items():
    if n > 1:
        say("resident named in more than one home", f"{r} x{n}")
real = [h for h in H if not h.get("filler")]
vacant = collections.Counter(h["design"] for h in real if not h.get("residents") and len(h["design"]) == 1)
for dsg in "abcdefgh":
    if not vacant.get(dsg):
        say("no vacant home of a design", dsg)
size = plan.get("design", {})
for h in H:
    if len(h["design"]) == 1 and size:
        want = TOWN["designs"][h["design"]]["scale"] * (size["house"] if h.get("filler") else size["home"])
        if abs(house_scale(h) - want) > 0.02:
            say("house size does not match its kind", f"{label(h)}: {house_scale(h) / TOWN['designs'][h['design']]['scale']:.2f} of full size, should be {(size['house'] if h.get('filler') else size['home']):.2f}", (h["x"], h["z"]))

print(f"{len(H)} houses: {len(real)} real homes ({len([h for h in real if h.get('residents')])} lived in, {sum(seen.values())} ponies; {sum(vacant.values())} vacant), "
      f"{len(H) - len(real)} background; {len(L)} landmarks; {len(streets)} streets, {len(dirt)} dirt roads, {len(plan.get('bridges', []))} bridges")
print("vacant homes by design:", dict(sorted(vacant.items())))
if not problems:
    print("no problems found")
for group, items in problems.items():
    print(f"\n{group}: {len(items)}")
    for t in items:
        print("  " + t)
if PIC:
    import subprocess, os
    here = os.path.dirname(os.path.abspath(__file__))
    PPM = 4.0
    cx = sum(h["x"] for h in H) / len(H); cz = sum(h["z"] for h in H) / len(H)
    subprocess.run([sys.executable, os.path.join(here, "render_plan.py"), sys.argv[1], PIC, "--around", str(cx), str(cz), "200", "--ppm", str(PPM)], check=True, stdout=subprocess.DEVNULL)
    img = cv2.imread(PIC)
    for x, z, group in marks:
        X, Z = int((x - (cx - 200)) * PPM), int((z - (cz - 200)) * PPM)
        cv2.circle(img, (X, Z), 14, (0, 0, 255), 2, cv2.LINE_AA)
    cv2.imwrite(PIC, img)
