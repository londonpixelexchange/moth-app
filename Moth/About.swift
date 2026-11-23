// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit

final class AboutWindowController: NSWindowController {
    let thanksText = NSTextField(labelWithString:"Pedro Ortiz Suarez\nDevon Dugentas\nThijs Dalhuijsen\nMalte Ostendorff\nMike Abbey")
    let versionText = NSTextField(labelWithString:"")
    let contentStack = NSStackView()
    private var licences: NSWindowController?
    private(set) var logoView: MothLogoView!
    private(set) var swarm: MothSwarmView?
    private weak var priorResponder: NSResponder?
    let projects = [
        ("Wumpus Mono Pro","https://vaughantype.com/wumpus-mono-pro"),
        ("SwiftTerm · Miguel de Icaza","https://github.com/migueldeicaza/SwiftTerm"),
        ("TOMLKit · Jeff Lebrun","https://github.com/LebJe/TOMLKit"),
        ("toml++ · Mark Gillard","https://github.com/marzer/tomlplusplus"),
        ("Nerd Fonts","https://github.com/ryanoasis/nerd-fonts"),
        ("JetBrains Mono","https://github.com/JetBrains/JetBrainsMono"),
        ("IBM Plex Mono","https://github.com/IBM/plex")
    ]
    static let horizontalPadding: CGFloat = 32
    static let verticalPadding: CGFloat = 24
    let websites = [("getmoth.dev","https://getmoth.dev")]
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:460),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:window)
        window.appearance = NSAppearance(named:.darkAqua)
        window.backgroundColor = AboutContentView.background
        window.title = "About Moth"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        let root = AboutContentView(); window.contentView = root
        let stack = contentStack; stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo:root.topAnchor,constant:Self.verticalPadding),
            stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:Self.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-Self.horizontalPadding),
            stack.bottomAnchor.constraint(lessThanOrEqualTo:root.bottomAnchor,constant:-Self.verticalPadding)
        ])
        let icon = MothLogoView(); logoView = icon; icon.reveal = { [weak self] in self?.startMothFlight() }; icon.setAccessibilityRole(.button); icon.image = Bundle.main.url(forResource:"AboutMoth",withExtension:"png").flatMap { NSImage(contentsOf:$0) } ?? NSApp.applicationIconImage; icon.imageScaling = .scaleProportionallyUpOrDown; icon.setAccessibilityLabel("White moth logo")
        stack.addArrangedSubview(icon); icon.widthAnchor.constraint(equalToConstant:128).isActive = true; icon.heightAnchor.constraint(equalToConstant:128).isActive = true
        stack.setCustomSpacing(10,after:icon)
        let title = NSTextField(labelWithString:"Moth"); title.font = .systemFont(ofSize:25,weight:.semibold); stack.addArrangedSubview(title)
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        let build = MothBuild.identifier
        versionText.stringValue = "Version \(version) (\(build))"; versionText.font = .systemFont(ofSize:11); versionText.textColor = .secondaryLabelColor; stack.addArrangedSubview(versionText)
        let websiteRow = NSStackView(); websiteRow.alignment = .centerY; websiteRow.spacing = 10
        for (index,site) in websites.enumerated() {
            if index > 0 { let dot = NSTextField(labelWithString:"·"); dot.textColor = .tertiaryLabelColor; websiteRow.addArrangedSubview(dot) }
            let link = NSButton(title:site.0,target:self,action:#selector(openWebsite(_:))); link.tag = index; link.isBordered = false; link.font = .systemFont(ofSize:12); styleLink(link); websiteRow.addArrangedSubview(link)
        }
        stack.addArrangedSubview(websiteRow)
        func separator() {
            if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(12,after:last) }
            let line = NSBox(); line.boxType = .separator; stack.addArrangedSubview(line); line.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
            stack.setCustomSpacing(12,after:line)
        }
        func heading(_ text: String) { let label = NSTextField(labelWithString:text); label.font = .systemFont(ofSize:13,weight:.semibold); stack.addArrangedSubview(label) }
        separator(); heading("Thanks")
        thanksText.font = .systemFont(ofSize:13); thanksText.alignment = .center; thanksText.maximumNumberOfLines = 0; stack.addArrangedSubview(thanksText)
        separator(); heading("Credits")
        let credits = NSStackView(); credits.orientation = .vertical; credits.alignment = .leading; credits.spacing = 4
        stack.addArrangedSubview(credits); credits.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        for start in stride(from:0,to:projects.count,by:2) {
            let row = NSStackView(); row.distribution = .fillEqually; row.spacing = 12
            credits.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:credits.widthAnchor).isActive = true
            for index in start..<min(start+2,projects.count) {
                let link = NSButton(title:projects[index].0,target:self,action:#selector(openProject(_:))); link.tag = index; link.isBordered = false; link.font = .systemFont(ofSize:12); styleLink(link); row.addArrangedSubview(link)
            }
        }
        let notices = NSButton(title:"Licences…",target:self,action:#selector(showLicences(_:))); notices.bezelStyle = .inline; notices.font = .systemFont(ofSize:11); styleLink(notices); stack.addArrangedSubview(notices)
        root.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width:480,height:ceil(stack.fittingSize.height)+Self.verticalPadding*2))
        root.layoutSubtreeIfNeeded(); window.center()
    }
    func startMothFlight() {
        guard swarm == nil,let root = window?.contentView,let image = logoView.image else { return }
        root.layoutSubtreeIfNeeded()
        guard let effect = MothSwarmView(frame:root.bounds,image:image,sourceRect:logoView.convert(logoView.bounds,to:root)) else { return }
        swarm = effect; effect.autoresizingMask = [.width,.height]
        priorResponder = window?.firstResponder
        effect.onFrame = { [weak self] time in self?.applyMothFlightFrame(time) }
        effect.onFinish = { [weak self,weak effect] in
            effect?.removeFromSuperview()
            guard let self else { return }
            self.contentStack.arrangedSubviews.forEach { $0.alphaValue = 1 }
            self.swarm = nil
            self.window?.makeFirstResponder(self.priorResponder ?? self.window?.contentView)
        }
        root.addSubview(effect); window?.makeFirstResponder(effect)
    }
    func applyMothFlightFrame(_ time: Double) {
        let t = Float(time)
        let envelope = MothSwarmView.smooth(0,1.1,t)*(1-MothSwarmView.smooth(9.2,11.4,t))
        for view in contentStack.arrangedSubviews where view !== logoView { view.alphaValue = CGFloat(1-envelope*0.94) }
        logoView.alphaValue = CGFloat(min(1,max(0,1-MothSwarmView.smooth(0.3,2.2,t)+MothSwarmView.smooth(9.5,11.4,t))))
    }
    private func styleLink(_ button: NSButton) {
        let color = NSColor(calibratedRed:0.68,green:0.75,blue:0.72,alpha:1)
        button.contentTintColor = color
        button.attributedTitle = NSAttributedString(string:button.title,attributes:[.font:button.font ?? NSFont.systemFont(ofSize:12),.foregroundColor:color])
    }
    @objc func openWebsite(_ sender: NSButton) { guard websites.indices.contains(sender.tag),let url = URL(string:websites[sender.tag].1) else { return }; NSWorkspace.shared.open(url) }
    required init?(coder: NSCoder) { fatalError() }
    @objc func openProject(_ sender: NSButton) { guard projects.indices.contains(sender.tag),let url = URL(string:projects[sender.tag].1) else { return }; NSWorkspace.shared.open(url) }
    @objc func showLicences(_ sender: Any?) {
        if licences == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:470),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.appearance = NSAppearance(named:.darkAqua); window.title = "Licences"; window.isReleasedWhenClosed = false; window.center()
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; window.contentView = scroll
            let text = NSTextView(frame:NSRect(x:0,y:0,width:650,height:470)); text.isEditable = false; text.isRichText = false; text.font = .monospacedSystemFont(ofSize:11,weight:.regular); text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width:16,height:16)
            let documents = ["LICENSE", "NOTICE", "THIRD-PARTY-NOTICES", "FONT-PERMISSION", "TRADEMARKS"]
            text.string = documents.map { name in
                guard let url = Bundle.main.url(forResource: name, withExtension: nil),
                      let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    return "\(name) unavailable."
                }
                return contents
            }.joined(separator: "\n\n")
            scroll.documentView = text; licences = NSWindowController(window:window)
        }
        licences?.showWindow(nil); licences?.window?.makeKeyAndOrderFront(nil)
    }
}
extension App {
    @objc func showAboutWindow(_ sender: Any?) {
        if aboutWindow == nil { aboutWindow = AboutWindowController() }
        aboutWindow?.showWindow(nil); aboutWindow?.window?.makeKeyAndOrderFront(nil)
    }
}

private final class AboutContentView: NSView {
    static let background = NSColor(calibratedRed:0.055,green:0.067,blue:0.072,alpha:1)
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { Self.background.setFill(); dirtyRect.fill() }
}

struct MothReleaseNotes: Decodable {
    struct Section: Decodable { let title:String; let items:[String] }
    let version:String
    let build:Int
    let status:String
    let commit:String?
    let sections:[Section]
    static let historyURL = URL(string:"https://getmoth.dev/docs/changelog/")!
    static func load() throws -> [Self] {
        guard let url = Bundle.main.url(forResource:"ReleaseNotes",withExtension:"json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Self].self,from:Data(contentsOf:url))
    }
}

final class ReleaseNotesWindowController: NSWindowController {
    let textView = NSTextView()
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:570),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "What’s New in Moth"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width:440,height:360)
        window.appearance = NSAppearance(named:.darkAqua)
        window.backgroundColor = NSColor(white:0.065,alpha:1)
        let root = NSView(); window.contentView = root
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(scroll)
        textView.isEditable = false; textView.isSelectable = true; textView.drawsBackground = false
        textView.isHorizontallyResizable = false; textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]; textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width:24,height:24)
        scroll.documentView = textView
        let link = NSButton(title:"Full changelog on getmoth.dev",target:self,action:#selector(openHistory(_:)))
        link.bezelStyle = .rounded; link.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(link)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:root.topAnchor),scroll.bottomAnchor.constraint(equalTo:link.topAnchor,constant:-12),
            link.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),link.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20)
        ])
        let output = NSMutableAttributedString()
        func append(_ text:String,size:CGFloat = 13,weight:NSFont.Weight = .regular,secondary:Bool = false,space:CGFloat = 8) {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = space
            output.append(NSAttributedString(string:text+"\n",attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:secondary ? NSColor.secondaryLabelColor:NSColor.labelColor,.paragraphStyle:paragraph]))
        }
        do {
            for release in try MothReleaseNotes.load() {
                append("Moth \(release.version)",size:23,weight:.semibold,space:4)
                let currentVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String
                let buildIdentity=release.version == currentVersion ? MothBuild.identifier:release.commit
                let metadata=[buildIdentity.map { "Build \($0)" },release.status == "unreleased" ? "Unreleased":nil].compactMap{$0}.joined(separator:" · ")
                if !metadata.isEmpty { append(metadata,secondary:true,space:18) }
                for section in release.sections {
                    append(section.title,size:14,weight:.semibold)
                    for item in section.items { append("• "+item) }
                }
                append("",space:18)
            }
        } catch { append("Release notes could not be loaded. The full changelog is available on getmoth.dev.") }
        textView.textStorage?.setAttributedString(output)
        window.center()
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func openHistory(_ sender:Any?) { NSWorkspace.shared.open(MothReleaseNotes.historyURL) }
}
