"""Build the whole plan into the game, every step in order (see the README, "Building it into the game").

usage: python tools/town_planner/build/build_all.py <project> <plan.json> [--godot C:/Tools/Godot/godot.exe] [--from <step>]
steps: ground, paint, houses, scenery, props, spots. `--from scenery` starts there (the earlier steps' output is
kept). Stops at the first step that fails.
"""
import os, subprocess, sys

ROOT, PLAN = sys.argv[1], sys.argv[2]
GODOT = sys.argv[sys.argv.index("--godot") + 1] if "--godot" in sys.argv else "C:/Tools/Godot/godot.exe"
START = sys.argv[sys.argv.index("--from") + 1] if "--from" in sys.argv else "ground"
HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["ground", "paint", "houses", "scenery", "props", "spots"]


def py(script, *args):
    print(f"--- {script}", flush=True)
    subprocess.run([sys.executable, os.path.join(HERE, script), ROOT, *args], check=True)


def gd(script, *args, window=False):
    print(f"--- {script}", flush=True)
    out = subprocess.run([GODOT] + ([] if window else ["--headless"]) + ["--xr-mode", "off", "--path", ROOT, "--script", f"res://tools/town_planner/build/{script}"] + (["--"] + list(args) if args else []),
                         capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1500)
    keep = [l for l in out.stdout.splitlines() if l[:1].isupper() and not l.startswith(("WARNING", "ERROR", "   "))]
    errors = [l for l in (out.stdout + out.stderr).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    print("\n".join(keep[-12:]), flush=True)
    if errors:
        raise SystemExit(f"{script}: " + errors[0])


todo = ORDER[ORDER.index(START):]
py("reset_inputs.py", *todo)
if "ground" in todo:
    py("apply_ground.py", PLAN)
    py("bake_flow.py", PLAN)                 # which way the rivers run (world/water/ponyville_flow.json)
if "paint" in todo:
    py("make_sage_texture.py")
    py("apply_paint.py", PLAN)
    gd("apply_ground_half.gd")
if "houses" in todo:
    gd("make_background_houses.gd")
    py("build_town.py", PLAN)
if "scenery" in todo:
    gd("dump_scenery.gd")
    py("plan_scenery.py", PLAN)
    gd("apply_scenery.gd")
    gd("round_bridges.gd")                # the three bridges to Town Hall: higher arches, posts to the ground
if "props" in todo:
    py("plan_props.py", PLAN)
    gd("apply_props.gd")
if "spots" in todo:
    py("plan_navigation.py", PLAN)
    py("plan_code_spots.py", PLAN)
    import json
    edge = json.load(open(PLAN, encoding="utf-8"))["edges"][0]["points"]
    gd("cut_track.gd", *[str(round(v)) for v in (min(p[0] for p in edge), max(p[0] for p in edge), min(p[1] for p in edge), max(p[1] for p in edge))], window=True)   # a MultiMesh cannot be read headless
print("built:", ", ".join(todo))
