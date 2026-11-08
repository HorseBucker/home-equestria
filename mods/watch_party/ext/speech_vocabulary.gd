extends "res://world/ai/speech_vocabulary.gd"
## Watch Party: the speech recognizer's word list also names what is on a television near Anon (its
## title and the names said in it lately, res://mods/watch_party/watch_company.gd speech_words),
## after the places and the core cast and before the ponies nearest him (Whisper keeps the end).
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_PATH := "res://world/ai/speech_vocabulary.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/ext_loader.gd")
const WATCH_PARTY_HUB := "Mods/watch_party"

static func prompt(characters: Dictionary, head: Variant, player_name := "") -> String:
	var game: Script = WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH)
	var text := str(game.call("prompt", characters, head, player_name))
	if not is_instance_valid(head) or not head is Node3D or not (head as Node3D).is_inside_tree(): return text
	var hub := (head as Node3D).get_tree().root.get_node_or_null(WATCH_PARTY_HUB)
	var company: Variant = hub.get("company") if hub != null else null
	if not is_instance_valid(company): return text
	var extra: Variant = (company as Node).call("speech_words", head)
	if not extra is Array or (extra as Array).is_empty(): return text
	var words: Array = Array(text.trim_suffix(".").split(", ", false))
	var known: Array = words.map(func(word: Variant) -> String: return str(word).to_lower())
	var core: Variant = game.get("_core")
	var at := mini(words.size(), PROMPT_PLACES.size() + ((core as Array).size() if core is Array else 0))
	for name: Variant in extra:
		var word := str(name).strip_edges()
		if word.is_empty() or word.to_lower() in known: continue
		known.append(word.to_lower())
		words.insert(at, word)
		at += 1
	return ", ".join(PackedStringArray(words)) + "."
