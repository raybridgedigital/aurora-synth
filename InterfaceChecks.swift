import AppKit
import Combine
import SwiftUI

@main struct InterfaceChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let tracking=XYTrackingView(frame:NSRect(x:0,y:0,width:424,height:224))
        var xyUpdates=0
        var lastXY=CGPoint.zero
        tracking.onMove={x,y in xyUpdates+=1;lastXY=CGPoint(x:x,y:y)}
        for i in 0..<200{tracking.track(CGPoint(x:12+Double(i)*2,y:12+Double(i)))}
        precondition(xyUpdates==0,"Pointer updates must not synchronously publish sound-model changes")
        precondition(tracking.position==CGPoint(x:0.995,y:0.0050000000000000044))
        tracking.flushPending()
        precondition(xyUpdates==1 && lastXY==tracking.position,"Rapid events must coalesce to the latest position")
        tracking.track(CGPoint(x:900,y:-30));tracking.flushPending()
        precondition(xyUpdates==2 && lastXY==CGPoint(x:1,y:1),"Final position must be clamped and delivered")
        tracking.track(CGPoint(x:0,y:999));tracking.cancelPending();tracking.flushPending()
        precondition(xyUpdates==2,"Removing the pad must cancel pending updates")
        print("PASS: XY pointer feedback is immediate; rapid sound updates coalesce, final positions flush, and pending work cancels.")
        for period in [12.0,80.0,300.0,2400.0]{
            let raw=(0..<8192).map{Float(sin(Double($0)*2*Double.pi/period)*0.02)}
            let display=ScopeTelemetry.displayWave(raw)
            let crossings=(1..<display.count).filter{display[$0-1]<=0 && display[$0]>0}.count
            precondition((2...3).contains(crossings),"Scope must display 2–3 cycles across low and high notes")
            precondition(display.allSatisfy{$0.isFinite && abs($0)<=0.821})
            let actual=ScopeTelemetry.displayWave(raw,normalize:false)
            precondition(actual.allSatisfy{$0.isFinite && abs($0)<=0.02001})
            let louder=ScopeTelemetry.displayWave(raw.map{$0*4},normalize:false)
            precondition(zip(actual,louder).allSatisfy{abs($0.0*4-$0.1)<0.00001},"Live waveform must preserve level changes")
        }
        precondition(ScopeTelemetry.displayWave(Array(repeating:0,count:8192)).allSatisfy{$0==0})
        print("PASS: triggered scope shows 2–3 cycles with bounded display gain and silent idle output.")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("AuroraChecks-"+UUID().uuidString)
        let model=SynthModel(storageDirectory:folder)
        let legacy=FactoryBank.make("test-legacy","Legacy test fixture","Templates","Neutral test fixture",a:[:])
        do {
            var original=FactoryBank.all[0];original.id="shared"
            var renamed=original;renamed.name="Renamed in another editor"
            var added=original;added.id="new"
            let base=SynthModel.PluginLibrary(presets:[original],favorites:["old"],deleted:[])
            let local=SynthModel.PluginLibrary(presets:[original,added],favorites:["old","local"],deleted:[])
            let disk=SynthModel.PluginLibrary(presets:[renamed],favorites:["remote"],deleted:[])
            let merged=try! SynthModel.PluginLibrary.merge(local,baseline:base,latest:disk)
            precondition(merged.presets.count==2 && merged.presets[0].name==renamed.name)
            precondition(merged.favorites==Set(["local","remote"]))
            let removed=SynthModel.PluginLibrary(presets:[],favorites:[],deleted:[original])
            let deletion=try! SynthModel.PluginLibrary.merge(removed,baseline:base,latest:merged)
            precondition(deletion.presets.map(\.id)==["new"] && deletion.deleted.count==1)
            print("PASS: concurrent plug-in library additions, renames, favorites and deletions preserve unrelated edits.")
        }
        defer { aurora_shutdown() }
        precondition(model.collection == "Aurora")
        precondition(SynthModel.restoredOutputGain(nil,revision:nil)==9)
        precondition(SynthModel.restoredOutputGain(6,revision:nil)==9)
        precondition(SynthModel.restoredOutputGain(12,revision:2)==9)
        precondition(SynthModel.restoredOutputGain(6,revision:3)==6) // customized rev-3 kept
        precondition(SynthModel.restoredOutputGain(24,revision:3)==9) // untouched +24 migrates to +9
        precondition(SynthModel.restoredOutputGain(30,revision:3)==24) // clamped custom kept
        precondition(SynthModel.restoredOutputGain(12,revision:4)==12)
        precondition(FactoryBank.all.count == 300)
        let singlePresetData=try! JSONEncoder().encode(FactoryBank.all[0])
        let presetBankData=try! JSONEncoder().encode(Array(FactoryBank.all.prefix(12)))
        precondition(try! SynthModel.presets(in:singlePresetData).count==1)
        precondition(try! SynthModel.presets(in:presetBankData).count==12)
        precondition((try? SynthModel.presets(in:Data("not a preset".utf8)))==nil)
        print("PASS: batch preset format accepts one preset or a multi-preset bank and rejects malformed data.")
        precondition(SynthModel.ranges.count==97 && ControlTarget.layerNames.count==97)
        for ref in FactoryBank.references {
            model.loadPreset(ref)
            precondition(SynthModel.sanitized(ref) != nil)
            for l in 0..<4 {for p in 79..<97 {precondition(abs(Double(aurora_get_parameter(Int32(l),Int32(p)))-ref.layers[l][p])<0.0001)}}
            let recalled=try! JSONDecoder().decode(SoundPreset.self,from:JSONEncoder().encode(ref))
            precondition(recalled.layers==ref.layers)
        }
        model.checkpoint();let oldPhase=model.patch.layers[0][84];model.set(0,84,0.9);model.undo();precondition(model.patch.layers[0][84]==oldPhase);model.redo();precondition(model.patch.layers[0][84]==0.9)
        precondition(MatrixAssignment(enabled:true,source:5,destination:12).valid(performance:false))
        model.loadPreset(legacy);precondition(aurora_get_parameter(0,79)==0 && aurora_get_parameter(0,82)==4 && aurora_get_parameter(0,93)==0)
        let upgradeOriginal=model.patch
        model.checkpoint();model.set(0,58,1);model.set(0,60,1900);model.set(0,64,2);model.set(0,68,0.7);model.set(0,70,2);model.set(0,71,0.4);model.set(0,73,3)
        let upgraded=model.patch
        let roundtrip=try! JSONDecoder().decode(SoundPreset.self,from:JSONEncoder().encode(upgraded))
        precondition(SynthModel.sanitized(roundtrip)?.layers[0][73]==3)
        precondition(MatrixAssignment(enabled:true,source:3,destination:20).valid(performance:false))
        precondition(ControlTarget(layer:3,parameter:78).valid)
        model.undo();precondition(model.patch.layers[0]==upgradeOriginal.layers[0]);model.redo();precondition(model.patch.layers[0]==upgraded.layers[0])
        model.loadPreset(upgradeOriginal);precondition(aurora_get_parameter(0,58)==0 && aurora_get_parameter(0,60)==3200 && aurora_get_parameter(0,73)==0)
        model.setOutputGain(9);model.loadPreset(upgradeOriginal);precondition(model.outputGain==9 && aurora_get_global(15)==9)
        model.setOutputGain(24);precondition(model.outputGain==24 && aurora_get_global(15)==24)
        print("PASS: extended sound controls serialize, sanitize, undo/redo, reset on legacy load, and output boost survives patch browsing.")
        model.selectTheme(.copperOrange)
        let upgradeView=NSHostingView(rootView:EditorView(m:model).padding(16).environment(\.auroraPalette,model.theme.palette).environment(\.colorScheme,.dark).foregroundStyle(Color.white))
        upgradeView.frame=NSRect(x:0,y:0,width:1100,height:3400);upgradeView.layoutSubtreeIfNeeded()
        if let bitmap=upgradeView.bitmapImageRepForCachingDisplay(in:upgradeView.bounds){upgradeView.cacheDisplay(in:upgradeView.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-upgrade-editor.png"))}
        let browserView=NSHostingView(rootView:PatchBrowser(m:model,close:{}).environment(\.auroraPalette,model.theme.palette).environment(\.colorScheme,.dark).foregroundStyle(Color.white))
        browserView.frame=NSRect(x:0,y:0,width:1380,height:760);browserView.layoutSubtreeIfNeeded()
        if let bitmap=browserView.bitmapImageRepForCachingDisplay(in:browserView.bounds){browserView.cacheDisplay(in:browserView.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-upgrade-browser.png"))}
        precondition(model.collectionSounds.count == 300)
        precondition(FactoryBank.prism.count == 100)
        precondition(Set(FactoryBank.all.map(\.id)).count==300)
        precondition(Set(FactoryBank.all.map{$0.name.lowercased()}).count==300)
        precondition(FactoryBank.nova.count==100)
        model.search=""
        precondition(model.library.filter{$0.id.hasPrefix("spectrum-")}.count==300)
        for sound in FactoryBank.all {
            model.loadPreset(sound)
            precondition(model.patch.id==sound.id && sound.motion?.count==4 && sound.motion!.allSatisfy(\.valid))
            precondition(sound.sends?.count==4 && sound.sends!.allSatisfy(\.valid))
            precondition(sound.customMacros?.count==8 && sound.customMacros!.values.allSatisfy(\.valid) && sound.xy!.valid)
            precondition(sound.soundMatrix!.flatMap{$0}.allSatisfy{$0.valid(performance:false)})
            precondition(sound.performanceMatrix!.allSatisfy{$0.valid(performance:true)})
            for index in 0..<8{model.macro(index,sound.macros[index])}
            for l in 0..<4 {for p in 0..<97{
                precondition(abs(model.patch.layers[l][p]-sound.layers[l][p])<0.00001,"Nova macro center changes the authored sound: \(sound.name) / \(l) / \(p)")
            }}
            for p in 1..<15{precondition(abs(model.patch.globalValue(p)-sound.globalValue(p))<0.00001)}
            model.moveXY(x:1,y:0)
            precondition(model.patch.macros[0]==1 && model.patch.macros[1]==0)
            let data=try! JSONEncoder().encode(model.patch)
            let decoded=try! JSONDecoder().decode(SoundPreset.self,from:data)
            precondition(decoded.customMacros==sound.customMacros && decoded.motion==sound.motion && decoded.xy==sound.xy && decoded.sends==sound.sends)
        }
        model.search="Prism"
        precondition(!model.library.isEmpty)
        model.search=""
        for sound in FactoryBank.prism {
            model.loadPreset(sound)
            precondition(model.patch.id==sound.id && aurora_get_parameter(0,44)==Float(sound.layers[0][44]))
        }
        model.category="Pads"
        precondition(model.library.count == FactoryBank.all.filter{$0.category == "Pads"}.count)
        model.category="All categories"
        model.search="Apricot Solstice"
        precondition(model.library.count == 1 && model.library[0].id == "spectrum-apricot-solstice")
        model.search="Atlas Submarine"
        precondition(model.library.count == 1 && model.library[0].id == "spectrum-atlas-submarine")
        model.search="no-match-interface-test"
        precondition(model.library.isEmpty)
        model.search=""
        // Initial status synchronization is allowed. Stable polls must be silent.
        model.poll()
        var rootPublications=0
        let rootObserver=model.objectWillChange.sink { rootPublications += 1 }
        for _ in 0..<20 { model.poll() }
        precondition(rootPublications == 0,"Unchanged polling invalidated the main interface")
        var meterPublications=0
        let meterObserver=model.telemetry.objectWillChange.sink { meterPublications += 1 }
        for n in 1...1200 {
            model.telemetry.update(peak:Float(n%100)/100,load:0.02,voices:n%64,midiEvents:UInt64(n))
        }
        precondition(rootPublications == 0,"Meter changes invalidated the main interface")
        precondition(meterPublications == 1200)
        let last=model.telemetry.snapshot
        for _ in 0..<1200 {
            model.telemetry.update(peak:last.peak,load:0.02,voices:last.voices,midiEvents:last.midiEvents)
        }
        precondition(meterPublications == 1200,"Repeated telemetry should not publish")
        withExtendedLifetime((rootObserver,meterObserver)) {}
        model.global(0,1);precondition(model.patch.globals[0]==1)
        model.setTranspose(12);model.loadPreset(legacy)
        precondition(model.transpose==12 && model.patch.globals[0]==1)
        model.tapTempo(at:100);model.tapTempo(at:100.5);model.tapTempo(at:101)
        precondition(model.patch.globals[1]==120)
        model.tapTempo(at:110);model.tapTempo(at:110.75)
        precondition(model.patch.globals[1]==80)
        model.selectedLayer=2
        model.checkpoint();model.updateMatrix(performance:false,slot:5){$0.enabled=true;$0.source=2;$0.destination=4;$0.amount = -0.5}
        precondition(model.matrixRows(performance:false)[5].enabled)
        model.selectedLayer=0;precondition(!model.matrixRows(performance:false)[5].enabled)
        model.checkpoint();model.updateMatrix(performance:true,slot:0){$0.enabled=true;$0.source=5;$0.cc=74;$0.destination=9;$0.target=1;$0.amount=0.8}
        precondition(model.matrixRows(performance:true)[0].target==4)
        model.undo();precondition(!model.matrixRows(performance:true)[0].enabled)
        model.redo();precondition(model.matrixRows(performance:true)[0].enabled)
        model.set(0,33,4);precondition(model.patch.layers[0][33]==4)
        model.global(6,0.7);precondition(model.patch.phaserMix==0.7)
        model.saveName="Test sound";model.saveUserPreset();let id=model.patch.id
        model.set(0,7,1234);model.renameID=id;model.renameName="Renamed";model.renameSound()
        precondition(model.patch.name=="Renamed" && model.patch.layers[0][7]==1234)
        precondition(model.userPresets[0].name=="Renamed")
        model.deleteSound(id);precondition(model.userPresets.isEmpty)
        model.undoDelete();precondition(model.userPresets.count==1)
        let saved=try! JSONDecoder().decode(SavedSession.self,from:Data(contentsOf:folder.appendingPathComponent("session.json")))
        precondition(saved.transpose==12 && saved.patch.globals[0]==1 && saved.patch.phaserMix==0.7 && saved.patch.layers[0][33]==4)
        precondition(saved.patch.soundMatrix?[2][5].amount == -0.5 && saved.patch.performanceMatrix?[0].cc==74)
        model.loadPreset(legacy);precondition((model.patch.phaserMix ?? 0)==0 && model.patch.layers[0][33]==0)
        precondition(model.matrixRows(performance:false).allSatisfy{!$0.enabled} && model.matrixRows(performance:true).allSatisfy{!$0.enabled})
        precondition(model.patch.layers[0][34]==0.5 && model.patch.layers[0][36]==1 && model.patch.layers[0][39]==0)
        model.saveCurrent();precondition(model.showingSave);model.showingSave=false
        model.set(0,34,0.2);model.set(0,35,0.6);model.set(0,36,4);model.set(0,39,1);model.set(0,40,19)
        model.saveName="Character";model.saveCategory="My textures";model.saveUserPreset();let characterID=model.patch.id
        let count=model.userPresets.count
        model.set(0,7,4321);model.saveCurrent()
        precondition(model.userPresets.count==count && model.patch.id==characterID && !model.dirty)
        precondition(model.userPresets.first{$0.id==characterID}!.layers[0][7]==4321)
        model.renameID=characterID;model.renameName="Character renamed";model.renameCategory="Experimental";model.set(0,7,3456);model.renameSound()
        precondition(model.patch.layers[0][7]==3456 && model.patch.category=="Experimental" && model.dirty)
        model.beginSaveAs();model.saveName="Copy";model.saveUserPreset();let copyID=model.patch.id
        precondition(copyID != characterID && model.userPresets.count==count+1)
        model.deleteSound(characterID);model.deleteSound(copyID)
        let trash=try! JSONDecoder().decode(SavedSession.self,from:Data(contentsOf:folder.appendingPathComponent("session.json")))
        precondition(trash.deletedPresets?.count==2 && trash.deletedPresets?.first?.layers[0][36]==4)
        model.restoreDeleted(characterID);precondition(model.deletedPresets.count==1 && model.deletedPresets[0].id==copyID)
        precondition(model.userPresets.first{$0.id==characterID}!.category=="Experimental")
        model.collection="Deleted sounds";precondition(model.collectionSounds.count==1)
        model.restoreDeleted(copyID);precondition(model.deletedPresets.isEmpty)
        model.checkpoint();model.global(7,2.5);model.global(9,-0.6);model.global(13,4.2);model.global(14,5)
        model.set(0,41,2);model.set(0,42,0.4);model.set(0,43,12)
        model.setRoute(12345,SourceRoute(mask:3,channel:2,velocityCurve:2))
        model.saveCurrent();model.persist()
        let expressive=try! JSONDecoder().decode(SavedSession.self,from:Data(contentsOf:folder.appendingPathComponent("session.json")))
        precondition(expressive.patch.globalValue(7)==2.5 && expressive.patch.globalValue(14)==5 && expressive.patch.layers[0][43]==12 && expressive.routes[12345]?.velocityCurve==2)
        model.undo();precondition(model.patch.globalValue(7)==0.22 && model.patch.layers[0][41]==0)
        model.redo();precondition(model.patch.globalValue(13)==4.2 && model.patch.layers[0][41]==2)
        model.loadPreset(legacy);precondition(model.patch.globalValue(14)==0 && model.patch.layers[0][43]==2)
        precondition(aurora_get_global(7)==Float(0.22) && aurora_get_parameter(0,43)==2)
        print("PASS: extended FX and expressive settings save, undo/redo, reset on old patch load; per-source velocity curve persists.")
        print("PASS: Save updates, Save As copies, editable categories preserve edits, multiple deletions persist and restore independently, oscillator settings persist.")
        print("PASS: matrix layer independence, shared-FX targets, undo/redo, saving and legacy patch defaults.")
        print("PASS: 100% master, persistent global transpose, tap tempo, rename preserving edits, delete and undo.")
        print("PASS: Aurora contains 300 distinct Spectrum sounds; all 300 load and all 97 parameters retain macro-center values. Motion, XY and save round trips pass.")
        print("PASS: 20 stable polls and 1,200 meter changes caused ZERO main-interface publications.")
        print("PASS: 1,200 unchanged meter samples caused ZERO additional publications.")
        model.selectedLayer=0
        let samples=(0..<512).map{Float(sin(Double($0)*2*Double.pi/256)*0.8)}
        let imported=ImportedWavetable(name:"Test portable wave",frameSize:256,data:samples.withUnsafeBytes{Data($0)})
        precondition(imported.valid && imported.frames==2)
        model.checkpoint();model.patch.importedWavetables=[0:imported];model.applyWavetables()
        model.set(0,44,1);model.set(0,45,24);model.set(0,46,0.7);model.set(0,47,3);model.set(0,48,0.4)
        model.updateMatrix(performance:false,slot:0){$0.enabled=true;$0.destination=12;$0.amount=0.3}
        model.updateMatrix(performance:true,slot:0){$0.enabled=true;$0.destination=15;$0.target=2;$0.amount=0.6}
        precondition(model.matrixRows(performance:true)[0].target==2)
        model.saveName="Portable wavetable";model.saveUserPreset();model.persist()
        let savedWave=try! JSONDecoder().decode(SavedSession.self,from:Data(contentsOf:folder.appendingPathComponent("session.json")))
        precondition(savedWave.patch.importedWavetables?[0]==imported && savedWave.patch.layers[0][45]==24)
        let portable=model.patch
        model.loadPreset(legacy);precondition(model.patch.layers[0][44]==0 && model.patch.layers[0][51]==0)
        model.undo();precondition(model.patch.importedWavetables?[0]==imported && aurora_get_parameter(0,45)==24)
        model.redo();precondition(model.patch.importedWavetables==nil)
        model.loadPreset(portable);model.set(0,1,2);precondition(model.patch.layers[0][44]==0)
        model.set(0,44,1);model.wavetableTelemetry.update()
        for name in MotionShapes.names {
            var motion=MotionSettings();motion.points=MotionShapes.points(name)
            precondition(motion.valid && motion.points.count<=16)
            for step in 0...100{precondition((0...1).contains(motion.shape(Double(step)/100)))}
            let data=motion.packet
            precondition(data.withUnsafeBufferPointer{aurora_set_motion(0,$0.baseAddress,Int32($0.count))}==1)
        }
        model.checkpoint();model.changeMotion{$0.enabled=true;$0.seconds=8;$0.routes[0].minimum=0.3;$0.points=MotionShapes.points("Double Swell");$0.routes[4].enabled=true}
        let designedMotion=model.motionSettings
        model.undo();precondition(!model.motionSettings.enabled)
        model.redo();precondition(model.motionSettings==designedMotion)
        model.selectedLayer=1;precondition(!model.motionSettings.enabled);model.selectedLayer=0
        let motionHost=NSHostingView(rootView:MotionEnvelopePanel(m:model).padding(16).background(Color.black).environment(\.colorScheme,.dark))
        motionHost.frame=NSRect(x:0,y:0,width:1120,height:900);motionHost.layoutSubtreeIfNeeded()
        if let bitmap=motionHost.bitmapImageRepForCachingDisplay(in:motionHost.bounds){motionHost.cacheDisplay(in:motionHost.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-motion-panel.png"))}
        let host=NSHostingView(rootView:WavetableSection(m:model).padding(16).background(Color.black).environment(\.colorScheme,.dark))
        host.frame=NSRect(x:0,y:0,width:1120,height:430);host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-wavetable-panels.png"))}
        print("PASS: embedded wavetable persistence, legacy reset, undo/redo, classic switch, and layer-specific wavetable matrix targets.")
        model.persist();model.shutdown()
        let restored=SynthModel(storageDirectory:folder)
        precondition(restored.patch.importedWavetables?[0]==imported)
        precondition(restored.motionSettings==designedMotion)
        restored.loadPreset(legacy);precondition(!restored.motionSettings.enabled)
        restored.undo();precondition(restored.motionSettings==designedMotion)
        precondition(restored.patch.layers[0][44]==1 && restored.patch.layers[0][45]==24)
        precondition(aurora_get_parameter(0,45)==24 && aurora_get_parameter(0,47)==3)
        var preview=[Float](repeating:0,count:128)
        let previewCount=preview.withUnsafeMutableBufferPointer{aurora_copy_wavetable_preview(0,0,$0.baseAddress,128)}
        precondition(previewCount==128 && preview.allSatisfy(\.isFinite) && preview.contains{abs($0)>0.1})
        precondition(restored.userPresets.contains{$0.id==portable.id && $0.importedWavetables?[0]==imported})
        precondition(!restored.running)
        restored.shutdown()
        print("PASS: fresh model restores embedded table, oscillator settings and saved preset with audio stopped.")
        print("PASS: 16 factory motion shapes validate through the DSP bridge; motion saves, restores, undoes, resets on legacy patches and stays layer-independent.")
        let toolsModel=SynthModel(storageDirectory:folder.appendingPathComponent("LayerTools"))
        toolsModel.userPresets=[legacy]
        toolsModel.loadPreset(legacy);let originalCutoff=toolsModel.patch.layers[0][7]
        toolsModel.set(0,7,1234);toolsModel.toggleComparison()
        precondition(toolsModel.comparingSaved && toolsModel.patch.layers[0][7]==1234 && aurora_get_parameter(0,7)==Float(originalCutoff))
        toolsModel.persist();toolsModel.toggleComparison()
        precondition(!toolsModel.comparingSaved && aurora_get_parameter(0,7)==1234)
        toolsModel.toggleComparison();toolsModel.set(0,7,2345)
        precondition(!toolsModel.comparingSaved && aurora_get_parameter(0,7)==2345)
        toolsModel.patch.importedWavetables=[0:imported];toolsModel.set(0,44,1);toolsModel.set(0,45,24)
        toolsModel.changeMotion{$0=designedMotion};toolsModel.sendBinding(true).wrappedValue=0.2;toolsModel.sendBinding(false).wrappedValue=0.6
        toolsModel.updateMatrix(performance:false,slot:0){$0.enabled=true;$0.destination=12;$0.amount=0.5}
        toolsModel.copyLayer(0);let beforePaste=toolsModel.patch.layers[1];toolsModel.pasteLayer(1)
        precondition(toolsModel.patch.layers[1]==toolsModel.patch.layers[0] && toolsModel.patch.importedWavetables?[2]==imported)
        precondition(toolsModel.patch.motion?[1]==designedMotion && toolsModel.patch.sends?[1].delay==0.2 && toolsModel.patch.soundMatrix?[1][0].destination==12)
        toolsModel.undo();precondition(toolsModel.patch.layers[1]==beforePaste && toolsModel.patch.importedWavetables?[2]==nil)
        toolsModel.redo();precondition(toolsModel.patch.importedWavetables?[2]==imported)
        toolsModel.toggleSolo(1);precondition(toolsModel.soloLayer==1)
        toolsModel.saveName="Layer tools";toolsModel.saveUserPreset();let savedTools=toolsModel.patch
        toolsModel.loadPreset(legacy);precondition(toolsModel.soloLayer == -1 && toolsModel.patch.sends==nil)
        toolsModel.loadPreset(savedTools);precondition(toolsModel.patch.sends?[1].reverb==0.6)
        toolsModel.collection="Aurora";toolsModel.category="Bass";toolsModel.search="";toolsModel.browsePatch(1)
        precondition(toolsModel.patch.category=="Bass");let browsedID=toolsModel.patch.id;toolsModel.browsePatch(1);precondition(toolsModel.patch.id != browsedID)
        let toolsHost=NSHostingView(rootView:ContentView(m:toolsModel))
        toolsHost.frame=NSRect(x:0,y:0,width:1440,height:900);toolsHost.layoutSubtreeIfNeeded()
        if let bitmap=toolsHost.bitmapImageRepForCachingDisplay(in:toolsHost.bounds){toolsHost.cacheDisplay(in:toolsHost.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-layer-tools.png"))}
        toolsModel.selectedLayer=0;toolsModel.loadPreset(legacy)
        toolsModel.changeMotion{$0.beats=8;$0.grid=16;$0.points=MotionShapes.points("Heartbeat")}
        precondition(toolsModel.motionSettings.snapped(0.17)==0.1875)
        toolsModel.saveShape(name:"My Heartbeat");let shapeID=toolsModel.savedShapes[0].id
        toolsModel.saveShape(name:"Renamed heartbeat",replacing:shapeID)
        precondition(toolsModel.savedShapes.count==1 && toolsModel.savedShapes[0].name=="Renamed heartbeat")
        toolsModel.checkpoint();toolsModel.editCustomMacro(0){$0.name="Intensity";$0.routes=[CustomMacroRoute(target:ControlTarget(layer:0,parameter:7),from:0.2,to:0.8),CustomMacroRoute(target:ControlTarget(layer:-1,parameter:4),from:0.8,to:0.1)]}
        toolsModel.macro(0,0);let dark=toolsModel.patch.layers[0][7],wet=toolsModel.patch.globals[4]
        toolsModel.macro(0,1);precondition(toolsModel.patch.layers[0][7]>dark && toolsModel.patch.globals[4]<wet)
        toolsModel.undo();precondition(toolsModel.patch.customMacros==nil)
        toolsModel.redo();precondition(toolsModel.macroNames[0]=="Intensity")
        let target=ControlTarget(layer:0,parameter:7)
        toolsModel.setControl(target,0.5);toolsModel.beginDirectLearn(target)
        toolsModel.handleDirectCC(source:123,channel:1,controller:64,value:1);precondition(toolsModel.learningControl != nil)
        toolsModel.handleDirectCC(source:123,channel:1,controller:74,value:0)
        precondition(toolsModel.directMappings.count==1 && toolsModel.learningControl==nil)
        let initialCutoff=toolsModel.patch.layers[0][7]
        toolsModel.handleDirectCC(source:999,channel:1,controller:74,value:1);precondition(toolsModel.patch.layers[0][7]==initialCutoff)
        toolsModel.handleDirectCC(source:123,channel:1,controller:74,value:0.1);precondition(toolsModel.patch.layers[0][7]==initialCutoff)
        toolsModel.handleDirectCC(source:123,channel:1,controller:74,value:0.6);precondition(toolsModel.patch.layers[0][7]>initialCutoff)
        toolsModel.setControl(target,0.8);let manuallySet=toolsModel.patch.layers[0][7]
        toolsModel.handleDirectCC(source:123,channel:1,controller:74,value:0.1);precondition(toolsModel.patch.layers[0][7]==manuallySet)
        let lockedLayers=toolsModel.patch.layers,lockedGlobals=toolsModel.patch.globals
        toolsModel.makeVariation(amount:1,locked:Set(VariationGroup.allCases),allLayers:true,random:{1})
        precondition(toolsModel.patch.layers==lockedLayers && toolsModel.patch.globals==lockedGlobals)
        toolsModel.makeVariation(amount:0.8,locked:[.pitch,.envelopes,.effects],allLayers:false,random:{1})
        precondition(toolsModel.patch.layers[0][7] != lockedLayers[0][7])
        for p in [4,9,10,11,12,13,15,27,28,37]{precondition(toolsModel.patch.layers[0][p]==lockedLayers[0][p])}
        precondition(toolsModel.patch.layers[1]==lockedLayers[1] && toolsModel.patch.globals==lockedGlobals)
        toolsModel.undo();precondition(toolsModel.patch.layers==lockedLayers)
        let beforeXY=toolsModel.patch.layers
        toolsModel.checkpoint();toolsModel.changeXY{$0.x=XYAxis(macro:0,start:0.2,end:0.8);$0.y=XYAxis(macro:3,start:0.9,end:0.1)}
        toolsModel.checkpoint();toolsModel.moveXY(x:1,y:1)
        precondition(abs(toolsModel.patch.macros[0]-0.8)<0.00001 && abs(toolsModel.patch.macros[3]-0.1)<0.00001)
        toolsModel.undo();precondition(toolsModel.patch.layers==beforeXY)
        toolsModel.redo();precondition(abs(toolsModel.patch.macros[0]-0.8)<0.00001)
        toolsModel.moveXY(x:-3,y:5);precondition(abs(toolsModel.patch.macros[0]-0.2)<0.00001 && abs(toolsModel.patch.macros[3]-0.1)<0.00001)
        toolsModel.assignXY(horizontal:true,macro:3);precondition(toolsModel.xySettings.x.macro==3 && toolsModel.xySettings.y.macro==0)
        toolsModel.undo();precondition(toolsModel.xySettings.x.macro==0 && toolsModel.xySettings.y.macro==3)
        let savedXY=toolsModel.xySettings
        toolsModel.changeXY{$0.y.macro=$0.x.macro}
        precondition(toolsModel.xySettings==savedXY)
        let xyHost=NSHostingView(rootView:XYPadPanel(m:toolsModel).padding(16).background(Color.black).environment(\.colorScheme,.dark).foregroundStyle(Color.white))
        xyHost.frame=NSRect(x:0,y:0,width:1120,height:470);xyHost.layoutSubtreeIfNeeded()
        if let bitmap=xyHost.bitmapImageRepForCachingDisplay(in:xyHost.bounds){xyHost.cacheDisplay(in:xyHost.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-xy-pad.png"))}
        toolsModel.saveName="Creative tools saved";toolsModel.saveUserPreset()
        let themeEncoder=JSONEncoder();themeEncoder.outputFormatting=[.sortedKeys]
        let patchBeforeTheme=try! themeEncoder.encode(toolsModel.patch)
        let dirtyBeforeTheme=toolsModel.dirty
        for theme in AuroraTheme.allCases {
            toolsModel.selectTheme(theme)
            precondition(try! themeEncoder.encode(toolsModel.patch)==patchBeforeTheme)
            precondition(toolsModel.dirty==dirtyBeforeTheme)
            let themeHost=NSHostingView(rootView:ContentView(m:toolsModel))
            themeHost.frame=NSRect(x:0,y:0,width:1440,height:900);themeHost.layoutSubtreeIfNeeded()
            if let bitmap=themeHost.bitmapImageRepForCachingDisplay(in:themeHost.bounds){themeHost.cacheDisplay(in:themeHost.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-theme-\(theme.rawValue).png"))}
        }
        toolsModel.loadPreset(legacy);precondition(toolsModel.theme == .graphiteOrange)
        toolsModel.undo()
        let creativeID=toolsModel.patch.id
        let creativeHost=NSHostingView(rootView:CreativeToolsView(m:toolsModel))
        creativeHost.frame=NSRect(x:0,y:0,width:1008,height:748);creativeHost.layoutSubtreeIfNeeded()
        if let bitmap=creativeHost.bitmapImageRepForCachingDisplay(in:creativeHost.bounds){creativeHost.cacheDisplay(in:creativeHost.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/aurora-creative-tools.png"))}
        toolsModel.shutdown()
        let creativeRestored=SynthModel(storageDirectory:folder.appendingPathComponent("LayerTools"))
        precondition(creativeRestored.theme == .graphiteOrange)
        print("PASS: all seven themes leave patch data unchanged; theme survives patch loads and restart.")
        precondition(creativeRestored.xySettings==savedXY)
        print("PASS: XY axis ranges, inversion, clamping, assignment swaps, undo/redo, invalid-state rejection and persistence.")
        precondition(creativeRestored.patch.id==creativeID && creativeRestored.macroNames[0]=="Intensity")
        precondition(creativeRestored.savedShapes.first?.name=="Renamed heartbeat" && creativeRestored.directMappings.count==1)
        precondition(creativeRestored.patch.motion?[0].beats==8 && creativeRestored.patch.motion?[0].grid==16)
        creativeRestored.deleteShape(shapeID);precondition(creativeRestored.savedShapes.isEmpty)
        creativeRestored.shutdown()
        print("PASS: synced/grid motion settings, reusable shape CRUD, custom macro ranges/reversal/undo, source-specific MIDI learn with pickup, variation locks and restart persistence.")
        print("PASS: A/B retains edits and restores engine parameters; layer copy includes waves/motion/matrix/sends; paste undo/redo; Solo clears on load; browsing follows filters.")
    }
}
