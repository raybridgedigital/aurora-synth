#pragma once
#include "AuroraBridge.h"
#include <memory>
namespace aurora {
class SynthEngine {
public:
    SynthEngine();
    ~SynthEngine();
    void prepare(double sampleRate); // called only while audio stopped
    void setParameter(int layer,int parameter,float value);
    float getParameter(int layer,int parameter) const;
    void setMatrix(int bank,int slot,bool enabled,int source,int destination,int target,int cc,float amount);
    void setTranspose(int semitones);
    void setGlobal(int parameter,float value);
    float getGlobal(int parameter) const;
    // Thread-safe producer entry points; render consumes events.
    void midi(int32_t sourceID,uint8_t status,uint8_t data1,uint8_t data2);
    void route(int32_t sourceID,int layerMask,int channel);
    void velocityCurve(int32_t sourceID,int curve);
    void hold(bool enabled);
    void clockSource(bool enabled,int32_t sourceID);
    void clock(int32_t sourceID,uint8_t status,double seconds);
    float clockTempo() const;
    void disconnect(int32_t sourceID);
    void panic();
    void render(float *left,float *right,uint32_t frames); // no allocation/locks
    float peak() const;
    int copyScope(float* samples,int capacity) const;
    int copyModulation(float* values,int capacity) const;
    bool setMotion(int layer,const float* data,int count);
    float motionPhase(int layer)const;
    void setLayerSends(int layer,float delay,float reverb);
    void soloLayer(int layer); // -1 clears solo; does not alter patch enable flags
    // Main-thread preparation and preview. Immutable banks are published at render boundaries.
    bool setCustomWavetable(int layer,int oscillator,const float* samples,int frames,int frameSize);
    void clearCustomWavetable(int layer,int oscillator);
    int copyWavetablePreview(int layer,int oscillator,float* samples,int capacity) const;
    static const char* wavetableName(int index);
    static const char* wavetableCategory(int index);
    int activeVoices() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
}
