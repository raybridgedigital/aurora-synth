# Patch Design Rules — KiMiA factory sound

**Audience:** any AI (or human) authoring factory patches. Read this before
creating or editing patches. Enforced where noted by
`scripts/assemble_modx_bank.py`; everything else is review-checked.

**Why these rules exist (owner, 25 September 2026).** KiMiA is a gigging
instrument. The owner would rather have 100 good patches than 400 that never
get played: 765 earlier patches were retired for exactly that reason (heavy,
samey, unused). The goal is a self-sufficient instrument for synth sounds — soon a
Dual Patch will combine two different characters, so the CK88's own sounds are
no longer needed for anything synth-based (its sampled grand piano stays on the
CK88). Every rule below serves that: a patch must be worth playing on stage on
its own and as one half of a Dual Patch.

## 1. Zero sustain for single-energy-attack instruments (ENFORCED)

A plucked, struck, or hammered string receives all its energy at the attack —
physics allows only decay afterwards. Sustain > 0 means "holds forever while
the key is down", which is impossible for these instruments. Therefore:

- Sustain (ADSR S, layer param 11, and every FM op sustain level L3) is **0**
  for: piano (all kinds incl. FM EP), harpsichord, clavinet, guitar (all
  kinds), dulcimer/santur, koto-family plucks, pizzicato, marimba, vibes,
  steel drums, music box, celesta/bells, sitar and other ethnic plucks,
  struck stabs and comps, thunder hits, laser zaps, picked bass.
- The ring comes from **Decay + Release**, not sustain. Set D/R to musical
  values (piano D ~1.0–1.5 / R ~1.0–1.8; plucks D ~0.2–0.8; percussion
  matched to the hit) so note-off never clips the tail.
- FM EP patches: every op sustain level (L3) is 0 — real pianos decay to
  silence while held. The subtractive bed layer follows the same rule.

Sustain > 0 is legitimate ONLY for: bowed strings (violin, cello, ebow),
blown winds (flute, clarinet, oboe, brass, shakuhachi), organ (wind-driven),
pads/choirs/drones, sustained horns, evolving clouds, and held-synth voices
(sub goblin, acid line, fretless song, mono synth leads). Ebow is a guitar
but bowed — it sustains. When in doubt, ask what excites the string.

## 2. Effects: all set up, only Reverb switched on (owner's rule)

When the player picks a patch they hear the **dry sound, plus its reverb where
that helps**. Every effect is still part of the design: each patch carries
settings for all ten effects, tuned for that sound (a chorus rate and depth
that suit it, a delay time, feedback and tone that suit its tempo and register,
a phaser or flanger speed that fits), but **every effect except Reverb ships
switched OFF**. Switching any of them on must make the sound better, because it
was set up for it.

- Reverb is the only effect that may ship ON. On or off is the designer's
  call per patch (a dry bass or a tight lead may ship with it off).
- Reverb Pre-delay and Tone belong to the reverb, not to the Delay effect.
- Width and movement come from the voice itself (unison spread, detune,
  stereo LFOs, motion envelopes), never from an effect that ships on.
- **Exception — Sound FX only.** Non-musical sound effects (risers, impacts,
  sweeps, textures) may ship any effects ON; creativity is limited only by
  the hardware. They must still stay clean, never crackle, and fit the CPU
  budget (rule 8). Musical FX follows the normal rule.
- **The original 55 AuroraFX patches (made before 25 September 2026) are
  exempt and stay exactly as they are** — the owner's decision. Do not "fix"
  their effect settings.

## 3. One character per patch; AI uses layers 1 and 2 only

Each patch is exactly one instrument/character — never Piano+Pad or
Bass+Lead hybrids. Layering two characters is the future dual-patch's job.
A second layer is allowed only as same-character support (sub octave, octave
shimmer, noise attack transient, sympathetic drone, octave double).

**Layers 3 and 4 are reserved for the owner (owner's rule, 25 September
2026).** Every AI — and anyone else designing sounds for KiMiA — uses **one or
two layers only: layer A, or A + B.** Layers C and D belong to Reza, the owner.
An AI must never switch on, fill, paste into or edit layer C or D, must never
propose a three- or four-layer design, and must leave any C/D content the
owner has made exactly as it is. If a sound seems to need a third layer,
simplify it to two, or describe the idea to the owner instead.

Why the engine has four layers at all: a future Dual Patch plays two 2-layer
patches together (four layers in total), and C/D stay free for the owner's
own exceptional designs. The retired 3–4 layer banks (archive/factory-banks)
show what happens otherwise: at a 24 September 2026 gig their pedalled 4-layer
sounds needed 82–91% of the 128-frame budget on an M3 MacBook Air and crackled.

**Design every patch as a good half of a Dual Patch.** Dual Patch will combine
two different characters (keys + pad, bass + keys split, lead over strings), so:

- **Matching loudness:** a patch's held-chord level sits close to its
  neighbours' (rule 6), so any two combine without one burying the other.
- **Controlled low end:** only basses (and deliberate sub layers) carry
  strong content below ~120 Hz; pads, keys, strings and leads keep it light so
  layers do not turn to mud.
- **Natural register:** voice the sound for the range it is played in, so it
  also works as one side of a split.

## 4. Categories

15 Yamaha MODX mains (Drum/Perc intentionally skipped — hits don't fit a
held-note synth audit) plus `FM EP` for pure electric pianos:
Piano, Keyboard, Organ, Guitar, Bass, Strings, Brass, Woodwind, Syn Lead,
Pad/Choir, Syn Comp, Chromatic Perc, Sound FX, Musical FX, Ethnic, FM EP.
New `SoundPreset.category` strings outside `FactoryBank.categoryOrder` sort
after the known ones — no app change needed for new categories.

## 5. Effect settings discipline

- A switched-off effect costs no DSP and keeps its settings in the patch, so
  there is no reason to leave one unconfigured: set up all ten for the sound
  (rule 2). A closed gate is exact silence (rule 6).
- Delay uses tempo sync by default; rates of tremolo, phaser and flanger
  should suit the tempo the sound is usually played at.
- **Reverb type:** Classic is a small, fast room with a slightly grainy
  tail — good for tight keys, organs, comps and anything that must stay out of
  the way. Plate is a dense, smooth studio plate — the classic choice for EPs,
  pads, vocal-style leads, strings and bells. Size, Decay, Pre-delay and Tone
  apply to both. Use Pre-delay (10–40 ms) to keep piano, EP and pluck attacks
  clear in front of a long tail; use Tone to match the tail to the sound (dark
  pads darker, bells brighter).

## 6. Every patch must be audible AND panic-clean

- Audible: renders measurable energy on standard audition notes
  (`Tests/PluginCoreChecks.mm`, `Tests/V1FactoryAudioAudit.mm`).
- Panic-clean: after panic + 0.4 s drain the bus reaches EXACT zero.
  Only states cleared in `SynthEngine::clearFxRingsAndFilters` (plus
  self-draining paths) qualify — wah filter states, flanger buffers and
  bitcrusher holds were added for exactly this reason. Any newly featured
  DSP state must be added there too.
- Peak headroom: hold peaks well under 1.0; stress (8 notes @ 127, master
  100%) must stay finite and unclipped.
- Loudness: new patches sit at **−33 dBFS early level** (the originals' median;
  loudest 0.4 s of a held chord, 0 dB boost), measured with `bench/patchcheck`
  and set with `scripts/calibrate_claude_levels.py`, so switching patches or
  pairing them in a Dual Patch does not jump in volume.

## 7. Identity and placement

- IDs `mx-<slug>` (MODX bank), `mxep-<slug>` (FM EP). Unique across the
  whole factory (`FactoryBank.all`), names unique case-insensitively —
  including against the retired GB109 bank (archive/factory-banks/v0.25.0;
  `scripts/assemble_modx_bank.py` checks it from there).
- The MODX bank lives in `Resources/AuroraFX.json`, generated by
  `scripts/assemble_modx_bank.py` — never hand-edit the JSON. The script
  asserts spec ranges, uniqueness, macro coverage, and rules 1–2 at
  generation time. `scripts/build.sh` does NOT regenerate banks (checked-in
  JSON is the source of truth).
- New patches are automatically round-trip/audio tested by
  `Tests/PluginCoreChecks.mm` (any-count loop over `AuroraFX.json`).
- Details ≤ 500 chars, evocative + one playing hint.

## 8. CPU budget (measured, M3 MacBook Air, 44.1 kHz, 128-frame buffer)

Cost scales with sounding oscillator lanes: every held key starts one voice per
layer, and each voice renders one lane per unison voice (FM layers render one).
Measured on the current engine, share of the real-time budget:

- one sounding subtractive lane ≈ 0.3–0.9% (filters, Character and wavetables
  add to it), one sounding FM voice ≈ 1.5%, all ten effects on ≈ 1.3%, a
  switched-off effect 0%;
- a single factory patch with 8 keys held on the pedal: median ≈ 4%, worst ≈ 13%
  (a sustaining two-layer pad);
- a Dual Patch pair with 16 keys held: ≈ 30–33% for two sustaining pads, with
  peaks near 50% at the moment the chord is struck.

Guidance: keep unison ≤ 2 on polyphonic patches and reserve unison 4–8 for mono
or single-layer leads. Give natural-decay sounds sustain 0 (rule 1) — once such
a note has decayed under the pedal its voice is freed, which is what keeps
pedalled pianos, plucks and FM EPs cheap. Aim for a Dual Patch pair at 16 held
keys to stay under ~50%, leaving headroom for effects, the UI and a warm laptop.

## 9. Clicks and crackle: causes and how to design around them

Learned from the 0.26.0 field test (Sub Marine clicked on every note, Black Moss crackled at
64 voices). Measured with `bench/clickfind` (loudest 1 ms burst above 1.5 kHz, relative to the
note's RMS); a pure tone should stay below about -60 dB.

1. **A pure tone exposes every corner of the envelope.** A linear attack meets the decay in a
   sharp corner, and a corner is broadband. On a sine or triangle sound (sub-basses, flutes,
   soft pads) nothing else masks it, so it becomes the loudest treble in the note. Sub Marine
   (sine an octave down, 4 ms attack) clicked at -44 dB on every note, worst when two keys
   alternate detached, because each note re-attacks. Since 0.26.1 the engine smooths voice gain
   (two 0.7 ms stages), which brings that click to -74 dB, but design for it anyway:
   pure-tone basses and pads get an attack of at least 5 ms unless the click is the point, and
   mono basses use legato voice mode so trills and repeated lines do not re-attack.
2. **Voices add up; Output boost must not live in the limiter.** One note of a pad is quiet;
   64 of them are not. Black Moss peaks at 0.64 at 0 dB boost with a full pool, so +9 dB
   drives it to 1.8 and the old limiter clamped every peak (hard clipping, 5th harmonic at
   -40 dB, heard as crackle). 0.26.1 limits cleanly (-54 dB), but a patch should still leave
   room: at the house master, the 8-note velocity-127 stress chord should peak around 0.5 at
   0 dB boost so a normal +6 to +12 dB boost only touches the limiter on the loudest moments.
3. **Pedal + long release fills the 64-voice pool, and a full pool steals.** Black Moss
   (1.1 s attack, 3 s release) reaches 64 voices within eight pedalled chords. 0.26.1 fades a
   stolen voice over 6 ms (up to 16 at once, 32 oscillator lanes) instead of cutting it
   (-26 dB), and anything beyond that still clicks. For pedalled playing keep pad releases
   near 3 s or less, and avoid two layers x long release x unison on the same pad.
4. **Keep sub-bass inside the rig's range.** An octave-down sine puts C1 at 33 Hz, below what
   keyboard speakers and guitar amps (CK88, Katana) reproduce. The fundamental disappears on
   stage, the player turns up, and every click and speaker limit is exposed. Keep the lowest
   played fundamentals near 40 Hz or above for small rigs, or add a little upper content
   (a touch of saw, Character or a second oscillator) so the bass is heard, not just felt.
5. **Tell sound-design clicks from dropouts.** If the header's triangle blinks, the Mac missed
   an audio deadline (CPU); see rule 8. If it stays dark and a sound still clicks, it is the
   sound: check 1-4.

## 10. Quality over quantity: how new patches are made and reviewed

- **Every patch has a musical job** you can say in a few words ("ballad EP for
  verses", "80s power-brass stab", "dark pad under a piano") and earns its place:
  no near-duplicates of an existing patch.
- **Batches.** New patches arrive in batches (about 25). The owner plays each
  batch and marks every patch keep, tweak or drop before the next batch starts;
  what is learned goes into the next batch.
- **AI-made patches are marked.** A patch designed by Claude carries the name
  suffix ` -CL` (for example `Velvet Tine -CL`) until the owner approves it; the
  suffix is removed in the next build and the patch ID never changes. The base
  name (without the suffix) must be unique in the whole factory.
- **Imitations work from a reference.** When a patch imitates a specific
  instrument or classic synth sound (a DX7 electric piano, a Juno pad, a Minimoog
  bass), design from what that sound actually is — its structure and measured
  spectrum, envelopes and velocity response — not from a vague memory. When a
  published reference is not enough, ask the owner for a short dry recording
  (a few notes, soft to hard, low to high).
- **Measure before handing over:** held-chord level (rule 6), clicks (rule 9),
  CPU with the pedal (rule 8), and a dry listen-through of the settings
  (every effect but Reverb off, rule 2).
