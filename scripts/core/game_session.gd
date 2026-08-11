class_name GameSession
extends Node
## Full port of game_state.py -- board, scoring, combos, all 22 cards, 5 items,
## 4 perks, 5 contracts, the Giga Boss and every game-over path.
##
## This node owns no visuals. It mutates state and emits signals; scenes render
## from those signals. That split is what makes the loop testable headlessly.

# ------------------------------------------------------------------ signals
signal board_changed
signal grid_resized
signal hand_changed
signal inventory_changed
signal stats_changed
signal combo_changed(streak: int, chances: int)
signal message_posted(text: String, color: Color, duration: float)
signal floating_score(text: String, kind: String)
signal piece_placed(cells: Array, color: Color)
signal cells_cleared(cells: Array, kind: String)
signal lines_cleared(count: int, rows: Array, cols: Array)
signal boss_state_changed
signal boss_fired(is_row: bool, line: int)
signal pending_effect_changed
signal request_screen(screen: String)
signal card_triggered(card_name: String)
signal run_started
signal game_over

# ------------------------------------------------------------ cell helpers
## A cell is either int 0 (empty) or a Dictionary:
##   k: 1 = placed block, 2 = obstacle
##   c: display Color
##   a: true when marked by Angel's Kiss
##   o: original Color underneath an Angel's Kiss mark
const K_BLOCK := 1
const K_OBSTACLE := 2

# ------------------------------------------------------------------- state
var grid_rows := Cfg.GRID_ROWS_DEFAULT
var grid_cols := Cfg.GRID_COLS_DEFAULT
var board: Array = []

var hand: Array = []                 # Array[Dictionary] of shape dicts
var selected_index := 0
var ghost_pos := Vector2i.ZERO
var pocketed_piece: Variant = null

var score := 0
var money := Cfg.STARTING_MONEY
var round_count := 1
var sets_placed_in_round := 1
var sets_per_round_target := Cfg.SETS_PER_ROUND_DEFAULT

var cards: Array = []
var items: Array = []
var perks: Array = []
var contracts: Array = []
var max_cards := Cfg.INITIAL_MAX_CARDS
var max_items := Cfg.INITIAL_MAX_ITEMS

var combo_streak := 0
var combo_miss_allowance := Cfg.MAX_COMBO_CHANCES
var combo_allowance_bonus := 0

var passive := {}
var obstacles_on_board := false
var is_game_over := false

var pending_effect: Dictionary = {}   # {type, size, source}
var potential_clear_cells: Array = []
var conjure_active := false

var shop_offers := {"cards": [], "items": []}
var shop_reroll_cost := Cfg.SHOP_REROLL_BASE_COST
var perk_offers: Array = []
var lucifer_offers: Array = []

# Giga Boss
var boss_active := false
var boss_laser_line := -1
var boss_laser_is_row := false
var boss_warning_active := false
var boss_next_line := -1
var boss_next_is_row := false

var _clear_lock := false   # guards re-entrant clears during cascades


func _init() -> void:
	reset_run()


# ==========================================================================
#  Setup / lifecycle
# ==========================================================================
func reset_run() -> void:
	grid_rows = Cfg.GRID_ROWS_DEFAULT
	grid_cols = Cfg.GRID_COLS_DEFAULT
	_make_empty_board()

	hand = []
	selected_index = 0
	ghost_pos = Vector2i(grid_rows / 2, grid_cols / 2)
	pocketed_piece = null

	score = 0
	money = Cfg.STARTING_MONEY
	round_count = 1
	sets_placed_in_round = 1
	sets_per_round_target = Cfg.SETS_PER_ROUND_DEFAULT

	cards = []
	items = []
	perks = []
	contracts = []
	max_cards = Cfg.INITIAL_MAX_CARDS
	max_items = Cfg.INITIAL_MAX_ITEMS

	combo_streak = 0
	combo_allowance_bonus = 0
	combo_miss_allowance = Cfg.MAX_COMBO_CHANCES

	obstacles_on_board = false
	is_game_over = false
	pending_effect = {}
	potential_clear_cells = []
	conjure_active = false

	shop_offers = {"cards": [], "items": []}
	shop_reroll_cost = Cfg.SHOP_REROLL_BASE_COST
	perk_offers = []
	lucifer_offers = []

	boss_active = false
	boss_laser_line = -1
	boss_laser_is_row = false
	boss_warning_active = false
	boss_next_line = -1
	boss_next_is_row = false

	recalculate_passives()


func start_new_run() -> void:
	reset_run()
	generate_hand()
	Juice.reset()
	run_started.emit()
	board_changed.emit()
	stats_changed.emit()
	inventory_changed.emit()
	combo_changed.emit(combo_streak, combo_miss_allowance)


func _make_empty_board() -> void:
	board = []
	for r in grid_rows:
		var row: Array = []
		row.resize(grid_cols)
		row.fill(0)
		board.append(row)


# ==========================================================================
#  Cell predicates
# ==========================================================================
func cell_at(r: int, c: int) -> Variant:
	if r < 0 or r >= grid_rows or c < 0 or c >= grid_cols:
		return 0
	return board[r][c]


func is_empty_cell(cell: Variant) -> bool:
	return not (cell is Dictionary)


func is_obstacle(cell: Variant) -> bool:
	return cell is Dictionary and cell.get("k", K_BLOCK) == K_OBSTACLE


## "Clearable" means a placed block: not empty, not an obstacle.
func is_clearable(cell: Variant) -> bool:
	return cell is Dictionary and cell.get("k", K_BLOCK) == K_BLOCK


func cell_color(cell: Variant) -> Color:
	if cell is Dictionary:
		return cell.get("c", Cfg.WHITE)
	return Color(0, 0, 0, 0)


func _make_block(color: Color) -> Dictionary:
	return {"k": K_BLOCK, "c": color, "a": false}


func _make_obstacle() -> Dictionary:
	return {"k": K_OBSTACLE, "c": Cfg.OBSTACLE_COLOR, "a": false}


# ==========================================================================
#  Card instance state (mimic-aware, mirrors get/set_card_instance_state)
# ==========================================================================
func effective_name(card: Dictionary) -> String:
	var m: String = card.get("mimic", "")
	if card.get("name", "") == "The Mimic" and not m.is_empty():
		return m
	return card.get("name", "")


func get_state(card: Dictionary, key: String, default_value: Variant = null) -> Variant:
	if card.get("name", "") == "The Mimic" and not String(card.get("mimic", "")).is_empty():
		return card.get("mimic_state", {}).get(key, default_value)
	return card.get("state", {}).get(key, default_value)


func set_state(card: Dictionary, key: String, value: Variant) -> void:
	if card.get("name", "") == "The Mimic" and not String(card.get("mimic", "")).is_empty():
		if not card.has("mimic_state"):
			card["mimic_state"] = {}
		card["mimic_state"][key] = value
	else:
		if not card.has("state"):
			card["state"] = {}
		card["state"][key] = value


func has_card(effective: String) -> bool:
	return find_card(effective) != null


func find_card(effective: String) -> Variant:
	for c in cards:
		if effective_name(c) == effective:
			return c
	return null


func count_cards(effective: String) -> int:
	var n := 0
	for c in cards:
		if effective_name(c) == effective:
			n += 1
	return n


func find_contract(contract_name: String) -> Variant:
	for c in contracts:
		if c.get("name", "") == contract_name:
			return c
	return null


## A contract's curse only applies until its condition is met.
func contract_curse_active(contract_name: String) -> bool:
	var c: Variant = find_contract(contract_name)
	return c != null and not c.get("condition_met", false)


func init_card_state(card: Dictionary) -> void:
	var n: String = card.get("name", "")
	match n:
		"Shape Shifter", "Trashcan", "Barrel":
			card["state"]["used_this_round"] = false
		"Star Streak":
			card["state"]["insurance_used_this_combo"] = false
		"Overcharge":
			card["state"]["last_bomb_streak_level"] = 0
		"Window Shopper":
			card["state"]["free_reroll_used_this_shop"] = false
		"Soul Stamp":
			card["state"]["soul_stamp_active"] = false
			card["state"]["soul_stamp_available"] = true
		"The Mimic":
			card["state"]["mimic_change_available"] = true
			if not String(card.get("mimic", "")).is_empty():
				init_mimic_state(card, card["mimic"])
			else:
				card["mimic_state"] = {}
	# Merlin's Hat keeps chosen_piece_name / selection_cooldown_round across rounds.


func init_mimic_state(card: Dictionary, mimicked: String) -> void:
	card["mimic_state"] = {}
	if Cards.card(mimicked).is_empty():
		return
	match mimicked:
		"Shape Shifter", "Trashcan", "Barrel":
			card["mimic_state"]["used_this_round"] = false
		"Soul Stamp":
			card["mimic_state"]["soul_stamp_active"] = false
			card["mimic_state"]["soul_stamp_available"] = true
		"Star Streak":
			card["mimic_state"]["insurance_used_this_combo"] = false
		"Overcharge":
			card["mimic_state"]["last_bomb_streak_level"] = 0
		"Window Shopper":
			card["mimic_state"]["free_reroll_used_this_shop"] = false


# ==========================================================================
#  Passive recalculation
# ==========================================================================
func recalculate_passives() -> void:
	passive = {
		"score_multiplier_bonus": 0.0,
		"extra_piece_in_set": 0,
		"shop_discount": 0.0,
		"star_streak_bonus": 0,
		"cards_can_duplicate": false,
	}
	sets_per_round_target = Cfg.SETS_PER_ROUND_DEFAULT

	for p in perks:
		match p.get("name", ""):
			"Score Boost Perk":
				passive["score_multiplier_bonus"] += 0.5
			"More Choices Perk":
				passive["extra_piece_in_set"] = 1

	# "Just a Favor": x10 multi while the curse still stands.
	if contract_curse_active("Just a Favor"):
		passive["score_multiplier_bonus"] += 9.0

	for card in cards:
		if card.get("name", "") == "Echo Chamber":
			passive["cards_can_duplicate"] = true

	passive["shop_discount"] = minf(1.0, count_cards("Thrifting") * 0.20)
	sets_per_round_target = maxi(1, Cfg.SETS_PER_ROUND_DEFAULT - count_cards("Efficiency Expert"))

	var streaks := count_cards("Star Streak")
	passive["star_streak_bonus"] = streaks

	var old_max := Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	combo_allowance_bonus = streaks
	var new_max := Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	if combo_miss_allowance == old_max:
		combo_miss_allowance = new_max
	else:
		combo_miss_allowance = clampi(combo_miss_allowance + (new_max - old_max), 0, new_max)

	# Perk slot caps.
	var pouches := 0
	var belts := 0
	for p in perks:
		if p.get("name", "") == "Extra Card Pouch":
			pouches += 1
		elif p.get("name", "") == "Extra Item Belt":
			belts += 1
	max_cards = Cfg.INITIAL_MAX_CARDS + mini(pouches, 5)
	max_items = Cfg.INITIAL_MAX_ITEMS + mini(belts, 3)

	stats_changed.emit()


# ==========================================================================
#  Placement
# ==========================================================================
func soul_stamp_provider() -> Variant:
	for card in cards:
		if effective_name(card) == "Soul Stamp":
			if get_state(card, "soul_stamp_active", false) and get_state(card, "soul_stamp_available", false):
				return card
	return null


func soul_stamp_armed() -> bool:
	return soul_stamp_provider() != null


func piece_cells(shape: Dictionary, r: int, c: int) -> Array:
	var out: Array = []
	for off in shape.get("coords", []):
		out.append(Vector2i(r + off.x, c + off.y))
	return out


func is_valid_placement(shape: Dictionary, r: int, c: int, stamp := false) -> bool:
	if shape.is_empty():
		return false
	for off in shape.get("coords", []):
		var rr: int = r + off.x
		var cc: int = c + off.y
		if rr < 0 or rr >= grid_rows or cc < 0 or cc >= grid_cols:
			return false
		var cell: Variant = board[rr][cc]
		if cell is Dictionary:
			if stamp:
				continue
			if is_obstacle(cell):
				# Obstacles only hard-block during a boss round.
				if obstacles_on_board:
					return false
			else:
				return false
	return true


func can_any_piece_be_placed() -> bool:
	if hand.is_empty():
		generate_hand()
	if hand.is_empty():
		return false
	var stamp := soul_stamp_armed()
	for shape in hand:
		for r in grid_rows:
			for c in grid_cols:
				if is_valid_placement(shape, r, c, stamp):
					return true
	return false


func selected_shape() -> Dictionary:
	if selected_index >= 0 and selected_index < hand.size():
		return hand[selected_index]
	return {}


func update_potential_clear_highlight() -> void:
	potential_clear_cells = []
	if not has_card("Clairvoyance Charm"):
		return
	var shape := selected_shape()
	if shape.is_empty():
		return
	var stamp := soul_stamp_armed()
	if not is_valid_placement(shape, ghost_pos.x, ghost_pos.y, stamp):
		return

	# Simulate the placement on a filled/empty mask.
	var filled: Array = []
	for r in grid_rows:
		var row: Array = []
		row.resize(grid_cols)
		for c in grid_cols:
			row[c] = is_clearable(board[r][c])
		filled.append(row)
	for off in shape.get("coords", []):
		var rr: int = ghost_pos.x + off.x
		var cc: int = ghost_pos.y + off.y
		if rr >= 0 and rr < grid_rows and cc >= 0 and cc < grid_cols:
			if stamp or not is_obstacle(board[rr][cc]):
				filled[rr][cc] = true

	var out: Dictionary = {}
	for r in grid_rows:
		var full := true
		for c in grid_cols:
			if not filled[r][c]:
				full = false
				break
		if full:
			for c in grid_cols:
				out[Vector2i(r, c)] = true
	for c in grid_cols:
		var full := true
		for r in grid_rows:
			if not filled[r][c]:
				full = false
				break
		if full:
			for r in grid_rows:
				out[Vector2i(r, c)] = true
	potential_clear_cells = out.keys()


## The core turn. Returns true when the piece actually went down.
func place_piece(shape: Dictionary, r: int, c: int) -> bool:
	var stamp_card: Variant = soul_stamp_provider()
	var stamp := stamp_card != null
	if not is_valid_placement(shape, r, c, stamp):
		update_potential_clear_highlight()
		return false

	Audio.play(Cfg.SFX_BLOCK_PLACE)
	Juice.shake(0.055, 8)

	var has_charming := has_card("Charming")
	var has_devils_luck := has_card("Devil's Luck")

	# --- Charming: 10% chance of a 3x3 blast centred on the piece ---
	var charming_cleared: Array = []
	if has_charming and randf() < 0.10:
		Audio.play(Cfg.SFX_ITEM_BOMB, 0.8)
		post_message("Charming Explosion!", Cfg.YELLOW, 1.0)
		card_triggered.emit("Charming")
		var centre := _shape_centre(shape, r, c)
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var er: int = centre.x + dr
				var ec: int = centre.y + dc
				if er >= 0 and er < grid_rows and ec >= 0 and ec < grid_cols and is_clearable(board[er][ec]):
					charming_cleared.append(Vector2i(er, ec))
					board[er][ec] = 0
		if not charming_cleared.is_empty():
			cells_cleared.emit(charming_cleared, "bomb")
			Juice.shake(0.35, 30)
			Juice.hitstop(0.05)
			_bump_combo("Charming")
			check_and_clear_lines()

	# --- Giga Boss: a warned shot fires on this placement ---
	if boss_active and boss_warning_active:
		boss_laser_line = boss_next_line
		boss_laser_is_row = boss_next_is_row
		boss_warning_active = false
		var kind := "Row" if boss_laser_is_row else "Column"
		post_message("Giga Boss: Laser firing at %s %d!" % [kind, boss_laser_line + 1], Cfg.RED, 1.0)
		Audio.play(Cfg.SFX_BOSS_LASER_CHARGE, 0.7)
		boss_state_changed.emit()
	else:
		boss_laser_line = -1

	# --- Write the piece ---
	var placed := piece_cells(shape, r, c)
	for cell_pos in placed:
		board[cell_pos.x][cell_pos.y] = _make_block(shape["color"])
	piece_placed.emit(placed, shape["color"])

	if stamp and stamp_card != null:
		set_state(stamp_card, "soul_stamp_available", false)
		set_state(stamp_card, "soul_stamp_active", false)
		post_message("Soul Stamp used.", Cfg.WHITE, 1.0)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Soul Stamp")

	# --- Consume from hand ---
	if selected_index >= 0 and selected_index < hand.size():
		hand.remove_at(selected_index)
	elif not hand.is_empty():
		hand.remove_at(0)
	selected_index = 0
	hand_changed.emit()

	var cleared_lines := check_and_clear_lines()

	if cleared_lines >= 2 and has_card("Clairvoyance Charm"):
		money += 5
		post_message("Clairvoyance: +$5!", Cfg.MONEY_COLOR, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.8)
		card_triggered.emit("Clairvoyance Charm")
		stats_changed.emit()

	if cleared_lines > 0:
		_bump_combo("")
		_trigger_overcharge()
	elif charming_cleared.is_empty():
		_handle_missed_combo(has_devils_luck)

	if hand.is_empty():
		_end_of_set(has_devils_luck)

	# --- Giga Boss fires after the dust settles ---
	if boss_active and boss_laser_line != -1:
		_fire_boss_laser()

	board_changed.emit()
	update_potential_clear_highlight()

	if not is_game_over and pending_effect.is_empty() and not conjure_active:
		if not can_any_piece_be_placed():
			check_game_over("No valid moves")
	return true


func _shape_centre(shape: Dictionary, r: int, c: int) -> Vector2i:
	var coords: Array = shape.get("coords", [])
	if coords.is_empty():
		return Vector2i(r, c)
	var min_r := 9999
	var max_r := -9999
	var min_c := 9999
	var max_c := -9999
	for off in coords:
		min_r = mini(min_r, off.x)
		max_r = maxi(max_r, off.x)
		min_c = mini(min_c, off.y)
		max_c = maxi(max_c, off.y)
	return Vector2i(r + (min_r + max_r) / 2, c + (min_c + max_c) / 2)


func _bump_combo(source: String) -> void:
	combo_streak += 1
	Audio.play_combo(combo_streak)
	combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	for card in cards:
		if effective_name(card) == "Star Streak":
			set_state(card, "insurance_used_this_combo", false)
	var label := "COMBO x%d!" % combo_streak
	if not source.is_empty():
		label = "COMBO x%d (%s)!" % [combo_streak, source]
	post_message(label, Cfg.COMBO_TEXT_COLOR, 1.5)
	Juice.set_combo(combo_streak)
	combo_changed.emit(combo_streak, combo_miss_allowance)


func _trigger_overcharge() -> void:
	for card in cards:
		if effective_name(card) != "Overcharge":
			continue
		var last: int = get_state(card, "last_bomb_streak_level", 0)
		@warning_ignore("integer_division")
		var level: int = combo_streak / 10
		if level > last and combo_streak >= 10:
			post_message("OVERCHARGE BOMB!", Cfg.MAGENTA, 1.5)
			Audio.play(Cfg.SFX_ITEM_BOMB, 1.2)
			card_triggered.emit("Overcharge")
			Juice.shake(0.5, 45)
			Juice.hitstop(0.07)
			var br: int = 0 if grid_rows < 4 else randi() % maxi(1, grid_rows - 3)
			var bc: int = 0 if grid_cols < 4 else randi() % maxi(1, grid_cols - 3)
			var hit: Array = []
			for dr in 4:
				for dc in 4:
					var rr: int = br + dr
					var cc: int = bc + dc
					if rr < grid_rows and cc < grid_cols and is_clearable(board[rr][cc]):
						hit.append(Vector2i(rr, cc))
						board[rr][cc] = 0
			if not hit.is_empty():
				cells_cleared.emit(hit, "bomb")
				check_and_clear_lines()
			set_state(card, "last_bomb_streak_level", level)


func _handle_missed_combo(has_devils_luck: bool) -> void:
	var devil_cleared := false
	if has_devils_luck and randf() < 0.33:
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Devil's Luck")
		if randi() % 2 == 0:
			var r := randi() % grid_rows
			apply_clear_effect("row_clear", r, 0, 3, true)
			post_message("Devil's Luck: Row Cleared!", Cfg.YELLOW, 1.5)
		else:
			var c := randi() % grid_cols
			apply_clear_effect("column_clear", 0, c, 3, true)
			post_message("Devil's Luck: Column Cleared!", Cfg.YELLOW, 1.5)
		devil_cleared = true

	if devil_cleared:
		return

	combo_miss_allowance -= 1
	if combo_miss_allowance >= 0:
		combo_changed.emit(combo_streak, combo_miss_allowance)
		return

	# Out of chances -- Star Streak may absorb one hit per combo.
	for card in cards:
		if effective_name(card) == "Star Streak" and not get_state(card, "insurance_used_this_combo", false):
			combo_miss_allowance = 0
			set_state(card, "insurance_used_this_combo", true)
			post_message("Star Streak Insurance!", Cfg.YELLOW, 1.0)
			Audio.play(Cfg.SFX_CARD_MET)
			card_triggered.emit("Star Streak")
			combo_changed.emit(combo_streak, combo_miss_allowance)
			return

	if combo_streak > 1:
		post_message("Combo Lost!", Cfg.RED, 1.5)
		Juice.shake(0.2, 20)

	if contract_curse_active("Just a Favor"):
		var lost := int(money * 0.10)
		money = maxi(0, money - lost)
		post_message("Just a Favor: Lost $%d (10%%)!" % lost, Cfg.RED, 2.0)
		Audio.play(Cfg.SFX_LOSE, 0.7)
		stats_changed.emit()

	combo_streak = 0
	combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	for card in cards:
		if effective_name(card) == "Star Streak":
			set_state(card, "insurance_used_this_combo", false)
	Juice.set_combo(0)
	combo_changed.emit(combo_streak, combo_miss_allowance)


# ==========================================================================
#  Line clearing
# ==========================================================================
func check_and_clear_lines() -> int:
	var angel_hits := 0
	var anim_cells: Dictionary = {}

	var rows_to_clear: Array = []
	for r in grid_rows:
		var full := true
		for c in grid_cols:
			if not is_clearable(board[r][c]):
				full = false
				break
		if full:
			rows_to_clear.append(r)
			for c in grid_cols:
				anim_cells[Vector2i(r, c)] = true
				if board[r][c].get("a", false):
					angel_hits += 1

	var cols_to_clear: Array = []
	for c in grid_cols:
		var full := true
		for r in grid_rows:
			if not is_clearable(board[r][c]):
				full = false
				break
		if full:
			cols_to_clear.append(c)
			for r in grid_rows:
				var key := Vector2i(r, c)
				if not anim_cells.has(key):
					anim_cells[key] = true
					if board[r][c].get("a", false):
						angel_hits += 1

	# --- Skyscraper: each cleared column drags a neighbour with it ---
	var bonus_cols: Array = []
	if has_card("Skyscraper") and not cols_to_clear.is_empty():
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Skyscraper")
		for cleared_c in cols_to_clear:
			var options: Array = []
			for cand in [cleared_c - 1, cleared_c + 1]:
				if cand >= 0 and cand < grid_cols and not cols_to_clear.has(cand) and not bonus_cols.has(cand):
					options.append(cand)
			if options.is_empty():
				continue
			var chosen: int = options[randi() % options.size()]
			bonus_cols.append(chosen)
			post_message("Skyscraper triggers!", Cfg.YELLOW, 1.0)
			for r in grid_rows:
				if not is_obstacle(board[r][chosen]):
					var key := Vector2i(r, chosen)
					if not anim_cells.has(key) and is_clearable(board[r][chosen]):
						anim_cells[key] = true
						if board[r][chosen].get("a", false):
							angel_hits += 1
			if items.size() < max_items and not Cards.ITEMS.is_empty():
				var item_name: String = Cards.ITEMS[randi() % Cards.ITEMS.size()]["name"]
				items.append(Cards.new_item_instance(item_name))
				post_message("Skyscraper: %s Gained!" % item_name, Cfg.WHITE, 1.0)
				Audio.play(Cfg.SFX_BUY, 0.7)
				inventory_changed.emit()

	var all_cols: Array = []
	for c in cols_to_clear:
		all_cols.append(c)
	for c in bonus_cols:
		all_cols.append(c)
	all_cols.sort()

	var cleared_count := rows_to_clear.size() + all_cols.size()
	if cleared_count == 0:
		return 0

	_collapse_rows(rows_to_clear)
	_collapse_columns(all_cols)

	Audio.play(Cfg.SFX_LINE_CLEAR)
	if cleared_count > 1:
		Audio.play(Cfg.SFX_LINE_CLEAR_COMBO, 0.9)
	cells_cleared.emit(anim_cells.keys(), "line")
	lines_cleared.emit(cleared_count, rows_to_clear, all_cols)
	Juice.shake(0.12 + 0.09 * cleared_count, 12 + 8 * cleared_count)
	if cleared_count >= 2:
		Juice.hitstop(0.04 + 0.015 * cleared_count)
		Juice.flash(Cfg.WHITE, 0.18 + 0.06 * cleared_count, 0.3)

	_award_clear(cleared_count, angel_hits, not rows_to_clear.is_empty(), not all_cols.is_empty())
	board_changed.emit()
	return cleared_count


func _collapse_rows(rows_to_clear: Array) -> void:
	if rows_to_clear.is_empty():
		return
	var kept: Array = []
	for r in grid_rows:
		if not rows_to_clear.has(r):
			kept.append(board[r])
	var rebuilt: Array = []
	for _i in rows_to_clear.size():
		var row: Array = []
		row.resize(grid_cols)
		row.fill(0)
		rebuilt.append(row)
	rebuilt.append_array(kept)
	board = rebuilt


## Cleared columns collapse leftwards; obstacles ride along instead of vanishing.
func _collapse_columns(cols: Array) -> void:
	if cols.is_empty():
		return
	for r in grid_rows:
		var keep: Array = []
		for c in grid_cols:
			var cell: Variant = board[r][c]
			if cols.has(c) and not is_obstacle(cell):
				continue
			keep.append(cell)
		var row: Array = []
		row.resize(grid_cols)
		row.fill(0)
		for i in mini(keep.size(), grid_cols):
			row[i] = keep[i]
		board[r] = row


func _award_clear(count: int, angel_hits: int, had_rows: bool, had_cols: bool) -> void:
	var earned: int = count * Cfg.BASE_MONEY_PER_LINE
	if count > 1:
		earned += (count - 1) * 2
	if angel_hits > 0:
		earned += angel_hits
		post_message("+$%d (Angel's Kiss)!" % angel_hits, Cfg.MONEY_COLOR, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.6)
		card_triggered.emit("Angel's Kiss")
	money += earned

	var mult: float = 1.0 + passive.get("score_multiplier_bonus", 0.0)
	var combo_mult: int = maxi(1, combo_streak)
	var line_bonus := 1.0
	if count == 2:
		line_bonus = 2.5
	elif count >= 3:
		line_bonus = count * 1.5
	var line_score: float = Cfg.BASE_SCORE_PER_LINE * count * line_bonus

	var terraform := count_cards("Terraform")
	if terraform > 0 and had_rows:
		line_score *= pow(2.0, terraform)
		post_message("Terraform x%d Score!" % int(pow(2, terraform)), Cfg.YELLOW, 1.0)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Terraform")

	var sky := count_cards("Skyscraper")
	if sky > 0 and had_cols:
		line_score *= pow(2.0, sky)
		post_message("Skyscraper x%d Score!" % int(pow(2, sky)), Cfg.YELLOW, 1.0)

	var total: float = line_score * mult * combo_mult
	score += int(round(total))

	floating_score.emit("%d x %d" % [int(round(line_score * mult)), combo_mult], "score")

	if count == 1:
		post_message("Line Cleared!", Cfg.WHITE, 1.0)
	elif count == 2:
		post_message("Double Clear!", Cfg.WHITE, 1.0)
	else:
		post_message("Multi Clear x%d!" % count, Cfg.WHITE, 1.0)

	# Perfectionist: an empty board (obstacles excepted) pays big.
	if has_card("Perfectionist") and _board_is_clear():
		score += Cfg.PERFECTIONIST_BONUS
		post_message("PERFECTIONIST! +%d Score!" % Cfg.PERFECTIONIST_BONUS, Cfg.YELLOW, 2.0)
		Audio.play(Cfg.SFX_BOARD_CLEAR)
		card_triggered.emit("Perfectionist")
		Juice.shake(0.6, 60)
		Juice.flash(Cfg.ACCENT_PRIMARY, 0.5, 0.6)
		floating_score.emit("PERFECTIONIST +%d" % Cfg.PERFECTIONIST_BONUS, "multiplier")

	stats_changed.emit()


func _board_is_clear() -> bool:
	for r in grid_rows:
		for c in grid_cols:
			if is_clearable(board[r][c]):
				return false
	return true


# ==========================================================================
#  End of set / round progression
# ==========================================================================
func _end_of_set(has_devils_luck: bool) -> void:
	sets_placed_in_round += 1
	save_run()

	# Boss-round obstacles seed the board.
	if round_count > 0 and round_count % 5 == 0:
		var to_add := 1 + randi() % 3
		var empties: Array = []
		for r in grid_rows:
			for c in grid_cols:
				if is_empty_cell(board[r][c]):
					empties.append(Vector2i(r, c))
		empties.shuffle()
		var placed := mini(to_add, empties.size())
		for i in placed:
			board[empties[i].x][empties[i].y] = _make_obstacle()
			obstacles_on_board = true
		if placed > 0:
			Audio.play(Cfg.SFX_OBSTACLE_APPEAR)
			post_message("Obstacles appear!", Cfg.OBSTACLE_COLOR.lightened(0.4), 1.5)

	if has_devils_luck and randf() < 0.33:
		money += 3
		post_message("Devil's Luck: +$3!", Cfg.MONEY_COLOR, 1.0)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Devil's Luck")
		stats_changed.emit()

	if has_devils_luck and randf() < 0.33:
		Audio.play(Cfg.SFX_CARD_MET, 0.7)
		var occupied: Array = []
		for r in grid_rows:
			for c in grid_cols:
				if is_clearable(board[r][c]):
					occupied.append(Vector2i(r, c))
		if not occupied.is_empty():
			var pick: Vector2i = occupied[randi() % occupied.size()]
			board[pick.x][pick.y] = 0
			post_message("Devil's Luck: A tile vanished!", Cfg.YELLOW, 1.5)
			cells_cleared.emit([pick], "vanish")
			check_and_clear_lines()

	_apply_angels_kiss()

	if sets_placed_in_round >= sets_per_round_target:
		_advance_round()
	else:
		generate_hand()


## Angel's Kiss re-rolls which single block is worth $1 at the start of each set.
func _apply_angels_kiss() -> void:
	if not has_card("Angel's Kiss"):
		return
	Audio.play(Cfg.SFX_CARD_MET, 0.5)
	var candidates: Array = []
	for r in grid_rows:
		for c in grid_cols:
			var cell: Variant = board[r][c]
			if is_clearable(cell):
				if cell.get("a", false):
					cell["a"] = false
					cell["c"] = cell.get("o", cell["c"])
				else:
					candidates.append(Vector2i(r, c))
	if candidates.is_empty():
		return
	var pick: Vector2i = candidates[randi() % candidates.size()]
	var target: Dictionary = board[pick.x][pick.y]
	target["o"] = target["c"]
	target["a"] = true
	target["c"] = Cfg.YELLOW
	post_message("Angel's Kiss active!", Cfg.YELLOW, 1.0)
	card_triggered.emit("Angel's Kiss")
	board_changed.emit()


func _advance_round() -> void:
	sets_placed_in_round = 0
	round_count += 1

	for card in cards:
		init_card_state(card)

	_tick_contracts()
	recalculate_passives()
	_apply_round_contracts()

	# Boss subsides at the round boundary, then may respawn.
	if boss_active:
		post_message("Giga Boss temporarily subsides...", Cfg.GREEN, 2.0)
		boss_active = false
		boss_warning_active = false
		boss_next_line = -1
		boss_laser_line = -1
		boss_state_changed.emit()

	var spawn_chance := 0.0
	if find_contract("Underdog") != null:
		boss_active = false
		boss_warning_active = false
		boss_next_line = -1
		boss_laser_line = -1
	elif round_count % 5 == 0:
		spawn_chance = 0.05 if round_count <= 25 else 0.20

	if randf() < spawn_chance:
		boss_active = true
		post_message("GIGA BOSS APPEARS!", Cfg.RED, 3.0)
		Audio.play(Cfg.SFX_BOSS_APPEAR)
		Juice.shake(0.8, 120)
		Juice.flash(Cfg.RED, 0.55, 0.8)
		_choose_next_boss_target()

	# The round after a boss round, leftover obstacles crumble into blocks.
	if (round_count - 1) > 0 and (round_count - 1) % 5 == 0 and obstacles_on_board:
		var converted := false
		for r in grid_rows:
			for c in grid_cols:
				if is_obstacle(board[r][c]):
					board[r][c] = _make_block(Cfg.GRAY)
					converted = true
		if converted:
			post_message("Boss obstacles shattered into blocks!", Cfg.GREEN, 1.5)
			Audio.play(Cfg.SFX_OBSTACLE_CONVERT)
		obstacles_on_board = false
		check_and_clear_lines()

	stats_changed.emit()
	board_changed.emit()

	if round_count % 5 == 0:
		Audio.play_music(Cfg.MUSIC_BOSS)
		post_message("BOSS ROUND %d!" % (round_count / 5), Cfg.RED, 3.0)
		generate_hand()
	elif (round_count - 1) % 5 == 3:
		generate_perk_offers()
		post_message("PERK SELECTION! (Round %d)" % round_count, Cfg.MAGENTA, 3.0)
		Audio.play_music(Cfg.MUSIC_LOBBY)
		request_screen.emit("perks")
	elif (round_count <= 25 and randf() < 0.033) or (round_count > 25 and randf() < 0.08):
		generate_lucifer_offers()
		post_message("LUCIFER'S LOST & FOUND! (Round %d)" % round_count, Cfg.RED, 3.0)
		Audio.play_music(Cfg.MUSIC_LOBBY)
		request_screen.emit("lucifer")
	else:
		shop_reroll_cost = Cfg.SHOP_REROLL_BASE_COST
		generate_shop_offers()
		post_message("SHOP OPEN! (Round %d)" % round_count, Cfg.YELLOW, 3.0)
		Audio.play_music(Cfg.MUSIC_LOBBY)
		for card in cards:
			if effective_name(card) == "Window Shopper":
				set_state(card, "free_reroll_used_this_shop", false)
		request_screen.emit("shop")


func _tick_contracts() -> void:
	var expired: Array = []
	for contract in contracts:
		if contract.get("expiration", 0) > 0:
			contract["expiration"] -= 1
			if contract["expiration"] == 0:
				post_message("Contract '%s' expired." % contract["name"], Cfg.ORANGE, 2.0)
				Audio.play(Cfg.SFX_LOSE, 0.6)
				expired.append(contract)
				continue
		if not contract.get("condition_met", false) and contract.get("condition_deadline", 0) > 0:
			contract["condition_deadline"] -= 1
			if contract["condition_deadline"] == 0:
				contract["condition_met"] = true
				post_message("Condition met for '%s'!" % contract["name"], Cfg.GREEN, 2.0)
				Audio.play(Cfg.SFX_CARD_MET)
				SaveGame.mark_contract_completed(contract["name"])
	for c in expired:
		contracts.erase(c)
	if not expired.is_empty():
		inventory_changed.emit()


func _apply_round_contracts() -> void:
	if find_contract("Greedy") != null:
		if not cards.is_empty():
			money += 5 * cards.size()
			post_message("Greedy: +$%d!" % (5 * cards.size()), Cfg.MONEY_COLOR, 1.0)
		if contract_curse_active("Greedy"):
			var broken: Array = []
			for card in cards:
				if randf() < 0.10:
					broken.append(card)
			if not broken.is_empty():
				Audio.play(Cfg.SFX_DEAL_WITH_DEATH, 0.5)
				for card in broken:
					cards.erase(card)
					post_message("Greedy Curse: %s broke!" % card["name"], Cfg.RED, 1.5)
				recalculate_passives()
				inventory_changed.emit()

	if find_contract("Free Money") != null:
		money += 20
		post_message("A mysterious gift: +$20!", Cfg.MONEY_COLOR, 1.5)
		Audio.play(Cfg.SFX_CARD_MET)
		if contract_curse_active("Free Money"):
			if randf() < 0.25:
				if not cards.is_empty():
					var lost: Dictionary = cards[randi() % cards.size()]
					cards.erase(lost)
					post_message("The gift's curse... Lost %s!" % lost.get("name", "a card"), Cfg.RED, 2.0)
					Audio.play(Cfg.SFX_LOSE, 0.7)
					recalculate_passives()
					inventory_changed.emit()
				else:
					post_message("The gift sought a toll, but found an empty coffer.", Cfg.YELLOW, 3.0)
		else:
			post_message("The gift seems... benign. For now.", Cfg.GREEN, 3.0)
	stats_changed.emit()


# ==========================================================================
#  Giga Boss
# ==========================================================================
func _choose_next_boss_target() -> void:
	if not boss_active:
		boss_warning_active = false
		boss_next_line = -1
		boss_state_changed.emit()
		return
	boss_next_is_row = randi() % 2 == 0
	boss_next_line = randi() % (grid_rows if boss_next_is_row else grid_cols)
	boss_warning_active = true
	var kind := "Row" if boss_next_is_row else "Column"
	post_message("Giga Boss: Warning! Next target: %s %d!" % [kind, boss_next_line + 1], Cfg.ORANGE, 1.5)
	boss_state_changed.emit()


func _fire_boss_laser() -> void:
	var hit: Array = []
	var line := boss_laser_line
	if boss_laser_is_row:
		if line >= 0 and line < grid_rows:
			for c in grid_cols:
				if is_clearable(board[line][c]):
					hit.append(Vector2i(line, c))
					board[line][c] = 0
			post_message("Giga Boss: Row %d DESTROYED!" % (line + 1), Cfg.RED, 1.5)
	else:
		if line >= 0 and line < grid_cols:
			for r in grid_rows:
				if is_clearable(board[r][line]):
					hit.append(Vector2i(r, line))
					board[r][line] = 0
			post_message("Giga Boss: Column %d DESTROYED!" % (line + 1), Cfg.RED, 1.5)

	if not hit.is_empty():
		cells_cleared.emit(hit, "laser")
		boss_fired.emit(boss_laser_is_row, line)
		Audio.play(Cfg.SFX_BOSS_LASER_FIRE)
		Juice.shake(0.65, 80)
		Juice.flash(Cfg.RED, 0.4, 0.45)
		Juice.hitstop(0.06)
		check_and_clear_lines()

	boss_laser_line = -1
	if boss_active:
		_choose_next_boss_target()
	else:
		boss_warning_active = false
		boss_next_line = -1
		boss_state_changed.emit()


# ==========================================================================
#  Hand generation
# ==========================================================================
func generate_hand() -> void:
	var base_count: int = [2, 2, 3][randi() % 3]
	var count: int = base_count + int(passive.get("extra_piece_in_set", 0))

	# Merlin's Hat weights its chosen piece 5x per copy.
	var merlin_picks := {}
	for card in cards:
		if effective_name(card) == "Merlin's Hat":
			var chosen: Variant = get_state(card, "chosen_piece_name", "")
			if chosen is String and not (chosen as String).is_empty():
				merlin_picks[chosen] = int(merlin_picks.get(chosen, 0)) + 1

	var pool: Array = []
	for shape in Cfg.SHAPES:
		var weight := 1
		if merlin_picks.has(shape["name"]):
			weight += 5 * int(merlin_picks[shape["name"]])
		for _i in weight:
			pool.append(shape)

	hand = []
	for _i in count:
		hand.append(Cfg.copy_shape(pool[randi() % pool.size()]))

	selected_index = 0
	ghost_pos = Vector2i(grid_rows / 2, grid_cols / 2) if not hand.is_empty() else Vector2i.ZERO
	hand_changed.emit()
	update_potential_clear_highlight()


# ==========================================================================
#  Shop / perks / contracts
# ==========================================================================
func generate_shop_offers() -> void:
	shop_offers = {"cards": [], "items": []}
	var can_duplicate: bool = passive.get("cards_can_duplicate", false)
	var owned: Array = []
	for c in cards:
		owned.append(c["name"])

	var available: Array = []
	for master in Cards.CARDS:
		var is_owned: bool = owned.has(master["name"])
		if not is_owned:
			available.append(master)
		elif can_duplicate and not master.get("unique", false):
			available.append(master)

	if not available.is_empty():
		var chosen: Array = []
		if not can_duplicate:
			var pool: Array = available.duplicate()
			pool.shuffle()
			chosen = pool.slice(0, mini(3, pool.size()))
		else:
			var weights: Array = []
			var total := 0.0
			for m in available:
				var w: float = Cards.rarity_weight(m["rarity"])
				weights.append(w)
				total += w
			for _i in 3:
				var roll := randf() * total
				var acc := 0.0
				for i in available.size():
					acc += weights[i]
					if roll <= acc:
						chosen.append(available[i])
						break
		for m in chosen:
			shop_offers["cards"].append({"name": m["name"], "rarity": m["rarity"]})

	var item_pool: Array = Cards.ITEMS.duplicate()
	item_pool.shuffle()
	for m in item_pool.slice(0, mini(2, item_pool.size())):
		shop_offers["items"].append({"name": m["name"], "cost": m["cost"], "rarity": m["rarity"]})


func shop_price(entry_name: String, base_cost: int) -> int:
	var discount: float = passive.get("shop_discount", 0.0)
	return maxi(0, int(base_cost * (1.0 - discount)))


func window_shopper_free_reroll() -> Variant:
	for card in cards:
		if effective_name(card) == "Window Shopper" and not get_state(card, "free_reroll_used_this_shop", false):
			return card
	return null


func reroll_shop() -> bool:
	var free_card: Variant = window_shopper_free_reroll()
	if free_card != null:
		set_state(free_card, "free_reroll_used_this_shop", true)
		generate_shop_offers()
		post_message("Shop Rerolled! (Free)", Cfg.WHITE, 1.0)
		Audio.play(Cfg.SFX_SHOP_REROLL)
		card_triggered.emit("Window Shopper")
		return true
	if money >= shop_reroll_cost:
		money -= shop_reroll_cost
		shop_reroll_cost += 1
		generate_shop_offers()
		post_message("Shop Rerolled!", Cfg.WHITE, 1.0)
		Audio.play(Cfg.SFX_SHOP_REROLL)
		stats_changed.emit()
		return true
	post_message("Not enough $ to reroll ($%d)!" % shop_reroll_cost, Cfg.RED, 1.0)
	return false


func buy_shop_entry(kind: String, index: int) -> bool:
	if contract_curse_active("Underdog"):
		post_message("Underdog Curse: Cannot acquire items!", Cfg.RED, 1.0)
		return false

	if kind == "card":
		if index < 0 or index >= shop_offers["cards"].size():
			return false
		var offer: Dictionary = shop_offers["cards"][index]
		if cards.size() >= max_cards:
			post_message("Card inventory full!", Cfg.RED, 1.0)
			return false
		var cost := shop_price(offer["name"], Cards.card_cost(offer["name"]))
		if money < cost:
			post_message("Not enough money!", Cfg.RED, 1.0)
			return false
		money -= cost
		add_card(offer["name"])
		shop_offers["cards"].remove_at(index)
		post_message("Bought %s for $%d!" % [offer["name"], cost], Cfg.MONEY_COLOR, 1.5)
		Audio.play(Cfg.SFX_BUY)
		stats_changed.emit()
		return true

	if kind == "item":
		if index < 0 or index >= shop_offers["items"].size():
			return false
		var offer: Dictionary = shop_offers["items"][index]
		if items.size() >= max_items:
			post_message("Item inventory full!", Cfg.RED, 1.0)
			return false
		var cost := shop_price(offer["name"], offer.get("cost", 0))
		if money < cost:
			post_message("Not enough money!", Cfg.RED, 1.0)
			return false
		money -= cost
		items.append(Cards.new_item_instance(offer["name"]))
		shop_offers["items"].remove_at(index)
		post_message("Bought %s for $%d!" % [offer["name"], cost], Cfg.MONEY_COLOR, 1.5)
		Audio.play(Cfg.SFX_BUY)
		stats_changed.emit()
		inventory_changed.emit()
		return true
	return false


func exit_shop() -> void:
	Audio.play_music(Cfg.MUSIC_BOSS if round_count % 5 == 0 else Cfg.MUSIC_INGAME)
	generate_hand()
	check_game_over("No valid moves")


func generate_perk_offers() -> void:
	var available: Array = []
	var owned: Array = []
	for p in perks:
		owned.append(p["name"])
	for master in Cards.PERKS:
		if master.get("stackable", true) or not owned.has(master["name"]):
			available.append(master)
	available.shuffle()
	perk_offers = []
	for m in available.slice(0, mini(3, available.size())):
		perk_offers.append({"name": m["name"], "rarity": m["rarity"], "description": m["description"]})


func choose_perk(index: int) -> void:
	if index < 0 or index >= perk_offers.size():
		return
	var chosen: Dictionary = perk_offers[index]
	add_perk(chosen["name"])
	post_message("Perk Gained: %s!" % chosen["name"], Cfg.MAGENTA, 1.5)
	perk_offers = []
	Audio.play(Cfg.SFX_BUY, 0.8)
	recalculate_passives()
	Audio.play_music(Cfg.MUSIC_INGAME)
	generate_hand()


func generate_lucifer_offers() -> void:
	var pool: Array = Cards.CONTRACTS.duplicate()
	pool.shuffle()
	lucifer_offers = []
	for master in pool.slice(0, mini(3, pool.size())):
		lucifer_offers.append({
			"name": master["name"],
			"description": master["description"],
			"condition_text": master["condition_text"],
			"condition_deadline": 3 + randi() % 5,
			"expiration": 0,
		})
	for offer in lucifer_offers:
		offer["expiration"] = offer["condition_deadline"] + 3 + randi() % 3


func choose_contract(index: int) -> void:
	if index < 0 or index >= lucifer_offers.size():
		return
	var offer: Dictionary = lucifer_offers[index]
	var instance := {
		"name": offer["name"],
		"description": offer["description"],
		"condition_text": offer["condition_text"],
		"condition_deadline": offer["condition_deadline"],
		"expiration": offer["expiration"],
		"condition_met": false,
	}
	contracts.append(instance)
	post_message("Contract Gained: %s!" % offer["name"], Cfg.YELLOW, 1.5)
	post_message("Condition in %d rounds. Expires in %d rounds." % [instance["condition_deadline"], instance["expiration"]], Cfg.LIGHT_GRAY, 2.0)

	match offer["name"]:
		"Underdog":
			if not items.is_empty():
				items.clear()
				post_message("Underdog: All items lost!", Cfg.RED, 1.5)
		"Just a Favor":
			combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
			post_message("Just a Favor: Combo chances reset!", Cfg.YELLOW, 1.0)

	lucifer_offers = []
	Audio.play(Cfg.SFX_BUY, 0.8)
	recalculate_passives()
	inventory_changed.emit()
	Audio.play_music(Cfg.MUSIC_INGAME)
	generate_hand()


# ==========================================================================
#  Inventory
# ==========================================================================
func add_card(card_name: String) -> void:
	var instance := Cards.new_card_instance(card_name)
	if instance.is_empty():
		return
	init_card_state(instance)
	cards.append(instance)
	post_message("Added Card: %s" % card_name, Cfg.GREEN, 1.5)

	if card_name == "Downsize":
		var shrunk := false
		if randi() % 2 == 0 and grid_rows > Cfg.MIN_GRID_ROWS:
			grid_rows -= 1
			board.remove_at(board.size() - 1)
			shrunk = true
		elif grid_cols > Cfg.MIN_GRID_COLS:
			grid_cols -= 1
			for r in board.size():
				board[r].remove_at(board[r].size() - 1)
			shrunk = true
		if shrunk:
			post_message("Grid Downsized!", Cfg.WHITE, 1.5)
			Audio.play(Cfg.SFX_CARD_MET)
			grid_resized.emit()
			board_changed.emit()

	recalculate_passives()
	inventory_changed.emit()


func add_perk(perk_name: String) -> void:
	var master := Cards.perk(perk_name)
	if master.is_empty():
		return
	if not master.get("stackable", true):
		for p in perks:
			if p["name"] == perk_name:
				post_message("Cannot add duplicate perk: %s" % perk_name, Cfg.RED, 1.0)
				return
	perks.append({"name": perk_name, "rarity": master["rarity"]})
	post_message("Added Perk: %s" % perk_name, Cfg.GREEN, 1.5)
	recalculate_passives()
	inventory_changed.emit()


func sell_price_for_card(card: Dictionary) -> int:
	@warning_ignore("integer_division")
	return Cfg.RARITY_COSTS.get(card.get("rarity", "Common"), 0) / 2


func sell_price_for_item(item: Dictionary) -> int:
	@warning_ignore("integer_division")
	return int(item.get("cost", 0)) / 2


func sell_card(index: int) -> void:
	if index < 0 or index >= cards.size():
		return
	var card: Dictionary = cards[index]
	money += sell_price_for_card(card)

	if card["name"] == "The Mimic":
		card["mimic"] = ""
		card["mimic_state"] = {}
	elif card["name"] == "Downsize":
		var grew := false
		if randi() % 2 == 0 and grid_rows < Cfg.MAX_GRID_ROWS:
			grid_rows += 1
			var row: Array = []
			row.resize(grid_cols)
			row.fill(0)
			board.insert(0, row)
			grew = true
		elif grid_cols < Cfg.MAX_GRID_COLS:
			grid_cols += 1
			for r in board.size():
				board[r].append(0)
			grew = true
		if grew:
			post_message("Grid Resized (Downsize Sold)!", Cfg.WHITE, 1.5)
			Audio.play(Cfg.SFX_CARD_MET)
			grid_resized.emit()
			board_changed.emit()

	post_message("Sold %s for $%d" % [card["name"], sell_price_for_card(card)], Cfg.MONEY_COLOR, 1.5)
	cards.remove_at(index)
	Audio.play(Cfg.SFX_SELL)
	recalculate_passives()
	inventory_changed.emit()


func sell_item(index: int) -> void:
	if index < 0 or index >= items.size():
		return
	var item: Dictionary = items[index]
	var price := sell_price_for_item(item)
	money += price
	items.remove_at(index)
	post_message("Sold %s for $%d" % [item["name"], price], Cfg.MONEY_COLOR, 1.5)
	Audio.play(Cfg.SFX_SELL)
	stats_changed.emit()
	inventory_changed.emit()


# ==========================================================================
#  Items
# ==========================================================================
func use_item(index: int) -> bool:
	if contract_curse_active("Underdog"):
		post_message("Underdog Curse: Cannot use items!", Cfg.RED, 1.0)
		return false
	if not pending_effect.is_empty() or conjure_active:
		post_message("Finish current action!", Cfg.RED, 1.0)
		return false
	if index < 0 or index >= items.size():
		return false

	var item: Dictionary = items[index]
	var consumed := true
	match item["name"]:
		"Wide Bomb":
			pending_effect = {"type": "row_clear", "source": "item"}
			post_message("Tap a row to clear!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_BOMB)
		"Tall Bomb":
			pending_effect = {"type": "column_clear", "source": "item"}
			post_message("Tap a column to clear!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_BOMB)
		"Small Bomb":
			pending_effect = {"type": "area_bomb", "size": 3, "source": "item"}
			post_message("Tap an area to bomb (3x3)!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_BOMB)
		"Magic Ball":
			conjure_active = true
			consumed = false
			post_message("Select a piece to conjure!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_CONJURE)
		"Eraser":
			pending_effect = {"type": "single_block_remove", "source": "item"}
			post_message("Tap a block to erase!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_ERASE)
		_:
			post_message("Unknown item: %s" % item["name"], Cfg.RED, 1.0)
			return false

	if consumed and Cards.item(item["name"]).get("consumable", true):
		items.remove_at(index)
		inventory_changed.emit()
	pending_effect_changed.emit()
	return true


func cancel_pending() -> void:
	if pending_effect.is_empty() and not conjure_active:
		return
	pending_effect = {}
	conjure_active = false
	pending_effect_changed.emit()


func conjure_piece(shape_name: String) -> void:
	var shape := Cfg.shape_by_name(shape_name)
	if shape.is_empty():
		return
	hand.append(Cfg.copy_shape(shape))
	post_message("Conjured %s!" % shape_name, Cfg.GREEN, 1.5)
	conjure_active = false
	pending_effect = {}
	for i in items.size():
		if items[i]["name"] == "Magic Ball":
			items.remove_at(i)
			break
	inventory_changed.emit()
	hand_changed.emit()
	pending_effect_changed.emit()
	update_potential_clear_highlight()
	check_game_over("No valid moves")


func apply_clear_effect(clear_type: String, r: int, c: int, size := 3, from_card := false) -> void:
	var hit: Array = []
	var sfx := Cfg.SFX_ITEM_BOMB

	match clear_type:
		"row_clear":
			if r < 0 or r >= grid_rows:
				return
			for cc in grid_cols:
				if is_clearable(board[r][cc]):
					hit.append(Vector2i(r, cc))
					board[r][cc] = 0
			post_message("Row %d cleared!" % (r + 1), Cfg.WHITE, 1.5)
		"column_clear":
			if c < 0 or c >= grid_cols:
				return
			for rr in grid_rows:
				if is_clearable(board[rr][c]):
					hit.append(Vector2i(rr, c))
					board[rr][c] = 0
			post_message("Column %d cleared!" % (c + 1), Cfg.WHITE, 1.5)
		"area_bomb":
			if r < 0 or r >= grid_rows or c < 0 or c >= grid_cols:
				return
			@warning_ignore("integer_division")
			var half: int = size / 2
			for dr in size:
				for dc in size:
					var rr: int = r - half + dr
					var cc: int = c - half + dc
					if rr >= 0 and rr < grid_rows and cc >= 0 and cc < grid_cols and is_clearable(board[rr][cc]):
						hit.append(Vector2i(rr, cc))
						board[rr][cc] = 0
			post_message("%dx%d Area bombed!" % [size, size], Cfg.WHITE, 1.5)
		"single_block_remove":
			sfx = Cfg.SFX_ITEM_ERASE
			if r < 0 or r >= grid_rows or c < 0 or c >= grid_cols:
				return
			if is_clearable(board[r][c]):
				hit.append(Vector2i(r, c))
				board[r][c] = 0
				post_message("Block at (%d,%d) erased!" % [r + 1, c + 1], Cfg.WHITE, 1.5)
			else:
				post_message("Nothing to erase there.", Cfg.RED, 1.0)
				pending_effect = {}
				pending_effect_changed.emit()
				return
		_:
			return

	Audio.play(sfx)
	if not hit.is_empty():
		cells_cleared.emit(hit, "bomb")
		Juice.shake(0.28 + 0.01 * hit.size(), 25)
		Juice.hitstop(0.04)

	var extra := check_and_clear_lines()
	if not hit.is_empty() or extra > 0:
		_bump_combo("CARD" if from_card else "ITEM")

	pending_effect = {}
	pending_effect_changed.emit()
	board_changed.emit()
	if not is_game_over:
		check_game_over("No valid moves")


# ==========================================================================
#  Card activation
# ==========================================================================
func activate_card(index: int, double_click := false) -> void:
	if not pending_effect.is_empty() or conjure_active:
		post_message("Finish current action!", Cfg.RED, 1.0)
		return
	if index < 0 or index >= cards.size():
		return

	var card: Dictionary = cards[index]
	var name_eff := effective_name(card)

	match name_eff:
		"Shape Shifter":
			if get_state(card, "used_this_round", false):
				post_message("Shape Shifter (this card) used this round.", Cfg.RED, 1.0)
				return
			if hand.is_empty() or selected_index >= hand.size():
				post_message("No piece to shift!", Cfg.RED, 1.0)
				return
			hand[selected_index] = Cfg.random_shape()
			set_state(card, "used_this_round", true)
			post_message("Shape Shifted!", Cfg.YELLOW, 1.0)
			Audio.play(Cfg.SFX_CARD_MET)
			card_triggered.emit("Shape Shifter")
			hand_changed.emit()
			update_potential_clear_highlight()

		"Soul Stamp":
			if not double_click:
				post_message("Soul Stamp: double-tap to arm.", Cfg.LIGHT_GRAY, 1.0)
				return
			if not get_state(card, "soul_stamp_available", false):
				post_message("Soul Stamp (this card) used up this round.", Cfg.RED, 1.5)
				return
			var armed: bool = not get_state(card, "soul_stamp_active", false)
			set_state(card, "soul_stamp_active", armed)
			post_message("Soul Stamp armed!" if armed else "Soul Stamp disarmed.", Cfg.YELLOW, 1.5)
			Audio.play(Cfg.SFX_CARD_MET)
			card_triggered.emit("Soul Stamp")
			update_potential_clear_highlight()
			inventory_changed.emit()

		"Trashcan":
			if get_state(card, "used_this_round", false):
				post_message("Trashcan (this card) used this round.", Cfg.RED, 1.0)
				return
			if hand.is_empty():
				post_message("No pieces in hand to trash!", Cfg.RED, 1.0)
				return
			if selected_index < 0 or selected_index >= hand.size():
				post_message("Select a piece to trash!", Cfg.RED, 1.0)
				return
			var trashed: String = hand[selected_index]["name"]
			hand.remove_at(selected_index)
			set_state(card, "used_this_round", true)
			post_message("Trashed %s!" % trashed, Cfg.YELLOW, 1.0)
			Audio.play(Cfg.SFX_ITEM_ERASE)
			card_triggered.emit("Trashcan")
			selected_index = 0
			hand_changed.emit()
			update_potential_clear_highlight()
			if not can_any_piece_be_placed():
				check_game_over("No valid moves")

		"Barrel":
			if get_state(card, "used_this_round", false):
				post_message("Barrel (this card) used this round.", Cfg.RED, 1.0)
				return
			if hand.is_empty() or selected_index >= hand.size():
				post_message("No pieces in hand to rotate!", Cfg.RED, 1.0)
				return
			var shape: Dictionary = hand[selected_index]
			shape["coords"] = Cfg.rotate_shape_coords(shape["coords"])
			set_state(card, "used_this_round", true)
			post_message("Barrel Roll! %s rotated." % shape.get("name", "Piece"), Cfg.YELLOW, 1.0)
			Audio.play(Cfg.SFX_CARD_MET)
			card_triggered.emit("Barrel")
			hand_changed.emit()
			update_potential_clear_highlight()

		_:
			post_message("%s has no tap action." % name_eff, Cfg.LIGHT_GRAY, 1.0)


## The Mimic starts copying `target_name`; one change per round.
func set_mimic_target(index: int, target_name: String) -> bool:
	if index < 0 or index >= cards.size():
		return false
	var card: Dictionary = cards[index]
	if card["name"] != "The Mimic":
		return false
	# The once-per-round budget belongs to The Mimic itself, so read it straight
	# off `state` -- get_state() would redirect into the copied card's state.
	if not bool(card.get("state", {}).get("mimic_change_available", true)):
		post_message("Mimic change on cooldown this round.", Cfg.RED, 1.0)
		return false
	card["mimic"] = target_name
	card["state"]["mimic_change_available"] = false
	init_mimic_state(card, target_name)
	post_message("Mimic now copying %s!" % target_name, Cfg.YELLOW, 1.5)
	Audio.play(Cfg.SFX_CARD_MET)
	recalculate_passives()
	inventory_changed.emit()
	return true


func mimicable_targets(mimic_index: int) -> Array:
	var out: Array = []
	for i in cards.size():
		if i == mimic_index:
			continue
		var master := Cards.card(cards[i]["name"])
		if master.get("mimicable", true):
			out.append({"index": i, "name": cards[i]["name"], "rarity": cards[i]["rarity"]})
	return out


func merlin_can_reselect(index: int) -> bool:
	if index < 0 or index >= cards.size():
		return false
	return round_count >= int(get_state(cards[index], "selection_cooldown_round", 0))


func set_merlin_piece(index: int, shape_name: String) -> void:
	if index < 0 or index >= cards.size():
		return
	var card: Dictionary = cards[index]
	if not merlin_can_reselect(index):
		post_message("Merlin's hat selection on cooldown.", Cfg.RED, 1.0)
		return
	set_state(card, "chosen_piece_name", shape_name)
	set_state(card, "selection_cooldown_round", round_count + 5)
	post_message("Merlin's hat targets %s!" % shape_name, Cfg.cosmic_color, 1.5)
	Audio.play(Cfg.SFX_CARD_MET)
	card_triggered.emit("Merlin's Hat")
	inventory_changed.emit()
	generate_hand()


# ==========================================================================
#  Pocket Dimension
# ==========================================================================
func pocket_piece(index: int) -> void:
	if not has_card("Pocket Dimension"):
		return
	if index < 0 or index >= hand.size():
		return
	Audio.play(Cfg.SFX_POCKET)
	if pocketed_piece == null:
		pocketed_piece = hand[index]
		hand.remove_at(index)
		post_message("Pocketed %s" % pocketed_piece["name"], Cfg.YELLOW, 1.0)
	else:
		var swapped_in: Dictionary = pocketed_piece
		pocketed_piece = hand[index]
		hand[index] = swapped_in
		post_message("Swapped %s with %s" % [pocketed_piece["name"], swapped_in["name"]], Cfg.YELLOW, 1.0)
	selected_index = 0 if hand.is_empty() else mini(index, hand.size() - 1)
	if hand.is_empty():
		generate_hand()
	hand_changed.emit()
	update_potential_clear_highlight()


func unpocket_piece() -> void:
	if pocketed_piece == null or not has_card("Pocket Dimension"):
		return
	Audio.play(Cfg.SFX_POCKET)
	hand.append(pocketed_piece)
	post_message("Unpocketed %s" % pocketed_piece["name"], Cfg.YELLOW, 1.0)
	pocketed_piece = null
	selected_index = hand.size() - 1
	hand_changed.emit()
	update_potential_clear_highlight()


# ==========================================================================
#  Game over
# ==========================================================================
func check_game_over(reason := "", force := false) -> void:
	if is_game_over:
		return
	if not force and can_any_piece_be_placed():
		return

	var eternal: Variant = find_contract("Eternal Youth")
	if eternal != null:
		if not reason.is_empty():
			post_message("%s triggered death, but..." % reason, Cfg.ORANGE, 1.5)
		post_message("ETERNAL YOUTH ACTIVATED!", Cfg.GREEN, 3.0)
		Audio.play(Cfg.SFX_DEAL_WITH_DEATH)
		Juice.flash(Cfg.GREEN, 0.6, 0.8)
		Juice.shake(0.7, 100)

		@warning_ignore("integer_division")
		round_count = maxi(1, round_count / 2)
		post_message("Rounds set to %d." % round_count, Cfg.YELLOW, 1.5)

		@warning_ignore("integer_division")
		var lose_count: int = cards.size() / 2
		for _i in lose_count:
			if cards.is_empty():
				break
			var idx := randi() % cards.size()
			post_message("Lost card: %s" % cards[idx]["name"], Cfg.RED, 1.0)
			cards.remove_at(idx)

		@warning_ignore("integer_division")
		score = score / 2
		post_message("Score halved to %d." % score, Cfg.YELLOW, 1.5)

		_wipe_board("Eternal Youth")
		contracts.erase(eternal)
		recalculate_passives()
		generate_hand()
		sets_placed_in_round = 0
		combo_streak = 0
		combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
		Juice.set_combo(0)
		combo_changed.emit(combo_streak, combo_miss_allowance)
		inventory_changed.emit()
		stats_changed.emit()
		board_changed.emit()
		return

	var deal: Variant = find_card("Deal with Death")
	if deal != null:
		post_message("DEAL WITH DEATH!", Cfg.RED, 3.0)
		_wipe_board("Deal with Death")
		money = 0
		cards.erase(deal)
		Audio.play(Cfg.SFX_DEAL_WITH_DEATH)
		Juice.flash(Cfg.RED, 0.6, 0.9)
		Juice.shake(0.8, 120)
		recalculate_passives()
		generate_hand()
		inventory_changed.emit()
		stats_changed.emit()
		board_changed.emit()
		return

	is_game_over = true
	post_message("GAME OVER!", Cfg.RED, 4.0)
	SaveGame.submit_score(score)
	SaveGame.delete_run()
	Audio.play(Cfg.SFX_LOSE)
	Audio.play_music(Cfg.MUSIC_LOBBY)
	Juice.set_combo(0)
	Juice.shake(0.9, 200)
	game_over.emit()
	request_screen.emit("gameover")


func _wipe_board(_source: String) -> void:
	var cleared: Array = []
	for r in grid_rows:
		for c in grid_cols:
			if is_clearable(board[r][c]):
				cleared.append(Vector2i(r, c))
				board[r][c] = 0
	if not cleared.is_empty():
		cells_cleared.emit(cleared, "bomb")


# ==========================================================================
#  Messages
# ==========================================================================
func post_message(text: String, color := Cfg.WHITE, duration := 1.5) -> void:
	message_posted.emit(text, color, duration)


# ==========================================================================
#  Save / load
# ==========================================================================
func _serialize_cell(cell: Variant) -> Variant:
	if not (cell is Dictionary):
		return 0
	var out := {"k": cell.get("k", K_BLOCK), "c": (cell.get("c", Cfg.WHITE) as Color).to_html(false)}
	if cell.get("a", false):
		out["a"] = true
		out["o"] = (cell.get("o", cell.get("c", Cfg.WHITE)) as Color).to_html(false)
	return out


func _deserialize_cell(raw: Variant) -> Variant:
	if not (raw is Dictionary):
		return 0
	var cell := {
		"k": int(raw.get("k", K_BLOCK)),
		"c": Color(String(raw.get("c", "ffffff"))),
		"a": bool(raw.get("a", false)),
	}
	if cell["a"]:
		cell["o"] = Color(String(raw.get("o", "ffffff")))
	return cell


func _serialize_shape(shape: Dictionary) -> Dictionary:
	var coords: Array = []
	for off in shape.get("coords", []):
		coords.append([off.x, off.y])
	return {"name": shape.get("name", ""), "color": (shape.get("color", Cfg.WHITE) as Color).to_html(false), "coords": coords}


func _deserialize_shape(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var coords: Array = []
	for pair in raw.get("coords", []):
		coords.append(Vector2i(int(pair[0]), int(pair[1])))
	return {"name": String(raw.get("name", "")), "color": Color(String(raw.get("color", "ffffff"))), "coords": coords}


func to_save_dict() -> Dictionary:
	var board_out: Array = []
	for r in grid_rows:
		var row: Array = []
		for c in grid_cols:
			row.append(_serialize_cell(board[r][c]))
		board_out.append(row)
	var hand_out: Array = []
	for shape in hand:
		hand_out.append(_serialize_shape(shape))
	return {
		"version": 1,
		"grid_rows": grid_rows, "grid_cols": grid_cols, "board": board_out,
		"hand": hand_out, "selected_index": selected_index,
		"pocketed": _serialize_shape(pocketed_piece) if pocketed_piece != null else null,
		"score": score, "money": money, "round_count": round_count,
		"sets_placed_in_round": sets_placed_in_round,
		"cards": cards, "items": items, "perks": perks, "contracts": contracts,
		"combo_streak": combo_streak, "combo_miss_allowance": combo_miss_allowance,
		"obstacles_on_board": obstacles_on_board,
		"boss_active": boss_active, "boss_next_line": boss_next_line,
		"boss_next_is_row": boss_next_is_row, "boss_warning_active": boss_warning_active,
	}


func from_save_dict(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	reset_run()
	grid_rows = int(data.get("grid_rows", Cfg.GRID_ROWS_DEFAULT))
	grid_cols = int(data.get("grid_cols", Cfg.GRID_COLS_DEFAULT))
	_make_empty_board()
	var raw_board: Array = data.get("board", [])
	for r in mini(grid_rows, raw_board.size()):
		var raw_row: Array = raw_board[r]
		for c in mini(grid_cols, raw_row.size()):
			board[r][c] = _deserialize_cell(raw_row[c])

	hand = []
	for raw in data.get("hand", []):
		var shape := _deserialize_shape(raw)
		if not shape.is_empty():
			hand.append(shape)
	selected_index = clampi(int(data.get("selected_index", 0)), 0, maxi(0, hand.size() - 1))
	var pocket: Variant = data.get("pocketed", null)
	pocketed_piece = _deserialize_shape(pocket) if pocket is Dictionary else null

	score = int(data.get("score", 0))
	money = int(data.get("money", Cfg.STARTING_MONEY))
	round_count = int(data.get("round_count", 1))
	sets_placed_in_round = int(data.get("sets_placed_in_round", 1))
	cards = _revive_list(data.get("cards", []))
	items = _revive_list(data.get("items", []))
	perks = _revive_list(data.get("perks", []))
	contracts = _revive_list(data.get("contracts", []))
	combo_streak = int(data.get("combo_streak", 0))
	obstacles_on_board = bool(data.get("obstacles_on_board", false))
	boss_active = bool(data.get("boss_active", false))
	boss_next_line = int(data.get("boss_next_line", -1))
	boss_next_is_row = bool(data.get("boss_next_is_row", false))
	boss_warning_active = bool(data.get("boss_warning_active", false))

	recalculate_passives()
	combo_miss_allowance = clampi(int(data.get("combo_miss_allowance", combo_miss_allowance)),
		0, Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus)
	is_game_over = false
	if hand.is_empty():
		generate_hand()
	Juice.set_combo(combo_streak)
	ghost_pos = Vector2i(grid_rows / 2, grid_cols / 2)
	update_potential_clear_highlight()

	grid_resized.emit()
	board_changed.emit()
	hand_changed.emit()
	inventory_changed.emit()
	stats_changed.emit()
	combo_changed.emit(combo_streak, combo_miss_allowance)
	boss_state_changed.emit()
	return true


## JSON round-trips lose the nested state dicts' types; rebuild them safely.
func _revive_list(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in raw:
		if entry is Dictionary:
			var copy: Dictionary = entry.duplicate(true)
			if not copy.has("state") or not (copy["state"] is Dictionary):
				copy["state"] = {}
			out.append(copy)
	return out


func save_run() -> void:
	if is_game_over:
		return
	SaveGame.save_run(to_save_dict())
