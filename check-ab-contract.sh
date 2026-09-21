#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx14.0"
APP="$ROOT_DIR/build/ABComparisonContract.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT_DIR/build/ModuleCache"
python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
s=(root/'Sources/AuroraApp.swift').read_text()
(root/'build/ABInterfaceUnderTest.swift').write_text(s.split('@main struct AuroraApp:App')[0])
PY
for resource in Aurora100 AuroraPrism100 AuroraNova100 AuroraGB109 AuroraShimmer29 AuroraReference; do
  cp "$ROOT_DIR/Resources/$resource.json" "$APP/Contents/Resources/$resource.json"
done
xcrun swiftc -parse-as-library -O -target "$TARGET" -sdk "$SDK_DIR" \
  -module-cache-path "$ROOT_DIR/build/ModuleCache" \
  -import-objc-header "$ROOT_DIR/Sources/AuroraBridge.h" \
  "$ROOT_DIR/build/ABInterfaceUnderTest.swift" \
  "$ROOT_DIR/Sources/AuroraBackend.swift" \
  "$ROOT_DIR/Sources/PluginEditor.swift" \
  "$ROOT_DIR/Sources/WavetableViews.swift" \
  "$ROOT_DIR/Sources/MotionViews.swift" \
  "$ROOT_DIR/Sources/CreativeTools.swift" \
  "$ROOT_DIR/Tests/ABComparisonContract.swift" \
  "$ROOT_DIR/build/objects/SynthEngine.o" "$ROOT_DIR/build/objects/MacAudioMIDI.o" \
  -lc++ -framework SwiftUI -framework AppKit -framework Foundation \
  -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreMIDI \
  -o "$APP/Contents/MacOS/ABComparisonContract"
NSUnbufferedIO=YES "$APP/Contents/MacOS/ABComparisonContract"
