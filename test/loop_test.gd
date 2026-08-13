extends Node
## Headless soak test for the rules engine. Drives thousands of turns with a
## simple bot, forces every card / item / contract path, and asserts the
## invariants that matter. Run with:
##   godot --headless --path . res://test/loop_test.tscn

var failures: Array[String] = []
var checks := 0

var session: GameSession
var screens_seen := {}
var rounds_reached := 0
var lines_total := 0
var game_overs := 0


func _ready() -> void:
	seed(1337)
	print("=== Block X Hell loop test ===")
	_test_shapes()
	_test_session_basics()
	_test_line_clearing()
	_test_column_collapse()
	_test_all_cards()
	_test_all_items()
	_test_content_is_wired()
	_test_contracts()
	_test_save_round_trip()
	_test_boss_cycle()
	_test_full_soak()
	_test_layout_math()
	_report()


# ==========================================================================
#  Helpers
# ==========================================================================
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("  FAIL: ", label)


func fresh() -> GameSession:
	if session != null and is_instance_valid(session):
		session.queue_free()
	session = GameSession.new()
	add_child(session)
	session.request_screen.connect(_on_screen)
	session.lines_cleared.connect(func(count: int, _r: Array, _c: Array): lines_total += count)
	session.start_new_run()
	return session


func _on_screen(screen: String) -> void:
	screens_seen[screen] = int(screens_seen.get(screen, 0)) + 1
	# Emulate what the UI layer does when each screen closes.
	match screen:
		"shop":
			session.exit_shop()
		"perks":
			if not session.perk_offers.is_empty():
				session.choose_perk(0)
		"lucifer":
			if not session.lucifer_offers.is_empty():
				session.choose_contract(0)
		"gameover":
			game_overs += 1


func board_is_well_formed(s: GameSession) -> bool:
	if s.board.size() != s.grid_rows:
		return false
	for row in s.board:
		if (row as Array).size() != s.grid_cols:
			return false
	return true


## Place the selected piece at the first legal cell. Returns false if stuck.
func bot_move(s: GameSession) -> bool:
	if s.hand.is_empty():
		s.generate_hand()
	var stamp := s.soul_stamp_armed()
	for i in s.hand.size():
		var shape: Dictionary = s.hand[i]
		for r in s.grid_rows:
			for c in s.grid_cols:
				if s.is_valid_placement(shape, r, c, stamp):
					s.selected_index = i
					return s.place_piece(shape, r, c)
	return false


## Place pieces wherever they best complete a line, to force clears.
func bot_greedy_move(s: GameSession) -> bool:
	if s.hand.is_empty():
		s.generate_hand()
	var stamp := s.soul_stamp_armed()
	var best_score := -1
	var best: Array = []
	for i in s.hand.size():
		var shape: Dictionary = s.hand[i]
		for r in s.grid_rows:
			for c in s.grid_cols:
				if not s.is_valid_placement(shape, r, c, stamp):
					continue
				var score := _fill_score(s, shape, r, c)
				if score > best_score:
					best_score = score
					best = [i, r, c]
	if best.is_empty():
		return false
	s.selected_index = best[0]
	return s.place_piece(s.hand[best[0]], best[1], best[2])


func _fill_score(s: GameSession, shape: Dictionary, r: int, c: int) -> int:
	var occupied := {}
	for off in shape["coords"]:
		occupied[Vector2i(r + off.x, c + off.y)] = true
	var total := 0
	for row in s.grid_rows:
		var filled := 0
		for col in s.grid_cols:
			if s.is_clearable(s.board[row][col]) or occupied.has(Vector2i(row, col)):
				filled += 1
		if filled == s.grid_cols:
			total += 100
		else:
			total += filled
	for col in s.grid_cols:
		var filled := 0
		for row in s.grid_rows:
			if s.is_clearable(s.board[row][col]) or occupied.has(Vector2i(row, col)):
				filled += 1
		if filled == s.grid_rows:
			total += 100
		else:
			total += filled
	return total


# ==========================================================================
#  Tests
# ==========================================================================
func _test_shapes() -> void:
	print("- shape table")
	check(Cfg.SHAPES.size() == 14, "14 shapes defined")
	for shape in Cfg.SHAPES:
		check(not (shape["coords"] as Array).is_empty(), "shape %s has cells" % shape["name"])
	# Rotating four times returns the original footprint.
	var square := Cfg.copy_shape(Cfg.shape_by_name("L"))
	var start: Array = square["coords"].duplicate()
	var coords: Array = start.duplicate()
	for _i in 4:
		coords = Cfg.rotate_shape_coords(coords)
	check(coords.size() == start.size(), "rotation preserves cell count")
	var as_set := {}
	for v in coords:
		as_set[v] = true
	for v in start:
		check(as_set.has(v), "rotation x4 restores L footprint")


func _test_session_basics() -> void:
	print("- session setup")
	var s := fresh()
	check(board_is_well_formed(s), "board dimensions")
	check(s.money == Cfg.STARTING_MONEY, "starting money")
	check(s.hand.size() >= 2, "starting hand dealt")
	check(s.round_count == 1, "starts at round 1")
	check(s.max_cards == Cfg.INITIAL_MAX_CARDS, "card slots")

	var before := s.hand.size()
	check(bot_move(s), "first placement succeeds")
	check(s.hand.size() == before - 1 or s.hand.size() >= 2, "hand shrinks or refills")
	check(board_is_well_formed(s), "board intact after placement")


func _test_line_clearing() -> void:
	print("- line clear + scoring")
	var s := fresh()
	# Fill row 0 except the last cell, then drop a single block into the gap.
	for c in s.grid_cols - 1:
		s.board[0][c] = s._make_block(Cfg.CYAN)
	var dot := Cfg.copy_shape(Cfg.shape_by_name("Dot1"))
	s.hand = [dot]
	s.selected_index = 0
	var score_before := s.score
	var money_before := s.money
	s.place_piece(dot, 0, s.grid_cols - 1)
	check(s.score > score_before, "line clear awards score")
	check(s.money > money_before, "line clear awards money")
	check(s.combo_streak == 1, "line clear starts combo")
	var row_clear := true
	for c in s.grid_cols:
		if s.is_clearable(s.board[0][c]):
			row_clear = false
	check(row_clear, "cleared row is empty")
	check(board_is_well_formed(s), "board intact after clear")

	# Obstacles must block a row from ever counting as full.
	var s2 := fresh()
	s2.board[0][0] = s2._make_obstacle()
	for c in range(1, s2.grid_cols):
		s2.board[0][c] = s2._make_block(Cfg.CYAN)
	check(s2.check_and_clear_lines() == 0, "obstacle row does not clear")


func _test_column_collapse() -> void:
	print("- column collapse")
	var s := fresh()
	# Fill column 2 completely; everything to its right shifts left.
	for r in s.grid_rows:
		s.board[r][2] = s._make_block(Cfg.RED)
	s.board[0][5] = s._make_block(Cfg.GREEN)
	var cleared := s.check_and_clear_lines()
	check(cleared == 1, "one column cleared")
	check(board_is_well_formed(s), "board intact after column collapse")
	check(s.is_clearable(s.board[0][4]), "right-hand block shifted left by one")

	# Obstacles ride the collapse instead of vanishing.
	var s2 := fresh()
	for r in s2.grid_rows:
		s2.board[r][0] = s2._make_block(Cfg.RED)
	s2.board[3][0] = s2._make_obstacle()
	check(s2.check_and_clear_lines() == 0, "column with obstacle does not clear")


func _test_all_cards() -> void:
	print("- every card")
	for entry in Cards.CARDS:
		var s := fresh()
		s.add_card(entry["name"])
		check(s.cards.size() == 1, "%s added" % entry["name"])
		check(board_is_well_formed(s), "%s keeps board well-formed" % entry["name"])
		check(Cards.asset_key(entry["name"]) != "", "%s has an asset key" % entry["name"])
		var key: String = Cards.asset_key(entry["name"])
		# Sculpted entries ship a .glb, later ones a primitive-mesh .tscn; asking
		# Cards is the only check that does not care which.
		check(Cards.model_scene(key) != null, "%s has a 3D model (%s)" % [entry["name"], key])

		# Tap and double-tap must never throw, whatever the card is.
		s.activate_card(0, false)
		s.activate_card(0, true)
		check(board_is_well_formed(s), "%s survives activation" % entry["name"])

		# Play a handful of turns with the card equipped.
		for _t in 12:
			if not bot_greedy_move(s):
				break
		check(board_is_well_formed(s), "%s survives play" % entry["name"])
		check(s.money >= 0, "%s never drives money negative" % entry["name"])
		check(s.combo_miss_allowance >= 0, "%s keeps chances >= 0" % entry["name"])
		check(s.combo_miss_allowance <= Cfg.MAX_COMBO_CHANCES + s.combo_allowance_bonus,
			"%s keeps chances within max" % entry["name"])

	# Targeted card specifics.
	var d := fresh()
	d.add_card("Downsize")
	check(d.grid_rows < Cfg.GRID_ROWS_DEFAULT or d.grid_cols < Cfg.GRID_COLS_DEFAULT,
		"Downsize shrinks the grid")
	check(board_is_well_formed(d), "Downsize leaves board well-formed")
	d.sell_card(0)
	check(board_is_well_formed(d), "selling Downsize leaves board well-formed")

	var m := fresh()
	m.add_card("The Mimic")
	m.add_card("Terraform")
	check(m.set_mimic_target(0, "Terraform"), "Mimic copies Terraform")
	check(m.effective_name(m.cards[0]) == "Terraform", "Mimic reports copied name")
	check(not m.set_mimic_target(0, "Terraform"), "Mimic change is once per round")

	var e := fresh()
	e.add_card("Efficiency Expert")
	check(e.sets_per_round_target == Cfg.SETS_PER_ROUND_DEFAULT - 1, "Efficiency Expert shortens rounds")

	var st := fresh()
	var base_allowance := st.combo_miss_allowance
	st.add_card("Star Streak")
	check(st.combo_miss_allowance == base_allowance + 1, "Star Streak grants an extra miss")

	var pk := fresh()
	pk.add_card("Pocket Dimension")
	var pocket_name: String = pk.hand[0]["name"]
	pk.pocket_piece(0)
	check(pk.pocketed_piece != null, "piece goes into the pocket")
	check(pk.pocketed_piece["name"] == pocket_name, "pocket keeps the right piece")
	pk.unpocket_piece()
	check(pk.pocketed_piece == null, "pocket empties again")

	var br := fresh()
	br.add_card("Barrel")
	var before_coords: Array = br.hand[0]["coords"].duplicate()
	br.selected_index = 0
	br.activate_card(0)
	check(br.hand[0]["coords"] != before_coords or before_coords.size() == 1,
		"Barrel rotates the selected piece")

	var perf := fresh()
	perf.add_card("Perfectionist")
	for c in perf.grid_cols - 1:
		perf.board[0][c] = perf._make_block(Cfg.CYAN)
	var dot2 := Cfg.copy_shape(Cfg.shape_by_name("Dot1"))
	perf.hand = [dot2]
	perf.selected_index = 0
	perf.place_piece(dot2, 0, perf.grid_cols - 1)
	check(perf.score >= Cfg.PERFECTIONIST_BONUS, "Perfectionist pays out on a clear board")


func _test_all_items() -> void:
	print("- every item")
	for entry in Cards.ITEMS:
		var s := fresh()
		# Give every item something to act on. Several of them deliberately
		# refuse to be spent on a board where they would do nothing, so an empty
		# board tests the refusal path rather than the effect.
		_stock_board_for_items(s)
		s.items.append(Cards.new_item_instance(entry["name"]))
		check(s.use_item(0), "%s activates" % entry["name"])
		var key: String = Cards.asset_key(entry["name"])
		check(Cards.model_scene(key) != null, "%s has a 3D model" % entry["name"])

		# Items come in three shapes and the test has to tell them apart by what
		# the item did, not by name, or every item added later needs a new case.
		if s.conjure_active:
			# Held until the player picks, so it is spent on the pick, not the use.
			var hand_before := s.hand.size()
			s.conjure_piece("O")
			check(s.hand.size() == hand_before + 1, "%s adds the conjured piece" % entry["name"])
			check(not s.conjure_active, "%s closes the picker" % entry["name"])
			check(s.items.is_empty(), "%s is consumed by the pick" % entry["name"])
		elif not s.pending_effect.is_empty():
			check(s.items.is_empty(), "%s is consumed" % entry["name"])
			# Fill a patch so the effect has something to destroy.
			for r in 4:
				for c in 4:
					s.board[r][c] = s._make_block(Cfg.BLUE)
			s.apply_clear_effect(s.pending_effect["type"], 1, 1, int(s.pending_effect.get("size", 3)))
			check(s.pending_effect.is_empty(), "%s clears its pending state" % entry["name"])
		else:
			# Instant: no picker, no target, it just happened.
			check(s.items.is_empty(), "%s is consumed" % entry["name"])
		check(board_is_well_formed(s), "%s keeps board well-formed" % entry["name"])
		check(s.money >= 0, "%s never drives money negative" % entry["name"])

		# Whatever it did, the run must still be playable afterwards.
		for _t in 8:
			if not bot_greedy_move(s):
				break
		check(board_is_well_formed(s), "%s survives play" % entry["name"])

	# An item that cannot do anything must say so and stay in the bag. Getting
	# this wrong is how a player pays 10 gold for a message telling them nothing
	# happened, so it is checked on the empty board every item refuses.
	for entry in Cards.ITEMS:
		var s := fresh()
		s.items.append(Cards.new_item_instance(entry["name"]))
		if s.use_item(0):
			continue
		check(s.items.size() == 1, "%s is kept when it is refused" % entry["name"])
		check(s.pending_effect.is_empty(), "%s arms nothing when refused" % entry["name"])
		check(not s.conjure_active, "%s opens no picker when refused" % entry["name"])


## Every table entry must be named somewhere in the rules engine.
##
## The failure this catches is a content table that grew without the code that
## makes it mean anything: the card buys, equips, shows its model and passes
## every behavioural check above, because it does nothing at all. Reading the
## source is crude, but a card that game_session.gd never mentions cannot
## possibly have an effect, and nothing else notices.
func _test_content_is_wired() -> void:
	print("- every entry is wired up")
	var file := FileAccess.open("res://scripts/core/game_session.gd", FileAccess.READ)
	if file == null:
		check(false, "game_session.gd is readable")
		return
	var src := file.get_as_text()
	file.close()
	for table in [Cards.CARDS, Cards.ITEMS, Cards.PERKS]:
		for entry: Dictionary in table:
			var entry_name: String = entry["name"]
			check(src.contains('"%s"' % entry_name),
				"%s is referenced in the rules engine" % entry_name)


## A board with loose blocks, a couple of obstacles and an active boss, so every
## item in the table has a legal target no matter what it does.
func _stock_board_for_items(s: GameSession) -> void:
	for c in s.grid_cols - 2:
		s.board[s.grid_rows - 1][c] = s._make_block(Cfg.ORANGE)
	for c in 3:
		s.board[s.grid_rows - 4][c] = s._make_block(Cfg.CYAN)
	s.board[1][1] = s._make_obstacle()
	s.board[2][4] = s._make_obstacle()
	s.obstacles_on_board = true
	s.boss_active = true
	s.board_changed.emit()


func _test_contracts() -> void:
	print("- contracts")
	for entry in Cards.CONTRACTS:
		var s := fresh()
		s.generate_lucifer_offers()
		check(s.lucifer_offers.size() > 0, "Lucifer offers generated")
		s.contracts.append({
			"name": entry["name"], "description": entry["description"],
			"condition_text": entry["condition_text"],
			"condition_deadline": 2, "expiration": 6, "condition_met": false,
		})
		s.recalculate_passives()
		for _t in 40:
			if not bot_greedy_move(s):
				break
		check(board_is_well_formed(s), "%s keeps board well-formed" % entry["name"])
		check(s.money >= 0, "%s never drives money negative" % entry["name"])

	# Underdog blocks items outright.
	var u := fresh()
	u.contracts.append({"name": "Underdog", "condition_deadline": 3, "expiration": 9, "condition_met": false})
	u.items.append(Cards.new_item_instance("Eraser"))
	check(not u.use_item(0), "Underdog curse blocks item use")
	check(not u.buy_shop_entry("item", 0), "Underdog curse blocks buying")

	# Eternal Youth revives instead of ending the run.
	var y := fresh()
	y.contracts.append({"name": "Eternal Youth", "condition_deadline": 5, "expiration": 9, "condition_met": false})
	y.score = 1000
	y.round_count = 8
	y.check_game_over("test", true)
	check(not y.is_game_over, "Eternal Youth prevents game over")
	check(y.score == 500, "Eternal Youth halves score")
	check(y.round_count == 4, "Eternal Youth halves rounds")
	check(y.find_contract("Eternal Youth") == null, "Eternal Youth is consumed")

	# Deal with Death does the same, one time.
	var dd := fresh()
	dd.add_card("Deal with Death")
	dd.money = 50
	dd.check_game_over("test", true)
	check(not dd.is_game_over, "Deal with Death prevents game over")
	check(dd.money == 0, "Deal with Death zeroes money")
	check(dd.find_card("Deal with Death") == null, "Deal with Death is destroyed")
	dd.check_game_over("test", true)
	check(dd.is_game_over, "second death is final")


func _test_save_round_trip() -> void:
	print("- save / load")
	var s := fresh()
	s.add_card("Terraform")
	s.add_card("The Mimic")
	s.set_mimic_target(1, "Terraform")
	s.add_perk("Score Boost Perk")
	s.items.append(Cards.new_item_instance("Wide Bomb"))
	s.contracts.append({"name": "Greedy", "condition_deadline": 3, "expiration": 8, "condition_met": false})
	for _t in 9:
		bot_greedy_move(s)
	s.board[0][0] = s._make_obstacle()
	s.board[1][1] = s._make_block(Cfg.YELLOW)
	s.board[1][1]["a"] = true
	s.board[1][1]["o"] = Cfg.CYAN

	var snapshot := s.to_save_dict()
	# Force it through JSON exactly as the disk path does.
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(snapshot))
	check(round_tripped is Dictionary, "save serialises to JSON")

	var loaded := GameSession.new()
	add_child(loaded)
	check(loaded.from_save_dict(round_tripped), "save loads back")
	check(loaded.grid_rows == s.grid_rows and loaded.grid_cols == s.grid_cols, "grid size restored")
	check(loaded.score == s.score, "score restored")
	check(loaded.money == s.money, "money restored")
	check(loaded.round_count == s.round_count, "round restored")
	check(loaded.cards.size() == s.cards.size(), "cards restored")
	check(loaded.effective_name(loaded.cards[1]) == "Terraform", "mimic target restored")
	check(loaded.items.size() == s.items.size(), "items restored")
	check(loaded.perks.size() == s.perks.size(), "perks restored")
	check(loaded.contracts.size() == s.contracts.size(), "contracts restored")
	check(loaded.is_obstacle(loaded.board[0][0]), "obstacle restored")
	check(bool(loaded.board[1][1].get("a", false)), "angel's kiss mark restored")
	check(board_is_well_formed(loaded), "loaded board well-formed")
	# Passives must be live again after a load.
	check(loaded.passive.get("score_multiplier_bonus", 0.0) >= 0.5, "perks recalculated on load")
	loaded.queue_free()


func _test_boss_cycle() -> void:
	print("- giga boss")
	var s := fresh()
	s.boss_active = true
	s._choose_next_boss_target()
	check(s.boss_warning_active, "boss telegraphs its next target")
	check(s.boss_next_line >= 0, "boss picks a line")

	# Fill the targeted line, then place: the laser must destroy it.
	var line := s.boss_next_line
	var is_row := s.boss_next_is_row
	if is_row:
		for c in s.grid_cols:
			s.board[line][c] = s._make_block(Cfg.BLUE)
	else:
		for r in s.grid_rows:
			s.board[r][line] = s._make_block(Cfg.BLUE)
	# The filled line clears itself first; refill afterwards to observe the laser.
	s.check_and_clear_lines()
	if is_row:
		for c in s.grid_cols - 1:
			s.board[line][c] = s._make_block(Cfg.BLUE)
	else:
		for r in s.grid_rows - 1:
			s.board[r][line] = s._make_block(Cfg.BLUE)

	var dot := Cfg.copy_shape(Cfg.shape_by_name("Dot1"))
	s.hand = [dot]
	s.selected_index = 0
	var placed := false
	for r in s.grid_rows:
		for c in s.grid_cols:
			if not placed and s.is_valid_placement(dot, r, c, false):
				placed = s.place_piece(dot, r, c)
	check(placed, "placement during a boss round works")
	check(board_is_well_formed(s), "board intact after laser")
	check(s.boss_warning_active, "boss re-telegraphs after firing")


func _test_full_soak() -> void:
	print("- soak: 6 runs x up to 900 turns")
	for run_index in 6:
		var s := fresh()
		var turns := 0
		while turns < 900 and not s.is_game_over:
			turns += 1
			var moved := bot_greedy_move(s) if turns % 3 else bot_move(s)
			if not moved:
				s.check_game_over("soak: no move")
				if not s.is_game_over:
					# Revived by a card/contract -- keep going.
					s.generate_hand()
					continue
				break
			if not board_is_well_formed(s):
				check(false, "board malformed during soak run %d turn %d" % [run_index, turns])
				break
			if s.money < 0:
				check(false, "money went negative during soak")
				break
			if s.combo_miss_allowance < 0:
				check(false, "chances went negative during soak")
				break
			# Buy something whenever the shop leaves stock and we can afford it.
			if not s.shop_offers["cards"].is_empty() and s.money > 40:
				s.buy_shop_entry("card", 0)
		rounds_reached = maxi(rounds_reached, s.round_count)
	check(rounds_reached >= 3, "soak reaches at least round 3 (got %d)" % rounds_reached)
	check(lines_total > 0, "soak cleared lines (got %d)" % lines_total)
	check(int(screens_seen.get("shop", 0)) > 0, "soak opened the shop")
	print("    rounds reached: %d, lines cleared: %d, screens: %s" % [rounds_reached, lines_total, screens_seen])


func _test_layout_math() -> void:
	print("- responsive layout")
	var sizes: Array[Vector2i] = [
		Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 768),
		Vector2i(2400, 1080), Vector2i(1080, 2400), Vector2i(768, 1024), Vector2i(390, 844),
	]
	for size in sizes:
		var cell := Layout.cell_size_for(Vector2(size) * 0.55, 12, 12)
		check(cell >= 18.0 and cell <= 96.0, "cell size in range at %s (got %f)" % [size, cell])
		# The board area must still hold a default grid at a readable cell size.
		var default_cell := Layout.cell_size_for(Vector2(size) * 0.5, Cfg.GRID_ROWS_DEFAULT, Cfg.GRID_COLS_DEFAULT)
		check(default_cell >= 18.0, "default grid readable at %s (got %f)" % [size, default_cell])
	check(Layout.touch_size() >= 40.0, "touch targets are at least 40px")
	# The grid must fit inside a phone-portrait board area at max grid size.
	var phone_cell := Layout.cell_size_for(Vector2(360, 420), Cfg.MAX_GRID_ROWS, Cfg.MAX_GRID_COLS)
	check(phone_cell * Cfg.MAX_GRID_COLS <= 360.0, "12x12 grid fits a narrow phone board area")


# ==========================================================================
func _report() -> void:
	print("=== %d checks, %d failures ===" % [checks, failures.size()])
	for f in failures:
		print("  * ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
