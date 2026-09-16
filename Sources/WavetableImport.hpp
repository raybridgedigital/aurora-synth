#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
#include <cstring>
#include <sys/stat.h>
#include <cstdio>
struct WavetableImportResult {std::vector<float> samples;int frameSize=0,frames=0;std::string error;};
inline WavetableImportResult readWavetableWAV(const char* path,int frameSize){
    WavetableImportResult result;result.frameSize=frameSize;
    auto fail=[&](const char* message){result.samples.clear();result.frames=0;result.error=message;return result;};
    if(!path||(frameSize!=256&&frameSize!=512&&frameSize!=1024&&frameSize!=2048))return fail("Choose a valid waveform frame size.");
    struct stat info{};if(stat(path,&info)||info.st_size<44||info.st_size>8*1024*1024)return fail("Choose a WAV wavetable smaller than 8 MB.");
    FILE* header=std::fopen(path,"rb");if(!header)return fail("Could not open this file.");char bytes[12]{};size_t read=std::fread(bytes,1,12,header);std::fclose(header);
    if(read!=12||std::memcmp(bytes,"RIFF",4)||std::memcmp(bytes+8,"WAVE",4))return fail("This file is not a supported WAV file.");
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(nullptr,(const UInt8*)path,std::strlen(path),false);ExtAudioFileRef file=nullptr;
    OSStatus error=ExtAudioFileOpenURL(url,&file);CFRelease(url);if(error)return fail("The WAV file is damaged or unsupported.");
    struct Close{ExtAudioFileRef file;~Close(){ExtAudioFileDispose(file);}}close{file};
    AudioStreamBasicDescription format{};UInt32 size=sizeof(format);error=ExtAudioFileGetProperty(file,kExtAudioFileProperty_FileDataFormat,&size,&format);
    if(error||format.mFormatID!=kAudioFormatLinearPCM||format.mChannelsPerFrame<1||format.mChannelsPerFrame>2)return fail("Use mono or stereo PCM/float WAV audio.");
    SInt64 count=0;size=sizeof(count);error=ExtAudioFileGetProperty(file,kExtAudioFileProperty_FileLengthFrames,&size,&count);
    if(error||count<frameSize||count%frameSize||count/frameSize>64)return fail("The WAV must contain 1–64 complete frames. Check Samples per frame (usually 2048).");
    AudioStreamBasicDescription client{};client.mSampleRate=format.mSampleRate;client.mFormatID=kAudioFormatLinearPCM;client.mFormatFlags=kAudioFormatFlagsNativeFloatPacked;client.mChannelsPerFrame=format.mChannelsPerFrame;client.mBitsPerChannel=32;client.mFramesPerPacket=1;client.mBytesPerFrame=client.mBytesPerPacket=4*client.mChannelsPerFrame;
    error=ExtAudioFileSetProperty(file,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client);if(error)return fail("Could not decode this WAV format.");
    std::vector<float> decoded(size_t(count)*client.mChannelsPerFrame);AudioBufferList buffers{1,{{client.mChannelsPerFrame,UInt32(decoded.size()*4),decoded.data()}}};UInt32 frames=UInt32(count);
    error=ExtAudioFileRead(file,&frames,&buffers);if(error||frames!=count)return fail("The WAV could not be read completely.");
    result.frames=int(count/frameSize);result.samples.resize(count);
    for(size_t i=0;i<decoded.size();i++)if(!std::isfinite(decoded[i]))return fail("The WAV contains invalid sample values.");
    for(int i=0;i<count;i++)result.samples[i]=client.mChannelsPerFrame==1?decoded[i]:(decoded[i*2]+decoded[i*2+1])*.5f;
    float peak=0;
    for(int f=0;f<result.frames;f++){double mean=0;for(int i=0;i<frameSize;i++)mean+=result.samples[f*frameSize+i];mean/=frameSize;for(int i=0;i<frameSize;i++){auto& x=result.samples[f*frameSize+i];x-=float(mean);peak=std::max(peak,std::abs(x));}}
    if(!std::isfinite(peak)||peak<1e-7f)return fail("This table is silent, constant, or cancels when converted to mono.");
    for(auto& x:result.samples)x*=.85f/peak;
    return result;
}
