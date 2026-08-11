class_name PiecePicker
extends ScreenBase
## Shape chooser. Backs both Merlin's Hat (weight a shape) and the Magic Ball
## item (conjure a shape straight into your hand).

signal picked(shape_name: String)
signal sell_requested
signal back_requested

var title_text := "Choose a piece"
var subtitle_text := ""
var locked := false
var locked_text := ""
var show_sell := false
var sell_label := "Sell this card"
var show_back := false
var back_label := "Back"
var highlight_name := ""


func _init() -> void:
	max_content_width = 900.0
	scrim_alpha = 0.92


func _build() -> void:
	add_header(title_text, subtitle_text, Cfg.cosmic_color)

	if locked and not locked_text.is_empty():
		var warn := UIKit.make_label(locked_text, "small", Cfg.RED)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(warn)

	var grid := GridContainer.new()
	grid.columns = 4 if Layout.portrait else 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)

	for shape in Cfg.SHAPES:
		grid.add_child(_make_tile(shape))

	content.add_child(UIKit.spacer(6))
	var buttons: Array[Button] = []
	if show_back:
		var back := UIKit.make_button(back_label, Cfg.PANEL_ACCENT, "small")
		back.pressed.connect(func():
			back_requested.emit()
			close())
		buttons.append(back)
	if show_sell:
		var sell := UIKit.make_button(sell_label, Cfg.ACCENT_DANGER, "small")
		sell.pressed.connect(func():
			sell_requested.emit()
			close())
		buttons.append(sell)
	var cancel := UIKit.make_button("Cancel", Cfg.PANEL_ACCENT, "small")
	cancel.pressed.connect(close)
	buttons.append(cancel)
	add_button_row(buttons)


func _make_tile(shape: Dictionary) -> Control:
	var chosen: bool = shape["name"] == highlight_name
	var panel := UIKit.make_panel(Color(0.08, 0.08, 0.15),
		Cfg.ACCENT_PRIMARY if chosen else Cfg.PANEL_ACCENT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var preview := PiecePreview.new()
	preview.custom_minimum_size = Vector2(78, 78)
	preview.set_shape(shape)
	preview.is_selected = chosen
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(preview)

	var label := UIKit.make_label(shape["name"], "tiny", Cfg.LIGHT_GRAY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(label)

	var pick := UIKit.make_button("Pick", Cfg.ACCENT_GOOD, "tiny")
	pick.custom_minimum_size.y = Layout.touch_size() * 0.8
	pick.disabled = locked
	pick.pressed.connect(func():
		picked.emit(String(shape["name"]))
		close())
	v.add_child(pick)
	return panel
