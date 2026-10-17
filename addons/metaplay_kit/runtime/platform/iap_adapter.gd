class_name IapAdapter
extends "res://addons/metaplay_kit/runtime/platform/purchase_provider_adapter.gd"

## Explicit deterministic desktop simulation. Production integrations should
## select GooglePlayPurchaseProvider or provide their own adapter.

signal consume_failed()
signal products_query_failed(message: String)
signal product_owned(product_key: Variant)
signal products_received(details: Dictionary)

var sku_details: Dictionary = {}
var auto_consume: bool = true
var _active_purchase_operation_id: int = 0


func set_auto_consume(auto: bool) -> void:
	auto_consume = auto


func request_purchased() -> void:
	purchases_restored.emit([])


func begin_purchase(item_name: Variant, operation_id: int) -> void:
	if operation_id <= 0 or _active_purchase_operation_id > 0:
		purchase_failed.emit(operation_id, &"purchase.in_progress")
		return
	_active_purchase_operation_id = operation_id
	if item_name == null or str(item_name).is_empty():
		purchase_fail(operation_id)
		return
	# The mock is visibly local and asynchronous; callers cannot mistake it for
	# a verified receipt, but the full store flow remains testable on desktop.
	call_deferred("purchase_success", str(item_name), operation_id)


func purchase_success(product_key: String, operation_id: int = 0) -> void:
	var resolved_operation_id: int = _resolve_purchase_operation_id(operation_id)
	if resolved_operation_id == _active_purchase_operation_id:
		_clear_active_purchase()
	purchase_succeeded.emit(resolved_operation_id, {
		"provider": "simulation",
		"verified": false,
		"simulated": true,
		"product_key": product_key,
		"transaction_id": "simulation:%s" % resolved_operation_id,
	})


func purchase_fail(operation_id: int = 0) -> void:
	var resolved_operation_id: int = _resolve_purchase_operation_id(operation_id)
	if resolved_operation_id == _active_purchase_operation_id:
		_clear_active_purchase()
	purchase_failed.emit(resolved_operation_id, &"purchase.provider_failed")


func purchase_cancel(operation_id: int = 0) -> void:
	var resolved_operation_id: int = _resolve_purchase_operation_id(operation_id)
	if resolved_operation_id == _active_purchase_operation_id:
		_clear_active_purchase()
	purchase_cancelled.emit(resolved_operation_id)


func _resolve_purchase_operation_id(operation_id: int) -> int:
	return operation_id if operation_id > 0 else _active_purchase_operation_id


func _clear_active_purchase() -> void:
	_active_purchase_operation_id = 0


func purchase_owned(sku: String) -> void:
	product_owned.emit(sku)


func consume(item_name: Variant) -> void:
	if item_name != null:
		consume_failed.emit()


func consume_all() -> void:
	pass


func consume_success(_receipt: String, _signature: String, _sku: String) -> void:
	pass


func consume_fail() -> void:
	consume_failed.emit()


func consume_not_required() -> void:
	pass


func sku_details_query(list: Variant) -> void:
	var requested: Array = list as Array if list is Array else []
	var mock_details: Dictionary = {}
	for sku: Variant in requested:
		mock_details[sku] = {"title": str(sku), "price": "SIMULADO"}
	call_deferred("sku_details_complete", mock_details)


func sku_details_complete(result: Dictionary) -> void:
	sku_details = result.duplicate(true)
	products_received.emit(sku_details.duplicate(true))


func sku_details_error(error_message: String) -> void:
	products_query_failed.emit(error_message)
