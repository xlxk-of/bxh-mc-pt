class_name Shockwave
extends Node2D
## Expanding ring drawn on top of an explosion, then self-frees. Cheap enough
## to fire several per clear without touching the particle budget.

@export var ring_color := Color.WHITE
@export var max_radius := 160.0
@export var duration := 0.42
@export var thickness := 6.0

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var p: float = clampf(_t / duration, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - p, 3.0)
	var radius: float = max_radius * eased
	var alpha: float = (1.0 - p) * 0.85
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48,
		Color(ring_color.r, ring_color.g, ring_color.b, alpha), thickness * (1.0 - p * 0.7), true)
	draw_arc(Vector2.ZERO, radius * 0.82, 0.0, TAU, 40,
		Color(1, 1, 1, alpha * 0.5), thickness * 0.4 * (1.0 - p), true)
