#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
mkdir -p build/V1SpecializedRegression.app/Contents/MacOS build/V1SpecializedRegression.app/Contents/Resources
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/AuroraApp.swift').read_text()
Path('build/V1SpecializedInterfaceUnderTest.swift').write_text(s.split('@main struct AuroraApp:App')[0])
PY
cp Resources/Aurora100.json build/V1SpecializedRegression.app/Contents/Resources/Aurora100.json
cp Resources/AuroraPrism100.json build/V1SpecializedRegression.app/Contents/Resources/AuroraPrism100.json
cp Resources/AuroraNova100.json build/V1SpecializedRegression.app/Contents/Resources/AuroraNova100.json
cp Resources/AuroraGB109.json build/V1SpecializedRegression.app/Contents/Resources/AuroraGB109.json
cp Resources/AuroraShimmer29.json build/V1SpecializedRegression.app/Contents/Resources/AuroraShimmer29.json
cp Resources/AuroraReference.json build/V1SpecializedRegression.app/Contents/Resources/AuroraReference.json
xcrun swiftc -parse-as-library -O -target arm64-apple-macosx14.0 -module-cache-path build/ModuleCache -import-objc-header Sources/AuroraBridge.h build/V1SpecializedInterfaceUnderTest.swift Sources/AuroraBackend.swift Sources/PluginEditor.swift Sources/WavetableViews.swift Sources/MotionViews.swift Sources/CreativeTools.swift V1SpecializedRegressionChecks.swift build/objects/SynthEngine.o build/objects/MacAudioMIDI.o -lc++ -framework SwiftUI -framework AppKit -framework Foundation -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreMIDI -o build/V1SpecializedRegression.app/Contents/MacOS/V1SpecializedRegression
build/V1SpecializedRegression.app/Contents/MacOS/V1SpecializedRegression
