extends Node
## The watch on Anon's wrist (the pause/Tab view): "Day 3 · Wed   14:05" in place of the game's "Day 37   14:05"
## (2026-11-21 play test; world/life/world_days.gd says why and how). The briefcase sets the watch's text itself
## (briefcase_inventory.gd _tell_time, which the Board Games mod ships its own copy of), so this rewrites the text
## after it each frame instead of changing that script. Lives under the root, attached once by town_root.gd.

const NAME := "WatchDay"
const DAYS := preload("res://world/life/world_days.gd")
var _case: WeakRef = weakref(null)

var _wrote := ""


static func attach(town: Node) -> void:
	var root := town.get_tree().root
	if root.get_node_or_null(NAME) != null: return
	var node: Node = (load("res://world/towns/ponyville/watch_day.gd") as GDScript).new()
	node.name = NAME
	root.add_child.call_deferred(node)


func _ready() -> void:
	process_priority = 10000          # after the briefcase's own _process


func _process(_delta: float) -> void:
	var case: Object = _case.get_ref()
	if case == null or not is_instance_valid(case):
		case = null
		for node: Node in get_tree().get_nodes_in_group("interaction_hint_sources"):
			if node.get("_watch") is Label3D: case = node; break
		_case = weakref(case)
		if case == null: return
	var watch: Label3D = case.get("_watch")
	if watch == null: return
	var text := watch.text
	if text == _wrote or not text.begins_with("Day "): return
	var parts := text.split("   ", false)
	var clock: Node = get_node_or_null("/root/TimeOfDay")
	if parts.size() < 2 or clock == null: return
	_wrote = "%s   %s" % [DAYS.label(get_tree(), int(clock.get("day"))), parts[parts.size() - 1]]
	watch.text = _wrote
