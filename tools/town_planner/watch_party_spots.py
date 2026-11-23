"""Watch Party's television spots from the planner (2026-11-18): place them with notes, the way the planner places
everything else.

usage:
  python tools/town_planner/watch_party_spots.py <plan.json> --mark
      writes <plan>_tv.json beside the plan: the plan with a note at each spot Watch Party uses now ("tv stand",
      "tv crt"), to open in the planner and see where they are.
  python tools/town_planner/watch_party_spots.py <plan.json> [--spots <mods/watch_party/spots.json>]
      reads the plan's notes and writes the spots Watch Party uses (its mods/watch_party/spots.json; by default the
      Watch Party checkout beside this repo, ../home-equestria-watch-party). Then rebuild the mod.

Notes (the planner's Note tool; case does not matter):
  tv stand [degrees]   the market's television stand, inside the white tent (the game's tent_friagram_lightbrown_01,
                       beside the pink furniture tent). Kept as an offset from that tent, so it follows the tent if the
                       tent moves. Degrees: the way its front faces, 0 = toward +z (south on the planner), 90 = +x
                       (east); without a number it keeps the facing it has.
  tv crt [degrees]     the vintage (CRT) set's spot at the Everfree's edge, before it is found. Its height is found in
                       the game (level, clear ground near the note).
  tv flat [degrees]    the flatscreen on its stand, deeper in the Everfree (outside the planner's map today).
  tv flat wall [deg]   the flatscreen made for a wall.
A note left out keeps the spot Watch Party has now. Worlds that already laid a set out somewhere keep it there,
except at a spot listed as retired (the old town's), which are laid out again at the new spot.
"""
import json, math, os, sys

PLAN = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SPOTS = sys.argv[sys.argv.index("--spots") + 1] if "--spots" in sys.argv else os.path.join(ROOT, "..", "home-equestria-watch-party", "mods", "watch_party", "spots.json")
TENT = "tent_friagram_lightbrown_01"
FINDS = {"tv crt": "goods:watch-tv-vintage", "tv flat wall": "goods:watch-tv-flat-wall", "tv flat": "goods:watch-tv-flat"}

plan = json.load(open(PLAN, encoding="utf-8"))
spots = json.load(open(SPOTS, encoding="utf-8"))
tent = next((l for l in plan.get("landmarks", []) if l.get("id") == TENT), None)
if tent is None:
    raise SystemExit(f"the plan has no {TENT}")
# the game turns the market tents to yaw 0 (world/shop/market_stalls.gd), so the tent's frame is the world's axes


def parse(text):
    words = text.strip().lower().split()
    for name in sorted(list(FINDS) + ["tv stand"], key=len, reverse=True):
        n = len(name.split())
        if words[:n] == name.split():
            rest = words[n:]
            try:
                return name, float(rest[0]) if rest else None
            except ValueError:
                return name, None
    return None, None


if "--mark" in sys.argv:
    notes = [n for n in plan.get("notes", []) if parse(str(n.get("text", "")))[0] is None]
    market = spots.get("market", {})
    off = market.get("offset", [0.27, 0.24])
    notes.append({"x": round(tent["x"] + off[0], 2), "z": round(tent["z"] + off[1], 2), "text": "tv stand %g" % market.get("facing", 351.0)})
    for name, id_ in FINDS.items():
        row = spots.get("overhaul", {}).get("forest", {}).get(id_)
        if row:
            notes.append({"x": row[0], "z": row[2], "text": "%s %g" % (name, row[3])})
    plan["notes"] = notes
    out = os.path.splitext(PLAN)[0] + "_tv.json"
    json.dump(plan, open(out, "w", encoding="utf-8"), separators=(",", ":"))
    print("wrote", out, "with the current spots as notes")
    raise SystemExit(0)

changed = []
for note in plan.get("notes", []):
    name, degrees = parse(str(note.get("text", "")))
    if name is None:
        continue
    if name == "tv stand":
        market = spots.setdefault("market", {"tent": "RNLScenery/Town/Market/" + TENT})
        market["offset"] = [round(note["x"] - tent["x"], 2), round(note["z"] - tent["z"], 2)]
        if degrees is not None:
            market["facing"] = degrees
        if math.hypot(*market["offset"]) > 5.0:
            print("note: the stand is %.1f m from the white tent's middle (the tent is about 10 x 14 m)" % math.hypot(*market["offset"]))
        changed.append(f"stand: {market['offset']} from the tent, facing {market.get('facing', 351.0)}")
    else:
        id_ = FINDS[name]
        # (the overhaul's own spots, used only when the overhaul is installed: Watch Party 1.2.4)
        ov = spots.setdefault("overhaul", {})
        old = ov.setdefault("forest", {}).get(id_)
        facing = degrees if degrees is not None else (old[3] if old else 0.0)
        if old and (abs(old[0] - note["x"]) > 0.5 or abs(old[2] - note["z"]) > 0.5):
            retired = ov.setdefault("retired", {}).setdefault(id_, [])
            if [old[0], old[1], old[2]] not in retired:
                retired.append([old[0], old[1], old[2]])
        ov["forest"][id_] = [round(note["x"], 2), 0.0, round(note["z"], 2), facing]
        changed.append(f"{name}: ({note['x']:.1f}, {note['z']:.1f}) facing {facing}")
if not changed:
    raise SystemExit("no tv notes in the plan (tv stand, tv crt, tv flat, tv flat wall); nothing changed")
json.dump(spots, open(SPOTS, "w", encoding="utf-8"), indent="\t")
print("\n".join(changed))
print("wrote", os.path.abspath(SPOTS), "- rebuild Watch Party to use them")
