// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import SwiftTerm

final class MacroRecorder {
    static let shared = MacroRecorder()
    private(set) weak var source: ShellView?
    private(set) var keys: [String] = []
    private(set) var delays: [Double] = []
    private var last = 0.0
    private var bytes = 0
    private(set) var reachedLimit = false
    func start(_ terminal: ShellView) { source = terminal; keys = []; delays = []; last = 0; bytes = 0; reachedLimit = false }
    func capture(_ data: ArraySlice<UInt8>,source: ShellView) {
        guard self.source === source,!data.isEmpty,!reachedLimit else { return }
        guard keys.count < 512,bytes+data.count <= 16384,let text = String(bytes:data,encoding:.utf8) else { reachedLimit = true; return }
        let now = ProcessInfo.processInfo.systemUptime, delay = last == 0 ? 0 : min(5,now-last)
        guard delays.reduce(0,+)+delay <= 120 else { reachedLimit = true; return }
        keys.append(text); delays.append(delay); bytes += data.count; last = now
    }
    func finish() -> Configuration.Macro {
        var macro = Configuration.Macro(); macro.keys = keys; macro.delays = delays; source = nil; return macro
    }
    func cancel() { source = nil; keys = []; delays = [] }
}

final class MacroPlayer {
    private var generation = 0
    private(set) var isPlaying = false
    func stop() { generation += 1; isPlaying = false }
    func play(_ macro: Configuration.Macro,in terminal: ShellView) {
        stop(); let token = generation
        if macro.keys.isEmpty {
            let bracket = terminal.getTerminal().bracketedPasteMode
            if bracket { terminal.sendUserText("\u{1b}[200~") }
            terminal.sendUserText(macro.text)
            if bracket { terminal.sendUserText("\u{1b}[201~") }
            if macro.submit { terminal.sendUserText("\r") }; return
        }
        isPlaying = true; var elapsed = 0.0
        for (index,key) in macro.keys.enumerated() {
            elapsed += macro.delays[index]
            DispatchQueue.main.asyncAfter(deadline:.now()+elapsed) { [weak self,weak terminal] in
                guard let self,self.generation == token,let terminal,terminal.process.running else { return }
                terminal.sendUserText(key)
                if index == macro.keys.count-1 { self.isPlaying = false }
            }
        }
    }
}

extension App {
    @objc func showMacros(_ sender: Any?) { showSettings(nil); appearancePanel?.tabs.selectTabViewItem(withIdentifier:"Macros") }
    @objc func runMacro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,let macro = config.macros[name],let pane = active?.workspace.active,MacroRecorder.shared.source == nil else { return }
        pane.window?.makeKeyAndOrderFront(nil); pane.window?.makeFirstResponder(pane.terminal)
        macroPlayer.play(macro,in:pane.terminal)
    }
    @objc func stopMacro(_ sender: Any?) { macroPlayer.stop() }
    @objc func toggleMacroRecording(_ sender: Any?) {
        let recorder = MacroRecorder.shared
        if recorder.source != nil {
            let limited = recorder.reachedLimit, macro = recorder.finish(); buildMenu(); windows.forEach { $0.refreshFooter() }
            guard !macro.keys.isEmpty else { return }
            let alert = NSAlert(); alert.messageText = "Save Recorded Macro"
            alert.informativeText = limited ? "The recording reached its size or time limit. Name the captured sequence." : "Name this sequence of typing and terminal keys. Replaying it also replays Enter and other control keys."
            var suggested = "Recorded Macro", suffix = 2
            while config.macros[suggested] != nil { suggested = "Recorded Macro \(suffix)"; suffix += 1 }
            let name = NSTextField(string:suggested); name.frame = NSRect(x:0,y:0,width:280,height:24); alert.accessoryView = name; alert.window.initialFirstResponder = name
            alert.addButton(withTitle:"Save"); alert.addButton(withTitle:"Discard")
            guard let window = active?.window else { return }
            alert.beginSheetModal(for:window) { [weak self] response in
                guard response == .alertFirstButtonReturn,let self else { return }
                var candidate = self.config; candidate.macros[name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)] = macro
                do { try candidate.validate(); try Configuration.save(candidate); self.config = candidate; self.buildMenu(); self.appearancePanel?.refresh() } catch { self.showError(error) }
            }
        } else if let terminal = active?.workspace.active.terminal {
            macroPlayer.stop(); recorder.start(terminal); terminal.window?.makeKeyAndOrderFront(nil); terminal.window?.makeFirstResponder(terminal)
            buildMenu(); windows.forEach { $0.refreshFooter() }
        }
    }
}
