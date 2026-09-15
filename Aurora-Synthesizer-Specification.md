# Aurora — Mac synthesizer specification

Version 1.0 · 14 September 2026 · Working product name

**A custom instrument for your MacBook Air M3 with 8 GB RAM, controlled by your M-Audio Oxygen Pro 25, Yamaha CK88, and Yamaha MODX7+.** Open the app, choose a sound, and play. Eight musical controls make everyday adjustments easy; a deeper editor exposes the full synthesizer.

This document specifies the full product. A native first playable build now exists at `build/Aurora.app`; see `README.md` for implemented features and verified checks. The earlier interface concept remains a simulation. Feature counts, performance figures, and release gates below describe the larger release unless marked otherwise.

## 1. Product decisions

| Decision | Specification |
|---|---|
| Main experience | Standalone macOS app; a DAW is unnecessary for playing, sound design, or quick recording. |
| Primary use | Home playing and sound creation, with reliable keyboard response and easy recall. |
| Sound structure | Four layers, each with its own sound, effects, key range, and MIDI assignment. |
| Everyday controls | Eight macros, preset browser, layer mixer, tempo, output level, and Stop all notes. |
| Deeper controls | Oscillators, filters, envelopes, modulation, effects, and arpeggiators. |
| Connections | Three simultaneous USB MIDI controllers; one selected stereo audio output. |
| Platform | Native Apple silicon app. Primary qualification: your MacBook Air M3, 8 GB, current macOS 26.x. Other macOS versions require separate qualification. |
| Working model | Local presets and recordings; offline use with no account required. |
| Later expansion | FM, sample/granular synthesis, hardware audio capture, and AU/VST3 instrument versions. |

Your Mac and three controller models are confirmed. You describe macOS as the latest version; this task's local host reports 26.6.2. Record the exact OS/driver versions again when testing a build. Headphones/speakers, existing hub/interface, and pedal models remain unspecified; the first build must work without requiring an additional audio interface.

For the 8 GB Mac, target less than **600 MB steady-state resident memory**, less than **1 GB peak** during preset switching, and less than **300 MB installed size** for the first release. These are validation budgets. Default to a 64-layer-voice cap and Performance quality; expose the 128-voice ceiling as an advanced option. Sample expansion must use bounded caching and background streaming.

## 2. Your physical setup

**Connect each keyboard to the Mac individually.** For the two Yamahas, use a USB-C–to–USB-B data cable: USB-C at the MacBook, USB-B at the instrument’s **USB TO HOST** connector. Their USB TO DEVICE ports are not the computer connection. Yamaha’s computer connection guide explicitly covers USB-B–to–USB-C cables. [Yamaha connection guide](https://manual.yamaha.com/mi/common/computer/en/computer_en_rm_y0_04.htm)

```text
Yamaha CK88       USB TO HOST ── USB-B to USB-C ──┐
Yamaha MODX7+     USB TO HOST ── USB-B to USB-C ──┼─ MacBook → Aurora
Oxygen Pro 25    USB-B port ───── USB-B to USB-C ┘              │
                                                              └─ One audio output
                                                                 → headphones/speakers
```

Use direct Mac ports where available. If ports are insufficient, use a powered USB hub/dock with at least three suitable USB data ports; qualify that exact hub during testing. Power the Yamahas with their normal instrument supplies. The Oxygen Pro 25 also uses USB-B and receives power over USB, so all three keyboards can use USB-C–USB-B data cables or their USB-A cables through a compatible hub. [Oxygen Pro 25 quickstart, p. 2](https://cdn.inmusicbrands.com/m-audio/maudio_documentation/OxygenPro25-QuickstartGuide-v1.3.pdf) M-Audio describes the Oxygen as class-compliant MIDI without a separate driver. [Oxygen Pro FAQ](https://support.m-audio.com/en/support/solutions/articles/69000810614-m-audio-oxygen-pro-series-frequently-asked-questions)

**Oxygen Pro 25 status:** you have confirmed it works with another synth on this Mac. Aurora's native bridge also detected its musical USB MIDI port, and the running app has received MIDI events. The manufacturer support-list omission is therefore a documentation qualification, not a blocker to using your working controller. Pedals, knob mappings, and prolonged playing still need to be checked in Aurora. [M-Audio macOS 26 compatibility](https://support.m-audio.com/en/support/solutions/articles/69000872803-m-audio-macos-26-tahoe-compatibility)

**MIDI carries playing instructions; audio carries the sound you hear.** Aurora generates its own sound on the Mac. Connecting a Yamaha does not copy its sound library into Aurora. Its internal sounds can remain useful alongside the software.

### Verified Yamaha capabilities

Channel directions below are stated from the instrument’s perspective to avoid confusing driver “input/output” labels.

| Instrument | Instrument → Mac audio | Mac → instrument audio | Setup implications |
|---|---|---|---|
| CK88 | Stereo, 24-bit, 44.1 kHz | Stereo, 24-bit, 44.1 kHz | Enable USB MIDI; select its musical MIDI port. USB return can play through CK outputs/speakers. |
| MODX7+ | 10 channels, five stereo pairs, at 44.1 kHz | 4 channels, two stereo pairs, at 44.1 kHz | Set MIDI IN/OUT to USB. Start with its musical Port 1 and a single transmit channel. |

Sources: [CK88 manual, pp. 19, 47–48, 69](https://usa.yamaha.com/files/download/other_assets/2/1547682/CK88_owners_manual_En_E0.pdf), [Yamaha CK connection guide](https://yamahasynth.com/learn/ck-series/connecting-ck/), [MODX+ FAQ](https://usa.yamaha.com/products/music_production/synthesizers/modxplus/faq.html), [MODX+ owner’s manual, p. 55](https://usa.yamaha.com/files/download/other_assets/3/1583913/VFC6440_modx_plus_owners_manual_En_B0.pdf).

Yamaha documents the **Yamaha Steinberg USB Driver** for these computer connections. On the checked download landing page, V3.1.10 supports macOS 14, 15, and 26 on Intel/Apple silicon. Yamaha also specifies a Mac security-policy change for Apple silicon installation; the setup guide must link to Yamaha’s procedure and leave that system change to the user. The product download indexes can lag behind the actual driver page. [Current Yamaha driver and installation guide](https://usa.yamaha.com/support/updates/yamaha_steinberg_usb_driver_for_mac.html)

### Recommended first configuration

1. Connect and power the keyboards; complete Yamaha’s driver installation if needed.
2. Choose **MacBook headphones/built-in output** for the first sound check. Later choose CK88, MODX7+, or an existing audio interface when that is where your headphones or speakers are connected.
3. Enable each keyboard as a MIDI input. Aurora displays its name and flashes an activity indicator when a key is pressed.
4. Start at **44.1 kHz, 128 frames** when a Yamaha is the audio device. Offer 64 frames for lower delay if stable and 256 frames if the system needs more headroom. Use the actual rates/buffers exposed by the chosen device.
5. Load a simple preset, play, test the sustain pedal, and save the setup as “Home keyboards.”

All three MIDI controllers can remain active regardless of the selected audio output. Selecting MODX7+ as output does not prevent CK88 from controlling Aurora.

For CK88: use **MENU → General → MIDI → MIDI Port → USB On**, musical **Port 1**; Port 2 bridges the DIN connectors. Enable **MIDI Control** to transmit supported panel controls. For software-only playing, use **Local Control Off**; keep it on when intentionally combining CK’s internal sound. Leave **USB Audio Loopback Off** for the initial setup. [CK88 manual, pp. 37–38, 48](https://usa.yamaha.com/files/download/other_assets/2/1547682/CK88_owners_manual_En_E0.pdf)

For MODX7+: use **UTILITY → Settings → MIDI I/O → MIDI IN/OUT → USB**. [MODX+ owner’s manual, p. 55](https://usa.yamaha.com/files/download/other_assets/3/1583913/VFC6440_modx_plus_owners_manual_En_B0.pdf) The setup wizard must inspect arriving channels and help choose a single-channel controller configuration. A multi-part Performance can generate notes on several channels; blindly accepting all channels may stack unwanted copies. Use Local Control Off for software-only playing, or keep it on for an intentional hardware/software layer. [Yamaha MIDI settings guide](https://yamahasynth.com/learn/MODX-Series-Synthesizers/mastering-modx-midi-settings-explained/)

For Oxygen Pro 25: begin in **Preset mode** for instrument control. Enable the musical MIDI endpoint first; inspect messages from control/DAW ports before adding them. Provide a custom Aurora mapping, verified by moving each control. Automatic DAW mappings are not a guarantee of automatic control of this custom app. [M-Audio mode and mapping guidance](https://support.m-audio.com/en/support/solutions/articles/69000810614-m-audio-oxygen-pro-series-frequently-asked-questions)

**Combining hardware audio is an optional later workflow.** To capture both Yamaha sound engines simultaneously over USB, support a user-created Aggregate Device after testing the exact combination. Apple requires matching sample rates and appropriate clock/drift-correction settings; use 44.1 kHz for this Yamaha combination. An alternative is both instruments’ analog outputs into one multi-input interface. Neither is required simply to play Aurora with three keyboards. [Apple Aggregate Device settings](https://support.apple.com/en-au/guide/audio-midi-setup/ams094c7edb4/mac)

## 3. Interface and everyday workflow

Three main views: **Play**, **Edit**, and **Routing**. The preset name, selected layer, undo/redo, and Stop all notes remain available across views. Record and audio settings are compact actions in the app chrome.

| View | What the user sees | What it makes easy |
|---|---|---|
| Play | Searchable presets, eight macros, four layer strips, keyboard ranges, favorites, output meter | Find a good sound, adjust its character, blend layers, and play. |
| Edit | One selected layer; Sound, Filter, Motion, and Effects modules; expandable advanced controls | Understand the sound path and edit one thing at a time. |
| Routing | Keyboard cards, source/channel assignments, pedal mappings, audio output, test indicators | See which keyboard plays which layer and diagnose silence. |

**Visual direction:** restrained studio instrument, generous spacing, clear typography, warm neutral surfaces, and one accent color. Provide system/light/dark appearance. A, B, C, and D labels identify layers as well as color. No decorative moving meters that imply real measurements.

Design the main window for approximately 1,180 × 780 logical pixels, resizable to 960 × 640. Support 100–150% interface scaling; collapse the browser into a drawer when needed. Controls have visible units, keyboard focus, accessible names/values, and a numeric-entry alternative to dragging. Target 4.5:1 text contrast and 3:1 control boundaries. Respect reduced motion.

Knobs use vertical dragging, fine adjustment with Shift, double-click reset, and direct value entry. Sliders and envelopes expose the same keyboard-accessible values. Editing a parameter shows a short explanation such as “Brightness opens the filter and adds upper harmonics.”

### Eight macros on the Play screen

| Macro | Musical purpose |
|---|---|
| Brightness | Dark to bright; usually filter cutoff and oscillator balance. |
| Warmth | Clean to rounded; drive and tonal balance. |
| Movement | Still to animated; modulation depth and rhythmic motion. |
| Space | Close to spacious; reverb/delay sends. |
| Attack | Immediate to gently swelling. |
| Release | Short to lingering after the key is released. |
| Width | Centered to wide stereo image. |
| Character | A clearly named, preset-specific change such as “Glass” or “Growl.” |

Play always displays eight **Performance macros**, independent of which layer is selected. They can target parameters across layers. A Sound supplies reusable suggested mappings, visible inside its layer editor; loading it offers to apply those suggestions and preserves unrelated layer assignments. References into replaced sounds are checked and unresolved destinations are visibly disabled. Display the actual destinations on expansion. Unassigned macros are labeled; user presets may rename them. Mapping ranges must avoid sudden loudness jumps.

The Oxygen Pro 25 has eight physical knobs, 16 pads, one fader, and keys with channel aftertouch. Its USB MIDI, MACKIE/HUI, and EDITOR ports have different roles; transport programming is separate from ordinary preset controls. [Oxygen Pro user guide, pp. 11–13, 55, 110](https://cdn.inmusicbrands.com/m-audio/maudio_documentation/Oxygen%20Pro%20Series%20-%20User%20Guide%20-v1.1.pdf)

Proposed Aurora profile: knobs 1–8 control the eight Performance macros; the fader controls the selected layer's level using pickup; pads play notes on a separately assignable channel; aftertouch adds a bounded expressive modulation. A verified custom transport mapping assigns Record to Quick Record and Stop to ending recording. Other transport buttons remain available for explicit user mapping. Do not overwrite the keyboard's saved presets automatically.

### Three essential workflows

**Play immediately:** open the app → last working setup loads → choose “Velvet Horizon” → play CK88 → change Brightness or Space.

**Create a split:** add bass to A and lead to B → choose “Split keyboard” → press the split key → see both ranges → save a Performance. Default boundary: MIDI note 60, with lower notes 0–59 and upper notes 60–127. Middle-C display naming is configurable.

**Use separate keyboards:** choose CK88 → layers A+B; MODX7+ → C; Oxygen Pro 25 → D. Each can transmit on channel 1 without interfering with the others. “All keyboards play this sound” is an explicit alternative.

## 4. Sound engine: first complete release

Every layer contains two oscillator slots, a sub oscillator, noise, filters, envelopes, modulation, an arpeggiator, and effects. A user can keep just one layer active or combine all four.

| Module | Required options |
|---|---|
| Oscillators | Independent analog or wavetable mode per slot; sine, triangle, saw, pulse/PWM; pitch, fine tune, level, phase/retrigger, sync; wavetable position and smooth scanning. |
| Wavetables | At least 32 original/licensed factory tables. Preview shape and position. User table import is later scope. |
| Unison | 1–8 oscillator copies, detune and spread; visible processing-cost indication. |
| Filters | Two per layer; low-pass, high-pass, band-pass, notch; 12/24 dB slopes where applicable, resonance, drive, key tracking; serial/parallel routing. |
| Envelopes | Three ADSR envelopes: amplitude, filter, and assignable; adjustable curve, velocity response, retrigger/legato; envelope times 0.5 ms–30 s. |
| LFOs | Four per layer; sine, triangle, saw, square, random; free-running or tempo-sync, retrigger, fade-in; 0.01–30 Hz or rhythmic divisions. |
| Modulation | 16 routes per layer; source, destination, depth, polarity, curve, bypass. Create by selecting a source then destination; drag is optional. |
| Performance | Mono/poly, legato, note priority, glide, pitch bend, velocity, mod wheel, sustain, expression, channel/poly pressure when supplied. |
| Tuning | Master tuning, layer transpose ±48 semitones, fine tuning ±100 cents. Microtuning is later scope. |

Ship musical starting templates: warm pad, analog bass, expressive lead, pluck, bell, synthetic keys, evolving texture, and rhythmic sequence. Factory patches must be loudness-balanced and useful from moderate playing velocities. Acoustic piano realism belongs to the later sample engine or the connected Yamaha’s own sound.

Target up to **128 simultaneous layer voices** across the instrument, subject to the performance profile. One played note sounding four layers consumes four layer voices. Unison adds oscillator work within each voice. Display active voices and real audio-thread load; do not promise maximum polyphony with every option at maximum.

Use band-limited oscillators, smooth wavetable interpolation, parameter smoothing, stable filters, and denormal/non-finite protection. Voice stealing prioritizes quiet/released voices and uses short fades to avoid clicks. Offer Performance and High Quality modes; never change quality automatically during a held note.

## 5. Effects, rhythm, and recording

Each layer has three reorderable insert slots chosen from chorus, phaser, drive, tremolo, and EQ. Two shared send buses provide tempo-sync delay and algorithmic reverb. A master output stage provides metering, gain, and low-latency overload protection. Effects expose wet/dry, bypass, clear units, and preset recall; bypass transitions must not click.

Each layer’s arpeggiator supports up/down/order/random, octave range 1–4, gate, swing, latch, and up to 32 steps with rest/tie/velocity. Its held-note collection and generated notes retain source ownership when several controllers feed a layer. Removing one source updates that collection without erasing other sources' notes. There is one master tempo. External MIDI clock comes from one explicitly selected source; loss of clock releases generated notes and displays “Clock lost.” Require an explicit transport restart after clock returns. Latch and sustain are separate controls.

**Quick Record** captures Aurora’s master stereo output to 24-bit WAV at the active sample rate. Optionally export incoming notes/controllers to a Standard MIDI File, with separate tracks and source metadata. MIDI capture contains input events, not UI edits or the arpeggiator's generated output. Version 1 does not include an internal MIDI player; exported MIDI may require track assignment elsewhere and does not guarantee reconstruction of the recording. Save an associated Performance snapshot alongside the recording.

Recording writes on a background thread, shows elapsed time and file location, and preserves recoverable audio after a disk error. The first release does not require a timeline editor or hardware audio recording.

## 6. Presets and session safety

Three distinct saved objects:

| Object | Stores |
|---|---|
| Sound | One layer’s engine, modulation, effects, and macro assignments. |
| Performance | Up to four sounds, their mix/ranges, macros, arpeggiators, and logical controller roles. |
| Setup | Physical device identities, role assignments, MIDI mappings, audio device, buffer, and calibration. |

Loading a Sound or Performance must not change the physical audio device, raise the global listening level, or silently remap hardware. Factory sounds are immutable; edits create user copies. A dirty-state indicator, undo/redo, A/B comparison, and recoverable working copy protect experimentation.

Ship at least **128 curated presets**: 24 pads, 20 leads, 20 basses, 20 keys/bells, 16 plucks, 16 textures, and 12 rhythmic sounds. Search by name, type, mood, brightness, and author; support favorites and recent sounds. A preset can be loaded with one action; Save As is always nearby.

Serialize stable parameter IDs and schema versions. Save atomically, retain the last valid version, and validate imports. Recovery restores edited sounds, assignments, tempo, and persistent settings; held voices, sustain state, active latch notes, and recording start inactive. Reconnected hardware uses pickup where applicable. Assets are referenced by stable IDs; later sample packs must report missing files without blocking the UI.

For Performance changes, new notes use the new sound while existing notes keep their original sound until release where resources allow. Keep at most two complete render generations, including inserts and send effects, under one global master stage. Both share the overall voice/CPU/memory budget. On further rapid changes or overload, fade the oldest generation over 20 ms. Bound retained effect tails to 10 seconds. Make this behavior deterministic and testable.

## 7. MIDI and connection requirements

- **Independent sources:** identify endpoints using available stable IDs plus a user alias. Store port and channel filters. Do not match solely on a displayed device name.
- **Correct note ownership:** track source, channel, original note, routed layer, and voice instance. Two keyboards playing the same pitch on channel 1 remain independent. Note-offs follow the mapping used at note-on, even after a split/transpose change.
- **Sustain and expression:** keep controller state per source/channel. Accept CC64, CC11, CC1, pitch bend, and pressure when available. Do not assume every keyboard supplies aftertouch, MPE, or continuous pedal data.
- **MIDI Learn:** select a software control, move a hardware control, confirm its detected source/CC and range. Support inversion, min/max, absolute control pickup, and common relative-encoder modes. Mapping a pedal must not unintentionally remove sustain.
- **Controller profiles:** provide Oxygen Pro 25, CK88, MODX+, and generic setup templates, validated against actual transmitted messages. Do not promise every panel knob or MODX Super Knob works without configuration.
- **Hot-plugging:** reconnect without restarting. Losing one controller releases only its notes and sustain state. Preserve other controllers’ playing.
- **Safe routing:** MIDI echo/output is off by default. No automatic SysEx writes, Yamaha patch changes, or hardware Local Control changes. Show the required hardware steps in setup.
- **Stop all notes:** one persistent control immediately stops voices, arpeggiator/latch state, sustain state, and effect feedback/tails. A device’s own All Notes Off affects only that device/channel.

The diagnostic sequence is visible and testable: **Keyboard detected → MIDI received → notes accepted by a layer → synth producing audio → output selected.** Each failed step has one relevant next action. Audio-device removal pauses output and keeps the session, rather than unexpectedly switching to another speaker.

## 8. Engineering architecture

The first build uses a native **C++ audio engine, SwiftUI interface, and direct Core Audio/Core MIDI integration**, compiled by the Mac's Command Line Tools without third-party dependencies. This replaces the initial JUCE/CMake proposal for the standalone prototype. The engine remains separate from the shell. Reassess a JUCE wrapper when implementing AU/VST3 formats; JUCE documents those targets. [JUCE audio plugin tutorial](https://juce.com/tutorials/tutorial_create_projucer_basic_plugin/)

Use Core MIDI for macOS MIDI integration and Core Audio for device output. Apple exposes hardware MIDI communication through Core MIDI. [Apple Core MIDI documentation](https://developer.apple.com/documentation/coremidi/)

```text
Core MIDI inputs → timestamped event queues → source/channel routing
                                              ↓
                                 A / B / C / D layer engines
                                              ↓
                              layer inserts → sends → master
                                              ↓
                                      Core Audio output

UI ↔ parameter/session model → bounded realtime-safe updates
Preset/sample loading and recording → background workers
```

Audio rendering must not allocate memory, access files/network, wait on UI work, or acquire blocking locks. Preallocate voice/event pools. Use sample-offset MIDI scheduling, bounded queues, smoothed parameter changes, background preset preparation, and an atomic handoff to rendering. Define queue-overflow recovery so dropped events cannot leave stuck notes.

Choose output sample rates from the actual device; support 44.1 and 48 kHz first, with 88.2/96 kHz optional for devices that expose them. Prepare resources before changing rate/buffer; fade and rebuild safely. Release builds require signing/notarization and a clean-machine installation test.

For later AU/VST3 operation, the DAW supplies MIDI, timing, automation, and audio routing. The plugin must not open the standalone hardware connections independently. Preserve stable automation IDs and report any introduced processing latency to the host.

## 9. Acceptance gates

All timing and load targets require measurement on a named Mac, OS, driver, output device, hub/cable arrangement, and preset. They are not measured results from the interface concept.

| ID | Test and pass condition |
|---|---|
| UX-01 | At least 4 of 5 first-time testers reach a playable sound within two minutes after drivers/cables are ready, without a manual. |
| UX-02 | The same testers can create a two-layer sound, make a keyboard split, map a knob, and save a Performance in five minutes. |
| MIDI-01 | CK88, MODX7+, and Oxygen Pro 25 work together; overlapping same-channel/same-pitch notes and pedal releases preserve correct ownership. Qualify Oxygen Pro 25 on macOS 26 before declaring the profile supported. |
| MIDI-02 | Repeated route changes, note-on velocity zero, sustain, overlapping repeated notes, channel modes, and device removal produce no stranded voices. |
| MIDI-03 | Reconnect each controller 20 times; restore its profile when identity is unambiguous and never stop another controller’s sustained notes. |
| MIDI-04 | Two sources feed one arpeggiator with latch/sustain. Disconnect or release one source, then lose/recover clock: preserve remaining ownership and require an explicit clock restart. |
| AUDIO-01 | Thirty-minute benchmark at 44.1 kHz/128 frames: 64 concurrent layer voices, two oscillators each, unison 1, one filter/layer, chorus, shared delay/reverb; zero underruns. Record 99th-percentile callback time, targeting below 70% of its deadline. |
| AUDIO-02 | With a short-attack benchmark sound, target measured MIDI-input-to-analog-output onset below 10 ms at the 95th percentile on the chosen reference rig. Measure 200 events and report driver/output delay separately from buffer duration. |
| AUDIO-03 | Full-path key-to-sound feel is evaluated on each keyboard. Do not present the 128-frame buffer duration of about 2.90 ms at 44.1 kHz as total playing latency. |
| AUDIO-04 | Test both Yamahas as the sole audio device at 44.1 kHz. Check return routing, monitoring, and absence of feedback. Unsupported rates cannot be selected. |
| AUDIO-05 | Two-hour mixed playing/editing/recording run, including worst-case presets: no crash, non-finite output, unbounded memory growth, or stuck notes; overload uses documented voice limits/fades. |
| PERF-01 | On the M3 Air/8 GB, meet the memory/install budgets in Section 1 and repeat the audio benchmark after 30 minutes of sustained load, including the supplied hub configuration. |
| SAVE-01 | Save/reload reproduces all sound parameters, routes, and assets. Interrupted-save tests recover either the old or new valid preset, never a corrupt replacement. |
| UI-01 | Keyboard-only use, VoiceOver names/values, high scaling, light/dark mode, and minimum window size retain access to every essential action. |
| REC-01 | WAV duration/rate/channels match the session; clipping is indicated; simulated disk failure preserves the recoverable recording and leaves playing responsive. |

If the reference rig misses the audio targets, reduce the default voice/unison/effect budget before release. Keep the richer options available only within a clearly communicated processing budget.

## 10. Delivery sequence

| Stage | Deliverable | Completion gate |
|---|---|---|
| 1 — Connection and feel | Native app, all three MIDI inputs, one audio output, simple oscillator patch, per-source sustain, output/device diagnostics | Real keyboards and Yamaha driver tested; no stuck notes; latency baseline recorded. |
| 2 — Playable prototype | Two layers, subtractive engine, eight macros, essential effects, 24 good presets, editable Play/Edit/Routing interface | Home-playing workflows validated with you; audio/UI response accepted. |
| 3 — First complete release | Four layers, wavetable mode, full modulation, arpeggiators, 128 presets, mappings, recording, recovery | Section 9 gates pass on the documented target configuration. |
| 4 — Sound expansion | Four-operator FM with visual algorithms; sampler/granular engine; sample import and library management; microtuning/MPE as supported | Each engine has its own preset, CPU, expression, and asset validation. |
| 5 — Production integration | AU instrument, then VST3; host automation/state; optional hardware input and Aggregate Device workflows | Plugin host compatibility and hardware/audio routing tested independently. |

The first engineering deliverable should be a small native build that you can play from your real keyboards. It will establish the sound, responsiveness, and connection behavior before the larger sound library and advanced engines are developed.
