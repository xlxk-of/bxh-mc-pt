extends Node
## Port of config.py -- colours, tuning constants and the block shape table.
## Everything the rules engine reads lives here so balance edits stay in one file.

# ---------------------------------------------------------------- palette
const WHITE      := Color8(255, 255, 255)
const BLACK      := Color8(0, 0, 0)
const GRAY       := Color8(128, 128, 128)
const LIGHT_GRAY := Color8(200, 200, 200)
const DARK_GRAY  := Color8(30, 30, 30)
const RED        := Color8(255, 0, 0)
const GREEN      := Color8(0, 255, 0)
const BLUE       := Color8(0, 0, 255)
const CYAN       := Color8(0, 255, 255)
const MAGENTA    := Color8(255, 0, 255)
const YELLOW     := Color8(255, 255, 0)
const ORANGE     := Color8(255, 165, 0)

const OBSTACLE_COLOR := Color8(80, 80, 80)
const COMBO_TEXT_COLOR := Color8(255, 100, 0)
const MONEY_COLOR := Color8(200, 200, 50)

# UI theme accents (carried over from drawing.py)
const PANEL_FILL     := Color8(22, 22, 36)
const PANEL_BORDER   := Color8(90, 95, 140)
const PANEL_ACCENT   := Color8(120, 140, 220)
const BUTTON_FILL    := Color8(44, 48, 82)
const BUTTON_HOVER   := Color8(78, 92, 168)
const ACCENT_PRIMARY := Color8(255, 210, 90)
const ACCENT_DANGER  := Color8(220, 70, 70)
const ACCENT_GOOD    := Color8(90, 210, 130)
const TEXT_DIM       := Color8(180, 185, 210)

## Cosmic rarity cycles through this palette, one step every COSMIC_FADE_TIME.
const COSMIC_PALETTE: Array[Color] = [
	Color8(148, 0, 211),   # deep purple
	Color8(75, 0, 130),    # indigo
	Color8(0, 0, 255),     # blue
	Color8(0, 191, 255),   # deep sky blue
	Color8(255, 105, 180), # hot pink
	Color8(255, 20, 147),  # deep pink
]
const COSMIC_FADE_TIME := 0.5 # seconds per palette step (was 30 frames @60fps)

const RARITY_ORDER: Array[String] = ["Common", "Rare", "Ultra", "Exotic", "Cosmic"]

const RARITY_COSTS := {
	"Common": 6, "Rare": 12, "Ultra": 20, "Exotic": 60, "Cosmic": 100,
}

const RARITY_BASE_COLORS := {
	"Common": GRAY, "Rare": BLUE, "Ultra": MAGENTA, "Exotic": YELLOW,
	"Cosmic": Color8(148, 0, 211),
}

## Live cosmic colour, advanced by _process. Read via rarity_color().
var cosmic_color: Color = COSMIC_PALETTE[0]
var _cosmic_index := 0
var _cosmic_t := 0.0

# ---------------------------------------------------------------- grid rules
const GRID_ROWS_DEFAULT := 9
const GRID_COLS_DEFAULT := 9
const MIN_GRID_ROWS := 4
const MAX_GRID_ROWS := 12
const MIN_GRID_COLS := 4
const MAX_GRID_COLS := 12

# ---------------------------------------------------------------- mechanics
const MAX_COMBO_CHANCES := 3
const BASE_MONEY_PER_LINE := 1
const INITIAL_MAX_CARDS := 5
const INITIAL_MAX_ITEMS := 3
const SETS_PER_ROUND_DEFAULT := 5
const STARTING_MONEY := 10
const DOUBLE_CLICK_TIME := 0.5   # seconds
const LONG_PRESS_TIME := 0.45    # seconds, touch tooltip / special action
const BASE_SCORE_PER_LINE := 100
const PERFECTIONIST_BONUS := 5000
const SHOP_REROLL_BASE_COST := 5

const LINE_CLEAR_EFFECT_TIME := 0.5   # seconds (was 30 frames)
const GIGA_BOSS_FLASH_TIME := 2.0     # seconds (was 120 frames)

# ---------------------------------------------------------------- shapes
## coords are (row, col) offsets, matching config.SHAPES in the Python build.
const SHAPES: Array[Dictionary] = [
	{"name": "I-vert",   "color": CYAN,       "coords": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)]},
	{"name": "I-horiz",  "color": CYAN,       "coords": [Vector2i(0,0), Vector2i(0,1), Vector2i(0,2), Vector2i(0,3)]},
	{"name": "L",        "color": BLUE,       "coords": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(2,1)]},
	{"name": "J",        "color": ORANGE,     "coords": [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(2,0)]},
	{"name": "T",        "color": MAGENTA,    "coords": [Vector2i(0,0), Vector2i(0,1), Vector2i(0,2), Vector2i(1,1)]},
	{"name": "S",        "color": GREEN,      "coords": [Vector2i(0,1), Vector2i(0,2), Vector2i(1,0), Vector2i(1,1)]},
	{"name": "Z",        "color": RED,        "coords": [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,2)]},
	{"name": "O",        "color": YELLOW,     "coords": [Vector2i(0,0), Vector2i(0,1), Vector2i(1,0), Vector2i(1,1)]},
	{"name": "Dot1",     "color": GRAY,       "coords": [Vector2i(0,0)]},
	{"name": "Dot2-H",   "color": GRAY,       "coords": [Vector2i(0,0), Vector2i(0,1)]},
	{"name": "Dot2-V",   "color": GRAY,       "coords": [Vector2i(0,0), Vector2i(1,0)]},
	{"name": "I-3vert",  "color": LIGHT_GRAY, "coords": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0)]},
	{"name": "I-3horiz", "color": LIGHT_GRAY, "coords": [Vector2i(0,0), Vector2i(0,1), Vector2i(0,2)]},
	{"name": "L-small",  "color": Color8(200,100,50), "coords": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1)]},
]

# ---------------------------------------------------------------- audio keys
const SFX_BLOCK_PLACE       := "sfx_block_place"
const SFX_LINE_CLEAR        := "sfx_line_clear"
const SFX_LINE_CLEAR_COMBO  := "zsfx_line_clear_combo"
const SFX_BOARD_CLEAR       := "sfx_line_clear_high_combo_accent"
const SFX_ITEM_BOMB         := "sfx_item_bomb"
const SFX_ITEM_CONJURE      := "sfx_card_condition_met"
const SFX_ITEM_ERASE        := "sfx_sell"
const SFX_CARD_MET          := "sfx_card_condition_met"
const SFX_BUY               := "sfx_buy"
const SFX_SELL              := "sfx_sell"
const SFX_LOSE              := "sfx_lose"
const SFX_UI_CLICK          := "sfx_ui_click"
const SFX_SHOP_REROLL       := "sfx_ui_click"
const SFX_POCKET            := "sfx_ui_click"
const SFX_OBSTACLE_APPEAR   := "sfx_obstacle_appear"
const SFX_OBSTACLE_CONVERT  := "sfx_card_condition_met"
const SFX_DEAL_WITH_DEATH   := "sfx_dealwithdeath"
const SFX_COMBO             := ["sfx_combo_1", "sfx_combo_2", "sfx_combo_3", "sfx_combo_4", "sfx_combo_5"]
const SFX_BOSS_APPEAR       := "sfx_giga_boss_appear"
const SFX_BOSS_LASER_CHARGE := "wierdlasersound"
const SFX_BOSS_LASER_FIRE   := "sfx_giga_boss_laser_fire"

const MUSIC_MENU   := "music_menu"
const MUSIC_LOBBY  := "music_lobby"
const MUSIC_INGAME := "music_lobby"
const MUSIC_BOSS   := "music_menu_old"


func _process(delta: float) -> void:
	_cosmic_t += delta
	if _cosmic_t >= COSMIC_FADE_TIME:
		_cosmic_t = 0.0
		_cosmic_index = (_cosmic_index + 1) % COSMIC_PALETTE.size()
	var nxt := COSMIC_PALETTE[(_cosmic_index + 1) % COSMIC_PALETTE.size()]
	cosmic_color = COSMIC_PALETTE[_cosmic_index].lerp(nxt, _cosmic_t / COSMIC_FADE_TIME)


## Rarity tint, with Cosmic resolving to the live animated colour.
func rarity_color(rarity: String) -> Color:
	if rarity == "Cosmic":
		return cosmic_color
	return RARITY_BASE_COLORS.get(rarity, WHITE)


func rarity_order(rarity: String) -> int:
	var i := RARITY_ORDER.find(rarity)
	return i if i >= 0 else RARITY_ORDER.size()


func shape_by_name(shape_name: String) -> Dictionary:
	for s in SHAPES:
		if s["name"] == shape_name:
			return s
	return {}


## Deep-ish copy of a shape so rotations never mutate the master table.
func copy_shape(shape: Dictionary) -> Dictionary:
	return {
		"name": shape["name"],
		"color": shape["color"],
		"coords": (shape["coords"] as Array).duplicate(),
	}


func random_shape() -> Dictionary:
	return copy_shape(SHAPES[randi() % SHAPES.size()])


## Bounding size of a shape in cells.
func shape_size(shape: Dictionary) -> Vector2i:
	var coords: Array = shape.get("coords", [])
	if coords.is_empty():
		return Vector2i.ZERO
	var min_r := 9999
	var max_r := -9999
	var min_c := 9999
	var max_c := -9999
	for c in coords:
		min_r = mini(min_r, c.x)
		max_r = maxi(max_r, c.x)
		min_c = mini(min_c, c.y)
		max_c = maxi(max_c, c.y)
	return Vector2i(max_c - min_c + 1, max_r - min_r + 1)


## Rotate 90 degrees clockwise and re-normalise to the origin.
func rotate_shape_coords(coords: Array) -> Array:
	if coords.is_empty():
		return []
	var rotated: Array = []
	for rc in coords:
		rotated.append(Vector2i(rc.y, -rc.x))
	var min_r := 9999
	var min_c := 9999
	for rc in rotated:
		min_r = mini(min_r, rc.x)
		min_c = mini(min_c, rc.y)
	var out: Array = []
	for rc in rotated:
		out.append(Vector2i(rc.x - min_r, rc.y - min_c))
	out.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	return out
