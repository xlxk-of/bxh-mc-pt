extends Node
## Why are the ScreenBase overlays invisible? Dump their geometry and modulate.

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in 40:
		await get_tree().process_frame
	main._start_new_run()
	for _i in 30:
		await get_tree().process_frame

	main.session.generate_shop_offers()
	main._open_shop()
	for _i in 60:
		await get_tree().process_frame

	var shop: Control = main._active_screen
	print("Engine.time_scale = ", Engine.time_scale, "  tree.paused = ", get_tree().paused)
	print("Juice fever=", Juice.fever_level, " trauma-ish")
	print("shop            pos=%s size=%s mod=%s vis=%s" % [shop.position, shop.size, shop.modulate, shop.visible])
	_walk(shop, 0)


func _walk(node: Node, depth: int) -> void:
	if depth > 5:
		return
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			print("%s%s pos=%s size=%s min=%s mod=%.2f vis=%s" % [
				"  ".repeat(depth + 1), c.get_class(), c.position, c.size,
				c.get_combined_minimum_size(), c.modulate.a, c.visible])
			_walk(child, depth + 1)
