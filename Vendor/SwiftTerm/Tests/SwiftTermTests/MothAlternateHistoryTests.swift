#if os(macOS)
import Foundation
import Testing
@testable import SwiftTerm

final class MothAlternateHistoryTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func terminal() -> Terminal { Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 4, scrollback: 30)) }
    @Test func hostResetRecoversUnfinishedSequenceAndModes() {
        let t = terminal()
        t.feed(text: "OLD_HISTORY\r\n\u{1b}[?1049h\u{1b}[?1000h\u{1b}[?2004h\u{1b}[?25l\u{1b}]2;unfinished")
        t.resetFromHost()
        #expect(!t.isCurrentBufferAlternate && t.mouseMode == .off && !t.bracketedPasteMode && !t.cursorHidden)
        t.feed(text: "RECOVERED")
        #expect(t.find("RECOVERED").matches.count == 1 && t.find("OLD_HISTORY").matches.isEmpty)
    }
    @Test func historyIsOptInAndBounded() {
        let t = terminal(); t.setAlternateScreenScrollback(true)
        t.feed(text: "\u{1b}[?1049h" + (0..<70).map { "line\($0)\r\n" }.joined())
        #expect(t.altBuffer.lines.count <= 34 && t.altBuffer.yBase > 0)
        #expect(t.find("line69").matches.count == 1 && t.find("line0").matches.isEmpty)
        t.setAlternateScreenScrollback(false)
        #expect(!t.altBuffer.hasScrollback && t.altBuffer.yBase == 0)
    }
    @Test func normalScreenAndAlternateHistoryStaySeparate() {
        let t = terminal(); t.setAlternateScreenScrollback(true)
        t.feed(text: "SHELL_MARK\r\n\u{1b}[?1049h" + (0..<12).map { "ALT_\($0)\r\n" }.joined())
        #expect(t.find("ALT_0").matches.count > 0 && t.find("SHELL_MARK").matches.isEmpty)
        t.feed(text: "\u{1b}[?1049l")
        #expect(t.find("SHELL_MARK").matches.count == 1 && t.find("ALT_0").matches.isEmpty)
        t.feed(text: "\u{1b}[?1049h")
        #expect(t.find("ALT_0").matches.isEmpty)
    }
    @Test func alternateResizesDoNotReflowScreenCoordinates() {
        let t = terminal(); t.setAlternateScreenScrollback(true)
        t.feed(text: "\u{1b}[?1049h1234567890ABCDEFGHIJ\r\nsecond\r\n")
        #expect(!t.altBuffer.isReflowEnabled)
        t.resize(cols: 10, rows: 4)
        #expect(t.find("second").matches.first?.startRow == 1)
    }
    @Test func explicitScrollUpRetainsReceivedRows() {
        let t = terminal(); t.setAlternateScreenScrollback(true)
        t.feed(text: "\u{1b}[?1049hFIRST\r\nSECOND\r\nTHIRD\r\nFOURTH\u{1b}[2S")
        #expect(t.altBuffer.yBase == 2)
        #expect(t.find("FIRST").matches.count == 1 && t.find("SECOND").matches.count == 1)
    }
}
#endif
