# Aurora

A native standalone synthesizer for Apple silicon Macs, built around playing and creating sounds with USB MIDI keyboards. This project targets your MacBook Air M3 with 8 GB of RAM, M-Audio Oxygen Pro 25, Yamaha CK88, and Yamaha MODX7+.

This is the playable 0.5 development milestone, including Aurora 100, a categorized bank of 100 new sounds. The [full product specification](Aurora-Synthesizer-Specification.md) describes the larger release; several of its advanced features remain future work.

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

The interface regression check passed: 20 stable polls and 1,200 changed telemetry samples caused zero main-model publications, and 1,200 repeated samples caused no extra meter publications. Both original and expansion presets were found in the combined 112-sound collection. Run `bash check-interface.sh` after building to reproduce the check. This read-only test initializes macOS UI/MIDI facilities but never starts audio or saves preset/session edits.

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

All 100 expansion sounds and the original 12 are bundled together under **Aurora**, for 112 factory sounds total. There is no separate Starter sounds collection. **Your sounds** contains saved and imported copies; **All sounds** brings the collections together. Search matches names, categories, and descriptions. Favorites apply within the selected collection and category. Saving or importing a sound keeps its category and opens Your sounds.

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

The complete specification's four LFOs, dual filters, full modulation matrix, wavetable library/scanning, step editing/latch/external clock, expanded effects, recording, and AU/VST plug-ins are later milestones. The current fifth oscillator shape is an original harmonic blend. The amplitude envelope also drives the filter envelope amount; a separate filter ADSR is later scope. Pitch bend currently uses a fixed ±2-semitone range. MIDI is applied at audio-block boundaries. Hardware audio capture is outside this first build. Exact controller-panel mappings must be checked against the messages each keyboard sends.

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
