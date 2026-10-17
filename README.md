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
| `addons/metaplay_kit/runtime/ui/meta_play_ui_config.gd` | Typed, versioned presentation profile for reusable kit UI components. |
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

### Configure reusable kit UI

The host may optionally supply a `MetaPlayUIConfig` resource once, before creating any MetaPlayKit UI components:

```gdscript
var ui_profile: MetaPlayUIConfig = load("res://config/meta_play_ui.tres") as MetaPlayUIConfig
ui_profile.text.campaign_locked_label = "Bloqueado" # Set resolved host-language text as needed.
ui_profile.text.result_score_format = "Puntuación: {score}"
TtpGuiApi.configure_ui_presentation(ui_profile)

# Create kit UI components only after configuration.
var campaign_panel: LevelCampaignPanel = LevelCampaignPanel.new()
```

Without a resource, the kit uses its internal defaults. `configure_ui_presentation(null)` restores those defaults before UI construction. Components snapshot the profile when initialized; the first component query locks configuration for the rest of the session, and later configuration attempts emit a warning and are ignored. The kit copies the supplied resource and returns isolated copies from `get_ui_presentation_config()`, so it never mutates the host's resource or exposes its stored instance. Unsupported `schema_version` values and invalid fields emit `push_warning` naming the field and fall back independently.

`MetaPlayUIConfig` exposes typed style tokens for kit components: primary/accent/text colors, font sizes, component spacing, modal overlay color, campaign button size and column count, store item height, star size/spacing, and loading-overlay margins/progress-bar height. These are logical viewport pixels. A host can create one shared `.tres` profile and tune it before instantiating kit components. The campaign columns and loading margins control layout inside those kit components; the profile does not build or reposition host-owned screens, and it does not replace the host's global theme. Icons and image assets are configured separately by #43.

The nested `MetaPlayUITextConfig` resource optionally overrides only text generated internally by kit components. It covers campaign states and score format, result titles and score format, the default continue label, and generic/equipped/owned store item labels. Empty values use English defaults; score formats must include `{score}`, and campaign score formats must also include `{stars}`. Labels, titles, descriptions, and prices supplied by the host remain authoritative. The host selects the active language and supplies already-resolved strings before it creates kit components. MetaPlayKit does not select a locale, load the host's translation catalog, or support changing language after UI construction in this version. A host should provide a visible label for each result action; actions without labels are omitted.

For supported graphic slots, `MetaPlayUIConfig` accepts typed `Texture2D` overrides from anywhere in the host project's `res://` namespace. The current slots are `active_star_texture`, `inactive_star_texture`, and `loading_background_texture`; a null value keeps the corresponding kit asset. For individual store products, provide an optional `icon_path` using a `res://` path in the item definition. The button loads it as a `Texture2D`; missing paths and other resource types warn and leave the item without an icon. These strings remain serializable in session inventory snapshots. The profile does not accept arbitrary slots or modify UI assembled by the host. For example:

```gdscript
ui_profile.active_star_texture = load("res://art/ui/star_gold.png") as Texture2D
ui_profile.loading_background_texture = load("res://art/ui/loading_screen.png") as Texture2D
TtpGuiApi.configure_ui_presentation(ui_profile)

TtpGuiApi.configure_items({
    "energy": {"title": "Energy", "icon_path": "res://art/items/energy.png", "price": "100"},
})
```

### Configure a session

```gdscript
TtpGuiApi.configure_levels({
    "forest": {
        "name": "Forest",
        "scene_path": "res://levels/forest.tscn",
    },
    "cave": {
        "name": "Cave",
        "scene_path": "res://levels/cave.tscn",
    },
})
TtpGuiApi.configure_level_result_rules({
    "forest": {
        "max_score": 1500,
        "star_thresholds": [500, 900, 1200],
        "required_conditions": ["goal_reached"],
    },
    "cave": {
        "max_score": 1800,
        "star_thresholds": [600, 1100, 1500],
        "required_conditions": ["boss_defeated", "exit_reached"],
    },
})
TtpGuiApi.configure_campaign_projection([
    {"key": "forest", "available": true, "selectable": true},
    {"key": "cave", "available": false, "selectable": false},
])
TtpGuiApi.configure_settings({"sfx": true, "music": true})
TtpGuiApi.configure_items(item_catalog)
TtpGuiApi.configure_currency_products(currency_products)
TtpGuiApi.configure_currency_rewards({"small_pack": 500, "large_pack": 2500})
TtpGuiApi.set_currency_balance(250)
```

A level catalog entry contains static data such as `name` and `scene_path`. Configure result rules separately with a maximum score, three ordered star thresholds, and required condition keys. The host reports boolean facts for those keys; every required condition must be true for a win. A winning result below the one-star threshold remains a win with zero stars. `configure_campaign_projection()` supplies ordered availability and selection flags for reusable campaign UI; the host owns those decisions. Item catalogs support basic, equippable, and phased entries; phased entries are addressed by paths such as `["power_boost", "phase1"]`. Currency reward values map product keys to the balance granted when credited.

### Commands and queries

| Purpose | Public methods |
| --- | --- |
| Configure presentation | `configure_ui_presentation`, `get_ui_presentation_config` |
| Configure session data | `configure_levels`, `configure_level_result_rules`, `configure_campaign_projection`, `configure_settings`, `configure_items`, `configure_currency_products`, `configure_currency_rewards`, `set_currency_balance` |
| Load and progress | `request_initial_level_load(key)`, `request_level_load(key) -> bool` (compatibility), `request_level_load_result(key) -> MetaPlayResult`, `cancel_level_load(operation_id)`, `begin_level_attempt(key) -> MetaPlayResult`, `complete_level(attempt_id, score, condition_facts, presentation) -> MetaPlayResult`, `retry_level(key) -> MetaPlayResult`, `request_next_level_load(key) -> MetaPlayResult` |
| Store and wallet | `purchase_item(path) -> MetaPlayResult`, `equip_item(path) -> MetaPlayResult`, `credit_currency_product(product_key) -> MetaPlayResult`, `begin_currency_purchase(product_key) -> MetaPlayResult`, `mark_currency_purchase_pending(operation_id, purchase) -> MetaPlayResult`, `complete_currency_purchase(operation_id, product_key, purchase) -> MetaPlayResult`, `apply_verified_currency_purchase(operation_id) -> MetaPlayResult`, `fail_currency_purchase(operation_id, provider_code) -> MetaPlayResult`, `cancel_currency_purchase(operation_id) -> MetaPlayResult`, `restore_purchase_records(purchases) -> MetaPlayResult`, `apply_restored_currency_purchase(transaction_id) -> MetaPlayResult` |
| Settings and rewards | `toggle_sfx`, `toggle_music`, `configure_completion_rewards(rewards, cooldown_seconds)`, `request_terminal_action(attempt_id, action_id)` |
| Host-owned state | `set_session_feature_state(key, state) -> MetaPlayResult`, `get_session_feature_state(key)`, `export_session_state() -> MetaPlayResult`, `restore_session_state(snapshot) -> MetaPlayResult` |
| Navigation | `request_home_screen`, `request_level_selection_screen`, `request_store_screen`, `request_settings_screen`, `start_or_resume_game(level_key) -> MetaPlayResult`, `select_level(key) -> MetaPlayResult` (emits host intent; does not load) |
| Read level/session state | `get_level(key)`, `get_levels`, `get_level_progress(key)`, `get_all_level_progress`, `get_campaign_projection` |
| Read store/settings state | `get_settings`, `get_items`, `get_item(path)`, `get_currency_products`, `get_currency_balance`, `get_item_type_values` |
| Loading/presentation helpers | `get_loaded_resource(path)`, `is_loading`, `format_number(value)` |

`begin_level_attempt()` issues an opaque attempt ID when the host is ready to enter gameplay. It is distinct from the load operation ID. The host chooses the level before calling it; MetaPlayKit does not check campaign availability. Beginning another attempt abandons prior active/lost attempts.

`complete_level(attempt_id, score, condition_facts, presentation)` validates the submitted score and required boolean facts against the registered rules. Every configured required condition must be true to win. A win's stars are calculated from the inclusive one/two/three-star thresholds; a successful result below the first threshold gets zero stars, and any loss gets zero stars. Best score and stars are stored separately from catalog and campaign availability. Identical result submissions are idempotent; conflicting or stale submissions are rejected. The optional `presentation` dictionary can provide a `next_level` entry and `actions` such as retry, continue, revive, or a bonus offer. `LevelResultPanel` is an optional reusable UI control that displays the evaluated outcome and supplied actions; the host still owns navigation and handles action requests.

Base completion rewards remain a kit-owned wallet feature: configure them with `configure_completion_rewards({"forest": 120}, cooldown_seconds)`. Optional result actions are host-owned. Connect `terminal_action_requested(attempt_id, action_id)`, validate the selected offer in the host, and apply its effect there. The kit does not grant optional currency, lives, shots, or ad rewards and does not keep their idempotency ledger; the host must persist and deduplicate its own claims.

`configure_campaign_projection()` accepts an ordered array of `{key, available, selectable}` entries for the optional `LevelCampaignPanel`. `select_level(key)` validates that the host marked the entry selectable, then emits `level_selection_requested(key)`; it does not begin a load. The host handles the event and calls `request_level_load(key)` if its policy accepts the choice. The generic load API validates registered level data and load lifecycle only; it does not enforce campaign availability. `get_level_progress()` returns copied completion and best-result records, while campaign order and availability remain host-owned.

`export_session_state()` returns a deep-copied snapshot at schema version 4. The snapshot contains level result records, wallet, settings, inventory, completion/reward ledger, verified purchase transaction IDs, and serializable feature state, but not the host's catalog, result rules, campaign projection, or terminal presentation. Configure the catalog/rules/campaign before restore. The host owns storage and calls `restore_session_state(snapshot)` explicitly. Restore validates the complete snapshot atomically and emits one `session_restored(schema_version)` signal after success. Version 3 snapshots migrate to version 4 with an empty purchase ledger; version 2 and earlier remain unsupported. Local snapshots are not authoritative against a modified client; online games must validate rewards and transaction IDs on their server.

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

`request_level_load_result(key)` returns `ACCEPTED` with the load operation ID when the registered resource can be requested; `request_level_load(key) -> bool` remains a compatibility wrapper. The host must authorize campaign access before calling it. `select_level(key)` returns a synchronous completed/rejected result for the UI intent and emits `level_selection_requested` on acceptance; it never starts a load. `start_or_resume_game(level_key)` and `request_next_level_load(level_key)` require explicit host-selected keys. The compatibility `load_next_level()` and `get_next_available_level()` no longer infer a destination. Observe `level_load_result` for the later resource outcome. Rejection codes include `level.not_found`, `level.scene_path_missing`, `level.load_in_progress`, and `level.no_available_level`; campaign and rule validation use `level.selection_not_allowed`, `campaign.projection_invalid`, and `level.rules_invalid`. Gameplay is presented by the host after the load completes and a valid level instance is created.

### Typed operation results

`MetaPlayResult` is the shared typed result contract for facade commands. Its `status` is one of `ACCEPTED`, `COMPLETED`, `REJECTED`, `FAILED`, or `CANCELLED`; `code` is a stable `StringName` for rejected or failed outcomes; `operation_id` correlates asynchronous acceptance with its terminal result; and `context` carries structured details as a defensive deep copy. Accepted, successful, and cancelled outcomes have no error code. Synchronous results use operation ID `0`; accepted, failed, and cancelled asynchronous results require a positive ID. Create results with `MetaPlayResult.accepted()`, `completed()`, `rejected()`, `failed()`, and `cancelled()` so these invariants are checked. Progression, store commands, level loading and currency purchase operations use this type.

Progression rejections also continue to emit the legacy `action_rejected` and `operation_rejected` message signals for existing consumers. New integrations should handle the returned result and avoid processing the same rejection again through a legacy signal. Store and wallet commands return `MetaPlayResult` as well: purchase/equip failures use stable codes such as `store.item_not_found`, `store.item_already_owned`, `store.item_not_owned`, `store.item_not_equippable`, and `wallet.insufficient_funds`; unknown currency products use `currency.product_not_found`. Rejected results include structured item/product context, and insufficient-funds context includes both required cost and current balance. Successful purchase/equip results include the updated item snapshot; successful currency credit includes the amount added and resulting balance. Store failures continue to emit legacy rejection messages, so integrations should consume the typed return and not handle the same failure again through `action_rejected`. Load consumers can migrate to `level_load_result(result: MetaPlayResult)`, emitted exactly once for each accepted operation with `COMPLETED`, `FAILED`, or `CANCELLED` status and the same operation ID. Its context contains `level_key`, a copied `level_data`, and `scene_path`; success also contains the exact loaded `resource`, while failure uses stable code `level.load_failed` and includes the loader's presentation-only `message`. Existing terminal signals remain available during migration; do not handle both the typed result and legacy terminal event for the same behavior.

Purchase operations use stable codes including `purchase.in_progress`, `purchase.operation_stale`, `purchase.product_mismatch`, `purchase.not_verified`, `purchase.signature_invalid`, `purchase.receipt_invalid`, `purchase.verifier_not_configured`, `purchase.provider_unavailable`, and `purchase.transaction_conflict`. Provider-specific failure codes are included as context; user-facing messages are not stable contract values.

### Correlated currency purchases

The facade arbitrates one currency purchase at a time. `begin_currency_purchase(product_key)` validates the configured product and returns `ACCEPTED` with a unique, increasing `operation_id`; a second in-flight request is rejected with `purchase.in_progress`. The host passes that ID to its provider adapter. A verified purchase calls `complete_currency_purchase(operation_id, product_key, purchase_data)`; pending, failed and cancelled purchases use their respective methods. Each accepted operation emits exactly one terminal `currency_purchase_result(result)` with `COMPLETED`, `FAILED`, or `CANCELLED`; a pending result emits `currency_purchase_pending` and keeps the operation active. Unknown IDs and duplicate/late callbacks are rejected with `purchase.operation_stale`; a mismatched product fails with `purchase.product_mismatch`.

Completion does **not** immediately credit the wallet. For a provider-verified result, the facade creates an operation-scoped grant that can be applied once with `apply_verified_currency_purchase(operation_id)`. The model records the provider transaction ID and returns a duplicate result without crediting twice. The transaction ledger is included in the host-owned session snapshot. `credit_currency_product()` remains available for non-store/manual flows and for the explicitly simulated demo adapter.

```gdscript
var purchase: MetaPlayResult = TtpGuiApi.begin_currency_purchase("small_pack")
if purchase.status == MetaPlayResult.Status.ACCEPTED:
    var operation_id: int = purchase.operation_id
    # Pass operation_id through PurchaseProviderAdapter.begin_purchase().

func _on_provider_purchase_succeeded(operation_id: int, purchase: Dictionary) -> void:
    var result: MetaPlayResult = TtpGuiApi.complete_currency_purchase(
        operation_id,
        purchase.get("product_key"),
        purchase,
    )
    if result.status == MetaPlayResult.Status.COMPLETED and not bool(result.context.get("simulated", false)):
        var grant: MetaPlayResult = TtpGuiApi.apply_verified_currency_purchase(operation_id)
        if grant.status == MetaPlayResult.Status.COMPLETED and not bool(grant.context.get("duplicate", false)):
            play_provider.consume_purchase(purchase)
```

#### Provider boundary and Google Play

`PurchaseProviderAdapter` defines the provider-neutral signals and methods. A host can implement its own subclass and verification flow, or use `GooglePlayPurchaseProvider` for the optional `GodotPayments` Android singleton. The Google Play adapter verifies the signed purchase JSON with the app-specific Play Console public key, checks the signed product ID and purchase state, and exposes the purchase token as `transaction_id`. Configure the public key before starting purchases:

```gdscript
var play_provider: GooglePlayPurchaseProvider = GooglePlayPurchaseProvider.new()
var key_result: MetaPlayResult = play_provider.configure_license_public_key(play_console_public_key)
if key_result.status == MetaPlayResult.Status.COMPLETED:
    add_child(play_provider)
    play_provider.purchase_succeeded.connect(_on_provider_purchase_succeeded)
    play_provider.purchase_pending.connect(_on_provider_purchase_pending)
    play_provider.purchase_failed.connect(_on_provider_purchase_failed)
```

The host starts the kit operation, then passes its ID and the configured Play product ID to `begin_purchase()`. `IapAdapter` is the explicit desktop simulation: it emits `provider: "simulation"` and `verified: false`, and cannot be mistaken for a verified store result. Host-authored adapters may use a server verifier and emit the normalized provider result with their own provider ID.

`restore_purchases()` requests the provider's owned-purchase query. The Google bridge calls `has_purchased(receipt, signature, sku)` for returned purchases and `finish_restore()` when that query is complete. Only locally signature-verified, purchased records are emitted. The host receives those records through `restore_purchase_records()` and decides how its product catalog maps them to durable entitlements. Consumable currency can be applied with `apply_restored_currency_purchase(transaction_id)`; the transaction ledger prevents the same token from granting twice. The Google adapter disables automatic consumption. The host calls `consume_purchase(purchase)` only after applying a consumable grant; non-consumable acknowledgement and subscription lifecycle remain host/backend policy.

The Google adapter's local signature check establishes that the receipt was signed for the configured app key and matches the product/purchase state; it does not query Google's current purchase state and cannot detect later refunds or revocations. Google's current guidance recommends sending purchase tokens to a secure backend, verifying them through the Google Play Developer API, checking token uniqueness, and granting benefits only after verification ([purchase integration](https://developer.android.com/google/play/billing/integrate), [fraud and abuse guidance](https://developer.android.com/google/play/billing/security)). The kit keeps a host-provider seam for that stronger server-side flow. Local snapshot idempotency improves callback/restart behavior but is not tamper-proof or shared across devices.

### Explicit legacy events

`send_notification_ui(signal_name, parameter)` is deprecated. It no longer emits arbitrary signal names dynamically. It accepts only the following legacy event aliases and validates their argument shape: `new_total_coins(int)`, `store_game_update_item_loadded(value)`, `store_game_buy_item(Array)`, `store_currency_buy_coins(value)`, `level_selector_load_new_level_selected(Dictionary)`, `modal_win_video_reward_showed(Array)`, and the no-argument events `home_tap_to_play_pressed`, `modal_lose_use_life_pressed`, `modal_config_change_sfx_status`, and `modal_config_change_music_status`. A valid call emits only the named legacy signal once and returns `COMPLETED`; it does not also emit a replacement semantic signal. Unsupported aliases return `REJECTED` with `api.event_unsupported`; wrong argument shapes return `api.event_arguments_invalid`. New integrations should call the corresponding facade method or emit their own host-owned event directly.

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
            "scene_path": "res://levels/forest.tscn",
        },
    })
    TtpGuiApi.configure_level_result_rules({
        "forest": {
            "max_score": 1500,
            "star_thresholds": [500, 900, 1200],
            "required_conditions": ["goal_reached"],
        },
    })
    TtpGuiApi.configure_campaign_projection([
        {"key": "forest", "available": true, "selectable": true},
    ])
    TtpGuiApi.request_initial_level_load("forest")

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
var completion: MetaPlayResult = TtpGuiApi.complete_level(attempt_id, 1250, {"goal_reached": true}, {"next_level": {"key": "cave", "label": "Continue"}, "actions": []})
if completion.status == MetaPlayResult.Status.REJECTED:
    push_warning("Level completion was rejected: %s" % completion.code)
```

The host reports score and facts; MetaPlayKit evaluates its configured conditions and star thresholds, then records the result. The host decides when to stop or pause gameplay and chooses any next destination. `LevelResultPanel` and `LevelCampaignPanel` are optional reusable presentation components; their action and selection signals return decisions to the host. The kit does not unlock levels or apply optional action rewards.

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
| `reward_claim_completed(result)` | A configured base completion reward was credited. Optional terminal actions do not grant rewards in the kit. |
| `session_restored(schema_version)` | One notification after the entire supported snapshot has been validated and applied. Query the facade for refreshed state after receiving it. |
| `action_rejected(message)` | A requested action or load could not be completed. |
| `currency_balance_changed(total)` / `store_catalog_changed()` | Wallet or item catalog changed. |
| `currency_purchase_pending(operation_id, purchase)` | A verified provider reported an asynchronous pending purchase; the operation stays open and grants no currency. |
| `currency_purchase_result(result)` | One terminal result per accepted purchase operation. |
| `currency_purchase_applied(result)` | A verified, non-duplicate transaction was credited to the wallet. |
| `currency_purchases_restored(purchases)` | The latest provider restore query returned verified purchase records for host-owned entitlement mapping. |
| `play_requested()` / `level_selected(level_data)` | Compatibility signals. New integrations should use explicit host destination keys and `level_selection_requested(level_key)`. |
| `level_selection_requested(level_key)` | The reusable campaign UI requests a host decision; the kit does not load the selected level. |
| `terminal_action_requested(attempt_id, action_id)` | A result-panel action was selected; the host validates and applies it. |
| `level_retry_requested(level_data)` / `next_level_load_requested(level_data)` | An accepted retry or progression load request. |
| `life_use_requested()` / `revive_reward_claimed(level_data)` / `reward_doubling_claimed(next_level, balance)` | Deprecated compatibility notifications; new optional result actions are host-owned requests. |
| `sfx_setting_changed(enabled)` / `music_setting_changed(enabled)` | A setting toggled; connect these to the host audio system. |
| `item_purchased(path)` / `item_equipped(path)` / `currency_product_credited(product_key)` | A store action succeeded. |

## Compatibility

Compatibility wrappers remain for legacy integrations, but campaign authorization and result actions now belong to the host. `complete_level()` requires the attempt ID, score, and condition facts; it returns the evaluated result and does not accept host-selected stars, progression, or optional rewards. Initial, resume, and next-level loading require an explicit host-selected destination. `load_next_level()` and `get_next_available_level()` do not infer one. The legacy `loading_completed` signal carries the same `(operation_id, level_data, resource)` result as `level_load_completed`; `get_loaded_resource(path)` remains available for consumers that still use the pull-based flow. `send_notification_ui()` is restricted to its documented alias map and is deprecated; migrate each call to an explicit facade operation or host-owned signal. Currency purchase completion now requires provider verification data and a separate operation-scoped grant call. Version 3 snapshots are migrated once to version 4; snapshots older than version 3 are unsupported. Do not connect to both a legacy signal and its replacement for the same behavior.

Public API compatibility follows semantic versioning aligned with the addon version: backward-compatible additions are minor releases; compatible fixes are patch releases; removed methods/signals or incompatible signature/behavior changes require a major release. Deprecated entry points remain available through the current major version. A removal requires a migration guide and deprecation notice in at least one minor release before the major version that removes it. Stable result codes are machine-readable contract values; human-readable messages may change and must not be used for branching.

| Legacy entry point | Preferred replacement |
| --- | --- |
| `send_notification_ui(name, parameter)` | An explicit `TtpGuiApi` command/result signal or a host-owned event; arbitrary signal emission is unsupported. |
| `add_coin_purchased(product_key)` / direct `credit_currency_product()` after an uncorrelated callback | `begin_currency_purchase()` followed by correlated provider verification and `apply_verified_currency_purchase(operation_id)`. |
| Boolean `request_level_load(key)` | `request_level_load_result(key)` and `level_load_result`. |
| Legacy load terminal signals | `level_load_result(result)`; handle only one terminal path per operation. |
| `complete_level()` with legacy/mutable progression decisions | `begin_level_attempt()` and typed `complete_level(attempt_id, score, condition_facts, presentation)`. |

## Current limitations

The kit has no backend, automatic file IO, or persistent save system. Progress, wallet, settings, purchases, and equipped items live in memory until the host explicitly exports a snapshot and stores it with its own save system. Google Play signature checking runs in the client and does not query purchase status after refunds/revocations. The demo's desktop IAP adapter is a simulation. Production games should use a secure backend to verify Google Play purchase tokens, handle acknowledgements/consumption, deduplicate globally, and protect online progress with server authority; a host-supplied provider can perform that workflow.

## Legacy reference material

Visual assets used by the demo were extracted from `interfaces/testAddons` with `demo/tools/extract_legacy_assets.py`. The archived folder remains available for reference; `interfaces/.gdignore` prevents Godot from importing the old Godot 3 project.

## Verification

`tests/` covers model invariants and repeated/invalid level loading, including retrying the same path after success, failure, or cancellation. JSON files in `scenarios/` exercise the demo's navigation, purchases, results, rewards, settings, and pause flows.
