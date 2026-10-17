class_name BlockingBackground
extends ColorRect

signal dismissed()

var _disabled: bool = false
var _fade: Tween = null
var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()


func _init() -> void:
	_ui_presentation_config = TtpGuiApi._get_ui_presentation_config_for_component()


func _ready() -> void:
	color = Color(0.05, 0.02, 0.08, 0.72)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func show_background_color() -> void:
	visible = true
	_fade_to(1.0)


func remove_background_color() -> void:
	_fade_to(0.0)


func show_background(state: bool = true) -> void:
	if state:
		show_background_color()
	else:
		remove_background_color()


func set_disabled(status: bool) -> void:
	_disabled = status
	mouse_filter = Control.MOUSE_FILTER_IGNORE if status else Control.MOUSE_FILTER_STOP


func _fade_to(alpha: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_zero_approx(alpha):
		_fade.tween_callback(func() -> void: visible = false)


func _on_gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and not _disabled:
		dismissed.emit()
