extends "res://tests/test_case.gd"

const ApiScript: GDScript = preload("res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd")
const LEVEL_PATH: String = "res://demo/scenes/level_stub.tscn"

var api: Node


func before_each() -> void:
	api = add_child_autofree(ApiScript.new()) as Node


func test_unknown_level_completion_returns_rejection_without_mutating_progress() -> void:
	api.call("configure_levels", {
		"first": {
			"name": "First",
			"enabled": true,
			"scene_path": LEVEL_PATH,
			"max_stars": 0,
			"max_score": 0,
		},
	})
	api.call("set_currency_balance", 100)
	watch_signals(api)

	var result: MetaPlayResult = api.call("complete_level", "missing", 3, 900, "next") as MetaPlayResult

	assert_eq(result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(result.code, &"attempt.not_found")
	assert_eq(result.context.get("attempt_id"), "missing")
	assert_eq(int(api.call("get_currency_balance")), 100)
	var level: Dictionary = api.call("get_level", "first") as Dictionary
	assert_eq(level.get("max_stars"), 0)
	assert_eq(level.get("max_score"), 0)
	assert_signal_emit_count(api, "navigation_requested", 0)
	assert_signal_emit_count(api, "currency_balance_changed", 0)
	assert_signal_emit_count(api, "action_rejected", 1, "The legacy rejection signal remains available during migration.")


func test_successful_level_completion_returns_committed_progress_and_emits_win_navigation() -> void:
	api.call("configure_levels", {
		"first": {"name": "First", "enabled": true, "scene_path": LEVEL_PATH},
		"second": {"name": "Second", "enabled": false, "scene_path": LEVEL_PATH},
	})
	api.call("set_currency_balance", 100)
	api.call("configure_completion_rewards", {"first": 50}, 3600)
	watch_signals(api)

	var attempt: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var attempt_id: String = str(attempt.context.get("attempt_id", ""))
	var result: MetaPlayResult = api.call("complete_level", attempt_id, 2, 900, "second") as MetaPlayResult
	var duplicate: MetaPlayResult = api.call("complete_level", attempt_id, 2, 900, "second") as MetaPlayResult
	var completed_level: Dictionary = api.call("get_level", "first") as Dictionary
	var next_level: Dictionary = api.call("get_level", "second") as Dictionary
	var navigation_args: Array = get_signal_args(api, "navigation_requested")
	var legacy_navigation_args: Array = get_signal_args(api, "screen_requested")

	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(result.code, &"")
	assert_eq(result.operation_id, 0)
	assert_eq(result.context.get("level_key"), "first")
	assert_eq(result.context.get("attempt_id"), attempt_id)
	assert_eq(result.context.get("currency_balance"), 150)
	assert_eq(result.context.get("reward_amount"), 50)
	assert_true(bool(duplicate.context.get("duplicate", false)))
	assert_eq(completed_level.get("max_stars"), 2)
	assert_eq(completed_level.get("max_score"), 900)
	assert_true(bool(next_level.get("enabled", false)))
	assert_eq(int(api.call("get_currency_balance")), 150)
	assert_eq(navigation_args[0], "win")
	assert_eq(legacy_navigation_args, navigation_args, "The compatibility event mirrors the semantic navigation request.")
	assert_signal_emit_count(api, "navigation_requested", 1)
	assert_signal_emit_count(api, "screen_requested", 1)
	assert_signal_emit_count(api, "action_rejected", 0)
	assert_signal_emit_count(api, "currency_balance_changed", 1, "Duplicate completion must not credit currency twice.")


func test_optional_reward_claim_is_idempotent_and_snapshot_restore_preserves_claims() -> void:
	api.call("configure_levels", {"first": {"enabled": true, "scene_path": LEVEL_PATH}})
	api.call("set_currency_balance", 100)
	api.call("configure_settings", {"sfx": false, "music": true})
	api.call("configure_items", {"hat": {"bought": true, "load": true}})
	api.call("configure_completion_rewards", {"first": 25}, 600)
	api.call("configure_optional_rewards", {"double_completion": 40})
	api.call("set_session_feature_state", &"quests", {"daily_count": 2, "flags": ["first_win"]})
	var attempt: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var attempt_id: String = str(attempt.context.get("attempt_id", ""))
	api.call("complete_level", attempt_id, 1, 10, null)
	var claim: MetaPlayResult = api.call("claim_reward_doubling", attempt_id, "ad-token-1") as MetaPlayResult
	var exported: MetaPlayResult = api.call("export_session_state") as MetaPlayResult
	var snapshot: Dictionary = exported.context.get("snapshot", {}) as Dictionary
	assert_eq(snapshot.get("schema_version"), 2)
	assert_true((snapshot.get("settings", {}) as Dictionary).has("sfx"))
	assert_true((snapshot.get("progression", {}) as Dictionary).has("levels"))
	var mutated_snapshot: Dictionary = snapshot.duplicate(true)
	(mutated_snapshot["settings"] as Dictionary)["sfx"] = true
	assert_false(bool((api.call("get_settings") as Dictionary).get("sfx", true)))
	api.call("set_currency_balance", 777)
	api.call("configure_settings", {"sfx": true, "music": false})
	api.call("configure_items", {})
	watch_signals(api)
	var restored: MetaPlayResult = api.call("restore_session_state", snapshot) as MetaPlayResult
	var duplicate: MetaPlayResult = api.call("claim_reward_doubling", attempt_id, "ad-token-1") as MetaPlayResult

	assert_eq(claim.context.get("amount"), 40)
	assert_eq(exported.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(restored.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(int(api.call("get_currency_balance")), 165)
	assert_false(bool((api.call("get_settings") as Dictionary).get("sfx", true)))
	assert_true(bool((api.call("get_item", ["hat"]) as Dictionary).get("bought", false)))
	assert_eq(api.call("get_session_feature_state", &"quests"), {"daily_count": 2, "flags": ["first_win"]})
	assert_true(bool(duplicate.context.get("duplicate", false)))
	assert_signal_emit_count(api, "session_restored", 1)
	assert_signal_emit_count(api, "currency_balance_changed", 0, "Restore emits one consolidated notification instead of partial wallet changes.")


func test_invalid_snapshot_restore_is_atomic_and_negative_reward_configuration_is_rejected() -> void:
	api.call("configure_levels", {"first": {"enabled": true, "scene_path": LEVEL_PATH}})
	api.call("set_currency_balance", 300)
	var negative_config: MetaPlayResult = api.call("configure_completion_rewards", {"first": -1}, 30) as MetaPlayResult
	var invalid_snapshot: Dictionary = {"schema_version": 2, "progression": {"levels": {"wrong": {}}}, "wallet": {"currency_balance": 1}, "settings": {}, "inventory": {"items": {}}, "features": {"level_completion": {"version": 1}}}
	watch_signals(api)
	var restore_result: MetaPlayResult = api.call("restore_session_state", invalid_snapshot) as MetaPlayResult
	var unsupported_snapshot: MetaPlayResult = api.call("restore_session_state", {"schema_version": 1}) as MetaPlayResult

	assert_eq(negative_config.status, MetaPlayResult.Status.REJECTED)
	assert_eq(negative_config.code, &"reward.configuration_invalid")
	assert_eq(restore_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(restore_result.code, &"session.snapshot_invalid")
	assert_eq(unsupported_snapshot.code, &"session.snapshot_unsupported")
	assert_signal_emit_count(api, "session_restored", 0)
	assert_eq(int(api.call("get_currency_balance")), 300)
	assert_true((api.call("get_level", "first") as Dictionary).has("scene_path"))
	var unserializable: Node = Node.new()
	var invalid_feature_state: MetaPlayResult = api.call("set_session_feature_state", &"quests", {"node": unserializable}) as MetaPlayResult
	assert_eq(invalid_feature_state.status, MetaPlayResult.Status.REJECTED)
	assert_eq(api.call("get_session_feature_state", &"quests"), {})
	api.call("configure_settings", {"unsafe": unserializable})
	var invalid_export: MetaPlayResult = api.call("export_session_state") as MetaPlayResult
	assert_eq(invalid_export.status, MetaPlayResult.Status.REJECTED)
	assert_eq(invalid_export.code, &"session.snapshot_invalid")
	unserializable.free()


func test_level_selection_returns_distinct_codes_for_unknown_and_locked_levels() -> void:
	api.call("configure_levels", {
		"locked": {"name": "Locked", "enabled": false, "scene_path": LEVEL_PATH},
	})
	watch_signals(api)

	var unknown_result: MetaPlayResult = api.call("select_level", "unknown") as MetaPlayResult
	var locked_result: MetaPlayResult = api.call("select_level", "locked") as MetaPlayResult

	assert_eq(unknown_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(unknown_result.code, &"level.not_found")
	assert_eq(locked_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(locked_result.code, &"level.locked")
	assert_signal_emit_count(api, "level_load_started", 0)
	assert_signal_emit_count(api, "level_selected", 0)
	assert_signal_emit_count(api, "level_selector_load_new_level_selected", 0)
	assert_signal_emit_count(api, "action_rejected", 2)


func test_accepted_selection_returns_load_id_and_emits_terminal_load_separately() -> void:
	api.call("configure_levels", {
		"first": {"name": "First", "enabled": true, "scene_path": LEVEL_PATH},
	})
	watch_signals(api)
	var nested_results: Array[MetaPlayResult] = []
	var nested_request_callback: Callable = func(_operation_id: int, _level_data: Dictionary) -> void:
		var nested_result: MetaPlayResult = api.call("select_level", "first") as MetaPlayResult
		nested_results.append(nested_result)
	api.connect("level_load_started", nested_request_callback, CONNECT_ONE_SHOT)

	var result: MetaPlayResult = api.call("select_level", "first") as MetaPlayResult
	var start_args: Array = get_signal_args(api, "level_load_started", 0)
	var finished: bool = await wait_until(func() -> bool: return not bool(api.call("is_loading")))
	var terminal_args: Array = get_signal_args(api, "level_load_completed", 0)

	assert_true(finished, "The accepted scene load must eventually reach a terminal event.")
	assert_eq(result.status, MetaPlayResult.Status.ACCEPTED)
	assert_gt(result.operation_id, 0)
	assert_eq(result.context.get("level_key"), "first")
	assert_eq(start_args[0], result.operation_id)
	assert_eq(terminal_args[0], result.operation_id)
	assert_eq(result.status, MetaPlayResult.Status.ACCEPTED, "The terminal load signal does not change the earlier command result.")
	assert_eq(nested_results.size(), 1)
	assert_eq(nested_results[0].status, MetaPlayResult.Status.REJECTED)
	assert_eq(nested_results[0].code, &"level.load_in_progress")
	assert_signal_emit_count(api, "level_selected", 1)
	assert_signal_emit_count(api, "level_selector_load_new_level_selected", 1)
	assert_signal_emit_count(api, "level_load_completed", 1)
	assert_signal_emit_count(api, "level_load_started", 1)


func test_play_retry_and_next_level_return_accepted_results_only_after_load_starts() -> void:
	api.call("configure_levels", {
		"first": {"name": "First", "enabled": true, "scene_path": LEVEL_PATH, "max_stars": 0},
	})
	watch_signals(api)

	var play_result: MetaPlayResult = api.call("start_or_resume_game") as MetaPlayResult
	assert_eq(play_result.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(await wait_until(func() -> bool: return not bool(api.call("is_loading"))))
	var retry_result: MetaPlayResult = api.call("retry_level", "first") as MetaPlayResult
	assert_eq(retry_result.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(await wait_until(func() -> bool: return not bool(api.call("is_loading"))))
	var next_result: MetaPlayResult = api.call("load_next_level") as MetaPlayResult
	assert_eq(next_result.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(await wait_until(func() -> bool: return not bool(api.call("is_loading"))))

	assert_ne(play_result.operation_id, retry_result.operation_id)
	assert_ne(retry_result.operation_id, next_result.operation_id)
	assert_signal_emit_count(api, "play_requested", 1)
	assert_signal_emit_count(api, "home_tap_to_play_pressed", 1)
	assert_signal_emit_count(api, "level_retry_requested", 1)
	assert_signal_emit_count(api, "next_level_load_requested", 1)
	assert_signal_emit_count(api, "modal_win_load_next_level_pressed", 1)
	assert_signal_emit_count(api, "level_load_completed", 3)


func test_play_advance_and_retry_report_missing_destinations() -> void:
	api.call("configure_levels", {})
	watch_signals(api)

	var play_result: MetaPlayResult = api.call("start_or_resume_game") as MetaPlayResult
	var next_result: MetaPlayResult = api.call("load_next_level") as MetaPlayResult
	var retry_result: MetaPlayResult = api.call("retry_level", "missing") as MetaPlayResult

	assert_eq(play_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(play_result.code, &"level.no_available_level")
	assert_eq(next_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(next_result.code, &"level.no_available_level")
	assert_eq(retry_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(retry_result.code, &"level.not_found")
	assert_signal_emit_count(api, "level_load_started", 0)
	assert_signal_emit_count(api, "play_requested", 0)
	assert_signal_emit_count(api, "level_retry_requested", 0)
	assert_signal_emit_count(api, "next_level_load_requested", 0)
