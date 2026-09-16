import SwiftUI

struct MotionPoint:Codable,Equatable {
    var x:Double
    var y:Double
    var curve:Double=0
}
struct MotionRoute:Codable,Equatable {
    var enabled=false
    var minimum:Double=0
    var maximum:Double=1
    var inverted=false
}
struct MotionSettings:Codable,Equatable {
    var enabled=false
    var loop=false
    var seconds=4.0
    var beats:Double?=nil
    var grid:Int?=nil
    var points=[MotionPoint(x:0,y:0,curve:-0.25),MotionPoint(x:1,y:1)]
    var routes=[MotionRoute(enabled:true),MotionRoute(minimum:400,maximum:6000),MotionRoute(minimum:0,maximum:12),MotionRoute(minimum:-1,maximum:1),MotionRoute(),MotionRoute(),MotionRoute(),MotionRoute()]
    static let names=["Volume","Filter cutoff","Pitch","Pan","Osc 1 position","Osc 2 position","Osc 1 warp","Osc 2 warp"]
    static let ranges:[ClosedRange<Double>]=[0...1,30...18000,-24...24,-1...1,0...1,0...1,0...1,0...1]
    var valid:Bool {
        if let beats{guard beats.isFinite,(0.25...32).contains(beats) else{return false}}
        if let grid{guard [0,4,8,16,32].contains(grid) else{return false}}
        guard seconds.isFinite,(0.1...60).contains(seconds),(2...16).contains(points.count),routes.count==8,points.first?.x==0,points.last?.x==1 else{return false}
        for (i,p) in points.enumerated(){
            guard p.x.isFinite,p.y.isFinite,p.curve.isFinite,(0...1).contains(p.x),(0...1).contains(p.y),(-1...1).contains(p.curve) else{return false}
            if i>0 && p.x-points[i-1].x<0.0001{return false}
        }
        return routes.enumerated().allSatisfy{i,r in r.minimum.isFinite && r.maximum.isFinite && Self.ranges[i].contains(r.minimum) && Self.ranges[i].contains(r.maximum) && r.minimum<=r.maximum}
    }
    var packet:[Float] {
        var data=[Float](repeating:0,count:85)
        data[84]=Float(beats ?? 0)
        data[0]=enabled ? 1:0;data[1]=loop ? 1:0;data[2]=Float(seconds);data[3]=Float(points.count)
        for (i,p) in points.enumerated(){data[4+i*3]=Float(p.x);data[5+i*3]=Float(p.y);data[6+i*3]=Float(p.curve)}
        for (i,r) in routes.enumerated(){data[52+i*4]=r.enabled ? 1:0;data[53+i*4]=Float(r.minimum);data[54+i*4]=Float(r.maximum);data[55+i*4]=r.inverted ? 1:0}
        return data
    }
    func snapped(_ x:Double)->Double {let steps=grid ?? 0;return steps>0 ? (x*Double(steps)).rounded()/Double(steps):x}
    func shape(_ x:Double)->Double {
        for i in 1..<points.count where x<=points[i].x {
            let a=points[i-1],b=points[i],t=max(0,min(1,(x-a.x)/(b.x-a.x)))
            return a.y+(b.y-a.y)*pow(t,pow(2,a.curve*3))
        }
        return points.last?.y ?? 0
    }
    func value(_ shape:Double,destination:Int)->Double {
        let route=routes[destination],t=route.inverted ? 1-shape:shape
        return destination==1 ? route.minimum*pow(route.maximum/route.minimum,t):route.minimum+(route.maximum-route.minimum)*t
    }
    static func formatted(_ value:Double,_ destination:Int)->String {
        switch destination {
        case 1:return value>=1000 ? String(format:"%0.1f kHz",value/1000):String(format:"%0.0f Hz",value)
        case 2:return String(format:"%+0.1f st",value)
        case 3:return abs(value)<0.005 ? "Center":String(format:"%0.0f%% %@",abs(value)*100,value<0 ? "L":"R")
        default:return String(format:"%0.0f%%",value*100)
        }
    }
}
enum MotionShapes {
    static let names=["Swell","Fade Out","Triangle","Sine","Pulse","Pluck","Double Swell","Staircase","Descending Steps","Heartbeat","Bounce","Ripple","Duck & Rise","Ratchet","Bloom","Sample & Hold"]
    static func points(_ name:String)->[MotionPoint] {
        func p(_ x:Double,_ y:Double,_ c:Double=0)->MotionPoint{MotionPoint(x:x,y:y,curve:c)}
        switch name {
        case "Fade Out":return [p(0,1,0.35),p(1,0)]
        case "Triangle":return [p(0,0),p(0.5,1),p(1,0)]
        case "Sine":return (0...12).map{p(Double($0)/12,(1-cos(Double($0)/12*2*Double.pi))/2)}
        case "Pulse":return [p(0,1),p(0.49,1),p(0.5,0),p(0.99,0),p(1,1)]
        case "Pluck":return [p(0,0),p(0.025,1,-0.6),p(0.6,0.05),p(1,0)]
        case "Double Swell":return [p(0,0,0.2),p(0.35,1),p(0.5,0.15,0.2),p(0.85,1),p(1,0)]
        case "Staircase":return [p(0,0),p(0.24,0),p(0.25,0.33),p(0.49,0.33),p(0.5,0.66),p(0.74,0.66),p(0.75,1),p(1,1)]
        case "Descending Steps":return points("Staircase").map{p($0.x,1-$0.y)}
        case "Heartbeat":return [p(0,0),p(0.12,1),p(0.22,0),p(0.32,0.65),p(0.44,0),p(1,0)]
        case "Bounce":return [p(0,1,-0.4),p(0.3,0),p(0.43,0.65,-0.4),p(0.65,0),p(0.75,0.35,-0.4),p(0.9,0),p(0.95,0.12),p(1,0)]
        case "Ripple":return [p(0,0.5),p(0.14,0.8),p(0.28,0.3),p(0.42,1),p(0.56,0.1),p(0.70,0.75),p(0.84,0.35),p(1,0.5)]
        case "Duck & Rise":return [p(0,1),p(0.06,0.05,0.4),p(0.8,1),p(1,1)]
        case "Ratchet":return [p(0,0),p(0.02,1,-0.4),p(0.24,0),p(0.25,0),p(0.27,0.85,-0.4),p(0.49,0),p(0.5,0),p(0.52,0.7,-0.4),p(0.74,0),p(0.75,0),p(0.77,0.55,-0.4),p(1,0)]
        case "Bloom":return [p(0,0,0.55),p(0.48,0.85,-0.4),p(0.65,1),p(0.78,1,0.45),p(1,0)]
        case "Sample & Hold":return [p(0,0.25),p(0.15,0.25),p(0.16,0.9),p(0.32,0.9),p(0.33,0.4),p(0.49,0.4),p(0.5,0.7),p(0.65,0.7),p(0.66,0.1),p(0.82,0.1),p(0.83,1),p(0.99,1),p(1,0.25)]
        default:return [p(0,0,-0.25),p(1,1)]
        }
    }
}
@MainActor final class MotionEditorState:ObservableObject {
    @Published var selected=0
    @Published var destination=0
    @Published var dragging=false
    @Published var shapeName="My shape"
    @Published var libraryID:String?=nil
}
@MainActor final class MotionTelemetry:ObservableObject {
    @Published var phases=[Float](repeating:-1,count:4)
    func update(){let next=(0..<4).map{(aurora_motion_phase(Int32($0))*300).rounded()/300};if next != phases{phases=next}}
}
extension SynthModel {
    var motionSettings:MotionSettings{patch.motion?[selectedLayer] ?? MotionSettings()}
    func changeMotion(_ change:(inout MotionSettings)->Void){
        finishComparison()
        var values=patch.motion ?? Array(repeating:MotionSettings(),count:4)
        change(&values[selectedLayer]);guard values[selectedLayer].valid else{return}
        patch.motion=values;applyMotion();dirty=true
    }
    func applyMotion(){
        for layer in 0..<4 {let data=(patch.motion?[layer] ?? MotionSettings()).packet
            _=data.withUnsafeBufferPointer{aurora_set_motion(Int32(layer),$0.baseAddress,Int32($0.count))}
        }
    }
}
struct MotionPlayhead:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var telemetry:MotionTelemetry
    let layer:Int
    var body:some View {
        GeometryReader { g in
            if telemetry.phases[layer]>=0 {Rectangle().fill(Color.white.opacity(0.65)).frame(width:1).offset(x:CGFloat(telemetry.phases[layer])*g.size.width)}
        }.allowsHitTesting(false)
    }
}
struct MotionGraph:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @ObservedObject var editor:MotionEditorState
    var settings:MotionSettings{m.motionSettings}
    func graphY(_ value:Double)->Double {
        let route=settings.routes[editor.destination],range=MotionSettings.ranges[editor.destination]
        let value=route.inverted ? 1-value:value
        if editor.destination==1 {return log(route.minimum/range.lowerBound)/log(range.upperBound/range.lowerBound)+value*log(route.maximum/route.minimum)/log(range.upperBound/range.lowerBound)}
        return (route.minimum+(route.maximum-route.minimum)*value-range.lowerBound)/(range.upperBound-range.lowerBound)
    }
    func rawY(_ y:Double)->Double {
        let lo=graphY(0),hi=graphY(1)
        return abs(hi-lo)<0.00001 ? 0.5:max(0,min(1,(y-lo)/(hi-lo)))
    }
    var body:some View {
        GeometryReader { g in
            ZStack(alignment:.topLeading){
                Canvas { context,size in
                    var grid=Path()
                    let divisions=max(4,settings.grid ?? 4)
                    for i in 0...divisions{let x=size.width*Double(i)/Double(divisions);grid.move(to:CGPoint(x:x,y:0));grid.addLine(to:CGPoint(x:x,y:size.height))}
                    for i in 0...4{let y=size.height*Double(i)/4;grid.move(to:CGPoint(x:0,y:y));grid.addLine(to:CGPoint(x:size.width,y:y))}
                    context.stroke(grid,with:.color(.white.opacity(0.08)),lineWidth:1)
                    var path=Path()
                    for i in 0...256 {let x=Double(i)/256,point=CGPoint(x:x*size.width,y:(1-graphY(settings.shape(x)))*size.height);if i==0{path.move(to:point)}else{path.addLine(to:point)}}
                    context.stroke(path,with:.color(palette.graphPink.opacity(0.15)),lineWidth:8)
                    context.stroke(path,with:.linearGradient(Gradient(colors:[palette.graphPink,palette.graphCyan]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:0)),style:StrokeStyle(lineWidth:2.5,lineJoin:.round))
                }.contentShape(Rectangle()).gesture(SpatialTapGesture(count:2).onEnded{event in
                    guard settings.points.count<16 else{return}
                    let x=settings.snapped(max(0,min(1,event.location.x/g.size.width)))
                    guard settings.points.allSatisfy({abs($0.x-x)>0.002}) else{return}
                    m.checkpoint();m.changeMotion{$0.points.append(MotionPoint(x:x,y:rawY(1-event.location.y/g.size.height)));$0.points.sort{$0.x<$1.x}}
                    editor.selected=settings.points.firstIndex(where:{abs($0.x-x)<0.00001}) ?? 0
                })
                MotionPlayhead(telemetry:m.motionTelemetry,layer:m.selectedLayer)
                ForEach(settings.points.indices,id:\.self){i in
                    Circle().fill(editor.selected==i ? Color.white:palette.graphPink).frame(width:12,height:12)
                        .frame(width:24,height:24).contentShape(Rectangle())
                        .position(x:settings.points[i].x*g.size.width,y:(1-graphY(settings.points[i].y))*g.size.height)
                        .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("motionGraph")).onChanged{event in
                            if !editor.dragging{m.checkpoint();editor.dragging=true};editor.selected=i
                            m.changeMotion{settings in
                                if i>0 && i<settings.points.count-1 {settings.points[i].x=max(settings.points[i-1].x+0.001,min(settings.points[i+1].x-0.001,settings.snapped(event.location.x/g.size.width)))}
                                settings.points[i].y=rawY(1-event.location.y/g.size.height)
                            }
                        }.onEnded{_ in editor.dragging=false})
                        .accessibilityLabel("Envelope point \(i+1)")
                        .accessibilityValue(String(format:"%0.2f seconds, %0.0f percent",settings.points[i].x*settings.seconds,settings.points[i].y*100))
                }
            }.coordinateSpace(name:"motionGraph")
        }.frame(height:190).padding(12).background(palette.graphBackground,in:RoundedRectangle(cornerRadius:8))
    }
}
struct MotionRouteCard:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @ObservedObject var editor:MotionEditorState
    let index:Int
    var route:MotionRoute{m.motionSettings.routes[index]}
    func rangeBinding(_ minimum:Bool)->Binding<Double>{Binding(get:{minimum ? route.minimum:route.maximum},set:{value in m.changeMotion{settings in if minimum{settings.routes[index].minimum=min(value,route.maximum)}else{settings.routes[index].maximum=max(value,route.minimum)}}})}
    var body:some View {
        VStack(spacing:10){
            HStack {
                Toggle(MotionSettings.names[index],isOn:Binding(get:{route.enabled},set:{value in m.checkpoint();m.changeMotion{$0.routes[index].enabled=value};editor.destination=index})).toggleStyle(.checkbox).font(.system(size:14,weight:palette.weight(.medium)))
                Spacer(minLength:2)
                Button{m.checkpoint();m.changeMotion{$0.routes[index].inverted.toggle()}}label:{Image(systemName:"arrow.up.arrow.down").foregroundStyle(route.inverted ? palette.selectedText:Color.white)}.buttonStyle(AuroraIconButtonStyle(selected:route.inverted)).help("Reverse this destination's movement")
            }
            ParameterSlider(title:"Minimum",value:rangeBinding(true),range:MotionSettings.ranges[index],logarithmic:index==1,format:{MotionSettings.formatted($0,index)},onBegin:{m.checkpoint();editor.destination=index})
            ParameterSlider(title:"Maximum",value:rangeBinding(false),range:MotionSettings.ranges[index],logarithmic:index==1,format:{MotionSettings.formatted($0,index)},onBegin:{m.checkpoint();editor.destination=index})
        }.padding(12).background(palette.raised.opacity(0.5),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(editor.destination==index ? palette.accent.opacity(0.6):.clear))
            .contentShape(Rectangle()).onTapGesture{editor.destination=index}
    }
}
struct MotionEnvelopePanel:View {
    @Environment(\.auroraPalette) private var palette
    @ObservedObject var m:SynthModel
    @StateObject private var editor=MotionEditorState()
    var settings:MotionSettings{m.motionSettings}
    var selected:Int{min(editor.selected,settings.points.count-1)}
    var controls:some View {
        VStack(alignment:.leading,spacing:12){
            HStack {
                Toggle("Enabled",isOn:Binding(get:{settings.enabled},set:{v in m.checkpoint();m.changeMotion{$0.enabled=v}})).toggleStyle(.switch).tint(palette.accent)
                Toggle("Loop",isOn:Binding(get:{settings.loop},set:{v in m.checkpoint();m.changeMotion{$0.loop=v}})).toggleStyle(.checkbox)
                Spacer()

            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:8),spacing:6){ForEach(MotionShapes.names,id:\.self){name in
                let active=settings.points==MotionShapes.points(name)
                Button{m.checkpoint();m.changeMotion{$0.points=MotionShapes.points(name)};editor.selected=0;editor.libraryID=nil}label:{
                    Text(name).font(.system(size:13,weight:active ? .bold:.regular)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth:.infinity).padding(.vertical,7)
                        .background(active ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:6)).foregroundStyle(active ? palette.selectedText:Color.white)
                }.buttonStyle(AuroraFlatButtonStyle(selected:active)).accessibilityLabel("Factory shape · \(name)").accessibilityAddTraits(active ? .isSelected:[])
            }}
            ParameterSlider(title:"Duration",value:Binding(get:{settings.seconds},set:{v in m.changeMotion{$0.seconds=v}}),range:0.1...60,logarithmic:true,format:{String(format:"%0.2f s",$0)},onBegin:{m.checkpoint()})
                .disabled(settings.beats != nil)
            HStack{
                Toggle("Tempo sync",isOn:Binding(get:{settings.beats != nil},set:{value in m.checkpoint();m.changeMotion{$0.beats=value ? 4:nil}})).toggleStyle(.checkbox)
                if settings.beats != nil {Picker("Length",selection:Binding(get:{settings.beats ?? 4},set:{value in m.checkpoint();m.changeMotion{$0.beats=value}})){ForEach([0.25,0.5,1,2,4,8,16,32],id:\.self){beats in Text(beats>=4 ? "\(Int(beats/4)) bar\(beats==4 ? "":"s") (4/4)":"\(beats.formatted()) beats").tag(beats)}}}
                Picker("Snap",selection:Binding(get:{settings.grid ?? 0},set:{v in m.checkpoint();m.changeMotion{$0.grid=v}})){Text("Off").tag(0);ForEach([4,8,16,32],id:\.self){Text("\($0) divisions").tag($0)}}
            }.font(.system(size:14,weight:palette.weight(.regular)))
            HStack{
                Picker("Graph",selection:$editor.destination){ForEach(0..<8){Text(MotionSettings.names[$0]).tag($0)}}
                Text(settings.beats.map{"0 → \($0.formatted()) beats"} ?? "0 → \(String(format:"%0.1f",settings.seconds)) s").foregroundStyle(palette.muted).monospacedDigit()
            }.font(.system(size:14,weight:palette.weight(.regular)))
        }
    }
    var pointControls:some View {
        HStack(spacing:18){
            ParameterSlider(title:selected==0 ? "Starting level":"Point \(selected+1) · level",value:Binding(get:{settings.points[selected].y},set:{v in m.changeMotion{$0.points[selected].y=v}}),format:{MotionSettings.formatted(settings.value($0,destination:editor.destination),editor.destination)},onBegin:{m.checkpoint()})
            ParameterSlider(title:"Curve to next point",value:Binding(get:{settings.points[selected].curve},set:{v in m.changeMotion{$0.points[selected].curve=v}}),range:-1...1,format:{String(format:"%+0.2f",$0)},onBegin:{m.checkpoint()}).disabled(selected==settings.points.count-1)
            Button("Delete point"){m.checkpoint();m.changeMotion{$0.points.remove(at:selected)};editor.selected=0}.disabled(selected==0 || selected==settings.points.count-1)
        }
    }
    var destinations:some View {
        VStack(alignment:.leading,spacing:12){
            Text("Destinations · select a control to adjust its range").font(.system(size:14,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:2),spacing:8){ForEach(0..<8){i in
                Button{editor.destination=i}label:{
                    HStack{Circle().fill(settings.routes[i].enabled ? palette.accent:palette.muted.opacity(0.3)).frame(width:6,height:6);Text(MotionSettings.names[i]);Spacer()}
                        .font(.system(size:14,weight:editor.destination==i ? .bold:.regular)).padding(10).frame(maxWidth:.infinity)
                        .background(editor.destination==i ? palette.buttonSelected:palette.buttonSurface,in:RoundedRectangle(cornerRadius:6))
                }.foregroundStyle(editor.destination==i ? palette.selectedText:Color.white).buttonStyle(AuroraFlatButtonStyle(selected:editor.destination==i)).accessibilityLabel("Edit \(MotionSettings.names[i]) envelope range")
            }}
        }
    }
    var body:some View {
        Panel(title:"Motion envelope · layer \(layerLetters[m.selectedLayer])"){
            controls
            HStack{
                Menu("My shapes (\(m.savedShapes.count))"){ForEach(m.savedShapes){shape in Button(shape.name){m.checkpoint();m.changeMotion{$0.points=shape.points};editor.selected=0;editor.libraryID=shape.id;editor.shapeName=shape.name}}}
                TextField("Shape name",text:$editor.shapeName).textFieldStyle(.roundedBorder)
                Button("Save new"){m.saveShape(name:editor.shapeName)}
                Button("Update"){if let id=editor.libraryID{m.saveShape(name:editor.shapeName,replacing:id)}}.disabled(editor.libraryID==nil)
                Button("Delete"){if let id=editor.libraryID{m.deleteShape(id);editor.libraryID=nil}}.disabled(editor.libraryID==nil)
            }.font(.system(size:13,weight:palette.weight(.regular)))
            MotionGraph(m:m,editor:editor)
            HStack{Text(MotionSettings.formatted(settings.routes[editor.destination].minimum,editor.destination));Spacer();Text("Drag points · double-click to add · select a point to bend its curve");Spacer();Text(MotionSettings.formatted(settings.routes[editor.destination].maximum,editor.destination))}.font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted)
            pointControls
            HStack(alignment:.top,spacing:18){destinations.frame(maxWidth:.infinity);MotionRouteCard(m:m,editor:editor,index:editor.destination).frame(width:320)}
            Text("Each note starts its own shape. Once holds the final value; Loop repeats while held. Volume replaces the attack/decay/sustain envelope; Release still fades notes out. Other destinations replace their base value; existing modulation still adds movement. Wavetable destinations require that oscillator's Wavetable mode; Warp also needs Bend, Sync or Fold.").font(.system(size:12,weight:palette.weight(.regular))).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
}
