import SwiftUI
import AppKit
import Darwin

final class AuroraBundleMarker:NSObject {}
enum AuroraResources {static let bundle=Bundle(for:AuroraBundleMarker.self)}

extension SynthModel {
    private struct PluginMappings:Codable {var mappings:[CCMapping];var directMappings:[DirectCCMapping]}
    func commitPluginMappings(){
#if AURORA_PLUGIN
        guard !syncingPlugin else{return}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard let data=try? encoder.encode(PluginMappings(mappings:mappings,directMappings:directMappings)),data != lastPluginMappingsData,let json=String(data:data,encoding:.utf8) else{return}
        aurora_plugin_set_mappings(backend.context,json);lastPluginMappingsData=data
#endif
    }
    struct PluginLibrary:Codable {
        var presets:[SoundPreset];var favorites:Set<String>;var deleted:[SoundPreset]
        static func merge(_ local:Self,baseline:Self,latest:Self)throws->Self {
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            func sounds(_ local:[SoundPreset],_ old:[SoundPreset],_ disk:[SoundPreset])throws->[SoundPreset]{
                let removed=Set(old.map(\.id)).subtracting(local.map(\.id))
                var result=disk.filter{!removed.contains($0.id)}
                for sound in local {
                    let previous=old.first{$0.id==sound.id}
                    if try previous.map({try encoder.encode($0)}) != encoder.encode(sound){
                        if let index=result.firstIndex(where:{$0.id==sound.id}){result[index]=sound}else{result.append(sound)}
                    }
                }
                return result
            }
            return try Self(presets:sounds(local.presets,baseline.presets,latest.presets),favorites:latest.favorites.subtracting(baseline.favorites.subtracting(local.favorites)).union(local.favorites.subtracting(baseline.favorites)),deleted:sounds(local.deleted,baseline.deleted,latest.deleted))
        }
    }
    func restorePluginLibrary(){
        if let data=try? Data(contentsOf:folder.appendingPathComponent("plugin-library.json")),let library=try? JSONDecoder().decode(PluginLibrary.self,from:data){
            userPresets=library.presets.compactMap{Self.sanitized($0)};favorites=library.favorites;deletedPresets=library.deleted.compactMap{Self.sanitized($0)};lastPresetData=data
        }else{
            if let data=try? Data(contentsOf:folder.appendingPathComponent("presets.json")),let list=try? JSONDecoder().decode([SoundPreset].self,from:data){userPresets=list.compactMap{Self.sanitized($0)}}
            if let data=try? Data(contentsOf:folder.appendingPathComponent("session.json")),let session=try? JSONDecoder().decode(SavedSession.self,from:data){favorites=session.favorites}
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            lastPresetData=try? encoder.encode(PluginLibrary(presets:userPresets,favorites:favorites,deleted:deletedPresets))
        }
    }
    func persistPluginLibrary(){
        commitPluginMappings()
        do{
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            let local=PluginLibrary(presets:userPresets,favorites:favorites,deleted:deletedPresets)
            let data=try encoder.encode(local)
            guard data != lastPresetData else{return}
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let lock=open(folder.appendingPathComponent("plugin-library.lock").path,O_CREAT|O_RDWR,0o600)
            guard lock >= 0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            defer{flock(lock,LOCK_UN);close(lock)}
            guard flock(lock,LOCK_EX)==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            let url=folder.appendingPathComponent("plugin-library.json")
            let decoder=JSONDecoder()
            let baseline=lastPresetData.flatMap{try? decoder.decode(PluginLibrary.self,from:$0)} ?? PluginLibrary(presets:[],favorites:[],deleted:[])
            let latest=(try? Data(contentsOf:url)).flatMap{try? decoder.decode(PluginLibrary.self,from:$0)} ?? baseline
            let merged=try PluginLibrary.merge(local,baseline:baseline,latest:latest)
            let saved=try encoder.encode(merged)
            try saved.write(to:url,options:.atomic);lastPresetData=saved
            userPresets=merged.presets;favorites=merged.favorites;deletedPresets=merged.deleted
        }catch{notice="Couldn't save your plug-in sound library: \(error.localizedDescription)"}
    }
    func pluginMetadataChanged(_ old:SoundPreset){
#if AURORA_PLUGIN
        guard !syncingPlugin,backend.isPlugin else{return}
        if old.id != patch.id || old.name != patch.name || old.category != patch.category || old.detail != patch.detail || old.motion != patch.motion || old.sends != patch.sends || old.soundMatrix != patch.soundMatrix || old.performanceMatrix != patch.performanceMatrix || old.customMacros != patch.customMacros || old.xy != patch.xy || old.importedWavetables != patch.importedWavetables {
            commitPluginPatch(apply:false)
        }
#endif
    }
    func commitPluginPatch(apply:Bool){
#if AURORA_PLUGIN
        guard !syncingPlugin,let context=backend.context,let data=try? JSONEncoder().encode(patch),let json=String(data:data,encoding:.utf8) else{return}
        aurora_plugin_patch_set(context,json,apply ? 1:0)
#endif
    }
    func syncPlugin(){
#if AURORA_PLUGIN
        guard let context=backend.context else{return}
        let revision=aurora_plugin_revision(context)
        guard revision != lastPluginRevision,let pointer=aurora_plugin_patch(context),let data=String(cString:pointer).data(using:.utf8),let decoded=try? JSONDecoder().decode(SoundPreset.self,from:data) else{return}
        syncingPlugin=true;patch=decoded
        transpose=Int(aurora_plugin_control(context,2012));holding=aurora_plugin_control(context,2013)>0.5
        outputGain=aurora_plugin_control(context,2040)
        routes[1]=SourceRoute(mask:Int(aurora_plugin_control(context,2030)),channel:Int(aurora_plugin_control(context,2031)),velocityCurve:Int(aurora_plugin_control(context,2032)))
        if let pointer=aurora_plugin_mappings(context),let data=String(cString:pointer).data(using:.utf8),let settings=try? JSONDecoder().decode(PluginMappings.self,from:data){
            mappings=settings.mappings;directMappings=settings.directMappings
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];lastPluginMappingsData=try? encoder.encode(settings)
        }
        syncingPlugin=false;lastPluginRevision=revision
#endif
    }
}

#if AURORA_PLUGIN
@MainActor final class AuroraPluginHostingView:NSHostingView<ContentView> {
    let model:SynthModel
    init(context:UnsafeMutableRawPointer){
        model=SynthModel(backend:AuroraBackend(context:context))
        super.init(rootView:ContentView(m:model))
        frame=NSRect(x:0,y:0,width:1280,height:820)
        autoresizingMask=[.width,.height]
    }
    required init(rootView:ContentView){fatalError("Use init(context:)")}
    required init?(coder:NSCoder){fatalError("Use init(context:)")}
}
@_cdecl("aurora_create_editor")
func createAuroraEditor(_ context:UnsafeMutableRawPointer)->UnsafeMutableRawPointer {
    let address=MainActor.assumeIsolated {UInt(bitPattern:Unmanaged.passRetained(AuroraPluginHostingView(context:context)).toOpaque())}
    return UnsafeMutableRawPointer(bitPattern:address)!
}
@_cdecl("aurora_destroy_editor")
func destroyAuroraEditor(_ pointer:UnsafeMutableRawPointer){
    MainActor.assumeIsolated {
        let view=Unmanaged<AuroraPluginHostingView>.fromOpaque(pointer).takeRetainedValue()
        view.model.shutdown();view.removeFromSuperview()
    }
}
#endif
