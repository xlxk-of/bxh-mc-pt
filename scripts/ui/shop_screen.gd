class_name ShopScreen
extends ScreenBase
## Between-round shop: sell from your inventory, buy cards and items, reroll.

signal exit_shop
signal request_dialog(kind: String, payload: Dictionary)

var session: GameSession

var _money_label: Label
var _offers_box: VBoxContainer
var _inventory_box: HBoxContainer
var _reroll_button: Button


func _init() -> void:
	max_content_width = 1000.0
	scrim_alpha = 0.94


func _build() -> void:
	if session == null:
		return
	add_header("Shop", "Round %d" % session.round_count, Cfg.ACCENT_PRIMARY)

	_money_label = UIKit.make_number("$%d" % session.money, "medium", Cfg.MONEY_COLOR)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_money_label)

	content.add_child(UIKit.make_section("Your Inventory - hold to sell"))
	var inv_scroll := ScrollContainer.new()
	inv_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_scroll.custom_minimum_size.y = 88
	content.add_child(inv_scroll)
	_inventory_box = HBoxContainer.new()
	_inventory_box.add_theme_constant_override("separation", 8)
	inv_scroll.add_child(_inventory_box)

	content.add_child(UIKit.make_section("For Sale"))
	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override("separation", 10)
	content.add_child(_offers_box)

	content.add_child(UIKit.spacer(6))
	_reroll_button = UIKit.make_button("Reroll", Cfg.ACCENT_PRIMARY, "small")
	_reroll_button.pressed.connect(_on_reroll)
	var exit_button := UIKit.make_button("Exit Shop", Cfg.ACCENT_DANGER, "small")
	exit_button.pressed.connect(_on_exit)
	add_button_row([_reroll_button, exit_button])

	refresh()


func refresh() -> void:
	if session == null or _offers_box == null:
		return
	_money_label.text = "$%d" % session.money
	_refresh_inventory()
	_refresh_offers()
	_refresh_reroll()


func _refresh_reroll() -> void:
	var free := session.window_shopper_free_reroll() != null
	_reroll_button.text = "Reroll (Free!)" if free else "Reroll ($%d)" % session.shop_reroll_cost
	_reroll_button.disabled = not free and session.money < session.shop_reroll_cost


func _refresh_inventory() -> void:
	for child in _inventory_box.get_children():
		child.queue_free()
	if session.cards.is_empty() and session.items.is_empty():
		_inventory_box.add_child(UIKit.make_label("(empty)", "tiny", Cfg.GRAY))
		return

	for i in session.cards.size():
		var card: Dictionary = session.cards[i]
		var shown: String = session.effective_name(card)
		var icon := CardIcon.new()
		icon.custom_minimum_size = Vector2(62, 62)
		icon.index = i
		icon.set_entry(shown, Cards.card(shown).get("rarity", "Common"))
		icon.tooltip_text = "%s\n%s\n\nHold to sell for $%d" % [
			shown, Cards.card(shown).get("description", ""), session.sell_price_for_card(card)]
		icon.long_pressed.connect(func(ic: CardIcon):
			request_dialog.emit("sell_card", {
				"index": ic.index, "name": session.cards[ic.index]["name"],
				"price": session.sell_price_for_card(session.cards[ic.index])}))
		icon.pressed.connect(func(ic: CardIcon):
			session.post_message("%s - hold to sell." % ic.entry_name, Cfg.LIGHT_GRAY, 1.0))
		_inventory_box.add_child(icon)

	if not session.items.is_empty():
		var sep := VSeparator.new()
		_inventory_box.add_child(sep)

	for i in session.items.size():
		var item: Dictionary = session.items[i]
		var icon := CardIcon.new()
		icon.custom_minimum_size = Vector2(62, 62)
		icon.index = i
		icon.set_entry(item["name"], item.get("rarity", "Common"))
		icon.tooltip_text = "%s\n%s\n\nHold to sell for $%d" % [
			item["name"], Cards.item(item["name"]).get("description", ""), session.sell_price_for_item(item)]
		icon.long_pressed.connect(func(ic: CardIcon):
			request_dialog.emit("sell_item", {
				"index": ic.index, "name": session.items[ic.index]["name"],
				"price": session.sell_price_for_item(session.items[ic.index])}))
		_inventory_box.add_child(icon)


func _refresh_offers() -> void:
	for child in _offers_box.get_children():
		child.queue_free()

	for i in session.shop_offers["cards"].size():
		var offer: Dictionary = session.shop_offers["cards"][i]
		var cost := session.shop_price(offer["name"], Cards.card_cost(offer["name"]))
		_offers_box.add_child(_make_offer_row(
			offer["name"], offer["rarity"], Cards.card(offer["name"]).get("description", ""),
			cost, session.cards.size() >= session.max_cards, "card", i))

	for i in session.shop_offers["items"].size():
		var offer: Dictionary = session.shop_offers["items"][i]
		var cost := session.shop_price(offer["name"], int(offer.get("cost", 0)))
		_offers_box.add_child(_make_offer_row(
			offer["name"], offer.get("rarity", "Common"), Cards.item(offer["name"]).get("description", ""),
			cost, session.items.size() >= session.max_items, "item", i))

	if _offers_box.get_child_count() == 0:
		_offers_box.add_child(UIKit.make_label("Sold out! Reroll for new stock.", "small", Cfg.TEXT_DIM))


func _make_offer_row(entry_name: String, rarity: String, description: String,
		cost: int, inventory_full: bool, kind: String, index: int) -> Control:
	var rarity_col := Cfg.rarity_color(rarity)
	var panel := UIKit.make_panel(Color(0.09, 0.09, 0.16), rarity_col)

	var row: BoxContainer = VBoxContainer.new() if Layout.portrait else HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var icon := CardIcon.new()
	icon.custom_minimum_size = Vector2(104, 104)
	icon.interactive = false
	icon.set_entry(entry_name, rarity)
	if Layout.portrait:
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.add_child(UIKit.make_label(entry_name, "body", Cfg.WHITE))
	title_row.add_child(UIKit.make_rarity_chip(rarity))
	text.add_child(title_row)

	var desc := UIKit.make_label(description, "small", Cfg.LIGHT_GRAY)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 220
	text.add_child(desc)

	var buy := UIKit.make_button("Buy  $%d" % cost, Cfg.ACCENT_GOOD, "small")
	buy.custom_minimum_size.x = 150
	if Layout.portrait:
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if inventory_full:
		buy.disabled = true
		buy.text = "Slots full"
	elif session.money < cost:
		buy.disabled = true
		buy.text = "$%d - short" % cost
	buy.pressed.connect(func():
		if session.buy_shop_entry(kind, index):
			refresh())
	row.add_child(buy)
	return panel


func _on_reroll() -> void:
	session.reroll_shop()
	refresh()


func _on_exit() -> void:
	exit_shop.emit()
	close()


func on_cancel() -> void:
	_on_exit()
