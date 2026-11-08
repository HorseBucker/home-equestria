extends Node
## Pony vision (part 3): now and then a still from the film is described in words by a vision
## model, and the pony remarking hears the description (watch_company.gd). The player lists any
## number of vision APIs (TV menu → Pony vision), each with its own source, model and calls a day.
## - Source: "own" (a provider, address and key of its own), "dialogue" (the game's dialogue
##   settings with another model, e.g. Sonnet while she talks with Opus) or "preset" (a saved LLM
##   preset, world/ai/llm_profiles.gd, again with its own model).
## - Order: "turns" goes round the list one call each; "in_order" uses the first with calls left.
## - Best: the one almost sure to work. When another fails, the same picture goes to the best one
##   at once, and the turn still moves on (key 1 fails → best; next call key 2). It takes turns
##   too unless "best_turns" is off, then it is only the backup.
## - Calls a day: counted per API when sent; the count starts again at midnight Pacific time, when
##   Google AI Studio's free quota resets (quotas there are per Cloud project, not per key).

const LLM := preload("res://world/ai/llm_client.gd")
const PROFILES := preload("res://world/ai/llm_profiles.gd")
const PROVIDERS := ["gemini", "anthropic", "openai"]
const PROVIDER_LABELS := {"gemini": "Google Gemini", "anthropic": "Anthropic Claude", "openai": "OpenAI-compatible"}
const DEFAULT_URLS := {"gemini": "https://generativelanguage.googleapis.com", "anthropic": "https://api.anthropic.com", "openai": ""}
## Longest side of the still sent; enough to tell faces and places, cheap in image tokens.
const MAX_SIDE := 768
const OUTPUT_TOKENS := 260
## Thinking models count their thoughts inside the output cap (world/ai/llm_client.gd).
const REASONING_ROOM := 1024
const TIMEOUT := 30.0
const RECENT_LINES := 6
const DESCRIBE_SYSTEM := "You describe a still from a film or TV show for someone who cannot see the screen. In two or three plain sentences say who is in the shot (how they look, what they are doing, their expression), where it seems to be, and anything striking (action, light, colour, words on screen). Name a character only when the dialogue given makes clear who it is; otherwise describe them. Describe only this picture: never tell the story, guess at it or say what comes next. No preamble."

## A web page on the screen (the browser, when ponies may see it): what site, what is on it.
const WEB_SYSTEM := "You describe a screenshot of a web page for someone who cannot see the screen. In two or three plain sentences say what kind of site and page it is, the main thing on it (a video and what it shows, a post, an article, a shop, a game) and anything striking (a picture, a headline, a few key words). Quote at most a few words. No preamble."

var hub: Node
var _llm: Node
var _busy := false

func _ready() -> void:
	_llm = LLM.new(); _llm.name = "WatchVisionLlm"
	add_child(_llm)

func _settings() -> RefCounted:
	return hub.get("settings") as RefCounted if hub != null else null

func apis() -> Array:
	var settings := _settings()
	return settings.vision.apis if settings != null else []

func enabled() -> bool:
	var settings := _settings()
	return settings != null and bool(settings.vision.enabled)

func busy() -> bool:
	return _busy

## Vision is on and some API can take a call now.
func usable() -> bool:
	return enabled() and not _plan().is_empty()

# --- the day's counts ---------------------------------------------------------------------------

## Calls `entry` has made today (Pacific date).
func calls_today(entry: Dictionary) -> int:
	_roll_day()
	return int((_settings().vision_usage.counts as Dictionary).get(str(entry.get("id", "")), 0))

func calls_left(entry: Dictionary) -> bool:
	var daily := int(entry.get("daily", 0))
	return daily <= 0 or calls_today(entry) < daily

func _count(entry: Dictionary) -> void:
	_roll_day()
	var settings := _settings()
	var counts: Dictionary = settings.vision_usage.counts
	var id := str(entry.get("id", ""))
	counts[id] = int(counts.get(id, 0)) + 1
	settings.save()

func _roll_day() -> void:
	var usage: Dictionary = _settings().vision_usage
	var today := pacific_date(Time.get_unix_time_from_system())
	if str(usage.get("date", "")) != today:
		usage.date = today
		usage.counts = {}

## The date in California for a Unix time ("2026-11-02").
static func pacific_date(unix: float) -> String:
	return Time.get_date_string_from_unix_time(int(unix) + pacific_offset(unix))

## Seconds from UTC to Pacific time: -7 h from the second Sunday of March (2:00) to the first
## Sunday of November (2:00), -8 h otherwise (the US rule since 2007).
static func pacific_offset(unix: float) -> int:
	var year := int(Time.get_datetime_dict_from_unix_time(int(unix) - 8 * 3600).year)
	var summer_from := _sunday(year, 3, 2) + 10 * 3600
	var summer_to := _sunday(year, 11, 1) + 9 * 3600
	return -7 * 3600 if unix >= summer_from and unix < summer_to else -8 * 3600

## Seconds until the counts start again (the next Pacific midnight).
static func seconds_to_reset(unix: float) -> int:
	var local := int(unix) + pacific_offset(unix)
	return 86400 - posmod(local, 86400)

## 00:00 UTC on the nth Sunday of a month.
static func _sunday(year: int, month: int, nth: int) -> int:
	var first := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var weekday := int(Time.get_datetime_dict_from_unix_time(first).weekday)
	return first + ((7 - weekday) % 7 + 7 * (nth - 1)) * 86400

# --- which API ----------------------------------------------------------------------------------

func best_index() -> int:
	var list := apis()
	for i in list.size():
		if bool((list[i] as Dictionary).get("best", false)): return i
	return -1

## Indexes to try for the next call: whose turn it is, then the best one as the backup.
func _plan() -> Array[int]:
	var list := apis()
	var out: Array[int] = []
	if list.is_empty(): return out
	var settings := _settings()
	var best := best_index()
	var first := -1
	var start := posmod(int(settings.vision.next), list.size()) if str(settings.vision.order) == "turns" else 0
	for step in list.size():
		var i := (start + step) % list.size()
		var entry: Dictionary = list[i]
		if i == best and not bool(entry.get("best_turns", true)): continue
		if calls_left(entry) and connection(entry).has("model"):
			first = i
			break
	if first >= 0: out.append(first)
	if best >= 0 and best != first and calls_left(list[best]) and connection(list[best]).has("model"): out.append(best)
	return out

## The LLM settings for one API (world/ai/llm_client.gd configure), or {"error": why}. Without
## `need_model` a missing model is no error (listing the models it offers).
func connection(entry: Dictionary, need_model := true) -> Dictionary:
	var section: Dictionary = {}
	match str(entry.get("source", "own")):
		"dialogue":
			var director: Node = get_tree().get_first_node_in_group("conversation_director") if is_inside_tree() else null
			var config: Variant = director.get("config") if director != null else null
			if not config is RefCounted: return {"error": "The game's dialogue settings are not loaded yet."}
			section = ((config as RefCounted).call("section", "llm") as Dictionary).duplicate()
		"preset":
			var profiles: RefCounted = PROFILES.new()
			profiles.call("open")
			var preset := str(entry.get("preset", ""))
			if preset.is_empty() or not preset in (profiles.call("names") as Array): return {"error": "Pick a saved preset."}
			section = profiles.call("get_profile", preset)
		_:
			var provider := str(entry.get("provider", "gemini"))
			if provider not in PROVIDERS: provider = "gemini"
			var url := str(entry.get("base_url", "")).strip_edges()
			if url.is_empty(): url = str(DEFAULT_URLS[provider])
			if url.is_empty(): return {"error": "Type the address (base URL) of the OpenAI-compatible server."}
			section = {"provider": provider, "base_url": url, "api_key": str(entry.get("api_key", "")).strip_edges()}
	var model := str(entry.get("model", "")).strip_edges()
	if not model.is_empty(): section.model = model
	if str(section.get("base_url", "")).is_empty(): return {"error": "That source has no address set."}
	if need_model and str(section.get("model", "")).is_empty(): return {"error": "Pick or type the model to use."}
	section.max_tokens = OUTPUT_TOKENS
	section.timeout = TIMEOUT
	section.temperature = 0.4
	section.generation_overrides = {}
	return section

# --- calls --------------------------------------------------------------------------------------

## Describes `image` (a frame of `title`, with the latest subtitle lines for names). `done(text,
## error)` is called once; false when nothing could be sent (off, no calls left, already busy).
func describe(image: Image, title: String, lines: Array, done: Callable, web := false) -> bool:
	if _busy or image == null or not enabled(): return false
	var plan := _plan()
	if plan.is_empty(): return false
	var jpeg := encode(image)
	if jpeg.is_empty(): return false
	var settings := _settings()
	if str(settings.vision.order) == "turns": settings.vision.next = (plan[0] + 1) % apis().size()
	_try(plan, 0, jpeg, ("A screenshot of %s. Describe it." % title) if web else _ask(title, lines), done, WEB_SYSTEM if web else DESCRIBE_SYSTEM)
	return true

## One call to API `index` with a tiny picture or the frame given (TV menu "Test").
func test(index: int, image: Image, done: Callable) -> bool:
	var list := apis()
	if _busy or index < 0 or index >= list.size(): return false
	if image == null:
		image = Image.create(64, 48, false, Image.FORMAT_RGB8)
		image.fill(Color(0.85, 0.35, 0.6))
	var plan: Array[int] = [index]
	_try(plan, 0, encode(image), "This is a connection test. Say in a few words what you see.", done, DESCRIBE_SYSTEM)
	return true

func _try(plan: Array[int], step: int, jpeg: String, ask: String, done: Callable, system: String) -> void:
	var entry: Dictionary = apis()[plan[step]]
	var section := connection(entry)
	var label := str(entry.get("name", "vision"))
	if section.has("error"):
		_failed(plan, step, jpeg, ask, done, system, label, str(section.error))
		return
	_llm.configure(section)
	_busy = true
	_count(entry)
	var answer := func(text: String, error: String) -> void:
		_busy = false
		if error.is_empty() and not text.strip_edges().is_empty():
			print("[watch_party] picture: described by %s (%d today)" % [label, calls_today(entry)])
			done.call(text.strip_edges(), "")
		else:
			_failed(plan, step, jpeg, ask, done, system, label, error if not error.is_empty() else "empty reply")
	if not _llm.call("complete_limited", system, [{"role": "user", "content": ask}], answer,
			{"image_jpeg": jpeg, "output_tokens": OUTPUT_TOKENS, "reasoning_room": REASONING_ROOM, "max_attempts": 1, "purpose": "watch_vision"}):
		_busy = false
		_failed(plan, step, jpeg, ask, done, system, label, "busy")

func _failed(plan: Array[int], step: int, jpeg: String, ask: String, done: Callable, system: String, label: String, error: String) -> void:
	if step + 1 < plan.size():
		print("[watch_party] picture: %s failed (%s); trying %s" % [label, error.left(120), str((apis()[plan[step + 1]] as Dictionary).get("name", "the best one"))])
		_try(plan, step + 1, jpeg, ask, done, system)
		return
	print("[watch_party] picture: %s failed (%s)" % [label, error.left(120)])
	done.call("", error)

static func _ask(title: String, lines: Array) -> String:
	var text := "A still from %s." % title
	var recent := lines.slice(maxi(0, lines.size() - RECENT_LINES))
	if not recent.is_empty():
		var quoted := PackedStringArray()
		for line: Variant in recent: quoted.append("\"%s\"" % str((line as Array)[1]).replace("\n", " ").strip_edges())
		text += " The last lines of dialogue before it (for names only):\n" + "\n".join(quoted)
	return text + "\nDescribe this still."

## A base64 JPEG no larger than MAX_SIDE (a copy: the frame on screen is left alone).
static func encode(image: Image) -> String:
	if image == null or image.is_empty(): return ""
	var copy := image.duplicate() as Image
	if copy.get_format() != Image.FORMAT_RGB8: copy.convert(Image.FORMAT_RGB8)
	var longest := maxi(copy.get_width(), copy.get_height())
	if longest > MAX_SIDE:
		var scale := float(MAX_SIDE) / float(longest)
		copy.resize(roundi(copy.get_width() * scale), roundi(copy.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var bytes := copy.save_jpg_to_buffer(0.85)
	return Marshalls.raw_to_base64(bytes) if not bytes.is_empty() else ""

static func new_id() -> String:
	return "api_%08x" % (randi() & 0x7fffffff)
