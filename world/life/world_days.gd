extends RefCounted
## The player's day counter (2026-11-21 play test: "Why does starting a new game show Day 35? ... whatever day I start
## on should always be day 0"), and the day of the week beside it.
##
## Why Day 35: a new world does not start its clock at 0. The dev put every new world in late summer (title_screen.gd
## _start_new_game, decision D-01, 2026-11-08: "so autumn and winter arrive in the first sessions"): with 20-day
## seasons (spring 0-19, summer 20-39 ...) its clock starts on day 34, the last third of summer, and the watch showed
## the clock's day + 1. The clock's day number itself stays as it is: the seasons, the town's events and the ponies'
## week all run on it.
##
## Here the counter counts from the day the world began: Day 1 on its first day. A world's first day is kept in its
## save (the world context's state, "world_start_day"), found once: a world on day 0 began there; one already past the
## late-summer start began on that start; one in between (an older world, begun before that rule) on day 0.
##
## The week: the game's own (day_planner.gd DAYS, day 0 a Sunday), which decides school days and the ponies' weekly
## schedules, so the watch's "Sat" is a day with no school.

const KEY := "world_start_day"
const SHORT := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


## The day the world began (on the game's clock).
static func start_day(tree: SceneTree, clock_day: int) -> int:
	var seasons: Node = tree.get_first_node_in_group("season_state") if tree != null else null
	var context: Variant = seasons.get("context") if seasons != null else null
	var state: Variant = (context as Object).get("state") if context is Object and is_instance_valid(context) else null
	if state is Dictionary and (state as Dictionary).get(KEY) != null:
		return int((state as Dictionary)[KEY])
	var days := 20
	var settings: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	if settings != null and settings.has_method("season_days"): days = maxi(1, int(settings.call("season_days")))
	var late_summer := days + mini(days - 1, ceili(2.0 * days / 3.0))      # (title_screen.gd late_summer_day)
	var start := late_summer if clock_day >= late_summer else 0
	if state is Dictionary and not bool((context as Object).get("_read_only")):
		(state as Dictionary)[KEY] = start
	return start


## "Day 3 · Wed": the days since the world began (Day 1 its first: 2026-11-22, "it'd make more sense if your first day
## in Ponyville was called day 1, rather than 0"), and the day of the week.
static func label(tree: SceneTree, clock_day: int) -> String:
	return "Day %d · %s" % [maxi(0, clock_day - start_day(tree, clock_day)) + 1, SHORT[posmod(clock_day, SHORT.size())]]
