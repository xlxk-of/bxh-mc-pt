class_name MainMenu
extends Control
## Title screen. Keeps the original's rising, rotating, fading block field and
## the focus-grows-the-button menu, rebuilt as real Controls so it scales.

signal start_run
signal continue_run
signal open_settings
signal quit_game

const BTN_BASE_W := 260.0
const BTN_FOCUS_W := 380.0
const BTN_BASE_H := 56.0
const BTN_FOCUS_H := 78.0

var has_saved_run := false

var _buttons: Array[Button] = []
var _focus_index := 0
var _progress: Array[float] = []
var _shapes: MenuShapeField
var _column: Control


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shapes = MenuShapeField.new()
	_shapes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shapes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shapes)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0, 0, 0, 0.42)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	Layout.layout_changed.connect(func():
		UIKit.fill_viewport(self)
		_rebuild())
	_rebuild()
	set_process(true)


func _rebuild() -> void:
	if _column != null and is_instance_valid(_column):
		_column.queue_free()
	_buttons.clear()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 24 if Layout.portrait else 60
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	add_child(margin)
	_column = margin

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(centre)

	var outer := VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 6)
	outer.custom_minimum_size.x = 0.0 if Layout.portrait else BTN_FOCUS_W
	centre.add_child(outer)

	var title := UIKit.make_title("BLOCK X HELL", "huge" if not Layout.portrait else "large")
	if Layout.portrait:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var subtitle := UIKit.make_label("Climb the tower", "small", Cfg.TEXT_DIM)
	if Layout.portrait:
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(subtitle)

	outer.add_child(UIKit.spacer(18))
	var hs_label := UIKit.make_label("HIGH SCORE", "small", Cfg.TEXT_DIM)
	var hs_value := UIKit.make_number(str(SaveGame.high_score), "large")
	if Layout.portrait:
		hs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hs_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hs_label)
	outer.add_child(hs_value)
	outer.add_child(UIKit.spacer(24))

	var defs: Array = []
	if has_saved_run:
		defs = [
			{"key": "continue", "label": "Continue Run", "accent": Cfg.ACCENT_GOOD},
			{"key": "new", "label": "New Run", "accent": Cfg.ACCENT_PRIMARY},
			{"key": "settings", "label": "Settings", "accent": Cfg.PANEL_ACCENT},
			{"key": "quit", "label": "Quit Game", "accent": Cfg.ACCENT_DANGER},
		]
	else:
		defs = [
			{"key": "new", "label": "Start Run", "accent": Cfg.ACCENT_PRIMARY},
			{"key": "settings", "label": "Settings", "accent": Cfg.PANEL_ACCENT},
			{"key": "quit", "label": "Quit Game", "accent": Cfg.ACCENT_DANGER},
		]

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	outer.add_child(list)

	_progress.clear()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var b := UIKit.make_button(d["label"], d["accent"], "medium")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT if not Layout.portrait else HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(BTN_BASE_W if not Layout.portrait else 0.0, BTN_BASE_H)
		if Layout.portrait:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("key", d["key"])
		b.set_meta("slot", i)
		b.mouse_entered.connect(func(): _focus_index = i)
		b.focus_entered.connect(func(): _focus_index = i)
		b.pressed.connect(_on_pressed.bind(String(d["key"])))
		list.add_child(b)
		_buttons.append(b)
		_progress.append(0.0)

	if not _buttons.is_empty():
		_focus_index = clampi(_focus_index, 0, _buttons.size() - 1)
		_buttons[_focus_index].grab_focus()

	outer.add_child(UIKit.spacer(14))
	var hint := "Tap to select" if Layout.touch_primary else "Mouse / arrows to navigate, click or Enter to select"
	var hint_label := UIKit.make_label(hint, "tiny", Cfg.TEXT_DIM)
	if Layout.portrait:
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint_label)


func _on_pressed(key: String) -> void:
	match key:
		"continue": continue_run.emit()
		"new": start_run.emit()
		"settings": open_settings.emit()
		"quit": quit_game.emit()


## Focused entries grow and brighten, matching the original menu's feel.
func _process(delta: float) -> void:
	if Layout.portrait:
		return
	for i in _buttons.size():
		if not is_instance_valid(_buttons[i]):
			continue
		var target := 1.0 if i == _focus_index else 0.0
		_progress[i] = lerpf(_progress[i], target, 1.0 - pow(0.0005, delta))
		var p := _progress[i]
		_buttons[i].custom_minimum_size = Vector2(
			lerpf(BTN_BASE_W, BTN_FOCUS_W, p),
			lerpf(BTN_BASE_H, BTN_FOCUS_H, p))
		_buttons[i].add_theme_font_size_override("font_size",
			int(lerpf(UIKit.font_size("medium"), UIKit.font_size("large"), p)))


func _unhandled_input(event: InputEvent) -> void:
	if _buttons.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		_move_focus(1)
	elif event.is_action_pressed("ui_up"):
		_move_focus(-1)


func _move_focus(delta: int) -> void:
	_focus_index = wrapi(_focus_index + delta, 0, _buttons.size())
	_buttons[_focus_index].grab_focus()
	Audio.play(Cfg.SFX_UI_CLICK, 0.5)
