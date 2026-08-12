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
## Tap targets and body copy are sized in *physical points*, not logical pixels.
## A phone packs ~620 logical pixels into a 402pt-wide screen, so a "60 logical
## px" button is really 39pt -- under Apple's 44pt floor. 48pt clears both the
## iOS (44pt) and Android (48dp) minimums.
const MIN_TOUCH_PT := 48.0
## How far above the finger a dragged piece floats, in physical points. A thumb
## plus the knuckle behind it covers roughly 100pt, which is why Block Blast
## lifts the piece clear of the whole hand rather than just the fingertip.
const DRAG_LIFT_PT := 112.0

var form: Form = Form.DESKTOP
var portrait := false
var touch_primary := false
var ui_scale := 1.0
var safe_area := Rect2i()

var _last_size := Vector2i.ZERO
var _pending_emit := false
var _pixel_ratio := 1.0
var _detected_touch := false
var _touch_seen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detected_touch = _detect_touch()
	touch_primary = _resolve_touch()
	_pixel_ratio = _detect_pixel_ratio()
	get_tree().root.size_changed.connect(_recalculate)
	_recalculate()


## A finger on the glass is the one signal that cannot be wrong, so it wins over
## every guess below. Mice never produce screen-touch events (Godot only
## synthesises them the other way round, and only when explicitly asked), so
## this cannot misfire on a desktop.
func _input(event: InputEvent) -> void:
	if _touch_seen:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_seen = true
		refresh_touch_mode()


## Native builds report their platform directly. The web build does not:
## OS.get_name() is "Web" everywhere, so an iPhone running the PWA would
## otherwise be treated as a desktop and get desktop-sized everything.
func _detect_touch() -> bool:
	if OS.get_name() in ["Android", "iOS"]:
		return true
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web"):
		# The feature tags above are user-agent sniffing, and a home-screen PWA
		# or a browser in "Request Desktop Site" mode reports a desktop UA. Ask
		# the browser about the pointer hardware instead, which it answers
		# honestly either way.
		var probe: Variant = JavaScriptBridge.eval("""
			(navigator.maxTouchPoints || 0) > 0
			|| 'ontouchstart' in window
			|| window.matchMedia('(pointer: coarse)').matches
		""", true)
		if typeof(probe) == TYPE_BOOL and probe:
			return true
		if DisplayServer.is_touchscreen_available():
			return true
	return false


## Detection is a guess; the player's setting is not. 0 = auto, 1 = force touch,
## 2 = force desktop.
func _resolve_touch() -> bool:
	match SaveGame.touch_override:
		1: return true
		2: return false
	return _detected_touch or _touch_seen


## Re-evaluates touch mode and re-flows the UI if the answer changed. Called by
## the settings screen and by the first touch event.
func refresh_touch_mode() -> void:
	var want := _resolve_touch()
	if want == touch_primary:
		return
	touch_primary = want
	_recalculate()


## Physical pixels alone cannot separate a phone from a tablet -- a modern phone
## has more of them than an old laptop. CSS pixels can, so divide out the device
## pixel ratio. screen_get_dpi() is unreliable on web (it reports 96 * ratio,
## which makes a 6" phone measure as a 10" tablet), hence asking the browser.
func _detect_pixel_ratio() -> float:
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval("window.devicePixelRatio", true)
		if value is float or value is int:
			return clampf(float(value), 1.0, 4.0)
	var s := DisplayServer.screen_get_scale()
	return clampf(s, 1.0, 4.0) if s > 0.0 else 1.0


## Size in CSS/points rather than raw pixels -- the number that actually tracks
## physical screen size.
func reference_size(size: Vector2i) -> Vector2:
	return Vector2(size) / maxf(_pixel_ratio, 0.5)


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


## Phone vs tablet from the CSS short side: phones land around 320-450pt,
## tablets around 700-1100pt, regardless of how many physical pixels they pack.
func _detect_form(size: Vector2i) -> Form:
	if not touch_primary:
		return Form.DESKTOP
	var short_pt: float = minf(reference_size(size).x, reference_size(size).y)
	if short_pt <= 550.0:
		return Form.PHONE
	if short_pt <= 1100.0:
		return Form.TABLET
	return Form.DESKTOP


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
			# Landscape phones are height-starved: a smaller target means fewer,
			# larger logical pixels, so the board and tray both stay usable.
			target = 620.0 if portrait else 430.0
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


## How many logical pixels cover one physical point on this display. This is the
## bridge between "how big is it in the layout" and "how big is it under a
## thumb": the stretch pass deliberately hands a phone *more* logical pixels
## than it has points, so anything that must stay physically large has to be
## multiplied by this or it silently shrinks.
func points_to_logical() -> float:
	var factor := get_window().content_scale_factor
	if factor <= 0.01:
		return 1.0
	return clampf(_pixel_ratio / factor, 0.75, 3.0)


## Minimum comfortable button height for the current input device.
func touch_size() -> float:
	if not touch_primary:
		return 40.0
	return maxf(56.0, MIN_TOUCH_PT * points_to_logical())


## Type has to grow by the same ratio as tap targets, or a phone ends up with
## physically *smaller* text than the desktop the layout was designed on.
func text_scale() -> float:
	if not touch_primary:
		return 1.0
	return clampf(points_to_logical(), 1.0, 1.7)


## Board cell size that fits `available` while staying inside sane bounds.
func cell_size_for(available: Vector2, rows: int, cols: int) -> float:
	if rows <= 0 or cols <= 0:
		return 32.0
	var by_w := available.x / float(cols)
	var by_h := available.y / float(rows)
	return clampf(floorf(minf(by_w, by_h)), 18.0, 96.0)


## How far above the finger the *bottom edge* of a dragged piece floats. Kept in
## physical points so the gap is the same real-world distance on every handset,
## with a board-relative floor so it never reads as less than two rows.
func drag_lift(cell_size := 40.0) -> float:
	if not touch_primary:
		return 0.0
	return maxf(cell_size * 2.0, DRAG_LIFT_PT * points_to_logical())


func is_phone() -> bool:
	return form == Form.PHONE


## Phones in landscape need their own arrangement: the desktop three-column
## layout spends most of a short screen on side rails.
func is_phone_landscape() -> bool:
	return form == Form.PHONE and not portrait


## True when the compact, single-rail arrangement should be used.
func is_compact() -> bool:
	return form == Form.PHONE or (form == Form.TABLET and portrait)
