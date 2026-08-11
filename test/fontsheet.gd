extends Node
## Renders a sample sheet of every bundled font so glyph quality can be judged
## by eye (has_char() reports true even for placeholder/watermark glyphs).

const SAMPLES := [
	"BLOCK X HELL",
	"Cards: 3/5  Sets 1/5",
	"$1,234  +$5  x10  67%",
	"Angel's Kiss (Ultra)",
	"abcdefghijklmnopqrstuvwxyz",
]


func _ready() -> void:
	var root := Control.new()
	root.size = Vector2(1100, 620)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.09)
	bg.size = root.size
	root.add_child(bg)
	add_child(root)

	var y := 12.0
	for kind in ["title", "pixel", "numeric"]:
		var header := Label.new()
		header.text = "— " + kind + " —"
		header.position = Vector2(14, y)
		header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		root.add_child(header)
		y += 26
		for s in SAMPLES:
			var l := Label.new()
			l.text = s
			l.add_theme_font_override("font", UIKit.font(kind))
			l.add_theme_font_size_override("font_size", 24)
			l.add_theme_color_override("font_color", Color(1, 1, 1))
			l.position = Vector2(24, y)
			root.add_child(l)
			y += 30
		y += 10

	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots/")
	img.save_png("user://shots/fontsheet.png")
	print("fontsheet written")
	get_tree().quit()
