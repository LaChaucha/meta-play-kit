class_name MetaPlayUIConfig
extends Resource

## Version of the serialized UI presentation profile contract.
const CURRENT_SCHEMA_VERSION: int = 1

@export_range(1, 2147483647, 1) var schema_version: int = CURRENT_SCHEMA_VERSION
