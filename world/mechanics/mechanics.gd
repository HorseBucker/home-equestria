extends Node
## One owner for the shared mechanics (docs/MECHANICS_ARCHITECTURE_2026_11_01.md, dev 2026-11-01:
## "universal game features that the ai can take advantage of ... a centralized, unified, organized
## mechanics system"). Every mechanic is built from the same pieces: tagged items
## (world/inventory/item_tags.gd), one way bits move (ledger.gd), one facts stream (facts.gd) and,
## in later packages, gifts, asks, stations, jobs, the town calendar and the market. Modules find
## each other through this hub; each one works with null neighbours (no hub, no facts).
const LEGACY := preload("res://world/mechanics/legacy.gd")
const FACTS := preload("res://world/mechanics/facts.gd")
const MARKET := preload("res://world/mechanics/market/market.gd")
const LEDGER := preload("res://world/mechanics/ledger.gd")
const GIFTS := preload("res://world/mechanics/gifts/gifts.gd")
const BELONGINGS := preload("res://world/mechanics/gifts/belongings.gd")
const STATIONS := preload("res://world/mechanics/stations/stations.gd")
const JOBS := preload("res://world/mechanics/jobs/jobs.gd")
const ASKS := preload("res://world/mechanics/asks/asks.gd")
const ASK_RULES := preload("res://world/mechanics/asks/ask_rules.gd")
const CALENDAR := preload("res://world/mechanics/calendar/town_calendar.gd")
const SAA_SITES := preload("res://world/mechanics/stations/saa_sites.gd")
const ITEM_CATALOG := preload("res://world/inventory/item_catalog.gd")
const AI_CACHE_S := 2.0
## Balloon rides ([use: balloon_ride]): the pilots and the ids that mean it (fly_balloon.gd).
const FLY_BALLOON := "res://world/life/day/actions/fly_balloon.gd"
const BALLOON_PILOTS := ["cherry_berry"]
const BALLOON_RIDE_IDS := ["balloon_ride", "balloon"]
## [use: fountain] (world/life/day/actions/fountain_visit.gd, 2026-11-18 play test: Pinkie came to the fountain
## with Anon for a sip of water and only drank when asked again): a pony near the Town Square fountain can go and
## drink from it herself, whatever she was doing (following Anon, standing with him).
const FOUNTAIN_VISIT := "res://world/life/day/actions/fountain_visit.gd"
const FOUNTAIN_IDS := ["fountain", "fountain_drink", "drink"]
## Cherry Berry's answers about the balloon she came to fetch (balloon_fetch.gd asking).
const BALLOON_ANSWER_IDS := ["balloon_take_home", "balloon_leave_it", "balloon_wait"]
const BALLOON_FETCH_ID := "balloon_fetch"
const NOTE_CHARS := 400
const GROUP := "mechanics"
var game: Node
var facts: Node        # facts.gd; WP1
var gifts: Node        # gifts/gifts.gd; WP2
var belongings: Node   # gifts/belongings.gd; WP2
var asks: Node         # asks/asks.gd; WP3
var stations: Node     # stations/stations.gd; WP4
var jobs: Node         # jobs/jobs.gd; WP5
var calendar: Node     # calendar/town_calendar.gd; WP7
var market: Node       # market/market.gd; WP1 (seller lookup), WP8 (economy)
var saa_sites: Node    # stations/saa_sites.gd; WP6 (places Anon's row, the cider press and stand on the farm)
var _ai_cache: Dictionary = {}   # pony id -> {"at": msec, "keys": {context keys}, "caps": [], "lines": []}

func _init() -> void:
	add_to_group(GROUP)
	add_to_group("pony_prompt_notes")

static func of(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group(GROUP) if tree != null else null

## Creates the module children that exist. Called by world/game.gd once world_context exists.
func setup(host: Node) -> void:
	game = host
	if facts == null:
		facts = FACTS.new(); facts.name = "Facts"; add_child(facts)
	facts.bind(context())
	if market == null:
		market = MARKET.new(); market.name = "Market"; add_child(market)
	if belongings == null:
		belongings = BELONGINGS.new(); belongings.name = "Belongings"; add_child(belongings)
	belongings.bind(context())
	if gifts == null:
		gifts = GIFTS.new(); gifts.name = "Gifts"; add_child(gifts)
	gifts.context = context(); gifts.game = game; gifts.belongings = belongings; gifts.facts = facts; gifts.market = market
	# The town calendar (WP7) before stations and jobs, which read its seasons, events and effects.
	if calendar == null:
		calendar = CALENDAR.new(); calendar.name = "Calendar"; add_child(calendar)
	calendar.game = game; calendar.context = context(); calendar.facts = facts; calendar.hub = self
	if stations == null:
		stations = STATIONS.new(); stations.name = "Stations"; add_child(stations)
	stations.game = game; stations.belongings = belongings; stations.bind(context(), facts)
	if jobs == null:
		jobs = JOBS.new(); jobs.name = "Jobs"; add_child(jobs)
	jobs.bind(context(), game); jobs.facts = facts; jobs.calendar = calendar
	if asks == null:
		asks = ASKS.new(); asks.name = "Asks"; add_child(asks)
	asks.context = context(); asks.game = game; asks.facts = facts; asks.gifts = gifts
	asks.connect_facts()
	if saa_sites == null:
		saa_sites = SAA_SITES.new(); saa_sites.name = "SweetAppleAcresSites"; add_child(saa_sites)
	saa_sites.hub = self
	# The pony economy (WP8): restock costs, daily income and trades, [sell]/[buy].
	market.bind(context()); market.game = game; market.facts = facts; market.gifts = gifts
	market.belongings = belongings; market.stations = stations; market.ledger = LEDGER

func context() -> Node:
	return game.get("world_context") as Node if is_instance_valid(game) else null

## Absolute game hours (day * 24 + hours).
func clock_hours() -> float:
	return float(FACTS.clock().at)

func day() -> int:
	return int(FACTS.clock().day)

## AI surface: appends capabilities and validator keys to `result` (coordinator.context()). Each
## capability appears only while the game can really do it; computed lines are cached for 2 s so
## the prompt note and the capability list always agree.
func ai_context(id: String, actor: Node3D, result: Dictionary) -> void:
	var row := _ai_row(id, actor)
	var capabilities: Variant = result.get("capabilities")
	if capabilities is Array:
		for type: String in row.caps:
			if type not in capabilities: (capabilities as Array).append(type)
	for key: String in row.keys: result[key] = row.keys[key]

func _ai_row(id: String, actor: Node3D) -> Dictionary:
	var cached: Variant = _ai_cache.get(id)
	if cached is Dictionary and Time.get_ticks_msec() - int((cached as Dictionary).at) < int(AI_CACHE_S * 1000.0) and (cached as Dictionary).get("actor") == actor:
		return cached
	var row := {"at": Time.get_ticks_msec(), "actor": actor, "caps": [], "keys": {}, "lines": []}
	# [give] (gifts.gd): what she really has, while Anon is beside her with room for it.
	if gifts != null and is_instance_valid(actor):
		var ids: Array[String] = gifts.offerable(id, actor)
		if not ids.is_empty():
			row.caps.append("give"); row.keys["givables"] = ids
			var names: PackedStringArray = []
			for item: String in ids.slice(0, 6): names.append(str(ITEM_CATALOG.definition(item).get("name", item)).to_lower())
			row.lines.append("- You could hand Anon: %s ([give: NAME])." % ", ".join(names))
	# [offer_job] (jobs/jobs.gd): work she hires for that is open now and Anon has not taken today.
	if jobs != null:
		var job_row: Dictionary = jobs.ai_row(id)
		if not job_row.is_empty():
			row.caps.append("offer_job"); row.keys["jobs"] = job_row.jobs; row.keys["job_names"] = job_row.get("job_names", {}); row.lines.append(str(job_row.line))
	# [use] (stations/stations.gd): stations near her she works, free, with their needs and inputs.
	# Only while day_runner.inject_now could take the step (a resident with today's card, not held).
	var day_runner: Node = get_tree().get_first_node_in_group("day_runner") if is_inside_tree() else null
	if stations != null and is_instance_valid(actor) and day_runner != null and day_runner.has_method("can_inject") and bool(day_runner.call("can_inject", id)):
		var station_ids: Array[String] = stations.workable(id, actor.global_position)
		if not station_ids.is_empty():
			row.caps.append("use"); row.keys["stations"] = station_ids
			row.lines.append("- Stations you could work: %s ([use: ID])." % ", ".join(PackedStringArray(station_ids.slice(0, 4))))
	# [use: balloon_ride] (world/life/day/actions/fly_balloon.gd, play test 2026-11-17: "give Cherry
	# the ability to give rides when asked"): the balloon's pilot takes Anon up when he asks. When she
	# cannot (weather, dark, bedtime, the balloon away or in use) she is told why, to say no kindly.
	if is_instance_valid(actor) and is_inside_tree() and bool((load(FOUNTAIN_VISIT) as Script).call("near", get_tree(), actor)):
		if "use" not in row.caps: row.caps.append("use")
		var near_ids: Array = (row.keys.get("stations", []) as Array).duplicate()
		near_ids.append_array(FOUNTAIN_IDS)
		row.keys["stations"] = near_ids
		row.lines.append("- The Town Square fountain is right here: whenever you mean to have a drink from it (thirsty, or you came for a sip of water), use [use: fountain] and you go and drink. Saying you drink is not drinking.")
	# Cherry Berry has asked Anon whether he is still using the balloon she came to take home (Ponyville overhaul,
	# balloon_fetch.gd): her answer to his reply is an action, chosen by her from what he said.
	var fetch: Node = get_tree().root.find_child("BalloonFetch", true, false) if is_inside_tree() else null
	if fetch != null and id == "cherry_berry" and bool(fetch.call("asking")):
		if "use" not in row.caps: row.caps.append("use")
		var answers: Array = (row.keys.get("stations", []) as Array).duplicate()
		answers.append_array(BALLOON_ANSWER_IDS)
		row.keys["stations"] = answers
		row.lines.append("- You came to take the hot-air balloon back to its pad and asked Anon whether he is still using it. When he answers, act on what he means: [use: balloon_take_home] to take it home now (he is done with it, or does not mind), [use: balloon_leave_it] to leave it where it is with him for now (he still needs it), or [use: balloon_wait] to come back for it in a few hours (he wants a little longer). If he never answers, you take it home.")
	# [use: balloon_fetch] (balloon_fetch.gd fetch_now): the balloon is out on the ground, away from its pad; she can go
	# and bring it home when Anon tells her where it is or asks her to.
	var away: Dictionary = fetch.call("fetchable") if fetch != null and id == "cherry_berry" and not bool(fetch.call("asking")) else {}
	if not away.is_empty():
		if "use" not in row.caps: row.caps.append("use")
		var fetch_ids: Array = (row.keys.get("stations", []) as Array).duplicate()
		fetch_ids.append(BALLOON_FETCH_ID)
		row.keys["stations"] = fetch_ids
		row.lines.append("- Your hot-air balloon is not on its pad: it stands on the ground about %d m away from it. When you mean to go and bring it home (Anon tells you where it is, or asks you to), use [use: balloon_fetch] and you go to it and %s. Saying you will fetch it is not fetching it, and a plain go_to only takes you there." % [int(away.metres), "walk it home on its rope" if bool(away.walk) else "fly it home"])
	if is_instance_valid(actor) and id in BALLOON_PILOTS and is_inside_tree():
		var flying: Script = load(FLY_BALLOON)
		var why: String = flying.call("ride_refusal", get_tree(), id)
		if why.is_empty():
			if "use" not in row.caps: row.caps.append("use")
			var listed: Array = (row.keys.get("stations", []) as Array).duplicate()
			listed.append_array(BALLOON_RIDE_IDS)
			row.keys["stations"] = listed
			row.lines.append("- You fly Ponyville's hot-air balloon: if Anon asks for a ride and you agree, use [use: balloon_ride]. You walk to it, he climbs into the basket after you, and you fly him over Ponyville and land again.")
		else:
			row.lines.append("- No balloon ride is possible right now (%s); if Anon asks for one, tell him kindly." % why)
	# [ask] (asks/asks.gd): one open favour at a time; her open one is her line.
	if asks != null:
		var open_line: String = asks.prompt_note(id)
		if not open_line.is_empty(): row.lines.append(open_line)
		elif asks.can_ask(id).is_empty():
			row.caps.append("ask"); row.keys["asks_open"] = true; row.keys["ask_from"] = id
			row.keys["ask_items"] = gifts.givables(id).map(func(entry: Dictionary) -> String: return str(entry.id)) if gifts != null else []
			row.keys["ask_ponies"] = _pony_names()
	# [invite] (calendar, WP7): today's events she may invite Anon to.
	if calendar != null and calendar.has_method("invitable"):
		var events: Variant = calendar.call("invitable", id)
		if events is Array and not (events as Array).is_empty():
			var event_ids: Array[String] = []
			var event_names := {}
			for event: Variant in events:
				event_ids.append(str(event)); event_names[str(event)] = str(calendar.row(str(event)).get("name", event))
			row.caps.append("invite"); row.keys["events"] = event_ids; row.keys["event_names"] = event_names
			row.lines.append(calendar.prompt_line(event_ids))
	# [sell] at her own loaded stall with Anon there, [buy] for what Anon holds beside her (market.gd, WP8).
	if market != null and market.has_method("ai_row") and is_instance_valid(actor):
		var trade: Dictionary = market.ai_row(id, actor)
		for type: Variant in trade.get("caps", []): row.caps.append(str(type))
		var trade_keys: Dictionary = trade.get("keys", {})
		for key: String in trade_keys: row.keys[key] = trade_keys[key]
		for line: Variant in trade.get("lines", []): row.lines.append(str(line))
	_ai_cache[id] = row
	if _ai_cache.size() > 64: _ai_cache.erase(_ai_cache.keys()[0])
	return row

## Forgets the cached capability rows (after a mechanic changed what a pony has).
func invalidate(id := "") -> void:
	if id.is_empty(): _ai_cache.clear()
	else: _ai_cache.erase(id)

## Runs a validated mechanic action. {"status": "completed"|"failed"|"accepted", "reason"}.
func dispatch(id: String, actor: Node3D, action: Dictionary) -> Dictionary:
	var type := str(action.get("type", ""))
	if type == "use" and str(action.get("station_id", "")) in BALLOON_ANSWER_IDS:
		var asker: Node = get_tree().root.find_child("BalloonFetch", true, false)
		if asker == null or not bool(asker.call("asking")): return {"status": "failed", "reason": "Nothing to answer about the balloon now"}
		var choice: String = {"balloon_take_home": "take", "balloon_leave_it": "leave", "balloon_wait": "later"}[str(action.station_id)]
		asker.call("_answered", choice)
		invalidate(id)
		return {"status": "completed", "reason": {"take": "You are taking the balloon home to its pad now", "leave": "You leave the balloon with Anon for now; you will not come for it again until tomorrow",
			"later": "You will come back for the balloon in a few hours"}[choice]}
	if type == "use" and str(action.get("station_id", "")) == BALLOON_FETCH_ID and id == "cherry_berry":
		var fetcher: Node = get_tree().root.find_child("BalloonFetch", true, false)
		var went: Dictionary = fetcher.call("fetch_now", get_tree()) if fetcher != null else {"status": "failed", "reason": "Not possible right now"}
		invalidate(id)
		return went
	if type == "use" and str(action.get("station_id", "")) in FOUNTAIN_IDS:
		var drink: Dictionary = (load(FOUNTAIN_VISIT) as Script).call("drink_now", get_tree(), id)
		invalidate(id)
		return drink
	var result: Dictionary = {"status": "failed", "reason": "No mechanic handles %s yet." % (type if not type.is_empty() else "that")}
	match type:
		"give":
			if gifts != null: result = gifts.give_to_anon(id, actor, str(action.get("item", "")))
		"offer_job":
			if jobs != null: result = jobs.hire(str(action.get("job_id", "")), id)
		"use":
			if str(action.get("station_id", "")) in BALLOON_RIDE_IDS and id in BALLOON_PILOTS:
				result = (load(FLY_BALLOON) as Script).call("request_ride", get_tree(), id)
			elif stations != null: result = stations.request_use(id, str(action.get("station_id", "")))
		"ask":
			if asks != null: result = _dispatch_ask(id, action)
		"invite":
			if asks != null: result = _dispatch_invite(id, action)
		"sell":
			if market != null: result = market.sell_offer(id, str(action.get("item", "")), int(action.get("price", 0)))
		"buy":
			if market != null: result = market.buy_offer(id, str(action.get("item", "")), int(action.get("price", 0)))
	invalidate(id)
	return result

## [ask]: the schema already normalised want/reward (ask_rules.gd); asks.gd checks the caps again.
func _dispatch_ask(id: String, action: Dictionary) -> Dictionary:
	var want := str(action.get("want", ""))
	var reward := str(action.get("reward", "thanks"))
	var made: Dictionary = asks.create(id, want, reward, "", "ai")
	if not bool(made.get("ok", false)): return {"status": "failed", "reason": str(made.get("error", "Not possible right now"))}
	return {"status": "completed", "reason": "Favour noted in Anon's notebook: %s" % ASK_RULES.describe(want, reward, _pony_names())}

## [invite]: an invitation in Anon's notebook until the event ends (calendar, WP7, when present).
func _dispatch_invite(id: String, action: Dictionary) -> Dictionary:
	var event := str(action.get("event_id", ""))
	var hours: float = ASKS.DEFAULT_HOURS
	if calendar != null and calendar.has_method("hours_left"):
		var left: Variant = calendar.call("hours_left", event)
		if (left is float or left is int) and float(left) > 0.0: hours = float(left)
	var made: Dictionary = asks.invite(id, event, "", hours)
	if not bool(made.get("ok", false)): return {"status": "failed", "reason": str(made.get("error", "Not possible right now"))}
	if calendar != null and calendar.has_method("note_invited"): calendar.call("note_invited", event, id)
	return {"status": "completed", "reason": "Invitation noted in Anon's notebook"}

## Loaded ponies' display names ({id: name}), for fetch favours.
func _pony_names() -> Dictionary:
	var names := {}
	var director: Variant = game.get("director") if is_instance_valid(game) else null
	var characters: Variant = (director as Node).get("characters") if is_instance_valid(director) else null
	if not characters is Dictionary: return names
	for pony: Variant in characters:
		var entry: Variant = (characters as Dictionary)[pony]
		var profile: Variant = (entry as Dictionary).get("profile") if entry is Dictionary else null
		names[str(pony)] = str((profile as Dictionary).get("name", pony)) if profile is Dictionary else str(pony).replace("_", " ").capitalize()
	return names

## pony_prompt_notes provider: at most one line per module, only for capabilities present now
## (the cached ai_context row), at most NOTE_CHARS in all.
func prompt_note(pony_id: String) -> String:
	var cached: Variant = _ai_cache.get(pony_id)
	var actor: Node3D = (cached as Dictionary).get("actor") as Node3D if cached is Dictionary and is_instance_valid((cached as Dictionary).get("actor")) else null
	if actor == null:
		var director: Variant = game.get("director") if is_instance_valid(game) else null
		var characters: Variant = (director as Node).get("characters") if is_instance_valid(director) else null
		if characters is Dictionary and (characters as Dictionary).get(pony_id) is Dictionary:
			actor = ((characters as Dictionary)[pony_id] as Dictionary).get("node") as Node3D
	if not is_instance_valid(actor): return ""
	return "\n".join(_ai_row(pony_id, actor).lines).left(NOTE_CHARS)
