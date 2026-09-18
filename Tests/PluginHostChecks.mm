#import <AppKit/AppKit.h>
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/gui/iplugview.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/common/memorystream.h"
#include <cassert>
#include <iostream>
#include <cmath>
using namespace Steinberg;using namespace Steinberg::Vst;
int main(int argc,char** argv){@autoreleasepool{
    assert(argc==2);[NSApplication sharedApplication];
    NSBundle* bundle=[NSBundle bundleWithPath:[@(argv[1]) stringByStandardizingPath]];NSError* error=nil;
    if(![bundle loadAndReturnError:&error]){std::cerr<<error.description.UTF8String<<"\n";return 1;}
    CFBundleRef cf=CFBundleCreate(nullptr,(__bridge CFURLRef)bundle.bundleURL);
    auto entry=(bool(*)(CFBundleRef))CFBundleGetFunctionPointerForName(cf,CFSTR("bundleEntry"));assert(entry&&entry(cf));
    auto getFactory=(IPluginFactory*(*)())CFBundleGetFunctionPointerForName(cf,CFSTR("GetPluginFactory"));assert(getFactory);
    auto factory=owned(getFactory());PClassInfo info{};assert(factory->getClassInfo(0,&info)==kResultOk);
    IComponent* raw=nullptr;assert(factory->createInstance(info.cid,IComponent::iid,(void**)&raw)==kResultOk);auto component=owned(raw);
    auto host=owned(new HostApplication);assert(component->initialize(host)==kResultOk);
    FUnknownPtr<IAudioProcessor> processor(component);FUnknownPtr<IEditController> controller(component);assert(processor&&controller);
    ProcessSetup setup{kRealtime,kSample32,512,48000};assert(processor->setupProcessing(setup)==kResultOk);
    assert(component->setActive(true)==kResultOk);assert(processor->setProcessing(true)==kResultOk);
    float l[512]{},r[512]{};float* channels[]={l,r};AudioBusBuffers output{};output.numChannels=2;output.channelBuffers32=channels;
    EventList events;Event note{};note.type=Event::kNoteOnEvent;note.sampleOffset=256;note.noteOn.pitch=60;note.noteOn.velocity=.8;events.addEvent(note);
    ProcessData data{};data.numSamples=512;data.numOutputs=1;data.outputs=&output;data.inputEvents=&events;
    ProcessContext context{};context.state=ProcessContext::kTempoValid;context.tempo=137;context.sampleRate=48000;data.processContext=&context;
    double energy=0;
    for(int block=0;block<100;block++){assert(processor->process(data)==kResultOk);events.clear();for(int i=0;i<512;i++){assert(std::isfinite(l[i]));if(block==0&&i<256)assert(l[i]==0&&r[i]==0);energy+=l[i]*l[i]+r[i]*r[i];}}
    std::cout<<"Hosted MIDI energy: "<<energy<<std::endl;assert(energy>0);
    assert(std::abs(controller->normalizedParamToPlain(1001,controller->getParamNormalized(1001))-137)<.001);
    ParameterChanges changes;int32 queueIndex=0,pointIndex=0;
    changes.addParameterData(2010,queueIndex)->addPoint(128,.2,pointIndex);
    changes.addParameterData(2011,queueIndex)->addPoint(256,.8,pointIndex);
    changes.addParameterData(6002,queueIndex)->addPoint(64,.32,pointIndex); // New filter 2 cutoff, old IDs unchanged.
    changes.addParameterData(6397,queueIndex)->addPoint(96,.75,pointIndex); // Layer D oscillator modulation amount.
    data.inputParameterChanges=&changes;assert(processor->process(data)==kResultOk);data.inputParameterChanges=nullptr;
    assert(std::abs(controller->getParamNormalized(2000)-.2)<1e-5);assert(std::abs(controller->getParamNormalized(2002)-.8)<1e-5);
    assert(std::abs(controller->getParamNormalized(6002)-.32)<1e-5);assert(std::abs(controller->getParamNormalized(6397)-.75)<1e-5);
    MemoryStream saved;assert(component->getState(&saved)==kResultOk);assert(saved.getSize()>100);
    processor->setProcessing(false);component->setActive(false);
    controller->setParamNormalized(2000,.9);saved.seek(0,IBStream::kIBSeekSet,nullptr);assert(component->setState(&saved)==kResultOk);
    assert(std::abs(controller->getParamNormalized(2000)-.2)<1e-5);
    assert(std::abs(controller->getParamNormalized(6002)-.32)<1e-5);
    MemoryStream editorState;assert(controller->getState(&editorState)==kResultOk);editorState.seek(0,IBStream::kIBSeekSet,nullptr);assert(controller->setState(&editorState)==kResultOk);
    setup.processMode=kOffline;setup.symbolicSampleSize=kSample64;assert(processor->setupProcessing(setup)==kResultOk);component->setActive(true);processor->setProcessing(true);
    double dl[512]{},dr[512]{};double* doubleChannels[]={dl,dr};output.channelBuffers64=doubleChannels;data.symbolicSampleSize=kSample64;data.processMode=kOffline;
    events.addEvent(note);assert(processor->process(data)==kResultOk);events.clear();double offlineEnergy=0;
    for(int block=0;block<100;block++){assert(processor->process(data)==kResultOk);for(int i=0;i<512;i++){assert(std::isfinite(dl[i]));offlineEnergy+=dl[i]*dl[i]+dr[i]*dr[i];}}
    assert(offlineEnergy>0);std::cout<<"Sample-offset MIDI, closed-editor XY automation, state recall and 64-bit offline rendering passed"<<std::endl;
    auto view=owned(controller->createView(ViewType::kEditor));assert(view);ViewRect rect{};assert(view->getSize(&rect)==kResultOk);
    std::cout<<"Editor size: "<<rect.getWidth()<<" x "<<rect.getHeight()<<std::endl;
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,rect.getWidth(),rect.getHeight()) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    assert(view->attached((__bridge void*)window.contentView,kPlatformTypeNSView)==kResultOk);
    [window.contentView layoutSubtreeIfNeeded];assert(window.contentView.subviews.count>0);
    std::cout<<"Editor attached with "<<window.contentView.subviews.count<<" subview(s)"<<std::endl;
    view->removed();view=nullptr;processor->setProcessing(false);component->setActive(false);component->terminate();
    std::cout<<"Host audio and editor lifecycle passed"<<std::endl;
}}
