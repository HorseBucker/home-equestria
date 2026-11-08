extends Node
## Settings → Watch Party: a tab of the mod's own at the foot of the game's settings sidebar
## (world/ui/settings_page.gd), the way other mods add theirs (no game script is replaced or
## extended: every settings page that appears is patched, and the patch is taken out again in
## _exit_tree). Its rows change watch_settings.gd and apply at once:
## - Light from the screen (room_light): Full, Near (a short reach) or Off. The light is the
##   biggest graphics cost of a set with ponies in front of it (playtest 2026-11-06).
## - Pony comments (pace): how often a pony watching along remarks (watch_company.gd PACES).
## - What ponies know of the browser (web_ponies), the slideshow on a set left off (slides_when_idle),
##   where the sets are (a spoiler, shown only when asked), skipping the magic quest (skip_quest,
##   "Ozone-powered TVs": dev 2026-11-07, the joke is the ozone AI ponies love to smell in the air).
## - A set Trixie blew up (finds.gd destroyed): a row to put it back at the market, shown only then.
## - The browser's load (browser_fps, browser_scale, browser_pause_hidden, browser_restore) and the
##   (zoom: Home, no setting).
## - Everything the TV menu sets up too (dev 2026-11-07: "if the player wants to set up everything
##   from the settings page, then they should be able to"): video folders, ffmpeg and the picture
##   (Videos), the photo folder (Photo slideshow), the home page and gdCEF (Web browser), Pony
##   vision (its on switch by Pony comments, and the TV menu's whole Pony vision page) and the
##   Setup page. The pages are the TV menu's own (vision_page.gd, setup_page.gd), stacked.

const STYLE := preload("res://world/ui/menu_style.gd")
const FINDS := preload("res://mods/watch_party/finds.gd")
const VISION_PAGE := "res://mods/watch_party/vision_page.gd"
const SETUP_PAGE := "res://mods/watch_party/setup_page.gd"
const SHAPES := [[false, "Fit"], [true, "Fill"]]
## Status lines (ffmpeg, the folders, gdCEF) are read again this often while the tab shows.
const STATUS_EVERY := 0.5
const COMPANY := preload("res://mods/watch_party/watch_company.gd")
const PAGE := "res://world/ui/settings_page.gd"
const TITLE := "Watch Party"
const ICON_KIND := "play"
const LIGHTS := [["full", "Full"], ["near", "Near"], ["off", "Off"]]
const WEB := [["none", "Nothing"], ["words", "Page & words"], ["pictures", "Also pictures"]]
const FPS := [[30, "30"], [15, "15"]]
const SCALES := [[100, "Full"], [75, "75%"]]
## What ponies need to follow a film's words (dev 2026-11-07: say what is needed, where the file
## goes and where to find one). tv_set.gd best_pony_choice: a text track, English first, a file
## beside the video before one inside it, whether or not it is shown on the screen.
const SUBTITLE_NOTE := "Ponies follow what is said in a video through its subtitles, even when they're not shown on the screen. They need text subtitles: ones inside the video file, or a subtitle file (.srt, .ass, .ssa or .vtt) in the same folder as the video, named like it: Movie.mkv and Movie.srt (or Movie.en.srt). Picture subtitles from Blu-rays and DVDs show on the screen, but ponies can't read them. Free subtitle files: OpenSubtitles.com or Podnapisi.net; pick one made for your copy of the video so the timing matches. Without subtitles, ponies know only the video's name."
## Why removing the mod needs this first (finds.gd remove_all).
const UNINSTALL_NOTE := "If you remove the mod while a TV or remote is in your briefcase or set up anywhere, the game sets your whole briefcase aside, bits and all. Press this first in every world you played with the mod: every TV and remote is removed for good. Then quit the game and delete watch_party.pck."
## The colour of a status line saying a download was found (dev 2026-11-07: green, not red).
const FOUND := Color(0.5, 0.88, 0.55)

var hub: Node
## One entry per patched page: {page, button, panel}.
var _patched: Array = []
var _status_wait := 0.0

func _ready() -> void:
	Mods.on_node(PAGE, _on_page)

func _exit_tree() -> void:
	for entry: Dictionary in _patched:
		for key: String in ["button", "panel"]:
			var node: Variant = entry.get(key)
			if is_instance_valid(node): (node as Node).queue_free()
		var page: Variant = entry.get("page")
		if is_instance_valid(page): (page as Node).remove_meta("watch_party_tab")
	_patched.clear()

func _settings() -> RefCounted:
	return hub.get("settings") as RefCounted if is_instance_valid(hub) else null

func _on_page(page: Node) -> void:
	if not is_instance_valid(page) or page.has_meta("watch_party_tab"): return
	page.set_meta("watch_party_tab", true)
	_patch.call_deferred(page)

## The page builds its sidebar in setup(), which may come a frame or two after it is ready.
func _patch(page: Node) -> void:
	for attempt: int in 10:
		if not is_instance_valid(page): return
		var side_scroll: Variant = page.get("_side_scroll")
		if side_scroll is ScrollContainer and (side_scroll as ScrollContainer).get_child_count() > 0 \
				and page.get("_content") is VBoxContainer and page.get("_tab_title") is Label and page.has_method("_button"):
			_build(page)
			return
		await get_tree().process_frame
	if is_instance_valid(page): page.remove_meta("watch_party_tab")

func _build(page: Node) -> void:
	var side := (page.get("_side_scroll") as ScrollContainer).get_child(0) as VBoxContainer
	var content := page.get("_content") as VBoxContainer
	if side == null or content == null: return
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	# A tab like the page's own (settings_page.gd _build_sidebar), last in the sidebar: below
	# Updates, or under another mod's heading when one came first.
	var button: Button = page.call("_button", side, TITLE, _show.bind(page))
	button.theme_type_variation = "Tab"; button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.clip_text = true
	button.custom_minimum_size = Vector2(0, font_size * 2.05)
	button.add_theme_font_size_override("font_size", font_size - 2)
	button.expand_icon = false
	if page.has_method("_icon_texture"): button.icon = page.call("_icon_texture", ICON_KIND)
	button.set_meta("no_sparkle", true)
	var panel := ScrollContainer.new(); panel.name = "WatchPartySettings"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus = true
	panel.visible = false
	# A settings page drawn into a texture (VR, the title) redraws on demand.
	panel.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _redraw(page))
	content.add_child(panel)
	var holder := MarginContainer.new(); holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side_name: String in ["left", "top", "bottom"]: holder.add_theme_constant_override("margin_" + side_name, 4 if side_name != "left" else 6)
	holder.add_theme_constant_override("margin_right", 14)
	panel.add_child(holder)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(list)
	var entry := {"page": page, "button": button, "panel": panel, "rows": {}}
	_patched.append(entry)
	_pills(entry, list, "Light from the screen", "room_light", LIGHTS, "")
	var paces: Array = []
	for key: String in COMPANY.PACE_ORDER: paces.append([key, str(COMPANY.PACES[key].label)])
	_pills(entry, list, "Pony comments", "pace", paces, "")
	_switch(entry, list, "Pony vision", "vision_enabled", "Ponies watching with you now and then see what is on the screen (a picture sent to your vision service). Set the service up under Pony vision below.")
	_pills(entry, list, "Ponies know of the browser", "web_ponies", WEB, "")
	_switch(entry, list, "Slideshow on a set left off", "slides_when_idle", "After a set has been off for 5 minutes while you're nearby, it shows your photos like a picture frame. Pick the folder in the TV menu → Photos & web.")
	_spoilers(entry, list)
	_switch(entry, list, "Ozone-powered TVs", "skip_quest", "Skips the quest to get the TVs working: every TV works as soon as you set it down. Why? Because Equestria's air is thick with ozone, that's why.")
	var lost := VBoxContainer.new(); lost.add_theme_constant_override("separation", 6)
	list.add_child(lost)
	entry.lost = lost
	_heading(entry, list, "Web browser")
	_pills(entry, list, "Frames a second", "browser_fps", FPS, "How often a page is drawn. 15 is lighter on slower computers. Requires browser restart.")
	_pills(entry, list, "Page resolution", "browser_scale", SCALES, "75% draws fewer pixels: lighter on slower computers. Requires browser restart.")
	_switch(entry, list, "Pause tabs you leave", "browser_pause_hidden", "When you switch tabs, any video or sound on the tab you left is paused.")
	_switch(entry, list, "Reopen tabs", "browser_restore", "On: the browser opens with the tabs you had last time. Off: it opens on a single page. Every open tab keeps running, so fewer is lighter.")
	_home_row(entry, list)
	_cef_rows(entry, list)
	_heading(entry, list, "Videos")
	_folder_rows(entry, list)
	_ffmpeg_rows(entry, list)
	_card(entry, list, "Subtitles for the ponies", SUBTITLE_NOTE)
	_pills(entry, list, "Picture", "fill", SHAPES, "Fit shows the whole picture, with black bars on a wide film. Fill fills the screen and cuts off a wide film's sides.")
	_switch(entry, list, "CRT look", "crt", "Scanlines and a curved tube on the vintage set.")
	_heading(entry, list, "Photo slideshow")
	_slides_rows(entry, list)
	_heading(entry, list, "Pony vision")
	_embed(entry, list, VISION_PAGE)
	_heading(entry, list, "Setup")
	_embed(entry, list, SETUP_PAGE)
	_heading(entry, list, "Uninstalling")
	_uninstall_rows(entry, list)
	# Any other tab, the game's or another mod's, hides this one.
	for child: Node in side.get_children(): _watch_button(child, entry)
	side.child_entered_tree.connect(_watch_button.bind(entry))
	_refresh(entry)

func _watch_button(node: Node, entry: Dictionary) -> void:
	if node is Button and node != entry.button and not (node as Button).pressed.is_connected(_hide.bind(entry)):
		(node as Button).pressed.connect(_hide.bind(entry))

func _entry(page: Node) -> Dictionary:
	for entry: Dictionary in _patched:
		if entry.page == page: return entry
	return {}

func _show(page: Node) -> void:
	var entry := _entry(page)
	if entry.is_empty() or not is_instance_valid(page): return
	_fill_fields(entry)
	for embedded: Variant in entry.get("pages", []):
		if is_instance_valid(embedded) and (embedded as Node).has_method("open"): (embedded as Node).call("open")
	var content := page.get("_content") as VBoxContainer
	# Everything under the title row makes way (the page's own lists and pages, other mods' tabs).
	for child: Node in content.get_children():
		if child is Control and child.get_index() > 0 and child != entry.panel: (child as Control).visible = false
	(entry.panel as Control).visible = true
	var side := (entry.button as Button).get_parent()
	for child: Node in side.get_children():
		if child is Button and (child as Button).toggle_mode: (child as Button).set_pressed_no_signal(child == entry.button)
	(page.get("_tab_title") as Label).text = TITLE
	var icon: Variant = page.get("_tab_icon")
	if icon is Control: (icon as Control).set("kind", ICON_KIND)
	_refresh(entry)

func _hide(entry: Dictionary) -> void:
	if is_instance_valid(entry.panel): (entry.panel as Control).visible = false
	if is_instance_valid(entry.button): (entry.button as Button).set_pressed_no_signal(false)

## A small heading between groups of rows.
func _heading(entry: Dictionary, list: VBoxContainer, title: String) -> void:
	var page: Node = entry.page
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	var gap := Control.new(); gap.custom_minimum_size.y = 6
	list.add_child(gap)
	list.add_child(STYLE.label(title.to_upper(), "Faint", maxi(12, font_size - 7)))

## A row card like the page's (settings_page.gd _row): the name and a note, the control beside.
func _card(entry: Dictionary, list: VBoxContainer, title: String, note: String) -> HBoxContainer:
	var page: Node = entry.page
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	var idle: Variant = page.get("_row_idle")
	var hover: Variant = page.get("_row_hover")
	var card := PanelContainer.new()
	if idle is StyleBox: card.add_theme_stylebox_override("panel", idle)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	if idle is StyleBox and hover is StyleBox:
		card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover); _redraw(page))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", idle); _redraw(page))
	list.add_child(card)
	var line := HBoxContainer.new(); line.add_theme_constant_override("separation", 12); card.add_child(line)
	var texts := VBoxContainer.new(); texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER; texts.add_theme_constant_override("separation", 1); line.add_child(texts)
	var name_label := STYLE.label(title, "", font_size)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; texts.add_child(name_label)
	var caption := STYLE.label(note, "Faint", font_size - 5)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; texts.add_child(caption)
	line.set_meta("caption", caption)
	return line

## Choices as pills in one track (settings_page.gd _segments).
func _pills(entry: Dictionary, list: VBoxContainer, title: String, key: String, options: Array, note: String) -> void:
	var page: Node = entry.page
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	var line := _card(entry, list, title, note)
	var track := PanelContainer.new(); track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	line.add_child(track)
	var pills := HBoxContainer.new(); pills.add_theme_constant_override("separation", 4); track.add_child(pills)
	for option: Array in options:
		var pill: Button = page.call("_button", pills, str(option[1]), _choose.bind(entry, key, option[0]))
		pill.theme_type_variation = "Segment"; pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 3)
		pill.set_meta("value", option[0])
	entry.rows[key] = pills
	# No note given: it says what the chosen option does (_option_note), and follows the choice.
	if note.is_empty():
		if not entry.has("captions"): entry.captions = {}
		entry.captions[key] = line.get_meta("caption")

func _switch(entry: Dictionary, list: VBoxContainer, title: String, key: String, note: String) -> void:
	var page: Node = entry.page
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	var line := _card(entry, list, title, note)
	var state := STYLE.label("", "Muted", font_size - 2); state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(state)
	var toggle := CheckButton.new(); toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.focus_mode = Control.FOCUS_ALL; toggle.set_meta("no_lift", true)
	toggle.set_meta("state_label", state)
	toggle.toggled.connect(func(on: bool) -> void: _choose(entry, key, on))
	toggle.mouse_entered.connect(_redraw.bind(page)); toggle.mouse_exited.connect(_redraw.bind(page))
	line.add_child(toggle)
	entry.rows[key] = toggle

func _choose(entry: Dictionary, key: String, value: Variant) -> void:
	var settings := _settings()
	if settings == null: return
	var company: Variant = hub.get("company")
	if key == "vision_enabled":
		(settings.get("vision") as Dictionary).enabled = bool(value)
		settings.save()
	elif key == "pace" and is_instance_valid(company):
		(company as Node).call("set_pace", str(value))   # saves, and the next remark follows the new pace
	elif key in ["fill", "crt"]:
		# Saved, and every set changes now (playtest 2026-11-07: Fit and Fill here seemed to do
		# nothing: a playing video kept its shape until it was started again).
		settings.set(key, value)
		settings.save()
		for tv: Node in get_tree().get_nodes_in_group("watch_tvs"):
			if key == "crt" and tv.has_method("_apply_crt"): tv.call("_apply_crt")
			if key == "fill" and tv.has_method("set_fill"): tv.call("set_fill", bool(value))
	else:
		settings.set(key, value)
		settings.save()
	print("[watch_party] setting %s: %s" % [key, str(value)])
	_refresh(entry)

func _refresh(entry: Dictionary) -> void:
	var settings := _settings()
	if settings == null: return
	_show_lost(entry)
	var spoiler: Variant = entry.get("spoiler")
	if is_instance_valid(spoiler) and (spoiler as Label).visible: (spoiler as Label).text = spoiler_text()
	for key: String in entry.rows:
		var node: Variant = entry.rows[key]
		if not is_instance_valid(node): continue
		var value: Variant = (settings.get("vision") as Dictionary).get("enabled", false) if key == "vision_enabled" else settings.get(key)
		if node is CheckButton:
			(node as CheckButton).set_pressed_no_signal(bool(value))
			((node as Node).get_meta("state_label") as Label).text = "On" if bool(value) else "Off"
		else:
			for pill: Node in (node as Node).get_children():
				if pill is Button: (pill as Button).set_pressed_no_signal(str(pill.get_meta("value")) == str(value))
			var captions: Dictionary = entry.get("captions", {})
			if captions.has(key) and is_instance_valid(captions[key]): (captions[key] as Label).text = _option_note(key, value)
	_redraw(entry.page)

func _redraw(page: Variant) -> void:
	if is_instance_valid(page) and (page as Node).has_method("_redraw"): (page as Node).call("_redraw")

## Where the sets are, behind a button (dev 2026-11-06: the welcome card stays vague; this tells all
## to a player who wants it).
func _spoilers(entry: Dictionary, list: VBoxContainer) -> void:
	var page: Node = entry.page
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	var line := _card(entry, list, "SPOILER: Where are the TVs?", "Where each set is and how to get them working.")
	var text := STYLE.label("", "Muted", font_size - 4)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.visible = false
	var button: Button = page.call("_button", line, "Show", _toggle_spoilers.bind(entry))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	list.add_child(text)
	entry.spoiler = text
	entry.spoiler_button = button

func _toggle_spoilers(entry: Dictionary) -> void:
	var text: Label = entry.spoiler
	text.visible = not text.visible
	(entry.spoiler_button as Button).text = "Hide" if text.visible else "Show"
	if text.visible: text.text = spoiler_text()
	_redraw(entry.page)

static func spoiler_text() -> String:
	var lines := PackedStringArray()
	lines.append("Old CRT set: " + _where(FINDS.VINTAGE, "lying at the forest edge, about 120 m from Fluttershy's cottage. Fluttershy heard it land. From the second day it's for sale in one of the market tents."))
	var untouched := [FINDS.FLAT_STAND, FINDS.FLAT_WALL].all(func(id: String) -> bool: return not FINDS.had(id) and not FINDS.destroyed(id) and not FINDS.at_market(id))
	if untouched:
		lines.append("Flatscreens (stand and wall): deeper in the Everfree, toward Zecora's hut. Zecora can lead you to one of them. From the third day they're for sale in one of the market tents.")
	else:
		lines.append("Flatscreen on its stand: " + _where(FINDS.FLAT_STAND, "deeper in the Everfree, toward Zecora's hut. Zecora can lead you to it. From the third day it's for sale in one of the market tents."))
		lines.append("Wall flatscreen: " + _where(FINDS.FLAT_WALL, "deeper in the Everfree, toward Zecora's hut, further in than the other one. From the third day it's for sale in one of the market tents."))
	lines.append("Remote: comes free with your first TV. You can buy an extra one from one of the market tents from the second day.")
	if FINDS.quest_skipped():
		lines.append("They work as soon as you set them down: \"Ozone-powered TVs\" is on.")
	else:
		lines.append("None of them work until somepony who knows magic has looked at one of each kind. Twilight is a good bet; Princess Celestia and Princess Luna can do it too when they visit, and Trixie will give it a go. Bring it to one of them, or turn on \"Ozone-powered TVs\" below to skip all that.")
	return "\n\n".join(lines)

static func _where(id: String, otherwise: String) -> String:
	if FINDS.destroyed(id): return "blown up. You can put it back at the market below."
	if FINDS.had(id): return "you have it."
	if FINDS.at_market(id): return "for sale in one of the market tents now."
	return otherwise

## A row for each set that blew up, to put it back at the market (shown only when there is one).
func _show_lost(entry: Dictionary) -> void:
	var holder: Variant = entry.get("lost")
	if not is_instance_valid(holder): return
	var gone: Array = FINDS.destroyed_list() if not FINDS.state().is_empty() else []
	var key := ",".join(PackedStringArray(gone))
	if str(entry.get("lost_key", "-")) == key: return
	entry.lost_key = key
	for child: Node in (holder as Node).get_children(): child.queue_free()
	var page: Node = entry.page
	for id: String in gone:
		var line := _card(entry, holder as VBoxContainer, "The %s blew up" % FINDS.kind_name(id), "It's gone for good, unless you put it back up for sale at the market. It will need waking again.")
		var button: Button = page.call("_button", line, "Put it back", _respawn.bind(entry, id))
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _respawn(entry: Dictionary, id: String) -> void:
	FINDS.respawn(id)
	_refresh(entry)

## What the chosen option of a row does, in a few plain lines (dev 2026-11-07: only the one that is
## on, easy to take in).
func _option_note(key: String, value: Variant) -> String:
	match key:
		"room_light":
			match str(value):
				"near": return "The light only reaches what is close in front of the set. Lighter on slower graphics cards."
				"off": return "No light from the screen. Easiest on slower graphics cards."
			return "The set lights the room in the colours of its picture."
		"web_ponies":
			match str(value):
				"words": return "Page & words: the page's title and address and some of its text, and a YouTube video's title and captions. These go to your AI service with the ponies' prompts."
				"pictures": return "Also pictures: page & words, and with Pony vision on, a picture of the page now and then, sent to your vision service."
			return "Nothing: only that you're busy with it. Nothing leaves your computer about what you're browsing."
		"pace": return _pace_note(str(value))
	return ""

## A pace preset in words: how often she remarks, and how often Pony vision looks at the picture.
func _pace_note(pace: String) -> String:
	var row: Dictionary = COMPANY.PACES.get(pace, COMPANY.PACES["normal"])
	var every: Array = row.every
	if every.is_empty(): return "Silent: no remarks. Ponies still watch along, and talk about it if you speak to them."
	var lines := PackedStringArray()
	lines.append("%s: a remark every %s to %s." % [str(row.label), _span(float(every[0])), _span(float(every[1]))])
	var picture := int(row.picture)
	if picture <= 0: return lines[0]
	var minutes := roundi((float(every[0]) + float(every[1])) * 0.5 * picture / 60.0)
	var company: Variant = hub.get("company") if is_instance_valid(hub) else null
	var vision: Variant = (company as Node).get("vision") if is_instance_valid(company) else null
	var on := is_instance_valid(vision) and (vision as Node).has_method("enabled") and bool((vision as Node).call("enabled"))
	if on: lines.append("Pony vision: she looks at the picture every %s remark, about every %d minutes." % [_nth(picture), maxi(1, minutes)])
	else: lines.append("Pony vision is off (TV menu → Pony vision), so she knows only the title and the subtitles.")
	return "\n".join(lines)

static func _span(seconds: float) -> String:
	if seconds < 90.0: return "%d seconds" % roundi(seconds)
	var minutes := seconds / 60.0
	return ("%d minutes" % roundi(minutes)) if absf(minutes - roundf(minutes)) < 0.1 else ("%.1f minutes" % minutes)

static func _nth(n: int) -> String:
	match n:
		1: return "single"
		2: return "second"
		3: return "third"
	return "%dth" % n

# --- what the TV menu sets up -------------------------------------------------------------------

## A row with a text field (and buttons after it). `submit` gets the text when Enter is pressed or
## the field loses the focus.
func _field_row(entry: Dictionary, list: VBoxContainer, title: String, note: String, hint: String, submit: Callable, buttons: Array = []) -> LineEdit:
	var page: Node = entry.page
	var line := _card(entry, list, title, note)
	var field := LineEdit.new()
	field.placeholder_text = hint
	field.custom_minimum_size.x = 300
	field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	field.text_submitted.connect(func(text: String) -> void: submit.call(text))
	field.focus_exited.connect(func() -> void: submit.call(field.text))
	line.add_child(field)
	for button: Array in buttons:
		var made: Button = page.call("_button", line, str(button[0]), button[1])
		made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return field

## A line under the rows that says how something stands (ffmpeg found, the folders).
func _status(entry: Dictionary, list: VBoxContainer, key: String) -> Label:
	var page: Node = entry.page
	var font_size := int(page.get("font_size")) if int(page.get("font_size")) > 0 else 20
	var label := STYLE.label("", "Faint", font_size - 5)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(label)
	if not entry.has("status"): entry.status = {}
	entry.status[key] = label
	return label

func _folder_rows(entry: Dictionary, list: VBoxContainer) -> void:
	entry.folder = _field_row(entry, list, "Video folders", "Every video in these folders and the ones inside them is in the TV menu's library.", "Add a folder, e.g. E:\\Movies", _add_folder.bind(entry),
		[["Add", func() -> void: _add_folder((entry.folder as LineEdit).text, entry)], ["Browse…", _pick.bind(entry, "videos")], ["Rescan", func() -> void: _settings().scan(); _show_status(entry)], ["Clear", func() -> void: _settings().clear_folders(); _show_status(entry)]])
	_status(entry, list, "folders")

func _add_folder(text: String, entry: Dictionary) -> void:
	var dir := text.strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
	if dir.is_empty(): return
	if not DirAccess.dir_exists_absolute(dir):
		((entry.status as Dictionary).folders as Label).text = "No folder at %s" % dir
		return
	(entry.folder as LineEdit).text = ""
	_settings().add_folder(dir)
	_show_status(entry)

func _ffmpeg_rows(entry: Dictionary, list: VBoxContainer) -> void:
	entry.ffmpeg = _field_row(entry, list, "ffmpeg", "Plays the videos. Empty: it is looked for in the game folder and the usual places.", "ffmpeg.exe or its folder", _set_ffmpeg.bind(entry), [["Check", func() -> void: _set_ffmpeg((entry.ffmpeg as LineEdit).text, entry, true)]])
	_status(entry, list, "ffmpeg")

func _set_ffmpeg(text: String, entry: Dictionary, check := false) -> void:
	var settings := _settings()
	if text.strip_edges() == str(settings.ffmpeg_path) and not check: return
	settings.ffmpeg_path = text.strip_edges()
	settings.save()
	hub.call("find_ffmpeg")
	_show_status(entry)

func _slides_rows(entry: Dictionary, list: VBoxContainer) -> void:
	entry.slides = _field_row(entry, list, "Photo folder", "The slideshow shows the pictures in this folder and the ones inside it, in a random order.", "A folder of pictures", _set_slides.bind(entry), [["Browse…", _pick.bind(entry, "slides")]])
	var page: Node = entry.page
	var line := _card(entry, list, "Seconds per picture", "How long each picture stays up. A GIF or WebM plays to its end at least once.")
	var seconds := SpinBox.new()
	seconds.min_value = 2; seconds.max_value = 600; seconds.step = 1
	seconds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seconds.value_changed.connect(func(value: float) -> void:
		if bool(entry.get("filling", false)): return
		_settings().slides_seconds = value
		_settings().save())
	line.add_child(seconds)
	entry.seconds = seconds
	_status(entry, list, "slides")

func _set_slides(text: String, entry: Dictionary) -> void:
	var settings := _settings()
	if text.strip_edges() == str(settings.slides_folder): return
	settings.slides_folder = text.strip_edges()
	settings.save()
	_show_status(entry)

func _home_row(entry: Dictionary, list: VBoxContainer) -> void:
	entry.home = _field_row(entry, list, "Home page", "Where a new tab starts.", "empty: duckduckgo.com", func(text: String) -> void:
		_settings().browser_home = text.strip_edges()
		_settings().save())

func _cef_rows(entry: Dictionary, list: VBoxContainer) -> void:
	entry.cef = _field_row(entry, list, "gdCEF", "Runs the web browser. Empty: its cef_artifacts folder beside HomeEquestria.exe.", "its cef_artifacts folder", _set_cef.bind(entry), [["Check", func() -> void: _set_cef((entry.cef as LineEdit).text, entry, true)]])
	_status(entry, list, "cef")

func _set_cef(text: String, entry: Dictionary, check := false) -> void:
	var settings := _settings()
	if text.strip_edges() == str(settings.browser_folder) and not check: return
	settings.browser_folder = text.strip_edges()
	settings.save()
	var engine: Variant = hub.get("web")
	if is_instance_valid(engine): (engine as Node).call("retry")
	_show_status(entry)

## Windows' folder picker for the video folders or the photo folder.
func _pick(entry: Dictionary, what: String) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Choose a folder with videos" if what == "videos" else "Choose a folder with pictures"
	dialog.dir_selected.connect(func(dir: String) -> void:
		if what == "videos": _add_folder(dir, entry)
		else:
			(entry.slides as LineEdit).text = dir
			_set_slides(dir, entry)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)

## Before removing the mod: everything it added leaves the world (finds.gd remove_all). Asks twice.
func _uninstall_rows(entry: Dictionary, list: VBoxContainer) -> void:
	var page: Node = entry.page
	var line := _card(entry, list, "Before you uninstall", UNINSTALL_NOTE)
	var button: Button = page.call("_button", line, "Remove all TVs", _pack_away.bind(entry))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	entry.pack_button = button
	_status(entry, list, "pack")

func _pack_away(entry: Dictionary) -> void:
	var button: Button = entry.pack_button
	var label: Label = (entry.status as Dictionary).pack
	if not bool(entry.get("pack_armed", false)):
		entry.pack_armed = true
		button.text = "Sure? Press again"
		label.text = "Every TV and remote leaves this world for good."
		_mark(label, -1)
		_redraw(entry.page)
		return
	entry.pack_armed = false
	button.text = "Remove all TVs"
	var game: Variant = Mods.game
	var why: Array = []
	var count: int = FINDS.remove_all((game as Node).get("inventory") as Node if is_instance_valid(game) else null, why)
	if count < 0:
		label.text = str(why[0]) if not why.is_empty() else "Nothing was removed."
		_mark(label, 0)
	else:
		label.text = "Done (%d removed). Now quit the game (it saves as it closes), then delete watch_party.pck from the mods folder." % count
		_mark(label, 1)
	_redraw(entry.page)

## The TV menu's own page, stacked to fit here.
func _embed(entry: Dictionary, list: VBoxContainer, path: String) -> void:
	var script: Script = load(path)
	if script == null: return
	var made: Variant = script.new()
	if not made is Control: return
	(made as Node).set("hub", hub)
	# Ozone-powered TVs (skipping the magic) has its own row above (dev 2026-11-07: not twice).
	if path == SETUP_PAGE: (made as Node).set("show_magic", false)
	(made as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(made as Control)
	# Side by side in the TV menu, stacked here. An HBoxContainer cannot be turned vertical
	# (playtest 2026-11-07: "Can't change orientation"), so its parts move into a column inside it.
	if made is HBoxContainer:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 12)
		for child: Node in (made as Node).get_children(): child.reparent(column, false)
		(made as Node).add_child(column)
	if not entry.has("pages"): entry.pages = []
	(entry.pages as Array).append(made)

## The fields as saved (the tab shown).
func _fill_fields(entry: Dictionary) -> void:
	var settings := _settings()
	if settings == null: return
	entry.filling = true
	for pair: Array in [["ffmpeg", "ffmpeg_path"], ["slides", "slides_folder"], ["home", "browser_home"], ["cef", "browser_folder"]]:
		var field: Variant = entry.get(pair[0])
		if is_instance_valid(field) and not (field as LineEdit).has_focus(): (field as LineEdit).text = str(settings.get(pair[1]))
	if is_instance_valid(entry.get("seconds")): (entry.seconds as SpinBox).value = float(settings.slides_seconds)
	entry.filling = false
	_show_status(entry)

## How ffmpeg, the folders and gdCEF stand now.
func _show_status(entry: Dictionary, count_pictures := true) -> void:
	var labels: Dictionary = entry.get("status", {})
	var settings := _settings()
	if settings == null or labels.is_empty(): return
	if is_instance_valid(labels.get("folders")):
		var folders: PackedStringArray = settings.folders
		(labels.folders as Label).text = ("%d videos in: %s" % [(settings.library as PackedStringArray).size(), ", ".join(folders)]) if not folders.is_empty() else "No folders yet: add the folder your videos are in."
	if is_instance_valid(labels.get("ffmpeg")):
		var found := str(hub.get("ffmpeg"))
		(labels.ffmpeg as Label).text = "Looking for ffmpeg…" if bool(hub.get("_searching")) else ("ffmpeg works: " + found if not found.is_empty() else "ffmpeg not found: videos will not play. The Setup page below says where to get it.")
		_mark(labels.ffmpeg, -1 if bool(hub.get("_searching")) else (1 if not found.is_empty() else 0))
	if count_pictures and is_instance_valid(labels.get("slides")):
		var folder := str(settings.slides_folder)
		(labels.slides as Label).text = ("%d pictures in that folder." % preload("res://mods/watch_party/slideshow.gd").list(folder).size()) if not folder.is_empty() else "No photo folder yet."
	if is_instance_valid(labels.get("cef")):
		var engine: Variant = hub.get("web")
		var cef := str((engine as Node).call("artifacts_folder")) if is_instance_valid(engine) else ""
		(labels.cef as Label).text = ("gdCEF found in %s." % cef) if not cef.is_empty() else "gdCEF not found: the browser will not open. The Setup page below says where to get it."
		_mark(labels.cef, 1 if not cef.is_empty() else 0)
	_redraw(entry.page)

## A status line coloured by how it stands: 1 found (green), 0 missing (red), -1 neither.
static func _mark(label: Label, found: int) -> void:
	label.theme_type_variation = "Warn" if found == 0 else "Faint"
	if found == 1: label.add_theme_color_override("font_color", FOUND)
	else: label.remove_theme_color_override("font_color")

func _process(delta: float) -> void:
	_status_wait -= delta
	if _status_wait > 0.0: return
	_status_wait = STATUS_EVERY
	# ffmpeg's search and gdCEF change by themselves; the picture count only when chosen (a big
	# folder takes a moment to list).
	for entry: Dictionary in _patched:
		if is_instance_valid(entry.panel) and (entry.panel as Control).is_visible_in_tree(): _show_status(entry, false)
