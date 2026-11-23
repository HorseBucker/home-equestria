"""Exact roof-against-roof check: each house's real outline seen from above (every triangle of its outside,
from build/qc/export_outlines.gd), not the box round it.

usage: python tools/town_planner/roof_check.py <plan.json>
Prints every pair of houses whose outsides really overlap or stand closer than 0.15 m.
"""
import json, math, os, sys
import numpy as np, cv2
from scipy import ndimage
from plan_geometry import TOWN, shape, gap, house_scale

HERE = os.path.dirname(os.path.abspath(__file__))
plan = json.load(open(sys.argv[1], encoding="utf-8"))
H = [h for h in plan["houses"] if len(h["design"]) == 1]
RES = 0.05
tris = {d: np.fromfile(os.path.join(HERE, "build/out/outlines", d + ".f32"), "<f4").reshape(-1, 3, 2) for d in "abcdefgh"}


def mask(h, x0, z0, n):
    k = house_scale(h); c, s = math.cos(h["yaw"]), math.sin(h["yaw"])
    t = tris[h["design"]] * k
    wx = h["x"] + t[..., 0] * c + t[..., 1] * s; wz = h["z"] - t[..., 0] * s + t[..., 1] * c
    pts = np.round(np.stack([(wx - x0) / RES, (wz - z0) / RES], -1) * 8).astype(np.int32)
    m = np.zeros((n, n), np.uint8)
    cv2.fillPoly(m, list(pts), 1, shift=3)
    return m


bad = 0
for i in range(len(H)):
    for j in range(i + 1, len(H)):
        a, b = H[i], H[j]
        if abs(a["x"] - b["x"]) > 26 or abs(a["z"] - b["z"]) > 26 or gap(shape(a), shape(b)) > 0.4:
            continue
        x0, z0 = min(a["x"], b["x"]) - 16, min(a["z"], b["z"]) - 16
        n = int((max(abs(a["x"] - b["x"]), abs(a["z"] - b["z"])) + 32) / RES)
        ma, mb = mask(a, x0, z0, n), mask(b, x0, z0, n)
        over = int((ma & mb).sum())
        d = ndimage.distance_transform_edt(1 - ma) * RES
        near = float(d[mb.astype(bool)].min())
        if over or near < 0.15:
            bad += 1
            name = lambda h: (h.get("name") or ("vacant home " if not h.get("filler") else "background ") + h["design"]) + f" ({h['x']:.0f}, {h['z']:.0f})"
            print(f"{name(a)} and {name(b)}: " + (f"overlap {over * RES * RES:.1f} m2" if over else f"{near:.2f} m apart"))
print("pairs really touching:", bad)
