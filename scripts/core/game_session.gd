class_name GameSession
extends Node
## Full port of game_state.py -- board, scoring, combos, every card, item, perk
## and contract, the Giga Boss and every game-over path, plus the cross-run Sin
## Tree bonuses read from the Profile autoload.
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
var next_hand: Array = []            # Architect's Eye preview; empty when unearned
var selected_index := 0
var ghost_pos := Vector2i.ZERO
var pocketed_piece: Variant = null

var score := 0
var money := Cfg.STARTING_MONEY
var round_count := 1
var sets_placed_in_round := 1
var sets_per_round_target := Cfg.SETS_PER_ROUND_DEFAULT
var bonus_sets_this_round := 0

var cards: Array = []
var items: Array = []
var perks: Array = []
var contracts: Array = []
var max_cards := Cfg.INITIAL_MAX_CARDS
var max_items := Cfg.INITIAL_MAX_ITEMS

var combo_streak := 0
var combo_miss_allowance := Cfg.MAX_COMBO_CHANCES
var combo_allowance_bonus := 0
var combo_shield := 0

var passive := {}
var obstacles_on_board := false
var is_game_over := false
## Soul Embers this run paid out, read by the game-over screen.
var last_run_embers := 0
var second_skin_used := false
var sin_revive_used := false

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
var boss_grace_left := 0   # Heavy Eyelids: placements the warned shot still waits

var _clear_lock := false   # guards re-entrant clears during cascades


func _init() -> void:
	reset_run()


# ==========================================================================
#  Setup / lifecycle
# ==========================================================================
func reset_run() -> void:
	# The Widening Pit is permanent, so the board it opens is part of the reset.
	var grid_bonus := int(Profile.bonus("grid_size_bonus"))
	grid_rows = mini(Cfg.MAX_GRID_ROWS, Cfg.GRID_ROWS_DEFAULT + grid_bonus)
	grid_cols = mini(Cfg.MAX_GRID_COLS, Cfg.GRID_COLS_DEFAULT + grid_bonus)
	_make_empty_board()

	hand = []
	next_hand = []
	selected_index = 0
	ghost_pos = Vector2i(grid_rows / 2, grid_cols / 2)
	pocketed_piece = null

	score = 0
	money = Cfg.STARTING_MONEY + int(Profile.bonus("start_money_bonus"))
	round_count = 1
	sets_placed_in_round = 1
	sets_per_round_target = Cfg.SETS_PER_ROUND_DEFAULT
	bonus_sets_this_round = 0

	cards = []
	items = []
	perks = []
	contracts = []
	max_cards = Cfg.INITIAL_MAX_CARDS
	max_items = Cfg.INITIAL_MAX_ITEMS

	combo_streak = int(Profile.bonus("combo_start_streak"))
	combo_allowance_bonus = 0
	combo_miss_allowance = Cfg.MAX_COMBO_CHANCES
	combo_shield = 0

	obstacles_on_board = false
	is_game_over = false
	second_skin_used = false
	sin_revive_used = false
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
	boss_grace_left = 0

	recalculate_passives()
	shop_reroll_cost = _base_reroll_cost()
	_grant_starting_items()


## Ash on the Tongue hands the run a random item before the first piece drops.
## Safe inside reset_run() because from_save_dict() overwrites `items` after it.
func _grant_starting_items() -> void:
	var count := int(Profile.bonus("start_item_count"))
	if count <= 0 or Cards.ITEMS.is_empty():
		return
	for _i in mini(count, max_items):
		var master: Dictionary = Cards.ITEMS[randi() % Cards.ITEMS.size()]
		items.append(Cards.new_item_instance(master["name"]))


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


func _has_perk(perk_name: String) -> bool:
	for p in perks:
		if p.get("name", "") == perk_name:
			return true
	return false


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
		"Shape Shifter", "Trashcan", "Barrel", "Duplicator":
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
		"Holy Bomb":
			card["state"]["holy_r"] = -1
			card["state"]["holy_c"] = -1
		"Soul Siphon":
			card["state"]["siphon_level"] = 0
		"Infernal Engine":
			card["state"]["engine_clean"] = 0
			card["state"]["engine_bonus"] = 0.0
		"Iron Lung":
			card["state"]["lung_used_this_round"] = false
		"Fool's Gold":
			card["state"]["gold_used_this_round"] = false
		"Second Wind":
			card["state"]["wind_used_this_round"] = false
		"The Mimic":
			card["state"]["mimic_change_available"] = true
			if not String(card.get("mimic", "")).is_empty():
				init_mimic_state(card, card["mimic"])
			else:
				card["mimic_state"] = {}
	# Merlin's Hat keeps chosen_piece_name / selection_cooldown_round across rounds,
	# Hell's Bell keeps bell_count and Time Shard keeps shard_ready_round.


func init_mimic_state(card: Dictionary, mimicked: String) -> void:
	card["mimic_state"] = {}
	if Cards.card(mimicked).is_empty():
		return
	match mimicked:
		"Shape Shifter", "Trashcan", "Barrel", "Duplicator":
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
		"Holy Bomb":
			card["mimic_state"]["holy_r"] = -1
			card["mimic_state"]["holy_c"] = -1
		"Soul Siphon":
			card["mimic_state"]["siphon_level"] = 0
		"Infernal Engine":
			card["mimic_state"]["engine_clean"] = 0
			card["mimic_state"]["engine_bonus"] = 0.0
		"Iron Lung":
			card["mimic_state"]["lung_used_this_round"] = false
		"Fool's Gold":
			card["mimic_state"]["gold_used_this_round"] = false
		"Second Wind":
			card["mimic_state"]["wind_used_this_round"] = false


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
		"score_double": false,
		"round_income": 0,
		"bomb_size_bonus": 0,
		"reroll_cap": 0,
		"obstacle_reduction": 0,
		"combo_scale": 1.0,
	}
	sets_per_round_target = Cfg.SETS_PER_ROUND_DEFAULT

	# One pass over the perks; the counts below feed blocks further down, so this
	# has to finish before the combo allowance and the slot caps are computed.
	var breaths := 0
	var wallets := 0
	var hagglers := 0
	var blasts := 0
	var frames := 0
	var gilders := 0
	var pouches := 0
	var belts := 0
	var cheap_rerolls := false
	for p in perks:
		match p.get("name", ""):
			"Score Boost Perk":
				passive["score_multiplier_bonus"] += 0.5
			"More Choices Perk":
				passive["extra_piece_in_set"] = 1
			"Deep Breath Perk":
				breaths += 1
			"Fat Wallet Perk":
				wallets += 1
			"Haggler Perk":
				hagglers += 1
			"Bigger Blast Perk":
				blasts += 1
			"Cheap Rerolls Perk":
				cheap_rerolls = true
			"Sturdy Frame Perk":
				frames += 1
			"Golden Streak Perk":
				gilders += 1
			"Extra Card Pouch":
				pouches += 1
			"Extra Item Belt":
				belts += 1
	breaths = mini(3, breaths)
	passive["round_income"] = 3 * mini(3, wallets)
	# Kept even so apply_clear_effect()'s size / 2 centring stays on the tapped cell.
	passive["bomb_size_bonus"] = 2 * mini(2, blasts) + int(Profile.bonus("bomb_size_bonus"))
	passive["reroll_cap"] = 3 if cheap_rerolls else 0
	passive["obstacle_reduction"] = mini(2, frames)
	passive["combo_scale"] = 1.0 + 0.5 * mini(2, gilders)

	# "Just a Favor": x10 multi while the curse still stands.
	if contract_curse_active("Just a Favor"):
		passive["score_multiplier_bonus"] += 9.0

	passive["score_multiplier_bonus"] += Profile.bonus("score_mult_bonus")

	for card in cards:
		if card.get("name", "") == "Echo Chamber":
			passive["cards_can_duplicate"] = true
		if card.get("name", "") == "Demon Pact":
			passive["score_double"] = true
		if effective_name(card) == "Infernal Engine":
			passive["score_multiplier_bonus"] += float(get_state(card, "engine_bonus", 0.0))

	# Capped below 1.0 so no stack of discounts can ever make a shop entry free.
	passive["shop_discount"] = minf(0.90, count_cards("Thrifting") * 0.20 + 0.10 * mini(3, hagglers))
	# Time Crystal adds after the Efficiency Expert subtraction, or the two cancel.
	sets_per_round_target = maxi(1, Cfg.SETS_PER_ROUND_DEFAULT - count_cards("Efficiency Expert")
		- int(Profile.bonus("sets_per_round_reduction"))) + bonus_sets_this_round

	var streaks := count_cards("Star Streak")
	passive["star_streak_bonus"] = streaks

	var old_max := Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	combo_allowance_bonus = streaks + breaths + int(Profile.bonus("combo_chance_bonus"))
	var new_max := Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	if combo_miss_allowance == old_max:
		combo_miss_allowance = new_max
	else:
		combo_miss_allowance = clampi(combo_miss_allowance + (new_max - old_max), 0, new_max)

	# Perk slot caps.
	max_cards = Cfg.INITIAL_MAX_CARDS + mini(pouches, 5) + int(Profile.bonus("card_slot_bonus"))
	max_items = Cfg.INITIAL_MAX_ITEMS + mini(belts, 3) + int(Profile.bonus("item_slot_bonus"))

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


## Mirror Soul's reflection roll, made once per consumption attempt. Callers ask
## it right where they would otherwise remove the item, so Magic Ball's deferred
## consumption gets the same treatment as an instant one.
func mirror_soul_saves() -> bool:
	var n := count_cards("Mirror Soul")
	if n == 0:
		return false
	if randf() >= minf(0.70, 0.35 * n):
		return false
	post_message("Mirror Soul: item preserved!", Cfg.MAGENTA, 1.0)
	Audio.play(Cfg.SFX_CARD_MET, 0.8)
	card_triggered.emit("Mirror Soul")
	return true


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

	# --- Charming / Smoldering Fists: a blast centred on the piece ---
	var blast_chance: float = (0.10 if has_charming else 0.0) + Profile.bonus("blast_chance_bonus")
	var charming_cleared: Array = []
	if blast_chance > 0.0 and randf() < blast_chance:
		Audio.play(Cfg.SFX_ITEM_BOMB, 0.8)
		if has_charming:
			post_message("Charming Explosion!", Cfg.YELLOW, 1.0)
			card_triggered.emit("Charming")
		else:
			post_message("Smoldering Fists ignite!", Cfg.ORANGE, 1.0)
		var radius: int = 1 + int(Profile.bonus("blast_radius_bonus"))
		var centre := _shape_centre(shape, r, c)
		for dr in range(-radius, radius + 1):
			for dc in range(-radius, radius + 1):
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
	if boss_active and boss_warning_active and boss_grace_left > 0:
		# Heavy Eyelids: the shot is still coming, just not yet.
		boss_grace_left -= 1
		boss_laser_line = -1
		post_message("Giga Boss stalls... %d placement(s) to impact." % (boss_grace_left + 1), Cfg.ORANGE, 1.0)
		boss_state_changed.emit()
	elif boss_active and boss_warning_active:
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
		# Momentum runs before Overcharge, which reads combo_streak / 10 and so
		# has to see the surged value rather than the pre-surge one.
		_apply_momentum(cleared_lines)
		_charge_infernal_engines()
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
	_siphon_souls()
	var label := "COMBO x%d!" % combo_streak
	if not source.is_empty():
		label = "COMBO x%d (%s)!" % [combo_streak, source]
	post_message(label, Cfg.COMBO_TEXT_COLOR, 1.5)
	Juice.set_combo(combo_streak)
	combo_changed.emit(combo_streak, combo_miss_allowance)


## Soul Siphon pays out once per five-step rung of the ladder, so a streak that
## is rebuilt from scratch has to climb past its old rung to pay again.
func _siphon_souls() -> void:
	var paid := false
	for card in cards:
		if effective_name(card) != "Soul Siphon":
			continue
		@warning_ignore("integer_division")
		var lvl: int = combo_streak / 5
		if combo_streak < 5 or lvl <= int(get_state(card, "siphon_level", 0)):
			continue
		money += 3
		set_state(card, "siphon_level", lvl)
		post_message("Soul Siphon: +$3!", Cfg.MONEY_COLOR, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.7)
		card_triggered.emit("Soul Siphon")
		paid = true
	if paid:
		stats_changed.emit()


## Momentum: a triple-or-better clear kicks the streak forward five steps.
func _apply_momentum(cleared_lines: int) -> void:
	var surge := 5 * count_cards("Momentum")
	if cleared_lines < 3 or surge == 0:
		return
	combo_streak += surge
	combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	Audio.play_combo(combo_streak)
	post_message("MOMENTUM! Combo x%d!" % combo_streak, Cfg.COMBO_TEXT_COLOR, 1.5)
	card_triggered.emit("Momentum")
	Juice.set_combo(combo_streak)
	Juice.shake(0.3, 25)
	combo_changed.emit(combo_streak, combo_miss_allowance)


## Infernal Engine banks half a multiplier every fifth clearing placement. The
## bonus is held until the round ends; only the charge counter is fragile.
func _charge_infernal_engines() -> void:
	var fired := false
	for card in cards:
		if effective_name(card) != "Infernal Engine":
			continue
		var clean: int = int(get_state(card, "engine_clean", 0)) + 1
		set_state(card, "engine_clean", clean)
		if clean % 5 != 0:
			continue
		set_state(card, "engine_bonus", float(get_state(card, "engine_bonus", 0.0)) + 0.5)
		post_message("Infernal Engine: +0.5x mult!", Cfg.ORANGE, 1.5)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Infernal Engine")
		fired = true
	if fired:
		recalculate_passives()


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

	if combo_shield > 0:
		combo_shield -= 1
		post_message("Ash shield absorbs the miss (%d left)." % combo_shield, Cfg.CYAN, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.6)
		combo_changed.emit(combo_streak, combo_miss_allowance)
		return

	# One Iron Lung per miss, so two copies buy two free misses in a round.
	for card in cards:
		if effective_name(card) != "Iron Lung" or get_state(card, "lung_used_this_round", false):
			continue
		set_state(card, "lung_used_this_round", true)
		post_message("Iron Lung holds the combo!", Cfg.GREEN, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.7)
		card_triggered.emit("Iron Lung")
		combo_changed.emit(combo_streak, combo_miss_allowance)
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

	# Second Wind pre-empts the loss outright, so the Just a Favor toll below it
	# never fires: a held combo is not a lost one.
	for card in cards:
		if effective_name(card) != "Second Wind":
			continue
		if get_state(card, "wind_used_this_round", false) or combo_streak < 4:
			continue
		set_state(card, "wind_used_this_round", true)
		@warning_ignore("integer_division")
		combo_streak = combo_streak / 2
		combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
		for other in cards:
			match effective_name(other):
				"Star Streak":
					set_state(other, "insurance_used_this_combo", false)
				"Soul Siphon":
					@warning_ignore("integer_division")
					set_state(other, "siphon_level", combo_streak / 5)
		post_message("Second Wind! Combo held at x%d." % combo_streak, Cfg.GREEN, 1.5)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Second Wind")
		Juice.set_combo(combo_streak)
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

	# Immortal Name keeps a floor under the streak instead of dropping to zero.
	combo_streak = int(Profile.bonus("combo_start_streak"))
	combo_miss_allowance = Cfg.MAX_COMBO_CHANCES + combo_allowance_bonus
	for card in cards:
		match effective_name(card):
			"Star Streak":
				set_state(card, "insurance_used_this_combo", false)
			"Soul Siphon":
				set_state(card, "siphon_level", 0)
			"Infernal Engine":
				set_state(card, "engine_clean", 0)
	Juice.set_combo(combo_streak)
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

	# Must run pre-collapse, while these row/column indices still address real cells.
	_melt_obstacles(rows_to_clear, all_cols)

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


## Magma Veins eats every obstacle orthogonally touching a line as it clears.
func _melt_obstacles(rows: Array, cols: Array) -> void:
	var veins := count_cards("Magma Veins")
	if veins == 0:
		return
	var found: Dictionary = {}
	for r in rows:
		for c in grid_cols:
			_collect_adjacent_obstacles(r, c, found)
	for c in cols:
		for r in grid_rows:
			_collect_adjacent_obstacles(r, c, found)
	if found.is_empty():
		return

	var melted: Array = found.keys()
	for cell_pos in melted:
		board[cell_pos.x][cell_pos.y] = 0
	var gained: int = 150 * melted.size() * veins
	score += gained
	cells_cleared.emit(melted, "bomb")
	post_message("Magma Veins: %d obstacle(s) melted!" % melted.size(), Cfg.ORANGE, 1.5)
	Audio.play(Cfg.SFX_OBSTACLE_CONVERT)
	card_triggered.emit("Magma Veins")
	floating_score.emit("+%d MAGMA" % gained, "score")
	Juice.shake(0.2, 18)
	_rescan_obstacles()


func _collect_adjacent_obstacles(r: int, c: int, found: Dictionary) -> void:
	for step: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var rr: int = r + step.x
		var cc: int = c + step.y
		if rr < 0 or rr >= grid_rows or cc < 0 or cc >= grid_cols:
			continue
		if is_obstacle(board[rr][cc]):
			found[Vector2i(rr, cc)] = true


## obstacles_on_board is the hard-block flag, so drop it the moment none remain
## or placement stays blocked on a board that has nothing left to block it.
func _rescan_obstacles() -> void:
	for r in grid_rows:
		for c in grid_cols:
			if is_obstacle(board[r][c]):
				return
	obstacles_on_board = false


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


## Slam every column down so its cells sit flush at the bottom, obstacles riding
## along like anything else. Returns true when at least one cell changed row.
func _gravity_compact() -> bool:
	var moved := false
	for c in grid_cols:
		var stack: Array = []
		var came_from: Array = []
		for r in grid_rows:
			if not is_empty_cell(board[r][c]):
				stack.append(board[r][c])
				came_from.append(r)
		var top: int = grid_rows - stack.size()
		for i in stack.size():
			if came_from[i] != top + i:
				moved = true
		for r in grid_rows:
			board[r][c] = 0
		for i in stack.size():
			board[top + i][c] = stack[i]
	return moved


func _award_clear(count: int, angel_hits: int, had_rows: bool, had_cols: bool) -> void:
	var earned: int = count * Cfg.BASE_MONEY_PER_LINE
	if count > 1:
		earned += (count - 1) * 2
	# BASE_MONEY_PER_LINE is 1, so a single Crown doubles all line income; that is
	# why it stacks linearly rather than multiplicatively.
	var greed := count_cards("Crown of Greed")
	if greed > 0:
		earned += count * greed
		post_message("Crown of Greed: +$%d!" % (count * greed), Cfg.MONEY_COLOR, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.6)
		card_triggered.emit("Crown of Greed")
	earned += count * int(Profile.bonus("money_per_line_bonus"))
	if angel_hits > 0:
		earned += angel_hits
		post_message("+$%d (Angel's Kiss)!" % angel_hits, Cfg.MONEY_COLOR, 1.0)
		Audio.play(Cfg.SFX_CARD_MET, 0.6)
		card_triggered.emit("Angel's Kiss")
	money += earned

	var mult: float = 1.0 + passive.get("score_multiplier_bonus", 0.0)
	# Scaling the multiplier rather than the total keeps Golden Streak visible in
	# the "%d x %d" text floating_score already prints.
	var combo_mult: int = maxi(1, int(combo_streak * passive.get("combo_scale", 1.0)))
	var line_bonus := 1.0
	if count == 2:
		line_bonus = 2.5
	elif count >= 3:
		line_bonus = count * 1.5
	if count >= 2:
		line_bonus *= 1.0 + Profile.bonus("multi_clear_score_bonus")
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

	# Fool's Gold multiplies line_score rather than the total, so the x3 lands
	# inside the number the floating label already shows.
	var golds := 0
	for card in cards:
		if effective_name(card) != "Fool's Gold" or get_state(card, "gold_used_this_round", false):
			continue
		line_score *= 3.0
		set_state(card, "gold_used_this_round", true)
		golds += 1
	if golds > 0:
		post_message("Fool's Gold x%d!" % int(pow(3, golds)), Cfg.ACCENT_PRIMARY, 1.5)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Fool's Gold")

	var total: float = line_score * mult * combo_mult
	var pact: bool = passive.get("score_double", false)
	if pact:
		total *= 2.0
	score += int(round(total))

	var label := "%d x %d" % [int(round(line_score * mult)), combo_mult]
	if pact:
		label += " x2 PACT"
	floating_score.emit(label, "score")

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

	# The lock keeps the Bell's own cross out of this award; the cascade it makes
	# is re-scored through the normal path once the lock is off.
	if not _clear_lock and count_cards("Hell's Bell") > 0:
		_clear_lock = true
		for card in cards:
			if effective_name(card) != "Hell's Bell":
				continue
			var bell: int = int(get_state(card, "bell_count", 0)) + count
			while bell >= 10:
				bell -= 10
				_ring_hells_bell()
			set_state(card, "bell_count", bell)
		_clear_lock = false
		check_and_clear_lines()

	stats_changed.emit()


## One toll: a full row and column go at once, wherever the Bell happens to point.
func _ring_hells_bell() -> void:
	var br := randi() % grid_rows
	var bc := randi() % grid_cols
	var found: Dictionary = {}
	for c in grid_cols:
		if is_clearable(board[br][c]):
			found[Vector2i(br, c)] = true
	for r in grid_rows:
		if is_clearable(board[r][bc]):
			found[Vector2i(r, bc)] = true
	var hit: Array = found.keys()
	for cell_pos in hit:
		board[cell_pos.x][cell_pos.y] = 0
	if not hit.is_empty():
		cells_cleared.emit(hit, "bomb")
	Audio.play(Cfg.SFX_ITEM_BOMB, 1.1)
	Juice.shake(0.45, 40)
	Juice.flash(Cfg.ORANGE, 0.3, 0.4)
	post_message("HELL'S BELL TOLLS! Row %d, Col %d!" % [br + 1, bc + 1], Cfg.ORANGE, 2.0)
	card_triggered.emit("Hell's Bell")


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
		var to_add: int = maxi(0, 1 + randi() % 3
			- int(passive.get("obstacle_reduction", 0))
			- int(Profile.bonus("obstacle_count_reduction")))
		# A fully suppressed spawn stays silent: no sound, no message, no seeding.
		if to_add > 0:
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
	_detonate_holy_bombs()

	if has_card("Gravity Well") and _gravity_compact():
		post_message("Gravity Well compacts the board!", Cfg.CYAN, 1.5)
		Audio.play(Cfg.SFX_OBSTACLE_CONVERT, 0.8)
		card_triggered.emit("Gravity Well")
		Juice.shake(0.25, 20)
		check_and_clear_lines()
		board_changed.emit()

	if sets_placed_in_round >= sets_per_round_target:
		_advance_round()
	else:
		generate_hand()


## Holy Bomb fills the zone it marked last set, then immediately marks a new one,
## so every fill is telegraphed a full set before it lands.
func _detonate_holy_bombs() -> void:
	var any := false
	for card in cards:
		if effective_name(card) != "Holy Bomb":
			continue
		any = true
		var hr: int = int(get_state(card, "holy_r", -1))
		var hc: int = int(get_state(card, "holy_c", -1))
		if hr >= 0 and hc >= 0:
			var filled: Array = []
			for dr in 3:
				for dc in 3:
					var rr: int = hr + dr
					var cc: int = hc + dc
					if rr < 0 or rr >= grid_rows or cc < 0 or cc >= grid_cols:
						continue
					if is_empty_cell(board[rr][cc]):
						board[rr][cc] = _make_block(Cfg.ACCENT_PRIMARY)
						filled.append(Vector2i(rr, cc))
			if not filled.is_empty():
				piece_placed.emit(filled, Cfg.ACCENT_PRIMARY)
				post_message("Holy Bomb detonates!", Cfg.ACCENT_PRIMARY, 1.5)
				Audio.play(Cfg.SFX_CARD_MET)
				card_triggered.emit("Holy Bomb")
				check_and_clear_lines()

		var next_r := randi() % maxi(1, grid_rows - 2)
		var next_c := randi() % maxi(1, grid_cols - 2)
		set_state(card, "holy_r", next_r)
		set_state(card, "holy_c", next_c)
		post_message("Holy Bomb marks rows %d-%d, cols %d-%d."
			% [next_r + 1, next_r + 3, next_c + 1, next_c + 3], Cfg.ACCENT_PRIMARY, 1.5)
	if any:
		board_changed.emit()


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
	bonus_sets_this_round = 0
	round_count += 1

	for card in cards:
		init_card_state(card)

	_tick_contracts()
	recalculate_passives()
	_apply_round_contracts()
	_pay_round_income()

	# Boss subsides at the round boundary, then may respawn. Demon Pact denies it
	# even that pause.
	if boss_active and not has_card("Demon Pact"):
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

	# Underdog's branch already force-cleared the boss, so it still wins outright.
	if has_card("Demon Pact") and round_count % 5 == 0 and find_contract("Underdog") == null:
		spawn_chance = maxf(spawn_chance, 0.35)

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
		shop_reroll_cost = _base_reroll_cost()
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


## Every round-boundary payout, settled before the shop screen opens. Ledger
## copies compound, each reading the balance the previous one left behind.
func _pay_round_income() -> void:
	var income: int = passive.get("round_income", 0)
	if income > 0:
		money += income
		post_message("Fat Wallet: +$%d!" % income, Cfg.MONEY_COLOR, 1.5)
		Audio.play(Cfg.SFX_BUY, 0.6)

	for card in cards:
		if effective_name(card) != "Ledger of Souls":
			continue
		@warning_ignore("integer_division")
		var interest: int = mini(8, money / 10)
		if interest > 0:
			money += interest
			post_message("Ledger of Souls: +$%d interest!" % interest, Cfg.MONEY_COLOR, 1.5)
			Audio.play(Cfg.SFX_CARD_MET, 0.7)
			card_triggered.emit("Ledger of Souls")

	var rate := Profile.bonus("round_interest_rate")
	if rate > 0.0:
		var usury := int(money * rate)
		if usury > 0:
			money += usury
			post_message("Usury: +$%d interest!" % usury, Cfg.MONEY_COLOR, 1.5)
			Audio.play(Cfg.SFX_CARD_MET, 0.7)

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
	boss_grace_left = int(Profile.bonus("boss_grace_bonus"))
	var kind := "Row" if boss_next_is_row else "Column"
	post_message("Giga Boss: Warning! Next target: %s %d!" % [kind, boss_next_line + 1], Cfg.ORANGE, 1.5)
	boss_state_changed.emit()


func _fire_boss_laser() -> void:
	# Frostbrand skips the damage, never the cycle: the fumbled shot still burns
	# the warning, so the boss has to telegraph a fresh target.
	var freeze := minf(0.80, 0.40 * count_cards("Frostbrand"))
	if freeze > 0.0 and randf() < freeze:
		post_message("Frostbrand: the Giga Boss freezes mid-cast!", Cfg.CYAN, 1.5)
		Audio.play(Cfg.SFX_CARD_MET)
		card_triggered.emit("Frostbrand")
		Juice.flash(Cfg.CYAN, 0.25, 0.3)
		boss_laser_line = -1
		if boss_active:
			_choose_next_boss_target()
		else:
			boss_warning_active = false
			boss_next_line = -1
			boss_state_changed.emit()
		return

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

	# SCORCHED EARTH: the boss's own laser becomes combo fuel.
	if line >= 0 and Profile.bonus("boss_laser_feeds_combo") > 0.0:
		_bump_combo("BOSS")

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
	# Architect's Eye means the set the player was shown is the set they get.
	hand = next_hand if not next_hand.is_empty() else _roll_set()
	next_hand = _roll_set() if Profile.bonus("next_set_preview") > 0.0 else []

	selected_index = 0
	ghost_pos = Vector2i(grid_rows / 2, grid_cols / 2) if not hand.is_empty() else Vector2i.ZERO
	hand_changed.emit()
	update_potential_clear_highlight()


## One Merlin-weighted set of pieces. Split out of generate_hand() so the
## Architect's Eye preview can roll the following set a turn early.
func _roll_set() -> Array:
	var base_count: int = [2, 2, 3][randi() % 3]
	var count: int = base_count + int(passive.get("extra_piece_in_set", 0)) \
		+ int(Profile.bonus("hand_size_bonus"))

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

	var out: Array = []
	for _i in maxi(1, count):
		out.append(Cfg.copy_shape(pool[randi() % pool.size()]))
	return out


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

	var card_slots: int = 3 + int(Profile.bonus("shop_card_slots_bonus"))
	var item_slots: int = 2 + int(Profile.bonus("shop_item_slots_bonus"))
	var bias := Profile.bonus("shop_rarity_weight_bonus")

	if not available.is_empty():
		var chosen: Array = []
		if not can_duplicate:
			# Uniform until Green Eyes is bought; only then does rarity bias the draw.
			if bias > 0.0:
				chosen = _weighted_draw(available, card_slots, bias)
			else:
				var pool: Array = available.duplicate()
				pool.shuffle()
				chosen = pool.slice(0, mini(card_slots, pool.size()))
		else:
			var weights: Array = []
			var total := 0.0
			for m in available:
				var w: float = _shop_weight(m, bias)
				weights.append(w)
				total += w
			for _i in card_slots:
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
	for m in item_pool.slice(0, mini(item_slots, item_pool.size())):
		shop_offers["items"].append({"name": m["name"], "cost": m["cost"], "rarity": m["rarity"]})


## Shop weight for one master entry. Green Eyes lifts everything above Common.
func _shop_weight(master: Dictionary, bias: float) -> float:
	var w: float = Cards.rarity_weight(master.get("rarity", "Common"))
	if master.get("rarity", "Common") != "Common":
		w *= 1.0 + bias
	return w


## Weighted draw without replacement, for the shop that may not repeat a card.
func _weighted_draw(pool: Array, count: int, bias: float) -> Array:
	var remaining: Array = pool.duplicate()
	var out: Array = []
	while out.size() < count and not remaining.is_empty():
		var total := 0.0
		for m in remaining:
			total += _shop_weight(m, bias)
		var roll := randf() * total
		var acc := 0.0
		var picked: int = remaining.size() - 1
		for i in remaining.size():
			acc += _shop_weight(remaining[i], bias)
			if roll <= acc:
				picked = i
				break
		out.append(remaining[picked])
		remaining.remove_at(picked)
	return out


func shop_price(entry_name: String, base_cost: int) -> int:
	var discount: float = passive.get("shop_discount", 0.0)
	return maxi(0, int(base_cost * (1.0 - discount)))


func window_shopper_free_reroll() -> Variant:
	for card in cards:
		if effective_name(card) == "Window Shopper" and not get_state(card, "free_reroll_used_this_shop", false):
			return card
	return null


## Reroll price after Collector (a flat fee that never climbs) and Cheap Rerolls.
func _base_reroll_cost() -> int:
	var fixed := int(Profile.bonus("shop_reroll_fixed_cost"))
	if fixed > 0:
		return fixed
	return _cap_reroll_cost(Cfg.SHOP_REROLL_BASE_COST)


func _cap_reroll_cost(cost: int) -> int:
	var cap: int = passive.get("reroll_cap", 0)
	return mini(cost, cap) if cap > 0 else cost


func reroll_shop() -> bool:
	var free_card: Variant = window_shopper_free_reroll()
	if free_card != null:
		set_state(free_card, "free_reroll_used_this_shop", true)
		generate_shop_offers()
		post_message("Shop Rerolled! (Free)", Cfg.WHITE, 1.0)
		Audio.play(Cfg.SFX_SHOP_REROLL)
		card_triggered.emit("Window Shopper")
		return true
	var fixed := int(Profile.bonus("shop_reroll_fixed_cost"))
	shop_reroll_cost = fixed if fixed > 0 else _cap_reroll_cost(shop_reroll_cost)
	if money >= shop_reroll_cost:
		money -= shop_reroll_cost
		if fixed <= 0:
			shop_reroll_cost = _cap_reroll_cost(shop_reroll_cost + 1)
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
	var base: int = Cfg.RARITY_COSTS.get(card.get("rarity", "Common"), 0) / 2
	return int(base * (1.0 + Profile.bonus("sell_value_bonus")))


func sell_price_for_item(item: Dictionary) -> int:
	@warning_ignore("integer_division")
	var base: int = int(item.get("cost", 0)) / 2
	return int(base * (1.0 + Profile.bonus("sell_value_bonus")))


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
			var size: int = 3 + int(passive.get("bomb_size_bonus", 0))
			pending_effect = {"type": "area_bomb", "size": size, "source": "item"}
			post_message("Tap an area to bomb (%dx%d)!" % [size, size], Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_BOMB)
		"Meteor Shard":
			# Keyed by name, not by size, so Bigger Blast cannot promote a Small
			# Bomb into a meteor and steal the score kicker.
			pending_effect = {
				"type": "area_bomb", "size": 5 + int(passive.get("bomb_size_bonus", 0)),
				"source": "item", "item": "Meteor Shard",
			}
			post_message("Tap an area for the meteor!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_BOMB, 1.15)
		"Soul Bomb":
			pending_effect = {"type": "cross_clear", "source": "item"}
			post_message("Tap a cell for the cross blast!", Cfg.WHITE, 2.0)
			Audio.play(Cfg.SFX_ITEM_BOMB, 1.1)
		"Time Crystal":
			bonus_sets_this_round += 1
			recalculate_passives()
			post_message("Time Crystal: +1 set this round!", Cfg.CYAN, 2.0)
			Audio.play(Cfg.SFX_CARD_MET)
			Juice.flash(Cfg.CYAN, 0.25, 0.3)
		"Hourglass of Ash":
			# Refreshes to 3 rather than stacking.
			combo_shield = 3
			post_message("Hourglass of Ash: 3 placements shielded!", Cfg.CYAN, 2.0)
			Audio.play(Cfg.SFX_CARD_MET)
			Juice.flash(Cfg.CYAN, 0.2, 0.25)
			combo_changed.emit(combo_streak, combo_miss_allowance)
		"Hell Magnet":
			if not _gravity_compact():
				post_message("Nothing to pull down.", Cfg.RED, 1.0)
				return false
			Audio.play(Cfg.SFX_OBSTACLE_CONVERT)
			Juice.shake(0.35, 30)
			post_message("Hell Magnet: board compacted!", Cfg.CYAN, 1.5)
			check_and_clear_lines()
			board_changed.emit()
			check_game_over("No valid moves")
		"Holy Water":
			var washed: Array = []
			for r in grid_rows:
				for c in grid_cols:
					if is_obstacle(board[r][c]):
						washed.append(Vector2i(r, c))
						board[r][c] = 0
			if washed.is_empty():
				post_message("Nothing to cleanse.", Cfg.RED, 1.0)
				return false
			obstacles_on_board = false
			cells_cleared.emit(washed, "vanish")
			Audio.play(Cfg.SFX_OBSTACLE_CONVERT)
			Juice.flash(Cfg.WHITE, 0.3, 0.35)
			post_message("Holy Water cleanses %d obstacle(s)!" % washed.size(), Cfg.WHITE, 1.5)
			check_and_clear_lines()
			board_changed.emit()
		"Mason's Chisel":
			# Mirrors the conversion _advance_round() runs when a boss round ends:
			# Holy Water empties those cells, the Chisel keeps them as material.
			var crumbled := 0
			for r in grid_rows:
				for c in grid_cols:
					if is_obstacle(board[r][c]):
						board[r][c] = _make_block(Cfg.GRAY)
						crumbled += 1
			if crumbled == 0:
				post_message("No obstacles to work.", Cfg.RED, 1.0)
				return false
			obstacles_on_board = false
			Audio.play(Cfg.SFX_OBSTACLE_CONVERT)
			Juice.shake(0.3, 22)
			post_message("Mason's Chisel: %d obstacle(s) crumble!" % crumbled, Cfg.WHITE, 1.5)
			check_and_clear_lines()
			board_changed.emit()
		"Chaos Dice":
			# The payout is capped by hand size, so it can never out-earn its cost.
			var rerolled := hand.size()
			if rerolled == 0:
				post_message("No hand to reroll.", Cfg.RED, 1.0)
				return false
			for i in rerolled:
				hand[i] = Cfg.random_shape()
			money += rerolled
			selected_index = 0
			post_message("Chaos Dice: hand rerolled, +$%d!" % rerolled, Cfg.MONEY_COLOR, 1.5)
			Audio.play(Cfg.SFX_SHOP_REROLL)
			Juice.shake(0.2, 15)
			hand_changed.emit()
			stats_changed.emit()
			update_potential_clear_highlight()
			check_game_over("No valid moves")
		"Lucifer's Whistle":
			if not boss_active:
				post_message("No boss to banish.", Cfg.RED, 1.0)
				return false
			boss_active = false
			boss_warning_active = false
			boss_next_line = -1
			# place_piece() checks boss_laser_line after the dust settles and would
			# otherwise fire an orphaned shot from a boss that is already gone.
			boss_laser_line = -1
			boss_grace_left = 0
			post_message("Lucifer's Whistle: the Giga Boss withdraws!", Cfg.GREEN, 2.5)
			Audio.play(Cfg.SFX_BOSS_APPEAR, 0.6)
			Juice.flash(Cfg.GREEN, 0.35, 0.4)
			boss_state_changed.emit()
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

	if consumed and Cards.item(item["name"]).get("consumable", true) and not mirror_soul_saves():
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
	# Magic Ball is spent on the pick, not on the use, so its Mirror Soul roll
	# has to happen here or it would be the one item the card ignored.
	if not mirror_soul_saves():
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
	# Captured up front: pending_effect is wiped before the branches finish with it.
	var src_item: String = pending_effect.get("item", "")
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
			if src_item == "Meteor Shard":
				score += 300
				floating_score.emit("+300 METEOR", "score")
				Juice.shake(0.5, 45)
				Juice.flash(Cfg.ORANGE, 0.3, 0.4)
				stats_changed.emit()
		"cross_clear":
			if r < 0 or r >= grid_rows or c < 0 or c >= grid_cols:
				return
			# Deduped, or the intersection cell would be listed twice.
			var found: Dictionary = {}
			for cc in grid_cols:
				if is_clearable(board[r][cc]):
					found[Vector2i(r, cc)] = true
			for rr in grid_rows:
				if is_clearable(board[rr][c]):
					found[Vector2i(rr, c)] = true
			for cell_pos in found:
				board[cell_pos.x][cell_pos.y] = 0
				hit.append(cell_pos)
			post_message("Cross blast at row %d, col %d!" % [r + 1, c + 1], Cfg.WHITE, 1.5)
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

		"Duplicator":
			if get_state(card, "used_this_round", false):
				post_message("Duplicator (this card) used this round.", Cfg.RED, 1.0)
				return
			if hand.is_empty() or selected_index >= hand.size():
				post_message("No piece to duplicate!", Cfg.RED, 1.0)
				return
			# copy_shape is mandatory: without it a later Barrel roll would rotate
			# both copies at once.
			hand.append(Cfg.copy_shape(hand[selected_index]))
			set_state(card, "used_this_round", true)
			post_message("Duplicated %s!" % hand[selected_index]["name"], Cfg.YELLOW, 1.0)
			Audio.play(Cfg.SFX_CARD_MET)
			card_triggered.emit("Duplicator")
			hand_changed.emit()
			update_potential_clear_highlight()

		"Time Shard":
			var ready_round: int = int(get_state(card, "shard_ready_round", 0))
			if round_count < ready_round:
				post_message("Time Shard recharges on round %d." % ready_round, Cfg.RED, 1.5)
				return
			# init_card_state() already IS the per-round reset, so replaying it on
			# every other card is exactly what "rewind the cooldowns" means.
			for i in cards.size():
				if i != index:
					init_card_state(cards[i])
			set_state(card, "shard_ready_round", round_count + 3)
			post_message("TIME SHARD: cooldowns rewound!", Cfg.CYAN, 2.0)
			Audio.play(Cfg.SFX_CARD_MET)
			card_triggered.emit("Time Shard")
			Juice.flash(Cfg.CYAN, 0.3, 0.35)
			inventory_changed.emit()

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
#  Pocket Dimension / free hand manipulation
# ==========================================================================
## The stash is open to the card holder and to anyone carrying Pocket of Sin.
func can_pocket() -> bool:
	return has_card("Pocket Dimension") or Profile.bonus("free_pocket") > 0.0


## Hellforged Hands: rotate a held piece with no card, no cooldown, no limit.
func free_rotate_available() -> bool:
	return Profile.bonus("free_rotate") > 0.0


func rotate_hand_piece(index: int) -> bool:
	if not free_rotate_available():
		return false
	if index < 0 or index >= hand.size():
		return false
	var shape: Dictionary = hand[index]
	shape["coords"] = Cfg.rotate_shape_coords(shape["coords"])
	post_message("%s rotated." % shape.get("name", "Piece"), Cfg.YELLOW, 1.0)
	Audio.play(Cfg.SFX_CARD_MET, 0.8)
	hand_changed.emit()
	update_potential_clear_highlight()
	return true


func pocket_piece(index: int) -> void:
	if not can_pocket():
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
	if pocketed_piece == null or not can_pocket():
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

	# Phoenix resolves first: it costs nothing but itself, so the harsher bargains
	# below stay in reserve as the true last-ditch saves.
	var feather: Variant = find_card("Phoenix Feather")
	if feather != null:
		post_message("PHOENIX FEATHER BURNS!", Cfg.ORANGE, 3.0)
		_wipe_board("Phoenix Feather")
		cards.erase(feather)
		Audio.play(Cfg.SFX_DEAL_WITH_DEATH)
		Juice.flash(Cfg.ORANGE, 0.6, 0.8)
		Juice.shake(0.7, 100)
		recalculate_passives()
		generate_hand()
		inventory_changed.emit()
		stats_changed.emit()
		board_changed.emit()
		return

	if not second_skin_used and _has_perk("Second Skin Perk"):
		second_skin_used = true
		if not reason.is_empty():
			post_message("%s triggered death, but..." % reason, Cfg.ORANGE, 1.5)
		post_message("SECOND SKIN!", Cfg.GREEN, 3.0)
		_wipe_board("Second Skin")
		Audio.play(Cfg.SFX_DEAL_WITH_DEATH, 0.8)
		Juice.flash(Cfg.GREEN, 0.5, 0.6)
		Juice.shake(0.6, 80)
		generate_hand()
		board_changed.emit()
		stats_changed.emit()
		return

	if not sin_revive_used and Profile.bonus("revive_once") > 0.0:
		sin_revive_used = true
		if not reason.is_empty():
			post_message("%s triggered death, but..." % reason, Cfg.ORANGE, 1.5)
		post_message("SECOND WIND!", Cfg.GREEN, 3.0)
		_wipe_board("Second Wind")
		Audio.play(Cfg.SFX_DEAL_WITH_DEATH, 0.8)
		Juice.flash(Cfg.GREEN, 0.5, 0.6)
		Juice.shake(0.6, 80)
		generate_hand()
		board_changed.emit()
		stats_changed.emit()
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

	# The run is the only thing that dies; the embers it earned outlive it.
	# Kept on the session because the game-over screen mutes the message feed,
	# so a toast here would be the one payout the player never sees.
	last_run_embers = Profile.embers_for_run(score, round_count)
	Profile.award_embers(last_run_embers)

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
	var next_out: Array = []
	for shape in next_hand:
		next_out.append(_serialize_shape(shape))
	return {
		"version": 1,
		"grid_rows": grid_rows, "grid_cols": grid_cols, "board": board_out,
		"hand": hand_out, "next_hand": next_out, "selected_index": selected_index,
		"pocketed": _serialize_shape(pocketed_piece) if pocketed_piece != null else null,
		"score": score, "money": money, "round_count": round_count,
		"sets_placed_in_round": sets_placed_in_round,
		"bonus_sets_this_round": bonus_sets_this_round,
		"cards": cards, "items": items, "perks": perks, "contracts": contracts,
		"combo_streak": combo_streak, "combo_miss_allowance": combo_miss_allowance,
		"combo_shield": combo_shield,
		"obstacles_on_board": obstacles_on_board,
		"second_skin_used": second_skin_used, "sin_revive_used": sin_revive_used,
		"boss_active": boss_active, "boss_next_line": boss_next_line,
		"boss_next_is_row": boss_next_is_row, "boss_warning_active": boss_warning_active,
		"boss_grace_left": boss_grace_left,
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
	next_hand = []
	for raw_next in data.get("next_hand", []):
		var preview := _deserialize_shape(raw_next)
		if not preview.is_empty():
			next_hand.append(preview)
	selected_index = clampi(int(data.get("selected_index", 0)), 0, maxi(0, hand.size() - 1))
	var pocket: Variant = data.get("pocketed", null)
	pocketed_piece = _deserialize_shape(pocket) if pocket is Dictionary else null

	score = int(data.get("score", 0))
	money = int(data.get("money", Cfg.STARTING_MONEY))
	round_count = int(data.get("round_count", 1))
	sets_placed_in_round = int(data.get("sets_placed_in_round", 1))
	# Read before recalculate_passives(), which folds it into sets_per_round_target.
	bonus_sets_this_round = int(data.get("bonus_sets_this_round", 0))
	cards = _revive_list(data.get("cards", []))
	items = _revive_list(data.get("items", []))
	perks = _revive_list(data.get("perks", []))
	contracts = _revive_list(data.get("contracts", []))
	combo_streak = int(data.get("combo_streak", 0))
	combo_shield = maxi(0, int(data.get("combo_shield", 0)))
	obstacles_on_board = bool(data.get("obstacles_on_board", false))
	# Reloading a run must not hand back a save the run has already spent.
	second_skin_used = bool(data.get("second_skin_used", false))
	sin_revive_used = bool(data.get("sin_revive_used", false))
	boss_active = bool(data.get("boss_active", false))
	boss_next_line = int(data.get("boss_next_line", -1))
	boss_next_is_row = bool(data.get("boss_next_is_row", false))
	boss_warning_active = bool(data.get("boss_warning_active", false))
	boss_grace_left = maxi(0, int(data.get("boss_grace_left", 0)))

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
