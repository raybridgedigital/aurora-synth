# Aurora v1 Test Contract

> **Current-status note (24 September 2026):** this document defines the intended baseline gates; it is not a claim that v0.25.0 currently passes them. The release's GitHub CI is red because native test links omit FM-engine symbols. See `SHARED_STATE.md`.

This suite is a clean baseline for the current Aurora architecture. It is intentionally separate from the historical regression suite.

## Authority order

Tests are derived from, in order:

1. Current intended product behavior.
2. Current public/model/DSP contracts in production code.
3. Real performance workflows: patch loading, macros/XY, layer copy/paste, MIDI, audio render, Panic, and host/plugin validation.

A test must not freeze an incidental implementation detail unless that detail is itself a supported contract.

## What this suite does not assume

- Factory presets do **not** need exactly eight custom macro definitions. `customMacros` is sparse and may contain 0...8 valid definitions.
- Re-applying a stored macro value does **not** imply every raw layer/global value remains identical. Default and custom macros are allowed to transform controls according to their current contract.
- XY does **not** universally mean Macro 1 + Macro 2. Each preset's `XYSettings` determines the two macro axes, with defaults supplied by the current model.
- UI/model tests do **not** start real-time Panic. They use deterministic model operations without an audio callback.
- Panic is not synchronous. Its current contract is fade-out -> silent wipe/commit -> fade-in.

## Baseline gates

### 1. Standalone build and root-view smoke

- Production standalone build succeeds.
- `SynthModel` initializes from an isolated temporary storage directory.
- The root `ContentView` can be hosted and laid out without a runtime trap.

### 2. Factory/preset contract

For every shipped factory preset:

- The preset satisfies `SynthModel.sanitized`.
- ID and display name are unique across the factory library.
- JSON encode/decode preserves authored data.
- Decoded data still satisfies the current schema.
- All eight macro endpoints (0 and 1), starting from the authored preset each time, leave the patch schema-valid.
- XY endpoints honor that preset's current axis assignment/range and leave the patch schema-valid.

The suite also explicitly verifies that a sparse custom-macro dictionary is valid.

### 3. Session/model workflow contract

- Patch load without real-time Panic succeeds deterministically.
- Master, output boost, and session EQ remain session-sticky across patch changes.
- Layer copy/paste carries the layer payload while keeping the resulting patch valid.
- Undo/redo restores the before/after model state.

### 4. DSP/audio contract

- Rendering produces only finite, bounded samples.
- A normal note produces audio and releases.
- Supported sample rates render safely.
- MIDI source/channel routing is honored.

### 5. Panic contract

Current architecture:

`request -> fade-out -> silent boundary -> clear voices/FX + commit deferred writes -> fade-in`

The baseline verifies:

- Parameter/global writes made after Panic are deferred during fade-out.
- Old live values remain observable before the silent boundary.
- Deferred values become live after the silent boundary.
- Pre-Panic queued events do not survive into the new generation.
- Voices are gone after Panic recovery.
- New notes work after recovery.
- `prepare()` is a valid silent hard-reset boundary and commits deferred state immediately.

### 6. Plugin gate

AU/VST3 build and host validation remain a separate product gate using the repository's existing plugin build/validator scripts. The baseline model/DSP tests do not duplicate host-SDK validation.

### 7. Sanitizers

`Tests/BaselineEngineTests.cpp` supports the same address+undefined and thread sanitizer modes as the existing native runner.

## Maintenance rule

When Aurora behavior intentionally changes, update this contract first, then update the test that represents it. Do not change production code merely to satisfy an obsolete test.
