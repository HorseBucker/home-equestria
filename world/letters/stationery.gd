extends RefCounted
## Writing paper (docs/LETTERS_PLAN_2026_10_29.md): four kinds sold in town as shop goods
## "goods:paper-<kind>" (world/shop/shop_items.gd GOODS; prices there are dev's proposals and
## match PRICES here), a few plain sheets given at the start (paper/letter_paper.gd). Fancier
## paper adds a little to a letter's craft score (letter_scoring.gd reads BONUS). PAPER and INK
## colour the sheet the handwriting is drawn on (paper/letter_ink.gd); MOTIF decorates its margin.
const KINDS := ["plain", "cream", "floral", "hearts"]
const NAMES := {"plain": "Plain writing paper", "cream": "Cream writing paper", "floral": "Floral writing paper", "hearts": "Writing paper with hearts"}
const PRICES := {"plain": 2, "cream": 4, "floral": 8, "hearts": 10}
const BONUS := {"plain": 0, "cream": 5, "floral": 10, "hearts": 15}
const PAPER := {"plain": Color("f7f4ec"), "cream": Color("f3e6c8"), "floral": Color("f6efe4"), "hearts": Color("fbeef0")}
const INK := {"plain": Color("27304a"), "cream": Color("3a2a1c"), "floral": Color("2f3d2a"), "hearts": Color("5a1f3a")}
## Margin decoration: "" none, "flowers" or "hearts", in this colour.
const MOTIF := {"plain": ["", Color.BLACK], "cream": ["", Color.BLACK], "floral": ["flowers", Color("d77fa1")], "hearts": ["hearts", Color("e0607e")]}
const QUILL := "goods:quill"
const ITEM_PREFIX := "goods:paper-"

static func valid(kind: String) -> bool:
	return kind in KINDS

## "goods:paper-cream" -> "cream"; "" when the id is not writing paper.
static func of_item(id: String) -> String:
	if not id.begins_with(ITEM_PREFIX): return ""
	var kind := id.substr(ITEM_PREFIX.length())
	return kind if valid(kind) else ""

static func item_id(kind: String) -> String:
	return ITEM_PREFIX + (kind if valid(kind) else "plain")

static func paper(kind: String) -> Color:
	return PAPER.get(kind, PAPER.plain)

static func ink(kind: String) -> Color:
	return INK.get(kind, INK.plain)

static func bonus(kind: String) -> int:
	return int(BONUS.get(kind, 0))
