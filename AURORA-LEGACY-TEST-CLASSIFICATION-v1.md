# Aurora v1 Legacy Test Classification

This document classifies the historical Aurora test suite against the current v1 architecture.

It does **not** delete or disable any historical test. The old suite remains available as regression archaeology until explicitly retired.

## Authority

For Aurora v1, test authority is:

1. current intended product behavior;
2. current public/model/DSP contracts;
3. real standalone and plug-in workflows;
4. historical tests as evidence of risk areas, not as authority over superseded architecture.

The current v1 baseline and reconstructed specialized regression suite were built under that rule.

## Classification

| Historical test | Status | v1 treatment | Reason |
| --- | --- | --- | --- |
| `InterfaceChecks.swift` | **REPLACE as CI authority / RETAIN as reference** | `V1SpecializedRegressionChecks.swift` + isolated A/B test | Contains useful model/UI regression history, but also obsolete macro-center equality, fixed-XY and old state-storage assumptions. Its useful workflows have been reconstructed against current behavior. |
| `check-interface.sh` | **REPLACE as CI authority** | `check-v1-specialized-regression.sh` | The runner currently makes Product Smoke red because it executes the stale `InterfaceChecks.swift` contract. Retain until explicit retirement. |
| `Tests/SynthEngineTests.cpp` | **KEEP** | Continue running under native sanitizer workflow | Deep current DSP/MIDI coverage: routing, ownership, Panic, transpose, arp, matrices, FX, mono/legato/glide, queue recovery and concurrency. Green under ASan/UBSan and TSan. |
| `Tests/RecordingChecks.cpp` | **KEEP** | Continue running | Valid behavioral coverage for WAV recording and normalization. |
| `Tests/WavetableTests.cpp` | **KEEP** | Continue running | Valid DSP/import/warp/phase/custom-table/concurrency coverage. |
| `Tests/MotionTests.cpp` | **KEEP** | Continue running | Valid motion-envelope, tempo-sync, retrigger and publication coverage. |
| `Tests/LayerToolsTests.cpp` | **KEEP** | Continue running | Valid layer-send and Solo DSP behavior. |
| `Tests/SonicUpgrades.cpp` | **KEEP** | Continue running | Valid dual-filter, oscillator-modulation, character, modulation-envelope and stability coverage. |
| `Tests/RefinementChecks.cpp` | **KEEP** | Continue running | Valid LFO/filter-route/unison/formant/tone regression coverage. |
| `Tests/PatchBankAudit.mm` | **REPLACE as current factory-bank authority / RETAIN as reference** | `Tests/V1FactoryAudioAudit.mm` | Valuable original idea, but its loader encodes older layer-count assumptions and is not migration-equivalent to current `SynthModel.sanitized`. The v1 audit covers all five current banks and mirrors current legacy migration. |
| `Tests/SpectrumAudit.mm` | **KEEP** | Continue as specialized Spectrum calibration/audit | It covers calibrated Spectrum-specific level and macro-endpoint behavior not replaced by the general factory audio audit. Current Panic handling is already aligned with the async mute-bus architecture. |
| `Tests/ReferenceLevels.mm` | **KEEP** | Continue running | Small focused loudness/reference-level safety gate. `prepare()` is a valid silent hard-reset boundary under current Panic architecture. |
| `Tests/PluginCoreChecks.mm` | **KEEP** | Continue running | Valuable plug-in state, migration, stable parameter-ID, MIDI learn, finite-audio and instance-isolation coverage. |
| `Tests/PluginHostChecks.mm` | **KEEP** | Continue running | Valuable real VST3 host lifecycle, MIDI timing, automation, state recall, 32/64-bit process and editor attachment coverage. |
| `Tests/BridgeProbe.cpp` | **KEEP while native harness uses it** | Keep optional bridge smoke | Low-cost bridge/API coverage. |
| `Tests/NormalizeRecording.cpp` | **KEEP as helper/tool** | Retain with recording checks | Supports the recording normalization regression path. |

## Historical assumptions confirmed obsolete

### Macro-center raw equality

Historical InterfaceChecks reapplied all eight stored macro values and required every raw parameter to remain identical.

That is not the current macro contract. Default macros intentionally transform controls and custom macro definitions may be sparse.

### Fixed XY macro numbers

Historical InterfaceChecks assumed XY always targeted fixed macro indexes.

Current Aurora uses per-preset `XYSettings`, including axis assignment, range and inversion.

### EQ as patch data

Historical checks treated globals 20...22 as patch FX.

Current Aurora treats EQ as session-sticky house EQ, independent of patch loading.

### Shared-engine A/B assertion

The historical monolithic interface process asserted standalone engine state while multiple `SynthModel` instances shared the singleton test engine.

Current A/B engine behavior is tested in a fresh process with one model and one engine.

### Exact stored layer-count assumptions

Current Aurora has 99 layer parameters, but legacy factory presets may legitimately store fewer values.

`AuroraGB109` stores parameters 0...96. Current loading supplies defaults for parameters 97 and 98 and recognizes absence of 97 as the legacy arp-rate format, migrating old parameter 23 divisions before applying the patch.

## Current specialized v1 coverage

The reconstructed v1 suite now provides independent coverage for:

- current factory schema and authored-data round-trip;
- sparse custom macros and configurable XY;
- session/preset CRUD and migration;
- matrices, expressive controls and telemetry publication behavior;
- sticky session EQ and patch FX separation;
- embedded wavetables and motion persistence;
- layer copy/paste, solo, browsing and A/B workflow;
- MIDI learn/pickup, variation locks, themes and creative tools;
- isolated A/B engine behavior;
- full audio/Panic/stress rendering of all 438 current factory presets.

## Current factory-bank audit

The dedicated v1 audio audit covers:

- Aurora100: 100 presets
- AuroraPrism100: 100 presets
- AuroraNova100: 100 presets
- AuroraGB109: 109 presets
- AuroraShimmer29: 29 presets

Total: **438 presets**.

Each preset is loaded under current migration rules, rendered for useful signal, stressed at high velocity/master level, checked for finite/bounded output, released, and drained through the current Panic transition.

## Recommended eventual CI shape

When the historical suite is explicitly retired, the clean v1 CI structure should be:

1. **Aurora v1 Baseline** for architectural contracts.
2. **Native Sanitizers** for the retained native DSP/regression suite.
3. **Aurora v1 Specialized Regression** for reconstructed model/UI, isolated A/B and current factory-bank audio audits.
4. **Product/plugin smoke** for standalone build plus AU/VST3 build/host validation.

The obsolete `InterfaceChecks.swift` gate should not remain a release blocker once explicit retirement is authorized.
