extends "res://tests/test_case.gd"

const ApiScript: GDScript = preload("res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd")
const LEVEL_PATH: String = "res://demo/scenes/level_stub.tscn"

var api: Node


func before_each() -> void:
	api = add_child_autofree(ApiScript.new()) as Node
	api.call("configure_levels", {
		"first": {"name": "First", "scene_path": LEVEL_PATH},
		"second": {"name": "Second", "scene_path": LEVEL_PATH},
	})
	api.call("configure_level_result_rules", {
		"first": {"max_score": 1000, "star_thresholds": [300, 600, 900], "required_conditions": ["goal_reached"]},
		"second": {"max_score": 1000, "star_thresholds": [300, 600, 900], "required_conditions": ["goal_reached"]},
	})
	api.call("configure_campaign_projection", [
		{"key": "first", "available": true, "selectable": true},
		{"key": "second", "available": false, "selectable": false},
	])


func test_unknown_attempt_result_is_rejected_without_mutating_progress() -> void:
	api.call("set_currency_balance", 100)
	watch_signals(api)
	var result: MetaPlayResult = api.call("complete_level", "missing", 900, {"goal_reached": true}) as MetaPlayResult
	assert_eq(result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(result.code, &"attempt.not_found")
	assert_eq(api.call("get_currency_balance"), 100)
	assert_eq(api.call("get_level_progress", "first"), {"completed": false, "best_score": 0, "best_stars": 0})
	assert_signal_emit_count(api, "level_attempt_completed", 0)
	assert_signal_emit_count(api, "action_rejected", 1)


func test_result_rules_calculate_stars_record_progress_and_never_unlock_next_level() -> void:
	api.call("configure_completion_rewards", {"first": 50}, 3600)
	api.call("set_currency_balance", 100)
	watch_signals(api)
	var started: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var attempt_id: String = str(started.context.get("attempt_id", ""))
	var presentation: Dictionary = {"next_level": {"key": "second", "label": "Continue", "action_id": "next_level"}, "actions": [{"id": "double", "label": "Double reward"}]}
	var result: MetaPlayResult = api.call("complete_level", attempt_id, 650, {"goal_reached": true}, presentation) as MetaPlayResult
	var duplicate: MetaPlayResult = api.call("complete_level", attempt_id, 650, {"goal_reached": true}, presentation) as MetaPlayResult
	var first_progress: Dictionary = api.call("get_level_progress", "first") as Dictionary
	var second_progress: Dictionary = api.call("get_level_progress", "second") as Dictionary
	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(result.context.get("outcome"), "won")
	assert_eq(result.context.get("stars"), 2)
	assert_eq(result.context.get("score"), 650)
	assert_eq(result.context.get("presentation"), presentation)
	assert_eq(first_progress, {"completed": true, "best_score": 650, "best_stars": 2})
	assert_eq(second_progress, {"completed": false, "best_score": 0, "best_stars": 0})
	assert_eq(api.call("get_currency_balance"), 150)
	assert_true(bool(duplicate.context.get("duplicate", false)))
	assert_eq(api.call("get_enabled_level_keys"), ["first"])
	assert_eq(api.call("get_next_available_level"), null)
	assert_signal_emit_count(api, "level_attempt_completed", 1)
	var completion_event: Array = get_signal_args(api, "level_attempt_completed")
	assert_eq(completion_event[0], attempt_id)
	assert_eq((completion_event[1] as Dictionary).get("outcome"), "won")
	assert_signal_emit_count(api, "currency_balance_changed", 1)


func test_failed_conditions_produce_zero_star_loss_and_no_completion_reward() -> void:
	api.call("configure_completion_rewards", {"first": 50}, 0)
	api.call("set_currency_balance", 100)
	watch_signals(api)
	var started: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var result: MetaPlayResult = api.call("complete_level", str(started.context.get("attempt_id", "")), 800, {"goal_reached": false}) as MetaPlayResult
	var progress: Dictionary = api.call("get_level_progress", "first") as Dictionary
	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(result.context.get("outcome"), "lost")
	assert_eq(result.context.get("stars"), 0)
	assert_false(bool(progress.get("completed", true)))
	assert_eq(progress.get("best_score"), 800)
	assert_eq(api.call("get_currency_balance"), 100)
	var completion_event: Array = get_signal_args(api, "level_attempt_completed")
	assert_eq((completion_event[1] as Dictionary).get("outcome"), "lost")


func test_legacy_loss_command_forces_loss_without_required_conditions() -> void:
	api.call("configure_level_result_rules", {
		"first": {"max_score": 1000, "star_thresholds": [300, 600, 900], "required_conditions": []},
	})
	var started: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var result: MetaPlayResult = api.call("report_level_loss", str(started.context.get("attempt_id", ""))) as MetaPlayResult
	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(result.context.get("outcome"), "lost")
	assert_false(bool(result.context.get("won", true)))


func test_terminal_actions_only_emit_host_requests_and_do_not_apply_rewards() -> void:
	api.call("set_currency_balance", 100)
	var started: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var attempt_id: String = str(started.context.get("attempt_id", ""))
	api.call("complete_level", attempt_id, 250, {"goal_reached": false}, {"actions": [{"id": "use_life", "label": "Use a life"}]})
	watch_signals(api)
	var requested: MetaPlayResult = api.call("request_terminal_action", attempt_id, &"use_life") as MetaPlayResult
	var rejected: MetaPlayResult = api.call("request_terminal_action", attempt_id, &"revive") as MetaPlayResult
	assert_eq(requested.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(rejected.status, MetaPlayResult.Status.REJECTED)
	assert_eq(rejected.code, &"result.action_not_offered")
	assert_eq(api.call("get_currency_balance"), 100)
	assert_signal_emit_count(api, "terminal_action_requested", 1)
	assert_eq(get_signal_args(api, "terminal_action_requested", 0), [attempt_id, &"use_life"])


func test_public_api_does_not_expose_screen_navigation_commands_or_signals() -> void:
	assert_false(api.has_signal("navigation_requested"))
	assert_false(api.has_signal("screen_requested"))
	assert_false(api.has_method("request_home_screen"))
	assert_false(api.has_method("request_level_selection_screen"))
	assert_false(api.has_method("request_store_screen"))
	assert_false(api.has_method("request_settings_screen"))
	assert_false(api.has_method("set_optional_section_available"))
	assert_false(api.has_method("is_optional_section_available"))


func test_host_can_resume_a_failed_attempt_without_a_life_or_reward_operation() -> void:
	watch_signals(api)
	var started: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var attempt_id: String = str(started.context.get("attempt_id", ""))
	var active_attempt_resume: MetaPlayResult = api.call("resume_level_attempt", attempt_id) as MetaPlayResult
	assert_eq(active_attempt_resume.status, MetaPlayResult.Status.REJECTED)
	assert_eq(active_attempt_resume.code, &"attempt.stale")
	api.call("complete_level", attempt_id, 250, {"goal_reached": false})
	var model: MetaPlayModel = api.get("_model") as MetaPlayModel
	var prior_attempt: Dictionary = (model.attempts[attempt_id] as Dictionary).duplicate(true)
	var result: MetaPlayResult = api.call("resume_level_attempt", attempt_id) as MetaPlayResult
	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_true(bool(result.context.get("resumed", false)))
	var resumed_attempt: Dictionary = model.attempts[attempt_id] as Dictionary
	assert_eq(resumed_attempt.get("status"), "active")
	assert_eq(resumed_attempt.get("result"), prior_attempt.get("result"), "Resume changes only attempt status.")
	assert_eq(resumed_attempt.get("completion"), prior_attempt.get("completion"), "Resume preserves the reported result payload.")
	var duplicate_resume: MetaPlayResult = api.call("resume_level_attempt", attempt_id) as MetaPlayResult
	assert_eq(duplicate_resume.code, &"attempt.stale", "A resume request only transitions a failed attempt once.")
	assert_signal_emit_count(api, "level_attempt_completed", 1)
	assert_false(api.has_method("revive_after_reward"))
	assert_false(api.has_method("use_life"))
	assert_false(api.has_signal("life_use_requested"))
	assert_false(api.has_signal("revive_reward_claimed"))
	assert_false(api.has_signal("modal_lose_use_life_pressed"))
	var completed_again: MetaPlayResult = api.call("complete_level", attempt_id, 950, {"goal_reached": true}) as MetaPlayResult
	assert_eq(completed_again.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(completed_again.context.get("outcome"), "won")


func test_campaign_selection_emits_host_intent_without_loading_and_generic_load_ignores_availability() -> void:
	watch_signals(api)
	var selected: MetaPlayResult = api.call("select_level", "first") as MetaPlayResult
	var locked: MetaPlayResult = api.call("select_level", "second") as MetaPlayResult
	var unknown: MetaPlayResult = api.call("select_level", "missing") as MetaPlayResult
	assert_eq(selected.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(locked.code, &"level.selection_not_allowed")
	assert_eq(unknown.code, &"level.not_found")
	assert_signal_emit_count(api, "level_selection_requested", 1)
	assert_signal_emit_count(api, "level_load_started", 0)
	var request: MetaPlayResult = api.call("request_level_load_result", "second") as MetaPlayResult
	assert_eq(request.status, MetaPlayResult.Status.ACCEPTED, "Load API validates resource data, not host campaign authorization.")
	assert_true(await wait_until(func() -> bool: return not bool(api.call("is_loading"))))
	assert_signal_emit_count(api, "level_load_completed", 1)


func test_campaign_projection_validation_is_atomic_and_order_is_host_defined() -> void:
	var invalid: MetaPlayResult = api.call("configure_campaign_projection", [
		{"key": "first", "available": true, "selectable": true},
		{"key": "second", "available": false, "selectable": true},
	]) as MetaPlayResult
	assert_eq(invalid.status, MetaPlayResult.Status.REJECTED)
	assert_eq(invalid.code, &"campaign.projection_invalid")
	assert_eq(api.call("get_campaign_projection"), [
		{"key": "first", "available": true, "selectable": true},
		{"key": "second", "available": false, "selectable": false},
	])


func test_session_snapshot_v4_contains_kit_state_but_not_host_owned_lives() -> void:
	var started: MetaPlayResult = api.call("begin_level_attempt", "first") as MetaPlayResult
	var attempt_id: String = str(started.context.get("attempt_id", ""))
	api.call("complete_level", attempt_id, 950, {"goal_reached": true})
	api.call("configure_settings", {"sfx": false, "music": true})
	var exported: MetaPlayResult = api.call("export_session_state") as MetaPlayResult
	var snapshot: Dictionary = exported.context.get("snapshot", {}) as Dictionary
	var progression: Dictionary = snapshot.get("progression", {}) as Dictionary
	var features: Dictionary = snapshot.get("features", {}) as Dictionary
	assert_eq(snapshot.get("schema_version"), 4)
	assert_eq(progression.get("level_progress"), {"first": {"completed": true, "best_score": 950, "best_stars": 3}, "second": {"completed": false, "best_score": 0, "best_stars": 0}})
	assert_false(progression.has("levels"), "The kit snapshot does not persist host catalog or availability policy.")
	assert_eq(features.keys().size(), 2, "Only kit-owned completion and purchase records are included.")
	assert_false(features.has("lives"), "Host-owned life balances are not part of the kit snapshot.")
	assert_false(api.has_method("set_session_feature_state"))
	assert_false(api.has_method("get_session_feature_state"))
	features["lives"] = {"balance": 3}
	snapshot["features"] = features
	api.call("configure_campaign_projection", [{"key": "first", "available": false, "selectable": false}, {"key": "second", "available": true, "selectable": true}])
	api.call("configure_settings", {"sfx": true})
	var restored: MetaPlayResult = api.call("restore_session_state", snapshot) as MetaPlayResult
	assert_eq(restored.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(api.call("get_campaign_projection"), [{"key": "first", "available": false, "selectable": false}, {"key": "second", "available": true, "selectable": true}])
	assert_eq(api.call("get_level_progress", "first"), {"completed": true, "best_score": 950, "best_stars": 3})
	assert_false(bool((api.call("get_settings") as Dictionary).get("sfx", true)))
	var reexported: MetaPlayResult = api.call("export_session_state") as MetaPlayResult
	var reexported_snapshot: Dictionary = reexported.context.get("snapshot", {}) as Dictionary
	assert_false((reexported_snapshot.get("features", {}) as Dictionary).has("lives"), "Unrecognized host feature data is not retained by the kit.")


func test_snapshot_rejects_missing_progress_keys_and_legacy_versions_atomically() -> void:
	var malformed: Dictionary = {"schema_version": 3, "progression": {"level_progress": {"unregistered": {"completed": false, "best_score": 0, "best_stars": 0}}}, "wallet": {"currency_balance": 10}, "settings": {}, "inventory": {"items": {}}, "features": {"level_completion": {"version": 1, "attempts": {}, "reward_claims": {}, "last_base_reward_claimed_at": {}, "attempt_sequence": 0}}}
	var invalid: MetaPlayResult = api.call("restore_session_state", malformed) as MetaPlayResult
	var old_version: MetaPlayResult = api.call("restore_session_state", {"schema_version": 2}) as MetaPlayResult
	assert_eq(invalid.code, &"session.snapshot_invalid")
	assert_eq(old_version.code, &"session.snapshot_unsupported")
	assert_eq(api.call("get_level_progress", "first"), {"completed": false, "best_score": 0, "best_stars": 0})


func test_host_must_explicitly_choose_start_and_next_levels() -> void:
	var missing_start: MetaPlayResult = api.call("start_or_resume_game") as MetaPlayResult
	var start: MetaPlayResult = api.call("start_or_resume_game", "first") as MetaPlayResult
	assert_eq(missing_start.status, MetaPlayResult.Status.REJECTED)
	assert_eq(start.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(await wait_until(func() -> bool: return not bool(api.call("is_loading"))))
	var missing_next: MetaPlayResult = api.call("load_next_level") as MetaPlayResult
	var explicit_next: MetaPlayResult = api.call("request_next_level_load", "second") as MetaPlayResult
	assert_eq(missing_next.status, MetaPlayResult.Status.REJECTED)
	assert_eq(explicit_next.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(await wait_until(func() -> bool: return not bool(api.call("is_loading"))))
