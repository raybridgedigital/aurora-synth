# Changelog

## 0.25.0 — 2026-09-24

### New effects (7)

- **Flanger** — modulated comb (0.9–5 ms), quadrature stereo, feedback.
- **Tremolo** — with three modes: Tremolo (classic amp wobble), Pan (left/right sweep), Rotary (spinning-speaker warble).
- **Bitcrusher** — bit depth + sample-rate reduction for lo-fi grit.
- **Compressor** — master-bus glue before the limiter: Threshold, Ratio, Attack, Release, Makeup, Auto, with a live gain-reduction meter. Defaults to 0 dB threshold (transparent until you pull it down).
- **Auto-wah** — envelope filter (low-pass/band-pass) that follows your playing.
- **Delay ducking** — repeats step aside while you play; Duck amount + release in the Delay panel.
- All new effects default to off; parameters append after the existing globals so DAW automation IDs stay stable.

### Performance matrix

- Performance matrix grows from **6 to 10 slots** (engine already reserved slots 6–9; caps lifted, feedback buffers resized). Old presets load with the extra rows empty.

### Interface

- Effects page re-arranged: Delay is now a compact 2-column panel (Shimmer-style pairs) with **Compressor beside it**; Chorus/Phaser/Reverb on their own row; Flanger/Tremolo/Bitcrusher/Auto-wah below.

### Performance (patch browser scrolling)

- Safari-class scroll smoothness (P1–P4): row tracking moved off the global model (debounced), patch list filter+sort memoized, per-frame preference churn reduced to a single reader, and telemetry pauses during active scrolling (meters freeze mid-scroll, resume on release).

### Plugins

- AU/VST3 rebuilt: display name **KiMiA**, version 0.25.0, corrected stale AudioComponents version integer so hosts register the update. `auval` passes.

## 0.24.3 — 2026-09-24

### Electric-piano behavior fix

- The pure FM EPs now **decay naturally like real pianos** instead of holding a pad-like sustain while keys are held (DX7 practice: op sustain level L3=0, tail rate on stage 3). Applies to the 5 v0.24.2 EPs plus **Rhodes Hybrid**, **Glass House EP**, **Glass Marimba** (fast woody bar decay), and **Nylon Harp** (~1.4 s string cascade) — the latter three were hybrids whose extra subtractive layers were sustaining under the FM layer; they are now pure single-layer FM. Regression assert: pure-flag patches must have L3=0 on every operator.

### New sounds

- New **FM EP** category — all 12 electric-piano patches now live there (DX Tine Classic, Suitcase 77, Stage Bark, Glass Hammer EP, Midnight Tine, Rhodes Hybrid, Glass House EP, plus the five below).
- Five more strictly-pure **DX7 …** electric pianos (no pad/texture/brass/string mixed in — layering is done via dual-patch): **DX7 E.Piano 1**, **DX7 E.Piano 2**, **DX7 Hard Tine**, **DX7 Mellow Tine**, **DX7 Bell Piano**. Factory bank grows to **125 patches** (FM EP: 12, FM: 13).

### Favorites

- New standard gold-ring **★ star favorite button** in the patch header next to **Save** / **Save As…** — tap to favorite the current patch.
- The **Save As…** dialog now has an **"Add to favorites"** star toggle: save and star in one step (confirmation: "Saved … Added to favorites.").

## 0.24.2 — 2026-09-24

### New sounds

- Five new pure DX7-style FM electric pianos (single FM layer, velocity→index on slot 2): **DX Tine Classic**, **Suitcase 77**, **Stage Bark**, **Glass Hammer EP**, **Midnight Tine**. Factory bank grows to 120 patches (FM category now 20).

### Rebrand

- The app is now **KiMiA**: sidebar wordmark (with mirrored wave icons, centered), window title, menu bar/Dock name, library collection picker, VoiceOver label, and the AU plugin display name ("Ray Bridge Digital: KiMiA" — visible after the next plugin rebuild). Internal identifiers, AU subtype, and file/folder names are unchanged, so DAW projects, presets, and settings keep working.

### Version metadata

- App 0.24.2 (build 35); Audio Unit 0.24.2.

## 0.24.1 — 2026-09-23

### Fixes

- Matrix slot number "10" no longer wraps onto two lines: the slot-number column in the Sound and Performance Matrices is wider (22pt) with monospaced digits and a single-line limit.
- Previous/next patch arrows now step alphabetically within the current patch's category (e.g. FM → next FM patch) instead of across the whole library, in both the header arrows and the Patch Browser arrows/keyboard shortcuts. Falls back to the full library when no same-category patch exists; an explicit browser category filter still wins.
- Performance Matrix row layout: the source dropdown is now the same width as the Sound Matrix's and the 65pt dead spacer is gone, so the → arrow sits right after the dropdown and aligns with the Sound Matrix rows. The CC-number field appears inline only when the source is "MIDI CC".

### Version metadata

- Git tag: `v0.24.1`
- Standalone marketing version: `0.24.1`
- Standalone build: `34`
- AU/VST3 marketing version: `0.24.1`

## 0.23.3 — 2026-09-22

### Fixes

- VST3 host automation now exposes the full 37-parameter global range (was 15): delay-sync, EQ, and the complete shimmer return block appear in the host automation list. Output gain stays on its dedicated path and tempo stays read-only. Existing parameter IDs are unchanged, so saved host automation keeps working.

### Version metadata

- Git tag: `v0.23.3`
- Standalone marketing version: `0.23.3`
- Standalone build: `32`
- AU/VST3 marketing version: `0.23.3`

## 0.23.2 — 2026-09-22

### Fixes

- Plug-in global handling now covers the full 37-parameter range (was 15): delay-sync, EQ, and the complete shimmer return block recall through patch load, state restore, MIDI Learn, and automation. Output gain stays managed via its dedicated revision path.
- `restoreState` reads the saved output boost even when the revision field is missing; only rev-3 +24 dB reference sessions migrate to +9 dB.
- `V1FactoryAudioAudit` accepts 6- or 10-slot Sound Matrices, matching `PatchBankAudit` and the engine.

### Version metadata

- Git tag: `v0.23.2`
- Standalone marketing version: `0.23.2`
- Standalone build: `31`
- AU/VST3 marketing version: `0.23.2`

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
