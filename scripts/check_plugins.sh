#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
AURORA_PLUGIN_BUILD_DIR="${AURORA_PLUGIN_BUILD_DIR:-/private/tmp/aurora-plugins-$UID}"
xcrun clang++ -std=c++20 -O2 -fobjc-arc -I Sources Tests/PluginCoreChecks.mm Sources/PluginCore.mm Sources/SynthEngine.cpp -framework Foundation -o build/PluginCoreChecks
build/PluginCoreChecks
"$AURORA_PLUGIN_BUILD_DIR/bin/Release/validator" "$AURORA_PLUGIN_BUILD_DIR/VST3/Release/Aurora.vst3"
"$AURORA_PLUGIN_BUILD_DIR/bin/Release/PluginHostChecks" "$AURORA_PLUGIN_BUILD_DIR/VST3/Release/Aurora.vst3"
# auval tests the installed copy; run install_plugins.sh after building first.
auval -v aumu Auro RyBr
