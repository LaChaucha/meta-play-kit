extends "res://tests/test_case.gd"

const ApiScript: GDScript = preload("res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd")

var api: Node


func before_each() -> void:
	api = add_child_autofree(ApiScript.new()) as Node
	api.call("configure_items", {
		"owned_hat": {"type": 1, "price": 100, "bought": true, "load": true, "group": "hat"},
		"available_hat": {"type": 1, "price": 50, "bought": false, "load": false, "group": "hat"},
		"expensive_item": {"type": 0, "price": 250, "bought": false},
		"unowned_hat": {"type": 1, "price": 75, "bought": false, "load": false, "group": "hat"},
		"owned_trinket": {"type": 0, "price": 0, "bought": true},
		"phased_item": {"type": 2, "stages": {"phase1": {"price": 25, "bought": false}}},
	})
	api.call("configure_currency_rewards", {"coins_small": 500})
	api.call("set_currency_balance", 100)


func test_purchase_rejections_return_stable_codes_and_keep_wallet_and_inventory_unchanged() -> void:
	watch_signals(api)
	var unknown_result: MetaPlayResult = _call_result("purchase_item", [["missing"]])
	assert_eq(unknown_result.status, MetaPlayResult.Status.REJECTED)
	assert_eq(unknown_result.code, &"store.item_not_found")
	assert_eq(unknown_result.context.get("item_path"), ["missing"])

	var owned_result: MetaPlayResult = _call_result("purchase_item", [["owned_hat"]])
	assert_eq(owned_result.code, &"store.item_already_owned")
	assert_eq(owned_result.context.get("item_path"), ["owned_hat"])

	var insufficient_result: MetaPlayResult = _call_result("purchase_item", [["expensive_item"]])
	assert_eq(insufficient_result.code, &"wallet.insufficient_funds")
	assert_eq(insufficient_result.context.get("cost"), 250)
	assert_eq(insufficient_result.context.get("balance"), 100)
	assert_eq(int(api.call("get_currency_balance")), 100)
	var expensive_item: Dictionary = api.call("get_item", ["expensive_item"]) as Dictionary
	assert_false(bool(expensive_item.get("bought", false)))
	assert_signal_emit_count(api, "item_purchased", 0)
	assert_signal_emit_count(api, "action_rejected", 3)


func test_equip_rejections_distinguish_unknown_unowned_and_non_equippable_items() -> void:
	watch_signals(api)
	var unknown_result: MetaPlayResult = _call_result("equip_item", [["missing"]])
	var unowned_result: MetaPlayResult = _call_result("equip_item", [["unowned_hat"]])
	var non_equippable_result: MetaPlayResult = _call_result("equip_item", [["owned_trinket"]])
	assert_eq(unknown_result.code, &"store.item_not_found")
	assert_eq(unowned_result.code, &"store.item_not_owned")
	assert_eq(non_equippable_result.code, &"store.item_not_equippable")
	var owned_hat: Dictionary = api.call("get_item", ["owned_hat"]) as Dictionary
	var unowned_hat: Dictionary = api.call("get_item", ["unowned_hat"]) as Dictionary
	assert_true(bool(owned_hat.get("load", false)))
	assert_false(bool(unowned_hat.get("load", true)))
	assert_signal_emit_count(api, "item_equipped", 0)
	assert_signal_emit_count(api, "action_rejected", 3)


func test_successful_store_and_currency_commands_return_updated_snapshots() -> void:
	watch_signals(api)
	var purchase_result: MetaPlayResult = _call_result("purchase_item", [["available_hat"]])
	assert_eq(purchase_result.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(purchase_result.operation_id, 0)
	var purchased_item: Dictionary = purchase_result.context.get("item", {}) as Dictionary
	assert_true(bool(purchased_item.get("bought", false)))
	assert_eq(purchase_result.context.get("cost"), 50)
	assert_eq(purchase_result.context.get("currency_balance"), 50)

	var equip_result: MetaPlayResult = _call_result("equip_item", [["available_hat"]])
	assert_eq(equip_result.status, MetaPlayResult.Status.COMPLETED)
	var equipped_item: Dictionary = equip_result.context.get("item", {}) as Dictionary
	assert_true(bool(equipped_item.get("load", false)))
	var old_hat: Dictionary = api.call("get_item", ["owned_hat"]) as Dictionary
	assert_false(bool(old_hat.get("load", true)))

	var missing_currency: MetaPlayResult = _call_result("credit_currency_product", ["unknown_pack"])
	assert_eq(missing_currency.status, MetaPlayResult.Status.REJECTED)
	assert_eq(missing_currency.code, &"currency.product_not_found")
	assert_eq(missing_currency.context.get("product_key"), "unknown_pack")
	assert_eq(int(api.call("get_currency_balance")), 50)

	var credited_currency: MetaPlayResult = _call_result("credit_currency_product", ["coins_small"])
	assert_eq(credited_currency.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(credited_currency.context.get("currency_added"), 500)
	assert_eq(credited_currency.context.get("currency_balance"), 550)
	assert_signal_emit_count(api, "item_purchased", 1)
	assert_signal_emit_count(api, "item_equipped", 1)
	assert_signal_emit_count(api, "currency_product_credited", 1)
	assert_signal_emit_count(api, "action_rejected", 1)


func _call_result(method_name: String, arguments: Array) -> MetaPlayResult:
	var raw_result: Variant = api.callv(method_name, arguments)
	return raw_result as MetaPlayResult
