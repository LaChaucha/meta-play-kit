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

	var result: MetaPlayResult = api.call("complete_level", "missing", 3, 900, 50, "next") as MetaPlayResult

	assert_eq(result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(result.code, &"level.not_found")
	assert_eq(result.context.get("level_key"), "missing")
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
	watch_signals(api)

	var result: MetaPlayResult = api.call("complete_level", "first", 2, 900, 50, "second") as MetaPlayResult
	var completed_level: Dictionary = api.call("get_level", "first") as Dictionary
	var next_level: Dictionary = api.call("get_level", "second") as Dictionary
	var navigation_args: Array = get_signal_args(api, "navigation_requested")
	var legacy_navigation_args: Array = get_signal_args(api, "screen_requested")

	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(result.code, &"")
	assert_eq(result.operation_id, 0)
	assert_eq(result.context.get("level_key"), "first")
	assert_eq(result.context.get("currency_balance"), 150)
	assert_eq(completed_level.get("max_stars"), 2)
	assert_eq(completed_level.get("max_score"), 900)
	assert_true(bool(next_level.get("enabled", false)))
	assert_eq(int(api.call("get_currency_balance")), 150)
	assert_eq(navigation_args[0], "win")
	assert_eq(legacy_navigation_args, navigation_args, "The compatibility event mirrors the semantic navigation request.")
	assert_signal_emit_count(api, "navigation_requested", 1)
	assert_signal_emit_count(api, "screen_requested", 1)
	assert_signal_emit_count(api, "currency_balance_changed", 1)
	assert_signal_emit_count(api, "action_rejected", 0)


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
