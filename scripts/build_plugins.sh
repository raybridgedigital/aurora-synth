#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/plugin build/ModuleCache
python3 - <<'PY'
from pathlib import Path
s = Path('Sources/AuroraApp.swift').read_text()
Path('build/plugin/Interface.swift').write_text(s.split('@main struct AuroraApp:App')[0])
PY
xcrun swiftc -parse-as-library -emit-library -static -O -D AURORA_PLUGIN -module-name AuroraPlugin -target arm64-apple-macosx14.0 -module-cache-path build/ModuleCache -import-objc-header Sources/PluginBridge.h build/plugin/Interface.swift Sources/AuroraBackend.swift Sources/PluginEditor.swift Sources/WavetableViews.swift Sources/MotionViews.swift Sources/CreativeTools.swift -o build/plugin/libAuroraUI.a
CMAKE="$PWD/build/deps/cmake-package/cmake/data/bin/cmake"
# Documents can be managed by iCloud. Its metadata races code signing, so
# compile signed bundles in a local, non-File-Provider directory.
AURORA_PLUGIN_BUILD_DIR="${AURORA_PLUGIN_BUILD_DIR:-/private/tmp/aurora-plugins-$UID}"
"$CMAKE" -S . -B "$AURORA_PLUGIN_BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DSMTG_CREATE_MODULE_INFO=OFF
"$CMAKE" --build "$AURORA_PLUGIN_BUILD_DIR" --parallel 4
