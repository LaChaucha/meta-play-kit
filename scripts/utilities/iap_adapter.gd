class_name IapAdapter
extends Node

## Small boundary around an optional Android GodotPayments singleton.
## Desktop/editor builds intentionally use an explicit deterministic mock.

signal purchased(product_key: Variant)
signal purchase_failed(message: String)
signal purchase_cancelled()
signal product_owned(product_key: Variant)
signal products_received(details: Dictionary)

var sku_details: Dictionary = {}
var auto_consume: bool = true
var _payments: Object = null


func _ready() -> void:
	if Engine.has_singleton("GodotPayments"):
		_payments = Engine.get_singleton("GodotPayments")


func set_auto_consume(auto: bool) -> void:
	auto_consume = auto
	if _payments != null and _payments.has_method("set_auto_consume"):
		_payments.call("set_auto_consume", auto)


func request_purchased() -> void:
	if _payments != null and _payments.has_method("request_purchased"):
		_payments.call("request_purchased")


func has_purchased(_receipt: String, _signature: String, sku: String) -> void:
	if not sku.is_empty():
		product_owned.emit(sku)


func purchase(item_name: Variant) -> void:
	if item_name == null or str(item_name).is_empty():
		purchase_failed.emit("Producto inválido.")
		return
	if _payments != null and _payments.has_method("purchase"):
		_payments.call("purchase", item_name)
		return
	# The mock is visibly local and asynchronous; callers cannot mistake it for
	# a verified receipt, but the full store flow remains testable on desktop.
	call_deferred("purchase_success", "mock-receipt", "mock-signature", str(item_name))


func purchase_success(_receipt: String, _signature: String, sku: String) -> void:
	purchased.emit(sku)


func purchase_fail() -> void:
	purchase_failed.emit("La compra no pudo completarse.")


func purchase_cancel() -> void:
	purchase_cancelled.emit()


func purchase_owned(sku: String) -> void:
	product_owned.emit(sku)


func consume(item_name: Variant) -> void:
	if item_name != null and _payments != null and _payments.has_method("consume"):
		_payments.call("consume", item_name)


func consume_all() -> void:
	if _payments != null and _payments.has_method("consume_all"):
		_payments.call("consume_all")


func consume_success(_receipt: String, _signature: String, _sku: String) -> void:
	pass


func consume_fail() -> void:
	purchase_failed.emit("No se pudo consumir la compra.")


func consume_not_required() -> void:
	pass


func sku_details_query(list: Variant) -> void:
	var requested: Array = list as Array if list is Array else []
	if _payments != null and _payments.has_method("sku_details_query"):
		_payments.call("sku_details_query", requested)
		return
	var mock_details: Dictionary = {}
	for sku: Variant in requested:
		mock_details[sku] = {"title": str(sku), "price": "SIMULADO"}
	call_deferred("sku_details_complete", mock_details)


func sku_details_complete(result: Dictionary) -> void:
	sku_details = result.duplicate(true)
	products_received.emit(sku_details.duplicate(true))


func sku_details_error(error_message: String) -> void:
	purchase_failed.emit(error_message)
