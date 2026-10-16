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
| Load and progress | `request_initial_level_load`, `request_level_load(key)`, `select_level(key)`, `complete_level(key, stars, score, reward_currency, next_level_key)`, `report_level_loss(key)`, `retry_level(key)`, `load_next_level()` |
| Store and wallet | `purchase_item(path)`, `equip_item(path)`, `credit_currency_product(product_key)` |
| Settings and rewards | `toggle_sfx`, `toggle_music`, `revive_after_reward(key)`, `claim_reward_doubling(extra_currency)`, `use_life()` |
| Navigation | `request_home_screen`, `request_level_selection_screen`, `request_store_screen`, `request_settings_screen`, `start_or_resume_game` |
| Read level/session state | `get_level(key)`, `get_levels`, `get_enabled_level_keys`, `get_next_available_level` |
| Read store/settings state | `get_settings`, `get_items`, `get_item(path)`, `get_currency_products`, `get_currency_balance`, `get_item_type_values` |
| Loading/presentation helpers | `get_loaded_resource(path)`, `is_loading`, `format_number(value)` |

`start_or_resume_game()` requests loading of the next available level. Gameplay is presented by the host after the load completes and a valid level instance is created. `request_level_load()` returns `true` when the request is accepted and `false` when it is rejected; rejection details are emitted through `action_rejected`. Only one load request can be active at a time, and direct requests as well as `select_level()` reject locked levels and levels without a scene path. `select_level()`, retry, next-level, and play-request signals are emitted only after their load request is accepted. `complete_level()` records progress and requests the `win` screen. The host owns stopping/pausing its gameplay node and deciding how to persist session state.

### Loading integration

Connect before requesting the initial level. The host receives the level definition (including `key`) at `level_load_started`, then retrieves the ready resource after `level_load_completed`. `get_loaded_resource(path)` consumes the ready resource, so a second immediate read returns `null`.

```gdscript
extends Node

var _pending_path: String = ""
var _pending_key: Variant = null

func _ready() -> void:
    TtpGuiApi.level_load_started.connect(_on_level_load_started)
    TtpGuiApi.level_load_completed.connect(_on_level_load_completed)
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

func _on_level_load_started(level_data: Dictionary) -> void:
    _pending_path = str(level_data.get("scene_path", ""))
    _pending_key = level_data.get("key")
    # Show the host game's loading UI.

func _on_level_load_completed() -> void:
    var packed_scene: PackedScene = TtpGuiApi.get_loaded_resource(_pending_path) as PackedScene
    if packed_scene == null:
        TtpGuiApi.request_home_screen()
        return
    var level: Node = packed_scene.instantiate()
    add_child(level)
    if level.has_method("configure"):
        level.call("configure", _pending_key, self)
    if level.has_method("start_level"):
        level.call("start_level")
    # Replace the current level and present gameplay in the host UI.

func _on_action_rejected(message: String) -> void:
    push_warning(message)
```

The methods `configure(key, host)`, `start_level()`, `stop_level()`, and `revive()` are conventions demonstrated by `demo/scripts/level.gd`, not requirements imposed on host scenes. Connect `loading_progress_changed(progress)` to the host's progress UI if desired. A failed load emits `action_rejected` and requests the home screen.

### Report gameplay results

```gdscript
TtpGuiApi.complete_level("forest", 3, 1250, 120, "cave")
TtpGuiApi.report_level_loss("forest")
```

The level-completion call records best stars and score, grants the configured session currency reward, and enables `next_level_key` if it is registered. The host decides when to stop or pause its gameplay node before reporting a result.

### Signals

| Signal | Meaning |
| --- | --- |
| `level_load_started(level_data)` / `level_load_completed()` | An accepted level load started / its resource became ready. |
| `loading_progress_changed(progress)` / `level_load_exit_animation_completed()` | Loading progress and completion of the demo-compatible exit transition. |
| `navigation_requested(screen_name, payload)` | A screen transition is requested (`home`, `game`, `levels`, `store`, `settings`, `win`, or `lose`). |
| `action_rejected(message)` | A requested action or load could not be completed. |
| `currency_balance_changed(total)` / `store_catalog_changed()` | Wallet or item catalog changed. |
| `play_requested()` / `level_selected(level_data)` | An accepted play or enabled-level selection request. |
| `level_retry_requested(level_data)` / `next_level_load_requested(level_data)` | An accepted retry or progression load request. |
| `life_use_requested()` / `revive_reward_claimed(level_data)` / `reward_doubling_claimed(next_level, balance)` | Reward-related actions; ad presentation/provider integration belongs to the host. |
| `sfx_setting_changed(enabled)` / `music_setting_changed(enabled)` | A setting toggled; connect these to the host audio system. |
| `item_purchased(path)` / `item_equipped(path)` / `currency_product_credited(product_key)` | A store action succeeded. |

## Compatibility

The original `TtpGuiApi` method and signal names remain as deprecated compatibility wrappers/signals for existing integrations. New host code should use the semantic API above. Signals with a direct replacement are emitted alongside their new equivalents; do not connect to both for the same event. Result-modal-specific legacy signals are emitted when their matching legacy wrapper is called. `send_notification_ui()` and `manage_tap_background()` remain only for old integrations and should not be used in new code. The old `TYPES_BTN_ITEM` enum is retained as a deprecated alias for `ItemType`.

## Current limitations

The kit has no backend or persistent save system. Progress, wallet, settings, purchases, and equipped items live in memory for the session. `credit_currency_product()` credits the configured amount for a product key; it does not validate a store receipt. The demo's desktop IAP adapter is a simulation. A shipped game must validate purchases with its platform provider and decide how to persist player progress.

## Legacy reference material

Visual assets used by the demo were extracted from `interfaces/testAddons` with `demo/tools/extract_legacy_assets.py`. The archived folder remains available for reference; `interfaces/.gdignore` prevents Godot from importing the old Godot 3 project.

## Verification

`tests/` covers model invariants and repeated/invalid level loading. JSON files in `scenarios/` exercise the demo's navigation, purchases, results, rewards, settings, and pause flows.
