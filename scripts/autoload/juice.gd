extends Node
## Game feel: trauma-based screen shake, hit-stop, full-screen flashes and the
## combo "fever" level that drives the escalating UI reaction.
##
## Screens call register_shake_target() with the CanvasLayer / Control they want
## rattled, and register_flash_rect() with a full-screen ColorRect.

signal fever_changed(level: int, streak: int)
signal shockwave(screen_pos: Vector2, strength: float)

## Combo thresholds for each fever tier. Tier 0 is "no fever".
const FEVER_THRESHOLDS := [0, 3, 5, 10, 20]
const MAX_TRAUMA := 1.0
const TRAUMA_DECAY := 1.8
const MAX_OFFSET := 26.0
const MAX_ROLL := 0.06

var fever_level := 0
var combo_streak := 0
var enabled := true

var _trauma := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _shake_targets: Array[Node] = []
var _flash_rect: ColorRect
var _flash_tween: Tween
var _hitstop_until := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.9
	_noise.seed = randi()


func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001)
	_time += real_delta

	if _hitstop_until > 0.0 and _time >= _hitstop_until:
		_hitstop_until = 0.0
		Engine.time_scale = 1.0

	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * real_delta)
	_apply_shake()


func _apply_shake() -> void:
	_shake_targets = _shake_targets.filter(func(n): return is_instance_valid(n))
	if _shake_targets.is_empty():
		return
	var amount: float = _trauma * _trauma * SaveGame.screen_shake * (1.0 if enabled else 0.0)
	var offset := Vector2.ZERO
	var roll := 0.0
	if amount > 0.0001:
		var t: float = _time * 34.0
		offset = Vector2(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(0.0, t)) * MAX_OFFSET * amount
		roll = _noise.get_noise_2d(t, 100.0) * MAX_ROLL * amount
	for n in _shake_targets:
		if n is CanvasLayer:
			(n as CanvasLayer).offset = offset
			(n as CanvasLayer).rotation = roll
		elif n is Node2D:
			(n as Node2D).position = offset
			(n as Node2D).rotation = roll
		elif n is Control:
			var c := n as Control
			c.position = c.get_meta("juice_home", Vector2.ZERO) + offset
			c.rotation = roll


func register_shake_target(node: Node) -> void:
	if node == null or _shake_targets.has(node):
		return
	if node is Control:
		node.set_meta("juice_home", (node as Control).position)
	_shake_targets.append(node)


func unregister_shake_target(node: Node) -> void:
	_shake_targets.erase(node)


func register_flash_rect(rect: ColorRect) -> void:
	_flash_rect = rect
	if _flash_rect:
		_flash_rect.modulate.a = 0.0
		_flash_rect.visible = true


# ----------------------------------------------------------------- effects
## `amount` is additive trauma in 0..1. Shake magnitude is trauma squared, so
## small repeated taps stay subtle while big hits really land.
func shake(amount: float, vibrate_ms := 0) -> void:
	if not enabled:
		return
	_trauma = minf(MAX_TRAUMA, _trauma + amount)
	if vibrate_ms > 0 and SaveGame.haptics and Layout.touch_primary:
		Input.vibrate_handheld(vibrate_ms)


## Freeze-frame for `seconds` of real time, used on big clears and explosions.
func hitstop(seconds: float, scale := 0.05) -> void:
	if not enabled or seconds <= 0.0:
		return
	Engine.time_scale = scale
	_hitstop_until = maxf(_hitstop_until, _time + seconds)


func flash(color: Color, strength := 0.5, duration := 0.25) -> void:
	if _flash_rect == null or not enabled:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(color.r, color.g, color.b, 1.0)
	_flash_rect.modulate.a = clampf(strength, 0.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.set_ignore_time_scale(true)
	_flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func emit_shockwave(screen_pos: Vector2, strength := 1.0) -> void:
	shockwave.emit(screen_pos, strength)


# -------------------------------------------------------------------- fever
func set_combo(streak: int) -> void:
	combo_streak = streak
	var level := 0
	for i in range(FEVER_THRESHOLDS.size() - 1, 0, -1):
		if streak >= FEVER_THRESHOLDS[i]:
			level = i
			break
	if level != fever_level:
		fever_level = level
		fever_changed.emit(fever_level, streak)


func fever_ratio() -> float:
	return float(fever_level) / float(FEVER_THRESHOLDS.size() - 1)


func reset() -> void:
	_trauma = 0.0
	combo_streak = 0
	if fever_level != 0:
		fever_level = 0
		fever_changed.emit(0, 0)
	Engine.time_scale = 1.0
	_hitstop_until = 0.0
