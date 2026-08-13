class_name TouchDragScroll
extends Node
## Finger-drag scrolling for a ScrollContainer whose children are interactive.
##
## Godot hands a whole gesture to the control that accepted the press, so a shop
## full of panels and Buy buttons can only be scrolled from the gutters between
## the cards -- a few pixels of target on a phone. This watches input *before*
## the GUI does; once the finger has clearly travelled rather than tapped, it
## takes the gesture over, makes the child let go without firing, and drives the
## scroll itself.
##
## Install it on any ScrollContainer:
##     TouchDragScroll.install(scroll)

## How far the finger must travel before a tap is reinterpreted as a scroll.
## Below this a shaky thumb still buys the card it was aiming at.
const START_THRESHOLD := 12.0
## Flick inertia: how fast the throw bleeds off, in fractions per second.
const FLICK_DECAY := 6.0
const FLICK_STOP := 14.0

var _scroll: ScrollContainer
var _armed := false
var _dragging := false
var _axis_x := false
var _press := Vector2.ZERO
var _velocity := 0.0


static func install(scroll: ScrollContainer) -> TouchDragScroll:
	var helper := TouchDragScroll.new()
	helper.name = "TouchDragScroll"
	scroll.add_child(helper)
	return helper


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer
	set_process_input(_scroll != null)
	set_process(false)


func _input(event: InputEvent) -> void:
	# Touch only. A mouse has a wheel and a scrollbar, and stealing its drags
	# would break every click-and-hold control in the list.
	if _scroll == null or not Layout.touch_primary:
		return
	if not _scroll.is_visible_in_tree() or get_viewport().is_input_handled():
		return

	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _armed:
		_on_motion(event as InputEventMouseMotion)


func _on_button(mb: InputEventMouseButton) -> void:
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_armed = _scroll.get_global_rect().has_point(mb.global_position) \
			and (_can_scroll(false) or _can_scroll(true))
		_press = mb.global_position
		_dragging = false
		_velocity = 0.0
		set_process(false)
		return
	if _dragging:
		# The children let go back in _take_over(), so the real release can pass
		# through untouched -- it lands on a control that is no longer pressing.
		_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
		set_process(absf(_velocity) > FLICK_STOP)
	_armed = false
	_dragging = false


func _on_motion(mm: InputEventMouseMotion) -> void:
	if not _dragging:
		var travel := mm.global_position - _press
		# The dominant direction decides the axis, so a horizontal drag across a
		# slider still belongs to the slider rather than scrolling the page.
		var wants_x: bool = absf(travel.x) > absf(travel.y)
		var distance: float = absf(travel.x) if wants_x else absf(travel.y)
		if distance < START_THRESHOLD or not _can_scroll(wants_x):
			return
		_axis_x = wants_x
		_dragging = true
		_take_over()

	var delta: float = mm.relative.x if _axis_x else mm.relative.y
	_apply(-delta)
	_velocity = delta / maxf(get_process_delta_time(), 0.001)
	get_viewport().set_input_as_handled()


## Coast after a flick, the way a native list does.
func _process(delta: float) -> void:
	_velocity = move_toward(_velocity, 0.0, absf(_velocity) * FLICK_DECAY * delta + FLICK_STOP)
	if absf(_velocity) < FLICK_STOP:
		_velocity = 0.0
		set_process(false)
		return
	_apply(-_velocity * delta)


func _apply(amount: float) -> void:
	if _axis_x:
		_scroll.scroll_horizontal += roundi(amount)
	else:
		_scroll.scroll_vertical += roundi(amount)


func _can_scroll(horizontal: bool) -> bool:
	var bar: ScrollBar = _scroll.get_h_scroll_bar() if horizontal else _scroll.get_v_scroll_bar()
	return bar != null and bar.max_value - bar.page > 1.0


## The control under the finger already took the press and would fire on
## release. NOTIFICATION_SCROLL_BEGIN is the engine's own "a scroll started, let
## go" signal -- it is what Godot's built-in touch scrolling sends, BaseButton
## drops its press attempt on it, and CardIcon and PiecePreview do the same.
func _take_over() -> void:
	_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
