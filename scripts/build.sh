#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Aurora.app"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"

python3 "$ROOT_DIR/scripts/assemble_patch_bank.py"

for source_file in Sources/AuroraApp.swift Sources/AuroraBridge.h Sources/SynthEngine.cpp Sources/MacAudioMIDI.mm Resources/Info.plist Resources/Aurora100.json; do
    if [[ ! -f "$ROOT_DIR/$source_file" ]]; then
        printf 'Missing source file: %s\n' "$source_file" >&2
        exit 1
    fi
done

SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
CLANGXX="$(xcrun --find clang++)"
SWIFTC="$(xcrun --find swiftc)"
TARGET="arm64-apple-macosx14.0"

mkdir -p "$BUILD_DIR/objects" "$MODULE_CACHE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

COMMON_FLAGS=(-std=c++20 -O2 -target "$TARGET" -isysroot "$SDK_DIR" -I "$ROOT_DIR/Sources" -fmodules-cache-path="$MODULE_CACHE_DIR")

printf 'Compiling audio engine…\n'
"$CLANGXX" "${COMMON_FLAGS[@]}" -c "$ROOT_DIR/Sources/SynthEngine.cpp" -o "$BUILD_DIR/objects/SynthEngine.o"

printf 'Compiling Core Audio and MIDI bridge…\n'
"$CLANGXX" "${COMMON_FLAGS[@]}" -fobjc-arc -c "$ROOT_DIR/Sources/MacAudioMIDI.mm" -o "$BUILD_DIR/objects/MacAudioMIDI.o"

printf 'Compiling native interface and linking Aurora…\n'
"$SWIFTC" -parse-as-library -O -target "$TARGET" -sdk "$SDK_DIR" \
    -module-name Aurora -module-cache-path "$MODULE_CACHE_DIR" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE_DIR" \
    -import-objc-header "$ROOT_DIR/Sources/AuroraBridge.h" \
    "$ROOT_DIR/Sources/AuroraApp.swift" \
    "$BUILD_DIR/objects/SynthEngine.o" "$BUILD_DIR/objects/MacAudioMIDI.o" \
    -lc++ -framework SwiftUI -framework AppKit -framework Foundation \
    -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreMIDI \
    -o "$BUILD_DIR/Aurora"

cp "$BUILD_DIR/Aurora" "$APP_DIR/Contents/MacOS/Aurora"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/Aurora100.json" "$APP_DIR/Contents/Resources/Aurora100.json"
plutil -lint "$APP_DIR/Contents/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
codesign --verify "$APP_DIR"
# File Provider can add FinderInfo to an app directory in Documents. The ZIP
# excludes extended attributes so its extracted bundle verifies strictly too.
ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$BUILD_DIR/Aurora.zip"
printf '\nBuilt: %s\nOpen the app with: open "%s"\n' "$APP_DIR" "$APP_DIR"
