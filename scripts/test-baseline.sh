#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/baseline"
SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
CLANGXX="$(xcrun --find clang++)"
TARGET="${AURORA_TEST_TARGET:-arm64-apple-macosx14.0}"
OPTIMIZATION="-O2"
SANITIZER_FLAGS=()

case "${AURORA_SANITIZER:-none}" in
    none|"") ;;
    address-undefined)
        OPTIMIZATION="-O1"
        SANITIZER_FLAGS=(-g -fno-omit-frame-pointer -fno-optimize-sibling-calls -fsanitize=address,undefined)
        ;;
    thread)
        OPTIMIZATION="-O1"
        SANITIZER_FLAGS=(-g -fno-omit-frame-pointer -fno-optimize-sibling-calls -fsanitize=thread)
        ;;
    *)
        printf 'Unknown AURORA_SANITIZER=%s\n' "$AURORA_SANITIZER" >&2
        exit 2
        ;;
esac

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$ROOT_DIR/build/ModuleCache"
COMMON=(-std=c++20 "$OPTIMIZATION" -pthread -target "$TARGET" -isysroot "$SDK_DIR" -I "$ROOT_DIR/Sources" -fmodules-cache-path="$ROOT_DIR/build/ModuleCache" "${SANITIZER_FLAGS[@]}")

printf 'Compiling Aurora v1 native baseline…\n'
"$CLANGXX" "${COMMON[@]}" -c "$ROOT_DIR/Sources/SynthEngine.cpp" -o "$BUILD_DIR/SynthEngine.o"
"$CLANGXX" "${COMMON[@]}" "$BUILD_DIR/SynthEngine.o" "$ROOT_DIR/Tests/BaselineEngineTests.cpp" -o "$BUILD_DIR/BaselineEngineTests"
"$BUILD_DIR/BaselineEngineTests"

# Sanitizer jobs intentionally exercise the native real-time engine only.
if [[ "${AURORA_SANITIZER:-none}" != "none" ]]; then
    exit 0
fi

printf '\nBuilding standalone production app for baseline smoke…\n'
bash "$ROOT_DIR/scripts/build.sh"

APP="$BUILD_DIR/AuroraBaselineChecks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
python3 - "$ROOT_DIR" "$BUILD_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); build=Path(sys.argv[2])
s=(root/'Sources/AuroraApp.swift').read_text()
(build/'InterfaceUnderTest.swift').write_text(s.split('@main struct AuroraApp:App')[0])
PY

for resource in Aurora100 AuroraPrism100 AuroraNova100 AuroraGB109 AuroraShimmer29 AuroraReference; do
    cp "$ROOT_DIR/Resources/$resource.json" "$APP/Contents/Resources/$resource.json"
done

printf 'Compiling Aurora v1 model/preset/UI baseline…\n'
xcrun swiftc -parse-as-library -O -target "$TARGET" \
    -module-cache-path "$ROOT_DIR/build/ModuleCache" \
    -import-objc-header "$ROOT_DIR/Sources/AuroraBridge.h" \
    "$BUILD_DIR/InterfaceUnderTest.swift" \
    "$ROOT_DIR/Sources/AuroraBackend.swift" \
    "$ROOT_DIR/Sources/PluginEditor.swift" \
    "$ROOT_DIR/Sources/WavetableViews.swift" \
    "$ROOT_DIR/Sources/MotionViews.swift" \
    "$ROOT_DIR/Sources/CreativeTools.swift" \
    "$ROOT_DIR/BaselineChecks.swift" \
    "$ROOT_DIR/build/objects/SynthEngine.o" \
    "$ROOT_DIR/build/objects/MacAudioMIDI.o" \
    -lc++ -framework SwiftUI -framework AppKit -framework Foundation \
    -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreMIDI \
    -o "$APP/Contents/MacOS/AuroraBaselineChecks"

NSUnbufferedIO=YES "$APP/Contents/MacOS/AuroraBaselineChecks"
printf '\nPASS baseline: Aurora v1 baseline suite complete\n'
