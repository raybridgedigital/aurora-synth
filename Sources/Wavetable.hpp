#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <memory>
#include <vector>

namespace aurora::wt {
constexpr float tau=6.283185307179586f;
inline constexpr const char* names[24]={"Silk Spectrum","Velvet Ranks","Warm Prism","Amber Pulse","Vowel Drift","Choir Glass","Reed Talk","Hollow Mouth","Copper Bells","Steel Petals","Crystal Steps","Bronze Motion","Acid Teeth","Razor Bloom","Electric Fold","Digital Grit","Cloud Harmonics","Frozen Organ","Air Columns","Dusk Choir","Round Sub","Rubber Wire","Soft Tines","Flute Halo"};
inline constexpr const char* categories[24]={"Warm","Warm","Warm","Warm","Vocal","Vocal","Vocal","Vocal","Metallic","Metallic","Metallic","Metallic","Aggressive","Aggressive","Aggressive","Aggressive","Atmospheric","Atmospheric","Atmospheric","Atmospheric","Pure","Pure","Pure","Pure"};
inline void fft(std::vector<std::complex<float>>& a,bool inverse){
    size_t n=a.size();for(size_t i=1,j=0;i<n;i++){size_t bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)std::swap(a[i],a[j]);}
    for(size_t len=2;len<=n;len<<=1){auto step=std::polar(1.f,(inverse?1:-1)*tau/float(len));for(size_t i=0;i<n;i+=len){std::complex<float> w=1;for(size_t j=0;j<len/2;j++){auto u=a[i+j],v=a[i+j+len/2]*w;a[i+j]=u+v;a[i+j+len/2]=u-v;w*=step;}}}
    if(inverse)for(auto& v:a)v/=float(n);
}
struct Cycle {
    std::array<std::vector<float>,9> levels;
    float at(float phase,int level) const{
        const auto& data=levels[level];int size=int(data.size())-1;float x=phase*size;int i=std::clamp(int(x),0,size-1);float f=x-i;
        return data[i]+f*(data[i+1]-data[i]);
    }
};
struct Bank {
    int frames=0;
    std::vector<Cycle> cycles; // frame-major, base + 8 amounts per warp
    float sample(float phase,float step,float position,int mode,float amount) const{
        phase-=std::floor(phase);position=std::clamp(position,0.f,1.f);amount=std::clamp(amount,0.f,1.f);mode=std::clamp(mode,0,3);
        // One octave of guard band keeps both interpolated mip levels below Nyquist.
        float lod=std::clamp(std::log2(std::max(1.f,step*1024.f/.45f)),0.f,8.f);
        int level=int(lod),next=std::min(8,level+1);float lm=lod-level;
        float frame=position*(frames-1);int a=int(frame),b=std::min(frames-1,a+1);float fm=frame-a;
        float warp=mode?amount*8:0;int wa=int(warp),wb=std::min(8,wa+1);float wm=warp-wa;
        auto index=[mode](int w){return w==0?0:1+(mode-1)*8+w-1;};
        auto read=[&](int f,int w){const auto& c=cycles[f*25+index(w)];return c.at(phase,level)*(1-lm)+c.at(phase,next)*lm;};
        float first=read(a,wa)*(1-fm)+read(b,wa)*fm;
        if(wm==0)return first;
        return first*(1-wm)+(read(a,wb)*(1-fm)+read(b,wb)*fm)*wm;
    }
};
inline std::unique_ptr<Bank> make(const float* input,int frames,int frameSize){
    if(!input||frames<1||frames>64||(frameSize!=256&&frameSize!=512&&frameSize!=1024&&frameSize!=2048))return nullptr;
    for(int i=0;i<frames*frameSize;i++)if(!std::isfinite(input[i])||std::abs(input[i])>4)return nullptr;
    auto bank=std::make_unique<Bank>();bank->frames=frames;bank->cycles.resize(frames*25);
    for(int f=0;f<frames;f++){
        auto raw=[&](float phase){phase-=std::floor(phase);float x=phase*frameSize;int i=int(x)%frameSize;float m=x-std::floor(x);return input[f*frameSize+i]*(1-m)+input[f*frameSize+(i+1)%frameSize]*m;};
        for(int variant=0;variant<25;variant++){
            int mode=variant?1+(variant-1)/8:0;float amount=variant?float(1+(variant-1)%8)/8:0;
            std::vector<std::complex<float>> spectrum(1024);
            for(int i=0;i<1024;i++){
                float phase=float(i)/1024;
                if(mode==1){float split=.5f+.45f*amount;phase=phase<split?.5f*phase/split:.5f+.5f*(phase-split)/(1-split);}
                if(mode==2)phase*=1+7*amount;
                float value=raw(phase);
                if(mode==3){float x=value*(1+5*amount);float folded=std::fmod(x+1,4.f);if(folded<0)folded+=4;value=1-std::abs(folded-2);}
                spectrum[i]=value;
            }
            fft(spectrum,false);spectrum[0]=0;
            auto& cycle=bank->cycles[f*25+variant];
            for(int level=0;level<9;level++){
                int n=std::max(8,1024>>level),harmonics=256>>level;
                std::vector<std::complex<float>> filtered(n);
                for(int k=1;k<=harmonics;k++){filtered[k]=spectrum[k]*float(n)/1024.f;filtered[n-k]=spectrum[1024-k]*float(n)/1024.f;}
                fft(filtered,true);auto& data=cycle.levels[level];data.resize(n+1);
                for(int i=0;i<n;i++)data[i]=filtered[i].real();data[n]=data[0];
            }
        }
    }
    return bank;
}
inline const std::array<std::unique_ptr<Bank>,24>& factory(){
    static const auto tables=[](){std::array<std::unique_ptr<Bank>,24> result;
        for(int table=0;table<24;table++){
            std::vector<float> data(8*1024);float peak=0;
            for(int frame=0;frame<8;frame++)for(int i=0;i<1024;i++){
                float p=float(i)/1024,t=float(frame)/7,value=0;
                for(int h=1;h<=64;h++){
                    float amp=1/std::pow(float(h),1.05f+.12f*(table%4));
                    switch(table/4){
                        case 0:amp*=std::exp(-h/(2+35*t));if(table%2&&h%2==0)amp*=.15f+.6f*t;break;
                        case 1:{float center=2+table%4+12*t;float z=(h-center)/(1.2f+table%3);amp*=.08f+3*std::exp(-z*z);break;}
                        case 2:amp*=h%(3+table%4)==1?1:.12f+t*.5f;break;
                        case 3:amp*=.25f+.75f*std::abs(std::sin(h*(.4f+t*2+table*.13f)));break;
                        case 4:amp*=std::exp(-h/(3+18*t))*(.4f+.6f*std::cos(h*.3f+table+t*3));break;
                        default:amp*=h<=2+int(t*(3+table%4))?1:.01f;break;
                    }
                    if(h==1)amp+=.35f;
                    float phase=(table/4==2 ? h*h*.013f*(table%4+1)*t:0);
                    value+=amp*std::sin(tau*(h*p+phase));
                }
                data[frame*1024+i]=value;peak=std::max(peak,std::abs(value));
            }
            for(auto& x:data)x*=.85f/std::max(.01f,peak);
            result[table]=make(data.data(),8,1024);
        }return result;
    }();return tables;
}
}
