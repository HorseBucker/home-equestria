"""V15 density plans (2026-11-17): each density plan with its vacant real homes filled in to the target.

usage: python tools/town_planner/fill_vacant_homes.py <plan_minimum.json> ... (writes ..V15_<setting>.json beside it)

A density plan (make_density_plans.py) keeps every lived-in home and makes every other house a background one; this
turns background houses into vacant real homes until plan["density"]["vacant_target"] is met:
- the mix of designs per setting (MIX): one of each design at Minimum, then mostly the designs with rooms (g, h,
  f, a), few of b and c (only a bed inside) and d;
- of a design, the background house that stands best: its front door on a street, then the one farthest from every
  real home so far, so the homes to move into are spread through town;
- not a house the bunting is tied to, and not one that would overlap a neighbour once grown to a real home's size
  (plan.design.home against .house).
A plan already at its target is copied as it is. The High plan is the built town and already meets its target.
"""
import json, math, os, re, sys
import plan_geometry as G

MIX = {"minimum": {"a": 1, "b": 1, "c": 1, "d": 1, "e": 1, "f": 1, "g": 1, "h": 1},
       "low": {"a": 3, "b": 1, "c": 1, "d": 1, "e": 1, "f": 3, "g": 3, "h": 3},
       "medium": {"a": 6, "b": 1, "c": 1, "d": 1, "e": 3, "f": 6, "g": 7, "h": 7}}
GOOD = ["g", "h", "f", "a", "e"]

for src in sys.argv[1:]:
    plan = json.load(open(src, encoding="utf-8"))
    dens = plan.get("density", {})
    name = dens.get("setting", "")
    target = int(dens.get("vacant_target", 0))
    houses = plan["houses"]
    home_k, house_k = plan.get("design", {}).get("home", 0.95), plan.get("design", {}).get("house", 0.9)
    streets = [r for r in plan["roads"] if r.get("type", "town") == "town" and len(r["points"]) > 1]
    banners = [(n["x"], n["z"]) for n in plan.get("notes", []) if str(n.get("text", "")).strip().lower() == "banner"]
    hall = next(h for h in houses if h["design"] == "town_hall")
    tied = set()
    for line in plan.get("railways", []):
        if line.get("name") != "bunting":
            continue
        for p in line["points"]:
            if any(math.dist(p, b) < 4.0 for b in banners) or math.dist(p, (hall["x"], hall["z"])) < 11.0:
                continue
            n = min((i for i, h in enumerate(houses) if len(h["design"]) == 1), key=lambda i: math.dist(p, (houses[i]["x"], houses[i]["z"])))
            if math.dist(p, (houses[n]["x"], houses[n]["z"])) <= 9.0:
                tied.add(n)
    real = [i for i, h in enumerate(houses) if len(h["design"]) == 1 and not h.get("filler", True)]
    vacant = [i for i in real if not houses[i].get("residents")]
    want = MIX.get(name, {})
    picked = []

    def grown(h):
        return dict(h, filler=False, scale=round(G.TOWN["designs"][h["design"]]["scale"] * home_k, 4))

    def fits(i):
        g = grown(houses[i]); s = G.shape(g)
        return all(G.gap(s, G.shape(o)) >= 0.2 for j, o in enumerate(houses) if j != i and math.dist((o["x"], o["z"]), (g["x"], g["z"])) < 30)

    def candidates(design):
        out = [i for i, h in enumerate(houses) if h["design"] == design and h.get("filler", True) and i not in tied and i not in picked and fits(i)]
        def key(i):
            door = G.door(houses[i])
            on_street = min(G.line_dist(door, r["points"]) - r["width"] / 2 for r in streets)
            spread = min([math.dist((houses[i]["x"], houses[i]["z"]), (houses[j]["x"], houses[j]["z"])) for j in real + picked] or [999.0])
            return (on_street > 5.0, -spread)
        return sorted(out, key=key)

    for design, count in want.items():
        for _ in range(count):
            if len(vacant) + len(picked) >= target:
                break
            c = candidates(design)
            if c:
                picked.append(c[0])
    # short of a design: the next of the roomier designs
    while len(vacant) + len(picked) < target:
        c = next((cands for d in GOOD for cands in [candidates(d)] if cands), None)
        if not c:
            break
        picked.append(c[0])
    for i in picked:
        houses[i].update(filler=False, scale=round(G.TOWN["designs"][houses[i]["design"]]["scale"] * home_k, 4), name="")
        houses[i].pop("residents", None)
    plan["version"] = 15
    plan["built_from"] = os.path.basename(src) + " + fill_vacant_homes.py"
    out = re.sub(r"V\d+_", "V15_", os.path.basename(src))
    path = os.path.join(os.path.dirname(os.path.abspath(src)), out)
    json.dump(plan, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    now = sum(1 for h in houses if len(h["design"]) == 1 and not h.get("filler", True) and not h.get("residents"))
    designs = {}
    for i in picked:
        designs[houses[i]["design"]] = designs.get(houses[i]["design"], 0) + 1
    n = sum(1 for h in houses if len(h["design"]) == 1)
    print(f"{name:8s} {n} houses: {now} vacant real homes (target {target}; made real here {dict(sorted(designs.items()))}), "
          f"{sum(1 for h in houses if len(h['design']) == 1 and h.get('filler', True))} background -> {out}")
