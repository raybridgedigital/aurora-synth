#include "SynthEngine.hpp"
#include "Wavetable.hpp"
#include "MotionEnvelope.hpp"
#include "FmEngine.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace aurora {
namespace {
constexpr int kLayers=4, kVoices=64, kSources=32;
constexpr float pi=3.14159265358979323846f, tau=2*pi;
constexpr size_t queueSize=2048, delaySize=768004, chorusSize=8192, shimmerSize=192000, shimmerPredelaySize=48000;
float bounded(float x,float lo,float hi,float fallback=0) {
    return std::isfinite(x) ? std::clamp(x,lo,hi) : fallback;
}
float parameterValue(int p,float v) {
    switch(p) {
        case APFilter1Slope:case APFilter2Slope:case APLFO1Sync:case APLFO2Sync:case APLFO1Retrigger:case APLFO2Retrigger:return std::round(bounded(v,0,1));
        case APLFO1Division:case APLFO2Division:return std::round(bounded(v,0,9,4));
        case APLFO1Delay:case APLFO2Delay:case APLFO1Fade:case APLFO2Fade:return bounded(v,0,8);
        case APFilter2Enabled:return bounded(v,0,1)>=.5f?1:0;
        case APFilterRouting:return std::round(bounded(v,0,2));
        case APFilter2Cutoff:return bounded(v,30,18000,3200);
        case APFilter2Resonance:return bounded(v,0,.9f);
        case APModAttack:return bounded(v,.001f,8,.01f);
        case APModDecay:case APModRelease:return bounded(v,.01f,12,.35f);
        case APModAmount:return bounded(v,-1,1);
        case APModDestination:return std::round(bounded(v,0,6));
        case APOscModMode:return std::round(bounded(v,0,3));
        case APOscModRatio:return bounded(v,.25f,8,1);
        case APCharacterMode:return std::round(bounded(v,0,4));
        case APCharacterBits:return std::round(bounded(v,4,16,12));
        case APCharacterRate:return bounded(v,.02f,1,1);
        case APWT1Table: case APWT2Table: return std::round(bounded(v,0,24));
        case APWT1WarpMode: case APWT2WarpMode: return std::round(bounded(v,0,5));
        case APVoiceMode: return std::round(bounded(v,0,2));
        case APGlide: return bounded(v,0,2);
        case APBendRange: return std::round(bounded(v,0,24,2));
        case APEnabled: case APArpEnabled: case APSync: return bounded(v,0,1)>=.5f?1:0;
        case APPulseWidth: return bounded(v,.05f,.95f,.5f);
        case APUnison: return std::round(bounded(v,1,8,1));
        case APUnisonDetune: return bounded(v,0,30);
        case APSyncTune: return bounded(v,0,36);
        case APWave1: case APWave2: case APLFOShape: case APLFO2Shape: return std::round(bounded(v,0,4));
        case APDetune: return bounded(v,-100,100);
        case APCutoff: return bounded(v,20,20000,1500);
        case APAttack: case APDecay: case APRelease: return bounded(v,.001f,30,.1f);
        case APPan: case APFilterEnvelope: return bounded(v,-1,1);
        case APTranspose: return std::round(bounded(v,-48,48));
        case APLFORate: case APLFO2Rate: return bounded(v,.01f,30,1);
        case APLFODestination: case APLFO2Destination:
            return std::round(bounded(v,0,3));
        case APArpRate: return std::round(bounded(v,0,5));
        case APArpMode: return std::round(bounded(v,0,29));
        case APArpVelocityShape: return std::round(bounded(v,0,4));
        case APArpSwing: return bounded(v,0,1);
        case APFilterType:case APFilter2Type: return std::round(bounded(v,0,3));
        case APArpOctaves: return std::round(bounded(v,1,4,1));
        case APArpGate: return bounded(v,.05f,.95f,.65f);
        case APKeyLow: case APKeyHigh: return std::round(bounded(v,0,127));
        default:
            if(p>=APLFO3Shape && p<APParameterCount){
                switch((p-APLFO3Shape)%9){
                    case 0: return std::round(bounded(v,0,4));
                    case 1: return bounded(v,.01f,30,1);
                    case 2: return bounded(v,0,1,1);
                    case 3: case 5: return std::round(bounded(v,0,1));
                    case 4: return std::round(bounded(v,0,9,4));
                    case 6: return bounded(v,0,1);
                    default: return bounded(v,0,8);
                }
            }
            return bounded(v,0,1);
    }
}
float globalValue(int p,float v) {
    if(p==AGOutputGain)return bounded(v,0,24);
    if(p==AGPhaserRate||p==AGChorusRate||p==AGFlangerRate)return bounded(v,.03f,5,.23f);
    if(p==AGFlangerFeedback)return bounded(v,0,.9f,.35f);
    if(p==AGTremRate)return bounded(v,.03f,8,3);
    if(p==AGTremMode)return bounded(v,0,2)>=1.5f?2.f:(bounded(v,0,2)>=.5f?1.f:0.f);
    if(p==AGCrushBits)return bounded(v,1,16,8);
    if(p==AGCrushDownsample)return bounded(v,1,64,1);
    if(p==AGDuckRelease)return bounded(v,0,1,.4f);
    if(p==AGCompThreshold)return bounded(v,-60,0,0);
    if(p==AGCompRatio)return bounded(v,1,12,2);
    if(p==AGCompAttack)return bounded(v,.1f,100,5);
    if(p==AGCompRelease)return bounded(v,5,1000,120);
    if(p==AGCompMakeup)return bounded(v,0,18,0);
    if(p==AGCompAuto||p==AGWahMode)return bounded(v,0,1)>=.5f?1.f:0.f;
    // Master FX power toggles are true switches, never partial: 0 = struck, 1 = in.
    if(p>=AGShimmerPower&&p<=AGCompPower)return bounded(v,0,1)>=.5f?1.f:0.f;
    if(p==AGPhaserFeedback)return bounded(v,-.85f,.85f);
    if(p==AGReverbDecay)return bounded(v,.2f,8,1);
    if(p==AGShimmerDecay||p==AGShimmerLateDecay)return bounded(v,.2f,12,3);
    if(p==AGDelayTiming)return std::round(bounded(v,0,7));
    if(p==AGTempo) return bounded(v,30,240,120);
    if(p==AGDelayFeedback) return bounded(v,0,.85f,.3f);
    if(p==AGDelaySync||p==AGShimmerReverse)return bounded(v,0,1)>=.5f?1.f:0.f;
    if(p==AGDelayTimeMs)return bounded(v,1,2000,375);
    if(p==AGEqLow||p==AGEqMid||p==AGEqHigh)return bounded(v,-12,12);
    if(p==AGShimmerPitch)return bounded(v,-12,24,12);
    if(p==AGShimmerPredelay)return bounded(v,0,200,20);
    if(p==AGShimmerAmount)return bounded(v,0,.95f,.45f);
    if(p==AGDelayMix||p==AGChorusMix)return bounded(v,0,.6f);
    if(p==AGReverbMix)return bounded(v,0,.75f);
    return bounded(v,0,1);
}
float polyBLEP(float phase,float step) {
    if(phase<step) { float t=phase/step; return 2*t-t*t-1; }
    if(phase>1-step) { float t=(phase-1)/step; return t*t+2*t+1; }
    return 0;
}
float oscillator(float phase,float step,int wave,float width=.5f) {
    switch(wave) {
        case 0: return std::sin(tau*phase);
        case 1: return 1-4*std::abs(phase-.5f);
        case 2: return 2*phase-1-polyBLEP(phase,step);
        case 3: { width=std::clamp(width,.05f,.95f);float v=phase<width?1.f:-1.f;
            v+=polyBLEP(phase,step); v-=polyBLEP(std::fmod(phase+1-width,1.f),step); return v; }
        default: {
            // Original compact harmonic voice, retained for classic patches.
            float v=std::sin(tau*phase);
            if(step*2<.45f) v+=.32f*std::sin(2*tau*phase);
            if(step*3<.45f) v+=.18f*std::sin(3*tau*phase);
            if(step*5<.45f) v+=.08f*std::sin(5*tau*phase);
            return v/1.58f;
        }
    }
}
uint32_t nextRandom(uint32_t& s) { s^=s<<13; s^=s>>17; s^=s<<5; return s; }
float randomUnit(uint32_t& s) { return float(nextRandom(s)>>8)*(1.f/8388608.f)-1; }
float shapeLFO(float p,int shape,float random) {
    switch(shape) {
        case 1: return 1-4*std::abs(p-.5f);
        case 2: return 2*p-1;
        case 3: return p<.5f?1:-1;
        case 4: return random;
        default: return std::sin(tau*p);
    }
}
struct Event { enum Kind:uint8_t { MIDI, Route, Disconnect, Curve, Hold, ClockSource, Clock } kind=MIDI;
    int32_t source=0; int a=0,b=0,c=0;uint64_t generation=0;double seconds=0; };
// Bounded sequence-number queue. Producers never wait on the audio thread. A
// producer gives up after bounded contention; overflow requests panic recovery.
// Only the render thread consumes it. All payload accesses are ordered by seq.
struct EventQueue {
    struct Cell { std::atomic<size_t> sequence{0}; Event event{}; };
    std::array<Cell,queueSize> cells{};
    alignas(64) std::atomic<size_t> enqueue{0};
    alignas(64) size_t dequeue=0;
    EventQueue() { for(size_t i=0;i<queueSize;i++) cells[i].sequence.store(i); }
    bool push(Event value) {
        size_t pos=enqueue.load(std::memory_order_relaxed);
        for(int attempts=0;attempts<16;attempts++) {
            Cell& cell=cells[pos&(queueSize-1)];
            auto seq=cell.sequence.load(std::memory_order_acquire);
            auto dif=static_cast<intptr_t>(seq)-static_cast<intptr_t>(pos);
            if(dif==0) {
                if(enqueue.compare_exchange_weak(pos,pos+1,std::memory_order_relaxed)) {
                    cell.event=value; cell.sequence.store(pos+1,std::memory_order_release); return true;
                }
            } else if(dif<0) return false;
            else pos=enqueue.load(std::memory_order_relaxed);
        }
        return false;
    }
    bool pop(Event& value) {
        Cell& cell=cells[dequeue&(queueSize-1)];
        if(cell.sequence.load(std::memory_order_acquire)!=dequeue+1) return false;
        value=cell.event; cell.sequence.store(dequeue+queueSize,std::memory_order_release); ++dequeue; return true;
    }
};
static_assert(std::atomic<float>::is_always_lock_free);
static_assert(std::atomic<size_t>::is_always_lock_free);
struct OscillatorLane {
    float phase1=0,phase2=.17f,subphase=0,ic1=0,ic2=0,syncCorrection=0;
    float f1b1=0,f1b2=0,f2b1=0,f2b2=0;
    float f2ic1=0,f2ic2=0,held=0,holdPhase=1,tone=0,previousCharacter=0;
};
struct Voice {
    int untransposedPitch=60;
    double motionTime=0;
    float motionValue=0,motionRelease=1,motionFade=0;
    bool motionStarted=false;
    bool active=false, arp=false; int source=0,channel=0,key=0,layer=0,stage=0;
    uint64_t serial=0; float phase1=0,phase2=.17f,subphase=0,frequency=440,targetFrequency=440;
    float envelope=0,velocity=1,ic1=0,ic2=0,filterG=.2f,filterK=1,lastL=0,lastR=0;
    float modEnvelope=0,filter2G=.2f,filter2K=1;int modStage=0;
    std::array<OscillatorLane,8> lanes{};
    aurora::FmVoiceState fm{}; // FM-mode operator phases/envelopes (zeroed per note by Voice{})
    std::array<float,5> lfoPhase{},lfoRandom{};
    uint32_t extraLFOSeed=0xA5A5A5A5u;
    double age=0;float noteRandom=0;
};
struct Tail { float left=0,right=0;int remaining=0;int layer=0; };
struct MatrixRoute {int source=0,destination=0,target=4,cc=1,slot=0;float amount=0;};
struct Source {
    int curve=0;
    std::array<std::array<uint64_t,128>,16> order{};
    bool used=false,connected=true; int32_t id=0; int mask=1,channel=0;
    std::array<std::array<uint8_t,128>,16> velocity{},physical{};
    std::array<bool,16> sustain{};
    std::array<float,16> bend{},wheel{},expression{};
    std::array<std::array<float,128>,16> controls{};
    std::array<float,16> pressure{};
    Source() { bend.fill(0); expression.fill(1); }
};
struct Layer {
    float delaySend=1,reverbSend=1,shimmerSend=1,delayTarget=1,reverbTarget=1,shimmerTarget=1;
    MotionEnvelope motion;
    std::array<const wt::Bank*,2> banks{};
    std::array<float,2> wtPosition{},wtAmount{};
    int previousMode=0;
    float glideStep=1;
    std::array<float,APParameterCount> p{};
    std::array<float,8> unisonRatios{1,1,1,1,1,1,1,1};
    float syncRatio=1,syncDecay=0;
    float attack=.01f,decay=.99f,release=.99f,detune=1;
    float modAttack=.01f,modDecay=.99f,modRelease=.99f,characterTone=1,characterSteps=2048;
    float gain=0,cutoff=1500;
    std::array<float,5> lfoPhase{},heldRandom{};
    std::array<uint32_t,5> lfoSeed{0,0x71b48a95u,0x51c3a91eu,0x8a2e17b4u,0x3d6f90c1u};
    double arpCountdown=0,gateCountdown=0;
    uint64_t arpStep=0; bool previousEnabled=false,previousArp=false,arpWaiting=true;
    aurora::FmParams fm{}; // block-boundary snapshot of this layer's 96 FM floats
    bool fmActive=false;
};
struct Candidate { int source=0,channel=0,key=0,note=0; float velocity=0; uint64_t order=0; };
struct Comb {
    float feedback=.77f;
    std::array<float,16384> data{}; int position=0,length=1500; float damp=0;
    float process(float input) {
        float delayed=data[position]; damp+=.35f*(delayed-damp);
        data[position]=input+feedback*damp; if(++position>=length)position=0; return delayed;
    }
    void clear() { data.fill(0);position=0;damp=0; }
};
struct Allpass {
    std::array<float,4096> data{}; int position=0,length=200;
    float process(float input) {
        float v=data[position], out=v-input; data[position]=input+.5f*v;
        if(++position>=length)position=0;return out;
    }
    void clear() { data.fill(0);position=0; }
};
}
struct SynthEngine::Impl {
    std::array<std::atomic<float>,4> delaySends{},reverbSends{},shimmerSends{};
    std::atomic<int> solo{-1};int activeSolo=-1;
    struct MotionPacket {std::atomic<unsigned> version{0};std::array<std::atomic<float>,motionSize> values{};};
    std::array<MotionPacket,4> motionPackets{};
    std::array<std::atomic<float>,4> motionPlayheads{};
    std::atomic<int> tableReaders{0};
    std::atomic<uint64_t> completedTableRenders{0};
    std::array<std::atomic<const wt::Bank*>,8> customBanks{};
    std::array<std::unique_ptr<wt::Bank>,8> ownedBanks{};
    struct RetiredBank {std::unique_ptr<wt::Bank> bank;uint64_t completed;};
    std::vector<RetiredBank> retiredBanks;
    std::array<std::atomic<float>,8> previewPosition{},previewAmount{};
    std::atomic<unsigned> previewActiveLayers{0};
    uint32_t phaseRandom=0x17253819,modulationRandom=0x936a8d21;
    static constexpr int kMatrixSlots=10, kFeedbackCount=50;
    std::array<std::atomic<float>,kFeedbackCount> modulationFeedback{};
    std::array<float,kFeedbackCount> frameFeedback{};
    std::array<std::array<std::atomic<uint64_t>,kMatrixSlots>,5> matrix{};
    std::array<std::array<MatrixRoute,kMatrixSlots>,5> activeMatrix{};
    std::array<int,5> matrixCount{};
    std::array<uint8_t,4> extraLFO{};
    std::array<float,128> latestCC{};
    float latestVelocity=0,latestPressure=0;
    static float performanceValue(const MatrixRoute& r,float velocity,float pressure,const std::array<float,128>& cc) {
        switch(r.source){case 0:return cc[1];case 1:return velocity;case 2:return pressure;case 3:return cc[11];case 4:return cc[64]>=.5f?1.f:0.f;default:return cc[r.cc];}
    }

    std::array<std::atomic<float>,8192> scopeSamples{};
    std::atomic<unsigned> scopePublished{0};
    unsigned scopePosition=0;
    std::atomic<int> transpose{0};
    float transposeRatio=1;
    std::array<std::array<std::atomic<float>,APParameterCount>,kLayers> parameters{};
    std::array<std::atomic<float>,AGGlobalCount> globals{};
    std::array<float,AGGlobalCount> global{};
    EventQueue queue; std::atomic<bool> panicRequested{false};std::atomic<uint64_t> eventGeneration{0};
    std::atomic<float> outputPeak{0}; std::atomic<int> voiceCount{0};
    std::array<Voice,kVoices> voices{};std::array<Tail,kVoices> tails{};size_t nextTail=0;
    std::array<Source,kSources> sources{};
    std::array<Layer,kLayers> layers{};
    std::array<Candidate,512> candidates{};
    std::array<float,delaySize> delayL{},delayR{};
    std::array<float,chorusSize> chorusL{},chorusR{};
    std::array<std::array<float,4>,2> phaserState{};
    std::array<float,2> phaserCoefficient{};
    std::array<float,2> phaserFeedback{};
    float phaserPhase=0,phaserMix=0;
    // 0.25.0 effects: flanger / tremolo / bitcrusher / delay duck / compressor / auto-wah
    std::array<float,4096> flangerBufL{},flangerBufR{};
    size_t flangerPos=0;
    float flangerPhase=0,flangerFBL=0,flangerFBR=0,flangerMix=0;
    float tremPhase=0;
    float wahEnv=0,wahMixS=0;
    std::array<float,2> wahLP{},wahBP{};
    float crushHoldL=0,crushHoldR=0; int crushCounter=0;
    float duckEnv=0;
    float compEnv=0;
    // Master FX power (AGShimmerPower…AGCompPower). Switching an effect off fades its
    // wet contribution over a 20 ms S-curve; once the fade reaches zero the effect runs
    // no DSP at all. Its memory (delay lines, rings) is then wiped in bounded slices at
    // block boundaries, so switching it back on starts from silence without a large
    // memset on the audio thread. An effect cannot reopen until its wipe has finished.
    enum FxSlot:int{FxShimmer=0,FxDelay,FxReverb,FxChorus,FxPhaser,FxFlanger,FxTrem,FxCrush,FxWah,FxComp,FxSlotCount};
    static constexpr float kFxFadeSeconds=.02f;
    static constexpr size_t kFxWipeFloatsPerFrame=512; // ~2 KB per frame: a few µs per block
    struct FxPowerState{float ramp=1;bool dirty=false;int wipeStage=0;size_t wipePos=0;};
    std::array<FxPowerState,FxSlotCount> fxPower{};
    bool delayResume=false;
    // Effect gains: the S-curve of each ramp, applied at every injection point.
    float shimPower=1,delayPower=1,verbPower=1,chorusPower=1,phaserPower=1;
    float flangerPower=1,tremPower=1,crushPower=1,wahPower=1,compPower=1;
    static float fxCurve(float ramp){return ramp*ramp*(3-2*ramp);}
    float& fxGain(int slot){
        switch(slot){
            case FxShimmer:return shimPower;case FxDelay:return delayPower;case FxReverb:return verbPower;
            case FxChorus:return chorusPower;case FxPhaser:return phaserPower;case FxFlanger:return flangerPower;
            case FxTrem:return tremPower;case FxCrush:return crushPower;case FxWah:return wahPower;default:return compPower;
        }
    }
    std::atomic<float> gainReduction{0};
    std::array<Comb,8> combs{}; std::array<Allpass,4> allpasses{};
    size_t delayPosition=0,chorusPosition=0; float chorusPhase=0,delaySamples=24000,master=.25f,outputGain=1,outputLimiter=1;
    // Mute-bus panic: fade FINAL stereo only; wipe large FX rings only under true silence.
    enum class PanicPhase : uint8_t { Idle=0, FadingOut=1, Silent=2, FadingIn=3 };
    PanicPhase panicPhase{PanicPhase::Idle};
    float panicGain{1.f};
    uint32_t panicSamplesLeft{0};
    uint32_t panicFadeTotal{1};
    bool panicWipePending{false};
    bool panicFxStarved{false};
    // While true, setParameter/setGlobal write HERE so Cut-on applyPatch cannot
    // retune shimmer mid-fade (Infinite Mirror / Fifth Cascade). Flushed at silence.
    std::atomic<bool> panicDeferParams{false};
    std::array<std::array<std::atomic<float>,APParameterCount>,kLayers> pendingParameters{};
    std::array<std::array<std::atomic<float>,kFmParamCount>,kLayers> fmParameters{};
    std::array<std::array<std::atomic<float>,kFmParamCount>,kLayers> pendingFmParameters{};
    std::array<std::atomic<float>,AGGlobalCount> pendingGlobals{};
    static constexpr float kPanicFadeOutMs=100.f;
    static constexpr float kPanicFadeInMs=25.f;
    static constexpr float kPanicHoldMs=80.f;
    static float smoothstep01(float t){t=std::clamp(t,0.f,1.f);return t*t*(3.f-2.f*t);}
    // Delay tone LPFs in feedback path (0=dark … 1=bright)
    float delayToneL=0,delayToneR=0;
    // 3-band EQ state (shelves + presence) on final stereo bus
    float eqLowL=0,eqLowR=0,eqMidL=0,eqMidR=0,eqHighL=0,eqHighR=0;
    // Full shimmer: pitch-shifted multi-voice diffusion return
    std::array<float,shimmerSize> shimmerBufL{},shimmerBufR{};
    std::array<float,shimmerPredelaySize> shimmerPreL{},shimmerPreR{};
    size_t shimmerWrite=0,shimmerPreWrite=0;
    float shimmerGrainL[3]{},shimmerGrainR[3]{};
    float shimmerReadL[3]{},shimmerReadR[3]{};
    float shimmerToneStateL=0,shimmerToneStateR=0;
    float shimmerFbL=0,shimmerFbR=0;
    std::array<Comb,4> shimmerCombs{};
    std::array<Allpass,2> shimmerAllpasses{};
    float shimmerEarlyStateL=0,shimmerEarlyStateR=0;
    double sampleRate=48000; uint64_t serial=0,sampleCounter=0; uint32_t random=0x8e7f4a35;
    bool holding=false,externalClock=false,clockPlaying=true;
    int32_t clockID=0;uint64_t clockTicks=0,clockAge=0;
    double lastClock=0,clockInterval=0;
    std::atomic<float> clockBPM{0};
    Impl() {
        for(int i=0;i<4;i++){delaySends[i]=1;reverbSends[i]=1;shimmerSends[i]=1;}
        for(auto& p:motionPlayheads)p.store(-1);
        (void)wt::factory();
        retiredBanks.reserve(16);
        std::array<float,APParameterCount> defaults{};
        defaults[APWave1]=2; defaults[APWave2]=1; defaults[APBlend]=.25f; defaults[APDetune]=7;
        defaults[APSub]=.12f; defaults[APCutoff]=3200; defaults[APResonance]=.15f;
        defaults[APAttack]=.012f; defaults[APDecay]=.35f; defaults[APSustain]=.7f;
        defaults[APRelease]=.35f; defaults[APLevel]=.7f; defaults[APLFORate]=.7f;
        defaults[APFilterEnvelope]=.2f; defaults[APArpRate]=1; defaults[APArpOctaves]=1;
        defaults[APArpGate]=.65f; defaults[APKeyHigh]=127; defaults[APLFO2Rate]=4;
        defaults[APLFO2Destination]=1;
        defaults[APPulseWidth]=.5f;defaults[APUnison]=1;defaults[APUnisonDetune]=8;defaults[APStereoSpread]=.6f;
        defaults[APBendRange]=2;
        defaults[APLFO1Division]=defaults[APLFO2Division]=4;
        for(int i=0;i<3;i++){int base=APLFO3Shape+i*9;defaults[base]=0;defaults[base+1]=1;defaults[base+2]=1;defaults[base+4]=4;}
        defaults[APFilter2Cutoff]=3200;defaults[APFilterBalance]=.5f;
        defaults[APModAttack]=.01f;defaults[APModDecay]=.35f;defaults[APModRelease]=.35f;
        defaults[APOscModRatio]=1;defaults[APCharacterDrive]=.25f;defaults[APCharacterMix]=1;
        defaults[APCharacterTone]=.5f;defaults[APCharacterBits]=12;defaults[APCharacterRate]=1;
        for(int l=0;l<kLayers;l++) for(int p=0;p<APParameterCount;p++)
            parameters[l][p].store(p==APEnabled ? float(l==0) : defaults[p]);
        globals[AGMaster].store(.25f);globals[AGTempo].store(120);globals[AGDelayMix].store(.12f);
        globals[AGDelayFeedback].store(.3f);globals[AGReverbMix].store(.16f);globals[AGChorusMix].store(.1f);
        globals[AGPhaserRate]=.22f;globals[AGPhaserDepth]=1;globals[AGChorusRate]=.23f;globals[AGChorusDepth]=1;globals[AGReverbSize]=.5f;globals[AGReverbDecay]=1;
        globals[AGDelaySync].store(1);globals[AGDelayTimeMs].store(375);globals[AGDelayPingPong].store(1);globals[AGDelayTone].store(.65f);
        globals[AGEqLow].store(0);globals[AGEqMid].store(0);globals[AGEqHigh].store(0);
        globals[AGShimmerMix].store(0);globals[AGShimmerPitch].store(12);globals[AGShimmerDecay].store(3);
        globals[AGShimmerTone].store(.55f);globals[AGShimmerPredelay].store(20);globals[AGShimmerAmount].store(.45f);
        globals[AGShimmerVoice1].store(.7f);globals[AGShimmerVoice2].store(.55f);globals[AGShimmerVoice3].store(.4f);
        globals[AGShimmerReverse].store(0);
        globals[AGShimmerEarlyLevel].store(.45f);globals[AGShimmerEarlySize].store(.35f);
        globals[AGShimmerLateLevel].store(.7f);globals[AGShimmerLateDecay].store(4);
        // Master FX power: only the shared delay and reverb returns start in the chain.
        // Every other effect starts off, so a patch only ever carries the FX it asked for.
        for(int p=AGShimmerPower;p<=AGCompPower;p++)globals[p].store(0);
        globals[AGDelayPower].store(1);globals[AGReverbPower].store(1);
        prepare(48000);
    }
    void clearPerformance() {
        // Kill voices / notes / modulation — no large ring wipes.
        for(auto& p:motionPlayheads)p.store(-1);
        holding=false;clockAge=0;lastClock=clockInterval=0;clockBPM=0;
        for(auto& value:modulationFeedback)value.store(0,std::memory_order_relaxed);
        latestCC.fill(0);latestVelocity=latestPressure=0;
        for(auto& s:sources){for(auto& cc:s.controls)cc.fill(0);s.pressure.fill(0);}
        for(auto& sample:scopeSamples)sample.store(0,std::memory_order_relaxed);
        for(auto& v:voices)v=Voice{};for(auto& t:tails)t=Tail{};
        for(auto& s:sources) {
            for(auto& a:s.velocity)a.fill(0);for(auto& a:s.physical)a.fill(0);
            s.sustain.fill(false);s.bend.fill(0);s.wheel.fill(0);s.expression.fill(1);
        }
        for(auto& l:layers){l.arpCountdown=0;l.gateCountdown=0;l.arpStep=0;l.arpWaiting=true;}
        outputPeak.store(0,std::memory_order_relaxed);voiceCount.store(0,std::memory_order_relaxed);
        previewActiveLayers.store(0);
    }
    void starveFxFeedback() {
        // Stop regeneration only. Do NOT zero tone/early/grain/wet state — that clicks at full bus gain.
        shimmerFbL=shimmerFbR=0;
        for(auto& c:combs)c.feedback=0;
        for(auto& c:shimmerCombs)c.feedback=0;
        panicFxStarved=true;
    }
    void clearFxRingsAndFilters() {
        // ONLY call while panicGain is locked at 0 (true silence).
        for(auto& channel:phaserState)channel.fill(0);
        phaserPhase=0;phaserMix=0;
        phaserFeedback.fill(0);
        delayL.fill(0);delayR.fill(0);chorusL.fill(0);chorusR.fill(0);
        delayToneL=delayToneR=0;
        // Wah / flanger / bitcrusher hold audio memory that outlives the
        // mute-bus fade, so a panic wipe must empty them too — otherwise a
        // featured wah or flanger keeps a nonzero tail past the drain and
        // the post-panic bus never reaches exact silence.
        flangerBufL.fill(0);flangerBufR.fill(0);flangerPos=0;
        flangerFBL=flangerFBR=0;
        wahEnv=0;wahLP.fill(0);wahBP.fill(0);
        crushHoldL=crushHoldR=0;crushCounter=0;
        eqLowL=eqLowR=eqMidL=eqMidR=eqHighL=eqHighR=0;
        shimmerBufL.fill(0);shimmerBufR.fill(0);shimmerPreL.fill(0);shimmerPreR.fill(0);
        shimmerWrite=shimmerPreWrite=0;shimmerToneStateL=shimmerToneStateR=0;shimmerFbL=shimmerFbR=0;
        shimmerEarlyStateL=shimmerEarlyStateR=0;
        for(int i=0;i<3;i++){shimmerGrainL[i]=shimmerGrainR[i]=0;shimmerReadL[i]=shimmerReadR[i]=0;}
        for(auto& c:combs)c.clear();for(auto& a:allpasses)a.clear();
        for(auto& c:shimmerCombs)c.clear();for(auto& a:shimmerAllpasses)a.clear();
        outputLimiter=1.f;
        delayPosition=chorusPosition=0;
        for(auto& f:fxPower){f.dirty=false;f.wipeStage=0;f.wipePos=0;}
    }
    // Scalar state of one effect (read/write positions, envelopes, filter memories).
    void resetEffectState(int slot) {
        switch(slot){
            case FxShimmer:
                for(auto& c:shimmerCombs){c.position=0;c.damp=0;}for(auto& a:shimmerAllpasses)a.position=0;
                shimmerWrite=shimmerPreWrite=0;shimmerToneStateL=shimmerToneStateR=0;shimmerFbL=shimmerFbR=0;
                shimmerEarlyStateL=shimmerEarlyStateR=0;
                for(int i=0;i<3;i++){shimmerGrainL[i]=shimmerGrainR[i]=0;shimmerReadL[i]=shimmerReadR[i]=0;}
                break;
            case FxDelay:delayToneL=delayToneR=0;duckEnv=0;break;
            case FxReverb:for(auto& c:combs){c.position=0;c.damp=0;}for(auto& a:allpasses)a.position=0;break;
            case FxPhaser:for(auto& channel:phaserState)channel.fill(0);phaserFeedback.fill(0);break;
            case FxFlanger:flangerFBL=flangerFBR=0;break;
            case FxCrush:crushHoldL=crushHoldR=0;crushCounter=0;break;
            case FxWah:wahEnv=0;wahMixS=0;wahLP.fill(0);wahBP.fill(0);break;
            case FxComp:compEnv=0;break;
            default:break;
        }
    }
    // Bounded wipe of a silent effect's memory. Returns true once it is fully clean.
    // Large rings are cleared across several blocks, `budget` floats at a time.
    bool wipeEffect(int slot,size_t& budget) {
        auto& f=fxPower[size_t(slot)];
        std::array<std::pair<float*,size_t>,12> spans{};int count=0;
        auto add=[&](float* data,size_t size){spans[size_t(count++)]={data,size};};
        switch(slot){
            case FxShimmer:
                add(shimmerBufL.data(),shimmerSize);add(shimmerBufR.data(),shimmerSize);
                add(shimmerPreL.data(),shimmerPredelaySize);add(shimmerPreR.data(),shimmerPredelaySize);
                for(auto& c:shimmerCombs)add(c.data.data(),c.data.size());
                for(auto& a:shimmerAllpasses)add(a.data.data(),a.data.size());
                break;
            case FxDelay:add(delayL.data(),delaySize);add(delayR.data(),delaySize);break;
            case FxReverb:for(auto& c:combs)add(c.data.data(),c.data.size());for(auto& a:allpasses)add(a.data.data(),a.data.size());break;
            case FxChorus:add(chorusL.data(),chorusSize);add(chorusR.data(),chorusSize);break;
            case FxFlanger:add(flangerBufL.data(),flangerBufL.size());add(flangerBufR.data(),flangerBufR.size());break;
            default:break;
        }
        while(f.wipeStage<count){
            auto [data,size]=spans[size_t(f.wipeStage)];
            const size_t n=std::min(size-f.wipePos,budget);
            std::fill_n(data+f.wipePos,n,0.f);f.wipePos+=n;budget-=n;
            if(f.wipePos<size)return false;
            f.wipePos=0;++f.wipeStage;
        }
        resetEffectState(slot);
        f.wipeStage=0;f.wipePos=0;f.dirty=false;
        return true;
    }
    void clearSound() {
        // Full reset (prepare / device change): performance + FX under known stop.
        clearPerformance();
        clearFxRingsAndFilters();
        panicPhase=PanicPhase::Idle;panicGain=1.f;panicSamplesLeft=0;panicFadeTotal=1;panicWipePending=false;panicFxStarved=false;panicDeferParams.store(false,std::memory_order_release);
    }
    void capturePendingFromLive() {
        for(int l=0;l<kLayers;l++)
            for(int p=0;p<APParameterCount;p++)
                pendingParameters[l][p].store(parameters[l][p].load(std::memory_order_relaxed),std::memory_order_relaxed);
        for(int g=0;g<AGGlobalCount;g++)
            pendingGlobals[g].store(globals[g].load(std::memory_order_relaxed),std::memory_order_relaxed);
        for(int l=0;l<kLayers;l++)
            for(int i=0;i<kFmParamCount;i++)
                pendingFmParameters[l][i].store(fmParameters[l][i].load(std::memory_order_relaxed),std::memory_order_relaxed);
    }
    void flushPendingToLive() {
        for(int l=0;l<kLayers;l++)
            for(int p=0;p<APParameterCount;p++)
                parameters[l][p].store(pendingParameters[l][p].load(std::memory_order_relaxed),std::memory_order_relaxed);
        for(int g=0;g<AGGlobalCount;g++)
            globals[g].store(pendingGlobals[g].load(std::memory_order_relaxed),std::memory_order_relaxed);
        for(int l=0;l<kLayers;l++)
            for(int i=0;i<kFmParamCount;i++)
                fmParameters[l][i].store(pendingFmParameters[l][i].load(std::memory_order_relaxed),std::memory_order_relaxed);
    }
    void beginPanicMute() {
        // Fade the FINAL bus first. Clearing voices/wet state here clicks while gain is still ~1
        // (esp. reverse shimmer patches like Ghost Harmonics). Wipe + voice kill happen in Silent.
        starveFxFeedback();
        if(panicPhase==PanicPhase::FadingOut)return;
        if(panicPhase==PanicPhase::Silent){
            panicWipePending=true;
            panicSamplesLeft=std::max(panicSamplesLeft,uint32_t(sampleRate*kPanicHoldMs*.001));
            return;
        }
        float start=std::clamp(panicGain,0.f,1.f);
        panicPhase=PanicPhase::FadingOut;
        // Hot shimmer pads (Infinite Mirror / Fifth Cascade) need a longer bus fade.
        float mix=globals[AGShimmerMix].load(std::memory_order_relaxed);
        float amt=globals[AGShimmerAmount].load(std::memory_order_relaxed);
        float dly=globals[AGDelayMix].load(std::memory_order_relaxed)*globals[AGDelayFeedback].load(std::memory_order_relaxed);
        float energy=std::clamp(mix*amt+0.5f*dly,0.f,1.f);
        float fadeMs=kPanicFadeOutMs+energy*100.f; // ~100–200 ms
        panicFadeTotal=std::max(1u,uint32_t(sampleRate*fadeMs*.001));
        panicSamplesLeft=std::max(1u,uint32_t(float(panicFadeTotal)*std::max(0.05f,start)));
        panicFadeTotal=panicSamplesLeft;
        // First audible sample must already be into the fade (gain 1 → click if wet/voices jump).
        if(panicSamplesLeft>1){
            --panicSamplesLeft;
            float progress=1.f-float(panicSamplesLeft)/float(panicFadeTotal);
            panicGain=(1.f-smoothstep01(progress))*start;
        }else{
            panicGain=start;
        }
    }
    float advancePanicGain() {
        switch(panicPhase){
        case PanicPhase::Idle:
            panicGain=1.f;return 1.f;
        case PanicPhase::FadingOut: {
            uint32_t total=std::max(1u,panicFadeTotal);
            float progress=1.f-float(panicSamplesLeft)/float(total);
            panicGain=1.f-smoothstep01(progress);
            if(panicSamplesLeft>0) --panicSamplesLeft;
            else {
                panicGain=0.f;
                panicPhase=PanicPhase::Silent;
                panicSamplesLeft=std::max(1u,uint32_t(sampleRate*kPanicHoldMs*.001));
                panicWipePending=true;
            }
            return panicGain;
        }
        case PanicPhase::Silent:
            panicGain=0.f;
            if(panicWipePending){
                clearPerformance();
                clearFxRingsAndFilters();
                // New patch params (deferred from Cut-on applyPatch) take effect only now.
                if(panicDeferParams.load(std::memory_order_acquire)){
                    flushPendingToLive();
                    panicDeferParams.store(false,std::memory_order_release);
                }
                panicWipePending=false;
            }
            if(panicSamplesLeft>0) --panicSamplesLeft;
            if(panicSamplesLeft==0){
                panicPhase=PanicPhase::FadingIn;
                panicFadeTotal=std::max(1u,uint32_t(sampleRate*kPanicFadeInMs*.001));
                panicSamplesLeft=panicFadeTotal;
                panicFxStarved=false;
            }
            return 0.f;
        case PanicPhase::FadingIn: {
            uint32_t total=std::max(1u,panicFadeTotal);
            float progress=1.f-float(panicSamplesLeft)/float(total);
            panicGain=smoothstep01(progress);
            if(panicSamplesLeft>0) --panicSamplesLeft;
            else {
                panicGain=1.f;
                panicPhase=PanicPhase::Idle;
            }
            return panicGain;
        }
        }
        return panicGain;
    }
    void prepare(double rate) {
        aurora::FmEngine::initTables();
        sampleRate=std::isfinite(rate)?std::clamp(rate,8000.,192000.):48000;
        // Device configuration may be queued before audio has started. Keep it,
        // but discard notes from a stopped interval and any old panic request.
        Event event;
        eventGeneration.fetch_add(1,std::memory_order_acq_rel);
        for(size_t n=0;n<queueSize&&queue.pop(event);n++)if(event.kind!=Event::MIDI)processEvent(event);
        panicRequested.store(false,std::memory_order_release);
        // prepare() is a silent hard-reset boundary. If a patch load deferred
        // parameter/global writes for Panic, commit them before clearing the
        // transition state so host startup/device reconfiguration cannot lose them.
        if(panicDeferParams.load(std::memory_order_acquire)){
            flushPendingToLive();
            panicDeferParams.store(false,std::memory_order_release);
        }
        clearSound(); snapshot();
        for(auto& layer:layers){layer.delaySend=layer.delayTarget;layer.reverbSend=layer.reverbTarget;layer.shimmerSend=layer.shimmerTarget;}
        constexpr float times[8]={.0297f,.0371f,.0411f,.0437f,.0307f,.0383f,.0427f,.0451f};
        for(int i=0;i<8;i++)combs[i].length=std::clamp(int(sampleRate*times[i]),1,16384);
        for(int i=0;i<4;i++)allpasses[i].length=std::clamp(int(sampleRate*(.0047f+.0013f*i)),1,4096);
        constexpr float shimmerTimes[4]={.0311f,.0413f,.0531f,.0677f};
        for(int i=0;i<4;i++)shimmerCombs[i].length=std::clamp(int(sampleRate*shimmerTimes[i]),1,16384);
        for(int i=0;i<2;i++)shimmerAllpasses[i].length=std::clamp(int(sampleRate*(.0051f+.0021f*i)),1,4096);
        delaySamples=float(sampleRate*.5);delayPosition=chorusPosition=0;sampleCounter=0;
        shimmerWrite=shimmerPreWrite=0;
        // Power gates restart at their parameter value so a bypassed effect cannot
        // leak one fade-length of wet audio at engine start or a device change.
        // clearSound() above has already emptied every effect.
        for(int i=0;i<FxSlotCount;i++){
            auto& f=fxPower[size_t(i)];
            f.ramp=globals[AGShimmerPower+i].load()>=.5f?1.f:0.f;f.dirty=false;f.wipeStage=0;f.wipePos=0;
            fxGain(i)=fxCurve(f.ramp);
        }
    }
    void requestPanic() {
        // Generation tagging also rejects a producer that reserved a queue slot
        // before panic, then published the stale note only after recovery.
        // Capture live params then defer writes so loadPreset's applyPatch cannot
        // change shimmer/FX while the old tail is still fading.
        capturePendingFromLive();
        panicDeferParams.store(true,std::memory_order_release);
        eventGeneration.fetch_add(1,std::memory_order_acq_rel);
        panicRequested.store(true,std::memory_order_release);
    }
    void submit(Event event) {
        event.generation=eventGeneration.load(std::memory_order_acquire);
        if(!queue.push(event))requestPanic();
    }
    int sourceIndex(int32_t id,bool create=true,bool recycle=false) {
        for(int i=0;i<kSources;i++)if(sources[i].used&&sources[i].id==id)return i;
        if(create)for(int i=0;i<kSources;i++)if(!sources[i].used) {
            sources[i]=Source{};sources[i].used=true;sources[i].id=id;sources[i].mask=id==0?15:1;return i;
        }
        if(create&&recycle)for(int i=0;i<kSources;i++)if(!sources[i].connected) {
            sources[i]=Source{};sources[i].used=true;sources[i].id=id;sources[i].mask=id==0?15:1;return i;
        }
        return -1;
    }
    bool routes(int source,int ch,int key,int layer) const {
        const auto& s=sources[source];const auto& p=layers[layer].p;
        return s.used&&s.connected&&(s.mask&(1<<layer))&&(s.channel==0||s.channel==ch+1)&&p[APEnabled]>.5f
            &&key>=p[APKeyLow]&&key<=p[APKeyHigh];
    }
    void fadeStolen(const Voice& voice) {
        if(voice.active)tails[nextTail++%tails.size()]={voice.lastL,voice.lastR,std::max(1,int(sampleRate*.005)),voice.layer};
    }
    void reserveOscillators(int reserve=0) {
        int used=reserve;
        for(const auto& v:voices)if(v.active)used+=int(layers[v.layer].p[APUnison]);
        while(used>256){
            Voice* oldest=nullptr;
            for(auto& v:voices)if(v.active&&(!oldest||(v.stage==3&&oldest->stage!=3)||((v.stage==3)==(oldest->stage==3)&&v.serial<oldest->serial)))oldest=&v;
            if(!oldest)break;
            used-=int(layers[oldest->layer].p[APUnison]);fadeStolen(*oldest);oldest->active=false;
        }
    }
    void releaseSource(int si,int channel=-1,int key=-1,bool force=false) {
        for(auto& v:voices)if(v.active&&v.source==si&&(channel<0||v.channel==channel)&&(key<0||v.key==key)) {
            if(force){fadeStolen(v);v.active=false;}else v.stage=3;
        }
    }
    struct LFOIndex {int shape,rate,depth,sync,division,retrigger,phase,delay,fade;};
    static LFOIndex lfoIndex(int o){
        if(o==0)return {APLFOShape,APLFORate,APLFODepth,APLFO1Sync,APLFO1Division,APLFO1Retrigger,APLFO1Phase,APLFO1Delay,APLFO1Fade};
        if(o==1)return {APLFO2Shape,APLFO2Rate,APLFO2Depth,APLFO2Sync,APLFO2Division,APLFO2Retrigger,APLFO2Phase,APLFO2Delay,APLFO2Fade};
        int base=APLFO3Shape+(o-2)*9;
        return {base,base+1,base+2,base+3,base+4,base+5,base+6,base+7,base+8};
    }
    float lfoRate(const std::array<float,APParameterCount>& p,int o) const {
        constexpr float beats[]={16,8,4,2,1,.5f,.25f,.125f,.75f,1.f/3};
        LFOIndex ix=lfoIndex(o);
        return p[ix.sync]>.5f?global[AGTempo]/(60.f*beats[std::clamp(int(p[ix.division]),0,9)]):p[ix.rate];
    }
    void startVoice(int si,int ch,int key,int pitch,float velocity,int layer,bool arp) {
        auto& settings=layers[layer].p;
        float targetHz=440.f*std::exp2((std::clamp(pitch+int(settings[APTranspose]),0,127)-69)/12.f);
        if(!arp&&settings[APVoiceMode]>.5f)for(auto& v:voices)if(v.active&&!v.arp&&v.source==si&&v.channel==ch&&v.layer==layer&&v.stage!=3){
            v.key=key;v.targetFrequency=targetHz;v.velocity=velocity;v.serial=++serial;
            v.untransposedPitch=pitch;
            if(settings[APGlide]<=0)v.frequency=targetHz;
            if(settings[APVoiceMode]<1.5f){v.age=0;v.lfoPhase={};v.lfoRandom[0]=randomUnit(modulationRandom);v.lfoRandom[1]=randomUnit(modulationRandom);v.noteRandom=randomUnit(modulationRandom);v.extraLFOSeed=0xA5A5A5A5u^uint32_t(v.serial);for(int i=2;i<5;i++)v.lfoRandom[i]=randomUnit(v.extraLFOSeed);v.stage=0;v.modStage=0;v.modEnvelope=0;v.motionTime=0;v.motionStarted=false;v.motionFade=0;v.motionRelease=1;}
            return;
        }
        // Repeated note-ons from the same physical key retrigger without losing
        // the ownership of equal pitches on a different source or channel.
        if(!arp)for(auto& v:voices)if(v.active&&!v.arp&&v.source==si&&v.channel==ch&&v.key==key&&v.layer==layer)v.stage=3;
        reserveOscillators(int(settings[APUnison]));
        Voice* target=nullptr;
        for(auto& v:voices)if(!v.active){target=&v;break;}
        if(!target) {
            target=&voices[0];
            for(auto& v:voices) {
                bool quieter=(v.stage==3&&target->stage!=3)||(v.stage==3&&target->stage==3&&v.envelope<target->envelope);
                if(quieter||(v.stage!=3&&target->stage!=3&&v.serial<target->serial))target=&v;
            }
        }
        fadeStolen(*target);
        *target=Voice{};target->active=true;target->arp=arp;target->source=si;target->channel=ch;
        target->key=key;target->layer=layer;target->serial=++serial;target->velocity=velocity;
        target->noteRandom=randomUnit(modulationRandom);target->lfoRandom[0]=randomUnit(modulationRandom);target->lfoRandom[1]=randomUnit(modulationRandom);target->extraLFOSeed=0xA5A5A5A5u^uint32_t(target->serial);for(int i=2;i<5;i++)target->lfoRandom[i]=randomUnit(target->extraLFOSeed);
        target->untransposedPitch=pitch;
        pitch=std::clamp(pitch+int(layers[layer].p[APTranspose]),0,127);
        target->frequency=440.f*std::exp2((pitch-69)/12.f);
        target->targetFrequency=target->frequency;
        for(auto& lane:target->lanes)for(int osc=0;osc<2;osc++)if(settings[APWT1Enabled+osc*7]>.5f){
            float phase=settings[APWT1Phase+osc*7]+(randomUnit(phaseRandom)+1)*.5f*settings[APWT1RandomPhase+osc*7];
            (osc?lane.phase2:lane.phase1)=phase-std::floor(phase);
        }
    }
    void returnToHeld(int si,int ch) {
        for(int l=0;l<kLayers;l++)if(layers[l].p[APVoiceMode]>.5f&&layers[l].p[APArpEnabled]<.5f){
            for(auto& v:voices)if(v.active&&v.source==si&&v.channel==ch&&v.layer==l&&!v.arp&&!sources[si].velocity[ch][v.key]){
                int key=-1;uint64_t newest=0;
                for(int n=0;n<128;n++)if(sources[si].velocity[ch][n]&&routes(si,ch,n,l)&&sources[si].order[ch][n]>=newest){key=n;newest=sources[si].order[ch][n];}
                if(key>=0&&v.stage!=3){startVoice(si,ch,key,key,sources[si].velocity[ch][key]/127.f,l,false);}else v.stage=3;
                break;
            }
        }
    }
    void releaseLayer(int layer) { for(auto& v:voices)if(v.active&&v.layer==layer)v.stage=3; }
    void restartHeld(int layer) {
        for(int si=0;si<kSources;si++)if(sources[si].used)for(int ch=0;ch<16;ch++)for(int key=0;key<128;key++)
            if(sources[si].velocity[ch][key]&&routes(si,ch,key,layer))
                startVoice(si,ch,key,key,sources[si].velocity[ch][key]/127.f,layer,false);
    }
    void snapshot() {
        activeSolo=solo.load(std::memory_order_relaxed);
        extraLFO.fill(0);
        for(int bank=0;bank<5;bank++){
            matrixCount[bank]=0;
            int slotLimit=kMatrixSlots;
            for(int routeSlot=0;routeSlot<slotLimit;routeSlot++){
                uint64_t bits=matrix[bank][routeSlot].load(std::memory_order_relaxed);
                if(bits&1){MatrixRoute r;r.slot=routeSlot;r.source=int((bits>>1)&15);r.destination=int((bits>>5)&63);r.target=int((bits>>11)&7);r.cc=int((bits>>14)&127);r.amount=float(int((bits>>21)&65535)-32768)/32767.f;activeMatrix[bank][matrixCount[bank]++]=r;if(bank<4&&r.source>=6&&r.source<=8)extraLFO[bank]|=uint8_t(1u<<(r.source-6));}
            }
        }

        transposeRatio=std::exp2(transpose.load(std::memory_order_relaxed)/12.f);
        for(int g=0;g<AGGlobalCount;g++)global[g]=globals[g].load(std::memory_order_relaxed);
        constexpr float roomTimes[8]={.0297f,.0371f,.0411f,.0437f,.0307f,.0383f,.0427f,.0451f};
        for(int i=0;i<8;i++){
            auto& c=combs[i];c.length=std::clamp(int(sampleRate*roomTimes[i]*(.5f+global[AGReverbSize])),1,16384);c.position%=c.length;
            c.feedback=panicFxStarved?0.f:std::min(.98f,std::pow(.001f,float(c.length/sampleRate)/global[AGReverbDecay]));
        }
        for(int l=0;l<kLayers;l++) {
            auto& layer=layers[l];auto& p=layer.p;
            layer.delayTarget=delaySends[l].load(std::memory_order_relaxed);layer.reverbTarget=reverbSends[l].load(std::memory_order_relaxed);layer.shimmerTarget=shimmerSends[l].load(std::memory_order_relaxed);
            auto& packet=motionPackets[l];unsigned before=packet.version.load();
            if(!(before&1)){
                MotionEnvelope next;for(int i=0;i<motionSize;i++)next.data[i]=packet.values[i].load();
                if(before==packet.version.load())layer.motion=next;
            }
            float oldTranspose=p[APTranspose];
            for(int i=0;i<APParameterCount;i++)p[i]=parameters[l][i].load(std::memory_order_relaxed);
            for(int i=0;i<kFmParamCount;i++)layer.fm.v[i]=fmParameters[l][i].load(std::memory_order_relaxed);
            layer.fmActive=layer.fm.v[FmEnabled]>.5f;
            if(oldTranspose!=p[APTranspose])for(auto& voice:voices)if(voice.active&&voice.layer==l){
                float ratio=std::exp2((std::clamp(voice.untransposedPitch+int(p[APTranspose]),0,127)-std::clamp(voice.untransposedPitch+int(oldTranspose),0,127))/12.f);
                voice.frequency*=ratio;voice.targetFrequency*=ratio;
            }
            for(int o=0;o<2;o++){
                int table=int(p[APWT1Table+o*7]);
                layer.banks[o]=table==24?customBanks[l*2+o].load():wt::factory()[table].get();
            }
            layer.attack=1.f/float(sampleRate*p[APAttack]);
            layer.decay=std::exp(-6.907755f/float(sampleRate*p[APDecay]));
            layer.release=std::exp(-9.21034f/float(sampleRate*p[APRelease]));
            layer.modAttack=1.f/float(sampleRate*p[APModAttack]);
            layer.modDecay=std::exp(-6.907755f/float(sampleRate*p[APModDecay]));
            layer.modRelease=std::exp(-9.21034f/float(sampleRate*p[APModRelease]));
            layer.characterTone=1-std::exp(-tau*std::min(300*std::exp2(p[APCharacterTone]*5.9f),float(sampleRate)*.4f)/float(sampleRate));
            layer.characterSteps=std::exp2(p[APCharacterBits]-1);
            layer.detune=std::exp2(p[APDetune]/1200.f);
            int count=std::clamp(int(p[APUnison]),1,8);
            for(int lane=0;lane<count;lane++)layer.unisonRatios[lane]=std::exp2((count==1?0.f:2.f*lane/(count-1)-1)*p[APUnisonDetune]/1200.f);
            layer.syncRatio=std::exp2((p[APSync]>.5f?p[APSyncTune]:0)/12.f);
            layer.syncDecay=std::exp(-1.f/float(sampleRate*.0002));
            layer.glideStep=p[APGlide]<=0?1.f:1-std::exp(-6.907755f/float(sampleRate*p[APGlide]));
            if(layer.previousMode!=int(p[APVoiceMode])){releaseLayer(l);layer.previousMode=int(p[APVoiceMode]);}
            bool enabled=p[APEnabled]>.5f,arp=p[APArpEnabled]>.5f;
            if(layer.previousEnabled!=enabled||layer.previousArp!=arp) {
                releaseLayer(l);layer.arpCountdown=0;layer.gateCountdown=0;layer.arpStep=0;layer.arpWaiting=false;
                if(enabled&&!arp)restartHeld(l);
            }
            layer.previousEnabled=enabled;layer.previousArp=arp;
        }
        reserveOscillators();
    }
    void processEvent(const Event& e) {
        if(e.kind==Event::Hold){
            holding=e.a!=0;
            if(!holding)for(int si=0;si<kSources;si++)for(int ch=0;ch<16;ch++)if(!sources[si].sustain[ch]){
                for(int n=0;n<128;n++)if(!sources[si].physical[ch][n])sources[si].velocity[ch][n]=0;
                returnToHeld(si,ch);for(int n=0;n<128;n++)if(!sources[si].physical[ch][n])releaseSource(si,ch,n);
            }
            return;
        }
        if(e.kind==Event::ClockSource){externalClock=e.a!=0;clockID=e.source;clockPlaying=true;clockTicks=0;lastClock=clockInterval=0;clockBPM=0;clockAge=0;for(int l=0;l<kLayers;l++){releaseLayerArp(l);layers[l].arpCountdown=0;}return;}
        if(e.kind==Event::Clock){
            if(!externalClock||e.source!=clockID)return;
            if(e.a==0xfc){clockPlaying=false;clockBPM=0;for(int l=0;l<kLayers;l++)releaseLayerArp(l);return;}
            if(e.a==0xfa||e.a==0xfb){clockPlaying=true;lastClock=0;if(e.a==0xfa){clockTicks=0;for(auto& l:layers)l.arpStep=0;}return;}
            if(e.a!=0xf8||!std::isfinite(e.seconds))return;
            double interval=e.seconds-lastClock;lastClock=e.seconds;clockAge=0;
            if(interval>=60.0/(240*24)*.9&&interval<=60.0/(30*24)*1.1){clockInterval=clockInterval==0?interval:clockInterval*.85+interval*.15;if(clockPlaying)clockBPM=std::clamp(float(60/(24*clockInterval)),30.f,240.f);}
            if(clockBPM>0)global[AGTempo]=clockBPM.load();
            if(clockPlaying)for(int l=0;l<kLayers;l++)if(layers[l].p[APEnabled]>.5f&&layers[l].p[APArpEnabled]>.5f){
                static constexpr int kArpTicks[]={24,12,8,6,4,3};
                int rate=std::clamp(int(layers[l].p[APArpRate]),0,5);
                if(clockTicks%uint64_t(kArpTicks[rate])==0)arpStep(l);
            }
            ++clockTicks;return;
        }
        int si=sourceIndex(e.source,e.kind!=Event::Disconnect,e.kind==Event::Route);if(si<0)return;
        auto& s=sources[si];
        if(e.kind==Event::Curve){s.curve=std::clamp(e.a,0,3);return;}
        if(e.kind==Event::Route) {
            releaseSource(si,-1,-1,true);
            for(auto& a:s.velocity)a.fill(0);for(auto& a:s.physical)a.fill(0);
            s.sustain.fill(false);s.mask=e.a&15;s.channel=std::clamp(e.b,0,16);s.connected=true;return;
        }
        if(e.kind==Event::Disconnect) { releaseSource(si,-1,-1,true);s=Source{};s.used=true;s.id=e.source;s.connected=false;return; }
        if(!s.connected)return;
        int ch=e.a&15,type=e.a&0xf0,key=e.b&127,value=e.c&127;
        bool performanceInput=s.mask!=0 && (s.channel==0||s.channel==ch+1);
        if(type==0x90&&value>0) {
            float velocity=value/127.f;
            if(s.curve==1)velocity=std::sqrt(velocity);else if(s.curve==2)velocity*=velocity;else if(s.curve==3)velocity=100/127.f;
            value=std::clamp(int(std::round(velocity*127)),1,127);s.order[ch][key]=++serial;
            if(performanceInput)latestVelocity=value/127.f;
            s.velocity[ch][key]=uint8_t(value);s.physical[ch][key]=1;
            for(int l=0;l<kLayers;l++)if(routes(si,ch,key,l)) {
                if(layers[l].p[APArpEnabled]<.5f)startVoice(si,ch,key,key,value/127.f,l,false);
                else if(layers[l].arpWaiting){layers[l].arpWaiting=false;layers[l].arpCountdown=0;}
            }
        } else if(type==0x80||(type==0x90&&value==0)) {
            s.physical[ch][key]=0;
            if(!s.sustain[ch]&&!holding){s.velocity[ch][key]=0;returnToHeld(si,ch);releaseSource(si,ch,key);}
        } else if(type==0xe0) {
            int bend=key|(value<<7);s.bend[ch]=(bend-8192)/8192.f;
        } else if(type==0xd0) {s.pressure[ch]=key/127.f;if(performanceInput)latestPressure=key/127.f;
        } else if(type==0xb0) {
            s.controls[ch][key]=value/127.f;if(performanceInput)latestCC[key]=value/127.f;
            if(key==1)s.wheel[ch]=value/127.f;
            else if(key==11)s.expression[ch]=value/127.f;
            else if(key==64) {
                bool on=value>=64;s.sustain[ch]=on;
                if(!on&&!holding){for(int n=0;n<128;n++)if(!s.physical[ch][n])s.velocity[ch][n]=0;returnToHeld(si,ch);for(int n=0;n<128;n++)if(!s.physical[ch][n])releaseSource(si,ch,n);}
            } else if(key==120||key==123) {
                s.velocity[ch].fill(0);s.physical[ch].fill(0);s.sustain[ch]=false;releaseSource(si,ch,-1,key==120);
            } else if(key==121) {
                s.controls[ch].fill(0);s.pressure[ch]=0;if(performanceInput){latestCC.fill(0);latestPressure=0;}
                s.bend[ch]=0;s.wheel[ch]=0;s.expression[ch]=1;s.sustain[ch]=false;
                if(!holding){for(int n=0;n<128;n++)if(!s.physical[ch][n])s.velocity[ch][n]=0;
                returnToHeld(si,ch);for(int n=0;n<128;n++)if(!s.physical[ch][n])releaseSource(si,ch,n);}
            }
        }
    }
    void arpStep(int layerIndex) {
        auto& layer=layers[layerIndex];auto& p=layer.p;
        releaseLayerArp(layerIndex);int count=0;
        for(int si=0;si<kSources;si++)if(sources[si].used)for(int ch=0;ch<16;ch++)for(int key=0;key<128;key++) {
            int velocity=sources[si].velocity[ch][key];if(!velocity||!routes(si,ch,key,layerIndex))continue;
            for(int oct=0;oct<int(p[APArpOctaves]);oct++)if(key+12*oct<=127&&count<int(candidates.size()))
                candidates[count++]={si,ch,key,key+12*oct,velocity/127.f,sources[si].order[ch][key]};
        }
        if(count==0){layer.arpStep=0;layer.arpCountdown=0;layer.arpWaiting=true;return;}
        int mode=std::clamp(int(p[APArpMode]),0,29);
        bool asPlayed=(mode==5||mode==6);
        if(asPlayed){
            std::sort(candidates.begin(),candidates.begin()+count,[](const Candidate& a,const Candidate& b){
                if(a.order!=b.order)return a.order<b.order;
                if(a.note!=b.note)return a.note<b.note;if(a.source!=b.source)return a.source<b.source;
                if(a.channel!=b.channel)return a.channel<b.channel;return a.key<b.key;
            });
            if(mode==6)std::reverse(candidates.begin(),candidates.begin()+count);
        }else{
            std::sort(candidates.begin(),candidates.begin()+count,[](const Candidate& a,const Candidate& b){
                if(a.note!=b.note)return a.note<b.note;if(a.source!=b.source)return a.source<b.source;
                if(a.channel!=b.channel)return a.channel<b.channel;return a.key<b.key;
            });
        }
        auto velShape=[&](float base,uint64_t step,int n)->float{
            int shape=std::clamp(int(p[APArpVelocityShape]),0,4);
            if(shape==0||n<=0)return base;
            if(shape==1)return base*((step%uint64_t(n))==0?1.f:.72f);
            if(shape==2)return base*((step%2)==0?1.f:.72f);
            float t=n<=1?1.f:float(step%uint64_t(n))/float(n-1);
            if(shape==3)return base*(.55f+.45f*t);
            return base*(1.f-.45f*t);
        };
        auto fire=[&](const Candidate& c,uint64_t step,int n){
            startVoice(c.source,c.channel,c.key,c.note,velShape(c.velocity,step,n),layerIndex,true);
        };
        uint64_t step=layer.arpStep;
        auto pickIndex=[&](int n)->int{
            if(n<=0)return 0;
            switch(mode){
                case 0: case 5: case 16: return int(step%uint64_t(n)); // Up / As played / Notes then octaves (sorted already)
                case 1: case 6: case 17: return n-1-int(step%uint64_t(n)); // Down / Reverse played
                case 2: case 10: { // Up/Down + Pendulum (no double ends) — keep legacy period
                    int period=std::max(1,2*n-2),s=int(step%uint64_t(period));
                    return s<n?s:period-s;
                }
                case 3: return int(nextRandom(random)%uint32_t(n));
                case 4: { // Down / Up (start at top, pendulum)
                    int period=std::max(1,2*n-2),s=int(step%uint64_t(period));
                    int idx=s<n?s:period-s; return n-1-idx;
                }
                case 8: { // Converge: ends inward
                    int half=(n+1)/2,s=int(step%uint64_t(std::max(1,n)));
                    if(s<half)return s;
                    return n-1-(s-half);
                }
                case 9: { // Diverge: center outward
                    int mid=n/2,s=int(step%uint64_t(std::max(1,n)));
                    if(s%2==0)return std::clamp(mid-(s/2),0,n-1);
                    return std::clamp(mid+(s/2)+ (n%2==0?0:0),0,n-1);
                }
                case 11: { // Zigzag: 0,2,4... then 1,3,5...
                    int evens=(n+1)/2,s=int(step%uint64_t(n));
                    if(s<evens)return s*2;
                    return 1+(s-evens)*2;
                }
                case 12: return int((step*2)%uint64_t(n)); // Skip 1
                case 13: return int((step*3)%uint64_t(n)); // Skip 2
                case 14: { // Two up, one down
                    int cycle=std::max(1,3),phase=int(step%uint64_t(cycle));
                    int base=int((step/uint64_t(cycle))%uint64_t(n));
                    if(phase==0)return base;
                    if(phase==1)return (base+1)%n;
                    return (base+n-1)%n;
                }
                case 15: { // Two down, one up
                    int cycle=3,phase=int(step%uint64_t(cycle));
                    int base=int((step/uint64_t(cycle))%uint64_t(n));
                    int top=n-1-base;
                    if(phase==0)return top;
                    if(phase==1)return (top+n-1)%n;
                    return (top+1)%n;
                }
                case 18: { // Octave leap: walk then +12 if available else wrap
                    int s=int(step%uint64_t(n));
                    if((step/uint64_t(n))%2==1) return (s+n/2)%n;
                    return s;
                }
                case 19: return (step%2==0)?0:n-1; // Pinky / thumb
                case 20: { // Gallop 0,0,1
                    static constexpr int pat[]={0,0,1};
                    int pi=pat[step%3];
                    return std::min(pi,n-1);
                }
                case 21: { // Hemiola 3 over 2
                    int s=int(step%6);
                    int map[]={0,1,2,0,1,2};
                    return map[s]%n;
                }
                case 22: return int((step/2)%uint64_t(n)); // Repeat x2
                case 23: return int((step/3)%uint64_t(n)); // Repeat x3
                case 24: { // First + climb
                    if(step%uint64_t(n+1)==0)return 0;
                    return 1+int((step-1)%uint64_t(std::max(1,n-1)));
                }
                case 25: { // Last + fall
                    if(step%uint64_t(n+1)==0)return n-1;
                    int k=int((step-1)%uint64_t(std::max(1,n-1)));
                    return n-2-k;
                }
                case 29: { // Spread walk: low, high, next-low, next-high...
                    int s=int(step%uint64_t(n));
                    if(s%2==0)return s/2;
                    return n-1-(s/2);
                }
                default: return int(step%uint64_t(n));
            }
        };

        // Chord: all notes each step
        if(mode==7){
            for(int i=0;i<count;i++)fire(candidates[i],step,count);
        } else if(mode==26||mode==27){ // Bass drone + up/down
            fire(candidates[0],step,count);
            if(count>1){
                int rest=count-1;
                int idx=mode==26?int(step%uint64_t(rest)):rest-1-int(step%uint64_t(rest));
                fire(candidates[1+idx],step,rest);
            }
        } else if(mode==28){ // Melody hold + arp below
            fire(candidates[count-1],step,count);
            if(count>1){
                int rest=count-1;
                int idx=int(step%uint64_t(rest));
                fire(candidates[idx],step,rest);
            }
        } else {
            if(mode==16){ // Notes then octaves: all base notes, then +1 oct, ...
                std::sort(candidates.begin(),candidates.begin()+count,[](const Candidate& a,const Candidate& b){
                    int ao=(a.note-a.key)/12,bo=(b.note-b.key)/12; if(ao!=bo)return ao<bo;
                    if(a.key!=b.key)return a.key<b.key; return a.note<b.note;
                });
            } else if(mode==17){ // Octaves then notes: climb each note through octaves
                std::sort(candidates.begin(),candidates.begin()+count,[](const Candidate& a,const Candidate& b){
                    if(a.key!=b.key)return a.key<b.key;
                    return a.note<b.note;
                });
            }
            fire(candidates[pickIndex(count)],step,count);
        }

        ++layer.arpStep;
        static constexpr double kBeats[]={1.0,0.5,1.0/3.0,0.25,1.0/6.0,0.125};
        int rate=std::clamp(int(p[APArpRate]),0,5);
        double duration=sampleRate*60.0/global[AGTempo]*kBeats[rate];
        float swing=std::clamp(p[APArpSwing],0.f,1.f);
        // Delay odd steps (1-based offbeats): after increment, odd step index was the one just played when step was odd before ++ 
        // Spec: if (arpStep%2)==1 add duration*swing*0.5 — use pre-increment step (0-based): odd steps get swing delay.
        if((step%2)==1) duration+=duration*swing*0.5;
        layer.arpCountdown+=duration;layer.gateCountdown=duration*p[APArpGate];
    }
        void releaseLayerArp(int l) { for(auto& v:voices)if(v.active&&v.arp&&v.layer==l)v.stage=3; }
    template<size_t N> static float delayed(const std::array<float,N>& buffer,size_t position,float amount) {
        float read=float(position)-amount;
        if(read<0)read+=float(N);int a=int(read);float f=read-float(a);int b=(a+1)%int(N);
        return buffer[size_t(a)]*(1-f)+buffer[size_t(b)]*f;
    }
    void render(float* left,float* right,uint32_t frames) {
        if(!left||!right)return;
        struct Reader {std::atomic<int>& count;std::atomic<uint64_t>& completed;Reader(std::atomic<int>& c,std::atomic<uint64_t>& e):count(c),completed(e){++count;}~Reader(){++completed;--count;}} reader(tableReaders,completedTableRenders);
        // MIDI timestamps are currently quantized to the start of this render
        // call. Parameter atomics form a control snapshot at the same boundary.
        snapshot();Event event;
        bool recover=panicRequested.exchange(false,std::memory_order_acq_rel);
        auto generation=eventGeneration.load(std::memory_order_acquire);
        if(recover)beginPanicMute();
        const bool panicBusy=panicPhase!=PanicPhase::Idle;
        for(size_t n=0;n<queueSize&&queue.pop(event);n++){
            // Always apply device/config events. Notes/Hold/Clock need current generation.
            // During Panic fade/clear, drop MIDI/Hold so nothing re-triggers the bus mid-wipe.
            const bool timed=event.kind==Event::MIDI||event.kind==Event::Hold||event.kind==Event::Clock;
            if(!timed){processEvent(event);continue;}
            if(event.generation!=generation)continue;
            if(panicBusy&&(event.kind==Event::MIDI||event.kind==Event::Hold))continue;
            processEvent(event);
        }
        // Shared FX follow the latest received performance message, including
        // controllers moved before playing. Layer destinations retain source/channel ownership.
        frameFeedback.fill(0);
        std::array<float,4> effectOffsets{};
        for(int i=0;i<matrixCount[4];i++){
            const auto& r=activeMatrix[4][i];
            if(r.destination>=8&&r.destination<=11){float value=r.amount*performanceValue(r,latestVelocity,latestPressure,latestCC);effectOffsets[r.destination-8]+=value;frameFeedback[40+r.slot]=value;}
        }
        constexpr int effects[]={AGChorusMix,AGPhaserMix,AGReverbMix,AGDelayMix};
        for(int i=0;i<4;i++)global[effects[i]]=std::clamp(global[effects[i]]+effectOffsets[i],0.f,1.f);
        float maximum=0;float smooth=1-std::exp(-1.f/float(sampleRate*.008));
        float masterTarget=global[AGMaster];
        float gainTarget=std::pow(10.f,global[AGOutputGain]/20.f);
        float limiterRelease=1-std::exp(-1.f/float(sampleRate*.1));
        // 0.25.0 effect envelope coefficients (per-block from current globals).
        const float wahAttCoef=1-std::exp(-1.f/float(sampleRate*.005));
        const float wahRelCoef=1-std::exp(-1.f/float(sampleRate*.15));
        const float compAttCoef=1-std::exp(-1.f/(float(sampleRate)*std::max(.00005f,global[AGCompAttack]*.001f)));
        const float compRelCoef=1-std::exp(-1.f/(float(sampleRate)*std::max(.005f,global[AGCompRelease]*.001f)));
        const float duckAttCoef=1-std::exp(-1.f/float(sampleRate*.001));
        const float duckRelSec=.02f*std::pow(75.f,std::clamp(global[AGDuckRelease],0.f,1.f));
        const float duckRelCoef=1-std::exp(-1.f/(float(sampleRate)*duckRelSec));
        float blockMaxGR=0;
        // Per-block constants that the sample loop used to recompute per voice or per sample.
        const double inverseRate=1/sampleRate;
        const float motionFadeStep=1.f/float(sampleRate*.003);
        const float tailLength=float(std::max(1,int(sampleRate*.005)));
        const float quietLimiterRelease=1-std::exp(-1.f/float(sampleRate*.02));
        // LFO phase increments depend only on layer parameters and tempo. The tempo can
        // move inside a block (external clock), so they are refreshed whenever it does.
        float lfoStepTempo=std::numeric_limits<float>::quiet_NaN();
        std::array<std::array<float,5>,kLayers> lfoStep{};
        std::array<double,kLayers> motionStep{};
        float delayTarget=0; // delay time in samples (tempo-synced or free), refreshed with the tempo
        // House EQ and compressor settings are block constants (globals move at block boundaries).
        const float eqLowG=std::pow(10.f,global[AGEqLow]/20.f),eqMidG=std::pow(10.f,global[AGEqMid]/20.f),eqHighG=std::pow(10.f,global[AGEqHigh]/20.f);
        const float eqLowC=std::exp(-2.f*pi*180.f/float(sampleRate)),eqMidC=std::exp(-2.f*pi*1200.f/float(sampleRate)),eqHighC=std::exp(-2.f*pi*5000.f/float(sampleRate));
        const float compThreshold=std::clamp(global[AGCompThreshold],-60.f,0.f);
        const float compRatio=std::max(1.f,std::clamp(global[AGCompRatio],1.f,12.f));
        const float compMakeup=global[AGCompAuto]>=.5f ? std::clamp(-compThreshold*(1.f-1.f/compRatio)*.7f,0.f,12.f) : std::clamp(global[AGCompMakeup],0.f,18.f);
        // Master FX power: a silent effect that still holds audio is wiped a slice at a
        // time; an effect opens only once clean; the target of every switch is fixed for
        // the block, so only effects that are mid-fade need per-sample work.
        const float fxStep=float(1/(sampleRate*kFxFadeSeconds));
        std::array<float,FxSlotCount> fxTarget{};uint32_t fxMoving=0;
        {
            size_t wipeBudget=size_t(frames)*kFxWipeFloatsPerFrame;
            for(int i=0;i<FxSlotCount;i++){
                auto& f=fxPower[size_t(i)];
                if(f.ramp==0.f&&f.dirty)wipeEffect(i,wipeBudget);
                const bool opening=f.ramp==0.f&&!f.dirty&&global[AGShimmerPower+i]>=.5f;
                const float target=global[AGShimmerPower+i]>=.5f&&!(f.ramp==0.f&&f.dirty)?1.f:0.f;
                fxTarget[size_t(i)]=target;
                if(f.ramp!=target)fxMoving|=1u<<i;
                if(opening){
                    // Resume parameter smoothers at their targets instead of gliding from
                    // values frozen when the effect went idle.
                    if(i==FxPhaser)phaserMix=global[AGPhaserMix];
                    if(i==FxFlanger)flangerMix=global[AGFlangerMix];
                    if(i==FxDelay)delayResume=true; // jump to the current delay time on first use
                }
                if(f.ramp>0.f||target>0.f)f.dirty=true; // it processes audio this block
            }
        }
        for(uint32_t frame=0;frame<frames;frame++,sampleCounter++) {
            // Advance panic envelope first so this sample's bus multiply is already correct.
            float pg=1.f;
            if(panicPhase!=PanicPhase::Idle){
                pg=advancePanicGain();
                if(panicPhase==PanicPhase::Silent || pg<=1.0e-4f){
                    left[frame]=0;right[frame]=0;
                    continue;
                }
            }
            if(externalClock&&++clockAge==uint64_t(sampleRate*.5)){clockBPM=0;lastClock=clockInterval=0;for(int l=0;l<kLayers;l++)releaseLayerArp(l);}
            if(externalClock&&clockBPM>0)global[AGTempo]=clockBPM.load(std::memory_order_relaxed);
            if(!(global[AGTempo]==lfoStepTempo)){
                lfoStepTempo=global[AGTempo];
                constexpr float divisions[8]={1,.5f,.25f,2,.75f,1.5f,1.f/3,2.f/3};
                if(global[AGDelaySync]>=.5f){
                    int div=std::clamp(int(std::lround(global[AGDelayTiming])),0,7);
                    float tempo=std::max(30.f,global[AGTempo]);
                    delayTarget=float(sampleRate*60.0/tempo)*divisions[div];
                }else
                    delayTarget=float(sampleRate)*std::clamp(global[AGDelayTimeMs],1.f,2000.f)*.001f;
                if(!std::isfinite(delayTarget))delayTarget=float(sampleRate)*.375f;
                for(int l=0;l<kLayers;l++){
                    for(int o=0;o<5;o++)lfoStep[l][o]=lfoRate(layers[l].p,o)/float(sampleRate);
                    const auto& motion=layers[l].motion;
                    double duration=motion.data[84]>0?motion.data[84]*60.0/global[AGTempo]:motion.data[2];
                    motionStep[l]=1/(sampleRate*duration);
                }
            }
            for(int l=0;l<kLayers;l++) {
                auto& layer=layers[l];auto& p=layer.p;
                layer.gain+=smooth*(p[APLevel]*p[APEnabled]*(activeSolo<0||activeSolo==l?1.f:0.f)-layer.gain);
                layer.delaySend+=smooth*(layer.delayTarget-layer.delaySend);layer.reverbSend+=smooth*(layer.reverbTarget-layer.reverbSend);layer.shimmerSend+=smooth*(layer.shimmerTarget-layer.shimmerSend);
                layer.cutoff+=smooth*(p[APCutoff]-layer.cutoff);
                for(int o=0;o<2;o++){
                    layer.wtPosition[o]+=smooth*(p[APWT1Position+o*7]-layer.wtPosition[o]);
                    layer.wtAmount[o]+=smooth*(p[APWT1Warp+o*7]-layer.wtAmount[o]);
                }
                for(int o=0;o<5;o++){
                    layer.lfoPhase[o]+=lfoStep[l][o];
                    if(layer.lfoPhase[o]>=1){layer.lfoPhase[o]-=1;uint32_t& seed=o==0?random:layer.lfoSeed[o];layer.heldRandom[o]=randomUnit(seed);}
                }
                if(p[APEnabled]>.5f&&p[APArpEnabled]>.5f) {
                    if(layer.gateCountdown>0&&--layer.gateCountdown<=0)releaseLayerArp(l);
                    if(!externalClock&&!layer.arpWaiting){if(layer.arpCountdown<=0)arpStep(l);else --layer.arpCountdown;}
                }
            }
            float outL=0,outR=0,sendDL=0,sendDR=0,sendRL=0,sendRR=0,sendSL=0,sendSR=0;
            float sharedLFO[kLayers][5];uint32_t sharedLFOReady=0;
            for(auto& v:voices)if(v.active) {
                auto& layer=layers[v.layer];const auto& p=layer.p;auto& source=sources[v.source];
                if(v.stage==0){v.envelope+=layer.attack;if(v.envelope>=1){v.envelope=1;v.stage=1;}}
                else if(v.stage==1){v.envelope=p[APSustain]+(v.envelope-p[APSustain])*layer.decay;
                    if(std::abs(v.envelope-p[APSustain])<.0001f)v.stage=2;}
                else if(v.stage==2){
                    v.envelope=p[APSustain];
                    // A natural-decay sound (sustain 0) that has finished decaying renders exact
                    // silence for as long as the key or pedal holds it. In poly mode, free the voice
                    // now, as release would, so held-pedal playing cannot fill the pool with silent
                    // voices. Mono/legato layers keep theirs: a legato note must not re-attack.
                    if(v.envelope==0.f&&p[APVoiceMode]<=.5f&&!layer.motion.routed(0)){v.active=false;continue;}
                }
                else {v.envelope*=layer.release;v.motionRelease*=layer.release;
                    if((layer.motion.routed(0)?v.motionRelease:v.envelope)<.00001f){v.active=false;continue;}}
                const auto& motion=layer.motion;
                if(motion.enabled()){
                    float target=motion.shape(float(v.motionTime));
                    if(!v.motionStarted){v.motionValue=target;v.motionStarted=true;}
                    else v.motionValue+=smooth*(target-v.motionValue);
                    if(v.stage!=3){
                        v.motionTime+=motionStep[v.layer];
                        if(motion.data[1]>.5f)v.motionTime-=std::floor(v.motionTime);
                        else v.motionTime=std::min(1.,v.motionTime);
                    }
                }
                v.motionFade=std::min(1.f,v.motionFade+motionFadeStep);
                if(v.stage==3)v.modEnvelope*=layer.modRelease;
                else if(v.modStage==0){v.modEnvelope=std::min(1.f,v.modEnvelope+layer.modAttack);if(v.modEnvelope>=1)v.modStage=1;}
                else {v.modEnvelope=p[APModSustain]+(v.modEnvelope-p[APModSustain])*layer.modDecay;}
                // Retrigger is polyphonic: a new note never resets another held note.
                // LFO 3–5 are Matrix-only. Depth scales the signal the Matrix reads. An unrouted one is skipped.
                float noteLFO[5]{};float noteCutoff=0,notePitch=0,notePan=0,noteAmp=1;
                for(int o=0;o<5;o++){
                    if(o>=2 && (extraLFO[v.layer]&uint8_t(1u<<(o-2)))==0)continue;
                    LFOIndex ix=lfoIndex(o);
                    bool retrigger=p[ix.retrigger]>.5f;
                    auto waveform=[&](float lfoPhase,float held){float phase=lfoPhase+p[ix.phase];phase-=std::floor(phase);return shapeLFO(phase,int(p[ix.shape]),held);};
                    float lfo;
                    if(retrigger)lfo=waveform(v.lfoPhase[o],v.lfoRandom[o]);
                    else {
                        // A free-running LFO has one phase per layer: shape it once per sample.
                        const uint32_t bit=1u<<(v.layer*5+o);
                        if(!(sharedLFOReady&bit)){sharedLFO[v.layer][o]=waveform(layer.lfoPhase[o],layer.heldRandom[o]);sharedLFOReady|=bit;}
                        lfo=sharedLFO[v.layer][o];
                    }
                    float elapsed=float(v.age)-p[ix.delay];
                    float fade=elapsed<0?0:(p[ix.fade]>0?std::min(1.f,elapsed/p[ix.fade]):1.f);
                    float shaped=lfo*fade;
                    if(elapsed>=0){v.lfoPhase[o]+=lfoStep[v.layer][o];if(v.lfoPhase[o]>=1){v.lfoPhase[o]-=std::floor(v.lfoPhase[o]);v.lfoRandom[o]=o<2?randomUnit(modulationRandom):randomUnit(v.extraLFOSeed);}}
                    if(o<2){
                        noteLFO[o]=shaped;
                        float amount=shaped*p[ix.depth];
                        switch(int(p[o?APLFO2Destination:APLFODestination])){case 0:noteCutoff+=amount*3;break;case 1:notePitch+=amount*2;break;case 2:notePan+=amount;break;default:noteAmp+=amount*.5f;}
                    }else noteLFO[o]=shaped*p[ix.depth];
                }
                // exp2(0) is exactly 1, so an unmodulated pitch skips the call.
                v.age+=inverseRate;notePitch=notePitch==0.f?1.f:std::exp2(notePitch/12.f);noteAmp=std::clamp(noteAmp,0.f,2.f);
                std::array<float,kFmDestCount> mod{};
                constexpr int modDestinations[]={0,16,1,18,19,12,13};
                mod[modDestinations[int(p[APModDestination])]]+=v.modEnvelope*p[APModAmount];
                if(matrixCount[v.layer]>0){
                    const float signals[]={noteLFO[0],noteLFO[1],v.envelope,v.modEnvelope,std::clamp((v.key-60)/60.f,-1.f,1.f),v.noteRandom,noteLFO[2],noteLFO[3],noteLFO[4],
                        // Sources 9/10: velocity + channel pressure promoted into soundSources (spec §6).
                        v.velocity,float(source.pressure[v.channel])};
                    for(int i=0;i<matrixCount[v.layer];i++){
                        const auto& r=activeMatrix[v.layer][i];
                        if(r.source<0||r.source>10||r.destination<0||r.destination>=kFmDestCount)continue;
                        float signal=signals[r.source];
                        mod[r.destination]+=signal*r.amount;
                        frameFeedback[v.layer*kMatrixSlots+r.slot]=signal*r.amount;
                    }
                }
                for(int i=0;i<matrixCount[4];i++){
                    const auto& r=activeMatrix[4][i];
                    if(r.destination<0||r.destination>20)continue;
                    if((r.destination<8||r.destination>=12)&&(r.target==4||r.target==v.layer)){float value=r.amount*performanceValue(r,v.velocity,source.pressure[v.channel],source.controls[v.channel]);mod[r.destination]+=value;frameFeedback[40+r.slot]=value;}
                }
                // Depth routes add modulation through each LFO's existing destination.
                float extraCutoff=0,extraPitch=0,extraPan=0,extraAmp=0;
                for(int i=0;i<2;i++){
                    float depth=p[i?APLFO2Depth:APLFODepth];
                    float amount=(std::clamp(depth+mod[6+i],0.f,1.f)-depth)*noteLFO[i];
                    switch(int(p[i?APLFO2Destination:APLFODestination])){case 0:extraCutoff+=amount*3;break;case 1:extraPitch+=amount*2;break;case 2:extraPan+=amount;break;default:extraAmp+=amount*.5f;}
                }
                float blend=std::clamp(p[APBlend]+mod[4],0.f,1.f),drive=std::clamp(p[APDrive]+mod[5],0.f,1.f);
                const float wheel=source.wheel[v.channel];
                float wheelPitch=wheel==0.f?1.f:1+wheel*std::sin(tau*layer.lfoPhase[1])*.0145f;
                v.frequency+=layer.glideStep*(v.targetFrequency-v.frequency);
                float motionPitch=motion.routed(2)?motion.value(2,v.motionValue):0;
                const float bendSemitones=source.bend[v.channel]*p[APBendRange];
                const float modSemitones=std::clamp(mod[1],-2.f,2.f)*12+extraPitch+motionPitch;
                float frequency=v.frequency*transposeRatio*(bendSemitones==0.f?1.f:std::exp2(bendSemitones/12.f))*notePitch*wheelPitch*(modSemitones==0.f?1.f:std::exp2(modSemitones/12.f));
                // Coefficients follow the note at 1/16 sample rate. Only the opening attack
                // samples update every sample (a new voice must not start on stale values);
                // quiet release tails no longer do.
                if((sampleCounter&15)==0||(v.stage==0&&v.envelope<=layer.attack*1.1f)) {
                    float cutoff=(motion.routed(1)?motion.value(1,v.motionValue):layer.cutoff)*std::exp2(noteCutoff+std::clamp(p[APFilterEnvelope]+mod[36],-1.f,1.f)*v.envelope*4+std::clamp(mod[0],-2.f,2.f)*4+extraCutoff);
                    cutoff=std::clamp(cutoff,20.f,std::min(20000.f,float(sampleRate)*.42f));
                    v.filterG=std::tan(pi*cutoff/float(sampleRate));v.filterK=2-1.85f*std::clamp(p[APResonance]+mod[21],0.f,.9f);
                    if(p[APFilter2Enabled]>.5f){
                        float cutoff2=std::clamp(p[APFilter2Cutoff]*std::exp2(std::clamp(mod[16],-2.f,2.f)*4),30.f,std::min(18000.f,float(sampleRate)*.42f));
                        v.filter2G=std::tan(pi*cutoff2/float(sampleRate));v.filter2K=2-1.85f*std::clamp(p[APFilter2Resonance]+mod[17],0.f,.9f);
                    }
                }
                // State-variable filter coefficients: one division per filter per voice sample,
                // shared by every unison lane and both 24 dB passes.
                struct SVF {float g,k,a1,a2,a3;};
                auto svf=[](float g,float k){float a1=1/(1+g*(g+k)),a2=g*a1,a3=g*a2;return SVF{g,k,a1,a2,a3};};
                const SVF c1=svf(v.filterG,v.filterK);
                const SVF c2=p[APFilter2Enabled]<.5f?c1:svf(v.filter2G,v.filter2K);
                int unison=layer.fmActive?1:std::clamp(int(p[APUnison]),1,8); // FM renders a single lane
                float width=std::clamp(p[APPulseWidth]+noteLFO[0]*p[APPWMDepth]*.45f+mod[22],.05f,.95f);
                v.lastL=v.lastR=0;
                float positions[2],amounts[2];
                for(int o=0;o<2;o++){
                    positions[o]=std::clamp((motion.routed(4+o)?motion.value(4+o,v.motionValue):layer.wtPosition[o])+mod[12+o],0.f,1.f);
                    amounts[o]=std::clamp((motion.routed(6+o)?motion.value(6+o,v.motionValue):layer.wtAmount[o])+mod[14+o],0.f,1.f);
                    if(frame+1==frames){previewPosition[v.layer*2+o].store(positions[o]);previewAmount[v.layer*2+o].store(amounts[o]);}
                }
                float formantMod[2]={std::clamp(p[APWT1Formant]+mod[29],0.f,1.f),std::clamp(p[APWT2Formant]+mod[31],0.f,1.f)};
                float toneMod[2]={std::clamp(p[APWT1Tone]+mod[30],0.f,1.f),std::clamp(p[APWT2Tone]+mod[32],0.f,1.f)};
                auto wave=[&](int o,float phase,float step){
                    return p[APWT1Enabled+o*7]>.5f&&layer.banks[o]?layer.banks[o]->shapedSample(phase,step,positions[o],int(p[APWT1WarpMode+o*7]),amounts[o],formantMod[o],toneMod[o]):oscillator(phase,step,int(p[o?APWave2:APWave1]),width);
                };
                // Everything below that does not depend on the unison lane is computed once per
                // voice sample. Each skipped exp2/sin/tanh is exact: exp2(0) is 1, a zero-level
                // sine adds nothing, and tanh(gain) is the same number for every lane.
                const float uniMod=std::clamp(mod[26],-1.f,1.f);
                const float subLevel=std::clamp(p[APSub]+mod[24],0.f,1.f);
                const float noiseLevel=std::clamp(p[APNoise]+mod[25],0.f,1.f);
                const int oscMode=int(p[APOscModMode]);
                const float oscAmount=std::clamp(p[APOscModAmount]+mod[18],0.f,1.f);
                float detuneExtra=1,syncExtra=1,ratio=1;
                if(!layer.fmActive){
                    const float detuneMod=std::clamp(mod[23],-1.f,1.f),syncMod=std::clamp(mod[28],-1.f,1.f);
                    if(detuneMod!=0.f)detuneExtra=std::exp2(detuneMod*30.f/1200.f);
                    if(syncMod!=0.f)syncExtra=std::exp2(syncMod*36.f/12.f);
                    ratio=std::clamp(p[APOscModRatio]*(mod[33]==0.f?1.f:std::exp2(mod[33])),.25f,8.f);
                }
                const int filterType=int(p[APFilterType]),filter2Type=int(p[APFilter2Type]);
                const bool slope1=p[APFilter1Slope]>.5f,slope2=p[APFilter2Slope]>.5f;
                const int character=int(p[APCharacterMode]);
                const float characterAmount=std::clamp(p[APCharacterDrive]+mod[19],0.f,1.f),characterGain=1+characterAmount*12;
                const float characterNorm=character==1?std::tanh(characterGain):1.f;
                float characterTone=layer.characterTone;
                if(character&&mod[35]!=0.f){float t=std::clamp(p[APCharacterTone]+mod[35],0.f,1.f);characterTone=1-std::exp(-tau*std::min(300*std::exp2(t*5.9f),float(sampleRate)*.4f)/float(sampleRate));}
                const float characterMix=std::clamp(p[APCharacterMix]+mod[34],0.f,1.f);
                const float amplitude=motion.routed(0)?motion.value(0,v.motionValue)*v.motionRelease*v.motionFade:v.envelope;
                const float velocityGain=layer.fmActive?1.f:v.velocity;
                const float expression=source.expression[v.channel];
                const float ampMod=std::clamp(noteAmp+mod[3]+extraAmp,0.f,2.f);
                const float spread=std::clamp(p[APStereoSpread]+mod[27],0.f,1.f);
                const float panBase=(motion.routed(3)?motion.value(3,v.motionValue):p[APPan])+notePan+mod[2]+extraPan;
                for(int laneIndex=0;laneIndex<unison;laneIndex++) {
                    auto& lane=v.lanes[laneIndex];
                    float position=unison==1?0.f:2.f*laneIndex/(unison-1)-1;
                    float uniExtra=uniMod==0.f?1.f:std::exp2(position*uniMod*30.f/1200.f);
                    float step=std::clamp(frequency*layer.unisonRatios[laneIndex]*uniExtra/float(sampleRate),.000001f,.45f);
                    float input;
                    if(layer.fmActive){
                        // Engine mode FM (spec §3): the four operators replace Osc1/Osc2;
                        // sub + noise stay beneath, then drive/filters/Character/amp/matrix run unchanged.
                        input=aurora::FmEngine::renderSample(layer.fm,v.fm,frequency,v.velocity,v.key,v.stage==3,double(sampleRate),mod.data()+aurora::kFmModBase);
                        if(subLevel!=0.f)input+=std::sin(tau*lane.subphase)*subLevel*.6f;
                        if(noiseLevel>.0001f)input+=randomUnit(random)*noiseLevel*.3f;
                        lane.subphase+=step*.5f;if(lane.subphase>=1)lane.subphase-=1;
                    } else {
                    float step2=std::clamp(step*layer.detune*detuneExtra*layer.syncRatio*syncExtra*(oscMode?ratio:1.f),.000001f,.45f);
                    float second=wave(1,lane.phase2,step2)+lane.syncCorrection;
                    // Bound modulation at high notes; classic and wavetable carriers share the same path.
                    float depth=oscAmount*std::clamp((.45f-step)/.25f,0.f,1.f);
                    float phase=lane.phase1+(oscMode==1?second*depth*.5f:0.f);phase-=std::floor(phase);
                    float first=wave(0,phase,std::min(.45f,step+(oscMode==1?step2*depth:0.f)));
                    if(oscMode==3)first=first*(1-depth)+first*second*depth;
                    input=first*(1-blend)+second*blend;
                    if(subLevel!=0.f)input+=std::sin(tau*lane.subphase)*subLevel*.6f;
                    if(noiseLevel>.0001f)input+=randomUnit(random)*noiseLevel*.3f;
                    float carrierStep=oscMode==2?std::clamp(step*(1+second*depth*4),-.45f,.45f):step;
                    lane.phase1+=carrierStep;lane.phase2+=step2;if(lane.phase2>=1)lane.phase2-=1;
                    if(lane.phase1<0)lane.phase1+=1;
                    if(lane.phase1>=1){
                        lane.phase1-=1;
                        if(p[APSync]>.5f){
                            float old=wave(1,lane.phase2,step2);
                            lane.phase2=std::fmod(lane.phase1/step*step2,1.f);
                            // Smooth the discontinuity created by resetting the slave oscillator.
                            lane.syncCorrection+=old-wave(1,lane.phase2,step2);
                        }
                    }
                    lane.syncCorrection*=layer.syncDecay;
                    lane.subphase+=step*.5f;if(lane.subphase>=1)lane.subphase-=1;
                    }
                    if(drive>.001f)input=std::tanh(input*(1+8*drive));
                    auto filter=[](float in,const SVF& c,int type,float& ic1,float& ic2){
                        float x=in-ic2,band=c.a1*ic1+c.a2*x,low=ic2+c.a2*ic1+c.a3*x;
                        ic1=2*band-ic1;ic2=2*low-ic2;
                        return type==1?in-c.k*band-low:type==2?band:type==3?in-c.k*band:low;
                    };
                    auto f1=[&](float x){float y=filter(x,c1,filterType,lane.ic1,lane.ic2);if(slope1)y=filter(y,c1,filterType,lane.f1b1,lane.f1b2);else lane.f1b1=lane.f1b2=0;return y;};
                    auto f2=[&](float x){float y=filter(x,c2,filter2Type,lane.f2ic1,lane.f2ic2);if(slope2)y=filter(y,c2,filter2Type,lane.f2b1,lane.f2b2);else lane.f2b1=lane.f2b2=0;return y;};
                    float filtered;
                    if(p[APFilter2Enabled]<.5f){filtered=f1(input);lane.f2ic1=lane.f2ic2=lane.f2b1=lane.f2b2=0;}
                    else if(p[APFilterRouting]<.5f)filtered=f2(f1(input));
                    else if(p[APFilterRouting]<1.5f)filtered=f1(f2(input));
                    else {float balance=std::clamp(p[APFilterBalance]+mod[20],0.f,1.f);filtered=f1(input)*(1-balance)+f2(input)*balance;}
                    if(character){
                        const float gain=characterGain;
                        auto shape=[&](float x){
                            if(character==1)return std::tanh(x*gain)/characterNorm;
                            if(character==2)return std::clamp(x*gain,-1.f,1.f);
                            return 2.f/pi*std::asin(std::sin(x*gain*pi*.5f));
                        };
                        float wet=filtered;
                        if(character==4){lane.holdPhase+=p[APCharacterRate];if(lane.holdPhase>=1){lane.holdPhase-=std::floor(lane.holdPhase);float steps=layer.characterSteps;lane.held=std::round(std::clamp(filtered*gain,-1.f,1.f)*steps)/steps;}wet=lane.held;}
                        else {wet=.5f*(shape((lane.previousCharacter+filtered)*.5f)+shape(filtered));lane.previousCharacter=filtered;}
                        lane.tone+=characterTone*(wet-lane.tone);
                        filtered+=(lane.tone-filtered)*characterMix;
                    }
                    float value=filtered*amplitude*velocityGain*expression*layer.gain*ampMod*.16f/unison;
                    float pan=std::clamp(panBase+position*spread,-1.f,1.f);
                    if(!std::isfinite(value)||!std::isfinite(lane.ic1)||!std::isfinite(lane.ic2)||!std::isfinite(lane.f2ic1)||!std::isfinite(lane.f2ic2)){lane=OscillatorLane{};continue;}
                    v.lastL+=value*std::sqrt(.5f*(1-pan));v.lastR+=value*std::sqrt(.5f*(1+pan));
                }
                outL+=v.lastL;outR+=v.lastR;
                sendDL+=v.lastL*layer.delaySend;sendDR+=v.lastR*layer.delaySend;
                sendRL+=v.lastL*layer.reverbSend;sendRR+=v.lastR*layer.reverbSend;
                sendSL+=v.lastL*layer.shimmerSend;sendSR+=v.lastR*layer.shimmerSend;
            }
            for(auto& t:tails)if(t.remaining>0){float fade=t.remaining/tailLength;if(activeSolo<0||activeSolo==t.layer){outL+=t.left*fade;outR+=t.right*fade;sendDL+=t.left*fade*layers[t.layer].delaySend;sendDR+=t.right*fade*layers[t.layer].delaySend;sendRL+=t.left*fade*layers[t.layer].reverbSend;sendRR+=t.right*fade*layers[t.layer].reverbSend;sendSL+=t.left*fade*layers[t.layer].shimmerSend;sendSR+=t.right*fade*layers[t.layer].shimmerSend;}--t.remaining;}
            // ---- Master FX power ----
            // Targets are fixed for the block. Only effects in the middle of a fade move.
            if(fxMoving){
                for(int i=0;i<FxSlotCount;i++)if(fxMoving&(1u<<i)){
                    auto& f=fxPower[size_t(i)];const float target=fxTarget[size_t(i)];
                    f.ramp=target>f.ramp?std::min(target,f.ramp+fxStep):std::max(target,f.ramp-fxStep);
                    fxGain(i)=fxCurve(f.ramp);
                    if(f.ramp==target)fxMoving&=~(1u<<i);
                }
            }
            // Every effect below runs only while its gain is above zero. A powered-off
            // effect whose fade has finished costs nothing; its gain is exactly zero, so
            // skipping it leaves the bus exactly as the gated code would have.
            // Effects built on delay lines also fade what they record: a line reopened
            // after a wipe then fills gradually, so its first repeat cannot step in.
            // At full power the gain is exactly 1 and the signal path is unchanged.
            // The chorus, delay and Schroeder room are shared stereo sends.
            if(chorusPower>0.f) {
                chorusL[chorusPosition]=outL*chorusPower;chorusR[chorusPosition]=outR*chorusPower;
                float chorusDelayL=float(sampleRate)*(.009f+.0028f*global[AGChorusDepth]*std::sin(tau*chorusPhase));
                float chorusDelayR=float(sampleRate)*(.011f+.0028f*global[AGChorusDepth]*std::sin(tau*(chorusPhase+.25f)));
                outL+=delayed(chorusL,chorusPosition,chorusDelayL)*global[AGChorusMix]*.5f*chorusPower;
                outR+=delayed(chorusR,chorusPosition,chorusDelayR)*global[AGChorusMix]*.5f*chorusPower;
                chorusPosition=(chorusPosition+1)%chorusSize;chorusPhase+=global[AGChorusRate]/float(sampleRate);if(chorusPhase>=1)chorusPhase-=1;
            }
            // Four swept all-pass stages per channel form moving cancellation
            // notches when blended with the dry signal. Coefficients stay stable.
            if(phaserPower>0.f) {
                phaserMix+=smooth*(global[AGPhaserMix]-phaserMix);
                if((sampleCounter&15)==0) {
                    for(int channel=0;channel<2;channel++) {
                        float sweep=.5f+.5f*global[AGPhaserDepth]*std::sin(tau*(phaserPhase+channel*.18f));
                        float hz=180.f*std::exp2(sweep*3.6f);
                        float tangent=std::tan(pi*std::min(hz,float(sampleRate)*.4f)/float(sampleRate));
                        phaserCoefficient[channel]=(tangent-1)/(tangent+1);
                    }
                }
                float phased[2]={outL+phaserFeedback[0]*global[AGPhaserFeedback],outR+phaserFeedback[1]*global[AGPhaserFeedback]};
                for(int channel=0;channel<2;channel++)for(float& state:phaserState[channel]) {
                    float input=phased[channel];
                    phased[channel]=phaserCoefficient[channel]*input+state;
                    state=input-phaserCoefficient[channel]*phased[channel];
                }
                for(int channel=0;channel<2;channel++)phaserFeedback[channel]=std::tanh(phased[channel]);
                outL+=phaserMix*.5f*(phased[0]-outL)*phaserPower;
                outR+=phaserMix*.5f*(phased[1]-outR)*phaserPower;
                phaserPhase+=global[AGPhaserRate]/float(sampleRate);if(phaserPhase>=1)phaserPhase-=1;
            }
            // ---- 0.25.0 inserts: flanger → tremolo/pan/rotary → auto-wah → bitcrusher ----
            if(flangerPower>0.f) {
                flangerMix+=smooth*(global[AGFlangerMix]-flangerMix);
                if(flangerMix>1e-3f) {
                    float dep=std::clamp(global[AGFlangerDepth],0.f,1.f);
                    float fb=panicFxStarved?0.f:std::clamp(global[AGFlangerFeedback],0.f,.9f);
                    float dL=float(sampleRate)*(.0009f+.0041f*dep*(.5f+.5f*std::sin(tau*flangerPhase)));
                    float dR=float(sampleRate)*(.0009f+.0041f*dep*(.5f+.5f*std::sin(tau*(flangerPhase+.25f))));
                    float inL=outL+flangerFBL,inR=outR+flangerFBR;
                    if(!std::isfinite(inL))inL=outL; if(!std::isfinite(inR))inR=outR;
                    flangerBufL[flangerPos]=inL*flangerPower;flangerBufR[flangerPos]=inR*flangerPower;
                    float fL=delayed(flangerBufL,flangerPos,dL),fR=delayed(flangerBufR,flangerPos,dR);
                    if(!std::isfinite(fL))fL=0; if(!std::isfinite(fR))fR=0;
                    flangerFBL=std::tanh(fL)*fb*flangerPower;flangerFBR=std::tanh(fR)*fb*flangerPower;
                    if(++flangerPos>=flangerBufL.size())flangerPos=0;
                    outL+=fL*flangerMix*flangerPower;outR+=fR*flangerMix*flangerPower;
                    flangerPhase+=global[AGFlangerRate]/float(sampleRate);if(flangerPhase>=1)flangerPhase-=1;
                }
            }
            if(tremPower>0.f) {
                // Tremolo/pan/rotary is a pure gain stage: gating its depth to zero
                // returns exactly unity, so bypass restores the untouched dry bus.
                float tMix=std::clamp(global[AGTremMix],0.f,1.f)*tremPower;
                if(tMix>1e-3f) {
                    tremPhase+=global[AGTremRate]/float(sampleRate);if(tremPhase>=1)tremPhase-=1;
                    float d=std::clamp(global[AGTremDepth],0.f,1.f)*tMix;
                    float s=std::sin(tau*tremPhase);
                    int mode=int(std::lround(std::clamp(global[AGTremMode],0.f,2.f)));
                    if(mode==1){outL*=1.f-d*(.5f+.5f*s);outR*=1.f-d*(.5f-.5f*s);}
                    else if(mode==2){outL*=1.f-d*(.5f+.5f*s);outR*=1.f-d*(.5f+.5f*std::sin(tau*tremPhase+pi*.5f));}
                    else {float g=1.f-d*(.5f+.5f*s);outL*=g;outR*=g;}
                }
            }
            if(wahPower>0.f) {
                // The power fade scales the wet blend directly (as every other effect's
                // return does). Routed through the Mix smoother it lagged the fade and was
                // still audible when the effect stopped. The block also keeps running until
                // the smoothed Mix has settled, so pulling Mix down quickly cannot click.
                float wMix=std::clamp(global[AGWahMix],0.f,1.f);
                if(wMix>1e-3f||wahMixS>1e-4f) {
                    wahMixS+=smooth*(wMix-wahMixS);
                    float envIn=std::abs(outL+outR)*.5f;
                    wahEnv+=(envIn>wahEnv?wahAttCoef:wahRelCoef)*(envIn-wahEnv);
                    float sens=std::clamp(global[AGWahSensitivity],0.f,1.f),range=std::clamp(global[AGWahRange],0.f,1.f);
                    float drive=std::clamp(wahEnv*(sens*10.f),0.f,1.f);
                    float hz=120.f*std::exp2(drive*range*5.5f);
                    bool band=global[AGWahMode]>=.5f;
                    float wet[2];
                    for(int ch=0;ch<2;ch++) {
                        float inCh=ch==0?outL:outR;
                        float g=std::tan(pi*std::min(hz,float(sampleRate)*.45f)/float(sampleRate));
                        float hp=inCh-wahLP[ch]-1.2f*wahBP[ch];
                        wahBP[ch]+=g*hp;wahLP[ch]+=g*wahBP[ch];
                        if(!std::isfinite(wahLP[ch])||!std::isfinite(wahBP[ch])){wahLP[ch]=0;wahBP[ch]=0;}
                        wet[ch]=band?wahBP[ch]:wahLP[ch];
                    }
                    const float amount=wahMixS*wahPower;
                    outL+=amount*(wet[0]-outL);outR+=amount*(wet[1]-outR);
                }
            }
            if(crushPower>0.f) {
                float cMix=std::clamp(global[AGCrushMix],0.f,1.f)*crushPower;
                if(cMix>1e-3f) {
                    float bits=std::clamp(global[AGCrushBits],1.f,16.f);
                    float levels=std::exp2(bits-1.f);
                    float wetL=outL,wetR=outR;
                    float holdAmt=std::clamp(global[AGCrushDownsample],1.f,64.f);
                    if(holdAmt>=1.5f) {
                        if(++crushCounter>=int(holdAmt)){crushCounter=0;crushHoldL=outL;crushHoldR=outR;}
                        wetL=crushHoldL;wetR=crushHoldR;
                    } else crushCounter=0;
                    wetL=std::round(wetL*levels)/levels;wetR=std::round(wetR*levels)/levels;
                    if(!std::isfinite(wetL))wetL=outL; if(!std::isfinite(wetR))wetR=outR;
                    outL+=cMix*(wetL-outL);outR+=cMix*(wetR-outR);
                }
            }
            float dl=0,dr=0;
            if(delayPower>0.f) {
                // A delay resuming from idle starts at its current time (it would otherwise
                // glide from the value it had when it went quiet).
                if(delayResume){delaySamples=std::min(float(delaySize-2),std::max(1.f,delayTarget));delayResume=false;}
                delaySamples+=smooth*.05f*(std::min(float(delaySize-2),std::max(1.f,delayTarget))-delaySamples);
                if(!std::isfinite(delaySamples)||delaySamples<1.f)delaySamples=std::max(1.f,delayTarget);
                dl=delayed(delayL,delayPosition,delaySamples);dr=delayed(delayR,delayPosition,delaySamples);
                if(!std::isfinite(dl))dl=0; if(!std::isfinite(dr))dr=0;
                // Delay ducking: repeats step aside while you play (Amount>0), release sets the return time.
                float duckGain=1.f;
                if(global[AGDuckAmount]>1e-3f) {
                    float envIn=std::abs(outL)+std::abs(outR);
                    duckEnv+=(envIn>duckEnv?duckAttCoef:duckRelCoef)*(envIn-duckEnv);
                    duckGain=1.f-std::clamp(global[AGDuckAmount],0.f,1.f)*std::min(1.f,duckEnv*4.f);
                } else duckEnv=0;
                dl*=duckGain;dr*=duckGain;
                float ping=std::clamp(global[AGDelayPingPong],0.f,1.f);
                float fbInL=dr*ping+dl*(1.f-ping);
                float fbInR=dl*ping+dr*(1.f-ping);
                // Tone: 0 dark (heavy LPF) … 1 bright (almost bypass)
                float toneAmt=std::clamp(global[AGDelayTone],0.f,1.f);
                float toneCoeff=.05f+.45f*toneAmt;
                delayToneL+=toneCoeff*(fbInL-delayToneL);
                delayToneR+=toneCoeff*(fbInR-delayToneR);
                if(!std::isfinite(delayToneL)||!std::isfinite(delayToneR)){delayToneL=0;delayToneR=0;}
                // Soft-clip feedback so scrubbing Mix/Feedback/Tone cannot lock the bus/limiter
                // During Panic fade-out, freeze delay regeneration so the wipe is near energy-free
                float fbAmt=std::clamp(global[AGDelayFeedback],0.f,.85f);
                if(panicFxStarved)fbAmt=0;
                // A closing delay stops regenerating; its line is wiped once the fade ends.
                fbAmt*=delayPower;
                float fbL=std::tanh(delayToneL*fbAmt);
                float fbR=std::tanh(delayToneR*fbAmt);
                float writeL=sendDL*delayPower+fbL, writeR=sendDR*delayPower+fbR;
                if(!std::isfinite(writeL))writeL=0; if(!std::isfinite(writeR))writeR=0;
                delayL[delayPosition]=writeL;delayR[delayPosition]=writeR;
                delayPosition=(delayPosition+1)%delaySize;
            }
            float rl=0,rr=0;
            if(verbPower>0.f) {
                float reverbInput=(sendRL+sendRR)*.16f*verbPower;
                for(int i=0;i<4;i++){rl+=combs[i].process(reverbInput);rr+=combs[i+4].process(reverbInput);}
                rl=allpasses[1].process(allpasses[0].process(rl));rr=allpasses[3].process(allpasses[2].process(rr));
            }
            outL+=dl*global[AGDelayMix]*delayPower+rl*global[AGReverbMix]*.25f*verbPower;
            outR+=dr*global[AGDelayMix]*delayPower+rr*global[AGReverbMix]*.25f*verbPower;

            // ---- Full Shimmer (pitch-shifted multi-voice diffusion) ----
            // Input is shimmer-send only — never the wet bus — so Mix/Amount cannot form an outer feedback loop.
            if(shimPower>0.f) {
                float shimmerIn=std::tanh((sendSL+sendSR)*.10f*shimPower);
                // Soft-clip predelay write (send + internal fb)
                float fbLIn=panicFxStarved?0.f:shimmerFbL;
                float fbRIn=panicFxStarved?0.f:shimmerFbR;
                float preWriteL=std::tanh(shimmerIn+fbLIn);
                float preWriteR=std::tanh(shimmerIn+fbRIn);
                if(!std::isfinite(preWriteL))preWriteL=0; if(!std::isfinite(preWriteR))preWriteR=0;
                shimmerPreL[shimmerPreWrite]=preWriteL;
                shimmerPreR[shimmerPreWrite]=preWriteR;
                float preSamples=std::clamp(global[AGShimmerPredelay]*.001f*float(sampleRate),0.f,float(shimmerPredelaySize-2));
                size_t preRead=(shimmerPreWrite+shimmerPredelaySize-size_t(preSamples))%shimmerPredelaySize;
                float preL=shimmerPreL[preRead],preR=shimmerPreR[preRead];
                shimmerPreWrite=(shimmerPreWrite+1)%shimmerPredelaySize;

                // Early reflections: short comb-ish one-pole + allpass size
                float earlySize=.002f+.028f*std::clamp(global[AGShimmerEarlySize],0.f,1.f);
                float earlyCoeff=std::exp(-1.f/(earlySize*float(sampleRate)+1.f));
                shimmerEarlyStateL=earlyCoeff*shimmerEarlyStateL+(1.f-earlyCoeff)*preL;
                shimmerEarlyStateR=earlyCoeff*shimmerEarlyStateR+(1.f-earlyCoeff)*preR;
                if(!std::isfinite(shimmerEarlyStateL)||!std::isfinite(shimmerEarlyStateR)){shimmerEarlyStateL=shimmerEarlyStateR=0;}
                float earlyL=shimmerEarlyStateL*global[AGShimmerEarlyLevel];
                float earlyR=shimmerEarlyStateR*global[AGShimmerEarlyLevel];

                // Write into pitch buffer (forward)
                shimmerBufL[shimmerWrite]=preL;
                shimmerBufR[shimmerWrite]=preR;

                // Harmony voices: +5, +7, +12 relative to AGShimmerPitch base
                constexpr float voiceSemi[3]={5.f,7.f,12.f};
                float voiceLvl[3]={global[AGShimmerVoice1],global[AGShimmerVoice2],global[AGShimmerVoice3]};
                float baseSemi=global[AGShimmerPitch];
                bool reverse=global[AGShimmerReverse]>=.5f;
                float pitchedL=0,pitchedR=0;
                for(int v=0;v<3;v++){
                    float ratio=std::exp2((baseSemi+voiceSemi[v])/12.f);
                    // Grain window ~40ms; advance read by ratio (or -ratio for reverse)
                    float grainSamples=float(sampleRate)*.04f;
                    float step=reverse?-ratio:ratio;
                    shimmerReadL[v]+=step;
                    shimmerReadR[v]+=step;
                    if(shimmerReadL[v]<0)shimmerReadL[v]+=grainSamples;
                    if(shimmerReadL[v]>=grainSamples)shimmerReadL[v]-=grainSamples;
                    if(shimmerReadR[v]<0)shimmerReadR[v]+=grainSamples;
                    if(shimmerReadR[v]>=grainSamples)shimmerReadR[v]-=grainSamples;
                    auto tap=[&](const std::array<float,shimmerSize>& buf,float offset)->float{
                        float pos=float(shimmerWrite)+shimmerSize-offset;
                        while(pos<0)pos+=float(shimmerSize);
                        size_t i0=size_t(pos)%shimmerSize;
                        size_t i1=(i0+1)%shimmerSize;
                        float frac=pos-std::floor(pos);
                        return buf[i0]*(1.f-frac)+buf[i1]*frac;
                    };
                    // Two taps with Hann crossfade for smoother pitch shift
                    float o1=shimmerReadL[v]+float(sampleRate)*.012f;
                    float o2=o1+grainSamples*.5f;
                    float w=shimmerReadL[v]/grainSamples;
                    float hann1=.5f-.5f*std::cos(tau*w);
                    float hann2=.5f-.5f*std::cos(tau*std::fmod(w+.5f,1.f));
                    float gL=tap(shimmerBufL,o1)*hann1+tap(shimmerBufL,o2)*hann2;
                    float gR=tap(shimmerBufR,o1)*hann1+tap(shimmerBufR,o2)*hann2;
                    float lvl=std::clamp(voiceLvl[v],0.f,1.f);
                    pitchedL+=gL*lvl;pitchedR+=gR*lvl;
                }
                // Soft-clip stacked voices so +5/+7/+12 cannot overdrive diffusion
                pitchedL=std::tanh(pitchedL*.55f);pitchedR=std::tanh(pitchedR*.55f);
                shimmerWrite=(shimmerWrite+1)%shimmerSize;

                // Late diffusion: Schroeder-ish on pitched signal, decay from LateDecay/ShimmerDecay
                float lateDecay=std::max(global[AGShimmerLateDecay],global[AGShimmerDecay]);
                for(int i=0;i<4;i++){
                    shimmerCombs[i].feedback=std::min(.92f,std::pow(.001f,float(shimmerCombs[i].length/sampleRate)/std::max(.2f,lateDecay)));
                }
                float lateIn=std::tanh((pitchedL+pitchedR)*.30f);
                float late=0;
                for(int i=0;i<4;i++)late+=shimmerCombs[i].process(lateIn);
                late=shimmerAllpasses[1].process(shimmerAllpasses[0].process(late));
                if(!std::isfinite(late))late=0;
                late*=global[AGShimmerLateLevel];

                // Tone LPF; Amount uses a squared curve so high settings stay musical without runaway
                float st=std::clamp(global[AGShimmerTone],0.f,1.f);
                float stCoeff=.04f+.5f*st;
                float wetL=earlyL+pitchedL*.45f+late*.55f;
                float wetR=earlyR+pitchedR*.45f+late*.55f;
                shimmerToneStateL+=stCoeff*(wetL-shimmerToneStateL);
                shimmerToneStateR+=stCoeff*(wetR-shimmerToneStateR);
                if(!std::isfinite(shimmerToneStateL)||!std::isfinite(shimmerToneStateR)){shimmerToneStateL=shimmerToneStateR=0;}
                float amount=std::clamp(global[AGShimmerAmount],0.f,.95f);
                // Power off starves both the input and the regeneration, so the
                // diffusion network decays to zero instead of holding its tail.
                float fbGain=amount*amount*.38f*shimPower;
                if(panicFxStarved){
                    shimmerFbL=shimmerFbR=0;
                }else{
                    shimmerFbL=std::tanh(shimmerToneStateL*fbGain);
                    shimmerFbR=std::tanh(shimmerToneStateR*fbGain);
                    if(!std::isfinite(shimmerFbL)||!std::isfinite(shimmerFbR)){shimmerFbL=shimmerFbR=0;shimmerToneStateL=shimmerToneStateR=0;}
                }

                float mix=std::clamp(global[AGShimmerMix],0.f,1.f);
                outL+=std::tanh(shimmerToneStateL)*mix*.9f*shimPower;
                outR+=std::tanh(shimmerToneStateR)*mix*.9f*shimPower;
            }


            // ---- Insert EQ on final stereo bus (before master/limiter) ----
            // Gains and pole coefficients only change at block boundaries (see eqLowG etc.).
            {
                auto eqChan=[&](float x,float& lo,float& mid,float& hi)->float{
                    lo=eqLowC*lo+(1.f-eqLowC)*x;
                    float highPass=x-lo;
                    mid=eqMidC*mid+(1.f-eqMidC)*highPass;
                    float presence=highPass-mid;
                    hi=eqHighC*hi+(1.f-eqHighC)*presence;
                    float air=presence-hi;
                    return lo*eqLowG+mid*eqMidG+hi*eqHighG+air;
                };
                outL=eqChan(outL,eqLowL,eqMidL,eqHighL);
                outR=eqChan(outR,eqLowR,eqMidR,eqHighR);
            }

            // ---- Master-bus compressor (feed-forward, zero lookahead) ----
            if(compPower>0.f) {
                float in=std::max(std::abs(outL),std::abs(outR));
                if(!std::isfinite(in))in=0;
                compEnv+=(in>compEnv?compAttCoef:compRelCoef)*(in-compEnv);
                float envDb=20.f*std::log10(std::max(compEnv,1.0e-6f));
                float over=envDb-compThreshold;
                float gr=over>0 ? over*(1.f-1.f/compRatio) : 0.f;
                float makeDb=compMakeup;
                // Fading the switch scales both gain reduction and makeup toward unity.
                makeDb*=compPower;gr*=compPower;
                float g=std::pow(10.f,(makeDb-gr)*.05f);
                if(std::isfinite(g)&&g>0){outL*=g;outR*=g;}
                if(gr>blockMaxGR)blockMaxGR=gr;
            }
            master+=smooth*(masterTarget-master);
            float finalL=std::tanh(outL*master),finalR=std::tanh(outR*master);
            outputGain+=smooth*(gainTarget-outputGain);
            if(outputGain>1.00001f){
                finalL*=outputGain;finalR*=outputGain;
                float peak=std::max(std::abs(finalL),std::abs(finalR));
                float target=std::min(1.f,.98f/std::max(.00001f,peak));
                // Attack fast on peaks; release quieter when quiet so Delay scrubbing cannot leave the bus muted
                float release=peak<.05f ? quietLimiterRelease : limiterRelease;
                outputLimiter=target<outputLimiter?target:outputLimiter+release*(target-outputLimiter);
                if(!std::isfinite(outputLimiter)||outputLimiter<.0001f)outputLimiter=peak>1.f?.0001f:1.f;
                finalL*=outputLimiter;finalR*=outputLimiter;
            }else outputLimiter=1;
            // Panic gain applied last (pg advanced at sample start). Idle → pg stays 1.
            finalL=std::isfinite(finalL)?finalL*pg:0;finalR=std::isfinite(finalR)?finalR*pg:0;
            left[frame]=finalL;right[frame]=finalR;
            // A mono sum can cancel wide/phase-opposed stereo sounds and falsely look quiet.
            if((sampleCounter&3)==0)scopeSamples[(scopePosition++)%scopeSamples.size()].store(left[frame],std::memory_order_relaxed);
            maximum=std::max(maximum,std::max(std::abs(left[frame]),std::abs(right[frame])));
        }
        scopePublished.store(scopePosition,std::memory_order_release);
        gainReduction.store(blockMaxGR,std::memory_order_relaxed);
        for(int i=0;i<kFeedbackCount;i++)modulationFeedback[i].store(frameFeedback[i],std::memory_order_relaxed);
        int count=0;unsigned activeLayers=0;for(const auto& v:voices)if(v.active){++count;activeLayers|=1u<<v.layer;}
        previewActiveLayers.store(activeLayers);
        for(int l=0;l<4;l++){
            const Voice* latest=nullptr;for(const auto& v:voices)if(v.active&&v.layer==l&&(!latest||v.serial>latest->serial))latest=&v;
            motionPlayheads[l].store(latest&&layers[l].motion.enabled()?float(latest->motionTime):-1);
        }
        voiceCount.store(count,std::memory_order_relaxed);
        outputPeak.store(maximum,std::memory_order_relaxed);
    }
};
SynthEngine::SynthEngine():impl(std::make_unique<Impl>()){}
SynthEngine::~SynthEngine()=default;
void SynthEngine::prepare(double sampleRate){impl->prepare(sampleRate);}
void SynthEngine::setParameter(int layer,int parameter,float value) {
    if(layer>=0&&layer<kLayers&&parameter>=0&&parameter<APParameterCount){
        float v=parameterValue(parameter,value);
        if(impl->panicDeferParams.load(std::memory_order_acquire))
            impl->pendingParameters[layer][parameter].store(v,std::memory_order_relaxed);
        else
            impl->parameters[layer][parameter].store(v,std::memory_order_relaxed);
    }
}
void SynthEngine::setLayerFM(int layer,const float* data,int count) {
    if(layer<0||layer>=kLayers||!data||count<=0)return;
    int n=std::min(count,int(kFmParamCount));
    bool defer=impl->panicDeferParams.load(std::memory_order_acquire);
    for(int i=0;i<n;i++){
        float v=data[i];
        if(!std::isfinite(v))continue;
        if(defer)impl->pendingFmParameters[layer][i].store(v,std::memory_order_relaxed);
        else impl->fmParameters[layer][i].store(v,std::memory_order_relaxed);
    }
}
float SynthEngine::getParameter(int layer,int parameter)const {
    return layer>=0&&layer<kLayers&&parameter>=0&&parameter<APParameterCount?
        impl->parameters[layer][parameter].load(std::memory_order_relaxed):0;
}
void SynthEngine::setTranspose(int semitones) { impl->transpose.store(std::clamp(semitones,-24,24),std::memory_order_relaxed); }
void SynthEngine::setGlobal(int parameter,float value) {
    if(parameter>=0&&parameter<AGGlobalCount){
        float v=globalValue(parameter,value);
        if(impl->panicDeferParams.load(std::memory_order_acquire))
            impl->pendingGlobals[parameter].store(v,std::memory_order_relaxed);
        else
            impl->globals[parameter].store(v,std::memory_order_relaxed);
    }
}
float SynthEngine::getGlobal(int parameter)const {
    return parameter>=0&&parameter<AGGlobalCount?impl->globals[parameter].load(std::memory_order_relaxed):0;
}
void SynthEngine::midi(int32_t sourceID,uint8_t status,uint8_t data1,uint8_t data2) {
    if(status>=0x80&&status<0xf0)impl->submit({Event::MIDI,sourceID,status,data1,data2});
}
void SynthEngine::route(int32_t sourceID,int layerMask,int channel){impl->submit({Event::Route,sourceID,layerMask,channel,0});}
void SynthEngine::velocityCurve(int32_t sourceID,int curve){impl->submit({Event::Curve,sourceID,curve,0,0});}
void SynthEngine::hold(bool enabled){impl->submit({Event::Hold,0,int(enabled),0,0});}
void SynthEngine::clockSource(bool enabled,int32_t sourceID){impl->submit({Event::ClockSource,sourceID,int(enabled),0,0});}
void SynthEngine::clock(int32_t sourceID,uint8_t status,double seconds){Event e{Event::Clock,sourceID,status,0,0};e.seconds=seconds;impl->submit(e);}
float SynthEngine::clockTempo() const{return impl->clockBPM.load(std::memory_order_relaxed);}
void SynthEngine::disconnect(int32_t sourceID){impl->submit({Event::Disconnect,sourceID,0,0,0});}
void SynthEngine::panic(){impl->requestPanic();}
void SynthEngine::render(float* left,float* right,uint32_t frames){impl->render(left,right,frames);}
float SynthEngine::peak()const{return impl->outputPeak.load(std::memory_order_relaxed);}
float SynthEngine::gainReduction()const{return impl->gainReduction.load(std::memory_order_relaxed);}
int SynthEngine::activeVoices()const{return impl->voiceCount.load(std::memory_order_relaxed);}
}

int aurora::SynthEngine::copyScope(float* samples,int capacity) const {
    if(!samples || capacity<=0)return 0;
    int count=std::min(capacity,8192);
    unsigned end=impl->scopePublished.load(std::memory_order_acquire);
    for(int i=0;i<count;i++)samples[i]=impl->scopeSamples[(end-count+i)%impl->scopeSamples.size()].load(std::memory_order_relaxed);
    return count;
}

void aurora::SynthEngine::setMatrix(int bank,int slot,bool enabled,int source,int destination,int target,int cc,float amount) {
    int slotLimit=10;
    if(bank<0||bank>4||slot<0||slot>=slotLimit)return;
    bool soundBlocked=bank!=4 && ((source<0||source>10) || destination<0 || destination>46 || (destination>7 && destination<12));
    bool performanceBlocked=bank==4 && (source<0||source>5||destination<0||destination>20);
    if(soundBlocked||performanceBlocked||target<0||target>4||cc<0||cc>127||!std::isfinite(amount))enabled=false;
    unsigned a=unsigned(int(std::round(std::clamp(std::isfinite(amount)?amount:0.f,-1.f,1.f)*32767))+32768);
    uint64_t bits=enabled?(1ull|(uint64_t(source)<<1)|(uint64_t(destination)<<5)|(uint64_t(target)<<11)|(uint64_t(cc)<<14)|(uint64_t(a)<<21)):0;
    impl->matrix[bank][slot].store(bits,std::memory_order_relaxed);
}
int aurora::SynthEngine::copyModulation(float* values,int capacity) const {
    if(!values||capacity<=0)return 0;
    int count=std::min(capacity,50);
    for(int i=0;i<count;i++)values[i]=impl->modulationFeedback[i].load(std::memory_order_relaxed);
    return count;
}

bool aurora::SynthEngine::setCustomWavetable(int layer,int oscillator,const float* samples,int frames,int frameSize) {
    if(layer<0||layer>=4||oscillator<0||oscillator>=2)return false;
    try {
        auto bank=wt::make(samples,frames,frameSize);if(!bank)return false;
        if(impl->tableReaders.load()==0)impl->retiredBanks.clear();
        else {
            auto completed=impl->completedTableRenders.load();
            std::erase_if(impl->retiredBanks,[completed](const auto& bank){return completed>bank.completed;});
        }
        if(impl->retiredBanks.size()>=8)return false;
        int slot=layer*2+oscillator;
        impl->customBanks[slot].exchange(bank.get());
        if(impl->ownedBanks[slot])impl->retiredBanks.push_back({std::move(impl->ownedBanks[slot]),impl->completedTableRenders.load()});
        impl->ownedBanks[slot]=std::move(bank);
        if(impl->tableReaders.load()==0)impl->retiredBanks.clear();
        return true;
    }catch(...){return false;}
}
void aurora::SynthEngine::clearCustomWavetable(int layer,int oscillator) {
    if(layer<0||layer>=4||oscillator<0||oscillator>=2)return;
    // A cleared owner can remain alive until its next replacement. No freeing on render.
    impl->customBanks[layer*2+oscillator].store(nullptr);
    if(impl->tableReaders.load()==0){impl->ownedBanks[layer*2+oscillator].reset();impl->retiredBanks.clear();}
}
int aurora::SynthEngine::copyWavetablePreview(int layer,int oscillator,float* samples,int capacity) const {
    if(layer<0||layer>=4||oscillator<0||oscillator>=2||!samples||capacity<=0)return 0;
    int base=APWT1Enabled+oscillator*7,slot=layer*2+oscillator;
    int table=int(getParameter(layer,base+1));
    const auto* bank=table==24?impl->customBanks[slot].load():wt::factory()[table].get();
    float position=getParameter(layer,base+2),amount=getParameter(layer,base+4);
    if(impl->previewActiveLayers.load()&(1u<<layer)){position=impl->previewPosition[slot].load();amount=impl->previewAmount[slot].load();}
    int count=std::min(capacity,512);
    for(int i=0;i<count;i++)samples[i]=bank?bank->shapedSample(float(i)/float(std::max(1,count-1)),.0001f,position,int(getParameter(layer,base+3)),amount,getParameter(layer,APWT1Formant+oscillator*2),getParameter(layer,APWT1Tone+oscillator*2)):0;
    return count;
}
const char* aurora::SynthEngine::wavetableName(int index){return index>=0&&index<24?wt::names[index]:"Imported";}
const char* aurora::SynthEngine::wavetableCategory(int index){return index>=0&&index<24?wt::categories[index]:"Custom";}

bool aurora::SynthEngine::setMotion(int layer,const float* data,int count){
    if(layer<0||layer>=4||!MotionEnvelope::valid(data,count))return false;
    auto& packet=impl->motionPackets[layer];packet.version.fetch_add(1);
    for(int i=0;i<motionSize;i++)packet.values[i].store(i<count?data[i]:0);
    packet.version.fetch_add(1);return true;
}
float aurora::SynthEngine::motionPhase(int layer)const{return layer>=0&&layer<4?impl->motionPlayheads[layer].load():-1;}
void aurora::SynthEngine::setLayerSends(int layer,float delay,float reverb,float shimmer){if(layer<0||layer>=4)return;impl->delaySends[layer].store(bounded(delay,0,1));impl->reverbSends[layer].store(bounded(reverb,0,1));impl->shimmerSends[layer].store(bounded(shimmer,0,1));}
void aurora::SynthEngine::soloLayer(int layer){impl->solo.store(layer>=0&&layer<4?layer:-1);}
