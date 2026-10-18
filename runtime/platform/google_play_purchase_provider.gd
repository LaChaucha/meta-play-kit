class_name GooglePlayPurchaseProvider
extends "res://addons/metaplay_kit/runtime/platform/purchase_provider_adapter.gd"

## Adapter for the optional GodotPayments Android singleton. Google Play's
## signed purchase JSON is verified locally with the app's Play Console key.
## Hosts can instead supply a provider adapter that performs server validation.

const PURCHASE_STATE_PURCHASED_LEGACY: int = 0
const PURCHASE_STATE_PURCHASED: int = 1
const PURCHASE_STATE_PENDING: int = 2
const ERROR_PROVIDER_UNAVAILABLE: StringName = &"purchase.provider_unavailable"
const ERROR_VERIFIER_NOT_CONFIGURED: StringName = &"purchase.verifier_not_configured"
const ERROR_SIGNATURE_INVALID: StringName = &"purchase.signature_invalid"
const ERROR_RECEIPT_INVALID: StringName = &"purchase.receipt_invalid"
const ERROR_PRODUCT_MISMATCH: StringName = &"purchase.product_mismatch"
const ERROR_OPERATION_STALE: StringName = &"purchase.operation_stale"

var _payments: Object = null
var _license_public_key: String = ""
var _active_operation_id: int = 0
var _active_product_key: String = ""
var _restored_purchases: Array = []
var _pending_consumptions: Array[Dictionary] = []


func _ready() -> void:
	if Engine.has_singleton("GodotPayments"):
		_payments = Engine.get_singleton("GodotPayments")
		if _payments.has_method("set_auto_consume"):
			_payments.call("set_auto_consume", false)


func configure_license_public_key(public_key: String) -> MetaPlayResult:
	var normalized_key: String = public_key.strip_edges()
	if normalized_key.is_empty():
		return MetaPlayResult.rejected(ERROR_VERIFIER_NOT_CONFIGURED)
	var key: CryptoKey = _load_public_key(normalized_key)
	if key == null:
		return MetaPlayResult.rejected(ERROR_VERIFIER_NOT_CONFIGURED)
	_license_public_key = normalized_key
	return MetaPlayResult.completed()


func begin_purchase(product_key: Variant, operation_id: int) -> void:
	if operation_id <= 0 or _active_operation_id > 0:
		purchase_failed.emit(operation_id, ERROR_OPERATION_STALE)
		return
	if _payments == null or not _payments.has_method("purchase"):
		purchase_failed.emit(operation_id, ERROR_PROVIDER_UNAVAILABLE)
		return
	if _license_public_key.is_empty():
		purchase_failed.emit(operation_id, ERROR_VERIFIER_NOT_CONFIGURED)
		return
	_active_operation_id = operation_id
	_active_product_key = str(product_key)
	if _active_product_key.is_empty():
		_clear_active_purchase()
		purchase_failed.emit(operation_id, ERROR_PRODUCT_MISMATCH)
		return
	_payments.call("purchase", _active_product_key)


func purchase_success(receipt: String, signature: String, sku: String, operation_id: int = 0) -> void:
	var resolved_operation_id: int = operation_id if operation_id > 0 else _active_operation_id
	if resolved_operation_id <= 0 or resolved_operation_id != _active_operation_id:
		purchase_failed.emit(resolved_operation_id, ERROR_OPERATION_STALE)
		return
	if sku != _active_product_key:
		_fail_active_purchase(ERROR_PRODUCT_MISMATCH)
		return
	var verified: Dictionary = _verify_signed_purchase(receipt, signature, sku)
	if not bool(verified.get("ok", false)):
		_fail_active_purchase(StringName(str(verified.get("code", ERROR_RECEIPT_INVALID))))
		return
	var purchase_data: Dictionary = verified.get("purchase", {}) as Dictionary
	var purchase_state: int = int(purchase_data.get("purchaseState", PURCHASE_STATE_PURCHASED_LEGACY))
	if purchase_state == PURCHASE_STATE_PENDING:
		purchase_pending.emit(resolved_operation_id, _normalized_purchase(purchase_data, receipt, signature))
		return
	_clear_active_purchase()
	purchase_succeeded.emit(resolved_operation_id, _normalized_purchase(purchase_data, receipt, signature))


func purchase_fail(operation_id: int = 0) -> void:
	var resolved_operation_id: int = operation_id if operation_id > 0 else _active_operation_id
	if resolved_operation_id == _active_operation_id:
		_clear_active_purchase()
	purchase_failed.emit(resolved_operation_id, &"purchase.provider_failed")


func purchase_cancel(operation_id: int = 0) -> void:
	var resolved_operation_id: int = operation_id if operation_id > 0 else _active_operation_id
	if resolved_operation_id == _active_operation_id:
		_clear_active_purchase()
	purchase_cancelled.emit(resolved_operation_id)


func restore_purchases() -> void:
	_restored_purchases.clear()
	if _payments == null or not _payments.has_method("request_purchased"):
		purchases_restored.emit([])
		return
	if _license_public_key.is_empty():
		purchase_failed.emit(0, ERROR_VERIFIER_NOT_CONFIGURED)
		return
	_payments.call("request_purchased")


func consume_purchase(purchase: Dictionary) -> void:
	var transaction_id: String = str(purchase.get("transaction_id", ""))
	var product_key: String = str(purchase.get("product_key", ""))
	if _payments == null or not _payments.has_method("consume") or transaction_id.is_empty() or product_key.is_empty():
		purchase_consumption_completed.emit(transaction_id, false)
		return
	_pending_consumptions.append({"transaction_id": transaction_id, "product_key": product_key})
	_payments.call("consume", product_key)


func consume_success(_receipt: String, _signature: String, sku: String) -> void:
	_finish_consumption_for_product(sku, true)


func consume_fail() -> void:
	if _pending_consumptions.is_empty():
		return
	var pending: Dictionary = _pending_consumptions.pop_front()
	purchase_consumption_completed.emit(str(pending.get("transaction_id", "")), false)


func consume_not_required() -> void:
	if _pending_consumptions.is_empty():
		return
	var pending: Dictionary = _pending_consumptions.pop_front()
	purchase_consumption_completed.emit(str(pending.get("transaction_id", "")), true)


## The native bridge calls this after its purchase query emits has_purchased()
## for each locally verified Play purchase.
func finish_restore() -> void:
	purchases_restored.emit(_restored_purchases.duplicate(true))


func has_purchased(receipt: String, signature: String, sku: String) -> void:
	var verified: Dictionary = _verify_signed_purchase(receipt, signature, sku)
	if not bool(verified.get("ok", false)):
		return
	var purchase_data: Dictionary = verified.get("purchase", {}) as Dictionary
	if int(purchase_data.get("purchaseState", PURCHASE_STATE_PURCHASED_LEGACY)) not in [PURCHASE_STATE_PURCHASED_LEGACY, PURCHASE_STATE_PURCHASED]:
		return
	_restored_purchases.append(_normalized_purchase(purchase_data, receipt, signature))


func _verify_signed_purchase(receipt: String, signature: String, sku: String) -> Dictionary:
	if _license_public_key.is_empty():
		return {"ok": false, "code": ERROR_VERIFIER_NOT_CONFIGURED}
	var key: CryptoKey = _load_public_key(_license_public_key)
	if key == null:
		return {"ok": false, "code": ERROR_VERIFIER_NOT_CONFIGURED}
	var signature_bytes: PackedByteArray = Marshalls.base64_to_raw(signature)
	if receipt.is_empty() or signature_bytes.is_empty():
		return {"ok": false, "code": ERROR_SIGNATURE_INVALID}
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA1) != OK or hashing.update(receipt.to_utf8_buffer()) != OK:
		return {"ok": false, "code": ERROR_SIGNATURE_INVALID}
	var digest: PackedByteArray = hashing.finish()
	if not Crypto.new().verify(HashingContext.HASH_SHA1, digest, signature_bytes, key):
		return {"ok": false, "code": ERROR_SIGNATURE_INVALID}
	var parsed: Variant = JSON.parse_string(receipt)
	if not parsed is Dictionary:
		return {"ok": false, "code": ERROR_RECEIPT_INVALID}
	var purchase: Dictionary = parsed as Dictionary
	if str(purchase.get("productId", "")) != sku:
		return {"ok": false, "code": ERROR_PRODUCT_MISMATCH}
	if not purchase.has("purchaseState"):
		return {"ok": false, "code": ERROR_RECEIPT_INVALID}
	var purchase_state: Variant = purchase.get("purchaseState")
	if not _is_integral_number(purchase_state) or int(purchase_state) not in [PURCHASE_STATE_PURCHASED_LEGACY, PURCHASE_STATE_PURCHASED, PURCHASE_STATE_PENDING]:
		return {"ok": false, "code": ERROR_RECEIPT_INVALID}
	if str(purchase.get("purchaseToken", "")).is_empty():
		return {"ok": false, "code": ERROR_RECEIPT_INVALID}
	purchase["purchaseState"] = int(purchase_state)
	var purchase_time: Variant = purchase.get("purchaseTime", 0)
	if _is_integral_number(purchase_time):
		purchase["purchaseTime"] = int(purchase_time)
	return {"ok": true, "purchase": purchase}


func _normalized_purchase(purchase: Dictionary, receipt: String, signature: String) -> Dictionary:
	return {
		"provider": "google_play",
		"verified": true,
		"verification": "google_play_signature",
		"product_key": str(purchase.get("productId", "")),
		"transaction_id": str(purchase.get("purchaseToken", "")),
		"purchase_state": int(purchase.get("purchaseState", PURCHASE_STATE_PURCHASED_LEGACY)),
		"purchase_time": int(purchase.get("purchaseTime", 0)),
		"acknowledged": bool(purchase.get("acknowledged", false)),
		"receipt": receipt,
		"signature": signature,
	}


func _load_public_key(public_key: String) -> CryptoKey:
	var pem: String = public_key
	if not pem.contains("-----BEGIN PUBLIC KEY-----"):
		var compact: String = pem.replace("\n", "").replace("\r", "").replace(" ", "")
		var wrapped: String = ""
		for offset: int in range(0, compact.length(), 64):
			wrapped += compact.substr(offset, 64) + "\n"
		pem = "-----BEGIN PUBLIC KEY-----\n%s-----END PUBLIC KEY-----\n" % wrapped
	var key: CryptoKey = CryptoKey.new()
	if key.load_from_string(pem, true) != OK:
		return null
	return key


func _is_integral_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))
	return false


func _fail_active_purchase(code: StringName) -> void:
	var operation_id: int = _active_operation_id
	_clear_active_purchase()
	purchase_failed.emit(operation_id, code)


func _finish_consumption_for_product(product_key: String, succeeded: bool) -> void:
	for index: int in range(_pending_consumptions.size()):
		var pending: Dictionary = _pending_consumptions[index]
		if str(pending.get("product_key", "")) != product_key:
			continue
		_pending_consumptions.remove_at(index)
		purchase_consumption_completed.emit(str(pending.get("transaction_id", "")), succeeded)
		return


func _clear_active_purchase() -> void:
	_active_operation_id = 0
	_active_product_key = ""
