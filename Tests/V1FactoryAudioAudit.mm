#import <Foundation/Foundation.h>
#include "SynthEngine.hpp"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <vector>

// Aurora v1 generic factory-bank audio audit. No audio device is opened or MIDI hardware touched.
// Derived from the historical PatchBankAudit, but current architecture is authoritative:
// bank sizes/categories are not hard-coded, session EQ (globals 20...22) is not patch data,
// and preset XY/custom-macro semantics are tested by the model regression suite instead.
// Build:
// xcrun clang++ -std=c++20 -O2 -fobjc-arc Sources/SynthEngine.cpp \
//   Tests/PatchBankAudit.mm -framework Foundation -I Sources -o build/patch-audit
// Run: build/patch-audit Resources/Aurora100.json build/patch-audit-report.json

namespace {
constexpr double sampleRate = 48000;
constexpr uint32_t blockSize = 256;
constexpr uint64_t fnvOffset = 14695981039346656037ULL;
constexpr uint64_t fnvPrime = 1099511628211ULL;

bool number(id value, double& result) {
    if (![value isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return false;
    result = [value doubleValue];
    return std::isfinite(result) && std::abs(result) <= std::numeric_limits<float>::max();
}

bool closeEnough(double a, double b) {
    return std::abs(a-b) <= 0.000001 * std::max(1.0, std::abs(a));
}

NSString *stringField(NSDictionary *patch, NSString *key, NSMutableArray *errors) {
    id value = patch[key];
    if (![value isKindOfClass:[NSString class]] ||
        [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        [errors addObject:[NSString stringWithFormat:@"%@ must be a nonempty string", key]];
        return @"";
    }
    return value;
}

struct AudioStats {
    double peak = 0;
    long double squareSum = 0;
    uint64_t samples = 0;
    uint64_t hash = fnvOffset;
    bool finite = true;
    int maxVoices = 0;

    void accept(float left, float right) {
        for (float sample : {left, right}) {
            if (!std::isfinite(sample)) { finite = false; continue; }
            peak = std::max(peak, std::abs(double(sample)));
            squareSum += double(sample) * double(sample);
            ++samples;
            // Canonical little-endian 24-bit quantization in a 32-bit word.
            // Hashing is deterministic without depending on native float bytes.
            int32_t quantized = int32_t(std::llround(std::clamp(double(sample), -1.0, 1.0) * 8388607));
            uint32_t bits = uint32_t(quantized);
            for (int byte = 0; byte < 4; ++byte) {
                hash ^= (bits >> (byte * 8)) & 0xff;
                hash *= fnvPrime;
            }
        }
    }

    double rms() const { return samples ? std::sqrt(double(squareSum / samples)) : 0; }
};

AudioStats render(aurora::SynthEngine& engine, double seconds) {
    std::array<float, blockSize> left{}, right{};
    uint64_t remaining = uint64_t(std::llround(seconds * sampleRate));
    AudioStats stats;
    while (remaining) {
        uint32_t frames = uint32_t(std::min<uint64_t>(remaining, blockSize));
        engine.render(left.data(), right.data(), frames);
        stats.maxVoices = std::max(stats.maxVoices, engine.activeVoices());
        for (uint32_t i = 0; i < frames; ++i) stats.accept(left[i], right[i]);
        remaining -= frames;
    }
    return stats;
}

bool checkPanic(aurora::SynthEngine& engine, NSMutableArray *errors) {
    // Panic is a mute-bus fade (~100–200 ms) then wipe at silence, not an instant hard cut.
    engine.panic();
    (void)render(engine, 0.40); // drain fade + hold wipe
    auto stats = render(engine, double(blockSize)/sampleRate);
    bool passed = stats.finite && stats.peak == 0 && engine.activeVoices() == 0;
    if (!passed) [errors addObject:@"Panic did not reach silence after mute-bus fade (voices/FX should be clear)"];
    return passed;
}

std::vector<int> auditionNotes(NSString *category) {
    NSString *lower = category.lowercaseString;
    if ([lower hasPrefix:@"bass"]) return {48};
    if ([lower hasPrefix:@"lead"]) return {60};
    // The lower and upper notes also exercise both sides of split programs.
    return {48, 60, 64, 67};
}

void notes(aurora::SynthEngine& engine, const std::vector<int>& keys, bool on, int velocity = 100) {
    for (int key : keys) engine.midi(0, on ? 0x90 : 0x80, uint8_t(key), on ? uint8_t(velocity) : 0);
}

bool loadPatch(NSDictionary *patch, aurora::SynthEngine& engine, NSMutableArray *errors,
               double& maximumRelease, int& enabledLayers) {
    id layers = patch[@"layers"];
    if (![layers isKindOfClass:[NSArray class]] || [layers count] != 4) {
        [errors addObject:@"Exactly four layers are required"];
        return false;
    }
    for (int layer = 0; layer < 4; ++layer) {
        id entry = layers[layer];
        id values = [entry isKindOfClass:[NSDictionary class]] ? entry[@"values"] : nil;
        if (![values isKindOfClass:[NSDictionary class]]) {
            [errors addObject:[NSString stringWithFormat:@"Layer %d values must be an object", layer]];
            continue;
        }
        // Match SynthModel.sanitized: sparse/older layer dictionaries are valid as long as
        // every stored key is within the current range. Missing extension parameters use
        // LayerPatch.initial defaults. GB109 is a 0...96 bank, so 97/98 default to zero.
        bool legacyRate = values[@"97"] == nil;
        for (NSString *storedKey in values) {
            NSInteger storedParameter = storedKey.integerValue;
            double storedValue;
            if (storedParameter < 0 || storedParameter >= APParameterCount || !number(values[storedKey], storedValue)) {
                [errors addObject:[NSString stringWithFormat:@"Layer %d has invalid parameter %@", layer, storedKey]];
            }
        }
        for (int parameter = 0; parameter < APParameterCount; ++parameter) {
            NSString *key = [NSString stringWithFormat:@"%d", parameter];
            id raw = values[key];
            double value = 0;
            if (!raw) {
                // Current LayerPatch.initial defaults for extension fields that can be absent.
                switch (parameter) {
                    case 34: value = 0.5; break;
                    case 36: value = 1; break;
                    case 37: value = 8; break;
                    case 38: value = 0.6; break;
                    case 43: value = 2; break;
                    case 60: value = 3200; break;
                    case 63: value = 0.5; break;
                    case 64: value = 0.01; break;
                    case 65: value = 0.35; break;
                    case 67: value = 0.35; break;
                    case 72: value = 1; break;
                    case 74: value = 0.25; break;
                    case 75: value = 1; break;
                    case 76: value = 0.5; break;
                    case 77: value = 12; break;
                    case 78: value = 1; break;
                    case 82: value = 4; break;
                    case 88: value = 4; break;
                    default:
                        if (parameter >= 99) {
                            int rel = (parameter - 99) % 9;
                            if (rel == 1 || rel == 2) value = 1;
                            else if (rel == 4) value = 4;
                            else value = 0;
                        } else value = 0;
                        break;
                }
            } else if (!number(raw, value)) {
                [errors addObject:[NSString stringWithFormat:@"Layer %d parameter %d must be a finite number", layer, parameter]];
                continue;
            }
            if (legacyRate && parameter == 23) {
                // Same migration as SynthModel.sanitized:
                // old 0,1,2,3 divisions -> current 0,1,3,5.
                static const double map[4] = {0,1,3,5};
                int index = int(std::llround(value));
                if (index >= 0 && index < 4) value = map[index];
            }
            engine.setParameter(layer, parameter, float(value));
            if (!closeEnough(value, engine.getParameter(layer, parameter)))
                [errors addObject:[NSString stringWithFormat:@"Layer %d parameter %d is out of range or nonintegral: %.8g", layer, parameter, value]];
        }
        if (engine.getParameter(layer, APKeyLow) > engine.getParameter(layer, APKeyHigh))
            [errors addObject:[NSString stringWithFormat:@"Layer %d has an inverted key range", layer]];
        if (engine.getParameter(layer, APEnabled) > 0.5f) {
            ++enabledLayers;
            maximumRelease = std::max(maximumRelease, double(engine.getParameter(layer, APRelease)));
        }
    }
    if (enabledLayers == 0) [errors addObject:@"At least one layer must be enabled"];
    id globals = patch[@"globals"];
    if (![globals isKindOfClass:[NSArray class]] || [globals count] != 6)
        [errors addObject:@"Exactly six global values are required"];
    else for (int parameter = 0; parameter < 6; ++parameter) {
        double value;
        if (!number(globals[parameter], value)) {
            [errors addObject:[NSString stringWithFormat:@"Global %d must be a finite number", parameter]];
            continue;
        }
        engine.setGlobal(parameter, float(value));
        if (!closeEnough(value, engine.getGlobal(parameter)))
            [errors addObject:[NSString stringWithFormat:@"Global %d is out of range: %.8g", parameter, value]];
    }
    if(patch[@"phaserMix"])engine.setGlobal(AGPhaserMix,[patch[@"phaserMix"] floatValue]);
    NSDictionary *fx=patch[@"fx"];
    for(NSString *key in fx){
        double value;int parameter=key.intValue;
        if(parameter<7||parameter>=AGGlobalCount||!number(fx[key],value)){[errors addObject:@"Invalid extended FX value"];continue;}
        if(parameter>=20 && parameter<=22)continue; // session-sticky house EQ
        engine.setGlobal(parameter,float(value));
        if(!closeEnough(value,engine.getGlobal(parameter)))[errors addObject:@"Extended FX value out of range"];
    }
    for(int bank=0;bank<5;bank++){
        NSArray *rows=bank==4?patch[@"performanceMatrix"]:(patch[@"soundMatrix"]?patch[@"soundMatrix"][bank]:nil);
        if(!rows)continue;
        if(rows.count!=6 && rows.count!=10){[errors addObject:@"Matrix must contain six or ten slots"];continue;}
        for(NSUInteger slot=0;slot<rows.count;slot++){
            NSDictionary *r=rows[slot];
            engine.setMatrix(bank,slot,[r[@"enabled"] boolValue],[r[@"source"] intValue],[r[@"destination"] intValue],[r[@"target"] intValue],[r[@"cc"] intValue],[r[@"amount"] floatValue]);
        }
    }
    NSArray *motion=patch[@"motion"], *sends=patch[@"sends"];
    if(motion && motion.count!=4)[errors addObject:@"Motion must describe four layers"];
    if(sends && sends.count!=4)[errors addObject:@"Sends must describe four layers"];
    for(int layer=0;layer<4;layer++){
        if(motion.count==4){
            NSDictionary *m=motion[layer];NSArray *points=m[@"points"],*routes=m[@"routes"];
            if(points.count<2 || points.count>16 || routes.count!=8){[errors addObject:@"Invalid motion dimensions"];continue;}
            std::array<float,85> packet{};
            packet[0]=[m[@"enabled"] boolValue];packet[1]=[m[@"loop"] boolValue];packet[2]=[m[@"seconds"] floatValue];packet[3]=points.count;
            for(NSUInteger i=0;i<points.count;i++){packet[4+i*3]=[points[i][@"x"] floatValue];packet[5+i*3]=[points[i][@"y"] floatValue];packet[6+i*3]=[points[i][@"curve"] floatValue];}
            for(int i=0;i<8;i++){packet[52+i*4]=[routes[i][@"enabled"] boolValue];packet[53+i*4]=[routes[i][@"minimum"] floatValue];packet[54+i*4]=[routes[i][@"maximum"] floatValue];packet[55+i*4]=[routes[i][@"inverted"] boolValue];}
            if([m[@"beats"] isKindOfClass:[NSNumber class]])packet[84]=[m[@"beats"] floatValue];
            if(!engine.setMotion(layer,packet.data(),packet.size()))[errors addObject:@"DSP rejected motion settings"];
        }
        if(sends.count==4){float rev=[sends[layer][@"reverb"] floatValue];id sh=sends[layer][@"shimmer"];engine.setLayerSends(layer,[sends[layer][@"delay"] floatValue],rev,sh?[sh floatValue]:rev);}
    }
    id macros = patch[@"macros"];
    if (![macros isKindOfClass:[NSArray class]] || [macros count] != 8)
        [errors addObject:@"Exactly eight macro values are required"];
    else for (int macro = 0; macro < 8; ++macro) {
        double value;
        if (!number(macros[macro], value) || value < 0 || value > 1)
            [errors addObject:[NSString stringWithFormat:@"Macro %d must be a finite number in 0...1", macro]];
    }
    return errors.count == 0;
}

void applyCustomMacro(NSDictionary *patch,aurora::SynthEngine& engine,int index,double position){
    NSDictionary *macro=patch[@"customMacros"][[NSString stringWithFormat:@"%d",index]];
    for(NSDictionary *r in macro[@"routes"]){
        int layer=[r[@"target"][@"layer"] intValue],p=[r[@"target"][@"parameter"] intValue];
        double n=[r[@"from"] doubleValue]+([r[@"to"] doubleValue]-[r[@"from"] doubleValue])*position;
        double lo=0,hi=1;
        bool logarithmic=false;
        if(layer>=0){
            switch(p){
                case 7:lo=30;hi=18000;logarithmic=true;break;
                case 9:lo=.001;hi=8;logarithmic=true;break;
                case 10:lo=.01;hi=8;logarithmic=true;break;
                case 12:lo=.01;hi=12;logarithmic=true;break;
                case 16:case 29:lo=.03;hi=20;logarithmic=true;break;
                case 14:case 20:lo=-1;hi=1;break;
                case 34:lo=.05;hi=.95;break;
            }
        }else{
            switch(p){case 2:case 5:hi=.6;break;case 3:case 4:hi=.75;break;case 7:case 10:lo=.03;hi=5;break;case 13:lo=.2;hi=8;break;}
        }
        double actual=logarithmic?lo*std::pow(hi/lo,n):lo+(hi-lo)*n;
        if(layer<0)engine.setGlobal(p,actual);else engine.setParameter(layer,p,actual);
    }
}
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            std::fprintf(stderr, "Usage: %s BANK.json REPORT.json\n", argv[0]);
            return 2;
        }
        const auto started = std::chrono::steady_clock::now();
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:@(argv[1]) options:0 error:&error];
        id decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        if (![decoded isKindOfClass:[NSArray class]]) {
            std::fprintf(stderr, "Cannot load preset array: %s\n", error ? error.localizedDescription.UTF8String : "expected a JSON array");
            return 2;
        }
        NSArray *bank = decoded;
        NSMutableArray *bankErrors = [NSMutableArray array];
        NSMutableArray *results = [NSMutableArray array];
        NSMutableSet *ids = [NSMutableSet set], *names = [NSMutableSet set];
        NSMutableDictionary *categories = [NSMutableDictionary dictionary];
        NSMutableDictionary *hashes = [NSMutableDictionary dictionary];
        NSUInteger failed = 0;
        double highestPeak = 0, highestStressPeak = 0, lowestRMS = std::numeric_limits<double>::max();
        for (NSUInteger index = 0; index < bank.count; ++index) {
            @autoreleasepool {
                NSMutableArray *errors = [NSMutableArray array], *warnings = [NSMutableArray array];
                id entry = bank[index];
                NSDictionary *patch = [entry isKindOfClass:[NSDictionary class]] ? entry : @{};
                NSString *identifier = stringField(patch, @"id", errors);
                NSString *name = stringField(patch, @"name", errors);
                NSString *category = stringField(patch, @"category", errors);
                stringField(patch, @"detail", errors);
                if ([ids containsObject:identifier]) [errors addObject:@"Duplicate preset ID"];
                if ([names containsObject:name.lowercaseString]) [errors addObject:@"Duplicate preset name (case insensitive)"];
                [ids addObject:identifier]; [names addObject:name.lowercaseString];
                categories[category] = @([categories[category] unsignedIntegerValue] + 1);
                NSMutableDictionary *result = [@{@"id":identifier, @"name":name, @"category":category,
                    @"errors":errors, @"warnings":warnings} mutableCopy];
                aurora::SynthEngine engine;
                double maximumRelease = 0;
                int enabledLayers = 0;
                if (loadPatch(patch, engine, errors, maximumRelease, enabledLayers)) {
                    engine.prepare(sampleRate);
                    auto keys = auditionNotes(category);
                    notes(engine, keys, true);
                    auto hold = render(engine, 4);
                    notes(engine, keys, false);
                    auto release = render(engine, 8);
                    int finalVoices = engine.activeVoices();
                    double peak = std::max(hold.peak, release.peak);
                    if (!hold.finite || !release.finite) [errors addObject:@"Nonfinite audition output"];
                    if (hold.rms() < 0.0001) [errors addObject:@"Audition RMS below 0.0001: silent or nearly silent patch"];
                    if (peak > 0.98) [errors addObject:@"Audition peak above 0.98"];
                    // The engine release reaches -80 dB at APRelease seconds and
                    // retires a voice at -100 dB: allow the documented 1.25× tail.
                    if (finalVoices > 0) {
                        if (maximumRelease * 1.26 < 8)
                            [errors addObject:@"Active voices remain beyond the expected release interval"];
                        else [warnings addObject:@"Long release still has active voices after eight seconds"];
                    }
                    bool panicPassed = checkPanic(engine, errors);
                    engine.setGlobal(AGMaster,1); // Worst-case user listening level, preserved across patch changes.
                    std::vector<int> stressNotes = {36, 43, 48, 55, 60, 64, 67, 72};
                    notes(engine, stressNotes, true, 127);
                    auto stress = render(engine, 8);
                    notes(engine, stressNotes, false);
                    if (!stress.finite) [errors addObject:@"Nonfinite stress output"];
                    if (stress.peak > 0.98) [errors addObject:@"Eight-note stress peak above 0.98"];
                    panicPassed = checkPanic(engine, errors) && panicPassed;
                    // Macro/XY behavior is covered by the current SynthModel regression suite.
                    NSString *hash = [NSString stringWithFormat:@"%016llx", (unsigned long long)hold.hash];
                    NSMutableArray *same = hashes[hash];
                    if (!same) { same = [NSMutableArray array]; hashes[hash] = same; }
                    [same addObject:identifier];
                    [result addEntriesFromDictionary:@{
                        @"enabledLayers":@(enabledLayers),
                        @"peak":@(peak), @"rms":@(hold.rms()), @"releaseRMS":@(release.rms()),
                        @"stressPeak":@(stress.peak), @"stressMaxVoices":@(stress.maxVoices),
                        @"renderHash":hash, @"activeVoicesAfterRelease":@(finalVoices),
                        @"activeVoicesAfterPanic":@(engine.activeVoices()), @"panicPassed":@(panicPassed)}];
                    NSMutableArray *auditionKeys = [NSMutableArray array];
                    for (int key : keys) [auditionKeys addObject:@(key)];
                    result[@"auditionNotes"] = auditionKeys;
                    highestPeak = std::max(highestPeak, peak);
                    highestStressPeak = std::max(highestStressPeak, stress.peak);
                    lowestRMS = std::min(lowestRMS, hold.rms());
                }
                result[@"passed"] = @(errors.count == 0);
                if (errors.count) ++failed;
                [results addObject:result];
                if ((index + 1) % 10 == 0 || errors.count) {
                    std::printf("Audited %lu/%lu: %s%s\n", (unsigned long)(index + 1),
                        (unsigned long)bank.count, name.UTF8String, errors.count ? " [FAILED]" : "");
                    std::fflush(stdout);
                }
            }
        }
        NSMutableArray *duplicates = [NSMutableArray array];
        for (NSString *hash in hashes) if ([hashes[hash] count] > 1)
            [duplicates addObject:@{@"renderHash":hash, @"presetIDs":hashes[hash]}];
        double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count();
        bool passed = failed == 0 && bankErrors.count == 0;
        NSDictionary *report = @{
            @"passed":@(passed), @"patchCount":@(bank.count), @"failedPatches":@(failed),
            @"sampleRate":@(sampleRate), @"holdSeconds":@4, @"releaseSeconds":@8, @"stressSeconds":@8,
            @"stressVelocity":@127, @"categoryCounts":categories, @"bankErrors":bankErrors,
            @"highestPeak":@(highestPeak), @"highestStressPeak":@(highestStressPeak),
            @"lowestHoldRMS":@(lowestRMS == std::numeric_limits<double>::max() ? 0 : lowestRMS),
            @"elapsedSeconds":@(elapsed), @"possibleDuplicateRenders":duplicates, @"patches":results,
            @"method":@"48 kHz stereo; four-second category-appropriate held phrase at velocity 100; eight-second release; eight notes at velocity 127 and Master 100% for eight seconds so slow attacks also reach full level; current patch FX (excluding session EQ) and modulation matrices enabled; Panic verification (mute-bus fade then wipe). FNV-1a hash of 24-bit quantized held audio. Identical renders are reported for review, not automatically rejected."};
        NSData *reportData = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
        if (!reportData || ![reportData writeToFile:@(argv[2]) options:NSDataWritingAtomic error:&error]) {
            std::fprintf(stderr, "Cannot write report: %s\n", error.localizedDescription.UTF8String);
            return 2;
        }
        std::printf("%s: %lu patches, %lu categories, %lu failed patches, %lu bank errors, %lu possible duplicate renders. Peak %.6f; stress peak %.6f; lowest RMS %.6f. %.2f seconds. Report: %s\n",
            passed ? "PASS" : "FAIL", (unsigned long)bank.count, (unsigned long)categories.count,
            (unsigned long)failed, (unsigned long)bankErrors.count, (unsigned long)duplicates.count,
            highestPeak, highestStressPeak, lowestRMS == std::numeric_limits<double>::max() ? 0 : lowestRMS, elapsed, argv[2]);
        return passed ? 0 : 1;
    }
}
