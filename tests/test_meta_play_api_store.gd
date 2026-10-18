extends "res://addons/metaplay_kit/tests/test_case.gd"

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
		"complete_currency_purchase", [started.operation_id, "coins_small", {
			"provider": "host_test",
			"verified": true,
			"product_key": "coins_small",
			"transaction_id": "play-token-1",
		}]
	)
	assert_eq(confirmed.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(confirmed.operation_id, started.operation_id)
	assert_true(bool(confirmed.context.get("verified", false)))
	assert_eq(api.call("get_currency_balance"), 100, "The operation result does not credit an entitlement implicitly.")
	assert_signal_emit_count(api, "currency_purchase_result", 1)
	var late_duplicate: MetaPlayResult = _call_result(
		"complete_currency_purchase", [started.operation_id, "coins_small", {
			"provider": "host_test",
			"verified": true,
			"product_key": "coins_small",
			"transaction_id": "play-token-1",
		}]
	)
	assert_eq(late_duplicate.status, MetaPlayResult.Status.REJECTED)
	assert_eq(late_duplicate.code, &"purchase.operation_stale")
	assert_signal_emit_count(api, "currency_purchase_result", 1)

	var credited: MetaPlayResult = _call_result("apply_verified_currency_purchase", [started.operation_id])
	assert_eq(credited.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(api.call("get_currency_balance"), 600)
	var duplicate_credit: MetaPlayResult = _call_result("apply_verified_currency_purchase", [started.operation_id])
	assert_eq(duplicate_credit.code, &"purchase.not_verified", "A completed operation can be applied only once.")
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
		"complete_currency_purchase", [started.operation_id, "another_product", {}]
	)
	assert_eq(mismatch.status, MetaPlayResult.Status.FAILED)
	assert_eq(mismatch.operation_id, started.operation_id)
	assert_eq(mismatch.code, &"purchase.product_mismatch")
	assert_eq(mismatch.context.get("confirmed_product_key"), "another_product")
	assert_eq(api.call("get_currency_balance"), 100)
	var payload_mismatch_start: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var payload_mismatch: MetaPlayResult = _call_result("complete_currency_purchase", [payload_mismatch_start.operation_id, "coins_small", {
		"provider": "host_test",
		"verified": true,
		"transaction_id": "wrong-product-token",
		"product_key": "coins_large",
	}])
	assert_eq(payload_mismatch.status, MetaPlayResult.Status.FAILED)
	assert_eq(payload_mismatch.code, &"purchase.product_mismatch")
	assert_eq(api.call("get_currency_balance"), 100)
	assert_signal_emit_count(api, "currency_purchase_result", 2)


func test_currency_purchase_requires_verified_provider_result_and_snapshot_deduplicates_transaction() -> void:
	watch_signals(api)
	var started: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var rejected: MetaPlayResult = _call_result("complete_currency_purchase", [started.operation_id, "coins_small", {
		"provider": "google_play",
		"verified": false,
		"product_key": "coins_small",
		"transaction_id": "unverified-token",
	}])
	assert_eq(rejected.status, MetaPlayResult.Status.FAILED)
	assert_eq(rejected.code, &"purchase.not_verified")
	assert_eq(api.call("get_currency_balance"), 100)

	var accepted: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var completed: MetaPlayResult = _call_result("complete_currency_purchase", [accepted.operation_id, "coins_small", {
		"provider": "google_play",
		"verified": true,
		"product_key": "coins_small",
		"transaction_id": "persistent-play-token",
	}])
	assert_eq(completed.status, MetaPlayResult.Status.COMPLETED)
	var applied: MetaPlayResult = _call_result("apply_verified_currency_purchase", [accepted.operation_id])
	assert_eq(applied.context.get("currency_balance"), 600)
	var export_result: MetaPlayResult = _call_result("export_session_state", [])
	var snapshot: Dictionary = export_result.context.get("snapshot", {}) as Dictionary
	assert_eq(snapshot.get("schema_version"), 4)
	var restore_result: MetaPlayResult = _call_result("restore_session_state", [snapshot])
	assert_eq(restore_result.status, MetaPlayResult.Status.COMPLETED)
	var replayed_start: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var replayed_complete: MetaPlayResult = _call_result("complete_currency_purchase", [replayed_start.operation_id, "coins_small", {
		"provider": "google_play",
		"verified": true,
		"product_key": "coins_small",
		"transaction_id": "persistent-play-token",
	}])
	assert_eq(replayed_complete.status, MetaPlayResult.Status.COMPLETED)
	var replayed: MetaPlayResult = _call_result("apply_verified_currency_purchase", [replayed_start.operation_id])
	assert_true(bool(replayed.context.get("duplicate", false)))
	assert_eq(api.call("get_currency_balance"), 600)
	var other_store_start: MetaPlayResult = _call_result("begin_currency_purchase", ["coins_small"])
	var other_store_completion: MetaPlayResult = _call_result("complete_currency_purchase", [other_store_start.operation_id, "coins_small", {
		"provider": "another_market",
		"verified": true,
		"product_key": "coins_small",
		"transaction_id": "persistent-play-token",
	}])
	assert_eq(other_store_completion.status, MetaPlayResult.Status.COMPLETED)
	var other_store_grant: MetaPlayResult = _call_result("apply_verified_currency_purchase", [other_store_start.operation_id])
	assert_false(bool(other_store_grant.context.get("duplicate", false)), "Provider-scoped transaction keys must not collide across stores.")
	assert_eq(api.call("get_currency_balance"), 1100)
	assert_signal_emit_count(api, "currency_purchase_result", 4)


func test_restored_google_play_purchase_requires_a_verified_restore_record_and_is_idempotent() -> void:
	watch_signals(api)
	var untrusted: MetaPlayResult = _call_result("apply_restored_currency_purchase", ["restore-token"])
	assert_eq(untrusted.code, &"purchase.not_verified")
	var restored: MetaPlayResult = _call_result("restore_purchase_records", [[{
		"provider": "google_play",
		"verified": true,
		"product_key": "coins_small",
		"transaction_id": "restore-token",
	}]])
	assert_eq(restored.status, MetaPlayResult.Status.COMPLETED)
	var first_apply: MetaPlayResult = _call_result("apply_restored_currency_purchase", ["restore-token"])
	assert_eq(first_apply.context.get("currency_balance"), 600)
	var duplicate_apply: MetaPlayResult = _call_result("apply_restored_currency_purchase", ["restore-token"])
	assert_true(bool(duplicate_apply.context.get("duplicate", false)))
	assert_eq(api.call("get_currency_balance"), 600)


func test_session_snapshot_v3_migrates_to_v4_with_empty_transaction_ledger() -> void:
	var exported: MetaPlayResult = _call_result("export_session_state", [])
	var snapshot: Dictionary = exported.context.get("snapshot", {}) as Dictionary
	snapshot["schema_version"] = 3
	var features: Dictionary = snapshot.get("features", {}) as Dictionary
	features.erase("purchase_transactions")
	snapshot["features"] = features
	var migrated: MetaPlayResult = _call_result("restore_session_state", [snapshot])
	assert_eq(migrated.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(migrated.context.get("schema_version"), 4)


func test_legacy_notification_helper_uses_explicit_aliases_and_rejects_unknown_events() -> void:
	watch_signals(api)
	var supported: MetaPlayResult = _call_result("send_notification_ui", ["new_total_coins", 250])
	var unsupported: MetaPlayResult = _call_result("send_notification_ui", ["not_a_signal", 250])
	var removed_life_alias: MetaPlayResult = _call_result("send_notification_ui", ["modal_lose_use_life_pressed", null])
	var invalid_arguments: MetaPlayResult = _call_result("send_notification_ui", ["new_total_coins", "250"])
	assert_eq(supported.status, MetaPlayResult.Status.COMPLETED)
	assert_eq(supported.context.get("event_name"), "new_total_coins")
	assert_eq(unsupported.status, MetaPlayResult.Status.REJECTED)
	assert_eq(unsupported.code, &"api.event_unsupported")
	assert_eq(removed_life_alias.code, &"api.event_unsupported")
	assert_eq(invalid_arguments.code, &"api.event_arguments_invalid")
	assert_signal_emit_count(api, "new_total_coins", 1)
	assert_signal_emit_count(api, "currency_balance_changed", 0, "Legacy aliases do not duplicate semantic signals.")


func test_host_item_icon_paths_remain_serializable_in_inventory_snapshots() -> void:
	api.call("configure_items", {
		"host_art_item": {
			"type": 0,
			"price": 10,
			"bought": false,
			"icon_path": "res://addons/metaplay_kit/assets/ui/icon_coin.png",
		},
	})
	var exported: MetaPlayResult = _call_result("export_session_state", [])
	assert_eq(exported.status, MetaPlayResult.Status.COMPLETED)
	var snapshot: Dictionary = exported.context.get("snapshot", {}) as Dictionary
	var inventory: Dictionary = snapshot.get("inventory", {}) as Dictionary
	var items: Dictionary = inventory.get("items", {}) as Dictionary
	var item: Dictionary = items.get("host_art_item", {}) as Dictionary
	assert_eq(item.get("icon_path"), "res://addons/metaplay_kit/assets/ui/icon_coin.png")


func _call_result(method_name: String, arguments: Array) -> MetaPlayResult:
	var raw_result: Variant = api.callv(method_name, arguments)
	return raw_result as MetaPlayResult
