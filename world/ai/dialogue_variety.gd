extends RefCounted
## One bounded rewrite for repeated stylistic habits, based on speech that actually played.
const PET_NAMES := ["darling", "sugarcube", "dear", "sweetie", "honey"]
const PET_REASON := "Repeated term of address: "
## A pet name used as a term of address: set off by a comma or opening a sentence ("thank you,
## darling." / "Darling, you ..."). "A darling filly", "Sweetie Belle" and "honey cakes" are not.
const VOCATIVE_AFTER := "(?i),\\s*(?:my\\s+)?%s\\b(?=\\s*(?:[,.!?;:\\[]|\u2026|$))"
const VOCATIVE_OPENING := "(?i)(^|[.!?\u2026]\\s+|\\]\\s*)(?:my\\s+)?%s\\s*[,!]\\s*(\\p{L})"

static func _regex(pattern: String, pet: String) -> RegEx:
	return RegEx.create_from_string(pattern % pet)

static func vocative(text: String, pet: String) -> bool:
	return _regex(VOCATIVE_AFTER, pet).search(text) != null or _regex(VOCATIVE_OPENING, pet).search(text) != null

## The reply without its repeated term of address, or "" when the reason is something else or the
## pet name cannot be removed cleanly (the caller then asks the model to revise, as before).
static func local_fix(text: String, why: String) -> String:
	if not why.begins_with(PET_REASON): return ""
	var pet := why.trim_prefix(PET_REASON).strip_edges()
	if pet not in PET_NAMES: return ""
	var fixed := _regex(VOCATIVE_AFTER, pet).sub(text, "", true)
	var opening := _regex(VOCATIVE_OPENING, pet)
	var found := opening.search(fixed)
	while found != null:
		fixed = fixed.left(found.get_start()) + found.get_string(1) + found.get_string(2).to_upper() + fixed.substr(found.get_end())
		found = opening.search(fixed)
	return fixed.strip_edges() if fixed != text and not vocative(fixed, pet) else ""

static func words(text: String) -> PackedStringArray:
	var regex := RegEx.new()
	regex.compile("[^\\p{L}\\p{N}']+")
	return regex.sub(text.to_lower().replace("’", "'"), " ", true).strip_edges().split(" ", false)


## Stock lines every pony fell back on (dev 2026-10-22: "every pony when they sit down with another
## is like 'my hooves are tired.' 'agreed! let us sit down and commence.'"). Matched on the spoken
## words; a hit sends the one bounded rewrite like any other repeat.
const STOCK := ["(?i)\\bmy (?:poor |tired |aching )?hooves (?:are|feel) (?:so |really )?(?:tired|aching|sore|killing me)",
	"(?i)^\\W*(?:agreed|indeed|obviously|quite so)\\W*$", "(?i)^\\W*agreed[!.,]", "(?i)\\blet us (?:sit|rest|commence|begin)\\b",
	"(?i)\\b(?:shall we|let's) (?:sit|rest) (?:down )?(?:here|for a (?:bit|while|spell))\\b"]
static var _stock: Array[RegEx] = []

static func stock(text: String) -> String:
	if _stock.is_empty():
		for pattern in STOCK: _stock.append(RegEx.create_from_string(pattern))
	for regex in _stock:
		var found := regex.search(text.strip_edges())
		if found != null: return found.get_string().strip_edges()
	return ""


static func reason(candidate: String, spoken: Array, player_text := "") -> String:
	var tokens := words(candidate)
	if tokens.is_empty(): return ""
	var cliche := stock(candidate)
	if cliche != "": return "Stock line \"%s\"; say something real instead" % cliche
	var recent := spoken.slice(maxi(0, spoken.size() - 6))
	var quoted := words(player_text)
	# Detect repeated clauses inside a single generated reply too.
	var phrases := {}
	for i in maxi(0,tokens.size()-5):
		var phrase := " ".join(tokens.slice(i,i+6))
		if phrases.has(phrase): return "Repeated six-word clause within the reply"
		phrases[phrase]=true
	for pet: String in PET_NAMES:
		if pet not in tokens or pet in quoted or not vocative(candidate, pet): continue
		for line in recent.slice(maxi(0, recent.size() - 3)):
			if pet in words(str(line)): return PET_REASON + pet
	for line in recent:
		var previous := words(str(line))
		if tokens.size() >= 4 and tokens == previous: return "Repeated complete sentence"
		if previous.size() >= 8 and tokens.size() >= 8:
			var shared := 0
			for i in tokens.size()-5:
				if " ".join(tokens.slice(i,i+6)) in " ".join(previous): shared+=1
			if float(shared)/maxi(1,tokens.size()-5) > .65: return "Reply closely recycles recent wording"
	# A repeated opening is a habit only after two prior uses, not any shared word.
	if tokens.size() >= 3:
		var opener := " ".join(tokens.slice(0, 3))
		var count := 0
		for line in recent:
			var previous := words(str(line))
			if previous.size() >= 3 and " ".join(previous.slice(0, 3)) == opener: count += 1
		if count >= 2: return "Repeated three-word opening: " + opener
	return ""


## Fixation guard (player thread report 2026-10-29: Twilight spent ~30 of 286 lines on her
## one-sentence letter, Dash answered every kiss with "loser carries the pears"). reason() above only
## rewrites one draft against her last six lines; this looks at her newest completed reply against her
## last FIXATION_WINDOW and returns one short note for her NEXT request, or "". It clears itself once
## her newest line moves on, and words Anon just said are exempt (he brought the topic up).
const FIXATION_WINDOW := 20
const TOPIC_WINDOW := 6
const FIXATION_NOTE := "You have said this several times already (%s); let it go and talk about something else unless Anon brings it up."
const STOP_WORDS := "the and but for nor yet you your yours she her hers him his they them their its it's this that these those what which who whom whose when where why how was were are been being have has had having does did doing done can could would should will shall may might must not don't can't won't isn't aren't wasn't didn't doesn't couldn't wouldn't shouldn't i'm i'll i've i'd you're you'll you've we're we'll we've they're that's there's here's what's let's with without from into onto about above after again against all also any anything because before below between both each even ever every few just more most much now off once only other our out over own same some something such than then there too under until very well yeah yes okay oh ugh hmm um ah wow hey anon everypony somepony anypony nopony pony ponies myself yourself herself himself ourselves really still maybe sure right little lot bit way thing things time day today tonight tomorrow one two three first last next back get got going come came make made see saw say said tell told think thought know knew want like look need feel try take give keep let put good great nice fine kind sort"
static var _stop := {}
static var _word_regex: RegEx
static var _tag_regex: RegEx

## Each word of a line: [raw lowercase words, content keys ("" for stop words, short words and names)].
## A capitalised word not opening a sentence counts as a name ("Princess Celestia", "Rarity's").
static func _tokens(text: String, exempt: Dictionary) -> Array:
	if _stop.is_empty():
		for word in STOP_WORDS.split(" ", false): _stop[word] = true
		_word_regex = RegEx.create_from_string("[\\p{L}\\p{N}']+")
		_tag_regex = RegEx.create_from_string("\\[[^\\]]*\\]")
	var clean := _tag_regex.sub(text.replace("’", "'"), " ", true)
	var raw := PackedStringArray()
	var keys := PackedStringArray()
	for found: RegExMatch in _word_regex.search_all(clean):
		var token := found.get_string().strip_edges().trim_prefix("'").trim_suffix("'")
		if token.is_empty(): continue
		var lower := token.to_lower()
		var before := clean.left(found.get_start()).strip_edges()
		var opening := before.is_empty() or before.right(1) in [".", "!", "?", "…"]
		var name := not opening and token.left(1) != token.left(1).to_lower() and not lower.begins_with("i'") and lower != "i"
		raw.append(lower)
		var key := lower.trim_suffix("'s")
		if key.length() > 4 and key.ends_with("s") and not key.ends_with("ss"): key = key.left(-1)
		if name or key.length() < 3 or _stop.has(lower) or _stop.has(key) or exempt.has(key): key = ""
		keys.append(key)
	return [raw, keys]

## The note for her next turn, or "". `spoken` is her own completed replies, oldest first. Triggers:
## the newest reply shares a distinctive four-word phrase (3+ content words) with an earlier one, or
## most of its content words; or its topic words keep recurring in her last TOPIC_WINDOW lines (one word
## in four lines, or two words each in three).
static func fixation_note(spoken: Array, player_text := "") -> String:
	if spoken.size() < 2: return ""
	var lines := spoken.slice(maxi(0, spoken.size() - FIXATION_WINDOW))
	var exempt := {}
	for key: String in _tokens(player_text, {})[1]:
		if key != "": exempt[key] = true
	var newest: Array = _tokens(str(lines[-1]), exempt)
	var raw: PackedStringArray = newest[0]
	var keys: PackedStringArray = newest[1]
	var mine := {}   # content key -> the word as she said it, in line order
	for i in keys.size():
		if keys[i] != "" and not mine.has(keys[i]): mine[keys[i]] = raw[i].trim_suffix("'s")
	if mine.is_empty(): return ""
	var phrases: PackedStringArray = []
	for i in raw.size() - 3:
		var content := 0
		for j in 4:
			if keys[i + j] != "": content += 1
		if content >= 3: phrases.append(" ".join(raw.slice(i, i + 4)))
	var counts := {}
	for index in lines.size() - 1:
		var earlier: Array = _tokens(str(lines[index]), exempt)
		var joined := " %s " % " ".join(earlier[0])
		for phrase in phrases:
			if (" %s " % phrase) in joined: return FIXATION_NOTE % phrase
		var theirs := {}
		for key: String in earlier[1]:
			if key != "": theirs[key] = true
		var shared: PackedStringArray = []
		for key: String in mine:
			if theirs.has(key): shared.append(str(mine[key]))
		if shared.size() >= 3 and shared.size() >= 0.6 * mini(mine.size(), theirs.size()): return FIXATION_NOTE % ", ".join(shared.slice(0, 3))
		if index >= lines.size() - TOPIC_WINDOW:
			for key: String in theirs:
				if mine.has(key): counts[key] = int(counts.get(key, 0)) + 1
	var topic: PackedStringArray = []
	var steady: PackedStringArray = []
	for key: String in mine:
		var lines_with := int(counts.get(key, 0)) + 1
		if lines_with >= 3: steady.append(str(mine[key]))
		if lines_with >= 4: topic.append(str(mine[key]))
	if steady.size() >= 2: return FIXATION_NOTE % ", ".join(steady.slice(0, 3))
	if not topic.is_empty(): return FIXATION_NOTE % ", ".join(topic.slice(0, 3))
	return ""
