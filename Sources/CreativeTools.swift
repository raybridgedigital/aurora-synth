import SwiftUI
import AppKit

struct XYAxis:Codable,Equatable {
    var macro:Int
    var start=0.0
    var end=1.0
    var valid:Bool{(0..<8).contains(macro) && start.isFinite && end.isFinite && (0...1).contains(start) && (0...1).contains(end)}
    func value(_ position:Double)->Double{start+(end-start)*max(0,min(1,position))}
    func position(_ value:Double)->Double{abs(end-start)<0.000001 ? 0.5:max(0,min(1,(value-start)/(end-start)))}
}
struct XYSettings:Codable,Equatable {
    var x=XYAxis(macro:0)
    var y=XYAxis(macro:2)
    var valid:Bool{x.valid && y.valid && x.macro != y.macro}
}
extension SynthModel {
    var xySettings:XYSettings{patch.xy ?? XYSettings()}
    func changeXY(_ change:(inout XYSettings)->Void){
        finishComparison();var settings=xySettings;change(&settings)
        guard settings.valid else{return};patch.xy=settings;dirty=true
    }
    func assignXY(horizontal:Bool,macro index:Int){
        guard (0..<8).contains(index) else{return};checkpoint()
        changeXY{settings in
            if horizontal{if settings.y.macro==index{settings.y.macro=settings.x.macro};settings.x.macro=index}
            else{if settings.x.macro==index{settings.x.macro=settings.y.macro};settings.y.macro=index}
        }
    }
    func moveXY(x:Double,y:Double){
        guard x.isFinite,y.isFinite else{return};finishComparison()
#if AURORA_PLUGIN
        aurora_plugin_xy(backend.context,x,y);syncPlugin();dirty=true
#else
        let settings=xySettings
        macro(settings.x.macro,settings.x.value(x));macro(settings.y.macro,settings.y.value(y))
#endif
    }
}
// Keep pointer feedback independent of SwiftUI's full sound-model redraws.
struct XYTrackingPad:NSViewRepresentable {
    var x:Double
    var y:Double
    var palette:AuroraPalette
    var onBegin:()->Void
    var onMove:(Double,Double)->Void
    func makeNSView(context:Context)->XYTrackingView{XYTrackingView()}
    func updateNSView(_ view:XYTrackingView,context:Context){
        view.onBegin=onBegin;view.onMove=onMove
        view.waveColor=NSColor(palette.graphCyan);view.fillColor=NSColor(palette.graphBackground)
        if !view.dragging{view.position=CGPoint(x:x,y:y)}
        view.needsDisplay=true
    }
    static func dismantleNSView(_ view:XYTrackingView,coordinator:()){view.cancelPending()}
}
@MainActor final class XYTrackingView:NSView {
    var onBegin:()->Void={}
    var onMove:(Double,Double)->Void={_,_ in}
    var waveColor=NSColor.cyan
    var fillColor=NSColor.black
    var position=CGPoint(x:0.5,y:0.5)
    private(set) var dragging=false
    private var pending:CGPoint?
    private var updateTimer:Timer?
    override var isFlipped:Bool{true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func draw(_ dirtyRect:NSRect){
        let background=NSBezierPath(roundedRect:bounds,xRadius:10,yRadius:10)
        fillColor.setFill();background.fill()
        NSGraphicsContext.saveGraphicsState();background.addClip()
        defer{NSGraphicsContext.restoreGraphicsState()}
        let grid=NSBezierPath()
        for i in 1..<4{
            let t=CGFloat(i)/4
            grid.move(to:NSPoint(x:bounds.width*t,y:0));grid.line(to:NSPoint(x:bounds.width*t,y:bounds.height))
            grid.move(to:NSPoint(x:0,y:bounds.height*t));grid.line(to:NSPoint(x:bounds.width,y:bounds.height*t))
        }
        waveColor.withAlphaComponent(0.18).setStroke();grid.lineWidth=1;grid.stroke()
        let point=CGPoint(x:12+position.x*max(1,bounds.width-24),y:12+(1-position.y)*max(1,bounds.height-24))
        let cross=NSBezierPath()
        cross.move(to:NSPoint(x:point.x,y:0));cross.line(to:NSPoint(x:point.x,y:bounds.height))
        cross.move(to:NSPoint(x:0,y:point.y));cross.line(to:NSPoint(x:bounds.width,y:point.y))
        cross.setLineDash([4,4],count:2,phase:0);cross.lineWidth=1
        waveColor.withAlphaComponent(0.5).setStroke();cross.stroke()
        waveColor.withAlphaComponent(0.2).setFill();NSBezierPath(ovalIn:NSRect(x:point.x-15,y:point.y-15,width:30,height:30)).fill()
        NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:point.x-7,y:point.y-7,width:14,height:14)).fill()
        let ring=NSBezierPath(ovalIn:NSRect(x:point.x-9,y:point.y-9,width:18,height:18))
        waveColor.setStroke();ring.lineWidth=2;ring.stroke()
    }
    func track(_ point:CGPoint){
        position=CGPoint(x:max(0,min(1,(point.x-12)/max(1,bounds.width-24))),y:max(0,min(1,1-(point.y-12)/max(1,bounds.height-24))))
        pending=position
        // Draw now, before publishing changes that invalidate the surrounding UI.
        needsDisplay=true;displayIfNeeded()
        if updateTimer==nil{
            let timer=Timer(timeInterval:1.0/60,repeats:false){[weak self] _ in
                MainActor.assumeIsolated{self?.flushPending()}
            }
            updateTimer=timer;RunLoop.main.add(timer,forMode:.common)
        }
    }
    func flushPending(){
        updateTimer?.invalidate();updateTimer=nil
        if let value=pending{pending=nil;onMove(value.x,value.y)}
    }
    func cancelPending(){updateTimer?.invalidate();updateTimer=nil;pending=nil}
    override func mouseDown(with event:NSEvent){dragging=true;onBegin();track(convert(event.locationInWindow,from:nil))}
    override func mouseDragged(with event:NSEvent){track(convert(event.locationInWindow,from:nil))}
    override func mouseUp(with event:NSEvent){
        track(convert(event.locationInWindow,from:nil));flushPending();dragging=false
    }
}
struct XYPadPanel:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    var settings:XYSettings{m.xySettings}
    func position(_ horizontal:Bool)->Double{let axis=horizontal ? settings.x:settings.y;return axis.position(m.patch.macros[axis.macro])}
    func axisControls(_ horizontal:Bool)->some View {
        let axis=horizontal ? settings.x:settings.y
        return VStack(spacing:8){
            HStack{
                Text(horizontal ? "X · left → right":"Y · bottom → top").font(.system(size:14,weight:palette.weight(.semibold))).foregroundStyle(.white)
                Spacer()
                Button("Reverse"){m.checkpoint();m.changeXY{settings in if horizontal{let old=settings.x.start;settings.x.start=settings.x.end;settings.x.end=old}else{let old=settings.y.start;settings.y.start=settings.y.end;settings.y.end=old}}}
            }
            Picker(horizontal ? "X macro":"Y macro",selection:Binding(get:{axis.macro},set:{m.assignXY(horizontal:horizontal,macro:$0)})){
                ForEach(0..<8){Text("\($0+1) · \(m.macroNames[$0])").tag($0)}
            }.labelsHidden()
            HStack(spacing:14){
                ParameterSlider(title:"From",value:Binding(get:{axis.start},set:{v in m.changeXY{if horizontal{$0.x.start=v}else{$0.y.start=v}}}),onBegin:{m.checkpoint()})
                ParameterSlider(title:"To",value:Binding(get:{axis.end},set:{v in m.changeXY{if horizontal{$0.x.end=v}else{$0.y.end=v}}}),onBegin:{m.checkpoint()})
            }
        }
    }
    var graph:some View {
        XYTrackingPad(x:position(true),y:position(false),palette:palette,
                      onBegin:{m.checkpoint()},onMove:{x,y in m.moveXY(x:x,y:y)})
            .frame(height:245)
            .accessibilityLabel("XY performance pad. Use the X and Y sliders below to adjust each axis.")
    }
    var body:some View {
        Panel(title:"XY · performance"){
            HStack(alignment:.top,spacing:20){
                VStack(spacing:10){
                    graph
                    HStack(spacing:18){
                        ParameterSlider(title:"X · \(m.macroNames[settings.x.macro])",value:Binding(get:{position(true)},set:{m.macro(settings.x.macro,settings.x.value($0))}),onBegin:{m.checkpoint()})
                        ParameterSlider(title:"Y · \(m.macroNames[settings.y.macro])",value:Binding(get:{position(false)},set:{m.macro(settings.y.macro,settings.y.value($0))}),onBegin:{m.checkpoint()})
                    }
                }
                VStack(spacing:16){axisControls(true);axisControls(false);HStack{Button("Center"){m.checkpoint();m.moveXY(x:0.5,y:0.5)};Spacer();Text("Drag to perform").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)}}.frame(width:300)
            }
            Text("Controls two macros, including custom assignments. Release to hold the position. Axis settings save with the patch. If routes overlap, Y applies last.").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
        }
    }
}

struct SavedMotionShape:Codable,Equatable,Identifiable {
    var id=UUID().uuidString
    var name:String
    var points:[MotionPoint]
    var valid:Bool{var settings=MotionSettings();settings.points=points;return !name.isEmpty && name.count<=80 && settings.valid}
}
struct ControlTarget:Codable,Equatable,Hashable {
    var layer=0 // -1 = shared control
    var parameter=7
    static let layerNames=["Enabled","Osc 1 wave","Osc 2 wave","Oscillator blend","Detune","Sub","Noise","Cutoff","Resonance","Attack","Decay","Sustain","Release","Level","Pan","Transpose","LFO 1 rate","LFO 1 depth","LFO 1 destination","LFO 1 shape","Filter envelope","Drive","Arp enabled","Arp rate","Arp mode","Arp octaves","Arp gate","Key low","Key high","LFO 2 rate","LFO 2 depth","LFO 2 destination","Filter type","LFO 2 shape","Pulse width","PWM depth","Unison","Unison detune","Stereo spread","Oscillator sync","Sync tune","Voice mode","Glide","Bend range","Osc 1 wavetable mode","Osc 1 table","Osc 1 position","Osc 1 warp mode","Osc 1 warp","Osc 1 phase","Osc 1 random phase","Osc 2 wavetable mode","Osc 2 table","Osc 2 position","Osc 2 warp mode","Osc 2 warp","Osc 2 phase","Osc 2 random phase","Filter 2 enabled","Filter 2 type","Filter 2 cutoff","Filter 2 resonance","Filter routing","Filter balance","Mod attack","Mod decay","Mod sustain","Mod release","Mod amount","Mod destination","Osc modulation mode","Osc modulation amount","Osc modulation ratio","Character mode","Character drive","Character mix","Character tone","Character bits","Character rate","Filter 1 slope","Filter 2 slope","LFO 1 sync","LFO 1 division","LFO 1 retrigger","LFO 1 phase","LFO 1 delay","LFO 1 fade","LFO 2 sync","LFO 2 division","LFO 2 retrigger","LFO 2 phase","LFO 2 delay","LFO 2 fade","Osc 1 formant","Osc 1 tone","Osc 2 formant","Osc 2 tone","Arp swing","Arp velocity shape"]
    static let globalNames=["Master","Tempo","Delay mix","Delay feedback","Reverb mix","Chorus mix","Phaser mix","Phaser rate","Phaser depth","Phaser feedback","Chorus rate","Chorus depth","Reverb size","Reverb decay","Delay timing","Output gain","Delay sync","Delay time ms","Delay ping-pong","Delay tone","EQ low","EQ mid","EQ high","Shimmer mix","Shimmer pitch","Shimmer decay","Shimmer tone","Shimmer pre-delay","Shimmer amount","Shimmer voice +5","Shimmer voice +7","Shimmer voice +12","Shimmer reverse","Shimmer early level","Shimmer early size","Shimmer late level","Shimmer late decay","Flanger mix","Flanger rate","Flanger depth","Flanger feedback","Tremolo mix","Tremolo rate","Tremolo depth","Tremolo mode","Bitcrusher mix","Bitcrusher bits","Bitcrusher downsample","Delay duck","Delay duck release","Compressor threshold","Compressor ratio","Compressor attack","Compressor release","Compressor makeup","Compressor auto","Auto-wah mix","Auto-wah sensitivity","Auto-wah range","Auto-wah filter","Shimmer power","Delay power","Reverb power","Chorus power","Phaser power","Flanger power","Tremolo power","Bitcrusher power","Auto-wah power","Compressor power","Reverb type","Reverb pre-delay","Reverb tone"]
    var valid:Bool{(-1...3).contains(layer) && (layer<0 ? Self.globalNames.indices:Self.layerNames.indices).contains(parameter)}
    var name:String{valid ? (layer<0 ? "Shared · "+Self.globalNames[parameter]:"\(layerLetters[layer]) · "+Self.layerNames[parameter]):"Unknown"}
    @MainActor var range:ClosedRange<Double>{layer<0 ? SynthModel.globalRanges[parameter]:SynthModel.ranges[parameter]}
    var logarithmic:Bool{layer>=0 && [7,9,10,12,16,29,60,64,65,67,72,78].contains(parameter)}
    @MainActor func actual(_ normalized:Double)->Double{
        let n=max(0,min(1,normalized)),r=range
        return logarithmic ? r.lowerBound*pow(r.upperBound/r.lowerBound,n):r.lowerBound+(r.upperBound-r.lowerBound)*n
    }
    @MainActor func normalized(_ actual:Double)->Double{
        let r=range,v=max(r.lowerBound,min(r.upperBound,actual))
        return logarithmic ? log(v/r.lowerBound)/log(r.upperBound/r.lowerBound):(v-r.lowerBound)/(r.upperBound-r.lowerBound)
    }
}
struct CustomMacroRoute:Codable,Equatable,Identifiable {
    var id=UUID().uuidString
    var target=ControlTarget()
    var from=0.0
    var to=1.0
    var valid:Bool{target.valid && from.isFinite && to.isFinite && (0...1).contains(from) && (0...1).contains(to)}
}
struct CustomMacro:Codable,Equatable {
    var name:String
    var routes:[CustomMacroRoute]=[]
    var valid:Bool{!name.isEmpty && name.count<=40 && routes.count<=16 && Set(routes.map(\.id)).count==routes.count && routes.allSatisfy(\.valid)}
}
struct DirectCCMapping:Codable,Equatable,Identifiable {
    var source:Int32
    var channel:Int
    var controller:Int
    var target:ControlTarget
    var id:String{"\(source):\(channel):\(controller)"}
    var valid:Bool{target.valid && (1...16).contains(channel) && (0...119).contains(controller) && controller != 64}
}
enum VariationGroup:String,CaseIterable,Identifiable {
    case oscillators="Oscillators", filter="Filter", envelopes="Envelopes", movement="Movement", pitch="Pitch", effects="FX"
    var id:String{rawValue}
    var parameters:[Int]{switch self{
    case .oscillators:return [3,4,5,6,34,35,37,38,46,48,53,55,71,72]
    case .filter:return [7,8,20,21,60,61,63]
    case .envelopes:return [9,10,11,12,64,65,66,67,68]
    case .movement:return [16,17,29,30]
    case .pitch:return [15,42]
    case .effects:return [74,75,76,77,78]
    }}
}
@MainActor final class CreativeEditorState:ObservableObject {
    @Published var tab=0
    @Published var macro=0
    @Published var target=ControlTarget()
    @Published var amount=0.15
    @Published var allLayers=false
    @Published var locked:Set<VariationGroup>=[.pitch,.envelopes,.effects]
}
extension SynthModel {
    func saveShape(name:String,replacing id:String?=nil){
        let clean=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80));guard !clean.isEmpty else{return}
        let shape=SavedMotionShape(id:id ?? UUID().uuidString,name:clean,points:motionSettings.points)
        guard shape.valid else{return}
        if let index=savedShapes.firstIndex(where:{$0.id==shape.id}){savedShapes[index]=shape}else{guard savedShapes.count<512 else{notice="Shape library limit reached.";return};savedShapes.append(shape)}
        saveShapeLibrary()
    }
    func deleteShape(_ id:String){savedShapes.removeAll{$0.id==id};saveShapeLibrary()}
    func saveShapeLibrary(){
        do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONEncoder().encode(savedShapes).write(to:folder.appendingPathComponent("motion-shapes.json"),options:.atomic)}catch{notice="Could not save shapes: \(error.localizedDescription)"}
    }
    func restoreShapeLibrary(){if let data=try? Data(contentsOf:folder.appendingPathComponent("motion-shapes.json")),data.count<2_000_000,let shapes=try? JSONDecoder().decode([SavedMotionShape].self,from:data){var ids=Set<String>();savedShapes=Array(shapes.filter{$0.valid && ids.insert($0.id).inserted}.prefix(512))}}
    func editCustomMacro(_ index:Int,_ change:(inout CustomMacro)->Void){
        finishComparison();guard (0..<8).contains(index) else{return}
        var macros=patch.customMacros ?? [:],definition=macros[index] ?? CustomMacro(name:macroNames[index]);change(&definition)
        guard definition.valid else{return};macros[index]=definition;patch.customMacros=macros;dirty=true
    }
    func controlValue(_ target:ControlTarget)->Double{target.layer<0 ? patch.globalValue(target.parameter):patch.layers[target.layer][target.parameter]}
    func setControl(_ target:ControlTarget,_ normalized:Double){
        guard target.valid,normalized.isFinite else{return}
        var value=target.actual(normalized)
        // The imported slot is selectable only when this oscillator actually has a table.
        if target.layer>=0 && [45,52].contains(target.parameter) && value.rounded()==24 && patch.importedWavetables?[target.layer*2+(target.parameter==52 ? 1:0)]==nil{value=23}
        if target.layer<0{global(target.parameter,value)}else{set(target.layer,target.parameter,value)}
    }
    func beginDirectLearn(_ target:ControlTarget){guard target.valid else{return};learningMacro=nil;learningControl=target;notice="Move a hardware knob for \(target.name)."}
    @discardableResult func handleDirectCC(source:Int32,channel:Int,controller:Int,value:Double)->Bool {
        if let target=learningControl {
            guard (0...119).contains(controller),controller != 64 else{notice="Choose a knob; sustain and channel-mode controls stay reserved.";return true}
            directMappings.removeAll{$0.target==target || ($0.source==source && $0.channel==channel && $0.controller==controller)}
            mappings.removeAll{$0.source==source && $0.channel==channel && $0.controller==controller}
            let mapping=DirectCCMapping(source:source,channel:channel,controller:controller,target:target)
            directMappings.append(mapping);directPickup.removeAll();directPrevious[mapping.id]=value;learningControl=nil;persist();notice="Mapped \(target.name). Cross its current value to take control.";return true
        }
        guard let mapping=directMappings.first(where:{$0.source==source && $0.channel==channel && $0.controller==controller}) else{return false}
        let target=mapping.target.normalized(controlValue(mapping.target)),previous=directPrevious[mapping.id] ?? value
        directPrevious[mapping.id]=value
        if directPickup.contains(mapping.id) || abs(value-target)<0.04 || (previous-target)*(value-target)<=0 {
            if Date().timeIntervalSince(lastDirectEdit)>0.5{checkpoint()};lastDirectEdit=Date()
            directPickup.insert(mapping.id);applyingDirectCC=true;defer{applyingDirectCC=false};setControl(mapping.target,value)
        }
        return true
    }
    func makeVariation(amount:Double,locked:Set<VariationGroup>,allLayers:Bool,random:()->Double={Double.random(in:-1...1)}){
        guard amount.isFinite,amount>0 else{return};checkpoint()
        let strength=min(1,amount)
        for layer in (allLayers ? Array(0..<4):[selectedLayer]) where patch.layers[layer][0]>0.5 {
            for group in VariationGroup.allCases where !locked.contains(group){for p in group.parameters{
                if locked.contains(.pitch) && ([4,37].contains(p) || ([16,17].contains(p) && patch.layers[layer][18]==1) || ([29,30].contains(p) && patch.layers[layer][31]==1)){continue}
                let target=ControlTarget(layer:layer,parameter:p),current=target.normalized(patch.layers[layer][p])
                var n=max(0,min(1,current+max(-1,min(1,random()))*strength*0.35))
                if p==6{n=min(0.25,n)};if p==8{n=min(0.78,n)}
                setControl(target,n)
            }}
            if !locked.contains(.movement),var motion=patch.motion?[layer],!(locked.contains(.pitch) && motion.routes[2].enabled),!(locked.contains(.envelopes) && motion.routes[0].enabled){
                for i in motion.points.indices{motion.points[i].y=max(0,min(1,motion.points[i].y+random()*strength*0.2))}
                patch.motion?[layer]=motion
            }
        }
        if !locked.contains(.effects){for p in [2,3,4,5,6,7,8,9,10,11,12,13]{let t=ControlTarget(layer:-1,parameter:p);var n=max(0,min(1,t.normalized(patch.globalValue(p))+random()*strength*0.2));if p==3{n=min(0.8,n)};setControl(t,n)}}
        applyMotion();dirty=true;notice="Variation created. Undo restores the previous sound; Save As keeps a separate copy."
    }
}
struct ControlTargetPicker:View {
    @Environment(\.auroraPalette) private var palette
    @Binding var target:ControlTarget
    var body:some View {
        HStack{
            Picker("Scope",selection:Binding(get:{target.layer},set:{v in target=ControlTarget(layer:v,parameter:v<0 ? 4:7)})){
                Text("Shared").tag(-1);ForEach(0..<4){Text("Layer \(layerLetters[$0])").tag($0)}
            }.frame(width:145)
            Picker("Control",selection:$target.parameter){ForEach(Array((target.layer<0 ? ControlTarget.globalNames:ControlTarget.layerNames).enumerated()),id:\.offset){i,name in Text(name).tag(i)}}
        }.labelsHidden()
    }
}
struct ControlLearnMenu:ViewModifier {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    let target:ControlTarget
    func body(content:Content)->some View {content.contextMenu{
        Button("MIDI Learn · \(target.name)"){m.beginDirectLearn(target)}
        if m.learningControl != nil {Button("Cancel MIDI Learn"){m.learningControl=nil}}
        Button("Remove MIDI mapping"){m.directMappings.removeAll{$0.target==target};m.persist()}.disabled(!m.directMappings.contains{$0.target==target})
    }}
}
struct MacroAssignmentRow:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    let macro:Int
    let index:Int
    var route:CustomMacroRoute{guard let routes=m.patch.customMacros?[macro]?.routes,routes.indices.contains(index) else{return CustomMacroRoute()};return routes[index]}
    func editRoute(_ change:(inout CustomMacroRoute)->Void){m.editCustomMacro(macro){definition in guard definition.routes.indices.contains(index) else{return};change(&definition.routes[index])}}
    func bound(_ key:WritableKeyPath<CustomMacroRoute,Double>)->Binding<Double>{Binding(get:{route[keyPath:key]},set:{v in editRoute{$0[keyPath:key]=v}})}
    var body:some View {
        VStack(spacing:10){
            HStack{ControlTargetPicker(target:Binding(get:{route.target},set:{v in m.checkpoint();editRoute{$0.target=v}}));Button("Remove"){m.checkpoint();m.editCustomMacro(macro){guard $0.routes.indices.contains(index) else{return};$0.routes.remove(at:index)}}}
            HStack(spacing:18){
                ParameterSlider(title:"At macro 0%",value:bound(\.from),format:{String(format:"%.3g",route.target.actual($0))},onBegin:{m.checkpoint()})
                ParameterSlider(title:"At macro 100%",value:bound(\.to),format:{String(format:"%.3g",route.target.actual($0))},onBegin:{m.checkpoint()})
                Button("Reverse"){m.checkpoint();editRoute{let f=$0.from;$0.from=$0.to;$0.to=f}}
            }
        }.padding(12).background(palette.surface,in:RoundedRectangle(cornerRadius:8))
    }
}
struct CreativeToolsView:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @StateObject private var editor=CreativeEditorState()
    var macroEditor:some View {
        VStack(alignment:.leading,spacing:16){
            Picker("Macro",selection:$editor.macro){ForEach(0..<8){Text("\($0+1) · \(m.macroNames[$0])").tag($0)}}
            Text("Custom assignments replace this macro's original behavior. Each route has its own range and direction. Move the macro to apply them.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            HStack{
                TextField("Macro name",text:Binding(get:{m.macroNames[editor.macro]},set:{v in m.checkpoint();m.editCustomMacro(editor.macro){$0.name=String(v.prefix(40))}})).textFieldStyle(.roundedBorder)
                Button("Add assignment"){m.checkpoint();m.editCustomMacro(editor.macro){$0.routes.append(CustomMacroRoute(target:ControlTarget(layer:m.selectedLayer,parameter:7)))}}.disabled((m.patch.customMacros?[editor.macro]?.routes.count ?? 0)>=16)
                Button("Restore original"){m.checkpoint();m.patch.customMacros?[editor.macro]=nil;m.dirty=true}
            }
            ScrollView{VStack(spacing:12){ForEach(0..<(m.patch.customMacros?[editor.macro]?.routes.count ?? 0),id:\.self){MacroAssignmentRow(m:m,macro:editor.macro,index:$0)}}}
            ParameterSlider(title:m.macroNames[editor.macro],value:Binding(get:{m.patch.macros[editor.macro]},set:{m.macro(editor.macro,$0)}),onBegin:{m.checkpoint()})
        }.padding(18)
    }
    var midiEditor:some View {
        VStack(alignment:.leading,spacing:18){
            Text("Choose any layer or shared control, then move a hardware knob. Mappings are specific to its keyboard, channel and CC, and persist across patches.").foregroundStyle(palette.muted)
            ControlTargetPicker(target:$editor.target)
            HStack{Button(m.learningControl==nil ? "Learn control":"Move a knob…"){m.beginDirectLearn(editor.target)};Button("Cancel"){m.learningControl=nil}.disabled(m.learningControl==nil)}
            Text(m.learningControl.map{"Learning: \($0.name)"} ?? "Soft takeover: cross the current control value before changes take effect. Sustain and channel-mode messages are reserved.").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.accent)
            ScrollView{VStack(alignment:.leading,spacing:12){ForEach(m.directMappings){mapping in
                HStack{Text(mapping.target.name);Spacer();Text("\(m.sources.first{$0.id==mapping.source}?.name ?? String(mapping.source)) · ch \(mapping.channel) · CC \(mapping.controller)").foregroundStyle(palette.muted);Button("Remove"){m.directMappings.removeAll{$0.id==mapping.id};m.directPickup.remove(mapping.id);m.persist()}}
            }}}
            Text("You can also right-click parameter sliders in Edit to learn them. MIDI CC 1 and 11 retain their normal wheel/expression behavior alongside learned assignments.").font(.system(size:13,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
        }.padding(18)
    }
    var variations:some View {
        VStack(alignment:.leading,spacing:20){
            Text("Create a variation of the current sound. Locked groups stay unchanged. Master level, layer levels, splits, routing and enabled layers are always preserved.").foregroundStyle(palette.muted)
            ParameterSlider(title:"Variation amount",value:$editor.amount,range:0.05...1,format:{$0<0.3 ? "Subtle · \(Int($0*100))%":$0<0.65 ? "Moderate · \(Int($0*100))%":"Adventurous · \(Int($0*100))%"})
            Toggle("All enabled layers",isOn:$editor.allLayers)
            Text(editor.allLayers ? "Scope: all enabled layers":"Scope: layer \(layerLetters[m.selectedLayer])").foregroundStyle(palette.accent)
            ForEach(VariationGroup.allCases){group in Toggle("Lock \(group.rawValue)",isOn:Binding(get:{editor.locked.contains(group)},set:{if $0{editor.locked.insert(group)}else{editor.locked.remove(group)}})).toggleStyle(.checkbox)}
            HStack{Button("Create variation"){m.makeVariation(amount:editor.amount,locked:editor.locked,allLayers:editor.allLayers)};Button("Undo"){m.undo()};Button("Save As…"){m.showingCreativeTools=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.3){m.beginSaveAs()}}}
            Spacer()
        }.padding(18)
    }
    var body:some View {
        VStack(spacing:16){HStack{Text("Creative tools").font(.system(size:25,weight:palette.weight(.semibold)));Spacer();Button("Done"){m.showingCreativeTools=false}}
            HStack(spacing:8){ForEach(Array(["Macros","MIDI Learn","Variations"].enumerated()),id:\.offset){index,title in
                Button{editor.tab=index}label:{Text(title).font(.system(size:15,weight:editor.tab==index ? .bold:.regular)).frame(maxWidth:.infinity).padding(.vertical,10).background(editor.tab==index ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:8)).foregroundStyle(editor.tab==index ? palette.selectedText:Color.white)}.buttonStyle(AuroraFlatButtonStyle(selected:editor.tab==index)).accessibilityAddTraits(editor.tab==index ? .isSelected:[])
            }}
            Group{switch editor.tab{case 1:midiEditor;case 2:variations;default:macroEditor}}.frame(maxWidth:.infinity,maxHeight:.infinity).background(palette.raised.opacity(0.35),in:RoundedRectangle(cornerRadius:10))
        }.padding(24).frame(width:960,height:700).background(palette.surface).buttonStyle(AuroraButtonStyle()).foregroundStyle(Color.white).font(.system(size:15,weight:palette.weight(.regular))).environment(\.colorScheme,.dark).preferredColorScheme(.dark)
    }
}
