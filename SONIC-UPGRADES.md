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

Output boost adds 0–18 dB after the original master stage, with stereo-linked peak protection at 0.98 full scale. It defaults to +6 dB for standalone sessions without a saved boost and new plug-in instances. It stays constant while browsing patches, saves with the standalone session or DAW project, and can be automated in a DAW. Old DAW projects missing this field restore at 0 dB to preserve their original level. This is a gain control, not automatic loudness normalization; presets retain their relative dynamics. Heavy boost on dense chords can engage the peak protection.

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
