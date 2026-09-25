#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum AuroraParameter {
    APEnabled=0, APWave1, APWave2, APBlend, APDetune, APSub, APNoise,
    APCutoff, APResonance, APAttack, APDecay, APSustain, APRelease,
    APLevel, APPan, APTranspose, APLFORate, APLFODepth, APLFODestination,
    APLFOShape, APFilterEnvelope, APDrive, APArpEnabled, APArpRate,
    APArpMode, APArpOctaves, APArpGate, APKeyLow, APKeyHigh,
    APLFO2Rate, APLFO2Depth, APLFO2Destination, APFilterType, APLFO2Shape,
    APPulseWidth, APPWMDepth, APUnison, APUnisonDetune, APStereoSpread,
    APSync, APSyncTune, APVoiceMode, APGlide, APBendRange,
    APWT1Enabled, APWT1Table, APWT1Position, APWT1WarpMode, APWT1Warp,
    APWT1Phase, APWT1RandomPhase,
    APWT2Enabled, APWT2Table, APWT2Position, APWT2WarpMode, APWT2Warp,
    APWT2Phase, APWT2RandomPhase,
    APFilter2Enabled, APFilter2Type, APFilter2Cutoff, APFilter2Resonance,
    APFilterRouting, APFilterBalance,
    APModAttack, APModDecay, APModSustain, APModRelease, APModAmount, APModDestination,
    APOscModMode, APOscModAmount, APOscModRatio,
    APCharacterMode, APCharacterDrive, APCharacterMix, APCharacterTone, APCharacterBits, APCharacterRate,
    APFilter1Slope, APFilter2Slope, APLFO1Sync, APLFO1Division, APLFO1Retrigger, APLFO1Phase, APLFO1Delay, APLFO1Fade, APLFO2Sync, APLFO2Division, APLFO2Retrigger, APLFO2Phase, APLFO2Delay, APLFO2Fade, APWT1Formant, APWT1Tone, APWT2Formant, APWT2Tone,
    APArpSwing, APArpVelocityShape,
    APLFO3Shape, APLFO3Rate, APLFO3Depth, APLFO3Sync, APLFO3Division, APLFO3Retrigger, APLFO3Phase, APLFO3Delay, APLFO3Fade,
    APLFO4Shape, APLFO4Rate, APLFO4Depth, APLFO4Sync, APLFO4Division, APLFO4Retrigger, APLFO4Phase, APLFO4Delay, APLFO4Fade,
    APLFO5Shape, APLFO5Rate, APLFO5Depth, APLFO5Sync, APLFO5Division, APLFO5Retrigger, APLFO5Phase, APLFO5Delay, APLFO5Fade,
    APParameterCount
};
// Parameter units: cutoff Hz; envelopes seconds; rate Hz; detune cents;
// level/sub/noise/blend/resonance/depth/drive/sustain 0...1; pan -1...1;
// wave 0 sine / 1 triangle / 2 saw / 3 pulse / 4 harmonic blend;
// LFO destination 0 cutoff / 1 pitch / 2 pan / 3 amplitude;
// filter 0 lowpass / 1 highpass / 2 bandpass. Arp rate 0=1/4, 1=1/8,
// 2=1/8T, 3=1/16, 4=1/16T, 5=1/32; mode 0..29 (0..3 keep old Up/Down/UpDown/Random).
enum AuroraGlobal { AGMaster=0, AGTempo, AGDelayMix, AGDelayFeedback,
    AGReverbMix, AGChorusMix, AGPhaserMix, AGPhaserRate, AGPhaserDepth,
    AGPhaserFeedback, AGChorusRate, AGChorusDepth, AGReverbSize, AGReverbDecay,
    AGDelayTiming, AGOutputGain,
    /* 0.20.8 delay refinements */
    AGDelaySync, AGDelayTimeMs, AGDelayPingPong, AGDelayTone,
    /* shared insert EQ (dB bipolar, always on) */
    AGEqLow, AGEqMid, AGEqHigh,
    /* full shimmer shared return */
    AGShimmerMix, AGShimmerPitch, AGShimmerDecay, AGShimmerTone,
    AGShimmerPredelay, AGShimmerAmount,
    AGShimmerVoice1, AGShimmerVoice2, AGShimmerVoice3,
    AGShimmerReverse,
    AGShimmerEarlyLevel, AGShimmerEarlySize,
    AGShimmerLateLevel, AGShimmerLateDecay,
    /* 0.25.0 effect expansion */
    AGFlangerMix, AGFlangerRate, AGFlangerDepth, AGFlangerFeedback,
    AGTremMix, AGTremRate, AGTremDepth, AGTremMode,
    AGCrushMix, AGCrushBits, AGCrushDownsample,
    AGDuckAmount, AGDuckRelease,
    AGCompThreshold, AGCompRatio, AGCompAttack, AGCompRelease, AGCompMakeup, AGCompAuto,
    AGWahMix, AGWahSensitivity, AGWahRange, AGWahMode,
    /* Master FX power (bypass) toggles: 1 = in the chain, 0 = struck from it.
       Shared returns (shimmer, delay, reverb) and master inserts (chorus, phaser,
       flanger, tremolo, bitcrusher, auto-wah, compressor) each own one toggle.
       Append-only: these IDs trail the v0.25.0 block so every earlier ID and every
       saved patch fx key keeps its meaning. The Play-screen house EQ is excluded —
       it is session-sticky, identity at 0 dB, and its bands are not patch data. */
    AGShimmerPower, AGDelayPower, AGReverbPower, AGChorusPower, AGPhaserPower,
    AGFlangerPower, AGTremPower, AGCrushPower, AGWahPower, AGCompPower,
    AGGlobalCount };
// Main-thread API; MIDI receive and audio rendering run on platform threads.
void aurora_initialize(void);
void aurora_shutdown(void);
void aurora_refresh_devices(void);
const char *aurora_audio_devices_json(void);
const char *aurora_midi_sources_json(void);
const char *aurora_status(void);
int aurora_start_audio(uint32_t deviceID, uint32_t bufferFrames);
void aurora_stop_audio(void);
int aurora_audio_running(void);
uint32_t aurora_current_device(void);
double aurora_sample_rate(void);
uint32_t aurora_buffer_frames(void);
void aurora_set_parameter(int layer,int parameter,float value);
float aurora_get_parameter(int layer,int parameter);
// Per-layer FM engine payload (spec FUTURE-PROPOSAL-FM-ENGINE.md §7): kFmParamCount = 96
// floats, layout documented in FmEngine.hpp (8 globals + 4 operators x 22 fields).
// All zeros / absent => engine mode Subtractive.
void aurora_set_layer_fm(int layer,const float* data,int count);
// bank 0...3: sound layer; bank 4: performance; target 0...3 or 4=all.
void aurora_set_matrix(int bank,int slot,int enabled,int source,int destination,int target,int cc,float amount);
int aurora_set_motion(int layer,const float* data,int count);
float aurora_motion_phase(int layer); // -1 while idle; most recently started note
void aurora_layer_sends(int layer,float delay,float reverb,float shimmer);
void aurora_solo_layer(int layer);
void aurora_set_transpose(int semitones);
void aurora_set_global(int parameter,float value);
float aurora_get_global(int parameter);
// MIDI channel: 0 all, 1...16 specific. layerMask bits A=1/B=2/C=4/D=8.
void aurora_route_source(int32_t sourceID,int layerMask,int channel);
void aurora_velocity_curve(int32_t sourceID,int curve); // linear, soft, hard, fixed
void aurora_hold(int enabled);
void aurora_clock_source(int enabled,int32_t sourceID);
float aurora_clock_tempo(void); // zero while waiting or stopped
int aurora_record_start(const char *path);
int aurora_record_stop(void);
int aurora_normalize_recording(const char *path);
int aurora_recording(void);
double aurora_record_seconds(void);
void aurora_note_on(int note,int velocity); // on-screen source reserved ID=0
void aurora_note_off(int note);
void aurora_panic(void);
float aurora_output_peak(void);
float aurora_comp_gr(void); // compressor gain reduction in dB (0 = inactive)
int aurora_copy_scope(float *samples, int capacity);
int aurora_copy_modulation(float *values, int capacity);
// Wavetable indices 0...23 are built-in; 24 selects the imported table.
// Import/previews run on the main thread, never the audio callback. Oscillator is 0 or 1.
int aurora_set_custom_wavetable(int layer,int oscillator,const float *samples,int frames,int frameSize);
void aurora_clear_custom_wavetable(int layer,int oscillator);
int aurora_copy_wavetable_preview(int layer,int oscillator,float *samples,int capacity);
const char *aurora_wavetable_name(int index);
const char *aurora_wavetable_category(int index);
int aurora_read_wavetable(const char *path,int frameSize,float *samples,int capacity,char *error,int errorCapacity);
float aurora_cpu_load(void); // audio callback duration / deadline, 0...1
// Core Audio processor overloads (audible dropouts) reported for the output device since audio
// last started. The DSP meter is a smoothed average, and dropouts begin before it reads 100%.
uint64_t aurora_audio_overloads(void);
void aurora_reset_audio_overloads(void); // the player acknowledged the count; start again from zero
int aurora_active_voices(void);
uint64_t aurora_midi_event_count(void);
// Last received CC packed: [source index unused][channel:8][cc:8][value:8].
// Return -1 when no CC has arrived; counter distinguishes repeated values.
int64_t aurora_last_cc(void);
int32_t aurora_last_cc_source(void);
uint64_t aurora_cc_count(void);
uint64_t aurora_last_cc_snapshot(void); // source ID high32; channel/CC/value low24; UINT64_MAX empty
#ifdef __cplusplus
}
#endif
