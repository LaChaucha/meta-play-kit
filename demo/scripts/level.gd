class_name MetaPlayDemoLevel
extends Node

## Minimal host-game level used to exercise the kit's integration contract.
## The UI owns the buttons; this node owns the simulated gameplay lifecycle.

signal started()
signal stopped()
signal won()
signal lost()
signal revived()

var stage: Node = null
var level_key: Variant = null
var active: bool = false
var attempt_id: String = ""


func configure(new_level_key: Variant, host_stage: Node) -> void:
	level_key = new_level_key
	stage = host_stage


func configure_attempt(new_attempt_id: String) -> void:
	attempt_id = new_attempt_id


func start_level() -> bool:
	active = true
	started.emit()
	return true


func stop_level() -> void:
	active = false
	stopped.emit()


func level_win() -> void:
	if not active:
		return
	stop_level()
	won.emit()
	if stage != null and stage.has_method("level_win"):
		stage.call("level_win", attempt_id, 1250, {"goal_reached": true})


func level_lose() -> void:
	if not active:
		return
	stop_level()
	lost.emit()
	if stage != null and stage.has_method("level_lose"):
		stage.call("level_lose", attempt_id, 450, {"goal_reached": false})


func revive() -> void:
	active = true
	revived.emit()
