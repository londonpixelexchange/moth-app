// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit

indirect enum SavedSplit: Codable {
    case pane
    case split(vertical: Bool, fraction: Double, first: SavedSplit, second: SavedSplit)
    var paneCount: Int { switch self { case .pane:return 1; case let .split(_,_,a,b):return a.paneCount+b.paneCount } }
    func validate(depth: Int = 0) throws {
        guard depth < Workspace.maximumPanes,paneCount <= Workspace.maximumPanes else { throw Configuration.invalid("A saved tab can contain up to nine panes.") }
        if case let .split(_,fraction,a,b) = self {
            guard fraction.isFinite,(0.05...0.95).contains(fraction) else { throw Configuration.invalid("Invalid saved divider position.") }
            try a.validate(depth:depth+1); try b.validate(depth:depth+1)
        }
    }
    var minimumSize: NSSize {
        switch self {
        case .pane:return NSSize(width:200,height:130)
        case let .split(vertical,_,a,b):let x = a.minimumSize,y = b.minimumSize; return vertical ? NSSize(width:x.width+y.width+1,height:max(x.height,y.height)) : NSSize(width:max(x.width,y.width),height:x.height+y.height+1)
        }
    }
}
struct SavedTab: Codable { var root: SavedSplit; var activePane: Int; var sessions: [String]? = nil }
struct SavedWindowLayout: Codable, Identifiable {
    var id = UUID()
    var profileID: String? = nil
    var name: String
    var tabs: [SavedTab]
    var activeTab: Int
    var width: Double
    var height: Double
    var paneCount: Int { tabs.reduce(0) { $0+$1.root.paneCount } }
    var summary: String { "\(tabs.count) \(tabs.count == 1 ? "tab" : "tabs") · \(paneCount) \(paneCount == 1 ? "pane" : "panes")" }
    func validate() throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 80,!name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains), (1...12).contains(tabs.count),tabs.indices.contains(activeTab),width.isFinite,height.isFinite,(560...10000).contains(width),(360...10000).contains(height) else { throw Configuration.invalid("Invalid saved window layout.") }
        for tab in tabs { try tab.root.validate(); guard (0..<tab.root.paneCount).contains(tab.activePane) else { throw Configuration.invalid("Invalid saved active pane.") } }
    }
    static func capture(_ controller: TerminalWindowController,name: String) throws -> SavedWindowLayout {
        let size = controller.window?.contentView?.bounds.size ?? NSSize(width:1120,height:740)
        let layout = SavedWindowLayout(profileID:controller.profileID,name:name.trimmingCharacters(in:.whitespacesAndNewlines),tabs:try controller.workspaces.map { try $0.savedTab() },activeTab:controller.index,width:Double(size.width),height:Double(size.height))
        try layout.validate(); return layout
    }
}
enum WindowLayoutStore {
    static var url: URL { Configuration.url.deletingLastPathComponent().appendingPathComponent("window-layouts.json") }
    private struct Document: Codable { var version = 1; var layouts: [SavedWindowLayout] }
    static func load(from url: URL = WindowLayoutStore.url) throws -> [SavedWindowLayout] {
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        let data = try Data(contentsOf:url); guard data.count < 1024*1024 else { throw Configuration.invalid("Saved window layouts exceed 1 MB.") }
        let document = try JSONDecoder().decode(Document.self,from:data)
        guard document.version == 1,document.layouts.count <= 100 else { throw Configuration.invalid("Unsupported saved window layout document.") }
        for layout in document.layouts { try layout.validate() }
        var layouts = document.layouts
        for i in layouts.indices { for j in layouts[i].tabs.indices { layouts[i].tabs[j].sessions = nil } }
        return layouts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func write(_ layouts: [SavedWindowLayout],to url: URL) throws {
        for layout in layouts { try layout.validate() }
        guard layouts.count <= 100 else { throw Configuration.invalid("You can save up to 100 window layouts.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(Document(layouts:layouts))
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:url.path) { let old = try Data(contentsOf:url); try old.write(to:url.appendingPathExtension("previous"),options:.atomic) }
        try data.write(to:url,options:.atomic)
    }
    static func save(_ layout: SavedWindowLayout,to url: URL = WindowLayoutStore.url) throws {
        var layouts = try load(from:url)
        if let index = layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(layout.name) == .orderedSame }) { var replacement = layout; replacement.id = layouts[index].id; layouts[index] = replacement } else { layouts.append(layout) }
        try write(layouts,to:url)
    }
    static func remove(_ id: UUID,from url: URL = WindowLayoutStore.url) throws { try write(load(from:url).filter { $0.id != id },to:url) }
    static func rename(_ id: UUID,to name: String,at url: URL = WindowLayoutStore.url) throws {
        var layouts = try load(from:url)
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        guard !layouts.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw Configuration.invalid("A layout with that name already exists.") }
        layouts[index].name = name.trimmingCharacters(in:.whitespacesAndNewlines); try write(layouts,to:url)
    }
}

private final class LayoutCell: NSTableCellView {
    let name = NSTextField(labelWithString:"")
    let detail = NSTextField(labelWithString:"")
    override init(frame: NSRect) {
        super.init(frame:frame); name.font = .systemFont(ofSize:13,weight:.medium); detail.font = .systemFont(ofSize:11); detail.textColor = .secondaryLabelColor
        for view in [name,detail] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([name.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),name.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-10),name.topAnchor.constraint(equalTo:topAnchor,constant:6),detail.leadingAnchor.constraint(equalTo:name.leadingAnchor),detail.trailingAnchor.constraint(equalTo:name.trailingAnchor),detail.topAnchor.constraint(equalTo:name.bottomAnchor,constant:3)])
    }
    required init?(coder: NSCoder) { fatalError() }
}
final class WindowLayoutChooser: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let application: App
    private let storeURL: URL
    let search = NSSearchField()
    let table = NSTableView()
    let status = NSTextField(labelWithString:"")
    private var all: [SavedWindowLayout] = []
    private var shown: [SavedWindowLayout] = []
    private let openButton = NSButton(title:"Open Layout",target:nil,action:nil)
    private let renameButton = NSButton(title:"Rename…",target:nil,action:nil)
    private let deleteButton = NSButton(title:"Delete",target:nil,action:nil)
    private let saveButton = NSButton(title:"Save Current Window…",target:nil,action:nil)
    init(application: App, storeURL: URL = WindowLayoutStore.url) {
        self.application = application; self.storeURL = storeURL
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:390),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        super.init(window:window); window.title = "Window Layouts"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width:480,height:320); window.center()
        let root = NSView(); window.contentView = root
        search.placeholderString = "Find a saved layout"; search.delegate = self; search.target = self; search.action = #selector(openSelected(_:)); search.sendsWholeSearchString = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("layout")); table.addTableColumn(column); table.headerView = nil; table.rowHeight = 48; table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(openSelected(_:)); table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; scroll.documentView = table
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor; status.toolTip = storeURL.path
        for (button,selector) in [(openButton,#selector(openSelected(_:))),(renameButton,#selector(renameSelected(_:))),(deleteButton,#selector(deleteSelected(_:))),(saveButton,#selector(saveCurrent(_:)))] { button.target = self; button.action = selector }
        openButton.keyEquivalent = "\r"
        let blank = NSButton(title:"New Window",target:self,action:#selector(newBlank(_:)))
        let top = NSStackView(views:[saveButton,renameButton,deleteButton]); top.spacing = 8
        let bottom = NSStackView(views:[status,blank,openButton]); bottom.spacing = 8
        for view in [search,scroll,top,bottom] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([search.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:18),search.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-18),search.topAnchor.constraint(equalTo:root.topAnchor,constant:18),top.topAnchor.constraint(equalTo:search.bottomAnchor,constant:12),top.leadingAnchor.constraint(equalTo:search.leadingAnchor),scroll.topAnchor.constraint(equalTo:top.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:search.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:search.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:bottom.topAnchor,constant:-12),bottom.leadingAnchor.constraint(equalTo:search.leadingAnchor),bottom.trailingAnchor.constraint(equalTo:search.trailingAnchor),bottom.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16)])
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    func reload() {
        var failure: String?
        do { all = try WindowLayoutStore.load(from:storeURL); status.stringValue = "Opens fresh shell sessions" } catch { all = []; failure = error.localizedDescription }
        filter(); if let failure { status.stringValue = failure }; saveButton.isEnabled = application.active != nil
    }
    private func filter() {
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        shown = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        table.reloadData(); if !shown.isEmpty { table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
        updateButtons(); if all.isEmpty { status.stringValue = "Save a window layout to get started" }
    }
    func controlTextDidChange(_ obj: Notification) { filter() }
    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("layout-cell")
        let cell = tableView.makeView(withIdentifier:id,owner:self) as? LayoutCell ?? LayoutCell(frame:.zero); cell.identifier = id
        cell.name.stringValue = shown[row].name; cell.detail.stringValue = shown[row].summary; return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    private func updateButtons() { let selected = shown.indices.contains(table.selectedRow); openButton.isEnabled = selected; renameButton.isEnabled = selected; deleteButton.isEnabled = selected }
    @objc func openSelected(_ sender: Any?) {
        guard shown.indices.contains(table.selectedRow) else { return }
        application.openSavedLayout(shown[table.selectedRow]); window?.orderOut(nil)
    }
    @objc func newBlank(_ sender: Any?) { application.newWindow(nil); window?.orderOut(nil) }
    @objc func saveCurrent(_ sender: Any?) { application.saveWindowLayout(sender) }
    @objc func renameSelected(_ sender: Any?) {
        guard shown.indices.contains(table.selectedRow),let window else { return }
        let layout = shown[table.selectedRow],alert = NSAlert(); alert.messageText = "Rename Layout"; alert.addButton(withTitle:"Rename"); alert.addButton(withTitle:"Cancel")
        let field = NSTextField(frame:NSRect(x:0,y:0,width:300,height:24)); field.stringValue = layout.name; alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.beginSheetModal(for:window) { [weak self] result in guard result == .alertFirstButtonReturn,let self else { return }; do { try WindowLayoutStore.rename(layout.id,to:field.stringValue,at:self.storeURL); self.reload() } catch { self.application.showError(error) } }
    }
    @objc func deleteSelected(_ sender: Any?) {
        guard shown.indices.contains(table.selectedRow) else { return }
        do { try WindowLayoutStore.remove(shown[table.selectedRow].id,from:storeURL); reload() } catch { application.showError(error) }
    }
}
extension App {
    @objc func showSavedLayouts(_ sender: Any?) {
        if layoutChooser == nil { layoutChooser = WindowLayoutChooser(application:self) }
        layoutChooser?.reload(); layoutChooser?.showWindow(nil); layoutChooser?.window?.makeKeyAndOrderFront(nil)
        if let chooser = layoutChooser { chooser.window?.makeFirstResponder(chooser.search) }; NSApp.activate(ignoringOtherApps:true)
    }
    @objc func saveWindowLayout(_ sender: Any?) {
        guard let controller = active,let parent = NSApp.keyWindow ?? controller.window else { return }
        let alert = NSAlert(); alert.messageText = "Save Window Layout"; alert.informativeText = "Saves tabs, splits and divider positions. Reopens with fresh shell sessions."; alert.addButton(withTitle:"Save"); alert.addButton(withTitle:"Cancel")
        let field = NSTextField(frame:NSRect(x:0,y:0,width:300,height:24)); field.placeholderString = "Layout name"; alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.beginSheetModal(for:parent) { [weak self,weak controller] result in
            guard result == .alertFirstButtonReturn,let self,let controller else { return }
            do { try WindowLayoutStore.save(SavedWindowLayout.capture(controller,name:field.stringValue)); self.layoutChooser?.reload() } catch { self.showError(error) }
        }
    }
    func openSavedLayout(_ layout: SavedWindowLayout) {
        do { try layout.validate() } catch { showError(error); return }
        let controller = TerminalWindowController(application:self,savedLayout:layout)
        windows.append(controller); controller.presentAndFocus()
    }
}
