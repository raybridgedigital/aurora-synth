#include "SynthEngine.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdio>
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
    e.panic();assert(render(e)<1e-7f);assert(e.activeVoices()==0);
    std::puts("PASS: notes, release, source/channel/sustain ownership, transpose, disconnect, panic");
}
void routingAndPrepare() {
    SynthEngine e;dry(e);e.setParameter(1,APEnabled,1);e.setParameter(1,APRelease,.02f);
    e.route(808,2,2);e.panic();e.prepare(44100); // Route survives prepare and stale panic.
    note(e,808,60,100,0);render(e);assert(e.activeVoices()==0);
    note(e,808,60,100,1);render(e);assert(e.activeVoices()==1);
    note(e,0,65);render(e);assert(e.activeVoices()==3); // GUI follows all enabled layers.
    e.route(808,1,1);render(e);assert(e.activeVoices()==2);
    e.panic();render(e);note(e,808,60,100,0);render(e);assert(e.activeVoices()==1);
    note(e,808,63);e.prepare(96000);render(e);assert(e.activeVoices()==0); // Stopped notes discarded.
    std::puts("PASS: channel/layer routing, GUI layers, prepare state preservation");
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
    assert(render(e)<1e-7f);assert(e.activeVoices()==0);
    note(e,1,60);assert(render(e)>.001f);off(e,1,60);render(e);
    std::atomic<bool> begin{false};std::array<std::thread,4> producers;
    for(int p=0;p<4;p++)producers[p]=std::thread([&,p] {
        while(!begin.load(std::memory_order_acquire))std::this_thread::yield();
        for(int i=0;i<10000;i++){note(e,100+p,48+i%24);off(e,100+p,48+i%24);e.setParameter(p,APCutoff,float(20+i%19000));}
    });
    begin.store(true,std::memory_order_release);
    for(int i=0;i<250;i++)render(e,128);
    for(auto& t:producers)t.join();e.panic();assert(render(e)<1e-7f);assert(e.activeVoices()==0);
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
    e.panic();render(e);for(int source=1;source<60;source++)note(e,source,60);render(e);assert(e.activeVoices()<=32);
    e.panic();render(e);std::puts("PASS: finite extreme controls, oscillator/filter modes, 64 voices, bounded source capacity");
}
void phaserEffect() {
    for(double sampleRate:{44100.,48000.,96000.,192000.}) {
        SynthEngine dryEngine,wetEngine;dry(dryEngine);dry(wetEngine);
        dryEngine.prepare(sampleRate);wetEngine.prepare(sampleRate);
        wetEngine.setGlobal(AGPhaserMix,1);
        note(dryEngine,0,60);note(wetEngine,0,60);
        std::array<float,256> dl{},dr{},wl{},wr{};double difference=0;
        for(int block=0;block<800;block++) {
            dryEngine.render(dl.data(),dr.data(),256);wetEngine.render(wl.data(),wr.data(),256);
            for(int i=0;i<256;i++){assert(std::isfinite(wl[i])&&std::isfinite(wr[i]));assert(std::abs(wl[i])<=1 && std::abs(wr[i])<=1);difference+=std::abs(wl[i]-dl[i]);}
        }
        assert(difference>1);
        wetEngine.panic();assert(render(wetEngine)<1e-7f);
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
    e.panic();render(e,4096);e.copyScope(samples.data(),256);
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
std::vector<float> matrixAudio(int bank,int source,int destination,int target=4,bool enabled=true,float amount=.65f,int controllerChannel=0) {
    SynthEngine e;dry(e);e.setParameter(0,APAttack,.01f);e.setParameter(0,APCutoff,1700);
    e.setParameter(0,APLFORate,4);e.setParameter(0,APLFO2Rate,7);
    e.setParameter(0,APLFODestination,1);e.setParameter(0,APLFO2Destination,2);
    e.setMatrix(bank,0,enabled,source,destination,target,74,amount);
    e.route(55,1,1);
    cc(e,55,1,100,controllerChannel);cc(e,55,11,100,controllerChannel);cc(e,55,64,127,controllerChannel);cc(e,55,74,100,controllerChannel);e.midi(55,uint8_t(0xd0|controllerChannel),100,0);
    note(e,55,60,100);
    std::vector<float> left(rate),right(rate);e.render(left.data(),right.data(),uint32_t(left.size()));
    for(size_t i=0;i<left.size();i++){assert(std::isfinite(left[i])&&std::isfinite(right[i]));assert(std::abs(left[i])<=1&&std::abs(right[i])<=1);}
    e.panic();assert(render(e)<1e-7f);
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
void benchmark() {
    SynthEngine e;e.prepare(44100);e.setGlobal(AGMaster,.25f);
    e.setGlobal(AGChorusMix,.4f);e.setGlobal(AGDelayMix,.3f);e.setGlobal(AGReverbMix,.3f);
    for(int l=0;l<4;l++) {
        e.setParameter(l,APEnabled,1);e.setParameter(l,APWave1,2);e.setParameter(l,APWave2,3);
        e.setParameter(l,APLFODepth,.3f);e.setParameter(l,APLFO2Depth,.1f);e.setParameter(l,APSustain,.8f);
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
    assert(e.activeVoices()==64);std::sort(durations.begin(),durations.end());double deadline=128.0/44100*1e6;
    std::printf("BENCHMARK: 30 s offline, 44.1 kHz/128, 64 voices + 4 FX + 30 matrix slots: %.3f s wall; p99 %.1f us (%.1f%% of %.1f us deadline), max %.1f us. Not a real-device underrun test.\n",
        elapsed,durations[size_t(durations.size()*.99)],100*durations[size_t(durations.size()*.99)]/deadline,deadline,durations.back());
}
}
int main() { matrices();lfoTwoShapes();scopeCapture();phaserEffect();globalTranspose();ownership();routingAndPrepare();arp();overflowAndConcurrent();extremesAndCapacity();benchmark();std::puts("All SynthEngine tests passed."); }
