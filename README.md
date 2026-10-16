# MetaPlayKit

MetaPlayKit is a reusable Godot 4.7 addon being developed as a production-oriented meta-game layer for multiple host games. It provides a public `TtpGuiApi` facade, progression and store rules, asynchronous level-resource loading, reusable UI components, a theme, and UI assets. This repository is an early product baseline with a sample consumer: the sample demonstrates integration but does not define the host game's screens or the product boundary. See [PRODUCT.md](PRODUCT.md) for the product intent, ownership boundaries, and readiness gates.

## Run the sample consumer

Open the repository root's `project.godot` in Godot 4.7 and run the main scene. The project uses a 1280 × 720 logical viewport with `canvas_items` stretching.

## Repository layout

| Path | Purpose |
| --- | --- |
| `addons/metaplay_kit/plugin.cfg` and `plugin.gd` | Editor plugin; enabling it registers the `TtpGuiApi` autoload. |
| `addons/metaplay_kit/runtime/api/` | Public facade, commands, queries, and signals. |
| `addons/metaplay_kit/runtime/model/` | Progression, wallet, settings, and store rules. |
| `addons/metaplay_kit/runtime/systems/` | Asynchronous resource loading. |
| `addons/metaplay_kit/runtime/components/`, `ui/` | Reusable UI controls and loading presentation. |
| `addons/metaplay_kit/runtime/platform/` | Optional platform purchase adapter and desktop mock. |
| `addons/metaplay_kit/assets/` | Reusable theme and UI art. |
| `PRODUCT.md` | Product direction, responsibility boundaries, and production readiness gates. |
| `demo/scenes/`, `demo/scripts/` | Sample consumer app and level; not required by the addon runtime. |
| `tests/`, `scenarios/` | Domain/loading tests and repeatable demo flows. |
| `interfaces/` | Archived Godot 3 reference material; not part of the runtime. |

A consuming game needs `addons/metaplay_kit/`, its own game content, and the autoload/plugin setup described below.

## Install

1. Copy `addons/metaplay_kit/` into the consuming project's `addons/` directory.
2. Open the project in Godot and allow it to import the addon.
3. In **Project > Project Settings > Plugins**, enable **MetaPlayKit**. The plugin registers the `TtpGuiApi` autoload. Resolve any existing autoload name/path conflict first.
4. Optionally set `gui/theme/custom` to `res://addons/metaplay_kit/assets/theme/metaplay.tres`. The plugin does not replace the host game's theme automatically.

## Public API

`TtpGuiApi` is the host game's facade. Use configuration methods before starting a session, action methods to request changes, read methods for UI projections, and signals to react to results. The facade returns deep copies of catalog, settings, and level data so callers do not mutate kit state through query results. The model and resource loader are implementation details and are not exposed as public properties.

### Configure a session

```gdscript
TtpGuiApi.configure_levels({
    "forest": {
        "name": "Forest",
        "max_score": 0,
        "max_stars": 0,
        "scene_path": "res://levels/forest.tscn",
        "enabled": true,
    },
    "cave": {
        "name": "Cave",
        "max_score": 0,
        "max_stars": 0,
        "scene_path": "res://levels/cave.tscn",
        "enabled": false,
    },
})
TtpGuiApi.configure_settings({"sfx": true, "music": true})
TtpGuiApi.configure_items(item_catalog)
TtpGuiApi.configure_currency_products(currency_products)
TtpGuiApi.configure_currency_rewards({"small_pack": 500, "large_pack": 2500})
TtpGuiApi.set_currency_balance(250)
```

A level entry uses `name`, `max_score`, `max_stars`, `scene_path`, and `enabled`. Item catalogs support basic, equippable, and phased entries; phased entries are addressed by paths such as `["power_boost", "phase1"]`. Currency reward values map product keys to the balance granted when credited.

### Commands and queries

| Purpose | Public methods |
| --- | --- |
| Configure session data | `configure_levels`, `configure_settings`, `configure_items`, `configure_currency_products`, `configure_currency_rewards`, `set_currency_balance` |
| Load and progress | `request_initial_level_load`, `request_level_load(key) -> bool` (compatibility), `request_level_load_result(key) -> MetaPlayResult`, `cancel_level_load(operation_id)`, `select_level(key) -> MetaPlayResult`, `begin_level_attempt(key) -> MetaPlayResult`, `complete_level(attempt_id, stars, score, next_level_key) -> MetaPlayResult`, `report_level_loss(attempt_id)`, `retry_level(key) -> MetaPlayResult`, `load_next_level() -> MetaPlayResult` |
| Store and wallet | `purchase_item(path) -> MetaPlayResult`, `equip_item(path) -> MetaPlayResult`, `credit_currency_product(product_key) -> MetaPlayResult` |
| Settings and rewards | `toggle_sfx`, `toggle_music`, `configure_completion_rewards(rewards, cooldown_seconds)`, `configure_optional_rewards(rewards)`, `claim_completion_reward(attempt_id)`, `claim_optional_reward(attempt_id, claim_id, reward_type)`, `revive_after_reward(attempt_id)`, `use_life()` |
| Host-owned state | `set_session_feature_state(key, state) -> MetaPlayResult`, `get_session_feature_state(key)`, `export_session_state() -> MetaPlayResult`, `restore_session_state(snapshot) -> MetaPlayResult` |
| Navigation | `request_home_screen`, `request_level_selection_screen`, `request_store_screen`, `request_settings_screen`, `start_or_resume_game() -> MetaPlayResult` |
| Read level/session state | `get_level(key)`, `get_levels`, `get_enabled_level_keys`, `get_next_available_level` |
| Read store/settings state | `get_settings`, `get_items`, `get_item(path)`, `get_currency_products`, `get_currency_balance`, `get_item_type_values` |
| Loading/presentation helpers | `get_loaded_resource(path)`, `is_loading`, `format_number(value)` |

`begin_level_attempt()` issues an opaque attempt ID only when the host is ready to enter gameplay. It is distinct from the asynchronous level-load operation ID; loading the initial scene does not start an attempt. Beginning another attempt abandons any prior active or lost attempt. A loss can be revived with the same attempt ID; retrying by loading the level again creates a new attempt once gameplay starts.

`complete_level(attempt_id, stars, score, next_level_key)` records the terminal result once and updates best stars/score. Identical duplicate submissions return the stored outcome without repeating navigation or wallet changes; conflicting or stale submissions are rejected. The method no longer accepts a caller-supplied currency amount. Configure base amounts with `configure_completion_rewards({"forest": 120}, cooldown_seconds)`. The first eligible completion reward is granted, and later rewards for that level become available after the host-configured cooldown. A completion replay may improve records even when its reward is still cooling down. `claim_completion_reward(attempt_id)` can be used to retry a claim after the cooldown expires.

Optional rewards are configured by type, for example `configure_optional_rewards({"double_completion": 120})`. After the host verifies an external provider outcome, call `claim_optional_reward(attempt_id, provider_claim_id, &"double_completion")`. The caller supplies an opaque unique claim ID, never a currency amount. Repeating the same claim returns its prior outcome; reusing the ID for another attempt or reward type is rejected. The kit does not initiate ads or purchases.

`export_session_state()` returns a `MetaPlayResult` whose context contains a deep-copied `snapshot` Dictionary at schema version 2. One snapshot always carries progression, wallet, settings, inventory, and feature state together. The `features` section includes the completion/reward ledger and serializable state supplied through `set_session_feature_state(key, state)`. Feature keys are stable strings; `level_completion` is reserved for the kit. Both feature-state setters and snapshot export reject non-serializable values instead of dropping them. The host owns storage and calls `restore_session_state(snapshot)` explicitly. Restore validates the entire snapshot before applying anything and emits one `session_restored(schema_version)` signal after success. This evolving product currently accepts only schema version 2; there is no migration path from the previous partial format. Local snapshots are not authoritative against a modified client; online games must validate rewards on their server.

```gdscript
var snapshot: Dictionary = {}
var export_result: MetaPlayResult = TtpGuiApi.export_session_state()
if export_result.status == MetaPlayResult.Status.COMPLETED:
    snapshot = export_result.context.get("snapshot", {}) as Dictionary
    # The host serializes and stores snapshot with its own save system.

var restore_result: MetaPlayResult = TtpGuiApi.restore_session_state(snapshot)
if restore_result.status == MetaPlayResult.Status.REJECTED:
    push_warning("Session restore was rejected: %s" % restore_result.code)
```

`select_level()`, `retry_level()`, `load_next_level()`, and `start_or_resume_game()` return `ACCEPTED` with the load operation ID only after a load request starts; otherwise they return `REJECTED`. `request_level_load_result(key)` provides the same typed admission result for direct load requests; `request_level_load(key) -> bool` remains as a compatibility wrapper. The accepted command result describes request admission, not the later scene-load outcome: observe `level_load_result` for that lifecycle. Rejection codes include `level.not_found`, `level.locked`, `level.scene_path_missing`, `level.load_in_progress`, and `level.no_available_level`. Legacy `action_rejected` messages continue to emit during migration. Gameplay is presented by the host after the load completes and a valid level instance is created. The host owns stopping/pausing its gameplay node and deciding how to persist session state.

### Typed operation results

`MetaPlayResult` is the shared typed result contract for the gradual migration of facade commands. Its `status` is one of `ACCEPTED`, `COMPLETED`, `REJECTED`, `FAILED`, or `CANCELLED`; `code` is a stable `StringName` for rejected or failed outcomes; `operation_id` correlates asynchronous acceptance with its terminal result; and `context` carries structured details as a defensive deep copy. Accepted, successful, and cancelled outcomes have no error code. Synchronous results use operation ID `0`; accepted, failed, and cancelled asynchronous results require a positive ID. Create results with `MetaPlayResult.accepted()`, `completed()`, `rejected()`, `failed()`, and `cancelled()` so these invariants are checked. Progression and store commands plus terminal level-load events use this type; asynchronous purchase-provider operations will migrate in a follow-up story.

Progression rejections also continue to emit the legacy `action_rejected` and `operation_rejected` message signals for existing consumers. New integrations should handle the returned result and avoid processing the same rejection again through a legacy signal. Store and wallet commands return `MetaPlayResult` as well: purchase/equip failures use stable codes such as `store.item_not_found`, `store.item_already_owned`, `store.item_not_owned`, `store.item_not_equippable`, and `wallet.insufficient_funds`; unknown currency products use `currency.product_not_found`. Rejected results include structured item/product context, and insufficient-funds context includes both required cost and current balance. Successful purchase/equip results include the updated item snapshot; successful currency credit includes the amount added and resulting balance. Store failures continue to emit legacy rejection messages, so integrations should consume the typed return and not handle the same failure again through `action_rejected`. Load consumers can migrate to `level_load_result(result: MetaPlayResult)`, emitted exactly once for each accepted operation with `COMPLETED`, `FAILED`, or `CANCELLED` status and the same operation ID. Its context contains `level_key`, a copied `level_data`, and `scene_path`; success also contains the exact loaded `resource`, while failure uses stable code `level.load_failed` and includes the loader's presentation-only `message`. Existing terminal signals remain available during migration; do not handle both the typed result and legacy terminal event for the same behavior.

### Loading integration

Connect before requesting the initial level. Every accepted request gets a monotonically increasing `operation_id`. The start, progress, accepted command result, and typed terminal result carry that same ID, so a host can correlate events even when the same scene is requested repeatedly. `loading_progress_changed` begins at `0.0`; values are clamped to `0.0..1.0` and never decrease during one operation. On success, progress reaches `1.0` before the terminal result. Progress is an estimate of loader work: only the terminal result determines the outcome, so progress reaching `1.0` alone does not mean success. Every accepted operation emits exactly one typed terminal result. Rejected requests emit no load lifecycle events. `get_loaded_resource(path)` remains as a compatibility helper and consumes the ready resource; new integrations should use the resource in the typed result context.

```gdscript
extends Node

var _pending_operation_id: int = 0
var _current_level: Node = null

func _ready() -> void:
    TtpGuiApi.level_load_started.connect(_on_level_load_started)
    TtpGuiApi.level_load_result.connect(_on_level_load_result)
    TtpGuiApi.action_rejected.connect(_on_action_rejected)
    TtpGuiApi.configure_levels({
        "forest": {
            "name": "Forest",
            "max_score": 0,
            "max_stars": 0,
            "scene_path": "res://levels/forest.tscn",
            "enabled": true,
        },
    })
    TtpGuiApi.request_initial_level_load()

func _on_level_load_started(operation_id: int, _level_data: Dictionary) -> void:
    _pending_operation_id = operation_id
    # Show the host game's loading UI.

func _on_level_load_result(result: MetaPlayResult) -> void:
    if result.operation_id != _pending_operation_id:
        return
    var context: Dictionary = result.context
    match result.status:
        MetaPlayResult.Status.COMPLETED:
            var level_data: Dictionary = context.get("level_data", {}) as Dictionary
            var resource: Resource = context.get("resource") as Resource
            var packed_scene: PackedScene = resource as PackedScene
            if packed_scene == null:
                _pending_operation_id = 0
                TtpGuiApi.request_home_screen()
                return
            var level: Node = packed_scene.instantiate() as Node
            if level == null:
                _pending_operation_id = 0
                TtpGuiApi.request_home_screen()
                return
            if level.has_method("configure"):
                var configured: Variant = level.call("configure", level_data.get("key"), self)
                if configured is bool and not configured:
                    level.free()
                    _pending_operation_id = 0
                    TtpGuiApi.request_home_screen()
                    return
            add_child(level)
            if level.has_method("start_level"):
                var started: Variant = level.call("start_level")
                if started is bool and not started:
                    if level.has_method("stop_level"):
                        level.call("stop_level")
                    remove_child(level)
                    level.queue_free()
                    _pending_operation_id = 0
                    TtpGuiApi.request_home_screen()
                    return
            if _current_level != null and is_instance_valid(_current_level):
                remove_child(_current_level)
                _current_level.queue_free()
            level.name = "CurrentLevel"
            _current_level = level
            _pending_operation_id = 0
            # Present gameplay in the host UI.
        MetaPlayResult.Status.FAILED, MetaPlayResult.Status.CANCELLED:
            _pending_operation_id = 0
            TtpGuiApi.request_home_screen()

func _on_action_rejected(message: String) -> void:
    push_warning(message)
```

`cancel_level_load(operation_id)` returns `true` only when it closes that active operation; wrong, terminal, or stale IDs return `false` and emit no second terminal event. Godot may continue the threaded resource work, but the kit invalidates its callbacks and discards its result. The methods `configure(key, host)`, `start_level()`, `stop_level()`, and `revive()` are conventions demonstrated by `demo/scripts/level.gd`, not requirements imposed on host scenes. In the sample, returning `false` from `configure()` or `start_level()` rejects the candidate; legacy methods returning no value are treated as successful. Connect `loading_progress_changed(operation_id, progress)` to the host's progress UI if desired, and ignore progress whose ID is not the host's pending operation. A failed resource load emits `level_load_failed(operation_id, level_data, message)`, then `action_rejected(message)`, and requests the home screen.

### Report gameplay results

```gdscript
var attempt: MetaPlayResult = TtpGuiApi.begin_level_attempt("forest")
var attempt_id: String = str(attempt.context.get("attempt_id", ""))
var completion: MetaPlayResult = TtpGuiApi.complete_level(attempt_id, 3, 1250, "cave")
if completion.status == MetaPlayResult.Status.REJECTED:
    push_warning("Level completion was rejected: %s" % completion.code)
TtpGuiApi.report_level_loss(attempt_id)
```

The level-completion call records best stars and score, grants the configured completion reward when eligible, and enables `next_level_key` if it is registered. The host decides when to stop or pause its gameplay node before reporting a result.

### Signals

| Signal | Meaning |
| --- | --- |
| `level_load_started(operation_id, level_data)` | An accepted load began. The ID is unique and increasing for the lifetime of the API node. |
| `loading_progress_changed(operation_id, progress)` | Normalized, non-decreasing progress in `0.0..1.0` for the identified active operation; progress is not a terminal result. |
| `level_load_result(result)` | Typed terminal outcome (`COMPLETED`, `FAILED`, or `CANCELLED`) with correlated ID and structured context. Failure code `level.load_failed` is stable; `message` is presentation-only. |
| `level_load_completed(operation_id, level_data, resource)` | Legacy terminal success event, emitted alongside `level_load_result`. |
| `level_load_failed(operation_id, level_data, message)` | Legacy terminal failure event, emitted alongside `level_load_result`. |
| `level_load_cancelled(operation_id, level_data)` | Legacy cancellation event, emitted alongside `level_load_result` after explicit cancellation or API shutdown. |
| `level_load_exit_animation_completed(operation_id)` | The demo-compatible exit transition finished after successful resource loading. |
| `navigation_requested(screen_name, payload)` | A screen transition is requested (`home`, `game`, `levels`, `store`, `settings`, `win`, or `lose`). |
| `level_attempt_started(attempt_id, level_key)` / `level_attempt_completed(attempt_id, result)` | Gameplay attempt identity and its idempotently recorded terminal result. |
| `reward_claim_completed(result)` | A new base or optional reward claim was applied; duplicate claims do not re-emit it. |
| `session_restored(schema_version)` | One notification after the entire supported snapshot has been validated and applied. Query the facade for refreshed state after receiving it. |
| `action_rejected(message)` | A requested action or load could not be completed. |
| `currency_balance_changed(total)` / `store_catalog_changed()` | Wallet or item catalog changed. |
| `play_requested()` / `level_selected(level_data)` | An accepted play or enabled-level selection request. |
| `level_retry_requested(level_data)` / `next_level_load_requested(level_data)` | An accepted retry or progression load request. |
| `life_use_requested()` / `revive_reward_claimed(level_data)` / `reward_doubling_claimed(next_level, balance)` | Reward-related actions; ad presentation/provider integration belongs to the host. |
| `sfx_setting_changed(enabled)` / `music_setting_changed(enabled)` | A setting toggled; connect these to the host audio system. |
| `item_purchased(path)` / `item_equipped(path)` / `currency_product_credited(product_key)` | A store action succeeded. |

## Compatibility

The original `TtpGuiApi` method and signal names remain as deprecated compatibility wrappers/signals for existing integrations. Completion-related signatures have intentionally migrated: `complete_level()` and `level_win()` now require an `attempt_id` and no caller-supplied currency amount; `report_level_loss()` and revive actions also require the attempt ID; reward doubling requires a unique claim ID instead of an amount. Update existing call sites before upgrading. The legacy `loading_completed` signal carries the same `(operation_id, level_data, resource)` result as `level_load_completed`; `get_loaded_resource(path)` remains available for consumers that still use the old pull-based flow. New host code should use the semantic API above. Signals with a direct replacement are emitted alongside their new equivalents; do not connect to both for the same event. Result-modal-specific legacy signals are emitted when their matching legacy wrapper is called. `send_notification_ui()` and `manage_tap_background()` remain only for old integrations and should not be used in new code. The old `TYPES_BTN_ITEM` enum is retained as a deprecated alias for `ItemType`.

## Current limitations

The kit has no backend, automatic file IO, or persistent save system. Progress, wallet, settings, purchases, and equipped items live in memory until the host explicitly exports a snapshot and stores it with its own save system. `credit_currency_product()` credits the configured amount for a product key; it does not validate a store receipt. The demo's desktop IAP adapter is a simulation. A shipped game must validate purchases with its platform provider and protect online progress with server authority.

## Legacy reference material

Visual assets used by the demo were extracted from `interfaces/testAddons` with `demo/tools/extract_legacy_assets.py`. The archived folder remains available for reference; `interfaces/.gdignore` prevents Godot from importing the old Godot 3 project.

## Verification

`tests/` covers model invariants and repeated/invalid level loading, including retrying the same path after success, failure, or cancellation. JSON files in `scenarios/` exercise the demo's navigation, purchases, results, rewards, settings, and pause flows.
