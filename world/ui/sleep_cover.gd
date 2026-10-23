extends "res://world/life/arrival_wake.gd"
## Ordinary sleep fades over the whole view; the arrival story keeps its eyelids.
const FADE_OUT_SECONDS := 2.0
const FADE_IN_SECONDS := 2.0

func setup(host: Node) -> void:
	super.setup(host)
	set_process(false)
	_top.hide(); _bottom.hide()
	_set_closed(0.0)

func close_eyes() -> void:
	await _fade(1.0, FADE_OUT_SECONDS)

func open_eyes(seconds := FADE_IN_SECONDS) -> void:
	_say("")
	await _fade(0.0, seconds)

## Wall time keeps the short transition bounded even when a frame takes longer.
func _fade(to: float, seconds: float) -> void:
	var from := _closed
	var began := Time.get_ticks_usec()
	while true:
		var elapsed := float(Time.get_ticks_usec() - began) * .000001
		_set_closed(lerpf(from, to, smoothstep(0.0, 1.0, minf(1.0, elapsed / maxf(.001, seconds)))))
		if elapsed >= seconds: return
		if not await SHUTDOWN.frame(self): return

func show_text(text: String) -> void:
	_say(text)

func finish() -> void:
	queue_free()
