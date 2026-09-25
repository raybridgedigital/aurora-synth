#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
mkdir -p build/V1ABComparison.app/Contents/MacOS build/V1ABComparison.app/Contents/Resources
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/AuroraApp.swift').read_text()
Path('build/V1ABInterfaceUnderTest.swift').write_text(s.split('@main struct AuroraApp:App')[0])
PY
for resource in Aurora100 AuroraPrism100 AuroraNova100 AuroraGB109 AuroraShimmer29 AuroraReference; do
    cp "Resources/$resource.json" "build/V1ABComparison.app/Contents/Resources/$resource.json"
done
xcrun swiftc -parse-as-library -O -target arm64-apple-macosx14.0 -module-cache-path build/ModuleCache -import-objc-header Sources/AuroraBridge.h build/V1ABInterfaceUnderTest.swift Sources/AuroraBackend.swift Sources/PluginEditor.swift Sources/WavetableViews.swift Sources/MotionViews.swift Sources/CreativeTools.swift V1ABComparisonChecks.swift build/objects/SynthEngine.o build/objects/FmEngine.o build/objects/MacAudioMIDI.o -lc++ -framework SwiftUI -framework AppKit -framework Foundation -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreMIDI -o build/V1ABComparison.app/Contents/MacOS/V1ABComparison
NSUnbufferedIO=YES build/V1ABComparison.app/Contents/MacOS/V1ABComparison
