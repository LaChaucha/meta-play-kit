class_name MetaPlayUIConfig
extends Resource

## Version of the serialized UI presentation profile contract.
const CURRENT_SCHEMA_VERSION: int = 1

@export_range(1, 2147483647, 1) var schema_version: int = CURRENT_SCHEMA_VERSION

## Colors used only by reusable MetaPlayKit controls.
@export var primary_color: Color = Color("7e3fca")
@export var accent_color: Color = Color("ffd23f")
@export var text_color: Color = Color("36131d")
@export var muted_text_color: Color = Color("806b79")
@export var modal_overlay_color: Color = Color(0.05, 0.02, 0.08, 0.72)

## Font sizes and spacing tokens, in logical viewport pixels.
@export_range(8, 48, 1) var body_font_size: int = 18
@export_range(12, 64, 1) var title_font_size: int = 34
@export_range(10, 48, 1) var score_font_size: int = 22
@export_range(0, 64, 1) var small_spacing: int = 6
@export_range(0, 96, 1) var component_spacing: int = 10
@export_range(0, 128, 1) var section_spacing: int = 14

## Bounds and arrangement tokens for kit-owned component content.
@export_range(0, 512, 1) var screen_horizontal_margin: int = 48
@export_range(0, 512, 1) var screen_vertical_margin: int = 32
@export_range(1, 3, 1) var campaign_columns: int = 1
@export var campaign_button_size: Vector2 = Vector2(360.0, 54.0)
@export_range(48, 256, 1) var store_item_height: int = 76
@export_range(16, 128, 1) var star_size: int = 48
@export_range(0, 64, 1) var star_spacing: int = 6
@export_range(0, 512, 1) var loading_progress_height: int = 28

## Optional host-provided text overrides. Empty fields use the kit's English defaults.
@export var text: MetaPlayUITextConfig = MetaPlayUITextConfig.new()

## Optional textures for supported kit-owned asset slots. Null keeps the kit default.
@export_group("Assets")
@export var active_star_texture: Texture2D
@export var inactive_star_texture: Texture2D
@export var loading_background_texture: Texture2D

## Availability affects only navigation requests made through MetaPlayKit.
@export_group("Optional section availability")
@export var level_selection_available: bool = true
@export var store_available: bool = true
@export var settings_available: bool = true


## Replaces invalid runtime values independently, preserving all other fields.
func normalize() -> void:
	var defaults: MetaPlayUIConfig = MetaPlayUIConfig.new()
	if text == null:
		push_warning("MetaPlayUIConfig field 'text' is invalid; using its default.")
		text = MetaPlayUITextConfig.new()
	else:
		text.normalize()
	_validate_texture_field("active_star_texture", active_star_texture)
	_validate_texture_field("inactive_star_texture", inactive_star_texture)
	_validate_texture_field("loading_background_texture", loading_background_texture)
	if not _valid_color(primary_color):
		push_warning("MetaPlayUIConfig field 'primary_color' is invalid; using its default.")
		primary_color = defaults.primary_color
	if not _valid_color(accent_color):
		push_warning("MetaPlayUIConfig field 'accent_color' is invalid; using its default.")
		accent_color = defaults.accent_color
	if not _valid_color(text_color):
		push_warning("MetaPlayUIConfig field 'text_color' is invalid; using its default.")
		text_color = defaults.text_color
	if not _valid_color(muted_text_color):
		push_warning("MetaPlayUIConfig field 'muted_text_color' is invalid; using its default.")
		muted_text_color = defaults.muted_text_color
	if not _valid_size(campaign_button_size):
		push_warning("MetaPlayUIConfig field 'campaign_button_size' is invalid; using its default.")
		campaign_button_size = defaults.campaign_button_size
	if not _valid_range(body_font_size, 8, 48):
		push_warning("MetaPlayUIConfig field 'body_font_size' is invalid; using its default.")
		body_font_size = defaults.body_font_size
	if not _valid_range(title_font_size, 12, 64):
		push_warning("MetaPlayUIConfig field 'title_font_size' is invalid; using its default.")
		title_font_size = defaults.title_font_size
	if not _valid_range(score_font_size, 10, 48):
		push_warning("MetaPlayUIConfig field 'score_font_size' is invalid; using its default.")
		score_font_size = defaults.score_font_size
	if not _valid_range(small_spacing, 0, 64):
		push_warning("MetaPlayUIConfig field 'small_spacing' is invalid; using its default.")
		small_spacing = defaults.small_spacing
	if not _valid_range(component_spacing, 0, 96):
		push_warning("MetaPlayUIConfig field 'component_spacing' is invalid; using its default.")
		component_spacing = defaults.component_spacing
	if not _valid_range(section_spacing, 0, 128):
		push_warning("MetaPlayUIConfig field 'section_spacing' is invalid; using its default.")
		section_spacing = defaults.section_spacing
	if not _valid_range(screen_horizontal_margin, 0, 512):
		push_warning("MetaPlayUIConfig field 'screen_horizontal_margin' is invalid; using its default.")
		screen_horizontal_margin = defaults.screen_horizontal_margin
	if not _valid_range(screen_vertical_margin, 0, 512):
		push_warning("MetaPlayUIConfig field 'screen_vertical_margin' is invalid; using its default.")
		screen_vertical_margin = defaults.screen_vertical_margin
	if not _valid_range(campaign_columns, 1, 3):
		push_warning("MetaPlayUIConfig field 'campaign_columns' is invalid; using its default.")
		campaign_columns = defaults.campaign_columns
	if not _valid_range(store_item_height, 48, 256):
		push_warning("MetaPlayUIConfig field 'store_item_height' is invalid; using its default.")
		store_item_height = defaults.store_item_height
	if not _valid_range(star_size, 16, 128):
		push_warning("MetaPlayUIConfig field 'star_size' is invalid; using its default.")
		star_size = defaults.star_size
	if not _valid_range(star_spacing, 0, 64):
		push_warning("MetaPlayUIConfig field 'star_spacing' is invalid; using its default.")
		star_spacing = defaults.star_spacing
	if not _valid_range(loading_progress_height, 0, 512):
		push_warning("MetaPlayUIConfig field 'loading_progress_height' is invalid; using its default.")
		loading_progress_height = defaults.loading_progress_height
	if not _valid_color(modal_overlay_color):
		push_warning("MetaPlayUIConfig field 'modal_overlay_color' is invalid; using its default.")
		modal_overlay_color = defaults.modal_overlay_color


func _valid_range(value: int, minimum: int, maximum: int) -> bool:
	return value >= minimum and value <= maximum


func _valid_size(value: Vector2) -> bool:
	return value.x >= 0.0 and value.y >= 0.0 and is_finite(value.x) and is_finite(value.y)


func _valid_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)


func _validate_texture_field(field_name: String, texture: Texture2D) -> void:
	if texture != null and not is_instance_valid(texture):
		push_warning("MetaPlayUIConfig field '%s' is invalid; using the kit default." % field_name)
