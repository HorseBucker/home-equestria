extends Node
## Waking a television with magic: a set out of the Everfree does nothing (finds.gd powered) until
## Anon brings one of its kind to somepony who can give it power of its own. Four ponies can
## (HELPERS): Twilight, Princess Celestia and Princess Luna (on their visits: world/life/
## princess_visits.gd keeps a visiting princess near Anon while this holds her), and Trixie, who is
## not very good at it (dev 2026-11-06): her spell leaves the set smoking, and when it is switched
## on there is a BLOW_CHANCE that it blows up (tv_blast.gd) and is gone. Anyone else (Rarity,
## say) can try in a conversation, but nothing here makes it work; the AI plays that out as it likes.
## Each helper knows only what she saw (finds.gd seen): a set woken or blown up near her counts, one
## woken elsewhere does not, so taking one set to Trixie, one to Twilight and one to Luna is three
## first times. They work it out together, a step at a time, each step waiting for Anon
## (playtest 2026-11-05: she talked and talked, and said it was on before it was):
## - She asks him to set it down somewhere sensible nearby (_suggestion: his own home if he has one
##   close; for Twilight else her library if it is not far, else a close friend's house right by;
##   else right where they are), and walks along behind him while he carries it there (_follow).
## - Once it stands near her she walks over and looks it over with her magic (horn lit, the set
##   glowing). The first time she tells him what she found and asks whether he knows how it works,
##   and waits for his answer; she answers that and asks him to try switching it on with the remote
##   while she watches with her magic (tv_controls.gd calls tried() when he does). What she saw
##   tells her what it needs, and she asks him to stand back.
## - With nopony talking, she casts the spell: a spark that never runs out, so it needs no plug and
##   works wherever it stands, indoors or out (tv_set.gd _standing). The remote in his hand gets a
##   spark too. The set stays dark (tv_set.gd arm) and she asks him to try again; when he switches it
##   on, the vintage set fills with static, a flatscreen shows "No Signal" (tv_set.gd power_up), and
##   only then does she react to it. If he never does, she switches it on herself after a while.
## - One she has seen before goes quicker (no question, a shorter look, no first try).
## - Without the remote (sold, say) she skips the tries and switches it on herself.
## - Anon can ask her to hold off and let somepony else have a go (HOLD_WORDS); naming another of the
##   helpers who is close by hands the set to her instead (before any spell is in it).
## - Bonus: if Anon holds up the remote near Twilight or a princess later, once a set works, she
##   gives it its spark then (once).
## Built on the game's story encounters (world/ai/encounters/encounter_runtime.gd), like the forest
## intro and Trixie's show: the AI says every line in its own words from a purpose (a beat's
## intent), never a script; this node does the walking, the looking and the spell (the beats with
## no intent) and marks them done. What just happened reaches her prompt as the encounter's
## LATEST EVENT (encounter_runtime.gd event). A beat that waits for Anon to speak (await_turn_s)
## is her reply to him when he does; she says it herself only if he stays quiet. The encounter does
## not hold her: Anon can talk, lead her home, anything; her purpose stays in her prompt until it
## is done. An encounter left from a save (world reloaded mid-quest) is cancelled on load and
## simply starts again. Skipped altogether with settings skip_quest ("Skip the magic").

const FINDS := preload("res://mods/watch_party/finds.gd")
const CATALOG := preload("res://mods/watch_party/catalog.gd")
const MAGIC := preload("res://world/characters/magic/unicorn_magic.gd")
const FX := "res://world/events/trixie_show/show_fx.gd"
const TWILIGHT := "twilight_sparkle"
const TRIXIE := "trixie"
## Who can wake a set: what she is like about it (mood), her spark, the names Anon may call her
## (call, a regex alternation), her magic's colour when her body has none, and whether she knows
## what she is doing (sure).
const HELPERS := {
	"twilight_sparkle": {"name": "Twilight", "names": "twilight|twi", "colour": Color("c58fe0"), "sure": true,
		"mood": "You are curious and a little excited: you have never seen anything like it.",
		"spark": "a little spark of your own magic that never runs out"},
	"celestia": {"name": "Princess Celestia", "names": "celestia|tia|princess", "colour": Color("ffd27a"), "sure": true,
		"mood": "In more than a thousand years you have seen a great many wonders, but never anything quite like this: you are curious, warm and a little amused.",
		"spark": "a tiny, steady spark of sunlight that never runs out"},
	"luna": {"name": "Princess Luna", "names": "luna|princess", "colour": Color("8a96f0"), "sure": true,
		"mood": "In all your long nights you have never seen the like: you are intrigued, and a little wary of it.",
		"spark": "a sliver of moonlight that never runs out"},
	"trixie": {"name": "Trixie", "names": "trixie", "colour": Color("6fb7ff"), "sure": false,
		"mood": "You have no idea what it is, but the Great and Powerful Trixie would never admit that: you are showy and boastful about it, and secretly not at all sure.",
		"spark": "a big, flashy spark of your own magic that you are fairly sure will never run out"},
}
const ORDER := ["twilight_sparkle", "celestia", "luna", "trixie"]
## How each helper goes about it, past what HELPERS says (dev 2026-11-07: "still noticeably the
## same prompt that Twilight got"). Twilight works it out with Anon, a step at a time, and has him
## try the remote while she watches (the functions below); the others each have their own:
## - Celestia sees at once that it is not of this world and asks what it was for in his world;
##   she flings it up to the sun and it comes back down bathed in sunlight (_sun), to a heavenly
##   tune; she lets him wake it, since it is his.
## - Luna senses it as a sleeper deep in a slumber and asks what it shows when awake; the world
##   dims, a pillar of moonlight comes down, the set rises and turns all the way round in it to a
##   heavenly tune (_moon), and it first wakes to a night sky (tv_set.gd wake_style "night").
## Both need the open sky (sky_needed when it stands under a roof).
## - Trixie tells him, with total confidence, what it is (very likely wrong) and asks him to agree;
##   a showy spell with sparks and smoke, his part to be her audience.
## Keys: notice (first time, %s her mood), notice_carry (%s mood, %s where), puzzle (%s what she sees
## close up, %s what her magic tells her), answer, try_again, explain_first, explain_again, cast (a
## line added to her spell's event), goal, commitment, label_puzzle, label_answer. Missing keys: the
## Twilight wording.
const STYLES := {
	"celestia": {
		"notice": "Anon has set the strange thing from the Everfree down before you. %s You are quite sure at a glance that it is not of this world. React to it calmly and warmly, in your own way, and say you would like a closer look. One to three sentences; do not explain what it is.",
		"notice_carry": "Anon has brought you a strange thing from the Everfree. %s You are quite sure at a glance that it is not of this world. React to it calmly and warmly, in your own way, and ask him kindly to set it down %s, so you can see it properly. One to three sentences; do not explain what it is.",
		"puzzle": "You have looked the strange thing over with your magic: %s. %s You can feel at once that no magic made it, and you are certain it does not come from Equestria or from anywhere in this world: it was built, with great care, by hands, around a flow of energy that does not exist here, and it must have come from Anon's world, as he did. Tell Anon one thing about it that touches you, in your own words; then, rather than asking how it works, ask him what it was for in his world, what folk there did with it. Do not cast anything.",
		"answer": "You asked Anon what the strange thing was for in his world. If he answered, respond warmly to what he actually said: it tells you something about where he comes from, and you may be curious, amused or moved. Then tell him you mean to give it a warmth of its own, from the sun itself, and ask him to stand back and watch. If he said nothing, just do that. You have not done anything to it yet: do not describe what you will do or say it works.",
		"try_again": "See LATEST EVENT: your spell is in, and the box is still dark. Invite Anon, gently, to wake it himself, since it is his. One or two short sentences. Do not say whether it worked: you do not know yet.",
		"explain_first": "See LATEST EVENT: the strange thing just woke, and the first thing on its glass is a sunrise, the sky warming to gold as a sun climbs over dark hills. React to it with quiet delight (you may well recognise your own sun), and tell Anon that a little piece of the sun lives inside it now, so it will never go dark for want of power, wherever he sets it down, indoors or out. End by asking whether he will show you what else it can do some day.",
		"explain_again": "See LATEST EVENT: it woke, as quickly as the one before. React briefly and warmly to what is on its glass and tell Anon it has its own little piece of the sun now. One or two sentences.",
		"cast_event": "You lifted the box with your magic and threw it, hard, straight up toward the sun. It tumbled away until it vanished with a twinkle; then it came back down out of the sky blazing like a falling star, and you caught it with your magic just above the ground and set it down gently where it had stood, still warm: %s is inside it now%s. It is still dark and silent: nopony has switched it on yet, so you do not know yet whether it worked.",
		"cast_self": "You threw the box straight up into the sun; it vanished with a twinkle and came back down blazing like a falling star, and you caught it just above the ground and set it down gently: %s is inside it now. Then you switched it on with a flick of magic",
		"goal": "look it over, learn from Anon what it was for in his world, and then give it a power source of its own",
		"commitment": "Look the strange thing over, ask Anon what it was for in his world, then give it a power source of its own with your magic. One step at a time: each step waits for Anon.",
		"label_puzzle": "telling Anon what you sense and asking what it was for in his world",
		"label_answer": "answering him and asking him to stand back and watch",
	},
	"luna": {
		"notice": "Anon has set a strange thing from the Everfree down before you. %s React to it in your own manner (a little formal, as you are) and say you would look closer upon it. One to three sentences; do not explain what it is.",
		"notice_carry": "Anon has brought a strange thing from the Everfree before you. %s React to it in your own manner and bid him set it down %s, that you may look upon it properly. One to three sentences; do not explain what it is.",
		"puzzle": "You have looked upon the strange thing with your magic: %s. %s To your senses it is like a pony fast asleep, whole and unharmed but sunk in a slumber nothing in Equestria can break, for what woke it in its own world came through its cord. Tell Anon what you sense, in your own words, rather as you might speak of a dreamer; then ask him what it shows when it is awake, what it dreams, as it were. Do not cast anything.",
		"answer": "You asked Anon what the strange thing shows when it is awake. If he answered, respond to what he actually said, briefly, in your own way. Then tell him you mean to call the moon's own light down upon it, and ask him to stand back and watch. If he said nothing, just do that. You have not done anything to it yet: do not describe what you will do or say it works.",
		"try_again": "See LATEST EVENT: your spell is in, and the box lies dark and silent, like a sleeper on the edge of waking. Bid Anon wake it himself, now. One or two short sentences. Do not say whether it worked: you do not know yet.",
		"explain_first": "See LATEST EVENT: the strange thing just woke, and the first thing on its glass is a night sky: your own night. React to it in your own way (you may be moved, or proud, or tease him a little), and tell Anon that a sliver of moonlight dwells in it now and will never wane, so it will wake wherever he sets it down, indoors or out, and that it is his.",
		"explain_again": "See LATEST EVENT: it woke, as the other did. React briefly to what is on its glass and tell Anon it holds its own sliver of moonlight now. One or two sentences.",
		"cast_event": "You called a pillar of moonlight down upon the box. The world around grew dim and still, and the box rose into the silver light, turned slowly all the way round, and settled again where it had stood: %s dwells in it now%s. It is still dark and silent: nopony has switched it on yet, so you do not know yet whether it worked.",
		"cast_self": "You called a pillar of moonlight down upon the box; it rose into the silver light, turned slowly all the way round and settled again: %s dwells in it now. Then you woke it with a touch of magic",
		"sky_needed": "You meant to call the moon's own light down upon the strange thing, but it is indoors, under a roof. Tell Anon, in a few words and in your own way, that it must stand beneath the open night sky for what you have in mind, and ask him to take it outside.",
		"goal": "look upon it, learn from Anon what it shows when awake, and then give it a power source of its own",
		"commitment": "Look upon the strange thing, ask Anon what it shows when it is awake, then give it a power source of its own with your magic. One step at a time: each step waits for Anon.",
		"label_puzzle": "telling Anon what you sense and asking what it shows when awake",
		"label_answer": "answering him and asking him to stand back and watch",
	},
	"trixie": {
		"notice": "Anon has set a strange thing from the Everfree down before you. %s React to it with flair, as if you had expected it all along, and announce that the Great and Powerful Trixie will examine it. One to three sentences; do not explain what it is.",
		"notice_carry": "Anon has brought you a strange thing from the Everfree. %s React to it with flair, as if you had expected it all along, and tell him to set it down %s, so Trixie can give it her expert attention. One to three sentences; do not explain what it is.",
		"puzzle": "You have looked the strange thing over, with plenty of flourish: %s. %s Rather than ask how it works, tell Anon with total confidence what it is and how it works: make up something that sounds magnificent and is very likely wrong. Then ask him, as if it were a formality, whether that is not exactly right. Do not cast anything.",
		"answer": "You told Anon, with total confidence, what the strange thing is, and asked whether you were right. If he answered, respond to what he said in your own way (if he corrected you, you knew that, of course: you were testing him). Then announce that the Great and Powerful Trixie will now bring it to life with a spell, and tell him, as your audience, to watch closely. If he said nothing, just do that. You have not cast anything yet: do not describe the spell or say it works.",
		"goal": "impress Anon: examine it with flair, explain it (whether or not you really know), and then give it a power source of its own",
		"commitment": "Put on a show for Anon with the strange thing: examine it with flair, tell him what it is, then give it a power source of its own with your magic. One step at a time: each step waits for Anon.",
		"label_puzzle": "telling Anon, with total confidence, what it is",
		"label_answer": "answering him and announcing your spell",
	},
}
## Celestia's throw (metres above where the set stands, seconds): she lifts it to SUN_WIND_HEIGHT
## and holds it a moment, throws it up to SUN_HEIGHT tumbling, it vanishes for SUN_GONE, comes
## back burning from SUN_BACK, falling fast to SUN_CATCH, where she catches it and sets it down. It
## needs the open sky (no roof over it: SKY_NEEDED otherwise).
const SKY_SFX := preload("res://mods/watch_party/sky_sfx.gd")
const SUN_WIND := 1.0
const SUN_WIND_HEIGHT := 1.8
const SUN_HEIGHT := 320.0
## Slow enough to follow it up (playtest 2026-11-07: "she threw it so fast that it basically
## vanished").
const SUN_RISE := 5.5
const SUN_GONE := 1.5
const SUN_BACK := 260.0
const SUN_FALL := 3.6
const SUN_CATCH := 8.0
const SUN_SETTLE := 2.4
## A princess's magic that has not finished after this long (seconds from the spell) is over all
## the same: the set back where it stood, the quest goes on (_end_ritual).
const RITUAL_LIMIT := 45.0
## Ponies this close see a princess's magic and may say something (_onlookers).
const SEEN_SKY := 45.0
const SUN_SEEN := "Princess Celestia just threw a strange box from Anon's world straight up into the sky with her magic, so high that it vanished with a twinkle, and now it is coming back down out of the sky on fire, like a falling star, close to you. React right away, in your own way: a sentence or two."
const MOON_SEEN := "Princess Luna just called a pillar of moonlight down out of the night sky onto a strange box from Anon's world, close to you: everything around has gone dim and still, and the box is rising and turning slowly in the silver light. React in your own way (quietly, if you like): a sentence or two."
## What Celestia's set first shows (tv_set.gd wake_style "sunrise").
const SUN_WAKE := "its glass lit up with a sunrise: a night sky warming from purple to gold as a sun climbs over dark hills. Your own sun, there on its glass."
## The princesses whose magic needs the open sky above the set.
const SKY_HELPERS := ["celestia", "luna"]
const HEAVENLY := preload("res://mods/watch_party/heavenly.gd")
## Luna's moonbeam (seconds): the world dims, the set rises and turns round once, and settles.
const MOON_DIM := 2.0
const MOON_TURN := 11.0
const MOON_RISE := 1.2
const MOON_LIGHT := Color(0.72, 0.78, 1.0)
## The dimming: everything further than DIM_INNER from the set darkens, fully past DIM_OUTER.
const DIM_INNER := 3.0
const DIM_OUTER := 9.0
const DIM_DEPTH := 0.82
const SKY_NEEDED := "You meant to give the strange thing its power from the sun itself, but it is indoors, under a roof. Tell Anon, in a few words and in your own way, that it needs to be out under the open sky for what you have in mind, and ask him to take it outside."
## Only Twilight has Anon try the remote while she watches it with her magic.
const WATCHES := ["twilight_sparkle"]

## Trixie's spell blows the set up when it is switched on this often.
const BLOW_CHANCE := 0.3
## A set that woke after her spell still smokes this long.
const SMOKE_AFTER := 30.0
## Her navigator's owner while this node walks her (the encounter lets this prefix move her).
const OWNER := "watch_party:"
const KEY := "watch_party_tv"
## Anon this close to her (metres, flat) with a set in hand or briefcase starts it; a set already
## standing this close to her starts it while he is within TALK_RANGE.
const SHOW_RANGE := 5.0
const PLACED_RANGE := 8.0
const TALK_RANGE := 10.0
## A set put down this close to her is the one she walks to.
const REACH_RANGE := 20.0
## Ponies this close to a set when it wakes saw it (finds.gd witness).
const SEEN_REACH := 15.0
## Anon this far from her for this long, with nothing put down: she lets it go for now.
const LOST_RANGE := 30.0
const LOST_SECONDS := 90.0
const GIVE_UP_SECONDS := 900.0
## After a quest that did not finish, her next waits this long.
const COOLDOWN := 120.0
## Anon naming a helper makes her the one a set goes to for this long (msec).
const WANTED_MSEC := 120000
const WALK_LIMIT := 45.0
## Following Anon while he carries the set: she keeps this far behind him, starts once he is
## further than FOLLOW_CLOSE and picks a new spot every FOLLOW_EVERY seconds.
const FOLLOW_GAP := 2.0
const FOLLOW_CLOSE := 3.5
const FOLLOW_EVERY := 1.5
## Where she stands to look: this far in front of the screen.
const STAND_OFF := 1.3
const EXAMINE_FIRST := 7.0
const EXAMINE_AGAIN := 3.0
## Her next step waits for nopony to have spoken for QUIET seconds. Her question waits ANSWER_WAIT
## for Anon's answer before she goes on by herself; she watches TRY_WAIT for him to try it with the
## remote, and waits SWITCH_WAIT after the spell for him to switch it on.
const QUIET := 2.0
const ANSWER_WAIT := 40.0
const TRY_WAIT := 60.0
const SWITCH_WAIT := 60.0
## Her purpose line is spoken within this long, or the quest moves on without it.
const LINE_WAIT := 60.0
## Anon asking her to hold off and let somepony else have a go (playtest 2026-11-06: he let Trixie
## try the third set, Twilight said "Fine, hooves off", and the spell went off at the next pause
## anyway). Held, her spell and her switching it on herself wait for his go-ahead (GO_WORDS, with
## her name), or for HOLD_QUIET seconds with nopony talking (whoever was trying has given up). Read
## from his words (_on_transcript): HOLD_WORDS anywhere; OFFER_WORDS only with another pony's name
## in the line ("Can you get it turned on, Trixie?"); SELF_WORDS (him wanting a go) only once her
## own steps are past the first set's question and try, where wanting a go is the plan anyway.
const HOLD_QUIET := 30.0
const HOLD_WORDS := "(?i)\\b(hooves off|hold (on|off|up)|not yet|wait (for|until|a (sec|second|minute|moment|bit))|don'?t (help|touch|do|cast|use|fix|spark|power|zap|magic|turn|switch|start)|let \\w+ (try|have a|do it|give it|go first)|(she|he|they) (try|tries|goes first)|(her|his|their) turn)\\b"
const SELF_WORDS := "(?i)\\b(let me (try|have|do|give)|my turn)\\b"
const OFFER_WORDS := "(?i)\\b(try|have a (go|try|crack|shot)|give it a|turn(ed)? (it )?on|switch(ed)? (it )?on|get it (working|going|on|turned)|can you|want to|your turn|you can do it)\\b"
const GO_WORDS := "(?i)\\b(go ahead|your turn,? (%s)|(%s),? (it'?s )?your turn|you do it|go for it|do your thing|help (her|him|them|us)|have at it|(okay|ok|alright|all right|fine),? (%s))\\b"
const HOLD_EVENT := "Anon asked you to hold off and let somepony else have a go first. Keep your magic to yourself: watch them try, react in your own way, and wait until it is your turn. You have not cast anything."
const GO_EVENT := "Anon says it is your turn now."
const GAVE_UP := "Nopony else got anywhere with it, so you took your turn. "
const CAST_SECONDS := 3.0
## Where she suggests setting it down (_suggestion): his home within HOME_NEAR of him, Twilight's
## library within LIBRARY_NEAR, a friend's house within FRIEND_NEAR.
const HOME_NEAR := 60.0
const LIBRARY_NEAR := 150.0
const FRIEND_NEAR := 50.0
const LIBRARY := "house:golden_oak_library"
## Houses of Twilight's close friends she would happily walk into with this (not the Cloudominium: clouds).
const FRIENDS := {
	"house:carousel_boutique": "Rarity's Carousel Boutique",
	"house:fluttershy_cottage": "Fluttershy's cottage",
	"house:sugarcube_tower": "Pinkie Pie's place at Sugarcube Corner",
	"shop:sugarcube_corner": "Sugarcube Corner, where Pinkie Pie lives",
	"landmark:appleacres_barned_01": "the barn at Sweet Apple Acres",
}
## The remote's spark: Anon holding the remote this close to her, after a set works.
const REMOTE_RANGE := 4.0
const REMOTE_CAST := 2.5
## The forest intro's stages (world/life/arrival_story.gd): Twilight is busy rescuing him.
const INTRO_STAGES := ["wake", "tutorial", "found", "teleport"]
const ORDINAL := ["first", "second", "third", "fourth", "fifth"]

const LOOKS := {
	FINDS.VINTAGE: "a big, heavy wooden box with a curved glass face, a row of knobs, and a cord ending in an odd little plug",
	FINDS.FLAT_STAND: "a thin, flat panel of black glass, smooth and shiny, standing on a low little table, with a cord ending in an odd little plug",
	FINDS.FLAT_WALL: "a thin, flat panel of black glass, smooth and shiny, with a bracket on its back as if it were meant to hang on a wall like a painting",
}
## How she thinks of one she saw before.
const SHORT := {
	FINDS.VINTAGE: "the big wooden box with the glass face",
	FINDS.FLAT_STAND: "the flat black glass panel on its little table",
	FINDS.FLAT_WALL: "the flat black glass panel made to hang on a wall",
}
const CLOSE_LOOKS := {
	FINDS.VINTAGE: "the glass face is grey and blank and curves outward, the knobs click when turned, and its cord ends in a pronged plug that fits nothing in Equestria",
	FINDS.FLAT_STAND: "the glass is perfectly black and you can see your own reflection in it, there are only a few tiny buttons along its edge, and its cord ends in a pronged plug that fits nothing in Equestria",
	FINDS.FLAT_WALL: "the glass is perfectly black and you can see your own reflection in it, there are only a few tiny buttons along its edge, and its cord ends in a pronged plug that fits nothing in Equestria",
}
## What her detection spell tells her, every time (Trixie's tells her much less).
const FOUND := "It is not broken and not alive: everything inside it is whole, just still, like a lamp nopony has lit, waiting for a steady flow of some kind of energy, the way a mill waits for water. Where it came from, that energy must have come in through the cord; there is nothing in Equestria for that plug to go into."
const FOUND_UNSURE := "Your magic tells you only a little: it is not alive and does not seem broken, and it seems to be waiting for some kind of energy to come in through its cord. Past that you are guessing, not that you would ever say so."
## What just happened, for her prompt (encounter LATEST EVENT).
const TRIED := "Anon just tried to switch the strange thing on with the little stick of buttons that came with it. Nothing happened at all, but your magic was watching: the stick sent a tiny call to the box, and the box reached down its cord for the steady flow it runs on and found nothing there."
const NOT_TRIED := "You have watched the strange thing with your magic for a good while and understood it: it is waiting to be fed a steady flow through its cord, and there is nothing in Equestria for that cord to go into."
const CAST := "You just cast your spell: %s is tucked inside the box where its cord goes in%s. The box is still dark and silent: nopony has switched it on yet, so you do not know yet whether it worked."
const CAST_UNSURE := " A thin curl of smoke is rising from the back of it now, and there is a smell like burnt toast; you are telling yourself that is perfectly normal."
const CAST_REMOTE := ", and a second, smaller one inside the stick of buttons in Anon's hand"
const SWITCHED := "Anon switched it on, and it woke: "
const SELF_SWITCHED := "Anon did not switch it on, so you did it yourself with a little flick of magic, and it woke: "
const STILL_SMOKING := " It is still smoking a little."
const BLEW := "%s, and it EXPLODED: a blinding flash, a fireball and a tremendous bang, bits of it flying everywhere and a cloud of black smoke rolling up, with a black scorch mark where it stood. There is nothing left of it worth keeping.%s%s"
## What Luna's set first shows (tv_set.gd wake_style "night").
const NIGHT_WAKE := "its glass filled with a peaceful night sky, stars twinkling and a soft moon shining among them: your own night, there on its glass."
const WAKE := {
	FINDS.VINTAGE: "it hissed, and its curved glass face filled with crackling grey snow.",
	FINDS.FLAT_STAND: "the black glass lit up, and the words NO SIGNAL are drifting slowly across it.",
	FINDS.FLAT_WALL: "the black glass lit up, and the words NO SIGNAL are drifting slowly across it.",
}
## Every one of her lines here: short, and leaving Anon room.
const SHORT_TURN := "At most three sentences, then stop and let Anon talk."
const CANT_REACH := "You meant to walk over to the strange thing Anon set down so you could look at it, but you cannot get to it where it is. Tell him so in a few words, in your own way, and ask him to put it somewhere you can reach."
const REMOTE_SPARK := "Anon just held out the little stick covered in buttons that came with the strange thing. Your magic told you it was just as lifeless as the box had been, waiting for the same kind of energy, so you gave it its own endless little spark too, the same way. Tell him so in a sentence or two, in your own way (you might guess the buttons are meant to work the box from across the room)."
const NEAR_BLAST := "A strange box from the Everfree that %s had cast a spell on just blew up with a tremendous bang, close to you%s. React to it right away in your own way: a sentence or two."

var hub: Node
## The quest under way: {key, helper, id, phase, t, since, first, actor, tv, spot, marker, aura, ...}; {} when none.
var _run: Dictionary = {}
var _check := 0.0
## Each helper's wait after a quest of hers that did not finish: {helper: seconds}.
var _cooldowns: Dictionary = {}
## The helper Anon named last (_on_transcript) and until when (msec) a set goes to her first.
var _wanted := ""
var _wanted_until := 0
## Anon spoke while she waits for his answer (the director's transcript is the player's own words),
## and somepony spoke after that (her reply to him).
var _heard := false
var _replied := false
## Seconds since anypony last spoke (the director idle).
var _quiet := 0.0
## The remote's spark under way: {actor, helper, remote, t, aura}; {} when none.
var _spark: Dictionary = {}

## A world opened: nothing under way. A quest left in its save is cancelled when it shows up
## (_cancel_stale) and starts again from the beginning.
func world(_game: Node) -> void:
	_run = {}
	_spark = {}
	_cooldowns = {}
	_wanted = ""

## Encounters of this quest in the world save that no quest here is running (a save made mid-quest).
func _cancel_stale(game: Node, encounters: Node) -> void:
	var context: Variant = game.get("world_context")
	var state: Variant = (context as Object).get("state") if context is Object else null
	var store: Variant = (state as Dictionary).get("encounters") if state is Dictionary else null
	if not store is Dictionary: return
	for key: Variant in (store as Dictionary).keys():
		if str(key).begins_with(KEY + ":") and str(key) != str(_run.get("key", "")) and bool(encounters.call("active", str(key))):
			encounters.call("cancel", str(key), "left from a save")
			print("[watch_party] quest: an unfinished quest from the save was reset")

func _exit_tree() -> void:
	if not _run.is_empty(): _finish(false, "Watch Party stopped")
	_end_spark()

func _physics_process(delta: float) -> void:
	for helper: Variant in _cooldowns.keys():
		_cooldowns[helper] = float(_cooldowns[helper]) - delta
		if float(_cooldowns[helper]) <= 0.0: _cooldowns.erase(helper)
	var director := _director()
	var idle := director == null or str(director.get("state")) == "idle"
	_quiet = _quiet + delta if idle else 0.0
	if _heard and not idle: _replied = true
	if not _spark.is_empty(): _sparking(delta)
	if not _run.is_empty():
		_step(delta)
		return
	_check -= delta
	if _check > 0.0: return
	_check = 1.0
	_orphans()
	_try_start()
	if _run.is_empty() and _spark.is_empty(): _try_spark()

# --- starting --------------------------------------------------------------------------------

func _director() -> Node:
	return get_tree().get_first_node_in_group("conversation_director") if is_inside_tree() else null

func _actor(director: Node, helper: String) -> Node3D:
	var characters: Variant = director.get("characters") if director != null else null
	if not characters is Dictionary or not (characters as Dictionary).has(helper): return null
	var node: Variant = (characters as Dictionary)[helper].get("node")
	return node as Node3D if is_instance_valid(node) and (node as Node3D).is_inside_tree() else null

func _name(helper: String) -> String:
	return str((HELPERS.get(helper, {}) as Dictionary).get("name", helper.capitalize()))

## A line of this helper's own way of going about it (STYLES), or `fallback` (Twilight's).
func _style(helper: String, key: String, fallback: String) -> String:
	var style: Variant = STYLES.get(helper)
	return str((style as Dictionary).get(key, fallback)) if style is Dictionary else fallback

func _sure(helper: String) -> bool:
	return bool((HELPERS.get(helper, {}) as Dictionary).get("sure", true))

func _inventory() -> Node:
	return Mods.game.get("inventory") as Node if is_instance_valid(Mods.game) else null

func _eye(inventory: Node) -> Vector3:
	var camera: Variant = inventory.get("camera") if is_instance_valid(inventory) else null
	return (camera as Node3D).global_position if camera is Node3D and (camera as Node3D).is_inside_tree() else Vector3.INF

## The goods Anon has with him: in his hands or in the briefcase (not set down somewhere).
func _carried(inventory: Node) -> Array:
	var ids: Array = []
	var held: Variant = inventory.get("held") if is_instance_valid(inventory) else null
	if held is Dictionary:
		for item: Variant in (held as Dictionary).values():
			if is_instance_valid(item): ids.append(str((item as Node).get_meta("item_id", "")))
	var store: Variant = inventory.get("inventory") if is_instance_valid(inventory) else null
	var slots: Variant = (store as Object).get("slots") if store is Object else null
	if slots is Array:
		for slot: Variant in slots:
			if slot is Dictionary and int((slot as Dictionary).get("count", 0)) > 0: ids.append(str(slot.get("id", "")))
	return ids

## A helper free to take a set now: there, awake, not held by another story, not resting from a
## quest that did not finish.
func _free(helper: String, director: Node, encounters: Node) -> Node3D:
	if _cooldowns.has(helper): return null
	var actor := _actor(director, helper)
	if actor == null or bool(actor.get("sleeping")) or bool(encounters.call("claimed", helper)): return null
	if helper == TWILIGHT:
		var story := get_tree().get_first_node_in_group("arrival_story")
		if story != null and story.has_method("stage") and str(story.call("stage")) in INTRO_STAGES: return null
	return actor

## What a helper would take: [id, placed] for a set standing near her (Anon within TALK_RANGE) or
## carried by Anon right by her; [] when none.
func _offer(actor: Node3D, eye: Vector3, inventory: Node) -> Array:
	var apart := _flat(eye, actor.global_position)
	if apart < TALK_RANGE:
		for node: Node in get_tree().get_nodes_in_group("watch_tvs_dormant"):
			var id := str(node.call("item_id"))
			if id in FINDS.TVS and not FINDS.powered(id) and _flat((node as Node3D).global_position, actor.global_position) < PLACED_RANGE: return [id, true]
	if apart < SHOW_RANGE:
		for id: Variant in _carried(inventory):
			if id in FINDS.TVS and not FINDS.powered(str(id)): return [str(id), false]
	return []

func _try_start() -> void:
	if FINDS.quest_skipped() or FINDS.state().is_empty(): return
	var game: Node = Mods.game
	var encounters: Node = game.get("encounters") as Node if is_instance_valid(game) else null
	var director := _director()
	if encounters == null or director == null: return
	_cancel_stale(game, encounters)
	if director.has_signal("transcript") and not director.is_connected("transcript", _on_transcript): director.connect("transcript", _on_transcript)
	var inventory := _inventory()
	var eye := _eye(inventory)
	if not eye.is_finite(): return
	# The one Anon asked for first, then the nearest.
	var wanted := _wanted if Time.get_ticks_msec() < _wanted_until else ""
	var best: Node3D = null
	var best_helper := ""
	var best_offer: Array = []
	var best_score := INF
	for helper: String in ORDER:
		var actor := _free(helper, director, encounters)
		if actor == null: continue
		var offer := _offer(actor, eye, inventory)
		if offer.is_empty(): continue
		var score := _flat(eye, actor.global_position) - (1000.0 if helper == wanted else 0.0)
		if score < best_score:
			best_score = score
			best = actor
			best_helper = helper
			best_offer = offer
	if best == null: return
	_begin(best_helper, str(best_offer[0]), bool(best_offer[1]), best, encounters, eye)

## What she saw before of these sets (finds.gd seen) and whether she saw one wake.
func _seen_woken(seen: Array) -> bool:
	return seen.any(func(row: Variant) -> bool: return row is Dictionary and not bool((row as Dictionary).get("blew", false)))

func _begin(helper: String, id: String, placed: bool, actor: Node3D, encounters: Node, eye: Vector3) -> void:
	var seen := FINDS.seen(helper)
	var key := "%s:%s:%d" % [KEY, id.get_slice(":", 1), FINDS.next_attempt()]
	var remote := FINDS.REMOTE in _carried(_inventory())
	var first := not _seen_woken(seen)
	var beats: Array = [
		{"id": "notice", "label": "noticing the strange thing", "speaker": helper, "intent": _notice_intent(helper, seen, placed, _suggestion(helper, eye))},
		{"id": "set_down", "label": "Anon sets it down near you"},
		{"id": "examine", "label": "looking it over with your magic"}]
	if first:
		var watches := remote and helper in WATCHES
		beats.append({"id": "puzzle", "label": _style(helper, "label_puzzle", "telling Anon what you found and asking whether he knows how it works"), "speaker": helper, "intent": _puzzle_intent(helper, id)})
		beats.append({"id": "answer", "label": _style(helper, "label_answer", "answering what Anon told you" + (" and asking him to try switching it on" if watches else "")), "speaker": helper, "intent": _style(helper, "answer", _answer_intent(watches)) + " " + SHORT_TURN if STYLES.has(helper) else _answer_intent(watches), "await_turn_s": ANSWER_WAIT})
		if watches:
			beats.append({"id": "try", "label": "Anon tries to switch it on while you watch it with your magic"})
			beats.append({"id": "insight", "label": "telling Anon what you saw and that you can give it power of its own", "speaker": helper, "intent": "See LATEST EVENT for what you just saw. Tell Anon in your own words what you understand about it now, and that you think you can give it a flow of its own with a spell; ask him to stand back. You have not cast anything yet: do not describe the spell or say it works. " + SHORT_TURN})
	beats.append({"id": "power", "label": "giving it a power source of its own with a spell"})
	if remote:
		var nerves := "with total confidence" if not _sure(helper) else "excited and a little nervous"
		beats.append({"id": "try_again", "label": "asking Anon to switch it on now", "speaker": helper, "intent": _style(helper, "try_again", "See LATEST EVENT: your spell is in, and the box is still dark. Ask Anon, %s, to try switching it on again now. One or two short sentences. Do not say whether it worked: you do not know yet." % nerves)})
		beats.append({"id": "switch_on", "label": "Anon switches it on"})
	beats.append({"id": "explain", "label": "seeing what happens when it is switched on, and telling Anon", "speaker": helper, "intent": _explain_intent(helper, seen)})
	var started: bool = encounters.call("begin", key, {
		"title": "working out the strange thing Anon brought from the Everfree" if first else "waking another of Anon's strange things from the Everfree",
		"participants": [helper], "movers": {helper: [OWNER]},
		"knows": {helper: _facts(helper, id, seen)},
		"commitment": {helper: _style(helper, "commitment", "Work out how the strange thing works together with Anon (look it over, ask him what he knows, watch him try it), then give it a power source of its own with your magic. One step at a time: each step waits for Anon.")},
		"beats": beats})
	if not started: return
	_run = {"key": key, "helper": helper, "id": id, "phase": "notice", "t": 0.0, "since": 0.0, "first": first, "remote": remote, "actor": weakref(actor), "lost": 0.0, "retakes": 0}
	_heard = false
	_replied = false
	if helper == "luna": HEAVENLY.prepare()
	if helper == "celestia": SKY_SFX.prepare()
	if helper in ["celestia", "luna"]:
		# Her visit (world/life/princess_visits.gd) walks her back to Anon whenever he is more than
		# a few metres off, every half second: it waits while she works on the set, and goes on
		# (to her farewell in its own time) once this is over.
		var visits: Node = Mods.game.get_node_or_null("PrincessVisits") if is_instance_valid(Mods.game) else null
		if visits != null and visits.is_processing():
			visits.set_process(false)
			_run.visits = weakref(visits)
	print("[watch_party] quest: %s is looking at the %s (%s she has seen)" % [_name(helper), FINDS.kind_name(id), ORDINAL[mini(seen.size(), 4)]])

# --- where to set it down ----------------------------------------------------------------------

## Every house loaded now: place id -> its node.
func _houses() -> Dictionary:
	var out: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("house_interiors"):
		if node is Node3D and node.has_method("place_id"): out[str(node.call("place_id"))] = node
	return out

## Anon's own home (the house reserved for him, or one he shares), or null.
func _his_home() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("house_interiors"):
		if node is Node3D and (str(node.get_meta("reserved_for", "")) == "player" or bool(node.get_meta("shared_player_home", false))): return node as Node3D
	return null

## Where she asks Anon to set the set down, as words for her purpose: inside wherever he is now;
## else his own home if he has one close by; for Twilight else her library if it is not far, else a
## close friend's house right by; else right where they are (it will work anywhere once woken).
func _suggestion(helper: String, eye: Vector3) -> String:
	if helper in SKY_HELPERS:
		return "somewhere outside, under the open sky" if not eye.is_finite() or CATALOG.house_at(get_tree(), [eye]) != null else "right here, out under the open sky"
	if not eye.is_finite(): return "right here, wherever is flat"
	if CATALOG.house_at(get_tree(), [eye]) != null: return "right here, somewhere on the floor where you can get all the way round it"
	var houses := _houses()
	var home := _his_home()
	if home != null and _flat(eye, home.global_position) < HOME_NEAR:
		return "inside his own home, which is close by"
	if helper == TWILIGHT:
		var library: Variant = houses.get(LIBRARY)
		if library is Node3D and _flat(eye, (library as Node3D).global_position) < LIBRARY_NEAR:
			return "inside your library (the Golden Oak Library is not far), where you have your books and tools to hand"
		for place: String in FRIENDS:
			var friend: Variant = houses.get(place)
			if friend is Node3D and _flat(eye, (friend as Node3D).global_position) < FRIEND_NEAR:
				return "inside %s, right by here (your friend won't mind)" % FRIENDS[place]
	return "right here on the ground: anywhere flat will do"

# --- what she knows and means to say -----------------------------------------------------------

## One thing she saw, in her words.
func _memory(helper: String, row: Dictionary) -> String:
	var thing := str(SHORT.get(str(row.get("id", "")), "one of them"))
	var by := str(row.get("by", ""))
	var who := "you" if by == helper else _name(by)
	if bool(row.get("blew", false)):
		return "you saw %s blow up with a tremendous bang when it was switched on after %s cast a spell on it" % [thing, "you had" if by == helper else who + " had"]
	if by == helper: return "you looked at %s and gave it a power source of its own with a spell, and it woke" % thing
	return "you watched %s give %s a power source of its own with a spell, and it woke" % [who, thing]

func _facts(helper: String, id: String, seen: Array) -> Array:
	var facts: Array = []
	var where := "Anon found it himself, lying in the Everfree Forest." if FINDS.found(id) else "A pony found it in the Everfree Forest and sold it at the Ponyville market as a curiosity, without knowing what it is; Anon bought it."
	facts.append("Anon has a strange object: %s. %s Nopony in Ponyville knows what it is." % [LOOKS[id], where])
	if seen.is_empty():
		facts.append("You have never seen anything like it. Anon may know what it is; you do not, and you do not know words like television, TV, screen, outlet or electricity unless Anon says them.")
		facts.append("This is the first of these you have looked at. You do not know of any others but the ones Anon tells you about.")
	else:
		var memories := PackedStringArray(seen.map(func(row: Variant) -> String: return _memory(helper, row as Dictionary) if row is Dictionary else ""))
		facts.append("You have seen these strange things before: %s." % "; ".join(memories))
		facts.append("This is the %s of them you have seen. You still do not know words like television, TV or electricity unless Anon says them." % ORDINAL[mini(seen.size(), 4)])
		if _seen_woken(seen): facts.append("You know the trick now: this one should be quick.")
		var same := seen.any(func(row: Variant) -> bool: return row is Dictionary and FINDS.is_flat(str(row.get("id", ""))) == FINDS.is_flat(id))
		if same: facts.append("This one is much like one you saw before.")
		else: facts.append("This one is a different kind from the one before: %s." % ("flatter, sleeker and newer-looking" if FINDS.is_flat(id) else "bulkier, wooden and old-fashioned"))
	if _his_home() != null: facts.append("Anon has a home of his own in Ponyville now.")
	else: facts.append("As far as you know, Anon has no home of his own in Ponyville yet.")
	facts.append("You cast spells on it only when this scene says you did (LATEST EVENT). Until then never describe yourself casting, or the thing waking, glowing or working.")
	facts.append("If Anon wants somepony else to have a go at it before you, let them: hold back and watch, and wait for your turn.")
	facts.append("Your goal: %s: %s, standing in for whatever made it go where it came from. Then it needs no cord or plug and will work wherever it is set down, indoors or out." % [_style(helper, "goal", "work out how it works, by looking it over with your magic and by asking Anon whether he knows, and then give it a power source of its own"), str(HELPERS[helper].spark)])
	if not _sure(helper): facts.append("In truth you have never done anything like this before and are making it up as you go, with as much flair as you can manage. Never admit that.")
	return facts

func _notice_intent(helper: String, seen: Array, placed: bool, where: String) -> String:
	var mood := str(HELPERS[helper].mood)
	if not _seen_woken(seen) and STYLES.has(helper):
		return _style(helper, "notice", "") % mood if placed else _style(helper, "notice_carry", "") % [mood, where]
	if not _seen_woken(seen):
		if placed: return "Anon has set the strange thing from the Everfree down right here. %s React to it in your own way and say you would like a closer look; you are about to walk over to it. One to three sentences; do not explain what it is." % mood
		return "Anon has brought the strange thing from the Everfree to you. %s React to it in your own way, and ask Anon to set it down %s, so you can take a proper look. One to three sentences; do not explain what it is." % [mood, where]
	if placed: return "Anon has set another of those strange things from the Everfree down right here. React briefly, with a nod to having seen one before, and say you will take a look. One or two sentences."
	return "Anon has brought you another of those strange things from the Everfree. React briefly, with a nod to having seen one before, and ask him to set it down %s. One or two sentences." % where

func _puzzle_intent(helper: String, id: String) -> String:
	if STYLES.has(helper) and (STYLES[helper] as Dictionary).has("puzzle"):
		return (_style(helper, "puzzle", "") % [CLOSE_LOOKS[id], FOUND if _sure(helper) else FOUND_UNSURE]) + " " + SHORT_TURN
	return "You have walked up to the strange thing and looked it over with your magic: %s. %s Tell Anon one or two curious things you found, in your own words, then ask him whether he knows what it is and how it is supposed to work. Do not cast anything. %s" % [CLOSE_LOOKS[id], FOUND if _sure(helper) else FOUND_UNSURE, SHORT_TURN]

## Her reply to his answer (or, if he says nothing, her next step anyway).
func _answer_intent(remote: bool) -> String:
	var next := "ask him to show you: to try switching it on with the little stick of buttons that came with it, while you watch it closely with your magic" if remote \
		else "tell him you think you can give it a steady flow of its own with a spell, and ask him to stand back"
	return "You asked Anon whether he knows what the strange thing is and how it works. If he answered, respond to what he actually said, briefly (a word you do not know, like electricity, delights you: ask about it). Then %s. If he has said nothing, just do that. You have not cast anything yet: do not describe a spell or say it works. %s" % [next, SHORT_TURN]

func _explain_intent(helper: String, seen: Array) -> String:
	if STYLES.has(helper) and (STYLES[helper] as Dictionary).has("explain_first"):
		return (_style(helper, "explain_first", "") + " " + SHORT_TURN) if not _seen_woken(seen) else _style(helper, "explain_again", "")
	if not _sure(helper):
		return "See LATEST EVENT for what just happened when it was switched on, and react to it right away, in character. If it woke, take all the credit (it was never in doubt, of course) and tell Anon it is his and has its own power now. If it blew up, react to the blast first (is everypony all right? is Anon?), then make excuses, blame the box, insist you meant to do that, or whatever fits you best. " + SHORT_TURN
	if not _seen_woken(seen):
		return "See LATEST EVENT: the strange thing just woke. React to what is on its glass right now (you do not know what it means: wonder about it), and tell Anon briefly that your spark will never run out, so it will work wherever he sets it down, indoors or out, and that it is his. End by asking him what it is meant to show. " + SHORT_TURN
	return "See LATEST EVENT: it woke, much quicker this time, with the same endless spark as before. React briefly to what is on its glass (you may compare it with the one you saw before) and tell Anon it has its own power now and is his. One or two sentences."

# --- the quest under way ---------------------------------------------------------------------

func _phase(name: String) -> void:
	_run.phase = name
	_run.since = 0.0

func _on_transcript(text: String) -> void:
	var named := _named_helper(text, str(_run.get("helper", "")))
	if not named.is_empty():
		_wanted = named
		_wanted_until = Time.get_ticks_msec() + WANTED_MSEC
	if _run.is_empty():
		if not named.is_empty(): _cooldowns.erase(named)
		return
	var helper := str(_run.helper)
	if str(_run.phase) in ["puzzle", "answer"]:
		_heard = true
		_replied = false
	if str(_run.phase) == "explain": return
	var encounters: Node = Mods.game.get("encounters") as Node if is_instance_valid(Mods.game) else null
	if encounters == null: return
	var held := bool(_run.get("held", false))
	var hold := RegEx.create_from_string(HOLD_WORDS).search(text) != null
	if not hold and str(_run.phase) not in ["puzzle", "answer", "try"]: hold = RegEx.create_from_string(SELF_WORDS).search(text) != null
	if not hold and _names_other(text): hold = RegEx.create_from_string(OFFER_WORDS).search(text) != null
	# Another helper named and close by, before any spell is in it: the set is hers to try now.
	if hold and not named.is_empty() and str(_run.phase) not in ["power", "prompt", "switch_on"] and _hand_over(named):
		return
	var names := str(HELPERS[helper].names)
	if held and not hold and RegEx.create_from_string(GO_WORDS % [names, names, names]).search(text) != null:
		_run.held = false
		_run.go = true
		encounters.call("event", helper, "go_ahead", GO_EVENT)
		print("[watch_party] quest: Anon gave %s the go-ahead" % _name(helper))
	elif hold and not held:
		_run.held = true
		encounters.call("event", helper, "holding", HOLD_EVENT)
		print("[watch_party] quest: %s holds off while somepony else has a go" % _name(helper))

## A helper (not `besides`) named in Anon's words who is here; "" when none.
func _named_helper(text: String, besides: String) -> String:
	var director := _director()
	for helper: String in ORDER:
		if helper == besides: continue
		if RegEx.create_from_string("(?i)\\b(%s)\\b" % str(HELPERS[helper].names)).search(text) == null: continue
		if _actor(director, helper) != null: return helper
	return ""

## The set goes from the helper under way to `helper`, who is free and close to Anon.
func _hand_over(helper: String) -> bool:
	var director := _director()
	var encounters: Node = Mods.game.get("encounters") as Node if is_instance_valid(Mods.game) else null
	if encounters == null: return false
	# Asked for by name, she has a go even if her own last try came to nothing.
	_cooldowns.erase(helper)
	var actor := _free(helper, director, encounters)
	var eye := _eye(_inventory())
	if actor == null or not eye.is_finite() or _flat(eye, actor.global_position) > TALK_RANGE: return false
	var from := str(_run.helper)
	_finish(false, "Anon asked %s to have a go instead" % _name(helper), false)
	print("[watch_party] quest: Anon hands it from %s to %s" % [_name(from), _name(helper)])
	_check = 0.0
	return true

## Another pony's name in Anon's words (the first part of her id: "trixie", "rainbow", "lyra").
func _names_other(text: String) -> bool:
	var characters: Variant = _director().get("characters") if _director() != null else null
	if not characters is Dictionary: return false
	var helper := str(_run.get("helper", ""))
	for id: Variant in (characters as Dictionary).keys():
		var name := str(id).get_slice("_", 0)
		if name.length() < 3 or str(id) == helper: continue
		if RegEx.create_from_string("(?i)\\b" + name + "\\b").search(text) != null: return true
	return false

## Held (Anon let somepony else have a go): still waiting, unless nopony has spoken for HOLD_QUIET
## (they gave up: it is her turn, and her next event says so).
func _holding() -> bool:
	if not bool(_run.get("held", false)): return false
	if _quiet < HOLD_QUIET: return true
	_run.held = false
	_run.gave_up = true
	print("[watch_party] quest: nopony else managed it; %s's turn" % _name(str(_run.helper)))
	return false

func _step(delta: float) -> void:
	_run.t = float(_run.t) + delta
	_run.since = float(_run.since) + delta
	var actor: Node3D = (_run.actor as WeakRef).get_ref() as Node3D
	var game: Node = Mods.game
	var encounters: Node = game.get("encounters") as Node if is_instance_valid(game) else null
	var key := str(_run.key)
	var helper := str(_run.helper)
	if actor == null or not actor.is_inside_tree() or encounters == null or not bool(encounters.call("active", key)):
		_finish(false, "%s left or the scene ended" % _name(helper))
		return
	if float(_run.t) > GIVE_UP_SECONDS:
		_finish(false, "it took too long")
		return
	var id := str(_run.id)
	if FINDS.powered(id) and str(_run.phase) in ["notice", "wait", "walk", "blocked"]:
		_finish(false, "that kind works already")
		return
	var since := float(_run.since)
	match str(_run.phase):
		"notice", "wait":
			# Set down near her, it is down: whatever she was about to ask, she goes to look
			# (playtest 2026-11-05: still asking him to set it down once it was).
			var tv := _placed_tv(id, actor)
			if tv != null:
				encounters.call("mark_delivered", key, "notice")
				encounters.call("mark_delivered", key, "set_down")
				_run.tv = weakref(tv)
				_walk(actor, tv)
				return
			if str(_run.phase) == "notice":
				if bool(encounters.call("delivered", key, "notice")) or since > LINE_WAIT: _phase("wait")
				return
			_follow(actor, id, delta)
			var eye := _eye(_inventory())
			_run.lost = float(_run.lost) + delta if not eye.is_finite() or _flat(eye, actor.global_position) > LOST_RANGE else 0.0
			if float(_run.lost) > LOST_SECONDS: _finish(false, "Anon went away with it")
		"walk": _walking(actor)
		"sky":
			# Celestia's set is under a roof: once it stands outdoors, she walks to it and goes on.
			var tv := _tv() if _tv() != null else _placed_tv(str(_run.id), actor)
			if tv != null and bool(tv.get("dormant")) and CATALOG.house_at(get_tree(), [tv.global_position]) == null and since > 2.0:
				_run.tv = weakref(tv)
				_run.sky_ready = true
				_walk(actor, tv)
		"blocked":
			# Waits for the set to be put down somewhere else.
			var tv := _tv()
			var moved := tv == null or tv.global_position.distance_to(_run.blocked_at) > 0.3 or not bool(tv.get("dormant"))
			if moved and since > 2.0: _phase("wait")
		"examine":
			if since >= (EXAMINE_FIRST if bool(_run.first) else EXAMINE_AGAIN):
				_unglow()
				encounters.call("mark_delivered", key, "examine")
				_phase("puzzle" if bool(_run.first) else "ready")
		"puzzle":
			if bool(encounters.call("delivered", key, "puzzle")) or since > LINE_WAIT:
				encounters.call("mark_delivered", key, "puzzle")
				_heard = false
				_replied = false
				_phase("answer")
		"answer":
			# Her reply to his answer is this beat; she says it unprompted only if he says nothing
			# (await_turn_s), and the encounter then marks it.
			# A second of quiet after her reply: before the encounter (1.5 s) would say it again.
			var answered := _heard and _replied and _quiet > 1.0
			if answered or since > ANSWER_WAIT + LINE_WAIT: encounters.call("mark_delivered", key, "answer")
			if bool(encounters.call("delivered", key, "answer")):
				_heard = false
				if bool(_run.remote) and str(_run.helper) in WATCHES: _start_watch(actor)
				else: _phase("ready")
		"try":
			if bool(_run.get("tried", false)) or since > TRY_WAIT:
				var watched := TRIED if bool(_run.get("tried", false)) else NOT_TRIED
				if not _sure(helper): watched = "Anon just tried to switch the strange thing on with the little stick of buttons that came with it. Nothing happened at all. Your magic felt something like a tiny call go from the stick to the box, and the box looking for something it did not find; you think." if bool(_run.get("tried", false)) else FOUND_UNSURE
				encounters.call("event", helper, "watched", watched)
				_unglow()
				encounters.call("mark_delivered", key, "try")
				_phase("insight")
			elif float(_run.get("horn", 0.0)) <= since and actor.has_method("cast_magic"):
				# Her horn stays lit while she watches.
				actor.call("cast_magic", 4.5)
				_run.horn = since + 4.0
		"insight":
			if bool(encounters.call("delivered", key, "insight")) or since > LINE_WAIT:
				encounters.call("mark_delivered", key, "insight")
				_phase("ready")
		"ready":
			# The spell only with nopony talking, and not while somepony else has a go.
			if _holding(): return
			if _quiet > QUIET or since > LINE_WAIT or bool(_run.get("go", false)) or bool(_run.get("gave_up", false)): _phase("power")
		"power": _casting(actor, encounters, key)
		"prompt", "switch_on": _switching(actor, encounters, key)
		"explain":
			if bool(encounters.call("delivered", key, "explain")) or since > LINE_WAIT:
				encounters.call("complete", key)
				_finish(not bool(_run.get("blew", false)), "done" if not bool(_run.get("blew", false)) else "it blew up")

func _tv() -> Node3D:
	var ref: Variant = _run.get("tv")
	var tv: Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
	return tv as Node3D if is_instance_valid(tv) and (tv as Node3D).is_inside_tree() else null

## A set of this kind standing (placed or set down, not woken) near her.
func _placed_tv(id: String, actor: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance := REACH_RANGE
	for node: Node in get_tree().get_nodes_in_group("watch_tvs_dormant"):
		var tv := node as Node3D
		if tv == null or str(tv.call("item_id")) != id: continue
		var distance := _flat(tv.global_position, actor.global_position)
		if distance < best_distance:
			best = tv
			best_distance = distance
	return best

func _nav(actor: Node3D) -> Node:
	return actor.get_node_or_null("Navigator")

## A value of one of the navigator's enums (world/characters/navigation/pony_navigator.gd), read
## from its script.
func _enum(nav: Node, enum_name: String, key: String, fallback: int) -> int:
	var script: Variant = nav.get_script()
	var values: Variant = (script as Script).get_script_constant_map().get(enum_name) if script is Script else null
	return int((values as Dictionary).get(key, fallback)) if values is Dictionary else fallback

## While Anon carries the set (to where she suggested, say), she walks along a couple of metres
## behind him, so it is near her wherever he puts it down. She stops when he stops or puts it away.
func _follow(actor: Node3D, id: String, delta: float) -> void:
	var nav := _nav(actor)
	var eye := _eye(_inventory())
	if nav == null or not eye.is_finite(): return
	var apart := _flat(eye, actor.global_position)
	var carrying := id in _carried(_inventory())
	if not carrying or apart < FOLLOW_CLOSE or apart > LOST_RANGE:
		if bool(_run.get("following", false)):
			_run.following = false
			_release(actor)
		return
	_run.follow_t = float(_run.get("follow_t", 0.0)) - delta
	if bool(_run.get("following", false)) and float(_run.follow_t) > 0.0: return
	_run.follow_t = FOLLOW_EVERY
	var anon := Vector3(eye.x, actor.global_position.y, eye.z)
	var back := actor.global_position - anon
	back.y = 0.0
	var spot := anon + (back.normalized() if back.length() > 0.01 else Vector3.BACK) * FOLLOW_GAP
	if nav.has_method("command_support"):
		var ground: Vector3 = nav.call("command_support", spot)
		if ground.is_finite(): spot = ground
	if not bool(_run.get("following", false)) and actor.has_method("request_posture"): actor.call("request_posture", "stand")
	nav.set("command_owner", OWNER + str(_run.helper))
	nav.call("go_to", spot, _enum(nav, "Gait", "WALK", 1))
	_run.following = true

func _walk(actor: Node3D, tv: Node3D) -> void:
	var nav := _nav(actor)
	if nav == null:
		_finish(false, "%s has no navigator" % _name(str(_run.helper)))
		return
	var out := Vector3(tv.global_basis.z.x, 0.0, tv.global_basis.z.z).normalized()
	var spot := tv.global_position + out * STAND_OFF
	if nav.has_method("command_support"):
		var ground: Vector3 = nav.call("command_support", spot)
		if ground.is_finite(): spot = ground
	_run.spot = spot
	_run.following = false
	if actor.has_method("request_posture"): actor.call("request_posture", "stand")
	nav.call("stay")
	nav.set("command_owner", OWNER + str(_run.helper))
	nav.call("go_to", spot, _enum(nav, "Gait", "WALK", 1))
	_phase("walk")

func _walking(actor: Node3D) -> void:
	var tv := _tv()
	if tv == null or not bool(tv.get("dormant")):
		# Picked up again while she was on her way.
		_release(actor)
		_phase("wait")
		return
	var nav := _nav(actor)
	var since := float(_run.since)
	if nav == null: return
	if str(nav.get("command_owner")) != OWNER + str(_run.helper):
		# Something else moved her (Anon asked her to follow, a visit): back to it in a moment.
		if since > 5.0:
			_run.retakes = int(_run.retakes) + 1
			if int(_run.retakes) > 3:
				_finish(false, "she kept being taken elsewhere")
				return
			_walk(actor, tv)
		return
	var spot: Vector3 = _run.spot
	var state: Variant = nav.get("state")
	if _flat(actor.global_position, spot) < 0.7 or state == _enum(nav, "State", "ARRIVED", -100):
		_arrive(actor, tv)
		return
	var stuck: bool = (state == _enum(nav, "State", "UNREACHABLE", -100) or state == _enum(nav, "State", "BLOCKED", -100)) and since > 3.0
	if stuck or since > WALK_LIMIT:
		_release(actor)
		_run.blocked_at = tv.global_position
		_say(CANT_REACH, actor, str(_run.helper))
		print("[watch_party] quest: %s cannot reach the set (%s)" % [_name(str(_run.helper)), "no way there" if stuck else "too long"])
		_phase("blocked")

func _colour(actor: Node3D) -> Color:
	var magic: Variant = actor.get("magic") if is_instance_valid(actor) else null
	var own: Variant = (magic as Node).get("color") if magic is Node else null
	return own if own is Color else HELPERS.get(str(_run.get("helper", "")), {}).get("colour", Color("c58fe0"))

## She is there: she faces it, looks at it and goes over it with her magic (horn lit, set glowing).
func _arrive(actor: Node3D, tv: Node3D) -> void:
	var nav := _nav(actor)
	nav.call("stay")
	var marker := Node3D.new()
	marker.name = "WatchPartyLook"
	var spec: Variant = tv.get("spec")
	if spec is Dictionary and (spec as Dictionary).has("centre"):
		var centre: Vector2 = spec.centre
		marker.position = Vector3(centre.x, centre.y, float((spec as Dictionary).get("z", 0.0)))
	else:
		marker.position = Vector3.UP * 0.6
	tv.add_child(marker)
	_run.marker = marker
	nav.set("face_point", marker.global_position)
	if actor.has_method("set_action_gaze"): actor.call("set_action_gaze", marker)
	var seconds := EXAMINE_FIRST if bool(_run.first) else EXAMINE_AGAIN
	if actor.has_method("cast_magic"): actor.call("cast_magic", seconds)
	var magic: Variant = actor.get("magic")
	if magic is Node and (magic as Node).has_method("glow_object"): _run.aura = (magic as Node).call("glow_object", tv.get_parent(), 0.55)
	if not _sure(str(_run.helper)):
		# Trixie looks it over with a flourish.
		var fx: Script = load(FX)
		if fx != null: fx.call("sparks", tv, marker.global_position, 0.6, _colour(actor))
	if bool(_run.get("sky_ready", false)):
		# Back after taking it outside: she already looked it over.
		_unglow()
		_phase("ready")
		return
	_phase("examine")

## She watches it with her magic (horn lit, the set softly glowing) while Anon tries the remote.
func _start_watch(actor: Node3D) -> void:
	var tv := _tv()
	var magic: Variant = actor.get("magic")
	if tv != null and magic is Node and (magic as Node).has_method("glow_object"): _run.aura = (magic as Node).call("glow_object", tv.get_parent(), 0.35)
	_run.tried = bool(_run.get("tried", false))   # he may have tried it already
	_run.horn = 0.0
	_phase("try")

## tv_controls.gd: Anon pressed a remote button at a set that does not work yet.
func tried() -> void:
	if not _run.is_empty() and str(_run.phase) in ["answer", "try"]: _run.tried = true

## The spell: horn held lit, a burst on the screen (and on the remote in his hand), and the set
## holds her spark, dark until it is switched on (tv_set.gd arm); without the remote she switches
## it on herself. Trixie's leaves it smoking, and may have doomed it (tv_set.gd doomed).
func _casting(actor: Node3D, encounters: Node, key: String) -> void:
	var tv := _tv()
	var helper := str(_run.helper)
	var magic: Variant = actor.get("magic")
	var colour := _colour(actor)
	if not bool(_run.get("casting", false)):
		if tv == null:
			_finish(false, "the set is gone")
			return
		if helper in SKY_HELPERS and CATALOG.house_at(get_tree(), [tv.global_position]) != null:
			_say(_style(helper, "sky_needed", SKY_NEEDED), actor, helper)
			_release(actor)
			print("[watch_party] quest: %s needs the set under the open sky" % _name(helper))
			_phase("sky")
			return
		_run.casting = true
		if helper == "celestia":
			_sun(actor, tv)
			return
		if helper == "luna":
			_moon(actor, tv)
			return
		if actor.has_method("cast_magic"): actor.call("cast_magic", CAST_SECONDS + 0.8)
		if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", true)
		if magic is Node and (magic as Node).has_method("glow_object"): _run.aura = (magic as Node).call("glow_object", tv.get_parent(), 1.0)
		var marker: Variant = _run.get("marker")
		var at: Vector3 = (marker as Node3D).position if is_instance_valid(marker) else Vector3.UP * 0.6
		MAGIC.burst(tv, at, colour, CAST_SECONDS, 0.35)
		if not _sure(helper):
			var fx: Script = load(FX)
			if fx != null:
				fx.call("sparks", tv, tv.to_global(at), CAST_SECONDS, colour)
				fx.call("puff", tv, tv.to_global(at), colour, 0.8)
		var remote := _held_remote(_inventory())
		var eye := _eye(_inventory())
		if remote != null and eye.is_finite() and _flat(eye, actor.global_position) < REMOTE_RANGE * 2.0 and not bool(FINDS.state().get("remote_powered", false)):
			if magic is Node and (magic as Node).has_method("glow_object"): _run.remote_aura = (magic as Node).call("glow_object", remote, 1.0)
			MAGIC.burst(remote, Vector3.ZERO, colour, CAST_SECONDS, 0.12)
			_run.sparked_remote = true
		return
	if helper in SKY_HELPERS and not bool(_run.get("sun_done", false)):
		if float(_run.since) < RITUAL_LIMIT: return
		print("[watch_party] quest: %s's magic did not finish; the set is put back" % _name(helper))
		_end_ritual()
	if helper not in SKY_HELPERS and float(_run.since) < CAST_SECONDS: return
	if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", false)
	_unglow()
	FINDS.power(str(_run.id), helper)
	var sparked := bool(_run.get("sparked_remote", false))
	if sparked:
		var data := FINDS.state()
		data.remote_powered = true
		FINDS.changed()
	if not _sure(helper) and tv != null:
		tv.call("smoke", INF)
		tv.set("doomed", randf() < BLOW_CHANCE)
		print("[watch_party] quest: Trixie's spell is in (%s)" % ("it will blow" if bool(tv.get("doomed")) else "it will hold"))
	var turn := GAVE_UP if bool(_run.get("gave_up", false)) else ""
	_run.gave_up = false
	_run.go = false
	var spark := str(HELPERS[helper].spark)
	if not bool(_run.remote):
		encounters.call("mark_delivered", key, "power")
		if tv != null: _switched(tv, encounters, key, turn + (_style(helper, "cast_self", "") % spark if STYLES.has(helper) and (STYLES[helper] as Dictionary).has("cast_self") else "You cast your spell, %s.%s Then you switched it on with a flick of magic" % [spark, _style(helper, "cast", "")]), true)
		return
	if tv != null: tv.call("arm")
	encounters.call("event", helper, "cast", turn + _style(helper, "cast_event", CAST) % [spark, CAST_REMOTE if sparked else ""] + _style(helper, "cast", "") + (CAST_UNSURE if not _sure(helper) else ""))
	encounters.call("mark_delivered", key, "power")
	print("[watch_party] quest: the spell is in; waiting for Anon to switch it on")
	_phase("prompt")

## Celestia's way (dev 2026-11-07: "it should look like she literally chucks it up into the sun"):
## she lifts the set and holds it a moment (the wind-up), then throws it: her magic lets go, and it
## tumbles away upward, slowing, to a speck high above; a twinkle, and it is gone. A moment later it
## comes back down burning like a meteor (flames, smoke, a roar that swells as it nears), falling
## fast, until just above the ground her magic catches it (a thump, a puff of steam, the flames
## out with a hiss) and sets it gently down where it stood, still glowing warm. Ponies near see it
## (_onlookers); its first picture is a sunrise (tv_set.gd prepare_wake).
## A stunt double makes the flight (_stunt_double: a plain copy of the set's look), while the set
## itself waits hidden and out of reach where it stood (playtest 2026-11-07: the game takes back a
## set lying more than 90 m from Anon, world/inventory/briefcase_drops.gd, and the real one thrown
## 320 m up was taken back mid-flight, the throw with it). _end_ritual puts everything back and
## tells _casting it is over (sun_done).
func _sun(actor: Node3D, tv: Node3D) -> void:
	var body: Variant = tv.get("body")
	var visual := tv.get_parent() as Node3D
	if not body is RigidBody3D or not (body as RigidBody3D).is_inside_tree() or visual == null:
		_run.sun_done = true
		return
	var item := body as RigidBody3D
	var game: Node = Mods.game if is_instance_valid(Mods.game) else tv
	var flier := _stunt_double(visual, game)
	if flier == null:
		_run.sun_done = true
		return
	_run.ritual = {"item": weakref(item), "layer": item.collision_layer, "freeze": item.freeze, "start": item.global_transform, "flier": weakref(flier)}
	item.freeze = true
	item.collision_layer = 0
	item.visible = false
	tv.call("prepare_wake", "sunrise")
	var home := flier.global_transform
	var colour := _colour(actor)
	var magic: Variant = actor.get("magic")
	var fly := {}
	if actor.has_method("cast_magic"): actor.call("cast_magic", SUN_WIND + 0.6)
	if actor.has_method("set_action_gaze"): actor.call("set_action_gaze", flier)
	if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", true)
	if magic is Node and (magic as Node).has_method("glow_object"): fly.aura = (magic as Node).call("glow_object", flier, 1.0)
	var flip := func() -> float: return 1.0 if randf() < 0.5 else -1.0
	var spin := Vector3(randf_range(3.0, 6.0) * flip.call(), randf_range(2.0, 4.5) * flip.call(), randf_range(2.5, 5.5) * flip.call())
	var wind_at := home.origin + Vector3.UP * SUN_WIND_HEIGHT
	var top := home.origin + Vector3.UP * SUN_HEIGHT
	var back_at := home.origin + Vector3.UP * SUN_BACK
	var catch_at := home.origin + Vector3.UP * SUN_CATCH
	var climb := func(t: float) -> void:
		if not is_instance_valid(flier): return
		var seconds := t * SUN_RISE
		var wobble := Vector3(sin(seconds * 1.7), sin(seconds * 2.3 + 1.0), sin(seconds * 1.1 + 2.0)) * 0.6
		flier.global_transform = Transform3D(home.basis * Basis.from_euler(spin * seconds * (1.0 - 0.35 * t) + wobble), wind_at.lerp(top, 1.0 - pow(1.0 - t, 1.7)))
	var fall := func(t: float) -> void:
		if not is_instance_valid(flier): return
		var seconds := t * SUN_FALL
		var rock := Vector3(sin(seconds * 3.1) * 0.22, seconds * 1.4, sin(seconds * 2.6 + 0.7) * 0.22)
		flier.global_transform = Transform3D(home.basis * Basis.from_euler(rock), back_at.lerp(catch_at, t * t))
	var settle := func(t: float) -> void:
		if not is_instance_valid(flier): return
		var from: Transform3D = fly.get("from", home)
		var eased := 1.0 - pow(1.0 - t, 3.0)
		var turned := from.basis.get_rotation_quaternion().slerp(home.basis.get_rotation_quaternion(), eased)
		flier.global_transform = Transform3D(Basis(turned), from.origin.lerp(home.origin, eased))
	var flight := flier.create_tween()
	# The wind-up.
	flight.tween_property(flier, "global_position", wind_at, SUN_WIND).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# The throw: her magic lets go.
	flight.tween_callback(func() -> void:
		_unglow_aura(fly)
		if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", false)
		var fx: Script = load(FX)
		if fx != null: fx.call("sparks", game, flier.global_position, 0.3, colour)
		SKY_SFX.play("whoosh", flier, 2.0, 20.0)
		SKY_SFX.play("climb", flier, -2.0, 80.0))
	flight.tween_method(climb, 0.0, 1.0, SUN_RISE)
	# Into the sun: a twinkle, and it is gone.
	flight.tween_callback(func() -> void:
		flier.visible = false
		_twinkle(game, top)
		SKY_SFX.play_flat("twinkle", game, -3.0))
	flight.tween_interval(SUN_GONE)
	# Back down, burning.
	flight.tween_callback(func() -> void:
		flier.global_transform = Transform3D(home.basis, back_at)
		flier.visible = true
		fly.fire = _fire(flier)
		SKY_SFX.play("meteor", flier, 6.0, 90.0)
		_onlookers("celestia", home.origin, SUN_SEEN, 0.0))
	flight.tween_method(fall, 0.0, 1.0, SUN_FALL)
	# Caught just above the ground, and set down gently.
	flight.tween_callback(func() -> void: _caught(actor, flier, fly, colour))
	flight.tween_method(settle, 0.0, 1.0, SUN_SETTLE)
	flight.tween_callback(func() -> void:
		_unglow_aura(fly)
		if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", false)
		if actor.has_method("set_action_gaze"): actor.call("set_action_gaze", null)
		var warm: Variant = fly.get("warm")
		_end_ritual()
		# The set itself is back, still warm: the glow goes over to it and cools.
		if is_instance_valid(item):
			SKY_SFX.play("tink", item, -2.0, 15.0)
			if is_instance_valid(warm):
				(warm as Node).reparent(item)
				var cool := (warm as OmniLight3D).create_tween()
				cool.tween_property(warm, "light_energy", 0.0, 4.0)
				cool.tween_callback((warm as Node).queue_free))
	print("[watch_party] quest: Celestia throws the set into the sun")

## A copy of the set's look for a stunt (only its meshes: no scripts, lights or sounds), in the
## world where the set stands.
func _stunt_double(visual: Node3D, parent: Node) -> Node3D:
	var copy := visual.duplicate(0) as Node3D
	if copy == null: return null
	_strip(copy)
	copy.name = "WatchPartyStuntDouble"
	parent.add_child(copy)
	copy.top_level = true
	copy.global_transform = visual.global_transform
	copy.visible = true
	return copy

static func _strip(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Light3D or child is AudioStreamPlayer3D or child is GPUParticles3D or child is Label3D or child is CollisionObject3D:
			child.free()
		else: _strip(child)

## A princess's magic is over: the set itself back where it stood, as it was, and the stunt double
## gone. Also the safety net when something cut it short (RITUAL_LIMIT).
func _end_ritual() -> void:
	var ritual: Variant = _run.get("ritual")
	if ritual is Dictionary:
		var item: Variant = ((ritual as Dictionary).item as WeakRef).get_ref()
		if is_instance_valid(item):
			(item as RigidBody3D).global_transform = (ritual as Dictionary).start
			(item as RigidBody3D).collision_layer = int((ritual as Dictionary).layer)
			(item as RigidBody3D).freeze = bool((ritual as Dictionary).freeze)
			(item as Node3D).visible = true
		var flier: Variant = ((ritual as Dictionary).flier as WeakRef).get_ref() if (ritual as Dictionary).get("flier") is WeakRef else null
		if is_instance_valid(flier): (flier as Node).queue_free()
		for extra: Variant in (ritual as Dictionary).get("extras", []):
			if is_instance_valid(extra): (extra as Node).queue_free()
	_run.erase("ritual")
	if not _run.is_empty(): _run.sun_done = true

## Her magic's hold on the set let go.
func _unglow_aura(fly: Dictionary) -> void:
	var aura: Variant = fly.get("aura")
	if aura is Array: MAGIC.unglow_object(aura)
	fly.erase("aura")

## Caught: a flash of her magic and a thump, the fire out in a puff of steam with a hiss, and her
## hold glowing round it as she brings it down.
func _caught(actor: Node3D, item: Node3D, fly: Dictionary, colour: Color) -> void:
	if not is_instance_valid(item): return
	fly.from = item.global_transform
	for part: Variant in fly.get("fire", []):
		if not is_instance_valid(part): continue
		if part is GPUParticles3D:
			(part as GPUParticles3D).emitting = false
			(part as Node).get_tree().create_timer(2.0).timeout.connect((part as Node).queue_free)
		else: (part as Node).queue_free()
	var fx: Script = load(FX)
	if fx != null: fx.call("puff", item.get_parent(), item.global_position + Vector3.UP * 0.5, Color(0.92, 0.92, 0.95), 1.4)
	SKY_SFX.play("catch", item, 3.0, 25.0)
	SKY_SFX.play("hiss", item, 0.0, 20.0)
	if is_instance_valid(actor):
		if actor.has_method("set_action_gaze"): actor.call("set_action_gaze", item)
		if actor.has_method("cast_magic"): actor.call("cast_magic", SUN_SETTLE + 0.5)
		var magic: Variant = actor.get("magic")
		if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", true)
		if magic is Node and (magic as Node).has_method("glow_object"): fly.aura = (magic as Node).call("glow_object", item, 1.0)
	var flash := OmniLight3D.new()
	flash.light_color = colour
	flash.omni_range = 14.0
	flash.light_energy = 6.0
	flash.shadow_enabled = false
	item.add_child(flash)
	var fade := flash.create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.6)
	fade.tween_callback(flash.queue_free)
	# Still warm from the sun: a glow that cools once it is down.
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.omni_range = 4.0
	warm.light_energy = 2.0
	warm.shadow_enabled = false
	item.add_child(warm)
	warm.position = Vector3.UP * 0.6
	fly.warm = warm

## Fire and smoke streaming up behind the falling set, and the light of its flames.
func _fire(item: Node3D) -> Array:
	var fx: Script = load(FX)
	var parts: Array = []
	if fx == null: return parts
	var texture: Texture2D = fx.call("_dot_texture")
	var flames_process := ParticleProcessMaterial.new()
	flames_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	flames_process.emission_sphere_radius = 0.45
	flames_process.direction = Vector3.UP
	flames_process.spread = 18.0
	flames_process.initial_velocity_min = 3.0
	flames_process.initial_velocity_max = 7.0
	flames_process.gravity = Vector3.ZERO
	flames_process.scale_min = 0.8
	flames_process.scale_max = 1.7
	flames_process.color_ramp = fx.call("_ramp", Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.25, 0.05, 0.0))
	parts.append(_trail(item, flames_process, 180, 0.55, 0.75, fx.call("_material", true, texture)))
	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_process.emission_sphere_radius = 0.5
	smoke_process.direction = Vector3.UP
	smoke_process.spread = 25.0
	smoke_process.initial_velocity_min = 1.0
	smoke_process.initial_velocity_max = 2.5
	smoke_process.gravity = Vector3.ZERO
	smoke_process.scale_min = 1.0
	smoke_process.scale_max = 2.2
	smoke_process.color_ramp = fx.call("_ramp", Color(0.3, 0.26, 0.22, 0.75), Color(0.25, 0.25, 0.25, 0.0))
	parts.append(_trail(item, smoke_process, 70, 1.8, 1.4, fx.call("_material", false, texture)))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 16.0
	light.light_energy = 4.0
	light.shadow_enabled = false
	item.add_child(light)
	light.position = Vector3.UP * 0.5
	parts.append(light)
	return parts

func _trail(item: Node3D, process: ParticleProcessMaterial, amount: int, lifetime: float, size: float, material: Material) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.process_material = process
	particles.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	particles.draw_pass_1 = quad
	item.add_child(particles)
	particles.position = Vector3.UP * 0.5
	particles.emitting = true
	return particles

## The twinkle where the set vanished: a bright four-pointed star that flares and is gone, the same
## size on screen however far up it is.
func _twinkle(parent: Node, at: Vector3) -> void:
	var star := Sprite3D.new()
	star.texture = _star_texture()
	star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	star.fixed_size = true
	star.pixel_size = 0.0011
	star.shaded = false
	star.no_depth_test = true
	star.render_priority = 20
	star.modulate = Color(1.0, 0.97, 0.85, 1.0)
	parent.add_child(star)
	star.global_position = at
	star.scale = Vector3.ONE * 0.1
	var flare := star.create_tween()
	flare.tween_property(star, "scale", Vector3.ONE * 1.6, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flare.parallel().tween_property(star, "rotation:z", 0.6, 0.9)
	flare.tween_property(star, "scale", Vector3.ONE * 0.05, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flare.tween_callback(star.queue_free)

static var _star: ImageTexture
static func _star_texture() -> ImageTexture:
	if _star != null: return _star
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x - size * 0.5) / (size * 0.5)
			var v := (y - size * 0.5) / (size * 0.5)
			var rays := pow(maxf(0.0, 1.0 - absf(u)), 5.0) * exp(-absf(v) * 45.0) + pow(maxf(0.0, 1.0 - absf(v)), 5.0) * exp(-absf(u) * 45.0)
			var core := exp(-(u * u + v * v) * 28.0)
			image.set_pixel(x, y, Color(1.0, 0.97, 0.88, clampf(rays + core, 0.0, 1.0)))
	_star = ImageTexture.create_from_image(image)
	return _star

## Ponies near a princess's magic (not her) see it: up to two say something about it, in their own
## words, starting `delay` seconds from now.
func _onlookers(helper: String, at: Vector3, purpose: String, delay: float) -> void:
	var director := _director()
	var characters: Variant = director.get("characters") if director != null else null
	if not characters is Dictionary: return
	var said := 0
	for pony: Variant in (characters as Dictionary).keys():
		if str(pony) == helper or said >= 2: continue
		var node: Variant = (characters as Dictionary)[pony].get("node")
		if not is_instance_valid(node) or not node is Node3D or bool((node as Node).get("sleeping")): continue
		if _flat((node as Node3D).global_position, at) > SEEN_SKY: continue
		_say(purpose, node as Node3D, str(pony), delay + said * 2.5)
		said += 1

## Luna's way (dev 2026-11-07): everything around grows dim but a small circle round the set, a
## pillar of silver moonlight comes down onto it, and the set rises into it and turns slowly all the
## way round to a heavenly tune, then settles where it stood. Out of reach meanwhile (no collision),
## put back exactly where it was; sun_done tells _casting it is over.
func _moon(actor: Node3D, tv: Node3D) -> void:
	var body: Variant = tv.get("body")
	if not body is RigidBody3D or not (body as RigidBody3D).is_inside_tree():
		_run.sun_done = true
		return
	var item := body as RigidBody3D
	var start := item.global_transform
	var was_frozen := item.freeze
	var layer := item.collision_layer
	_run.ritual = {"item": weakref(item), "layer": layer, "freeze": was_frozen, "start": start}
	item.freeze = true
	item.collision_layer = 0
	tv.call("prepare_wake", "night")
	_onlookers("luna", start.origin, MOON_SEEN, 1.5)
	var total := MOON_DIM + MOON_TURN + MOON_DIM
	if actor.has_method("cast_magic"): actor.call("cast_magic", total)
	var magic: Variant = actor.get("magic")
	if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", true)
	var game: Node = Mods.game if is_instance_valid(Mods.game) else tv
	var dim := _dimmer(start.origin)
	var beam := _beam(game, start.origin)
	var glow := OmniLight3D.new()
	glow.light_color = MOON_LIGHT
	glow.omni_range = DIM_INNER + 1.0
	glow.light_energy = 0.0
	glow.shadow_enabled = false
	game.add_child(glow)
	glow.global_position = start.origin + Vector3.UP * 1.4
	var down := SpotLight3D.new()
	down.light_color = MOON_LIGHT
	down.spot_range = 24.0
	down.spot_angle = 10.0
	down.light_energy = 0.0
	down.shadow_enabled = false
	game.add_child(down)
	down.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), start.origin + Vector3.UP * 18.0)
	HEAVENLY.play(game)
	# The dimming and the lights go too if the safety net ends it (_end_ritual).
	(_run.ritual as Dictionary).extras = [dim, beam, glow, down]
	var spin := func(t: float) -> void:
		if not is_instance_valid(item): return
		var lift := MOON_RISE * (smoothstep(0.0, 0.22, t) - smoothstep(0.8, 1.0, t))
		var turn := TAU * smoothstep(0.1, 0.85, t)
		item.global_transform = Transform3D(start.basis.rotated(Vector3.UP, turn), start.origin + Vector3.UP * lift)
	# In parallel within each step; chain() starts the next step after the last one ends.
	var ritual := item.create_tween().set_parallel(true)
	ritual.tween_property(glow, "light_energy", 1.6, MOON_DIM)
	ritual.tween_property(down, "light_energy", 5.0, MOON_DIM)
	if dim != null: ritual.tween_property(dim.material_override, "shader_parameter/amount", 1.0, MOON_DIM)
	if beam != null: ritual.tween_property(beam.material_override, "shader_parameter/amount", 1.0, MOON_DIM)
	ritual.chain().tween_method(spin, 0.0, 1.0, MOON_TURN)
	ritual.chain().tween_property(glow, "light_energy", 0.0, MOON_DIM)
	ritual.tween_property(down, "light_energy", 0.0, MOON_DIM)
	if dim != null: ritual.tween_property(dim.material_override, "shader_parameter/amount", 0.0, MOON_DIM)
	if beam != null: ritual.tween_property(beam.material_override, "shader_parameter/amount", 0.0, MOON_DIM)
	ritual.chain().tween_callback(func() -> void:
		if is_instance_valid(item):
			item.global_transform = start
			item.collision_layer = layer
			item.freeze = was_frozen
		for node: Variant in [dim, beam, glow, down]:
			if is_instance_valid(node): (node as Node).queue_free()
		_run.erase("ritual")
		if not _run.is_empty(): _run.sun_done = true)
	print("[watch_party] quest: Luna calls down the moonlight")

## The world dimmed but a circle round `centre`: a quad over the whole view (on the camera, so the
## headset sees it too) that darkens each pixel by how far what it shows lies from `centre`.
func _dimmer(centre: Vector3) -> MeshInstance3D:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null: return null
	var shader := Shader.new()
	shader.code = DIM_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("centre", centre)
	material.set_shader_parameter("inner", DIM_INNER)
	material.set_shader_parameter("outer", DIM_OUTER)
	material.set_shader_parameter("depth", DIM_DEPTH)
	material.set_shader_parameter("amount", 0.0)
	var quad := MeshInstance3D.new()
	quad.name = "WatchPartyMoonDim"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.material_override = material
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(quad)
	quad.position = Vector3(0, 0, -0.5)
	return quad

## The pillar of moonlight, from high above down onto `at`.
func _beam(parent: Node, at: Vector3) -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = BEAM_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("amount", 0.0)
	material.set_shader_parameter("colour", MOON_LIGHT)
	material.render_priority = 10
	var pillar := MeshInstance3D.new()
	pillar.name = "WatchPartyMoonbeam"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.1
	mesh.bottom_radius = 0.8
	mesh.height = 60.0
	mesh.radial_segments = 24
	mesh.cap_top = false
	mesh.cap_bottom = false
	pillar.mesh = mesh
	pillar.material_override = material
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pillar)
	pillar.global_position = at + Vector3.UP * 30.0
	return pillar

const DIM_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 centre;
uniform float inner = 3.0;
uniform float outer = 9.0;
uniform float depth = 0.8;
uniform float amount = 0.0;
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
	float z = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	float far = 1.0;
	if (z > 0.000001) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
		vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
		far = smoothstep(inner, outer, distance(world, centre));
	}
	ALBEDO = vec3(0.0, 0.0, 0.015);
	ALPHA = amount * depth * far;
}
"""

const BEAM_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled;
uniform float amount = 0.0;
uniform vec3 colour : source_color = vec3(0.72, 0.78, 1.0);
varying float height;
void vertex() {
	height = VERTEX.y;
}
void fragment() {
	float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade = smoothstep(30.0, 10.0, height) * smoothstep(-30.0, -29.0, height);
	ALBEDO = colour;
	ALPHA = amount * 0.38 * rim * fade;
}
"""

## A princess's spell lights the place: Celestia's a burst of warm gold, Luna's a soft silver glow.
func _cast_light(tv: Node3D, at: Vector3, colour: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = colour
	light.omni_range = reach
	light.light_energy = 0.0
	light.shadow_enabled = false
	tv.add_child(light)
	light.position = at + Vector3(0, 0, 0.4)
	var glow := light.create_tween()
	glow.tween_property(light, "light_energy", energy, CAST_SECONDS * 0.4)
	glow.tween_property(light, "light_energy", 0.0, CAST_SECONDS * 0.6)
	glow.tween_callback(light.queue_free)

## After the spell: she asks him to try again (prompt) and waits for him to switch it on
## (switch_on); once it is on, what happened is her next event. He may be quicker than her line.
## Too long, and she switches it on herself.
func _switching(actor: Node3D, encounters: Node, key: String) -> void:
	var tv := _tv()
	var since := float(_run.since)
	if str(_run.phase) == "prompt" and (bool(encounters.call("delivered", key, "try_again")) or since > LINE_WAIT):
		encounters.call("mark_delivered", key, "try_again")
		_phase("switch_on")
		return
	if tv == null: return   # picked up: it comes back when set down again (tv_set.gd _process)
	var blown := bool(tv.get("blown"))
	if not blown and bool(tv.get("active")) and not bool(tv.call("armed")) and not bool(tv.call("waking")):
		# Put away and set down again in between: dark and waiting once more.
		tv.call("arm")
	var woke := bool(tv.call("waking")) or blown
	# Not while somepony else has a go at switching it on, until his go-ahead or they give up.
	var by_her := not woke and str(_run.phase) == "switch_on" and (since > SWITCH_WAIT or bool(_run.get("go", false)) or bool(_run.get("gave_up", false))) and not _holding() and bool(tv.get("active"))
	if not woke and not by_her: return
	if by_her:
		if actor.has_method("cast_magic"): actor.call("cast_magic", 1.0)
		var marker: Variant = _run.get("marker")
		MAGIC.burst(tv, (marker as Node3D).position if is_instance_valid(marker) else Vector3.UP * 0.6, _colour(actor), 0.8, 0.2)
	encounters.call("mark_delivered", key, "try_again")
	encounters.call("mark_delivered", key, "switch_on")
	print("[watch_party] quest: %s switched it on" % (_name(str(_run.helper)) if by_her else "Anon"))
	_switched(tv, encounters, key, "Anon did not switch it on, so you did it yourself with a little flick of magic" if by_her else "Anon switched it on", by_her)

## It is switched on: it wakes, or (Trixie's doomed spell) it blows up. Her next event says which;
## every pony close by saw it.
func _switched(tv: Node3D, encounters: Node, key: String, how: String, by_her: bool) -> void:
	var helper := str(_run.helper)
	var id := str(_run.id)
	if bool(tv.get("doomed")):
		tv.set("doomed", false)
		var blast: Node = hub.get("blast") as Node if is_instance_valid(hub) else null
		var result: Dictionary = blast.call("blast", tv, helper) if blast != null else {}
		var anon := " The blast threw Anon off his feet." if bool(result.get("anon", false)) else " Anon was far enough away to keep his feet."
		var her := " It threw you back a few steps, though you landed on your hooves." if helper in (result.get("ponies", []) as Array) else ""
		encounters.call("event", helper, "blew", BLEW % [how, anon, her])
		_run.blew = true
		_react(helper, result)
	else:
		# Anon's press already woke it (tv_set.gd press): once only (playtest 2026-11-07: a second,
		# frozen "No Signal" stayed in the middle of the screen).
		if not bool(tv.call("waking")): tv.call("power_up")
		if not _sure(helper): tv.call("smoke", SMOKE_AFTER)
		var woke := ", and it woke: " + (NIGHT_WAKE if helper == "luna" else SUN_WAKE if helper == "celestia" else str(WAKE[id])) + (STILL_SMOKING if not _sure(helper) else "")
		encounters.call("event", helper, "woke", how + woke)
		_witnesses(tv, id, helper)
	_phase("explain")

## Every pony close to the set (awake) saw it wake (finds.gd witness).
func _witnesses(tv: Node3D, id: String, by: String) -> void:
	var characters: Variant = _director().get("characters") if _director() != null else null
	if not characters is Dictionary: return
	for pony: Variant in (characters as Dictionary).keys():
		var node: Variant = (characters as Dictionary)[pony].get("node")
		if not is_instance_valid(node) or not node is Node3D or bool((node as Node).get("sleeping")): continue
		if _flat((node as Node3D).global_position, tv.global_position) <= SEEN_REACH: FINDS.witness(str(pony), id, by)

## Up to two other ponies close by say something about the bang, in their own words.
func _react(by: String, result: Dictionary) -> void:
	var said := 0
	for pony: Variant in result.get("seen", []):
		if str(pony) == by or said >= 2: continue
		var actor := _actor(_director(), str(pony))
		if actor == null: continue
		var thrown := " (the blast threw you back a few steps; you landed on your hooves)" if str(pony) in (result.get("ponies", []) as Array) else ""
		_say(NEAR_BLAST % [_name(by), thrown], actor, str(pony), 1.5 + said * 2.5)
		said += 1

## A set Trixie doomed whose quest ended before it was switched on (Anon walked off, say): switched
## on later all the same, it blows up then.
func _orphans() -> void:
	for node: Node in get_tree().get_nodes_in_group("watch_tvs"):
		if not bool(node.get("blown")) or not bool(node.get("doomed")): continue
		node.set("doomed", false)
		var blast: Node = hub.get("blast") as Node if is_instance_valid(hub) else null
		if blast == null: continue
		var result: Dictionary = blast.call("blast", node, TRIXIE)
		_react(TRIXIE, result)

func _unglow() -> void:
	for part: String in ["aura", "remote_aura"]:
		var aura: Variant = _run.get(part)
		if aura is Array: MAGIC.unglow_object(aura)
		_run.erase(part)

## Her navigator back to her own life (the encounter's reservation lets go when it ends).
func _release(actor: Node3D) -> void:
	var nav := _nav(actor) if is_instance_valid(actor) else null
	if nav != null and str(nav.get("command_owner")) == OWNER + str(_run.get("helper", "")):
		nav.set("face_point", Vector3.INF)
		nav.call("stay")
		nav.set("command_owner", "")

func _finish(success: bool, why: String, rest := true) -> void:
	if _run.is_empty(): return
	# Cut short in the middle of a princess's magic: the set back first.
	if _run.has("ritual"): _end_ritual()
	var run := _run
	var actor: Node3D = (run.actor as WeakRef).get_ref() as Node3D
	_unglow()
	if is_instance_valid(actor): _release(actor)
	_run = {}
	if is_instance_valid(actor):
		if actor.has_method("set_action_gaze"): actor.call("set_action_gaze", null)
		var magic: Variant = actor.get("magic")
		if magic is Node and (magic as Node).has_method("hold"): (magic as Node).call("hold", false)
	var marker: Variant = run.get("marker")
	if is_instance_valid(marker): (marker as Node).queue_free()
	var visits: Variant = (run.visits as WeakRef).get_ref() if run.get("visits") is WeakRef else null
	if is_instance_valid(visits): (visits as Node).set_process(true)
	var encounters: Node = Mods.game.get("encounters") as Node if is_instance_valid(Mods.game) else null
	if encounters != null and bool(encounters.call("active", str(run.key))): encounters.call("cancel", str(run.key), why)
	if not success and rest and not bool(run.get("blew", false)): _cooldowns[str(run.helper)] = COOLDOWN
	print("[watch_party] quest: %s (%s)" % ["the %s works now" % FINDS.kind_name(str(run.id)) if success else "stopped", why])
	if success and is_instance_valid(hub) and hub.has_method("after_power_up"): hub.call("after_power_up")

# --- the remote's spark ------------------------------------------------------------------------

## The remote in one of Anon's hands, or null.
func _held_remote(inventory: Node) -> Node3D:
	var held: Variant = inventory.get("held") if is_instance_valid(inventory) else null
	if not held is Dictionary: return null
	for item: Variant in (held as Dictionary).values():
		if is_instance_valid(item) and str((item as Node).get_meta("item_id", "")) == FINDS.REMOTE: return item as Node3D
	return null

## Once a set works: Anon holding the remote up near Twilight or a princess (nothing else of hers
## under way) gets it a spark of its own too. Once per world (finds.gd remote_powered).
func _try_spark() -> void:
	var data := FINDS.state()
	if data.is_empty() or bool(data.get("remote_powered", false)) or FINDS.powered_list().is_empty() or FINDS.quest_skipped(): return
	var director := _director()
	var encounters: Node = Mods.game.get("encounters") as Node if is_instance_valid(Mods.game) else null
	if encounters == null: return
	var inventory := _inventory()
	var remote := _held_remote(inventory)
	var eye := _eye(inventory)
	if remote == null or not eye.is_finite(): return
	for helper: String in ORDER:
		if not _sure(helper): continue
		var actor := _actor(director, helper)
		if actor == null or bool(actor.get("sleeping")) or bool(encounters.call("claimed", helper)) or _flat(eye, actor.global_position) > REMOTE_RANGE: continue
		_spark = {"actor": weakref(actor), "helper": helper, "remote": weakref(remote), "t": 0.0}
		if actor.has_method("set_action_gaze"): actor.call("set_action_gaze", remote)
		if actor.has_method("cast_magic"): actor.call("cast_magic", REMOTE_CAST + 0.5)
		var magic: Variant = actor.get("magic")
		if magic is Node and (magic as Node).has_method("glow_object"): _spark.aura = (magic as Node).call("glow_object", remote, 1.0)
		MAGIC.burst(remote, Vector3.ZERO, _colour(actor), REMOTE_CAST, 0.12)
		print("[watch_party] quest: %s gives the remote a spark too" % _name(helper))
		return

func _sparking(delta: float) -> void:
	_spark.t = float(_spark.t) + delta
	if float(_spark.t) < REMOTE_CAST: return
	var actor: Node3D = (_spark.actor as WeakRef).get_ref() as Node3D
	var helper := str(_spark.helper)
	_end_spark()
	var data := FINDS.state()
	if data.is_empty(): return
	data.remote_powered = true
	FINDS.changed()
	if is_instance_valid(actor): _say(REMOTE_SPARK, actor, helper)

func _end_spark() -> void:
	if _spark.is_empty(): return
	var aura: Variant = _spark.get("aura")
	if aura is Array: MAGIC.unglow_object(aura)
	var actor: Variant = (_spark.actor as WeakRef).get_ref() if _spark.get("actor") is WeakRef else null
	if is_instance_valid(actor) and (actor as Node).has_method("set_action_gaze"): (actor as Node).call("set_action_gaze", null)
	_spark = {}

## One line in her own words (the director's intent queue), as watch_invite.gd _say; after `delay`
## seconds.
func _say(purpose: String, actor: Node3D, speaker: String, delay := 0.0) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_say.bind(purpose, actor, speaker))
		return
	var director := _director()
	if director == null or not director.has_method("queue_generated_intent") or not is_instance_valid(actor): return
	var started := Time.get_ticks_msec()
	director.call("queue_generated_intent", speaker, purpose, "watch_party:quest:%d" % started,
		func() -> bool: return is_instance_valid(actor) and actor.is_inside_tree() and Time.get_ticks_msec() - started < 60000, Callable(), true)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
