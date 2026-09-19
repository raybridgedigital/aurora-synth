# Aurora

## Output boost · 0.20.1

House calibration for dual-keyboard use (CK88 / stage piano as the other layer): Output boost defaults to **+9 dB** (was +24). Untouched +24 sessions migrate once; customized boost values are kept. In-app sidebar still shows **v0.20**; bundle metadata is 0.20.1. Master ~50–75% is the intended blend range. See [SONIC-UPGRADES.md](SONIC-UPGRADES.md).

## Interface polish · 0.20

User-created patches show a flag icon only (no “User” label), placed beside the favorite star. Rename/delete uses a three-dot menu without a chevron, including the editor header, patch cards, and library rows. Other ellipsis menus match that style.

## Patch workflow and scrolling · 0.18

The large patch browser now has a dedicated **User Saved** tab with direct batch import and export controls. Import accepts multiple individual preset files as well as JSON preset banks; export writes all user sounds to one portable bank. Long sound-design, library and browser lists use lazy rendering so macOS can maintain native inertial scrolling while Aurora's live meters continue updating.

## Sound design upgrades · 0.17

Edit now includes dual filters, an independent modulation envelope, oscillator phase/FM/ring modulation, and per-layer Character processing. Copper Orange, patch-browser favorites and navigation, output boost with peak protection, and selectable scope scaling are included. Existing patches and DAW parameter IDs are preserved. See [Sound design upgrades](SONIC-UPGRADES.md) for routing, gain behavior and validation details.

## DAW integration · 0.16

Aurora now builds as a native Apple Silicon VST3 instrument for Ableton Live/Cubase and an AU instrument for Logic Pro, alongside the standalone app. Each instance has its own sound engine and project state, with host tempo, automation, MIDI Learn, and the full Aurora editor. Build/install instructions and the exact validation limits are in [DAW integration](DAW-INTEGRATION.md). AU and VST3 validators, the automated host tests, and standalone regression checks pass; Logic application testing and Ableton save/export testing were skipped because of activation/license limits.

## Spectrum — rebuilt 300-sound factory bank

Aurora includes **300 Spectrum factory sounds**, with 30 in each of ten categories. The rebuilt library uses the full synthesis engine: dual filters, independent modulation envelopes, oscillator interaction, per-layer Character, LFO timing and articulation, Mirror/Quant warp, Formant/Tone shaping, and per-note modulation. There are 240 four-layer performances and 60 three-layer sounds. Each has eight custom macros, an XY pad, keyboard-expression routes and separate layer Delay/Reverb sends. No external samples are required.

X transforms timbre; Y shifts the layer balance. The six remaining macros control Motion, Space, Contour, Release, Width and Echo. Centered macro positions preserve each patch's authored settings. Drawable motion uses free or tempo-synced curves for filter, pan and wavetable movement, with destinations chosen per sound. Macro routes avoid base controls replaced by motion. Layer count and unison are restrained for the MacBook Air.

See the [Spectrum catalog](Patch%20Banks/Aurora%20Spectrum%20300%20Catalog.md) for layer roles and playing notes, and the [preset archive](Patch%20Banks/Aurora%20Spectrum%20300%20Patches.zip) for portable copies. Spectrum replaces the older factory bank. Saved user sounds remain separate, with a small User flag in both browsers. The factory count excludes user saves.

## Color themes · 0.14

Use the palette button beside **Sound library** to choose Midnight, Copper, Ocean, Forest, Graphite or Graphite Orange. Themes update immediately across panels, controls, dialogs and graphs with distinct selected/unselected button colors. Graphite Orange keeps Graphite's backgrounds and adds orange sliders and selected buttons with dark text; the other themes retain white button text. Copper is the default. The preference is saved separately in `~/Library/Application Support/Aurora/appearance.json`, so patch loading, patch sharing and Undo do not change the theme.

## XY performance pad · 0.13

In **Play**, the XY pad controls two distinct macros (including custom macro assignments). X moves left to right; Y moves bottom to top. Each axis has adjustable From/To endpoints and Reverse. Center moves both axes to their range midpoints. Release holds the position; the X/Y sliders provide precise and keyboard-accessible adjustment. Selecting the other axis’s macro swaps the assignments. Axis settings and macro values save with the patch, and a drag is one Undo step. The cursor follows the assigned macro values; values outside a restricted axis range appear at its nearest edge. Overlapping custom routes apply X first, then Y. Existing patches use Brightness on X and Movement on Y without changing sound until the pad is moved.

## Creative tools · 0.12

Open **Creative tools…** beside the A/B controls for three tabs:

- **Macros:** customize any of the eight macros, rename it, and add up to 16 layer/shared-control assignments. Each assignment maps macro 0% and 100% to independent endpoints; Reverse swaps them. Custom assignments replace that macro's original behavior. Restore Original restores the factory mapping. Overlapping routes are applied in order, with the last route taking precedence. Assignments travel with presets and participate in Undo/Redo.
- **MIDI Learn:** choose a layer or shared synthesis control and press Learn, then move a hardware knob. Cutoff, envelope, character, wavetable Position/Warp and detailed FX sliders also offer right-click Learn menus. Mappings are specific to the MIDI source, channel and CC; they persist separately from patches. Soft takeover requires crossing the current value after learning, loading a patch or manually editing a mapped control. Sustain and channel-mode CCs are reserved. Wheel/expression CCs still perform their native functions. These controls use the existing 20 Hz UI MIDI polling path, not sample-accurate automation.
- **Variations:** choose an amount and the selected layer or all enabled layers. Lock Oscillators, Filter, Envelopes, Movement, Pitch and FX independently. Pitch, Envelopes and FX start locked. Pitch locks also preserve detune and pitch-targeted LFO settings; protected pitch/volume motion curves are retained. Master/layer levels, enabled layers, splits, routing, tempo and macro assignments are always preserved. Variations alter bounded continuous settings, not sample files or wavetable identities. Undo restores the previous sound; Save As keeps a separate copy.

In **Motion envelope**, Tempo Sync offers quarter-beat through 32-beat lengths (bar labels assume 4/4), following internal or measured MIDI-clock tempo. Each note still starts its own curve; this is tempo synchronization rather than transport-position synchronization. Tempo changes preserve the current curve position. Snap offers 4/8/16/32 divisions for point times; existing points are unchanged until moved.

**My shapes** saves reusable curve points independently of patches. Enter a name and Save New; choose a saved shape to load it, Update to replace its curve/name, or Delete to remove it. Loading a shape preserves the envelope's timing and destination ranges. The library is stored in `~/Library/Application Support/Aurora/motion-shapes.json`. All previous patches and free-time motion envelopes remain compatible.

## Layer mixing and comparison · 0.11

Each layer card now has **S** for Solo and an **…** menu for Copy/Paste. Solo temporarily fades other layers out without changing their enable switches or discarding held notes. Clear Solo restores them; loading another patch clears Solo. Existing shared FX tails can ring out. Solo is an audition state and is not saved into a patch.

Copy/Paste transfers the layer's oscillator/filter/envelope/arp settings, Sound Matrix, motion envelope, Delay/Reverb sends and embedded imported wavetables. Paste supports Undo/Redo, and the clipboard remains available across patch changes. Global FX, keyboard routing and the patch-wide Performance Matrix stay with the destination patch.

The **Delay send / Reverb send** sliders below the layer cards affect the selected layer. They feed separate buses before the shared Chorus/Phaser stage; the existing Delay/Reverb Mix knobs control the returns. Thus a layer with both sends at zero adds no new echo/room energy while another layer remains wet. Old patches default to 100% sends. Delay/Reverb receive the direct layer signal now, so their tails no longer inherit the shared Chorus/Phaser coloration.

Beside the previous/next controls, **B · Edited — compare A** auditions the last saved factory/user patch; **A · Saved — return to B** restores the edited sound. The visible controls and session data retain your edits throughout. Changing a sound control automatically returns to B. Master volume is preserved. Previous/next browse the current sidebar filters alphabetically and wrap at the ends; patch changes remain undoable.

## Drawable motion envelope · 0.10

Open **Edit → Motion envelope**, below the wavetable row, and enable it for the selected layer. Drag points in the graph; double-click the background to insert a point (up to 16). Select a point to change its level or bend the segment toward the next point. Interior points can be deleted. The endpoints stay at the beginning and end of the duration.

**Factory shapes** supplies 16 editable starting points in two complete rows: Swell, Fade Out, Triangle, Sine, Pulse, Pluck, Double Swell, Staircase, Descending Steps, Heartbeat, Bounce, Ripple, Duck & Rise, Ratchet, Bloom and Sample & Hold. Duck & Rise dips then recovers, Ratchet repeats four fading plucks, Bloom slowly opens and closes, and Sample & Hold steps through a fixed varied sequence. Choosing a shape preserves your duration and destination ranges. Sine and pulse are editable point approximations, with short transitions rather than discontinuous volume jumps.

Duration spans 0.1–60 seconds. Every note starts its own envelope; Loop repeats while held, while a non-looping shape holds its last value. Mono mode retriggers; legato continues the current curve. Releasing a note freezes its position and uses the layer's Release setting to fade it out. The playhead represents the most recently started active note. A short onset ramp and smoothed movement reduce clicks.

Enable any combination of Volume, Filter cutoff, Pitch, Pan, Oscillator 1/2 Position and Oscillator 1/2 Warp. Each destination has independent Minimum/Maximum sliders and a reverse button. The graph displays the selected destination's rescaled shape, so a volume floor of 30% lifts its valleys while leaving a 100% ceiling intact. The first point can be moved above that floor independently. Cutoff is displayed and interpolated logarithmically; pitch is a semitone offset and pan spans left to right.

Volume replaces the layer's Attack/Decay/Sustain shaping while retaining Release, velocity, expression and layer/master levels. Other destinations replace their base controls; existing matrix/LFO modulation still adds on top and is bounded by the engine. Wavetable routes require Wavetable mode; Warp needs an active warp mode. Shared FX are not motion destinations in this release.

All settings belong to each patch/layer, including Save As, export/import, session restoration and Undo/Redo. Existing patches default to disabled motion. Complete fixed-size configurations are published atomically without allocation or locks in the render callback.

## Prism — 100 additional performances

The Prism update added 100 sounds to the original 112. Search **Prism** in the Aurora library to find them. Each of the ten existing musical categories receives ten additions, including evolving vocal pads, elastic basses, sync leads, glass keys, metallic plucks, sequenced arps, atmospheric textures, spectral organs, synthetic ensembles and keyboard splits.

Prism uses both wavetable oscillators, per-layer Sound Matrix movement, velocity-to-filter response, mod-wheel scanning and pressure-to-warp control. Layered designs combine complementary timbres; the ten splits divide at MIDI 60. Mono leads and basses use legato glide. Imported audio is not required.

See [the complete Prism catalog](Patch%20Banks/Aurora%20Prism%20100%20Catalog.md) for individual playing suggestions. The grouped ZIP beside it contains all 100 portable presets. The build includes the bank automatically; the existing sounds and user saves remain available.

## Wavetable update · 0.9

In **Edit**, each layer now has two wavetable oscillator panels. Choose **Wavetable**, select a table, and move **Position** to scan between its frames. Oscillator Blend still balances oscillator 1 against oscillator 2. Selecting a classic waveform returns that oscillator to Classic mode; existing patches keep their original sound.

The 24 original tables are grouped into Warm, Vocal, Metallic, Aggressive, Atmospheric and Pure. Both oscillators offer Off/Bend/Sync/Fold warp, phase and random starting phase. Preview curves follow the last rendered note's scan/warp values. Both matrices include oscillator 1/2 Position and Warp destinations; Performance Matrix layer targets remain independent.

**Phase & import → Osc 1 / Osc 2** loads mono or stereo PCM/float WAV tables containing 1–64 consecutive frames of 256, 512, 1024 or 2048 samples. Choose the correct frame size in the file dialog. Stereo is averaged to mono, DC is removed per frame, and the table is peak-normalized. This imports prepared tables, not arbitrary recordings or proprietary Serum/Vital presets. Imported sample data travels inside saved/exported patches, session recovery and Undo/Redo.

Tables and warped variants are prepared outside the audio callback with frequency-dependent mip levels and interpolated frame/warp scanning. Position and Warp controls are smoothed. Bank replacement retains old memory until the render callback has finished using it. This is a focused wavetable instrument feature set; it does not include a spectral editor, resynthesis or full Serum/Vital compatibility.

A native standalone synthesizer for Apple silicon Macs, built around playing and creating sounds with USB MIDI keyboards. This project targets your MacBook Air M3 with 8 GB of RAM, M-Audio Oxygen Pro 25, Yamaha CK88, and Yamaha MODX7+.

This development build includes wavetable oscillators, drawable motion envelopes, creative tools, an XY performance pad and 300 Spectrum factory sounds. The [full product specification](Aurora-Synthesizer-Specification.md) describes the larger release.

## Hold, clock and recording · 0.8

The performance bar below the layer strips provides Hold, a MIDI clock source selector, and Record / Stop recording. Hold latches released notes, including the chord feeding an arpeggiator. Turn it off to release latched keys; a physically held key or sustain pedal still owns its notes. Panic, audio stop and patch changes clear Hold. It adds notes until released, rather than automatically replacing a latched chord.

Select a connected MIDI input under Clock to follow its 24-pulse-per-quarter-note timing. Arpeggiator steps follow incoming pulses; delay follows the measured tempo. MIDI Start resets the pattern, Stop releases arpeggiator notes, and Continue resumes. A half-second clock timeout stops the arpeggiator and shows Waiting / stopped. Select Internal to return to the patch tempo. Supported tempo is 30–240 BPM; MIDI is applied at audio-block boundaries. Clock and Hold start disabled each app session. These paths are tested with synthetic MIDI events; physical keyboard clock output still needs verification with the sending device configured to transmit clock.

Record captures Aurora's final stereo output (including FX and Master) to 24-bit WAV at the current output sample rate. Since 0.8.1, files are saved in `~/Desktop/Aurora`; Show WAV reveals the completed file. After Stop, a background pass normalizes the stereo-linked sample peak to −3 dBFS, preserving channel balance and duration. Silence remains silent. The original file is replaced only after normalization succeeds; failures retain the unnormalized WAV. Normalization adjusts level and cannot repair distortion already in the sound.

Recording uses Core Audio's preinitialized asynchronous writer and finalizes on Stop, audio shutdown, or app quit. A take stops automatically at one hour to stay within WAV size limits at supported sample rates. Errors are shown in the performance bar. This captures the synth output, not microphone input or a Yamaha's internal audio.

## Expression and effects · 0.7

Edit now includes per-layer Poly, Mono, and Legato modes, overlapping-note glide (0–2 seconds), and a pitch-bend range of ±0–24 semitones. Mono retriggers the envelope from its current level; Legato preserves the envelope. Both use last-note priority separately for each keyboard/channel and return to a held note when the latest key is released. Glide applies to connected mono/legato notes; the arpeggiator keeps its own note/gate behavior. Routing offers Linear, Soft touch, Hard touch, and Fixed (velocity 100) curves saved per MIDI input, independently of patches.

The FX detail row adds phaser rate/depth/signed feedback, chorus rate/depth, and reverb size/approximate decay (0.2–8 seconds). Delay offers quarter, eighth, sixteenth, half, dotted eighth/quarter, and triplet eighth/quarter timing, synced to the header tempo. FX remain shared across the patch. New settings participate in Save, Save As, import/export and undo/redo. Old patches default to Poly, no glide, ±2-semitone bend, and quarter-note delay.

## Sound design and saving · 0.6

Each layer now has pulse width and LFO 1 pulse-width modulation, one to four unison voices with detune and stereo spread, and oscillator 2 sync with a tuning control. These controls occupy an additional three-panel row without enlarging existing panels. PWM follows LFO 1's waveform and rate independently of its main depth control. Sync resets oscillator 2 from oscillator 1 and smooths the reset discontinuity; it is not fully alias-free. Four-voice unison uses more CPU; the engine still supports 64 played layer voices.

Assigned Matrix destinations show slim modulation indicators; each Matrix row also shows its current signed contribution. Polyphonic feedback represents the most recently rendered note, rather than every note's modulation range. Feedback updates independently of the main interface model.

Save updates an existing user sound; Save As creates a separate copy with an editable category. Saving a factory sound opens Save As. Rename / category edits saved details without discarding current sound edits. Deleted sounds remain in the Deleted sounds collection and can be restored individually across app restarts. Existing patches use neutral oscillator defaults until the new controls are changed.

## Build and run

Requirements: an Apple silicon Mac, macOS 14 or newer, and Apple's Command Line Tools with a macOS SDK and Swift compiler. No third-party libraries, package downloads, or paid developer account are required for a local build.

From this project folder:

```sh
./scripts/build.sh
open build/Aurora.app
```

The build validates and assembles the patch recipes, then compiles the C++ engine, Objective-C++ Core Audio/Core MIDI integration, and SwiftUI interface. It creates `build/Aurora.app` and an `Aurora.zip` archive, and signs the app with a local ad-hoc signature. It does not install the app elsewhere or launch it automatically. The bundle is not a notarized distribution release. The ZIP excludes Finder metadata that a synced Documents folder can attach to app directories.

## Interface update · 0.3

Typography is larger throughout: control labels are 15 pt, secondary text is 12–14 pt, panel titles are 19 pt, and the current sound title is 36 pt. The default window is 1480 × 940 points with a minimum width of 1260 points, and can be zoomed to the available screen space on a 15-inch MacBook Air. All three editor rows have three equal-width panels; delay and chorus/reverb have their own panels.

The app keeps native macOS scrolling and momentum. Live meters publish into a separate observable object instead of invalidating the entire interface. Stable audio status/device lists do not republish; routine refresh uses device-change notifications; unchanged sessions are not repeatedly written; maintenance is deferred during native event tracking. Eager panel/library layouts avoid estimated scroll heights. These changes reduce avoidable scroll work, but do not establish measured frame-rate parity with Safari.

The interface regression check passed: 20 stable polls and 1,200 changed telemetry samples caused zero main-model publications, and 1,200 repeated samples caused no extra meter publications. Both original and expansion presets were found in the combined 112-sound collection. Run `bash check-interface.sh` after building to reproduce the check. It initializes macOS UI/MIDI facilities and exercises saving in a temporary test directory; it never starts audio or edits your saved sounds.

## First playing session

1. Connect the Oxygen Pro 25 or a Yamaha's USB TO HOST port to the Mac using a suitable USB data cable. Use your already working Oxygen configuration as the first test.
2. Open Aurora and choose the audio output connected to your headphones or speakers. MacBook built-in output is a useful starting point.
3. Enable the keyboard's musical MIDI input and route it to the desired layers. Select one transmit channel when a MODX Performance sends notes on multiple channels.
4. Start audio, choose a sound, and play. Start with a 128-frame buffer; use 256 if playback crackles. Confirm the displayed actual buffer and sample rate because the audio device decides what it supports.
5. Use Stop all notes if a note remains held, and stop audio before changing the physical listening setup.

All three controllers can supply MIDI independently of the selected audio output. Yamaha internal sounds remain inside the instruments; Aurora generates its own audio. Yamaha output devices require the appropriate working macOS audio driver. See the specification's linked Yamaha instructions for hardware settings and connections.

The Oxygen Pro 25 has been detected by Aurora, and hardware MIDI events have reached the running app.

## Aurora 100 sound bank

Choose **Aurora** in **Sound library**, then use the category menu to browse ten sounds in each of these groups:

| Category | Character |
| --- | --- |
| Pads | Slow analog beds, airy harmonics, layered swells |
| Bass | Sub, acid, pulse, plucked, and moving basses |
| Leads | Rounded, bright, breathy, octave, and fifth voices |
| Keys | Synthetic electric keys, bells, clav-like and poly sounds |
| Plucks | Wood, glass, wire, and short electronic attacks |
| Arps | Different directions, divisions, gates, octave spans, and layered patterns |
| Textures | Noise, drones, random filter motion, and stereo movement |
| Organs | Synthesized flute, reed, octave, fifth, and percussion registrations |
| Brass & Strings | Synthesized brass attacks and bowed ensemble colors |
| Splits | Left/right combinations divided at MIDI note 60 |

All 300 Spectrum sounds are bundled under **Aurora**. **Your sounds** contains saved and imported copies, visibly marked User; **All sounds** brings the collections together. Search matches names, categories, and descriptions. Favorites apply within the selected collection and category. Saving or importing a sound keeps its category and opens Your sounds.

The [complete catalog](<Patch Banks/Aurora 100 Catalog.md>) describes every sound. The [grouped patch archive](<Patch Banks/Aurora 100 Patches.zip>) contains individual `.aurora.json` files for import or backup. It does not need to be imported into the updated app.

Arps play while you hold notes. Splits use MIDI notes 0–59 for the lower voice and 60–127 for the upper voice. On the Oxygen Pro 25, use its octave controls to reach either side, or route another keyboard to the same layers. The CK88 and MODX7+ provide more space for two-hand split playing. These are synthesized sounds, not acoustic instrument samples or Yamaha internal voices. Patch loading preserves the current Master volume.

## First milestone scope

- Four sound layers with level, pan, transpose, and keyboard ranges.
- Two oscillators per layer, sub oscillator, noise, filter, amplitude envelope, and drive.
- Two LFOs per layer, with selectable destinations for sound movement.
- Per-layer arpeggiators with rate, direction, octave range, and gate controls.
- Shared chorus, delay, and reverb controls.
- Core MIDI input routing, sustain and expressive controllers, MIDI activity, and Stop all notes.
- Native audio device selection, a choice of buffer sizes, and audio/voice activity displays.
- 112 factory performances, grouped collection/category browsing, favorites/search, user preset saving, JSON import/export, and automatic session recovery.
- Eight musical macros with source-specific MIDI Learn and hardware pickup.
- On-screen piano and typing-key auditioning.

Aurora has two LFOs per layer, dual filters, wavetable scanning, per-layer effects sends and AU/VST3 plug-ins. The fifth classic oscillator shape is an original harmonic blend. Filter 1 retains its amplitude-envelope amount, alongside the independent Mod envelope. Standalone MIDI is applied at audio-block boundaries; VST3 MIDI honors host sample offsets. Hardware audio capture remains outside this build. Exact controller-panel mappings depend on the messages each keyboard sends.

## Verification

```sh
./scripts/test.sh
./scripts/test.sh --bridge
bash scripts/audit_patch_bank.sh
```

The first command builds and runs the offline C++ engine tests without opening an audio device. The optional `--bridge` mode also runs a read-only device enumeration probe when its source is present. It does not play audio or change system audio settings.

The patch audit assembles the bank and renders all 100 patches through the real engine at 48 kHz, checking unique names and settings, categories, finite output, audible output, release behavior, eight-note velocity-127 chords for eight seconds, and Stop all notes. It writes `build/patch-audit-report.json`. All 100 passed with no duplicate audio hashes; the highest tested stress peak was 0.1671 at the bank's 25% reference Master. Short plucks naturally have a lower average level over a four-second held note. This is an automated audio check, not a subjective listening review or a measurement of hardware latency.

Automated checks cannot establish how the instrument feels and sounds on the physical setup. Hardware validation still needs notes and pedals from each keyboard, three-controller routing, USB disconnect/reconnect, selected-output playback, and a sustained listening/load session on this M3 Mac. The specification's latency, memory, and thirty-minute stability targets are validation goals, not measurements from this first milestone.

Verified for this build:

- Native compilation, bundle metadata, and local code-signature checks passed.
- Offline tests passed for audio generation, release, per-source/channel sustain, routing, transpose, disconnection, arpeggiators, concurrent MIDI producers, overflow recovery, finite extreme controls, and 64 voices.
- A 30-second offline render at 44.1 kHz/128 frames with 64 voices and three effects completed in 1.529 seconds; p99 callback time was 176.6 microseconds. This is an offline DSP benchmark, not measured keyboard latency or an underrun guarantee.
- The native bridge detected Oxygen Pro 25 USB MIDI and kept DIN, Mackie/HUI, and Editor ports disabled by default.
- A muted native audio test passed on MacBook Air Speakers at 44.1 kHz/128 frames, with a live synth voice processed by the output callback.
- The running app's Play/Edit/Routing views were inspected; loading a preset and playing an on-screen note changed the live voice count. The app subsequently received hardware MIDI events.
- Version 0.2's bundled 100-sound bank, ten categories, search, empty-search state, and split-preset loading were checked in the native app. The original 12 sounds and existing user data were retained.

User presets and session settings live in `~/Library/Application Support/Aurora/`. Restarting restores sounds and routes with audio stopped; it does not resume held notes or start playback automatically.

## Source layout

| Path | Purpose |
| --- | --- |
| `Sources/AuroraApp.swift` | Native SwiftUI application and controls |
| `Sources/AuroraBridge.h` | C interface shared with Swift |
| `Sources/MacAudioMIDI.mm` | Core Audio output and Core MIDI device integration |
| `Sources/SynthEngine.hpp` and `.cpp` | Portable C++ synthesis engine |
| `Tests/` | Offline engine checks and optional device probe |
| `Resources/Info.plist` | Local macOS application metadata |
| `Resources/PatchRecipes/` | Authored sound designs used by the bank assembler |
| `Resources/Aurora100.json` | Complete bundled factory expansion |
| `Patch Banks/` | Grouped portable presets and the full catalog |
| `scripts/` | Reproducible build and verification commands |

The interface and hardware integration use Apple frameworks directly; the first milestone does not use JUCE or CMake.

## Interface update · 0.4

Performance controls now live in the header: master volume (0–100%), speaker toggle, Stop all notes, MIDI/DSP readout, tap tempo, and global transpose (±24 semitones). The footer and output scope are removed. Global transpose survives patch changes and session restore; existing listening volume is preserved.

Layer cards select on their background and offer oscillator-one waveform menus. Sound design uses three equal-height panels per row, per-layer octave steps, and arpeggiator pattern/division buttons. Factory harmonic intervals are preserved when changing octaves. Sound-library rows have full-width hit areas; saved sounds have a ••• menu for Rename and Delete. The library menu offers Undo Delete for the most recently deleted sound, including after restart.

## Modulation matrices · 0.5

Open **Matrix** beside Play, Edit and Routing. Enable a slot, choose its source and destination, then move Amount away from zero. Six Sound Matrix slots are stored independently for each layer; select A/B/C/D without leaving Matrix. Six Performance Matrix slots are shared by the patch, with A/B/C/D/All targets for layer parameters. All assignments support saving, export/import, Undo/Redo, bypass, and slot reset. Old patches start with disabled slots.

Sound sources: LFO 1, LFO 2 (full waveform, independent of each Depth slider), and the per-voice amplitude envelope. Destinations: cutoff, pitch, pan, amplitude, oscillator blend, and drive. Performance sources: mod wheel, note velocity, channel pressure, expression pedal, sustain pedal, and a selectable MIDI CC number (0–127). Performance destinations add LFO 1/2 depth, chorus, phaser, reverb and delay mix. Shared FX always target the whole patch and use the latest received value across keyboards; layer destinations use the note's own MIDI source/channel. Existing wheel vibrato, expression, sustain, and macro MIDI Learn still operate.

Amount is bipolar and additive. 100% corresponds to four octaves for cutoff, 12 semitones for pitch, and one normalized unit elsewhere. Bounds protect the resulting parameter. Routes are published atomically and evaluated in the audio engine without locks or allocation; UI meter/scope updates remain separate from the main interface.

### Final synthesis refinement

Both filters now offer Notch and 12/24 dB slopes. Each LFO has tempo sync, per-note retrigger/free-run, phase, delay and fade. Wavetables add Mirror/Quant warp and separate Formant/Tone shaping. Sound Matrix adds Key Tracking and per-note Random. Unison extends to eight voices with a shared oscillator budget. New Reference sounds—Copper Focus and Prism Motion—provide the basis for +24 dB default output calibration. All previous sounds remain installed. See SONIC-UPGRADES.md for behavior and measured levels.
