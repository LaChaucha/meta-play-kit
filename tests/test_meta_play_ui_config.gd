extends "res://tests/test_case.gd"

const ApiScript: GDScript = preload("res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd")

var api: Node


func before_each() -> void:
	api = add_child_autofree(ApiScript.new()) as Node


func test_api_uses_internal_ui_profile_defaults_when_none_is_configured() -> void:
	var profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_not_null(profile)
	assert_eq(profile.schema_version, MetaPlayUIConfig.CURRENT_SCHEMA_VERSION)


func test_configured_profile_is_copied_and_getter_returns_an_isolated_snapshot() -> void:
	var host_profile: MetaPlayUIConfig = MetaPlayUIConfig.new()
	api.call("configure_ui_presentation", host_profile)
	var stored_profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_ne(stored_profile.get_instance_id(), host_profile.get_instance_id())

	host_profile.schema_version = 9
	assert_eq(stored_profile.schema_version, MetaPlayUIConfig.CURRENT_SCHEMA_VERSION)

	stored_profile.schema_version = 8
	var next_snapshot: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_eq(next_snapshot.schema_version, MetaPlayUIConfig.CURRENT_SCHEMA_VERSION)
	assert_ne(next_snapshot.get_instance_id(), stored_profile.get_instance_id())


func test_unsupported_schema_version_warns_and_falls_back_to_the_supported_field_value() -> void:
	var host_profile: MetaPlayUIConfig = MetaPlayUIConfig.new()
	host_profile.schema_version = 99
	api.call("configure_ui_presentation", host_profile)
	var normalized_profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_eq(normalized_profile.schema_version, MetaPlayUIConfig.CURRENT_SCHEMA_VERSION)
	assert_eq(host_profile.schema_version, 99)


func test_component_style_fields_are_typed_and_invalid_values_fall_back_independently() -> void:
	var host_profile: MetaPlayUIConfig = MetaPlayUIConfig.new()
	host_profile.body_font_size = 100
	host_profile.campaign_columns = 2
	host_profile.screen_horizontal_margin = 72
	api.call("configure_ui_presentation", host_profile)
	var normalized_profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_eq(normalized_profile.body_font_size, 18)
	assert_eq(normalized_profile.campaign_columns, 2)
	assert_eq(normalized_profile.screen_horizontal_margin, 72)
	assert_eq(host_profile.body_font_size, 100)


func test_first_component_query_locks_the_profile_for_v1() -> void:
	api.call("_get_ui_presentation_config_for_component")
	var later_profile: MetaPlayUIConfig = MetaPlayUIConfig.new()
	later_profile.schema_version = 99
	api.call("configure_ui_presentation", later_profile)
	var active_profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_eq(active_profile.schema_version, MetaPlayUIConfig.CURRENT_SCHEMA_VERSION)


func test_components_can_be_created_after_ui_profile_registration() -> void:
	var component_scripts: Array[String] = [
		"res://addons/metaplay_kit/runtime/components/blocking_background.gd",
		"res://addons/metaplay_kit/runtime/components/draggable_component.gd",
		"res://addons/metaplay_kit/runtime/components/level_campaign_panel.gd",
		"res://addons/metaplay_kit/runtime/components/level_result_panel.gd",
		"res://addons/metaplay_kit/runtime/components/star_rating.gd",
		"res://addons/metaplay_kit/runtime/components/store_item_button.gd",
		"res://addons/metaplay_kit/runtime/ui/loading_overlay.gd",
	]
	for script_path: String in component_scripts:
		var component_script: GDScript = load(script_path) as GDScript
		assert_not_null(component_script, "Could not load UI component: %s" % script_path)
		var component: Node = component_script.new() as Node
		assert_not_null(component, "Could not instantiate UI component: %s" % script_path)
		component.free()
