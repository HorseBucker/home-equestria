"""The town's added trees at each density (high too, since 2026-11-21: "Let's try 9.5 m"), the lower town densities' own trees (2026-11-21 play test: "add some trees in the grassy areas to the lower density
options ... the minimum and low options look flat and empty ... a few trees on medium if you can fit some as well.
High should remain the same").

usage: python tools/town_planner/build/plan_density_trees.py <project> <high plan> <medium plan> <low plan> <minimum plan>
(after build_density.py has built each density's ground: build/out/density_<setting>/ground.f32)

Each lower density keeps the full town's trees (build/out/props.json) and every tree added at the density above it,
and adds more in its own open lawns: between the buildings (near the streets), clear of houses, landmarks, streets,
squares, door paths, dirt roads, water, fields, wells, benches and lamps, at least SPACING from any other tree, on
ground no steeper than 12 degrees; the small hills may carry them. Writes build/out/trees_<setting>.json (the props
json form apply_props.gd reads: {"trees": [{x, y, z, yaw}]}).
"""
import json, math, os, sys

import cv2
import numpy as np

ROOT, HIGH = sys.argv[1], sys.argv[2]
LOWER = dict(zip(("medium", "low", "minimum"), sys.argv[3:6]))
LOWER["high"] = HIGH
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
# (2026-11-21: minimum "needs more trees ... like 2x to 3x more": 40 -> 150 there, closer together)
ADD = {"high": 65, "medium": 1000, "low": 1000, "minimum": 90}     # (2026-11-21: high gets its own at 9.5 m; minimum's total kept at 315)
SPACING = {"high": 9.5, "medium": 10.0, "low": 10.0, "minimum": 8.0}
# (2026-11-23 play test: "you can see how much fuller and more lush minimum feels compared to low ... I want whatever
# setting minimum used to determine where the trees go to be used for low ... Medium could also be a bit more lush.
# High is fine as is." Each tree goes where the lawn is farthest from any tree, so what shaped a town is the gap left
# when it stopped: minimum stopped at its count (90) with no spot more than 10.0 m from a tree, low at 25 with gaps of
# 15.2 m, medium at 8 with 23.2 m. Low and medium now fill to minimum's 10.0 m, however many trees that takes.)
# `--only medium,low` writes just those settings' trees (the others are worked out, as the lower ones build on them,
# but their files are left as they are: minimum is kept as it was liked, 315 trees, laid before low got its new ones).
ONLY = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
if ONLY: sys.argv = sys.argv[:sys.argv.index("--only")]

# make_v22.py's masks (houses, landmarks, streets, door paths, water ...), without running its plan writing
src = open(os.path.join(HERE, "..", "make_v22.py"), encoding="utf-8").read()
scope = {"__file__": os.path.join(HERE, "..", "make_v22.py"), "__name__": "make_v22_masks"}
exec(compile(src[:src.index("plans = {s:")], "make_v22.py", "exec"), scope)
blocked_for, RES, X0m, Z0m, NXm, NZm = (scope[k] for k in ("blocked_for", "RES", "X0", "Z0", "NX", "NZ"))
line, disc, turn, DESIGNS = scope["line"], scope["disc"], scope["turn"], scope["DESIGNS"]

props = json.load(open(os.path.join(OUT, "props.json")))
trees = [dict(t) for t in props["trees"]]
for setting in ("high", "medium", "low", "minimum"):
    plan = json.load(open(LOWER[setting], encoding="utf-8"))
    blocked, village = blocked_for(plan, greens=False)
    extra = np.zeros(blocked.shape, np.uint8)
    for h in plan["houses"]:
        d = DESIGNS[h["design"]]
        if len(h["design"]) == 1 and "door" in d:
            # its door path straight out (apply_paint.py lays it so, up to 16 m), and room to walk beside it
            k = h.get("scale") or d["scale"]
            q = turn([d["door"][0] * k, d["door"][1] * k], h["yaw"]); door = (h["x"] + q[0], h["z"] + q[1])
            line(extra, [list(door), [door[0] + math.sin(h["yaw"]) * 16, door[1] + math.cos(h["yaw"]) * 16]], 6.0)
    for p in props["outdoor"]:
        disc(extra, p["x"], p["z"], 4.0)
    gdir = OUT if setting == "high" else os.path.join(OUT, f"density_{setting}")
    grid = json.load(open(os.path.join(gdir, "grid.json")))
    GX0, GZ0 = int(grid["origin"][0]), int(grid["origin"][1])
    ground = np.fromfile(os.path.join(gdir, "ground.f32"), "<f4").reshape(grid["rows"], grid["columns"])
    gz_, gx_ = np.gradient(ground)
    steep = np.degrees(np.arctan(np.hypot(gx_, gz_))) > 12.0

    def g(x, z):
        return float(ground[min(grid["rows"] - 1, max(0, round(z) - GZ0)), min(grid["columns"] - 1, max(0, round(x) - GX0))])

    free = village & ~blocked & ~extra.astype(bool)
    cand = np.argwhere(free[::4, ::4]) * 4                                  # every 2 m
    pts = [(c * RES + X0m, r * RES + Z0m) for r, c in cand]
    pts = [p for p in pts if not steep[min(grid["rows"] - 1, max(0, round(p[1]) - GZ0)), min(grid["columns"] - 1, max(0, round(p[0]) - GX0))]]
    have = np.array([(t["x"], t["z"]) for t in trees]) if trees else np.zeros((0, 2))
    P = np.array(pts) if pts else np.zeros((0, 2))
    near = np.min(np.hypot(P[:, None, 0] - have[None, :, 0], P[:, None, 1] - have[None, :, 1]), axis=1) if len(P) and len(have) else np.full(len(P), 1e9)
    rng = np.random.default_rng({"high": 60, "medium": 61, "low": 62, "minimum": 63}[setting])
    added = []
    for _ in range(ADD[setting]):
        k = int(np.argmax(near)) if len(near) else -1
        if k < 0 or near[k] < SPACING[setting]:
            break
        x, z = float(P[k, 0]) + float(rng.uniform(-0.6, 0.6)), float(P[k, 1]) + float(rng.uniform(-0.6, 0.6))
        t = {"x": round(x, 2), "z": round(z, 2), "y": round(g(x, z), 3), "yaw": round(float(rng.uniform(0, 6.283)), 3), "density": setting}
        trees.append(t); added.append(t)
        near = np.minimum(near, np.hypot(P[:, 0] - x, P[:, 1] - z))
    # every tree stands on this density's own ground (its hills differ from the full town's)
    for t in trees:
        t["y"] = round(g(t["x"], t["z"]), 3)
    if ONLY is None or setting in ONLY:
        json.dump({"trees": trees}, open(os.path.join(OUT, f"trees_{setting}.json"), "w"), indent=1)
    print(f"{setting:8s} trees: {len(added)} added here, {len(trees) - len(props['trees'])} more than the full town in all")
