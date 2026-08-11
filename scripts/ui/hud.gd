class_name HUD
extends Control
## In-game interface. Owns the BoardView and re-flows its panels between a
## landscape three-column layout and a portrait stacked layout.

signal request_dialog(kind: String, payload: Dictionary)
signal request_settings

const CARD_COLS_LANDSCAPE := 3
const SIDE_WIDTH := 250.0

var session: GameSession
var board: BoardView

var _lane: BoxContainer
var _board_holder: Control
var _portrait_built := false
var _built := false

# Live widgets rebuilt with the layout.
var _money_label: Label
var _score_label: Label
var _round_label: Label
var _sets_label: Label
var _combo_label: Label
var _chances_label: Label
var _combo_flame: GPUParticles2D
var _tray_box: BoxContainer
var _pocket_preview: PiecePreview
var _card_grid: GridContainer
var _item_grid: GridContainer
var _perk_list: VBoxContainer
var _contract_list: VBoxContainer
var _previews: Array[PiecePreview] = []
var _card_icons: Array[CardIcon] = []
var _item_icons: Array[CardIcon] = []

var _dragging_index := -1
var _last_card_tap := {}


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	board = BoardView.new()
	board.name = "BoardView"
	Layout.layout_changed.connect(_on_layout_changed)
	Juice.fever_changed.connect(_on_fever_changed)


func bind(new_session: GameSession) -> void:
	UIKit.fill_viewport(self)
	session = new_session
	board.bind(session)
	session.stats_changed.connect(_refresh_stats)
	session.hand_changed.connect(_refresh_tray)
	session.inventory_changed.connect(_refresh_inventory)
	session.combo_changed.connect(_on_combo_changed)
	session.card_triggered.connect(_on_card_triggered)
	_build_layout()


func _on_layout_changed() -> void:
	UIKit.fill_viewport(self)
	if _built and _portrait_built == Layout.portrait:
		return
	_build_layout()


# ==========================================================================
#  Layout construction
# ==========================================================================
func _build_layout() -> void:
	if session == null:
		return
	if board.get_parent() != null:
		board.get_parent().remove_child(board)
	for child in get_children():
		child.queue_free()
	_previews.clear()
	_card_icons.clear()
	_item_icons.clear()
	_portrait_built = Layout.portrait

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := 10 if Layout.portrait else 16
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	add_child(margin)

	_board_holder = Control.new()
	_board_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_holder.add_child(board)

	if Layout.portrait:
		_lane = VBoxContainer.new()
		_lane.add_theme_constant_override("separation", 8)
		margin.add_child(_lane)
		_lane.add_child(_build_top_bar())
		# The board owns the middle of the screen; the strips keep fixed heights
		# so the thumb zone at the bottom stays predictable.
		_board_holder.size_flags_stretch_ratio = 2.0
		_lane.add_child(_board_holder)
		_lane.add_child(_build_inventory_strip())
		_lane.add_child(_build_tray(true))
	else:
		_lane = HBoxContainer.new()
		_lane.add_theme_constant_override("separation", 14)
		margin.add_child(_lane)

		var left := VBoxContainer.new()
		left.custom_minimum_size.x = SIDE_WIDTH
		left.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 12)
		left.add_child(_build_stats_panel())
		left.add_child(_build_tray(false))
		_lane.add_child(left)

		_lane.add_child(_board_holder)

		var right := VBoxContainer.new()
		right.custom_minimum_size.x = SIDE_WIDTH
		right.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 12)
		right.add_child(_build_inventory_panel())
		_lane.add_child(right)

	_built = true
	_refresh_stats()
	_refresh_tray()
	_refresh_inventory()
	_on_combo_changed(session.combo_streak, session.combo_miss_allowance)


func _build_stats_panel() -> Control:
	var panel := UIKit.make_panel(Color(0.08, 0.08, 0.14), Cfg.ACCENT_PRIMARY)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	_money_label = UIKit.make_number("$0", "medium", Cfg.MONEY_COLOR)
	money_row.add_child(_money_label)
	v.add_child(money_row)

	v.add_child(UIKit.make_label("SCORE", "tiny", Cfg.TEXT_DIM))
	_score_label = UIKit.make_number("0", "medium")
	v.add_child(_score_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	v.add_child(grid)
	grid.add_child(UIKit.make_label("ROUND", "tiny", Cfg.TEXT_DIM))
	grid.add_child(UIKit.make_label("SETS", "tiny", Cfg.TEXT_DIM))
	_round_label = UIKit.make_number("1", "small")
	grid.add_child(_round_label)
	_sets_label = UIKit.make_label("1/5", "small")
	grid.add_child(_sets_label)

	v.add_child(UIKit.spacer(4))
	var combo_holder := Control.new()
	combo_holder.custom_minimum_size.y = 34
	v.add_child(combo_holder)
	_combo_label = UIKit.make_number("COMBO ---", "small", Cfg.WHITE)
	_combo_label.position = Vector2(0, 2)
	combo_holder.add_child(_combo_label)
	_combo_flame = _make_flame()
	_combo_flame.position = Vector2(4, 30)
	combo_holder.add_child(_combo_flame)

	_chances_label = UIKit.make_label("Chances: 3", "tiny", Cfg.TEXT_DIM)
	v.add_child(_chances_label)

	v.add_child(UIKit.spacer(6))
	var settings_btn := UIKit.make_button("Menu (Esc)", Cfg.PANEL_ACCENT, "small")
	settings_btn.pressed.connect(func(): request_settings.emit())
	v.add_child(settings_btn)
	return panel


func _build_top_bar() -> Control:
	var panel := UIKit.make_panel(Color(0.08, 0.08, 0.14), Cfg.ACCENT_PRIMARY)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	_money_label = UIKit.make_number("$0", "small", Cfg.MONEY_COLOR)
	h.add_child(_money_label)

	var score_box := VBoxContainer.new()
	score_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_box.add_theme_constant_override("separation", 0)
	score_box.add_child(UIKit.make_label("SCORE", "tiny", Cfg.TEXT_DIM))
	_score_label = UIKit.make_number("0", "small")
	score_box.add_child(_score_label)
	h.add_child(score_box)

	var round_box := VBoxContainer.new()
	round_box.add_theme_constant_override("separation", 0)
	round_box.add_child(UIKit.make_label("ROUND", "tiny", Cfg.TEXT_DIM))
	var rrow := HBoxContainer.new()
	_round_label = UIKit.make_number("1", "small")
	rrow.add_child(_round_label)
	_sets_label = UIKit.make_label(" 1/5", "tiny", Cfg.TEXT_DIM)
	_sets_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	rrow.add_child(_sets_label)
	round_box.add_child(rrow)
	h.add_child(round_box)

	var combo_box := VBoxContainer.new()
	combo_box.add_theme_constant_override("separation", 0)
	combo_box.add_child(UIKit.make_label("COMBO", "tiny", Cfg.TEXT_DIM))
	var combo_row := HBoxContainer.new()
	combo_row.add_theme_constant_override("separation", 6)
	_combo_label = UIKit.make_number("---", "small")
	combo_row.add_child(_combo_label)
	_chances_label = UIKit.make_label("3", "tiny", Cfg.TEXT_DIM)
	_chances_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	combo_row.add_child(_chances_label)
	combo_box.add_child(combo_row)
	h.add_child(combo_box)

	# The flame needs an absolute anchor, so it lives in its own fixed slot.
	var flame_slot := Control.new()
	flame_slot.custom_minimum_size = Vector2(26, 40)
	_combo_flame = _make_flame()
	_combo_flame.position = Vector2(13, 36)
	flame_slot.add_child(_combo_flame)
	h.add_child(flame_slot)

	var btn := UIKit.make_button("≡", Cfg.PANEL_ACCENT, "small")
	btn.custom_minimum_size = Vector2(Layout.touch_size(), Layout.touch_size())
	btn.pressed.connect(func(): request_settings.emit())
	h.add_child(btn)
	return panel


## Flame that grows with the combo fever, echoing the pygame particle emitter.
func _make_flame() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = 40
	p.lifetime = 0.85
	p.emitting = false
	p.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(10, 2, 0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 18.0
	mat.gravity = Vector3(0, -55, 0)
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 70.0
	mat.scale_min = 0.4
	mat.scale_max = 1.1
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 0.5, 0.95), Color(1, 0.45, 0.05, 0.7), Color(0.6, 0.05, 0.0, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat
	var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	p.texture = ImageTexture.create_from_image(img)
	return p


func _build_tray(horizontal: bool) -> Control:
	var panel := UIKit.make_panel(Color(0.07, 0.07, 0.13), Cfg.PANEL_ACCENT)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)
	if not horizontal:
		outer.add_child(UIKit.make_label("NEXT PIECES", "tiny", Cfg.TEXT_DIM))

	if horizontal:
		_tray_box = HBoxContainer.new()
		_tray_box.alignment = BoxContainer.ALIGNMENT_CENTER
	else:
		_tray_box = VBoxContainer.new()
	_tray_box.add_theme_constant_override("separation", 8)
	outer.add_child(_tray_box)
	return panel


func _build_inventory_panel() -> Control:
	var panel := UIKit.make_panel(Color(0.07, 0.07, 0.13), Cfg.PANEL_ACCENT)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	v.add_child(UIKit.make_section("Cards"))
	_card_grid = GridContainer.new()
	_card_grid.columns = CARD_COLS_LANDSCAPE
	_card_grid.add_theme_constant_override("h_separation", 8)
	_card_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_card_grid)

	v.add_child(UIKit.make_section("Items"))
	_item_grid = GridContainer.new()
	_item_grid.columns = CARD_COLS_LANDSCAPE
	_item_grid.add_theme_constant_override("h_separation", 8)
	_item_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_item_grid)

	v.add_child(UIKit.make_section("Perks"))
	_perk_list = VBoxContainer.new()
	_perk_list.add_theme_constant_override("separation", 2)
	v.add_child(_perk_list)

	v.add_child(UIKit.make_section("Contracts"))
	_contract_list = VBoxContainer.new()
	_contract_list.add_theme_constant_override("separation", 2)
	v.add_child(_contract_list)

	v.add_child(UIKit.spacer(6))
	var hint := "Hold a card for its special action" if Layout.touch_primary \
		else "Right-click a card for its special action"
	v.add_child(UIKit.make_label(hint, "tiny", Cfg.TEXT_DIM))
	return panel


## Portrait: cards and items share one horizontally scrolling strip.
func _build_inventory_strip() -> Control:
	var panel := UIKit.make_panel(Color(0.07, 0.07, 0.13), Cfg.PANEL_ACCENT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 84
	v.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)

	_card_grid = GridContainer.new()
	_card_grid.columns = 99
	_card_grid.add_theme_constant_override("h_separation", 6)
	row.add_child(_card_grid)

	var sep := VSeparator.new()
	row.add_child(sep)

	_item_grid = GridContainer.new()
	_item_grid.columns = 99
	_item_grid.add_theme_constant_override("h_separation", 6)
	row.add_child(_item_grid)

	_perk_list = VBoxContainer.new()
	_contract_list = VBoxContainer.new()
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 10)
	meta.add_child(_perk_list)
	meta.add_child(_contract_list)
	v.add_child(meta)
	return panel


# ==========================================================================
#  Refresh
# ==========================================================================
func _refresh_stats() -> void:
	if session == null or _money_label == null:
		return
	_money_label.text = "$%d" % session.money
	_score_label.text = str(session.score)
	_round_label.text = str(session.round_count)
	_sets_label.text = "%d/%d" % [session.sets_placed_in_round, session.sets_per_round_target]


func _refresh_tray() -> void:
	if _tray_box == null or session == null:
		return
	for child in _tray_box.get_children():
		child.queue_free()
	_previews.clear()
	_pocket_preview = null

	var slot: float = 76.0 if Layout.portrait else 84.0
	for i in session.hand.size():
		var p := PiecePreview.new()
		p.custom_minimum_size = Vector2(slot, slot)
		p.index = i
		p.set_shape(session.hand[i])
		p.is_selected = i == session.selected_index
		p.selected.connect(_on_piece_selected)
		p.drag_started.connect(_on_piece_drag_started)
		p.double_tapped.connect(_on_piece_double_tapped)
		_tray_box.add_child(p)
		_previews.append(p)

	if session.has_card("Pocket Dimension"):
		var pocket := PiecePreview.new()
		pocket.custom_minimum_size = Vector2(slot, slot)
		pocket.index = -1
		pocket.is_pocket = true
		pocket.set_shape(session.pocketed_piece if session.pocketed_piece != null else {})
		pocket.double_tapped.connect(func(_i): session.unpocket_piece())
		pocket.selected.connect(func(_i): pass)
		_tray_box.add_child(pocket)
		_pocket_preview = pocket


func _refresh_inventory() -> void:
	if _card_grid == null or session == null:
		return
	for child in _card_grid.get_children():
		child.queue_free()
	for child in _item_grid.get_children():
		child.queue_free()
	_card_icons.clear()
	_item_icons.clear()

	var slot: float = 56.0 if Layout.portrait else 66.0
	for i in session.max_cards:
		var icon := CardIcon.new()
		icon.custom_minimum_size = Vector2(slot, slot)
		icon.index = i
		if i < session.cards.size():
			var card: Dictionary = session.cards[i]
			var shown: String = session.effective_name(card)
			icon.set_entry(shown, Cards.card(shown).get("rarity", card.get("rarity", "Common")))
			icon.tooltip_text = "%s\n%s" % [shown, Cards.card(shown).get("description", "")]
			if session.effective_name(card) == "Soul Stamp" \
				and session.get_state(card, "soul_stamp_active", false):
				icon.modulate = Color(1.25, 1.25, 0.8)
			icon.pressed.connect(_on_card_pressed)
			icon.long_pressed.connect(_on_card_long_pressed)
		else:
			icon.set_entry("")
			icon.interactive = false
		_card_grid.add_child(icon)
		_card_icons.append(icon)

	for i in session.max_items:
		var icon := CardIcon.new()
		icon.custom_minimum_size = Vector2(slot, slot)
		icon.index = i
		if i < session.items.size():
			var item: Dictionary = session.items[i]
			icon.set_entry(item["name"], item.get("rarity", "Common"))
			icon.tooltip_text = "%s\n%s" % [item["name"], Cards.item(item["name"]).get("description", "")]
			icon.pressed.connect(_on_item_pressed)
			icon.long_pressed.connect(_on_item_long_pressed)
		else:
			icon.set_entry("")
			icon.interactive = false
		_item_grid.add_child(icon)
		_item_icons.append(icon)

	_refresh_perks()
	_refresh_contracts()


func _refresh_perks() -> void:
	if _perk_list == null:
		return
	for child in _perk_list.get_children():
		child.queue_free()
	var counts := {}
	var order: Array = []
	for p in session.perks:
		var n: String = p["name"]
		counts[n] = int(counts.get(n, 0)) + 1
		if not order.has(n):
			order.append(n)
	for n in order:
		var text: String = n if counts[n] == 1 else "%s (x%d)" % [n, counts[n]]
		var l := UIKit.make_label(text, "tiny", Cfg.LIGHT_GRAY)
		l.tooltip_text = Cards.perk(n).get("description", "")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		_perk_list.add_child(l)


func _refresh_contracts() -> void:
	if _contract_list == null:
		return
	for child in _contract_list.get_children():
		child.queue_free()
	for contract in session.contracts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var name_label := UIKit.make_label(contract["name"], "tiny", Cfg.YELLOW)
		name_label.tooltip_text = "%s\nCurse: %s" % [contract.get("description", ""), contract.get("condition_text", "")]
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(name_label)
		if contract.get("condition_met", false):
			row.add_child(UIKit.make_label("(Met!)", "tiny", Cfg.GREEN))
		elif int(contract.get("condition_deadline", 0)) > 0:
			row.add_child(UIKit.make_label("(%d)" % contract["condition_deadline"], "tiny", Cfg.RED))
		if int(contract.get("expiration", 0)) > 0:
			row.add_child(UIKit.make_label("(%d)" % contract["expiration"], "tiny", Cfg.BLUE.lightened(0.4)))
		_contract_list.add_child(row)


func _on_combo_changed(streak: int, chances: int) -> void:
	if _combo_label == null:
		return
	if streak > 0:
		_combo_label.text = "COMBO x%d" % streak if not Layout.portrait else "x%d" % streak
		_combo_label.add_theme_color_override("font_color", Cfg.COMBO_TEXT_COLOR)
		UIKit.pop(_combo_label, 1.0 + minf(streak * 0.02, 0.35), 0.22)
	else:
		_combo_label.text = "COMBO ---" if not Layout.portrait else "---"
		_combo_label.add_theme_color_override("font_color", Cfg.WHITE)
	if _chances_label:
		_chances_label.text = ("Chances: %d" % maxi(0, chances)) if not Layout.portrait else str(maxi(0, chances))


func _on_fever_changed(level: int, _streak: int) -> void:
	if _combo_flame == null or not is_instance_valid(_combo_flame):
		return
	_combo_flame.emitting = level > 0
	_combo_flame.amount_ratio = clampf(level / 4.0, 0.15, 1.0)
	var mat := _combo_flame.process_material as ParticleProcessMaterial
	if mat and level >= 3:
		# Blue flame at high fever, matching the original's tiering.
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		ramp.colors = PackedColorArray([Color(0.85, 0.98, 1, 0.95), Color(0.0, 0.75, 1.0, 0.75), Color(0.9, 0.97, 1, 0.0)])
		var tex := GradientTexture1D.new()
		tex.gradient = ramp
		mat.color_ramp = tex


func _on_card_triggered(card_name: String) -> void:
	for icon in _card_icons:
		if is_instance_valid(icon) and icon.entry_name == card_name:
			icon.celebrate()


# ==========================================================================
#  Interaction
# ==========================================================================
func _on_piece_selected(index: int) -> void:
	session.selected_index = index
	session.update_potential_clear_highlight()
	for p in _previews:
		if is_instance_valid(p):
			p.is_selected = p.index == index
	Audio.play(Cfg.SFX_UI_CLICK, 0.6)


func _on_piece_double_tapped(index: int) -> void:
	if session.has_card("Pocket Dimension"):
		session.pocket_piece(index)


func _on_piece_drag_started(index: int, global_pos: Vector2) -> void:
	if index < 0 or index >= session.hand.size():
		return
	if not session.pending_effect.is_empty() or session.conjure_active:
		return
	_dragging_index = index
	for p in _previews:
		if is_instance_valid(p):
			p.hidden_for_drag = p.index == index
	board.begin_drag(session.hand[index], index, global_pos)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if _dragging_index < 0:
		return
	if event is InputEventMouseMotion:
		board.update_drag((event as InputEventMouseMotion).global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			board.end_drag(mb.global_position)
			_dragging_index = -1
			set_process_input(false)
			for p in _previews:
				if is_instance_valid(p):
					p.hidden_for_drag = false
			_refresh_tray()


func _on_card_pressed(icon: CardIcon) -> void:
	if icon.index >= session.cards.size():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_card_tap.get(icon.index, -99.0)
	var is_double: bool = now - last < Cfg.DOUBLE_CLICK_TIME
	_last_card_tap[icon.index] = 0.0 if is_double else now
	session.activate_card(icon.index, is_double)
	_refresh_inventory()


func _on_card_long_pressed(icon: CardIcon) -> void:
	if icon.index >= session.cards.size():
		return
	var card: Dictionary = session.cards[icon.index]
	if card["name"] == "The Mimic":
		if not String(card.get("mimic", "")).is_empty() and card["mimic"] == "Merlin's Hat":
			request_dialog.emit("merlin", {"index": icon.index})
		else:
			request_dialog.emit("mimic", {"index": icon.index})
		return
	if session.effective_name(card) == "Merlin's Hat":
		request_dialog.emit("merlin", {"index": icon.index})
		return
	request_dialog.emit("sell_card", {
		"index": icon.index, "name": card["name"],
		"price": session.sell_price_for_card(card),
	})


func _on_item_pressed(icon: CardIcon) -> void:
	if icon.index >= session.items.size():
		return
	session.use_item(icon.index)
	_refresh_inventory()


func _on_item_long_pressed(icon: CardIcon) -> void:
	if icon.index >= session.items.size():
		return
	var item: Dictionary = session.items[icon.index]
	request_dialog.emit("sell_item", {
		"index": icon.index, "name": item["name"],
		"price": session.sell_price_for_item(item),
	})
