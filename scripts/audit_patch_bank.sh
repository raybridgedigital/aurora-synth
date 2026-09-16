#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/ModuleCache"
python3 "$ROOT_DIR/scripts/assemble_patch_bank.py"
python3 "$ROOT_DIR/scripts/assemble_prism_bank.py"
xcrun clang++ -std=c++20 -O2 -fobjc-arc \
    -fmodules-cache-path="$ROOT_DIR/build/ModuleCache" \
    "$ROOT_DIR/Sources/SynthEngine.cpp" "$ROOT_DIR/Tests/PatchBankAudit.mm" \
    -framework Foundation -I "$ROOT_DIR/Sources" -o "$ROOT_DIR/build/patch-audit"
"$ROOT_DIR/build/patch-audit" "$ROOT_DIR/Resources/Aurora100.json" "$ROOT_DIR/build/patch-audit-report.json"
"$ROOT_DIR/build/patch-audit" "$ROOT_DIR/Resources/AuroraPrism100.json" "$ROOT_DIR/build/prism-audit-report.json"
