# Patch Design Rules — KiMiA factory sound

**Audience:** any AI (or human) authoring factory patches. Read this before
creating or editing patches. Enforced where noted by
`scripts/assemble_modx_bank.py`; everything else is review-checked.

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

## 2. Delay ships OFF by default; only Reverb may ship ON — except FX-flavored sounds

Delay is part of the sound design — patches that call for it carry fully
authored delay parameters (mix, feedback, timing, tone, ducking) — but the
delay power toggle ships OFF by default in every category. If the player
wants delay, one toggle restores the factory-designed delay for that patch.

Exception: **Sound FX** and **Musical FX** may ship delay ON, where the
echo is inseparable from the designed character (e.g. Laser Drawer,
Arp Botanica). Everywhere else, Reverb is the only insert FX that may ship
powered ON. Rule 5 still applies: everything not featured stays off.

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

## 4. Categories

15 Yamaha MODX mains (Drum/Perc intentionally skipped — hits don't fit a
held-note synth audit) plus `FM EP` for pure electric pianos:
Piano, Keyboard, Organ, Guitar, Bass, Strings, Brass, Woodwind, Syn Lead,
Pad/Choir, Syn Comp, Chromatic Perc, Sound FX, Musical FX, Ethnic, FM EP.
New `SoundPreset.category` strings outside `FactoryBank.categoryOrder` sort
after the known ones — no app change needed for new categories.

## 5. FX power discipline

Every patch features 1–3 insert FX with explicit power toggles; all other
FX powers are OFF. A closed gate must be exact silence (see rule 6), so
unused FX cost nothing and leak nothing. All ten insert FX should be
featured somewhere across the bank.

## 6. Every patch must be audible AND panic-clean

- Audible: renders measurable energy on standard audition notes
  (`Tests/PluginCoreChecks.mm`, `Tests/V1FactoryAudioAudit.mm`).
- Panic-clean: after panic + 0.4 s drain the bus reaches EXACT zero.
  Only states cleared in `SynthEngine::clearFxRingsAndFilters` (plus
  self-draining paths) qualify — wah filter states, flanger buffers and
  bitcrusher holds were added for exactly this reason. Any newly featured
  DSP state must be added there too.
- Peak headroom: hold peaks well under 1.0; stress (8 notes @ 127, master
  100%) must stay finite and unclipped. Calibrate against the GB109 house
  band (hold RMS roughly 0.008–0.035).

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
