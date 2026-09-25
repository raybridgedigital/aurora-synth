# Changelog

## 0.26.1 — 2026-09-25

### Clicks and crackle (from the first play-test of 0.26.0)

- **Declicked voice envelopes.** Voice gain now passes through two 0.7 ms one-pole stages, so a fast linear attack no longer clicks where it turns into the decay. On a pure tone (Sub Marine, 4 ms attack) the note-on click fell from -44 dB to -74 dB relative to the note, and note-off clicks by about 10 dB. Very short percussive spikes (3 ms attack into a 50 ms decay) peak about 1 dB lower.
- **Click-free voice stealing.** When all 64 voices are busy, the stolen voice keeps rendering its real waveform through a 6 ms S-curve fade in one of 16 ghost slots (capped at 32 oscillator lanes) instead of being replaced by its frozen last sample. On a held 64-voice sine chord, steal clicks fell from +42 dB to +16 dB over the chord's own treble.
- **Clean Output-boost limiter.** The previous limiter took its gain from each sample's own peak, so every sample above the ceiling was clamped: hard clipping, heard as crackle on loud chords. The new one follows a 25 ms peak hold with a 1 ms attack and 150 ms release, and a soft knee that never exceeds 0.98. A loud chord at +18 dB: 5th harmonic -39.9 dB → -54 dB. Black Moss with a full voice pool at +12.3 dB: 1,905 → 23 samples near full scale. At 0 dB boost the output is unchanged.
- Cost of all three on the heaviest Dual Patch load: 33.0% → 33.8% of the 128-frame budget (within measurement noise).

### Dropout indicator

- The count uses the DSP readout's colour and stays after the first dropout until you click it; clicking clears it to zero. The red triangle blinks five times a second while dropouts are happening, stays lit for five seconds after the last one, then hides — so a dropout you missed still leaves its number behind.

### Sound design guide

- PATCH-DESIGN-RULES rule 9 explains what caused the clicks (pure tones expose envelope corners, voices add up into the limiter, pedal + long release fills the pool, sub-bass below the rig's range) and how to design around them.
- PATCH-DESIGN-RULES rule 3: AI (and anyone else designing sounds) uses one or two layers only — layer A, or A + B. Layers C and D are reserved for the owner.

### Build

- GitHub CI runs on `macos-26` with Xcode 26.6 instead of the deprecated `macos-14` image. Its Xcode 15.4 could not type-check the FM envelope mini-curve in time, which failed the Product Smoke, Baseline and Specialized Regression workflows on every push since 0.25.0. The app code is unchanged; the CI now matches the toolchain KiMiA is built with.
- `scripts/build.sh` signs the app again if iCloud Drive re-tags the bundle during signing (seen on a synced Desktop folder).

## 0.26.0 — 2026-09-25

### Real-time DSP (gig reliability)

- **Effects bypass frees DSP.** A switched-off effect fades out over 20 ms and then does no processing at all. Previously a switched-off Reverb re-cleared its 576 KB of rings on every sample — 27.7% of the 128-frame budget at 44.1 kHz with nothing playing, against 1% with the Reverb on — and Shimmer, Delay, Compressor and the chorus line kept running while off. With nothing playing: all ten effects off 27.7% → 0.34%; shipping default (Delay + Reverb) 1.05% → 0.49%.
- **No stale audio, no clicks when switching.** A switched-off effect's memory is wiped in small slices over the next blocks (no large clear on the audio thread) and it only reopens once clean, so audio recorded before the bypass never returns. Delay-line effects also fade what they record, which removes re-enable clicks that 0.25.0 had on the flanger, phaser and the first repeat of a delay. The auto-wah keeps filtering until its Mix has faded, so pulling Mix down quickly no longer cuts the wet signal off in one step.
- **Faster voices, identical sound.** Per-sample math that could not change the result is skipped or hoisted (exp2 of zero, the sub-oscillator sine at level 0, the wheel-vibrato sine at rest, tanh of the Character gain per unison lane, per-voice LFO shaping, FM operator ordering). All 55 factory patches, 19 Dual Patch pairs, the 60 GB109 sounds and 96 FM variants render bit-identical.
- **Silent pedal-held voices are freed.** A poly note with sustain 0 that has fully decayed under the key or pedal releases its voice. Pedalled pianos, plucks and FM EPs no longer fill the 64-voice pool with silence or steal audible notes. Mono/legato layers are unchanged. Quiet release tails also stop updating filter coefficients every sample (differences ≤ 1.4e-6).
- Measured on an M3 MacBook Air, 44.1 kHz/128 frames, 8-bar passage with the pedal held: Stage Cedar 22% → 6% of the audio budget, Tine Stage 76 22% → 8%, Glass Twelve 27% → 4%, Stab Alley 54% → 1.4%.
- New engine tests: `trueBypass` (clean re-enable, rapid toggling, click-free switching per effect), `bypassCost` (switched-off effects must cost under half of switched-on ones; skipped under sanitizers) and `silentVoiceRelease`.

### Stage safety

- **Matrix screen crash fixed.** Since 0.25.0 the Matrix screen draws ten Performance Matrix rows, but every factory patch stores six, so loading a factory sound and opening Matrix crashed the app (and the plug-in editor). Six-row matrices are now padded to ten everywhere, which also stops slots 7–10 of the previous patch staying active in the engine.
- **Dropout counter.** Next to "DSP … Voices …" the header now shows a red warning with the number of Core Audio dropouts since audio started — each one an audible click. The smoothed DSP figure can sit well below 100% while cycles are already being dropped (825 dropouts in 27 s at an 82% average in the reconstructed 24 September gig). Restarting audio resets the count.

### Factory library

- KiMiA ships one bank: `Resources/AuroraFX.json` (55 patches, 1–2 layers each). The library lists categories in the bank's keyboard-first order and the default sound is its first patch (Felt & Timber). The startup notice "A factory sound bank could not be loaded", which appeared on every launch once the legacy banks had been emptied, is gone.
- Retired banks are archived, not deleted: Spectrum 300, Aurora 100, Prism 100, Nova 100, Shimmer 29, GB109 and the reference pair (765 patches, as shipped in 0.25.0) with their catalogs, the Nova generators, the Spectrum audit and the patch recipes now live in `archive/`. A session saved on a retired sound starts on the default sound; user presets are never touched. Archived banks can be imported into Your sounds.
- Build, plug-in resources, CI (factory audio audit now runs on AuroraFX) and the baseline, specialized-regression and plug-in checks were updated to the single bank; the classic bank generators refuse to run so the retired banks cannot be regenerated by accident.

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

- AU/VST3 source metadata and display name advanced to **KiMiA 0.25.0**, including correction of the stale `AudioComponents` version integer. The locally installed bundles remain **0.24.3**; the 0.25.0 plug-ins were not rebuilt/installed/revalidated after the final version bump. The installed 0.24.3 AU's earlier `auval` pass does not certify 0.25.0. Current v0.25.0 plug-in build CI also fails on the SwiftUI compiler type-check timeout described in `DAW-INTEGRATION.md` and `SHARED_STATE.md`.

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
- Added full rendered-audio, stress, release, and Panic auditing for all **438 then-current factory presets**:
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
