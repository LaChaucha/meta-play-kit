extends Node

## Public facade for host games. Callers configure data, issue game actions,
## query read-only snapshots, and subscribe to events without accessing internals.

const LEVEL_LOAD_BUSY_MESSAGE: String = "A level load is already in progress."

signal level_load_started(operation_id: int, level_data: Dictionary)
signal level_load_completed(operation_id: int, level_data: Dictionary, resource: Resource)
signal level_load_failed(operation_id: int, level_data: Dictionary, message: String)
signal level_load_cancelled(operation_id: int, level_data: Dictionary)
signal level_load_exit_animation_completed(operation_id: int)
signal loading_progress_changed(operation_id: int, progress: float)
signal navigation_requested(screen_name: String, payload: Dictionary)
signal action_rejected(message: String)
signal currency_balance_changed(total: int)
signal play_requested()
signal level_selected(level_data: Dictionary)
signal level_retry_requested(level_data: Dictionary)
signal next_level_load_requested(level_data: Dictionary)
signal life_use_requested()
signal revive_reward_claimed(level_data: Dictionary)
signal reward_doubling_claimed(next_level: Dictionary, currency_balance: int)
signal sfx_setting_changed(enabled: bool)
signal music_setting_changed(enabled: bool)
signal item_purchased(item_path: Array)
signal item_equipped(item_path: Array)
signal currency_product_credited(product_key: Variant)
signal store_catalog_changed()

# Legacy signals retained for existing integrations. New consumers should use
# the semantic signals above.
signal modal_lose_retry_button_pressed(level_data: Dictionary)
signal modal_lose_use_life_pressed()
signal modal_lose_video_reward_showed(level_data: Dictionary)
signal modal_win_retry_button_pressed(level_data: Dictionary)
signal modal_win_load_next_level_pressed(level_data: Dictionary)
signal home_tap_to_play_pressed()
signal loading_started(operation_id: int, level_data: Dictionary)
signal loading_completed(operation_id: int, level_data: Dictionary, resource: Resource)
signal level_selector_load_new_level_selected(level_data: Dictionary)
signal loading_exit_animation_completed(operation_id: int)
signal store_game_update_item_loadded(item_key: Variant)
signal store_game_buy_item(item_key: Array)
signal store_currency_buy_coins(product_key: Variant)
signal modal_config_change_sfx_status()
signal modal_config_change_music_status()
signal modal_win_video_reward_showed(information: Array)
signal new_total_coins(total: int)
signal screen_requested(screen_name: String, payload: Dictionary)
signal operation_rejected(message: String)

enum ItemType {
	BASIC = 0,
	EQUIP = 1,
	PHASE = 2,
}

# Deprecated name retained for source compatibility.
enum TYPES_BTN_ITEM {
	BASIC = 0,
	EQUIP = 1,
	PHASE = 2,
}

var _model: MetaPlayModel = MetaPlayModel.new()
var _resource_batch: ResourceBatch = ResourceBatch.new()
var _loading_level: Dictionary = {}
var _loading_path: String = ""
var _load_request_active: bool = false
var _load_terminal_emitting: bool = false
var _next_load_operation_id: int = 0
var _active_load_operation_id: int = 0


func _ready() -> void:
	_model.coins_changed.connect(_on_coins_changed)
	_model.store_changed.connect(_on_store_changed)
	_resource_batch.load_finished.connect(_on_batch_finished)
	_resource_batch.load_failed.connect(_on_batch_failed)
	_resource_batch.stage_updated.connect(_on_loading_progress)


# Configuration commands.
func configure_levels(levels: Dictionary) -> void:
	_model.set_levels(levels)


func configure_settings(settings: Dictionary) -> void:
	_model.set_configuration(settings)


func configure_currency_products(products: Dictionary) -> void:
	_model.set_currency_items(products)


func configure_items(items: Dictionary) -> void:
	_model.set_game_items(items)


func configure_currency_rewards(rewards: Dictionary) -> void:
	_model.set_coin_values(rewards)


func set_currency_balance(amount: int) -> void:
	_model.set_coins(amount)


# Queries return copies so consumers cannot mutate kit-owned state accidentally.
func get_level(level_key: Variant) -> Dictionary:
	return _model.get_level(level_key)


func get_levels() -> Dictionary:
	return _model.levels.duplicate(true)


func get_enabled_level_keys() -> Array:
	return _model.get_enabled_level_keys().duplicate()


func get_next_available_level() -> Variant:
	return _model.get_next_level_to_play()


func get_settings() -> Dictionary:
	return _model.configuration.duplicate(true)


func get_currency_products() -> Dictionary:
	return _model.currency_items.duplicate(true)


func get_items() -> Dictionary:
	return _model.game_items.duplicate(true)


func get_item(item_path: Array) -> Dictionary:
	return _model.get_store_item(item_path)


func get_currency_balance() -> int:
	return _model.coins


func get_item_type_values() -> Dictionary:
	return _model.get_type_buttons()


func format_number(value: Variant) -> String:
	return _model.format_number(value)


func is_loading() -> bool:
	return _load_request_active


func get_loaded_resource(path: String) -> Resource:
	return _resource_batch.get_resource(path)


# Level and progression actions.
func request_initial_level_load() -> Dictionary:
	var level_key: Variant = get_next_available_level()
	var level: Dictionary = get_level(level_key)
	if not level.is_empty():
		request_level_load(level_key)
	return level


func request_level_load(level_key: Variant) -> bool:
	if _load_request_active or _load_terminal_emitting:
		_reject(LEVEL_LOAD_BUSY_MESSAGE)
		return false
	var level: Dictionary = get_level(level_key)
	if level.is_empty():
		_reject("The requested level does not exist.")
		return false
	if not bool(level.get("enabled", false)):
		_reject("The requested level is locked or unavailable.")
		return false
	var scene_path: String = str(level.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		_reject("The requested level does not have a scene path.")
		return false
	_loading_level = level
	_loading_level["key"] = level_key
	_loading_path = scene_path
	_next_load_operation_id += 1
	_active_load_operation_id = _next_load_operation_id
	_load_request_active = true
	var level_data: Dictionary = _loading_level.duplicate(true)
	level_load_started.emit(_active_load_operation_id, level_data)
	loading_started.emit(_active_load_operation_id, level_data)
	_resource_batch.add_resource_to_batch(_loading_path)
	_resource_batch.start_loading(24)
	return true


func complete_level(
		level_key: Variant,
		stars: int,
		score: int,
		reward_currency: int,
		next_level_key: Variant = null
	) -> void:
	var result: Dictionary = _model.complete_level(
		level_key, stars, score, reward_currency, next_level_key
	)
	if not bool(result.get("ok", false)):
		_reject(str(result.get("message", "Could not record level completion.")))
		return
	_emit_navigation("win", {
		"level_key": level_key,
		"stars": clampi(stars, 0, 3),
		"score": maxi(0, score),
		"coins": maxi(0, reward_currency),
		"next_level": next_level_key,
	})


func report_level_loss(level_key: Variant) -> void:
	_emit_navigation("lose", {"level_key": level_key})


func retry_level(level_key: Variant) -> void:
	var level: Dictionary = get_level(level_key)
	if level.is_empty():
		return
	if not request_level_load(level_key):
		return
	level_retry_requested.emit(level)


func load_next_level() -> void:
	var next_key: Variant = get_next_available_level()
	var level: Dictionary = get_level(next_key)
	if level.is_empty():
		return
	if not request_level_load(next_key):
		return
	next_level_load_requested.emit(level)
	modal_win_load_next_level_pressed.emit(level)


func revive_after_reward(level_key: Variant) -> void:
	var level: Dictionary = get_level(level_key)
	if level.is_empty():
		return
	revive_reward_claimed.emit(level)
	modal_lose_video_reward_showed.emit(level)
	_emit_navigation("game", {"level_key": level_key, "revived": true})


func claim_reward_doubling(extra_currency: int) -> void:
	_model.add_coins(extra_currency)
	var next_level: Dictionary = get_level(get_next_available_level())
	reward_doubling_claimed.emit(next_level, _model.coins)
	modal_win_video_reward_showed.emit([next_level, _model.coins])


func use_life() -> void:
	life_use_requested.emit()
	modal_lose_use_life_pressed.emit()


# Navigation and settings actions.
func request_home_screen() -> void:
	_request_screen("home")


func request_level_selection_screen() -> void:
	_request_screen("levels")


func request_store_screen() -> void:
	_request_screen("store")


func request_settings_screen() -> void:
	_request_screen("settings")


func start_or_resume_game() -> void:
	var level_key: Variant = get_next_available_level()
	if level_key == null:
		return
	if not request_level_load(level_key):
		return
	play_requested.emit()
	home_tap_to_play_pressed.emit()


func select_level(level_key: Variant) -> void:
	var level: Dictionary = get_level(level_key)
	if level.is_empty() or not bool(level.get("enabled", false)):
		_reject("The selected level is locked or unavailable.")
		return
	if not request_level_load(level_key):
		return
	level_selected.emit(level)
	level_selector_load_new_level_selected.emit(level)


func toggle_sfx() -> void:
	var enabled: bool = _model.toggle_sfx()
	sfx_setting_changed.emit(enabled)
	modal_config_change_sfx_status.emit()


func toggle_music() -> void:
	var enabled: bool = _model.toggle_music()
	music_setting_changed.emit(enabled)
	modal_config_change_music_status.emit()


func purchase_item(item_path: Array) -> void:
	var result: Dictionary = _model.purchase_game_item(item_path)
	if bool(result.get("ok", false)):
		var path_copy: Array = item_path.duplicate(true)
		item_purchased.emit(path_copy)
		store_game_buy_item.emit(path_copy)
	else:
		_reject(str(result.get("message", "Could not purchase item.")))


func equip_item(item_path: Array) -> void:
	var result: Dictionary = _model.equip_item(item_path)
	if bool(result.get("ok", false)):
		var path_copy: Array = item_path.duplicate(true)
		item_equipped.emit(path_copy)
		store_game_update_item_loadded.emit(path_copy)
	else:
		_reject(str(result.get("message", "Could not equip item.")))


func credit_currency_product(product_key: Variant) -> void:
	var result: Dictionary = _model.add_currency_product(product_key)
	if bool(result.get("ok", false)):
		currency_product_credited.emit(product_key)
		store_currency_buy_coins.emit(product_key)
	else:
		_reject(str(result.get("message", "Could not credit currency product.")))


func _request_screen(screen_name: String) -> void:
	_emit_navigation(screen_name, {})


func _emit_navigation(screen_name: String, payload: Dictionary) -> void:
	var safe_payload: Dictionary = payload.duplicate(true)
	navigation_requested.emit(screen_name, safe_payload)
	screen_requested.emit(screen_name, safe_payload)


func _reject(message: String) -> void:
	action_rejected.emit(message)
	operation_rejected.emit(message)


func _on_coins_changed(total: int) -> void:
	currency_balance_changed.emit(total)
	new_total_coins.emit(total)


func _on_store_changed() -> void:
	store_catalog_changed.emit()


func _on_loading_progress(progress: float) -> void:
	if _load_request_active:
		loading_progress_changed.emit(_active_load_operation_id, progress)


func _on_batch_finished() -> void:
	if not _load_request_active:
		return
	var operation_id: int = _active_load_operation_id
	var level_data: Dictionary = _loading_level.duplicate(true)
	var resource: Resource = _resource_batch.peek_resource(_loading_path)
	if resource == null:
		_on_batch_failed(_loading_path, "The loaded level resource is unavailable.")
		return
	_load_request_active = false
	_active_load_operation_id = 0
	_load_terminal_emitting = true
	level_load_completed.emit(operation_id, level_data, resource)
	loading_completed.emit(operation_id, level_data, resource)
	_load_terminal_emitting = false
	call_deferred("_emit_loading_exit", operation_id)


func _emit_loading_exit(operation_id: int) -> void:
	level_load_exit_animation_completed.emit(operation_id)
	loading_exit_animation_completed.emit(operation_id)


func _on_batch_failed(_path: String, message: String) -> void:
	if not _load_request_active:
		return
	var operation_id: int = _active_load_operation_id
	var level_data: Dictionary = _loading_level.duplicate(true)
	_load_request_active = false
	_active_load_operation_id = 0
	_load_terminal_emitting = true
	level_load_failed.emit(operation_id, level_data, message)
	_load_terminal_emitting = false
	_reject(message)
	_request_screen("home")


# Deprecated compatibility wrappers for the original TtpGuiApi names.
func set_levels(value: Dictionary) -> void:
	configure_levels(value)


func set_game_configuration(value: Dictionary) -> void:
	configure_settings(value)


func set_store_currency(value: Dictionary) -> void:
	configure_currency_products(value)


func set_store_game(value: Dictionary) -> void:
	configure_items(value)


func set_list_value_items_store_game(value: Dictionary) -> void:
	configure_currency_rewards(value)


func set_player_coins(value: int) -> void:
	set_currency_balance(value)


func load_first_level_to_play() -> Dictionary:
	return request_initial_level_load()


func load_level(level_key: Variant) -> void:
	request_level_load(level_key)


func level_win(level_key: Variant, _data: Dictionary, stars: int, score: int, coins: int, next_key: Variant) -> void:
	complete_level(level_key, stars, score, coins, next_key)


func level_lose(level_key: Variant) -> void:
	report_level_loss(level_key)


func modal_win_retry_level(level_key: Variant) -> void:
	var level: Dictionary = get_level(level_key)
	if level.is_empty():
		return
	if not request_level_load(level_key):
		return
	level_retry_requested.emit(level)
	modal_win_retry_button_pressed.emit(level)


func modal_lose_retry_level(level_key: Variant) -> void:
	var level: Dictionary = get_level(level_key)
	if level.is_empty():
		return
	if not request_level_load(level_key):
		return
	level_retry_requested.emit(level)
	modal_lose_retry_button_pressed.emit(level)


func modal_win_next_level(_current_level_key: Variant) -> void:
	load_next_level()


func notify_modal_lose_video_reward(level_key: Variant) -> void:
	revive_after_reward(level_key)


func notify_modal_lose_use_life() -> void:
	use_life()


func notify_modal_win_video_reward(_level_key: Variant, extra_coins: int) -> void:
	claim_reward_doubling(extra_coins)


func select_pause() -> void:
	request_home_screen()


func get_resource_loaded(path: String) -> Resource:
	return get_loaded_resource(path)


func show_home() -> void:
	request_home_screen()


func notify_change_sfx_status() -> void:
	toggle_sfx()


func notify_change_music_status() -> void:
	toggle_music()


func get_next_level_to_play() -> Variant:
	return get_next_available_level()


func tap_to_play_pressed() -> void:
	start_or_resume_game()


func change_level(level_key: Variant) -> void:
	select_level(level_key)


func show_level_selector_pressed(status: bool) -> void:
	_request_screen("levels" if status else "home")


func show_panel_store(status: bool) -> void:
	_request_screen("store" if status else "home")


func show_panel_config(status: bool) -> void:
	_request_screen("config" if status else "home")


func get_item_in_store_game_dictionary(item_path: Array) -> Dictionary:
	return get_item(item_path)


func get_total_players_coins() -> int:
	return get_currency_balance()


func get_type_buttons() -> Dictionary:
	return get_item_type_values()


func update_item_game_loaded(item_path: Array) -> void:
	equip_item(item_path)


func update_item_sold_in_store_game(item_path: Array) -> void:
	purchase_item(item_path)


func add_coin_purchased(product_key: Variant) -> void:
	credit_currency_product(product_key)


func send_notification_ui(signal_name: String, parameter: Variant = null) -> void:
	if not has_signal(signal_name):
		_reject("Unknown UI signal: %s" % signal_name)
		return
	if parameter == null:
		# lint:ignore godot3_api -- deprecated compatibility method accepts a dynamic signal name.
		emit_signal(signal_name)
	else:
		# lint:ignore godot3_api -- deprecated compatibility method accepts a dynamic signal name.
		emit_signal(signal_name, parameter)


func manage_tap_background() -> void:
	pass
