# Aurora v1 Test Reconstruction Assessment

**Status:** documentation of the Aurora v1 regression reconstruction strategy  
**Date:** 2026-09-21  
**Scope:** tests, test architecture, regression authority, oracle quality, and maintenance rules  
**Production-code impact:** none

This document explains why Aurora's v1 regression suite was reconstructed, how expected behavior can be recovered safely from a working application and its current architecture, where that process is reliable, where it is not, and how future maintainers should interpret the resulting tests.

It is intended to be read together with:

- `AURORA-SPECIALIZED-REGRESSION-CONTRACT-v1.md`
- `AURORA-LEGACY-TEST-CLASSIFICATION-v1.md`

## Executive assessment

Reconstructing the Aurora test suite from the current working product, current architecture, current production code, and the intent of the historical tests was the correct recovery strategy.

The old suite had accumulated assertions that froze superseded implementation assumptions. Several of those assertions were independently shown to be stale while the application remained correct in real standalone/MainStage use.

The reconstructed suite is therefore not intended to make the current code "pass itself." Its purpose is to recover the current **behavioral contract** of Aurora v1 and protect that contract with tests that prefer observable behavior, persistence semantics, compatibility rules, DSP invariants, and real workflow outcomes over incidental implementation details.

A crucial limitation remains:

> Production code can tell us what Aurora currently does. It cannot always tell us what Aurora is supposed to do.

For that reason, not every expectation has the same authority. This document defines the source-of-truth hierarchy and an oracle-provenance model for future maintenance.

## Why reconstruction was necessary

Aurora's historical tests grew over many versions and architectures. Some tests remained valuable. Others preserved assumptions that were once valid but are no longer part of Aurora v1.

Confirmed examples include:

### Macro-center raw equality

Historical `InterfaceChecks.swift` assumed that loading a preset and reapplying all stored macro values should leave every raw parameter numerically unchanged.

That is not the current macro contract. Default macros intentionally transform controls, and custom macro definitions may be sparse.

A failure such as:

`fx-acid-knife-lead`  
layer 0, parameter 7  
expected 600  
actual approximately 937

is therefore not evidence of a production bug by itself.

### Fixed XY mappings

Historical tests assumed X and Y always targeted fixed macro indexes.

Current Aurora supports per-preset `XYSettings`, including macro assignment, range, and inversion.

### EQ stored as patch data

Historical checks treated globals 20...22 as patch FX.

Current Aurora treats those EQ controls as session-sticky house EQ, separate from patch data.

### Shared-engine A/B contamination

A historical monolithic UI regression process created multiple `SynthModel` instances that shared the standalone test engine.

That caused an apparent A/B engine failure. A fresh-process A/B test with one model and one engine proved the production A/B behavior was correct.

### Exact layer-count assumptions

Current Aurora exposes 99 layer parameters, but legacy factory data is allowed to store fewer values.

`AuroraGB109` stores parameters 0...96. Current loading supplies defaults for 97 and 98 and uses the absence of parameter 97 as the legacy arp-format marker. Parameter 23 is then migrated from the historical arp division encoding into the current one.

The old exact-count assumption therefore rejected valid legacy data.

## The correct mental model

The reconstruction should be understood as:

```text
working application
      +
current product behavior
      +
current architecture
      +
production implementation
      +
historical test intent
      +
compatibility requirements
      ↓
current Aurora v1 behavioral contract
      ↓
regression tests
```

The goal is **not**:

```text
read production code
      ↓
copy its branches into tests
      ↓
declare the implementation correct
```

That second pattern can accidentally bless a production bug and turn it into a permanent specification.

## Source-of-truth hierarchy

When reconstructing or updating Aurora tests, use the following hierarchy.

### 1. Intended user-visible behavior

The highest-level question is what Aurora is supposed to do for the musician.

Examples:

- loading a saved sound should reproduce that sound correctly;
- A/B should audition saved A without destroying edited B;
- Panic should recover to silence and zero active voices;
- Save As should create a distinct preset rather than overwrite the original;
- browsing presets should not destroy session-sticky state that is intentionally outside patch data.

### 2. Explicit architectural contracts

Use current architectural decisions as authority where they are intentional and documented.

Examples:

- patch state versus session state;
- per-preset `XYSettings`;
- Panic deferred-write/generation behavior;
- standalone-engine ownership rules;
- preset migration rules;
- plugin state ownership and lifecycle.

### 3. Compatibility and data-format contracts

Backward compatibility is a first-class source of truth.

Examples:

- legacy presets may omit newer parameters;
- missing extension parameters receive documented defaults;
- GB109 uses the legacy arp-rate migration;
- old saved sessions must remain loadable where compatibility is intentionally supported.

### 4. Formal invariants and external standards

Some expectations do not depend on Aurora's current implementation.

Examples:

- DSP output must not become NaN or infinity;
- state round-trips must preserve supported data;
- parameter IDs intended to be stable must remain stable;
- AU/VST3 host lifecycle behavior must satisfy the relevant plugin contracts;
- bounded output and valid parameter ranges must remain valid.

### 5. Current production implementation

Production code is essential for understanding exact current mechanics, edge cases, defaults, and state transitions.

It is a strong source for reconstructing **implemented contracts**, but it is not automatically proof of intended behavior.

### 6. Historical tests

Historical tests are evidence of previous risk areas and previous behavior.

They are not authority over a superseded architecture.

## Characterization versus specification tests

Two test types are intentionally present.

### Characterization tests

These answer:

> What does the current stable Aurora implementation do?

They are useful when recovering coverage around an existing working application.

They are especially useful for:

- exact migration behavior;
- current publication/coalescing behavior;
- UI geometry-sensitive behavior;
- current defaults and compatibility paths.

Characterization tests should be treated as lower-authority when their expectation is tightly coupled to implementation details.

### Specification tests

These answer:

> What must Aurora continue to do?

They are stronger and should survive internal refactoring.

Examples:

- preset encode/decode round-trip;
- malformed preset rejection;
- Save/Save As/rename/delete/restore semantics;
- A/B state preservation;
- session persistence;
- Panic recovery;
- finite audio;
- plugin state round-trip;
- undo/redo semantics;
- legacy preset compatibility.

## Oracle provenance

Every important regression expectation should ideally be traceable to one of these sources.

| Tag | Meaning | Maintenance rule |
| --- | --- | --- |
| **PRODUCT** | Explicit user-facing behavior | Change only with an intentional product decision |
| **FORMAT** | Saved-data or backward-compatibility contract | Change only with an explicit migration/versioning decision |
| **STANDARD** | External host/plugin/MIDI/etc. contract | Change only when the applicable standard or integration contract changes |
| **INVARIANT** | Safety, mathematical, range, or DSP invariant | Treat as highly stable |
| **ARCHITECTURE** | Intentional Aurora internal contract | Change only with an explicit architecture change |
| **CHARACTERIZE** | Current implementation behavior | Reassess if implementation changes while user-visible behavior remains correct |

Future test documentation should use these tags where practical.

## Assessment of the reconstructed suite

### High-confidence behavioral oracles

The following areas have strong independent expectations and are suitable as durable release-protection tests:

- preset serialization and authored-data round-trip;
- malformed preset rejection;
- Save, update, Save As, rename, delete, restore;
- undo/redo behavior;
- session persistence;
- A/B audition and edited-B preservation;
- editing while comparing exits comparison correctly;
- patch state versus session-sticky state;
- finite DSP output;
- bounded output;
- non-silent factory audition;
- voice cleanup;
- Panic recovery;
- plugin state round-trip;
- plugin lifecycle behavior;
- sample-offset MIDI behavior;
- supported 32/64-bit plugin processing;
- stable parameter IDs where intentionally stable.

These expectations do not need to be justified by copying the implementation. They describe observable or compatibility-level behavior.

### Strong but architecture-dependent expectations

These are legitimate contracts, but their exact values come from Aurora architecture or historical compatibility rules:

- output-gain migration by saved-state revision;
- legacy extension-parameter defaults;
- GB109 missing-parameter handling;
- legacy arp-rate migration;
- matrix dimensions and ownership;
- session EQ separation;
- current default values for newly added controls;
- current parameter count and legal ranges.

These should be documented as **ARCHITECTURE** or **FORMAT** rules so they do not become unexplained magic constants.

### Useful characterization expectations

Some checks are valuable regression detectors but are more implementation-shaped.

Examples currently include:

- exact XY pointer/coalescing geometry outcomes;
- exact scope display normalization bounds such as the current 0.821 ceiling;
- exact publication-count behavior;
- certain precise UI timing/coalescing assumptions.

These tests are not wrong. They should simply be recognized as **CHARACTERIZE** tests.

If a future refactor changes one of these values while the intended UX remains correct, the test should be reviewed rather than production being changed automatically to satisfy it.

## Factory audio audit assessment

`Tests/V1FactoryAudioAudit.mm` is stronger than a model-only self-consistency test because it independently drives the DSP engine and evaluates rendered audio.

For every current factory preset it performs, in broad terms:

```text
load current or legacy patch data
→ apply current migration semantics
→ render a held audition
→ render release
→ check finite output / RMS / peak / voice behavior
→ stress with eight notes at velocity 127
→ Panic
→ render through Panic recovery
→ verify cleanup
```

The audit covers:

- Aurora100: 100
- AuroraPrism100: 100
- AuroraNova100: 100
- AuroraGB109: 109
- AuroraShimmer29: 29

Total: **438 factory sounds**.

This provides independent behavioral evidence because the final oracle is not simply "did `SynthModel.sanitized` return the same values?" The oracle includes actual audio, boundedness, useful signal, stress behavior, release behavior, and Panic recovery.

### Important maintenance note

The factory audit intentionally duplicates certain migration/default rules instead of calling `SynthModel.sanitized` and declaring success.

That independence is useful, but it creates a maintenance responsibility.

The duplicated defaults and legacy mappings must be treated as **versioned FORMAT/ARCHITECTURE contracts**. If an intentional migration rule changes, the contract documentation and both implementations must be updated together.

Otherwise the duplicated values can become the next generation of stale test assumptions.

## GB109 compatibility contract

GB109 is intentionally an older-format factory bank.

Current behavior is:

- stored layer parameters: 0...96;
- parameter 97 defaults to 0;
- parameter 98 defaults to 0;
- absence of parameter 97 identifies the legacy arp format;
- old parameter 23 arp-rate values migrate as:
  - 0 → 0
  - 1 → 1
  - 2 → 3
  - 3 → 5

Parameters 97 and 98 represent the newer Arp Swing and Arp Velocity Shape controls.

The reconstructed factory audit mirrors this compatibility contract.

This is an example of a case where reverse engineering is appropriate because the expected behavior is supported by current loader architecture, compatibility intent, and successful real rendering, not merely by a historical assertion.

## Macro and XY assessment

The historical macro test was too implementation-specific because it required raw-parameter equality after macro application.

The reconstructed contract is healthier:

- factory presets must satisfy the current schema;
- authored preset data must round-trip;
- every macro must be able to reach 0 and 1 without producing an invalid patch;
- XY behavior must use the preset's effective `XYSettings`;
- sparse custom macro definitions are valid.

This protects the current behavior without demanding that all internal raw parameters remain identical.

Future macro tests should prefer properties such as:

- intended destinations actually change;
- resulting values remain in legal ranges;
- unrelated destinations are not changed unexpectedly;
- audio remains finite;
- patch validity is preserved.

Avoid broad raw-parameter golden snapshots unless a particular raw value is itself part of an intentional public or compatibility contract.

## A/B assessment

A/B engine behavior is intentionally isolated into a fresh process.

The durable contract is:

```text
load saved sound
→ edit parameter
→ switch to saved A
→ engine auditions saved value
→ edited B model state is retained
→ return to B
→ engine restores edited value
→ B persists
→ editing while comparing exits comparison correctly
```

This is a strong PRODUCT/ARCHITECTURE oracle.

The previous monolithic multi-model failure was test contamination caused by shared standalone engine state, not evidence of a production defect.

## Native and plugin tests

The native specialized tests remain valuable and should not be discarded merely because the model/UI suite was reconstructed.

They cover areas including:

- recording/WAV normalization;
- wavetable generation/import;
- phase/warp;
- concurrency;
- motion;
- layer sends;
- solo;
- dual filters;
- oscillator modulation;
- character processing;
- LFO refinements;
- MIDI ownership/routing;
- transpose;
- arp;
- matrices;
- FX;
- mono/legato/glide;
- queue recovery.

Plugin validation remains separate from model/UI regression and covers areas including:

- stable parameter IDs;
- state round-trip;
- finite audio;
- host lifecycle;
- sample-offset MIDI;
- 32/64-bit processing;
- editor attachment.

Keeping these layers separate reduces cross-contamination and makes failures easier to interpret.

## Known weak spots to review carefully in the future

The reconstructed suite is substantially healthier than the old monolithic regression, but it is not immune to test drift.

Future maintainers should pay particular attention to:

1. **Exact UI geometry values**  
   These can become stale after harmless layout changes.

2. **Exact display-normalization constants**  
   Keep them only if they correspond to an intentional visual contract.

3. **Exact publication/coalescing counts**  
   These may represent performance architecture rather than user-visible behavior.

4. **Duplicated migration/default tables**  
   These are useful independent oracles only when explicitly versioned and documented.

5. **Implementation-derived branch fixtures**  
   If a test simply copies every branch of a production function, confirm that the branch values represent an intentional contract.

## The anti-self-fulfilling-test rule

Before freezing a reconstructed expectation, ask:

> If production contained a bug today, would this test accidentally bless that bug?

If the answer is yes, obtain a second source of truth.

Acceptable second sources include:

- explicit product behavior;
- an architectural decision;
- a compatibility/data-format requirement;
- a known-good historical release;
- an external plugin/MIDI/host standard;
- a mathematical or DSP invariant;
- a real standalone/MainStage workflow;
- an explicit product-owner decision.

## Recommended maintenance workflow

For every future failing regression:

```text
failure
  ↓
identify oracle provenance
  ↓
is this PRODUCT / FORMAT / STANDARD / INVARIANT?
  ├─ yes → investigate production first
  └─ no
      ↓
is this ARCHITECTURE?
      ├─ yes → determine whether architecture intentionally changed
      └─ no / CHARACTERIZE
          ↓
compare intended user behavior with current implementation
          ↓
update the test if the old implementation assumption is obsolete
```

Do not change production code merely to turn a historical red check green.

If a genuine new production bug is proven, document its user-facing impact before changing production.

## CI authority for Aurora v1

The intended clean v1 regression structure is:

1. **Aurora v1 Baseline**  
   Architectural and foundational contracts.

2. **Native Sanitizers**  
   Retained native DSP/regression coverage under ASan/UBSan and TSan.

3. **Aurora v1 Specialized Regression**  
   Reconstructed model/UI workflows, isolated A/B behavior, and current factory-bank audio audits.

4. **Product/plugin validation**  
   Standalone build plus AU/VST3 build and host validation.

The historical `InterfaceChecks.swift` suite remains useful as regression archaeology, but its obsolete assertions must not override the current v1 contract.

It should remain retained until explicit retirement is authorized.

## Definition of a genuine production bug

A regression failure should be treated as evidence of a production bug only when the failing expectation is supported by an independent source of truth.

Strong examples:

- NaN/Inf audio;
- broken preset persistence;
- incorrect state round-trip;
- real A/B data loss;
- Panic fails to recover;
- valid legacy data no longer loads;
- a supported plugin host lifecycle breaks;
- a user-visible workflow no longer behaves according to the documented product contract.

A disagreement with a stale historical implementation assumption is not sufficient.

## Decision record

For Aurora v1:

- production/app code is not changed merely to satisfy stale tests;
- historical tests are preserved until explicitly retired;
- current product behavior and intentional architecture are authoritative;
- old tests are mined for risk areas and intent;
- reconstructed tests prefer observable behavior over internal representation;
- compatibility rules are treated as versioned contracts;
- implementation-shaped checks are marked conceptually as characterization tests;
- future test expectations should document their oracle provenance.

## Bottom line

The reconstruction strategy is technically sound and appropriate for Aurora's situation.

A large portion of expected behavior can be recovered reliably from the working product, current architecture, production code, persistence formats, DSP invariants, plugin contracts, and historical intent.

What cannot be recovered safely from code alone is product intent that is not otherwise documented, especially musical taste, subjective UX quality, and whether a particular sonic transformation is artistically desirable.

The safest long-term rule is:

> Recover the **behavioral contract**, not the historical implementation.

That principle should govern Aurora v1 test maintenance going forward.
