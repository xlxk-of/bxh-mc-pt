extends Node
## Focused check for TouchDragScroll, away from the rest of the game.
##
## Builds a tall list of buttons in a ScrollContainer, then drives synthetic
## pointer gestures at it:
##   * a drag that starts on a button scrolls the list and does not press it
##   * a tap on that same button still presses it
##   * a horizontal drag is left alone, so sliders keep working
##
##   godot --path . res://test/scroll_touch.tscn

const ROWS := 24

var _scroll: ScrollContainer
var _presses: Array[int] = []
var _failures := 0


func _ready() -> void:
	Layout.touch_primary = true
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(600, 800)
	layer.add_child(root)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.position = Vector2(20, 20)
	_scroll.size = Vector2(560, 700)
	root.add_child(_scroll)
	TouchDragScroll.install(_scroll)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 560
	column.add_theme_constant_override("separation", 8)
	_scroll.add_child(column)
	for i in ROWS:
		var b := Button.new()
		b.text = "Row %d" % i
		b.custom_minimum_size.y = 70
		var idx := i
		b.pressed.connect(func(): _presses.append(idx))
		column.add_child(b)

	await get_tree().process_frame
	await get_tree().process_frame

	var target: Button = column.get_child(2)
	var centre: Vector2 = target.get_global_rect().get_center()

	# 1. Vertical drag starting on a button.
	var before: int = _scroll.scroll_vertical
	_presses.clear()
	await _drag(centre, Vector2(0, -28), 8)
	await _idle(0.35)
	_check("drag from a button scrolls", _scroll.scroll_vertical - before > 80,
		"moved %dpx" % (_scroll.scroll_vertical - before))
	_check("drag from a button does not press it", _presses.is_empty(),
		"presses=%s" % str(_presses))

	# 2. Tap on a button.
	_scroll.scroll_vertical = 0
	await _idle(0.2)
	_presses.clear()
	await _tap(column.get_child(2).get_global_rect().get_center())
	await _idle(0.2)
	_check("tap still presses", _presses == [2], "presses=%s" % str(_presses))

	# 3. Horizontal drag must be ignored by a vertical-only list, so that a
	#    slider inside one keeps its own gesture.
	before = _scroll.scroll_vertical
	_presses.clear()
	await _drag(column.get_child(2).get_global_rect().get_center(), Vector2(30, 0), 8)
	await _idle(0.3)
	_check("horizontal drag leaves the list alone",
		_scroll.scroll_vertical == before, "moved %dpx" % (_scroll.scroll_vertical - before))

	print("=== scroll touch: %d failures ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %-42s %s  (%s)" % [what, "OK" if ok else "FAIL", detail])


func _drag(from: Vector2, step: Vector2, steps: int) -> void:
	_press(from)
	await get_tree().process_frame
	var at := from
	for i in steps:
		at += step
		var move := InputEventMouseMotion.new()
		move.position = at
		move.global_position = at
		move.relative = step
		Input.parse_input_event(move)
		await get_tree().process_frame
	_release(at)
	await get_tree().process_frame


func _tap(at: Vector2) -> void:
	_press(at)
	await get_tree().process_frame
	_release(at)
	await get_tree().process_frame


func _press(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


func _release(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


func _idle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame
