extends "res://world/ai/speech_input.gd"
## Watch Party: T (push to talk) while typing on a television is a letter, not talking (playtest
## 2026-11-07: typing in a page's search box as Trixie spoke, the T cut her off). The game already
## leaves T alone while one of its own text fields has the focus; a field on a TV screen (the page
## or the browser's address bar, in TV mode) is in the screen's own viewport, so the game cannot
## see it: the Watch Party hub says (typing_on_tv). The VR talk button is the game's as ever.
## Applied by the game (mod.json "extends"); see res://mods/watch_party/hooks.gd.

## Marks this script as Watch Party's extension of the game script (hooks.gd).
const WATCH_PARTY_PATH := "res://world/ai/speech_input.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/hooks.gd")

const WATCH_PARTY_HUB := "/root/Mods/watch_party"

func _ptt_pressed() -> bool:
	var hub: Node = get_node_or_null(WATCH_PARTY_HUB)
	if hub == null or not hub.has_method("typing_on_tv") or not bool(hub.call("typing_on_tv")): return super()
	for controller in _controllers:
		if controller != null and is_instance_valid(controller) and controller.has_method("is_button_pressed"):
			if controller.is_button_pressed(vr_button):
				return true
	return false
