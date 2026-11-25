import Foundation
import Testing
@testable import SwiftTerm

@Suite(.serialized)
struct MothResizeTests {
    @Test func resizeMeasurements() {
        for history in [0, 10000] {
            for filled in [false, true] {
                var trials: [Double] = []
                var allocated = 0
                for _ in 0..<3 {
                    let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols:100,rows:30,scrollback:history)
                    _ = delegate
                    if filled { terminal.feed(text:(0..<1000).map { "row \($0) a short history line\r\n" }.joined()) }
                    let before = ProcessInfo.processInfo.systemUptime
                    for step in 0..<120 { terminal.resize(cols:80+step%40,rows:25+step%10) }
                    trials.append((ProcessInfo.processInfo.systemUptime-before)*1000/120)
                    allocated = terminal.normalBuffer.lines.getArray().compactMap{$0}.count
                }
                print("RESIZE_BENCH history=\(history) filled=\(filled) median_ms=\(trials.sorted()[1]) allocated_rows=\(allocated)")
            }
        }
    }

    @Test func resizingAnEmptyTerminalKeepsUnusedHistoryUnallocated() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols:100,rows:30,scrollback:10000)
        _ = delegate
        terminal.setAlternateScreenScrollback(true)
        for size in [(120,30),(60,20),(140,40),(80,24)] { terminal.resize(cols:size.0,rows:size.1) }
        #expect(terminal.altBuffer.lines.getArray().compactMap{$0}.count <= 40)
        let buffer = terminal.normalBuffer
        // Retired visible rows may remain cached, but unused scrollback must stay lazy.
        #expect(buffer.lines.getArray().compactMap{$0}.count <= 40)
        #expect(buffer.lines.count == 24)
        #expect((0..<buffer.lines.count).allSatisfy { buffer.lines[$0].count >= 80 })
    }

    @Test func resizedRowsRemainValidWhenRetiredSlotsAreReused() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols:100,rows:30,scrollback:10000)
        _ = delegate
        terminal.resize(cols:50,rows:10)
        terminal.resize(cols:140,rows:40)
        terminal.feed(text:(0..<80).map { "\($0) " + String(repeating:"x",count:120)+"\r\n" }.joined())
        #expect(terminal.find("79 ").matches.count == 1)
        #expect((0..<terminal.normalBuffer.lines.count).allSatisfy { terminal.normalBuffer.lines[$0].count >= 140 })
    }

    @Test func resizeKeepsWrappedHistoryText() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols:100,rows:30,scrollback:10000)
        _ = delegate
        terminal.feed(text:(0..<200).map { "row \($0): " + String(repeating:"abcdefghij",count:16)+"\r\n" }.joined())
        let text = terminal.exportPlainText()
        for columns in [60,120,80,140,100] { terminal.resize(cols:columns,rows:30) }
        #expect(terminal.exportPlainText() == text)
    }
}
