# Aurora v0.17 — sound design upgrades

All four sound-design additions are per layer and live under Edit. Existing sounds load with Filter 2 bypassed, direct Mod envelope amount at zero, oscillator modulation Off and Character Off.

## Filter 2

Filter 2 has low-pass, high-pass and band-pass modes, independent cutoff and resonance, and three routes: Filter 1 → 2, Filter 2 → 1, and Parallel. Parallel balance blends the separate filter outputs; it does not change the serial routes. Both filters use state-variable processing. The serial orders can sound alike with static linear settings; Parallel produces a different response.

Sound and Performance matrices can now target Filter 2 cutoff, Filter 2 resonance and Parallel balance. Filter 1's existing amplitude-envelope amount keeps its original behavior.

## Mod envelope

The independent per-note ADSR can directly control Filter 1, Filter 2, Pitch, oscillator modulation amount, Character drive or either wavetable position. Its bipolar Amount adds to the base control. It is also a Sound Matrix source, independent of the direct Amount, allowing multiple destinations. Mono retriggers it; Legato carries it through overlapping notes. Note-off releases it; the amplitude/motion envelope still determines the audible note lifetime.

## Oscillator interaction

Oscillator 2 can phase-modulate, frequency-modulate or ring-modulate oscillator 1. Ratio sets oscillator 2's frequency relationship when modulation is enabled. Lower Oscillator blend to hear the modulated carrier alone; raise Blend to mix oscillator 2 into the output. Both classic and wavetable oscillators are supported, alongside the existing hard sync. Oscillator modulation amount is a matrix destination. Depth is bounded at high pitches to reduce extreme high-frequency artifacts; aggressive audio-rate modulation is not guaranteed alias-free.

## Character

Each layer gets Warm saturation, hard Clip, wave Fold and Crush (bit depth plus sample-rate reduction), with Drive, Tone and wet/dry Mix. Processing sits after the filters and before the amplitude stage, layer balance and FX sends. Character drive is a matrix destination. A dry layer's existing send behavior is unchanged.

New controls are available to custom macros and MIDI Learn, are stored in patches and host state, and participate in patch undo/redo, A/B, layer copy/paste and variation groups. Existing VST3/AU parameter IDs remain unchanged: new layer controls use a separate ID block starting at 6000.

## Output level and scopes

Aurora intentionally attenuates individual voices to reserve headroom for polyphony and layered sounds. Older factory patches also commonly store a 25% master value. This can sound considerably quieter than instruments with hotter factory presets.

Output boost adds 0–24 dB after the master stage, with stereo-linked peak protection at 0.98 full scale. The pre-1.0 reference calibration now defaults to +24 dB and migrates older sessions once, as requested. It stays constant across patches and saves with the standalone session or DAW project. Presets retain their dynamics; dense chords may engage peak protection.

The large scope offers Auto scale and Actual level, with a separate stereo peak reading in dBFS. Auto scale changes only the drawing. Scopes now show the left output instead of averaging left and right, avoiding cancellation from opposing stereo phases. A hard-right signal can therefore appear flat in the waveform while the stereo meter still shows its output.

## Appearance and browsing

Copper Orange retains Copper's background, with orange sliders, macro rings and selected buttons. Selected buttons use dark text; other text remains white. Existing theme preferences remain unchanged.

Every patch browser card has an independent favorite star. Top-right previous/next arrows (also Left/Right keys) follow the displayed category's alphabetical list and wrap at its ends. Selecting a patch scrolls it into view; clicking a star does not load that patch. Clicking outside still closes the browser.

## Validation

- DSP suite: bypass behavior, filter routes, classic/wavetable modulation modes, all Character modes, Mod envelope routing, output boost and extreme-setting finite output pass.
- A pre-upgrade reference render and the upgraded bypass render compare sample-for-sample identically at 0 dB boost.
- +6 dB boost measured +5.99 dB on the reference render (including its startup ramp).
- All 300 JSON factory patches pass hosted state/audio checks; all 312 sounds pass interface coverage.
- New layer state/automation, layer D MIDI Learn, legacy defaults, saving and undo/redo checks pass.
- AU validator passes; VST3 validator reports 47 passed, 0 failed. Native test-host audio, tempo, automation, state and editor checks pass.
- UI layouts were rendered and inspected; the updated standalone app launches as v0.17.

Logic application testing and Ableton save/export testing remain skipped by request because of licensing. No new commercial-host certification is implied.

## Final synthesis refinement

- Both filters: low-pass, high-pass, band-pass, and Notch; independent 12/24 dB selectors. The 24 dB mode cascades two state-variable sections. Existing filter routing remains available.
- Both LFOs: Hz or tempo sync (4 bars through 1/32, dotted eighth and eighth triplet), free-run or per-note retrigger, phase offset, up to eight seconds of delay and fade-in. Delay/fade affect direct destinations, Sound Matrix and PWM. Free-run follows a continuous layer clock; it is tempo-locked in rate, not snapped to DAW song position. Mono retriggers; legato continues.
- Mirror and Quant warp variants are prepared and band-limited outside the render callback. Formant moves harmonics through windowed harmonic multiplication, crossfading adjacent ratios. Tone progressively removes upper harmonics through the existing mip filters. Both shape controls are neutral at zero and are visible in the wavetable preview.
- Sound Matrix: Key Tracking is bipolar around MIDI 60 (one unit per five octaves, clamped); Random is a fixed bipolar value for each note, retained through its release.
- Unison now supports 1–8 oscillator lanes per layer voice, with a shared 256-lane budget (up to 32 note voices at eight-lane unison). Older/releasing voices fade out when the budget is reached, including when unison is increased while notes are held. Higher unison, four active layers, and Formant all increase DSP cost.
- Eighteen appended layer parameters retain existing parameter IDs and participate in preset serialization, macro targets, MIDI Learn, undo/redo, and layer copy/paste. Missing fields select neutral shaping, 12 dB slopes and free-running LFOs.

### Pre-1.0 output calibration

At the user's request, older standalone/plug-in gain settings migrate once to +24 dB. Subsequent adjustments persist normally. Master remains 0–100%, and Output boost remains 0–24 dB; the stereo-linked peak ceiling is 0.98 full scale. No automatic patch normalization or OS volume changes are applied.

Two newly authored Reference sounds are included without deleting existing patches: Copper Focus and Prism Motion. At Master 100%, boost +24 dB, velocity 110, and 48 kHz, sustained single-note stereo RMS measures approximately −13.0/−14.7 dBFS; three-note chords measure −9.3/−10.3 dBFS. Peak ceiling checks pass. These are digital level measurements, not an acoustic match to macOS notifications.

The eight-voice unison budget test rendered 30 seconds of audio (32 notes × 8 unison, four FX, 30 matrix routes, 44.1 kHz/128 frames) in 12.01 seconds. The 99th-percentile callback was 1.246 ms against a 2.902 ms deadline. This is an offline benchmark, not a guarantee against device underruns at every setting.
