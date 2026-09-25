#include <cstdlib>
#include <vector>
#include <string>
#include "SynthEngine.hpp"
#include "Wavetable.hpp"
#include "WavetableImport.hpp"
#include <cassert>
#include <thread>
#include <atomic>
#include <chrono>
#include <unistd.h>
using aurora::SynthEngine;
static std::vector<float> phaseAudio(float phase,float random){
    SynthEngine engine;engine.prepare(48000);
    for(int global:{AGDelayMix,AGReverbMix,AGChorusMix,AGPhaserMix})engine.setGlobal(global,0);
    for(int parameter:{APSub,APNoise,APLFODepth,APLFO2Depth,APDrive,APFilterEnvelope,APBlend})engine.setParameter(0,parameter,0);
    engine.setParameter(0,APCutoff,18000);engine.setParameter(0,APResonance,0);
    std::vector<float> wave(1024);for(int i=0;i<1024;i++)wave[i]=.8f*sin(aurora::wt::tau*i/1024);
    assert(engine.setCustomWavetable(0,0,wave.data(),1,1024));
    engine.setParameter(0,APWT1Enabled,1);engine.setParameter(0,APWT1Table,24);
    engine.setParameter(0,APWT1Phase,phase);engine.setParameter(0,APWT1RandomPhase,random);
    engine.midi(1,0x90,69,100);
    std::vector<float> left(1024),right(1024);engine.render(left.data(),right.data(),1024);return left;
}
static void writeWAV(const char* path,int count,int channels,bool silent=false){
    AudioStreamBasicDescription format{48000,kAudioFormatLinearPCM,kAudioFormatFlagsNativeFloatPacked,UInt32(4*channels),1,UInt32(4*channels),UInt32(channels),32,0};
    auto url=CFURLCreateFromFileSystemRepresentation(nullptr,(const UInt8*)path,strlen(path),false);AudioFileID file;
    assert(AudioFileCreateWithURL(url,kAudioFileWAVEType,&format,kAudioFileFlags_EraseFile,&file)==0);CFRelease(url);
    std::vector<float> data(count*channels);for(int i=0;i<count;i++)for(int c=0;c<channels;c++)data[i*channels+c]=silent?0:.2f+.4f*sin(aurora::wt::tau*i/256);
    UInt32 size=UInt32(data.size()*4);assert(AudioFileWriteBytes(file,false,0,&size,data.data())==0);AudioFileClose(file);
}
int main(){
    auto start=std::chrono::steady_clock::now();const auto& banks=aurora::wt::factory();
    printf("Factory preparation: %.2fs\n",std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());
    const auto fixed=phaseAudio(0,0),repeated=phaseAudio(0,0),inverted=phaseAudio(.5f,0),randomized=phaseAudio(0,1);
    float randomDifference=0;
    for(int i=0;i<1024;i++){
        assert(std::abs(fixed[i]-repeated[i])<1e-7f);
        assert(std::abs(fixed[i]+inverted[i])<.00001f);
        randomDifference+=std::abs(fixed[i]-randomized[i]);
    }
    assert(randomDifference>.1f);
    puts("PASS: repeatable fixed phase, half-cycle phase inversion, and random phase alters note onset.");
    std::vector<std::vector<float>> signatures;
    for(const auto& bank:banks){
        assert(bank&&bank->frames==8);std::vector<float> sig;
        for(int i=0;i<256;i++)sig.push_back(bank->sample(i/256.f,.001f,.63f,0,0));
        for(const auto& old:signatures){float diff=0;for(int i=0;i<256;i++)diff+=std::abs(old[i]-sig[i]);assert(diff>.01f);}
        signatures.push_back(sig);
        for(int mode=0;mode<6;mode++)for(float step:{.001f,.01f,.1f,.4f})for(int i=0;i<256;i++){
            float p=i/256.f,a=bank->sample(p,step,.5f,mode,.43f),b=bank->sample(p,step,.50001f,mode,.43001f);
            assert(std::isfinite(a)&&std::abs(a)<4&&std::abs(a-b)<.002f);
            assert(std::abs(bank->sample(p,step,.5f,mode,0)-bank->sample(p,step,.5f,0,0))<1e-6f);
        }
    }
    puts("PASS: 24 distinct tables, all warp modes finite, continuous frame/warp interpolation, zero warp preserves base.");
    std::vector<float> sine(1024);for(int i=0;i<1024;i++)sine[i]=.8f*sin(aurora::wt::tau*i/1024);
    auto bank=aurora::wt::make(sine.data(),1,1024);assert(bank);
    for(int i=0;i<1024;i++)assert(std::abs(bank->sample(i/1024.f,.001f,0,0,0)-sine[i])<.0001f);
    assert(!aurora::wt::make(sine.data(),65,1024));assert(!aurora::wt::make(nullptr,1,1024));
    for(int i=0;i<1024;i++)sine[i]=.8f*sin(aurora::wt::tau*100*i/1024);
    bank=aurora::wt::make(sine.data(),1,1024);float high=0;for(int i=0;i<1024;i++)high=std::max(high,std::abs(bank->sample(i/1024.f,.02f,0,0,0)));assert(high<.0001f);
    puts("PASS: fundamental amplitude preserved and above-Nyquist harmonic suppressed.");
    const char* tmp=std::getenv("TMPDIR");std::string pattern=std::string(tmp&&*tmp?tmp:"/tmp")+"/aurora-wavetable-test-XXXXXX"; // $TMPDIR first (sandboxes, CI)
    std::vector<char> pathBuffer(pattern.begin(),pattern.end());pathBuffer.push_back(0);char* path=pathBuffer.data();int fd=mkstemp(path);assert(fd>=0);close(fd);
    for(int channels:{1,2}){writeWAV(path,512,channels);auto imported=readWavetableWAV(path,256);assert(imported.frames==2&&imported.error.empty());float sum=0,peak=0;for(auto x:imported.samples){sum+=x;peak=std::max(peak,std::abs(x));}assert(std::abs(sum)<.001f&&std::abs(peak-.85f)<.0001f);}
    writeWAV(path,513,1);assert(!readWavetableWAV(path,256).error.empty());
    writeWAV(path,256,1,true);assert(!readWavetableWAV(path,256).error.empty());
    assert(!readWavetableWAV(path,123).error.empty());unlink(path);
    puts("PASS: mono/stereo WAV import, normalization, DC removal, incomplete frame/silence/invalid size rejection.");
    SynthEngine engine;engine.prepare(48000);engine.setGlobal(AGMaster,.5);engine.setGlobal(AGReverbMix,0);engine.setGlobal(AGDelayMix,0);engine.setGlobal(AGChorusMix,0);
    engine.setParameter(0,APWT1Enabled,1);engine.setParameter(0,APWT2Enabled,1);engine.setParameter(0,APWT1Table,23);assert(engine.getParameter(0,APWT1Table)==23);
    engine.setMatrix(0,0,true,0,12,0,1,.6f);engine.setMatrix(4,0,true,0,15,0,1,.5f);engine.midi(1,0xb0,1,127);engine.midi(1,0x90,60,100);
    std::array<float,256> left{},right{};float peak=0;
    for(int block=0;block<200;block++){engine.render(left.data(),right.data(),256);for(float x:left){assert(std::isfinite(x)&&std::abs(x)<=1);peak=std::max(peak,std::abs(x));}}
    assert(peak>.001f);std::array<float,46> feedback{};engine.copyModulation(feedback.data(),46);assert(std::abs(feedback[0])>.01f&&feedback[40]>.49f);
    for(int table=0;table<24;table++){
        engine.setParameter(0,APWT1Table,table);engine.setParameter(0,APWT2Table,23-table);
        engine.render(left.data(),right.data(),256);
        assert(engine.activeVoices()==1);
        for(int i=0;i<256;i++)assert(std::isfinite(left[i])&&std::isfinite(right[i])&&std::abs(left[i])<=1&&std::abs(right[i])<=1);
    }
    puts("PASS: all 24 tables can switch on both oscillators while retaining a held note and bounded output.");
    engine.setMatrix(4,0,true,0,15,2,1,.5f);engine.render(left.data(),right.data(),256);engine.copyModulation(feedback.data(),46);assert(feedback[40]==0);
    engine.setParameter(1,APWT1Position,.8f);engine.setParameter(1,APWT1Table,2);
    std::array<float,128> preview{};engine.copyWavetablePreview(1,0,preview.data(),128);
    for(int i=0;i<128;i++)assert(std::abs(preview[i]-banks[2]->sample(i/127.f,.0001f,.8f,0,0))<.00001f);
    std::atomic<bool> stop=false;std::thread audio([&]{while(!stop){engine.render(left.data(),right.data(),256);for(float x:left)assert(std::isfinite(x));}});
    for(int n=0;n<12;n++){assert(engine.setCustomWavetable(0,0,sine.data(),1,1024));engine.setParameter(0,APWT1Table,24);engine.clearCustomWavetable(0,0);}
    stop=true;audio.join();puts("PASS: dual wavetable audio, matrix destinations/target isolation, idle layer preview, concurrent custom-bank replacement/clear.");
    engine.setParameter(0,APWT1Table,13);engine.setParameter(0,APWT2Table,17);engine.setParameter(0,APWT1WarpMode,3);engine.setParameter(0,APWT1Warp,.7f);engine.setParameter(0,APUnison,4);
    for(int key=30;key<94;key++)engine.midi(1,0x90,key,90);
    engine.render(left.data(),right.data(),256);start=std::chrono::steady_clock::now();
    for(int block=0;block<375;block++)engine.render(left.data(),right.data(),256);
    double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    printf("64 voices × 4 unison × 2 wavetable oscillators: 2s audio rendered in %.3fs (%.1f%% of one core offline).\n",seconds,seconds*50);
}
