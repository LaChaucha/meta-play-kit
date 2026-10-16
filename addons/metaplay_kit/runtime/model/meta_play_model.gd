class_name MetaPlayModel
extends RefCounted

## State owner for levels, wallet, configuration and the in-memory store.
## UI controllers only read projections from here and write through these
## validated use-case methods.

signal coins_changed(total: int)
signal levels_changed()
signal store_changed()
signal configuration_changed(configuration: Dictionary)

enum ItemType {
	BASIC = 0,
	EQUIP = 1,
	PHASE = 2,
}

var levels: Dictionary = {}
var configuration: Dictionary = {
	"sfx": true,
	"music": true,
	"url_terms_and_conditions": "https://example.com/terms",
	"url_rate_us": "https://example.com/rate",
}
var currency_items: Dictionary = {}
var game_items: Dictionary = {}
var coin_values: Dictionary = {}
var coins: int = 0


func set_levels(value: Dictionary) -> void:
	levels = value.duplicate(true)
	levels_changed.emit()


func set_configuration(value: Dictionary) -> void:
	configuration = value.duplicate(true)
	configuration_changed.emit(configuration.duplicate(true))


func set_currency_items(value: Dictionary) -> void:
	currency_items = value.duplicate(true)
	store_changed.emit()


func set_game_items(value: Dictionary) -> void:
	game_items = value.duplicate(true)
	store_changed.emit()


func set_coin_values(value: Dictionary) -> void:
	coin_values = value.duplicate(true)


func set_coins(value: int) -> void:
	coins = maxi(0, value)
	coins_changed.emit(coins)


func add_coins(value: int) -> int:
	set_coins(coins + maxi(0, value))
	return coins


func get_level(level_key: Variant) -> Dictionary:
	if not levels.has(level_key):
		return {}
	var raw: Variant = levels[level_key]
	return raw.duplicate(true) if raw is Dictionary else {}


func get_enabled_level_keys() -> Array:
	var result: Array = []
	for level_key: Variant in levels.keys():
		var raw: Variant = levels[level_key]
		if raw is Dictionary and bool((raw as Dictionary).get("enabled", false)):
			result.append(level_key)
	return result


func get_next_level_to_play() -> Variant:
	var enabled: Array = get_enabled_level_keys()
	for level_key: Variant in enabled:
		var level: Dictionary = get_level(level_key)
		if int(level.get("max_stars", 0)) <= 0:
			return level_key
	return enabled[0] if not enabled.is_empty() else null


func complete_level(
		level_key: Variant,
		stars: int,
		score: int,
		reward_coins: int,
		next_level_key: Variant
	) -> Dictionary:
	if not levels.has(level_key):
		return {
			"ok": false,
			"code": &"level.not_found",
			"message": "Nivel inexistente.",
		}
	var level: Dictionary = get_level(level_key)
	level["max_stars"] = maxi(int(level.get("max_stars", 0)), clampi(stars, 0, 3))
	level["max_score"] = maxi(int(level.get("max_score", 0)), maxi(0, score))
	levels[level_key] = level
	if next_level_key != null and levels.has(next_level_key):
		var next_level: Dictionary = get_level(next_level_key)
		next_level["enabled"] = true
		levels[next_level_key] = next_level
	add_coins(reward_coins)
	levels_changed.emit()
	return {
		"ok": true,
		"level": level.duplicate(true),
		"coins": coins,
		"next_level": next_level_key,
	}


func get_store_item(item_path: Array) -> Dictionary:
	if item_path.size() == 1:
		var item_key: Variant = item_path[0]
		if not game_items.has(item_key):
			return {}
		var raw: Variant = game_items[item_key]
		return raw.duplicate(true) if raw is Dictionary else {}
	if item_path.size() == 2:
		var parent: Dictionary = get_store_item([item_path[0]])
		var stages: Dictionary = parent.get("stages", {}) as Dictionary
		var stage_key: Variant = item_path[1]
		if not stages.has(stage_key):
			return {}
		var stage_raw: Variant = stages[stage_key]
		return stage_raw.duplicate(true) if stage_raw is Dictionary else {}
	return {}


func purchase_game_item(item_path: Array) -> Dictionary:
	var item: Dictionary = get_store_item(item_path)
	if item.is_empty():
		return {"ok": false, "message": "Artículo inexistente."}
	if bool(item.get("bought", false)):
		return {"ok": false, "message": "Ya lo tienes."}
	var cost: int = _parse_price(item.get("price", 0))
	if cost > coins:
		return {"ok": false, "message": "No tienes monedas suficientes.", "cost": cost}
	set_coins(coins - cost)
	_set_item_fields(item_path, {"bought": true})
	store_changed.emit()
	return {"ok": true, "message": "Compra completada.", "cost": cost, "coins": coins}


func equip_item(item_path: Array) -> Dictionary:
	var item: Dictionary = get_store_item(item_path)
	if item.is_empty():
		return {"ok": false, "message": "Artículo inexistente."}
	if not bool(item.get("bought", false)):
		return {"ok": false, "message": "Compra el artículo antes de equiparlo."}
	if not item.has("load"):
		return {"ok": false, "message": "Este artículo no se puede equipar."}
	var group_name: String = str(item.get("group", ""))
	if not group_name.is_empty():
		_clear_equipped_group(group_name)
	_set_item_fields(item_path, {"load": true})
	store_changed.emit()
	return {"ok": true, "message": "Artículo equipado.", "item": item_path.duplicate()}


func add_currency_product(product_key: Variant) -> Dictionary:
	if not coin_values.has(product_key):
		return {"ok": false, "message": "Paquete monetario inexistente."}
	var amount: int = maxi(0, int(coin_values[product_key]))
	add_coins(amount)
	return {"ok": true, "message": "+%s monedas" % format_number(amount), "coins": coins}


func toggle_sfx() -> bool:
	configuration["sfx"] = not bool(configuration.get("sfx", true))
	configuration_changed.emit(configuration.duplicate(true))
	return bool(configuration["sfx"])


func toggle_music() -> bool:
	configuration["music"] = not bool(configuration.get("music", true))
	configuration_changed.emit(configuration.duplicate(true))
	return bool(configuration["music"])


func get_type_buttons() -> Dictionary:
	return {"BASIC": ItemType.BASIC, "EQUIP": ItemType.EQUIP, "PHASE": ItemType.PHASE}


func format_number(value: Variant) -> String:
	var digits: String = str(value)
	var negative: bool = digits.begins_with("-")
	if negative:
		digits = digits.substr(1)
	var formatted: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += "."
		formatted += digits[index]
	return ("-" if negative else "") + formatted


func _parse_price(value: Variant) -> int:
	if value is int or value is float:
		return maxi(0, int(value))
	var normalized: String = str(value).replace(".", "").replace(",", "")
	return maxi(0, normalized.to_int())


func _set_item_fields(item_path: Array, fields: Dictionary) -> void:
	if item_path.size() == 1:
		var item_key: Variant = item_path[0]
		var item: Dictionary = get_store_item(item_path)
		item.merge(fields, true)
		game_items[item_key] = item
		return
	if item_path.size() == 2:
		var parent_key: Variant = item_path[0]
		var stage_key: Variant = item_path[1]
		var parent: Dictionary = get_store_item([parent_key])
		var stages: Dictionary = parent.get("stages", {}) as Dictionary
		var stage: Dictionary = get_store_item(item_path)
		stage.merge(fields, true)
		stages[stage_key] = stage
		parent["stages"] = stages
		game_items[parent_key] = parent


func _clear_equipped_group(group_name: String) -> void:
	for item_key: Variant in game_items.keys():
		var item: Dictionary = get_store_item([item_key])
		if str(item.get("group", "")) == group_name and item.has("load"):
			item["load"] = false
			game_items[item_key] = item
		var stages: Dictionary = item.get("stages", {}) as Dictionary
		for stage_key: Variant in stages.keys():
			var stage_raw: Variant = stages[stage_key]
			if stage_raw is not Dictionary:
				continue
			var stage: Dictionary = (stage_raw as Dictionary).duplicate(true)
			if str(stage.get("group", "")) == group_name and stage.has("load"):
				stage["load"] = false
				stages[stage_key] = stage
		if not stages.is_empty():
			item["stages"] = stages
			game_items[item_key] = item
