extends Node
## Visual smoke test: boots the real game, drives it through every screen and
## both orientations, and writes PNGs so the layout can be eyeballed.
##   godot --path . res://test/screenshot.tscn

const OUT_DIR := "user://shots/"

var main: Node


func _ready() -> void:
	seed(4242)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _settle(60)

	await _shot("01_main_menu")

	main._start_new_run()
	await _settle(45)
	await _shot("02_game_landscape")

	# Give the player some toys so the panels are populated.
	var session: GameSession = main.session
	for card_name in ["Merlin's Hat", "The Mimic", "Barrel", "Angel's Kiss", "Overcharge"]:
		session.add_card(card_name)
	for item_name in ["Wide Bomb", "Small Bomb", "Magic Ball"]:
		session.items.append(Cards.new_item_instance(item_name))
	session.add_perk("Score Boost Perk")
	session.contracts.append({
		"name": "Greedy", "description": "Each card gives $5 every round.",
		"condition_text": "10% chance they break",
		"condition_deadline": 3, "expiration": 8, "condition_met": false})
	session.inventory_changed.emit()
	session.money = 250
	session.stats_changed.emit()
	await _settle(30)
	await _shot("03_game_full_inventory")

	# Build a combo so the fever visuals kick in.
	session.combo_streak = 12
	Juice.set_combo(12)
	session.combo_changed.emit(12, 3)
	for c in session.grid_cols - 1:
		session.board[0][c] = session._make_block(Cfg.CYAN)
	session.board_changed.emit()
	await _settle(20)
	var dot := Cfg.copy_shape(Cfg.shape_by_name("Dot1"))
	session.hand.append(dot)
	session.selected_index = session.hand.size() - 1
	session.place_piece(dot, 0, session.grid_cols - 1)
	await _settle(6)
	await _shot("04_line_clear_fever")

	# Shop.
	session.generate_shop_offers()
	main._open_shop()
	await _settle(45)
	await _shot("05_shop")
	main._active_screen.close()
	await _settle(20)

	# Perk draft.
	session.generate_perk_offers()
	main._open_perks()
	await _settle(45)
	await _shot("06_perks")
	main._active_screen.close()
	await _settle(20)

	# Lucifer's Lost & Found.
	session.generate_lucifer_offers()
	main._open_lucifer()
	await _settle(45)
	await _shot("07_lucifer")
	main._active_screen.close()
	await _settle(20)

	# Merlin's Hat picker (a modal over live gameplay).
	main._open_merlin_picker(0)
	await _settle(40)
	await _shot("08_piece_picker")
	main._modal.close()
	await _settle(20)

	# Settings.
	main._open_settings(false)
	await _settle(40)
	await _shot("09_settings")
	main._modal.close()
	await _settle(20)

	# Portrait / phone layout.
	DisplayServer.window_set_size(Vector2i(560, 980))
	await _settle(60)
	await _shot("10_portrait")

	# Game over.
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _settle(40)
	session.check_game_over("screenshot", true)
	session.check_game_over("screenshot", true)
	session.check_game_over("screenshot", true)
	await _settle(50)
	await _shot("11_game_over")

	print("Shots written to ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Wait in real seconds, not frames: the window runs unthrottled here, so a
## frame count is not a reliable proxy for "animations have finished".
func _settle(frames: int) -> void:
	await get_tree().create_timer(maxf(0.12, frames / 60.0), true, false, true).timeout
	await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + shot_name + ".png"
	img.save_png(path)
	print("  wrote ", shot_name, " ", img.get_size())
