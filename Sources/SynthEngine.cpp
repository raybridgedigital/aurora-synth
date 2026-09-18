#include "SynthEngine.hpp"
#include "Wavetable.hpp"
#include "MotionEnvelope.hpp"
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
constexpr size_t queueSize=2048, delaySize=768004, chorusSize=8192;
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
        case APLFODestination: case APLFO2Destination: case APArpRate: case APArpMode:
            return std::round(bounded(v,0,3));
        case APFilterType:case APFilter2Type: return std::round(bounded(v,0,3));
        case APArpOctaves: return std::round(bounded(v,1,4,1));
        case APArpGate: return bounded(v,.05f,.95f,.65f);
        case APKeyLow: case APKeyHigh: return std::round(bounded(v,0,127));
        default: return bounded(v,0,1);
    }
}
float globalValue(int p,float v) {
    if(p==AGOutputGain)return bounded(v,0,24);
    if(p==AGPhaserRate||p==AGChorusRate)return bounded(v,.03f,5,.23f);
    if(p==AGPhaserFeedback)return bounded(v,-.85f,.85f);
    if(p==AGReverbDecay)return bounded(v,.2f,8,1);
    if(p==AGDelayTiming)return std::round(bounded(v,0,7));
    if(p==AGTempo) return bounded(v,30,240,120);
    if(p==AGDelayFeedback) return bounded(v,0,.85f,.3f);
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
    std::array<float,2> lfoPhase{},lfoRandom{};
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
    float delaySend=1,reverbSend=1,delayTarget=1,reverbTarget=1;
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
    float gain=0,cutoff=1500,lfoPhase=0,lfo2Phase=0,heldRandom=0,heldRandom2=0;
    uint32_t random2=0x71b48a95;
    double arpCountdown=0,gateCountdown=0;
    uint64_t arpStep=0; bool previousEnabled=false,previousArp=false,arpWaiting=true;
};
struct Candidate { int source=0,channel=0,key=0,note=0; float velocity=0; };
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
    std::array<std::atomic<float>,4> delaySends{},reverbSends{};
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
    std::array<std::atomic<float>,30> modulationFeedback{};
    std::array<float,30> frameFeedback{};
    std::array<std::array<std::atomic<uint64_t>,6>,5> matrix{};
    std::array<std::array<MatrixRoute,6>,5> activeMatrix{};
    std::array<int,5> matrixCount{};
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
    std::array<Comb,8> combs{}; std::array<Allpass,4> allpasses{};
    size_t delayPosition=0,chorusPosition=0; float chorusPhase=0,delaySamples=24000,master=.25f,outputGain=1,outputLimiter=1;
    double sampleRate=48000; uint64_t serial=0,sampleCounter=0; uint32_t random=0x8e7f4a35;
    bool holding=false,externalClock=false,clockPlaying=true;
    int32_t clockID=0;uint64_t clockTicks=0,clockAge=0;
    double lastClock=0,clockInterval=0;
    std::atomic<float> clockBPM{0};
    Impl() {
        for(int i=0;i<4;i++){delaySends[i]=1;reverbSends[i]=1;}
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
        defaults[APFilter2Cutoff]=3200;defaults[APFilterBalance]=.5f;
        defaults[APModAttack]=.01f;defaults[APModDecay]=.35f;defaults[APModRelease]=.35f;
        defaults[APOscModRatio]=1;defaults[APCharacterDrive]=.25f;defaults[APCharacterMix]=1;
        defaults[APCharacterTone]=.5f;defaults[APCharacterBits]=12;defaults[APCharacterRate]=1;
        for(int l=0;l<kLayers;l++) for(int p=0;p<APParameterCount;p++)
            parameters[l][p].store(p==APEnabled ? float(l==0) : defaults[p]);
        globals[AGMaster].store(.25f);globals[AGTempo].store(120);globals[AGDelayMix].store(.12f);
        globals[AGDelayFeedback].store(.3f);globals[AGReverbMix].store(.16f);globals[AGChorusMix].store(.1f);
        globals[AGPhaserRate]=.22f;globals[AGPhaserDepth]=1;globals[AGChorusRate]=.23f;globals[AGChorusDepth]=1;globals[AGReverbSize]=.5f;globals[AGReverbDecay]=1;
        prepare(48000);
    }
    void clearSound() {
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
        for(auto& channel:phaserState)channel.fill(0);
        phaserPhase=0;phaserMix=0;
        phaserFeedback.fill(0);
        delayL.fill(0);delayR.fill(0);chorusL.fill(0);chorusR.fill(0);
        for(auto& c:combs)c.clear();for(auto& a:allpasses)a.clear();
        outputPeak.store(0,std::memory_order_relaxed);voiceCount.store(0,std::memory_order_relaxed);
        previewActiveLayers.store(0);
    }
    void prepare(double rate) {
        sampleRate=std::isfinite(rate)?std::clamp(rate,8000.,192000.):48000;
        // Device configuration may be queued before audio has started. Keep it,
        // but discard notes from a stopped interval and any old panic request.
        Event event;
        eventGeneration.fetch_add(1,std::memory_order_acq_rel);
        for(size_t n=0;n<queueSize&&queue.pop(event);n++)if(event.kind!=Event::MIDI)processEvent(event);
        panicRequested.store(false,std::memory_order_release);
        clearSound(); snapshot();
        for(auto& layer:layers){layer.delaySend=layer.delayTarget;layer.reverbSend=layer.reverbTarget;}
        constexpr float times[8]={.0297f,.0371f,.0411f,.0437f,.0307f,.0383f,.0427f,.0451f};
        for(int i=0;i<8;i++)combs[i].length=std::clamp(int(sampleRate*times[i]),1,16384);
        for(int i=0;i<4;i++)allpasses[i].length=std::clamp(int(sampleRate*(.0047f+.0013f*i)),1,4096);
        delaySamples=float(sampleRate*.5);delayPosition=chorusPosition=0;sampleCounter=0;
    }
    void requestPanic() {
        // Generation tagging also rejects a producer that reserved a queue slot
        // before panic, then published the stale note only after recovery.
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
    float lfoRate(const std::array<float,APParameterCount>& p,int o) const {
        constexpr float beats[]={16,8,4,2,1,.5f,.25f,.125f,.75f,1.f/3};
        int base=APLFO1Sync+o*6;
        return p[base]>.5f?global[AGTempo]/(60.f*beats[int(p[base+1])]):p[o?APLFO2Rate:APLFORate];
    }
    void startVoice(int si,int ch,int key,int pitch,float velocity,int layer,bool arp) {
        auto& settings=layers[layer].p;
        float targetHz=440.f*std::exp2((std::clamp(pitch+int(settings[APTranspose]),0,127)-69)/12.f);
        if(!arp&&settings[APVoiceMode]>.5f)for(auto& v:voices)if(v.active&&!v.arp&&v.source==si&&v.channel==ch&&v.layer==layer&&v.stage!=3){
            v.key=key;v.targetFrequency=targetHz;v.velocity=velocity;v.serial=++serial;
            v.untransposedPitch=pitch;
            if(settings[APGlide]<=0)v.frequency=targetHz;
            if(settings[APVoiceMode]<1.5f){v.age=0;v.lfoPhase={};v.lfoRandom={randomUnit(modulationRandom),randomUnit(modulationRandom)};v.noteRandom=randomUnit(modulationRandom);v.stage=0;v.modStage=0;v.modEnvelope=0;v.motionTime=0;v.motionStarted=false;v.motionFade=0;v.motionRelease=1;}
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
        target->noteRandom=randomUnit(modulationRandom);target->lfoRandom={randomUnit(modulationRandom),randomUnit(modulationRandom)};
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
        for(int bank=0;bank<5;bank++){
            matrixCount[bank]=0;
            int slotIndex=0;
            for(auto& slot:matrix[bank]){
                int routeSlot=slotIndex++;
                uint64_t bits=slot.load(std::memory_order_relaxed);
                if(bits&1){MatrixRoute r;r.slot=routeSlot;r.source=(bits>>1)&7;r.destination=(bits>>4)&31;r.target=(bits>>9)&7;r.cc=(bits>>12)&127;r.amount=float(int((bits>>19)&65535)-32768)/32767.f;activeMatrix[bank][matrixCount[bank]++]=r;}
            }
        }

        transposeRatio=std::exp2(transpose.load(std::memory_order_relaxed)/12.f);
        for(int g=0;g<AGGlobalCount;g++)global[g]=globals[g].load(std::memory_order_relaxed);
        constexpr float roomTimes[8]={.0297f,.0371f,.0411f,.0437f,.0307f,.0383f,.0427f,.0451f};
        for(int i=0;i<8;i++){
            auto& c=combs[i];c.length=std::clamp(int(sampleRate*roomTimes[i]*(.5f+global[AGReverbSize])),1,16384);c.position%=c.length;
            c.feedback=std::min(.98f,std::pow(.001f,float(c.length/sampleRate)/global[AGReverbDecay]));
        }
        for(int l=0;l<kLayers;l++) {
            auto& layer=layers[l];auto& p=layer.p;
            layer.delayTarget=delaySends[l].load(std::memory_order_relaxed);layer.reverbTarget=reverbSends[l].load(std::memory_order_relaxed);
            auto& packet=motionPackets[l];unsigned before=packet.version.load();
            if(!(before&1)){
                MotionEnvelope next;for(int i=0;i<motionSize;i++)next.data[i]=packet.values[i].load();
                if(before==packet.version.load())layer.motion=next;
            }
            float oldTranspose=p[APTranspose];
            for(int i=0;i<APParameterCount;i++)p[i]=parameters[l][i].load(std::memory_order_relaxed);
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
            if(clockPlaying)for(int l=0;l<kLayers;l++)if(layers[l].p[APEnabled]>.5f&&layers[l].p[APArpEnabled]>.5f&&clockTicks%uint64_t(24>>int(layers[l].p[APArpRate]))==0)arpStep(l);
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
                candidates[count++]={si,ch,key,key+12*oct,velocity/127.f};
        }
        if(count==0){layer.arpStep=0;layer.arpCountdown=0;layer.arpWaiting=true;return;}
        std::sort(candidates.begin(),candidates.begin()+count,[](const Candidate& a,const Candidate& b){
            if(a.note!=b.note)return a.note<b.note;if(a.source!=b.source)return a.source<b.source;
            if(a.channel!=b.channel)return a.channel<b.channel;return a.key<b.key;
        });
        int index=0,mode=int(p[APArpMode]);
        if(mode==0)index=int(layer.arpStep%count);
        else if(mode==1)index=count-1-int(layer.arpStep%count);
        else if(mode==2){int period=std::max(1,2*count-2),step=int(layer.arpStep%period);index=step<count?step:period-step;}
        else index=int(nextRandom(random)%uint32_t(count));
        const auto& c=candidates[index];startVoice(c.source,c.channel,c.key,c.note,c.velocity,layerIndex,true);
        ++layer.arpStep;
        double duration=sampleRate*60.0/global[AGTempo]/double(1<<int(p[APArpRate]));
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
        if(recover)clearSound();
        for(size_t n=0;n<queueSize&&queue.pop(event);n++)
            if((event.kind!=Event::MIDI&&event.kind!=Event::Hold&&event.kind!=Event::Clock)||(!recover&&event.generation==generation))processEvent(event);
        // Shared FX follow the latest received performance message, including
        // controllers moved before playing. Layer destinations retain source/channel ownership.
        frameFeedback.fill(0);
        std::array<float,4> effectOffsets{};
        for(int i=0;i<matrixCount[4];i++){
            const auto& r=activeMatrix[4][i];
            if(r.destination>=8&&r.destination<=11){float value=r.amount*performanceValue(r,latestVelocity,latestPressure,latestCC);effectOffsets[r.destination-8]+=value;frameFeedback[24+r.slot]=value;}
        }
        constexpr int effects[]={AGChorusMix,AGPhaserMix,AGReverbMix,AGDelayMix};
        for(int i=0;i<4;i++)global[effects[i]]=std::clamp(global[effects[i]]+effectOffsets[i],0.f,1.f);
        float maximum=0;float smooth=1-std::exp(-1.f/float(sampleRate*.008));
        float masterTarget=global[AGMaster];
        float gainTarget=std::pow(10.f,global[AGOutputGain]/20.f);
        float limiterRelease=1-std::exp(-1.f/float(sampleRate*.1));
        for(uint32_t frame=0;frame<frames;frame++,sampleCounter++) {
            if(externalClock&&++clockAge==uint64_t(sampleRate*.5)){clockBPM=0;lastClock=clockInterval=0;for(int l=0;l<kLayers;l++)releaseLayerArp(l);}
            if(externalClock&&clockBPM>0)global[AGTempo]=clockBPM.load(std::memory_order_relaxed);
            for(int l=0;l<kLayers;l++) {
                auto& layer=layers[l];auto& p=layer.p;
                layer.gain+=smooth*(p[APLevel]*p[APEnabled]*(activeSolo<0||activeSolo==l?1.f:0.f)-layer.gain);
                layer.delaySend+=smooth*(layer.delayTarget-layer.delaySend);layer.reverbSend+=smooth*(layer.reverbTarget-layer.reverbSend);
                layer.cutoff+=smooth*(p[APCutoff]-layer.cutoff);
                for(int o=0;o<2;o++){
                    layer.wtPosition[o]+=smooth*(p[APWT1Position+o*7]-layer.wtPosition[o]);
                    layer.wtAmount[o]+=smooth*(p[APWT1Warp+o*7]-layer.wtAmount[o]);
                }
                layer.lfoPhase+=lfoRate(p,0)/float(sampleRate);
                if(layer.lfoPhase>=1){layer.lfoPhase-=1;layer.heldRandom=randomUnit(random);}
                layer.lfo2Phase+=lfoRate(p,1)/float(sampleRate);if(layer.lfo2Phase>=1){layer.lfo2Phase-=1;layer.heldRandom2=randomUnit(layer.random2);}
                if(p[APEnabled]>.5f&&p[APArpEnabled]>.5f) {
                    if(layer.gateCountdown>0&&--layer.gateCountdown<=0)releaseLayerArp(l);
                    if(!externalClock&&!layer.arpWaiting){if(layer.arpCountdown<=0)arpStep(l);else --layer.arpCountdown;}
                }
            }
            float outL=0,outR=0,sendDL=0,sendDR=0,sendRL=0,sendRR=0;
            for(auto& v:voices)if(v.active) {
                auto& layer=layers[v.layer];const auto& p=layer.p;auto& source=sources[v.source];
                if(v.stage==0){v.envelope+=layer.attack;if(v.envelope>=1){v.envelope=1;v.stage=1;}}
                else if(v.stage==1){v.envelope=p[APSustain]+(v.envelope-p[APSustain])*layer.decay;
                    if(std::abs(v.envelope-p[APSustain])<.0001f)v.stage=2;}
                else if(v.stage==2)v.envelope=p[APSustain];
                else {v.envelope*=layer.release;v.motionRelease*=layer.release;
                    if((layer.motion.routed(0)?v.motionRelease:v.envelope)<.00001f){v.active=false;continue;}}
                const auto& motion=layer.motion;
                if(motion.enabled()){
                    float target=motion.shape(float(v.motionTime));
                    if(!v.motionStarted){v.motionValue=target;v.motionStarted=true;}
                    else v.motionValue+=smooth*(target-v.motionValue);
                    if(v.stage!=3){
                        double duration=motion.data[84]>0?motion.data[84]*60.0/global[AGTempo]:motion.data[2];
                        v.motionTime+=1/(sampleRate*duration);
                        if(motion.data[1]>.5f)v.motionTime-=std::floor(v.motionTime);
                        else v.motionTime=std::min(1.,v.motionTime);
                    }
                }
                v.motionFade=std::min(1.f,v.motionFade+1.f/float(sampleRate*.003));
                if(v.stage==3)v.modEnvelope*=layer.modRelease;
                else if(v.modStage==0){v.modEnvelope=std::min(1.f,v.modEnvelope+layer.modAttack);if(v.modEnvelope>=1)v.modStage=1;}
                else {v.modEnvelope=p[APModSustain]+(v.modEnvelope-p[APModSustain])*layer.modDecay;}
                // Retrigger is polyphonic: a new note never resets another held note.
                float noteLFO[2];float noteCutoff=0,notePitch=0,notePan=0,noteAmp=1;
                for(int o=0;o<2;o++){
                    int base=APLFO1Sync+o*6;
                    bool retrigger=p[base+2]>.5f;
                    float phase=(retrigger?v.lfoPhase[o]:(o?layer.lfo2Phase:layer.lfoPhase))+p[base+3];phase-=std::floor(phase);
                    float held=retrigger?v.lfoRandom[o]:(o?layer.heldRandom2:layer.heldRandom);
                    float elapsed=float(v.age)-p[base+4];
                    float fade=elapsed<0?0:(p[base+5]>0?std::min(1.f,elapsed/p[base+5]):1.f);
                    noteLFO[o]=shapeLFO(phase,int(p[o?APLFO2Shape:APLFOShape]),held)*fade;
                    if(elapsed>=0){v.lfoPhase[o]+=lfoRate(p,o)/float(sampleRate);if(v.lfoPhase[o]>=1){v.lfoPhase[o]-=std::floor(v.lfoPhase[o]);v.lfoRandom[o]=randomUnit(modulationRandom);}}
                    float amount=noteLFO[o]*p[o?APLFO2Depth:APLFODepth];
                    switch(int(p[o?APLFO2Destination:APLFODestination])){case 0:noteCutoff+=amount*3;break;case 1:notePitch+=amount*2;break;case 2:notePan+=amount;break;default:noteAmp+=amount*.5f;}
                }
                v.age+=1/sampleRate;notePitch=std::exp2(notePitch/12.f);noteAmp=std::clamp(noteAmp,0.f,2.f);
                std::array<float,21> mod{};
                constexpr int modDestinations[]={0,16,1,18,19,12,13};
                mod[modDestinations[int(p[APModDestination])]]+=v.modEnvelope*p[APModAmount];
                for(int i=0;i<matrixCount[v.layer];i++){
                    const auto& r=activeMatrix[v.layer][i];
                    float signals[]={noteLFO[0],noteLFO[1],v.envelope,v.modEnvelope,std::clamp((v.key-60)/60.f,-1.f,1.f),v.noteRandom};
                    float signal=signals[r.source];
                    mod[r.destination]+=signal*r.amount;
                    frameFeedback[v.layer*6+r.slot]=signal*r.amount;
                }
                for(int i=0;i<matrixCount[4];i++){
                    const auto& r=activeMatrix[4][i];
                    if((r.destination<8||r.destination>=12)&&(r.target==4||r.target==v.layer)){float value=r.amount*performanceValue(r,v.velocity,source.pressure[v.channel],source.controls[v.channel]);mod[r.destination]+=value;frameFeedback[24+r.slot]=value;}
                }
                // Depth routes add modulation through each LFO's existing destination.
                float extraCutoff=0,extraPitch=0,extraPan=0,extraAmp=0;
                for(int i=0;i<2;i++){
                    float depth=p[i?APLFO2Depth:APLFODepth];
                    float amount=(std::clamp(depth+mod[6+i],0.f,1.f)-depth)*noteLFO[i];
                    switch(int(p[i?APLFO2Destination:APLFODestination])){case 0:extraCutoff+=amount*3;break;case 1:extraPitch+=amount*2;break;case 2:extraPan+=amount;break;default:extraAmp+=amount*.5f;}
                }
                float blend=std::clamp(p[APBlend]+mod[4],0.f,1.f),drive=std::clamp(p[APDrive]+mod[5],0.f,1.f);
                float wheelPitch=1+source.wheel[v.channel]*std::sin(tau*layer.lfo2Phase)*.0145f;
                v.frequency+=layer.glideStep*(v.targetFrequency-v.frequency);
                float motionPitch=motion.routed(2)?motion.value(2,v.motionValue):0;
                float frequency=v.frequency*transposeRatio*std::exp2(source.bend[v.channel]*p[APBendRange]/12.f)*notePitch*wheelPitch*std::exp2((std::clamp(mod[1],-2.f,2.f)*12+extraPitch+motionPitch)/12.f);
                if((sampleCounter&15)==0||v.envelope<=layer.attack*1.1f) {
                    float cutoff=(motion.routed(1)?motion.value(1,v.motionValue):layer.cutoff)*std::exp2(noteCutoff+p[APFilterEnvelope]*v.envelope*4+std::clamp(mod[0],-2.f,2.f)*4+extraCutoff);
                    cutoff=std::clamp(cutoff,20.f,std::min(20000.f,float(sampleRate)*.42f));
                    v.filterG=std::tan(pi*cutoff/float(sampleRate));v.filterK=2-1.85f*p[APResonance];
                    if(p[APFilter2Enabled]>.5f){
                        float cutoff2=std::clamp(p[APFilter2Cutoff]*std::exp2(std::clamp(mod[16],-2.f,2.f)*4),30.f,std::min(18000.f,float(sampleRate)*.42f));
                        v.filter2G=std::tan(pi*cutoff2/float(sampleRate));v.filter2K=2-1.85f*std::clamp(p[APFilter2Resonance]+mod[17],0.f,.9f);
                    }
                }
                float g=v.filterG,k=v.filterK,a1=1/(1+g*(g+k)),a2=g*a1,a3=g*a2;
                int unison=std::clamp(int(p[APUnison]),1,8);
                float width=std::clamp(p[APPulseWidth]+noteLFO[0]*p[APPWMDepth]*.45f,.05f,.95f);
                v.lastL=v.lastR=0;
                float positions[2],amounts[2];
                for(int o=0;o<2;o++){
                    positions[o]=std::clamp((motion.routed(4+o)?motion.value(4+o,v.motionValue):layer.wtPosition[o])+mod[12+o],0.f,1.f);
                    amounts[o]=std::clamp((motion.routed(6+o)?motion.value(6+o,v.motionValue):layer.wtAmount[o])+mod[14+o],0.f,1.f);
                    if(frame+1==frames){previewPosition[v.layer*2+o].store(positions[o]);previewAmount[v.layer*2+o].store(amounts[o]);}
                }
                auto wave=[&](int o,float phase,float step){
                    return p[APWT1Enabled+o*7]>.5f&&layer.banks[o]?layer.banks[o]->shapedSample(phase,step,positions[o],int(p[APWT1WarpMode+o*7]),amounts[o],p[APWT1Formant+o*2],p[APWT1Tone+o*2]):oscillator(phase,step,int(p[o?APWave2:APWave1]),width);
                };
                for(int laneIndex=0;laneIndex<unison;laneIndex++) {
                    auto& lane=v.lanes[laneIndex];
                    float position=unison==1?0.f:2.f*laneIndex/(unison-1)-1;
                    float step=std::clamp(frequency*layer.unisonRatios[laneIndex]/float(sampleRate),.000001f,.45f);
                    int oscMode=int(p[APOscModMode]);
                    float oscAmount=std::clamp(p[APOscModAmount]+mod[18],0.f,1.f);
                    float step2=std::clamp(step*layer.detune*layer.syncRatio*(oscMode?p[APOscModRatio]:1.f),.000001f,.45f);
                    float second=wave(1,lane.phase2,step2)+lane.syncCorrection;
                    // Bound modulation at high notes; classic and wavetable carriers share the same path.
                    float depth=oscAmount*std::clamp((.45f-step)/.25f,0.f,1.f);
                    float phase=lane.phase1+(oscMode==1?second*depth*.5f:0.f);phase-=std::floor(phase);
                    float first=wave(0,phase,std::min(.45f,step+(oscMode==1?step2*depth:0.f)));
                    if(oscMode==3)first=first*(1-depth)+first*second*depth;
                    float input=first*(1-blend)+second*blend;
                    input+=std::sin(tau*lane.subphase)*p[APSub]*.6f;
                    if(p[APNoise]>.0001f)input+=randomUnit(random)*p[APNoise]*.3f;
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
                    if(drive>.001f)input=std::tanh(input*(1+8*drive));
                    auto filter=[](float in,float g,float k,int type,float& ic1,float& ic2){
                        float a1=1/(1+g*(g+k)),a2=g*a1,a3=g*a2;
                        float x=in-ic2,band=a1*ic1+a2*x,low=ic2+a2*ic1+a3*x;
                        ic1=2*band-ic1;ic2=2*low-ic2;
                        return type==1?in-k*band-low:type==2?band:type==3?in-k*band:low;
                    };
                    auto f1=[&](float x){float y=filter(x,g,k,int(p[APFilterType]),lane.ic1,lane.ic2);if(p[APFilter1Slope]>.5f)y=filter(y,g,k,int(p[APFilterType]),lane.f1b1,lane.f1b2);else lane.f1b1=lane.f1b2=0;return y;};
                    auto f2=[&](float x){float y=filter(x,v.filter2G,v.filter2K,int(p[APFilter2Type]),lane.f2ic1,lane.f2ic2);if(p[APFilter2Slope]>.5f)y=filter(y,v.filter2G,v.filter2K,int(p[APFilter2Type]),lane.f2b1,lane.f2b2);else lane.f2b1=lane.f2b2=0;return y;};
                    float filtered;
                    if(p[APFilter2Enabled]<.5f){filtered=f1(input);lane.f2ic1=lane.f2ic2=lane.f2b1=lane.f2b2=0;}
                    else if(p[APFilterRouting]<.5f)filtered=f2(f1(input));
                    else if(p[APFilterRouting]<1.5f)filtered=f1(f2(input));
                    else {float balance=std::clamp(p[APFilterBalance]+mod[20],0.f,1.f);filtered=f1(input)*(1-balance)+f2(input)*balance;}
                    int character=int(p[APCharacterMode]);
                    if(character){
                        float amount=std::clamp(p[APCharacterDrive]+mod[19],0.f,1.f),gain=1+amount*12;
                        auto shape=[&](float x){
                            if(character==1)return std::tanh(x*gain)/std::tanh(gain);
                            if(character==2)return std::clamp(x*gain,-1.f,1.f);
                            return 2.f/pi*std::asin(std::sin(x*gain*pi*.5f));
                        };
                        float wet=filtered;
                        if(character==4){lane.holdPhase+=p[APCharacterRate];if(lane.holdPhase>=1){lane.holdPhase-=std::floor(lane.holdPhase);float steps=layer.characterSteps;lane.held=std::round(std::clamp(filtered*gain,-1.f,1.f)*steps)/steps;}wet=lane.held;}
                        else {wet=.5f*(shape((lane.previousCharacter+filtered)*.5f)+shape(filtered));lane.previousCharacter=filtered;}
                        lane.tone+=layer.characterTone*(wet-lane.tone);
                        filtered+=(lane.tone-filtered)*p[APCharacterMix];
                    }
                    float amplitude=motion.routed(0)?motion.value(0,v.motionValue)*v.motionRelease*v.motionFade:v.envelope;
                    float value=filtered*amplitude*v.velocity*source.expression[v.channel]*layer.gain*std::clamp(noteAmp+mod[3]+extraAmp,0.f,2.f)*.16f/unison;
                    float pan=std::clamp((motion.routed(3)?motion.value(3,v.motionValue):p[APPan])+notePan+mod[2]+extraPan+position*p[APStereoSpread],-1.f,1.f);
                    if(!std::isfinite(value)||!std::isfinite(lane.ic1)||!std::isfinite(lane.ic2)||!std::isfinite(lane.f2ic1)||!std::isfinite(lane.f2ic2)){lane=OscillatorLane{};continue;}
                    v.lastL+=value*std::sqrt(.5f*(1-pan));v.lastR+=value*std::sqrt(.5f*(1+pan));
                }
                outL+=v.lastL;outR+=v.lastR;
                sendDL+=v.lastL*layer.delaySend;sendDR+=v.lastR*layer.delaySend;
                sendRL+=v.lastL*layer.reverbSend;sendRR+=v.lastR*layer.reverbSend;
            }
            float tailLength=float(std::max(1,int(sampleRate*.005)));
            for(auto& t:tails)if(t.remaining>0){float fade=t.remaining/tailLength;if(activeSolo<0||activeSolo==t.layer){outL+=t.left*fade;outR+=t.right*fade;sendDL+=t.left*fade*layers[t.layer].delaySend;sendDR+=t.right*fade*layers[t.layer].delaySend;sendRL+=t.left*fade*layers[t.layer].reverbSend;sendRR+=t.right*fade*layers[t.layer].reverbSend;}--t.remaining;}
            // The chorus, delay and Schroeder room are shared stereo sends.
            chorusL[chorusPosition]=outL;chorusR[chorusPosition]=outR;
            float chorusDelayL=float(sampleRate)*(.009f+.0028f*global[AGChorusDepth]*std::sin(tau*chorusPhase));
            float chorusDelayR=float(sampleRate)*(.011f+.0028f*global[AGChorusDepth]*std::sin(tau*(chorusPhase+.25f)));
            outL+=delayed(chorusL,chorusPosition,chorusDelayL)*global[AGChorusMix]*.5f;
            outR+=delayed(chorusR,chorusPosition,chorusDelayR)*global[AGChorusMix]*.5f;
            chorusPosition=(chorusPosition+1)%chorusSize;chorusPhase+=global[AGChorusRate]/float(sampleRate);if(chorusPhase>=1)chorusPhase-=1;
            // Four swept all-pass stages per channel form moving cancellation
            // notches when blended with the dry signal. Coefficients stay stable.
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
            outL+=phaserMix*.5f*(phased[0]-outL);
            outR+=phaserMix*.5f*(phased[1]-outR);
            phaserPhase+=global[AGPhaserRate]/float(sampleRate);if(phaserPhase>=1)phaserPhase-=1;
            constexpr float divisions[8]={1,.5f,.25f,2,.75f,1.5f,1.f/3,2.f/3};
            delaySamples+=smooth*.05f*(std::min(float(delaySize-2),float(sampleRate*60/global[AGTempo])*divisions[int(global[AGDelayTiming])])-delaySamples);
            float dl=delayed(delayL,delayPosition,delaySamples),dr=delayed(delayR,delayPosition,delaySamples);
            delayL[delayPosition]=sendDL+dr*global[AGDelayFeedback];delayR[delayPosition]=sendDR+dl*global[AGDelayFeedback];
            delayPosition=(delayPosition+1)%delaySize;
            float reverbInput=(sendRL+sendRR)*.16f,rl=0,rr=0;
            for(int i=0;i<4;i++){rl+=combs[i].process(reverbInput);rr+=combs[i+4].process(reverbInput);}
            rl=allpasses[1].process(allpasses[0].process(rl));rr=allpasses[3].process(allpasses[2].process(rr));
            outL+=dl*global[AGDelayMix]+rl*global[AGReverbMix]*.25f;
            outR+=dr*global[AGDelayMix]+rr*global[AGReverbMix]*.25f;
            master+=smooth*(masterTarget-master);
            float finalL=std::tanh(outL*master),finalR=std::tanh(outR*master);
            outputGain+=smooth*(gainTarget-outputGain);
            if(outputGain>1.00001f){
                finalL*=outputGain;finalR*=outputGain;
                float target=std::min(1.f,.98f/std::max(.00001f,std::max(std::abs(finalL),std::abs(finalR))));
                outputLimiter=target<outputLimiter?target:outputLimiter+limiterRelease*(target-outputLimiter);
                finalL*=outputLimiter;finalR*=outputLimiter;
            }else outputLimiter=1;
            left[frame]=std::isfinite(finalL)?finalL:0;right[frame]=std::isfinite(finalR)?finalR:0;
            // A mono sum can cancel wide/phase-opposed stereo sounds and falsely look quiet.
            if((sampleCounter&3)==0)scopeSamples[(scopePosition++)%scopeSamples.size()].store(left[frame],std::memory_order_relaxed);
            maximum=std::max(maximum,std::max(std::abs(left[frame]),std::abs(right[frame])));
        }
        scopePublished.store(scopePosition,std::memory_order_release);
        for(int i=0;i<30;i++)modulationFeedback[i].store(frameFeedback[i],std::memory_order_relaxed);
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
    if(layer>=0&&layer<kLayers&&parameter>=0&&parameter<APParameterCount)
        impl->parameters[layer][parameter].store(parameterValue(parameter,value),std::memory_order_relaxed);
}
float SynthEngine::getParameter(int layer,int parameter)const {
    return layer>=0&&layer<kLayers&&parameter>=0&&parameter<APParameterCount?
        impl->parameters[layer][parameter].load(std::memory_order_relaxed):0;
}
void SynthEngine::setTranspose(int semitones) { impl->transpose.store(std::clamp(semitones,-24,24),std::memory_order_relaxed); }
void SynthEngine::setGlobal(int parameter,float value) {
    if(parameter>=0&&parameter<AGGlobalCount)impl->globals[parameter].store(globalValue(parameter,value),std::memory_order_relaxed);
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
    if(bank<0||bank>4||slot<0||slot>=6)return;
    if(source<0||source>5||destination<0||destination>20||(bank!=4&&destination>5&&destination<12)||target<0||target>4||cc<0||cc>127||!std::isfinite(amount))enabled=false;
    unsigned a=unsigned(int(std::round(std::clamp(std::isfinite(amount)?amount:0.f,-1.f,1.f)*32767))+32768);
    uint64_t bits=enabled?(1ull|(uint64_t(source)<<1)|(uint64_t(destination)<<4)|(uint64_t(target)<<9)|(uint64_t(cc)<<12)|(uint64_t(a)<<19)):0;
    impl->matrix[bank][slot].store(bits,std::memory_order_relaxed);
}
int aurora::SynthEngine::copyModulation(float* values,int capacity) const {
    if(!values||capacity<=0)return 0;
    int count=std::min(capacity,30);
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
void aurora::SynthEngine::setLayerSends(int layer,float delay,float reverb){if(layer<0||layer>=4)return;impl->delaySends[layer].store(bounded(delay,0,1));impl->reverbSends[layer].store(bounded(reverb,0,1));}
void aurora::SynthEngine::soloLayer(int layer){impl->solo.store(layer>=0&&layer<4?layer:-1);}
