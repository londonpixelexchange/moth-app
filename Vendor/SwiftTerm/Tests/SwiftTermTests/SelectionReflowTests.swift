import Testing
@testable import SwiftTerm
final class SelectionReflowTests {
    func host(_ text: String,cols: Int = 40,rows: Int = 12) -> HeadlessTerminal {
        var options = TerminalOptions.default; options.cols = cols; options.rows = rows; options.scrollback = 1000
        let host = HeadlessTerminal(options:options) { _ in }; host.terminal.feed(byteArray:Array(text.utf8)); return host
    }
    @Test func selectionSurvivesNarrowAndWideReflow() {
        let h = host("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda\r\nsecond logical line\r\n")
        let t = h.terminal!,s = SelectionService(terminal:t)
        s.setSoftStart(bufferPosition:Position(col:6,row:0)); s.shiftExtend(bufferPosition:Position(col:12,row:1))
        let expected = s.getSelectedText()
        for width in [18,70,26,40] {
            let state = s.captureResizeState(); t.resize(cols:width,rows:15); s.restoreResizeState(state)
            #expect(s.active); #expect(s.getSelectedText() == expected)
        }
    }
    @Test func multilineAndUnicodeSelectionSurvives() {
        let h = host("one 🦋 e\u{301} two three four five six seven eight nine ten\r\nnext logical line\r\n")
        let t = h.terminal!,s = SelectionService(terminal:t)
        s.setSoftStart(bufferPosition:Position(col:0,row:0)); s.shiftExtend(bufferPosition:Position(col:10,row:2))
        let expected = s.getSelectedText(),state = s.captureResizeState()
        t.resize(cols:23,rows:10); s.restoreResizeState(state)
        #expect(s.active); #expect(s.getSelectedText() == expected)
    }
    @Test func scrolledViewportStaysAtSameLogicalText() {
        let h = host((0..<90).map { "history \($0) with enough text to wrap on resizing\r\n" }.joined())
        let t = h.terminal!,s = SelectionService(terminal:t),buffer = t.displayBuffer
        buffer.yDisp = 20
        let before = t.getDisplayText(start:Position(col:0,row:20),end:Position(col:8,row:20))
        let state = s.captureResizeState(); t.resize(cols:24,rows:15); s.restoreResizeState(state)
        #expect(buffer.yDisp < buffer.yBase)
        #expect(t.getDisplayText(start:Position(col:0,row:buffer.yDisp),end:Position(col:8,row:buffer.yDisp)) == before)
    }
    @Test func alternateScreenSelectionRemainsOnItsCells() {
        let h = host("\u{1b}[?1049hhello alternate screen")
        let t = h.terminal!,s = SelectionService(terminal:t)
        s.setSoftStart(bufferPosition:Position(col:0,row:0)); s.shiftExtend(bufferPosition:Position(col:5,row:0))
        let state = s.captureResizeState(); t.resize(cols:30,rows:15); s.restoreResizeState(state)
        #expect(s.active); #expect(s.getSelectedText() == "hello")
    }
}
