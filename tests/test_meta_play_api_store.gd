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


func test_currency_purchase_operations_are_correlated_and_credit_only_after_confirmation() -> void:
	watch_signals(api)
	var started: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var concurrent: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	assert_eq(started.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(started.operation_id > 0)
	assert_eq(started.context.get("product_key"), "coins_small")
	assert_eq(concurrent.status, MetaPlayResult.Status.REJECTED)
	assert_eq(concurrent.code, &"purchase.in_progress")
	assert_eq(concurrent.operation_id, 0)
	assert_eq(api.call("get_currency_balance"), 100)
	assert_signal_emit_count(api, "currency_purchase_result", 0)

	var confirmed: MetaPlayResult = _call_result(
		"complete_currency_purchase", [started.operation_id, "coins_small"]
	)
	assert_eq(confirmed.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(confirmed.operation_id, started.operation_id)
	assert_true(bool(confirmed.context.get("provider_confirmed", false)))
	assert_eq(api.call("get_currency_balance"), 100, "The operation result does not credit an entitlement implicitly.")
	assert_signal_emit_count(api, "currency_purchase_result", 1)
	var late_duplicate: MetaPlayResult = _call_result(
		"complete_currency_purchase", [started.operation_id, "coins_small"]
	)
	assert_eq(late_duplicate.status, MetaPlayResult.Status.REJECTED)
	assert_eq(late_duplicate.code, &"purchase.operation_stale")
	assert_signal_emit_count(api, "currency_purchase_result", 1)

	var credited: MetaPlayResult = _call_result("credit_currency_product", ["coins_small"])
	assert_eq(credited.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(api.call("get_currency_balance"), 600)


func test_currency_purchase_failure_and_cancellation_are_distinct_terminal_results() -> void:
	watch_signals(api)
	var first: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var failed: MetaPlayResult = _call_result("fail_currency_purchase", [first.operation_id])
	assert_eq(failed.status, MetaPlayResult.Status.FAILED)
	assert_eq(failed.operation_id, first.operation_id)
	assert_eq(failed.code, &"purchase.provider_failed")
	assert_eq(api.call("get_currency_balance"), 100)

	var second: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	assert_eq(second.status, MetaPlayResult.Status.ACCEPTED)
	assert_true(second.operation_id > first.operation_id)
	var cancelled: MetaPlayResult = _call_result("cancel_currency_purchase", [second.operation_id])
	assert_eq(cancelled.status, MetaPlayResult.Status.CANCELLED)
	assert_eq(cancelled.operation_id, second.operation_id)
	assert_eq(cancelled.code, &"")
	assert_eq(api.call("get_currency_balance"), 100)
	assert_signal_emit_count(api, "currency_purchase_result", 2)


func test_currency_purchase_rejects_unknown_products_and_mismatched_confirmation() -> void:
	watch_signals(api)
	var unknown: MetaPlayResult = _call_result("begin_currency_purchase", ["unknown_pack"])
	assert_eq(unknown.status, MetaPlayResult.Status.REJECTED)
	assert_eq(unknown.code, &"currency.product_not_found")
	assert_signal_emit_count(api, "currency_purchase_result", 0)

	var started: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var mismatch: MetaPlayResult = _call_result(
		"complete_currency_purchase", [started.operation_id, "another_product"]
	)
	assert_eq(mismatch.status, MetaPlayResult.Status.FAILED)
	assert_eq(mismatch.operation_id, started.operation_id)
	assert_eq(mismatch.code, &"purchase.product_mismatch")
	assert_eq(mismatch.context.get("confirmed_product_key"), "another_product")
	assert_eq(api.call("get_currency_balance"), 100)
	assert_signal_emit_count(api, "currency_purchase_result", 1)


func test_legacy_notification_helper_uses_explicit_aliases_and_rejects_unknown_events() -> void:
	watch_signals(api)
	var supported: MetaPlayResult = _call_result("send_notification_ui", ["new_total_coins", 250])
	var unsupported: MetaPlayResult = _call_result("send_notification_ui", ["not_a_signal", 250])
	var invalid_arguments: MetaPlayResult = _call_result("send_notification_ui", ["new_total_coins", "250"])
	assert_eq(supported.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(supported.context.get("event_name"), "new_total_coins")
	assert_eq(unsupported.status, MetaPlayResult.Status.REJECTED)
	assert_eq(unsupported.code, &"api.event_unsupported")
	assert_eq(invalid_arguments.code, &"api.event_arguments_invalid")
	assert_signal_emit_count(api, "new_total_coins", 1)
	assert_signal_emit_count(api, "currency_balance_changed", 0, "Legacy aliases do not duplicate semantic signals.")


func _call_result(method_name: String, arguments: Array) -> MetaPlayResult:
	var raw_result: Variant = api.callv(method_name, arguments)
	return raw_result as MetaPlayResult
