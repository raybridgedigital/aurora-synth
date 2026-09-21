import AppKit
import Foundation
import SwiftUI

@main struct ABComparisonContract {
    @MainActor static func main() {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Aurora-AB-Contract-"+UUID().uuidString)
        let model = SynthModel(storageDirectory: folder)
        defer {
            model.shutdown()
            try? FileManager.default.removeItem(at: folder)
        }

        let sound = FactoryBank.make("ab-contract","A/B Contract","Templates","Isolated A/B behavior",a:[7:2600])
        model.userPresets = [sound]
        model.loadPreset(sound, panic: false)

        precondition(model.patch.layers[0][7] == 2600)
        precondition(aurora_get_parameter(0,7) == 2600)

        model.set(0,7,1234)
        precondition(model.patch.layers[0][7] == 1234)
        precondition(aurora_get_parameter(0,7) == 1234)

        model.toggleComparison()
        precondition(model.comparingSaved)
        precondition(model.patch.layers[0][7] == 1234)
        precondition(aurora_get_parameter(0,7) == 2600)

        model.toggleComparison()
        precondition(!model.comparingSaved)
        precondition(model.patch.layers[0][7] == 1234)
        precondition(aurora_get_parameter(0,7) == 1234)

        model.persist()
        let saved = try! JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: folder.appendingPathComponent("session.json")))
        precondition(saved.patch.layers[0][7] == 1234)

        model.toggleComparison()
        precondition(model.comparingSaved)
        model.set(0,7,2345)
        precondition(!model.comparingSaved)
        precondition(model.patch.layers[0][7] == 2345)
        precondition(aurora_get_parameter(0,7) == 2345)

        print("PASS: isolated A/B audition restores edited engine state, persists B state, and exits comparison on edit.")
    }
}
