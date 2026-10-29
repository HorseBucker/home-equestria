extends RefCounted
## Day words and clock times for an agreed meeting (docs/LETTERS_PLAN_2026_10_29.md section 8):
## "tomorrow" + "3:00" on day 12 is day 13 at 15:00. A day is today, tonight, tomorrow or a number
## of days ahead (0-14); a time is 15:00, 15, 3pm, 3:30 pm or noon, and a bare 1-5 means the
## afternoon, and "tonight" / "in the evening" make 8 mean 20:00. A validated day is written back as
## the absolute "day N", so the meeting stays the same day however long until it is booked.
## Meetings fall between 06:00 and 21:00 and at least 20 game minutes from now.
## Pure functions; the clock comes in as arguments so tests can use a fake one.

const EARLIEST := 6.0
const LATEST := 21.0
const MAX_DAYS := 14
const SOONEST_HOURS := 20.0 / 60.0
## Before this hour the calendar day has already turned, but "tomorrow" still means the coming day.
const NIGHT_ENDS := 4.0
const DAY_ERROR := "Say the day as today, tomorrow or a number of days ahead"
const TIME_ERROR := "Pick a time between 06:00 and 21:00"
const PAST_ERROR := "That time has already passed"
const NUMBER_WORDS := {"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
	"eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "a": 1, "a couple of": 2}

## {"ok", "error", "day" (absolute), "hour", "offset", "day_text" ("day N"), "time_text" ("HH:MM")}.
static func parse(day_word: String, time_text: String, clock_day: int, clock_hours: float) -> Dictionary:
	var offset := day_offset(day_word, clock_hours)
	var absolute := RegEx.create_from_string("(?i)^\\s*day\\s*(\\d{1,6})\\s*$").search(day_word)
	if absolute != null:
		offset = int(absolute.get_string(1)) - clock_day
		if offset > MAX_DAYS: offset = -1
	if offset < 0: return {"ok": false, "error": DAY_ERROR}
	var hour := evening(hour_of(time_text), day_word + " " + time_text)
	if hour < EARLIEST or hour > LATEST: return {"ok": false, "error": TIME_ERROR}
	var day := clock_day + offset
	if float(day) + hour / 24.0 - (float(clock_day) + clock_hours / 24.0) < SOONEST_HOURS / 24.0:
		return {"ok": false, "error": PAST_ERROR}
	return {"ok": true, "error": "", "day": day, "hour": hour, "offset": offset, "day_text": "day %d" % day, "time_text": clock_text(hour)}

## Days from today, or -1. "tomorrow" said after midnight (before NIGHT_ENDS) is the coming day.
static func day_offset(word: String, clock_hours := 12.0) -> int:
	var w := word.strip_edges().to_lower().replace("_", " ").replace("-", " ")
	w = w.trim_prefix("in ").trim_prefix("+").trim_suffix(" from now").trim_suffix(" ahead").strip_edges()
	if w in ["today", "tonight", "this morning", "this afternoon", "this evening", "later", "later today"]: return 0
	if w.begins_with("tomorrow"): return 0 if clock_hours < NIGHT_ENDS else 1
	if w in ["day after tomorrow", "the day after tomorrow", "overmorrow"]: return 2 if clock_hours >= NIGHT_ENDS else 1
	for suffix: String in [" days", " day"]:
		if w.ends_with(suffix): w = w.trim_suffix(suffix).strip_edges(); break
	var count := -1
	if w.is_valid_int(): count = int(w)
	elif NUMBER_WORDS.has(w): count = int(NUMBER_WORDS[w])
	return count if count >= 0 and count <= MAX_DAYS else -1

## The hour as a float (15.5 for 3:30 pm), or -1.0 when it cannot be read.
static func hour_of(text: String) -> float:
	var t := text.strip_edges().to_lower().replace("a.m.", "am").replace("p.m.", "pm").replace(".", ":")
	t = t.trim_prefix("at ").replace("o'clock", "").replace("o’clock", "").replace("oclock", "").strip_edges()
	if t in ["noon", "midday", "12 noon"]: return 12.0
	if t == "midnight": return 0.0
	var pm := false
	var am := false
	for word: String in ["in the afternoon", "in the evening", "at night", "tonight"]:
		if t.ends_with(word): pm = true; t = t.trim_suffix(word).strip_edges()
	if t.ends_with("in the morning"): am = true; t = t.trim_suffix("in the morning").strip_edges()
	var found := RegEx.create_from_string("^(\\d{1,2})(?:[:h](\\d{2}))?\\s*(am|pm)?$").search(t.replace(" ", "") if t.length() < 12 else t)
	if found == null: return -1.0
	var h := int(found.get_string(1))
	var m := int(found.get_string(2)) if not found.get_string(2).is_empty() else 0
	var suffix := found.get_string(3)
	if m >= 60 or h > 23: return -1.0
	if suffix == "am" or am:
		if h == 12: h = 0
	elif suffix == "pm" or pm:
		if h < 12: h += 12
	elif h >= 1 and h <= 5:
		h += 12   # "come at 3" means the afternoon
	return float(h) + float(m) / 60.0

## 1:00-11:59 said with tonight, evening or night (and no am or morning) is the evening hour.
static func evening(hour: float, text: String) -> float:
	if hour < 1.0 or hour >= 12.0: return hour
	var lower := text.to_lower()
	if RegEx.create_from_string("(?:\\d\\s*|\\b)(?:am\\b|a\\.m\\.)|\\bmorning\\b").search(lower) != null: return hour
	return hour + 12.0 if RegEx.create_from_string("\\b(tonight|evening|night)\\b").search(lower) != null else hour

static func clock_text(hour: float) -> String:
	var minutes := roundi(hour * 60.0)
	return "%02d:%02d" % [int(minutes / 60.0) % 24, minutes % 60]

## "today", "tomorrow" or "on day N" for a prompt line ("at Town Hall tomorrow at 15:00").
static func day_words(day: int, clock_day: int) -> String:
	if day == clock_day: return "today"
	if day == clock_day + 1: return "tomorrow"
	return "on day %d" % day

## The first day phrase in free text ("show up tomorrow at town hall at 3:00" -> "tomorrow"), or "".
static func find_day(text: String) -> String:
	var found := RegEx.create_from_string("(?i)\\b(the day after tomorrow|today|tonight|tomorrow|in (?:\\d{1,2}|one|two|three|four|five|six|seven|a couple of) days?)\\b").search(text)
	return found.get_string(1).to_lower() if found != null else ""

## The first clock time in free text ("at 3:00", "3pm", "noon", "at 8 in the evening"), or "".
## A bare number counts only after "at" so "in 2 days" is never a time.
static func find_time(text: String) -> String:
	var part := "(?:\\s+(?:in the (?:morning|afternoon|evening)|at night|tonight))?"
	var found := RegEx.create_from_string("(?i)(?:\\bat\\s+(\\d{1,2}(?::\\d{2})?(?:\\s*(?:am|pm|a\\.m\\.|p\\.m\\.|o'?clock))?" + part + ")\\b|\\b(\\d{1,2}:\\d{2}(?:\\s*(?:am|pm))?" + part + "|\\d{1,2}\\s*(?:am|pm|a\\.m\\.|p\\.m\\.|o'?clock)" + part + ")|\\b(noon|midday))").search(text)
	if found == null: return ""
	for group in [1, 2, 3]:
		if not found.get_string(group).is_empty(): return found.get_string(group).strip_edges()
	return ""
