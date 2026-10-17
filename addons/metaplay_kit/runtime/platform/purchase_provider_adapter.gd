class_name PurchaseProviderAdapter
extends Node

## Provider-neutral lifecycle boundary. Subclasses bridge a store SDK or a
## host-owned purchase service and emit normalized, correlated outcomes.

signal purchase_succeeded(operation_id: int, purchase: Dictionary)
signal purchase_pending(operation_id: int, purchase: Dictionary)
signal purchase_failed(operation_id: int, code: StringName)
signal purchase_cancelled(operation_id: int)
signal purchases_restored(purchases: Array)
signal purchase_consumption_completed(transaction_id: String, succeeded: bool)


func begin_purchase(_product_key: Variant, _operation_id: int) -> void:
	push_error("PurchaseProviderAdapter subclasses must implement begin_purchase().")


func restore_purchases() -> void:
	push_error("PurchaseProviderAdapter subclasses must implement restore_purchases().")


func consume_purchase(_purchase: Dictionary) -> void:
	push_error("PurchaseProviderAdapter subclasses must implement consume_purchase().")
