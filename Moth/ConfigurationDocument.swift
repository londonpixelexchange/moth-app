// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import Foundation
import TOMLKit
import CoreFoundation

/// TOMLKit handles the grammar. Source-region edits preserve all untouched comments/formatting.
enum TOMLDocument {
    static func parse(_ text: String) throws -> TOMLTable {
        do { return try TOMLTable(string: text) }
        catch let error as TOMLParseError {
            throw Configuration.invalid("TOML line \(error.source.begin.line), column \(error.source.begin.column): \(error.description)")
        }
    }
    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
    static func quote(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    static func key(_ key: String) -> String {
        key.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || $0 == "_" || $0 == "-" } ? key : quote(key)
    }
    static func value(_ value: TOMLValueConvertible) -> String {
        if let number = value.double { return String(number) }
        var item = value
        if let table = value.table {
            let copy = TOMLTable(inline: true)
            for name in table.keys { copy[name] = table[name] }
            item = copy
        }
        let output = TOMLTable(["v": item]).convert(to: .toml)
        return String(output.dropFirst(output.firstIndex(of: "=")!.utf16Offset(in: output)+1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static let descriptions: [String: String] = [
        "paint": "type: solid | linear. colors: six-digit hex values; empty inherits the theme.\n# Gradients accept 2–6 stops. angle: 0–360 degrees for linear gradients.",
        "borderPaint": "Border paint: type = solid | linear; colors = [] inherits borderColor.\n# Gradients use 2–6 six-digit colours. angle controls the linear direction.",
        "typography": "lineHeight: cell height multiplier (1–2). characterSpacing: extra points per cell (0–6).\n# antialias: smooth text edges (true by default); false draws crisp pixel edges.\n# ligatures: opt in to programming ligatures; useBold/useItalic enable ANSI font styles.\n# [typography.features] contains four-character OpenType tags and integer values (0=off, 1=on).\n# Empty features use font defaults; disabling ligatures overrides liga/calt/dlig/hlig.",
        "window": "Tabs/session info placement and the inside window border.\n# chromePosition: bottom or titlebar; showTabBar and showStatusBar control visibility. Colours are six hex digits, without #.\n# showBorder: false hides the custom border without losing its saved paint/width.\n# opacity: 0–1, background only; text stays opaque. frosted: native blur behind the window.\n# frostIntensity: 0–1, blending clear glass with the full native frosting effect.\n# Lower opacity reveals the desktop or frosting. Reduce Transparency makes the background opaque.",
        "background": "style: flow for animation, solid for a plain background, or image for a picture.\n# imagePath: local image file (supports ~); imageScale: fill or fit; imageOpacity: 0–1.\n# effectColors: 2–6 animation colours; [] uses the default palette.\n# intensity is Strength (0–1); speed controls motion. background.paint applies only when Off.\n# Motion respects Reduce Motion.",
        "cursor": "shape: block | underline | bar. animation: breathe | blink | noblink.\n# period is a full animation cycle in seconds (0.2–5). View > Cursor saves these settings.",
        "bell": "mode: visual (default), sound, both, or off.\n# style: border (pane edge), flash (soft pane wash), window-border (whole window edge).\n# intensity: 0–1; flash peaks at 18% of this value. thickness: border width in points (1–12).\n# sound: system name such as Glass, Ping, Pop, or an absolute audio path. volume: 0–1.\n# badge: count bells on the Dock icon while Moth is inactive; clears when Moth becomes active.\n# duration: visual highlight seconds (0.08–1). color: empty uses the theme accent, or six hex digits.",
        "keyboardSound": "enabled: typing sounds, off by default. Toggle with Cmd+Option+K.\n# style: drip | tink | wood | notes (Soft Keys) | glass | pluck | bells | marimba | custom.\n# volume: 0–1 (quiet default 0.12). reverb: 0–1 (dry to spacious).\n# key: C, C#, D, D#, E, F, F#, G, G#, A, A#, B.\n# musical: false plays the natural sound; true enables key, mode and pattern.\n# mode: ionian | dorian | phrygian | lydian | mixolydian | aeolian | locrian.\n# pattern: ascending | descending | random | arpeggiating.\n# files: absolute audio-file paths for style = custom (up to 16 clips, 10 seconds each).\n# Multiple files rotate; musical custom playback treats the original as C4 and changes speed.\n# Shortcuts and pasted text stay silent.",
        "closeConfirmation": "Skip confirmation only when EVERY local program in the session is allowed.\n# Includes foreground and background children: allowing zsh does not allow its running jobs.\n# Use exact executable names (zsh, vim) or absolute paths. No wildcard matching.\n# enabled = false disables all close/quit confirmations, including unidentified processes.",
        "keybindings": "Command shortcuts. toggleMaximizePane maximises or restores the active split pane. selectTab1–selectTab9 select the matching tab in the active window.",
        "updates": "checkAtLaunch checks getmoth.dev for releases at launch. Downloads open in your browser. App-wide.",
        "advanced": "allowDoubleSizeLines enables DEC double-width and double-height lines (app-wide).\n# Disabled ignores size requests and returns existing lines to normal.\n# sessionRecovery keeps new PTYs in a local helper for reconnection after an app crash. Up to 64 MB of output per pane stays in helper memory.\n# inheritWorkingDirectory uses the local shell cwd for new tabs and splits; new windows use workingDirectory.\n# Launch environment and directory apply to new sessions. Empty paths use defaults or disable logging.\n# logDirectory writes raw terminal output; clipboard writes are disabled by default.",
        "macros": "Named snippets or recordings. Each [macros.Name] has text, submit, shortcut, keys and delays.\n# Use either text or recorded keys. Recorded keys include Enter/control keys; delays are seconds.",
        "palette": "Custom terminal base colours override the selected built-in theme. Set enabled = false to use theme colours."
    ]
    static let sectionOrder = ["typography", "window", "background", "cursor", "bell", "keyboardSound", "closeConfirmation", "updates", "advanced", "macros", "keybindings", "palette"]
    static func render(_ table: TOMLTable) -> String {
        var out = "# Moth configuration\n# Save to reload every open window. Invalid edits keep the last valid settings.\n# textEncoding selects the session charset (UTF-8 is recommended).\n# enabledEncodings controls the app-wide encoding choices; current profile/session encodings remain valid when hidden.\n# closeOnExit: true closes an exited pane/tab, then the last window; false retains output and exit status.\n# alternateScreenScrollback saves received lines in mosh/full-screen sessions (bounded by scrollback).\n# ansiColors: [] for defaults, or 16 hex colours (normal 0–7, bright 8–15).\n# defaultProfileID: empty uses Default; otherwise a named profile UUID from Profiles/*.toml.\n# showLayoutsOnLaunch offers saved window layouts when the app launches.\n# Built-in colour themes: \(Configuration.themeNames.joined(separator: ", ")).\n# Choose colours and motion in Settings (Cmd+,).\n# An enabled [palette] overrides theme colours; set palette.enabled = false to use built-ins.\n\n"
        let rootOrder = ["theme", "ansiColors", "showLayoutsOnLaunch", "defaultProfileID", "fontName", "fontSize", "scrollback", "alternateScreenScrollback", "closeOnExit", "textEncoding", "enabledEncodings", "shell", "optionAsMeta"]
        let scalarKeys = table.keys.filter { table[$0]?.table == nil }.sorted { a,b in (rootOrder.firstIndex(of:a) ?? 100) == (rootOrder.firstIndex(of:b) ?? 100) ? a < b : (rootOrder.firstIndex(of:a) ?? 100) < (rootOrder.firstIndex(of:b) ?? 100) }
        for name in scalarKeys { out += "\(key(name)) = \(value(table[name]!))\n" }
        func section(_ table: TOMLTable, path: [String]) {
            out += "\n"
            if let description = descriptions[path.last!] { out += "# \(description)\n" }
            out += "[\(path.map(key).joined(separator: "."))]\n"
            for name in table.keys.sorted() where table[name]?.table == nil { out += "\(key(name)) = \(value(table[name]!))\n" }
            for name in table.keys.sorted() { if let child = table[name]?.table { section(child, path: path+[name]) } }
        }
        let sections = table.keys.filter { table[$0]?.table != nil }.sorted { (sectionOrder.firstIndex(of:$0) ?? 100) < (sectionOrder.firstIndex(of:$1) ?? 100) }
        for name in sections { section(table[name]!.table!, path: [name]) }
        if table["palette"] == nil { out += "\n# Optional custom terminal palette; uncomment this section to enable.\n# [palette]\n# enabled = true\n# background = \"151820\"\n# foreground = \"DFE4EF\"\n# accent = \"A5B8FF\"\n" }
        return out
    }
    static func merge(into target: TOMLTable, from source: TOMLTable) {
        for name in source.keys {
            if let old = target[name]?.table, let new = source[name]?.table { merge(into: old, from: new) }
            else { target[name] = source[name] }
        }
    }
    static func table(fromJSON object: [String: Any]) -> TOMLTable {
        let result = TOMLTable()
        for (key, object) in object where key != "_help" { if let converted = jsonValue(object) { result[key] = converted } }
        return result
    }
    static func jsonValue(_ object: Any) -> TOMLValueConvertible? {
        if let s = object as? String { return s }
        if let n = object as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            return String(cString: n.objCType).contains("f") || String(cString: n.objCType).contains("d") ? n.doubleValue as TOMLValueConvertible : n.int64Value as TOMLValueConvertible
        }
        if let a = object as? [Any] { return TOMLArray(a.compactMap(jsonValue)) }
        if let d = object as? [String: Any] { return table(fromJSON: d) }
        return nil // TOML has no null; the original JSON remains backed up.
    }
    /// Remove the old factory palette assignment; preserve handwritten multiline arrays and comments.
    static func removingLegacyBackgroundColors(_ text: String) throws -> String {
        guard let value = try parse(text)["background"]?["colors"] else { return text }
        let region = value.tomlValue.source
        guard region.begin.line == region.end.line else { return text }
        var lines = text.components(separatedBy: "\n")
        let index = region.begin.line-1
        guard lines.indices.contains(index), lines[index].range(of: #"^\s*(colors|background\.colors)\s*="# , options: .regularExpression) != nil else { return text }
        let scalars = Array(lines[index].unicodeScalars)
        let suffix = String(String.UnicodeScalarView(scalars.dropFirst(region.end.column-1))).trimmingCharacters(in: .whitespaces)
        if suffix.hasPrefix("#") { lines[index] = suffix } else { lines.remove(at: index) }
        return lines.joined(separator: "\n")
    }
    struct Edit { let range: NSRange; let replacement: String }
    static func updating(_ text: String, with desired: TOMLTable) throws -> String {
        let current = try parse(text)
        var edits: [Edit] = [], inserts: [Int: String] = [:], appended = ""
        let ns = text as NSString
        func offset(_ position: TOMLSourcePosition) throws -> Int {
            var line = 1, column = 1, utf16 = 0
            for scalar in text.unicodeScalars {
                if line == position.line && column == position.column { return utf16 }
                utf16 += scalar.value > 0xFFFF ? 2 : 1
                if scalar == "\n" { line += 1; column = 1 } else { column += 1 }
            }
            if line == position.line && column == position.column { return utf16 }
            throw Configuration.invalid("Cannot locate a TOML value to update; the original file was left unchanged.")
        }
        func replacement(_ old: TOMLValueConvertible, _ new: TOMLValueConvertible) throws {
            if old.tomlValue == new.tomlValue { return }
            let source = old.tomlValue.source
            let start = try offset(source.begin), end = try offset(source.end)
            edits.append(Edit(range: NSRange(location: start, length: end-start), replacement: value(new)))
        }
        func visit(_ old: TOMLTable, _ new: TOMLTable, path: [String], source: TOMLSourceRegion?) throws {
            var missing: [String] = []
            // This dictionary is owned by the feature controls: absence means
            // inherit the font default, rather than retain an old override.
            if [["typography","features"],["environment"],["advanced","environment"]].contains(path) {
                for name in old.keys where new[name] == nil {
                    let region = old[name]!.tomlValue.source
                    let start = try offset(region.begin), end = try offset(region.end)
                    let line = ns.lineRange(for:NSRange(location:start,length:end-start))
                    let trailing = ns.substring(with:NSRange(location:end,length:line.location+line.length-end)).trimmingCharacters(in:.whitespacesAndNewlines)
                    edits.append(Edit(range:line,replacement:trailing.hasPrefix("#") ? trailing+"\n" : ""))
                }
            }
            for name in new.keys.sorted() {
                let next = new[name]!
                if let previous = old[name] {
                    if let left = previous.table, let right = next.table {
                        if left.inline {
                            let copy = TOMLTable(inline: true)
                            if ![["typography","features"],["environment"],["advanced","environment"]].contains(path+[name]) { for key in left.keys { copy[key] = left[key] } }
                            merge(into: copy, from: right); try replacement(previous, copy)
                        } else { try visit(left, right, path: path+[name], source: previous.tomlValue.source) }
                    } else { try replacement(previous, next) }
                } else if let table = next.table {
                    func appendSection(_ table: TOMLTable, path: [String]) {
                        appended += "\n"
                        if path.count == 1, let note = descriptions[path[0]] { appended += "# \(note)\n" }
                        appended += "[\(path.map(key).joined(separator: "."))]\n"
                        for name in table.keys.sorted() where table[name]?.table == nil { appended += "\(key(name)) = \(value(table[name]!))\n" }
                        for name in table.keys.sorted() { if let child = table[name]?.table { appendSection(child, path: path+[name]) } }
                    }
                    appendSection(table, path: path+[name])
                } else { missing.append("\(key(name)) = \(value(next))\n") }
            }
            if !missing.isEmpty {
                let index: Int
                if path.isEmpty { index = 0 }
                else if let source {
                    let start = try offset(source.begin)
                    let line = ns.lineRange(for: NSRange(location: start, length: 0))
                    let lineText = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                    // An implicit parent table can point at its child's header.
                    // Only insert here when that header actually names this table.
                    var headerTable = try? parse(lineText+"\n__moth_insert_marker__ = true\n")
                    for component in path { headerTable = headerTable?[component]?.table }
                    if headerTable?["__moth_insert_marker__"]?.bool != true {
                        let prefix = path.map(key).joined(separator: ".") + "."
                        inserts[0, default: ""] += missing.map { prefix+$0 }.joined()
                        return
                    }
                    index = line.location+line.length
                } else { throw Configuration.invalid("Cannot locate the TOML section to update.") }
                let separator = index == ns.length && index > 0 && !text.hasSuffix("\n") ? "\n" : ""
                inserts[index, default: ""] += separator + missing.joined()
            }
        }
        try visit(current, desired, path: [], source: nil)
        for (index, content) in inserts { edits.append(Edit(range: NSRange(location: index, length: 0), replacement: content)) }
        let result = NSMutableString(string: text)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) { result.replaceCharacters(in: edit.range, with: edit.replacement) }
        if !appended.isEmpty { result.append("\n"+appended) }
        _ = try parse(result as String) // Validate the edit before touching the user's file.
        return result as String
    }
}
