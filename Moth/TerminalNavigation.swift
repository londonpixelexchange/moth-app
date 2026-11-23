// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import SwiftTerm

final class FindBar: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    let count = NSTextField(labelWithString: "")
    let matchCase = NSButton(checkboxWithTitle: "Match Case", target: nil, action: nil)
    let regex = NSButton(checkboxWithTitle:"Regex",target:nil,action:nil)
    var changed: (() -> Void)?
    var step: ((Int) -> Void)?
    var dismissed: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        field.placeholderString = "Find in this pane"; field.delegate = self
        field.sendsSearchStringImmediately = true; field.sendsWholeSearchString = false
        field.setAccessibilityLabel("Find in terminal scrollback")
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); count.textColor = .secondaryLabelColor
        count.setContentHuggingPriority(.required, for: .horizontal)
        regex.target = self; regex.action = #selector(optionsChanged); regex.toolTip = "Regular expressions. Zero-length matches are not highlighted."
        matchCase.target = self; matchCase.action = #selector(optionsChanged)
        let previous = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")!, target: self, action: #selector(previousMatch))
        let next = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")!, target: self, action: #selector(nextMatch))
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close find")!, target: self, action: #selector(closeFind))
        for button in [previous, next, close] { button.bezelStyle = .inline }
        let stack = NSStackView(views: [field, count, matchCase, regex, previous, next, close])
        stack.spacing = 10; stack.alignment = .centerY; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), stack.centerYAnchor.constraint(equalTo: centerYAnchor), field.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func optionsChanged() { changed?() }
    @objc private func previousMatch() { step?(-1) }
    @objc private func nextMatch() { step?(1) }
    @objc private func closeFind() { dismissed?() }
    func controlTextDidChange(_ notification: Notification) { changed?() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { dismissed?(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { step?(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? -1 : 1); return true }
        return false
    }
}

extension NSPasteboard.PasteboardType { static let mothTab = NSPasteboard.PasteboardType("com.thom.moth.tab") }

final class TerminalTabButton: NSButton, NSDraggingSource {
    var workspaceID = UUID()
    weak var sourceController: TerminalWindowController?
    private var escapeMonitor: Any?
    private var cancelled = false
    private var mouseStart: NSPoint?
    private var dragging = false
    override func mouseDown(with event: NSEvent) {
        mouseStart = convert(event.locationInWindow, from: nil)
        dragging = false; highlight(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x-start.x, point.y-start.y) >= 5 else { return }
        dragging = true; highlight(false); cancelled = false
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelled = true }; return event
        }
        let item = NSPasteboardItem(); item.setString(workspaceID.uuidString, forType: .mothTab)
        let preview = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        image.lockFocus(); draw(bounds); image.unlockFocus()
        preview.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [preview], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = false
    }
    override func mouseUp(with event: NSEvent) {
        highlight(false)
        if !dragging, mouseStart != nil, bounds.contains(convert(event.locationInWindow, from: nil)) { performClick(nil) }
        mouseStart = nil
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false; mouseStart = nil; highlight(false)
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        finishDrag(at:screenPoint,operation:operation,wasCancelled:cancelled || (NSApp.currentEvent?.type == .keyDown && NSApp.currentEvent?.keyCode == 53))
    }
    func finishDrag(at screenPoint: NSPoint,operation: NSDragOperation,wasCancelled: Bool) {
        guard operation.isEmpty,!wasCancelled,let source = sourceController,
              source.application.owner(ofTab:workspaceID) === source,
              !source.application.windows.contains(where: { $0.window?.isVisible == true && $0.window!.frame.contains(screenPoint) }) else { return }
        _ = source.detachTab(workspaceID,at:screenPoint)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title,action) in [("Move Tab to New Window",#selector(tearOffTab)),("Close Tab",#selector(closeThisTab))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func tearOffTab() { _ = sourceController?.detachTab(workspaceID,at:NSEvent.mouseLocation) }
    @objc private func closeThisTab() { sourceController?.closeTab(workspaceID) }
    deinit { if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) } }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
}

final class TabStrip: NSStackView {
    weak var controller: TerminalWindowController?
    private let marker = CALayer()
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        registerForDraggedTypes([.mothTab]); marker.backgroundColor = NSColor.controlAccentColor.cgColor
        marker.cornerRadius = 1; marker.isHidden = true; layer?.addSublayer(marker)
    }
    required init?(coder: NSCoder) { fatalError() }
    func tabID(from pasteboard: NSPasteboard) -> UUID? {
        controller?.droppedTabID(pasteboard)
    }
    private func insertionIndex(_ info: NSDraggingInfo) -> Int {
        let x = convert(info.draggingLocation, from: nil).x
        return arrangedSubviews.firstIndex(where: { x < $0.frame.midX }) ?? arrangedSubviews.count
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard tabID(from: sender.draggingPasteboard) != nil else { marker.isHidden = true; return [] }
        (enclosingScrollView?.superview as? TerminalTabBar)?.autoscrollDrag(at:sender.draggingLocation)
        let index = insertionIndex(sender)
        let x = index < arrangedSubviews.count ? arrangedSubviews[index].frame.minX-2 : (arrangedSubviews.last?.frame.maxX ?? 0)+2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        marker.frame = CGRect(x: x, y: 3, width: 2, height: max(4, bounds.height-6)); marker.isHidden = false; CATransaction.commit()
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { marker.isHidden = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        marker.isHidden = true
        guard let id = tabID(from: sender.draggingPasteboard) else { return false }
        return controller?.receiveTab(id,at:insertionIndex(sender)) ?? false
    }
}

/// Horizontal tab scrolling belongs to the chrome, never to the terminal's mouse modes.
final class TabScrollView: NSScrollView {
    var didScroll: (() -> Void)?
    func moveTabs(by distance: CGFloat) {
        let limit = max(0,(documentView?.frame.width ?? 0)-contentView.bounds.width)
        let x = min(limit,max(0,contentView.bounds.minX+distance))
        contentView.scroll(to:NSPoint(x:x,y:0)); reflectScrolledClipView(contentView); didScroll?()
    }
    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        moveTabs(by:-delta*(event.hasPreciseScrollingDeltas ? 1 : 12))
    }
}

/// Keeps the selected tab visible and provides a native menu without reducing label widths.
final class TerminalTabBar: NSView {
    let strip = TabStrip()
    let scrollView = TabScrollView()
    let previousButton = NSButton()
    let nextButton = NSButton()
    let overflowButton = NSButton()
    private var displayedIDs: [UUID] = []
    private var selectedID: UUID?
    private var revealSelection = true
    private var previousWidth: CGFloat = -1
    private(set) var isOverflowing = false
    private var boundsObserver: NSObjectProtocol?
    var buttons: [TerminalTabButton] { strip.arrangedSubviews.compactMap { $0 as? TerminalTabButton } }
    override init(frame: NSRect) {
        super.init(frame:frame)
        registerForDraggedTypes([.mothTab])
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false; scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none; scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        strip.orientation = .horizontal; strip.spacing = 4; strip.alignment = .centerY
        strip.distribution = .fillProportionally
        strip.translatesAutoresizingMaskIntoConstraints = true; strip.autoresizingMask = []
        scrollView.documentView = strip; addSubview(scrollView)
        for (button,symbol,label,action) in [(previousButton,"chevron.left","Show earlier tabs",#selector(previousTabs)),(nextButton,"chevron.right","Show later tabs",#selector(nextTabs)),(overflowButton,"chevron.down","Show all tabs",#selector(showAllTabs))] {
            button.image = NSImage(systemSymbolName:symbol,accessibilityDescription:label)
            button.isBordered = false; button.bezelStyle = .inline; button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .secondaryLabelColor; button.target = self; button.action = action
            button.toolTip = label; button.setAccessibilityLabel(label); addSubview(button)
        }
        scrollView.didScroll = { [weak self] in self?.updateNavigation() }
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scrollView.contentView,queue:.main) { [weak self] _ in self?.updateNavigation() }
        setAccessibilityLabel("Terminal tabs")
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { strip.controller?.tabDropOperation(sender.draggingPasteboard) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { strip.controller?.acceptTabDrop(sender.draggingPasteboard) ?? false }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }
    static func preferredWidth(for button: NSButton) -> CGFloat { min(170,max(92,ceil(button.intrinsicContentSize.width)+10)) }
    func prepareForReload() {
        guard let selectedID,let button = buttons.first(where: { $0.workspaceID == selectedID }) else { return }
        let visible = scrollView.contentView.bounds
        if button.frame.minX >= visible.minX-0.5 && button.frame.maxX <= visible.maxX+0.5 { revealSelection = true }
    }
    func tabsChanged(selected id: UUID) {
        let ids = buttons.map(\.workspaceID)
        revealSelection = revealSelection || ids != displayedIDs || selectedID != id
        displayedIDs = ids; selectedID = id; needsLayout = true
        layoutSubtreeIfNeeded()
    }
    override func layout() {
        super.layout()
        let items = buttons
        let width = items.reduce(CGFloat(0)) { $0+Self.preferredWidth(for:$1) }+CGFloat(max(0,items.count-1))*strip.spacing
        isOverflowing = width > bounds.width+0.5
        let height = max(0,min(22,bounds.height)), y = (bounds.height-height)/2
        let leading: CGFloat = isOverflowing ? 22 : 0
        let trailing: CGFloat = isOverflowing ? 44 : 0
        for button in [previousButton,nextButton,overflowButton] { button.isHidden = !isOverflowing }
        previousButton.frame = NSRect(x:0,y:y,width:20,height:height)
        nextButton.frame = NSRect(x:max(0,bounds.width-44),y:y,width:20,height:height)
        overflowButton.frame = NSRect(x:max(0,bounds.width-20),y:y,width:20,height:height)
        scrollView.frame = NSRect(x:leading,y:y,width:max(0,bounds.width-leading-trailing),height:height)
        strip.setFrameSize(NSSize(width:max(1,width),height:22)); strip.layoutSubtreeIfNeeded()
        let resized = abs(previousWidth-bounds.width)>0.5; previousWidth = bounds.width
        scrollView.moveTabs(by:0)
        if !isOverflowing { scrollView.moveTabs(by:-scrollView.contentView.bounds.minX) }
        else if revealSelection || resized { revealSelectedTab() }
        revealSelection = false; updateNavigation()
    }
    func revealSelectedTab() {
        guard let selectedID,let button = buttons.first(where: { $0.workspaceID == selectedID }) else { return }
        let visible = scrollView.contentView.bounds
        if button.frame.minX < visible.minX { scrollView.moveTabs(by:button.frame.minX-visible.minX) }
        else if button.frame.maxX > visible.maxX { scrollView.moveTabs(by:button.frame.maxX-visible.maxX) }
    }
    private func updateNavigation() {
        let visible = scrollView.contentView.bounds
        previousButton.isEnabled = isOverflowing && visible.minX > 0.5
        nextButton.isEnabled = isOverflowing && visible.maxX < strip.frame.width-0.5
        overflowButton.toolTip = "Show all \(buttons.count) tabs"
    }
    @objc func previousTabs() { scrollView.moveTabs(by:-max(92,scrollView.contentView.bounds.width*0.7)) }
    @objc func nextTabs() { scrollView.moveTabs(by:max(92,scrollView.contentView.bounds.width*0.7)) }
    func allTabsMenu() -> NSMenu {
        let menu = NSMenu(title:"All Tabs")
        guard let controller = strip.controller else { return menu }
        for (i,workspace) in controller.workspaces.enumerated() {
            let item = NSMenuItem(title:"\(i+1)  \(workspace.title)",action:#selector(TerminalWindowController.selectTabFromMenu(_:)),keyEquivalent:"")
            if i < 9,let binding = controller.config.keybindings["selectTab\(i+1)"],let shortcut = Configuration.shortcut(binding) {
                item.keyEquivalent = shortcut.1.contains(.shift) ? shortcut.0.uppercased() : shortcut.0
                item.keyEquivalentModifierMask = shortcut.1
            }
            item.target = controller; item.representedObject = workspace.id
            item.state = i == controller.index ? .on : .off
            item.toolTip = workspace.title; menu.addItem(item)
        }
        return menu
    }
    @objc private func showAllTabs() { allTabsMenu().popUp(positioning:nil,at:NSPoint(x:0,y:overflowButton.bounds.minY),in:overflowButton) }
    func autoscrollDrag(at pointInWindow: NSPoint) {
        let point = scrollView.convert(pointInWindow,from:nil)
        if point.x < scrollView.bounds.minX+22 { scrollView.moveTabs(by:-12) }
        else if point.x > scrollView.bounds.maxX-22 { scrollView.moveTabs(by:12) }
    }
}


extension App {
    func owner(ofTab id: UUID) -> TerminalWindowController? { windows.first { $0.workspaces.contains { $0.id == id } } }
    func checkpointTransferredSessions() {
        if SessionRecovery.enabled && !keepingSessions && !shuttingDown { try? SessionRecovery.save(windows) }
        buildMenu()
    }
}

extension TerminalWindowController {
    func droppedTabID(_ pasteboard: NSPasteboard) -> UUID? {
        guard let value = pasteboard.string(forType:.mothTab),let id = UUID(uuidString:value),canReceiveTab(id) else { return nil }
        return id
    }
    func tabDropOperation(_ pasteboard: NSPasteboard) -> NSDragOperation { droppedTabID(pasteboard) == nil ? [] : .move }
    func acceptTabDrop(_ pasteboard: NSPasteboard) -> Bool { guard let id = droppedTabID(pasteboard) else { return false }; return receiveTab(id) }
}


extension NSPasteboard.PasteboardType { static let mothPane = NSPasteboard.PasteboardType("com.thom.moth.pane") }

final class PaneDragHandle: NSButton, NSDraggingSource {
    var paneID = UUID()
    private var start: NSPoint?
    private var dragging = false
    private weak var sourceApplication: App?
    private var escapeMonitor: Any?
    private var cancelled = false
    override func mouseDown(with event: NSEvent) { start = event.locationInWindow; dragging = false }
    override func mouseUp(with event: NSEvent) { start = nil; dragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging,let start,hypot(event.locationInWindow.x-start.x,event.locationInWindow.y-start.y) >= 5 else { return }
        dragging = true; cancelled = false; sourceApplication = (window?.windowController as? TerminalWindowController)?.application
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in if event.keyCode == 53 { self?.cancelled = true }; return event }
        let item = NSPasteboardItem(); item.setString(paneID.uuidString,forType:.mothPane)
        let preview = NSDraggingItem(pasteboardWriter:item)
        preview.setDraggingFrame(bounds,contents:image)
        beginDraggingSession(with:[preview],event:event,source:self).animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession,sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func draggingSession(_ session: NSDraggingSession,endedAt point: NSPoint,operation: NSDragOperation) {
        dragging = false; start = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        finishDrag(at:point,operation:operation,wasCancelled:cancelled || (NSApp.currentEvent?.type == .keyDown && NSApp.currentEvent?.keyCode == 53))
    }
    func finishDrag(at point: NSPoint,operation: NSDragOperation,wasCancelled: Bool) {
        guard operation.isEmpty,!wasCancelled,let app = sourceApplication ?? (window?.windowController as? TerminalWindowController)?.application,app.isOutsideTerminalWindows(point) else { return }
        _ = app.detachPane(paneID,at:point)
    }
    deinit { if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) } }
}

enum PaneDropZone { case left,right,top,bottom,centre
    var vertical: Bool { self == .left || self == .right }
    var before: Bool { self == .left || self == .top }
    static func at(_ point: NSPoint,in rect: NSRect) -> PaneDropZone {
        let distances: [(PaneDropZone,CGFloat)] = [(.left,(point.x-rect.minX)/max(1,rect.width)),(.right,(rect.maxX-point.x)/max(1,rect.width)),(.bottom,(point.y-rect.minY)/max(1,rect.height)),(.top,(rect.maxY-point.y)/max(1,rect.height))]
        if let nearest = distances.min(by: { $0.1 < $1.1 }),nearest.1 < 0.25 { return nearest.0 }
        return .centre
    }
    func preview(in rect: NSRect) -> NSRect {
        switch self {
        case .left:return NSRect(x:rect.minX,y:rect.minY,width:rect.width/2,height:rect.height)
        case .right:return NSRect(x:rect.midX,y:rect.minY,width:rect.width/2,height:rect.height)
        case .top:return NSRect(x:rect.minX,y:rect.midY,width:rect.width,height:rect.height/2)
        case .bottom:return NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height/2)
        case .centre:return rect
        }
    }
}

extension App {
    func owner(ofPane id: UUID) -> (TerminalWindowController,Workspace,Pane)? {
        for controller in windows { for workspace in controller.workspaces { if let pane = workspace.panes.first(where: { $0.id == id }) { return (controller,workspace,pane) } } }
        return nil
    }
    func canMovePane(_ id: UUID,to target: Pane,zone: PaneDropZone) -> Bool {
        guard let (_,source,pane) = owner(ofPane:id),pane !== target,let (_,destination,_) = owner(ofPane:target.id) else { return false }
        if zone == .centre { return true }
        let size=destination.splitSize(of:target)
        return source.panes.count > 1 && (source === destination || destination.panes.count < Workspace.maximumPanes) && (zone.vertical ? size.width >= 420 : size.height >= 280)
    }
    @discardableResult func movePane(_ id: UUID,to target: Pane,zone: PaneDropZone) -> Bool {
        guard canMovePane(id,to:target,zone:zone) else { return false }
        if let (_,source,_)=owner(ofPane:id) { source.restoreSplitLayout() }
        if let (_,destination,_)=owner(ofPane:target.id) { destination.restoreSplitLayout() }
        guard canMovePane(id,to:target,zone:zone),let (sourceWindow,source,pane) = owner(ofPane:id),let (targetWindow,destination,_) = owner(ofPane:target.id) else { return false }
        if zone == .centre {
            let placeholder = NSView(frame:pane.frame)
            Workspace.replaceSlot(pane,with:placeholder)
            Workspace.replaceSlot(target,with:pane)
            Workspace.replaceSlot(placeholder,with:target)
            if source !== destination {
                let a = source.panes.firstIndex(of:pane)!,b = destination.panes.firstIndex(of:target)!
                source.panes[a] = target; destination.panes[b] = pane
                source.bind(target); destination.bind(pane)
                if source.active === pane { source.active = target }
            }
        } else {
            guard source.detach(pane) else { return false }
            let split = TerminalSplitView(frame:target.frame); split.isVertical = zone.vertical; split.dividerStyle = .thin
            Workspace.replaceSlot(target,with:split)
            pane.translatesAutoresizingMaskIntoConstraints = true; target.translatesAutoresizingMaskIntoConstraints = true
            for view in (zone.before ? [pane,target] : [target,pane]) { split.addArrangedSubview(view) }
            destination.panes.append(pane); destination.bind(pane)
            destination.root.layoutSubtreeIfNeeded(); split.adjustSubviews()
            split.setPosition((zone.vertical ? split.bounds.width : split.bounds.height)/2,ofDividerAt:0)
        }
        destination.active = pane
        source.highlight(); destination.highlight()
        source.root.layoutSubtreeIfNeeded(); destination.root.layoutSubtreeIfNeeded()
        if sourceWindow !== targetWindow { pane.applyForTransfer(targetWindow.config); if zone == .centre { target.applyForTransfer(sourceWindow.config) } }
        source.changed?(); destination.changed?()
        targetWindow.window?.makeKeyAndOrderFront(nil); targetWindow.window?.makeFirstResponder(pane.terminal)
        checkpointTransferredSessions(); return true
    }
}

extension Workspace {
    /// Replace a leaf in its exact slot, preserving ancestor proportions.
    static func replaceSlot(_ old: NSView,with replacement: NSView) {
        guard let parent = old.superview else { return }
        let frame = old.frame
        if let split = parent as? NSSplitView {
            let frames = split.arrangedSubviews.map { ($0,$0.frame) },index = split.arrangedSubviews.firstIndex(of:old)!
            old.removeFromSuperview(); replacement.translatesAutoresizingMaskIntoConstraints = true
            split.insertArrangedSubview(replacement,at:index)
            for (view,rect) in frames where view !== old { view.frame = rect }
            replacement.frame = frame
        } else {
            old.removeFromSuperview(); parent.addSubview(replacement); replacement.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([replacement.leadingAnchor.constraint(equalTo:parent.leadingAnchor),replacement.trailingAnchor.constraint(equalTo:parent.trailingAnchor),replacement.topAnchor.constraint(equalTo:parent.topAnchor),replacement.bottomAnchor.constraint(equalTo:parent.bottomAnchor)])
        }
    }
}

extension Pane {
    func clearDropPreview() { dropPreview.isHidden = true }
    func paneDragOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let controller = window?.windowController as? TerminalWindowController,let value = info.draggingPasteboard.string(forType:.mothPane),let id = UUID(uuidString:value) else { clearDropPreview(); return [] }
        let zone = PaneDropZone.at(convert(info.draggingLocation,from:nil),in:bounds)
        guard controller.application.canMovePane(id,to:self,zone:zone) else { clearDropPreview(); return [] }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dropPreview.frame = zone.preview(in:bounds).insetBy(dx:3,dy:3); dropPreview.isHidden = false; CATransaction.commit()
        return .move
    }
    func acceptPaneDrop(_ info: NSDraggingInfo) -> Bool {
        clearDropPreview()
        guard let controller = window?.windowController as? TerminalWindowController,let value = info.draggingPasteboard.string(forType:.mothPane),let id = UUID(uuidString:value) else { return false }
        return controller.application.movePane(id,to:self,zone:PaneDropZone.at(convert(info.draggingLocation,from:nil),in:bounds))
    }
}


extension App {
    func isOutsideTerminalWindows(_ point: NSPoint) -> Bool { !windows.contains { $0.window?.isVisible == true && $0.window!.frame.contains(point) } }
    @discardableResult func detachPane(_ id: UUID,at point: NSPoint) -> TerminalWindowController? {
        guard let (source,workspace,pane) = owner(ofPane:id) else { return nil }
        if workspace.panes.count == 1 { return source.detachTab(workspace.id,at:point) }
        let size = pane.bounds.size
        guard workspace.detach(pane) else { return nil }
        let moved = Workspace(config:source.config,startProcesses:false,adopting:pane)
        let controller = TerminalWindowController(application:self,adopting:moved,template:source)
        windows.append(controller)
        controller.window?.setContentSize(NSSize(width:max(560,size.width),height:max(360,size.height+60)))
        if let window = controller.window {
            let area = (NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? window.frame
            window.setFrameOrigin(NSPoint(x:max(area.minX,min(point.x-80,area.maxX-window.frame.width)),y:max(area.minY,min(point.y-window.frame.height+20,area.maxY-window.frame.height))))
        }
        controller.presentAndFocus(); checkpointTransferredSessions(); return controller
    }
}
