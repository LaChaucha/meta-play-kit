class_name DraggableComponent
extends ScrollContainer

signal item_pressed(item_key: Variant)

var items_on_sell: Array[StoreItemButton] = []
var items_not_on_sell: Array[StoreItemButton] = []
var _list: VBoxContainer = null
var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()


func _init() -> void:
	_ui_presentation_config = TtpGuiApi._get_ui_presentation_config_for_component()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", _ui_presentation_config.component_spacing)
	add_child(_list)


func reset_position() -> void:
	scroll_vertical = 0


func reset_items_loaded() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		child.queue_free()
	items_on_sell.clear()
	items_not_on_sell.clear()


func set_currency_items(items: Dictionary) -> void:
	reset_items_loaded()
	for product_key: Variant in items.keys():
		_create_button(items[product_key] as Dictionary, product_key)


func set_game_items(items: Dictionary) -> void:
	reset_items_loaded()
	for item_key: Variant in items.keys():
		var item: Dictionary = items[item_key] as Dictionary
		if int(item.get("type", 0)) == MetaPlayModel.ItemType.PHASE:
			var stages: Dictionary = item.get("stages", {}) as Dictionary
			for stage_key: Variant in stages.keys():
				var stage: Dictionary = stages[stage_key] as Dictionary
				if not bool(stage.get("bought", false)):
					_create_button(stage, [item_key, stage_key])
					break
		else:
			_create_button(item, [item_key])
	set_position_game_items()


func set_position_game_items() -> void:
	if _list == null:
		return
	for button: StoreItemButton in items_on_sell + items_not_on_sell:
		_list.move_child(button, _list.get_child_count() - 1)


func disabled_items(status: bool) -> void:
	for button: StoreItemButton in items_on_sell + items_not_on_sell:
		button.disabled_button(status)


func callback_items(_event: InputEvent, item_object: Node) -> void:
	var button: StoreItemButton = item_object as StoreItemButton
	if button != null:
		item_pressed.emit(button.item_key)


func calculate_drag_release_aceleration(
		release_y: float,
		press_y: float,
		release_time: int,
		press_time: int
	) -> float:
	var elapsed_ms: int = maxi(1, release_time - press_time)
	return (release_y - press_y) / float(elapsed_ms) * 1000.0


func move_screen(acceleration: float, release_y: float) -> void:
	scroll_vertical = maxi(0, int(float(scroll_vertical) - acceleration * 0.15 - release_y * 0.0))


func is_interactive_position(local_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local_position)


func _create_button(data_item: Dictionary, id_button: Variant) -> void:
	if _list == null:
		return
	var button: StoreItemButton = StoreItemButton.new()
	button.set_item(data_item, id_button)
	button.item_selected.connect(_on_item_selected)
	_list.add_child(button)
	if bool(data_item.get("bought", false)):
		items_not_on_sell.append(button)
	else:
		items_on_sell.append(button)


func _on_item_selected(item_key: Variant) -> void:
	item_pressed.emit(item_key)
