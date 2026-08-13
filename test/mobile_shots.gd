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
	Layout._detected_touch = true

	main._start_new_run()
	await _settle(0.6)

	await _shot_mode(PORTRAIT, "phone_portrait")
	await _shot_mode(LANDSCAPE, "phone_landscape")
	await _test_rotation()
	_verify_drag_gain()
	_verify_touch_metrics()
	await _verify_touch_override()
	await _verify_shop_drag_scroll()
	await _verify_menu_round_trip()
	await _verify_burst_budget()

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

	print("  [%s] mode=%s form=%d logical=%s board=%s cell=%.0f lane=%s" % [
		tag, hud._built_mode, Layout.form, Layout.logical_size(),
		hud.board.size, hud.board.cell_size, hud._lane.size])

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

	# Settings is the densest screen in the game and the one most likely to fall
	# back to desktop metrics, so it gets captured mid-run (where it doubles as
	# the pause menu) and scrolled to the bottom.
	main._open_settings(false)
	await _settle(0.9)
	await _shot(tag + "_settings")
	_check_fits(tag + " settings", main._modal)
	var scroll := _find_scroll(main._modal)
	if scroll:
		scroll.scroll_vertical = 100000
		await _settle(0.4)
		await _shot(tag + "_settings_bottom")
		print("  [%s] settings scroll %d of %d px" % [
			tag, scroll.scroll_vertical, scroll.get_v_scroll_bar().max_value])
	if main._modal:
		main._modal.close()
	await _settle(0.4)

	# The Sin Tree is the widest thing in the game (seven branches) squeezed onto
	# the narrowest screen, so it is worth a look in both orientations.
	Profile.reset_tree()
	Profile.embers = 0
	Profile.award_embers(400)
	Profile.buy(SinTreeData.NODES[0]["id"])
	main._open_sin_tree()
	await _settle(0.9)
	await _shot(tag + "_sin_tree")
	_check_fits(tag + " sin tree", main._modal)
	var tree_scroll := _find_scroll(main._modal)
	if tree_scroll:
		tree_scroll.scroll_vertical = 100000
		await _settle(0.4)
		await _shot(tag + "_sin_tree_bottom")
	if main._modal:
		main._modal.close()
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
		"OK" if main._hud._built_mode.begins_with("phone_landscape") else "FAIL"])

	if main._active_screen:
		main._active_screen.close()
	await _settle(0.5)

	DisplayServer.window_set_size(PORTRAIT)
	await _settle(1.0)
	await _shot("rotate_back_portrait_game")
	print("  rotation back in game: hud=%s %s" % [
		main._hud._built_mode, "OK" if main._hud._built_mode.begins_with("portrait") else "FAIL"])


## The piece must track finger *motion* amplified by the gain, not the finger
## position. Checked numerically because it is nearly impossible to eyeball.
func _verify_drag_gain() -> void:
	var session: GameSession = main.session
	var board: BoardView = main._hud.board
	if session.hand.is_empty():
		session.generate_hand()

	# Also covers the drag-speed slider: whatever it is set to is what the piece
	# actually travels, and Direct ignores it entirely.
	SaveGame.drag_gain = 1.5
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
		var want: float = 1.0 if mode == BoardView.PLACEMENT_DIRECT else SaveGame.drag_gain
		var ok: bool = moved.is_equal_approx(delta * want)
		print("  placement mode %d: finger %s -> piece %s (expected %.1fx) %s" % [
			mode, delta, moved, want, "OK" if ok else "FAIL"])
	SaveGame.placement_mode = BoardView.PLACEMENT_DEFAULT


## The mid-round crash, pinned.
##
## The board used to build one GPUParticles2D per cleared cell, each carrying its
## own process material, colour ramp texture and particle texture. A cross blast
## on a full board did that seventeen times over, and a good combo did it several
## times a second, until the browser tab hit its GPU memory ceiling and reloaded
## itself. Emitters must stay bounded no matter how much is cleared at once.
func _verify_burst_budget() -> void:
	var board: BoardView = main._hud.board
	var session: GameSession = main.session
	var whole_board: Array = []
	for r in session.grid_rows:
		for c in session.grid_cols:
			whole_board.append(Vector2i(r, c))

	# Six full-board clears back to back, which is worse than anything the game
	# can actually produce in one frame.
	for i in 6:
		board._on_cells_cleared(whole_board, "line")
	await get_tree().process_frame

	var emitters := 0
	for child in board.get_children():
		if child is GPUParticles2D:
			emitters += 1
	var naive: int = whole_board.size() * 6
	print("  burst budget: %d emitters after %d cleared cells (naive %d, cap %d) %s" % [
		emitters, whole_board.size() * 6, naive, BoardView.MAX_LIVE_BURSTS,
		"OK" if emitters <= BoardView.MAX_LIVE_BURSTS else "FAIL"])


## Nothing may reach past the side of the screen. Godot lays a container out past
## the edge rather than shrink a Button below its own label, so a screen that
## looks fine on a desktop can quietly run a third of itself off a phone - and
## unlike a clipped 3D model, there is no visual tell until you go looking.
func _check_fits(what: String, root: Node) -> void:
	if root == null:
		print("  %s width: SKIPPED (nothing open)" % what)
		return
	var limit: float = Layout.logical_size().x
	var worst := _overflow(root, limit, "")
	var over: float = worst[0]
	print("  %s fits %.0fpx wide: %s%s" % [
		what, limit, "OK" if over <= 1.0 else "FAIL",
		"" if over <= 1.0 else "  (%s overflows by %.0fpx)" % [worst[1], over]])


func _overflow(node: Node, limit: float, path: String) -> Array:
	var worst := 0.0
	var culprit := ""
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree():
			var over: float = c.get_global_rect().end.x - limit
			if over > worst:
				worst = over
				culprit = path
	for child in node.get_children():
		var sub := _overflow(child, limit, path + "/" + child.name)
		if sub[0] > worst:
			worst = sub[0]
			culprit = sub[1]
	return [worst, culprit]


func _find_scroll(node: Node) -> ScrollContainer:
	if node == null:
		return null
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll(child)
		if found:
			return found
	return null


## Tap targets and type are specified in physical points, so the check is done
## in points too: logical pixels alone say nothing about how big a control
## actually is under a thumb.
func _verify_touch_metrics() -> void:
	var pt: float = Layout.points_to_logical()
	var touch_pt: float = Layout.touch_size() / pt
	var body_pt: float = UIKit.font_size("body") / pt
	var tiny_pt: float = UIKit.font_size("tiny") / pt
	var lift_pt: float = Layout.drag_lift(main._hud.board.cell_size) / pt
	print("  touch target %.0fpt (min %.0f) %s" % [
		touch_pt, Layout.MIN_TOUCH_PT, "OK" if touch_pt >= Layout.MIN_TOUCH_PT - 0.5 else "FAIL"])
	print("  body text %.0fpt, caption %.0fpt %s" % [
		body_pt, tiny_pt, "OK" if body_pt >= 15.0 and tiny_pt >= 10.0 else "FAIL"])
	print("  drag lift %.0fpt %s" % [
		lift_pt, "OK" if lift_pt >= 90.0 else "FAIL"])


## The settings escape hatch has to re-flow the running game, not just store a
## number -- a player who needs to force the touch layout is already staring at
## a UI that mis-detected them, so "it applies next launch" is no use.
func _verify_touch_override() -> void:
	var hud: HUD = main._hud
	SaveGame.touch_override = 2
	Layout.refresh_touch_mode()
	await _settle(0.5)
	var mouse_px := Layout.touch_size()
	var mouse_mode: String = hud._built_mode

	SaveGame.touch_override = 1
	Layout.refresh_touch_mode()
	await _settle(0.5)
	var touch_px := Layout.touch_size()
	var touch_mode: String = hud._built_mode

	var ok: bool = touch_px > mouse_px \
		and not mouse_mode.ends_with("_touch") and touch_mode.ends_with("_touch")
	print("  touch override: Mouse -> %s %.0fpx, Touch -> %s %.0fpx %s" % [
		mouse_mode, mouse_px, touch_mode, touch_px, "OK" if ok else "FAIL"])

	SaveGame.touch_override = 0
	Layout.refresh_touch_mode()
	await _settle(0.5)


## The complaint that started this: on a phone the shop could only be scrolled
## from the gutters between the cards, because every panel and Buy button ate
## the drag. Dragging from *on top of* a Buy button must scroll and must not
## buy -- and a plain tap on that same button must still buy.
func _verify_shop_drag_scroll() -> void:
	DisplayServer.window_set_size(PORTRAIT)
	await _settle(0.8)
	main.session.money = 999
	main.session.generate_shop_offers()
	main._open_shop()
	await _settle(0.9)

	var shop: Node = main._active_screen
	var scroll := _find_scroll(shop)
	var buy := _find_button(shop, "Buy")
	if scroll == null or buy == null:
		print("  shop drag-scroll: SKIPPED (no scroll view or no affordable offer)")
		return

	var start: Vector2 = buy.get_global_rect().get_center()
	var before_scroll: int = scroll.scroll_vertical
	var before_money: int = main.session.money
	var before_cards: int = main.session.cards.size() + main.session.items.size()

	await _drag(start, Vector2(0, -30), 6)
	await _settle(0.4)
	var scrolled: int = scroll.scroll_vertical - before_scroll
	var bought: bool = main.session.money != before_money \
		or main.session.cards.size() + main.session.items.size() != before_cards
	print("  shop drag from a Buy button: scrolled %dpx, bought=%s %s" % [
		scrolled, bought, "OK" if scrolled > 40 and not bought else "FAIL"])

	# A tap on the same control must still go through, or the fix has simply
	# traded one broken interaction for another.
	buy = _find_button(shop, "Buy")
	if buy != null:
		before_money = main.session.money
		await _tap(buy.get_global_rect().get_center())
		await _settle(0.4)
		var tapped: bool = main.session.money != before_money
		print("  tap on a Buy button still buys: %s %s" % [tapped, "OK" if tapped else "FAIL"])

	if main._active_screen:
		main._active_screen.close()
	await _settle(0.4)


## Going back to the menu now tears the HUD down to release its 3D viewports,
## which is only safe if walking straight back into a run rebuilds it. A blank
## playfield here would be a far worse bug than the one that motivated it.
func _verify_menu_round_trip() -> void:
	var hud: HUD = main._hud
	var icons_before: int = hud._previews.size()
	main._show_main_menu()
	await _settle(0.7)
	var released: bool = not hud._built and hud._previews.is_empty()

	main._start_new_run()
	await _settle(0.9)
	var rebuilt: bool = hud._built and hud.visible \
		and hud._previews.size() > 0 and hud.board.get_parent() != null
	print("  menu round trip: released=%s rebuilt=%s (%d -> 0 -> %d slots) %s" % [
		released, rebuilt, icons_before, hud._previews.size(),
		"OK" if released and rebuilt else "FAIL"])
	await _shot("after_menu_round_trip")


func _find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).text.begins_with(prefix) \
			and not (node as Button).disabled:
		return node
	for child in node.get_children():
		var found := _find_button(child, prefix)
		if found:
			return found
	return null


func _drag(from: Vector2, step: Vector2, steps: int) -> void:
	_press(from)
	var at := from
	for i in steps:
		at += step
		var move := InputEventMouseMotion.new()
		move.position = at
		move.global_position = at
		move.relative = step
		Input.parse_input_event(move)
		await get_tree().process_frame
	_release(at)


func _tap(at: Vector2) -> void:
	_press(at)
	await get_tree().process_frame
	_release(at)


func _press(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


func _release(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name + ".png")
	print("  wrote ", shot_name, " ", img.get_size())
