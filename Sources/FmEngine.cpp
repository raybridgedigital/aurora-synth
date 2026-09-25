#include "FmEngine.hpp"
#include "Wavetable.hpp"
#include <algorithm>
#include <array>
#include <cmath>
// 4-operator FM / phase-modulation core — FUTURE-PROPOSAL-FM-ENGINE.md (LOCKED v1.0) §4, §5, §10.
// 16 algorithms, per-operator rate/level envelopes (ADSR alternate), one algorithm-designated
// feedback op, dedicated pitch strike envelope, fixed 2x oversampling of the modulator chain,
// double-precision phases, denormal-safe parked state, finite guards that reset voice state.
namespace aurora {
namespace {
constexpr float kTau=6.283185307179586f;
constexpr int kSineBits=12,kSineSize=1<<kSineBits; // 4096-entry sine, linear interp
// Full-level modulator -> phase cycles. ~10 cycles reaches tine-bark sidebands.
constexpr float kIndexCycles=10.f;
// Feedback depth at amount 1. DX-like scream with a hard, bounded reach.
constexpr float kFeedbackCycles=6.f;
struct Tables { float sine[kSineSize+1]{}; };
Tables& tables(){static Tables t;return t;}
struct Algo { const char* name; int8_t target[4]; int8_t feedbackOp; };
// target[o] = op modulated by o (-1 = carrier). feedbackOp = designated self-mod op (-1 = none).
// Families per spec §4: 4 single-carrier chains · 5 two-carrier pairs (EP home) ·
// 4 stacked/additive-ish · 3 feedback-forward.
constexpr Algo kAlgos[16]={
    {"Deep Chain",    { 1, 2, 3,-1}, 0},
    {"Twin Roots",    { 2, 2, 3,-1}, 0},
    {"Split Chain",   { 1, 3, 3,-1}, 0},
    {"Triple Root",   { 3, 3, 3,-1}, 0},
    {"EP Twin",       {-1,-1, 0, 1}, 2},
    {"Chain & Solo",  {-1, 0, 1,-1}, 2},
    {"Mirror Pair",   { 1,-1,-1, 2}, 0},
    {"Nested Twin",   {-1,-1, 3, 0}, 2},
    {"Hub Pair",      { 2, 3,-1,-1}, 0},
    {"Triple Crown",  {-1,-1,-1, 0}, 3},
    {"Post Stack",    {-1,-1,-1, 1}, 3},
    {"Head Stack",    { 3,-1,-1,-1}, 0},
    {"Pure Additive", {-1,-1,-1,-1},-1},
    {"Deep Feedback", { 1, 2, 3,-1}, 2},
    {"Twin Feedback", {-1,-1, 0, 1}, 3},
    {"Loopback",      { 1, 2, 3,-1}, 3},
};
// The order in which each algorithm evaluates its operators within one modulator tick:
// an operator runs once every operator modulating it has run, lowest index first within
// a round. It depends only on the algorithm, so it is resolved at compile time instead
// of re-deriving it twice per sample per voice.
struct AlgoOrder { int8_t op[4]{}; int8_t count=0; };
constexpr std::array<AlgoOrder,16> kOrders=[]{
    std::array<AlgoOrder,16> out{};
    for(int a=0;a<16;a++){
        const Algo& A=kAlgos[a];bool done[4]={};int n=0;
        for(int round=0;round<4;round++){
            bool progress=false;
            for(int o=0;o<4;o++){
                if(done[o])continue;
                bool ready=true;
                for(int k=0;k<4;k++)if(A.target[k]==o&&!done[k]){ready=false;break;}
                if(!ready)continue;
                out[size_t(a)].op[n++]=int8_t(o);done[o]=true;progress=true;
            }
            if((done[0]&&done[1]&&done[2]&&done[3])||!progress)break;
        }
        out[size_t(a)].count=int8_t(n);
    }
    return out;
}();
float polyBlep(float phase,float step){
    if(phase<step){float t=phase/step;return 2*t-t*t-1.f;}
    if(phase>1-step){float t=(phase-(1-step))/step;return (t-2)*t+1.f;}
    return 0.f;
}
float sineLookup(float phase){
    phase-=std::floor(phase);
    float x=phase*float(kSineSize);
    int i=int(x)&(kSineSize-1);
    float f=x-std::floor(x);
    const float* t=tables().sine;
    return t[i]*(1-f)+t[i+1]*f;
}
// phase in cycles; step in cycles/sample (anti-alias correction).
float opWave(int wave,float phase,float step,float width,float table,float pos,float warp){
    phase-=std::floor(phase);
    switch(std::clamp(wave,0,4)){
        case 1:return 1.f-4.f*std::abs(phase-.5f);
        case 2:return 2.f*phase-1.f-polyBlep(phase,step);
        case 3:{width=std::clamp(width,.05f,.95f);
            float v=phase<width?1.f:-1.f;
            v+=polyBlep(phase,step);
            v-=polyBlep(std::fmod(phase+1-width,1.f),step);
            return v;}
        case 4:{auto* bank=wt::factory()[std::clamp(int(table),0,23)].get();
            if(!bank)return sineLookup(phase);
            float amount=std::clamp(warp,0.f,1.f);
            return bank->sample(phase,step,std::clamp(pos,0.f,1.f),amount>0?1:0,amount,0.f);}
        default:return sineLookup(phase);
    }
}
} // namespace
void FmEngine::initTables(){
    auto& t=tables();
    for(int i=0;i<=kSineSize;i++)t.sine[i]=std::sin(kTau*float(i)/float(kSineSize));
    wt::factory(); // pre-build wavetable banks while audio is stopped (never on the callback)
}
int FmEngine::algorithmCount(){return 16;}
const char* FmEngine::algorithmName(int index){return kAlgos[std::clamp(index,0,15)].name;}
float FmEngine::renderSample(const FmParams& params,FmVoiceState& st,float baseHz,
                             float velocity,int key,bool released,double sampleRate,const float* mod){
    const float* g=params.v.data();
    auto opP=[&](int o,int f){return g[kFmGlobalCount+o*kFmOpStride+f];};
    if(!std::isfinite(baseHz)||baseHz<1.f)baseHz=1.f;
    if(!std::isfinite(velocity))velocity=0.f;
    velocity=std::clamp(velocity,0.f,1.f);
    const float sr=float(std::isfinite(sampleRate)&&sampleRate>1000.?sampleRate:48000.);
    float mm[kFmModCount];
    for(int i=0;i<kFmModCount;i++)mm[i]=(!mod||!std::isfinite(mod[i]))?0.f:std::clamp(mod[i],-1.f,1.f);
    // Dedicated pitch strike envelope (spec §5): jumps to amount at note-on, decays to
    // zero over time, curve shapes the fall. Voice zero-state retriggers it per note.
    if(st.pitchClock>=0.f){
        float amount=std::clamp(g[FmPitchEnvAmount]+mm[6],-1.f,1.f)*12.f;
        float time=std::clamp(g[FmPitchEnvTime],.001f,4.f);
        float power=amount==0.f?1.f:std::exp2(-2.f+4.f*std::clamp(g[FmPitchEnvCurve],0.f,1.f)); // 0.25...4
        float t=st.pitchClock/sr;
        if(t<time){
            float x=1.f-t/time;
            st.pitchEnv=amount==0.f?amount:amount*std::pow(std::max(x,0.f),power);
            st.pitchClock+=1.f/sr;
        } else { st.pitchEnv=0.f; st.pitchClock=-1.f; }
    }
    if(st.pitchEnv!=0.f)baseHz*=std::exp2(st.pitchEnv/12.f);
    int alg=std::clamp(int(std::round(g[FmAlgorithm])),0,15);
    const Algo& A=kAlgos[alg];
    float feedback=std::clamp(g[FmFeedback]+mm[4],0.f,1.f);
    float carrierMix=std::clamp(g[FmCarrierMix]+mm[5],0.f,1.f);
    if(std::abs(st.feedbackDelay)<1e-30f)st.feedbackDelay=0.f; // denormal guard
    // Per-operator gather + envelope advance. Envelope labor split (spec §5): op envelopes
    // shape timbre (modulator index / carrier amplitude curve); the layer Amp Env stays
    // the note's loudness and is applied downstream exactly as in Subtractive mode.
    float opLevel[4],opEnv[4],opScale[4],opHz[4],opWidth[4],opPos[4],opWarp[4];
    float opTable[4],opWaveId[4],halfStep[4],stepCyc[4];
    for(int o=0;o<4;o++){
        int envMode=int(opP(o,FmEnvMode));
        float r[4],lv[4];
        for(int i=0;i<4;i++){r[i]=std::clamp(opP(o,FmRate1+i),.02f,200.f);lv[i]=std::clamp(opP(o,FmLevel1+i),0.f,1.f);}
        int ks=std::clamp(int(opP(o,FmKeyScale)),0,3);
        float levelScale=1.f,rateScale=1.f;
        if(ks==1){levelScale=std::exp2(float(60-key)/60.f);rateScale=std::exp2(float(key-60)/120.f);}
        else if(ks==2&&key%2)levelScale=.72f;
        else if(ks==3&&!(key%2))levelScale=.72f;
        // Envelope stage machine: 0 attack → 1 decay → 2 hold → 3 release (note-off enters
        // 3 from any stage). Rate/Level mode: time = 1/rate. ADSR alternate: rates are
        // seconds, decay lands on level3 (sustain); level2 unused in ADSR.
        int stage=int(st.stage[o]);
        if(released&&stage<3)stage=3;
        float target,sec;
        if(envMode==0){
            target=lv[stage];
            sec=1.f/std::max(.02f,r[stage]*rateScale);
        } else if(stage==0){target=lv[0];sec=std::clamp(opP(o,FmRate1),.001f,20.f)*rateScale;}
        else if(stage==1){target=lv[2];sec=std::clamp(opP(o,FmRate2),.001f,20.f)*rateScale;}
        else if(stage==2){target=lv[2];sec=.001f;}
        else {target=lv[3];sec=std::clamp(opP(o,FmRate4),.001f,20.f)*rateScale;}
        float ramp=1.f/(sr*std::max(sec,1e-6f));
        float d=target-st.env[o];
        if(std::abs(d)<=ramp){st.env[o]=target;if(stage<2)stage++;}
        else st.env[o]+=d>0?ramp:-ramp;
        st.stage[o]=int8_t(stage);
        opEnv[o]=st.env[o];
        opLevel[o]=std::clamp(opP(o,FmLevel)+mm[o],0.f,1.f);
        float velSense=std::clamp(opP(o,FmVel),0.f,1.f);
        opScale[o]=levelScale*(1.f-velSense*(1.f-velocity));
        float hz=opP(o,FmFixedMode)>.5f
            ?std::clamp(opP(o,FmFixedHz),1.f,20000.f)
            :baseHz*std::clamp(opP(o,FmRatio),.25f,16.f);
        const float fine=std::clamp(opP(o,FmRatioFine)+mm[7],-1.f,1.f);
        if(fine!=0.f)hz*=std::exp2(fine); // fine ±100¢ (+ matrix)
        if(!std::isfinite(hz))hz=1.f;
        opHz[o]=std::clamp(hz,0.01f,float(sr)*.45f);
        opWaveId[o]=opP(o,FmWave);
        opTable[o]=opP(o,FmWTTable);
        opWidth[o]=opP(o,FmPulseWidth);
        opPos[o]=std::clamp(opP(o,FmWTPos)+mm[8],0.f,1.f);
        opWarp[o]=std::clamp(opP(o,FmWTWarp)+mm[9],0.f,1.f);
        stepCyc[o]=opHz[o]/sr;
        halfStep[o]=stepCyc[o]*.5f;
    }
    // Modulator chain ticks twice per output sample (spec §5: fixed 2x modulator
    // oversampling, no user param). Carrier phases advance once and receive the
    // trapezoid average of the two ticks. Feedback = 1-sample delay at this internal rate.
    float outs[4],inner[4],innerAvg[4]={};
    float fbDelay=st.feedbackDelay;
    const AlgoOrder& order=kOrders[size_t(alg)];
    for(int tick=0;tick<2;tick++){
        {
            for(int step=0;step<order.count;step++){
                const int o=order.op[step];
                float modIn=0.f;
                for(int k=0;k<4;k++)if(A.target[k]==o)modIn+=outs[k]*kIndexCycles;
                float ph=float(st.phase[o]);
                if(o==A.feedbackOp&&A.feedbackOp>=0)ph+=fbDelay*feedback*kFeedbackCycles;
                ph+=modIn;
                float w=opWave(int(opWaveId[o]),ph,stepCyc[o],opWidth[o],opTable[o],opPos[o],opWarp[o]);
                outs[o]=w*opEnv[o]*opLevel[o]*opScale[o];
                inner[o]=modIn;
                if(!std::isfinite(outs[o])){st=FmVoiceState{};return 0.f;}
                if(A.target[o]>=0){ // modulators advance at 2x; carriers wait for their once-per-sample step
                    st.phase[o]+=double(halfStep[o]);
                    st.phase[o]-=std::floor(st.phase[o]);
                }
            }
        }
        if(A.feedbackOp>=0)fbDelay=outs[A.feedbackOp];
        for(int o=0;o<4;o++)if(A.target[o]<0)innerAvg[o]=tick==0?inner[o]:.5f*(innerAvg[o]+inner[o]);
    }
    st.feedbackDelay=std::isfinite(fbDelay)?fbDelay:0.f;
    // Carriers: first carrier takes (1-mix), the rest share mix (n==1 ignores mix).
    int carriers[4],n=0;
    for(int o=0;o<4;o++)if(A.target[o]<0)carriers[n++]=o;
    if(n==0)carriers[n++]=3; // defensive: every shipped algorithm has a carrier
    float out=0.f;
    for(int ci=0;ci<n;ci++){
        int o=carriers[ci];
        float weight=n==1?1.f:(ci==0?1.f-carrierMix:carrierMix/float(n-1));
        float ph=float(st.phase[o]);
        if(o==A.feedbackOp&&A.feedbackOp>=0)ph+=st.feedbackDelay*feedback*kFeedbackCycles;
        ph+=innerAvg[o];
        float w=opWave(int(opWaveId[o]),ph,stepCyc[o],opWidth[o],opTable[o],opPos[o],opWarp[o]);
        out+=w*opEnv[o]*opLevel[o]*opScale[o]*weight;
        st.phase[o]+=double(stepCyc[o]);
        st.phase[o]-=std::floor(st.phase[o]);
    }
    if(!std::isfinite(out)){st=FmVoiceState{};return 0.f;}
    return out;
}
} // namespace aurora


