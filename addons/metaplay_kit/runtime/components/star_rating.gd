class_name StarRating
extends HBoxContainer

const STAR_ON: Texture2D = preload("res://addons/metaplay_kit/assets/ui/star_on.png")
const STAR_OFF: Texture2D = preload("res://addons/metaplay_kit/assets/ui/star_off.png")

var _stars: Array[TextureRect] = []
var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()


func _init() -> void:
	_ui_presentation_config = TtpGuiApi._get_ui_presentation_config_for_component()


func _ready() -> void:
	add_theme_constant_override("separation", _ui_presentation_config.star_spacing)
	if _stars.is_empty():
		for index: int in range(3):
			var star: TextureRect = TextureRect.new()
			star.name = "Star%d" % (index + 1)
			star.custom_minimum_size = Vector2.ONE * _ui_presentation_config.star_size
			star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			star.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(star)
			_stars.append(star)
	update_modal(0)


func update_modal(quantity_star: int) -> void:
	var visible_stars: int = clampi(quantity_star, 0, 3)
	for index: int in range(_stars.size()):
		_stars[index].texture = STAR_ON if index < visible_stars else STAR_OFF
