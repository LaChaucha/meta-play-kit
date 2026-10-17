extends Control

## End-to-end demonstration of the MetaPlayKit public façade. Every functional
## case from the interface documents is reachable from this one scene.

const UI: GDScript = preload("res://addons/metaplay_kit/runtime/ui/ui_factory.gd")
const ResultPanel: GDScript = preload("res://addons/metaplay_kit/runtime/components/level_result_panel.gd")
const CampaignPanel: GDScript = preload("res://addons/metaplay_kit/runtime/components/level_campaign_panel.gd")
const COLOR_GOLD: Color = Color("ffd23f")
const COLOR_INK: Color = Color("36131d")
const COLOR_CREAM: Color = Color("fff5d6")
const COLOR_CYAN: Color = Color("1dd3d0")
const COLOR_RED: Color = Color("ff5d73")

var _home_screen: VBoxContainer = null
var _game_screen: VBoxContainer = null
var _coin_label: Label = null
var _game_coin_label: Label = null
var _game_level_label: Label = null
var _overlay: BlockingBackground = null
var _dialog: PanelContainer = null
var _dialog_body: VBoxContainer = null
var _loading: LoadingOverlay = null
var _toast: Label = null
var _iap: IapAdapter = null

var _current_level_key: Variant = "level1"
var _selected_level_index: int = 0
var _pending_store_key: Variant = null
var _pending_purchase_operation_id: int = 0
var _store_mode: String = "game"
var _result_payload: Dictionary = {}
var _initial_boot: bool = true
var _current_level_node: Node = null
var _loading_operation_id: int = 0
var _current_attempt_id: String = ""
var _demo_action_claims: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_scaffold()
	_build_interface()
	_connect_api()
	_configure_demo_data()
	_loading.visible = true
	TtpGuiApi.request_initial_level_load("level1")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _game_screen.visible:
		if get_tree().paused:
			_resume_game()
		else:
			_show_pause()


func show_home() -> void:
	get_tree().paused = false
	_close_dialog()
	_loading.complete_loading()
	_initial_boot = false
	_home_screen.visible = true
	_game_screen.visible = false
	_update_coins(TtpGuiApi.get_currency_balance())


func show_level(level_data: Dictionary, resource: Resource) -> bool:
	var packed_scene: PackedScene = resource as PackedScene
	if packed_scene == null:
		_on_operation_rejected("No se pudo instanciar el nivel cargado.")
		return false
	var level_node: Node = packed_scene.instantiate()
	if level_node == null:
		_on_operation_rejected("No se pudo crear la instancia del nivel.")
		return false
	var level_key: Variant = level_data.get("key", _current_level_key)
	if level_node.has_method("configure"):
		var configuration_result: Variant = level_node.call("configure", level_key, self)
		if configuration_result is bool and not configuration_result:
			level_node.free()
			_on_operation_rejected("No se pudo configurar el nivel.")
			return false
	level_node.name = "PendingLevel"
	add_child(level_node)
	if level_node.has_method("start_level"):
		var start_result: Variant = level_node.call("start_level")
		if start_result is bool and not start_result:
			if level_node.has_method("stop_level"):
				level_node.call("stop_level")
			remove_child(level_node)
			level_node.queue_free()
			_on_operation_rejected("No se pudo iniciar el nivel.")
			return false
	if is_instance_valid(_current_level_node):
		remove_child(_current_level_node)
		_current_level_node.queue_free()
	level_node.name = "CurrentLevel"
	_current_level_node = level_node
	_current_level_key = level_key
	_current_attempt_id = ""
	if not _initial_boot:
		var attempt_result: MetaPlayResult = TtpGuiApi.begin_level_attempt(level_key)
		if attempt_result.status != MetaPlayResult.Status.COMPLETED:
			remove_child(level_node)
			level_node.queue_free()
			_current_level_node = null
			_on_operation_rejected("No se pudo iniciar la partida.")
			return false
		_current_attempt_id = str(attempt_result.context.get("attempt_id", ""))
		if level_node.has_method("configure_attempt"):
			level_node.call("configure_attempt", _current_attempt_id)
	return true


func change_current_level(new_level: Dictionary) -> void:
	TtpGuiApi.request_level_load(new_level.get("key", _current_level_key))


func set_current_level(level_node: Node) -> void:
	if _current_level_node != null and is_instance_valid(_current_level_node):
		remove_child(_current_level_node)
		_current_level_node.queue_free()
	level_node.name = "CurrentLevel"
	if level_node.get_parent() != self:
		add_child(level_node)
	_current_level_node = level_node


func update_item_game_loaded(_item_key: Variant) -> void:
	_show_toast("Artículo equipado")


func unblock_item_game(_item_key: Variant) -> void:
	_show_toast("Artículo desbloqueado")


func update_total_coins(total: int) -> void:
	_update_coins(total)


func update_sfx_game_configuration(enabled: bool) -> void:
	_show_toast("Efectos activos" if enabled else "Efectos silenciados")


func update_music_game_configuration(enabled: bool) -> void:
	_show_toast("Música activa" if enabled else "Música silenciada")


func level_win(attempt_id: String, score: int, condition_facts: Dictionary) -> void:
	var next_key: Variant = _demo_next_level_key(_current_level_key)
	var presentation: Dictionary = {
		"title": "¡GANASTE!",
		"next_level": {"key": next_key, "label": "SIGUIENTE", "action_id": "next_level"} if next_key != null else {},
		"actions": [
			{"id": "retry", "label": "REPETIR"},
			{"id": "double_completion", "label": "VER VIDEO · +50 MONEDAS", "reward_amount": 50},
			{"id": "home", "label": "INICIO"},
		],
	}
	var result: MetaPlayResult = TtpGuiApi.complete_level(attempt_id, score, condition_facts, presentation)
	if result.status == MetaPlayResult.Status.COMPLETED:
		_update_demo_campaign()


func retry_level(level: Dictionary) -> void:
	change_current_level(level)


func load_next_level(level: Dictionary) -> void:
	var next_level: Dictionary = level.duplicate(true)
	next_level["key"] = level.get("key")
	change_current_level(next_level)


func level_lose(attempt_id: String, score: int, condition_facts: Dictionary) -> void:
	var presentation: Dictionary = {
		"title": "INTÉNTALO DE NUEVO",
		"actions": [
			{"id": "retry", "label": "REPETIR"},
			{"id": "revive", "label": "VER VIDEO · UNA VIDA EXTRA"},
			{"id": "home", "label": "INICIO"},
		],
	}
	TtpGuiApi.complete_level(attempt_id, score, condition_facts, presentation)


func revive_level(_level: Dictionary) -> void:
	if _current_level_node != null and is_instance_valid(_current_level_node) and _current_level_node.has_method("revive"):
		_current_level_node.call("revive")
	_show_game({"level_key": _current_level_key, "revived": true})


func duplicate_won_coins(_next_level_data: Dictionary, balance: int) -> void:
	_update_coins(balance)


func _clear_scaffold() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _build_interface() -> void:
	var background: TextureRect = TextureRect.new()
	background.name = "Background"
	background.texture = preload("res://demo/assets/world/home_room.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var wash: ColorRect = ColorRect.new()
	wash.name = "WarmWash"
	wash.color = Color(0.20, 0.04, 0.13, 0.16)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(wash)

	var frame: MarginContainer = MarginContainer.new()
	frame.name = "ScreenFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_%s" % side, 28)
	background.add_child(frame)

	var screen_stack: Control = Control.new()
	screen_stack.name = "ScreenStack"
	screen_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(screen_stack)

	_home_screen = _build_home_screen()
	screen_stack.add_child(_home_screen)
	_game_screen = _build_game_screen()
	screen_stack.add_child(_game_screen)
	_game_screen.visible = false

	_overlay = BlockingBackground.new()
	_overlay.name = "ModalOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.dismissed.connect(_close_dialog)
	add_child(_overlay)

	var center: CenterContainer = CenterContainer.new()
	center.name = "DialogCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	_dialog = UI.panel(Vector2(600.0, 0.0))
	_dialog.name = "Dialog"
	center.add_child(_dialog)
	_dialog_body = VBoxContainer.new()
	_dialog_body.name = "DialogBody"
	_dialog_body.add_theme_constant_override("separation", 14)
	_dialog.add_child(_dialog_body)
	_overlay.visible = false

	_loading = LoadingOverlay.new()
	_loading.name = "LoadingOverlay"
	_loading.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_loading)
	_loading.visible = false

	_toast = UI.label("", 18, COLOR_CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.name = "Toast"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-220.0, -78.0)
	_toast.size = Vector2(440.0, 52.0)
	_toast.add_theme_stylebox_override("normal", _toast_style())
	_toast.visible = false
	_toast.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast)

	_iap = IapAdapter.new()
	_iap.name = "IAP"
	_iap.purchase_succeeded.connect(_on_iap_purchase_succeeded)
	_iap.purchase_pending.connect(_on_iap_purchase_pending)
	_iap.purchase_failed.connect(_on_iap_purchase_failed)
	_iap.purchase_cancelled.connect(_on_iap_purchase_cancelled)
	_iap.purchases_restored.connect(_on_iap_purchases_restored)
	add_child(_iap)


func _build_home_screen() -> VBoxContainer:
	var screen: VBoxContainer = VBoxContainer.new()
	screen.name = "HomeScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 12)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.name = "StatusBar"
	top_row.add_theme_constant_override("separation", 10)
	screen.add_child(top_row)
	var brand: Label = UI.label("META PLAY KIT", 26, COLOR_CREAM)
	brand.name = "Brand"
	top_row.add_child(brand)
	top_row.add_child(UI.spacer())
	_coin_label = UI.label("", 24, COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_coin_label.name = "CoinLabel"
	top_row.add_child(_coin_label)

	var center: CenterContainer = CenterContainer.new()
	center.name = "HeroCenter"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(center)
	var hero_panel: PanelContainer = UI.panel(Vector2(560.0, 320.0))
	hero_panel.name = "HeroPanel"
	center.add_child(hero_panel)
	var hero: VBoxContainer = VBoxContainer.new()
	hero.name = "HeroContent"
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 12)
	hero_panel.add_child(hero)
	var title: Label = UI.label("ARCADE HOME", 52, COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	title.theme_type_variation = "TitleLabel"
	hero.add_child(title)
	hero.add_child(UI.label("Un kit de metajuego listo para probar", 20, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var stars: StarRating = StarRating.new()
	stars.name = "HomeStars"
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_child(stars)
	var tap: Button = UI.button("TOCA PARA JUGAR", _on_tap_to_play, Vector2(360.0, 72.0))
	tap.name = "TapToPlayButton"
	tap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero.add_child(tap)

	var navigation_center: CenterContainer = CenterContainer.new()
	navigation_center.name = "NavigationCenter"
	screen.add_child(navigation_center)
	var navigation: HBoxContainer = HBoxContainer.new()
	navigation.name = "Navigation"
	navigation.add_theme_constant_override("separation", 16)
	navigation_center.add_child(navigation)
	var levels_button: Button = UI.button("NIVELES", _show_levels, Vector2(200.0, 76.0), preload("res://addons/metaplay_kit/assets/ui/icon_levels.png"))
	levels_button.name = "LevelsButton"
	navigation.add_child(levels_button)
	var store_button: Button = UI.button("TIENDA", _show_store, Vector2(200.0, 76.0), preload("res://addons/metaplay_kit/assets/ui/icon_store.png"))
	store_button.name = "StoreButton"
	navigation.add_child(store_button)
	var config_button: Button = UI.button("AJUSTES", _show_config, Vector2(200.0, 76.0), preload("res://addons/metaplay_kit/assets/ui/icon_settings.png"))
	config_button.name = "ConfigButton"
	navigation.add_child(config_button)
	var promo_button: Button = UI.button("PROMO", _show_promo, Vector2(200.0, 76.0), preload("res://addons/metaplay_kit/assets/ui/icon_video.png"))
	promo_button.name = "PromoButton"
	navigation.add_child(promo_button)
	return screen


func _build_game_screen() -> VBoxContainer:
	var screen: VBoxContainer = VBoxContainer.new()
	screen.name = "GameScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 12)
	var header: HBoxContainer = HBoxContainer.new()
	header.name = "GameHeader"
	screen.add_child(header)
	var pause_button: Button = UI.button("PAUSA", _show_pause, Vector2(170.0, 58.0))
	pause_button.name = "PauseButton"
	header.add_child(pause_button)
	header.add_child(UI.spacer())
	_game_coin_label = UI.label("", 24, COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_game_coin_label.name = "GameCoinLabel"
	header.add_child(_game_coin_label)

	var center: CenterContainer = CenterContainer.new()
	center.name = "LevelCenter"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(center)
	var card: PanelContainer = UI.panel(Vector2(520.0, 300.0))
	card.name = "LevelCard"
	center.add_child(card)
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "LevelContent"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	card.add_child(content)
	_game_level_label = UI.label("", 38, COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_game_level_label.name = "LevelName"
	_game_level_label.theme_type_variation = "TitleLabel"
	content.add_child(_game_level_label)
	content.add_child(UI.label("Escena de prueba: elige un resultado", 20, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "ResultActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	content.add_child(actions)
	var win_button: Button = UI.button("GANAR", _simulate_win, Vector2(180.0, 64.0))
	win_button.name = "WinButton"
	actions.add_child(win_button)
	var lose_button: Button = UI.button("PERDER", _simulate_lose, Vector2(180.0, 64.0))
	lose_button.name = "LoseButton"
	lose_button.theme_type_variation = "DangerButton"
	actions.add_child(lose_button)

	var footer: Label = UI.label("Este nivel simula los callbacks del juego anfitrión", 16, COLOR_CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	footer.name = "GameFooter"
	screen.add_child(footer)
	return screen


func _connect_api() -> void:
	TtpGuiApi.navigation_requested.connect(_on_screen_requested)
	TtpGuiApi.level_load_started.connect(_on_loading_started)
	TtpGuiApi.level_load_result.connect(_on_loading_result)
	TtpGuiApi.currency_balance_changed.connect(_update_coins)
	TtpGuiApi.action_rejected.connect(_on_operation_rejected)
	TtpGuiApi.item_equipped.connect(update_item_game_loaded)
	TtpGuiApi.item_purchased.connect(unblock_item_game)
	TtpGuiApi.sfx_setting_changed.connect(update_sfx_game_configuration)
	TtpGuiApi.music_setting_changed.connect(update_music_game_configuration)
	TtpGuiApi.revive_reward_claimed.connect(revive_level)
	TtpGuiApi.reward_doubling_claimed.connect(duplicate_won_coins)
	TtpGuiApi.level_selection_requested.connect(_on_host_level_selection_requested)
	TtpGuiApi.terminal_action_requested.connect(_on_host_terminal_action_requested)
	TtpGuiApi.loading_progress_changed.connect(_on_loading_progress)
	TtpGuiApi.store_catalog_changed.connect(_on_store_changed)
	TtpGuiApi.currency_purchase_result.connect(_on_currency_purchase_result)


func _configure_demo_data() -> void:
	var levels: Dictionary = {}
	var result_rules: Dictionary = {}
	for index: int in range(1, 7):
		var level_key: String = "level%d" % index
		levels[level_key] = {
			"name": "Nivel %02d" % index,
			"scene_path": "res://demo/scenes/level_stub.tscn",
		}
		result_rules[level_key] = {"max_score": 1500, "star_thresholds": [500, 900, 1200], "required_conditions": ["goal_reached"]}
	TtpGuiApi.configure_levels(levels)
	TtpGuiApi.configure_level_result_rules(result_rules)
	_update_demo_campaign()
	TtpGuiApi.set_currency_balance(800)
	TtpGuiApi.configure_settings({
		"sfx": true,
		"music": true,
		"url_terms_and_conditions": "https://example.com/terms",
		"url_rate_us": "https://example.com/rate",
		"url_video": "https://example.com/promo",
	})
	TtpGuiApi.configure_currency_products({
		"coins_small": {"title": "Bolsa brillante", "description": "500 monedas", "price": "USD 0,99", "bought": false},
		"coins_medium": {"title": "Cofre arcade", "description": "1.500 monedas", "price": "USD 2,49", "bought": false},
		"coins_large": {"title": "Tesoro total", "description": "4.000 monedas", "price": "USD 4,99", "bought": false},
	})
	TtpGuiApi.configure_currency_rewards({"coins_small": 500, "coins_medium": 1500, "coins_large": 4000})
	TtpGuiApi.configure_completion_rewards({"level1": 120, "level2": 120, "level3": 120, "level4": 120, "level5": 120, "level6": 120}, 86400)
	TtpGuiApi.configure_items({
		"sun_hat": {"type": 1, "title": "Sombrero solar", "description": "El clásico del kit", "price": "0", "bought": true, "load": true, "group": "hat", "colorTitle": "#7a2d21"},
		"space_hat": {"type": 1, "title": "Casco espacial", "description": "Un look de otro mundo", "price": "450", "bought": false, "load": false, "group": "hat", "colorTitle": "#7a2d21"},
		"coin_trail": {"type": 0, "title": "Estela dorada", "description": "Brilla al moverte", "price": "250", "bought": false, "colorTitle": "#7a2d21"},
		"power_boost": {"type": 2, "title": "Impulso", "description": "Mejora progresiva", "stages": {
			"phase1": {"title": "Impulso I", "description": "+5%", "price": "100", "bought": false},
			"phase2": {"title": "Impulso II", "description": "+10%", "price": "250", "bought": false},
			"phase3": {"title": "Impulso III", "description": "+20%", "price": "500", "bought": false},
		}},
	})
	_update_coins(800)


func _on_tap_to_play() -> void:
	TtpGuiApi.start_or_resume_game(_demo_play_level_key())


func _show_game(payload: Dictionary) -> void:
	var requested_key: Variant = payload.get("level_key", _current_level_key)
	if not is_instance_valid(_current_level_node) or requested_key != _current_level_key:
		TtpGuiApi.request_level_load(requested_key)
		return
	get_tree().paused = false
	_close_dialog()
	var level: Dictionary = TtpGuiApi.get_level(_current_level_key)
	_game_level_label.text = str(level.get("name", "Nivel de prueba"))
	_home_screen.visible = false
	_game_screen.visible = true
	_update_coins(TtpGuiApi.get_currency_balance())
	if bool(payload.get("revived", false)):
		_show_toast("¡Reanimado! Continúa la partida")


func _show_levels() -> void:
	_begin_dialog("CAMPAÑA")
	var campaign: VBoxContainer = CampaignPanel.new() as VBoxContainer
	campaign.name = "CampaignHistory"
	campaign.call("present_campaign", TtpGuiApi.get_campaign_projection(), TtpGuiApi.get_all_level_progress(), TtpGuiApi.get_levels())
	campaign.connect("level_selection_requested", _on_campaign_entry_selected)
	_dialog_body.add_child(campaign)
	_dialog_body.add_child(UI.button("CERRAR", _close_dialog, Vector2(220.0, 52.0)))


func _render_level_selector(enabled: Array) -> void:
	_begin_dialog("CAMPAÑA")
	var level_key: Variant = enabled[_selected_level_index]
	var level: Dictionary = TtpGuiApi.get_level(level_key)
	var name_label: Label = UI.label(str(level.get("name", "Nivel")), 34, COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.name = "SelectedLevelName"
	_dialog_body.add_child(name_label)
	var stars: StarRating = StarRating.new()
	stars.name = "SelectedLevelStars"
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	_dialog_body.add_child(stars)
	stars.update_modal(int(level.get("max_stars", 0)))
	_dialog_body.add_child(UI.label("Mejor puntuación: %s" % TtpGuiApi.format_number(level.get("max_score", 0)), 18, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "LevelActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_dialog_body.add_child(actions)
	actions.add_child(UI.button("◀", func() -> void: _change_level_preview(-1), Vector2(90.0, 58.0)))
	var play: Button = UI.button("CARGAR", _load_selected_level, Vector2(220.0, 58.0))
	play.name = "LoadLevelButton"
	actions.add_child(play)
	actions.add_child(UI.button("▶", func() -> void: _change_level_preview(1), Vector2(90.0, 58.0)))
	_dialog_body.add_child(UI.button("CERRAR", _close_dialog, Vector2(220.0, 52.0)))


func _change_level_preview(direction: int) -> void:
	var enabled: Array = TtpGuiApi.get_enabled_level_keys()
	_selected_level_index = wrapi(_selected_level_index + direction, 0, enabled.size())
	_render_level_selector(enabled)


func _load_selected_level() -> void:
	var campaign: Array = TtpGuiApi.get_campaign_projection()
	for raw_entry: Variant in campaign:
		if raw_entry is Dictionary and bool((raw_entry as Dictionary).get("selectable", false)):
			TtpGuiApi.select_level((raw_entry as Dictionary).get("key"))
			return


func _on_campaign_entry_selected(level_key: Variant) -> void:
	TtpGuiApi.select_level(level_key)


func _on_host_level_selection_requested(level_key: Variant) -> void:
	change_current_level({"key": level_key})


func _on_result_panel_action_requested(attempt_id: String, action_id: StringName) -> void:
	TtpGuiApi.request_terminal_action(attempt_id, action_id)


func _on_host_terminal_action_requested(attempt_id: String, action_id: StringName) -> void:
	var claim_key: String = "%s:%s" % [attempt_id, str(action_id)]
	if _demo_action_claims.has(claim_key):
		_on_operation_rejected("Esta acción ya fue procesada.")
		return
	match action_id:
		&"retry":
			_demo_action_claims[claim_key] = true
			TtpGuiApi.retry_level(_current_level_key)
		&"next_level":
			_demo_action_claims[claim_key] = true
			_next_level()
		&"home":
			_demo_action_claims[claim_key] = true
			show_home()
		&"double_completion":
			_demo_action_claims[claim_key] = "pending"
			_show_reward_wait("Simulando recompensa de video…", true, attempt_id, action_id)
		&"revive":
			_demo_action_claims[claim_key] = "pending"
			_show_reward_wait("Simulando recompensa de video…", false, attempt_id, action_id)
		_:
			_on_operation_rejected("Acción de resultado desconocida.")


func _demo_next_level_key(current_level_key: Variant) -> Variant:
	var keys: Array = TtpGuiApi.get_levels().keys()
	var current_index: int = keys.find(current_level_key)
	if current_index >= 0 and current_index + 1 < keys.size():
		return keys[current_index + 1]
	return null


func _demo_play_level_key() -> Variant:
	var keys: Array = TtpGuiApi.get_levels().keys()
	var progress: Dictionary = TtpGuiApi.get_all_level_progress()
	for level_key: Variant in keys:
		var level_progress: Dictionary = progress.get(level_key, {}) as Dictionary
		if not bool(level_progress.get("completed", false)):
			return level_key
	return keys.back() if not keys.is_empty() else null


func _update_demo_campaign() -> void:
	var keys: Array = TtpGuiApi.get_levels().keys()
	var progress: Dictionary = TtpGuiApi.get_all_level_progress()
	var highest_completed_index: int = -1
	for index: int in range(keys.size()):
		var level_progress: Dictionary = progress.get(keys[index], {}) as Dictionary
		if bool(level_progress.get("completed", false)):
			highest_completed_index = index
	var all_completed: bool = not keys.is_empty() and highest_completed_index == keys.size() - 1
	var projection: Array = []
	for index: int in range(keys.size()):
		var available: bool = all_completed or index <= highest_completed_index + 1
		projection.append({"key": keys[index], "available": available, "selectable": available})
	TtpGuiApi.configure_campaign_projection(projection)


func _show_config() -> void:
	_begin_dialog("CONFIGURACIÓN")
	var config: Dictionary = TtpGuiApi.get_settings()
	var grid: GridContainer = GridContainer.new()
	grid.name = "ConfigGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	_dialog_body.add_child(grid)
	grid.add_child(UI.label("Efectos", 22, COLOR_INK))
	var sfx: Button = UI.button("ACTIVOS" if bool(config.get("sfx", true)) else "SILENCIADOS", _toggle_sfx, Vector2(230.0, 56.0), preload("res://addons/metaplay_kit/assets/ui/icon_sfx.png"))
	sfx.name = "SfxToggle"
	grid.add_child(sfx)
	grid.add_child(UI.label("Música", 22, COLOR_INK))
	var music: Button = UI.button("ACTIVA" if bool(config.get("music", true)) else "SILENCIADA", _toggle_music, Vector2(230.0, 56.0), preload("res://addons/metaplay_kit/assets/ui/icon_music.png"))
	music.name = "MusicToggle"
	grid.add_child(music)
	_dialog_body.add_child(UI.h_separator())
	_dialog_body.add_child(UI.button("TÉRMINOS Y CONDICIONES", _open_terms, Vector2(360.0, 54.0)))
	_dialog_body.add_child(UI.button("VOLVER", _close_dialog, Vector2(220.0, 52.0)))


func _toggle_sfx() -> void:
	TtpGuiApi.toggle_sfx()
	_show_config()


func _toggle_music() -> void:
	TtpGuiApi.toggle_music()
	_show_config()


func _open_terms() -> void:
	var uri: String = str(TtpGuiApi.get_settings().get("url_terms_and_conditions", ""))
	if not uri.is_empty():
		OS.shell_open(uri)


func _open_rate_page() -> void:
	var uri: String = str(TtpGuiApi.get_settings().get("url_rate_us", ""))
	if not uri.is_empty():
		OS.shell_open(uri)


func _open_promo_web_page() -> void:
	var uri: String = str(TtpGuiApi.get_settings().get("url_video", ""))
	if not uri.is_empty():
		OS.shell_open(uri)


func _show_store() -> void:
	_begin_dialog("TIENDA")
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.name = "StoreTabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	_dialog_body.add_child(tabs)
	var game_tab: Button = UI.button("ARTÍCULOS", func() -> void: _set_store_mode("game"), Vector2(210.0, 52.0))
	game_tab.disabled = _store_mode == "game"
	tabs.add_child(game_tab)
	var currency_tab: Button = UI.button("MONEDAS", func() -> void: _set_store_mode("currency"), Vector2(210.0, 52.0))
	currency_tab.disabled = _store_mode == "currency"
	tabs.add_child(currency_tab)
	var balance: Label = UI.label("Saldo: %s" % TtpGuiApi.format_number(TtpGuiApi.get_currency_balance()), 20, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER)
	balance.name = "StoreBalance"
	_dialog_body.add_child(balance)
	var list: DraggableComponent = DraggableComponent.new()
	list.name = "StoreList"
	list.custom_minimum_size = Vector2(540.0, 330.0)
	list.item_pressed.connect(_on_store_item_pressed)
	_dialog_body.add_child(list)
	if _store_mode == "game":
		list.set_game_items(TtpGuiApi.get_items())
	else:
		list.set_currency_items(TtpGuiApi.get_currency_products())
	_dialog_body.add_child(UI.button("VOLVER", _close_dialog, Vector2(220.0, 52.0)))


func _set_store_mode(mode: String) -> void:
	_store_mode = mode
	_show_store()


func _on_store_item_pressed(item_key: Variant) -> void:
	_pending_store_key = item_key.duplicate() if item_key is Array else item_key
	if item_key is Array:
		var path: Array = item_key as Array
		var item: Dictionary = TtpGuiApi.get_item(path)
		if bool(item.get("bought", false)) and item.has("load"):
			TtpGuiApi.equip_item(path)
			_show_store()
			return
		if bool(item.get("bought", false)):
			_on_operation_rejected("Ya tienes este artículo.")
			return
		_show_store_confirmation("Comprar %s por %s monedas" % [str(item.get("title", "artículo")), str(item.get("price", "0"))])
	else:
		var currency: Dictionary = TtpGuiApi.get_currency_products().get(item_key, {}) as Dictionary
		_show_store_confirmation("Compra simulada: %s · %s" % [str(currency.get("title", "paquete")), str(currency.get("price", ""))])


func _show_store_confirmation(message: String) -> void:
	_begin_dialog("CONFIRMAR")
	_dialog_body.add_child(UI.label(message, 22, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	_dialog_body.add_child(actions)
	actions.add_child(UI.button("CANCELAR", _show_store, Vector2(190.0, 56.0)))
	actions.add_child(UI.button("ACEPTAR", _accept_store_operation, Vector2(190.0, 56.0)))


func _accept_store_operation() -> void:
	if _pending_store_key is Array:
		TtpGuiApi.purchase_item(_pending_store_key as Array)
		_show_store()
	else:
		var start_result: MetaPlayResult = TtpGuiApi.begin_currency_purchase(_pending_store_key)
		if start_result.status != MetaPlayResult.Status.ACCEPTED:
			return
		_pending_purchase_operation_id = start_result.operation_id
		_iap.begin_purchase(_pending_store_key, start_result.operation_id)
		_show_store()


func _on_iap_purchase_succeeded(operation_id: int, purchase: Dictionary) -> void:
	var product_key: Variant = purchase.get("product_key")
	TtpGuiApi.complete_currency_purchase(operation_id, product_key, purchase)


func _on_iap_purchase_pending(operation_id: int, purchase: Dictionary) -> void:
	TtpGuiApi.mark_currency_purchase_pending(operation_id, purchase)


func _on_iap_purchase_failed(operation_id: int, error_code: StringName) -> void:
	TtpGuiApi.fail_currency_purchase(operation_id, error_code)


func _on_iap_purchase_cancelled(operation_id: int) -> void:
	TtpGuiApi.cancel_currency_purchase(operation_id)


func _on_iap_purchases_restored(purchases: Array) -> void:
	TtpGuiApi.restore_purchase_records(purchases)


func _on_currency_purchase_result(result: MetaPlayResult) -> void:
	if result.operation_id != _pending_purchase_operation_id:
		return
	_pending_purchase_operation_id = 0
	match result.status:
		MetaPlayResult.Status.COMPLETED:
			var product_key: Variant = result.context.get("product_key")
			if bool(result.context.get("simulated", false)):
				var credit_result: MetaPlayResult = TtpGuiApi.credit_currency_product(product_key)
				_show_toast("Compra simulada completada" if credit_result.status == MetaPlayResult.Status.COMPLETED else "No se pudo acreditar la simulación")
			else:
				var applied: MetaPlayResult = TtpGuiApi.apply_verified_currency_purchase(result.operation_id)
				if applied.status != MetaPlayResult.Status.COMPLETED:
					_show_toast("No se pudo aplicar la compra verificada")
				else:
					var already_credited: bool = bool(applied.context.get("duplicate", false))
					_show_toast("Compra ya procesada" if already_credited else "Compra verificada")
		MetaPlayResult.Status.FAILED:
			_show_toast("La compra no pudo completarse")
		MetaPlayResult.Status.CANCELLED:
			_show_toast("Compra cancelada")
		MetaPlayResult.Status.CANCELLED:
			_show_toast("Compra cancelada")
	_show_store()


func _show_promo() -> void:
	_begin_dialog("VIDEO PROMOCIONAL")
	_dialog_body.add_child(UI.label("Vista previa local del espacio promocional.\nLa URL externa sólo se abre por acción del usuario.", 21, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var video_icon: TextureRect = TextureRect.new()
	video_icon.texture = preload("res://addons/metaplay_kit/assets/ui/icon_video.png")
	video_icon.custom_minimum_size = Vector2(150.0, 150.0)
	video_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	video_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialog_body.add_child(video_icon)
	_dialog_body.add_child(UI.button("ABRIR PROMO", _open_promo_web_page, Vector2(260.0, 52.0)))
	_dialog_body.add_child(UI.button("CERRAR", _close_dialog, Vector2(220.0, 52.0)))


func _simulate_win() -> void:
	if _current_level_node != null and is_instance_valid(_current_level_node) and _current_level_node.has_method("level_win"):
		_current_level_node.call("level_win")
	else:
		level_win(_current_attempt_id, 1250, {"goal_reached": true})


func _simulate_lose() -> void:
	if _current_level_node != null and is_instance_valid(_current_level_node) and _current_level_node.has_method("level_lose"):
		_current_level_node.call("level_lose")
	else:
		level_lose(_current_attempt_id, 450, {"goal_reached": false})


func _show_win(payload: Dictionary) -> void:
	_present_terminal_result(payload)


func _show_lose(payload: Dictionary) -> void:
	_present_terminal_result(payload)


func _present_terminal_result(payload: Dictionary) -> void:
	_result_payload = payload.duplicate(true)
	var presentation: Dictionary = payload.get("presentation", {}) as Dictionary
	var view_data: Dictionary = presentation.duplicate(true)
	for key: Variant in payload.keys():
		view_data[key] = payload[key]
	_begin_dialog(str(view_data.get("title", "RESULTADO")))
	var result_panel: PanelContainer = ResultPanel.new() as PanelContainer
	result_panel.name = "LevelResultPanel"
	result_panel.connect("action_requested", _on_result_panel_action_requested)
	result_panel.call("present_result", view_data)
	_dialog_body.add_child(result_panel)


func _retry_current_level() -> void:
	TtpGuiApi.retry_level(_current_level_key)


func _next_level() -> void:
	var presentation: Dictionary = _result_payload.get("presentation", {}) as Dictionary
	var next_level: Dictionary = presentation.get("next_level", {}) as Dictionary
	if not next_level.is_empty():
		TtpGuiApi.request_level_load(next_level.get("key"))


func _reward_win() -> void:
	_on_result_panel_action_requested(_current_attempt_id, &"double_completion")


func _reward_lose() -> void:
	_on_result_panel_action_requested(_current_attempt_id, &"revive")


func _show_reward_wait(message: String, is_win: bool, attempt_id: String, action_id: StringName) -> void:
	_begin_dialog("RECOMPENSA")
	_dialog_body.add_child(UI.label(message, 26, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var progress: ProgressBar = ProgressBar.new()
	progress.name = "RewardProgress"
	progress.custom_minimum_size = Vector2(420.0, 28.0)
	progress.max_value = 1.0
	progress.value = 0.0
	progress.show_percentage = false
	_dialog_body.add_child(progress)
	var tween: Tween = create_tween()
	tween.tween_property(progress, "value", 1.0, 1.2)
	await tween.finished
	if is_win:
		TtpGuiApi.set_currency_balance(TtpGuiApi.get_currency_balance() + 50)
		_demo_action_claims["%s:%s" % [attempt_id, str(action_id)]] = true
		_show_toast("Monedas duplicadas")
		var updated_payload: Dictionary = _result_payload.duplicate(true)
		var updated_presentation: Dictionary = updated_payload.get("presentation", {}) as Dictionary
		var updated_actions: Array = updated_presentation.get("actions", []) as Array
		for index: int in range(updated_actions.size() - 1, -1, -1):
			var action: Dictionary = updated_actions[index] as Dictionary
			if StringName(str(action.get("id", ""))) == action_id:
				updated_actions.remove_at(index)
		updated_presentation["actions"] = updated_actions
		updated_payload["presentation"] = updated_presentation
		_present_terminal_result(updated_payload)
	else:
		_demo_action_claims["%s:%s" % [attempt_id, str(action_id)]] = true
		TtpGuiApi.revive_after_reward(attempt_id)


func _show_pause() -> void:
	get_tree().paused = true
	_begin_dialog("PAUSA")
	_dialog_body.add_child(UI.label("La simulación está pausada", 22, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var resume: Button = UI.button("CONTINUAR", _resume_game, Vector2(280.0, 60.0))
	resume.name = "ResumeButton"
	_dialog_body.add_child(resume)
	_dialog_body.add_child(UI.button("VOLVER AL INICIO", _pause_to_home, Vector2(280.0, 56.0)))


func _resume_game() -> void:
	get_tree().paused = false
	_close_dialog()


func _pause_to_home() -> void:
	get_tree().paused = false
	TtpGuiApi.request_home_screen()


func _begin_dialog(title_text: String) -> void:
	_clear_container(_dialog_body)
	_overlay.visible = true
	_overlay.modulate.a = 1.0
	var heading: Label = UI.label(title_text, 36, COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	heading.name = "DialogTitle"
	heading.theme_type_variation = "TitleLabel"
	_dialog_body.add_child(heading)
	_dialog_body.add_child(UI.h_separator())


func _close_dialog() -> void:
	if _overlay != null:
		_overlay.visible = false
	if get_tree().paused:
		get_tree().paused = false


func _clear_container(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_screen_requested(screen_name: String, payload: Dictionary) -> void:
	match screen_name:
		"home":
			show_home()
		"game":
			if not _initial_boot:
				_show_game(payload)
		"levels":
			_show_levels()
		"store":
			_show_store()
		"config":
			_show_config()
		"settings":
			_show_config()
		"win":
			_show_win(payload)
		"lose":
			_show_lose(payload)


func _on_loading_started(operation_id: int, level_data: Dictionary) -> void:
	_loading_operation_id = operation_id
	get_tree().paused = false
	if is_instance_valid(_current_level_node) and _current_level_node.has_method("stop_level"):
		_current_level_node.call("stop_level")
	_game_screen.visible = false
	_loading.load_level(str(level_data.get("scene_path", "")))
	_close_dialog()


func _on_loading_progress(operation_id: int, progress: float) -> void:
	if operation_id != _loading_operation_id:
		return
	_loading.update_progress(progress)


func _on_loading_completed(operation_id: int, level_data: Dictionary, resource: Resource) -> void:
	if operation_id != _loading_operation_id:
		return
	_loading_operation_id = 0
	if not show_level(level_data, resource):
		show_home()
		return
	_loading.load_finished()
	_loading.complete_loading()
	if _initial_boot:
		_initial_boot = false
		show_home()
	else:
		_show_game({"level_key": _current_level_key})


func _on_loading_result(result: MetaPlayResult) -> void:
	var result_context: Dictionary = result.context
	var level_data: Dictionary = result_context.get("level_data", {}) as Dictionary
	match result.status:
		MetaPlayResult.Status.COMPLETED:
			var resource: Resource = result_context.get("resource") as Resource
			_on_loading_completed(result.operation_id, level_data, resource)
		MetaPlayResult.Status.FAILED:
			_on_loading_failed(
				result.operation_id,
				level_data,
				str(result_context.get("message", "Level loading failed."))
			)
		MetaPlayResult.Status.CANCELLED:
			_on_loading_cancelled(result.operation_id, level_data)


func _on_loading_failed(operation_id: int, _level_data: Dictionary, _message: String) -> void:
	if operation_id != _loading_operation_id:
		return
	_loading_operation_id = 0
	show_home()


func _on_loading_cancelled(operation_id: int, _level_data: Dictionary) -> void:
	if operation_id != _loading_operation_id:
		return
	_loading_operation_id = 0
	show_home()


func _on_operation_rejected(message: String) -> void:
	_show_toast(message)


func _on_store_changed() -> void:
	if _overlay.visible and _dialog_body.get_node_or_null("StoreList") != null:
		_show_store()


func _update_coins(total: int) -> void:
	var text_value: String = "MONEDAS  %s" % TtpGuiApi.format_number(total)
	if _coin_label != null:
		_coin_label.text = text_value
	if _game_coin_label != null:
		_game_coin_label.text = text_value


func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: _toast.visible = false)


func _toast_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.05, 0.10, 0.94)
	style.border_color = COLOR_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
