#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/ModuleCache"
cd "$ROOT_DIR"
# FX-only: do NOT rebuild here — rebuild_factory_bank.py would restore the wiped
# non-FX banks. The audit runs against the checked-in Resources/*.json as-is.
xcrun clang++ -std=c++20 -O2 -fobjc-arc \
    -fmodules-cache-path="$ROOT_DIR/build/ModuleCache" \
    "$ROOT_DIR/Sources/SynthEngine.cpp" "$ROOT_DIR/Sources/FmEngine.cpp" "$ROOT_DIR/Sources/PluginCore.mm" "$ROOT_DIR/Tests/SpectrumAudit.mm" \
    -framework Foundation -I "$ROOT_DIR/Sources" -o "$ROOT_DIR/build/patch-audit"
"$ROOT_DIR/build/patch-audit"
