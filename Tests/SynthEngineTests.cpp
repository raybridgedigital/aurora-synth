#include "SynthEngine.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <initializer_list>
#include <limits>
#include <thread>
#include <vector>

using aurora::SynthEngine;
namespace {
constexpr int rate=48000;
void dry(SynthEngine& e) {
    e.prepare(rate);e.setGlobal(AGDelayMix,0);e.setGlobal(AGReverbMix,0);e.setGlobal(AGChorusMix,0);
    e.setParameter(0,APRelease,.025f);e.setParameter(0,APAttack,.003f);
}
// Only Delay and Reverb ship powered; a test that exercises another effect must say so.
void powerOn(SynthEngine& e,std::initializer_list<int> effects){for(int id:effects)e.setGlobal(id,1);}
float render(SynthEngine& e,int frames=4800) {
    std::array<float,257> l{},r{};float peak=0;
    while(frames>0) {
        int n=std::min(frames,int(l.size()));e.render(l.data(),r.data(),uint32_t(n));
        for(int i=0;i<n;i++) { assert(std::isfinite(l[i])&&std::isfinite(r[i]));
            assert(std::abs(l[i])<=1&&std::abs(r[i])<=1);peak=std::max(peak,std::max(std::abs(l[i]),std::abs(r[i]))); }
        frames-=n;
    }
    return peak;
}

float drainPanic(SynthEngine& e) {
    // Mute-bus Panic: fade out (~100–200 ms) + hold wipe (~80 ms) + short fade-in.
    // Peak during the fade is expected; assert silence only after the wipe.
    // Use enough frames for the highest SR exercised in these tests (192 kHz).
    e.panic();
    render(e, int(192000 * 0.45));
    return render(e, 4800);
}
void note(SynthEngine& e,int source,int key,int velocity=100,int channel=0){e.midi(source,uint8_t(0x90|channel),uint8_t(key),uint8_t(velocity));}
void off(SynthEngine& e,int source,int key,int channel=0){e.midi(source,uint8_t(0x80|channel),uint8_t(key),0);}
void cc(SynthEngine& e,int source,int number,int value,int channel=0){e.midi(source,uint8_t(0xb0|channel),uint8_t(number),uint8_t(value));}
void ownership() {
    SynthEngine e;dry(e);
    note(e,10,60);assert(render(e)>.005f);assert(e.activeVoices()==1);
    note(e,-803,60);render(e);assert(e.activeVoices()==2);
    off(e,10,60);render(e);assert(e.activeVoices()==1);
    off(e,-803,60);render(e);assert(e.activeVoices()==0);assert(render(e)<1e-7f);
    note(e,10,60,100,0);note(e,10,60,100,1);render(e);assert(e.activeVoices()==2);
    off(e,10,60,0);render(e);assert(e.activeVoices()==1);off(e,10,60,1);render(e);assert(e.activeVoices()==0);
    note(e,10,60);note(e,20,64);cc(e,10,64,127);off(e,10,60);off(e,20,64);
    render(e);assert(e.activeVoices()==1);cc(e,20,64,0);render(e);assert(e.activeVoices()==1);
    cc(e,10,64,0);render(e);assert(e.activeVoices()==0);
    note(e,10,60);render(e);e.setParameter(0,APTranspose,24);e.setParameter(0,APKeyLow,80);
    off(e,10,60);render(e);assert(e.activeVoices()==0);
    e.setParameter(0,APKeyLow,0);note(e,10,60);note(e,20,60);render(e);
    e.disconnect(10);render(e);assert(e.activeVoices()==1);
    note(e,10,62);render(e);assert(e.activeVoices()==1); // Late callback is ignored.
    e.route(10,1,0);note(e,10,62);render(e);assert(e.activeVoices()==2);
    assert(drainPanic(e)<1e-7f);assert(e.activeVoices()==0);
    std::puts("PASS: notes, release, source/channel/sustain ownership, transpose, disconnect, panic");
}
void deferredPanicCommit() {
    SynthEngine e;dry(e);
    e.setParameter(0,APRelease,.02f);e.setGlobal(AGMaster,.8f);
    e.panic();
    e.setParameter(0,APRelease,.31f);e.setGlobal(AGMaster,.31f);
    // Panic captures the live patch, then defers subsequent patch writes.
    assert(std::abs(e.getParameter(0,APRelease)-.02f)<.0001f);
    assert(std::abs(e.getGlobal(AGMaster)-.8f)<.0001f);
    render(e,int(rate*.05)); // minimum fade-out is ~100 ms, so values must still be live-old here
    assert(std::abs(e.getParameter(0,APRelease)-.02f)<.0001f);
    assert(std::abs(e.getGlobal(AGMaster)-.8f)<.0001f);
    render(e,int(rate*.25)); // by 300 ms total, even the longest fade has crossed the silent commit boundary
    assert(std::abs(e.getParameter(0,APRelease)-.31f)<.0001f);
    assert(std::abs(e.getGlobal(AGMaster)-.31f)<.0001f);
    render(e,int(rate*.20)); // finish fade-in so following tests start from Idle
    std::puts("PASS: Panic defers patch writes during fade-out and commits them at the silent boundary");
}

void routingAndPrepare() {
    SynthEngine e;dry(e);e.setParameter(1,APEnabled,1);e.setParameter(1,APRelease,.02f);
    e.route(808,2,2);e.panic();
    e.setParameter(1,APRelease,.031f);e.setGlobal(AGMaster,.31f);
    e.prepare(44100); // Route survives prepare; deferred patch state commits at this silent boundary.
    assert(std::abs(e.getParameter(1,APRelease)-.031f)<.0001f&&std::abs(e.getGlobal(AGMaster)-.31f)<.0001f);
    note(e,808,60,100,0);render(e);assert(e.activeVoices()==0);
    note(e,808,60,100,1);render(e);assert(e.activeVoices()==1);
    note(e,0,65);render(e);assert(e.activeVoices()==3); // GUI follows all enabled layers.
    e.route(808,1,1);render(e);assert(e.activeVoices()==2);
    (void)drainPanic(e);note(e,808,60,100,0);render(e);assert(e.activeVoices()==1);
    note(e,808,63);e.prepare(96000);render(e);assert(e.activeVoices()==0); // Stopped notes discarded.
    std::puts("PASS: channel/layer routing, GUI layers, prepare state and deferred patch preservation");
}
double frequency(const std::vector<float>& audio,int start,int count) {
    int crossings=0;for(int i=start+1;i<start+count;i++)crossings+=audio[i-1]<=0&&audio[i]>0;
    return double(crossings)*rate/count;
}
void globalTranspose() {
    for(int layer=0;layer<4;layer++) {
        SynthEngine e;dry(e);
        for(int j=0;j<4;j++)e.setParameter(j,APEnabled,j==layer);
        e.setParameter(layer,APWave1,0);e.setParameter(layer,APBlend,0);e.setParameter(layer,APSub,0);
        e.setParameter(layer,APNoise,0);e.setParameter(layer,APLFODepth,0);e.setParameter(layer,APLFO2Depth,0);
        e.setParameter(layer,APTranspose,0);e.setParameter(layer,APSustain,1);e.setParameter(layer,APRelease,.01f);
        e.setParameter(layer,APKeyLow,69);e.setParameter(layer,APKeyHigh,69);
        e.route(44,1<<layer,0);note(e,44,69);
        std::vector<float> l(rate),r(rate);
        for(int shift:{0,12,-12,99}) {
            e.setTranspose(shift);e.render(l.data(),r.data(),rate);
            double measured=frequency(l,rate/2,rate/2),expected=440*std::exp2(std::clamp(shift,-24,24)/12.0);
            assert(std::abs(measured-expected)<5);assert(e.activeVoices()==1);
        }
        off(e,44,69);render(e,rate);assert(e.activeVoices()==0);
    }
    std::puts("PASS: global transpose retunes held notes in all four layers, clamps, preserves splits and note-off ownership");
}
void arp() {
    SynthEngine e;dry(e);
    e.setParameter(0,APWave1,0);e.setParameter(0,APBlend,0);e.setParameter(0,APSub,0);
    e.setParameter(0,APFilterEnvelope,0);e.setParameter(0,APCutoff,20000);e.setParameter(0,APResonance,0);
    e.setParameter(0,APArpEnabled,1);e.setParameter(0,APArpRate,1);e.setParameter(0,APArpGate,.8f);
    e.setParameter(0,APRelease,.004f);e.setGlobal(AGTempo,120);
    note(e,44,60);note(e,44,64);note(e,44,67);
    std::vector<float> l(rate),r(rate);e.render(l.data(),r.data(),rate);
    double first=frequency(l,2400,4800),second=frequency(l,14400,4800),third=frequency(l,26400,4800);
    assert(first>240&&first<280);assert(second>310&&second<350);assert(third>370&&third<420);
    float gatePeak=0;for(int i=11000;i<11800;i++)gatePeak=std::max(gatePeak,std::abs(l[i]));assert(gatePeak<.0001f);
    cc(e,44,64,127);off(e,44,60);off(e,44,64);off(e,44,67);assert(render(e,rate)>.001f);
    cc(e,44,64,0);render(e,rate);assert(e.activeVoices()==0);
    assert(render(e,rate)<.00001f);
    std::printf("PASS: arp pitch order %.0f/%.0f/%.0f Hz, gate, sustain and stop\n",first,second,third);
}
void overflowAndConcurrent() {
    SynthEngine e;dry(e);note(e,1,60);render(e);
    for(int i=0;i<10000;i++)note(e,1,i%128);
    // Queue overflow triggers mute-bus Panic — wait for wipe, then assert silence.
    assert(drainPanic(e)<1e-7f);assert(e.activeVoices()==0);
    note(e,1,60);assert(render(e)>.001f);off(e,1,60);render(e);
    std::atomic<bool> begin{false};std::array<std::thread,4> producers;
    for(int p=0;p<4;p++)producers[p]=std::thread([&,p] {
        while(!begin.load(std::memory_order_acquire))std::this_thread::yield();
        for(int i=0;i<10000;i++){note(e,100+p,48+i%24);off(e,100+p,48+i%24);e.setParameter(p,APCutoff,float(20+i%19000));}
    });
    begin.store(true,std::memory_order_release);
    for(int i=0;i<250;i++)render(e,128);
    for(auto& t:producers)t.join();assert(drainPanic(e)<1e-7f);assert(e.activeVoices()==0);
    std::puts("PASS: bounded queue overflow recovery and four concurrent MIDI/control producers");
}
void extremesAndCapacity() {
    SynthEngine e;dry(e);
    for(int l=0;l<4;l++) {
        for(int p=0;p<APParameterCount;p++)e.setParameter(l,p,std::numeric_limits<float>::quiet_NaN());
        e.setParameter(l,APEnabled,1);e.setParameter(l,APKeyLow,0);e.setParameter(l,APKeyHigh,127);
        e.setParameter(l,APLevel,1);e.setParameter(l,APSustain,1);e.setParameter(l,APNoise,1);
        e.setParameter(l,APDrive,1);e.setParameter(l,APResonance,1);e.setParameter(l,APFilterEnvelope,1);
        e.setParameter(l,APLFODepth,1);e.setParameter(l,APLFO2Depth,1);
        e.setParameter(l,APLFORate,30);e.setParameter(l,APLFO2Rate,30);e.setParameter(l,APRelease,.01f);
    }
    e.setGlobal(AGMaster,1);e.setGlobal(AGDelayMix,1);e.setGlobal(AGDelayFeedback,1000);
    e.setGlobal(AGReverbMix,1);e.setGlobal(AGChorusMix,1);assert(e.getGlobal(AGDelayFeedback)==.85f);
    for(int n=0;n<100;n++)note(e,0,n);render(e);assert(e.activeVoices()==64);
    for(int wave=0;wave<5;wave++)for(int filter=0;filter<3;filter++) {
        for(int l=0;l<4;l++){e.setParameter(l,APWave1,float(wave));e.setParameter(l,APWave2,float((wave+1)%5));
            e.setParameter(l,APFilterType,float(filter));e.setParameter(l,APCutoff,filter==0?20:20000);}
        render(e,1024);
    }
    (void)drainPanic(e);for(int source=1;source<60;source++)note(e,source,60);render(e);assert(e.activeVoices()<=32);
    (void)drainPanic(e);std::puts("PASS: finite extreme controls, oscillator/filter modes, 64 voices, bounded source capacity");
}
void phaserEffect() {
    for(double sampleRate:{44100.,48000.,96000.,192000.}) {
        SynthEngine dryEngine,wetEngine;dry(dryEngine);dry(wetEngine);
        dryEngine.prepare(sampleRate);wetEngine.prepare(sampleRate);
        powerOn(wetEngine,{AGPhaserPower});
        wetEngine.setGlobal(AGPhaserMix,1);
        note(dryEngine,0,60);note(wetEngine,0,60);
        std::array<float,256> dl{},dr{},wl{},wr{};double difference=0;
        for(int block=0;block<800;block++) {
            dryEngine.render(dl.data(),dr.data(),256);wetEngine.render(wl.data(),wr.data(),256);
            for(int i=0;i<256;i++){assert(std::isfinite(wl[i])&&std::isfinite(wr[i]));assert(std::abs(wl[i])<=1 && std::abs(wr[i])<=1);difference+=std::abs(wl[i]-dl[i]);}
        }
        assert(difference>1);
        assert(drainPanic(wetEngine)<1e-7f);
        wetEngine.setGlobal(AGPhaserMix,2);assert(wetEngine.getGlobal(AGPhaserMix)==1);
    }
    std::puts("PASS: phaser audibly changes output, remains finite at four sample rates, clamps and clears on panic");
}
void scopeCapture() {
    SynthEngine e;dry(e);note(e,0,60);render(e,4096);
    std::array<float,256> samples{};
    assert(e.copyScope(samples.data(),256)==256);
    float peak=0;for(float x:samples){assert(std::isfinite(x));peak=std::max(peak,std::abs(x));}
    assert(peak>.001f);assert(e.copyScope(nullptr,256)==0);
    (void)drainPanic(e);e.copyScope(samples.data(),256);
    for(float x:samples)assert(x==0);
    std::puts("PASS: scope captures actual output and clears after panic");
}
void lfoTwoShapes() {
    std::array<std::vector<float>,5> audio;
    for(int shape=0;shape<5;shape++) {
        SynthEngine e;dry(e);e.setParameter(0,APLFODepth,0);
        e.setParameter(0,APLFO2Rate,8);e.setParameter(0,APLFO2Depth,1);
        e.setParameter(0,APLFO2Destination,3);e.setParameter(0,APLFO2Shape,float(shape));
        assert(e.getParameter(0,APLFO2Shape)==shape);note(e,0,60);
        audio[shape].resize(rate);std::vector<float> right(rate);e.render(audio[shape].data(),right.data(),rate);
        for(float sample:audio[shape])assert(std::isfinite(sample));
        off(e,0,60);render(e,rate);assert(e.activeVoices()==0);
    }
    for(int a=0;a<5;a++)for(int b=a+1;b<5;b++) {
        double delta=0;for(int i=rate/2;i<rate;i++)delta+=std::abs(audio[a][i]-audio[b][i]);assert(delta>1);
    }
    std::puts("PASS: all five LFO 2 waveforms produce distinct modulation and release correctly");
}
void matrixLFOs() {
    auto take=[&](bool route, float depth, float hz) {
        SynthEngine e;dry(e);
        e.setParameter(0,APLFODepth,0);e.setParameter(0,APLFO2Depth,0);
        e.setParameter(0,APLFO3Shape,2);e.setParameter(0,APLFO3Rate,hz);e.setParameter(0,APLFO3Depth,depth);
        e.setParameter(0,APLFO5Shape,2);e.setParameter(0,APLFO5Rate,hz);e.setParameter(0,APLFO5Depth,1);
        if(route)e.setMatrix(0,7,true,6,1,4,1,1.f);
        note(e,0,60);
        std::vector<float> left(rate), right(rate);
        e.render(left.data(),right.data(),rate);
        for(float sample:left)assert(std::isfinite(sample));
        return left;
    };
    auto plain=take(false,1,8);
    auto full=take(true,1,8);
    auto quiet=take(true,0,8);
    double moved=0,scaled=0;
    for(int i=rate/4;i<rate;i++){moved+=std::abs(full[i]-plain[i]);scaled+=std::abs(quiet[i]-plain[i]);}
    assert(moved>1);
    assert(scaled<1e-4);
    SynthEngine fast,slow;dry(fast);dry(slow);
    for(SynthEngine* e:{&fast,&slow}){e->setParameter(0,APLFODepth,0);e->setParameter(0,APLFO2Depth,0);e->setParameter(0,APLFO5Depth,1);e->setParameter(0,APLFO5Shape,2);e->setMatrix(0,9,true,8,3,4,1,1.f);}
    fast.setParameter(0,APLFO5Rate,12);slow.setParameter(0,APLFO5Rate,.4f);
    note(fast,0,60);note(slow,0,60);
    std::vector<float> a(rate),b(rate),ar(rate),br(rate);
    fast.render(a.data(),ar.data(),rate);slow.render(b.data(),br.data(),rate);
    double fifth=0;for(int i=rate/4;i<rate;i++)fifth+=std::abs(a[i]-b[i]);
    assert(fifth>1);
    assert(fast.getParameter(0,APLFO3Depth)==1);
    std::puts("PASS: LFO 3–5 are Matrix-only, Depth scales them, and LFO 5 does not alias to LFO 1");
}
std::vector<float> matrixAudio(int bank,int source,int destination,int target=4,bool enabled=true,float amount=.65f,int controllerChannel=0) {
    SynthEngine e;dry(e);powerOn(e,{AGChorusPower,AGPhaserPower});e.setParameter(0,APAttack,.01f);e.setParameter(0,APCutoff,1700);
    e.setParameter(0,APLFORate,4);e.setParameter(0,APLFO2Rate,7);
    e.setParameter(0,APLFODestination,1);e.setParameter(0,APLFO2Destination,2);
    e.setMatrix(bank,0,enabled,source,destination,target,74,amount);
    e.route(55,1,1);
    cc(e,55,1,100,controllerChannel);cc(e,55,11,100,controllerChannel);cc(e,55,64,127,controllerChannel);cc(e,55,74,100,controllerChannel);e.midi(55,uint8_t(0xd0|controllerChannel),100,0);
    note(e,55,60,100);
    std::vector<float> left(rate),right(rate);e.render(left.data(),right.data(),uint32_t(left.size()));
    for(size_t i=0;i<left.size();i++){assert(std::isfinite(left[i])&&std::isfinite(right[i]));assert(std::abs(left[i])<=1&&std::abs(right[i])<=1);}
    assert(drainPanic(e)<1e-7f);
    left.insert(left.end(),right.begin(),right.end());return left;
}
void matrices() {
    auto difference=[](const auto& a,const auto& b){double total=0;for(size_t i=0;i<a.size();i++)total+=std::abs(a[i]-b[i]);return total;};
    auto drySound=matrixAudio(0,0,0,4,false);
    for(int source=0;source<3;source++)for(int destination=0;destination<6;destination++) {
        assert(difference(drySound,matrixAudio(0,source,destination))>.001);
        assert(difference(drySound,matrixAudio(0,source,destination,4,false))==0);
    }
    for(int source=0;source<6;source++)for(int destination=0;destination<12;destination++) {
        double delta=difference(drySound,matrixAudio(4,source,destination));
        if(delta<=.001)std::fprintf(stderr,"Matrix source %d destination %d difference %f\n",source,destination,delta);
        assert(delta>.001);
        if(destination<8)assert(difference(drySound,matrixAudio(4,source,destination,1))==0);
    }
    assert(difference(matrixAudio(4,0,9,4,false,.65f,1),matrixAudio(4,0,9,4,true,.65f,1))==0); // Wrong-channel CC cannot control shared effects.
    assert(difference(drySound,matrixAudio(1,0,0))==0); // Layer B's sound route cannot affect A.
    assert(difference(drySound,matrixAudio(4,99,99))==0); // Invalid routes are disabled.
    assert(difference(drySound,matrixAudio(0,2,3,4,true,-1))>.001);
    std::puts("PASS: all 18 Sound Matrix and 72 Performance Matrix source/destination combinations, bypass, layer isolation, negative amounts and invalid-route protection");
}
void oscillatorCharacter() {
    auto sound=[](int mode){
        SynthEngine e;dry(e);e.setParameter(0,APWave1,3);e.setParameter(0,APWave2,3);e.setParameter(0,APBlend,.8f);
        e.setParameter(0,APLFODepth,0);e.setParameter(0,APLFORate,5);
        if(mode==1)e.setParameter(0,APPulseWidth,.2f);
        if(mode==2)e.setParameter(0,APPWMDepth,.7f);
        if(mode==3||mode==4){e.setParameter(0,APUnison,4);e.setParameter(0,APStereoSpread,mode==3?0:1);}
        if(mode==5){e.setParameter(0,APSync,1);e.setParameter(0,APSyncTune,19);}
        note(e,0,60);std::vector<float> l(rate),r(rate);e.render(l.data(),r.data(),rate);
        for(int i=0;i<rate;i++)assert(std::isfinite(l[i])&&std::isfinite(r[i])&&std::abs(l[i])<=1&&std::abs(r[i])<=1);
        off(e,0,60);render(e,rate);assert(e.activeVoices()==0);
        l.insert(l.end(),r.begin(),r.end());return l;
    };
    auto baseline=sound(0);
    for(int mode=1;mode<=5;mode++){auto result=sound(mode);double delta=0;for(size_t i=0;i<result.size();i++)delta+=std::abs(result[i]-baseline[i]);assert(delta>1);}
    auto mono=sound(3),stereo=sound(4);double width=0;
    for(int i=0;i<rate;i++){assert(mono[i]==mono[i+rate]);width+=std::abs(stereo[i]-stereo[i+rate]);}assert(width>1);
    for(double sr:{44100.,48000.,96000.,192000.}){
        SynthEngine e;dry(e);e.prepare(sr);e.setParameter(0,APUnison,4);e.setParameter(0,APPWMDepth,1);e.setParameter(0,APSync,1);e.setParameter(0,APSyncTune,36);
        for(int wave=0;wave<5;wave++){e.setParameter(0,APWave1,float(wave));e.setParameter(0,APWave2,float(wave));note(e,0,12);note(e,0,127);render(e);assert(drainPanic(e)<1e-7f);}
    }
    std::puts("PASS: pulse width, PWM, unison, stereo spread and sync change audio; stereo isolation, note release and extremes at four sample rates");
}
void modulationFeedback() {
    SynthEngine e;dry(e);e.setMatrix(0,5,true,2,0,4,1,.5f);e.setMatrix(4,3,true,0,2,0,1,-.75f);
    cc(e,0,1,127);note(e,0,60);render(e);
    std::array<float,46> feedback{};assert(e.copyModulation(feedback.data(),46)==46);assert(e.copyModulation(nullptr,46)==0);
    assert(feedback[5]>0 && feedback[5]<=.501f);assert(std::abs(feedback[43]+.75f)<.001f);
    for(int i=0;i<46;i++)if(i!=5&&i!=43)assert(feedback[i]==0);
    e.setMatrix(4,3,false,0,2,0,1,-.75f);render(e);e.copyModulation(feedback.data(),46);assert(feedback[43]==0);
    (void)drainPanic(e);e.copyModulation(feedback.data(),46);for(float x:feedback)assert(x==0);
    std::puts("PASS: signed modulation feedback preserves sparse route slots, bypasses and clears on panic");
}
void expressivePlaying() {
    auto setup=[](SynthEngine& e,int mode){dry(e);e.setParameter(0,APVoiceMode,float(mode));e.setParameter(0,APWave1,0);e.setParameter(0,APBlend,0);e.setParameter(0,APSub,0);e.setParameter(0,APFilterEnvelope,0);e.setParameter(0,APLFODepth,0);e.setParameter(0,APCutoff,18000);};
    for(int mode=1;mode<=2;mode++){
        SynthEngine e;setup(e,mode);note(e,1,60);render(e);note(e,1,72);render(e);assert(e.activeVoices()==1);
        off(e,1,72);std::vector<float> l(rate),r(rate);e.render(l.data(),r.data(),rate);assert(e.activeVoices()==1);assert(std::abs(frequency(l,rate/2,rate/2)-262)<5);
        note(e,2,67);render(e);assert(e.activeVoices()==2);off(e,2,67);render(e);assert(e.activeVoices()==1);
        cc(e,1,64,127);note(e,1,72);off(e,1,72);render(e);cc(e,1,64,0);e.render(l.data(),r.data(),rate);assert(std::abs(frequency(l,rate/2,rate/2)-262)<5);
        off(e,1,60);render(e,rate);assert(e.activeVoices()==0);
        note(e,1,60);render(e);e.disconnect(1);render(e);assert(e.activeVoices()==0 && render(e)<1e-7f);
    }
    SynthEngine e;setup(e,2);e.setParameter(0,APGlide,1);note(e,0,60);render(e);note(e,0,72);
    std::vector<float> l(rate),r(rate);e.render(l.data(),r.data(),rate);
    assert(frequency(l,0,4800)<450);assert(frequency(l,rate/2,rate/2)>510);
    e.setParameter(0,APBendRange,12);e.midi(0,0xe0,127,127);e.render(l.data(),r.data(),rate);assert(std::abs(frequency(l,rate/2,rate/2)-1046)<8);
    e.setParameter(0,APBendRange,0);e.render(l.data(),r.data(),rate);assert(std::abs(frequency(l,rate/2,rate/2)-523)<5);
    float peaks[4]{};
    for(int curve=0;curve<4;curve++){SynthEngine v;setup(v,0);v.velocityCurve(19,curve);note(v,19,60,40);peaks[curve]=render(v);}
    assert(peaks[1]>peaks[0]&&peaks[0]>peaks[2]&&peaks[3]>peaks[1]);
    std::puts("PASS: mono/legato last-note return, sustain, source isolation, disconnect, glide trajectory, live bend range and velocity curves");
}
void extendedEffects() {
    auto sound=[](int parameter,float value){SynthEngine e;dry(e);powerOn(e,{AGPhaserPower,AGChorusPower});e.setGlobal(AGPhaserMix,.8f);e.setGlobal(AGChorusMix,.6f);e.setGlobal(AGReverbMix,.7f);e.setGlobal(AGDelayMix,.6f);if(parameter>=0)e.setGlobal(parameter,value);note(e,0,60);render(e,2400);off(e,0,60);std::vector<float> l(rate*2),r(rate*2);e.render(l.data(),r.data(),uint32_t(l.size()));for(float x:l)assert(std::isfinite(x)&&std::abs(x)<=1);assert(drainPanic(e)<1e-7f);return l;};
    auto baseline=sound(-1,0);
    for(auto pair:std::array<std::pair<int,float>,8>{{{AGPhaserRate,3},{AGPhaserDepth,.1f},{AGPhaserFeedback,.7f},{AGChorusRate,3},{AGChorusDepth,.1f},{AGReverbSize,1},{AGReverbDecay,5},{AGDelayTiming,4}}}){
        auto other=sound(pair.first,pair.second);double delta=0;for(size_t i=0;i<other.size();i++)delta+=std::abs(other[i]-baseline[i]);assert(delta>.01);
    }
    for(double sr:{44100.,48000.,96000.,192000.}){SynthEngine e;e.prepare(sr);e.setGlobal(AGTempo,30);e.setGlobal(AGDelayMix,1);e.setGlobal(AGPhaserMix,1);e.setGlobal(AGPhaserFeedback,.85f);e.setGlobal(AGReverbMix,1);e.setGlobal(AGReverbDecay,8);e.setGlobal(AGReverbSize,1);note(e,0,60);for(int timing=0;timing<8;timing++){e.setGlobal(AGDelayTiming,float(timing));render(e,4096);}assert(drainPanic(e)<1e-7f);}
    std::puts("PASS: all eight FX controls change rendered audio; all delay timings and maximum feedback stay bounded at four sample rates");
}
void masterFxPower() {
    // Each master FX power toggle has to be a real bypass in the engine, not a UI flag.
    // Two claims are checked: a toggle is a true switch (never a partial blend), and an
    // unpowered effect contributes exactly nothing — alone, and with every other effect
    // struck at the same time. "Exactly nothing" is measured against the same patch with
    // that effect dialled transparent, which is the untouched dry bus.
    constexpr std::array<int,10> power{AGShimmerPower,AGDelayPower,AGReverbPower,AGChorusPower,AGPhaserPower,
                                       AGFlangerPower,AGTremPower,AGCrushPower,AGWahPower,AGCompPower};
    constexpr int frames=16800; // 0.35 s: note on, release, then the effect tails
    auto capture=[&power](unsigned liveMask,unsigned offMask){
        SynthEngine e;
        auto on=[liveMask](int i){return (liveMask>>i)&1u;};
        e.setParameter(0,APAttack,.003f);e.setParameter(0,APRelease,.025f);
        e.setGlobal(AGShimmerMix,on(0)?1.f:0.f);e.setGlobal(AGShimmerAmount,.9f);e.setGlobal(AGShimmerDecay,8);
        e.setGlobal(AGShimmerVoice1,1);e.setGlobal(AGShimmerVoice2,1);e.setGlobal(AGShimmerVoice3,1);
        e.setGlobal(AGDelaySync,0);e.setGlobal(AGDelayMix,on(1)?.6f:0.f);e.setGlobal(AGDelayFeedback,.75f);e.setGlobal(AGDelayTimeMs,60);
        e.setGlobal(AGReverbMix,on(2)?.75f:0.f);e.setGlobal(AGReverbSize,1);e.setGlobal(AGReverbDecay,6);
        e.setGlobal(AGChorusMix,on(3)?.6f:0.f);e.setGlobal(AGChorusRate,3);e.setGlobal(AGChorusDepth,1);
        e.setGlobal(AGPhaserMix,on(4)?.8f:0.f);e.setGlobal(AGPhaserRate,3);e.setGlobal(AGPhaserDepth,1);e.setGlobal(AGPhaserFeedback,.7f);
        e.setGlobal(AGFlangerMix,on(5)?.8f:0.f);e.setGlobal(AGFlangerDepth,1);e.setGlobal(AGFlangerFeedback,.8f);
        e.setGlobal(AGTremMix,on(6)?1.f:0.f);e.setGlobal(AGTremDepth,1);e.setGlobal(AGTremRate,4);
        e.setGlobal(AGCrushMix,on(7)?1.f:0.f);e.setGlobal(AGCrushBits,4);e.setGlobal(AGCrushDownsample,8);
        e.setGlobal(AGWahMix,on(8)?1.f:0.f);e.setGlobal(AGWahSensitivity,1);e.setGlobal(AGWahRange,1);
        e.setGlobal(AGCompThreshold,on(9)?-40.f:0.f);e.setGlobal(AGCompRatio,12);e.setGlobal(AGCompMakeup,on(9)?18.f:0.f);
        for(int i=0;i<10;i++)e.setGlobal(power[size_t(i)],((offMask>>i)&1u)?0.f:1.f);
        // prepare() snapshots the toggles, so a struck effect starts fully closed
        // instead of leaking one fade of wet audio before its gate settles.
        e.prepare(rate);
        std::array<float,257> l{},r{};std::vector<float> out;out.reserve(size_t(frames)*2);
        auto push=[&](int n){for(int i=0;i<n;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));assert(std::abs(l[i])<=1&&std::abs(r[i])<=1);out.push_back(l[i]);out.push_back(r[i]);}};
        note(e,0,60);note(e,0,67);
        for(int remaining=frames/2;remaining>0;){int n=std::min(remaining,257);e.render(l.data(),r.data(),uint32_t(n));push(n);remaining-=n;}
        off(e,0,60);off(e,0,67);
        for(int remaining=frames-frames/2;remaining>0;){int n=std::min(remaining,257);e.render(l.data(),r.data(),uint32_t(n));push(n);remaining-=n;}
        assert(e.activeVoices()==0);
        return out;
    };
    auto difference=[](const std::vector<float>& a,const std::vector<float>& b){double worst=0;for(size_t i=0;i<a.size();i++)worst=std::max(worst,double(std::abs(a[i]-b[i])));return worst;};
    {SynthEngine e; // Shipping default: only the shared Delay and Reverb returns are powered.
     for(int id:power){
         bool expectOn=id==AGDelayPower||id==AGReverbPower;
         assert(e.getGlobal(id)==(expectOn?1.f:0.f));
     }
     // A power toggle is a switch, never a wet blend.
     e.setGlobal(AGShimmerPower,.4f);assert(e.getGlobal(AGShimmerPower)==0);
     e.setGlobal(AGShimmerPower,.6f);assert(e.getGlobal(AGShimmerPower)==1);
     e.setGlobal(AGCompPower,-3);assert(e.getGlobal(AGCompPower)==0);
     e.setGlobal(AGWahPower,7);assert(e.getGlobal(AGWahPower)==1);
     // A bare engine must be silent apart from the two shared returns.
     e.setGlobal(AGDelayMix,0);e.setGlobal(AGReverbMix,0);
     dry(e);powerOn(e,{AGShimmerPower,AGChorusPower,AGPhaserPower,AGFlangerPower,AGTremPower,AGCrushPower,AGWahPower,AGCompPower,AGReverbPower});
     e.setGlobal(AGShimmerMix,1);e.setGlobal(AGCompThreshold,-40);e.setGlobal(AGCompRatio,12);e.setGlobal(AGCompMakeup,18);
     note(e,0,60);render(e,2400);off(e,0,60);render(e);
     assert(drainPanic(e)<1e-7f);}
    // Reference bus: every effect dialled transparent with every power switch on.
    auto neutral=capture(0,0);
    // Each effect on its own has to change the bus, otherwise the toggle proves nothing.
    for(int i=0;i<10;i++){auto wet=capture(1u<<i,0);assert(difference(wet,neutral)>1e-3);}
    // Each effect switched off has to give that same dry bus back.
    for(int i=0;i<10;i++){auto struck=capture(1u<<i,1u<<i);assert(difference(struck,neutral)<1e-7);}
    auto allStruck=capture(0x3ffu,0x3ffu);assert(difference(allStruck,neutral)<1e-7);
    std::puts("PASS: all ten master FX power toggles are true switches; a struck effect renders the dry bus exactly, alone and with every effect struck together");
}
void silentVoiceRelease() {
    // A natural-decay note (sustain 0) held by the pedal renders exact silence once decayed.
    // In poly mode its voice is freed, so pedalled playing cannot fill the pool with silence.
    SynthEngine e;dry(e);e.setParameter(0,APSustain,0);e.setParameter(0,APDecay,.05f);e.setParameter(0,APRelease,.3f);
    cc(e,0,64,127);
    for(int k=40;k<100;k++){note(e,0,k);render(e,240);off(e,0,k);}
    render(e,rate/2);assert(e.activeVoices()==0);assert(render(e,4800)==0);
    note(e,0,60);assert(render(e,2400)>.01f);        // a new note still speaks normally
    cc(e,0,64,0);render(e,rate);assert(e.activeVoices()==0);
    // Mono/legato keeps its single voice so a legato note does not re-attack after the decay.
    SynthEngine m;dry(m);m.setParameter(0,APVoiceMode,2);m.setParameter(0,APSustain,0);m.setParameter(0,APDecay,.05f);
    note(m,0,60);render(m,rate/2);assert(m.activeVoices()==1);note(m,0,64);render(m,2400);assert(m.activeVoices()==1);
    off(m,0,64);off(m,0,60);render(m,rate);assert(m.activeVoices()==0);
    std::puts("PASS: decayed pedal-held poly voices are freed with exact silence; mono legato keeps its voice");
}
void performanceTools() {
    SynthEngine e;dry(e);e.hold(true);note(e,9,60);render(e);off(e,9,60);render(e,rate);assert(e.activeVoices()==1);
    e.hold(false);render(e,rate);assert(e.activeVoices()==0);
    e.hold(true);note(e,9,60);cc(e,9,64,127);off(e,9,60);e.hold(false);render(e);assert(e.activeVoices()==1);cc(e,9,64,0);render(e,rate);assert(e.activeVoices()==0);
    e.hold(true);assert(drainPanic(e)<1e-7f);note(e,9,60);off(e,9,60);render(e,rate);assert(e.activeVoices()==0);
    e.setParameter(0,APArpEnabled,1);e.clockSource(true,9);note(e,9,60);render(e);assert(e.activeVoices()==0);
    e.clock(8,0xf8,1);e.clock(8,0xf8,1.02);render(e);assert(e.clockTempo()==0);
    e.clock(9,0xfa,1);
    for(int tick=0;tick<48;tick++){e.clock(9,0xf8,1+tick/48.0);render(e,1000);}
    assert(std::abs(e.clockTempo()-120)<.1f);
    e.clock(9,0xfc,2);render(e,rate);assert(e.activeVoices()==0&&e.clockTempo()==0);
    e.clock(9,0xfb,3);for(int tick=0;tick<12;tick++){e.clock(9,0xf8,3+tick/48.0);render(e,1000);}assert(e.clockTempo()>119);
    render(e,rate);assert(e.activeVoices()==0&&e.clockTempo()==0);
    e.clockSource(false,9);assert(render(e,rate)>.001f);assert(drainPanic(e)<1e-7f);
    std::puts("PASS: hold/release, sustain ownership, panic resets hold; selected MIDI clock tempo, Start/Stop/Continue, timeout and internal fallback");
}
void benchmark(int unison=1) {
    SynthEngine e;e.prepare(44100);e.setGlobal(AGMaster,.25f);
    powerOn(e,{AGChorusPower,AGPhaserPower});
    e.setGlobal(AGChorusMix,.4f);e.setGlobal(AGDelayMix,.3f);e.setGlobal(AGReverbMix,.3f);
    for(int l=0;l<4;l++) {
        e.setParameter(l,APEnabled,1);e.setParameter(l,APWave1,2);e.setParameter(l,APWave2,3);
        e.setParameter(l,APLFODepth,.3f);e.setParameter(l,APLFO2Depth,.1f);e.setParameter(l,APSustain,.8f);
        e.setParameter(l,APUnison,float(unison));
    }
    e.setGlobal(AGPhaserMix,.5f);
    for(int bank=0;bank<5;bank++)for(int slot=0;slot<6;slot++)e.setMatrix(bank,slot,true,bank==4?1:slot%3,slot,4,74,.15f);
    for(int n=48;n<64;n++)note(e,0,n,80);
    std::array<float,128> l{},r{};std::vector<double> durations;durations.reserve(11000);
    auto beginning=std::chrono::steady_clock::now();
    for(int block=0;block<(44100*30+127)/128;block++) {
        auto start=std::chrono::steady_clock::now();e.render(l.data(),r.data(),128);
        auto end=std::chrono::steady_clock::now();durations.push_back(std::chrono::duration<double,std::micro>(end-start).count());
        for(int i=0;i<128;i++)assert(std::isfinite(l[i])&&std::isfinite(r[i]));
    }
    double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-beginning).count();
    assert(e.activeVoices()==std::min(64,256/unison));std::sort(durations.begin(),durations.end());double deadline=128.0/44100*1e6;
    std::printf("BENCHMARK: 30 s offline, 44.1 kHz/128, %d voices x %d unison + 4 FX + 30 matrix slots: %.3f s wall; p99 %.1f us (%.1f%% of %.1f us deadline), max %.1f us. Not a real-device underrun test.\n",
        e.activeVoices(),unison,elapsed,durations[size_t(durations.size()*.99)],100*durations[size_t(durations.size()*.99)]/deadline,deadline,durations.back());
}
}
int main() { performanceTools();expressivePlaying();extendedEffects();masterFxPower();silentVoiceRelease();oscillatorCharacter();modulationFeedback();matrices();lfoTwoShapes();matrixLFOs();scopeCapture();phaserEffect();globalTranspose();ownership();deferredPanicCommit();routingAndPrepare();arp();overflowAndConcurrent();extremesAndCapacity();if(!std::getenv("AURORA_SKIP_BENCHMARKS")){benchmark();benchmark(4);}std::puts("All SynthEngine tests passed."); }
