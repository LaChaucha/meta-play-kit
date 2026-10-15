extends "res://tests/test_case.gd"

const ModelScript: GDScript = preload("res://scripts/core/meta_play_model.gd")
const LevelScript: GDScript = preload("res://scripts/demo/level.gd")

var model: MetaPlayModel


func before_each() -> void:
	model = ModelScript.new()
	model.set_levels({
		"level1": {"enabled": true, "max_stars": 0, "max_score": 0},
		"level2": {"enabled": false, "max_stars": 0, "max_score": 0},
	})
	model.set_game_items({
		"sun_hat": {
			"title": "Sombrero solar",
			"price": 0,
			"bought": true,
			"load": true,
			"group": "hat",
		},
		"space_hat": {
			"title": "Casco espacial",
			"price": "450",
			"bought": false,
			"load": false,
			"group": "hat",
		},
		"trail": {
			"title": "Estela dorada",
			"price": "250",
			"bought": false,
		},
	})
	model.set_coin_values({"coins_small": 500})
	model.set_coins(800)


func test_purchase_debits_the_wallet_and_marks_the_item_as_owned() -> void:
	watch_signals(model)
	var result: Dictionary = model.purchase_game_item(["trail"])

	assert_true(bool(result.get("ok", false)))
	assert_eq(model.coins, 550)
	assert_true(bool(model.get_store_item(["trail"]).get("bought", false)))
	assert_signal_emitted_with(model, "coins_changed", [550])
	assert_signal_emitted(model, "store_changed")


func test_failed_purchase_never_changes_or_overdraws_the_wallet() -> void:
	model.set_coins(100)
	var result: Dictionary = model.purchase_game_item(["space_hat"])

	assert_false(bool(result.get("ok", true)))
	assert_eq(model.coins, 100)
	assert_false(bool(model.get_store_item(["space_hat"]).get("bought", true)))


func test_equipping_an_item_is_exclusive_within_its_group() -> void:
	model.purchase_game_item(["space_hat"])
	var result: Dictionary = model.equip_item(["space_hat"])

	assert_true(bool(result.get("ok", false)))
	assert_false(bool(model.get_store_item(["sun_hat"]).get("load", true)))
	assert_true(bool(model.get_store_item(["space_hat"]).get("load", false)))


func test_level_completion_keeps_records_unlocks_next_and_grants_reward() -> void:
	var result: Dictionary = model.complete_level("level1", 2, 1250, 120, "level2")

	assert_true(bool(result.get("ok", false)))
	assert_eq(model.get_level("level1").get("max_stars"), 2)
	assert_eq(model.get_level("level1").get("max_score"), 1250)
	assert_true(bool(model.get_level("level2").get("enabled", false)))
	assert_eq(model.coins, 920)
	assert_eq(model.get_next_level_to_play(), "level2")


func test_currency_product_and_number_formatting() -> void:
	var result: Dictionary = model.add_currency_product("coins_small")

	assert_true(bool(result.get("ok", false)))
	assert_eq(model.coins, 1300)
	assert_eq(model.format_number(model.coins), "1.300")
	assert_eq(model.format_number(-1250000), "-1.250.000")


func test_configuration_toggles_emit_the_updated_snapshot() -> void:
	watch_signals(model)
	assert_false(model.toggle_sfx())
	assert_false(model.toggle_music())
	assert_signal_emit_count(model, "configuration_changed", 2)
	var snapshot: Dictionary = get_signal_args(model, "configuration_changed")[0]
	assert_false(bool(snapshot.get("music", true)))


func test_demo_level_has_a_safe_start_stop_and_revive_lifecycle() -> void:
	var level: MetaPlayDemoLevel = add_child_autofree(LevelScript.new()) as MetaPlayDemoLevel
	watch_signals(level)
	level.configure("level1", null)
	level.start_level()
	assert_true(level.active)
	assert_signal_emitted(level, "started")
	level.stop_level()
	assert_false(level.active)
	assert_signal_emitted(level, "stopped")
	level.revive()
	assert_true(level.active)
	assert_signal_emitted(level, "revived")
