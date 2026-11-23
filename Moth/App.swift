// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import SwiftTerm

@main
final class App: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var keepingSessions = false
    var shuttingDown = false
    var recoveryTimer: Timer?
    var recoveryError: Error?
    var config = Configuration()
    var profiles: [TerminalProfile] = []
    var profileDirectory = ProfileStore.directory
    var profileError: Error?
    private var profilesWatcher: ProfilesWatcher?
    var appearancePanel: AppearancePanel?
    var layoutChooser: WindowLayoutChooser?
    var aboutWindow: AboutWindowController?
    var releaseNotesWindow: ReleaseNotesWindowController?
    let updateChecker = UpdateChecker()
    weak var lastTerminalWindow: TerminalWindowController?
    private(set) var bellCount = 0
    func recordBell() {
        bellCount = bellCount == Int.max ? Int.max : bellCount + 1
        NSApp.dockTile.badgeLabel = String(bellCount)
    }
    @objc func clearBellBadge(_ sender: Any?) { bellCount = 0; NSApp.dockTile.badgeLabel = nil }
    func applicationDidBecomeActive(_ notification: Notification) { clearBellBadge(nil); updateSecureInput(); ((NSApp.keyWindow?.windowController as? TerminalWindowController) ?? windows.last(where: { $0.pendingInitialFocus }))?.finishInitialFocus() }
    func applicationDidResignActive(_ notification: Notification) { updateSecureInput() }
    func applicationWillTerminate(_ notification: Notification) { shuttingDown = true; recoveryTimer?.invalidate(); appearancePanel?.flushAudioEdits(); if let fullscreenKeyMonitor { NSEvent.removeMonitor(fullscreenKeyMonitor) }; secureKeyboardEntry = false; updateSecureInput(); macroPlayer.stop(); MacroRecorder.shared.cancel() }
    @objc func resetTerminal(_ sender: Any?) {
        guard let pane = active?.workspace.active else { return }
        pane.terminal.getTerminal().resetFromHost()
        pane.terminal.feed(text: "")
        pane.apply(active?.config ?? config)
        pane.terminal.needsDisplay = true
        active?.refreshSearch()
    }
    @objc func showDocumentation(_ sender: Any?) { NSWorkspace.shared.open(URL(string:"https://getmoth.dev/docs/")!) }

    @objc func showReleaseNotes(_ sender: Any?) {
        if releaseNotesWindow == nil { releaseNotesWindow = ReleaseNotesWindowController() }
        releaseNotesWindow?.showWindow(nil)
        releaseNotesWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings(_ sender: Any?) {
        if appearancePanel == nil { appearancePanel = AppearancePanel(application: self) }
        appearancePanel?.selectProfile(active?.profileID); appearancePanel?.refresh(); appearancePanel?.showWindow(nil); appearancePanel?.window?.makeKeyAndOrderFront(nil)
    }

    var windows: [TerminalWindowController] = []
    var watcher: ConfigWatcher?
    private var systemAppearanceObserver: NSKeyValueObservation?
    var configError: Error?
    let macroPlayer = MacroPlayer()
    var secureKeyboardEntry = false
    var ownsSecureInput = false
    private var fullscreenKeyMonitor: Any?
    var active: TerminalWindowController? {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController,controller.application === self { return controller }
        if let lastTerminalWindow,windows.contains(where: { $0 === lastTerminalWindow }) { return lastTerminalWindow }
        return windows.last
    }
    static func main() {
        SessionRecovery.runHelperIfRequested()
        if CommandLine.arguments.contains("--recovery-test-host"),RecoveryHostFixture.root == nil { fputs("Recovery test requires its isolated temporary folder.\n",stderr); exit(2) }
        MothBenchmark.mainStarted = ProcessInfo.processInfo.systemUptime
        let app = NSApplication.shared, delegate = App()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Configuration.registerFonts()
        if let icon = Bundle.main.url(forResource: "Moth", withExtension: "icns"), let image = NSImage(contentsOf: icon) { NSApp.applicationIconImage = image }

        SiteScreenshots.prepare()
        MothBenchmark.prepare()
        do {
            config = try Configuration.expandFile()
        } catch { configError = error }
        updateChecker.onStateChange = { [weak self] in self?.appearancePanel?.refreshUpdateStatus() }
        reloadProfiles(); buildMenu()
        profilesWatcher = ProfilesWatcher(directory:profileDirectory)
        profilesWatcher?.changed = { [weak self] in guard let self else { return }; self.reloadProfiles(); self.appearancePanel?.applyPendingAudioEdits(to:&self.config); self.applyAppearance(); self.buildMenu() }
        fullscreenKeyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard Self.isFullscreenShortcut(event) else { return event }
            if !event.isARepeat { self?.toggleNativeFullScreen(nil) }; return nil
        }
        systemAppearanceObserver = NSApp.observe(\.effectiveAppearance,options:[.new]) { [weak self] _,_ in
            DispatchQueue.main.async { guard let self,self.config.theme == "system" || self.windows.contains(where: { $0.config.theme == "system" }) else { return }; self.applyAppearance(); self.buildMenu() }
        }
        let settingsSection = CommandLine.arguments.first(where: { $0.hasPrefix("--settings-section=") }).map { String($0.dropFirst("--settings-section=".count)) }
        let reviewing = SiteScreenshots.enabled || MothBenchmark.enabled || settingsSection != nil || CommandLine.arguments.contains("--appearance") || CommandLine.arguments.contains("--customise-background") || CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--about") || CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--keyboard-sounds")
        if reviewing { SessionRecovery.runtimeEnabled = false }
        if !reviewing {
            do { try SessionRecovery.claimOwnership() } catch { SessionRecovery.runtimeEnabled = false; showError(error); NSApp.terminate(nil); return }
        }
        if !reviewing,restoreSessions() { }
        else if !reviewing,config.showLayoutsOnLaunch,(try? WindowLayoutStore.load().isEmpty) == false { showSavedLayouts(nil) } else { newWindow(nil) }
        if CommandLine.arguments.contains("--appearance") || CommandLine.arguments.contains("--settings") { showSettings(nil) }
        if let settingsSection { showSettings(nil); if appearancePanel?.pages[settingsSection] != nil { appearancePanel?.tabs.selectTabViewItem(withIdentifier:settingsSection) } }
        if CommandLine.arguments.contains("--keyboard-sounds") { showSettings(nil); appearancePanel?.tabs.selectTabViewItem(withIdentifier:"Keyboard Sounds") }
        if CommandLine.arguments.contains("--customise-background") { showSettings(nil) }
        if CommandLine.arguments.contains("--about") { showAboutWindow(nil) }
        watcher = ConfigWatcher(url: Configuration.url)
        watcher?.changed = { [weak self] in self?.readConfiguration(showError: false) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if CommandLine.arguments.contains("--self-test") { SelfTest.run(app: self) }
        if MothBenchmark.enabled { MothBenchmark.run(self) }
        if SiteScreenshots.enabled { SiteScreenshots.run(self) }
        if !reviewing { startRecoveryCheckpoints() }
        if !reviewing,RecoveryHostFixture.root == nil,config.updates.checkAtLaunch {
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
                guard let self,!self.shuttingDown,self.config.updates.checkAtLaunch else { return }
                self.updateChecker.check(manual:false)
            }
        }
        RecoveryHostFixture.run(self)
    }
    @objc func accessibilityChanged() { applyAppearance() }
    @objc func newWindow(_ sender: Any?) { openWindow(profileID:profile(config.defaultProfileID)?.id) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { newWindow(nil) }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if keepingSessions { shuttingDown = true; return .terminateNow }
        let programs = Array(Set(windows.flatMap(\.confirmationPrograms))).sorted()
        if !programs.isEmpty && !confirm("Quit Moth?", detail: "Running programs: \(programs.joined(separator: ", ")). Closing will end their sessions.", button: "Quit") { return .terminateCancel }
        shuttingDown = true; recoveryTimer?.invalidate(); windows.forEach { $0.stop() }
        if SessionRecovery.enabled { try? FileManager.default.removeItem(at:SessionRecovery.manifestURL) }
        return .terminateNow
    }
    func confirm(_ title: String, detail: String, button: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: button); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    @objc func newTab(_ sender: Any?) { if let active { active.newTab(nil) } else { newWindow(nil) } }
    @objc func splitRight(_ sender: Any?) { active?.workspace.split(vertical: true, config: active?.config ?? config) }
    @objc func splitDown(_ sender: Any?) { active?.workspace.split(vertical: false, config: active?.config ?? config) }
    static func isFullscreenShortcut(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers?.lowercased() == "f" && event.modifierFlags.intersection([.command,.control,.shift,.option]) == [.command,.control]
    }
    @objc func toggleNativeFullScreen(_ sender: Any?) { NSApp.keyWindow?.toggleFullScreen(sender) }
    @objc func toggleMaximizePane(_ sender: Any?) { active?.workspace.toggleMaximizePane() }
    @objc func nextPane(_ sender: Any?) { active?.nextPane() }
    @objc func nextTab(_ sender: Any?) { active?.nextTab() }
    @objc func selectTabNumber(_ sender: NSMenuItem) { active?.selectTab(at: sender.tag) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            menuItem.title = updateChecker.isChecking ? "Checking for Updates…":"Check for Updates…"
            return !updateChecker.isChecking
        }
        if menuItem.action == #selector(toggleMaximizePane(_:)) {
            menuItem.title=active?.workspace.isPaneMaximized == true ? "Restore Split Layout":"Maximise Pane"
            return (active?.workspace.panes.count ?? 0)>1
        }
        if menuItem.action == #selector(changeTheme(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == (active?.config ?? config).theme ? .on : .off
        }
        if menuItem.action == #selector(changeTextEncoding(_:)) { menuItem.state = (menuItem.representedObject as? String) == active?.config.textEncoding ? .on : .off; return active != nil }
        if menuItem.action == #selector(assignWindowProfile(_:)) { menuItem.state = (menuItem.representedObject as? String) == active?.profileID ? .on : .off; return active != nil }
        if menuItem.action == #selector(selectTabNumber(_:)) {
            guard let active, active.workspaces.indices.contains(menuItem.tag) else { menuItem.state = .off; return false }
            menuItem.state = active.index == menuItem.tag ? .on : .off
        }
        if menuItem.action == #selector(saveSelectedText(_:)) { return !(active?.workspace.active.terminal.getSelection() ?? "").isEmpty }
        if menuItem.action == #selector(saveScrollback(_:)) || menuItem.action == #selector(printScrollback(_:)) { return active != nil }
        if menuItem.action == #selector(runMacro(_:)) { return active != nil && MacroRecorder.shared.source == nil }
        return true
    }
    @objc func find(_ sender: Any?) { active?.showFind() }
    @objc func findNext(_ sender: Any?) { active?.stepFind(1) }
    @objc func findPrevious(_ sender: Any?) { active?.stepFind(-1) }
    @objc func moveTabLeft(_ sender: Any?) { active?.moveActiveTab(by: -1) }
    @objc func moveTabRight(_ sender: Any?) { active?.moveActiveTab(by: 1) }
    @objc func closePane(_ sender: Any?) {
        if let window = NSApp.keyWindow, !(window.windowController is TerminalWindowController) { window.performClose(sender) }
        else { active?.closePane() }
    }
    @objc func reloadConfig(_ sender: Any?) { readConfiguration(showError: true) }
    func readConfiguration(showError: Bool) {
        do { config = try Configuration.load(); reloadProfiles(); appearancePanel?.applyPendingAudioEdits(to:&config); configError = nil; applyAppearance() }
        catch { configError = error; windows.forEach { $0.refreshFooter() }; appearancePanel?.refresh(); if showError { self.showError(error) } }
        buildMenu()
    }
    func applyAppearance() { KeyboardSoundPlayer.shared.update((active?.config ?? config).keyboardSound); if !config.bell.badge { clearBellBadge(nil) }; windows.forEach { $0.applyAppearance() }; appearancePanel?.refresh() }
    @objc func editConfig(_ sender: Any?) {
        do {
            if FileManager.default.fileExists(atPath: Configuration.url.path) { _ = try? Configuration.expandFile() }
            else { try Configuration.expandFile() }
            NSWorkspace.shared.open(Configuration.url)
        } catch { showError(error) }
    }
    @objc func showConfigError(_ sender: Any?) { if let configError { showError(configError) } }
    @objc func changeTheme(_ sender: NSMenuItem) { changeActiveSettings { $0.theme = sender.representedObject as! String; $0.palette = nil } }
    @objc func zoomIn(_ sender: Any?) { guard let active else { return }; active.zoomFontSize = min(32,active.config.fontSize+1); active.applyAppearance() }
    @objc func zoomOut(_ sender: Any?) { guard let active else { return }; active.zoomFontSize = max(9,active.config.fontSize-1); active.applyAppearance() }
    @objc func toggleKeyboardSounds(_ sender: Any?) {
        changeActiveSettings { $0.keyboardSound.enabled.toggle() }
        if !(active?.config ?? config).keyboardSound.enabled { KeyboardSoundPlayer.shared.stop() }
    }
    @objc func selectBellMode(_ sender: NSMenuItem) { changeActiveSettings { $0.bell.mode = sender.representedObject as! String } }
    @objc func selectBellStyle(_ sender: NSMenuItem) { changeActiveSettings { $0.bell.style = sender.representedObject as! String } }
    @objc func previewBell(_ sender: Any?) { active?.workspace.active.terminal.feed(text: "\u{7}") }
    @objc func selectBackground(_ sender: NSMenuItem) {
        changeActiveSettings { $0.background.style = sender.representedObject as! String }
    }
    @objc func selectCursorShape(_ sender: NSMenuItem) {
        changeActiveSettings { $0.cursor.shape = sender.representedObject as! String }
    }
    @objc func selectCursorAnimation(_ sender: NSMenuItem) {
        changeActiveSettings { $0.cursor.animation = sender.representedObject as! String }
    }
    @objc func toggleStatus(_ sender: Any?) { changeActiveSettings { $0.window.showStatusBar.toggle() } }
    @objc func toggleTabs(_ sender: Any?) { changeActiveSettings { $0.window.showTabBar.toggle() } }
    func persistAppearance() {
        applyAppearance(); buildMenu()
        do { try Configuration.save(config) } catch { showError(error) }
    }
    @objc func demo(_ sender: Any?) {
        newTab(nil)
        if let script = Bundle.main.url(forResource: "showcase", withExtension: "sh") {
            active?.workspace.active.terminal.send(txt: "/bin/bash '\(script.path.replacingOccurrences(of: "'", with: "'\\''"))'\r")
        }
    }
    func showError(_ error: Error) { NSAlert(error: error).runModal() }
    func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let sub = NSMenu(title: title); item.submenu = sub; main.addItem(item); return sub }
        func item(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command, action: String? = nil, target: AnyObject? = nil) {
            let shortcut = action.flatMap { config.keybindings[$0] }.flatMap(Configuration.shortcut)
            let modifiers = shortcut?.1 ?? flags
            let equivalent = shortcut?.0 ?? key
            // AppKit represents shifted letters with uppercase key equivalents.
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: modifiers.contains(.shift) ? equivalent.uppercased() : equivalent)
            item.keyEquivalentModifierMask = modifiers; item.target = target ?? self
            menu.addItem(item)
        }
        let app = menu("Moth")
        item(app, "About Moth", #selector(showAboutWindow(_:)))
        item(app, "Check for Updates…", #selector(checkForUpdates(_:)))
        app.addItem(.separator()); item(app, "Settings…", #selector(showSettings(_:)), ",")
        item(app, "Edit Configuration…", #selector(editConfig(_:)))
        item(app, "Reload Configuration", #selector(reloadConfig(_:)), action: "reloadConfig")
        app.addItem(.separator()); item(app, "Hide Moth", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(app,"Quit and Keep Sessions",#selector(quitKeepingSessions(_:)))
        item(app, "Quit Moth", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        item(app,"Secure Keyboard Entry",#selector(toggleSecureKeyboardEntry(_:)))
        app.items.last?.state = secureKeyboardEntry ? .on : .off
        let file = menu("File")
        item(file,"Save Scrollback…",#selector(saveScrollback(_:)),"s")
        item(file,"Save Selected Text…",#selector(saveSelectedText(_:)))
        file.addItem(.separator()); item(file,"Page Setup…",#selector(pageSetup(_:)),"p",[.command,.shift])
        item(file,"Print…",#selector(printScrollback(_:)),"p")
        let shell = menu("Shell")
        item(shell, "New Window", #selector(newWindow(_:)), action: "newWindow")
        item(shell, "New Tab", #selector(newTab(_:)), action: "newTab")
        item(shell, "Split Right", #selector(splitRight(_:)), action: "splitRight")
        item(shell, "Split Down", #selector(splitDown(_:)), action: "splitDown")
        shell.addItem(.separator()); item(shell, "Reset Terminal", #selector(resetTerminal(_:)), action: "resetTerminal")
        item(shell, "Close Pane", #selector(closePane(_:)), action: "closePane")
        let edit = menu("Edit")
        // nil targets follow the responder chain to the focused terminal.
        for (title, selector, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key); edit.addItem(entry)
        }
        edit.addItem(.separator())
        item(edit, "Find…", #selector(find(_:)), "f")
        item(edit, "Find Next", #selector(findNext(_:)), "g")
        item(edit, "Find Previous", #selector(findPrevious(_:)), "g", [.command, .shift])
        let current = active?.config ?? config
        let view = menu("View")
        item(view,"Maximise Pane",#selector(toggleMaximizePane(_:)),action:"toggleMaximizePane")
        item(view, "Next Pane", #selector(nextPane(_:)), action: "nextPane")
        item(view, "Next Tab", #selector(nextTab(_:)), action: "nextTab")
        let tabsItem = NSMenuItem(title: "Select Tab", action: nil, keyEquivalent: "")
        let tabsMenu = NSMenu(title: "Select Tab"); tabsItem.submenu = tabsMenu; view.addItem(tabsItem)
        for number in 1...9 {
            item(tabsMenu, "Tab \(number)", #selector(selectTabNumber(_:)), action: "selectTab\(number)")
            tabsMenu.items.last?.tag = number-1
        }
        item(view, "Move Tab Left", #selector(moveTabLeft(_:)), "[", [.command, .control, .shift])
        item(view, "Move Tab Right", #selector(moveTabRight(_:)), "]", [.command, .control, .shift])
        item(view, "Increase Font Size", #selector(zoomIn(_:)), "+")
        item(view, "Decrease Font Size", #selector(zoomOut(_:)), "-")
        view.addItem(.separator())
        let fullscreen = FullscreenMenuItem(title:"Toggle Full Screen",action:#selector(toggleNativeFullScreen(_:)),keyEquivalent:"f")
        fullscreen.target = self; fullscreen.allowsAutomaticKeyEquivalentLocalization = false; fullscreen.keyEquivalentModifierMask = [.command,.control]; view.addItem(fullscreen)
        item(view, "Settings…", #selector(showSettings(_:)))
        view.addItem(.separator())
        let cursorItem = NSMenuItem(title: "Cursor", action: nil, keyEquivalent: "")
        let cursorMenu = NSMenu(title: "Cursor"); cursorItem.submenu = cursorMenu; view.addItem(cursorItem)
        for shape in ["block", "underline", "bar"] {
            let entry = NSMenuItem(title: shape.capitalized, action: #selector(selectCursorShape(_:)), keyEquivalent: "")
            entry.representedObject = shape; entry.target = self; entry.state = current.cursor.shape == shape ? .on : .off
            cursorMenu.addItem(entry)
        }
        cursorMenu.addItem(.separator())
        for (animation, title) in [("breathe", "Breathe"), ("blink", "Blink"), ("noblink", "No Blink")] {
            let entry = NSMenuItem(title: title, action: #selector(selectCursorAnimation(_:)), keyEquivalent: "")
            entry.representedObject = animation; entry.target = self; entry.state = current.cursor.animation == animation ? .on : .off
            cursorMenu.addItem(entry)
        }
        view.addItem(.separator())
        item(view,"Keyboard Sounds",#selector(toggleKeyboardSounds(_:)),action:"toggleKeyboardSounds")
        view.items.last?.state = current.keyboardSound.enabled ? .on : .off
        let bellItem = NSMenuItem(title: "Bell", action: nil, keyEquivalent: "")
        let bellMenu = NSMenu(title: "Bell"); bellItem.submenu = bellMenu; view.addItem(bellItem)
        for (mode,title) in [("visual","Visual"),("sound","Sound"),("both","Visual and Sound"),("off","Off")] {
            let entry = NSMenuItem(title: title, action: #selector(selectBellMode(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = mode; entry.state = current.bell.mode == mode ? .on : .off
            bellMenu.addItem(entry)
        }
        bellMenu.addItem(.separator())
        let effectItem = NSMenuItem(title: "Visual Effect", action: nil, keyEquivalent: "")
        let effectMenu = NSMenu(title: "Visual Effect"); effectItem.submenu = effectMenu; bellMenu.addItem(effectItem)
        for (style,title) in [("border","Pane Border"),("flash","Soft Pane Flash"),("window-border","Window Border")] {
            let entry = NSMenuItem(title: title, action: #selector(selectBellStyle(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = style; entry.state = current.bell.style == style ? .on : .off
            effectMenu.addItem(entry)
        }
        bellMenu.addItem(.separator()); item(bellMenu, "Clear Bell Badge", #selector(clearBellBadge(_:)))
        item(bellMenu, "Preview Bell", #selector(previewBell(_:)))
        view.addItem(.separator())
        item(view, "Show Status Bar", #selector(toggleStatus(_:)))
        view.items.last?.state = current.window.showStatusBar ? .on : .off
        item(view, "Show Tab Bar", #selector(toggleTabs(_:)))
        view.items.last?.state = current.window.showTabBar ? .on : .off
        let macrosMenu = menu("Macros")
        item(macrosMenu,"Manage Macros…",#selector(showMacros(_:)))
        item(macrosMenu,MacroRecorder.shared.source == nil ? "Start Recording" : "Stop Recording…",#selector(toggleMacroRecording(_:)))
        item(macrosMenu,"Stop Playback",#selector(stopMacro(_:))); macrosMenu.addItem(.separator())
        for name in config.macros.keys.sorted() {
            let macro = config.macros[name]!, key = Configuration.shortcut(macro.shortcut)
            item(macrosMenu,name,#selector(runMacro(_:)),key?.0 ?? "",key?.1 ?? .command)
            macrosMenu.items.last?.representedObject = name
        }
        let windowsMenu = menu("Window")
        let newProfileItem = NSMenuItem(title:"New Window with Profile",action:nil,keyEquivalent:"")
        let newProfileMenu = NSMenu(title:"New Window with Profile"); newProfileItem.submenu = newProfileMenu; windowsMenu.addItem(newProfileItem)
        let assignItem = NSMenuItem(title:"Window Profile",action:nil,keyEquivalent:"")
        let assignMenu = NSMenu(title:"Window Profile"); assignItem.submenu = assignMenu; windowsMenu.addItem(assignItem)
        for (name,id) in [("Default",Optional<String>.none)]+profiles.map({ ($0.name,Optional($0.id)) }) {
            item(newProfileMenu,name,#selector(newProfileWindow(_:))); newProfileMenu.items.last?.representedObject = id
            item(assignMenu,name,#selector(assignWindowProfile(_:))); assignMenu.items.last?.representedObject = id
        }
        item(windowsMenu,"Manage Profiles…",#selector(showProfiles(_:)))
        let encodingItem = NSMenuItem(title:"Text Encoding",action:nil,keyEquivalent:"")
        let encodingMenu = NSMenu(title:"Text Encoding"); encodingItem.submenu = encodingMenu; windowsMenu.addItem(encodingItem)
        for encoding in TerminalTextEncoding.available(active?.config ?? config) { item(encodingMenu,encoding.title+(config.enabledEncodings.contains(encoding.id) ? "" : " (current)"),#selector(changeTextEncoding(_:))); encodingMenu.items.last?.representedObject = encoding.id }
        windowsMenu.addItem(.separator())
        item(windowsMenu, "Saved Layouts…", #selector(showSavedLayouts(_:)), action:"openLayouts")
        item(windowsMenu, "Save Window Layout…", #selector(saveWindowLayout(_:)))
        windowsMenu.addItem(.separator())
        item(windowsMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        windowsMenu.items.last?.target = nil
        item(windowsMenu, "Zoom", #selector(NSWindow.performZoom(_:)))
        windowsMenu.items.last?.target = nil
        item(windowsMenu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
        NSApp.windowsMenu = windowsMenu
        if configError != nil { app.addItem(.separator()); item(app, "Configuration Error…", #selector(showConfigError(_:))) }
        let help = menu("Help")
        item(help, "Documentation", #selector(showDocumentation(_:)))
        item(help, "What’s New?", #selector(showReleaseNotes(_:)))
        help.addItem(.separator())
        item(help, "Run Graphics & Glyph Showcase", #selector(demo(_:)))
        NSApp.mainMenu = main
    }
}

final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    unowned let application: App
    var profileID: String?
    var profileSnapshot: TerminalProfile?
    var zoomFontSize: Double?
    private var configuredFontName: String?
    private var configuredFontSize: Double?
    var baseConfiguration: Configuration {
        if let found = application.profile(profileID) { profileSnapshot = found }
        return profileID == nil ? application.config : profileSnapshot?.applying(to:application.config) ?? application.config
    }
    var config: Configuration {
        var result = baseConfiguration
        if let zoomFontSize { result.fontSize = zoomFontSize }; return result
    }
    var workspaces: [Workspace] = []
    var index = 0
    var pendingInitialFocus = false
    private var initialFocusRetry:DispatchWorkItem?
    private var initialFocusAttempts=0
    let content = FlowBackgroundView(frame: .zero)
    let footer = NSView()
    let tabBar = TerminalTabBar()
    var tabs: TabStrip { tabBar.strip }
    let findBar = FindBar(frame: .zero)
    private var findHeight: NSLayoutConstraint!
    private var searchTimer: Timer?
    private var searchDebounce: DispatchWorkItem?
    private weak var searchPane: Pane?
    private var searchVersion: UInt64?
    private(set) var searchMatches: [TerminalSearchMatch] = []
    private(set) var searchIndex = -1
    private var searchTruncated = false
    private var searchError: String?
    let stage = NSView()
    let status = NSTextField(labelWithString: "")
    var footerHeight: NSLayoutConstraint!
    private var tabSignature = ""
    private var chromeConstraints: [NSLayoutConstraint] = []
    private var chromePosition: String?
    private let titlebarChrome = NSTitlebarAccessoryViewController()
    private let titlebarChromeHost = NSView()
    var workspace: Workspace { workspaces[index] }
    var confirmationPrograms: [String] { Array(Set(workspaces.flatMap(\.panes).flatMap { $0.closeWarningPrograms(config.closeConfirmation) })).sorted() }
    let recoveryID = UUID()
    var runningCount: Int { workspaces.flatMap(\.panes).filter { $0.terminal.process.running }.count }
    init(application: App, savedLayout: SavedWindowLayout? = nil, profileID: String? = nil, adopting: Workspace? = nil, template: TerminalWindowController? = nil) {
        self.application = application
        self.profileSnapshot = template?.profileSnapshot ?? application.profile(profileID ?? savedLayout?.profileID)
        self.profileID = template?.profileID ?? self.profileSnapshot?.id
        self.zoomFontSize = template?.zoomFontSize
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Moth"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 360); window.delegate = self
        window.contentView = content
        tabs.controller = self
        findBar.isHidden = true
        findBar.changed = { [weak self] in self?.scheduleSearch() }
        findBar.step = { [weak self] direction in self?.stepFind(direction) }
        findBar.dismissed = { [weak self] in self?.hideFind() }
        status.font = .systemFont(ofSize: 10); status.textColor = .secondaryLabelColor
        status.alignment = .right; status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.wantsLayer = true
        for view in [stage, footer, findBar] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        for view in [tabBar, status] { view.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(view) }
        footerHeight = footer.heightAnchor.constraint(equalToConstant: 28)
        findHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor), findBar.leadingAnchor.constraint(equalTo: content.leadingAnchor), findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor), findHeight,
            stage.topAnchor.constraint(equalTo: findBar.bottomAnchor), stage.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 1), stage.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -1),
            footerHeight,
            tabBar.leadingAnchor.constraint(equalTo:footer.leadingAnchor,constant:10),tabBar.topAnchor.constraint(equalTo:footer.topAnchor),tabBar.bottomAnchor.constraint(equalTo:footer.bottomAnchor),tabBar.trailingAnchor.constraint(equalTo:status.leadingAnchor,constant:-10),
            status.widthAnchor.constraint(lessThanOrEqualTo:footer.widthAnchor,multiplier:0.3),
            status.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12), status.centerYAnchor.constraint(equalTo: footer.centerYAnchor), status.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])
        if let adopting {
            if let size = template?.window?.contentView?.bounds.size { window.setContentSize(size) }
            addWorkspace(adopting); showWorkspace()
        } else if let savedLayout {
            for tab in savedLayout.tabs { addWorkspace(Workspace(config:config,saved:tab)) }
            index = savedLayout.activeTab
            let minimum = savedLayout.tabs.map { $0.root.minimumSize }.reduce(NSSize(width:560,height:360)) { NSSize(width:max($0.width,$1.width+2),height:max($0.height,$1.height+60)) }
            window.minSize = minimum; window.setContentSize(NSSize(width:max(minimum.width,savedLayout.width),height:max(minimum.height,savedLayout.height)))
            window.title = "Moth — "+savedLayout.name; showWorkspace()
        } else { newTab(nil) }
        applyAppearance(updatePanes:adopting == nil)
        if let adopting { adopting.panes.forEach { $0.applyForTransfer(config) } }
    }
    required init?(coder: NSCoder) { fatalError() }
    func presentAndFocus() {
        guard let window,!workspaces.isEmpty else { return }
        pendingInitialFocus = true; window.initialFirstResponder = workspace.active.terminal
        showWindow(nil); content.layoutSubtreeIfNeeded()
        NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(workspace.active.terminal)
        DispatchQueue.main.async { [weak self] in self?.finishInitialFocus() }
    }
    func finishInitialFocus(retrying:Bool = false) {
        initialFocusRetry?.cancel();initialFocusRetry=nil
        guard pendingInitialFocus,application.windows.contains(where:{$0 === self}),let window,window.isVisible,!workspaces.isEmpty else { return }
        if !retrying { initialFocusAttempts=40 }
        let terminal=workspace.active.terminal
        if NSApp.isActive,window.isKeyWindow,NSApp.keyWindow === window,!terminal.readOnly,!terminal.isHidden {
            content.layoutSubtreeIfNeeded()
            if window.firstResponder === terminal,!terminal.hasFocus { window.makeFirstResponder(nil) }
            if window.makeFirstResponder(terminal),window.firstResponder === terminal,terminal.hasFocus {
                pendingInitialFocus=false;return
            }
        }
        guard initialFocusAttempts>0 else { return };initialFocusAttempts-=1
        let retry=DispatchWorkItem { [weak self] in self?.finishInitialFocus(retrying:true) }
        initialFocusRetry=retry;DispatchQueue.main.asyncAfter(deadline:.now()+0.025,execute:retry)
    }
    func applyAppearance(updatePanes: Bool = true) {
        let base = baseConfiguration
        if let configuredFontName,configuredFontName != base.fontName || configuredFontSize != base.fontSize { zoomFontSize = nil }
        configuredFontName = base.fontName; configuredFontSize = base.fontSize
        window?.appearance = NSAppearance(named: config.selectedTheme.light ? .aqua : .darkAqua)
        window?.isOpaque = config.windowBackgroundOpacity == 1
        window?.backgroundColor = config.windowBackgroundOpacity == 1 ? config.colors.0 : .clear
        window?.alphaValue = 1
        content.apply(config)
        footer.layer?.backgroundColor = config.colors.0.withAlphaComponent(0.25).cgColor
        if updatePanes { for ws in workspaces { for pane in ws.panes { pane.apply(config) } } }
        refreshFooter()
    }
    private func placeChrome(height: CGFloat) {
        guard let window else { return }
        let position = config.window.chromePosition
        if chromePosition != position {
            chromePosition = position
            NSLayoutConstraint.deactivate(chromeConstraints); chromeConstraints = []
            if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === titlebarChrome }) { window.removeTitlebarAccessoryViewController(at:index) }
            footer.removeFromSuperview()
            if position == "titlebar" {
                titlebarChromeHost.frame = NSRect(x:0,y:0,width:window.frame.width,height:height)
                titlebarChromeHost.autoresizingMask = [.width]
                titlebarChrome.view = titlebarChromeHost; titlebarChrome.layoutAttribute = .bottom
                titlebarChromeHost.addSubview(footer)
                chromeConstraints = [footer.leadingAnchor.constraint(equalTo:titlebarChromeHost.leadingAnchor),footer.trailingAnchor.constraint(equalTo:titlebarChromeHost.trailingAnchor),footer.topAnchor.constraint(equalTo:titlebarChromeHost.topAnchor),footer.bottomAnchor.constraint(equalTo:titlebarChromeHost.bottomAnchor),stage.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-1)]
                NSLayoutConstraint.activate(chromeConstraints); window.addTitlebarAccessoryViewController(titlebarChrome)
            } else {
                content.addSubview(footer)
                chromeConstraints = [footer.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:1),footer.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-1),footer.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-1),stage.bottomAnchor.constraint(equalTo:footer.topAnchor)]
                NSLayoutConstraint.activate(chromeConstraints)
            }
        }
        if position == "titlebar" {
            titlebarChrome.fullScreenMinHeight = height
            titlebarChromeHost.isHidden = height == 0
            if titlebarChromeHost.frame.height != height { titlebarChromeHost.setFrameSize(NSSize(width:window.frame.width,height:height)) }
        }
    }
    func fitMinimumSize() {
        guard let window else { return }
        let size = workspaces.compactMap { try? $0.savedTab().root.minimumSize }.reduce(NSSize(width:560,height:360)) {
            NSSize(width:max($0.width,$1.width+2),height:max($0.height,$1.height+60))
        }
        window.minSize = size
        if window.frame.width < size.width || window.frame.height < size.height {
            var frame = window.frame; frame.size.width = max(frame.width,size.width); frame.size.height = max(frame.height,size.height)
            window.setFrame(frame,display:false)
        }
    }
    func refreshFooter() {
        guard !workspaces.isEmpty else { return }
        fitMinimumSize()
        let showTabs = config.window.showTabBar && workspaces.count > 1
        tabBar.isHidden = !showTabs; status.isHidden = !config.window.showStatusBar
        let showFooter = showTabs || config.window.showStatusBar
        footer.isHidden = !showFooter; footerHeight.constant = showFooter ? 28 : 0
        placeChrome(height:showFooter ? 28 : 0)
        let error = application.configError ?? application.profileError ?? application.recoveryError
        status.stringValue = !config.window.showStatusBar ? "" : error == nil ? "\(workspace.title)   ·   \(workspace.active.dimensions.stringValue)" : (application.recoveryError != nil && application.configError == nil && application.profileError == nil ? "Session recovery unavailable" : "Configuration error · using last valid settings")
        if MacroRecorder.shared.source === workspace.active.terminal { status.stringValue = "● Recording macro · Stop from the Macros menu" }
        status.toolTip = error?.localizedDescription ?? workspace.title
        window?.title = workspace.title+(profileSnapshot.map { " — "+$0.name } ?? "")
        if !findBar.isHidden && searchPane !== workspace.active { refreshSearch() }
        let signature = "\(index):" + workspaces.map { "\($0.id):\($0.title)" }.joined(separator: "|")
        guard signature != tabSignature else { return }
        tabSignature = signature
        tabBar.prepareForReload()
        for view in tabs.arrangedSubviews { tabs.removeArrangedSubview(view); view.removeFromSuperview() }
        for (i, ws) in workspaces.enumerated() {
            let button = TerminalTabButton(title: "\(i+1)  \(ws.title)", target: self, action: #selector(selectTab(_:)))
            button.workspaceID = ws.id; button.sourceController = self
            button.toolTip = "\(ws.title) · Drag to reorder or move to another window"
            button.tag = i; button.bezelStyle = .recessed; button.state = i == index ? .on : .off
            button.showsBorderOnlyWhileMouseInside = i != index
            button.font = .systemFont(ofSize: 11, weight: i == index ? .medium : .regular)
            button.lineBreakMode = .byTruncatingMiddle; button.setAccessibilityLabel("Tab \(i+1): \(ws.title)")
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.widthAnchor.constraint(equalToConstant:TerminalTabBar.preferredWidth(for:button)).isActive = true
            tabs.addArrangedSubview(button)
        }
        tabBar.tabsChanged(selected:workspace.id)
    }
    @objc func selectTabFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        selectTab(at:index)
    }
    func newTab(_ sender: Any?) {
        guard workspaces.count < 12 else { NSSound.beep(); return }
        let directory = workspaces.indices.contains(index) ? workspace.active.localWorkingDirectory : nil
        addWorkspace(Workspace(config:config,inheritedDirectory:directory)); index = workspaces.count-1; showWorkspace()
    }
    private func addWorkspace(_ ws: Workspace) {
        ws.bell = { [weak application] in application?.recordBell() }
        ws.closeRequested = { [weak self,weak ws] pane in
            guard let self,let ws,let index = self.workspaces.firstIndex(where: { $0 === ws }) else { return }
            self.index = index; ws.active = pane; ws.highlight(); self.window?.makeFirstResponder(pane.terminal); self.closePane()
        }
        ws.sessionEnded = { [weak self,weak ws] pane in guard let self,let ws,self.config.closeOnExit,pane.ended else { return }; self.removeSession(pane,from:ws) }
        ws.changed = { [weak self] in self?.refreshFooter() }
        workspaces.append(ws)
    }
    @objc func selectTab(_ sender: NSButton) { selectTab(at: sender.tag) }
    func selectTab(at newIndex: Int) {
        guard workspaces.indices.contains(newIndex) else { return }
        index = newIndex; showWorkspace()
    }
    func showWorkspace() {
        fitMinimumSize()
        stage.subviews.forEach { $0.removeFromSuperview() }
        workspace.mount(workspace.root, in: stage)
        stage.layoutSubtreeIfNeeded(); workspace.applyRestoredGeometry(); refreshFooter()
        window?.initialFirstResponder = workspace.active.terminal
        window?.makeFirstResponder(workspace.active.terminal)
    }
    func nextPane() {
        let panes = workspace.orderedPanes, i = panes.firstIndex(of: workspace.active) ?? 0
        workspace.focusPane(panes[(i+1)%panes.count])
    }
    func nextTab() { index = (index+1)%workspaces.count; showWorkspace() }
    func closePane() {
        let programs = workspace.active.closeWarningPrograms(config.closeConfirmation)
        guard programs.isEmpty || application.confirm("Close this shell session?", detail: "Running programs: \(programs.joined(separator: ", ")). The session will end.", button: "Close Session") else { return }
        removeSession(workspace.active,from:workspace)
    }
    private func removeSession(_ pane: Pane,from ws: Workspace) {
        guard let removedIndex = workspaces.firstIndex(where: { $0 === ws }),ws.panes.contains(where: { $0 === pane }) else { return }
        if ws.panes.count > 1 { ws.close(pane); refreshFooter(); return }
        let selected = workspace
        ws.stop(); workspaces.remove(at:removedIndex)
        if workspaces.isEmpty { window?.close() }
        else if selected === ws { index = min(removedIndex,workspaces.count-1); showWorkspace() }
        else { index = workspaces.firstIndex(where: { $0 === selected }) ?? 0; refreshFooter() }
    }
    @discardableResult
    func moveTab(id: UUID, toInsertionIndex destination: Int) -> Bool {
        guard let source = workspaces.firstIndex(where: { $0.id == id }), (0...workspaces.count).contains(destination) else { return false }
        let selected = workspace
        let moved = workspaces.remove(at: source)
        workspaces.insert(moved, at: destination > source ? destination-1 : destination)
        index = workspaces.firstIndex(where: { $0 === selected })!
        refreshFooter()
        return true
    }
    /// Transfers ownership of the existing view tree, without ending or recreating a PTY.
    private func takeWorkspace(_ id: UUID) -> Workspace? {
        guard let source = workspaces.firstIndex(where: { $0.id == id }) else { return nil }
        let selected = workspace,removed = workspaces.remove(at:source)
        removed.root.removeFromSuperview()
        if !workspaces.isEmpty {
            index = workspaces.firstIndex(where: { $0 === selected }) ?? min(source,workspaces.count-1)
            showWorkspace()
        } else { index = 0; hideFind() }
        return removed
    }
    func canReceiveTab(_ id: UUID) -> Bool {
        guard let source = application.owner(ofTab:id) else { return false }
        return source === self || workspaces.count < 12
    }
    @discardableResult func receiveTab(_ id: UUID,at insertion: Int? = nil) -> Bool {
        guard canReceiveTab(id),let source = application.owner(ofTab:id) else { return false }
        let destination = insertion ?? workspaces.count
        guard (0...workspaces.count).contains(destination) else { return false }
        if source === self { return moveTab(id:id,toInsertionIndex:destination) }
        guard let moved = source.takeWorkspace(id) else { return false }
        addWorkspace(moved)
        workspaces.removeLast(); workspaces.insert(moved,at:destination); index = destination
        moved.panes.forEach { $0.applyForTransfer(config) }
        showWorkspace(); window?.makeKeyAndOrderFront(nil)
        if source.workspaces.isEmpty { source.window?.close() }
        application.checkpointTransferredSessions()
        return true
    }
    @discardableResult func detachTab(_ id: UUID,at point: NSPoint) -> TerminalWindowController? {
        guard let moved = takeWorkspace(id) else { return nil }
        let controller = TerminalWindowController(application:application,adopting:moved,template:self)
        application.windows.append(controller)
        if let window = controller.window {
            let screen = NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main
            let area = screen?.visibleFrame ?? window.frame
            window.setFrameOrigin(NSPoint(x:max(area.minX,min(point.x-80,area.maxX-window.frame.width)),y:max(area.minY,min(point.y-window.frame.height+20,area.maxY-window.frame.height))))
            controller.presentAndFocus()
        }
        if workspaces.isEmpty { window?.close() }
        application.checkpointTransferredSessions()
        return controller
    }
    func closeTab(_ id: UUID) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        let programs = Array(Set(ws.panes.flatMap { $0.closeWarningPrograms(config.closeConfirmation) })).sorted()
        guard programs.isEmpty || application.confirm("Close this tab?",detail:"Running programs: "+programs.joined(separator:", ")+". Their sessions will end.",button:"Close Tab") else { return }
        guard let removed = takeWorkspace(id) else { return }; removed.stop()
        if workspaces.isEmpty { window?.close() }
        application.checkpointTransferredSessions()
    }
    func moveActiveTab(by offset: Int) {
        let target = index+offset
        guard workspaces.indices.contains(target) else { return }
        _ = moveTab(id: workspace.id, toInsertionIndex: target > index ? target+1 : target)
    }
    func showFind() {
        pendingInitialFocus = false
        findBar.isHidden = false; findHeight.constant = 38
        content.layoutSubtreeIfNeeded()
        refreshSearch(); window?.makeFirstResponder(findBar.field)
        if searchTimer == nil {
            let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
                guard let self, !self.findBar.isHidden else { return }
                if self.searchPane !== self.workspace.active || self.searchVersion != self.workspace.active.terminal.getTerminal().searchContentVersion { self.refreshSearch(preserveMatch: true) }
            }
            RunLoop.main.add(timer, forMode: .common); searchTimer = timer
        }
    }
    func hideFind() {
        searchDebounce?.cancel(); searchTimer?.invalidate(); searchTimer = nil
        findBar.isHidden = true; findHeight.constant = 0
        content.layoutSubtreeIfNeeded(); if !workspaces.isEmpty { pendingInitialFocus = workspace.active.terminal.replayingSession; window?.makeFirstResponder(workspace.active.terminal) }
    }
    private func scheduleSearch() {
        searchVersion = nil
        searchDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refreshSearch() }
        searchDebounce = item; DispatchQueue.main.asyncAfter(deadline: .now()+0.15, execute: item)
    }
    func refreshSearch(preserveMatch: Bool = false) {
        guard !findBar.isHidden else { return }
        let pane = workspace.active!, terminal = pane.terminal.getTerminal()
        let old = preserveMatch && searchPane === pane && searchMatches.indices.contains(searchIndex) ? searchMatches[searchIndex] : nil
        let result = terminal.find(findBar.field.stringValue,caseSensitive:findBar.matchCase.state == .on,regularExpression:findBar.regex.state == .on)
        searchPane = pane; searchVersion = terminal.searchContentVersion
        searchMatches = result.matches; searchTruncated = result.truncated; searchError = result.error
        searchIndex = old.flatMap { searchMatches.firstIndex(of: $0) } ?? (searchMatches.isEmpty ? -1 : 0)
        revealFind()
        findBar.count.textColor = result.error == nil ? .secondaryLabelColor : .systemRed
        findBar.count.toolTip = result.error ?? (result.truncated ? "Search stopped at its result or time limit; these are partial results." : nil)
        if result.error != nil { findBar.count.stringValue = "Invalid regex" }
    }
    func stepFind(_ direction: Int) {
        if findBar.isHidden { showFind() }
        searchDebounce?.cancel()
        if searchVersion != workspace.active.terminal.getTerminal().searchContentVersion || searchPane !== workspace.active { refreshSearch(preserveMatch: true) }
        guard !searchMatches.isEmpty else { return }
        searchIndex = (searchIndex + direction + searchMatches.count) % searchMatches.count
        revealFind()
    }
    private func revealFind() {
        if searchMatches.indices.contains(searchIndex) { _ = searchPane?.terminal.revealSearchMatch(searchMatches[searchIndex]) }
        if searchError != nil { findBar.count.stringValue = "Invalid regex"; return }
        findBar.count.stringValue = findBar.field.stringValue.isEmpty ? "" : searchMatches.isEmpty ? (searchTruncated ? "Search limit reached" : "No matches") : "\(searchIndex+1) of \(searchMatches.count)\(searchTruncated ? "+" : "")"
    }
    func stop() { searchDebounce?.cancel(); searchTimer?.invalidate(); searchTimer = nil; workspaces.forEach { $0.stop() } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let programs = confirmationPrograms
        guard programs.isEmpty || application.confirm("Close this window?", detail: "Running programs: \(programs.joined(separator: ", ")). Their sessions will end.", button: "Close Window") else { return false }
        stop(); return true
    }
    func windowWillClose(_ notification: Notification) { if !application.keepingSessions { stop() }; application.windows.removeAll { $0 === self }; if SessionRecovery.enabled && !application.keepingSessions && !application.shuttingDown { try? SessionRecovery.save(application.windows) } }
    func windowDidBecomeKey(_ notification: Notification) { finishInitialFocus(); application.lastTerminalWindow = self; KeyboardSoundPlayer.shared.update(config.keyboardSound); application.buildMenu(); content.layoutSubtreeIfNeeded(); if !workspaces.isEmpty { workspace.applyRestoredGeometry() }; refreshFooter() }
    func windowDidEnterFullScreen(_ notification: Notification) { content.needsLayout = true }
    func windowDidExitFullScreen(_ notification: Notification) { content.needsLayout = true }
    func windowDidMiniaturize(_ notification: Notification) { content.pauseMotion(true) }
    func windowDidDeminiaturize(_ notification: Notification) { content.pauseMotion(false) }
}

enum ThemePreview {
    static func preview(_ config: Configuration, motion: Bool, time: Double = 4) -> NSImage {
        let size = NSSize(width: 280, height: 176), scale: CGFloat = 2
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width*scale), pixelsHigh: Int(size.height*scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext; context.scaleBy(x: scale, y: scale)
        let rect = NSRect(origin: .zero, size: size)
        if config.theme == "system" {
            for (index,name) in ["moth-dark","moth-light"].enumerated() {
                var half = Configuration(); half.theme = name; half.background.style = "solid"
                context.saveGState(); context.clip(to:CGRect(x:CGFloat(index)*size.width/2,y:0,width:size.width/2,height:size.height))
                preview(half,motion:false).draw(in:rect); context.restoreGState()
            }
            bitmap.size = size; let image = NSImage(size:size); image.addRepresentation(bitmap); return image
        }
        let base = CAGradientLayer(); base.frame = rect
        (config.background.style == "solid" ? config.background.paint : Configuration.Paint()).apply(to: base, fallback: config.colors.0); base.render(in: context)
        if motion, config.background.style != "solid", let cg = FlowBackgroundView.render(config: config, size: NSSize(width: size.width*scale, height: size.height*scale), time: time) {
            context.saveGState(); context.setAlpha(CGFloat(config.backgroundFieldOpacity)); context.draw(cg, in: rect); context.restoreGState()
        }
        // Quiet window chrome gives scale without covering the colour field.
        NSColor.black.withAlphaComponent(0.10).setFill(); NSRect(x: 0, y: 151, width: size.width, height: 25).fill()
        for (index, hex) in ["FF6159", "FFBD2E", "28C840"].enumerated() {
            NSColor.hex(hex).withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 13+index*12, y: 160, width: 7, height: 7)).fill()
        }
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        func text(_ value: String, x: CGFloat, y: CGFloat, color: NSColor) {
            (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
        }
        text("~/projects", x: 19, y: 112, color: config.colors.1.withAlphaComponent(0.72))
        text("❯", x: 19, y: 85, color: config.colors.2)
        text("moth", x: 38, y: 85, color: config.colors.1)
        if !motion {
            for (index, color) in [config.colors.1, config.colors.2, config.colors.1.withAlphaComponent(0.35)].enumerated() {
                color.setFill(); NSBezierPath(roundedRect: NSRect(x: 19+index*51, y: 30, width: 39, height: 8), xRadius: 4, yRadius: 4).fill()
            }
        } else {
            config.colors.2.withAlphaComponent(0.9).setFill(); NSRect(x: 78, y: 85, width: 7, height: 17).fill()
        }
        bitmap.size = size
        let image = NSImage(size: size); image.addRepresentation(bitmap); return image
    }

}

final class AppearancePreviewButton: NSButton {
    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 136) }
    private var tracking: NSTrackingArea?
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(next); tracking = next
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 12, yRadius: 12).fill() }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let card = bounds.insetBy(dx: 3, dy: 3)
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        (hovering ? NSColor.controlBackgroundColor : NSColor.controlBackgroundColor.withAlphaComponent(0.65)).setFill(); shape.fill()
        let picture = NSRect(x: card.minX+5, y: card.minY+34, width: card.width-10, height: card.height-39)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: picture, xRadius: 8, yRadius: 8).addClip()
        if let image, image.size.width > 0, image.size.height > 0 {
            let scale = min(picture.width/image.size.width,picture.height/image.size.height)
            let size = NSSize(width:image.size.width*scale,height:image.size.height*scale)
            let destination = NSRect(x:picture.midX-size.width/2,y:picture.midY-size.height/2,width:size.width,height:size.height)
            image.draw(in:destination,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        }
        NSGraphicsContext.restoreGraphicsState()
        let titleRect = NSRect(x: card.minX+12, y: card.minY+9, width: card.width-42, height: 17)
        (title as NSString).draw(in: titleRect, withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
        if selected {
            NSColor.controlAccentColor.setFill()
            let check = NSRect(x: card.maxX-28, y: card.minY+9, width: 16, height: 16)
            NSBezierPath(ovalIn: check).fill()
            let tick = NSBezierPath(); tick.move(to: NSPoint(x: check.minX+4, y: check.minY+8)); tick.line(to: NSPoint(x: check.minX+7, y: check.minY+5)); tick.line(to: NSPoint(x: check.minX+12, y: check.minY+11)); tick.lineWidth = 1.7; tick.lineCapStyle = .round; tick.lineJoinStyle = .round; NSColor.white.setStroke(); tick.stroke()
        }
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(hovering ? 0.8 : 0.45)).setStroke()
        shape.lineWidth = selected ? 2 : 0.75; shape.stroke()
    }
}

final class DirectionWheel: NSSlider {
    static func wrap(_ angle: Double) -> Double { let value = angle.truncatingRemainder(dividingBy:360); return value < 0 ? value+360 : value }
    func rotate(by degrees: Double) {
        doubleValue = Self.wrap(doubleValue+degrees)
        if let action { _ = sendAction(action,to:target) }
    }
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        rotate(by:Double(delta)*(event.hasPreciseScrollingDeltas ? 1 : 5))
    }
    override func keyDown(with event: NSEvent) {
        let step: Double = event.modifierFlags.contains(.shift) ? 15 : 1
        switch event.keyCode { case 123,125: rotate(by:-step); case 124,126: rotate(by:step); default: super.keyDown(with:event) }
    }
}

final class PaintControls: NSStackView {
    var changed: ((Configuration.Paint) -> Void)?
    private var paint = Configuration.Paint()
    let type = NSPopUpButton()
    let firstWell = NSColorWell()
    let secondWell = NSColorWell()
    private let extraWells = (0..<4).map { _ in NSColorWell() }
    private var wells: [NSColorWell] { [firstWell, secondWell] + extraWells }
    private var count = 2
    private let colourRow = NSStackView()
    private let add = NSButton(title: "+",target:nil,action:nil)
    private let remove = NSButton(title: "−",target:nil,action:nil)
    let angle = DirectionWheel(value:90,minValue:0,maxValue:360,target:nil,action:nil)
    let angleRow = NSStackView()
    let angleValue = NSTextField(labelWithString:"90°")
    override init(frame: NSRect) { super.init(frame:frame) }
    convenience init(title: String) {
        self.init(frame:.zero); orientation = .vertical; alignment = .leading; spacing = 8
        func row(_ text: String) -> NSStackView {
            let label = NSTextField(labelWithString:text), controls = NSStackView()
            let line = NSStackView(views:[label,NSView(),controls]); line.spacing = 16; line.alignment = .centerY
            controls.spacing = 8; controls.alignment = .centerY; controls.widthAnchor.constraint(equalToConstant:300).isActive = true
            line.heightAnchor.constraint(greaterThanOrEqualToConstant:30).isActive = true
            addArrangedSubview(line); line.widthAnchor.constraint(equalTo:widthAnchor).isActive = true; return controls
        }
        let header = row(title); type.addItems(withTitles:["Single colour","Gradient"]); type.target = self; type.action = #selector(edited(_:)); header.addArrangedSubview(type)
        header.addArrangedSubview(NSView()); header.addArrangedSubview(NSButton(title:"Reset colours",target:self,action:#selector(inherit(_:))))
        let colours = row("Colours"); colourRow.orientation = .horizontal; colourRow.spacing = 6; colourRow.setContentHuggingPriority(.required,for:.horizontal); colours.addArrangedSubview(colourRow)
        for (i,well) in wells.enumerated() {
            if #available(macOS 14.0,*) { well.supportsAlpha = false }
            well.widthAnchor.constraint(equalToConstant:32).isActive = true; well.target = self; well.action = #selector(edited(_:)); well.setAccessibilityLabel("\(title) colour \(i+1)"); colourRow.addArrangedSubview(well)
        }
        for button in [add,remove] { button.target = self; button.action = #selector(changeCount(_:)); button.widthAnchor.constraint(equalToConstant:24).isActive = true; colours.addArrangedSubview(button) }
        add.toolTip = "Add gradient colour (up to six)"; remove.toolTip = "Remove last gradient colour (at least two)"; colours.addArrangedSubview(NSView())
        let direction = row("Direction"); angleRow.orientation = .horizontal; angleRow.spacing = 10; direction.addArrangedSubview(angleRow)
        angle.sliderType = .circular; angle.isContinuous = true; angle.widthAnchor.constraint(equalToConstant:48).isActive = true; angle.heightAnchor.constraint(equalToConstant:48).isActive = true
        angle.toolTip = "Turn or scroll to change direction; wraps at 360°."
        angle.target = self; angle.action = #selector(edited(_:)); angle.setAccessibilityLabel("\(title) gradient direction")
        angleRow.addArrangedSubview(angle); angleRow.addArrangedSubview(angleValue); angleValue.widthAnchor.constraint(equalToConstant:45).isActive = true; angleRow.addArrangedSubview(NSView())
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ value: Configuration.Paint, fallback: NSColor, second: NSColor) {
        paint = value; type.selectItem(at:value.type == "linear" ? 1 : 0)
        count = max(2,value.colors.count)
        for (i,well) in wells.enumerated() { well.color = i < value.colors.count ? NSColor.hex(value.colors[i]) : i == 0 ? fallback : second; well.isHidden = i > 0 && (value.type == "solid" || i >= count) }
        add.isHidden = value.type == "solid"; remove.isHidden = value.type == "solid"; add.isEnabled = count < 6; remove.isEnabled = count > 2
        angleRow.superview?.superview?.isHidden = value.type != "linear"; angle.doubleValue = value.angle; angleValue.stringValue = "\(Int(value.angle.rounded()) % 360)°"
    }
    @objc func edited(_ sender: Any?) {
        func hex(_ color: NSColor) -> String { let c = color.usingColorSpace(.sRGB)!; return String(format:"%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded())) }
        paint.type = type.indexOfSelectedItem == 1 ? "linear" : "solid"
        paint.colors = wells.prefix(count).map { hex($0.color) }
        if (sender as AnyObject?) === angle { paint.angle = DirectionWheel.wrap(angle.doubleValue) }
        changed?(paint)
    }
    @objc func changeCount(_ sender: NSButton) {
        if sender === add && count < 6 { wells[count].color = wells[count-1].color; count += 1 }
        else if sender === remove && count > 2 { count -= 1 }
        edited(sender)
    }
    @objc func inherit(_ sender: Any?) { changed?(Configuration.Paint()) }
}

final class AppearanceDocumentView: NSView { override var isFlipped: Bool { true } }

/// Controls for the single animated colour field.
final class AnimatedBackgroundControls: NSStackView {
    var changed: (([String], Double, Double) -> Void)?
    var reset: (() -> Void)?
    let strength = NSSlider(value: 0.22, minValue: 0, maxValue: 1, target: nil, action: nil)
    let speed = NSSlider(value: 0.5, minValue: 0.05, maxValue: 3, target: nil, action: nil)
    let strengthValue = NSTextField(labelWithString: "22%")
    let speedValue = NSTextField(labelWithString: "0.5×")
    let colourRow = NSStackView()
    let addColour = NSButton(title: "+", target: nil, action: nil)
    let removeColour = NSButton(title: "−", target: nil, action: nil)
    private(set) var wells: [NSColorWell] = []
    private var colorCount = 3
    private var pending: DispatchWorkItem?
    private var mode = "flow"
    override init(frame: NSRect) {
        super.init(frame: frame); orientation = .vertical; alignment = .leading; spacing = 12
        func row(_ title: String) -> NSStackView {
            let controls = NSStackView(); controls.spacing = 8; controls.alignment = .centerY
            let label = NSTextField(labelWithString:title)
            let line = NSStackView(views:[label,NSView(),controls]); line.spacing = 16; line.alignment = .centerY
            controls.widthAnchor.constraint(equalToConstant:300).isActive = true
            line.heightAnchor.constraint(greaterThanOrEqualToConstant:30).isActive = true
            addArrangedSubview(line); line.widthAnchor.constraint(equalTo:widthAnchor).isActive = true; return controls
        }
        let colours = row("Colours"); colourRow.orientation = .horizontal; colourRow.spacing = 6; colourRow.setContentHuggingPriority(.required, for: .horizontal); colours.addArrangedSubview(colourRow)
        for index in 0..<6 {
            let well = NSColorWell()
            if #available(macOS 14.0, *) { well.supportsAlpha = false }
            well.widthAnchor.constraint(equalToConstant: 32).isActive = true; well.target = self; well.action = #selector(edited(_:))
            well.setAccessibilityLabel("Animation colour \(index+1)"); colourRow.addArrangedSubview(well); wells.append(well)
        }
        for button in [addColour, removeColour] { button.target = self; button.action = #selector(changeColourCount(_:)); colours.addArrangedSubview(button); button.widthAnchor.constraint(equalToConstant: 24).isActive = true }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); colours.addArrangedSubview(spacer)
        addColour.toolTip = "Add a colour (up to six)"; addColour.setAccessibilityLabel("Add animation colour")
        removeColour.toolTip = "Remove the last colour (at least two)"; removeColour.setAccessibilityLabel("Remove last animation colour")
        for (title, slider, value) in [("Strength", strength, strengthValue), ("Speed", speed, speedValue)] {
            let line = row(title); slider.target = self; slider.action = #selector(edited(_:)); slider.isContinuous = true
            slider.setAccessibilityLabel("Background \(title.lowercased())")
            line.addArrangedSubview(slider); line.addArrangedSubview(value)
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 50).isActive = true
        }
        addArrangedSubview(NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { pending?.cancel() }
    func update(_ background: Configuration.Background) {
        mode = background.style
        let colors = background.resolvedColors; colorCount = colors.count
        for index in wells.indices { wells[index].isHidden = index >= colorCount; if index < colorCount { wells[index].color = NSColor.hex(colors[index]) } }
        strength.doubleValue = background.intensity; speed.doubleValue = background.speed; updateValues()
        addColour.isEnabled = colorCount < 6; removeColour.isEnabled = colorCount > 2
    }
    private func updateValues() {
        strengthValue.stringValue = "\(Int((strength.doubleValue*100).rounded()))%"
        speedValue.stringValue = String(format: "%.2g×", speed.doubleValue)
    }
    @objc func edited(_ sender: Any?) {
        updateValues(); pending?.cancel()
        let colours = wells.prefix(colorCount).map { well -> String in
            let c = well.color.usingColorSpace(.sRGB)!
            return String(format: "%02X%02X%02X", Int((c.redComponent*255).rounded()), Int((c.greenComponent*255).rounded()), Int((c.blueComponent*255).rounded()))
        }
        let strength = strength.doubleValue, speed = speed.doubleValue, mode = mode
        let next = DispatchWorkItem { [weak self] in guard let self, self.mode == mode else { return }; self.changed?(colours, strength, speed) }
        pending = next; DispatchQueue.main.asyncAfter(deadline: .now()+0.06, execute: next)
    }
    @objc func changeColourCount(_ sender: NSButton) {
        if sender === addColour && colorCount < 6 { wells[colorCount].color = wells[colorCount-1].color; colorCount += 1 }
        else if sender === removeColour && colorCount > 2 { colorCount -= 1 }
        for i in wells.indices { wells[i].isHidden = i >= colorCount }
        addColour.isEnabled = colorCount < 6; removeColour.isEnabled = colorCount > 2; edited(sender)
    }
    @objc func resetDefaults(_ sender: Any?) { pending?.cancel(); reset?() }
}

/// A read-only miniature terminal, using the same renderer and glyph grid as real sessions.
final class TerminalPreviewView: FlowBackgroundView {
    let terminalPane = Pane(config: Configuration(), start: false)
    let chrome = NSView()
    private let shellTitle = NSTextField(labelWithString: "")
    let infoBar = NSView()
    private var infoPlacement: NSLayoutConstraint!
    private var infoHeight: NSLayoutConstraint!
    private var terminalTopInset: NSLayoutConstraint!
    private var terminalBottomInset: NSLayoutConstraint!
    private let glyphImage = NSImageView()
    private var glyphsDirty = true
    private var glyphSize = NSSize.zero
    override init(frame: NSRect) {
        super.init(frame: frame)
        chrome.wantsLayer = true
        for child in [chrome, infoBar, terminalPane] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        terminalTopInset = terminalPane.topAnchor.constraint(equalTo:chrome.bottomAnchor)
        terminalBottomInset = terminalPane.bottomAnchor.constraint(equalTo:bottomAnchor)
        infoHeight = infoBar.heightAnchor.constraint(equalToConstant:28)
        infoPlacement = infoBar.bottomAnchor.constraint(equalTo:bottomAnchor)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor), chrome.trailingAnchor.constraint(equalTo: trailingAnchor), chrome.topAnchor.constraint(equalTo: topAnchor), chrome.heightAnchor.constraint(equalToConstant: 28),
            terminalPane.leadingAnchor.constraint(equalTo: leadingAnchor), terminalPane.trailingAnchor.constraint(equalTo: trailingAnchor), terminalTopInset, terminalBottomInset,
            infoBar.leadingAnchor.constraint(equalTo:leadingAnchor),infoBar.trailingAnchor.constraint(equalTo:trailingAnchor),infoHeight,infoPlacement
        ])
        for (index, kind) in [NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton].enumerated() {
            guard let light = NSWindow.standardWindowButton(kind,for:[.titled,.closable,.miniaturizable,.resizable]) else { continue }
            light.translatesAutoresizingMaskIntoConstraints = false; chrome.addSubview(light)
            NSLayoutConstraint.activate([light.widthAnchor.constraint(equalToConstant:14),light.heightAnchor.constraint(equalToConstant:16),light.leadingAnchor.constraint(equalTo:chrome.leadingAnchor,constant:8+CGFloat(index)*23),light.topAnchor.constraint(equalTo:chrome.topAnchor,constant:8)])
        }
        shellTitle.font = .systemFont(ofSize:10); shellTitle.translatesAutoresizingMaskIntoConstraints = false; infoBar.addSubview(shellTitle)
        NSLayoutConstraint.activate([shellTitle.trailingAnchor.constraint(equalTo:infoBar.trailingAnchor,constant:-12),shellTitle.centerYAnchor.constraint(equalTo:infoBar.centerYAnchor)])
        terminalPane.terminal.readOnly = true
        terminalPane.terminal.caretViewTracksFocus = false
        // A transparent snapshot uses the real terminal renderer while avoiding a
        // second live terminal layer competing with the animated preview surface.
        terminalPane.terminal.isHidden = true
        glyphImage.imageScaling = .scaleAxesIndependently; glyphImage.translatesAutoresizingMaskIntoConstraints = false; addSubview(glyphImage)
        NSLayoutConstraint.activate([glyphImage.leadingAnchor.constraint(equalTo:terminalPane.terminal.leadingAnchor),glyphImage.trailingAnchor.constraint(equalTo:terminalPane.terminal.trailingAnchor),glyphImage.topAnchor.constraint(equalTo:terminalPane.terminal.topAnchor),glyphImage.bottomAnchor.constraint(equalTo:terminalPane.terminal.bottomAnchor)])
        setAccessibilityLabel("Terminal preview")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout(); terminalPane.layoutSubtreeIfNeeded()
        renderGlyphs()
    }
    private func renderGlyphs() {
        let terminal = terminalPane.terminal, size = terminal.bounds.size
        guard size.width > 0,size.height > 0,glyphsDirty || size != glyphSize else { return }
        glyphsDirty = false; glyphSize = size
        let scale = window?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*scale),pixelsHigh:Int(size.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return }
        memset(bitmap.bitmapData!,0,bitmap.bytesPerRow*bitmap.pixelsHigh)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x:scale,y:scale); terminal.draw(terminal.bounds)
        NSGraphicsContext.restoreGraphicsState()
        if let image = bitmap.cgImage { glyphImage.image = NSImage(cgImage:image,size:size) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func apply(_ configuration: Configuration) {
        var config = configuration; config.scrollback = 0; config.advanced.logDirectory = ""
        super.apply(config); terminalPane.apply(config)
        appearance = NSAppearance(named:config.selectedTheme.light ? .aqua : .darkAqua)
        chrome.layer?.backgroundColor = NSColor.clear.cgColor
        shellTitle.textColor = config.colors.1.withAlphaComponent(0.6)
        let hasInfo = config.window.showStatusBar
        let atTop = config.window.chromePosition == "titlebar"
        infoPlacement.isActive = false
        infoPlacement = atTop ? infoBar.topAnchor.constraint(equalTo:chrome.bottomAnchor) : infoBar.bottomAnchor.constraint(equalTo:bottomAnchor)
        infoPlacement.isActive = true; infoHeight.constant = hasInfo ? 28 : 0; infoBar.isHidden = !hasInfo
        terminalTopInset.constant = hasInfo && atTop ? 28 : 0
        terminalBottomInset.constant = hasInfo && !atTop ? -28 : 0
        shellTitle.stringValue = "moth:~   ·   \(terminalPane.terminal.getTerminal().cols) × \(terminalPane.terminal.getTerminal().rows)"
        let rgb = config.colors.2.usingColorSpace(.sRGB)!
        let prompt = "\u{1b}[38;2;\(Int(rgb.redComponent*255));\(Int(rgb.greenComponent*255));\(Int(rgb.blueComponent*255))m$\u{1b}[0m"
        terminalPane.terminal.getTerminal().resetFromHost()
        let normal = (0..<8).map { "\u{1b}[\(30+$0)m██ \u{1b}[0m" }.joined()
        let bright = (0..<8).map { "\u{1b}[\(90+$0)m██ \u{1b}[0m" }.joined()
        terminalPane.terminal.feed(text:"\(prompt) echo \"Hello, Moth.\"\r\nHello, Moth.\r\n->  !=  ===  0O  1lI\r\n\(normal)\r\n\(bright)")
        glyphsDirty = true; needsLayout = true; renderGlyphs()
    }
}
