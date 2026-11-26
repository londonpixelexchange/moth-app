// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import TOMLKit

/// Named, portable appearance and session defaults. App-wide controls stay in config.toml.
struct TerminalProfile: Codable {
    var version = 1
    var id = UUID().uuidString
    var name: String
    var theme: String = "system"
    var fontName: String = Configuration.defaultFontName
    var fontSize: Double = 14
    var typography: Configuration.Typography = Configuration.Typography()
    var ansiColors: [String] = []
    var palette: Configuration.Palette? = nil
    var window: Configuration.Window = Configuration.Window()
    var background: Configuration.Background = Configuration.Background()
    var cursor: Configuration.Cursor = Configuration.Cursor()
    var bell: Configuration.Bell = Configuration.Bell()
    var keyboardSound: Configuration.KeyboardSound = Configuration.KeyboardSound()
    var scrollback: Int = 10000
    var alternateScreenScrollback: Bool = true
    var shell: String = "/bin/zsh"
    var optionAsMeta: Bool = false
    var alwaysRepeatHeldKeys = false
    var closeOnExit: Bool = true
    var textEncoding = "UTF-8"
    var loginShell: Bool = true
    var workingDirectory: String = ""
    var inheritWorkingDirectory = true
    var environment: [String:String] = [:]
    init(name: String,configuration: Configuration) {
        self.name = name
        theme = configuration.theme
        fontName = configuration.fontName
        fontSize = configuration.fontSize
        typography = configuration.typography
        ansiColors = configuration.ansiColors
        palette = configuration.palette
        window = configuration.window
        background = configuration.background
        cursor = configuration.cursor
        bell = configuration.bell
        keyboardSound = configuration.keyboardSound
        scrollback = configuration.scrollback
        alternateScreenScrollback = configuration.alternateScreenScrollback
        shell = configuration.shell
        optionAsMeta = configuration.optionAsMeta
        alwaysRepeatHeldKeys = configuration.alwaysRepeatHeldKeys
        closeOnExit = configuration.closeOnExit
        textEncoding = configuration.textEncoding
        loginShell = configuration.advanced.loginShell
        workingDirectory = configuration.advanced.workingDirectory
        inheritWorkingDirectory = configuration.advanced.inheritWorkingDirectory
        environment = configuration.advanced.environment
    }
    init(from decoder: Decoder) throws {
        self.init(name:"",configuration:Configuration())
        let c = try decoder.container(keyedBy:CodingKeys.self)
        version = try c.decodeIfPresent(Int.self,forKey:.version) ?? 1
        id = try c.decode(String.self,forKey:.id)
        name = try c.decode(String.self,forKey:.name)
        theme = try c.decodeIfPresent(String.self,forKey:.theme) ?? theme
        fontName = try c.decodeIfPresent(String.self,forKey:.fontName) ?? fontName
        if fontName == "WumpusMonoNFM" { fontName = Configuration.defaultFontName }
        if c.contains(.fontSize) { if let integer = try? c.decode(Int.self,forKey:.fontSize) { fontSize = Double(integer) } else { fontSize = try c.decode(Double.self,forKey:.fontSize) } }
        typography = try c.decodeIfPresent(Configuration.Typography.self,forKey:.typography) ?? typography
        ansiColors = try c.decodeIfPresent([String].self,forKey:.ansiColors) ?? ansiColors
        palette = try c.decodeIfPresent(Configuration.Palette.self,forKey:.palette)
        window = try c.decodeIfPresent(Configuration.Window.self,forKey:.window) ?? window
        background = try c.decodeIfPresent(Configuration.Background.self,forKey:.background) ?? background
        cursor = try c.decodeIfPresent(Configuration.Cursor.self,forKey:.cursor) ?? cursor
        bell = try c.decodeIfPresent(Configuration.Bell.self,forKey:.bell) ?? bell
        keyboardSound = try c.decodeIfPresent(Configuration.KeyboardSound.self,forKey:.keyboardSound) ?? keyboardSound
        scrollback = try c.decodeIfPresent(Int.self,forKey:.scrollback) ?? scrollback
        alternateScreenScrollback = try c.decodeIfPresent(Bool.self,forKey:.alternateScreenScrollback) ?? alternateScreenScrollback
        shell = try c.decodeIfPresent(String.self,forKey:.shell) ?? shell
        optionAsMeta = try c.decodeIfPresent(Bool.self,forKey:.optionAsMeta) ?? optionAsMeta
        alwaysRepeatHeldKeys = try c.decodeIfPresent(Bool.self,forKey:.alwaysRepeatHeldKeys) ?? false
        closeOnExit = try c.decodeIfPresent(Bool.self,forKey:.closeOnExit) ?? closeOnExit
        textEncoding = try c.decodeIfPresent(String.self,forKey:.textEncoding) ?? "UTF-8"
        loginShell = try c.decodeIfPresent(Bool.self,forKey:.loginShell) ?? loginShell
        workingDirectory = try c.decodeIfPresent(String.self,forKey:.workingDirectory) ?? workingDirectory
        inheritWorkingDirectory = try c.decodeIfPresent(Bool.self,forKey:.inheritWorkingDirectory) ?? true
        environment = try c.decodeIfPresent([String:String].self,forKey:.environment) ?? environment
    }
    func applying(to base: Configuration) -> Configuration {
        var result = base
        result.theme = theme
        result.fontName = fontName
        result.fontSize = fontSize
        result.typography = typography
        result.ansiColors = ansiColors
        result.palette = palette
        result.window = window
        result.background = background
        result.cursor = cursor
        result.bell = bell
        result.keyboardSound = keyboardSound
        result.scrollback = scrollback
        result.alternateScreenScrollback = alternateScreenScrollback
        result.shell = shell
        result.optionAsMeta = optionAsMeta
        result.alwaysRepeatHeldKeys = alwaysRepeatHeldKeys
        result.closeOnExit = closeOnExit
        result.textEncoding = textEncoding
        result.advanced.loginShell = loginShell
        result.advanced.workingDirectory = workingDirectory
        result.advanced.inheritWorkingDirectory = inheritWorkingDirectory
        result.advanced.environment = environment
        return result
    }
    func validate(base: Configuration) throws {
        guard version == 1,UUID(uuidString:id) != nil,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 80,!name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else { throw Configuration.invalid("Profiles need a name (up to 80 characters), valid ID and supported version.") }
        try applying(to:base).validate()
    }
}

enum ProfileStore {
    static var directory: URL { Configuration.url.deletingLastPathComponent().appendingPathComponent("Profiles",isDirectory:true) }
    static func url(_ id: String,in directory: URL = directory) -> URL { directory.appendingPathComponent(id+".toml") }
    static func files(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []).filter { $0.pathExtension.lowercased() == "toml" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func load(_ file: URL,base: Configuration) throws -> TerminalProfile {
        let data = try Data(contentsOf:file); guard data.count <= 262144 else { throw Configuration.invalid("Profile exceeds 256 KB.") }
        let profile = try TOMLDecoder().decode(TerminalProfile.self,from:String(decoding:data,as:UTF8.self))
        guard profile.id == file.deletingPathExtension().lastPathComponent else { throw Configuration.invalid("The profile ID must match its file name.") }
        var result = profile; if result.palette?.enabled == false { result.palette = nil }
        try result.validate(base:base); return result
    }
    static func save(_ profile: TerminalProfile,base: Configuration,in directory: URL = directory) throws {
        try profile.validate(base:base)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file = url(profile.id,in:directory), desired: TOMLTable = try TOMLEncoder().encode(profile)
        let text: String
        if FileManager.default.fileExists(atPath:file.path) {
            let old = try String(contentsOf:file,encoding:.utf8)
            if profile.palette == nil,try TOMLDocument.parse(old)["palette"] != nil { desired["palette"] = TOMLTable(["enabled":false]) }
            text = try TOMLDocument.updating(old,with:desired)
        }
        else { text = "# Moth profile — appearance and session defaults. Edits reload live.\n# Keyboard shortcuts, macros and other app-wide preferences live in config.toml.\n\n"+TOMLDocument.render(desired) }
        try TOMLDocument.write(text,to:file)
    }
    static func remove(_ id: String,in directory: URL = directory) throws {
        guard UUID(uuidString:id) != nil else { throw Configuration.invalid("Invalid profile ID.") }
        let file = url(id,in:directory)
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        let backup = file.appendingPathExtension("before-delete-"+UUID().uuidString.prefix(6))
        try Data(contentsOf:file).write(to:backup,options:.atomic)
        try FileManager.default.removeItem(at:file)
    }
    static func archiveAll(in directory: URL = directory) throws {
        guard FileManager.default.fileExists(atPath:directory.path) else { return }
        try FileManager.default.moveItem(at:directory,to:directory.appendingPathExtension("before-reset-"+UUID().uuidString.prefix(6)))
    }
}

/// Observe edits inside existing files as well as file creation, deletion and atomic saves.
final class ProfilesWatcher {
    private var timer: Timer?
    private var fingerprint: String
    var changed: (() -> Void)?
    init(directory: URL) {
        func signature() -> String {
            ProfileStore.files(in:directory).map { file in
                let a = (try? FileManager.default.attributesOfItem(atPath:file.path)) ?? [:]
                return file.lastPathComponent+":"+String(describing:a[.systemFileNumber])+":"+String((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)+":"+String(describing:a[.size])
            }.joined(separator:"|")
        }
        fingerprint = signature()
        timer = Timer.scheduledTimer(withTimeInterval:0.6,repeats:true) { [weak self] _ in
            guard let self else { return }; let next = signature()
            if next != self.fingerprint { self.fingerprint = next; self.changed?() }
        }
    }
    deinit { timer?.invalidate() }
}

extension App {
    func profile(_ id: String?) -> TerminalProfile? { profiles.first { $0.id == id } }
    func settings(for id: String?) -> Configuration { profile(id)?.applying(to:config) ?? config }
    func reloadProfiles() {
        var loaded: [TerminalProfile] = [], errors: [String] = []
        let files = ProfileStore.files(in:profileDirectory)
        if files.count > 64 { profileError = Configuration.invalid("Up to 64 profiles are supported."); return }
        for file in files {
            do { loaded.append(try ProfileStore.load(file,base:config)) }
            catch { errors.append(file.lastPathComponent+": "+error.localizedDescription); if let old = profiles.first(where: { $0.id == file.deletingPathExtension().lastPathComponent }) { loaded.append(old) } }
        }
        profiles = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        profileError = errors.isEmpty ? nil : Configuration.invalid(errors.joined(separator:"\n"))
    }
    func saveSettings(_ candidate: Configuration,profileID: String?) throws {
        try candidate.validate()
        if let current = profile(profileID) {
            var next = TerminalProfile(name:current.name,configuration:candidate); next.id = current.id
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            if try encoder.encode(next) != encoder.encode(current) { try ProfileStore.save(next,base:config,in:profileDirectory) }
            // These controls belong to the app even when editing a named profile.
            var global = config
            global.keybindings = candidate.keybindings; global.macros = candidate.macros; global.closeConfirmation = candidate.closeConfirmation
            global.enabledEncodings = candidate.enabledEncodings
            global.updates = candidate.updates
            global.lookup = candidate.lookup
            global.showLayoutsOnLaunch = candidate.showLayoutsOnLaunch; global.defaultProfileID = candidate.defaultProfileID
            global.advanced.sessionRecovery = candidate.advanced.sessionRecovery
            global.advanced.allowDoubleSizeLines = candidate.advanced.allowDoubleSizeLines
            global.advanced.logDirectory = candidate.advanced.logDirectory; global.advanced.allowRemoteClipboard = candidate.advanced.allowRemoteClipboard; global.advanced.copyOnSelect = candidate.advanced.copyOnSelect
            if try Configuration.document(global) != Configuration.document(config) { try Configuration.save(global); config = global }
            reloadProfiles()
        } else { try Configuration.save(candidate); config = candidate }
        configError = nil; applyAppearance(); buildMenu()
    }
    func changeActiveSettings(_ edit: (inout Configuration)->Void) {
        var candidate = active?.baseConfiguration ?? config; edit(&candidate)
        // A window whose profile file was removed is deliberately detached.
        // Keep edits local instead of accidentally replacing Default's settings.
        if let active,let id = active.profileID,profile(id) == nil {
            var snapshot = TerminalProfile(name:active.profileSnapshot?.name ?? "Removed profile",configuration:candidate); snapshot.id = id
            active.profileSnapshot = snapshot; active.applyAppearance(); buildMenu(); return
        }
        do { try saveSettings(candidate,profileID:active?.profileID) } catch { showError(error) }
    }
    @objc func newProfileWindow(_ sender: NSMenuItem) { openWindow(profileID:sender.representedObject as? String) }
    func openWindow(profileID: String?) {
        let controller = TerminalWindowController(application:self,profileID:profileID)
        windows.append(controller); controller.window?.setFrameOrigin(NSPoint(x:120+(windows.count-1)%6*28,y:100+(windows.count-1)%6*28))
        controller.presentAndFocus()
    }
    @objc func assignWindowProfile(_ sender: NSMenuItem) {
        guard let window = active else { return }; window.profileID = profile(sender.representedObject as? String)?.id; window.profileSnapshot = profile(window.profileID); window.zoomFontSize = nil; window.applyAppearance(); buildMenu()
    }
    @objc func changeTextEncoding(_ sender: NSMenuItem) { changeActiveSettings { $0.textEncoding = sender.representedObject as! String } }
    @objc func showProfiles(_ sender: Any?) { showSettings(nil); appearancePanel?.tabs.selectTabViewItem(withIdentifier:"Profiles") }
}
