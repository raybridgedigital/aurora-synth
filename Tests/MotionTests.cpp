#include "SynthEngine.hpp"
#include "MotionEnvelope.hpp"
#include <cassert>
#include <vector>
#include <thread>
#include <atomic>
#include <cstdio>
using aurora::SynthEngine;
using aurora::MotionEnvelope;
MotionEnvelope setting(int destination=0){
    MotionEnvelope m;m.data[0]=1;m.data[2]=.2f;m.data[3]=2;m.data[4]=0;m.data[5]=0;m.data[7]=1;m.data[8]=1;
    for(int i=0;i<8;i++){int b=52+i*4;m.data[b]=i==destination;m.data[b+1]=i==1?300:i==2?-12:i==3?-1:0;m.data[b+2]=i==1?8000:i==2?12:1;}
    return m;
}
void configure(SynthEngine& e){
    e.prepare(48000);for(int g:{AGDelayMix,AGReverbMix,AGChorusMix,AGPhaserMix})e.setGlobal(g,0);
    for(int p:{APSub,APNoise,APLFODepth,APLFO2Depth,APDrive,APFilterEnvelope,APBlend,APResonance})e.setParameter(0,p,0);
    e.setParameter(0,APWave1,0);e.setParameter(0,APSustain,1);e.setParameter(0,APAttack,.001);e.setParameter(0,APCutoff,18000);e.setParameter(0,APRelease,.04);
}
std::vector<float> render(SynthEngine& e,int n){
    std::vector<float> audio(n);float l[128],r[128];for(int start=0;start<n;start+=128){int count=std::min(128,n-start);e.render(l,r,count);for(int i=0;i<count;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i])&&std::abs(l[i])<=1&&std::abs(r[i])<=1);audio[start+i]=l[i]+r[i];}}return audio;
}
double rms(const std::vector<float>& a,int start,int n){double sum=0;for(int i=start;i<start+n;i++)sum+=a[i]*a[i];return sqrt(sum/n);}
void publish(SynthEngine& e,const MotionEnvelope& m){assert(e.setMotion(0,m.data.data(),int(m.data.size())));}
int main(){
    auto shape=setting();assert(MotionEnvelope::valid(shape.data.data(),84));
    assert(shape.shape(0)==0&&shape.shape(1)==1&&std::abs(shape.shape(.5)-.5)<1e-6);
    shape.data[53]=.3;assert(std::abs(shape.value(0,.5)-.65)<1e-6);shape.data[55]=1;assert(std::abs(shape.value(0,0)-1)<1e-6);
    shape.data[6]=1;assert(shape.shape(.5)<.01);shape.data[6]=-1;assert(shape.shape(.5)>.9);
    auto bad=shape;bad.data[7]=0;assert(!MotionEnvelope::valid(bad.data.data(),84));bad=shape;bad.data[2]=0;assert(!MotionEnvelope::valid(bad.data.data(),84));bad=shape;bad.data[53]=2;assert(!MotionEnvelope::valid(bad.data.data(),84));
    SynthEngine e;configure(e);shape=setting();publish(e,shape);e.midi(1,0x90,69,100);auto swell=render(e,19200);
    assert(rms(swell,1200,1200)<rms(swell,12000,1200)*.3);assert(e.motionPhase(0)==1);
    e.midi(1,0x80,69,0);render(e,4800);assert(e.activeVoices()==0&&e.motionPhase(0)==-1);
    configure(e);shape.data[53]=.4;publish(e,shape);e.midi(1,0x90,69,100);auto floor=render(e,19200);
    assert(rms(floor,1200,1200)>rms(swell,1200,1200)*2);
    configure(e);shape=setting();shape.data[1]=1;publish(e,shape);e.midi(1,0x90,69,100);render(e,12000);assert(std::abs(e.motionPhase(0)-.25)<.001);
    e.midi(1,0x90,72,100);render(e,2400);assert(e.activeVoices()==2&&std::abs(e.motionPhase(0)-.25)<.001);
    e.panic();render(e, int(48000*0.40));assert(e.activeVoices()==0&&e.motionPhase(0)==-1);
    puts("PASS: curve interpolation/bending, floor scaling/inversion, slow volume swell, nonzero starting volume, release, loop, polyphonic retrigger and Panic.");
    for(int destination=0;destination<8;destination++){
        SynthEngine dry,wet;configure(dry);configure(wet);
        for(auto* engine:{&dry,&wet}){engine->setParameter(0,APWT1Enabled,1);engine->setParameter(0,APWT2Enabled,1);engine->setParameter(0,APWT1Table,12);engine->setParameter(0,APWT2Table,8);engine->setParameter(0,APWT1WarpMode,3);engine->setParameter(0,APWT2WarpMode,1);engine->setParameter(0,APBlend,.5);}
        shape=setting(destination);publish(wet,shape);dry.midi(1,0x90,60,100);wet.midi(1,0x90,60,100);
        auto a=render(dry,12000),b=render(wet,12000);double difference=0;for(int i=0;i<12000;i++)difference+=std::abs(a[i]-b[i]);assert(difference>.01);
    }
    SynthEngine legacy,disabled;configure(legacy);configure(disabled);shape=setting();shape.data[0]=0;publish(disabled,shape);legacy.midi(1,0x90,60,100);disabled.midi(1,0x90,60,100);assert(render(legacy,12000)==render(disabled,12000));
    // An enabled envelope on B must not alter a voice routed exclusively to A.
    configure(legacy);configure(disabled);shape=setting();assert(disabled.setMotion(1,shape.data.data(),84));legacy.midi(1,0x90,60,100);disabled.midi(1,0x90,60,100);assert(render(legacy,12000)==render(disabled,12000));
    puts("PASS: all eight destinations alter rendered audio; disabled envelopes preserve exact legacy output; layer isolation.");
    for(int mode:{1,2}){
        configure(e);e.setParameter(0,APVoiceMode,float(mode));shape=setting();shape.data[2]=1;publish(e,shape);
        e.midi(1,0x90,60,100);render(e,4800);e.midi(1,0x90,64,100);render(e,2400);
        assert(std::abs(e.motionPhase(0)-(mode==1?.05f:.15f))<.001);
    }
    configure(e);e.setParameter(0,APVoiceMode,0);e.setParameter(0,APSustain,0);e.setParameter(0,APDecay,.001);
    shape=setting();shape.data[53]=1;publish(e,shape);e.midi(1,0x90,60,100);render(e,12000);
    e.midi(1,0x80,60,0);auto tail=render(e,480);assert(rms(tail,0,480)>.0001);
    render(e,4800);assert(e.activeVoices()==0);
    puts("PASS: mono retriggers, legato continues, and custom volume releases correctly even with ADSR sustain at zero.");
    configure(e);shape=setting();shape.data[84]=2;publish(e,shape);e.setGlobal(AGTempo,120);
    e.midi(1,0x90,60,100);render(e,12000);assert(std::abs(e.motionPhase(0)-.25)<.001);
    e.setGlobal(AGTempo,60);render(e,12000);assert(std::abs(e.motionPhase(0)-.375)<.001);
    auto invalidBeat=shape;invalidBeat.data[84]=-1;assert(!e.setMotion(0,invalidBeat.data.data(),85));
    puts("PASS: beat-synced envelope duration follows tempo changes without resetting phase; invalid beat lengths rejected.");
    configure(e);shape=setting();publish(e,shape);e.midi(1,0x90,60,100);
    std::atomic<bool> done=false;std::thread audio([&]{while(!done)render(e,128);});
    for(int i=0;i<10000;i++){shape.data[2]=.1f+float(i%100)*.1f;shape.data[53]=float(i%10)*.05f;publish(e,shape);}done=true;audio.join();
    puts("PASS: concurrent complete-configuration publication remains finite without render locks.");
}
