#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <atomic>
#include <thread>
#include <chrono>

// File creation/finalization is on the main thread. Core Audio's asynchronous
// writer performs disk work off the render thread; readers protect disposal.
class AudioRecorder {
    ExtAudioFileRef file=nullptr;
    std::atomic<bool> enabled{false};
    std::atomic<int> readers{0};
    std::atomic<OSStatus> error{0};
    std::atomic<uint64_t> frames{0};
    double rate=48000;
public:
    ~AudioRecorder(){stop();}
    OSStatus start(CFURLRef url,double sampleRate) {
        stop();rate=sampleRate;frames=0;error=0;
        AudioStreamBasicDescription disk{};disk.mSampleRate=rate;disk.mFormatID=kAudioFormatLinearPCM;
        disk.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
        disk.mChannelsPerFrame=2;disk.mBitsPerChannel=24;disk.mFramesPerPacket=1;disk.mBytesPerFrame=disk.mBytesPerPacket=6;
        OSStatus result=ExtAudioFileCreateWithURL(url,kAudioFileWAVEType,&disk,nullptr,0,&file);
        if(result){error=result;return result;}
        AudioStreamBasicDescription client{};client.mSampleRate=rate;client.mFormatID=kAudioFormatLinearPCM;
        client.mFormatFlags=UInt32(kAudioFormatFlagsNativeFloatPacked)|UInt32(kAudioFormatFlagIsNonInterleaved);
        client.mChannelsPerFrame=2;client.mBitsPerChannel=32;client.mFramesPerPacket=1;client.mBytesPerFrame=client.mBytesPerPacket=4;
        result=ExtAudioFileSetProperty(file,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client);
        if(!result)result=ExtAudioFileWriteAsync(file,0,nullptr);
        if(result){error=result;stop();return result;}
        enabled=true;return noErr;
    }
    void write(UInt32 count,const AudioBufferList* buffers) {
        ++readers;
        if(enabled.load()&&error.load()==0){OSStatus result=ExtAudioFileWriteAsync(file,count,buffers);if(result){error=result;enabled=false;}else{frames.fetch_add(count,std::memory_order_relaxed);if(seconds()>=3600)enabled=false;}}
        --readers;
    }
    OSStatus stop() {
        enabled=false;
        while(readers.load()!=0)std::this_thread::sleep_for(std::chrono::milliseconds(1));
        if(file){OSStatus result=ExtAudioFileDispose(file);file=nullptr;if(result&&error==0)error=result;}
        return error.load();
    }
    bool running() const{return enabled.load();}
    double seconds() const{return frames.load(std::memory_order_relaxed)/rate;}
};
