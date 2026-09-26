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

- **The code freeze of 24 September 2026 (after v0.25.0) was lifted by the owner on 25 September 2026** for the Claude Code work described under "Owner direction in effect". Outside that direction, do not edit `Sources/`, scripts, tests, resources, plug-in code, or build configuration without an explicit owner request.
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

**Tests adapt to the software (owner's rule).** "I don't want to make the software worse just to
comply with an outdated test. It's wrong. The test needs to adapt. The test only needs to catch
bad errors, not make the software worse." (Reza, 25 September 2026.) When a test or CI job fails,
fix KiMiA only if it caught a real defect; otherwise update the test or the CI and say why in the
commit. See the owner's rule in `AURORA-TEST-CONTRACT-v1.md`.

**Live gigging first; plug-ins only on request.** KiMiA is used as the standalone app for live
gigs and not in a DAW at the moment. Do not rebuild, install or revalidate the AU/VST3 plug-ins
unless the owner asks (owner, 25 September 2026); keep plug-in source compiling and its tests
green.

**Owner patch policy:** every AI (and anyone else designing sounds) uses one or two layers only —
layer A, or A + B — so a future Dual Patch runs four layers in total. Layers C and D are reserved
for the owner: AI never switches them on, fills or edits them, and leaves the owner's C/D content
untouched (PATCH-DESIGN-RULES.md rule 3; CPU budget in rule 8; clicks in rule 9).

## Release 0.26.0 work (branch `claude/dsp-bypass-and-performance`, merged to `main`)

Commits on top of `63c0cc4` (`git log --oneline 63c0cc4..`), each with its tests green:

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
6. **Dropout counter.** `aurora_audio_overloads()` counts Core Audio processor overloads on the
   running device (first 0.5 s after start ignored); the header shows a red count from the first
   dropout on. Plug-ins return 0.

**Measured on the owner's M3 MacBook Air (8 GB), 44.1 kHz/128 frames** (benchmark harness in
`~/Desktop/KiMiA by Claude/bench`, outside the repo): idle with all FX off 27.7 % → 0.34 %;
pedal-held 8-bar passage Stage Cedar 22 % → 6 %, Tine Stage 76 22 % → 8 %, Glass Twelve 27 % → 4 %;
heaviest Dual Patch pair with 16 held keys ≈ 33 % mean / 50 % peak (was ≈ 65 %).

**Gig reconstruction (v0.25.0 engine, set-list Spectrum patches, pedalled chords + melody, inside
a real AUHAL callback on this Mac):** Deepwater Pearls 82 % mean / 91 % median load and **825
Core Audio overloads in 27 s** at 128 frames, still 119 at 256 frames; effects were ~1 % of the
load — four layers × unison × pedal filled the 64-voice pool. The new engine alone cuts that
patch to 1 overload; the heaviest new-bank Dual Patch pair runs 41 % mean / 56 % max with none.

**Local validation on the branch:** `scripts/test.sh` green; `scripts/test-baseline.sh` green
(red on `63c0cc4`); `check-v1-specialized-regression.sh` green (crashed on `63c0cc4`);
`check-v1-ab-comparison.sh` green; `Tests/PluginCoreChecks.mm` green on all 55 patches;
`Tests/V1FactoryAudioAudit.mm` on AuroraFX: 55 patches, 0 failures. Not run: AU/VST3 build,
validator, auval (plug-in build tooling), GitHub CI.

## Current release — v0.26.0

- Tag `v0.26.0` on `main` (25 September 2026): fast-forward of branch
  `claude/dsp-bypass-and-performance` plus the version bump. App `0.26.0` build `38`; AU/VST3
  source metadata `0.26.0` (AU component version 6656; the VST3 class version string was stale
  at "0.24.0" and now reads 0.26.0).
- Contents: true FX bypass and the Reverb re-clear fix, faster voice rendering (bit-identical)
  with silent pedal-held voices freed, the Matrix screen crash fix, the dropout counter, and the
  single-bank factory library (AuroraFX, 55 patches) with the retired banks archived.
- The older annotated tag `v0.26` (`f4d645c`, "FX-only factory + 55-patch MODX bank") is left
  untouched; it predates the version bump and that build still reported 0.25.0.
- **Installed plug-ins:** still 0.24.3 (checked 25 September). The owner deferred plug-in
  rebuilds until asked; the standalone app is the gig instrument.
- **Not in 0.26.0:** the Dattorro Plate reverb (second reverb type, Classic stays default) is
  work in progress on local branch `claude/plate-reverb`, not pushed.

## Next release — v0.26.1 (branch `claude/0.26.1-click-fixes`, not pushed)

From the owner's first play-test of 0.26.0: Sub Marine clicked on single notes (worst when two
keys alternate), Black Moss crackled with a full 64-voice pool, and one run showed 267 dropouts
that could not be reproduced.

- **Causes found (offline click scan + real Core Audio runs):** Sub Marine — the corner where a
  4 ms linear attack turns into the decay, at -44 to -48 dB on a pure sine sub-bass (not the
  speakers, not the limiter). Black Moss — the old Output-boost limiter clamped every sample above
  0.98 (hard clipping, 1,905 samples at +12.3 dB), plus voice-steal clicks at the full pool.
- **Fixes:** two-stage 0.7 ms voice-gain declick (-74 dB), 16 ghost slots that fade stolen voices
  over 6 ms with their real waveform (steal clicks +42 → +16 dB over the chord's treble),
  peak-hold soft-knee limiter (ceiling 0.98; 0 dB boost unchanged). Heavy Dual Patch cost
  33.0 % → 33.8 %. Tests: `envelopeDeclick`, `cleanVoiceSteal`, `cleanOutputLimiter`.
- **Dropout indicator:** count in the DSP colour, stays until clicked (click = reset to zero);
  triangle blinks at 5 Hz while dropouts arrive, stays lit 5 s, then hides.
- **267 dropouts:** not reproducible on this Mac; the likeliest explanation is heavy benchmark
  and build jobs from this session running at the same time on the fanless Air (the repo is on
  the iCloud-synced Desktop, so iCloud was also syncing their output). Heavy jobs now run under
  `taskpolicy -b` (efficiency cores). Watch the counter.
- **CI:** all workflows move from the deprecated `macos-14` (Xcode 15.4) to `macos-26`
  (Xcode 26.6); the interface code that Xcode 15.4 could not type-check is unchanged (owner's
  rule: tests adapt to the software). `scripts/build.sh` retries signing when iCloud re-tags
  the bundle.
- **Docs:** PATCH-DESIGN-RULES rule 3 (layers C/D reserved for the owner) and rule 9 (clicks);
  the owner's test rule in both test contracts.
- **Local validation:** `scripts/test.sh`, baseline, specialized regression, A/B, PluginCoreChecks
  (55 patches) and the AuroraFX audio audit (55 patches, 0 failures) all green; the plug-in
  interface type-checks with `AURORA_PLUGIN`. Plug-ins not rebuilt (owner direction).

## Work after 0.26.1 — branch `claude/0.27-reverb-and-patches` (local, not pushed)

On top of the local 0.26.1 commits (`90b6f07`):

- **Reverb (`67f2c25`):** Type Classic/Plate (global 70; Plate = Dattorro, level-matched to Classic
  within ~2 dB by a Decay-dependent gain), Pre-delay 0–200 ms (71), Tone (72; 0.5 = the original
  damping). Size/Pre-delay changes cross-fade over 50 ms (were +11 to +23 dB clicks on pure
  tones). Defaults reproduce 0.26.1 bit-for-bit (170 patches, three A/B scenarios). The owner
  approved the Plate ("just do it"); it ships in the main app, no separate test build.
- **Tests (`0a5ef75`):** temporary files follow `$TMPDIR` (sandbox/CI friendly).
- **Design rules (`0caf190`):** effects rule (only Reverb ships on; Sound FX exempt; the original
  55 exempt), Dual Patch halves, batches, ` -CL` names, reference-based imitation.
- **FM engine:** exponential (DX-style) operator envelopes (env mode 2), rates up to 1000 (1 ms
  segments), editor Index slider with a squared taper. **Oscillators:** DC-free pulse waves
  (subtractive and FM).
- **50 new patches (` -CL`), done and awaiting the owner's review:** `scripts/claude_patches.py`
  (authoring DSL + definitions, appended by `scripts/assemble_modx_bank.py` after the 55
  originals), levels calibrated to −33 dBFS with `scripts/calibrate_claude_levels.py` and
  `bench/patchcheck` (45 exact, 4 within 1–3 dB where Level is at its cap; the Riser by hand).
  `PATCH-ENGINE-REFERENCE.md` = how the engine behaves, for patch designers.
- Version numbers still read 0.26.1; the owner decides release numbering and pushes.

**No backward compatibility until after the v1 assessment (owner, 26 September 2026):** "make
the best engine possible ... forget about backward compatibility". Engine changes may alter
existing patches; the owner will build new patches and does not plan to reuse the old ones.

**Version 1 plan (owner, 26 September 2026):** v1 = the current software + 150 factory patches
(55 originals + 50 Claude patches reviewed together + 45 more later), then a full stress test and
optimisation assessment for real gigs (not commercial: no notarisation needed; no crackles, no
crashes). v2 = Dual Patch. **FM engine improvements are welcome** ("if things go bad we can go
back") — keep existing patches' sound unless the owner agrees otherwise.

## Validation status — read before making release claims

### v0.25.0 GitHub CI: NOT GREEN

All four jobs associated with the v0.25.0 push failed:

- Product Smoke / standalone and AU+VST3 build: Swift compiler could not type-check `ContentView.body` in reasonable time at `Sources/AuroraApp.swift:261` (the generated plug-in interface copy reports the same body line).
- Aurora v1 Baseline: native test link failed because `FmEngine` symbols used by `SynthEngine` were absent from the test link (`FmEngine::initTables`, `FmEngine::renderSample`).
- Aurora v1 Specialized Regression: same FM-engine test-link class of failure.
- Native Sanitizers: ASan/UBSan and TSan native suites failed to link for the same missing FM-engine symbols.

Do not describe v0.25.0 CI as passing. These failures are recorded validation debt; code remediation is frozen pending an explicit unfreeze.

**Remediation status (25 September 2026).** The "missing FM-engine symbols" link failures are
fixed in `main` (`842ff85`). CI on the `v0.26.0` push (`6b51a31`): Native Sanitizers **green**;
Product Smoke, v1 Baseline and v1 Specialized Regression **red**, all three from one error —
`AuroraApp.swift:261:25`, "unable to type-check this expression in reasonable time". Line 261 is
`FmEnvCurve.body` (the FM operator envelope mini-curve), not `ContentView.body` as recorded above.
The runners were `macos-14` (deprecated by GitHub) with Xcode 15.4 (Swift 5.10); this Mac builds
with Swift 6.4, which compiles that code without trouble, so the error only showed on GitHub.
**Owner direction (25 September 2026): the CI serves the software.** When a stale test or an
outdated CI toolchain fails, update the test or the CI; never make the software worse to satisfy
it. 0.26.1 therefore moves every workflow to `macos-26` (Xcode 26.6) and leaves the interface
code unchanged. Confirm on the next CI run before calling CI green.

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
- `PATCH-DESIGN-RULES.md` — what a factory patch must be (owner's rules)
- `PATCH-ENGINE-REFERENCE.md` — how the engine behaves, for patch designers (with the 50-patch plan)
- `AURORA-*-TEST-*.md` — v0.22 reconstruction authority; current release must still pass the test contract before being called green

## Pending queue

1. **Owner play-test of 0.26.1** on the CK88 rig (Sub Marine alternating notes, Black Moss full
   pool, pedalled pianos/EPs, toggling effects live, dropout indicator), then push/tag on request.
2. **CI remediation:** 0.26.1 moves all workflows from `macos-14` (Xcode 15.4, which failed to
   type-check `FmEnvCurve.body`) to `macos-26` (Xcode 26.6). Confirm on the first CI run after it
   is pushed; fix whatever fails there in the CI or the tests unless it is a real product bug.
3. **Plug-in rebuild/install/revalidation — only when the owner asks** (deferred 25 September:
   standalone gig use). How: build AU/VST3 with the pinned SDKs (`PluginDependencies.lock`,
   checkouts in `build/deps`), install with `scripts/install_plugins.sh` (backs up the old
   bundles), validate with `scripts/check_plugins.sh`.
4. **Dual Patch live:** locked design, not implemented. The engine now leaves headroom for it
   (see PATCH-DESIGN-RULES.md rule 8).
5. **Hardware validation:** owner-deferred. Gates: three-controller operation, pedals/ownership,
   reconnect/hot-plug, external clock, 30-minute and two-hour runs (thermal: fanless MacBook Air),
   latency, memory, exact output/hub setup.
6. **Public distribution:** Developer ID signing/notarization and clean-machine install.
7. **Brand follow-up:** internal repo/file/identifier paths intentionally remain Aurora.
8. **Plate reverb — done** on `claude/0.27-reverb-and-patches` (`67f2c25`). The old local branch
   `claude/plate-reverb` (`f7cb142`) is superseded.
9. **50 new patches (` -CL`):** built and calibrated; the owner reviews all 50 together (keep /
   tweak / drop). Approved patches lose ` -CL` in the next build; ids stay.
10. **Version 1 assessment + stress test:** after the patches — full-system optimisation for
   real gigs (crackle-free, crash-free); the owner prefers a fresh session with a handoff.

The original specification's sampler/granular engine, sample import/library management, microtuning/MPE, and optional hardware-audio/Aggregate Device workflows remain later scope, not active queue items.

## Handoff protocol

1. Read this file first.
2. Label the active role.
3. Re-check the code freeze before any action.
4. Make the smallest authorized change.
5. Update this file after every significant decision or documentation change.
6. Never describe historical test results or installed plug-in versions as current without checking the live evidence.
