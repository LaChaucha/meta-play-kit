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


func configure(new_level_key: Variant, host_stage: Node) -> void:
	level_key = new_level_key
	stage = host_stage


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
		stage.call("level_win", level_key, 3, 1250, 120)


func level_lose() -> void:
	if not active:
		return
	stop_level()
	lost.emit()
	if stage != null and stage.has_method("level_lose"):
		stage.call("level_lose", level_key)


func revive() -> void:
	active = true
	revived.emit()
