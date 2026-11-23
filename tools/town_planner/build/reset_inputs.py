"""Put the files a build step rewrites back as the game shipped them (commit 6b17658, before the overhaul), so the
step can run again. usage: python tools/town_planner/build/reset_inputs.py <project> <step>...
steps: ground, paint, houses, scenery, props, spots (each as in the README); all = every step."""
import json, subprocess, sys
ROOT, steps = sys.argv[1], set(sys.argv[2:])
BASE = "6b17658"
FILES = {
    "ground": ["world/terrain/sculpt/index.json", "world/water/rivers.json", "world/water/ponyville_canals.json", "world/terrain/data_half"],
    "paint": ["world/biomes/authored/surface_index.json"],
    "houses": ["world/towns/ponyville/town.tscn"],
    "scenery": ["world/props/ponyville/rnl_scenery.json", "world/props/ponyville/rnl_scenery.scn", "world/props/ponyville/rnl_scenery_defaults.tscn",
                "world/towns/ponyville/pad_lifts.json"],          # (river_crossings.gd is not reset: only its bridge list is rewritten)
    "props": ["world/biomes/authored/index.json", "world/props/ponyville_kit/placements.json", "world/props/ponyville/farm_layout.json",
              "world/props/ponyville/town_trees.scn", "world/props/ponyville/outdoor_props.scn"],
}
if "all" in steps:
    steps = set(FILES)
for s in steps:
    if s in FILES:
        subprocess.run(["git", "-C", ROOT, "checkout", BASE, "--"] + FILES[s], check=True)
# the railway's baked track is not in git (it comes with the game's source data): the first time, an untouched
# copy is kept in build/out/originals; after that the step starts from that copy
if "spots" in steps:
    import os, shutil
    track = os.path.join(ROOT, "world/railway/track.scn")
    keep = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "originals", "track.scn")
    os.makedirs(os.path.dirname(keep), exist_ok=True)
    if not os.path.exists(keep):
        shutil.copy2(track, keep)
    else:
        shutil.copy2(keep, track)
# bundle.json holds both the paint's tiles ("surface") and the vegetation's ("biomes"): reset only the asked half
old = json.loads(subprocess.run(["git", "-C", ROOT, "show", BASE + ":world/biomes/authored/bundle.json"], capture_output=True, text=True, encoding="utf-8", check=True).stdout)
path = ROOT + "/world/biomes/authored/bundle.json"
now = json.load(open(path, encoding="utf-8"))
for step, half in (("paint", "surface"), ("props", "biomes")):
    if step in steps:
        now[half] = old[half]
json.dump(now, open(path, "w", encoding="utf-8"), indent=2)
print("reset:", ", ".join(sorted(steps)))
