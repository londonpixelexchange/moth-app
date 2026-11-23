// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import SwiftTerm
import QuartzCore
import Metal
import ImageIO
import simd
import Darwin

/// Keep the user's divider proportions when the window or an ancestor pane resizes.
final class TerminalSplitView: NSSplitView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let oldLength = (isVertical ? oldSize.width : oldSize.height)-dividerThickness
        let fraction = arrangedSubviews.count == 2 && oldLength > 0 ? (isVertical ? arrangedSubviews[0].frame.width : arrangedSubviews[0].frame.height)/oldLength : nil
        super.resizeSubviews(withOldSize:oldSize)
        let length = (isVertical ? bounds.width : bounds.height)-dividerThickness
        if let fraction, fraction > 0, fraction < 1, length > 0 { setPosition(length*fraction,ofDividerAt:0) }
    }
}

class ShellView: LocalProcessTerminalView {
    var session: SessionConnection?
    enum RecoveryPresentation { case restoring, ready, disconnected }
    var recoveryPresentationChanged: ((RecoveryPresentation)->Void)?
    var acceptsInputDuringSessionStartup = false
    var replayingSession = false
    var suppressSessionReplies = false
    var replayAcknowledgement = Data()
    var replayResponses: [UInt8] = []
    var recoveryHistoryTruncated = false
    var sessionEnded = false
    var readOnly = false
    var advanced = Configuration.Advanced()
    private var userInputDepth = 0
    private var encodingInputDepth = 0
    private var transcoder = TerminalTranscoder("UTF-8")
    private(set) var lastEncodingError: String?
    var textEncoding: String { transcoder.id }
    func configureTextEncoding(_ id: String) {
        guard id != transcoder.id else { return }
        let tail = transcoder.decode([],final:true); if !tail.isEmpty { feed(byteArray:tail[...]) }
        transcoder = TerminalTranscoder(id); lastEncodingError = nil; toolTip = nil
    }
    override func dataReceived(slice: ArraySlice<UInt8>) {
        if MothBenchmark.enabled { MothBenchmark.recordReceivedBytes(slice.count) }
        if transcoder.id == "UTF-8" { super.dataReceived(slice:slice); return }
        let decoded = transcoder.decode(slice); if !decoded.isEmpty { super.dataReceived(slice:decoded[...]) }
    }
    override func processTerminated(_ source: LocalProcess,exitCode: Int32?) {
        let tail = transcoder.decode([],final:true); if !tail.isEmpty { feed(byteArray:tail[...]) }
        super.processTerminated(source,exitCode:exitCode)
    }
    func sendUserText(_ text: String) {
        encodingInputDepth += 1; defer { encodingInputDepth -= 1 }; send(txt:text)
    }
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !suppressSessionReplies else { return }
        if replayingSession && !(acceptsInputDuringSessionStartup && (userInputDepth > 0 || encodingInputDepth > 0)) {
            // Historical queries that were not answered before disconnection are
            // replied to once replay has finished, without filling the IPC write queue.
            if replayResponses.count+data.count <= 65536 { replayResponses.append(contentsOf:data) }
            return
        }
        if userInputDepth > 0 { MacroRecorder.shared.capture(data,source:self) }
        if transcoder.id == "UTF-8" { super.send(source:source,data:data); return }
        if userInputDepth > 0 || encodingInputDepth > 0 {
            guard let encoded = transcoder.encode(data) else { lastEncodingError = "This text cannot be represented in \(TerminalTextEncoding.title(transcoder.id)). Choose UTF-8 to send it."; toolTip = lastEncodingError; NSSound.beep(); return }
            lastEncodingError = nil; toolTip = nil; super.send(source:source,data:encoded[...])
        } else { super.send(source:source,data:data) }
    }
    override func insertText(_ string: Any,replacementRange: NSRange) {
        guard !readOnly else { return }; userInputDepth += 1; defer { userInputDepth -= 1 }
        super.insertText(string,replacementRange:replacementRange)
    }
    override func paste(_ sender: Any) {
        guard !readOnly else { return }; userInputDepth += 1; defer { userInputDepth -= 1 }; super.paste(sender)
    }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with:event)
        if !readOnly,advanced.copyOnSelect,!(getSelection() ?? "").isEmpty { copy(self) }
    }
    override var acceptsFirstResponder: Bool { !readOnly && super.acceptsFirstResponder }
    var keyboardSound = Configuration.KeyboardSound()
    override func keyDown(with event: NSEvent) {
        guard !readOnly else { return }
        if KeyboardSoundPlayer.shouldPlay(event) { KeyboardSoundPlayer.shared.play(keyboardSound) }
        userInputDepth += 1; defer { userInputDepth -= 1 }
        super.keyDown(with:event)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        getTerminal().allowsApplicationColumnModeChanges = false
        fontVariantResolver = FontTypography.styledFont
        wantsLayer = true
        registerForDraggedTypes([.fileURL,.mothTab,.mothPane])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        getTerminal().allowsApplicationColumnModeChanges = false
        fontVariantResolver = FontTypography.styledFont
        wantsLayer = true
        registerForDraggedTypes([.fileURL,.mothTab,.mothPane])
    }
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        return objects.map { $0 as URL }.filter(\.isFileURL)
    }
    static func quotePath(_ path: String) -> String {
        // Never send literal terminal control keys, even if they occur in a filename.
        if path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
            let escaped = path.unicodeScalars.map { scalar -> String in
                switch scalar.value {
                case 0...31, 127: return String(format: "\\x%02x", scalar.value)
                case 39: return "\\'"
                case 92: return "\\\\"
                default: return String(scalar)
                }
            }.joined()
            return "$'" + escaped + "'"
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static func fileDropText(from pasteboard: NSPasteboard) -> String? {
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return nil }
        return urls.map { quotePath($0.path) }.joined(separator: " ") + " "
    }
    @discardableResult
    func insertFileDrop(from pasteboard: NSPasteboard) -> Bool {
        guard !readOnly,let text = Self.fileDropText(from:pasteboard) else { return false }
        userInputDepth += 1; defer { userInputDepth -= 1 }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        if getTerminal().bracketedPasteMode { send(txt: "\u{1b}[200~") }
        send(txt: text)
        if getTerminal().bracketedPasteMode { send(txt: "\u{1b}[201~") }
        return true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.availableType(from:[.mothPane]) != nil { return (superview as? Pane)?.paneDragOperation(sender) ?? [] }
        if sender.draggingPasteboard.availableType(from:[.mothTab]) != nil { return (window?.windowController as? TerminalWindowController)?.tabDropOperation(sender.draggingPasteboard) ?? [] }
        return sender.draggingSourceOperationMask.contains(.copy) && Self.fileDropText(from: sender.draggingPasteboard) != nil ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !draggingEntered(sender).isEmpty }
    override func draggingExited(_ sender: NSDraggingInfo?) { (superview as? Pane)?.clearDropPreview() }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.availableType(from:[.mothPane]) != nil { return (superview as? Pane)?.acceptPaneDrop(sender) ?? false }
        if sender.draggingPasteboard.availableType(from:[.mothTab]) != nil { return (window?.windowController as? TerminalWindowController)?.acceptTabDrop(sender.draggingPasteboard) ?? false }
        return insertFileDrop(from:sender.draggingPasteboard)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(self)
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String,_ action: Selector,enabled: Bool = true,value: Any? = nil) {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; item.isEnabled = enabled; item.representedObject = value; menu.addItem(item)
        }
        if let link = link(at:event) {
            add("Open Link",#selector(openContextLink(_:)),value:link.link)
            add("Copy Link",#selector(copyContextLink(_:)),value:link.link); menu.addItem(.separator())
        }
        add("Copy",#selector(copy(_:)),enabled:!(getSelection() ?? "").isEmpty)
        add("Paste",#selector(paste(_:)),enabled:!readOnly && NSPasteboard.general.string(forType:.string) != nil)
        add("Select All",#selector(selectAll(_:))); menu.addItem(.separator())
        let owner = contextOwner
        add("Split Pane Right",#selector(contextSplitRight),enabled:owner.map { $0.1.panes.count < Workspace.maximumPanes && $0.2.bounds.width >= 420 } ?? false)
        add("Split Pane Below",#selector(contextSplitBelow),enabled:owner.map { $0.1.panes.count < Workspace.maximumPanes && $0.2.bounds.height >= 280 } ?? false)
        add(owner?.1.isPaneMaximized == true ? "Restore Split Layout":"Maximise Pane",#selector(contextMaximizePane),enabled:owner.map{$0.1.panes.count>1} ?? false)
        add("Move Pane to New Window",#selector(contextDetachPane),enabled:owner != nil)
        add("Close Pane",#selector(contextClosePane),enabled:owner != nil)
        return menu
    }
    private var contextOwner: (TerminalWindowController,Workspace,Pane)? {
        guard let pane = superview as? Pane,let controller = window?.windowController as? TerminalWindowController else { return nil }
        return controller.application.owner(ofPane:pane.id)
    }
    @objc private func openContextLink(_ item: NSMenuItem) { if let link = item.representedObject as? String { requestOpenLink(source:self,link:link,params:[:]) } }
    @objc private func copyContextLink(_ item: NSMenuItem) { if let link = item.representedObject as? String { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link,forType:.string) } }
    @objc private func contextSplitRight() { if let (controller,workspace,pane) = contextOwner { workspace.active = pane; workspace.split(vertical:true,config:controller.config) } }
    @objc private func contextSplitBelow() { if let (controller,workspace,pane) = contextOwner { workspace.active = pane; workspace.split(vertical:false,config:controller.config) } }
    @objc private func contextMaximizePane() { if let (_,workspace,pane)=contextOwner { workspace.active=pane;workspace.toggleMaximizePane() } }
    @objc private func contextDetachPane() { if let (controller,_,pane) = contextOwner { _ = controller.application.detachPane(pane.id,at:NSEvent.mouseLocation) } }
    @objc private func contextClosePane() { (superview as? Pane)?.onClose?() }

    var onBell: (() -> Void)?
    override func bell(source: Terminal) { if !replayingSession { onBell?() } }

    var focused: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        guard !readOnly else { return false }
        let result = super.becomeFirstResponder()
        if result { focused?() }
        return result
    }
    // Remote terminal content must not silently replace the system clipboard (OSC 52).
    override func clipboardCopy(source: TerminalView, content: Data) {
        guard !replayingSession,advanced.allowRemoteClipboard,content.count <= 1048576,let string = String(data:content,encoding:.utf8) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(string,forType:.string)
    }
}

enum ShellEnvironment {
    static func session(inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = inherited
        // GUI launchers and build tools use NO_COLOR for their own logs. A new
        // interactive terminal must advertise its own capabilities instead.
        env.removeValue(forKey: "NO_COLOR")
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Moth"
        env["TERM_PROGRAM_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }
}

/// A temporary decorative layer; it never participates in keyboard or mouse input.
final class BellPulseLayer: CALayer {
    private var generation = 0
    override init() { super.init(); opacity = 0; zPosition = 1000 }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    func stopPulse() {
        generation &+= 1; removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true); opacity = 0; CATransaction.commit()
    }
    func pulse(peak: Float, duration: Double) {
        stopPulse(); let token = generation
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            CATransaction.begin(); CATransaction.setDisableActions(true); opacity = peak; CATransaction.commit()
        } else {
            let animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = peak; animation.toValue = 0
            animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            add(animation, forKey: "visualBell")
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+duration) { [weak self] in
            guard let self, self.generation == token else { return }; self.stopPulse()
        }
    }
}

final class Pane: NSView, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let dragHandle = PaneDragHandle()
    let dropPreview = CALayer()
    let unavailableRecoveryID = UUID().uuidString
    let terminal = ShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    let label = NSTextField(labelWithString: "zsh")
    let dimensions = NSTextField(labelWithString: "")
    var changed: (() -> Void)?
    var title = "Shell"
    var ended = false
    var onFocus: (() -> Void)?
    var onBell: (() -> Void)?
    var onClose: (() -> Void)?
    var onExit: (() -> Void)?
    private var stopping = false
    let closeButton = NSButton()
    let recoveryIndicator = NSStackView()
    let recoveryMessage = NSTextField(labelWithString:"Restoring session…")
    private let recoverySpinner = NSProgressIndicator()
    private var terminalTop: NSLayoutConstraint!
    private var closeCenterX: NSLayoutConstraint!
    private var geometryObservers: [NSObjectProtocol] = []
    private var appliedANSI: [String]?
    private var appliedHistory: Int?
    private var logDirectory: String?
    private let logSession = UUID().uuidString
    let bellLayer = BellPulseLayer()
    private var bellConfig = Configuration.Bell()
    private var lastBell = -Double.infinity
    private(set) var bellSound: NSSound?
    override func layout() {
        super.layout()
        alignCloseControl()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bellLayer.frame = bounds.width > 6 && bounds.height > 6 ? bounds.insetBy(dx: 3, dy: 3) : .zero; CATransaction.commit()
    }
    private func alignCloseControl() {
        guard Thread.isMainThread else { DispatchQueue.main.async { [weak self] in self?.alignCloseControl() }; return }
        guard closeCenterX != nil,let scroller = terminal.subviews.first(where: { $0 is NSScroller }) else { return }
        let center = scroller.convert(scroller.bounds,to:self).midX
        if abs(closeCenterX.constant-center) > 0.1 { closeCenterX.constant = center; needsLayout = true }
    }
    deinit { geometryObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    private func ringBell() {
        guard Thread.isMainThread else { DispatchQueue.main.async { [weak self] in self?.ringBell() }; return }
        guard bellConfig.mode != "off" else { return }
        if bellConfig.badge { onBell?() }
        guard CACurrentMediaTime()-lastBell >= 0.2 else { return }
        lastBell = CACurrentMediaTime()
        if ["sound","both"].contains(bellConfig.mode) {
            bellSound?.stop()
            bellSound = bellConfig.sound.hasPrefix("/") ? NSSound(contentsOfFile: bellConfig.sound, byReference: true) : NSSound(named: NSSound.Name(bellConfig.sound))?.copy() as? NSSound
            bellSound?.volume = Float(bellConfig.volume); bellSound?.play()
        }
        if ["visual","both"].contains(bellConfig.mode) {
            if bellConfig.style == "window-border", let background = window?.contentView as? FlowBackgroundView {
                bellLayer.stopPulse()
                background.ringWindowBell(bellConfig, color: bellLayer.borderColor ?? terminal.caretColor.cgColor)
            } else {
                bellLayer.pulse(peak: Float(bellConfig.intensity * (bellConfig.style == "flash" ? 0.18 : 1)), duration: bellConfig.duration)
            }
        }
    }
    init(config: Configuration, start: Bool = true, recovering: String? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.fileURL,.mothTab,.mothPane])
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        closeButton.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"Close pane")
        closeButton.isBordered = false; closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self; closeButton.action = #selector(closeThisPane(_:)); closeButton.toolTip = "Close Pane (⌘W)"; closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false; addSubview(closeButton)
        dragHandle.paneID = id; dragHandle.image = NSImage(systemSymbolName:"line.3.horizontal",accessibilityDescription:"Move pane")
        dragHandle.isBordered = false; dragHandle.contentTintColor = .secondaryLabelColor
        dragHandle.toolTip = "Drag to move pane. Drop at an edge to split, or in the centre to swap."
        dragHandle.setAccessibilityLabel("Move pane"); dragHandle.translatesAutoresizingMaskIntoConstraints = false; addSubview(dragHandle)
        dropPreview.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        dropPreview.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        dropPreview.borderWidth = 1; dropPreview.cornerRadius = 5; dropPreview.isHidden = true; dropPreview.zPosition = 100
        layer?.addSublayer(dropPreview)
        terminalTop = terminal.topAnchor.constraint(equalTo:topAnchor,constant:10)
        closeCenterX = closeButton.centerXAnchor.constraint(equalTo:leadingAnchor,constant:bounds.width-20)
        NSLayoutConstraint.activate([
            dragHandle.trailingAnchor.constraint(equalTo:closeButton.leadingAnchor,constant:-6),dragHandle.centerYAnchor.constraint(equalTo:closeButton.centerYAnchor),dragHandle.widthAnchor.constraint(equalToConstant:16),dragHandle.heightAnchor.constraint(equalToConstant:16),
            closeCenterX, closeButton.topAnchor.constraint(equalTo:topAnchor,constant:4),closeButton.widthAnchor.constraint(equalToConstant:16),closeButton.heightAnchor.constraint(equalToConstant:16),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            terminalTop,
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200), heightAnchor.constraint(greaterThanOrEqualToConstant: 130)
        ])
        for view in [terminal] + terminal.subviews.filter({ $0 is NSScroller }) {
            view.postsFrameChangedNotifications = true
            geometryObservers.append(NotificationCenter.default.addObserver(forName:NSView.frameDidChangeNotification,object:view,queue:nil) { [weak self] _ in self?.alignCloseControl() })
        }
        bellLayer.opacity = 0; bellLayer.borderWidth = 3; bellLayer.cornerRadius = 6
        layer?.addSublayer(bellLayer)
        terminal.onBell = { [weak self] in self?.ringBell() }
        recoverySpinner.style = .spinning; recoverySpinner.controlSize = .small
        recoveryMessage.font = .systemFont(ofSize:13); recoveryMessage.textColor = .secondaryLabelColor
        recoveryIndicator.orientation = .horizontal; recoveryIndicator.alignment = .centerY; recoveryIndicator.spacing = 8
        recoveryIndicator.addArrangedSubview(recoverySpinner); recoveryIndicator.addArrangedSubview(recoveryMessage)
        recoveryIndicator.translatesAutoresizingMaskIntoConstraints = false; recoveryIndicator.isHidden = true; addSubview(recoveryIndicator)
        NSLayoutConstraint.activate([recoveryIndicator.centerXAnchor.constraint(equalTo:centerXAnchor),recoveryIndicator.centerYAnchor.constraint(equalTo:centerYAnchor),recoveryIndicator.leadingAnchor.constraint(greaterThanOrEqualTo:leadingAnchor,constant:16),recoveryIndicator.trailingAnchor.constraint(lessThanOrEqualTo:trailingAnchor,constant:-16)])
        terminal.recoveryPresentationChanged = { [weak self] state in
            guard let self else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            switch state {
            case .restoring:
                terminal.isHidden = true; recoveryIndicator.isHidden = false
                recoveryMessage.stringValue = "Restoring session…"; recoverySpinner.isHidden = false; recoverySpinner.startAnimation(nil)
            case .ready:
                recoverySpinner.stopAnimation(nil); recoveryIndicator.isHidden = true; terminal.isHidden = false
            case .disconnected:
                terminal.isHidden = true; recoveryIndicator.isHidden = false
                recoveryMessage.stringValue = "Session disconnected"; recoverySpinner.stopAnimation(nil); recoverySpinner.isHidden = true
            }
            CATransaction.commit()
            if case .ready = state { changed?(); if NSApp.isActive { (window?.windowController as? TerminalWindowController)?.finishInitialFocus() } }
        }
        terminal.processDelegate = self
        terminal.focused = { [weak self] in self?.onFocus?() }
        apply(config)
        if start {
            var env = ShellEnvironment.session(); env.merge(config.advanced.environment) { _,override in override }
            // Each session inherits the user's environment, never a hard-coded minimal PATH.
            let cwd = ProcessInspector.usableDirectory(config.advanced.workingDirectory) ?? FileManager.default.homeDirectoryForCurrentUser.path
            if recovering != nil || (SessionRecovery.enabled && config.advanced.sessionRecovery) {
                do {
                    let connection: SessionConnection
                    if let recovering { connection = try SessionRecovery.connect(recovering) }
                    else { let size = terminal.getWindowSize(); connection = try SessionRecovery.launch(shell:config.shell,args:config.advanced.loginShell ? ["-l"] : [],environment:env,directory:cwd,rows:Int(size.ws_row),cols:Int(size.ws_col)) }
                    terminal.beginSession(connection,restoring:recovering != nil)
                } catch {
                    if let recovering { SessionRecovery.removeRecord(recovering) }
                    ended = true; title = "Session unavailable"; terminal.readOnly = true
                    terminal.feed(text:"Session unavailable\r\n\r\n"+error.localizedDescription+"\r\n\r\nNo commands were rerun. Close this pane and open a new session to continue.")
                }
            } else {
                terminal.startProcess(executable: config.shell, args: config.advanced.loginShell ? ["-l"] : [], environment: env.map { "\($0.key)=\($0.value)" }, currentDirectory:cwd)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func apply(_ config: Configuration) {
        let (bg, fg, accent) = config.colors
        let shortcut = (config.keybindings["closePane"] ?? "").replacingOccurrences(of:"cmd+",with:"⌘").replacingOccurrences(of:"shift+",with:"⇧").replacingOccurrences(of:"alt+",with:"⌥").replacingOccurrences(of:"ctrl+",with:"⌃").uppercased()
        closeButton.toolTip = shortcut.isEmpty ? "Close Pane" : "Close Pane (\(shortcut))"
        bellLayer.stopPulse()
        (window?.contentView as? FlowBackgroundView)?.windowBellLayer.stopPulse()
        terminal.keyboardSound = config.keyboardSound
        terminal.advanced = config.advanced
        terminal.getTerminal().allowDoubleSizeLines = config.advanced.allowDoubleSizeLines
        terminal.configureTextEncoding(config.textEncoding)
        if logDirectory != config.advanced.logDirectory {
            logDirectory = config.advanced.logDirectory
            if config.advanced.logDirectory.isEmpty { terminal.setHostLogging(directory:nil) }
            else {
                let directory = URL(fileURLWithPath:config.advanced.logDirectory).appendingPathComponent("Moth-"+logSession)
                do { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); terminal.setHostLogging(directory:directory.path) }
                catch { terminal.setHostLogging(directory:nil); print("Moth output logging:",error.localizedDescription) }
            }
        }
        bellConfig = config.bell
        bellLayer.borderWidth = config.bell.style == "flash" ? 0 : config.bell.thickness
        bellLayer.backgroundColor = config.bell.style == "flash" ? (config.bell.color.isEmpty ? accent : NSColor.hex(config.bell.color)).cgColor : NSColor.clear.cgColor
        bellLayer.borderColor = (config.bell.color.isEmpty ? accent : NSColor.hex(config.bell.color)).cgColor
        if config.bell.mode == "off" {
            bellSound?.stop(); bellSound = nil
        }
        layer?.backgroundColor = NSColor.clear.cgColor
        let transparent = (config.background.style != "solid" || !config.background.paint.colors.isEmpty || config.windowBackgroundOpacity < 1) && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        terminal.nativeBackgroundColor = transparent ? bg.withAlphaComponent(0) : bg
        terminal.layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
        let ansi = config.resolvedANSIColors
        if appliedANSI != ansi {
            terminal.installColors(ansi.map { value in
                let rgb = Int(value,radix:16)!
                return SwiftTerm.Color(red:UInt16(((rgb >> 16) & 255)*257),green:UInt16(((rgb >> 8) & 255)*257),blue:UInt16((rgb & 255)*257))
            })
            appliedANSI = ansi
        }
        terminal.nativeForegroundColor = fg
        terminal.caretColor = config.cursor.paint.resolved(accent)[0]
        terminal.configureCursorPaint(type: config.cursor.paint.type, colors: config.cursor.paint.resolved(accent), angle: config.cursor.paint.angle)
        terminal.caretTextColor = bg
        terminal.selectedTextBackgroundColor = accent.withAlphaComponent(0.25)
        let desiredFont = FontTypography.font(config)
        if terminal.font.fontName != desiredFont.fontName || terminal.font.pointSize != desiredFont.pointSize || !terminal.font.fontDescriptor.isEqual(desiredFont.fontDescriptor) {
            terminal.font = desiredFont
        }
        terminal.configureTypography(lineHeight:config.typography.lineHeight,characterSpacing:config.typography.characterSpacing,ligatures:config.typography.ligatures,useBold:config.typography.useBold,useItalic:config.typography.useItalic,antialias:config.typography.antialias)
        terminal.configureCursor(shape: config.cursor.shape, animation: config.cursor.animation, period: config.cursor.period)
        terminal.getTerminal().setAlternateScreenScrollback(config.alternateScreenScrollback)
        terminal.optionAsMetaKey = config.optionAsMeta
        if appliedHistory != config.scrollback { terminal.getTerminal().changeHistorySize(config.scrollback); appliedHistory = config.scrollback }
        terminal.needsDisplay = true
    }
    func applyForTransfer(_ config: Configuration) {
        var config = config
        // Adopting a window's appearance must not shrink the existing history.
        config.scrollback = max(config.scrollback,appliedHistory ?? config.scrollback)
        apply(config)
    }
    @objc func closeThisPane(_ sender: Any?) { onClose?() }
    func showSplitControl(_ visible: Bool) { closeButton.isHidden = !visible; dragHandle.isHidden = !visible; terminalTop.constant = visible ? 24 : 10 }
    func setActive(_ active: Bool) { label.textColor = active ? terminal.caretColor : .secondaryLabelColor; label.stringValue = "\(active ? "●" : "○")  \(title)" }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { dimensions.stringValue = "\(newCols) × \(newRows)"; if !terminal.replayingSession { changed?() } }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Late OSC title messages must not replace a retained session’s exit status.
        guard !ended else { return }; self.title = String(title.prefix(120)); if !terminal.replayingSession { changed?() }
    }
    var localWorkingDirectory: String? {
        guard !ended,terminal.process.running else { return nil }
        return ProcessInspector.workingDirectory(of:terminal.process.shellPid)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Remote OSC 7 paths must not become local launch directories.
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard Thread.isMainThread else { DispatchQueue.main.async { [weak self] in self?.processTerminated(source:source,exitCode:exitCode) }; return }
        guard !ended else { return }
        ended = true; title = "Exited · \(exitCode.map(String.init) ?? "unknown")"; changed?()
        // Defer removal until the PTY delegate has finished updating its state.
        DispatchQueue.main.async { [weak self] in guard let self,!self.stopping else { return }; self.onExit?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { terminal.menu(for:event) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDropPreview() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { terminal.draggingEntered(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { terminal.draggingUpdated(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { terminal.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { terminal.performDragOperation(sender) }
    func closeWarningPrograms(_ policy: Configuration.CloseConfirmation) -> [String] {
        guard policy.enabled, terminal.process.running else { return [] }
        return ProcessInspector.assess(shellPID: terminal.process.shellPid, foregroundGroup: tcgetpgrp(terminal.process.childfd)).requiringConfirmation(policy)
    }
    func stop() { stopping = true; if terminal.process.running { terminal.terminate() } }
}

final class Workspace {
    static let maximumPanes = 9
    let id = UUID()
    let root = NSView()
    var panes: [Pane] = []
    var active: Pane!
    var changed: (() -> Void)?
    var bell: (() -> Void)?
    var closeRequested: ((Pane) -> Void)?
    var sessionEnded: ((Pane) -> Void)?
    private let startProcesses: Bool
    private var restoredFractions: [ObjectIdentifier:Double] = [:]
    private var recoveringSessions: [String] = []
    private var maximizedLayout: NSView?
    private var maximizedPlaceholder: NSView?
    private var maximizedPane: Pane?
    private var maximizedFractions: [ObjectIdentifier:Double] = [:]
    var isPaneMaximized: Bool { maximizedPane != nil }
    var orderedPanes: [Pane] {
        func leaves(_ view: NSView) -> [Pane] {
            if view === maximizedPlaceholder,let pane = maximizedPane { return [pane] }
            if let pane = view as? Pane { return [pane] }; return view.subviews.flatMap(leaves)
        }
        if let maximizedLayout { return leaves(maximizedLayout) }
        return root.subviews.flatMap(leaves)
    }
    var title: String { active?.title ?? "Shell" }
    init(config: Configuration, startProcesses: Bool = true, saved: SavedTab? = nil, inheritedDirectory: String? = nil, adopting: Pane? = nil) {
        self.startProcesses = startProcesses
        if let adopting { panes.append(adopting); bind(adopting); mount(adopting,in:root); active = adopting }
        else if let saved {
            recoveringSessions = saved.sessions ?? []
            let view = restoredView(saved.root,config:config); mount(view,in:root)
            active = panes[min(saved.activePane,panes.count-1)]
        } else { let pane = makePane(config,directory:inheritedDirectory); mount(pane,in:root); active = pane }
        highlight()
    }
    private func restoredView(_ node: SavedSplit,config: Configuration) -> NSView {
        switch node {
        case .pane:return makePane(config)
        case let .split(vertical,fraction,first,second):
            let split = TerminalSplitView(); split.isVertical = vertical; split.dividerStyle = .thin
            for child in [first,second] { let view = restoredView(child,config:config); view.translatesAutoresizingMaskIntoConstraints = true; split.addArrangedSubview(view) }
            restoredFractions[ObjectIdentifier(split)] = fraction; return split
        }
    }
    func applyRestoredGeometry() {
        guard !restoredFractions.isEmpty,root.bounds.width > 0,root.bounds.height > 0 else { return }
        root.layoutSubtreeIfNeeded()
        func fit(_ view: NSView) {
            if let split = view as? NSSplitView {
                split.adjustSubviews()
                if let fraction = restoredFractions[ObjectIdentifier(split)] { let length = (split.isVertical ? split.bounds.width : split.bounds.height)-split.dividerThickness; split.setPosition(length*fraction,ofDividerAt:0) }
            }
            for child in view.subviews { fit(child) }
        }
        fit(root); restoredFractions.removeAll(); root.layoutSubtreeIfNeeded()
    }
    func savedTab() throws -> SavedTab {
        var leaves: [Pane] = []
        func capture(_ view: NSView) throws -> SavedSplit {
            if view === maximizedPlaceholder,let pane = maximizedPane { leaves.append(pane);return .pane }
            if let pane = view as? Pane { leaves.append(pane); return .pane }
            guard let split = view as? NSSplitView,split.arrangedSubviews.count == 2 else { throw Configuration.invalid("Cannot save an incomplete split layout.") }
            let length = (split.isVertical ? split.bounds.width : split.bounds.height)-split.dividerThickness
            let size = split.isVertical ? split.arrangedSubviews[0].frame.width : split.arrangedSubviews[0].frame.height
            let fraction=maximizedFractions[ObjectIdentifier(split)] ?? restoredFractions[ObjectIdentifier(split)] ?? Double(size/max(1,length))
            return .split(vertical:split.isVertical,fraction:max(0.05,min(0.95,fraction)),first:try capture(split.arrangedSubviews[0]),second:try capture(split.arrangedSubviews[1]))
        }
        guard let view = maximizedLayout ?? root.subviews.first else { throw Configuration.invalid("Cannot save an empty tab.") }
        let node = try capture(view); return SavedTab(root:node,activePane:leaves.firstIndex(where: { $0 === active }) ?? 0)
    }
    func makePane(_ config: Configuration,directory: String? = nil) -> Pane {
        var launchConfig = config
        if config.advanced.inheritWorkingDirectory,let directory = ProcessInspector.usableDirectory(directory) { launchConfig.advanced.workingDirectory = directory }
        let recovering = recoveringSessions.isEmpty ? nil : recoveringSessions.removeFirst()
        let pane = Pane(config: launchConfig,start:startProcesses,recovering:recovering)
        panes.append(pane); bind(pane)
        return pane
    }
    func bind(_ pane: Pane) {
        pane.onFocus = { [weak self, weak pane] in guard let self, let pane else { return }; self.active = pane; self.highlight(); self.changed?() }
        pane.onBell = { [weak self] in self?.bell?() }
        pane.onClose = { [weak self, weak pane] in guard let pane else { return }; self?.closeRequested?(pane) }
        pane.onExit = { [weak self,weak pane] in guard let pane else { return }; self?.sessionEnded?(pane) }
        pane.changed = { [weak self] in self?.highlight(); self?.changed?() }
    }
    func mount(_ view: NSView, in host: NSView) {
        host.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor), view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
    }
    func splitSize(of pane:Pane)->NSSize {
        if pane === maximizedPane,let placeholder=maximizedPlaceholder { return placeholder.frame.size }
        return pane.bounds.size
    }
    func toggleMaximizePane() {
        if isPaneMaximized { restoreSplitLayout() } else if let active { maximizePane(active) }
    }
    private func maximizePane(_ pane:Pane) {
        guard panes.count > 1,panes.contains(where:{$0 === pane}),let layout=root.subviews.first else { return }
        applyRestoredGeometry();root.layoutSubtreeIfNeeded()
        func remember(_ view:NSView) {
            if let split=view as? NSSplitView,split.arrangedSubviews.count==2 {
                let length=(split.isVertical ? split.bounds.width:split.bounds.height)-split.dividerThickness
                let first=split.arrangedSubviews[0].frame.size
                maximizedFractions[ObjectIdentifier(split)]=Double((split.isVertical ? first.width:first.height)/max(1,length))
            }
            view.subviews.forEach(remember)
        }
        remember(layout)
        let placeholder=NSView(frame:pane.frame)
        Self.replaceSlot(pane,with:placeholder)
        layout.removeFromSuperview()
        maximizedLayout=layout;maximizedPlaceholder=placeholder;maximizedPane=pane
        active=pane;mount(pane,in:root);root.layoutSubtreeIfNeeded();highlight()
        pane.window?.makeFirstResponder(pane.terminal);changed?()
    }
    func restoreSplitLayout() {
        guard let layout=maximizedLayout,let placeholder=maximizedPlaceholder,let pane=maximizedPane else { return }
        pane.removeFromSuperview();Self.replaceSlot(placeholder,with:pane)
        maximizedLayout=nil;maximizedPlaceholder=nil;maximizedPane=nil
        restoredFractions.merge(maximizedFractions) { _,saved in saved };maximizedFractions.removeAll()
        mount(layout,in:root);root.layoutSubtreeIfNeeded();applyRestoredGeometry();highlight()
        active?.window?.makeFirstResponder(active.terminal);changed?()
    }
    func focusPane(_ pane:Pane) {
        guard panes.contains(where:{$0 === pane}) else { return }
        let keepMaximized=isPaneMaximized
        if keepMaximized { restoreSplitLayout() }
        active=pane
        if keepMaximized { maximizePane(pane) } else { highlight();pane.window?.makeFirstResponder(pane.terminal);changed?() }
    }
    func split(vertical: Bool, config: Configuration) {
        restoreSplitLayout()
        guard panes.count < Self.maximumPanes, let old = active, let parent = old.superview else { NSSound.beep(); return }
        // Replace a leaf with a nested split, preserving the existing PTY and scrollback.
        guard vertical ? old.bounds.width >= 420 : old.bounds.height >= 280 else { NSSound.beep(); return }
        let split = TerminalSplitView(frame:old.frame); split.isVertical = vertical; split.dividerStyle = .thin
        if let parentSplit = parent as? NSSplitView {
            let frames = parentSplit.arrangedSubviews.map { ($0,$0.frame) }
            let index = parentSplit.arrangedSubviews.firstIndex(of:old)!
            old.removeFromSuperview(); split.translatesAutoresizingMaskIntoConstraints = true
            parentSplit.insertArrangedSubview(split,at:index)
            for (view,frame) in frames where view !== old { view.frame = frame }
            split.frame = frames[index].1
        } else { old.removeFromSuperview(); mount(split,in:parent) }
        let next = makePane(config,directory:old.localWorkingDirectory)
        old.translatesAutoresizingMaskIntoConstraints = true
        next.translatesAutoresizingMaskIntoConstraints = true
        split.addArrangedSubview(old); split.addArrangedSubview(next)
        root.layoutSubtreeIfNeeded()
        (parent as? NSSplitView)?.adjustSubviews()
        split.adjustSubviews()
        split.setPosition((vertical ? split.bounds.width : split.bounds.height) / 2, ofDividerAt: 0)
        active = next; highlight(); next.window?.makeFirstResponder(next.terminal)
    }
    func closeActive() { if let active { close(active) } }
    func close(_ closing: Pane) { if detach(closing) { closing.stop() } }
    @discardableResult func detach(_ closing: Pane) -> Bool {
        restoreSplitLayout()
        guard panes.count > 1, let index = panes.firstIndex(of:closing) else { return false }
        let wasActive = closing === active
        var container = closing.superview as? NSSplitView
        closing.removeFromSuperview(); panes.removeAll { $0 === closing }
        while let split = container,split.arrangedSubviews.count < 2 {
            guard let parent = split.superview else { break }
            let replacedFrame = split.frame
            let sibling = split.arrangedSubviews.first
            let parentSplit = parent as? NSSplitView
            let frames = parentSplit?.arrangedSubviews.map { ($0,$0.frame) } ?? []
            let insertion = parentSplit?.arrangedSubviews.firstIndex(of:split) ?? 0
            sibling?.removeFromSuperview(); split.removeFromSuperview()
            if let sibling {
                if let parentSplit {
                    sibling.translatesAutoresizingMaskIntoConstraints = true; sibling.frame = replacedFrame
                    parentSplit.insertArrangedSubview(sibling,at:insertion)
                    for (view,frame) in frames where view !== split { view.frame = frame }
                    sibling.frame = replacedFrame
                }
                else { mount(sibling,in:parent) }
            }
            container = parentSplit
        }
        if wasActive { active = panes[min(index,panes.count-1)] }; highlight()
        root.layoutSubtreeIfNeeded()
        func fit(_ view: NSView) { if let split = view as? NSSplitView { split.adjustSubviews() }; for child in view.subviews { fit(child) } }
        fit(root); root.layoutSubtreeIfNeeded()
        if wasActive { active.window?.makeFirstResponder(active.terminal) }; changed?(); return true
    }
    func highlight() { for pane in panes { pane.setActive(pane === active); pane.showSplitControl(panes.count > 1) } }
    func stop() { panes.forEach { $0.stop() } }
}

private final class WindowFrostView: NSVisualEffectView {
    // Decorative glass must not intercept shell input, file drops or window controls.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A continuous, domain-warped colour field, rendered by native Metal.
/// Bounded-resolution frames are produced away from terminal input and drawing.
class FlowBackgroundView: NSView {
    let windowBellLayer = BellPulseLayer()
    private let field = CALayer()
    private let metalField = CAMetalLayer()
    private(set) var presentedFrames = 0
    var onFramePresented: ((MTLTexture,Double)->Void)?
    private let backdrop = CALayer()
    let pictureLayer = CALayer()
    private final class Picture: NSObject { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let pictures: NSCache<NSString,Picture> = { let cache = NSCache<NSString,Picture>(); cache.countLimit = 4; cache.totalCostLimit = 128*1024*1024; return cache }()
    static func loadBackgroundImage(_ path: String) -> CGImage? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath:(path as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath:url.path) else { return nil }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path):\(modified):\(attributes[.size] ?? "")" as NSString
        if let cached = pictures.object(forKey:key) { return cached.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:4096,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
        pictures.setObject(Picture(image),forKey:key,cost:image.width*image.height*4); return image
    }
    let tint = CAGradientLayer()
    let borderPaintLayer = CAGradientLayer()
    private let borderMask = CALayer()
    let frost: NSVisualEffectView = WindowFrostView()
    let backgroundSurface = BackgroundTintSurface()
    var backgroundOpacity: Float { backdrop.opacity }
    var backdropIsOnTintSurface: Bool { backdrop.superlayer === backgroundSurface.layer }
    private var config = Configuration()
    private var timer: Timer?
    private var paused = false
    private var systemSleeping = false
    private var screensSleeping = false
    private var sessionInactive = false
    private var activityObservers:[(NotificationCenter,NSObjectProtocol)] = []
    private var windowObservers:[NSObjectProtocol] = []
    private var inFlight = false
    private var revision = 0
    private var elapsed: Double = 0
    private var lastTick = CACurrentMediaTime()
    private static let queue = DispatchQueue(label: "com.thom.moth.background", qos: .utility)
    private static let device = MTLCreateSystemDefaultDevice()
    private static let commands = device?.makeCommandQueue()
    // Original field shader: no stacked lens silhouettes, radial spot centres,
    // or repeating stripe masks. Two smooth warps refract a broad colour volume.
    private static let pipeline: MTLComputePipelineState? = {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: shader, options: nil)
            guard let function = library.makeFunction(name: "mothField") else { return nil }
            return try device.makeComputePipelineState(function: function)
        } catch { NSLog("Moth background shader: %@", error.localizedDescription); return nil }
    }()
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void mothField(texture2d<float, access::write> image [[texture(0)]],
                          constant float4 *settings [[buffer(0)]], uint2 pixel [[thread_position_in_grid]]) {
        if (pixel.x >= image.get_width() || pixel.y >= image.get_height()) return;
        float2 size = float2(image.get_width(), image.get_height());
        // Keep native image coordinates increasing upward for Fire advection.
        float2 coord = float2(pixel.x, size.y - float(pixel.y)) + 0.5;
        float t = settings[0].x, seed = settings[0].w;
        float3 a = settings[1].xyz, b = settings[2].xyz, c = settings[3].xyz;
        float2 uv = coord / size;
        float2 p = (uv - 0.5) * float2(size.x / size.y, 1.0);
        float2 q = p;
        float drift = t * 0.17;
        float2 bend = float2(
            sin(q.y * 2.2 + drift + seed) + 0.37 * cos(q.x * 1.7 - q.y * 1.1 - drift),
            cos(q.x * 1.6 - drift * 0.8) + 0.32 * sin(q.y * 2.1 + drift));
        float2 r = q + bend * 0.58;
        float refraction = sin(r.x * 1.8 + r.y * 1.1 + seed + drift)
                         + 0.45 * cos(r.y * 2.5 - r.x * 0.7 - drift * 0.6);
        float pool = 0.5 + 0.5 * sin(refraction * 1.45 + r.y * 0.6);
        float light = 0.5 + 0.5 * cos(r.x * 1.15 - r.y * 1.4 + refraction * 0.65 + seed);
        float3 color = mix(a, b, smoothstep(0.08, 0.92, pool));
        color = mix(color, c, smoothstep(0.12, 0.97, light) * 0.82);
        color = mix(color, settings[4].xyz, settings[4].w * (0.5 + 0.5 * sin(refraction + r.x)) * 0.6);
        color = mix(color, settings[5].xyz, settings[5].w * (0.5 + 0.5 * cos(refraction - r.y)) * 0.6);
        color = mix(color, settings[6].xyz, settings[6].w * (0.5 + 0.5 * sin(r.x - r.y)) * 0.6);
        color *= 0.52 + light * 0.48;
        // Sub-byte stationary dither prevents quantisation contours in dark fields.
        float dither = fract(sin(dot(coord, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
        image.write(float4(color + dither / 255.0, 1.0), pixel);
    }
    """
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        registerForDraggedTypes([.mothTab])
        frost.blendingMode = .behindWindow; frost.material = .underWindowBackground
        frost.state = .active; frost.autoresizingMask = [.width, .height]
        frost.isHidden = true; frost.wantsLayer = true
        addSubview(frost, positioned: .below, relativeTo: nil)
        backgroundSurface.wantsLayer = true; backgroundSurface.autoresizingMask = [.width,.height]
        addSubview(backgroundSurface,positioned:.above,relativeTo:frost)
        backgroundSurface.layer?.addSublayer(backdrop); backdrop.addSublayer(tint); backdrop.addSublayer(pictureLayer); backdrop.addSublayer(field)
        backdrop.masksToBounds = true
        layer?.addSublayer(borderPaintLayer); borderPaintLayer.mask = borderMask; borderPaintLayer.zPosition = 999
        layer?.addSublayer(windowBellLayer)
        field.contentsGravity = .resize; field.magnificationFilter = .linear
        metalField.device = Self.device; metalField.pixelFormat = .bgra8Unorm
        metalField.framebufferOnly = false; metalField.maximumDrawableCount = 2
        metalField.allowsNextDrawableTimeout = true; metalField.isOpaque = true
        metalField.colorspace = CGColorSpace(name:CGColorSpace.sRGB)
        metalField.isHidden = true; field.addSublayer(metalField)
        observeActivity()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { (window?.windowController as? TerminalWindowController)?.tabDropOperation(sender.draggingPasteboard) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { (window?.windowController as? TerminalWindowController)?.acceptTabDrop(sender.draggingPasteboard) ?? false }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        timer?.invalidate()
        activityObservers.forEach{$0.0.removeObserver($0.1)}
        windowObservers.forEach{NotificationCenter.default.removeObserver($0)}
    }
    private func observeActivity() {
        let appCenter=NotificationCenter.default
        for name in [NSApplication.didHideNotification,NSApplication.didUnhideNotification] {
            let token=appCenter.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.updateTimer()}
            activityObservers.append((appCenter,token))
        }
        let workspace=NSWorkspace.shared.notificationCenter
        func observe(_ name:Notification.Name,_ change:@escaping (FlowBackgroundView)->Void) {
            let token=workspace.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in
                guard let self else{return};change(self);self.updateTimer()
            }
            activityObservers.append((workspace,token))
        }
        observe(NSWorkspace.willSleepNotification){$0.systemSleeping=true}
        observe(NSWorkspace.didWakeNotification){$0.systemSleeping=false}
        observe(NSWorkspace.screensDidSleepNotification){$0.screensSleeping=true}
        observe(NSWorkspace.screensDidWakeNotification){$0.screensSleeping=false}
        observe(NSWorkspace.sessionDidResignActiveNotification){$0.sessionInactive=true}
        observe(NSWorkspace.sessionDidBecomeActiveNotification){$0.sessionInactive=false}
    }
    private var motionActivityAllowed:Bool {
        guard !systemSleeping,!screensSleeping,!sessionInactive,!NSApp.isHidden,!isHiddenOrHasHiddenAncestor,
              let window,window.isVisible,!window.isMiniaturized else{return false}
        return window.occlusionState.contains(.visible)
    }
    private var visibleField: Bool { config.background.style == "flow" && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    private var moving: Bool { visibleField && config.background.animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !paused }
    func apply(_ config: Configuration) {
        self.config = config; revision += 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = NSColor.clear.cgColor
        backdrop.opacity = Float(config.windowBackgroundOpacity)
        (config.background.style == "solid" ? config.background.paint : Configuration.Paint()).apply(to: tint, fallback: config.colors.0)
        config.window.borderPaint.apply(to: borderPaintLayer, fallback: NSColor.hex(config.window.borderColor))
        frost.isHidden = !config.usesFrosting
        frost.alphaValue = CGFloat(config.window.frostIntensity)
        frost.frame = bounds; backgroundSurface.frame = bounds; backgroundSurface.layer?.frame = bounds; backgroundSurface.layer?.bounds = CGRect(origin:.zero,size:bounds.size); backdrop.frame = bounds; tint.frame = backdrop.bounds
        layer?.borderColor = NSColor.clear.cgColor
        layer?.borderWidth = 0; layer?.masksToBounds = true
        pictureLayer.contents = config.background.style == "image" ? Self.loadBackgroundImage(config.background.imagePath) : nil
        pictureLayer.contentsGravity = config.background.imageScale == "fit" ? .resizeAspect : .resizeAspectFill
        pictureLayer.opacity = Float(config.background.imageOpacity); pictureLayer.frame = backdrop.bounds
        field.opacity = Float(config.backgroundFieldOpacity)
        field.isHidden = !visibleField
        updateCornerGeometry(); layoutWindowBell(); field.frame = backdrop.bounds
        layoutMetalField()
        CATransaction.commit()
        // One synchronous bounded frame also supports static backgrounds and snapshots.
        setFrame(visibleField ? Self.render(config: config, size: bounds.size, time: elapsed) : nil)
        updateTimer()
    }
    private static func settings(config:Configuration,time:Double) -> [SIMD4<Float>] {
        let palette = config.background.resolvedColors
        let colors = (0..<6).map { index -> SIMD4<Float> in
            let color = NSColor.hex(palette[index % palette.count]).usingColorSpace(.sRGB)!
            return SIMD4(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), index < palette.count ? 1 : 0)
        }
        return [SIMD4<Float>(Float(time), 0, 0, 0.7)] + colors
    }
    private func layoutMetalField() {
        metalField.frame = field.bounds
        let scale = min(1,640/max(1,max(bounds.width,bounds.height)))
        let size = CGSize(width:max(32,Int(bounds.width*scale)),height:max(32,Int(bounds.height*scale)))
        if metalField.drawableSize != size { revision += 1; metalField.drawableSize = size }
    }
    static func render(config: Configuration, size: CGSize, time: Double) -> CGImage? {
        guard size.width > 0, size.height > 0, let device, let pipeline, let commands else { return nil }
        let scale = min(1, 640 / max(size.width, size.height))
        let width = max(32, Int(size.width*scale)), height = max(32, Int(size.height*scale))
        var settings = Self.settings(config:config,time:time)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite]; descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let command = commands.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline); encoder.setTexture(texture, index: 0)
        encoder.setBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride * settings.count, index: 0)
        let group = MTLSize(width: pipeline.threadExecutionWidth, height: max(1, pipeline.maxTotalThreadsPerThreadgroup / pipeline.threadExecutionWidth), depth: 1)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        if !device.hasUnifiedMemory, let blit = command.makeBlitCommandEncoder() { blit.synchronize(resource: texture); blit.endEncoding() }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        if MothBenchmark.enabled { MothBenchmark.recordGPU(seconds:command.gpuEndTime-command.gpuStartTime) }
        var bytes = Data(count: width*height*4)
        bytes.withUnsafeMutableBytes { buffer in texture.getBytes(buffer.baseAddress!, bytesPerRow: width*4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
    private func updateTimer() {
        guard moving,motionActivityAllowed else {
            if timer != nil { revision += 1 }
            timer?.invalidate();timer=nil;lastTick=CACurrentMediaTime();return
        }
        guard timer == nil else{return}
        lastTick=CACurrentMediaTime()
        let next = Timer(timeInterval: 1.0/20, repeats: true) { [weak self] _ in self?.tick() }
        next.tolerance = 0.012; RunLoop.main.add(next, forMode: .common); timer = next
    }
    private func tick() {
        guard moving,motionActivityAllowed else{updateTimer();return}
        let now = CACurrentMediaTime()
        elapsed += min(0.2, now-lastTick) * config.background.speed; lastTick = now
        guard moving, !inFlight, window?.isVisible == true, !bounds.isEmpty else { return }
        inFlight = true
        let revision = revision, config = config, time = elapsed, metalLayer = metalField
        Self.queue.async { [weak self] in
            autoreleasepool {
                guard let pipeline = Self.pipeline,let commands = Self.commands,
                      let drawable = metalLayer.nextDrawable(),let command = commands.makeCommandBuffer(),
                      let encoder = command.makeComputeCommandEncoder() else {
                    DispatchQueue.main.async { self?.inFlight = false }; return
                }
                var settings = Self.settings(config:config,time:time)
                encoder.setComputePipelineState(pipeline); encoder.setTexture(drawable.texture,index:0)
                encoder.setBytes(&settings,length:MemoryLayout<SIMD4<Float>>.stride*settings.count,index:0)
                let group = MTLSize(width:pipeline.threadExecutionWidth,height:max(1,pipeline.maxTotalThreadsPerThreadgroup/pipeline.threadExecutionWidth),depth:1)
                encoder.dispatchThreads(MTLSize(width:drawable.texture.width,height:drawable.texture.height,depth:1),threadsPerThreadgroup:group)
                encoder.endEncoding()
                command.addCompletedHandler { [weak self] command in
                    if MothBenchmark.enabled,command.status == .completed { MothBenchmark.recordGPU(seconds:command.gpuEndTime-command.gpuStartTime) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }; self.inFlight = false
                        guard command.status == .completed,self.revision == revision,self.moving,self.motionActivityAllowed else { return }
                        CATransaction.begin(); CATransaction.setDisableActions(true)
                        self.metalField.isHidden = false; drawable.present(); self.presentedFrames += 1
                        CATransaction.commit()
                        self.onFramePresented?(drawable.texture,time)
                    }
                }
                command.commit()
            }
        }
    }

    override func layout() {
        super.layout(); updateCornerGeometry(); layoutWindowBell()
        CATransaction.begin(); CATransaction.setDisableActions(true); frost.frame = bounds; backgroundSurface.frame = bounds; backgroundSurface.layer?.frame = bounds; backgroundSurface.layer?.bounds = CGRect(origin:.zero,size:bounds.size); backdrop.frame = bounds; tint.frame = backdrop.bounds; field.frame = backdrop.bounds; pictureLayer.frame = backdrop.bounds; layoutMetalField(); CATransaction.commit()
        if visibleField, field.contents == nil { setFrame(Self.render(config: config, size: bounds.size, time: elapsed)) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach{NotificationCenter.default.removeObserver($0)};windowObservers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.didExposeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self] _ in self?.updateTimer()})
            }
        }
        updateCornerGeometry();updateTimer()
    }
    override func viewDidHide(){super.viewDidHide();updateTimer()}
    override func viewDidUnhide(){super.viewDidUnhide();updateTimer()}
    private func layoutWindowBell() {
        borderPaintLayer.frame = bounds
        borderPaintLayer.isHidden = !config.window.showBorder || config.window.borderWidth == 0
        let width = CGFloat(config.window.borderWidth)
        borderMask.frame = bounds; borderMask.backgroundColor = nil
        borderMask.borderColor = NSColor.white.cgColor; borderMask.borderWidth = width
        borderMask.cornerRadius = layer?.cornerRadius ?? 0; borderMask.cornerCurve = layer?.cornerCurve ?? .continuous

        windowBellLayer.frame = bounds.width > 6 && bounds.height > 6 ? bounds.insetBy(dx: 3, dy: 3) : .zero
        windowBellLayer.cornerRadius = max(0, (layer?.cornerRadius ?? 0)-3)
    }
    func ringWindowBell(_ bell: Configuration.Bell, color: CGColor) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        windowBellLayer.borderColor = color; windowBellLayer.borderWidth = bell.thickness
        layoutWindowBell(); CATransaction.commit()
        windowBellLayer.pulse(peak: Float(bell.intensity), duration: bell.duration)
    }
    private func updateCornerGeometry() {
        guard let layer else { return }
        if window?.styleMask.contains(.fullScreen) == true { layer.cornerRadius = 0; return }
        var parent = superview
        while let view = parent {
            if let native = view.layer, native.cornerRadius > 0, view.bounds.width >= bounds.width { layer.cornerRadius = native.cornerRadius; layer.cornerCurve = native.cornerCurve; return }
            parent = view.superview
        }
        let radius: CGFloat
        if #available(macOS 26, *) { radius = 16 } else { radius = 10 }
        layer.cornerRadius = min(radius, min(bounds.width, bounds.height)/2); layer.cornerCurve = .circular
    }
    var animationCount: Int { moving && timer != nil ? 1 : 0 }
    private(set) var frameImage: CGImage?
    private func setFrame(_ image: CGImage?) { frameImage = image; field.contents = image; metalField.isHidden = true }
    func pauseMotion(_ paused: Bool) { self.paused = paused; updateTimer() }
}


extension Configuration.Paint {
    func apply(to layer: CAGradientLayer, fallback: NSColor) {
        let palette = resolved(fallback)
        layer.colors = (type == "solid" ? [palette[0], palette[0]] : palette).map { $0.cgColor }
        layer.type = .axial
        let radians = angle * .pi/180
        layer.startPoint = CGPoint(x: 0.5-cos(radians)/2, y: 0.5-sin(radians)/2)
        layer.endPoint = CGPoint(x: 0.5+cos(radians)/2, y: 0.5+sin(radians)/2)
    }
}

final class BackgroundTintSurface: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
