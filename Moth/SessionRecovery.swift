// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import SwiftTerm
import Darwin

/// Owns only the local connection. The independent helper owns the shell and PTY.
final class SessionConnection {
    let id: String
    private let socket: String
    private let fd: Int32
    private let writes = DispatchQueue(label:"dev.getmoth.session.input")
    private let lock = NSLock()
    private var connected = true
    var received: ((UInt8,Data) -> Void)?
    init(id: String, socket: String) throws {
        self.id = id; self.socket = socket
        fd = moth_session_connect(socket)
        guard fd >= 0 else { throw Configuration.invalid("This session is no longer available. Its helper may have ended, or the Mac may have restarted.") }
    }
    func start() {
        DispatchQueue.global(qos:.userInitiated).async { [self] in
            func readExactly(_ count: Int) -> Data? {
                var data = Data(count:count), offset = 0
                while offset < count {
                    let n = data.withUnsafeMutableBytes { Darwin.read(fd,$0.baseAddress!.advanced(by:offset),count-offset) }
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { return nil }; offset += n
                }
                return data
            }
            while let header = readExactly(5) {
                let count = header.dropFirst().reduce(0) { ($0 << 8) | Int($1) }
                guard count <= 1024*1024,let body = count == 0 ? Data() : readExactly(count) else { break }
                DispatchQueue.main.sync { [self] in self.received?(header[0],body) }
            }
            lock.lock(); let wasConnected = connected; connected = false; lock.unlock()
            Darwin.close(fd)
            if wasConnected { DispatchQueue.main.async { [weak self] in self?.received?(UInt8(ascii:"D"),Data()) } }
        }
    }
    func send(_ type: UInt8, _ data: Data = Data()) {
        if type == UInt8(ascii:"I"),data.count > 65536 {
            for offset in stride(from:0,to:data.count,by:65536) { send(type,Data(data[offset..<min(offset+65536,data.count)])) }; return
        }
        writes.async { [self] in
            lock.lock(); defer { lock.unlock() }
            guard connected else { return }
            let result = data.withUnsafeBytes { moth_session_send(fd,type,$0.baseAddress,UInt32(data.count)) }
            if result != 0 { shutdown(fd,SHUT_WR) }
        }
    }
    func end() {
        // The five-byte stop request must be sent before AppKit is allowed to quit.
        // A separate local control connection never waits for terminal-output replay.
        if moth_session_end(socket) == 0 || errno == ENOENT || errno == ECONNREFUSED { SessionRecovery.removeRecord(id) }
        detach()
    }
    func detach() {
        lock.lock(); defer { lock.unlock() }
        guard connected else { return }; connected = false; shutdown(fd,SHUT_RDWR)
    }
    // The read loop closes the fd after shutdown, preventing descriptor-reuse races.
    deinit { }
}

enum SessionRecovery {
    static var runtimeEnabled = true
    private static var ownershipFD: Int32 = -1
    static var enabled: Bool {
        runtimeEnabled &&
        !CommandLine.arguments.contains("--self-test") && !SiteScreenshots.enabled && !MothBenchmark.enabled && !CommandLine.arguments.contains("--vector-reference")
    }
    static func claimOwnership() throws {
        try privateDirectory(directory)
        let fd = Darwin.open(directory.appendingPathComponent("owner.lock").path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw Configuration.invalid("Moth could not lock its session recovery folder.") }
        guard flock(fd,LOCK_EX|LOCK_NB) == 0 else { Darwin.close(fd); throw Configuration.invalid("Another copy of Moth is already managing these sessions. Use that copy, or quit it before opening this one.") }
        ownershipFD = fd
    }
    static var directory: URL { Configuration.url.deletingLastPathComponent().appendingPathComponent("Sessions",isDirectory:true) }
    private static var lastSavedData: Data?
    static var manifestURL: URL { directory.appendingPathComponent("recovery.json") }
    struct Record: Codable { var id: String; var socket: String }
    struct Window: Codable { var layout: SavedWindowLayout; var x: Double; var y: Double }
    struct Document: Codable { var version = 1; var windows: [Window] }
    static func privateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let attrs = try FileManager.default.attributesOfItem(atPath:url.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory,(attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw Configuration.invalid("Session recovery requires a private folder owned by your account.") }
        if (attrs[.posixPermissions] as? NSNumber)?.intValue != 0o700 { try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path) }
    }
    static func recordURL(_ id: String) throws -> URL {
        guard UUID(uuidString:id) != nil else { throw Configuration.invalid("Invalid recovery session identifier.") }
        return directory.appendingPathComponent(id+".json")
    }
    static func connect(_ id: String) throws -> SessionConnection {
        let url = try recordURL(id)
        let data = try Data(contentsOf:url); guard data.count < 4096 else { throw Configuration.invalid("Invalid session record.") }
        let record = try JSONDecoder().decode(Record.self,from:data)
        guard record.id == id,URL(fileURLWithPath:record.socket).lastPathComponent == id else { throw Configuration.invalid("Invalid session endpoint.") }
        return try SessionConnection(id:id,socket:record.socket)
    }
    static func launch(shell: String,args: [String],environment: [String:String],directory cwd: String,rows: Int,cols: Int) throws -> SessionConnection {
        try privateDirectory(directory)
        // Darwin's Unix socket path limit is 104 bytes. Keep sockets outside long config paths.
        let sockets = URL(fileURLWithPath:"/tmp/moth-sessions-\(getuid())",isDirectory:true)
        try privateDirectory(sockets)
        let id = UUID().uuidString, socket = sockets.appendingPathComponent(id).path
        let record = Record(id:id,socket:socket)
        let url = try recordURL(id)
        try JSONEncoder().encode(record).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        let helper = Process(); helper.executableURL = Bundle.main.executableURL
        helper.arguments = ["--session-broker",socket,String(rows),String(cols),shell]+args
        helper.environment = environment; helper.currentDirectoryURL = URL(fileURLWithPath:cwd)
        helper.standardInput = FileHandle.nullDevice; helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
        do { try helper.run() } catch { try? FileManager.default.removeItem(at:url); throw error }
        // The helper only binds a socket and opens a PTY before becoming available.
        // A short startup wait never waits for a shell prompt or shell startup scripts.
        let deadline = ProcessInfo.processInfo.systemUptime+2
        repeat {
            if let connection = try? connect(id) { return connection }
            if !helper.isRunning { break }; usleep(5000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        helper.terminate(); try? FileManager.default.removeItem(at:url)
        throw Configuration.invalid("Moth could not start the session helper. No replacement shell was started.")
    }
    static func removeRecord(_ id: String) { if let url = try? recordURL(id) { try? FileManager.default.removeItem(at:url) } }
    static func load() throws -> Document? {
        let data = FileManager.default.fileExists(atPath:manifestURL.path) ? try Data(contentsOf:manifestURL) : try JSONEncoder().encode(Document(windows:[]))
        guard data.count < 2*1024*1024 else { throw Configuration.invalid("Session recovery data exceeds its size limit.") }
        var document = try JSONDecoder().decode(Document.self,from:data)
        guard document.version == 1,document.windows.count <= 32 else { throw Configuration.invalid("Unsupported session recovery document.") }
        var identifiers = Set<String>()
        for window in document.windows {
            try window.layout.validate()
            guard window.x.isFinite,window.y.isFinite else { throw Configuration.invalid("Invalid recovered window position.") }
            for tab in window.layout.tabs {
                guard let sessions = tab.sessions,sessions.count == tab.root.paneCount else { throw Configuration.invalid("Incomplete recovered session layout.") }
                for id in sessions { guard UUID(uuidString:id) != nil,identifiers.insert(id).inserted else { throw Configuration.invalid("Invalid or duplicate recovered session.") } }
            }
        }
        let records = (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        for url in records.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where UUID(uuidString:url.deletingPathExtension().lastPathComponent) != nil {
            guard document.windows.count < 32,let data = try? Data(contentsOf:url),data.count < 4096,let record = try? JSONDecoder().decode(Record.self,from:data),record.id == url.deletingPathExtension().lastPathComponent,!identifiers.contains(record.id),URL(fileURLWithPath:record.socket).lastPathComponent == record.id else { continue }
            guard FileManager.default.fileExists(atPath:record.socket) else { removeRecord(record.id); continue }
            let tab = SavedTab(root:.pane,activePane:0,sessions:[record.id])
            let layout = SavedWindowLayout(name:"Recovered Session",tabs:[tab],activeTab:0,width:1120,height:740)
            document.windows.append(Window(layout:layout,x:120,y:100)); identifiers.insert(record.id)
        }
        return document.windows.isEmpty ? nil : document
    }
    static func save(_ windows: [TerminalWindowController]) throws {
        try privateDirectory(directory)
        var snapshots: [Window] = []
        for window in windows where !window.workspaces.isEmpty {
            guard window.workspaces.flatMap(\.panes).contains(where: { $0.terminal.session != nil && $0.terminal.process.running }) else { continue }
            var layout = try SavedWindowLayout.capture(window,name:"Recovered Window")
            layout.id = window.recoveryID
            for (i,workspace) in window.workspaces.enumerated() {
                let ids = workspace.orderedPanes.map { $0.terminal.session?.id ?? $0.unavailableRecoveryID }
                layout.tabs[i].sessions = ids
            }
            snapshots.append(Window(layout:layout,x:Double(window.window?.frame.origin.x ?? 0),y:Double(window.window?.frame.origin.y ?? 0)))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(windows:snapshots))
        guard data != lastSavedData else { return }
        try data.write(to:manifestURL,options:.atomic)
        lastSavedData = data
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:manifestURL.path)
    }
    static func discard(_ document: Document) {
        for window in document.windows { for tab in window.layout.tabs { for id in tab.sessions ?? [] {
            if let url = try? recordURL(id),let data = try? Data(contentsOf:url),let record = try? JSONDecoder().decode(Record.self,from:data),record.id == id,URL(fileURLWithPath:record.socket).lastPathComponent == id { if moth_session_end(record.socket) == 0 || errno == ENOENT || errno == ECONNREFUSED { removeRecord(id) } }
        } } }
        try? FileManager.default.removeItem(at:manifestURL)
    }
    /// Called before AppKit starts. Helpers never open windows or read GUI preferences.
    static func runHelperIfRequested() {
        let args = CommandLine.arguments
        guard args.count >= 6,args[1] == "--session-broker",let rows = Int32(args[3]),let cols = Int32(args[4]),(2...1000).contains(rows),(2...1000).contains(cols) else { return }
        let strings = [args[5]]+Array(args.dropFirst(6))
        let pointers = strings.map { strdup($0) }+[nil]
        let result = pointers.withUnsafeBufferPointer { moth_session_broker(args[2],rows,cols,args[5],$0.baseAddress) }
        for pointer in pointers { free(pointer) }; exit(result)
    }
}

extension ShellView {
    func beginSession(_ connection: SessionConnection,restoring:Bool = true) {
        session = connection; replayingSession = true; sessionEnded = false; readOnly = restoring
        acceptsInputDuringSessionStartup = !restoring
        if restoring { recoveryPresentationChanged?(.restoring) }
        process.attachExternal(shellPID:0,send:{ [weak connection] bytes in connection?.send(UInt8(ascii:"I"),Data(bytes)) },resize:{ [weak self,weak connection] rows,cols in
            guard let self,!self.replayingSession else { return }
            let size = self.getWindowSize()
            var values = [UInt32(rows).bigEndian,UInt32(cols).bigEndian,UInt32(size.ws_xpixel).bigEndian,UInt32(size.ws_ypixel).bigEndian]
            let data = values.withUnsafeMutableBytes { Data($0) }; connection?.send(UInt8(ascii:"R"),data)
        },terminate:{ [weak connection] in connection?.end() })
        connection.received = { [weak self,weak connection] type,data in
            guard let self,let connection else { return }
            func value(_ offset: Int) -> Int { data.dropFirst(offset).prefix(4).reduce(0) { ($0 << 8) | Int($1) } }
            switch type {
            case UInt8(ascii:"H"):
                guard data.count == 20 else { return }
                self.process.updateExternalPID(Int32(truncatingIfNeeded:value(0)))
                self.getTerminal().resize(cols:value(12),rows:value(8))
                self.recoveryHistoryTruncated = value(16) != 0
            case UInt8(ascii:"O"),UInt8(ascii:"P"):
                guard data.count >= 8 else { return }
                self.suppressSessionReplies = type == UInt8(ascii:"P")
                self.process.receiveExternal(data:Array(data.dropFirst(8))[...])
                self.suppressSessionReplies = false
                if self.replayingSession { self.replayAcknowledgement = Data(data.prefix(8)) }
                else if type == UInt8(ascii:"O") { connection.send(UInt8(ascii:"A"),Data(data.prefix(8))) }
            case UInt8(ascii:"R"):
                if data.count == 8 || data.count == 16 { self.getTerminal().resize(cols:value(4),rows:value(0)) }
            case UInt8(ascii:"E"):
                self.replayingSession = false; self.readOnly = false; self.acceptsInputDuringSessionStartup = false
                if !self.replayResponses.isEmpty { self.process.send(data:self.replayResponses[...]); self.replayResponses.removeAll() }
                if self.replayAcknowledgement.count == 8 { connection.send(UInt8(ascii:"A"),self.replayAcknowledgement); self.replayAcknowledgement = Data() }
                self.setFrameSize(self.frame.size); self.needsDisplay = true
                let size = self.getWindowSize(); self.process.resize(rows:Int(size.ws_row),cols:Int(size.ws_col))
                self.recoveryPresentationChanged?(.ready)
                if self.recoveryHistoryTruncated { self.toolTip = "This session kept running. Its oldest output exceeded the 64 MB recovery buffer. Full-screen programs may need to redraw (Ctrl+L)." }
            case UInt8(ascii:"X"):
                guard data.count == 4 else { return }; self.sessionEnded = true
                self.process.externalExited(Int32(truncatingIfNeeded:value(0)))
                SessionRecovery.removeRecord(connection.id); connection.detach()
            case UInt8(ascii:"D"):
                guard !self.sessionEnded else { return }
                self.toolTip = "The session helper disconnected. Reopen Moth to try recovering this session."
                self.readOnly = true; self.acceptsInputDuringSessionStartup = false
                self.recoveryPresentationChanged?(.disconnected)
                self.processDelegate?.setTerminalTitle(source:self,title:"Disconnected")
            default: break
            }
        }
        connection.start()
    }
}

extension App {
    func restoreSessions() -> Bool {
        guard SessionRecovery.enabled else { return false }
        do {
            guard let document = try SessionRecovery.load(),!document.windows.isEmpty else { return false }
            let alert = NSAlert(); alert.messageText = "Recover your terminal sessions?"
            alert.informativeText = "Moth found sessions from a previous run. Recover reconnects to the original processes where they are still available. It does not rerun commands. End Sessions terminates those shells and jobs."
            alert.addButton(withTitle:"Recover Sessions"); alert.addButton(withTitle:"End Sessions")
            if RecoveryHostFixture.root == nil && alert.runModal() != .alertFirstButtonReturn { SessionRecovery.discard(document); return false }
            for entry in document.windows {
                let controller = TerminalWindowController(application:self,savedLayout:entry.layout)
                windows.append(controller); controller.window?.setFrameOrigin(NSPoint(x:entry.x,y:entry.y)); if let window = controller.window { window.setFrame(window.constrainFrameRect(window.frame,to:nil),display:false) }
                controller.presentAndFocus()
            }
            return !windows.isEmpty
        } catch { showError(error); return false }
    }
    @objc func quitKeepingSessions(_ sender: Any?) {
        guard !windows.flatMap(\.workspaces).flatMap(\.panes).contains(where: { $0.terminal.process.running && $0.terminal.session == nil }) else { showError(Configuration.invalid("Some running panes were started with session recovery disabled. Close them before quitting with sessions kept.")); return }
        do { try SessionRecovery.save(windows) } catch { showError(error); return }
        keepingSessions = true
        windows.flatMap(\.workspaces).flatMap(\.panes).forEach { $0.terminal.session?.detach() }
        NSApp.terminate(nil)
    }
    func startRecoveryCheckpoints() {
        guard SessionRecovery.enabled else { return }
        recoveryTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            guard let self,!self.keepingSessions,!self.shuttingDown else { return }
            do { try SessionRecovery.save(self.windows); self.recoveryError = nil } catch { self.recoveryError = error }
        }
        try? SessionRecovery.save(windows)
    }
}

/// Integration probe for the real AppKit client and terminal core. Only used by --self-test.
final class SessionRecoveryProbe {
    var results: [String:Bool] = [:]
    var finished = false
    private var probeWindows: [NSWindow] = []
    private func mount(_ pane: Pane) {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:500),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = pane; pane.layoutSubtreeIfNeeded(); probeWindows.append(window)
    }
    private var first: Pane?
    private var recovered: Pane?
    private var id: String?
    private var originalPID: Int32 = 0
    private var replayBellCount = 0
    private var firstHadOutput = false
    private var config = Configuration()
    private static let names = ["recoveryClientStartsRealPTY","recoveryKeepsOriginalProcess","recoveryReplaysOutputAndAttributes","recoveryReplaysSixelImages","recoveryDoesNotReplayBells","recoveryAcceptsInputAndResize","recoveryRetainsRealExitStatus","recoveryLayoutRoundTripsSessions","namedLayoutsDoNotAttachRecoverySessions"]
    static func start() -> SessionRecoveryProbe {
        let probe = SessionRecoveryProbe(); names.forEach { probe.results[$0] = false }; DispatchQueue.main.async { probe.run() }; return probe
    }
    private func waitUntil(timeout: Double,condition: @escaping () -> Bool,completion: @escaping (Bool) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime+timeout
        func poll() { if condition() { completion(true) } else if ProcessInfo.processInfo.systemUptime >= deadline { completion(false) } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.03) { poll() } } }
        poll()
    }
    private func text(_ pane: Pane) -> String { pane.terminal.getTerminal().exportPlainText() }
    private func run() {
        config.closeOnExit = false; config.advanced.loginShell = false
        let pane = Pane(config:config,start:false); mount(pane); first = pane
        // This fixture accepts a tiny fixed command vocabulary, never user commands.
        let image = "\u{1b}Pq\"1;1;4;6#0;2;100;0;0!4~\u{1b}\\".utf8.map { String(format:"\\%03o",Int($0)) }.joined()
        let script = "stty -echo; printf 'READY:%s\\n' $$; sleep 0.4; printf '\\033[31mOFFLINE_RED\\033[0m\\007\\n'; printf '\(image)'; while IFS= read -r line; do case \"$line\" in size) printf 'SIZE:'; stty size;; quit) exit 7;; esac; done"
        do {
            let connection = try SessionRecovery.launch(shell:"/bin/sh",args:["-c",script],environment:ShellEnvironment.session(),directory:FileManager.default.temporaryDirectory.path,rows:24,cols:80)
            id = connection.id; pane.terminal.beginSession(connection)
            self.waitUntil(timeout:4,condition:{ self.text(pane).contains("READY:") && !pane.terminal.replayingSession }) { ready in
                self.results["recoveryClientStartsRealPTY"] = ready && pane.terminal.process.shellPid > 0
                guard ready else { print("Recovery ready timeout:",self.text(pane),"replaying:",pane.terminal.replayingSession,"pid:",pane.terminal.process.shellPid); self.stop(); return }
                self.originalPID = pane.terminal.process.shellPid; self.firstHadOutput = self.text(pane).contains("OFFLINE_RED")
                connection.detach()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.65) { self.reattach() }
            }
        } catch { print("Recovery probe:",error); stop() }
    }
    private func reattach() {
        guard let id else { return }
        do {
            let pane = Pane(config:config,start:false); mount(pane); recovered = pane
            pane.terminal.onBell = { [weak self] in self?.replayBellCount += 1 }
            pane.terminal.beginSession(try SessionRecovery.connect(id))
            self.results["recoveryHidesIntermediateReplay"] = pane.terminal.isHidden && !pane.recoveryIndicator.isHidden && pane.terminal.readOnly && !pane.terminal.acceptsFirstResponder
            self.waitUntil(timeout:4,condition:{ !pane.terminal.replayingSession && self.text(pane).contains("OFFLINE_RED") }) { ready in
                self.results["recoveryRevealsReadyInput"] = ready && !pane.terminal.isHidden && pane.recoveryIndicator.isHidden && !pane.terminal.readOnly && pane.terminal.acceptsFirstResponder
                self.results["recoveryKeepsOriginalProcess"] = ready && pane.terminal.process.shellPid == self.originalPID && pane.terminal.process.running
                var red = false
                for row in 0..<pane.terminal.getTerminal().rows { for col in 0..<pane.terminal.getTerminal().cols { if pane.terminal.getTerminal().getCharData(col:col,row:row)?.attribute.fg == .ansi256(code:1) { red = true } } }
                self.results["recoveryReplaysOutputAndAttributes"] = ready && self.text(pane).contains("READY:\(self.originalPID)") && red
                self.results["recoveryReplaysSixelImages"] = pane.terminal.getTerminal().buffer.hasAnyImages
                self.results["recoveryDoesNotReplayBells"] = self.replayBellCount == 0
                pane.terminal.process.resize(rows:31,cols:93); pane.terminal.send(txt:"size\r")
                self.waitUntil(timeout:3,condition:{ self.text(pane).contains("SIZE:31 93") }) { resized in
                    self.results["recoveryAcceptsInputAndResize"] = resized
                    pane.terminal.send(txt:"quit\r")
                    self.waitUntil(timeout:3,condition:{ pane.ended }) { ended in
                        self.results["recoveryRetainsRealExitStatus"] = ended && !pane.terminal.process.running && pane.title == "Exited · 7"
                        self.checkLayout(); self.stop()
                    }
                }
            }
        } catch { print("Recovery reconnect probe:",error); stop() }
    }
    private func checkLayout() {
        do {
            let tab = SavedTab(root:.split(vertical:true,fraction:0.4,first:.pane,second:.pane),activePane:1,sessions:[UUID().uuidString,UUID().uuidString])
            let layout = SavedWindowLayout(name:"Recovery Fixture",tabs:[tab],activeTab:0,width:900,height:600)
            let data = try JSONEncoder().encode(layout), again = try JSONDecoder().decode(SavedWindowLayout.self,from:data)
            results["recoveryLayoutRoundTripsSessions"] = again.tabs[0].sessions == tab.sessions && again.tabs[0].activePane == 1
            let url = SessionRecovery.directory.appendingPathComponent("named-layout-test.json")
            try WindowLayoutStore.save(layout,to:url)
            results["namedLayoutsDoNotAttachRecoverySessions"] = try WindowLayoutStore.load(from:url).first?.tabs.first?.sessions == nil
        } catch { print("Recovery layout probe:",error) }
    }
    func stop() { finished = true; if recovered == nil { first?.stop() } else { first?.terminal.session?.detach() }; recovered?.stop(); if recovered == nil,let id,let connection = try? SessionRecovery.connect(id) { connection.send(UInt8(ascii:"T")); connection.start() }; if let id { SessionRecovery.removeRecord(id) }; first = nil; recovered = nil; probeWindows.forEach { $0.close() }; probeWindows.removeAll() }
}

/// Explicit, isolated crash/relaunch fixture. It cannot select the user's config folder.
enum RecoveryHostFixture {
    static var root: URL? {
        guard CommandLine.arguments.contains("--recovery-test-host"),let path = ProcessInfo.processInfo.environment["MOTH_RECOVERY_TEST_ROOT"] else { return nil }
        let url = URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix("/private/tmp/moth-recovery-host-") || url.path.hasPrefix("/tmp/moth-recovery-host-") else { return nil }
        return url
    }
    static func run(_ app: App) {
        guard let root else { return }
        if ProcessInfo.processInfo.environment["MOTH_RECOVERY_TEST_FOCUS"] == "1" { NewWindowFocusChecks(app:app,root:root).run();return }
        try? Data("Fixture started: \(app.windows.count) windows".utf8).write(to:root.appendingPathComponent("diagnostics.txt"))
        let expectedURL = root.appendingPathComponent("expected.json")
        if !FileManager.default.fileExists(atPath:expectedURL.path) {
            guard let first = app.active else { exit(3) }
            first.content.layoutSubtreeIfNeeded(); first.workspace.split(vertical:true,config:first.config)
            first.workspace.root.layoutSubtreeIfNeeded(); first.workspace.split(vertical:false,config:first.config)
            if ProcessInfo.processInfo.environment["MOTH_RECOVERY_TEST_PANES"]=="9" {
                first.window?.setContentSize(NSSize(width:1500,height:1000));first.content.layoutSubtreeIfNeeded()
                while first.workspace.panes.count<9 {
                    first.workspace.root.layoutSubtreeIfNeeded()
                    let candidates=first.workspace.panes.filter{$0.bounds.width>=420 || $0.bounds.height>=280}
                    guard let pane=candidates.max(by:{$0.bounds.width*$0.bounds.height < $1.bounds.width*$1.bounds.height}) else { exit(9) }
                    first.workspace.active=pane
                    let vertical=pane.bounds.width>=420 && (pane.bounds.height<280 || pane.bounds.width/420 >= pane.bounds.height/280)
                    first.workspace.split(vertical:vertical,config:first.config)
                }
            }
            let expectedPaneCount=first.workspace.panes.count+2
            first.newTab(nil); first.selectTab(at:0); app.newWindow(nil)
            let panes = app.windows.flatMap(\.workspaces).flatMap(\.orderedPanes)
            wait(deadline:ProcessInfo.processInfo.systemUptime+8,condition:{ panes.allSatisfy { $0.terminal.process.shellPid > 0 && !$0.terminal.replayingSession && $0.terminal.getTerminal().exportPlainText().contains("moth-test$") } }) { ready in
                guard ready,panes.count == expectedPaneCount else {
                    let report = panes.map { "pid=\($0.terminal.process.shellPid) replay=\($0.terminal.replayingSession) text=\($0.terminal.getTerminal().exportPlainText())" }.joined(separator:"\n")
                    try? Data("Pane count=\(panes.count) ready=\(ready)\n\(report)".utf8).write(to:root.appendingPathComponent("diagnostics.txt")); exit(4)
                }
                for pane in panes { pane.terminal.send(txt:"stty -echo; printf 'RECOVERY_READY:%s\\n' $$; sleep 2; printf 'RECOVERY_AFTER_DISCONNECT\\n'\r") }
                wait(deadline:ProcessInfo.processInfo.systemUptime+5,condition:{ panes.allSatisfy { $0.terminal.getTerminal().exportPlainText().contains("RECOVERY_READY:\($0.terminal.process.shellPid)") } }) { ready in
                    guard ready else { exit(5) }
                    do {
                        if ProcessInfo.processInfo.environment["MOTH_RECOVERY_TEST_MAXIMIZED"]=="1" { first.workspace.toggleMaximizePane() }
                        try SessionRecovery.save(app.windows)
                        let json: [String:Any] = ["app":getpid(),"splitPanes":first.workspace.panes.count,"shells":panes.map { $0.terminal.process.shellPid },"sessions":panes.compactMap { $0.terminal.session?.id }]
                        try JSONSerialization.data(withJSONObject:json,options:[.sortedKeys]).write(to:expectedURL,options:.atomic)
                    } catch { print(error); exit(6) }
                }
            }
        } else {
            let panes = app.windows.flatMap(\.workspaces).flatMap(\.orderedPanes)
            wait(deadline:ProcessInfo.processInfo.systemUptime+8,condition:{ panes.allSatisfy { !$0.terminal.replayingSession && $0.terminal.getTerminal().exportPlainText().contains("RECOVERY_AFTER_DISCONNECT") } }) { ready in
                do {
                    let expected = try JSONSerialization.jsonObject(with:Data(contentsOf:expectedURL)) as! [String:Any]
                    let pids = (expected["shells"] as! [NSNumber]).map(\.int32Value)
                    let checks: [String:Bool] = [
                        "fullAppRelaunchKeepsOriginalShells":ready && panes.map { $0.terminal.process.shellPid } == pids,
                        "fullAppRelaunchKeepsTabsAndNestedSplits":app.windows.count == 2 && app.windows[0].workspaces.count == 2 && app.windows[0].workspaces[0].panes.count == (expected["splitPanes"] as? Int ?? 3) && app.windows[0].index == 0,
                        "fullAppRelaunchKeepsTerminalHistory":ready && panes.allSatisfy { $0.terminal.getTerminal().exportPlainText().contains("RECOVERY_READY:\($0.terminal.process.shellPid)") },
                        "fullAppRelaunchDoesNotDuplicateSessions":panes.compactMap { $0.terminal.session?.id } == expected["sessions"] as? [String],
                        "fullAppRelaunchRevealsReadyPanes":ready && panes.allSatisfy { !$0.terminal.isHidden && $0.recoveryIndicator.isHidden && !$0.terminal.readOnly },
                        "fullAppRelaunchFocusesRecoveredPane":app.active.map { $0.window?.firstResponder === $0.workspace.active.terminal } ?? false
                    ]
                    let keeping = FileManager.default.fileExists(atPath:root.appendingPathComponent("keep-request").path)
                    try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(keeping ? "kept-results.json" : "results.json"),options:.atomic)
                    if keeping { try FileManager.default.removeItem(at:root.appendingPathComponent("keep-request")); app.quitKeepingSessions(nil); return }
                } catch { print(error); exit(7) }
                NSApp.terminate(nil)
            }
        }
    }
    private static func wait(deadline: Double,condition: @escaping () -> Bool,completion: @escaping (Bool) -> Void) {
        if condition() { completion(true) } else if ProcessInfo.processInfo.systemUptime >= deadline { completion(false) } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { wait(deadline:deadline,condition:condition,completion:completion) } }
    }
}

/// Uses real session helpers and native window key delivery, never the user's data.
private final class NewWindowFocusChecks {
    let app:App;let root:URL
    var checks:[String:Bool]=[:]
    init(app:App,root:URL){self.app=app;self.root=root}
    func wait(_ condition:@escaping ()->Bool,_ done:@escaping (Bool)->Void){
        let deadline=ProcessInfo.processInfo.systemUptime+4
        func poll(){if condition(){done(true)}else if ProcessInfo.processInfo.systemUptime>=deadline{done(false)}else{DispatchQueue.main.asyncAfter(deadline:.now()+0.01){poll()}}}
        poll()
    }
    func finish(){
        try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("focus-results.json"),options:.atomic)
        app.config.closeConfirmation.enabled=false
        NSApp.terminate(nil)
    }
    func type(_ text:String,in controller:TerminalWindowController){
        for character in text {
            let value=String(character),code:UInt16=character=="\r" ? 36:0
            let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:controller.window!.windowNumber,context:nil,characters:value,charactersIgnoringModifiers:value,isARepeat:false,keyCode:code)!
            NSApp.sendEvent(event)
        }
    }
    func run(){
        wait({NSApp.isActive && self.app.windows.last?.window?.isKeyWindow==true}){ [self] active in
            checks["initialLaunchFocusesWithoutClick"] = active && app.windows.last?.window?.firstResponder === app.windows.last?.workspace.active.terminal
            open(0)
        }
    }
    func open(_ index:Int){
        guard index<3 else {finish();return}
        let prior=app.windows.last!
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:prior.window!.windowNumber,context:nil,characters:"n",charactersIgnoringModifiers:"n",isARepeat:false,keyCode:45)!
        let count=app.windows.count
        checks["commandNCreatesWindow_\(index)"]=NSApp.mainMenu?.performKeyEquivalent(with:event)==true && app.windows.count==count+1
        guard app.windows.count==count+1 else{finish();return}
        let target=app.windows.last!,terminal=app.windows.last!.workspace.active.terminal
        checks["helperStartupAcceptsInputImmediately_\(index)"] = terminal.session != nil && !terminal.readOnly && terminal.acceptsFirstResponder && !terminal.isHidden
        type("printf '\\nFOCUS_INPUT_\(index)\\n'\r",in:target)
        wait({terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains("FOCUS_INPUT_\(index)")}){ [self] typed in
            checks["firstKeystrokesReachNewShell_\(index)"]=typed
            checks["newWindowRetainsNativeFocus_\(index)"]=target.window?.isKeyWindow==true && target.window?.firstResponder === terminal && terminal.hasFocus
            open(index+1)
        }
    }
}
