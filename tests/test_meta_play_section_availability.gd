extends "res://tests/test_case.gd"

const ApiScript: GDScript = preload("res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd")
const SECTION_LEVELS: int = 0
const SECTION_STORE: int = 1
const SECTION_SETTINGS: int = 2

var api: Node


func before_each() -> void:
	api = add_child_autofree(ApiScript.new()) as Node
	watch_signals(api)


func test_optional_sections_are_enabled_by_default_and_requests_emit_navigation() -> void:
	var requests: Array[MetaPlayResult] = [
		api.call("request_level_selection_screen") as MetaPlayResult,
		api.call("request_store_screen") as MetaPlayResult,
		api.call("request_settings_screen") as MetaPlayResult,
	]
	assert_eq(requests.size(), 3)
	for result: MetaPlayResult in requests:
		assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(get_signal_emit_count(api, "navigation_requested"), 3)
	assert_signal_emitted_with(api, "navigation_requested", ["levels", {}])
	assert_signal_emitted_with(api, "navigation_requested", ["store", {}])
	assert_signal_emitted_with(api, "navigation_requested", ["settings", {}])


func test_host_profile_can_disable_an_optional_section_before_component_creation() -> void:
	var profile: MetaPlayUIConfig = MetaPlayUIConfig.new()
	profile.store_available = false
	api.call("configure_ui_presentation", profile)
	profile.store_available = true
	assert_false(api.call("is_optional_section_available", SECTION_STORE))
	var result: MetaPlayResult = api.call("request_store_screen") as MetaPlayResult
	assert_eq(result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(result.code, &"ui.section_unavailable")


func test_runtime_availability_updates_the_central_profile_after_components_initialize() -> void:
	api.call("_get_ui_presentation_config_for_component")
	var configured: MetaPlayResult = api.call("set_optional_section_available", SECTION_STORE, false) as MetaPlayResult
	assert_eq(configured.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(configured.context.get("section"), &"store")
	assert_false(api.call("is_optional_section_available", SECTION_STORE))
	var snapshot: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_false(snapshot.store_available)

	var restored: MetaPlayResult = api.call("set_optional_section_available", SECTION_STORE, true) as MetaPlayResult
	assert_eq(restored.status, MetaPlayResult.Status.COMPLETED)
	assert_true(api.call("is_optional_section_available", SECTION_STORE))


func test_host_campaign_selection_remains_available_when_level_screen_is_disabled() -> void:
	api.call("configure_levels", {"forest": {"name": "Forest"}})
	api.call("configure_campaign_projection", [{"key": "forest", "available": true, "selectable": true}])
	api.call("set_optional_section_available", SECTION_LEVELS, false)
	var result: MetaPlayResult = api.call("select_level", "forest") as MetaPlayResult
	assert_eq(result.status, MetaPlayResult.Status.COMPLETED)
	assert_signal_emitted_with(api, "level_selection_requested", ["forest"])
	assert_signal_not_emitted(api, "navigation_requested")


func test_disabled_optional_requests_are_rejected_without_emitting_navigation() -> void:
	api.call("set_optional_section_available", SECTION_LEVELS, false)
	api.call("set_optional_section_available", SECTION_STORE, false)
	api.call("set_optional_section_available", SECTION_SETTINGS, false)

	var requests: Array[MetaPlayResult] = [
		api.call("request_level_selection_screen") as MetaPlayResult,
		api.call("request_store_screen") as MetaPlayResult,
		api.call("request_settings_screen") as MetaPlayResult,
	]
	for index: int in range(requests.size()):
		assert_eq(requests[index].status, MetaPlayResult.Status.REJECTED)
		assert_eq(requests[index].code, &"ui.section_unavailable")
		assert_eq(requests[index].operation_id, 0)
		assert_eq(requests[index].context.get("section"), [&"levels", &"store", &"settings"][index])
	assert_signal_emit_count(api, "navigation_requested", 0)
	assert_signal_emit_count(api, "action_rejected", 3)


func test_disabling_section_blocks_new_requests_but_preserves_prior_and_core_navigation() -> void:
	var accepted: MetaPlayResult = api.call("request_store_screen") as MetaPlayResult
	assert_eq(accepted.status, MetaPlayResult.Status.COMPLETED)
	api.call("set_optional_section_available", SECTION_STORE, false)
	var rejected: MetaPlayResult = api.call("request_store_screen") as MetaPlayResult
	assert_eq(rejected.status, MetaPlayResult.Status.REJECTED)
	var home_result: MetaPlayResult = api.call("request_home_screen") as MetaPlayResult
	assert_eq(home_result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(get_signal_emit_count(api, "navigation_requested"), 2)
	assert_signal_emitted_with(api, "navigation_requested", ["store", {}])
	assert_signal_emitted_with(api, "navigation_requested", ["home", {}])


func test_legacy_config_destination_uses_settings_availability_policy() -> void:
	api.call("set_optional_section_available", SECTION_SETTINGS, false)
	var rejected: MetaPlayResult = api.call("show_panel_config", true) as MetaPlayResult
	assert_eq(rejected.status, MetaPlayResult.Status.REJECTED)
	assert_eq(rejected.code, &"ui.section_unavailable")
	assert_signal_not_emitted(api, "navigation_requested")
	assert_signal_emit_count(api, "action_rejected", 1)

	var home_result: MetaPlayResult = api.call("show_panel_config", false) as MetaPlayResult
	assert_eq(home_result.status, MetaPlayResult.Status.COMPLETED)
	assert_signal_emitted_with(api, "navigation_requested", ["home", {}])


func test_invalid_optional_section_returns_a_stable_rejection() -> void:
	var result: MetaPlayResult = api.call("set_optional_section_available", 99, false) as MetaPlayResult
	assert_eq(result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(result.code, &"ui.section_invalid")
	assert_eq(result.context.get("section"), 99)
