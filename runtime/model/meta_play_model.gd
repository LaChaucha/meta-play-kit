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
var level_progress: Dictionary = {}
var level_result_rules: Dictionary = {}
var campaign_projection: Array = []
var configuration: Dictionary = {
	"sfx": true,
	"music": true,
	"url_terms_and_conditions": "https://example.com/terms",
	"url_rate_us": "https://example.com/rate",
}
var currency_items: Dictionary = {}
var game_items: Dictionary = {}
var coin_values: Dictionary = {}
var purchase_transactions: Dictionary = {}
var coins: int = 0
var attempts: Dictionary = {}
var completion_rewards: Dictionary = {}
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


func begin_attempt(level_key: Variant) -> Dictionary:
	if not levels.has(level_key):
		return _completion_failure(&"level.not_found", "The requested level does not exist.", {"level_key": level_key})
	if not level_result_rules.has(level_key):
		return _completion_failure(&"level.rules_missing", "The requested level has no result rules.", {"level_key": level_key})
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


func resume_attempt(attempt_id: String) -> bool:
	if not attempts.has(attempt_id):
		return false
	var attempt: Dictionary = (attempts[attempt_id] as Dictionary).duplicate(true)
	if str(attempt.get("status", "")) != "failed":
		return false
	attempt["status"] = "active"
	attempts[attempt_id] = attempt
	return true


func record_attempt_result(
		attempt_id: String,
		score: int,
		condition_facts: Dictionary,
		presentation: Dictionary,
		force_loss: bool = false
	) -> Dictionary:
	if not attempts.has(attempt_id):
		return _completion_failure(&"attempt.not_found", "The gameplay attempt is unknown or stale.", {"attempt_id": attempt_id})
	var attempt: Dictionary = (attempts[attempt_id] as Dictionary).duplicate(true)
	var level_key: Variant = attempt.get("level_key")
	var evaluation: Dictionary = evaluate_level_result(level_key, score, condition_facts, force_loss)
	if not bool(evaluation.get("ok", false)):
		return evaluation
	var requested_result: Dictionary = evaluation.get("result", {}).duplicate(true)
	requested_result["presentation"] = presentation.duplicate(true)
	if str(attempt.get("status", "")) in ["completed", "failed"]:
		if attempt.get("result", {}) == requested_result:
			var duplicate_result: Dictionary = attempt.get("completion", {}).duplicate(true)
			duplicate_result["duplicate"] = true
			return duplicate_result
		return _completion_failure(&"attempt.already_completed", "The attempt was already completed with a different result.", {"attempt_id": attempt_id})
	if str(attempt.get("status", "")) != "active":
		return _completion_failure(&"attempt.stale", "The gameplay attempt is no longer active.", {"attempt_id": attempt_id})
	if not levels.has(level_key):
		return _completion_failure(&"level.not_found", "The attempt level no longer exists.", {"attempt_id": attempt_id, "level_key": level_key})
	var progress: Dictionary = get_level_progress(level_key)
	progress["best_score"] = maxi(int(progress.get("best_score", 0)), int(requested_result["score"]))
	progress["best_stars"] = maxi(int(progress.get("best_stars", 0)), int(requested_result["stars"]))
	if bool(requested_result.get("won", false)):
		progress["completed"] = true
	level_progress[level_key] = progress
	attempt["status"] = "completed" if bool(requested_result.get("won", false)) else "failed"
	attempt["result"] = requested_result.duplicate(true)
	attempts[attempt_id] = attempt
	levels_changed.emit()
	var response: Dictionary = {"ok": true, "attempt_id": attempt_id, "level_key": level_key, "outcome": requested_result["outcome"], "won": requested_result["won"], "stars": requested_result["stars"], "score": requested_result["score"], "progress": progress.duplicate(true), "presentation": presentation.duplicate(true), "coins": coins, "duplicate": false}
	attempt["completion"] = response.duplicate(true)
	attempts[attempt_id] = attempt
	return response


func configure_level_result_rules(rules_by_level: Dictionary) -> Dictionary:
	var validated: Dictionary = {}
	for level_key: Variant in rules_by_level.keys():
		var raw_rules: Variant = rules_by_level[level_key]
		if not levels.has(level_key) or not raw_rules is Dictionary:
			return _completion_failure(&"level.rules_invalid", "Result rules must reference registered levels and be dictionaries.", {"level_key": level_key})
		var rules: Dictionary = raw_rules as Dictionary
		var max_score: Variant = rules.get("max_score")
		var raw_thresholds: Variant = rules.get("star_thresholds")
		var raw_conditions: Variant = rules.get("required_conditions", [])
		if not max_score is int or int(max_score) < 0 or not raw_thresholds is Array or (raw_thresholds as Array).size() != 3 or not raw_conditions is Array:
			return _completion_failure(&"level.rules_invalid", "Level rules require a non-negative max score, three thresholds, and required conditions.", {"level_key": level_key})
		var thresholds: Array = raw_thresholds as Array
		var previous_threshold: int = 0
		for threshold_index: int in range(thresholds.size()):
			var raw_threshold: Variant = thresholds[threshold_index]
			if not raw_threshold is int or int(raw_threshold) < previous_threshold or int(raw_threshold) > int(max_score):
				return _completion_failure(&"level.rules_invalid", "Star thresholds must be non-decreasing and within the maximum score.", {"level_key": level_key, "threshold_index": threshold_index})
			previous_threshold = int(raw_threshold)
		var seen_conditions: Dictionary = {}
		for raw_condition: Variant in raw_conditions as Array:
			if not (raw_condition is String or raw_condition is StringName) or str(raw_condition).strip_edges().is_empty() or seen_conditions.has(str(raw_condition)):
				return _completion_failure(&"level.rules_invalid", "Required condition keys must be unique, non-empty strings.", {"level_key": level_key})
			seen_conditions[str(raw_condition)] = true
		validated[level_key] = {
			"max_score": int(max_score),
			"star_thresholds": thresholds.duplicate(true),
			"required_conditions": raw_conditions.duplicate(true),
		}
	level_result_rules = validated
	return {"ok": true}


func evaluate_level_result(
		level_key: Variant,
		score: int,
		condition_facts: Dictionary,
		force_loss: bool = false
	) -> Dictionary:
	if not levels.has(level_key):
		return _completion_failure(&"level.not_found", "The requested level does not exist.", {"level_key": level_key})
	if not level_result_rules.has(level_key):
		return _completion_failure(&"level.rules_missing", "The requested level has no result rules.", {"level_key": level_key})
	var rules: Dictionary = level_result_rules[level_key] as Dictionary
	var max_score: int = int(rules.get("max_score", 0))
	if score < 0 or score > max_score:
		return _completion_failure(&"level.result_invalid", "The submitted score is outside the configured range.", {"level_key": level_key, "score": score, "max_score": max_score})
	if force_loss:
		return {"ok": true, "result": {"outcome": "lost", "won": false, "stars": 0, "score": score, "condition_facts": condition_facts.duplicate(true)}}
	var conditions: Array = rules.get("required_conditions", []) as Array
	for condition_key: Variant in conditions:
		if not condition_facts.has(condition_key) or not condition_facts[condition_key] is bool or not bool(condition_facts[condition_key]):
			var failed_result: Dictionary = {"ok": true, "result": {"outcome": "lost", "won": false, "stars": 0, "score": score, "condition_facts": condition_facts.duplicate(true)}}
			return failed_result
	var thresholds: Array = rules.get("star_thresholds", []) as Array
	var stars: int = 0
	for star_index: int in range(thresholds.size()):
		if score >= int(thresholds[star_index]):
			stars = star_index + 1
	return {"ok": true, "result": {"outcome": "won", "won": true, "stars": stars, "score": score, "condition_facts": condition_facts.duplicate(true)}}


func configure_campaign_projection(projection: Array) -> Dictionary:
	var validated: Array = []
	var seen_levels: Dictionary = {}
	for raw_entry: Variant in projection:
		if not raw_entry is Dictionary:
			return _completion_failure(&"campaign.projection_invalid", "Campaign entries must be dictionaries.", {})
		var entry: Dictionary = raw_entry as Dictionary
		var level_key: Variant = entry.get("key")
		var available: Variant = entry.get("available")
		var selectable: Variant = entry.get("selectable")
		if not levels.has(level_key) or not available is bool or not selectable is bool or (bool(selectable) and not bool(available)) or seen_levels.has(level_key):
			return _completion_failure(&"campaign.projection_invalid", "Campaign entries must uniquely reference levels and provide valid availability and selection flags.", {"level_key": level_key})
		seen_levels[level_key] = true
		validated.append({"key": level_key, "available": bool(available), "selectable": bool(selectable)})
	campaign_projection = validated
	return {"ok": true}


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


func export_completion_state() -> Dictionary:
	var persisted_attempts: Dictionary = attempts.duplicate(true)
	for attempt_id: Variant in persisted_attempts.keys():
		var raw_attempt: Variant = persisted_attempts[attempt_id]
		if not raw_attempt is Dictionary:
			continue
		var attempt: Dictionary = raw_attempt as Dictionary
		var result: Dictionary = attempt.get("result", {}) as Dictionary
		result.erase("presentation")
		attempt["result"] = result
		var completion: Dictionary = attempt.get("completion", {}) as Dictionary
		completion.erase("presentation")
		attempt["completion"] = completion
		persisted_attempts[attempt_id] = attempt
	return {"version": 1, "attempts": persisted_attempts, "reward_claims": reward_claims.duplicate(true), "last_base_reward_claimed_at": last_base_reward_claimed_at.duplicate(true), "attempt_sequence": _attempt_sequence}


func can_restore_completion_state(snapshot: Dictionary, available_levels: Dictionary) -> bool:
	if int(snapshot.get("version", -1)) != 1:
		return false
	var sequence_raw: Variant = snapshot.get("attempt_sequence")
	if not sequence_raw is int or int(sequence_raw) < 0:
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
		if not available_levels.has(attempt.get("level_key")) or not ["active", "lost", "failed", "completed", "abandoned"].has(attempt_status):
			return false
		if attempt_status in ["completed", "failed"]:
			var result_raw: Variant = attempt.get("result")
			var completion_raw: Variant = attempt.get("completion")
			if not result_raw is Dictionary or not completion_raw is Dictionary:
				return false
			var attempt_result: Dictionary = result_raw as Dictionary
			var completion: Dictionary = completion_raw as Dictionary
			if not attempt_result.get("stars") is int or not attempt_result.get("score") is int or not attempt_result.get("won") is bool:
				return false
			if int(attempt_result["stars"]) < 0 or int(attempt_result["stars"]) > 3 or int(attempt_result["score"]) < 0:
				return false
			if bool(attempt_result["won"]) != (attempt_status == "completed"):
				return false
			if str(completion.get("attempt_id", "")) != str(attempt_id) or completion.get("level_key") != attempt.get("level_key"):
				return false
	for claim_key: Variant in (raw_claims as Dictionary).keys():
		var claim_raw: Variant = raw_claims[claim_key]
		if not claim_key is String or not claim_raw is Dictionary:
			return false
		var claim: Dictionary = claim_raw as Dictionary
		var claim_attempt_id: String = str(claim.get("attempt_id", ""))
		if not (raw_attempts as Dictionary).has(claim_attempt_id) or not claim.get("amount") is int or not claim.get("coins") is int or int(claim.get("amount", -1)) < 0 or int(claim.get("coins", -1)) < 0:
			return false
		if str(claim_key).begins_with("base:"):
			if str(claim_key) != "base:%s" % claim_attempt_id or str(((raw_attempts as Dictionary)[claim_attempt_id] as Dictionary).get("status", "")) != "completed":
				return false
		else:
			return false
	for level_key: Variant in (raw_last_claimed as Dictionary).keys():
		var timestamp: Variant = raw_last_claimed[level_key]
		if not available_levels.has(level_key) or not timestamp is int or int(timestamp) < 0:
			return false
	return true


func restore_completion_state(snapshot: Dictionary) -> bool:
	if not can_restore_completion_state(snapshot, levels):
		return false
	var raw_attempts: Dictionary = snapshot.get("attempts", {}) as Dictionary
	var raw_claims: Dictionary = snapshot.get("reward_claims", {}) as Dictionary
	var raw_last_claimed: Dictionary = snapshot.get("last_base_reward_claimed_at", {}) as Dictionary
	attempts = (raw_attempts as Dictionary).duplicate(true)
	reward_claims = (raw_claims as Dictionary).duplicate(true)
	last_base_reward_claimed_at = (raw_last_claimed as Dictionary).duplicate(true)
	_attempt_sequence = int(snapshot.get("attempt_sequence", 0))
	return true


func _completion_failure(code: StringName, message: String, context: Dictionary) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "context": context.duplicate(true)}


func set_levels(value: Dictionary) -> void:
	levels = value.duplicate(true)
	level_progress.clear()
	level_result_rules.clear()
	campaign_projection.clear()
	for level_key: Variant in levels.keys():
		level_progress[level_key] = {"completed": false, "best_score": 0, "best_stars": 0}
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


func get_level_progress(level_key: Variant) -> Dictionary:
	if not level_progress.has(level_key):
		return {}
	var raw: Variant = level_progress[level_key]
	return raw.duplicate(true) if raw is Dictionary else {}


func get_all_level_progress() -> Dictionary:
	return level_progress.duplicate(true)


func get_enabled_level_keys() -> Array:
	var result: Array = []
	for raw_entry: Variant in campaign_projection:
		if raw_entry is Dictionary and bool((raw_entry as Dictionary).get("available", false)):
			result.append((raw_entry as Dictionary).get("key"))
	return result


func get_next_level_to_play() -> Variant:
	return null


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


func record_verified_currency_purchase(product_key: Variant, transaction_id: String, provider_id: String) -> Dictionary:
	if not coin_values.has(product_key):
		return _store_failure(&"currency.product_not_found", "The verified purchase references an unknown product.", {"product_key": product_key})
	if transaction_id.strip_edges().is_empty() or provider_id.strip_edges().is_empty():
		return _store_failure(&"purchase.transaction_invalid", "A verified purchase requires a transaction ID and provider ID.", {})
	var transaction_key: String = "%s:%s" % [provider_id, transaction_id]
	if purchase_transactions.has(transaction_key):
		var existing: Dictionary = purchase_transactions[transaction_key] as Dictionary
		if str(existing.get("product_key", "")) != str(product_key) or str(existing.get("provider", "")) != provider_id:
			return _store_failure(&"purchase.transaction_conflict", "A transaction ID cannot be reused for a different product or provider.", {"transaction_id": transaction_id})
		return {"ok": true, "duplicate": true, "transaction_id": transaction_id, "product_key": existing.get("product_key"), "currency_added": 0, "currency_balance": coins}
	var amount: int = maxi(0, int(coin_values[product_key]))
	add_coins(amount)
	var transaction: Dictionary = {
		"transaction_id": transaction_id,
		"product_key": str(product_key),
		"provider": provider_id,
		"currency_added": amount,
	}
	purchase_transactions[transaction_key] = transaction
	return {
		"ok": true,
		"duplicate": false,
		"transaction_id": transaction_id,
		"product_key": product_key,
		"provider": provider_id,
		"currency_added": amount,
		"currency_balance": coins,
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
