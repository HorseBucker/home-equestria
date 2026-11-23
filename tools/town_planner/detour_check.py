"""How far round is every spot from the Town Hall on foot? Finds land the rivers cut off from town.

usage: python tools/town_planner/detour_check.py <plan.json> <elevation export dir> [<png>]
(the export dir holds water.u8 and grid.json: elevation.py --export)
Walking distance from the Town Hall over dry ground and the plan's bridges (2 m cells), against the straight
distance. Prints each stretch of land whose walk is more than twice the straight line and 150 m longer, and how
much of the map that is; the picture shades the walk's excess.
"""
import json, math, os, sys
import cv2, numpy as np
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

plan = json.load(open(sys.argv[1], encoding="utf-8")); D = sys.argv[2]
PNG = sys.argv[3] if len(sys.argv) > 3 else None
g = json.load(open(os.path.join(D, "grid.json"))); NX, NZ = g["columns"], g["rows"]; X0, Z0 = g["origin"]
water = np.fromfile(os.path.join(D, "water.u8"), np.uint8).reshape(NZ, NX).astype(bool)
deck = np.zeros((NZ, NX), np.uint8)
for b in plan["bridges"]:
    cv2.line(deck, (int(round(b["a"][0] - X0)), int(round(b["a"][1] - Z0))), (int(round(b["b"][0] - X0)), int(round(b["b"][1] - Z0))), 1, 3)
walk = (~water) | deck.astype(bool)
K = 2
w2 = walk[:NZ // K * K, :NX // K * K].reshape(NZ // K, K, NX // K, K).all(axis=(1, 3)) | deck[:NZ // K * K, :NX // K * K].reshape(NZ // K, K, NX // K, K).any(axis=(1, 3))
h, w = w2.shape
idx = np.arange(h * w).reshape(h, w)
rows, cols, vals = [], [], []
for dz, dx, cost in ((0, 1, K), (1, 0, K), (1, 1, K * 1.4142), (1, -1, K * 1.4142)):
    a = idx[max(0, -dz):h - max(0, dz), max(0, -dx):w - max(0, dx)]
    b = idx[max(0, dz):, max(0, dx):w + min(0, dx)] if dx >= 0 else idx[dz:, :w + dx]
    if dx < 0:
        a = idx[:h - dz, -dx:]
    ok = w2.ravel()[a.ravel()] & w2.ravel()[b.ravel()]
    rows.append(a.ravel()[ok]); cols.append(b.ravel()[ok]); vals.append(np.full(int(ok.sum()), cost))
graph = coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(h * w, h * w)).tocsr()
hall = next(hh for hh in plan["houses"] if hh["design"] == "town_hall")
src = idx[int((hall["z"] - Z0) / K) + 9, int((hall["x"] - X0) / K) - 9]
dist = dijkstra(graph, directed=False, indices=src).reshape(h, w)
xs = X0 + (np.arange(w) + 0.5) * K; zs = Z0 + (np.arange(h) + 0.5) * K
straight = np.hypot(xs[None, :] - hall["x"], zs[:, None] - hall["z"])
excess = dist - straight
far = w2 & np.isfinite(dist) & (dist > 2 * straight) & (excess > 150)
cut = w2 & ~np.isfinite(dist)
lab, n = ndimage.label(far | cut)
print(f"land walked to from the Town Hall: {int((w2 & np.isfinite(dist)).sum()) * K * K} m2; cut off entirely: {int(cut.sum()) * K * K} m2; a long way round: {int(far.sum()) * K * K} m2")
for k in range(1, n + 1):
    zz, xx = np.nonzero(lab == k)
    if len(zz) * K * K < 400:
        continue
    e = excess[zz, xx]
    print(f"  {len(zz) * K * K} m2 round ({xs[int(xx.mean())]:.0f}, {zs[int(zz.mean())]:.0f}), x {xs[xx.min()]:.0f}..{xs[xx.max()]:.0f}, z {zs[zz.min()]:.0f}..{zs[zz.max()]:.0f}: "
          + ("no way there" if not np.isfinite(e).all() else f"{np.median(e):.0f} m further on foot than as the crow flies"))
if PNG:
    im = np.zeros((h, w, 3), np.uint8); im[:] = (120, 190, 130)
    ex = np.clip(np.nan_to_num(excess, posinf=600) / 400.0, 0, 1)
    im[..., 2] = (130 + 125 * ex).astype(np.uint8); im[..., 1] = (190 - 120 * ex).astype(np.uint8); im[..., 0] = (120 - 80 * ex).astype(np.uint8)
    im[~w2] = (200, 120, 60)
    cv2.imwrite(PNG, cv2.resize(im, None, fx=2, fy=2, interpolation=cv2.INTER_NEAREST))
