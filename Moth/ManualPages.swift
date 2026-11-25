// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import WebKit
import Darwin

struct ManualReference: Equatable {
    let name: String
    let section: String?
    var query: String { name + (section.map { "(\($0))" } ?? "") }
    init?(_ selection: String) {
        let value = selection.trimmingCharacters(in:.whitespacesAndNewlines)
        guard value.utf8.count <= 128,
              let match = value.range(of:#"^[A-Za-z0-9_][A-Za-z0-9_.+\-]*(?:\([1-9][A-Za-z0-9]*\))?$"#,options:.regularExpression),match == value.startIndex..<value.endIndex else { return nil }
        if let start = value.firstIndex(of:"(") {
            name = String(value[..<start]); section = String(value[value.index(after:start)..<value.index(before:value.endIndex)])
        } else { name = value; section = nil }
    }
    static func link(_ url: URL) -> ManualReference? {
        guard url.scheme == "moth-man" else { return nil }
        return ManualReference(String(url.absoluteString.dropFirst("moth-man:".count)).removingPercentEncoding ?? "")
    }
}

enum ManualPages {
    struct Page { let reference: ManualReference; let html: String }
    static func load(_ reference: ManualReference) throws -> Page {
        var args = ["-w"]
        if let section = reference.section { args.append(section) }; args.append(reference.name)
        let locations = try run("/usr/bin/man",args)
        guard let path = String(data:locations,encoding:.utf8)?.components(separatedBy:.newlines).first(where:{$0.hasPrefix("/")}),FileManager.default.fileExists(atPath:path) else {
            throw failure("No local manual page for \(reference.query).")
        }
        let file = URL(fileURLWithPath:path)
        let source: Data
        if path.hasSuffix(".gz") { source = try run("/usr/bin/gzip",["-dc",path]) }
        else if path.hasSuffix(".bz2") { source = try run("/usr/bin/bzip2",["-dc",path]) }
        else { source = try Data(contentsOf:file) }
        let body = try run("/usr/bin/mandoc",["-T","html","-O","fragment,man=moth-man:%N(%S)"],input:source,directory:file.deletingLastPathComponent().deletingLastPathComponent())
        guard let html = String(data:body,encoding:.utf8),!html.isEmpty else { throw failure("This manual page could not be rendered.") }
        return Page(reference:reference,html:document(html))
    }
    static func failure(_ text: String) -> NSError { NSError(domain:"MothManual",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    // Argument arrays are passed directly to the executables. Selected terminal
    // output is never evaluated by a shell, including in a remote session.
    static func run(_ executable: String,_ arguments: [String],input: Data? = nil,directory: URL? = nil) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moth-man-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let output = folder.appendingPathComponent("output"),source = folder.appendingPathComponent("source")
        FileManager.default.createFile(atPath:output.path,contents:nil)
        let writer = try FileHandle(forWritingTo:output); defer { try? writer.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        if (environment["MANPATH"] ?? "").isEmpty {
            let installed = ["/opt/homebrew/share/man","/usr/local/share/man"].filter { FileManager.default.fileExists(atPath:$0) }
            if !installed.isEmpty { environment["MANPATH"] = installed.joined(separator:":")+":" }
        }
        environment["LC_ALL"] = "C"; environment["MANPAGER"] = "/bin/cat"; environment["PAGER"] = "/bin/cat"; environment.removeValue(forKey:"MANOPT")
        process.environment = environment; process.standardOutput = writer; process.standardError = FileHandle.nullDevice
        var reader: FileHandle?
        if let input {
            guard input.count <= 16*1024*1024 else { throw failure("This manual page is too large to display.") }
            try input.write(to:source); reader = try FileHandle(forReadingFrom:source); process.standardInput = reader
        } else { process.standardInput = FileHandle.nullDevice }
        defer { try? reader?.close() }
        let done = DispatchSemaphore(value:0); process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout:.now()+10) == .timedOut {
            process.terminate()
            if done.wait(timeout:.now()+1) == .timedOut { kill(process.processIdentifier,SIGKILL); process.waitUntilExit() }
            throw failure("Manual lookup timed out. Try another command.")
        }
        guard process.terminationStatus == 0 else { throw failure("No local manual page was found, or it could not be rendered.") }
        let size = try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size <= 16*1024*1024 else { throw failure("This manual page is too large to display.") }
        return try Data(contentsOf:output)
    }
    static func document(_ fragment: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>:root{color-scheme:light dark;--fg:#27242f;--bg:#faf9fc;--link:#62508d}@media(prefers-color-scheme:dark){:root{--fg:#e4e1eb;--bg:#1e1c25;--link:#c5b5f2}}body{font:14px -apple-system,sans-serif;line-height:1.55;margin:24px;color:var(--fg);background:var(--bg)}a{color:var(--link)}pre,code,var,kbd{font-family:ui-monospace,monospace}pre{white-space:pre-wrap;overflow-wrap:anywhere}.head,.foot{font-size:11px;opacity:.7;display:flex;justify-content:space-between;gap:12px}.Sh{margin-top:1.6em}h2{font-size:16px}h3{font-size:14px}table{border-collapse:collapse;max-width:100%}table.Nm td:first-child{white-space:nowrap}td{padding:2px 8px 2px 0;vertical-align:top}dl{margin-left:12px}.permalink{text-decoration:none}main{overflow-wrap:anywhere}p{margin:.65em 0}</style></head><body>\(fragment)</body></html>
        """
    }
}

private final class ManualWebView: WKWebView {
    var focused: (() -> Void)?
    override func becomeFirstResponder() -> Bool { focused?(); return super.becomeFirstResponder() }
}

final class ManualPageController: NSViewController, WKNavigationDelegate, NSSearchFieldDelegate {
    private let browser: ManualWebView
    let searchField = NSSearchField()
    private let titleLabel = NSTextField(labelWithString:"")
    private let status = NSTextField(labelWithString:"")
    private let backButton = NSButton(title:"Back",target:nil,action:nil)
    private let forwardButton = NSButton(title:"Forward",target:nil,action:nil)
    private let windowButton = NSButton(title:"Open in Window",target:nil,action:nil)
    private var history: [ManualReference] = []
    private var historyIndex = -1
    private var generation = UUID()
    private(set) var reference: ManualReference
    private(set) var documentLoaded = false
    private(set) var renderedHTML: String?
    private(set) var lastError: String?
    var onOpenWindow: ((ManualReference)->Void)? { didSet { windowButton.isHidden = onOpenWindow == nil } }
    var onFocus: (() -> Void)?
    var onReferenceChange: ((ManualReference)->Void)?
    init(_ reference: ManualReference) {
        self.reference = reference
        let config = WKWebViewConfiguration(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        browser = ManualWebView(frame:.zero,configuration:config)
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame:NSRect(x:0,y:0,width:760,height:560))
        browser.navigationDelegate = self; browser.allowsBackForwardNavigationGestures = false
        browser.focused = { [weak self] in self?.onFocus?() }
        titleLabel.font = .systemFont(ofSize:13,weight:.semibold); titleLabel.lineBreakMode = .byTruncatingMiddle
        searchField.placeholderString = "Find in manual"; searchField.delegate = self; searchField.setAccessibilityLabel("Find in manual")
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        backButton.target = self; backButton.action = #selector(goBack); backButton.toolTip = "Previous manual page"
        forwardButton.target = self; forwardButton.action = #selector(goForward)
        windowButton.target = self; windowButton.action = #selector(openWindow); windowButton.isHidden = onOpenWindow == nil
        let previous = NSButton(title:"Previous",target:self,action:#selector(previousMatch))
        let next = NSButton(title:"Next",target:self,action:#selector(nextMatch))
        let toolbar = NSStackView(views:[backButton,forwardButton,titleLabel,windowButton]); toolbar.spacing = 8; toolbar.alignment = .centerY
        let find = NSStackView(views:[searchField,previous,next]); find.spacing = 8
        let stack = NSStackView(views:[toolbar,find,status,browser]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:12),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-12),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-12)])
        for child in [toolbar,find,browser] { child.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
        browser.heightAnchor.constraint(greaterThanOrEqualToConstant:80).isActive = true
        open(reference)
    }
    func open(_ next: ManualReference,record: Bool = true) {
        _ = view; reference = next; renderedHTML = nil; lastError = nil; documentLoaded = false
        if record {
            history = Array(history.prefix(historyIndex+1)); history.append(next); historyIndex = history.count-1
        }
        backButton.isEnabled = historyIndex > 0; forwardButton.isEnabled = historyIndex+1 < history.count
        titleLabel.stringValue = next.query; status.stringValue = "Loading local manual…"; searchField.stringValue = ""
        onReferenceChange?(next)
        let token = UUID(); generation = token
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try ManualPages.load(next) }
            DispatchQueue.main.async { [weak self] in
                guard let self,self.generation == token else { return }
                switch result {
                case .success(let page):
                    self.renderedHTML = page.html; self.browser.loadHTMLString(page.html,baseURL:nil)
                    self.status.stringValue = "Local manual · \(next.query)"
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.status.stringValue = error.localizedDescription
                    self.browser.loadHTMLString(ManualPages.document("<h2>Manual unavailable</h2><p>Check the command name and install its local manual page, then try again.</p>"),baseURL:nil)
                }
            }
        }
    }
    func focusSearch() { _ = view; onFocus?(); view.window?.makeFirstResponder(searchField) }
    func find(backwards: Bool = false,completion: ((Bool)->Void)? = nil) {
        let config = WKFindConfiguration(); config.backwards = backwards; config.wraps = true
        browser.find(searchField.stringValue,configuration:config) { [weak self] result in
            completion?(result.matchFound)
            if !result.matchFound { self?.status.stringValue = "No matches" } else if let self { self.status.stringValue = "Local manual · \(self.reference.query)" }
        }
    }
    func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) { documentLoaded = true }
    func webView(_ webView: WKWebView,didFailProvisionalNavigation navigation: WKNavigation!,withError error: Error) {
        lastError = error.localizedDescription; documentLoaded = true; status.stringValue = error.localizedDescription
    }
    func snapshot(_ completion: @escaping (NSImage?)->Void) {
        browser.takeSnapshot(with:nil) { image,_ in completion(image) }
    }
    func controlTextDidChange(_ obj: Notification) { find() }
    func controlTextDidBeginEditing(_ obj: Notification) { onFocus?() }
    func control(_ control: NSControl,textView: NSTextView,doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { find(backwards:NSApp.currentEvent?.modifierFlags.contains(.shift) == true); return true }
        return false
    }
    @objc private func nextMatch() { onFocus?(); find() }
    @objc private func previousMatch() { onFocus?(); find(backwards:true) }
    @objc private func goBack() { guard historyIndex > 0 else { return }; onFocus?(); historyIndex -= 1; open(history[historyIndex],record:false) }
    @objc private func goForward() { guard historyIndex+1 < history.count else { return }; onFocus?(); historyIndex += 1; open(history[historyIndex],record:false) }
    @objc private func openWindow() { onOpenWindow?(reference) }
    func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if let next = ManualReference.link(url) { decisionHandler(.cancel); onFocus?(); open(next); return }
        // Only the rendered document and its in-page section anchors may navigate.
        decisionHandler(["about","applewebdata"].contains(url.scheme ?? "") ? .allow : .cancel)
    }
}

/// Reference documents have their own windows; terminal panes remain PTYs.
final class ManualWindowController: NSWindowController, NSWindowDelegate {
    let viewer: ManualPageController
    var onClose: (() -> Void)?
    init(_ reference: ManualReference,viewer existing: ManualPageController? = nil) {
        viewer = existing ?? ManualPageController(reference)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:600),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.isRestorable = false
        window.minSize = NSSize(width:520,height:360)
        super.init(window:window)
        window.delegate = self; window.title = "Manual: " + reference.query
        viewer.onOpenWindow = nil; viewer.onFocus = nil
        viewer.onReferenceChange = { [weak window] ref in window?.title = "Manual: " + ref.query }
        window.contentViewController = viewer
        window.setFrameAutosaveName("MothManualReference"); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
