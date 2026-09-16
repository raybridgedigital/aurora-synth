#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <unistd.h>

// Two-pass, stereo-linked peak normalization. Called off the audio/UI threads.
// The original is replaced only after a complete, successfully finalized WAV.
inline OSStatus normalizeWAV(const char* path) {
    ExtAudioFileRef input=nullptr,output=nullptr;
    auto urlFor=[](const std::string& p){return CFURLCreateFromFileSystemRepresentation(nullptr,(const UInt8*)p.data(),p.size(),false);};
    CFURLRef url=urlFor(path);OSStatus result=ExtAudioFileOpenURL(url,&input);CFRelease(url);
    if(result)return result;
    AudioStreamBasicDescription disk{};UInt32 size=sizeof(disk);
    result=ExtAudioFileGetProperty(input,kExtAudioFileProperty_FileDataFormat,&size,&disk);
    if(!result&&(disk.mChannelsPerFrame!=2||disk.mFormatID!=kAudioFormatLinearPCM))result=kAudio_ParamError;
    AudioStreamBasicDescription client{};client.mSampleRate=disk.mSampleRate;client.mFormatID=kAudioFormatLinearPCM;
    client.mFormatFlags=UInt32(kAudioFormatFlagsNativeFloatPacked)|UInt32(kAudioFormatFlagIsNonInterleaved);
    client.mChannelsPerFrame=2;client.mBitsPerChannel=32;client.mFramesPerPacket=1;client.mBytesPerFrame=client.mBytesPerPacket=4;
    if(!result)result=ExtAudioFileSetProperty(input,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client);
    std::array<float,8192> left{},right{};
    struct Stereo {UInt32 count;AudioBuffer buffers[2];} data{2,{{1,sizeof(left),left.data()},{1,sizeof(right),right.data()}}};
    auto buffers=reinterpret_cast<AudioBufferList*>(&data);float peak=0;
    while(!result){UInt32 count=left.size();data.buffers[0].mDataByteSize=data.buffers[1].mDataByteSize=sizeof(left);result=ExtAudioFileRead(input,&count,buffers);if(result||!count)break;for(UInt32 i=0;i<count;i++){if(!std::isfinite(left[i])||!std::isfinite(right[i])){result=kAudio_ParamError;break;}peak=std::max({peak,std::abs(left[i]),std::abs(right[i])});}}
    if(result||peak<1e-8f){ExtAudioFileDispose(input);return result;}
    std::string temporary=std::string(path)+".normalizing-"+std::to_string(getpid());
    url=urlFor(temporary);
    if(!result)result=ExtAudioFileCreateWithURL(url,kAudioFileWAVEType,&disk,nullptr,0,&output);
    CFRelease(url);bool created=output!=nullptr;
    if(!result)result=ExtAudioFileSetProperty(output,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client);
    if(!result)result=ExtAudioFileSeek(input,0);
    const float gain=std::pow(10.f,-3.f/20.f)/peak;
    while(!result){UInt32 count=left.size();data.buffers[0].mDataByteSize=data.buffers[1].mDataByteSize=sizeof(left);result=ExtAudioFileRead(input,&count,buffers);if(result||!count)break;for(UInt32 i=0;i<count;i++){left[i]*=gain;right[i]*=gain;}result=ExtAudioFileWrite(output,count,buffers);}
    ExtAudioFileDispose(input);
    if(output){OSStatus finish=ExtAudioFileDispose(output);if(!result)result=finish;}
    if(!result&&std::rename(temporary.c_str(),path)!=0)result=kAudio_FilePermissionError;
    if(result&&created)std::remove(temporary.c_str());
    return result;
}
