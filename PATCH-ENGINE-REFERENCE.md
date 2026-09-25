# KiMiA Sound Engine Reference — for patch designers

**Audience:** any AI (or human) designing factory patches. Read
[PATCH-DESIGN-RULES.md](PATCH-DESIGN-RULES.md) first — it says *what* a patch must be.
This document says *how the engine actually behaves*, so a design lands where you intend.
Everything here was read from the source (`Sources/SynthEngine.cpp`, `Sources/FmEngine.cpp`,
`Sources/AuroraBridge.h`) and measured on 25–26 September 2026 (engine 0.26.1 + the 0.27
reverb). If the code changes, re-check the numbers you rely on.

---

## 1. Signal flow

```
per voice (one per held key per layer):
  Osc 1 + Osc 2 (classic waves or wavetables) ─┐        FM mode: 4 operators replace Osc 1/2
  + Sub (sine, 1 octave down, x0.6)            ├─ Drive (tanh, pre-filter) ─ Filter 1 (+ Filter 2)
  + Noise (white, x0.3)                        ┘   ─ Character (warm/clip/fold/crush + tone) ─
  x amp envelope (declicked) x velocity (subtractive only) x expression x Level x 0.16/unison
  -> pan (unison lanes spread) -> dry bus, and per-layer sends -> Delay / Reverb / Shimmer

master bus: dry + inserts (chorus, phaser, flanger, tremolo/pan/rotary, auto-wah, bitcrusher)
  + send returns (delay, reverb, shimmer) -> house EQ (session) -> compressor
  -> tanh(signal x Master) -> Output boost (session, dB) -> limiter (ceiling 0.98)
```

- Up to 64 voices; a stolen voice fades over 6 ms in a ghost slot.
- **Master (patch `globals[0]`) feeds a tanh soft clip.** High Master on a dense patch saturates
  softly; keep the pre-tanh level moderate and set loudness with Master, not Level at 1.0.
- Output boost, house EQ and the limiter are session settings, not patch data.

## 2. Patch file (`Resources/AuroraFX.json`, a JSON array)

| Field | Meaning |
|---|---|
| `id`, `name`, `category`, `detail` | `mx-<slug>` / `mxep-<slug>`; name unique; detail ≤ 500 chars |
| `layers[4]` | `{values: {"0": … "125": …}, fm?: {...}}` — layer params by index (section 3); `fm` makes it an FM layer |
| `globals[6]` | Master, Tempo, Delay mix, Delay feedback, Reverb mix, Chorus mix |
| `phaserMix` | global 6 |
| `fx` | `{"7": …}` globals 7–14 and 16–72 (20–22 are the session EQ and are never stored) |
| `sends[4]` | per layer `{delay, reverb, shimmer, shimmerBypass}` send amounts |
| `soundMatrix[4][10]` | per-layer modulation routes (section 6) |
| `performanceMatrix[6]` | global routes from wheel/velocity/pressure/expression/sustain/CC (padded to 10 by the app) |
| `motion[4]` | motion envelope per layer (section 8) |
| `customMacros{"0"…"7"}`, `macros[8]` | macro names/routes, stored positions (0.5) |
| `xy` | XY pad: x/y → macro index and range |

Loading (`SynthModel.applyPatch`, mirrored by `bench/patchload.hpp`): sends, motion, matrices,
globals 6–14 and 16–72 (missing keys take `SoundPreset.fxDefaults`), all 126 layer params,
FM, then `globals[0…5]`. **Macros are not applied at load**: a patch sounds exactly like its
stored parameters.

## 3. Layer parameters (0–125)

Units: cutoff Hz, times seconds, rates Hz, detune cents. `[lo, hi]`, *log* = log-scaled for
macros/UI, *int* = integer.

### Oscillators
| # | Param | Range | Behaviour |
|---|---|---|---|
| 0 | Enabled | 0/1 | layers C/D (2, 3) stay 0 for AI patches |
| 1, 2 | Osc 1/2 wave | 0–4 int | 0 sine, 1 triangle, 2 saw (polyBLEP), 3 pulse (uses PW), 4 harmonic (sine + .32·2nd + .18·3rd + .08·5th) |
| 3 | Oscillator blend | 0–1 | 0 = Osc 1 only, 1 = Osc 2 only |
| 4 | Detune | 0–30 cents | Osc 2 ratio (Osc 2 sharp) |
| 5 | Sub | 0–1 | **sine** one octave below, ×0.6 |
| 6 | Noise | 0–1 | white, ×0.3, continuous (shaped only by the amp envelope) |
| 34, 35 | Pulse width, PWM | .05–.95, 0–1 | PWM = LFO 1 × depth × 0.45 (so PWM needs LFO 1 running; LFO 1 depth can stay 0) |
| 36, 37, 38 | Unison, detune, spread | 1–8, 0–30, 0–1 | lanes spread ±detune symmetrically; output ×1/unison, so decorrelated lanes are **quieter** (4 lanes ≈ −6 dB RMS) |
| 39, 40 | Sync, Sync tune | 0/1, 0–36 st | Osc 2 ratio = 2^(tune/12) **only when sync is on**. Whole-number ratios (tune 12, 19, 24) reset seamlessly: sync on + tune 12 is a clean Osc 2 an octave up |
| 70, 71, 72 | Osc mod mode, amount, ratio | 0–3, 0–1, .25–8 | 1 phase mod (Osc 2 → Osc 1 phase), 2 linear FM, 3 ring; depth fades out toward Nyquist |
| 44–50 / 51–57 | WT 1 / WT 2: on, table, position, warp mode, warp, phase, random phase | | wavetable replaces the classic wave |
| 93–96 | WT formant, tone (×2) | 0–1 | |

Factory wavetables (0–23): Warm — 0 Silk Spectrum, 1 Velvet Ranks, 2 Warm Prism, 3 Amber Pulse;
Vocal — 4 Vowel Drift, 5 Choir Glass, 6 Reed Talk, 7 Hollow Mouth; Metallic — 8 Copper Bells,
9 Steel Petals, 10 Crystal Steps, 11 Bronze Motion; Aggressive — 12 Acid Teeth, 13 Razor Bloom,
14 Electric Fold, 15 Digital Grit; Atmospheric — 16 Cloud Harmonics, 17 Frozen Organ, 18 Air
Columns, 19 Dusk Choir; Pure — 20 Round Sub, 21 Rubber Wire, 22 Soft Tines, 23 Flute Halo.
Table 24 = user import.

### Filters and colour
| # | Param | Behaviour |
|---|---|---|
| 7, 8 | Cutoff, resonance | state-variable filter; resonance k = 2 − 1.85·res (0–0.9); cutoff clamped 20 Hz … 0.42·fs |
| 32, 79 | Filter type, slope | 0 LP, 1 HP, 2 BP, 3 notch; 12 or 24 dB |
| 20 | Filter envelope | −1…1: cutoff × 2^(amount × **amp envelope** × 4) — it follows the amp envelope (±4 octaves at full) |
| 58–63, 80 | Filter 2 on, type, cutoff, res, routing, balance, slope | routing 0: 1→2, 1: 2→1, 2: parallel (balance mixes) |
| — | Key tracking | none built in: route source *key* → cutoff; amount 1.25 ≈ 100 % tracking (source = (key−60)/60) |
| 21 | Drive | pre-filter tanh(x·(1+8·drive)) |
| 73–78 | Character: mode, drive, mix, tone, bits, rate | post-filter; 1 warm (tanh, normalised), 2 clip, 3 fold, 4 crush (sample-hold, bits, rate); drive gain 1+12·drive; tone = low-pass from 300 Hz·2^(5.9·tone) |

### Envelopes
| # | Param | Behaviour |
|---|---|---|
| 9 | Attack | **linear** ramp, seconds |
| 10 | Decay | exponential toward Sustain; Decay = time to fall **60 dB** of the distance |
| 11 | Sustain | 0–1. Poly voice with sustain 0 is **freed at −80 dB (1.33 × Decay)** even while key/pedal holds it |
| 12 | Release | exponential; Release = time to **−80 dB**; the voice is freed at −100 dB (1.25 × Release) |
| 64–69 | Mod envelope A/D/S/R, amount, destination | same maths; destination 0 cutoff, 1 Filter 2 cutoff, 2 pitch, 3 osc mod, 4 character drive, 5 WT 1 pos, 6 WT 2 pos; amount 1 → +4 octaves on cutoff |

Amplitude is smoothed by two 0.7 ms one-pole stages (declick): attacks faster than ~2 ms
round off slightly; pure tones still want attack ≥ 5 ms (rule 9).

**Decay drives CPU with the pedal.** A pedalled sustain-0 note lives 1.33 × Decay seconds; a
Decay of 8 s keeps ~20 voices alive in a pedalled passage (measured), 4 s about half that.

### LFOs
| # | Param | Behaviour |
|---|---|---|
| 16–19 | LFO 1 rate, depth, destination, shape | dest 0 cutoff (±3 octaves × depth), 1 pitch (±2 st × depth), 2 pan, 3 amplitude (±0.5 × depth); shapes 0 sine, 1 tri, 2 saw, 3 square, 4 random |
| 29–31, 33 | LFO 2 rate, depth, dest, shape | same. **LFO 2's phase drives the mod wheel's built-in vibrato** (±25 cents at full wheel), so keep LFO 2 rate at a vibrato rate (~5.2 Hz) even when LFO 2 depth is 0 |
| 81–92 | sync, division, retrigger, phase, delay, fade (×2) | division 0 4 bars, 1 2 bars, 2 1 bar, 3 1/2, 4 1/4, 5 1/8, 6 1/16, 7 1/32, 8 1/8 dotted, 9 1/8 triplet; delay/fade in seconds (delayed vibrato: delay .3–.5, fade .5) |
| 99–125 | LFO 3–5 | matrix-only sources; an unrouted one costs nothing |

### Voice, arp, range, level
| # | Param | Behaviour |
|---|---|---|
| 41, 42, 43 | Voice mode, glide, bend | 0 poly, 1 mono (retrigger), 2 legato; glide = time to −60 dB of the pitch distance |
| 22–26, 97, 98 | Arp on, rate, mode, octaves, gate, swing, velocity shape | rate 0 1/4, 1 1/8, 2 1/8T, 3 1/16, 4 1/16T, 5 1/32; 30 modes |
| 27, 28 | Key low/high | splits |
| 13, 14, 15 | Level, pan, transpose | Level is linear gain |

**Velocity:** a subtractive layer's amplitude is × velocity (linear: velocity 40 vs 100 =
−8 dB, the same for every patch). An FM layer ignores that; its dynamics come only from each
operator's velocity sense. For more expressive keys, add velocity → cutoff (brightness) or
velocity → FM index routes.

## 4. FM engine (layer `fm` block)

Four operators, 2× oversampled modulator chain, one designated feedback operator. When `fm`
is enabled the operators replace Osc 1/2; Sub, Noise, Drive, both filters, Character, the
amp envelope, Level and pan still apply. FM layers render one lane (no unison).

**Algorithms** (`target[o]` = operator that `o` modulates, −1 = carrier; fb = feedback op):

| # | Name | Topology | fb |
|---|---|---|---|
| 0 | Deep Chain | 0→1→2→3 (3 carrier) | 0 |
| 1 | Twin Roots | 0→2, 1→2, 2→3 | 0 |
| 2 | Split Chain | 0→1→3, 2→3 | 0 |
| 3 | Triple Root | 0, 1, 2 → 3 | 0 |
| 4 | **EP Twin** | 2→0, 3→1 (carriers 0, 1) | 2 |
| 5 | Chain & Solo | 2→1→0, carrier 3 | 2 |
| 6 | Mirror Pair | 0→1, 3→2 (carriers 1, 2) | 0 |
| 7 | Nested Twin | 2→3→0, carrier 1 | 2 |
| 8 | Hub Pair | 0→2, 1→3 (carriers 2, 3) | 0 |
| 9 | Triple Crown | 3→0, carriers 0, 1, 2 | 3 |
| 10 | Post Stack | 3→1, carriers 0, 1, 2 | 3 |
| 11 | Head Stack | 0→3, carriers 1, 2, 3 | 0 |
| 12 | **Pure Additive** | four carriers (drawbars) | — |
| 13 | Deep Feedback | chain, fb on 2 | 2 |
| 14 | Twin Feedback | as EP Twin, fb on 3 | 3 |
| 15 | Loopback | chain, fb on 3 | 3 |

**Operator fields:** wave (0 sine, 1 tri, 2 saw, 3 pulse, 4 wavetable), ratio 0.25–16 (or
fixed Hz), fine ±1 = ±100 cents, level, velocity sense, key scale, envelope (4 rates, 4
levels), env mode (0 rate/level, 1 ADSR-seconds), pulse width, wavetable table/pos/warp.

- **Modulator level is an index: 1.0 = 10 cycles ≈ 63 radians of phase deviation.** Musical
  indices are small: an electric-piano body wants 1–2 rad (**level ≈ 0.015–0.03**), a tine
  0.5–1.3 rad (≈ 0.008–0.02); 5+ rad is already brassy/harsh. Use `index_level(radians)` in
  `scripts/claude_patches.py`. The five original FM EPs use levels 0.3–0.5 (20–30 rad) — the
  reason they measure 13 dB brighter than a DX-style EP should.
- Carrier level = amplitude. With several carriers, `carrierMix` weights them: first carrier
  (1 − mix), the rest mix/(n−1) each (n carriers). Pure Additive with mix 0.75 = equal weights.
- **Velocity sense s** scales an operator by 1 − s·(1 − velocity) (linear). On modulators it is
  brightness-with-touch; on carriers it is loudness-with-touch.
- **Key scale:** 1 "low" = level × 2^((60−key)/60) (−2.4 dB two octaves up) and envelope rates ×
  2^((key−60)/120) (higher notes faster) — the DX-like choice for tines and EP bodies; 2/3 = ×0.72
  on odd/even keys (special effects).
- **Envelope (mode 0):** stage 1 ramps to L1 at R1, stage 2 to L2 at R2, stage 3 to L3 at R3 and
  holds; note-off ramps to L4 at R4 from any stage. Segment time = 1/rate seconds; **ramps are
  linear in amplitude** (not dB like a DX7), so approximate an exponential fall with a quick
  first drop (L2) and a slower second segment. **Rates are clamped 0.02–200 (≥ 5 ms per
  segment)** by the engine; the app's packer allows up to 300, which then acts as 200.
- Feedback (0–1) adds the feedback op's own output × 6 cycles to its phase — its effect scales
  with that op's level, so feedback on a small-index modulator is subtle.
- Pitch envelope: amount × 12 semitones at note-on, falling to 0 over `time` (curve shapes it)
  — plucks (koto, harp) and zaps.
- Matrix FM destinations (37–46): op 1–4 level (additive to level), feedback, carrier mix, pitch
  env, fine, WT position/warp. **Macros cannot reach FM fields** (they target layer params);
  use the sound matrix (velocity, pressure, envelopes, LFOs) for FM expression.

## 5. Recipes that work (measured)

- **DX7-style EP** (`Eighty-Three Tines -CL`): EP Twin; op0 carrier 1:1 (level .72), op1 carrier
  1:1 fine +.03 (+3 cents, level .6), op2 body modulator 1:1 index ≈ 1.6 rad, op3 tine 14:1
  index ≈ 1.0 rad; modulator vel sense .9, carrier .85; key scale low on all; tine env
  (200, 12, 2.5, 10 / 1, .25, 0, 0), body (200, 2.5, 0.36, 6 / 1, .5, 0, 0), carriers
  (200, 3, .16, 4 / 1, .6, 0, 0); layer amp attack .001, Decay 8, Sustain 0, Release .45,
  cutoff 12 kHz. Measured: 13 dB darker above 2.5 kHz than the old FM EPs, full decay.
- **Drawbar organ:** Pure Additive, ratios 0.5 / 1 / 1.5 / 2 (16', 8', 5⅓', 4') or 1 / 2 / 3 / 4;
  percussion = a carrier at 2 or 3 with a fast-decaying envelope; key click = a second layer of
  noise with a ~20 ms envelope. Rotary = the Tremolo effect in Rotary mode (ships off).
- **Octave-up second oscillator:** sync on, Sync tune 12.
- **Delayed vibrato:** LFO 1 → pitch, depth .02–.04, rate ~5.3, delay .35, fade .5.

## 6. Modulation matrix

**Sound matrix** (per layer, 10 slots). Sources: 0 LFO 1, 1 LFO 2, 2 amp envelope, 3 mod
envelope, 4 key ((key−60)/60), 5 per-note random, 6–8 LFO 3–5, 9 velocity (0–1), 10 channel
pressure. Each route adds `signal × amount` to its destination:

| Dest | Name | Scaling |
|---|---|---|
| 0 | Cutoff | clamp ±2, × 4 octaves (amount .25 = 1 octave) |
| 1 | Pitch | clamp ±2, × 12 semitones |
| 2 | Pan | additive |
| 3 | Amplitude | added to 1 (clamped 0–2) |
| 4, 5 | Blend, drive | additive |
| 6, 7 | LFO 1/2 depth | additive to depth |
| 8–11 | chorus, phaser, reverb, delay | shared-bus amounts |
| 12–15 | WT 1/2 position, warp | additive |
| 16, 17 | Filter 2 cutoff (×4 oct), res | |
| 18, 19 | Osc mod amount, character drive | additive |
| 20, 21, 22 | Filter balance, resonance, pulse width | additive |
| 23 | Detune | × 30 cents |
| 24, 25 | Sub, noise level | additive |
| 26, 27 | Unison detune (× 30 cents), stereo spread | |
| 28 | Sync tune | × 36 semitones |
| 29–32 | WT formant/tone | |
| 33 | Osc mod ratio | × 2^signal |
| 34, 35, 36 | Character mix, tone, filter envelope | |
| 37–40 | FM op 1–4 level | additive |
| 41–46 | FM feedback, carrier mix, pitch env, fine, WT mod pos/warp | |

**Performance matrix** (global, 6 slots): sources 0 mod wheel, 1 velocity, 2 channel pressure,
3 expression (CC 11), 4 sustain, 5 any CC; destinations **0–20 only** (no FM, no WT formant);
target = one layer or 4 (all). Every Claude patch routes expression → amplitude (+0.1).

## 7. Macros and XY

Eight custom macros, each a list of routes `{target: {layer, parameter}, from, to}` with
from/to in **normalised** units (log parameters normalised in log space; `normalized()` in
`scripts/rebuild_factory_bank.py`). Layer −1 targets globals / fx keys. Keep every route
**symmetric around the stored value** (macro 0.5 = the patch as stored), because macros are not
applied at load. `CustomMacro.valid` needs at least one route per macro. XY maps x/y to two
macros (Claude patches: macro 0 and 1; say so at the end of `detail`).

## 8. Motion envelopes

Per layer: enabled, loop, seconds (or beats), 2–16 points (x 0→1 increasing, y 0–1, curve
±1), and eight routes (enabled, min, max, inverted): 0 amplitude, 1 cutoff (Hz, 30–18000),
2 pitch (st, ±24), 3 pan, 4/5 WT 1/2 position, 6/7 WT 1/2 warp. When route 0 is on, the
motion envelope replaces the amp envelope. Good for risers, swells, rhythmic gates. Leave
motion disabled unless designed (`disabled_motion()`).

## 9. Effects (all ten, per patch)

Rule 2: all set up, only Reverb ships on (Sound FX excepted). A switched-off effect costs
**0 % DSP** and switches without clicks (20 ms fades).

| Effect | Keys | Notes |
|---|---|---|
| Delay | globals 2, 3; fx 14, 16–19, 48–49 | sync on; timing 0 1/4, 1 1/8, 2 1/16, 3 1/2, 4 1/8 dotted, 5 1/4 dotted, 6 1/8T, 7 1/4T; ms 1–2000 when unsynced; ping-pong; tone; duck amount/release |
| Reverb | global 4; fx 12, 13, 70–72 | **Type** 0 Classic (small Schroeder room, grainy tail) / 1 Plate (Dattorro, dense and smooth, level-matched to Classic within ~2 dB); Size 0–1; Decay 0.2–8 s (Classic's real RT60 is ~20 % shorter at long settings, Plate tracks it); **Pre-delay** 0–200 ms; **Tone** 0 dark … 0.5 original … 1 bright. Size/Pre-delay changes are click-free |
| Chorus | global 5; fx 10, 11 | rate, depth |
| Phaser | `phaserMix`; fx 7–9 | rate, depth, feedback (±.85) |
| Shimmer | fx 23–36 | mix, pitch (−12…24), decay, tone, pre-delay, amount, +5/+7/+12 voices, reverse, early/late |
| Flanger | fx 37–40 | mix (≤ .8), rate, depth, feedback (≤ .9) |
| Tremolo | fx 41–44 | mix, rate, depth, mode 0 tremolo / 1 pan / 2 rotary |
| Bitcrusher | fx 45–47 | mix, bits 1–16, downsample 1–64 |
| Compressor | fx 50–55 | threshold (0 = off), ratio, attack ms, release ms, makeup, auto |
| Auto-wah | fx 56–59 | mix, sensitivity, range, mode 0 LP / 1 BP |
| Power | fx 60–69 | shimmer, delay, reverb, chorus, phaser, flanger, tremolo, crush, wah, comp |

Per-layer sends (`sends`) scale how much of each layer reaches Delay, Reverb and Shimmer.

## 10. Loudness, low end, CPU — how to measure

`bench/patchcheck` (outside the repo, `~/Desktop/KiMiA by Claude/bench`) renders patches
through the engine exactly as the app loads them (0 dB boost, 48 kHz) and prints: **early** =
RMS of a C3-G3-C4-E4 chord at velocity 100 (single C2 for basses, C5 for
mono leads); velocity 40 and 115 relative to 100; share below 120 Hz and above 2.5 kHz;
note-on click (rule 9 method); level after 6 s held; stress peak (8 notes at 127); CPU of a
pedalled 8-bar passage and peak voices. "Early" is the loudest 0.5 s window in the first 3 s
of the held chord, so slow-attack pads are judged at their full level. Build and run:

```
cd ~/Desktop/KiMiA by Claude/bench     # see README.md there
./bin/patchcheck ../aurora-synth/Resources/AuroraFX.json --match " -CL"
```

Reference (the 55 originals, 26 September, `bench/results/patchcheck-v2.*`): early level median
−33.0 dBFS, from −51.5 (Bell Reed 200) to −17.4 (Reed Confession) — a 34 dB spread; non-bass
share below 120 Hz, median −14.2 dB. The four FM EP drafts read −33 to −38 dBFS at Master 0.5. **Target for new patches: −30 ± 2 dBFS early RMS** (set with Master). Non-bass patches: share below 120 Hz ≤ about
−12 dB (Dual Patch low-end rule). **CPU numbers under `taskpolicy -b` run on efficiency cores
and read ~2.5× high** — compare patches with each other there, or measure at normal priority
for absolute numbers. Budget guidance: rule 8 of PATCH-DESIGN-RULES.md.

## 11. Authoring pipeline (Claude patches)

1. Design in **`scripts/claude_patches.py`**: `layer(**named params)` from a neutral base (no
   hidden LFO/filter-env/drive), `op()` / `fm()` / `index_level()` for FM, `effects(family,
   **overrides)` sets all ten effects (only Reverb on; `sound_fx=True` for Sound FX), sound and
   performance routes by name, `macros=[(name, [(layer, param, span)])]`, `struck=True` forces
   sustain 0 (and asserts FM L3 = 0). Names end in ` -CL`.
2. `python3 scripts/assemble_modx_bank.py` rebuilds `Resources/AuroraFX.json`: the 55
   originals byte-identical, then the Claude patches, validated (unique base names and ids,
   layers A/B only, only Reverb powered, eight valid macros).
3. Measure with `bench/patchcheck`, then write calibrated Master values to
   `scripts/claude_levels.json` (`{"mx-…": master}`; new master = old × 10^((target − early)/20),
   capped so the stress peak stays sane) and rebuild.
4. `./scripts/build.sh`, then the test suites (`scripts/test.sh`, `scripts/test-baseline.sh`,
   `check-v1-specialized-regression.sh`, `check-v1-ab-comparison.sh`, `Tests/PluginCoreChecks.mm`,
   `Tests/V1FactoryAudioAudit.mm`); the audit and plug-in checks loop over every patch.
5. The owner reviews in the app; approved patches lose ` -CL` in the next build (ids stay).

## 12. Gotchas (all found the hard way)

- FM modulator level 1.0 ≈ 63 rad; EP indices are 0.01–0.03 (section 4).
- FM envelope rates ≤ 200 (5 ms segments) and linear in amplitude.
- LFO 2 rate = mod-wheel vibrato rate, even when LFO 2 depth is 0.
- Filter envelope follows the **amp** envelope; for an independent filter sweep use the mod
  envelope (destination 0).
- Sub is a sine (not a square); Osc 2 cannot transpose an octave without sync (sync + tune 12).
- Unison lowers RMS (×1/unison); calibrate Master after choosing unison.
- Velocity → amplitude is linear and identical in every subtractive patch; FM layers need
  carrier velocity sense for dynamics.
- Sustain-0 poly voices free themselves at −80 dB, so long Decay = more pedalled voices = CPU.
- Master goes through tanh: loud Master on dense chords saturates.
- Pure tones expose envelope corners (rule 9): attack ≥ 5 ms on sine/triangle sounds.
- Macros can't target FM fields; the performance matrix can't reach destinations above 20.

## 13. Where everything else is

- `SHARED_STATE.md` — owner's standing rules (local commits only, push/tag on request, plug-ins
  only on request, tests serve the software), release state, pending queue.
- `PATCH-DESIGN-RULES.md` — the owner's patch rules (layers, effects, clicks, CPU, batches).
- `CHANGELOG.md` — what changed per version (0.26.0 true bypass, 0.26.1 declick/limiter/voice
  stealing, 0.27 reverb).
- `AURORA-TEST-CONTRACT-v1.md` — test suites and the owner's rule that tests adapt to the software.
- `~/Desktop/KiMiA by Claude/bench/README.md` — measurement tools (real-callback load, bit-exact
  A/B against release snapshots, patch measurements, reverb checks).
- `~/Desktop/KiMiA by Claude/NEXT-SESSION-PROMPTS.md` — ready prompts for the next sessions.

---

## Appendix A — the 50-patch batch (September 2026)

Owner decisions: 50 new patches reviewed together; names end in ` -CL`; version 1 ships 150
patches (55 originals + these 50 + 45 more later). Spread: Pad/Choir 6, Syn Lead 5, Keyboard 4,
FM EP 4, Organ 4, Strings 4, Brass 4, Syn Comp 4, Piano 3, Chromatic Perc 3, Woodwind 2, Guitar 2,
Bass 2, Ethnic 1, Musical FX 1, Sound FX 1.

**Status 26 September 2026:** framework done; 4 FM EP drafts in `scripts/claude_patches.py`
(Eighty-Three Tines, Ballad Glass, Tine Bark, Bell Tine Nineties) — built and measured once,
not yet level-calibrated (early −33 to −38 dBFS at Master .5), CPU with pedal high because of
Decay 8 s (consider 5–6 s), Bell Tine Nineties too dark (−48 dB above 2.5 kHz). The other 46 are
planned below, not written.

| Category | Planned patches (musical job) |
|---|---|
| FM EP | Eighty-Three Tines (1983 FM EP, ballads/80s pop) · Ballad Glass (soft verse EP) · Tine Bark (funk EP, velocity bark + grit) · Bell Tine Nineties (90s R&B bell EP) |
| Keyboard | Wurli Smoke (Wurlitzer 200A, reedy bark) · Pianet Spark (Hohner Pianet, short woody pluck) · Clav Stax (dark funk clav, no wah) · Harmonium Porch (reed harmonium, bellows) |
| Piano | House Piano 90 (M1-style house piano, FM body + bell pair) · Electric Grand 80 (CP-80 twang, FM) · Lo-Fi Upright (crushed, tape-wobbled upright) |
| Organ | Drawbar Jazz (888 + 3rd-harmonic percussion, key-click layer) · Rock Drive (full drawbars + warm Character overdrive) · Combo Sixty (Vox/Farfisa squares, octave via sync) · Musette Café (three-reed accordion) |
| Strings | Solina Glow (string machine, unison ensemble) · Cinema Section (slow swelling section + octave layer) · Staccato Bows (short rhythmic strings) · Cello Lament (mono legato cello, delayed vibrato) |
| Brass | Jump Brass (OB-Xa bright saws) · Section Punch (tight horn stabs) · Horn Swell (warm French-horn pad) · Muted Noir (harmon-muted trumpet lead) |
| Syn Lead | Sawtooth Sermon (fat mono saw, glide) · Sync Scream (sync lead, mod-env sweep) · Whistle Portamento (soft sine/triangle, glide + vibrato) · Chip Square (8-bit square, crush) · Vowel Talker (formant wavetable lead) |
| Pad/Choir | Polyester Pad (Juno PWM pad) · Breath Choir (airy vocal wavetables, HP'd) · Dark Matter (slow evolving wavetable drone, LFO 3-5 motion) · Glass Halo (FM bell pad + octave shimmer layer) · CS Sunrise (Blade Runner brass pad, pressure opens it) · Soft Cloud (light high pad to sit under a piano) |
| Syn Comp | Supersaw Anthem (unison 5 stab, short release) · Lagoon Pluck (tropical-house pluck) · Funk Poly (Prophet poly comp) · Reso Stab 90 (resonant house stab) |
| Chromatic Perc | Vibes Night Club (FM vibes, voice-level motor tremolo) · Glock Candy (additive glockenspiel partials, +24) · Kalimba Sun (thumb piano) |
| Woodwind | Pan Flute Andes (breath chiff) · Clarinet Shadow (square, mono legato) |
| Guitar | Clean Chime (clean electric pluck) · Banjo Porch (bright twang) |
| Bass | Finger Round (plucked finger bass) · Mono Floor (Minimoog-style mono bass) |
| Ethnic | Koto Garden (FM pluck with pitch strike) |
| Musical FX | Heartbeat Pulse (tempo-synced gated pad, LFO 3 square → amplitude) |
| Sound FX | Riser Nebula (motion-envelope riser; effects may ship on) |
