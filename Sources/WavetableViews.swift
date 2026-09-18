import SwiftUI

@MainActor final class WavetableTelemetry:ObservableObject {
    var backend=AuroraBackend()
    @Published var waves=[[Float]](repeating:[Float](repeating:0,count:128),count:8)
    func update(){
        var next=waves
        for slot in 0..<8 {
            var samples=[Float](repeating:0,count:128)
            _=samples.withUnsafeMutableBufferPointer{backend.aurora_copy_wavetable_preview(Int32(slot/2),Int32(slot%2),$0.baseAddress,128)}
            next[slot]=samples.map{($0*500).rounded()/500}
        }
        if next != waves{waves=next}
    }
}
struct WavetablePreview:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:WavetableTelemetry
    let slot:Int
    var body:some View {
        Canvas { context,size in
            var mid=Path();mid.move(to:CGPoint(x:0,y:size.height/2));mid.addLine(to:CGPoint(x:size.width,y:size.height/2))
            context.stroke(mid,with:.color(.white.opacity(0.1)),lineWidth:1)
            let samples=telemetry.waves[slot]
            var path=Path()
            for (i,value) in samples.enumerated(){
                let point=CGPoint(x:CGFloat(i)*size.width/CGFloat(samples.count-1),y:size.height*(0.5-CGFloat(value)*0.4))
                if i==0{path.move(to:point)}else{path.addLine(to:point)}
            }
            let color=slot%2==0 ? palette.graphCyan:palette.graphPink
            context.stroke(path,with:.color(color.opacity(0.15)),lineWidth:7)
            context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:2.2,lineJoin:.round))
        }.frame(height:66).padding(8).background(palette.graphBackground,in:RoundedRectangle(cornerRadius:7))
            .accessibilityLabel("Oscillator \(slot%2+1) wavetable preview")
    }
}
struct WavetableOscillatorPanel:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    let oscillator:Int
    var base:Int{44+oscillator*7}
    var enabled:Bool{m.patch.layers[m.selectedLayer][base] > 0.5}
    func choices(_ labels:[String],parameter:Int)->some View {
        HStack(spacing:4){ForEach(Array(labels.enumerated()),id:\.offset){i,label in
            Button{m.checkpoint();m.set(m.selectedLayer,parameter,Double(i))}label:{
                Text(label).font(.system(size:12,weight:Int(m.patch.layers[m.selectedLayer][parameter])==i ? .bold:.regular)).frame(maxWidth:.infinity).padding(.vertical,5)
                    .background(Int(m.patch.layers[m.selectedLayer][parameter])==i ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:5))
                    .foregroundStyle(Int(m.patch.layers[m.selectedLayer][parameter])==i ? palette.selectedText:Color.white)
            }.buttonStyle(AuroraFlatButtonStyle(selected:Int(m.patch.layers[m.selectedLayer][parameter])==i)).accessibilityLabel("Oscillator \(oscillator+1) \(label)")
        }}
    }
    var tableBinding:Binding<Int>{Binding(get:{Int(m.patch.layers[m.selectedLayer][base+1])},set:{m.checkpoint();m.set(m.selectedLayer,base+1,Double($0));m.set(m.selectedLayer,base,1)})}
    var tablePicker:some View {
        Picker("Table",selection:tableBinding){
            ForEach(["Warm","Vocal","Metallic","Aggressive","Atmospheric","Pure"],id:\.self){category in
                Section(category){ForEach((0..<24).filter{WavetableCatalog.categories[$0]==category},id:\.self){index in Text(WavetableCatalog.names[index]).tag(index)}}
            }
            if m.hasCustomWavetable(oscillator:oscillator){Section("Imported"){Text(m.patch.importedWavetables?[m.selectedLayer*2+oscillator]?.name ?? "Imported").tag(24)}}
        }.font(.system(size:14,weight:palette.weight(.regular))).accessibilityLabel("Oscillator \(oscillator+1) table")
    }
    var body:some View {
        Panel(title:"Wavetable · oscillator \(oscillator+1)"){
            choices(["Classic","Wavetable"],parameter:base)
            tablePicker
            WavetablePreview(telemetry:m.wavetableTelemetry,slot:m.selectedLayer*2+oscillator).opacity(enabled ? 1:0.35)
            ParameterSlider(title:"Position",value:m.parameter(base+2),onBegin:{m.checkpoint()}).modifier(MatrixFeedback(model:m,destination:12+oscillator))
                .modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:m.selectedLayer,parameter:base+2)))
            choices(["Off","Bend","Sync","Fold"],parameter:base+3)
            ParameterSlider(title:"Warp",value:m.parameter(base+4),onBegin:{m.checkpoint()}).modifier(MatrixFeedback(model:m,destination:14+oscillator))
                .modifier(ControlLearnMenu(m:m,target:ControlTarget(layer:m.selectedLayer,parameter:base+4)))
        }
    }
}
struct WavetablePhasePanel:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    func phaseControls(_ oscillator:Int)->some View {
        VStack(spacing:10){
            ParameterSlider(title:"Osc \(oscillator+1) · phase",value:m.parameter(49+oscillator*7),format:{String(format:"%.0f°",$0*360)},onBegin:{m.checkpoint()})
            ParameterSlider(title:"Random phase",value:m.parameter(50+oscillator*7),onBegin:{m.checkpoint()})
        }
    }
    var body:some View {
        Panel(title:"Phase & import"){
            phaseControls(0)
            phaseControls(1)
            HStack(spacing:8){ForEach(0..<2){o in
                Button{m.importWavetable(oscillator:o)}label:{Label("Osc \(o+1)",systemImage:"square.and.arrow.down").font(.system(size:13,weight:palette.weight(.regular))).frame(maxWidth:.infinity)}
                    .help("Import a WAV wavetable into oscillator \(o+1)")
            }}
            Text(m.wavetableMessage.isEmpty ? "Import a WAV table with 1–64 frames. Your imported wave is saved inside the patch.":m.wavetableMessage).font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
}
struct WavetableSection:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    var body:some View {
        EqualHeightRow(spacing:16){WavetableOscillatorPanel(m:m,oscillator:0);WavetableOscillatorPanel(m:m,oscillator:1);WavetablePhasePanel(m:m)}
    }
}
