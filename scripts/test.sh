#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
RUN_BRIDGE=false
if [[ "${1:-}" == "--bridge" ]]; then
    RUN_BRIDGE=true
    shift
fi
if [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--bridge]\n' "$0" >&2
    exit 2
fi

if [[ ! -f "$ROOT_DIR/Tests/SynthEngineTests.cpp" ]]; then
    printf 'DSP tests are not present at Tests/SynthEngineTests.cpp.\n' >&2
    exit 1
fi

SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
CLANGXX="$(xcrun --find clang++)"
mkdir -p "$BUILD_DIR/tests" "$BUILD_DIR/ModuleCache"
COMMON_FLAGS=(-std=c++20 -O2 -pthread -target arm64-apple-macosx14.0 -isysroot "$SDK_DIR" -I "$ROOT_DIR/Sources" -fmodules-cache-path="$BUILD_DIR/ModuleCache")

printf 'Compiling and running DSP tests…\n'
"$CLANGXX" "${COMMON_FLAGS[@]}" -c "$ROOT_DIR/Sources/SynthEngine.cpp" \
    -o "$BUILD_DIR/tests/SynthEngine.o"
"$CLANGXX" "${COMMON_FLAGS[@]}" \
    "$BUILD_DIR/tests/SynthEngine.o" "$ROOT_DIR/Tests/SynthEngineTests.cpp" \
    -o "$BUILD_DIR/tests/SynthEngineTests"
"$BUILD_DIR/tests/SynthEngineTests"

"$CLANGXX" "${COMMON_FLAGS[@]}" "$ROOT_DIR/Tests/RecordingChecks.cpp" \
    -framework AudioToolbox -framework CoreFoundation -o "$BUILD_DIR/tests/RecordingChecks"
"$BUILD_DIR/tests/RecordingChecks"

"$CLANGXX" "${COMMON_FLAGS[@]}" "$BUILD_DIR/tests/SynthEngine.o" "$ROOT_DIR/Tests/WavetableTests.cpp" \
    -framework AudioToolbox -framework CoreFoundation -o "$BUILD_DIR/tests/WavetableTests"
"$BUILD_DIR/tests/WavetableTests"

"$CLANGXX" "${COMMON_FLAGS[@]}" "$BUILD_DIR/tests/SynthEngine.o" "$ROOT_DIR/Tests/MotionTests.cpp" -o "$BUILD_DIR/tests/MotionTests"
"$BUILD_DIR/tests/MotionTests"

"$CLANGXX" "${COMMON_FLAGS[@]}" "$BUILD_DIR/tests/SynthEngine.o" "$ROOT_DIR/Tests/LayerToolsTests.cpp" -o "$BUILD_DIR/tests/LayerToolsTests"
"$BUILD_DIR/tests/LayerToolsTests"

if [[ "$RUN_BRIDGE" == true ]]; then
    if [[ ! -f "$ROOT_DIR/Tests/BridgeProbe.cpp" ]]; then
        printf 'Optional device probe is not present at Tests/BridgeProbe.cpp.\n' >&2
        exit 1
    fi
    printf '\nCompiling and running the read-only device probe…\n'
    "$CLANGXX" "${COMMON_FLAGS[@]}" -fobjc-arc -c "$ROOT_DIR/Sources/MacAudioMIDI.mm" \
        -o "$BUILD_DIR/tests/MacAudioMIDI.o"
    "$CLANGXX" "${COMMON_FLAGS[@]}" \
        "$BUILD_DIR/tests/SynthEngine.o" "$BUILD_DIR/tests/MacAudioMIDI.o" "$ROOT_DIR/Tests/BridgeProbe.cpp" \
        -framework Foundation -framework CoreAudio -framework AudioUnit \
        -framework AudioToolbox -framework CoreMIDI \
        -o "$BUILD_DIR/tests/BridgeProbe"
    "$BUILD_DIR/tests/BridgeProbe"
fi
