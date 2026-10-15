extends Node

## Public façade compatible with the functional contract documented in
## interfaces/INT-85-TTP_GUI_API.md. Presentation stays in scene controllers;
## this singleton owns orchestration and delegates state invariants to the model.

signal modal_lose_retry_button_pressed(level_data: Dictionary)
signal modal_lose_use_life_pressed()
signal modal_lose_video_reward_showed(level_data: Dictionary)
signal modal_win_retry_button_pressed(level_data: Dictionary)
signal modal_win_load_next_level_pressed(level_data: Dictionary)
signal home_tap_to_play_pressed()
signal loading_started(level_data: Dictionary)
signal loading_completed()
signal level_selector_load_new_level_selected(level_data: Dictionary)
signal loading_exit_animation_completed()
signal store_game_update_item_loadded(item_key: Variant)
signal store_game_buy_item(item_key: Array)
signal store_currency_buy_coins(product_key: Variant)
signal modal_config_change_sfx_status()
signal modal_config_change_music_status()
signal modal_win_video_reward_showed(information: Array)
signal new_total_coins(total: int)
signal screen_requested(screen_name: String, payload: Dictionary)
signal operation_rejected(message: String)

enum TYPES_BTN_ITEM {
	BASIC = 0,
	EQUIP = 1,
	PHASE = 2,
}

var model: MetaPlayModel = MetaPlayModel.new()
var resource_batch: ResourceBatch = ResourceBatch.new()
var _loading_level: Dictionary = {}
var _loading_path: String = ""


func _ready() -> void:
	model.coins_changed.connect(_on_coins_changed)
	resource_batch.load_finished.connect(_on_batch_finished)
	resource_batch.load_failed.connect(_on_batch_failed)


func send_notification_ui(signal_name: String, parameter: Variant = null) -> void:
	if not has_signal(signal_name):
		operation_rejected.emit("Señal de interfaz desconocida: %s" % signal_name)
		return
	if parameter == null:
		# lint:ignore godot3_api -- compatibility entry point intentionally receives a runtime signal name.
		emit_signal(signal_name)
	else:
		# lint:ignore godot3_api -- compatibility entry point intentionally receives a runtime signal name.
		emit_signal(signal_name, parameter)


func set_levels(dictionary_levels: Dictionary) -> void:
	model.set_levels(dictionary_levels)


func set_game_configuration(config: Dictionary) -> void:
	model.set_configuration(config)


func set_store_currency(items: Dictionary) -> void:
	model.set_currency_items(items)


func set_store_game(dictionary_items: Dictionary) -> void:
	model.set_game_items(dictionary_items)


func set_list_value_items_store_game(list_coins: Dictionary) -> void:
	model.set_coin_values(list_coins)


func set_player_coins(value: int) -> void:
	model.set_coins(value)


func load_first_level_to_play() -> Dictionary:
	var level_key: Variant = model.get_next_level_to_play()
	var level: Dictionary = model.get_level(level_key)
	if not level.is_empty():
		load_level(level_key)
	return level


func load_level(level_key: Variant) -> void:
	var level: Dictionary = model.get_level(level_key)
	if level.is_empty():
		operation_rejected.emit("El nivel solicitado no existe.")
		return
	_loading_level = level
	_loading_level["key"] = level_key
	_loading_path = str(level.get("scene_path", ""))
	loading_started.emit(_loading_level.duplicate(true))
	if _loading_path.is_empty():
		call_deferred("_on_batch_finished")
		return
	resource_batch.add_resource_to_batch(_loading_path)
	resource_batch.start_loading(24)


func level_win(
		level_key: Variant,
		_new_data_level: Dictionary,
		quantity_stars: int,
		score: int,
		coins_earned: int,
		next_level_to_play: Variant
	) -> void:
	var result: Dictionary = model.complete_level(
		level_key,
		quantity_stars,
		score,
		coins_earned,
		next_level_to_play
	)
	if not bool(result.get("ok", false)):
		operation_rejected.emit(str(result.get("message", "No se pudo registrar la victoria.")))
		return
	screen_requested.emit("win", {
		"level_key": level_key,
		"stars": clampi(quantity_stars, 0, 3),
		"score": maxi(0, score),
		"coins": maxi(0, coins_earned),
		"next_level": next_level_to_play,
	})


func modal_win_retry_level(level_key: Variant) -> void:
	var level: Dictionary = model.get_level(level_key)
	if level.is_empty():
		return
	modal_win_retry_button_pressed.emit(level)
	load_level(level_key)


func modal_win_next_level(_current_level_key: Variant) -> void:
	var next_key: Variant = model.get_next_level_to_play()
	var level: Dictionary = model.get_level(next_key)
	if level.is_empty():
		return
	modal_win_load_next_level_pressed.emit(level)
	load_level(next_key)


func level_lose(level_key: Variant) -> void:
	screen_requested.emit("lose", {"level_key": level_key})


func modal_lose_retry_level(level_key: Variant) -> void:
	var level: Dictionary = model.get_level(level_key)
	if level.is_empty():
		return
	modal_lose_retry_button_pressed.emit(level)
	load_level(level_key)


func notify_modal_lose_video_reward(level_key: Variant) -> void:
	var level: Dictionary = model.get_level(level_key)
	if level.is_empty():
		return
	modal_lose_video_reward_showed.emit(level)
	screen_requested.emit("game", {"level_key": level_key, "revived": true})


func notify_modal_lose_use_life() -> void:
	modal_lose_use_life_pressed.emit()


func notify_modal_win_video_reward(_level_key: Variant, extra_coins: int) -> void:
	model.add_coins(extra_coins)
	var next_key: Variant = model.get_next_level_to_play()
	var next_level: Dictionary = model.get_level(next_key)
	modal_win_video_reward_showed.emit([next_level, model.coins])


func select_pause() -> void:
	show_home()


func get_resource_loaded(path: String) -> Resource:
	return resource_batch.get_resource(path)


func show_home() -> void:
	screen_requested.emit("home", {})


func notify_change_sfx_status() -> void:
	model.toggle_sfx()
	modal_config_change_sfx_status.emit()


func notify_change_music_status() -> void:
	model.toggle_music()
	modal_config_change_music_status.emit()


func get_next_level_to_play() -> Variant:
	return model.get_next_level_to_play()


func tap_to_play_pressed() -> void:
	home_tap_to_play_pressed.emit()
	var level_key: Variant = model.get_next_level_to_play()
	screen_requested.emit("game", {"level_key": level_key})


func change_level(new_level: Variant) -> void:
	var level: Dictionary = model.get_level(new_level)
	if level.is_empty() or not bool(level.get("enabled", false)):
		operation_rejected.emit("Ese nivel todavía está bloqueado.")
		return
	level_selector_load_new_level_selected.emit(level)
	load_level(new_level)


func show_level_selector_pressed(status: bool) -> void:
	screen_requested.emit("levels" if status else "home", {})


func show_panel_store(status: bool) -> void:
	screen_requested.emit("store" if status else "home", {})


func show_panel_config(status: bool) -> void:
	screen_requested.emit("config" if status else "home", {})


func get_item_in_store_game_dictionary(item_key: Array) -> Dictionary:
	return model.get_store_item(item_key)


func get_total_players_coins() -> int:
	return model.coins


func get_type_buttons() -> Dictionary:
	return model.get_type_buttons()


func update_item_game_loaded(item_key: Array) -> void:
	var result: Dictionary = model.equip_item(item_key)
	if bool(result.get("ok", false)):
		store_game_update_item_loadded.emit(item_key.duplicate())
	else:
		operation_rejected.emit(str(result.get("message", "No se pudo equipar.")))


func update_item_sold_in_store_game(item_key: Array) -> void:
	var result: Dictionary = model.purchase_game_item(item_key)
	if bool(result.get("ok", false)):
		store_game_buy_item.emit(item_key.duplicate())
	else:
		operation_rejected.emit(str(result.get("message", "No se pudo comprar.")))


func get_level(level_key: Variant) -> Dictionary:
	return model.get_level(level_key)


func add_coin_purchased(item: Variant) -> void:
	var result: Dictionary = model.add_currency_product(item)
	if bool(result.get("ok", false)):
		store_currency_buy_coins.emit(item)
	else:
		operation_rejected.emit(str(result.get("message", "No se pudo acreditar la compra.")))


func manage_tap_background() -> void:
	pass


func _on_coins_changed(total: int) -> void:
	new_total_coins.emit(total)


func _on_batch_finished() -> void:
	# The stage must instantiate the loaded scene before presenting gameplay.
	loading_completed.emit()
	call_deferred("_emit_loading_exit")


func _emit_loading_exit() -> void:
	loading_exit_animation_completed.emit()


func _on_batch_failed(_path: String, message: String) -> void:
	operation_rejected.emit(message)
	screen_requested.emit("home", {})
