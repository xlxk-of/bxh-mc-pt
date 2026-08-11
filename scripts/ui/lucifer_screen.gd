class_name LuciferScreen
extends ScreenBase
## Lucifer's Lost & Found. Each contract pairs a blessing with a curse that
## only lifts once its condition timer runs out, so the choice has teeth.

signal finished

var session: GameSession


func _init() -> void:
	max_content_width = 980.0
	scrim_alpha = 0.95


func _build() -> void:
	if session == null:
		return
	add_header("Lucifer's Lost & Found", "Every gift has a price", Cfg.RED)

	var row: BoxContainer = VBoxContainer.new() if Layout.portrait else HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)

	for i in session.lucifer_offers.size():
		row.add_child(_make_contract(session.lucifer_offers[i], i))

	content.add_child(UIKit.spacer(8))
	var walk := UIKit.make_button("Walk Away", Cfg.PANEL_ACCENT, "small")
	walk.pressed.connect(_finish)
	add_button_row([walk])


func _make_contract(offer: Dictionary, index: int) -> Control:
	var panel := UIKit.make_panel(Color(0.14, 0.06, 0.08), Cfg.RED)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var title := UIKit.make_title(offer["name"], "medium", Cfg.ACCENT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var boon := UIKit.make_label(offer.get("description", ""), "small", Cfg.ACCENT_GOOD)
	boon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boon.custom_minimum_size = Vector2(215, 46)
	v.add_child(boon)

	var curse_head := UIKit.make_label("CURSE", "tiny", Cfg.RED)
	curse_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(curse_head)

	var curse := UIKit.make_label(offer.get("condition_text", ""), "small", Cfg.LIGHT_GRAY)
	curse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	curse.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	curse.custom_minimum_size = Vector2(215, 44)
	v.add_child(curse)

	var timers := UIKit.make_label(
		"Curse lifts in %d rounds · expires in %d" % [offer["condition_deadline"], offer["expiration"]],
		"tiny", Cfg.TEXT_DIM)
	timers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(timers)

	var sign_button := UIKit.make_button("Sign", Cfg.ACCENT_DANGER, "small")
	sign_button.pressed.connect(func():
		session.choose_contract(index)
		SteamManager.unlock("DEAL_MAKER")
		_finish())
	v.add_child(sign_button)
	return panel


func _finish() -> void:
	if session.lucifer_offers.size() > 0:
		session.lucifer_offers = []
		Audio.play_music(Cfg.MUSIC_INGAME)
		session.generate_hand()
	finished.emit()
	close()


func on_cancel() -> void:
	_finish()
