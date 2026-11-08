extends Node
## Ponies watching along (part 2). A pony who accepted [watch_tv] (watch_invite.gd) and settled in
## front of a set is a watcher here until she gets up.
## - Comments: one shared timer at the player's pace (PACES, the TV menu; a change applies at once).
##   When it fires, the watcher who spoke least recently gets what was said in the video since her
##   last remark (subtitles, at most MAX_LINES, no older than the pace's memory) as a "watch"
##   reaction (ext/conversation_director.gd): a short remark or [silence]. With nothing
##   new since her last remark she skips, unless it has been quiet longer than the pace's "anyway".
##   Never while the player speaks or any pony is mid-turn. The timer runs on game time (_now):
##   it stands still while the game is paused (the pause menu pauses the tree). When the timer fires she waits up to
##   BREAK_WAIT for a scene break (a cut in the picture after a quiet spell: a natural moment to
##   react to the scene that ended), then up to GAP_WAIT more for any pause in the dialogue, then
##   speaks anyway. The player speaking starts the wait over (the director itself drops a remark
##   still being thought).
## - Pictures (vision_pool.gd, opt-in): every pace "picture"th remark, and any remark with no new
##   dialogue (an action stretch), first has a still described in words; at a scene break it is
##   the last frame of the scene that ended, since that is what her lines are about. Films the
##   ponies cannot read (title only) get a picture twice as often.
## - What she has seen: each watcher keeps the stretches of video that played in front of her
##   (spans). Remarks and notes only ever carry lines from those, so skipping ahead leaves out
##   what she never saw, and a pony who sits down late knows nothing from before. Switching to
##   another video, or jumping a good way within one, is told to her the next time she speaks.
## - Notes: the player's words to a watcher carry what is on and the last lines (note_for); a
##   group exchange gets one note for all (group_note) saying who has seen what.
## - Nearby: every pony within TV_NEAR of a set in the same house is told it is there and what is
##   on (prompt_note, the game's pony_prompt_notes group), watching or not.
## - YouTube: a video there (status "youtube", web_view.gd YT_JS) is watched like a film: its
##   captions are its subtitles, its place in the video is the position, and an ad on is told as one.
## - Ducking: the film drops DUCK_DB while a pony near the set speaks with a real voice (TTS); not
##   for Ponese, which needs no words to be heard.

const CHATTER := preload("res://world/ai/chatter_voice.gd")
## Pace presets (playtest table, 2026-11-01, one step slower; vision columns come with vision):
## seconds between remarks [shortest, longest], a remark anyway after this long with nothing new,
## how far back her dialogue reaches, and every how many remarks a picture is described (all about
## 6-10 minutes apart; playtest 2026-11-02: "every 4 or so on normal").
## Playtest 2026-11-02 (second test): "slightly more often", so every preset is about a fifth quicker.
const PACES := {
	"chatty": {"label": "Chatty", "every": [40.0, 75.0], "anyway": 120.0, "memory": 180.0, "picture": 5},
	# Normal: every 60 to 120 seconds (dev 2026-11-07).
	"normal": {"label": "Normal", "every": [60.0, 120.0], "anyway": 240.0, "memory": 300.0, "picture": 4},
	"relaxed": {"label": "Relaxed", "every": [120.0, 200.0], "anyway": 360.0, "memory": 300.0, "picture": 3},
	"quiet": {"label": "Quiet", "every": [200.0, 300.0], "anyway": 480.0, "memory": 360.0, "picture": 2},
	"silent": {"label": "Silent", "every": [], "anyway": INF, "memory": 180.0, "picture": 0}}
const PACE_ORDER := ["chatty", "normal", "relaxed", "quiet", "silent"]
## Anon asking a pony watching with him to look at the screen (dev 2026-11-07): before she answers,
## a fresh look (pony vision), whatever her pace; it counts as her latest look, so the next one of
## her own waits its turn again. Otherwise, speaking to her gets her a look only when her last one
## is older than her pace's look interval (look_interval). Films, the slideshow and web pages (when
## Settings → Watch Party lets ponies see them) alike. ext/conversation_director.gd handle_text asks
## wants_look() and waits for look_before_reply() (at most LOOK_WAIT seconds).
const LOOK_WORDS := "(?i)(\\blook(ing)?( over)? (at|here)\\b|\\blook!|^\\s*look\\b|\\b(do|did|can|could) you see\\b|\\bsee (this|that|her|him|them|it)\\b|\\bwatch (this|that)\\b|\\bcheck (this|that|it) out\\b|\\bcheck out\\b|\\bwhat('?s| is| was) (that|this|happening|going on|she doing|he doing|on (the )?(screen|tv|television))\\b|\\bwho('?s| is) (that|this)\\b|\\bwhat (am i|are we|is this|are those|is that)\\b|\\bwhat do you (think|make) of (this|that|it)\\b|\\bhow (does|do) (this|that|it|she|he|they) look\\b|\\b(is|isn'?t) (this|that|she|he) (cute|pretty|funny|adorable|cool|weird|gross|scary)\\b|\\brecogni[sz]e\\b|\\bon (the )?(screen|tv|television)\\b|\\bthis (part|scene|bit|one|picture|page)\\b|\\bthat (part|scene|bit|one|picture|page)\\b|\\bguess what\\b|\\bwhat do you see\\b|\\btell me what you see\\b|\\bdescribe\\b)"
const LOOK_WAIT := 8.0
## Never two looks closer together than this, asked for or not.
const LOOK_MIN := 20.0
const MAX_LINES := 25
const GAP_WAIT := 10.0
const BREAK_WAIT := 15.0
## A cut is a scene break when no line was up in the seconds before it; it is a moment to speak
## for this long after.
const BREAK_QUIET := 2.0
const BREAK_FRESH := 1.0
## A picture describes the screen for this many video seconds (later remarks and notes use it).
const PICTURE_FRESH := 45.0
const NOTE_PICTURE := 120.0
const VISION_POOL := preload("res://mods/watch_party/vision_pool.gd")
## Speech hints: names said in the last SPEECH_SECONDS while Anon is within SPEECH_RANGE of a set.
const SPEECH_SECONDS := 300.0
const SPEECH_RANGE := 15.0
const SPEECH_NAMES := 14
## Capitalized words that are no names (lowercase).
const COMMON_WORDS := ["i", "i'm", "i'll", "i've", "i'd", "ok", "okay", "oh", "ah", "uh", "um", "hey", "yes", "yeah", "no", "mr", "mrs", "ms", "dr", "sir", "madam", "ma'am", "miss", "mister", "lord", "lady", "god", "mom", "mum", "dad", "mama", "papa", "the", "a", "an", "and", "but", "what", "why", "how", "who", "where", "when", "please", "thanks", "thank", "sorry", "well", "now", "come", "go", "look", "wait", "stop", "hello", "hi", "goodbye", "bye", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "english", "christ", "jesus"]
## The player's words carry at most this much of the dialogue.
const NOTE_SECONDS := 120.0
const NOTE_LINES := 15
## How much of a web page's own text a pony is given (watch_company _web_summary).
const WEB_TEXT := 700
## For a pony away from the set while Anon has one set up somewhere (prompt_note).
const SLIDE_TITLE := "a picture from Anon's own photo slideshow"
## With the magic quest skipped (settings skip_quest, "Ozone-powered TVs"), why his sets work.
const OZONE_NOTE := " It needs no plug or magic: it runs on the ozone in the air, which Equestria has plenty of."
const OWNED_NOTE := "- Anon has a television set up at his place: a box that shows things from his human world, moving pictures with sound. Watching something on it together is one of the things you two can do, like a walk or a meal; suggest it yourself when it would suit you and the moment, or say yes or no when he asks. When you are both going to watch now, use [watch_tv]: you go along with him and settle in by the set."
## For a pony near a set who is not watching (playtest 2026-11-06: Cheerilee, told "sit down and
## watch", only walked up to Anon three times).
const WATCH_TOGETHER := "If you and Anon are going to sit down and watch it together, use [watch_tv]."
## For a pony watching (playtest 2026-11-06: Anon said he had to go, Derpy went home, Rainbow Dash
## said goodbye and stayed sitting in front of the set).
const WATCH_DONE := "When the watching is over, or Anon says he has to go, get up and go on with your day: use [resume_routine] (or [go_home] if you are heading home)."
## A YouTube video, for a pony (once per remark or note), and an ad on in it.
const TUBE_WORDS := "YouTube is a place on the web of his human world where anyone can put up moving pictures they made, from shows to everyday clips; its words come from the captions that go with it."
const AD_WORDS := "Right now an advertisement is playing instead of the video (a short paid notice for something sold in his world, cut in before or during it): it is not part of the video, so do not take it for the story; if you say anything about it, you know it is an ad."
const DUCK_DB := -10.0
const DUCK_RANGE := 9.0
const DUCK_DOWN_PER_SECOND := 40.0
const DUCK_UP_PER_SECOND := 12.0
const TICK := 0.25
## After the player speaks, the next remark waits this share of a full pace wait.
const AFTER_PLAYER := 0.6
## Position moves within this per tick count as watching on; more is a jump (seek, skip).
const JUMP_SECONDS := 4.0
## A jump this long is told to her; it is news for JUMP_TOLD seconds.
const JUMP_NOTICE := 20.0
const JUMP_TOLD := 150.0
const MAX_SPANS := 40
## After a switch to another video, a remark comes this soon (seconds, at most).
const SWITCH_REMARK := [15.0, 30.0]
const INVITE := preload("res://mods/watch_party/watch_invite.gd")
const CATALOG := preload("res://mods/watch_party/catalog.gd")
## How a set looks before it is woken (magic_quest.gd LOOKS), for a pony in front of one.
const QUEST := preload("res://mods/watch_party/magic_quest.gd")
const DORMANT_NOTE := "- Right here in front of you: a strange object Anon brought out of the Everfree Forest, %s. You have never seen anything like it and do not know what it is or what it is for; nopony in Ponyville does. As it is, it does nothing at all. Anon may have his own word for it."

var hub: Node
## id -> {actor: WeakRef, tv: WeakRef, since, said_at (clock), state, path (the video she is
## watching), seen_from (video seconds when she sat down or it switched), heard_to (video seconds
## of her last remark), spans ([[from, to], ...] video seconds played in front of her), last_pos,
## jump ({kind: switch/ahead/back, from, to, old, at, told} or {})}
var watchers: Dictionary = {}
var _next_at := -1.0
var _last_remark := -1e9
var _waited := 0.0
## This remark's moment has come (no more waiting for a break or gap).
var _going := false
var _at_break := false
## Pictures: "" (none yet this remark), "asked", "done"; the round guards a late answer.
var _picture_state := ""
var _round := 0
var _remarks_since_picture := 0
## When the screen was last described for the ponies (_now()), by her own remark or for Anon.
var _last_look := -INF
## Ponies whose next words follow Anon asking them to look: their note says so.
var _looked_for: Dictionary = {}
var _looking := false
## The latest description: {"text", "at" (video seconds), "path", "break"}.
var last_picture: Dictionary = {}
var vision: Node
var _tick := 0.0
var _duck: Dictionary = {}   # tv instance id -> current dB
var _director: Node
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	vision = VISION_POOL.new(); vision.name = "Vision"
	vision.hub = hub
	add_child(vision)
	add_to_group("pony_prompt_notes")

## Seconds of game running (not paused), for every wait here: the pause menu pauses the tree, so
## _process stops and so does this (the wall clock went on, and a remark due during the pause
## came the moment the game went on).
static var _clock := 0.0

static func _now() -> float:
	return _clock

func pace_key() -> String:
	var key := str(hub.settings.pace) if hub != null and hub.get("settings") != null else "normal"
	return key if PACES.has(key) else "normal"

func pace() -> Dictionary:
	return PACES[pace_key()]

## A new pace, from the TV menu: saved, and the next remark rescheduled from the last one.
func set_pace(key: String) -> void:
	if not PACES.has(key) or hub == null: return
	hub.settings.pace = key
	hub.settings.save()
	print("[watch_party] pace: %s" % key)
	if not watchers.is_empty(): _schedule(maxf(_last_remark, _now() - 5.0))

func _schedule(from: float, share := 1.0) -> void:
	var every: Array = pace().every
	_waited = 0.0
	_going = false
	_at_break = false
	_picture_state = ""
	_round += 1
	if every.is_empty():
		_next_at = -1.0
		return
	_next_at = maxf(_now() + 3.0, from + share * _rng.randf_range(float(every[0]), float(every[1])))

func watching(id: String, actor: Node3D, tv: Node3D) -> void:
	if watchers.has(id):
		var row: Dictionary = watchers[id]
		if (row.tv as WeakRef).get_ref() == tv: return
	var status: Dictionary = tv.call("status")
	var at := float(status.get("position", 0.0))
	watchers[id] = {"actor": weakref(actor), "tv": weakref(tv), "since": _now(), "said_at": _now(), "seen_from": at, "heard_to": at, "state": "",
		"path": str(status.get("path", "")), "spans": [[at, at]], "last_pos": at, "jump": {}}
	print("[watch_party] %s is watching (pace %s)" % [id, pace_key()])
	if _next_at < 0.0: _schedule(_now())

func stop_watching(id: String) -> void:
	watchers.erase(id)
	if watchers.is_empty(): _next_at = -1.0

func is_watching(id: String) -> bool:
	return watchers.has(id)

func _director_node() -> Node:
	if not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("conversation_director")
		if _director != null and _director.has_signal("transcript") and not _director.transcript.is_connected(_player_spoke):
			_director.transcript.connect(_player_spoke)
	return _director

## He spoke: the next remark waits again (a little less than a full wait, AFTER_PLAYER).
func _player_spoke(_text: String) -> void:
	if not watchers.is_empty(): _schedule(_now(), AFTER_PLAYER)

func _process(delta: float) -> void:
	_clock += delta
	_update_duck(delta)
	_tick -= delta
	if _tick > 0.0: return
	_tick = TICK
	var director := _director_node()
	for id: String in watchers.keys():
		var row: Dictionary = watchers[id]
		var actor: Variant = (row.actor as WeakRef).get_ref()
		var tv: Variant = (row.tv as WeakRef).get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(tv) or not bool((tv as Node).get("active")):
			watchers.erase(id)
			continue
		_film_ended(id, row, tv as Node3D, director)
		_follow(id, row, tv as Node3D)
		_hold_visit(id)
	if watchers.is_empty() or director == null or _next_at < 0.0 or _now() < _next_at: return
	_remark(director)

## A visiting princess (world/life/princess_visits.gd) says goodbye after a quiet half minute
## with Anon, and the film is mostly quiet: while she watches, her visit clock stays at its start,
## so she leaves when the watch ends instead (she gets up, the visit carries on as usual).
func _hold_visit(id: String) -> void:
	var game: Variant = Mods.game
	var visits: Node = (game as Node).get_node_or_null("PrincessVisits") if is_instance_valid(game) else null
	var visit: Variant = visits.get("visit") if visits != null else null
	if not visit is Dictionary or str((visit as Dictionary).get("id", "")) != id: return
	if str((visit as Dictionary).get("phase", "")) == "with_player": (visit as Dictionary).time = 0.0

## What plays in front of her: her spans grow while it plays on; a seek or skip starts a new
## one; another video starts her over. Wound back, what follows is new to her again.
func _follow(id: String, row: Dictionary, tv: Node3D) -> void:
	var status: Dictionary = tv.call("status")
	var state := str(status.state)
	if state not in ["playing", "paused"]: return
	var path := str(status.path)
	var position := float(status.position)
	if path != str(row.path):
		if not str(row.path).is_empty():
			row.jump = {"kind": "switch", "old": str(row.get("title", title_of(str(row.path)))), "at": _now(), "told": false}
			print("[watch_party] %s saw the set switch to %s" % [id, path.get_file()])
			if not _going and _next_at >= 0.0: _next_at = minf(_next_at, _now() + _rng.randf_range(float(SWITCH_REMARK[0]), float(SWITCH_REMARK[1])))
		row.path = path
		row.title = _shown_title(status)
		row.spans = [[position, position]]
		row.seen_from = position
		row.heard_to = position
		row.last_pos = position
		return
	var last := float(row.last_pos)
	var spans: Array = row.spans
	if position >= last - 0.5 and position <= last + JUMP_SECONDS:
		if state == "playing" and not spans.is_empty(): (spans[-1] as Array)[1] = maxf(float((spans[-1] as Array)[1]), position)
	else:
		if absf(position - last) >= JUMP_NOTICE:
			row.jump = {"kind": "ahead" if position > last else "back", "from": last, "to": position, "at": _now(), "told": false}
		spans.append([position, position])
		if spans.size() > MAX_SPANS: spans.pop_front()
		if position < float(row.heard_to): row.heard_to = position
	row.last_pos = position

## The lines between two times that she actually saw (said within one of her spans).
func _seen(row: Dictionary, tv: Node3D, from: float, to: float) -> Array:
	var out: Array = []
	for line: Variant in tv.call("heard", from, to):
		var at := float((line as Array)[0])
		for span: Variant in row.spans:
			if at >= float((span as Array)[0]) - 1.0 and at <= float((span as Array)[1]) + 0.5:
				out.append(line)
				break
	return out

## A recent switch or jump in words ("" when there is none to tell).
func _jump_text(row: Dictionary) -> String:
	var jump: Dictionary = row.get("jump", {})
	if jump.is_empty() or _now() - float(jump.at) > JUMP_TOLD: return ""
	match str(jump.kind):
		"switch":
			return " Anon just switched the television to this from %s; you have seen nothing of this one before now." % str(jump.old)
		"ahead":
			return " Anon just skipped ahead about %s (from %s to %s in); you did not see what happened in between." % [_length_words(float(jump.to) - float(jump.from)), _length_words(float(jump.from)), _length_words(float(jump.to))]
		"back":
			return " Anon just went back about %s to see part of it again." % _length_words(float(jump.from) - float(jump.to))
	return ""

static func _length_words(seconds: float) -> String:
	if seconds < 90.0: return "%d seconds" % roundi(seconds)
	if seconds < 5400.0: return "%d minutes" % roundi(seconds / 60.0)
	return "%.1f hours" % (seconds / 3600.0)

## The film just finished: whoever watched reacts once (optional, like any remark).
func _film_ended(id: String, row: Dictionary, tv: Node3D, director: Node) -> void:
	var state := str((tv.call("status") as Dictionary).get("state", "idle"))
	var was := str(row.state)
	row.state = state
	if state != "ended" or was not in ["playing", "paused"] or pace_key() == "silent" or director == null: return
	if str(director.get("state")) != "idle": return
	var title := title_of(str(tv.get("current")))
	director.call("_on_physical_reaction", "watch", id, true,
		"%s just finished on Anon's television; you watched it with him. If you like, say in a few words what you thought of it, in your own way, or only [silence]. Do not retell the story." % title)

## One remark, if the moment allows.
func _remark(director: Node) -> void:
	# Never over the player or another pony's turn.
	if str(director.get("state")) != "idle": return
	var speech: Variant = director.get("speech")
	if speech is Object and str((speech as Object).get("state")) == "hearing": return
	var id := ""
	var tv: Node3D = null
	var oldest := INF
	for key: String in watchers:
		var entry: Dictionary = watchers[key]
		var set_node := (entry.tv as WeakRef).get_ref() as Node3D
		var state := str((set_node.call("status") as Dictionary).get("state", "idle"))
		# A slideshow only with pony vision on: what she says comes from seeing a picture.
		if state not in ["playing", "paused"] and not (state == "slides" and bool(vision.call("usable"))): continue
		if float(entry.said_at) < oldest:
			oldest = float(entry.said_at)
			id = key
			tv = set_node
	if id.is_empty(): return
	var status: Dictionary = tv.call("status")
	var position := float(status.position)
	# The moment: a scene break (at most BREAK_WAIT), else a pause in the dialogue (GAP_WAIT more).
	if not _going and str(status.state) == "playing":
		var talking := bool(tv.call("talking_now"))
		var at_break := not talking and _scene_break(tv, position)
		if not at_break and _waited < BREAK_WAIT + GAP_WAIT and (talking or _waited < BREAK_WAIT):
			_waited += TICK
			return
		_at_break = at_break
	_going = true
	var row: Dictionary = watchers[id]
	var chosen := pace()
	var slides := _is_slides(status)
	var lines: Array = [] if slides else _seen(row, tv, maxf(float(row.heard_to), position - float(chosen.memory)), position)
	if lines.size() > MAX_LINES: lines = lines.slice(lines.size() - MAX_LINES)
	var jump := _jump_text(row) if not bool((row.jump as Dictionary).get("told", true)) else ""
	if lines.is_empty() and jump.is_empty() and _now() - float(row.said_at) < float(chosen.anyway):
		# Nothing new since her last remark: skip this one.
		_schedule(_now())
		return
	var web := _is_page(status)
	var title_only := not web and not slides and not _reads(tv, status)
	# A picture first, when one is due: described, then this runs again with it.
	# Never a picture of an ad.
	if _picture_state == "" and not bool(status.get("ad", false)) and _picture_due(lines.is_empty(), title_only) and bool(vision.call("usable")):
		var image: Image = tv.call("picture_for_pony", 3.0 if _at_break else 1.5)
		var ticket := _round
		var cut := _at_break
		var path := str(status.path)
		if image != null and vision.call("describe", image, _page_title(status) if web else (SLIDE_TITLE if slides else _shown_title(status)), lines, func(text: String, _error: String) -> void: _described(text, position, path, cut, ticket), web):
			_picture_state = "asked"
			return
	if _picture_state == "asked": return
	# Seconds into a slideshow are not seconds into a film: anything of this run counts.
	var picture := _fresh_picture(str(status.path), position, 0.0 if slides else float(row.seen_from), PICTURE_FRESH) if _picture_state == "done" else ""
	if slides and picture.is_empty():
		# Nothing seen of it to talk about yet: the next picture.
		_picture_state = ""
		_next_at = _now() + 10.0
		_waited = 0.0
		_going = false
		return
	director.call("_on_physical_reaction", "watch", id, true, _summary(tv, status, lines, title_only, picture, jump))
	if str(director.get("state")) == "thinking" and str(director.get("_current")) == id:
		if not jump.is_empty(): (row.jump as Dictionary).told = true
		row.heard_to = position
		row.said_at = _now()
		# The pace and the time since the last remark go in the log (dev 2026-11-07: to check a
		# pace change took).
		var gap := (" %.0f s after the last," % (_now() - _last_remark)) if is_finite(_last_remark) and _last_remark > 0.0 else ""
		_last_remark = _now()
		_remarks_since_picture = 0 if not picture.is_empty() else _remarks_since_picture + 1
		var due := int(pace().get("picture", 0))
		print("[watch_party] %s may remark (%s,%s %d new lines, %s%s%s%s)" % [id, str(pace().label).to_lower(), gap, lines.size(), "title only" if title_only else "subtitles", ", picture" if not picture.is_empty() else "", ", scene break" if _at_break else "",
			(", picture in %d more" % maxi(1, due - _remarks_since_picture)) if due > 0 and picture.is_empty() else ""])
		_schedule(_now())
	else:
		# Out of earshot or the moment passed: try again shortly (a picture already described stays).
		_next_at = _now() + 5.0
		_waited = 0.0
		_going = false

## A cut in the picture just now, after a spell with no line up: a scene ending.
static func _scene_break(tv: Node3D, position: float) -> bool:
	var cut := float(tv.call("last_cut"))
	if cut < 0.0 or position - cut < 0.0 or position - cut > BREAK_FRESH: return false
	return (tv.call("heard", cut - BREAK_QUIET, cut) as Array).is_empty()

func _picture_due(no_lines: bool, title_only: bool) -> bool:
	var every := int(pace().get("picture", 0))
	if every <= 0: return false
	if _now() - _last_look < LOOK_MIN: return false
	if title_only: every = maxi(1, ceili(every / 2.0))
	elif no_lines: return true
	return _remarks_since_picture + 1 >= every

func _described(text: String, at: float, path: String, cut: bool, ticket: int) -> void:
	_last_look = _now()
	if not text.is_empty(): last_picture = {"text": text.left(700), "at": at, "path": path, "break": cut}
	if ticket == _round: _picture_state = "done"

## The latest description if it is of this film, after `seen_from` and within `fresh` seconds.
func _fresh_picture(path: String, position: float, seen_from: float, fresh: float) -> String:
	if last_picture.is_empty() or str(last_picture.path) != path: return ""
	var at := float(last_picture.at)
	if at < seen_from or position - at > fresh or at > position + 5.0: return ""
	return str(last_picture.text)

## The remark request: what is on, how far in, and what was said since her last remark.
func _summary(tv: Node3D, status: Dictionary, lines: Array, title_only: bool, picture := "", jump := "") -> String:
	if _is_page(status): return _web_summary(tv, status, lines, picture, jump)
	if _is_slides(status): return _slides_summary(picture)
	var text := "You are watching %s, something from Anon's human world, on his television with him, %s." % [_shown_title(status), _when(float(status.position), float(status.duration))]
	if bool(status.get("youtube", false)): text += " " + TUBE_WORDS
	text += jump
	if bool(status.get("ad", false)): text += " " + AD_WORDS
	if str(status.state) == "paused": text += " He has paused it for a moment."
	if _at_break: text += " The picture just cut away after a quiet moment, as if a scene ended: a natural point to react to what came before."
	if title_only:
		text += " You can see the picture, but you cannot make out what anyone in it says, so do not invent particular events, names or lines; keep any remark general (the mood, the evening, the two of you)."
	elif lines.is_empty() and jump.is_empty():
		text += " Nobody in it has said anything since you last spoke: a quiet stretch."
	else:
		text += " What was said in it since you last spoke (its subtitles, oldest first):\n" + _quoted(lines)
	if not picture.is_empty():
		text += "\nWhat you see on the screen%s (described in words): %s" % [" as that scene ended" if _at_break else " right now", picture]
	text += "\nYou have never seen it before: react only to what has happened so far, and never guess at, hint at or reveal what comes next, even if you think you know the story. React the way a friend beside him on the couch would: a quick remark of a sentence or two (three at most), a laugh, now and then a question to Anon, or only [silence] when nothing in it moves you to speak. Never read its lines back, sum up the plot or narrate."
	return text

## The remark request on a web page Anon lets her see: the pages he opened since her last remark,
## a little of the page's text, and (now and then) what the page looks like.
func _web_summary(tv: Node3D, status: Dictionary, lines: Array, picture: String, jump: String) -> String:
	var text := "You are sitting with Anon in front of his television, which he is using to look at pages from the web of his human world (something like a vast library of pictures, writing and moving pictures from everywhere there, that he can talk on too). The page on it now: %s." % _page_title(status)
	text += jump
	if not lines.is_empty(): text += " Pages he opened since you last spoke (oldest first):\n" + _quoted(lines)
	var words := str(tv.call("page_text")).left(WEB_TEXT)
	if not words.is_empty(): text += "\nSome of the words on the page now: \"%s\"" % words
	if not picture.is_empty(): text += "\nWhat the page looks like (described in words): " + picture
	text += "\nReact the way a friend beside him would: a quick remark of a sentence or two (three at most), a question about what he is looking at, a laugh, or only [silence] when nothing in it moves you to speak. Do not read the page back or describe it."
	return text

## The remark request on Anon's photo slideshow: the picture on now, seen through pony vision.
func _slides_summary(picture: String) -> String:
	var text := "You are sitting with Anon in front of his television, which is showing a slideshow of his own pictures, one after another."
	if not picture.is_empty(): text += "\nThe picture on it now (described in words): " + picture
	text += "\nReact the way a friend beside him would: a quick remark of a sentence or two (three at most) about the picture, a question about it, a laugh, or only [silence] when nothing in it moves you to speak. Do not describe it back."
	return text

## The photo slideshow (tv_set.gd status mode "slides").
static func _is_slides(status: Dictionary) -> bool:
	return str(status.get("mode", "")) == "slides"

## A YouTube video (web_view.gd YT_JS) the ponies may see, rather than a page.
static func _tube(status: Dictionary) -> bool:
	return bool(status.get("youtube", false))

## A web page other than a YouTube video.
static func _is_page(status: Dictionary) -> bool:
	return str(status.get("mode", "")) == "web" and not _tube(status)

## What is on, in words: a film's title from its file, or a YouTube video's title and channel.
static func _shown_title(status: Dictionary) -> String:
	if not _tube(status): return title_of(str(status.get("path", "")))
	var channel := str(status.get("channel", "")).strip_edges()
	return "\"%s\"%s, a video on YouTube" % [str(status.get("title", "")).strip_edges(), (" from " + channel) if not channel.is_empty() else ""]

## The ponies can follow what is said in it: a film with subtitles or a YouTube video with captions.
static func _reads(tv: Node3D, status: Dictionary) -> bool:
	if _tube(status): return bool(status.get("captions", false))
	return not str(tv.get("pony_track")).is_empty()

## The page on a set's web browser: "title (site)".
static func _page_title(status: Dictionary) -> String:
	var title := str(status.get("title", "")).strip_edges()
	var host := str(status.get("url", "")).get_slice("://", 1).get_slice("/", 0).trim_prefix("www.")
	if title.is_empty(): return "a page on " + host if not host.is_empty() else "a web page"
	return "%s (%s)" % [title, host] if not host.is_empty() else title

## A slideshow on the set: that pictures are showing, and the latest one seen (pony vision).
func _slides_note(status: Dictionary, seen_from: float, id := "") -> String:
	var note := "(You are in front of Anon's television; it is showing a slideshow of his own pictures, one after another."
	var shown := _fresh_picture(str(status.path), float(status.position), seen_from, NOTE_PICTURE)
	note += _look_words(id, shown, " The one on it a moment ago (described in words): ")
	return note + ")"

## Seconds between her looks at her pace: her remarks' average gap times how many remarks a look
## comes with (Quiet: every second remark, about 8 minutes). INF with no looks at this pace.
func look_interval() -> float:
	var row := pace()
	var every: Array = row.get("every", [])
	var times := int(row.get("picture", 0))
	if every.is_empty() or times <= 0: return INF
	return (float(every[0]) + float(every[1])) * 0.5 * times

## A watching pony and her set to look for: one named in his words, else the only one, else the
## one who spoke last. [] when nopony is watching anything a pony may see.
func _look_target(text: String) -> Array:
	var best := ""
	var latest := -INF
	for id: String in watchers:
		var tv := ((watchers[id] as Dictionary).tv as WeakRef).get_ref() as Node3D
		if tv == null: continue
		var status: Dictionary = tv.call("status")
		var shown := str(status.state) in ["playing", "paused", "slides"] or (_is_page(status) and str(status.state) != "private")
		if not shown: continue
		if RegEx.create_from_string("(?i)\\b" + id.get_slice("_", 0) + "\\b").search(text) != null: return [id, tv]
		if float((watchers[id] as Dictionary).said_at) > latest:
			latest = float((watchers[id] as Dictionary).said_at)
			best = id
	if best.is_empty(): return []
	return [best, ((watchers[best] as Dictionary).tv as WeakRef).get_ref()]

## Anon is about to speak to a pony watching with him: a look is due (asked for, or her last one is
## old), pony vision can make it and the screen may be seen.
func wants_look(text: String) -> bool:
	if _looking or watchers.is_empty() or not bool(vision.call("usable")) or bool(vision.call("busy")): return false
	if _look_target(text).is_empty(): return false
	if _now() - _last_look < LOOK_MIN: return false
	if RegEx.create_from_string(LOOK_WORDS).search(text) != null: return true
	return _now() - _last_look >= look_interval()

## The look itself: the screen described now, for the note on his words; waits at most LOOK_WAIT.
func look_before_reply(text: String) -> void:
	var target := _look_target(text)
	if target.is_empty(): return
	var id := str(target[0])
	var tv := target[1] as Node3D
	var status: Dictionary = tv.call("status")
	var image: Image = tv.call("picture_for_pony", 1.5)
	if image == null: return
	var asked := RegEx.create_from_string(LOOK_WORDS).search(text) != null
	var web := _is_page(status)
	var title := _page_title(status) if web else (SLIDE_TITLE if _is_slides(status) else _shown_title(status))
	var position := float(status.position)
	var path := str(status.path)
	var done := [false]
	var described := func(words: String, _error: String) -> void:
		if not words.is_empty(): last_picture = {"text": words.left(700), "at": position, "path": path, "break": false}
		done[0] = true
	if not bool(vision.call("describe", image, title, [], described, web)): return
	_looking = true
	_last_look = _now()
	# Her own next look waits its full turn again.
	_remarks_since_picture = 0
	if asked: _looked_for[id] = true
	print("[watch_party] %s looks at the screen before answering (%s)" % [id, "asked to" if asked else "her last look was a while ago"])
	var waited := 0.0
	while not bool(done[0]) and waited < LOOK_WAIT:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_looking = false

## How the latest look reads in her note: "right now" when Anon just asked her to look.
func _look_words(id: String, picture: String, earlier: String) -> String:
	if picture.is_empty(): return ""
	if _looked_for.has(id):
		_looked_for.erase(id)
		return " Anon asked you to look at the screen: right now it shows (described in words): " + picture
	return earlier + picture

## The note on the player's words to a watcher ("" when she is not watching anything on).
func note_for(id: String) -> String:
	if not watchers.has(id): return ""
	var tv := ((watchers[id] as Dictionary).tv as WeakRef).get_ref() as Node3D
	if tv == null: return ""
	var status: Dictionary = tv.call("status")
	if _is_slides(status): return _slides_note(status, 0.0, id)
	if str(status.state) not in ["playing", "paused"]: return ""
	var position := float(status.position)
	if _is_page(status):
		var page_note := "(Anon is showing you pages from the web of his human world on his television; the page on it now: %s." % _page_title(status)
		var page_words := str(tv.call("page_text")).left(WEB_TEXT / 2)
		if not page_words.is_empty(): page_note += " Some of its words: \"%s\"" % page_words
		var shown := _fresh_picture(str(status.path), position, float((watchers[id] as Dictionary).seen_from), NOTE_PICTURE)
		page_note += _look_words(id, shown, " A little while ago it looked like this (described in words): ")
		return page_note + ")"
	var text := "(You and Anon are watching %s, something from his human world, on his television, %s%s." % [_shown_title(status), _when(position, float(status.duration)), "; he has paused it" if str(status.state) == "paused" else ""]
	if _tube(status): text += " " + TUBE_WORDS
	if bool(status.get("ad", false)): text += " " + AD_WORDS
	if not _reads(tv, status):
		text += " You cannot make out what anyone in it says."
	else:
		# Only what she saw: never from before she sat down, nor what a skip passed over.
		var seen_from := float((watchers[id] as Dictionary).seen_from)
		var lines: Array = _seen(watchers[id], tv, position - NOTE_SECONDS, position)
		if lines.size() > NOTE_LINES: lines = lines.slice(lines.size() - NOTE_LINES)
		if not lines.is_empty(): text += " Lately in it (its subtitles, oldest first):\n" + _quoted(lines) + "\n"
		elif position - seen_from < 30.0: text += " You only just sat down: you have not seen or heard any of it yet, so you know nothing of what happened before."
	var picture := _fresh_picture(str(status.path), position, float((watchers[id] as Dictionary).seen_from), NOTE_PICTURE)
	text += _look_words(id, picture, " A little while ago the screen showed (described in words): ")
	text += _jump_text(watchers[id])
	return text + " You have never seen it before; no guesses about what comes next.)"

static func _quoted(lines: Array) -> String:
	var out := PackedStringArray()
	for line: Variant in lines:
		var words := str((line as Array)[1]).replace("\n", " ").strip_edges()
		if not words.is_empty(): out.append("\"%s\"" % words)
	return "\n".join(out)

static func _when(position: float, length: float) -> String:
	var minutes := int(position / 60.0)
	var at := "just at the start" if minutes < 2 else "about %d minutes in" % minutes
	if length > 0.0:
		var total := roundi(length / 60.0)
		at += " (it runs %s)" % ("about %d minutes" % total if total < 100 else "about %.1f hours" % (length / 3600.0))
	return at

## A file name as a title: "The.Film.2019.2160p.UHD.BluRay.Remux.mkv" -> "The Film (2019)".
static func title_of(path: String) -> String:
	if path.begins_with("web:"): return "his web browser"
	var stem := path.get_file().get_basename().replace(".", " ").replace("_", " ")
	var episode := RegEx.create_from_string("(?i)\\bS(\\d{1,2})\\s*E(\\d{1,3})\\b").search(stem)
	if episode != null:
		var series := _trim(stem.substr(0, episode.get_start()))
		return "%s (season %d, episode %d)" % [series if not series.is_empty() else "a show", int(episode.get_string(1)), int(episode.get_string(2))]
	var year := RegEx.create_from_string("\\b(19\\d\\d|20\\d\\d)\\b").search(stem)
	if year != null and year.get_start() > 0:
		return "%s (%s)" % [_trim(stem.substr(0, year.get_start())), year.get_string(1)]
	var junk := RegEx.create_from_string("(?i)\\b(2160p|1080p|720p|480p|4k|uhd|blu-?ray|bdrip|brrip|web-?dl|webrip|hdtv|remux|x264|x265|h264|h265|hevc|hdr|dv)\\b").search(stem)
	if junk != null and junk.get_start() > 0: stem = stem.substr(0, junk.get_start())
	return _trim(stem)

static func _trim(text: String) -> String:
	return RegEx.create_from_string("[\\s\\-\\[\\(]+$").sub(text.strip_edges(), "").strip_edges()

# --- what ponies are told ---------------------------------------------------------------------

## Her situation line (director_prompts.gd situation_block, group pony_prompt_notes): a set near
## her in the same house and what is on, "" when there is none.
func prompt_note(id: String) -> String:
	var director := _director_node()
	var characters: Variant = director.get("characters") if director != null else null
	if not characters is Dictionary or not (characters as Dictionary).has(id): return ""
	var pony: Variant = (characters[id] as Dictionary).get("node")
	if not is_instance_valid(pony) or not pony is Node3D or not (pony as Node3D).is_inside_tree(): return ""
	var tv := INVITE.near_tv(get_tree(), (pony as Node3D).global_position)
	var asleep := INVITE.dormant_near(get_tree(), (pony as Node3D).global_position)
	if asleep != null and (tv == null or INVITE._flat(asleep.global_position, (pony as Node3D).global_position) < INVITE._flat(tv.global_position, (pony as Node3D).global_position)):
		# One Twilight has not woken yet: only a strange object (playtest 2026-11-06: Trixie was
		# brought in to see one and saw only the bed).
		var kind := str(asleep.call("item_id"))
		return DORMANT_NOTE % str(QUEST.LOOKS.get(kind, QUEST.LOOKS[CATALOG.VINTAGE]))
	if tv == null:
		# A little way off (playtest 2026-11-06: at a party out of doors Cheerilee, beyond
		# TV_NEAR, was told nothing and took it for a music box): she knows it is there.
		var far := INVITE.near_tv(get_tree(), (pony as Node3D).global_position, INVITE.TV_SEEN)
		if far != null:
			var far_state := str((far.call("status") as Dictionary).get("state", "idle"))
			return "- A little way off: Anon's television, a box that shows things from his human world, moving pictures with sound. %s %s" % [
				"It is off right now." if far_state in ["idle", "stopped", "ended", ""] else "It is on, but you are too far away to make out what is on it.", WATCH_TOGETHER]
		# Away from it: that he has one, and that watching together is a thing they can do.
		if INVITE.owned_homes(get_tree()).is_empty(): return ""
		return OWNED_NOTE + _ozone()
	var status: Dictionary = tv.call("status")
	var text := "- Nearby: Anon's television, a box that shows things from his human world, moving pictures with sound." + _ozone()
	var state := str(status.state)
	if _is_page(status) and state in ["playing", "paused"]: state = "web"
	match state:
		"web":
			text += " Anon is looking at pages from his world's web on it. On it now: %s." % _page_title(status)
		"private":
			text += " Anon is using it for something of his own right now (pages from his world's web that you cannot make out from where you are)."
		"slides":
			text += " It is showing pictures, one after another, like a slow picture book."
		"playing", "paused":
			# The title is in plain sight (playtest 2026-11-06: Berry, asked what song it was, said she could not see it).
			text += " It is on. On it now: %s, %s%s." % [_shown_title(status), _when(float(status.position), float(status.duration)), ", paused" if str(status.state) == "paused" else ""]
		"tuning":
			text += " It is just starting something."
		_:
			text += " It is off right now."
	if watchers.has(id): text += " You are watching it with him. " + WATCH_DONE
	else: text += " " + WATCH_TOGETHER
	return text

## One note for a whole group exchange (ext/conversation_director.gd _group_prompt): what is on, the lines
## every watching member saw, and who sat down when, so nopony knows what she never saw.
func group_note(members: Array) -> String:
	var watching: Array[String] = []
	for member: Variant in members:
		if watchers.has(str(member)): watching.append(str(member))
	if watching.is_empty(): return ""
	var tv := ((watchers[watching[0]] as Dictionary).tv as WeakRef).get_ref() as Node3D
	if tv == null: return ""
	var status: Dictionary = tv.call("status")
	if _is_slides(status): return _slides_note(status, 0.0)
	if str(status.state) not in ["playing", "paused"]: return ""
	var position := float(status.position)
	if _is_page(status):
		return "(You are in front of Anon's television; he is showing you pages from the web of his human world, now %s. Each pony knows only the pages she saw herself.)" % _page_title(status)
	var text := "(You are in front of Anon's television: %s, %s%s." % [_shown_title(status), _when(position, float(status.duration)), "; he has paused it" if str(status.state) == "paused" else ""]
	var shared := _seen(watchers[watching[0]], tv, position - NOTE_SECONDS, position)
	for member: String in watching.slice(1):
		shared = shared.filter(func(line: Variant) -> bool: return _seen(watchers[member], tv, float((line as Array)[0]) - 0.1, float((line as Array)[0]) + 0.1).size() > 0)
	if shared.size() > NOTE_LINES: shared = shared.slice(shared.size() - NOTE_LINES)
	if bool(status.get("ad", false)): text += " " + AD_WORDS
	if _reads(tv, status) and not shared.is_empty():
		text += " Lately in it (its subtitles, which all of you watching saw, oldest first):\n" + _quoted(shared) + "\n"
	var director := _director_node()
	for member: String in watching:
		var row: Dictionary = watchers[member]
		var since := float(row.seen_from)
		text += " %s has been watching %s." % [_display_name(director, member), "since the start" if since < 60.0 else "since about %s in" % _length_words(since)]
		text += _jump_text(row)
	for member: Variant in members:
		if str(member) not in watching: text += " %s is not watching it." % _display_name(director, str(member))
	text += " Each pony knows only what she saw herself: nopony may draw on parts she was not there for, even if another pony talked about them before she came. Nopony has seen it before; no guesses about what comes next.)"
	return text

static func _display_name(director: Node, id: String) -> String:
	var characters: Variant = director.get("characters") if director != null else null
	if characters is Dictionary and (characters as Dictionary).has(id):
		var profile: Variant = (characters[id] as Dictionary).get("profile", {})
		if profile is Dictionary and not str((profile as Dictionary).get("name", "")).is_empty(): return str(profile.name)
	return id

# --- speech recognition hints ------------------------------------------------------------------

## Names the recognizer should spell (ext/speech_vocabulary.gd adds them to Whisper's
## prompt): the film's title and the names said in its last few minutes ("Osgiliath", "Éowyn"),
## while Anon is near a set that has something on. Most recent last (Whisper keeps the end).
func speech_words(head: Node3D) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(head) or not head.is_inside_tree(): return out
	var tv: Node3D = null
	var nearest := SPEECH_RANGE
	for node: Node in get_tree().get_nodes_in_group("watch_tvs"):
		var set_node := node as Node3D
		if set_node == null or not bool(set_node.get("active")): continue
		var state := str((set_node.call("status") as Dictionary).get("state", "idle"))
		if state not in ["playing", "paused"]: continue
		var distance := set_node.global_position.distance_to(head.global_position)
		if distance < nearest:
			nearest = distance
			tv = set_node
	if tv == null: return out
	var status: Dictionary = tv.call("status")
	var title := str(status.get("title", "")) if _tube(status) else title_of(str(status.path)).get_slice(" (", 0)
	if not title.is_empty(): out.append(title)
	var position := float(status.position)
	out.append_array(names_in(tv.call("heard", position - SPEECH_SECONDS, position), SPEECH_NAMES))
	return out

## Proper names in subtitle lines, newest kept: capitalized words mid-sentence ("... told Éowyn"),
## joined when they follow each other ("Minas Tirith"); a sentence's first word only when it also
## appears capitalized mid-sentence somewhere. Shouted all-caps words and common words are left out.
static func names_in(lines: Array, most: int) -> Array[String]:
	var words := RegEx.create_from_string("[\\p{L}][\\p{L}\\p{M}'’\\-]*")
	var breaks := RegEx.create_from_string("[.!?…:;\"“”\\-–—]")
	var parsed: Array = []          # per line: [[word, starts_sentence, joined_to_previous], ...]
	var mid := {}
	for line: Variant in lines:
		var text := str((line as Array)[1]).replace("\n", " ")
		var row: Array = []
		var last_end := -1
		for found: RegExMatch in words.search_all(text):
			var word := found.get_string()
			var between := text.substr(last_end, found.get_start() - last_end) if last_end >= 0 else ""
			var starts := last_end < 0 or breaks.search(between) != null
			row.append([word, starts, between == " "])
			last_end = found.get_end()
			if not starts and _capital(word): mid[_bare(word).to_lower()] = true
		parsed.append(row)
	var found_names: Array[String] = []
	var seen := {}
	for r in range(parsed.size() - 1, -1, -1):
		var phrases: Array[String] = []
		var phrase := PackedStringArray()
		for token: Array in parsed[r]:
			var word := str(token[0])
			var keep := _capital(word) and (not bool(token[1]) or mid.has(_bare(word).to_lower())) and _bare(word).to_lower() not in COMMON_WORDS
			if keep and (phrase.is_empty() or bool(token[2])):
				phrase.append(_bare(word))
				if word != _bare(word):
					phrases.append(" ".join(phrase)); phrase = PackedStringArray()
				continue
			if not phrase.is_empty(): phrases.append(" ".join(phrase))
			phrase = PackedStringArray()
			if keep: phrase.append(_bare(word))
		if not phrase.is_empty(): phrases.append(" ".join(phrase))
		for i in range(phrases.size() - 1, -1, -1):
			var candidate := phrases[i]
			if candidate.length() < 3 or seen.has(candidate.to_lower()): continue
			seen[candidate.to_lower()] = true
			found_names.append(candidate)
			if found_names.size() >= most: break
		if found_names.size() >= most: break
	found_names.reverse()
	return found_names

## Starts with a capital and is not shouted (all capitals).
static func _capital(word: String) -> bool:
	var first := word.left(1)
	return first != first.to_lower() and (word.length() < 2 or word != word.to_upper())

## Without a possessive ending.
static func _bare(word: String) -> String:
	for tail: String in ["'s", "’s", "'", "’"]:
		if word.length() > tail.length() + 1 and word.ends_with(tail): return word.left(word.length() - tail.length())
	return word

# --- ducking ----------------------------------------------------------------------------------

func _update_duck(delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group("watch_tvs"):
		var tv := node as Node3D
		if tv == null or not tv.has_method("set_duck"): continue
		var key := tv.get_instance_id()
		var target := DUCK_DB if _voice_near(tv) else 0.0
		var now := float(_duck.get(key, 0.0))
		if is_equal_approx(now, target) and is_equal_approx(target, 0.0): continue
		now = move_toward(now, target, delta * (DUCK_DOWN_PER_SECOND if target < now else DUCK_UP_PER_SECOND))
		_duck[key] = now
		tv.call("set_duck", now)

## A pony near the set is speaking with a real (TTS) voice.
func _voice_near(tv: Node3D) -> bool:
	var director := _director_node()
	if director == null: return false
	var state := str((tv.call("status") as Dictionary).get("state", "idle"))
	if state != "playing": return false
	var characters: Variant = director.get("characters")
	if not characters is Dictionary: return false
	for id: Variant in characters:
		var entry: Dictionary = characters[id]
		var pony: Variant = entry.get("node")
		if not is_instance_valid(pony) or not pony is Node3D or not (pony as Node).has_method("is_speaking"): continue
		if (pony as Node3D).global_position.distance_to(tv.global_position) > DUCK_RANGE: continue
		if bool((pony as Node).call("is_speaking")) and _voiced(director, entry.get("profile", {})): return true
	return false

## Her line is a TTS voice, not Ponese (world/ai/tts_client.gd synthesize_profile, same choice).
static func _voiced(director: Node, profile: Variant) -> bool:
	var tts: Variant = director.get("tts")
	if not is_instance_valid(tts) or not profile is Dictionary: return false
	var settings: Node = (tts as Node).get_tree().root.get_node_or_null("Settings")
	if settings != null and settings.has_method("tts_enabled") and not settings.tts_enabled(): return false
	if not (tts as Node).has_method("has_server") or not (tts as Node).call("has_server"): return false
	var mode := str((tts as Node).get("voice_mode"))
	if CHATTER.is_ponese_mode(mode): return false
	var voice: Dictionary = profile
	var openai_voiced: bool = str((tts as Node).get("provider")) == "openai" and voice.has("openai_voice") and not CHATTER.is_ponese_mode(str(voice.get("voice_mode", mode)))
	return openai_voiced or not CHATTER.use_chatter(voice, mode)

static func _ozone() -> String:
	return OZONE_NOTE if preload("res://mods/watch_party/finds.gd").quest_skipped() else ""
