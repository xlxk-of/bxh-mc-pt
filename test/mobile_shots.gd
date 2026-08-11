extends Node
## Renders the phone layouts on a desktop by forcing Layout into its touch path
## and matching the CSS dimensions of a real handset, then captures the states
## that matter for feel: idle, mid-drag, the shop, and a live rotation.
##
##   godot --path . res://test/mobile_shots.tscn

const OUT_DIR := "user://shots_mobile/"

# iPhone 16 Pro is 2622x1206 at devicePixelRatio 3 -> 874x402 CSS points. Using
# half the pixels with half the ratio keeps the same reference size (and so the
# same layout decisions) while fitting inside a desktop monitor.
const LANDSCAPE := Vector2i(1311, 603)
const PORTRAIT := Vector2i(603, 1311)
const RATIO := 1.5

var main: Node


func _ready() -> void:
	seed(99)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _settle(1.0)

	# Force the touch path: OS.get_name() is "Windows" here, so the real
	# detection would correctly say desktop.
	Layout.touch_primary = true
	Layout._pixel_ratio = RATIO

	main._start_new_run()
	await _settle(0.6)

	await _shot_mode(PORTRAIT, "phone_portrait")
	await _shot_mode(LANDSCAPE, "phone_landscape")
	await _test_rotation()
	_verify_drag_gain()

	print("form=%s portrait=%s scale=%.2f logical=%s" % [
		Layout.form, Layout.portrait, get_window().content_scale_factor, Layout.logical_size()])
	print("shots -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot_mode(size: Vector2i, tag: String) -> void:
	DisplayServer.window_set_size(size)
	await _settle(0.8)
	var session: GameSession = main.session
	var hud: HUD = main._hud

	for c in range(0, session.grid_cols - 3):
		session.board[session.grid_rows - 1][c] = session._make_block(Cfg.ORANGE)
	for c in range(0, 3):
		session.board[session.grid_rows - 2][c] = session._make_block(Cfg.CYAN)
	session.board_changed.emit()
	await _settle(0.3)
	await _shot(tag + "_idle")

	print("  [%s] board=%s cell=%.0f grid=%s lane=%s" % [
		tag, hud.board.size, hud.board.cell_size, hud.board.grid_rect().size, hud._lane.size])

	# Mid-drag: piece floating above the finger, ghost on the board.
	if not session.hand.is_empty():
		var board: BoardView = hud.board
		var rect := board.grid_rect()
		var finger := board.get_global_transform() * (rect.position + rect.size * Vector2(0.55, 0.62))
		board.begin_drag(session.hand[0], 0, finger)
		board.update_drag(finger)
		await _settle(0.4)
		await _shot(tag + "_dragging")
		board.cancel_drag()
		await _settle(0.2)

	session.generate_shop_offers()
	main._open_shop()
	await _settle(0.9)
	await _shot(tag + "_shop")
	if main._active_screen:
		main._active_screen.close()
	await _settle(0.4)


## Rotating the device mid-game has to re-flow the HUD *and* any screen that is
## already open, which is the case that used to be left mis-shaped.
func _test_rotation() -> void:
	DisplayServer.window_set_size(PORTRAIT)
	await _settle(0.8)
	main.session.generate_shop_offers()
	main._open_shop()
	await _settle(0.9)
	var before: String = main._hud._built_mode

	DisplayServer.window_set_size(LANDSCAPE)
	await _settle(1.0)
	await _shot("rotate_shop_open_landscape")
	print("  rotation with shop open: hud %s -> %s %s" % [
		before, main._hud._built_mode,
		"OK" if main._hud._built_mode == "phone_landscape" else "FAIL"])

	if main._active_screen:
		main._active_screen.close()
	await _settle(0.5)

	DisplayServer.window_set_size(PORTRAIT)
	await _settle(1.0)
	await _shot("rotate_back_portrait_game")
	print("  rotation back in game: hud=%s %s" % [
		main._hud._built_mode, "OK" if main._hud._built_mode == "portrait" else "FAIL"])


## The piece must track finger *motion* amplified by the gain, not the finger
## position. Checked numerically because it is nearly impossible to eyeball.
func _verify_drag_gain() -> void:
	var session: GameSession = main.session
	var board: BoardView = main._hud.board
	if session.hand.is_empty():
		session.generate_hand()

	for mode in [BoardView.PLACEMENT_DEFAULT, BoardView.PLACEMENT_DIRECT]:
		SaveGame.placement_mode = mode
		var rect := board.grid_rect()
		var finger := board.get_global_transform() * (rect.position + rect.size * 0.5)
		board.begin_drag(session.hand[0], 0, finger)
		var start := board.piece_centre()
		var delta := Vector2(40, -50)
		board.update_drag(finger + delta)
		var moved := board.piece_centre() - start
		board.cancel_drag()
		var want: float = 1.0 if mode == BoardView.PLACEMENT_DIRECT else BoardView.DRAG_GAIN
		var ok: bool = moved.is_equal_approx(delta * want)
		print("  placement mode %d: finger %s -> piece %s (expected %.1fx) %s" % [
			mode, delta, moved, want, "OK" if ok else "FAIL"])
	SaveGame.placement_mode = BoardView.PLACEMENT_DEFAULT


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name + ".png")
	print("  wrote ", shot_name, " ", img.get_size())
