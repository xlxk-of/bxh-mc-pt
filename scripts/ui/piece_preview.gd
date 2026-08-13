class_name PiecePreview
extends Control
## One slot in the piece tray. Draws the shape, shows selection, and is the
## start point for drag-to-place. A short tap selects; a drag picks up.

signal selected(index: int)
signal drag_started(index: int, global_pos: Vector2)
signal double_tapped(index: int)

const DRAG_THRESHOLD := 10.0

var shape: Dictionary = {}
var index := -1
var is_selected := false:
	set(value):
		is_selected = value
		queue_redraw()
var is_pocket := false
var hidden_for_drag := false:
	set(value):
		hidden_for_drag = value
		queue_redraw()

var _press_pos := Vector2.ZERO
var _pressing := false
var _drag_fired := false
var _last_tap_time := 0.0
var _hover := 0.0
var _mouse_in := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Only a fallback. Callers that size their slots -- the HUD tray sizes its
	# own off the tap-target metric -- set this before the node enters the tree,
	# and stomping their value here is what used to pin every tray to 84px.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(84, 84)
	mouse_entered.connect(func(): _mouse_in = true)
	mouse_exited.connect(func(): _mouse_in = false)
	set_process(true)


func set_shape(new_shape: Dictionary) -> void:
	shape = new_shape
	queue_redraw()


func _process(delta: float) -> void:
	var want := 1.0 if _mouse_in else 0.0
	var next: float = lerpf(_hover, want, 1.0 - pow(0.002, delta))
	if absf(next - _hover) > 0.001:
		_hover = next
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if shape.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pressing = true
			_drag_fired = false
			_press_pos = mb.global_position
			selected.emit(index)
			accept_event()
		else:
			if _pressing and not _drag_fired:
				var now := Time.get_ticks_msec() / 1000.0
				if now - _last_tap_time < Cfg.DOUBLE_CLICK_TIME:
					double_tapped.emit(index)
					_last_tap_time = 0.0
				else:
					_last_tap_time = now
			_pressing = false
			accept_event()
	elif event is InputEventMouseMotion and _pressing and not _drag_fired:
		var mm := event as InputEventMouseMotion
		if mm.global_position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_drag_fired = true
			drag_started.emit(index, mm.global_position)


func _notification(what: int) -> void:
	# The landscape tray lives in a scroll view; a finger dragging it into view
	# must not also pick up the piece it happened to start on.
	if what == NOTIFICATION_SCROLL_BEGIN:
		_pressing = false
		_drag_fired = false


func _draw() -> void:
	var accent := Cfg.CYAN if is_pocket else Cfg.ACCENT_PRIMARY
	var bg := Color(0.09, 0.09, 0.16, 0.75 + 0.15 * _hover)
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	var border_alpha := 0.9 if is_selected else (0.25 + 0.35 * _hover)
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r, accent.g, accent.b, border_alpha),
		false, 3.0 if is_selected else 1.5)

	if shape.is_empty() or hidden_for_drag:
		if is_pocket:
			var label := "EMPTY" if shape.is_empty() else ""
			if not label.is_empty():
				var f: Font = UIKit.font("ui")
				var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.55), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.35))
		return

	var coords: Array = shape.get("coords", [])
	if coords.is_empty():
		return
	var dims := Cfg.shape_size(shape)
	var pad: float = maxf(6.0, minf(size.x, size.y) * 0.12)
	var block: float = minf((size.x - pad * 2.0) / float(dims.x), (size.y - pad * 2.0) / float(dims.y))
	# Cap relative to the slot, not at a fixed pixel size, so a piece fills the
	# space it is given on a phone instead of floating in the middle of it.
	block = minf(block, minf(size.x, size.y) * 0.34)
	var total := Vector2(dims.x, dims.y) * block
	var origin := (size - total) * 0.5 + Vector2(0, -1.0 * _hover * 3.0)

	var min_r := 9999
	var min_c := 9999
	for off in coords:
		min_r = mini(min_r, off.x)
		min_c = mini(min_c, off.y)

	var col: Color = shape.get("color", Cfg.WHITE)
	for off in coords:
		var pos := origin + Vector2(off.y - min_c, off.x - min_r) * block
		var r := Rect2(pos, Vector2(block, block)).grow(-1.5)
		draw_rect(r, col, true)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34)), Color(1, 1, 1, 0.18), true)
		draw_rect(r, Color(0, 0, 0, 0.4), false, 1.0)
