# Changelog

## 0.23.1 — 2026-09-22

### Fixes

- Completed the 0.23 five-LFO upgrade in the factory-bank pipeline and plug-in layer: `PluginParameters.hpp` layer defaults now cover all 126 parameters (was 99), so AU/VST3 no longer read past the defaults array when loading 99-parameter factory patches.
- Plug-in patch validation and apply paths accept 6- or 10-slot Sound Matrices (performance stays 6); legacy 6-slot patches have slots 6–9 cleared on load.
- `rebuild_factory_bank.py` targets the 126-parameter engine: per-layer LFO 3–5 voices and 10-slot Sound Matrix routes (pulse width, wavetable formant/tone/position, character, filter envelope). Factory banks themselves are unchanged in this release.
- Patch-bank audit accepts 6- or 10-slot matrices.

### Version metadata

- Git tag: `v0.23.1`
- Standalone marketing version: `0.23.1`
- Standalone build: `30`
- AU/VST3 marketing version: `0.23.1`

## 0.23.0 — 2026-09-22

### Modulation

- Added LFO 3, LFO 4, and LFO 5 on each layer. They have Depth and no destination of their own. Depth scales every Sound Matrix route from that LFO and defaults to full.
- Kept LFO 1 and LFO 2 behavior, including their Destination and Depth. An unrouted new LFO does not change the sound.
- Widened the Sound Matrix from 6 to 10 slots and appended destinations through filter envelope, wavetable formant and tone, character, pulse width, detune, and the other continuous controls. Shared effect destinations stay off the Sound Matrix. The Performance Matrix remains 6 slots.
- A saved 6-slot matrix loads as 10 slots. Existing parameter IDs are unchanged.

### Interface

- Added a second Edit row for LFO 3–5. The destination line reads “Select destination on the Matrix”.
- Added a per-layer Shimmer bypass stored in the patch. The send level is kept.
- All Patches remembers the category, User Saved filter, search, and scroll row for the session. The master slider sits between the search field and the patch arrows.

### Regression

- Baseline engine coverage for the five LFOs, slot 10, the new destinations, rejected routes, and the 46-value modulation meter.
- Baseline model coverage for the longer parameter list, legacy matrix padding, LFO 5 formant routes, and per-layer Shimmer bypass.

### Version metadata

- Git tag: `v0.23`
- Standalone marketing version: `0.23.0`
- Standalone build: `29`
- AU/VST3 marketing version: `0.23.0`

## 0.22.0 — 2026-09-21

### Release hardening

- Corrected plug-in parameter-ID handling for Layer D sends so those parameters do not collide with MIDI-route IDs.
- Preserved plug-in routing and MIDI configuration across prepare/reinitialization paths.
- Preserved the default all-layer MIDI route at plug-in startup.
- Corrected revision-3 output-gain migration.
- Preserved deferred patch state across prepare during the current Panic/Cut-on architecture.
- Kept Swift 6/macOS build paths explicit where needed for current toolchains.

### Regression and validation

- Added a clean Aurora v1 architecture baseline.
- Added reconstructed model/UI regression coverage based on the current v1 behavioral contract.
- Added an isolated A/B comparison regression to avoid shared-engine contamination.
- Added full rendered-audio, stress, release, and Panic auditing for all **438 current factory presets**:
  - Aurora100: 100
  - AuroraPrism100: 100
  - AuroraNova100: 100
  - AuroraGB109: 109
  - AuroraShimmer29: 29
- Kept native sanitizer coverage under ASan/UBSan and TSan.
- Kept standalone, AU, VST3, state, host-lifecycle, MIDI, and DSP validation as separate CI layers.
- Retired the historical `InterfaceChecks.swift` / `check-interface.sh` path from CI/release authority while intentionally retaining both files for regression archaeology and future troubleshooting.
- Documented the reconstruction methodology, source-of-truth hierarchy, compatibility contracts, oracle quality, and historical test classification.

### Important testing note

No production/app/DSP/plugin code was changed **as a consequence of the test reconstruction/reverse-engineering work**. Historical tests were treated as evidence, not authority over superseded architecture. Where old assertions no longer matched the working product, the test contract was reconstructed around current intended behavior, architecture, compatibility rules, and independent invariants.

### Version metadata

- Git tag: `v0.22`
- Standalone marketing version: `0.22.0`
- Standalone build: `28`
- AU/VST3 marketing version: `0.22.0`

## Earlier releases

Earlier 0.21.x and older release notes remain documented in `README.md` and the repository tag history.
