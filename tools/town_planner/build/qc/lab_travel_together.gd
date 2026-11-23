extends SceneTree
## director_group.gd _travel_together on the two 2026-11-22 play-test exchanges (no game: a stand-in host and contexts).
## Prints TOGETHER lines. Run: godot --headless --script res://tools/town_planner/build/qc/lab_travel_together.gd

class FakeGroup:
	var members: Array = []

class FakeHost extends Node:
	var group := FakeGroup.new()
	func _now() -> float: return 0.0

func _init() -> void:
	var places := ["landmark:fountain_01", "landmark:hayburger", "landmark:town_hall"]
	var labels := {"landmark:fountain_01": "Town Square fountain", "landmark:hayburger": "Hayburger", "landmark:town_hall": "Town Hall"}
	var host := FakeHost.new()
	var group: RefCounted = (load("res://world/ai/director_group.gd") as GDScript).new(host)
	for case: Array in [
		[["aloe", "flitter"], [
			{"speaker_id": "flitter", "speech": "Should we tell him he can show it off at the spa?", "actions": []},
			{"speaker_id": "aloe", "speech": "Come, let us walk on toward the fountain.", "actions": [{"id": "a", "type": "go_to", "location_id": "landmark:fountain_01", "pace": "walk"}]}]],
		[["fluttershy", "big_mcintosh"], [
			{"speaker_id": "fluttershy", "speech": "Um, would you maybe want to walk to Hayburger? Only if you're hungry, of course...", "actions": []},
			{"speaker_id": "big_mcintosh", "speech": "Could eat. After you.", "actions": [{"id": "b", "type": "follow", "target_id": "fluttershy"}]}]],
		[["aloe", "lotus"], [
			{"speaker_id": "aloe", "speech": "Let's go to the fountain.", "actions": [{"id": "c", "type": "go_to", "location_id": "landmark:fountain_01", "pace": "walk"}]},
			{"speaker_id": "lotus", "speech": "Maybe later, I'll pass for now.", "actions": []}]]]:
		host.group.members = case[0]
		var contexts := {}
		for id: String in case[0]: contexts[id] = {"locations": places, "place_labels": labels}
		var beats: Array = case[1]
		group.call("_travel_together", beats, contexts, 1)
		for beat: Dictionary in beats:
			print("TOGETHER %s%s %s" % ["(silent) " if beat.get("silent_travel", false) else "", beat.speaker_id, JSON.stringify(beat.actions)])
		print("TOGETHER arrivals to watch: ", group.get("_arrivals"))
		print("TOGETHER --")
	quit()
