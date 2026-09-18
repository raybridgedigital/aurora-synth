#import <Foundation/Foundation.h>
#include "PluginCore.hpp"
#include <cmath>
#include <iostream>
#include <cassert>
using namespace auroraPlugin;
int main(){@autoreleasepool{
 NSData* data=[NSData dataWithContentsOfFile:@"Resources/AuroraReference.json"];
 NSArray* bank=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];assert(bank.count==2);
 for(NSDictionary* p in bank)for(int chord:{1,3}){
  Core c;NSData* d=[NSJSONSerialization dataWithJSONObject:p options:0 error:nil];NSString* j=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];assert(c.setPatchJSON(j.UTF8String,true));c.engine.prepare(48000);c.setActual(outputGainID,24);
  for(int n=0;n<chord;n++)c.midi(0x90,60+n*4,110);
  double energy=0,peak=0;float l[256],r[256];int count=0;
  for(int b=0;b<750;b++){c.engine.render(l,r,256);if(b>90)for(int i=0;i<256;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));peak=std::max(peak,double(std::max(std::abs(l[i]),std::abs(r[i]))));energy+=l[i]*l[i]+r[i]*r[i];count+=2;}}
  double rms=10*log10(energy/count);std::cout<<[p[@"name"] UTF8String]<<" "<<chord<<" notes: RMS "<<rms<<" dBFS, peak "<<20*log10(peak)<<" dBFS\n";
  assert(peak<=.98001);assert(rms>-19&&rms<-5);
 }
}}
