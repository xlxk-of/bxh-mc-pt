extends Node
## Throwaway diagnostics: report control sizes after the HUD builds, and probe
## which glyphs each bundled font actually contains.

func _ready() -> void:
	_probe_fonts()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in 40:
		await get_tree().process_frame
	main._start_new_run()
	for _i in 40:
		await get_tree().process_frame

	var hud: HUD = main._hud
	print("window          : ", get_window().size, " scale=", get_window().content_scale_factor)
	print("Layout.logical  : ", Layout.logical_size(), " portrait=", Layout.portrait, " form=", Layout.form)
	_dump("HUD", hud)
	for child in hud.get_children():
		_dump("  " + child.get_class(), child)
		for g in child.get_children():
			_dump("    " + g.get_class(), g)
			for h in g.get_children():
				_dump("      " + h.get_class() + " " + h.name, h)
	print("board rect      : ", hud.board.get_rect(), " grid=", hud.board.grid_rect(), " cell=", hud.board.cell_size)
	get_tree().quit()


func _dump(label: String, node: Node) -> void:
	if node is Control:
		var c := node as Control
		print("%-28s pos=%s size=%s min=%s flags=%d/%d" % [
			label, c.position, c.size, c.get_combined_minimum_size(),
			c.size_flags_horizontal, c.size_flags_vertical])


func _probe_fonts() -> void:
	var probe := "ABCXYZ abcxyz 0123456789 $/,.:()%!-x"
	for kind in ["title", "pixel", "numeric"]:
		var f: Font = UIKit.font(kind)
		var missing := ""
		for i in probe.length():
			var ch := probe[i]
			if ch == " ":
				continue
			if not f.has_char(ch.unicode_at(0)):
				missing += ch
		print("font %-8s -> %-28s missing: %s" % [kind, f.get_font_name(), ("(none)" if missing.is_empty() else missing)])
