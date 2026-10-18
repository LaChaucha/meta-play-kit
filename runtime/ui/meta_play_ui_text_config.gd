class_name MetaPlayUITextConfig
extends Resource

## Empty values use the kit's documented English fallback. The host supplies
## resolved strings for its active language; the kit does not select a locale.
@export_group("Campaign")
@export var campaign_completed_label: String = ""
@export var campaign_available_label: String = ""
@export var campaign_locked_label: String = ""
@export var campaign_score_format: String = ""

@export_group("Level result")
@export var result_success_title: String = ""
@export var result_failure_title: String = ""
@export var result_score_format: String = ""
@export var continue_action_label: String = ""

@export_group("Store item")
@export var item_fallback_title: String = ""
@export var item_equipped_label: String = ""
@export var item_owned_label: String = ""


func resolve(value: String, fallback: String) -> String:
	return fallback if value.strip_edges().is_empty() else value


func format_campaign_score(score: int) -> String:
	var format_value: String = resolve(campaign_score_format, "★ {stars}   Score {score}")
	return format_value.replace("{score}", str(score))


func format_result_score(score: int) -> String:
	var format_value: String = resolve(result_score_format, "Score: {score}")
	return format_value.format({"score": score})


func normalize() -> void:
	if not campaign_score_format.strip_edges().is_empty() and (not campaign_score_format.contains("{score}") or not campaign_score_format.contains("{stars}")):
		push_warning("MetaPlayUITextConfig field 'campaign_score_format' must include {score} and {stars}; using its default.")
		campaign_score_format = ""
	if not result_score_format.strip_edges().is_empty() and not result_score_format.contains("{score}"):
		push_warning("MetaPlayUITextConfig field 'result_score_format' must include {score}; using its default.")
		result_score_format = ""
