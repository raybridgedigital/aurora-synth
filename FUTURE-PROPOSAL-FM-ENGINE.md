# FUTURE-PROPOSAL-FM-ENGINE — Advanced FM Engine (Stage 4)

**Status: ✅ SHIPPED in v0.24.0 — design history.** The locked v1.0 design was owner-approved on 23 September 2026 and Phases 1–4 shipped in the v0.24.0 release. Later releases expanded and refined the FM EP library. This document is retained as the implementation contract and decision history; `CHANGELOG.md` and `README.md` are the current release authority. The optional full-library wipe/re-baseline remains deferred and owner-triggered. Dual-patch remains separately locked and not implemented.

**Original proposal status at lock time:** code was frozen pending named phase unfreezes, and FM was queue position #1. Those statements below describe the proposal as it stood on 23 September 2026, not the current project queue.

## Standing owner directives (v0.2 rulings)

- **Zero backward compatibility.** Wipe planned eventually; design fully unconstrained by the old format. **Owner re-affirmation (23 Sep, later message):** *"sacrifice all backward compatibility against excellent new features… most of old patches are crap… if it's bad just delete it"* — no compat shims will ever be added; old binaries reading FM patches may render them as plain subtractive (accepted, see decision log).
- **Wipe timing: deferred, owner-triggered.** Current patches stay. Owner: *"Bad patches are better than nothing — an empty synth is unacceptable."* Leaving them has zero effect on FM work: JSON is inert data read at load; patches without the new `fm` section simply load engine mode `Subtractive`.
- **Testing / CI / compliance: out of scope.** Red CI accepted; re-baseline later.
- **Hardware validation: out of scope** for this work; stability confidence assumed.
- North star: DX7-class electric piano = life blood; Aurora must stand alone as sound source on any MIDI controller.
- Original focus: **FM engine + the 15 flagship FM patches** — the great new feature. EP-ish re-authors / ` (OLD)` pairs = **optional side quest, AI's call** (owner, 23 Sep: *"trivial… I don't give a shit about the old ones"*); pairs ride along only if re-authors happen. At that time Scroll P1–P4 and dual-patch were parked; scroll later shipped in v0.25.0, while dual-patch remains parked.

## 1. Why

At proposal time, the engine could not reach DX-class EPs: it had no inharmonic operator ratios beyond 2-op oscillator modulation, no independent per-operator harmonic decay, and no per-operator feedback. Velocity was only a Performance Matrix source (`AuroraApp.swift:1844` at the time). FM closed all four natively and is historically the electric-piano method.

## 2. Goals / Non-goals

**Goals:** authentic DX tine/glass/Wurli/felt EPs · velocity→index as first-class touch · beyond-DX7 quality-of-life · full integration with Aurora's per-layer chain (filters → Character → FX → matrix → macros) · FM patch library (15 flagship + EP-ish A/B pairs) shipped in a dedicated **FM category**.
**Non-goals:** sampler/granular · MPE · preserving old patches (wipe declared) · replacing the subtractive engine (coexistence per layer) · test/CI updates (deferred) · hardware validation.

## 3. Architecture — DECIDED: Option A (per-layer engine mode)

Each layer gains engine mode `Subtractive | FM`. **Per-layer (owner-confirmed): algorithm, feedback and pitch envelope are stored — and sound — per layer**; two layers can run two different algorithms. In FM mode the four operators replace Osc1/Osc2; **the sub-oscillator and noise remain available beneath** (owner-confirmed — hammer/felt strike realism, low-end body). The layer's filters, Character, matrix, LFOs 1–5, sends, arp and macros work unchanged. DSP core: new `FmEngine.hpp/.cpp` beside `SynthEngine.cpp` (C++ `double` phase accumulators, denormal guards, high-res sine table, key-sync modes). Wavetable-modulator storage reuses `Wavetable.hpp`. Swift bridge via `AuroraBridge.h`.

## 4. Algorithms — DECIDED: 16 for v1

Candidate family split (refine during Phase 1): 4 single-carrier chains · 5 two-carrier pairs (the EP home) · 4 stacked/additive-ish · 3 feedback-forward. All named + diagrammed (spec: *"visual algorithms"*). Feedback attaches to the algorithm-defined operator (DX convention).

## 5. Parameter tables (v1)

**Per operator ×4:** Wave (Sine · Triangle · Saw · Pulse · **Wavetable** with table/position/warp) · Level (modulator = index / carrier = amplitude) · Ratio 0.25×–16× or fixed-freq 1 Hz–20 kHz · Ratio fine ±100¢ · Key scale (Off/Low/Even/Odd) · Velocity sense 0–100% (carrier→level, modulator→index) · Feedback (designated ops) · Key sync · Pan *(v1.1 candidate)*.
**Operator envelope ×4:** Rate/Level mode default (4 rates + 4 levels — the independent harmonic-decay curve; fast index collapse = tine bark); ADSR alternate; velocity→env amount; tempo-synced rates optional.
**Envelope labor split (designer rule):** operator envelopes = timbre evolution (modulator→index, carrier→its own amplitude curve, DX-accurate); layer Amp Env = the note's overall loudness shape.
**Global per layer:** algorithm select · **single feedback amount** routed to the algorithm's designated operator (DX model; per-operator feedback = v1.1) · **dedicated pitch envelope** (amount, time, curve) — DECIDED · carrier mix · FM drive-into existing filters/Character · per-layer FM out.
**No dedicated FM LFO** — Aurora's 5 layer LFOs + matrix exceed a DX7 already.
**DSP defaults:** per-sample processing with 1-sample feedback delay (DX lineage) · fixed 2× oversampling on the modulator chain (alias control, no user param) · denormal guards.

## 6. Matrix & modulation — DECIDED

New destinations (~12): Op1–4 index/level, feedback amount, ratio fine, carrier mix, pitch-env amount, WT-modulator position/warp (matrix 37→~49). **Velocity promoted permanently into `soundSources`.** Channel pressure per spec `:109` routes to index, bounded. Existing macros/macro-routes target `{layer, parameter}` natively.

## 7. Patch format

Verified schema: a patch = `"layers": [ { "values": { … } } ×4 ]` plus top-level `fx` / `soundMatrix` / `sends` / etc. The FM payload lives **inside each layer object**, sibling of `values` (per-layer, owner-confirmed):

`"layers": [ { "values": {…}, "fm": { "enabled", "algorithm", "ops": { "0..3": { wave, ratio, level, env {rates, levels}, vel, … } }, "feedback", "pitchEnv" } }, … ]`

A layer with no `fm` key ⇒ engine mode `Subtractive` (load-time default, not compat — erased entirely at future wipe).

## 8. The 15 new FM patches — category "FM"

- **Every one gets `"category": "FM"`.** Verified mechanics: `libraryGroups` groups the browser by category, the category dropdown filters on it, and search matches name+category+detail (`AuroraApp.swift:820-835`). "FM" isn't in the hardcoded order list (`:228`), so it appears via the alphabetical dynamic tail — grouped and findable with **zero code change**. Optional polish at unfreeze: insert "FM" into `categoryOrder` for position.
- **Delivery: append into `Resources/Aurora100.json`** — that file loads in both the app (`AuroraApp.swift:230`) and the plugin (`PluginCore.mm:62`), so new patches reach app and (eventually) DAW. Data append + the one-line loader-guard relaxation below — a separate bank file would require new loader code, rejected.
- Bank counts: `Aurora100.json` entries **100 → 115** with the flagship 15 (the deliverable); **+ B more only if the side quest runs** (B=11 → 126). Side-quest originals move in place in their home files — those file counts never change.
- **⚠ Loader guard — the one mandatory code line (lock review finding):** the app refuses any `Aurora100.json` whose count isn't exactly 100 — `sounds.count == 100 else { return [] }` (`AuroraApp.swift:233`; same pattern :239/:245/:251/:257 for the other banks). Appending patches without relaxing it **silently empties the entire factory bank at runtime** (100 patches vanish; `:859` fires) — a runtime invariant, *not* a CI matter. Therefore Phase 4 includes the one-line fix `== 100` → `>= 100` at `:233`, riding the Phase 4 unfreeze (patch work is post-unfreeze by construction). Plugin side verified during lock review: **no count guard exists** — `PluginCore.mm:64` only checks the bank is non-empty, so the plugin needs no change. The count-sensitive tests that turn red are `PatchBankAudit.mm:246` (`bank.count != 100`) and `PluginCoreChecks.mm:22` (`bank.count == 100` assert) → red accepted per directive; re-baseline at the owner's deferred wipe.
- **Composition (draft):** 1–7 electric piano: bright DX tine · mellow DX ballad · Wurli-through-Character · felt/tine ambient · hybrid Rhodes-ish · clav/metal key · glass EP — 8–9 bells/mallets: vibraphone · marimba/glass — 10–11 plucks: harp-ish · harpsichord-ish — 12–13 basses: round FM · click/tine — 14–15 motion: bell-pad · evolving keys.
- Coverage: ≥10 of the 16 algorithms exercised; **every patch routes velocity→index**. Authoring collaborative; audition is the owner's ear (no process attached).
- **Wave policy:** flagship 15 authored core-on-sine (DX authenticity); WT-modulator ops allowed where they earn their place. **Optimization target = live gigging (the app).** DAW/plugin parity = low-priority Phase-2 fix (owner: *fix if cheap*).
- **EP-ish expansion batch — OPTIONAL SIDE QUEST (owner, 23 Sep: AI's call whether/when — never an owner ask; category `FM`):** re-author the current EP-adjacent patches onto FM, keeping name/detail spirit. **Verified pool (16, grep-checked 23 Sep), all in loaded banks' Keys blocks** — `Aurora100.json`: Apricot Felt · Glass Espresso · Moss Porcelain · Paper Wurlitzer · Silver Tack · Yellow Felt Cinema — `AuroraPrism100.json`: Honey Rhodescope · Kaleidoscope Clav · Electric Walnut · Blue Ceramic Piano · Zinc Bell Piano — `AuroraNova100.json`: Copper Tines · Rosewood Ghost · Underwater Upright · Afterhours Opal · Ivory Rain. Default batch **B = 11** (EP-idiom core) if the side quest runs. **15 flagship is the hard deliverable; this batch is gravy.**
- **A/B pairing (conditional & trivial — owner, 23 Sep: *"if you do [re-authors], give me the old and new so I can compare… as simple as that"*):** the side quest exists only to compare, so *IF* re-authors ship, each ships two entries in category `FM` — the **FM version under the clean original name** and the **original kept as-is**, moved to `FM` with a **` (OLD)` suffix** (e.g. `Honey Rhodescope` beside `Honey Rhodescope (OLD)`). Only `name` + `category` touch the original — sound stays byte-identical; suffix (not prefix) so the browser's name-sort (`all` is name-sorted, `AuroraApp.swift:264`) places each pair adjacent. Mechanics if run (verified 23 Sep): **originals edited in place in their home files** — `Aurora100.json` / `AuroraPrism100.json` / `AuroraNova100.json` (rename + recategorize; counts unchanged); **FM re-authors append into `Aurora100.json`** (the one file the app *and* plugin load). `AuroraSpectrum300.json` plays no role — never loaded. **Skip the whole side quest freely — owner doesn't care about the old ones; core (engine + flagship 15) is unaffected either way.**

## 9. UX — visual algorithms

Layer card engine toggle `Subtractive | FM`. FM panel: **16-diagram picker grid** (vector drawings), four operator columns (wave · ratio · level · velocity · mini envelope curve — bounded canvases, no per-frame invalidation, honoring the rendering-audit lessons), feedback + pitch env, compact collapse. Play-screen macros unaffected. Accessibility labels + `.help` per conventions; AU/VST3 automation via `PluginParameters.hpp` (stable IDs, DAW-persistent).

## 10. Design targets (engineering intent — not process)

**24-note FM polyphony floor** on M3 (owner-set); 32 stretch. Double-precision phases, denormal guards. Stability: owner-confident, validation excluded by directive.

## 11. Phases (original delivery plan)

1. **C++ core — SHIPPED v0.24.0:** ops, rate/level envelopes, 16 algorithms, feedback.
2. **Swift integration — SHIPPED v0.24.0:** layer engine mode, JSON load/save, bridge, matrix destinations, velocity source, checkpoint/undo + save-as/user-preset writers round-tripping `fm`, and `PluginCore` bank parsing.
3. **UX — SHIPPED v0.24.0:** visual algorithms + FM panel.
4. **Flagship library — SHIPPED v0.24.0 and expanded in v0.24.2–v0.24.3:** the original 15 flagship FM patches, five pure DX-style EPs, and five additional `DX7 …` EP variants; loader guard fixed. The optional OLD A/B side quest was not required and was skipped.
5. **Deferred, owner-triggered:** full patch wipe + test re-baseline — no earlier than when the owner decides the old library has served its purpose.

The original 100→115 count describes the first FM delivery. The current `Aurora100.json` contains 125 sounds after the approved FM EP expansion; see `CHANGELOG.md`.

## 12. Decision log

| # | Decision |
|---|---|
| 1 | FM was queue #1 at proposal time and shipped in v0.24.0 |
| 2 | Architecture A — per-layer `Subtractive \| FM` |
| 3 | **16** algorithms v1 |
| 4 | Dedicated pitch envelope |
| 5 | Wipe deferred, owner-triggered; patches stay for now |
| 6 | Velocity promoted to `soundSources` |
| 7 | Polyphony floor **24** |
| 8 | Name: **"FM"** |
| 9 | Testing/CI + hardware validation out of scope; red accepted |
| 10 | **15 patches, category "FM", appended to Aurora100.json** |
| 11 | **Per-layer** algorithm/feedback/pitch-env; sub + noise kept in FM mode |
| 12 | Feedback = single per-layer amount (per-operator = v1.1) |
| 13 | **Live gigging = optimization target**; DAW parity low-priority, fix-if-cheap |
| 14 | **EP-ish batch:** re-author/carry existing EP-adjacent patches into category `FM` (15 flagship floor + flexible extras) |
| 15 | **OLD A/B pairing:** originals kept + moved to `FM` with ` (OLD)` suffix; re-authors keep clean names; pairs sort adjacent |
| 16 | **Loader guard rides Phase 4:** `AuroraApp.swift:233` `== 100` → `>= 100` (runtime invariant; appends otherwise empty the bank) |
| 17 | **Zero backward compat re-affirmed (owner, 23 Sep):** pristine new features/code outrank compat; old patches = raw material, not sacred — if any compat burden appears, **delete it, don't engineer around it**. True forward-compat edge accepted: **old binaries reading FM patches get `fm` ignored → subtractive render — no guarantee, no shim, ever.** The absent-`fm` → Subtractive default is a load-time rule for the current library (dies at wipe), not compat. |
| 18 | **Side-quest demotion (owner, 23 Sep):** EP-ish re-authors + ` (OLD)` pairs are **OPTIONAL — AI's call, trivial, never an owner ask** (*"I don't give a shit about the old ones"*). Core = engine + 15 flagship. If re-authors run → pairs run (old+new comparison = the point); if not → nothing lost. Supersedes the mandate-flavor of rows 14–15; row-15 mechanics still apply whenever the side quest runs. |

