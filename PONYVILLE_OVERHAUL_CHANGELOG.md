# Ponyville Overhaul: changelog

By HorseBucker. For Home: Equestria **0.3.1.2-maredev** only.

## 1.0.3

- **Day counter in the save list.** 1.0.2 fixed the day shown in game for worlds started before the game's 0.3.1
  update, but the save list kept showing the wrong day for saves made before 1.0.2. It shows the real day now.

## 1.0.2

- **Day counter for older worlds.** The overhaul counts days from the day your world began, so a new world's first
  day is Day 1 instead of the base game's Day 35. Worlds started before the game's 0.3.1 update began on day 0, but
  were counted as if they'd begun in late summer, so a world on Day 53 showed Day 19. They show their real day again.

## 1.0.1: fixes from the first player report

- **Ponies home spot fixed.** Each pony's home spot, where she and her friends meet up, was set
  wherever she happened to be standing the first time the game saw her, and kept for good. Some ended up in the
  carrot fields and open country east of town (one 160 m from the pony's home), and other ponies kept gathering
  there. They're now set by each pony's own front door (or where she stands, if that's in town), and a world from
  before forgets the meeting spots it had out in the fields, once. A pony who ends up out of town with nowhere to go
  heads back in instead of standing there waiting.
- **Class at the schoolhouse after a night's sleep.** Sleeping from one school day's class into the next left the
  first class open, and the two fought over the fillies every frame. The old class now ends. Sleeping also no longer
  makes the game think a pony has been stuck all day and send her home.
- **Everypony vanished with modChad's Pathfinding Fix installed.** Its pack clashes with the copy built into the
  overhaul and left Ponyville with no navigation, so no pony could be placed. Its pack is now switched off when the
  town loads (it isn't needed: everything it does is built in).
- **Garden cypresses removed.** The tall bushes beside houses poked through the walls into the rooms, and looked out
  of place next to the town's other trees.
- **Changing the town density** no longer leaves a tree, bench or lamp standing inside your home when the setting
  you switch to didn't have a house there.
- **Sounds.** The windmill sound comes from the new windmills (both now), and the hens and wind chimes moved with the
  barn, Fluttershy's cottage and the Carousel Boutique.
- **Rivers and lakes, reworked.**
  - The banks follow a smooth outline of the water, with a low lip rising out of it, so the waterline curves
    naturally instead of stepping in a sawtooth. The bed slopes smoothly across every stream, so the narrow branches
    are one stream instead of a string of puddles.
  - The channels are a wide, gentle bowl rather than a ditch, and the roads beside them keep their level.
  - A new stream bed under the water and a little way up the bank: light, sandy earth with fine grit, in place of
    grass and of the game's blue river texture, fading softly into the grass.
  - The water shows the bed through it tinted teal in the shallows and deepens to blue, fading in at its edge. The
    shore has a faint soft edge instead of a hard white line, and the ripples are at stream scale and follow each branch round the forks.
  - Reeds and cattails, shore grass and stones gather at the forks, bends and bridge ends, with smaller clusters
    along the banks. They're batched like the gardens, so they cost little to draw.
  - Every bridge's posts reach down into the stream bed.
  - The lake beside the farmyard windmill has a proper bank instead of a straight cliff level with the water.
  - Ponies may hesitate for a minute or two the first time, while the game maps the new banks.
- **The spa's hoof file** is never put in the Town Hall chest. The spa always lays out its own, so a chested one
  was a copy, and copies already in the chest are removed.
- **Old saves:** gifts the ponies had set out in their old houses (Flower Gifts' bunches included) are set out again
  in their new homes instead of going into the chest. With unfplap, its footstools in ponies' houses are let go and
  it lays new ones in the new houses. This applies to worlds converted from now on. In a world already converted,
  those things stay in the chest.
- **Flower Gifts:** its town flower patches grow beside the new town's gardens, spread across the whole town, as
  they grew beside the old town's. Never on a roof, inside a house, under water, or on a street, path or dirt road.
  The snapdragons and moonflowers moved with the windmill and Fluttershy's cottage.
- **Mailboxes.** Every real home now has exactly one red mailbox (a quarter had none), off the street and clear of
  the door path, lamps, benches, trees and the neighbours' houses (one stood inside a lamp post), at every density.
- **Anon's Mailbox:** the green mailbox takes the place of your house's own red mailbox, instead of standing out in
  the street.
- **Watch Party 1.2.0 and earlier:** the television stand and the remote's counter are in the market's white tent
  instead of on a stream bank where the old market stood, and the vintage set lies at the Everfree's edge behind
  Fluttershy's new cottage.

## 1.0.0: first release

Ponyville is rebuilt from the ground up based on the official town map from Tails of Equestria. Everything below is a
change from the town the game ships with.

### The town

- **A new layout after the show's map.** New streets, squares and lanes, with every landmark where the map puts it:
  - in town: the Town Hall square, Sugarcube Corner, Golden Oak Library, Carousel Boutique, the schoolhouse, the Day
    Spa, the hospital, the train station, Hayburger and the market;
  - round the edges: Sweet Apple Acres (barn, orchard and farmyard), Fluttershy's cottage on its rise, Carrot Top's
    farm, the windmills, the Crusaders' clubhouse and the Cloudominium in the sky.
- **Houses.** Real homes that ponies live in, and background houses that fill out the streets. Every pony who lives in
  Ponyville has a home, and popular ponies get the bigger ones. The real homes use roomier house designs.
- **New ground and water.**
  - A flat village with grassy rises on its lawns, and gently rolling countryside.
  - Rivers that flow from springs into lakes, plus canals, a bog and a quiet brook sound.
  - A big hill north-east of town, with a picnic tree on top.
- **Bridges.**
  - 13 bridges over the new streams, three of them footbridges out to the southern meadows.
  - The three bridges to the Town Hall have a rounder, show-like arch. Their posts reach down into the water, and the
    banks under every bridge are grass instead of road.
  - The roads to the bridge by Fluttershy's cottage meet on dry ground and end square on the bridge, clear of the
    stream.
- **A new ground texture.** The show's dusty sage packed earth along the streets and squares, with lawn under the
  rows of houses and short paths from front doors to the street (some houses deliberately have none).
- **Dressing.** Trees, gardens, flowerbeds, street lamps, benches, picnic tables, wells, bunting round the Town Hall,
  the schoolhouse's picket fence and the farms' crop rows. Every density setting gets its own trees.
- **Background houses.**
  - Drawn as single cheap meshes, with opaque lilac windows as in the show.
  - A box sits behind every window and door, so you can't see through a house from any angle.
- **Lighting.** Street lamps light the streets, not the rooms behind the walls.
- **The railway** that ran through the new houses is cut out. The tool that lays the tracks isn't in the game's
  source code, so the line couldn't be rerouted round the new town, and there are no trains for now.
- **A storage chest in the Town Hall** for anything you want to keep. An old world's belongings wait in it too (see
  Old saves).
- **The map and title screen.**
  - The in-game map's aerial picture is retaken from the new town for every density setting, in summer with the
    trees in full leaf, and with Rainbow Dash's Cloudominium in it.
  - New title-screen pictures of the town, with 360-degree versions in VR.

### Settings

- **Town density** (Settings > Graphics). Each setting is its own smaller, more open village, with its own rises,
  trees and door paths; lower settings are also lighter to run.

  | Setting | Houses |
  |---|---|
  | Minimum | 75 |
  | Low | 130 |
  | Medium | 190 |
  | High | 260 |

  It applies the next time a world loads; "Reload world now" applies it at once. Your own home is kept at every
  setting.

### Performance

- **Shadows.** Houses cast their sun shadows from simplified shapes, and switch to full shadows within 30 m of you.
- **Background houses.** They have distance versions, and the most common designs are lighter still.
- **Result.** In testing at High density, a street view draws about 40% fewer triangles than before these changes,
  and a view over the whole town about 20% fewer.

### Ponies' lives

- **Homes and days.** Every pony's home, routines and favourite places follow the new town.
- **New residents.** Sunshower Raindrops, White Lightning, Cloudchaser and Thunderlane now live in Ponyville.
- **School.** mitty's Ponyville Schoolhouse is built in: the schoolhouse can be walked into, with a classroom of
  nine desks, Cheerilee's desk, a chalkboard, shelves and a door. On school days (Monday to Friday, not in the
  Hearth's Warming holidays) the foals set off at 8 and Cheerilee teaches from 9 to 3. With the AI on and you in
  the room, she teaches out loud, a foal may answer, and she may ask you to hand out worksheets or fetch the globe
  or telescope. Foals without a desk of their own, like Anonfilly, sit at the back of the room. Adults keep out of
  the schoolyard during class. Without the classroom (it failed to load), the class meets in the schoolyard instead.
- **The Cutie Mark Crusaders** go crusading around town together after school and on some days off, to a place
  that fits the day's idea.
- **Work and errands.**
  - Carrot Top tends her fields.
  - Cherry Berry gives balloon rides. If the balloon is left somewhere for a few hours, she fetches it back to its
    pad, walking it home on a rope in her mouth or flying it.
- **The fountain** has water in it, and ponies drink from it: small ones hop up onto the rim, tall ones lean down on bent forelegs. It has
  round collision.
- **Getting about town.**
  - Ponies spread out at places rather than piling onto one spot.
  - They rest on the grass rather than in the street, and use the street benches.
  - Ponies who agree to go somewhere together walk there together and chat when they arrive.
- **Hayburger.** Ponies come in by themselves for a meal: the restaurant sits level with the street, so they can step
  up through its door.
- **Pony size.** Doorways fit larger ponies (tested at 1.35 size), and each pony's personal space in crowds follows
  her size.
- **Quick lifts.** Picking a pony up for less than a second, without carrying her 1.5 m or more, isn't told to her
  AI, so you can nudge a stuck pony free without upsetting her.
- **The calendar.** A world's first day is Day 1 everywhere: the watch, the pause menu and the saved-games list.
- **Small fixes.** Cherry Berry's tail matches her mane; the picnic tables stand on the ground.

### Pathfinding

- **Bridges.** Trips over the streams are led across chains of bridges, and the route search prefers streets and
  bridges.
- **Into buildings.**
  - Ponies can walk to and into the Golden Oak, Town Hall, Sugarcube Corner, Fluttershy's cottage, the barn and the
    Carousel Boutique, and to the front of every other landmark.
  - They can follow you inside a house.
- **The same ground, near or far.** The walk grid measures the ground the same whether or not you're nearby, so a
  buried ramp or foundation no longer looks like a drop.
- **Arrival spots.**
  - A pony going to a landmark stands on open ground in front of it, never on a floor inside a closed building.
  - The Hayburger is met beside its front door.
- **Doorways and indoors.** Ponies walk single file through doorways, stand up beside furniture, and step clear of it
  indoors.
- **No more search storms.** A trip that can't be reached no longer searches again and again. Before, this could
  freeze a pony for a minute and halve the frame rate.
- **Stuck ponies.** A pony wedged somewhere is freed after 20 seconds even while you're watching.
- **Directions in conversation.** The ponies' place list says which way the big town places lie. When a landmark has
  an inside, the list gives the inside's own place id too, so "take me into Fluttershy's cottage" goes in.
- **Places from the old map are gone.**
  - Sweet Apple Acres and the barn point to the new farm.
  - Remembered places from an old save are forgotten once, and learnt again from the new town.
- **Flying home.** A pegasus flying home lands at her door, not on her roof.

### Old saves

A world started in the old town is brought over once, and a backup is kept in the world's `saves/archive` folder:
- **Your home.** Your old home is let go. Ask Mayor Mare or Princess Celestia for any empty house. Only the pony who
  gave you the old one hears that it's closed for repairs.
- **Your things.** Your belongings, and gifts ponies had set out in their old houses, go into a new storage chest in
  the Town Hall. The chest also holds other mods' items, which their mods still count.
- **Where you start.** If you saved in town, you start at the Town Hall's door, and ponies saved out in town start at
  home.

### Compatibility

- **Ponyville Schoolhouse (mitty).** Built in, so the pack isn't needed. If it's installed anyway, version 0.1.0 is
  switched off in favour of the built-in copy; a newer version runs instead of it. Either way there is only one
  classroom.
- **Board Games.** Both chess tables work: one by the fountain and one by the Golden Oak's fireplace. Its pony action
  is merged into the overhaul's copy of the same file, and does nothing without the mod.
- **Pedal Copter.** It parks by Sugarcube Corner.
- **Watch Party** places its TVs in the new town.
- **modChad's Pathfinding Fix** is built in (route choice, house ceilings, crowd spacing by size), so its own pack
  isn't needed. Since 1.0.1, if it's installed anyway it is switched off when the town loads; you can remove it.
- **Checked against the rest.** Every other bundled mod and the community mods tested (Queen Chrysalis, Cadance,
  Anonfilly, Mare Care, Fishing, Mailbox, Move In With Player, Pantyhose and others) work as they are.

### Known issues

- **First minutes after installing.** Ponies may pause before long trips while the game maps the new town.
- **Rainbow Dash's Cloudominium.** She can't yet walk inside it on her own. She lands at her door now.
- **The Day Spa.** It has an inside, but ponies only walk to its door; they don't go in yet.
- **Three of mitty's "favor" mods were made for the old town.** They work, but place their story items where the old
  town had things:
  - Applejack's Wagon Wheel (the farm wagon and spare wheel);
  - Fluttershy's Birdseed (the birdhouse grove);
  - Rainbow Dash's Rain Clouds (where Dash waits).

  They need their coordinates updated. Other mods that put things at fixed spots in the old town may need the same
  (Flower Gifts and Anon's Mailbox are handled since 1.0.1).
- **Mirror Pool with Pantyhose.** A few rendering errors were seen once in testing, and Pantyhose's shop items couldn't
  be sold. It's a load-order issue between those two mods.

### Credits

- **modChad:** the Pathfinding Fix 1.1.0, folded in.
- **ponywizard:** the doorway following and ground measuring from pull request #20.
- **MLPChag:** Board Games' compatibility lines, carried in the overhaul's copies of the files both mods change
  (Board Games itself is still needed for the chess tables).
- **mitty:** the Ponyville Schoolhouse 0.1.0, built in with permission.
- **The Home: Equestria developers:** the game this all stands on.
