"""The in-game map's picture of the rebuilt Ponyville (2026-11-17), from capture_map.gd's shots.

usage: python tools/town_planner/build/make_map_tiles.py <project>
(after: godot --xr-mode off --resolution 1024x1024 --path <project> -- --new-game --skip-title --weather clear
        --lab res://tools/town_planner/build/qc/capture_map.gd)

world/ui/aerial_map (read by world/ui/aerial_map_layer.gd) holds the map in three levels: 4 m a pixel over the
whole world, 1 m a pixel in 1024 m tiles, and a "town" level at 0.25 m a pixel in 256 m tiles. The shots are
graded the way the shipped imagery was (manifest "grade": saturation, brightness) and
- become the town level's tiles (town/town_<x/256>_<z/256>.png), the level's tile list growing to every shot;
- are shrunk into the 1 m and 4 m tiles and the overview over the same ground, faded into the old picture
  over FEATHER metres at the edge so the countryside around stays as it was.
The manifest's tile lists and a note of this are updated. Old files are overwritten; git has them.

  python tools/town_planner/build/make_map_tiles.py <project> --density minimum|low|medium
the town at a lower density (town_density.gd; shots in build/out/map_<setting> from capture_map.gd run with that
density): the same tiles, blended into the full town's picture, written as copies under
world/ui/aerial_map/density/<setting>/ at the same relative paths, which the map uses in place of the full
town's while that town is loaded (aerial_map_layer.gd _image_path). The manifest is left as it is.
"""
import glob, json, math, os, re, sys
import numpy as np
from PIL import Image, ImageEnhance

ROOT = sys.argv[1]
DENSITY = sys.argv[sys.argv.index("--density") + 1] if "--density" in sys.argv else ""
MAP = os.path.join(ROOT, "world/ui/aerial_map")
SHOTS = os.path.join(ROOT, "tools/town_planner/build/out/map" + ("_" + DENSITY if DENSITY else ""))
DEST = os.path.join(MAP, "density", DENSITY) if DENSITY else MAP


def dest(name):
    path = os.path.join(DEST, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path
FEATHER = 48.0           # metres of fade into the old picture at the edge of the new ground
## The shots south of the town's edge (z 0..256: Sweet Apple Acres' fields to Fluttershy's cottage; 2026-11-18,
## round 8: they had been left out and that strip still showed the old town) are used only this far south, so the
## Everfree beyond keeps the old picture: the plan's edge (z 188) plus the fade.
SOUTH_CUT = 188 + 48
manifest = json.load(open(os.path.join(MAP, "manifest.json"), encoding="utf-8"))
grade = manifest.get("grade", {"saturation": 0.65, "brightness": 0.95})


def graded(im):
    # the tile is the shot's middle square (the camera's ortho size is its height; the window need not be square)
    w, h = im.size
    if w != h:
        s = min(w, h); im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    im = ImageEnhance.Color(im.convert("RGB")).enhance(float(grade["saturation"]))
    return ImageEnhance.Brightness(im).enhance(float(grade["brightness"]))


shots = {}
for f in glob.glob(os.path.join(SHOTS, "shot_*.png")):
    x, z = map(int, re.findall(r"shot_(-?\d+)_(-?\d+)", os.path.basename(f))[0])
    shots[(x, z)] = graded(Image.open(f))
if not shots:
    raise SystemExit("no shots in " + SHOTS)
# The shots by the Everfree (x >= 0, z >= 0) come out darker than the town's (its light, even with the fog off for
# the shot): each is brought to the shot north of it, per channel, over a band along their shared edge.
for (x, z) in sorted(shots):
    if x < 0 or z < 0 or (x, z - 256) not in shots:
        continue
    a_ = np.asarray(shots[(x, z)].convert("RGB"), np.float32); b_ = np.asarray(shots[(x, z - 256)].convert("RGB"), np.float32)
    band = max(8, a_.shape[0] // 25)
    gain_ = b_[-band:].reshape(-1, 3).mean(0) / np.maximum(a_[:band].reshape(-1, 3).mean(0), 1.0)
    shots[(x, z)] = Image.fromarray(np.clip(a_ * gain_, 0, 255).astype(np.uint8))
    print(f"shot {x},{z} brought to the one north of it: gain {np.round(gain_, 3)}")
xs = sorted({k[0] for k in shots}); zs = sorted({k[1] for k in shots})
SPAN = 256
X0, Z0 = xs[0], zs[0]
X1, Z1 = xs[-1] + SPAN, zs[-1] + SPAN
print(f"{len(shots)} shots over x {X0}..{X1}, z {Z0}..{Z1}")

def git_image(name):
    """The game's own picture (before the overhaul) of a map file."""
    import io, subprocess
    raw = subprocess.run(["git", "-C", ROOT, "show", "8919fff:world/ui/aerial_map/" + name], capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(raw)).convert("RGB")


def south_rows(x, z):
    """How many metres of a shot are used: all of it, but the ones east of x 0 (by the Everfree) only to SOUTH_CUT."""
    return SPAN if x < 0 else max(0, min(SPAN, SOUTH_CUT - z))



# ---- the town level: one tile per shot ----
town = next(l for l in manifest["levels"] if abs(float(l["metres_per_pixel"]) - 0.25) < 1e-6)
have = {(t["x"], t["z"]): t for t in town["tiles"]}
for (x, z), im in sorted(shots.items()):
    name = f"town/town_{x // SPAN}_{z // SPAN}.png"
    have[(x, z)] = {"x": x, "z": z, "file": name}
town["tiles"] = [have[k] for k in sorted(have)]

# ---- the mosaic at 1 m a pixel, and its fade-in mask ----
W, H = X1 - X0, Z1 - Z0
mosaic = Image.new("RGB", (W, H))
for (x, z), im in shots.items():
    mosaic.paste(im.resize((SPAN, SPAN), Image.LANCZOS), (x - X0, z - Z0))
# (the shots need not fill the rectangle: the Everfree's corner south-east of the town is left out, its forest
# unchanged and better in the old picture than from a camera over it; the fade follows whatever they cover)
from scipy import ndimage
covered = np.zeros((H, W), bool)
for (x, z) in shots:
    covered[z - Z0:z - Z0 + south_rows(x, z), x - X0:x - X0 + SPAN] = True
inside = ndimage.distance_transform_edt(np.pad(covered, 1, constant_values=False))[1:-1, 1:-1]
mask_1m = np.clip((inside - 1.0) / FEATHER, 0.0, 1.0).astype(np.float32)


def paste_into(level_mpp, name, tile_x, tile_z, span_m):
    """Blend the mosaic into one tile of a coarser level (its own pixels: span_m / level_mpp)."""
    tile = Image.open(os.path.join(MAP, name)).convert("RGB") if DENSITY else git_image(name)
    px = tile.size[0]
    mpp = span_m / px
    # the part of the mosaic over this tile, in metres
    ax0, az0 = int(max(X0, tile_x)), int(max(Z0, tile_z))
    ax1, az1 = int(min(X1, tile_x + span_m)), int(min(Z1, tile_z + span_m))
    if ax1 <= ax0 or az1 <= az0:
        return False
    w, h = int(round((ax1 - ax0) / mpp)), int(round((az1 - az0) / mpp))
    part = mosaic.crop((ax0 - X0, az0 - Z0, ax1 - X0, az1 - Z0)).resize((w, h), Image.LANCZOS)
    m = Image.fromarray((mask_1m[az0 - Z0:az1 - Z0, ax0 - X0:ax1 - X0] * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)
    tile.paste(part, (int(round((ax0 - tile_x) / mpp)), int(round((az0 - tile_z) / mpp))), m)
    tile.save(dest(name), optimize=True)
    return True


# ---- colour: the shots match the old picture's countryside (the old capture was made without haze, under
# another sky: pasted as they are they stood out as a paler square). Per channel, the mean and spread of the
# new pixels in a band inside the edge are brought to the old picture's there, over unchanged country.
level_1m = next(l for l in manifest["levels"] if abs(float(l["metres_per_pixel"]) - 1.0) < 1e-6)
old = Image.new("RGB", (W, H))
for t_ in level_1m["tiles"]:
    tx, tz, sp = int(t_["x"]), int(t_["z"]), int(level_1m["span"])
    if tx + sp <= X0 or tx >= X1 or tz + sp <= Z0 or tz >= Z1:
        continue
    # (a lower density matches the game's own picture from git, as the full town's run did: the files here
    # already hold that run's matched town, and matching to them would grade it twice)
    # (always the game's own picture from git: the files here hold an earlier run's town, and matching to them
    # would grade it twice)
    old.paste(git_image(t_["file"]), (tx - X0, tz - Z0))
band = covered & (inside > 6.0) & (inside < 140.0)
new_a = np.asarray(mosaic, np.float32); old_a = np.asarray(old, np.float32)
gain = old_a[band].std(0) / np.maximum(new_a[band].std(0), 1.0)
offset = old_a[band].mean(0) - new_a[band].mean(0) * gain
print("colour match: gain", np.round(gain, 3), "offset", np.round(offset, 1))
mosaic = Image.fromarray(np.clip(new_a * gain + offset, 0, 255).astype(np.uint8))


def matched(im):
    return Image.fromarray(np.clip(np.asarray(im, np.float32) * gain + offset, 0, 255).astype(np.uint8))


for (x, z), im in sorted(shots.items()):
    name = f"town/town_{x // SPAN}_{z // SPAN}.png"
    big = matched(im.resize((1024, 1024), Image.LANCZOS))
    rows = south_rows(x, z)
    if rows < SPAN:
        base = git_image(name).resize((1024, 1024), Image.LANCZOS)
        fade = np.clip((rows - (np.arange(1024) + 0.5) / 4.0) / FEATHER, 0.0, 1.0)
        base.paste(big, (0, 0), Image.fromarray((np.repeat(fade[:, None], 1024, 1) * 255).astype(np.uint8)))
        big = base
    big.save(dest(name), optimize=True)

touched = []
for level in manifest["levels"]:
    mpp = float(level["metres_per_pixel"])
    if mpp < 1.0:
        continue
    span = float(level["span"])
    for t in level["tiles"]:
        if paste_into(mpp, t["file"], t["x"], t["z"], span):
            touched.append(t["file"])
# the overview: the whole world
b = manifest["bounds"]
ov = Image.open(os.path.join(MAP, manifest["overview"])).convert("RGB")
span_x = float(b[2])
if paste_into(span_x / ov.size[0], manifest["overview"], b[0], b[1], span_x):
    touched.append(manifest["overview"])
manifest["town_rebuild"] = "Ponyville overhaul 2026-11-17: town level and the tiles over x %d..%d, z %d..%d recaptured in game " \
    "(tools/town_planner/build/qc/capture_map.gd, make_map_tiles.py)" % (X0, X1, Z0, Z1)
if not DENSITY:
    json.dump(manifest, open(os.path.join(MAP, "manifest.json"), "w", encoding="utf-8"), indent=1)
print("town tiles:", len(town["tiles"]), "; coarser tiles and overview updated:", touched)
