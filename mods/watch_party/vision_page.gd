extends HBoxContainer
## The TV menu's "Pony vision" page (tv_menu.gd): whether ponies see the picture, the order the
## vision APIs take, and the list of APIs with one edited at a time (vision_pool.gd explains the
## fields). Every change is saved half a second after the last one.

const POOL := preload("res://mods/watch_party/vision_pool.gd")
const PROFILES := preload("res://world/ai/llm_profiles.gd")
const MODEL_CATALOG := preload("res://world/ai/model_catalog.gd")
## Seconds after the last change to the address, key or source before its models are listed.
const FETCH_DELAY := 0.8
const SOURCES := ["own", "dialogue", "preset"]
const SOURCE_LABELS := ["Its own key", "The game's dialogue settings", "A saved LLM preset"]
const ORDERS := ["turns", "in_order"]
const MODEL_HINTS := {"gemini": "e.g. gemini-2.5-flash", "anthropic": "e.g. claude-sonnet-5-5", "openai": "the model's name on that server"}

var hub: Node
var menu: Node
var _enabled: CheckButton
var _order: OptionButton
var _list: ItemList
var _reset: Label
var _editor: GridContainer
var _name: LineEdit
var _source: OptionButton
var _preset_label: Label
var _preset: OptionButton
var _provider_label: Label
var _provider: OptionButton
var _url_label: Label
var _url: LineEdit
var _key_label: Label
var _key: LineEdit
var _model: LineEdit
var _model_pick: OptionButton
var _model_status: Label
var _catalog: Node
var _fetch_in := -1.0
var _fetch_ticket := 0
var _daily: SpinBox
var _best: CheckButton
var _best_turns: CheckButton
var _test: Button
var _status: Label
var _selected := -1
var _presets: Array = []
var _save_in := -1.0
var _refresh := 0.0
var _filling := false

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_list_panel())
	add_child(_editor_panel())

func _list_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_enabled = CheckButton.new(); _enabled.text = "Ponies see the picture now and then"
	_enabled.toggled.connect(_enabled_toggled)
	column.add_child(_enabled)
	var about := _label("Every few remarks (every 4th at Normal, and whenever nothing has been said for a while) a still from the film goes to a vision model, and the pony hears its description. Only those stills leave your computer.", "Faint")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(about)
	var order_row := HBoxContainer.new(); order_row.add_theme_constant_override("separation", 10)
	order_row.add_child(_label("Order", "Muted"))
	_order = _drop(_order_chosen)
	_order.add_item("Take turns, one call each")
	_order.add_item("The first with calls left")
	order_row.add_child(_order)
	column.add_child(order_row)
	column.add_child(_label("Vision APIs", "Subheading"))
	_list = ItemList.new(); _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 160)
	_list.item_selected.connect(_select)
	column.add_child(_list)
	var buttons := HBoxContainer.new(); buttons.add_theme_constant_override("separation", 8)
	buttons.add_child(_button("Add", _add, "Primary"))
	buttons.add_child(_button("Up", _move.bind(-1), "Ghost"))
	buttons.add_child(_button("Down", _move.bind(1), "Ghost"))
	buttons.add_child(_button("Remove", _remove, "Danger"))
	column.add_child(buttons)
	_reset = _label("", "Faint"); _reset.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_reset)
	return panel

func _editor_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_editor = GridContainer.new(); _editor.columns = 2
	_editor.add_theme_constant_override("h_separation", 14); _editor.add_theme_constant_override("v_separation", 10)
	column.add_child(_editor)
	_name = _field("Name", "e.g. Gemini key 1")
	_source = _drop(_source_chosen)
	for text: String in SOURCE_LABELS: _source.add_item(text)
	_row("Uses", _source)
	_preset = _drop(_preset_chosen)
	_preset_label = _row("Preset", _preset)
	_provider = _drop(_provider_chosen)
	for key: String in POOL.PROVIDERS: _provider.add_item(str(POOL.PROVIDER_LABELS[key]))
	_provider_label = _row("Provider", _provider)
	_url = _field("Address", "")
	_url_label = _editor.get_child(_editor.get_child_count() - 2) as Label
	_key = _field("API key", "")
	_key.secret = true
	_key_label = _editor.get_child(_editor.get_child_count() - 2) as Label
	_model = _field("Model", "")
	var pick_row := HBoxContainer.new(); pick_row.add_theme_constant_override("separation", 10)
	_model_pick = _drop(_model_picked)
	_model_pick.visible = false
	pick_row.add_child(_model_pick)
	_model_status = _label("", "Faint"); _model_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_model_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_row.add_child(_model_status)
	_row("", pick_row)
	_daily = SpinBox.new(); _daily.min_value = 0; _daily.max_value = 100000; _daily.step = 1
	_daily.suffix = "a day"
	# Wide enough for the whole number (playtest 2026-11-07: beside its note it shrank to one digit).
	_daily.custom_minimum_size.x = 170
	_daily.tooltip_text = "0: no limit. The count starts again at midnight Pacific time."
	_daily.value_changed.connect(func(value: float) -> void: _edit("daily", int(value)))
	# Said beside the box, not only in its tooltip (dev 2026-11-07: make it clear 0 is no limit).
	var daily_row := HBoxContainer.new(); daily_row.add_theme_constant_override("separation", 10)
	daily_row.add_child(_daily)
	var daily_note := _label("0 means no limit. The count starts again at midnight Pacific time.", "Faint")
	daily_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	daily_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daily_row.add_child(daily_note)
	_row("Calls", daily_row)
	_best = CheckButton.new(); _best.text = "Best: the backup when another fails"
	_best.tooltip_text = "The one almost sure to work. When another API fails, the same picture goes to this one at once."
	_best.toggled.connect(_best_toggled)
	_row("", _best)
	_best_turns = CheckButton.new(); _best_turns.text = "Also takes its turn"
	_best_turns.tooltip_text = "Off: it is only the backup and is never called in turn."
	_best_turns.toggled.connect(func(on: bool) -> void: _edit("best_turns", on))
	_row("", _best_turns)
	var test_row := HBoxContainer.new(); test_row.add_theme_constant_override("separation", 10)
	_test = _button("Test", _run_test)
	test_row.add_child(_test)
	_status = _label("", "Faint"); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(_status)
	column.add_child(test_row)
	return panel

func _row(text: String, control: Control) -> Label:
	var label := _label(text, "Muted")
	_editor.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_child(control)
	return label

func _field(text: String, hint: String) -> LineEdit:
	var line := LineEdit.new(); line.placeholder_text = hint
	var key := str({"Name": "name", "Address": "base_url", "API key": "api_key", "Model": "model"}[text])
	line.text_changed.connect(func(value: String) -> void:
		_edit(key, value.strip_edges())
		if key in ["base_url", "api_key"]: _queue_fetch())
	_row(text, line)
	return line

func _label(text: String, variation := "") -> Label:
	var label := Label.new(); label.text = text
	if not variation.is_empty(): label.theme_type_variation = variation
	return label

func _button(text: String, pressed: Callable, variation := "") -> Button:
	var button := Button.new(); button.text = text
	if not variation.is_empty(): button.theme_type_variation = variation
	button.pressed.connect(pressed)
	return button

func _drop(chosen: Callable) -> OptionButton:
	var drop := OptionButton.new()
	drop.theme_type_variation = "Drop"
	drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop.fit_to_longest_item = false
	drop.clip_text = true
	drop.item_selected.connect(chosen)
	return drop

# --- state --------------------------------------------------------------------------------------

func _settings() -> RefCounted:
	return hub.get("settings") as RefCounted

func _vision() -> Dictionary:
	return _settings().vision

func _apis() -> Array:
	return _vision().apis

func _pool() -> Node:
	var company: Variant = hub.get("company")
	return (company as Node).get("vision") as Node if is_instance_valid(company) else null

## The page as saved, from the top (the menu opening or this page being shown).
func open() -> void:
	_filling = true
	_enabled.set_pressed_no_signal(bool(_vision().enabled))
	_order.select(maxi(0, ORDERS.find(str(_vision().order))))
	var profiles: RefCounted = PROFILES.new()
	profiles.call("open")
	_presets = profiles.call("names")
	_preset.clear()
	for preset: Variant in _presets: _preset.add_item(str(preset))
	_filling = false
	_fill_list()
	_select(clampi(_selected, 0, _apis().size() - 1) if not _apis().is_empty() else -1)

func _fill_list() -> void:
	var pool := _pool()
	_list.clear()
	for entry: Dictionary in _apis():
		var label := str(entry.get("name", "")).strip_edges()
		if label.is_empty(): label = "Unnamed"
		var model := str(entry.get("model", "")).strip_edges()
		var used := int(pool.call("calls_today", entry)) if pool != null else 0
		var daily := int(entry.get("daily", 0))
		var text := ("★ " if bool(entry.get("best", false)) else "") + label
		if not model.is_empty(): text += " · " + model
		text += " · %d%s today" % [used, (" of %d" % daily) if daily > 0 else " (no limit)"]
		_list.add_item(text)
	if _selected >= 0 and _selected < _list.item_count: _list.select(_selected)
	_show_reset()

func _show_reset() -> void:
	var left := POOL.seconds_to_reset(Time.get_unix_time_from_system())
	_reset.text = "Day counts start again at midnight Pacific time (in %d h %d min)." % [left / 3600, (left % 3600) / 60]
	if _apis().is_empty(): _reset.text = "Add an API to let ponies see the picture. " + _reset.text

func _select(index: int) -> void:
	_selected = index
	_editor.get_parent().get_parent().visible = index >= 0
	if index < 0: return
	var entry: Dictionary = _apis()[index]
	_filling = true
	_name.text = str(entry.get("name", ""))
	_source.select(maxi(0, SOURCES.find(str(entry.get("source", "own")))))
	_preset.select(_presets.find(str(entry.get("preset", ""))))
	_provider.select(maxi(0, POOL.PROVIDERS.find(str(entry.get("provider", "gemini")))))
	_url.text = str(entry.get("base_url", ""))
	_key.text = str(entry.get("api_key", ""))
	_model.text = str(entry.get("model", ""))
	_daily.set_value_no_signal(int(entry.get("daily", 0)))
	_best.set_pressed_no_signal(bool(entry.get("best", false)))
	_best_turns.set_pressed_no_signal(bool(entry.get("best_turns", true)))
	_status.text = ""
	_model_status.text = ""
	_filling = false
	_show_fields()
	_queue_fetch()

## Only the fields the chosen source uses.
func _show_fields() -> void:
	if _selected < 0: return
	var entry: Dictionary = _apis()[_selected]
	var source := str(entry.get("source", "own"))
	var own := source == "own"
	for control: Control in [_provider_label, _provider, _url_label, _url, _key_label, _key]: control.visible = own
	_preset_label.visible = source == "preset"; _preset.visible = source == "preset"
	var provider := str(entry.get("provider", "gemini"))
	_url.placeholder_text = str(POOL.DEFAULT_URLS.get(provider, "")) if provider != "openai" else "e.g. https://openrouter.ai/api/v1"
	_model.placeholder_text = str(MODEL_HINTS.get(provider, "")) if own else "empty: the same model as the dialogue"
	_best_turns.disabled = not bool(entry.get("best", false))
	if source == "preset" and _presets.is_empty(): _status.text = "No saved LLM presets yet (Settings → AI Settings)."

func _edit(key: String, value: Variant) -> void:
	if _filling or _selected < 0 or _selected >= _apis().size(): return
	(_apis()[_selected] as Dictionary)[key] = value
	_changed()

func _enabled_toggled(on: bool) -> void:
	_vision().enabled = on
	_changed()

func _order_chosen(index: int) -> void:
	_vision().order = ORDERS[index]
	_changed()

func _provider_chosen(index: int) -> void:
	_edit("provider", POOL.PROVIDERS[index])
	_show_fields()
	_queue_fetch()

func _preset_chosen(index: int) -> void:
	_edit("preset", _preset.get_item_text(index) if index >= 0 else "")
	_queue_fetch()

func _source_chosen(index: int) -> void:
	_edit("source", SOURCES[index])
	_show_fields()
	_queue_fetch()

# --- the models an API offers (world/ai/model_catalog.gd, as AI Settings lists them) ------------

func _queue_fetch() -> void:
	_fetch_in = FETCH_DELAY
	_fetch_ticket += 1
	_model_pick.visible = false
	if is_instance_valid(_catalog): _catalog.call("cancel")

func _fetch_models() -> void:
	var pool := _pool()
	if pool == null or _selected < 0 or _selected >= _apis().size(): return
	var entry: Dictionary = _apis()[_selected]
	var section: Dictionary = pool.call("connection", entry, false)
	if section.has("error"):
		_model_status.text = str(section.error)
		return
	if str(entry.get("source", "own")) == "own" and str(entry.get("api_key", "")).strip_edges().is_empty() and str(entry.get("provider", "gemini")) != "openai":
		_model_status.text = "Type the API key to list its models."
		return
	if not is_instance_valid(_catalog):
		_catalog = MODEL_CATALOG.new(); _catalog.name = "VisionModels"
		add_child(_catalog)
		_catalog.connect("completed", _models_listed)
	var ticket := _fetch_ticket
	_catalog.set_meta("ticket", ticket)
	_model_status.text = "Fetching models…"
	_catalog.call("fetch", section)

func _models_listed(models: PackedStringArray, error: String) -> void:
	if not is_instance_valid(_catalog) or int(_catalog.get_meta("ticket", -1)) != _fetch_ticket: return
	_model_pick.clear()
	for id: String in models: _model_pick.add_item(id)
	var current := _model.text.strip_edges()
	_model_pick.select(Array(models).find(current))
	_model_pick.visible = not models.is_empty()
	if not error.is_empty(): _model_status.text = error
	elif current.is_empty() or Array(models).has(current): _model_status.text = "%d models. Choose one, or type its ID above." % models.size()
	else: _model_status.text = "%d models; \"%s\" is not among them." % [models.size(), current]

func _model_picked(index: int) -> void:
	if index < 0: return
	var id := _model_pick.get_item_text(index)
	_model.text = id
	_edit("model", id)
	_model_status.text = "Model set."

func _best_toggled(on: bool) -> void:
	if _filling or _selected < 0: return
	for i in _apis().size(): (_apis()[i] as Dictionary).best = on and i == _selected
	_best_turns.disabled = not on
	_changed()

func _add() -> void:
	var number := _apis().size() + 1
	_apis().append({"id": POOL.new_id(), "name": "Vision %d" % number, "source": "own", "preset": "", "provider": "gemini",
		"base_url": "", "api_key": "", "model": "", "daily": 0, "best": _apis().is_empty(), "best_turns": true})
	_selected = _apis().size() - 1
	_changed()
	_fill_list()
	_select(_selected)

func _remove() -> void:
	if _selected < 0 or _selected >= _apis().size(): return
	_apis().remove_at(_selected)
	_selected = mini(_selected, _apis().size() - 1)
	_changed()
	_fill_list()
	_select(_selected)

func _move(step: int) -> void:
	var to := _selected + step
	if _selected < 0 or to < 0 or to >= _apis().size(): return
	var entry: Variant = _apis()[_selected]
	_apis()[_selected] = _apis()[to]
	_apis()[to] = entry
	_selected = to
	_changed()
	_fill_list()

func _changed() -> void:
	if _filling: return
	_save_in = 0.5

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if _fetch_in >= 0.0:
		_fetch_in -= delta
		if _fetch_in < 0.0: _fetch_models()
	if _save_in >= 0.0:
		_save_in -= delta
		if _save_in < 0.0:
			_settings().save()
			_fill_list()
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 30.0
		_show_reset()

## Saves now (the menu closing).
func flush() -> void:
	if _save_in >= 0.0:
		_save_in = -1.0
		_settings().save()

func _run_test() -> void:
	var pool := _pool()
	if pool == null or _selected < 0: return
	var entry: Dictionary = _apis()[_selected]
	var section: Dictionary = pool.call("connection", entry)
	if section.has("error"):
		_status.text = str(section.error); _status.theme_type_variation = "Warn"
		return
	var tv: Variant = menu.get("tv") if menu != null else null
	var image: Image = (tv as Node).call("picture_for_pony", 0.0) if is_instance_valid(tv) and (tv as Node).has_method("picture_for_pony") else null
	var started: bool = pool.call("test", _selected, image, _tested)
	if started:
		_test.disabled = true
		_status.text = "Asking…" + (" (with the picture on the TV)" if image != null else "")
		_status.theme_type_variation = "Faint"
	else:
		_status.text = "Busy with another picture; try again in a moment."

func _tested(text: String, error: String) -> void:
	if not is_instance_valid(_status): return
	_test.disabled = false
	_fill_list()
	if error.is_empty():
		_status.text = "Works: " + text.replace("\n", " ").left(160)
		_status.theme_type_variation = "Muted"
	else:
		_status.text = "Failed: " + error.left(200)
		_status.theme_type_variation = "Warn"
