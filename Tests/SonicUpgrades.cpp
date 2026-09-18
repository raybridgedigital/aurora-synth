#include "SynthEngine.hpp"
#include <cassert>
#include <cmath>
#include <fstream>
#include <iostream>
#include <vector>
#include <algorithm>
using aurora::SynthEngine;
void setup(SynthEngine& e){
    e.prepare(48000);e.setGlobal(AGMaster,.7);e.setGlobal(AGDelayMix,0);e.setGlobal(AGReverbMix,0);e.setGlobal(AGChorusMix,0);
    e.setParameter(0,APAttack,.002);e.setParameter(0,APSustain,.8);e.setParameter(0,APRelease,.2);
    e.setParameter(0,APFilterEnvelope,0);e.setParameter(0,APCutoff,4500);e.setParameter(0,APDrive,0);
    e.setParameter(0,APLFODepth,0);e.setParameter(0,APLFO2Depth,0);e.setParameter(0,APBlend,.2);
}
std::vector<float> render(SynthEngine& e,int note=60){
    e.midi(0,0x90,note,100);std::vector<float> out;float l[256],r[256];
    for(int b=0;b<160;b++){if(b==120)e.midi(0,0x80,note,0);e.render(l,r,256);for(int i=0;i<256;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));assert(std::abs(l[i])<=1.001&&std::abs(r[i])<=1.001);out.push_back(l[i]);}}
    return out;
}
double energy(const std::vector<float>& v){double sum=0;for(auto x:v)sum+=x*x;return sum/v.size();}
double difference(const std::vector<float>& a,const std::vector<float>& b){double sum=0;for(size_t i=0;i<a.size();i++)sum+=std::abs(a[i]-b[i]);return sum/a.size();}
int main(int argc,char** argv){
    SynthEngine base;setup(base);auto dry=render(base);assert(energy(dry)>1e-7);
    if(argc>1){std::ofstream file(argv[1],std::ios::binary);file.write((const char*)dry.data(),dry.size()*sizeof(float));return 0;}
    SynthEngine bypass;setup(bypass);bypass.setParameter(0,APFilter2Cutoff,30);bypass.setParameter(0,APModAmount,0);bypass.setParameter(0,APOscModAmount,1);bypass.setParameter(0,APCharacterDrive,1);
    assert(difference(dry,render(bypass))==0);
    std::vector<std::vector<float>> filters;
    for(int route=0;route<3;route++){
        SynthEngine e;setup(e);e.setParameter(0,APFilter2Enabled,1);e.setParameter(0,APFilter2Type,1);e.setParameter(0,APFilter2Cutoff,900);e.setParameter(0,APFilterRouting,route);filters.push_back(render(e));assert(difference(dry,filters.back())>1e-4);
    }
    // Linear serial filters commute; parallel must differ from their cascade.
    assert(difference(filters[0],filters[2])>1e-4);
    for(int wavetable=0;wavetable<2;wavetable++)for(int mode=1;mode<=3;mode++){
        SynthEngine e;setup(e);e.setParameter(0,APWT1Enabled,wavetable);e.setParameter(0,APWT2Enabled,wavetable);e.setParameter(0,APOscModMode,mode);e.setParameter(0,APOscModAmount,.65);e.setParameter(0,APOscModRatio,2.3);
        assert(difference(dry,render(e))>1e-4);
    }
    for(int mode=1;mode<=4;mode++){
        SynthEngine e;setup(e);e.setParameter(0,APCharacterMode,mode);e.setParameter(0,APCharacterDrive,.65);e.setParameter(0,APCharacterRate,.1);e.setParameter(0,APCharacterBits,5);assert(difference(dry,render(e))>1e-4);
    }
    SynthEngine envelope;setup(envelope);envelope.setParameter(0,APModAttack,.5);envelope.setParameter(0,APModSustain,.3);envelope.setMatrix(0,0,true,3,0,0,1,-.8);assert(difference(dry,render(envelope))>1e-4);
    SynthEngine boost;setup(boost);boost.setGlobal(AGOutputGain,6);auto louder=render(boost);double gain=std::sqrt(energy(louder)/energy(dry));assert(gain>1.9&&gain<2.01);
    std::cout<<"Reference RMS "<<20*std::log10(std::sqrt(energy(dry)))<<" dBFS; +6 dB boost measured "<<20*std::log10(gain)<<" dB\n";
    SynthEngine loud;setup(loud);loud.setGlobal(AGMaster,1);loud.setGlobal(AGOutputGain,18);
    for(int l=0;l<4;l++){loud.setParameter(l,APEnabled,1);loud.setParameter(l,APLevel,1);loud.setParameter(l,APCharacterMode,2);loud.setParameter(l,APCharacterDrive,1);loud.setParameter(l,APUnison,4);}
    loud.route(0,15,0);for(int n=40;n<56;n++)loud.midi(0,0x90,n,127);auto limited=render(loud);assert(*std::max_element(limited.begin(),limited.end())<=.98001);
    for(int note:{24,72,120})for(int mode=1;mode<=3;mode++){
        SynthEngine e;setup(e);e.setParameter(0,APOscModMode,mode);e.setParameter(0,APOscModAmount,1);e.setParameter(0,APOscModRatio,8);e.setParameter(0,APFilter2Enabled,1);e.setParameter(0,APFilter2Resonance,.9);e.setParameter(0,APFilter2Cutoff,18000);e.setParameter(0,APCharacterMode,3);e.setParameter(0,APCharacterDrive,1);render(e,note);
    }
    std::cout<<"PASS: bypass, dual filters, classic/wavetable modulation, character, mod envelope, gain and extreme-setting stability\n";
}
