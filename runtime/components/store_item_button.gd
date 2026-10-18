class_name StoreItemButton
extends Button

signal item_selected(item_key: Variant)

var enable: bool = true
var on_sell: bool = true
var item_key: Variant = null
var item_data: Dictionary = {}
var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()


func _init() -> void:
	_ui_presentation_config = TtpGuiApi._get_ui_presentation_config_for_component()


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, _ui_presentation_config.store_item_height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pressed.connect(_on_pressed)


func is_enabled() -> Variant:
	return enable


func get_on_sell() -> Variant:
	return on_sell


func disabled_button(status: bool = true) -> void:
	disabled = status
	enable = not status


func add_point_in_number(value: String) -> String:
	var formatted: String = ""
	for index: int in range(value.length()):
		if index > 0 and (value.length() - index) % 3 == 0:
			formatted += "."
		formatted += value[index]
	return formatted


func set_texture_item(texture_path: String) -> void:
	if texture_path.strip_edges().is_empty():
		icon = null
		return
	if not texture_path.begins_with("res://"):
		push_warning("StoreItemButton asset field 'icon_path' must reference a res:// project resource; no icon will be shown.")
		icon = null
		return
	if not ResourceLoader.exists(texture_path):
		push_warning("StoreItemButton asset field 'icon_path' references a missing project resource '%s'; no icon will be shown." % texture_path)
		icon = null
		return
	var loaded_resource: Resource = load(texture_path)
	var texture: Texture2D = loaded_resource as Texture2D
	if texture == null:
		push_warning("StoreItemButton asset field 'icon_path' could not load a Texture2D from '%s'; no icon will be shown." % texture_path)
		icon = null
		return
	icon = texture
	expand_icon = true


func set_title(title: Variant, color_value: Variant) -> void:
	if title != null:
		text = str(title)
	if color_value != null:
		add_theme_color_override("font_color", Color.from_string(str(color_value), Color.WHITE))


func set_description(description: Variant) -> void:
	tooltip_text = "" if description == null else str(description)


func set_price(price_text: String, color_value: String) -> void:
	text += "  ·  %s" % price_text
	add_theme_color_override("font_color", Color.from_string(color_value, Color.WHITE))


func set_backgroud(_texture_path: Variant) -> void:
	pass


func set_item(data_item: Dictionary, id_button: Variant) -> void:
	item_data = data_item.duplicate(true)
	item_key = id_button.duplicate() if id_button is Array else id_button
	on_sell = not bool(item_data.get("bought", false))
	var title: String = str(item_data.get("title", ""))
	if title.strip_edges().is_empty():
		title = _ui_presentation_config.text.resolve(_ui_presentation_config.text.item_fallback_title, "Item")
	var description: String = str(item_data.get("description", ""))
	var price: String = str(item_data.get("price", ""))
	var suffix: String = ""
	if bool(item_data.get("load", false)):
		suffix = "  ·  %s" % _ui_presentation_config.text.resolve(_ui_presentation_config.text.item_equipped_label, "Equipped")
	elif bool(item_data.get("bought", false)):
		suffix = "  ·  %s" % _ui_presentation_config.text.resolve(_ui_presentation_config.text.item_owned_label, "Owned")
	elif not price.is_empty():
		suffix = "  ·  %s" % price
	text = title + suffix
	tooltip_text = description
	var raw_icon_path: Variant = item_data.get("icon_path", "")
	set_texture_item("" if raw_icon_path == null else str(raw_icon_path))


func _on_pressed() -> void:
	item_selected.emit(item_key)
