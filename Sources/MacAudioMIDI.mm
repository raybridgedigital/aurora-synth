#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreMIDI/CoreMIDI.h>
#include <mach/mach_time.h>
#include "AuroraBridge.h"
#include "SynthEngine.hpp"
#include "AudioRecorder.hpp"
#include "WavNormalization.hpp"
#include "WavetableImport.hpp"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace {
struct Source {
    MIDIEndpointRef endpoint = 0;
    int32_t id = 0;
    std::string name;
    std::atomic<bool> connected{false};
    std::atomic<int> layerMask{0};
    std::atomic<int> channel{0};
    std::atomic<uint64_t> events{0};
};
struct Route { int mask = 1; int channel = 0; };
struct State {
    aurora::SynthEngine engine;
    AudioRecorder recorder;
    bool initialized = false;
    MIDIClientRef midiClient = 0;
    MIDIPortRef midiInput = 0;
    std::map<MIDIEndpointRef, Source *> sources;
    // Retired contexts remain alive until the input port is disposed: a receive
    // callback already in flight may still hold the refcon after disconnection.
    std::vector<std::unique_ptr<Source>> contexts;
    std::map<int32_t, Route> routes;
    std::map<int32_t,int> velocityCurves;
    std::map<std::string, int32_t> fallbackIDs;
    int32_t nextFallback = INT32_MIN + 1;
    std::atomic<bool> devicesChanged{false};
    std::atomic<bool> audioChanged{false};
    std::atomic<uint64_t> midiEvents{0};
    std::atomic<uint64_t> ccEvents{0};
    std::atomic<uint64_t> lastCC{UINT64_MAX};
    AudioUnit output = nullptr;
    AudioDeviceID currentDevice = 0;
    bool running = false;
    std::atomic<bool> acceptNotes{false};
    double sampleRate = 48000;
    UInt32 bufferFrames = 128;
    double secondsPerTick = 0;
    std::atomic<float> cpu{0};
    std::atomic<uint64_t> overloads{0};
    std::atomic<uint64_t> overloadGraceUntil{0}; // mach time; the HAL reports a start-up overload
    std::string audioJSON = "[]", midiJSON = "[]";
    std::string status = "Audio is stopped. Choose an output and enable audio.";
};
State &state() { static State s; return s; }

std::string utf8(NSString *value) {
    return value ? std::string(value.UTF8String ?: "") : std::string();
}
NSString *ns(const std::string &value) {
    return [[NSString alloc] initWithBytes:value.data() length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"Unknown";
}
std::string json(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return data ? std::string(static_cast<const char *>(data.bytes), data.length) : "[]";
}
std::string audioString(AudioObjectID device, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address{selector, kAudioObjectPropertyScopeGlobal,
                                       kAudioObjectPropertyElementMain};
    CFStringRef value = nullptr;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &value) || !value) return {};
    return utf8(CFBridgingRelease(value));
}
std::string midiString(MIDIObjectRef object, CFStringRef property) {
    CFStringRef value = nullptr;
    if (MIDIObjectGetStringProperty(object, property, &value) || !value) return {};
    return utf8(CFBridgingRelease(value));
}
template<class T> bool audioProperty(AudioObjectID object,
    AudioObjectPropertySelector selector, T &result,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal) {
    AudioObjectPropertyAddress address{selector, scope, kAudioObjectPropertyElementMain};
    UInt32 size = sizeof(T);
    return AudioObjectGetPropertyData(object, &address, 0, nullptr, &size, &result) == noErr;
}
bool hasOutput(AudioDeviceID device) {
    AudioObjectPropertyAddress address{kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(device, &address, 0, nullptr, &size) || size < sizeof(AudioBufferList)) return false;
    std::vector<uint8_t> storage(size);
    auto *buffers = reinterpret_cast<AudioBufferList *>(storage.data());
    if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, buffers)) return false;
    UInt32 channels = 0;
    for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) channels += buffers->mBuffers[i].mNumberChannels;
    return channels >= 2;
}
std::vector<AudioDeviceID> outputDevices() {
    AudioObjectPropertyAddress address{kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nullptr, &size)) return {};
    std::vector<AudioDeviceID> result(size / sizeof(AudioDeviceID));
    if (size && AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size, result.data())) return {};
    result.resize(size / sizeof(AudioDeviceID));
    std::erase_if(result, [](AudioDeviceID device) {
        UInt32 alive = 1;
        audioProperty(device, kAudioDevicePropertyDeviceIsAlive, alive);
        return !alive || !hasOutput(device);
    });
    return result;
}
OSStatus hardwareChanged(AudioObjectID, UInt32, const AudioObjectPropertyAddress *, void *context) {
    static_cast<State *>(context)->devicesChanged.store(true, std::memory_order_release);
    return noErr;
}
OSStatus activeAudioChanged(AudioObjectID, UInt32, const AudioObjectPropertyAddress *, void *context) {
    static_cast<State *>(context)->audioChanged.store(true, std::memory_order_release);
    return noErr;
}
// The HAL posts this on its notification thread whenever an I/O cycle missed its deadline.
// Device start-up typically reports one miss with nothing playing; the first half second after
// starting is ignored so the counter only shows dropouts a player could hear.
OSStatus processorOverload(AudioObjectID, UInt32, const AudioObjectPropertyAddress *, void *context) {
    auto &s = *static_cast<State *>(context);
    if (mach_absolute_time() >= s.overloadGraceUntil.load(std::memory_order_relaxed))
        s.overloads.fetch_add(1, std::memory_order_relaxed);
    return noErr;
}
void listenToDevice(State &s, AudioDeviceID device, bool add) {
    for (auto selector : std::initializer_list<AudioObjectPropertySelector>{kAudioDevicePropertyDeviceIsAlive,
                          kAudioDevicePropertyNominalSampleRate,
                          kAudioDevicePropertyBufferFrameSize}) {
        AudioObjectPropertyAddress address{selector, kAudioObjectPropertyScopeGlobal,
                                           kAudioObjectPropertyElementMain};
        if (add) AudioObjectAddPropertyListener(device, &address, activeAudioChanged, &s);
        else AudioObjectRemovePropertyListener(device, &address, activeAudioChanged, &s);
    }
    AudioObjectPropertyAddress overload{kAudioDeviceProcessorOverload, kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
    if (add) AudioObjectAddPropertyListener(device, &overload, processorOverload, &s);
    else AudioObjectRemovePropertyListener(device, &overload, processorOverload, &s);
}
void stopAudio(State &s) {
    s.acceptNotes.store(false, std::memory_order_release);
    if (s.currentDevice) listenToDevice(s, s.currentDevice, false);
    if (s.output) {
        AudioOutputUnitStop(s.output);
        AudioUnitUninitialize(s.output);
        AudioComponentInstanceDispose(s.output);
        s.output = nullptr;
    }
    s.recorder.stop();
    s.running = false;
    s.currentDevice = 0;
    s.cpu.store(0, std::memory_order_relaxed);
    s.engine.panic();
}
std::string errorMessage(const char *operation, OSStatus code) {
    return std::string(operation) + " (Core Audio error " + std::to_string(code) + ").";
}
OSStatus render(void *context, AudioUnitRenderActionFlags *, const AudioTimeStamp *,
                UInt32, UInt32 frames, AudioBufferList *buffers) {
    auto &s = *static_cast<State *>(context);
    const uint64_t start = mach_absolute_time();
    // The HAL client format is two non-interleaved Float32 channels. Do not
    // allocate, lock, call Objective-C, or resize containers on this thread.
    if (buffers && buffers->mNumberBuffers >= 2 &&
        buffers->mBuffers[0].mData && buffers->mBuffers[1].mData &&
        buffers->mBuffers[0].mDataByteSize >= frames * sizeof(float) &&
        buffers->mBuffers[1].mDataByteSize >= frames * sizeof(float)) {
        s.engine.render(static_cast<float *>(buffers->mBuffers[0].mData),
                        static_cast<float *>(buffers->mBuffers[1].mData), frames);
        s.recorder.write(frames,buffers);
        for (UInt32 i = 2; i < buffers->mNumberBuffers; ++i)
            if (buffers->mBuffers[i].mData)
                memset(buffers->mBuffers[i].mData, 0, buffers->mBuffers[i].mDataByteSize);
    } else if (buffers) {
        for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i)
            if (buffers->mBuffers[i].mData)
                memset(buffers->mBuffers[i].mData, 0, buffers->mBuffers[i].mDataByteSize);
    }
    const double deadline = frames / s.sampleRate;
    const float load = deadline > 0 ? float((mach_absolute_time() - start) * s.secondsPerTick / deadline) : 0;
    const float previous = s.cpu.load(std::memory_order_relaxed);
    s.cpu.store(std::clamp(previous * 0.9f + load * 0.1f, 0.f, 10.f), std::memory_order_relaxed);
    return noErr;
}
bool autoEnable(MIDIEndpointRef endpoint, const std::string &name) {
    NSString *lower = ns(name).lowercaseString;
    for (NSString *excluded in @[@"remote", @"editor", @"mackie", @"hui", @"daw", @"network", @"session", @"bluetooth", @"iac", @"midi din"])
        if ([lower containsString:excluded]) return false;
    if ([lower containsString:@"modx"] || [lower containsString:@"ck88"] || [lower containsString:@"ck61"]) {
        for (NSString *auxiliary in @[@"port 2", @"port 3", @"-2", @"-3"])
            if ([lower containsString:auxiliary]) return false;
    }
    MIDIEntityRef entity = 0;
    MIDIDeviceRef device = 0;
    MIDIEndpointGetEntity(endpoint, &entity);
    if (entity) MIDIEntityGetDevice(entity, &device);
    if (!device) return false; // Virtual / application endpoints are opt-in.
    SInt32 offline = 0;
    MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline);
    if (offline) return false;
    NSString *owner = ns(midiString(device, kMIDIPropertyDriverOwner)).lowercaseString;
    if ([owner containsString:@"network"] || [owner containsString:@"bluetooth"] || [owner containsString:@"iac"]) return false;
    return true; // Physical musical ports, including Yamaha and class-compliant USB.
}
void receiveMIDI(State &s, const MIDIEventList *list, void *context) {
    auto *source = static_cast<Source *>(context);
    if (!source || !source->connected.load(std::memory_order_acquire)) return;
    constexpr unsigned lengths[16] = {1,1,1,2,2,4,1,1,2,2,2,3,3,4,4,4};
    const MIDIEventPacket *packet = &list->packet[0];
    for (UInt32 p = 0; p < list->numPackets; ++p) {
        for (UInt32 i = 0; i < packet->wordCount;) {
            const UInt32 word = packet->words[i];
            const unsigned type = word >> 28;
            const unsigned length = lengths[type];
            if (i + length > packet->wordCount) break;
            if(type==1&&s.acceptNotes.load(std::memory_order_acquire)){
                uint8_t status=(word>>16)&0xff;
                if(status==0xf8||status==0xfa||status==0xfb||status==0xfc)s.engine.clock(source->id,status,(packet->timeStamp ? packet->timeStamp:mach_absolute_time())*s.secondsPerTick);
            }
            if (type == 2) { // CoreMIDI translates MIDI 2 sources to requested protocol 1.
                const uint8_t status = (word >> 16) & 0xff;
                const uint8_t data1 = (word >> 8) & 0x7f;
                const uint8_t data2 = word & 0x7f;
                if (status >= 0x80 && status < 0xf0) {
                    source->events.fetch_add(1, std::memory_order_relaxed);
                    s.midiEvents.fetch_add(1, std::memory_order_relaxed);
                    if (source->layerMask.load(std::memory_order_relaxed)) {
                        if (s.acceptNotes.load(std::memory_order_acquire))
                            s.engine.midi(source->id, status, data1, data2);
                        const int channel = (status & 15) + 1;
                        const int selectedChannel = source->channel.load(std::memory_order_relaxed);
                        if ((status & 0xf0) == 0xb0 && (!selectedChannel || selectedChannel == channel)) {
                            const uint64_t packed = (uint64_t(uint32_t(source->id)) << 32) |
                                (uint64_t(channel) << 16) | (uint64_t(data1) << 8) | data2;
                            s.lastCC.store(packed, std::memory_order_release);
                            s.ccEvents.fetch_add(1, std::memory_order_release);
                        }
                    }
                }
            }
            i += length;
        }
        packet = MIDIEventPacketNext(packet);
    }
}
void refreshMIDI(State &s) {
    if (!s.midiInput) return;
    std::set<MIDIEndpointRef> present;
    const ItemCount count = MIDIGetNumberOfSources();
    for (ItemCount i = 0; i < count; ++i) {
        auto endpoint = MIDIGetSource(i);
        if (!endpoint) continue;
        SInt32 offline = 0;
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline);
        if (!offline) present.insert(endpoint);
    }
    for (auto it = s.sources.begin(); it != s.sources.end();) {
        if (present.contains(it->first)) { ++it; continue; }
        Source *source = it->second;
        source->connected.store(false, std::memory_order_release);
        MIDIPortDisconnectSource(s.midiInput, it->first);
        s.engine.disconnect(source->id);
        it = s.sources.erase(it);
    }
    for (auto endpoint : present) {
        std::string name = midiString(endpoint, kMIDIPropertyDisplayName);
        if (name.empty()) name = midiString(endpoint, kMIDIPropertyName);
        if (name.empty()) name = "MIDI input";
        if (auto found = s.sources.find(endpoint); found != s.sources.end()) {
            found->second->name = name;
            continue;
        }
        SInt32 id = 0;
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id);
        bool collision = false;
        for (auto &[unused, source] : s.sources) if (source->id == id) collision = true;
        if (!id || collision) {
            const std::string key = name + ":" + std::to_string(endpoint);
            auto [it, added] = s.fallbackIDs.emplace(key, s.nextFallback);
            if (added) ++s.nextFallback;
            id = it->second;
        }
        auto source = std::make_unique<Source>();
        source->endpoint = endpoint;
        source->id = id;
        source->name = name;
        auto found = s.routes.find(id);
        const bool modx = [ns(name).lowercaseString containsString:@"modx"];
        const Route route = found != s.routes.end() ? found->second : Route{autoEnable(endpoint, name) ? 15 : 0, modx ? 1 : 0};
        source->layerMask.store(route.mask);
        source->channel.store(route.channel);
        Source *context = source.get();
        s.contexts.push_back(std::move(source));
        s.engine.route(id, route.mask, route.channel);
        if(auto curve=s.velocityCurves.find(id);curve!=s.velocityCurves.end())s.engine.velocityCurve(id,curve->second);
        context->connected.store(true, std::memory_order_release);
        const OSStatus result = MIDIPortConnectSource(s.midiInput, endpoint, context);
        if (result != noErr) {
            context->connected.store(false, std::memory_order_release);
            s.engine.disconnect(id);
            s.status = "Could not connect MIDI input " + name + " (error " + std::to_string(result) + ").";
            continue;
        }
        s.sources.emplace(endpoint, context);
        s.routes[id] = route;
    }
}
void updateMIDIJSON(State &s) {
    NSMutableArray *array = [NSMutableArray array];
    for (const auto &[endpoint, source] : s.sources) {
        const int mask = source->layerMask.load(std::memory_order_relaxed);
        [array addObject:@{@"id": @(source->id), @"uid": @(source->id),
            @"name": ns(source->name), @"enabled": @(mask != 0),
            @"layerMask": @(mask), @"channel": @(source->channel.load(std::memory_order_relaxed)),
            @"events": @(source->events.load(std::memory_order_relaxed))}];
    }
    s.midiJSON = json(array);
}
void refreshDevices(State &s) {
    @autoreleasepool {
        s.devicesChanged.store(false, std::memory_order_release);
        s.audioChanged.store(false, std::memory_order_release);
        const auto devices = outputDevices();
        NSMutableArray *array = [NSMutableArray array];
        for (auto device : devices) {
            Float64 rate = 0;
            audioProperty(device, kAudioDevicePropertyNominalSampleRate, rate);
            [array addObject:@{@"id": @(device), @"name": ns(audioString(device, kAudioObjectPropertyName)),
                @"uid": ns(audioString(device, kAudioDevicePropertyDeviceUID)), @"sampleRate": @(rate)}];
        }
        s.audioJSON = json(array);
        if (s.running) {
            Float64 rate = 0;
            if (std::find(devices.begin(), devices.end(), s.currentDevice) == devices.end()) {
                stopAudio(s);
                s.status = "The selected audio output disconnected. Choose an output and enable audio again.";
            } else if (!audioProperty(s.currentDevice, kAudioDevicePropertyNominalSampleRate, rate) || std::abs(rate - s.sampleRate) > 0.5) {
                stopAudio(s);
                s.status = "The audio output sample rate changed. Enable audio again to use its current rate.";
            } else {
                audioProperty(s.currentDevice, kAudioDevicePropertyBufferFrameSize, s.bufferFrames);
            }
        }
        refreshMIDI(s);
        updateMIDIJSON(s);
    }
}
void checkChanges(State &s) {
    if (s.devicesChanged.load(std::memory_order_acquire) || s.audioChanged.load(std::memory_order_acquire)) refreshDevices(s);
}
}

extern "C" {
void aurora_initialize() {
    auto &s = state();
    if (s.initialized) return;
    s.initialized = true;
    mach_timebase_info_data_t timebase{};
    mach_timebase_info(&timebase);
    s.secondsPerTick = double(timebase.numer) / double(timebase.denom) / 1e9;
    s.engine.route(0, 15, 0);
    auto *context = &s;
    OSStatus result = MIDIClientCreateWithBlock(CFSTR("Aurora Synthesizer"), &s.midiClient,
        ^(const MIDINotification *) { context->devicesChanged.store(true, std::memory_order_release); });
    if (result == noErr) {
        result = MIDIInputPortCreateWithProtocol(s.midiClient, CFSTR("Aurora Input"), kMIDIProtocol_1_0,
            &s.midiInput, ^(const MIDIEventList *events, void *source) { receiveMIDI(*context, events, source); });
    }
    if (result != noErr) s.status = "MIDI could not initialize (error " + std::to_string(result) + ").";
    AudioObjectPropertyAddress address{kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &address, hardwareChanged, &s);
    refreshDevices(s);
}
void aurora_shutdown() {
    auto &s = state();
    if (!s.initialized) return;
    stopAudio(s);
    for (auto &[endpoint, source] : s.sources) {
        source->connected.store(false, std::memory_order_release);
        s.engine.disconnect(source->id);
    }
    if (s.midiInput) MIDIPortDispose(s.midiInput);
    if (s.midiClient) MIDIClientDispose(s.midiClient);
    s.midiInput = 0; s.midiClient = 0;
    s.sources.clear();
    s.contexts.clear();
    AudioObjectPropertyAddress address{kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &address, hardwareChanged, &s);
    s.initialized = false;
    s.midiJSON = "[]";
    s.status = "Audio is stopped.";
}
void aurora_refresh_devices() { aurora_initialize(); refreshDevices(state()); }
const char *aurora_audio_devices_json() { checkChanges(state()); return state().audioJSON.c_str(); }
const char *aurora_midi_sources_json() { checkChanges(state()); @autoreleasepool { updateMIDIJSON(state()); } return state().midiJSON.c_str(); }
const char *aurora_status() { checkChanges(state()); return state().status.c_str(); }
int aurora_start_audio(uint32_t deviceID, uint32_t requestedFrames) {
    aurora_initialize();
    auto &s = state();
    stopAudio(s);
    if (!deviceID && !audioProperty(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice, deviceID)) {
        s.status = "No default audio output is available."; return 0;
    }
    if (!deviceID || !hasOutput(deviceID)) {
        s.status = "Select an available audio output with at least two channels."; return 0;
    }
    Float64 rate = 0;
    if (!audioProperty(deviceID, kAudioDevicePropertyNominalSampleRate, rate) || rate < 8000 || rate > 192000) {
        s.status = "Could not read a supported sample rate from the selected audio output."; return 0;
    }
    UInt32 frames = requestedFrames ? requestedFrames : 128;
    AudioValueRange range{};
    if (audioProperty(deviceID, kAudioDevicePropertyBufferFrameSizeRange, range))
        frames = UInt32(std::clamp<double>(frames, range.mMinimum, range.mMaximum));
    AudioObjectPropertyAddress bufferAddress{kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    Boolean writable = false;
    if (AudioObjectIsPropertySettable(deviceID, &bufferAddress, &writable) == noErr && writable)
        AudioObjectSetPropertyData(deviceID, &bufferAddress, 0, nullptr, sizeof(frames), &frames);
    audioProperty(deviceID, kAudioDevicePropertyBufferFrameSize, frames);
    // Never change the hardware sample rate: CK88/MODX interfaces may require
    // their existing rate. Read it again after the buffer request.
    audioProperty(deviceID, kAudioDevicePropertyNominalSampleRate, rate);
    s.sampleRate = rate;
    s.bufferFrames = frames;
    s.engine.prepare(rate);
    AudioComponentDescription description{kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(nullptr, &description);
    if (!component) { s.status = "The macOS audio output component is unavailable."; return 0; }
    OSStatus result = AudioComponentInstanceNew(component, &s.output);
    auto fail = [&](const char *operation, OSStatus error) { stopAudio(s); s.status = errorMessage(operation, error); return 0; };
    if (result) return fail("Could not create the audio output", result);
    UInt32 enable = 1, disable = 0;
    result = AudioUnitSetProperty(s.output, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, sizeof(enable));
    if (result) return fail("Could not enable audio playback", result);
    result = AudioUnitSetProperty(s.output, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable, sizeof(disable));
    if (result) return fail("Could not configure the audio output", result);
    result = AudioUnitSetProperty(s.output, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, sizeof(deviceID));
    if (result) return fail("Could not select the audio device", result);
    AudioStreamBasicDescription format{};
    format.mSampleRate = rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = AudioFormatFlags(kAudioFormatFlagsNativeFloatPacked) | AudioFormatFlags(kAudioFormatFlagIsNonInterleaved);
    format.mBytesPerPacket = sizeof(float);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(float);
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    result = AudioUnitSetProperty(s.output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
    if (result) return fail("Could not configure stereo audio", result);
    UInt32 maximumFrames = std::max<UInt32>(4096, frames);
    AudioUnitSetProperty(s.output, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFrames, sizeof(maximumFrames));
    AURenderCallbackStruct callback{render, &s};
    result = AudioUnitSetProperty(s.output, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback));
    if (result) return fail("Could not configure the synthesizer callback", result);
    result = AudioUnitInitialize(s.output);
    if (result) return fail("Could not initialize the selected audio output", result);
    result = AudioOutputUnitStart(s.output);
    if (result) return fail("Could not start the selected audio output", result);
    s.currentDevice = deviceID;
    s.overloads.store(0, std::memory_order_relaxed);
    s.overloadGraceUntil.store(mach_absolute_time() + uint64_t(0.5 / s.secondsPerTick), std::memory_order_relaxed);
    s.running = true;
    s.acceptNotes.store(true, std::memory_order_release);
    listenToDevice(s, deviceID, true);
    audioProperty(deviceID, kAudioDevicePropertyBufferFrameSize, s.bufferFrames);
    s.status = "Audio is running through " + audioString(deviceID, kAudioObjectPropertyName) + ".";
    return 1;
}
void aurora_stop_audio() { stopAudio(state()); state().status = "Audio is stopped. Enable audio to play."; }
int aurora_audio_running() { checkChanges(state()); return state().running; }
uint32_t aurora_current_device() { return state().currentDevice; }
double aurora_sample_rate() { return state().sampleRate; }
uint32_t aurora_buffer_frames() { return state().bufferFrames; }
void aurora_set_parameter(int layer, int parameter, float value) { state().engine.setParameter(layer, parameter, value); }
void aurora_set_layer_fm(int layer, const float *data, int count) { state().engine.setLayerFM(layer, data, count); }
int aurora_set_custom_wavetable(int layer,int oscillator,const float* samples,int frames,int frameSize){return state().engine.setCustomWavetable(layer,oscillator,samples,frames,frameSize);}
void aurora_clear_custom_wavetable(int layer,int oscillator){state().engine.clearCustomWavetable(layer,oscillator);}
int aurora_copy_wavetable_preview(int layer,int oscillator,float* samples,int capacity){return state().engine.copyWavetablePreview(layer,oscillator,samples,capacity);}
const char* aurora_wavetable_name(int index){return aurora::SynthEngine::wavetableName(index);}
const char* aurora_wavetable_category(int index){return aurora::SynthEngine::wavetableCategory(index);}
int aurora_read_wavetable(const char* path,int frameSize,float* samples,int capacity,char* error,int errorCapacity){
    auto result=readWavetableWAV(path,frameSize);
    if(error&&errorCapacity>0){std::strncpy(error,result.error.c_str(),size_t(errorCapacity-1));error[errorCapacity-1]=0;}
    if(!result.error.empty()||!samples||capacity<int(result.samples.size()))return 0;
    std::copy(result.samples.begin(),result.samples.end(),samples);return result.frames;
}
float aurora_get_parameter(int layer, int parameter) { return state().engine.getParameter(layer, parameter); }
void aurora_set_matrix(int bank,int slot,int enabled,int source,int destination,int target,int cc,float amount) { state().engine.setMatrix(bank,slot,enabled,source,destination,target,cc,amount); }
int aurora_set_motion(int layer,const float* data,int count){return state().engine.setMotion(layer,data,count)?1:0;}
float aurora_motion_phase(int layer){return state().engine.motionPhase(layer);}
void aurora_layer_sends(int layer,float delay,float reverb,float shimmer){state().engine.setLayerSends(layer,delay,reverb,shimmer);}
void aurora_solo_layer(int layer){state().engine.soloLayer(layer);}
void aurora_set_transpose(int semitones) { state().engine.setTranspose(semitones); }
void aurora_set_global(int parameter, float value) { state().engine.setGlobal(parameter, value); }
void aurora_velocity_curve(int32_t sourceID,int curve) {
    auto& s=state();curve=std::clamp(curve,0,3);auto found=s.velocityCurves.find(sourceID);
    if(found==s.velocityCurves.end()||found->second!=curve){s.velocityCurves[sourceID]=curve;s.engine.velocityCurve(sourceID,curve);}
}
void aurora_hold(int enabled){state().engine.hold(enabled!=0);}
void aurora_clock_source(int enabled,int32_t sourceID){state().engine.clockSource(enabled!=0,sourceID);}
float aurora_clock_tempo(){return state().engine.clockTempo();}
int aurora_record_start(const char* path){
    auto& s=state();if(!s.running||!path)return 0;
    NSURL* url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    OSStatus result=s.recorder.start((__bridge CFURLRef)url,s.sampleRate);
    if(result)s.status=errorMessage("Could not start recording",result);
    return result==noErr;
}
int aurora_record_stop(){auto& s=state();OSStatus result=s.recorder.stop();if(result)s.status=errorMessage("Recording could not be completed",result);return result==noErr;}
int aurora_normalize_recording(const char* path){return path&&normalizeWAV(path)==noErr;}
int aurora_recording(){return state().recorder.running();}
double aurora_record_seconds(){return state().recorder.seconds();}
float aurora_get_global(int parameter) { return state().engine.getGlobal(parameter); }
void aurora_route_source(int32_t id, int layerMask, int channel) {
    auto &s = state();
    layerMask &= 15;
    channel = std::clamp(channel, 0, 16);
    const auto previous = s.routes.find(id);
    const bool changed = previous == s.routes.end() || previous->second.mask != layerMask || previous->second.channel != channel;
    s.routes[id] = Route{layerMask, channel};
    for (const auto &[endpoint, source] : s.sources) if (source->id == id) {
        source->layerMask.store(layerMask, std::memory_order_relaxed);
        source->channel.store(channel, std::memory_order_relaxed);
    }
    if (changed) s.engine.route(id, layerMask, channel);
}
void aurora_note_on(int note, int velocity) {
    if (!state().running) return;
    state().engine.midi(0, 0x90, uint8_t(std::clamp(note, 0, 127)), uint8_t(std::clamp(velocity, 1, 127)));
}
void aurora_note_off(int note) { if (state().running) state().engine.midi(0, 0x80, uint8_t(std::clamp(note, 0, 127)), 0); }
void aurora_panic() { state().engine.panic(); }
int aurora_copy_modulation(float *values,int capacity) {
    if(!values||capacity<=0)return 0;
    if(!state().running){int count=std::min(capacity,50);std::fill_n(values,count,0.f);return count;}
    return state().engine.copyModulation(values,capacity);
}
int aurora_copy_scope(float *samples,int capacity) {
    if(!samples || capacity<=0)return 0;
    if(!state().running){int n=std::min(capacity,256);std::fill_n(samples,n,0.f);return n;}
    return state().engine.copyScope(samples,capacity);
}
float aurora_output_peak() { return state().running ? state().engine.peak() : 0; }
float aurora_comp_gr(){ return state().running ? state().engine.gainReduction() : 0; }
float aurora_cpu_load() { return state().cpu.load(std::memory_order_relaxed); }
uint64_t aurora_audio_overloads() { return state().running ? state().overloads.load(std::memory_order_relaxed) : 0; }
void aurora_reset_audio_overloads() { state().overloads.store(0, std::memory_order_relaxed); }
int aurora_active_voices() { return state().running ? state().engine.activeVoices() : 0; }
uint64_t aurora_midi_event_count() { return state().midiEvents.load(std::memory_order_relaxed); }
int64_t aurora_last_cc() { const auto value = state().lastCC.load(std::memory_order_acquire); return value == UINT64_MAX ? -1 : int64_t(value & 0xffffff); }
int32_t aurora_last_cc_source() { const auto value = state().lastCC.load(std::memory_order_acquire); return value == UINT64_MAX ? 0 : int32_t(value >> 32); }
uint64_t aurora_cc_count() { return state().ccEvents.load(std::memory_order_acquire); }
uint64_t aurora_last_cc_snapshot() { return state().lastCC.load(std::memory_order_acquire); }
}
