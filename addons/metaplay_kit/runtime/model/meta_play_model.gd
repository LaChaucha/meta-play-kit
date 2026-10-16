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
var attempts: Dictionary = {}
var completion_rewards: Dictionary = {}
var optional_rewards: Dictionary = {}
var reward_cooldown_seconds: int = 0
var last_base_reward_claimed_at: Dictionary = {}
var reward_claims: Dictionary = {}
var _attempt_sequence: int = 0


func configure_completion_rewards(values: Dictionary, cooldown_seconds: int) -> Dictionary:
	if cooldown_seconds < 0:
		return _completion_failure(&"reward.configuration_invalid", "The reward cooldown cannot be negative.", {})
	for level_key: Variant in values.keys():
		var raw_amount: Variant = values[level_key]
		if not levels.has(level_key) or not raw_amount is int or int(raw_amount) < 0:
			return _completion_failure(&"reward.configuration_invalid", "Completion rewards require registered levels and non-negative amounts.", {"level_key": level_key})
	completion_rewards = values.duplicate(true)
	reward_cooldown_seconds = cooldown_seconds
	return {"ok": true}


func configure_optional_rewards(values: Dictionary) -> Dictionary:
	for reward_type: Variant in values.keys():
		var raw_amount: Variant = values[reward_type]
		if str(reward_type).strip_edges().is_empty() or not raw_amount is int or int(raw_amount) < 0:
			return _completion_failure(&"reward.configuration_invalid", "Optional rewards require non-empty types and non-negative amounts.", {"reward_type": reward_type})
	optional_rewards = values.duplicate(true)
	return {"ok": true}


func begin_attempt(level_key: Variant) -> Dictionary:
	if not levels.has(level_key):
		return _completion_failure(&"level.not_found", "The requested level does not exist.", {"level_key": level_key})
	var level: Dictionary = get_level(level_key)
	if not bool(level.get("enabled", false)):
		return _completion_failure(&"level.locked", "The requested level is unavailable.", {"level_key": level_key})
	_attempt_sequence += 1
	for prior_id: Variant in attempts.keys():
		var prior_attempt: Dictionary = (attempts[prior_id] as Dictionary).duplicate(true)
		if str(prior_attempt.get("status", "")) == "active" or str(prior_attempt.get("status", "")) == "lost":
			prior_attempt["status"] = "abandoned"
			attempts[prior_id] = prior_attempt
	var attempt_id: String = "attempt-%s-%s" % [str(Time.get_ticks_usec()), str(_attempt_sequence)]
	attempts[attempt_id] = {"level_key": level_key, "status": "active", "result": {}}
	return {"ok": true, "attempt_id": attempt_id, "level_key": level_key}


func mark_attempt_lost(attempt_id: String) -> bool:
	if not attempts.has(attempt_id):
		return false
	var attempt: Dictionary = (attempts[attempt_id] as Dictionary).duplicate(true)
	if str(attempt.get("status", "")) != "active":
		return false
	attempt["status"] = "lost"
	attempts[attempt_id] = attempt
	return true


func revive_attempt(attempt_id: String) -> bool:
	if not attempts.has(attempt_id):
		return false
	var attempt: Dictionary = (attempts[attempt_id] as Dictionary).duplicate(true)
	if str(attempt.get("status", "")) != "lost":
		return false
	attempt["status"] = "active"
	attempts[attempt_id] = attempt
	return true


func record_attempt_result(attempt_id: String, stars: int, score: int, next_level_key: Variant) -> Dictionary:
	if not attempts.has(attempt_id):
		return _completion_failure(&"attempt.not_found", "The gameplay attempt is unknown or stale.", {"attempt_id": attempt_id})
	var attempt: Dictionary = (attempts[attempt_id] as Dictionary).duplicate(true)
	var requested_result: Dictionary = {"stars": clampi(stars, 0, 3), "score": maxi(0, score), "next_level_key": next_level_key}
	if str(attempt.get("status", "")) == "completed":
		if attempt.get("result", {}) == requested_result:
			var duplicate_result: Dictionary = attempt.get("completion", {}).duplicate(true)
			duplicate_result["duplicate"] = true
			return duplicate_result
		return _completion_failure(&"attempt.already_completed", "The attempt was already completed with a different result.", {"attempt_id": attempt_id})
	if str(attempt.get("status", "")) != "active":
		return _completion_failure(&"attempt.stale", "The gameplay attempt is no longer active.", {"attempt_id": attempt_id})
	var level_key: Variant = attempt.get("level_key")
	if not levels.has(level_key):
		return _completion_failure(&"level.not_found", "The attempt level no longer exists.", {"attempt_id": attempt_id, "level_key": level_key})
	var level: Dictionary = get_level(level_key)
	level["max_stars"] = maxi(int(level.get("max_stars", 0)), int(requested_result["stars"]))
	level["max_score"] = maxi(int(level.get("max_score", 0)), int(requested_result["score"]))
	levels[level_key] = level
	if next_level_key != null and levels.has(next_level_key):
		var next_level: Dictionary = get_level(next_level_key)
		next_level["enabled"] = true
		levels[next_level_key] = next_level
	attempt["status"] = "completed"
	attempt["result"] = requested_result.duplicate(true)
	attempts[attempt_id] = attempt
	levels_changed.emit()
	var response: Dictionary = {"ok": true, "attempt_id": attempt_id, "level_key": level_key, "level": level.duplicate(true), "next_level_key": next_level_key, "stars": requested_result["stars"], "score": requested_result["score"], "coins": coins, "duplicate": false}
	attempt["completion"] = response.duplicate(true)
	attempts[attempt_id] = attempt
	return response


func claim_base_reward(attempt_id: String, now_unix_seconds: int) -> Dictionary:
	if not attempts.has(attempt_id):
		return _completion_failure(&"attempt.not_found", "The gameplay attempt is unknown or stale.", {"attempt_id": attempt_id})
	var attempt: Dictionary = (attempts[attempt_id] as Dictionary).duplicate(true)
	if str(attempt.get("status", "")) != "completed":
		return _completion_failure(&"attempt.not_completed", "The attempt has no completed result.", {"attempt_id": attempt_id})
	var prior_claim: Dictionary = reward_claims.get("base:%s" % attempt_id, {})
	if not prior_claim.is_empty():
		var duplicate_claim: Dictionary = prior_claim.duplicate(true)
		duplicate_claim["duplicate"] = true
		return duplicate_claim
	var level_key: Variant = attempt.get("level_key")
	var amount: int = maxi(0, int(completion_rewards.get(level_key, 0)))
	var last_claimed: int = int(last_base_reward_claimed_at.get(level_key, 0))
	if last_base_reward_claimed_at.has(level_key) and now_unix_seconds - last_claimed < reward_cooldown_seconds:
		return _completion_failure(&"reward.cooldown_active", "The completion reward is still on cooldown.", {"attempt_id": attempt_id, "level_key": level_key, "available_at": last_claimed + reward_cooldown_seconds})
	if amount <= 0:
		return _completion_failure(&"reward.not_configured", "No completion reward is configured for this level.", {"attempt_id": attempt_id, "level_key": level_key})
	add_coins(amount)
	last_base_reward_claimed_at[level_key] = now_unix_seconds
	var result: Dictionary = {"ok": true, "attempt_id": attempt_id, "level_key": level_key, "granted": true, "amount": amount, "coins": coins, "duplicate": false}
	reward_claims["base:%s" % attempt_id] = result.duplicate(true)
	return result


func claim_optional_reward(attempt_id: String, claim_id: String, reward_type: StringName) -> Dictionary:
	if not attempts.has(attempt_id):
		return _completion_failure(&"attempt.not_found", "The gameplay attempt is unknown or stale.", {"attempt_id": attempt_id})
	var attempt: Dictionary = attempts[attempt_id] as Dictionary
	if str(attempt.get("status", "")) != "completed":
		return _completion_failure(&"attempt.not_completed", "The attempt has no completed result.", {"attempt_id": attempt_id})
	if claim_id.strip_edges().is_empty():
		return _completion_failure(&"reward.claim_id_required", "A unique host claim ID is required.", {"attempt_id": attempt_id})
	var prior: Dictionary = reward_claims.get("optional:%s" % claim_id, {})
	if not prior.is_empty():
		if str(prior.get("attempt_id", "")) != attempt_id or StringName(str(prior.get("reward_type", ""))) != reward_type:
			return _completion_failure(&"reward.claim_id_conflict", "The claim ID was already used for another reward.", {"claim_id": claim_id})
		var duplicate: Dictionary = prior.duplicate(true)
		duplicate["duplicate"] = true
		return duplicate
	if not optional_rewards.has(reward_type):
		return _completion_failure(&"reward.type_not_configured", "The optional reward type is not configured.", {"reward_type": reward_type})
	var amount: int = maxi(0, int(optional_rewards[reward_type]))
	add_coins(amount)
	var result: Dictionary = {"ok": true, "attempt_id": attempt_id, "claim_id": claim_id, "reward_type": reward_type, "granted": true, "amount": amount, "coins": coins, "duplicate": false}
	reward_claims["optional:%s" % claim_id] = result.duplicate(true)
	return result


func export_completion_state() -> Dictionary:
	return {"version": 1, "attempts": attempts.duplicate(true), "reward_claims": reward_claims.duplicate(true), "last_base_reward_claimed_at": last_base_reward_claimed_at.duplicate(true), "attempt_sequence": _attempt_sequence}


func restore_completion_state(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", -1)) != 1:
		return false
	var raw_attempts: Variant = snapshot.get("attempts")
	var raw_claims: Variant = snapshot.get("reward_claims")
	var raw_last_claimed: Variant = snapshot.get("last_base_reward_claimed_at")
	if not raw_attempts is Dictionary or not raw_claims is Dictionary or not raw_last_claimed is Dictionary:
		return false
	for attempt_id: Variant in (raw_attempts as Dictionary).keys():
		var entry: Variant = raw_attempts[attempt_id]
		if not attempt_id is String or str(attempt_id).is_empty() or not entry is Dictionary:
			return false
		var attempt: Dictionary = entry as Dictionary
		var attempt_status: String = str(attempt.get("status", ""))
		if not levels.has(attempt.get("level_key")) or not ["active", "lost", "completed", "abandoned"].has(attempt_status):
			return false
		if attempt_status == "completed" and (not attempt.get("result", {}) is Dictionary or not attempt.get("completion", {}) is Dictionary):
			return false
	for claim_key: Variant in (raw_claims as Dictionary).keys():
		var claim_raw: Variant = raw_claims[claim_key]
		if not claim_key is String or not claim_raw is Dictionary:
			return false
		var claim: Dictionary = claim_raw as Dictionary
		var claim_attempt_id: String = str(claim.get("attempt_id", ""))
		if not (raw_attempts as Dictionary).has(claim_attempt_id) or int(claim.get("amount", -1)) < 0 or int(claim.get("coins", -1)) < 0:
			return false
		if str(claim_key).begins_with("base:"):
			if str(claim_key) != "base:%s" % claim_attempt_id or str(((raw_attempts as Dictionary)[claim_attempt_id] as Dictionary).get("status", "")) != "completed":
				return false
		elif str(claim_key).begins_with("optional:"):
			if str(claim_key) != "optional:%s" % str(claim.get("claim_id", "")) or str(claim.get("reward_type", "")).is_empty():
				return false
		else:
			return false
	for level_key: Variant in (raw_last_claimed as Dictionary).keys():
		if not levels.has(level_key) or int(raw_last_claimed[level_key]) < 0:
			return false
	attempts = (raw_attempts as Dictionary).duplicate(true)
	reward_claims = (raw_claims as Dictionary).duplicate(true)
	last_base_reward_claimed_at = (raw_last_claimed as Dictionary).duplicate(true)
	_attempt_sequence = maxi(0, int(snapshot.get("attempt_sequence", 0)))
	return true


func _completion_failure(code: StringName, message: String, context: Dictionary) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "context": context.duplicate(true)}


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
		return _store_failure(&"store.item_not_found", "Artículo inexistente.", {"item_path": item_path.duplicate(true)})
	if bool(item.get("bought", false)):
		return _store_failure(&"store.item_already_owned", "Ya lo tienes.", {"item_path": item_path.duplicate(true)})
	var cost: int = _parse_price(item.get("price", 0))
	if cost > coins:
		return _store_failure(
			&"wallet.insufficient_funds",
			"No tienes monedas suficientes.",
			{"item_path": item_path.duplicate(true), "cost": cost, "balance": coins}
		)
	set_coins(coins - cost)
	_set_item_fields(item_path, {"bought": true})
	store_changed.emit()
	return {
		"ok": true,
		"message": "Compra completada.",
		"cost": cost,
		"coins": coins,
		"item_path": item_path.duplicate(true),
		"item": get_store_item(item_path),
	}


func equip_item(item_path: Array) -> Dictionary:
	var item: Dictionary = get_store_item(item_path)
	if item.is_empty():
		return _store_failure(&"store.item_not_found", "Artículo inexistente.", {"item_path": item_path.duplicate(true)})
	if not bool(item.get("bought", false)):
		return _store_failure(&"store.item_not_owned", "Compra el artículo antes de equiparlo.", {"item_path": item_path.duplicate(true)})
	if not item.has("load"):
		return _store_failure(&"store.item_not_equippable", "Este artículo no se puede equipar.", {"item_path": item_path.duplicate(true)})
	var group_name: String = str(item.get("group", ""))
	if not group_name.is_empty():
		_clear_equipped_group(group_name)
	_set_item_fields(item_path, {"load": true})
	store_changed.emit()
	return {
		"ok": true,
		"message": "Artículo equipado.",
		"item_path": item_path.duplicate(true),
		"item": get_store_item(item_path),
	}


func add_currency_product(product_key: Variant) -> Dictionary:
	if not coin_values.has(product_key):
		return _store_failure(&"currency.product_not_found", "Paquete monetario inexistente.", {"product_key": product_key})
	var amount: int = maxi(0, int(coin_values[product_key]))
	add_coins(amount)
	return {
		"ok": true,
		"message": "+%s monedas" % format_number(amount),
		"coins": coins,
		"coins_added": amount,
		"product_key": product_key,
	}


func _store_failure(code: StringName, message: String, context: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"context": context.duplicate(true),
	}


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
