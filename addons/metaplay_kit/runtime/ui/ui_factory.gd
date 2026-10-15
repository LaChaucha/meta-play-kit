class_name MetaPlayUIFactory
extends RefCounted


static func label(
		text_value: String,
		font_size: int = 20,
		color_value: Color = Color.WHITE,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
	) -> Label:
	var result: Label = Label.new()
	result.text = text_value
	result.horizontal_alignment = alignment
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color_value)
	result.autowrap_mode = TextServer.AUTOWRAP_OFF
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func button(
		text_value: String,
		callback: Callable,
		minimum_size: Vector2 = Vector2(180.0, 54.0),
		icon_texture: Texture2D = null
	) -> Button:
	var result: Button = Button.new()
	result.text = text_value
	result.custom_minimum_size = minimum_size
	result.focus_mode = Control.FOCUS_ALL
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if icon_texture != null:
		result.icon = icon_texture
		result.expand_icon = true
	result.pressed.connect(callback)
	return result


static func spacer() -> Control:
	var result: Control = Control.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func panel(minimum_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var result: PanelContainer = PanelContainer.new()
	result.custom_minimum_size = minimum_size
	return result


static func h_separator() -> HSeparator:
	var result: HSeparator = HSeparator.new()
	result.custom_minimum_size = Vector2(0.0, 2.0)
	return result
