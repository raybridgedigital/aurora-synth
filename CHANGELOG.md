# Changelog

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
