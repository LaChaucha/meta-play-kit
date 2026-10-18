class_name MetaPlayResult
extends RefCounted

## Stable outcome shared by synchronous facade commands and asynchronous workflows.
## Use the static constructors so each status keeps its required fields consistent.

enum Status {
	ACCEPTED,
	COMPLETED,
	REJECTED,
	FAILED,
	CANCELLED,
}

var status: Status:
	get:
		return _status

var code: StringName:
	get:
		return _code

var operation_id: int:
	get:
		return _operation_id

var context: Dictionary:
	get:
		return _context.duplicate(true)

var _status: Status = Status.COMPLETED
var _code: StringName = &""
var _operation_id: int = 0
var _context: Dictionary = {}


func _init(
		result_status: Status,
		result_code: StringName = &"",
		result_operation_id: int = 0,
		result_context: Dictionary = {}
	) -> void:
	_status = result_status
	_code = result_code
	_operation_id = result_operation_id
	_context = result_context.duplicate(true)
	assert(is_valid(), "MetaPlayResult was created with an invalid status, code, or operation ID.")


static func accepted(operation_id: int, context: Dictionary = {}) -> MetaPlayResult:
	return MetaPlayResult.new(Status.ACCEPTED, &"", operation_id, context)


static func completed(operation_id: int = 0, context: Dictionary = {}) -> MetaPlayResult:
	return MetaPlayResult.new(Status.COMPLETED, &"", operation_id, context)


static func rejected(code: StringName, context: Dictionary = {}) -> MetaPlayResult:
	return MetaPlayResult.new(Status.REJECTED, code, 0, context)


static func failed(operation_id: int, code: StringName, context: Dictionary = {}) -> MetaPlayResult:
	return MetaPlayResult.new(Status.FAILED, code, operation_id, context)


static func cancelled(operation_id: int, context: Dictionary = {}) -> MetaPlayResult:
	return MetaPlayResult.new(Status.CANCELLED, &"", operation_id, context)


## Checks the public contract invariants for this result.
func is_valid() -> bool:
	match _status:
		Status.ACCEPTED:
			return _operation_id > 0 and _code == &""
		Status.COMPLETED:
			return _operation_id >= 0 and _code == &""
		Status.REJECTED:
			return _operation_id == 0 and _code != &""
		Status.FAILED:
			return _operation_id > 0 and _code != &""
		Status.CANCELLED:
			return _operation_id > 0 and _code == &""
	return false
