"""Every bridge's posts reach the stream bed (2026-11-24 play test: "the bridge's wooden support posts sit awkwardly on
the steep slope with gaps underneath. Extend the bridge pilings/posts downward so they plant firmly into the riverbed").

usage: python tools/town_planner/build/bridge_posts.py <project>
then:  godot --headless --xr-mode off --path . --script res://tools/town_planner/build/round_bridges.gd
(after fix_shore.py, whose deeper, wider banks left the posts short)

plan_scenery.py measured the ground under the posts of the three rounded bridges to Town Hall only ("post_floors" in
build/out/scenery_moves.json, which round_bridges.gd lengthens the posts to). This measures it for every bridge, on
the ground as it is now: under each post's footprint, the lowest ground of any town density (the shores are the same
at all of them, the rises are not), POST_SINK m deeper. "round" says which bridges round_bridges.gd also makes rounder
and fills under (the three); the others only get their posts.
"""
import json, math, os, sys

import numpy as np

ROOT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
ROUND_BRIDGES = {"bridge_03", "bridge_04", "bridge_07"}          # plan_scenery.py
POST_FEET = [(-5.905, 4.54), (5.905, 4.54), (-5.905, -4.55), (5.905, -4.55)]
POST_HALF = (0.475, 0.33)
POST_SINK = 0.25

grid = json.load(open(os.path.join(OUT, "grid.json")))
NX, NZ = grid["columns"], grid["rows"]; X0, Z0 = int(grid["origin"][0]), int(grid["origin"][1])
grounds = [np.fromfile(os.path.join(OUT, d, "ground.f32") if d else os.path.join(OUT, "ground.f32"), "<f4").reshape(NZ, NX)
           for d in ("", "density_medium", "density_low", "density_minimum")]


def g(x, z):
    fx, fz = x - X0, z - Z0
    c0, r0 = int(math.floor(fx)), int(math.floor(fz))
    tx, tz = fx - c0, fz - r0
    return min(float(a[r0, c0] * (1 - tx) * (1 - tz) + a[r0, c0 + 1] * tx * (1 - tz) + a[r0 + 1, c0] * (1 - tx) * tz + a[r0 + 1, c0 + 1] * tx * tz) for a in grounds)


path = os.path.join(OUT, "scenery_moves.json")
moves = json.load(open(path))
for bid, m in moves.items():
    if m.get("action") != "bridge":
        continue
    sx, sy, sz = m["scale"]
    yaw = float(m["yaw"])
    ux, uz = math.cos(yaw), -math.sin(yaw)
    vx, vz = math.sin(yaw), math.cos(yaw)
    floors = []
    for fx, fz in POST_FEET:
        under = []
        for dx in (-POST_HALF[0], 0.0, POST_HALF[0]):
            for dz in (-POST_HALF[1], 0.0, POST_HALF[1]):
                lx, lz = (fx + dx) * sx, (fz + dz) * sz
                under.append(g(m["x"] + ux * lx + vx * lz, m["z"] + uz * lx + vz * lz))
        floors.append(round(min(under) - POST_SINK, 3))
    old = m.get("post_floors")
    m["post_floors"] = floors
    m["round"] = bid in ROUND_BRIDGES
    foot = float(m["y"]) - 4.24 * float(sy)
    print(f"{bid}: posts' feet at {foot:.2f}, ground under them {[round(f + POST_SINK, 2) for f in floors]}" + (f" (was {old})" if old else ""))
json.dump(moves, open(path, "w"), indent=1)
