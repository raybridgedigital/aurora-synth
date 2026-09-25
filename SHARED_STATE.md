# SHARED_STATE.md — AI agent coordination file

**Audience:** AI coding agents and the human owner. Read this file before any major action. Human readers may ignore it.

## Project

KiMiA (internal project lineage: Aurora) — native macOS synthesizer for Apple silicon, macOS 14 or newer. Standalone app plus AU and VST3 instruments; Swift/SwiftUI UI, C++ engine, and Objective-C++ Core Audio/Core MIDI integration; no third-party dependencies.

- Repository: `raybridgedigital/aurora-synth`, branch `main`
- Build: `./scripts/build.sh` → `build/Aurora.app`
- Tests: `./scripts/run-tests.sh` plus specialized suites under `scripts/`
- Release record: `CHANGELOG.md`
- Product/status overview: `README.md`
- Patch design rules (mandatory for factory-sound work): `PATCH-DESIGN-RULES.md`

## Roles

**Researcher · Architect · Implementer · Critic · Security Auditor** — keep roles consistent and prefer small, concrete steps.

## Freeze / approval rules

- **CODE FROZEN since 24 September 2026 after v0.25.0.** Do not edit `Sources/`, scripts, tests, resources, plug-in code, or build configuration until the owner gives an explicit named unfreeze.
- Documentation-only corrections require a documentation-only request. This file was refreshed on that basis after the v0.25.0 tag.
- `.grok/` is owner-managed and must remain untracked. Never stage or commit it.
- Do not infer approval to tag, push, install plug-ins, or alter local support data from an implementation or documentation request.

### Owner direction in effect (25 September 2026, Claude Code session)

After the 24 September gig (DSP at 100 %, crackling) the owner asked Claude Code, working in
`~/Desktop/KiMiA by Claude/aurora-synth` on branch `claude/dsp-bypass-and-performance`, to
assess and fix the FX-bypass/DSP problem, to improve the software (engine, effects, reliability)
wherever it helps the gigging instrument, and to archive the old factory banks. Standing limits:
no release, tag, push, plug-in installation or change to live support data without an explicit
owner request. Other local folders (`~/Desktop/Aurora Source`, older builds, patch backups) are
history/reference only; the uncommitted bypass edits in `~/Desktop/Aurora Source` (another
model's work in progress, which did not compile) are superseded by this branch — do not apply them.

**Owner patch policy:** regular patches use at most two layers, so a future Dual Patch runs four
layers in total. Three- and four-layer patches are for rare, exceptional designs only
(PATCH-DESIGN-RULES.md rule 3; CPU budget in rule 8).

## Branch `claude/dsp-bypass-and-performance` (25 September 2026, unpushed)

Five commits on top of `63c0cc4`, each with its tests green:

1. **Voices (bit-identical).** Per-sample math that cannot change the result is skipped or hoisted
   (exp2 of zero, sub sine at level 0, wheel vibrato at rest, tanh(Character gain) per lane,
   per-layer shaping of free-running LFOs, hoisted SVF divisions/LFO steps/motion clocks, FM
   operator order resolved at compile time, motion curve-0 segments skip pow). Verified sample by
   sample against the previous engine on all 55 AuroraFX patches, 19 Dual Patch pairs, the 60
   GB109 sounds and 96 FM variants. Behaviour changes: fully decayed sustain-0 **poly** voices held
   by key/pedal are freed (mono/legato unchanged); quiet release tails update filter coefficients
   every 16 samples (≤ 1.4e-6 difference).
2. **True FX bypass.** Root cause of "DSP still at 100 % after bypass": a powered-off Reverb re-armed
   its flush every sample and cleared 576 KB of rings 44,100×/s (27.7 % of the 44.1 kHz/128 budget
   with nothing playing). Now: 20 ms S-curve fade, then zero DSP; memory wiped in bounded slices
   (512 floats/frame) at block boundaries; an effect reopens only when clean; delay-line effects
   fade what they record (removes flanger/phaser/delay re-enable clicks); auto-wah power applied at
   the output. Steady-state audio bit-identical (patch FX settings and all-ten-on). Tests:
   `trueBypass`, `bypassCost` (timing guard, skipped under sanitizers via `AURORA_SKIP_TIMING`).
3. **Matrix screen crash fix.** Six-slot performance matrices (every factory patch) are padded to
   ten; opening the Matrix screen after loading a factory sound crashed the app since 0.25.0.
   Stale v1 test expectations refreshed (ten performance slots, collection "KiMiA", 70 globals).
4. **Factory library = AuroraFX only.** 765 retired patches archived with catalogs, Nova generators,
   Spectrum/reference audits and patch recipes in `archive/`; app/plug-in/CI/tests load only
   `Resources/AuroraFX.json`; retired-ID sessions fall back to the default sound (Felt & Timber);
   classic bank generators refuse to run.
5. **Docs** (this file, README, CHANGELOG, PATCH-DESIGN-RULES rule 8 CPU budget).

**Measured on the owner's M3 MacBook Air (8 GB), 44.1 kHz/128 frames** (benchmark harness in
`~/Desktop/KiMiA by Claude/bench`, outside the repo): idle with all FX off 27.7 % → 0.34 %;
pedal-held 8-bar passage Stage Cedar 22 % → 6 %, Tine Stage 76 22 % → 8 %, Glass Twelve 27 % → 4 %;
heaviest Dual Patch pair with 16 held keys ≈ 33 % mean / 50 % peak (was ≈ 65 %).

**Gig reconstruction (v0.25.0 engine, set-list Spectrum patches, pedalled chords + melody):**
Deepwater Pearls 82 % mean / 91 % median / 41 overrun blocks; effects were ~1 % of the load —
four layers × unison × pedal filled the 64-voice pool. A 256-frame buffer does not help a
sustained overload.

**Local validation on the branch:** `scripts/test.sh` green; `scripts/test-baseline.sh` green
(red on `63c0cc4`); `check-v1-specialized-regression.sh` green (crashed on `63c0cc4`);
`check-v1-ab-comparison.sh` green; `Tests/PluginCoreChecks.mm` green on all 55 patches;
`Tests/V1FactoryAudioAudit.mm` on AuroraFX: 55 patches, 0 failures. Not run: AU/VST3 build,
validator, auval (plug-in build tooling), GitHub CI.

## Current release — v0.25.0

- HEAD: `b29e88319ec69dbbccbba3d93b11f7dca6d60a5a` (`b29e883`), tagged `v0.25.0`, pushed to `origin/main` and `origin/v0.25.0` on 24 September 2026.
- Source metadata: app `0.25.0` build `37`; AU/VST3 source metadata `0.25.0`.
- Local standalone 0.25.0 release build completed successfully before tagging. A current local `build/Aurora.app` artifact is not guaranteed to remain present.
- **Installed plug-in boundary:** the locally installed AU and VST3 bundles are `0.24.3`. The v0.25.0 plug-in source has not been rebuilt/installed/revalidated after the final version bump.
- v0.25.0 features: flanger; tremolo with Tremolo/Pan/Rotary modes; bitcrusher; master compressor with gain-reduction meter; auto-wah; delay ducking; Performance Matrix 6→10; compact Delay + Compressor effects row; P1–P4 scroll-smoothness work.
- v0.24 line: four-operator FM engine with 16 visual algorithms; FM/EP factory expansion; natural-decay EP fixes; favorites-on-save; KiMiA display-name pass.

## Validation status — read before making release claims

### v0.25.0 GitHub CI: NOT GREEN

All four jobs associated with the v0.25.0 push failed:

- Product Smoke / standalone and AU+VST3 build: Swift compiler could not type-check `ContentView.body` in reasonable time at `Sources/AuroraApp.swift:261` (the generated plug-in interface copy reports the same body line).
- Aurora v1 Baseline: native test link failed because `FmEngine` symbols used by `SynthEngine` were absent from the test link (`FmEngine::initTables`, `FmEngine::renderSample`).
- Aurora v1 Specialized Regression: same FM-engine test-link class of failure.
- Native Sanitizers: ASan/UBSan and TSan native suites failed to link for the same missing FM-engine symbols.

Do not describe v0.25.0 CI as passing. These failures are recorded validation debt; code remediation is frozen pending an explicit unfreeze.

**Remediation status (25 September 2026).** The "missing FM-engine symbols" link failures are
fixed in `main` (`842ff85`). Branch `claude/dsp-bypass-and-performance` additionally makes the
baseline and specialized-regression suites pass locally (see the branch section). The Product
Smoke Swift `ContentView.body` timeout is **not** addressed and no CI run has been triggered:
treat all four jobs as red until a run proves otherwise.

### Factory-bank inventory

- Shipped: `Resources/AuroraFX.json` — 55 patches (48 single-layer, 7 two-layer), 16 categories.
- Archived (not shipped, not loaded): `archive/factory-banks/v0.25.0/` — Spectrum 300, Aurora 100
  (incl. 25 FM), Prism 100, Nova 100, Shimmer 29, GB109, Reference 2 = 765 patches, plus catalogs.
  The historical 438/463-sound audits and the re-baseline item are obsolete.

### Plug-ins and hosts

- v0.24.3 installed AU passed `auval -v aumu Auro RyBr` in the prior release work.
- v0.25.0 plug-in source is not represented by a successful current plug-in build/install/validator run.
- Logic Pro remains unverified in-app; exhaustive playback, bounce, automation, project, and commercial-host coverage remains incomplete.
- Public distribution still lacks Developer ID signing, notarization, and clean-machine installation qualification.

## Documentation status

Authoritative current documents:

- `README.md` — current release overview plus chronological release archive
- `CHANGELOG.md` — release-by-release record
- `DAW-INTEGRATION.md` — installed/source plug-in boundary and host-verification limits
- `FUTURE-PROPOSAL-SCROLL-SMOOTHNESS.md` — shipped design history
- `FUTURE-PROPOSAL-MODULATION-EXPANSION.md` — shipped design history
- `FUTURE-PROPOSAL-FM-ENGINE.md` — shipped design history plus deferred wipe
- `Dual-Patch-Specification.md` — locked, not implemented
- `AURORA-*-TEST-*.md` — v0.22 reconstruction authority; current release must still pass the test contract before being called green

## Pending queue

1. **Owner review of branch `claude/dsp-bypass-and-performance`** — play-test on the CK88 rig
   (pedalled pianos/EPs, Dual-Patch-style layering, toggling effects live), then decide on
   merge/push. Nothing is pushed.
2. **CI remediation:** the Swift `ContentView.body` type-check timeout (Product Smoke) is untouched.
   `FmEngine.o` links are in `main` since `842ff85`. No CI run has happened on the branch.
3. **Plug-in rebuild/install/revalidation:** installed AU/VST3 bundles are 0.24.3 and carry the
   Matrix crash and the old bypass; rebuild after owner approval.
4. **Dual Patch live:** locked design, not implemented. The engine now leaves headroom for it
   (see PATCH-DESIGN-RULES.md rule 8).
5. **Hardware validation:** owner-deferred. Gates: three-controller operation, pedals/ownership,
   reconnect/hot-plug, external clock, 30-minute and two-hour runs (thermal: fanless MacBook Air),
   latency, memory, exact output/hub setup.
6. **Public distribution:** Developer ID signing/notarization and clean-machine install.
7. **Brand follow-up:** internal repo/file/identifier paths intentionally remain Aurora.
8. **Effects sound quality (proposal, needs owner audition):** the Schroeder reverb and grain
   shimmer are the oldest DSP in the chain; any algorithm change alters every patch that uses
   them, so it must be auditioned before it replaces the current sound.

The original specification's sampler/granular engine, sample import/library management, microtuning/MPE, and optional hardware-audio/Aggregate Device workflows remain later scope, not active queue items.

## Handoff protocol

1. Read this file first.
2. Label the active role.
3. Re-check the code freeze before any action.
4. Make the smallest authorized change.
5. Update this file after every significant decision or documentation change.
6. Never describe historical test results or installed plug-in versions as current without checking the live evidence.
