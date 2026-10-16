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
| Load and progress | `request_initial_level_load`, `request_level_load(key) -> bool`, `cancel_level_load(operation_id)`, `select_level(key) -> MetaPlayResult`, `complete_level(key, stars, score, reward_currency, next_level_key) -> MetaPlayResult`, `report_level_loss(key)`, `retry_level(key) -> MetaPlayResult`, `load_next_level() -> MetaPlayResult` |
| Store and wallet | `purchase_item(path)`, `equip_item(path)`, `credit_currency_product(product_key)` |
| Settings and rewards | `toggle_sfx`, `toggle_music`, `revive_after_reward(key)`, `claim_reward_doubling(extra_currency)`, `use_life()` |
| Navigation | `request_home_screen`, `request_level_selection_screen`, `request_store_screen`, `request_settings_screen`, `start_or_resume_game() -> MetaPlayResult` |
| Read level/session state | `get_level(key)`, `get_levels`, `get_enabled_level_keys`, `get_next_available_level` |
| Read store/settings state | `get_settings`, `get_items`, `get_item(path)`, `get_currency_products`, `get_currency_balance`, `get_item_type_values` |
| Loading/presentation helpers | `get_loaded_resource(path)`, `is_loading`, `format_number(value)` |

`complete_level()` returns `MetaPlayResult.Status.COMPLETED` after applying progress and rewards, or `REJECTED` with a stable code when it cannot apply the completion. `select_level()`, `retry_level()`, `load_next_level()`, and `start_or_resume_game()` return `ACCEPTED` with the load operation ID only after a load request starts; otherwise they return `REJECTED`. The accepted command result describes request admission, not the later scene-load outcome: observe `level_load_completed`, `level_load_failed`, or `level_load_cancelled` for that lifecycle. Direct `request_level_load()` still returns `bool` in this story; its typed terminal-result migration remains separate. Rejection codes include `level.not_found`, `level.locked`, `level.scene_path_missing`, `level.load_in_progress`, and `level.no_available_level`. Legacy `action_rejected` messages continue to emit during migration. Gameplay is presented by the host after the load completes and a valid level instance is created. The host owns stopping/pausing its gameplay node and deciding how to persist session state.

### Typed operation results

`MetaPlayResult` is the shared typed result contract for the gradual migration of facade commands. Its `status` is one of `ACCEPTED`, `COMPLETED`, `REJECTED`, `FAILED`, or `CANCELLED`; `code` is a stable `StringName` for rejected or failed outcomes; `operation_id` correlates asynchronous acceptance with its terminal result; and `context` carries structured details as a defensive deep copy. Accepted, successful, and cancelled outcomes have no error code. Synchronous results use operation ID `0`; accepted, failed, and cancelled asynchronous results require a positive ID. Create results with `MetaPlayResult.accepted()`, `completed()`, `rejected()`, `failed()`, and `cancelled()` so these invariants are checked. Progression facade commands now return this type; store commands and typed terminal load results will migrate in follow-up stories.

Progression rejections also continue to emit the legacy `action_rejected` and `operation_rejected` message signals for existing consumers. New integrations should handle the returned result and avoid processing the same rejection again through a legacy signal. The load terminal signals keep their current signatures until their separate migration story; use the operation ID on the accepted progression result to correlate that existing load lifecycle.

### Loading integration

Connect before requesting the initial level. Every accepted request gets a monotonically increasing `operation_id`. The start, progress, and terminal signals carry that same ID, so a host can correlate events even when the same scene is requested repeatedly. `loading_progress_changed` begins at `0.0`; values are clamped to `0.0..1.0` and never decrease during one operation. On success, progress reaches `1.0` before `level_load_completed`. Progress is an estimate of loader work: only `level_load_completed`, `level_load_failed`, or `level_load_cancelled` determines the terminal outcome, so progress reaching `1.0` alone does not mean success. Every accepted operation emits exactly one of those terminal results. A successful completion includes the exact loaded `Resource` and level definition for that operation. Rejected requests emit no load lifecycle events. `get_loaded_resource(path)` remains as a compatibility helper and consumes the ready resource; new integrations should use the resource delivered by the completion signal.

```gdscript
extends Node

var _pending_operation_id: int = 0
var _current_level: Node = null

func _ready() -> void:
    TtpGuiApi.level_load_started.connect(_on_level_load_started)
    TtpGuiApi.level_load_completed.connect(_on_level_load_completed)
    TtpGuiApi.level_load_failed.connect(_on_level_load_failed)
    TtpGuiApi.level_load_cancelled.connect(_on_level_load_cancelled)
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

func _on_level_load_completed(operation_id: int, level_data: Dictionary, resource: Resource) -> void:
    if operation_id != _pending_operation_id:
        return
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

func _on_level_load_failed(operation_id: int, _level_data: Dictionary, message: String) -> void:
    if operation_id != _pending_operation_id:
        return
    _pending_operation_id = 0
    push_warning("Level load %d failed: %s" % [operation_id, message])
    TtpGuiApi.request_home_screen()

func _on_level_load_cancelled(operation_id: int, _level_data: Dictionary) -> void:
    if operation_id != _pending_operation_id:
        return
    _pending_operation_id = 0
    TtpGuiApi.request_home_screen()

func _on_action_rejected(message: String) -> void:
    push_warning(message)
```

`cancel_level_load(operation_id)` returns `true` only when it closes that active operation; wrong, terminal, or stale IDs return `false` and emit no second terminal event. Godot may continue the threaded resource work, but the kit invalidates its callbacks and discards its result. The methods `configure(key, host)`, `start_level()`, `stop_level()`, and `revive()` are conventions demonstrated by `demo/scripts/level.gd`, not requirements imposed on host scenes. In the sample, returning `false` from `configure()` or `start_level()` rejects the candidate; legacy methods returning no value are treated as successful. Connect `loading_progress_changed(operation_id, progress)` to the host's progress UI if desired, and ignore progress whose ID is not the host's pending operation. A failed resource load emits `level_load_failed(operation_id, level_data, message)`, then `action_rejected(message)`, and requests the home screen.

### Report gameplay results

```gdscript
var completion: MetaPlayResult = TtpGuiApi.complete_level("forest", 3, 1250, 120, "cave")
if completion.status == MetaPlayResult.Status.REJECTED:
    push_warning("Level completion was rejected: %s" % completion.code)
TtpGuiApi.report_level_loss("forest")
```

The level-completion call records best stars and score, grants the configured session currency reward, and enables `next_level_key` if it is registered. The host decides when to stop or pause its gameplay node before reporting a result.

### Signals

| Signal | Meaning |
| --- | --- |
| `level_load_started(operation_id, level_data)` | An accepted load began. The ID is unique and increasing for the lifetime of the API node. |
| `loading_progress_changed(operation_id, progress)` | Normalized, non-decreasing progress in `0.0..1.0` for the identified active operation; progress is not a terminal result. |
| `level_load_completed(operation_id, level_data, resource)` | Terminal success: the requested resource became ready. `resource` is the exact resource for this operation. |
| `level_load_failed(operation_id, level_data, message)` | Terminal failure: resource loading failed; never emitted together with success for the same ID. |
| `level_load_cancelled(operation_id, level_data)` | Terminal cancellation after `cancel_level_load(operation_id)` or when the API node exits the tree during an active load. |
| `level_load_exit_animation_completed(operation_id)` | The demo-compatible exit transition finished after successful resource loading. |
| `navigation_requested(screen_name, payload)` | A screen transition is requested (`home`, `game`, `levels`, `store`, `settings`, `win`, or `lose`). |
| `action_rejected(message)` | A requested action or load could not be completed. |
| `currency_balance_changed(total)` / `store_catalog_changed()` | Wallet or item catalog changed. |
| `play_requested()` / `level_selected(level_data)` | An accepted play or enabled-level selection request. |
| `level_retry_requested(level_data)` / `next_level_load_requested(level_data)` | An accepted retry or progression load request. |
| `life_use_requested()` / `revive_reward_claimed(level_data)` / `reward_doubling_claimed(next_level, balance)` | Reward-related actions; ad presentation/provider integration belongs to the host. |
| `sfx_setting_changed(enabled)` / `music_setting_changed(enabled)` | A setting toggled; connect these to the host audio system. |
| `item_purchased(path)` / `item_equipped(path)` / `currency_product_credited(product_key)` | A store action succeeded. |

## Compatibility

The original `TtpGuiApi` method and signal names remain as deprecated compatibility wrappers/signals for existing integrations. The legacy `loading_completed` signal carries the same `(operation_id, level_data, resource)` result as `level_load_completed`; `get_loaded_resource(path)` remains available for consumers that still use the old pull-based flow. New host code should use the semantic API above. Signals with a direct replacement are emitted alongside their new equivalents; do not connect to both for the same event. Result-modal-specific legacy signals are emitted when their matching legacy wrapper is called. `send_notification_ui()` and `manage_tap_background()` remain only for old integrations and should not be used in new code. The old `TYPES_BTN_ITEM` enum is retained as a deprecated alias for `ItemType`.

## Current limitations

The kit has no backend or persistent save system. Progress, wallet, settings, purchases, and equipped items live in memory for the session. `credit_currency_product()` credits the configured amount for a product key; it does not validate a store receipt. The demo's desktop IAP adapter is a simulation. A shipped game must validate purchases with its platform provider and decide how to persist player progress.

## Legacy reference material

Visual assets used by the demo were extracted from `interfaces/testAddons` with `demo/tools/extract_legacy_assets.py`. The archived folder remains available for reference; `interfaces/.gdignore` prevents Godot from importing the old Godot 3 project.

## Verification

`tests/` covers model invariants and repeated/invalid level loading, including retrying the same path after success, failure, or cancellation. JSON files in `scenarios/` exercise the demo's navigation, purchases, results, rewards, settings, and pause flows.
