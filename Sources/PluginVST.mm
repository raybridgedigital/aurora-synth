#import <AppKit/AppKit.h>
#include "PluginCore.hpp"
#include "PluginBridge.h"
#include "public.sdk/source/vst/vstsinglecomponenteffect.h"
#include "public.sdk/source/common/pluginview.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ustring.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstmidicontrollers.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <vector>
using namespace Steinberg;
using namespace Steinberg::Vst;
namespace auroraPlugin {
static const FUID processorUID(0x61DF9511,0x44C9489C,0xA01D133E,0x637C0A16);

class Editor final:public CPluginView {
    Core& core;IPtr<FUnknown> owner;NSView* view=nil;
public:
    explicit Editor(Core& c,FUnknown* instance):core(c),owner(instance){rect={0,0,1280,820};}
    ~Editor()override{if(view)removed();}
    tresult PLUGIN_API isPlatformTypeSupported(FIDString type)override{return type&&std::strcmp(type,kPlatformTypeNSView)==0?kResultTrue:kResultFalse;}
    tresult PLUGIN_API attached(void* parent,FIDString type)override{
        if(!parent||isPlatformTypeSupported(type)!=kResultTrue)return kResultFalse;
        @autoreleasepool {view=(__bridge NSView*)aurora_create_editor(&core);[(__bridge NSView*)parent addSubview:view];}
        return CPluginView::attached(parent,type);
    }
    tresult PLUGIN_API removed()override{if(view){aurora_destroy_editor((__bridge void*)view);view=nil;}return CPluginView::removed();}
    tresult PLUGIN_API canResize()override{return kResultTrue;}
    tresult PLUGIN_API checkSizeConstraint(ViewRect* size)override{if(!size)return kInvalidArgument;size->right=size->left+std::max(1260,size->getWidth());size->bottom=size->top+std::max(780,size->getHeight());return kResultTrue;}
    tresult PLUGIN_API onSize(ViewRect* size)override{if(!size)return kInvalidArgument;rect=*size;if(view)[view setFrameSize:NSMakeSize(size->getWidth(),size->getHeight())];return kResultTrue;}
};

class PlainParameter final:public Parameter {
    int id;
public:
    PlainParameter(int identifier,const std::string& title,double value,int flags):id(identifier){
        info.id=identifier;UString(info.title,128).fromAscii(title.c_str());info.flags=flags;
        auto s=Core::spec(identifier);info.stepCount=s.integer?int(s.high-s.low):0;
        info.defaultNormalizedValue=value;valueNormalized=value;
    }
    ParamValue toPlain(ParamValue v)const override{return Core::actual(id,v);}
    ParamValue toNormalized(ParamValue v)const override{return Core::normalize(id,v);}
    void toString(ParamValue v,String128 out)const override{char text[64];auto s=Core::spec(id);snprintf(text,sizeof(text),s.integer?"%.0f":"%.3f",toPlain(v));UString(out,128).fromAscii(text);}
    bool fromString(const TChar* text,ParamValue& v)const override{char buffer[128];UString((TChar*)text,128).toAscii(buffer,128);char* end=nullptr;double actual=std::strtod(buffer,&end);if(end==buffer||!std::isfinite(actual))return false;v=toNormalized(actual);return true;}
};

class Processor final:public SingleComponentEffect, public IMidiMapping {
    Core core;
    std::vector<float> temporaryL,temporaryR;
    struct Timed {int offset,id;double value;int status,a,b;int order=0;};
    std::array<Timed,8192> timeline{};
    bool haveTransport=false,wasPlaying=false;
    int64 previousEnd=0;
public:
    static FUnknown* createInstance(void*){return static_cast<IComponent*>(new Processor);}
    tresult PLUGIN_API queryInterface(const TUID iid,void** obj)override{
        if(FUID::fromTUID(iid)==IMidiMapping::iid){*obj=static_cast<IMidiMapping*>(this);addRef();return kResultOk;}
        return SingleComponentEffect::queryInterface(iid,obj);
    }
    uint32 PLUGIN_API addRef()override{return SingleComponentEffect::addRef();}
    uint32 PLUGIN_API release()override{return SingleComponentEffect::release();}
    tresult PLUGIN_API initialize(FUnknown* host)override{
        auto result=SingleComponentEffect::initialize(host);if(result!=kResultOk)return result;
        addAudioOutput(STR16("Stereo"),SpeakerArr::kStereo);addEventInput(STR16("MIDI"),16);
        processContextRequirements.needTempo().needTransportState().needProjectTimeMusic().needContinousTimeSamples();
        auto add=[&](int id,std::string name,int flags=ParameterInfo::kCanAutomate){parameters.addParameter(new PlainParameter(id,name,core.normalized(id),flags));};
        for(int l=0;l<4;l++)for(int p=0;p<APParameterCount;p++)add(layerID(l,p),std::string(1,char('A'+l))+" / "+layers[p].name);
        for(int p=0;p<15;p++)add(1000+p,globals[p].name,p==1?ParameterInfo::kIsReadOnly:ParameterInfo::kCanAutomate);
        for(int i=0;i<8;i++)add(2000+i,"Macro "+std::to_string(i+1));
        add(xyX,"XY / X");add(xyY,"XY / Y");add(transposeID,"Global transpose");add(holdID,"Hold");
        add(routeMaskID,"MIDI / Layers");add(routeChannelID,"MIDI / Channel");add(velocityID,"MIDI / Velocity curve");
        add(outputGainID,"Output boost / dB");
        for(int l=0;l<4;l++){add(sendBase+l*2,std::string(1,char('A'+l))+" / Delay send");add(sendBase+l*2+1,std::string(1,char('A'+l))+" / Reverb send");}
        for(int ch=0;ch<16;ch++)for(int cc=0;cc<130;cc++)add(midiBase+ch*130+cc,"MIDI "+std::to_string(ch+1)+" / "+std::to_string(cc),ParameterInfo::kIsHidden);
        core.notify=[this](int id,double value){beginEdit(id);EditControllerEx1::setParamNormalized(id,value);performEdit(id,value);endEdit(id);};
        core.stateChanged=[this]{if(componentHandler)componentHandler->restartComponent(kParamValuesChanged);if(componentHandler2)componentHandler2->setDirty(true);};
        return kResultOk;
    }
    tresult PLUGIN_API terminate()override{core.notify={};core.stateChanged={};return SingleComponentEffect::terminate();}
    tresult PLUGIN_API getMidiControllerAssignment(int32 bus,int16 channel,CtrlNumber cc,ParamID& id)override{
        if(bus!=0||channel<0||channel>15||cc<0||cc>129)return kResultFalse;id=midiBase+channel*130+cc;return kResultTrue;
    }
    tresult PLUGIN_API setBusArrangements(SpeakerArrangement*,int32 ins,SpeakerArrangement* outs,int32 count)override{return ins==0&&count==1&&outs&&outs[0]==SpeakerArr::kStereo?kResultTrue:kResultFalse;}
    tresult PLUGIN_API canProcessSampleSize(int32 size)override{return size==kSample32||size==kSample64?kResultTrue:kResultFalse;}
    tresult PLUGIN_API setupProcessing(ProcessSetup& setup)override{
        if(setup.sampleRate<8000||setup.sampleRate>192000||setup.maxSamplesPerBlock<1||setup.maxSamplesPerBlock>1048576)return kInvalidArgument;
        temporaryL.resize(setup.maxSamplesPerBlock);temporaryR.resize(setup.maxSamplesPerBlock);
        core.sampleRate=setup.sampleRate;core.blockSize=setup.maxSamplesPerBlock;core.engine.prepare(setup.sampleRate);
        haveTransport=false;return SingleComponentEffect::setupProcessing(setup);
    }
    tresult PLUGIN_API setActive(TBool state)override{core.active=state;if(!state)core.engine.panic();return kResultOk;}
    tresult PLUGIN_API setProcessing(TBool state)override{if(!state)core.engine.panic();return kResultOk;}
    uint32 PLUGIN_API getTailSamples()override{return uint32(core.sampleRate*30);}
    IPlugView* PLUGIN_API createView(FIDString name)override{return name&&std::strcmp(name,ViewType::kEditor)==0?new Editor(core,static_cast<IComponent*>(this)):nullptr;}
    tresult PLUGIN_API setParamNormalized(ParamID id,ParamValue value)override{
        if(!core.active)core.setNormalized(id,value);
        return EditControllerEx1::setParamNormalized(id,value);
    }
    ParamValue PLUGIN_API getParamNormalized(ParamID id)override{return core.normalized(id);}
    tresult PLUGIN_API getEditorState(IBStream* stream)override{if(!stream)return kInvalidArgument;uint32 version=1;return stream->write(&version,4,nullptr);}
    tresult PLUGIN_API setEditorState(IBStream* stream)override{if(!stream)return kInvalidArgument;uint32 version=0;int32 read=0;return stream->read(&version,4,&read)==kResultOk&&read==4&&version==1?kResultOk:kResultFalse;}
    tresult PLUGIN_API getState(IBStream* stream)override{
        if(!stream)return kInvalidArgument;auto data=core.saveState();uint32 length=uint32(data.size());int32 written=0;
        if(stream->write(&length,4,&written)!=kResultOk||written!=4)return kResultFalse;
        return stream->write(data.data(),length,&written)==kResultOk&&written==int32(length)?kResultOk:kResultFalse;
    }
    tresult PLUGIN_API setState(IBStream* stream)override{
        if(!stream)return kInvalidArgument;uint32 length=0;int32 read=0;
        if(stream->read(&length,4,&read)!=kResultOk||read!=4||length>12000000)return kResultFalse;
        std::string data(length,'\0');if(stream->read(data.data(),length,&read)!=kResultOk||read!=int32(length))return kResultFalse;
        if(!core.restoreState(data.c_str()))return kResultFalse;
        for(int i=0;i<parameters.getParameterCount();i++){auto* p=parameters.getParameterByIndex(i);p->setNormalized(core.normalized(p->getInfo().id));}
        return kResultOk;
    }
    tresult PLUGIN_API setComponentState(IBStream* stream)override{return setState(stream);}
    tresult PLUGIN_API process(ProcessData& data)override{
        auto start=std::chrono::steady_clock::now();
        if(data.numSamples<0||size_t(data.numSamples)>temporaryL.size())return kInvalidArgument;
        if(data.processContext){auto& c=*data.processContext;
            if((c.state&ProcessContext::kTempoValid)&&std::isfinite(c.tempo)&&c.tempo>0){if(core.tempo!=c.tempo)++core.revision;core.tempo=c.tempo;core.values[1001]=c.tempo;core.engine.setGlobal(AGTempo,float(c.tempo));}
            bool playing=c.state&ProcessContext::kPlaying;
            bool jump=haveTransport&&playing&&wasPlaying&&c.projectTimeSamples!=previousEnd;
            if(jump||(haveTransport&&wasPlaying&&!playing))core.engine.panic();
            haveTransport=true;wasPlaying=playing;previousEnd=c.projectTimeSamples+data.numSamples;
        }
        int n=0;
        if(data.inputParameterChanges)for(int q=0;q<data.inputParameterChanges->getParameterCount();q++){
            auto* queue=data.inputParameterChanges->getParameterData(q);if(!queue)continue;
            for(int i=0;i<queue->getPointCount();i++){int32 offset;double value;if(queue->getPoint(i,offset,value)!=kResultOk)continue;
                if(n==int(timeline.size())){core.engine.panic();return kResultFalse;}
                timeline[n++]={std::clamp(offset,0,data.numSamples),int(queue->getParameterId()),value,0,0,0};
            }
        }
        if(data.inputEvents)for(int i=0;i<data.inputEvents->getEventCount();i++){
            Event event{};if(data.inputEvents->getEvent(i,event)!=kResultOk)continue;int status=0,a=0,b=0;
            switch(event.type){case Event::kNoteOnEvent:status=0x90|(event.noteOn.channel&15);a=event.noteOn.pitch;b=int(event.noteOn.velocity*127+.5);break;
            case Event::kNoteOffEvent:status=0x80|(event.noteOff.channel&15);a=event.noteOff.pitch;break;
            case Event::kPolyPressureEvent:status=0xa0|(event.polyPressure.channel&15);a=event.polyPressure.pitch;b=int(event.polyPressure.pressure*127+.5);break;
            default:continue;}
            if(n==int(timeline.size())){core.engine.panic();return kResultFalse;}
            timeline[n++]={std::clamp(event.sampleOffset,0,data.numSamples),-1,0,status,a,b};
        }
        for(int i=0;i<n;i++)timeline[i].order=i;
        std::sort(timeline.begin(),timeline.begin()+n,[](const Timed& a,const Timed& b){return a.offset==b.offset?a.order<b.order:a.offset<b.offset;});
        float* left=temporaryL.data();float* right=temporaryR.data();
        bool output=data.numOutputs>0&&data.outputs&&data.outputs[0].numChannels>=2;
        if(output&&data.symbolicSampleSize==kSample32){left=data.outputs[0].channelBuffers32[0];right=data.outputs[0].channelBuffers32[1];}
        if(!left||!right)return kInvalidArgument;
        int cursor=0;
        for(int i=0;i<n;i++){auto& e=timeline[i];if(e.offset>cursor){core.engine.render(left+cursor,right+cursor,e.offset-cursor);cursor=e.offset;}
            if(e.id>=0)core.setNormalized(e.id,e.value);else core.midi(e.status,e.a,e.b);
        }
        if(cursor<data.numSamples)core.engine.render(left+cursor,right+cursor,data.numSamples-cursor);
        if(output){data.outputs[0].silenceFlags=0;if(data.symbolicSampleSize==kSample64)for(int i=0;i<data.numSamples;i++){data.outputs[0].channelBuffers64[0][i]=left[i];data.outputs[0].channelBuffers64[1][i]=right[i];}}
        double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();core.cpu=data.numSamples>0?float(seconds/(data.numSamples/core.sampleRate.load())):0;
        return kResultOk;
    }
};
}
bool InitModule(){return true;}
bool DeinitModule(){return true;}
BEGIN_FACTORY_DEF("Ray Bridge Digital","https://github.com/raybridgedigital/aurora-synth","")
DEF_CLASS2(INLINE_UID_FROM_FUID(auroraPlugin::processorUID),PClassInfo::kManyInstances,kVstAudioEffectClass,"Aurora",0,"Instrument|Synth","0.20.6",kVstVersionString,auroraPlugin::Processor::createInstance)
END_FACTORY
