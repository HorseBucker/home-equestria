extends "res://world/ai/conversation_director.gd"
## Watch Party: the ponies' side of watching television with Anon.
## - _action_prompt(): the [watch_tv] help line among her extra tags while she is offered it
##   (ext/pony_action_executor.gd capabilities), and in a group's shared action reference.
## - system_prompt(): a pony watching with Anon gets the note on what is on
##   (res://mods/watch_party/watch_company.gd note_for: title, place in it, lines she saw).
## - _group_prompt(): a group in front of a set gets the group note (watch_company.gd group_note:
##   who has seen what, so a pony who sat down late does not borrow what the others watched).
## - _on_physical_reaction(): "watch" is a remark about what is on (watch_company.gd sends it at a
##   scene break or a gap in the dialogue). Like a lull it may be only [silence], never during a
##   busy turn or while Anon speaks, and it does not count as chatting. A watching pony gets no lull
##   ("quiet"): her remarks keep the film's pace instead.
## - handle_text(): Anon speaking to a pony watching with him, asking her to look at the screen
##   ("look at this", "who's that?") or long after her last look: the screen is described first
##   (watch_company.gd look_before_reply, a few seconds at most), so her answer sees it.
## Applied by the game (mod.json "extends"); see res://mods/watch_party/hooks.gd.

## Marks this script as Watch Party's extension of the game script (hooks.gd).
const WATCH_PARTY_PATH := "res://world/ai/conversation_director.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/hooks.gd")

const WATCH_PARTY_INVITE := "res://mods/watch_party/watch_invite.gd"
const WATCH_PARTY_HELP := "- [watch_tv] watch something on Anon's television with him: you go to the set (or go along with him until you reach one) and settle in on a seat or the floor in front of it; only if you want to, and say yes or no in your own words. It does the walking and the sitting down: add no [follow], [sit], [lie_down] or [stay] with it"
## Where the help line goes (world/ai/director_prompts.gd _action_prompt and _group_prompt).
const WATCH_PARTY_SOLO_LIST := "Your extra tags now:\n"
const WATCH_PARTY_GROUP_LIST := "This reference grants no extra capabilities.\n"
const WATCH_PARTY_CONTEXT := "[On the television you are watching, not spoken to you] "
const WATCH_PARTY_BRIEF := " LESS IS MORE: one or two words, or only [silence], are often enough; longer chatter only when the moment invites it, not after every touch. Do not repeat this instruction."
## Set while a "watch" remark builds its prompt: its event already says what is on.
var _watch_party_bare := false
const WATCH_PARTY_HUB := "/root/Mods/watch_party"

func handle_text(text: String) -> void:
	var hub: Node = get_node_or_null(WATCH_PARTY_HUB)
	var company: Variant = hub.get("company") if hub != null else null
	if not is_instance_valid(company) or not (company as Node).has_method("wants_look") or not bool((company as Node).call("wants_look", text)):
		super(text)
		return
	if is_instance_valid(hud): hud.set_state("thinking", "You: " + text.strip_edges().left(120))
	_watch_party_thinking(company as Node, text)
	await company.look_before_reply(text)
	super(text)

## The pony about to look shows her thinking dots over her head while the picture is described
## (playtest 2026-11-07: asked something, she gave no sign of anything for a few seconds). The
## reply itself then shows them as always (_show_indicator).
func _watch_party_thinking(company: Node, text: String) -> void:
	var target: Variant = company.call("_look_target", text) if company.has_method("_look_target") else []
	if not target is Array or (target as Array).is_empty(): return
	var id := str((target as Array)[0])
	if not characters.has(id) or not is_instance_valid(player_head): return
	var node: Variant = characters[id].node
	if not is_instance_valid(node): return
	if not is_instance_valid(indicator):
		indicator = INDICATOR.new()
		add_child(indicator)
	indicator.show_for(node, player_head, "thinking")

func _watch_party_offered(id: String) -> bool:
	if not is_instance_valid(actions) or not actions.has_method("context"): return false
	var context: Variant = actions.context(id, _action_targets(id))
	return context is Dictionary and "watch_tv" in (context as Dictionary).get("capabilities", [])

func _action_prompt(id: String) -> String:
	var text := super(id)
	if not _watch_party_offered(id): return text
	if WATCH_PARTY_SOLO_LIST in text: return text.replace(WATCH_PARTY_SOLO_LIST, WATCH_PARTY_SOLO_LIST + WATCH_PARTY_HELP + "\n")
	return text + "\n" + WATCH_PARTY_SOLO_LIST + WATCH_PARTY_HELP

func system_prompt(id: String) -> String:
	var text := super(id)
	if _watch_party_bare: return text
	var note := str(load(WATCH_PARTY_INVITE).call("note", id))
	return text if note.is_empty() else text + "\n\n" + note

func _group_prompt() -> String:
	var text := super()
	var members: Array = group.members.duplicate() if group != null else []
	if members.any(func(member: Variant) -> bool: return _watch_party_offered(str(member))):
		if WATCH_PARTY_GROUP_LIST in text: text = text.replace(WATCH_PARTY_GROUP_LIST, WATCH_PARTY_GROUP_LIST + WATCH_PARTY_HELP + "\n")
		else: text += "\n" + WATCH_PARTY_HELP
	var note := str(load(WATCH_PARTY_INVITE).call("group_note", members))
	return text if note.is_empty() else text + "\n" + note

func _on_physical_reaction(kind: String, id: String, deferred: bool = false, summary := "") -> void:
	if kind == "quiet" and bool(load(WATCH_PARTY_INVITE).call("watching", self, id)): return
	if kind == "watch":
		_watch_party_remark(id, summary)
		return
	super(kind, id, deferred, summary)

## The game's contact reaction (world/ai/director_contacts.gd _on_physical_reaction) for a remark on
## what is on: always offered (no reaction chance), no chat clock, no encounter event.
func _watch_party_remark(id: String, summary: String) -> void:
	if quiet_moment(id): return
	if not characters.has(id): return
	if not is_instance_valid(player_head) or not is_instance_valid(characters[id].node): return
	if not awareness.can_hear(characters[id].node, player_head, _earshot(id)): return
	if state != "idle" or speech.state == "hearing": return
	_current = id; _listener_id = "player"; _turn_id += 1; _rewrite_used = false; _recorded = false
	_pending_text = ""; _pending_actions = []; _player_text = ""
	_set_attention(id, player_head)
	state = "thinking"; speech.set_muted(false); _show_indicator("thinking"); hud.set_state("thinking", "")
	var messages: Array = characters[id].history.duplicate(true)
	_physical_context = time_gap_note(id) + WATCH_PARTY_CONTEXT + summary
	messages.append({"role": "user", "content": _physical_context + WATCH_PARTY_BRIEF})
	if not await _take_llm(): return
	_watch_party_bare = true
	var prompt: String = system_prompt(id)
	_watch_party_bare = false
	_trace_request("contact:watch", id, prompt, messages)
	_label_next("watch_comment")
	if not llm.complete(prompt, messages, _on_reply.bind(_turn_id)): _fail("llm busy")
