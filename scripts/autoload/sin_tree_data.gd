class_name SinTreeData
extends RefCounted
## The Sin Tree: the permanent upgrade graph bought with Soul Embers, seven
## branches of five tiers each. Pure data plus lookups - Profile owns what is
## owned, what it cost, and what the effects add up to.
##
## Every node names one prerequisite in its own branch and one tier shallower,
## so each branch is a straight chain and no purchase order can ever cycle.
##
## "effect_key" is the whole contract with the rules engine: game_session.gd
## asks Profile.bonus(key) and never learns which node paid for it. That is what
## lets two tiers in the same branch share a key and simply stack, and why a
## node can be rebalanced here without touching a line of game logic.

## Branch colours arrive from the design table as "r, g, b" strings and stay in
## that form so this file stays a transcription of it. Use branch_color().
const BRANCHES: Array[Dictionary] = [
	{"id": "wrath", "name": "Wrath", "color": "220, 70, 70",
	 "blurb": "Burn what will not fall."},
	{"id": "greed", "name": "Greed", "color": "200, 200, 50",
	 "blurb": "Bleed the world for coin."},
	{"id": "pride", "name": "Pride", "color": "255, 210, 90",
	 "blurb": "Let the number speak your name."},
	{"id": "sloth", "name": "Sloth", "color": "120, 140, 220",
	 "blurb": "Endure. Everything else is effort."},
	{"id": "envy", "name": "Envy", "color": "90, 210, 130",
	 "blurb": "What they hold should be yours."},
	{"id": "gluttony", "name": "Gluttony", "color": "255, 165, 0",
	 "blurb": "Room for more. Always more."},
	{"id": "heresy", "name": "Heresy", "color": "148, 0, 211",
	 "blurb": "Break the rules the game was built on."},
]

const NODES: Array[Dictionary] = [
	{"id": "wrath_1", "branch": "wrath", "tier": 1, "cost": 10, "requires": "",
	 "name": "Smoldering Fists", "effect_key": "blast_chance_bonus", "effect_value": 0.05,
	 "description": "5% chance any placed piece detonates a 3x3."},
	{"id": "wrath_2", "branch": "wrath", "tier": 2, "cost": 25, "requires": "wrath_1",
	 "name": "Burning Wake", "effect_key": "obstacle_count_reduction", "effect_value": 1,
	 "description": "Boss rounds seed 1 fewer obstacle."},
	{"id": "wrath_3", "branch": "wrath", "tier": 3, "cost": 55, "requires": "wrath_2",
	 "name": "Cinder Lungs", "effect_key": "blast_chance_bonus", "effect_value": 0.07,
	 "description": "+7% detonation chance; 12% in total."},
	{"id": "wrath_4", "branch": "wrath", "tier": 4, "cost": 110, "requires": "wrath_3",
	 "name": "Rain of Ash", "effect_key": "blast_radius_bonus", "effect_value": 1,
	 "description": "Your detonations widen to 5x5."},
	{"id": "wrath_5", "branch": "wrath", "tier": 5, "cost": 200, "requires": "wrath_4",
	 "name": "SCORCHED EARTH", "effect_key": "boss_laser_feeds_combo", "effect_value": 1,
	 "description": "Every Giga Boss laser now bumps your combo."},

	{"id": "greed_1", "branch": "greed", "tier": 1, "cost": 10, "requires": "",
	 "name": "Copper Tongue", "effect_key": "money_per_line_bonus", "effect_value": 1,
	 "description": "+$1 for every line cleared."},
	{"id": "greed_2", "branch": "greed", "tier": 2, "cost": 25, "requires": "greed_1",
	 "name": "Silver Tongue", "effect_key": "start_money_bonus", "effect_value": 15,
	 "description": "Start each run with $25 instead of $10."},
	{"id": "greed_3", "branch": "greed", "tier": 3, "cost": 55, "requires": "greed_2",
	 "name": "Pawnbroker's Eye", "effect_key": "sell_value_bonus", "effect_value": 0.5,
	 "description": "Cards and items sell for 50% more."},
	{"id": "greed_4", "branch": "greed", "tier": 4, "cost": 110, "requires": "greed_3",
	 "name": "Gilded Ledger", "effect_key": "money_per_line_bonus", "effect_value": 1,
	 "description": "+$1 more per line; +$2 in total."},
	{"id": "greed_5", "branch": "greed", "tier": 5, "cost": 200, "requires": "greed_4",
	 "name": "USURY", "effect_key": "round_interest_rate", "effect_value": 0.15,
	 "description": "Every round ends paying 15% interest on your money."},

	{"id": "pride_1", "branch": "pride", "tier": 1, "cost": 10, "requires": "",
	 "name": "Tall Posture", "effect_key": "score_mult_bonus", "effect_value": 0.15,
	 "description": "+0.15x score multiplier."},
	{"id": "pride_2", "branch": "pride", "tier": 2, "cost": 25, "requires": "pride_1",
	 "name": "Gilded Ego", "effect_key": "score_mult_bonus", "effect_value": 0.25,
	 "description": "+0.25x more; +0.40x in total."},
	{"id": "pride_3", "branch": "pride", "tier": 3, "cost": 55, "requires": "pride_2",
	 "name": "Laurel Crown", "effect_key": "multi_clear_score_bonus", "effect_value": 0.5,
	 "description": "Double and multi clears score 50% higher."},
	{"id": "pride_4", "branch": "pride", "tier": 4, "cost": 110, "requires": "pride_3",
	 "name": "Monument to Self", "effect_key": "score_mult_bonus", "effect_value": 0.5,
	 "description": "+0.50x more; +0.90x in total."},
	{"id": "pride_5", "branch": "pride", "tier": 5, "cost": 200, "requires": "pride_4",
	 "name": "IMMORTAL NAME", "effect_key": "combo_start_streak", "effect_value": 2,
	 "description": "Runs open at combo x2. Your combo never falls below it."},

	{"id": "sloth_1", "branch": "sloth", "tier": 1, "cost": 10, "requires": "",
	 "name": "Deep Breath", "effect_key": "combo_chance_bonus", "effect_value": 1,
	 "description": "+1 miss before the combo breaks."},
	{"id": "sloth_2", "branch": "sloth", "tier": 2, "cost": 25, "requires": "sloth_1",
	 "name": "Heavy Eyelids", "effect_key": "boss_grace_bonus", "effect_value": 1,
	 "description": "The Giga Boss waits 1 extra placement before firing."},
	{"id": "sloth_3", "branch": "sloth", "tier": 3, "cost": 55, "requires": "sloth_2",
	 "name": "Slack Hours", "effect_key": "sets_per_round_reduction", "effect_value": 1,
	 "description": "Rounds end a set early. The shop comes sooner."},
	{"id": "sloth_4", "branch": "sloth", "tier": 4, "cost": 110, "requires": "sloth_3",
	 "name": "Dead Weight", "effect_key": "combo_chance_bonus", "effect_value": 2,
	 "description": "+2 more misses; +3 in total."},
	{"id": "sloth_5", "branch": "sloth", "tier": 5, "cost": 200, "requires": "sloth_4",
	 "name": "SECOND WIND", "effect_key": "revive_once", "effect_value": 1,
	 "description": "Once per run, death wipes the board instead."},

	{"id": "envy_1", "branch": "envy", "tier": 1, "cost": 10, "requires": "",
	 "name": "Sticky Fingers", "effect_key": "shop_card_slots_bonus", "effect_value": 1,
	 "description": "+1 card on offer in every shop."},
	{"id": "envy_2", "branch": "envy", "tier": 2, "cost": 25, "requires": "envy_1",
	 "name": "Green Eyes", "effect_key": "shop_rarity_weight_bonus", "effect_value": 0.35,
	 "description": "Rare and better cards surface 35% more often."},
	{"id": "envy_3", "branch": "envy", "tier": 3, "cost": 55, "requires": "envy_2",
	 "name": "Covetous Hands", "effect_key": "shop_item_slots_bonus", "effect_value": 1,
	 "description": "+1 item on offer in every shop."},
	{"id": "envy_4", "branch": "envy", "tier": 4, "cost": 110, "requires": "envy_3",
	 "name": "Never Enough", "effect_key": "shop_card_slots_bonus", "effect_value": 1,
	 "description": "+1 more card on offer; +2 in total."},
	{"id": "envy_5", "branch": "envy", "tier": 5, "cost": 200, "requires": "envy_4",
	 "name": "COLLECTOR", "effect_key": "shop_reroll_fixed_cost", "effect_value": 1,
	 "description": "Shop rerolls cost $1. Always. They never climb."},

	{"id": "gluttony_1", "branch": "gluttony", "tier": 1, "cost": 10, "requires": "",
	 "name": "Big Appetite", "effect_key": "item_slot_bonus", "effect_value": 1,
	 "description": "+1 item slot."},
	{"id": "gluttony_2", "branch": "gluttony", "tier": 2, "cost": 25, "requires": "gluttony_1",
	 "name": "Wide Gullet", "effect_key": "bomb_size_bonus", "effect_value": 2,
	 "description": "Item bombs swallow 5x5 instead of 3x3."},
	{"id": "gluttony_3", "branch": "gluttony", "tier": 3, "cost": 55, "requires": "gluttony_2",
	 "name": "Second Stomach", "effect_key": "card_slot_bonus", "effect_value": 1,
	 "description": "+1 card slot."},
	{"id": "gluttony_4", "branch": "gluttony", "tier": 4, "cost": 110, "requires": "gluttony_3",
	 "name": "Gaping Maw", "effect_key": "item_slot_bonus", "effect_value": 1,
	 "description": "+1 more item slot; +2 in total."},
	{"id": "gluttony_5", "branch": "gluttony", "tier": 5, "cost": 200, "requires": "gluttony_4",
	 "name": "DEVOURER", "effect_key": "hand_size_bonus", "effect_value": 1,
	 "description": "+1 piece in every set you are dealt."},

	{"id": "heresy_1", "branch": "heresy", "tier": 1, "cost": 10, "requires": "",
	 "name": "Ash on the Tongue", "effect_key": "start_item_count", "effect_value": 1,
	 "description": "Begin every run holding 1 random item."},
	{"id": "heresy_2", "branch": "heresy", "tier": 2, "cost": 25, "requires": "heresy_1",
	 "name": "Architect's Eye", "effect_key": "next_set_preview", "effect_value": 1,
	 "description": "See the next set of pieces before you commit."},
	{"id": "heresy_3", "branch": "heresy", "tier": 3, "cost": 55, "requires": "heresy_2",
	 "name": "Pocket of Sin", "effect_key": "free_pocket", "effect_value": 1,
	 "description": "Stash 1 piece for later without Pocket Dimension."},
	{"id": "heresy_4", "branch": "heresy", "tier": 4, "cost": 110, "requires": "heresy_3",
	 "name": "Hellforged Hands", "effect_key": "free_rotate", "effect_value": 1,
	 "description": "Rotate any piece in hand, any time. No card needed."},
	{"id": "heresy_5", "branch": "heresy", "tier": 5, "cost": 200, "requires": "heresy_4",
	 "name": "THE WIDENING PIT", "effect_key": "grid_size_bonus", "effect_value": 1,
	 "description": "The board opens 1 row and 1 column wider, forever."},
]

## Returned for an unknown branch so callers can iterate the result blind.
const NO_NODES: Array[Dictionary] = []

static var _node_by_id := {}
static var _branch_by_id := {}
static var _nodes_by_branch := {}
static var _color_by_branch := {}
static var _deepest_tier := 1


## Indexed once when the class is first loaded; the tables are consts, so there
## is never a reason to rebuild.
static func _static_init() -> void:
	for branch_entry: Dictionary in BRANCHES:
		var branch_id: String = branch_entry["id"]
		_branch_by_id[branch_id] = branch_entry
		_color_by_branch[branch_id] = _parse_color(branch_entry["color"])
		var chain: Array[Dictionary] = []
		_nodes_by_branch[branch_id] = chain
	for node_entry: Dictionary in NODES:
		_node_by_id[node_entry["id"]] = node_entry
		var branch_id: String = node_entry["branch"]
		if not _nodes_by_branch.has(branch_id):
			# A node naming a branch that BRANCHES does not list would otherwise
			# be unreachable from every screen instead of merely misfiled.
			var orphans: Array[Dictionary] = []
			_nodes_by_branch[branch_id] = orphans
		_nodes_by_branch[branch_id].append(node_entry)
		_deepest_tier = maxi(_deepest_tier, int(node_entry["tier"]))


# ==========================================================================
#  Lookups
# ==========================================================================
## The master entry for a node id, or {} when no node carries it. Callers get
## the shared table row, exactly as Cards.card() hands out its master rows.
static func node(node_id: String) -> Dictionary:
	return _node_by_id.get(node_id, {})


static func branch(branch_id: String) -> Dictionary:
	return _branch_by_id.get(branch_id, {})


## Every node of one branch in table order, which is tier order. Shared, so a
## screen may read it but must not sort or append to it.
static func nodes_in_branch(branch_id: String) -> Array[Dictionary]:
	return _nodes_by_branch.get(branch_id, NO_NODES)


static func branch_color(branch_id: String) -> Color:
	return _color_by_branch.get(branch_id, Color.WHITE)


## Deepest tier in the whole tree - the row count a branch column needs.
static func max_tier() -> int:
	return _deepest_tier


static func _parse_color(rgb: String) -> Color:
	var parts := rgb.split(",", false)
	if parts.size() < 3:
		return Color.WHITE
	return Color8(parts[0].strip_edges().to_int(), parts[1].strip_edges().to_int(),
		parts[2].strip_edges().to_int())
