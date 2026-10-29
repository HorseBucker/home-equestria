extends RefCounted
## The craft half of a letter's hidden score (Animal Crossing style, dev 2026-10-29), by fixed
## rules: greeting, sign-off, length, no word spam, sentence punctuation and the stationery. The
## heart half is the recipient's own judgement (letter_post.gd). Never shown to the player.
## Parts and points: docs/LETTERS_PLAN_2026_10_29.md section 5.
const LETTER_TEXT := preload("res://world/letters/letter_text.gd")
const POINTS := {"greeting": 15, "sign_off": 15, "length": 25, "no_spam": 15, "punctuation": 15, "stationery": 15}
## Fallback for stationery.gd BONUS (PAPER owns the kinds).
const STATIONERY_BONUS := {"plain": 0, "cream": 5, "floral": 10, "hearts": 15}
const STATIONERY_SCRIPT := "res://world/letters/stationery.gd"
## A repeated content word counts at most this often towards the length.
const LENGTH_REPEATS := 3
const SPAM_SHARE := 0.12
const SPAM_FAULT := 5
const STOPWORDS := ["a", "an", "the", "and", "or", "but", "so", "if", "of", "to", "in", "on", "at", "by", "for", "with",
	"from", "about", "as", "is", "am", "are", "was", "were", "be", "been", "it", "its", "it's", "i", "i'm", "me", "my", "you",
	"your", "you're", "we", "our", "us", "he", "she", "her", "him", "his", "they", "them", "that", "this", "there", "then",
	"than", "not", "no", "do", "did", "have", "has", "had", "will", "would", "can", "could", "just", "really", "very",
	"what", "when", "how", "all", "too", "up", "out", "what's", "that's", "i'll", "i've", "don't", "can't"]

## {"score": int, "parts": {part: points}}; `recipient_name` is the display name the greeting
## resolved to ("" when the greeting names nopony Derpy knows).
static func craft(text: String, recipient_name: String, stationery: String) -> Dictionary:
	var clean: String = LETTER_TEXT.clean(text)
	var greeting: String = LETTER_TEXT.greeting_name(text)
	var closing: Dictionary = LETTER_TEXT.sign_off(text)
	var body := body_text(clean, not greeting.is_empty(), bool(closing.get("found", false)))
	var words: PackedStringArray = LETTER_TEXT.words(body)
	var parts := {
		"greeting": 0 if greeting.is_empty() else (POINTS.greeting if not recipient_name.is_empty() else 5),
		"sign_off": 0 if not bool(closing.get("found", false)) else (POINTS.sign_off if not str(closing.get("name", "")).is_empty() else 8),
		"length": _length_points(_effective_length(words)),
		"no_spam": _spam_points(body, words),
		"punctuation": _punctuation_points(body),
		"stationery": stationery_bonus(stationery)}
	var total := 0
	for key: String in parts: total += int(parts[key])
	return {"score": clampi(total, 0, 100), "parts": parts}

## Total = 40% craft + 60% heart (section 5).
static func total(craft_score: int, heart: int) -> int:
	return clampi(roundi(0.4 * craft_score + 0.6 * heart), 0, 100)

## Without AI her heart follows the craft, kept off the extremes. The top (90) lets a craft-85
## letter reach the 85 total that the warmest friendship step, a gift and good gossip need.
static func fallback_heart(craft_score: int) -> int:
	return clampi(craft_score, 20, 90)

## Friendship change for a total score (rude letters cost).
static func friendship_for(score: int) -> int:
	if score >= 85: return 3
	if score >= 70: return 2
	if score >= 50: return 1
	if score >= 30: return 0
	if score >= 15: return -1
	return -2

static func stationery_bonus(kind: String) -> int:
	var bonus: Dictionary = STATIONERY_BONUS
	if ResourceLoader.exists(STATIONERY_SCRIPT):
		var script: Script = load(STATIONERY_SCRIPT)
		var constants: Dictionary = script.get_script_constant_map() if script != null else {}
		if constants.get("BONUS") is Dictionary: bonus = constants.BONUS
	return clampi(int(bonus.get(kind, 0)), 0, POINTS.stationery)

## The letter without its greeting line and its sign-off lines (closing and name).
static func body_text(clean: String, has_greeting: bool, has_sign_off: bool) -> String:
	var lines: Array = []
	for line: String in clean.split("\n"):
		if not line.strip_edges().is_empty(): lines.append(line.strip_edges())
	if has_greeting and not lines.is_empty(): lines.pop_front()
	# "Love,\nAnon" or "Love, Anon": a short last line, and the closing line above a bare name.
	if has_sign_off and not lines.is_empty() and str(lines[-1]).split(" ", false).size() <= 6:
		var last: String = lines.pop_back()
		if not last.ends_with(",") and not lines.is_empty() and str(lines[-1]).ends_with(",") and str(lines[-1]).split(" ", false).size() <= 3:
			lines.pop_back()
	return "\n".join(lines)

static func _effective_length(words: PackedStringArray) -> int:
	var counts := {}
	var length := 0
	for word: String in words:
		counts[word] = int(counts.get(word, 0)) + 1
		if word in STOPWORDS or int(counts[word]) <= LENGTH_REPEATS: length += 1
	return length

static func _length_points(count: int) -> int:
	if count >= 40 and count <= 200: return POINTS.length
	if (count >= 20 and count <= 39) or (count >= 201 and count <= 350): return 15
	if count >= 8 and count <= 19: return 6
	return 0

static func _spam_points(body: String, words: PackedStringArray) -> int:
	if words.size() < 3: return 0
	var faults := 0
	var counts := {}
	var top := 0
	var run := 1
	for i in words.size():
		var word: String = words[i]
		if i > 0: run = run + 1 if word == words[i - 1] else 1
		if run == 3: faults += 1
		if word in STOPWORDS: continue
		counts[word] = int(counts.get(word, 0)) + 1
		top = maxi(top, int(counts[word]))
	var share := float(top) / float(words.size())
	if top >= 3 and share > SPAM_SHARE: faults += 2 if share > 0.4 else 1
	var seen := {}
	for line: String in body.split("\n"):
		var key := " ".join(LETTER_TEXT.words(line))
		if key.is_empty(): continue
		if seen.has(key):
			faults += 1; break
		seen[key] = true
	return maxi(0, POINTS.no_spam - SPAM_FAULT * faults)

static func _punctuation_points(body: String) -> int:
	var sentences: PackedStringArray = LETTER_TEXT.sentences(body)
	if sentences.is_empty(): return 0
	var good := 0
	for sentence: String in sentences:
		var s := sentence.strip_edges()
		if s.is_empty(): continue
		var first := ""
		for c: String in s:
			if c.to_lower() != c.to_upper():
				first = c; break
		var starts := not first.is_empty() and first == first.to_upper()
		var closed := s.ends_with(".") or s.ends_with("!") or s.ends_with("?") or (s.ends_with("\"") and s.length() > 1 and s[s.length() - 2] in ".!?")
		if starts and closed: good += 1
	return roundi(POINTS.punctuation * float(good) / float(sentences.size()))
