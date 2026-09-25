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

### Named unfreeze in effect (25 September 2026)

The owner directed implementation of two items, and that request is the unfreeze for exactly
their scope. Nothing else is unfrozen, and no release action was taken or implied:

1. **Master bypass / power toggles** for the shared and master FX panels, covering both the UI
   and DSP silence gating.
2. **Test infrastructure** — link `FmEngine.o` into every native test target that already
   links `SynthEngine.o`, and make the benchmark passes opt-in.

Still frozen: the SwiftUI `ContentView.body` split, factory-bank re-baseline, plug-in
rebuild/install/revalidation, Dual-Patch, release/tag/push, and the stale bank-count fixtures
described below.

## In-progress work (25 September 2026)

**Master FX power toggles — implemented, uncommitted.** `AGGlobalCount` is now **70**
(was 60). Ten append-only power globals were added at IDs 60–69:
`AGShimmerPower, AGDelayPower, AGReverbPower, AGChorusPower, AGPhaserPower, AGFlangerPower,
AGTremPower, AGCrushPower, AGWahPower, AGCompPower`. Append-only, so every earlier global ID and
every saved `patch.fx` key keeps its meaning; old patches simply have no `fx[60…69]` and
default to powered on.

- **UI:** `Panel` gained an optional header accessory, and `FxPowerToggle` is wired into all ten
  FX panel headers. `SynthModel.applyPatch` now pushes globals `16...69` (it stopped at 59).
- **DSP:** one smoothed 0/1 gate per effect, advanced every sample, applied to every injection
  point (input, regeneration, return). A closed gate is exact silence; the delay stops
  regenerating and writes silence into its line, the Schroeder rings are cleared once the fade
  has reached zero, and the compressor's makeup/gain-reduction both collapse to unity.
  Bypass is click-free, and `prepare()` snapshots the toggles so a struck effect cannot leak
  one fade of wet audio at engine start.
- **Shipping default: only Delay and Reverb are powered.** The owner requires every other
  effect to start off. All three default sites agree (`SynthEngine` constructor,
  `PluginCore` `fallback[]`, `AuroraApp` `fxDefaults`): IDs 61/62 = 1, 60 and 63–69 = 0.
  `masterFxPower` asserts this on a bare engine, so it cannot regress. Consequences handled:
  `extendedEffects`, `phaserEffect`, `matrices` and `benchmark` now call a new
  `powerOn()` helper, because they assert that chorus/phaser (and the shared-effect Matrix
  destinations) change the audio. **Consequence to be aware of:** the frozen v1 factory banks
  carry no `fx[60…69]` keys, so any bank patch that relied on shimmer/chorus/phaser/flanger/
  tremolo/bitcrusher/auto-wah/compressor now needs an explicit `"<id>": 1` in its `fx` block to
  keep that effect. Writing those keys into the banks is a separate, owner-gated resources change
  that also interacts with the 463-sound re-baseline.
- **Deliberately excluded:** the Play-screen house EQ. Its bands are session-sticky and not
  patch data, and it is identity at 0 dB, so a patch-level power switch there would be
  misleading. Per-layer `LayerSends.shimmerBypass` was also kept: it is a per-layer send mute,
  semantically different from the master switch, and removing it would break patch decode.
- **Verification:** `Tests/SynthEngineTests.cpp::masterFxPower` proves each toggle is a true
  switch and that a struck effect renders the dry bus sample-accurately, alone and with all
  ten struck together.

**Latent plug-in bug found and fixed on the way.** `Sources/PluginParameters.hpp::globals[]`
held 37 entries while `AGGlobalCount` was 60, so `Core::spec()` read past the end of the table
for IDs 1037–1059 (the whole v0.25.0 FX block), and `PluginVST.mm` dereferenced
`globals[p].name` across the same range while answering `getParameterInfo`. The table now
covers all 70 globals, `scripts/generate_backend.py` carries the full range list, and
`Tests/PluginCoreChecks.mm` holds a `static_assert` so the table can never fall short again.
The generator now also refuses to run instead of silently truncating `layers[]`/`defaults[]`,
which its stale `assemble_prism_bank.py` inputs would have done.

**CI debt item 1 — FM test link: fixed locally, not yet re-run on CI.** `FmEngine.o` is now in
`scripts/test.sh`, `scripts/test-baseline.sh`, `scripts/check_plugins.sh`,
`scripts/audit_patch_bank.sh`, `check-interface.sh`, `check-v1-ab-comparison.sh`,
`check-v1-specialized-regression.sh`, and the specialized-regression workflow. Verified locally:
`scripts/test.sh` green, `scripts/build.sh` green, `scripts/test-baseline.sh` compiles, links
and runs its native half. The `ContentView.body` compile risk is untouched.

**Found while fixing the test runner:** `scripts/test.sh` could not run at all on macOS's
`/bin/bash` 3.2 — `set -u` plus `"${SANITIZER_FLAGS[@]}"` on an empty array aborts before any
compilation. Sanitizer flags are now appended only when non-empty.

**Still blocking a full green run — pre-existing, owner decision needed.** `Aurora100.json`
contains 125 patches in the committed tree, but `BaselineChecks.swift` and
`Tests/PluginCoreChecks.mm` still assert 100, so `test-baseline.sh`'s last step and
`check_plugins.sh` fail on that fixture count. This is the same drift already recorded as the
463-sound inventory re-baseline item; it is unrelated to the power-toggle work and was left
alone.


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

**Local remediation status (25 September 2026, uncommitted).** The three "missing FM-engine
symbols" failures and the specialized-regression factory-audit link are fixed in the working
tree and verified locally (see the in-progress section). The Product Smoke Swift
`ContentView.body` timeout is **not** addressed, and no CI run has been triggered. Treat all
four jobs as still red until the owner reviews and commits this work.

### Factory-bank inventory

Current resource counts:

- `Aurora100.json`: 125
- `AuroraPrism100.json`: 100
- `AuroraNova100.json`: 100
- `AuroraGB109.json`: 109
- `AuroraShimmer29.json`: 29
- Five-bank v1 audit inventory: **463**
- Separate Spectrum bank: 300

The **438** total in v0.22-era documentation was accurate for the historical five-bank snapshot (100+100+100+109+29). The current 463-sound inventory still requires a clean full audit/re-baseline; the historical 438-pass result must not be presented as current certification.

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

1. **v0.25.0 CI remediation — highest priority technical debt:** split the oversized SwiftUI `body` expression and add `FmEngine.cpp` to every native test link. **The `FmEngine.cpp` half is done in the working tree and locally verified; the `body` split is untouched and remains frozen.** Do not re-run or describe CI as green until the owner commits and the workflows run.
2. **Current 463-sound factory audit/re-baseline:** owner-triggered; the old library wipe remains intentionally deferred so the instrument is never shipped empty. Also resolves the stale `Aurora100 count == 100` literals in `BaselineChecks.swift` and `Tests/PluginCoreChecks.mm`, which now fail against the committed 125-patch bank.
3. **v0.25.0 plug-in rebuild/install/revalidation:** source metadata is current, but installed bundles remain 0.24.3.
4. **Dual-patch live:** locked design, not implemented; parked until explicitly unfrozen.
5. **Hardware validation:** owner-deferred. Original gates remain three-controller operation, pedals/ownership, reconnect/hot-plug, external clock, 30-minute and two-hour runs, latency, memory, and exact output/hub setup.
6. **Public distribution:** Developer ID signing/notarization and clean-machine install.
7. **Brand follow-up:** internal repo/file/identifier paths intentionally remain Aurora; domain/trademark administration and deeper rename tiers are parked.
8. **Optional EP cleanup:** Solar Tine, Ballad Tine, Felt Cinema Tine, and Wurli Coals still hold sustain; conversion to natural EP decay/move to FM EP requires a separate owner decision.

The original specification's sampler/granular engine, sample import/library management, microtuning/MPE, and optional hardware-audio/Aggregate Device workflows remain later scope, not active queue items.

## Handoff protocol

1. Read this file first.
2. Label the active role.
3. Re-check the code freeze before any action.
4. Make the smallest authorized change.
5. Update this file after every significant decision or documentation change.
6. Never describe historical test results or installed plug-in versions as current without checking the live evidence.
