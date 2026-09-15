#include "SynthEngine.hpp"
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
constexpr size_t queueSize=2048, delaySize=384004, chorusSize=8192;
float bounded(float x,float lo,float hi,float fallback=0) {
    return std::isfinite(x) ? std::clamp(x,lo,hi) : fallback;
}
float parameterValue(int p,float v) {
    switch(p) {
        case APEnabled: case APArpEnabled: return bounded(v,0,1)>=.5f?1:0;
        case APWave1: case APWave2: case APLFOShape: case APLFO2Shape: return std::round(bounded(v,0,4));
        case APDetune: return bounded(v,-100,100);
        case APCutoff: return bounded(v,20,20000,1500);
        case APAttack: case APDecay: case APRelease: return bounded(v,.001f,30,.1f);
        case APPan: case APFilterEnvelope: return bounded(v,-1,1);
        case APTranspose: return std::round(bounded(v,-48,48));
        case APLFORate: case APLFO2Rate: return bounded(v,.01f,30,1);
        case APLFODestination: case APLFO2Destination: case APArpRate: case APArpMode:
            return std::round(bounded(v,0,3));
        case APFilterType: return std::round(bounded(v,0,2));
        case APArpOctaves: return std::round(bounded(v,1,4,1));
        case APArpGate: return bounded(v,.05f,.95f,.65f);
        case APKeyLow: case APKeyHigh: return std::round(bounded(v,0,127));
        default: return bounded(v,0,1);
    }
}
float globalValue(int p,float v) {
    if(p==AGTempo) return bounded(v,30,240,120);
    if(p==AGDelayFeedback) return bounded(v,0,.85f,.3f);
    return bounded(v,0,1);
}
float polyBLEP(float phase,float step) {
    if(phase<step) { float t=phase/step; return 2*t-t*t-1; }
    if(phase>1-step) { float t=(phase-1)/step; return t*t+2*t+1; }
    return 0;
}
float oscillator(float phase,float step,int wave) {
    switch(wave) {
        case 0: return std::sin(tau*phase);
        case 1: return 1-4*std::abs(phase-.5f);
        case 2: return 2*phase-1-polyBLEP(phase,step);
        case 3: { float v=phase<.5f?1.f:-1.f;
            v+=polyBLEP(phase,step); v-=polyBLEP(std::fmod(phase+.5f,1.f),step); return v; }
        default: {
            // Original, compact harmonic voice; high harmonics are omitted
            // above Nyquist. Table scanning/import is deliberately later scope.
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
struct Event { enum Kind:uint8_t { MIDI, Route, Disconnect } kind=MIDI;
    int32_t source=0; int a=0,b=0,c=0;uint64_t generation=0; };
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
struct Voice {
    bool active=false, arp=false; int source=0,channel=0,key=0,layer=0,stage=0;
    uint64_t serial=0; float phase1=0,phase2=.17f,subphase=0,frequency=440;
    float envelope=0,velocity=1,ic1=0,ic2=0,filterG=.2f,filterK=1,lastL=0,lastR=0;
};
struct Tail { float left=0,right=0;int remaining=0; };
struct MatrixRoute {int source=0,destination=0,target=4,cc=1;float amount=0;};
struct Source {
    bool used=false,connected=true; int32_t id=0; int mask=1,channel=0;
    std::array<std::array<uint8_t,128>,16> velocity{},physical{};
    std::array<bool,16> sustain{};
    std::array<float,16> bend{},wheel{},expression{};
    std::array<std::array<float,128>,16> controls{};
    std::array<float,16> pressure{};
    Source() { bend.fill(1); expression.fill(1); }
};
struct Layer {
    std::array<float,APParameterCount> p{};
    float attack=.01f,decay=.99f,release=.99f,detune=1;
    float gain=0,cutoff=1500,lfoPhase=0,lfo2Phase=0,heldRandom=0,heldRandom2=0;
    uint32_t random2=0x71b48a95;
    double arpCountdown=0,gateCountdown=0;
    uint64_t arpStep=0; bool previousEnabled=false,previousArp=false,arpWaiting=true;
};
struct Candidate { int source=0,channel=0,key=0,note=0; float velocity=0; };
struct Comb {
    std::array<float,16384> data{}; int position=0,length=1500; float damp=0;
    float process(float input) {
        float delayed=data[position]; damp+=.35f*(delayed-damp);
        data[position]=input+.77f*damp; if(++position>=length)position=0; return delayed;
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
    std::array<std::array<std::atomic<uint64_t>,6>,5> matrix{};
    std::array<std::array<MatrixRoute,6>,5> activeMatrix{};
    std::array<int,5> matrixCount{};
    std::array<float,128> latestCC{};
    float latestVelocity=0,latestPressure=0;
    static float performanceValue(const MatrixRoute& r,float velocity,float pressure,const std::array<float,128>& cc) {
        switch(r.source){case 0:return cc[1];case 1:return velocity;case 2:return pressure;case 3:return cc[11];case 4:return cc[64]>=.5f?1.f:0.f;default:return cc[r.cc];}
    }

    std::array<std::atomic<float>,512> scopeSamples{};
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
    float phaserPhase=0,phaserMix=0;
    std::array<Comb,8> combs{}; std::array<Allpass,4> allpasses{};
    size_t delayPosition=0,chorusPosition=0; float chorusPhase=0,delaySamples=24000,master=.25f;
    double sampleRate=48000; uint64_t serial=0,sampleCounter=0; uint32_t random=0x8e7f4a35;
    Impl() {
        std::array<float,APParameterCount> defaults{};
        defaults[APWave1]=2; defaults[APWave2]=1; defaults[APBlend]=.25f; defaults[APDetune]=7;
        defaults[APSub]=.12f; defaults[APCutoff]=3200; defaults[APResonance]=.15f;
        defaults[APAttack]=.012f; defaults[APDecay]=.35f; defaults[APSustain]=.7f;
        defaults[APRelease]=.35f; defaults[APLevel]=.7f; defaults[APLFORate]=.7f;
        defaults[APFilterEnvelope]=.2f; defaults[APArpRate]=1; defaults[APArpOctaves]=1;
        defaults[APArpGate]=.65f; defaults[APKeyHigh]=127; defaults[APLFO2Rate]=4;
        defaults[APLFO2Destination]=1;
        for(int l=0;l<kLayers;l++) for(int p=0;p<APParameterCount;p++)
            parameters[l][p].store(p==APEnabled ? float(l==0) : defaults[p]);
        globals[AGMaster].store(.25f);globals[AGTempo].store(120);globals[AGDelayMix].store(.12f);
        globals[AGDelayFeedback].store(.3f);globals[AGReverbMix].store(.16f);globals[AGChorusMix].store(.1f);
        prepare(48000);
    }
    void clearSound() {
        latestCC.fill(0);latestVelocity=latestPressure=0;
        for(auto& s:sources){for(auto& cc:s.controls)cc.fill(0);s.pressure.fill(0);}
        for(auto& sample:scopeSamples)sample.store(0,std::memory_order_relaxed);
        for(auto& v:voices)v=Voice{};for(auto& t:tails)t=Tail{};
        for(auto& s:sources) {
            for(auto& a:s.velocity)a.fill(0);for(auto& a:s.physical)a.fill(0);
            s.sustain.fill(false);s.bend.fill(1);s.wheel.fill(0);s.expression.fill(1);
        }
        for(auto& l:layers){l.arpCountdown=0;l.gateCountdown=0;l.arpStep=0;l.arpWaiting=true;}
        for(auto& channel:phaserState)channel.fill(0);
        phaserPhase=0;phaserMix=0;
        delayL.fill(0);delayR.fill(0);chorusL.fill(0);chorusR.fill(0);
        for(auto& c:combs)c.clear();for(auto& a:allpasses)a.clear();
        outputPeak.store(0,std::memory_order_relaxed);voiceCount.store(0,std::memory_order_relaxed);
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
        if(voice.active)tails[nextTail++%tails.size()]={voice.lastL,voice.lastR,std::max(1,int(sampleRate*.005))};
    }
    void releaseSource(int si,int channel=-1,int key=-1,bool force=false) {
        for(auto& v:voices)if(v.active&&v.source==si&&(channel<0||v.channel==channel)&&(key<0||v.key==key)) {
            if(force){fadeStolen(v);v.active=false;}else v.stage=3;
        }
    }
    void startVoice(int si,int ch,int key,int pitch,float velocity,int layer,bool arp) {
        // Repeated note-ons from the same physical key retrigger without losing
        // the ownership of equal pitches on a different source or channel.
        if(!arp)for(auto& v:voices)if(v.active&&!v.arp&&v.source==si&&v.channel==ch&&v.key==key&&v.layer==layer)v.stage=3;
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
        pitch=std::clamp(pitch+int(layers[layer].p[APTranspose]),0,127);
        target->frequency=440.f*std::exp2((pitch-69)/12.f);
    }
    void releaseLayer(int layer) { for(auto& v:voices)if(v.active&&v.layer==layer)v.stage=3; }
    void restartHeld(int layer) {
        for(int si=0;si<kSources;si++)if(sources[si].used)for(int ch=0;ch<16;ch++)for(int key=0;key<128;key++)
            if(sources[si].velocity[ch][key]&&routes(si,ch,key,layer))
                startVoice(si,ch,key,key,sources[si].velocity[ch][key]/127.f,layer,false);
    }
    void snapshot() {
        for(int bank=0;bank<5;bank++){
            matrixCount[bank]=0;
            for(auto& slot:matrix[bank]){
                uint64_t bits=slot.load(std::memory_order_relaxed);
                if(bits&1){MatrixRoute r;r.source=(bits>>1)&7;r.destination=(bits>>4)&15;r.target=(bits>>8)&7;r.cc=(bits>>11)&127;r.amount=float(int((bits>>18)&65535)-32768)/32767.f;activeMatrix[bank][matrixCount[bank]++]=r;}
            }
        }

        transposeRatio=std::exp2(transpose.load(std::memory_order_relaxed)/12.f);
        for(int g=0;g<AGGlobalCount;g++)global[g]=globals[g].load(std::memory_order_relaxed);
        for(int l=0;l<kLayers;l++) {
            auto& layer=layers[l];auto& p=layer.p;
            for(int i=0;i<APParameterCount;i++)p[i]=parameters[l][i].load(std::memory_order_relaxed);
            layer.attack=1.f/float(sampleRate*p[APAttack]);
            layer.decay=std::exp(-6.907755f/float(sampleRate*p[APDecay]));
            layer.release=std::exp(-9.21034f/float(sampleRate*p[APRelease]));
            layer.detune=std::exp2(p[APDetune]/1200.f);
            bool enabled=p[APEnabled]>.5f,arp=p[APArpEnabled]>.5f;
            if(layer.previousEnabled!=enabled||layer.previousArp!=arp) {
                releaseLayer(l);layer.arpCountdown=0;layer.gateCountdown=0;layer.arpStep=0;layer.arpWaiting=false;
                if(enabled&&!arp)restartHeld(l);
            }
            layer.previousEnabled=enabled;layer.previousArp=arp;
        }
    }
    void processEvent(const Event& e) {
        int si=sourceIndex(e.source,e.kind!=Event::Disconnect,e.kind==Event::Route);if(si<0)return;
        auto& s=sources[si];
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
            if(performanceInput)latestVelocity=value/127.f;
            s.velocity[ch][key]=uint8_t(value);s.physical[ch][key]=1;
            for(int l=0;l<kLayers;l++)if(routes(si,ch,key,l)) {
                if(layers[l].p[APArpEnabled]<.5f)startVoice(si,ch,key,key,value/127.f,l,false);
                else if(layers[l].arpWaiting){layers[l].arpWaiting=false;layers[l].arpCountdown=0;}
            }
        } else if(type==0x80||(type==0x90&&value==0)) {
            s.physical[ch][key]=0;
            if(!s.sustain[ch]){s.velocity[ch][key]=0;releaseSource(si,ch,key);}
        } else if(type==0xe0) {
            int bend=key|(value<<7);s.bend[ch]=std::exp2(((bend-8192)/8192.f)*2.f/12.f);
        } else if(type==0xd0) {s.pressure[ch]=key/127.f;if(performanceInput)latestPressure=key/127.f;
        } else if(type==0xb0) {
            s.controls[ch][key]=value/127.f;if(performanceInput)latestCC[key]=value/127.f;
            if(key==1)s.wheel[ch]=value/127.f;
            else if(key==11)s.expression[ch]=value/127.f;
            else if(key==64) {
                bool on=value>=64;s.sustain[ch]=on;
                if(!on)for(int n=0;n<128;n++)if(!s.physical[ch][n]){s.velocity[ch][n]=0;releaseSource(si,ch,n);}
            } else if(key==120||key==123) {
                s.velocity[ch].fill(0);s.physical[ch].fill(0);s.sustain[ch]=false;releaseSource(si,ch,-1,key==120);
            } else if(key==121) {
                s.controls[ch].fill(0);s.pressure[ch]=0;if(performanceInput){latestCC.fill(0);latestPressure=0;}
                s.bend[ch]=1;s.wheel[ch]=0;s.expression[ch]=1;s.sustain[ch]=false;
                for(int n=0;n<128;n++)if(!s.physical[ch][n]){s.velocity[ch][n]=0;releaseSource(si,ch,n);}
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
        // MIDI timestamps are currently quantized to the start of this render
        // call. Parameter atomics form a control snapshot at the same boundary.
        snapshot();Event event;
        bool recover=panicRequested.exchange(false,std::memory_order_acq_rel);
        auto generation=eventGeneration.load(std::memory_order_acquire);
        if(recover)clearSound();
        for(size_t n=0;n<queueSize&&queue.pop(event);n++)
            if(event.kind!=Event::MIDI||(!recover&&event.generation==generation))processEvent(event);
        // Shared FX follow the latest received performance message, including
        // controllers moved before playing. Layer destinations retain source/channel ownership.
        std::array<float,4> effectOffsets{};
        for(int i=0;i<matrixCount[4];i++){
            const auto& r=activeMatrix[4][i];
            if(r.destination>=8)effectOffsets[r.destination-8]+=r.amount*performanceValue(r,latestVelocity,latestPressure,latestCC);
        }
        constexpr int effects[]={AGChorusMix,AGPhaserMix,AGReverbMix,AGDelayMix};
        for(int i=0;i<4;i++)global[effects[i]]=std::clamp(global[effects[i]]+effectOffsets[i],0.f,1.f);
        float maximum=0;float smooth=1-std::exp(-1.f/float(sampleRate*.008));
        float masterTarget=global[AGMaster];
        for(uint32_t frame=0;frame<frames;frame++,sampleCounter++) {
            std::array<float,kLayers> cutoffMod{},pitchMod{},panMod{},ampMod{},rawLFO1{},rawLFO2{};
            for(int l=0;l<kLayers;l++) {
                auto& layer=layers[l];auto& p=layer.p;
                layer.gain+=smooth*(p[APLevel]*p[APEnabled]-layer.gain);
                layer.cutoff+=smooth*(p[APCutoff]-layer.cutoff);
                rawLFO1[l]=shapeLFO(layer.lfoPhase,int(p[APLFOShape]),layer.heldRandom);rawLFO2[l]=shapeLFO(layer.lfo2Phase,int(p[APLFO2Shape]),layer.heldRandom2);
                float v1=rawLFO1[l]*p[APLFODepth],v2=rawLFO2[l]*p[APLFO2Depth];
                float values[2]={v1,v2};int dests[2]={int(p[APLFODestination]),int(p[APLFO2Destination])};
                for(int i=0;i<2;i++)switch(dests[i]) {
                    case 0:cutoffMod[l]+=values[i]*3;break;
                    case 1:pitchMod[l]+=values[i]*2;break;
                    case 2:panMod[l]+=values[i];break;
                    default:ampMod[l]+=values[i]*.5f;break;
                }
                pitchMod[l]=std::exp2(pitchMod[l]/12.f);ampMod[l]=std::clamp(1+ampMod[l],0.f,2.f);
                layer.lfoPhase+=p[APLFORate]/float(sampleRate);
                if(layer.lfoPhase>=1){layer.lfoPhase-=1;layer.heldRandom=randomUnit(random);}
                layer.lfo2Phase+=p[APLFO2Rate]/float(sampleRate);if(layer.lfo2Phase>=1){layer.lfo2Phase-=1;layer.heldRandom2=randomUnit(layer.random2);}
                if(p[APEnabled]>.5f&&p[APArpEnabled]>.5f) {
                    if(layer.gateCountdown>0&&--layer.gateCountdown<=0)releaseLayerArp(l);
                    if(!layer.arpWaiting){if(layer.arpCountdown<=0)arpStep(l);else --layer.arpCountdown;}
                }
            }
            float outL=0,outR=0;
            for(auto& v:voices)if(v.active) {
                auto& layer=layers[v.layer];const auto& p=layer.p;auto& source=sources[v.source];
                if(v.stage==0){v.envelope+=layer.attack;if(v.envelope>=1){v.envelope=1;v.stage=1;}}
                else if(v.stage==1){v.envelope=p[APSustain]+(v.envelope-p[APSustain])*layer.decay;
                    if(std::abs(v.envelope-p[APSustain])<.0001f)v.stage=2;}
                else if(v.stage==2)v.envelope=p[APSustain];
                else {v.envelope*=layer.release;if(v.envelope<.00001f){v.active=false;continue;}}
                std::array<float,8> mod{};
                for(int i=0;i<matrixCount[v.layer];i++){
                    const auto& r=activeMatrix[v.layer][i];
                    float signal=r.source==0?rawLFO1[v.layer]:(r.source==1?rawLFO2[v.layer]:v.envelope);
                    mod[r.destination]+=signal*r.amount;
                }
                for(int i=0;i<matrixCount[4];i++){
                    const auto& r=activeMatrix[4][i];
                    if(r.destination<8&&(r.target==4||r.target==v.layer))mod[r.destination]+=r.amount*performanceValue(r,v.velocity,source.pressure[v.channel],source.controls[v.channel]);
                }
                // Depth routes add modulation through each LFO's existing destination.
                float extraCutoff=0,extraPitch=0,extraPan=0,extraAmp=0;
                for(int i=0;i<2;i++){
                    float depth=p[i?APLFO2Depth:APLFODepth];
                    float amount=(std::clamp(depth+mod[6+i],0.f,1.f)-depth)*(i?rawLFO2[v.layer]:rawLFO1[v.layer]);
                    switch(int(p[i?APLFO2Destination:APLFODestination])){case 0:extraCutoff+=amount*3;break;case 1:extraPitch+=amount*2;break;case 2:extraPan+=amount;break;default:extraAmp+=amount*.5f;}
                }
                float blend=std::clamp(p[APBlend]+mod[4],0.f,1.f),drive=std::clamp(p[APDrive]+mod[5],0.f,1.f);
                float wheelPitch=1+source.wheel[v.channel]*std::sin(tau*layer.lfo2Phase)*.0145f;
                float frequency=v.frequency*transposeRatio*source.bend[v.channel]*pitchMod[v.layer]*wheelPitch*std::exp2((std::clamp(mod[1],-2.f,2.f)*12+extraPitch)/12.f);
                float step=std::clamp(frequency/float(sampleRate),.000001f,.45f);
                float step2=std::clamp(step*layer.detune,.000001f,.45f);
                float input=oscillator(v.phase1,step,int(p[APWave1]))*(1-blend)
                    +oscillator(v.phase2,step2,int(p[APWave2]))*blend;
                input+=std::sin(tau*v.subphase)*p[APSub]*.6f;
                if(p[APNoise]>.0001f)input+=randomUnit(random)*p[APNoise]*.3f;
                v.phase1+=step;if(v.phase1>=1)v.phase1-=1;
                v.phase2+=step2;if(v.phase2>=1)v.phase2-=1;
                v.subphase+=step*.5f;if(v.subphase>=1)v.subphase-=1;
                if((sampleCounter&15)==0||v.envelope<=layer.attack*1.1f) {
                    float cutoff=layer.cutoff*std::exp2(cutoffMod[v.layer]+p[APFilterEnvelope]*v.envelope*4+std::clamp(mod[0],-2.f,2.f)*4+extraCutoff);
                    cutoff=std::clamp(cutoff,20.f,std::min(20000.f,float(sampleRate)*.42f));
                    v.filterG=std::tan(pi*cutoff/float(sampleRate));v.filterK=2-1.85f*p[APResonance];
                }
                if(drive>.001f)input=std::tanh(input*(1+8*drive));
                float g=v.filterG,k=v.filterK,a1=1/(1+g*(g+k)),a2=g*a1,a3=g*a2;
                float x=input-v.ic2,band=a1*v.ic1+a2*x,low=v.ic2+a2*v.ic1+a3*x;
                v.ic1=2*band-v.ic1;v.ic2=2*low-v.ic2;
                float filtered=int(p[APFilterType])==1?input-k*band-low:(int(p[APFilterType])==2?band:low);
                float value=filtered*v.envelope*v.velocity*source.expression[v.channel]*layer.gain*std::clamp(ampMod[v.layer]+mod[3]+extraAmp,0.f,2.f)*.16f;
                float pan=std::clamp(p[APPan]+panMod[v.layer]+mod[2]+extraPan,-1.f,1.f);
                if(!std::isfinite(value)||!std::isfinite(v.ic1)||!std::isfinite(v.ic2)){v.active=false;continue;}
                v.lastL=value*std::sqrt(.5f*(1-pan));v.lastR=value*std::sqrt(.5f*(1+pan));
                outL+=v.lastL;outR+=v.lastR;
            }
            float tailLength=float(std::max(1,int(sampleRate*.005)));
            for(auto& t:tails)if(t.remaining>0){float fade=t.remaining/tailLength;outL+=t.left*fade;outR+=t.right*fade;--t.remaining;}
            // The chorus, delay and Schroeder room are shared stereo sends.
            chorusL[chorusPosition]=outL;chorusR[chorusPosition]=outR;
            float chorusDelayL=float(sampleRate)*(.009f+.0028f*std::sin(tau*chorusPhase));
            float chorusDelayR=float(sampleRate)*(.011f+.0028f*std::sin(tau*(chorusPhase+.25f)));
            outL+=delayed(chorusL,chorusPosition,chorusDelayL)*global[AGChorusMix]*.5f;
            outR+=delayed(chorusR,chorusPosition,chorusDelayR)*global[AGChorusMix]*.5f;
            chorusPosition=(chorusPosition+1)%chorusSize;chorusPhase+=.23f/float(sampleRate);if(chorusPhase>=1)chorusPhase-=1;
            // Four swept all-pass stages per channel form moving cancellation
            // notches when blended with the dry signal. Coefficients stay stable.
            phaserMix+=smooth*(global[AGPhaserMix]-phaserMix);
            if((sampleCounter&15)==0) {
                for(int channel=0;channel<2;channel++) {
                    float sweep=.5f+.5f*std::sin(tau*(phaserPhase+channel*.18f));
                    float hz=180.f*std::exp2(sweep*3.6f);
                    float tangent=std::tan(pi*std::min(hz,float(sampleRate)*.4f)/float(sampleRate));
                    phaserCoefficient[channel]=(tangent-1)/(tangent+1);
                }
            }
            float phased[2]={outL,outR};
            for(int channel=0;channel<2;channel++)for(float& state:phaserState[channel]) {
                float input=phased[channel];
                phased[channel]=phaserCoefficient[channel]*input+state;
                state=input-phaserCoefficient[channel]*phased[channel];
            }
            outL+=phaserMix*.5f*(phased[0]-outL);
            outR+=phaserMix*.5f*(phased[1]-outR);
            phaserPhase+=.22f/float(sampleRate);if(phaserPhase>=1)phaserPhase-=1;
            delaySamples+=smooth*.05f*(float(sampleRate*60/global[AGTempo])-delaySamples);
            float dl=delayed(delayL,delayPosition,delaySamples),dr=delayed(delayR,delayPosition,delaySamples);
            delayL[delayPosition]=outL+dr*global[AGDelayFeedback];delayR[delayPosition]=outR+dl*global[AGDelayFeedback];
            delayPosition=(delayPosition+1)%delaySize;
            float reverbInput=(outL+outR)*.16f,rl=0,rr=0;
            for(int i=0;i<4;i++){rl+=combs[i].process(reverbInput);rr+=combs[i+4].process(reverbInput);}
            rl=allpasses[1].process(allpasses[0].process(rl));rr=allpasses[3].process(allpasses[2].process(rr));
            outL+=dl*global[AGDelayMix]+rl*global[AGReverbMix]*.25f;
            outR+=dr*global[AGDelayMix]+rr*global[AGReverbMix]*.25f;
            master+=smooth*(masterTarget-master);
            float finalL=std::tanh(outL*master),finalR=std::tanh(outR*master);
            left[frame]=std::isfinite(finalL)?finalL:0;right[frame]=std::isfinite(finalR)?finalR:0;
            if((sampleCounter&3)==0)scopeSamples[(scopePosition++)%scopeSamples.size()].store((left[frame]+right[frame])*.5f,std::memory_order_relaxed);
            maximum=std::max(maximum,std::max(std::abs(left[frame]),std::abs(right[frame])));
        }
        scopePublished.store(scopePosition,std::memory_order_release);
        int count=0;for(const auto& v:voices)count+=v.active;
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
void SynthEngine::disconnect(int32_t sourceID){impl->submit({Event::Disconnect,sourceID,0,0,0});}
void SynthEngine::panic(){impl->requestPanic();}
void SynthEngine::render(float* left,float* right,uint32_t frames){impl->render(left,right,frames);}
float SynthEngine::peak()const{return impl->outputPeak.load(std::memory_order_relaxed);}
int SynthEngine::activeVoices()const{return impl->voiceCount.load(std::memory_order_relaxed);}
}

int aurora::SynthEngine::copyScope(float* samples,int capacity) const {
    if(!samples || capacity<=0)return 0;
    int count=std::min(capacity,256);
    unsigned end=impl->scopePublished.load(std::memory_order_acquire);
    for(int i=0;i<count;i++)samples[i]=impl->scopeSamples[(end-count+i)%512].load(std::memory_order_relaxed);
    return count;
}

void aurora::SynthEngine::setMatrix(int bank,int slot,bool enabled,int source,int destination,int target,int cc,float amount) {
    if(bank<0||bank>4||slot<0||slot>=6)return;
    if(source<0||source>(bank==4?5:2)||destination<0||destination>(bank==4?11:5)||target<0||target>4||cc<0||cc>127||!std::isfinite(amount))enabled=false;
    unsigned a=unsigned(int(std::round(std::clamp(std::isfinite(amount)?amount:0.f,-1.f,1.f)*32767))+32768);
    uint64_t bits=enabled?(1ull|(uint64_t(source)<<1)|(uint64_t(destination)<<4)|(uint64_t(target)<<8)|(uint64_t(cc)<<11)|(uint64_t(a)<<18)):0;
    impl->matrix[bank][slot].store(bits,std::memory_order_relaxed);
}
