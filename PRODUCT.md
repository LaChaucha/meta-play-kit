# MetaPlayKit product direction

## Product intent

MetaPlayKit is a reusable Godot addon intended to provide a dependable meta-game layer for multiple host games. It should let a host integrate level progression, a wallet, a configurable store, configured level-completion rewards, settings, and reusable UI through a stable public contract, while keeping gameplay and presentation under host control.

The repository currently contains an early product baseline and a sample consumer. The sample demonstrates integration; it does not define the product boundary or imply that every production capability is already implemented.

## Product boundary

### MetaPlayKit owns

- Validated meta-game state and rules for progression, currency, catalog ownership, and explicitly configured level-completion rewards.
- A stable host-facing API with documented commands, queries, and events.
- Reusable integration components and adapters where they are useful across games.
- Explicit contracts for asynchronous operations and optional platform integrations.

### The host game owns

- Gameplay, level scenes, input, and the lifecycle of gameplay nodes.
- Player life balances and their gameplay/economy rules, including when lives are spent, granted, refilled, or eligible for use.
- Player login/session history, calendar and time-zone interpretation, consecutive-day streaks, and time-based reward schedules or eligibility.
- Screen composition, navigation, branding, localization, and accessibility decisions.
- Player identity, persistence provider, backend connectivity, and authoritative online validation.
- Platform store configuration and the decision to enable real purchases.

The kit may offer optional presentation components and declarative UI profiles, but it must not require a host to adopt a fixed screen tree or navigation flow.

For host-owned systems such as lives, the kit may provide reusable UI action intents and generic gameplay-attempt lifecycle operations. It does not own the host's balance, eligibility policy, ad or purchase flow, or persistence for those systems.

Daily login tracking, consecutive-day streaks, and daily reward programs are outside the current product scope. The host identifies players and sessions, interprets dates and time zones, decides whether a reward is available, defines its effect, and persists that state. MetaPlayKit does not record daily connections, calculate streaks, decide reward eligibility, or expose snapshot fields or APIs for those policies. Its reward support is limited to configured level-completion rewards and their claims.

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
- **Ownership boundaries:** lives and calendar-based engagement are host-owned. MetaPlayKit may report generic action intents and resume a host-authorized gameplay attempt, but it does not manage lives, daily connections, streaks, or time-based reward eligibility. Daily rewards and streaks in [issue #9](https://github.com/LaChaucha/meta-play-kit/issues/9) are out of current scope; quests in [issue #10](https://github.com/LaChaucha/meta-play-kit/issues/10) require a separate product decision.
- **Evidence:** maintain automated tests for domain rules and API contracts, plus clean-project integration checks for the supported installation path.

These gates are a release checklist to refine, not a promise that every optional feature must ship in the first product release.

## Roadmap approach

Treat the GitHub issues as the active product backlog. Resolve foundational contracts first: load lifecycle, reward idempotency, state persistence, and operation results. Then finalize host navigation and progression policies. Platform purchase verification and configurable UI can build on those contracts. Any future calendar-based engagement capability requires an explicit product-scope decision before entering the backlog. Each epic should be split into independently reviewable features before implementation.

Keep the sample consumer useful as an integration example and regression surface. It may exercise product capabilities, but sample-only screens, labels, and flows should stay outside the reusable runtime unless a separate product requirement justifies them.
