import SwiftUI
import AppKit
import Combine

private let accent = Color(red: 0.72, green: 0.85, blue: 0.58)
private let surface = Color(red: 0.115, green: 0.14, blue: 0.125)
private let raised = Color(red: 0.16, green: 0.19, blue: 0.165)
private let muted = Color(red: 0.64, green: 0.70, blue: 0.65)
private let layerLetters = ["A", "B", "C", "D"]

struct LayerPatch: Codable, Equatable {
    var values: [Int: Double]
    subscript(_ id: Int) -> Double {
        get { values[id] ?? 0 }
        set { values[id] = newValue }
    }
    static var initial: LayerPatch {
        LayerPatch(values: [0:1,1:2,2:1,3:0.35,4:7,5:0.12,6:0,
            7:2600,8:0.15,9:0.025,10:0.35,11:0.75,12:0.7,13:0.65,
            14:0,15:0,16:0.4,17:0.12,18:0,19:0,20:0.15,21:0.08,
            22:0,23:2,24:0,25:1,26:0.65,27:0,28:127,
            29:0.16,30:0.06,31:2,32:0,33:0])
    }
}
struct MatrixAssignment:Codable,Equatable {
    var enabled=false
    var source=0
    var destination=0
    var target=4
    var cc=1
    var amount=0.0
    static let empty=Array(repeating:MatrixAssignment(),count:6)
    func valid(performance:Bool)->Bool {
        (0...(performance ? 5:2)).contains(source) && (0...(performance ? 11:5)).contains(destination) && (0...4).contains(target) && (0...127).contains(cc) && amount.isFinite && (-1...1).contains(amount)
    }
}
struct SoundPreset: Identifiable, Codable {
    var id: String
    var name: String
    var category: String
    var detail: String
    var layers: [LayerPatch]
    var globals: [Double]
    var macros: [Double]
    var phaserMix: Double? = nil
    var soundMatrix: [[MatrixAssignment]]? = nil
    var performanceMatrix: [MatrixAssignment]? = nil
}
struct AudioDevice: Identifiable, Decodable, Equatable {
    var id: UInt32
    var name: String
    var uid: String?
    var sampleRate: Double?
}
struct MIDISource: Identifiable, Decodable, Equatable {
    var id: Int32
    var name: String
    var enabled: Bool?
    var layerMask: Int?
    var channel: Int?
    var events: UInt64?
}
struct SourceRoute: Codable {
    var mask: Int
    var channel: Int
}
struct CCMapping: Codable {
    var source: Int32
    var channel: Int
    var controller: Int
    var macro: Int
}
struct SavedSession: Codable {
    var version: Int = 1
    var patch: SoundPreset
    var favorites: Set<String>
    var routes: [Int32: SourceRoute]
    var mappings: [CCMapping]
    var outputUID: String?
    var buffer: Int
    var transpose: Int? = nil
    var deletedSound: SoundPreset? = nil
}

enum FactoryBank {
    static func make(_ id: String, _ name: String, _ category: String, _ detail: String,
                     a: [Int:Double], b: [Int:Double]? = nil,
                     effects: [Double] = [0.25,110,0.15,0.3,0.22,0.12]) -> SoundPreset {
        var layers = Array(repeating: LayerPatch.initial, count: 4)
        for i in 1..<4 { layers[i][0] = 0 }
        for (k,v) in a { layers[0][k] = v }
        if let b { for (k,v) in b { layers[1][k] = v }; layers[1][0] = 1 }
        return SoundPreset(id:id,name:name,category:category,detail:detail,layers:layers,
                           globals:effects,macros:Array(repeating:0.5,count:8))
    }
    static let categoryOrder = ["Pads", "Bass", "Leads", "Keys", "Plucks", "Arps", "Textures", "Organs", "Brass & Strings", "Splits", "Templates"]
    static let expansion: [SoundPreset] = {
        guard let url = Bundle.main.url(forResource: "Aurora100", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let sounds = try? JSONDecoder().decode([SoundPreset].self, from: data),
              sounds.count == 100 else { return [] }
        return sounds
    }()
    static let all: [SoundPreset] = expansion + starter
    static let starter: [SoundPreset] = [
        make("velvet", "Velvet Horizon", "Pads", "Warm analog layers, slow movement, and a little room to breathe.",
             a:[1:2,2:1,7:1800,9:0.65,12:2.4,17:0.16,13:0.48,14:-0.2],
             b:[1:4,2:0,7:3200,9:1.1,12:3.1,13:0.25,14:0.2,15:12]),
        make("glass", "Glass & Ember", "Keys", "Clear, bell-like harmonics with a warm, soft tail.",
             a:[1:4,2:0,3:0.72,7:5800,9:0.003,10:1.1,11:0.14,12:1.0,5:0,17:0.03,20:0.4]),
        make("orbit", "Low Orbit", "Bass", "A round bass with a focused attack and solid foundation.",
             a:[1:2,2:3,7:650,9:0.002,10:0.22,11:0.55,12:0.12,5:0.35,15:-12,20:0.55,21:0.23,17:0],
             effects:[0.25,110,0,0.2,0.04,0]),
        make("paper", "Paper Satellites", "Plucks", "A light, shifting pluck that leaves trails in the air.",
             a:[1:4,2:2,7:3900,9:0.001,10:0.3,11:0.05,12:0.3,20:0.6,17:0.2],
             effects:[0.25,118,0.28,0.38,0.24,0.1]),
        make("after", "After Hours", "Keys", "Mellow synthetic electric keys for late-night playing.",
             a:[1:0,2:4,3:0.4,7:2100,9:0.006,10:0.8,11:0.35,12:0.55,21:0.1,20:0.3,5:0.03]),
        make("north", "Northern Lights", "Pads", "An airy texture with wide, gently moving layers.",
             a:[1:4,2:2,7:3300,9:1.8,12:4.2,17:0.32,13:0.4,14:-0.35],
             b:[1:1,2:0,7:6400,15:12,9:2.2,12:3.6,13:0.22,14:0.35,17:0.17],
             effects:[0.25,95,0.21,0.4,0.38,0.22]),
        make("copper", "Copper Wire", "Leads", "A bright, animated lead. Add expression with the mod wheel.",
             a:[1:2,2:3,3:0.3,7:4200,9:0.007,10:0.2,11:0.7,12:0.22,4:11,17:0.03,21:0.15]),
        make("tide", "Tidal Steps", "Arps", "Hold a chord and let the arpeggiator find its way.",
             a:[1:2,2:4,7:2200,9:0.002,10:0.22,11:0.16,12:0.23,22:1,23:2,24:2,25:2,20:0.4],
             effects:[0.25,108,0.24,0.33,0.18,0.08]),
        make("pulse", "Midnight Pulse", "Arps", "A descending pulse with a short envelope and rhythmic echo.",
             a:[1:3,2:2,7:1200,9:0.002,10:0.15,11:0.08,12:0.12,22:1,23:1,24:1,25:2,20:0.5],
             effects:[0.25,120,0.2,0.4,0.12,0.08]),
        make("dust", "Warm Dust", "Textures", "Soft noise and slow filter motion over a steady harmonic core.",
             a:[1:1,2:4,7:1400,6:0.12,9:0.9,12:2.8,17:0.35,16:0.15,20:0.2]),
        make("split", "Bass / Sky", "Splits", "Bass below middle C. A soft pad from middle C upward.",
             a:[1:2,2:3,7:700,9:0.002,12:0.15,28:59,20:0.45,5:0.3],
             b:[1:4,2:1,7:2500,9:0.5,12:2.1,27:60,13:0.48]),
        make("init", "Init · clean canvas", "Templates", "One oscillator, no motion or effects. Start with a single idea.",
             a:[1:2,2:0,3:0,5:0,7:16000,9:0.005,10:0.2,11:0.8,12:0.25,17:0,30:0,20:0,21:0],
             effects:[0.25,110,0,0,0,0])
    ]
}

struct MeterSnapshot: Equatable {
    var peak:Float=0
    var cpuPercent:Int=0
    var voices:Int=0
    var midiEvents:UInt64=0
}
@MainActor final class AudioTelemetry:ObservableObject {
    @Published private(set) var snapshot=MeterSnapshot()
    func update(peak:Float,load:Float,voices:Int,midiEvents:UInt64) {
        let safePeak=peak.isFinite ? max(0,min(1,peak)):0
        let safeLoad=load.isFinite ? max(0,min(100,load)):0
        let next=MeterSnapshot(peak:(safePeak*1000).rounded()/1000,cpuPercent:Int(safeLoad*100),voices:voices,midiEvents:midiEvents)
        if snapshot != next { snapshot=next }
    }
}
@MainActor final class ScopeTelemetry:ObservableObject {
    @Published private(set) var samples=Array(repeating:Float(0),count:256)
    func update() {
        var next=Array(repeating:Float(0),count:256)
        let count=next.withUnsafeMutableBufferPointer{aurora_copy_scope($0.baseAddress,Int32($0.count))}
        if count>0 && next != samples {samples=next}
    }
}
struct OutputScope:View {
    @ObservedObject var telemetry:ScopeTelemetry
    var body:some View {
        Canvas{context,size in
            var center=Path();center.move(to:CGPoint(x:0,y:size.height/2));center.addLine(to:CGPoint(x:size.width,y:size.height/2))
            context.stroke(center,with:.color(muted.opacity(0.2)),lineWidth:0.5)
            var wave=Path()
            for (i,sample) in telemetry.samples.enumerated(){
                let point=CGPoint(x:CGFloat(i)*size.width/CGFloat(telemetry.samples.count-1),y:size.height/2-CGFloat(max(-1,min(1,sample*3)))*(size.height/2-3))
                if i==0{wave.move(to:point)}else{wave.addLine(to:point)}
            }
            context.stroke(wave,with:.color(accent),lineWidth:1)
        }.background(Color.black.opacity(0.2),in:RoundedRectangle(cornerRadius:5)).accessibilityLabel("Live output waveform").help("Live output scope")
    }
}
struct EngineReadout:View {
    @ObservedObject var telemetry:AudioTelemetry
    var body:some View { Text("MIDI \(telemetry.snapshot.midiEvents) · DSP \(telemetry.snapshot.cpuPercent)%").monospacedDigit() }
}
struct VoiceStatus:View {
    @ObservedObject var telemetry:AudioTelemetry
    let running:Bool
    var body:some View {
        HStack{Label("\(telemetry.snapshot.voices) voices",systemImage:"waveform");Spacer();Text(running ? "Ready to play":"Enable audio in the header to start")}
    }
}

@MainActor final class SynthModel: ObservableObject {
    @Published var patch = FactoryBank.all[0]
    @Published var userPresets: [SoundPreset] = []
    @Published var selectedLayer = 0
    @Published var screen = "Play"
    @Published var search = ""
    @Published var collection = "Aurora"
    @Published var category = "All categories"
    @Published var favoritesOnly = false
    @Published var favorites: Set<String> = []
    @Published var devices: [AudioDevice] = []
    @Published var sources: [MIDISource] = []
    @Published var output: UInt32 = 0
    @Published var buffer = 128
    @Published var running = false
    @Published var status = "Audio is off. Choose your output, then enable audio."
    let telemetry = AudioTelemetry()
    let scope=ScopeTelemetry()
    @Published var sampleRate = 0.0
    @Published var actualFrames: UInt32 = 0
    @Published var pressed: Set<Int> = []
    @Published var routes: [Int32:SourceRoute] = [:]
    @Published var mappings: [CCMapping] = []
    @Published var learningMacro: Int? = nil
    @Published var notice = ""
    @Published var dirty = false
    @Published var saveName = ""
    @Published var showingSave = false
    @Published var transpose = 0
    @Published var renameID: String? = nil
    @Published var renameName = ""
    @Published var deletedSound: SoundPreset? = nil
    private var tapTimes: [TimeInterval] = []
    func setTranspose(_ value:Int) {
        transpose=max(-24,min(24,value));aurora_set_transpose(Int32(transpose));persist()
    }
    func tapTempo(at time:TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let last=tapTimes.last, time-last > 3 || time <= last {tapTimes=[]}
        tapTimes.append(time);if tapTimes.count>5{tapTimes.removeFirst()}
        if tapTimes.count>1 {
            let interval=(tapTimes.last!-tapTimes.first!)/Double(tapTimes.count-1)
            checkpoint();global(1,(60/interval).rounded())
        }
    }
    func renameSound() {
        let name=String(renameName.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120))
        guard let id=renameID,!name.isEmpty,let i=userPresets.firstIndex(where:{$0.id==id}) else{return}
        userPresets[i].name=name;if patch.id==id{patch.name=name}
        renameID=nil;persist();notice="Sound renamed to \(name)."
    }
    func deleteSound(_ id:String) {
        guard let i=userPresets.firstIndex(where:{$0.id==id}) else{return}
        deletedSound=userPresets.remove(at:i)
        persist();notice="Sound deleted. Undo Delete is available in the library menu."
    }
    func undoDelete() {
        guard let sound=deletedSound else{return}
        userPresets.insert(sound,at:0);deletedSound=nil;persist()
    }
    private var timer: Timer?
    private var lastSessionData:Data?
    private var lastPresetData:Data?
    private var ticks = 0
    private var lastCCCount: UInt64 = 0
    private var pickup: Set<Int> = []
    private var previousCC: [Int:Double] = [:]
    private var monitors: [Any] = []
    private var outputUID: String?
    private var undoPatches: [SoundPreset] = []
    private var redoPatches: [SoundPreset] = []
    private static let ranges: [ClosedRange<Double>] = [0...1,0...4,0...4,0...1,0...30,0...1,0...1,30...18000,0...0.9,0.001...8,0.01...8,0...1,0.01...12,0...1,-1...1,-48...48,0.03...20,0...1,0...3,0...4,-1...1,0...1,0...1,0...3,0...3,1...4,0.1...0.95,0...127,0...127,0.03...20,0...1,0...3,0...2,0...4]
    private static let integerParameters: Set<Int> = [0,1,2,15,18,19,22,23,24,25,27,28,31,32,33]
    private static let globalRanges: [ClosedRange<Double>] = [0...1,30...240,0...0.6,0...0.75,0...0.75,0...0.6,0...1]
    private static func sanitized(_ input:SoundPreset) -> SoundPreset? {
        guard input.layers.count==4,input.globals.count==6,input.macros.count==8,
              input.globals.allSatisfy(\.isFinite),input.macros.allSatisfy(\.isFinite) else{return nil}
        guard (input.phaserMix ?? 0).isFinite else{return nil}
        if let matrix=input.soundMatrix {guard matrix.count==4,matrix.allSatisfy({$0.count==6 && $0.allSatisfy{$0.valid(performance:false)}}) else{return nil}}
        if let matrix=input.performanceMatrix {guard matrix.count==6,matrix.allSatisfy({$0.valid(performance:true)}) else{return nil}}
        var result=input
        result.phaserMix=max(0,min(1,input.phaserMix ?? 0))
        for i in 0..<4 {
            guard input.layers[i].values.allSatisfy({(0..<ranges.count).contains($0.key) && $0.value.isFinite}) else{return nil}
            var layer=LayerPatch.initial
            for (p,v) in input.layers[i].values {
                let r=ranges[p],clipped=max(r.lowerBound,min(r.upperBound,v))
                layer[p]=integerParameters.contains(p) ? clipped.rounded():clipped
            }
            if layer[27]>layer[28]{layer[28]=layer[27]}
            result.layers[i]=layer
        }
        for p in 0..<6 {result.globals[p]=max(globalRanges[p].lowerBound,min(globalRanges[p].upperBound,input.globals[p]))}
        result.macros=input.macros.map{max(0,min(1,$0))}
        result.name=String(input.name.prefix(120));result.detail=String(input.detail.prefix(500));result.category=String(input.category.prefix(60))
        return result
    }
    private let keyNotes: [UInt16:Int] = [0:60,13:61,1:62,14:63,2:64,3:65,17:66,5:67,16:68,4:69,32:70,38:71,40:72,31:73,37:74,35:75,41:76]
    let macroNames = ["Brightness","Warmth","Movement","Space","Attack","Release","Width","Character"]
    var collectionSounds: [SoundPreset] {
        switch collection {
        case "Aurora": return FactoryBank.all
        case "Your sounds": return userPresets
        default: return userPresets + FactoryBank.all
        }
    }
    func orderedCategories(_ sounds: [SoundPreset]) -> [String] {
        let categories = Set(sounds.map(\.category))
        return FactoryBank.categoryOrder.filter { categories.contains($0) }
            + categories.subtracting(FactoryBank.categoryOrder).sorted()
    }
    var categories: [String] { orderedCategories(collectionSounds) }
    var library: [SoundPreset] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return collectionSounds.filter {
            (category == "All categories" || $0.category == category) &&
            (!favoritesOnly || favorites.contains($0.id)) &&
            (query.isEmpty || ($0.name + " " + $0.category + " " + $0.detail).localizedCaseInsensitiveContains(query))
        }
    }
    var libraryGroups: [(category: String, sounds: [SoundPreset])] {
        let sounds = library
        return orderedCategories(sounds).map { category in
            (category, sounds.filter { $0.category == category }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
    private var storageDirectory: URL?
    private var folder: URL {
        if let storageDirectory {return storageDirectory}
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Aurora",isDirectory:true)
    }
    init(storageDirectory:URL? = nil) {
        self.storageDirectory=storageDirectory
        aurora_initialize()
        restore()
        if FactoryBank.expansion.isEmpty {
            notice="Aurora 100 could not be loaded. Rebuild or reopen the complete app bundle."
        }
        applyPatch()
        refresh()
        installKeyboard()
        let updateTimer = Timer(timeInterval:0.05,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        updateTimer.tolerance=0.005
        RunLoop.main.add(updateTimer,forMode:.common)
        timer=updateTimer
    }
    func applyPatch() {
        applyMatrix()
        aurora_set_transpose(Int32(transpose))
        aurora_set_global(6,Float(patch.phaserMix ?? 0))
        for i in 0..<4 { aurora_set_parameter(Int32(i),33,Float(patch.layers[i][33]));for (p,v) in patch.layers[i].values { aurora_set_parameter(Int32(i),Int32(p),Float(v)) } }
        for (p,v) in patch.globals.enumerated() { aurora_set_global(Int32(p),Float(v)) }
    }
    func matrixRows(performance:Bool)->[MatrixAssignment] {
        performance ? (patch.performanceMatrix ?? MatrixAssignment.empty):(patch.soundMatrix?[selectedLayer] ?? MatrixAssignment.empty)
    }
    func updateMatrix(performance:Bool,slot:Int,change:(inout MatrixAssignment)->Void) {
        guard (0..<6).contains(slot) else{return}
        var rows=matrixRows(performance:performance);change(&rows[slot])
        if performance && rows[slot].destination>=8{rows[slot].target=4}
        guard rows[slot].valid(performance:performance) else{return}
        if performance{patch.performanceMatrix=rows}else{
            var matrix=patch.soundMatrix ?? Array(repeating:MatrixAssignment.empty,count:4)
            matrix[selectedLayer]=rows;patch.soundMatrix=matrix
        }
        applyMatrix();dirty=true
    }
    func applyMatrix() {
        for bank in 0..<5 {
            let rows=bank==4 ? (patch.performanceMatrix ?? MatrixAssignment.empty):(patch.soundMatrix?[bank] ?? MatrixAssignment.empty)
            for (slot,row) in rows.enumerated(){aurora_set_matrix(Int32(bank),Int32(slot),row.enabled ? 1:0,Int32(row.source),Int32(row.destination),Int32(row.target),Int32(row.cc),Float(row.amount))}
        }
    }
    func checkpoint() {
        if undoPatches.last?.layers != patch.layers || undoPatches.last?.globals != patch.globals || undoPatches.last?.phaserMix != patch.phaserMix || undoPatches.last?.soundMatrix != patch.soundMatrix || undoPatches.last?.performanceMatrix != patch.performanceMatrix {
            undoPatches.append(patch); if undoPatches.count > 40 { undoPatches.removeFirst() }; redoPatches = []
        }
    }
    func undo() { guard let old = undoPatches.popLast() else { return }; redoPatches.append(patch); patch=old;applyPatch();dirty=true;pickup=[];previousCC=[:] }
    func redo() { guard let old = redoPatches.popLast() else { return }; undoPatches.append(patch);patch=old;applyPatch();dirty=true;pickup=[];previousCC=[:] }
    func loadPreset(_ preset: SoundPreset) {
        checkpoint()
        let master=patch.globals[0]
        aurora_panic();pressed=[]
        patch=preset; patch.globals[0]=master
        applyPatch();dirty=false;pickup=[];previousCC=[:]
        notice="Loaded \(preset.name). Previous edits are available with Undo."
        persist()
    }
    func set(_ layer:Int,_ parameter:Int,_ value:Double) {
        guard (0..<4).contains(layer),Self.ranges.indices.contains(parameter),value.isFinite else{return}
        let range=Self.ranges[parameter]
        var value=max(range.lowerBound,min(range.upperBound,value))
        if Self.integerParameters.contains(parameter){value=value.rounded()}
        if parameter==27{value=min(value,patch.layers[layer][28])}
        if parameter==28{value=max(value,patch.layers[layer][27])}
        patch.layers[layer][parameter]=value
        aurora_set_parameter(Int32(layer),Int32(parameter),Float(value));dirty=true
    }
    func global(_ parameter:Int,_ value:Double) {
        guard Self.globalRanges.indices.contains(parameter),value.isFinite else{return}
        let r=Self.globalRanges[parameter],value=max(r.lowerBound,min(r.upperBound,value))
        if parameter==6{patch.phaserMix=value}else{patch.globals[parameter]=value};aurora_set_global(Int32(parameter),Float(value));dirty=true
    }
    func parameter(_ parameter:Int, layer:Int?=nil) -> Binding<Double> {
        let l=layer ?? selectedLayer
        return Binding(get:{self.patch.layers[l][parameter]},set:{self.set(l,parameter,$0)})
    }
    func globalBinding(_ parameter:Int) -> Binding<Double> {
        Binding(get:{parameter==6 ? (self.patch.phaserMix ?? 0):self.patch.globals[parameter]},set:{self.global(parameter,$0)})
    }
    func macro(_ index:Int,_ value:Double) {
        let value=max(0,min(1,value));let delta=value-patch.macros[index]
        patch.macros[index]=value
        for i in 0..<4 {
            let l=patch.layers[i]
            switch index {
            case 0:set(i,7,max(30,min(18000,l[7]*pow(2,delta*6))))
            case 1:set(i,21,max(0,min(1,l[21]+delta*0.65)))
            case 2:set(i,17,max(0,min(1,l[17]+delta*0.65)))
            case 4:set(i,9,max(0.001,min(8,l[9]*pow(2,delta*8))))
            case 5:set(i,12,max(0.01,min(12,l[12]*pow(2,delta*6))))
            case 6:set(i,14,(i%2==0 ? -1.0:1.0)*value*0.65)
            case 7:set(i,3,max(0,min(1,l[3]+delta)))
            default:break
            }
        }
        if index==3 { global(4,max(0,min(0.75,patch.globals[4]+delta*0.7)));global(2,max(0,min(0.6,patch.globals[2]+delta*0.4))) }
        if index==6 { global(5,value*0.4) }
        dirty=true
    }
    func refresh(force:Bool=true) {
        if force { aurora_refresh_devices() }
        func decode<T:Decodable>(_ type:T.Type,_ pointer:UnsafePointer<CChar>?) -> T? {
            guard let pointer else {return nil};return try? JSONDecoder().decode(type,from:Data(String(cString:pointer).utf8))
        }
        let nextDevices=decode([AudioDevice].self,aurora_audio_devices_json()) ?? []
        let nextSources=decode([MIDISource].self,aurora_midi_sources_json()) ?? []
        if devices != nextDevices { devices=nextDevices }
        if sources != nextSources { sources=nextSources }
        if output==0, let uid=outputUID,let d=devices.first(where:{$0.uid==uid}) { output=d.id }
        for source in sources {
            if let route=routes[source.id] {
                if source.layerMask != route.mask || source.channel != route.channel {aurora_route_source(source.id,Int32(route.mask),Int32(route.channel))}
            }
            else { routes[source.id]=SourceRoute(mask:source.layerMask ?? ((source.enabled ?? true) ? 1:0),channel:source.channel ?? 0) }
        }
    }
    func poll() {
        ticks += 1
        // Keep disk work and device-list updates out of live scroll/drag tracking.
        if RunLoop.main.currentMode != .eventTracking {
            if ticks % 40 == 0 { refresh(force:false) }
            if ticks % 100 == 0 { persist() }
        }
        let nextRunning=aurora_audio_running() != 0
        let nextRate=aurora_sample_rate(), nextFrames=aurora_buffer_frames()
        if running != nextRunning { running=nextRunning }
        if sampleRate != nextRate { sampleRate=nextRate }
        if actualFrames != nextFrames { actualFrames=nextFrames }
        scope.update()
        telemetry.update(peak:aurora_output_peak(),load:aurora_cpu_load(),voices:Int(aurora_active_voices()),midiEvents:aurora_midi_event_count())
        if let p=aurora_status() {
            let nextStatus=String(cString:p)
            if status != nextStatus { status=nextStatus }
        }
        let count=aurora_cc_count()
        if count != lastCCCount {
            lastCCCount=count
            let cc=aurora_last_cc_snapshot();guard cc != UInt64.max else{return}
            let source=Int32(bitPattern:UInt32(cc>>32)),channel=Int((cc>>16)&255),controller=Int((cc>>8)&255),value=Double(cc&255)/127
            if let index=learningMacro {
                if controller==64 {notice="Sustain stays assigned to the pedal. Move a knob to learn it.";return}
                mappings.removeAll{$0.macro==index || ($0.source==source && $0.channel==channel && $0.controller==controller)}
                mappings.append(CCMapping(source:source,channel:channel,controller:controller,macro:index))
                learningMacro=nil;pickup.remove(index);previousCC[index]=value;notice="CC \(controller) learned for \(macroNames[index]). Cross the current value to take control.";persist()
            } else {
                for mapping in mappings where mapping.source==source && mapping.channel==channel && mapping.controller==controller {
                    let target=patch.macros[mapping.macro],previous=previousCC[mapping.macro] ?? value
                    previousCC[mapping.macro]=value
                    if pickup.contains(mapping.macro) || abs(value-target)<0.04 || (previous-target)*(value-target)<=0 {
                        pickup.insert(mapping.macro);macro(mapping.macro,value)
                    }
                }
            }
        }
    }
    func setRoute(_ source:Int32,_ route:SourceRoute) {
        routes[source]=route;aurora_route_source(source,Int32(route.mask),Int32(route.channel));persist()
    }
    func toggleAudio() {
        notice=""
        if running {aurora_stop_audio();pressed=[]}
        else { _=aurora_start_audio(output,UInt32(buffer));output=aurora_current_device() }
        poll()
    }
    func changeOutput(_ id:UInt32) {
        if running { aurora_stop_audio();pressed=[];notice="Output changed. Enable audio when you're ready." }
        output=id;outputUID=devices.first(where:{$0.id==id})?.uid;persist()
    }
    func noteOn(_ note:Int) { guard !pressed.contains(note) else{return};pressed.insert(note);aurora_note_on(Int32(note),90) }
    func noteOff(_ note:Int) { guard pressed.contains(note) else{return};pressed.remove(note);aurora_note_off(Int32(note)) }
    func panic() {aurora_panic();pressed=[];notice="All notes and effect tails stopped."}
    func favorite(_ id:String) { if favorites.contains(id){favorites.remove(id)}else{favorites.insert(id)};persist() }
    func saveUserPreset() {
        let name=saveName.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty else{return}
        var copy=patch;copy.id=UUID().uuidString;copy.name=name;copy.detail="Your own Aurora performance."
        userPresets.insert(copy,at:0);patch=copy;dirty=false;showingSave=false
        collection="Your sounds";category="All categories";search="";favoritesOnly=false
        persist();notice="Saved \(name)."
    }
    func exportPreset() {
        let panel=NSSavePanel();panel.nameFieldStringValue=patch.name+".aurora.json";panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try JSONEncoder().encode(patch).write(to:url,options:.atomic);notice="Preset exported."}catch{notice="Could not export: \(error.localizedDescription)"}
    }
    func importPreset() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let data=try Data(contentsOf:url);guard data.count<1_000_000 else{throw CocoaError(.fileReadCorruptFile)}
            let decoded=try JSONDecoder().decode(SoundPreset.self,from:data)
            guard var item=Self.sanitized(decoded) else{throw CocoaError(.fileReadCorruptFile)}
            item.id=UUID().uuidString;userPresets.insert(item,at:0);loadPreset(item)
            collection="Your sounds";category="All categories";search="";favoritesOnly=false;persist()
        } catch { notice="This preset could not be imported: \(error.localizedDescription)" }
    }
    func persist() {
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let saved=SavedSession(patch:patch,favorites:favorites,routes:routes,mappings:mappings,outputUID:outputUID,buffer:buffer,transpose:transpose,deletedSound:deletedSound)
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            let sessionData=try encoder.encode(saved), presetData=try encoder.encode(userPresets)
            if sessionData != lastSessionData {
                try sessionData.write(to:folder.appendingPathComponent("session.json"),options:.atomic)
                lastSessionData=sessionData
            }
            if presetData != lastPresetData {
                try presetData.write(to:folder.appendingPathComponent("presets.json"),options:.atomic)
                lastPresetData=presetData
            }
        }catch{notice="Couldn't save the session: \(error.localizedDescription)"}
    }
    func restore() {
        if let data=try? Data(contentsOf:folder.appendingPathComponent("session.json")),let s=try? JSONDecoder().decode(SavedSession.self,from:data),s.version==1,let valid=Self.sanitized(s.patch) {
            deletedSound=s.deletedSound.flatMap{Self.sanitized($0)}
            transpose=max(-24,min(24,s.transpose ?? 0))
            patch=valid;favorites=s.favorites;routes=s.routes.filter{(0...15).contains($0.value.mask) && (0...16).contains($0.value.channel)}
            mappings=s.mappings.filter{(0..<8).contains($0.macro) && (0...127).contains($0.controller) && (1...16).contains($0.channel)}
            outputUID=s.outputUID;buffer=[64,128,256,512].contains(s.buffer) ? s.buffer:128
        }
        if let data=try? Data(contentsOf:folder.appendingPathComponent("presets.json")),let list=try? JSONDecoder().decode([SoundPreset].self,from:data){userPresets=list.compactMap{Self.sanitized($0)}}
    }
    func installKeyboard() {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]) { [weak self] event in
            guard let self,NSApp.keyWindow?.firstResponder is NSTextView == false,!event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),!event.modifierFlags.contains(.option),let note=self.keyNotes[event.keyCode] else{return event}
            if event.type == .keyDown {if !event.isARepeat{self.noteOn(note)}}else{self.noteOff(note)}
            return nil
        } as Any)
        NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main){[weak self] _ in
            Task { @MainActor in guard let self else{return};for note in Array(self.pressed){self.noteOff(note)} }
        }
    }
    func shutdown() {persist();timer?.invalidate();for m in monitors{NSEvent.removeMonitor(m)};aurora_shutdown()}
}

struct EqualHeightRow: Layout {
    var spacing: CGFloat = 16
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width=proposal.width ?? 900
        let cell=(width-spacing*CGFloat(max(0,subviews.count-1)))/CGFloat(max(1,subviews.count))
        return CGSize(width:width,height:subviews.map{$0.sizeThatFits(.init(width:cell,height:nil)).height}.max() ?? 0)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let cell=(bounds.width-spacing*CGFloat(max(0,subviews.count-1)))/CGFloat(max(1,subviews.count))
        for (i,view) in subviews.enumerated(){view.place(at:CGPoint(x:bounds.minX+CGFloat(i)*(cell+spacing),y:bounds.minY),anchor:.topLeading,proposal:.init(width:cell,height:bounds.height))}
    }
}
struct Panel<Content:View>:View {
    let title:String
    @ViewBuilder var content:Content
    var body:some View {VStack(alignment:.leading,spacing:16){Text(title).font(.system(size:19,weight:.semibold));content}.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(surface,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.07)))}
}
struct ParameterSlider:View {
    let title:String
    @Binding var value:Double
    var range:ClosedRange<Double>=0...1
    var logarithmic=false
    var format:(Double)->String = {String(format:"%.0f%%",$0*100)}
    var onBegin:()->Void = {}
    var normalized:Binding<Double> {
        Binding(get:{logarithmic ? log(max(range.lowerBound,value)/range.lowerBound)/log(range.upperBound/range.lowerBound):(value-range.lowerBound)/(range.upperBound-range.lowerBound)},set:{v in value=logarithmic ? range.lowerBound*pow(range.upperBound/range.lowerBound,v):range.lowerBound+v*(range.upperBound-range.lowerBound)})
    }
    var body:some View {
        VStack(spacing:5){HStack{Text(title).foregroundStyle(muted);Spacer();Text(format(value)).monospacedDigit()}.font(.system(size:15));Slider(value:normalized,in:0...1,onEditingChanged:{if $0{onBegin()}}).tint(accent).accessibilityLabel(title).accessibilityValue(format(value))}
    }
}
struct MacroDial:View {
    @ObservedObject var model:SynthModel
    let index:Int
    var value:Double{model.patch.macros[index]}
    var body:some View {
        VStack(spacing:9){
            ZStack{
                Circle().trim(from:0.125,to:0.875).stroke(raised,lineWidth:5).rotationEffect(.degrees(90))
                Circle().trim(from:0.125,to:0.125+value*0.75).stroke(accent,style:StrokeStyle(lineWidth:5,lineCap:.round)).rotationEffect(.degrees(90))
                Circle().fill(surface).padding(10)
                Capsule().fill(accent).frame(width:3,height:15).offset(y:-25).rotationEffect(.degrees(-135+270*value))
            }.frame(width:88,height:88).accessibilityHidden(true)
            HStack{Text(model.macroNames[index]);Spacer();Text("\(Int(value*100))").foregroundStyle(muted).monospacedDigit()}.font(.system(size:15,weight:.medium))
            Slider(value:Binding(get:{value},set:{model.macro(index,$0)}),in:0...1,onEditingChanged:{if $0{model.checkpoint()}}).tint(accent).accessibilityLabel(model.macroNames[index])
            Button{model.learningMacro = model.learningMacro==index ? nil:index;model.notice=model.learningMacro==nil ? "MIDI Learn cancelled.":"Move a hardware knob for \(model.macroNames[index])."}label:{Label(model.learningMacro==index ? "Move a knob…":model.mappings.contains(where:{$0.macro==index}) ? "Mapped":"MIDI Learn",systemImage:"cable.connector")}.buttonStyle(.plain).font(.system(size:13)).foregroundStyle(model.learningMacro==index ? accent:muted)
        }.frame(maxWidth:.infinity).padding(.vertical,8)
    }
}
struct LayerStrip:View {
    @ObservedObject var model:SynthModel
    let index:Int
    var body:some View {
        VStack(alignment:.leading,spacing:9){
            HStack{
                Button{model.selectedLayer=index;if model.screen != "Matrix"{model.screen="Edit"}}label:{Text(layerLetters[index]).font(.system(size:15,weight:.bold)).frame(width:32,height:29).background(model.selectedLayer==index ? accent:raised,in:RoundedRectangle(cornerRadius:5)).foregroundStyle(model.selectedLayer==index ? Color.black:Color.white)}.buttonStyle(.plain)
                Spacer()
                Button{model.checkpoint();model.set(index,0,model.patch.layers[index][0]>0.5 ? 0:1)}label:{Image(systemName:"power").foregroundStyle(model.patch.layers[index][0]>0.5 ? accent:muted)}.buttonStyle(.plain).accessibilityLabel("Enable layer \(layerLetters[index])")
            }
            Picker("Layer \(layerLetters[index]) waveform",selection:Binding(get:{Int(model.patch.layers[index][1])},set:{model.checkpoint();model.set(index,1,Double($0));model.selectedLayer=index})){
                ForEach(Array(["Sine","Triangle","Saw","Pulse","Harmonic"].enumerated()),id:\.offset){i,name in Text(name).tag(i)}
            }.labelsHidden().font(.system(size:16,weight:.medium))
            HStack{Text("\(Int(model.patch.layers[index][27]))–\(Int(model.patch.layers[index][28]))");Spacer();Text(model.patch.layers[index][22]>0.5 ? "ARP":"POLY")}.font(.system(size:13)).foregroundStyle(muted)
            Slider(value:model.parameter(13,layer:index),in:0...1,onEditingChanged:{if $0{model.checkpoint()}}).tint(accent).accessibilityLabel("Layer \(layerLetters[index]) volume")
        }.padding(13).background(surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(model.selectedLayer==index ? accent.opacity(0.55):.white.opacity(0.08))).opacity(model.patch.layers[index][0]>0.5 ? 1:0.65).contentShape(Rectangle()).onTapGesture{model.selectedLayer=index;if model.screen != "Matrix"{model.screen="Edit"}}
    }
}
struct PianoView:View {
    @ObservedObject var model:SynthModel
    private let whites=(48...84).filter{[0,2,4,5,7,9,11].contains($0%12)}
    private var blacks:[(Int,Int)]{(48...84).filter{[1,3,6,8,10].contains($0%12)}.map{note in (note,whites.filter{$0<note}.count-1)}}
    func key(_ note:Int,black:Bool)->some View {
        RoundedRectangle(cornerRadius:4).fill(model.pressed.contains(note) ? accent:(black ? Color(red:0.08,green:0.10,blue:0.085):Color(red:0.81,green:0.84,blue:0.79)))
            .overlay(alignment:.bottom){if !black{Text(note%12==0 ? "C\(note/12-1)":"").font(.system(size:12)).foregroundStyle(.black.opacity(0.5)).padding(.bottom,7)}}
            .gesture(DragGesture(minimumDistance:0).onChanged{_ in model.noteOn(note)}.onEnded{_ in model.noteOff(note)})
            .accessibilityElement(children:.ignore).accessibilityLabel("MIDI note \(note)").accessibilityAddTraits(.isButton)
            .accessibilityAction{model.noteOn(note);Task{@MainActor in try? await Task.sleep(for:.milliseconds(250));model.noteOff(note)}}
    }
    var body:some View {
        VStack(spacing:8){HStack{Text("PLAY A LITTLE").tracking(1.4);Spacer();Text("Typing keys A W S E D… · middle C = MIDI 60")}.font(.system(size:13)).foregroundStyle(muted)
            GeometryReader{g in let width=g.size.width/Double(whites.count)
                ZStack(alignment:.topLeading){HStack(spacing:2){ForEach(whites,id:\.self){note in key(note,black:false)}}
                    ForEach(blacks,id:\.0){note,pos in key(note,black:true).frame(width:width*0.6,height:51).offset(x:width*Double(pos+1)-width*0.3)}
                }
            }.frame(height:82)
        }
    }
}

struct EditorView:View {
    @ObservedObject var m:SynthModel
    let waves=["Sine","Triangle","Saw","Pulse","Harmonic"]
    func choice(_ label:String,_ p:Int,_ options:[String])->some View {
        Picker(label,selection:Binding(get:{Int(m.patch.layers[m.selectedLayer][p])},set:{m.checkpoint();m.set(m.selectedLayer,p,Double($0))})){ForEach(Array(options.enumerated()),id:\.offset){i,s in Text(s).tag(i)}}.font(.system(size:15))
    }
    func optionButtons(_ label:String,_ parameter:Int,_ options:[String])->some View {
        HStack(spacing:8){
            Text(label).font(.system(size:14)).foregroundStyle(muted).fixedSize()
            HStack(spacing:3){
                ForEach(Array(options.enumerated()),id:\.offset){index,name in
                    let selected=Int(m.patch.layers[m.selectedLayer][parameter])==index
                    let shortName=["Triangle":"Tri","Square":"Sqr","Random":"Rnd","Amplitude":"Amp","Harmonic":"Harm"][name] ?? name
                    Button{m.checkpoint();m.set(m.selectedLayer,parameter,Double(index))}label:{
                        Text(shortName).font(.system(size:12,weight:.medium)).lineLimit(1).frame(maxWidth:.infinity).frame(height:22).background(selected ? accent:raised,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(selected ? Color.black:Color.white).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(name).accessibilityLabel("\(label) \(name)").accessibilityAddTraits(selected ? [.isSelected]:[])
                }
            }
        }.frame(height:22)
    }
    var layerOctave:Int {Int(floor(m.patch.layers[m.selectedLayer][15]/12))}
    func shiftOctave(_ delta:Int) {
        let octave=max(-3,min(3,layerOctave+delta))
        let residual=Int(m.patch.layers[m.selectedLayer][15])-12*layerOctave
        m.checkpoint();m.set(m.selectedLayer,15,Double(octave*12+residual))
    }
    var octaveControl:some View {
        HStack(spacing:8){
            Text("Octave").font(.system(size:15)).foregroundStyle(muted)
            Spacer()
            HStack(spacing:0){
                Button{shiftOctave(-1)}label:{Image(systemName:"chevron.left").frame(width:25,height:22).contentShape(Rectangle())}.disabled(layerOctave <= -3).accessibilityLabel("Layer octave down")
                Text(layerOctave > 0 ? "+\(layerOctave)":"\(layerOctave)").font(.system(size:15,weight:.medium)).monospacedDigit().frame(width:32).accessibilityLabel("Layer octave \(layerOctave)")
                Button{shiftOctave(1)}label:{Image(systemName:"chevron.right").frame(width:25,height:22).contentShape(Rectangle())}.disabled(layerOctave >= 3).accessibilityLabel("Layer octave up")
            }.buttonStyle(.plain).background(raised,in:RoundedRectangle(cornerRadius:5))
        }.frame(height:22)
    }
    func slider(_ label:String,_ p:Int,_ range:ClosedRange<Double> = 0...1,log:Bool=false,format:@escaping(Double)->String={String(format:"%.0f%%",$0*100)})->some View {
        ParameterSlider(title:label,value:m.parameter(p),range:range,logarithmic:log,format:format,onBegin:{m.checkpoint()})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Layer \(layerLetters[m.selectedLayer]) · sound design").font(.system(size:21,weight:.medium));Spacer();Text("Every control shapes the audio engine").font(.system(size:14)).foregroundStyle(muted)}
            VStack(alignment:.leading,spacing:16){
                EqualHeightRow(spacing:16){
                Panel(title:"Oscillators"){
                    optionButtons("Oscillator 1",1,waves);optionButtons("Oscillator 2",2,waves)
                    slider("Oscillator blend",3);slider("Detune",4,0...30,format:{String(format:"%.1f cents",$0)})
                    HStack{slider("Sub",5);slider("Noise",6)}
                }
                Panel(title:"Filter"){
                    optionButtons("Type",32,["Low-pass","High-pass","Band-pass"])
                    slider("Cutoff",7,30...18000,log:true,format:{$0>=1000 ? String(format:"%.1f kHz",$0/1000):String(format:"%.0f Hz",$0)})
                    slider("Resonance",8,0...0.9);slider("Envelope amount",20,-1...1)
                    slider("Drive",21)
                }
                Panel(title:"Amplitude envelope"){
                    slider("Attack",9,0.001...8,log:true,format:timeText)
                    slider("Decay",10,0.01...8,log:true,format:timeText)
                    slider("Sustain",11)
                    slider("Release",12,0.01...12,log:true,format:timeText)
                }
                }
                EqualHeightRow(spacing:16){
                Panel(title:"LFO 1 · movement"){
                    optionButtons("Shape",19,["Sine","Triangle","Saw","Square","Random"])
                    optionButtons("Destination",18,["Cutoff","Pitch","Pan","Amplitude"])
                    slider("Rate",16,0.03...20,log:true,format:{String(format:"%.2f Hz",$0)})
                    slider("Depth",17)
                }
                Panel(title:"LFO 2 · slow motion"){
                    optionButtons("Shape",33,["Sine","Triangle","Saw","Square","Random"])
                    optionButtons("Destination",31,["Cutoff","Pitch","Pan","Amplitude"])
                    slider("Rate",29,0.03...20,log:true,format:{String(format:"%.2f Hz",$0)})
                    slider("Depth",30)
                }
                Panel(title:"Layer range & balance"){
                    octaveControl
                    slider("Low key",27,0...127,format:{"MIDI \(Int($0))"})
                    slider("High key",28,0...127,format:{"MIDI \(Int($0))"})
                    slider("Pan",14,-1...1,format:{$0 == 0 ? "Center":String(format:"%.0f%% %@",abs($0)*100,$0<0 ? "L":"R")})
                }
                }
            }
            ArpEffectsView(m:m)
        }
    }
    func timeText(_ x:Double)->String{x<1 ? String(format:"%.0f ms",x*1000):String(format:"%.2f s",x)}
}
struct ArpEffectsView:View {
    @ObservedObject var m:SynthModel
    func choices(_ label:String,_ parameter:Int,_ options:[String])->some View {
        VStack(alignment:.leading,spacing:8){Text(label).foregroundStyle(muted)
            HStack(spacing:4){ForEach(Array(options.enumerated()),id:\.offset){i,name in
                Button{m.checkpoint();m.set(m.selectedLayer,parameter,Double(i))}label:{Text(name).font(.system(size:14)).frame(maxWidth:.infinity).padding(.vertical,8).background(Int(m.patch.layers[m.selectedLayer][parameter])==i ? accent:raised,in:RoundedRectangle(cornerRadius:6)).foregroundStyle(Int(m.patch.layers[m.selectedLayer][parameter])==i ? Color.black:Color.white).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("\(label) \(name)")
            }}
        }
    }
    var body:some View {
        EqualHeightRow(spacing:16){
            Panel(title:"Arpeggiator · layer \(layerLetters[m.selectedLayer])"){
                Toggle("Arpeggiator enabled",isOn:Binding(get:{m.patch.layers[m.selectedLayer][22]>0.5},set:{m.checkpoint();m.set(m.selectedLayer,22,$0 ? 1:0)})).tint(accent)
                choices("Pattern",24,["Up","Down","Up/down","Random"])
                choices("Division",23,["1/4","1/8","1/16","1/32"])
                Stepper("Octaves: \(Int(m.patch.layers[m.selectedLayer][25]))",value:Binding(get:{Int(m.patch.layers[m.selectedLayer][25])},set:{m.set(m.selectedLayer,25,Double($0))}),in:1...4)
                ParameterSlider(title:"Gate",value:m.parameter(26),range:0.1...0.95)
            }.font(.system(size:15))
            Panel(title:"Delay"){
                Text("Quarter-note echoes synced to your tempo.").font(.system(size:14)).foregroundStyle(muted)
                ParameterSlider(title:"Mix",value:m.globalBinding(2),range:0...0.6)
                ParameterSlider(title:"Feedback",value:m.globalBinding(3),range:0...0.75)
            }
            Panel(title:"FX"){
                ParameterSlider(title:"Chorus",value:m.globalBinding(5),range:0...0.6)
                ParameterSlider(title:"Phaser",value:m.globalBinding(6),onBegin:{m.checkpoint()})
                ParameterSlider(title:"Reverb",value:m.globalBinding(4),range:0...0.75)
                Text("Shared across all four layers. Shape each layer's drive in its Filter panel.").font(.system(size:14)).foregroundStyle(muted)
            }
        }
    }
}
struct MatrixView:View {
    @ObservedObject var m:SynthModel
    private let soundSources=["LFO 1","LFO 2","Amp envelope"]
    private let performanceSources=["Mod wheel","Velocity","Channel pressure","Expression","Sustain","MIDI CC"]
    private let destinations=["Cutoff","Pitch","Pan","Amplitude","Oscillator blend","Drive","LFO 1 depth","LFO 2 depth","Chorus","Phaser","Reverb","Delay mix"]
    func binding<T>(_ performance:Bool,_ slot:Int,_ key:WritableKeyPath<MatrixAssignment,T>)->Binding<T> {
        Binding(get:{m.matrixRows(performance:performance)[slot][keyPath:key]},set:{value in m.checkpoint();m.updateMatrix(performance:performance,slot:slot){$0[keyPath:key]=value}})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Panel(title:"Sound Matrix · layer \(layerLetters[m.selectedLayer])"){
                Text("Add movement from either LFO or the amplitude envelope. These routes add to the controls in Edit; LFO sources use their full waveform, independent of the Depth slider.").font(.system(size:14)).foregroundStyle(muted)
                ForEach(0..<6){row in routeRow(false,row)}
            }
            Panel(title:"Performance Matrix · this patch"){
                Text("Use your wheels, playing dynamics, pedals, or any MIDI CC. Layer routes follow each note’s keyboard and channel. Shared FX follow the latest received source value across keyboards.").font(.system(size:14)).foregroundStyle(muted)
                ForEach(0..<6){row in routeRow(true,row)}
            }
            Text("Amount is an offset: ±100% gives up to 4 octaves of cutoff movement, 12 semitones of pitch, or the full normalized range of other destinations. Multiple slots add together; the final value is bounded. Existing wheel vibrato, expression, sustain, and MIDI Learn remain active.").font(.system(size:13)).foregroundStyle(muted)
        }
    }
    func routeRow(_ performance:Bool,_ slot:Int)->some View {
        let row=m.matrixRows(performance:performance)[slot]
        return HStack(spacing:10){
            Toggle("Slot \(slot+1)",isOn:binding(performance,slot,\.enabled)).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("\(performance ? "Performance":"Sound") slot \(slot+1) enabled")
            Text("\(slot+1)").foregroundStyle(muted).frame(width:14)
            Picker("Source",selection:binding(performance,slot,\.source)){
                ForEach(Array((performance ? performanceSources:soundSources).enumerated()),id:\.offset){i,name in Text(name).tag(i)}
            }.labelsHidden().frame(width:performance ? 150:140).accessibilityLabel("Slot \(slot+1) source")
            if performance && row.source==5 {
                HStack(spacing:3){Text("CC").foregroundStyle(muted);TextField("CC number",value:binding(performance,slot,\.cc),format:.number).textFieldStyle(.roundedBorder).frame(width:36)}.frame(width:65)
            } else if performance {Color.clear.frame(width:65,height:1)}
            Image(systemName:"arrow.right").foregroundStyle(muted)
            Picker("Destination",selection:binding(performance,slot,\.destination)){
                ForEach(0..<(performance ? destinations.count:6),id:\.self){i in Text(destinations[i]).tag(i)}
            }.labelsHidden().frame(width:150).accessibilityLabel("Slot \(slot+1) destination")
            if performance {
                if row.destination>=8{Text("Whole patch").foregroundStyle(accent).frame(width:100)}else{
                    Picker("Target",selection:binding(true,slot,\.target)){Text("All layers").tag(4);ForEach(0..<4){i in Text("Layer \(layerLetters[i])").tag(i)}}.labelsHidden().frame(width:100)
                }
            }
            Slider(value:Binding(get:{m.matrixRows(performance:performance)[slot].amount},set:{value in m.updateMatrix(performance:performance,slot:slot){$0.amount=value}}),in:-1...1,onEditingChanged:{if $0{m.checkpoint()}}).tint(accent).frame(minWidth:70).accessibilityLabel("Slot \(slot+1) amount")
            Text(String(format:"%+.0f%%",row.amount*100)).monospacedDigit().frame(width:58,alignment:.trailing)
            Button{m.checkpoint();m.updateMatrix(performance:performance,slot:slot){$0=MatrixAssignment()}}label:{Image(systemName:"arrow.counterclockwise")}.buttonStyle(.plain).help("Reset slot \(slot+1)")
        }.font(.system(size:14)).padding(.vertical,5).opacity(row.enabled ? 1:0.65)
    }
}
struct RoutingView:View {
    @ObservedObject var m:SynthModel
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Your keyboards").font(.system(size:22,weight:.medium));Spacer();Button("Refresh",systemImage:"arrow.clockwise"){m.refresh()}}
            Text("Choose the layers each MIDI source plays. MIDI inputs and the audio output are independent.").foregroundStyle(muted).font(.system(size:15))
            if m.sources.isEmpty {Panel(title:"No MIDI sources detected"){Text("Connect a keyboard by USB, then Refresh. The on-screen keyboard still works.").foregroundStyle(muted);Text("Yamaha keyboards use USB TO HOST and the Yamaha Steinberg USB Driver.").font(.system(size:15))}}
            ForEach(m.sources){source in sourceRow(source)}
            Panel(title:"Audio output"){
                Text(m.running ? "Audio is enabled. Changing the output stops playback until you enable audio again.":"Audio is stopped. Choose the output connected to your headphones or speakers.").font(.system(size:15)).foregroundStyle(muted)
                HStack{Picker("Output",selection:Binding(get:{m.output},set:{m.changeOutput($0)})){Text("System default").tag(UInt32(0));ForEach(m.devices){Text($0.name).tag($0.id)}}
                    Picker("Buffer",selection:$m.buffer){ForEach([64,128,256,512],id:\.self){Text("\($0) frames").tag($0)}}.frame(width:220).disabled(m.running)}
                Text("The output's actual sample rate is used. CK88 and MODX7+ USB audio use 44.1 kHz.").font(.system(size:14)).foregroundStyle(muted)
            }
            Panel(title:"Oxygen Pro 25 · MIDI Learn"){
                Text("Use Preset mode and the musical USB MIDI port. Click MIDI Learn below any macro, then move one of your eight knobs. Cross the macro's current position to take control without a jump.").font(.system(size:15)).foregroundStyle(muted)
                if m.mappings.isEmpty{Text("No knobs mapped yet.").font(.system(size:15))}
                ForEach(m.mappings,id:\.macro){mapping in HStack{Text(m.macroNames[mapping.macro]);Spacer();Text("CC \(mapping.controller) · ch \(mapping.channel)").foregroundStyle(muted);Button("Remove"){m.mappings.removeAll{$0.macro==mapping.macro};m.persist()}}.font(.system(size:15))}
            }
        }
    }
    func sourceRow(_ source:MIDISource)->some View {
        let route=m.routes[source.id] ?? SourceRoute(mask:1,channel:0)
        return Panel(title:source.name){
            HStack{
                ForEach(0..<4){i in Button{var r=route;r.mask ^= (1<<i);m.setRoute(source.id,r)}label:{Text("Layer \(layerLetters[i])").frame(maxWidth:.infinity).padding(.vertical,7).background(route.mask&(1<<i) != 0 ? accent:raised,in:RoundedRectangle(cornerRadius:6)).foregroundStyle(route.mask&(1<<i) != 0 ? Color.black:Color.white)}.buttonStyle(.plain)}
                Picker("Channel",selection:Binding(get:{route.channel},set:{m.setRoute(source.id,SourceRoute(mask:route.mask,channel:$0))})){Text("All").tag(0);ForEach(1...16,id:\.self){Text("\($0)").tag($0)}}.frame(width:160)
            }
            HStack{Text(route.mask==0 ? "Input disabled":"Assigned to "+(0..<4).filter{route.mask&(1<<$0) != 0}.map{layerLetters[$0]}.joined(separator:" + "));Spacer();Text("\(source.events ?? 0) MIDI events")}.font(.system(size:14)).foregroundStyle(muted)
        }
    }
}

struct ContentView:View {
    @ObservedObject var m:SynthModel
    var body:some View {
        VStack(spacing:0){header;Divider().opacity(0.15)
            HStack(spacing:0){sidebar.frame(width:270);Divider().opacity(0.15)
                ScrollView{
                    VStack(alignment:.leading,spacing:23){
                        HStack(alignment:.top){VStack(alignment:.leading,spacing:6){Text(m.patch.category.uppercased()).font(.system(size:13,weight:.medium)).tracking(2).foregroundStyle(accent);Text(m.patch.name+(m.dirty ? " ·":"")).font(.system(size:36,weight:.medium,design:.rounded));Text(m.patch.detail).font(.system(size:15)).foregroundStyle(muted)};Spacer();Button("Save sound",systemImage:"square.and.arrow.down"){m.saveName=m.patch.name+" copy";m.showingSave=true}.controlSize(.regular)}
                        HStack(spacing:10){ForEach(0..<4){LayerStrip(model:m,index:$0)}}
                        if m.screen=="Play" {play} else if m.screen=="Edit" {EditorView(m:m)} else if m.screen=="Matrix" {MatrixView(m:m)} else {RoutingView(m:m)}
                    }.padding(24)
                }.background(Color(red:0.075,green:0.095,blue:0.083))
            }

        }.background(surface).foregroundStyle(Color(red:0.92,green:0.95,blue:0.91)).preferredColorScheme(.dark).font(.system(size:15)).controlSize(.regular).frame(minWidth:1260,minHeight:780)
        .sheet(isPresented:Binding(get:{m.renameID != nil},set:{if !$0{m.renameID=nil}})){
            VStack(alignment:.leading,spacing:18){Text("Rename sound").font(.system(size:26,weight:.semibold));TextField("Sound name",text:$m.renameName).textFieldStyle(.roundedBorder);HStack{Button("Cancel"){m.renameID=nil};Spacer();Button("Rename"){m.renameSound()}.keyboardShortcut(.defaultAction).disabled(m.renameName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:460)
        }
        .sheet(isPresented:$m.showingSave){VStack(alignment:.leading,spacing:18){Text("Save your sound").font(.system(size:26,weight:.semibold));TextField("Preset name",text:$m.saveName).textFieldStyle(.roundedBorder);HStack{Button("Cancel"){m.showingSave=false};Spacer();Button("Save"){m.saveUserPreset()}.keyboardShortcut(.defaultAction).disabled(m.saveName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:460)}
    }
    var header:some View {
        HStack(spacing:12){
            HStack(spacing:8){Image(systemName:"waveform").foregroundStyle(accent);Text("AURORA").tracking(3).font(.system(size:19,weight:.semibold))}.frame(minWidth:125,idealWidth:262,maxWidth:262,alignment:.leading).help(m.notice.isEmpty ? "Aurora synthesizer":m.notice)
            Picker("View",selection:$m.screen){Text("Play").tag("Play");Text("Edit").tag("Edit");Text("Routing").tag("Routing");Text("Matrix").tag("Matrix")}.labelsHidden().pickerStyle(.segmented).frame(width:250)
            OutputScope(telemetry:m.scope).frame(minWidth:65,idealWidth:120,maxWidth:160).frame(height:30)
            HStack(spacing:6){
                TextField("Tempo",value:Binding(get:{Int(m.patch.globals[1])},set:{m.global(1,Double($0))}),format:.number).textFieldStyle(.roundedBorder).frame(width:48).monospacedDigit().accessibilityLabel("Tempo")
                Text("BPM").font(.system(size:12)).foregroundStyle(muted)
                Button("Tap"){m.tapTempo()}.help("Tap repeatedly to set the tempo")
            }.fixedSize()
            Divider().frame(height:24)
            HStack(spacing:0){
                Button{m.setTranspose(m.transpose-1)}label:{Image(systemName:"chevron.left").frame(width:28,height:30).contentShape(Rectangle())}.disabled(m.transpose <= -24).accessibilityLabel("Transpose down one semitone")
                Text(m.transpose > 0 ? "+\(m.transpose)":"\(m.transpose)").monospacedDigit().font(.system(size:15,weight:.medium)).frame(width:34).accessibilityLabel("Global transpose \(m.transpose) semitones")
                Button{m.setTranspose(m.transpose+1)}label:{Image(systemName:"chevron.right").frame(width:28,height:30).contentShape(Rectangle())}.disabled(m.transpose >= 24).accessibilityLabel("Transpose up one semitone")
            }.buttonStyle(.plain).background(raised,in:RoundedRectangle(cornerRadius:7)).help("Global transpose · semitones · applies to all layers")
            HStack(spacing:5){
                Button{m.undo()}label:{Image(systemName:"arrow.uturn.backward").frame(width:18,height:20)}.help("Undo").accessibilityLabel("Undo").keyboardShortcut("z",modifiers:.command)
                Button{m.redo()}label:{Image(systemName:"arrow.uturn.forward").frame(width:18,height:20)}.help("Redo").accessibilityLabel("Redo").keyboardShortcut("z",modifiers:[.command,.shift])
            }
            HStack(spacing:6){Text("Master").foregroundStyle(muted);Slider(value:m.globalBinding(0),in:0...1).frame(minWidth:65,idealWidth:95,maxWidth:115).tint(accent).accessibilityLabel("Master volume");Text(String(format:"%.0f%%",m.patch.globals[0]*100)).frame(width:40).monospacedDigit()}
            Button{m.toggleAudio()}label:{Image(systemName:m.running ? "speaker.wave.2.fill":"speaker.slash").font(.system(size:17)).foregroundStyle(m.running ? Color.black:accent).frame(width:34,height:30).background(m.running ? accent:raised,in:RoundedRectangle(cornerRadius:7))}.buttonStyle(.plain).accessibilityLabel(m.running ? "Turn audio off":"Turn audio on").help(m.status+String(format:" · %.1f kHz · %d frames",m.sampleRate/1000,m.actualFrames))
            Button("Panic",systemImage:"stop.circle"){m.panic()}.help("Stop all notes and effect tails").fixedSize().keyboardShortcut(".",modifiers:.command)
            EngineReadout(telemetry:m.telemetry).font(.system(size:13)).foregroundStyle(muted).frame(width:130,alignment:.trailing)
        }.font(.system(size:14)).padding(.horizontal,20).padding(.vertical,14)
    }
    var sidebar:some View {
        VStack(alignment:.leading,spacing:16){HStack{Text("Sound library").font(.system(size:18,weight:.semibold));Spacer();Menu{Button("Undo Delete"){m.undoDelete()}.disabled(m.deletedSound==nil);Button("Import preset…"){m.importPreset()};Button("Export current preset…"){m.exportPreset()}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:20)}
            TextField("Search sounds",text:$m.search).textFieldStyle(.roundedBorder).font(.system(size:15))
            VStack(alignment:.leading,spacing:9){
                Picker("Collection",selection:$m.collection){
                    Text("Aurora").tag("Aurora")
                    Text("Your sounds").tag("Your sounds")
                    Text("All sounds").tag("All sounds")
                }.labelsHidden().accessibilityLabel("Sound collection")
                Picker("Category",selection:$m.category){
                    Text("All categories").tag("All categories")
                    ForEach(m.categories,id:\.self){Text($0).tag($0)}
                }.labelsHidden().accessibilityLabel("Sound category")
            }.font(.system(size:15))
                .onChange(of:m.collection){_,_ in m.category="All categories"}
            Toggle("Favorites",isOn:$m.favoritesOnly).toggleStyle(.checkbox).font(.system(size:14)).foregroundStyle(muted)
            ScrollView{VStack(alignment:.leading,spacing:4){
                ForEach(m.libraryGroups,id:\.category){group in
                    HStack(spacing:6){
                        Text(group.category.uppercased()).font(.system(size:18,weight:.bold)).tracking(0.3)
                        Spacer(minLength:0)
                        Text("\(group.sounds.count)").font(.system(size:13,weight:.semibold)).monospacedDigit()
                    }.foregroundStyle(accent).padding(.horizontal,10).padding(.vertical,9)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .background(accent.opacity(0.17),in:RoundedRectangle(cornerRadius:7))
                        .overlay(RoundedRectangle(cornerRadius:7).stroke(accent.opacity(0.25),lineWidth:1))
                        .padding(.top,12).padding(.bottom,4)
                    ForEach(group.sounds){p in presetRow(p)}
                }
                if m.library.isEmpty {
                    Text(m.collection == "Your sounds" && m.userPresets.isEmpty ? "Save a sound to begin your collection." : "No sounds match these filters.")
                        .font(.system(size:15)).foregroundStyle(muted).padding(.vertical,20)
                }
            }}
            Text("\(m.library.count) of \(m.collectionSounds.count) sounds\n\(FactoryBank.all.count) factory sounds installed").font(.system(size:13)).foregroundStyle(muted).lineSpacing(4)
        }.padding(16)
    }
    func presetRow(_ p:SoundPreset)->some View {
        HStack(spacing:0){
            Button{m.loadPreset(p)}label:{
                Text(p.name).font(.system(size:15,weight:.medium)).lineLimit(2).frame(minHeight:36,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,11).padding(.leading,10).contentShape(Rectangle())
            }.buttonStyle(.plain).help(p.detail)
            if m.userPresets.contains(where:{$0.id==p.id}) {
                Menu{Button("Rename…"){m.renameName=p.name;m.renameID=p.id};Button("Delete",role:.destructive){m.deleteSound(p.id)}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:22).accessibilityLabel("Manage \(p.name)")
            }
            Button{m.favorite(p.id)}label:{Image(systemName:m.favorites.contains(p.id) ? "star.fill":"star").font(.system(size:13)).foregroundStyle(m.favorites.contains(p.id) ? accent:muted.opacity(0.4))}
                .buttonStyle(.plain).padding(.trailing,8).help("Favorite \(p.name)").accessibilityLabel("Favorite \(p.name)")
        }.background(m.patch.id==p.id ? raised:Color.clear,in:RoundedRectangle(cornerRadius:8))
    }
    var play:some View {
        VStack(alignment:.leading,spacing:23){HStack{Text("Make it yours").font(.system(size:20,weight:.medium));Spacer();Text("8 performance macros").font(.system(size:14)).foregroundStyle(muted)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:24),count:4),spacing:16){ForEach(0..<8){MacroDial(model:m,index:$0)}}
            VoiceStatus(telemetry:m.telemetry,running:m.running).font(.system(size:14)).foregroundStyle(muted).padding(13).background(surface,in:RoundedRectangle(cornerRadius:10))
            PianoView(model:m)
        }
    }

}

final class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
@main struct AuroraApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model=SynthModel()
    var body:some Scene {
        WindowGroup("Aurora") {ContentView(m:model).onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in model.shutdown()}}
            .defaultSize(width:1480,height:940)
            .commands{CommandGroup(replacing:.newItem){};CommandGroup(after:.saveItem){Button("Save sound…"){model.saveName=model.patch.name+" copy";model.showingSave=true}.keyboardShortcut("s",modifiers:.command)}}
    }
}
