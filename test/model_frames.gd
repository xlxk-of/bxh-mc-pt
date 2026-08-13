extends Node
## Renders every card and item model at icon size and checks that none of it
## touches the edge of its viewport, at every angle of the turntable.
##
## "The model is cut off" is invisible in code and obvious in pixels: a model
## that overflows its ortho box paints right up to the border, so a non-empty
## outermost ring is exactly the bug. Each failing entry is written out as a PNG
## so the crop can be seen rather than argued about.
##
##   godot --path . res://test/model_frames.tscn

const OUT_DIR := "user://shots_models/"
const ICON := 192
## Sampled around a full turn: clipping is rotation-dependent, and a model can
## sit comfortably head-on while its corners leave the frame side-on.
const ANGLES := 8
## Ignore all-but-invisible edge pixels: MSAA and the soft rim light bleed a
## little alpha outward even when the silhouette is comfortably inside.
const ALPHA_FLOOR := 0.08

var _root: Control
var _failures: Array[String] = []
var _checked := 0
var _skipped: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_root = Control.new()
	_root.size = Vector2(ICON, ICON)
	add_child(_root)
	await get_tree().process_frame

	print("=== model framing: %dpx icon, %d angles ===" % [ICON, ANGLES])
	for entry in Cards.CARDS:
		await _check(entry["name"], entry.get("rarity", "Common"))
	for entry in Cards.ITEMS:
		await _check(entry["name"], entry.get("rarity", "Common"))

	if not _skipped.is_empty():
		print("no 3D model (frame-strip fallback): ", ", ".join(_skipped))
	print("=== %d models checked, %d cropped ===" % [_checked, _failures.size()])
	for f in _failures:
		print("  CROPPED ", f)
	if not _failures.is_empty():
		print("crops written to ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(entry_name: String, rarity: String) -> void:
	var icon := CardIcon.new()
	icon.interactive = false
	icon.custom_minimum_size = Vector2(ICON, ICON)
	_root.add_child(icon)
	icon.size = Vector2(ICON, ICON)
	icon.set_entry(entry_name, rarity)
	await get_tree().process_frame

	var viewport: SubViewport = icon._viewport
	if viewport == null or not is_instance_valid(viewport):
		_skipped.append(entry_name)
		icon.queue_free()
		return

	_checked += 1
	var worst := 0.0
	var worst_angle := 0.0
	for i in ANGLES:
		var angle := TAU * float(i) / float(ANGLES)
		icon._pivot.rotation.y = angle
		await RenderingServer.frame_post_draw
		var edge := _edge_alpha(viewport.get_texture().get_image())
		if edge > worst:
			worst = edge
			worst_angle = angle
	if worst > ALPHA_FLOOR:
		_failures.append("%s (alpha %.2f at %.0f deg)" % [entry_name, worst, rad_to_deg(worst_angle)])
		icon._pivot.rotation.y = worst_angle
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(
			OUT_DIR + entry_name.to_snake_case().validate_filename() + ".png")
	icon.queue_free()


## Highest alpha anywhere on the outermost ring of pixels. Anything solid there
## has been sliced off by the edge of the viewport.
func _edge_alpha(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return 0.0
	var worst := 0.0
	for x in w:
		worst = maxf(worst, img.get_pixel(x, 0).a)
		worst = maxf(worst, img.get_pixel(x, h - 1).a)
	for y in h:
		worst = maxf(worst, img.get_pixel(0, y).a)
		worst = maxf(worst, img.get_pixel(w - 1, y).a)
	return worst
