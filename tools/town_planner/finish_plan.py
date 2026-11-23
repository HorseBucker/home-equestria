"""The last small fixes to a plan drawn in the planner, before it is built.

usage: python tools/town_planner/finish_plan.py <plan.json> <out.json> [--drop-bridge x z]...

- `--drop-bridge x z`: the bridge nearest that spot is taken out.
- A bridge end with no road or street within 4 m gets a short lane to the nearest town street.
- A bridge more than 12 degrees off square: the bridge stays as drawn and the stream is straightened for 5 m
  either side so it runs square under it.
- Roofs that overlap or nearly touch ease apart (background houses give way first, at most 2.5 m, never into a
  street, a landmark or the water).
- Landmarks that overlap ease apart the same way (the smaller one moves).
- A pony named in a house of her own is not also a resident of Sugarcube Corner (no beds there).
Prints what it did; check_plan.py then checks the result.
"""
import json, math, sys
from plan_geometry import TOWN, shape, gap, line_dist, probes, wet, turn, house_scale, seg_point, along, inside

SRC, OUT = sys.argv[1], sys.argv[2]
plan = json.load(open(SRC, encoding="utf-8"))
H, L = plan["houses"], plan["landmarks"]
streets = [r for r in plan["roads"] if r.get("type", "town") == "town"]
dirt = [r for r in plan["roads"] if r.get("type") == "dirt"]

# ---- bridges ----
i = 3
while i < len(sys.argv):
    if sys.argv[i] == "--drop-bridge":
        at = (float(sys.argv[i + 1]), float(sys.argv[i + 2]))
        b = min(plan["bridges"], key=lambda b: math.dist(at, ((b["a"][0] + b["b"][0]) / 2, (b["a"][1] + b["b"][1]) / 2)))
        plan["bridges"].remove(b)
        print(f"bridge at ({(b['a'][0] + b['b'][0]) / 2:.0f}, {(b['a'][1] + b['b'][1]) / 2:.0f}) taken out")
        i += 3
    else:
        i += 1
for b in plan["bridges"]:
    mid = [(b["a"][0] + b["b"][0]) / 2, (b["a"][1] + b["b"][1]) / 2]
    r = min(plan["rivers"], key=lambda r: line_dist(mid, r["points"]))
    line = along(r["points"], 1.0)
    near = min(line, key=lambda p: math.dist(p[:2], mid))
    span = [p for p in line if abs(p[4] - near[4]) <= 10.0]
    tx, tz = span[-1][0] - span[0][0], span[-1][1] - span[0][1]; n = math.hypot(tx, tz) or 1
    dx, dz = b["b"][0] - b["a"][0], b["b"][1] - b["a"][1]; m = math.hypot(dx, dz) or 1
    skew = math.degrees(math.asin(min(1.0, abs((tx * dx + tz * dz) / (n * m)))))
    if skew > 12:
        # the stream square under the bridge: its points within 6 m of the deck's middle make way for a straight 10 m
        t = [dz / m, -dx / m]
        if t[0] * tx + t[1] * tz < 0:
            t = [-t[0], -t[1]]
        keep_a = [p for p in r["points"] if (p[0] - mid[0]) * t[0] + (p[1] - mid[1]) * t[1] < -6.0 and math.dist(p, mid) < 400]
        first = next(k for k, p in enumerate(r["points"]) if math.dist(p, mid) <= 6.5 or (p[0] - mid[0]) * t[0] + (p[1] - mid[1]) * t[1] > -6.0 and math.dist(p, mid) < 12)
        last = max(k for k, p in enumerate(r["points"]) if math.dist(p, mid) <= 6.5 or (k >= first and (p[0] - mid[0]) * t[0] + (p[1] - mid[1]) * t[1] < 6.0 and math.dist(p, mid) < 12))
        flip = (r["points"][min(last + 1, len(r["points"]) - 1)][0] - r["points"][max(first - 1, 0)][0]) * t[0] + \
               (r["points"][min(last + 1, len(r["points"]) - 1)][1] - r["points"][max(first - 1, 0)][1]) * t[1] < 0
        s = -1 if flip else 1
        new = [[round(mid[0] - t[0] * 5 * s, 2), round(mid[1] - t[1] * 5 * s, 2)], [round(mid[0] + t[0] * 5 * s, 2), round(mid[1] + t[1] * 5 * s, 2)]]
        r["points"] = r["points"][:first] + new + r["points"][last + 1:]
        print(f"bridge at ({mid[0]:.0f}, {mid[1]:.0f}) was {skew:.0f} degrees off square: the stream now runs straight under it")
    for k in ("a", "b"):
        ways = streets + dirt
        d = min(min(math.dist(w["points"][0], b[k]), math.dist(w["points"][-1], b[k]), line_dist(b[k], w["points"])) for w in ways)
        if d <= 4:
            continue
        s = min(streets, key=lambda s: line_dist(b[k], s["points"]))
        q = min((seg_point(b[k], s["points"][j], s["points"][j + 1]) for j in range(len(s["points"]) - 1)), key=lambda v: v[0])[1]
        if math.dist(q, b[k]) > 25:
            print(f"bridge end at ({b[k][0]:.0f}, {b[k][1]:.0f}): no street within 25 m; left alone"); continue
        out = [(b[k][0] - mid[0]), (b[k][1] - mid[1])]; ln = math.hypot(*out) or 1
        lane = {"type": "town", "name": "Bridge Lane", "width": 4.0,
                "points": [[round(b[k][0] - out[0] / ln * 0.4, 2), round(b[k][1] - out[1] / ln * 0.4, 2)], [round(q[0], 2), round(q[1], 2)]]}
        plan["roads"].append(lane); streets.append(lane)
        print(f"bridge end at ({b[k][0]:.0f}, {b[k][1]:.0f}): a {math.dist(q, b[k]):.0f} m lane to {s.get('name', 'the street')}")


# ---- roofs and landmarks apart ----
def walls(h):
    d = TOWN["designs"][h["design"]]; k = house_scale(h)
    return [[h["x"] + p[0], h["z"] + p[1]] for p in turn([[q[0] * k, q[1] * k] for q in d["footprint"]], h["yaw"])]


def stands(h, others):
    sh = shape(h)
    for o in others:
        if o is not h and abs(o["x"] - h["x"]) < 45 and abs(o["z"] - h["z"]) < 45 and gap(sh, shape(o)) < (0.8 if "id" in o else 0.3):
            return False
    pr = probes(walls(h))
    for s in streets:
        if min(line_dist(p, s["points"]) for p in pr) < s["width"] / 2 - 0.3:
            return False
    for r in dirt:
        if min(line_dist(p, r["points"]) for p in pr) < r["width"] / 2 + 0.2:
            return False
    return wet(plan, sh, 0.5) <= 0


fixed_l = [l for l in L if l["id"] != "cloudominium_01"]
for round_ in range(6):
    pairs = []
    for a in range(len(H)):
        for c in range(a + 1, len(H)):
            if abs(H[a]["x"] - H[c]["x"]) < 26 and abs(H[a]["z"] - H[c]["z"]) < 26:
                g = gap(shape(H[a]), shape(H[c]))
                if g < 0.3:
                    pairs.append((g, H[a], H[c]))
    if not pairs:
        break
    for g, p, q in sorted(pairs, key=lambda v: v[0]):
        g = gap(shape(p), shape(q))
        if g >= 0.3:
            continue
        need = 0.35 - g
        dx, dz = q["x"] - p["x"], q["z"] - p["z"]; ln = math.hypot(dx, dz) or 1
        movers = sorted([(q, 1), (p, -1)], key=lambda v: (not v[0].get("filler"), len(v[0]["design"]) > 1))
        done = False
        # one house gives way; failing that both share it; along the line between them, or a little to either side
        for share in ((1.0, 0.0), (0.5, 0.5), (0.0, 1.0)):
            for bend in (0.0, 0.5, -0.5, 1.0, -1.0):
                c, s = math.cos(bend), math.sin(bend)
                ux, uz = (dx * c - dz * s) / ln, (dx * s + dz * c) / ln
                extra = 1.0 / max(0.3, math.cos(bend))
                was = [(h["x"], h["z"]) for h, _ in movers]
                for (h, sign), part in zip(movers, share):
                    h["x"] += ux * sign * need * part * extra; h["z"] += uz * sign * need * part * extra
                if need * extra <= 2.5 and all(stands(h, H + fixed_l) for (h, _), part in zip(movers, share) if part) and gap(shape(p), shape(q)) >= 0.3:
                    done = True; break
                for (h, _), w in zip(movers, was):
                    h["x"], h["z"] = w
            if done:
                break
        name = lambda h: (h.get("name") or ("vacant home " if not h.get("filler") else "background ") + h["design"]) + f" ({h['x']:.0f}, {h['z']:.0f})"
        print(("eased apart: " if done else "COULD NOT ease apart: ") + f"{name(p)} and {name(q)} (roofs were {g:+.2f} m)")
for h in H:
    h["x"], h["z"] = round(h["x"], 2), round(h["z"], 2)
for a in range(len(fixed_l)):
    for c in range(a + 1, len(fixed_l)):
        p, q = fixed_l[a], fixed_l[c]
        if math.dist((p["x"], p["z"]), (q["x"], q["z"])) < 40:
            g = gap(shape(p), shape(q))
            if g < 0.5:
                small = min((p, q), key=lambda l: max(math.dist(v, (l["x"], l["z"])) for v in shape(l)))
                other = q if small is p else p
                dx, dz = small["x"] - other["x"], small["z"] - other["z"]; ln = math.hypot(dx, dz) or 1
                for _ in range(40):
                    if gap(shape(small), shape(other)) >= 0.6:
                        break
                    small["x"] += dx / ln * 0.1; small["z"] += dz / ln * 0.1
                small["x"], small["z"] = round(small["x"], 2), round(small["z"], 2)
                print(f"landmarks eased apart: {small['id']} away from {other['id']} (were {g:+.2f} m)")

# ---- one home each ----
own = {r for h in H if len(h["design"]) == 1 for r in (h.get("residents") or [])}
for h in H:
    if h["design"] == "sugarcube" and h.get("residents"):
        stay = [r for r in h["residents"] if r not in own]
        if stay != h["residents"]:
            print("Sugarcube Corner: no longer the home of", ", ".join(r for r in h["residents"] if r in own))
            h["residents"] = stay
plan["built_from"] = SRC.replace("\\", "/").rsplit("/", 1)[-1]
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
