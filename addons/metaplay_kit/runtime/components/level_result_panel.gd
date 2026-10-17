class_name LevelResultPanel
extends PanelContainer

signal action_requested(attempt_id: String, action_id: StringName)

const UI: GDScript = preload("res://addons/metaplay_kit/runtime/ui/ui_factory.gd")
const StarRatingScript: GDScript = preload("res://addons/metaplay_kit/runtime/components/star_rating.gd")

var _attempt_id: String = ""
var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()


func _init() -> void:
	_ui_presentation_config = TtpGuiApi._get_ui_presentation_config_for_component()


func present_result(result: Dictionary) -> void:
	_attempt_id = str(result.get("attempt_id", ""))
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "ResultContent"
	content.add_theme_constant_override("separation", _ui_presentation_config.section_spacing)
	add_child(content)
	var won: bool = bool(result.get("won", false))
	var default_title: String = _ui_presentation_config.text.resolve(
		_ui_presentation_config.text.result_success_title if won else _ui_presentation_config.text.result_failure_title,
		"Level Complete" if won else "Level Failed"
	)
	var title: Label = UI.label(_host_text_or_default(result.get("title"), default_title), _ui_presentation_config.title_font_size, _ui_presentation_config.accent_color, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "ResultTitle"
	content.add_child(title)
	var stars: StarRating = StarRatingScript.new() as StarRating
	stars.name = "ResultStars"
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(stars)
	stars.update_modal(int(result.get("stars", 0)))
	content.add_child(UI.label(_ui_presentation_config.text.format_result_score(int(result.get("score", 0))), _ui_presentation_config.score_font_size, _ui_presentation_config.text_color, HORIZONTAL_ALIGNMENT_CENTER))
	var next_level: Variant = result.get("next_level")
	if next_level is Dictionary and not (next_level as Dictionary).is_empty():
		var next_data: Dictionary = next_level as Dictionary
		var continue_label: String = _ui_presentation_config.text.resolve(_ui_presentation_config.text.continue_action_label, "Continue")
		_add_action_button(content, _host_text_or_default(next_data.get("label"), continue_label), StringName(str(next_data.get("action_id", "next_level"))))
	var raw_actions: Variant = result.get("actions", [])
	if raw_actions is Array:
		for raw_action: Variant in raw_actions as Array:
			if raw_action is Dictionary:
				var action: Dictionary = raw_action as Dictionary
				var action_label: String = _host_text_or_default(action.get("label"), "")
				if not action_label.is_empty():
					_add_action_button(content, action_label, StringName(str(action.get("id", ""))))


func _add_action_button(content: VBoxContainer, label: String, action_id: StringName) -> void:
	if str(action_id).is_empty():
		return
	var button: Button = UI.button(label, func() -> void: action_requested.emit(_attempt_id, action_id))
	button.name = "Action_%s" % str(action_id).to_pascal_case()
	content.add_child(button)


func _host_text_or_default(value: Variant, fallback: String) -> String:
	if value == null or str(value).strip_edges().is_empty():
		return fallback
	return str(value)
