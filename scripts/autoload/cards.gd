extends Node
## Port of game_data.py -- the master tables for cards, items, perks and
## contracts, plus the asset key each entry uses for its 3D model / frame strip.

const MODEL_DIR := "res://assets/models/"
const FRAME_DIR := "res://assets/cards/frames/"

## NOTE: the Python build declared the card as "Star Streak" but every effect
## lookup asked for "Star Streaks", so the card silently did nothing. The port
## uses "Star Streak" consistently, which makes the card work as described.
const CARDS: Array[Dictionary] = [
	{"name": "Shape Shifter", "asset": "shape_shifter", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "click",
	 "description": "(Tap Card) Reroll held piece (1/rnd)."},
	{"name": "Pocket Dimension", "asset": "pocket_dimension", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Dbl-Tap Piece/Pocket) Store 1 piece."},
	{"name": "Downsize", "asset": "downsize", "rarity": "Ultra", "unique": true, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) -1 random row/col (min 4x4). One time on acquire. Adds back on sell."},
	{"name": "Soul Stamp", "asset": "soul_stamp", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "double",
	 "description": "(Dbl-Tap Card) Place over blocks (1 use/rnd)."},
	{"name": "Charming", "asset": "charming", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(On Place) 10% chance for 3x3 bomb to spawn."},
	{"name": "Angel's Kiss", "asset": "angels_kiss", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Each Set: 1 Block is worth $1 when cleared."},
	{"name": "Devil's Luck", "asset": "devils_luck", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Each Set: 33% for: line clear OR tile vanish OR +$3."},
	{"name": "Thrifting", "asset": "thrifting", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) 20% off shop items."},
	{"name": "Deal with Death", "asset": "deal_with_death", "rarity": "Ultra", "unique": true, "mimicable": false,
	 "activation": "passive",
	 "description": "(Passive) On game over: board clears, set money to $0, card is destroyed."},
	{"name": "Skyscraper", "asset": "skyscraper", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "On Vertical Clear, Clear Adjacent Column + 2x Score + Add Item."},
	{"name": "Perfectionist", "asset": "perfectionist", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Board clear (excludes obstacles) = 5,000 Points."},
	{"name": "Star Streak", "asset": "star_streak", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Combo gets 1 extra miss."},
	{"name": "Terraform", "asset": "terraform", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(On Place) Horiz clear: x2 line score."},
	{"name": "Clairvoyance Charm", "asset": "clairvoyance_charm", "rarity": "Ultra", "unique": true, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Potential line clears are brighter. If piece clears 2+ lines, +$5."},
	{"name": "The Mimic", "asset": "the_mimic", "rarity": "Exotic", "unique": true, "mimicable": false,
	 "activation": "special",
	 "description": "(Hold / RMouse) Copies another card's effect. Changeable 1/rnd. Has its own cooldowns."},
	{"name": "Overcharge", "asset": "overcharge", "rarity": "Exotic", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Every 10 combo streak, a 4x4 bomb clears random non-obstacle blocks."},
	{"name": "Window Shopper", "asset": "window_shopper", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) First shop reroll each visit is free."},
	{"name": "Efficiency Expert", "asset": "efficiency_expert", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Rounds require 1 fewer set to complete (min 1, stacks)."},
	{"name": "Echo Chamber", "asset": "echo_chamber", "rarity": "Exotic", "unique": true, "mimicable": false,
	 "activation": "passive",
	 "description": "(Passive) Non-Unique cards can now be found multiple times in the shop."},
	{"name": "Merlin's Hat", "asset": "merlins_hat", "rarity": "Cosmic", "unique": false, "mimicable": true,
	 "activation": "special",
	 "description": "(Hold / RMouse) Increases odds of a chosen piece spawning by 500% (reselect every 5 rnd)."},
	{"name": "Trashcan", "asset": "trashcan", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "click",
	 "description": "(Tap Card) Deletes one selected piece in hand (1/rnd)."},
	{"name": "Barrel", "asset": "barrel", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "click",
	 "description": "Rotate a piece of your choice once to the right (1/rnd)."},
	{"name": "Holy Bomb", "asset": "holy_bomb", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Marks a 3x3 zone; at the next set it fills with holy blocks."},
	{"name": "Duplicator", "asset": "duplicator", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "click",
	 "description": "(Tap Card) Copy the selected piece into your hand (1/rnd)."},
	{"name": "Magma Veins", "asset": "magma_veins", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Line clears melt adjacent obstacles: +150 points each."},
	{"name": "Soul Siphon", "asset": "soul_siphon", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Every 5th combo step siphons +$3."},
	{"name": "Crown of Greed", "asset": "crown_of_greed", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) +$1 for every line you clear."},
	{"name": "Momentum", "asset": "momentum", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(On Place) Clearing 3+ lines at once surges your combo by +5."},
	{"name": "Infernal Engine", "asset": "infernal_engine", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Every 5 clearing placements: +0.5x score mult for the round."},
	{"name": "Hell's Bell", "asset": "hells_bell", "rarity": "Ultra", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Every 10th line cleared rings the Bell: row+column cross blast."},
	{"name": "Frostbrand", "asset": "frostbrand", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) 40% chance the Giga Boss freezes and fumbles its shot."},
	{"name": "Gravity Well", "asset": "gravity_well", "rarity": "Ultra", "unique": true, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) After every set, all blocks slam down and compact."},
	{"name": "Phoenix Feather", "asset": "phoenix_feather", "rarity": "Exotic", "unique": true, "mimicable": false,
	 "activation": "passive",
	 "description": "(Passive) On game over: board clears, hand refreshes, the feather burns."},
	{"name": "Mirror Soul", "asset": "mirror_soul", "rarity": "Exotic", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) 35% chance an item is not consumed when used."},
	{"name": "Demon Pact", "asset": "demon_pact", "rarity": "Cosmic", "unique": true, "mimicable": false,
	 "activation": "passive",
	 "description": "(Passive) All score doubled. The Giga Boss never rests. Sign here."},
	{"name": "Time Shard", "asset": "time_shard", "rarity": "Exotic", "unique": true, "mimicable": false,
	 "activation": "click",
	 "description": "(Tap Card) Refresh every other card's once-per-round use (1 per 3 rnd)."},
	{"name": "Ledger of Souls", "asset": "ledger_of_souls", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Each round: +$1 for every $10 you hold (max $8)."},
	{"name": "Iron Lung", "asset": "iron_lung", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) The first miss each round costs no combo chance."},
	{"name": "Fool's Gold", "asset": "fools_gold", "rarity": "Common", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) The first line clear each round scores x3."},
	{"name": "Second Wind", "asset": "second_wind", "rarity": "Rare", "unique": false, "mimicable": true,
	 "activation": "passive",
	 "description": "(Passive) Once per round, a lost combo keeps half its streak."},
]

const ITEMS: Array[Dictionary] = [
	{"name": "Wide Bomb", "asset": "wide_bomb", "cost": 4, "consumable": true, "rarity": "Common",
	 "description": "Clear chosen row (non-obstacles)."},
	{"name": "Tall Bomb", "asset": "tall_bomb", "cost": 4, "consumable": true, "rarity": "Common",
	 "description": "Clear chosen col (non-obstacles)."},
	{"name": "Small Bomb", "asset": "small_bomb", "cost": 6, "consumable": true, "rarity": "Rare",
	 "description": "Clear 3x3 area (non-obstacles)."},
	{"name": "Magic Ball", "asset": "magic_ball", "cost": 8, "consumable": true, "rarity": "Rare",
	 "description": "Select any standard piece to add to your set."},
	{"name": "Eraser", "asset": "eraser", "cost": 3, "consumable": true, "rarity": "Common",
	 "description": "Remove 1 chosen non-obstacle block."},
	{"name": "Meteor Shard", "asset": "meteor_shard", "cost": 9, "consumable": true, "rarity": "Rare",
	 "description": "Call down a meteor: 5x5 blast plus 300 points."},
	{"name": "Time Crystal", "asset": "time_crystal", "cost": 12, "consumable": true, "rarity": "Ultra",
	 "description": "+1 extra set this round."},
	{"name": "Hell Magnet", "asset": "hell_magnet", "cost": 7, "consumable": true, "rarity": "Rare",
	 "description": "All blocks slam downward and compact."},
	{"name": "Holy Water", "asset": "holy_water", "cost": 10, "consumable": true, "rarity": "Ultra",
	 "description": "Cleanse every obstacle from the board."},
	{"name": "Soul Bomb", "asset": "soul_bomb", "cost": 11, "consumable": true, "rarity": "Ultra",
	 "description": "Detonate a full row and column cross."},
	{"name": "Chaos Dice", "asset": "chaos_dice", "cost": 5, "consumable": true, "rarity": "Common",
	 "description": "Reroll your whole hand and pocket $1 per piece."},
	{"name": "Mason's Chisel", "asset": "masons_chisel", "cost": 6, "consumable": true, "rarity": "Rare",
	 "description": "Every obstacle crumbles into a normal, clearable block."},
	{"name": "Hourglass of Ash", "asset": "hourglass_of_ash", "cost": 8, "consumable": true, "rarity": "Rare",
	 "description": "Your next 3 placements cannot break the combo."},
	{"name": "Lucifer's Whistle", "asset": "lucifers_whistle", "cost": 12, "consumable": true, "rarity": "Ultra",
	 "description": "The Giga Boss loses interest and leaves for this round."},
]

const PERKS: Array[Dictionary] = [
	{"name": "Score Boost Perk", "rarity": "Common", "stackable": true,
	 "description": "+0.5x score mult"},
	{"name": "More Choices Perk", "rarity": "Rare", "stackable": false,
	 "description": "+1 piece option/set"},
	{"name": "Extra Card Pouch", "rarity": "Exotic", "stackable": true,
	 "description": "+1 Card Slot (max 5 extra)"},
	{"name": "Extra Item Belt", "rarity": "Rare", "stackable": true,
	 "description": "+1 Item Slot (max 3 extra)"},
	{"name": "Deep Breath Perk", "rarity": "Common", "stackable": true,
	 "description": "+1 combo chance (max 3)"},
	{"name": "Fat Wallet Perk", "rarity": "Common", "stackable": true,
	 "description": "+$3 each round (max 3)"},
	{"name": "Haggler Perk", "rarity": "Common", "stackable": true,
	 "description": "-10% shop prices (max 3, stacks with Thrifting)"},
	{"name": "Bigger Blast Perk", "rarity": "Rare", "stackable": true,
	 "description": "+2 cells to bomb items (max 2)"},
	{"name": "Cheap Rerolls Perk", "rarity": "Rare", "stackable": false,
	 "description": "Shop rerolls never cost more than $3"},
	{"name": "Sturdy Frame Perk", "rarity": "Rare", "stackable": true,
	 "description": "-1 obstacle per boss round (max 2)"},
	{"name": "Golden Streak Perk", "rarity": "Ultra", "stackable": true,
	 "description": "Combo multiplier counts 50% higher (max 2)"},
	{"name": "Second Skin Perk", "rarity": "Exotic", "stackable": false,
	 "description": "Once per run, death wipes the board instead"},
]

const CONTRACTS: Array[Dictionary] = [
	{"name": "Greedy", "description": "Each card gives $5 every round.",
	 "condition_text": "10% chance they break"},
	{"name": "Just a Favor", "description": "Gain x10 Multi to each connection.",
	 "condition_text": "Lose 10% of money on combo loss"},
	{"name": "Eternal Youth", "description": "You get a second chance when you die.",
	 "condition_text": "Everything is halved"},
	{"name": "Underdog", "description": "Disable all bosses.",
	 "condition_text": "Items are disabled"},
	{"name": "Free Money", "description": "Every round you are bestowed with $20.",
	 "condition_text": "25% chance for cards to go missing"},
]

var _card_by_name := {}
var _item_by_name := {}
var _perk_by_name := {}
var _contract_by_name := {}
var _model_cache := {}
var _frames_cache := {}


func _ready() -> void:
	for c in CARDS:
		_card_by_name[c["name"]] = c
	for i in ITEMS:
		_item_by_name[i["name"]] = i
	for p in PERKS:
		_perk_by_name[p["name"]] = p
	for c in CONTRACTS:
		_contract_by_name[c["name"]] = c


func card(card_name: String) -> Dictionary:
	return _card_by_name.get(card_name, {})


func item(item_name: String) -> Dictionary:
	return _item_by_name.get(item_name, {})


func perk(perk_name: String) -> Dictionary:
	return _perk_by_name.get(perk_name, {})


func contract(contract_name: String) -> Dictionary:
	return _contract_by_name.get(contract_name, {})


func card_cost(card_name: String) -> int:
	var c := card(card_name)
	return Cfg.RARITY_COSTS.get(c.get("rarity", "Common"), 0)


## Make a fresh, savable instance of a master card entry.
func new_card_instance(card_name: String) -> Dictionary:
	var master := card(card_name)
	if master.is_empty():
		return {}
	return {"name": card_name, "rarity": master["rarity"], "state": {}, "mimic": ""}


func new_item_instance(item_name: String) -> Dictionary:
	var master := item(item_name)
	if master.is_empty():
		return {}
	return {"name": item_name, "cost": master["cost"], "rarity": master["rarity"]}


func asset_key(entry_name: String) -> String:
	if _card_by_name.has(entry_name):
		return _card_by_name[entry_name].get("asset", "")
	if _item_by_name.has(entry_name):
		return _item_by_name[entry_name].get("asset", "")
	return ""


## Cached PackedScene for a card/item 3D model, or null when there is none.
##
## Sculpted entries ship a .glb exported from Blender. Entries added since then
## are built in-engine out of primitive meshes and live as .tscn beside them, so
## both kinds are looked up the same way and CardIcon cannot tell them apart.
func model_scene(key: String) -> PackedScene:
	if key.is_empty():
		return null
	if _model_cache.has(key):
		return _model_cache[key]
	var scene: PackedScene = null
	for ext: String in [".glb", ".tscn"]:
		var path := MODEL_DIR + key + "/" + key + ext
		if ResourceLoader.exists(path):
			scene = load(path)
			break
	_model_cache[key] = scene
	return scene


## Cached SpriteFrames built from the pre-rendered turntable PNG strip.
## Used as the low-cost icon on constrained devices and as a model fallback.
func frames(key: String) -> SpriteFrames:
	if key.is_empty():
		return null
	if _frames_cache.has(key):
		return _frames_cache[key]
	var sf: SpriteFrames = null
	var dir_path := FRAME_DIR + key
	if DirAccess.dir_exists_absolute(dir_path):
		var files := DirAccess.get_files_at(dir_path)
		var pngs: Array[String] = []
		for f in files:
			var clean := f.trim_suffix(".remap").trim_suffix(".import")
			if clean.ends_with(".png") and not pngs.has(clean):
				pngs.append(clean)
		pngs.sort()
		if not pngs.is_empty():
			sf = SpriteFrames.new()
			sf.set_animation_speed("default", 15.0)
			sf.set_animation_loop("default", true)
			for f in pngs:
				var tex: Texture2D = load(dir_path + "/" + f)
				if tex:
					sf.add_frame("default", tex)
	_frames_cache[key] = sf
	return sf


## Shop rarity weights, matching generate_shop_offers().
func rarity_weight(rarity: String) -> float:
	match rarity:
		"Common": return 10.0
		"Rare": return 5.0
		"Ultra": return 2.0
		"Exotic": return 1.0
		"Cosmic": return 0.5
	return 3.0
