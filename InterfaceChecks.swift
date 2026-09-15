import AppKit
import Combine

@main struct InterfaceChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("AuroraChecks-"+UUID().uuidString)
        let model=SynthModel(storageDirectory:folder)
        defer { aurora_shutdown() }
        precondition(model.collection == "Aurora")
        precondition(FactoryBank.all.count == 112)
        precondition(model.collectionSounds.count == 112)
        model.category="Pads"
        precondition(model.library.count == FactoryBank.all.filter{$0.category == "Pads"}.count)
        model.category="All categories"
        model.search="Velvet Horizon"
        precondition(model.library.count == 1 && model.library[0].id == "velvet")
        model.search="Amber Drift"
        precondition(model.library.count == 1 && model.library[0].id == "a100-amber-drift")
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
        model.setTranspose(12);model.loadPreset(FactoryBank.all[1])
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
        model.loadPreset(FactoryBank.all[0]);precondition((model.patch.phaserMix ?? 0)==0 && model.patch.layers[0][33]==0)
        precondition(model.matrixRows(performance:false).allSatisfy{!$0.enabled} && model.matrixRows(performance:true).allSatisfy{!$0.enabled})
        print("PASS: matrix layer independence, shared-FX targets, undo/redo, saving and legacy patch defaults.")
        print("PASS: 100% master, persistent global transpose, tap tempo, rename preserving edits, delete and undo.")
        print("PASS: Aurora contains all 112 sounds; filters find both original and new patches.")
        print("PASS: 20 stable polls and 1,200 meter changes caused ZERO main-interface publications.")
        print("PASS: 1,200 unchanged meter samples caused ZERO additional publications.")
    }
}
