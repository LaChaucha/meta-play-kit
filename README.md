# MetaPlayKit

MetaPlayKit is a reusable Godot 4.7 meta-game kit with a sample game that shows how to integrate it. The kit provides a public API, progression and store rules, asynchronous resource loading, reusable UI components, a theme, and UI assets. The demo project is the example consumer; its level gameplay and screens are sample implementations.

## Run the demo

Open the repository root's `project.godot` in Godot 4.7 and run the main scene. The demo uses a 1280 × 720 logical viewport with `canvas_items` stretching.

## Repository layout

| Path | Purpose |
| --- | --- |
| `addons/metaplay_kit/plugin.cfg` and `plugin.gd` | Godot editor plugin. Enabling it registers the `TtpGuiApi` autoload in a consuming project. |
| `addons/metaplay_kit/runtime/api/` | Public runtime facade and signals. |
| `addons/metaplay_kit/runtime/model/` | Level progression, currency, configuration, and store rules. |
| `addons/metaplay_kit/runtime/systems/` | Asynchronous resource loading. |
| `addons/metaplay_kit/runtime/components/` | Reusable blocking background, draggable list, star rating, and store-item controls. |
| `addons/metaplay_kit/runtime/ui/` | UI factory and loading overlay. |
| `addons/metaplay_kit/runtime/platform/` | Optional platform purchase adapter with a desktop mock. |
| `addons/metaplay_kit/assets/` | Reusable theme and UI art. |
| `demo/scenes/` and `demo/scripts/` | Demo app and sample level. This is example integration code, not required runtime kit content. |
| `demo/assets/` and `demo/tools/` | Demo-only art and the legacy asset extraction utility. |
| `tests/` and `scenarios/` | Domain/loading tests and repeatable UI-flow scenarios. |
| `interfaces/` | Archived Godot 3 source material; not part of the runtime. |

The repository root remains the development and demo Godot project. A consuming game only needs the `addons/metaplay_kit/` directory and its own project configuration and game content.

## Install the kit in another game

1. Copy `addons/metaplay_kit/` into the consuming game's `addons/` directory.
2. Open the project in Godot and let it import the addon.
3. In **Project → Project Settings → Plugins**, enable **MetaPlayKit**. The plugin registers the `TtpGuiApi` autoload. If the project already has an autoload with that name, resolve the name/path conflict before enabling the plugin.
4. Optionally apply the kit theme by setting `gui/theme/custom` to `res://addons/metaplay_kit/assets/theme/metaplay.tres`. The demo enables this theme in its own `project.godot`; the plugin does not replace a game's theme automatically.

The demo configures the autoload and theme directly in its `project.godot` and enables the editor plugin. The plugin detects the existing matching autoload and avoids registering a duplicate. This also provides a reference for projects that manage the autoload themselves.

## Host-game integration

### Configure the session

`TtpGuiApi` is the public autoload implemented in `addons/metaplay_kit/runtime/api/ttp_gui_api.gd`. Register levels and initial session state before requesting a load:

```gdscript
TtpGuiApi.set_levels({
	"level1": {
		"name": "Forest",
		"max_score": 0,
		"max_stars": 0,
		"scene_path": "res://demo/scenes/level_stub.tscn",
		"enabled": true,
	},
	"level2": {
		"name": "Cave",
		"max_score": 0,
		"max_stars": 0,
		"scene_path": "res://demo/scenes/level_stub.tscn",
		"enabled": false,
	},
})
TtpGuiApi.set_player_coins(250)
TtpGuiApi.set_game_configuration({"sfx": true, "music": true})
```

Each level entry uses `name`, `max_score`, `max_stars`, `scene_path`, and `enabled`. Replace the sample scene paths with scenes from the consuming game. `load_first_level_to_play()` chooses the next playable level, starts loading it, and returns its registered definition. Use `get_level(key)` and `get_next_level_to_play()` to query progression.

### Load and start the host's level

Connect to the loading signals before requesting the first level. `loading_started(level_data)` sends a deep copy of the level definition with its key added under `key`. `loading_completed()` fires after loading finishes. The host must retrieve and instantiate the `PackedScene`, attach the resulting node, and start its gameplay lifecycle. `get_resource_loaded(path)` consumes the ready resource for that path; an immediate second read returns `null`.

This example shows the integration points. The consuming game supplies the level container and can replace the loading and error presentation to fit its own UI:

```gdscript
extends Node

@export var level_container_path: NodePath

var _level_container: Node = null
var _pending_scene_path: String = ""
var _pending_level_key: Variant = null
var _current_level: Node = null


func _ready() -> void:
	_level_container = get_node(level_container_path)
	TtpGuiApi.loading_started.connect(_on_loading_started)
	TtpGuiApi.loading_completed.connect(_on_loading_completed)
	TtpGuiApi.operation_rejected.connect(_on_operation_rejected)
	TtpGuiApi.set_levels({
		"level1": {
			"name": "Forest",
			"max_score": 0,
			"max_stars": 0,
			"scene_path": "res://demo/scenes/level_stub.tscn",
			"enabled": true,
		},
	})
	TtpGuiApi.load_first_level_to_play()


func _on_loading_started(level_data: Dictionary) -> void:
	_pending_scene_path = str(level_data.get("scene_path", ""))
	_pending_level_key = level_data.get("key")
	# Show the host game's loading UI here.


func _on_loading_completed() -> void:
	var packed_scene: PackedScene = TtpGuiApi.get_resource_loaded(
		_pending_scene_path
	) as PackedScene
	if packed_scene == null or not is_instance_valid(_level_container):
		TtpGuiApi.show_home()
		return

	var new_level: Node = packed_scene.instantiate()
	if is_instance_valid(_current_level):
		if _current_level.has_method("stop_level"):
			_current_level.call("stop_level")
		_current_level.queue_free()
	_level_container.add_child(new_level)
	_current_level = new_level
	if new_level.has_method("configure"):
		new_level.call("configure", _pending_level_key, self)
	if new_level.has_method("start_level"):
		new_level.call("start_level")
	# Hide the loading UI and present the game here.


func _on_operation_rejected(message: String) -> void:
	push_warning(message)
```

`configure(key, host)`, `start_level()`, `stop_level()`, and `revive()` are optional conventions implemented by the demo level in `demo/scripts/level.gd`; the kit does not require those methods on a host scene. On a resource-load failure, the facade emits `operation_rejected` and requests the `home` screen with `screen_requested`.

### Report a game result

Stop the host level and report wins through the facade:

```gdscript
TtpGuiApi.level_win(
	level_key,
	TtpGuiApi.get_level(level_key),
	3,                 # stars, clamped to 0..3
	1250,              # score
	120,               # coins earned
	"level2"           # registered level to unlock, if it exists
)
```

The model records the best score and star count, credits the reward, and enables the registered key passed as `next_level_to_play`. The facade then emits `screen_requested("win", payload)`. The second argument (`level_data`) remains for compatibility; the current model looks up the registered level using `level_key`.

For a loss, call `TtpGuiApi.level_lose(level_key)`. It requests the `lose` screen; the host remains responsible for stopping or pausing its gameplay node. Other available actions include `load_level(key)`, `change_level(key)` (enabled levels only), `modal_win_retry_level(key)`, `modal_lose_retry_level(key)`, and `modal_win_next_level(current_key)`. The last method chooses the next level from the model's progression state.

Navigation requests include `show_home()`, `show_level_selector_pressed(true)`, `show_panel_store(true)`, `show_panel_config(true)`, and `tap_to_play_pressed()`. The `screen_requested(screen_name, payload)` signal uses `home`, `game`, `levels`, `store`, `config`, `win`, and `lose` as screen names.

### Signals

| Signal | Meaning |
| --- | --- |
| `loading_started(level_data)` | A level load begins; data includes `key` and `scene_path`. |
| `loading_completed()` | The resource has loaded and can be retrieved by the host. |
| `loading_exit_animation_completed()` | The loading overlay can finish its exit transition. |
| `screen_requested(screen_name, payload)` | The facade requests a screen. |
| `operation_rejected(message)` | An operation was rejected or a load failed. |
| `new_total_coins(total)` | The wallet balance changed. |
| `home_tap_to_play_pressed()` | Play was requested from the home screen. |
| `level_selector_load_new_level_selected(level_data)` | A level was selected from the level selector. |
| `modal_win_retry_button_pressed(level_data)` / `modal_lose_retry_button_pressed(level_data)` | Retry was requested from a result screen. |
| `modal_win_load_next_level_pressed(level_data)` | Next-level loading was requested from a win screen. |
| `modal_lose_use_life_pressed()` | A life-use action was requested; the host handles its effect. |
| `modal_lose_video_reward_showed(level_data)` / `modal_win_video_reward_showed(information)` | A simulated video reward was reported. |
| `modal_config_change_sfx_status()` / `modal_config_change_music_status()` | The matching audio setting changed. |
| `store_game_buy_item(item_key)` / `store_game_update_item_loadded(item_key)` | A store item was purchased or equipped successfully. |
| `store_currency_buy_coins(product_key)` | A configured currency product was credited. |

Legacy names, including `store_game_update_item_loadded`, are retained for compatibility. In `modal_win_video_reward_showed(information)`, the array contains the next level and updated coin balance. `send_notification_ui(signal_name, parameter)` emits a facade signal by name; callers must pass the argument count and types declared by that signal. `select_pause()` currently requests `home`; `manage_tap_background()` is a placeholder.

### Stores, settings, and rewards

- `set_store_game(catalog)` configures game items. Entries use `type` (0 basic, 1 equippable, 2 phased), `title`, `description`, `price`, and `bought`. Equippable entries also use `load` and `group`. Phased items are nested under `stages` and addressed with paths such as `["power_boost", "phase1"]`.
- `update_item_sold_in_store_game(path)` attempts a purchase after validating its price and the wallet. `update_item_game_loaded(path)` equips an owned item. Use `get_item_in_store_game_dictionary(path)` to query its definition and `get_type_buttons()` to get the item-type values.
- `set_store_currency(products)` configures offers; `set_list_value_items_store_game(amounts)` maps each product key to the amount of coins it grants. `add_coin_purchased(key)` credits that configured amount. `get_total_players_coins()` returns the current balance.
- `set_game_configuration(config)` sets initial values. `notify_change_sfx_status()` and `notify_change_music_status()` toggle them and emit signals; connect those signals to the host game's audio system.
- `notify_modal_lose_video_reward(key)` and `notify_modal_win_video_reward(key, extra_coins)` report simulated video rewards. `notify_modal_lose_use_life()` only emits a signal; the host decides how to spend a life.

## Current limitations

The model and API do not persist data or connect a backend. Progress, wallet balance, settings, purchases, and equipped items live in memory for the session. `add_coin_purchased()` credits the configured amount for a product key; it does not validate a store receipt. The demo's desktop IAP adapter is a simulation. A shipped game must integrate and validate purchases with its platform provider and decide how to persist player progress.

## Legacy reference material

Visual assets used by the demo were extracted from `interfaces/testAddons` with `demo/tools/extract_legacy_assets.py`. The archived folder remains available as reference material; `interfaces/.gdignore` prevents Godot from importing the old Godot 3 project.

## Verification

The tests in `tests/` cover model invariants and repeated/invalid level loading. JSON files in `scenarios/` exercise the app with inputs and check layout, navigation, purchases, wins, losses, rewards, settings, and pause flows.
