class_name SkillTreeScreen
extends ScreenBase
## The Sin Tree: where the Soul Embers a dead run leaves behind are spent on
## permanent upgrades. Seven branches of five tiers each, and a node only says
## what it is once the node before it is owned - the tree reveals itself as it is
## paid for, which is the whole reason it is a tree and not a list.
##
## A desktop lays all seven spines out side by side. Anything narrower - a phone
## in either orientation, a tablet, a tall desktop window - shows one branch at a
## time behind a segmented picker, because seven columns at 140px are neither
## readable nor hittable.

signal spent(node_id: String)

## Below this many logical pixels across, seven columns stop being a layout and
## start being a stack of slivers.
const WIDE_MIN_WIDTH := 1000.0
## Sins per row in the picker. Seven across cannot fit "Gluttony" at a thumb-sized
## font on a phone; two rows of four can, and nothing is hidden behind a scroll.
const PICKER_COLUMNS := 4
const BRANCH_SEPARATION := 8.0

enum State { LOCKED, TOO_DEAR, AFFORDABLE, OWNED }

var _branch_index := 0
var _built_wide := false
var _intro_done := false
var _cards := {}
var _spines := {}
var _field: EmberField
var _ember_label: Label
var _ember_shown := 0.0
var _ember_tween: Tween


func _init() -> void:
	max_content_width = 1240.0
	scrim_alpha = 0.95


func _ready() -> void:
	super._ready()
	# Every visible piece of state is driven from the Profile signals rather than
	# from the buy handler, so embers awarded or spent anywhere else land here too.
	Profile.embers_changed.connect(_on_embers_changed)
	Profile.node_purchased.connect(_on_node_purchased)


## Seven spines side by side need a desktop's width. Everything narrower gets one
## branch, in a column measured for the device instead of for the viewport.
func content_width() -> float:
	if _wide():
		return max_content_width
	if not Layout.touch_primary:
		return 620.0
	return 960.0 if Layout.portrait else 760.0


func _wide() -> bool:
	return not Layout.touch_primary and Layout.logical_size().x >= WIDE_MIN_WIDTH


static func owns(node_id: String) -> bool:
	return Profile.owns(node_id)


## ScreenBase only rebuilds on rotation or on an input-device change. Dragging a
## desktop window past the width where seven spines stop fitting changes this
## screen's entire arrangement, so it has to watch that edge itself.
func _on_layout_changed() -> void:
	var previous := _built_wide
	super._on_layout_changed()
	# _build() refreshes _built_wide, so an unchanged value means super() did not
	# rebuild and the width alone crossed the threshold.
	if previous == _built_wide and previous != _wide():
		rebuild()


func _build() -> void:
	_built_wide = _wide()
	_cards.clear()
	_spines.clear()
	_ensure_field()
	content.add_theme_constant_override("separation", roundi(12.0 * Layout.text_scale()))

	_add_chrome()
	if _built_wide:
		_add_all_branches()
	else:
		_add_single_branch()

	_repaint_all()
	_start_counter()

	if _built_wide:
		content.add_child(UIKit.spacer(10))
		var back := UIKit.make_button("Back", Cfg.PANEL_ACCENT, "small")
		back.pressed.connect(close)
		add_button_row([back])
	content.add_child(UIKit.spacer(Layout.touch_size()))


# ==========================================================================
#  Chrome
# ==========================================================================
func _add_chrome() -> void:
	if _built_wide:
		add_header("The Sin Tree", "Seven sins. Spend what the dead left you.", Cfg.ACCENT_PRIMARY)
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 0)
		_ember_label = UIKit.make_number("0", "large", Cfg.ORANGE)
		_ember_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(_ember_label)
		var caption := UIKit.make_label("SOUL EMBERS", "tiny", Cfg.TEXT_DIM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(caption)
		content.add_child(block)
		return

	# One line of chrome on a phone: the tree needs the vertical space far more
	# than a title block does.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.add_child(UIKit.make_title("SIN TREE", "medium", Cfg.ACCENT_PRIMARY))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_ember_label = UIKit.make_number("0", "small", Cfg.ORANGE)
	_ember_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_ember_label)
	var unit := UIKit.make_label("EMBERS", "tiny", Cfg.TEXT_DIM)
	unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(unit)
	content.add_child(bar)

	# Same reasoning as the settings list: the tree scrolls, and hunting for the
	# way out below five tiers of cards is how a menu becomes a trap.
	var back := UIKit.make_button("Back", Cfg.ACCENT_GOOD, "medium")
	back.custom_minimum_size.y = Layout.touch_size() * 1.15
	back.pressed.connect(close)
	content.add_child(back)


## The drift field hangs on the screen root between the scrim and the content
## frame, so it survives the teardown that a rotation or a branch switch triggers.
func _ensure_field() -> void:
	if _field != null and is_instance_valid(_field):
		return
	_field = EmberField.new()
	add_child(_field)
	move_child(_field, 1)


# ==========================================================================
#  Arrangements
# ==========================================================================
func _add_all_branches() -> void:
	var branches: Array = SinTreeData.BRANCHES
	var width := _column_width(branches.size())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(BRANCH_SEPARATION))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	for i in branches.size():
		var branch: Dictionary = branches[i]
		var column := _make_branch_column(branch, true)
		column.custom_minimum_size.x = width
		row.add_child(column)
	if _field:
		_field.accent = Cfg.ORANGE


func _add_single_branch() -> void:
	var branches: Array = SinTreeData.BRANCHES
	if branches.is_empty():
		return
	_branch_index = clampi(_branch_index, 0, branches.size() - 1)
	content.add_child(_make_picker(branches))

	var branch: Dictionary = branches[_branch_index]
	var accent := _branch_color(branch)
	var blurb := UIKit.make_label(String(branch.get("blurb", "")), "small", Cfg.TEXT_DIM)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(blurb)

	content.add_child(_make_branch_column(branch, false))
	if _field:
		_field.accent = accent


## Every column has to be the same width or the seven spines drift out of step
## with each other. A BoxContainer only shares out the *surplus* evenly, and the
## cards have different minimums, so the width is worked out up front instead.
func _column_width(count: int) -> float:
	if count <= 1:
		return 0.0
	var pad := 14.0 if Layout.portrait else 28.0
	var span: float = minf(content_width(), Layout.logical_size().x - pad * 2.0)
	return floorf((span - BRANCH_SEPARATION * float(count - 1)) / float(count))


## Four sins across is more than "GLUTTONY" fits into on a phone, and the shared
## title bar has to survive a five-figure balance, so both give ground rather
## than truncate. A tab that reads "GLUTT" is not a tab.
func _ember_text(value: int) -> String:
	if value < 10000:
		return str(value)
	return "%.1fk" % (value / 1000.0)


func _make_picker(branches: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = PICKER_COLUMNS if _built_wide or not Layout.portrait else 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in branches.size():
		var branch: Dictionary = branches[i]
		var accent := _branch_color(branch)
		var tab := UIKit.make_button(String(branch.get("name", "?")), accent, "small")
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# A Button's minimum width is its full label, and SIZE_EXPAND_FILL only
		# ever grows past that. Four untrimmable "GLUTTONY"s are wider than a
		# phone, so the grid would push itself off the side of the screen.
		tab.clip_text = true
		tab.custom_minimum_size.y = Layout.touch_size()
		_paint_segment(tab, accent, i == _branch_index)
		tab.pressed.connect(_select_branch.bind(i))
		grid.add_child(tab)
	return grid


## Segmented picker, tinted with each sin's own colour so the tab bar doubles as
## the legend for the tree underneath it.
func _paint_segment(button: Button, accent: Color, chosen: bool) -> void:
	var fill: Color = accent.darkened(0.62) if chosen else Cfg.BUTTON_FILL.darkened(0.35)
	var style := UIKit.button_style(fill, accent, 10, false)
	style.set_border_width_all(2 if chosen else 1)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_color_override("font_color", Cfg.WHITE if chosen else Cfg.TEXT_DIM)


func _select_branch(index: int) -> void:
	if index == _branch_index:
		return
	_branch_index = index
	# Switching sins swaps the whole tree, spine included. Rebuilding is cheaper to
	# reason about than re-pointing the existing cards at another branch's nodes,
	# and it drops the scroll back to tier one, which is where you want to be.
	rebuild()


# ==========================================================================
#  Branch column
# ==========================================================================
func _make_branch_column(branch: Dictionary, narrow: bool) -> Control:
	var branch_id := String(branch.get("id", ""))
	var accent := _branch_color(branch)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if narrow:
		column.add_child(_branch_heading(branch, accent))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var spine := BranchSpine.new()
	spine.accent = accent
	spine.custom_minimum_size.x = maxf(24.0, Layout.touch_size() * 0.5)
	row.add_child(spine)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	row.add_child(stack)

	# Tier order is what the spine walks, so it is enforced here rather than
	# assumed of the table.
	var nodes: Array = Profile.nodes_in_branch(branch_id)
	nodes.sort_custom(func(a, b): return int(a.get("tier", 0)) < int(b.get("tier", 0)))
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		stack.add_child(_make_node_card(node, accent, narrow))

	spine.track(stack, nodes)
	_spines[branch_id] = spine
	return column


func _branch_heading(branch: Dictionary, accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var title := UIKit.make_title(String(branch.get("name", "?")), "small", accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var blurb := UIKit.make_label(String(branch.get("blurb", "")), "tiny", Cfg.TEXT_DIM)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Pinned so all seven headings end level and the spines start on one line.
	blurb.custom_minimum_size.y = UIKit.font_size("tiny") * 3.2
	box.add_child(blurb)
	return box


## Branch tints are stored as "r, g, b" in the data table, the same notation the
## pygame build used. Colours are accepted too, so the table is free to change its
## mind without breaking the screen.
func _branch_color(branch: Dictionary) -> Color:
	var raw: Variant = branch.get("color", "")
	if raw is Color:
		return raw
	var parts := String(raw).split(",", false)
	if parts.size() < 3:
		return Cfg.PANEL_ACCENT
	return Color8(int(parts[0].strip_edges()), int(parts[1].strip_edges()),
		int(parts[2].strip_edges()))


# ==========================================================================
#  Node cards
# ==========================================================================
## Two shapes, one set of parts. The wide row is for the single-branch layout,
## where there is room to put the tap target beside the text; the stacked card is
## for the seven-across desktop layout, where there is not.
func _make_node_card(node: Dictionary, accent: Color, narrow: bool) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := UIKit.make_label("", "small" if narrow else "body", Cfg.WHITE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var cost := UIKit.make_label("%d EMBERS" % int(node.get("cost", 0)), "tiny", Cfg.ORANGE)

	var body_kind := "tiny" if narrow else "small"
	var desc := UIKit.make_label(String(node.get("description", "")), body_kind, Cfg.LIGHT_GRAY)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.y = UIKit.font_size(body_kind) * 2.6

	var action := UIKit.make_button("Unlock", accent, "small")
	action.custom_minimum_size.y = Layout.touch_size()
	# Deliberately no clip_text and no width cap. clip_text drops the label out of
	# the minimum-size calculation entirely, so the button collapses to its
	# padding; a cap narrower than the label renders "UNLOC". The labels here are
	# one short word, and the description beside them autowraps to give the room.
	action.pressed.connect(_on_buy.bind(node))

	if narrow:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(title)
		box.add_child(cost)
		box.add_child(desc)
		box.add_child(action)
		panel.add_child(box)
	else:
		# No width cap: 150px is narrower than "UNLOCK" in the display face, and a
		# capped button with clip_text on renders "UNLOC". The description beside
		# it autowraps, so it is the side that should give.
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_constant_override("separation", 2)
		text.add_child(title)
		text.add_child(cost)
		text.add_child(desc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(text)
		row.add_child(action)
		panel.add_child(row)

	# A PanelContainer fits every child to its whole inner rect, so the purchase
	# flash is just a second child added after the text.
	var flash := ColorRect.new()
	flash.color = accent
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(flash)

	_cards[String(node.get("id", ""))] = {
		"node": node, "accent": accent, "narrow": narrow, "panel": panel,
		"title": title, "cost": cost, "desc": desc, "action": action, "flash": flash,
	}
	return panel


## Four states, resolved in the order that makes them unambiguous. A node with no
## prerequisite is its branch's entrance and is always legible: nothing gates it,
## so it can never be one of the "???" cards.
func _state_of(node: Dictionary) -> State:
	var id := String(node.get("id", ""))
	if owns(id):
		return State.OWNED
	if Profile.can_buy(id):
		return State.AFFORDABLE
	if String(node.get("requires", "")).is_empty() or Profile.revealed(id):
		return State.TOO_DEAR
	return State.LOCKED


func _paint_node(refs: Dictionary) -> void:
	var node: Dictionary = refs["node"]
	var accent: Color = refs["accent"]
	var narrow: bool = refs["narrow"]
	var cost := int(node.get("cost", 0))
	var state := _state_of(node)
	var known := state != State.LOCKED

	var panel: PanelContainer = refs["panel"]
	var title: Label = refs["title"]
	var cost_label: Label = refs["cost"]
	var desc: Label = refs["desc"]
	var action: Button = refs["action"]

	title.text = String(node.get("name", "?")) if known else "???"
	cost_label.visible = known
	desc.visible = known
	action.visible = known

	match state:
		State.OWNED:
			panel.add_theme_stylebox_override("panel",
				_node_style(accent.darkened(0.74), accent, 2, narrow))
			title.add_theme_color_override("font_color", Cfg.WHITE)
			cost_label.add_theme_color_override("font_color", Cfg.ACCENT_GOOD)
			action.disabled = true
			action.text = "Owned"
		State.AFFORDABLE:
			panel.add_theme_stylebox_override("panel",
				_node_style(Color(0.10, 0.10, 0.18), accent, 1, narrow))
			title.add_theme_color_override("font_color", accent.lightened(0.35))
			cost_label.add_theme_color_override("font_color", Cfg.ORANGE)
			action.disabled = false
			# The cost is already spelled out as "N EMBERS" two lines up, so the
			# button repeating it only bought a label too wide for the column.
			action.text = "Unlock"
		State.TOO_DEAR:
			panel.add_theme_stylebox_override("panel",
				_node_style(Color(0.08, 0.08, 0.13), Cfg.GRAY, 1, narrow))
			title.add_theme_color_override("font_color", Cfg.TEXT_DIM)
			cost_label.add_theme_color_override("font_color", Cfg.GRAY)
			action.disabled = true
			action.text = "Short"
		_:
			panel.add_theme_stylebox_override("panel",
				_node_style(Color(0.05, 0.05, 0.09), Cfg.PANEL_BORDER.darkened(0.45), 1, narrow))
			title.add_theme_color_override("font_color", Cfg.GRAY)


## Node panels restyle in place on every purchase, so the stylebox is built here
## instead of going through UIKit.make_panel: the card has to change fill and
## border weight without being torn down and rebuilt underneath a running tween.
func _node_style(fill: Color, border: Color, width: int, narrow: bool) -> StyleBoxFlat:
	var sb := UIKit.panel_style(fill, border, 12, width)
	sb.content_margin_left = 10.0 if narrow else 16.0
	sb.content_margin_right = 10.0 if narrow else 16.0
	sb.content_margin_top = 9.0 if narrow else 12.0
	sb.content_margin_bottom = 9.0 if narrow else 12.0
	sb.shadow_size = 6
	return sb


func _repaint_all() -> void:
	for key in _cards.keys():
		var refs: Dictionary = _cards[key]
		_paint_node(refs)
	for key in _spines.keys():
		var spine: BranchSpine = _spines[key]
		spine.queue_redraw()


# ==========================================================================
#  Buying
# ==========================================================================
func _on_buy(node: Dictionary) -> void:
	if Profile.buy(String(node.get("id", ""))):
		return
	# The card offered a purchase and Profile refused it, so the card is reading
	# from a state that has moved on. Repainting is what corrects it.
	_repaint_all()


func _on_node_purchased(node_id: String) -> void:
	if _closing:
		return
	_repaint_all()
	spent.emit(node_id)
	Audio.play(Cfg.SFX_BUY)

	# The branch the purchase landed in may not be the one on screen.
	var refs: Dictionary = _cards.get(node_id, {})
	if refs.is_empty():
		return
	_flash_card(refs)
	Juice.shake(0.10, 14)
	var node: Dictionary = refs["node"]
	var spine: BranchSpine = _spines.get(String(node.get("branch", "")))
	if spine:
		spine.play_pulse(int(node.get("tier", 1)))


func _flash_card(refs: Dictionary) -> void:
	var flash: ColorRect = refs["flash"]
	var panel: Control = refs["panel"]
	flash.color = (refs["accent"] as Color).lightened(0.55)
	flash.modulate.a = 0.9
	var t := flash.create_tween()
	t.set_ignore_time_scale(true)
	t.tween_property(flash, "modulate:a", 0.0, 0.5) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	UIKit.pop(panel, 1.05, 0.26)


# ==========================================================================
#  Ember counter
# ==========================================================================
## Counts up from nothing the first time the screen is opened, and rolls between
## values after that. A rotation or a branch switch rebuilds the label, which is
## why the intro only fires once.
func _start_counter() -> void:
	if _intro_done:
		_paint_embers(float(Profile.embers))
		return
	_intro_done = true
	_ember_shown = 0.0
	_set_embers(Profile.embers, 0.9)


func _set_embers(target: int, time: float) -> void:
	if _ember_tween and _ember_tween.is_valid():
		_ember_tween.kill()
	_ember_tween = create_tween()
	_ember_tween.set_ignore_time_scale(true)
	_ember_tween.tween_method(_paint_embers, _ember_shown, float(target), time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ember_tween.tween_callback(func():
		if is_instance_valid(_ember_label):
			UIKit.pop(_ember_label, 1.14, 0.2))


func _paint_embers(value: float) -> void:
	_ember_shown = value
	if is_instance_valid(_ember_label):
		_ember_label.text = _ember_text(roundi(value))


func _on_embers_changed(total: int) -> void:
	if _closing:
		return
	_set_embers(total, 0.45)
	_repaint_all()


# ==========================================================================
#  Branch spine
# ==========================================================================
## The connective tissue of one branch: a vertical rail carrying a dot per tier.
## The stretch between two owned nodes burns in the branch colour; everything past
## the last purchase stays a cold hairline. A purchase sends a single pulse down
## the rail, and that pulse is the only thing in here that runs _process.
class BranchSpine extends Control:
	const PULSE_TIME := 0.62
	const DOT_RADIUS := 5.0

	var accent := Cfg.PANEL_ACCENT

	var _nodes: Array = []
	var _tiers: Array[Control] = []
	var _box: Container
	var _pulse_to := -1
	var _pulse_t := 0.0


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)


	## `box` holds one card per tier in tier order. The rail reads its dot heights
	## back off those cards rather than spacing them evenly, so a card that grows
	## when it is revealed drags its own tier marker along with it.
	func track(box: Container, nodes: Array) -> void:
		_box = box
		_nodes = nodes
		_tiers.clear()
		for child in box.get_children():
			_tiers.append(child as Control)
		box.sort_children.connect(queue_redraw)
		resized.connect(queue_redraw)


	func play_pulse(tier: int) -> void:
		_pulse_to = maxi(0, tier - 1)
		_pulse_t = 0.0
		set_process(true)


	func _process(delta: float) -> void:
		_pulse_t += delta
		if _pulse_t >= PULSE_TIME:
			_pulse_to = -1
			set_process(false)
		queue_redraw()


	## Dot heights come from the sibling card box, so everything stays in this
	## control's own coordinates without touching global transforms - which the
	## open/close animation is busy scaling.
	func _dots() -> PackedVector2Array:
		var out := PackedVector2Array()
		if _box == null:
			return out
		var x := size.x * 0.5
		var base := _box.position.y - position.y
		for card in _tiers:
			if not is_instance_valid(card):
				continue
			out.append(Vector2(x, base + card.position.y + card.size.y * 0.5))
		return out


	func _owned(index: int) -> bool:
		return SkillTreeScreen.owns(_id_at(index))


	## Mirrors the screen's reveal rule: a tier with no prerequisite is never dark.
	func _revealed(index: int) -> bool:
		if index < 0 or index >= _nodes.size():
			return false
		var node: Dictionary = _nodes[index]
		return String(node.get("requires", "")).is_empty() or Profile.revealed(_id_at(index))


	func _id_at(index: int) -> String:
		if index < 0 or index >= _nodes.size():
			return ""
		return String((_nodes[index] as Dictionary).get("id", ""))


	func _draw() -> void:
		var dots := _dots()
		if dots.is_empty():
			return
		if dots.size() > 1:
			draw_line(dots[0], dots[dots.size() - 1],
				Color(accent.r, accent.g, accent.b, 0.20), 3.0, true)
		for i in range(1, dots.size()):
			if _owned(i - 1) and _owned(i):
				draw_line(dots[i - 1], dots[i],
					Color(accent.r, accent.g, accent.b, 0.85), 5.0, true)
				draw_line(dots[i - 1], dots[i], Color(1, 1, 1, 0.22), 1.5, true)
		for i in dots.size():
			_draw_dot(dots[i], i)
		_draw_pulse(dots)


	func _draw_dot(at: Vector2, index: int) -> void:
		if _owned(index):
			draw_circle(at, DOT_RADIUS + 3.0, Color(accent.r, accent.g, accent.b, 0.30))
			draw_circle(at, DOT_RADIUS, accent)
			draw_circle(at, DOT_RADIUS * 0.42, Color(1, 1, 1, 0.9))
		elif _revealed(index):
			draw_arc(at, DOT_RADIUS, 0.0, TAU, 18,
				Color(accent.r, accent.g, accent.b, 0.9), 2.0, true)
		else:
			draw_circle(at, DOT_RADIUS * 0.5, Color(accent.r, accent.g, accent.b, 0.26))


	## Four circles for the whole effect, so a phone can run it over the drift
	## field without anyone having to think about the frame budget.
	func _draw_pulse(dots: PackedVector2Array) -> void:
		if _pulse_to < 0:
			return
		var target := clampi(_pulse_to, 0, dots.size() - 1)
		var p: float = clampf(_pulse_t / PULSE_TIME, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - p, 3.0)
		var at: Vector2 = dots[0].lerp(dots[target], eased)
		var fade: float = 1.0 - p
		draw_circle(at, DOT_RADIUS * (3.4 + eased * 2.2),
			Color(accent.r, accent.g, accent.b, 0.35 * fade))
		draw_circle(at, DOT_RADIUS * (1.6 + eased * 0.8), Color(1, 1, 1, 0.75 * fade))


# ==========================================================================
#  Drift field
# ==========================================================================
## Embers rising slowly behind the tree, tinted by whichever sin is on screen.
## Hand-drawn circles rather than a particle system: a couple of dozen of these
## cost a phone less than a GPUParticles2D plus its process material, and the
## count halves again on a handset.
class EmberField extends Control:
	const RISE_MIN := 8.0
	const RISE_MAX := 26.0
	const TINT_RATE := 2.2

	var accent := Cfg.ORANGE

	var _motes: Array = []
	var _tint := Cfg.ORANGE
	var _time := 0.0


	func _ready() -> void:
		UIKit.fill_viewport(self)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		Layout.layout_changed.connect(func(): UIKit.fill_viewport(self))
		set_process(true)


	func _seed() -> void:
		var count := 26 if Layout.is_phone() else 52
		for i in count:
			_motes.append({
				"pos": Vector2(randf() * size.x, randf() * size.y),
				"rise": randf_range(RISE_MIN, RISE_MAX),
				"sway": randf_range(6.0, 20.0),
				"phase": randf_range(0.0, TAU),
				"radius": randf_range(1.2, 3.4),
				"alpha": randf_range(0.18, 0.6),
			})


	func _process(delta: float) -> void:
		if size.x <= 1.0 or size.y <= 1.0:
			UIKit.fill_viewport(self)
			return
		if _motes.is_empty():
			_seed()
		_time += delta
		_tint = _tint.lerp(accent, clampf(delta * TINT_RATE, 0.0, 1.0))
		for m in _motes:
			m["pos"].y -= m["rise"] * delta
			if m["pos"].y < -6.0:
				m["pos"].y = size.y + randf_range(4.0, 60.0)
				m["pos"].x = randf() * size.x
			# Wrapping rather than reseeding keeps the field alive across a window
			# resize, which fires far too often to rebuild anything on.
			m["pos"].x = fposmod(m["pos"].x, maxf(size.x, 1.0))
		queue_redraw()


	func _draw() -> void:
		for m in _motes:
			var at: Vector2 = m["pos"]
			at.x += sin(_time * 0.6 + float(m["phase"])) * float(m["sway"])
			var a: float = m["alpha"]
			var r: float = m["radius"]
			draw_circle(at, r * 2.6, Color(_tint.r, _tint.g, _tint.b, a * 0.20))
			draw_circle(at, r, Color(_tint.r, _tint.g, _tint.b, a))
