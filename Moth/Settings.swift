// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import UniformTypeIdentifiers

private final class SettingsAction: NSObject {
    let run: (Any?) -> Void
    init(_ run: @escaping (Any?) -> Void) { self.run = run }
    @objc func invoke(_ sender: Any?) { run(sender) }
}

/// One native settings window, backed by the same validated, live-reloaded TOML document.
final class AppearancePanel: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate, NSWindowDelegate {
    unowned let application: App
    let livePreview = TerminalPreviewView(frame: .zero)
    let tabs = NSTabView()
    let navigation = NSTableView()
    private(set) var editingProfileID: String?
    private let profileSelector = NSPopUpButton()
    private let defaultProfileSelector = NSPopUpButton()
    private let profileSummary = NSTextField(wrappingLabelWithString:"")
    private var profileButtons: [NSButton] = []
    private var pendingAudioProfileID: String?
    var settingsConfig: Configuration {
        get { application.settings(for:editingProfileID) }
        set {
            if let current = application.profile(editingProfileID),let index = application.profiles.firstIndex(where: { $0.id == current.id }) {
                var next = TerminalProfile(name:current.name,configuration:newValue); next.id = current.id; application.profiles[index] = next
            } else { application.config = newValue }
        }
    }
    private var editingFile: URL { editingProfileID.map { ProfileStore.url($0,in:application.profileDirectory) } ?? Configuration.url }
    func selectProfile(_ id: String?) {
        let next = application.profile(id)?.id
        guard next != editingProfileID else { return }; flushAudioEdits(); editingProfileID = next; featureSignature = ""; refresh()
    }
    private func refreshProfileSelectors() {
        if editingProfileID != nil && application.profile(editingProfileID) == nil { editingProfileID = nil }
        profileSelector.removeAllItems(); profileSelector.addItem(withTitle:"Default")
        defaultProfileSelector.removeAllItems(); defaultProfileSelector.addItem(withTitle:"Default")
        for profile in application.profiles { profileSelector.addItem(withTitle:profile.name); profileSelector.lastItem?.representedObject = profile.id; defaultProfileSelector.addItem(withTitle:profile.name); defaultProfileSelector.lastItem?.representedObject = profile.id }
        profileSelector.selectItem(at:profileSelector.itemArray.firstIndex { ($0.representedObject as? String) == editingProfileID } ?? 0)
        defaultProfileSelector.selectItem(at:defaultProfileSelector.itemArray.firstIndex { ($0.representedObject as? String ?? "") == application.config.defaultProfileID } ?? 0)
        for button in profileButtons { button.isEnabled = editingProfileID != nil }
        profileSummary.stringValue = editingProfileID == nil ? "Default supplies settings for windows without a named profile. Create a profile from these settings, or select one above to edit it." : "Changes apply to windows using this profile. Shell and starting-directory changes apply to new sessions. Shortcuts, macros, close confirmations and diagnostic/clipboard options remain app-wide."
        configPath.stringValue = editingFile.path; configPath.toolTip = editingFile.path
    }
    private let sections = ["Theme","Background","Font","Colours","Cursor","Window","Shell","Bell","Keyboard Sounds","Profiles","Macros","Shortcuts","Look Up & Manuals","Closing","Updates","Advanced"]
    private let symbols = ["paintpalette","sparkles","textformat","slider.horizontal.3","character.cursor.ibeam","macwindow","terminal","bell","pianokeys","person.crop.rectangle.stack","record.circle","command","book","xmark.circle","arrow.triangle.2.circlepath","gearshape.2"]
    private let subtitles = [
        "Theme":"Choose a starting palette, then make it your own.",
        "Background":"Choose a plain colour, moving colour field or your own picture.",
        "Font":"Shape your terminal’s type, spacing and OpenType details.",
        "Colours":"Fine-tune text and the sixteen ANSI colours.",
        "Cursor":"Shape, movement and colour for your insertion point.",
        "Window":"Glass, borders and the details around your terminal.",
        "Shell":"Defaults for new sessions and terminal history.",
        "Bell":"Choose how the terminal gets your attention.",
        "Keyboard Sounds":"A subtle accompaniment to your typing.",
        "Profiles":"Choose appearance and session defaults for each window.",
        "Shortcuts":"Make everyday actions easy to reach.",
        "Look Up & Manuals":"Definitions and local command documentation, within reach.",
        "Closing":"Control when Moth asks before ending a session.",
        "Updates":"Check for new releases of Moth."
    ]
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let configPath = NSTextField(labelWithString: Configuration.url.path)
    let backgroundNote = NSTextField(wrappingLabelWithString: "A dynamic background or picture overrides the chosen theme’s background. Your text colours stay the same.")
    let backgroundEnabled = NSButton(checkboxWithTitle: "Dynamic background", target: nil, action: nil)
    let imageControls = NSStackView()
    let imageDescription = NSTextField(labelWithString:"")
    let animatedControls = AnimatedBackgroundControls()
    let plainBackgroundControls = PaintControls(title: "Background")
    private(set) var soundButtons: [NSButton] = []
    private var pageTop: NSLayoutConstraint!
    private var pageTopWithoutPreview: NSLayoutConstraint!
    private(set) var paletteButtons: [NSButton] = []
    private(set) var fields: [String: NSView] = [:]
    private(set) var pages: [String: NSStackView] = [:]
    private(set) var scrollViews: [String: NSScrollView] = [:]
    private var actions: [SettingsAction] = []
    private var refreshers: [() -> Void] = []
    private var numericAdjusters: [ObjectIdentifier:(Double)->Void] = [:]
    private(set) var numericSteppers: [String:NSStepper] = [:]
    private var textActions: [ObjectIdentifier: () -> Void] = [:]
    private var refreshing = false
    private var showingFileError = false
    private var pendingAudioSave: DispatchWorkItem?
    private var pendingAudioValues: [String:Double] = [:]
    private var previewHeight: NSLayoutConstraint!
    private let macroSelector = NSPopUpButton()
    private let macroEditor = NSTextView()
    private let macroShortcut = NSTextField()
    private let macroSubmit = NSButton(checkboxWithTitle:"Press Enter after inserting text",target:nil,action:nil)
    private let macroSummary = NSTextField(wrappingLabelWithString:"")
    private var selectedMacro = ""
    private let encodingSelector = NSPopUpButton()
    private let fontFeatures = NSStackView()
    private var featureSignature = ""
    private var featureActions: [SettingsAction] = []
    private var fontDescription = NSTextField(labelWithString: "")

    init(application: App) {
        self.application = application
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 980,height: 800), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self; window.title = "Settings"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 940,height: 700); window.center()
        let root = SettingsRootView(); window.contentView = root
        let scopeRow = NSStackView(); scopeRow.alignment = .centerY; scopeRow.spacing = 10
        let scopeTitle = NSTextField(labelWithString:"Editing profile"); scopeTitle.font = .systemFont(ofSize:12,weight:.medium)
        profileSelector.setAccessibilityLabel("Profile to edit"); profileSelector.setContentCompressionResistancePriority(.defaultLow,for:.horizontal); profileSelector.widthAnchor.constraint(lessThanOrEqualToConstant:300).isActive = true; profileSelector.widthAnchor.constraint(greaterThanOrEqualToConstant:180).isActive = true
        action(profileSelector) { [weak self] _ in guard let self else { return }; self.selectProfile(self.profileSelector.selectedItem?.representedObject as? String) }
        scopeRow.addArrangedSubview(scopeTitle); scopeRow.addArrangedSubview(profileSelector); scopeRow.addArrangedSubview(NSView()); scopeRow.addArrangedSubview(button("Manage Profiles…") { [weak self] in self?.tabs.selectTabViewItem(withIdentifier:"Profiles") })
        scopeRow.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(scopeRow)
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow
        let sidebarTitle = NSTextField(labelWithString:"Settings"); sidebarTitle.font = .systemFont(ofSize:17,weight:.semibold)
        let navigationScroll = NSScrollView(); navigationScroll.drawsBackground = false; navigationScroll.hasVerticalScroller = true
        navigation.headerView = nil; navigation.backgroundColor = .clear; navigation.rowHeight = 30; navigation.intercellSpacing = NSSize(width:0,height:3)
        navigation.style = .sourceList
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section")); column.resizingMask = .autoresizingMask; navigation.addTableColumn(column)
        navigation.dataSource = self; navigation.delegate = self; navigation.setAccessibilityLabel("Settings sections"); navigationScroll.documentView = navigation
        for view in [sidebar,sidebarTitle,navigationScroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo:root.leadingAnchor),sidebar.topAnchor.constraint(equalTo:root.topAnchor),sidebar.bottomAnchor.constraint(equalTo:root.bottomAnchor),sidebar.widthAnchor.constraint(equalToConstant:210),
            sidebarTitle.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:20),sidebarTitle.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:25),
            navigationScroll.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:8),navigationScroll.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-8),navigationScroll.topAnchor.constraint(equalTo:sidebarTitle.bottomAnchor,constant:20),navigationScroll.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-16)
        ])
        tabs.tabViewType = .noTabsNoBorder; tabs.delegate = self
        let footer = NSStackView(); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 5
        let note = NSTextField(wrappingLabelWithString: "Settings save automatically. You can also edit the configuration file; saved edits reload live.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        configPath.setContentCompressionResistancePriority(.defaultLow,for:.horizontal); configPath.isSelectable = true; configPath.font = .monospacedSystemFont(ofSize: 11,weight: .regular); configPath.lineBreakMode = .byTruncatingMiddle; configPath.toolTip = Configuration.url.path
        let fileRow = NSStackView(views: [configPath, button("Edit Configuration…") { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.editingFile) }, button("Show in Finder") { [weak self] in guard let self else { return }; NSWorkspace.shared.activateFileViewerSelecting([self.editingFile]) }])
        fileRow.spacing = 10; fileRow.alignment = .centerY
        footer.addArrangedSubview(note); footer.addArrangedSubview(fileRow)
        errorLabel.textColor = .systemRed; errorLabel.font = .systemFont(ofSize: 11); errorLabel.isHidden = true
        footer.addArrangedSubview(errorLabel)
        for view in [livePreview,tabs,footer] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        previewHeight = livePreview.heightAnchor.constraint(equalToConstant:164)
        pageTop = tabs.topAnchor.constraint(equalTo:livePreview.bottomAnchor,constant:16)
        pageTopWithoutPreview = tabs.topAnchor.constraint(equalTo:scopeRow.bottomAnchor,constant:16)
        NSLayoutConstraint.activate([
            scopeRow.topAnchor.constraint(equalTo:root.topAnchor,constant:24),scopeRow.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:24),scopeRow.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),scopeRow.heightAnchor.constraint(equalToConstant:28),
            livePreview.topAnchor.constraint(equalTo: scopeRow.bottomAnchor,constant: 16),livePreview.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: 24),livePreview.trailingAnchor.constraint(equalTo: root.trailingAnchor,constant: -24),previewHeight,
            pageTop,tabs.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: 8),tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor,constant: -8),tabs.bottomAnchor.constraint(equalTo: footer.topAnchor,constant: -12),
            footer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: 24),footer.trailingAnchor.constraint(equalTo: root.trailingAnchor,constant: -24),footer.bottomAnchor.constraint(equalTo: root.bottomAnchor,constant: -16),fileRow.widthAnchor.constraint(equalTo: footer.widthAnchor)
        ])
        buildTheme(); buildBackground(); buildText(); buildColours(); buildCursor(); buildWindow(); buildShell(); buildBell(); buildKeyboardSounds(); buildProfiles(); buildMacros(); buildShortcuts(); buildLookup(); buildClosing(); buildUpdates(); buildAdvanced()
        navigation.reloadData(); navigation.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func refresh() {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        refreshProfileSelectors()
        var sample = settingsConfig; sample.window.opacity = 1; sample.window.frosted = false
        updatePreviewVisibility()
        window?.contentView?.layoutSubtreeIfNeeded()
        livePreview.apply(sample)
        for refresh in refreshers { refresh() }
        refreshUpdateStatus()
        let config = settingsConfig
        for card in paletteButtons { card.state = card.identifier?.rawValue == config.theme ? .on : .off }
        fontDescription.stringValue = "\(NSFont(name: config.fontName,size: config.fontSize)?.displayName ?? config.fontName) · \(Int(config.fontSize)) pt"
        refreshFontFeatures()
        let plain = config.background.style == "solid"
        backgroundEnabled.state = config.background.style == "flow" ? .on : .off; animatedControls.isHidden = config.background.style != "flow"; plainBackgroundControls.isHidden = !plain
        imageControls.isHidden = config.background.style != "image"
        imageDescription.stringValue = config.background.style == "image" ? ((config.background.imagePath as NSString).lastPathComponent + (FlowBackgroundView.loadBackgroundImage(config.background.imagePath) == nil ? " · Image unavailable" : "")) : "No picture in use"
        imageDescription.toolTip = config.background.imagePath
        animatedControls.update(config.background); plainBackgroundControls.update(config.background.paint,fallback: config.colors.0,second: config.colors.2)
        if let error = application.configError ?? application.profileError { showingFileError = true; showError(error.localizedDescription) }
        else if showingFileError { showingFileError = false; errorLabel.isHidden = true; errorLabel.stringValue = "" }
    }
    @discardableResult
    func commit(_ change: (inout Configuration) -> Void) -> Bool {
        guard !refreshing else { return false }
        flushAudioEdits()
        var candidate = settingsConfig; change(&candidate)
        do {
            try application.saveSettings(candidate,profileID:editingProfileID)
            application.configError = nil
            showingFileError = false; errorLabel.isHidden = true; errorLabel.stringValue = ""
            application.applyAppearance(); application.buildMenu(); return true
        } catch { showError(error.localizedDescription); return false }
    }
    private func showError(_ message: String) { errorLabel.textColor = .systemRed; errorLabel.stringValue = message; errorLabel.isHidden = false }
    private func action(_ control: NSControl, _ run: @escaping (Any?) -> Void) {
        let action = SettingsAction(run); actions.append(action); control.target = action; control.action = #selector(SettingsAction.invoke(_:))
    }
    private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title,target: nil,action: nil); action(button) { _ in run() }; return button
    }
    private func register(_ id: String, _ view: NSView) { fields[id] = view; view.identifier = NSUserInterfaceItemIdentifier(id) }
    private func page(_ name: String, grouped: Bool = true) -> NSStackView {
        let item = NSTabViewItem(identifier: name); item.label = name
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; item.view = scroll
        let document = AppearanceDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        let heading = NSTextField(labelWithString:name); heading.font = .systemFont(ofSize:22,weight:.semibold)
        let subtitle = NSTextField(wrappingLabelWithString:subtitles[name] ?? ""); subtitle.font = .systemFont(ofSize:12); subtitle.textColor = .secondaryLabelColor
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        for view in [heading,subtitle,stack] { view.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(view) }
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            heading.topAnchor.constraint(equalTo:document.topAnchor,constant:8),heading.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:16),
            subtitle.topAnchor.constraint(equalTo:heading.bottomAnchor,constant:6),subtitle.leadingAnchor.constraint(equalTo:heading.leadingAnchor),subtitle.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-16),
            stack.topAnchor.constraint(equalTo:subtitle.bottomAnchor,constant:24),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-16),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-24)
        ])
        let content = grouped ? group(nil,in:stack) : stack
        pages[name] = stack; scrollViews[name] = scroll; tabs.addTabViewItem(item); return content
    }
    private func group(_ title: String?, in page: NSStackView) -> NSStackView {
        if let title {
            let label = NSTextField(labelWithString:title); label.font = .systemFont(ofSize:12,weight:.semibold); label.textColor = .secondaryLabelColor
            page.addArrangedSubview(label); page.setCustomSpacing(8,after:label)
        }
        let card = NSBox(); card.boxType = .custom; card.titlePosition = .noTitle; card.cornerRadius = 10; card.borderWidth = 0.5; card.borderColor = .separatorColor; card.fillColor = .controlBackgroundColor; card.contentViewMargins = .zero
        let body = NSView(); card.contentView = body
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 12; content.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(content)
        page.addArrangedSubview(card); card.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),content.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),content.topAnchor.constraint(equalTo:body.topAnchor,constant:14),content.bottomAnchor.constraint(equalTo:body.bottomAnchor,constant:-14)])
        return content
    }
    private func updatePreviewVisibility() {
        let section = tabs.selectedTabViewItem?.identifier as? String ?? "Theme"
        let visual = ["Theme","Background","Font","Colours","Cursor","Window"].contains(section)
        livePreview.isHidden = !visual
        previewHeight.constant = max(196,settingsConfig.fontSize*settingsConfig.typography.lineHeight*6+72)
        if visual { pageTopWithoutPreview.isActive = false; pageTop.isActive = true }
        else { pageTop.isActive = false; pageTopWithoutPreview.isActive = true }
    }
    func windowWillClose(_ notification: Notification) { flushAudioEdits(); KeyboardSoundPlayer.shared.stopAudition() }
    static func terminalCursorIcon() -> NSImage {
        let image = NSImage(size:NSSize(width:18,height:18),flipped:false) { _ in
            ("A" as NSString).draw(at:NSPoint(x:0,y:1),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:NSColor.black])
            NSColor.black.setFill(); NSRect(x:11,y:2,width:6,height:14).fill(); return true
        }
        image.isTemplate = true; return image
    }
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(), icon = NSImageView(), label = NSTextField(labelWithString:sections[row])
        icon.image = sections[row] == "Cursor" ? Self.terminalCursorIcon() : NSImage(systemSymbolName:symbols[row],accessibilityDescription:nil); icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize:13,weight:.medium)
        for view in [icon,label] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        cell.textField = label; cell.imageView = icon
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:18),icon.heightAnchor.constraint(equalToConstant:18),label.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:10),label.centerYAnchor.constraint(equalTo:cell.centerYAnchor),label.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-4)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = navigation.selectedRow
        if index >= 0, index < tabs.numberOfTabViewItems, tabs.selectedTabViewItem !== tabs.tabViewItem(at:index) { tabs.selectTabViewItem(at:index) }
    }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let item = tabViewItem,let name = item.identifier as? String,let index = sections.firstIndex(of:name) else { return }
        if navigation.selectedRow != index { navigation.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false) }
        if previewHeight != nil { updatePreviewVisibility() }
        if name != "Keyboard Sounds" { KeyboardSoundPlayer.shared.stopAudition() }
    }
    private func section(_ title: String, in page: NSStackView) {
        let separator = NSBox(); separator.boxType = .separator
        page.addArrangedSubview(separator); separator.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        let label = NSTextField(labelWithString:title); label.font = .systemFont(ofSize:12,weight:.semibold); label.textColor = .secondaryLabelColor; page.addArrangedSubview(label)
    }
    private func note(_ text: String, in page: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: text); label.textColor = .secondaryLabelColor; label.font = .systemFont(ofSize: 12)
        page.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
    }
    private func row(_ title: String, _ control: NSView, in page: NSStackView) {
        let line: NSStackView
        if title.isEmpty { line = NSStackView(views:[control,NSView()]) }
        else {
            let label = NSTextField(labelWithString:title); label.font = .systemFont(ofSize:13)
            let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
            line = NSStackView(views:[label,spacer,control])
            label.setContentCompressionResistancePriority(.required,for:.horizontal)
            control.widthAnchor.constraint(equalToConstant:300).isActive = true
        }
        line.orientation = .horizontal; line.alignment = .centerY; line.spacing = 16
        line.heightAnchor.constraint(greaterThanOrEqualToConstant:30).isActive = true
        page.addArrangedSubview(line); line.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
    }
    @discardableResult private func check(_ id: String, _ title: String, _ key: WritableKeyPath<Configuration,Bool>, in page: NSStackView) -> NSButton {
        let box = NSButton(checkboxWithTitle: title,target: nil,action: nil); register(id,box)
        action(box) { [weak self,weak box] _ in guard let self,let box else { return }; self.commit { $0[keyPath:key] = box.state == .on } }
        refreshers.append { [weak self,weak box] in guard let self else { return }; box?.state = self.settingsConfig[keyPath:key] ? .on : .off }
        row("",box,in:page); return box
    }
    private func choice(_ id: String, _ title: String, _ key: WritableKeyPath<Configuration,String>, _ values: [(String,String)], in page: NSStackView) {
        let popup = NSPopUpButton(); popup.addItems(withTitles: values.map(\.0)); register(id,popup); popup.setAccessibilityLabel(title)
        action(popup) { [weak self,weak popup] _ in guard let self,let popup else { return }; self.commit { $0[keyPath:key] = values[popup.indexOfSelectedItem].1 } }
        refreshers.append { [weak self,weak popup] in guard let self else { return }; popup?.selectItem(at: values.firstIndex(where: { $0.1 == self.settingsConfig[keyPath:key] }) ?? 0) }
        row(title,popup,in:page)
    }
    private func text(_ id: String, _ title: String, get: @escaping (Configuration)->String, set: @escaping (inout Configuration,String)->Void, in page: NSStackView) -> NSTextField {
        let field = NSTextField(); field.delegate = self; register(id,field); field.setAccessibilityLabel(title)
        let save: () -> Void = { [weak self,weak field] in guard let self,let field else { return }; self.commit { set(&$0,field.stringValue) } }
        textActions[ObjectIdentifier(field)] = save; action(field) { _ in save() }
        refreshers.append { [weak self,weak field] in guard let self,let field,field.currentEditor() == nil else { return }; field.stringValue = get(self.settingsConfig) }
        row(title,field,in:page); return field
    }
    func controlTextDidEndEditing(_ obj: Notification) { if let field = obj.object as? NSTextField { textActions[ObjectIdentifier(field)]?() } }
    func control(_ control: NSControl,textView: NSTextView,doCommandBy selector: Selector) -> Bool {
        guard let field = control as? NSTextField,let adjust = numericAdjusters[ObjectIdentifier(field)] else { return false }
        let multiplier = NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? 10.0 : 1.0
        if selector == #selector(NSResponder.moveUp(_:)) || selector == #selector(NSResponder.moveDown(_:)) {
            adjust(selector == #selector(NSResponder.moveUp(_:)) ? multiplier : -multiplier)
            textView.string = field.stringValue; textView.setSelectedRange(NSRange(location:textView.string.utf16.count,length:0)); return true
        }
        return false
    }
    private func number(_ id: String, _ title: String, range: ClosedRange<Double>, get: @escaping (Configuration)->Double, set: @escaping (inout Configuration,Double)->Void, in page: NSStackView) {
        let field = NSTextField(); field.delegate = self; register(id,field); field.setAccessibilityLabel(title); field.widthAnchor.constraint(equalToConstant:100).isActive = true
        let step: Double = id == "typography.lineHeight" ? 0.05 : id == "typography.characterSpacing" ? 0.25 : id == "bell.duration" ? 0.01 : id == "cursor.period" ? 0.1 : id == "window.borderWidth" ? 0.25 : 1
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 3; formatter.usesGroupingSeparator = false
        let save: () -> Void = { [weak self,weak field] in
            guard let self,let field else { return }
            guard let value = formatter.number(from:field.stringValue)?.doubleValue,range.contains(value) else { self.showError("\(title) must be between \(range.lowerBound) and \(range.upperBound)."); return }
            self.commit { set(&$0,value) }
        }
        textActions[ObjectIdentifier(field)] = save; action(field) { _ in save() }
        let stepper = NSStepper(); stepper.minValue = range.lowerBound; stepper.maxValue = range.upperBound; stepper.increment = step; stepper.valueWraps = false; stepper.autorepeat = true; stepper.setAccessibilityLabel("Adjust \(title.lowercased())")
        numericSteppers[id] = stepper
        let adjust: (Double)->Void = { [weak self,weak field,weak stepper] direction in
            guard let self,let field else { return }
            let old = formatter.number(from:field.stringValue)?.doubleValue ?? get(self.settingsConfig)
            let value = max(range.lowerBound,min(range.upperBound,((old+direction*step)*1000).rounded()/1000))
            field.stringValue = formatter.string(from:NSNumber(value:value)) ?? ""; stepper?.doubleValue = value
            self.commit { set(&$0,value) }
        }
        numericAdjusters[ObjectIdentifier(field)] = adjust
        action(stepper) { [weak field,weak stepper] _ in guard let field,let stepper else { return }; field.stringValue = formatter.string(from:NSNumber(value:stepper.doubleValue)) ?? ""; save() }
        refreshers.append { [weak self,weak field,weak stepper] in guard let self,let field,field.currentEditor() == nil else { return }; let value = get(self.settingsConfig); field.stringValue = formatter.string(from:NSNumber(value:value)) ?? ""; stepper?.doubleValue = value }
        let wrap = NSStackView(views:[field,stepper,NSView()]); wrap.spacing = 6; row(title,wrap,in:page)
    }
    private func slider(_ id: String, _ title: String, _ key: WritableKeyPath<Configuration,Double>, range: ClosedRange<Double>, in page: NSStackView) {
        let slider = NSSlider(value: range.lowerBound,minValue: range.lowerBound,maxValue: range.upperBound,target: nil,action: nil); slider.isContinuous = id == "keyboardSound.volume" || id == "keyboardSound.reverb"; register(id,slider); slider.setAccessibilityLabel(title)
        let value = NSTextField(labelWithString: ""); value.font = .monospacedDigitSystemFont(ofSize: 11,weight: .regular); value.widthAnchor.constraint(equalToConstant: 52).isActive = true
        action(slider) { [weak self,weak slider,weak value] _ in
            guard let self,let slider else { return }
            if id == "keyboardSound.volume" || id == "keyboardSound.reverb" {
                if self.pendingAudioValues.isEmpty { self.pendingAudioProfileID = self.editingProfileID }
                self.settingsConfig[keyPath:key] = slider.doubleValue; self.pendingAudioValues[id] = slider.doubleValue
                KeyboardSoundPlayer.shared.update(self.settingsConfig.keyboardSound)
                value?.stringValue = "\(Int((slider.doubleValue*100).rounded()))%"
                self.pendingAudioSave?.cancel()
                let save = DispatchWorkItem { [weak self] in self?.flushAudioEdits() }; self.pendingAudioSave = save
                DispatchQueue.main.asyncAfter(deadline:.now()+0.15,execute:save)
            } else { self.commit { $0[keyPath:key] = slider.doubleValue } }
        }
        refreshers.append { [weak self,weak slider,weak value] in guard let self else { return }; let v = self.settingsConfig[keyPath:key]; slider?.doubleValue = v; value?.stringValue = range == 0...1 ? "\(Int((v*100).rounded()))%" : String(format:"%.2g",v) }
        let wrap = NSStackView(views:[slider,value]); wrap.spacing = 10; row(title,wrap,in:page)
    }
    func applyPendingAudioEdits(to config: inout Configuration) {
        guard !pendingAudioValues.isEmpty else { return }
        var target = application.profile(pendingAudioProfileID)?.applying(to:config) ?? config
        if let volume = pendingAudioValues["keyboardSound.volume"] { target.keyboardSound.volume = volume }
        if let reverb = pendingAudioValues["keyboardSound.reverb"] { target.keyboardSound.reverb = reverb }
        if let current = application.profile(pendingAudioProfileID),let index = application.profiles.firstIndex(where: { $0.id == current.id }) {
            var next = TerminalProfile(name:current.name,configuration:target); next.id = current.id; application.profiles[index] = next
        } else { config = target }
    }
    func flushAudioEdits() {
        pendingAudioSave?.cancel(); pendingAudioSave = nil
        guard !pendingAudioValues.isEmpty else { return }
        do {
            let document = try Configuration.load(); application.config = document
            if let id = pendingAudioProfileID,let index = application.profiles.firstIndex(where: { $0.id == id }) {
                application.profiles[index] = try ProfileStore.load(ProfileStore.url(id,in:application.profileDirectory),base:document)
            }
            var candidate = application.settings(for:pendingAudioProfileID)
            if let volume = pendingAudioValues["keyboardSound.volume"] { candidate.keyboardSound.volume = volume }
            if let reverb = pendingAudioValues["keyboardSound.reverb"] { candidate.keyboardSound.reverb = reverb }
            try application.saveSettings(candidate,profileID:pendingAudioProfileID)
            pendingAudioValues = [:]; pendingAudioProfileID = nil; application.configError = nil
        } catch { showError(error.localizedDescription) }
    }
    private func resetPreferences() {
        let alert = NSAlert(); alert.messageText = "Reset All Preferences?"; alert.informativeText = "Restore Moth’s defaults and reset named profiles. Current configuration and profile files are backed up. Saved layouts and running shells are kept."
        alert.addButton(withTitle:"Reset Preferences"); alert.addButton(withTitle:"Cancel")
        alert.window.defaultButtonCell = alert.buttons.last?.cell as? NSButtonCell
        guard let window else { return }
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn,let self else { return }
            self.flushAudioEdits(); self.pendingAudioSave?.cancel(); self.pendingAudioValues = [:]
            do {
                let (defaults,backup) = try Configuration.resetPreferences()
                try ProfileStore.archiveAll(in:self.application.profileDirectory)
                self.editingProfileID = nil; self.application.profiles = []
                for window in self.application.windows { window.profileID = nil; window.profileSnapshot = nil; window.zoomFontSize = nil }
                self.application.macroPlayer.stop(); MacroRecorder.shared.cancel()
                self.application.secureKeyboardEntry = false; self.application.updateSecureInput()
                self.application.config = defaults; self.application.configError = nil; self.application.applyAppearance(); self.application.buildMenu()
                self.errorLabel.textColor = .secondaryLabelColor; self.errorLabel.stringValue = backup.map { "Preferences reset. Backup: \($0.path)" } ?? "Preferences reset."; self.errorLabel.isHidden = false
            } catch { self.showError(error.localizedDescription) }
        }
    }
    private func colour(_ id: String, _ title: String, get: @escaping (Configuration)->NSColor, set: @escaping (inout Configuration,String)->Void, in page: NSStackView) {
        let well = NSColorWell(); if #available(macOS 14.0,*) { well.supportsAlpha = false }; register(id,well); well.setAccessibilityLabel(title); well.widthAnchor.constraint(equalToConstant: 60).isActive = true
        action(well) { [weak self,weak well] _ in guard let self,let well else { return }; self.commit { set(&$0,well.color.rgbHex) } }
        refreshers.append { [weak self,weak well] in guard let self else { return }; well?.color = get(self.settingsConfig) }
        let wrap = NSStackView(views:[well,NSView()]); row(title,wrap,in:page)
    }
    private func paint(_ id: String, _ title: String, _ key: WritableKeyPath<Configuration,Configuration.Paint>, fallback: @escaping (Configuration)->NSColor, in page: NSStackView) -> PaintControls {
        let controls = PaintControls(title:title); controls.changed = { [weak self] value in self?.commit { $0[keyPath:key] = value } }
        register(id+".type",controls.type); register(id+".colors",controls); register(id+".angle",controls.angle)
        refreshers.append { [weak self,weak controls] in guard let self else { return }; let c = self.settingsConfig; controls?.update(c[keyPath:key],fallback:fallback(c),second:c.colors.2) }
        page.addArrangedSubview(controls); controls.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true; return controls
    }
    private func paletteChange(_ config: inout Configuration, _ key: WritableKeyPath<Configuration.Palette,String>, _ value: String) {
        let colors = config.colors
        var palette = config.palette ?? Configuration.Palette(background:colors.0.rgbHex,foreground:colors.1.rgbHex,accent:colors.2.rgbHex)
        palette[keyPath:key] = value; config.palette = palette
    }
    private func buildTheme() {
        let page = page("Theme")
        note("A theme supplies starting colours. Font, cursor and background settings can be customised in this window. Choosing a theme resets custom theme colours.",in:page)
        for offset in stride(from:0,to:Configuration.themeNames.count,by:3) {
            let line = NSStackView(); line.orientation = .horizontal; line.distribution = .fillEqually; line.spacing = 10
            page.addArrangedSubview(line); line.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
            for name in Configuration.themeNames[offset..<min(offset+3,Configuration.themeNames.count)] {
                let card = AppearancePreviewButton(title:Configuration.themeTitle(name),target:nil,action:nil)
                card.identifier = NSUserInterfaceItemIdentifier(name); card.setButtonType(.toggle); card.isBordered = false
                // Keep the miniature window at its original aspect ratio above the label.
                let ratio: CGFloat = 176.0/280.0
                card.heightAnchor.constraint(equalTo:card.widthAnchor,multiplier:ratio,constant:45-16*ratio).isActive = true
                var sample = Configuration(); sample.theme = name; sample.background.style = "solid"
                card.image = ThemePreview.preview(sample,motion:false)
                action(card) { [weak self] _ in self?.commit { $0.theme = name; $0.palette = nil; $0.ansiColors = [] } }
                paletteButtons.append(card); line.addArrangedSubview(card)
            }
        }
        register("theme",page)
        section("Theme details",in:page)
        let override = NSButton(checkboxWithTitle:"Custom theme colours",target:nil,action:nil); register("palette.enabled",override)
        action(override) { [weak self,weak override] _ in guard let self,let override else { return }; self.commit { c in
            if override.state == .on { let colors = c.colors; c.palette = Configuration.Palette(background:colors.0.rgbHex,foreground:colors.1.rgbHex,accent:colors.2.rgbHex) } else { c.palette = nil }
        } }
        refreshers.append { [weak self,weak override] in override?.state = self?.settingsConfig.palette == nil ? .off : .on }; page.addArrangedSubview(override)
        colour("palette.background","Theme background",get:{$0.colors.0},set:{ [weak self] c,v in self?.paletteChange(&c,\.background,v) },in:page)
        colour("palette.accent","Accent colour",get:{$0.colors.2},set:{ [weak self] c,v in self?.paletteChange(&c,\.accent,v) },in:page)
        page.addArrangedSubview(button("Reset Theme Colours") { [weak self] in self?.commit { $0.palette = nil } })
    }
    private func buildBackground() {
        let page = page("Background")
        backgroundNote.textColor = .secondaryLabelColor; backgroundNote.font = .systemFont(ofSize:12)
        page.addArrangedSubview(backgroundNote); backgroundNote.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        register("background.style",backgroundEnabled)
        action(backgroundEnabled) { [weak self] _ in guard let self else { return }; self.commit { $0.background.style = self.backgroundEnabled.state == .on ? "flow" : "solid" } }
        page.addArrangedSubview(backgroundEnabled)
        page.addArrangedSubview(animatedControls); animatedControls.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        register("background.effectColors",animatedControls.colourRow); register("background.intensity",animatedControls.strength); register("background.speed",animatedControls.speed)
        animatedControls.changed = { [weak self] colors,strength,speed in self?.commit { $0.background.effectColors = colors; $0.background.intensity = strength; $0.background.speed = speed } }
        animatedControls.reset = { [weak self] in self?.commit { $0.background.resetAnimation() } }
        let motion = check("background.animated","Animate movement",\.background.animated,in:page)
        refreshers.append { [weak self,weak motion] in motion?.isHidden = self?.settingsConfig.background.style != "flow" }
        page.addArrangedSubview(plainBackgroundControls); plainBackgroundControls.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        register("background.paint.type",plainBackgroundControls.type); register("background.paint.colors",plainBackgroundControls); register("background.paint.angle",plainBackgroundControls.angle)
        plainBackgroundControls.changed = { [weak self] paint in self?.commit { $0.background.paint = paint } }
        let choose = NSButton(title:"Choose Picture…",target:nil,action:nil)
        register("background.imagePath",choose)
        action(choose) { [weak self] _ in
            guard let self,let window = self.window else { return }
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
            panel.beginSheetModal(for:window) { [weak self] result in
                guard result == .OK,let url = panel.url,let self else { return }
                guard FlowBackgroundView.loadBackgroundImage(url.path) != nil else { self.showError("This file could not be opened as a background picture."); return }
                self.commit { $0.background.imagePath = url.path; $0.background.style = "image" }
            }
        }
        row("Picture",choose,in:page)
        imageDescription.textColor = .secondaryLabelColor; imageDescription.font = .systemFont(ofSize:12); imageDescription.lineBreakMode = .byTruncatingMiddle
        page.addArrangedSubview(imageDescription); imageDescription.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        imageControls.orientation = .vertical; imageControls.alignment = .leading; imageControls.spacing = 14
        page.addArrangedSubview(imageControls); imageControls.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        choice("background.imageScale","Picture sizing",\.background.imageScale,[("Fill window","fill"),("Fit entire picture","fit")],in:imageControls)
        slider("background.imageOpacity","Picture strength",\.background.imageOpacity,range:0...1,in:imageControls)
        let remove = NSButton(title:"Remove Picture",target:nil,action:nil); register("background.removeImage",remove)
        action(remove) { [weak self] _ in self?.commit { $0.background.imagePath = ""; $0.background.style = "solid" } }
        imageControls.addArrangedSubview(remove)
        note("The picture stays in its original location. Moving or deleting it restores the theme background.",in:imageControls)
    }
    private func buildText() {
        let page = page("Font",grouped:false)
        let face = group("Typeface",in:page)
        let choose = button("Choose Font…") { [weak self] in self?.chooseFont() }; register("fontName",choose)
        let fontRow = NSStackView(views:[choose,NSView()]); row("Terminal font",fontRow,in:face)
        fontDescription.font = .systemFont(ofSize:12); fontDescription.textColor = .secondaryLabelColor; fontDescription.lineBreakMode = .byTruncatingMiddle
        face.addArrangedSubview(fontDescription); fontDescription.widthAnchor.constraint(equalTo:face.widthAnchor).isActive = true
        let bundled = NSPopUpButton(); bundled.addItem(withTitle:"Custom font")
        for font in Configuration.bundledFonts { bundled.addItem(withTitle:font.0) }
        action(bundled) { [weak self,weak bundled] _ in guard let self,let bundled,bundled.indexOfSelectedItem > 0 else { return }; self.commit { $0.fontName = Configuration.bundledFonts[bundled.indexOfSelectedItem-1].1 } }
        refreshers.append { [weak self,weak bundled] in guard let self else { return }; bundled?.selectItem(at:Configuration.bundledFonts.firstIndex { $0.1 == self.settingsConfig.fontName }.map { $0+1 } ?? 0) }
        row("Bundled fonts",bundled,in:face)
        number("fontSize","Font size (pt)",range:9...32,get:{$0.fontSize},set:{$0.fontSize = $1},in:face)
        note("Monospaced fonts keep the terminal grid aligned. Nerd Fonts include prompt symbols and icons.",in:face)
        let spacing = group("Spacing",in:page)
        number("typography.lineHeight","Line height (×)",range:1...2,get:{$0.typography.lineHeight},set:{$0.typography.lineHeight = $1},in:spacing)
        number("typography.characterSpacing","Character spacing (pt)",range:0...6,get:{$0.typography.characterSpacing},set:{$0.typography.characterSpacing = $1},in:spacing)
        note("Extra space applies to the terminal grid, including the cursor and selection. Text stays centred vertically.",in:spacing)
        let shaping = group("Shaping & styles",in:page)
        check("typography.antialias","Anti-alias text",\.typography.antialias,in:shaping)
        check("typography.ligatures","Enable ligatures",\.typography.ligatures,in:shaping)
        note("Join supported sequences such as ->, != and === while preserving terminal cells. The chosen font must supply the ligatures.",in:shaping)
        check("typography.useBold","Use bold fonts for bold text",\.typography.useBold,in:shaping)
        check("typography.useItalic","Use italic fonts for italic text",\.typography.useItalic,in:shaping)
        let features = group("OpenType features",in:page)
        note("Options come from the chosen font. Font Default leaves a feature unchanged; Off and On override it. Some features change character widths; Moth keeps its fixed grid.",in:features)
        fontFeatures.orientation = .vertical; fontFeatures.alignment = .leading; fontFeatures.spacing = 12
        features.addArrangedSubview(fontFeatures); fontFeatures.widthAnchor.constraint(equalTo:features.widthAnchor).isActive = true
        features.addArrangedSubview(button("Reset Typography") { [weak self] in self?.commit { $0.typography = Configuration.Typography() } })

    }
    private func refreshFontFeatures() {
        let config = settingsConfig
        let signature = config.fontName+String(describing:config.typography.features.sorted { $0.key < $1.key })+String(config.typography.ligatures)
        guard signature != featureSignature else { return }; featureSignature = signature
        featureActions.removeAll(); fields = fields.filter { !$0.key.hasPrefix("opentype.") }
        for view in fontFeatures.arrangedSubviews { fontFeatures.removeArrangedSubview(view); view.removeFromSuperview() }
        let font = NSFont(name:config.fontName,size:config.fontSize)!
        let supported = FontTypography.supportedTags(font)
        let tags = Set(supported).union(config.typography.features.keys).sorted()
        if tags.isEmpty { note("This font does not advertise OpenType features.",in:fontFeatures) }
        for tag in tags {
            let popup = NSPopUpButton(); popup.addItems(withTitles:["Font Default","Off","On"])
            let current = config.typography.features[tag]
            if let current,current > 1 { popup.addItem(withTitle:"Value \(current)"); popup.selectItem(at:3) }
            else { popup.selectItem(at:current.map { $0 == 0 ? 1 : 2 } ?? 0) }
            popup.setAccessibilityLabel(FontTypography.label(tag)); popup.identifier = NSUserInterfaceItemIdentifier("opentype."+tag)
            let gated = ["liga","calt","dlig","hlig"].contains(tag) && !config.typography.ligatures
            popup.isEnabled = !gated && tag != "kern"; popup.toolTip = tag == "kern" ? "Terminal characters use a fixed grid; font kerning is not applied between cells." : gated ? "Enable ligatures to customise this feature." : tag
            let handler = SettingsAction { [weak self,weak popup] _ in
                guard let self,let popup else { return }; let index = popup.indexOfSelectedItem
                self.commit { if index == 0 { $0.typography.features.removeValue(forKey:tag) } else if index < 3 { $0.typography.features[tag] = index-1 } }
            }
            featureActions.append(handler); popup.target = handler; popup.action = #selector(SettingsAction.invoke(_:)); register("opentype."+tag,popup)
            row("\(FontTypography.label(tag)) · \(tag)",popup,in:fontFeatures)
        }
    }

    private func buildColours() {
        let outer = page("Colours",grouped:false)
        var page = group("Default text",in:outer)
        colour("palette.foreground","Text colour",get:{$0.colors.1},set:{ [weak self] c,v in self?.paletteChange(&c,\.foreground,v) },in:page)
        page.addArrangedSubview(button("Use Theme Text Colour") { [weak self] in self?.commit { c in let foreground = NSColor.hex(c.selectedTheme.foreground).rgbHex; if c.palette != nil { c.palette?.foreground = foreground } } })
        page = group("ANSI palette",in:outer)
        let preset = NSPopUpButton(); preset.addItem(withTitle:"Custom")
        for palette in Configuration.ansiPresets { preset.addItem(withTitle:palette.0) }
        action(preset) { [weak self,weak preset] _ in guard let self,let preset,preset.indexOfSelectedItem > 0 else { return }; let colors = Configuration.ansiPresets[preset.indexOfSelectedItem-1].1; self.commit { $0.ansiColors = colors } }
        refreshers.append { [weak self,weak preset] in guard let self else { return }; let colors = self.settingsConfig.resolvedANSIColors; preset?.selectItem(at:Configuration.ansiPresets.firstIndex(where: { $0.1 == colors }).map { $0+1 } ?? 0) }
        row("ANSI palette",preset,in:page)
        note("Eight normal and eight bright colours, used by colourised terminal output. Applications using true colour choose their own RGB colours.",in:page)
        let grid = NSStackView(); grid.orientation = .vertical; grid.alignment = .leading; grid.spacing = 8
        register("ansiColors",grid); page.addArrangedSubview(grid); grid.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        let heading = NSStackView(); heading.spacing = 12
        for (title,width) in [("Colour",160.0),("Normal",148.0),("Bright",148.0)] { let label = NSTextField(labelWithString:title); label.font = .systemFont(ofSize:11,weight:.semibold); label.textColor = .secondaryLabelColor; label.widthAnchor.constraint(equalToConstant:width).isActive = true; heading.addArrangedSubview(label) }
        heading.addArrangedSubview(NSView()); grid.addArrangedSubview(heading); heading.widthAnchor.constraint(equalTo:grid.widthAnchor).isActive = true
        for (index,title) in ["Black","Red","Green","Yellow","Blue","Magenta","Cyan","White"].enumerated() {
            let name = NSTextField(labelWithString:title); name.widthAnchor.constraint(equalToConstant:160).isActive = true
            let line = NSStackView(views:[name]); line.spacing = 12; line.alignment = .centerY
            for slot in [index,index+8] {
                let well = NSColorWell(); if #available(macOS 14.0,*) { well.supportsAlpha = false }
                well.widthAnchor.constraint(equalToConstant:46).isActive = true; well.setAccessibilityLabel("\(slot < 8 ? "Normal" : "Bright") \(title.lowercased())")
                register("ansiColors.\(slot)",well)
                let hex = NSTextField(labelWithString:""); hex.font = .monospacedSystemFont(ofSize:11,weight:.regular); hex.widthAnchor.constraint(equalToConstant:90).isActive = true; hex.isSelectable = true
                line.addArrangedSubview(well); line.addArrangedSubview(hex)
                action(well) { [weak self,weak well] _ in guard let self,let well else { return }; self.commit { c in var colors = c.resolvedANSIColors; colors[slot] = well.color.rgbHex; c.ansiColors = colors } }
                refreshers.append { [weak self,weak well,weak hex] in guard let self else { return }; let value = self.settingsConfig.resolvedANSIColors[slot]; well?.color = .hex(value); hex?.stringValue = "#"+value }
            }
            line.addArrangedSubview(NSView())
            grid.addArrangedSubview(line); line.widthAnchor.constraint(equalTo:grid.widthAnchor).isActive = true
        }
        page.addArrangedSubview(button("Reset ANSI Colours") { [weak self] in self?.commit { $0.ansiColors = [] } })
    }
    private func chooseFont() {
        let manager = NSFontManager.shared; manager.target = self; manager.action = #selector(changeFont(_:))
        let c = settingsConfig
        manager.setSelectedFont(NSFont(name:c.fontName,size:c.fontSize) ?? .monospacedSystemFont(ofSize:c.fontSize,weight:.regular),isMultiple:false)
        manager.orderFrontFontPanel(nil)
    }
    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let old = NSFont(name:settingsConfig.fontName,size:settingsConfig.fontSize) ?? .monospacedSystemFont(ofSize:settingsConfig.fontSize,weight:.regular)
        let font = manager.convert(old)
        commit { $0.fontName = font.fontName; $0.fontSize = font.pointSize }
    }
    private func buildCursor() {
        let page = page("Cursor")
        choice("cursor.shape","Shape",\.cursor.shape,[("Block","block"),("Underline","underline"),("Bar","bar")],in:page)
        choice("cursor.animation","Animation",\.cursor.animation,[("Breathe","breathe"),("Blink","blink"),("Steady","noblink")],in:page)
        number("cursor.period","Cycle (seconds)",range:0.2...5,get:{$0.cursor.period},set:{$0.cursor.period = $1},in:page)
        _ = paint("cursor.paint","Cursor colour",\.cursor.paint,fallback:{$0.colors.2},in:page)
        note("Reset colours uses the theme accent. Cursor animation respects Reduce Motion.",in:page)
    }
    private func buildWindow() {
        let outer = page("Window",grouped:false)
        var page = group("Glass",in:outer)
        slider("window.opacity","Background opacity",\.window.opacity,range:0...1,in:page)
        check("window.frosted","Frosted glass",\.window.frosted,in:page)
        slider("window.frostIntensity","Frosting intensity",\.window.frostIntensity,range:0...1,in:page)
        let frostRow = page.arrangedSubviews.last
        let frostNote = NSTextField(wrappingLabelWithString:"Lower background opacity to reveal the frosting. Intensity blends clear glass with the full native blur effect.")
        frostNote.font = .systemFont(ofSize:11); frostNote.textColor = .secondaryLabelColor; page.addArrangedSubview(frostNote); frostNote.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        refreshers.append { [weak self,weak frostRow,weak frostNote] in let enabled = self?.settingsConfig.window.frosted == true; frostRow?.isHidden = !enabled; frostNote?.isHidden = !enabled }
        note("Opacity and frosting affect the background. Text stays opaque. Reduce Transparency makes the background opaque.",in:page)
        page = group("Border",in:outer)
        let borderEnabled = NSButton(checkboxWithTitle:"Show Window Border",target:nil,action:nil); register("window.showBorder",borderEnabled)
        action(borderEnabled) { [weak self,weak borderEnabled] _ in guard let self,let borderEnabled else { return }; self.commit { c in c.window.showBorder = borderEnabled.state == .on; if c.window.showBorder && c.window.borderWidth == 0 { c.window.borderWidth = 1 } } }
        refreshers.append { [weak self,weak borderEnabled] in borderEnabled?.state = self?.settingsConfig.window.showBorder == true ? .on : .off }
        page.addArrangedSubview(borderEnabled)
        note("Hiding the border keeps its saved colours, gradient and width.",in:page)
        colour("window.borderColor","Base border colour",get:{NSColor.hex($0.window.borderColor)},set:{$0.window.borderColor = $1},in:page)
        _ = paint("window.borderPaint","Border",\.window.borderPaint,fallback:{NSColor.hex($0.window.borderColor)},in:page)
        number("window.borderWidth","Border width (pt)",range:0...6,get:{$0.window.borderWidth},set:{$0.window.borderWidth = $1},in:page)
        page = group("Window controls",in:outer)
        choice("window.chromePosition","Tabs and session info",\.window.chromePosition,[("Bottom","bottom"),("Title Bar","titlebar")],in:page)
        check("window.showStatusBar","Show status bar",\.window.showStatusBar,in:page)
        check("window.showTabBar","Show tab bar when multiple tabs are open",\.window.showTabBar,in:page)
    }
    private func buildShell() {
        let outer = page("Shell",grouped:false)
        var page = group("New sessions",in:outer)
        _ = text("shell","Shell executable",get:{$0.shell},set:{$0.shell = $1},in:page)
        page.addArrangedSubview(button("Choose Shell…") { [weak self] in self?.chooseFile(audio:false) { url in self?.commit { $0.shell = url.path } } })
        note("The shell is used for new sessions. Existing sessions keep running.",in:page)
        register("textEncoding",encodingSelector); encodingSelector.setAccessibilityLabel("Session text encoding")
        action(encodingSelector) { [weak self] _ in guard let self,let id = self.encodingSelector.selectedItem?.representedObject as? String else { return }; self.commit { $0.textEncoding = id } }
        refreshers.append { [weak self] in
            guard let self else { return }; let config = self.settingsConfig
            self.encodingSelector.removeAllItems()
            for encoding in TerminalTextEncoding.available(config) { self.encodingSelector.addItem(withTitle:encoding.title+(config.enabledEncodings.contains(encoding.id) ? "" : " (current)")); self.encodingSelector.lastItem?.representedObject = encoding.id }
            self.encodingSelector.selectItem(at:self.encodingSelector.itemArray.firstIndex { ($0.representedObject as? String) == config.textEncoding } ?? 0)
        }
        row("Text encoding",encodingSelector,in:page)
        note("UTF-8 is recommended. Legacy encodings convert both terminal output and keyboard/pasted text. The choice also appears in Window → Text Encoding; Advanced controls which encodings are offered.",in:page)
        page = group("History and navigation",in:outer)
        number("scrollback","Scrollback lines",range:0...100000,get:{Double($0.scrollback)},set:{$0.scrollback = Int($1.rounded())},in:page)
        check("alternateScreenScrollback","Keep local history from full-screen sessions such as mosh",\.alternateScreenScrollback,in:page)
        check("showLayoutsOnLaunch","Offer saved window layouts at launch (app-wide)",\.showLayoutsOnLaunch,in:page)
        check("optionAsMeta","Use Option as Meta",\.optionAsMeta,in:page)
        note("Leave off to type keyboard-layout characters such as # with Option+3 on a British keyboard. Enabling Meta sends terminal escape sequences instead.",in:page)
    }
    private func chooseFile(audio: Bool, completion: @escaping (URL)->Void) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if audio { panel.allowedContentTypes = [.audio] }
        guard let window else { return }
        panel.beginSheetModal(for:window) { result in if result == .OK,let url = panel.url { completion(url) } }
    }
    private func buildBell() {
        let page = page("Bell")
        choice("bell.mode","Notification",\.bell.mode,[("Off","off"),("Visual","visual"),("Sound","sound"),("Visual and sound","both")],in:page)
        choice("bell.style","Visual effect",\.bell.style,[("Pane border","border"),("Soft flash","flash"),("Window border","window-border")],in:page)
        _ = text("bell.sound","Sound name or file",get:{$0.bell.sound},set:{$0.bell.sound = $1},in:page)
        page.addArrangedSubview(button("Choose Sound File…") { [weak self] in self?.chooseFile(audio:true) { url in self?.commit { $0.bell.sound = url.path } } })
        note("Use a system sound name such as Glass or Ping, or choose an audio file.",in:page)
        slider("bell.volume","Volume",\.bell.volume,range:0...1,in:page)
        slider("bell.intensity","Visual strength",\.bell.intensity,range:0...1,in:page)
        number("bell.duration","Duration (seconds)",range:0.08...1,get:{$0.bell.duration},set:{$0.bell.duration = $1},in:page)
        number("bell.thickness","Border thickness (pt)",range:1...12,get:{$0.bell.thickness},set:{$0.bell.thickness = $1},in:page)
        colour("bell.color","Visual colour",get:{$0.bell.color.isEmpty ? $0.colors.2 : NSColor.hex($0.bell.color)},set:{$0.bell.color = $1},in:page)
        page.addArrangedSubview(button("Use Theme Accent") { [weak self] in self?.commit { $0.bell.color = "" } })
        check("bell.badge","Count bells on the Dock icon",\.bell.badge,in:page)
        page.addArrangedSubview(button("Preview Bell") { [weak self] in self?.application.previewBell(nil) })
    }
    private func buildKeyboardSounds() {
        let page = page("Keyboard Sounds",grouped:false)
        let master = NSStackView(); master.alignment = .centerY; master.spacing = 12
        let enabled = NSButton(checkboxWithTitle:"Play sounds while typing",target:nil,action:nil); register("keyboardSound.enabled",enabled)
        action(enabled) { [weak self,weak enabled] _ in guard let self,let enabled else { return }; self.commit { $0.keyboardSound.enabled = enabled.state == .on } }
        refreshers.append { [weak self,weak enabled] in enabled?.state = self?.settingsConfig.keyboardSound.enabled == true ? .on : .off }
        let preview = button("Try Sequence") { [weak self] in
            guard let self else { return }; KeyboardSoundPlayer.shared.audition(self.settingsConfig.keyboardSound)
            if let error = KeyboardSoundPlayer.shared.lastError { self.showError("Audio could not start: \(error)") }
        }
        refreshers.append { [weak self,weak preview] in preview?.title = self?.settingsConfig.keyboardSound.musical == true ? "Try Sequence" : "Try Sound" }
        preview.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil); preview.imagePosition = .imageLeading
        master.addArrangedSubview(enabled); master.addArrangedSubview(NSView()); master.addArrangedSubview(preview)
        page.addArrangedSubview(master); master.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        let sound = group("Sound",in:page)
        let grid = NSStackView(); grid.orientation = .vertical; grid.spacing = 8; grid.alignment = .leading
        register("keyboardSound.style",grid); sound.addArrangedSubview(grid); grid.widthAnchor.constraint(equalTo:sound.widthAnchor).isActive = true
        for start in stride(from:0,to:Configuration.keyboardSoundOptions.count,by:4) {
            let line = NSStackView(); line.distribution = .fillEqually; line.spacing = 8
            grid.addArrangedSubview(line); line.widthAnchor.constraint(equalTo:grid.widthAnchor).isActive = true
            for option in Configuration.keyboardSoundOptions[start..<min(start+4,Configuration.keyboardSoundOptions.count)] {
                let tile = SoundChoiceButton(title:option.title,target:nil,action:nil)
                tile.identifier = NSUserInterfaceItemIdentifier(option.id); tile.symbol = option.symbol; tile.setButtonType(.toggle); tile.isBordered = false; tile.setAccessibilityLabel(option.title)
                tile.heightAnchor.constraint(equalToConstant:54).isActive = true
                action(tile) { [weak self] _ in self?.commit { $0.keyboardSound.style = option.id } }
                soundButtons.append(tile); line.addArrangedSubview(tile)
            }
        }
        refreshers.append { [weak self] in guard let self else { return }; for tile in self.soundButtons { tile.state = tile.identifier?.rawValue == self.settingsConfig.keyboardSound.style ? .on : .off; tile.needsDisplay = true } }
        let customRow = NSStackView(); customRow.alignment = .centerY; customRow.spacing = 12
        let custom = NSButton(checkboxWithTitle:"Custom audio files",target:nil,action:nil)
        action(custom) { [weak self,weak custom] _ in
            guard let self,let custom else { return }
            if custom.state == .on && self.settingsConfig.keyboardSound.files.isEmpty { self.chooseKeyboardSoundFiles(); custom.state = .off }
            else { self.commit { $0.keyboardSound.style = custom.state == .on ? "custom" : "drip" } }
        }
        customRow.addArrangedSubview(custom); customRow.addArrangedSubview(NSView()); customRow.addArrangedSubview(button("Choose Files…") { [weak self] in self?.chooseKeyboardSoundFiles() })
        sound.addArrangedSubview(customRow); customRow.widthAnchor.constraint(equalTo:sound.widthAnchor).isActive = true
        let files = NSTextField(wrappingLabelWithString:""); files.font = .systemFont(ofSize:11); files.textColor = .secondaryLabelColor; files.isSelectable = true
        let clear = button("Remove Files") { [weak self] in self?.commit { $0.keyboardSound.files = []; if $0.keyboardSound.style == "custom" { $0.keyboardSound.style = "drip" } } }
        clear.bezelStyle = .inline; clear.font = .systemFont(ofSize:11)
        let filesRow = NSStackView(views:[files,NSView(),clear]); filesRow.alignment = .centerY; filesRow.spacing = 12
        register("keyboardSound.files",filesRow); sound.addArrangedSubview(filesRow); filesRow.widthAnchor.constraint(equalTo:sound.widthAnchor).isActive = true
        refreshers.append { [weak self,weak custom,weak files,weak filesRow] in
            guard let self else { return }; let config = self.settingsConfig.keyboardSound
            custom?.state = config.style == "custom" ? .on : .off
            filesRow?.isHidden = config.files.isEmpty
            let names = config.files.map { URL(fileURLWithPath:$0).lastPathComponent }
            files?.stringValue = names.prefix(3).joined(separator:", ")+(names.count > 3 ? " + \(names.count-3) more" : "")
            files?.toolTip = config.files.joined(separator:"\n")
        }
        slider("keyboardSound.volume","Volume",\.keyboardSound.volume,range:0...1,in:sound)
        slider("keyboardSound.reverb","Reverb",\.keyboardSound.reverb,range:0...1,in:sound)
        let music = group("Musical behaviour",in:page)
        check("keyboardSound.musical","Enable musical behaviour",\.keyboardSound.musical,in:music)
        let musicOptions = NSStackView(); musicOptions.orientation = .vertical; musicOptions.alignment = .leading; musicOptions.spacing = 12
        music.addArrangedSubview(musicOptions); musicOptions.widthAnchor.constraint(equalTo:music.widthAnchor).isActive = true
        refreshers.append { [weak self,weak musicOptions] in musicOptions?.isHidden = self?.settingsConfig.keyboardSound.musical != true }
        choice("keyboardSound.key","Key",\.keyboardSound.key,Configuration.musicalKeys.map { ($0.replacingOccurrences(of:"#",with:"♯"),$0) },in:musicOptions)
        choice("keyboardSound.mode","Mode",\.keyboardSound.mode,Configuration.musicalModes.map { ($0.0.capitalized,$0.0) },in:musicOptions)
        let pattern = NSSegmentedControl(labels:["Ascending","Descending","Random","Arpeggiating"],trackingMode:.selectOne,target:nil,action:nil)
        pattern.segmentDistribution = .fillEqually; pattern.font = .systemFont(ofSize:12); register("keyboardSound.pattern",pattern); pattern.setAccessibilityLabel("Note pattern")
        action(pattern) { [weak self,weak pattern] _ in guard let self,let pattern,pattern.selectedSegment >= 0 else { return }; self.commit { $0.keyboardSound.pattern = Configuration.musicalPatterns[pattern.selectedSegment] } }
        refreshers.append { [weak self,weak pattern] in guard let self else { return }; pattern?.selectedSegment = Configuration.musicalPatterns.firstIndex(of:self.settingsConfig.keyboardSound.pattern) ?? 2 }
        musicOptions.addArrangedSubview(pattern); pattern.widthAnchor.constraint(equalTo:musicOptions.widthAnchor).isActive = true
        note("Each key press advances a note. Arpeggiating follows the 1st, 3rd, 5th and 7th notes, then returns. Custom files are treated as C4; pitching changes their playback speed.",in:musicOptions)
        let shortcut = NSTextField(wrappingLabelWithString:""); shortcut.font = .systemFont(ofSize:11); shortcut.textColor = .secondaryLabelColor; page.addArrangedSubview(shortcut); shortcut.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
        refreshers.append { [weak self,weak shortcut] in guard let self else { return }; let binding = self.settingsConfig.keybindings["toggleKeyboardSounds"] ?? ""; shortcut?.stringValue = binding.isEmpty ? "Set a toggle shortcut in Shortcuts. Shortcuts and pasted text stay silent." : "Toggle: \(Self.shortcutTitle(binding)). Change it in Shortcuts. Shortcuts and pasted text stay silent." }
    }
    private func chooseKeyboardSoundFiles() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.message = "Choose up to 16 short audio clips. Multiple files rotate as you type."
        guard let window else { return }
        panel.beginSheetModal(for:window) { [weak self] result in
            guard result == .OK,let self else { return }
            self.commit { $0.keyboardSound.files = panel.urls.map(\.path); $0.keyboardSound.style = "custom" }
        }
    }
    private static func shortcutTitle(_ binding: String) -> String {
        guard let (key,flags) = Configuration.shortcut(binding) else { return binding }
        return (flags.contains(.control) ? "⌃" : "")+(flags.contains(.option) ? "⌥" : "")+(flags.contains(.shift) ? "⇧" : "")+(flags.contains(.command) ? "⌘" : "")+(key == "\r" ? "↩":key.uppercased())
    }
    private func buildProfiles() {
        let page = page("Profiles",grouped:false)
        let manage = group("Named profiles",in:page)
        profileSummary.font = .systemFont(ofSize:12); profileSummary.textColor = .secondaryLabelColor
        manage.addArrangedSubview(profileSummary); profileSummary.widthAnchor.constraint(equalTo:manage.widthAnchor).isActive = true
        let create = button("New Profile…") { [weak self] in self?.editProfileName(rename:false) }
        let rename = button("Rename…") { [weak self] in self?.editProfileName(rename:true) }
        let remove = button("Delete…") { [weak self] in self?.deleteProfile() }
        let open = button("Open Window") { [weak self] in guard let self else { return }; self.application.openWindow(profileID:self.editingProfileID) }
        let actions = NSStackView(views:[create,rename,remove,open]); actions.spacing = 8; manage.addArrangedSubview(actions)
        profileButtons = [rename,remove]
        note("New Profile copies the profile currently selected above. Each named profile has its own editable TOML file. Deleting a profile backs up its file; existing windows keep their current settings until you choose another profile for them.",in:manage)
        let launch = group("New windows",in:page)
        register("defaultProfileID",defaultProfileSelector); defaultProfileSelector.setAccessibilityLabel("Default profile for new windows")
        action(defaultProfileSelector) { [weak self] _ in
            guard let self else { return }; self.flushAudioEdits()
            var global = self.application.config; global.defaultProfileID = self.defaultProfileSelector.selectedItem?.representedObject as? String ?? ""
            do { try Configuration.save(global); self.application.config = global; self.application.applyAppearance(); self.application.buildMenu() } catch { self.showError(error.localizedDescription) }
        }
        row("Default profile",defaultProfileSelector,in:launch)
        note("Cmd+N uses this profile. Window → New Window with Profile opens a specific profile; Window → Window Profile changes an existing window. New tabs and splits inherit their window’s profile. Saved layouts retain the profile selection.",in:launch)
    }
    private func editProfileName(rename: Bool) {
        flushAudioEdits(); let current = application.profile(editingProfileID)
        guard !rename || current != nil,let window else { return }
        let alert = NSAlert(); alert.messageText = rename ? "Rename Profile" : "New Profile"
        alert.informativeText = rename ? "The profile keeps its settings and existing windows." : "Copy the current appearance and session defaults into a named profile."
        let name = NSTextField(frame:NSRect(x:0,y:0,width:320,height:24)); name.stringValue = rename ? current!.name : ""; name.placeholderString = "Profile name"; alert.accessoryView = name
        alert.addButton(withTitle:rename ? "Rename" : "Create"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn,let self else { return }
            let title = name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            guard title.caseInsensitiveCompare("Default") != .orderedSame,!self.application.profiles.contains(where: { $0.name.caseInsensitiveCompare(title) == .orderedSame && $0.id != (rename ? current?.id : nil) }) else { self.showError("Choose a unique profile name other than Default."); return }
            var profile = TerminalProfile(name:title,configuration:self.settingsConfig)
            if rename { profile.id = current!.id }
            do {
                try ProfileStore.save(profile,base:self.application.config,in:self.application.profileDirectory); self.application.reloadProfiles(); self.editingProfileID = profile.id; self.featureSignature = ""
                self.application.applyAppearance(); self.application.buildMenu()
            } catch { self.showError(error.localizedDescription) }
        }
    }
    private func deleteProfile() {
        guard let current = application.profile(editingProfileID),let window else { return }
        let alert = NSAlert(); alert.messageText = "Delete \(current.name)?"; alert.informativeText = "A backup of its profile file is kept. Existing windows retain their settings; new windows will no longer offer this profile."
        alert.addButton(withTitle:"Delete Profile"); alert.addButton(withTitle:"Cancel"); alert.window.defaultButtonCell = alert.buttons.last?.cell as? NSButtonCell
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn,let self else { return }; self.flushAudioEdits()
            do {
                try ProfileStore.remove(current.id,in:self.application.profileDirectory)
                if self.application.config.defaultProfileID == current.id { self.application.config.defaultProfileID = ""; try Configuration.save(self.application.config) }
                self.editingProfileID = nil; self.application.reloadProfiles(); self.application.applyAppearance(); self.application.buildMenu()
            } catch { self.showError(error.localizedDescription) }
        }
    }

    private func buildMacros() {
        let page = page("Macros",grouped:false)
        note("Save text snippets or record typing and terminal keys. Macros run in the active pane. Recordings include hidden input too; keep secrets out of saved macros.",in:page)
        let list = group("Saved macros",in:page); register("macros",list)
        action(macroSelector) { [weak self] _ in guard let self else { return }; self.selectedMacro = self.macroSelector.titleOfSelectedItem ?? ""; self.refreshMacroEditor() }
        row("Macro",macroSelector,in:list)
        let buttons = NSStackView(views:[button("New Snippet…") { [weak self] in self?.nameMacro(rename:false) },button("Rename…") { [weak self] in self?.nameMacro(rename:true) },button("Delete") { [weak self] in guard let self,!self.selectedMacro.isEmpty else { return }; self.commit { $0.macros.removeValue(forKey:self.selectedMacro) }; self.selectedMacro = ""; self.refreshMacroEditor() }]); buttons.spacing = 8; list.addArrangedSubview(buttons)
        macroSummary.font = .systemFont(ofSize:11); macroSummary.textColor = .secondaryLabelColor; list.addArrangedSubview(macroSummary); macroSummary.widthAnchor.constraint(equalTo:list.widthAnchor).isActive = true
        let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        macroEditor.isRichText = false; macroEditor.font = .monospacedSystemFont(ofSize:12,weight:.regular); macroEditor.isVerticallyResizable = true; macroEditor.autoresizingMask = [.width]; macroEditor.textContainer?.widthTracksTextView = true; scroll.documentView = macroEditor
        list.addArrangedSubview(scroll); scroll.heightAnchor.constraint(equalToConstant:100).isActive = true; scroll.widthAnchor.constraint(equalTo:list.widthAnchor).isActive = true
        row("Shortcut",macroShortcut,in:list); macroShortcut.placeholderString = "Optional, e.g. cmd+alt+1"
        list.addArrangedSubview(macroSubmit)
        let apply = button("Apply Macro") { [weak self] in
            guard let self,var macro = self.settingsConfig.macros[self.selectedMacro] else { return }
            macro.shortcut = self.macroShortcut.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            if macro.keys.isEmpty { macro.text = self.macroEditor.string; macro.submit = self.macroSubmit.state == .on }
            self.commit { $0.macros[self.selectedMacro] = macro }
        }
        list.addArrangedSubview(apply)
        let record = group("Record and replay",in:page)
        let actions = NSStackView(views:[button("Start / Stop Recording…") { [weak self] in self?.application.toggleMacroRecording(nil) },button("Run Selected") { [weak self] in guard let self else { return }; let item = NSMenuItem(); item.representedObject = self.selectedMacro; self.application.runMacro(item) },button("Stop Playback") { [weak self] in self?.application.stopMacro(nil) }]); actions.spacing = 8; record.addArrangedSubview(actions)
        note("Return to the terminal to record. Stop from the Macros menu, then name the recording. Playback keeps recorded delays, including Enter and control keys. Stop Playback cancels pending keys.",in:record)
        refreshers.append { [weak self] in self?.refreshMacroEditor() }
    }
    private func refreshMacroEditor() {
        let names = settingsConfig.macros.keys.sorted()
        if !names.contains(selectedMacro) { selectedMacro = names.first ?? "" }
        macroSelector.removeAllItems(); macroSelector.addItems(withTitles:names.isEmpty ? ["No saved macros"] : names); macroSelector.selectItem(at:names.firstIndex(of:selectedMacro) ?? 0); macroSelector.isEnabled = !names.isEmpty
        guard let macro = settingsConfig.macros[selectedMacro] else { macroEditor.string = ""; macroEditor.isEditable = false; macroShortcut.stringValue = ""; macroSubmit.isEnabled = false; macroSummary.stringValue = "Create a snippet or record a sequence to begin."; return }
        if macroEditor.window?.firstResponder !== macroEditor { macroEditor.string = macro.keys.isEmpty ? macro.text : macro.keys.map { $0.debugDescription }.joined(separator:"\n") }
        macroEditor.isEditable = macro.keys.isEmpty; macroShortcut.stringValue = macro.shortcut
        macroSubmit.state = macro.submit ? .on : .off; macroSubmit.isEnabled = macro.keys.isEmpty
        macroSummary.stringValue = macro.keys.isEmpty ? "Text snippet · Apply saves your edits." : "Recorded sequence · \(macro.keys.count) input events · \(String(format:"%.1f",macro.delays.reduce(0,+))) seconds. Shortcut remains editable."
    }
    private func nameMacro(rename: Bool) {
        let old = selectedMacro
        if rename && settingsConfig.macros[old] == nil { return }
        let alert = NSAlert(); alert.messageText = rename ? "Rename Macro" : "New Snippet"
        let name = NSTextField(string:rename ? old : "New Macro"); name.frame = NSRect(x:0,y:0,width:280,height:24); alert.accessoryView = name; alert.window.initialFirstResponder = name
        alert.addButton(withTitle:rename ? "Rename" : "Create"); alert.addButton(withTitle:"Cancel")
        guard let window else { return }
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn,let self else { return }
            let next = name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            guard self.settingsConfig.macros[next] == nil || next == old else { self.showError("A macro with that name already exists."); return }
            if self.commit({ c in let macro = rename ? c.macros.removeValue(forKey:old) ?? Configuration.Macro() : Configuration.Macro(); c.macros[next] = macro }) { self.selectedMacro = next; self.refreshMacroEditor() }
        }
    }
    private let updateStatus = NSTextField(wrappingLabelWithString:"")
    private var updateCheckButton: NSButton?
    func refreshUpdateStatus() {
        updateStatus.stringValue = application.updateChecker.status
        updateStatus.isHidden = updateStatus.stringValue.isEmpty
        updateCheckButton?.isEnabled = !application.updateChecker.isChecking
        updateCheckButton?.title = application.updateChecker.isChecking ? "Checking…":"Check for Updates…"
    }
    private func buildUpdates() {
        let page=page("Updates",grouped:false)
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        let build=MothBuild.identifier
        note("Moth \(version) (\(build))",in:page)
        let options=group("Software updates",in:page)
        check("updates.checkAtLaunch","Check for updates when Moth launches",\.updates.checkAtLaunch,in:options)
        note("Checks getmoth.dev for new releases. Downloads open in your browser. This setting applies to all profiles.",in:options)
        let check=button("Check for Updates…") { [weak self] in self?.application.checkForUpdates(nil) }
        register("updates.checkNow",check);updateCheckButton=check;options.addArrangedSubview(check)
        updateStatus.textColor = .secondaryLabelColor;updateStatus.font = .systemFont(ofSize:12)
        options.addArrangedSubview(updateStatus);refreshUpdateStatus()
    }
    private func buildAdvanced() {
        let page = page("Advanced",grouped:false)
        note("Encoding choices, terminal compatibility, diagnostics and clipboard permissions are app-wide. Launch defaults apply to new sessions of the selected profile.",in:page)
        let encodings = group("Text encodings",in:page)
        note("Enable the encodings offered in the Shell settings and Window menu. This list is app-wide. Disabling an entry hides it from new choices. Profiles and sessions already using it keep their encoding, shown as “current”. Keep at least one encoding enabled.",in:encodings)
        let encodingList = NSStackView(); encodingList.orientation = .vertical; encodingList.alignment = .leading; encodingList.spacing = 6; encodings.addArrangedSubview(encodingList); encodingList.widthAnchor.constraint(equalTo:encodings.widthAnchor).isActive = true
        register("enabledEncodings",encodingList)
        for offset in stride(from:0,to:TerminalTextEncoding.choices.count,by:2) {
            let line = NSStackView(); line.distribution = .fillEqually; line.spacing = 12; encodingList.addArrangedSubview(line); line.widthAnchor.constraint(equalTo:encodingList.widthAnchor).isActive = true
            for encoding in TerminalTextEncoding.choices[offset..<min(offset+2,TerminalTextEncoding.choices.count)] {
                let box = NSButton(checkboxWithTitle:encoding.title,target:nil,action:nil); box.setAccessibilityLabel(encoding.title); line.addArrangedSubview(box)
                register("encoding.enabled."+encoding.id,box)
                action(box) { [weak self,weak box] _ in
                    guard let self,let box else { return }
                    let saved = self.commit { config in if box.state == .on { if !config.enabledEncodings.contains(encoding.id) { config.enabledEncodings.append(encoding.id) } } else { config.enabledEncodings.removeAll { $0 == encoding.id } } }
                    if !saved { box.state = self.settingsConfig.enabledEncodings.contains(encoding.id) ? .on : .off }
                }
                refreshers.append { [weak self,weak box] in guard let self else { return }; box?.state = self.settingsConfig.enabledEncodings.contains(encoding.id) ? .on : .off }
            }
            if line.arrangedSubviews.count == 1 { line.addArrangedSubview(NSView()) }
        }
        let compatibility = group("Terminal compatibility",in:page)
        check("advanced.allowDoubleSizeLines","Allow VT100 double-width and double-height lines",\.advanced.allowDoubleSizeLines,in:compatibility)
        note("Allows terminal programs to enlarge individual lines. Turning this off returns existing double-size lines to normal and ignores new size requests. Applies to all profiles without restarting their shells.",in:compatibility)
        let recovery = group("Session recovery",in:page)
        check("advanced.sessionRecovery","Keep new sessions recoverable after an app crash",\.advanced.sessionRecovery,in:recovery)
        note("A local helper keeps shells and jobs running if Moth disconnects. Recovery keeps up to 64 MB of terminal output per pane in the helper’s memory. It cannot survive a Mac restart. Closing a pane or quitting normally ends its session. Use Moth → Quit and Keep Sessions to reconnect later. Changes apply to new sessions.",in:recovery)
        let launch = group("New sessions",in:page)
        _ = text("advanced.workingDirectory","Starting directory",get:{$0.advanced.workingDirectory},set:{$0.advanced.workingDirectory = $1},in:launch)
        note("New windows start here, or in your home directory when empty. New tabs and splits can use the active shell’s current directory instead.",in:launch)
        check("advanced.inheritWorkingDirectory","Open new tabs and splits in the current directory",\.advanced.inheritWorkingDirectory,in:launch)
        note("Uses the local shell’s directory, including recovered sessions. Remote SSH and mosh paths are not used as local folders. If unavailable, the starting directory above is used.",in:launch)
        check("advanced.loginShell","Start a login shell",\.advanced.loginShell,in:launch).toolTip = "Loads login startup files for new sessions. For zsh: .zprofile and .zlogin, as well as interactive .zshrc."
        let env = NSTextView(), scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; env.isRichText = false; env.font = .monospacedSystemFont(ofSize:12,weight:.regular); env.isVerticallyResizable = true; env.autoresizingMask = [.width]; env.textContainer?.widthTracksTextView = true; scroll.documentView = env
        register("advanced.environment",env); launch.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo:launch.widthAnchor).isActive = true; scroll.heightAnchor.constraint(equalToConstant:110).isActive = true
        note("Environment overrides: one NAME=value per line. They override the inherited environment, including TERM and COLORTERM when explicitly supplied.",in:launch)
        launch.addArrangedSubview(button("Apply Environment") { [weak self,weak env] in
            guard let self,let env else { return }; var values: [String:String] = [:]
            for line in env.string.components(separatedBy:.newlines) where !line.isEmpty {
                guard let equals = line.firstIndex(of:"="),equals != line.startIndex else { self.showError("Use one NAME=value entry per line."); return }
                let name = String(line[..<equals]); guard values[name] == nil else { self.showError("Duplicate environment variable: \(name)"); return }; values[name] = String(line[line.index(after:equals)...])
            }
            self.commit { $0.advanced.environment = values }
        })
        refreshers.append { [weak self,weak env] in guard let self,let env,env.window?.firstResponder !== env else { return }; env.string = self.settingsConfig.advanced.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator:"\n") }
        let logging = group("Diagnostics",in:page)
        _ = text("advanced.logDirectory","Output log folder",get:{$0.advanced.logDirectory},set:{$0.advanced.logDirectory = $1},in:logging)
        note("Empty disables logging. An existing absolute folder receives raw output logs for each pane. Logs can contain sensitive terminal output.",in:logging)
        let clipboard = group("Clipboard",in:page)
        check("advanced.copyOnSelect","Copy selected terminal text automatically",\.advanced.copyOnSelect,in:clipboard)
        check("advanced.allowRemoteClipboard","Allow terminal programs to write to the clipboard (OSC 52)",\.advanced.allowRemoteClipboard,in:clipboard)
        let reset = group("Reset",in:page)
        note("Restore the default preferences. A backup of the current configuration is saved first.",in:reset)
        let resetButton = button("Reset All Preferences…") { [weak self] in self?.resetPreferences() }; resetButton.contentTintColor = .systemRed; reset.addArrangedSubview(resetButton)
    }
    private func buildLookup() {
        let page = page("Look Up & Manuals")
        note("Text actions are app-wide and apply immediately to every terminal.",in:page)
        choice("lookup.forceClickAction","Force-click / Look Up gesture",\.lookup.forceClickAction,[("Off","off"),("Word definition","definition"),("Manual page","manual")],in:page)
        note("Press firmly on a Force Touch trackpad, or use the macOS Look Up gesture. Control+Command+D and the Look Up context-menu action always show a word definition.",in:page)
        check("lookup.commandClickManual","Command-click command names to open their manual pages",\.lookup.commandClickManual,in:page)
        choice("lookup.manualPresentation","Open manual pages in",\.lookup.manualPresentation,[("Popover","popover"),("Separate window","window")],in:page)
        note("Manuals come from this Mac, including when the terminal is connected to another machine. Select a command or a reference such as printf(3), then use Open Manual Page in the context menu or Control+Command+M (the default shortcut). Change that shortcut in Shortcuts. Search within a manual with Command+F; follow SEE ALSO links to related pages.",in:page)
    }
    private func buildShortcuts() {
        let page = page("Shortcuts")
        note("Use cmd, shift, alt and ctrl, followed by a single key or return; for example cmd+shift+d or cmd+shift+return. Untick Enabled to disable a shortcut.",in:page)
        let titles = ["openManualPage":"Open manual page","newWindow":"New window","newTab":"New tab","splitRight":"Split right","splitDown":"Split down","closePane":"Close pane","nextPane":"Next pane","toggleMaximizePane":"Maximise pane","nextTab":"Next tab","reloadConfig":"Reload configuration","resetTerminal":"Reset terminal","openLayouts":"Open window layouts","toggleKeyboardSounds":"Keyboard sounds"]
        for name in Configuration.actions {
            let title = titles[name] ?? "Select tab \(name.replacingOccurrences(of:"selectTab",with:""))"
            let field = NSTextField(); field.delegate = self; field.font = .monospacedSystemFont(ofSize:12,weight:.regular); register("keybindings."+name,field)
            let enabled = NSButton(checkboxWithTitle:"Enabled",target:nil,action:nil)
            let save: ()->Void = { [weak self,weak field] in guard let self,let field else { return }; self.commit { $0.keybindings[name] = field.stringValue.trimmingCharacters(in:.whitespaces) } }
            textActions[ObjectIdentifier(field)] = save; action(field) { _ in save() }
            action(enabled) { [weak self,weak enabled,weak field] _ in guard let self,let enabled,let field else { return }; self.commit { $0.keybindings[name] = enabled.state == .on ? (field.stringValue.isEmpty ? Configuration.defaultKeybindings[name] ?? "" : field.stringValue) : "" } }
            refreshers.append { [weak self,weak field,weak enabled] in
                guard let self,let field else { return }; let value = self.settingsConfig.keybindings[name] ?? ""
                if field.currentEditor() == nil { field.stringValue = value }; enabled?.state = value.isEmpty ? .off : .on; field.isEnabled = !value.isEmpty
            }
            let line = NSStackView(views:[field,enabled]); line.spacing = 12; row(title,line,in:page)
        }
    }
    private func buildClosing() {
        let page = page("Closing",grouped:false)
        let exit = group("Session exit",in:page)
        check("closeOnExit","Close sessions when the shell exits",\.closeOnExit,in:exit)
        note("Closes the exited pane or tab, then the window when its last session ends. Turn off to keep the output and exit status visible. Commands returning to a running shell leave the session open.",in:exit)
        let confirmation = group("Close confirmation · App-wide",in:page)
        check("closeConfirmation.enabled","Confirm before closing running programs",\.closeConfirmation.enabled,in:confirmation)
        note("These programs can close without confirmation. Other foreground or background jobs still prompt. Enter one exact program name or executable path per line.",in:confirmation)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let list = NSTextView(); list.isRichText = false; list.font = .monospacedSystemFont(ofSize:12,weight:.regular); list.autoresizingMask = [.width]; list.isVerticallyResizable = true; list.textContainer?.widthTracksTextView = true; scroll.documentView = list
        register("closeConfirmation.ignorePrograms",list)
        confirmation.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo:confirmation.widthAnchor).isActive = true; scroll.heightAnchor.constraint(equalToConstant:150).isActive = true
        refreshers.append { [weak self,weak list] in guard let self,let list,list.window?.firstResponder !== list else { return }; list.string = self.settingsConfig.closeConfirmation.ignorePrograms.joined(separator:"\n") }
        confirmation.addArrangedSubview(button("Apply Program List") { [weak self,weak list] in guard let self,let list else { return }; let programs = list.string.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }; self.commit { $0.closeConfirmation.ignorePrograms = programs } })
    }
}

private extension NSColor {
    var rgbHex: String {
        let c = usingColorSpace(.sRGB)!
        return String(format:"%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
    }
}

private final class SettingsRootView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}

/// A quiet selectable sound tile, following the current native appearance.
private final class SoundChoiceButton: NSButton {
    var symbol = "waveform"
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let rect = bounds.insetBy(dx:1,dy:1), path = NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.labelColor.withAlphaComponent(0.035)).setFill(); path.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.5)).setStroke(); path.lineWidth = selected ? 1.5 : 0.5; path.stroke()
        let color: NSColor = selected ? .controlAccentColor : .secondaryLabelColor
        let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:15,weight:.regular))
        image?.lockFocus(); color.set(); NSRect(origin:.zero,size:image!.size).fill(using:.sourceIn); image?.unlockFocus()
        image?.draw(in:NSRect(x:(bounds.width-18)/2,y:8,width:18,height:18),from:.zero,operation:.sourceOver,fraction:isHighlighted ? 0.6 : 1,respectFlipped:true,hints:nil)
        let text = title as NSString
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12,weight:selected ? .medium : .regular),.foregroundColor:NSColor.labelColor]
        let size = text.size(withAttributes:attributes)
        text.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:32),withAttributes:attributes)
    }
}
