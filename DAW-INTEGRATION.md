# Aurora DAW integration

Aurora's development plug-ins target native Apple Silicon, macOS 14 or later:

- Audio Unit v2 instrument: `aumu / Auro / RyBr`, for Logic Pro and MainStage.
- VST3 instrument: Aurora by Ray Bridge Digital, for Ableton Live and Cubase.
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

Restart the DAW after replacing an already loaded plug-in. In Live, enable VST3 system folders in Settings → Plug-Ins, then search for Aurora.

## Verification status

DAW integration coding and host checks are current as of **19 September 2026** (plug-ins rebuilt/installed as **0.20.3**). This is not a claim of full certification in every commercial host workflow.

- Steinberg validator: 47 passed, 0 failed on the development build.
- Apple `auval`: passed on the installed AU (`aumu / Auro / RyBr`), including MIDI and render tests.
- Core checks: 300 JSON factory-bank patches round-trip through host state; finite audio, independent instances, macro/XY changes, and invalid-state rejection checked. MIDI Learn, soft pickup and mapping recall pass without an editor. The additional 12 Swift factory voices are covered by standalone interface checks rather than the hosted bank test.
- Test host: sample-offset MIDI, host tempo, XY automation without an editor, component/editor-state recall, 64-bit offline rendering, and editor attach/remove passed.
- **Ableton Live 12.4.6 (VST3):** discovery/loading confirmed; native Aurora editor visible. Saving/exporting were disabled in demo mode at that check.
- **Cubase AI 15 (VST3):** discovery, instrument loading, full editor, patch selection and transpose changes checked. Project save/reopen exercised; visual confirmation of recalled patch/transpose was limited by UI automation.
- **MainStage 4.3.1 (AU):** verified 19 September 2026 with the 0.20.3 component — Software Instrument channel loaded **AU Instruments → Ray Bridge Digital → Aurora**, editor window opened (`Instrument [Inst 2]`), Musical Typing produced channel meter activity, no crash.
- **Logic Pro (AU):** not opened in-app yet (no license on the test machine). Same Audio Unit as MainStage; MainStage pass is a strong proxy for basic load/play/editor. Bounce/arrange workflows remain unverified in Logic itself.
- Standalone build and interface regression suite passed, including factory sounds, saving/undo, MIDI Learn, themes, motion/wavetables, XY, and concurrent library merge checks.

Actual DAW playback/bounce and automation workflows are not exhaustively verified in every host. Restart hosts after replacing installed binaries so they load 0.20.3.

`bash scripts/check_plugins.sh` runs the automated checks. It requires a built plug-in and tests the installed AU copy, so install the current build first.

## State and libraries

Project state contains the complete sound, including motion curves, matrices, custom macro/XY assignments and embedded imported wavetables, plus global transpose and MIDI routing/velocity curve. Existing patches with missing newer optional fields keep defaults. Hold is released on project restore to prevent unexpected stuck notes.

The standalone session file is not overwritten by a plug-in instance. Plug-in user sounds, favorites and deleted sounds use `plugin-library.json` in Aurora's support folder, initially importing the standalone library when no plug-in library exists. Writes use a cross-process file lock and merge each editor's changes against its last snapshot, preserving unrelated additions, renames, deletions and favorite changes from other instances. If two editors change the same sound, the later save wins for that sound.

MIDI Learn bindings and soft-pickup behavior are handled by the instance's audio core even with the editor closed, and bindings are stored with the DAW project. All keyboard input must be routed through the DAW track; the plug-in does not open competing hardware connections.

The subsequent v0.17 sound-engine and interface upgrades are documented in [Sound design upgrades](SONIC-UPGRADES.md). Existing parameter IDs are preserved; added layer parameters occupy IDs 6000–6404 in separate per-layer blocks, and output boost uses ID 2040. The same AU, VST3 and automated host checks pass for this build.
