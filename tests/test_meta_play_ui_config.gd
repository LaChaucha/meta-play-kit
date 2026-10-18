extends "res://addons/metaplay_kit/tests/test_case.gd"

const ApiScript: GDScript = preload("res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd")
const StoreItemButtonScript: GDScript = preload("res://addons/metaplay_kit/runtime/components/store_item_button.gd")

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
	host_profile.text.campaign_locked_label = "Bloqueado"
	api.call("configure_ui_presentation", host_profile)
	var normalized_profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_eq(normalized_profile.body_font_size, 18)
	assert_eq(normalized_profile.campaign_columns, 2)
	assert_eq(normalized_profile.screen_horizontal_margin, 72)
	assert_eq(normalized_profile.text.campaign_locked_label, "Bloqueado")
	assert_eq(host_profile.body_font_size, 100)
	assert_eq(host_profile.text.campaign_locked_label, "Bloqueado")


func test_optional_text_fields_use_english_fallbacks_and_validate_score_placeholders() -> void:
	var text_config: MetaPlayUITextConfig = MetaPlayUITextConfig.new()
	assert_eq(text_config.resolve(text_config.campaign_locked_label, "Locked"), "Locked")
	assert_eq(text_config.format_result_score(125), "Score: 125")
	text_config.result_score_format = "Puntos"
	text_config.normalize()
	assert_eq(text_config.format_result_score(125), "Score: 125")


func test_host_project_texture_can_be_supplied_as_a_typed_kit_asset_override() -> void:
	var host_profile: MetaPlayUIConfig = MetaPlayUIConfig.new()
	var host_texture: Texture2D = load("res://addons/metaplay_kit/assets/ui/star_on.png") as Texture2D
	assert_not_null(host_texture)
	host_profile.active_star_texture = host_texture
	api.call("configure_ui_presentation", host_profile)
	var stored_profile: MetaPlayUIConfig = api.call("get_ui_presentation_config") as MetaPlayUIConfig
	assert_not_null(stored_profile.active_star_texture)
	assert_eq(stored_profile.active_star_texture.resource_path, host_texture.resource_path)


func test_store_item_loads_an_optional_texture_from_the_host_project_path() -> void:
	var item_button: StoreItemButton = StoreItemButtonScript.new() as StoreItemButton
	item_button.set_item({
		"title": "Host item",
		"icon_path": "res://addons/metaplay_kit/assets/ui/star_on.png",
	}, "host_item")
	assert_not_null(item_button.icon)
	assert_eq(item_button.icon.resource_path, "res://addons/metaplay_kit/assets/ui/star_on.png")
	item_button.free()


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
