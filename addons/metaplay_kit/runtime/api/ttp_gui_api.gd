extends Node

## Public facade for host games. Callers configure data, issue game actions,
## query read-only snapshots, and subscribe to events without accessing internals.

const LEVEL_LOAD_BUSY_MESSAGE: String = "A level load is already in progress."
const RESULT_CODE_API_UNAVAILABLE: StringName = &"api.unavailable"
const RESULT_CODE_LEVEL_NOT_FOUND: StringName = &"level.not_found"
const RESULT_CODE_LEVEL_LOCKED: StringName = &"level.locked"
const RESULT_CODE_LEVEL_SCENE_PATH_MISSING: StringName = &"level.scene_path_missing"
const RESULT_CODE_LEVEL_LOAD_IN_PROGRESS: StringName = &"level.load_in_progress"
const RESULT_CODE_LEVEL_LOAD_FAILED: StringName = &"level.load_failed"
const RESULT_CODE_NO_AVAILABLE_LEVEL: StringName = &"level.no_available_level"
const RESULT_CODE_PROGRESSION_REJECTED: StringName = &"progression.rejected"
const RESULT_CODE_STORE_ITEM_NOT_FOUND: StringName = &"store.item_not_found"
const RESULT_CODE_STORE_ITEM_ALREADY_OWNED: StringName = &"store.item_already_owned"
const RESULT_CODE_STORE_ITEM_NOT_OWNED: StringName = &"store.item_not_owned"
const RESULT_CODE_STORE_ITEM_NOT_EQUIPPABLE: StringName = &"store.item_not_equippable"
const RESULT_CODE_WALLET_INSUFFICIENT_FUNDS: StringName = &"wallet.insufficient_funds"
const RESULT_CODE_CURRENCY_PRODUCT_NOT_FOUND: StringName = &"currency.product_not_found"

signal level_load_started(operation_id: int, level_data: Dictionary)
signal level_load_completed(operation_id: int, level_data: Dictionary, resource: Resource)
signal level_load_failed(operation_id: int, level_data: Dictionary, message: String)
signal level_load_cancelled(operation_id: int, level_data: Dictionary)
signal level_load_result(result: MetaPlayResult)
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
signal level_attempt_started(attempt_id: String, level_key: Variant)
signal level_attempt_completed(attempt_id: String, result: Dictionary)
signal reward_claim_completed(result: MetaPlayResult)

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
var _load_start_signals_emitting: bool = false
var _is_shutting_down: bool = false
var _next_load_operation_id: int = 0
var _active_load_operation_id: int = 0
var _active_load_progress: float = 0.0
var _active_load_progress_emitted: bool = false
var _pending_cancelled_operation_id: int = 0
var _pending_cancelled_level_data: Dictionary = {}
var _pending_cancelled_scene_path: String = ""


func _ready() -> void:
	_model.coins_changed.connect(_on_coins_changed)
	_model.store_changed.connect(_on_store_changed)
	_resource_batch.load_finished.connect(_on_batch_finished)
	_resource_batch.load_failed.connect(_on_batch_failed)
	_resource_batch.stage_updated.connect(_on_loading_progress)


func _enter_tree() -> void:
	_is_shutting_down = false


func _exit_tree() -> void:
	_is_shutting_down = true
	if _load_request_active:
		_finish_active_load_as_cancelled()
	else:
		_resource_batch.close()


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


func configure_completion_rewards(rewards: Dictionary, cooldown_seconds: int) -> MetaPlayResult:
	var result: Dictionary = _model.configure_completion_rewards(rewards, cooldown_seconds)
	if not bool(result.get("ok", false)):
		return _reject_with_result(StringName(str(result.get("code", "reward.configuration_invalid"))), str(result.get("message", "Invalid completion reward configuration.")), result.get("context", {}) as Dictionary)
	return MetaPlayResult.completed()


func configure_optional_rewards(rewards: Dictionary) -> MetaPlayResult:
	var result: Dictionary = _model.configure_optional_rewards(rewards)
	if not bool(result.get("ok", false)):
		return _reject_with_result(StringName(str(result.get("code", "reward.configuration_invalid"))), str(result.get("message", "Invalid optional reward configuration.")), result.get("context", {}) as Dictionary)
	return MetaPlayResult.completed()


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
	var result: MetaPlayResult = request_level_load_result(level_key)
	return result.status == MetaPlayResult.Status.ACCEPTED


func request_level_load_result(level_key: Variant) -> MetaPlayResult:
	return _start_level_load_operation(level_key)


func _start_level_load_operation(level_key: Variant) -> MetaPlayResult:
	if _is_shutting_down:
		return MetaPlayResult.rejected(RESULT_CODE_API_UNAVAILABLE, {"level_key": level_key})
	if _load_request_active or _load_terminal_emitting:
		return _reject_with_result(
			RESULT_CODE_LEVEL_LOAD_IN_PROGRESS,
			LEVEL_LOAD_BUSY_MESSAGE,
			{"level_key": level_key}
		)
	var level: Dictionary = get_level(level_key)
	if level.is_empty():
		return _reject_with_result(
			RESULT_CODE_LEVEL_NOT_FOUND,
			"The requested level does not exist.",
			{"level_key": level_key}
		)
	if not bool(level.get("enabled", false)):
		return _reject_with_result(
			RESULT_CODE_LEVEL_LOCKED,
			"The requested level is locked or unavailable.",
			{"level_key": level_key}
		)
	var scene_path: String = str(level.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		return _reject_with_result(
			RESULT_CODE_LEVEL_SCENE_PATH_MISSING,
			"The requested level does not have a scene path.",
			{"level_key": level_key}
		)
	_loading_level = level
	_loading_level["key"] = level_key
	_loading_path = scene_path
	_next_load_operation_id += 1
	_active_load_operation_id = _next_load_operation_id
	_active_load_progress = 0.0
	_active_load_progress_emitted = false
	_load_request_active = true
	var level_data: Dictionary = _loading_level.duplicate(true)
	var operation_id: int = _active_load_operation_id
	var accepted_result: MetaPlayResult = MetaPlayResult.accepted(
		operation_id, {"level_key": level_key, "scene_path": scene_path}
	)
	_load_start_signals_emitting = true
	level_load_started.emit(operation_id, level_data)
	loading_started.emit(operation_id, level_data)
	_load_start_signals_emitting = false
	if _pending_cancelled_operation_id == operation_id:
		_emit_pending_load_cancelled()
		return accepted_result
	if not _load_request_active or _active_load_operation_id != operation_id or _is_shutting_down:
		return accepted_result
	_on_loading_progress(0.0)
	if not _load_request_active or _active_load_operation_id != operation_id or _is_shutting_down:
		return accepted_result
	_resource_batch.add_resource_to_batch(_loading_path)
	_resource_batch.start_loading(24)
	return accepted_result


func cancel_level_load(operation_id: int) -> bool:
	if _is_shutting_down or not _load_request_active or operation_id != _active_load_operation_id:
		return false
	_finish_active_load_as_cancelled()
	return true


func _finish_active_load_as_cancelled() -> void:
	if not _load_request_active:
		return
	var operation_id: int = _active_load_operation_id
	var level_data: Dictionary = _loading_level.duplicate(true)
	var scene_path: String = _loading_path
	_load_request_active = false
	_active_load_operation_id = 0
	_load_terminal_emitting = true
	_loading_level.clear()
	_loading_path = ""
	_resource_batch.close()
	if _load_start_signals_emitting:
		_pending_cancelled_operation_id = operation_id
		_pending_cancelled_level_data = level_data
		_pending_cancelled_scene_path = scene_path
		return
	level_load_result.emit(MetaPlayResult.cancelled(operation_id, {
		"level_key": level_data.get("key"),
		"level_data": level_data,
		"scene_path": scene_path,
	}))
	level_load_cancelled.emit(operation_id, level_data)
	_load_terminal_emitting = false


func _emit_pending_load_cancelled() -> void:
	var operation_id: int = _pending_cancelled_operation_id
	var level_data: Dictionary = _pending_cancelled_level_data.duplicate(true)
	var scene_path: String = _pending_cancelled_scene_path
	_pending_cancelled_operation_id = 0
	_pending_cancelled_level_data.clear()
	_pending_cancelled_scene_path = ""
	level_load_result.emit(MetaPlayResult.cancelled(operation_id, {
		"level_key": level_data.get("key"),
		"level_data": level_data,
		"scene_path": scene_path,
	}))
	level_load_cancelled.emit(operation_id, level_data)
	_load_terminal_emitting = false


func begin_level_attempt(level_key: Variant) -> MetaPlayResult:
	var outcome: Dictionary = _model.begin_attempt(level_key)
	if not bool(outcome.get("ok", false)):
		return _reject_with_result(StringName(str(outcome.get("code", "attempt.rejected"))), str(outcome.get("message", "Could not begin level attempt.")), {"level_key": level_key})
	var attempt_id: String = str(outcome.get("attempt_id", ""))
	level_attempt_started.emit(attempt_id, level_key)
	return MetaPlayResult.completed(0, {"attempt_id": attempt_id, "level_key": level_key})


func complete_level(
		attempt_id: String,
		stars: int,
		score: int,
		next_level_key: Variant = null
	) -> MetaPlayResult:
	var result: Dictionary = _model.record_attempt_result(attempt_id, stars, score, next_level_key)
	if not bool(result.get("ok", false)):
		var failure_code: StringName = StringName(
			str(result.get("code", RESULT_CODE_PROGRESSION_REJECTED))
		)
		return _reject_with_result(
			failure_code,
			str(result.get("message", "Could not record level completion.")),
			{"attempt_id": attempt_id}
		)
	if bool(result.get("duplicate", false)):
		var prior_reward: Dictionary = _model.reward_claims.get("base:%s" % attempt_id, {}) as Dictionary
		result["reward_granted"] = bool(prior_reward.get("granted", false))
		result["reward_amount"] = int(prior_reward.get("amount", 0))
		result["coins"] = int(prior_reward.get("coins", _model.coins))
		return MetaPlayResult.completed(0, result)
	var level_key: Variant = result.get("level_key")
	var reward: Dictionary = _model.claim_base_reward(attempt_id, int(Time.get_unix_time_from_system()))
	if bool(reward.get("ok", false)):
		reward_claim_completed.emit(MetaPlayResult.completed(0, reward))
	result["reward_granted"] = bool(reward.get("granted", false))
	result["reward_amount"] = int(reward.get("amount", 0))
	result["reward_code"] = StringName(str(reward.get("code", "")))
	result["coins"] = _model.coins
	level_attempt_completed.emit(attempt_id, result.duplicate(true))
	_emit_navigation("win", {
		"attempt_id": attempt_id,
		"level_key": level_key,
		"stars": int(result.get("stars", 0)),
		"score": int(result.get("score", 0)),
		"coins": int(result.get("reward_amount", 0)),
		"currency_balance": _model.coins,
		"next_level": next_level_key,
	})
	return MetaPlayResult.completed(0, {
		"attempt_id": attempt_id,
		"level_key": level_key,
		"stars": int(result.get("stars", 0)),
		"score": int(result.get("score", 0)),
		"currency_balance": int(result.get("coins", _model.coins)),
		"reward_granted": bool(result.get("reward_granted", false)),
		"reward_amount": int(result.get("reward_amount", 0)),
		"next_level_key": next_level_key,
		"duplicate": bool(result.get("duplicate", false)),
	})


func claim_completion_reward(attempt_id: String) -> MetaPlayResult:
	var result: Dictionary = _model.claim_base_reward(attempt_id, int(Time.get_unix_time_from_system()))
	return _finish_reward_claim(result, "Could not claim completion reward.")


func claim_optional_reward(attempt_id: String, claim_id: String, reward_type: StringName) -> MetaPlayResult:
	var result: Dictionary = _model.claim_optional_reward(attempt_id, claim_id, reward_type)
	return _finish_reward_claim(result, "Could not claim optional reward.")


func _finish_reward_claim(outcome: Dictionary, fallback_message: String) -> MetaPlayResult:
	if not bool(outcome.get("ok", false)):
		return _reject_with_result(StringName(str(outcome.get("code", "reward.rejected"))), str(outcome.get("message", fallback_message)), outcome.get("context", {}) as Dictionary)
	var response: MetaPlayResult = MetaPlayResult.completed(0, outcome)
	if not bool(outcome.get("duplicate", false)):
		reward_claim_completed.emit(response)
	return response


func export_session_state() -> Dictionary:
	return {"schema_version": 1, "levels": _model.levels.duplicate(true), "currency_balance": _model.coins, "completion_state": _model.export_completion_state()}


func restore_session_state(snapshot: Dictionary) -> MetaPlayResult:
	if int(snapshot.get("schema_version", -1)) != 1:
		return _reject_with_result(&"session.snapshot_unsupported", "The session snapshot version is unsupported.")
	var raw_levels: Variant = snapshot.get("levels")
	var raw_completion: Variant = snapshot.get("completion_state")
	var balance: int = int(snapshot.get("currency_balance", -1))
	if not raw_levels is Dictionary or not raw_completion is Dictionary or balance < 0:
		return _reject_with_result(&"session.snapshot_invalid", "The session snapshot is incomplete or invalid.")
	for level_key: Variant in (raw_levels as Dictionary).keys():
		if not (raw_levels as Dictionary)[level_key] is Dictionary:
			return _reject_with_result(&"session.snapshot_invalid", "The session snapshot contains invalid level data.", {"level_key": level_key})
	var previous_levels: Dictionary = _model.levels.duplicate(true)
	_model.levels = (raw_levels as Dictionary).duplicate(true)
	if not _model.restore_completion_state(raw_completion as Dictionary):
		_model.levels = previous_levels
		return _reject_with_result(&"session.snapshot_invalid", "The session completion state is invalid.")
	_model.set_coins(balance)
	_model.levels_changed.emit()
	return MetaPlayResult.completed(0, {"schema_version": 1})


func report_level_loss(attempt_id: String) -> MetaPlayResult:
	if not _model.mark_attempt_lost(attempt_id):
		return _reject_with_result(&"attempt.stale", "The gameplay attempt cannot report a loss.", {"attempt_id": attempt_id})
	var attempt: Dictionary = _model.attempts.get(attempt_id, {}) as Dictionary
	var level_key: Variant = attempt.get("level_key")
	_emit_navigation("lose", {"attempt_id": attempt_id, "level_key": level_key})
	return MetaPlayResult.completed(0, {"attempt_id": attempt_id, "level_key": level_key})


func retry_level(level_key: Variant) -> MetaPlayResult:
	var result: MetaPlayResult = _start_level_load_operation(level_key)
	if result.status != MetaPlayResult.Status.ACCEPTED:
		return result
	var level: Dictionary = get_level(level_key)
	level_retry_requested.emit(level)
	return result


func load_next_level() -> MetaPlayResult:
	var next_key: Variant = get_next_available_level()
	if next_key == null:
		return _reject_with_result(
			RESULT_CODE_NO_AVAILABLE_LEVEL,
			"No level is available to advance to."
		)
	var result: MetaPlayResult = _start_level_load_operation(next_key)
	if result.status != MetaPlayResult.Status.ACCEPTED:
		return result
	var level: Dictionary = get_level(next_key)
	next_level_load_requested.emit(level)
	modal_win_load_next_level_pressed.emit(level)
	return result


func revive_after_reward(attempt_id: String) -> MetaPlayResult:
	if not _model.revive_attempt(attempt_id):
		return _reject_with_result(&"attempt.stale", "The gameplay attempt cannot be revived.", {"attempt_id": attempt_id})
	var attempt: Dictionary = _model.attempts.get(attempt_id, {}) as Dictionary
	var level: Dictionary = get_level(attempt.get("level_key"))
	revive_reward_claimed.emit(level)
	modal_lose_video_reward_showed.emit(level)
	_emit_navigation("game", {"attempt_id": attempt_id, "level_key": attempt.get("level_key"), "revived": true})
	return MetaPlayResult.completed(0, {"attempt_id": attempt_id, "revived": true})


func claim_reward_doubling(attempt_id: String, claim_id: String) -> MetaPlayResult:
	var claim_result: MetaPlayResult = claim_optional_reward(attempt_id, claim_id, &"double_completion")
	if claim_result.status != MetaPlayResult.Status.COMPLETED:
		return claim_result
	if bool(claim_result.context.get("duplicate", false)):
		return claim_result
	var next_level: Dictionary = get_level(get_next_available_level())
	reward_doubling_claimed.emit(next_level, _model.coins)
	modal_win_video_reward_showed.emit([next_level, _model.coins])
	return claim_result


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


func start_or_resume_game() -> MetaPlayResult:
	var level_key: Variant = get_next_available_level()
	if level_key == null:
		return _reject_with_result(
			RESULT_CODE_NO_AVAILABLE_LEVEL,
			"No level is available to start or resume."
		)
	var result: MetaPlayResult = _start_level_load_operation(level_key)
	if result.status != MetaPlayResult.Status.ACCEPTED:
		return result
	play_requested.emit()
	home_tap_to_play_pressed.emit()
	return result


func select_level(level_key: Variant) -> MetaPlayResult:
	var result: MetaPlayResult = _start_level_load_operation(level_key)
	if result.status != MetaPlayResult.Status.ACCEPTED:
		return result
	var level: Dictionary = get_level(level_key)
	level_selected.emit(level)
	level_selector_load_new_level_selected.emit(level)
	return result


func toggle_sfx() -> void:
	var enabled: bool = _model.toggle_sfx()
	sfx_setting_changed.emit(enabled)
	modal_config_change_sfx_status.emit()


func toggle_music() -> void:
	var enabled: bool = _model.toggle_music()
	music_setting_changed.emit(enabled)
	modal_config_change_music_status.emit()


func purchase_item(item_path: Array) -> MetaPlayResult:
	var result: Dictionary = _model.purchase_game_item(item_path)
	if bool(result.get("ok", false)):
		var path_copy: Array = item_path.duplicate(true)
		item_purchased.emit(path_copy)
		store_game_buy_item.emit(path_copy)
		return MetaPlayResult.completed(0, {
			"item_path": path_copy,
			"item": result.get("item", {}),
			"cost": int(result.get("cost", 0)),
			"currency_balance": int(result.get("coins", _model.coins)),
		})
	return _reject_store_result(result, RESULT_CODE_STORE_ITEM_NOT_FOUND, "Could not purchase item.")


func equip_item(item_path: Array) -> MetaPlayResult:
	var result: Dictionary = _model.equip_item(item_path)
	if bool(result.get("ok", false)):
		var path_copy: Array = item_path.duplicate(true)
		item_equipped.emit(path_copy)
		store_game_update_item_loadded.emit(path_copy)
		return MetaPlayResult.completed(0, {
			"item_path": path_copy,
			"item": result.get("item", {}),
		})
	return _reject_store_result(result, RESULT_CODE_STORE_ITEM_NOT_FOUND, "Could not equip item.")


func credit_currency_product(product_key: Variant) -> MetaPlayResult:
	var result: Dictionary = _model.add_currency_product(product_key)
	if bool(result.get("ok", false)):
		currency_product_credited.emit(product_key)
		store_currency_buy_coins.emit(product_key)
		return MetaPlayResult.completed(0, {
			"product_key": product_key,
			"currency_added": int(result.get("coins_added", 0)),
			"currency_balance": int(result.get("coins", _model.coins)),
		})
	return _reject_store_result(
		result,
		RESULT_CODE_CURRENCY_PRODUCT_NOT_FOUND,
		"Could not credit currency product."
	)


func _request_screen(screen_name: String) -> void:
	_emit_navigation(screen_name, {})


func _emit_navigation(screen_name: String, payload: Dictionary) -> void:
	var safe_payload: Dictionary = payload.duplicate(true)
	navigation_requested.emit(screen_name, safe_payload)
	screen_requested.emit(screen_name, safe_payload)


func _reject(message: String) -> void:
	action_rejected.emit(message)
	operation_rejected.emit(message)


func _reject_with_result(
		code: StringName,
		message: String,
		context: Dictionary = {}
	) -> MetaPlayResult:
	_reject(message)
	return MetaPlayResult.rejected(code, context)


func _reject_store_result(
		model_result: Dictionary,
		fallback_code: StringName,
		fallback_message: String
	) -> MetaPlayResult:
	var code: StringName = StringName(str(model_result.get("code", fallback_code)))
	var message: String = str(model_result.get("message", fallback_message))
	var raw_context: Variant = model_result.get("context", {})
	var context: Dictionary = raw_context.duplicate(true) if raw_context is Dictionary else {}
	return _reject_with_result(code, message, context)


func _on_coins_changed(total: int) -> void:
	currency_balance_changed.emit(total)
	new_total_coins.emit(total)


func _on_store_changed() -> void:
	store_catalog_changed.emit()


func _on_loading_progress(progress: float) -> void:
	if not _load_request_active or not is_finite(progress):
		return
	var normalized_progress: float = clampf(progress, 0.0, 1.0)
	if normalized_progress < _active_load_progress:
		normalized_progress = _active_load_progress
	if _active_load_progress_emitted and is_equal_approx(normalized_progress, _active_load_progress):
		return
	_active_load_progress = normalized_progress
	_active_load_progress_emitted = true
	loading_progress_changed.emit(_active_load_operation_id, _active_load_progress)


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
	level_load_result.emit(MetaPlayResult.completed(operation_id, {
		"level_key": level_data.get("key"),
		"level_data": level_data,
		"scene_path": _loading_path,
		"resource": resource,
	}))
	level_load_completed.emit(operation_id, level_data, resource)
	loading_completed.emit(operation_id, level_data, resource)
	_load_terminal_emitting = false
	call_deferred("_emit_loading_exit", operation_id)


func _emit_loading_exit(operation_id: int) -> void:
	level_load_exit_animation_completed.emit(operation_id)
	loading_exit_animation_completed.emit(operation_id)


func _on_batch_failed(path: String, message: String) -> void:
	if not _load_request_active:
		return
	var operation_id: int = _active_load_operation_id
	var level_data: Dictionary = _loading_level.duplicate(true)
	_resource_batch.close()
	_load_request_active = false
	_active_load_operation_id = 0
	_load_terminal_emitting = true
	level_load_result.emit(MetaPlayResult.failed(operation_id, RESULT_CODE_LEVEL_LOAD_FAILED, {
		"level_key": level_data.get("key"),
		"level_data": level_data,
		"scene_path": path,
		"message": message,
	}))
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


func level_win(attempt_id: String, _data: Dictionary, stars: int, score: int, next_key: Variant) -> void:
	complete_level(attempt_id, stars, score, next_key)


func level_lose(attempt_id: String) -> void:
	report_level_loss(attempt_id)


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


func notify_modal_lose_video_reward(attempt_id: String) -> void:
	revive_after_reward(attempt_id)


func notify_modal_lose_use_life() -> void:
	use_life()


func notify_modal_win_video_reward(attempt_id: String, claim_id: String) -> void:
	claim_reward_doubling(attempt_id, claim_id)


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
