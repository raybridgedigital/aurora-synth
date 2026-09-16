#include "AudioRecorder.hpp"
#include "WavNormalization.hpp"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <string>
#include <unistd.h>
int main(){
    char directory[]="/tmp/aurora-recording-XXXXXX";assert(mkdtemp(directory));
    std::string path=std::string(directory)+"/check.wav";
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(nullptr,(const UInt8*)path.data(),path.size(),false);
    AudioRecorder recorder;assert(recorder.start(url,48000)==noErr);
    std::array<float,480> left{},right{};
    struct StereoBuffers{UInt32 count;AudioBuffer buffers[2];} buffers{2,{{1,sizeof(left),left.data()},{1,sizeof(right),right.data()}}};
    for(int block=0;block<100;block++){
        for(int i=0;i<480;i++){left[i]=.2f*std::sin((block*480+i)*6.2831853f*440/48000);right[i]=-left[i];}
        recorder.write(480,reinterpret_cast<AudioBufferList*>(&buffers));
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(recorder.seconds()==1);assert(recorder.stop()==noErr&&!recorder.running());
    ExtAudioFileRef file=nullptr;assert(ExtAudioFileOpenURL(url,&file)==noErr);
    SInt64 frames=0;UInt32 size=sizeof(frames);assert(ExtAudioFileGetProperty(file,kExtAudioFileProperty_FileLengthFrames,&size,&frames)==noErr&&frames==48000);
    AudioStreamBasicDescription format{};size=sizeof(format);assert(ExtAudioFileGetProperty(file,kExtAudioFileProperty_FileDataFormat,&size,&format)==noErr);
    assert(format.mChannelsPerFrame==2&&format.mSampleRate==48000&&format.mBitsPerChannel==24);
    AudioStreamBasicDescription client{};client.mSampleRate=48000;client.mFormatID=kAudioFormatLinearPCM;client.mFormatFlags=UInt32(kAudioFormatFlagsNativeFloatPacked)|UInt32(kAudioFormatFlagIsNonInterleaved);client.mChannelsPerFrame=2;client.mBitsPerChannel=32;client.mFramesPerPacket=1;client.mBytesPerFrame=client.mBytesPerPacket=4;
    assert(ExtAudioFileSetProperty(file,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client)==noErr);
    UInt32 count=480;assert(ExtAudioFileRead(file,&count,reinterpret_cast<AudioBufferList*>(&buffers))==noErr&&count==480);
    double energy=0;for(int i=0;i<480;i++){energy+=left[i]*left[i];assert(std::abs(left[i]+right[i])<.00001f);}assert(energy>1);
    ExtAudioFileDispose(file);
    assert(normalizeWAV(path.c_str())==noErr);
    assert(ExtAudioFileOpenURL(url,&file)==noErr);
    assert(ExtAudioFileSetProperty(file,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client)==noErr);
    float peak=0;UInt32 total=0;
    for(;;){count=480;buffers.buffers[0].mDataByteSize=buffers.buffers[1].mDataByteSize=sizeof(left);assert(ExtAudioFileRead(file,&count,reinterpret_cast<AudioBufferList*>(&buffers))==noErr);if(!count)break;total+=count;for(UInt32 i=0;i<count;i++){peak=std::max(peak,std::abs(left[i]));assert(std::abs(left[i]+right[i])<.00001f);}}
    assert(total==48000&&std::abs(peak-std::pow(10.f,-3.f/20.f))<.00001f);
    ExtAudioFileDispose(file);CFRelease(url);
    assert(normalizeWAV(path.c_str())==noErr); // repeat normalization is safe
    assert(normalizeWAV("/nonexistent/aurora.wav")!=noErr);
    std::puts("PASS: normalization peaks at -3 dBFS, preserves stereo phase/duration, and handles repeat/missing-file cases");
    std::puts("PASS: recorder writes a finalized 24-bit stereo WAV, correct duration/sample rate, nonzero audio and independent channels");
}
