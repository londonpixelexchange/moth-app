// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: GPL-3.0-or-later
// Licensed under GNU GPL version 3 or later. See LICENSE.

import AppKit
import Carbon
import UniformTypeIdentifiers

extension App {
    @objc func toggleSecureKeyboardEntry(_ sender: Any?) {
        secureKeyboardEntry.toggle(); updateSecureInput(); buildMenu()
    }
    func updateSecureInput() {
        let desired = secureKeyboardEntry && NSApp.isActive
        if desired && !ownsSecureInput {
            if EnableSecureEventInput() == noErr { ownsSecureInput = true }
            else { secureKeyboardEntry = false }
        } else if !desired && ownsSecureInput { DisableSecureEventInput(); ownsSecureInput = false }
    }
    func exportText(selection: Bool) -> String {
        guard let terminal = active?.workspace.active.terminal else { return "" }
        return selection ? terminal.getSelection() ?? "" : terminal.getTerminal().exportPlainText()
    }
    @objc func saveScrollback(_ sender: Any?) { saveTerminalText(selection:false) }
    @objc func saveSelectedText(_ sender: Any?) { saveTerminalText(selection:true) }
    private func saveTerminalText(selection: Bool) {
        let text = exportText(selection:selection)
        guard !text.isEmpty,let window = active?.window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = selection ? "Moth Selection.txt" : "Moth Scrollback.txt"
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK,let url = panel.url else { return }
            do { try text.write(to:url,atomically:true,encoding:.utf8) } catch { self?.showError(error) }
        }
    }
    @objc func pageSetup(_ sender: Any?) { NSPageLayout().runModal(with:NSPrintInfo.shared) }
    @objc func printScrollback(_ sender: Any?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let width = max(100,info.paperSize.width-info.leftMargin-info.rightMargin)
        let text = NSTextView(frame:NSRect(x:0,y:0,width:width,height:100))
        text.isRichText = false; text.font = NSFont(name:config.fontName,size:11) ?? .monospacedSystemFont(ofSize:11,weight:.regular)
        text.textColor = .black; text.backgroundColor = .white; text.string = exportText(selection:false)
        text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
        text.layoutManager?.ensureLayout(for:text.textContainer!)
        let height = text.layoutManager?.usedRect(for:text.textContainer!).height ?? 100
        text.setFrameSize(NSSize(width:width,height:max(100,height+20)))
        NSPrintOperation(view:text,printInfo:info).run()
    }
}

/// macOS may rewrite the conventional full-screen item to Fn+F. Keep the
/// explicitly requested Command-Control-F visible and available in Moth.
final class FullscreenMenuItem: NSMenuItem {
    override var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        get { [.command,.control] }
        set { super.keyEquivalentModifierMask = [.command,.control] }
    }
}
