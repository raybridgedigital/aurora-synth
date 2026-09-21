# Aurora v1 Specialized Regression Contract

This suite reconstructs Aurora's specialized regression coverage from the current working product, current production architecture, and the intent of the historical tests.

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

## Native DSP areas currently validated

The existing native suite is green under ASan/UBSan and TSan. Its behavior-level coverage remains valuable evidence for recording/WAV normalization, wavetable generation and import, motion envelopes, layer sends/solo, dual filters, oscillator modulation, character processing, LFO refinements, MIDI ownership/routing, transpose, arp, matrices, FX, mono/legato/glide and queue recovery.

Those tests remain untouched while this reconstructed suite recovers the model/UI workflows that had become unreachable behind stale factory assumptions.

## Plugin areas currently validated

Current AU/VST3 build and validation are green. Existing plugin checks cover stable parameter IDs, state round-trip, finite audio, host lifecycle, sample-offset MIDI, 32/64-bit processing and editor attachment.

## Corrected factory contract

Historical behavior incorrectly required applying stored macro values to leave every raw parameter identical and assumed fixed XY macro numbers.

Aurora v1 instead requires:
- factory presets satisfy the current schema;
- authored data round-trips;
- each macro can reach 0 and 1 while leaving a valid patch;
- XY follows each preset's effective XYSettings;
- sparse custom macro definitions are valid.

## Maintenance

When behavior intentionally changes, update this contract first and then the corresponding reconstructed test.
