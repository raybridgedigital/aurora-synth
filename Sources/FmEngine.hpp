#pragma once
// FmEngine — 4-operator phase-modulation engine.
// Spec: FUTURE-PROPOSAL-FM-ENGINE.md (LOCKED v1.0), sections 4, 5, 10.
// Layer parameters arrive via the bridge (`aurora_set_layer_fm`) as 96 floats —
// this layout is the single contract shared by Swift (FmPatch.packed()),
// PluginCore (fm dictionary packer) and the DSP below.
#include <array>
#include <cstdint>
namespace aurora {
inline constexpr int kFmOpCount=4;
inline constexpr int kFmGlobalCount=8;
inline constexpr int kFmOpStride=22;
inline constexpr int kFmParamCount=kFmGlobalCount+kFmOpCount*kFmOpStride; // 96
inline constexpr int kFmModCount=10;  // matrix destinations 37...46
inline constexpr int kFmModBase=37;   // first FM destination inside the engine's mod[]
inline constexpr int kFmDestCount=kFmModBase+kFmModCount; // sound matrix destinations are now 0...46
enum FmGlobal : int {
    FmEnabled=0, FmAlgorithm, FmFeedback, FmCarrierMix,
    FmPitchEnvAmount, FmPitchEnvTime, FmPitchEnvCurve, FmReserved
};
// Per-operator fields, stride 22, base = kFmGlobalCount + op * kFmOpStride.
enum FmOpField : int {
    FmWave=0,     // 0 sine / 1 triangle / 2 saw / 3 pulse / 4 wavetable
    FmRatio,      // 0.25...16 x note frequency
    FmFixedHz,    // 1...20000 Hz when FmFixedMode >= 0.5
    FmFixedMode,  // 0 ratio, 1 fixed frequency
    FmRatioFine,  // -1...1 = ±100 cents
    FmLevel,      // modulator: index, carrier: amplitude (0...1)
    FmVel,        // velocity sense 0...1
    FmKeyScale,   // 0 off / 1 low / 2 even / 3 odd
    FmKeySync,    // stored for v1.1 free-run phase continuity; voices always reset today
    FmEnvMode,    // 0 rate/level (4 rates + 4 levels), 1 ADSR alternate (rates = seconds),
                  // 2 exponential rate/level (falls at 96 dB per 1/rate s, DX-style)
    FmPulseWidth, // 0.05...0.95
    FmRate1, FmRate2, FmRate3, FmRate4,       // rate/level: speed 0.02...1000 (time = 1/rate)
    FmLevel1, FmLevel2, FmLevel3, FmLevel4,   // 0...1
    FmWTTable,    // 0...23 factory wavetable
    FmWTPos,      // wavetable position 0...1
    FmWTWarp      // wavetable warp 0...1
};
struct FmParams { std::array<float,kFmParamCount> v{}; };
struct FmVoiceState {
    std::array<double,kFmOpCount> phase{};   // double-precision accumulators (spec §10)
    std::array<float,kFmOpCount> env{};
    std::array<int8_t,kFmOpCount> stage{};   // 0 attack · 1 decay · 2 hold · 3 release
    float feedbackDelay=0; // 1-sample delay at the internal modulator rate (DX lineage)
    std::array<float,kFmOpCount> expFactor{}; // exponential mode: per-sample fall for expSpeed
    std::array<float,kFmOpCount> expSpeed{};
    float pitchEnv=0;      // semitones; one-shot strike envelope
    float pitchClock=0;    // seconds since note-on; <0 once the strike envelope parks
};
class FmEngine {
public:
    static void initTables(); // sine + wavetable banks; call from SynthEngine::prepare
    // One output sample for one voice.
    //  baseHz    final note frequency (post bend/glide/matrix pitch, pre pitch-env)
    //  velocity  0...1 note velocity (carrier/modulator sense applied per op)
    //  key       MIDI key number (key-scale routing)
    //  released  true while the layer voice is in release (stage 3)
    //  mod       10 FM matrix destination offsets 37...46 (may be null)
    static float renderSample(const FmParams& params,FmVoiceState& st,float baseHz,
                              float velocity,int key,bool released,double sampleRate,const float* mod);
    static const char* algorithmName(int index); // 0...15, UI labels
    static int algorithmCount();
};
}
