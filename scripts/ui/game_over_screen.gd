class_name GameOverScreen
extends ScreenBase
## Run summary with the two exits from the original: restart, or main menu.

signal restart_run
signal to_main_menu

var final_score := 0
var best_score := 0
var is_new_best := false
var rounds_survived := 1


func _init() -> void:
	max_content_width = 520.0
	scrim_alpha = 0.88
	use_scroll = false


func _build() -> void:
	add_header("GAME OVER", "", Cfg.ACCENT_DANGER)

	var panel := UIKit.make_panel(Color(0.13, 0.07, 0.09), Cfg.ACCENT_DANGER)
	content.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	v.add_child(_stat("FINAL SCORE", str(final_score), "large", Cfg.WHITE))
	if is_new_best:
		var badge := UIKit.make_label("* NEW HIGH SCORE *", "small", Cfg.ACCENT_PRIMARY)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(badge)
	v.add_child(UIKit.spacer(8))
	v.add_child(_stat("HIGH SCORE", str(best_score), "medium", Cfg.ACCENT_PRIMARY))
	v.add_child(UIKit.spacer(8))
	v.add_child(_stat("ROUNDS SURVIVED", str(rounds_survived), "medium", Cfg.TEXT_DIM))

	content.add_child(UIKit.spacer(10))
	var again := UIKit.make_button("Restart (R)", Cfg.ACCENT_GOOD, "small")
	again.pressed.connect(func():
		restart_run.emit()
		close())
	var menu := UIKit.make_button("Main Menu", Cfg.PANEL_ACCENT, "small")
	menu.pressed.connect(func():
		to_main_menu.emit()
		close())
	add_button_row([again, menu])


func _stat(label: String, value: String, kind: String, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := UIKit.make_label(label, "tiny", Cfg.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var v := UIKit.make_number(value, kind, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(v)
	return box


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
		and (event as InputEventKey).keycode == KEY_R:
		restart_run.emit()
		close()
		get_viewport().set_input_as_handled()


func on_cancel() -> void:
	to_main_menu.emit()
	close()
