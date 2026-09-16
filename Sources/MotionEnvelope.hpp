#pragma once
#include <array>
#include <algorithm>
#include <cmath>

namespace aurora {
// Packet: enabled, loop, seconds, point count; 16 (time,value,curve) points;
// eight (enabled,minimum,maximum,inverted) routes. Main-thread publisher only.
constexpr int motionSize=85; // final value: beats per cycle, 0 = seconds
struct MotionEnvelope {
    std::array<float,motionSize> data{};
    bool enabled()const{return data[0]>.5f;}
    bool routed(int destination)const{return enabled()&&data[52+destination*4]>.5f;}
    float shape(float phase)const {
        int count=int(data[3]);if(count<2)return 0;
        phase=std::clamp(phase,0.f,1.f);
        for(int i=1;i<count;i++)if(phase<=data[4+i*3]){
            int a=4+(i-1)*3,b=a+3;
            float t=std::clamp((phase-data[a])/(data[b]-data[a]),0.f,1.f);
            t=std::pow(t,std::exp2(data[a+2]*3));
            return data[a+1]+(data[b+1]-data[a+1])*t;
        }
        return data[4+(count-1)*3+1];
    }
    float value(int destination,float shape)const {
        int base=52+destination*4;float t=data[base+3]>.5f?1-shape:shape;
        float low=data[base+1],high=data[base+2];
        return destination==1?low*std::pow(high/low,t):low+(high-low)*t;
    }
    static bool valid(const float* p,int count){
        if(!p||(count!=motionSize&&count!=84))return false;
        for(int i=0;i<count;i++)if(!std::isfinite(p[i]))return false;
        if(count==85 && p[84]!=0 && (p[84]<.25f||p[84]>32))return false;
        auto flag=[](float v){return v==0||v==1;};
        if(!flag(p[0])||!flag(p[1])||p[2]<.1f||p[2]>60||p[3]<2||p[3]>16||p[3]!=std::floor(p[3]))return false;
        int points=int(p[3]);
        if(p[4]!=0||p[4+(points-1)*3]!=1)return false;
        for(int i=0;i<points;i++){
            int b=4+i*3;
            if(p[b]<0||p[b]>1||p[b+1]<0||p[b+1]>1||std::abs(p[b+2])>1)return false;
            if(i&&p[b]-p[b-3]<.0001f)return false;
        }
        for(int i=0;i<8;i++){
            int b=52+i*4;float lo=i==1?30:i==2?-24:i==3?-1:0,hi=i==1?18000:i==2?24:1;
            if(!flag(p[b])||!flag(p[b+3])||p[b+1]<lo||p[b+2]>hi||p[b+1]>p[b+2])return false;
        }
        return true;
    }
};
}
