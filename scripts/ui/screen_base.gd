class_name ScreenBase
extends Control
## Common chrome for every full-screen overlay: a dimming scrim, a centred
## content column that stays readable at any aspect ratio, and a short
## open/close animation. Subclasses fill `content` in `_build()`.

signal closed

@export var scrim_alpha := 0.82
@export var max_content_width := 900.0
@export var use_scroll := true

var content: VBoxContainer
var _scrim: ColorRect
var _frame: Control
var _closing := false


func _ready() -> void:
	UIKit.fill_viewport(self)
	Layout.layout_changed.connect(func(): UIKit.fill_viewport(self))
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scrim = UIKit.make_scrim(scrim_alpha)
	add_child(_scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 14 if Layout.portrait else 28
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	add_child(margin)

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(centre)

	var available := Layout.logical_size() - Vector2(pad, pad) * 2.0
	_frame = VBoxContainer.new()
	_frame.custom_minimum_size.x = minf(max_content_width, available.x)
	if use_scroll:
		# Scroll views must be told how tall to be; their own minimum is zero.
		_frame.custom_minimum_size.y = maxf(120.0, available.y)
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_frame)

	if use_scroll:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Without a deadzone, a touch drag that starts on a button is swallowed
		# by the button instead of scrolling the list.
		scroll.scroll_deadzone = 12
		scroll.follow_focus = true
		_frame.add_child(scroll)
		content = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 12)
		scroll.add_child(content)
	else:
		content = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 12)
		_frame.add_child(content)

	_build()
	_animate_in()


## Subclasses override this.
func _build() -> void:
	pass


func _animate_in() -> void:
	_scrim.modulate.a = 0.0
	_frame.modulate.a = 0.0
	_frame.scale = Vector2(0.97, 0.97)
	_frame.pivot_offset = _frame.size * 0.5
	var t := create_tween()
	t.set_ignore_time_scale(true)
	t.set_parallel(true)
	t.tween_property(_scrim, "modulate:a", 1.0, 0.18)
	t.tween_property(_frame, "modulate:a", 1.0, 0.22)
	t.tween_property(_frame, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween()
	t.set_ignore_time_scale(true)
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.16)
	t.tween_property(_frame, "scale", Vector2(0.97, 0.97), 0.16)
	t.chain().tween_callback(func():
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		on_cancel()
		get_viewport().set_input_as_handled()


## Escape / back gesture. Overridden by screens that must not be dismissed.
func on_cancel() -> void:
	Audio.play(Cfg.SFX_UI_CLICK)
	close()


## Standard header: big title plus optional subtitle.
func add_header(title: String, subtitle := "", accent := Cfg.ACCENT_PRIMARY) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var t := UIKit.make_title(title, "large" if Layout.portrait else "title", accent)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if not subtitle.is_empty():
		var s := UIKit.make_label(subtitle, "small", Cfg.TEXT_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)
	content.add_child(box)


## Row of buttons that wraps to a column on narrow screens.
func add_button_row(buttons: Array[Button]) -> BoxContainer:
	var box: BoxContainer = VBoxContainer.new() if Layout.portrait else HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(b)
	content.add_child(box)
	return box
