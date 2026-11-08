extends "res://world/ui/interaction_hints.gd"
## Watch Party: a television lying in the Everfree is free (ext/market.gd prices it at nothing), so
## its prompt says "Pick up", not "Buy · 0 bits". Every other good's prompt is the game's own.
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_FOREST := "watch_party:forest:"

func _item_hint(item: Node3D, control: String, point: Vector3) -> Dictionary:
	var hint: Dictionary = super(item, control, point)
	var shelf: Variant = item.get_meta("shop_display") if item.has_meta("shop_display") else null
	if not is_instance_valid(shelf) or not str((shelf as Node).get("display_id")).begins_with(WATCH_PARTY_FOREST): return hint
	var store: Variant = inventory.get("inventory") if is_instance_valid(inventory) else null
	var bits := int((store as Object).get("bits")) if store is Object else 0
	var word := "Buy · " + CURRENCY.amount(0) + "\nBalance " + CURRENCY.amount(bits)
	if hint.has("text"): hint.text = str(hint.text).replace(word, "Pick up")
	return hint
