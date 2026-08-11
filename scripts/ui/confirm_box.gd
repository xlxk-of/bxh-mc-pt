class_name ConfirmBox
extends ScreenBase
## Yes/no modal, used for selling cards and items.

signal confirmed
signal declined

var title_text := "Are you sure?"
var body_text := ""
var confirm_text := "Yes"
var cancel_text := "No"
var accent := Cfg.ACCENT_DANGER


func _init() -> void:
	max_content_width = 460.0
	scrim_alpha = 0.7
	use_scroll = false


func _build() -> void:
	var panel := UIKit.make_panel(Color(0.12, 0.09, 0.14), accent)
	content.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var t := UIKit.make_label(title_text, "medium", Cfg.ACCENT_PRIMARY)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)

	if not body_text.is_empty():
		var b := UIKit.make_label(body_text, "small", Cfg.MONEY_COLOR)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(b)

	var yes := UIKit.make_button(confirm_text, Cfg.ACCENT_GOOD, "small")
	yes.pressed.connect(func():
		confirmed.emit()
		close())
	var no := UIKit.make_button(cancel_text, Cfg.PANEL_ACCENT, "small")
	no.pressed.connect(func():
		declined.emit()
		close())
	add_button_row([yes, no])


func on_cancel() -> void:
	declined.emit()
	close()
