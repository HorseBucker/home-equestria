extends CanvasLayer
## Once per world, a card at the top of the view hinting that the televisions are out there (dev
## 2026-11-06: a player who just installed the mod would look for them at the market and find
## nothing the first day). Kept vague on purpose: who knows something, where exactly, and who can
## make them work are for the player to find (Settings → Watch Party has the spoilers). Shown when
## the story has begun in a world (finds.gd first_day) where Anon has no set yet, for READ_SECONDS,
## then it fades. Not before the game's opening is over and he has walked outside (playtest
## 2026-11-07: it came up during the forest tutorial): Twilight has teleported him to Golden Oak
## Library, or the opening was skipped and he woke there, or the world was past it already
## (world/life/arrival_story.gd), and then he stands out of every house, free to move, for
## SETTLE_SECONDS. Kept in the world save (finds.gd state: welcomed). Desktop: a card at the top of the screen; VR: the same
## words on a card in front of the headset view (vr_notice.gd).

const FINDS := preload("res://mods/watch_party/finds.gd")
const STYLE := preload("res://world/ui/menu_style.gd")
const VR_NOTICE := preload("res://mods/watch_party/vr_notice.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const TITLE := "Something from your world"
const IN_FOREST := "Some things from your world are lying somewhere in the Everfree, free for whoever finds them first. A couple of ponies near the forest might know something. Wait too long and somepony else will find them and want bits for them."
const AT_MARKET := "A few things from your world turned up in the Everfree, and somepony found them before you did. Perhaps they're for sale somewhere in town."
const READ_SECONDS := 20.0
const FADE_SECONDS := 2.0
## This long outdoors, free to move, before it shows.
const SETTLE_SECONDS := 3.0
const CHECK_SECONDS := 1.0

var _check := 0.0
var _settled := 0.0
var _shown_for := -1.0
var _panel: PanelContainer
var _text: Label
var _vr: Node3D

func _ready() -> void:
	layer = 16
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.offset_left = -330; _panel.offset_right = 330; _panel.offset_top = 70
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme = STYLE.theme()
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.08, 0.06, 0.12, 0.86); style.set_corner_radius_all(12)
	style.border_color = Color(1, 1, 1, 0.12); style.set_border_width_all(1)
	for side: String in ["left", "right"]: style.set("content_margin_" + side, 20)
	for side: String in ["top", "bottom"]: style.set("content_margin_" + side, 14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	var heading := Label.new(); heading.text = TITLE; heading.theme_type_variation = "Subheading"
	column.add_child(heading)
	_text = Label.new(); _text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(620, 0)
	column.add_child(_text)
	visible = false

## A new world: it may show again there (once).
func world() -> void:
	_settled = 0.0
	_shown_for = -1.0
	visible = false
	if is_instance_valid(_vr): _vr.queue_free()
	_vr = null

func _exit_tree() -> void:
	if is_instance_valid(_vr): _vr.queue_free()

func _process(delta: float) -> void:
	if _shown_for >= 0.0:
		_shown_for += delta
		_panel.modulate.a = clampf((READ_SECONDS + FADE_SECONDS - _shown_for) / FADE_SECONDS, 0.0, 1.0)
		if _shown_for >= READ_SECONDS + FADE_SECONDS:
			visible = false
			_shown_for = -1.0
		return
	_check -= delta
	if _check > 0.0: return
	_check = CHECK_SECONDS
	var data := FINDS.state()
	if not data.has("first_day") or bool(data.get("welcomed", false)): return
	var game: Node = Mods.game
	var inventory: Node = game.get("inventory") as Node if is_instance_valid(game) else null
	if inventory == null: return
	# A world with a set already (or one found or bought since) needs no telling.
	var any_had := FINDS.TVS.any(func(id: String) -> bool: return FINDS.had(id))
	if any_had or not FINDS.owned(inventory).filter(func(id: Variant) -> bool: return id in FINDS.TVS).is_empty():
		data.welcomed = true
		FINDS.changed()
		return
	var body: Variant = inventory.get("player_body")
	var free: bool = is_instance_valid(body) and not bool((body as Node).get("controls_locked")) and not get_tree().paused \
			and _opening_over(game) and _outdoors(game)
	_settled = _settled + CHECK_SECONDS if free else 0.0
	if _settled < SETTLE_SECONDS: return
	data.welcomed = true
	FINDS.changed()
	var said := words()
	if bool(inventory.get("_desktop")):
		_text.text = said
		_panel.modulate.a = 1.0
		visible = true
		_shown_for = 0.0
	else:
		var camera: Variant = inventory.get("camera")
		if not camera is Camera3D: return
		_vr = VR_NOTICE.new()
		_vr.call("setup", camera, 0.02)
		_vr.call("show_text", TITLE, said, READ_SECONDS)
		get_tree().create_timer(READ_SECONDS + FADE_SECONDS + 1.0).timeout.connect(func() -> void:
			if is_instance_valid(_vr): _vr.queue_free())
	print("[watch_party] welcome card shown (%s)" % ("desktop" if bool(inventory.get("_desktop")) else "VR"))

## The game's opening has handed Anon over to Ponyville: Twilight's teleport is done (or the opening
## was skipped, which sets the same flag), or the world is past the opening altogether.
static func _opening_over(game: Node) -> bool:
	var arrival: Variant = game.get("arrival")
	if not arrival is Node or not is_instance_valid(arrival): return true
	var data: Variant = (arrival as Node).get("data")
	if not data is Dictionary: return true
	return str((data as Dictionary).get("stage", "done")) == "done" or bool((data as Dictionary).get("teleported", false))

## Anon is out of every house, measured as the game does it (arrival_story.gd _feet: the floor
## from his body, the place from his eyes).
func _outdoors(game: Node) -> bool:
	var player: Variant = game.get("player")
	if not player is Node3D or not game.has_method("_find_camera"): return true
	var camera: Variant = game.call("_find_camera", player)
	var body: Node3D = player as Node3D
	if bool(game.get("xr_active")) and (player as Node).has_node("Body"): body = (player as Node).get_node("Body") as Node3D
	if not camera is Node3D or body == null: return true
	var eye := (camera as Node3D).global_position
	return HOUSE.at(get_tree(), Vector3(eye.x, body.global_position.y, eye.z)) == null

static func words() -> String:
	var in_forest := FINDS.TVS.any(func(id: String) -> bool: return FINDS.in_forest(id))
	return IN_FOREST if in_forest else AT_MARKET
