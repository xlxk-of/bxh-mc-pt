extends Node
## Portrait layout measurements.

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in 40:
		await get_tree().process_frame
	main._start_new_run()
	for _i in 30:
		await get_tree().process_frame

	for size in [Vector2i(560, 980), Vector2i(1080, 2400), Vector2i(390, 844)]:
		DisplayServer.window_set_size(size)
		for _i in 30:
			await get_tree().process_frame
		var hud: HUD = main._hud
		print("--- window %s  scale=%.2f  logical=%s  portrait=%s form=%d" % [
			size, get_window().content_scale_factor, Layout.logical_size(), Layout.portrait, Layout.form])
		print("    HUD size      = ", hud.size)
		var lane: Node = hud.get_child(0).get_child(0)
		for child in lane.get_children():
			if child is Control:
				print("    lane child %-18s size=%s min=%s ratio=%.1f" % [
					child.get_class(), (child as Control).size,
					(child as Control).get_combined_minimum_size(),
					(child as Control).size_flags_stretch_ratio])
		print("    board size    = ", hud.board.size, " cell=", hud.board.cell_size,
			" grid=", hud.board.grid_rect().size)
	get_tree().quit()
