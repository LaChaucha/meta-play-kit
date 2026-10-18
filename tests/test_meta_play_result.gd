extends "res://addons/metaplay_kit/tests/test_case.gd"


func test_synchronous_success_is_completed_without_error_code_or_operation_id() -> void:
	var result: MetaPlayResult = MetaPlayResult.completed()

	assert_true(result.is_valid())
	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(result.code, &"")
	assert_eq(result.operation_id, 0)


func test_rejected_action_has_stable_code_and_no_operation_id() -> void:
	var result: MetaPlayResult = MetaPlayResult.rejected(&"level.not_found", {"level_key": "missing"})

	assert_true(result.is_valid())
	assert_eq(result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(result.code, &"level.not_found")
	assert_eq(result.operation_id, 0)
	assert_eq(result.context, {"level_key": "missing"})


func test_async_results_preserve_the_accepted_operation_id() -> void:
	var accepted: MetaPlayResult = MetaPlayResult.accepted(7, {"action": "load_level"})
	var completed: MetaPlayResult = MetaPlayResult.completed(7, {"resource_path": "levels/level.tscn"})
	var failed: MetaPlayResult = MetaPlayResult.failed(8, &"load.failed", {"path": "levels/missing.tscn"})
	var cancelled: MetaPlayResult = MetaPlayResult.cancelled(9)

	assert_true(accepted.is_valid())
	assert_true(completed.is_valid())
	assert_true(failed.is_valid())
	assert_true(cancelled.is_valid())
	assert_eq(accepted.status, MetaPlayResult.Status.ACCEPTED)
	assert_eq(accepted.operation_id, 7)
	assert_eq(completed.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(completed.operation_id, accepted.operation_id)
	assert_eq(failed.status, MetaPlayResult.Status.FAILED)
	assert_eq(failed.operation_id, 8)
	assert_eq(failed.code, &"load.failed")
	assert_eq(cancelled.status, MetaPlayResult.Status.CANCELLED)
	assert_eq(cancelled.operation_id, 9)


func test_context_is_copied_when_received_and_when_exposed() -> void:
	var source_context: Dictionary = {"metadata": {"tags": ["original"]}}
	var result: MetaPlayResult = MetaPlayResult.accepted(3, source_context)
	source_context["metadata"]["tags"].append("source mutation")
	var exposed_context: Dictionary = result.context
	exposed_context["metadata"]["tags"].append("consumer mutation")

	assert_eq(result.context, {"metadata": {"tags": ["original"]}})
