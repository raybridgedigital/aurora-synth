#pragma once
#include "SynthEngine.hpp"
#include "PluginParameters.hpp"
#include <array>
#include <atomic>
#include <functional>
#include <memory>
#include <string>
namespace auroraPlugin {
constexpr int globalBase=1000,macroBase=2000,xyX=2010,xyY=2011,transposeID=2012,holdID=2013,sendBase=2020,midiBase=3000;
constexpr int routeMaskID=2030,routeChannelID=2031,velocityID=2032;
constexpr int outputGainID=2040;
// Keep every v0.16 parameter ID stable. New layer controls occupy a separate block.
constexpr int layerID(int l,int p){return p<58?l*58+p:6000+l*128+p-58;}
constexpr int parameterForID(int id){return id>=0&&id<232?id%58:id>=6000&&id<6512&&(id-6000)%128<APParameterCount-58?(id-6000)%128+58:-1;}
constexpr int layerForID(int id){return id<232?id/58:(id-6000)/128;}
struct MacroRoute {std::atomic<int> target{-1};std::atomic<float> from{0},to{1};};
class Core {
public:
    Core();~Core();
    aurora::SynthEngine engine;
    std::array<std::atomic<float>,8192> values{};
    std::array<std::array<MacroRoute,16>,8> macroRoutes;
    std::array<std::atomic<int>,8> macroCounts{};
    std::array<std::atomic<double>,8> storageLegacy{};
    std::array<std::atomic<int>,2> xyMacros{};
    std::array<std::atomic<float>,2> xyStarts{},xyEnds{};
    std::atomic<uint64_t> revision{1},midiEvents{0};
    std::atomic<uint64_t> ccEvents{0},lastCC{UINT64_MAX},mappingRevision{1};
    std::array<std::atomic<int>,2048> learnedTargets{};
    std::array<float,2048> previousCC{};
    std::array<bool,2048> pickedUp{};
    uint64_t appliedMappingRevision=0;
    std::atomic<double> sampleRate{48000},tempo{110};
    std::atomic<uint32_t> blockSize{512};
    std::atomic<bool> active{false};
    std::atomic<float> cpu{0};
    std::function<void(int,double)> notify;
    std::function<void()> stateChanged;
    void setActual(int id,double value,bool fromUI=false);
    void setNormalized(int id,double value,bool fromUI=false);
    double normalized(int id)const;
    static Spec spec(int id);
    static double actual(int id,double normalized);
    static double normalize(int id,double actual);
    void prepare(double rate);
    void midi(int status,int a,int b);
    std::string patchJSON();
    bool setPatchJSON(const char* json,bool apply);
    std::string saveState();
    bool restoreState(const char* json);
    bool setMappingsJSON(const char* json,bool apply=true);
    std::string mappingsJSON();
    std::string resourceDirectory();
private:
    struct Storage;std::unique_ptr<Storage> storage;
    void configureMetadata();
    void macro(int index,double value);
};
}
