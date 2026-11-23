"""Town density plans (2026-11-17): a starting plan for each density setting, for HorseBucker to arrange in the planner.

usage: python tools/town_planner/make_density_plans.py <plan.json> [<out folder>]

The game will offer a town density setting (Minimum, Low, Medium, High) for weaker PCs. Each setting is its own
plan, made from the built plan (High is the built plan itself):

  setting   houses   vacant real homes to aim for
  minimum       75      8   (one of each design)
  low          130     16
  medium       190     32
  high         all     all the built plan has

- Every home a pony lives in stays where it is, a real home with its residents; so does every house the bunting
  is tied to (as it is).
- Every other house that stays becomes a background house: the planner shows how many vacant real homes the plan
  has against the setting's target (plan["density"]), and HorseBucker turns background houses into real ones (T).
- Which houses stay: the town is thinned evenly, keeping its streets lived-in rather than emptying whole blocks.
  A house stays if no house already kept stands within a spacing that grows as the setting gets sparser; among
  the candidates the ones nearer the middle of town and with a front door on a street come first. Lower settings
  are subsets of higher ones, so a house kept at Minimum is kept everywhere.
- Landmarks are not houses and are untouched; nor are roads, gardens' plan data or anything else.
Writes ponyville_plan<version>_<setting>.json beside the source unless a folder is given.
"""
import json, math, os, sys
import plan_geometry as G

SRC = sys.argv[1]
OUT_DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(SRC))
plan = json.load(open(SRC, encoding="utf-8"))
SETTINGS = [("minimum", 75, 8), ("low", 130, 16), ("medium", 190, 32)]
HOUSE = plan.get("design", {}).get("house", 0.9)

houses = plan["houses"]
small = [i for i, h in enumerate(houses) if len(h["design"]) == 1]
owned = [i for i in small if not houses[i].get("filler", True) and houses[i].get("residents")]
# houses the bunting is tied to (plan_props.py tie(): a string's end within 9 m of a house that is not by a banner
# or the Town Hall) stay at every setting, as they are
banners = [(n["x"], n["z"]) for n in plan.get("notes", []) if str(n.get("text", "")).strip().lower() == "banner"]
_hall = next(h for h in houses if h["design"] == "town_hall")
tied = []
for line in plan.get("railways", []):
    if line.get("name") != "bunting":
        continue
    for p in line["points"]:
        if any(math.dist(p, b) < 4.0 for b in banners) or math.dist(p, (_hall["x"], _hall["z"])) < 11.0:
            continue
        n = min(small, key=lambda i: math.dist(p, (houses[i]["x"], houses[i]["z"])))
        if math.dist(p, (houses[n]["x"], houses[n]["z"])) <= 9.0 and n not in tied:
            tied.append(n)
print("houses the bunting is tied to:", [(houses[i]["design"], houses[i]["x"], houses[i]["z"], "background" if houses[i].get("filler", True) else "real") for i in tied])
# houses only the full town has (2026-11-18: the A house right outside Golden Oak, at x 3 z -252, "looks odd being the
# only house on that street and blocking the view of Golden Oak" at the lower settings; a player whose home it is
# keeps it there, town_density.gd keep_homes)
HIGH_ONLY = [(2.37, -251.89), (14.63, -249.55)]   # (and the E house beside it, which took its place when it went)
others = [i for i in small if i not in owned and not any(math.dist((houses[i]["x"], houses[i]["z"]), spot) < 0.5 for spot in HIGH_ONLY)]
hall = next(h for h in houses if h["design"] == "town_hall")
centre = (hall["x"], hall["z"])
streets = [r for r in plan["roads"] if r.get("type", "town") == "town" and len(r["points"]) > 1]


def score(i):
    """Higher keeps first: near the middle of town, and a front door on a street."""
    h = houses[i]
    door = G.door(h)
    on_street = min(G.line_dist(door, r["points"]) - r["width"] / 2 for r in streets)
    return -math.dist((h["x"], h["z"]), centre) / 300.0 - max(0.0, on_street - 4.0) / 12.0


order = sorted(others, key=score, reverse=True)
# one spare house of every design stays at every setting, so even Minimum can offer one home of each to move into
seeds = []
for design in sorted({houses[i]["design"] for i in others}):
    best = next((i for i in order if houses[i]["design"] == design), None)
    if best is not None and best not in tied: seeds.append(best)
total_now = len(small)


def thin(count, previous):
    """`count` houses: the owned ones, those kept at the sparser setting, then the best spaced of the rest."""
    kept = list(dict.fromkeys(owned + tied + seeds + previous))
    spacing = 60.0
    while len(kept) < count and spacing > 2.0:
        for i in order:
            if len(kept) >= count:
                break
            if i in kept:
                continue
            at = (houses[i]["x"], houses[i]["z"])
            if all(math.dist(at, (houses[k]["x"], houses[k]["z"])) >= spacing for k in kept):
                kept.append(i)
        spacing *= 0.85
    return kept


def write(name, kept, target, convert=True):
    out = json.loads(json.dumps(plan))
    keep = set(kept)
    out_houses = []
    for i, h in enumerate(out["houses"]):
        if len(h["design"]) != 1:
            out_houses.append(h)        # Sugarcube Corner, the Town Hall: landmarks
            continue
        if i not in keep:
            continue
        if i not in owned and i not in tied and convert:
            h["filler"] = True
            h.pop("vacant", None); h.pop("residents", None); h["name"] = ""
            h["scale"] = round(G.TOWN["designs"][h["design"]]["scale"] * HOUSE, 4)
        out_houses.append(h)
    out["houses"] = out_houses
    vacant = sum(1 for h in out_houses if len(h["design"]) == 1 and not h.get("filler", True) and not h.get("residents"))
    out["density"] = {"setting": name, "houses": sum(1 for h in out_houses if len(h["design"]) == 1), "vacant_target": target,
                      "note": "Town density setting (make_density_plans.py). Turn background houses into real homes (T) until the "
                              "planner's vacant count meets the target; homes ponies live in stay as they are."}
    out["built_from"] = os.path.basename(SRC) + " + make_density_plans.py (" + name + ")"
    base = os.path.splitext(os.path.basename(SRC))[0]
    path = os.path.join(OUT_DIR, f"{base}_{name}.json")
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    real = sum(1 for h in out_houses if len(h["design"]) == 1 and not h.get("filler", True))
    print(f"{name:8s} {out['density']['houses']:4d} houses: {real} real ({len(owned)} lived in, {vacant} vacant; target {target}), "
          f"{out['density']['houses'] - real} background -> {path}")


previous = []
for name, count, target in SETTINGS:
    previous = thin(count, previous)
    write(name, previous, target)
# high: the built plan as it is, with its own target
vacant_now = sum(1 for i in small if not houses[i].get("filler", True) and not houses[i].get("residents"))
write("high", list(range(len(houses))), vacant_now, convert=False)
