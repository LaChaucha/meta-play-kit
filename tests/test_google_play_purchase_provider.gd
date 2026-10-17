extends "res://tests/test_case.gd"

const ProviderScript: GDScript = preload("res://addons/metaplay_kit/runtime/platform/google_play_purchase_provider.gd")

class FakePayments extends RefCounted:
	var purchased_products: Array[String] = []
	var consumed_products: Array[String] = []

	func purchase(product_key: Variant) -> void:
		purchased_products.append(str(product_key))

	func consume(product_key: Variant) -> void:
		consumed_products.append(str(product_key))


var provider: Node
var signing_key: CryptoKey
var crypto: Crypto


func before_each() -> void:
	provider = add_child_autofree(ProviderScript.new()) as Node
	crypto = Crypto.new()
	signing_key = crypto.generate_rsa(2048)
	var configuration: MetaPlayResult = provider.call(
		"configure_license_public_key",
		signing_key.save_to_string(true)
	) as MetaPlayResult
	assert_eq(configuration.status, MetaPlayResult.Status.COMPLETED)


func test_google_play_signed_purchase_is_verified_and_correlated() -> void:
	watch_signals(provider)
	var receipt: String = _signed_receipt("coins_small", 0, "play-token-1")
	var signature: String = _signature_for(receipt)
	var verification: Dictionary = provider.call("_verify_signed_purchase", receipt, signature, "coins_small") as Dictionary
	assert_true(bool(verification.get("ok", false)), str(verification))
	provider.set("_active_operation_id", 42)
	provider.set("_active_product_key", "coins_small")
	provider.call("purchase_success", receipt, signature, "coins_small", 42)
	assert_signal_emitted_with(provider, "purchase_succeeded", [42, {
		"provider": "google_play",
		"verified": true,
		"verification": "google_play_signature",
		"product_key": "coins_small",
		"transaction_id": "play-token-1",
		"purchase_state": 0,
		"purchase_time": 1700000000000,
		"acknowledged": false,
		"receipt": receipt,
		"signature": signature,
	}])
	assert_eq(provider.get("_active_operation_id"), 0)


func test_invalid_signature_and_product_mismatch_never_succeed() -> void:
	watch_signals(provider)
	var receipt: String = _signed_receipt("coins_small", 0, "play-token-2")
	provider.set("_active_operation_id", 51)
	provider.set("_active_product_key", "coins_small")
	provider.call("purchase_success", receipt, Marshalls.raw_to_base64(PackedByteArray([1, 2, 3])), "coins_small", 51)
	assert_signal_emitted_with(provider, "purchase_failed", [51, &"purchase.signature_invalid"])
	assert_signal_emit_count(provider, "purchase_succeeded", 0)

	provider.set("_active_operation_id", 52)
	provider.set("_active_product_key", "coins_small")
	provider.call("purchase_success", _signed_receipt("coins_large", 0, "play-token-3"), _signature_for(_signed_receipt("coins_large", 0, "play-token-3")), "coins_large", 52)
	assert_signal_emitted_with(provider, "purchase_failed", [52, &"purchase.product_mismatch"])
	assert_signal_emit_count(provider, "purchase_succeeded", 0)


func test_pending_purchase_is_reported_without_closing_operation() -> void:
	watch_signals(provider)
	var receipt: String = _signed_receipt("coins_small", 2, "play-token-pending")
	provider.set("_active_operation_id", 61)
	provider.set("_active_product_key", "coins_small")
	provider.call("purchase_success", receipt, _signature_for(receipt), "coins_small", 61)
	assert_signal_emit_count(provider, "purchase_pending", 1)
	assert_signal_emit_count(provider, "purchase_succeeded", 0)
	assert_eq(provider.get("_active_operation_id"), 61)


func test_restore_reports_only_verified_purchased_records() -> void:
	watch_signals(provider)
	var purchased_receipt: String = _signed_receipt("coins_small", 0, "restore-token")
	var pending_receipt: String = _signed_receipt("coins_large", 2, "pending-token")
	provider.call("has_purchased", purchased_receipt, _signature_for(purchased_receipt), "coins_small")
	provider.call("has_purchased", pending_receipt, _signature_for(pending_receipt), "coins_large")
	provider.call("finish_restore")
	var restored_args: Array = get_signal_args(provider, "purchases_restored")
	assert_eq(restored_args.size(), 1)
	var restored: Array = restored_args[0] as Array
	assert_eq(restored.size(), 1)
	assert_eq((restored[0] as Dictionary).get("transaction_id"), "restore-token")


func test_purchase_adapter_consumes_only_when_host_requests_it_after_grant() -> void:
	watch_signals(provider)
	var payments: FakePayments = FakePayments.new()
	provider.set("_payments", payments)
	provider.call("begin_purchase", "coins_small", 72)
	assert_eq(payments.purchased_products, ["coins_small"])
	var receipt: String = _signed_receipt("coins_small", 0, "consume-token")
	provider.call("purchase_success", receipt, _signature_for(receipt), "coins_small", 72)
	provider.call("consume_purchase", {
		"product_key": "coins_small",
		"transaction_id": "consume-token",
	})
	assert_eq(payments.consumed_products, ["coins_small"])
	provider.call("consume_success", "", "", "coins_small")
	assert_signal_emitted_with(provider, "purchase_consumption_completed", ["consume-token", true])


func _signed_receipt(product_key: String, purchase_state: int, transaction_id: String) -> String:
	return JSON.stringify({
		"productId": product_key,
		"purchaseState": purchase_state,
		"purchaseToken": transaction_id,
		"purchaseTime": 1700000000000,
		"acknowledged": false,
	})


func _signature_for(receipt: String) -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA1)
	hashing.update(receipt.to_utf8_buffer())
	return Marshalls.raw_to_base64(crypto.sign(HashingContext.HASH_SHA1, hashing.finish(), signing_key))
