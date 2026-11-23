# Ponyville Overhaul

A mod for Home: Equestria by HorseBucker. Ponyville rebuilt after the official map of the show's Ponyville: a dense,
show-like town of real homes and background houses, new streets, rivers, lakes and bridges, the landmarks where the
map has them, a hill to overlook it all from, and ponies' days to match.

**Made for game version 0.3.1.2-maredev only.** It replaces many of the game's own files (listed at the end), so a
different game version can break it.

## Install

1. Download `ponyville_overhaul.pck` from this repository's Releases.
2. Put it in the game's `mods` folder, next to the game's own `bundled` folder (not inside it).
3. Start the game. It shows up under Settings > Mods.

**Back up your saves first** (`%APPDATA%\home-equestria-public\worlds`). The first time a world from the old town
loads with the mod, it is brought over to the new town once (see "Old saves" below), and a copy of the save is kept
in the world's `saves/archive` folder.

## What it changes

### The town
- Ponyville laid out after the official map: the Town Hall square, the market, Sugarcube Corner, Golden Oak Library,
  Carousel Boutique, the schoolhouse, the day spa, the hospital, the train station, Sweet Apple Acres with its barn,
  orchard and farmyard, Fluttershy's cottage on its rise, Carrot Top's farm, windmills, the Cloudominium.
- About 260 houses: real homes ponies live in (every pony that lives in Ponyville has one) and background houses that
  fill the streets. Popular ponies live in bigger houses. Background houses are drawn as single cheap meshes.
- New ground: a flat village with grassy rises on its lawns, gently rolling countryside, rivers, canals and lakes that
  hold water, bridges over them, and a big hill north-east of the town with a tree on top, a good spot for a picnic.
- Street lamps light the streets, not the rooms behind the walls: houses stay dark inside at night.
- Trees, gardens, flowerbeds, lamps, benches, picnic tables, wells, bunting round the Town Hall, the schoolhouse's
  picket fence, crop rows on the farms.
- The old railway track that ran through the new houses is taken out (trains are switched off in this game version).
- The in-game map's aerial picture is retaken from the new town, for every town density.
- New title-screen pictures of the new town (the town at sunset, the schoolhouse, the barn, Fluttershy's cottage and
  the Town Hall at night), sharp at 1440p and fitting any window; VR keeps 360-degree versions.

### Settings (Settings > Graphics)
- **Town density**: Minimum (75 houses), Low (130), Medium (190), High (260). Lower settings make a smaller, more open
  village (lighter on a PC too, and some find it closer to the show), with their own grassy rises in the space that frees up and paths only to the doors still there; it
  applies the next time a world loads ("Reload world now" does it at once). Your own home is always kept, whatever
  the setting, and anything you set out in a house that a lower setting does not build waits in the Town Hall chest.

### Ponies
- Every pony's home, routines and favourite places follow the new town; pathing to doors and over every bridge.
- School: the foals go to school and Cheerilee teaches; with the AI on and Anon nearby, she gives a lesson she makes up.
- The Cutie Mark Crusaders go crusading on some days, to a place that fits the day's idea, and talk their plan over.
- Carrot Top tends her fields; Cherry Berry gives balloon rides, and fetches the balloon back to its pad when it has
  been left somewhere else for a few hours.
- Ponies drink from the Town Square fountain: small ponies hop up with their forehooves on the rim and sip, tall ones
  lean down on bent forelegs; quiet sip sounds. A pony who walks there with you, or decides to have a drink, goes and
  drinks.
- The fountain has round collision (no invisible corners).

### The Town Hall storage chest
- A golden chest in the Town Hall: take, store and discard things, including items from other mods (they stay counted
  by their mod, so no duplicates appear).

### Old saves
A world started in the old town is brought over once:
- Your old home is let go (it no longer exists); pick any empty house and ask Mayor Mare or Princess Celestia for it.
  Only the pony who gave you the old one hears that it is closed for repairs. Nopony else is told the town changed.
- Your belongings that were in the old home or lying around town go into the Town Hall chest, as do gifts ponies had
  set out in their old houses.
- You start at the Town Hall's door.

### Other mods
Tested together with the game's bundled mods (Board Games, Grooming, Flowing Manes, Idle Life, Balloon Boarding,
Teleport, Princess Teleport, Pegasus Ride, Kissing, Horn Glow, Dance, Tease/Shove, Pin the Tail, Mirror Pool, Pedal
Copter, Sit Anywhere, Output Console, Watch Party, AnonFilly). Some are adjusted from the overhaul's side, without
changing their files:
- **Board Games**: the public chess table stands on the grass by the fountain, and its table by the Golden Oak's
  fireplace and its pony action are kept in the overhaul's copies of the two files both replace.
- **Pedal Copter**: its parking spot is by Sugarcube Corner, facing south-east.
- **Watch Party** (1.2.2): the market's TV stand in the white tent, the old TV near Fluttershy's new cottage.

Known: with Mirror Pool on, a few rendering errors were seen once in testing and Pantyhose's shop items could not be
sold (a load-order issue between those two mods).

## Uninstalling
Take `ponyville_overhaul.pck` out of the mods folder. Worlds saved in the new town keep the new town's homes and
positions, which do not exist in the old one: start a new world or restore a backup from before the mod.

## For builders: the town planner
`tools/town_planner/` holds the planner used to make the town and the scripts that build a plan into the game. Open
`tools/town_planner/planner.html` in a browser and load a plan (`ponyville_planV28_high.json` is the one built). The
README there explains the plan format, the notes the build reads (`banner`, `chess table`, `hill`, `mound`,
`picnic tree`, Watch Party's `tv ...`), how to build (`build/build_all.py`, `build/build_density.py`), check
(`build/qc/`) and pack (`build/make_overhaul_pack.py`). The build needs this game version's source and Godot 4.5.

## Game files replaced
New files are not listed. Scripts and data the mod replaces (and so may conflict with another mod that replaces the
same file):

- `addons/godotshaders/toon_water.gdshader`
- `autoload/quality.gd`
- `world/ai/director_group.gd`
- `world/ai/pony_action_coordinator.gd`
- `world/ai/pony_action_executor.gd`
- `world/ai/pony_awareness.gd`
- `world/audio/soundscape.gd`
- `world/biomes/authored/bundle.json`
- `world/biomes/authored/index.json`
- `world/biomes/biome_field.gd`
- `world/buildings/boutique/architecture.gd`
- `world/buildings/boutique/interior.gd`
- `world/buildings/boutique/layout.gd`
- `world/buildings/boutique/shelves.gd`
- `world/buildings/cloudominium/cloud_drift.gd`
- `world/buildings/cloudominium/home.gd`
- `world/buildings/golden_oak/home.gd`
- `world/buildings/golden_oak/interior.gd`
- `world/buildings/hayburger/hayburger_interior.gd`
- `world/buildings/homes.json`
- `world/buildings/house_interior.gd`
- `world/buildings/trixie_wagon.gd`
- `world/characters/background/ai/shoeshine.json`
- `world/characters/background/roster.json`
- `world/characters/locomotion/placement_recovery.gd`
- `world/characters/locomotion/pony_locomotion.gd`
- `world/characters/locomotion/pony_posture.gd`
- `world/characters/navigation/house_travel.gd`
- `world/characters/navigation/navigator_commands.gd`
- `world/characters/navigation/navigator_routes.gd`
- `world/characters/navigation/navigator_wander.gd`
- `world/characters/navigation/pony_navigator.gd`
- `world/characters/princesses/princess_hybrid.gd`
- `world/characters/spike/spike.gd`
- `world/game_residents.gd`
- `world/housing/furnishing_rules.gd`
- `world/housing/home_furnishing.gd`
- `world/letters/letter_fallback.gd`
- `world/letters/letter_post.gd`
- `world/life/arrival_story.gd`
- `world/life/day/actions/bench_rest.gd`
- `world/life/day/actions/go_to.gd`
- `world/life/day/day_action.gd`
- `world/life/day/day_planner.gd`
- `world/life/day/day_runner.gd`
- `world/life/day/day_tables.json`
- `world/life/essence.gd`
- `world/life/living_world.gd`
- `world/life/living_world_runtime.gd`
- `world/life/night_rest.gd`
- `world/life/seating.gd`
- `world/life/stuck_rescue.gd`
- `world/main.tscn`
- `world/mechanics/data/events.json`
- `world/mechanics/data/jobs.json`
- `world/mechanics/data/stations.json`
- `world/mechanics/jobs/cider_stand.gd`
- `world/mechanics/mechanics.gd`
- `world/mechanics/stations/planting_plot.gd`
- `world/mechanics/stations/saa_sites.gd`
- `world/minigames/apple_bucking/harvest_state.gd`
- `world/minigames/fishing/dock_spec.json`
- `world/navigation/place_directory.gd`
- `world/navigation/river_crossings.gd`
- `world/navigation/walk_grid_service.gd`
- `world/navigation/walk_planner.gd`
- `world/painting/station_install.gd`
- `world/performance/town_render_budget.gd`
- `world/population/default_assignments.json`
- `world/population/pony_population_config.gd`
- `world/props/ponyville/farm_dressing.gd`
- `world/props/ponyville/farm_layout.json`
- `world/props/ponyville/rnl_scenery.json`
- `world/props/ponyville/rnl_scenery_defaults.tscn`
- `world/props/ponyville_kit/kit_dressing.gd`
- `world/props/ponyville_kit/kit_spots.gd`
- `world/props/ponyville_kit/placements.json`
- `world/saves/save_catalogue.gd`
- `world/seasons/season_state.gd`
- `world/seasons/snow_trail.gd`
- `world/terrain/sculpt/index.json`
- `world/terrain/textures.json`
- `world/terrain/world_terrain.gd`
- `world/towns/ponyville/pad_lifts.json`
- `world/towns/ponyville/town.tscn`
- `world/ui/aerial_map/manifest.json`
- `world/ui/aerial_map_layer.gd`
- `world/ui/baked_vistas.gd`
- `world/ui/named_map_places.json`
- `world/ui/pause_menu.gd`
- `world/ui/pony_map_icons.json`
- `world/ui/settings_page.gd`
- `world/ui/title_screen.gd`
- `world/ui/title_vista.gd`
- `world/ui/world_map_view.gd`
- `world/vehicles/balloon/balloon.gd`
- `world/water/ponyville_canals.json`
- `world/water/rivers.json`
- `world/water/world_water.gd`
- `world/world_layout.json`
- `world/railway/track.scn` (the railway, with the old line cut out of the town)

Also replaced: the in-game map's aerial pictures (`world/ui/aerial_map/`), the authored ground and vegetation tiles under the town (`world/biomes/authored/`), the title-screen pictures (`world/ui/baked_vistas/`) and 11 other assets (scenery, terrain).
