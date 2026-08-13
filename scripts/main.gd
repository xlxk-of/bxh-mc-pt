extends Node
## Root router. Owns the GameSession, the layer stack, and every screen
## transition: menu -> run -> shop / perks / Lucifer's -> game over -> menu.

const CRT_SHADER := "res://scripts/fx/crt.gdshader"

var session: GameSession

var _bg_layer: CanvasLayer
var _game_layer: CanvasLayer
var _fx_layer: CanvasLayer
var _ui_layer: CanvasLayer
var _post_layer: CanvasLayer

var _background: LevelBackground
var _hud: HUD
var _toasts: ToastLayer
var _flash: ColorRect
var _crt: ColorRect
var _crt_material: ShaderMaterial

var _menu: MainMenu
var _active_screen: ScreenBase
var _modal: ScreenBase
var _in_run := false
var _best_combo := 0


func _ready() -> void:
	randomize()
	UIKit.install_theme(get_tree().root)
	_build_layers()

	session = GameSession.new()
	session.name = "Session"
	add_child(session)
	_connect_session()

	_hud.bind(session)
	_hud.board.geometry_changed.connect(_sync_toast_anchor)
	Layout.layout_changed.connect(_sync_toast_anchor)
	_sync_toast_anchor()
	_apply_display_settings()
	_show_main_menu()
	get_tree().auto_accept_quit = false


# ==========================================================================
#  Layers
# ==========================================================================
func _build_layers() -> void:
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -100
	add_child(_bg_layer)
	_background = LevelBackground.new()
	_bg_layer.add_child(_background)

	_game_layer = CanvasLayer.new()
	_game_layer.layer = 0
	add_child(_game_layer)
	_hud = HUD.new()
	_hud.request_dialog.connect(_on_hud_dialog)
	_hud.request_settings.connect(_open_settings.bind(false))
	_game_layer.add_child(_hud)
	Juice.register_shake_target(_game_layer)

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 10
	add_child(_fx_layer)
	_toasts = ToastLayer.new()
	_fx_layer.add_child(_toasts)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 1)
	_flash.modulate.a = 0.0
	_fx_layer.add_child(_flash)
	Juice.register_flash_rect(_flash)

	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 20
	add_child(_ui_layer)

	_post_layer = CanvasLayer.new()
	_post_layer.layer = 100
	add_child(_post_layer)
	_crt = ColorRect.new()
	_crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(CRT_SHADER):
		_crt_material = ShaderMaterial.new()
		_crt_material.shader = load(CRT_SHADER)
		_crt.material = _crt_material
	_post_layer.add_child(_crt)


func _apply_display_settings() -> void:
	if _crt_material:
		_crt_material.set_shader_parameter("enabled", 1.0 if SaveGame.crt_filter else 0.0)
	_crt.visible = SaveGame.crt_filter
	if SaveGame.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	Audio.apply_volumes()


func _process(_delta: float) -> void:
	if _crt_material:
		_crt_material.set_shader_parameter("fever", Juice.fever_ratio())


# ==========================================================================
#  Session wiring
# ==========================================================================
func _connect_session() -> void:
	session.message_posted.connect(func(text: String, color: Color, duration: float):
		_toasts.post(text, color, duration))
	session.floating_score.connect(func(text: String, kind: String):
		_toasts.float_score(text, kind, _board_anchor()))
	session.request_screen.connect(_on_request_screen)
	session.pending_effect_changed.connect(_on_pending_effect_changed)
	session.stats_changed.connect(_on_stats_changed)
	session.combo_changed.connect(_on_combo_changed)
	session.lines_cleared.connect(_on_lines_cleared)
	session.boss_state_changed.connect(_on_boss_state)
	session.game_over.connect(_on_game_over)


## Park the message feed in the band the board reserves under the grid.
func _sync_toast_anchor() -> void:
	if _hud == null or _hud.board == null or not _hud.board.is_inside_tree():
		return
	var rect := _hud.board.grid_rect()
	var bottom_global: Vector2 = _hud.board.get_global_transform() * rect.end
	_toasts.set_anchor_bottom(bottom_global.y + 70.0)


func _board_anchor() -> Vector2:
	if _hud and _hud.board:
		var rect := _hud.board.grid_rect()
		var global := _hud.board.get_global_transform() * (rect.position + Vector2(rect.size.x * 0.5, -30.0))
		return global
	return Vector2.INF


func _on_stats_changed() -> void:
	if not _in_run:
		return
	_background.apply_theme(_background.theme_for_round(session.round_count))
	if session.score >= 100000:
		SteamManager.unlock("SCORE_100K")
	if session.cards.size() >= session.max_cards:
		SteamManager.unlock("FULL_HOUSE")


func _on_combo_changed(streak: int, _chances: int) -> void:
	if streak > _best_combo:
		_best_combo = streak
		if streak >= 10:
			SteamManager.unlock("COMBO_10")
		if streak >= 25:
			SteamManager.unlock("COMBO_25")


func _on_lines_cleared(_count: int, _rows: Array, _cols: Array) -> void:
	SteamManager.unlock("FIRST_BLOOD")


func _on_boss_state() -> void:
	if session.boss_active:
		_background.apply_theme("furnace")
	SteamManager.flush()


# ==========================================================================
#  Screen routing
# ==========================================================================
func _clear_screen() -> void:
	if _active_screen != null and is_instance_valid(_active_screen):
		_active_screen.queue_free()
	_active_screen = null
	_toasts.set_muted(false)


## Full-screen menus mute the running commentary so the two do not overlap.
func _set_screen(screen: ScreenBase) -> void:
	_active_screen = screen
	_toasts.set_muted(true)
	screen.closed.connect(func():
		if _active_screen == screen:
			_active_screen = null
		_toasts.set_muted(false))
	_ui_layer.add_child(screen)


func _show_main_menu() -> void:
	_in_run = false
	_clear_screen()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_hud.visible = false
	# Not just hidden: a hidden HUD still holds a 3D viewport per card.
	_hud.release_visuals()
	_toasts.clear()
	Juice.reset()
	_background.apply_theme("limbo")

	_menu = MainMenu.new()
	_menu.has_saved_run = SaveGame.has_run()
	_menu.start_run.connect(_start_new_run)
	_menu.continue_run.connect(_continue_run)
	_menu.open_settings.connect(_open_settings.bind(true))
	_menu.quit_game.connect(_quit)
	_ui_layer.add_child(_menu)
	Audio.play_music(Cfg.MUSIC_MENU)
	SteamManager.set_rich_presence("steam_display", "#Status_Menu")


func _enter_run() -> void:
	_in_run = true
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	_hud.visible = true
	_hud.ensure_built()
	_background.apply_theme(_background.theme_for_round(session.round_count))
	Audio.play_music(Cfg.MUSIC_INGAME)
	SteamManager.set_rich_presence("steam_display", "#Status_Playing")


func _start_new_run() -> void:
	SaveGame.delete_run()
	_best_combo = 0
	session.start_new_run()
	_enter_run()


func _continue_run() -> void:
	var data := SaveGame.load_run()
	if data.is_empty() or not session.from_save_dict(data):
		session.post_message("Save could not be loaded - starting fresh.", Cfg.RED, 2.5)
		_start_new_run()
		return
	_best_combo = session.combo_streak
	_enter_run()
	session.post_message("Run restored - round %d." % session.round_count, Cfg.ACCENT_GOOD, 2.0)


func _on_request_screen(screen: String) -> void:
	match screen:
		"shop": _open_shop()
		"perks": _open_perks()
		"lucifer": _open_lucifer()
		"gameover": pass   # handled by the game_over signal


func _open_shop() -> void:
	_clear_screen()
	var shop := ShopScreen.new()
	shop.session = session
	shop.exit_shop.connect(func():
		session.exit_shop()
		_active_screen = null)
	shop.request_dialog.connect(_on_shop_dialog.bind(shop))
	_set_screen(shop)


func _open_perks() -> void:
	_clear_screen()
	var perks := PerkScreen.new()
	perks.session = session
	perks.finished.connect(func(): _active_screen = null)
	_set_screen(perks)


func _open_lucifer() -> void:
	_clear_screen()
	var lucifer := LuciferScreen.new()
	lucifer.session = session
	lucifer.finished.connect(func(): _active_screen = null)
	_set_screen(lucifer)


func _on_game_over() -> void:
	_clear_screen()
	var over := GameOverScreen.new()
	over.final_score = session.score
	over.best_score = SaveGame.high_score
	over.is_new_best = session.score >= SaveGame.high_score and session.score > 0
	over.rounds_survived = session.round_count
	over.restart_run.connect(func():
		_active_screen = null
		_start_new_run())
	over.to_main_menu.connect(func():
		_active_screen = null
		_show_main_menu())
	_set_screen(over)
	SteamManager.set_stat("last_score", session.score)
	SteamManager.flush()


func _open_settings(from_menu: bool) -> void:
	if _modal != null and is_instance_valid(_modal):
		return
	Audio.set_music_dimmed(true)
	var settings := SettingsScreen.new()
	settings.from_main_menu = from_menu
	settings.crt_changed.connect(func(on: bool):
		_crt.visible = on
		if _crt_material:
			_crt_material.set_shader_parameter("enabled", 1.0 if on else 0.0))
	settings.resume_run.connect(func(): pass)
	settings.restart_run.connect(_start_new_run)
	settings.to_main_menu.connect(func():
		if _in_run:
			session.save_run()
		_show_main_menu())
	settings.closed.connect(func():
		Audio.set_music_dimmed(false)
		_modal = null
		_toasts.set_muted(_active_screen != null))
	_modal = settings
	_toasts.set_muted(true)
	_ui_layer.add_child(settings)


# ==========================================================================
#  Dialogs
# ==========================================================================
func _on_hud_dialog(kind: String, payload: Dictionary) -> void:
	_open_dialog(kind, payload, null)


func _on_shop_dialog(kind: String, payload: Dictionary, shop: ShopScreen) -> void:
	_open_dialog(kind, payload, shop)


func _open_dialog(kind: String, payload: Dictionary, shop: ShopScreen) -> void:
	if _modal != null and is_instance_valid(_modal):
		return
	match kind:
		"sell_card":
			_confirm_sell("card", payload, shop)
		"sell_item":
			_confirm_sell("item", payload, shop)
		"mimic":
			_open_mimic_picker(int(payload["index"]))
		"merlin":
			_open_merlin_picker(int(payload["index"]))


func _confirm_sell(kind: String, payload: Dictionary, shop: ShopScreen) -> void:
	var box := ConfirmBox.new()
	box.title_text = "Sell %s?" % payload.get("name", "")
	box.body_text = "for $%d" % int(payload.get("price", 0))
	box.confirm_text = "Sell"
	box.cancel_text = "Keep"
	box.confirmed.connect(func():
		if kind == "card":
			session.sell_card(int(payload["index"]))
		else:
			session.sell_item(int(payload["index"]))
		if shop != null and is_instance_valid(shop):
			shop.refresh())
	box.closed.connect(func(): _modal = null)
	_modal = box
	_ui_layer.add_child(box)


func _open_mimic_picker(index: int) -> void:
	var picker := CardPicker.new()
	picker.title_text = "The Mimic"
	picker.subtitle_text = "Copy another card's effect (once per round)"
	picker.entries = session.mimicable_targets(index)
	picker.show_sell = true
	picker.sell_label = "Sell The Mimic ($%d)" % session.sell_price_for_card(session.cards[index])
	picker.picked.connect(func(card_name: String):
		session.set_mimic_target(index, card_name)
		_hud._refresh_inventory())
	picker.sell_requested.connect(func():
		_confirm_sell("card", {
			"index": index, "name": "The Mimic",
			"price": session.sell_price_for_card(session.cards[index])}, null))
	picker.closed.connect(func(): _modal = null)
	_modal = picker
	_ui_layer.add_child(picker)


func _open_merlin_picker(index: int) -> void:
	var card: Dictionary = session.cards[index]
	var picker := PiecePicker.new()
	picker.title_text = "Merlin's Hat"
	picker.subtitle_text = "This piece spawns 500%% more often"
	picker.highlight_name = String(session.get_state(card, "chosen_piece_name", ""))
	picker.locked = not session.merlin_can_reselect(index)
	picker.locked_text = "Selection is on cooldown until round %d." % int(
		session.get_state(card, "selection_cooldown_round", 0))
	picker.show_sell = true
	picker.sell_label = "Sell ($%d)" % session.sell_price_for_card(card)
	# When The Mimic is copying Merlin's Hat, offer a route back to its own menu.
	picker.show_back = card["name"] == "The Mimic"
	picker.back_label = "Back to Mimic"
	picker.picked.connect(func(shape_name: String):
		session.set_merlin_piece(index, shape_name))
	picker.sell_requested.connect(func():
		_confirm_sell("card", {
			"index": index, "name": card["name"],
			"price": session.sell_price_for_card(card)}, null))
	picker.back_requested.connect(func():
		_modal = null
		_open_mimic_picker(index))
	picker.closed.connect(func(): _modal = null)
	_modal = picker
	_ui_layer.add_child(picker)


## Magic Ball conjure -- opened straight from the session's pending state.
func _open_conjure_picker() -> void:
	if _modal != null and is_instance_valid(_modal):
		return
	var picker := PiecePicker.new()
	picker.title_text = "Magic Ball"
	picker.subtitle_text = "Conjure any piece into your hand"
	picker.picked.connect(func(shape_name: String): session.conjure_piece(shape_name))
	picker.closed.connect(func():
		_modal = null
		if session.conjure_active:
			session.cancel_pending())
	_modal = picker
	_ui_layer.add_child(picker)


# ==========================================================================
#  Global input
# ==========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _modal != null and is_instance_valid(_modal):
			return
		if not session.pending_effect.is_empty() or session.conjure_active:
			session.cancel_pending()
			get_viewport().set_input_as_handled()
			return
		if _in_run and _active_screen == null:
			_open_settings(false)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_menu") and OS.is_debug_build():
		_toggle_debug_menu()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if _in_run and session != null and not session.is_game_over:
			session.save_run()


func _quit() -> void:
	if _in_run and session != null and not session.is_game_over:
		session.save_run()
	SaveGame.save_settings()
	SteamManager.shutdown()
	get_tree().quit()


# ==========================================================================
#  Debug menu (debug builds only)
# ==========================================================================
func _toggle_debug_menu() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.close()
		return
	var picker := CardPicker.new()
	picker.title_text = "Debug: grant a card"
	picker.subtitle_text = "Debug builds only"
	var entries: Array = []
	for c in Cards.CARDS:
		entries.append({"name": c["name"], "rarity": c["rarity"]})
	picker.entries = entries
	picker.picked.connect(func(card_name: String):
		session.add_card(card_name)
		session.generate_hand())
	picker.closed.connect(func(): _modal = null)
	_modal = picker
	_ui_layer.add_child(picker)


func _on_pending_effect_changed() -> void:
	if session.conjure_active:
		_open_conjure_picker()
