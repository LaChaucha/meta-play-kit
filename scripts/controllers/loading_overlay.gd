class_name LoadingOverlay
extends Control

var progress_bar: ProgressBar = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func update_progress(progress: float) -> void:
	if progress_bar != null:
		progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0


func load_finished() -> void:
	update_progress(1.0)


func load_level(_resource_to_load: String) -> void:
	visible = true
	update_progress(0.0)


func start_loading() -> void:
	visible = true


func complete_loading() -> void:
	visible = false


func _build() -> void:
	var background: TextureRect = TextureRect.new()
	background.name = "LoadingBackground"
	background.texture = preload("res://art/ui/loading_background.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var bottom: MarginContainer = MarginContainer.new()
	bottom.name = "ProgressMargin"
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.add_theme_constant_override("margin_left", 160)
	bottom.add_theme_constant_override("margin_right", 160)
	bottom.add_theme_constant_override("margin_bottom", 84)
	add_child(bottom)

	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(0.0, 28.0)
	progress_bar.show_percentage = false
	bottom.add_child(progress_bar)
