# Complete app audit and enhancement pass

## Features
- [x] Review every major user flow: unlock, browsing, address entry, vault, import, results, single run, 2×2 mode, profile cycling, settings, history, and bookmarks.
- [x] Fix crashes, freezes, stuck states, broken buttons, and flows that can leave the app half-running.
- [x] Improve the run queue so stop, restart, burn, retry, and completion behavior stays predictable.
- [x] Strengthen 2×2 mode so all four windows stay synchronized where expected while remaining separate from each other.
- [x] Tighten profile cycling so active work is stopped safely before old browsing state is cleared.
- [x] Reduce memory pressure from browser windows, screenshots, stored results, and background tasks.
- [x] Improve error messages and recovery so failures are visible without interrupting the workflow.

## Design
- [x] Keep the current dark, compact browser style and avoid a major visual redesign.
- [x] Polish confusing controls, labels, and menus where the current action is unclear.
- [x] Make live status surfaces easier to hide, restore, and understand during long runs.
- [x] Preserve fast access to the most important controls: address bar, run, burn, vault/results, settings, and 2×2 mode.

## Screens / Areas
- [x] **Browser screen**: audit navigation, address editing, toolbar actions, run status, burn history, and keyboard behavior.
- [x] **2×2 screen**: audit shared URL entry, per-window isolation, status pills, stop/start behavior, and transitions from single mode.
- [x] **Vault and results**: audit clearing, importing, disabled handling, queue order, screenshots, filters, and result reset behavior.
- [x] **Settings**: audit notification toggles, run timing, profile cycling, locale/timezone controls, and safety confirmations.
- [x] **Startup and lock**: audit app launch, seeding, unlock, and install/runtime stability.

## Validation
- [x] Run the app’s full build validation after changes.
- [x] Attempt the existing test suite where supported; unavailable in this sandbox because xcodebuild is not installed.
- [x] Provide a focused manual debug checklist for the simulator covering browsing, 2×2 mode, run loop, burn, import, profile cycle, and results.

## Improvement Policy
- [x] I will apply ambitious cleanup where it improves reliability, but preserve the app’s current product behavior unless a behavior is clearly broken.
- [x] I will keep changes grounded in the existing app rather than replacing the product direction.
- [x] I will summarize any larger risks or follow-up opportunities after validation.
