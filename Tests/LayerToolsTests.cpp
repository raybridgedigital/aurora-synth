#include "SynthEngine.hpp"
#include <vector>
#include <cassert>
#include <cmath>
#include <cstdio>
using aurora::SynthEngine;
double render(SynthEngine& e,int samples){std::vector<float> l(samples),r(samples);e.render(l.data(),r.data(),samples);double energy=0;for(int i=0;i<samples;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));energy+=l[i]*l[i]+r[i]*r[i];}return energy;}
void setup(SynthEngine& e){
    e.setGlobal(AGChorusMix,0);e.setGlobal(AGPhaserMix,0);e.setGlobal(AGDelayMix,.6);e.setGlobal(AGReverbMix,.6);e.setGlobal(AGDelayFeedback,.4);
    for(int i=0;i<2;i++){e.setParameter(i,APEnabled,1);e.setParameter(i,APRelease,.005);e.setParameter(i,APAttack,.001);e.setParameter(i,APSustain,1);e.setParameter(i,APNoise,0);}
    e.route(1,1,0);e.route(2,2,0);e.prepare(48000);
}
double tail(int source,float delay,float reverb){SynthEngine e;setup(e);e.setLayerSends(0,0,0,0);e.setLayerSends(1,delay,reverb,reverb);e.prepare(48000);e.midi(source,0x90,60,100);render(e,6000);e.midi(source,0x80,60,0);render(e,2400);return render(e,48000);}
int main(){
    assert(tail(1,1,1)<1e-8);assert(tail(2,0,0)<1e-8);assert(tail(2,1,0)>.001);assert(tail(2,0,1)>.001);
    SynthEngine e;setup(e);e.setGlobal(AGDelayMix,0);e.setGlobal(AGReverbMix,0);e.midi(1,0x90,60,100);assert(render(e,4800)>.001);
    e.soloLayer(1);render(e,12000);assert(render(e,2400)<1e-8);assert(e.activeVoices()==1);
    e.soloLayer(-1);assert(render(e,4800)>.001);assert(e.activeVoices()==1);
    e.midi(1,0x80,60,0);render(e,4800);assert(e.activeVoices()==0);
    puts("PASS: dry layer never feeds shared Delay/Reverb, sends act independently, Solo preserves held notes and un-Solo restores them.");
}
