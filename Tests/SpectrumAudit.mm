#import <Foundation/Foundation.h>
#include "PluginCore.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>
using namespace auroraPlugin;
struct Level {double energy=0,peak=0;size_t count=0;bool finite=true;double rms()const{return 10*std::log10(std::max(1e-15,energy/std::max(size_t(1),count)));}};
Level render(Core& c,double seconds,double skip=0){
    Level s;float l[256],r[256];int frames=int(seconds*48000),elapsed=0;
    while(elapsed<frames){int n=std::min(256,frames-elapsed);c.engine.render(l,r,n);for(int i=0;i<n;i++){
        s.finite&=std::isfinite(l[i])&&std::isfinite(r[i]);s.peak=std::max(s.peak,double(std::max(std::abs(l[i]),std::abs(r[i]))));
        if(elapsed+i>=skip*48000){s.energy+=double(l[i])*l[i]+double(r[i])*r[i];s.count+=2;}
    }elapsed+=n;}return s;
}
bool load(Core& c,NSDictionary* p){NSData* d=[NSJSONSerialization dataWithJSONObject:p options:0 error:nil];NSString* j=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];return c.setPatchJSON(j.UTF8String,true);}
std::vector<int> notes(NSString* category){if([category isEqualToString:@"Bass"])return {48};if([category isEqualToString:@"Leads"])return {64};if([category isEqualToString:@"Splits"])return {48,60,64};return {60,64,67};}
void play(Core& c,const std::vector<int>& keys,int velocity=104){for(int n:keys)c.midi(0x90,n,velocity);}
int main(int argc,char** argv){@autoreleasepool{
    bool calibrate=argc>1&&std::string(argv[1]).find("--calibrate")==0;
    bool plucksOnly=argc>1&&std::string(argv[1])=="--calibrate-plucks";
    NSData* data=[NSData dataWithContentsOfFile:@"Resources/AuroraSpectrum300.json"];
    NSArray* bank=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(bank.count!=300)return 2;
    NSMutableArray* results=[NSMutableArray array];NSMutableDictionary* trims=[NSMutableDictionary dictionary];int failed=0,index=0;
    if(plucksOnly){NSData* saved=[NSData dataWithContentsOfFile:@"Resources/SpectrumLevelTrims.json"];if(saved)[trims addEntriesFromDictionary:[NSJSONSerialization JSONObjectWithData:saved options:0 error:nil]];}
    for(NSDictionary* p in bank){@autoreleasepool{
        if(plucksOnly&&![p[@"category"] isEqualToString:@"Plucks"])continue;
        Core c;if(!load(c,p)){std::cerr<<"Rejected "<<[p[@"name"] UTF8String]<<"\n";return 3;}c.engine.prepare(48000);c.setActual(outputGainID,calibrate?0:24);
        NSString* category=p[@"category"];auto keys=notes(category);play(c,keys);
        Level main;
        if([category isEqualToString:@"Plucks"]){
            // Measure a played phrase, not the silent tail of a one-shot pluck.
            for(int strike=0;strike<8;strike++){
                if(strike)play(c,keys);auto attack=render(c,.3);
                for(int n:keys)c.midi(0x80,n,0);auto decay=render(c,.2);
                for(auto part:{attack,decay}){main.energy+=part.energy;main.count+=part.count;main.peak=std::max(main.peak,part.peak);main.finite&=part.finite;}
            }
        }else main=render(c,4,.6);
        double target=[category isEqualToString:@"Bass"]?-15:[category isEqualToString:@"Leads"]?-15:[category isEqualToString:@"Textures"]?-19:[category isEqualToString:@"Pads"]?-17:-16;
        NSMutableArray* issues=[NSMutableArray array];
        if(!main.finite||main.peak>1.001||main.rms()<-65)[issues addObject:@"Invalid/silent main output"];
        double peak=main.peak,maxMacroPeak=0;
        if(calibrate){
            double highest=0;for(NSDictionary* l in p[@"layers"])if([l[@"values"][@"0"] boolValue])highest=std::max(highest,[l[@"values"][@"13"] doubleValue]);
            double factor=std::pow(10.,(target-main.rms()-24)/20.);
            trims[p[@"id"]]=@(std::clamp(factor,.12,std::min(2.5,.98/std::max(.01,highest))));
        }else{
            for(int n:keys)c.midi(0x80,n,0);auto tail=render(c,5);peak=std::max(peak,tail.peak);
            if(!tail.finite||c.engine.activeVoices()!=0)[issues addObject:@"Invalid or stuck release"];
            c.engine.panic();auto panic=render(c,.02);if(panic.peak!=0)[issues addObject:@"Panic failed"];
            play(c,{36,48,55,60,64,67,72,84},127);auto stress=render(c,1.5);peak=std::max(peak,stress.peak);if(!stress.finite||stress.peak>.98001)[issues addObject:@"Invalid stress output"];
            for(int macro=0;macro<8;macro++)for(double value:{0.,1.}){
                if(!load(c,p))return 4;c.engine.panic();render(c,.01);c.setActual(macroBase+macro,value);play(c,keys);auto m=render(c,.5);maxMacroPeak=std::max(maxMacroPeak,m.peak);if(!m.finite||m.peak>.98001||m.peak<1e-7)[issues addObject:@"Invalid macro endpoint output"];
            }
            if(main.rms()<-29)[issues addObject:@"Patch too quiet at calibrated level"];
            if(main.rms()>-8)[issues addObject:@"Patch too loud at calibrated level"];
        }
        if(issues.count){failed++;std::cerr<<[p[@"name"] UTF8String]<<": "<<[[issues description] UTF8String]<<"\n";}
        [results addObject:@{@"id":p[@"id"],@"name":p[@"name"],@"category":category,@"rmsDBFS":@(main.rms()),@"peak":@(peak),@"macroPeak":@(maxMacroPeak),@"issues":issues}];
        if(++index%25==0)std::cout<<(calibrate?"Calibrated ":"Audited ")<<index<<"/300; "<<failed<<" issues"<<std::endl;
    }}
    NSString* path=calibrate?@"Resources/SpectrumLevelTrims.json":@"build/spectrum-audit.json";
    NSData* out=[NSJSONSerialization dataWithJSONObject:calibrate?(id)trims:(id)results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];if(![out writeToFile:path atomically:YES])return 5;
    if(calibrate){NSData* stats=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];[stats writeToFile:@"build/spectrum-calibration.json" atomically:YES];}
    std::cout<<(calibrate?"Calibration":"Full bank audit")<<" complete: "<<bank.count<<" sounds, "<<failed<<" issues\n";return failed?1:0;
}}
