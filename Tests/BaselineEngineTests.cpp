#include "SynthEngine.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

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

double difference(const std::vector<float>& a, const std::vector<float>& b) {
    double total = 0;
    for (size_t i = 0; i < a.size(); ++i) total += std::abs(a[i] - b[i]);
    return total;
}

std::vector<float> renderHeld(SynthEngine& engine) {
    noteOn(engine, 0, 60);
    std::vector<float> left(kRate / 2), right(kRate / 2);
    engine.render(left.data(), right.data(), static_cast<uint32_t>(left.size()));
    for (float sample : left) require(std::isfinite(sample) && std::abs(sample) <= 1.001f, "LFO upgrade render left the contract");
    return left;
}

void silenceDirectLFOs(SynthEngine& engine) {
    engine.setParameter(0, APLFODepth, 0);
    engine.setParameter(0, APLFO2Depth, 0);
    engine.setParameter(0, APPWMDepth, 0);
}

void modulationUpgradeContract() {
    static_assert(APParameterCount == 126, "LFO 3-5 must extend the parameter list without renumbering it");
    static_assert(APLFORate == 16 && APLFO2Rate == 29 && APWT1Formant == 93, "existing parameter IDs moved");
    static_assert(APLFO3Shape == 99 && APLFO4Shape == 108 && APLFO5Shape == 117 && APLFO5Fade == 125, "new LFO block is not appended");

    SynthEngine fresh;
    configurePlayable(fresh);
    requireNear(fresh.getParameter(0, APLFO3Depth), 1, 0.0001f, "LFO 3 depth does not default to full");
    requireNear(fresh.getParameter(0, APLFO4Depth), 1, 0.0001f, "LFO 4 depth does not default to full");
    requireNear(fresh.getParameter(0, APLFO5Depth), 1, 0.0001f, "LFO 5 depth does not default to full");

    auto held = [](auto&& setup) {
        SynthEngine engine;
        configurePlayable(engine);
        silenceDirectLFOs(engine);
        engine.setParameter(0, APWave1, 3);
        engine.setParameter(0, APBlend, 0);
        engine.setParameter(0, APPulseWidth, 0.5f);
        setup(engine);
        return renderHeld(engine);
    };
    const auto plain = held([](SynthEngine&) {});
    const auto unrouted = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFO3Shape, 2);
        engine.setParameter(0, APLFO3Rate, 8);
        engine.setParameter(0, APLFO3Depth, 1);
    });
    require(difference(plain, unrouted) < 1e-4, "an unrouted LFO 3 changed the audio");

    const auto pitched = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFO3Shape, 2);
        engine.setParameter(0, APLFO3Rate, 8);
        engine.setParameter(0, APLFO3Depth, 1);
        engine.setMatrix(0, 9, true, 6, 1, 4, 1, 1);
    });
    require(difference(plain, pitched) > 1, "LFO 3 in sound-matrix slot 10 did not reach pitch");
    const auto scaled = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFO3Shape, 2);
        engine.setParameter(0, APLFO3Rate, 8);
        engine.setParameter(0, APLFO3Depth, 0);
        engine.setMatrix(0, 9, true, 6, 1, 4, 1, 1);
    });
    require(difference(plain, scaled) < 1e-4, "LFO 3 depth did not scale its matrix route");

    const auto fifthFast = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFO5Shape, 2);
        engine.setParameter(0, APLFO5Rate, 11);
        engine.setParameter(0, APLFO5Depth, 1);
        engine.setMatrix(0, 8, true, 8, 3, 4, 1, 0.8f);
    });
    const auto fifthSlow = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFO5Shape, 2);
        engine.setParameter(0, APLFO5Rate, 0.4f);
        engine.setParameter(0, APLFO5Depth, 1);
        engine.setMatrix(0, 8, true, 8, 3, 4, 1, 0.8f);
    });
    require(difference(fifthFast, fifthSlow) > 1, "LFO 5 aliased onto an earlier LFO");

    const auto width = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFO4Shape, 2);
        engine.setParameter(0, APLFO4Rate, 5);
        engine.setParameter(0, APLFO4Depth, 1);
        engine.setMatrix(0, 0, true, 7, 22, 4, 1, 0.8f);
    });
    require(difference(plain, width) > 0.2, "LFO 4 did not reach the new pulse-width destination");

    const auto depthRoute = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFORate, 7);
        engine.setParameter(0, APLFOShape, 0);
        engine.setParameter(0, APLFODestination, 1);
        engine.setParameter(0, APLFO3Shape, 2);
        engine.setParameter(0, APLFO3Rate, 1.5f);
        engine.setParameter(0, APLFO3Depth, 1);
        engine.setMatrix(0, 1, true, 6, 6, 4, 1, 1);
    });
    const auto depthOff = held([](SynthEngine& engine) {
        engine.setParameter(0, APLFORate, 7);
        engine.setParameter(0, APLFOShape, 0);
        engine.setParameter(0, APLFODestination, 1);
    });
    require(difference(depthRoute, depthOff) > 0.2, "LFO 3 did not modulate LFO 1 depth");

    const auto blocked = held([](SynthEngine& engine) {
        engine.setMatrix(0, 0, true, 0, 9, 4, 1, 1);
        engine.setMatrix(4, 6, true, 0, 1, 4, 1, 1);
    });
    require(difference(plain, blocked) < 1e-4, "a blocked sound or performance route became audible");

    SynthEngine meters;
    configurePlayable(meters);
    silenceDirectLFOs(meters);
    meters.setParameter(0, APLFO3Shape, 3);
    meters.setParameter(0, APLFO3Rate, 4);
    meters.setParameter(0, APLFO3Depth, 1);
    meters.setMatrix(0, 9, true, 6, 1, 4, 1, 0.5f);
    meters.setMatrix(4, 0, true, 0, 1, 4, 1, -0.25f);
    noteOn(meters, 0, 60, 100);
    meters.midi(0, 0xb0, 1, 127);
    renderFinite(meters, kRate / 8);
    std::array<float, 46> feedback{};
    require(meters.copyModulation(feedback.data(), 46) == 46, "modulation meter did not grow to 46 values");
    require(std::abs(feedback[9]) > 0.01f, "sound-matrix slot 10 did not report feedback");
    require(std::abs(feedback[40] + 0.25f) < 0.02f, "performance feedback did not stay at index 40");
    std::puts("PASS baseline: five LFOs, ten sound routes, new destinations, and meter layout");
}
} // namespace

int main() {
    basicAudioContract();
    sampleRateContract();
    routingContract();
    panicDeferredCommitContract();
    panicGenerationContract();
    prepareBoundaryContract();
    modulationUpgradeContract();
    std::puts("PASS baseline: Aurora v1 native DSP contract");
    return 0;
}
