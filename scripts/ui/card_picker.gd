class_name CardPicker
extends ScreenBase
## Grid of owned cards, used by The Mimic to choose what to copy.

signal picked(card_name: String)
signal sell_requested

var title_text := "Choose a card to copy"
var subtitle_text := ""
var entries: Array = []   # [{name, rarity, index}]
var show_sell := false
var sell_label := "Sell this card"


func _init() -> void:
	max_content_width = 860.0
	scrim_alpha = 0.92


func _build() -> void:
	add_header(title_text, subtitle_text, Cfg.rarity_color("Exotic"))

	if entries.is_empty():
		var empty := UIKit.make_label("No eligible cards to copy.", "small", Cfg.TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty)
	else:
		var grid := GridContainer.new()
		grid.columns = 2 if Layout.portrait else 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		content.add_child(grid)
		for entry in entries:
			grid.add_child(_make_entry(entry))

	content.add_child(UIKit.spacer(6))
	var buttons: Array[Button] = []
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


func _make_entry(entry: Dictionary) -> Control:
	var rarity: String = entry.get("rarity", "Common")
	var panel := UIKit.make_panel(Color(0.09, 0.09, 0.16), Cfg.rarity_color(rarity))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var icon := CardIcon.new()
	icon.custom_minimum_size = Vector2(90, 90)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.interactive = false
	icon.set_entry(entry["name"], rarity)
	v.add_child(icon)

	var title := UIKit.make_label(entry["name"], "small", Cfg.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)

	var desc := UIKit.make_label(Cards.card(entry["name"]).get("description", ""), "tiny", Cfg.LIGHT_GRAY)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.y = 46
	v.add_child(desc)

	var pick := UIKit.make_button("Copy", Cfg.ACCENT_GOOD, "small")
	pick.pressed.connect(func():
		picked.emit(String(entry["name"]))
		close())
	v.add_child(pick)
	return panel
