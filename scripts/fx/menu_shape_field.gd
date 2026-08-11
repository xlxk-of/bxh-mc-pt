class_name MenuShapeField
extends Control
## The menu's ambient block field: tetromino silhouettes drift upward, spinning
## slowly and fading out near the top. Straight port of the pygame version's
## main_menu_bg_shapes, but resolution independent.

const SPAWN_CHANCE := 1.4      # expected spawns per second
const BLOCK_SIZE := 17.0
const FADE_ZONE := 0.34        # top fraction of the screen where shapes fade

var _shapes: Array = []
var _accum := 0.0
var _seeded := false


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Layout.layout_changed.connect(func(): UIKit.fill_viewport(self))
	set_process(true)


func _spawn(vertical_bias := 0.0) -> void:
	var shape: Dictionary = Cfg.SHAPES[randi() % Cfg.SHAPES.size()]
	var dims := Cfg.shape_size(shape)
	var w := dims.x * BLOCK_SIZE
	var h := dims.y * BLOCK_SIZE
	_shapes.append({
		"shape": shape,
		"pos": Vector2(randf_range(-w * 0.5, size.x - w * 0.5), lerpf(size.y + h, -h, vertical_bias)),
		"speed": randf_range(22.0, 78.0),
		"angle": randf_range(0.0, TAU),
		"spin": randf_range(-0.9, 0.9),
		"alpha": 1.0,
		"dims": Vector2(w, h),
	})


func _process(delta: float) -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		UIKit.fill_viewport(self)
		return
	if _shapes.is_empty() and not _seeded:
		_seeded = true
		for i in 12:
			_spawn(randf())
	_accum += delta * SPAWN_CHANCE
	while _accum >= 1.0:
		_accum -= 1.0
		if _shapes.size() < 46:
			_spawn()

	var fade_y: float = size.y * FADE_ZONE
	var keep: Array = []
	for s in _shapes:
		s["pos"].y -= s["speed"] * delta
		s["angle"] += s["spin"] * delta
		var centre_y: float = s["pos"].y + s["dims"].y * 0.5
		s["alpha"] = 1.0 if centre_y > fade_y else clampf(centre_y / maxf(fade_y, 1.0), 0.0, 1.0)
		if centre_y + s["dims"].y > 0.0 and s["alpha"] > 0.01:
			keep.append(s)
	_shapes = keep
	queue_redraw()


func _draw() -> void:
	for s in _shapes:
		var shape: Dictionary = s["shape"]
		var coords: Array = shape["coords"]
		if coords.is_empty():
			continue
		var min_r := 9999
		var min_c := 9999
		for off in coords:
			min_r = mini(min_r, off.x)
			min_c = mini(min_c, off.y)

		var centre: Vector2 = s["pos"] + s["dims"] * 0.5
		var rot: float = s["angle"]
		var col: Color = shape["color"]
		var a: float = s["alpha"] * 0.55

		draw_set_transform(centre, rot, Vector2.ONE)
		var half: Vector2 = s["dims"] * 0.5
		for off in coords:
			var local := Vector2(off.y - min_c, off.x - min_r) * BLOCK_SIZE - half
			var r := Rect2(local, Vector2(BLOCK_SIZE, BLOCK_SIZE)).grow(-1.0)
			draw_rect(r, Color(col.r, col.g, col.b, a), true)
			draw_rect(r, Color(1, 1, 1, a * 0.35), false, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
