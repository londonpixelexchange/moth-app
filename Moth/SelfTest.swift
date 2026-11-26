// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import AVFoundation
import SwiftTerm
import CoreText
import TOMLKit
import Darwin
import Metal

// In-process integration checks exercise the exact app binary and vendored core.
// Run Moth.app/Contents/MacOS/Moth --self-test. Results are written to the supplied path.
enum SelfTest {
    static func run(app: App) {
        setbuf(stdout,nil)
        if CommandLine.arguments.contains("--focus-only") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                var checks: [String:Bool] = [:];activationClickChecks(app:app,into:&checks)
                let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!
                try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
                print(checks);app.windows.forEach { $0.stop() };exit(checks.values.allSatisfy { $0 } ? 0:1)
            }
            return
        }
        if CommandLine.arguments.contains("--gloam-only") { LiveAnimationChecks(app).run();return }
        if CommandLine.arguments.contains("--animation-only") { AnimatedColourChecks.run(app);return }
        if CommandLine.arguments.contains("--keyboard-only") {
            var checks: [String:Bool] = [:];keyboardInputChecks(into:&checks)
            HeldKeyPTYChecks.run(app) { live in
                checks.merge(live) { _,new in new }
                let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!
                try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
                print(checks);app.windows.forEach { $0.stop() };exit(checks.values.allSatisfy { $0 } ? 0:1)
            }
            return
        }
        if CommandLine.arguments.contains("--resize-only") { ResizeWindowChecks(app).run();return }
        if CommandLine.arguments.contains("--manuals-only") { ManualViewerChecks(app).run();return }
        if CommandLine.arguments.contains("--metal-only") { MetalPresentationChecks(app).run();return }
        if CommandLine.arguments.contains("--lifecycle-only") { BackgroundLifecycleChecks(app).run();return }
        if CommandLine.arguments.contains("--panes-only") {
            var checks:[String:Bool]=[:];splitGeometryChecks(into:&checks);paneMaximizationChecks(into:&checks)
            livePaneMaximizationChecks { live in
                checks.merge(live){_,new in new}
                let output=ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-pane-results.json"
                try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
                print(checks);app.windows.forEach{$0.stop()};exit(checks.values.allSatisfy{$0} ? 0:1)
            }
            return
        }
        if CommandLine.arguments.contains("--transfers-only") { TabTransferChecks(app).run(); return }
        if CommandLine.arguments.contains("--updates-only") { UpdateAndPromptChecks.run(app); return }
        if CommandLine.arguments.contains("--vt-only") { VTCompatibilityChecks.run(app); return }
        if CommandLine.arguments.contains("--fonts-only") { FullFontFamilyChecks.run(app); return }
        if CommandLine.arguments.contains("--pictures-only") { BackgroundPictureChecks.run(app); return }
        if CommandLine.arguments.contains("--blink-only") { TextBlinkChecks(app).run(); return }
        if CommandLine.arguments.contains("--links-only") { LinkOpeningChecks.run(app); return }
        if CommandLine.arguments.contains("--tabs-only") { TabOverflowChecks.run(app); return }
        if CommandLine.arguments.contains("--directory-only") { DirectoryInheritanceChecks.run(app); return }
        if CommandLine.arguments.contains("--recovery-only") {
            let probe = SessionRecoveryProbe.start()
            func finish() {
                guard probe.finished else { DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { finish() }; return }
                let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-recovery-results.json"
                try! JSONSerialization.data(withJSONObject:probe.results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
                print(probe.results); app.windows.forEach { $0.stop() }; exit(probe.results.values.allSatisfy { $0 } ? 0 : 1)
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { finish() }; return
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+45) { print("Self-test timed out"); app.windows.forEach { $0.stop() }; exit(2) }
        var checks: [String: Bool] = [:]
        let host = app.active!
        let outputFolder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json").deletingLastPathComponent()
        try! Data(Configuration.document(Configuration()).utf8).write(to: outputFolder.appendingPathComponent("config.example.toml"))
        var minimal = Configuration(); minimal.window.showStatusBar = false; minimal.window.showTabBar = false; minimal.window.borderWidth = 0; minimal.window.showBorder = false; minimal.background.style = "solid"; minimal.cursor.shape = "bar"; minimal.cursor.animation = "noblink"
        try! Data(Configuration.document(minimal).utf8).write(to: outputFolder.appendingPathComponent("config.minimal.example.toml"))
        checks["bundledNerdFont"] = NSFont(name: app.config.fontName, size: 14) != nil
        let terminal = host.workspace.active.terminal
        terminal.send(txt: "printf '\\nMoth_PTY_OK\\n'; test -t 0 && echo Moth_IS_TTY; stty size\r")
        app.splitRight(nil); app.splitDown(nil)
        checks["nestedSplits"] = host.workspace.panes.count == 3
        host.workspace.closeActive()
        checks["closeSplit"] = host.workspace.panes.count == 2
        app.newTab(nil); checks["independentTabs"] = host.workspaces.count == 2
        let command1 = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: host.window!.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
        let command2 = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: host.window!.windowNumber, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19)!
        checks["command1SelectsFirstTab"] = NSApp.mainMenu?.performKeyEquivalent(with: command1) == true && host.index == 0
        checks["command2SelectsSecondTab"] = NSApp.mainMenu?.performKeyEquivalent(with: command2) == true && host.index == 1
        host.selectTab(at: 8)
        checks["missingTabDoesNotChangeSelection"] = host.index == 1
        host.index = 0; host.showWorkspace()
        host.window!.setContentSize(NSSize(width: 1000, height: 650)); host.window!.contentView?.layoutSubtreeIfNeeded()
        let colors = Pane(config: app.config, start: false)
        colors.terminal.feed(text: "\u{1b}[31mRED\u{1b}[0m\r\n\u{1b}[38;2;12;34;56mTRUE\u{1b}[0m")
        checks["ansiText"] = colors.terminal.getTerminal().getLine(row: 0)?.translateToString(trimRight: true).contains("RED") == true
        checks["truecolorAttribute"] = colors.terminal.getTerminal().getCharData(col: 0, row: 1)?.attribute.fg == .trueColor(red: 12, green: 34, blue: 56)
        checks["truecolorText"] = colors.terminal.getTerminal().getLine(row: 1)?.translateToString(trimRight: true).contains("TRUE") == true
        let history = Pane(config: app.config, start: false)
        history.terminal.feed(text: "HISTORY_START\r\n" + (0..<80).map { "line \($0)\r\n" }.joined())
        checks["scrollbackPreserved"] = history.terminal.getTerminal().getScrollInvariantLine(row: 0)?.translateToString(trimRight: true).contains("HISTORY_START") == true
        colors.terminal.feed(text: "\u{1b}[?1049hALT\u{1b}[?1049l")
        checks["alternateScreenRestored"] = colors.terminal.getTerminal().getLine(row: 0)?.translateToString(trimRight: true).contains("RED") == true
        // Preserve every pasteboard representation around the copy/paste integration check.
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        colors.terminal.selectAll(nil); colors.terminal.copy(self)
        checks["selectionCopy"] = board.string(forType: .string)?.contains("RED") == true
        board.clearContents(); board.setString("printf '\\nMoth_PASTE_OK\\n'", forType: .string)
        terminal.paste(self); terminal.send(txt: "\r")
        board.clearContents()
        let restored = saved.map { entries -> NSPasteboardItem in let item = NSPasteboardItem(); entries.forEach { item.setData($0.1, forType: $0.0) }; return item }
        board.writeObjects(restored)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
            terminal.send(txt: "printf 'Moth_SIZE='; stty size\r")
        }
        // Exercise Sixel through the real AppKit image renderer, then sample its pixels.
        let graphics = Pane(config: Configuration(), start: false)
        let graphicsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        graphicsWindow.contentView = graphics
        graphicsWindow.orderFront(nil); graphicsWindow.contentView?.layoutSubtreeIfNeeded()
        graphics.terminal.feed(text: "\u{1b}Pq\"1;1;240;60#0;2;65;72;100#1;2;55;85;70#2;2;100;70;45" + String(repeating: "#0!80~#1!80~#2!80~-", count: 10) + "\u{1b}\\\r\nAFTER_IMAGE")
        checks["sixelAttached"] = graphics.terminal.getTerminal().buffer.hasAnyImages
        if let bitmap = graphics.terminal.bitmapImageRepForCachingDisplay(in: graphics.terminal.bounds) {
            graphics.terminal.cacheDisplay(in: graphics.terminal.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                let resultPath = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
                try? png.write(to: URL(fileURLWithPath: resultPath).deletingLastPathComponent().appendingPathComponent("SixelProbe.png"))
            }
            var found = false
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.85, color.redComponent - color.greenComponent > 0.1, color.greenComponent - color.blueComponent > 0.1 { found = true; break }
                }
                if found { break }
            }
            checks["sixelRenderedPixels"] = found
        } else { checks["sixelRenderedPixels"] = false }
        for width in [360.0, 900.0, 420.0, 640.0] {
            graphicsWindow.setContentSize(NSSize(width: width, height: 400)); graphics.layoutSubtreeIfNeeded()
        }
        if let bitmap = graphics.terminal.bitmapImageRepForCachingDisplay(in: graphics.terminal.bounds) {
            graphics.terminal.cacheDisplay(in: graphics.terminal.bounds, to: bitmap)
            var found = false
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) { for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.85, color.redComponent-color.greenComponent > 0.1, color.greenComponent-color.blueComponent > 0.1 { found = true }
            } }
            checks["sixelSurvivesRepeatedWindowResize"] = found && graphics.terminal.getTerminal().buffer.hasAnyImages
        } else { checks["sixelSurvivesRepeatedWindowResize"] = false }
        graphicsWindow.orderOut(nil)
        checks["configRoundTrip"] = (try? JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(app.config)))?.fontName == app.config.fontName
        checks["invalidShortcutRejected"] = Configuration.shortcut("bogus+t") == nil
        checks["powerlineCellAlignment"] = powerlineCellAlignment()
        checks["transparentRedrawMatchesFreshFrame"] = transparentRedrawMatchesFreshFrame()
        checks["textRunsStayOnGrid"] = textRunsStayOnGrid()
        checks["boxDrawingUsesSameGridAsText"] = boxDrawingUsesSameGridAsText()
        fileDropChecks(into: &checks)
        definitionChecks(into: &checks)
        manualChecks(into: &checks)
        alternateHistoryChecks(into: &checks)
        wheelChecks(into: &checks)
        appearanceFeatureChecks(app: app, into: &checks)
        bellChecks(into: &checks)
        encodingChecks(into:&checks)
        inverseVideoChecks(into:&checks)
        typographyChecks(app:app,into:&checks)
        preferenceResetChecks(into:&checks)
        let chromeSaved = app.config
        let chromePIDs = host.workspaces.flatMap(\.panes).map { $0.terminal.process.shellPid }
        app.config.window.chromePosition = "titlebar"; app.applyAppearance()
        checks["tabsMoveIntoNativeTitlebar"] = host.window!.titlebarAccessoryViewControllers.contains { host.footer.isDescendant(of:$0.view) }
        app.config = chromeSaved; app.applyAppearance()
        checks["movingChromeBackPreservesSessions"] = host.footer.superview === host.content && chromePIDs == host.workspaces.flatMap(\.panes).map { $0.terminal.process.shellPid }
        checks["helpMenuOffersDocumentation"] = NSApp.mainMenu?.items.first(where:{$0.title == "Help"})?.submenu?.items.contains(where:{$0.action == #selector(App.showDocumentation(_:)) && $0.title == "Documentation"}) == true
        let identity=MothBuild.identity
        checks["buildIdentityRecordsGitCommit"] = identity.map { (40...64).contains($0.commit.count) && $0.commit.allSatisfy({$0.isHexDigit}) && $0.commit.hasPrefix($0.shortCommit) && $0.shortCommit.count>=7 } ?? false
        checks["visibleBuildUsesCommitHash"] = MothBuild.identifier.hasPrefix(identity?.shortCommit ?? "missing")
        checks["internalBuildRemainsNumeric"] = Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "") != nil
        let releaseNotes = try? MothReleaseNotes.load()
        checks["bundledReleaseNotesIncludePublicRelease"] = releaseNotes?.contains { $0.version == "0.27.0" && $0.status == "released" && !$0.sections.isEmpty } == true
        checks["releaseNoteStatusesAreValid"] = releaseNotes?.allSatisfy { ["released","unreleased"].contains($0.status) } == true
        checks["helpMenuOffersReleaseNotes"] = NSApp.mainMenu?.items.first(where:{$0.title == "Help"})?.submenu?.items.contains(where:{$0.action == #selector(App.showReleaseNotes(_:)) && $0.title == "What’s New?"}) == true
        let notesWindow = ReleaseNotesWindowController()
        checks["releaseNotesWindowHasReadableContent"] = notesWindow.textView.string.contains(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "missing") && notesWindow.textView.string.contains("0.27.0")
        checks["unreleasedLabelMatchesReleaseMetadata"] = notesWindow.textView.string.contains("Unreleased") == (releaseNotes?.contains(where:{$0.status == "unreleased"}) == true)
        keyboardInputChecks(into:&checks)
        keyboardSoundChecks(app:app,into:&checks)
        developmentChecks(app:app,into:&checks)
        windowGlassChecks(into: &checks)
        cursorChecks(into: &checks)
        configurationExpansionChecks(into: &checks)
        closePolicyChecks(into: &checks)
        themeCatalogueChecks(app: app, into: &checks)
        for style in Configuration.backgroundStyles {
            var preset = app.config; preset.background.style = style
            do { try preset.validate(); let view = FlowBackgroundView(frame: NSRect(x: 0, y: 0, width: 320, height: 180)); view.apply(preset); view.layoutSubtreeIfNeeded(); let pane = Pane(config: preset, start: false); let expectedAlpha: CGFloat = style == "solid" || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0; checks["background_\(style)"] = view.layer != nil && pane.terminal.nativeBackgroundColor.alphaComponent == expectedAlpha && (style != "flow" || view.frameImage != nil) } catch { checks["background_\(style)"] = false }
        }
        backgroundGallery()
        let fireWindow = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 360,height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        let fireView = FlowBackgroundView(frame: .zero)
        var fireConfig = Configuration(); fireConfig.background.style = "flow"; fireConfig.background.speed = 3
        fireWindow.contentView = fireView; fireView.apply(fireConfig); fireWindow.orderFront(nil)
        var firstFireSample: Int?
        DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { firstFireSample = fireView.presentedFrames }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.2) {
            let later = fireView.presentedFrames
            checks["flowFieldAnimatesOnScreen"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || !fireWindow.occlusionState.contains(.visible) || (firstFireSample != nil && later > firstFireSample!)
            fireWindow.orderOut(nil)
        }
        let job = Process(); job.executableURL = URL(fileURLWithPath: "/bin/zsh"); job.arguments = ["-c", "sleep 30 & wait"]
        try! job.run()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
            let assessment = ProcessInspector.assess(shellPID: job.processIdentifier)
            checks["backgroundJobsStillRequireConfirmation"] = assessment.requiringConfirmation(Configuration.CloseConfirmation()).contains("sleep")
            for program in assessment.programs { kill(program.pid, SIGTERM) }
            if job.isRunning { job.terminate() }
        }
        let tmuxScroll = startTmuxScrollCheck()
        let fullScreenChecks = startFullScreenChecks()
        let screenChecks = startGNUScreenChecks()
        let liveMonitor = startMonitorCheck()
        let htopMonitor = startMonitorCheck(program: "htop")
        let cleanEnvironment = ShellEnvironment.session(inherited: ["NO_COLOR": "1", "TERM": "dumb", "COLORTERM": "", "PATH": "/test/path"])
        checks["sessionsAdvertiseColourCapabilities"] = cleanEnvironment["NO_COLOR"] == nil && cleanEnvironment["TERM"] == "xterm-256color" && cleanEnvironment["COLORTERM"] == "truecolor" && cleanEnvironment["PATH"] == "/test/path"
        let originalFont = app.config.fontSize
        let commandN = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: host.window!.windowNumber, context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45)!
        checks["newWindowShortcut"] = NSApp.mainMenu?.performKeyEquivalent(with: commandN) == true
        let second = app.active!
        checks["newWindowIndependentPTY"] = app.windows.count == 2 && second.workspace.active.terminal.process.shellPid != host.workspace.active.terminal.process.shellPid
        checks["nativeAnimatedBackground"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || (host.window?.occlusionState.contains(.visible) == true ? host.content.animationCount > 0:host.content.animationCount == 0)
        checks["minimalTitlebar"] = host.window!.toolbar == nil && host.window!.titleVisibility == .hidden
        checks["noPaneHeaders"] = host.workspace.panes.allSatisfy { $0.label.superview == nil && $0.dimensions.superview == nil }
        NSApp.mainMenu?.performKeyEquivalent(with: command2)
        checks["tabShortcutsStayInActiveWindow"] = host.index == 0 && second.index == 0
        host.window!.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
            var config = app.config; config.fontSize = originalFont + 1
            config.window.showStatusBar = false; config.window.showTabBar = false
            config.window.borderColor = "AA55CC"
            config.window.opacity = 0.65; config.window.frosted = true
            config.bell.mode = "off"
            config.cursor.shape = "bar"; config.cursor.animation = "noblink"
            try! Configuration.save(config)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.8) {
            checks["appearancePanelReflectsFileReload"] = (app.appearancePanel?.fields["fontSize"] as? NSTextField)?.doubleValue == originalFont+1 && (app.appearancePanel?.fields["cursor.shape"] as? NSPopUpButton)?.titleOfSelectedItem == "Bar"
            checks["liveReloadAtomicSave"] = app.config.fontSize == originalFont + 1 && host.workspace.active.terminal.font.pointSize == originalFont + 1 && second.workspace.active.terminal.font.pointSize == originalFont + 1
            if checks["liveReloadAtomicSave"] == false { print("Reload diagnostic:",app.config.fontSize,originalFont+1,"disk:",String(describing:try? Configuration.load().fontSize),"error:",String(describing:app.configError)) }
            for controller in [host,second] { controller.workspace.active.terminal.feed(text: "\u{7}") }
            checks["bellPreferencesReloadAcrossWindows"] = [host,second].allSatisfy { $0.workspace.active.bellLayer.animation(forKey: "visualBell") == nil && $0.workspace.active.bellSound == nil }
            checks["cursorReloadsAcrossWindows"] = [host, second].allSatisfy { $0.workspace.active.terminal.getTerminal().options.cursorStyle == .steadyBar }
            checks["footerCanBeHidden"] = host.footer.isHidden && host.footerHeight.constant == 0
            checks["liveBorderColour"] = (host.content.borderPaintLayer.colors as? [CGColor])?.first == NSColor.hex("AA55CC").cgColor
            checks["windowGlassReloadsAcrossWindows"] = [host, second].allSatisfy { $0.window?.alphaValue == 1 && $0.window?.isOpaque == (app.config.windowBackgroundOpacity == 1) && abs(Double($0.content.backgroundOpacity)-Double(app.config.windowBackgroundOpacity)) < 0.001 && $0.content.frost.isHidden == !app.config.usesFrosting }
            try! Data("{ invalid".utf8).write(to: Configuration.url, options: .atomic)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.5) {
            checks["appearancePanelShowsFileErrors"] = app.appearancePanel?.errorLabel.isHidden == false
            checks["invalidReloadKeepsLastGood"] = app.config.fontSize == originalFont + 1 && app.configError != nil
            var config = app.config; config.fontSize = originalFont + 2; config.background.animated = false
            let text = try! Configuration.document(config)
            try! Data(text.utf8).write(to: Configuration.url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+2.2) {
            checks["appearancePanelClearsFileErrors"] = app.appearancePanel?.errorLabel.isHidden == true
            checks["liveReloadInPlaceSave"] = app.config.fontSize == originalFont + 2 && app.configError == nil
            checks["backgroundMotionCanStop"] = host.content.animationCount == 0
            terminal.send(txt: "printf 'Moth_SIZE='; stty size\r")
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+3.2) {
            let text = (0..<500).compactMap { terminal.getTerminal().getScrollInvariantLine(row: $0)?.translateToString(trimRight: true) }.joined(separator: "\n")
            checks["realPTYOutput"] = text.contains("Moth_PTY_OK") && text.contains("Moth_IS_TTY")
            checks["pasteIntoPTY"] = text.contains("Moth_PASTE_OK")
            checks["resize"] = text.contains("Moth_SIZE=\(terminal.getTerminal().rows) \(terminal.getTerminal().cols)")
            if let monitor = liveMonitor {
                let text = (0..<monitor.1.terminal.getTerminal().rows).compactMap { monitor.1.terminal.getTerminal().getLine(row: $0)?.translateToString(trimRight: true) }.joined(separator: "\n")
                checks["btmLivePTY"] = monitor.1.terminal.process.running && text.contains("CPU") && text.contains("Processes")
                checks["btmProducesColours"] = colourCount(monitor.1) > 2
                if let view = monitor.0.contentView { capturePreview(view, name: "BtmPreview.png") }
                monitor.1.stop(); monitor.0.orderOut(nil)
            }
            if let monitor = htopMonitor {
                checks["htopProducesColours"] = monitor.1.terminal.process.running && colourCount(monitor.1) > 2
                if let view = monitor.0.contentView { capturePreview(view, name: "HtopPreview.png") }
                monitor.1.stop(); monitor.0.orderOut(nil)
            }
            checks.merge(fullScreenChecks.results) { _, new in new }; fullScreenChecks.stop()
            checks.merge(screenChecks.results) { _, new in new }; screenChecks.stop()
            if let tmuxScroll { checks.merge(tmuxScroll.results) { _, new in new }; tmuxScroll.stop() }
            let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
            app.config = Configuration(); try! Configuration.save(app.config); app.applyAppearance()
            app.newWindow(nil)
            let preview = app.active!
            runningCursorChecks(app: app, controller: preview) { motionChecks in
                checks.merge(motionChecks) { _, new in new }
                preview.content.layoutSubtreeIfNeeded()
                preview.content.layer?.displayIfNeeded()
                let size = preview.content.bounds.size, scale: CGFloat = 2
                if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width*scale), pixelsHigh: Int(size.height*scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                    context.cgContext.scaleBy(x: scale, y: scale)
                    preview.content.layer?.render(in: context.cgContext)
                    if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("WindowPreview.png")) }
                }
                resetShortcutChecks(app: app, into: &checks)
                navigationChecks(app: app, into: &checks)
                activationClickChecks(app:app,into:&checks)
                paneClosingChecks(app:app,into:&checks)
                splitGeometryChecks(into:&checks)
                paneMaximizationChecks(into:&checks)
                savedLayoutChecks(app:app,into:&checks)
                profileChecks { profileResults in
                checks.merge(profileResults) { _,new in new }
                encodingPTYChecks { encodingResults in
                checks.merge(encodingResults) { _,new in new }
                sessionExitChecks { exitChecks in
                checks.merge(exitChecks) { _,new in new }
                macroPTYChecks { macroChecks in
                checks.merge(macroChecks) { _,new in new }
                runPlainMoshChecks { moshChecks in
                    checks.merge(moshChecks) { _, new in new }
                    let data = try! JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
                    try! data.write(to: URL(fileURLWithPath: output))
                    app.windows.forEach { $0.stop() }
                    exit(checks.values.allSatisfy { $0 } ? 0 : 1)
                }
                }
                }
                }
                }
            }
        }
    }
    static func waitFor(_ condition: @escaping ()->Bool,timeout: Double = 2,_ completion: @escaping (Bool)->Void) {
        let deadline = ProcessInfo.processInfo.systemUptime+timeout
        func poll() { if condition() { completion(true) } else if ProcessInfo.processInfo.systemUptime >= deadline { completion(false) } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.03) { poll() } } }
        poll()
    }
    static func encodingChecks(into checks: inout [String:Bool]) {
        checks["encodingCatalogIncludesUnicodeAndLegacyCharsets"] = TerminalTextEncoding.choices.count >= 15 && TerminalTextEncoding.choices.contains { $0.id == "SHIFT_JIS" }
        let latin = TerminalTranscoder("ISO-8859-1"), western = TerminalTranscoder("WINDOWS-1252")
        checks["legacyOutputDecodesAccentedAndEuroText"] = String(bytes:latin.decode([0x63,0x61,0x66,0xe9]),encoding:.utf8) == "café" && String(bytes:western.decode([0x80]),encoding:.utf8) == "€"
        checks["legacyInputEncodesActualBytes"] = western.encode(Array("café €".utf8)[...]) == [0x63,0x61,0x66,0xe9,0x20,0x80]
        let japanese = TerminalTranscoder("SHIFT_JIS")
        checks["multibyteDecoderRetainsPartialCharacter"] = japanese.decode([0x82]).isEmpty && String(bytes:japanese.decode([0xa0]),encoding:.utf8) == "あ"
        let big5 = TerminalTranscoder("BIG5")
        checks["big5DecoderRetainsPartialCharacter"] = big5.decode([0xa4]).isEmpty && String(bytes:big5.decode([0x40]),encoding:.utf8) == "一"
        let gb = TerminalTranscoder("GB18030"), text = "😀"
        if let bytes = gb.encode(Array(text.utf8)[...]) {
            let decoded = bytes.flatMap { gb.decode([$0]) }
            checks["gb18030FourByteSequencesSurviveReadBoundaries"] = bytes.count == 4 && String(bytes:decoded,encoding:.utf8) == text
        } else { checks["gb18030FourByteSequencesSurviveReadBoundaries"] = false }
        let malformed = TerminalTranscoder("SHIFT_JIS")
        _ = malformed.decode([0x82]); checks["truncatedLegacyCharacterProducesReplacementAtExit"] = String(bytes:malformed.decode([],final:true),encoding:.utf8) == "�"
        let control = Array("\u{1b}[31mASCII\u{1b}[0m\r\n\u{1b}Pq~\u{1b}\\".utf8)
        checks["allEncodingsPreserveTerminalControlSequences"] = TerminalTextEncoding.choices.allSatisfy { item in let codec = TerminalTranscoder(item.id); return codec.decode(control[...]) == control && codec.encode(control[...]) == control }
        checks["unrepresentableTextIsRejectedWithoutLossySubstitution"] = TerminalTranscoder("ASCII").encode(Array("☃".utf8)[...]) == nil
        let utf8 = Array("界👩‍💻é".utf8), unicode = TerminalTranscoder("UTF-8")
        checks["utf8RemainsByteForByteFastPath"] = utf8.flatMap { unicode.decode([$0]) } == utf8
    }
    static func encodingPTYChecks(completion: @escaping ([String:Bool])->Void) {
        var config = Configuration(); config.shell = "/bin/sh"; config.advanced.loginShell = false; config.advanced.environment["ENV"] = "/dev/null"; config.textEncoding = "WINDOWS-1252"
        let pane = Pane(config:config,start:true), terminal = pane.terminal
        terminal.sendUserText("stty -echo; /usr/bin/printf '\\351\\200\\nENC_READY\\n'; IFS= read -r line; /usr/bin/printf 'RECEIVED=%s\\n' \"$line\"\r")
        waitFor({ terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("ENC_READY") },timeout:3) { ready in
            var checks: [String:Bool] = [:]
            checks["legacyPTYOutputRendersUnicode"] = ready && terminal.getTerminal().exportPlainText().contains("é€")
            terminal.sendUserText("café €\r")
            waitFor({ terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("RECEIVED=café €") },timeout:3) { received in
                checks["legacyPTYInputRoundTripsThroughRealShell"] = received
                terminal.configureTextEncoding("ASCII"); terminal.sendUserText("☃")
                checks["unrepresentableInputExplainsEncodingFailure"] = terminal.lastEncodingError?.contains("UTF-8") == true
                pane.stop(); completion(checks)
            }
        }
    }
    static func profileChecks(completion: @escaping ([String:Bool])->Void) {
        var checks: [String:Bool] = [:]
        let folder = Configuration.url.deletingLastPathComponent().appendingPathComponent("profile-fixtures",isDirectory:true)
        let app = App(); app.profileDirectory = folder; app.config = Configuration(); app.config.advanced.loginShell = false; app.config.advanced.environment["ZDOTDIR"] = Configuration.url.deletingLastPathComponent().path
        let originalDocument = try? Data(contentsOf:Configuration.url)
        var cool = app.config; cool.theme = "moth-dark"; cool.fontSize = 13; cool.window.opacity = 0.82; cool.cursor.shape = "bar"; cool.closeOnExit = false; cool.advanced.workingDirectory = Configuration.url.deletingLastPathComponent().path; cool.advanced.environment["MOTH_PROFILE"] = "cool"
        var warm = app.config; warm.theme = "moth-light"; warm.fontName = "IBMPlexMono"; warm.fontSize = 17; warm.window.opacity = 1; warm.cursor.shape = "underline"; warm.advanced.environment["MOTH_PROFILE"] = "warm"
        var first = TerminalProfile(name:"Cool Work",configuration:cool), second = TerminalProfile(name:"Warm Notes",configuration:warm)
        var watcher: ProfilesWatcher?
        func finish() {
            watcher = nil
            for controller in app.windows { controller.stop(); controller.window?.close() }
            app.appearancePanel?.window?.close(); app.appearancePanel = nil
            if let originalDocument { try? originalDocument.write(to:Configuration.url,options:.atomic) }
            try? FileManager.default.removeItem(at:folder)
            completion(checks)
        }
        do {
            try ProfileStore.save(first,base:app.config,in:folder); try ProfileStore.save(second,base:app.config,in:folder); app.reloadProfiles()
            checks["profilesPersistAppearanceAndSessionDefaults"] = app.profiles.count == 2 && app.profile(first.id)?.applying(to:app.config).cursor.shape == "bar" && app.profile(first.id)?.workingDirectory == cool.advanced.workingDirectory && app.profile(first.id)?.environment["MOTH_PROFILE"] == "cool" && app.profile(first.id)?.closeOnExit == false
            app.openWindow(profileID:first.id); let left = app.active!
            app.openWindow(profileID:second.id); let right = app.active!
            let leftPID = left.workspace.active.terminal.process.shellPid, rightPID = right.workspace.active.terminal.process.shellPid
            left.workspace.active.terminal.sendUserText("printf 'PROFILE_LEFT=%s\\nPROFILE_CWD=%s\\n' \"$MOTH_PROFILE\" \"$PWD\"\r")
            right.workspace.active.terminal.sendUserText("printf 'PROFILE_RIGHT=%s\\n' \"$MOTH_PROFILE\"\r")
            checks["differentProfilesCoexistInIndependentWindows"] = left.config.theme == "moth-dark" && right.config.theme == "moth-light" && left.workspace.active.terminal.font.pointSize == 13 && right.workspace.active.terminal.font.pointSize == 17 && left.workspace.active.terminal.font.fontName != right.workspace.active.terminal.font.fontName
            // Compare actual renderer configuration, not just the stored profile.
            checks["profileColoursAndFontsReachEachTerminal"] = left.workspace.active.terminal.nativeForegroundColor == cool.colors.1 && right.workspace.active.terminal.nativeForegroundColor == warm.colors.1 && leftPID != rightPID
            let picker = AppearancePanel(application:app); app.appearancePanel = picker; picker.selectProfile(first.id)
            _ = picker.commit { $0.fontSize = 15; $0.typography.lineHeight = 1.2 }
            let savedFirst = try ProfileStore.load(ProfileStore.url(first.id,in:folder),base:app.config)
            checks["editingProfileLeavesDefaultAndOtherProfileUnchanged"] = left.workspace.active.terminal.font.pointSize == 15 && right.workspace.active.terminal.font.pointSize == 17 && app.config.fontSize == 14 && savedFirst.fontSize == 15
            picker.tabs.selectTabViewItem(withIdentifier:"Profiles"); picker.showWindow(nil); picker.window?.contentView?.layoutSubtreeIfNeeded()
            if let root = picker.window?.contentView,let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds) {
                root.cacheDisplay(in:root.bounds,to:bitmap)
                try? bitmap.representation(using:.png,properties:[:])?.write(to:Configuration.url.deletingLastPathComponent().appendingPathComponent("ProfilesEditorPreview.png"))
                let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!).deletingLastPathComponent()
                try? bitmap.representation(using:.png,properties:[:])?.write(to:output.appendingPathComponent("ProfilesEditorPreview.png"))
            }
            checks["profileEditsPreserveRunningShells"] = left.workspace.active.terminal.process.shellPid == leftPID && right.workspace.active.terminal.process.shellPid == rightPID
            let layout = try SavedWindowLayout.capture(left,name:"Profile layout")
            let data = try JSONEncoder().encode(layout), restored = try JSONDecoder().decode(SavedWindowLayout.self,from:data)
            checks["savedLayoutsRetainProfileIdentity"] = restored.profileID == first.id
            app.config.defaultProfileID = second.id; app.newWindow(nil); let defaultWindow = app.active!
            checks["newWindowsUseSelectedDefaultProfile"] = defaultWindow.profileID == second.id && defaultWindow.config.fontSize == 17
            defaultWindow.stop(); defaultWindow.window?.close()
            // Rename keeps IDs stable, including already-open windows and saved layouts.
            first = app.profile(first.id)!; first.name = "Cool Renamed"; try ProfileStore.save(first,base:app.config,in:folder); app.reloadProfiles(); app.applyAppearance()
            checks["profileRenameKeepsOpenWindowsAndIdentity"] = left.profileID == first.id && left.profileSnapshot?.name == "Cool Renamed" && restored.profileID == left.profileID
            var painted = first; painted.palette = Configuration.Palette(background:"111111",foreground:"EEEEEE",accent:"AA88FF"); painted.environment["REMOVE_ME"] = "yes"
            try ProfileStore.save(painted,base:app.config,in:folder); painted.palette = nil; painted.environment.removeValue(forKey:"REMOVE_ME"); try ProfileStore.save(painted,base:app.config,in:folder)
            let cleared = try ProfileStore.load(ProfileStore.url(first.id,in:folder),base:app.config)
            checks["profileOverridesCanReturnToDefaults"] = cleared.palette == nil && cleared.environment["REMOVE_ME"] == nil
            // Invalid edits retain the last valid profile, rather than changing its windows.
            try Data("not valid [ toml".utf8).write(to:ProfileStore.url(first.id,in:folder)); app.reloadProfiles(); app.applyAppearance()
            checks["malformedProfileKeepsLastValidWindowSettings"] = app.profileError != nil && left.config.fontSize == 15 && right.config.fontSize == 17
            try ProfileStore.save(second,base:app.config,in:folder)
            try FileManager.default.removeItem(at:ProfileStore.url(first.id,in:folder)); try ProfileStore.save(first,base:app.config,in:folder); app.reloadProfiles()
            watcher = ProfilesWatcher(directory:folder); watcher?.changed = { app.reloadProfiles(); app.applyAppearance() }
            var changed = first; changed.fontSize = 19
            // In-place replacement has the same byte count; timestamps must retain subsecond precision.
            let file = ProfileStore.url(first.id,in:folder), old = try String(contentsOf:file), next = old.replacingOccurrences(of:"fontSize = 15.0",with:"fontSize = 19.0")
            try next.write(to:file,atomically:false,encoding:.utf8)
            waitFor({ left.config.fontSize == 19 },timeout:2) { reloaded in
                checks["profileFilesReloadInPlaceWithoutAffectingOtherWindows"] = reloaded && right.config.fontSize == 17 && left.workspace.active.terminal.process.shellPid == leftPID
                let leftText = left.workspace.active.terminal.getTerminal().exportPlainText(), rightText = right.workspace.active.terminal.getTerminal().exportPlainText()
                checks["profileEnvironmentReachesIndependentShells"] = leftText.components(separatedBy:"\n").contains("PROFILE_LEFT=cool") && rightText.components(separatedBy:"\n").contains("PROFILE_RIGHT=warm")
                let cwd = leftText.components(separatedBy:"\n").first { $0.hasPrefix("PROFILE_CWD=") } ?? ""
                checks["profileStartingDirectoryReachesShell"] = URL(fileURLWithPath:String(cwd.dropFirst("PROFILE_CWD=".count))).resolvingSymlinksInPath().path == URL(fileURLWithPath:cool.advanced.workingDirectory).resolvingSymlinksInPath().path
                right.window?.makeKeyAndOrderFront(nil)
                let selection = NSMenuItem(); selection.representedObject = first.id; app.assignWindowProfile(selection)
                checks["assigningWindowProfilePreservesPTYAndAppliesAppearance"] = right.profileID == first.id && right.config.fontSize == 19 && right.workspace.active.terminal.font.pointSize == 19 && right.workspace.active.terminal.process.shellPid == rightPID
                let activeItem = NSMenuItem(title:"Cool",action:#selector(App.assignWindowProfile(_:)),keyEquivalent:""); activeItem.representedObject = first.id
                checks["windowProfileMenuChecksCurrentProfile"] = app.validateMenuItem(activeItem) && activeItem.state == .on
                do {
                    try ProfileStore.remove(first.id,in:folder); app.reloadProfiles(); app.applyAppearance()
                    checks["deletingProfileKeepsExistingWindowAndShell"] = app.profile(first.id) == nil && left.config.fontSize == 19 && left.workspace.active.terminal.process.shellPid == leftPID && left.workspace.active.terminal.process.running
                    checks["profileDeletionCreatesBackup"] = ((try? FileManager.default.contentsOfDirectory(atPath:folder.path)) ?? []).contains { $0.hasPrefix(first.id+".toml.before-delete-") }
                    right.window?.makeKeyAndOrderFront(nil); right.zoomFontSize = 25; right.applyAppearance()
                    app.changeActiveSettings { $0.fontSize = 20 }
                    checks["detachedProfileEditsDoNotOverwriteDefaultOrOtherWindows"] = right.config.fontSize == 20 && app.config.fontSize == 14 && left.config.fontSize == 19 && right.workspace.active.terminal.process.shellPid == rightPID
                    checks["fontSettingsReplaceTransientWindowZoom"] = right.zoomFontSize == nil && right.workspace.active.terminal.font.pointSize == 20

                } catch { checks["deletingProfileKeepsExistingWindowAndShell"] = false }
                finish()
            }
        } catch { print("Profile checks:",error); checks["profilesPersistAppearanceAndSessionDefaults"] = false; finish() }
    }

    static func sessionExitChecks(completion: @escaping ([String:Bool])->Void) {
        var checks: [String:Bool] = [:]
        let app = App(), retainedApp = App(), fastApp = App()
        for target in [app,retainedApp,fastApp] {
            target.config = Configuration(); target.config.advanced.loginShell = false
            target.config.advanced.environment["ZDOTDIR"] = Configuration.url.deletingLastPathComponent().path
        }
        retainedApp.config.closeOnExit = false
        checks["sessionsCloseOnExitByDefault"] = Configuration().closeOnExit
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("exit-preferences.toml")
        do { try Configuration.save(retainedApp.config,to:path); checks["keepExitedSessionsPreferenceRoundTrips"] = try !Configuration.load(from:path).closeOnExit } catch { checks["keepExitedSessionsPreferenceRoundTrips"] = false }
        app.newWindow(nil); let solo = app.active!, soloPane = app.active!.workspace.active!
        app.newWindow(nil); let split = app.active!, splitWS = split.workspace
        let splitExit = splitWS.active!
        splitWS.split(vertical:true,config:app.config)
        let splitSurvivor = splitWS.active!, splitPID = splitWS.active!.terminal.process.shellPid
        app.newWindow(nil); let tabs = app.active!, tabExit = tabs.workspace.active!
        tabs.newTab(nil); let selectedTab = tabs.workspace, tabPID = tabs.workspace.active!.terminal.process.shellPid
        app.newWindow(nil); let failed = app.active!, failedPane = app.active!.workspace.active!
        retainedApp.newWindow(nil); let retained = retainedApp.active!, retainedPane = retainedApp.active!.workspace.active!
        fastApp.config.shell = "/usr/bin/false"; fastApp.newWindow(nil)
        let ready = [soloPane,splitExit,splitSurvivor,tabExit,selectedTab.active!,failedPane,retainedPane]
        ready.forEach { $0.terminal.send(txt:"printf 'EXIT_READY\\n'\r") }
        func wait(_ condition: @escaping ()->Bool,deadline: TimeInterval,_ done: @escaping (Bool)->Void) {
            if condition() { done(true) }
            else if ProcessInfo.processInfo.systemUptime >= deadline { done(false) }
            else { DispatchQueue.main.asyncAfter(deadline:.now()+0.03) { wait(condition,deadline:deadline,done) } }
        }
        func cleanup() {
            for target in [app,retainedApp,fastApp] { for controller in target.windows { controller.stop(); controller.window?.close() } }
            completion(checks)
        }
        wait({ ready.allSatisfy { $0.terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("EXIT_READY") } },deadline:ProcessInfo.processInfo.systemUptime+3) { isReady in
            checks["ordinaryCommandCompletionKeepsWindowOpen"] = isReady && app.windows.contains(where: { $0 === solo }) && soloPane.terminal.process.running
            soloPane.terminal.send(data:[4]); splitExit.terminal.send(data:[4]); tabExit.terminal.send(data:[4])
            failedPane.terminal.send(txt:"exit 7\r"); retainedPane.terminal.send(txt:"printf 'KEEP_EXIT_OUTPUT\\n'; exit 7\r")
            wait({ soloPane.ended && splitExit.ended && tabExit.ended && failedPane.ended && retainedPane.ended && retainedPane.title.hasPrefix("Exited ·") && retainedPane.terminal.getTerminal().exportPlainText().contains("KEEP_EXIT_OUTPUT") && fastApp.windows.isEmpty && !app.windows.contains(where: { $0 === solo }) && !app.windows.contains(where: { $0 === failed }) && splitWS.panes.count == 1 && tabs.workspaces.count == 1 },deadline:ProcessInfo.processInfo.systemUptime+3) { _ in
                checks["controlDClosesLastSessionWindow"] = soloPane.ended && !app.windows.contains(where: { $0 === solo }) && solo.window?.isVisible == false
                checks["exitedSplitCollapsesWithoutChangingActivePane"] = splitExit.ended && splitWS.panes.count == 1 && splitWS.active === splitSurvivor && splitSurvivor.terminal.process.running && splitSurvivor.terminal.process.shellPid == splitPID && splitWS.root.subviews.first === splitSurvivor
                checks["exitedBackgroundTabKeepsSelectedSession"] = tabExit.ended && tabs.workspaces.count == 1 && tabs.workspace === selectedTab && selectedTab.active.terminal.process.running && selectedTab.active.terminal.process.shellPid == tabPID
                checks["nonzeroExitClosesSession"] = failedPane.ended && !app.windows.contains(where: { $0 === failed })
                checks["immediateProcessExitClosesWindow"] = fastApp.windows.isEmpty
                checks["keepOpenRetainsOutputAndExitStatus"] = retainedPane.ended && retainedApp.windows.contains(where: { $0 === retained }) && retainedPane.title.hasPrefix("Exited ·") && retainedPane.terminal.getTerminal().exportPlainText().contains("KEEP_EXIT_OUTPUT")
                let exitTitle = retainedPane.title
                retainedPane.setTerminalTitle(source:retainedPane.terminal,title:"Late shell title")
                checks["exitedSessionTitleSurvivesLateShellUpdates"] = retainedPane.title == exitTitle
                cleanup()
            }
        }
    }

    static func wordNavigationPTYChecks(completion:@escaping ([String:Bool])->Void) {
        var config=Configuration();config.shell="/bin/zsh";config.advanced.loginShell=false
        config.advanced.environment["ZDOTDIR"]=Configuration.url.deletingLastPathComponent().path
        let pane=Pane(config:config,start:true),terminal=pane.terminal
        terminal.sendUserText("bindkey -e; printf '\\nMOTH_WORD_READY\\n'\r")
        waitFor({terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("MOTH_WORD_READY")}){ ready in
            guard ready else {pane.stop();completion(["optionArrowsNavigateRealZshWords":false]);return}
            terminal.sendUserText("printf '%s\\n' MOTH_WORD_tail")
            func arrow(_ characters:String,_ code:UInt16){
                let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.option,.function,.numericPad],timestamp:0,windowNumber:0,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code)!
                terminal.keyDown(with:event)
            }
            arrow("\u{f702}",123);terminal.sendUserText("nav-")
            arrow("\u{f703}",124);terminal.sendUserText("-ok\r")
            waitFor({terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("nav-MOTH_WORD_tail-ok")}){ passed in
                pane.stop();completion(["optionArrowsNavigateRealZshWords":passed])
            }
        }
    }

    static func macroPTYChecks(completion: @escaping ([String:Bool])->Void) {
        var checks: [String:Bool] = [:]
        let folder = Configuration.url.deletingLastPathComponent(), logs = folder.appendingPathComponent("output-logs")
        try! FileManager.default.createDirectory(at:logs,withIntermediateDirectories:true)
        var config = Configuration(); config.shell = "/bin/zsh"; config.advanced.loginShell = false; config.advanced.workingDirectory = folder.path; config.advanced.environment = ["MOTH_ADVANCED_TEST":"works","ZDOTDIR":folder.path]; config.advanced.logDirectory = logs.path
        let pane = Pane(config:config,start:true), terminal = pane.terminal, recorder = MacroRecorder.shared, player = MacroPlayer()
        terminal.send(txt:"printf 'MOTH_ENV=%s\\nMOTH_CWD=%s\\n' \"$MOTH_ADVANCED_TEST\" \"$PWD\"\r")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            let output = terminal.getTerminal().exportPlainText()
            let cwdLine = output.components(separatedBy:"\n").first { $0.hasPrefix("MOTH_CWD=") } ?? ""
            let actual = URL(fileURLWithPath:String(cwdLine.dropFirst("MOTH_CWD=".count))).standardizedFileURL.resolvingSymlinksInPath().path
            let expected = folder.standardizedFileURL.resolvingSymlinksInPath().path
            checks["advancedEnvironmentAndDirectoryReachPTY"] = output.contains("MOTH_ENV=works") && actual == expected
            if actual != expected { print("Directory comparison:",actual.debugDescription,expected.debugDescription) }
            if checks["advancedEnvironmentAndDirectoryReachPTY"] == false { print("Advanced PTY output:",output.debugDescription) }
            recorder.start(terminal)
            terminal.insertText("printf 'MOTH_RECORDED_PTY_OK\\n'",replacementRange:NSRange(location:NSNotFound,length:0))
            for (characters,code) in [("\u{f702}",UInt16(123)),("\u{f703}",UInt16(124)),("\r",UInt16(36))] {
                let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code)!
                terminal.keyDown(with:event)
            }
            let macro = recorder.finish()
            checks["recordedMacroIncludesArrowAndReturnKeys"] = macro.keys.joined().contains("\u{1b}[") && macro.keys.joined().contains("\r")
            waitFor({ terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("MOTH_RECORDED_PTY_OK") }) { originalRan in
            checks["recordedMacroOriginalExecutesBeforeReplay"] = originalRan
            player.play(macro,in:terminal)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.6) {
                let lines = terminal.getTerminal().exportPlainText().components(separatedBy:"\n")
                checks["recordedMacroReplaysInRealShell"] = lines.filter { $0 == "MOTH_RECORDED_PTY_OK" }.count >= 2
                if checks["recordedMacroReplaysInRealShell"] == false { print("Recorded PTY output:",lines,"keys:",macro.keys.map(\.debugDescription)) }
                var snippet = Configuration.Macro(); snippet.text = "printf 'MOTH_SNIPPET_PTY_OK\\n'"; snippet.submit = true
                player.play(snippet,in:terminal)
                var cancelled = Configuration.Macro(); cancelled.keys = ["printf 'MOTH_CANCELLED_PTY\\n'\r"]; cancelled.delays = [0.3]
                player.play(cancelled,in:terminal); player.stop()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                    let text = terminal.getTerminal().exportPlainText(), lines = text.components(separatedBy:"\n")
                    checks["snippetMacroExecutesWhenSubmitEnabled"] = lines.contains("MOTH_SNIPPET_PTY_OK")
                    checks["macroPlaybackCancellationStopsPendingKeys"] = !lines.contains("MOTH_CANCELLED_PTY")
                    let sessions = (try? FileManager.default.contentsOfDirectory(at:logs,includingPropertiesForKeys:nil)) ?? []
                    checks["advancedOutputLoggingCreatesPerPaneFiles"] = sessions.contains { ((try? FileManager.default.contentsOfDirectory(at:$0,includingPropertiesForKeys:nil)) ?? []).contains { ((try? Data(contentsOf:$0))?.count ?? 0) > 0 } }
                    pane.stop(); recorder.cancel(); player.stop(); wordNavigationPTYChecks { navigation in checks.merge(navigation){_,new in new}; completion(checks) }
                }
            }
            }
        }
    }

    static func alternateHistoryChecks(into checks: inout [String: Bool]) {
        let pane = Pane(config: Configuration(), start: false), view = pane.terminal
        view.feed(text: "\u{1b}[?1049h" + (0..<100).map { "ALT_HISTORY_\($0)\r\n" }.joined())
        let bottom = view.getTerminal().buffer.yDisp
        view.handleScrollWheel(deltaY: 3, precise: false, at: CGPoint(x: 50,y: 50))
        let position = view.getTerminal().buffer.yDisp
        checks["alternateHistoryEnabledByDefault"] = view.canScroll && position < bottom
        view.feed(text: "ADDITIONAL_OUTPUT\r\n")
        checks["outputDoesNotPullReaderOutOfHistory"] = view.getTerminal().buffer.yDisp == position
        view.scroll(toPosition: 1); let live = view.getTerminal().buffer.yDisp
        view.feed(text: "LIVE_OUTPUT\r\n")
        checks["scrollingToBottomResumesFollowingOutput"] = view.getTerminal().buffer.yDisp > live
        var config = Configuration(); config.alternateScreenScrollback = false; pane.apply(config)
        checks["alternateHistoryCanBeDisabledLive"] = !view.canScroll && view.getTerminal().buffer.yDisp == 0
    }

    static func appearanceFeatureChecks(app: App, into checks: inout [String: Bool]) {
        let saved = app.config
        var config = Configuration(); config.background.style = "solid"; config.cursor.animation = "noblink"
        config.background.paint.colors = ["FF0000", "0000FF"]; config.background.paint.type = "linear"; config.background.paint.angle = 0
        config.window.borderPaint = config.background.paint; config.cursor.paint = config.background.paint
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("gradient-probe.toml")
        do {
            try Configuration.save(config, to: path); let loaded = try Configuration.load(from: path)
            checks["gradientConfigRoundTrips"] = loaded.cursor.paint.colors == config.cursor.paint.colors && loaded.window.borderPaint.type == "linear" && loaded.background.paint.angle == 0
            let legacy = try Configuration.document(config).replacingOccurrences(of: "type = \"linear\"", with: "type = \"radial\"")
            try Data(legacy.utf8).write(to: path)
            let migrated = try Configuration.expandFile(at: path)
            let persisted = try String(contentsOf: path)
            checks["legacyRadialPaintMigratesWithoutLosingColours"] = [migrated.window.borderPaint, migrated.background.paint, migrated.cursor.paint].allSatisfy { $0.type == "linear" && $0.colors == config.background.paint.colors && $0.angle == 0 } && !persisted.contains("type = \"radial\"")

            try Data("[background]\nstyle = 'custom'\ncolors = ['112233', '445566']\n".utf8).write(to: path)
            let custom = try Configuration.expandFile(at: path)
            checks["legacyCustomEffectMigratesToBackgroundColours"] = custom.background.style == "flow" && custom.background.paint.type == "linear" && custom.background.paint.colors == ["112233", "445566"] && custom.background.effectColors == ["112233", "445566"]
            checks["legacyBackgroundPaletteRemovedFromSavedConfig"] = try TOMLDocument.parse(String(contentsOf: path))["background"]?["colors"] == nil && FileManager.default.fileExists(atPath: path.appendingPathExtension("before-background-palette").path)
            try Data("[background]\nstyle = 'fire'\nintensity = 0.6\nspeed = 1.2\n".utf8).write(to: path)
            let formerPreset = try Configuration.expandFile(at: path)
            checks["legacyPresetBecomesSingleBackground"] = formerPreset.background.style == "flow" && formerPreset.background.resolvedColors == Configuration.Background.legacyPalettes["fire"]! && formerPreset.background.intensity == 0.6 && formerPreset.background.speed == 1.2

        } catch { checks["gradientConfigRoundTrips"] = false; checks["legacyRadialPaintMigratesWithoutLosingColours"] = false; checks["legacyCustomEffectMigratesToBackgroundColours"] = false }
        let background = FlowBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)); background.apply(config); background.layoutSubtreeIfNeeded()
        func pixels(_ layer: CALayer) -> NSBitmapImageRep {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            layer.render(in: NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext); return bitmap
        }
        let linear = pixels(background.tint)
        checks["linearBackgroundPaintRenders"] = (linear.colorAt(x: 10, y: 50)?.redComponent ?? 0) > 0.8 && (linear.colorAt(x: 190, y: 50)?.blueComponent ?? 0) > 0.8
        checks["gradientBorderClipsToNativeCorners"] = background.borderPaintLayer.mask?.borderWidth == CGFloat(config.window.borderWidth) && background.borderPaintLayer.mask?.cornerRadius == background.layer?.cornerRadius
        let borderPixels = pixels(background.borderPaintLayer)
        let borderLeft = borderPixels.colorAt(x: 0, y: 50), borderRight = borderPixels.colorAt(x: 199, y: 50)
        checks["gradientBorderOnlyPaintsOutline"] = (borderPixels.colorAt(x: 100, y: 50)?.alphaComponent ?? 1) < 0.01 && (borderLeft?.redComponent ?? 0) > (borderLeft?.blueComponent ?? 1) && (borderRight?.blueComponent ?? 0) > (borderRight?.redComponent ?? 1)
        for mode in ["flow"] {
            var active = Configuration(); active.background.style = mode; active.background.intensity = 1
            active.background.effectColors = ["FF0000", "FF0000"]
            let animated = FlowBackgroundView(frame:NSRect(x:0,y:0,width:200,height:100))
            let host = NSWindow(contentRect:animated.frame,styleMask:[.borderless],backing:.buffered,defer:false); host.isReleasedWhenClosed = false; host.contentView = animated; host.orderFront(nil)
            animated.apply(active); animated.layoutSubtreeIfNeeded()
            let red = pixels(animated.backgroundSurface.layer!).colorAt(x: 100,y: 50)!.usingColorSpace(.sRGB)!
            active.background.effectColors = ["0000FF", "0000FF"]; animated.apply(active)
            let blue = pixels(animated.backgroundSurface.layer!).colorAt(x: 100,y: 50)!.usingColorSpace(.sRGB)!
            checks["\(mode)PaletteEditsChangeAnimatedField"] = red.redComponent-blue.redComponent > 0.18 && blue.blueComponent-red.blueComponent > 0.18
            host.orderOut(nil)
        }
        var layered = Configuration(); layered.background.style = "aurora"; layered.background.paint.colors = ["FF0000"]
        let field = FlowBackgroundView(frame: NSRect(x: 0,y: 0,width: 200,height: 100)); field.apply(layered)
        let first = pixels(field.layer!).colorAt(x: 100,y: 50)!.usingColorSpace(.sRGB)!
        layered.background.paint.colors = ["0000FF"]; field.apply(layered)
        let second = pixels(field.layer!).colorAt(x: 100,y: 50)!.usingColorSpace(.sRGB)!
        checks["plainPaintDoesNotTintAnimatedPreset"] = abs(first.redComponent-second.redComponent) < 0.01 && abs(first.blueComponent-second.blueComponent) < 0.01
        layered.background.effectColors = ["123456", "ABCDEF"]; layered.background.intensity = 0.65; layered.background.speed = 1.7
        do {
            try Configuration.save(layered, to: path); let loaded = try Configuration.load(from: path)
            checks["effectPaletteRoundTripsWithStrengthAndSpeed"] = loaded.background.effectColors == ["123456", "ABCDEF"] && loaded.background.intensity == 0.65 && loaded.background.speed == 1.7
        } catch { checks["effectPaletteRoundTripsWithStrengthAndSpeed"] = false }
        let pane = Pane(config: config, start: false)
        checks["gradientBackgroundLeavesTerminalTransparent"] = pane.terminal.nativeBackgroundColor.alphaComponent == (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0)
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 300,height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = pane; pane.layoutSubtreeIfNeeded()
        pane.terminal.caretViewTracksFocus = false; pane.terminal.feed(text: " \r")
        if let caret = pane.terminal.subviews.first(where: { String(describing: type(of: $0)) == "CaretView" }), let layer = caret.layer {
            let bitmap = makeBitmap(for: caret); let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; context.scaleBy(x: 2, y: 2)
            (caret as? CALayerDelegate)?.draw?(layer, in: context)
            let left = bitmap.colorAt(x: 1, y: bitmap.pixelsHigh/2), right = bitmap.colorAt(x: bitmap.pixelsWide-2, y: bitmap.pixelsHigh/2)
            checks["gradientCursorRenders"] = (left?.redComponent ?? 0) > 0.7 && (right?.blueComponent ?? 0) > 0.7
        } else { checks["gradientCursorRenders"] = false }
        window.close()
        var invalid = config; invalid.cursor.paint.type = "unknown"
        do { try invalid.validate(); checks["invalidPaintRejected"] = false } catch { checks["invalidPaintRejected"] = true }
        app.config.bell.mode = "visual"; app.config.bell.badge = true; app.active?.workspace.active.apply(app.config)
        let bellWorkspace = app.active?.workspace, originalBellHandler = bellWorkspace?.bell
        bellWorkspace?.bell = { [weak app] in app?.recordBell(appIsActive: false) }
        app.clearBellBadge(nil); bellWorkspace?.active.terminal.feed(text: "\u{7}\u{7}\u{7}")
        checks["bellBadgeCountsEvenRateLimitedBells"] = app.bellCount == 3 && NSApp.dockTile.badgeLabel == "3"
        bellWorkspace?.bell = originalBellHandler
        app.recordBell(appIsActive: true)
        checks["foregroundBellClearsAccumulatedBadge"] = app.bellCount == 0 && NSApp.dockTile.badgeLabel == nil
        for _ in 0..<3 { app.recordBell(appIsActive: true) }
        checks["foregroundBellsDoNotAccumulateBadge"] = app.bellCount == 0 && NSApp.dockTile.badgeLabel == nil
        app.recordBell(appIsActive: false)
        checks["backgroundBellsResumeBadgeCount"] = app.bellCount == 1 && NSApp.dockTile.badgeLabel == "1"
        app.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        checks["bellBadgeClearsWhenAppActivated"] = app.bellCount == 0 && NSApp.dockTile.badgeLabel == nil
        app.config.bell.badge = false; app.active?.workspace.active.apply(app.config); app.active?.workspace.active.terminal.feed(text: "\u{7}")
        checks["bellBadgeCanBeDisabled"] = app.bellCount == 0
        checks["runtimeAppIconIsLoaded"] = NSApp.applicationIconImage?.representations.contains(where: { $0.pixelsWide >= 128 }) == true
        app.config = saved; app.applyAppearance(); app.clearBellBadge(nil)
    }

    static func resetShortcutChecks(app: App, into checks: inout [String: Bool]) {
        let host = app.active!, terminal = host.workspace.active.terminal, pid = host.workspace.active.terminal.process.shellPid
        terminal.feed(text: "RESET_PROBE\u{1b}[?1049h\u{1b}[?1000h")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: host.window!.windowNumber, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
        host.window?.makeKeyAndOrderFront(nil)
        app.buildMenu()
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        checks["commandRResetsWithoutRestartingShell"] = handled && !terminal.getTerminal().isCurrentBufferAlternate && terminal.getTerminal().mouseMode == .off && terminal.process.shellPid == pid && terminal.process.running && terminal.getTerminal().find("RESET_PROBE").matches.isEmpty
        if checks["commandRResetsWithoutRestartingShell"] == false { print("Reset probe: pid=\(pid), handled=\(handled), alternate=\(terminal.getTerminal().isCurrentBufferAlternate), mouse=\(terminal.getTerminal().mouseMode), pidSame=\(terminal.process.shellPid == pid), running=\(terminal.process.running), remaining=\(terminal.getTerminal().find("RESET_PROBE").matches.count)") }

    }

    static func inverseVideoChecks(into checks: inout [String:Bool]) {
        for mode in ["solid","flow","opacity"] {
            var config = Configuration(); config.theme = "moth-dark"; config.background.style = mode == "flow" ? "flow" : "solid"
            if mode == "opacity" { config.window.opacity = 0.4 }
            let pane = Pane(config:config,start:false), terminal = pane.terminal
            terminal.setFrameSize(NSSize(width:420,height:180))
            terminal.feed(text:"\u{1b}[7m  %CPU  \u{1b}[27m   \r\n\u{1b}[38;2;220;40;60;7m  RED   \u{1b}[0m   \r\n\u{1b}[48;2;40;80;220;7m  BLUE  \u{1b}[0m   \r\n\u{1b}[38;2;40;200;100;48;2;130;40;170;7m  BOTH  \u{1b}[0m   \r\n    ")
            let bitmap = makeBitmap(for:terminal); draw(terminal,into:bitmap)
            let width = terminal.caretFrame.width, height = terminal.caretFrame.height
            func matches(_ color: NSColor?,_ expected: NSColor) -> Bool {
                guard let a = color?.usingColorSpace(.sRGB),let b = expected.usingColorSpace(.sRGB) else { return false }
                return a.alphaComponent > 0.99 && abs(a.redComponent-b.redComponent) < 0.025 && abs(a.greenComponent-b.greenComponent) < 0.025 && abs(a.blueComponent-b.blueComponent) < 0.025
            }
            let backgrounds = [config.colors.1,NSColor.hex("DC283C"),config.colors.1,NSColor.hex("28C864")]
            let foregrounds = [config.colors.0,config.colors.0,NSColor.hex("2850DC"),NSColor.hex("8228AA")]
            var padded = true, textVisible = true
            for row in 0..<4 {
                let y = Int((Double(row)+0.5)*height*2)
                for column in [0,1,7] { padded = padded && matches(bitmap.colorAt(x:Int((Double(column)+0.5)*width*2),y:y),backgrounds[row]) }
                var count = 0
                for y in Int(Double(row)*height*2)..<Int(Double(row+1)*height*2) {
                    for x in Int(2*width*2)..<Int(6*width*2) { if matches(bitmap.colorAt(x:x,y:y),foregrounds[row]) { count += 1 } }
                }
                textVisible = textVisible && count > 12
            }
            checks["inverseVideoFillsPadding_"+mode] = padded
            checks["inverseVideoSwapsDefaultAndExplicitTextColours_"+mode] = textVisible
            if mode != "solid" {
                let afterReset = bitmap.colorAt(x:Int(9.5*width*2),y:Int(height))
                checks["inverseResetRestoresTransparentCanvas_"+mode] = (afterReset?.alphaComponent ?? 1) < 0.01
            }
            if mode == "flow",let png = bitmap.representation(using:.png,properties:[:]) {
                let folder = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!).deletingLastPathComponent()
                try? png.write(to:folder.appendingPathComponent("InverseVideoPreview.png"))
            }
        }

        var config = Configuration()
        config.background.style = "flow"
        let pane = Pane(config: config, start: false)
        let terminal = pane.terminal
        terminal.setFrameSize(NSSize(width: 420, height: 180))
        let width = terminal.caretFrame.width
        let height = terminal.caretFrame.height
        let columns = terminal.getTerminal().cols
        let gridEdge = CGFloat(columns) * width
        terminal.feed(text: String(repeating: "x", count: columns - 6)
            + "\u{1b}[7m[Classified]\u{1b}[27m\r\n> ")
        let bitmap = makeBitmap(for: terminal)
        draw(terminal, into: bitmap)
        let rowCenter = Int(height)
        let lastCell = bitmap.colorAt(x: Int((gridEdge - width / 2) * 2), y: rowCenter)
        let gutter = bitmap.colorAt(x: Int((gridEdge + 2) * 2), y: rowCenter)
        checks["wrappedInverseVideoStopsAtGridEdge"] =
            (lastCell?.alphaComponent ?? 0) > 0.99 && (gutter?.alphaComponent ?? 1) < 0.01

        terminal.setFrameSize(NSSize(width: 420 + 12 * width, height: 180))
        let matches = terminal.getTerminal().find("[Classified]").matches
        checks["wrappedInverseVideoReflowsOntoOneRow"] =
            matches.count == 1 && matches[0].startRow == matches[0].endRow
    }

    static func typographyChecks(app: App,into checks: inout [String:Bool]) {
        let saved = app.config, host = app.active!, pane = app.active!.workspace.active!
        let pid = pane.terminal.process.shellPid
        defer { app.config = saved; app.applyAppearance() }
        var config = Configuration(); config.fontName = "JetBrainsMonoNFM-Regular"
        app.config = config; app.applyAppearance(); host.content.layoutSubtreeIfNeeded()
        let natural = pane.terminal.caretFrame.size, rows = pane.terminal.getTerminal().rows, cols = pane.terminal.getTerminal().cols
        pane.terminal.feed(text:"\u{1b}[?1000h")
        config.typography.lineHeight = 1.5; config.typography.characterSpacing = 1.25
        config.typography.ligatures = true; config.typography.antialias = false; config.typography.features = ["zero":1,"ss01":1]
        app.config = config; app.applyAppearance(); host.content.layoutSubtreeIfNeeded()
        let expanded = pane.terminal.caretFrame.size
        checks["typographyResizesGridAndCursor"] = expanded.height >= natural.height*1.45 && abs(expanded.width-natural.width-1.25) < 0.01 && pane.terminal.getTerminal().rows < rows && pane.terminal.getTerminal().cols < cols
        checks["liveTypographyKeepsShellAndTerminalModes"] = pane.terminal.process.shellPid == pid && pane.terminal.process.running && pane.terminal.getTerminal().mouseMode != .off
        pane.terminal.feed(text:"\u{1b}[?1000l")
        func glyphs(_ text: String,_ config: Configuration) -> [CGGlyph] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[.font:FontTypography.font(config),.ligature:config.typography.ligatures ? 1 : 0]))
            return (CTLineGetGlyphRuns(line) as! [CTRun]).flatMap { run in
                var values = [CGGlyph](repeating:0,count:CTRunGetGlyphCount(run)); CTRunGetGlyphs(run,CFRange(),&values); return values
            }
        }
        var plain = config; plain.typography = Configuration.Typography()
        checks["programmingLigaturesChangeActualShaping"] = glyphs("-> != ===",plain) != glyphs("-> != ===",config)
        var zeroOff = config; zeroOff.typography.features["zero"] = 0
        checks["openTypeZeroChangesActualGlyph"] = glyphs("0",zeroOff) != glyphs("0",config)
        checks["openTypeFeaturesDiscoveredFromFont"] = FontTypography.supportedTags(NSFont(name:config.fontName,size:14)!).contains("calt")
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("typography-fixture.toml")
        do { try Configuration.save(config,to:path); checks["typographyTOMLRoundTrip"] = try Configuration.load(from:path).typography == config.typography } catch { checks["typographyTOMLRoundTrip"] = false }
        for (name,value) in [("lineHeight",0.2),("characterSpacing",-1.0)] {
            var invalid = config
            if name == "lineHeight" { invalid.typography.lineHeight = value } else { invalid.typography.characterSpacing = value }
            do { try invalid.validate(); checks["invalidTypographyRejected_"+name] = false } catch { checks["invalidTypographyRejected_"+name] = true }
        }
        var invalid = config; invalid.typography.features = ["not-a-tag":1]
        do { try invalid.validate(); checks["invalidOpenTypeTagRejected"] = false } catch { checks["invalidOpenTypeTagRejected"] = true }
        do {
            for (name,text) in [("table","[typography.features]\nzero = 1 # keep this note\nss01 = 1\n"),("inline","[typography]\nfeatures = { zero = 1, ss01 = 1 }\n")] {
                try Data(text.utf8).write(to:path)
                var reset = config; reset.typography = Configuration.Typography(); try Configuration.save(reset,to:path)
                checks["resetTypographyRemovesOverrides_"+name] = try Configuration.load(from:path).typography.features.isEmpty
            }
        } catch { print("Reset typography:",error); checks["resetTypographyRemovesOverrides_table"] = false }
        let rendered = Pane(config:plain,start:false); rendered.terminal.setFrameSize(NSSize(width:500,height:120))
        rendered.terminal.feed(text:"-> != === 0O 1lI")
        let before = makeBitmap(for:rendered.terminal); draw(rendered.terminal,into:before)
        var shaped = plain; shaped.typography.ligatures = true; shaped.typography.features["zero"] = 1
        rendered.apply(shaped)
        let after = makeBitmap(for:rendered.terminal); draw(rendered.terminal,into:after)
        checks["typographyChangesNativeRenderedPixels"] = Data(bytes:before.bitmapData!,count:before.bytesPerRow*before.pixelsHigh) != Data(bytes:after.bitmapData!,count:after.bytesPerRow*after.pixelsHigh)
        checks["ligaturesKeepOriginalTextAndCursorColumns"] = rendered.terminal.getTerminal().getLine(row:0)?.translateToString(trimRight:true) == "-> != === 0O 1lI" && rendered.terminal.getTerminal().buffer.x == 16
        func edgeCount(_ antialias: Bool) -> Int {
            var c = plain; c.typography.antialias = antialias; rendered.apply(c)
            rendered.terminal.nativeBackgroundColor = .clear; rendered.terminal.nativeForegroundColor = .white
            let bitmap = makeBitmap(for:rendered.terminal); draw(rendered.terminal,into:bitmap)
            let bytes = bitmap.bitmapData!
            return stride(from:3,to:bitmap.bytesPerRow*bitmap.pixelsHigh,by:4).reduce(0) { $0+((bytes[$1] > 0 && bytes[$1] < 255) ? 1 : 0) }
        }
        let smoothEdges = edgeCount(true), hardEdges = edgeCount(false)
        checks["antialiasToggleChangesRenderedGlyphEdges"] = smoothEdges > 20 && hardEdges == 0
        if checks["antialiasToggleChangesRenderedGlyphEdges"] != true { print("Antialias edges:",smoothEdges,hardEdges) }

    }

    static func preferenceResetChecks(into checks: inout [String:Bool]) {
        let folder = Configuration.url.deletingLastPathComponent().appendingPathComponent("reset-fixture")
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:folder) }
            let path = folder.appendingPathComponent("config.toml")
            var custom = Configuration(); custom.fontSize = 23; custom.window.opacity = 0.3
            try Configuration.save(custom,to:path)
            let original = try Data(contentsOf:path)
            let (_,backup) = try Configuration.resetPreferences(at:path)
            let restored = try Configuration.load(from:path)
            checks["resetPreferencesBacksUpExactConfig"] = try backup.map { try Data(contentsOf:$0) == original } ?? false
            checks["resetPreferencesRestoresFactoryDefaults"] = try Configuration.document(restored) == Configuration.document(Configuration())
            let malformed = Data("not valid [ toml".utf8); try malformed.write(to:path)
            let (_,recovery) = try Configuration.resetPreferences(at:path)
            checks["resetCanRecoverMalformedConfig"] = try recovery.map { try Data(contentsOf:$0) == malformed } == true && Configuration.load(from:path).fontSize == Configuration().fontSize
        } catch { print("Reset preferences checks:",error); checks["resetPreferencesRestoresFactoryDefaults"] = false }
    }

    static func keyboardInputChecks(into checks: inout [String:Bool]) {
        let defaults = Configuration(), pane = Pane(config:Configuration(),start:false)
        let terminal = pane.terminal, recorder = MacroRecorder.shared
        func input(_ characters:String, raw:String, meta:Bool, code:UInt16 = 20, flags:NSEvent.ModifierFlags = .option) -> String {
            terminal.optionAsMetaKey = meta
            recorder.start(terminal)
            let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:characters,charactersIgnoringModifiers:raw,isARepeat:false,keyCode:code)!
            terminal.keyDown(with:event)
            return recorder.finish().keys.joined()
        }
        func held(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], expected: String) -> Bool {
            terminal.optionAsMetaKey = false;recorder.start(terminal)
            for index in 0..<12 {
                let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:Double(index)/30,windowNumber:0,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:index > 0,keyCode:code)!
                terminal.keyDown(with:event)
            }
            return recorder.finish().keys.joined() == String(repeating:expected,count:12)
        }
        checks["terminalDefaultsToKeyRepeat"] = !UserDefaults.standard.bool(forKey:"ApplePressAndHoldEnabled")
        checks["heldLetterDeliversEveryRepeat"] = held("a",code:0,expected:"a")
        checks["heldShiftLetterDeliversEveryRepeat"] = held("A",code:0,flags:.shift,expected:"A")
        checks["heldSpaceDeliversEveryRepeat"] = held(" ",code:49,expected:" ")
        checks["heldBackspaceDeliversEveryRepeat"] = held("\u{7f}",code:51,expected:"\u{7f}")
        checks["heldArrowDeliversEveryRepeat"] = held("\u{f703}",code:124,flags:[.function,.numericPad],expected:"\u{1b}[C")
        checks["heldControlKeyDeliversEveryRepeat"] = held("d",code:2,flags:.control,expected:"\u{4}")
        checks["nativeOptionTypingIsDefault"] = !defaults.optionAsMeta && !pane.terminal.optionAsMetaKey
        checks["britishOptionThreeSendsHash"] = input("#",raw:"3",meta:false) == "#"
        checks["nativeOptionTypingPreservesLayoutCharacters"] = input("€",raw:"2",meta:false) == "€"
        checks["nativeOptionSymbolsUseMacOSInput"] = [("π","p",UInt16(35)),("®","r",UInt16(15)),("©","g",UInt16(5)),("ø","o",UInt16(31))].allSatisfy { input($0.0,raw:$0.1,meta:false,code:$0.2) == $0.0 }
        checks["ordinaryArrowsRetainCursorMovement"] = input("\u{f702}",raw:"\u{f702}",meta:false,code:123,flags:[.function,.numericPad]) == "\u{1b}[D" && input("\u{f703}",raw:"\u{f703}",meta:false,code:124,flags:[.function,.numericPad]) == "\u{1b}[C"
        recorder.start(terminal)
        terminal.setMarkedText("´",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        terminal.insertText("é",replacementRange:NSRange(location:NSNotFound,length:0));terminal.unmarkText()
        checks["composedTextSendsOnlyCommittedCharacter"] = recorder.finish().keys.joined() == "é"

        checks["explicitOptionMetaStillSendsEscape"] = input("#",raw:"3",meta:true) == "\u{1b}3"
        for meta in [false,true] {
            checks["optionLeftMovesByWord_meta_\(meta)"] = input("\u{f702}",raw:"\u{f702}",meta:meta,code:123) == "\u{1b}b"
            checks["optionRightMovesByWord_meta_\(meta)"] = input("\u{f703}",raw:"\u{f703}",meta:meta,code:124) == "\u{1b}f"
        }
        pane.stop()
    }

    static func keyboardSoundChecks(app: App, into checks: inout [String:Bool]) {
        var config = Configuration()
        checks["keyboardSoundsQuietAndOffByDefault"] = !config.keyboardSound.enabled && config.keyboardSound.volume == 0.12
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("typing-sounds.toml")
        config.keyboardSound.musical = true
        config.keyboardSound.enabled = true; config.keyboardSound.style = "notes"; config.keyboardSound.key = "F#"; config.keyboardSound.mode = "locrian"; config.keyboardSound.volume = 0.08; config.keyboardSound.pattern = "descending"; config.keyboardSound.reverb = 0.42
        do { try Configuration.save(config,to:path); let loaded = try Configuration.load(from:path); checks["keyboardSoundSettingsRoundTrip"] = loaded.keyboardSound.enabled && loaded.keyboardSound.style == "notes" && loaded.keyboardSound.key == "F#" && loaded.keyboardSound.mode == "locrian" && loaded.keyboardSound.volume == 0.08 && loaded.keyboardSound.pattern == "descending" && loaded.keyboardSound.reverb == 0.42 && loaded.keyboardSound.musical } catch { checks["keyboardSoundSettingsRoundTrip"] = false }
        var bounded = true,distinct = Set<String>()
        for style in Configuration.keyboardSoundStyles {
            let samples = KeyboardSoundPlayer.samples(style:style,midi:64)
            bounded = bounded && samples.allSatisfy { $0.isFinite && abs($0) < 0.3 } && samples.first == 0 && abs(samples.last ?? 1) < 0.001 && samples.contains { abs($0) > 0.05 }
            distinct.insert(samples.prefix(200).map { String(format:"%.4f",$0) }.joined())
        }
        checks["builtInTypingSoundsAreDistinctAndFadeQuietly"] = bounded && distinct.count == Configuration.keyboardSoundStyles.count && distinct.count >= 8
        checks["musicalNotesFollowSelectedKeyAndMode"] = KeyboardSoundPlayer.midiNotes(config.keyboardSound) == [66,67,69,71,72,74,76]
        checks["allSevenMusicalModesAvailable"] = Configuration.musicalModes.count == 7 && Configuration.musicalModes.allSatisfy { $0.1.count == 7 && $0.1.first == 0 && Set($0.1).count == 7 }
        func event(_ text: String, flags: NSEvent.ModifierFlags = []) -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:app.active!.window!.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:0)! }
        checks["typingSoundIgnoresShortcutsAndNavigation"] = KeyboardSoundPlayer.shouldPlay(event("a")) && KeyboardSoundPlayer.shouldPlay(event("é",flags:.option)) && !KeyboardSoundPlayer.shouldPlay(event("v",flags:.command)) && !KeyboardSoundPlayer.shouldPlay(event("c",flags:.control)) && !KeyboardSoundPlayer.shouldPlay(event("\u{f700}"))
        let player = KeyboardSoundPlayer.shared
        var audio = config.keyboardSound; audio.volume = 0.001
        let scheduled = player.scheduledCount
        let pane = Pane(config:config,start:false); pane.terminal.keyboardSound = audio
        pane.terminal.keyDown(with:event("a"))
        checks["terminalTypingSchedulesNativeAudio"] = player.scheduledCount == scheduled+1
        player.stop()
        pane.terminal.readOnly = true; pane.terminal.keyDown(with:event("a"))
        checks["terminalPreviewsStaySilent"] = player.scheduledCount == scheduled+1
        audio.enabled = false
        checks["disabledTypingSoundsNeverScheduleAudio"] = !player.play(audio) && player.scheduledCount == scheduled+1
        let saved = app.config
        app.config.keyboardSound.enabled = false; app.buildMenu()
        let toggle = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.option],timestamp:0,windowNumber:app.active!.window!.windowNumber,context:nil,characters:"k",charactersIgnoringModifiers:"k",isARepeat:false,keyCode:40)!
        let handled = NSApp.mainMenu?.performKeyEquivalent(with:toggle) == true
        checks["keyboardSoundsToggleWithCommandOptionK"] = handled && app.config.keyboardSound.enabled && (try? Configuration.load().keyboardSound.enabled) == true
        app.toggleKeyboardSounds(nil)
        checks["keyboardSoundsToggleOffAndSave"] = !app.config.keyboardSound.enabled && (try? Configuration.load().keyboardSound.enabled) == false
        app.config = saved; app.persistAppearance(); player.stop()
        var phrase = config.keyboardSound
        phrase.pattern = "ascending"
        var ascending = KeyboardNoteSequence()
        checks["ascendingPatternWalksScaleAndWraps"] = (0..<8).map { _ in ascending.next(phrase) } == [66,67,69,71,72,74,76,66]
        phrase.pattern = "descending"; var descending = KeyboardNoteSequence()
        checks["descendingPatternWalksScaleAndWraps"] = (0..<9).map { _ in descending.next(phrase) } == [78,76,74,72,71,69,67,66,78]
        var descendingPhrase = phrase; descendingPhrase.key = "C"; descendingPhrase.mode = "ionian"
        var ionianDescending = KeyboardNoteSequence()
        checks["descendingIonianRunsTonicToTonic"] = (0..<9).map { _ in ionianDescending.next(descendingPhrase) } == [72,71,69,67,65,64,62,60,72]
        descendingPhrase.mode = "locrian"
        checks["changingDescendingModeRestartsAtUpperTonic"] = ionianDescending.next(descendingPhrase) == 72
        var locrianDescending = KeyboardNoteSequence()
        checks["descendingLocrianRunsTonicToTonic"] = (0..<9).map { _ in locrianDescending.next(descendingPhrase) } == [72,70,68,66,65,63,61,60,72]
        var allDescending = true
        for key in Configuration.musicalKeys {
            for mode in Configuration.musicalModes {
                descendingPhrase.key = key; descendingPhrase.mode = mode.0
                var sequence = KeyboardNoteSequence()
                let root = 60+Configuration.musicalKeys.firstIndex(of:key)!
                let expected = [root+12]+mode.1.reversed().map { root+$0 }
                allDescending = (0..<64).allSatisfy { sequence.next(descendingPhrase) == expected[$0 % 8] } && allDescending
            }
        }
        checks["descendingAllKeysAndModesRepeatCompleteOctaves"] = allDescending
        phrase.pattern = "arpeggiating"; var arpeggio = KeyboardNoteSequence()
        checks["arpeggioUsesModalChordTonesAndReturns"] = (0..<7).map { _ in arpeggio.next(phrase) } == [66,69,72,76,72,69,66]
        phrase.pattern = "random"; var random = KeyboardNoteSequence()
        checks["randomPatternChoosesOnlyScaleNotes"] = (0..<7).map { i in random.next(phrase,randomIndex:{i}) } == [66,67,69,71,72,74,76]
        phrase.key = "C"; phrase.mode = "ionian"; phrase.pattern = "ascending"
        checks["changingScaleBeginsNewPhrase"] = ascending.next(phrase) == 60
        var allPitched = true
        for style in Configuration.keyboardSoundStyles {
            player.stop(); var sound = config.keyboardSound; sound.style = style; sound.pattern = "ascending"; sound.volume = 0.001
            allPitched = player.play(sound,preview:true) && player.lastMIDI == 66 && player.play(sound,preview:true) && player.lastMIDI == 67 && allPitched
        }
        checks["everySoundUsesTheChosenMusicalSequence"] = allPitched
        var wet = config.keyboardSound; wet.reverb = 0.77; player.update(wet)
        checks["reverbSliderControlsNativeEffectMix"] = abs(player.reverbMix-77) < 0.001 && player.routesThroughReverb
        wet.reverb = 0; player.update(wet)
        checks["reverbCanBeCompletelyDry"] = player.reverbMix == 0
        player.stop()
        do {
            var sound = Configuration.KeyboardSound(); sound.style = "bells"; sound.volume = 1; sound.reverb = 0.6
            let baselinePlayer = KeyboardSoundPlayer(), adjustedPlayer = KeyboardSoundPlayer()
            let baseline = try baselinePlayer.renderForValidation(sound,frames:44100)
            let adjusted = try adjustedPlayer.renderForValidation(sound,frames:44100,volumeChange:(11025,0.25))
            func rms(_ samples: [Float]) -> Double { sqrt(samples[18000..<35000].reduce(0) { $0+Double($1*$1) }/17000) }
            let ratio = rms(adjusted)/rms(baseline)
            checks["volumeChangesExistingVoiceAndReverbLoudness"] = ratio > 0.20 && ratio < 0.30
            if checks["volumeChangesExistingVoiceAndReverbLoudness"] != true { print("Live gain ratio:",ratio) }
        } catch { print("Offline gain check:",error); checks["volumeChangesExistingVoiceAndReverbLoudness"] = false }
        var natural = config.keyboardSound; natural.musical = false; natural.key = "B"; natural.mode = "locrian"; natural.pattern = "ascending"
        var naturalSequence = KeyboardNoteSequence()
        checks["musicalBehaviourIsOffByDefault"] = !Configuration().keyboardSound.musical
        checks["naturalSoundsIgnoreMusicalKeyAndPattern"] = (0..<8).map { _ in naturalSequence.next(natural) } == Array(repeating:60,count:8)
        natural.musical = true
        checks["enablingMusicStartsChosenPhrase"] = naturalSequence.next(natural) == 71
        let tink = KeyboardSoundPlayer.samples(style:"tink",midi:60)
        let head = Array(tink.prefix(2205)), crossings = zip(head,head.dropFirst()).filter { ($0.0 >= 0) != ($0.1 >= 0) }.count
        checks["tinkHasHighBrightPitch"] = Double(crossings)/(2*Double(head.count)/44100) > 1800
        func energy(_ samples: [Float],from:Double,to:Double) -> Double {
            let slice = samples.dropFirst(Int(from*44100)).prefix(max(1,Int((to-from)*44100)))
            return slice.reduce(0) { $0+Double($1*$1) }/Double(max(1,slice.count))
        }
        let wood = KeyboardSoundPlayer.samples(style:"wood",midi:60), bell = KeyboardSoundPlayer.samples(style:"bells",midi:60), glass = KeyboardSoundPlayer.samples(style:"glass",midi:60)
        checks["woodIsDryAndBellsRetainTheirRing"] = energy(wood,from:0.07,to:0.09) < energy(wood,from:0,to:0.02)*0.001 && energy(bell,from:0.35,to:0.45) > energy(bell,from:0.02,to:0.05)*0.005
        checks["glassHasLongerResonanceThanTink"] = glass.count > tink.count*2 && energy(glass,from:0.25,to:0.35) > 0.000001
        do {
            let folder = Configuration.url.deletingLastPathComponent()
            let format = AVAudioFormat(standardFormatWithSampleRate:44100,channels:1)!
            var paths: [String] = []
            for (index,hz) in [220.0,660.0].enumerated() {
                let path = folder.appendingPathComponent("custom-key-\(index).wav")
                let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:8820)!; buffer.frameLength = 8820
                for i in 0..<8820 { buffer.floatChannelData![0][i] = Float(sin(2*Double.pi*hz*Double(i)/44100)*0.1) }
                let file = try AVAudioFile(forWriting:path,settings:format.settings); try file.write(from:buffer)
                paths.append(path.path)
            }
            var custom = Configuration(); custom.keyboardSound.style = "custom"; custom.keyboardSound.files = paths; custom.keyboardSound.volume = 0.001
            try custom.validate(); try Configuration.save(custom,to:path)
            checks["customSoundFilesPersist"] = try Configuration.load(from:path).keyboardSound.files == paths
            player.stop()
            let first = player.play(custom.keyboardSound,preview:true) && player.lastCustomFile == paths[0] && player.lastFrameCount == 8820 && player.lastMIDI == 60
            let second = player.play(custom.keyboardSound,preview:true) && player.lastCustomFile == paths[1]
            checks["customAudioDecodesPlaysAndRotates"] = first && second
            player.stop(); custom.keyboardSound.musical = true; custom.keyboardSound.key = "F#"; custom.keyboardSound.mode = "locrian"; custom.keyboardSound.pattern = "ascending"
            checks["customAudioSupportsMusicalPitching"] = player.play(custom.keyboardSound,preview:true) && player.lastMIDI == 66 && player.lastFrameCount < 8820 && player.lastFrameCount > 6000
            player.stop()
            custom.keyboardSound.files = [folder.appendingPathComponent("missing.wav").path]
            do { try custom.validate(); checks["missingCustomSoundRejected"] = false } catch { checks["missingCustomSoundRejected"] = true }
            let bad = folder.appendingPathComponent("not-a-sound.txt"); try Data("not audio".utf8).write(to:bad); custom.keyboardSound.files = [bad.path]
            do { try custom.validate(); checks["invalidCustomAudioRejected"] = false } catch { checks["invalidCustomAudioRejected"] = true }
        } catch { print("Custom audio checks:",error); checks["customAudioDecodesPlaysAndRotates"] = false }
        var invalidPattern = config; invalidPattern.keyboardSound.pattern = "invalid"
        do { try invalidPattern.validate(); checks["invalidNotePatternRejected"] = false } catch { checks["invalidNotePatternRejected"] = true }
        var invalidReverb = config; invalidReverb.keyboardSound.reverb = 1.1
        do { try invalidReverb.validate(); checks["invalidReverbRejected"] = false } catch { checks["invalidReverbRejected"] = true }
        var invalid = config; invalid.keyboardSound.mode = "invalid"
        do { try invalid.validate(); checks["invalidMusicalModeRejected"] = false } catch { checks["invalidMusicalModeRejected"] = true }
    }

    static func developmentChecks(app: App,into checks: inout [String:Bool]) {
        checks["allThreeFontFamiliesBundledAndRegistered"] = Configuration.bundledFonts.allSatisfy { NSFont(name:$0.1,size:14) != nil } && Bundle.main.url(forResource:"WumpusMonoPro-Regular",withExtension:"ttf",subdirectory:"Fonts") != nil
        checks["wumpusIsDefaultFont"] = Configuration().fontName == "WumpusMonoPro-Regular"
        let notices = Bundle.main.url(forResource:"THIRD-PARTY-NOTICES",withExtension:nil).flatMap { try? String(contentsOf:$0) } ?? ""
        let fontPermission = Bundle.main.url(forResource:"FONT-PERMISSION",withExtension:nil).flatMap { try? String(contentsOf:$0) } ?? ""
        checks["fontEmbeddingLicenceAndIBMLicenceBundled"] = fontPermission.contains("worldwide, non-exclusive, royalty-free permission") && notices.contains("IBM Plex Mono 2.5.0") && notices.contains("SIL OPEN FONT LICENSE")
        var hash: UInt64 = 14695981039346656037
        for x in KeyboardSoundPlayer.samples(style:"tink",midi:60) { for shift in stride(from:0,to:32,by:8) { hash = (hash ^ UInt64((x.bitPattern >> shift)&255)) &* 1099511628211 } }
        checks["tinkWaveformRemainsUnchanged"] = hash == 0x16acb3c7afaaa9fc
        checks["otherSoundsHaveLongerHauntingTails"] = KeyboardSoundPlayer.samples(style:"glass",midi:60).count > 44100 && KeyboardSoundPlayer.samples(style:"bells",midi:60).count > 60000 && KeyboardSoundPlayer.samples(style:"notes",midi:60).count > 35000
        checks["systemThemeFirstAndDefault"] = Configuration.themeNames.prefix(3).elementsEqual(["system","moth-dark","moth-light"]) && Configuration().theme == "system"
        var system = Configuration(); system.theme = "system"
        checks["systemThemeResolvesBothMacAppearances"] = system.resolvedTheme(systemDark:true).name == "moth-dark" && system.resolvedTheme(systemDark:false).name == "moth-light"
        let lastSix = Configuration.themes.suffix(6)
        checks["sixNewThemesSplitLightAndDarkWithANSIColours"] = lastSix.count == 6 && lastSix.filter(\.light).count == 3 && lastSix.allSatisfy { $0.ansiColors.count == 16 && $0.ansiColors.allSatisfy(Configuration.validHex) }
        let priorAppearance = NSApp.appearance, priorConfig = app.config
        app.config.theme = "system"; app.config.palette = nil
        NSApp.appearance = NSAppearance(named:.darkAqua); app.applyAppearance()
        let dark = app.config.selectedTheme.name == "moth-dark" && app.windows.allSatisfy { $0.window?.appearance?.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua }
        NSApp.appearance = NSAppearance(named:.aqua); app.applyAppearance()
        checks["systemThemeUpdatesNativeWindowAppearance"] = dark && app.config.selectedTheme.name == "moth-light" && app.windows.allSatisfy { $0.window?.appearance?.bestMatch(from:[.aqua,.darkAqua]) == .aqua }
        NSApp.appearance = priorAppearance; app.config = priorConfig; app.applyAppearance()
        let folder = Configuration.url.deletingLastPathComponent(), migration = folder.appendingPathComponent("defaults-migration.toml")
        do {
            var old = Configuration(); old.fontName = "JetBrainsMonoNFM-Regular"; old.theme = "midnight"; try Configuration.save(old,to:migration)
            let first = try Configuration.expandFile(at:migration)
            checks["factoryFontAndThemeDefaultsMigrateOnce"] = first.fontName == "WumpusMonoPro-Regular" && first.theme == "system"
            try Configuration.save(old,to:migration); let chosen = try Configuration.expandFile(at:migration)
            checks["laterExplicitFontAndThemeChoicesArePreserved"] = chosen.fontName == old.fontName && chosen.theme == "midnight"
            var config = Configuration(); var macro = Configuration.Macro(); macro.keys = ["hello","\u{1b}[D","\r"]; macro.delays = [0,0.1,0.2]; macro.shortcut = "cmd+alt+1"; config.macros["Recorded Example"] = macro
            config.advanced.environment = ["MOTH_TEST_OVERRIDE":"yes","EQUALS":"a=b"]; config.advanced.workingDirectory = folder.path; config.advanced.loginShell = false
            let file = folder.appendingPathComponent("macros-advanced.toml"); try config.validate(); try Configuration.save(config,to:file); let loaded = try Configuration.load(from:file)
            checks["recordedKeysAndAdvancedSettingsRoundTripTOML"] = loaded.macros["Recorded Example"]?.keys == macro.keys && loaded.macros["Recorded Example"]?.delays == macro.delays && loaded.advanced.environment["EQUALS"] == "a=b" && !loaded.advanced.loginShell
            config.macros["Recorded Example"]?.shortcut = "cmd+p"
            do { try config.validate(); checks["macrosRejectReservedShortcuts"] = false } catch { checks["macrosRejectReservedShortcuts"] = true }
        } catch { print("Development persistence checks:",error); checks["recordedKeysAndAdvancedSettingsRoundTripTOML"] = false }
        let pane = Pane(config:Configuration(),start:false), recorder = MacroRecorder.shared
        recorder.start(pane.terminal); pane.terminal.feed(text:"\u{1b}[6n")
        checks["macroRecordingExcludesTerminalResponses"] = recorder.keys.isEmpty
        pane.terminal.insertText("typed",replacementRange:NSRange(location:NSNotFound,length:0)); let recorded = recorder.finish()
        checks["macroRecordingCapturesUserTyping"] = recorded.keys.joined() == "typed"
        pane.terminal.feed(text:"log 123\r\nlog ABC\r\n界 e\u{301} 👩‍💻\r\n")
        let terminal = pane.terminal.getTerminal()
        checks["regexSearchMatchesPatterns"] = terminal.find("log [0-9]+",regularExpression:true).matches.count == 1
        checks["regexInvalidPatternReportsError"] = terminal.find("[",regularExpression:true).error != nil
        checks["regexUnicodeMatchesMapToCells"] = terminal.find("界.*👩‍💻",regularExpression:true).matches.count == 1
        checks["scrollbackExportContainsPlainText"] = terminal.exportPlainText().contains("log 123") && !terminal.exportPlainText().contains("\u{1b}")
        var glass = Configuration(); glass.window.frosted = true; glass.window.opacity = 0.2
        let surface = FlowBackgroundView(frame:NSRect(x:0,y:0,width:200,height:120)); surface.apply(glass)
        checks["frostTintSurfaceIsAboveNativeMaterial"] = surface.subviews.firstIndex(of:surface.backgroundSurface)! > surface.subviews.firstIndex(of:surface.frost)! && surface.backdropIsOnTintSurface
        let low = surface.backgroundOpacity; glass.window.opacity = 0.8; surface.apply(glass)
        checks["frostingRespectsOpacityChanges"] = abs(low-0.2) < 0.001 && abs(surface.backgroundOpacity-0.8) < 0.001
        glass.window.borderWidth = 2; glass.window.borderPaint.colors = ["AA3344","5566DD"]; glass.window.borderPaint.type = "linear"; glass.window.showBorder = false; surface.apply(glass)
        let hidden = surface.borderPaintLayer.isHidden
        glass.window.showBorder = true; surface.apply(glass)
        checks["windowBorderToggleKeepsSavedPaintAndWidth"] = hidden && !surface.borderPaintLayer.isHidden && surface.borderPaintLayer.mask?.borderWidth == 2 && glass.window.borderPaint.colors == ["AA3344","5566DD"]

        func all(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0]+($0.submenu.map(all) ?? []) } }
        let menu = all(NSApp.mainMenu!)
        checks["nativeFileMenuHasExportsPrintAndPageSetup"] = [#selector(App.saveScrollback(_:)),#selector(App.saveSelectedText(_:)),#selector(App.printScrollback(_:)),#selector(App.pageSetup(_:))].allSatisfy { action in menu.contains { $0.action == action } }
        checks["secureKeyboardEntryToggleIsInMothMenu"] = NSApp.mainMenu?.items.first?.submenu?.items.contains { $0.action == #selector(App.toggleSecureKeyboardEntry(_:)) } == true
        let full = menu.first { $0.action == #selector(App.toggleNativeFullScreen(_:)) }
        checks["nativeFullscreenUsesCommandControlF"] = full?.keyEquivalent == "f" && full?.keyEquivalentModifierMask == [.command,.control]
        if checks["nativeFullscreenUsesCommandControlF"] == false { print("Full screen item:",full?.title as Any,full?.keyEquivalent as Any,full?.keyEquivalentModifierMask.rawValue as Any) }
        let fullKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.control],timestamp:0,windowNumber:0,context:nil,characters:"f",charactersIgnoringModifiers:"f",isARepeat:false,keyCode:3)!
        let findKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:"f",charactersIgnoringModifiers:"f",isARepeat:false,keyCode:3)!
        checks["fullscreenKeyboardHandlerPreservesFindShortcut"] = App.isFullscreenShortcut(fullKey) && !App.isFullscreenShortcut(findKey)
        let about = AboutWindowController(); about.window?.contentView?.layoutSubtreeIfNeeded()
        checks["wumpusHasLicensedFontCreditLink"] = about.projects.contains { $0.0.contains("Wumpus Mono Pro") && $0.1 == "https://vaughantype.com/wumpus-mono-pro" }
        checks["terminalCursorSymbolIsAvailable"] = AppearancePanel.terminalCursorIcon().isTemplate
        checks["aboutHeightFitsContent"] = abs((about.window?.contentView?.bounds.height ?? 0)-about.contentStack.fittingSize.height-AboutWindowController.verticalPadding*2) < 2
        if let root = about.window?.contentView,let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds) {
            root.cacheDisplay(in:root.bounds,to:bitmap)
            let folder = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!).deletingLastPathComponent()
            try? bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("AboutPreview.png"))
        }
    }

    static func bellChecks(into checks: inout [String: Bool]) {
        var config = Configuration(); config.bell.mode = "visual"; config.bell.color = "123456"
        let visual = Pane(config: config, start: false)
        visual.terminal.feed(text: "\u{7}")
        checks["BELTriggersVisualBell"] = visual.bellLayer.animation(forKey: "visualBell") != nil || visual.bellLayer.opacity == 1
        checks["visualBellUsesConfiguredColour"] = visual.bellLayer.borderColor == NSColor.hex("123456").cgColor
        checks["visualBellDoesNotPlaySound"] = visual.bellSound == nil
        config.bell.mode = "off"; visual.apply(config); visual.terminal.feed(text: "\u{7}")
        checks["bellCanBeDisabledLive"] = visual.bellLayer.animationKeys()?.isEmpty != false && visual.bellLayer.opacity == 0 && visual.bellSound == nil
        config.bell.mode = "sound"; config.bell.volume = 0
        let audio = Pane(config: config, start: false); audio.terminal.feed(text: "\u{7}")
        checks["bellUsesConfiguredSoundAndVolume"] = audio.bellSound != nil && audio.bellSound?.volume == 0 && audio.bellLayer.animation(forKey: "visualBell") == nil
        audio.bellSound?.stop()
        config.bell.mode = "both"
        let both = Pane(config: config, start: false); both.terminal.feed(text: "\u{7}")
        checks["bellCanCombineSoundAndVisual"] = both.bellSound != nil && (both.bellLayer.animation(forKey: "visualBell") != nil || both.bellLayer.opacity == 1)
        both.bellSound?.stop()
        var flashConfig = Configuration(); flashConfig.bell.mode = "visual"; flashConfig.bell.style = "flash"; flashConfig.bell.intensity = 0.5
        let flash = Pane(config: flashConfig, start: false); flash.terminal.feed(text: "\u{7}")
        let peak = (flash.bellLayer.animation(forKey: "visualBell") as? CABasicAnimation)?.fromValue as? Float ?? flash.bellLayer.opacity
        checks["visualBellCanUseSoftPaneFlash"] = flash.bellLayer.borderWidth == 0 && flash.bellLayer.backgroundColor != nil && abs(peak-0.09) < 0.001
        var windowConfig = Configuration(); windowConfig.bell.mode = "visual"; windowConfig.bell.style = "window-border"; windowConfig.bell.thickness = 5
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 500,height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = FlowBackgroundView(frame: .zero); window.contentView = root; root.apply(windowConfig)
        let windowPane = Pane(config: windowConfig, start: false); windowPane.frame = root.bounds; root.addSubview(windowPane)
        windowPane.terminal.feed(text: "\u{7}")
        checks["visualBellCanPulseWholeWindowBorder"] = (root.windowBellLayer.animation(forKey: "visualBell") != nil || root.windowBellLayer.opacity > 0) && windowPane.bellLayer.animation(forKey: "visualBell") == nil && root.windowBellLayer.borderWidth == 5
        windowConfig.bell.style = "border"; windowPane.apply(windowConfig)
        checks["visualBellStyleChangesClearOldEffect"] = root.windowBellLayer.animation(forKey: "visualBell") == nil && root.windowBellLayer.opacity == 0
        window.close()
        var invalidStyle = Configuration(); invalidStyle.bell.style = "unknown"
        do { try invalidStyle.validate(); checks["invalidVisualBellStyleRejected"] = false } catch { checks["invalidVisualBellStyleRejected"] = true }
        config.bell.style = "flash"; config.bell.intensity = 0.3; config.bell.thickness = 4
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("bell-config.toml")
        do { try Configuration.save(config, to: path); let loaded = try Configuration.load(from: path); checks["bellConfigRoundTrips"] = loaded.bell.mode == "both" && loaded.bell.color == "123456" && loaded.bell.volume == 0 && loaded.bell.style == "flash" && loaded.bell.intensity == 0.3 && loaded.bell.thickness == 4 } catch { checks["bellConfigRoundTrips"] = false }
        config.bell.mode = "invalid"
        do { try config.validate(); checks["invalidBellModeRejected"] = false } catch { checks["invalidBellModeRejected"] = true }
    }

    static func runPlainMoshChecks(completion: @escaping ([String: Bool]) -> Void) {
        let executable = "/opt/homebrew/bin/mosh-server", client = "/opt/homebrew/bin/mosh-client"
        guard FileManager.default.isExecutableFile(atPath: executable), FileManager.default.isExecutableFile(atPath: client) else { completion([:]); return }
        let folder = Configuration.url.deletingLastPathComponent(), script = folder.appendingPathComponent("plain-mosh.sh")
        let fixture = "printf 'MOTH_MOSH_READY\\n'; read marker; i=0; while [ $i -lt 110 ]; do printf 'MOTH_MOSH_%03d\\n' $i; i=$((i+1)); sleep 0.03; done; printf 'MOTH_MOSH_END\\n'; exec /bin/sh\n"
        try! Data(fixture.utf8).write(to: script)
        var environment = ShellEnvironment.session(); environment["LANG"] = "en_US.UTF-8"; environment["LC_ALL"] = "en_US.UTF-8"; environment["MOSH_SERVER_NETWORK_TMOUT"] = "10"
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: executable)
        server.arguments = ["new","-i","127.0.0.1","-p","0","-c","256","--","/bin/sh",script.path]
        server.environment = environment; server.standardOutput = output; server.standardError = output
        let handshake: String
        do { try server.run(); handshake = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); server.waitUntilExit() }
        catch { completion(["plainMoshLoopbackStarts": false]); return }
        // The ephemeral session key stays in memory and is never written to logs/results.
        guard let line = handshake.components(separatedBy: "\n").first(where: { $0.hasPrefix("MOSH CONNECT ") }) else { completion(["plainMoshLoopbackStarts": false]); return }
        let fields = line.split(separator: " ")
        guard fields.count == 4 else { completion(["plainMoshLoopbackStarts": false]); return }
        var serverPID: Int32?
        if let range = handshake.range(of: #"pid = [0-9]+"#, options: .regularExpression) { serverPID = Int32(handshake[range].split(separator: " ").last ?? "") }
        environment["MOSH_KEY"] = String(fields[3])
        let pane = Pane(config: Configuration(), start: false), view = pane.terminal
        view.startProcess(executable: client, args: ["127.0.0.1",String(fields[2])], environment: environment.map { "\($0.key)=\($0.value)" })
        var results: [String: Bool] = [:], bottom = 0, up = 0
        let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.8) {
            results["plainMoshLoopbackStarts"] = view.getTerminal().find("MOTH_MOSH_READY").matches.count > 0
            view.send(txt: "start\r")
        }
        func finish() {
            if let serverPID, ProcessInspector.assess(shellPID: serverPID).programs.contains(where: { $0.pid == serverPID && $0.name == "mosh-server" }) { kill(serverPID, SIGTERM) }
            pane.stop(); completion(results)
        }
        func checkOutput(_ attempts: Int) {
            let terminal = view.getTerminal()
            guard !terminal.find("MOTH_MOSH_END").matches.isEmpty || attempts == 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { checkOutput(attempts-1) }; return
            }
            bottom = terminal.buffer.yDisp
            results["plainMoshHasLocalHistory"] = terminal.isCurrentBufferAlternate && view.canScroll && bottom > 0 && !terminal.find("MOTH_MOSH_END").matches.isEmpty
            view.handleScrollWheel(deltaY: 6, precise: false, at: point)
            up = terminal.buffer.yDisp
            results["plainMoshWheelScrollsUp"] = up < bottom
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
                view.handleScrollWheel(deltaY: -3, precise: false, at: point)
                results["plainMoshWheelScrollsDown"] = view.getTerminal().buffer.yDisp > up
                view.handleScrollWheel(deltaY: 120, precise: true, at: point, phase: .began)
                results["plainMoshTrackpadScrolls"] = view.getTerminal().buffer.yDisp < bottom
                view.scroll(toPosition: 0)
                results["plainMoshScrollThumbWorks"] = view.getTerminal().buffer.yDisp == 0 && view.scrollThumbsize > 0 && view.scrollThumbsize < 1
                view.scroll(toPosition: 1); view.send(txt: "exit\r")
                DispatchQueue.main.asyncAfter(deadline: .now()+0.6) { finish() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { checkOutput(100) }
    }

    static func wheelChecks(into checks: inout [String: Bool]) {
        let view = DropCaptureView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        let point = CGPoint(x: 40, y: 100)
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
        view.handleScrollWheel(deltaY: 1, precise: false, at: point)
        let up = String(bytes: view.sent, encoding: .utf8) ?? ""
        checks["wheelUpUsesSGRMouseProtocol"] = up.hasPrefix("\u{1b}[<64;") && up.hasSuffix("M") && up.filter { $0 == "M" }.count == 1
        view.sent.removeAll(); view.handleScrollWheel(deltaY: -2, precise: false, at: point)
        let down = String(bytes: view.sent, encoding: .utf8) ?? ""
        checks["wheelDownHasNoReleaseEvents"] = down.components(separatedBy: "\u{1b}[<65;").count == 3 && !down.contains("m")
        view.sent.removeAll()
        view.handleScrollWheel(deltaY: 0.1, precise: true, at: point, phase: .began)
        checks["trackpadSubLineMotionAccumulates"] = view.sent.isEmpty
        for _ in 0..<499 { view.handleScrollWheel(deltaY: 0.1, precise: true, at: point) }
        let reports = (String(bytes: view.sent, encoding: .utf8) ?? "").components(separatedBy: "\u{1b}[<64;").count-1
        checks["trackpadSubLineMotionAccumulates"] = checks["trackpadSubLineMotionAccumulates"] == true && reports > 0 && reports < 20
        view.sent.removeAll(); view.handleScrollWheel(deltaY: 10000, precise: false, at: point)
        checks["wheelReportingIsBounded"] = view.sent.filter { $0 == 77 }.count == 40
        view.sent.removeAll(); view.handleScrollWheel(deltaY: 1, precise: false, at: point, modifiers: [.option,.control])
        checks["wheelPreservesModifiers"] = String(bytes: view.sent, encoding: .utf8)?.hasPrefix("\u{1b}[<88;") == true
        let history = DropCaptureView(frame: view.frame)
        history.feed(text: (0..<100).map { "line \($0)\r\n" }.joined())
        let bottom = history.getTerminal().buffer.yDisp
        history.handleScrollWheel(deltaY: 2, precise: false, at: point)
        checks["ordinaryScrollbackStillWorks"] = history.getTerminal().buffer.yDisp == bottom-2 && history.sent.isEmpty
        history.feed(text: "\u{1b}[?1000h\u{1b}[?1006h"); let beforeShift = history.getTerminal().buffer.yDisp
        history.handleScrollWheel(deltaY: 1, precise: false, at: point, modifiers: .shift)
        checks["shiftWheelBypassesMouseReporting"] = history.sent.isEmpty && history.getTerminal().buffer.yDisp == beforeShift-1
        let alternate = DropCaptureView(frame: view.frame)
        alternate.feed(text: "\u{1b}[?1049h")
        alternate.handleScrollWheel(deltaY: 1, precise: false, at: point)
        checks["alternateScreenDoesNotInjectUnrequestedKeys"] = alternate.sent.isEmpty
        alternate.feed(text: "\u{1b}[?1007h")
        alternate.handleScrollWheel(deltaY: 1, precise: false, at: point)
        checks["alternateScrollModeSendsCursorKeys"] = alternate.sent == [27,91,65]
        alternate.sent.removeAll(); alternate.feed(text: "\u{1b}[?1h")
        alternate.handleScrollWheel(deltaY: -1, precise: false, at: point)
        checks["alternateScrollRespectsApplicationCursorMode"] = alternate.sent == [27,79,66]
        alternate.sent.removeAll(); alternate.feed(text: "\u{1b}[?1007l")
        alternate.handleScrollWheel(deltaY: 1, precise: false, at: point)
        checks["alternateScrollCanBeDisabled"] = alternate.sent.isEmpty && !alternate.getTerminal().alternateScrollMode
        let wide = DropCaptureView(frame: NSRect(x: 0,y: 0,width: 5000,height: 200))
        wide.feed(text: "\u{1b}[?1000h")
        wide.handleScrollWheel(deltaY: 1, precise: false, at: CGPoint(x: 4900,y: 100))
        checks["legacyMouseClampsWideCoordinates"] = wide.sent.count == 6 && wide.sent[4] == 255
    }

    final class TmuxScrollChecks {
        var results: [String: Bool] = [:]
        let pane = Pane(config: Configuration(), start: false)
        let socket = "moth-scroll-\(getpid())"
        let executable = "/opt/homebrew/bin/tmux"
        @discardableResult func command(_ arguments: [String]) -> String {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = ["-L",socket]+arguments
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do { try process.run(); let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } catch { return "" }
        }
        func position(_ target: String) -> Int { Int(command(["display-message","-p","-t",target,"#{scroll_position}"])) ?? 0 }
        func stop() { command(["kill-server"]); pane.stop() }
    }
    static func startTmuxScrollCheck() -> TmuxScrollChecks? {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/tmux") else { return nil }
        let probe = TmuxScrollChecks(), folder = Configuration.url.deletingLastPathComponent()
        let conf = folder.appendingPathComponent("tmux-test.conf"), script = folder.appendingPathComponent("tmux-output.sh")
        try! Data("set -g mouse on\nset -g status off\nset -g history-limit 2000\nset -s escape-time 0\n".utf8).write(to: conf)
        try! Data("i=0; while [ $i -lt 200 ]; do printf 'MOTH_SCROLL_%03d\\n' $i; i=$((i+1)); done; echo MOTH_SCROLL_END; exec /bin/sh\n".utf8).write(to: script)
        var environment = ShellEnvironment.session(); environment.removeValue(forKey: "TMUX")
        let command = "/bin/sh " + ShellView.quotePath(script.path)
        probe.pane.terminal.startProcess(executable: probe.executable, args: ["-L",probe.socket,"-f",conf.path,"new-session","-s","wheel",command], environment: environment.map { "\($0.key)=\($0.value)" })
        var first = 0, afterDown = 0
        let point = CGPoint(x: probe.pane.terminal.bounds.width*0.2, y: probe.pane.terminal.bounds.height*0.5)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.6) {
            probe.results["tmuxEnablesMouseReporting"] = probe.pane.terminal.getTerminal().mouseMode != .off
            probe.command(["split-window","-h","-t","wheel:0",command])
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.0) {
            probe.pane.terminal.handleScrollWheel(deltaY: 6, precise: false, at: point)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.6) {
            first = probe.position("wheel:0.0")
            probe.results["tmuxWheelEntersCopyMode"] = probe.command(["display-message","-p","-t","wheel:0.0","#{pane_in_mode}"]) == "1" && first > 0
            probe.results["tmuxWheelTargetsPaneUnderPointer"] = first > 0 && probe.position("wheel:0.1") == 0
            probe.pane.terminal.handleScrollWheel(deltaY: -1, precise: false, at: point)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+2.2) {
            afterDown = probe.position("wheel:0.0")
            probe.results["tmuxWheelScrollsDown"] = afterDown < first
            probe.pane.terminal.handleScrollWheel(deltaY: 140, precise: true, at: point, phase: .began)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+2.9) {
            probe.results["tmuxTrackpadScrollsHistory"] = probe.position("wheel:0.0") > afterDown
        }
        return probe
    }

    static func themeCatalogueChecks(app: App, into checks: inout [String: Bool]) {
        func luminance(_ color: NSColor) -> Double {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ x: CGFloat) -> Double { let x = Double(x); return x <= 0.04045 ? x/12.92 : pow((x+0.055)/1.055, 2.4) }
            return 0.2126*linear(rgb.redComponent)+0.7152*linear(rgb.greenComponent)+0.0722*linear(rgb.blueComponent)
        }
        var roundTrips = true, readable = true
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("theme-catalogue.toml")
        for name in Configuration.themeNames {
            var config = Configuration(); config.theme = name
            do { try config.validate(); try Configuration.save(config, to: path); let loaded = try Configuration.load(from: path); roundTrips = roundTrips && loaded.theme == name } catch { roundTrips = false }
            let (bg,fg,_) = config.colors, low = min(luminance(bg),luminance(fg)), high = max(luminance(bg),luminance(fg))
            readable = readable && (high+0.05)/(low+0.05) >= 4.5
        }
        checks["allThemesLoadFromTOML"] = roundTrips
        checks["themeTextContrast"] = readable
        app.buildMenu()
        let view = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu
        func menuItems(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0]+($0.submenu.map(menuItems) ?? []) } }
        let allItems = menuItems(NSApp.mainMenu!)
        let commaItems = allItems.filter { $0.keyEquivalent == "," }
        checks["commandCommaOpensSettingsNotConfigEditor"] = commaItems.count == 1 && commaItems.first?.title == "Settings…" && commaItems.first?.action == #selector(App.showSettings(_:)) && allItems.first(where: { $0.action == #selector(App.editConfig(_:)) })?.keyEquivalent == ""
        let picker = AppearancePanel(application:app)
        app.appearancePanel = picker
        picker.window?.contentView?.layoutSubtreeIfNeeded()
        checks["oneAppearanceMenuIncludesBackground"] = view?.items.filter { $0.title == "Settings…" }.count == 1 && view?.items.contains(where: { $0.title == "Dynamic Backgrounds…" }) == false && picker.pages["Background"] != nil
        checks["themeSelectionHasTick"] = picker.paletteButtons.count == Configuration.themeNames.count && picker.paletteButtons.filter { $0.state == .on }.count == 1
        let enter = NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:picker.window!.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
        let exit = NSEvent.enterExitEvent(with:.mouseExited,location:.zero,modifierFlags:[],timestamp:0,windowNumber:picker.window!.windowNumber,context:nil,eventNumber:1,trackingNumber:0,userData:nil)!
        checks["themePreviewsSurvivePointerExit"] = picker.paletteButtons.allSatisfy { card in
            guard let card = card as? AppearancePreviewButton,let original = card.image else { return false }
            for _ in 0..<3 { card.mouseEntered(with:enter); card.mouseExited(with:exit) }
            return card.image === original
        }

        checks["backgroundOverrideIsExplained"] = picker.backgroundNote.stringValue.contains("overrides") && picker.backgroundNote.stringValue.contains("theme")
        checks["configurationPathAndFileEditingAreExplained"] = picker.configPath.stringValue == Configuration.url.path && picker.configPath.isSelectable
        var schema = Configuration(); schema.palette = Configuration.Palette(background:"151820",foreground:"DFE4EF",accent:"A5B8FF")
        let object = try! JSONSerialization.jsonObject(with:JSONEncoder().encode(schema))
        func paths(_ object: Any, prefix: String = "") -> Set<String> {
            if let dictionary = object as? [String:Any] { return dictionary.reduce(into:Set<String>()) { result,pair in result.formUnion(paths(pair.value,prefix:prefix.isEmpty ? pair.key : prefix+"."+pair.key)) } }
            return [prefix]
        }
        let expected = paths(object), missing = expected.subtracting(picker.fields.keys)
        checks["appearancePanelCoversEditableConfiguration"] = missing.isEmpty
        if !missing.isEmpty { print("Settings missing fields:",missing.sorted()) }
        checks["nativeFontAndTextColourPickersExist"] = picker.fields["fontName"] is NSButton && picker.fields["palette.foreground"] is NSColorWell && picker.fields["cursor.shape"] is NSPopUpButton
        let about = AboutWindowController()
        checks["aboutWindowIncludesRequestedThanks"] = about.thanksText.stringValue == "Pedro Ortiz Suarez\nDevon Dugentas\nThijs Dalhuijsen\nMalte Ostendorff\nMike Abbey\nPaul Bernicchi\nFinn Roach" && about.versionText.stringValue.contains(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Version")
        checks["openSourceNoticesAreBundled"] = Bundle.main.url(forResource:"THIRD-PARTY-NOTICES",withExtension:nil).flatMap { try? String(contentsOf:$0) }.map { $0.contains("Miguel de Icaza") && $0.contains("Jeff Lebrun") && $0.contains("Mark Gillard") } == true
        let saved = app.config
        app.config.background.style = "solid"; app.config.background.effectColors = ["112233","445566"]; app.config.background.speed = 2; app.config.background.intensity = 0.9
        picker.refresh(); picker.backgroundEnabled.performClick(nil)
        checks["backgroundTogglePreservesCustomSettings"] = app.config.background.style == "flow" && app.config.background.effectColors == ["112233","445566"] && app.config.background.speed == 2 && app.config.background.intensity == 0.9
        picker.animatedControls.reset?(); picker.refresh()
        checks["backgroundResetRestoresDefaults"] = app.config.background.resolvedColors == Configuration.Background.defaultColors && app.config.background.speed == 0.5 && app.config.background.intensity == 0.22
        checks["animatedEditorShowsPaletteStrengthAndSpeed"] = picker.plainBackgroundControls.isHidden && !picker.animatedControls.isHidden && picker.animatedControls.wells.filter { !$0.isHidden }.count == 3
        picker.tabs.selectTabViewItem(withIdentifier:"Background"); picker.window?.contentView?.layoutSubtreeIfNeeded()
        if let scroll = picker.scrollViews["Background"],let doc = scroll.documentView { checks["backgroundEditorFitsWithoutScrolling"] = doc.frame.height <= scroll.contentView.bounds.height+1 } else { checks["backgroundEditorFitsWithoutScrolling"] = false }
        let terminal = picker.livePreview.terminalPane.terminal
        checks["terminalPreviewUsesRealRendererWithoutPTY"] = !terminal.process.running && !terminal.acceptsFirstResponder && terminal.getTerminal().find("Hello, Moth.").matches.count > 0 && picker.livePreview.chrome.subviews.count == 3 && picker.livePreview.chrome.subviews.allSatisfy { $0 is NSButton }
        let chromeProbe = TerminalPreviewView(frame:NSRect(x:0,y:0,width:740,height:230))
        var previewConfig = app.config; previewConfig.window.showStatusBar = true; previewConfig.window.chromePosition = "titlebar"
        chromeProbe.apply(previewConfig); chromeProbe.layoutSubtreeIfNeeded()
        checks["previewSessionInformationMatchesTitlebarPosition"] = chromeProbe.infoBar.frame.midY > chromeProbe.terminalPane.frame.midY
        previewConfig.window.chromePosition = "bottom"; chromeProbe.apply(previewConfig); chromeProbe.layoutSubtreeIfNeeded()
        checks["previewSessionInformationMatchesBottomPosition"] = chromeProbe.infoBar.frame.midY < chromeProbe.terminalPane.frame.midY
        previewConfig.window.showStatusBar = false; chromeProbe.apply(previewConfig)
        checks["previewSessionInformationCanBeHidden"] = chromeProbe.infoBar.isHidden
        let terminalPixels = makeBitmap(for:terminal); draw(terminal,into:terminalPixels)
        var glyphPixels = 0
        for y in stride(from:0,to:terminalPixels.pixelsHigh,by:2) { for x in stride(from:0,to:terminalPixels.pixelsWide,by:2) { if let c = terminalPixels.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),c.alphaComponent > 0.5 && max(c.redComponent,c.greenComponent,c.blueComponent) > 0.5 { glyphPixels += 1 } } }
        checks["terminalPreviewRendersSampleGlyphs"] = glyphPixels > 100
        if let colour = picker.fields["palette.foreground"] as? NSColorWell {
            colour.color = .hex("CC5500"); _ = NSApp.sendAction(colour.action!,to:colour.target,from:colour)
            checks["textColourControlPersistsAndApplies"] = (try? Configuration.load().palette?.foreground) == "CC5500" && app.config.colors.1 == NSColor.hex("CC5500")
        } else { checks["textColourControlPersistsAndApplies"] = false }
        if let size = picker.fields["fontSize"] as? NSTextField {
            size.stringValue = "18"; picker.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:size))
            checks["fontSizeControlPersistsAndApplies"] = app.config.fontSize == 18 && (try? Configuration.load().fontSize) == 18
        } else { checks["fontSizeControlPersistsAndApplies"] = false }
        if let normal = picker.fields["ansiColors.1"] as? NSColorWell,let bright = picker.fields["ansiColors.9"] as? NSColorWell {
            normal.color = .hex("DDBBDD"); _ = NSApp.sendAction(normal.action!,to:normal.target,from:normal)
            bright.color = .hex("FFDDEE"); _ = NSApp.sendAction(bright.action!,to:bright.target,from:bright)
            checks["ansiNormalAndBrightControlsPersist"] = (try? Configuration.load().resolvedANSIColors[1]) == "DDBBDD" && (try? Configuration.load().resolvedANSIColors[9]) == "FFDDEE"
        } else { checks["ansiNormalAndBrightControlsPersist"] = false }
        checks["pastelANSIPresetsAreValid"] = Configuration.ansiPresets.count >= 4 && Configuration.ansiPresets.allSatisfy { $0.1.count == 16 && $0.1.allSatisfy(Configuration.validHex) }
        if let size = picker.fields["fontSize"] as? NSTextField,let stepper = picker.numericSteppers["fontSize"] {
            stepper.doubleValue = 19; _ = NSApp.sendAction(stepper.action!,to:stepper.target,from:stepper)
            checks["numericStepperPersistsIncrement"] = app.config.fontSize == 19
            let editor = NSTextView(); _ = picker.control(size,textView:editor,doCommandBy:#selector(NSResponder.moveDown(_:)))
            checks["numericArrowKeysAdjustAndPersist"] = app.config.fontSize == 18 && (try? Configuration.load().fontSize) == 18
        }
        if let border = picker.fields["window.showBorder"] as? NSButton {
            _ = picker.commit { $0.window.showBorder = true; $0.window.borderWidth = 1.75 }
            border.performClick(nil)
            let hidden = app.config.window.showBorder == false && (try? Configuration.load().window.showBorder) == false
            border.performClick(nil)
            checks["settingsBorderTogglePersistsWithoutLosingWidth"] = hidden && app.config.window.showBorder && app.config.window.borderWidth == 1.75
        }
        let before = try! Data(contentsOf:Configuration.url)
        checks["settingsRejectInvalidEditWithoutChangingFile"] = !picker.commit { $0.fontSize = 4 } && (try? Data(contentsOf:Configuration.url)) == before && app.config.fontSize == 18
        let stops = ["112233","334455","556677","778899","99AABB","BBDDFF"]
        _ = picker.commit { $0.cursor.paint.type = "linear"; $0.cursor.paint.colors = stops }
        picker.refresh()
        if let angle = picker.fields["cursor.paint.angle"] as? NSSlider {
            angle.doubleValue = 45; _ = NSApp.sendAction(angle.action!,to:angle.target,from:angle)
            checks["gradientEditorPreservesAllSixStops"] = app.config.cursor.paint.colors == stops && app.config.cursor.paint.angle == 45 && (try? Configuration.load().cursor.paint.colors) == stops
        } else { checks["gradientEditorPreservesAllSixStops"] = false }
        if let wheel = picker.fields["cursor.paint.angle"] as? DirectionWheel {
            checks["directionControlsAreContinuousWheels"] = ["cursor.paint.angle","window.borderPaint.angle","background.paint.angle"].allSatisfy { (picker.fields[$0] as? NSSlider)?.sliderType == .circular && (picker.fields[$0] as? NSSlider)?.isContinuous == true }
            wheel.doubleValue = 359.75; wheel.rotate(by:1)
            let forward = app.config.cursor.paint.angle
            wheel.rotate(by:-2)
            checks["directionWheelWrapsWithFractionalPrecision"] = abs(forward-0.75) < 0.001 && abs(app.config.cursor.paint.angle-358.75) < 0.001 && app.config.cursor.paint.colors == stops
        } else { checks["directionControlsAreContinuousWheels"] = false; checks["directionWheelWrapsWithFractionalPrecision"] = false }
        var coloured = Configuration(); coloured.background.style = "solid"; coloured.ansiColors = Configuration.defaultANSIColors
        let colours = Pane(config:coloured,start:false); colours.terminal.feed(text:"\u{1b}[31mMMMMMM\r\n\u{1b}[91mMMMMMM")
        coloured.ansiColors[1] = "FF0000"; coloured.ansiColors[9] = "00FF00"; colours.apply(coloured)
        let bitmap = makeBitmap(for:colours.terminal); draw(colours.terminal,into:bitmap)
        var red = false,green = false
        for y in stride(from:0,to:bitmap.pixelsHigh,by:2) { for x in stride(from:0,to:min(250,bitmap.pixelsWide),by:2) { if let c = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) { if c.redComponent > 0.7 && c.greenComponent < 0.2 { red = true }; if c.greenComponent > 0.7 && c.redComponent < 0.2 { green = true } } } }
        checks["ansiPaletteRecoloursExistingIndexedText"] = red && green
        _ = picker.commit { $0.keybindings["newTab"] = "" }
        checks["shortcutsCanBeDisabledAndReloaded"] = (try? Configuration.load().keybindings["newTab"]) == ""
        _ = picker.commit { $0.background.style = "solid" }; picker.refresh()
        checks["offBackgroundHasPlainColourControls"] = !picker.plainBackgroundControls.isHidden && picker.animatedControls.isHidden && picker.backgroundEnabled.state == .off
        _ = picker.commit { $0.keyboardSound.musical = true }
        let everySoundHasScale = picker.soundButtons.allSatisfy { tile in
            tile.performClick(nil)
            return app.config.keyboardSound.style == tile.identifier?.rawValue && (picker.fields["keyboardSound.key"] as? NSControl)?.isEnabled == true && (picker.fields["keyboardSound.mode"] as? NSControl)?.isEnabled == true
        }
        checks["allSoundTilesKeepKeyAndModeAvailable"] = everySoundHasScale && picker.soundButtons.count == Configuration.keyboardSoundStyles.count
        if let mode = picker.fields["keyboardSound.mode"] as? NSPopUpButton { mode.selectItem(at:6); _ = NSApp.sendAction(mode.action!,to:mode.target,from:mode) }
        checks["musicalModePickerPersistsLocrian"] = (try? Configuration.load().keyboardSound.mode) == "locrian"
        if let pattern = picker.fields["keyboardSound.pattern"] as? NSSegmentedControl,let reverb = picker.fields["keyboardSound.reverb"] as? NSSlider {
            pattern.selectedSegment = 3; _ = NSApp.sendAction(pattern.action!,to:pattern.target,from:pattern)
            reverb.doubleValue = 0.63; _ = NSApp.sendAction(reverb.action!,to:reverb.target,from:reverb); picker.flushAudioEdits()
            checks["patternAndReverbControlsPersist"] = (try? Configuration.load().keyboardSound.pattern) == "arpeggiating" && (try? Configuration.load().keyboardSound.reverb) == 0.63
        } else { checks["patternAndReverbControlsPersist"] = false }
        if let musical = picker.fields["keyboardSound.musical"] as? NSButton,let key = picker.fields["keyboardSound.key"] {
            musical.performClick(nil)
            checks["musicalOptionsHideWhenDisabled"] = !app.config.keyboardSound.musical && key.isHiddenOrHasHiddenAncestor && (try? Configuration.load().keyboardSound.musical) == false
            musical.performClick(nil)
            checks["musicalTogglePreservesSavedModeAndPattern"] = app.config.keyboardSound.musical && !key.isHiddenOrHasHiddenAncestor && app.config.keyboardSound.mode == "locrian" && app.config.keyboardSound.pattern == "arpeggiating"
        }
        app.config.fontName = "JetBrainsMonoNFM-Regular"; app.config.typography.ligatures = true; app.persistAppearance(); picker.refresh()
        if let feature = picker.fields["opentype.zero"] as? NSPopUpButton {
            feature.selectItem(at:2); _ = NSApp.sendAction(feature.action!,to:feature.target,from:feature)
            checks["openTypeControlPersistsAndApplies"] = (try? Configuration.load().typography.features["zero"]) == 1
            if let reset = picker.fields["opentype.zero"] as? NSPopUpButton {
                reset.selectItem(at:0); _ = NSApp.sendAction(reset.action!,to:reset.target,from:reset)
                checks["fontDefaultRemovesSavedFeatureOverride"] = (try? Configuration.load().typography.features["zero"]) == nil
            }
        } else { checks["openTypeControlPersistsAndApplies"] = false }
        if let stepper = picker.numericSteppers["typography.lineHeight"] {
            stepper.doubleValue = 1.35; _ = NSApp.sendAction(stepper.action!,to:stepper.target,from:stepper)
            checks["lineHeightControlPersistsAndApplies"] = (try? Configuration.load().typography.lineHeight) == 1.35 && app.active?.workspace.active.terminal.lineHeightMultiplier == 1.35
        }
        if let antialias = picker.fields["typography.antialias"] as? NSButton {
            app.config.typography.antialias = true; app.persistAppearance(); picker.refresh(); antialias.performClick(nil)
            checks["antialiasControlPersistsAndUpdatesTerminalsAndPreview"] = (try? Configuration.load().typography.antialias) == false && app.windows.flatMap(\.workspaces).flatMap(\.panes).allSatisfy { !$0.terminal.antialiasText } && !picker.livePreview.terminalPane.terminal.antialiasText
        } else { checks["antialiasControlPersistsAndUpdatesTerminalsAndPreview"] = false }
        if let encoding = picker.fields["encoding.enabled.SHIFT_JIS"] as? NSButton {
            encoding.performClick(nil)
            checks["advancedEncodingCheckboxUpdatesPersistentMenuChoices"] = (try? Configuration.load().enabledEncodings.contains("SHIFT_JIS")) == false && !TerminalTextEncoding.available(app.config).contains { $0.id == "SHIFT_JIS" }
            encoding.performClick(nil)
            checks["encodingCanBeEnabledAgain"] = (try? Configuration.load().enabledEncodings.contains("SHIFT_JIS")) == true
            let enabledBefore = app.config.enabledEncodings
            app.config.enabledEncodings = ["UTF-8"]; app.persistAppearance(); picker.refresh()
            if let last = picker.fields["encoding.enabled.UTF-8"] as? NSButton {
                last.performClick(nil)
                checks["cannotDisableLastEncodingAndCheckboxReflectsSavedState"] = last.state == .on && app.config.enabledEncodings == ["UTF-8"] && (try? Configuration.load().enabledEncodings) == ["UTF-8"]
            }
            app.config.enabledEncodings = enabledBefore; app.persistAppearance(); picker.refresh()

        } else { checks["advancedEncodingCheckboxUpdatesPersistentMenuChoices"] = false }
        if let close = picker.fields["closeOnExit"] as? NSButton {
            let old = app.config.closeOnExit; close.performClick(nil)
            checks["closeOnExitSettingsControlPersists"] = (try? Configuration.load().closeOnExit) == !old && app.config.closeOnExit == !old
        } else { checks["closeOnExitSettingsControlPersists"] = false }
        app.config = saved; app.persistAppearance(); picker.refresh()
        picker.showWindow(nil)
        var panelsFit = true, sidebarWorks = true
        for name in ["Theme","Background","Colours","Keyboard Sounds","Cursor","Window","Font","Profiles","Closing","Macros","Advanced"] {
            picker.tabs.selectTabViewItem(withIdentifier:name); picker.window?.contentView?.layoutSubtreeIfNeeded()
            if ["Keyboard Sounds","Profiles","Closing","Macros","Advanced"].contains(name) { checks["terminalPreviewIsContextualToVisualSettings"] = picker.livePreview.isHidden }
            else { checks["terminalPreviewReturnsForVisualSettings"] = !picker.livePreview.isHidden }
            sidebarWorks = sidebarWorks && picker.navigation.selectedRow >= 0 && picker.tabs.tabViewType == .noTabsNoBorder
            if let scroll = picker.scrollViews[name],let document = scroll.documentView {
                panelsFit = panelsFit && abs(document.frame.width-scroll.contentView.bounds.width) < 1
                if let page = picker.pages[name] { panelsFit = panelsFit && page.frame.width > 500 && page.frame.maxX <= document.bounds.maxX }
            } else { panelsFit = false }
            if let root = picker.window?.contentView,let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds) {
                root.cacheDisplay(in:root.bounds,to:bitmap)
                let folder = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!).deletingLastPathComponent()
                try? bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("Appearance-"+name.replacingOccurrences(of:" ",with:"")+".png"))
            }
            if name == "Advanced",let target = picker.fields["enabledEncodings"],let scroll = picker.scrollViews[name],let document = scroll.documentView {
                let rect = target.convert(target.bounds,to:document).insetBy(dx:0,dy:-55)
                document.scrollToVisible(rect); picker.window?.contentView?.layoutSubtreeIfNeeded()
                if let root = picker.window?.contentView { capturePreview(root,name:"Appearance-Encodings.png") }
                scroll.contentView.scroll(to:.zero); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        var resizedFit = true
        for size in [NSSize(width:940,height:700),NSSize(width:1180,height:900)] {
            picker.window?.setContentSize(size)
            for name in ["Keyboard Sounds","Background","Cursor","Colours","Font"] {
                picker.tabs.selectTabViewItem(withIdentifier:name); picker.window?.contentView?.layoutSubtreeIfNeeded()
                if let scroll = picker.scrollViews[name],let document = scroll.documentView {
                    resizedFit = resizedFit && abs(document.frame.width-scroll.contentView.bounds.width) < 1
                    for field in picker.fields.values where field.window === picker.window && !field.isHiddenOrHasHiddenAncestor {
                        let frame = field.convert(field.bounds,to:document)
                        resizedFit = resizedFit && frame.minX >= -1 && frame.maxX <= document.bounds.width+1
                    }
                }
            }
        }
        checks["settingsControlsStayInsideNarrowAndWideWindows"] = resizedFit
        picker.window?.setContentSize(NSSize(width:980,height:800))
        checks["settingsSidebarTracksSelectedSection"] = sidebarWorks
        checks["settingsPagesFitConsistentContentWidth"] = panelsFit
        checks["keyboardSoundControlsIncludeKeyModeAndVolume"] = picker.fields["keyboardSound.enabled"] is NSButton && picker.fields["keyboardSound.style"] is NSStackView && picker.fields["keyboardSound.mode"] is NSPopUpButton && picker.fields["keyboardSound.key"] is NSPopUpButton && picker.fields["keyboardSound.volume"] is NSSlider
        picker.window?.orderOut(nil)
        app.config = saved; app.persistAppearance()
        checks["opacityOnlyAppearsInAppearance"] = view?.items.contains(where: { $0.title == "Opacity" }) == false && picker.fields["window.opacity"] is NSSlider && picker.fields["window.frosted"] is NSButton
    }

    static func activateValidationApp() {
        NSApp.activate(ignoringOtherApps:true)
        if !NSApp.isActive,Bundle.main.bundleURL.lastPathComponent == "Moth Validation.app" {
            let open = Process(); open.executableURL = URL(fileURLWithPath:"/usr/bin/open"); open.arguments = ["-a",Bundle.main.bundlePath]; open.standardOutput = FileHandle.nullDevice; open.standardError = FileHandle.nullDevice
            try? open.run(); open.waitUntilExit()
        }
    }
    static func focusForKeyboardTest(_ controller: TerminalWindowController) {
        guard let window = controller.window else { return }
        activateValidationApp(); window.makeKeyAndOrderFront(nil)
        let deadline = Date().addingTimeInterval(0.5)
        while (!window.isKeyWindow || !NSApp.isActive), Date() < deadline {
            if let event = NSApp.nextEvent(matching:.any,until:Date().addingTimeInterval(0.01),inMode:.default,dequeue:true) { NSApp.sendEvent(event) }
            RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.01))
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func activationClickChecks(app: App, into checks: inout [String:Bool]) {
        let previous = app.active, controller = TerminalWindowController(application:app)
        app.windows.append(controller);controller.showWindow(nil)
        guard let window = controller.window else { checks["paneClickFixture"] = false;return }
        defer { controller.stop();window.close();previous?.window?.makeKeyAndOrderFront(nil) }
        window.setContentSize(NSSize(width:1000,height:650));controller.content.layoutSubtreeIfNeeded()
        let workspace = controller.workspace
        workspace.split(vertical:true,config:app.config);controller.content.layoutSubtreeIfNeeded()
        guard workspace.panes.count == 2 else { checks["paneClickFixture"] = false;return }
        let first = workspace.panes[0],second = workspace.panes[1]
        window.makeFirstResponder(first.terminal)
        func click(_ pane: Pane, gutter: Bool) -> Bool {
            let target: NSView = gutter ? pane:pane.terminal
            let local = gutter ? NSPoint(x:2,y:pane.bounds.midY):NSPoint(x:30,y:pane.terminal.bounds.midY)
            let point = target.convert(local,to:nil)
            let down = NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            // Verify the gate AppKit uses for an activating click, then exercise
            // actual window hit testing and first-responder routing. Physical
            // cross-application activation still requires an interactive check.
            let accepts = target.acceptsFirstMouse(for:down)
            if accepts {
                window.sendEvent(down)
                let up = NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
                window.sendEvent(up)
            }
            return accepts && window.firstResponder === pane.terminal && workspace.active === pane
        }
        checks["firstClickFocusesClickedTerminalPane"] = click(second,gutter:false)
        checks["firstClickMovesFocusBackToOtherPane"] = click(first,gutter:false)
        checks["firstClickInPanePaddingFocusesItsTerminal"] = click(second,gutter:true)
        let recorder = MacroRecorder.shared;recorder.start(second.terminal)
        let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"x",charactersIgnoringModifiers:"x",isARepeat:false,keyCode:7)!
        window.sendEvent(key)
        checks["typingAfterPaneClickReachesClickedPane"] = recorder.finish().keys.joined() == "x"
    }

    static func paneClosingChecks(app: App, into checks: inout [String:Bool]) {
        let previous = app.active, confirmation = app.config.closeConfirmation.enabled
        app.config.closeConfirmation.enabled = false
        let controller = TerminalWindowController(application:app)
        app.windows.append(controller)
        controller.window?.setContentSize(NSSize(width:1100,height:700)); controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        controller.content.layoutSubtreeIfNeeded()
        let ws = controller.workspace
        ws.split(vertical:true,config:app.config); ws.split(vertical:false,config:app.config)
        controller.content.layoutSubtreeIfNeeded()
        checks["splitPanesHaveCloseControls"] = ws.panes.count == 3 && ws.panes.allSatisfy { !$0.closeButton.isHidden }
        controller.content.layoutSubtreeIfNeeded()
        checks["paneCloseButtonsAlignWithScrollbars"] = ws.panes.allSatisfy { pane in
            guard let scroller = pane.terminal.subviews.first(where: { $0 is NSScroller }) else { return false }
            return abs(scroller.convert(scroller.bounds,to:pane).midX-pane.closeButton.frame.midX) < 0.5
        }
        func splitCount(_ view: NSView) -> Int { (view is NSSplitView ? 1 : 0)+view.subviews.reduce(0) { $0+splitCount($1) } }
        focusForKeyboardTest(controller)
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:controller.window!.windowNumber,context:nil,characters:"w",charactersIgnoringModifiers:"w",isARepeat:false,keyCode:13)!
        let handled = NSApp.mainMenu?.performKeyEquivalent(with:event) == true
        if !handled || ws.panes.count != 2 { print("Close dispatch:",handled,"active app:",NSApp.isActive,"key:",String(describing:NSApp.keyWindow?.windowController),"expected key:",controller.window?.isKeyWindow == true,"target:",app.active === controller) }
        checks["commandWCollapsesNestedSplit"] = handled && ws.panes.count == 2 && splitCount(ws.root) == 1
        if ws.panes.count == 2 {
            let survivor = ws.panes[1], pid = ws.panes[1].terminal.process.shellPid
            ws.panes[0].closeButton.performClick(nil)
            controller.content.layoutSubtreeIfNeeded()
            checks["paneCloseButtonCollapsesLastSplit"] = ws.panes.count == 1 && splitCount(ws.root) == 0 && ws.root.subviews.first === survivor && abs(survivor.frame.width-ws.root.bounds.width) < 1 && abs(survivor.frame.height-ws.root.bounds.height) < 1
            checks["closingSplitPreservesSurvivingSession"] = survivor.terminal.process.shellPid == pid && survivor.terminal.process.running && survivor.closeButton.isHidden
        } else { checks["paneCloseButtonCollapsesLastSplit"] = false; checks["closingSplitPreservesSurvivingSession"] = false }
        controller.stop(); controller.window?.close(); app.config.closeConfirmation.enabled = confirmation
        previous?.window?.makeKeyAndOrderFront(nil)
    }

    static func livePaneMaximizationChecks(completion:@escaping ([String:Bool])->Void) {
        var config=Configuration();config.shell="/bin/sh";config.advanced.loginShell=false
        config.advanced.environment=["PS1":"$ ","ENV":"/dev/null","HISTFILE":"/dev/null"]
        func row()->SavedSplit { .split(vertical:true,fraction:0.33,first:.pane,second:.split(vertical:true,fraction:0.5,first:.pane,second:.pane)) }
        let tree=SavedSplit.split(vertical:false,fraction:0.33,first:row(),second:.split(vertical:false,fraction:0.5,first:row(),second:row()))
        let ws=Workspace(config:config,startProcesses:true,saved:SavedTab(root:tree,activePane:4))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1000),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=ws.root;ws.root.layoutSubtreeIfNeeded();ws.applyRestoredGeometry()
        let panes=ws.orderedPanes,pids=ws.orderedPanes.map{$0.terminal.process.shellPid}
        ws.toggleMaximizePane()
        for (index,pane) in panes.enumerated() { pane.terminal.send(txt:"printf 'MOTH_ZOOM_\(index)\\n'\r") }
        let deadline=ProcessInfo.processInfo.systemUptime+6
        func check(){
            let output=panes.enumerated().allSatisfy { index,pane in pane.terminal.getTerminal().exportPlainText().contains("MOTH_ZOOM_\(index)\r") || pane.terminal.getTerminal().find("MOTH_ZOOM_\(index)").matches.count>=2 }
            if !output,ProcessInfo.processInfo.systemUptime<deadline { DispatchQueue.main.asyncAfter(deadline:.now()+0.1){check()};return }
            var results:[String:Bool]=[:]
            results["allNineShellsSurviveMaximisation"]=pids.allSatisfy{$0>0 && kill($0,0)==0} && ws.orderedPanes.map{$0.terminal.process.shellPid}==pids
            results["hiddenPanesKeepReceivingPTYOutput"]=output
            ws.focusPane(panes[8]);ws.restoreSplitLayout()
            results["restoringAndCyclingKeepOriginalShellProcesses"]=ws.orderedPanes.map{$0.terminal.process.shellPid}==pids && panes.allSatisfy{$0.terminal.process.running}
            ws.stop();window.close();completion(results)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3){check()}
    }
    static func paneMaximizationChecks(into checks:inout [String:Bool]) {
        let config=Configuration()
        func row()->SavedSplit { .split(vertical:true,fraction:0.33,first:.pane,second:.split(vertical:true,fraction:0.5,first:.pane,second:.pane)) }
        let tree=SavedSplit.split(vertical:false,fraction:0.33,first:row(),second:.split(vertical:false,fraction:0.5,first:row(),second:row()))
        let ws=Workspace(config:config,startProcesses:false,saved:SavedTab(root:tree,activePane:4))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1000),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=ws.root;ws.root.layoutSubtreeIfNeeded();ws.applyRestoredGeometry()
        let original=ws.orderedPanes,target=ws.active!
        for (index,pane) in original.enumerated() { pane.terminal.feed(text:"pane \(index) history\r\n") }
        target.terminal.selectAll(nil)
        let selection=target.terminal.getSelection()
        let history=original.map{$0.terminal.getTerminal().exportPlainText()}
        func same(_ left:SavedSplit,_ right:SavedSplit)->Bool {
            switch (left,right) {
            case (.pane,.pane):return true
            case let (.split(v,x,a,b),.split(w,y,c,d)):return v==w && abs(x-y)<0.01 && same(a,c) && same(b,d)
            default:return false
            }
        }
        do {
            let before=try ws.savedTab()
            ws.toggleMaximizePane()
            checks["maximisePaneFillsTab"] = ws.isPaneMaximized && ws.root.subviews.count==1 && ws.root.subviews.first === target && abs(target.bounds.width-ws.root.bounds.width)<1 && abs(target.bounds.height-ws.root.bounds.height)<1
            checks["maximiseKeepsAllNinePaneObjects"] = ws.panes.count==9 && zip(ws.orderedPanes,original).allSatisfy{$0 === $1}
            let during=try ws.savedTab();try during.root.validate()
            checks["savingWhileMaximisedPreservesWholeLayout"] = during.root.paneCount==9 && same(before.root,during.root) && during.activePane==before.activePane
            checks["maximisePreservesSelection"] = selection != nil && target.terminal.getSelection()==selection
            window.setContentSize(NSSize(width:1600,height:1100));ws.root.layoutSubtreeIfNeeded()
            ws.toggleMaximizePane()
            let after=try ws.savedTab()
            checks["restoreAfterResizeKeepsDividerRatios"] = !ws.isPaneMaximized && same(before.root,after.root)
            checks["restoreKeepsPaneHistory"] = zip(original,history).allSatisfy{$0.terminal.getTerminal().exportPlainText()==$1}
            ws.toggleMaximizePane();ws.focusPane(original[5])
            checks["cyclingPanesWhileMaximisedKeepsMaximisedView"] = ws.isPaneMaximized && ws.active === original[5] && ws.root.subviews.first === original[5]
            ws.close(original[5])
            checks["closingMaximisedPaneRestoresRemainingSplits"] = !ws.isPaneMaximized && ws.panes.count==8 && ws.orderedPanes.count==8
            ws.toggleMaximizePane();let detached=ws.active!
            checks["detachingMaximisedPaneRestoresLayout"] = ws.detach(detached) && !ws.isPaneMaximized && ws.panes.count==7 && ws.orderedPanes.count==7
            detached.stop()
            checks["maximiseShortcutIsCommandShiftReturn"] = Configuration.shortcut(config.keybindings["toggleMaximizePane"] ?? "")?.0=="\r" && Configuration.shortcut(config.keybindings["toggleMaximizePane"] ?? "")?.1 == [.command,.shift]
            let legacy=try JSONDecoder().decode(Configuration.self,from:Data("{\"keybindings\":{\"newWindow\":\"cmd+n\"}}".utf8))
            checks["existingPreferencesGetMaximiseShortcut"] = legacy.keybindings["toggleMaximizePane"]=="cmd+shift+return"
            let reserved=try JSONDecoder().decode(Configuration.self,from:Data("{\"keybindings\":{\"newWindow\":\"cmd+shift+return\"}}".utf8))
            checks["maximiseMigrationRespectsShortcutConflicts"] = reserved.keybindings["toggleMaximizePane"]==""
            let macroConfig=try JSONDecoder().decode(Configuration.self,from:Data("{\"macros\":{\"Test\":{\"text\":\"date\",\"shortcut\":\"cmd+shift+enter\"}}}".utf8))
            try macroConfig.validate()
            checks["maximiseMigrationRespectsMacroShortcuts"] = macroConfig.keybindings["toggleMaximizePane"]==""
        } catch { print("Maximisation checks:",error);checks["maximiseLayoutChecksComplete"]=false }
        ws.stop();window.close()
    }
    static func splitGeometryChecks(into checks: inout [String:Bool]) {
        var proportions = true,alignment = true,coverage = true
        for secondVertical in [true,false] { for closing in 0..<3 {
            let ws = Workspace(config:Configuration(),startProcesses:false)
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:700),styleMask:[.borderless],backing:.buffered,defer:false); window.isReleasedWhenClosed = false; window.contentView = ws.root
            window.orderFront(nil); ws.root.layoutSubtreeIfNeeded(); ws.split(vertical:true,config:Configuration()); ws.split(vertical:secondVertical,config:Configuration())
            window.setContentSize(NSSize(width:1300,height:760)); ws.root.layoutSubtreeIfNeeded()
            if ws.panes.count == 3 { ws.active = ws.panes[closing]; ws.closeActive() }
            ws.root.layoutSubtreeIfNeeded()
            if let split = ws.root.subviews.first as? NSSplitView,split.arrangedSubviews.count == 2,ws.panes.count == 2 {
                let available = (split.isVertical ? split.bounds.width : split.bounds.height)-split.dividerThickness
                let first = split.isVertical ? split.arrangedSubviews[0].frame.width : split.arrangedSubviews[0].frame.height
                proportions = proportions && abs(first/available-0.5) < 0.015
                let area = ws.panes.reduce(CGFloat(0)) { $0+$1.frame.width*$1.frame.height }
                let expected = ws.root.bounds.width*ws.root.bounds.height-split.dividerThickness*(split.isVertical ? split.bounds.height : split.bounds.width)
                coverage = coverage && abs(area-expected) < 4*max(ws.root.bounds.width,ws.root.bounds.height)
                for pane in ws.panes {
                    if let scroller = pane.terminal.subviews.first(where: { $0 is NSScroller }) { alignment = alignment && abs(scroller.convert(scroller.bounds,to:pane).midX-pane.closeButton.frame.midX) < 0.5 } else { alignment = false }
                }
            } else { proportions = false; coverage = false; alignment = false }
            ws.stop(); window.close()
        } }
        checks["closingAnyOfThreePanesPreservesSplitProportions"] = proportions
        checks["closeControlsTrackExpandedPaneScrollbars"] = alignment
        checks["closedSplitLeavesNoEmptyArea"] = coverage
        // Nine panes form a useful three-by-three workspace. Check both live
        // splitting and the deepest serialised tree that nine leaves can form.
        func row(_ count:Int)->SavedSplit {
            count == 1 ? .pane:.split(vertical:true,fraction:1/Double(count),first:.pane,second:row(count-1))
        }
        let eight=SavedSplit.split(vertical:false,fraction:1.0/3,first:row(3),second:.split(vertical:false,fraction:0.5,first:row(3),second:row(2)))
        let nineWS=Workspace(config:Configuration(),startProcesses:false,saved:SavedTab(root:eight,activePane:7))
        let nineWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1000),styleMask:[.borderless],backing:.buffered,defer:false)
        nineWindow.isReleasedWhenClosed=false;nineWindow.contentView=nineWS.root
        nineWS.root.layoutSubtreeIfNeeded();nineWS.applyRestoredGeometry()
        nineWS.split(vertical:true,config:Configuration());nineWS.root.layoutSubtreeIfNeeded()
        checks["ninthPaneCanBeCreated"] = nineWS.panes.count == 9
        nineWS.active=nineWS.orderedPanes.first
        let hasSpace=(nineWS.active?.bounds.width ?? 0)>=420
        nineWS.split(vertical:true,config:Configuration())
        checks["tenthPaneIsRejectedEvenWithSpace"] = hasSpace && nineWS.panes.count == 9
        do {
            let saved=try nineWS.savedTab();try saved.root.validate()
            let data=try JSONEncoder().encode(saved)
            let decoded=try JSONDecoder().decode(SavedTab.self,from:data);try decoded.root.validate()
            checks["ninePaneLayoutRoundTrips"] = decoded.root.paneCount == 9
            let restored=Workspace(config:Configuration(),startProcesses:false,saved:decoded)
            checks["ninePaneLayoutRestores"] = restored.panes.count == 9;restored.stop()
            try row(9).validate();checks["deeplyNestedNinePaneLayoutAllowed"] = true
        } catch { print("Nine-pane layout:",error);checks["ninePaneLayoutRoundTrips"]=false }
        do { try row(10).validate();checks["tenPaneLayoutRejected"]=false } catch { checks["tenPaneLayoutRejected"]=true }
        nineWS.stop();nineWindow.close()
    }
    static func savedLayoutChecks(app: App,into checks: inout [String:Bool]) {
        let previous = app.active,source = TerminalWindowController(application:app)
        source.window?.setContentSize(NSSize(width:1100,height:700)); source.showWindow(nil); source.window?.makeKeyAndOrderFront(nil); source.content.layoutSubtreeIfNeeded()
        source.workspace.split(vertical:true,config:app.config); source.workspace.split(vertical:false,config:app.config)
        if let split = source.workspace.root.subviews.first as? NSSplitView { split.setPosition((split.bounds.width-split.dividerThickness)*0.35,ofDividerAt:0) }
        source.newTab(nil); source.workspace.split(vertical:false,config:app.config); source.selectTab(at:0); source.content.layoutSubtreeIfNeeded()
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("layout-store-test.json")
        do {
            let saved = try SavedWindowLayout.capture(source,name:"Daily Work"); try WindowLayoutStore.save(saved,to:path)
            let loaded = try WindowLayoutStore.load(from:path)
            checks["namedWindowLayoutPersistsTabsAndSplits"] = loaded.count == 1 && loaded[0].name == "Daily Work" && loaded[0].tabs.count == 2 && loaded[0].tabs.map { $0.root.paneCount } == [3,2] && loaded[0].activeTab == 0
            let restored = TerminalWindowController(application:app,savedLayout:loaded[0]); restored.showWindow(nil); restored.window?.makeKeyAndOrderFront(nil); restored.content.layoutSubtreeIfNeeded(); restored.workspace.applyRestoredGeometry()
            let again = try SavedWindowLayout.capture(restored,name:"Restored")
            func nodesEqual(_ left: SavedSplit,_ right: SavedSplit) -> Bool {
                switch (left,right) { case (.pane,.pane):return true; case let (.split(v,x,a,b),.split(w,y,c,d)):return v == w && abs(x-y) < 0.015 && nodesEqual(a,c) && nodesEqual(b,d); default:return false }
            }
            checks["restoredLayoutKeepsDividerRatiosAndActiveTab"] = saved.activeTab == again.activeTab && zip(saved.tabs,again.tabs).allSatisfy { pair in nodesEqual(pair.0.root,pair.1.root) && pair.0.activePane == pair.1.activePane }
            let originalPIDs = Set(source.workspaces.flatMap(\.panes).map { $0.terminal.process.shellPid })
            checks["restoredLayoutStartsFreshShells"] = restored.workspaces.flatMap(\.panes).allSatisfy { $0.terminal.process.running && !originalPIDs.contains($0.terminal.process.shellPid) }
            restored.selectTab(at:1); restored.content.layoutSubtreeIfNeeded(); restored.workspace.applyRestoredGeometry()
            checks["restoredInactiveTabGetsItsSplitGeometry"] = restored.workspace.panes.count == 2 && (restored.workspace.root.subviews.first as? NSSplitView)?.isVertical == false
            restored.stop(); restored.window?.close()
            let chooser = WindowLayoutChooser(application:app,storeURL:path); app.layoutChooser = chooser
            app.buildMenu()
            let shortcut = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.shift],timestamp:0,windowNumber:source.window!.windowNumber,context:nil,characters:"R",charactersIgnoringModifiers:"R",isARepeat:false,keyCode:15)!
            checks["commandShiftROpensSavedLayoutChooser"] = NSApp.mainMenu?.performKeyEquivalent(with:shortcut) == true && chooser.window?.isVisible == true
            chooser.search.stringValue = "Daily"; chooser.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:chooser.search))
            checks["savedLayoutChooserFiltersByName"] = chooser.table.numberOfRows == 1
            let before = app.windows.count
            _ = NSApp.sendAction(chooser.search.action!,to:chooser.search.target,from:chooser.search)
            let opened = app.windows.last
            checks["layoutChooserOpensNamedMultiTabWindow"] = app.windows.count == before+1 && opened?.workspaces.count == 2 && opened?.workspaces.flatMap(\.panes).count == 5
            if app.windows.count > before { opened?.stop(); opened?.window?.close() }
            chooser.window?.close(); app.layoutChooser = nil
            try WindowLayoutStore.rename(saved.id,to:"Writing",at:path)
            checks["savedLayoutsCanBeRenamed"] = try WindowLayoutStore.load(from:path).first?.name == "Writing"
            try WindowLayoutStore.remove(saved.id,from:path)
            checks["savedLayoutsCanBeDeleted"] = try WindowLayoutStore.load(from:path).isEmpty
            var invalid = saved; invalid.activeTab = 99
            do { try invalid.validate(); checks["invalidSavedLayoutRejected"] = false } catch { checks["invalidSavedLayoutRejected"] = true }
        } catch { print("Layout tests:",error); checks["namedWindowLayoutPersistsTabsAndSplits"] = false }
        source.stop(); source.window?.close(); previous?.window?.makeKeyAndOrderFront(nil)
        let migration = Configuration.url.deletingLastPathComponent().appendingPathComponent("layout-shortcuts.toml")
        do {
            let text = try Configuration.document(Configuration()).replacingOccurrences(of:"reloadConfig = \"cmd+alt+r\"",with:"reloadConfig = \"cmd+shift+r\"").components(separatedBy:"\n").filter { !$0.hasPrefix("openLayouts =") }.joined(separator:"\n")
            try Data(text.utf8).write(to:migration); let config = try Configuration.expandFile(at:migration)
            checks["layoutShortcutMigrationMovesReloadToOptionR"] = config.keybindings["openLayouts"] == "cmd+shift+r" && config.keybindings["reloadConfig"] == "cmd+alt+r"
        } catch { checks["layoutShortcutMigrationMovesReloadToOptionR"] = false }
        app.buildMenu()
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0]+($0.submenu.map(items) ?? []) } }
        let all = NSApp.mainMenu.map(items) ?? []
        let launch = all.first { $0.action == #selector(App.showSavedLayouts(_:)) },reload = all.first { $0.action == #selector(App.reloadConfig(_:)) }
        checks["layoutAndReloadMenusHaveDistinctShortcuts"] = launch?.keyEquivalent == "R" && launch?.keyEquivalentModifierMask == [.command,.shift] && reload?.keyEquivalent == "r" && reload?.keyEquivalentModifierMask == [.command,.option]
    }

    static func windowGlassChecks(into checks: inout [String: Bool]) {
        var config = Configuration(); config.background.style = "solid"; config.window.opacity = 0.45
        let view = FlowBackgroundView(frame:NSRect(x:0,y:0,width:180,height:100))
        let host = NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false); host.isReleasedWhenClosed = false; host.isOpaque = false; host.backgroundColor = .clear; host.contentView = view; host.orderFront(nil)
        view.apply(config); view.layoutSubtreeIfNeeded(); defer { host.orderOut(nil) }
        let bitmap = makeBitmap(for: view), context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.scaleBy(x: 2, y: 2); view.backgroundSurface.layer?.render(in: context)
        let alpha = bitmap.colorAt(x: 180, y: 100)?.alphaComponent ?? -1
        checks["windowBackgroundActuallyHasAlpha"] = abs(alpha-config.windowBackgroundOpacity) < 0.02
        if checks["windowBackgroundActuallyHasAlpha"] == false { print("Opacity sample:",alpha,"surface:",view.backgroundSurface.layer?.frame as Any) }
        checks["clearGlassHasNoFrosting"] = view.frost.isHidden
        let pane = Pane(config: config, start: false)
        checks["solidTerminalAllowsWindowTransparency"] = pane.terminal.nativeBackgroundColor.alphaComponent == (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0)
        pane.terminal.feed(text: "\u{1b}[38;2;255;255;255mMMMMMMMM")
        let textBitmap = makeBitmap(for: pane.terminal); draw(pane.terminal, into: textBitmap)
        var solidText = false, clearBackground = false
        for y in 0..<textBitmap.pixelsHigh { for x in 0..<min(300,textBitmap.pixelsWide) {
            if let color = textBitmap.colorAt(x: x, y: y) {
                if color.alphaComponent > 0.98 { solidText = true }
                if color.alphaComponent < 0.01 { clearBackground = true }
            }
        } }
        checks["transparentWindowKeepsTextOpaque"] = solidText && (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || clearBackground)
        config.window.frosted = true; config.window.frostIntensity = 0.35; view.apply(config)
        checks["frostUsesNativeBehindWindowMaterial"] = view.frost.isHidden == !config.usesFrosting && view.frost.blendingMode == .behindWindow && view.frost.material == .underWindowBackground && abs(view.frost.alphaValue-0.35) < 0.001 && abs(Double(view.backgroundOpacity)-Double(config.windowBackgroundOpacity)) < 0.001
        config.window.opacity = 1; view.apply(config)
        checks["windowOpacityCanReturnToSolid"] = view.backgroundOpacity == 1
        var invalid = config; invalid.window.opacity = 1.5
        do { try invalid.validate(); checks["invalidWindowOpacityRejected"] = false } catch { checks["invalidWindowOpacityRejected"] = true }
        let folder = Configuration.url.deletingLastPathComponent().appendingPathComponent("glass-config.toml")
        config.window.opacity = 0.85
        do {
            try Configuration.save(config, to: folder); let loaded = try Configuration.load(from: folder)
            checks["windowGlassConfigRoundTrips"] = loaded.window.opacity == 0.85 && loaded.window.frosted && loaded.window.frostIntensity == 0.35
        } catch { checks["windowGlassConfigRoundTrips"] = false }
    }

    static func navigationChecks(app: App, into checks: inout [String: Bool]) {
        let controller = TerminalWindowController(application: app)
        app.windows.append(controller)
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        defer { controller.stop(); controller.window?.close(); app.windows.first?.window?.makeKeyAndOrderFront(nil) }
        controller.newTab(nil); controller.newTab(nil); controller.selectTab(at: 1)
        let original = controller.workspaces, selected = controller.workspace
        let pids = original.map { $0.active.terminal.process.shellPid }
        checks["tabReorderPreservesSessionsAndSelection"] = controller.moveTab(id: original[0].id, toInsertionIndex: 3) && controller.workspaces.map(\.id) == [original[1].id, original[2].id, original[0].id] && controller.workspace === selected && original.map { $0.active.terminal.process.shellPid } == pids
        controller.moveActiveTab(by: 1)
        checks["keyboardTabReorder"] = controller.index == 1 && controller.workspace === selected
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        pasteboard.setString(UUID().uuidString, forType: .mothTab)
        checks["tabReorderRejectsForeignWindow"] = controller.tabs.tabID(from: pasteboard) == nil && !controller.moveTab(id: UUID(), toInsertionIndex: 0)
        pasteboard.setString(selected.id.uuidString, forType: .mothTab)
        checks["tabDragIdentifiesSession"] = controller.tabs.tabID(from: pasteboard) == selected.id
        let pane = controller.workspace.active!, terminal = pane.terminal
        terminal.feed(text: "\u{1b}c" + (0..<90).map { "log \($0)\r\n" }.joined() + "needle one\r\nNEEDLE two\r\n界 e\u{301} 👩‍💻\r\n")
        focusForKeyboardTest(controller)
        controller.pendingInitialFocus = true; controller.showFind()
        let searchResponder = controller.window?.firstResponder
        controller.finishInitialFocus()
        checks["recoveryFocusDoesNotStealSearchInput"] = !controller.pendingInitialFocus && searchResponder is NSTextView && controller.window?.firstResponder === searchResponder
        controller.hideFind()
        let commandF = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
        let findHandled = NSApp.mainMenu?.performKeyEquivalent(with:commandF) == true
        checks["commandFShowsNativeFind"] = findHandled && !controller.findBar.isHidden
        if !findHandled || controller.findBar.isHidden { print("Find dispatch:",findHandled,"active app:",NSApp.isActive,"key:",String(describing:NSApp.keyWindow?.windowController),"expected key:",controller.window?.isKeyWindow == true,"target:",app.active === controller) }
        controller.findBar.field.stringValue = "needle"; controller.refreshSearch()
        checks["findSelectsCopyableScrollbackMatch"] = controller.searchMatches.count == 2 && terminal.getSelection() == "needle"
        controller.stepFind(1)
        checks["findNextAndWrap"] = controller.searchIndex == 1 && terminal.getSelection() == "NEEDLE"
        controller.stepFind(1); checks["findNextAndWrap"] = checks["findNextAndWrap"] == true && controller.searchIndex == 0
        controller.stepFind(-1); checks["findPreviousWraps"] = controller.searchIndex == 1
        controller.findBar.matchCase.state = .on; controller.refreshSearch()
        checks["findMatchCase"] = controller.searchMatches.count == 1
        controller.findBar.field.stringValue = "👩‍💻"; controller.refreshSearch()
        checks["findUnicodeSelection"] = terminal.getSelection() == "👩‍💻"
        controller.findBar.regex.state = .on; controller.findBar.field.stringValue = "log [0-9]+"; controller.refreshSearch()
        checks["findBarRegexHighlightsActualTerminalText"] = !controller.searchMatches.isEmpty && terminal.getSelection()?.hasPrefix("log ") == true
        controller.findBar.field.stringValue = "["; controller.refreshSearch()
        checks["findBarShowsInvalidRegexInline"] = controller.findBar.count.stringValue == "Invalid regex" && controller.searchMatches.isEmpty
        controller.findBar.regex.state = .off
        controller.findBar.field.stringValue = "needle"; controller.findBar.matchCase.state = .off; controller.refreshSearch()
        controller.workspace.split(vertical: true, config: app.config)
        controller.refreshFooter()
        checks["findFollowsActiveSplit"] = controller.searchMatches.isEmpty
        controller.window?.makeFirstResponder(pane.terminal)
        checks["findReturnsToOriginalSplit"] = controller.searchMatches.count == 2
        controller.showFind(); controller.findBar.field.stringValue = "needle"; controller.refreshSearch()
        capturePreview(controller.content, name: "SearchPreview.png")
        controller.hideFind()
        checks["findDismissRestoresTerminalFocus"] = controller.findBar.isHidden && controller.window?.firstResponder === pane.terminal
        let history = terminal.getTerminal().find("log 0").matches.first
        checks["findRevealsOldHistory"] = history.map { terminal.revealSearchMatch($0) && terminal.getSelection() == "log 0" } ?? false
        terminal.getTerminal().changeHistorySize(1)
        checks["findRejectsEvictedMatch"] = history.map { !terminal.revealSearchMatch($0) } ?? false
        checks["compiledAppIcon"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "Moth" && Bundle.main.url(forResource: "Moth", withExtension: "icns") != nil
    }

    static func powerlineCellAlignment() -> Bool {
        var passed = true
        for size in [11.0, 14.0, 20.0] {
            var config = Configuration(); config.fontSize = size; config.background.style = "solid"
            config.palette = Configuration.Palette(background: "000000", foreground: "FFFFFF", accent: "FFFFFF")
            let pane = Pane(config: config, start: false)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = pane; window.orderFront(nil); pane.layoutSubtreeIfNeeded()
            pane.terminal.feed(text: "\r\n\u{1b}[38;2;50;100;255m\u{e0b0}\u{e0b2}\u{e0b4}\u{e0b6}\u{1b}[0m")
            guard let bitmap = pane.terminal.bitmapImageRepForCachingDisplay(in: pane.terminal.bounds) else { passed = false; continue }
            pane.terminal.cacheDisplay(in: pane.terminal.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsHigh)/pane.terminal.bounds.height
            let font = pane.terminal.font as CTFont
            let height = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
            let first = Int(height*scale), last = Int(height*2*scale)
            var count = 0, top = false, bottom = false, overhang = false
            for y in 0..<min(bitmap.pixelsHigh, last+4) {
                for x in 0..<min(bitmap.pixelsWide, 100) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.blueComponent > color.redComponent+0.3 && color.blueComponent > color.greenComponent+0.1 {
                        count += 1
                        if y < first || y >= last { overhang = true }
                        if y <= first+1 { top = true }
                        if y >= last-2 { bottom = true }
                    }
                }
            }
            passed = passed && count > 20 && top && bottom && !overhang
            if size == 14, let png = bitmap.representation(using: .png, properties: [:]) {
                let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
                try? png.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("PowerlineProbe.png"))
            }
            window.orderOut(nil)
        }
        return passed
    }

    static func makeBitmap(for view: NSView) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width*2), pixelsHigh: Int(view.bounds.height*2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow*bitmap.pixelsHigh)
        return bitmap
    }
    static func draw(_ terminal: ShellView, into bitmap: NSBitmapImageRep) {
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        terminal.draw(terminal.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    static func transparentRedrawMatchesFreshFrame() -> Bool {
        let terminal = ShellView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        terminal.font = NSFont(name: Configuration().fontName, size: 14)!
        terminal.nativeBackgroundColor = .clear
        let reused = makeBitmap(for: terminal)
        terminal.feed(text: "MMMMMMMM\r\n\u{1b}[32m88888888\u{1b}[0m")
        draw(terminal, into: reused)
        terminal.feed(text: "\u{1b}[2J\u{1b}[HI")
        draw(terminal, into: reused)
        let fresh = makeBitmap(for: terminal)
        draw(terminal, into: fresh)
        let count = fresh.bytesPerRow*fresh.pixelsHigh
        return Data(bytes: reused.bitmapData!, count: count) == Data(bytes: fresh.bitmapData!, count: count)
    }
    static func textRunsStayOnGrid() -> Bool {
        let terminal = ShellView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        terminal.font = NSFont(name: Configuration().fontName, size: 14)!
        terminal.nativeBackgroundColor = .black
        let font = terminal.font
        let width = font.advancement(forGlyph: font.glyph(withName: "W")).width
        for prefix in ["fi", "ffi", "==>", "->", "e\u{301}", "界", "👩‍💻"] {
            terminal.feed(text: "\u{1b}[2J\u{1b}[H\u{1b}[0m" + prefix + "\u{1b}[38;2;255;0;255mX\u{1b}[0m")
            guard let column = (0..<30).first(where: { terminal.getTerminal().getCharacter(col: $0, row: 0) == "X" }) else { return false }
            let bitmap = makeBitmap(for: terminal); draw(terminal, into: bitmap)
            var xs: [Int] = []
            for y in 0..<min(80, bitmap.pixelsHigh) {
                for x in 0..<min(180, bitmap.pixelsWide) {
                    if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > 0.7, c.greenComponent < 0.25, c.blueComponent > 0.7, c.alphaComponent > 0.5 { xs.append(x) }
                }
            }
            guard let minX = xs.min(), let maxX = xs.max(), CGFloat(minX) >= CGFloat(column)*width*2-1, CGFloat(maxX) < CGFloat(column+1)*width*2+1 else {
                print("Grid mismatch: prefix=\(prefix.debugDescription) column=\(column) width=\(width) pixels=\(String(describing: xs.min()))...\(String(describing: xs.max()))")
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
                    try? png.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("TextLayoutFailure.png"))
                }
                return false
            }
        }
        terminal.feed(text: "\u{1b}[2J\u{1b}[H==> Downloading https://example.test/office/file\r\nVerified 429.9KB / 429.9KB\r\nSoftware Update: fi ffi ==> ->\r\n")
        let bitmap = makeBitmap(for: terminal); draw(terminal, into: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
            try? png.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("TextLayoutProbe.png"))
        }
        return true
    }
    static func boxDrawingUsesSameGridAsText() -> Bool {
        let terminal = ShellView(frame: NSRect(x: 0, y: 0, width: 1300, height: 100))
        terminal.font = NSFont(name: Configuration().fontName, size: 14)!
        terminal.nativeBackgroundColor = .black; terminal.nativeForegroundColor = .white
        terminal.feed(text: "\u{1b}[1;101H│")
        let bitmap = makeBitmap(for: terminal); draw(terminal, into: bitmap)
        var pixels: [Int] = []
        for y in 0..<80 {
            for x in 0..<bitmap.pixelsWide {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > 0.7, c.greenComponent > 0.7, c.blueComponent > 0.7 { pixels.append(x) }
            }
        }
        guard !pixels.isEmpty else { return false }
        let width = terminal.font.advancement(forGlyph: terminal.font.glyph(withName: "W")).width
        let expected = (100.5 * width) * 2
        let actual = Double(pixels.reduce(0, +))/Double(pixels.count)
        return abs(actual - expected) < 2
    }
    static func manualChecks(into checks: inout [String: Bool]) {
        checks["manualReferencesKeepSections"] = ManualReference(" printf(3) ")?.query == "printf(3)"
        checks["manualReferencesRejectShellInput"] = ["-a","/tmp/file","ls;touch /tmp/no","$(id)","ls\nwhoami","a b","foo(0)",String(repeating:"x",count:129)].allSatisfy { ManualReference($0) == nil }
        checks["manualLinksPreserveSection"] = ManualReference.link(URL(string:"moth-man:printf(3)")!)?.query == "printf(3)"
        checks["manualLinksRejectExternalURLs"] = ManualReference.link(URL(string:"https://example.com")!) == nil
        do {
            let html = try ManualPages.load(ManualReference("ls(1)")!).html
            checks["manualRendersLocalPageAndSeeAlso"] = html.contains("list directory contents") && html.contains("moth-man:chmod(1)")
            checks["manualHTMLBlocksExternalResources"] = html.contains("default-src 'none'")
        } catch { checks["manualRendersLocalPageAndSeeAlso"] = false }
        var config = Configuration(); config.lookup.forceClickAction = "manual"; config.lookup.manualPresentation = "window"; config.lookup.commandClickManual = false
        do {
            let decoded = try TOMLDecoder().decode(Configuration.self,from:Configuration.document(config))
            checks["manualSettingsRoundTrip"] = decoded.lookup.forceClickAction == "manual" && decoded.lookup.manualPresentation == "window" && !decoded.lookup.commandClickManual
        } catch { checks["manualSettingsRoundTrip"] = false }
        do {
            var old = Configuration(); old.keybindings.removeValue(forKey:"openManualPage")
            let upgraded = try TOMLDecoder().decode(Configuration.self,from:Configuration.document(old))
            checks["manualShortcutUpgradesExistingConfiguration"] = upgraded.keybindings["openManualPage"] == "cmd+ctrl+m"
            var macro = Configuration.Macro(); macro.text = "hello"; macro.shortcut = "ctrl+cmd+m"; old.macros["Existing"] = macro
            let retained = try TOMLDecoder().decode(Configuration.self,from:Configuration.document(old))
            checks["manualShortcutUpgradePreservesExistingMacro"] = retained.keybindings["openManualPage"] == "" && retained.macros["Existing"]?.shortcut == "ctrl+cmd+m"
        } catch { checks["manualShortcutUpgradesExistingConfiguration"] = false }
        config.lookup.forceClickAction = "invalid"
        checks["manualSettingsRejectUnknownActions"] = (try? config.validate()) == nil
        let terminal = DefinitionCaptureView(frame:NSRect(x:0,y:0,width:600,height:200)); terminal.feed(text:"ls")
        _ = terminal.revealSearchMatch(terminal.getTerminal().find("ls").matches.first!)
        let point = terminal.definitionTarget()!.baselineOrigin
        terminal.lookup.forceClickAction = "off"; terminal.performLookupGesture(at:point)
        checks["forceClickOffSuppressesLookup"] = terminal.manuals.isEmpty && terminal.definitions.isEmpty
        terminal.lookup.forceClickAction = "manual"; terminal.performLookupGesture(at:point)
        checks["forceClickManualUsesLocalViewer"] = terminal.manuals == ["ls"] && terminal.definitions.isEmpty && terminal.sent.isEmpty
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.control],timestamp:0,windowNumber:0,context:nil,characters:"m",charactersIgnoringModifiers:"m",isARepeat:false,keyCode:46)!
        terminal.keyDown(with:event)
        checks["manualShortcutPreservesSelectionAndPTY"] = terminal.manuals == ["ls","ls"] && terminal.getSelection() == "ls" && terminal.sent.isEmpty
        terminal.manualShortcut = ""
        terminal.lookup.forceClickAction = "definition"; terminal.performLookupGesture(at:point)
        checks["forceClickDefinitionRemainsAvailable"] = terminal.definitions == ["ls"]
        let down = NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        let up = NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        terminal.mouseDown(with:down); terminal.mouseUp(with:up)
        checks["commandClickManualDoesNotType"] = terminal.manuals.count == 3 && terminal.sent.isEmpty
        let ids = [UUID().uuidString,UUID().uuidString,UUID().uuidString]
        let legacy = SavedTab(root:.split(vertical:true,fraction:0.4,first:.manual("ls"),second:.split(vertical:false,fraction:0.5,first:.pane,second:.pane)),activePane:2,sessions:ids)
        if let retained = legacy.removingManualPanes() {
            checks["manualPreviewMigrationKeepsTerminalSessions"] = retained.root.paneCount == 2 && retained.sessions == Array(ids.dropFirst()) && retained.activePane == 1
            let restored = Workspace(config:Configuration(),startProcesses:false,saved:legacy)
            checks["manualPreviewLayoutRestoresOnlyTerminals"] = restored.panes.count == 2 && restored.panes.allSatisfy { !$0.terminal.isHidden }
            restored.stop()
        } else { checks["manualPreviewMigrationKeepsTerminalSessions"] = false }
        checks["manualOnlyPreviewLayoutIsRemoved"] = SavedTab(root:.manual("ls"),activePane:0).removingManualPanes() == nil
        do {
            var old = Configuration(); old.lookup.manualPresentation = "split"
            let updated = try TOMLDecoder().decode(Configuration.self,from:Configuration.document(old))
            checks["manualSplitPreferenceMigratesToWindow"] = updated.lookup.manualPresentation == "window"
        } catch { checks["manualSplitPreferenceMigratesToWindow"] = false }
    }
    static func definitionChecks(into checks: inout [String: Bool]) {
        let terminal = DefinitionCaptureView(frame:NSRect(x:0,y:0,width:600,height:200))
        terminal.feed(text:"hello world")
        let match = terminal.getTerminal().find("hello").matches.first!
        _ = terminal.revealSearchMatch(match)
        let target = terminal.definitionTarget()
        checks["definitionUsesSelectedText"] = target?.text.string == "hello" && terminal.bounds.contains(target!.baselineOrigin)
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.control],timestamp:0,windowNumber:0,context:nil,characters:"d",charactersIgnoringModifiers:"d",isARepeat:false,keyCode:2)!
        terminal.keyDown(with:event)
        checks["definitionShortcutPreservesSelectionAndPTY"] = terminal.definitions == ["hello"] && terminal.getSelection() == "hello" && terminal.sent.isEmpty
        terminal.readOnly = true; terminal.keyDown(with:event)
        checks["definitionWorksInReadOnlyTerminal"] = terminal.definitions == ["hello","hello"] && terminal.sent.isEmpty
        terminal.selectNone()
        checks["definitionWithoutSelectionIsEmpty"] = terminal.definitionTarget() == nil
        if let origin = target?.baselineOrigin {
            let point = NSPoint(x:origin.x+1,y:origin.y+1)
            let click = NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:0)!
            let menu = terminal.menu(for:click)
            let lookup = menu?.items.first { $0.action == #selector(ShellView.lookUpSelection(_:)) }
            checks["definitionContextMenuSelectsWord"] = lookup?.isEnabled == true && terminal.getSelection() == "hello"
            terminal.quickLook(with:click)
            checks["definitionGestureUsesNativePresentation"] = terminal.definitions.last == "hello" && terminal.sent.isEmpty
        }
    }

    static func fileDropChecks(into checks: inout [String: Bool]) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let paths = ["/tmp/Moth file.txt", "/tmp/it's $special;$(echo NO).txt", "/tmp/日本語 folder", "/tmp/line\nbreak\t\u{1b}.txt"]
        board.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
        let text = ShellView.fileDropText(from: board) ?? ""
        checks["fileDropReadsMultipleURLs"] = ShellView.fileURLs(from: board).map(\.path) == paths
        checks["fileDropNoControlKeysOrEnter"] = !text.isEmpty && !text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-fc", "printf '%s\\0' " + text]
        process.standardOutput = pipe
        do {
            try process.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            checks["fileDropShellQuoting"] = process.terminationStatus == 0 && output == Data((paths.joined(separator: "\0") + "\0").utf8)
        } catch { checks["fileDropShellQuoting"] = false }
        let capture = DropCaptureView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        capture.feed(text: "\u{1b}[?2004h")
        checks["fileDropUsesBracketedPaste"] = capture.insertFileDrop(from: board) && String(bytes: capture.sent, encoding: .utf8) == "\u{1b}[200~" + text + "\u{1b}[201~"
        board.clearContents(); board.setString("ordinary text", forType: .string)
        checks["fileDropRejectsNonFileText"] = ShellView.fileDropText(from: board) == nil
    }

    final class FullScreenChecks {
        var results: [String: Bool] = [:]
        var panes: [Pane] = []
        func stop() { panes.forEach { $0.stop() } }
    }
    static func startGNUScreenChecks() -> FullScreenChecks {
        let suite = FullScreenChecks()
        let pane = Pane(config: Configuration(), start: false)
        suite.panes = [pane]
        let view = pane.terminal
        let terminal = view.getTerminal()
        let environment = ShellEnvironment.session(inherited: [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin"
        ]).map { "\($0.key)=\($0.value)" }
        let command = """
        read -r start
        /usr/bin/screen -c /dev/null -q /bin/sh -c 'printf "MOTH_SCREEN_IN="; stty size; echo MOTH_SCREEN_READY; read -r stop'
        printf 'MOTH_SCREEN_OUT='; stty size
        read -r finish
        """
        view.startProcess(executable: "/bin/sh", args: ["-c", command], environment: environment)
        view.setFrameSize(NSSize(width: 1000, height: 550))
        let cols = terminal.cols, rows = terminal.rows
        let dimensions = "\(cols) × \(rows)"
        let validSize = cols != 80 && cols != 132 && pane.dimensions.stringValue == dimensions
        suite.results["gnuScreenStartsAtPaneSize"] = false
        suite.results["gnuScreenExitPreservesPaneAndPTYSize"] = false
        func outputContains(_ text: String) -> Bool { terminal.exportPlainText().contains(text) }
        func hasOriginalSize() -> Bool {
            validSize && terminal.cols == cols && terminal.rows == rows && pane.dimensions.stringValue == dimensions
        }
        view.send(txt: "start\r")
        waitFor({ outputContains("MOTH_SCREEN_READY") }, timeout: 1.4) { started in
            suite.results["gnuScreenStartsAtPaneSize"] = started && hasOriginalSize() &&
                outputContains("MOTH_SCREEN_IN=\(rows) \(cols)")
            if suite.results["gnuScreenStartsAtPaneSize"] != true {
                print("GNU Screen start diagnostic:", "expected", dimensions, "actual", terminal.cols, terminal.rows, "label", pane.dimensions.stringValue, "valid", validSize, "output", terminal.exportPlainText())
            }
            guard started else { return }
            view.send(txt: "stop\r")
            waitFor({ outputContains("MOTH_SCREEN_OUT=\(rows) \(cols)") }, timeout: 1.4) { restored in
                suite.results["gnuScreenExitPreservesPaneAndPTYSize"] = restored && hasOriginalSize()
                view.send(txt: "finish\r")
            }
        }
        return suite
    }

    static func startFullScreenChecks() -> FullScreenChecks {
        let suite = FullScreenChecks()
        let folder = Configuration.url.deletingLastPathComponent()
        let vimFile = folder.appendingPathComponent("vim-probe.txt"), lessFile = folder.appendingPathComponent("less-probe.txt")
        try! Data("MOTH_VIM_FIXTURE\n".utf8).write(to: vimFile)
        try! Data((0..<250).map { "MOTH_PAGER_LINE_\($0)\n" }.joined().utf8).write(to: lessFile)
        let vim = Pane(config: Configuration(), start: false), less = Pane(config: Configuration(), start: false)
        suite.panes = [vim, less]
        let environment = ShellEnvironment.session().map { "\($0.key)=\($0.value)" }
        vim.terminal.startProcess(executable: "/usr/bin/vim", args: ["-Nu", "NONE", "-n", "-i", "NONE", "-N", vimFile.path], environment: environment)
        less.terminal.startProcess(executable: "/usr/bin/less", args: ["-R", lessFile.path], environment: environment)
        func text(_ pane: Pane) -> String { let t = pane.terminal.getTerminal(); return (0..<t.rows).compactMap { t.getLine(row: $0)?.translateToString(trimRight: true) }.joined(separator: "\n") }
        func awaitInitialFrame(_ attempts: Int) {
            if attempts > 0 && (!vim.terminal.getTerminal().isCurrentBufferAlternate || !text(vim).contains("MOTH_VIM_FIXTURE") || !text(less).contains("MOTH_PAGER_LINE_0")) {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { awaitInitialFrame(attempts-1) }; return
            }
            suite.results["vimUsesAlternateScreen"] = vim.terminal.getTerminal().isCurrentBufferAlternate && text(vim).contains("MOTH_VIM_FIXTURE")
            suite.results["lessDisplaysPTYOutput"] = text(less).contains("MOTH_PAGER_LINE_0")
            vim.terminal.frame.size = NSSize(width: 570, height: 320)
            vim.terminal.send(txt: "gg0iEDITED_\u{1b}:wq\r")
            less.terminal.send(txt: "G")
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { awaitInitialFrame(20) }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.8) {
            suite.results["lessNavigatesToEnd"] = text(less).contains("MOTH_PAGER_LINE_249")
            less.terminal.send(txt: "q")
            suite.results["vimKeyboardInputSavesFile"] = (try? String(contentsOf: vimFile, encoding: .utf8)) == "EDITED_MOTH_VIM_FIXTURE\n"
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+2.7) {
            suite.results["vimAndLessExitCleanly"] = !vim.terminal.process.running && !less.terminal.process.running
        }
        return suite
    }

    static func colourCount(_ pane: Pane) -> Int {
        let terminal = pane.terminal.getTerminal()
        var colors = Set<String>()
        for row in 0..<terminal.rows { for col in 0..<terminal.cols {
            if let cell = terminal.getCharData(col: col, row: row), cell.getCharacter() != " " {
                let color = cell.attribute.fg
                if color != .defaultColor && color != .defaultInvertedColor { colors.insert(String(describing: color)) }
            }
        } }
        return colors.count
    }
    static func startMonitorCheck(program: String = "btm") -> (NSWindow, Pane)? {
        let candidates = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/\(program)").path, "/opt/homebrew/bin/\(program)"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let config = Configuration()
        let root = FlowBackgroundView(frame: .zero), pane = Pane(config: config, start: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 720), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentView = root; root.apply(config)
        root.addSubview(pane); pane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pane.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor), pane.leadingAnchor.constraint(equalTo: root.leadingAnchor), pane.trailingAnchor.constraint(equalTo: root.trailingAnchor), pane.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
        window.orderFront(nil); root.layoutSubtreeIfNeeded()
        let path = Configuration.url.deletingLastPathComponent().appendingPathComponent("bottom.toml")
        let environment = ShellEnvironment.session()
        pane.terminal.startProcess(executable: executable, args: program == "btm" ? ["--config_location", path.path] : [], environment: environment.map { "\($0.key)=\($0.value)" })
        return (window, pane)
    }
    static func capturePreview(_ view: NSView, name: String) {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); view.layer?.displayIfNeeded()
        let bitmap = makeBitmap(for: view)
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        context.cgContext.scaleBy(x: 2, y: 2)
        view.layer?.render(in: context.cgContext)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
            try? png.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(name))
        }
    }

    static func cursorChecks(into checks: inout [String: Bool]) {
        var config = Configuration()
        let pane = Pane(config: config, start: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = pane; window.makeKeyAndOrderFront(nil); pane.layoutSubtreeIfNeeded()
        window.makeFirstResponder(pane.terminal)
        pane.terminal.caretViewTracksFocus = false
        guard let caret = pane.terminal.subviews.first(where: { String(describing: type(of: $0)) == "CaretView" }) else { checks["cursorViewExists"] = false; return }
        for shape in ["block", "underline", "bar"] {
            for motion in ["blink", "breathe", "noblink"] {
                config.cursor.shape = shape; config.cursor.animation = motion
                pane.apply(config)
                caret.displayIfNeeded(); caret.layer?.displayIfNeeded()
                let animation = caret.layer?.animation(forKey: "opacity")
                let expectedAnimation: Bool
                if motion == "noblink" || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { expectedAnimation = animation == nil }
                else if motion == "blink" { expectedAnimation = (animation as? CAKeyframeAnimation)?.calculationMode == .discrete }
                else { expectedAnimation = (animation as? CABasicAnimation)?.autoreverses == true }
                let bitmap = makeBitmap(for: caret)
                let drawing = NSGraphicsContext(bitmapImageRep: bitmap)!
                drawing.cgContext.scaleBy(x: 2, y: 2)
                if let layer = caret.layer { (caret as? CALayerDelegate)?.draw?(layer, in: drawing.cgContext) }
                var xs: [Int] = [], ys: [Int] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { xs.append(x); ys.append(y) }
                    }
                }
                let width = (xs.max() ?? -1) - (xs.min() ?? 0) + 1
                let height = (ys.max() ?? -1) - (ys.min() ?? 0) + 1
                let expectedShape: Bool
                switch shape {
                case "underline": expectedShape = width >= bitmap.pixelsWide-2 && (1...5).contains(height)
                case "bar": expectedShape = height >= bitmap.pixelsHigh-2 && (1...5).contains(width)
                default: expectedShape = width >= bitmap.pixelsWide-2 && height >= bitmap.pixelsHigh-2
                }
                checks["cursor_\(shape)_\(motion)"] = expectedAnimation && expectedShape
                if !expectedAnimation || !expectedShape { print("Cursor \(shape)/\(motion): animation=\(expectedAnimation), pixels=\(width)x\(height), bounds=\(caret.bounds)") }
            }
        }
        pane.terminal.caretViewTracksFocus = true
        window.makeFirstResponder(nil)
        checks["cursorStopsWhenUnfocused"] = caret.layer?.animation(forKey: "opacity") == nil
        window.orderOut(nil)
    }
    static func configurationExpansionChecks(into checks: inout [String: Bool]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moth-config-expansion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.toml"), legacy = folder.appendingPathComponent("config.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let old: [String: Any] = ["fontSize": 17, "theme": "forest", "window": ["borderColor": "123456"], "extraSetting": ["keep": true], "_help": ["old": "remove me"]]
            let oldData = try JSONSerialization.data(withJSONObject: old)
            try oldData.write(to: legacy)
            let config = try Configuration.expandFile(at: url)
            var text = try String(contentsOf: url)
            var table = try TOMLTable(string: text)
            checks["jsonMigratesToCommentedTOML"] = table["cursor"] != nil && table["background"] != nil && text.contains("# shape:") && table["_help"] == nil
            checks["jsonMigrationBacksUpOriginal"] = try Data(contentsOf: legacy.appendingPathExtension("before-toml")) == oldData
            checks["configExpansionPreservesPreferences"] = config.fontSize == 17 && config.theme == "forest" && config.window.borderColor == "123456" && table["extraSetting"]?["keep"]?.bool == true
            text = text.replacingOccurrences(of: "fontSize = 17", with: "fontSize = 17 # my font size π")
            text += "\n# My hand-written notes: 日本語\n[customNotes]\ntext = \"Keep # inside strings\" # trailing note\nitems = [\n  \"one\", # array note\n  \"two\"\n]\n"
            try Data(text.utf8).write(to: url)
            var changed = config; changed.cursor.shape = "bar"; changed.fontSize = 18
            try Configuration.save(changed, to: url)
            let saved = try String(contentsOf: url)
            table = try TOMLTable(string: saved)
            checks["tomlSavePreservesComments"] = saved.contains("# my font size π") && saved.contains("# My hand-written notes: 日本語") && saved.contains("# array note") && saved.contains("# trailing note")
            checks["configSavePreservesUnknownFields"] = table["extraSetting"]?["keep"]?.bool == true && table["customNotes"]?["text"]?.string == "Keep # inside strings"
            checks["tomlMenuChangesUpdateValues"] = try Configuration.load(from: url).fontSize == 18 && Configuration.load(from: url).cursor.shape == "bar"
            try Data("cursor.shape = 'bar' # dotted note\n".utf8).write(to: url)
            _ = try Configuration.expandFile(at: url)
            checks["tomlDottedKeysSupported"] = try Configuration.load(from: url).cursor.shape == "bar"
            try Data("cursor = { shape = 'underline', animation = 'blink' } # inline note\n".utf8).write(to: url)
            var inline = try Configuration.load(from: url); inline.cursor.animation = "noblink"
            try Configuration.save(inline, to: url)
            checks["tomlInlineTablesSupported"] = try String(contentsOf: url).contains("# inline note") && Configuration.load(from: url).cursor.animation == "noblink"
            let malformed = Data("[cursor\n".utf8)
            try malformed.write(to: url)
            do { try Configuration.expandFile(at: url); checks["invalidConfigNotRewritten"] = false }
            catch { checks["invalidConfigNotRewritten"] = try Data(contentsOf: url) == malformed }
            var bad = config; bad.cursor.animation = "flicker"
            do { try bad.validate(); checks["invalidCursorRejected"] = false }
            catch { checks["invalidCursorRejected"] = true }
        } catch { checks["configExpansionChecks"] = false; print("TOML test error:", error) }
    }

    static func backgroundGallery() {
        let names = ["flow", "solid"]
        let width: CGFloat = 320, height: CGFloat = 210, scale: CGFloat = 2
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width*4*scale), pixelsHigh: Int(height*3*scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor.hex(0x0B0D12).cgColor); context.fill(CGRect(x: 0, y: 0, width: width*4, height: height*3))
        for (index, name) in names.enumerated() {
            var config = Configuration(); config.background.style = name
            let view = FlowBackgroundView(frame: NSRect(x: 0, y: 0, width: width-16, height: height-40)); view.apply(config)
            let x = CGFloat(index%4)*width+8, y = CGFloat(2-index/4)*height+30
            context.saveGState(); context.translateBy(x: x, y: y); view.layer?.render(in: context); context.restoreGState()
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: name.capitalized, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.hex(0xDFE4EF)]))
            context.textPosition = CGPoint(x: x+6, y: y-18); CTLineDraw(line, context)
        }
        if let data = bitmap.representation(using: .png, properties: [:]) {
            let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
            try? data.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("BackgroundsPreview.png"))
        }
    }
    static func closePolicyChecks(into checks: inout [String: Bool]) {
        var policy = Configuration.CloseConfirmation()
        let shell = RunningProgram(pid: 1, path: "/bin/zsh"), vim = RunningProgram(pid: 2, path: "/usr/bin/vim")
        checks["idleShellSkipsConfirmation"] = CloseAssessment(programs: [shell]).requiringConfirmation(policy).isEmpty
        checks["unlistedProgramRequiresConfirmation"] = CloseAssessment(programs: [shell, vim]).requiringConfirmation(policy) == ["vim"]
        policy.ignorePrograms.append("vim")
        checks["explicitProgramExceptionWorks"] = CloseAssessment(programs: [shell, vim]).requiringConfirmation(policy).isEmpty
        policy.ignorePrograms = ["/usr/bin/vim"]
        checks["exceptionsCanMatchExactPaths"] = CloseAssessment(programs: [vim]).requiringConfirmation(policy).isEmpty && !CloseAssessment(programs: [RunningProgram(pid: 3, path: "/tmp/vim")]).requiringConfirmation(policy).isEmpty
        checks["unknownProcessesStillRequireConfirmation"] = !CloseAssessment(uncertain: true).requiringConfirmation(policy).isEmpty
        policy.enabled = false
        checks["confirmationCanBeDisabled"] = CloseAssessment(programs: [vim], uncertain: true).requiringConfirmation(policy).isEmpty
    }

    static func sampleOpacity(_ layer: CALayer, count: Int, completion: @escaping ([Float]) -> Void) {
        var values: [Float] = []
        func tick(_ remaining: Int) {
            values.append(layer.presentation()?.opacity ?? layer.opacity)
            guard remaining > 1 else { completion(values); return }
            DispatchQueue.main.asyncAfter(deadline: .now()+0.08) { tick(remaining-1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.05) { tick(count) }
    }
    static func runningCursorChecks(app: App, controller: TerminalWindowController, completion: @escaping ([String: Bool]) -> Void) {
        activateValidationApp()
        let terminal = controller.workspace.active.terminal
        guard let caret = terminal.subviews.first(where: { String(describing: type(of: $0)) == "CaretView" }), let layer = caret.layer else { completion(["cursorPresentationExists": false]); return }
        var results: [String: Bool] = [:], measurements: [String: [Float]] = [:]
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        func focus(_ target: TerminalWindowController, then action: @escaping () -> Void) {
            NSApp.activate(ignoringOtherApps: true); target.window?.makeKeyAndOrderFront(nil)
            target.window?.makeFirstResponder(target.workspace.active.terminal)
            func settled(_ remaining: Int) {
                let view = target.workspace.active.terminal
                if NSApp.isActive && target.window?.isKeyWindow == true && target.window?.firstResponder === view && view.hasFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.05, execute: action)
                } else if remaining > 0 {
                    NSApp.activate(ignoringOtherApps: true); target.window?.makeKeyAndOrderFront(nil)
                    target.window?.makeFirstResponder(view)
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { settled(remaining-1) }
                } else {
                    print("Cursor focus did not settle: app=\(NSApp.isActive), key=\(target.window?.isKeyWindow ?? false), terminal=\(view.hasFocus)")
                    action()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { settled(15) }
        }

        func measureBlink() {
            app.config.cursor.shape = "bar"; app.config.cursor.animation = "blink"; app.config.cursor.period = 0.6
            try! Configuration.save(app.config); app.applyAppearance()
            focus(controller) {
            terminal.configureCursor(shape: "bar", animation: "blink", period: 0.6)
            sampleOpacity(layer, count: 12) { blink in
                measurements["blink"] = blink
                results["cursorBlinkChangesOnScreen"] = reduceMotion || (blink.contains { $0 < 0.1 } && blink.contains { $0 > 0.9 })
                terminal.configureCursor(shape: "bar", animation: "noblink", period: 0.6)
                sampleOpacity(layer, count: 4) { steady in
                    measurements["noblink"] = steady
                    results["cursorNoBlinkStaysVisible"] = layer.animation(forKey: "opacity") == nil && steady.allSatisfy { $0 > 0.99 }
                    let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-test-results.json"
                    if let data = try? JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("CursorMotionSamples.json")) }
                    app.applyAppearance(); completion(results)
                }
            }
            }
        }
        focus(controller) {
            results["newWindowCursorStartsAnimating"] = reduceMotion || layer.animation(forKey: "opacity") != nil
            sampleOpacity(layer, count: 17) { breathe in
                measurements["breathe"] = breathe
                results["cursorBreatheChangesOnScreen"] = reduceMotion || (breathe.max()! - breathe.min()! > 0.2 && breathe.contains { (0.2...0.8).contains($0) })
                focus(controller) {
                    terminal.configureCursor(shape: "bar", animation: "breathe", period: 1.4)
                    if let other = app.windows.first(where: { $0 !== controller }) {
                        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: other.window)
                        results["otherWindowDoesNotStopCursor"] = reduceMotion || layer.animation(forKey: "opacity") != nil
                        focus(other) {
                            results["cursorPausesWhenWindowInactive"] = layer.animation(forKey: "opacity") == nil
                            focus(controller) {
                                results["cursorRestartsWhenWindowRefocused"] = reduceMotion || layer.animation(forKey: "opacity") != nil
                                measureBlink()
                            }
                        }
                    } else { measureBlink() }
                }
            }
        }
    }

}

final class DropCaptureView: ShellView {
    var sent: [UInt8] = []
    override func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
}

/// Real PTY tests for local directory inheritance, isolated from foreground UI timing.
private final class DirectoryInheritanceChecks {
    let app: App
    var results: [String:Bool] = [:]
    var extraWorkspaces: [Workspace] = []
    var extraWindows: [NSWindow] = []
    let root = Configuration.url.deletingLastPathComponent().appendingPathComponent("directory-fixtures")
    var configured: String { root.appendingPathComponent("configured").path }
    var source: String { root.appendingPathComponent("source 'quoted' Ω").path }
    var second: String { root.appendingPathComponent("second").path }
    init(_ app: App) { self.app = app }
    static func run(_ app: App) { let test = DirectoryInheritanceChecks(app); test.start() }
    func canonical(_ path: String?) -> String? { path.map { URL(fileURLWithPath:$0).resolvingSymlinksInPath().path } }
    func at(_ pane: Pane,_ path: String) -> Bool { canonical(pane.localWorkingDirectory) == canonical(path) }
    func wait(_ condition: @escaping () -> Bool,_ completion: @escaping (Bool) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime+5
        func poll() { if condition() { completion(true) } else if ProcessInfo.processInfo.systemUptime >= deadline { completion(false) } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.04) { poll() } } }
        poll()
    }
    func start() {
        do {
            for path in [configured,source,second] { try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true) }
            var config = Configuration(); config.shell = "/bin/sh"; config.closeOnExit = false
            config.advanced.loginShell = false; config.advanced.workingDirectory = configured
            config.advanced.environment = ["PS1":"directory-test$ ","HISTFILE":"/dev/null","BASH_ENV":"/dev/null","ENV":"/dev/null"]
            app.config = config; app.windows.forEach { $0.stop(); $0.window?.close() }; app.newWindow(nil)
            let controller = app.active!, pane = controller.workspace.active!
            wait({ self.at(pane,self.configured) && pane.terminal.getTerminal().exportPlainText().contains("directory-test$") }) { ready in
                self.results["newWindowUsesConfiguredDirectory"] = ready
                guard ready else { self.finish(); return }
                pane.terminal.send(txt:"cd "+ShellView.quotePath(self.source)+"\r")
                self.wait({ self.at(pane,self.source) }) { moved in
                    guard moved else { self.results["shellCanChangeDirectory"] = false; self.finish(); return }
                    controller.content.layoutSubtreeIfNeeded(); controller.workspace.split(vertical:true,config:controller.config)
                    let split = controller.workspace.active!
                    self.wait({ split !== pane && self.at(split,self.source) }) { inherited in
                        self.results["splitInheritsSpacesQuotesAndUnicodeDirectory"] = inherited
                        self.results["inheritingDoesNotChangeConfiguredDefaults"] = self.app.config.advanced.workingDirectory == self.configured
                        split.terminal.send(txt:"cd "+ShellView.quotePath(self.second)+"\r")
                        self.wait({ self.at(split,self.second) }) { moved in
                            guard moved else { self.results["activeSplitChangesDirectory"] = false; self.finish(); return }
                            self.checkTabs(controller)
                        }
                    }
                }
            }
        } catch { print("Directory tests:",error); results["directoryFixturesReady"] = false; finish() }
    }
    func checkTabs(_ controller: TerminalWindowController) {
        controller.newTab(nil); let tab = controller.workspace.active!
        wait({ self.at(tab,self.second) }) { inherited in
            self.results["newTabUsesActiveSplitDirectory"] = inherited
            // A remote OSC 7 update must not redirect a new local shell into /etc.
            tab.terminal.feed(text:"\u{1b}]7;file://remote.example/etc\u{1b}\\")
            controller.newTab(nil); let remote = controller.workspace.active!
            self.wait({ self.at(remote,self.second) }) { local in
                self.results["remoteDirectoryReportsDoNotOverrideLocalCWD"] = local
                self.app.config.advanced.inheritWorkingDirectory = false
                controller.newTab(nil); let fixed = controller.workspace.active!
                self.wait({ self.at(fixed,self.configured) }) { fixedDirectory in
                    self.results["inheritanceCanBeDisabled"] = fixedDirectory
                    self.app.config.advanced.inheritWorkingDirectory = true
                    fixed.stop(); controller.newTab(nil); let fallback = controller.workspace.active!
                    self.wait({ self.at(fallback,self.configured) }) { fallbackDirectory in
                        self.results["exitedSessionFallsBackToConfiguredDirectory"] = fallbackDirectory
                        self.app.newWindow(nil); let windowPane = self.app.windows.last!.workspace.active!
                        self.wait({ self.at(windowPane,self.configured) }) { newWindow in
                            self.results["newWindowsDoNotInheritOtherWindows"] = newWindow
                            self.checkRecoveredShell()
                        }
                    }
                }
            }
        }
    }
    func mount(_ workspace: Workspace) {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:650),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = workspace.root; workspace.root.layoutSubtreeIfNeeded()
        extraWindows.append(window); extraWorkspaces.append(workspace)
    }
    func checkRecoveredShell() {
        do {
            let config = app.config, first = Workspace(config:config,startProcesses:false); mount(first)
            var env = ShellEnvironment.session(); env.merge(config.advanced.environment) { _,next in next }
            let connection = try SessionRecovery.launch(shell:"/bin/sh",args:[],environment:env,directory:source,rows:24,cols:80)
            first.active.terminal.beginSession(connection)
            wait({ !first.active.terminal.replayingSession && self.at(first.active,self.source) }) { ready in
                guard ready else { self.results["helperDirectoryAvailable"] = false; self.finish(); return }
                connection.detach()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.15) {
                    do {
                        let recovered = Workspace(config:config,startProcesses:false); self.mount(recovered)
                        recovered.active.terminal.beginSession(try SessionRecovery.connect(connection.id))
                        self.wait({ !recovered.active.terminal.replayingSession && self.at(recovered.active,self.source) }) { attached in
                            self.results["recoveredShellRetainsLocalDirectory"] = attached
                            // Use the same new-session path as a normal split, with real child PTYs.
                            let child = Workspace(config:config,inheritedDirectory:recovered.active.localWorkingDirectory); self.mount(child)
                            self.wait({ self.at(child.active,self.source) }) { inherited in
                                self.results["recoveredShellDirectoryCanStartNewSessions"] = inherited
                                self.checkFallbackAndConfig()
                            }
                        }
                    } catch { print(error); self.results["recoveredShellAttaches"] = false; self.finish() }
                }
            }
        } catch { print(error); results["helperLaunches"] = false; finish() }
    }
    func checkFallbackAndConfig() {
        do {
            var config = Configuration(); config.advanced.inheritWorkingDirectory = false
            let file = root.appendingPathComponent("directory-settings.toml"); try Configuration.save(config,to:file)
            results["directoryPreferenceRoundTripsTOML"] = try Configuration.load(from:file).advanced.inheritWorkingDirectory == false
            let profile = TerminalProfile(name:"Directory fixture",configuration:config)
            try ProfileStore.save(profile,base:app.config,in:app.profileDirectory)
            app.reloadProfiles()
            let loaded = try ProfileStore.load(ProfileStore.url(profile.id,in:app.profileDirectory),base:app.config)
            results["namedProfileKeepsDirectoryPreference"] = !loaded.applying(to:app.config).advanced.inheritWorkingDirectory
            var candidate = loaded.applying(to:app.config); candidate.advanced.sessionRecovery.toggle()
            try app.saveSettings(candidate,profileID:profile.id)
            results["recoveryPreferenceSavesWhenEditingNamedProfile"] = app.config.advanced.sessionRecovery == candidate.advanced.sessionRecovery
            app.config.advanced.workingDirectory = root.appendingPathComponent("missing").path
            app.newWindow(nil); let pane = app.windows.last!.workspace.active!
            wait({ self.at(pane,FileManager.default.homeDirectoryForCurrentUser.path) }) { home in
                self.results["missingStartingDirectoryFallsBackToHome"] = home; self.finish()
            }
        } catch { print(error); results["directoryConfigurationValid"] = false; finish() }
    }
    func finish() {
        extraWorkspaces.forEach { $0.stop() }; extraWindows.forEach { $0.close() }; app.windows.forEach { $0.stop() }
        let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-directory-results.json"
        do { try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output)); print(results) } catch { print(error); exit(2) }
        exit(results.values.allSatisfy { $0 } ? 0 : 1)
    }
}

private enum TabOverflowChecks {
    static func run(_ app: App) {
        var checks: [String:Bool] = [:]
        app.windows.forEach { $0.stop(); $0.window?.close() }
        var config = Configuration(); config.shell = "/bin/sh"; config.advanced.loginShell = false
        config.advanced.environment = ["PS1":"$ ","HISTFILE":"/dev/null","ENV":"/dev/null","BASH_ENV":"/dev/null"]
        config.closeConfirmation.enabled = false; config.closeOnExit = false; config.theme = "moth-dark"
        config.window.opacity = 1; config.window.frosted = false; config.background.style = "solid"
        app.config = config; app.newWindow(nil)
        let controller = app.windows.last!, bar = controller.tabBar
        for _ in 1..<12 { controller.newTab(nil) }
        let originalPIDs = Set(controller.workspaces.flatMap(\.panes).map { $0.terminal.process.shellPid })
        func layout() {
            controller.window?.contentView?.superview?.layoutSubtreeIfNeeded()
            for accessory in controller.window?.titlebarAccessoryViewControllers ?? [] { accessory.view.layoutSubtreeIfNeeded() }
            controller.content.layoutSubtreeIfNeeded(); controller.footer.superview?.layoutSubtreeIfNeeded(); bar.layoutSubtreeIfNeeded()
        }
        func selectedVisible() -> Bool {
            guard let button = bar.buttons.first(where: { $0.workspaceID == controller.workspace.id }) else { return false }
            let visible = bar.scrollView.contentView.bounds
            return button.frame.minX >= visible.minX-0.5 && button.frame.maxX <= visible.maxX+0.5
        }
        controller.window?.setContentSize(NSSize(width:560,height:500)); layout()
        checks["narrowWindowKeepsAllTwelveTabs"] = bar.buttons.count == 12 && bar.isOverflowing
        checks["overflowTabsKeepReadableWidths"] = bar.buttons.allSatisfy { $0.frame.width >= 91.5 && $0.frame.width <= 170.5 }
        checks["newTabIsFullyVisible"] = controller.index == 11 && selectedVisible()
        checks["overflowControlsAppearOnlyWhenNeeded"] = !bar.overflowButton.isHidden && !bar.previousButton.isHidden && !bar.nextButton.isHidden
        controller.selectTab(at:0); layout()
        checks["selectingFirstTabRevealsBeginning"] = selectedVisible() && bar.scrollView.contentView.bounds.minX < 0.5 && !bar.previousButton.isEnabled && bar.nextButton.isEnabled
        app.lastTerminalWindow = controller; app.buildMenu()
        let command9 = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:controller.window!.windowNumber,context:nil,characters:"9",charactersIgnoringModifiers:"9",isARepeat:false,keyCode:25)!
        let selectedByKey = NSApp.mainMenu?.performKeyEquivalent(with:command9) == true; layout()
        checks["commandNineRevealsHiddenTab"] = selectedByKey && controller.index == 8 && selectedVisible()
        let before = bar.scrollView.contentView.bounds.minX, selectedID = controller.workspace.id
        bar.previousTabs()
        checks["scrollingTabsDoesNotChangeActiveSession"] = controller.workspace.id == selectedID && bar.scrollView.contentView.bounds.minX < before
        let menu = bar.allTabsMenu()
        checks["allTabsMenuIncludesEverySessionAndShortcuts"] = menu.items.count == 12 && menu.items.prefix(9).enumerated().allSatisfy { $0.element.keyEquivalent == String($0.offset+1) } && menu.items.suffix(3).allSatisfy { $0.keyEquivalent.isEmpty }
        checks["allTabsMenuChecksOnlyActiveTab"] = menu.items.filter { $0.state == .on }.count == 1 && menu.items[8].state == .on
        let originalBinding = app.config.keybindings["selectTab1"]
        app.config.keybindings["selectTab1"] = "cmd+alt+1"
        let customMenu = bar.allTabsMenu()
        let customKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.option],timestamp:0,windowNumber:controller.window!.windowNumber,context:nil,characters:"1",charactersIgnoringModifiers:"1",isARepeat:false,keyCode:18)!
        let customSelected = customMenu.performKeyEquivalent(with:customKey); layout()
        checks["allTabsMenuHonoursConfiguredShortcuts"] = customSelected && controller.index == 0 && selectedVisible()
        app.config.keybindings["selectTab1"] = originalBinding
        controller.selectTabFromMenu(menu.items[11]); layout()
        checks["menuCanRevealTwelfthTab"] = controller.index == 11 && selectedVisible()
        let staleItem = bar.allTabsMenu().items[3], movedID = controller.workspaces[3].id
        _ = controller.moveTab(id:movedID,toInsertionIndex:0)
        controller.selectTabFromMenu(staleItem); layout()
        checks["menuSelectionUsesStableIdentityAfterReorder"] = controller.workspace.id == movedID && controller.index == 0 && selectedVisible()
        controller.window?.setContentSize(NSSize(width:2200,height:500)); layout()
        checks["wideWindowRemovesOverflowControls"] = !bar.isOverflowing && bar.overflowButton.isHidden && bar.previousButton.isHidden && bar.nextButton.isHidden
        controller.window?.setContentSize(NSSize(width:560,height:500)); controller.selectTab(at:11); layout()
        checks["shrinkingWindowKeepsSelectionVisible"] = bar.isOverflowing && selectedVisible()
        app.config.window.chromePosition = "titlebar"; app.applyAppearance(); layout()
        checks["overflowWorksInNativeTitlebar"] = bar.isOverflowing && selectedVisible() && controller.window!.titlebarAccessoryViewControllers.contains { controller.footer.isDescendant(of:$0.view) }
        app.config.window.showTabBar = false; app.applyAppearance(); layout()
        checks["tabPreferenceHidesWholeOverflowBar"] = bar.isHidden
        app.config.window.showTabBar = true; app.config.window.showStatusBar = false; app.config.window.chromePosition = "bottom"
        app.applyAppearance(); layout()
        checks["overflowWorksWithoutStatusText"] = !bar.isHidden && controller.status.isHidden && bar.isOverflowing && selectedVisible()
        controller.workspace.active.title = String(repeating:"long terminal title ",count:10); controller.refreshFooter(); layout()
        checks["longTitleDoesNotCrushOtherTabs"] = bar.buttons.allSatisfy { $0.frame.width >= 91.5 && $0.frame.width <= 170.5 } && selectedVisible()
        controller.closePane(); layout()
        checks["closingActiveTabRevealsItsNeighbour"] = controller.workspaces.count == 11 && selectedVisible() && bar.allTabsMenu().items.count == 11
        controller.selectTab(at:0); layout()
        let right = bar.scrollView.convert(NSPoint(x:bar.scrollView.bounds.maxX-1,y:bar.scrollView.bounds.midY),to:nil)
        bar.autoscrollDrag(at:right)
        checks["draggingAtEdgeScrollsHiddenTabs"] = bar.scrollView.contentView.bounds.minX > 0
        let remainingPIDs = Set(controller.workspaces.flatMap(\.panes).map { $0.terminal.process.shellPid })
        checks["tabNavigationPreservesOriginalPTYProcesses"] = remainingPIDs.count == 11 && remainingPIDs.isSubset(of:originalPIDs)
        controller.selectTab(at:0); app.config.window.showStatusBar = true; app.applyAppearance(); layout()
        if let bitmap = controller.footer.bitmapImageRepForCachingDisplay(in:controller.footer.bounds) {
            controller.footer.cacheDisplay(in:controller.footer.bounds,to:bitmap)
            if let data = bitmap.representation(using:.png,properties:[:]),let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] { try? data.write(to:URL(fileURLWithPath:path).deletingLastPathComponent().appendingPathComponent("TabsFooterPreview.png")) }
        }
        let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-tabs-results.json"
        do { try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output)); print(checks) } catch { print(error); exit(2) }
        if CommandLine.arguments.contains("--tabs-review") { return }
        app.windows.forEach { $0.stop() }; exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}

private final class LinkOpeningChecks: TerminalViewDelegate {
    func clipboardCopy(source: TerminalView,content: Data) {}
    var links: [String] = []
    var sent: [UInt8] = []
    func sizeChanged(source: TerminalView,newCols: Int,newRows: Int) {}
    func setTerminalTitle(source: TerminalView,title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView,directory: String?) {}
    func send(source: TerminalView,data: ArraySlice<UInt8>) { sent.append(contentsOf:data) }
    func scrolled(source: TerminalView,position: Double) {}
    func rangeChanged(source: TerminalView,startY: Int,endY: Int) {}
    func requestOpenLink(source: TerminalView,link: String,params: [String:String]) { links.append(link) }
    static func run(_ app: App) {
        let delegate = LinkOpeningChecks(),view = TerminalView(frame:NSRect(x:0,y:0,width:800,height:400))
        let window = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = view; view.terminalDelegate = delegate
        view.resize(cols:80,rows:20)
        func event(_ type: NSEvent.EventType,_ col: CGFloat,_ flags: NSEvent.ModifierFlags,_ row: CGFloat = 0) -> NSEvent {
            let size = view.getOptimalFrameSize(),scroller = view.subviews.first { $0 is NSScroller }?.frame.width ?? 0
            let width = (size.width-scroller)/CGFloat(view.getTerminal().cols),height = size.height/CGFloat(view.getTerminal().rows)
            let point = view.convert(NSPoint(x:(col+0.5)*width,y:view.frame.height-height*(row+0.5)),to:nil)
            return NSEvent.mouseEvent(with:type,location:point,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        }
        var checks: [String:Bool] = [:]
        view.feed(text:"https://getmoth.dev")
        view.mouseDown(with:event(.leftMouseDown,5,.command)); view.mouseUp(with:event(.leftMouseUp,5,.command))
        checks["commandClickOpensPlainURL"] = delegate.links == ["https://getmoth.dev"]
        delegate.links.removeAll()
        view.mouseDown(with:event(.leftMouseDown,5,[])); view.mouseUp(with:event(.leftMouseUp,5,[]))
        checks["ordinaryClickDoesNotOpenURL"] = delegate.links.isEmpty
        view.mouseDown(with:event(.leftMouseDown,5,.command)); view.mouseDragged(with:event(.leftMouseDragged,10,.command)); view.mouseUp(with:event(.leftMouseUp,10,.command))
        checks["commandDragDoesNotOpenURL"] = delegate.links.isEmpty
        view.mouseDown(with:event(.leftMouseDown,5,.command)); view.mouseUp(with:event(.leftMouseUp,10,.command))
        checks["releaseAwayFromPressDoesNotOpenURL"] = delegate.links.isEmpty
        view.feed(text:"\u{1b}[?1000h"); delegate.sent.removeAll()
        view.mouseDown(with:event(.leftMouseDown,5,.command)); view.mouseUp(with:event(.leftMouseUp,5,.command))
        checks["commandClickBypassesApplicationMouseReporting"] = delegate.links == ["https://getmoth.dev"] && delegate.sent.isEmpty
        view.getTerminal().resetFromHost(); delegate.links.removeAll()
        let target = "https://getmoth.dev/a;b?file=My%20Project"
        view.feed(text:"\u{1b}]8;;"+target+"\u{1b}\\Contact\u{1b}]8;;\u{1b}\\")
        view.mouseDown(with:event(.leftMouseDown,2,.command)); view.mouseUp(with:event(.leftMouseUp,2,.command))
        checks["commandClickUsesOSC8DestinationWithoutChangingEscapes"] = delegate.links == [target]
        view.getTerminal().resetFromHost(); delegate.links.removeAll()
        view.feed(text:"mailto:support@getmoth.dev")
        view.mouseDown(with:event(.leftMouseDown,10,.command)); view.mouseUp(with:event(.leftMouseUp,10,.command))
        checks["commandClickDispatchesMailURL"] = delegate.links == ["mailto:support@getmoth.dev"]
        view.getTerminal().resetFromHost(); view.feed(text:"https://getmoth.dev")
        view.mouseMoved(with:event(.mouseMoved,5,.command))
        checks["commandHoverUnderlinesEntireURL"] = view.hoveredLinkRanges.first.map { $0.startColumn == 0 && $0.endColumn == 19 } ?? false
        view.mouseMoved(with:event(.mouseMoved,5,[]))
        checks["releasingCommandRemovesLinkUnderline"] = view.hoveredLinkRanges.isEmpty
        view.getTerminal().resetFromHost(); delegate.links.removeAll()
        let wrappedURL = "https://cdn.discordapp.com/attachments/690251772102574089/1574230884528300103/IMG_0465.png?ex=6b04e442&is=6b0392c2&hm=994f20d30d39fdcbfcf0b50b61c9a8f7384fd98c61e3d79fc688d70c9389cea2&"
        let wrappedText = Array(("phlud> "+wrappedURL)),columns = view.getTerminal().cols
        let wrappedRows = stride(from:0,to:wrappedText.count,by:columns).map { String(wrappedText[$0..<min($0+columns,wrappedText.count)]) }
        view.feed(text:wrappedRows.joined(separator:"\r\n"))
        var hoverComplete = true
        for row in wrappedRows.indices {
            view.mouseMoved(with:event(.mouseMoved,row == 0 ? 10 : 2,.command,CGFloat(row)))
            hoverComplete = hoverComplete && (view.hoveredLinkRanges.first.map { $0.startRow == 0 && $0.startColumn == 7 && $0.endRow == wrappedRows.count-1 && $0.endColumn == wrappedRows.last!.count } ?? false)
            view.mouseDown(with:event(.leftMouseDown,row == 0 ? 10 : 2,.command,CGFloat(row)))
            view.mouseUp(with:event(.leftMouseUp,row == 0 ? 10 : 2,.command,CGFloat(row)))
        }
        checks["commandHoverUnderlinesRepaintedURLFromEveryRow"] = hoverComplete
        checks["commandClickOpensCompleteRepaintedURLFromEveryRow"] = delegate.links == Array(repeating:wrappedURL,count:wrappedRows.count)
        view.getTerminal().resetFromHost(); view.feed(text:"\u{1b}]8;;https://getmoth.dev\u{1b}\\Contact\u{1b}]8;;\u{1b}\\")
        view.mouseMoved(with:event(.mouseMoved,2,.command))
        checks["hyperlinkUnderlineCoversLabelNotDestination"] = view.hoveredLinkRanges.first.map { $0.startColumn == 0 && $0.endColumn == 7 } ?? false
        view.getTerminal().resetFromHost(); view.feed(text:"\u{1b}]8;;https://getmoth.dev\u{1b}\\🦋 link\u{1b}]8;;\u{1b}\\")
        view.mouseMoved(with:event(.mouseMoved,1,.command))
        checks["wideHyperlinkLabelUnderlinesBothCells"] = view.hoveredLinkRanges.first.map { $0.startColumn == 0 && $0.endColumn == 7 } ?? false
        checks["wideHyperlinkIsClickableOnContinuationCell"] = view.link(at:event(.mouseMoved,1,.command))?.link == "https://getmoth.dev"
        // Keep the standard menu and focus checks independent of foreground activation.
        app.newWindow(nil); let first = app.windows.last!
        first.content.layoutSubtreeIfNeeded()
        checks["newWindowImmediatelyTargetsTerminalForTyping"] = first.window?.firstResponder === first.workspace.active.terminal && first.window?.initialFirstResponder === first.workspace.active.terminal
        first.workspace.split(vertical:true,config:first.config); first.content.layoutSubtreeIfNeeded()
        let pane = first.workspace.active!,pid = pane.terminal.process.shellPid,sourceWorkspace = first.workspace
        pane.terminal.feed(text:"\r\nretained pane selection\r\n")
        if let match = pane.terminal.getTerminal().find("retained pane selection").matches.first { _ = pane.terminal.revealSearchMatch(match) }
        let menuEvent = NSEvent.mouseEvent(with:.rightMouseDown,location:pane.terminal.convert(NSPoint(x:5,y:5),to:nil),modifierFlags:[],timestamp:0,windowNumber:first.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        let menu = pane.terminal.menu(for:menuEvent)!
        checks["terminalHasStandardContextMenu"] = ["Copy","Paste","Select All","Move Pane to New Window","Close Pane"].allSatisfy { title in menu.items.contains { $0.title == title } }
        checks["contextCopyUsesExistingSelection"] = menu.items.first { $0.title == "Copy" }?.isEnabled == true && pane.terminal.getSelection() == "retained pane selection"
        let before = app.windows.count,outside = NSPoint(x:-20000,y:-20000)
        pane.dragHandle.finishDrag(at:outside,operation:[],wasCancelled:true)
        checks["cancelledPaneDragKeepsOriginalWindow"] = app.windows.count == before && sourceWorkspace.panes.contains { $0 === pane }
        pane.dragHandle.finishDrag(at:outside,operation:[],wasCancelled:false)
        let detached = app.windows.last!
        checks["paneDragTearsOffIntoNewWindow"] = app.windows.count == before+1 && detached.workspace.panes.count == 1 && detached.workspace.active === pane && sourceWorkspace.panes.count == 1
        checks["paneTearOffKeepsProcessAndSelection"] = pane.terminal.process.shellPid == pid && kill(pid,0) == 0 && pane.terminal.getSelection() == "retained pane selection"
        checks["paneTearOffFocusesTerminalImmediately"] = detached.window?.firstResponder === pane.terminal && detached.window?.initialFirstResponder === pane.terminal
        pane.terminal.getTerminal().resetFromHost(); pane.terminal.feed(text:"https://getmoth.dev/a%20b")
        let linkEvent = NSEvent.mouseEvent(with:.rightMouseDown,location:pane.terminal.convert(NSPoint(x:24,y:pane.terminal.bounds.height-5),to:nil),modifierFlags:[],timestamp:0,windowNumber:detached.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        let linkMenu = pane.terminal.menu(for:linkEvent)!
        checks["linkContextMenuOffersOpenAndCopy"] = ["Open Link","Copy Link"].allSatisfy { title in linkMenu.items.contains { $0.title == title } }
        if let index = linkMenu.items.firstIndex(where: { $0.title == "Copy Link" }) { linkMenu.performActionForItem(at:index) }
        checks["copyLinkPreservesDestinationEncoding"] = NSPasteboard.general.string(forType:.string) == "https://getmoth.dev/a%20b"
        detached.newTab(nil); let tab = detached.workspace,button = detached.tabBar.buttons.last!
        checks["tabHasContextMenu"] = button.menu(for:menuEvent)?.items.map(\.title) == ["Move Tab to New Window","Close Tab"]
        let tabWindowCount = app.windows.count
        button.finishDrag(at:outside,operation:[],wasCancelled:true)
        checks["cancelledTabDragDoesNotTearOff"] = app.windows.count == tabWindowCount
        button.finishDrag(at:outside,operation:.move,wasCancelled:false)
        checks["acceptedTabDropDoesNotAlsoTearOff"] = app.windows.count == tabWindowCount
        button.finishDrag(at:outside,operation:[],wasCancelled:false)
        checks["tabDragCompletionCreatesNewWindow"] = app.windows.count == tabWindowCount+1 && app.windows.last?.workspace === tab && detached.workspaces.count == 1
        window.close(); app.windows.forEach { $0.stop() }
        let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-link-results.json"
        do { try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output)); print(checks) } catch { print(error); exit(2) }
        exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}

private final class TabTransferChecks {
    let app: App
    var checks: [String:Bool] = [:]
    init(_ app: App) { self.app = app }
    func layout(_ controller: TerminalWindowController) {
        controller.window?.contentView?.superview?.layoutSubtreeIfNeeded()
        controller.content.layoutSubtreeIfNeeded(); controller.workspace.root.layoutSubtreeIfNeeded()
    }
    func run() {
        app.windows.forEach { $0.stop(); $0.window?.close() }
        var config = Configuration(); config.shell = "/bin/sh"; config.advanced.loginShell = false
        config.advanced.environment = ["PS1":"$ ","HISTFILE":"/dev/null","ENV":"/dev/null","BASH_ENV":"/dev/null"]
        config.closeConfirmation.enabled = false; config.closeOnExit = false; config.theme = "moth-dark"
        config.background.style = "solid"; config.window.frosted = false; config.window.opacity = 1
        app.config = config; app.newWindow(nil)
        let source = app.windows.last!
        source.window?.setContentSize(NSSize(width:1440,height:900)); layout(source)
        source.newTab(nil); layout(source)
        let moved = source.workspace
        moved.split(vertical:true,config:config); layout(source)
        moved.split(vertical:false,config:config); layout(source)
        let originalPanes = moved.panes,active = moved.active!
        let pids = originalPanes.map { $0.terminal.process.shellPid }
        app.newWindow(nil); let target = app.windows.last!
        target.window?.setContentSize(NSSize(width:760,height:580)); layout(target)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            let text = "selected e\u{301} 🦋 content across a soft wrapped logical line with several words"
            for pane in originalPanes {
                pane.terminal.feed(text:"\u{1b}c"+(0..<90).map { "history \($0) preserved\r\n" }.joined()+text+"\r\n")
                if let match = pane.terminal.getTerminal().find(text).matches.first { _ = pane.terminal.revealSearchMatch(match) }
            }
            self.checks["fixtureHasThreeLiveSplitSessions"] = originalPanes.count == 3 && pids.allSatisfy { $0 > 0 && kill($0,0) == 0 }
            self.checks["fixtureSelectsTextBeforeTransfer"] = originalPanes.allSatisfy { $0.terminal.getSelection() == text }
            moved.toggleMaximizePane()
            let pasteboard = NSPasteboard.withUniqueName(); pasteboard.setString(moved.id.uuidString,forType:.mothTab)
            self.checks["singleTabWindowAcceptsForeignTab"] = target.tabDropOperation(pasteboard) == .move
            self.checks["crossWindowTransferSucceeds"] = target.receiveTab(moved.id,at:0)
            self.layout(target)
            self.checks["movingTabPreservesMaximisedPane"] = moved.isPaneMaximized && moved.root.subviews.first === active
            self.checks["transferKeepsWorkspaceAndPaneIdentity"] = target.workspace === moved && moved.panes.elementsEqual(originalPanes,by: { $0 === $1 }) && moved.active === active
            self.checks["transferKeepsLiveProcessIDs"] = moved.panes.map { $0.terminal.process.shellPid } == pids && pids.allSatisfy { kill($0,0) == 0 }
            self.checks["transferPreservesSelectionThroughResize"] = originalPanes.allSatisfy { $0.terminal.getSelection() == text }
            self.checks["transferPreservesScrollback"] = originalPanes.allSatisfy { !$0.terminal.getTerminal().find("history 0 preserved").matches.isEmpty }
            self.checks["sourceKeepsOtherTabs"] = source.workspaces.count == 1 && self.app.windows.contains { $0 === source }
            self.checks["destinationOwnsReboundCallbacks"] = { active.title = "Transferred session"; moved.changed?(); return target.window?.title.contains("Transferred session") == true }()
            let oldCount = target.workspaces.count
            let detached = target.detachTab(moved.id,at:NSPoint(x:500,y:600))!
            self.layout(detached)
            self.checks["tearOffCreatesOnlyOneWindowWithSameSessions"] = detached.workspaces.count == 1 && detached.workspace === moved && target.workspaces.count == oldCount-1 && moved.panes.map { $0.terminal.process.shellPid } == pids
            self.checks["tearOffKeepsSelection"] = originalPanes.allSatisfy { $0.terminal.getSelection() == text }
            self.checks["tearingOffTabPreservesMaximisedPane"] = moved.isPaneMaximized && moved.root.subviews.first === active
            self.checks["tearOffKeepsNestedLayout"] = moved.orderedPanes.count == 3 && (try? moved.savedTab().root) != nil
            self.checks["moveLastTabClosesEmptySourceWithoutStoppingIt"] = target.receiveTab(moved.id) && !self.app.windows.contains { $0 === detached } && pids.allSatisfy { kill($0,0) == 0 }
            while source.workspaces.count < 12 { source.newTab(nil) }
            self.checks["fullWindowRejectsTransferWithoutRemovingSource"] = !source.receiveTab(moved.id) && target.workspaces.contains { $0 === moved } && source.workspaces.count == 12
            self.checks["unknownTabIsRejected"] = !target.receiveTab(UUID())
            self.checks["invalidInsertionDoesNotDetach"] = !target.receiveTab(source.workspace.id,at:99) && source.workspaces.count == 12
            // Repeated ownership changes must not recreate terminals or leave duplicate roots.
            for _ in 0..<4 { _ = target.detachTab(moved.id,at:NSPoint(x:500,y:600)); _ = target.receiveTab(moved.id,at:0) }
            self.layout(target)
            self.checks["repeatedTabMovesKeepMaximisedPane"] = moved.isPaneMaximized && moved.root.subviews.first === active
            self.checks["repeatedMovesKeepUniqueOwnershipAndPIDs"] = self.app.windows.flatMap(\.workspaces).filter { $0 === moved }.count == 1 && moved.root.superview === target.stage && moved.panes.map { $0.terminal.process.shellPid } == pids
            target.window?.setContentSize(NSSize(width:1440,height:960)); self.layout(target)
            let ordered = moved.orderedPanes
            self.checks["paneCentreDropSwapsExactSlots"] = self.app.movePane(ordered[0].id,to:ordered[1],zone:.centre) && moved.orderedPanes[0] === ordered[1] && moved.orderedPanes[1] === ordered[0]
            self.checks["paneSwapKeepsSelections"] = moved.panes.allSatisfy { $0.terminal.getSelection() == text }
            self.checks["paneRejectsDropOnItself"] = !self.app.movePane(ordered[0].id,to:ordered[0],zone:.centre)
            moved.active=ordered[0];moved.toggleMaximizePane()
            self.checks["invalidPaneDropDoesNotLeaveMaximisedMode"] = !self.app.movePane(ordered[0].id,to:ordered[0],zone:.centre) && moved.isPaneMaximized
            moved.restoreSplitLayout()
            let edgeTarget = moved.orderedPanes.last!
            self.checks["paneEdgeDropRearrangesWithoutNewSession"] = self.app.movePane(ordered[0].id,to:edgeTarget,zone:.top) && moved.panes.count == 3 && Set(moved.panes.map { $0.terminal.process.shellPid }) == Set(pids)
            source.selectTab(at:0); self.layout(source)
            let otherWorkspace = source.workspace,otherPane = otherWorkspace.active!
            moved.active=ordered[0];moved.toggleMaximizePane()
            self.checks["paneCanMoveBetweenWindows"] = self.app.movePane(ordered[0].id,to:otherPane,zone:.right) && otherWorkspace.panes.contains { $0 === ordered[0] } && moved.panes.count == 2
            self.checks["movingMaximisedPaneRestoresSourceLayout"] = !moved.isPaneMaximized && moved.orderedPanes.count==2
            self.checks["movedPaneRebindsFocusToNewWorkspace"] = { ordered[0].onFocus?(); return otherWorkspace.active === ordered[0] }()
            otherWorkspace.active=ordered[0];otherWorkspace.toggleMaximizePane()
            moved.active=moved.panes[0];moved.toggleMaximizePane()
            self.checks["paneCrossWindowSwapWorks"] = self.app.movePane(ordered[0].id,to:moved.panes[0],zone:.centre) && moved.panes.contains { $0 === ordered[0] } && otherWorkspace.panes.count == 2
            self.checks["swappingMaximisedPanesRestoresBothLayouts"] = !moved.isPaneMaximized && !otherWorkspace.isPaneMaximized
            self.checks["paneLayoutSerializesAfterMoves"] = (try? otherWorkspace.savedTab().root.validate()) != nil && (try? moved.savedTab().root.validate()) != nil
            self.checks["paneMovesKeepAllOriginalProcessesAlive"] = pids.allSatisfy { kill($0,0) == 0 } && Set(self.app.windows.flatMap(\.workspaces).flatMap(\.panes).map { ObjectIdentifier($0) }).count == self.app.windows.flatMap(\.workspaces).flatMap(\.panes).count
            active.terminal.sendUserText("printf '\\nLIVE_AFTER_MOVE_%s\\n' $$\n")
            self.wait { !active.terminal.getTerminal().find("LIVE_AFTER_MOVE_\(active.terminal.process.shellPid)").matches.isEmpty } completion: { ready in
                self.checks["movedPTYStillAcceptsInputAndProducesOutput"] = ready
                self.app.config.closeOnExit = true
                active.terminal.sendUserText("exit 0\n")
                self.wait { self.app.owner(ofPane:active.id) == nil } completion: { removed in
                    self.checks["exitAfterMovesRemovesPaneFromCurrentOwner"] = removed
                    self.checks["exitAfterMovesLeavesOtherOriginalProcessesRunning"] = pids.filter { $0 != active.terminal.process.shellPid }.allSatisfy { kill($0,0) == 0 }
                    self.finish()
                }
            }
        }
    }
    func wait(_ predicate: @escaping ()->Bool,completion: @escaping (Bool)->Void) {
        let deadline = ProcessInfo.processInfo.systemUptime+5
        func poll() { if predicate() { completion(true) } else if ProcessInfo.processInfo.systemUptime > deadline { completion(false) } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.05,execute:poll) } }
        poll()
    }
    func finish() {
        let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-transfer-results.json"
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
        print(checks); app.windows.forEach { $0.stop() }; exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}

private final class TextBlinkChecks {
    let app: App
    let view = TerminalView(frame:NSRect(x:0,y:0,width:900,height:420))
    var window: NSWindow!
    var checks: [String:Bool] = [:]
    init(_ app: App) { self.app = app }
    var rowHeight: CGFloat { view.getOptimalFrameSize().height/CGFloat(view.getTerminal().rows) }
    func bitmap(_ row: Int? = nil) -> NSBitmapImageRep {
        let rect = row.map { NSRect(x:0,y:view.bounds.height-CGFloat($0+1)*rowHeight,width:200,height:rowHeight) } ?? view.bounds
        let bitmap = view.bitmapImageRepForCachingDisplay(in:rect)!
        view.cacheDisplay(in:rect,to:bitmap); return bitmap
    }
    func rows() -> [Data] { (0..<10).map { bitmap($0).representation(using:.png,properties:[:])! } }
    func wait(_ predicate: @escaping ()->Bool,_ completion: @escaping (Bool)->Void) {
        let deadline = ProcessInfo.processInfo.systemUptime+3
        func poll() { if predicate() { completion(true) } else if ProcessInfo.processInfo.systemUptime > deadline { completion(false) } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.02,execute:poll) } }; poll()
    }
    func run() {
        window = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        view.nativeForegroundColor = .white; view.nativeBackgroundColor = .clear
        view.feed(text:"\u{1b}[?25lMMMMMMMM\r\n\u{1b}[5mMMMMMMMM\u{1b}[0m\r\n\u{1b}[1;5mMMMMMMMM\u{1b}[0m\r\n\u{1b}[4;5mMMMMMMMM\u{1b}[0m\r\n\u{1b}[7;5mMMMMMMMM\u{1b}[0m\r\n\u{1b}[1;4;7;5mMMMMMMMM\u{1b}[0m\r\n\u{1b}[6mMMMMMMMM\u{1b}[0m\r\n\u{1b}[48;2;180;40;60;5mMMMMMMMM\u{1b}[0m\r\n\u{1b}[5m█─█─█─█─\u{1b}[0m\r\n\u{1b}[5;25mMMMMMMMM\u{1b}[0m")
        let on = rows()
        let folder = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-blink.json").deletingLastPathComponent()
        try? bitmap().representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("blink-visible.png"))
        checks["visibleBlinkStartsTimerWithoutKeyboardFocus"] = view.textBlinkTimerRunning
        wait({ !self.view.textBlinkVisible }) { changed in
            self.checks["textBlinkTimerReachesHiddenPhase"] = changed
            let off = self.rows()
            self.checks["normalTextDoesNotBlink"] = on[0] == off[0]
            self.checks["SGR5TextBlinks"] = on[1] != off[1]
            self.checks["boldBlinkWorks"] = on[2] != off[2]
            self.checks["underlineBlinksWithText"] = on[3] != off[3]
            self.checks["inverseBlinkWorks"] = on[4] != off[4]
            self.checks["boldInverseUnderlineBlinkWorks"] = on[5] != off[5]
            self.checks["SGR6AlsoBlinks"] = on[6] != off[6]
            self.checks["truecolorBackgroundTextBlinks"] = on[7] != off[7]
            self.checks["customBlockAndBoxGlyphsBlink"] = on[8] != off[8]
            self.checks["SGR25DisablesBlink"] = on[9] == off[9]
            let inverse = self.bitmap(4).colorAt(x:0,y:0)?.usingColorSpace(.deviceRGB)
            self.checks["inverseBackgroundRemainsOpaqueWhenTextIsHidden"] = (inverse?.redComponent ?? 0) > 0.9 && (inverse?.alphaComponent ?? 0) > 0.9
            let color = self.bitmap(7).colorAt(x:0,y:0)?.usingColorSpace(.deviceRGB)
            self.checks["truecolorBackgroundRemainsWhenTextIsHidden"] = (color?.redComponent ?? 0) > 0.6 && (color?.greenComponent ?? 1) < 0.3
            try? self.bitmap().representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("blink-hidden.png"))
            self.wait({ self.view.textBlinkVisible }) { returned in
                self.checks["textBlinkReturnsToVisiblePhase"] = returned && self.rows()[1] == on[1]
                self.view.feed(text:"\u{1b}cstatic text\u{1b}[?25l"); _ = self.bitmap()
                self.checks["noBlinkTimerForStaticTerminal"] = !self.view.textBlinkTimerRunning
                self.window.close(); self.app.windows.forEach { $0.stop() }
                let output = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-blink.json"
                try! JSONSerialization.data(withJSONObject:self.checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
                print(self.checks); exit(self.checks.values.allSatisfy { $0 } ? 0 : 1)
            }
        }
    }
}

private enum BackgroundPictureChecks {
    static func run(_ app: App) {
        var checks: [String:Bool] = [:]
        let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-pictures.json")
        do {
            let imageURL = output.deletingLastPathComponent().appendingPathComponent("background fixture.png")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:120,pixelsHigh:60,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let pixels = bitmap.bitmapData!
            for y in 0..<60 { for x in 0..<120 {
                let index = y*bitmap.bytesPerRow+x*4
                pixels[index] = x < 60 ? 255 : 0; pixels[index+1] = 0
                pixels[index+2] = x < 60 ? 0 : 255; pixels[index+3] = 255
            } }
            try bitmap.representation(using:.png,properties:[:])!.write(to:imageURL)
            var config = Configuration(); config.background.style = "image"; config.background.imagePath = imageURL.path; config.background.imageScale = "fit"; config.background.imageOpacity = 0.42
            try config.validate()
            let file = output.deletingLastPathComponent().appendingPathComponent("picture.toml"); try Configuration.save(config,to:file)
            let read = try Configuration.load(from:file)
            checks["imageSettingsRoundTripTOML"] = read.background.style == "image" && read.background.imagePath == imageURL.path && read.background.imageScale == "fit" && read.background.imageOpacity == 0.42
            let profile = TerminalProfile(name:"Picture fixture",configuration:config)
            let decoded = try JSONDecoder().decode(TerminalProfile.self,from:JSONEncoder().encode(profile)).applying(to:Configuration())
            checks["profilesKeepTheirOwnBackgroundPicture"] = decoded.background.imagePath == imageURL.path && decoded.background.imageOpacity == 0.42
            let image = FlowBackgroundView.loadBackgroundImage(imageURL.path)
            checks["nativeImageDecoderLoadsPicture"] = image?.width == 120 && image?.height == 60
            checks["sameUnchangedImageUsesDecodeCache"] = image === FlowBackgroundView.loadBackgroundImage(imageURL.path)
            let background = FlowBackgroundView(frame:NSRect(x:0,y:0,width:500,height:500)); background.apply(config); background.layoutSubtreeIfNeeded()
            checks["fitSizingUsesAspectFit"] = background.pictureLayer.contents != nil && background.pictureLayer.contentsGravity == .resizeAspect && background.pictureLayer.opacity == Float(0.42)
            config.background.imageScale = "fill"; background.apply(config)
            checks["fillSizingUsesAspectFill"] = background.pictureLayer.contentsGravity == .resizeAspectFill
            config.window.opacity = 0.6; background.apply(config)
            checks["pictureRespectsWindowOpacity"] = abs(background.backgroundOpacity-0.6) < 0.001
            let pane = Pane(config:config,start:false)
            checks["terminalLetsPictureShowBehindText"] = pane.terminal.nativeBackgroundColor.alphaComponent == 0
            app.config = config
            let panel = AppearancePanel(application:app); panel.refresh()
            checks["settingsExposePictureAndSizingAndStrength"] = panel.fields["background.imagePath"] is NSButton && panel.fields["background.imageScale"] is NSPopUpButton && panel.fields["background.imageOpacity"] != nil && !panel.imageControls.isHidden && panel.animatedControls.isHidden && panel.plainBackgroundControls.isHidden
            let remove = panel.fields["background.removeImage"] as! NSButton; remove.performClick(nil)
            checks["removePictureRestoresPlainBackground"] = app.config.background.style == "solid" && app.config.background.imagePath.isEmpty
            config.background.imagePath = imageURL.path+".missing"; background.apply(config)
            checks["missingFileFallsBackWithoutRejectingConfiguration"] = (try? config.validate()) != nil && background.pictureLayer.contents == nil
            let invalid = output.deletingLastPathComponent().appendingPathComponent("not-an-image.png"); try Data("not an image".utf8).write(to:invalid)
            checks["invalidImageIsRejectedByDecoder"] = FlowBackgroundView.loadBackgroundImage(invalid.path) == nil
            var bad = config; bad.background.imageScale = "stretch"
            checks["invalidSizingRejected"] = (try? bad.validate()) == nil
            bad = config; bad.background.imageOpacity = 2
            checks["invalidImageStrengthRejected"] = (try? bad.validate()) == nil
            panel.close()
        } catch { print(error); checks["pictureFixtureCompleted"] = false }
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print(checks); app.windows.forEach { $0.stop() }; exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}

private enum FullFontFamilyChecks {
    static func run(_ app: App) {
        var checks: [String:Bool] = [:]
        let styles = ["Thin","ThinItalic","UltraLight","UltraLightItalic","Light","LightItalic","Regular","Italic","Medium","MediumItalic","SemiBold","SemiBoldItalic","Bold","BoldItalic"]
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:40),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.orderFront(nil)
        let canvas = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1100,pixelsHigh:styles.count*40,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let context = NSGraphicsContext(bitmapImageRep:canvas)!
        for (index,style) in styles.enumerated() {
            var config = Configuration(); config.fontName = "WumpusMonoPro-"+style; config.fontSize = 18; config.typography.features = ["ss01":1]; config.typography.ligatures = true
            let terminal = ShellView(frame:NSRect(x:0,y:0,width:1100,height:40)); terminal.font = FontTypography.font(config)
            terminal.nativeBackgroundColor = NSColor.hex("11151C"); terminal.nativeForegroundColor = NSColor.hex("E1E5EE"); window.contentView = terminal
            terminal.feed(text:style.padding(toLength:19,withPad:" ",startingAt:0)+"AaBb gjpqy 012345  == != ->  \u{f07b} \u{f120} \u{e0b0} \u{f0001}\u{1b}[?25l")
            let italic = style.hasSuffix("Italic") || style == "Italic"
            var weight = style.replacingOccurrences(of:"Italic",with:""); if weight.isEmpty { weight = "Regular" }
            let italicFace = weight == "Regular" ? "Italic" : weight+"Italic"
            let fonts = terminal.fontVariants
            checks[style+"UsesRealSelectedFace"] = fonts["regular"]?.fontName == config.fontName
            checks[style+"UsesExactItalicFace"] = fonts["italic"]?.fontName == "WumpusMonoPro-"+italicFace
            checks[style+"UsesRealBoldFace"] = fonts["bold"]?.fontName == "WumpusMonoPro-"+(italic ? "BoldItalic" : "Bold") && fonts["boldItalic"]?.fontName == "WumpusMonoPro-BoldItalic"
            let baseFeatures = terminal.font.fontDescriptor.object(forKey:.featureSettings) as? NSArray
            checks[style+"KeepsOpenTypeFeaturesInVariants"] = fonts.values.allSatisfy { ($0.fontDescriptor.object(forKey:.featureSettings) as? NSArray)?.isEqual(to:baseFeatures as? [Any] ?? []) == true }
            checks[style+"GetsNerdGlyphsInAllVariants"] = fonts.values.allSatisfy { font in
                ["\u{f07b}","\u{f120}","\u{e0b0}","\u{f0001}"].allSatisfy { text in
                    let fallback = CTFontCreateForString(font,text as CFString,CFRange(location:0,length:text.utf16.count))
                    return CTFontCopyPostScriptName(fallback) as String == "MothNerdSymbolsMono-Regular"
                }
            }
            let fontURL = CTFontCopyAttribute(terminal.font,kCTFontURLAttribute) as? URL
            checks[style+"LoadsBundledLicensedTextFace"] = fontURL?.resolvingSymlinksInPath().path.hasPrefix(Bundle.main.bundleURL.resolvingSymlinksInPath().path+"/") == true
            if style == "Regular" { print("Font origin:",String(describing:fontURL),"bundle:",Bundle.main.bundleURL) }
            let bitmap = terminal.bitmapImageRepForCachingDisplay(in:terminal.bounds)!
            terminal.cacheDisplay(in:terminal.bounds,to:bitmap)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            NSImage(cgImage:bitmap.cgImage!,size:terminal.bounds.size).draw(in:NSRect(x:0,y:(styles.count-index-1)*40,width:1100,height:40))
            NSGraphicsContext.restoreGraphicsState()
        }
        let unicodeFont = FontTypography.font(Configuration())
        checks["ordinaryUnicodeKeepsSystemFallback"] = ["界","🦋"].allSatisfy { text in
            let font = CTFontCreateForString(unicodeFont,text as CFString,CFRange(location:0,length:text.utf16.count))
            return !(CTFontCopyPostScriptName(font) as String).contains("LastResort") && CTFontCopyPostScriptName(font) as String != "MothNerdSymbolsMono-Regular"
        }
        checks["nativeFontPickerHasAllFourteenFaces"] = NSFontManager.shared.availableMembers(ofFontFamily:"Wumpus Mono Pro")?.count == 14
        checks["legacyDefaultPreferenceMigrates"] = (try? JSONDecoder().decode(Configuration.self,from:Data("{\"fontName\":\"WumpusMonoNFM\"}".utf8)))?.fontName == Configuration.defaultFontName
        var profile = TerminalProfile(name:"Legacy font",configuration:Configuration()); profile.fontName = "WumpusMonoNFM"
        checks["legacyProfilePreferenceMigrates"] = (try? JSONDecoder().decode(TerminalProfile.self,from:JSONEncoder().encode(profile)))?.fontName == Configuration.defaultFontName
        checks["originalMergedFontIsNotBundled"] = Bundle.main.url(forResource:"WumpusMonoNerdFontMono-Regular",withExtension:"ttf",subdirectory:"Fonts") == nil
        let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-fonts.json")
        try! canvas.representation(using:.png,properties:[:])!.write(to:output.deletingLastPathComponent().appendingPathComponent("font-family.png"))
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        window.close(); print(checks); app.windows.forEach { $0.stop() }; exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}

private final class VTCompatibilityChecks: TerminalViewDelegate {
    var sent: [UInt8] = []
    func sizeChanged(source: TerminalView,newCols: Int,newRows: Int) {}
    func setTerminalTitle(source: TerminalView,title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView,directory: String?) {}
    func send(source: TerminalView,data: ArraySlice<UInt8>) { sent.append(contentsOf:data) }
    func scrolled(source: TerminalView,position: Double) {}
    func rangeChanged(source: TerminalView,startY: Int,endY: Int) {}
    func clipboardCopy(source: TerminalView,content: Data) {}
    func requestOpenLink(source: TerminalView,link: String,params: [String:String]) {}
    static func run(_ app: App) {
        var checks: [String:Bool] = [:]
        let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-vt.json")
        let view = TerminalView(frame:NSRect(x:0,y:0,width:900,height:360)), recorder = VTCompatibilityChecks()
        let window = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;view.terminalDelegate=recorder;window.makeKeyAndOrderFront(nil)
        view.font=FontTypography.font(Configuration());view.nativeBackgroundColor = .black;view.nativeForegroundColor = .white
        view.resize(cols:80,rows:12)
        view.feed(text:"\u{1b}[?25lMMMM\r\n\u{1b}#6MMMM\r\n\u{1b}#3MMMM\r\n\u{1b}#4MMMM\r\n\u{1b}#5normal")
        let height=view.getOptimalFrameSize().height/CGFloat(view.getTerminal().rows)
        func row(_ index: Int)->NSBitmapImageRep {
            let rect=NSRect(x:0,y:view.bounds.height-CGFloat(index+1)*height,width:200,height:height)
            let image=view.bitmapImageRepForCachingDisplay(in:rect)!;view.cacheDisplay(in:rect,to:image);return image
        }
        func ink(_ image: NSBitmapImageRep)->(width:Int,count:Int) {
            var xs:[Int]=[],count=0
            for y in 0..<image.pixelsHigh { for x in 0..<image.pixelsWide {
                if let c=image.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.redComponent>0.65,c.greenComponent>0.65,c.blueComponent>0.65 { xs.append(x);count+=1 }
            } }
            return ((xs.max() ?? 0)-(xs.min() ?? 0)+1,count)
        }
        let single=ink(row(0)),wide=ink(row(1)),top=row(2),bottom=row(3)
        checks["doubleWidthActuallyRendersAtTwiceWidth"] = wide.width>single.width*18/10 && wide.width<single.width*23/10
        checks["doubleHeightTopAndBottomRenderDistinctHalves"] = ink(top).count>0 && ink(bottom).count>0 && top.representation(using:.png,properties:[:]) != bottom.representation(using:.png,properties:[:])
        let before=wide.width;view.getTerminal().allowDoubleSizeLines=false
        checks["disableRestoresNormalRenderedWidth"] = ink(row(1)).width*18/10<before
        view.getTerminal().allowDoubleSizeLines=true
        view.feed(text:"\u{1b}[2;1H\u{1b}#6ABCDEFGHIJ\u{1b}[?25h")
        view.feed(text:"\u{1b}[2;3H")
        RunLoop.current.run(until:Date().addingTimeInterval(0.1));view.displayIfNeeded()
        let cellWidth=view.caretFrame.width/2
        checks["doubleWidthCursorUsesTwoCells"] = abs(view.caretFrame.minX-cellWidth*4)<1 && view.caretFrame.width>cellWidth*1.9
        view.feed(text:"\u{1b}[?25l")
        func mouse(_ type:NSEvent.EventType,_ column:CGFloat)->NSEvent {
            let point=view.convert(NSPoint(x:cellWidth*column,y:view.bounds.height-height*1.5),to:nil)
            return NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        }
        view.mouseDown(with:mouse(.leftMouseDown,2.1));view.mouseDragged(with:mouse(.leftMouseDragged,8.1));view.mouseUp(with:mouse(.leftMouseUp,8.1))
        print("VT selection:",String(reflecting:view.getSelection()))
        checks["selectionUsesDoubleWidthCellCoordinates"] = view.getSelection()=="BCD"
        view.selectNone()
        recorder.sent=[];view.doCommand(by:#selector(NSResponder.deleteBackward(_:)))
        checks["defaultBackarrowSendsDelete"] = recorder.sent == [127]
        view.feed(text:"\u{1b}[?67h");recorder.sent=[];view.doCommand(by:#selector(NSResponder.deleteBackward(_:)))
        checks["DECBKMSetSendsBackspace"] = recorder.sent == [8]
        view.feed(text:"\u{1b}[?67l");recorder.sent=[];view.doCommand(by:#selector(NSResponder.deleteBackward(_:)))
        checks["DECBKMResetSendsDelete"] = recorder.sent == [127]
        view.feed(text:"\u{1b}[2J\u{1b}[H\u{1b}#5MMMM\u{1b}[?25l")
        let normalBefore=row(0).representation(using:.png,properties:[:])
        view.feed(text:"\u{1b}[?5h")
        let reversed=row(0).representation(using:.png,properties:[:])
        checks["reverseVideoRepaintsExistingText"] = reversed != normalBefore
        view.feed(text:"\u{1b}[?5l")
        checks["reverseVideoRestoresExistingText"] = row(0).representation(using:.png,properties:[:]) == normalBefore
        do {
            let configURL=output.deletingLastPathComponent().appendingPathComponent("vt-config.toml")
            var config=Configuration();config.advanced.allowDoubleSizeLines=false
            try Configuration.save(config,to:configURL)
            checks["compatibilityPreferencePersistsInTOML"] = try !Configuration.load(from:configURL).advanced.allowDoubleSizeLines
            checks["oldConfigurationsDefaultToEnabled"] = try JSONDecoder().decode(Configuration.Advanced.self,from:Data("{}".utf8)).allowDoubleSizeLines
            try Data(Configuration.document(config).utf8).write(to:output.deletingLastPathComponent().appendingPathComponent("config.example.toml"))
            let panel=AppearancePanel(application:app)
            checks["settingsExposeCompatibilityToggle"] = panel.fields["advanced.allowDoubleSizeLines"] is NSButton
            if let box=panel.fields["advanced.allowDoubleSizeLines"] as? NSButton {
                app.config.advanced.allowDoubleSizeLines=true;app.applyAppearance();panel.refresh();box.performClick(nil)
                checks["settingsToggleUpdatesLiveWindows"] = app.windows.flatMap(\.workspaces).flatMap(\.panes).allSatisfy { !$0.terminal.getTerminal().allowDoubleSizeLines }
                checks["settingsToggleSavesPreference"] = try !Configuration.load().advanced.allowDoubleSizeLines
            }
            panel.close()
        } catch { print(error);checks["configurationChecksCompleted"] = false }
        let full=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:full)
        try? full.representation(using:.png,properties:[:])?.write(to:output.deletingLastPathComponent().appendingPathComponent("vt-line-sizes.png"))
        print("VT pixel widths:",single.width,wide.width,"selection",view.getSelection() ?? "")
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print(checks);window.close();app.windows.forEach { $0.stop() };exit(checks.values.allSatisfy { $0 } ? 0:1)
    }
}

private enum UpdateAndPromptChecks {
    static func run(_ app: App) {
        var checks: [String:Bool] = [:]
        for key in ["newerBuildOfSameVersionIsOffered","unsupportedMacOSDoesNotOfferInstall","automaticCheckAnnouncesNewRelease"] { checks[key]=false }
        let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-updates.json")
        let system=OperatingSystemVersion(majorVersion:14,minorVersion:0,patchVersion:0)
        func evaluate(_ json:String,version:String="1.2.3",build:Int=10)->UpdateOutcome? {
            UpdateChecker.evaluate(Data(json.utf8),currentVersion:version,currentBuild:build,systemVersion:system)
        }
        let newer=#"{"version":"1.3.0","build":11,"diskImage":"https://getmoth.dev/downloads/Moth-1.3.0.dmg"}"#
        if case .available?=evaluate(newer) { checks["newerVersionIsOffered"]=true } else { checks["newerVersionIsOffered"]=false }
        checks["emptyFeedIsNotAnError"] = evaluate("{}") == .noPublicRelease
        checks["sameVersionIsCurrent"] = evaluate(newer,version:"1.3.0",build:11) == .upToDate
        checks["olderVersionsDoNotDowngrade"] = evaluate(newer,version:"2.0.0") == .upToDate
        if case .available?=evaluate(newer,version:"1.3.0",build:9) { checks["newerBuildOfSameVersionIsOffered"]=true }
        checks["invalidMetadataIsRejected"] = evaluate("not json")==nil && evaluate(#"{"version":"newest","diskImage":"https://getmoth.dev/a.dmg"}"#)==nil
        checks["unsafeDownloadsAreRejected"] = ["http://getmoth.dev/a.dmg","file:///tmp/a.dmg","https://elsewhere.example/a.dmg","https://user:password@getmoth.dev/a.dmg"].allSatisfy { url in evaluate("{\"version\":\"2.0.0\",\"diskImage\":\""+url+"\"}")==nil }
        let hashedFeed=newer.replacingOccurrences(of:"\"build\":11",with:"\"build\":11,\"commit\":\"012345abcdef\"")
        if case .available(let release)?=evaluate(hashedFeed) { checks["releaseFeedSupportsCommitIdentity"] = release.commit == "012345abcdef" }
        checks["hashDoesNotReplaceUpdateOrdering"] = evaluate(hashedFeed,version:"1.3.0",build:11) == .upToDate
        checks["invalidBuildIsRejected"] = evaluate(#"{"version":"2.0.0","build":true,"diskImage":"https://getmoth.dev/a.dmg"}"#)==nil
        checks["prereleaseOrderingIsNumeric"] = MothVersion("1.3.0-beta.2")! < MothVersion("1.3.0-beta.10")! && MothVersion("1.3.0-beta.10")! < MothVersion("1.3.0")! && MothVersion("1.9.0")! < MothVersion("1.10.0")! && MothVersion("1.0.0-99999999999999999999")! < MothVersion("1.0.0-100000000000000000000")! && MothVersion("1.0.0-01")==nil
        if case .requiresNewerSystem?=evaluate(#"{"version":"2.0.0","minimumSystemVersion":"15.0","diskImage":"https://getmoth.dev/a.dmg"}"#) { checks["unsupportedMacOSDoesNotOfferInstall"]=true }
        var callback:((Result<Data,Error>)->Void)?,requests=0,presentations=0,lastResult:Result<UpdateOutcome,Error>?
        let checker=UpdateChecker(version:"1.2.3",build:10,systemVersion:system) { request,completion in
            requests+=1;callback=completion
            checks["checkerUsesFirstPartyHTTPSFeed"] = request.url==UpdateChecker.endpoint && request.timeoutInterval<=15
            checks["requestContainsNoCookiesOrDeviceIdentifier"] = request.value(forHTTPHeaderField:"Cookie")==nil && request.url?.query==nil && request.value(forHTTPHeaderField:"User-Agent")=="Moth/1.2.3"
        }
        checker.presenter={ presentations+=1;lastResult=$0 }
        func reply(_ result:Result<Data,Error>) {
            callback?(result)
            let deadline=Date().addingTimeInterval(2)
            while checker.isChecking && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            checks["asynchronousCheckCompletes"] = !checker.isChecking
        }
        checker.check(manual:false);checker.check(manual:true)
        checks["concurrentChecksShareOneRequest"] = requests==1
        reply(.success(Data("{}".utf8)))
        checks["manualCheckReportsNoPublicRelease"] = presentations==1 && (try? lastResult?.get()) == .noPublicRelease
        checker.check(manual:false);reply(.success(Data("{}".utf8)))
        checks["automaticChecksStayQuietWithoutRelease"] = presentations==1
        checker.check(manual:false);reply(.failure(URLError(.notConnectedToInternet)))
        checks["automaticOfflineFailureIsQuiet"] = presentations==1 && checker.status=="Couldn’t check for updates."
        checker.check(manual:true);reply(.failure(URLError(.notConnectedToInternet)))
        checks["manualOfflineFailureIsReported"] = presentations==2
        checker.check(manual:false);reply(.success(Data(newer.utf8)))
        if case .available? = try? lastResult?.get() { checks["automaticCheckAnnouncesNewRelease"] = presentations==3 }
        do {
            var config=Configuration();config.updates.checkAtLaunch=false
            let file=output.deletingLastPathComponent().appendingPathComponent("updates.toml");try Configuration.save(config,to:file)
            checks["launchCheckPreferenceRoundTripsTOML"] = try !Configuration.load(from:file).updates.checkAtLaunch
            checks["oldConfigurationDefaultsToLaunchCheck"] = try JSONDecoder().decode(Configuration.Updates.self,from:Data("{}".utf8)).checkAtLaunch
            let panel=AppearancePanel(application:app)
            checks["dedicatedUpdatesSettingsPageExists"] = panel.pages["Updates"] != nil && panel.fields["updates.checkNow"] is NSButton
            if let box=panel.fields["updates.checkAtLaunch"] as? NSButton {
                app.config.updates.checkAtLaunch=true;panel.refresh();box.performClick(nil)
                checks["settingsTogglePersistsLaunchCheck"] = try !Configuration.load().updates.checkAtLaunch
            }
            let profile=TerminalProfile(name:"Update preference fixture",configuration:app.config)
            try ProfileStore.save(profile,base:app.config,in:app.profileDirectory);app.reloadProfiles()
            var candidate=app.config;candidate.updates.checkAtLaunch=true
            try app.saveSettings(candidate,profileID:profile.id)
            let savedUpdates=try Configuration.load().updates
            checks["updatePreferenceIsAppWideWhenEditingProfile"] = app.config.updates.checkAtLaunch && savedUpdates.checkAtLaunch
            checks["mothMenuIncludesUpdateCheck"] = NSApp.mainMenu?.items.first?.submenu?.items.contains { $0.title=="Check for Updates…" && $0.action == #selector(App.checkForUpdates(_:)) } == true
            panel.close()
        } catch { print(error);checks["updatePreferenceChecksComplete"]=false }
        let view=TerminalView(frame:NSRect(x:0,y:0,width:600,height:80))
        let window=NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;window.orderFront(nil)
        var samples=0,failures=0,worst:CGFloat=0
        var triangleSamples=0,triangleFailures=0,triangleWorst:CGFloat=0
        for font in ["WumpusMonoPro-Regular","JetBrainsMonoNFM-Regular","IBMPlexMono"] {
            for size in [11.0,13.0,14.0,16.0,19.0] {
                var config=Configuration();config.fontName=font;config.fontSize=size;view.font=FontTypography.font(config)
                for prefix in 1...8 {
                    view.feed(text:"\u{1b}[2J\u{1b}[H\u{1b}[?25l\u{1b}[48;2;180;177;216m"+String(repeating:" ",count:prefix)+"\u{1b}[38;2;180;177;216;48;2;94;129;255m\u{e0b0}      \u{1b}[0m")
                    let rect=view.bounds,image=view.bitmapImageRepForCachingDisplay(in:rect)!
                    view.cacheDisplay(in:rect,to:image)
                    let scale=CGFloat(image.pixelsWide)/rect.width
                    let h=view.getOptimalFrameSize().height/CGFloat(view.getTerminal().rows)
                    // Wumpus and the bundled monospaced families use fixed cell advances.
                    let effective=view.getOptimalFrameSize().width-(view.subviews.first { $0 is NSScroller }?.frame.width ?? 0)
                    let width=effective/CGFloat(view.getTerminal().cols)
                    let seam=Int((CGFloat(prefix)*width*scale).rounded())
                    // A filled separator must remain a full triangle, including
                    // its corners. A seam fix must not create a rectangular neck.
                    let left=floor(CGFloat(prefix)*width*scale)
                    let right=ceil(CGFloat(prefix+1)*width*scale)
                    let height=(h*scale).rounded()
                    for py in 1..<Int(height)-1 {
                        let expected=left+(right-left)*(1-abs(2*(CGFloat(py)+0.5)/height-1))
                        var edge:CGFloat=left
                        for px in Int(left)...Int(right) {
                            guard let c=image.colorAt(x:px,y:py)?.usingColorSpace(.sRGB),
                                  let foreground=image.colorAt(x:max(0,Int(left)-3),y:py)?.usingColorSpace(.sRGB),
                                  let background=image.colorAt(x:Int(right)+3,y:py)?.usingColorSpace(.sRGB) else { continue }
                            let distance=abs(c.redComponent-foreground.redComponent)+abs(c.greenComponent-foreground.greenComponent)+abs(c.blueComponent-foreground.blueComponent)
                            let backgroundDistance=abs(c.redComponent-background.redComponent)+abs(c.greenComponent-background.greenComponent)+abs(c.blueComponent-background.blueComponent)
                            if distance<backgroundDistance { edge=CGFloat(px)+1 }
                        }
                        let error=abs(edge-expected)
                        triangleSamples+=1;triangleWorst=max(triangleWorst,error)
                        if error>1.1 { triangleFailures+=1 }
                    }
                    for y in Int(h*scale*0.3)...Int(h*scale*0.7) {
                        for x in (seam-1)...(seam+1) {
                            guard let c=image.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else { continue }
                            let referenceX=max(0,seam-Int(width*scale/2))
                            guard let reference=image.colorAt(x:referenceX,y:y)?.usingColorSpace(.sRGB) else { continue }
                            let error=max(abs(c.redComponent-reference.redComponent),abs(c.greenComponent-reference.greenComponent),abs(c.blueComponent-reference.blueComponent))
                            samples+=1;worst=max(worst,error);if error>0.025 { failures+=1 }
                        }
                    }
                }
            }
        }
        checks["powerlineFilledJoinHasNoVerticalSeam"] = failures==0 && samples>1000
        checks["powerlineFilledSeparatorHasStraightSlopesToCorners"] = triangleFailures==0 && triangleSamples>1000
        print("Powerline triangle samples:",triangleSamples,"failures:",triangleFailures,"worst edge error:",triangleWorst)
        print("Powerline join samples:",samples,"failures:",failures,"worst colour error:",worst)
        view.feed(text:"\u{1b}[2J\u{1b}[H\u{1b}[?25l\u{1b}[38;2;180;177;216;49m\u{e0b6}\u{1b}[38;2;0;0;0;48;2;180;177;216m  thom@omicron \u{1b}[38;2;180;177;216;48;2;94;129;255m\u{e0b0}\u{1b}[38;2;0;0;0m  \u{f07b} ~ \u{1b}[38;2;94;129;255;49m\u{e0b4}\u{1b}[0m")
        let image=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:image)
        try? image.representation(using:.png,properties:[:])?.write(to:output.deletingLastPathComponent().appendingPathComponent("powerline-join.png"))
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print(checks);window.close();app.windows.forEach { $0.stop() };exit(checks.values.allSatisfy { $0 } ? 0:1)
    }
}

private final class BackgroundLifecycleWindow:NSWindow {
    var reportedOcclusion:NSWindow.OcclusionState = .visible
    override var occlusionState:NSWindow.OcclusionState { reportedOcclusion }
}
private final class BackgroundLifecycleChecks {
    let app:App
    let view=FlowBackgroundView(frame:NSRect(x:0,y:0,width:400,height:260))
    var window:BackgroundLifecycleWindow!
    var checks:[String:Bool]=[:]
    init(_ app:App){self.app=app}
    func changed(){NotificationCenter.default.post(name:NSWindow.didChangeOcclusionStateNotification,object:window)}
    func workspace(_ name:Notification.Name){NSWorkspace.shared.notificationCenter.post(name:name,object:NSWorkspace.shared)}
    func run(){
        var config=Configuration();config.background.style="flow";config.background.animated=true
        let expected=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0:1
        window=BackgroundLifecycleWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;window.orderFront(nil);view.apply(config);changed()
        checks["visibleWindowSchedulesExpectedMotion"]=view.animationCount==expected
        checks["staticBackgroundFrameRemainsAvailable"]=view.frameImage != nil || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        window.reportedOcclusion=[];changed()
        checks["fullyOccludedWindowHasNoAnimationTimer"]=view.animationCount==0
        window.reportedOcclusion = .visible;changed()
        checks["revealedWindowResumesExpectedMotion"]=view.animationCount==expected
        workspace(NSWorkspace.willSleepNotification)
        checks["systemSleepStopsAnimationTimer"]=view.animationCount==0
        workspace(NSWorkspace.screensDidSleepNotification);workspace(NSWorkspace.didWakeNotification)
        checks["systemWakeWaitsForSleepingDisplay"]=view.animationCount==0
        workspace(NSWorkspace.screensDidWakeNotification)
        checks["displayWakeResumesExpectedMotion"]=view.animationCount==expected
        workspace(NSWorkspace.sessionDidResignActiveNotification)
        checks["inactiveSessionStopsAnimationTimer"]=view.animationCount==0
        workspace(NSWorkspace.screensDidWakeNotification)
        checks["displayWakeDoesNotResumeInactiveSession"]=view.animationCount==0
        workspace(NSWorkspace.sessionDidBecomeActiveNotification)
        checks["activeSessionResumesExpectedMotion"]=view.animationCount==expected
        view.isHidden=true
        checks["hiddenViewStopsAnimationTimer"]=view.animationCount==0
        view.isHidden=false
        checks["unhiddenViewResumesExpectedMotion"]=view.animationCount==expected
        view.pauseMotion(true);workspace(NSWorkspace.willSleepNotification);workspace(NSWorkspace.didWakeNotification)
        checks["wakeRespectsExplicitMotionPause"]=view.animationCount==0
        view.pauseMotion(false)
        checks["explicitResumeRestoresExpectedMotion"]=view.animationCount==expected
        window.orderOut(nil);changed()
        checks["orderedOutWindowHasNoAnimationTimer"]=view.animationCount==0
        window.orderFront(nil);changed()
        checks["orderedInWindowResumesExpectedMotion"]=view.animationCount==expected
        view.pauseMotion(true)
        let before=view.frameImage?.dataProvider?.data as Data?
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25){
            self.checks["pausedBackgroundDoesNotPublishMoreFrames"]=(self.view.frameImage?.dataProvider?.data as Data?)==before
            self.view.pauseMotion(false);self.window.contentView=NSView(frame:self.view.frame)
            self.checks["detachedViewHasNoAnimationTimer"]=self.view.animationCount==0
            let output=ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-lifecycle-checks.json"
            try! JSONSerialization.data(withJSONObject:self.checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
            print(self.checks);self.window.close();self.app.windows.forEach{$0.stop()};exit(self.checks.values.allSatisfy{$0} ? 0:1)
        }
    }
}

private final class MetalPresentationChecks {
    let app:App
    let view=FlowBackgroundView(frame:NSRect(x:0,y:0,width:400,height:260))
    var window:NSWindow!
    var config=Configuration()
    var checks:[String:Bool]=[:]
    var phase=0
    init(_ app:App){self.app=app}
    func matchesReference(_ texture:MTLTexture,time:Double)->Bool {
        guard let image=FlowBackgroundView.render(config:config,size:view.bounds.size,time:time),
              image.width==texture.width,image.height==texture.height,
              let reference=image.dataProvider?.data as Data? else{return false}
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:texture.width,height:texture.height,mipmapped:false)
        let device=texture.device;descriptor.storageMode=device.hasUnifiedMemory ? .shared:.managed
        guard let copy=device.makeTexture(descriptor:descriptor),let command=device.makeCommandQueue()?.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else{return false}
        blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:texture.width,height:texture.height,depth:1),to:copy,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
        if !device.hasUnifiedMemory {blit.synchronize(resource:copy)}
        blit.endEncoding();command.commit();command.waitUntilCompleted()
        guard command.status == .completed else{return false}
        var bytes=[UInt8](repeating:0,count:texture.width*texture.height*4)
        bytes.withUnsafeMutableBytes{copy.getBytes($0.baseAddress!,bytesPerRow:texture.width*4,from:MTLRegionMake2D(0,0,texture.width,texture.height),mipmapLevel:0)}
        return reference.withUnsafeBytes{ raw in
            let old=raw.bindMemory(to:UInt8.self)
            for y in stride(from:0,to:texture.height,by:max(1,texture.height/12)) {
                for x in stride(from:0,to:texture.width,by:max(1,texture.width/12)) {
                    let i=(y*texture.width+x)*4
                    if abs(Int(bytes[i])-Int(old[i+2]))>1 || abs(Int(bytes[i+1])-Int(old[i+1]))>1 || abs(Int(bytes[i+2])-Int(old[i]))>1 || bytes[i+3] != 255 {return false}
                }
            }
            return true
        }
    }
    func finish(){
        view.onFramePresented=nil;window.orderOut(nil);app.windows.forEach{$0.stop()}
        let path=ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-metal-checks.json"
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print(checks);exit(checks.values.allSatisfy{$0} ? 0:1)
    }
    func run(){
        config.background.style="flow";config.background.effectColors=["C04872","335D95","A8C6AE"]
        config.window.opacity=0.72;config.window.frosted=true
        window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        view.apply(config);view.layoutSubtreeIfNeeded()
        checks["metalRetainsConfiguredOpacity"]=abs(view.backgroundOpacity-Float(config.windowBackgroundOpacity))<0.001
        checks["metalRetainsFrostedGlass"] = !view.frost.isHidden && view.backdropIsOnTintSurface
        view.onFramePresented={ [self] texture,time in
            if phase==0 {
                checks["directMetalFrameMatchesReferenceColours"]=matchesReference(texture,time:time)
                checks["directMetalFrameHasExpectedSize"]=texture.width==400 && texture.height==260
                phase=1;window.setContentSize(NSSize(width:920,height:460));view.layoutSubtreeIfNeeded()
            } else if phase==1,texture.width==640,texture.height==320 {
                checks["resizedMetalFrameMatchesReferenceColours"]=matchesReference(texture,time:time)
                checks["metalDrawableResolutionRemainsBounded"]=true
                phase=2;view.pauseMotion(true);let count=view.presentedFrames
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3){ [self] in
                    checks["pausedMetalDoesNotPresentMoreFrames"]=view.presentedFrames==count
                    phase=3;view.pauseMotion(false)
                }
            } else if phase==3 {
                checks["metalResumesAfterPause"]=true;phase=4;window.orderOut(nil);let count=view.presentedFrames
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3){ [self] in
                    checks["hiddenMetalDoesNotPresentMoreFrames"]=view.presentedFrames==count
                    phase=5;window.makeKeyAndOrderFront(nil)
                }
            } else if phase==5 {
                checks["metalResumesWhenWindowReturns"]=true;phase=6
                config.background.animated=false;view.apply(config);let count=view.presentedFrames
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3){ [self] in
                    checks["staticModeStopsMetalPresentation"]=view.presentedFrames==count && view.animationCount==0 && view.frameImage != nil
                    finish()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+12){ [self] in checks["metalPresentationCompletedBeforeTimeout"]=false;finish() }
    }
}

private final class DefinitionCaptureView: ShellView {
    var manuals: [String] = []
    override func showManual(_ reference: ManualReference,at point: NSPoint? = nil) { manuals.append(reference.query) }
    var definitions: [String] = []
    var sent: [UInt8] = []
    override func showDefinition(for attrString: NSAttributedString?, at textBaselineOrigin: NSPoint) {
        definitions.append(attrString?.string ?? "")
    }
    override func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf:data) }
}

private final class ManualViewerChecks {
    let app: App
    var checks: [String:Bool] = [:]
    var finished = false
    init(_ app: App) { self.app = app }
    func run() {
        SelfTest.manualChecks(into:&checks)
        guard let window = app.active else { checks["manualViewerWindowExists"] = false; finish(); return }
        window.window?.setContentSize(NSSize(width:1100,height:700)); window.content.layoutSubtreeIfNeeded()
        let workspace = window.workspace,source = window.workspace.active!
        let frame = source.frame,pid = source.terminal.process.shellPid
        source.terminal.lookup.manualPresentation = "popover"
        source.terminal.showManual(ManualReference("ls(1)")!)
        guard let viewer = source.terminal.presentedManual else { checks["manualViewerPopoverOpens"] = false; finish();return }
        wait(viewer) { [self] in
            checks["manualViewerPopoverPreservesTerminalLayout"] = workspace.panes.count == 1 && source.frame == frame && source.terminal.process.shellPid == pid
            viewer.searchField.stringValue = "directory"
            viewer.find { [self] found in
                checks["manualViewerNativeSearchFindsText"] = found
                viewer.snapshot { [self] image in
                    if let data = image?.tiffRepresentation,let bitmap = NSBitmapImageRep(data:data),let png = bitmap.representation(using:.png,properties:[:]) {
                        let path = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!).deletingLastPathComponent().appendingPathComponent("ManualPreview.png")
                        try? png.write(to:path); checks["manualViewerRenderedSnapshot"] = bitmap.pixelsWide > 100 && bitmap.pixelsHigh > 100
                    } else { checks["manualViewerRenderedSnapshot"] = false }
                    viewer.open(ManualReference.link(URL(string:"moth-man:chmod(1)")!)!)
                    wait(viewer) { [self] in
                        checks["manualViewerRelatedPageLoads"] = viewer.reference.query == "chmod(1)" && viewer.renderedHTML?.contains("change file modes") == true
                        app.find(nil)
                        checks["manualViewerPopoverUsesAppFind"] = viewer.searchField.currentEditor() != nil
                        viewer.onOpenWindow?(viewer.reference)
                        guard let reference = app.manualWindows.last else { checks["manualViewerOpensReferenceWindow"] = false;finish();return }
                        checks["manualViewerOpensReferenceWindow"] = reference.viewer === viewer && reference.window?.isVisible == true && source.terminal.presentedManual == nil
                        checks["manualViewerTransferRetainsDocument"] = viewer.documentLoaded && viewer.reference.query == "chmod(1)"
                        app.find(nil)
                        checks["manualReferenceWindowUsesAppFind"] = viewer.searchField.currentEditor() != nil
                        checks["manualReferenceWindowDoesNotCreatePanes"] = workspace.panes.count == 1 && source.frame == frame && source.terminal.process.shellPid == pid
                        viewer.open(ManualReference("moth_missing_manual_123456")!)
                        wait(viewer,expectError:true) { [self] in
                            checks["manualViewerMissingPageShowsInlineError"] = viewer.lastError != nil && viewer.documentLoaded
                            reference.close()
                            checks["manualReferenceWindowClosesIndependently"] = app.manualWindows.isEmpty && source.terminal.process.running && workspace.panes.count == 1
                            source.terminal.lookup.manualPresentation = "window"
                            source.terminal.showManual(ManualReference("printf(3)")!)
                            guard let direct = app.manualWindows.last else { checks["manualWindowPreferenceWorks"] = false;finish();return }
                            wait(direct.viewer) { [self] in
                                checks["manualWindowPreferenceWorks"] = direct.viewer.reference.query == "printf(3)" && direct.window?.isVisible == true && source.terminal.presentedManual == nil
                                let reused = app.showManualWindow(ManualReference("ls")!)
                                checks["manualWindowPreferenceReusesReferenceWindow"] = reused === direct && app.manualWindows.count == 1
                                direct.close();finish()
                            }
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+30) { [self] in if !finished { checks["manualViewerFinishedBeforeTimeout"] = false;finish() } }
    }
    func wait(_ viewer: ManualPageController,expectError: Bool = false,remaining: Int = 150,done: @escaping ()->Void) {
        guard !finished else { return }
        if viewer.documentLoaded && (expectError ? viewer.lastError != nil : viewer.renderedHTML != nil) { done();return }
        guard remaining > 0 else { print("Manual load timeout:",viewer.renderedHTML?.count ?? 0,viewer.lastError ?? "no error",viewer.documentLoaded);checks["manualViewerLoadedBeforeTimeout"] = false;finish();return }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { [self] in wait(viewer,expectError:expectError,remaining:remaining-1,done:done) }
    }
    func finish() {
        guard !finished else { return }; finished = true
        let path = ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-manual-results.json"
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print("Manual viewer checks:",checks)
        Array(app.manualWindows).forEach { $0.close() }
        app.windows.forEach { $0.stop() }; NSApp.terminate(nil)
    }
}

/// Programmatic window-resize timings exercise the same layout, reflow and
/// drawing path. They do not measure mouse-drag latency or other terminal apps.
private final class ResizeWindowChecks {
    let app: App
    var checks: [String:Bool] = [:]
    var measurements: [[String:Any]] = []
    var finished = false
    let scenarios = [("empty-minimal",0,false,false),("history-minimal",3000,false,false),("selection-history-minimal",3000,true,false),("empty-dynamic",0,false,true)]
    init(_ app: App) { self.app = app }
    func run() {
        guard let terminal = app.active?.workspace.active.terminal else { finish();return }
        // Keep the PTY running for real resize notifications, with no prompt or
        // readline repaint altering the selection/content under measurement.
        terminal.sendUserText("stty -echo; printf '%s%s\\n' MOTH_RESIZE_ QUIET; exec /bin/sleep 60\r")
        func ready(_ remaining: Int) {
            if !terminal.getTerminal().find("MOTH_RESIZE_QUIET").matches.isEmpty {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { self.scenario(0) };return
            }
            guard remaining > 0 else { self.checks["resizeFixtureReady"] = false;self.finish();return }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { ready(remaining-1) }
        }
        ready(120)
        DispatchQueue.main.asyncAfter(deadline:.now()+45) { [self] in if !finished { checks["resizeMeasurementCompleted"] = false;finish() } }
    }
    func scenario(_ index: Int) {
        guard !finished else { return }
        guard index < scenarios.count,let host = app.active else { finish();return }
        let (name,history,selected,animated) = scenarios[index]
        var config = Configuration();config.background.style = animated ? "flow":"solid";config.cursor.animation = "noblink"
        app.config = config;app.applyAppearance()
        let terminal = host.workspace.active.terminal
        terminal.selectNone();terminal.getTerminal().resetFromHost()
        host.window?.setContentSize(NSSize(width:1000,height:640));host.content.layoutSubtreeIfNeeded()
        if history > 0 { terminal.feed(text:(0..<history).map { "resize row \($0) history text abcdefghijklmnopqrstuvwxyz\r\n" }.joined()) }
        if selected,let match = terminal.getTerminal().find("resize row 2999").matches.first { _ = terminal.revealSearchMatch(match) }
        var samples: [Double] = []
        func step(_ count: Int) {
            guard !self.finished else { return }
            let start = ProcessInfo.processInfo.systemUptime
            let sweep = count%60,offset = sweep < 30 ? sweep : 60-sweep
            host.window?.setContentSize(NSSize(width:820+offset*12,height:600+count%9*3))
            host.content.layoutSubtreeIfNeeded();terminal.needsDisplay = true;host.content.displayIfNeeded();CATransaction.flush()
            if count >= 6 { samples.append((ProcessInfo.processInfo.systemUptime-start)*1000) }
            if count < 65 { DispatchQueue.main.asyncAfter(deadline:.now()+0.01) { step(count+1) };return }
            let ordered = samples.sorted(),total = samples.reduce(0,+)
            let values: [String:Any] = ["scenario":name,"samples":samples.count,"meanMilliseconds":total/Double(samples.count),"medianMilliseconds":ordered[ordered.count/2],"p95Milliseconds":ordered[Int(Double(ordered.count-1)*0.95)],"maximumMilliseconds":ordered.last!]
            self.measurements.append(values);print("WINDOW_RESIZE_BENCH",values)
            let core = terminal.getTerminal()
            self.checks["resizeFinalDimensions_"+name] = host.workspace.active.dimensions.stringValue == "\(core.cols) × \(core.rows)" && host.status.stringValue.contains("\(core.cols) × \(core.rows)")
            if selected { self.checks["resizeKeepsSelection"] = terminal.getSelection() == "resize row 2999" }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { self.scenario(index+1) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { step(0) }
    }
    func finish() {
        guard !finished else { return };finished = true
        let path = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"] ?? "/tmp/moth-resize-results.json")
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:path)
        try! JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:path.deletingLastPathComponent().appendingPathComponent("ResizeMeasurements.json"))
        app.windows.forEach { $0.stop() };NSApp.terminate(nil)
    }
}


/// Same per-cell truecolour/upper-half-block workload as Gloam, with deterministic
/// frames and no network/audio decoding included in the terminal measurement.
private enum AnimatedColourChecks {
    static func run(_ app: App) {
        guard let host = app.active else { exit(1) }
        var config = Configuration();config.background.style = "solid";config.cursor.animation = "noblink"
        app.config = config;app.applyAppearance()
        let terminal = host.workspace.active.terminal
        host.window?.setContentSize(NSSize(width:1200,height:800));host.content.layoutSubtreeIfNeeded()
        terminal.getTerminal().resetFromHost()
        terminal.feed(text:"\u{1b}[?1049h\u{1b}[?25l")
        let core = terminal.getTerminal(),cols = core.cols,rows = core.rows-1
        let scale = host.window!.backingScaleFactor,size = terminal.bounds.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*scale),pixelsHigh:Int(size.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let context = NSGraphicsContext(bitmapImageRep:bitmap)!
        var feedSamples: [Double] = [],drawSamples: [Double] = []
        let frameCount = 120
        func frame(_ index: Int) {
            var text = "\u{1b}[H"
            for row in 0..<rows {
                for col in 0..<cols {
                    let n = index*7919+row*cols+col,r = n%256,g = (n/256)%256,b = (n*13)%256
                    text += "\u{1b}[38;2;\(r);\(g);\(b)m\u{1b}[48;2;\((r+47)%256);\((g+101)%256);\((b+19)%256)m▀"
                }
                text += "\u{1b}[0m\r\n"
            }
            text += "\u{1b}[0mframe \(index)\u{1b}[K"
            let start = ProcessInfo.processInfo.systemUptime
            terminal.feed(text:text)
            let fed = ProcessInfo.processInfo.systemUptime
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = context
            context.cgContext.saveGState();context.cgContext.scaleBy(x:scale,y:scale)
            terminal.draw(terminal.bounds)
            context.cgContext.restoreGState();NSGraphicsContext.restoreGraphicsState()
            if index >= 10 { feedSamples.append((fed-start)*1000);drawSamples.append((ProcessInfo.processInfo.systemUptime-fed)*1000) }
            if index+1 < frameCount { DispatchQueue.main.async { frame(index+1) };return }
            func stats(_ samples: [Double]) -> [String:Double] {
                let sorted = samples.sorted()
                return ["meanMilliseconds":samples.reduce(0,+)/Double(samples.count),"p95Milliseconds":sorted[Int(Double(sorted.count-1)*0.95)]]
            }
            let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!)
            let measures: [String:Any] = ["cols":cols,"rows":rows,"frames":frameCount,"feed":stats(feedSamples),"draw":stats(drawSamples)]
            try! JSONSerialization.data(withJSONObject:measures,options:[.prettyPrinted,.sortedKeys]).write(to:output.deletingLastPathComponent().appendingPathComponent("AnimationMeasurements.json"))
            try! bitmap.representation(using:.png,properties:[:])!.write(to:output.deletingLastPathComponent().appendingPathComponent("Animation.png"))
            let checks = ["animationReachedLastFrame":core.exportPlainText().contains("frame \(frameCount-1)"),"animationGridSizePreserved":core.cols == cols && core.rows == rows+1]
            try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output)
            print("ANIMATION_BENCH",measures)
            app.windows.forEach { $0.stop() };exit(checks.values.allSatisfy { $0 } ? 0:1)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { frame(0) }
    }
}


/// Optional local-program probe: exercise the ordinary PTY and on-screen draw
/// path while measuring how promptly the main run loop can service input.
private final class LiveAnimationChecks {
    let app: App
    var ticks: [Double] = []
    var timer: Timer?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var checks: [String:Bool] = [:]
    init(_ app: App) { self.app = app }
    func run() {
        guard let command = ProcessInfo.processInfo.environment["MOTH_TEST_ANIMATION_COMMAND"],let host = app.active else { exit(2) }
        var config = Configuration();config.background.style = "solid";config.cursor.animation = "noblink"
        app.config = config;app.applyAppearance()
        host.window?.setContentSize(NSSize(width:1200,height:800));host.content.layoutSubtreeIfNeeded()
        let terminal = host.workspace.active.terminal
        terminal.sendUserText("stty -echo; \(ShellView.quotePath(command)); printf '\\nMOTH_ANIMATION_EXIT:%s\\n' \"$?\"\r")
        func waitFor(_ predicate: @escaping ()->Bool, _ remaining: Int, _ done: @escaping (Bool)->Void) {
            if predicate() { done(true);return }
            if remaining == 0 { done(false);return }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { waitFor(predicate,remaining-1,done) }
        }
        waitFor({ terminal.getTerminal().isCurrentBufferAlternate },200) { ready in
            self.checks["liveAnimationEnteredAlternateScreen"] = ready
            guard ready else { self.finish();return }
            self.lastTick = ProcessInfo.processInfo.systemUptime
            self.timer = Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true) { _ in
                let now = ProcessInfo.processInfo.systemUptime
                self.ticks.append((now-self.lastTick)*1000);self.lastTick = now
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+10) {
                self.timer?.invalidate();self.timer = nil
                if let bitmap = terminal.bitmapImageRepForCachingDisplay(in:terminal.bounds) {
                    terminal.cacheDisplay(in:terminal.bounds,to:bitmap)
                    let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!).deletingLastPathComponent()
                    try? bitmap.representation(using:.png,properties:[:])?.write(to:output.appendingPathComponent("LiveAnimation.png"))
                }
                terminal.sendUserText("q")
                waitFor({ !terminal.getTerminal().isCurrentBufferAlternate && terminal.getTerminal().exportPlainText().contains("MOTH_ANIMATION_EXIT:0") },200) { exited in
                    self.checks["liveAnimationRespondsToQuitAndRestoresShell"] = exited;self.finish()
                }
            }
        }
    }
    func finish() {
        let output = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_TEST_RESULT"]!)
        let sorted = ticks.sorted()
        let metrics: [String:Any] = ["ticks":ticks.count,"meanIntervalMilliseconds":ticks.isEmpty ? 0:ticks.reduce(0,+)/Double(ticks.count),"p95IntervalMilliseconds":sorted.isEmpty ? 0:sorted[Int(Double(sorted.count-1)*0.95)],"maximumIntervalMilliseconds":sorted.last ?? 0]
        try! JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:output.deletingLastPathComponent().appendingPathComponent("LiveAnimationMeasurements.json"))
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print("LIVE_ANIMATION",metrics,checks)
        app.windows.forEach { $0.stop() };exit(checks.values.allSatisfy { $0 } ? 0:1)
    }
}


private enum HeldKeyPTYChecks {
    static func run(_ app: App, done: @escaping ([String:Bool])->Void) {
        guard let terminal = app.active?.workspace.active.terminal else { done(["heldKeysReachPTY":false]);return }
        let cases: [(String,UInt16,NSEvent.ModifierFlags,String)] = [
            ("a",0,[],"a"),("A",0,.shift,"A"),(" ",49,[]," "),
            ("\u{7f}",51,[],"\u{7f}"),("\u{f703}",124,[.function,.numericPad],"\u{1b}[C"),("d",2,.control,"\u{4}")]
        let expected = cases.map { String(repeating:$0.3,count:12) }.joined()
        let hex = expected.utf8.map { String(format:"%02x",$0) }.joined()
        terminal.sendUserText("stty -echo -icanon min 1 time 0; printf '\\033[?1l\\nMOTH_HELD_%s\\n' READY; /usr/bin/od -An -v -tx1 -N\(expected.utf8.count); stty echo icanon; printf '\\nMOTH_HELD_%s\\n' DONE\r")
        func wait(_ marker: String, _ remaining: Int, _ completion: @escaping (Bool)->Void) {
            if terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains(marker) { completion(true);return }
            guard remaining > 0 else { completion(false);return }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { wait(marker,remaining-1,completion) }
        }
        wait("MOTH_HELD_READY",120) { ready in
            guard ready else { print("HELD_KEY_PTY_NOT_READY",terminal.getTerminal().exportPlainText());done(["heldKeysReachPTY":false]);return }
            for (characters,code,flags,_) in cases {
                for index in 0..<12 {
                    let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:Double(index)/30,windowNumber:terminal.window!.windowNumber,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:index > 0,keyCode:code)!
                    terminal.keyDown(with:event)
                }
            }
            wait("MOTH_HELD_DONE",120) { complete in
                let output = terminal.getTerminal().exportPlainText().components(separatedBy:.whitespacesAndNewlines).joined()
                if !complete || !output.contains(hex) { print("HELD_KEY_PTY",complete,"expected",hex,"actual",output) }
                done(["heldKeysReachPTY":complete && output.contains(hex)])
            }
        }
    }
}
