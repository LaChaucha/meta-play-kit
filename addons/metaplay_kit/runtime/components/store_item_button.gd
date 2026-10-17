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
	custom_minimum_size = Vector2(0.0, 76.0)
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


func set_texture_item(texture_path: Variant) -> void:
	if texture_path == null or str(texture_path).is_empty():
		icon = null
		return
	icon = load(str(texture_path)) as Texture2D
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
	var title: String = str(item_data.get("title", "Artículo"))
	var description: String = str(item_data.get("description", ""))
	var price: String = str(item_data.get("price", ""))
	var suffix: String = ""
	if bool(item_data.get("load", false)):
		suffix = "  ·  EQUIPADO"
	elif bool(item_data.get("bought", false)):
		suffix = "  ·  ADQUIRIDO"
	elif not price.is_empty():
		suffix = "  ·  %s" % price
	text = title + suffix
	tooltip_text = description


func _on_pressed() -> void:
	item_selected.emit(item_key)
