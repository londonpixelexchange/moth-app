//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/29/20.
//

import Foundation
import Testing

@testable import SwiftTerm

final class SelectionTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
        print ("here")
    }
    
    @Test(arguments: [false, true])
    func copyingWrappedTextAfterScrollbackPreservesLogicalLines(reversed: Bool) {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 8))
        terminal.feed(text: String(repeating: "history\r\n", count: 30))
        let base = terminal.buffer.yBase
        #expect(base > 0)
        let historyWraps = (0..<base).map { terminal.buffer.lines[$0].isWrapped }
        let text = "This is one long line that wraps across several terminal rows."
        // Redrawing above the bottom row exercises wrapping into existing screen rows.
        terminal.feed(text: "\u{1b}[1;1H\u{1b}[J"+text+"\r\nnext line")
        let cursor = terminal.getCursorLocation()
        let start = Position(col: 0, row: base)
        let end = Position(col: cursor.x, row: base+cursor.y)
        let selection = SelectionService(terminal: terminal)
        selection.setSoftStart(bufferPosition: reversed ? end : start)
        selection.dragExtend(bufferPosition: reversed ? start : end)
        #expect(selection.getSelectedText() == text+"\nnext line")
        #expect((0..<base).map { terminal.buffer.lines[$0].isWrapped } == historyWraps)
    }

    @Test func testDoesNotCrashWhenSelectingWordOrExpressionOutsideColumnRange() {
        let terminal = Terminal(delegate: self, options: TerminalOptions (cols: 10, rows: 10))
        let selection = SelectionService(terminal: terminal)
        terminal.feed (text: "1234567890")
        
        // depending on the size of terminal view, there might be a space near the margin where the user
        // clicks which might result in a col or row outside the bounds of terminal,
        selection.selectWordOrExpression(at: Position(col: -1, row: 0), in: terminal.buffer)
        selection.selectWordOrExpression(at: Position(col: 11, row: 0), in: terminal.buffer)
    }
    
    @Test func testDoesNotCrashWhenSelectingWordOrExpressionOutsideRowRange() {
        let terminal = Terminal(delegate: self, options: TerminalOptions (cols: 10, rows: 10))
        let selection = SelectionService(terminal: terminal)
        terminal.feed (text: "1234567890")

        // depending on the size of terminal view, there might be a space near the margin where the user
        // clicks which might result in a col or row outside the bounds of terminal,
        selection.selectWordOrExpression(at: Position (col: 0, row: -1), in: terminal.buffer)

    }

    @Test func testSelectWordOrExpressionSelectsWord() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 1))
        let selection = SelectionService(terminal: terminal)
        terminal.feed(text: "hello world")

        selection.selectWordOrExpression(at: Position(col: 1, row: 0), in: terminal.buffer)

        #expect(selection.getSelectedText() == "hello")
    }

    @Test(arguments: ["1.2.3.4", "192.168.100.200", "host.example.org", "file_name-v2.txt"])
    func doubleClickSelectsWholeTokenAtEveryCharacter(token: String) {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 2))
        let selection = SelectionService(terminal: terminal)
        let prefix = "before "
        terminal.feed(text: prefix+token+" after")
        for column in prefix.count..<(prefix.count+token.count) {
            selection.selectWordOrExpression(at: Position(col: column,row: 0),in: terminal.buffer)
            #expect(selection.getSelectedText() == token, "Clicked column \(column)")
            #expect(selection.start.col == prefix.count)
            #expect(selection.end.col == prefix.count+token.count)
        }
    }

    @Test func wordDragExtendsThroughAnAddressSeparator() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 30, rows: 2))
        let selection = SelectionService(terminal: terminal)
        terminal.feed(text: "1.2.3.4 5.6.7.8")
        selection.selectWordOrExpression(at: Position(col: 0,row: 0),in: terminal.buffer)
        selection.dragExtend(bufferPosition: Position(col: 9,row: 0))
        #expect(selection.getSelectedText() == "1.2.3.4 5.6.7.8")
    }

    @Test func testSelectWordOrExpressionSelectsBalancedParens() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 1))
        let selection = SelectionService(terminal: terminal)
        terminal.feed(text: "(abc) def")

        selection.selectWordOrExpression(at: Position(col: 0, row: 0), in: terminal.buffer)
        #expect(selection.getSelectedText() == "(abc)")

        selection.selectWordOrExpression(at: Position(col: 4, row: 0), in: terminal.buffer)
        #expect(selection.getSelectedText() == "(abc)")
    }

#if os(macOS)
    // Test only on macOS due to differences in how frames are handled on mac and iOS
    @Test func testMouseHitCorrectWhenScrolled() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: .init(width: 10, height: 10)))

        for _ in 0..<100 {
            view.terminal.feed (text: "12345")
        }

        // Scroll all the way down, check the bottom-left corner
        view.scrollTo(row: 100)
        #expect(view.calculateMouseHit(at: CGPoint(x: 0, y: 0)).grid.row == 100)

        // Scroll all the way back up, check the top-left corner
        view.scrollTo(row: 1)
        #expect(view.calculateMouseHit(at: CGPoint(x: 0, y: 10)).grid.row == 1)
    }
#endif
}
