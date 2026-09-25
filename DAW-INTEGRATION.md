# KiMiA / Aurora DAW integration

KiMiA's development plug-ins target native Apple Silicon, macOS 14 or later. Bundle filenames and identifiers intentionally retain the Aurora lineage for compatibility.

- Audio Unit v2 instrument: `aumu / Auro / RyBr`, for Logic Pro and MainStage.
- VST3 instrument: **KiMiA by Ray Bridge Digital**, for Ableton Live and Cubase; the installed bundle filename remains `Aurora.vst3`.
- Stereo audio output, no audio input, MIDI on all 16 channels.
- Each instance owns its engine, sound, imported wavetables, routing, macros, and XY assignments.
- Host automation covers layer parameters, shared FX, macros, XY position, transpose, Hold, layer sends, and input routing/velocity curve.
- The host supplies audio devices, buffer size, and tempo. Use the host's MIDI mapping and audio recording/bounce controls.

## Development build

Pinned SDK revisions are listed in `PluginDependencies.lock`. Place their checkouts in `build/deps/vst3sdk` (including submodules) and `build/deps/AudioUnitSDK`. The build uses Apple's Command Line Tools, Swift, and CMake at `build/deps/cmake-package/cmake/data/bin/cmake`.

Run `bash scripts/build_plugins.sh`, then `bash scripts/install_plugins.sh`. The installer backs up existing Aurora plug-ins under `~/Library/Application Support/Aurora/Plugin Backups/` before replacing them.

Signed build products are under `/private/tmp/aurora-plugins-$UID/`, outside iCloud-managed Documents. Set `AURORA_PLUGIN_BUILD_DIR` to use a different local build directory. Source files and factory banks stay in the project. These local development builds use ad-hoc signing; public distribution still needs a Developer ID signing/notarization workflow.

Installed locations:

- `~/Library/Audio/Plug-Ins/VST3/Aurora.vst3`
- `~/Library/Audio/Plug-Ins/Components/Aurora.component`

Restart the DAW after replacing an already loaded plug-in. In Live, enable VST3 system folders in Settings → Plug-Ins, then search for **KiMiA** (the bundle filename remains `Aurora.vst3`).

## Verification status

### Current v0.25.0 boundary

- The repository/tag and plug-in source metadata are **0.25.0**.
- The plug-ins currently installed in `~/Library/Audio/Plug-Ins` are **0.24.3**. The 0.25.0 plug-in source has not been rebuilt, installed, and revalidated after the final version bump.
- The installed 0.24.3 AU passed `auval -v aumu Auro RyBr` in the v0.24.3 release work. That pass does not validate the current 0.25.0 plug-in source.
- The local standalone 0.25.0 build completed successfully before tagging, but current GitHub CI is not green. The standalone and plug-in jobs fail on a SwiftUI compiler type-check timeout; native baseline/regression/sanitizer jobs fail to link because FM-engine symbols are absent from their test link.
- These are recorded validation gaps, not claims that v0.25.0 plug-ins or regression suites passed.

### Historical host evidence

The following evidence was collected on earlier builds and remains useful, but it is not full certification of v0.25.0:

- Steinberg validator: 47 passed, 0 failed on the earlier development build recorded in this document.
- Apple `auval`: passed on the installed 0.24.3 AU (`aumu / Auro / RyBr`), including MIDI and render tests.
- Core checks: 300 Spectrum JSON factory-bank patches round-trip through host state; finite audio, independent instances, macro/XY changes, and invalid-state rejection were checked. MIDI Learn, soft pickup, and mapping recall pass without an editor.
- Test host: sample-offset MIDI, host tempo, XY automation without an editor, component/editor-state recall, 64-bit offline rendering, and editor attach/remove passed on the build current at that time.
- **Ableton Live 12.4.6 (VST3):** discovery/loading confirmed; native editor visible. Saving/exporting were disabled in demo mode at that check.
- **Cubase AI 15 (VST3):** discovery, instrument loading, full editor, patch selection, and transpose changes checked. Project save/reopen was exercised; visual confirmation of recalled patch/transpose was limited by UI automation.
- **MainStage 4.3.1 (AU):** verified 19 September 2026 with the 0.20.3/0.20.4 component — Software Instrument channel loaded **AU Instruments → Ray Bridge Digital → Aurora**, editor opened, Musical Typing produced channel-meter activity, no crash.
- **Logic Pro (AU):** not opened in-app yet (no license on the test machine). The MainStage pass is only a proxy for basic load/play/editor behavior. Bounce and arrange workflows remain unverified in Logic itself.
- Standalone interface regression passed on the build current when recorded, including factory sounds, saving/undo, MIDI Learn, themes, motion/wavetables, XY, and concurrent library merge checks.

Actual DAW playback/bounce and automation workflows are not exhaustively verified in every commercial host. After a future 0.25.0 rebuild/install, restart hosts so they load the new binary rather than the currently installed 0.24.3 bundles.

`bash scripts/check_plugins.sh` runs the automated checks. It requires a built plug-in and tests the installed AU copy, so install the current build first.

## State and libraries

Project state contains the complete sound, including motion curves, matrices, custom macro/XY assignments and embedded imported wavetables, plus global transpose and MIDI routing/velocity curve. Existing patches with missing newer optional fields keep defaults. Hold is released on project restore to prevent unexpected stuck notes.

The standalone session file is not overwritten by a plug-in instance. Plug-in user sounds, favorites and deleted sounds use `plugin-library.json` in Aurora's support folder, initially importing the standalone library when no plug-in library exists. Writes use a cross-process file lock and merge each editor's changes against its last snapshot, preserving unrelated additions, renames, deletions and favorite changes from other instances. If two editors change the same sound, the later save wins for that sound.

MIDI Learn bindings and soft-pickup behavior are handled by the instance's audio core even with the editor closed, and bindings are stored with the DAW project. All keyboard input must be routed through the DAW track; the plug-in does not open competing hardware connections.

The subsequent v0.17 sound-engine and interface upgrades are documented in [Sound design upgrades](SONIC-UPGRADES.md). Existing parameter IDs are preserved; added layer parameters occupy separate per-layer blocks, and output boost uses ID 2040. This is an ID-lineage note, not a claim that the current plug-in build passes validation; see the current v0.25.0 boundary above.
