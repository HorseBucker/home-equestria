# Ponyville planner

The tools that made the Ponyville Overhaul: a page for laying out the town by hand, and the build scripts that turn
that layout into the game's ground, paint, houses, scenery, props and pathing. The town follows the official
Ponyville map from Tails of Equestria, the licensed MLP tabletop RPG.

Needs Godot 4.5 (`godot` below) and Python 3 with numpy, scipy, opencv-python, Pillow and soundfile. Run everything
from the project folder.

## What's here

| | |
|---|---|
| `planner.html` | The planner. Open it in a browser. It keeps the plan between visits; "Save plan" downloads it. |
| `ponyville_planV28_high.json` | The plan the game is built from (High density, 260 houses). |
| `ponyville_planV28_{medium,low,minimum}.json` | The plans for the other town density settings. |
| `ponyville_traced_plan.json` | The first plan, traced from the official map by `trace_map.py`. |
| `data/` | What the planner draws over: the game's ground, water and town, and the official map (`reference.jpg`). |
| `build/` | The build scripts. `build/qc/` holds the checks and the picture labs. |
| `make_v22.py`, `ponyville_planV19_high.json`, `ponyville_planV20_high.json` | Kept for `build/plan_density_trees.py`, which reads its masks from `make_v22.py`. |

## The plan file

World metres, x east, z south (north is -z), yaw in radians about the up axis.

- `houses`: design (a-h), `filler` (true: a background house nopony enters), x, z, yaw, `scale`, `residents`
- `landmarks`: the id of a building in `world/props/ponyville/rnl_scenery.json`, and where it goes
- `roads`: `type` (`town`: Ponyville's sage packed-earth streets, `dirt`: the game's dirt road), width, points
- `grounds`, `greens`: outlines of open town ground, and of lawns left inside it
- `rivers` (width, points), `lakes` and `flats` (outlines), `bridges` (width, the two bank points)
- `fields` (outline, `crop`), `woods` (outline, tree `density`)
- `notes`: text at a spot, with an optional facing; the build reads `bench`, `no bench` and `banner`
- `edges`: the area that is rebuilt; the old town inside it is cleared, nothing outside it changes
- `terrain`: the ground shape `elevation.py` makes from the plan (deterministic, so the build remakes it)
- `density`: on the lower plans, which setting the plan is for
- `no_door_path_houses`: houses that get no path painted from their door to the street

## Refreshing the planner's data

After a game update, or to see the built town in the planner:

```
godot --headless --xr-mode off --path . --script res://tools/town_planner/export_ground.gd
python tools/town_planner/build_data.py
```

## Plan tools

- `trace_map.py`, `tidy_plan.py`, `assign_residents.py`: trace the official map into a plan, join its loose road and
  river ends, and give every Ponyville resident a home.
- `elevation.py <plan> [--preview ground.png]`: the ground the plan makes.
- `check_plan.py`, `roof_check.py`, `street_check.py`, `detour_check.py`: overlaps, touching roofs, streets that
  dead-end, long walks round water.
- `render_plan.py <plan> picture.png [--around x z radius] [--labels]`: a picture of a plan.
- `make_density_plans.py`, `fill_vacant_homes.py`: the lower density plans from the High one.

## Building the town into the game

The full build, from the game's own files as shipped (each step resets the files it writes):

```
python tools/town_planner/build/build_all.py . tools/town_planner/ponyville_planV28_high.json [--from <step>]
```

| Step | What it writes |
|---|---|
| `ground` | The ground and water: a sculpt overlay per region, one water surface for every river and lake, the river current (`ponyville_flow.json`). |
| `paint` | The ground's paint: sage streets and squares, lawns, door paths, dirt roads, river beds, fields, grass under the bridges; and the "Very Low" quality copy. |
| `houses` | The background house models, and `town.tscn`: every real home and background house. |
| `scenery` | The landmarks and their dressing where the plan puts them, the bridges, and the three rounded bridges to the Town Hall. |
| `props` | Trees, street lamps, benches, flowerbeds, gardens, farm fences and crops, vegetation. |
| `spots` | The walk grid's fingerprint, the coordinates written into game scripts, and the old railway cut out of town. |

Then the lower density settings (run again whenever High is rebuilt):

```
python tools/town_planner/build/build_density.py . tools/town_planner/ponyville_planV28_high.json tools/town_planner/ponyville_planV28_minimum.json tools/town_planner/ponyville_planV28_low.json tools/town_planner/ponyville_planV28_medium.json
```

Each setting gets its own `town_<setting>.tscn`, ground, paint and gardens, and its own trees
(`plan_density_trees.py`: every lawn filled until nowhere is more than 10 m from a tree).

Then the shores, the mailboxes and the banks' dressing (each once, in this order), and the repaint below:

```
python tools/town_planner/build/fix_shore.py .
python tools/town_planner/build/fix_mailboxes.py .
python tools/town_planner/build/bake_flow.py . tools/town_planner/ponyville_planV28_high.json
godot --headless --xr-mode off --path . --script res://tools/town_planner/build/make_river_dressing.gd
python tools/town_planner/build/place_river_dressing.py .
```

`fix_shore.py` reshapes every bank from a smooth outline of the water and lays the water surface over it;
`fix_mailboxes.py` gives every real home a clear mailbox; `make_river_dressing.gd` and `place_river_dressing.py`
make and set the reeds, shore grass and stones. The stream bed texture is `make_stream_bed_texture.py`'s.

To repaint only (after changing roads or paths in a plan):

```
python tools/town_planner/build/reset_inputs.py . paint
python tools/town_planner/build/apply_paint.py . tools/town_planner/ponyville_planV28_high.json
godot --headless --xr-mode off --path . --script res://tools/town_planner/build/apply_ground_half.gd
python tools/town_planner/build/apply_paint.py . tools/town_planner/ponyville_planV28_medium.json --density medium
python tools/town_planner/build/apply_paint.py . tools/town_planner/ponyville_planV28_low.json --density low
python tools/town_planner/build/apply_paint.py . tools/town_planner/ponyville_planV28_minimum.json --density minimum
```

Two parts of the game can't be rebuilt from source: the baked scenery's builder and the railway's track builder are
not in the source release. `apply_scenery.gd` edits the baked `rnl_scenery.scn` directly, and `cut_track.gd` can only
cut the old line out of town, so there are no trains.

## Pictures

Both run inside the real game with a window. Set `APPDATA` to a scratch folder first.

- The in-game map, for each density (put `[town] density="<setting>"` in the scratch folder's
  `home-equestria-public/town_density.cfg`; High needs none):

  ```
  godot --xr-mode off --resolution 1024x1024 --path . -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/capture_map.gd
  python tools/town_planner/build/make_map_tiles.py . [--density <setting>]
  ```

- The title screen's pictures (summer, each view at its own hour):

  ```
  godot --xr-mode off --resolution 1280x720 --path . -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/capture_vistas.gd [--views a,b]
  ```

## The mod pack

```
python tools/town_planner/build/make_overhaul_pack.py [--version 1.0.0]
```

Writes `build/out/ponyville_overhaul.pck`: every game file the overhaul changed since the game's 0.3.1.2 source,
read from what is staged in git, plus the item data in `build/overhaul_merge/`. Let Godot import new textures
and sounds once before packing. To test it from source, put the pack in the scratch folder's
`home-equestria-public/mods`.

## Checks

`build/qc/` holds labs that run inside the game (`--lab res://tools/town_planner/build/qc/<lab>.gd`, scratch
`APPDATA`): `town_lab.gd` (anything off the ground, homes, views), `perf_lab.gd` (frame cost at fixed views),
`stutter_lab.gd` and `lab_process_bisect.gd` (hitches while walking, and which mod script causes them),
`lab_visits.gd` and `lab_enter.gd` (ponies walking to and into landmarks), `lab_density.gd`, `lab_chest.gd`,
`lab_school_mod.gd` and others. Source runs need `tools/gaea_study/material_bank.gd`, or the ground renders white.

## Credits

The planner and the overhaul are by HorseBucker. Folded in: modChad's Pathfinding Fix, ponywizard's doorway pathing
fixes (pull request #20) and mitty's Ponyville Schoolhouse (with permission). MLPChag's Board Games works alongside:
its compatibility lines are carried in the overhaul's copies of the files both mods change.
