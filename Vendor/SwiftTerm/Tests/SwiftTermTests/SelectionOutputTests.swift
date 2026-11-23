#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@Suite(.serialized)
final class SelectionOutputTests {
    func view(history: Int = 20) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        view.getTerminal().resize(cols: 20, rows: 4)
        view.getTerminal().changeHistorySize(history)
        return view
    }

    func select(_ text: String, in view: TerminalView) throws {
        let match = try #require(view.getTerminal().find(text).matches.first)
        #expect(view.revealSearchMatch(match))
        #expect(view.getSelection() == text)
    }

    @Test(arguments: [false, true])
    func appendedOutputKeepsSelection(byteFeed: Bool) throws {
        let view = view()
        view.feed(text: "selected text\r\n")
        try select("selected text", in: view)
        if byteFeed { view.feed(byteArray: Array("fresh output\r\n".utf8)[...]) }
        else { view.feed(text: "fresh output\r\n") }
        #expect(view.selectionActive)
        #expect(view.getSelection() == "selected text")
    }

    @Test func scrolledSelectionStaysOnItsOriginalText() throws {
        let view = view(history: 8), terminal = view.getTerminal()
        view.feed(text: (0..<11).map { "line-\($0)\r\n" }.joined())
        try select("line-9", in: view)
        let row = view.selection.start.row, top = terminal.displayBuffer.linesTop
        view.feed(text: "line-11\r\n")
        let trimmed = terminal.displayBuffer.linesTop-top
        #expect(trimmed > 0)
        #expect(view.selection.start.row == row-trimmed)
        #expect(view.getSelection() == "line-9")
    }

    @Test func overwrittenCellsKeepTheLiveRange() throws {
        let view = view()
        view.feed(text: "original\r\n")
        try select("original", in: view)
        view.feed(text: "\u{1b}[1;1Hupdated!")
        #expect(view.selectionActive)
        #expect(view.getSelection() == "updated!")
    }

    @Test func controlOnlyOutputKeepsSelection() throws {
        let view = view()
        view.feed(text: "selected\r\n")
        try select("selected", in: view)
        view.feed(text: "\u{1b}[?25l")
        #expect(view.getSelection() == "selected")
    }

    @Test(arguments: [false, true])
    func partiallyEvictedRangeKeepsRemainingRows(reversed: Bool) {
        let view = view(history: 2)
        view.feed(text: "one\r\ntwo\r\nthree\r\n")
        let a = Position(col: 1, row: 0), b = Position(col: 5, row: 2)
        view.selection.setSoftStart(bufferPosition: reversed ? b : a)
        view.selection.dragExtend(bufferPosition: reversed ? a : b)
        view.feed(text: "four\r\nfive\r\nsix\r\n")
        #expect(view.getSelection() == "two\nthree")
    }

    @Test func fullyEvictedRangeClears() throws {
        let view = view(history: 2)
        view.feed(text: "selected\r\n")
        try select("selected", in: view)
        view.feed(text: (0..<10).map { "line-\($0)\r\n" }.joined())
        #expect(!view.selectionActive)
        #expect(view.getSelection() == nil)
    }

    @Test func selectionDoesNotJumpIntoAnotherScreenBuffer() throws {
        let view = view()
        view.feed(text: "normal\r\n")
        try select("normal", in: view)
        view.feed(text: "\u{1b}[?1049halternate")
        #expect(!view.selectionActive)
    }

    @Test(arguments: ["line-2", "line-9"])
    func clearingScrollbackPreservesOnlySurvivingRanges(text: String) throws {
        let view = view(history: 8)
        view.feed(text: (0..<11).map { "line-\($0)\r\n" }.joined())
        try select(text, in: view)
        view.feed(text: "\u{1b}[3J")
        #expect(view.getSelection() == (text == "line-9" ? text : nil))
    }

    @Test func synchronizedOutputKeepsSelectionOnTheSameScreen() throws {
        let view = view()
        view.feed(text: "selected\r\n")
        try select("selected", in: view)
        view.feed(text: "\u{1b}[?2026hfresh output\r\n")
        #expect(view.getSelection() == "selected")
        view.feed(text: "\u{1b}[?2026l")
        #expect(view.getSelection() == "selected")
    }

    @Test func mouseAnchorFollowsScrollbackBeforeDraggingBegins() throws {
        let view = view(history: 8)
        view.feed(text: (0..<11).map { "line-\($0)\r\n" }.joined())
        func event(_ type: NSEvent.EventType, column: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: (column+0.1)*view.caretFrame.width, y: view.frame.height-view.caretFrame.height/2),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown,column: 0))
        view.feed(text: "line-11\r\n")
        view.mouseDragged(with: try event(.leftMouseDragged,column: 5))
        #expect(view.getSelection() == "line-8\nline-")
        view.mouseUp(with: try event(.leftMouseUp,column: 5))
    }

    @Test func dragCanContinueAfterOutput() {
        let view = view()
        view.feed(text: "alpha beta\r\n")
        view.selection.setSoftStart(bufferPosition: Position(col: 0, row: 0))
        view.selection.dragExtend(bufferPosition: Position(col: 5, row: 0))
        view.feed(text: "fresh output\r\n")
        #expect(view.selectionActive)
        view.selection.dragExtend(bufferPosition: Position(col: 10, row: 0))
        #expect(view.getSelection() == "alpha beta")
    }
}
#endif
