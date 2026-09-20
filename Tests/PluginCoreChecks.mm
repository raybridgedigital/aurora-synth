#import <Foundation/Foundation.h>
#include "PluginCore.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <algorithm>
using namespace auroraPlugin;
static std::string json(id object){NSData* data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];return std::string((const char*)data.bytes,data.length);}
static void finishPanic(Core& c){
    constexpr int total=int(48000*.45);
    float l[256],r[256];
    for(int remaining=total;remaining>0;remaining-=256)c.engine.render(l,r,std::min(remaining,256));
}
static void panicAndDrain(Core& c){c.engine.panic();finishPanic(c);}
int main(){@autoreleasepool {
    Core a,b;int tested=0;
    assert(a.values[outputGainID]==9);
    static_assert(layerID(3,57)==231 && layerID(0,58)==6000 && layerID(3,78)==6404);
    for(NSString* file in @[@"Aurora100",@"AuroraPrism100",@"AuroraNova100",@"AuroraReference"]){
        NSData* data=[NSData dataWithContentsOfFile:[NSString stringWithFormat:@"Resources/%@.json",file]];
        NSArray* bank=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];assert(bank.count==([file isEqualToString:@"AuroraReference"]?2:100));
        for(NSDictionary* patch in bank){
            if(!a.setPatchJSON(json(patch).c_str(),true)){std::cerr<<"Rejected patch: "<<[patch[@"name"] UTF8String]<<std::endl;return 1;}
            a.setActual(transposeID,3);a.setActual(2000,.71);a.setActual(xyX,.23);a.setActual(xyY,.82);
            auto state=a.saveState();assert(b.restoreState(state.c_str()));
            assert(a.patchJSON()==b.patchJSON());assert(b.values[transposeID]==3);
            a.engine.prepare(48000);b.engine.prepare(48000);
            finishPanic(a);finishPanic(b);
            a.midi(0x90,60,100);b.midi(0x90,60,100);
            float l[256],r[256],bl[256],br[256];double energy=0;
            for(int block=0;block<100;block++){
                a.engine.render(l,r,256);b.engine.render(bl,br,256);
                for(int i=0;i<256;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));energy+=l[i]*l[i]+r[i]*r[i];}
            }
            assert(energy>0);panicAndDrain(a);panicAndDrain(b);
            float previous=b.values[7];a.setActual(7,4321);assert(b.values[7]==previous);
            auto unchanged=b.saveState();assert(!b.restoreState("{}"));assert(b.saveState()==unchanged);
            NSMutableDictionary* malformed=[patch mutableCopy];malformed[@"layers"]=@[@{},@{},@{},@{}];
            assert(!b.setPatchJSON(json(malformed).c_str(),true));assert(b.saveState()==unchanged);
            malformed=[patch mutableCopy];malformed[@"motion"]=@[@{},@{},@{},@{}];
            assert(!b.setPatchJSON(json(malformed).c_str(),true));assert(b.saveState()==unchanged);
            ++tested;
        }
    }
    const char* mappings=R"({"mappings":[{"source":1,"channel":1,"controller":20,"macro":0}],"directMappings":[]})";
    assert(a.setMappingsJSON(mappings));a.setActual(2000,.5);a.midi(0xb0,20,10);assert(std::abs(a.normalized(2000)-.5)<1e-5);
    a.midi(0xb0,20,64);a.midi(0xb0,20,100);assert(std::abs(a.normalized(2000)-100./127)<1e-5);
    auto mappedState=a.saveState();assert(b.restoreState(mappedState.c_str()));assert(a.mappingsJSON()==b.mappingsJSON());
    b.midi(0xb0,20,100);b.midi(0xb0,20,110);assert(std::abs(b.normalized(2000)-110./127)<1e-5);
    std::cout<<"Closed-editor MIDI Learn, soft pickup and project recall passed\n";
    for(int l=0;l<4;l++)for(int p=58;p<APParameterCount;p++)a.setNormalized(layerID(l,p),.65);
    a.setActual(outputGainID,12);
    auto extended=a.saveState();assert(b.restoreState(extended.c_str()));
    for(int l=0;l<4;l++)for(int p=58;p<APParameterCount;p++)assert(a.values[layerID(l,p)]==b.values[layerID(l,p)]);
    assert(b.values[outputGainID]==12);
    const char* direct=R"({"mappings":[],"directMappings":[{"source":1,"channel":1,"controller":21,"target":{"layer":3,"parameter":71}}]})";
    assert(b.setMappingsJSON(direct));b.setActual(layerID(3,71),.5);b.midi(0xb0,21,64);b.midi(0xb0,21,110);assert(std::abs(b.normalized(layerID(3,71))-110./127)<1e-5);
    // A pre-upgrade DAW state has no boost and no added layer values.
    NSMutableDictionary* legacy=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:extended.data() length:extended.size()] options:NSJSONReadingMutableContainers error:nil];
    [legacy removeObjectForKey:@"outputGain"];[legacy removeObjectForKey:@"outputGainRevision"];
    for(NSMutableDictionary* layer in legacy[@"patch"][@"layers"])for(int p=58;p<APParameterCount;p++)[layer[@"values"] removeObjectForKey:[NSString stringWithFormat:@"%d",p]];
    assert(b.restoreState(json(legacy).c_str()));assert(b.values[outputGainID]==9);
    for(int l=0;l<4;l++){assert(b.values[layerID(l,58)]==0);assert(b.values[layerID(l,68)]==0);assert(b.values[layerID(l,70)]==0);assert(b.values[layerID(l,73)]==0);assert(b.values[layerID(l,60)]==3200);}
    std::cout<<"Extended layer automation/state, layer D MIDI Learn and legacy project defaults passed\n";
    std::cout<<tested<<" factory patches: host state round-trip, finite audio, XY/macros and instance isolation passed\n";
}}
