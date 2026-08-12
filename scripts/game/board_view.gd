class_name BoardView
extends Control
## The playfield. Draws the grid and every overlay, and owns pointer input for
## both control schemes:
##
##   * Drag  - press a tray piece, drag it over the board, release to drop.
##             The piece floats a hand's width above the finger and tracks
##             finger *motion* rather than absolute position, amplified by
##             DRAG_GAIN, so a short thumb swipe from the tray in the bottom
##             third of the screen reaches the top row.
##   * Tap   - tap a tray piece to select, then tap a cell to drop it there.
##   * Mouse - the ghost simply follows the cursor; click to drop.
##
## Targeted item effects (bombs / eraser) reuse the same pointer path.

signal cell_hovered(cell: Vector2i)
signal drag_state_changed(dragging: bool)
signal geometry_changed

const GRID_LINE := Color(1, 1, 1, 0.07)
const BOARD_BG := Color(0.03, 0.03, 0.07, 0.93)

var session: GameSession

var cell_size := 40.0
var board_origin := Vector2.ZERO

## Default (Block Blast style) placement multiplies finger motion by this, so
## the piece outruns the thumb and a short swipe reaches the far side of the
## board. Direct placement uses 1.0, putting the piece under the finger.
const DRAG_GAIN := 2.0
const PLACEMENT_DEFAULT := 0
const PLACEMENT_DIRECT := 1

var dragging := false
var drag_index := -1
var _drag_shape: Dictionary = {}
var _drag_finger_start := Vector2.ZERO
var _drag_piece_anchor := Vector2.ZERO
var _drag_lift := 0.0
var _pointer_pos := Vector2.ZERO
var _pointer_inside := false
var _ghost_valid := false
var _snap_used := false

var _cell_fx := {}        # Vector2i -> {t, dur, kind}
var _clear_flash := 0.0
var _laser_pulse := 0.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	resized.connect(_recompute_geometry)
	set_process(true)


func bind(new_session: GameSession) -> void:
	session = new_session
	session.board_changed.connect(_on_board_changed)
	session.grid_resized.connect(_recompute_geometry)
	session.cells_cleared.connect(_on_cells_cleared)
	session.piece_placed.connect(_on_piece_placed)
	session.boss_state_changed.connect(queue_redraw)
	session.pending_effect_changed.connect(queue_redraw)
	_recompute_geometry()


# ==========================================================================
#  Geometry
# ==========================================================================
## A band under the grid is reserved for the message feed so toasts never sit
## on top of the playfield.
const MESSAGE_BAND := 76.0


func _recompute_geometry() -> void:
	if session == null:
		return
	var pad := 18.0
	# On a short screen the reserved message strip costs more board than it is
	# worth; toasts simply overlay the lower board there instead.
	var band := 0.0 if size.y < 470.0 else MESSAGE_BAND
	var usable := size - Vector2(pad * 2.0, pad * 2.0 + band)
	cell_size = Layout.cell_size_for(usable, session.grid_rows, session.grid_cols)
	var grid_px := Vector2(session.grid_cols, session.grid_rows) * cell_size
	# On a portrait phone the grid is width-limited, so the holder ends up far
	# taller than the board and centring leaves a dead strip between the last
	# row and the tray. Sitting the grid lower shortens every drag, which is the
	# whole point of the tray living in the bottom third of the screen.
	var bias := 0.62 if (Layout.touch_primary and Layout.portrait) else 0.5
	board_origin = Vector2(
		(size.x - grid_px.x) * 0.5,
		maxf(0.0, size.y - band - grid_px.y) * bias).floor()
	geometry_changed.emit()
	queue_redraw()


func grid_rect() -> Rect2:
	if session == null:
		return Rect2()
	return Rect2(board_origin, Vector2(session.grid_cols, session.grid_rows) * cell_size)


func cell_rect(r: int, c: int) -> Rect2:
	return Rect2(board_origin + Vector2(c, r) * cell_size, Vector2(cell_size, cell_size))


func cell_center(r: int, c: int) -> Vector2:
	return board_origin + Vector2(c + 0.5, r + 0.5) * cell_size


func cell_at_point(p: Vector2) -> Vector2i:
	var local := (p - board_origin) / cell_size
	return Vector2i(floori(local.y), floori(local.x))


func in_bounds(cell: Vector2i) -> bool:
	return session != null and cell.x >= 0 and cell.x < session.grid_rows \
		and cell.y >= 0 and cell.y < session.grid_cols


# ==========================================================================
#  Input
# ==========================================================================
func begin_drag(shape: Dictionary, hand_index: int, pointer_global: Vector2) -> void:
	if session == null or session.is_game_over:
		return
	dragging = true
	drag_index = hand_index
	_drag_shape = shape
	session.selected_index = hand_index
	# Anchor the relative frame: the piece starts directly above the finger, and
	# every later sample moves it by the finger delta times DRAG_GAIN.
	_pointer_pos = get_global_transform().affine_inverse() * pointer_global
	_drag_finger_start = _pointer_pos
	# drag_lift() is the gap under the piece's *bottom edge*, so the shape's own
	# half-height is added on top. Without that a 4-tall bar would still sit
	# under the thumb no matter how large the lift is.
	var half_height := Cfg.shape_size(shape).y * cell_size * 0.5
	_drag_lift = Layout.drag_lift(cell_size)
	_drag_piece_anchor = _pointer_pos - Vector2(0, _drag_lift + half_height)
	_update_pointer(pointer_global)
	drag_state_changed.emit(true)
	queue_redraw()


func end_drag(pointer_global: Vector2, commit := true) -> bool:
	if not dragging:
		return false
	_update_pointer(pointer_global)
	var placed := false
	if commit and _pointer_inside and not _drag_shape.is_empty():
		var origin := _ghost_origin(cell_at_point(piece_centre()), _drag_shape)
		origin = _snapped_origin(origin, _drag_shape)
		if session.is_valid_placement(_drag_shape, origin.x, origin.y, session.soul_stamp_armed()):
			session.ghost_pos = origin
			placed = session.place_piece(_drag_shape, origin.x, origin.y)
	dragging = false
	drag_index = -1
	_drag_shape = {}
	drag_state_changed.emit(false)
	queue_redraw()
	return placed


func cancel_drag() -> void:
	if not dragging:
		return
	dragging = false
	drag_index = -1
	_drag_shape = {}
	drag_state_changed.emit(false)
	queue_redraw()


func update_drag(pointer_global: Vector2) -> void:
	if not dragging:
		return
	_update_pointer(pointer_global)
	queue_redraw()


## Amplification only makes sense for a thumb: a mouse cursor is already precise
## and absolute, so pointer input stays rigidly 1:1 whatever the setting says.
func _drag_gain() -> float:
	if not Layout.touch_primary:
		return 1.0
	return 1.0 if SaveGame.placement_mode == PLACEMENT_DIRECT else DRAG_GAIN


## Where the piece itself sits, in board-local space. While dragging this is
## driven by accumulated finger motion, not by the finger position, so the two
## intentionally diverge as you swipe.
func piece_centre() -> Vector2:
	if not dragging:
		return _pointer_pos
	var moved := (_pointer_pos - _drag_finger_start) * _drag_gain()
	var centre := _drag_piece_anchor + moved
	# Keep it reachable: never let the piece outrun the board entirely.
	var bounds := Rect2(Vector2.ZERO, size).grow(cell_size)
	return centre.clamp(bounds.position, bounds.end)


func _update_pointer(pointer_global: Vector2) -> void:
	_pointer_pos = get_global_transform().affine_inverse() * pointer_global
	var probe := piece_centre() if dragging else _pointer_pos
	var cell := cell_at_point(probe)
	_pointer_inside = in_bounds(cell)
	if _pointer_inside and session != null:
		var shape: Dictionary = _drag_shape if dragging else session.selected_shape()
		if not shape.is_empty():
			var origin := _snapped_origin(_ghost_origin(cell, shape), shape)
			session.ghost_pos = origin
			_ghost_valid = session.is_valid_placement(shape, origin.x, origin.y, session.soul_stamp_armed())
			session.update_potential_clear_highlight()
		cell_hovered.emit(cell)


## Centre the shape on the pointer instead of anchoring its top-left corner --
## far easier to aim with a thumb.
func _ghost_origin(pointer_cell: Vector2i, shape: Dictionary) -> Vector2i:
	var s := Cfg.shape_size(shape)
	@warning_ignore("integer_division")
	return pointer_cell - Vector2i(s.y / 2, s.x / 2)


## Snap to the nearest position the piece actually fits, searching outward in
## rings. A generous radius is what makes the Block Blast style work: the piece
## floats loosely under the thumb and the board decides where it belongs, so you
## never have to place pixel-accurately with a finger covering the target.
const SNAP_RADIUS := 2


func _snapped_origin(origin: Vector2i, shape: Dictionary) -> Vector2i:
	_snap_used = false
	if session == null:
		return origin
	var stamp := session.soul_stamp_armed()
	if session.is_valid_placement(shape, origin.x, origin.y, stamp):
		return origin
	var best := origin
	var best_dist := INF
	for dr in range(-SNAP_RADIUS, SNAP_RADIUS + 1):
		for dc in range(-SNAP_RADIUS, SNAP_RADIUS + 1):
			if dr == 0 and dc == 0:
				continue
			var cand := origin + Vector2i(dr, dc)
			if not session.is_valid_placement(shape, cand.x, cand.y, stamp):
				continue
			# Prefer the smallest move, and break ties toward vertical nudges so
			# the piece appears to fall into place rather than slide sideways.
			var d := Vector2(dc, dr).length() + (0.05 if dr != 0 else 0.0)
			if d < best_dist:
				best_dist = d
				best = cand
	_snap_used = best != origin
	return best


func _gui_input(event: InputEvent) -> void:
	if session == null or session.is_game_over:
		return

	if event is InputEventMouseMotion:
		_update_pointer((event as InputEventMouseMotion).global_position)
		queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not session.pending_effect.is_empty():
				session.cancel_pending()
				accept_event()
			return
		if mb.pressed:
			_update_pointer(mb.global_position)
			accept_event()
			return
		# Release inside the board: place, or resolve a targeted item effect.
		_update_pointer(mb.global_position)
		if not _pointer_inside:
			return
		var cell := cell_at_point(_pointer_pos)
		if not session.pending_effect.is_empty():
			_resolve_pending(cell)
		elif dragging:
			end_drag(mb.global_position)
		else:
			var shape := session.selected_shape()
			if not shape.is_empty():
				var origin := _snapped_origin(_ghost_origin(cell, shape), shape)
				if session.is_valid_placement(shape, origin.x, origin.y, session.soul_stamp_armed()):
					session.place_piece(shape, origin.x, origin.y)
				else:
					_reject_feedback()
		accept_event()


func _resolve_pending(cell: Vector2i) -> void:
	var effect: Dictionary = session.pending_effect
	session.apply_clear_effect(effect.get("type", ""), cell.x, cell.y, int(effect.get("size", 3)))


func _reject_feedback() -> void:
	Audio.play(Cfg.SFX_UI_CLICK, 0.4, 0.7)
	Juice.shake(0.06)


# ==========================================================================
#  Reactions
# ==========================================================================
func _on_board_changed() -> void:
	queue_redraw()


func _on_piece_placed(cells: Array, _color: Color) -> void:
	for cell in cells:
		_cell_fx[cell] = {"t": 0.0, "dur": 0.22, "kind": "place"}
	queue_redraw()


func _on_cells_cleared(cells: Array, kind: String) -> void:
	_clear_flash = 1.0
	if kind == "laser":
		_laser_pulse = 1.0
	for cell in cells:
		_cell_fx[cell] = {"t": 0.0, "dur": 0.42, "kind": "clear"}
		_spawn_burst(cell_center(cell.x, cell.y), _burst_color(kind), kind)
	if cells.size() >= 4:
		_spawn_shockwave(_average_center(cells), _burst_color(kind))
	queue_redraw()


func _average_center(cells: Array) -> Vector2:
	var sum := Vector2.ZERO
	for cell in cells:
		sum += cell_center(cell.x, cell.y)
	return sum / maxf(cells.size(), 1.0)


func _burst_color(kind: String) -> Color:
	match kind:
		"laser": return Cfg.RED
		"bomb": return Cfg.ORANGE
		"vanish": return Cfg.CYAN
	# Line clears take the combo fever colour so streaks visibly heat up.
	return [Cfg.WHITE, Cfg.ACCENT_PRIMARY, Cfg.ORANGE, Cfg.RED, Cfg.MAGENTA][Juice.fever_level]


# ==========================================================================
#  Particles
# ==========================================================================
func _spawn_burst(pos: Vector2, color: Color, kind: String) -> void:
	var p := GPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 1.0
	p.amount = 14 if kind == "line" else 22
	p.lifetime = 0.75
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = cell_size * 0.35
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 620, 0)
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 300.0 if kind != "line" else 220.0
	mat.angular_velocity_min = -520.0
	mat.angular_velocity_max = 520.0
	mat.scale_min = 0.35
	mat.scale_max = 1.0
	mat.damping_min = 60.0
	mat.damping_max = 180.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(color.r, color.g, color.b, 0.95),
		Color(color.r * 0.5, color.g * 0.25, color.b * 0.25, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat

	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	p.texture = ImageTexture.create_from_image(img)

	add_child(p)
	var timer := get_tree().create_timer(p.lifetime + 0.3)
	timer.timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


func _spawn_shockwave(pos: Vector2, color: Color) -> void:
	var ring := Shockwave.new()
	ring.position = pos
	ring.ring_color = color
	ring.max_radius = cell_size * 4.5
	add_child(ring)


# ==========================================================================
#  Drawing
# ==========================================================================
func _process(delta: float) -> void:
	if session == null:
		return
	_time += delta
	_clear_flash = maxf(0.0, _clear_flash - delta * 2.4)
	_laser_pulse = maxf(0.0, _laser_pulse - delta * 0.6)
	var done: Array = []
	for key in _cell_fx:
		_cell_fx[key]["t"] += delta
		if _cell_fx[key]["t"] >= _cell_fx[key]["dur"]:
			done.append(key)
	for key in done:
		_cell_fx.erase(key)
	queue_redraw()


func _draw() -> void:
	if session == null:
		return
	var rect := grid_rect()

	# Board well.
	draw_rect(rect.grow(12.0), Color(0, 0, 0, 0.72), true)
	draw_rect(rect.grow(10.0), Color(Cfg.PANEL_ACCENT.r, Cfg.PANEL_ACCENT.g, Cfg.PANEL_ACCENT.b, 0.35), false, 2.0)
	draw_rect(rect, BOARD_BG, true)

	# Grid lines.
	for c in range(session.grid_cols + 1):
		var x := board_origin.x + c * cell_size
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), GRID_LINE, 1.0)
	for r in range(session.grid_rows + 1):
		var y := board_origin.y + r * cell_size
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID_LINE, 1.0)

	_draw_potential_clears()
	_draw_cells()
	_draw_boss()
	_draw_ghost()
	_draw_pending_effect()

	if _clear_flash > 0.001:
		draw_rect(rect, Color(1, 1, 1, _clear_flash * 0.14), true)


func _draw_cells() -> void:
	for r in session.grid_rows:
		for c in session.grid_cols:
			var cell: Variant = session.board[r][c]
			if not (cell is Dictionary):
				continue
			var key := Vector2i(r, c)
			var base := cell_rect(r, c)
			var fx: Dictionary = _cell_fx.get(key, {})
			var t := 0.0
			var kind := ""
			if not fx.is_empty():
				t = clampf(fx["t"] / fx["dur"], 0.0, 1.0)
				kind = fx["kind"]

			var scale := 1.0
			if kind == "place":
				scale = 1.0 + 0.35 * (1.0 - ease(t, 0.35))
			elif kind == "clear":
				scale = 1.0 + 0.25 * t
			var inset: float = maxf(1.0, cell_size * 0.06)
			var draw_r := base.grow(-inset)
			if not is_equal_approx(scale, 1.0):
				var grow: float = draw_r.size.x * (scale - 1.0) * 0.5
				draw_r = draw_r.grow(grow)

			var col: Color = session.cell_color(cell)
			var alpha := 1.0
			if kind == "clear":
				alpha = 1.0 - t
				col = col.lerp(Cfg.WHITE, t * 0.85)
			col.a = alpha

			var radius: float = maxf(2.0, cell_size * 0.16)
			_draw_block(draw_r, col, radius, session.is_obstacle(cell), cell.get("a", false), alpha)


## One block: fill, top highlight, bottom shade, border. Angel's Kiss blocks
## get a shimmering gold rim, obstacles a hatched slate look.
func _draw_block(r: Rect2, col: Color, radius: float, obstacle: bool, angel: bool, alpha: float) -> void:
	draw_rect(r, col, true)

	var hi := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34))
	draw_rect(hi, Color(1, 1, 1, 0.16 * alpha), true)
	var lo := Rect2(Vector2(r.position.x, r.end.y - r.size.y * 0.24), Vector2(r.size.x, r.size.y * 0.24))
	draw_rect(lo, Color(0, 0, 0, 0.24 * alpha), true)

	if obstacle:
		var step: float = maxf(4.0, r.size.x / 4.0)
		var x := r.position.x
		while x < r.end.x:
			draw_line(Vector2(x, r.end.y), Vector2(minf(x + r.size.y, r.end.x), r.position.y),
				Color(0.15, 0.15, 0.18, 0.75 * alpha), 1.5)
			x += step
		draw_rect(r, Color(0.85, 0.85, 0.9, 0.7 * alpha), false, 2.0)
		return

	if angel:
		var shimmer := 0.55 + 0.45 * sin(_time * 5.0)
		draw_rect(r.grow(1.5), Color(1.0, 0.92, 0.45, shimmer * alpha), false, 2.5)
		draw_rect(r, Color(1, 1, 1, 0.25 * shimmer * alpha), false, 1.0)
	else:
		draw_rect(r, Color(0, 0, 0, 0.35 * alpha), false, 1.0)
		draw_rect(r, Color(1, 1, 1, 0.10 * alpha), false, 1.0)
	_unused(radius)


func _unused(_v: Variant) -> void:
	pass


func _draw_potential_clears() -> void:
	if session.potential_clear_cells.is_empty():
		return
	if not session.pending_effect.is_empty() or session.conjure_active:
		return
	var pulse := 0.32 + 0.14 * sin(_time * 6.0)
	for cell in session.potential_clear_cells:
		var r := cell_rect(cell.x, cell.y)
		draw_rect(r, Color(0.25, 1.0, 0.35, pulse * 0.5), true)
		draw_rect(r, Color(0.4, 1.0, 0.5, pulse + 0.3), false, 2.0)


func _draw_ghost() -> void:
	if session.is_game_over:
		return
	if not session.pending_effect.is_empty() or session.conjure_active:
		return
	var shape: Dictionary = _drag_shape if dragging else session.selected_shape()
	if shape.is_empty():
		return
	if not dragging and not _pointer_inside and Layout.touch_primary:
		return

	var origin: Vector2i = session.ghost_pos
	var stamp := session.soul_stamp_armed()
	var valid := session.is_valid_placement(shape, origin.x, origin.y, stamp)
	var piece_color: Color = shape.get("color", Cfg.WHITE)
	var tint := piece_color if valid else Cfg.RED
	if stamp and valid:
		tint = Cfg.YELLOW

	# --- Landing preview -------------------------------------------------
	# This has to be unmistakable: while dragging, the finger is nowhere near
	# the target, so the board itself must answer "where does this go?".
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var inset: float = maxf(1.0, cell_size * 0.06)
	# True only when a separate piece is being drawn above the finger. With a
	# mouse there is no lift, so the footprint below *is* the piece and has to
	# keep its colour.
	var floating := dragging and _drag_lift > 0.0
	for off in shape.get("coords", []):
		var rr: int = origin.x + off.x
		var cc: int = origin.y + off.y
		if not in_bounds(Vector2i(rr, cc)):
			continue
		var cell := cell_rect(rr, cc)
		var r := cell.grow(-inset)
		if valid and floating:
			# A dark silhouette, never a colour copy. The bright piece floating
			# above the finger is the object being moved; this is only the hole
			# it will drop into, and two saturated copies of the same shape a
			# few pixels apart read as a rendering bug.
			draw_rect(cell, Color(0, 0, 0, 0.55), true)
			draw_rect(r, Color(tint.r * 0.3, tint.g * 0.3, tint.b * 0.3, 0.8), true)
			draw_rect(r, Color(1, 1, 1, 0.4 + 0.35 * pulse), false, maxf(2.0, cell_size * 0.07))
		elif valid:
			# Nothing floats above a mouse cursor, and tap-to-place has no
			# floating piece either, so here the footprint stands in for the
			# piece and is drawn in full colour.
			var fill: float = 0.95 if (dragging and _pointer_inside) else 0.60
			draw_rect(cell, Color(0, 0, 0, 0.45), true)
			draw_rect(r, Color(tint.r, tint.g, tint.b, fill), true)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34)),
				Color(1, 1, 1, 0.20), true)
			draw_rect(Rect2(Vector2(r.position.x, r.end.y - r.size.y * 0.24),
				Vector2(r.size.x, r.size.y * 0.24)), Color(0, 0, 0, 0.22), true)
			draw_rect(r, Color(1, 1, 1, 0.55 + 0.35 * pulse), false, maxf(2.0, cell_size * 0.07))
		else:
			draw_rect(r, Color(tint.r, tint.g, tint.b, 0.30), true)
			draw_rect(r, Color(tint.r, tint.g, tint.b, 0.85), false, maxf(2.0, cell_size * 0.06))

	# Outline the whole footprint so the piece reads as one object, not N cells.
	if valid:
		_draw_footprint_outline(shape, origin, Color(1, 1, 1, 0.30 + 0.30 * pulse))

	# --- The piece itself, floating free above the finger -----------------
	# Drawn for the whole drag, including over a valid drop. The piece is the
	# object you are moving and the footprint above is its shadow; hiding the
	# piece whenever it happened to be over a legal cell is what made the lift
	# look like it was not being applied at all.
	if floating:
		var s := Cfg.shape_size(shape)
		var half := Vector2(s.x, s.y) * cell_size * 0.5
		var anchor := piece_centre() - half
		for off in shape.get("coords", []):
			var pos := anchor + Vector2(off.y, off.x) * cell_size
			var r := Rect2(pos, Vector2(cell_size, cell_size)).grow(-inset)
			# Shadow first, so the piece reads as hovering over the board.
			draw_rect(Rect2(r.position + Vector2(0, cell_size * 0.12), r.size),
				Color(0, 0, 0, 0.35), true)
			draw_rect(r, Color(piece_color.r, piece_color.g, piece_color.b, 0.97), true)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34)),
				Color(1, 1, 1, 0.22), true)
			draw_rect(Rect2(Vector2(r.position.x, r.end.y - r.size.y * 0.24),
				Vector2(r.size.x, r.size.y * 0.24)), Color(0, 0, 0, 0.22), true)
			draw_rect(r, Color(1, 1, 1, 0.75), false, maxf(1.5, cell_size * 0.05))


## Traces the outer border of a shape's footprint by drawing only the edges that
## have no neighbouring cell, which reads far cleaner than boxing every cell.
func _draw_footprint_outline(shape: Dictionary, origin: Vector2i, color: Color) -> void:
	var filled := {}
	for off in shape.get("coords", []):
		filled[Vector2i(origin.x + off.x, origin.y + off.y)] = true
	var width: float = maxf(2.0, cell_size * 0.09)
	for cell: Vector2i in filled:
		if not in_bounds(cell):
			continue
		var r := cell_rect(cell.x, cell.y)
		if not filled.has(cell + Vector2i(-1, 0)):
			draw_line(r.position, Vector2(r.end.x, r.position.y), color, width)
		if not filled.has(cell + Vector2i(1, 0)):
			draw_line(Vector2(r.position.x, r.end.y), r.end, color, width)
		if not filled.has(cell + Vector2i(0, -1)):
			draw_line(r.position, Vector2(r.position.x, r.end.y), color, width)
		if not filled.has(cell + Vector2i(0, 1)):
			draw_line(Vector2(r.end.x, r.position.y), r.end, color, width)


func _draw_pending_effect() -> void:
	if session.pending_effect.is_empty() or not _pointer_inside:
		return
	var cell := cell_at_point(_pointer_pos)
	if not in_bounds(cell):
		return
	var kind: String = session.pending_effect.get("type", "")
	var tint := Cfg.YELLOW
	var pulse := 0.4 + 0.2 * sin(_time * 8.0)
	match kind:
		"row_clear":
			var r := Rect2(board_origin + Vector2(0, cell.x * cell_size),
				Vector2(session.grid_cols * cell_size, cell_size))
			draw_rect(r, Color(tint.r, tint.g, tint.b, pulse * 0.4), true)
			draw_rect(r, tint, false, 3.0)
		"column_clear":
			var r := Rect2(board_origin + Vector2(cell.y * cell_size, 0),
				Vector2(cell_size, session.grid_rows * cell_size))
			draw_rect(r, Color(tint.r, tint.g, tint.b, pulse * 0.4), true)
			draw_rect(r, tint, false, 3.0)
		"area_bomb":
			var s: int = int(session.pending_effect.get("size", 3))
			@warning_ignore("integer_division")
			var half: int = s / 2
			for dr in s:
				for dc in s:
					var target := Vector2i(cell.x - half + dr, cell.y - half + dc)
					if in_bounds(target):
						draw_rect(cell_rect(target.x, target.y), Color(tint.r, tint.g, tint.b, pulse * 0.45), true)
			draw_rect(Rect2(board_origin + Vector2((cell.y - half) * cell_size, (cell.x - half) * cell_size),
				Vector2(s, s) * cell_size), tint, false, 3.0)
		"single_block_remove":
			var r := cell_rect(cell.x, cell.y)
			draw_rect(r, Color(tint.r, tint.g, tint.b, pulse * 0.5), true)
			draw_rect(r, tint, false, 3.0)


func _draw_boss() -> void:
	if not session.boss_active:
		return
	var rect := grid_rect()

	if session.boss_warning_active and session.boss_next_line >= 0:
		var warn := 0.35 + 0.35 * absf(sin(_time * 4.0))
		var col := Color(Cfg.ORANGE.r, Cfg.ORANGE.g, Cfg.ORANGE.b, warn)
		var band: Rect2
		if session.boss_next_is_row:
			band = Rect2(rect.position + Vector2(0, session.boss_next_line * cell_size),
				Vector2(rect.size.x, cell_size))
		else:
			band = Rect2(rect.position + Vector2(session.boss_next_line * cell_size, 0),
				Vector2(cell_size, rect.size.y))
		draw_rect(band, Color(col.r, col.g, col.b, warn * 0.25), true)
		draw_rect(band, col, false, 2.0)
		_draw_warning_arrow(band)

	if _laser_pulse > 0.001:
		var beam := Color(1.0, 0.25, 0.25, _laser_pulse * 0.75)
		var band: Rect2
		if session.boss_laser_is_row:
			band = Rect2(rect.position + Vector2(0, session.boss_laser_line * cell_size),
				Vector2(rect.size.x, cell_size))
		else:
			band = Rect2(rect.position + Vector2(session.boss_laser_line * cell_size, 0),
				Vector2(cell_size, rect.size.y))
		draw_rect(band.grow(_laser_pulse * 6.0), beam, true)
		draw_rect(band, Color(1, 1, 1, _laser_pulse), false, 3.0)


func _draw_warning_arrow(band: Rect2) -> void:
	var s: float = cell_size * 0.4
	var pts := PackedVector2Array()
	if session.boss_next_is_row:
		var y := band.position.y + band.size.y * 0.5
		var x := board_origin.x - 8.0
		pts = PackedVector2Array([Vector2(x, y), Vector2(x - s, y - s * 0.6), Vector2(x - s, y + s * 0.6)])
	else:
		var x := band.position.x + band.size.x * 0.5
		var y := board_origin.y - 8.0
		pts = PackedVector2Array([Vector2(x, y), Vector2(x - s * 0.6, y - s), Vector2(x + s * 0.6, y - s)])
	draw_colored_polygon(pts, Cfg.ORANGE)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Cfg.WHITE, 1.5)
