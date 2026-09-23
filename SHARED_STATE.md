# SHARED_STATE.md — AI agent coordination file

**Audience: AI coding agents (and the human owner).** This is the shared memory for a vibe-coding workflow: any AI session, editor agent, or teammate picks up context here instead of re-discovering it. Read it at the start of every major action; update it after every significant decision or code change. Human readers can ignore it.

## Project

Aurora — native macOS synthesizer (standalone + AU + VST3) for Apple silicon, macOS 14 or newer. Swift/SwiftUI UI, C++ engine, Objective-C++ Core Audio/Core MIDI glue, zero third-party dependencies.

- Repo: `raybridgedigital/aurora-synth`, branch `main`
- Build: `./scripts/build.sh` → `build/Aurora.app` · Tests: `./scripts/run-tests.sh` and specialized suites under `scripts/`
- Docs: `README.md` (system requirements + release notes), `CHANGELOG.md`, `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md` (parked + frozen), `FUTURE-PROPOSAL-MODULATION-EXPANSION.md` (shipped v0.23 — design history), `Dual-Patch-Specification.md` (locked design, not implemented), `FUTURE-PROPOSAL-FM-ENGINE.md` (**v0.2 draft, local + uncommitted — QUEUE #1**, owner-decided 23 Sep 2026)

## Roles (label every statement)

**Researcher · Architect · Implementer · Critic · Security Auditor** — keep roles consistent across sessions and prefer small, concrete next steps over giant jumps.

## Current state (22–23 Sep 2026)

- **HEAD:** `main`, pushed — newest `a2c1e79` (hardware validation = queue item 4), then `f60d464` (modulation-shipped correction + roadmap), `35e3f7e` (this file added), `58abe96` (scroll proposal + README index); all 22 Sep 2026, docs-only. A file can't contain its own hash — run `git log -1` for the live value. Prior `5ceb6a7` archived `InterfaceChecks.swift` + added the README system-requirements line; `28af936` 4/4 green. **CI:** each new push auto-cancels the previous push's still-running Specialized Regression job — those cancellations are not failures; confirm live status anytime with `gh run list --repo raybridgedigital/aurora-synth`.
- **`archive/InterfaceChecks.swift` is archived** — kept for regression archaeology only, **not CI/release authority**. Path references updated in `check-interface.sh`, `.github/workflows/smoke-build.yml`, `AURORA-LEGACY-TEST-CLASSIFICATION-v1.md`, `AURORA-V1-TEST-RECONSTRUCTION-ASSESSMENT.md`.
- README now has an explicit **system-requirements line** (top of file): Apple silicon + macOS 14 or newer, no Intel/Windows/Linux versions planned.
- Working tree: clean except untracked `.grok/` (owner-managed — never stage or commit it). This file is committed at the owner's explicit request (22 Sep 2026).
- **Remaining roadmap (owner-reordered 23 Sep 2026): 1 — the FM engine build** — spec drafted in `FUTURE-PROPOSAL-FM-ENGINE.md` (**v1.0 LOCKED, pushed 23 Sep**): per-layer `Subtractive | FM`, 16 visual algorithms, velocity→index, 15 flagship + EP-ish A/B pairs (FM re-author + ` (OLD)` original), all `category: "FM"` — **lock review done 23 Sep: 3 findings folded (phantom patch names → verified pool; loader guard `:233` rides Phase 4; filename citations fixed).** **Owner directives recorded there:** testing/CI compliance out of scope (red accepted; re-baseline later) · hardware validation deferred by owner (not a blocker) · full patch wipe deferred — current library stays (*"bad patches > nothing; no empty synth"*) · live gigging = the optimization target, DAW parity low-priority. **23 Sep later message: zero backward compat re-affirmed** — pristine new code/features > compat, old patches = crap, delete any compat burden instead of engineering around it (spec decision row 17; old binaries misrendering FM patches accepted) · **23 Sep final message: EP-ish re-authors + OLD pairs = optional side quest, AI's call (row 18); core = engine + 15 flagship.** Then parked: scroll P1–P4 (frozen; spec = `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md`) and dual-patch (design locked). Modulation expansion is NOT outstanding — shipped in v0.23.

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

1. **FM engine build — QUEUE #1 (owner, 23 Sep 2026: "super important, life blood")** — spec drafted in `FUTURE-PROPOSAL-FM-ENGINE.md` (**LOCKED v1.0 — committed + pushed 23 Sep at owner order**; full decision log rows 1–18 inside). Shape: per-layer engine mode `Subtractive | FM` (ops replace Osc1/Osc2; sub + noise kept), 16 visual algorithms, rate/level operator envelopes, single per-layer feedback, dedicated pitch env, velocity promoted into `soundSources`, matrix 37→~49 destinations, ~24-note polyphony target, optimization target = live gigging (app); DAW parity low-priority/fix-if-cheap. Each build phase needs a named unfreeze (Phase 1 = C++ `FmEngine.hpp/.cpp` beside `SynthEngine.cpp`).
2. **FM patch library (spec Phase 4)** — **core = 15 flagship, all `category: "FM"`, appended into `Resources/Aurora100.json` (100 → 115)**. **Side quest (owner, 23 Sep: AI's call — *"trivial… I don't give a shit about the old ones"*, never an owner ask):** EP-ish re-authors from the verified 16-name pool (default B=11; earlier 11-name list had 6 phantom names → corrected at lock review) → only if run: appended too (→ ≈126) with **A/B pairs**: originals re-cat'd + renamed ` (OLD)` **in place** in their home files (counts unchanged), re-authors keep clean names. **Mandatory one-liner rides Phase 4:** `AuroraApp.swift:233` `count == 100` → `>= 100` — without it, appends make the guard reject the whole factory bank at runtime (`:859` notice; 100 patches vanish); plugin has no such guard (`PluginCore.mm:64` non-empty check only). `PatchBankAudit.mm:246` + `PluginCoreChecks.mm:22` count asserts go red = owner-accepted. Full library wipe = **deferred, owner-triggered**, atomic with its re-baseline at that time. Former "patch redesign → harness re-tighten" intent folds here (owner 23 Sep: testing compliance not important now).
3. **P1–P4 scroll-smoothness work** — proposal published at `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md` (commit `58abe96`, indexed in README's parked proposals). Implementation starts only when the owner unfreezes the UI for this named change.
4. **Dual-patch live** — design locked in `Dual-Patch-Specification.md`, not implemented; engine-touching, parked until the owner explicitly scopes and unfreezes it.
5. **Hardware validation pass — owner-deferred (23 Sep 2026: "not important for now, i believe it will be stable")** — out of the active queue; revive only at the owner's explicit word (original three-controller/pedal/USB/clock/30-min checklist preserved in this file's git history).
6. **This file's git fate** — ✅ resolved 22 Sep 2026 (committed/pushed at owner request; PII scan clean). Working tree now also holds `FUTURE-PROPOSAL-FM-ENGINE.md` + this update — **both committed & pushed 23 Sep 2026 at owner order (*"commit and push the spec"*)**; future doc commits likewise wait for an explicit owner word.

## Handoff protocol

1. Read this file first. 2. Label your role. 3. Take the smallest concrete next step. 4. Update this file after every significant decision or code change. 5. Re-check the freeze/approval rules before any edit or git action.
