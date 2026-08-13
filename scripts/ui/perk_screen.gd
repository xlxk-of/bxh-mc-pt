class_name PerkScreen
extends ScreenBase
## Between-round perk draft: pick one of three, or skip.

signal finished

var session: GameSession


func _init() -> void:
	max_content_width = 940.0
	scrim_alpha = 0.94


func _build() -> void:
	if session == null:
		return
	add_header("Perk Selection", "Round %d - choose one" % session.round_count, Cfg.MAGENTA)

	var row: BoxContainer = VBoxContainer.new() if Layout.portrait else HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)

	for i in session.perk_offers.size():
		row.add_child(_make_card(session.perk_offers[i], i))

	content.add_child(UIKit.spacer(8))
	var skip := UIKit.make_button("Skip", Cfg.PANEL_ACCENT, "small")
	skip.pressed.connect(_finish)
	add_button_row([skip])


func _make_card(offer: Dictionary, index: int) -> Control:
	var accent := Cfg.rarity_color(offer.get("rarity", "Common"))
	var panel := UIKit.make_panel(Color(0.10, 0.08, 0.16), accent)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var tags := UIKit.make_tag_row(offer.get("rarity", "Common"), "Perk")
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(tags)

	var title := UIKit.make_label(offer["name"], "body", Cfg.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)

	var desc := UIKit.make_label(offer.get("description", ""), "small", Cfg.LIGHT_GRAY)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(200, 60)
	v.add_child(desc)

	var take := UIKit.make_button("Take", Cfg.ACCENT_GOOD, "small")
	take.pressed.connect(func():
		session.choose_perk(index)
		_finish())
	v.add_child(take)
	return panel


func _finish() -> void:
	if session.perk_offers.size() > 0:
		# Skipped: clear the offer and resume play the same way choosing does.
		session.perk_offers = []
		Audio.play_music(Cfg.MUSIC_INGAME)
		session.generate_hand()
	finished.emit()
	close()


func on_cancel() -> void:
	_finish()
