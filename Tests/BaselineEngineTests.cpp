#include "SynthEngine.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>

using aurora::SynthEngine;

namespace {
constexpr int kRate = 48000;

[[noreturn]] void fail(const std::string& message) {
    std::fprintf(stderr, "BASELINE FAIL: %s\n", message.c_str());
    std::fflush(stderr);
    std::exit(1);
}

void require(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

void requireNear(float actual, float expected, float epsilon, const std::string& message) {
    if (!std::isfinite(actual) || std::abs(actual - expected) > epsilon) {
        fail(message + " (actual=" + std::to_string(actual) + ", expected=" + std::to_string(expected) + ")");
    }
}

float renderFinite(SynthEngine& engine, int frames) {
    std::array<float, 257> left{}, right{};
    float peak = 0.0f;
    while (frames > 0) {
        const int count = std::min(frames, static_cast<int>(left.size()));
        engine.render(left.data(), right.data(), static_cast<uint32_t>(count));
        for (int i = 0; i < count; ++i) {
            require(std::isfinite(left[i]) && std::isfinite(right[i]), "render produced NaN/Inf");
            require(std::abs(left[i]) <= 1.001f && std::abs(right[i]) <= 1.001f,
                    "render escaped the bounded output contract");
            peak = std::max(peak, std::max(std::abs(left[i]), std::abs(right[i])));
        }
        frames -= count;
    }
    return peak;
}

void configurePlayable(SynthEngine& engine, double sampleRate = kRate) {
    engine.prepare(sampleRate);
    engine.setGlobal(AGMaster, 0.65f);
    engine.setGlobal(AGDelayMix, 0.0f);
    engine.setGlobal(AGReverbMix, 0.0f);
    engine.setGlobal(AGChorusMix, 0.0f);
    engine.setParameter(0, APEnabled, 1.0f);
    engine.setParameter(0, APAttack, 0.003f);
    engine.setParameter(0, APRelease, 0.025f);
}

void noteOn(SynthEngine& engine, int32_t source, int note, int velocity = 100, int channel = 0) {
    engine.midi(source, static_cast<uint8_t>(0x90 | channel), static_cast<uint8_t>(note), static_cast<uint8_t>(velocity));
}

void noteOff(SynthEngine& engine, int32_t source, int note, int channel = 0) {
    engine.midi(source, static_cast<uint8_t>(0x80 | channel), static_cast<uint8_t>(note), 0);
}

void basicAudioContract() {
    SynthEngine engine;
    configurePlayable(engine);
    noteOn(engine, 0, 60);
    const float peak = renderFinite(engine, kRate / 10);
    require(peak > 0.0005f, "normal note did not produce audible output");
    require(engine.activeVoices() > 0, "normal note did not create an active voice");
    noteOff(engine, 0, 60);
    renderFinite(engine, kRate / 4);
    require(engine.activeVoices() == 0, "released note left a stuck voice");
    std::puts("PASS baseline: normal note renders finite bounded audio and releases");
}

void sampleRateContract() {
    for (const int rate : {44100, 48000, 96000, 192000}) {
        SynthEngine engine;
        configurePlayable(engine, rate);
        noteOn(engine, 0, 64);
        require(renderFinite(engine, rate / 25) > 0.0001f,
                "note failed at supported sample rate " + std::to_string(rate));
        noteOff(engine, 0, 64);
        renderFinite(engine, rate / 4);
        require(engine.activeVoices() == 0,
                "voice did not release at supported sample rate " + std::to_string(rate));
    }
    std::puts("PASS baseline: 44.1/48/96/192 kHz render safely");
}

void routingContract() {
    SynthEngine engine;
    configurePlayable(engine);
    engine.setParameter(1, APEnabled, 1.0f);
    engine.setParameter(1, APAttack, 0.003f);
    engine.setParameter(1, APRelease, 0.025f);

    // Source 808 -> layer B only, MIDI channel 2 only.
    engine.route(808, 2, 2);
    renderFinite(engine, 64);

    noteOn(engine, 808, 60, 100, 0); // MIDI channel 1: must be ignored.
    renderFinite(engine, kRate / 40);
    require(engine.activeVoices() == 0, "routing accepted a note from the wrong channel");

    noteOn(engine, 808, 60, 100, 1); // MIDI channel 2.
    require(renderFinite(engine, kRate / 20) > 0.0001f, "routing rejected the configured source/channel");
    require(engine.activeVoices() == 1, "routing did not isolate the note to layer B");
    noteOff(engine, 808, 60, 1);
    renderFinite(engine, kRate / 4);
    require(engine.activeVoices() == 0, "routed note left a stuck voice");
    std::puts("PASS baseline: source/layer/channel routing contract");
}

void panicDeferredCommitContract() {
    SynthEngine engine;
    configurePlayable(engine);
    engine.setParameter(0, APRelease, 0.02f);
    engine.setGlobal(AGMaster, 0.80f);

    noteOn(engine, 0, 60);
    renderFinite(engine, kRate / 20);
    require(engine.activeVoices() > 0, "precondition failed: Panic test has no active voice");

    engine.panic();
    engine.setParameter(0, APRelease, 0.31f);
    engine.setGlobal(AGMaster, 0.31f);

    requireNear(engine.getParameter(0, APRelease), 0.02f, 0.0001f,
                "Panic exposed deferred layer write before silent boundary");
    requireNear(engine.getGlobal(AGMaster), 0.80f, 0.0001f,
                "Panic exposed deferred global write before silent boundary");

    // Minimum fade-out is ~100 ms. At 50 ms the live state must still be old.
    renderFinite(engine, static_cast<int>(kRate * 0.05));
    requireNear(engine.getParameter(0, APRelease), 0.02f, 0.0001f,
                "Panic committed layer write during fade-out");
    requireNear(engine.getGlobal(AGMaster), 0.80f, 0.0001f,
                "Panic committed global write during fade-out");

    // 300 ms total crosses even the energy-extended fade and the silent commit boundary.
    renderFinite(engine, static_cast<int>(kRate * 0.25));
    requireNear(engine.getParameter(0, APRelease), 0.31f, 0.0001f,
                "Panic did not commit deferred layer write at the silent boundary");
    requireNear(engine.getGlobal(AGMaster), 0.31f, 0.0001f,
                "Panic did not commit deferred global write at the silent boundary");

    renderFinite(engine, static_cast<int>(kRate * 0.20));
    require(engine.activeVoices() == 0, "Panic recovery left an active voice");
    require(renderFinite(engine, kRate / 20) < 1e-6f, "Panic recovery did not return to silence");

    noteOn(engine, 0, 67);
    require(renderFinite(engine, kRate / 20) > 0.0001f, "engine did not recover for new notes after Panic");
    noteOff(engine, 0, 67);
    renderFinite(engine, kRate / 4);
    std::puts("PASS baseline: Panic defers writes, commits at silence, clears voices, and recovers");
}

void panicGenerationContract() {
    SynthEngine engine;
    configurePlayable(engine);

    // Reserve/publish a note before Panic. Generation tagging must prevent it
    // from becoming a post-Panic voice when the render thread catches up.
    noteOn(engine, 77, 62);
    engine.panic();
    renderFinite(engine, static_cast<int>(kRate * 0.45));
    require(engine.activeVoices() == 0, "pre-Panic queued event survived into the new generation");
    require(renderFinite(engine, kRate / 20) < 1e-6f, "generation reset did not settle to silence");

    noteOn(engine, 77, 65);
    require(renderFinite(engine, kRate / 20) > 0.0001f, "new-generation MIDI did not work after Panic");
    noteOff(engine, 77, 65);
    renderFinite(engine, kRate / 4);
    std::puts("PASS baseline: Panic rejects stale queued MIDI but accepts new-generation MIDI");
}

void prepareBoundaryContract() {
    SynthEngine engine;
    configurePlayable(engine);
    engine.setParameter(0, APRelease, 0.02f);
    engine.setGlobal(AGMaster, 0.75f);

    engine.panic();
    engine.setParameter(0, APRelease, 0.19f);
    engine.setGlobal(AGMaster, 0.41f);

    // prepare() runs only while audio is stopped, so it is a valid silent hard-reset boundary.
    engine.prepare(44100);
    requireNear(engine.getParameter(0, APRelease), 0.19f, 0.0001f,
                "prepare() lost deferred layer state");
    requireNear(engine.getGlobal(AGMaster), 0.41f, 0.0001f,
                "prepare() lost deferred global state");
    require(engine.activeVoices() == 0, "prepare() did not clear performance state");

    noteOn(engine, 0, 69);
    require(renderFinite(engine, 44100 / 20) > 0.0001f, "engine did not render after prepare() boundary");
    noteOff(engine, 0, 69);
    renderFinite(engine, 44100 / 4);
    std::puts("PASS baseline: prepare() commits deferred state at a silent hard-reset boundary");
}
} // namespace

int main() {
    basicAudioContract();
    sampleRateContract();
    routingContract();
    panicDeferredCommitContract();
    panicGenerationContract();
    prepareBoundaryContract();
    std::puts("PASS baseline: Aurora v1 native DSP contract");
    return 0;
}
