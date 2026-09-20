#pragma once
#include "AuroraBridge.h"
#ifdef __cplusplus
extern "C" {
#endif
void aurora_plugin_initialize(void *context);
void aurora_plugin_shutdown(void *context);
void aurora_plugin_refresh_devices(void *context);
const char * aurora_plugin_audio_devices_json(void *context);
const char * aurora_plugin_midi_sources_json(void *context);
const char * aurora_plugin_status(void *context);
int aurora_plugin_start_audio(void *context, uint32_t deviceID, uint32_t bufferFrames);
void aurora_plugin_stop_audio(void *context);
int aurora_plugin_audio_running(void *context);
uint32_t aurora_plugin_current_device(void *context);
double aurora_plugin_sample_rate(void *context);
uint32_t aurora_plugin_buffer_frames(void *context);
void aurora_plugin_set_parameter(void *context, int layer, int parameter, float value);
float aurora_plugin_get_parameter(void *context, int layer, int parameter);
void aurora_plugin_set_matrix(void *context, int bank, int slot, int enabled, int source, int destination, int target, int cc, float amount);
int aurora_plugin_set_motion(void *context, int layer, const float *data, int count);
float aurora_plugin_motion_phase(void *context, int layer);
void aurora_plugin_layer_sends(void *context, int layer, float delay, float reverb, float shimmer);
void aurora_plugin_solo_layer(void *context, int layer);
void aurora_plugin_set_transpose(void *context, int semitones);
void aurora_plugin_set_global(void *context, int parameter, float value);
float aurora_plugin_get_global(void *context, int parameter);
void aurora_plugin_route_source(void *context, int32_t sourceID, int layerMask, int channel);
void aurora_plugin_velocity_curve(void *context, int32_t sourceID, int curve);
void aurora_plugin_hold(void *context, int enabled);
void aurora_plugin_clock_source(void *context, int enabled, int32_t sourceID);
float aurora_plugin_clock_tempo(void *context);
int aurora_plugin_record_start(void *context, const char *path);
int aurora_plugin_record_stop(void *context);
int aurora_plugin_recording(void *context);
double aurora_plugin_record_seconds(void *context);
void aurora_plugin_note_on(void *context, int note, int velocity);
void aurora_plugin_note_off(void *context, int note);
void aurora_plugin_panic(void *context);
float aurora_plugin_output_peak(void *context);
int aurora_plugin_copy_scope(void *context, float *samples, int capacity);
int aurora_plugin_copy_modulation(void *context, float *values, int capacity);
int aurora_plugin_set_custom_wavetable(void *context, int layer, int oscillator, const float *samples, int frames, int frameSize);
void aurora_plugin_clear_custom_wavetable(void *context, int layer, int oscillator);
int aurora_plugin_copy_wavetable_preview(void *context, int layer, int oscillator, float *samples, int capacity);
float aurora_plugin_cpu_load(void *context);
int aurora_plugin_active_voices(void *context);
uint64_t aurora_plugin_midi_event_count(void *context);
int64_t aurora_plugin_last_cc(void *context);
int32_t aurora_plugin_last_cc_source(void *context);
uint64_t aurora_plugin_cc_count(void *context);
uint64_t aurora_plugin_last_cc_snapshot(void *context);
const char *aurora_plugin_patch(void *context);
void aurora_plugin_patch_set(void *context,const char *json,int apply);
void aurora_plugin_macro(void *context,int index,double value);
uint64_t aurora_plugin_revision(void *context);
void *aurora_create_editor(void *context);
void aurora_destroy_editor(void *view);
void aurora_plugin_xy(void *context,double x,double y);
double aurora_plugin_control(void *context,int id);
const char *aurora_plugin_mappings(void *context);
void aurora_plugin_set_mappings(void *context,const char *json);
#ifdef __cplusplus
}
#endif
