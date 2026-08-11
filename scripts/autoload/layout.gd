extends Node
## Responsive layout brain.
##
## The project renders at a 1280x720 logical base with `canvas_items` stretch,
## so scaling is a single knob: Window.content_scale_factor. A phone gets a
## larger factor (fewer, bigger logical pixels -> thumb-sized controls), a big
## desktop monitor gets a modest bump so the board is not lost in the middle.
## Screens listen to `layout_changed` and re-flow between landscape and portrait.

signal layout_changed

enum Form { PHONE, TABLET, DESKTOP }

const BASE_SIZE := Vector2i(1280, 720)
const MIN_TOUCH_PX := 52.0   # logical px; Material/HIG minimum comfortable target

var form: Form = Form.DESKTOP
var portrait := false
var touch_primary := false
var ui_scale := 1.0
var safe_area := Rect2i()

var _last_size := Vector2i.ZERO
var _pending_emit := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_primary = DisplayServer.is_touchscreen_available() and OS.get_name() in ["Android", "iOS"]
	get_tree().root.size_changed.connect(_recalculate)
	_recalculate()


## Polling the window each frame makes the pass self-correcting: resize events
## can arrive before the window reports its final size, and content_scale_factor
## only takes effect on the following frame. Listeners are therefore notified
## one frame after the scale is applied, when logical_size() is trustworthy.
func _process(_delta: float) -> void:
	if get_window().size != _last_size:
		_recalculate()
	elif _pending_emit:
		_pending_emit = false
		layout_changed.emit()


func _recalculate() -> void:
	var win := get_window()
	var size := win.size
	if size.x <= 0 or size.y <= 0:
		return

	_last_size = size
	portrait = size.y > size.x
	form = _detect_form(size)
	safe_area = DisplayServer.get_display_safe_area()

	# Pin the stretch base to the live window so the project's 1280x720 design
	# size stops contributing its own scale. With base == window the stretch
	# factor is exactly 1, which leaves content_scale_factor as the single knob
	# that decides how big a logical pixel is.
	var factor := _scale_for(size)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if win.content_scale_size != size:
		win.content_scale_size = size
	if not is_equal_approx(win.content_scale_factor, factor):
		win.content_scale_factor = factor
	ui_scale = factor
	_pending_emit = true


func _detect_form(size: Vector2i) -> Form:
	if not touch_primary:
		return Form.DESKTOP
	# Diagonal in inches decides phone vs tablet; fall back to pixel count when
	# the platform reports a nonsense DPI.
	var dpi := DisplayServer.screen_get_dpi()
	if dpi > 40:
		var inches := Vector2(size).length() / float(dpi)
		return Form.TABLET if inches >= 6.5 else Form.PHONE
	return Form.TABLET if mini(size.x, size.y) >= 900 else Form.PHONE


## The scale is chosen so the *short* side always lands near a target number of
## logical pixels. A phone therefore gets few, large logical pixels (thumb-sized
## controls) while a 4K monitor gets a crisp 1:1.5 upscale of the same layout.
## Deriving it from the short side is what makes portrait work: a tall narrow
## window scales UP, it does not shrink the UI into the corner.
func _scale_for(size: Vector2i) -> float:
	var short_side := float(mini(size.x, size.y))
	var target := 720.0
	match form:
		Form.PHONE:
			target = 560.0 if portrait else 640.0
		Form.TABLET:
			target = 820.0
		Form.DESKTOP:
			target = 640.0 if portrait else 720.0
	return clampf(snappedf(short_side / target, 0.01), 0.5, 3.0)


## Logical viewport size after content scaling -- what layouts should design to.
## This is the canvas the UI actually draws into.
func logical_size() -> Vector2:
	var win := get_window()
	var rect := win.get_visible_rect().size
	if rect.x > 1.0 and rect.y > 1.0:
		return rect
	return Vector2(win.size) / maxf(win.content_scale_factor, 0.01)


## Minimum comfortable button height for the current input device.
func touch_size() -> float:
	return MIN_TOUCH_PX if touch_primary else 40.0


## Board cell size that fits `available` while staying inside sane bounds.
func cell_size_for(available: Vector2, rows: int, cols: int) -> float:
	if rows <= 0 or cols <= 0:
		return 32.0
	var by_w := available.x / float(cols)
	var by_h := available.y / float(rows)
	return clampf(floorf(minf(by_w, by_h)), 18.0, 96.0)


## How far above the finger a dragged piece floats so it stays visible.
func drag_lift() -> float:
	return 78.0 if touch_primary else 0.0


func is_phone() -> bool:
	return form == Form.PHONE
