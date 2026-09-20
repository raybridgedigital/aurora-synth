#include "PluginBridge.h"
#include "PluginCore.hpp"
#include "WavetableImport.hpp"
#include "WavNormalization.hpp"
#include <cstring>
using auroraPlugin::Core;
static Core& core(void* p){return *static_cast<Core*>(p);}
extern "C" {
void aurora_plugin_initialize(void*){}
void aurora_plugin_shutdown(void*){}
void aurora_plugin_refresh_devices(void*){}
const char* aurora_plugin_audio_devices_json(void*){return "[]";}
const char* aurora_plugin_midi_sources_json(void* p){thread_local std::string data;data="[{\"id\":1,\"name\":\"DAW MIDI input\",\"enabled\":true,\"layerMask\":"+std::to_string(int(core(p).values[2030]))+",\"channel\":"+std::to_string(int(core(p).values[2031]))+"}]";return data.c_str();}
const char* aurora_plugin_status(void*){return "Audio, MIDI and tempo are controlled by your DAW.";}
int aurora_plugin_start_audio(void*,uint32_t,uint32_t){return 1;}
void aurora_plugin_stop_audio(void*){}
int aurora_plugin_audio_running(void* p){return core(p).active;}
uint32_t aurora_plugin_current_device(void*){return 0;}
double aurora_plugin_sample_rate(void* p){return core(p).sampleRate;}
uint32_t aurora_plugin_buffer_frames(void* p){return core(p).blockSize;}
void aurora_plugin_set_parameter(void* p,int l,int parameter,float v){core(p).setActual(auroraPlugin::layerID(l,parameter),v,true);}
float aurora_plugin_get_parameter(void* p,int l,int parameter){return core(p).engine.getParameter(l,parameter);}
void aurora_plugin_set_global(void* p,int parameter,float v){core(p).setActual(parameter==AGOutputGain?auroraPlugin::outputGainID:1000+parameter,v,true);}
float aurora_plugin_get_global(void* p,int parameter){return core(p).engine.getGlobal(parameter);}
void aurora_plugin_set_matrix(void* p,int b,int slot,int enabled,int source,int destination,int target,int cc,float amount){core(p).engine.setMatrix(b,slot,enabled,source,destination,target,cc,amount);}
int aurora_plugin_set_motion(void* p,int l,const float* data,int count){return core(p).engine.setMotion(l,data,count);}
float aurora_plugin_motion_phase(void* p,int l){return core(p).engine.motionPhase(l);}
void aurora_plugin_layer_sends(void* p,int l,float delay,float reverb,float shimmer){core(p).setActual(sendID(l,0),delay,true);core(p).setActual(sendID(l,1),reverb,true);core(p).setActual(sendID(l,2),shimmer,true);}
void aurora_plugin_solo_layer(void* p,int l){core(p).engine.soloLayer(l);}
void aurora_plugin_set_transpose(void* p,int semitones){core(p).setActual(2012,semitones,true);}
void aurora_plugin_route_source(void* p,int32_t source,int mask,int channel){if(source==1){core(p).setActual(2030,mask,true);core(p).setActual(2031,channel,true);}}
void aurora_plugin_velocity_curve(void* p,int32_t source,int curve){if(source==1&&core(p).values[2032]!=curve)core(p).setActual(2032,curve,true);}
void aurora_plugin_hold(void* p,int enabled){core(p).setActual(2013,enabled,true);}
void aurora_plugin_clock_source(void*,int,int32_t){}
float aurora_plugin_clock_tempo(void* p){return core(p).tempo;}
int aurora_plugin_record_start(void*,const char*){return 0;}
int aurora_plugin_record_stop(void*){return 0;}
int aurora_plugin_recording(void*){return 0;}
double aurora_plugin_record_seconds(void*){return 0;}
void aurora_plugin_note_on(void* p,int n,int v){core(p).engine.midi(0,0x90,n,v);}
void aurora_plugin_note_off(void* p,int n){core(p).engine.midi(0,0x80,n,0);}
void aurora_plugin_panic(void* p){core(p).engine.panic();core(p).setActual(2013,0);}
float aurora_plugin_output_peak(void* p){return core(p).engine.peak();}
int aurora_plugin_copy_scope(void* p,float* data,int count){return core(p).engine.copyScope(data,count);}
int aurora_plugin_copy_modulation(void* p,float* data,int count){return core(p).engine.copyModulation(data,count);}
int aurora_plugin_set_custom_wavetable(void* p,int l,int o,const float* data,int frames,int size){return core(p).engine.setCustomWavetable(l,o,data,frames,size);}
void aurora_plugin_clear_custom_wavetable(void* p,int l,int o){core(p).engine.clearCustomWavetable(l,o);}
int aurora_plugin_copy_wavetable_preview(void* p,int l,int o,float* data,int count){return core(p).engine.copyWavetablePreview(l,o,data,count);}
float aurora_plugin_cpu_load(void* p){return core(p).cpu;}
int aurora_plugin_active_voices(void* p){return core(p).engine.activeVoices();}
uint64_t aurora_plugin_midi_event_count(void* p){return core(p).midiEvents;}
int64_t aurora_plugin_last_cc(void*){return -1;}
int32_t aurora_plugin_last_cc_source(void*){return 1;}
uint64_t aurora_plugin_cc_count(void* p){return core(p).ccEvents;}
uint64_t aurora_plugin_last_cc_snapshot(void* p){return core(p).lastCC;}
const char* aurora_plugin_patch(void* p){thread_local std::string json;json=core(p).patchJSON();return json.c_str();}
void aurora_plugin_patch_set(void* p,const char* json,int apply){if(core(p).setPatchJSON(json,apply)&&core(p).stateChanged)core(p).stateChanged();}
double aurora_plugin_control(void* p,int id){return id>=0&&id<8192?double(core(p).values[id]):0;}
const char* aurora_plugin_mappings(void* p){thread_local std::string json;json=core(p).mappingsJSON();return json.c_str();}
void aurora_plugin_set_mappings(void* p,const char* json){if(core(p).setMappingsJSON(json)&&core(p).stateChanged)core(p).stateChanged();}
void aurora_plugin_macro(void* p,int index,double value){core(p).setActual(2000+index,value,true);}
void aurora_plugin_xy(void* p,double x,double y){core(p).setActual(2010,x,true);core(p).setActual(2011,y,true);}
uint64_t aurora_plugin_revision(void* p){return core(p).revision;}
const char* aurora_wavetable_name(int i){return aurora::SynthEngine::wavetableName(i);}
const char* aurora_wavetable_category(int i){return aurora::SynthEngine::wavetableCategory(i);}
int aurora_read_wavetable(const char* path,int frameSize,float* output,int capacity,char* error,int errorCapacity){auto result=readWavetableWAV(path,frameSize);if(error&&errorCapacity>0)snprintf(error,errorCapacity,"%s",result.error.c_str());if(!result.error.empty()||int(result.samples.size())>capacity)return 0;std::copy(result.samples.begin(),result.samples.end(),output);return result.frames;}
int aurora_normalize_recording(const char*){return 0;}
}
