class_name LevelCampaignPanel
extends VBoxContainer

signal level_selection_requested(level_key: Variant)

const UI: GDScript = preload("res://addons/metaplay_kit/runtime/ui/ui_factory.gd")

var _ui_presentation_config: MetaPlayUIConfig = MetaPlayUIConfig.new()


func _init() -> void:
	_ui_presentation_config = TtpGuiApi._get_ui_presentation_config_for_component()


func present_campaign(entries: Array, progress_by_level: Dictionary, level_catalog: Dictionary) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", _ui_presentation_config.section_spacing)
	var campaign_grid: GridContainer = GridContainer.new()
	campaign_grid.name = "CampaignGrid"
	campaign_grid.columns = _ui_presentation_config.campaign_columns
	campaign_grid.add_theme_constant_override("h_separation", _ui_presentation_config.component_spacing)
	campaign_grid.add_theme_constant_override("v_separation", _ui_presentation_config.component_spacing)
	campaign_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(campaign_grid)
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var level_key: Variant = entry.get("key")
		var level: Dictionary = level_catalog.get(level_key, {}) as Dictionary
		var progress: Dictionary = progress_by_level.get(level_key, {}) as Dictionary
		var completed: bool = bool(progress.get("completed", false))
		var state_label: String = "Completed" if completed else ("Available" if bool(entry.get("available", false)) else "Locked")
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Level_%s" % str(level_key).to_pascal_case()
		row.add_theme_constant_override("separation", _ui_presentation_config.component_spacing)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		campaign_grid.add_child(row)
		var button: Button = UI.button("%s  ·  %s" % [str(level.get("name", level_key)), state_label], func() -> void: level_selection_requested.emit(level_key), _ui_presentation_config.campaign_button_size)
		button.disabled = not bool(entry.get("selectable", false))
		button.name = "Select_%s" % str(level_key).to_pascal_case()
		button.add_theme_color_override("font_color", _ui_presentation_config.primary_color)
		row.add_child(button)
		var score_label: Label = UI.label("★ %d   Score %d" % [int(progress.get("best_stars", 0)), int(progress.get("best_score", 0))], _ui_presentation_config.body_font_size, _ui_presentation_config.muted_text_color)
		score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(score_label)
