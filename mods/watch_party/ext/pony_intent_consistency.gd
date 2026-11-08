extends "res://world/ai/pony_intent_consistency.gd"
## Watch Party: [watch_tv] walks along with Anon itself (res://mods/watch_party/watch_invite.gd), so
## a reply that accepts "come with me" with it needs no separate travel action.
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_PATH := "res://world/ai/pony_intent_consistency.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/ext_loader.gd")

static func missing(request: String, speech: String, actions: Array) -> String:
	for action: Variant in actions:
		if action is Dictionary and (action as Dictionary).get("type") == "watch_tv": return ""
	return str(WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH).call("missing", request, speech, actions))
