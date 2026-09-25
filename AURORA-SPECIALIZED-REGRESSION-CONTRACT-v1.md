# Aurora v1 Specialized Regression Contract

> **Current-status note (25 September 2026):** this remains the reconstructed behavioral contract. The v0.25.0 FM-engine link failure is fixed and the suite passes locally on 0.26.1; GitHub CI on the `v0.26.0` push was still red because of the deprecated `macos-14` runners' Xcode 15.4, and 0.26.1 moves CI to `macos-26`. Historical suite results below describe the build on which they were recorded; see `SHARED_STATE.md`.

**Owner's rule (25 September 2026):** "I don't want to make the software worse just to comply with an outdated test. It's wrong. The test needs to adapt. The test only needs to catch bad errors, not make the software worse." Fix KiMiA when a test catches a real defect; otherwise update the test or the CI. Details in [AURORA-TEST-CONTRACT-v1.md](AURORA-TEST-CONTRACT-v1.md).

This suite reconstructs Aurora's specialized regression coverage from the current working product, current production architecture, and the intent of the historical tests.

For the methodology behind that reconstruction, the limits of code-derived expectations, oracle-provenance categories, and guidance for distinguishing production bugs from stale tests, see [AURORA-V1-TEST-RECONSTRUCTION-ASSESSMENT.md](AURORA-V1-TEST-RECONSTRUCTION-ASSESSMENT.md).

## Rules

1. Production behavior and current public/model/DSP contracts are authoritative.
2. Historical tests are evidence of important risk areas, not authority over current architecture.
3. Production code is never changed merely to satisfy a historical assertion.
4. The historical suite remains untouched until explicitly retired.
5. New tests prefer observable behavior and persistence contracts over incidental internal representations.

## Recovered model/UI areas

- XY pointer coalescing and clamping.
- Scope display stability.
- Concurrent plugin-library merge semantics.
- Output-gain migration.
- Preset single/bank decoding and malformed-data rejection.
- Extended controls and legacy defaults.
- Current factory preset schema, authored-data round-trip, macro endpoints and configurable XY mappings.
- Search/filter behavior and stable telemetry publications.
- Master/transpose/tap-tempo/session persistence.
- Sound/performance matrix independence and undo/redo.
- Save/update/Save As, rename, delete/restore and editable categories.
- Extended FX, delay, EQ, shimmer and expressive settings.
- Embedded wavetable persistence, preview, undo/redo and legacy reset.
- Motion shapes, layer independence and persistence.
- A/B comparison, layer copy/paste, sends, solo and browsing.
- XY assignment/range/inversion persistence.
- Themes do not mutate patch data.
- Custom macros, saved motion shapes, MIDI learn/pickup and variation locks.

## Factory audio audit

The dedicated DSP audit is designed to render every factory preset independently from the model/UI harness. Each preset is loaded, auditioned, stress-rendered, and drained through Panic while checking finite output, useful signal level, bounded peak, release behavior, and voice cleanup.

The audit follows the same migration rules as `SynthModel.sanitized`:
- sparse/legacy layer dictionaries are accepted when all stored keys are valid;
- missing extension parameters use current `LayerPatch.initial` defaults;
- legacy presets without parameter 97 use the historical rate-division migration for parameter 23;
- session EQ globals 20...22 are not treated as patch FX.

This matters for `AuroraGB109`, whose 109 presets intentionally store parameters 0...96. Parameters 97 and 98 are supplied by defaults when the bank is loaded. At the v0.22 reconstruction baseline, the other four factory banks stored all 99 layer parameters; the current architecture defines 126 layer parameters.

CI is structured to audit the five banks independently so one large bank cannot hide a failure in another. A current 463-sound pass still needs to be re-established; see `SHARED_STATE.md`.

## Isolated A/B contract

A/B comparison engine behavior is tested in a fresh process with one `SynthModel` and one standalone engine. The long model/UI regression tests model state and persistence only, avoiding false failures from multiple model instances sharing the standalone test engine.

## Historical native DSP validation and current boundary

At the reconstruction baseline, the native suite was green under ASan/UBSan and TSan. Its behavior-level coverage remains valuable evidence for recording/WAV normalization, wavetable generation and import, motion envelopes, layer sends/solo, dual filters, oscillator modulation, character processing, LFO refinements, MIDI ownership/routing, transpose, arp, matrices, FX, mono/legato/glide and queue recovery. Current v0.25 sanitizer jobs are not green because their native test link omits FM-engine symbols.

Those tests remain untouched while this reconstructed suite recovers the model/UI workflows that had become unreachable behind stale factory assumptions.

## Historical plug-in validation and current boundary

Historical plug-in checks cover stable parameter IDs, state round-trip, finite audio, host lifecycle, sample-offset MIDI, 32/64-bit processing and editor attachment. The current v0.25.0 plug-in source is not green: its build CI hits the SwiftUI type-check timeout, and the installed bundles remain 0.24.3.

## Corrected factory contract

Historical behavior incorrectly required applying stored macro values to leave every raw parameter identical and assumed fixed XY macro numbers.

Aurora v1 instead requires:
- factory presets satisfy the current schema;
- authored data round-trips;
- each macro can reach 0 and 1 while leaving a valid patch;
- XY follows each preset's effective XYSettings;
- sparse custom macro definitions are valid;
- legacy factory layers may omit newer extension parameters and are migrated exactly as current production loading does.

## Maintenance

When behavior intentionally changes, update this contract first and then the corresponding reconstructed test.
