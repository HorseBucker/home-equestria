extends Node
## Anon's side of letter writing (docs/LETTERS_PLAN_2026_10_29.md sections 4.2 and 7). Created by
## relationship_runtime.gd setup; groups "letter_paper" and "letter_dictation".
## - Starter paper: once per world, three plain sheets and a quill go into the briefcase
##   (state.letter_paper, saved with the world); a full briefcase retries later.
## - Desktop typing: a click on a held draft opens a typing session. The letter's line being typed
##   lives in a hidden LineEdit (keys, repeat and layouts as everywhere else, and every input
##   handler already treats a focused LineEdit as typing); the text appears only on the paper.
##   Enter starts a new line, Backspace on an empty line goes back up, "scratch that" alone on a
##   line crosses out the last sentence, Esc or a click ends it (a click held on sends, through
##   letter_tool.gd). The session is the desktop activity (player/desktop_action_owner.gd): it owns
##   the hand and locks movement, and menus end it before they open.
## - VR dictation: while the quill's nib is over an open draft (quill_tool.gd dictate_tick) and for
##   a moment after, is_dictating() is true: director_speech_input.gd sends his words to
##   take_words instead of to the ponies. A push-to-talk mic is opened hands-free meanwhile. A
##   sentence he is still saying keeps dictation on until it ends, and the mic mode only switches
##   between sentences (a switch mid-sentence would throw the recording away).
const DESKTOP_OWNER := preload("res://player/desktop_action_owner.gd")
const LETTER_TEXT := preload("res://world/letters/letter_text.gd")
const STATIONERY := preload("res://world/letters/stationery.gd")
const TOOL := preload("res://world/letters/paper/letter_tool.gd")
const GROUP := "letter_paper"
const DICTATION_GROUP := "letter_dictation"
const STATE_KEY := "letter_paper"
const STARTER_PAPER := 3
const POLL := 2.0
## Dictation stays on this long after the nib leaves the paper, so a sentence being spoken as
## the quill is pulled away still lands on the letter.
const DICTATION_GRACE_MS := 1500
const SAVE_TYPING := 2.0

var game: Node
var _poll := POLL
var _dictation_letter := ""
var _dictation_item: WeakRef
var _dictation_at := -100000
var _mic_restore := ""
## A sentence began while dictating and is still being spoken: it lands on the paper too.
var _carry := false
var _typing_letter := ""
var _typing_item: WeakRef
var _typing_inventory: Node
var _committed := ""
var _typing_dirty := false
var _typing_saved_at := 0.0
var _lock_owned := false
var _field: LineEdit

func setup(host: Node) -> void:
	game = host
	add_to_group(GROUP)
	add_to_group(DICTATION_GROUP)
	var context: Variant = game.get("world_context")
	if context is Node and (context as Node).has_signal("reopened"):
		(context as Node).connect("reopened", _on_reopened)

func _exit_tree() -> void:
	end_typing()
	_open_mic(false)

## Another world or save slot was loaded: any session belongs to the old one.
func _on_reopened(_world_id: String) -> void:
	end_typing()
	_dictation_letter = ""; _dictation_at = -100000; _carry = false

func _process(delta: float) -> void:
	# Hands-free dictation follows the quill every frame (a few comparisons), between sentences only.
	var hearing := _hearing()
	if not hearing: _carry = false
	elif _quill_on(): _carry = true
	var dictation := is_dictating()
	if dictation != (not _mic_restore.is_empty()) and not hearing: _open_mic(dictation)
	_poll -= delta
	if _poll > 0.0: return
	_poll = POLL
	_grant_starter()
	if typing() and _typing_dirty and Time.get_ticks_msec() * 0.001 - _typing_saved_at > SAVE_TYPING: _save_typing()

# --- starter paper --------------------------------------------------------------------------

func _context() -> Node:
	var context: Variant = game.get("world_context") if is_instance_valid(game) else null
	return context as Node if context is Node and is_instance_valid(context) else null

func _store() -> Object:
	var briefcase: Variant = game.get("inventory") if is_instance_valid(game) else null
	if not briefcase is Node or not is_instance_valid(briefcase): return null
	var store: Variant = (briefcase as Node).get("inventory")
	return store as Object if store is Object else null

## Once per world: the starter sheets and quill, after the title and loading are over.
func _grant_starter() -> bool:
	var context := _context()
	var store := _store()
	if context == null or store == null or bool(context.get("_read_only")) or str(context.get("world_id")).is_empty(): return false
	var briefcase: Node = game.get("inventory")
	if bool(briefcase.get("hud_hidden")) or game.has_node("LoadingCover"): return false
	var state: Dictionary = context.get("state")
	var flags: Dictionary = state.get(STATE_KEY) as Dictionary if state.get(STATE_KEY) is Dictionary else {}
	if bool(flags.get("starter", false)): return false
	if not bool(flags.get("paper", false)):
		if int(store.call("grant", STATIONERY.item_id("plain"), STARTER_PAPER)) < 0: return false
		flags["paper"] = true
		state[STATE_KEY] = flags; context.call("_changed")
	if not bool(flags.get("quill", false)):
		if int(store.call("grant", STATIONERY.QUILL, 1)) < 0: return false
		flags["quill"] = true
	flags["starter"] = true
	state[STATE_KEY] = flags; context.call("_changed")
	print("[letters] starter writing paper and quill in the briefcase")
	return true

# --- VR dictation ---------------------------------------------------------------------------

## The quill's nib is over this draft's open sheet this tick (quill_tool.gd). False when the
## letter is no longer a draft.
func dictate_tick(letter_id: String, item: Node) -> bool:
	var post: Node = get_tree().get_first_node_in_group("letter_post")
	if post == null or letter_id.is_empty(): return false
	var row: Dictionary = post.call("row", letter_id)
	if str(row.get("status", "")) != "draft": return false
	_dictation_letter = letter_id
	_dictation_item = weakref(item)
	_dictation_at = Time.get_ticks_msec()
	return true

func is_dictating() -> bool:
	return _quill_on() or (_carry and not _dictation_letter.is_empty())

func _quill_on() -> bool:
	return not _dictation_letter.is_empty() and Time.get_ticks_msec() - _dictation_at <= DICTATION_GRACE_MS

func _speech() -> Node:
	var director: Variant = game.get("director") if is_instance_valid(game) else null
	var speech: Variant = (director as Node).get("speech") if director is Node and is_instance_valid(director) else null
	return speech as Node if speech is Node and is_instance_valid(speech) else null

## The microphone is inside a sentence (speech_input.gd).
func _hearing() -> bool:
	var speech := _speech()
	return speech != null and bool(speech.get("_in_speech"))

## His transcribed words for the letter under the quill; "scratch that" crosses out the last
## sentence (letter_text.gd dictate).
func take_words(text: String) -> void:
	var post: Node = get_tree().get_first_node_in_group("letter_post")
	if post == null or _dictation_letter.is_empty() or text.strip_edges().is_empty(): return
	var row: Dictionary = post.call("row", _dictation_letter)
	if str(row.get("status", "")) != "draft": return
	var written: String = LETTER_TEXT.dictate(str(row.get("text", "")), text)
	if not bool(post.call("set_text", _dictation_letter, written)): return
	var item: Variant = _dictation_item.get_ref() if _dictation_item != null else null
	if is_instance_valid(item) and TOOL.handles(item as Node): TOOL.on(item as Node3D).refresh_sheet()

## A push-to-talk microphone listens hands-free while the quill writes (speech_input.gd VAD).
func _open_mic(on_: bool) -> void:
	var speech := _speech()
	if speech == null:
		_mic_restore = ""; return
	if on_:
		if str(speech.get("mode")) == "ptt":
			_mic_restore = "ptt"
			speech.set("mode", "vad"); speech.call("apply_settings", false)
		else: _mic_restore = "-"   # already open (or off): nothing to restore
	elif not _mic_restore.is_empty():
		if _mic_restore == "ptt" and str(speech.get("mode")) == "vad":
			speech.set("mode", "ptt"); speech.call("apply_settings", false)
		_mic_restore = ""

# --- desktop typing -------------------------------------------------------------------------

func typing() -> bool:
	return not _typing_letter.is_empty()

## Opens a typing session on a held draft; false if another activity owns the hand.
func begin_typing(letter_id: String, item: Node3D, inventory: Node) -> bool:
	if typing(): return _typing_letter == letter_id
	var post: Node = get_tree().get_first_node_in_group("letter_post")
	if post == null or not DESKTOP_OWNER.claim(inventory, self): return false
	var row: Dictionary = post.call("row", letter_id)
	if str(row.get("status", "")) != "draft":
		DESKTOP_OWNER.release(inventory, self); return false
	_typing_letter = letter_id; _typing_item = weakref(item); _typing_inventory = inventory
	var text := str(row.get("text", ""))
	var cut := text.rfind("\n")
	_committed = text.substr(0, cut + 1)
	_make_field()
	_field.text = text.substr(cut + 1)
	_field.max_length = maxi(1, LETTER_TEXT.MAX_CHARS - _committed.length())
	_field.caret_column = _field.text.length()
	_field.grab_focus()
	var body: Variant = inventory.get("player_body")
	if body is Node and is_instance_valid(body) and "controls_locked" in body and not bool((body as Node).get("controls_locked")):
		(body as Node).set("controls_locked", true); _lock_owned = true
	_typing_dirty = false; _typing_saved_at = Time.get_ticks_msec() * 0.001
	_show_live()
	return true

## Ends the session: the text is stored, the sheet folds, the hand and movement are free again.
func end_typing() -> void:
	if not typing(): return
	_save_typing()
	var inventory := _typing_inventory
	var item: Variant = _typing_item.get_ref() if _typing_item != null else null
	_typing_letter = ""; _committed = ""
	if is_instance_valid(_field):
		_field.text = ""
		_field.release_focus()
	if _lock_owned and is_instance_valid(inventory):
		var body: Variant = inventory.get("player_body")
		if body is Node and is_instance_valid(body): (body as Node).set("controls_locked", false)
	_lock_owned = false
	if is_instance_valid(inventory): DESKTOP_OWNER.release(inventory, self)
	_typing_inventory = null
	if is_instance_valid(item) and TOOL.handles(item as Node):
		var sheet: Node = (item as Node).get_node_or_null("LetterSheet")
		if sheet != null: sheet.call("fold")
		TOOL.on(item as Node3D).refresh_sheet()

## Menus and other activities end typing first (desktop_action_owner.gd).
func cancel_desktop_activity() -> void:
	end_typing()

func _letter_text() -> String:
	return (_committed + _field.text).left(LETTER_TEXT.MAX_CHARS) if is_instance_valid(_field) else _committed

func _save_typing() -> void:
	if not typing(): return
	var post: Node = get_tree().get_first_node_in_group("letter_post")
	if post != null: post.call("set_text", _typing_letter, _letter_text())
	_typing_dirty = false
	_typing_saved_at = Time.get_ticks_msec() * 0.001

func _show_live() -> void:
	var item: Variant = _typing_item.get_ref() if _typing_item != null else null
	if is_instance_valid(item) and TOOL.handles(item as Node): TOOL.on(item as Node3D).refresh_sheet(_letter_text())

func _make_field() -> void:
	if is_instance_valid(_field): return
	var layer := CanvasLayer.new(); layer.name = "LetterTyping"; layer.layer = -10
	add_child(layer)
	_field = LineEdit.new(); _field.name = "LetterLine"
	# Off screen and invisible: the words show on the paper only.
	_field.position = Vector2(-4000, -4000); _field.size = Vector2(400, 30)
	_field.modulate = Color(1, 1, 1, 0)
	_field.context_menu_enabled = false
	_field.virtual_keyboard_enabled = false
	_field.select_all_on_focus = false
	_field.caret_blink = false
	layer.add_child(_field)
	_field.text_changed.connect(func(_text: String) -> void:
		_typing_dirty = true
		_show_live())

## Typing's own keys and clicks, before the hidden field gets the printable ones.
func _input(event: InputEvent) -> void:
	if not typing(): return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed or not click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			get_viewport().set_input_as_handled(); return
		var inventory := _typing_inventory
		var item: Variant = _typing_item.get_ref() if _typing_item != null else null
		end_typing()
		# The click that ends typing may be held on to send the letter.
		if click.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(item) and TOOL.handles(item as Node):
			TOOL.on(item as Node3D).hold_after_typing(inventory, "desktop")
		get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not (event as InputEventKey).pressed: return
	var key := event as InputEventKey
	match key.keycode if key.keycode != KEY_NONE else key.physical_keycode:
		KEY_ESCAPE:
			end_typing()
		KEY_ENTER, KEY_KP_ENTER:
			var line := _field.text
			if LETTER_TEXT.is_scratch_line(line):
				_committed = LETTER_TEXT.strike_last_sentence(_committed.strip_edges(false, true))
				if not _committed.is_empty(): _committed += "\n"
			elif _committed.length() + line.length() + 1 <= LETTER_TEXT.MAX_CHARS:
				_committed += line + "\n"
			else: return
			_set_line("")
		KEY_BACKSPACE:
			if not _field.text.is_empty() or _committed.is_empty(): return
			# Back up onto the line above.
			var above := _committed.trim_suffix("\n")
			var cut := above.rfind("\n")
			_committed = above.substr(0, cut + 1)
			_set_line(above.substr(cut + 1))
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END, KEY_TAB, KEY_PAGEUP, KEY_PAGEDOWN:
			pass   # The writing goes on at the end of the letter.
		_:
			return
	get_viewport().set_input_as_handled()

func _set_line(text: String) -> void:
	_field.text = text
	_field.max_length = maxi(1, LETTER_TEXT.MAX_CHARS - _committed.length())
	_field.caret_column = text.length()
	_typing_dirty = true
	_save_typing()
	_show_live()

## The desktop hint while typing (interaction_hints.gd asks the desktop activity owner).
func interaction_hint() -> Dictionary:
	var item: Variant = _typing_item.get_ref() if _typing_item != null else null
	if not typing() or not is_instance_valid(item): return {}
	var text := "Type your letter   Enter · New line   Esc · Done"
	var post: Node = get_tree().get_first_node_in_group("letter_post")
	if post != null:
		var check: Dictionary = post.call("can_send", _typing_letter)
		if bool(check.get("ok", false)): text += "   Hold click · Send to " + str(check.get("to_name", ""))
	return {"target": item, "text": text, "point": (item as Node3D).global_position, "outline": null}

## Puts a briefcase letter into a free hand (COURIER, after Anon takes it from the mailbox).
## `inventory` is the briefcase node; side "" picks the desktop hand or a free VR hand.
static func put_in_hand(inventory: Node, letter_id: String, side: String) -> bool:
	if not is_instance_valid(inventory) or letter_id.is_empty(): return false
	var store: Object = inventory.get("inventory")
	if store == null: return false
	var slots: Array = store.get("slots")
	var index := -1
	for slot_index in slots.size():
		var slot: Dictionary = slots[slot_index]
		if str(slot.get("id", "")) == "letter:" + letter_id: index = slot_index; break
	if index < 0: return false
	var sides: Array = [side] if not side.is_empty() else (["desktop"] if bool(inventory.get("_desktop")) else ["right", "left"])
	for hand: String in sides:
		if bool(inventory.call("hand_busy", hand)): continue
		var pose := Transform3D.IDENTITY
		if hand == "desktop":
			var eye: Camera3D = inventory.get("camera")
			if eye != null: pose = eye.global_transform
		else:
			var sample: Dictionary = inventory.call("hand_sample", hand)
			if not bool(sample.get("active", false)): continue
			pose = sample.pose
		if bool(inventory.call("take_slot", hand, index, pose, false)): return true
	return false
