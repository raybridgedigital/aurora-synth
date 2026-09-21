# FUTURE PROPOSAL — Modulation Expansion

> **STATUS: PROPOSAL ONLY — DO NOT IMPLEMENT YET**
>
> This document records a possible future Aurora modulation upgrade. The design is intentionally parked for later evaluation.
>
> **Decision gate:** revisit only after Aurora v0.22 has been used extensively in real-world standalone/DAW/live-performance conditions and the existing engine's overall performance, usability, and sound-design limits are better understood.
>
> This is **not** an active roadmap commitment and should not trigger production-code changes by itself.

## Why this proposal exists

Aurora already has a strong modulation system: two per-layer LFOs, Amp and Mod envelopes, per-note random, key tracking, Motion Envelope, Sound Matrix, and Performance Matrix.

The proposed upgrade is intended to add genuinely useful independent movement without turning Aurora into a dense modular synth or adding features merely for specification-sheet value.

The intended product model remains:

- **Motion = deliberate drawn evolution**
- **LFOs = repeating movement**
- **Envelopes = note dynamics**
- **Matrix = flexible routing**

---

# 1. Scope

The proposal consists of:

1. Expanding the Sound Matrix destination set.
2. Expanding the Sound Matrix from 6 to 10 slots per layer.
3. Adding LFO 3, LFO 4 and LFO 5 as Matrix-only modulation sources.
4. Keeping LFO 1 and LFO 2 fully backward-compatible with their current direct routing.
5. Keeping Motion Envelope separate from the Matrix.
6. Preserving all existing presets, plugin automation, and sound behavior.

The upgrade should increase real-world sound-design capability rather than merely increase feature count.

---

# 2. Backward compatibility

Backward compatibility is a hard requirement.

All existing Aurora v0.22 presets must:

- load successfully;
- retain existing parameter values;
- retain existing Sound Matrix assignments;
- retain existing Performance Matrix assignments;
- retain existing LFO 1/2 behavior;
- retain existing Motion behavior;
- retain existing plugin automation;
- require no manual migration;
- produce the same intended sound.

Do not renumber existing:

- parameter IDs;
- Matrix source IDs;
- Matrix destination IDs;
- AU parameter IDs;
- VST3 parameter IDs.

New IDs must be appended.

Existing factory banks must not be rewritten simply to support the new architecture.

---

# 3. LFO 1 and LFO 2

LFO 1 and LFO 2 retain their complete existing behavior:

- Shape
- Destination
- Depth
- Free Hz / Tempo Sync
- Rate
- Division
- Free-run / Retrigger
- Phase
- Delay
- Fade In

Their existing direct routing remains permanently supported.

No existing preset should need conversion.

## Recommended advanced Matrix workflow

LFO 1 and LFO 2 also continue to work as Sound Matrix sources.

When direct LFO Depth is set to 0:

- the direct Destination path contributes no modulation;
- the LFO still runs normally;
- its raw modulation signal remains available to the Sound Matrix;
- Matrix Amount controls modulation depth and polarity.

User-facing documentation should explicitly encourage this workflow for advanced routing:

> **Advanced routing:** set LFO Depth to 0 and route the LFO through the Sound Matrix. The LFO continues running normally while Matrix Amount controls modulation depth and polarity.

The existing direct routing remains the faster/simple workflow.

---

# 4. LFO 3, LFO 4 and LFO 5

Add three additional LFOs per layer.

These are **Matrix-only modulation sources**.

They provide:

- Shape
- Free Hz / Tempo Sync
- Rate
- Tempo Division
- Free-run / Retrigger
- Phase
- Delay
- Fade In

Shapes:

- Sine
- Triangle
- Saw
- Square
- Random

They do **not** have:

- Destination
- Depth

Their routing model is:

**LFO → Sound Matrix → Destination**

Matrix Amount controls modulation depth and polarity.

---

# 5. LFO implementation

LFO 3–5 should use the same timing behavior and DSP semantics as LFO 1/2.

Where practical, generalize the engine around a five-LFO model rather than implementing three unrelated duplicate code paths.

Each LFO must have independent:

- phase state;
- retrigger state;
- random waveform state;
- delay state;
- fade state.

Random LFOs must not accidentally share random sequences.

---

# 6. LFO performance optimization

LFO 3–5 should not perform unnecessary DSP work when unused.

If a new LFO has no active Sound Matrix route, avoid calculating its per-sample modulation in the hot audio path where practical.

Recommended implementation:

- determine active LFO usage outside the hottest DSP path;
- maintain lightweight active-route masks or equivalent prepared state;
- avoid heap allocation in the audio thread;
- avoid locks in the audio thread;
- preserve Aurora's current real-time-safe architecture.

Unused additional LFOs should have essentially negligible CPU cost.

---

# 7. Sound Matrix sources

Existing source IDs remain unchanged:

| ID | Source |
|---:|---|
| 0 | LFO 1 |
| 1 | LFO 2 |
| 2 | Amp Envelope |
| 3 | Mod Envelope |
| 4 | Key Tracking |
| 5 | Per-note Random |

Append:

| ID | New source |
|---:|---|
| 6 | LFO 3 |
| 7 | LFO 4 |
| 8 | LFO 5 |

Motion Envelope is **not** a Matrix source.

Preferred visual order:

**LFO 1 · LFO 2 · LFO 3 · LFO 4 · LFO 5 · Amp Envelope · Mod Envelope · Key Tracking · Random**

Visual order does not need to match internal numeric IDs.

---

# 8. Matrix runtime encoding

The current runtime Matrix packing only allows the existing source range.

Because the Sound Matrix would now have 9 sources:

- expand source storage to at least **4 bits**.

Because the destination count is increasing:

- allocate **6 bits** for destination IDs.

This allows up to 64 Matrix destination IDs without another encoding redesign.

The packed runtime representation must remain internal only and must not become the persistent preset format.

Preset compatibility remains based on serialized Matrix assignment values.

---

# 9. Sound Matrix slot count

Increase Sound Matrix capacity from:

**6 → 10 slots per layer**

With four layers this provides:

**40 Sound Matrix routes per patch**

Performance Matrix remains:

**6 slots**

Do not expand Performance Matrix as part of this proposal.

Ten Sound Matrix slots is an intentional product boundary. Do not automatically expand to 16, 24, or 32.

---

# 10. Matrix slot backward compatibility

Existing presets containing six Sound Matrix entries must load with:

- slots 1–6 preserved exactly;
- slots 7–10 automatically created as empty routes.

Do not require old preset rewriting.

New presets may save all 10 slots.

Loading code should accept both historical 6-slot and new 10-slot Sound Matrix layouts.

---

# 11. Matrix telemetry

Current live Matrix telemetry assumes:

**6 Sound Matrix slots × 4 layers + 6 Performance slots = 30 values**

Update it to:

**10 × 4 + 6 = 46 values**

Recommended mapping:

- Layer A: 0–9
- Layer B: 10–19
- Layer C: 20–29
- Layer D: 30–39
- Performance Matrix: 40–45

Telemetry is visual/UI feedback only and must not influence DSP behavior.

All Matrix activity indicators must continue working correctly.

---

# 12. Motion Envelope

Motion remains a completely separate modulation system.

It is **not** added as a Sound Matrix source.

Its conceptual purpose is different:

**Motion = deliberate drawn evolution**

In synthesis terminology, Aurora Motion is similar to an MSEG, or Multi-Stage Envelope Generator, but the product should continue using the friendlier **Motion Envelope** name.

---

# 13. Motion routing philosophy

For new sound design, Motion should conceptually favor:

**one shape → one primary destination → minimum / maximum**

Examples:

- Motion → Filter Cutoff → 400 Hz to 6 kHz
- Motion → WT Position → 15% to 90%
- Motion → Pitch → 0 to +12 semitones

This direct min/max behavior is valuable because Motion defines an explicit trajectory rather than merely adding a Matrix offset.

Motion should remain easy to understand and should not become another generic Matrix source.

---

# 14. Legacy Motion compatibility

Existing Aurora Motion supports multiple direct destinations.

That behavior must remain available internally for existing presets.

Do not alter how legacy multi-destination Motion patches render.

If a future UI simplifies Motion toward a single primary destination for new patches, historical presets containing multiple Motion routes must still:

- load;
- render correctly;
- save safely;
- retain their additional legacy routes.

Do not silently discard or rewrite legacy Motion data.

---

# 15. Existing Motion destinations

Existing Motion destinations remain compatible:

- Volume
- Filter Cutoff
- Pitch
- Pan
- Osc 1 Position
- Osc 2 Position
- Osc 1 Warp
- Osc 2 Warp

Future Motion destination expansion may reuse the continuous destination catalog where architecturally appropriate, but Motion remains separate from the Matrix.

---

# 16. Sound Matrix destinations

Preserve all existing destination IDs 0–20.

Append new destinations only.

Recommended additions:

| New ID | Destination |
|---:|---|
| 21 | Filter 1 Resonance |
| 22 | Pulse Width |
| 23 | Oscillator Detune |
| 24 | Sub Level |
| 25 | Noise Level |
| 26 | Unison Detune |
| 27 | Stereo Spread |
| 28 | Sync Tune |
| 29 | WT 1 Formant |
| 30 | WT 1 Tone |
| 31 | WT 2 Formant |
| 32 | WT 2 Tone |
| 33 | Osc Mod Ratio |
| 34 | Character Mix |
| 35 | Character Tone |
| 36 | Filter Envelope Amount |

Only add destinations whose DSP path can support smooth, bounded real-time modulation safely.

---

# 17. LFO Depth destinations

Existing destination IDs:

- 6: LFO 1 Depth
- 7: LFO 2 Depth

should become selectable from the Sound Matrix.

This enables modulation-of-modulation such as:

- LFO 3 → LFO 1 Depth
- LFO 4 → LFO 2 Depth
- Mod Envelope → LFO 1 Depth

This is an intentional feature and gives the additional LFOs significantly more real-world value.

---

# 18. Shared/global FX

Do not use per-note Sound Matrix modulators directly for global/shared FX as part of this proposal.

Shared processors include:

- Chorus
- Phaser
- Reverb
- Delay
- Shimmer

These operate at patch/global level, while Sound Matrix sources are primarily per-layer/per-note.

Do not invent an aggregation model merely to expose these destinations.

Performance Matrix global-effect behavior remains unchanged.

Global modulation can be evaluated separately in the future.

---

# 19. Discrete destinations

Do not add continuous Matrix modulation to discrete/state-changing parameters such as:

- oscillator waveform;
- filter type;
- filter slope;
- wavetable selection;
- warp mode;
- character mode;
- oscillator modulation mode;
- filter routing;
- voice mode;
- arp mode;
- arp enable;
- unison voice count.

Fast modulation of these can create clicks, unstable state changes, excessive processing, or confusing behavior.

The Matrix should primarily target continuous sound parameters.

---

# 20. Destination modulation semantics

Existing destination behavior must remain unchanged.

New destinations should generally behave as:

**effective value = base value + Matrix modulation**

followed by correct parameter bounding.

Where appropriate, modulation should respect musical scaling.

Examples:

- cutoff should behave logarithmically/perceptually;
- pitch should use semitone-related units;
- detune should use cents;
- normalized controls remain within 0...1;
- bipolar controls retain their correct range;
- ratios remain within valid ratio ranges.

Matrix modulation must never create NaN, infinity, or invalid DSP state.

---

# 21. Parameter smoothing

Any newly modulated parameter that can produce audible stepping or clicks should receive appropriate smoothing.

Particular attention should be given to:

- Resonance
- Pulse Width
- Detune
- Sync Tune
- Formant
- Tone
- Osc Mod Ratio
- Character parameters

Do not blindly smooth every parameter if doing so unnecessarily changes modulation response.

Smoothing decisions should be destination-specific.

---

# 22. LFO UI layout

Preserve the existing row:

**LFO 1 | LFO 2 | Layer Range & Balance**

Add a second equal-width row:

**LFO 3 | LFO 4 | LFO 5**

This is the primary UI reason for adding three new LFOs together rather than adding only LFO 3.

Each new LFO panel should visually match Aurora's current design.

---

# 23. LFO 3–5 panel layout

Each new panel contains:

- Shape
- Clock: Hz / Tempo
- Rate or Division
- Mode: Free-run / Retrigger
- expandable Phase · Delay · Fade

Do not show:

- Destination
- Depth

Add subtle help text:

> Route this LFO from the Sound Matrix.

The new panels should remain visually simpler than LFO 1 and LFO 2.

---

# 24. Sound Matrix UI

The Sound Matrix should display:

**10 routing rows per layer**

Source picker:

- LFO 1
- LFO 2
- LFO 3
- LFO 4
- LFO 5
- Amp Envelope
- Mod Envelope
- Key Tracking
- Per-note Random

Destination picker includes all supported continuous Sound Matrix destinations.

The Matrix should remain a single understandable routing surface, not become a modular patching environment.

---

# 25. Performance Matrix

Performance Matrix stays unchanged at:

**6 slots**

Existing sources, behavior, and global-effect routing remain unchanged except where shared infrastructure must be updated safely.

Do not expand it simply because Sound Matrix grows.

---

# 26. Plugin parameter compatibility

Existing AU/VST3 automation IDs must remain stable.

Append new LFO parameters only.

New LFO parameters must participate in:

- standalone preset saving;
- plugin state saving;
- DAW project recall;
- AU automation;
- VST3 automation;
- undo/redo;
- A/B state;
- layer copy/paste;
- preset sanitization.

Existing DAW projects must open unchanged.

---

# 27. Preset/schema revision

Increment Aurora's internal preset/schema revision when this feature is eventually implemented.

The revision should allow migration logic to distinguish:

- pre-expansion presets;
- post-expansion presets.

Old presets should not be required to physically contain new fields.

Missing new fields use defaults.

---

# 28. LFO 3–5 defaults

Recommended defaults:

- Shape: Sine
- Clock: Free Hz
- neutral/sensible default Rate
- Retrigger: consistent with Aurora's existing LFO default semantics
- Phase: 0
- Delay: 0
- Fade: 0

Because LFO 3–5 are Matrix-only, an unrouted new LFO must have no audible effect regardless of its defaults.

---

# 29. CPU and memory requirements

Memory impact should be negligible.

The primary cost is DSP evaluation of additional active LFOs.

Implementation should ensure:

- unrouted LFO 3–5 cost essentially nothing;
- empty Matrix slots cost essentially nothing;
- only active routes are processed;
- no audio-thread heap allocation;
- no audio-thread locks.

Do not assume performance is acceptable without measurement.

---

# 30. Performance benchmarking

Before and after implementation, measure at least:

## Normal patch

Typical factory patch with modest polyphony.

## Heavy modulation patch

Use:

- all four layers;
- all five LFOs where relevant;
- all 10 Sound Matrix routes active;
- Motion active;
- high polyphony;
- wavetable processing;
- filters;
- effects.

Test at:

- 44.1 kHz
- 48 kHz
- 96 kHz
- 192 kHz

Track:

- rendering time;
- CPU usage;
- underruns;
- peak voices;
- audio stability.

Target:

> Presets not using LFO 3–5 should show no meaningful performance regression.

---

# 31. Required regression tests

## Backward compatibility

Verify:

- representative v0.22 presets load unchanged;
- all factory banks remain valid;
- existing LFO 1/2 direct routing behaves unchanged;
- existing Matrix source/destination IDs retain their original meaning;
- existing Motion patches behave unchanged;
- AU/VST3 projects retain automation/state.

## LFO 3–5

For each new LFO verify:

- Sine;
- Triangle;
- Saw;
- Square;
- Random;
- free-running rate;
- tempo sync;
- all divisions;
- free-run;
- retrigger;
- phase;
- delay;
- fade;
- positive Matrix amount;
- negative Matrix amount;
- multiple destinations;
- per-note behavior;
- independent random state.

## Modulation-of-modulation

Explicitly test:

- LFO 3 → LFO 1 Depth
- LFO 4 → LFO 2 Depth
- Mod Envelope → LFO 1 Depth

Verify direct LFO routing still works, Matrix routing still works, modulation remains bounded, and output remains finite.

## Ten-slot Matrix

Verify:

- old 6-slot preset loads as 10 slots;
- slots 1–6 are preserved;
- slots 7–10 are empty;
- all 10 slots save and restore;
- undo/redo works;
- layer copy/paste includes all 10;
- plugin state preserves all 10;
- telemetry works for all 10.

## Motion

Verify legacy Motion remains correct:

- Once;
- Loop;
- free duration;
- tempo sync;
- custom points;
- curves;
- per-note behavior;
- multiple legacy destinations;
- save/load;
- undo/redo;
- layer copy/paste.

If the UI later introduces a simplified single-primary-destination workflow, it must not destroy historical multi-route Motion data.

## Destination safety

For each new destination test:

- minimum Matrix amount;
- maximum Matrix amount;
- negative modulation;
- positive modulation;
- multiple routes summed;
- correct clamping;
- finite output;
- no invalid state;
- no unexpected discontinuity.

---

# 32. Audio safety

Run relevant regression and stress tests at:

- 44.1 kHz
- 48 kHz
- 96 kHz
- 192 kHz

Verify:

- finite samples;
- no NaN;
- no infinity;
- no stuck voices;
- no Panic regression;
- proper recovery;
- sanitizer suite remains clean.

---

# 33. Factory compatibility

The existing 438-preset factory audio audit remains authoritative.

Do not modify existing factory presets merely to demonstrate the feature.

All existing banks must continue passing.

New showcase presets may be created separately only after implementation and validation.

---

# 34. Documentation

If implemented, update user-facing modulation documentation.

Clearly explain:

## LFO 1 / 2

Simple workflow:

**LFO → Destination + Depth**

Advanced workflow:

**Depth = 0 → LFO → Sound Matrix**

## LFO 3 / 4 / 5

Always:

**LFO → Sound Matrix**

## Motion

Motion is for custom drawn evolution with explicit destination ranges.

## Matrix

The Matrix is for flexible modulation routing and modulation-of-modulation.

Avoid making the documentation feel like a modular-synthesis manual.

---

# 35. Non-goals

This proposal does **not** include:

- more than 10 Sound Matrix slots;
- more than 6 Performance Matrix slots;
- additional Motion Envelopes;
- Motion as a Matrix source;
- global LFOs;
- global FX LFO modulation;
- arbitrary modular cables;
- audio-rate modulation;
- LFO waveform drawing;
- additional random generators;
- modulation of discrete switches;
- removal of LFO 1/2 direct routing;
- replacement of legacy Motion behavior.

---

# 36. Final proposed architecture

Per layer:

```text
LFO 1 ─────┐
LFO 2 ─────┤
LFO 3 ─────┤
LFO 4 ─────┤
LFO 5 ─────┤
Amp Env ───┤
Mod Env ───┤──> SOUND MATRIX ──> continuous destinations
Key Track ─┤
Random ────┘
```

Sound Matrix:

**10 slots per layer**

Performance Matrix:

**6 slots**

Motion remains separate:

```text
Custom multi-stage shape
        ↓
Direct destination
        ↓
Explicit Min / Max trajectory
```

LFO 1/2 retain their existing direct routing in parallel.

LFO 3–5 are Matrix-only.

---

# 37. Product boundary

Aurora should become significantly deeper without changing its identity.

The mental model remains:

**Motion = deliberate drawn evolution**

**LFOs = repeating movement**

**Envelopes = note dynamics**

**Matrix = flexible routing**

The proposal should only move to implementation after real-world use of the current software demonstrates that the additional modulation depth is worth the UI, compatibility, testing, and performance complexity.
