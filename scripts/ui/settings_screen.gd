class_name SettingsScreen
extends ScreenBase
## Audio / display / control options. In-run it also offers resume, restart and
## a route back to the main menu, exactly like the pygame pause menu.
##
## Laid out as a phone settings *list* rather than a desktop form: every option
## is a full-width card with a tap target sized off Layout.touch_size(), the
## primary way out sits at the top where a thumb can reach it, and the two
## destructive actions are pushed to the bottom behind their own heading.

signal resume_run
signal restart_run
signal to_main_menu
signal crt_changed(enabled: bool)

var from_main_menu := true


func _init() -> void:
	scrim_alpha = 0.95


## In portrait the settings list *is* the screen -- a 620px column inside a 620px
## viewport only adds gutters. A landscape phone is the opposite problem: a
## full-width row across 936px is an absurd measure, so it keeps a column.
func content_width() -> float:
	if not Layout.touch_primary:
		return 620.0
	return 940.0 if Layout.portrait else 700.0


func _build() -> void:
	content.add_theme_constant_override("separation", roundi(12.0 * Layout.text_scale()))
	add_header("Settings")

	# The way back out comes first: on a phone the list scrolls, and hunting for
	# "Resume" below the fold is the difference between a pause menu and a trap.
	var leave := UIKit.make_button("Resume" if not from_main_menu else "Back",
		Cfg.ACCENT_GOOD, "medium")
	leave.custom_minimum_size.y = Layout.touch_size() * 1.15
	leave.pressed.connect(func():
		_save_and_close()
		if not from_main_menu:
			resume_run.emit())
	content.add_child(leave)

	_section("Controls")
	_placement_card()
	if Layout.touch_primary:
		# Only meaningful on a thumb: a mouse is absolute and always 1:1.
		_slider_card("Drag speed", SaveGame.drag_gain, func(v: float):
			SaveGame.drag_gain = v,
			BoardView.DRAG_GAIN_MIN, BoardView.DRAG_GAIN_MAX, 0.1, "x",
			"How far the piece travels for each inch your finger moves. Higher crosses the board faster; lower aims more precisely.")
		_toggle_card("Haptics", SaveGame.haptics, func(on: bool):
			SaveGame.haptics = on
			if on:
				Input.vibrate_handheld(20))
	_touch_layout_card()

	_section("Audio")
	_slider_card("Music", SaveGame.music_volume, func(v: float):
		SaveGame.music_volume = v
		Audio.apply_volumes())
	_slider_card("SFX", SaveGame.sfx_volume, func(v: float):
		SaveGame.sfx_volume = v
		Audio.apply_volumes()
		Audio.play(Cfg.SFX_UI_CLICK, 0.6))

	_section("Display")
	_toggle_card("CRT Filter", SaveGame.crt_filter, func(on: bool):
		SaveGame.crt_filter = on
		crt_changed.emit(on))
	_slider_card("Screen Shake", SaveGame.screen_shake, func(v: float):
		SaveGame.screen_shake = v)
	# Fullscreen is a desktop window mode. A phone browser is already fullscreen
	# and an installed PWA cannot leave it, so the row would be a dead control.
	if not Layout.touch_primary:
		_toggle_card("Fullscreen", SaveGame.fullscreen, func(on: bool):
			SaveGame.fullscreen = on
			_apply_fullscreen(on))

	if not from_main_menu:
		_section("Run")
		var restart := _row_button("Restart Run", Cfg.ACCENT_PRIMARY)
		restart.pressed.connect(func():
			_save_and_close()
			restart_run.emit())
		content.add_child(restart)
		var menu := _row_button("Quit to Main Menu", Cfg.ACCENT_DANGER)
		menu.pressed.connect(func():
			_save_and_close()
			to_main_menu.emit())
		content.add_child(menu)

	content.add_child(UIKit.spacer(Layout.touch_size()))


# ==========================================================================
#  Cards
# ==========================================================================
func _section(title: String) -> void:
	content.add_child(UIKit.spacer(6))
	content.add_child(UIKit.make_section(title, Cfg.ACCENT_PRIMARY))


## One settings row: a full-width panel so the whole strip reads as a single
## object. Returns the box to fill, already parented into the list.
func _card() -> VBoxContainer:
	var panel := UIKit.make_panel(Color(0.10, 0.10, 0.19), Cfg.PANEL_ACCENT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	content.add_child(panel)
	return v


## Full-width action bar. Left-aligned like a list row rather than centred like
## a dialog button, and always at least one tap target tall.
func _row_button(label: String, accent := Cfg.PANEL_ACCENT) -> Button:
	var b := UIKit.make_button(label, accent, "body")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = Layout.touch_size()
	return b


## Right-hand state chip on a row button. A Button renders exactly one label, so
## the current value rides along as an overlay pinned to the trailing edge.
func _row_value(host: Button, text: String, color: Color) -> Label:
	var l := UIKit.make_label(text, "body", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -18.0
	host.add_child(l)
	return l


func _hint(text: String) -> Label:
	var l := UIKit.make_label(text, "small", Cfg.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _slider_card(label: String, value: float, on_change: Callable,
		low := 0.0, high := 1.0, step := 0.01, unit := "%", hint := "") -> void:
	var box := _card()

	var row := HBoxContainer.new()
	var name_label := UIKit.make_label(label, "body")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := UIKit.make_label(_slider_text(value, unit), "body", Cfg.ACCENT_PRIMARY)
	row.add_child(value_label)
	box.add_child(row)

	var slider := UIKit.make_slider(value, Cfg.ACCENT_PRIMARY, low, high, step)
	slider.value_changed.connect(func(v: float):
		value_label.text = _slider_text(v, unit)
		on_change.call(v))
	box.add_child(slider)
	if not hint.is_empty():
		box.add_child(_hint(hint))


## Percentages read better as whole numbers; a gain multiplier needs its decimal.
func _slider_text(value: float, unit: String) -> String:
	if unit == "%":
		return "%d%%" % roundi(value * 100.0)
	return "%.1f%s" % [value, unit]


func _toggle_card(label: String, value: bool, on_change: Callable, hint := "") -> void:
	var box := _card()
	var b := _row_button(label)
	b.set_meta("state", value)
	var chip := _row_value(b, _on_off(value), Cfg.ACCENT_GOOD if value else Cfg.GRAY)
	b.pressed.connect(func():
		var state: bool = not bool(b.get_meta("state"))
		b.set_meta("state", state)
		chip.text = _on_off(state)
		chip.add_theme_color_override("font_color", Cfg.ACCENT_GOOD if state else Cfg.GRAY)
		on_change.call(state))
	box.add_child(b)
	if not hint.is_empty():
		box.add_child(_hint(hint))


func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


## Segmented picker: every option visible and directly tappable. A cycling
## button hides the alternatives, which is the wrong trade on a phone where the
## label is the only affordance you get.
func _segmented(options: Array, current: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var buttons: Array[Button] = []
	for label in options:
		var b := UIKit.make_button(String(label), Cfg.ACCENT_PRIMARY, "body")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = Layout.touch_size()
		buttons.append(b)
		row.add_child(b)
	for i in buttons.size():
		buttons[i].pressed.connect(func():
			_paint_segments(buttons, i)
			on_change.call(i))
	_paint_segments(buttons, current)
	return row


func _paint_segments(buttons: Array[Button], selected: int) -> void:
	for i in buttons.size():
		var chosen: bool = i == selected
		var fill: Color = Cfg.BUTTON_HOVER if chosen else Cfg.BUTTON_FILL.darkened(0.3)
		var accent: Color = Cfg.ACCENT_PRIMARY if chosen else Cfg.PANEL_ACCENT
		var style := UIKit.button_style(fill, accent, 10, false)
		style.set_border_width_all(2 if chosen else 1)
		buttons[i].add_theme_stylebox_override("normal", style)
		buttons[i].add_theme_color_override("font_color", Cfg.WHITE if chosen else Cfg.TEXT_DIM)


# ==========================================================================
#  Control options
# ==========================================================================
## Two ways to hold a piece. Default is the Block Blast feel; Direct is the
## literal one, for players who would rather aim than throw.
const PLACEMENT_NAMES := ["Default", "Direct"]


func _placement_card() -> void:
	var box := _card()
	box.add_child(UIKit.make_label("Drag style", "body"))
	var desc := _hint(_placement_blurb(SaveGame.placement_mode))
	box.add_child(_segmented(PLACEMENT_NAMES, SaveGame.placement_mode, func(i: int):
		SaveGame.placement_mode = i
		desc.text = _placement_blurb(i)))
	box.add_child(desc)


func _placement_blurb(mode: int) -> String:
	if mode == BoardView.PLACEMENT_DIRECT:
		return "The piece sits under your finger and follows it exactly. Aim it."
	return "The piece floats a hand's width above your finger and travels %.1fx as far, so a short flick from the tray reaches the top row." % SaveGame.drag_gain


## The escape hatch for a browser that lies about its pointer. A home-screen PWA
## can report a desktop user agent, and the whole UI then sizes itself for a
## mouse -- tiny buttons, no drag lift. Auto is right almost always; the manual
## settings exist so a wrong guess is never unrecoverable.
func _touch_layout_card() -> void:
	var box := _card()
	box.add_child(UIKit.make_label("Touch layout", "body"))
	var desc := _hint(_touch_blurb())
	box.add_child(_segmented(["Auto", "Touch", "Mouse"],
		SaveGame.touch_override, func(i: int):
			SaveGame.touch_override = i
			# If this actually flips the mode, Layout re-scales the window and
			# emits layout_changed a frame later, which rebuilds this screen
			# against the new metrics. Rebuilding here instead would read the
			# previous frame's content scale and lay out to the old size.
			Layout.refresh_touch_mode()
			desc.text = _touch_blurb()))
	box.add_child(desc)


func _touch_blurb() -> String:
	var detected := "touch" if Layout.touch_primary else "mouse"
	if SaveGame.touch_override == 1:
		return "Forced to the touch layout: big controls and drag-to-place."
	if SaveGame.touch_override == 2:
		return "Forced to the desktop layout: compact controls, 1:1 pointer."
	return "Detected: %s. Switch to Touch if the controls look small on a phone." % detected


func _apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _save_and_close() -> void:
	SaveGame.save_settings()
	close()


func on_cancel() -> void:
	_save_and_close()
	if not from_main_menu:
		resume_run.emit()
