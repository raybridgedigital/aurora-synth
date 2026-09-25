# Aurora Spectrum verification

The bank contains exactly 300 unique factory sounds: 30 in each category, with 240 four-layer and 60 three-layer performances. Saved user sounds remain separate.

## Audio checks

All 300 sounds passed offline rendering through the actual plug-in core at 48 kHz, Master 100%, Output boost +24 dB:

- Category-appropriate notes and chords; repeated phrases for plucks.
- Finite output and calibrated level bounds.
- Note release and Panic clearing.
- Eight-note, maximum-velocity stress rendering with peak protection.
- Both endpoints of all eight macros (4,800 endpoint renders), with non-silent, finite output.

These are automated measurements, not a claim of listening to every sound. Levels below are phrase RMS, not perceived-loudness or speaker-SPL measurements.

| Category | Lowest RMS | Average RMS | Highest RMS |
|---|---:|---:|---:|
| Pads | -21.2 dBFS | -17.1 dBFS | -15.5 dBFS |
| Bass | -15.0 dBFS | -15.0 dBFS | -15.0 dBFS |
| Leads | -18.3 dBFS | -15.2 dBFS | -15.0 dBFS |
| Keys | -20.0 dBFS | -16.4 dBFS | -16.0 dBFS |
| Plucks | -22.4 dBFS | -18.7 dBFS | -16.0 dBFS |
| Arps | -17.2 dBFS | -16.1 dBFS | -16.0 dBFS |
| Textures | -20.0 dBFS | -19.0 dBFS | -18.0 dBFS |
| Organs | -16.0 dBFS | -15.9 dBFS | -14.6 dBFS |
| Brass & Strings | -16.0 dBFS | -16.0 dBFS | -16.0 dBFS |
| Splits | -16.0 dBFS | -16.0 dBFS | -16.0 dBFS |

## Integration checks

- Native interface regression checks passed, including all 300 presets, centered macros, serialization, undo/redo, comparison, layer tools and XY.
- Plug-in core state round-trips passed for 300 factory sounds and two separate reference fixtures.
- VST3 validator: 47 passed, zero failed.
- Native host checks: timestamped MIDI, closed-editor XY automation, state recall, 64-bit offline rendering and editor lifecycle passed.
- Apple Audio Unit validation passed.
- Standalone, installed VST3 and installed AU resource banks match byte-for-byte.
- User flags visually verified in the sound selector; the shared badge is also present in sidebar rows.

Detailed audio results: `build/spectrum-audit.json`. Reproduce with `bash scripts/audit_patch_bank.sh`.
