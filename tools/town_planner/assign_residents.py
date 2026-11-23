"""Give every pony who lives in Ponyville in the game a real home in a plan.

usage: python tools/town_planner/assign_residents.py <project> <plan.json> [<out.json>]

Residents come from world/population/default_assignments.json (region "ponyville"); families who
share a house come from world/population/pony_households.gd. Ponies with their own building in the
game (the library, the boutique, the cottage, Sugarcube Corner, the Cloudominium, Trixie's wagon)
keep it. Everypony else gets one of the plan's houses, made a real home and named after them: near
the place they belong to where there is one (Cheerilee by the school, Nurse Redheart by the
hospital), the grandest house for Diamond Tiara, and spread through town otherwise.
"""
import json, math, re, sys

ROOT, SRC = sys.argv[1], sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 else SRC
plan = json.load(open(SRC, encoding="utf-8"))
assign = json.load(open(ROOT + "/world/population/default_assignments.json", encoding="utf-8"))["assignments"]
residents = sorted(k for k, v in assign.items() if v == "ponyville")
text = open(ROOT + "/world/population/pony_households.gd", encoding="utf-8").read()
block = text[text.index("const FAMILIES"):text.index("static func")]
families = [re.findall(r'"([a-z_]+)"', row) for row in re.findall(r"\[([^\[\]]+)\]", block)]

# ponies whose home is a building of its own in the game (world/buildings/homes.json, night_rest.gd SKY_HOMES,
# trixie_wagon.gd); the label is where they are in the plan
OWN = {"twilight_sparkle": "Golden Oak Library", "spike": "Golden Oak Library", "rarity": "Carousel Boutique",
       "sweetie_belle": "Carousel Boutique", "fluttershy": "Fluttershy's cottage", "pinkie_pie": "Sugarcube Corner",
       "rainbow_dash": "the Cloudominium", "trixie": "her wagon by the market"}
NAMES = {"drwhooves": "Dr. Hooves", "dr_caballeron": "Dr. Caballeron", "sweetie_drops": "Bon Bon", "mayor_mare": "Mayor Mare",
         "big_mcintosh": "Big McIntosh", "lyra_heartstrings": "Lyra Heartstrings", "octavia_melody": "Octavia Melody"}
# where a household belongs: a landmark id, or a design name of a special building
ANCHOR = {"applejack": "appleacres_barned_01", "cheerilee": "schoolhouse_01", "nurse_redheart": "general_hospital_01",
          "aloe": "spa_01", "lotus_blossom": "spa_01", "mayor_mare": "town_hall", "lyra_heartstrings": "sugarcube",
          "sweetie_drops": "sugarcube", "vinyl_scratch": "town_hall", "roseluck": "tent_friagram_red_01",
          "daisy": "tent_friagram_red_01", "lily_valley": "tent_friagram_red_01", "derpy_hooves": "schoolhouse_01",
          "silver_spoon": "@diamond_tiara", "starlight_glimmer": "goldenoaklibrary_01", "drwhooves": "trainstation_01"}
NEIGHBOURS_OK = {frozenset(["lyra_heartstrings", "sweetie_drops"]), frozenset(["aloe", "lotus_blossom"])}


def name(pid):
    return NAMES.get(pid, " ".join(w.capitalize() for w in pid.split("_")))


def household(pid):
    for f in families:
        if pid in f:
            return f
    return [pid]


homes = []
seen = set()
for pid in residents:
    if pid in seen or pid in OWN:
        continue
    fam = [m for m in household(pid) if m in residents]
    seen.update(fam)
    if any(m in OWN for m in fam):
        continue
    homes.append(fam)


def inside(poly, p):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
        j = i
    return hit


town = [g["points"] for g in plan.get("grounds", [])]
spots = {l["id"]: (l["x"], l["z"]) for l in plan.get("landmarks", [])}
spots.update({h["design"]: (h["x"], h["z"]) for h in plan["houses"] if len(h["design"]) > 1})
houses = plan["houses"]
size = {"a": 45, "b": 29, "c": 31, "d": 120, "e": 70, "f": 55, "g": 74, "h": 64}
free = [i for i, h in enumerate(houses) if len(h["design"]) == 1]
in_town = {i for i in free if any(inside(g, (houses[i]["x"], houses[i]["z"])) for g in town)}
taken = {}                       # house index -> household
SPREAD = 14.0


def pick(fam, near=None, best_key=None, town_only=True):
    ok = [i for i in free if i not in taken and (i in in_town or not town_only)]
    def crowded(i):
        for j, other in taken.items():
            if math.dist((houses[i]["x"], houses[i]["z"]), (houses[j]["x"], houses[j]["z"])) < SPREAD and \
                    not any(frozenset([a, b]) in NEIGHBOURS_OK for a in fam for b in other):
                return True
        return False
    roomy = [i for i in ok if not crowded(i)] or ok
    if best_key:
        return max(roomy, key=best_key)
    if near:
        return min(roomy, key=lambda i: math.dist(near, (houses[i]["x"], houses[i]["z"])))
    # spread: the house farthest from every real home so far (and from the special buildings)
    others = [(houses[j]["x"], houses[j]["z"]) for j in taken] + list(spots.values())
    return max(roomy, key=lambda i: min(math.dist((houses[i]["x"], houses[i]["z"]), o) for o in others))


town_js = open(ROOT + "/tools/town_planner/data/town.js", encoding="utf-8").read()
TOWN = json.loads(town_js[town_js.index("{"):town_js.rindex("}") + 1])
scenery = {r["id"]: r for r in TOWN["scenery"]}


def reach(points, x, z):
    return max(math.dist(p, (x, z)) for p in points) if points else 6.0


def radius_of_house(h):
    d = TOWN["designs"][h["design"]]
    return reach([(p[0] * (h.get("scale") or d["scale"]), p[1] * (h.get("scale") or d["scale"])) for p in d["footprint"]], 0, 0)


def new_house_near(at, design):
    """A new house by `at`, in the first clear spot on rings round it, facing it."""
    me = radius_of_house({"design": design})
    blockers = [(h["x"], h["z"], radius_of_house(h)) for h in houses]
    for l in plan["landmarks"]:
        s = scenery[l["id"]]
        blockers.append((l["x"], l["z"], reach(s["footprint"], s["x"], s["z"])))
    for ring in range(14, 80, 3):
        for k in range(24):
            a = k * math.pi / 12
            x, z = at[0] + math.cos(a) * ring, at[1] + math.sin(a) * ring
            if all(math.dist((x, z), (bx, bz)) > br + me + 1.5 for bx, bz, br in blockers) and                     not any(inside(l["points"], (x, z)) for l in plan.get("lakes", [])):
                houses.append({"design": design, "filler": True, "x": round(x, 2), "z": round(z, 2),
                               "yaw": round(math.atan2(at[0] - x, at[1] - z), 4), "name": ""})
                free.append(len(houses) - 1)
                return len(houses) - 1
    raise SystemExit("no room near %s" % (at,))


order = sorted(homes, key=lambda f: (0 if f[0] == "diamond_tiara" else 1 if any(m in ANCHOR for m in f) else 2, f[0]))
for fam in order:
    lead = next((m for m in fam if m in ANCHOR), fam[0])
    where = ANCHOR.get(lead)
    if lead == "diamond_tiara":
        i = pick(fam, best_key=lambda i: size[houses[i]["design"]] * (houses[i].get("scale") or 1))
    elif where and where.startswith("@"):
        friend = next(j for j, f in taken.items() if where[1:] in f)
        i = pick(fam, near=(houses[friend]["x"], houses[friend]["z"]))
    elif where == "appleacres_barned_01":
        i = new_house_near(spots[where], "g")      # the Apples' house in the game is a G, by their barn
    elif where:
        i = pick(fam, near=spots[where])
    else:
        i = pick(fam)
    taken[i] = fam

for i, fam in taken.items():
    houses[i]["filler"] = False
    houses[i]["name"] = " & ".join(name(m) for m in fam)
    houses[i]["residents"] = fam
for h in houses:
    if h["design"] == "sugarcube":
        h["residents"] = ["pinkie_pie"]
json.dump(plan, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))

print(len(residents), "ponies live in Ponyville;", len(homes), "households need a house")
for pid, where in OWN.items():
    if pid in residents:
        print(f"  {name(pid)}: {where} (own building in the game)")
for i, fam in sorted(taken.items(), key=lambda t: houses[t[0]]["name"]):
    h = houses[i]
    print(f"  {h['name']}: house {h['design'].upper()} at ({h['x']:.0f}, {h['z']:.0f})")
