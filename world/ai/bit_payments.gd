extends RefCounted
## Paying ponies (dev 2026-10-28: "pay ponies needs to be a UI thing that causes a prompt letting
## the AI know it has the money now and every pony needs to have a wallet with how many bits they
## have. Models interpreting shit incorrectly can't affect gameplay like that"). Only the Pay panel
## (world/ui/pay_panel.gd) moves bits; the pony's model is told afterwards and never moves any
## itself. Every pony's purse is saved with the world (world_context.state.pony_wallets) and her
## prompt shows what she holds (situation_line).
const SFX := preload("res://world/audio/interaction_sounds.gd")
const STATE_KEY := "pony_wallets"
const MAX_PURSE := 999999

## What a pony carries before Anon ever pays her: 20-200 bits, the same in every world.
static func starting(id: String) -> int:
	return 20 + absi(hash("wallet:" + id)) % 181

static func balance(context: Node, id: String) -> int:
	if not is_instance_valid(context) or id.is_empty(): return 0
	var wallets: Variant = context.state.get(STATE_KEY)
	if not wallets is Dictionary: return starting(id)
	var held: Variant = (wallets as Dictionary).get(id)
	if not (held is int or held is float) or not is_finite(float(held)): return starting(id)
	return clampi(int(held), 0, MAX_PURSE)

## Moves `amount` bits from Anon's purse to pony `id`. Returns "" when paid, else why not.
static func pay(game: Node, pony: Node3D, id: String, amount: int) -> String:
	if not is_instance_valid(game) or id.is_empty(): return "Nobody to pay."
	if amount <= 0: return "Nothing to pay."
	var context: Node = game.get("world_context")
	var store: RefCounted = game.inventory.inventory if is_instance_valid(game.get("inventory")) else null
	if not is_instance_valid(context) or bool(context.get("_read_only")) or store == null: return "Bits cannot change hooves right now."
	if int(store.bits) < amount: return "You only have %d bits." % int(store.bits)
	var before := balance(context, id)
	if before + amount > MAX_PURSE: return "Her purse is full."
	if not store.debit_bits(amount): return str(store.last_error) if not str(store.last_error).is_empty() else "Could not pay."
	if not context.state.get(STATE_KEY) is Dictionary: context.state[STATE_KEY] = {}
	context.state[STATE_KEY][id] = before + amount
	context._changed()
	if is_instance_valid(pony): SFX.play_purchase(pony)
	context.record("payment", "Anon paid %s %d bits." % [id.replace("_", " ").capitalize(), amount], [id, "player"], [id, "player"])
	print("[bits] Anon paid %s %d bits (her purse %d -> %d)" % [id, amount, before, before + amount])
	return ""

## Her purse in her prompt's situation block.
static func situation_line(context: Node, id: String) -> String:
	return "- Your purse holds %d bits (Ponyville's money)." % balance(context, id)
