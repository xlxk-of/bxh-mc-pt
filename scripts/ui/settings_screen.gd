class_name SettingsScreen
extends ScreenBase
## Audio / display / control options. In-run it also offers resume, restart and
## a route back to the main menu, exactly like the pygame pause menu.

signal resume_run
signal restart_run
signal to_main_menu
signal crt_changed(enabled: bool)

var from_main_menu := true


func _init() -> void:
	max_content_width = 620.0
	scrim_alpha = 0.95


func _build() -> void:
	add_header("Settings")

	content.add_child(UIKit.make_section("Audio"))
	content.add_child(_slider("Music", SaveGame.music_volume, func(v: float):
		SaveGame.music_volume = v
		Audio.apply_volumes()))
	content.add_child(_slider("SFX", SaveGame.sfx_volume, func(v: float):
		SaveGame.sfx_volume = v
		Audio.apply_volumes()
		Audio.play(Cfg.SFX_UI_CLICK, 0.6)))

	content.add_child(UIKit.make_section("Display"))
	content.add_child(_toggle("Fullscreen", SaveGame.fullscreen, func(on: bool):
		SaveGame.fullscreen = on
		_apply_fullscreen(on)))
	content.add_child(_toggle("CRT Filter", SaveGame.crt_filter, func(on: bool):
		SaveGame.crt_filter = on
		crt_changed.emit(on)))
	content.add_child(_slider("Screen Shake", SaveGame.screen_shake, func(v: float):
		SaveGame.screen_shake = v))

	if Layout.touch_primary:
		content.add_child(UIKit.make_section("Touch"))
		content.add_child(_toggle("Haptics", SaveGame.haptics, func(on: bool):
			SaveGame.haptics = on
			if on:
				Input.vibrate_handheld(20)))

	content.add_child(UIKit.spacer(8))
	var buttons: Array[Button] = []
	if not from_main_menu:
		var resume := UIKit.make_button("Resume", Cfg.ACCENT_GOOD, "small")
		resume.pressed.connect(func():
			_save_and_close()
			resume_run.emit())
		buttons.append(resume)
		var restart := UIKit.make_button("Restart Run", Cfg.ACCENT_PRIMARY, "small")
		restart.pressed.connect(func():
			_save_and_close()
			restart_run.emit())
		buttons.append(restart)
		var menu := UIKit.make_button("Main Menu", Cfg.ACCENT_DANGER, "small")
		menu.pressed.connect(func():
			_save_and_close()
			to_main_menu.emit())
		buttons.append(menu)
	else:
		var back := UIKit.make_button("Back", Cfg.ACCENT_GOOD, "small")
		back.pressed.connect(_save_and_close)
		buttons.append(back)
	add_button_row(buttons)


func _slider(label: String, value: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	var name_label := UIKit.make_label(label, "small")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := UIKit.make_label("%d%%" % int(value * 100.0), "small", Cfg.TEXT_DIM)
	row.add_child(value_label)
	box.add_child(row)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size.y = maxf(28.0, Layout.touch_size() * 0.6)
	slider.value_changed.connect(func(v: float):
		value_label.text = "%d%%" % int(v * 100.0)
		on_change.call(v))
	box.add_child(slider)
	return box


func _toggle(label: String, value: bool, on_change: Callable) -> Control:
	var b := UIKit.make_button("%s: %s" % [label, "On" if value else "Off"],
		Cfg.PANEL_ACCENT, "small")
	b.set_meta("state", value)
	b.pressed.connect(func():
		var state: bool = not bool(b.get_meta("state"))
		b.set_meta("state", state)
		b.text = "%s: %s" % [label, "On" if state else "Off"]
		on_change.call(state))
	return b


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
