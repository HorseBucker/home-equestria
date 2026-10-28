extends RefCounted
## Trixie's stage patter: at each moment of the show the director generates one short line from
## a purpose (never a script) through its normal intent queue, voice and speech bubble. One AI
## round trip per moment, about 10-12 per show (opening speech, each trick, the pause between
## tricks, finale, bow); shows are rare (3 % of days, 7-day cooldown). Skipped quietly while the
## player is out of earshot (the show goes on without words then), or without AI. Her lines are
## firm (dev 2026-10-28): Anon cannot cut one off, his words wait for its end, and a newer line
## replaces one she never got to say.

const SITUATION := "[Observed situation, not player speech] You are performing your magic show on the schoolhouse stage in front of a crowd of ponies%s. "
const PURPOSE := {
	"speech_open": "The spotlights find you alone on your stage before the show. Open your speech to the crowd: introduce yourself as The Great and Powerful Trixie with full showmare flair and welcome Ponyville to your show. Two sentences.",
	"speech_promise": "Go on with your opening speech: promise the crowd wonders they have never seen, and dare any doubters out there to keep watching. End by announcing the first trick: %s. Two or three sentences.",
	"interlude": "The crowd is applauding your last trick (%s). Soak it up and take a bow, then build anticipation for what comes next: %s. Two short sentences.",
	"cards": "You levitate a whole deck of cards into rings, stars and shapes above the stage. Boast about it to the crowd. One short sentence.",
	"pick_card": "You float one card from your deck to %s in the audience to look at, to make it reappear from your hat. Address them. One short sentence.",
	"doves": "You make doves burst out of your magician's hat. Present the trick grandly. One short sentence.",
	"rings": "You levitate your linking rings around yourself and link them in mid-air. One short boastful sentence.",
	"vanish": "You step into your magic box to vanish. Build suspense. One short sentence.",
	"vanish_reveal": "You have just reappeared behind the audience after vanishing from the box. Gloat. One short sentence.",
	"cannon_ask": "You have wheeled out your cannon and ask Anon, who is watching, to be fired out of it as your human cannonball: he only has to walk up to the cannon. One or two short sentences.",
	"cannon_declined": "Anon did not come up to be your human cannonball. Shrug it off theatrically. One short sentence.",
	"cannon_fire": "Anon climbed into your cannon. Count down and light the fuse. One short sentence.",
	"cannon_land": "Anon just flew out of your cannon over the crowd and landed in a hay pile. One short sentence.",
	"finale": "Your grand finale is starting. Proclaim it. One short sentence.",
	"mishap": "Something went wrong: %s. React as Trixie: embarrassed but recovering your pride. One short sentence.",
	"closing": "The show is over. Take your bow verbally and thank your adoring audience in your own boastful way. One short sentence.",
}

var runtime: Node
var session: Dictionary
var _count := 0

func _init(owner_node: Node) -> void:
	runtime = owner_node
	session = runtime.show

var _last_key := ""

## Queues her line for this moment; `finished` runs once it was spoken to the end. False when no
## line is coming (no AI, Anon out of earshot).
func say(key: String, detail := "", finished := Callable()) -> bool:
	var director: Node = runtime.game.get("director") if runtime.game != null else null
	if director == null or not director.has_method("queue_generated_intent") or not PURPOSE.has(key): return false
	if not runtime._near_stage(runtime.EARSHOT): return false
	# A line she never got to say is stale by now (Anon talked over the show): drop it, unless
	# she is saying it right now.
	if _last_key != "" and str(director.get("_authored_active")) != _last_key and director.has_method("cancel_authored_line"):
		director.cancel_authored_line(_last_key)
	var crowd := ""
	if runtime.audience != null:
		var n: int = runtime.audience.watching_ids().size()
		crowd = " (%d watching)" % n if n > 0 else " (hardly anypony came)"
	var purpose: String = PURPOSE[key]
	var parts := detail.split("|")
	var count := purpose.count("%s")
	if count == 1: purpose = purpose % (detail if not detail.is_empty() else "somepony")
	elif count == 2: purpose = purpose % [parts[0], parts[1] if parts.size() > 1 else "the next trick"]
	_count += 1
	var day := int(runtime.show.get("day", 0))
	var show_key := "trixie_show:%d:%s:%d" % [day, key, _count]
	var valid := func() -> bool: return is_instance_valid(runtime) and runtime.owns_show(session) and runtime.trixie() != null
	if not director.queue_generated_intent(runtime.TRIXIE, SITUATION % crowd + purpose, show_key, valid, finished, false, true): return false
	_last_key = show_key
	return true
