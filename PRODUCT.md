# MetaPlayKit product direction

## Product intent

MetaPlayKit is a reusable Godot addon intended to provide a dependable meta-game layer for multiple host games. It should let a host integrate level progression, a wallet, a configurable store, rewards, settings, and optional engagement systems through a stable public contract, while keeping gameplay and presentation under host control.

The repository currently contains an early product baseline and a sample consumer. The sample demonstrates integration; it does not define the product boundary or imply that every production capability is already implemented.

## Product boundary

### MetaPlayKit owns

- Validated meta-game state and rules for progression, currency, catalog ownership, and configured reward claims.
- A stable host-facing API with documented commands, queries, and events.
- Reusable integration components and adapters where they are useful across games.
- Explicit contracts for asynchronous operations and optional platform integrations.

### The host game owns

- Gameplay, level scenes, input, and the lifecycle of gameplay nodes.
- Screen composition, navigation, branding, localization, and accessibility decisions.
- Player identity, persistence provider, backend connectivity, and authoritative online validation.
- Platform store configuration and the decision to enable real purchases.

The kit may offer optional presentation components and declarative UI profiles, but it must not require a host to adopt a fixed screen tree or navigation flow.

## Product principles

1. **Host-first integration:** configuration and state access go through documented public APIs; consumers do not reach into kit internals.
2. **Reusable by default:** functionality belongs in the addon only when it serves more than the sample game or is an explicit product capability.
3. **Safe state changes:** repeated callbacks, concurrent operations, invalid data, and restoration must have defined outcomes.
4. **Explicit trust boundaries:** local validation improves correctness but does not replace server authority or store receipt verification.
5. **Stable contracts:** public API changes require compatibility decisions, migration guidance, and versioning.
6. **Presentation flexibility:** host games can use their own screens, themes, assets, text, and layout.
7. **Honest capability claims:** documentation distinguishes shipped behavior from proposed or host-supplied behavior.

## Current baseline and target gap

The current code has in-memory progression, wallet, settings, and store state; asynchronous level-resource loading; an API facade; reusable UI components; and a desktop purchase simulation. It does not yet provide persistent saves, a backend, authoritative purchase verification, or all the concurrency and idempotency guarantees needed for production economies. The sample also demonstrates one particular screen flow and must not be treated as mandatory host behavior.

Production suitability depends on the host game's threat model. For an offline single-player game, local state and host persistence may be sufficient. For online, competitive, or monetized economies, the host must connect authoritative services and verified platform purchases; the addon alone cannot provide those guarantees.

## Production readiness gates

Before describing a release as production-ready, define and meet these gates for the supported product scope:

- **Distribution:** install, enable, disable, upgrade, and remove the addon in a clean consuming project without relying on demo files.
- **Contracts:** document API stability, supported Godot versions, migration policy, error codes, and compatibility lifetime.
- **Lifecycle:** define cancellation/arbitration for overlapping loads and ensure every operation reaches a terminal result. Tracked by [GitHub issue #1](https://github.com/LaChaucha/meta-play-kit/issues/1) and [issue #6](https://github.com/LaChaucha/meta-play-kit/issues/6).
- **Economy correctness:** prevent duplicate completion and bonus claims and define replay rewards. Tracked by [issue #2](https://github.com/LaChaucha/meta-play-kit/issues/2).
- **State ownership:** provide a versioned, validated save/restore contract without imposing a storage provider. Tracked by [issue #3](https://github.com/LaChaucha/meta-play-kit/issues/3).
- **Host integration:** support host-owned navigation, explicit progression policies, and optional UI configuration. Tracked by [issue #4](https://github.com/LaChaucha/meta-play-kit/issues/4), [issue #5](https://github.com/LaChaucha/meta-play-kit/issues/5), and [issue #11](https://github.com/LaChaucha/meta-play-kit/issues/11).
- **Platform commerce:** do not grant real-money entitlements until provider verification and transaction idempotency are defined. Tracked by [issue #7](https://github.com/LaChaucha/meta-play-kit/issues/7).
- **Optional engagement:** lives, daily rewards, and quests remain opt-in and must use the same persistence and idempotent reward contracts. Tracked by [issues #8](https://github.com/LaChaucha/meta-play-kit/issues/8), [#9](https://github.com/LaChaucha/meta-play-kit/issues/9), and [#10](https://github.com/LaChaucha/meta-play-kit/issues/10).
- **Evidence:** maintain automated tests for domain rules and API contracts, plus clean-project integration checks for the supported installation path.

These gates are a release checklist to refine, not a promise that every optional feature must ship in the first product release.

## Roadmap approach

Treat the GitHub issues as the active product backlog. Resolve foundational contracts first: load lifecycle, reward idempotency, state persistence, and operation results. Then finalize host navigation and progression policies. Platform purchase verification, optional engagement systems, and configurable UI can build on those contracts. Each epic should be split into independently reviewable features before implementation.

Keep the sample consumer useful as an integration example and regression surface. It may exercise product capabilities, but sample-only screens, labels, and flows should stay outside the reusable runtime unless a separate product requirement justifies them.
