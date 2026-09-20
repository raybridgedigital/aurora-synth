#include "SynthEngine.hpp"
#include "Wavetable.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
using aurora::SynthEngine;
void setup(SynthEngine& e){e.prepare(48000);e.setGlobal(AGMaster,.8);for(int p:{AGDelayMix,AGReverbMix,AGChorusMix,AGPhaserMix})e.setGlobal(p,0);for(int p:{APLFODepth,APLFO2Depth,APFilterEnvelope,APNoise,APDrive})e.setParameter(0,p,0);e.setParameter(0,APCutoff,1400);e.setParameter(0,APSustain,1);e.setParameter(0,APAttack,.001);}
std::vector<float> render(SynthEngine& e,int frames){std::vector<float> l(frames),r(frames);e.render(l.data(),r.data(),frames);for(int i=0;i<frames;i++)assert(std::isfinite(l[i])&&std::isfinite(r[i])&&std::abs(l[i])<=1&&std::abs(r[i])<=1);return l;}
void drainPanic(SynthEngine& e){e.panic();render(e,int(48000*.45));}
float feedback(SynthEngine& e){float f[30];e.copyModulation(f,30);return f[0];}
double energy(const std::vector<float>& a){double v=0;for(auto x:a)v+=x*x;return v/a.size();}
int main(){
 for(int o=0;o<2;o++){
  SynthEngine e;setup(e);int base=APLFO1Sync+o*6;e.setGlobal(AGTempo,120);e.setParameter(0,base,1);e.setParameter(0,base+1,4);e.setParameter(0,base+2,1);e.setMatrix(0,0,true,o,2,0,1,1);e.midi(0,0x90,60,100);
  render(e,6001);assert(feedback(e)>.99f); // 1/4 cycle at 120 BPM / quarter note
  e.midi(0,0x90,64,100);render(e,1);assert(std::abs(feedback(e))<.002f);
  render(e,6000);assert(feedback(e)>.99f); // new note retriggered
  drainPanic(e); // mute-bus fade + wipe before next notes/params
  e.setParameter(0,base+4,.2);e.setParameter(0,base+5,.4);e.setParameter(0,base+3,.25);e.midi(0,0x90,60,100);render(e,9000);assert(std::abs(feedback(e))<.001f);render(e,1200);assert(std::abs(feedback(e))<.04f);
  drainPanic(e); // mute-bus fade + wipe before free-run check
  e.setParameter(0,base+4,0);e.setParameter(0,base+5,0);e.setParameter(0,base+2,0);e.setParameter(0,base+3,0);render(e,2345);e.midi(0,0x90,60,100);render(e,1);float before=feedback(e);e.midi(0,0x90,67,100);render(e,1);assert(std::abs(feedback(e)-before)<.002f);
 }
 for(int source:{4,5}){
  SynthEngine e;setup(e);e.setMatrix(0,0,true,source,2,0,1,1);e.midi(0,0x90,72,100);render(e,400);float a=feedback(e);render(e,700);assert(feedback(e)==a);if(source==4)assert(std::abs(a-.2f)<.0001f);else{e.midi(0,0x90,72,100);render(e,1);assert(feedback(e)!=a);}
 }
 double slopeEnergy[2];for(int slope=0;slope<2;slope++){SynthEngine e;setup(e);e.setParameter(0,APWave1,0);e.setParameter(0,APBlend,0);e.setParameter(0,APSub,0);e.setParameter(0,APCutoff,300);e.setParameter(0,APFilter1Slope,slope);e.midi(0,0x90,84,100);render(e,2000);slopeEnergy[slope]=energy(render(e,12000));}assert(slopeEnergy[1]<slopeEnergy[0]*.2);
 for(int type=0;type<4;type++)for(int route=0;route<3;route++){SynthEngine e;setup(e);e.setParameter(0,APFilterType,type);e.setParameter(0,APFilter2Enabled,1);e.setParameter(0,APFilter2Type,type);e.setParameter(0,APFilter1Slope,1);e.setParameter(0,APFilter2Slope,1);e.setParameter(0,APFilterRouting,route);e.setParameter(0,APUnison,8);for(int key:{48,60,64,67})e.midi(0,0x90,key,110);assert(energy(render(e,8000))>1e-10);}
 {SynthEngine e;setup(e);e.setParameter(0,APUnison,4);for(int n=24;n<88;n++)e.midi(0,0x90,n,100);render(e,256);assert(e.activeVoices()==64);e.setParameter(0,APUnison,8);render(e,256);assert(e.activeVoices()==32);for(int n=24;n<88;n++)e.midi(0,0x90,n,100);render(e,256);assert(e.activeVoices()==32);}
 auto& bank=*aurora::wt::factory()[4];double diff[4]={};for(int i=0;i<1024;i++){float p=i/1024.f;float dry=bank.sample(p,.001f,.5f,0,0);float v[]={bank.sample(p,.001f,.5f,4,.7f),bank.sample(p,.001f,.5f,5,.9f),bank.shapedSample(p,.001f,.5f,0,0,.3f,0),bank.shapedSample(p,.001f,.5f,0,0,0,.6f)};for(int j=0;j<4;j++){assert(std::isfinite(v[j]));diff[j]+=std::abs(v[j]-dry);}}
 for(double d:diff)assert(d>1);
 std::cout<<"PASS: both LFO clocks/retrigger/free-run/phase/delay/fade, stable per-note sources, 24 dB attenuation, all filter routes with eight unison voices, Mirror/Quant/Formant/Tone audio changes\n";
}
