import AppKit
import Darwin
import Foundation
import SwiftUI

@inline(never) private func fail(_ message:String)->Never {
    FileHandle.standardError.write(Data("BASELINE FAIL: \(message)\n".utf8)); exit(1)
}
private func check(_ ok:@autoclosure()->Bool,_ message:String){if !ok(){fail(message)}}
private func near(_ a:Double,_ b:Double,_ message:String){if !a.isFinite || abs(a-b)>0.000001{fail("\(message) · \(a) != \(b)")}}
private func same(_ a:SoundPreset,_ b:SoundPreset)->Bool {
    a.id==b.id && a.name==b.name && a.category==b.category && a.detail==b.detail &&
    a.layers==b.layers && a.globals==b.globals && a.macros==b.macros && a.phaserMix==b.phaserMix &&
    a.fx==b.fx && a.soundMatrix==b.soundMatrix && a.motion==b.motion && a.sends==b.sends &&
    a.customMacros==b.customMacros && a.xy==b.xy && a.performanceMatrix==b.performanceMatrix &&
    a.importedWavetables==b.importedWavetables
}

@main struct AuroraBaselineChecks {
    @MainActor static func main(){
        _=NSApplication.shared
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("AuroraBaseline-"+UUID().uuidString)
        let model=SynthModel(storageDirectory:folder)
        defer{aurora_shutdown();try? FileManager.default.removeItem(at:folder)}

        let root=NSHostingView(rootView:ContentView(m:model));root.frame=NSRect(x:0,y:0,width:1480,height:940);root.layoutSubtreeIfNeeded()
        check(root.frame.width==1480 && root.frame.height==940,"root ContentView layout")

        check(FactoryBank.expansion.count==0,"Aurora100 count")
        check(FactoryBank.prism.count==0,"Prism count")
        check(FactoryBank.nova.count==0,"Nova count")
        check(FactoryBank.gb.count==60,"GB count")
        check(FactoryBank.shimmer.count==0,"Shimmer count")
        check(Set(FactoryBank.all.map(\.id)).count==FactoryBank.all.count,"duplicate factory IDs")
        check(Set(FactoryBank.all.map{$0.name.lowercased()}).count==FactoryBank.all.count,"duplicate factory names")

        let enc=JSONEncoder(),dec=JSONDecoder()
        for sound in FactoryBank.all {
            check(SynthModel.sanitized(sound) != nil,"invalid factory preset \(sound.id)")
            do{let copy=try dec.decode(SoundPreset.self,from:enc.encode(sound));check(same(sound,copy),"round-trip changed \(sound.id)");check(SynthModel.sanitized(copy) != nil,"round-trip invalid \(sound.id)")}catch{fail("round-trip failed \(sound.id): \(error)")}
            for i in 0..<8 {
                model.patch=sound;model.macro(i,0);near(model.patch.macros[i],0,"macro 0 \(sound.id)/\(i)");check(SynthModel.sanitized(model.patch) != nil,"macro 0 invalid \(sound.id)/\(i)")
                model.patch=sound;model.macro(i,1);near(model.patch.macros[i],1,"macro 1 \(sound.id)/\(i)");check(SynthModel.sanitized(model.patch) != nil,"macro 1 invalid \(sound.id)/\(i)")
            }
            let xy=sound.xy ?? XYSettings();check(xy.valid,"invalid XY \(sound.id)")
            model.patch=sound;model.moveXY(x:1,y:0);near(model.patch.macros[xy.x.macro],xy.x.value(1),"XY X \(sound.id)");near(model.patch.macros[xy.y.macro],xy.y.value(0),"XY Y \(sound.id)");check(SynthModel.sanitized(model.patch) != nil,"XY invalid \(sound.id)")
        }
        var sparse=FactoryBank.make("baseline-sparse","Baseline Sparse","Templates","Contract fixture",a:[:]);sparse.customMacros=[2:CustomMacro(name:"Sparse")]
        check(SynthModel.sanitized(sparse) != nil,"sparse customMacros rejected")

        let first=FactoryBank.all[0],second=FactoryBank.all[FactoryBank.all.count-1]
        model.patch=first;model.applyPatch();model.global(0,0.42);model.setOutputGain(11);model.setEqLow(2.5);model.setEqMid(-1.5);model.setEqHigh(1)
        model.loadPreset(second,panic:false)
        check(model.patch.id==second.id,"patch load");near(model.patch.globals[0],0.42,"master sticky");near(model.outputGain,11,"output gain sticky");near(model.eqLow,2.5,"EQ low sticky");near(model.eqMid,-1.5,"EQ mid sticky");near(model.eqHigh,1,"EQ high sticky")

        let src=FactoryBank.make("baseline-copy","Copy","Templates","Fixture",a:[7:777,13:0.37,14:-0.22])
        let dst=FactoryBank.make("baseline-dst","Destination","Templates","Fixture",a:[7:4321],b:[7:1234])
        model.patch=src;model.copyLayer(0);model.patch=dst;model.pasteLayer(1,panic:false)
        check(model.patch.layers[1]==src.layers[0],"layer copy/paste");check(SynthModel.sanitized(model.patch) != nil,"paste invalid")

        var edit=FactoryBank.make("baseline-undo","Undo","Templates","Fixture",a:[7:1200]);edit.globals[0]=0.5
        model.patch=edit;model.applyPatch();let before=model.patch.layers[0][7];model.checkpoint();model.set(0,7,6400);let after=model.patch.layers[0][7]
        check(after != before,"edit failed");model.undo();near(model.patch.layers[0][7],before,"undo");model.redo();near(model.patch.layers[0][7],after,"redo")

        check(SynthModel.ranges.count==126,"layer parameter ranges did not grow with LFO 3-5")
        near(model.patch.layers[0][101],1,"LFO 3 depth default")
        near(model.patch.layers[0][110],1,"LFO 4 depth default")
        near(model.patch.layers[0][119],1,"LFO 5 depth default")
        var legacy=FactoryBank.make("baseline-lfo","Legacy Matrix","Templates","Six-slot fixture",a:[:])
        var six=Array(repeating:Array(repeating:MatrixAssignment(),count:6),count:4)
        six[1][2]=MatrixAssignment(enabled:true,source:8,destination:29,target:4,cc:1,amount:0.4)
        legacy.soundMatrix=six
        guard let padded=SynthModel.sanitized(legacy) else {fail("legacy six-slot matrix rejected")}
        check(padded.soundMatrix?[1].count==10,"legacy matrix did not pad to ten slots")
        check(padded.soundMatrix?[1][2].source==8 && padded.soundMatrix?[1][2].destination==29,"LFO 5 formant route was dropped")
        check(padded.soundMatrix?[1][9].enabled==false,"padded matrix slot was not empty")
        var blocked=legacy
        blocked.soundMatrix?[0][0]=MatrixAssignment(enabled:true,source:6,destination:9,target:4,cc:1,amount:0.5)
        check(SynthModel.sanitized(blocked)==nil,"sound matrix accepted a shared-FX destination")
        let oldSend=try! dec.decode(LayerSends.self,from:Data("{\"delay\":0.2,\"reverb\":0.4,\"shimmer\":0.3}".utf8))
        check(!oldSend.shimmerBypass,"missing shimmer bypass did not stay off")
        let storedBypass=try! dec.decode(LayerSends.self,from:enc.encode(LayerSends(shimmerBypass:true)))
        check(storedBypass.shimmerBypass,"shimmer bypass did not round-trip")
        model.selectedLayer=2
        model.setShimmerBypass(true)
        check(model.patch.sends?[2].shimmerBypass==true,"layer bypass was not stored on the patch")
        check(model.patch.sends?[0].shimmerBypass != true,"layer bypass leaked onto another layer")
        model.selectedLayer=0
        check(model.matrixRows(performance:false).count==10,"sound matrix row count")
        check(model.matrixRows(performance:true).count==10,"performance matrix row count")
        // Six-row patches (all factory patches) pad to ten; the Matrix screen draws ten rows.
        var sixRows=model.patch;sixRows.performanceMatrix=Array(repeating:MatrixAssignment(),count:6)
        model.patch=sixRows;check(model.matrixRows(performance:true).count==10,"six-row performance matrix pads to ten")
        model.updateMatrix(performance:false,slot:9){$0.enabled=true;$0.source=6;$0.destination=36;$0.amount=0.25}
        check(model.soundRows(0)[9].source==6 && model.soundRows(0)[9].destination==36,"slot 10 did not store LFO 3 to filter envelope")
        check(model.modulationSlots(destination:36,layer:0)==[9],"sound feedback index")
        // Ten performance slots since 0.25.0: the seventh is accepted, an eleventh is not.
        model.updateMatrix(performance:true,slot:6){$0.enabled=true;$0.destination=1}
        check(model.matrixRows(performance:true)[6].enabled && model.patch.performanceMatrix?.count==10,"performance matrix rejected its seventh slot")
        model.updateMatrix(performance:true,slot:10){$0.enabled=true;$0.destination=1}
        check(model.matrixRows(performance:true).count==10 && model.matrixRows(performance:true).filter(\.enabled).count==1,"performance matrix accepted an eleventh slot")

        print("PASS baseline: Aurora v1 model/preset/UI contract")
    }
}
