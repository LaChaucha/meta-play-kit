# AGENTS.md — MetaPlayKit addon

## Purpose and scope

This repository contains the reusable Godot addon, product/API documentation, addon unit tests, and development tools. Its checkout directory is `addons/metaplay_kit/` inside a consuming project. `plugin.cfg` must remain directly in that directory. The sample consumer and its integration tests live in a separate repository.

The addon targets Godot 4.7, typed GDScript, and the GL Compatibility renderer. Product intent and responsibility boundaries are in `PRODUCT.md` and the GitHub backlog.

## Development rules

- Keep responsibilities separate: `MetaPlayModel` owns kit rules and state; `TtpGuiApi` exposes the public contract and coordinates; reusable components own bounded UI behavior.
- Preserve explicit types in GDScript arguments, variables, and return values. Avoid inferring types from `Variant`, dictionaries, nodes, or null values.
- Runtime code and assets must resolve from `res://addons/metaplay_kit/` in a host project. Preserve this path when editing resource references.
- Preserve `.uid` and `.import` sidecars with their resources. Use Godot-aware tools when moving resources.
- Keep the desktop purchase path simulated. Google Play signature checks are local validation, not a substitute for server verification. Open external links only after explicit user action.
- The host owns gameplay, navigation, campaign availability, lives, daily engagement, player identity, and persistence IO. The kit owns only its documented meta-game state and configured level-completion rewards.
- Do not make commits or push without explicit user authorization. For an authorized commit, use:

```sh
GIT_AUTHOR_NAME="Eduardo David Angeleri" GIT_AUTHOR_EMAIL="angeleridavid@gmail.com" GIT_COMMITTER_NAME="Eduardo David Angeleri" GIT_COMMITTER_EMAIL="angeleridavid@gmail.com" git commit -m "<descriptive commit message>"
```

## Repository contents

| Path | Responsibility |
| --- | --- |
| `plugin.cfg`, `plugin.gd` | Editor plugin and `TtpGuiApi` autoload registration. |
| `runtime/api/` | Public facade and typed operation results. |
| `runtime/model/` | Progression, wallet, settings, store, and completion reward rules. |
| `runtime/systems/` | Asynchronous resource loading. |
| `runtime/components/`, `runtime/ui/` | Reusable controls and UI helpers. |
| `runtime/platform/` | Optional purchase provider adapters. |
| `assets/` | Kit theme and UI assets. |
| `tests/` | Unit tests for kit behavior and contracts. |
| `tools/package_addon.py` | Consumer ZIP builder; excludes tests and development files. |
| `PRODUCT.md`, `README.md` | Product boundary and integration/API documentation. |

## Tests and packaging

Run addon unit tests from a Godot consumer project with this checkout at `addons/metaplay_kit/`, using the Godot test runner with `--tests-dir addons/metaplay_kit/tests`. Tests that require sample scenes, sample scripts, or demo assets belong in the separate consumer repository.

Run `python tools/package_addon.py` to create a ZIP with a top-level `metaplay_kit/` folder containing only plugin metadata, runtime code, resources, and the README. Never include tests, `.git`, or development task files in the consumer package.

## User story documentation

When asked to decompose an epic into user stories, inspect the GitHub issue and product contract, group the stories by component, and write complete, testable acceptance criteria in BDD or an unambiguous checklist. Save approved analysis under `tasks/` using `US-XXX-short-descriptive-name.md`, with an index README. Do not commit or push without explicit authorization.
