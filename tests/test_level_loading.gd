extends "res://tests/test_case.gd"

const BatchScript: GDScript = preload("res://addons/metaplay_kit/runtime/systems/resource_batch.gd")
const LEVEL_PATH: String = "res://demo/scenes/level_stub.tscn"


func test_concurrent_level_request_is_rejected_and_selection_signals_follow_acceptance() -> void:
	TtpGuiApi.configure_levels({
		"first": {"name": "First", "enabled": true, "scene_path": LEVEL_PATH},
		"second": {"name": "Second", "enabled": true, "scene_path": LEVEL_PATH},
	})
	var rejected_messages: Array[String] = []
	var selected_levels: Array[Dictionary] = []
	var legacy_selected_levels: Array[Dictionary] = []
	var started_level_keys: Array[String] = []
	var play_events: Array[bool] = []
	var retry_events: Array[Dictionary] = []
	var next_level_events: Array[Dictionary] = []
	var started_operation_ids: Array[int] = []
	var rejected_callback: Callable = func(message: String) -> void: rejected_messages.append(message)
	var selected_callback: Callable = func(level_data: Dictionary) -> void: selected_levels.append(level_data)
	var legacy_selected_callback: Callable = func(level_data: Dictionary) -> void: legacy_selected_levels.append(level_data)
	var started_callback: Callable = func(operation_id: int, level_data: Dictionary) -> void:
		started_operation_ids.append(operation_id)
		started_level_keys.append(str(level_data.get("key", "")))
	var play_callback: Callable = func() -> void: play_events.append(true)
	var retry_callback: Callable = func(level_data: Dictionary) -> void: retry_events.append(level_data)
	var next_level_callback: Callable = func(level_data: Dictionary) -> void: next_level_events.append(level_data)
	TtpGuiApi.action_rejected.connect(rejected_callback)
	TtpGuiApi.level_selected.connect(selected_callback)
	TtpGuiApi.level_selector_load_new_level_selected.connect(legacy_selected_callback)
	TtpGuiApi.level_load_started.connect(started_callback)
	TtpGuiApi.play_requested.connect(play_callback)
	TtpGuiApi.home_tap_to_play_pressed.connect(play_callback)
	TtpGuiApi.level_retry_requested.connect(retry_callback)
	TtpGuiApi.modal_win_retry_button_pressed.connect(retry_callback)
	TtpGuiApi.modal_lose_retry_button_pressed.connect(retry_callback)
	TtpGuiApi.next_level_load_requested.connect(next_level_callback)
	TtpGuiApi.modal_win_load_next_level_pressed.connect(next_level_callback)
	var nested_request_results: Array[bool] = []
	var request_during_start: Callable = func(_operation_id: int, _level_data: Dictionary) -> void:
		TtpGuiApi.start_or_resume_game()
		TtpGuiApi.retry_level("second")
		TtpGuiApi.modal_win_retry_level("second")
		TtpGuiApi.modal_lose_retry_level("second")
		TtpGuiApi.load_next_level()
		TtpGuiApi.select_level("second")
		nested_request_results.append(TtpGuiApi.request_level_load("second"))
	TtpGuiApi.level_load_started.connect(request_during_start, CONNECT_ONE_SHOT)

	TtpGuiApi.select_level("first")
	assert_eq(nested_request_results, [false], "A reentrant request must be rejected before it can replace the active destination.")
	assert_eq(started_level_keys, ["first"])
	assert_eq(started_operation_ids.size(), 1, "Only the accepted request gets an operation ID.")
	assert_eq(rejected_messages.size(), 7)
	assert_eq(rejected_messages.back(), TtpGuiApi.LEVEL_LOAD_BUSY_MESSAGE)
	assert_eq(selected_levels.size(), 1, "Only the accepted selection should be announced.")
	assert_eq(legacy_selected_levels.size(), 1, "The legacy selection signal must also follow acceptance.")
	assert_true(play_events.is_empty(), "Rejected play requests must not emit semantic or legacy play signals.")
	assert_true(retry_events.is_empty(), "Rejected retries must not emit semantic or legacy retry signals.")
	assert_true(next_level_events.is_empty(), "Rejected progression requests must not emit semantic or legacy progression signals.")
	var selected_level: Dictionary = selected_levels[0]
	assert_eq(selected_level.get("name"), "First", "Only the accepted selection should be announced.")

	var first_finished: bool = await wait_until(func() -> bool: return not TtpGuiApi.is_loading())
	if not assert_true(first_finished, "The accepted request must eventually release the single-load slot."):
		_disconnect_load_arbitration_test_signals(rejected_callback, selected_callback, legacy_selected_callback, started_callback, play_callback, retry_callback, next_level_callback)
		return
	var first_resource: Resource = TtpGuiApi.get_loaded_resource(LEVEL_PATH)
	assert_is(first_resource, PackedScene)

	TtpGuiApi.select_level("second")
	assert_eq(selected_levels.size(), 2, "A new request should be accepted after the first operation finishes.")
	assert_eq(started_operation_ids.size(), 2)
	assert_ne(started_operation_ids[0], started_operation_ids[1], "Repeated scene requests get distinct operation IDs.")
	var second_finished: bool = await wait_until(func() -> bool: return not TtpGuiApi.is_loading())
	if not assert_true(second_finished):
		_disconnect_load_arbitration_test_signals(rejected_callback, selected_callback, legacy_selected_callback, started_callback, play_callback, retry_callback, next_level_callback)
		return
	var second_resource: Resource = TtpGuiApi.get_loaded_resource(LEVEL_PATH)
	assert_is(second_resource, PackedScene)
	_disconnect_load_arbitration_test_signals(rejected_callback, selected_callback, legacy_selected_callback, started_callback, play_callback, retry_callback, next_level_callback)


func _disconnect_load_arbitration_test_signals(
		rejected_callback: Callable,
		selected_callback: Callable,
		legacy_selected_callback: Callable,
		started_callback: Callable,
		play_callback: Callable,
		retry_callback: Callable,
		next_level_callback: Callable
	) -> void:
	TtpGuiApi.action_rejected.disconnect(rejected_callback)
	TtpGuiApi.level_selected.disconnect(selected_callback)
	TtpGuiApi.level_selector_load_new_level_selected.disconnect(legacy_selected_callback)
	TtpGuiApi.level_load_started.disconnect(started_callback)
	TtpGuiApi.play_requested.disconnect(play_callback)
	TtpGuiApi.home_tap_to_play_pressed.disconnect(play_callback)
	TtpGuiApi.level_retry_requested.disconnect(retry_callback)
	TtpGuiApi.modal_win_retry_button_pressed.disconnect(retry_callback)
	TtpGuiApi.modal_lose_retry_button_pressed.disconnect(retry_callback)
	TtpGuiApi.next_level_load_requested.disconnect(next_level_callback)
	TtpGuiApi.modal_win_load_next_level_pressed.disconnect(next_level_callback)


func test_invalid_or_locked_level_load_is_rejected_before_loading_starts() -> void:
	TtpGuiApi.configure_levels({
		"locked": {"name": "Locked", "enabled": false, "scene_path": LEVEL_PATH},
		"missing_path": {"name": "Missing path", "enabled": true, "scene_path": ""},
	})
	var rejected_messages: Array[String] = []
	var rejected_callback: Callable = func(message: String) -> void: rejected_messages.append(message)
	TtpGuiApi.action_rejected.connect(rejected_callback)

	assert_false(TtpGuiApi.request_level_load("locked"))
	assert_false(TtpGuiApi.request_level_load("missing_path"))
	assert_false(TtpGuiApi.request_level_load("unknown"))
	assert_false(TtpGuiApi.is_loading())
	assert_eq(rejected_messages.size(), 3)
	TtpGuiApi.action_rejected.disconnect(rejected_callback)


func test_failed_load_emits_one_correlated_terminal_event() -> void:
	allow_errors()
	TtpGuiApi.configure_levels({
		"missing": {"name": "Missing resource", "enabled": true, "scene_path": "user://missing-load-operation-test.tscn"},
	})
	var started_ids: Array[int] = []
	var completed_ids: Array[int] = []
	var failed_ids: Array[int] = []
	var terminal_loading_states: Array[bool] = []
	var started_callback: Callable = func(operation_id: int, _data: Dictionary) -> void: started_ids.append(operation_id)
	var completed_callback: Callable = func(operation_id: int, _data: Dictionary) -> void: completed_ids.append(operation_id)
	var failed_callback: Callable = func(operation_id: int, _data: Dictionary, _message: String) -> void:
		failed_ids.append(operation_id)
		terminal_loading_states.append(TtpGuiApi.is_loading())
	TtpGuiApi.level_load_started.connect(started_callback)
	TtpGuiApi.level_load_completed.connect(completed_callback)
	TtpGuiApi.level_load_failed.connect(failed_callback)
	assert_true(TtpGuiApi.request_level_load("missing"))
	var finished: bool = await wait_until(func() -> bool: return not TtpGuiApi.is_loading())
	assert_true(finished)
	assert_eq(started_ids.size(), 1)
	assert_eq(failed_ids, started_ids, "Failure must close the same accepted operation.")
	assert_true(completed_ids.is_empty(), "A failed operation must never emit success.")
	assert_eq(terminal_loading_states, [false], "The operation is closed before its terminal signal is delivered.")
	TtpGuiApi.level_load_started.disconnect(started_callback)
	TtpGuiApi.level_load_completed.disconnect(completed_callback)
	TtpGuiApi.level_load_failed.disconnect(failed_callback)


func test_successful_load_closes_operation_before_terminal_signal() -> void:
	TtpGuiApi.configure_levels({
		"first": {"name": "First", "enabled": true, "scene_path": LEVEL_PATH},
	})
	var started_ids: Array[int] = []
	var progress_ids: Array[int] = []
	var completed_ids: Array[int] = []
	var terminal_loading_states: Array[bool] = []
	var started_callback: Callable = func(operation_id: int, _data: Dictionary) -> void: started_ids.append(operation_id)
	var progress_callback: Callable = func(operation_id: int, _progress: float) -> void: progress_ids.append(operation_id)
	var completed_callback: Callable = func(operation_id: int, _data: Dictionary) -> void:
		completed_ids.append(operation_id)
		terminal_loading_states.append(TtpGuiApi.is_loading())
	TtpGuiApi.level_load_started.connect(started_callback)
	TtpGuiApi.loading_progress_changed.connect(progress_callback)
	TtpGuiApi.level_load_completed.connect(completed_callback)
	assert_true(TtpGuiApi.request_level_load("first"))
	var finished: bool = await wait_until(func() -> bool: return not TtpGuiApi.is_loading())
	assert_true(finished)
	assert_eq(started_ids.size(), 1)
	assert_eq(completed_ids, started_ids, "Success must close the same accepted operation.")
	assert_false(progress_ids.is_empty(), "The loader should report progress for an accepted operation.")
	for progress_id: int in progress_ids:
		assert_eq(progress_id, started_ids[0], "Progress must be correlated to the active operation.")
	assert_eq(terminal_loading_states, [false], "The operation is closed before its terminal signal is delivered.")
	TtpGuiApi.level_load_started.disconnect(started_callback)
	TtpGuiApi.loading_progress_changed.disconnect(progress_callback)
	TtpGuiApi.level_load_completed.disconnect(completed_callback)


func test_consumed_scene_can_be_loaded_again_for_next_level_and_retry() -> void:
	var batch: ResourceBatch = BatchScript.new()
	watch_signals(batch)
	for load_index: int in range(3):
		batch.add_resource_to_batch(LEVEL_PATH)
		batch.start_loading(0)
		var completed: bool = await wait_until(func() -> bool: return not batch.is_loading())
		if not assert_true(completed, "La carga %d debe finalizar." % load_index):
			batch.close()
			return
		var resource: Resource = batch.get_resource(LEVEL_PATH)
		assert_is(resource, PackedScene, "Cada carga debe entregar una escena instanciable.")
		assert_null(batch.get_resource(LEVEL_PATH), "La extracción consume sólo el resultado del lote actual.")
	assert_signal_emit_count(batch, "load_finished", 3)
	batch.close()


func test_uninstantiable_level_returns_home_without_showing_game() -> void:
	var stage: Node = add_scene("res://demo/scenes/main.tscn")
	var loading: Control = stage.get_node("LoadingOverlay") as Control
	var boot_completed: bool = await wait_until(func() -> bool: return not loading.visible)
	if not assert_true(boot_completed):
		return
	TtpGuiApi.configure_levels({
		"invalid_level": {"name": "Nivel inválido", "enabled": true, "scene_path": "res://icon.svg"},
	})
	TtpGuiApi.request_level_load("invalid_level")
	var load_completed: bool = await wait_until(func() -> bool: return not TtpGuiApi.is_loading())
	if not assert_true(load_completed):
		return
	assert_false(loading.visible, "Un fallo no debe dejar la pantalla de carga bloqueando la UI.")
	var game: Control = stage.get_node("Background/ScreenFrame/ScreenStack/GameScreen") as Control
	var home: Control = stage.get_node("Background/ScreenFrame/ScreenStack/HomeScreen") as Control
	assert_false(game.visible, "La pantalla de juego necesita una instancia válida.")
	assert_true(home.visible)
	assert_eq(stage.get("_current_level_key"), "level1", "Un fallo no debe cambiar el nivel activo.")
