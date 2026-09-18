#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stamp="$(date +%Y%m%d-%H%M%S)"
AURORA_PLUGIN_BUILD_DIR="${AURORA_PLUGIN_BUILD_DIR:-/private/tmp/aurora-plugins-$UID}"
install_bundle() {
    local source="$1" parent="$2" name="$3"
    mkdir -p "$parent"
    if [ -e "$parent/$name" ]; then
        mkdir -p "$HOME/Library/Application Support/Aurora/Plugin Backups/$stamp"
        mv "$parent/$name" "$HOME/Library/Application Support/Aurora/Plugin Backups/$stamp/$name"
    fi
    ditto --norsrc "$source" "$parent/$name"
    xattr -cr "$parent/$name"
    codesign --force --sign - "$parent/$name"
    codesign --verify "$parent/$name"
}
install_bundle "$AURORA_PLUGIN_BUILD_DIR/VST3/Release/Aurora.vst3" "$HOME/Library/Audio/Plug-Ins/VST3" Aurora.vst3
install_bundle "$AURORA_PLUGIN_BUILD_DIR/lib/Release/Aurora.component" "$HOME/Library/Audio/Plug-Ins/Components" Aurora.component
