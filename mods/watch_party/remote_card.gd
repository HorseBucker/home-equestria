extends CanvasLayer
## The remote's card (desktop): in the bottom right corner while the TV remote is in hand, what is
## on and the controls (tv_controls.gd reads them). Shown and fed by tv_controls.gd.

const SET := preload("res://mods/watch_party/tv_set.gd")
const CONTROLS := [["Click", "Play / pause"], ["Hold click", "Power on / off"], ["Right click", "Menu: videos, subtitles, sound"], ["Wheel", "Skip 10 s"],
	["Left / Right", "Previous / next video"], ["Up / Down", "Volume"]]

var _status: Label
var _refresh := 0.0
var _flash_until := 0.0

func _ready() -> void:
	layer = 15
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0; panel.anchor_right = 1.0; panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = -330; panel.offset_right = -20; panel.offset_top = -256; panel.offset_bottom = -20
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN; panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.08, 0.07, 0.06, 0.78); style.set_corner_radius_all(8)
	style.content_margin_left = 14; style.content_margin_right = 14; style.content_margin_top = 10; style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var heading := Label.new(); heading.text = "TV remote"; heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	_status = Label.new(); _status.modulate = Color("f0c674")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _status.custom_minimum_size = Vector2(280, 0)
	column.add_child(_status)
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	for row: Array in CONTROLS:
		var key := Label.new(); key.text = str(row[0]); key.modulate = Color(1, 1, 1, 0.7)
		var does := Label.new(); does.text = str(row[1])
		grid.add_child(key); grid.add_child(does)
	column.add_child(grid)
	visible = false

## What is on at `tv` (null: no set on nearby), at most four times a second.
func show_status(tv: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _flash_until or now < _refresh: return
	_refresh = now + 0.25
	if tv == null:
		_status.text = "No television on nearby"
		return
	var status: Dictionary = tv.call("status")
	var state := str(status.get("state", "idle"))
	if state in ["idle", "ended"]:
		_status.text = "Off: click or hold to turn on"
		return
	var line := ("Paused: " if state == "paused" else "") + str(status.get("title", ""))
	var volume := "vol " + ("muted" if float(status.get("volume_db", 0.0)) <= -80.0 else str(roundi(float(status.get("volume_db", 0.0)))))
	# Only a video has a time to show (a page's position is just how long the browser is open).
	var mode := str(status.get("mode", ""))
	if mode == "web" or mode == "slides":
		_status.text = "%s\n%s" % [line, ("Web browser · " if mode == "web" else "") + volume]
		return
	var time := SET.clock(float(status.get("position", 0.0)))
	if float(status.get("duration", 0.0)) > 0.0: time += " / " + SET.clock(float(status.duration))
	_status.text = "%s\n%s · %s" % [line, time, volume]

func flash(text: String, seconds := 2.0) -> void:
	_status.text = text
	_flash_until = Time.get_ticks_msec() / 1000.0 + seconds
