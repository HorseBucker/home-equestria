extends "res://world/ai/pony_action_schema.gd"
## Watch Party: the [watch_tv] action (res://mods/watch_party/watch_invite.gd carries it out). The
## game's TYPES, FIELDS, ALIASES and TAG_HELP are constants a mod cannot add to, and its own
## checks read them from inside this script. So decode(), decode_tags() and validate(), the three
## entry points the rest of the game calls, take [watch_tv] out of a reply, let the game read the
## rest exactly as it would, and put the action back in. Its help line reaches the prompt through
## the director (ext/conversation_director.gd). Only offered while the pony has "watch_tv" among her
## capabilities (ext/pony_action_executor.gd); otherwise everything is the game's own.
## Also Zecora's way to the flatscreen lying in the Everfree (finds.gd slab_place): while it lies
## there, her locations include it ("point:X,Z", the navigator's own story waypoint form, labelled
## "the strange black slab in the Everfree"), so her [lead: player, strange black slab] is a lead
## the game carries out. Nopony else is given it.
## Applied by the game (mod.json "extends"); see res://mods/watch_party/hooks.gd.

const WATCH_PARTY_PATH := "res://world/ai/pony_action_schema.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/hooks.gd")
const WATCH_PARTY_TYPE := "watch_tv"
## The tag and the spellings a model uses for it.
const WATCH_PARTY_NAMES := ["watch_tv", "watchtv", "watch", "watch_movie", "watch_a_movie", "watch_show", "watch_television", "television", "tv", "movie"]
## Movement tags [watch_tv] already does (walking to the set, sitting or lying down there): a reply
## that has it drops them instead of letting them replace it (watch_invite.gd KEPT).
const WATCH_PARTY_COVERED := ["sit", "lie_down", "stay", "stand", "sit_on_seat"]

const WATCH_PARTY_FINDS := preload("res://mods/watch_party/finds.gd")
const WATCH_PARTY_GUIDE := "zecora"

static func _watch_party_game() -> Script:
	return WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH)

static func _watch_party_offered(context: Dictionary) -> bool:
	return WATCH_PARTY_TYPE in context.get("capabilities", [])

## The context with the slab among its places (a copy; the caller's is left as it was).
static func _watch_party_with_slab(context: Dictionary) -> Dictionary:
	var place := WATCH_PARTY_FINDS.slab_place()
	if place.is_empty(): return context
	var out := context.duplicate()
	var locations: Array = (context.get("locations", []) as Array).duplicate()
	if not place.id in locations: locations.append(place.id)
	out.locations = locations
	var labels: Dictionary = (context.get("place_labels", {}) as Dictionary).duplicate()
	labels[place.id] = place.label
	out.place_labels = labels
	return out

static func _watch_party_places(context: Dictionary, actor: String) -> Dictionary:
	return _watch_party_with_slab(context) if actor == WATCH_PARTY_GUIDE else context

static func validate(action: Variant, context: Dictionary) -> String:
	if action is Dictionary and str((action as Dictionary).get("location_id", "")).begins_with("point:"):
		# Zecora's lead to the slab, checked again when it is carried out.
		context = _watch_party_with_slab(context)
	if not action is Dictionary or (action as Dictionary).get("type") != WATCH_PARTY_TYPE:
		return str(_watch_party_game().call("validate", action, context))
	if not _id((action as Dictionary).get("id")): return "Invalid action ID"
	if not _watch_party_offered(context): return "Capability unavailable: " + WATCH_PARTY_TYPE
	if not _keys(action, ["id", "type"]): return "Unknown action fields"
	return ""

static func decode_tags(text: String, actor: String, turn: int, context: Dictionary) -> Dictionary:
	context = _watch_party_places(context, actor)
	if not _watch_party_offered(context): return _watch_party_game().call("decode_tags", text, actor, turn, context)
	var asked := _watch_party_strip(text)
	var result: Dictionary = _watch_party_game().call("decode_tags", str(asked.text), actor, turn, context)
	return _watch_party_join(result, bool(asked.found), turn)

static func decode(text: String, actor: String, turn: int, context: Dictionary, bind_request := false) -> Dictionary:
	var game := _watch_party_game()
	context = _watch_party_places(context, actor)
	if not _watch_party_offered(context): return game.call("decode", text, actor, turn, context, bind_request)
	var body := text.strip_edges()
	if body.begins_with("```"):
		body = body.substr(3).strip_edges()
		if body.to_lower().begins_with("json"): body = body.substr(4).strip_edges()
		if body.ends_with("```"): body = body.left(-3).strip_edges()
	if body.begins_with("{"): return _watch_party_json(text, body, actor, turn, context, bind_request)
	var asked := _watch_party_strip(text)
	if not bool(asked.found): return game.call("decode", text, actor, turn, context, bind_request)
	var result: Dictionary = game.call("decode", str(asked.text), actor, turn, context, bind_request)
	return _watch_party_join(result, true, turn)

## The reply without its [watch_tv] tags: {"text", "found"}.
static func _watch_party_strip(text: String) -> Dictionary:
	var tags := RegEx.create_from_string("\\[\\s*([A-Za-z][A-Za-z _-]{1,40}?)\\s*(?:[:=][^\\]\\r\\n]*)?\\]")
	var out := text
	var found := false
	for tag: RegExMatch in tags.search_all(text):
		var tag_name := tag.get_string(1).strip_edges().to_lower().replace(" ", "_").replace("-", "_")
		if tag_name not in WATCH_PARTY_NAMES: continue
		out = out.replace(tag.get_string(0), "")
		found = true
	return {"text": out.strip_edges() if found else text, "found": found}

## [watch_tv] added to what the game read from the rest of a tag reply.
static func _watch_party_join(result: Dictionary, found: bool, turn: int) -> Dictionary:
	if not found or result.has("error"): return result
	var kept: Array = []
	var moving := false
	for action: Variant in result.get("actions", []):
		if action is Dictionary and _watch_party_covered(action): continue
		if action is Dictionary and channel(str((action as Dictionary).get("type", ""))) == "movement": moving = true
		kept.append(action)
	var dropped: Array = result.get("dropped", [])
	if moving: dropped.append("[watch_tv] (Only one movement per reply)")
	elif kept.size() >= 2: dropped.append("[watch_tv] (At most two actions per reply)")
	else:
		kept.append({"id": "t%d-%d-%s" % [turn, kept.size(), WATCH_PARTY_TYPE], "type": WATCH_PARTY_TYPE})
		result.actions = kept
		result.control_only = false
	result.dropped = dropped
	return result

## A structured (JSON) reply: the game checks it without its watch_tv action, then it is added.
static func _watch_party_json(text: String, body: String, actor: String, turn: int, context: Dictionary, bind_request: bool) -> Dictionary:
	var game := _watch_party_game()
	var parser := JSON.new()
	if parser.parse(body) != OK or not parser.data is Dictionary or not (parser.data as Dictionary).get("actions") is Array:
		return game.call("decode", text, actor, turn, context, bind_request)
	var value: Dictionary = parser.data
	var watch: Dictionary = {}
	var rest: Array = []
	for action: Variant in value.actions:
		if action is Dictionary and (action as Dictionary).get("type") == WATCH_PARTY_TYPE and watch.is_empty(): watch = action
		else: rest.append(action)
	if watch.is_empty(): return game.call("decode", text, actor, turn, context, bind_request)
	# What [watch_tv] already does is dropped, as in a tag reply.
	rest = rest.filter(func(action: Variant) -> bool: return not (action is Dictionary and _watch_party_covered(action)))
	var error := validate(watch, context)
	if error != "": return {"error": error}
	if rest.size() >= 2: return {"error": "At most two actions per reply"}
	for action: Variant in rest:
		if action is Dictionary and channel(str((action as Dictionary).get("type", ""))) == "movement":
			return {"error": "One intention per channel per reply"}
		if action is Dictionary and (action as Dictionary).get("id") == watch.get("id"):
			return {"error": "Duplicate action IDs in reply"}
	value.actions = rest
	var result: Dictionary = game.call("decode", JSON.stringify(value), actor, turn, context, bind_request)
	if result.has("error"): return result
	var actions: Array = result.get("actions", [])
	actions.append(watch.duplicate(true))
	result.actions = actions
	result.control_only = false
	return result

static func _watch_party_covered(action: Dictionary) -> bool:
	var kind := str(action.get("type", ""))
	if kind in WATCH_PARTY_COVERED: return true
	return kind in ["follow", "approach"] and str(action.get("target_id", "")) == "player"
