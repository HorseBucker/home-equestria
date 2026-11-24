extends RefCounted
## Mods the overhaul carries built in, whose own packs must stand down when installed beside it (2026-11-24 player
## report: "Everypony vanishes and trying to spawn them in gives a navigation error").
##
## modChad's Pathfinding Fix (pathfinding_fix) is folded into the overhaul's own game scripts (walk_grid_service.gd,
## walk_planner.gd, pony_navigator.gd, princess_hybrid.gd, world/buildings/house_ceilings.gd). Its pack, installed as
## well, still starts: its walk_grid_service_fix.gd extends the overhaul's walk_grid_service.gd and declares
## BUDGET_REASON again, which Godot refuses ("The member BUDGET_REASON already exists in parent class"), yet its entry
## node goes on to swap each new zone's WalkGridService onto that broken script, so Ponyville has no walk grid and
## no pony can be placed; and it adds its house ceilings a second time while the town is being built ("Parent node is
## busy setting up children"). So before the town is built (town_root.gd), its entry node is switched off in place:
## its node watcher disconnected and its processing stopped. It is not freed (mods.gd _stop): its _exit_tree undoes
## every house ceiling in the group the overhaul's own ceilings share.

const FOLDED := ["pathfinding_fix"]


static func stand_down(tree: SceneTree) -> void:
	var mods: Node = tree.root.get_node_or_null("Mods")
	if mods == null: return
	for id: String in FOLDED:
		var node: Node = mods.get_node_or_null(NodePath(id))
		if node == null or node.has_meta("overhaul_stood_down"): continue
		for connection: Dictionary in tree.node_added.get_connections():
			var callable: Callable = connection.callable
			if callable.get_object() == node: tree.node_added.disconnect(callable)
		node.set_process(false)
		node.set_physics_process(false)
		node.set_meta("overhaul_stood_down", true)
		print("[overhaul] %s is built into the Ponyville Overhaul: its own pack is switched off (it can be removed)" % id)
