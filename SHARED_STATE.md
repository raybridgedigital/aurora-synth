# SHARED_STATE.md — AI agent coordination file

**Audience: AI coding agents (and the human owner).** This is the shared memory for a vibe-coding workflow: any AI session, editor agent, or teammate picks up context here instead of re-discovering it. Read it at the start of every major action; update it after every significant decision or code change. Human readers can ignore it.

## Project

Aurora — native macOS synthesizer (standalone + AU + VST3) for Apple silicon, macOS 14 or newer. Swift/SwiftUI UI, C++ engine, Objective-C++ Core Audio/Core MIDI glue, zero third-party dependencies.

- Repo: `raybridgedigital/aurora-synth`, branch `main`
- Build: `./scripts/build.sh` → `build/Aurora.app` · Tests: `./scripts/run-tests.sh` and specialized suites under `scripts/`
- Docs: `README.md` (system requirements + release notes), `CHANGELOG.md`, `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md` (parked + frozen), `FUTURE-PROPOSAL-MODULATION-EXPANSION.md` (shipped v0.23 — design history), `Dual-Patch-Specification.md` (locked design, not implemented)

## Roles (label every statement)

**Researcher · Architect · Implementer · Critic · Security Auditor** — keep roles consistent across sessions and prefer small, concrete next steps over giant jumps.

## Current state (22 Sep 2026)

- **HEAD:** `main`, pushed — latest: `Docs: park Safari-class scroll-smoothness proposal (UI-only P1-P4, frozen)` (`58abe96`, proposal + README index); this file's own commit follows it (a file can't contain its own hash — run `git log -1` to see it). Prior `5ceb6a7` archived `InterfaceChecks.swift` + added the README system-requirements line (3 of 4 CI ✅; its Specialized Regression run was superseded/cancelled by the following push, not failed); `28af936` was 4/4 green. Confirm CI anytime: `gh run list --repo raybridgedigital/aurora-synth`.
- **`archive/InterfaceChecks.swift` is archived** — kept for regression archaeology only, **not CI/release authority**. Path references updated in `check-interface.sh`, `.github/workflows/smoke-build.yml`, `AURORA-LEGACY-TEST-CLASSIFICATION-v1.md`, `AURORA-V1-TEST-RECONSTRUCTION-ASSESSMENT.md`.
- README now has an explicit **system-requirements line** (top of file): Apple silicon + macOS 14 or newer, no Intel/Windows/Linux versions planned.
- Working tree: clean except untracked `.grok/` (owner-managed — never stage or commit it). This file is committed at the owner's explicit request (22 Sep 2026).
- **Remaining roadmap = exactly 3** (owner-confirmed 22 Sep 2026): patch redesign → then harness re-tighten; scroll P1–P4 (frozen; spec = `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md`); dual-patch live (parked, design locked). Modulation expansion is NOT outstanding — shipped in v0.23.

## Freeze / approval rules (never violate)

1. **Engine, app, plugin, and test code is FROZEN.** Allowed without unfreeze: docs, README, harness scripts, workflow comments, `archive/`. The owner must unfreeze by naming a specific change.
2. **Never commit, push, or tag without an explicit per-instance owner request.** Earlier approvals do not carry over.
3. While frozen, deliver **reports only** — no code edits.
4. Validate before claiming done: build/test, re-read edited files, confirm `git status` matches the intended scope.

## Rendering-bug audit (delivered 22 Sep 2026, read-only)

- **No open rendering bugs** in the UI layer (`Sources/AuroraApp.swift`, `CreativeTools.swift`, `MotionViews.swift`, `PluginEditor.swift`, `WavetableViews.swift`): canvases bounded and gated, `isFinite` guards at data entry, stable row identities, no unsafe unwraps in draw paths; all historical scroll/frame/meter/invalidation fixes already landed.
- Scroll smoothness vs Safari = main-thread invalidation work, not visuals and not the scroller (macOS `ScrollView` is already `NSScrollView`-backed). Proposed **UI-only** fixes, held until unfreeze (line numbers as of `5ceb6a7`):
  - **P1** — move `patchBrowserRow` off `SynthModel` (`AuroraApp.swift:479`, writes at `:2302–2305`) into local `PatchBrowserState` (`:2118`). Purely under the hood: no look change; kills whole-app invalidation on every patch-row scroll crossing. ~15–25 lines.
  - **P2** — memoize `PatchBrowser.sounds` (`:2199–2209`): removes the 438-preset `localizedStandardCompare` re-sort on every body evaluation; identical results. ~10–15 lines.
  - **P3** — extend the existing `.eventTracking` guard (`:1033`) to the telemetry `.update()` calls in `poll()`. One subtle visible tradeoff: meters/scope pause during an active scroll/drag and resume on release. ~5–10 lines.
  - **P4** — replace per-row `GeometryReader` preference (`:2189`, `:~2296`) with a single sentinel + row arithmetic; removes per-frame preference churn. Under the hood. ~10–20 lines.
  - Validation when implemented: Instruments (Time Profiler + Core Animation FPS) while flinging the patch list, plus UI smokes. ≈ half a day total.

## Pending queue

1. **Owner's patch redesign (= patch/bank redo, owner side)** → after it lands, re-tighten the harness: re-assert spectrum count, exhaustive preset-restore coverage.
2. **P1–P4 scroll-smoothness work** — proposal published at `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md` (commit `58abe96`, indexed in README's parked proposals). Implementation starts only when the owner unfreezes the UI for this named change.
3. **Dual-patch live** — design locked in `Dual-Patch-Specification.md`, not implemented; engine-touching, parked until the owner explicitly scopes and unfreezes it.
4. **This file's git fate** — ✅ resolved: committed and pushed at the owner's explicit request (22 Sep 2026); now visible on GitHub and in clones. PII scan clean (no real name, email, or local paths — only the already-public repo handle).

## Handoff protocol

1. Read this file first. 2. Label your role. 3. Take the smallest concrete next step. 4. Update this file after every significant decision or code change. 5. Re-check the freeze/approval rules before any edit or git action.
