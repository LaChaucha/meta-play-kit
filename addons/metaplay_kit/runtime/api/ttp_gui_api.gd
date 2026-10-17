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
const RESULT_CODE_PURCHASE_IN_PROGRESS: StringName = &"purchase.in_progress"
const RESULT_CODE_PURCHASE_OPERATION_STALE: StringName = &"purchase.operation_stale"
const RESULT_CODE_PURCHASE_PRODUCT_MISMATCH: StringName = &"purchase.product_mismatch"
const RESULT_CODE_PURCHASE_PROVIDER_FAILED: StringName = &"purchase.provider_failed"
const RESULT_CODE_PURCHASE_NOT_VERIFIED: StringName = &"purchase.not_verified"
const RESULT_CODE_PURCHASE_TRANSACTION_INVALID: StringName = &"purchase.transaction_invalid"
const SESSION_SNAPSHOT_VERSION: int = 4
const PREVIOUS_SESSION_SNAPSHOT_VERSION: int = 3
const COMPLETION_FEATURE_STATE_KEY: String = "level_completion"
const PURCHASE_TRANSACTIONS_FEATURE_STATE_KEY: String = "purchase_transactions"

signal level_load_started(operation_id: int, level_data: Dictionary)
signal level_load_completed(operation_id: int, level_data: Dictionary, resource: Resource)
signal level_load_failed(operation_id: int, level_data: Dictionary, message: String)
signal level_load_cancelled(operation_id: int, level_data: Dictionary)
signal level_load_result(result: MetaPlayResult)
signal level_load_exit_animation_completed(operation_id: int)
signal loading_progress_changed(operation_id: int, progress: float)
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
signal currency_purchase_result(result: MetaPlayResult)
signal currency_purchase_pending(operation_id: int, purchase: Dictionary)
signal currency_purchase_applied(result: MetaPlayResult)
signal currency_purchases_restored(purchases: Array)
signal store_catalog_changed()
signal level_attempt_started(attempt_id: String, level_key: Variant)
signal level_attempt_completed(attempt_id: String, result: Dictionary)
signal level_selection_requested(level_key: Variant)
signal terminal_action_requested(attempt_id: String, action_id: StringName)
signal campaign_projection_changed(entries: Array)
signal reward_claim_completed(result: MetaPlayResult)
signal session_restored(schema_version: int)

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
var _next_purchase_operation_id: int = 0
var _active_purchase_operation_id: int = 0
var _active_purchase_product_key: Variant = null
var _verified_purchase_grants: Dictionary = {}
var _verified_restored_purchases: Dictionary = {}
var _active_load_operation_id: int = 0
var _active_load_progress: float = 0.0
var _active_load_progress_emitted: bool = false
var _pending_cancelled_operation_id: int = 0
var _pending_cancelled_level_data: Dictionary = {}
var _pending_cancelled_scene_path: String = ""
var _session_feature_state: Dictionary = {}
var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()
var _ui_presentation_config_locked: bool = false


func _ready() -> void:
	_model.coins_changed.connect(_on_coins_changed)
	_model.store_changed.connect(_on_store_changed)
	_resource_batch.load_finished.connect(_on_batch_finished)
	_resource_batch.load_failed.connect(_on_batch_failed)
	_resource_batch.stage_updated.connect(_on_loading_progress)


## Stores a snapshot of the host's UI profile before it creates kit components.
## Passing null restores the kit's internal default profile.
func configure_ui_presentation(profile: MetaPlayUIConfig = null) -> void:
	if _ui_presentation_config_locked:
		push_warning(
			"TtpGuiApi UI presentation field 'configuration_timing' cannot change after a kit UI component is initialized; the active profile is retained."
		)
		return
	if profile == null:
		_ui_presentation_config = MetaPlayUIConfig.new()
		return
	var normalized_profile: MetaPlayUIConfig = profile.duplicate(true) as MetaPlayUIConfig
	if normalized_profile == null:
		push_warning("TtpGuiApi UI presentation field 'profile' is invalid; using the internal default profile.")
		_ui_presentation_config = MetaPlayUIConfig.new()
		return
	if normalized_profile.schema_version != MetaPlayUIConfig.CURRENT_SCHEMA_VERSION:
		push_warning(
			"TtpGuiApi UI presentation field 'schema_version' is unsupported; using the default value %d."
			% MetaPlayUIConfig.CURRENT_SCHEMA_VERSION
		)
		normalized_profile.schema_version = MetaPlayUIConfig.CURRENT_SCHEMA_VERSION
	normalized_profile.normalize()
	_ui_presentation_config = normalized_profile


## Returns an isolated snapshot so consumers cannot mutate the stored profile.
func get_ui_presentation_config() -> MetaPlayUIConfig:
	var profile_copy: MetaPlayUIConfig = _ui_presentation_config.duplicate(true) as MetaPlayUIConfig
	return profile_copy if profile_copy != null else MetaPlayUIConfig.new()


## Internal component query; locks the profile once kit UI construction begins.
func _get_ui_presentation_config_for_component() -> MetaPlayUIConfig:
	_ui_presentation_config_locked = true
	return get_ui_presentation_config()


func _enter_tree() -> void:
	_is_shutting_down = false


func _exit_tree() -> void:
	_is_shutting_down = true
	if _active_purchase_operation_id > 0:
		_finish_currency_purchase(MetaPlayResult.cancelled(_active_purchase_operation_id, {
			"product_key": _active_purchase_product_key,
			"reason": "api_shutdown",
		}))
	_verified_purchase_grants.clear()
	_verified_restored_purchases.clear()
	if _load_request_active:
		_finish_active_load_as_cancelled()
	else:
		_resource_batch.close()


# Configuration commands.
func configure_levels(levels: Dictionary) -> void:
	var catalog: Dictionary = {}
	for level_key: Variant in levels.keys():
		var raw_level: Variant = levels[level_key]
		if not raw_level is Dictionary:
			continue
		var definition: Dictionary = (raw_level as Dictionary).duplicate(true)
		definition.erase("enabled")
		definition.erase("max_score")
		definition.erase("max_stars")
		definition.erase("result_rules")
		catalog[level_key] = definition
	_model.set_levels(catalog)
	var rules: Dictionary = {}
	for level_key: Variant in levels.keys():
		var raw_level: Dictionary = levels[level_key] as Dictionary if levels[level_key] is Dictionary else {}
		if raw_level.has("result_rules"):
			rules[level_key] = raw_level["result_rules"]
	if not rules.is_empty():
		configure_level_result_rules(rules)
	_model.campaign_projection.clear()


func configure_level_result_rules(rules_by_level: Dictionary) -> MetaPlayResult:
	var result: Dictionary = _model.configure_level_result_rules(rules_by_level)
	if not bool(result.get("ok", false)):
		return _reject_with_result(StringName(str(result.get("code", "level.rules_invalid"))), str(result.get("message", "Invalid level result rules.")), result.get("context", {}) as Dictionary)
	return MetaPlayResult.completed()


func configure_campaign_projection(entries: Array) -> MetaPlayResult:
	var result: Dictionary = _model.configure_campaign_projection(entries)
	if not bool(result.get("ok", false)):
		return _reject_with_result(StringName(str(result.get("code", "campaign.projection_invalid"))), str(result.get("message", "Invalid campaign projection.")), result.get("context", {}) as Dictionary)
	campaign_projection_changed.emit(get_campaign_projection())
	return MetaPlayResult.completed(0, {"entries": get_campaign_projection()})


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


func set_currency_balance(amount: int) -> void:
	_model.set_coins(amount)


# Queries return copies so consumers cannot mutate kit-owned state accidentally.
func get_level(level_key: Variant) -> Dictionary:
	var level: Dictionary = _model.get_level(level_key)
	if level.is_empty():
		return level
	var progress: Dictionary = _model.get_level_progress(level_key)
	level["completed"] = bool(progress.get("completed", false))
	level["max_score"] = int(progress.get("best_score", 0))
	level["max_stars"] = int(progress.get("best_stars", 0))
	return level


func get_levels() -> Dictionary:
	var result: Dictionary = {}
	for level_key: Variant in _model.levels.keys():
		result[level_key] = get_level(level_key)
	return result


func get_level_progress(level_key: Variant) -> Dictionary:
	return _model.get_level_progress(level_key)


func get_all_level_progress() -> Dictionary:
	return _model.get_all_level_progress()


func get_campaign_projection() -> Array:
	return _model.campaign_projection.duplicate(true)


func get_enabled_level_keys() -> Array:
	return _model.get_enabled_level_keys().duplicate()


func get_next_available_level() -> Variant:
	return null


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
func request_initial_level_load(level_key: Variant = null) -> Dictionary:
	if level_key == null:
		return {}
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
		score: int,
		condition_facts: Dictionary,
		presentation: Dictionary = {}
	) -> MetaPlayResult:
	return _complete_level(attempt_id, score, condition_facts, presentation, false)


func _complete_level(
		attempt_id: String,
		score: int,
		condition_facts: Dictionary,
		presentation: Dictionary,
		force_loss: bool
	) -> MetaPlayResult:
	var result: Dictionary = _model.record_attempt_result(attempt_id, score, condition_facts, presentation, force_loss)
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
	var reward: Dictionary = {}
	if bool(result.get("won", false)):
		reward = _model.claim_base_reward(attempt_id, int(Time.get_unix_time_from_system()))
		if bool(reward.get("ok", false)):
			reward_claim_completed.emit(MetaPlayResult.completed(0, reward))
	result["reward_granted"] = bool(reward.get("granted", false))
	result["reward_amount"] = int(reward.get("amount", 0))
	result["reward_code"] = StringName(str(reward.get("code", "")))
	result["coins"] = _model.coins
	level_attempt_completed.emit(attempt_id, result.duplicate(true))
	return MetaPlayResult.completed(0, {
		"attempt_id": attempt_id,
		"level_key": level_key,
		"outcome": result.get("outcome", "lost"),
		"won": bool(result.get("won", false)),
		"stars": int(result.get("stars", 0)),
		"score": int(result.get("score", 0)),
		"currency_balance": int(result.get("coins", _model.coins)),
		"reward_granted": bool(result.get("reward_granted", false)),
		"reward_amount": int(result.get("reward_amount", 0)),
		"presentation": result.get("presentation", {}),
		"duplicate": bool(result.get("duplicate", false)),
	})


func claim_completion_reward(attempt_id: String) -> MetaPlayResult:
	var result: Dictionary = _model.claim_base_reward(attempt_id, int(Time.get_unix_time_from_system()))
	return _finish_reward_claim(result, "Could not claim completion reward.")


func claim_optional_reward(attempt_id: String, _claim_id: String, reward_type: StringName) -> MetaPlayResult:
	return request_terminal_action(attempt_id, reward_type)


func request_terminal_action(attempt_id: String, action_id: StringName) -> MetaPlayResult:
	if not _model.attempts.has(attempt_id):
		return _reject_with_result(&"attempt.not_found", "The result action references an unknown attempt.", {"attempt_id": attempt_id})
	var attempt: Dictionary = _model.attempts[attempt_id] as Dictionary
	if not ["completed", "failed"].has(str(attempt.get("status", ""))):
		return _reject_with_result(&"attempt.not_completed", "The attempt has no terminal result.", {"attempt_id": attempt_id})
	var result: Dictionary = attempt.get("result", {}) as Dictionary
	var presentation: Dictionary = result.get("presentation", {}) as Dictionary
	var actions: Array = presentation.get("actions", []) as Array
	var next_level: Variant = presentation.get("next_level")
	if next_level is Dictionary and StringName(str((next_level as Dictionary).get("action_id", "next_level"))) == action_id:
		terminal_action_requested.emit(attempt_id, action_id)
		return MetaPlayResult.completed(0, {"attempt_id": attempt_id, "action_id": action_id})
	for raw_action: Variant in actions:
		if raw_action is Dictionary and StringName(str((raw_action as Dictionary).get("id", ""))) == action_id:
			terminal_action_requested.emit(attempt_id, action_id)
			return MetaPlayResult.completed(0, {"attempt_id": attempt_id, "action_id": action_id})
	return _reject_with_result(&"result.action_not_offered", "The requested action was not offered for this attempt.", {"attempt_id": attempt_id, "action_id": action_id})


func _finish_reward_claim(outcome: Dictionary, fallback_message: String) -> MetaPlayResult:
	if not bool(outcome.get("ok", false)):
		return _reject_with_result(StringName(str(outcome.get("code", "reward.rejected"))), str(outcome.get("message", fallback_message)), outcome.get("context", {}) as Dictionary)
	var response: MetaPlayResult = MetaPlayResult.completed(0, outcome)
	if not bool(outcome.get("duplicate", false)):
		reward_claim_completed.emit(response)
	return response


func set_session_feature_state(feature_key: StringName, feature_state: Dictionary) -> MetaPlayResult:
	var normalized_key: String = str(feature_key).strip_edges()
	if normalized_key.is_empty() or normalized_key == COMPLETION_FEATURE_STATE_KEY:
		return _reject_with_result(&"session.feature_key_invalid", "The feature state key is empty or reserved.", {"feature_key": normalized_key})
	if not _is_snapshot_serializable(feature_state):
		return _reject_with_result(&"session.feature_state_invalid", "Feature state must contain only serializable values.", {"feature_key": normalized_key})
	_session_feature_state[normalized_key] = feature_state.duplicate(true)
	return MetaPlayResult.completed(0, {"feature_key": normalized_key})


func get_session_feature_state(feature_key: StringName) -> Dictionary:
	var state: Variant = _session_feature_state.get(str(feature_key), {})
	return state.duplicate(true) if state is Dictionary else {}


func export_session_state() -> MetaPlayResult:
	var feature_state: Dictionary = _session_feature_state.duplicate(true)
	feature_state[COMPLETION_FEATURE_STATE_KEY] = _model.export_completion_state()
	feature_state[PURCHASE_TRANSACTIONS_FEATURE_STATE_KEY] = _model.purchase_transactions.duplicate(true)
	var snapshot: Dictionary = {
		"schema_version": SESSION_SNAPSHOT_VERSION,
		"progression": {"level_progress": _model.get_all_level_progress()},
		"wallet": {"currency_balance": _model.coins},
		"settings": _model.configuration.duplicate(true),
		"inventory": {"items": _model.game_items.duplicate(true)},
		"features": feature_state,
	}
	if not _is_snapshot_serializable(snapshot):
		return _reject_with_result(&"session.snapshot_invalid", "The current session contains data that cannot be serialized.")
	return MetaPlayResult.completed(0, {"snapshot": snapshot})


func restore_session_state(snapshot: Dictionary) -> MetaPlayResult:
	var normalized_snapshot: Dictionary = _migrate_session_snapshot(snapshot)
	if normalized_snapshot.is_empty():
		return _reject_with_result(&"session.snapshot_unsupported", "The session snapshot version is unsupported.")
	var raw_progression: Variant = normalized_snapshot.get("progression")
	var raw_wallet: Variant = normalized_snapshot.get("wallet")
	var raw_settings: Variant = normalized_snapshot.get("settings")
	var raw_inventory: Variant = normalized_snapshot.get("inventory")
	var raw_features: Variant = normalized_snapshot.get("features")
	if not raw_progression is Dictionary or not raw_wallet is Dictionary or not raw_settings is Dictionary or not raw_inventory is Dictionary or not raw_features is Dictionary:
		return _reject_with_result(&"session.snapshot_invalid", "The session snapshot is incomplete or invalid.")
	var progression: Dictionary = raw_progression as Dictionary
	var wallet: Dictionary = raw_wallet as Dictionary
	var inventory: Dictionary = raw_inventory as Dictionary
	var features: Dictionary = raw_features as Dictionary
	var raw_progress: Variant = progression.get("level_progress")
	var raw_items: Variant = inventory.get("items")
	var raw_completion: Variant = features.get(COMPLETION_FEATURE_STATE_KEY)
	var raw_purchase_transactions: Variant = features.get(PURCHASE_TRANSACTIONS_FEATURE_STATE_KEY)
	var raw_balance: Variant = wallet.get("currency_balance")
	if not raw_progress is Dictionary or not raw_items is Dictionary or not raw_completion is Dictionary or not raw_purchase_transactions is Dictionary or not raw_balance is int or int(raw_balance) < 0:
		return _reject_with_result(&"session.snapshot_invalid", "The session snapshot is missing required domain state.")
	if not _is_snapshot_serializable(normalized_snapshot):
		return _reject_with_result(&"session.snapshot_invalid", "The session snapshot contains non-serializable values.")
	var restored_progress: Dictionary = (raw_progress as Dictionary).duplicate(true)
	for level_key: Variant in restored_progress.keys():
		var entry: Variant = restored_progress[level_key]
		if not _model.levels.has(level_key) or not entry is Dictionary:
			return _reject_with_result(&"session.snapshot_invalid", "The session snapshot contains invalid level progress.", {"level_key": level_key})
		var progress_entry: Dictionary = entry as Dictionary
		if not progress_entry.get("completed") is bool or not progress_entry.get("best_score") is int or not progress_entry.get("best_stars") is int or int(progress_entry["best_score"]) < 0 or int(progress_entry["best_stars"]) < 0 or int(progress_entry["best_stars"]) > 3:
			return _reject_with_result(&"session.snapshot_invalid", "The session snapshot contains invalid level progress values.", {"level_key": level_key})
	if restored_progress.size() != _model.levels.size():
		return _reject_with_result(&"session.snapshot_invalid", "The session snapshot does not match the configured level catalog.")
	if not _model.can_restore_completion_state(raw_completion as Dictionary, _model.levels):
		return _reject_with_result(&"session.snapshot_invalid", "The session completion state is invalid.")
	if not _is_purchase_transaction_ledger_valid(raw_purchase_transactions as Dictionary):
		return _reject_with_result(&"session.snapshot_invalid", "The purchase transaction ledger is invalid.")
	var restored_features: Dictionary = features.duplicate(true)
	restored_features.erase(COMPLETION_FEATURE_STATE_KEY)
	restored_features.erase(PURCHASE_TRANSACTIONS_FEATURE_STATE_KEY)
	_model.level_progress = restored_progress
	_model.configuration = (raw_settings as Dictionary).duplicate(true)
	_model.game_items = (raw_items as Dictionary).duplicate(true)
	_model.coins = int(raw_balance)
	_model.purchase_transactions = (raw_purchase_transactions as Dictionary).duplicate(true)
	var completion_restored: bool = _model.restore_completion_state(raw_completion as Dictionary)
	assert(completion_restored, "Validated completion state must restore atomically.")
	_session_feature_state = restored_features
	session_restored.emit(SESSION_SNAPSHOT_VERSION)
	return MetaPlayResult.completed(0, {"schema_version": SESSION_SNAPSHOT_VERSION})


func _migrate_session_snapshot(snapshot: Dictionary) -> Dictionary:
	var snapshot_version: int = int(snapshot.get("schema_version", -1))
	if snapshot_version == SESSION_SNAPSHOT_VERSION:
		return snapshot.duplicate(true)
	if snapshot_version != PREVIOUS_SESSION_SNAPSHOT_VERSION:
		return {}
	var migrated: Dictionary = snapshot.duplicate(true)
	var raw_features: Variant = migrated.get("features")
	if not raw_features is Dictionary:
		return migrated
	var features: Dictionary = (raw_features as Dictionary).duplicate(true)
	features[PURCHASE_TRANSACTIONS_FEATURE_STATE_KEY] = {}
	migrated["features"] = features
	migrated["schema_version"] = SESSION_SNAPSHOT_VERSION
	return migrated


func _is_purchase_transaction_ledger_valid(ledger: Dictionary) -> bool:
	for transaction_id: Variant in ledger.keys():
		var raw_entry: Variant = ledger[transaction_id]
		if not transaction_id is String or str(transaction_id).strip_edges().is_empty() or not raw_entry is Dictionary:
			return false
		var entry: Dictionary = raw_entry as Dictionary
		var entry_transaction_id: String = str(entry.get("transaction_id", ""))
		var entry_provider: String = str(entry.get("provider", ""))
		var expected_key: String = "%s:%s" % [entry_provider, entry_transaction_id]
		if entry_transaction_id.is_empty() or entry_provider.is_empty() or str(transaction_id) != expected_key or str(entry.get("product_key", "")).is_empty():
			return false
		if not entry.get("currency_added") is int or int(entry.get("currency_added", -1)) < 0:
			return false
	return true


func _is_snapshot_serializable(value: Variant) -> bool:
	if value == null or value is bool or value is int or value is String or value is StringName:
		return true
	if value is float:
		return is_finite(float(value))
	if value is Array:
		for item: Variant in value:
			if not _is_snapshot_serializable(item):
				return false
		return true
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if not (key is String or key is StringName) or not _is_snapshot_serializable((value as Dictionary)[key]):
				return false
		return true
	return false


func report_level_loss(attempt_id: String) -> MetaPlayResult:
	if not _model.attempts.has(attempt_id):
		return _reject_with_result(&"attempt.not_found", "The gameplay attempt is unknown or stale.", {"attempt_id": attempt_id})
	var attempt: Dictionary = _model.attempts[attempt_id] as Dictionary
	var level_key: Variant = attempt.get("level_key")
	var facts: Dictionary = {}
	var rules: Dictionary = _model.level_result_rules.get(level_key, {}) as Dictionary
	for condition_key: Variant in rules.get("required_conditions", []) as Array:
		facts[condition_key] = false
	return _complete_level(attempt_id, 0, facts, {}, true)


func retry_level(level_key: Variant) -> MetaPlayResult:
	var result: MetaPlayResult = _start_level_load_operation(level_key)
	if result.status != MetaPlayResult.Status.ACCEPTED:
		return result
	var level: Dictionary = get_level(level_key)
	level_retry_requested.emit(level)
	return result


func load_next_level() -> MetaPlayResult:
	return _reject_with_result(RESULT_CODE_NO_AVAILABLE_LEVEL, "The host must explicitly choose a level before loading the next level.")


func request_next_level_load(next_key: Variant) -> MetaPlayResult:
	if next_key == null:
		return _reject_with_result(RESULT_CODE_NO_AVAILABLE_LEVEL, "The host did not provide a next-level key.")
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
	return MetaPlayResult.completed(0, {"attempt_id": attempt_id, "revived": true})


func claim_reward_doubling(attempt_id: String, _claim_id: String) -> MetaPlayResult:
	return request_terminal_action(attempt_id, &"double_completion")


func use_life() -> void:
	life_use_requested.emit()
	modal_lose_use_life_pressed.emit()


func start_or_resume_game(level_key: Variant = null) -> MetaPlayResult:
	if level_key == null:
		return _reject_with_result(RESULT_CODE_NO_AVAILABLE_LEVEL, "The host must choose a level before starting or resuming the game.")
	var result: MetaPlayResult = _start_level_load_operation(level_key)
	if result.status != MetaPlayResult.Status.ACCEPTED:
		return result
	play_requested.emit()
	home_tap_to_play_pressed.emit()
	return result


func select_level(level_key: Variant) -> MetaPlayResult:
	if not _model.levels.has(level_key):
		return _reject_with_result(RESULT_CODE_LEVEL_NOT_FOUND, "The requested level does not exist.", {"level_key": level_key})
	for raw_entry: Variant in _model.campaign_projection:
		if raw_entry is Dictionary and (raw_entry as Dictionary).get("key") == level_key:
			if not bool((raw_entry as Dictionary).get("selectable", false)):
				return _reject_with_result(&"level.selection_not_allowed", "The host marked this campaign entry as non-selectable.", {"level_key": level_key})
			level_selection_requested.emit(level_key)
			var level: Dictionary = get_level(level_key)
			level_selected.emit(level)
			level_selector_load_new_level_selected.emit(level)
			return MetaPlayResult.completed(0, {"level_key": level_key})
	return _reject_with_result(&"level.selection_not_configured", "The level is not part of the host campaign projection.", {"level_key": level_key})


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


func begin_currency_purchase(product_key: Variant) -> MetaPlayResult:
	if _active_purchase_operation_id > 0:
		return _reject_with_result(
			RESULT_CODE_PURCHASE_IN_PROGRESS,
			"A currency purchase is already in progress.",
			{"active_operation_id": _active_purchase_operation_id}
		)
	if product_key == null or str(product_key).strip_edges().is_empty() or not _model.coin_values.has(product_key):
		return _reject_with_result(
			RESULT_CODE_CURRENCY_PRODUCT_NOT_FOUND,
			"The currency purchase references an unknown product.",
			{"product_key": product_key}
		)
	_next_purchase_operation_id += 1
	_active_purchase_operation_id = _next_purchase_operation_id
	_active_purchase_product_key = product_key
	return MetaPlayResult.accepted(_active_purchase_operation_id, {"product_key": product_key})


func mark_currency_purchase_pending(operation_id: int, purchase: Dictionary) -> MetaPlayResult:
	if not _is_active_purchase(operation_id):
		return _reject_stale_purchase(operation_id)
	if str(purchase.get("product_key", "")) != str(_active_purchase_product_key) or not bool(purchase.get("verified", false)):
		return _reject_with_result(RESULT_CODE_PURCHASE_NOT_VERIFIED, "The pending purchase is not verified for the active product.", {"operation_id": operation_id})
	var safe_purchase: Dictionary = purchase.duplicate(true)
	currency_purchase_pending.emit(operation_id, safe_purchase)
	return MetaPlayResult.accepted(operation_id, {"pending": true, "purchase": safe_purchase})


func complete_currency_purchase(
		operation_id: int,
		confirmed_product_key: Variant,
		purchase: Dictionary = {}
	) -> MetaPlayResult:
	if not _is_active_purchase(operation_id):
		return _reject_stale_purchase(operation_id)
	if confirmed_product_key != _active_purchase_product_key:
		return _finish_currency_purchase(MetaPlayResult.failed(
			operation_id,
			RESULT_CODE_PURCHASE_PRODUCT_MISMATCH,
			{"product_key": _active_purchase_product_key, "confirmed_product_key": confirmed_product_key}
		))
	if str(purchase.get("product_key", "")) != str(_active_purchase_product_key):
		return _finish_currency_purchase(MetaPlayResult.failed(
			operation_id,
			RESULT_CODE_PURCHASE_PRODUCT_MISMATCH,
			{"product_key": _active_purchase_product_key, "purchase_product_key": purchase.get("product_key")}
		))
	var provider_id: String = str(purchase.get("provider", ""))
	var simulated: bool = provider_id == "simulation" and bool(purchase.get("simulated", false)) and not bool(purchase.get("verified", false))
	if not simulated:
		var transaction_id: String = str(purchase.get("transaction_id", "")).strip_edges()
		if provider_id.is_empty() or transaction_id.is_empty() or not bool(purchase.get("verified", false)):
			return _finish_currency_purchase(MetaPlayResult.failed(
				operation_id,
				RESULT_CODE_PURCHASE_NOT_VERIFIED,
				{"product_key": _active_purchase_product_key}
			))
	var completed_context: Dictionary = {
		"product_key": _active_purchase_product_key,
		"provider": provider_id,
		"transaction_id": str(purchase.get("transaction_id", "")),
		"verification": str(purchase.get("verification", "")),
		"verified": bool(purchase.get("verified", false)),
		"simulated": simulated,
	}
	if not simulated:
		_verified_purchase_grants[operation_id] = completed_context.duplicate(true)
	return _finish_currency_purchase(MetaPlayResult.completed(operation_id, completed_context))


func apply_verified_currency_purchase(operation_id: int) -> MetaPlayResult:
	var grant_raw: Variant = _verified_purchase_grants.get(operation_id)
	if not grant_raw is Dictionary:
		return _reject_with_result(RESULT_CODE_PURCHASE_NOT_VERIFIED, "No verified purchase is available for this operation ID.", {"operation_id": operation_id})
	var grant: Dictionary = grant_raw as Dictionary
	var outcome: Dictionary = _model.record_verified_currency_purchase(
		grant.get("product_key"),
		str(grant.get("transaction_id", "")),
		str(grant.get("provider", ""))
	)
	if not bool(outcome.get("ok", false)):
		return _reject_store_result(outcome, RESULT_CODE_PURCHASE_TRANSACTION_INVALID, "Could not apply the verified purchase.")
	_verified_purchase_grants.erase(operation_id)
	var result: MetaPlayResult = MetaPlayResult.completed(operation_id, outcome)
	if not bool(outcome.get("duplicate", false)):
		currency_purchase_applied.emit(result)
	return result


func get_verified_purchase_transaction(transaction_id: String, provider_id: String) -> Dictionary:
	var transaction_key: String = "%s:%s" % [provider_id, transaction_id]
	var entry: Variant = _model.purchase_transactions.get(transaction_key, {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}


func restore_purchase_records(purchases: Array) -> MetaPlayResult:
	var verified_records: Array = []
	var restored_by_transaction: Dictionary = {}
	for raw_purchase: Variant in purchases:
		if not raw_purchase is Dictionary:
			continue
		var purchase: Dictionary = raw_purchase as Dictionary
		if not bool(purchase.get("verified", false)) or str(purchase.get("provider", "")).is_empty() or str(purchase.get("transaction_id", "")).is_empty():
			continue
		var safe_purchase: Dictionary = purchase.duplicate(true)
		var transaction_id: String = str(safe_purchase.get("transaction_id", ""))
		verified_records.append(safe_purchase)
		restored_by_transaction[transaction_id] = safe_purchase
	_verified_restored_purchases = restored_by_transaction
	currency_purchases_restored.emit(verified_records.duplicate(true))
	return MetaPlayResult.completed(0, {"purchases": verified_records})


func apply_restored_currency_purchase(transaction_id: String) -> MetaPlayResult:
	var purchase_raw: Variant = _verified_restored_purchases.get(transaction_id)
	if not purchase_raw is Dictionary:
		return _reject_with_result(RESULT_CODE_PURCHASE_NOT_VERIFIED, "The transaction is not part of the latest verified restore result.", {"transaction_id": transaction_id})
	var purchase: Dictionary = purchase_raw as Dictionary
	var outcome: Dictionary = _model.record_verified_currency_purchase(
		purchase.get("product_key"),
		transaction_id,
		str(purchase.get("provider", ""))
	)
	if not bool(outcome.get("ok", false)):
		return _reject_store_result(outcome, RESULT_CODE_PURCHASE_TRANSACTION_INVALID, "Could not apply the restored purchase.")
	var result: MetaPlayResult = MetaPlayResult.completed(0, outcome)
	if not bool(outcome.get("duplicate", false)):
		currency_purchase_applied.emit(result)
	return result


func fail_currency_purchase(operation_id: int, provider_code: StringName = &"") -> MetaPlayResult:
	if not _is_active_purchase(operation_id):
		return _reject_stale_purchase(operation_id)
	return _finish_currency_purchase(MetaPlayResult.failed(
		operation_id,
		RESULT_CODE_PURCHASE_PROVIDER_FAILED,
		{"product_key": _active_purchase_product_key, "provider_code": provider_code}
	))


func cancel_currency_purchase(operation_id: int) -> MetaPlayResult:
	if not _is_active_purchase(operation_id):
		return _reject_stale_purchase(operation_id)
	return _finish_currency_purchase(MetaPlayResult.cancelled(operation_id, {
		"product_key": _active_purchase_product_key,
	}))


func _is_active_purchase(operation_id: int) -> bool:
	return operation_id > 0 and operation_id == _active_purchase_operation_id


func _reject_stale_purchase(operation_id: int) -> MetaPlayResult:
	return _reject_with_result(
		RESULT_CODE_PURCHASE_OPERATION_STALE,
		"The purchase operation is unknown, stale, or already terminal.",
		{"operation_id": operation_id}
	)


func _finish_currency_purchase(result: MetaPlayResult) -> MetaPlayResult:
	_active_purchase_operation_id = 0
	_active_purchase_product_key = null
	currency_purchase_result.emit(result)
	return result


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


func level_win(attempt_id: String, score: int, condition_facts: Dictionary, presentation: Dictionary = {}) -> void:
	complete_level(attempt_id, score, condition_facts, presentation)


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


func get_resource_loaded(path: String) -> Resource:
	return get_loaded_resource(path)


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


func send_notification_ui(signal_name: String, parameter: Variant = null) -> MetaPlayResult:
	## Deprecated explicit alias map for the legacy helper; arbitrary signal names are never emitted.
	match signal_name:
		"new_total_coins":
			if not parameter is int:
				return _legacy_event_arguments_invalid(signal_name)
			new_total_coins.emit(int(parameter))
		"store_game_update_item_loadded":
			if parameter == null:
				return _legacy_event_arguments_invalid(signal_name)
			store_game_update_item_loadded.emit(parameter)
		"store_game_buy_item":
			if not parameter is Array:
				return _legacy_event_arguments_invalid(signal_name)
			store_game_buy_item.emit((parameter as Array).duplicate(true))
		"store_currency_buy_coins":
			if parameter == null:
				return _legacy_event_arguments_invalid(signal_name)
			store_currency_buy_coins.emit(parameter)
		"level_selector_load_new_level_selected":
			if not parameter is Dictionary:
				return _legacy_event_arguments_invalid(signal_name)
			level_selector_load_new_level_selected.emit((parameter as Dictionary).duplicate(true))
		"modal_win_video_reward_showed":
			if not parameter is Array:
				return _legacy_event_arguments_invalid(signal_name)
			modal_win_video_reward_showed.emit((parameter as Array).duplicate(true))
		"home_tap_to_play_pressed", "modal_lose_use_life_pressed", "modal_config_change_sfx_status", "modal_config_change_music_status":
			if parameter != null:
				return _legacy_event_arguments_invalid(signal_name)
			match signal_name:
				"home_tap_to_play_pressed":
					home_tap_to_play_pressed.emit()
				"modal_lose_use_life_pressed":
					modal_lose_use_life_pressed.emit()
				"modal_config_change_sfx_status":
					modal_config_change_sfx_status.emit()
				"modal_config_change_music_status":
					modal_config_change_music_status.emit()
		_:
			return _reject_with_result(
				&"api.event_unsupported",
				"The requested UI event is unsupported; use a declared facade method or signal.",
				{"event_name": signal_name}
			)
	return MetaPlayResult.completed(0, {"event_name": signal_name, "legacy": true})


func _legacy_event_arguments_invalid(signal_name: String) -> MetaPlayResult:
	return _reject_with_result(
		&"api.event_arguments_invalid",
		"The legacy UI event received arguments with an invalid shape.",
		{"event_name": signal_name}
	)


func manage_tap_background() -> void:
	pass
