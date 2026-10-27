extends RefCounted
## Subtitle colours per pony: a pale fill, an outline in her own colour and a dark drop shadow.
## subtitle_colors.json holds a per-character subtitle style sheet for the show (366 characters),
## shared on 2026-10-27 as "designed (and extensively tested) as subtitles colors to work over a
## complex background without the need for the opaque screen behind them". A pony it does not name
## gets the same kind of pair from her coat and mane line. The AI context page's pony cards
## (world/ui/ai_context_page.gd) wear these colours. The bottom caption (world/ui/speech_caption.gd)
## used them too, until it took the colours of the words above her head (2026-10-27).

const DATA := "res://world/ai/subtitle_colors.json"
## Titles left off a name before looking it up ("Princess Luna" is "Luna" there).
const TITLES := ["princess", "prince", "dr", "mayor", "miss", "mrs", "mr", "ms", "nurse", "king", "queen"]
## Derived pairs: how far her coat goes toward white for the fill, and the darkest the outline's
## relative luminance may be before it no longer stands off the fill.
const FILL_LIFT := 0.7
const OUTLINE_LUMINANCE := 0.2

static var _data: Dictionary = {}


## The sheet's colours for a pony id ("twilight_sparkle") or name ("Princess Luna"), {} when the
## sheet does not name her.
static func for_pony(id: String, name := "") -> Dictionary:
	var keys: Array[String] = []
	if not id.is_empty():
		var aliases: Dictionary = _load().get("aliases", {})
		if aliases.has(id): keys.append(str(aliases[id]))
		keys.append(_key(id))
	keys.append(_key(name))
	var words := name.to_lower().replace(".", " ").split(" ", false)
	if words.size() > 1 and words[0] in TITLES: keys.append(_key(" ".join(words.slice(1))))
	for key in keys:
		var found := style(key)
		if not found.is_empty(): return found
	return {}


## The sheet's colours for one style key (its name in lower case, letters and digits only).
static func style(key: String) -> Dictionary:
	var styles: Dictionary = _load().get("styles", {})
	if key.is_empty() or not styles.has(key): return {}
	var entry: Dictionary = styles[key]
	return {"fill": Color(str(entry.get("fill", "#FFFFFF"))), "outline": Color(str(entry.get("outline", "#000000"))),
		"shadow": Color(str(entry.get("shadow", "#000000")))}


## The sheet's kind of pair from a coat and a mane line: the coat most of the way to white, and
## the line saturated and darkened under the fill.
static func derived(coat: Color, line: Color) -> Dictionary:
	var fill := Color(coat.lerp(Color.WHITE, FILL_LIFT), 1.0)
	var outline := Color(line, 1.0)
	if outline.s > 0.12: outline.s = maxf(outline.s, 0.55)
	for i in 20:
		if _luminance(outline) <= OUTLINE_LUMINANCE: break
		outline.v = maxf(0.0, outline.v - 0.05)
	return {"fill": fill, "outline": outline, "shadow": Color.BLACK}


static func _luminance(colour: Color) -> float:
	var linear := colour.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


static func _key(text: String) -> String:
	var key := ""
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"): key += c
	return key


static func _load() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = parsed if parsed is Dictionary else {"styles": {}}
	return _data
