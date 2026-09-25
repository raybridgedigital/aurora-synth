import SwiftUI
import AppKit
import Combine

let layerLetters = ["A", "B", "C", "D"]

struct AuroraPalette {
    let background:Color, surface:Color, raised:Color, accent:Color
    let buttonSurface:Color, buttonSelected:Color, graphBackground:Color, graphCyan:Color, graphPink:Color
    let selectedText:Color
    let boldText:Bool
    func weight(_ standard:Font.Weight = .regular)->Font.Weight{boldText ? .bold:standard}
    let muted=Color(red:0.76,green:0.79,blue:0.82)
    init(_ background:UInt32,_ surface:UInt32,_ raised:UInt32,_ accent:UInt32,_ button:UInt32,_ selected:UInt32,_ graph:UInt32,_ wave1:UInt32,_ wave2:UInt32,selectedText:UInt32=0xFFFFFF,boldText:Bool=false){
        func color(_ hex:UInt32)->Color{Color(red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255)}
        self.background=color(background);self.surface=color(surface);self.raised=color(raised);self.accent=color(accent)
        buttonSurface=color(button);buttonSelected=color(selected);graphBackground=color(graph);graphCyan=color(wave1);graphPink=color(wave2)
        self.selectedText=color(selectedText)
        self.boldText=boldText
    }
}
enum AuroraTheme:String,Codable,CaseIterable,Identifiable {
    case midnight="Midnight",copper="Copper",copperOrange="Copper Orange",ocean="Ocean",forest="Forest",graphite="Graphite",graphiteOrange="Graphite Orange"
    var id:String{rawValue}
    var palette:AuroraPalette{switch self{
    case .midnight:return AuroraPalette(0x0D1122,0x181E34,0x252E49,0xA7BDFF,0x283C60,0x8D471D,0x080D1A,0x5ADFFC,0xF3BC77)
    case .copper:return AuroraPalette(0x131815,0x1D2420,0x29302A,0xB8D995,0x2E476E,0xA64D1F,0x090E1A,0x33E0FF,0xFFC077)
    case .copperOrange:return AuroraPalette(0x131815,0x1D2420,0x29302A,0xFFAA45,0x2E476E,0xFFAA45,0x090E1A,0x33E0FF,0xFFC077,selectedText:0x23180D)
    case .ocean:return AuroraPalette(0x071C26,0x102D3B,0x1A4051,0x8EE6E6,0x1D485C,0x7C3C69,0x04151F,0x55E3D0,0xB5B2FF)
    case .forest:return AuroraPalette(0x101E18,0x1E3026,0x2B4333,0xC8E3A2,0x2C4A3C,0x80522A,0x081710,0xA1EFBC,0xF4CC70)
    case .graphite:return AuroraPalette(0x141416,0x242429,0x33333B,0xD1D7E6,0x3B3B45,0x245B83,0x0B0B10,0xF6D17A,0xC7AAFF)
    case .graphiteOrange:return AuroraPalette(0x141416,0x242429,0x33333B,0xFFB04A,0x3B3B45,0xFFB04A,0x0B0B10,0xFFB04A,0xC7AAFF,selectedText:0x20170D)
    }}
}
private struct AuroraPaletteKey:EnvironmentKey {static let defaultValue=AuroraTheme.copper.palette}
extension EnvironmentValues {
    var auroraPalette:AuroraPalette{get{self[AuroraPaletteKey.self]}set{self[AuroraPaletteKey.self]=newValue}}
}
struct AuroraButtonStyle:ButtonStyle {
    @Environment(\.auroraPalette) private var palette
    var selected=false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.fontWeight(selected || configuration.isPressed ? .bold:.regular).padding(.horizontal,9).padding(.vertical,5)
            .foregroundStyle(selected ? palette.selectedText:Color.white)
            .background(selected ? palette.buttonSelected:configuration.role == .destructive ? palette.buttonSelected.opacity(0.55):palette.buttonSurface,in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).stroke(palette.graphCyan.opacity(0.4),lineWidth:0.7))
            .opacity(enabled ? (configuration.isPressed ? 0.65:1):0.35)
    }
}
struct AuroraFlatButtonStyle:ButtonStyle {
    var selected=false
    @Environment(\.auroraPalette) private var palette
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.fontWeight(selected || configuration.isPressed ? .bold:.regular).opacity(enabled ? (configuration.isPressed ? 0.65:1):0.35)
    }
}
struct AuroraIconButtonStyle:ButtonStyle {
    @Environment(\.auroraPalette) private var palette
    var selected=false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.fontWeight(selected || configuration.isPressed ? .bold:.regular).padding(3).background(selected ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).stroke(palette.graphCyan.opacity(0.4),lineWidth:0.7))
            .opacity(enabled ? (configuration.isPressed ? 0.65:1):0.35)
    }
}

enum WavetableCatalog {
    static let names=(0..<24).map{String(cString:aurora_wavetable_name(Int32($0)))}
    static let categories=(0..<24).map{String(cString:aurora_wavetable_category(Int32($0)))}
}
struct ImportedWavetable:Codable,Equatable {
    var name:String
    var frameSize:Int
    var data:Data // packed little-endian Float32; embedded for portable presets
    var samples:[Float]{data.withUnsafeBytes{raw in (0..<(raw.count/4)).map{Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}}}
    var frames:Int{[256,512,1024,2048].contains(frameSize) ? data.count/(frameSize*4):0}
    var valid:Bool{[256,512,1024,2048].contains(frameSize) && (1...64).contains(frames) && data.count==frames*frameSize*4 && !name.isEmpty && samples.allSatisfy{$0.isFinite && abs($0)<=1.001}}
}

/// FM engine payload — FUTURE-PROPOSAL-FM-ENGINE.md §7: `fm` sibling of `values` per layer;
/// absent = Subtractive. Packed 96 floats matching FmEngine.hpp enums exactly.
struct FmEnv: Codable, Equatable {
    var rates: [Double] = [80, 30, 20, 60]
    var levels: [Double] = [0.9, 0.5, 0.45, 0]
    enum CodingKeys: String, CodingKey { case rates, levels }
    init() {}
    init(rates: [Double], levels: [Double]) { self.rates = rates; self.levels = levels }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rates = Array(((try? c.decode([Double].self, forKey: .rates)) ?? rates).prefix(4))
        levels = Array(((try? c.decode([Double].self, forKey: .levels)) ?? levels).prefix(4))
        while rates.count < 4 { rates.append(0.02) }
        while levels.count < 4 { levels.append(0) }
    }
}
struct FmPitchEnv: Codable, Equatable {
    var amount = 0.0, time = 0.05, curve = 0.5
    enum CodingKeys: String, CodingKey { case amount, time, curve }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? amount
        time = (try? c.decode(Double.self, forKey: .time)) ?? time
        curve = (try? c.decode(Double.self, forKey: .curve)) ?? curve
    }
}
struct FmOpState: Codable, Equatable {
    var wave = 0, ratio = 1.0, fixedHz = 440.0, fixedMode = 0, fine = 0.0
    var level = 0.0, vel = 0.0, keyScale = 0, keySync = 1, envMode = 0, pulseWidth = 0.5
    var wtTable = 0, wtPos = 0.5, wtWarp = 0.0
    var env = FmEnv()
    enum CodingKeys: String, CodingKey {
        case wave, ratio, fixedHz, fixedMode, fine, level, vel, keyScale, keySync, envMode, pulseWidth, wtTable, wtPos, wtWarp, env
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wave = (try? c.decode(Int.self, forKey: .wave)) ?? wave
        ratio = (try? c.decode(Double.self, forKey: .ratio)) ?? ratio
        fixedHz = (try? c.decode(Double.self, forKey: .fixedHz)) ?? fixedHz
        fixedMode = (try? c.decode(Int.self, forKey: .fixedMode)) ?? fixedMode
        fine = (try? c.decode(Double.self, forKey: .fine)) ?? fine
        level = (try? c.decode(Double.self, forKey: .level)) ?? level
        vel = (try? c.decode(Double.self, forKey: .vel)) ?? vel
        keyScale = (try? c.decode(Int.self, forKey: .keyScale)) ?? keyScale
        keySync = (try? c.decode(Int.self, forKey: .keySync)) ?? keySync
        envMode = (try? c.decode(Int.self, forKey: .envMode)) ?? envMode
        pulseWidth = (try? c.decode(Double.self, forKey: .pulseWidth)) ?? pulseWidth
        wtTable = (try? c.decode(Int.self, forKey: .wtTable)) ?? wtTable
        wtPos = (try? c.decode(Double.self, forKey: .wtPos)) ?? wtPos
        wtWarp = (try? c.decode(Double.self, forKey: .wtWarp)) ?? wtWarp
        env = (try? c.decode(FmEnv.self, forKey: .env)) ?? env
    }
}
struct FmPatch: Codable, Equatable {
    var enabled = false
    var algorithm = 4            // "EP Twin" — life-blood default (spec §4/§8)
    var feedback = 0.45
    var carrierMix = 0.5
    var pitchEnv = FmPitchEnv()
    var ops: [String: FmOpState] = FmPatch.defaultOps
    enum CodingKeys: String, CodingKey { case enabled, algorithm, feedback, carrierMix, pitchEnv, ops }
    static var defaultOps: [String: FmOpState] {
        // EP-flavoured: tine modulator on op1, body modulator on op2, ops 3–4 carriers (EP Twin).
        var tine = FmOpState(); tine.ratio = 14; tine.level = 0.5; tine.vel = 0.6
        tine.env = FmEnv(rates: [180, 10, 8, 40], levels: [1, 0.25, 0.2, 0])
        var body = FmOpState(); body.level = 0.35; body.vel = 0.4
        body.env = FmEnv(rates: [40, 8, 6, 30], levels: [0.8, 0.5, 0.45, 0])
        var car1 = FmOpState(); car1.level = 0.85; car1.vel = 0.9
        car1.env = FmEnv(rates: [120, 6, 6, 50], levels: [1, 0.75, 0.7, 0])
        var car2 = FmOpState(); car2.level = 0.8; car2.vel = 0.9
        car2.env = FmEnv(rates: [60, 5, 5, 60], levels: [1, 0.6, 0.55, 0])
        return ["0": tine, "1": body, "2": car1, "3": car2]
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? enabled
        algorithm = (try? c.decode(Int.self, forKey: .algorithm)) ?? algorithm
        feedback = (try? c.decode(Double.self, forKey: .feedback)) ?? feedback
        carrierMix = (try? c.decode(Double.self, forKey: .carrierMix)) ?? carrierMix
        pitchEnv = (try? c.decode(FmPitchEnv.self, forKey: .pitchEnv)) ?? pitchEnv
        ops = (try? c.decode([String: FmOpState].self, forKey: .ops)) ?? ops
    }
    func op(_ i: Int) -> FmOpState { ops[String(i)] ?? FmOpState() }
    mutating func setOp(_ i: Int, _ value: FmOpState) { ops[String(i)] = value }
    static func cl(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v.isFinite ? max(lo, min(hi, v)) : lo }
    static func cl(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }
    /// 96-float bridge payload — field order mirrors FmEngine.hpp enums exactly.
    func packed() -> [Float] {
        var out = [Float](repeating: 0, count: 96)
        out[0] = enabled ? 1 : 0
        out[1] = Float(FmPatch.cl(algorithm, 0, 15))
        out[2] = Float(FmPatch.cl(feedback, 0, 1))
        out[3] = Float(FmPatch.cl(carrierMix, 0, 1))
        out[4] = Float(FmPatch.cl(pitchEnv.amount, -1, 1))
        out[5] = Float(FmPatch.cl(pitchEnv.time, 0.001, 4))
        out[6] = Float(FmPatch.cl(pitchEnv.curve, 0, 1))
        for i in 0..<4 {
            let o = op(i), b = 8 + i * 22
            let rates = o.env.rates + [0.02, 0.02, 0.02, 0.02]
            let levels = o.env.levels + [0, 0, 0, 0]
            out[b + 0] = Float(FmPatch.cl(o.wave, 0, 4))
            out[b + 1] = Float(FmPatch.cl(o.ratio, 0.25, 16))
            out[b + 2] = Float(FmPatch.cl(o.fixedHz, 1, 20000))
            out[b + 3] = o.fixedMode > 0 ? 1 : 0
            out[b + 4] = Float(FmPatch.cl(o.fine, -1, 1))
            out[b + 5] = Float(FmPatch.cl(o.level, 0, 1))
            out[b + 6] = Float(FmPatch.cl(o.vel, 0, 1))
            out[b + 7] = Float(FmPatch.cl(o.keyScale, 0, 3))
            out[b + 8] = o.keySync > 0 ? 1 : 0
            out[b + 9] = o.envMode > 0 ? 1 : 0
            out[b + 10] = Float(FmPatch.cl(o.pulseWidth, 0.05, 0.95))
            for r in 0..<4 { out[b + 11 + r] = Float(FmPatch.cl(rates[r], 0.02, 300)) }
            for l in 0..<4 { out[b + 15 + l] = Float(FmPatch.cl(levels[l], 0, 1)) }
            out[b + 19] = Float(FmPatch.cl(o.wtTable, 0, 23))
            out[b + 20] = Float(FmPatch.cl(o.wtPos, 0, 1))
            out[b + 21] = Float(FmPatch.cl(o.wtWarp, 0, 1))
        }
        return out
    }
}
/// Vector diagram of one FM algorithm — 4 op boxes, routing arrows, filled carriers, feedback dot.
/// Static content inside a bounded canvas (no per-frame invalidation; rendering-audit lessons).
struct FmAlgorithmDiagram: View {
    @Environment(\.auroraPalette) private var palette
    let algorithm:Int
    let selected:Bool
    var body: some View {
        let meta=FmPatch.algorithmMeta[min(max(algorithm,0),15)]
        Canvas { ctx,size in
            let box=CGSize(width:min(16,size.width*0.26),height:13)
            let positions=(0..<4).map{idx->CGPoint in
                CGPoint(x: idx%2==0 ? size.width*0.16 : size.width*0.70,
                        y: idx<2 ? size.height*0.24 : size.height*0.74)
            }
            let ink=Color.white.opacity(selected ? 0.92 : 0.62)
            let accent=palette.accent
            for i in 0..<4 where meta.target[i]>=0 {
                var arrow=Path()
                let a=positions[i],b=positions[meta.target[i]]
                arrow.move(to:a)
                arrow.addLine(to:b)
                ctx.stroke(arrow,with:.color(accent.opacity(0.85)),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
                var tip=Path()
                let dx=b.x-a.x,dy=b.y-a.y,len=max(1,(dx*dx+dy*dy).squareRoot())
                let ux=dx/len,uy=dy/len
                let end=CGPoint(x:b.x-ux*(box.width*0.5+2),y:b.y-uy*(box.height*0.5+2))
                tip.move(to:end)
                tip.addLine(to:CGPoint(x:end.x-ux*4-uy*2.4,y:end.y-uy*4+ux*2.4))
                tip.move(to:end)
                tip.addLine(to:CGPoint(x:end.x-ux*4+uy*2.4,y:end.y-uy*4-ux*2.4))
                ctx.stroke(tip,with:.color(accent.opacity(0.9)),lineWidth:1.2)
            }
            for i in 0..<4 {
                let p=positions[i]
                let rect=CGRect(x:p.x-box.width/2,y:p.y-box.height/2,width:box.width,height:box.height)
                let carrier=meta.target[i]<0
                let opRect=Path(roundedRect:rect,cornerRadius:3)
                if carrier {ctx.fill(opRect,with:.color(accent.opacity(selected ? 0.85 : 0.55)))}
                ctx.stroke(opRect,with:.color(ink),lineWidth:1)
                let label=Text("\(i+1)").font(.system(size:9,weight:.bold)).foregroundColor(carrier ? Color.black : ink)
                ctx.draw(label,at:CGPoint(x:p.x,y:p.y-0.5),anchor:.center)
                if meta.fb==i {
                    var fb=Path()
                    fb.addEllipse(in:CGRect(x:p.x+box.width*0.34,y:p.y-box.height*0.78,width:5,height:5))
                    ctx.fill(fb,with:.color(Color.orange.opacity(0.95)))
                }
            }
        }
        .accessibilityLabel("Algorithm diagram \(algorithm+1) \(FmPatch.algorithmMeta[min(max(algorithm,0),15)].name)")
    }
}
/// Mini envelope curve (4 levels across, L4 tail) — bounded, static per parameter value.
struct FmEnvCurve: View {
    @Environment(\.auroraPalette) private var palette
    let op:FmOpState
    var body: some View {
        Canvas { ctx,size in
            let levels=op.env.levels
            var seq:[Double]=[]
            seq.append(levels.count>3 ? levels[3] : 0)
            seq.append(contentsOf:(0..<4).map{i in i<levels.count ? levels[i] : 0})
            seq.append(levels.count>3 ? levels[3] : 0)
            let pts=(0..<seq.count).map{idx->CGPoint in
                CGPoint(x:size.width*CGFloat(idx)/CGFloat(seq.count-1),
                        y:size.height*(1-CGFloat(max(0,min(1,seq[idx]))))*0.9+size.height*0.05)
            }
            var grid=Path()
            grid.move(to:CGPoint(x:0,y:size.height-0.5));grid.addLine(to:CGPoint(x:size.width,y:size.height-0.5))
            ctx.stroke(grid,with:.color(.white.opacity(0.12)),lineWidth:1)
            var path=Path()
            path.move(to:pts[0])
            for p in pts.dropFirst(){path.addLine(to:p)}
            ctx.stroke(path,with:.color(palette.accent),style:StrokeStyle(lineWidth:1.5,lineJoin:.round))
            for p in pts{ctx.fill(Path(ellipseIn:CGRect(x:p.x-1.8,y:p.y-1.8,width:3.6,height:3.6)),with:.color(palette.accent))}
        }
        .background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:5))
        .accessibilityLabel("Operator envelope shape")
    }
}
func ratioText(_ v:Double)->String{String(format:"%.2f×",v)}
func fmRateText(_ v:Double)->String{String(format:"%.1f",v)}
func fmLevelText(_ v:Double)->String{String(format:"%.2f",v)}
func fmFreqText(_ v:Double)->String{v>=1000 ? String(format:"%.1f kHz",v/1000):String(format:"%.0f Hz",v)}
/// One cell of the 16-algorithm picker grid — keeps the grid closure trivially typed.
struct FmAlgorithmCell: View {
    @Environment(\.auroraPalette) private var palette
    let index:Int
    let selected:Bool
    let select:()->Void
    var body: some View {
        Button(action:select){
            VStack(spacing:2){
                FmAlgorithmDiagram(algorithm:index,selected:selected).frame(width:66,height:40)
                Text(FmPatch.algorithmMeta[index].name).font(.system(size:9)).lineLimit(1).foregroundStyle(selected ? palette.selectedText:palette.muted)
            }
        }.buttonStyle(.plain)
        .padding(4).background(selected ? palette.accent.opacity(0.18):palette.buttonSurface,in:RoundedRectangle(cornerRadius:6))
        .overlay(RoundedRectangle(cornerRadius:6).stroke(selected ? palette.accent:.white.opacity(0.08)))
        .accessibilityLabel("Algorithm \(index+1) \(FmPatch.algorithmMeta[index].name)")
    }
}
/// One operator column — hoisted so the FM panel closure stays type-checkable.
struct FmOperatorColumn: View {
    let index:Int
    let editor:EditorView
    var body: some View { editor.fmOpColumnBody(index) }
}
extension FmPatch {
    /// Mirrors kAlgos in Sources/FmEngine.cpp (locked spec §4) — UI labels + diagram routing.
    /// Families: 4 single-carrier chains · 5 two-carrier pairs (EP home) · 4 stacked · 3 feedback-forward.
    static let algorithmMeta:[(name:String,target:[Int],fb:Int)]=[
        ("Deep Tine",[1,2,3,-1],0),("Twin Roots",[2,2,3,-1],0),("Split Chain",[1,3,3,-1],0),("Triple Root",[3,3,3,-1],0),
        ("EP Twin",[-1,-1,0,1],2),("Chain & Solo",[-1,0,1,-1],2),("Mirror Pair",[1,-1,-1,2],0),("Nested Twin",[-1,-1,3,0],2),
        ("Hub Pair",[2,3,-1,-1],0),("Triple Crown",[-1,-1,-1,0],3),("Post Stack",[-1,-1,-1,1],3),("Head Stack",[3,-1,-1,-1],0),
        ("Pure Additive",[-1,-1,-1,-1],-1),("Deep Feedback",[1,2,3,-1],2),("Twin Feedback",[-1,-1,0,1],3),("Loopback",[1,2,3,-1],3)]
}
struct LayerPatch: Codable, Equatable {
    var values: [Int: Double]
    /// Spec §7: FM payload sibling of `values`. nil / absent = engine mode Subtractive.
    var fm: FmPatch? = nil
    subscript(_ id: Int) -> Double {
        get { values[id] ?? Self.extensionDefaults[id] ?? (id==34 ? 0.5 : id==36 ? 1 : id==37 ? 8 : id==38 ? 0.6 : id==43 ? 2 : 0) }
        set { values[id] = newValue }
    }
    static let extensionDefaults:[Int:Double]=[60:3200,63:0.5,64:0.01,65:0.35,67:0.35,72:1,74:0.25,75:1,76:0.5,77:12,78:1,82:4,88:4,100:1,101:1,103:4,109:1,110:1,112:4,118:1,119:1,121:4]
    static var initial: LayerPatch {
        LayerPatch(values: [0:1,1:2,2:1,3:0.35,4:7,5:0.12,6:0,
            7:2600,8:0.15,9:0.025,10:0.35,11:0.75,12:0.7,13:0.65,
            14:0,15:0,16:0.4,17:0.12,18:0,19:0,20:0.15,21:0.08,
            22:0,23:3,24:0,25:1,26:0.65,27:0,28:127,
            29:0.16,30:0.06,31:2,32:0,33:0,34:0.5,35:0,36:1,37:8,38:0.6,39:0,40:0,
            97:0,98:0])
    }
}
struct LayerSends:Codable,Equatable {
    var delay=1.0
    var reverb=1.0
    var shimmer=1.0
    var shimmerBypass=false
    var valid:Bool{delay.isFinite && reverb.isFinite && shimmer.isFinite && (0...1).contains(delay) && (0...1).contains(reverb) && (0...1).contains(shimmer)}
    enum CodingKeys:String,CodingKey{case delay,reverb,shimmer,shimmerBypass}
    init(delay:Double=1,reverb:Double=1,shimmer:Double=1,shimmerBypass:Bool=false){self.delay=delay;self.reverb=reverb;self.shimmer=shimmer;self.shimmerBypass=shimmerBypass}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        delay=try c.decodeIfPresent(Double.self,forKey:.delay) ?? 1
        reverb=try c.decodeIfPresent(Double.self,forKey:.reverb) ?? 1
        // Migration: missing shimmer key → copy reverb
        shimmer=try c.decodeIfPresent(Double.self,forKey:.shimmer) ?? reverb
        shimmerBypass=try c.decodeIfPresent(Bool.self,forKey:.shimmerBypass) ?? false
    }
}
struct LayerClipboard {
    var layer:LayerPatch
    var matrix:[MatrixAssignment]
    var motion:MotionSettings
    var sends:LayerSends
    var waves:[Int:ImportedWavetable]
}
struct MatrixAssignment:Codable,Equatable {
    var enabled=false
    var source=0
    var destination=0
    var target=4
    var cc=1
    var amount=0.0
    static let soundEmpty=Array(repeating:MatrixAssignment(),count:10)
    static let performanceEmpty=Array(repeating:MatrixAssignment(),count:10)
    func valid(performance:Bool)->Bool {
        let sourceOK=performance ? (0...5).contains(source):(0...10).contains(source)
        let destinationOK=performance ? (0...20).contains(destination):((0...7).contains(destination)||(12...46).contains(destination))
        return sourceOK && destinationOK && (0...4).contains(target) && (0...127).contains(cc) && amount.isFinite && (-1...1).contains(amount)
    }
}
struct SoundPreset: Identifiable, Codable {
    static let fxDefaults:[Int:Double]=[7:0.22,8:1,9:0,10:0.23,11:1,12:0.5,13:1,14:0,16:1,17:375,18:1,19:0.65,20:0,21:0,22:0,23:0,24:12,25:3,26:0.55,27:20,28:0.45,29:0.7,30:0.55,31:0.4,32:0,33:0.45,34:0.35,35:0.7,36:4,37:0,38:0.23,39:0.55,40:0.35,41:0,42:3,43:0.6,44:0,45:0,46:8,47:1,48:0,49:0.4,50:0,51:2,52:5,53:120,54:0,55:0,56:0,57:0.5,58:0.5,59:0,60:0,61:1,62:1,63:0,64:0,65:0,66:0,67:0,68:0,69:0]
    var fx: [Int:Double]? = nil
    func globalValue(_ id:Int)->Double {id<6 ? globals[id] : id==6 ? (phaserMix ?? 0) : (fx?[id] ?? Self.fxDefaults[id] ?? 0)}
    var id: String
    var name: String
    var category: String
    var detail: String
    var layers: [LayerPatch]
    var globals: [Double]
    var macros: [Double]
    var phaserMix: Double? = nil
    var soundMatrix: [[MatrixAssignment]]? = nil
    var motion:[MotionSettings]? = nil
    var sends:[LayerSends]? = nil
    var customMacros:[Int:CustomMacro]?=nil
    var xy:XYSettings?=nil
    var performanceMatrix: [MatrixAssignment]? = nil
    var importedWavetables:[Int:ImportedWavetable]? = nil
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
    var velocityCurve: Int? = nil
}
struct CCMapping: Codable {
    var source: Int32
    var channel: Int
    var controller: Int
    var macro: Int
}
struct SetSlot: Codable, Equatable {
    var patchId: String? = nil
    var name: String? = nil
    /// Optional pad BPM override (30…240). nil = use the patch tempo on recall.
    var tempo: Double? = nil
    var isEmpty: Bool { patchId == nil || patchId?.isEmpty == true }
}

struct SavedSession: Codable {
    var directMappings:[DirectCCMapping]?=nil
    var version: Int = 1
    var patch: SoundPreset
    var favorites: Set<String>
    var favoritesOnly: Bool? = nil
    var routes: [Int32: SourceRoute]
    var mappings: [CCMapping]
    var outputUID: String?
    var buffer: Int
    var transpose: Int? = nil
    var deletedSound: SoundPreset? = nil
    var deletedPresets: [SoundPreset]? = nil
    var outputGain:Double?=nil
    var outputGainRevision:Int?=nil
    /// Session house EQ (dB) — sticky across patch changes, like Output boost.
    var eqLow:Double?=nil
    var eqMid:Double?=nil
    var eqHigh:Double?=nil
    var setPage: Int? = nil
    var setSlots: [[SetSlot]]? = nil
    var setCutOnSwitch: Bool? = nil
    /// App keyboard / on-screen piano octave offset (not global transpose).
    var keyboardOctave: Int? = nil
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
    static let categoryOrder = ["Pads", "Bass", "Leads", "Keys", "Plucks", "Arps", "Textures", "Organs", "Brass & Strings", "Splits", "Templates", "FX", "2020s", "Shimmer"]
    static let expansion: [SoundPreset] = {
        guard let url = AuroraResources.bundle.url(forResource: "Aurora100", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let sounds = try? JSONDecoder().decode([SoundPreset].self, from: data),
              sounds.count >= 100 else { return [] }
        return sounds
    }()
    static let prism: [SoundPreset] = {
        guard let url=AuroraResources.bundle.url(forResource:"AuroraPrism100",withExtension:"json"),
              let data=try? Data(contentsOf:url),
              let sounds=try? JSONDecoder().decode([SoundPreset].self,from:data),sounds.count==100 else{return []}
        return sounds
    }()
    static let nova: [SoundPreset] = {
        guard let url=AuroraResources.bundle.url(forResource:"AuroraNova100",withExtension:"json"),
              let data=try? Data(contentsOf:url),
              let sounds=try? JSONDecoder().decode([SoundPreset].self,from:data),sounds.count==100 else{return []}
        return sounds
    }()
    static let gb: [SoundPreset] = {
        guard let url=AuroraResources.bundle.url(forResource:"AuroraGB109",withExtension:"json"),
              let data=try? Data(contentsOf:url),
              let sounds=try? JSONDecoder().decode([SoundPreset].self,from:data),sounds.count==60 else{return []}
        return sounds
    }()
    static let shimmer: [SoundPreset] = {
        guard let url=AuroraResources.bundle.url(forResource:"AuroraShimmer29",withExtension:"json"),
              let data=try? Data(contentsOf:url),
              let sounds=try? JSONDecoder().decode([SoundPreset].self,from:data),sounds.count==29 else{return []}
        return sounds
    }()
    static let references:[SoundPreset] = {
        guard let url=AuroraResources.bundle.url(forResource:"AuroraReference",withExtension:"json"),let data=try? Data(contentsOf:url),let sounds=try? JSONDecoder().decode([SoundPreset].self,from:data) else{return []}
        return sounds
    }()
    /// Brand-new bank (FX-only era). No strict count: it starts empty and grows
    /// as new patches are authored. The 60 FX reference sounds live in `gb`.
    static let fxBank: [SoundPreset] = {
        guard let url=AuroraResources.bundle.url(forResource:"AuroraFX",withExtension:"json"),
              let data=try? Data(contentsOf:url),
              let sounds=try? JSONDecoder().decode([SoundPreset].self,from:data) else{return []}
        return sounds
    }()
    static let all: [SoundPreset] = (expansion + prism + nova + gb + shimmer + fxBank).sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
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
    var backend=AuroraBackend()
    @Published private(set) var samples=Array(repeating:Float(0),count:256)
    @Published private(set) var levelSamples=Array(repeating:Float(0),count:256)
    // Trigger at upward zero crossings, selecting three complete cycles. This
    // is a display-only zoom; the recorded and audible signal is unchanged.
    static func displayWave(_ input:[Float],normalize:Bool=true)->[Float]{
        let silence=Array(repeating:Float(0),count:256)
        guard input.count>4 else{return silence}
        let recent=Array(input.suffix(4096))
        let peak=recent.reduce(Float(0)){max($0,abs($1))}
        guard peak.isFinite,peak>0.0001 else{return silence}
        var crossings:[Int]=[],armed=false
        for i in 1..<input.count{
            if input[i] < -peak*0.12{armed=true}
            if armed && input[i-1]<=0 && input[i]>0{crossings.append(i);armed=false}
        }
        let end=crossings.last ?? (input.count-1)
        let start=crossings.count>=3 ? crossings[max(0,crossings.count-4)]:max(0,end-255)
        guard end>start else{return silence}
        let windowPeak=input[start...end].reduce(Float(0)){max($0,abs($1))}
        let gain:Float=normalize ? 0.82/max(0.0001,windowPeak):1
        return (0..<256).map{i in
            let position=Float(start)+Float(end-start)*Float(i)/255
            let a=min(end,Int(position)),b=min(end,a+1),mix=position-Float(a)
            return (input[a]*(1-mix)+input[b]*mix)*gain
        }
    }
    func update() {
        var raw=Array(repeating:Float(0),count:8192)
        let count=raw.withUnsafeMutableBufferPointer{backend.aurora_copy_scope($0.baseAddress,Int32($0.count))}
        let next=Self.displayWave(Array(raw.prefix(Int(count)))).map{($0*500).rounded()/500}
        if next != samples {samples=next}
        let levels=Self.displayWave(Array(raw.prefix(Int(count))),normalize:false).map{($0*1000).rounded()/1000}
        if levels != levelSamples{levelSamples=levels}
    }
}
struct OutputLevelReadout:View {
    @ObservedObject var telemetry:AudioTelemetry
    var body:some View{
        Text(telemetry.snapshot.peak>0.00001 ? String(format:"Peak %.1f dBFS",20*log10(telemetry.snapshot.peak)):"Peak −∞ dBFS")
            .font(.system(size:13,design:.monospaced)).foregroundStyle(telemetry.snapshot.peak>0.95 ? Color.orange:Color.white)
    }
}
struct OutputScope:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:ScopeTelemetry
    var normalized=true
    var body:some View {
        Canvas{context,size in
            var center=Path();center.move(to:CGPoint(x:0,y:size.height/2));center.addLine(to:CGPoint(x:size.width,y:size.height/2))
            context.stroke(center,with:.color(palette.muted.opacity(0.2)),lineWidth:0.5)
            var wave=Path()
            let samples=normalized ? telemetry.samples:telemetry.levelSamples
            if !normalized {
                var grid=Path()
                for i in 1..<8{let x=size.width*Double(i)/8;grid.move(to:CGPoint(x:x,y:0));grid.addLine(to:CGPoint(x:x,y:size.height))}
                for i in 1..<4{let y=size.height*Double(i)/4;grid.move(to:CGPoint(x:0,y:y));grid.addLine(to:CGPoint(x:size.width,y:y))}
                context.stroke(grid,with:.color(palette.graphCyan.opacity(0.12)),lineWidth:0.5)
            }
            for (i,sample) in samples.enumerated(){
                let point=CGPoint(x:CGFloat(i)*size.width/CGFloat(telemetry.samples.count-1),y:size.height/2-CGFloat(max(-1,min(1,sample)))*(size.height/2-3))
                if i==0{wave.move(to:point)}else{wave.addLine(to:point)}
            }
            context.stroke(wave,with:.color(palette.graphCyan.opacity(0.13)),lineWidth:normalized ? 4:8)
            context.stroke(wave,with:.linearGradient(Gradient(colors:[palette.graphCyan,palette.accent,palette.graphPink]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:0)),lineWidth:normalized ? 1.5:2)
        }.background(palette.graphBackground,in:RoundedRectangle(cornerRadius:7)).accessibilityLabel("Live output waveform").help(normalized ? "Live output · three-cycle view with automatic display scaling":"Live output · three-cycle view at actual output level")
    }
}
@MainActor final class ModulationTelemetry:ObservableObject {
    var backend=AuroraBackend()
    @Published private(set) var values=Array(repeating:Float(0),count:50)
    func update() {
        var next=Array(repeating:Float(0),count:50)
        _=next.withUnsafeMutableBufferPointer{backend.aurora_copy_modulation($0.baseAddress,Int32($0.count))}
        next=next.map{($0*100).rounded()/100}
        if next != values{values=next}
    }
}
struct ModulationIndicator:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:ModulationTelemetry
    let slots:[Int]
    var body:some View {
        GeometryReader{g in
            let value=max(-1,min(1,slots.reduce(Float(0)){$0+telemetry.values[$1]}))
            ZStack(alignment:.leading){
                Capsule().fill(palette.accent.opacity(0.17))
                Capsule().fill(palette.accent).frame(width:3).offset(x:CGFloat((value+1)/2)*max(0,g.size.width-3))
            }
        }.frame(height:3).accessibilityLabel("Live matrix modulation").help("Matrix modulation · position shows the combined offset for the most recently rendered note")
    }
}
@MainActor final class CompGRTelemetry:ObservableObject {
    var backend=AuroraBackend()
    @Published private(set) var gr:Double=0
    func update(){let v=Double(backend.aurora_comp_gr());let clamped=v.isFinite ? max(0,min(48,v)) : 0;if clamped != gr{gr=clamped}}
}
struct CompGRMeter:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:CompGRTelemetry
    var body:some View {
        HStack(spacing:6){
            GeometryReader{g in
                let clipped=min(telemetry.gr,24)/24
                ZStack(alignment:.trailing){
                    Capsule().fill(palette.accent.opacity(0.17))
                    Capsule().fill(palette.graphPink).frame(width:3).offset(x:-CGFloat(clipped)*max(0,g.size.width-3))
                }
            }.frame(height:3)
            Text(telemetry.gr<0.05 ? "GR off" : String(format:"−%.1f dB",telemetry.gr)).font(.system(size:11,weight:palette.weight(.regular))).monospacedDigit().foregroundStyle(palette.muted).frame(width:58,alignment:.trailing)
        }.accessibilityLabel("Compressor gain reduction").help("Gain reduction · how much the compressor is pulling down")
    }
}
struct MatrixFeedback:ViewModifier {
    @Environment(\.auroraPalette) private var palette
    let model:SynthModel
    let destination:Int
    var layer:Int?=nil
    func body(content:Content)->some View {
        let slots=model.modulationSlots(destination:destination,layer:layer)
        content.overlay(alignment:.bottom){if !slots.isEmpty{ModulationIndicator(telemetry:model.modulation,slots:slots).offset(y:3)}}
    }
}
@MainActor final class PerformanceTelemetry:ObservableObject {
    var backend=AuroraBackend()
    @Published var clockBPM:Double=0
    @Published var seconds:Int=0
    func update(){let bpm=(Double(backend.aurora_clock_tempo())*10).rounded()/10;let time=Int(backend.aurora_record_seconds());if bpm != clockBPM{clockBPM=bpm};if time != seconds{seconds=time}}
}
struct ClockReadout:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:PerformanceTelemetry
    var body:some View{Text(telemetry.clockBPM>0 ? String(format:"%.1f",telemetry.clockBPM):"—").monospacedDigit().frame(width:48).accessibilityLabel("External tempo")}
}
struct EngineReadout:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:AudioTelemetry
    var body:some View {
        // Fixed-width digit fields (DSP XXX% · Voices XX) so the header does not jump.
        HStack(spacing:14){
            Text(String(format:"DSP %3d%%", min(999, telemetry.snapshot.cpuPercent)))
                .monospacedDigit()
                .accessibilityLabel("DSP \(telemetry.snapshot.cpuPercent) percent")
            Text(String(format:"Voices %2d", min(99, telemetry.snapshot.voices)))
                .monospacedDigit()
                .accessibilityLabel("\(telemetry.snapshot.voices) active voices")
                .help("Active voices")
        }
        .accessibilityElement(children:.combine)
    }
}
struct VoiceStatus:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    var body:some View {
        ZStack{
            HStack(spacing:12){
                Label("\(m.telemetry.snapshot.voices) voices",systemImage:"waveform")
                Spacer(minLength:8)
                Text(m.running ? "Ready to play":"Enable audio in the header to start")
            }
            HStack(spacing:0){
                Button{m.setKeyboardOctave(m.keyboardOctave-1)}label:{Image(systemName:"chevron.left").frame(width:28,height:30).contentShape(Rectangle())}.disabled(m.keyboardOctave <= -2).accessibilityLabel("App keyboard octave down")
                Text(m.keyboardOctave > 0 ? "+\(m.keyboardOctave)":"\(m.keyboardOctave)").monospacedDigit().font(.system(size:15,weight:palette.weight(.medium))).frame(width:34).accessibilityLabel("App keyboard octave \(m.keyboardOctave)")
                Button{m.setKeyboardOctave(m.keyboardOctave+1)}label:{Image(systemName:"chevron.right").frame(width:28,height:30).contentShape(Rectangle())}.disabled(m.keyboardOctave >= 2).accessibilityLabel("App keyboard octave up")
            }.buttonStyle(AuroraFlatButtonStyle()).background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:7)).help("App keyboard octave · on-screen piano and typing keys (A W S E D…) · not global transpose")
        }
    }
}

@MainActor final class SynthModel: ObservableObject {
    let backend:AuroraBackend
    var syncingPlugin=false
    var lastPluginRevision:UInt64=UInt64.max
    var lastPluginMappingsData:Data?
    @Published var patch = FactoryBank.all.first{$0.name=="Apricot Solstice"} ?? FactoryBank.all[0] {didSet{pluginMetadataChanged(oldValue)}}
    @Published var userPresets: [SoundPreset] = []
    @Published var selectedLayer = 0
    @Published var screen = "Play"
    @Published var search = ""
    @Published var patchBrowserCategory:String?=nil
    @Published var patchBrowserUserOnly=false
    @Published var patchBrowserRow=0
    @Published var collection = "KiMiA"
    @Published var category = "All categories"
    @Published var outputGain=9.0
    static func restoredOutputGain(_ saved:Double?,revision:Int?)->Double {
        // Rev 4: CK88 / stage-piano dual-layer house level (~+9 dB), Master ~50–75%.
        // Rev 3 was the synth-reference +24 dB migration. Move untouched +24 sessions
        // to +9 once; keep any boost the user already customized.
        if revision == 4, let saved, saved.isFinite { return max(0, min(24, saved)) }
        if revision == 3, let saved, saved.isFinite {
            if abs(saved - 24) < 0.01 { return 9 }
            return max(0, min(24, saved))
        }
        return 9
    }
    func setOutputGain(_ gain:Double){
        guard gain.isFinite else{return};outputGain=max(0,min(24,gain));backend.aurora_set_global(15,Float(outputGain));persist()
    }
    /// Session EQ (dB), sticky across patches — not stored in patch.fx.
    @Published var eqLow=0.0
    @Published var eqMid=0.0
    @Published var eqHigh=0.0
    func setEqLow(_ v:Double){guard v.isFinite else{return};eqLow=max(-12,min(12,v));backend.aurora_set_global(20,Float(eqLow));persist()}
    func setEqMid(_ v:Double){guard v.isFinite else{return};eqMid=max(-12,min(12,v));backend.aurora_set_global(21,Float(eqMid));persist()}
    func setEqHigh(_ v:Double){guard v.isFinite else{return};eqHigh=max(-12,min(12,v));backend.aurora_set_global(22,Float(eqHigh));persist()}
    func applySessionEQ(){
        backend.aurora_set_global(20,Float(eqLow))
        backend.aurora_set_global(21,Float(eqMid))
        backend.aurora_set_global(22,Float(eqHigh))
    }
    @Published var favoritesOnly = false
    @Published var favorites: Set<String> = []
    @Published var setPage = 0
    @Published var setSlots: [[SetSlot]] = Array(repeating: Array(repeating: SetSlot(), count: 16), count: 4)
    @Published var setCutOnSwitch = false
    @Published var devices: [AudioDevice] = []
    @Published var sources: [MIDISource] = []
    @Published var output: UInt32 = 0
    @Published var buffer = 128
    @Published var running = false
    @Published var status = "Audio is off. Choose your output, then enable audio."
    let telemetry = AudioTelemetry()
    let scope=ScopeTelemetry()
    let modulation=ModulationTelemetry()
    let compGR=CompGRTelemetry()
    @Published var sampleRate = 0.0
    @Published var actualFrames: UInt32 = 0
    @Published var pressed: Set<Int> = []
    @Published var routes: [Int32:SourceRoute] = [:]
    @Published var mappings: [CCMapping] = []
    @Published var learningMacro: Int? = nil
    @Published var notice = ""
    @Published var dirty = false
    @Published var saveName = ""
    @Published var saveCategory = ""
    @Published var saveFavorite = false
    @Published var showingSave = false
    @Published var transpose = 0
    @Published var keyboardOctave = 0
    @Published var renameID: String? = nil
    @Published var renameName = ""
    @Published var renameCategory = ""
    @Published var deletedPresets:[SoundPreset] = []
    var deletedSound:SoundPreset? {deletedPresets.first}
    private var tapTimes: [TimeInterval] = []
    let wavetableTelemetry=WavetableTelemetry()
    let motionTelemetry=MotionTelemetry()
    @Published var showingCreativeTools=false
    @Published var savedShapes:[SavedMotionShape]=[]
    @Published var learningControl:ControlTarget?=nil
    @Published var directMappings:[DirectCCMapping]=[]
    var directPickup=Set<String>()
    var directPrevious:[String:Double]=[:]
    var lastDirectEdit=Date.distantPast
    var applyingDirectCC=false
    @Published var soloLayer = -1
    @Published var comparingSaved=false
    @Published var layerClipboard:LayerClipboard?=nil
    var savedComparison:SoundPreset?{userPresets.first{$0.id==patch.id} ?? FactoryBank.all.first{$0.id==patch.id}}
    func finishComparison(){if comparingSaved{comparingSaved=false;applyPatch()}}
    func toggleComparison(){
        if comparingSaved{finishComparison();return}
        guard var reference=savedComparison else{return}
        let edits=patch;reference.globals[0]=edits.globals[0]
        comparingSaved=true;patch=reference;applyPatch();patch=edits
    }
    func browsePatch(_ delta:Int, panic:Bool = true){
        let all=library.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
        let scoped=all.filter{$0.category==patch.category}
        let sounds=scoped.isEmpty ? all:scoped
        guard !sounds.isEmpty else{return}
        let index=sounds.firstIndex{$0.id==patch.id} ?? (delta>0 ? -1:0)
        loadPreset(sounds[(index+delta+sounds.count)%sounds.count], panic: panic)
    }
    func toggleSolo(_ layer:Int){soloLayer=soloLayer==layer ? -1:layer;backend.aurora_solo_layer(Int32(soloLayer))}
    func copyLayer(_ layer:Int){
        let waves=Dictionary(uniqueKeysWithValues:(0..<2).compactMap{o -> (Int,ImportedWavetable)? in guard let wave=patch.importedWavetables?[layer*2+o] else{return nil};return (o,wave)})
        layerClipboard=LayerClipboard(layer:patch.layers[layer],matrix:patch.soundMatrix?[layer] ?? MatrixAssignment.soundEmpty,motion:patch.motion?[layer] ?? MotionSettings(),sends:patch.sends?[layer] ?? LayerSends(),waves:waves)
        notice="Copied layer \(layerLetters[layer]), including modulation, sends and imported waves."
    }
    func pasteLayer(_ layer:Int, panic:Bool = true){
        guard let copied=layerClipboard else{return};checkpoint()
        if panic { backend.aurora_panic();pressed=[];holding=false }
        patch.layers[layer]=copied.layer
        var matrix=patch.soundMatrix ?? Array(repeating:MatrixAssignment.soundEmpty,count:4);matrix[layer]=copied.matrix;patch.soundMatrix=matrix
        var motion=patch.motion ?? Array(repeating:MotionSettings(),count:4);motion[layer]=copied.motion;patch.motion=motion
        var sends=patch.sends ?? Array(repeating:LayerSends(),count:4);sends[layer]=copied.sends;patch.sends=sends
        var waves=patch.importedWavetables ?? [:];for o in 0..<2{waves[layer*2+o]=copied.waves[o]};patch.importedWavetables=waves.isEmpty ? nil:waves
        selectedLayer=layer;applyPatch();dirty=true;notice="Pasted into layer \(layerLetters[layer]). Undo restores the previous layer."
    }
    enum SendBus{case delay,reverb,shimmer}
    func sendBinding(_ bus:SendBus)->Binding<Double>{Binding(get:{let sends=self.patch.sends?[self.selectedLayer] ?? LayerSends();switch bus{case .delay:return sends.delay;case .reverb:return sends.reverb;case .shimmer:return sends.shimmer}},set:{value in
        self.finishComparison();var sends=self.patch.sends ?? Array(repeating:LayerSends(),count:4)
        switch bus{case .delay:sends[self.selectedLayer].delay=value;case .reverb:sends[self.selectedLayer].reverb=value;case .shimmer:sends[self.selectedLayer].shimmer=value}
        self.patch.sends=sends;self.applySends();self.dirty=true
    })}
    /// Compatibility for older call sites / InterfaceChecks
    func sendBinding(_ delay:Bool)->Binding<Double>{sendBinding(delay ? .delay:.reverb)}
    func applySends(){for l in 0..<4{let sends=patch.sends?[l] ?? LayerSends();backend.aurora_layer_sends(Int32(l),Float(sends.delay),Float(sends.reverb),Float(sends.shimmerBypass ? 0:sends.shimmer))}}
    func setShimmerBypass(_ bypassed:Bool){
        checkpoint()
        finishComparison()
        var sends=patch.sends ?? Array(repeating:LayerSends(),count:4)
        sends[selectedLayer].shimmerBypass=bypassed
        patch.sends=sends
        applySends()
        dirty=true
    }
    @Published var wavetableMessage=""
    private var appliedWavetables:[Int:ImportedWavetable]=[:]
    func hasCustomWavetable(oscillator:Int)->Bool{patch.importedWavetables?[selectedLayer*2+oscillator] != nil}
    func wavetableName(oscillator:Int)->String{
        let index=max(0,min(24,Int(patch.layers[selectedLayer][45+oscillator*7])))
        return index==24 ? (patch.importedWavetables?[selectedLayer*2+oscillator]?.name ?? "Import a table"):WavetableCatalog.names[index]
    }
    func importWavetable(oscillator:Int){
        finishComparison()
        let layer=selectedLayer,slot=layer*2+oscillator
        let panel=NSOpenPanel();panel.allowedContentTypes=[.wav];panel.allowsMultipleSelection=false
        panel.message="Import a WAV wavetable: 1–64 aligned waveform frames. This does not convert an ordinary recording into a wavetable."
        let accessory=NSStackView();accessory.orientation = .horizontal;accessory.spacing=12
        accessory.addArrangedSubview(NSTextField(labelWithString:"Samples per frame:"))
        let sizes=NSPopUpButton();for size in [256,512,1024,2048]{sizes.addItem(withTitle:String(size));sizes.lastItem?.tag=size};sizes.selectItem(withTag:2048)
        accessory.addArrangedSubview(sizes);panel.accessoryView=accessory;panel.isAccessoryViewDisclosed=true
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let frameSize=sizes.selectedItem?.tag ?? 2048
        var samples=Array(repeating:Float(0),count:64*2048),error=Array(repeating:CChar(0),count:512)
        let frames=samples.withUnsafeMutableBufferPointer{buffer in error.withUnsafeMutableBufferPointer{message in aurora_read_wavetable(url.path,Int32(frameSize),buffer.baseAddress,Int32(buffer.count),message.baseAddress,Int32(message.count))}}
        guard frames>0 else{wavetableMessage=String(cString:error);return}
        samples=Array(samples.prefix(Int(frames)*frameSize))
        let imported=ImportedWavetable(name:String(url.deletingPathExtension().lastPathComponent.prefix(80)),frameSize:frameSize,data:samples.withUnsafeBytes{Data($0)})
        guard installWavetable(imported,layer:layer,oscillator:oscillator) else{return}
        checkpoint();if patch.importedWavetables==nil{patch.importedWavetables=[:]};patch.importedWavetables?[slot]=imported
        appliedWavetables[slot]=imported;set(layer,44+oscillator*7,1);set(layer,45+oscillator*7,24)
        wavetableMessage="Imported \(imported.name) · \(frames) frames. Save the patch to keep this table.";persist()
    }
    @discardableResult func installWavetable(_ imported:ImportedWavetable,layer:Int,oscillator:Int)->Bool{
        guard imported.valid else{wavetableMessage="This wavetable data is invalid.";return false}
        let samples=imported.samples
        let success=samples.withUnsafeBufferPointer{backend.aurora_set_custom_wavetable(Int32(layer),Int32(oscillator),$0.baseAddress,Int32(imported.frames),Int32(imported.frameSize))}==1
        if !success{wavetableMessage="Could not prepare the wavetable. The previous table is still available."}
        return success
    }
    func applyWavetables(){
        for slot in 0..<8{
            let imported=patch.importedWavetables?[slot]
            if imported != appliedWavetables[slot]{
                if let imported{if installWavetable(imported,layer:slot/2,oscillator:slot%2){appliedWavetables[slot]=imported}}
                else{backend.aurora_clear_custom_wavetable(Int32(slot/2),Int32(slot%2));appliedWavetables[slot]=nil}
            }
        }
    }
    let performanceTelemetry=PerformanceTelemetry()
    @Published var holding=false
    @Published var externalClock=false
    @Published var clockSourceID:Int32=0
    @Published var recording=false
    @Published var recordingURL:URL?=nil
    @Published var recordingMessage=""
    @Published var normalizingRecording=false
    private let normalizationQueue=DispatchQueue(label:"Aurora.RecordingNormalization",qos:.utility)
    func setHold(_ enabled:Bool){holding=enabled;backend.aurora_hold(enabled ? 1:0)}
    func setClock(_ enabled:Bool,source:Int32){externalClock=enabled;clockSourceID=source;backend.aurora_clock_source(enabled ? 1:0,source)}
    func toggleRecording(){
        if recording{finishRecording();return}
        guard running else{recordingMessage="Enable audio first.";return}
        guard !normalizingRecording else{return}
        let directory=FileManager.default.urls(for:.desktopDirectory,in:.userDomainMask)[0].appendingPathComponent("Aurora",isDirectory:true)
        do{
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let stamp=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
            let url=directory.appendingPathComponent("Aurora-\(stamp)-\(UUID().uuidString.prefix(6)).wav")
            if backend.aurora_record_start(url.path)==1{recordingURL=url;recording=true;recordingMessage=""}else{recordingMessage=String(cString:backend.aurora_status())}
        }catch{recordingMessage="Could not create recording: \(error.localizedDescription)"}
    }
    func finishRecording(){
        let success=backend.aurora_record_stop()==1;recording=false
        guard success,let url=recordingURL else{recordingMessage="Recording error: "+String(cString:backend.aurora_status());return}
        normalizingRecording=true;recordingMessage="Normalizing…"
        normalizationQueue.async{[weak self] in
            let normalized=aurora_normalize_recording(url.path)==1
            guard let model=self else{return}
            DispatchQueue.main.async{
                MainActor.assumeIsolated {
                    model.normalizingRecording=false
                    model.recordingMessage=normalized ? "Saved to Desktop/Aurora · normalized to −3 dB":"Saved original WAV; normalization failed."
                }
            }
        }
    }
    func setTranspose(_ value:Int) {
        transpose=max(-24,min(24,value));backend.aurora_set_transpose(Int32(transpose));persist()
    }
    func setKeyboardOctave(_ value:Int) {
        let next=max(-2,min(2,value))
        guard next != keyboardOctave else{return}
        for note in Array(pressed){noteOff(note)}
        keyboardOctave=next
        persist()
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
        let category=String(renameCategory.trimmingCharacters(in:.whitespacesAndNewlines).prefix(60))
        if !category.isEmpty{userPresets[i].category=category;if patch.id==id{patch.category=category}}
        self.category="All categories"
        renameID=nil;persist();notice="Sound renamed to \(name)."
    }
    func deleteSound(_ id:String) {
        guard let i=userPresets.firstIndex(where:{$0.id==id}) else{return}
        deletedPresets.insert(userPresets.remove(at:i),at:0)
        persist();notice="Sound moved to Deleted sounds. Restore it from the collection menu."
    }
    func undoDelete() {
        guard let sound=deletedSound else{return}
        restoreDeleted(sound.id)
    }
    func restoreDeleted(_ id:String) {
        guard let i=deletedPresets.firstIndex(where:{$0.id==id}) else{return}
        let sound=deletedPresets.remove(at:i)
        if !userPresets.contains(where:{$0.id==id}){userPresets.insert(sound,at:0)}
        persist();notice="Restored \(sound.name)."
    }
    func beginSaveAs() {saveName=patch.name+" copy";saveCategory=patch.category;saveFavorite=false;showingSave=true}
    func saveCurrent() {
        finishComparison()
        guard let i=userPresets.firstIndex(where:{$0.id==patch.id}) else{beginSaveAs();return}
        userPresets[i]=patch;dirty=false;persist();notice="Saved \(patch.name)."
    }
    private var timer: Timer?
    private var lastSessionData:Data?
    var lastPresetData:Data?
    private var ticks = 0
    private var lastCCCount: UInt64 = 0
    private var pickup: Set<Int> = []
    private var previousCC: [Int:Double] = [:]
    private var monitors: [Any] = []
    private var outputUID: String?
    private var undoPatches: [SoundPreset] = []
    private var redoPatches: [SoundPreset] = []
    static let ranges: [ClosedRange<Double>] = [0...1,0...4,0...4,0...1,0...30,0...1,0...1,30...18000,0...0.9,0.001...8,0.01...8,0...1,0.01...12,0...1,-1...1,-48...48,0.03...20,0...1,0...3,0...4,-1...1,0...1,0...1,0...5,0...29,1...4,0.1...0.95,0...127,0...127,0.03...20,0...1,0...3,0...3,0...4,0.05...0.95,0...1,1...8,0...30,0...1,0...1,0...36,0...2,0...2,0...24,0...1,0...24,0...1,0...5,0...1,0...1,0...1,0...1,0...24,0...1,0...5,0...1,0...1,0...1,0...1,0...3,30...18000,0...0.9,0...2,0...1,0.001...8,0.01...12,0...1,0.01...12,-1...1,0...6,0...3,0...1,0.25...8,0...4,0...1,0...1,0...1,4...16,0.02...1,0...1,0...1,0...1,0...9,0...1,0...1,0...8,0...8,0...1,0...9,0...1,0...1,0...8,0...8,0...1,0...1,0...1,0...1,0...1,0...4,0...4,0.03...20,0...1,0...1,0...9,0...1,0...1,0...8,0...8,0...4,0.03...20,0...1,0...1,0...9,0...1,0...1,0...8,0...8,0...4,0.03...20,0...1,0...1,0...9,0...1,0...1,0...8,0...8]
    private static let integerParameters: Set<Int> = [0,1,2,15,18,19,22,23,24,25,27,28,31,32,33,36,39,41,43,44,45,47,51,52,54,58,59,62,69,70,73,77,79,80,81,82,83,87,88,89,98,99,102,103,104,108,111,112,113,117,120,121,122]
    static let globalRanges: [ClosedRange<Double>] = [0...1,30...240,0...0.6,0...0.75,0...0.75,0...0.6,0...1,0.03...5,0...1,-0.85...0.85,0.03...5,0...1,0...1,0.2...8,0...7,0...24,0...1,1...2000,0...1,0...1,-12...12,-12...12,-12...12,0...1,-12...24,0.2...12,0...1,0...200,0...0.95,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0.2...12,0...1,0.03...5,0...1,0...0.9,0...1,0.03...8,0...1,0...2,0...1,1...16,1...64,0...1,0...1,-60...0,1...12,0.1...100,5...1000,0...18,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1,0...1]
    static func sanitized(_ input:SoundPreset) -> SoundPreset? {
        guard input.layers.count==4,input.globals.count==6,input.macros.count==8,
              input.globals.allSatisfy(\.isFinite),input.macros.allSatisfy(\.isFinite) else{return nil}
        guard (input.phaserMix ?? 0).isFinite else{return nil}
        var paddedSound:[[MatrixAssignment]]?
        if let matrix=input.soundMatrix {
            guard matrix.count==4 else{return nil}
            var padded:[[MatrixAssignment]]=[]
            for layer in matrix {
                var rows=layer
                if rows.count==6 {rows.append(contentsOf:Array(repeating:MatrixAssignment(),count:4))}
                guard rows.count==10, rows.allSatisfy({$0.valid(performance:false)}) else{return nil}
                padded.append(rows)
            }
            paddedSound=padded
        }
        if let motion=input.motion{guard motion.count==4,motion.allSatisfy(\.valid) else{return nil}}
        if let sends=input.sends{guard sends.count==4,sends.allSatisfy(\.valid) else{return nil}}
        var paddedPerf:[MatrixAssignment]?=nil
        if var matrix=input.performanceMatrix {
            if matrix.count==6 {matrix.append(contentsOf:Array(repeating:MatrixAssignment(),count:4))}
            guard matrix.count==10,matrix.allSatisfy({$0.valid(performance:true)}) else{return nil}
            paddedPerf=matrix
        }
        if let macros=input.customMacros{guard macros.count<=8,macros.allSatisfy({(0..<8).contains($0.key) && $0.value.valid}) else{return nil}}
        if let xy=input.xy{guard xy.valid else{return nil}}
        var result=input
        if let paddedSound {result.soundMatrix=paddedSound}
        if let paddedPerf {result.performanceMatrix=paddedPerf}
        if let tables=input.importedWavetables{guard tables.count<=8,tables.allSatisfy({(0..<8).contains($0.key)&&$0.value.valid}) else{return nil}}
        for slot in 0..<8 where input.layers[slot/2][45+(slot%2)*7]==24 {
            guard input.importedWavetables?[slot] != nil else{return nil}
        }
        if let fx=input.fx {
            // 20–22 are session EQ (Play), not patch — drop if present in older files
            let patchFX=fx.filter{!($0.key==20 || $0.key==21 || $0.key==22)}
            guard patchFX.allSatisfy({(((7...14).contains($0.key)) || ((16...69).contains($0.key))) && $0.value.isFinite && globalRanges.indices.contains($0.key)}) else{return nil}
            result.fx=patchFX.mapValues{$0}
            for (p,v) in patchFX {
                let r=globalRanges[p]
                let rounded = (p==14 || p==16 || p==32 || p==24) ? v.rounded() : v
                result.fx?[p]=max(r.lowerBound,min(r.upperBound,rounded))
            }
        }
        result.phaserMix=max(0,min(1,input.phaserMix ?? 0))
        for i in 0..<4 {
            guard input.layers[i].values.allSatisfy({(0..<ranges.count).contains($0.key) && $0.value.isFinite}) else{return nil}
            var layer=LayerPatch.initial
            let legacyRate = input.layers[i].values[97] == nil
            for (p,v) in input.layers[i].values {
                var value=v
                if legacyRate, p==23 {
                    // Old rate 0,1,2,3 → 0,1,3,5 (1/4,1/8,1/16,1/32) before clip into expanded divisions.
                    let map=[0.0,1.0,3.0,5.0]
                    let idx=Int(v.rounded())
                    if (0..<map.count).contains(idx) { value=map[idx] }
                }
                let r=ranges[p],clipped=max(r.lowerBound,min(r.upperBound,value))
                layer[p]=integerParameters.contains(p) ? clipped.rounded():clipped
            }
            if layer[27]>layer[28]{layer[28]=layer[27]}
            layer.fm=input.layers[i].fm
            result.layers[i]=layer
        }
        for p in 0..<6 {result.globals[p]=max(globalRanges[p].lowerBound,min(globalRanges[p].upperBound,input.globals[p]))}
        result.macros=input.macros.map{max(0,min(1,$0))}
        result.name=String(input.name.prefix(120));result.detail=String(input.detail.prefix(500));result.category=String(input.category.prefix(60))
        return result
    }
    private let keyNotes: [UInt16:Int] = [0:60,13:61,1:62,14:63,2:64,3:65,17:66,5:67,16:68,4:69,32:70,38:71,40:72,31:73,37:74,35:75,41:76]
    static let defaultMacroNames = ["Brightness","Warmth","Movement","Space","Attack","Release","Width","Character"]
    var collectionSounds: [SoundPreset] {
        switch collection {
        case "KiMiA": return FactoryBank.all
        case "Your sounds": return userPresets
        case "Deleted sounds": return deletedPresets
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
    @Published private(set) var theme=AuroraTheme.copper
    func selectTheme(_ value:AuroraTheme){
        guard value != theme else{return};theme=value
        do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONEncoder().encode(value).write(to:folder.appendingPathComponent("appearance.json"),options:.atomic)}catch{notice="Couldn't save appearance: \(error.localizedDescription)"}
    }
    var macroNames:[String]{(0..<8).map{patch.customMacros?[$0]?.name ?? Self.defaultMacroNames[$0]}}
    var folder: URL {
        if let storageDirectory {return storageDirectory}
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Aurora",isDirectory:true)
    }
    init(storageDirectory:URL? = nil,backend:AuroraBackend=AuroraBackend()) {
        self.backend=backend
        scope.backend=backend;modulation.backend=backend;performanceTelemetry.backend=backend
        motionTelemetry.backend=backend;wavetableTelemetry.backend=backend
        self.storageDirectory=storageDirectory
        if let data=try? Data(contentsOf:folder.appendingPathComponent("appearance.json")),let saved=try? JSONDecoder().decode(AuroraTheme.self,from:data){theme=saved}
        backend.aurora_initialize()
        if !backend.isPlugin{restore()}else{restorePluginLibrary();syncPlugin()}
        restoreShapeLibrary()
        if FactoryBank.expansion.isEmpty || FactoryBank.prism.isEmpty {
            notice="A factory sound bank could not be loaded. Rebuild or reopen the complete app bundle."
        }
        if !backend.isPlugin{applyPatch()}
        refresh()
        if !backend.isPlugin{installKeyboard()}
        let updateTimer = Timer(timeInterval:0.05,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        updateTimer.tolerance=0.005
        RunLoop.main.add(updateTimer,forMode:.common)
        timer=updateTimer
    }
    func applyPatch() {
#if AURORA_PLUGIN
        commitPluginPatch(apply:true);return
#endif
        directPickup.removeAll();directPrevious.removeAll()
        applySends()
        applyMotion()
        applyWavetables()
        applyMatrix()
        backend.aurora_set_transpose(Int32(transpose))
        backend.aurora_set_global(15,Float(outputGain))
        backend.aurora_set_global(6,Float(patch.phaserMix ?? 0))
        for p in 7...14{backend.aurora_set_global(Int32(p),Float(patch.globalValue(p)))}
        for p in 16...69 where p < 20 || p > 22 {
            backend.aurora_set_global(Int32(p),Float(patch.globalValue(p)))
        }
        applySessionEQ() // house EQ stays session-sticky across patch loads
        for i in 0..<4 {for p in 0..<Self.ranges.count {backend.aurora_set_parameter(Int32(i),Int32(p),Float(patch.layers[i][p]))}}
        for i in 0..<4 { applyFm(i) }
        for (p,v) in patch.globals.enumerated() { backend.aurora_set_global(Int32(p),Float(v)) }
    }
    func soundRows(_ layer:Int)->[MatrixAssignment] {
        var rows=patch.soundMatrix?[layer] ?? MatrixAssignment.soundEmpty
        if rows.count==6 {rows.append(contentsOf:Array(repeating:MatrixAssignment(),count:4))}
        return rows.count==10 ? rows : MatrixAssignment.soundEmpty
    }
    func matrixRows(performance:Bool)->[MatrixAssignment] {
        performance ? (patch.performanceMatrix ?? MatrixAssignment.performanceEmpty):soundRows(selectedLayer)
    }
    func modulationSlots(destination:Int,layer:Int?=nil)->[Int] {
        let layer=layer ?? selectedLayer
        var slots:[Int]=[]
        if destination<8 || destination>=12 {
            for (i,row) in soundRows(layer).enumerated() where row.enabled && row.destination==destination {slots.append(layer*10+i)}
        }
        for (i,row) in (patch.performanceMatrix ?? MatrixAssignment.performanceEmpty).enumerated() where row.enabled && row.destination==destination && ((8...11).contains(destination) || row.target==4 || row.target==layer){slots.append(40+i)}
        return slots
    }
    func updateMatrix(performance:Bool,slot:Int,change:(inout MatrixAssignment)->Void) {
        finishComparison()
        guard (0..<10).contains(slot) else{return}
        var rows=matrixRows(performance:performance);change(&rows[slot])
        if performance && (8...11).contains(rows[slot].destination){rows[slot].target=4}
        guard rows[slot].valid(performance:performance) else{return}
        if performance{patch.performanceMatrix=rows}else{
            var matrix=patch.soundMatrix ?? Array(repeating:MatrixAssignment.soundEmpty,count:4)
            matrix[selectedLayer]=rows;patch.soundMatrix=matrix
        }
        applyMatrix();dirty=true
    }
    func applyMatrix() {
        for bank in 0..<5 {
            let rows=bank==4 ? (patch.performanceMatrix ?? MatrixAssignment.performanceEmpty):soundRows(bank)
            for (slot,row) in rows.enumerated(){backend.aurora_set_matrix(Int32(bank),Int32(slot),row.enabled ? 1:0,Int32(row.source),Int32(row.destination),Int32(row.target),Int32(row.cc),Float(row.amount))}
        }
    }
    func checkpoint() {
        finishComparison()
        if undoPatches.last?.layers != patch.layers || undoPatches.last?.globals != patch.globals || undoPatches.last?.phaserMix != patch.phaserMix || undoPatches.last?.fx != patch.fx || undoPatches.last?.soundMatrix != patch.soundMatrix || undoPatches.last?.performanceMatrix != patch.performanceMatrix || undoPatches.last?.importedWavetables != patch.importedWavetables || undoPatches.last?.motion != patch.motion || undoPatches.last?.sends != patch.sends || undoPatches.last?.customMacros != patch.customMacros || undoPatches.last?.xy != patch.xy || undoPatches.last?.macros != patch.macros {
            undoPatches.append(patch); if undoPatches.count > 40 { undoPatches.removeFirst() }; redoPatches = []
        }
    }
    func undo() { finishComparison();guard let old = undoPatches.popLast() else { return }; redoPatches.append(patch); patch=old;applyPatch();dirty=true;pickup=[];previousCC=[:] }
    func redo() { finishComparison();guard let old = redoPatches.popLast() else { return }; undoPatches.append(patch);patch=old;applyPatch();dirty=true;pickup=[];previousCC=[:] }
    func loadPreset(_ preset: SoundPreset, panic: Bool = true) {
        checkpoint()
        directPickup.removeAll();directPrevious.removeAll()
        soloLayer = -1;backend.aurora_solo_layer(-1)
        let master=patch.globals[0]
        if panic {
            backend.aurora_panic();pressed=[];holding=false
        }
        patch=preset; patch.globals[0]=master
        applyPatch();dirty=false;pickup=[];previousCC=[:]
        notice="Loaded \(preset.name). Previous edits are available with Undo."
        persist()
    }
    func set(_ layer:Int,_ parameter:Int,_ value:Double) {
        finishComparison()
        if !applyingDirectCC{for mapping in directMappings where mapping.target==ControlTarget(layer:layer,parameter:parameter){directPickup.remove(mapping.id);directPrevious[mapping.id]=nil}}
        guard (0..<4).contains(layer),Self.ranges.indices.contains(parameter),value.isFinite else{return}
        let range=Self.ranges[parameter]
        var value=max(range.lowerBound,min(range.upperBound,value))
        if Self.integerParameters.contains(parameter){value=value.rounded()}
        if parameter==27{value=min(value,patch.layers[layer][28])}
        if parameter==28{value=max(value,patch.layers[layer][27])}
        patch.layers[layer][parameter]=value
        if parameter==1 || parameter==2{let mode=parameter==1 ? 44:51;patch.layers[layer][mode]=0;backend.aurora_set_parameter(Int32(layer),Int32(mode),0)}
        backend.aurora_set_parameter(Int32(layer),Int32(parameter),Float(value));dirty=true
    }
    func global(_ parameter:Int,_ value:Double) {
        if parameter != 0{finishComparison()}
        if !applyingDirectCC{for mapping in directMappings where mapping.target==ControlTarget(layer:-1,parameter:parameter){directPickup.remove(mapping.id);directPrevious[mapping.id]=nil}}
        guard Self.globalRanges.indices.contains(parameter),value.isFinite else{return}
        // Output gain (15) uses setOutputGain; still allow clamping if reached via ControlTarget.
        let needsRound = parameter==14 || parameter==16 || parameter==32 || parameter==24
        let r=Self.globalRanges[parameter],value=max(r.lowerBound,min(r.upperBound,needsRound ? value.rounded():value))
        if parameter==15{setOutputGain(value);return}
        if parameter==20{setEqLow(value);return}
        if parameter==21{setEqMid(value);return}
        if parameter==22{setEqHigh(value);return}
        if parameter>6{if patch.fx==nil{patch.fx=[:]};patch.fx?[parameter]=value}else if parameter==6{patch.phaserMix=value}else{patch.globals[parameter]=value};backend.aurora_set_global(Int32(parameter),Float(value));dirty=true
    }
    /// FM engine edit: checkpoint for undo, mutate this layer's FmPatch, push 96 floats.
    func setFm(_ mutate:(inout FmPatch)->Void, layer:Int?=nil, checkpointing:Bool=true) {
        let l=layer ?? selectedLayer
        if checkpointing { checkpoint() }
        var fm=patch.layers[l].fm ?? FmPatch()
        mutate(&fm)
        patch.layers[l].fm=fm
        applyFm(l)
        dirty=true
    }
    func applyFm(_ l:Int) {
        backend.aurora_set_layer_fm(Int32(l),(patch.layers[l].fm ?? FmPatch()).packed(),Int32(96))
    }
    func parameter(_ parameter:Int, layer:Int?=nil) -> Binding<Double> {
        let l=layer ?? selectedLayer
        return Binding(get:{self.patch.layers[l][parameter]},set:{self.set(l,parameter,$0)})
    }
    func globalBinding(_ parameter:Int) -> Binding<Double> {
        if parameter==20{return Binding(get:{self.eqLow},set:{self.setEqLow($0)})}
        if parameter==21{return Binding(get:{self.eqMid},set:{self.setEqMid($0)})}
        if parameter==22{return Binding(get:{self.eqHigh},set:{self.setEqHigh($0)})}
        return Binding(get:{self.patch.globalValue(parameter)},set:{self.global(parameter,$0)})
    }
    func macro(_ index:Int,_ value:Double) {
#if AURORA_PLUGIN
        aurora_plugin_macro(backend.context,Int32(index),value);syncPlugin();dirty=true;return
#endif
        finishComparison()
        let value=max(0,min(1,value));let delta=value-patch.macros[index]
        patch.macros[index]=value
        if let definition=patch.customMacros?[index]{for route in definition.routes{setControl(route.target,route.from+(route.to-route.from)*value)};dirty=true;return}
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
        if force { backend.aurora_refresh_devices() }
        func decode<T:Decodable>(_ type:T.Type,_ pointer:UnsafePointer<CChar>?) -> T? {
            guard let pointer else {return nil};return try? JSONDecoder().decode(type,from:Data(String(cString:pointer).utf8))
        }
        let nextDevices=decode([AudioDevice].self,backend.aurora_audio_devices_json()) ?? []
        let nextSources=decode([MIDISource].self,backend.aurora_midi_sources_json()) ?? []
        if devices != nextDevices { devices=nextDevices }
        if sources != nextSources { sources=nextSources }
        if output==0, let uid=outputUID,let d=devices.first(where:{$0.uid==uid}) { output=d.id }
        for source in sources {
            if let route=routes[source.id] {
                backend.aurora_velocity_curve(source.id,Int32(max(0,min(3,route.velocityCurve ?? 0))))
                if source.layerMask != route.mask || source.channel != route.channel {backend.aurora_route_source(source.id,Int32(route.mask),Int32(route.channel))}
            }
            else { routes[source.id]=SourceRoute(mask:source.layerMask ?? ((source.enabled ?? true) ? 1:0),channel:source.channel ?? 0) }
        }
    }
    func poll() {
        // P3: defer main-thread pull/telemetry work during live scroll & drag tracking; resumes on release.
        let tracking=RunLoop.main.currentMode == .eventTracking
        if !tracking {
            syncPlugin()
            performanceTelemetry.update()
        }
        if recording&&backend.aurora_recording()==0{finishRecording()}
        ticks += 1
        // Keep disk work and device-list updates out of live scroll/drag tracking.
        if RunLoop.main.currentMode != .eventTracking {
            if ticks % 40 == 0 { refresh(force:false) }
            if ticks % 100 == 0 { persist() }
        }
        let nextRunning=backend.aurora_audio_running() != 0
        let nextRate=backend.aurora_sample_rate(), nextFrames=backend.aurora_buffer_frames()
        if running != nextRunning { running=nextRunning;if !running{holding=false} }
        if sampleRate != nextRate { sampleRate=nextRate }
        if actualFrames != nextFrames { actualFrames=nextFrames }
        if !tracking {
            scope.update()
            modulation.update()
            compGR.update()
            wavetableTelemetry.update()
            motionTelemetry.update()
            telemetry.update(peak:backend.aurora_output_peak(),load:backend.aurora_cpu_load(),voices:Int(backend.aurora_active_voices()),midiEvents:backend.aurora_midi_event_count())
        }
        if let p=backend.aurora_status() {
            let nextStatus=String(cString:p)
            if status != nextStatus { status=nextStatus }
        }
        let count=backend.aurora_cc_count()
        if count != lastCCCount {
            lastCCCount=count
            let cc=backend.aurora_last_cc_snapshot();guard cc != UInt64.max else{return}
            let source=Int32(bitPattern:UInt32(cc>>32)),channel=Int((cc>>16)&255),controller=Int((cc>>8)&255),value=Double(cc&255)/127
            if backend.isPlugin && learningMacro==nil && learningControl==nil{return}
            if learningMacro==nil && handleDirectCC(source:source,channel:channel,controller:controller,value:value){return}
            if let index=learningMacro {
                if controller==64 || controller>=120 {notice="Sustain and channel-mode controls stay reserved. Move a knob to learn it.";return}
                directMappings.removeAll{$0.source==source && $0.channel==channel && $0.controller==controller}
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
        routes[source]=route;backend.aurora_route_source(source,Int32(route.mask),Int32(route.channel));backend.aurora_velocity_curve(source,Int32(max(0,min(3,route.velocityCurve ?? 0))));persist()
    }
    func toggleAudio() {
        guard !backend.isPlugin else{return}
        holding=false
        if recording{finishRecording()}
        notice=""
        if running {backend.aurora_stop_audio();pressed=[]}
        else { _=backend.aurora_start_audio(output,UInt32(buffer));output=backend.aurora_current_device() }
        poll()
    }
    func changeOutput(_ id:UInt32) {
        if running { backend.aurora_stop_audio();pressed=[];notice="Output changed. Enable audio when you're ready." }
        output=id;outputUID=devices.first(where:{$0.id==id})?.uid;persist()
    }
    func noteOn(_ note:Int) { guard !pressed.contains(note) else{return};pressed.insert(note);backend.aurora_note_on(Int32(note),90) }
    func noteOff(_ note:Int) { guard pressed.contains(note) else{return};pressed.remove(note);backend.aurora_note_off(Int32(note)) }
    func panic() {backend.aurora_panic();pressed=[];holding=false;notice="All notes and effect tails stopped."}
    func favorite(_ id:String) { if favorites.contains(id){favorites.remove(id)}else{favorites.insert(id)};persist() }
    func setFavoritesOnly(_ on:Bool) {
        guard favoritesOnly != on else { return }
        favoritesOnly = on
        persist()
    }
    static func normalizedSetSlots(_ raw: [[SetSlot]]?) -> [[SetSlot]] {
        var pages = Array(repeating: Array(repeating: SetSlot(), count: 16), count: 4)
        guard let raw else { return pages }
        for p in 0..<min(4, raw.count) {
            for s in 0..<min(16, raw[p].count) {
                let slot = raw[p][s]
                let id = slot.patchId?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id, !id.isEmpty {
                    let tempo: Double? = {
                        guard let t = slot.tempo, t.isFinite else { return nil }
                        return max(30, min(240, t.rounded()))
                    }()
                    pages[p][s] = SetSlot(patchId: String(id.prefix(80)), name: slot.name.map { String($0.prefix(120)) }, tempo: tempo)
                }
            }
        }
        return pages
    }
    func setSetPage(_ page: Int) {
        let next = max(0, min(3, page))
        guard setPage != next else { return }
        setPage = next
        persist()
    }
    func setSetCutOnSwitch(_ on: Bool) {
        guard setCutOnSwitch != on else { return }
        setCutOnSwitch = on
        persist()
    }
    private var setLibrary: [SoundPreset] { userPresets + FactoryBank.all }
    func presetForSetSlot(_ slot: SetSlot) -> SoundPreset? {
        guard let id = slot.patchId, !id.isEmpty else { return nil }
        return setLibrary.first { $0.id == id }
    }
    func applySetSlotTempo(_ slot: SetSlot) {
        guard let t = slot.tempo, t.isFinite else { return }
        let bpm = max(30, min(240, t.rounded()))
        guard abs(patch.globals[1] - bpm) > 0.05 else { return }
        global(1, bpm)
    }
    func recallSetSlot(_ index: Int) {
        guard (0..<16).contains(index) else { return }
        let slot = setSlots[setPage][index]
        guard !slot.isEmpty else { notice = "Set pad \(index + 1) is empty. Right-click to assign the current patch."; return }
        guard let preset = presetForSetSlot(slot) else {
            notice = "Set pad \(index + 1) points to a missing patch (\(slot.name ?? "unknown")). Clear or reassign it."
            return
        }
        if patch.id == preset.id {
            if let t = slot.tempo {
                let bpm = max(30, min(240, t.rounded()))
                if abs(patch.globals[1] - bpm) > 0.05 {
                    applySetSlotTempo(slot)
                    persist()
                    notice = "Pad \(index + 1) tempo \(Int(bpm)) BPM."
                } else {
                    notice = "Already on \(preset.name)."
                }
            } else {
                notice = "Already on \(preset.name)."
            }
            return
        }
        loadPreset(preset, panic: setCutOnSwitch)
        applySetSlotTempo(slot)
        if slot.tempo != nil { persist() }
        if let t = slot.tempo {
            notice = "Loaded \(preset.name) · pad tempo \(Int(max(30, min(240, t.rounded())))) BPM."
        }
    }
    func assignSetSlot(_ index: Int, withTempo: Bool = false) {
        guard (0..<16).contains(index) else { return }
        let tempo: Double? = withTempo ? max(30, min(240, patch.globals[1].rounded())) : nil
        setSlots[setPage][index] = SetSlot(patchId: patch.id, name: patch.name, tempo: tempo)
        persist()
        if let tempo {
            notice = "Assigned \(patch.name) @ \(Int(tempo)) BPM to page \(setPage + 1) · pad \(index + 1)."
        } else {
            notice = "Assigned \(patch.name) to page \(setPage + 1) · pad \(index + 1) (patch tempo)."
        }
    }
    func setSetSlotTempo(_ index: Int) {
        guard (0..<16).contains(index) else { return }
        var slot = setSlots[setPage][index]
        guard !slot.isEmpty else { notice = "Pad \(index + 1) is empty — assign a patch first."; return }
        let bpm = max(30, min(240, patch.globals[1].rounded()))
        slot.tempo = bpm
        setSlots[setPage][index] = slot
        persist()
        notice = "Pad \(index + 1) tempo set to \(Int(bpm)) BPM (overrides patch)."
    }
    func clearSetSlotTempo(_ index: Int) {
        guard (0..<16).contains(index) else { return }
        var slot = setSlots[setPage][index]
        guard !slot.isEmpty, slot.tempo != nil else { return }
        slot.tempo = nil
        setSlots[setPage][index] = slot
        persist()
        notice = "Pad \(index + 1) uses patch tempo again."
    }
    func clearSetSlot(_ index: Int) {
        guard (0..<16).contains(index) else { return }
        guard !setSlots[setPage][index].isEmpty else { return }
        setSlots[setPage][index] = SetSlot()
        persist()
        notice = "Cleared page \(setPage + 1) · pad \(index + 1)."
    }
    func saveUserPreset() {
        finishComparison()
        let name=String(saveName.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120));guard !name.isEmpty else{return}
        var copy=patch;copy.id=UUID().uuidString;copy.name=name;copy.detail="Your own Aurora performance."
        let category=String(saveCategory.trimmingCharacters(in:.whitespacesAndNewlines).prefix(60))
        if !category.isEmpty{copy.category=category}
        userPresets.insert(copy,at:0);patch=copy;dirty=false;showingSave=false
        let starred=saveFavorite;if starred{favorites.insert(copy.id)}
        collection="Your sounds";self.category="All categories";search=""
        persist();notice="Saved \(name)."+(starred ? " Added to favorites.":"")
    }
    func exportPreset() {
        let panel=NSSavePanel();panel.nameFieldStringValue=patch.name+".aurora.json";panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try JSONEncoder().encode(patch).write(to:url,options:.atomic);notice="Preset exported."}catch{notice="Could not export: \(error.localizedDescription)"}
    }
    static func presets(in data:Data)throws->[SoundPreset] {
        let decoder=JSONDecoder()
        if let item=try? decoder.decode(SoundPreset.self,from:data){return [item]}
        if let items=try? decoder.decode([SoundPreset].self,from:data),!items.isEmpty{return items}
        throw CocoaError(.fileReadCorruptFile)
    }
    func importPresetURLs(_ urls:[URL]) {
        var imported:[SoundPreset]=[],failed=0
        for url in urls {
            do {
                // A bank may contain many embedded user wavetables, so its portable
                // JSON can be much larger than a single-preset file.
                guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<512_000_000 else{throw CocoaError(.fileReadCorruptFile)}
                let data=try Data(contentsOf:url);guard data.count<512_000_000 else{throw CocoaError(.fileReadCorruptFile)}
                for decoded in try Self.presets(in:data) {
                    guard var item=Self.sanitized(decoded) else{failed+=1;continue}
                    item.id=UUID().uuidString;imported.append(item)
                }
            }catch{failed+=1}
        }
        guard !imported.isEmpty else{notice="No valid Aurora presets were found in the selected files.";return}
        userPresets.insert(contentsOf:imported,at:0);loadPreset(imported[0])
        collection="Your sounds";category="All categories";search="";persist()
        notice="Imported \(imported.count) preset\(imported.count==1 ? "":"s")"+(failed>0 ? "; \(failed) item\(failed==1 ? "":"s") could not be imported.":".")
    }
    func importPreset() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK else{return};importPresetURLs(panel.urls)
    }
    func importPresets() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=true
        panel.message="Select individual Aurora presets or preset-bank JSON files."
        guard panel.runModal() == .OK else{return};importPresetURLs(panel.urls)
    }
    func exportUserPresets() {
        guard !userPresets.isEmpty else{notice="There are no user-saved presets to export yet.";return}
        let panel=NSSavePanel();panel.nameFieldStringValue="Aurora User Patches.aurora.json";panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(userPresets).write(to:url,options:.atomic)
            notice="Exported \(userPresets.count) user preset\(userPresets.count==1 ? "":"s") in one bank file."
        }catch{notice="Could not export the preset bank: \(error.localizedDescription)"}
    }
    func persist() {
        if backend.isPlugin{persistPluginLibrary();return}
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let saved=SavedSession(directMappings:directMappings,patch:patch,favorites:favorites,favoritesOnly:favoritesOnly,routes:routes,mappings:mappings,outputUID:outputUID,buffer:buffer,transpose:transpose,deletedPresets:deletedPresets,outputGain:outputGain,outputGainRevision:4,eqLow:eqLow,eqMid:eqMid,eqHigh:eqHigh,setPage:setPage,setSlots:setSlots,setCutOnSwitch:setCutOnSwitch,keyboardOctave:keyboardOctave)
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
            deletedPresets=(s.deletedPresets ?? (s.deletedSound.map{[$0]} ?? [])).compactMap{Self.sanitized($0)}
            transpose=max(-24,min(24,s.transpose ?? 0))
            var directIDs=Set<String>(),directTargets=Set<ControlTarget>()
            directMappings=Array((s.directMappings ?? []).filter{$0.valid && directIDs.insert($0.id).inserted && directTargets.insert($0.target).inserted}.prefix(256))
            patch=valid;favorites=s.favorites;favoritesOnly=s.favoritesOnly ?? false;routes=s.routes.filter{(0...15).contains($0.value.mask) && (0...16).contains($0.value.channel)}
            outputGain=Self.restoredOutputGain(s.outputGain,revision:s.outputGainRevision)
            eqLow=max(-12,min(12,s.eqLow ?? 0))
            eqMid=max(-12,min(12,s.eqMid ?? 0))
            eqHigh=max(-12,min(12,s.eqHigh ?? 0))
            mappings=s.mappings.filter{(0..<8).contains($0.macro) && (0...127).contains($0.controller) && (1...16).contains($0.channel)}
            outputUID=s.outputUID;buffer=[64,128,256,512].contains(s.buffer) ? s.buffer:128
            setPage=max(0,min(3,s.setPage ?? 0))
            setSlots=Self.normalizedSetSlots(s.setSlots)
            setCutOnSwitch=s.setCutOnSwitch ?? false
            keyboardOctave=max(-2,min(2,s.keyboardOctave ?? 0))
        }
        if let data=try? Data(contentsOf:folder.appendingPathComponent("presets.json")),let list=try? JSONDecoder().decode([SoundPreset].self,from:data){userPresets=list.compactMap{Self.sanitized($0)}}
        // Retired factory sounds should not remain the startup sound after the
        // Spectrum replacement. User sounds, including imports, remain intact.
        let retiredFactory=patch.id.hasPrefix("a100-") || patch.id.hasPrefix("prism-") || patch.id.hasPrefix("nova-") || FactoryBank.starter.contains{$0.id==patch.id} || FactoryBank.references.contains{$0.id==patch.id}
        if retiredFactory && !userPresets.contains(where:{$0.id==patch.id}) {
            let master=patch.globals[0]
            patch=FactoryBank.all.first{$0.name=="Apricot Solstice"} ?? FactoryBank.all[0]
            patch.globals[0]=master
        }
    }
    func installKeyboard() {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]) { [weak self] event in
            guard let self,NSApp.keyWindow?.firstResponder is NSTextView == false,!event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),!event.modifierFlags.contains(.option),let base=self.keyNotes[event.keyCode] else{return event}
            let note=base+self.keyboardOctave*12
            guard (0...127).contains(note) else{return event}
            if event.type == .keyDown {if !event.isARepeat{self.noteOn(note)}}else{self.noteOff(note)}
            return nil
        } as Any)
        NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {
                guard let self else{return}
                for note in Array(self.pressed){self.noteOff(note)}
            }
        }
    }
    func shutdown() {if recording{finishRecording()};normalizationQueue.sync{};persist();timer?.invalidate();for m in monitors{NSEvent.removeMonitor(m)};backend.aurora_shutdown()}
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
/// Weighted columns; row height from `heightSource` subview (default first), so a short panel is not stretched by a tall neighbor.
struct WeightedHeightRow: Layout {
    var spacing: CGFloat = 16
    var weights: [CGFloat]
    var heightSource: Int = 0
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width=proposal.width ?? 900
        let n=subviews.count
        guard n>0 else {return .zero}
        let wts=Array(weights.prefix(n))+Array(repeating:1.0,count:max(0,n-weights.count))
        let total=max(0.0001,wts.reduce(0,+))
        let usable=width-spacing*CGFloat(max(0,n-1))
        let heights:(Int)->CGFloat = { i in
            subviews[i].sizeThatFits(.init(width:usable*(wts[i]/total),height:nil)).height
        }
        let src=min(max(0,heightSource),n-1)
        return CGSize(width:width,height:heights(src))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let n=subviews.count
        guard n>0 else {return}
        let wts=Array(weights.prefix(n))+Array(repeating:1.0,count:max(0,n-weights.count))
        let total=max(0.0001,wts.reduce(0,+))
        let usable=bounds.width-spacing*CGFloat(max(0,n-1))
        var x=bounds.minX
        for (i,view) in subviews.enumerated(){
            let w=usable*(wts[i]/total)
            view.place(at:CGPoint(x:x,y:bounds.minY),anchor:.topLeading,proposal:.init(width:w,height:bounds.height))
            x+=w+spacing
        }
    }
}
struct Panel<Content:View>:View {
    @Environment(\.auroraPalette) private var palette
    let title:String
    var accessory:AnyView?=nil
    let content:Content
    init(title:String,accessory:AnyView?=nil,@ViewBuilder content:()->Content){self.title=title;self.accessory=accessory;self.content=content()}
    var body:some View {VStack(alignment:.leading,spacing:16){HStack(alignment:.center,spacing:10){Text(title).font(.system(size:19,weight:palette.weight(.semibold)));Spacer(minLength:0);if let accessory{accessory}};content}.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(palette.surface,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.07))).buttonStyle(AuroraButtonStyle())}
}
/// Master FX power switch for an effects panel header. Off is a true bypass in the
/// engine — the effect leaves the stereo bus — and the wet mix, rate and depth
/// settings stay stored in the patch so powering back on restores the exact sound.
struct FxPowerToggle:View {
    @ObservedObject var m:SynthModel
    let parameter:Int
    let name:String
    let help:String
    private var on:Bool{m.patch.globalValue(parameter) >= 0.5}
    var body:some View {
        Button{m.checkpoint();m.global(parameter,on ? 0:1)}label:{
            Label(on ? "On":"Off",systemImage:"power").font(.system(size:12)).lineLimit(1)
        }
        // selected = the accent colour, so powered reads orange and Off reads grey.
        // AuroraButtonStyle also bolds the selected label, reinforcing the state.
        .buttonStyle(AuroraButtonStyle(selected:on))
        .accessibilityLabel(name)
        .accessibilityValue(on ? "On":"Off")
        .accessibilityHint(help)
        .help(help)
    }
}
struct ParameterSlider:View {
    @Environment(\.auroraPalette) private var palette
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
        VStack(spacing:5){HStack{Text(title).foregroundStyle(palette.muted);Spacer();Text(format(value)).monospacedDigit()}.font(.system(size:15,weight:palette.weight(.regular)));Slider(value:normalized,in:0...1,onEditingChanged:{if $0{onBegin()}}).tint(palette.accent).accessibilityLabel(title).accessibilityValue(format(value))}
    }
}
struct MacroDial:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var model:SynthModel
    let index:Int
    var value:Double{model.patch.macros[index]}
    var body:some View {
        VStack(spacing:9){
            ZStack{
                Circle().trim(from:0.125,to:0.875).stroke(palette.raised,lineWidth:5).rotationEffect(.degrees(90))
                Circle().trim(from:0.125,to:0.125+value*0.75).stroke(palette.accent,style:StrokeStyle(lineWidth:5,lineCap:.round)).rotationEffect(.degrees(90))
                Circle().fill(palette.surface).padding(10)
                Capsule().fill(palette.accent).frame(width:3,height:15).offset(y:-25).rotationEffect(.degrees(-135+270*value))
            }.frame(width:88,height:88).accessibilityHidden(true)
            HStack{Text(model.macroNames[index]);Spacer();Text("\(Int(value*100))").foregroundStyle(palette.muted).monospacedDigit()}.font(.system(size:15,weight:palette.weight(.medium)))
            Slider(value:Binding(get:{value},set:{model.macro(index,$0)}),in:0...1,onEditingChanged:{if $0{model.checkpoint()}}).tint(palette.accent).accessibilityLabel(model.macroNames[index])
                Button{model.learningControl=nil;model.learningMacro = model.learningMacro==index ? nil:index;model.notice=model.learningMacro==nil ? "MIDI Learn cancelled.":"Move a hardware knob for \(model.macroNames[index])."}label:{Label(model.learningMacro==index ? "Move a knob…":model.mappings.contains(where:{$0.macro==index}) ? "Mapped":"MIDI Learn",systemImage:"cable.connector")}.buttonStyle(AuroraIconButtonStyle()).font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(Color.white)
        }.frame(maxWidth:.infinity).padding(.vertical,8)
    }
}
struct LayerStrip:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var model:SynthModel
    let index:Int
    var body:some View {
        VStack(alignment:.leading,spacing:9){
            HStack(spacing:8){
                Button{model.selectedLayer=index;if model.screen != "Matrix"{model.screen="Edit"}}label:{Text(layerLetters[index]).font(.system(size:15,weight:model.selectedLayer==index ? .bold:.regular)).frame(width:32,height:29).background(model.selectedLayer==index ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:5)).foregroundStyle(model.selectedLayer==index ? palette.selectedText:Color.white)}.buttonStyle(AuroraFlatButtonStyle(selected:model.selectedLayer==index))
                Spacer(minLength:8)
                Button{model.toggleSolo(index)}label:{Text("S").font(.system(size:13,weight:model.soloLayer==index ? .bold:.regular)).foregroundStyle(model.soloLayer==index ? palette.selectedText:Color.white).frame(width:23,height:23).background(model.soloLayer==index ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:4))}.buttonStyle(AuroraFlatButtonStyle(selected:model.soloLayer==index)).help("Solo layer \(layerLetters[index]); shared FX tails may continue")
                Menu{Button("Copy layer"){model.copyLayer(index)};Button("Paste layer"){model.pasteLayer(index)}.disabled(model.layerClipboard==nil)}label:{AuroraEllipsisLabel()}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Copy or paste this layer, including its modulation and wavetable data").accessibilityLabel("Copy or paste layer \(layerLetters[index])")
                Button{model.checkpoint();model.set(index,0,model.patch.layers[index][0]>0.5 ? 0:1)}label:{Image(systemName:"power").foregroundStyle(model.patch.layers[index][0]>0.5 ? palette.selectedText:Color.white)}.buttonStyle(AuroraIconButtonStyle(selected:model.patch.layers[index][0]>0.5)).accessibilityLabel("Enable layer \(layerLetters[index])")
            }
            Picker("Layer \(layerLetters[index]) engine",selection:Binding(get:{(model.patch.layers[index].fm?.enabled ?? false) ? 1:0},set:{v in model.selectedLayer=index;model.setFm{fm in fm.enabled = v==1}})){
                Text("Sub").tag(0)
                Text("FM").tag(1)
            }.labelsHidden().frame(width:96).pickerStyle(.segmented).font(.system(size:13)).accessibilityLabel("Layer \(layerLetters[index]) engine Subtractive or FM")
            Picker("Layer \(layerLetters[index]) waveform",selection:Binding(get:{model.patch.layers[index][44] > 0.5 ? 5:Int(model.patch.layers[index][1])},set:{model.checkpoint();if $0==5{model.set(index,44,1)}else{model.set(index,1,Double($0))};model.selectedLayer=index})){
                ForEach(Array(["Sine","Triangle","Saw","Pulse","Harmonic"].enumerated()),id:\.offset){i,name in Text(name).tag(i)}
                Text("Wavetable").tag(5)
            }.labelsHidden().font(.system(size:16,weight:palette.weight(.medium)))
            HStack{Text("\(Int(model.patch.layers[index][27]))–\(Int(model.patch.layers[index][28]))");Spacer();Text(model.patch.layers[index][22]>0.5 ? "ARP":["POLY","MONO","LEGATO"][max(0,min(2,Int(model.patch.layers[index][41])))])}.font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            Slider(value:model.parameter(13,layer:index),in:0...1,onEditingChanged:{if $0{model.checkpoint()}}).tint(palette.accent).accessibilityLabel("Layer \(layerLetters[index]) volume").modifier(MatrixFeedback(model:model,destination:3,layer:index))
        }.padding(13).background(palette.surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(model.selectedLayer==index ? palette.accent.opacity(0.55):.white.opacity(0.08))).opacity(model.patch.layers[index][0]>0.5 ? 1:0.65).contentShape(Rectangle()).onTapGesture{model.selectedLayer=index;if model.screen != "Matrix"{model.screen="Edit"}}
    }
}
struct PianoView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var model:SynthModel
    private var low:Int{48+model.keyboardOctave*12}
    private var high:Int{84+model.keyboardOctave*12}
    private var whites:[Int]{(low...high).filter{[0,2,4,5,7,9,11].contains($0%12)}}
    private var blacks:[(Int,Int)]{(low...high).filter{[1,3,6,8,10].contains($0%12)}.map{note in (note,whites.filter{$0<note}.count-1)}}
    func key(_ note:Int,black:Bool)->some View {
        RoundedRectangle(cornerRadius:4).fill(model.pressed.contains(note) ? palette.accent:(black ? Color(red:0.08,green:0.10,blue:0.085):Color(red:0.81,green:0.84,blue:0.79)))
            .overlay(alignment:.bottom){if !black{Text(note%12==0 ? "C\(note/12-1)":"").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(.black.opacity(0.5)).padding(.bottom,7)}}
            .gesture(DragGesture(minimumDistance:0).onChanged{_ in model.noteOn(note)}.onEnded{_ in model.noteOff(note)})
            .accessibilityElement(children:.ignore).accessibilityLabel("MIDI note \(note)").accessibilityAddTraits(.isButton)
            .accessibilityAction{model.noteOn(note);Task{@MainActor in try? await Task.sleep(for:.milliseconds(250));model.noteOff(note)}}
    }
    var body:some View {
        let middleC=60+model.keyboardOctave*12
        return VStack(spacing:8){HStack{Text("PLAY A LITTLE").tracking(1.4);Spacer();Text("Typing keys A W S E D… · middle C = MIDI \(middleC)")}.font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            GeometryReader{g in let width=g.size.width/Double(max(1,whites.count))
                ZStack(alignment:.topLeading){HStack(spacing:2){ForEach(whites,id:\.self){note in key(note,black:false)}}
                    ForEach(blacks,id:\.0){note,pos in key(note,black:true).frame(width:width*0.6,height:51).offset(x:width*Double(pos+1)-width*0.3)}
                }
            }.frame(height:82)
        }
    }
}

@MainActor final class EditorDisplayState:ObservableObject {@Published var autoScale=true}
struct EditorView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @StateObject private var display=EditorDisplayState()
    var scopeAutoScale:Bool{get{display.autoScale} nonmutating set{display.autoScale=newValue}}
    let waves=["Sine","Triangle","Saw","Pulse","Harmonic"]
    func choice(_ label:String,_ p:Int,_ options:[String])->some View {
        Picker(label,selection:Binding(get:{Int(m.patch.layers[m.selectedLayer][p])},set:{m.checkpoint();m.set(m.selectedLayer,p,Double($0))})){ForEach(Array(options.enumerated()),id:\.offset){i,s in Text(s).tag(i)}}.font(.system(size:15,weight:palette.weight(.regular)))
    }
    // MARK: - FM engine panel (FUTURE-PROPOSAL-FM-ENGINE.md §3/§9)
    var fmOn:Bool{m.patch.layers[m.selectedLayer].fm?.enabled ?? false}
    var fm:FmPatch{m.patch.layers[m.selectedLayer].fm ?? FmPatch()}
    func fmBinding<T>(_ kp:WritableKeyPath<FmPatch,T>)->Binding<T>{
        Binding(get:{(m.patch.layers[m.selectedLayer].fm ?? FmPatch())[keyPath:kp]},
                set:{v in m.setFm({$0[keyPath:kp]=v},checkpointing:false)})
    }
    func fmOpBinding<T>(_ op:Int,_ kp:WritableKeyPath<FmOpState,T>)->Binding<T>{
        Binding(get:{(m.patch.layers[m.selectedLayer].fm ?? FmPatch()).op(op)[keyPath:kp]},
                set:{v in m.setFm({var o=$0.op(op);o[keyPath:kp]=v;$0.setOp(op,o)},checkpointing:false)})
    }
    func fmEnvBinding(_ op:Int,_ levels:Bool,_ i:Int)->Binding<Double>{
        Binding(get:{let o=(m.patch.layers[m.selectedLayer].fm ?? FmPatch()).op(op)
            return levels ? (o.env.levels.count>i ? o.env.levels[i] : 0) : (o.env.rates.count>i ? o.env.rates[i] : 0.02)},
                set:{v in m.setFm({var o=$0.op(op);var e=o.env
                    if levels {while e.levels.count<=i{e.levels.append(0)};e.levels[i]=v}
                    else {while e.rates.count<=i{e.rates.append(0.02)};e.rates[i]=v}
                    o.env=e;$0.setOp(op,o)},checkpointing:false)})
    }
    func fmSlider(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,log:Bool=false,help:String="",format:@escaping(Double)->String={String(format:"%.0f%%",$0*100)})->some View{
        ParameterSlider(title:title,value:value,range:range,logarithmic:log,format:format,onBegin:{m.checkpoint()}).help(help.isEmpty ? title : help)
    }
    /// Engine toggle — lives above the panel content in BOTH modes so FM is always reachable.
    var enginePicker:some View{
        HStack(spacing:14){
            Picker("Engine",selection:Binding(get:{fmOn ? 1:0},set:{v in m.setFm({$0.enabled=v==1})})){
                Text("Subtractive").tag(0);Text("FM").tag(1)
            }.pickerStyle(.segmented).frame(width:180).accessibilityLabel("Engine mode Subtractive or FM")
            Spacer()
            Text(fmOn ? "Sub + noise + filters + Character stay live under FM" : "Switch to FM for 4-operator synthesis").font(.system(size:12)).foregroundStyle(palette.muted)
        }
    }
    @ViewBuilder func fmContent()->some View{
        VStack(alignment:.leading,spacing:12){
            // 16 visual algorithms — vector drawings in bounded canvases (spec §9)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:8),spacing:8){
                ForEach(0..<16,id:\.self){idx in FmAlgorithmCell(index:idx,selected:fm.algorithm==idx,select:{m.setFm({$0.algorithm=idx})})}
            }
            HStack(spacing:14){
                fmSlider("Feedback",fmBinding(\.feedback),0...1,help:"FM feedback amount into the algorithm's designated operator")
                fmSlider("Carrier mix",fmBinding(\.carrierMix),0...1,help:"FM carrier mix between the algorithm's carriers",format:{String(format:"%.0f%% A/B",$0*100)})
                fmSlider("Pitch env",fmBinding(\.pitchEnv.amount),-1...1,help:"FM pitch strike envelope amount in semitones",format:{String(format:"%.0f st",$0*12)})
                fmSlider("Strike time",fmBinding(\.pitchEnv.time),0.001...4,log:true,help:"FM pitch strike envelope decay time",format:{String(format:"%.0f ms",$0*1000)})
                fmSlider("Curve",fmBinding(\.pitchEnv.curve),0...1,help:"FM pitch strike envelope curve")
            }
            HStack(alignment:.top,spacing:10){ForEach(0..<4,id:\.self){FmOperatorColumn(index:$0,editor:self)}}
            HStack{slider("Sub",5);slider("Noise",6)}
        }
    }
    func fmOpColumn(_ i:Int)->some View { FmOperatorColumn(index:i,editor:self) }
    func fmOpColumnBody(_ i:Int)->some View {
        let op=fm.op(i)
        let meta=FmPatch.algorithmMeta[fm.algorithm]
        let fmWaves=["Sine","Tri","Saw","Pulse","Table"]
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:4){
                Text("Op \(i+1)").font(.system(size:13,weight:palette.weight(.medium)))
                Spacer()
                Text(meta.target[i]<0 ? "carrier":"mod→\(meta.target[i]+1)").font(.system(size:9)).foregroundStyle(palette.muted)
            }
            Picker("Wave",selection:fmOpBinding(i,\.wave)){
                ForEach(Array(fmWaves.enumerated()),id:\.offset){idx,n in Text(n).tag(idx)}
            }.labelsHidden().pickerStyle(.segmented).font(.system(size:11)).accessibilityLabel("Op \(i+1) wave").help("Operator \(i+1) waveform")
            fmSlider("Ratio",fmOpBinding(i,\.ratio),0.25...16,log:true,help:"Operator \(i+1) frequency ratio",format:ratioText)
            fmSlider("Level",fmOpBinding(i,\.level),0...1,help:"Operator \(i+1) level — modulator index or carrier amplitude")
            fmSlider("Velocity",fmOpBinding(i,\.vel),0...1,help:"Operator \(i+1) velocity sensitivity")
            FmEnvCurve(op:op).frame(height:42)
            DisclosureGroup("Envelope"){
                Picker("Mode",selection:fmOpBinding(i,\.envMode)){Text("Rate/Level").tag(0);Text("ADSR").tag(1)}
                    .pickerStyle(.segmented).font(.system(size:11)).accessibilityLabel("Op \(i+1) envelope mode")
                ForEach(0..<4,id:\.self){s in fmEnvRow(i,s)}
                Picker("Keys",selection:fmOpBinding(i,\.keyScale)){
                    ForEach(Array(["Off","Low","Even","Odd"].enumerated()),id:\.offset){idx,n in Text(n).tag(idx)}
                }.pickerStyle(.segmented).font(.system(size:11)).accessibilityLabel("Op \(i+1) key scale")
                HStack(spacing:8){
                    fmSlider("Fine",fmOpBinding(i,\.fine),-1...1,format:{String(format:"%.0f ¢",$0*100)})
                    if op.wave==3 {fmSlider("Width",fmOpBinding(i,\.pulseWidth),0.05...0.95,format:{String(format:"%.0f%%",$0*100)})}
                }
            }.font(.system(size:12))
            HStack(spacing:8){
                Toggle("Fixed",isOn:Binding(get:{fm.op(i).fixedMode>0},set:{v in m.setFm({var o=$0.op(i);o.fixedMode=v ? 1:0;$0.setOp(i,o)},checkpointing:false)}))
                    .toggleStyle(.checkbox).tint(palette.accent).font(.system(size:12)).accessibilityLabel("Op \(i+1) fixed frequency")
                if op.fixedMode>0 {
                    fmSlider("Freq",fmOpBinding(i,\.fixedHz),1...20000,log:true,format:fmFreqText)
                }
            }
            if op.wave==4 {
                fmSlider("Position",fmOpBinding(i,\.wtPos),0...1)
                fmSlider("Warp",fmOpBinding(i,\.wtWarp),0...1)
            }
        }.padding(8).background(palette.surface,in:RoundedRectangle(cornerRadius:8))
        .overlay(RoundedRectangle(cornerRadius:8).stroke(.white.opacity(0.06)))
        .accessibilityLabel("Operator \(i+1) column")
    }

    func fmEnvRow(_ i:Int,_ s:Int)->some View {
        HStack(spacing:6){
            fmSlider("R\(s+1)",fmEnvBinding(i,false,s),0.02...300,log:true,format:fmRateText)
            fmSlider("L\(s+1)",fmEnvBinding(i,true,s),0...1,format:fmLevelText)
        }
    }

    func optionButtons(_ label:String,_ parameter:Int,_ options:[String],offset:Int=0)->some View {
        HStack(spacing:8){
            Text(label).font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted).fixedSize()
            HStack(spacing:3){
                ForEach(Array(options.enumerated()),id:\.offset){index,name in
                    let usingTable=(parameter==1 && m.patch.layers[m.selectedLayer][44]>0.5)||(parameter==2 && m.patch.layers[m.selectedLayer][51]>0.5)
                    let selected = !usingTable && Int(m.patch.layers[m.selectedLayer][parameter])==index+offset
                    let shortName=["Triangle":"Tri","Square":"Sqr","Random":"Rnd","Amplitude":"Amp","Harmonic":"Harm"][name] ?? name
                    Button{m.checkpoint();m.set(m.selectedLayer,parameter,Double(index+offset))}label:{
                        Text(shortName).font(.system(size:12,weight:selected ? .bold:.regular)).lineLimit(1).frame(maxWidth:.infinity).frame(height:22).background(selected ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(selected ? palette.selectedText:Color.white).contentShape(Rectangle())
                    }.buttonStyle(AuroraFlatButtonStyle(selected:selected)).help(name).accessibilityLabel("\(label) \(name)").accessibilityAddTraits(selected ? [.isSelected]:[])
                }
            }
        }.frame(height:22).modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:m.selectedLayer,parameter:parameter)))
    }
    var layerOctave:Int {Int(floor(m.patch.layers[m.selectedLayer][15]/12))}
    func shiftOctave(_ delta:Int) {
        let octave=max(-3,min(3,layerOctave+delta))
        let residual=Int(m.patch.layers[m.selectedLayer][15])-12*layerOctave
        m.checkpoint();m.set(m.selectedLayer,15,Double(octave*12+residual))
    }
    var octaveControl:some View {
        HStack(spacing:8){
            Text("Octave").font(.system(size:15,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            Spacer()
            HStack(spacing:0){
                Button{shiftOctave(-1)}label:{Image(systemName:"chevron.left").frame(width:25,height:22).contentShape(Rectangle())}.disabled(layerOctave <= -3).accessibilityLabel("Layer octave down")
                Text(layerOctave > 0 ? "+\(layerOctave)":"\(layerOctave)").font(.system(size:15,weight:palette.weight(.medium))).monospacedDigit().frame(width:32).accessibilityLabel("Layer octave \(layerOctave)")
                Button{shiftOctave(1)}label:{Image(systemName:"chevron.right").frame(width:25,height:22).contentShape(Rectangle())}.disabled(layerOctave >= 3).accessibilityLabel("Layer octave up")
            }.buttonStyle(AuroraFlatButtonStyle()).background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:5))
        }.frame(height:22)
    }
    func slider(_ label:String,_ p:Int,_ range:ClosedRange<Double> = 0...1,log:Bool=false,format:@escaping(Double)->String={String(format:"%.0f%%",$0*100)})->some View {
        ParameterSlider(title:label,value:m.parameter(p),range:range,logarithmic:log,format:format,onBegin:{m.checkpoint()})
            .modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:m.selectedLayer,parameter:p)))
            .overlay(alignment:.bottom){
                if let destination=[7:0,15:1,14:2,13:3,3:4,21:5,17:6,30:7,60:16,61:17,71:18,74:19,63:20,8:21,34:22,4:23,5:24,6:25,37:26,38:27,40:28,93:29,94:30,95:31,96:32,72:33,75:34,76:35,20:36][p] {
                    let slots=m.modulationSlots(destination:destination)
                    if !slots.isEmpty{ModulationIndicator(telemetry:m.modulation,slots:slots).offset(y:3)}
                }
            }
    }
    func lfoPanel(_ o:Int)->some View {
        let base=81+o*6
        return Panel(title:"LFO \(o+1) · movement"){
            optionButtons("Shape",o==0 ? 19:33,["Sine","Triangle","Saw","Square","Random"])
            optionButtons("Destination",o==0 ? 18:31,["Cutoff","Pitch","Pan","Amplitude"])
            optionButtons("Clock",base,["Hz","Tempo"])
            if m.patch.layers[m.selectedLayer][base] > 0.5 {
                slider("Division",base+1,0...9,format:{["4 bars","2 bars","1 bar","1/2","1/4","1/8","1/16","1/32","1/8 dotted","1/8 triplet"][max(0,min(9,Int($0.rounded())))]})
            } else {slider("Rate",o==0 ? 16:29,0.03...20,log:true,format:{String(format:"%.2f Hz",$0)})}
            slider("Depth",o==0 ? 17:30)
            optionButtons("Mode",base+2,["Free-run","Retrigger"])
            DisclosureGroup("Phase · delay · fade"){
                slider("Phase",base+3,format:{String(format:"%.0f°",$0*360)})
                HStack{slider("Delay",base+4,0...8,format:timeText);slider("Fade in",base+5,0...8,format:timeText)}
            }.font(.system(size:13))
        }
    }
    func matrixLFOPanel(_ index:Int)->some View {
        let base=99+index*9
        return Panel(title:"LFO \(index+3) · movement"){
            optionButtons("Shape",base,["Sine","Triangle","Saw","Square","Random"])
            Text("Select destination on the Matrix").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            optionButtons("Clock",base+3,["Hz","Tempo"])
            if m.patch.layers[m.selectedLayer][base+3] > 0.5 {
                slider("Division",base+4,0...9,format:{["4 bars","2 bars","1 bar","1/2","1/4","1/8","1/16","1/32","1/8 dotted","1/8 triplet"][max(0,min(9,Int($0.rounded())))]})
            } else {slider("Rate",base+1,0.03...20,log:true,format:{String(format:"%.2f Hz",$0)})}
            slider("Depth",base+2)
            optionButtons("Mode",base+5,["Free-run","Retrigger"])
            DisclosureGroup("Phase · delay · fade"){
                slider("Phase",base+6,format:{String(format:"%.0f°",$0*360)})
                HStack{slider("Delay",base+7,0...8,format:timeText);slider("Fade in",base+8,0...8,format:timeText)}
            }.font(.system(size:13))
        }
    }
    func filter1Panel()->some View{
        Panel(title:"Filter 1"){
            optionButtons("Type",32,["Low-pass","High-pass","Band-pass","Notch"])
            optionButtons("Slope",79,["12 dB","24 dB"])
            slider("Cutoff",7,30...18000,log:true,format:{$0>=1000 ? String(format:"%.1f kHz",$0/1000):String(format:"%.0f Hz",$0)})
            slider("Resonance",8,0...0.9);slider("Envelope amount",20,-1...1)
            slider("Drive",21)
        }
    }
    func ampEnvPanel()->some View{
        Panel(title:"Amplitude envelope"){
            slider("Attack",9,0.001...8,log:true,format:timeText)
            slider("Decay",10,0.01...8,log:true,format:timeText)
            slider("Sustain",11)
            slider("Release",12,0.01...12,log:true,format:timeText)
        }
    }
    var body:some View {
        LazyVStack(alignment:.leading,spacing:16){
            HStack{Text("Layer \(layerLetters[m.selectedLayer]) · sound design").font(.system(size:21,weight:palette.weight(.medium)));Spacer();Text("Every control shapes the audio engine").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}
            VStack(alignment:.leading,spacing:16){
                if fmOn {
                    // FM gets its own full-width row — the 16-algorithm grid and four operator
                    // columns need the space; Filter 1 + Amp envelope pair up below.
                    Panel(title:"FM Engine · layer \(layerLetters[m.selectedLayer])"){
                        enginePicker
                        fmContent()
                    }
                    EqualHeightRow(spacing:16){
                        filter1Panel()
                        ampEnvPanel()
                    }
                } else {
                EqualHeightRow(spacing:16){
                Panel(title:"Oscillators"){
                    enginePicker
                    optionButtons("Oscillator 1",1,waves);optionButtons("Oscillator 2",2,waves)
                    slider("Oscillator blend",3);slider("Detune",4,0...30,format:{String(format:"%.1f cents",$0)})
                    HStack{slider("Sub",5);slider("Noise",6)}
                }
                filter1Panel()
                ampEnvPanel()
                }
                }
                EqualHeightRow(spacing:16){
                lfoPanel(0)
                lfoPanel(1)
                Panel(title:"Layer range & balance"){
                    octaveControl.modifier(MatrixFeedback(model:m,destination:1))
                    slider("Low key",27,0...127,format:{"MIDI \(Int($0))"})
                    slider("High key",28,0...127,format:{"MIDI \(Int($0))"})
                    slider("Pan",14,-1...1,format:{$0 == 0 ? "Center":String(format:"%.0f%% %@",abs($0)*100,$0<0 ? "L":"R")})
                }
                }
                EqualHeightRow(spacing:16){
                    matrixLFOPanel(0)
                    matrixLFOPanel(1)
                    matrixLFOPanel(2)
                }
            }
            EqualHeightRow(spacing:16){
                Panel(title:"Filter 2 · routing"){
                    optionButtons("Filter 2",58,["Bypass","On"])
                    optionButtons("Type",59,["Low-pass","High-pass","Band-pass","Notch"])
                    optionButtons("Slope",80,["12 dB","24 dB"])
                    slider("Cutoff",60,30...18000,log:true,format:{String(format:"%.0f Hz",$0)})
                    slider("Resonance",61,0...0.9)
                    optionButtons("Routing",62,["1 → 2","2 → 1","Parallel"])
                    slider("Parallel balance",63).disabled(m.patch.layers[m.selectedLayer][62] != 2)
                    Text("Serial combines the filters; Parallel blends their separate outputs.").font(.system(size:13)).foregroundStyle(palette.muted)
                }
                Panel(title:"Mod envelope"){
                    HStack{slider("Attack",64,0.001...8,log:true,format:timeText);slider("Decay",65,0.01...12,log:true,format:timeText)}
                    HStack{slider("Sustain",66);slider("Release",67,0.01...12,log:true,format:timeText)}
                    VStack(alignment:.leading,spacing:5){
                        Text("Destination").font(.system(size:14)).foregroundStyle(palette.muted)
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:4),spacing:4){ForEach(Array(["Filter 1","Filter 2","Pitch","Osc mod","Character","WT 1","WT 2"].enumerated()),id:\.offset){i,title in
                            Button(title){m.checkpoint();m.set(m.selectedLayer,69,Double(i))}.font(.system(size:12)).buttonStyle(AuroraButtonStyle(selected:Int(m.patch.layers[m.selectedLayer][69])==i))
                        }}
                    }
                    slider("Amount",68,-1...1)
                    Text("Independent per note. Also available as a source in Sound Matrix; follows Mono/Legato mode.").font(.system(size:13)).foregroundStyle(palette.muted)
                }
                Panel(title:"Character · layer insert"){
                    optionButtons("Mode",73,["Off","Warm","Clip","Fold","Crush"])
                    slider("Drive",74);slider("Tone",76);slider("Mix",75)
                    HStack{slider("Bits",77,4...16,format:{"\(Int($0)) bit"});slider("Sample rate",78,0.02...1,log:true)}.disabled(m.patch.layers[m.selectedLayer][73] != 4)
                    Text("After both filters, before layer balance and Delay/Reverb sends.").font(.system(size:13)).foregroundStyle(palette.muted)
                }
            }
            Panel(title:"Live waveform · output"){
                HStack{
                    Button("Auto scale"){scopeAutoScale=true}.buttonStyle(AuroraButtonStyle(selected:scopeAutoScale))
                    Button("Actual level"){scopeAutoScale=false}.buttonStyle(AuroraButtonStyle(selected:!scopeAutoScale))
                    Spacer();OutputLevelReadout(telemetry:m.telemetry)
                }
                OutputScope(telemetry:m.scope,normalized:scopeAutoScale).frame(height:160)
                HStack(spacing:24){
                    ParameterSlider(title:"Output boost",value:Binding(get:{m.outputGain},set:{m.setOutputGain($0)}),range:0...24,format:{String(format:"+%.1f dB",$0)}).frame(width:280)
                    Text("Left output waveform · stereo peak meter · boost stays constant across patches, with peak protection. Auto scale changes only the graph.").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
            }
            WavetableSection(m:m)
            MotionEnvelopePanel(m:m).id(m.selectedLayer)
            ArpEffectsView(m:m)
            EqualHeightRow(spacing:16){
                Panel(title:"Pulse & PWM"){
                    slider("Pulse width",34,0.05...0.95)
                    slider("PWM amount",35)
                    Text("Select Pulse on either oscillator. PWM follows LFO 1’s waveform and rate, independent of its Depth.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
                Panel(title:"Unison & stereo"){
                    optionButtons("Voices",36,["1","2","3","4","5","6","7","8"],offset:1)
                    Text("8-voice unison: up to 32 notes across layers").font(.system(size:12)).foregroundStyle(palette.muted)
                    slider("Unison detune",37,0...30,format:{String(format:"%.1f cents",$0)})
                    slider("Stereo spread",38)
                    Text("2–4 copies per note; levels are balanced automatically.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
                Panel(title:"Oscillator interaction"){
                    optionButtons("Modulation",70,["Off","Phase","FM","Ring"])
                    slider("Mod amount",71)
                    slider("Osc 2 ratio",72,0.25...8,log:true,format:{String(format:"%.2f×",$0)})
                    Toggle("Sync oscillator 2 to 1",isOn:Binding(get:{m.patch.layers[m.selectedLayer][39]>0.5},set:{m.checkpoint();m.set(m.selectedLayer,39,$0 ? 1:0)})).tint(palette.accent)
                    slider("Sync tuning",40,0...36,format:{String(format:"%.1f semitones",$0)})
                    Text("Oscillator 2 modulates oscillator 1. Lower Blend to hear the carrier alone. Works with classic and wavetable waves.").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
            }
            Panel(title:"Playing · layer \(layerLetters[m.selectedLayer])"){
                EqualHeightRow(spacing:24){
                    VStack(alignment:.leading,spacing:12){optionButtons("Mode",41,["Poly","Mono","Legato"]);Text("Last-note priority per keyboard/channel. Mono retriggers; Legato connects overlapping notes. Arpeggiator keeps its own gate.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}
                    VStack(alignment:.leading,spacing:12){slider("Glide",42,0...2,format:{$0==0 ? "Off":String(format:"%.0f ms",$0*1000)});Text("Pitch slides between overlapping mono or legato notes.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}
                    slider("Pitch-bend range",43,0...24,format:{"±\(Int($0)) semitones"})
                }
            }
        }
    }
    func timeText(_ x:Double)->String{x<1 ? String(format:"%.0f ms",x*1000):String(format:"%.2f s",x)}
}
struct ArpEffectsView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    func control(_ title:String,_ id:Int,_ range:ClosedRange<Double> = 0...1,_ format:@escaping(Double)->String={String(format:"%.0f%%",$0*100)})->some View {
        ParameterSlider(title:title,value:m.globalBinding(id),range:range,format:format,onBegin:{m.checkpoint()})
            .modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:-1,parameter:id)))
    }
    /// Header power switch for one shared return or master insert (AG*Power global).
    func power(_ parameter:Int,_ help:String)->AnyView {AnyView(FxPowerToggle(m:m,parameter:parameter,name:ControlTarget.globalNames[parameter],help:help))}
    func globalPicker(_ label:String,_ parameter:Int,_ options:[String])->some View {
        HStack(spacing:8){
            Text(label).font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted).fixedSize()
            HStack(spacing:3){
                ForEach(Array(options.enumerated()),id:\.offset){index,name in
                    let selected=Int(m.patch.globalValue(parameter).rounded())==index
                    Button{m.checkpoint();m.global(parameter,Double(index))}label:{
                        Text(name).font(.system(size:12,weight:selected ? .bold:.regular)).lineLimit(1).frame(maxWidth:.infinity).frame(height:22).background(selected ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(selected ? palette.selectedText:Color.white).contentShape(Rectangle())
                    }.buttonStyle(AuroraFlatButtonStyle(selected:selected)).help(name).accessibilityLabel("\(label) \(name)").accessibilityAddTraits(selected ? [.isSelected]:[])
                }
            }
        }.frame(height:22)
    }
    func divisionButtons()->some View {
        let options=["1/4","1/8","1/8T","1/16","1/16T","1/32"]
        return HStack(spacing:8){
            Text("Division").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted).fixedSize()
            HStack(spacing:3){
                ForEach(Array(options.enumerated()),id:\.offset){index,name in
                    let selected=Int(m.patch.layers[m.selectedLayer][23])==index
                    Button{m.checkpoint();m.set(m.selectedLayer,23,Double(index))}label:{
                        Text(name).font(.system(size:12,weight:selected ? .bold:.regular)).lineLimit(1).frame(maxWidth:.infinity).frame(height:22).background(selected ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(selected ? palette.selectedText:Color.white).contentShape(Rectangle())
                    }.buttonStyle(AuroraFlatButtonStyle(selected:selected)).help("Division \(name)").accessibilityLabel("Division \(name)").accessibilityAddTraits(selected ? [.isSelected]:[])
                }
            }
        }.frame(height:22).modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:m.selectedLayer,parameter:23)))
    }
    /// Matches ParameterSlider footprint: title row + control row, so it lines up with Mix/Pitch neighbors.
    func reverseButtons()->some View {
        let options=["Forward","Reverse"]
        return VStack(spacing:5){
            HStack{
                Text("Direction").foregroundStyle(palette.muted)
                Spacer()
                Text(" ").monospacedDigit().hidden()
            }.font(.system(size:15,weight:palette.weight(.regular)))
            HStack(spacing:3){
                ForEach(Array(options.enumerated()),id:\.offset){index,name in
                    let selected=Int(m.patch.globalValue(32))==index
                    Button{m.checkpoint();m.global(32,Double(index))}label:{
                        Text(name).font(.system(size:12,weight:selected ? .bold:.regular)).lineLimit(1).frame(maxWidth:.infinity).frame(maxHeight:.infinity).background(selected ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(selected ? palette.selectedText:Color.white).contentShape(Rectangle())
                    }.buttonStyle(AuroraFlatButtonStyle(selected:selected)).help(name).accessibilityLabel(name).accessibilityAddTraits(selected ? [.isSelected]:[])
                }
            }
            .frame(maxWidth:.infinity)
            .frame(height:20)
        }.modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:-1,parameter:32)))
    }
    func delaySyncButtons()->some View {
        let options=["Free","Tempo"]
        return HStack(spacing:8){
            Text("Sync").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted).fixedSize()
            HStack(spacing:3){
                ForEach(Array(options.enumerated()),id:\.offset){index,name in
                    let selected=Int(m.patch.globalValue(16))==index
                    Button{m.checkpoint();m.global(16,Double(index))}label:{
                        Text(name).font(.system(size:12,weight:selected ? .bold:.regular)).lineLimit(1).frame(maxWidth:.infinity).frame(height:22).background(selected ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(selected ? palette.selectedText:Color.white).contentShape(Rectangle())
                    }.buttonStyle(AuroraFlatButtonStyle(selected:selected)).help(name).accessibilityLabel("Sync \(name)").accessibilityAddTraits(selected ? [.isSelected]:[])
                }
            }
        }.frame(height:22).modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:-1,parameter:16)))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            // Row 1 — Arpeggiator (1/3) | Shimmer (2/3), height from Shimmer
            WeightedHeightRow(spacing:16,weights:[1,2],heightSource:1){
                Panel(title:"Arpeggiator"){
                    Toggle("Enabled",isOn:Binding(get:{m.patch.layers[m.selectedLayer][22] > 0.5},set:{m.checkpoint();m.set(m.selectedLayer,22,$0 ? 1:0)}))
                    Picker("Pattern",selection:Binding(get:{Int(m.patch.layers[m.selectedLayer][24])},set:{m.checkpoint();m.set(m.selectedLayer,24,Double($0))})){
                        ForEach(Array([
                            "Up","Down","Up/Down","Random",
                            "As played","As played ↑↓","Chord stab","Outside-in","Inside-out",
                            "Pinky walk","Thumb walk","Octave hop","Fifth leap","Converge","Diverge",
                            "Brownian","Skip 2","Pairwise","Hex rotate","Blue notes favor","Pendulum 3 over 2",
                            "Repeat ×2","Repeat ×3","First + climb","Last + fall","Bass drone + up","Bass drone + down",
                            "Melody hold + arp below","Spread walk"
                        ].enumerated()),id:\.offset){i,name in Text(name).tag(i)}
                    }
                    divisionButtons()
                    Stepper("Octaves: \(Int(m.patch.layers[m.selectedLayer][25]))",value:Binding(get:{Int(m.patch.layers[m.selectedLayer][25])},set:{m.set(m.selectedLayer,25,Double($0))}),in:1...4)
                    ParameterSlider(title:"Gate",value:m.parameter(26),range:0.1...0.95)
                    ParameterSlider(title:"Swing",value:m.parameter(97),range:0...1)
                    Picker("Velocity shape",selection:Binding(get:{Int(m.patch.layers[m.selectedLayer][98])},set:{m.checkpoint();m.set(m.selectedLayer,98,Double($0))})){
                        ForEach(Array(["Off","Accent 1st","Accent every 2","Ramp up","Ramp down"].enumerated()),id:\.offset){i,name in Text(name).tag(i)}
                    }
                    Toggle("Latch",isOn:Binding(get:{m.holding},set:{m.setHold($0)}))
                        .tint(palette.accent)
                        .help("Keeps the chord/arp running after you lift keys (same as Hold). Panic or Latch off clears.")
                    Text("Latch uses the global Hold — Panic or Latch off clears held arp notes.")
                        .font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }.font(.system(size:15,weight:palette.weight(.regular)))
                Panel(title:"Shimmer",accessory:power(60,"Take the shimmer return out of the shared bus. Mix, pitch and decay stay in the patch.")){
                    VStack(alignment:.leading,spacing:10){
                        HStack(alignment:.center,spacing:12){
                            control("Mix",23)
                            control("Pitch",24,-12...24,{String(format:"%+.0f st",$0)})
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Decay",25,0.2...12,{String(format:"%.1f s",$0)})
                            control("Tone",26)
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Pre-delay",27,0...200,{String(format:"%.0f ms",$0)})
                            control("Amount",28,0...0.95)
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Voice +5",29)
                            control("Voice +7",30)
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Voice +12",31)
                            reverseButtons()
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Early level",33)
                            control("Early size",34)
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Late level",35)
                            control("Late decay",36,0.2...12,{String(format:"%.1f s",$0)})
                        }
                        HStack(alignment:.center,spacing:12){
                            VStack(alignment:.leading,spacing:4){
                                ParameterSlider(title:"Shimmer send",value:m.sendBinding(.shimmer),onBegin:{m.checkpoint()})
                                Text("Layer send into shared shimmer return.")
                                    .font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Button{m.setShimmerBypass(!(m.patch.sends?[m.selectedLayer].shimmerBypass ?? false))}label:{
                                Text("Bypass").frame(maxWidth:.infinity)
                            }
                            .buttonStyle(AuroraButtonStyle(selected:m.patch.sends?[m.selectedLayer].shimmerBypass ?? false))
                            .frame(maxWidth:.infinity)
                            .accessibilityLabel("Bypass shimmer for this layer")
                            .help("This layer does not feed Shimmer. The send level stays stored in the patch.")
                        }
                        Text("Pitch-shifted multi-voice diffusion · +5 / +7 / +12 relative to Pitch.")
                            .font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                    }
                }
            }

            // Row 2 — Delay | Compressor
            EqualHeightRow(spacing:16){
                Panel(title:"Delay",accessory:power(61,"Take the shared delay return out of the bus and stop its repeats regenerating.")){
                    VStack(alignment:.leading,spacing:10){
                        delaySyncButtons()
                        HStack(alignment:.center,spacing:12){
                            if m.patch.globalValue(16) >= 0.5 {
                                Picker("Timing",selection:Binding(get:{Int(m.patch.globalValue(14))},set:{m.checkpoint();m.global(14,Double($0))})){
                                    ForEach(Array(["1/4","1/8","1/16","1/2","1/8 dotted","1/4 dotted","1/8 triplet","1/4 triplet"].enumerated()),id:\.offset){i,name in Text(name).tag(i)}
                                }
                            } else {
                                control("Time",17,1...2000,{String(format:"%.0f ms",$0)})
                            }
                            ParameterSlider(title:"Mix",value:m.globalBinding(2),range:0...0.6).modifier(MatrixFeedback(model:m,destination:11))
                        }
                        HStack(alignment:.center,spacing:12){
                            ParameterSlider(title:"Feedback",value:m.globalBinding(3),range:0...0.75)
                            control("Ping-pong",18)
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Tone",19)
                            control("Duck",48,0...1,{String(format:"%.0f%%",$0*100)})
                        }
                        HStack(alignment:.center,spacing:12){
                            control("Duck release",49,0...1,{String(format:"%.0f ms",$0*1500)})
                            ParameterSlider(title:"Delay send",value:m.sendBinding(.delay),onBegin:{m.checkpoint()})
                        }
                        Text("Layer send into shared delay return.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                    }
                }
                Panel(title:"Compressor",accessory:power(69,"Take the master compressor out of the chain. Gain reduction falls back to 0 dB.")){
                    control("Threshold",50,-60...0,{String(format:"%.0f dB",$0)})
                    control("Ratio",51,1...12,{String(format:"%.1f:1",$0)})
                    HStack(alignment:.center,spacing:12){
                        control("Attack",52,0.1...100,{String(format:"%.1f ms",$0)})
                        control("Release",53,5...1000,{String(format:"%.0f ms",$0)})
                    }
                    HStack(alignment:.center,spacing:12){
                        control("Makeup",54,0...18,{String(format:"%.1f dB",$0)})
                        globalPicker("Auto",55,["Off","On"])
                    }
                    CompGRMeter(telemetry:m.compGR)
                    Text("Master glue before the limiter · Threshold 0 dB = off.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
            }

            // Row 3 — Chorus | Phaser | Reverb
            EqualHeightRow(spacing:16){
                Panel(title:"Chorus",accessory:power(63,"Take the shared chorus out of the bus. Rate and depth stay in the patch.")){
                    ParameterSlider(title:"Mix",value:m.globalBinding(5),range:0...0.6).modifier(MatrixFeedback(model:m,destination:8))
                    control("Rate",10,0.03...5,{String(format:"%.2f Hz",$0)})
                    control("Depth",11)
                }
                Panel(title:"Phaser",accessory:power(64,"Take the master phaser out of the chain. Its all-pass state is cleared while bypassed.")){
                    ParameterSlider(title:"Mix",value:m.globalBinding(6),onBegin:{m.checkpoint()}).modifier(MatrixFeedback(model:m,destination:9))
                    control("Rate",7,0.03...5,{String(format:"%.2f Hz",$0)})
                    control("Depth",8)
                    control("Feedback",9,-0.85...0.85)
                }
                Panel(title:"Reverb",accessory:power(62,"Take the shared room out of the bus. Size and decay stay in the patch.")){
                    ParameterSlider(title:"Mix",value:m.globalBinding(4),range:0...0.75).modifier(MatrixFeedback(model:m,destination:10))
                    control("Size",12)
                    control("Decay",13,0.2...8,{String(format:"%.1f s",$0)})
                    ParameterSlider(title:"Reverb send",value:m.sendBinding(.reverb),onBegin:{m.checkpoint()})
                    Text("Layer send into shared room.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
            }

            // Row 4 — Flanger | Tremolo | Bitcrusher | Auto-wah
            EqualHeightRow(spacing:16){
                Panel(title:"Flanger",accessory:power(65,"Take the flanger comb out of the master chain.")){
                    control("Mix",37,0...0.8)
                    control("Rate",38,0.03...5,{String(format:"%.2f Hz",$0)})
                    control("Depth",39)
                    control("Feedback",40,0...0.9)
                    Text("Short modulated comb · the classic jet swoosh.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
                Panel(title:"Tremolo",accessory:power(66,"Take the tremolo/pan/rotary stage out of the chain. Bypass restores unity gain.")){
                    control("Mix",41,0...0.8)
                    control("Rate",42,0.03...8,{String(format:"%.1f Hz",$0)})
                    control("Depth",43)
                    globalPicker("Mode",44,["Tremolo","Pan","Rotary"])
                    Text("Tremolo = amp wobble · Pan = left/right sweep · Rotary = spinning speaker.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
                Panel(title:"Bitcrusher",accessory:power(67,"Take the bitcrusher out of the chain.")){
                    control("Mix",45,0...1)
                    control("Bits",46,1...16,{String(format:"%.0f bit",$0)})
                    control("Downsample",47,1...64,{String(format:"%dx",Int($0))})
                    Text("Lo-fi grit · Downsample 1x = clean.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
                Panel(title:"Auto-wah",accessory:power(68,"Take the envelope filter out of the chain.")){
                    control("Mix",56,0...1)
                    control("Sensitivity",57)
                    control("Range",58)
                    globalPicker("Filter",59,["Low-pass","Band-pass"])
                    Text("Envelope filter that follows your playing.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                }
            }

        }
    }
}
struct MatrixView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    private let soundSources:[(id:Int,name:String)]=[(0,"LFO 1"),(1,"LFO 2"),(6,"LFO 3"),(7,"LFO 4"),(8,"LFO 5"),(2,"Amp envelope"),(3,"Mod envelope"),(4,"Key tracking"),(5,"Per-note random"),(9,"Velocity"),(10,"Channel pressure")]
    private let performanceSources=["Mod wheel","Velocity","Channel pressure","Expression","Sustain","MIDI CC"]
    private let destinations=["Cutoff","Pitch","Pan","Amplitude","Oscillator blend","Drive","LFO 1 depth","LFO 2 depth","Chorus","Phaser","Reverb","Delay mix","WT 1 position","WT 2 position","WT 1 warp","WT 2 warp","Filter 2 cutoff","Filter 2 resonance","Osc modulation","Character drive","Filter balance","Filter 1 resonance","Pulse width","Detune","Sub level","Noise level","Unison detune","Stereo spread","Sync tune","WT 1 formant","WT 1 tone","WT 2 formant","WT 2 tone","Osc mod ratio","Character mix","Character tone","Filter envelope","Op 1 level","Op 2 level","Op 3 level","Op 4 level","FM feedback","FM carrier mix","Pitch envelope","FM ratio fine","WT mod position","WT mod warp"]
    func binding<T>(_ performance:Bool,_ slot:Int,_ key:WritableKeyPath<MatrixAssignment,T>)->Binding<T> {
        Binding(get:{m.matrixRows(performance:performance)[slot][keyPath:key]},set:{value in m.checkpoint();m.updateMatrix(performance:performance,slot:slot){$0[keyPath:key]=value}})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Panel(title:"Sound Matrix · layer \(layerLetters[m.selectedLayer])"){
                Text("Route an LFO or envelope to a sound control. LFO 3, 4 and 5 get their destination here. LFO 1 and 2 also keep the destination on their own panels. Depth on LFO 3–5 scales every Matrix route from that LFO.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                ForEach(0..<10){row in routeRow(false,row)}
            }
            Panel(title:"Performance Matrix · this patch"){
                Text("Use your wheels, playing dynamics, pedals, or any MIDI CC. Layer routes follow each note’s keyboard and channel. Shared FX follow the latest received source value across keyboards.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                ForEach(0..<10){row in routeRow(true,row)}
            }
            Text("Amount is an offset: ±100% gives up to 4 octaves of cutoff movement, 12 semitones of pitch, or the full normalized range of other destinations. Multiple slots add together; the final value is bounded. Existing wheel vibrato, expression, sustain, and MIDI Learn remain active.").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
        }
    }
    func routeRow(_ performance:Bool,_ slot:Int)->some View {
        let row=m.matrixRows(performance:performance)[slot]
        return HStack(spacing:10){
            Toggle("Slot \(slot+1)",isOn:binding(performance,slot,\.enabled)).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("\(performance ? "Performance":"Sound") slot \(slot+1) enabled")
            Text("\(slot+1)").foregroundStyle(palette.muted).monospacedDigit().lineLimit(1).frame(width:22,alignment:.leading)
            Picker("Source",selection:binding(performance,slot,\.source)){
                if performance {
                    ForEach(Array(performanceSources.enumerated()),id:\.offset){i,name in Text(name).tag(i)}
                } else {
                    ForEach(soundSources,id:\.id){item in Text(item.name).tag(item.id)}
                }
            }.labelsHidden().frame(width:140).accessibilityLabel("Slot \(slot+1) source")
            if performance && row.source==5 {
                HStack(spacing:3){Text("CC").foregroundStyle(palette.muted);TextField("CC number",value:binding(performance,slot,\.cc),format:.number).textFieldStyle(.roundedBorder).frame(width:36)}
            }
            Image(systemName:"arrow.right").foregroundStyle(palette.muted)
            Picker("Destination",selection:binding(performance,slot,\.destination)){
                ForEach(performance ? Array(0..<21):Array(0..<8)+Array(12..<destinations.count),id:\.self){i in Text(destinations[i]).tag(i)}
            }.labelsHidden().frame(width:150).accessibilityLabel("Slot \(slot+1) destination")
            if performance {
                if (8...11).contains(row.destination){Text("Whole patch").foregroundStyle(palette.accent).frame(width:100)}else{
                    Picker("Target",selection:binding(true,slot,\.target)){Text("All layers").tag(4);ForEach(0..<4){i in Text("Layer \(layerLetters[i])").tag(i)}}.labelsHidden().frame(width:100)
                }
            }
            Slider(value:Binding(get:{m.matrixRows(performance:performance)[slot].amount},set:{value in m.updateMatrix(performance:performance,slot:slot){$0.amount=value}}),in:-1...1,onEditingChanged:{if $0{m.checkpoint()}}).tint(palette.accent).frame(minWidth:70).accessibilityLabel("Slot \(slot+1) amount")
            VStack(spacing:3){
                Text(String(format:"%+.0f%%",row.amount*100)).monospacedDigit()
                ModulationIndicator(telemetry:m.modulation,slots:[(performance ? 40:m.selectedLayer*10)+slot])
            }.frame(width:58,alignment:.trailing)
            Button{m.checkpoint();m.updateMatrix(performance:performance,slot:slot){$0=MatrixAssignment()}}label:{Image(systemName:"arrow.counterclockwise")}.buttonStyle(AuroraIconButtonStyle()).help("Reset slot \(slot+1)")
        }.font(.system(size:14,weight:palette.weight(.regular))).padding(.vertical,5).opacity(row.enabled ? 1:0.65)
    }
}
struct RoutingView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Your keyboards").font(.system(size:22,weight:palette.weight(.medium)));Spacer();Button("Refresh",systemImage:"arrow.clockwise"){m.refresh()}}
            Text("Choose the layers each MIDI source plays. MIDI inputs and the audio output are independent.").foregroundStyle(palette.muted).font(.system(size:15,weight:palette.weight(.regular)))
            if m.sources.isEmpty {Panel(title:"No MIDI sources detected"){Text("Connect a keyboard by USB, then Refresh. The on-screen keyboard still works.").foregroundStyle(palette.muted);Text("Yamaha keyboards use USB TO HOST and the Yamaha Steinberg USB Driver.").font(.system(size:15,weight:palette.weight(.regular)))}}
            ForEach(m.sources){source in sourceRow(source)}
            if m.backend.isPlugin {Panel(title:"DAW connection"){
                Text("Your DAW supplies MIDI, audio output, buffer size, and tempo. Aurora’s MIDI Learn assignments save with this project and work with the editor closed. You can also use your DAW’s automation and MIDI mapping. Record and bounce from the instrument track.").foregroundStyle(palette.muted)
            }} else {Panel(title:"Audio output"){
                Text(m.running ? "Audio is enabled. Changing the output stops playback until you enable audio again.":"Audio is stopped. Choose the output connected to your headphones or speakers.").font(.system(size:15,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                HStack{Picker("Output",selection:Binding(get:{m.output},set:{m.changeOutput($0)})){Text("System default").tag(UInt32(0));ForEach(m.devices){Text($0.name).tag($0.id)}}
                    Picker("Buffer",selection:$m.buffer){ForEach([64,128,256,512],id:\.self){Text("\($0) frames").tag($0)}}.frame(width:220).disabled(m.running)}
                Text("The output's actual sample rate is used. CK88 and MODX7+ USB audio use 44.1 kHz.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            }
            Panel(title:"Oxygen Pro 25 · MIDI Learn"){
                Text("Use Preset mode and the musical USB MIDI port. Click MIDI Learn below any macro, then move one of your eight knobs. Cross the macro's current position to take control without a jump.").font(.system(size:15,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                if m.mappings.isEmpty{Text("No knobs mapped yet.").font(.system(size:15,weight:palette.weight(.regular)))}
                ForEach(m.mappings,id:\.macro){mapping in HStack{Text(m.macroNames[mapping.macro]);Spacer();Text("CC \(mapping.controller) · ch \(mapping.channel)").foregroundStyle(palette.muted);Button("Remove"){m.mappings.removeAll{$0.macro==mapping.macro};m.persist()}}.font(.system(size:15,weight:palette.weight(.regular)))}
            }
            }
        }
    }
    func sourceRow(_ source:MIDISource)->some View {
        let route=m.routes[source.id] ?? SourceRoute(mask:1,channel:0)
        return Panel(title:source.name){
            HStack{
                ForEach(0..<4){i in Button{var r=route;r.mask ^= (1<<i);m.setRoute(source.id,r)}label:{Text("Layer \(layerLetters[i])").frame(maxWidth:.infinity).padding(.vertical,7).background(route.mask&(1<<i) != 0 ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:6)).foregroundStyle(route.mask&(1<<i) != 0 ? palette.selectedText:Color.white)}.buttonStyle(AuroraFlatButtonStyle(selected:route.mask&(1<<i) != 0))}
                Picker("Channel",selection:Binding(get:{route.channel},set:{var r=route;r.channel=$0;m.setRoute(source.id,r)})){Text("All").tag(0);ForEach(1...16,id:\.self){Text("\($0)").tag($0)}}.frame(width:160)
            }
            Picker("Velocity curve",selection:Binding(get:{route.velocityCurve ?? 0},set:{var r=route;r.velocityCurve=$0;m.setRoute(source.id,r)})){
                Text("Linear").tag(0);Text("Soft touch").tag(1);Text("Hard touch").tag(2);Text("Fixed · 100").tag(3)
            }.frame(maxWidth:380).help("Soft touch makes lighter playing louder; Hard touch gives more quiet range. Saved for this MIDI input.")
            HStack{Text(route.mask==0 ? "Input disabled":"Assigned to "+(0..<4).filter{route.mask&(1<<$0) != 0}.map{layerLetters[$0]}.joined(separator:" + "));Spacer();Text("\(source.events ?? 0) MIDI events")}.font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
        }
    }
}

struct PerformanceTools:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @ObservedObject var telemetry:PerformanceTelemetry
    var body:some View{
        VStack(alignment:.leading,spacing:8){
            HStack(spacing:18){
                Button("Hold"){m.setHold(!m.holding)}.buttonStyle(AuroraButtonStyle(selected:m.holding)).accessibilityAddTraits(m.holding ? .isSelected:[]).disabled(!m.running).help("Hold released notes and arpeggios until Hold is turned off or Panic is pressed.")
                if m.backend.isPlugin {Text("DAW tempo · Record and bounce in your DAW").foregroundStyle(palette.muted);Spacer()} else {
                Picker("Clock",selection:Binding(get:{m.externalClock ? m.clockSourceID:0},set:{m.setClock($0 != 0,source:$0)})){
                    Text("Internal").tag(Int32(0));ForEach(m.sources){Text($0.name).tag($0.id)}
                }.frame(maxWidth:360)
                if m.externalClock{Text(telemetry.clockBPM>0 ? "Synced":"Waiting / stopped").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}
                Spacer(minLength:0)
                Button(m.recording ? "Stop recording":"Record",systemImage:m.recording ? "stop.circle.fill":"record.circle"){m.toggleRecording()}.buttonStyle(AuroraButtonStyle(selected:m.recording)).disabled(m.normalizingRecording || (!m.running && !m.recording))
                if m.recording{Text(String(format:"%02d:%02d",telemetry.seconds/60,telemetry.seconds%60)).monospacedDigit().frame(width:48)}
                if let url=m.recordingURL,!m.recording,!m.normalizingRecording{Button("Show WAV"){NSWorkspace.shared.activateFileViewerSelecting([url])}}
                }
            }
            if !m.recordingMessage.isEmpty{Text(m.recordingMessage).font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}
        }.padding(12).background(palette.surface,in:RoundedRectangle(cornerRadius:10))
    }
}
struct CategoryWrap:Layout {
    var spacing:CGFloat=8
    func positions(_ subviews:Subviews,_ width:CGFloat)->(points:[CGPoint],height:CGFloat){
        var points:[CGPoint]=[],x:CGFloat=0,y:CGFloat=0,rowHeight:CGFloat=0
        for view in subviews{
            let size=view.sizeThatFits(.unspecified)
            if x>0 && x+size.width>width{y+=rowHeight+spacing;x=0;rowHeight=0}
            points.append(CGPoint(x:x,y:y));x+=size.width+spacing;rowHeight=max(rowHeight,size.height)
        }
        return(points,y+rowHeight)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize{let width=proposal.width ?? 900;return CGSize(width:width,height:positions(subviews,width).height)}
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()){
        for (i,point) in positions(subviews,bounds.width).points.enumerated(){subviews[i].place(at:CGPoint(x:bounds.minX+point.x,y:bounds.minY+point.y),proposal:.unspecified)}
    }
}
struct PerformanceSetRack: View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m: SynthModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Set").font(.system(size: 14, weight: palette.weight(.medium))).foregroundStyle(palette.muted)
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { page in
                        SetChromeButton(
                            title: "\(page + 1)",
                            subtitle: nil,
                            active: m.setPage == page,
                            filled: true,
                            missing: false,
                            compact: true
                        ) { m.setSetPage(page) }
                        .accessibilityLabel("Set page \(page + 1)")
                        .accessibilityAddTraits(m.setPage == page ? .isSelected : [])
                        .help("Set page \(page + 1) · 16 pads")
                    }
                }
                Toggle(isOn: Binding(get: { m.setCutOnSwitch }, set: { m.setSetCutOnSwitch($0) })) {
                    Text("Cut on switch")
                        .font(.system(size: 12, weight: palette.weight(.regular)))
                }
                .toggleStyle(.checkbox)
                .foregroundStyle(palette.muted)
                .help("When on, pad changes Panic-cut like a hard preset load. When off, held notes and FX can finish.")
                Text("Tap to load · right-click to assign or clear")
                    .font(.system(size: 12, weight: palette.weight(.regular))).foregroundStyle(palette.muted)
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                ForEach(0..<16, id: \.self) { index in
                    SetPadButton(m: m, index: index)
                }
            }
        }
        .padding(12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Shared chrome for Set page buttons and the 16 pads — same fill, stroke, and bold-on-active text.
struct SetChromeButton: View {
    @Environment(\.auroraPalette) private var palette
    let title: String
    let subtitle: String?
    let active: Bool
    let filled: Bool
    let missing: Bool
    /// Page chips stay compact (layer A–D width); pads use the original wide row size.
    var compact: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if let subtitle {
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.system(size: compact ? 17 : 18, weight: active ? .bold : .semibold))
                            .monospacedDigit()
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    Text(title)
                        .font(.system(size: compact ? 17 : 18, weight: active ? .bold : .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? palette.selectedText : (filled ? Color.white : palette.muted))
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(width: compact ? 32 : nil, height: compact ? 40 : 52)
            .background(
                active ? palette.buttonSelected : (filled ? palette.buttonSurface : palette.buttonSurface.opacity(0.45)),
                in: RoundedRectangle(cornerRadius: compact ? 5 : 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 5 : 7)
                    .stroke(
                        missing ? Color.orange.opacity(0.9) :
                        (active ? palette.accent : palette.graphCyan.opacity(filled ? 0.35 : 0.18)),
                        lineWidth: active || missing ? 1.4 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 5 : 7))
        }
        .buttonStyle(AuroraFlatButtonStyle())
        .frame(width: compact ? 32 : nil)
    }
}

struct SetPadButton: View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m: SynthModel
    let index: Int
    private var slot: SetSlot { m.setSlots[m.setPage][index] }
    private var filled: Bool { !slot.isEmpty }
    private var active: Bool {
        guard filled, slot.patchId == m.patch.id else { return false }
        if let t = slot.tempo { return abs(m.patch.globals[1] - t) < 0.51 }
        return true
    }
    private var missing: Bool { filled && m.presetForSetSlot(slot) == nil }
    var body: some View {
        SetChromeButton(
            title: "\(index + 1)",
            subtitle: filled ? String((slot.name ?? "—").prefix(7)) : "·",
            active: active,
            filled: filled,
            missing: missing
        ) { m.recallSetSlot(index) }
        .help(helpText)
        .accessibilityLabel(accessibility)
        .contextMenu {
            Button("Assign current patch") { m.assignSetSlot(index) }
            Button("Assign current patch + tempo") { m.assignSetSlot(index, withTempo: true) }
            Divider()
            Button("Set pad tempo to current") { m.setSetSlotTempo(index) }.disabled(!filled)
            Button("Clear pad tempo") { m.clearSetSlotTempo(index) }.disabled(!filled || slot.tempo == nil)
            Divider()
            Button("Clear", role: .destructive) { m.clearSetSlot(index) }.disabled(!filled)
        }
    }
    private var helpText: String {
        if !filled { return "Pad \(index + 1) empty · right-click to assign \(m.patch.name)" }
        if missing { return "Pad \(index + 1): missing patch \(slot.name ?? "")" }
        if let t = slot.tempo {
            return "Pad \(index + 1): \(slot.name ?? "") · \(Int(t)) BPM (pad overrides patch)"
        }
        return "Pad \(index + 1): \(slot.name ?? "") · patch tempo"
    }
    private var accessibility: String {
        if !filled { return "Empty set pad \(index + 1)" }
        let tempoBit = slot.tempo.map { ", \(Int($0)) BPM override" } ?? ""
        return "Set pad \(index + 1), \(slot.name ?? "patch")\(tempoBit)\(active ? ", selected" : "")"
    }
}

@MainActor final class PatchBrowserState:ObservableObject {
    @Published var visible=false
    @Published var category:String?=nil
    @Published var userSavedOnly=false
    @Published var headerWidth:CGFloat=0
    @Published var trailingWidth:CGFloat=0
    /// P1: top-row tracking lives here (browser-local) instead of SynthModel, so a row
    /// crossing no longer invalidates the whole app; mirrored back to the model debounced.
    @Published var row=0
    var mirrorRow:((Int)->Void)?=nil
    private var mirrorGeneration=0
    func setRow(_ value:Int,immediate:Bool=false) {
        row=value
        mirrorGeneration+=1
        if immediate { mirrorRow?(value); return }
        let generation=mirrorGeneration
        Task{[weak self] in
            try? await Task.sleep(nanoseconds:600_000_000)
            guard let self,self.mirrorGeneration==generation else{return}
            self.mirrorRow?(self.row)
        }
    }
    /// P2: memoized filter+sort cache keyed on every input of `PatchBrowser.sounds`.
    var soundsCache:(PatchBrowserSoundsKey,[SoundPreset])?=nil
}
struct PatchBrowserSoundsKey:Equatable {
    var userOnly:Bool
    var category:String?
    var favoritesOnly:Bool
    var favorites:Set<String>
    var userFingerprint:String
    var query:String
}
struct UserPatchBadge:View {
    @Environment(\.auroraPalette) private var palette
    var body:some View {
        Image(systemName:"flag.fill").font(.system(size:11,weight:.semibold))
            .foregroundStyle(Color.white).frame(width:24,height:24)
            .background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:4))
            .overlay(RoundedRectangle(cornerRadius:4).stroke(palette.accent.opacity(0.8),lineWidth:1))
            .fixedSize().accessibilityLabel("User-created patch").help("User-created patch")
    }
}
struct AuroraEllipsisLabel:View {
    var body:some View {
        Image(systemName:"ellipsis").font(.system(size:15,weight:.bold)).foregroundStyle(Color.white).frame(width:24,height:24).contentShape(Rectangle())
    }
}
struct UserPatchMenu:View {
    let name:String
    let rename:()->Void
    let deletePatch:()->Void
    var body:some View {
        Menu{Button("Rename / category…",action:rename);Button("Delete",role:.destructive,action:deletePatch)}label:{
            AuroraEllipsisLabel()
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Manage \(name)").help("Rename or delete \(name)")
    }
}
struct PatchBrowserCard:View {
    @Environment(\.auroraPalette) private var palette
    let patch:SoundPreset
    let selected:Bool
    let userSound:Bool
    let favorite:Bool
    let toggleFavorite:()->Void
    let rename:()->Void
    let deletePatch:()->Void
    let select:()->Void
    var body:some View{
        Button(action:select){
            VStack(alignment:.leading,spacing:9){
                HStack(alignment:.top,spacing:8){
                    Text(patch.name).font(.system(size:17,weight:palette.weight(.semibold))).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                    if selected{Image(systemName:"checkmark.circle.fill").foregroundStyle(palette.accent)}
                }
                Spacer(minLength:0)
                HStack{
                    Text(patch.category).font(.system(size:13,weight:palette.weight(.medium))).foregroundStyle(selected ? palette.accent:palette.muted).lineLimit(1)
                    Spacer()
                    Color.clear.frame(width:userSound ? 89:25,height:24)
                }
            }.padding(15).frame(height:104).frame(maxWidth:.infinity,alignment:.leading)
                .background(selected ? palette.buttonSurface:palette.buttonSurface.opacity(0.4),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? palette.buttonSelected:palette.graphCyan.opacity(0.25),lineWidth:selected ? 1.5:1))
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(AuroraFlatButtonStyle()).help(patch.name+" · "+patch.detail).accessibilityLabel("Load patch \(patch.name)").accessibilityAddTraits(selected ? .isSelected:[])
        .overlay(alignment:.bottomTrailing){
            HStack(spacing:8){
                if userSound{
                    UserPatchBadge().allowsHitTesting(false)
                    UserPatchMenu(name:patch.name,rename:rename,deletePatch:deletePatch)
                }
                Button(action:toggleFavorite){Image(systemName:favorite ? "star.fill":"star").foregroundStyle(favorite ? palette.accent:Color.white).frame(width:32,height:32).background(palette.surface,in:RoundedRectangle(cornerRadius:6))}.buttonStyle(AuroraFlatButtonStyle()).accessibilityLabel("\(favorite ? "Unfavorite":"Favorite") \(patch.name)")
            }.padding(8)
        }
    }
}
private struct PatchScrollYKey:PreferenceKey {
    static var defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=nextValue()}
}
struct PatchBrowser:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    let close:()->Void
    @StateObject private var state=PatchBrowserState()
    var category:String?{get{m.patchBrowserCategory} nonmutating set{m.patchBrowserCategory=newValue}}
    var sounds:[SoundPreset]{
        let query=m.search.trimmingCharacters(in:.whitespacesAndNewlines)
        let key=PatchBrowserSoundsKey(userOnly:m.patchBrowserUserOnly,category:category,favoritesOnly:m.favoritesOnly,favorites:m.favorites,
            userFingerprint:m.userPresets.map{$0.id+"|"+$0.name+"|"+$0.category+"|"+$0.detail}.joined(separator:";"),query:query)
        if let cached=state.soundsCache,cached.0==key{return cached.1}
        let list=(key.userOnly ? m.userPresets:m.userPresets+FactoryBank.all).filter{
            (category==nil || $0.category==category) &&
            (!m.favoritesOnly || m.favorites.contains($0.id)) &&
            (query.isEmpty || ($0.name+" "+$0.category+" "+$0.detail).localizedCaseInsensitiveContains(query))
        }.sorted{
            let order=$0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id<$1.id:order == .orderedAscending
        }
        state.soundsCache=(key,list)
        return list
    }
    @ViewBuilder private var browserMaster:some View {
        let searchRight=state.headerWidth/2+160
        let gap=state.headerWidth-state.trailingWidth-searchRight
        let width=min(300,gap-12)
        if state.headerWidth>0, state.trailingWidth>0, width>=140 {
            HStack(spacing:6){
                Text("Master").foregroundStyle(palette.muted)
                Slider(value:m.globalBinding(0),in:0...1).tint(palette.accent).accessibilityLabel("Master volume")
                Text(String(format:"%.0f%%",m.patch.globals[0]*100)).frame(width:40).monospacedDigit()
            }
            .font(.system(size:14,weight:palette.weight(.regular)))
            .frame(width:width,height:36)
            .offset(x:(searchRight+gap/2)-state.headerWidth/2)
        }
    }
    func step(_ delta:Int){
        let all=sounds
        let scoped=category==nil ? all.filter{$0.category==m.patch.category}:all
        let list=scoped.isEmpty ? all:scoped
        guard !list.isEmpty else{return}
        let next=list.firstIndex{$0.id==m.patch.id}.map{($0+delta+list.count)%list.count} ?? (delta>0 ? 0:list.count-1)
        m.loadPreset(list[next])
    }
    var body:some View{
        let patches=sounds
        VStack(alignment:.leading,spacing:18){
            HStack(alignment:.center,spacing:12){
                HStack(alignment:.center,spacing:12){
                    VStack(alignment:.leading,spacing:4){
                        Text(m.patchBrowserUserOnly ? "User saved patches":"All patches").font(.system(size:26,weight:palette.weight(.semibold)))
                        Text(m.patchBrowserUserOnly ? "Your saved and imported sounds, ready to audition.":"Choose a sound, then play your keyboard.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                    }
                    Button{m.setFavoritesOnly(!m.favoritesOnly)}label:{
                        Image(systemName:m.favoritesOnly ? "star.fill":"star")
                            .font(.system(size:15,weight:.semibold))
                            .foregroundStyle(m.favoritesOnly ? palette.accent:Color.white)
                            .frame(width:30,height:30)
                            .background(palette.surface,in:RoundedRectangle(cornerRadius:6))
                            .overlay(RoundedRectangle(cornerRadius:6).stroke(m.favoritesOnly ? palette.accent.opacity(0.85):palette.graphCyan.opacity(0.35),lineWidth:1))
                    }.buttonStyle(AuroraFlatButtonStyle())
                    .help(m.favoritesOnly ? "Showing favorites only · tap to show all":"Show favorites only")
                    .accessibilityLabel(m.favoritesOnly ? "Show all patches":"Show favorites only")
                    .accessibilityAddTraits(m.favoritesOnly ? .isSelected:[])
                }
                Spacer(minLength:0)
                HStack(spacing:10){
                    if m.patchBrowserUserOnly{
                        Button("Import…"){m.importPresets()}.buttonStyle(AuroraButtonStyle())
                        Button("Export all"){m.exportUserPresets()}.buttonStyle(AuroraButtonStyle()).disabled(m.userPresets.isEmpty)
                    }
                    Button{step(-1)}label:{Image(systemName:"chevron.left").frame(width:28,height:28)}.buttonStyle(AuroraButtonStyle()).keyboardShortcut(.leftArrow,modifiers:[]).accessibilityLabel("Previous patch in this category")
                    Button{step(1)}label:{Image(systemName:"chevron.right").frame(width:28,height:28)}.buttonStyle(AuroraButtonStyle()).keyboardShortcut(.rightArrow,modifiers:[]).accessibilityLabel("Next patch in this category")
                    Button{m.toggleAudio()}label:{Image(systemName:m.running ? "speaker.wave.2.fill":"speaker.slash").font(.system(size:18,weight:palette.weight(.regular))).frame(width:36,height:36)}.buttonStyle(AuroraIconButtonStyle()).foregroundStyle(m.running ? palette.accent:palette.muted).help(m.running ? "Turn audio off":"Turn audio on")
                    Button(action:close){Image(systemName:"xmark").font(.system(size:16,weight:palette.weight(.semibold))).frame(width:36,height:36).background(palette.buttonSurface,in:Circle())}.buttonStyle(AuroraFlatButtonStyle()).keyboardShortcut(.cancelAction).accessibilityLabel("Close patch browser")
                }
                .background{GeometryReader{geo in Color.clear.onAppear{state.trailingWidth=geo.size.width}.onChange(of:geo.size.width){_,width in state.trailingWidth=width}}}
            }
            .background{GeometryReader{geo in Color.clear.onAppear{state.headerWidth=geo.size.width}.onChange(of:geo.size.width){_,width in state.headerWidth=width}}}
            .overlay(alignment:.center){
                TextField("Search patches",text:$m.search)
                    .textFieldStyle(.plain)
                    .font(.system(size:15,weight:palette.weight(.regular)))
                    .padding(.horizontal,12)
                    .frame(width:320,height:36)
                    .background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:7))
                    .overlay(RoundedRectangle(cornerRadius:7).stroke(palette.graphCyan.opacity(0.35),lineWidth:1))
                    .accessibilityLabel("Search patches")
                    .help("Type part of a name — e.g. -GB for Grok Bot patches")
            }
            .overlay(alignment:.center){browserMaster}
            CategoryWrap{
                categoryButton("All",nil)
                Button{m.patchBrowserUserOnly=true;category=nil}label:{Text("User Saved").font(.system(size:15,weight:m.patchBrowserUserOnly ? .bold:.regular)).padding(.horizontal,13).padding(.vertical,8).background(m.patchBrowserUserOnly ? palette.buttonSelected:palette.buttonSurface,in:Capsule()).foregroundStyle(m.patchBrowserUserOnly ? palette.selectedText:Color.white)}.buttonStyle(AuroraFlatButtonStyle(selected:m.patchBrowserUserOnly)).accessibilityLabel("Browse user saved patches").accessibilityAddTraits(m.patchBrowserUserOnly ? .isSelected:[])
                ForEach(m.orderedCategories(m.userPresets+FactoryBank.all),id:\.self){categoryButton($0,$0)}
            }
            Divider().opacity(0.2)
            ScrollViewReader{proxy in
                ScrollView{
                    LazyVStack(spacing:12){
                        ForEach(0..<((patches.count+6)/7),id:\.self){row in
                            EqualHeightRow(spacing:12){
                                ForEach(0..<7,id:\.self){column in
                                    let index=row*7+column
                                    if index<patches.count{
                                        let p=patches[index]
                                        PatchBrowserCard(patch:p,selected:m.patch.id==p.id,userSound:m.userPresets.contains(where:{$0.id==p.id}),favorite:m.favorites.contains(p.id),toggleFavorite:{m.favorite(p.id)},rename:{m.renameName=p.name;m.renameCategory=p.category;m.renameID=p.id},deletePatch:{m.deleteSound(p.id)}){m.loadPreset(p)}.id(p.id)
                                    }else{Color.clear.frame(height:104).accessibilityHidden(true)}
                                }
                            }
                        }
                        if patches.isEmpty{Text(m.search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? (m.patchBrowserUserOnly ? "No user-saved patches yet. Save or import a sound to add it here.":"No patches in this view.") : "No patches match this search.").font(.system(size:16)).foregroundStyle(palette.muted).padding(.vertical,40)}
                    }.background{GeometryReader{geo in Color.clear.preference(key:PatchScrollYKey.self,value:geo.frame(in:.named("patchGrid")).minY)}}.padding(2)
                }
                .coordinateSpace(name:"patchGrid")
                .onPreferenceChange(PatchScrollYKey.self){y in
                    // P4: one reader on the stack + row arithmetic (row = card 104 + spacing 12).
                    let rows=max(1,(patches.count+6)/7)
                    let row=max(0,min(rows-1,Int((-y/116).rounded())))
                    guard state.row != row else{return}
                    state.setRow(row)
                }
                .onAppear{
                    // P1: restore from the model's debounced mirror; row tracking stays browser-local.
                    state.mirrorRow={row in m.patchBrowserRow=row}
                    let rows=max(1,(patches.count+6)/7)
                    let row=min(max(0,m.patchBrowserRow),rows-1)
                    state.setRow(row,immediate:true)
                    let index=row*7
                    if patches.indices.contains(index){proxy.scrollTo(patches[index].id,anchor:.top)}
                }
                .onChange(of:category){_,_ in state.setRow(0,immediate:true);if let first=patches.first{proxy.scrollTo(first.id,anchor:.top)}}
                .onChange(of:m.patchBrowserUserOnly){_,_ in state.setRow(0,immediate:true);if let first=patches.first{proxy.scrollTo(first.id,anchor:.top)}}
                .onChange(of:m.search){_,_ in state.setRow(0,immediate:true);if let first=patches.first{proxy.scrollTo(first.id,anchor:.top)}}
                .onChange(of:m.patch.id){_,id in withAnimation(.easeOut(duration:0.18)){proxy.scrollTo(id,anchor:.center)}}
            }
            HStack{Text("\(patches.count) patches · A–Z");Spacer();Text(m.patch.name).lineLimit(1);Image(systemName:"waveform").foregroundStyle(palette.accent)}.font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
        }.padding(24).background(palette.surface,in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.13)))
            .shadow(color:.black.opacity(0.45),radius:30,y:12)
    }
    func categoryButton(_ label:String,_ value:String?)->some View{
        let selected = !m.patchBrowserUserOnly && category==value
        return Button{m.patchBrowserUserOnly=false;category=value}label:{Text(label).font(.system(size:15,weight:selected ? .bold:.regular)).padding(.horizontal,13).padding(.vertical,8).background(selected ? palette.buttonSelected:palette.buttonSurface,in:Capsule()).foregroundStyle(selected ? palette.selectedText:Color.white)}.buttonStyle(AuroraFlatButtonStyle(selected:selected)).accessibilityLabel("Browse \(label)").accessibilityAddTraits(selected ? .isSelected:[])
    }
}
struct ContentView:View {
    @ObservedObject var m:SynthModel
    var body:some View{AuroraContentView(m:m).environment(\.auroraPalette,m.theme.palette)}
}
struct AuroraContentView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @StateObject private var browserState=PatchBrowserState()
    var showingPatchBrowser:Bool{get{browserState.visible} nonmutating set{browserState.visible=newValue}}
    var body:some View {
        VStack(spacing:0){header;Divider().opacity(0.15)
            HStack(spacing:0){sidebar.frame(width:270);Divider().opacity(0.15)
                ScrollView{
                    LazyVStack(alignment:.leading,spacing:23){
                        HStack(alignment:.center){VStack(alignment:.leading,spacing:6){Text(m.patch.category.uppercased()).font(.system(size:13,weight:palette.weight(.medium))).tracking(2).foregroundStyle(palette.accent);Text(m.patch.name+(m.dirty ? " ·":"")).font(.system(size:36,weight:palette.weight(.medium),design:.rounded));Text(m.patch.detail).font(.system(size:15,weight:palette.weight(.regular))).foregroundStyle(palette.muted)};Spacer();HStack(alignment:.center,spacing:8){if m.userPresets.contains(where:{$0.id==m.patch.id}){UserPatchMenu(name:m.patch.name,rename:{m.renameName=m.patch.name;m.renameCategory=m.patch.category;m.renameID=m.patch.id},deletePatch:{m.deleteSound(m.patch.id)})};Button{m.favorite(m.patch.id)}label:{Image(systemName:m.favorites.contains(m.patch.id) ? "star.fill":"star").foregroundStyle(m.favorites.contains(m.patch.id) ? palette.accent:Color.white).frame(width:32,height:32).background(palette.surface,in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(m.favorites.contains(m.patch.id) ? palette.accent.opacity(0.85):palette.graphCyan.opacity(0.35),lineWidth:1))}.buttonStyle(AuroraFlatButtonStyle()).help(m.favorites.contains(m.patch.id) ? "Remove from favorites":"Save to favorites").accessibilityLabel("\(m.favorites.contains(m.patch.id) ? "Unfavorite":"Favorite") \(m.patch.name)").accessibilityAddTraits(m.favorites.contains(m.patch.id) ? .isSelected:[]);Button("Save",systemImage:"square.and.arrow.down"){m.saveCurrent()}.controlSize(.regular);Button("Save As…"){m.beginSaveAs()}}}
                        HStack(spacing:10){
                            Button{m.setFavoritesOnly(!m.favoritesOnly)}label:{
                                Image(systemName:m.favoritesOnly ? "star.fill":"star")
                                    .foregroundStyle(m.favoritesOnly ? palette.accent:Color.white)
                                    .frame(width:28,height:28)
                                    .background(palette.surface,in:RoundedRectangle(cornerRadius:6))
                                    .overlay(RoundedRectangle(cornerRadius:6).stroke(m.favoritesOnly ? palette.accent.opacity(0.85):palette.graphCyan.opacity(0.35),lineWidth:1))
                            }.buttonStyle(AuroraFlatButtonStyle())
                            .help(m.favoritesOnly ? "Showing favorites only · tap to show all":"Show favorites only")
                            .accessibilityLabel(m.favoritesOnly ? "Show all patches":"Show favorites only")
                            .accessibilityAddTraits(m.favoritesOnly ? .isSelected:[])
                            Button{m.browsePatch(-1)}label:{Image(systemName:"chevron.left")}.help("Previous patch in the current category")
                            Button{m.browsePatch(1)}label:{Image(systemName:"chevron.right")}.help("Next patch in the current category")
                            Button(m.comparingSaved ? "A · Saved — return to B":"B · Edited — compare A"){m.toggleComparison()}.buttonStyle(AuroraButtonStyle(selected:m.comparingSaved)).disabled(m.savedComparison==nil)
                            if m.comparingSaved{Text("Hearing saved sound · your edits are retained").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.accent)}
                            Button("Creative tools…"){m.showingCreativeTools=true}
                            Spacer()
                            if m.soloLayer>=0{Button("Clear solo"){m.toggleSolo(m.soloLayer)}}
                        }
                        HStack(spacing:10){ForEach(0..<4){LayerStrip(model:m,index:$0)}}
                        if m.screen=="Play" {
                            PerformanceSetRack(m:m)
                            HStack(alignment:.center,spacing:16){
                                Text("EQ")
                                    .font(.system(size:28,weight:palette.weight(.semibold)))
                                    .foregroundStyle(Color.white)
                                    .frame(width:56,alignment:.center)
                                    .frame(maxHeight:.infinity,alignment:.center)
                                ParameterSlider(title:"Low",value:Binding(get:{m.eqLow},set:{m.setEqLow($0)}),range:-12...12,format:{String(format:"%+.1f dB",$0)},onBegin:{m.checkpoint()})
                                ParameterSlider(title:"Mid",value:Binding(get:{m.eqMid},set:{m.setEqMid($0)}),range:-12...12,format:{String(format:"%+.1f dB",$0)},onBegin:{m.checkpoint()})
                                ParameterSlider(title:"High",value:Binding(get:{m.eqHigh},set:{m.setEqHigh($0)}),range:-12...12,format:{String(format:"%+.1f dB",$0)},onBegin:{m.checkpoint()})
                            }
                            .fixedSize(horizontal:false,vertical:true)
                            .padding(12)
                            .background(palette.surface,in:RoundedRectangle(cornerRadius:10))
                            .help("House EQ for the whole mix · stays when you change patches (like Output boost)")
                            play
                        } else if m.screen=="Edit" {EditorView(m:m)} else if m.screen=="Matrix" {MatrixView(m:m)} else {RoutingView(m:m)}
                    }.padding(24)
                }.background(palette.background)
            }

        }.background(palette.surface).foregroundStyle(Color.white).preferredColorScheme(.dark).environment(\.colorScheme,.dark).font(.system(size:15,weight:palette.weight(.regular))).controlSize(.regular).buttonStyle(AuroraButtonStyle()).frame(minWidth:1260,minHeight:780)
        .allowsHitTesting(!showingPatchBrowser).accessibilityHidden(showingPatchBrowser)
        .overlay{
            if showingPatchBrowser{
                GeometryReader{geometry in
                    ZStack{
                        Button{showingPatchBrowser=false}label:{Color.black.opacity(0.5).contentShape(Rectangle())}.buttonStyle(AuroraFlatButtonStyle()).accessibilityLabel("Dismiss patch browser")
                        PatchBrowser(m:m){showingPatchBrowser=false}.frame(width:geometry.size.width*0.94,height:geometry.size.height*0.9).foregroundStyle(Color.white)
                    }.frame(width:geometry.size.width,height:geometry.size.height)
                }
            }
        }
        .sheet(isPresented:Binding(get:{m.renameID != nil},set:{if !$0{m.renameID=nil}})){
            VStack(alignment:.leading,spacing:18){Text("Edit sound details").font(.system(size:26,weight:palette.weight(.semibold)));TextField("Sound name",text:$m.renameName).textFieldStyle(.roundedBorder);TextField("Category",text:$m.renameCategory).textFieldStyle(.roundedBorder);HStack{Button("Cancel"){m.renameID=nil};Spacer();Button("Save details"){m.renameSound()}.keyboardShortcut(.defaultAction).disabled(m.renameName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:460).buttonStyle(AuroraButtonStyle())
        }
        .sheet(isPresented:$m.showingCreativeTools){CreativeToolsView(m:m)}
        .sheet(isPresented:$m.showingSave){VStack(alignment:.leading,spacing:18){Text("Save sound as").font(.system(size:26,weight:palette.weight(.semibold)));TextField("Preset name",text:$m.saveName).textFieldStyle(.roundedBorder);TextField("Category",text:$m.saveCategory).textFieldStyle(.roundedBorder);Text("Use an existing category or enter your own.").foregroundStyle(palette.muted);HStack(spacing:8){Button{m.saveFavorite.toggle()}label:{Image(systemName:m.saveFavorite ? "star.fill":"star").foregroundStyle(m.saveFavorite ? palette.accent:Color.white).frame(width:32,height:32).background(palette.surface,in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(m.saveFavorite ? palette.accent.opacity(0.85):palette.graphCyan.opacity(0.35),lineWidth:1))}.buttonStyle(AuroraFlatButtonStyle()).help(m.saveFavorite ? "Will be added to favorites":"Save to favorites").accessibilityLabel("Save to favorites").accessibilityAddTraits(m.saveFavorite ? .isSelected:[]);Text("Add to favorites").foregroundStyle(palette.muted)};HStack{Button("Cancel"){m.showingSave=false};Spacer();Button("Save"){m.saveUserPreset()}.keyboardShortcut(.defaultAction).disabled(m.saveName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:460).buttonStyle(AuroraButtonStyle())}
    }
    var header:some View {
        HStack(spacing:12){
            HStack(spacing:8){Image(systemName:"waveform").foregroundStyle(palette.accent);Text("KiMiA").tracking(3).font(.system(size:19,weight:palette.weight(.semibold))).lineLimit(1);Image(systemName:"waveform").foregroundStyle(palette.accent)}.frame(minWidth:125,idealWidth:262,maxWidth:262,alignment:.center).help(m.notice.isEmpty ? "KiMiA synthesizer":m.notice)
            HStack(spacing:3){ForEach(["Play","Edit","Matrix","Routing"],id:\.self){name in Button{m.screen=name}label:{Text(name).font(.system(size:13,weight:m.screen==name ? .bold:.regular)).frame(maxWidth:.infinity).frame(height:28).background(m.screen==name ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:5)).foregroundStyle(m.screen==name ? palette.selectedText:Color.white)}.buttonStyle(AuroraFlatButtonStyle(selected:m.screen==name)).accessibilityAddTraits(m.screen==name ? .isSelected:[])}}.frame(width:250)
            OutputScope(telemetry:m.scope).frame(minWidth:65,idealWidth:120,maxWidth:160).frame(height:30)
            HStack(spacing:6){
                if m.backend.isPlugin {Text(String(format:"%.1f",m.patch.globals[1])).monospacedDigit().help("Tempo supplied by your DAW")}
                else if m.externalClock{ClockReadout(telemetry:m.performanceTelemetry)}else{TextField("Tempo",value:Binding(get:{Int(m.patch.globals[1])},set:{m.global(1,Double($0))}),format:.number).textFieldStyle(.roundedBorder).frame(width:48).monospacedDigit().accessibilityLabel("Tempo")}
                Text("BPM").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                if !m.backend.isPlugin{Button("Tap"){m.tapTempo()}.disabled(m.externalClock).help("Tap repeatedly to set the tempo")}
            }.fixedSize()
            Divider().frame(height:24)
            HStack(spacing:0){
                Button{m.setTranspose(m.transpose-1)}label:{Image(systemName:"chevron.left").frame(width:28,height:30).contentShape(Rectangle())}.disabled(m.transpose <= -24).accessibilityLabel("Transpose down one semitone")
                Text(m.transpose > 0 ? "+\(m.transpose)":"\(m.transpose)").monospacedDigit().font(.system(size:15,weight:palette.weight(.medium))).frame(width:34).accessibilityLabel("Global transpose \(m.transpose) semitones")
                Button{m.setTranspose(m.transpose+1)}label:{Image(systemName:"chevron.right").frame(width:28,height:30).contentShape(Rectangle())}.disabled(m.transpose >= 24).accessibilityLabel("Transpose up one semitone")
            }.buttonStyle(AuroraFlatButtonStyle()).background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:7)).help("Global transpose · semitones · applies to all layers")
            HStack(spacing:5){
                Button{m.undo()}label:{Image(systemName:"arrow.uturn.backward").frame(width:18,height:20)}.help("Undo").accessibilityLabel("Undo").keyboardShortcut("z",modifiers:.command)
                Button{m.redo()}label:{Image(systemName:"arrow.uturn.forward").frame(width:18,height:20)}.help("Redo").accessibilityLabel("Redo").keyboardShortcut("z",modifiers:[.command,.shift])
            }
            HStack(spacing:6){Text("Master").foregroundStyle(palette.muted);Slider(value:m.globalBinding(0),in:0...1).frame(minWidth:65,idealWidth:95,maxWidth:115).tint(palette.accent).accessibilityLabel("Master volume");Text(String(format:"%.0f%%",m.patch.globals[0]*100)).frame(width:40).monospacedDigit()}
            Button{m.toggleAudio()}label:{Image(systemName:m.running ? "speaker.wave.2.fill":"speaker.slash").font(.system(size:17,weight:m.running ? .bold:.regular)).foregroundStyle(m.running ? palette.selectedText:Color.white).frame(width:34,height:30).background(m.running ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:7))}.buttonStyle(AuroraFlatButtonStyle(selected:m.running)).accessibilityLabel(m.running ? "Turn audio off":"Turn audio on").help(m.status+String(format:" · %.1f kHz · %d frames",m.sampleRate/1000,m.actualFrames))
            .disabled(m.backend.isPlugin)
            Button("Panic",systemImage:"stop.circle"){m.panic()}.help("Stop all notes and effect tails").fixedSize().keyboardShortcut(".",modifiers:.command)
            EngineReadout(telemetry:m.telemetry).font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted).frame(maxWidth:.infinity,alignment:.center)
        }.font(.system(size:14,weight:palette.weight(.regular))).padding(.horizontal,20).padding(.vertical,14)
    }
    var themeMenu:some View {
        Menu{ForEach(AuroraTheme.allCases){theme in Button{m.selectTheme(theme)}label:{Label(theme.rawValue,systemImage:m.theme==theme ? "checkmark.circle.fill":"circle")}}}label:{Image(systemName:"paintpalette.fill").foregroundStyle(Color.white).frame(width:26,height:26).background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:6))}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Color theme · \(m.theme.rawValue)").accessibilityLabel("Color theme · \(m.theme.rawValue)")
    }
    var sidebar:some View {
        VStack(alignment:.leading,spacing:16){HStack(spacing:8){Text("Sound library").font(.system(size:18,weight:palette.weight(.semibold)));Spacer(minLength:8);themeMenu;Menu{Button("Undo Delete"){m.undoDelete()}.disabled(m.deletedSound==nil);Divider();Button("Import one preset…"){m.importPreset()};Button("Import multiple presets…"){m.importPresets()};Button("Export current preset…"){m.exportPreset()};Button("Export all user presets…"){m.exportUserPresets()}.disabled(m.userPresets.isEmpty)}label:{AuroraEllipsisLabel()}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Library actions").help("Import, export, or undo delete")}
            TextField("Search sounds",text:$m.search).textFieldStyle(.roundedBorder).font(.system(size:15,weight:palette.weight(.regular)))
            VStack(alignment:.leading,spacing:9){
                Picker("Collection",selection:$m.collection){
                    Text("KiMiA").tag("KiMiA")
                    Text("Your sounds").tag("Your sounds")
                    Text("Deleted sounds").tag("Deleted sounds")
                    Text("All sounds").tag("All sounds")
                }.labelsHidden().accessibilityLabel("Sound collection")
                Picker("Category",selection:$m.category){
                    Text("All categories").tag("All categories")
                    ForEach(m.categories,id:\.self){Text($0).tag($0)}
                }.labelsHidden().accessibilityLabel("Sound category")
            }.font(.system(size:15,weight:palette.weight(.regular)))
                .onChange(of:m.collection){_,_ in m.category="All categories"}
            Toggle("Favorites",isOn:Binding(get:{m.favoritesOnly},set:{m.setFavoritesOnly($0)})).toggleStyle(.checkbox).font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            ScrollView{LazyVStack(alignment:.leading,spacing:4){
                ForEach(m.libraryGroups,id:\.category){group in
                    HStack(spacing:6){
                        Text(group.category.uppercased()).font(.system(size:18,weight:palette.weight(.bold))).tracking(0.3)
                        Spacer(minLength:0)
                        Text("\(group.sounds.count)").font(.system(size:13,weight:palette.weight(.semibold))).monospacedDigit()
                    }.foregroundStyle(palette.accent).padding(.horizontal,10).padding(.vertical,9)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .background(palette.accent.opacity(0.17),in:RoundedRectangle(cornerRadius:7))
                        .overlay(RoundedRectangle(cornerRadius:7).stroke(palette.accent.opacity(0.25),lineWidth:1))
                        .padding(.top,12).padding(.bottom,4)
                    ForEach(group.sounds){p in presetRow(p)}
                }
                if m.library.isEmpty {
                    Text(m.collection == "Your sounds" && m.userPresets.isEmpty ? "Save a sound to begin your collection." : "No sounds match these filters.")
                        .font(.system(size:15,weight:palette.weight(.regular))).foregroundStyle(palette.muted).padding(.vertical,20)
                }
            }}
            HStack(alignment:.center){
                VStack(alignment:.leading,spacing:5){
                    Text("\(m.library.count) of \(m.collectionSounds.count) sounds").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
                    Text("by Ray Bridge Digital").font(.system(size:14,weight:palette.weight(.bold),design:.rounded)).foregroundStyle(palette.accent)
                    if let version=AuroraResources.bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String {
                        Text("v"+version.split(separator:".").prefix(2).joined(separator:".")).font(.system(size:13,weight:.regular)).foregroundStyle(palette.muted).accessibilityLabel("KiMiA version \(version)")
                    }
                }
                Spacer(minLength:6)
                Button{showingPatchBrowser=true}label:{Image(systemName:"square.grid.3x3.fill").font(.system(size:18,weight:palette.weight(.regular))).foregroundStyle(palette.accent).frame(width:34,height:34).background(palette.buttonSurface,in:RoundedRectangle(cornerRadius:7))}.buttonStyle(AuroraFlatButtonStyle()).help("Browse all patches").accessibilityLabel("Open all patches")
            }
        }.padding(16)
    }
    func presetRow(_ p:SoundPreset)->some View {
        let userSound=m.userPresets.contains(where:{$0.id==p.id})
        return HStack(spacing:8){
            Button{m.loadPreset(p)}label:{
                Text(p.name).font(.system(size:15,weight:palette.weight(.medium))).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                    .frame(minHeight:36,alignment:.leading).padding(.vertical,11).padding(.leading,10).contentShape(Rectangle())
            }.buttonStyle(AuroraFlatButtonStyle()).help(p.detail)
            if m.collection=="Deleted sounds" {
                Button{m.restoreDeleted(p.id)}label:{Image(systemName:"arrow.uturn.backward")}.buttonStyle(AuroraIconButtonStyle()).help("Restore \(p.name)").accessibilityLabel("Restore \(p.name)").padding(.trailing,8)
            }else{
                if userSound{
                    UserPatchBadge().allowsHitTesting(false)
                    UserPatchMenu(name:p.name,rename:{m.renameName=p.name;m.renameCategory=p.category;m.renameID=p.id},deletePatch:{m.deleteSound(p.id)})
                }
                Button{m.favorite(p.id)}label:{Image(systemName:m.favorites.contains(p.id) ? "star.fill":"star").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(Color.white)}
                    .buttonStyle(AuroraIconButtonStyle()).padding(.trailing,8).help("Favorite \(p.name)").accessibilityLabel("Favorite \(p.name)")
            }
        }.background(m.patch.id==p.id ? palette.buttonSelected.opacity(0.25):palette.buttonSurface.opacity(0.22),in:RoundedRectangle(cornerRadius:8))
    }
    var play:some View {
        VStack(alignment:.leading,spacing:23){
            XYPadPanel(m:m)
            HStack{Text("Make it yours").font(.system(size:20,weight:palette.weight(.medium)));Spacer();Text("8 performance macros").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:24),count:4),spacing:16){ForEach(0..<8){MacroDial(model:m,index:$0)}}
            PerformanceTools(m:m,telemetry:m.performanceTelemetry)
            VoiceStatus(m:m).font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted).padding(13).background(palette.surface,in:RoundedRectangle(cornerRadius:10))
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
        WindowGroup("KiMiA") {ContentView(m:model).onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in model.shutdown()}}
            .defaultSize(width:1480,height:940)
            .commands{CommandGroup(replacing:.newItem){};CommandGroup(after:.saveItem){Button("Save"){model.saveCurrent()}.keyboardShortcut("s",modifiers:.command);Button("Save As…"){model.beginSaveAs()}.keyboardShortcut("s",modifiers:[.command,.shift])}}
    }
}
