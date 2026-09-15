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
    void disconnect(int32_t sourceID);
    void panic();
    void render(float *left,float *right,uint32_t frames); // no allocation/locks
    float peak() const;
    int copyScope(float* samples,int capacity) const;
    int activeVoices() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
}
