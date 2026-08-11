class_name ToastLayer
extends Control
## Transient text: the message queue from add_message(), plus the rising score
## pop-ups from the floating-text system.

const MAX_TOASTS := 4

var anchor_point := Vector2(0.5, 0.72)   ## where score pops spawn, in viewport %
## Bottom edge of the message stack in logical px. NAN falls back to a
## viewport-relative position.
var anchor_y := NAN

var _stack: VBoxContainer


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.add_theme_constant_override("separation", 2)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	Layout.layout_changed.connect(func():
		UIKit.fill_viewport(self)
		_reposition())
	_reposition()


## The stack grows upward from its anchor line so a burst of messages never
## runs off the bottom of the screen.
func _reposition() -> void:
	var vp := Layout.logical_size()
	var width: float = minf(560.0, vp.x - 40.0)
	var height := 150.0
	_stack.size = Vector2(width, height)
	var bottom: float = anchor_y
	if is_nan(bottom):
		bottom = vp.y * (0.60 if Layout.portrait else 0.80)
	bottom = clampf(bottom, height, vp.y)
	_stack.position = Vector2((vp.x - width) * 0.5, bottom - height)


func post(text: String, color := Cfg.WHITE, duration := 1.5) -> void:
	while _stack.get_child_count() >= MAX_TOASTS:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()

	var label := UIKit.make_label(text, "small" if Layout.portrait else "body", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.modulate.a = 0.0
	_stack.add_child(label)

	var t := label.create_tween()
	t.set_ignore_time_scale(true)
	t.tween_property(label, "modulate:a", 1.0, 0.10)
	t.tween_interval(maxf(0.1, duration - 0.4))
	t.tween_property(label, "modulate:a", 0.0, 0.30)
	t.tween_callback(label.queue_free)


## Big score pop that rises and fades, mirroring FloatingText from the original.
func float_score(text: String, kind := "score", at := Vector2.INF) -> void:
	var color := Cfg.GREEN if kind == "score" else Cfg.YELLOW
	var label := UIKit.make_number(text, "large", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	add_child(label)

	var vp := Layout.logical_size()
	var origin := at
	if origin == Vector2.INF:
		origin = Vector2(vp.x * anchor_point.x, vp.y * anchor_point.y)
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	label.position = origin - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.6, 0.6)

	var t := label.create_tween()
	t.set_ignore_time_scale(true)
	t.set_parallel(true)
	t.tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:y", label.position.y - 96.0, 1.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(label, "modulate:a", 0.0, 0.45)
	t.chain().tween_callback(label.queue_free)


## Full-screen menus own the frame; fade the running commentary out of the way.
func set_anchor_bottom(y: float) -> void:
	if is_nan(y) or absf(y - anchor_y) > 1.0:
		anchor_y = y
		_reposition()


func set_muted(muted: bool) -> void:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	t.tween_property(self, "modulate:a", 0.0 if muted else 1.0, 0.15)


func clear() -> void:
	for child in _stack.get_children():
		child.queue_free()
