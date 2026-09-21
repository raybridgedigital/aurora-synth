import AppKit
import Foundation

@inline(never) private func fail(_ message:String)->Never{
    FileHandle.standardError.write(Data("A/B REGRESSION FAIL: \(message)\n".utf8))
    exit(1)
}
private func check(_ ok:@autoclosure()->Bool,_ message:String){if !ok(){fail(message)}}
private func near(_ a:Double,_ b:Double,_ message:String){if !a.isFinite || abs(a-b)>0.000001{fail("\(message) · \(a) != \(b)")}}

@main struct AuroraV1ABComparisonChecks {
    @MainActor static func main(){
        _=NSApplication.shared
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("AuroraV1AB-"+UUID().uuidString)
        let model=SynthModel(storageDirectory:folder)
        defer{
            model.shutdown()
            try? FileManager.default.removeItem(at:folder)
        }

        let sound=FactoryBank.all[0]
        model.loadPreset(sound,panic:false)
        let authored=model.patch.layers[0][7]
        near(Double(aurora_get_parameter(0,7)),authored,"factory cutoff not applied")

        model.set(0,7,1234)
        near(model.patch.layers[0][7],1234,"edited B value missing from model")
        near(Double(aurora_get_parameter(0,7)),1234,"edited B value missing from engine before comparison")

        model.toggleComparison()
        check(model.comparingSaved,"A comparison did not activate")
        near(model.patch.layers[0][7],1234,"A audition mutated edited B model state")
        near(Double(aurora_get_parameter(0,7)),authored,"A audition did not load saved engine value")

        model.toggleComparison()
        check(!model.comparingSaved,"return to B did not leave comparison mode")
        near(model.patch.layers[0][7],1234,"return to B lost edited model value")
        near(Double(aurora_get_parameter(0,7)),1234,"return to B did not restore edited engine value")

        model.persist()
        let saved=try! JSONDecoder().decode(SavedSession.self,from:Data(contentsOf:folder.appendingPathComponent("session.json")))
        near(saved.patch.layers[0][7],1234,"session persistence did not keep edited B value")

        model.toggleComparison()
        check(model.comparingSaved,"second A audition did not activate")
        model.set(0,7,2345)
        check(!model.comparingSaved,"editing while auditioning A did not return to B")
        near(model.patch.layers[0][7],2345,"edit while comparing did not update B model")
        near(Double(aurora_get_parameter(0,7)),2345,"edit while comparing did not update engine")

        print("PASS: isolated A/B audition preserves edited B state, restores engine state, persists B, and editing exits comparison.")
    }
}
