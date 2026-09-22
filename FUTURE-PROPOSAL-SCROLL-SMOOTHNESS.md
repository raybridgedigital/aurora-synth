# Future proposal — Safari-class scroll smoothness (UI-only, P1–P4)

**Status: PROPOSED — parked. The code is frozen; nothing in this document is implemented. This file is the proposal only.** Implementation requires an explicit, per-instance unfreeze from the owner that names this change.

**Scope: UI layer only** (`Sources/AuroraApp.swift`). No engine, DSP, plugin, audio-thread, timer-interval, or test-code changes. No new dependencies.

**Basis:** read-only rendering-bug audit of 22 Sep 2026 against `main` at `5ceb6a7`. Audit verdict: **no open rendering bugs** — the items below are performance-only, and every historical scroll/frame/meter/invalidation fix has already landed.

## Goal

Match Safari browsing feel: continuous, hitch-free scrolling in the patch browser and the main editor while audio is running. Honest target: eliminate perceptible dropped frames caused by main-thread invalidation during scroll. Bit-identical WebKit tile compositing is not promised — but "feels like Safari" is realistic on Apple silicon.

## Why it can hitch today

macOS SwiftUI `ScrollView` is already `NSScrollView`-backed — the same native inertia Safari uses. The scroller is not the problem; **work injected on the main thread while scrolling is**:

| # | Cause | Location (as of `5ceb6a7`) |
|---|---|---|
| 1 | Every patch-row crossing (~116 pt) writes `m.patchBrowserRow` into the globally observed `SynthModel`, invalidating ~19 observer sites across the whole app mid-scroll | `AuroraApp.swift:479`, writes at `:2302–2305` |
| 2 | Per-row `GeometryReader` preference values change every frame while scrolling; the `onPreferenceChange` closure runs on main each frame | `:2189–2192`, `:≈2296` |
| 3 | `PatchBrowser.sounds` re-filters and `localizedStandardCompare`-sorts 438+ presets on **every** body evaluation — including each invalidation caused by #1 | `:2199–2209` |
| 4 | The 50 Hz `poll()` runs `syncPlugin` + five telemetry `.update()` calls even during `.eventTracking`; only disk work (`refresh`/`persist`) is deferred today | `:1027–1074`, guard at `:1033` |
| 5 | Radius-30 panel shadow re-rasters whenever the browser panel invalidates — amplified by #1 | `:≈2320` |

## Proposed changes

### P1 — take scroll-row tracking off `SynthModel` (highest leverage, invisible)

Move row tracking into the existing local `PatchBrowserState` (`:2118–2124`), which already owns browser-local UI state. Keep session scroll-restore (README 0.23 behavior) by writing the row through to persistence **debounced on scroll idle / browser close**, not per crossing.

- Effect: kills cause #1 (whole-app invalidation per row crossing) and, with it, cause #5's re-raster frequency.
- Visibility: **none** — identical layout, cards, scroll physics, and restore behavior.
- Size: ~15–25 lines, all in `AuroraApp.swift`. Risk: low — must preserve last-row session restore (covered in validation).

### P2 — memoize `PatchBrowser.sounds` (invisible)

Cache the filtered + sorted list, invalidated only when its six inputs change: `category`, `search`, `favoritesOnly`, `favorites`, `userPresets`, `FactoryBank`. Same sort, same results — computed once per change instead of once per body evaluation.

- Effect: kills cause #3 for scroll, search typing, CC-driven publishes, and every other invalidation.
- Visibility: **none** — identical ordering and filtering.
- Size: ~10–15 lines. Risk: low — stale-cache risk mitigated by keying on all six inputs.

### P3 — defer telemetry compute during `.eventTracking` (optional, one visible tradeoff)

Extend the existing disk-work guard (`:1033`) to the telemetry `.update()` calls in `poll()` so scope/modulation/wavetable/motion/meter compute pauses during an active scroll or drag and resumes on release.

- Effect: removes cause #4's main-thread contention during scroll.
- Visibility: **one deliberate, subtle change** — live meters/scope freeze mid-scroll and resume when you release (arguably more Safari-like, since browsers suspend non-essential work while scrolling). Drop this proposal if meters must keep ticking.
- Size: ~5–10 lines. Risk: trivial.

### P4 — single-sentinel row tracking (optional polish, invisible)

Replace the per-row `GeometryReader` preference fan-in with one sentinel row (or single reader on the `LazyVStack`) plus row-height arithmetic to derive the top row.

- Effect: removes cause #2's per-frame preference churn.
- Visibility: none — same row index semantics.
- Size: ~10–20 lines. Risk: low — must reproduce restore-row semantics exactly.

## Suggested implementation order

1. **P1 + P2 first** (both invisible, highest leverage) → measure.
2. Add **P4** only if measurement still shows preference-related per-frame work.
3. Add **P3** only if telemetry contention still shows, and only if the meter-pause tradeoff is accepted.

## Validation plan

- **Instruments:** Time Profiler + Core Animation FPS/Hitches while flinging the patch list end-to-end and scrolling the main editor with audio running. Gate: no `SynthModel` publishes and no multi-millisecond sorts attributable to the browser on scroll frames.
- **Behavior:** patch browser restores the last session row; search/category/favorites filtering and ordering unchanged; with P3, meters/scope resume immediately on scroll release.
- **Automated:** `./scripts/run-tests.sh` + specialized suites + UI smokes; CI 4/4 green.
- **Acceptance:** perceptible scroll hitches gone on the fling test; zero visual or behavioral regressions; docs-only line counts match the estimates above (no scope creep into engine code).

## Effort

≈ half a day total including Instruments verification and UI smokes. P1–P4 combined ≈ 45–70 lines, one file.

## Out of scope

Engine/DSP changes, audio-thread work, new dependencies, and any AppKit rewrite of the scroller — unnecessary, because the scroller is already native.
