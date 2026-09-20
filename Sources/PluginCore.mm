#import <Foundation/Foundation.h>
#include "PluginCore.hpp"
#include "MotionEnvelope.hpp"
#include <algorithm>
#include <cmath>
#include <mutex>
#include <dlfcn.h>
namespace auroraPlugin {
struct Core::Storage {std::recursive_mutex mutex;NSMutableDictionary* patch;NSDictionary* mappings;};
static NSString* key(int p){return [NSString stringWithFormat:@"%d",p];}
static bool dictionary(id value){return [value isKindOfClass:NSDictionary.class];}
static bool number(id value){return [value isKindOfClass:NSNumber.class]&&std::isfinite([value doubleValue]);}
static bool numericFields(id value,NSArray* names){if(!dictionary(value))return false;for(NSString* name in names)if(!number(value[name]))return false;return true;}
static bool arraySize(id value,NSUInteger count){return [value isKindOfClass:NSArray.class]&&[value count]==count;}
static void removeNullProperties(id value){
    if([value isKindOfClass:NSMutableDictionary.class])for(id k in [value allKeys]){if(value[k]==NSNull.null)[value removeObjectForKey:k];else removeNullProperties(value[k]);}
    else if([value isKindOfClass:NSArray.class])for(id item in value)removeNullProperties(item);
}
static bool numericDictionary(id value){if(!dictionary(value))return false;for(id k in value)if(!number(value[k]))return false;return true;}
static bool motionPacket(NSDictionary* m,float* packet){
    std::fill(packet,packet+85,0);packet[2]=4;packet[3]=2;packet[7]=1;packet[8]=1;packet[57]=400;packet[58]=6000;
    if(!m)return true;
    if(!numericFields(m,@[@"enabled",@"loop",@"seconds"])||![m[@"points"] isKindOfClass:NSArray.class]||!arraySize(m[@"routes"],8))return false;
    NSArray* points=m[@"points"],*routes=m[@"routes"];if(points.count<2||points.count>16)return false;
    packet[0]=[m[@"enabled"] floatValue];packet[1]=[m[@"loop"] floatValue];packet[2]=[m[@"seconds"] floatValue];packet[3]=points.count;
    for(NSUInteger i=0;i<points.count;i++){if(!numericFields(points[i],@[@"x",@"y",@"curve"]))return false;packet[4+i*3]=[points[i][@"x"] floatValue];packet[5+i*3]=[points[i][@"y"] floatValue];packet[6+i*3]=[points[i][@"curve"] floatValue];}
    for(int i=0;i<8;i++){if(!numericFields(routes[i],@[@"enabled",@"minimum",@"maximum",@"inverted"]))return false;packet[52+i*4]=[routes[i][@"enabled"] floatValue];packet[53+i*4]=[routes[i][@"minimum"] floatValue];packet[54+i*4]=[routes[i][@"maximum"] floatValue];packet[55+i*4]=[routes[i][@"inverted"] floatValue];}
    if(m[@"beats"]){if(!number(m[@"beats"]))return false;packet[84]=[m[@"beats"] floatValue];}
    return aurora::MotionEnvelope::valid(packet,85);
}
static bool validPatch(NSDictionary* p){
    for(NSString* name in @[@"id",@"name",@"category",@"detail"])if(![p[name] isKindOfClass:NSString.class])return false;
    if(!arraySize(p[@"layers"],4)||!arraySize(p[@"globals"],6)||!arraySize(p[@"macros"],8))return false;
    for(id layer in p[@"layers"])if(!dictionary(layer)||!numericDictionary(layer[@"values"]))return false;
    for(id v in p[@"globals"])if(!number(v))return false;
    for(id v in p[@"macros"])if(!number(v))return false;
    if(p[@"fx"]&&!numericDictionary(p[@"fx"]))return false;
    if(p[@"phaserMix"]&&!number(p[@"phaserMix"]))return false;
    if(p[@"sends"]){if(!arraySize(p[@"sends"],4))return false;for(id s in p[@"sends"])if(!numericFields(s,@[@"delay",@"reverb"]))return false;}
    if(p[@"motion"]){if(!arraySize(p[@"motion"],4))return false;for(id m in p[@"motion"]){float packet[85];if(!motionPacket(m,packet))return false;}}
    if(p[@"soundMatrix"]&&!arraySize(p[@"soundMatrix"],4))return false;
    for(int b=0;b<5;b++){id rows=b==4?p[@"performanceMatrix"]:p[@"soundMatrix"]?p[@"soundMatrix"][b]:nil;if(rows){if(!arraySize(rows,6))return false;for(id row in rows)if(!numericFields(row,@[@"enabled",@"source",@"destination",@"target",@"cc",@"amount"]))return false;}}
    if(p[@"xy"]){if(!dictionary(p[@"xy"]))return false;for(NSString* axis in @[@"x",@"y"])if(!numericFields(p[@"xy"][axis],@[@"macro",@"start",@"end"]))return false;}
    if(p[@"customMacros"]){if(!dictionary(p[@"customMacros"]))return false;for(id k in p[@"customMacros"]){id m=p[@"customMacros"][k];if(!dictionary(m)||![m[@"routes"] isKindOfClass:NSArray.class]||[m[@"routes"] count]>16)return false;for(id row in m[@"routes"])if(!numericFields(row,@[@"from",@"to"])||!numericFields(row[@"target"],@[@"layer",@"parameter"]))return false;}}
    if(p[@"importedWavetables"]){if(!dictionary(p[@"importedWavetables"]))return false;for(id k in p[@"importedWavetables"]){id w=p[@"importedWavetables"][k];if(!dictionary(w)||!number(w[@"frameSize"])||![w[@"data"] isKindOfClass:NSString.class])return false;int size=[w[@"frameSize"] intValue];if(!(size==256||size==512||size==1024||size==2048))return false;NSData* bytes=[[NSData alloc] initWithBase64EncodedString:w[@"data"] options:0];if(!bytes||bytes.length<size*4||bytes.length>64*size*4||bytes.length%(size*4))return false;const float* samples=(const float*)bytes.bytes;for(NSUInteger i=0;i<bytes.length/4;i++)if(!std::isfinite(samples[i]))return false;}}
    return true;
}
static NSMutableDictionary* clone(NSDictionary* dictionary){
    if(!dictionary)return [NSMutableDictionary dictionary];
    NSData* data=[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    return data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:[NSMutableDictionary dictionary];
}
std::string Core::resourceDirectory(){Dl_info info{};dladdr((void*)&key,&info);NSString* path=@(info.dli_fname?:"");return [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Resources"].UTF8String;}
Core::Core():storage(std::make_unique<Storage>()){
    @autoreleasepool {
        storage->patch=[NSMutableDictionary dictionary];
        storage->mappings=@{@"mappings":@[],@"directMappings":@[]};for(auto& target:learnedTargets)target=-1;
        values[routeMaskID]=15;
        setActual(outputGainID,9);
        for(int ch=0;ch<16;ch++){values[midiBase+ch*130+7]=1;values[midiBase+ch*130+11]=1;values[midiBase+ch*130+129]=.5;}
        xyMacros[0]=0;xyMacros[1]=2;xyEnds[0]=xyEnds[1]=1;
        NSData* data=[NSData dataWithContentsOfFile:[@(resourceDirectory().c_str()) stringByAppendingPathComponent:@"Aurora100.json"]];
        NSArray* bank=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if(bank.count){NSData* patch=[NSJSONSerialization dataWithJSONObject:bank[0] options:0 error:nil];NSString* json=[[NSString alloc] initWithData:patch encoding:NSUTF8StringEncoding];setPatchJSON(json.UTF8String,true);}
        else {for(int l=0;l<4;l++)for(int p=0;p<APParameterCount;p++)setActual(layerID(l,p),p==0?(l==0):defaults[p]);for(int p=0;p<15;p++)setActual(globalBase+p,engine.getGlobal(p));}
        // Initial patch load advances the Panic event generation. Queue the
        // default MIDI routes afterwards so they cannot be discarded as stale.
        engine.route(0,15,0);engine.route(1,15,0);
    }
}
Core::~Core()=default;
Spec Core::spec(int id){
    if(parameterForID(id)>=0)return layers[parameterForID(id)];
    if(id>=globalBase&&id<globalBase+15)return globals[id-globalBase];
    if(id==transposeID)return {"Transpose",-24,24,false,true};
    if(id==outputGainID)return {"Output boost",0,24,false,false};
    if(id==holdID)return {"Hold",0,1,false,true};
    if(id==routeMaskID)return {"MIDI layer mask",0,15,false,true};
    if(id==routeChannelID)return {"MIDI channel",0,16,false,true};
    if(id==velocityID)return {"Velocity curve",0,3,false,true};
    return {"Performance",0,1,false,false};
}
double Core::actual(int id,double n){auto s=spec(id);n=std::isfinite(n)?std::clamp(n,0.,1.):0;double v=s.logarithmic?s.low*std::pow(s.high/s.low,n):s.low+(s.high-s.low)*n;return s.integer?std::round(v):v;}
double Core::normalize(int id,double value){auto s=spec(id);value=std::clamp(value,s.low,s.high);return s.logarithmic?std::log(value/s.low)/std::log(s.high/s.low):(value-s.low)/(s.high-s.low);}
double Core::normalized(int id)const{return id>=0&&id<8192?normalize(id,values[id].load()):0;}
void Core::prepare(double rate){
    sampleRate=rate;
    engine.prepare(rate);
    // Engine prepare is a hard audio reset. Re-publish the plug-in's persisted
    // DAW MIDI configuration so split patches still receive layers B/C/D.
    engine.route(1,int(values[routeMaskID].load()),int(values[routeChannelID].load()));
    engine.velocityCurve(1,int(values[velocityID].load()));
}
void Core::midi(int status,int a,int b){
    if((status&0xf0)==0xb0&&a>=0&&a<128&&b>=0&&b<128){
        lastCC=(uint64_t(1)<<32)|(uint64_t((status&15)+1)<<16)|(uint64_t(a)<<8)|uint64_t(b);++ccEvents;
        auto current=mappingRevision.load();if(current!=appliedMappingRevision){pickedUp.fill(false);previousCC.fill(-1);appliedMappingRevision=current;}
        int slot=(status&15)*128+a,target=learnedTargets[slot];float value=float(b)/127;
        if(target>=0){double expected=normalized(target);float previous=previousCC[slot];
            if(pickedUp[slot]||std::abs(value-expected)<.04||(previous>=0&&(previous-expected)*(value-expected)<=0)){pickedUp[slot]=true;setNormalized(target,value);}
            previousCC[slot]=value;
        }
    }
    engine.midi(1,uint8_t(status),uint8_t(a),uint8_t(b));++midiEvents;
}
std::string Core::mappingsJSON(){@autoreleasepool{std::lock_guard lock(storage->mutex);NSData* data=[NSJSONSerialization dataWithJSONObject:storage->mappings options:NSJSONWritingSortedKeys error:nil];return std::string((const char*)data.bytes,data.length);}}
bool Core::setMappingsJSON(const char* json,bool apply){@autoreleasepool{
    if(!json||strlen(json)>200000)return false;
    NSData* data=[NSData dataWithBytes:json length:strlen(json)];id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(!dictionary(object))return false;
    std::array<int,2048> targets;targets.fill(-1);
    for(NSString* name in @[@"mappings",@"directMappings"]){id rows=object[name];if(![rows isKindOfClass:NSArray.class]||[rows count]>256)return false;
        for(id row in rows){if(!numericFields(row,@[@"source",@"channel",@"controller"]))return false;
            int source=[row[@"source"] intValue],ch=[row[@"channel"] intValue],cc=[row[@"controller"] intValue],target=-1;
            if(source!=1||ch<1||ch>16||cc<0||cc>=120||cc==64)return false;
            if([name isEqualToString:@"mappings"]){if(!number(row[@"macro"]))return false;int m=[row[@"macro"] intValue];if(m<0||m>7)return false;target=macroBase+m;}
            else {if(!numericFields(row[@"target"],@[@"layer",@"parameter"]))return false;int l=[row[@"target"][@"layer"] intValue],p=[row[@"target"][@"parameter"] intValue];if(l < -1||l>3||p<0||p>=(l<0?15:APParameterCount))return false;target=l<0?globalBase+p:layerID(l,p);}
            targets[(ch-1)*128+cc]=target;
        }
    }
    if(!apply)return true;
    std::lock_guard lock(storage->mutex);storage->mappings=object;for(int i=0;i<2048;i++)learnedTargets[i]=targets[i];++mappingRevision;++revision;return true;
}}
void Core::setNormalized(int id,double v,bool ui){setActual(id,actual(id,v),ui);}
void Core::setActual(int id,double v,bool ui){
    if(id<0||id>=8192||!std::isfinite(v))return;
    auto s=spec(id);v=std::clamp(v,s.low,s.high);if(s.integer)v=std::round(v);
    values[id]=float(v);
    if(parameterForID(id)>=0)engine.setParameter(layerForID(id),parameterForID(id),float(v));
    else if(id>=globalBase&&id<globalBase+15){if(id!=globalBase+1||!active)engine.setGlobal(id-globalBase,float(v));}
    else if(id>=macroBase&&id<macroBase+8)macro(id-macroBase,v);
    else if(id==xyX||id==xyY){int axis=id-xyX;int m=xyMacros[axis];setActual(macroBase+m,xyStarts[axis]+(xyEnds[axis]-xyStarts[axis])*v);}
    else if(id==transposeID)engine.setTranspose(int(v));
    else if(id==outputGainID)engine.setGlobal(AGOutputGain,float(v));
    else if(id==holdID)engine.hold(v>.5);
    else if(id==routeMaskID||id==routeChannelID)engine.route(1,int(values[routeMaskID]),int(values[routeChannelID]));
    else if(id==velocityID)engine.velocityCurve(1,int(v));
    else if(isSendID(id)){int l=sendLayerForID(id);engine.setLayerSends(l,values[sendID(l,0)],values[sendID(l,1)],values[sendID(l,2)]);}
    else if(id>=midiBase&&id<midiBase+16*130){int ch=(id-midiBase)/130,cc=(id-midiBase)%130;
        if(cc==129){int bend=int(std::round(v*16383));midi(0xe0|ch,bend&127,bend>>7);}
        else if(cc==128)midi(0xd0|ch,int(v*127+.5),0);
        else midi(0xb0|ch,cc,int(v*127+.5));
    }
    ++revision;
    if(id>=macroBase&&id<macroBase+8)for(int axis=0;axis<2;axis++)if(xyMacros[axis]==id-macroBase){double start=xyStarts[axis],span=xyEnds[axis]-start;values[xyX+axis]=std::abs(span)<.000001?.5:std::clamp((v-start)/span,0.,1.);}
    if(ui&&notify)notify(id,normalized(id));
}
void Core::macro(int index,double value){
    int count=macroCounts[index];
    if(count>=0){for(int i=0;i<count;i++){auto& r=macroRoutes[index][i];int id=r.target;float a=r.from,b=r.to;if(id>=0)setNormalized(id,a+(b-a)*value);}return;}
    // Legacy presets use their existing relative performance macros.
    double previous=storageLegacy[index].exchange(value);
    double delta=value-previous;
    for(int l=0;l<4;l++){
        auto get=[&](int p){return double(values[layerID(l,p)]);};
        auto set=[&](int p,double v){setActual(layerID(l,p),v);};
        switch(index){case 0:set(7,get(7)*std::pow(2,delta*6));break;case 1:set(21,get(21)+delta*.65);break;case 2:set(17,get(17)+delta*.65);break;case 4:set(9,get(9)*std::pow(2,delta*8));break;case 5:set(12,get(12)*std::pow(2,delta*6));break;case 6:set(14,(l%2?1.:-1.)*value*.65);break;case 7:set(3,get(3)+delta);break;}
    }
    if(index==3){setActual(1004,values[1004]+delta*.7);setActual(1002,values[1002]+delta*.4);}
    if(index==6)setActual(1005,value*.4);
}
void Core::configureMetadata(){
    NSDictionary* p=storage->patch;
    for(int i=0;i<8;i++){
        NSDictionary* def=p[@"customMacros"][key(i)];NSArray* rows=def[@"routes"];
        macroCounts[i]=-1;
        for(NSUInteger r=0;r<std::min(NSUInteger(16),rows.count);r++){
            NSDictionary* item=rows[r];int l=[item[@"target"][@"layer"] intValue],par=[item[@"target"][@"parameter"] intValue];
            int target=l<0?globalBase+par:layerID(l,par);
            if(l < -1 || l>3 || par<0 || par>=(l<0?15:APParameterCount))target=-1;
            macroRoutes[i][r].target=target;macroRoutes[i][r].from=[item[@"from"] floatValue];macroRoutes[i][r].to=[item[@"to"] floatValue];
        }
        macroCounts[i]=def?int(std::min(NSUInteger(16),rows.count)):-1;
    }
    for(int i=0;i<2;i++){
        NSDictionary* axis=p[@"xy"][i?@"y":@"x"];
        xyMacros[i]=axis?std::clamp([axis[@"macro"] intValue],0,7):(i?2:0);
        xyStarts[i]=axis?[axis[@"start"] floatValue]:0;xyEnds[i]=axis?[axis[@"end"] floatValue]:1;
        double start=xyStarts[i],span=xyEnds[i]-start;
        values[xyX+i]=std::abs(span)<.000001?.5:std::clamp((values[macroBase+xyMacros[i]]-start)/span,0.,1.);
    }
}
bool Core::setPatchJSON(const char* json,bool apply){
    @autoreleasepool {
        if(!json || strlen(json)>12'000'000)return false;
        NSData* data=[NSData dataWithBytes:json length:strlen(json)];
        id decoded=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if(![decoded isKindOfClass:NSDictionary.class])return false;
        removeNullProperties(decoded);
        NSDictionary* p=decoded;
        if(!validPatch(p))return false;
        std::lock_guard lock(storage->mutex);storage->patch=clone(p);configureMetadata();
        if(apply){
            engine.panic();
            for(int l=0;l<4;l++)for(int i=0;i<APParameterCount;i++){id v=p[@"layers"][l][@"values"][key(i)];setActual(layerID(l,i),[v isKindOfClass:NSNumber.class]?[v doubleValue]:defaults[i]);}
            for(int i=0;i<15;i++){
                double fallback[]={.25,110,0,.3,0,0,0,.22,1,0,.23,1,.5,1,0};
                id v=i<6?p[@"globals"][i]:i==6?p[@"phaserMix"]:p[@"fx"][key(i)];
                setActual(globalBase+i,[v isKindOfClass:NSNumber.class]?[v doubleValue]:fallback[i]);
            }
            for(int i=0;i<8;i++){values[macroBase+i]=[p[@"macros"][i] floatValue];storageLegacy[i]=values[macroBase+i].load();}
            configureMetadata();
            for(int l=0;l<4;l++){
                NSArray* sends=p[@"sends"];
                setActual(sendID(l,0),sends.count==4?[sends[l][@"delay"] floatValue]:1);
                float rev=sends.count==4?[sends[l][@"reverb"] floatValue]:1;
                setActual(sendID(l,1),rev);
                id shObj=sends.count==4?sends[l][@"shimmer"]:nil;
                setActual(sendID(l,2),shObj?[shObj floatValue]:rev);
                NSArray* motions=p[@"motion"];NSDictionary* m=motions.count==4?motions[l]:nil;
                float packet[85]{};packet[2]=4;packet[3]=2;packet[7]=1;packet[8]=1;
                if(m){NSArray* points=m[@"points"],*routes=m[@"routes"];if(points.count<2||points.count>16||routes.count!=8)return false;
                    packet[0]=[m[@"enabled"] boolValue];packet[1]=[m[@"loop"] boolValue];packet[2]=[m[@"seconds"] floatValue];packet[3]=points.count;
                    for(NSUInteger i=0;i<points.count;i++){packet[4+i*3]=[points[i][@"x"] floatValue];packet[5+i*3]=[points[i][@"y"] floatValue];packet[6+i*3]=[points[i][@"curve"] floatValue];}
                    for(int i=0;i<8;i++){packet[52+i*4]=[routes[i][@"enabled"] boolValue];packet[53+i*4]=[routes[i][@"minimum"] floatValue];packet[54+i*4]=[routes[i][@"maximum"] floatValue];packet[55+i*4]=[routes[i][@"inverted"] boolValue];}
                    if([m[@"beats"] isKindOfClass:NSNumber.class])packet[84]=[m[@"beats"] floatValue];
                }else {packet[57]=400;packet[58]=6000;}
                if(!engine.setMotion(l,packet,85))return false;
                for(int o=0;o<2;o++){
                    NSDictionary* wave=p[@"importedWavetables"][key(l*2+o)];
                    if(wave){NSData* bytes=[[NSData alloc] initWithBase64EncodedString:wave[@"data"] options:0];int size=[wave[@"frameSize"] intValue];
                        if(!bytes||!(size==256||size==512||size==1024||size==2048)||bytes.length%(size*4)||bytes.length>64*size*4)return false;
                        if(!engine.setCustomWavetable(l,o,(const float*)bytes.bytes,int(bytes.length/(size*4)),size))return false;
                    }else engine.clearCustomWavetable(l,o);
                }
            }
            for(int b=0;b<5;b++)for(int s=0;s<6;s++){
                NSArray* banks=p[@"soundMatrix"];NSArray* rows=b==4?p[@"performanceMatrix"]:(banks.count==4?banks[b]:nil);NSDictionary* r=rows.count==6?rows[s]:nil;
                engine.setMatrix(b,s,[r[@"enabled"] boolValue],[r[@"source"] intValue],[r[@"destination"] intValue],r?[r[@"target"] intValue]:4,[r[@"cc"] intValue],[r[@"amount"] floatValue]);
            }
        }
        ++revision;return true;
    }
}
std::string Core::patchJSON(){
    @autoreleasepool {
        std::lock_guard lock(storage->mutex);NSMutableDictionary* p=clone(storage->patch);if(!p[@"layers"])return "{}";
        for(int l=0;l<4;l++)for(int i=0;i<APParameterCount;i++)p[@"layers"][l][@"values"][key(i)]=@(values[layerID(l,i)].load());
        for(int i=0;i<6;i++)p[@"globals"][i]=@(values[globalBase+i].load());
        p[@"phaserMix"]=@(values[1006].load());if(!p[@"fx"])p[@"fx"]=[NSMutableDictionary dictionary];
        for(int i=7;i<15;i++)p[@"fx"][key(i)]=@(values[globalBase+i].load());
        for(int i=0;i<8;i++)p[@"macros"][i]=@(values[macroBase+i].load());
        NSMutableArray* sends=[NSMutableArray array];for(int l=0;l<4;l++)[sends addObject:@{@"delay":@(values[sendID(l,0)].load()),@"reverb":@(values[sendID(l,1)].load()),@"shimmer":@(values[sendID(l,2)].load())}];p[@"sends"]=sends;
        NSData* data=[NSJSONSerialization dataWithJSONObject:p options:NSJSONWritingSortedKeys error:nil];return std::string((const char*)data.bytes,data.length);
    }
}
std::string Core::saveState(){@autoreleasepool{
    auto patch=patchJSON();NSData* data=[NSData dataWithBytes:patch.data() length:patch.size()];
    id p=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    std::lock_guard lock(storage->mutex);
    NSDictionary* object=@{@"version":@1,@"patch":p?:@{},@"outputGain":@(values[outputGainID].load()),@"outputGainRevision":@4,@"transpose":@(values[transposeID].load()),@"routeMask":@(values[routeMaskID].load()),@"routeChannel":@(values[routeChannelID].load()),@"velocityCurve":@(values[velocityID].load()),@"midiMappings":storage->mappings};
    NSData* state=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];return std::string((const char*)state.bytes,state.length);
}}
bool Core::restoreState(const char* json){@autoreleasepool{
    if(!json||strlen(json)>12'000'000)return false;
    NSData* data=[NSData dataWithBytes:json length:strlen(json)];id state=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![state isKindOfClass:NSDictionary.class]||![state[@"version"] isKindOfClass:NSNumber.class]||[state[@"version"] intValue]!=1||![state[@"patch"] isKindOfClass:NSDictionary.class])return false;
    for(NSString* name in @[@"transpose",@"routeMask",@"routeChannel",@"velocityCurve",@"outputGain"])if(state[name]&&!number(state[name]))return false;
    NSData* p=[NSJSONSerialization dataWithJSONObject:state[@"patch"] options:0 error:nil];NSString* s=[[NSString alloc] initWithData:p encoding:NSUTF8StringEncoding];
    id mappings=state[@"midiMappings"]?:@{@"mappings":@[],@"directMappings":@[]};
    if(!dictionary(mappings))return false;
    NSData* mappingData=[NSJSONSerialization dataWithJSONObject:mappings options:0 error:nil];NSString* mappingString=[[NSString alloc] initWithData:mappingData encoding:NSUTF8StringEncoding];
    if(!setMappingsJSON(mappingString.UTF8String,false)||!setPatchJSON(s.UTF8String,true))return false;
    setMappingsJSON(mappingString.UTF8String);
    {
        const int revision=[state[@"outputGainRevision"] intValue];
        double gain=9;
        if(revision==4 && state[@"outputGain"]) gain=[state[@"outputGain"] doubleValue];
        else if(revision==3 && state[@"outputGain"]) {
            gain=[state[@"outputGain"] doubleValue];
            if(std::fabs(gain-24)<0.01) gain=9; // CK88 dual-layer migration from +24 reference
        }
        setActual(outputGainID,gain);
    } // Rev 4: CK88 dual-layer house calibration (~+9 dB).
    setActual(transposeID,[state[@"transpose"] doubleValue]);setActual(routeMaskID,state[@"routeMask"]?[state[@"routeMask"] doubleValue]:15);
    setActual(routeChannelID,[state[@"routeChannel"] doubleValue]);setActual(velocityID,[state[@"velocityCurve"] doubleValue]);setActual(holdID,0);return true;
}}
}
